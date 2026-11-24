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
    /// Optional team logo per row (career tables).
    var rowLogos: [URL?] = []

    static func == (a: StatTable, b: StatTable) -> Bool { a.title == b.title && a.labels == b.labels && a.rows.map(\.name) == b.rows.map(\.name) }
    func hash(into h: inout Hasher) { h.combine(title); h.combine(labels) }
}

struct GameLogEntry: Identifiable, Hashable {
    let id: String
    var league: String = ""
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
    /// Competitions the team plays in (football: league, cups, Europe).
    var competitions: [League] = []
    /// Full team statistics (MLB: hitting/pitching/fielding, NBA: general/offense/defense).
    var statSections: [(title: String, rows: [InfoRow])] = []
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
    /// Per-competition season stats (football: league / cup / Europe).
    var competitionStats: [(name: String, rows: [InfoRow])] = []
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
        if let next = dates.filter({ $0 > Date() }).min() {
            if Calendar.current.isDateInToday(next) { return "Today \(Fmt.time(next))" }
            return "Next: \(Fmt.day(next))"
        }
        if !events.isEmpty, dates.contains(where: { Calendar.current.isDateInToday($0) }) { return "Today · Final" }
        // ESPN's calendar lists every match day ("2026-11-28T07:00Z" = that US day).
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let today = Calendar.current.startOfDay(for: Date())
        let days = d["leagues"][0]["calendar"].array.compactMap { $0.string.flatMap { f.date(from: String($0.prefix(10))) } }
        if let next = days.filter({ $0 > today }).min() { return "Next: \(Fmt.dayOnly(next))" }
        if let last = days.max(), last < today.addingTimeInterval(-86_400 * 10) { return "Off Season" }
        if let last = dates.max(), Date().timeIntervalSince(last) > 86_400 * 10 { return "Off Season" }
        return nil
    }

    // MARK: Cups

    struct CupRound: Identifiable, Hashable {
        var id: String { label }
        let label: String
        let detail: String
        let start: Date
        let end: Date
    }

    static func cupRounds(_ league: League) async throws -> [CupRound] {
        guard let path = league.espn, let url = URL(string: "\(site)/\(path)/scoreboard") else { return [] }
        let d = try await HTTP.shared.json(url, maxAge: 3600)
        return d["leagues"][0]["calendar"].array.flatMap { $0["entries"].array }.compactMap { e in
            guard let s = ESPNDate.parse(e["startDate"].string), let en = ESPNDate.parse(e["endDate"].string) else { return nil }
            return CupRound(label: e["label"].str.replacingOccurrences(of: "Rd of", with: "Round of"),
                            detail: e["detail"].str, start: s, end: en)
        }
    }

    /// Games in a cup round (fetched day by day; ESPN refuses ranges).
    /// ESPN's round windows are broad (e.g. 4 Sep – 30 Oct for games on 27–28 Oct),
    /// so use the round's short label ("Oct 27-28", "Aug 21-Sep 2") for the real days.
    static func cupGames(_ league: League, round: CupRound) async throws -> [Game] {
        let cal = Calendar.current
        var days = matchDays(round)
        if days.isEmpty {
            var d = cal.startOfDay(for: round.start)
            while d <= round.end { days.append(d); d = cal.date(byAdding: .day, value: 1, to: d)! }
        }
        // ESPN dates are US-based: include the day before each match day too.
        let withPrev = Set(days.flatMap { [$0, cal.date(byAdding: .day, value: -1, to: $0)!] })
        let games = try await GameFeed.days(league, Array(withPrev))
        return games.filter { g in days.contains { cal.isDate($0, inSameDayAs: g.date) } || days.isEmpty }
    }

    /// "Oct 27-28" / "Aug 21-Sep 2" / "Dec 4-Feb 11" -> each day in that span.
    static func matchDays(_ round: CupRound) -> [Date] {
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d yyyy"
        let parts = round.detail.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return [] }
        let startYear = cal.component(.year, from: round.start.addingTimeInterval(86_400))
        guard let first = f.date(from: "\(parts[0]) \(startYear)") else { return [] }
        let month = parts[0].split(separator: " ").first.map(String.init) ?? ""
        let secondText = parts[1].contains(" ") ? parts[1] : "\(month) \(parts[1])"
        guard var last = f.date(from: "\(secondText) \(startYear)") else { return [] }
        if last < first { last = cal.date(byAdding: .year, value: 1, to: last)! }
        // Long spans (e.g. "Dec 4-Feb 11") are scheduling windows: cap at 70 days.
        var out: [Date] = []
        var d = first
        while d <= last && out.count < 70 { out.append(d); d = cal.date(byAdding: .day, value: 1, to: d)! }
        return out
    }

    /// NBA Cup season label: the Cup runs Oct–Dec.
    static func nbaCupYear(_ now: Date = Date()) -> Int {
        let c = Calendar.current.dateComponents([.year, .month], from: now)
        return (c.month ?? 1) >= 9 ? (c.year ?? 2026) : (c.year ?? 2026) - 1
    }

    // MARK: Team

    /// Every game of a season, from the league's match-day calendar (rugby has no team schedules on ESPN).
    static func seasonGames(_ league: League) async throws -> [Game] {
        guard let path = league.espn, let url = URL(string: "\(site)/\(path)/scoreboard") else { return [] }
        let d = try await HTTP.shared.json(url, maxAge: 3600)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let days = d["leagues"][0]["calendar"].array.compactMap { $0.string.flatMap { f.date(from: String($0.prefix(10))) } }
        return try await GameFeed.days(league, days)
    }

    static func team(_ league: League, id: String) async throws -> TeamPage {
        guard let path = league.espn else { throw FetchError.parse("No ESPN path") }
        if league.family == .rugby {
            let groups = try await standings(league, divisions: false)
            let row = groups.flatMap(\.rows).first { $0.id == id }
            let games = try await seasonGames(league).filter { $0.home.id == id || $0.away.id == id }
            let form = games.filter { $0.state == .post }.suffix(5).map { g -> String in
                let me = g.home.id == id ? g.home : g.away, them = g.home.id == id ? g.away : g.home
                let a = Int(me.score ?? "") ?? 0, b = Int(them.score ?? "") ?? 0
                return a > b ? "W" : a < b ? "L" : "D"
            }
            let s = row?.stats ?? [:]
            let stats = [("Played", "gamesPlayed"), ("Won", "gamesWon"), ("Drawn", "gamesDrawn"), ("Lost", "gamesLost"),
                         ("Points for", "pointsFor"), ("Points against", "pointsAgainst"), ("Tries for", "triesFor"),
                         ("Bonus points", "bonusPoints"), ("League points", "points")]
                .compactMap { pair in s[pair.1].map { InfoRow(label: pair.0, value: $0) } }
            let squad = await RugbySquad.load(teamName: row?.name ?? "")
            return TeamPage(league: league, id: id, name: row?.name ?? "", abbr: row?.abbr ?? "", logo: row?.logo,
                            color: nil, record: s["overall"].map { _ in "\(s["gamesWon"] ?? "0")-\(s["gamesDrawn"] ?? "0")-\(s["gamesLost"] ?? "0")" },
                            standing: s["rank"].map { "\(BBL.ordinal(Int($0) ?? 0)) in Premiership Rugby" },
                            games: games, roster: squad, stats: stats, injuries: [], form: form)
        }
        let base = "\(site)/\(path)/teams/\(id)"
        async let infoJ = HTTP.shared.json(URL(string: base)!, maxAge: 600)
        async let schedJ = HTTP.shared.json(URL(string: "\(base)/schedule")!, maxAge: 300)
        async let rosterJ = HTTP.shared.json(URL(string: "\(base)/roster")!, maxAge: 3600)
        // Regular season explicitly: in the off-season ESPN's default is the postseason.
        async let teamStatsJ = HTTP.shared.json(URL(string: "\(base)/statistics?seasontype=2")!, maxAge: 3600)
        let info = (try await infoJ)["team"]
        let events = (try? await schedJ)?["events"].array ?? []
        let roster = (try? await rosterJ) ?? J(nil)

        var games = events.map { scheduleGame($0, league: league) }
        var competitions: [League] = [league]
        if league.family == .soccer {
            // The club's other competitions: domestic cup and European cups.
            let country = league.espn?.contains("ger.") == true ? "ger" : league.espn?.contains("eng.") == true ? "eng" : ""
            let candidates = League.all.filter { other in
                guard other.family == .soccer, other.id != league.id, let p = other.espn else { return false }
                return p.contains("uefa") || (!country.isEmpty && p.contains("\(country)."))
                    && !(other.id == "bl1" || other.id == "bl2" || other.id == "epl")
            }
            let found = await withTaskGroup(of: (League, [J]).self) { group -> [(League, [J])] in
                for c in candidates {
                    group.addTask {
                        guard let p = c.espn else { return (c, []) }
                        var evs: [J] = []
                        for suffix in ["", "?fixture=true"] {
                            if let u = URL(string: "\(site)/\(p)/teams/\(id)/schedule\(suffix)"),
                               let j = try? await HTTP.shared.json(u, maxAge: 300) { evs += j["events"].array }
                        }
                        return (c, evs)
                    }
                }
                var out: [(League, [J])] = []
                for await r in group { out.append(r) }
                return out
            }
            if let fx = URL(string: "\(base)/schedule?fixture=true"), let more = try? await HTTP.shared.json(fx, maxAge: 300) {
                games += more["events"].array.map { scheduleGame($0, league: league) }
            }
            for (c, evs) in found where !evs.isEmpty {
                competitions.append(c)
                games += evs.map { scheduleGame($0, league: c) }
            }
            competitions.sort { a, b in
                (League.all.firstIndex(of: a) ?? 0) < (League.all.firstIndex(of: b) ?? 0)
            }
        }
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

        var sections: [(title: String, rows: [InfoRow])] = []
        if league.family != .soccer, let ts = try? await teamStatsJ {
            let titles = ["batting": "Hitting", "pitching": "Pitching", "fielding": "Fielding",
                          "general": "General", "offensive": "Offense", "defensive": "Defense"]
            for c in ts["results"]["stats"]["categories"].array {
                let rows = c["stats"].array.compactMap { s -> InfoRow? in
                    guard let v = s["displayValue"].string, !v.isEmpty, s["name"].str != "teamGamesPlayed" else { return nil }
                    let rank = s["rankDisplayValue"].string.map { " (\($0))" } ?? ""
                    return InfoRow(label: s["displayName"].string ?? s["name"].str, value: v + rank)
                }
                if !rows.isEmpty {
                    sections.append((titles[c["name"].str] ?? c["displayName"].str, rows))
                }
            }
        }

        var page = TeamPage(
            league: league, id: id,
            name: info["displayName"].str,
            abbr: info["abbreviation"].str,
            logo: info["logos"][0]["href"].url,
            color: info["color"].string,
            record: recordItem["summary"].string,
            standing: info["standingSummary"].string.map(cleanCompetitionName),
            games: games, roster: players, stats: stats, injuries: injuries, form: form,
            competitions: competitions
        )
        page.statSections = sections
        return page
    }

    private static func rosterPlayer(_ p: J, group: String?) -> RosterPlayer {
        RosterPlayer(
            id: p["id"].str,
            name: p["displayName"].str,
            jersey: p["jersey"].string,
            position: p["position"]["abbreviation"].string,
            age: p["age"].int,
            height: Units.height(p["displayHeight"].string),
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
        add("Born", [Units.birthDate(a["displayDOB"].string), a["displayBirthPlace"].string].compactMap { $0 }.joined(separator: " · "))
        add("Height / Weight", [Units.height(a["displayHeight"].string), Units.weight(a["displayWeight"].string)].compactMap { $0 }.joined(separator: " · "))
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
        let statNames = ovs["displayNames"].array.map(\.str)
        let competitionStats: [(name: String, rows: [InfoRow])] = ovs["splits"].array.map { sp in
            (sp["displayName"].str, zip(statNames, sp["stats"].array.map(\.str)).map { InfoRow(label: $0, value: $1) })
        }
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
        // Career: "2026-27 · OKC" with the team logo; a season split between teams gets a "Total" row.
        // NBA: averages only (totals and misc totals are left out).
        let teamsBySlug = st["teams"]
        let careerCats = st["categories"].array.filter { league.id != "nba" || $0["name"].str == "averages" || $0["name"].str.contains("postseasonAverages") }
        for c in careerCats.prefix(3) {
            let lines = Array(c["statistics"].array.suffix(8).reversed())
            var rows: [(name: String, values: [String])] = []
            var logos: [URL?] = []
            for s in lines {
                let season = s["season"]["displayName"].str
                let team = teamsBySlug[s["teamSlug"].str]
                let abbr = team["abbreviation"].string
                    ?? (s["teamSlug"].string.map { _ in "Total" } ?? "")
                rows.append((abbr.isEmpty ? season : "\(season) · \(abbr)", s["stats"].array.map(\.str)))
                logos.append(team["logos"].array.first { $0["rel"].array.contains { $0.str == "dark" } }?["href"].url
                             ?? team["logos"][0]["href"].url)
            }
            if !rows.isEmpty {
                tables.append(StatTable(title: "Career · " + c["displayName"].str, labels: c["labels"].array.map(\.str),
                                        rows: rows, rowLogos: logos))
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
                    league: e["leagueName"].string ?? e["leagueShortName"].str,
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
            gameLog: Array(entries.prefix(20)),
            competitionStats: competitionStats
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
        "776": "uel", "20296": "uecl", "3954": "dfb", "40": "fac",
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
