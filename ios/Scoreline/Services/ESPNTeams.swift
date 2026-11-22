import Foundation

// MARK: - Models

struct RosterPlayer: Identifiable, Hashable {
    let id: String
    let name: String
    let jersey: String?
    let position: String?
    let age: Int?
    let height: String?
    let headshot: URL?
    let group: String?
    var statLine: String? = nil
}

struct InfoRow: Hashable {
    let label: String
    let value: String
}

struct StatTable: Hashable {
    let title: String
    let labels: [String]
    let rows: [(name: String, values: [String])]

    static func == (a: StatTable, b: StatTable) -> Bool { a.title == b.title && a.labels == b.labels && a.rows.map(\.name) == b.rows.map(\.name) }
    func hash(into h: inout Hasher) { h.combine(title); h.combine(labels) }
}

struct GameLogEntry: Identifiable, Hashable {
    let id: String
    let date: Date?
    let opponent: String
    let opponentLogo: URL?
    let atVs: String
    let result: String
    let score: String
    let stats: [String]
}

struct TeamPage {
    let league: League
    let id: String
    let name: String
    let abbr: String
    let logo: URL?
    let color: String?
    let record: String?
    let standing: String?
    var games: [Game]
    var roster: [RosterPlayer]
    var stats: [InfoRow]
    var injuries: [InfoRow]
    var form: [String]
}

struct PlayerPage {
    let league: League
    let id: String
    let name: String
    let headshot: URL?
    let team: String?
    let teamId: String?
    let teamLogo: URL?
    let bio: [InfoRow]
    let seasonStats: [InfoRow]
    let tables: [StatTable]
    let gameLogLabels: [String]
    let gameLog: [GameLogEntry]
}

// MARK: - ESPN teams / athletes

extension ESPN {
    static let common = "https://site.web.api.espn.com/apis/common/v3/sports"

    /// Games across a date range (used for "Upcoming").
    static func scoreboard(_ league: League, from: Date, to: Date) async throws -> [Game] {
        guard let path = league.espn,
              let url = URL(string: "\(site)/\(path)/scoreboard?dates=\(ESPNDate.ymd(from))-\(ESPNDate.ymd(to))&limit=300") else { return [] }
        let d = try await HTTP.shared.json(url, maxAge: 120)
        return d["events"].array.map { game($0, league: league) }.sorted { $0.date < $1.date }
    }

    /// "Off Season", "Live", "Regular Season" … for the league menu.
    static func status(_ league: League) async -> String? {
        guard let path = league.espn, let url = URL(string: "\(site)/\(path)/scoreboard") else { return nil }
        guard let d = try? await HTTP.shared.json(url, maxAge: 300) else { return nil }
        let events = d["events"].array
        let live = events.filter { $0["status"]["type"]["state"].str == "in" }.count
        if live > 0 { return "\(live) live" }
        let dates = events.compactMap { ESPNDate.parse($0["date"].string) }
        if let last = dates.max(), Date().timeIntervalSince(last) > 86_400 * 10 { return "Off Season" }
        if let next = dates.filter({ $0 > Date() }).min() {
            if Calendar.current.isDateInToday(next) { return "Today \(Fmt.time(next))" }
            return "Next: \(Fmt.day(next))"
        }
        return d["leagues"][0]["season"]["type"]["name"].string
    }

    // MARK: Team

