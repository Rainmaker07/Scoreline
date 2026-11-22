import Foundation

// MARK: - Models

enum GameState: String {
    case pre, live = "in", post
    var sortRank: Int { self == .live ? 0 : self == .pre ? 1 : 2 }
}

struct Side: Hashable {
    var id: String
    var name: String
    var short: String
    var abbr: String
    var logo: URL?
    var color: String?
    var altColor: String?
    var score: String?
    var winner: Bool?
    var record: String?
    var linescores: [String]
    var isHome: Bool

    var tintHex: String? {
        if let c = color, c.lowercased() != "000000" { return c }
        return altColor
    }
}

struct Scorer: Hashable {
    let teamId: String
    let text: String
}

struct Game: Identifiable, Hashable {
    let id: String
    let leagueId: String
    let date: Date
    var state: GameState
    var statusText: String
    var home: Side
    var away: Side
    var note: String?
    var broadcast: String?
    var scorers: [Scorer]

    var league: League { League.byId(leagueId)! }

    /// European football lists the home side first, US sports the away side.
    var ordered: (left: Side, right: Side) {
        league.family == .soccer ? (home, away) : (away, home)
    }
}

struct StandingRow: Identifiable, Hashable {
    let id: String
    let name: String
    let short: String
    let abbr: String
    let logo: URL?
    let stats: [String: String]
    let noteColor: String?
    let noteText: String?
}

struct StandingGroup: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let rows: [StandingRow]
}

struct LeaderEntry: Hashable {
    let name: String
    var athleteId: String? = nil
    let team: String?
    let teamLogo: URL?
    let headshot: URL?
    let value: String
    let detail: String?
}

struct LeaderCategory: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let label: String
    let leaders: [LeaderEntry]
}

// MARK: - Status

struct StatusInfo {
    let state: GameState
    let text: String
}

func statusInfo(_ st: J, family: Family) -> StatusInfo {
    let type = st["type"]
    let state = GameState(rawValue: type["state"].str) ?? .pre
    switch state {
    case .live:
        if family == .soccer {
            if type["name"].str == "STATUS_HALFTIME" || type["shortDetail"].str == "Halftime" { return StatusInfo(state: state, text: "HT") }
            return StatusInfo(state: state, text: st["displayClock"].string ?? "Live")
        }
        return StatusInfo(state: state, text: type["shortDetail"].string ?? type["detail"].string ?? "Live")
    case .post:
        let d = type["shortDetail"].string ?? "Final"
        return StatusInfo(state: state, text: d == "FT" ? "Final" : d)
    case .pre:
        return StatusInfo(state: state, text: type["shortDetail"].str)
    }
}

// MARK: - Client

enum ESPN {
    static let site = "https://site.api.espn.com/apis/site/v2/sports"
    static let siteV3 = "https://site.api.espn.com/apis/site/v3/sports"
    static let core = "https://site.api.espn.com/apis/v2/sports"

    static func side(_ c: J) -> Side {
        let t = c["team"]
        return Side(
            id: t["id"].string ?? c["id"].str,
            name: t["displayName"].string ?? t["name"].str,
            short: t["shortDisplayName"].string ?? t["name"].string ?? t["displayName"].str,
            abbr: t["abbreviation"].str,
            logo: t["logo"].url ?? t["logos"][0]["href"].url,
            color: t["color"].string,
            altColor: t["alternateColor"].string,
            score: c["score"].string,
            winner: c["winner"].bool,
            record: c["records"][0]["summary"].string ?? c["record"][0]["displayValue"].string ?? c["record"][0]["summary"].string,
            linescores: c["linescores"].array.map { $0["displayValue"].string ?? $0["value"].double.map { String(Int($0)) } ?? "" },
            isHome: c["homeAway"].str == "home"
        )
    }

    static func game(_ e: J, league: League) -> Game {
        let comp = e["competitions"][0]
        let cs = comp["competitors"].array
        let home = side(cs.first { $0["homeAway"].str == "home" } ?? cs.first ?? J(nil))
        let away = side(cs.first { $0["homeAway"].str == "away" } ?? (cs.count > 1 ? cs[1] : J(nil)))
        let st = statusInfo(comp["status"].exists ? comp["status"] : e["status"], family: league.family)
        let scorers: [Scorer] = comp["details"].array.filter { $0["scoringPlay"].bool == true }.map { d in
            var text = d["athletesInvolved"][0]["shortName"].str + " " + d["clock"]["displayValue"].str
            if d["penaltyKick"].bool == true { text += " (P)" }
            if d["ownGoal"].bool == true { text += " (OG)" }
            return Scorer(teamId: d["team"]["id"].str, text: text.trimmingCharacters(in: .whitespaces))
        }
        let broadcast = comp["broadcasts"][0]["names"].array.compactMap { $0.string }.joined(separator: ", ")
        var note = comp["notes"][0]["headline"].string ?? comp["series"]["summary"].string
        let pens = cs.compactMap { $0["shootoutScore"].int }
        if pens.count == 2 {
            let hp = cs.first { $0["homeAway"].str == "home" }?["shootoutScore"].int ?? 0
            let ap = cs.first { $0["homeAway"].str == "away" }?["shootoutScore"].int ?? 0
            let pensText = league.family == .soccer ? "Penalties \(hp)–\(ap)" : "Shootout \(hp)–\(ap)"
            note = [note, pensText].compactMap { $0 }.joined(separator: " · ")
        }
        return Game(
            id: e["id"].str,
            leagueId: league.id,
            date: ESPNDate.parse(e["date"].string) ?? Date(),
            state: st.state,
            statusText: st.text,
            home: home,
            away: away,
            note: note,
            broadcast: broadcast.isEmpty ? comp["broadcast"].string : broadcast,
            scorers: scorers
        )
    }

    static func scoreboard(_ league: League, date: Date) async throws -> [Game] {
        guard let path = league.espn, let url = URL(string: "\(site)/\(path)/scoreboard?dates=\(ESPNDate.ymd(date))") else { return [] }
        let d = try await HTTP.shared.json(url, maxAge: 15)
        return d["events"].array.map { game($0, league: league) }
            .sorted { ($0.state.sortRank, $0.date) < ($1.state.sortRank, $1.date) }
    }

    static func summary(_ league: League, id: String) async throws -> J {
        guard let path = league.espn, let url = URL(string: "\(site)/\(path)/summary?event=\(id)") else { return J(nil) }
        return try await HTTP.shared.json(url, maxAge: 10)
    }

    // MARK: Standings

    private static func collect(_ node: J, into out: inout [StandingGroup]) {
        let entries = node["standings"]["entries"].array
        if !entries.isEmpty {
            let rows = entries.map { en -> StandingRow in
                var stats: [String: String] = [:]
                for s in en["stats"].array {
                    let v = s["displayValue"].str
                    if let n = s["name"].string { stats[n] = v }
                    if let t = s["type"].string { stats[t] = v }
                }
                let t = en["team"]
                return StandingRow(
                    id: t["id"].str,
                    name: t["displayName"].str,
                    short: t["shortDisplayName"].string ?? t["name"].str,
                    abbr: t["abbreviation"].str,
                    logo: t["logos"][0]["href"].url,
                    stats: stats,
                    noteColor: en["note"]["color"].string,
                    noteText: en["note"]["description"].string
                )
            }
            out.append(StandingGroup(name: node["name"].str, rows: rows))
        }
        for c in node["children"].array { collect(c, into: &out) }
    }

    static func standings(_ league: League, divisions: Bool) async throws -> [StandingGroup] {
        guard let path = league.espn, let url = URL(string: "\(core)/\(path)/standings\(divisions ? "?level=3" : "")") else { return [] }
        let d = try await HTTP.shared.json(url, maxAge: 300)
        var out: [StandingGroup] = []
        collect(d, into: &out)
        return out
    }

    // MARK: Leaders