    static func team(_ league: League, id: String) async throws -> TeamPage {
        guard let path = league.espn else { throw FetchError.parse("No ESPN path") }
        let base = "\(site)/\(path)/teams/\(id)"
        async let infoJ = HTTP.shared.json(URL(string: base)!, maxAge: 600)
        async let schedJ = HTTP.shared.json(URL(string: "\(base)/schedule")!, maxAge: 300)
        async let rosterJ = HTTP.shared.json(URL(string: "\(base)/roster")!, maxAge: 3600)
        let info = (try await infoJ)["team"]
        var events = (try? await schedJ)?["events"].array ?? []
        if league.family == .soccer, let fx = URL(string: "\(base)/schedule?fixture=true"),
           let more = try? await HTTP.shared.json(fx, maxAge: 300) {
            events += more["events"].array
        }
        let roster = (try? await rosterJ) ?? J(nil)

        var games = events.map { scheduleGame($0, league: league) }
        var seen = Set<String>()
        games = games.filter { seen.insert($0.id).inserted }.sorted { $0.date < $1.date }

        var players: [RosterPlayer] = []
        var injuries: [InfoRow] = []
        for a in roster["athletes"].array {
            if a["items"].exists {
                for p in a["items"].array { players.append(rosterPlayer(p, group: a["position"].string)) }
            } else {
                players.append(rosterPlayer(a, group: nil))
            }
        }
        for a in roster["athletes"].array.flatMap({ $0["items"].exists ? $0["items"].array : [$0] }) {
            if let inj = a["injuries"].array.first, inj.exists {
                injuries.append(InfoRow(label: a["displayName"].str, value: inj["status"].string ?? inj["type"]["description"].str))
            }
        }

        let recordItem = info["record"]["items"][0]
        var stats: [InfoRow] = []
        let wanted: [(String, String)] = league.family == .soccer
            ? [("gamesPlayed", "Played"), ("wins", "Wins"), ("ties", "Draws"), ("losses", "Losses"), ("pointsFor", "Goals for"),
               ("pointsAgainst", "Goals against"), ("pointDifferential", "Goal difference"), ("points", "Points")]
            : [("avgPointsFor", league.family == .baseball ? "Runs per game" : "Points per game"),
               ("avgPointsAgainst", league.family == .baseball ? "Runs allowed per game" : "Opp. points per game"),
               ("differential", "Differential"), ("streak", "Streak"), ("divisionWinPercent", "Division win %"),
               ("leagueWinPercent", "League win %")]
        let map = Dictionary(recordItem["stats"].array.map { ($0["name"].str, $0) }, uniquingKeysWith: { a, _ in a })
        for (k, label) in wanted {
            if let s = map[k], let v = s["value"].double {
                let text: String
                if k.lowercased().contains("percent") { text = String(format: "%.3f", v) }
                else if k == "streak" { text = v > 0 ? "W\(Int(v))" : "L\(Int(-v))" }
                else if v.rounded() == v { text = String(Int(v)) }
                else { text = String(format: "%.1f", v) }
                stats.append(InfoRow(label: label, value: text))
            }
        }
        for item in info["record"]["items"].array.dropFirst() {
            if let s = item["summary"].string { stats.append(InfoRow(label: item["description"].string ?? item["type"].str.capitalized, value: s)) }
        }

        let finished = games.filter { $0.state == .post }
        let form = finished.suffix(5).map { g -> String in
            let me = g.home.id == id ? g.home : g.away
            let other = g.home.id == id ? g.away : g.home
            let a = Double(me.score ?? "") ?? 0, b = Double(other.score ?? "") ?? 0
            return a > b ? "W" : a < b ? "L" : "D"
        }

        return TeamPage(
            league: league, id: id,
            name: info["displayName"].str,
            abbr: info["abbreviation"].str,
            logo: info["logos"][0]["href"].url,
            color: info["color"].string,
            record: recordItem["summary"].string,
            standing: info["standingSummary"].string,
            games: games, roster: players, stats: stats, injuries: injuries, form: form
        )
    }

    private static func rosterPlayer(_ p: J, group: String?) -> RosterPlayer {
        RosterPlayer(
            id: p["id"].str,
            name: p["displayName"].str,
            jersey: p["jersey"].string,
            position: p["position"]["abbreviation"].string,
            age: p["age"].int,
            height: p["displayHeight"].string,
            headshot: p["headshot"]["href"].url,
            group: group
        )
    }

    /// Team schedule events have scores as objects instead of strings.
    private static func scheduleGame(_ e: J, league: League) -> Game {
        var g = game(e, league: league)
        let cs = e["competitions"][0]["competitors"].array
        for c in cs {
            let score = c["score"]["displayValue"].string ?? c["score"].string
            if c["homeAway"].str == "home" { g.home.score = score } else { g.away.score = score }
            if c["homeAway"].str == "home" { g.home.winner = c["winner"].bool } else { g.away.winner = c["winner"].bool }
        }
        return g
    }

    // MARK: Player

    static func sportPath(_ league: League) -> String? { league.espn }

    static func player(_ league: League, id: String) async throws -> PlayerPage {
        guard let path = league.espn else { throw FetchError.parse("No ESPN path") }
        let base = "\(common)/\(path)/athletes/\(id)"
        async let mainJ = HTTP.shared.json(URL(string: base)!, maxAge: 3600)
        async let overviewJ = HTTP.shared.json(URL(string: "\(base)/overview")!, maxAge: 600)
        async let logJ = HTTP.shared.json(URL(string: "\(base)/gamelog")!, maxAge: 600)
        async let statsJ = HTTP.shared.json(URL(string: "\(base)/stats")!, maxAge: 3600)

        let a = (try await mainJ)["athlete"]
        let ov = (try? await overviewJ) ?? J(nil)
        let log = (try? await logJ) ?? J(nil)
        let st = (try? await statsJ) ?? J(nil)

        var bio: [InfoRow] = []
        func add(_ label: String, _ v: String?) { if let v, !v.isEmpty { bio.append(InfoRow(label: label, value: v)) } }
        add("Position", a["position"]["displayName"].string)
        add("Number", a["displayJersey"].string)
        add("Age", a["age"].int.map(String.init))
        add("Born", [a["displayDOB"].string, a["displayBirthPlace"].string].compactMap { $0 }.joined(separator: " · "))
        add("Height / Weight", [a["displayHeight"].string, a["displayWeight"].string].compactMap { $0 }.joined(separator: " · "))
        add("Nationality", a["citizenship"].string)
        add("Experience", a["displayExperience"].string)
        add("Draft", a["displayDraft"].string)
        add("College", a["college"]["name"].string)

        var season: [InfoRow] = a["statsSummary"]["statistics"].array.map { s in
            let rank = s["rankDisplayValue"].string.map { " (\($0))" } ?? ""
            return InfoRow(label: s["displayName"].str, value: s["displayValue"].str + rank)
        }

        var tables: [StatTable] = []
        let ovs = ov["statistics"]
        if !ovs["labels"].array.isEmpty {
            tables.append(StatTable(
                title: ovs["displayName"].string ?? "Stats",
                labels: ovs["labels"].array.map(\.str),
                rows: ovs["splits"].array.map { ($0["displayName"].str, $0["stats"].array.map(\.str)) }
            ))
            if season.isEmpty, let first = ovs["splits"].array.first {
                let labels = ovs["displayNames"].array.map(\.str)
                season = zip(labels, first["stats"].array.map(\.str)).map { InfoRow(label: $0, value: $1) }
            }
        }
        for c in st["categories"].array.prefix(3) {
            let rows = c["statistics"].array.suffix(8).reversed().map { s in
                (s["season"]["displayName"].str + (s["teamSlug"].string.map { " " + $0.uppercased() } ?? ""), s["stats"].array.map(\.str))
            }
            if !rows.isEmpty {
                tables.append(StatTable(title: "Career · " + c["displayName"].str, labels: c["labels"].array.map(\.str), rows: rows))
            }
        }

        // Game log: newest first, last 10 games
        var entries: [GameLogEntry] = []
        for cat in log["seasonTypes"][0]["categories"].array {
            for ev in cat["events"].array {
                let id = ev["eventId"].str
                let e = log["events"][id]
                entries.append(GameLogEntry(
                    id: id,
                    date: ESPNDate.parse(e["gameDate"].string?.replacingOccurrences(of: ".000+00:00", with: "Z")),
                    opponent: e["opponent"]["abbreviation"].str,
                    opponentLogo: e["opponent"]["logo"].url,
                    atVs: e["atVs"].str,
                    result: e["gameResult"].str,
                    score: e["score"].str,
                    stats: ev["stats"].array.map(\.str)
                ))
            }
        }
        entries.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }

        return PlayerPage(
            league: league, id: id,
            name: a["displayName"].str,
            headshot: a["headshot"]["href"].url,
            team: a["team"]["displayName"].string,
            teamId: a["team"]["id"].string,
            teamLogo: a["team"]["logos"][0]["href"].url,
            bio: bio,
            seasonStats: season,
            tables: tables,
            gameLogLabels: log["labels"].array.map(\.str),
            gameLog: Array(entries.prefix(10))
        )
    }

    // MARK: Search

    struct SearchHit: Identifiable, Hashable {
        let id: String
        let kind: String   // "player" / "team"
        let name: String
        let subtitle: String
        let leagueId: String
        let entityId: String
        let image: URL?
    }

    /// ESPN league ids that appear in search result uids (s:..~l:<id>~a:<id>).
    private static let uidLeague: [String: String] = [
        "46": "nba", "10": "mlb", "700": "epl", "720": "bl1", "3907": "bl2", "775": "ucl",
    ]

    static func search(_ q: String) async -> [SearchHit] {
        guard let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://site.web.api.espn.com/apis/search/v2?query=\(enc)&limit=10"),
              let d = try? await HTTP.shared.json(url, maxAge: 300) else { return [] }
        var hits: [SearchHit] = []
        for r in d["results"].array where ["player", "team"].contains(r["type"].str) {
            for c in r["contents"].array {
                let uid = c["uid"].str
                let parts = Dictionary(uid.split(separator: "~").compactMap { p -> (String, String)? in
                    let kv = p.split(separator: ":", maxSplits: 1)
                    return kv.count == 2 ? (String(kv[0]), String(kv[1])) : nil
                }, uniquingKeysWith: { a, _ in a })
                let subtitle = c["subtitle"].str
                var leagueId: String?
                if let l = parts["l"] { leagueId = uidLeague[l] }
                if leagueId == nil, parts["s"] == "600" {
                    // Football uids carry no league: use the subtitle for teams, any
                    // football league for players (athlete endpoints are league-agnostic).
                    let sub = subtitle.lowercased()
                    if parts["t"] != nil {
                        if sub.contains("2. bundesliga") { leagueId = "bl2" }
                        else if sub.contains("bundesliga") { leagueId = "bl1" }
                        else if sub == "premier league" || sub == "english premier league" { leagueId = "epl" }
                    } else {
                        leagueId = "epl"
                    }
                }
                guard let leagueId else { continue }
                let entity = parts["a"] ?? parts["t"] ?? ""
                hits.append(SearchHit(
                    id: uid, kind: r["type"].str, name: c["displayName"].str,
                    subtitle: subtitle.isEmpty ? (League.byId(leagueId)?.name ?? "") : subtitle,
                    leagueId: leagueId, entityId: entity,
                    image: c["image"]["default"].url ?? c["image"]["defaultDark"].url
                ))
            }
        }
        return hits
    }
}