    static func leaders(_ league: League) async throws -> [LeaderCategory] {
        guard let path = league.espn else { return [] }
        if league.family == .soccer {
            guard let url = URL(string: "\(site)/\(path)/statistics") else { return [] }
            let d = try await HTTP.shared.json(url, maxAge: 1800)
            return d["stats"].array.map { s in
                let name = s["name"].str
                return LeaderCategory(
                    name: name,
                    label: s["displayName"].string ?? (name == "goalsLeaders" ? "Goals" : "Assists"),
                    leaders: s["leaders"].array.prefix(20).map { l in
                        let team = l["athlete"]["team"].exists ? l["athlete"]["team"] : l["team"]
                        return LeaderEntry(
                            name: l["athlete"]["displayName"].str,
                            athleteId: l["athlete"]["id"].string,
                            team: team["displayName"].string,
                            teamLogo: team["logos"][0]["href"].url,
                            headshot: nil,
                            value: l["value"].double.map { String(Int($0)) } ?? "",
                            // "Matches: 10, Goals: 9" -> "10 matches" (the number is already on the right)
                            detail: matchesText(l["displayValue"].str)
                        )
                    }
                )
            }
        }
        guard let url = URL(string: "\(siteV3)/\(path)/leaders") else { return [] }
        let d = try await HTTP.shared.json(url, maxAge: 1800)
        return d["leaders"]["categories"].array.compactMap { c in
            let name = c["name"].str
            if skippedLeaderCategories.contains(name) { return nil }
            return LeaderCategory(
                name: name,
                label: c["displayName"].str,
                leaders: c["leaders"].array.map { l in
                    let full = l["displayValue"].str
                    let value = formatLeader(name, value: l["value"].double, display: full)
                    return LeaderEntry(
                        name: l["athlete"]["displayName"].str,
                        athleteId: l["athlete"]["id"].string,
                        team: l["team"]["abbreviation"].string ?? l["athlete"]["team"]["abbreviation"].string,
                        teamLogo: l["team"]["logos"][0]["href"].url,
                        headshot: l["athlete"]["headshot"]["href"].url,
                        value: value,
                        // Baseball's displayValue is the player's full stat line: keep it as context.
                        detail: value == full ? nil : full
                    )
                }
            )
        }
    }

    static func matchesText(_ s: String) -> String? {
        guard let r = s.range(of: #"Matches:\s*(\d+)"#, options: .regularExpression) else { return nil }
        let n = s[r].filter(\.isNumber)
        return n == "1" ? "1 match" : "\(n) matches"
    }

    /// Categories ESPN fills with low-sample outliers.
    static let skippedLeaderCategories: Set<String> = ["opponentAvg"]

    /// Formats a leader's value the way the sport writes it.
    static func formatLeader(_ category: String, value: Double?, display: String) -> String {
        guard let v = value else { return display }
        let c = category.lowercased()
        let threeDecimal: Set<String> = ["avg", "ops", "onbasepct", "slugavg", "opponentavg"]
        let twoDecimal: Set<String> = ["era", "whip"]
        if threeDecimal.contains(c) {
            let s = String(format: "%.3f", v)
            return s.hasPrefix("0") ? String(s.dropFirst()) : s
        }
        if twoDecimal.contains(c) { return String(format: "%.2f", v) }
        if c.contains("pct") || c.contains("percentage") {
            return String(format: "%.1f", v <= 1 ? v * 100 : v)
        }
        if c.contains("pergame") || c.hasPrefix("avg") || c == "per" || c.contains("rating") || c.contains("war") || c.contains("score") {
            return String(format: "%.1f", v)
        }
        if v.rounded() == v { return String(Int(v)) }
        return String(format: "%.1f", v)
    }
}

// MARK: - Tennis

struct Slam: Identifiable, Hashable {
    let id: String
    let name: String
    let short: String
    let surface: String
    let color: String
    let month: Int
    let day: Int

    func probe(_ year: Int) -> String { String(format: "%04d%02d%02d", year, month, day) }

    static let all: [Slam] = [
        Slam(id: "ao", name: "Australian Open", short: "AO", surface: "Hard", color: "1e8fd5", month: 1, day: 25),
        Slam(id: "rg", name: "Roland Garros", short: "RG", surface: "Clay", color: "c4572c", month: 6, day: 1),
        Slam(id: "wim", name: "Wimbledon", short: "WIM", surface: "Grass", color: "3d7a3a", month: 7, day: 5),
        Slam(id: "uso", name: "US Open", short: "USO", surface: "Hard", color: "2a4fa3", month: 9, day: 7),
    ]

    /// "Live: Wimbledon", "Next: Australian Open · Jan" for the league menu.
    static func statusLine(_ now: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.month, .day], from: now)
        let key = (c.month ?? 1) * 100 + (c.day ?? 1)
        for s in all {
            let mid = s.month * 100 + s.day
            if key >= mid - 7 && key <= mid + 8 { return "Live: \(s.name)" }
        }
        let next = all.first { $0.month * 100 + $0.day > key } ?? all[0]
        return "Next: \(next.name)"
    }

    /// Most recent slam that has started this year.
    static func current(_ now: Date = Date()) -> Slam {
        let c = Calendar.current.dateComponents([.month, .day], from: now)
        let key = (c.month ?? 1) * 100 + (c.day ?? 1)
        return all.last { $0.month * 100 + $0.day - 14 <= key } ?? all[0]
    }
}

struct SetScore: Hashable {
    let games: Int
    let tiebreak: Int?
    let won: Bool?
}

struct TennisPlayer: Hashable {
    let id: String
    let name: String
    let flag: URL?
    let country: String?
    let seed: Int?
    let winner: Bool?
    let sets: [SetScore]
}

struct TennisMatch: Identifiable, Hashable {
    let id: String
    let round: String
    let date: Date
    let state: GameState
    let status: String
    let court: String?
    let players: [TennisPlayer]
}

struct TennisEvent: Hashable {
    let name: String
    let start: Date?
    let end: Date?
    let venue: String?
    let champion: String?
    let matches: [TennisMatch]
}

extension ESPN {
    static let roundOrder = ["Round 1", "Round 2", "Round 3", "Round 4", "Quarterfinal", "Semifinal", "Final"]

    private static func player(_ c: J) -> TennisPlayer {
        let a = c["athlete"].exists ? c["athlete"] : c["roster"]
        let rank = c["curatedRank"]["current"].int
        return TennisPlayer(
            id: c["id"].str,
            name: a["displayName"].string ?? "TBD",
            flag: a["flag"]["href"].url ?? a["athletes"][0]["flag"]["href"].url,
            country: a["flag"]["alt"].string,
            seed: (rank ?? 99) < 99 ? rank : nil,
            winner: c["winner"].bool,
            sets: c["linescores"].array.map { SetScore(games: $0["value"].int ?? 0, tiebreak: $0["tiebreak"].int, won: $0["winner"].bool) }
        )
    }

    static func slam(_ slam: Slam, year: Int, grouping: String) async throws -> TennisEvent? {
        guard let url = URL(string: "\(site)/tennis/atp/scoreboard?dates=\(slam.probe(year))") else { return nil }
        let isPast = year < Calendar.current.component(.year, from: Date())
        let d = try await HTTP.shared.json(url, maxAge: isPast ? 86_400 * 30 : 60)
        let first = slam.name.split(separator: " ").first.map(String.init)?.lowercased() ?? ""
        let events = d["events"].array
        guard let ev = events.first(where: { $0["major"].bool == true && $0["name"].str.lowercased().contains(first) })
            ?? events.first(where: { $0["major"].bool == true }) else { return nil }
        return tennisEvent(ev, grouping: grouping)
    }

    /// Builds a draw from one ESPN tennis event (any tournament).
    static func tennisEvent(_ ev: J, grouping: String) -> TennisEvent {
        let g = ev["groupings"].array.first { $0["grouping"]["slug"].str == grouping }
        let matches: [TennisMatch] = (g?["competitions"].array ?? []).compactMap { c in
            let round = c["round"]["displayName"].str
            if round.hasPrefix("Qualifying") { return nil }
            let ordered = c["competitors"].array.sorted { ($0["order"].int ?? 0) < ($1["order"].int ?? 0) }
            guard ordered.count == 2 else { return nil }
            let st = statusInfo(c["status"], family: .tennis)
            return TennisMatch(
                id: c["id"].str,
                round: round,
                date: ESPNDate.parse(c["date"].string) ?? Date(),
                state: st.state,
                status: st.text,
                court: c["venue"]["court"].string,
                players: ordered.map(player)
            )
        }
        let champion = matches.first { $0.round == "Final" && $0.state == .post }?.players.first { $0.winner == true }?.name
        return TennisEvent(
            name: ev["name"].str,
            start: ESPNDate.parse(ev["date"].string),
            end: ESPNDate.parse(ev["endDate"].string),
            venue: ev["venue"]["fullName"].string ?? ev["venue"]["displayName"].string,
            champion: champion,
            matches: matches
        )
    }
}
