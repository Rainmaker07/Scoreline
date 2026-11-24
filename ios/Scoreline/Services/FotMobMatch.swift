import Foundation

/// Football match data from FotMob that ESPN doesn't have: expected goals, detailed
/// stats, shot map, momentum, player ratings and head-to-head.
/// The FotMob match is found by date and team names.
enum FotMobMatch {
    struct Shot: Hashable {
        let x: Double          // 0...105, towards the goal the team attacks
        let y: Double          // 0...68
        let xg: Double
        let isGoal: Bool
        let onTarget: Bool
        let home: Bool
        let player: String
        let minute: Int
    }

    struct Rating: Hashable {
        let name: String
        let rating: Double
        let home: Bool
        let position: String?
    }

    struct StatRow: Hashable {
        let title: String
        let home: String
        let away: String
        let homeValue: Double?
        let awayValue: Double?
    }

    struct Data {
        let matchId: Int
        let homeName: String
        let awayName: String
        let xg: (home: Double, away: Double)?
        let groups: [(title: String, rows: [StatRow])]
        let shots: [Shot]
        /// Minute -> pressure (-100 away ... +100 home).
        let momentum: [(minute: Double, value: Double)]
        let ratings: [Rating]
        let playerOfTheMatch: String?
        /// Head-to-head: home wins, draws, away wins, and recent meetings.
        let h2h: (home: Int, draws: Int, away: Int)?
        let h2hMatches: [(date: Date?, home: String, away: String, score: String, competition: String)]
    }

    private static func normalize(_ s: String) -> [String] {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en"))
            .replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: ".", with: " ")
        let skip: Set<String> = ["fc", "afc", "cf", "sc", "the", "club", "de", "1", "sv", "vfl", "vfb", "tsg", "bv", "ac", "as", "rb"]
        return folded.split(separator: " ").map(String.init).filter { $0.count > 1 && !skip.contains($0) }
    }

    /// True if two club names share a meaningful word ("Man City" / "Manchester City" via the alias list).
    static func sameTeam(_ a: String, _ b: String) -> Bool {
        let aliases: [String: String] = ["man": "manchester", "utd": "united", "spurs": "tottenham", "wolves": "wolverhampton",
                                         "gladbach": "monchengladbach", "leverkusen": "leverkusen", "bayern": "bayern",
                                         "inter": "internazionale", "psg": "paris", "nott'm": "nottingham", "forest": "nottingham"]
        func words(_ s: String) -> Set<String> { Set(normalize(s).map { aliases[$0] ?? $0 }) }
        let wa = words(a), wb = words(b)
        if wa.isEmpty || wb.isEmpty { return false }
        // "Manchester City" vs "Manchester United" share "manchester": require the distinctive word too.
        let generic: Set<String> = ["manchester", "united", "city", "real", "athletic", "sporting", "borussia", "eintracht"]
        let shared = wa.intersection(wb)
        return !shared.subtracting(generic).isEmpty || (!shared.isEmpty && wa == wb)
    }

    private static var idCache: [String: Int] = [:]

    static func matchId(for game: Game) async -> Int? {
        if let hit = idCache[game.id] { return hit }
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.timeZone = TimeZone(identifier: "Europe/Berlin")
        for d in [game.date, game.date.addingTimeInterval(-86_400)] {
            let day = f.string(from: d)
            guard let url = URL(string: "https://www.fotmob.com/api/data/matches?date=\(day)&timezone=Europe%2FBerlin"),
                  let j = try? await HTTP.shared.json(url, maxAge: game.state == .post ? 86_400 : 120) else { continue }
            for l in j["leagues"].array {
                for m in l["matches"].array where sameTeam(m["home"]["name"].str, game.home.name)
                    && sameTeam(m["away"]["name"].str, game.away.name) {
                    if let id = m["id"].int { idCache[game.id] = id; return id }
                }
            }
        }
        return nil
    }

    static func load(_ game: Game) async -> Data? {
        guard let id = await matchId(for: game),
              let url = URL(string: "https://www.fotmob.com/api/data/matchDetails?matchId=\(id)"),
              let d = try? await HTTP.shared.json(url, maxAge: game.state == .live ? 30 : game.state == .post ? 86_400 : 600)
        else { return nil }
        let c = d["content"]
        let teams = d["header"]["teams"].array
        let homeId = teams.first?["id"].int, homeName = teams.first?["name"].str ?? game.home.name
        let awayName = teams.count > 1 ? teams[1]["name"].str : game.away.name

        // Stats groups ("Top stats", "Shots", "Passes" ...).
        var groups: [(title: String, rows: [StatRow])] = []
        var xg: (Double, Double)?
        for g in c["stats"]["Periods"]["All"]["stats"].array {
            let rows: [StatRow] = g["stats"].array.compactMap { s in
                let vals = s["stats"].array
                guard vals.count == 2, s["type"].str != "title" else { return nil }
                func text(_ v: J) -> String { v.string ?? v.double.map { $0.rounded() == $0 ? String(Int($0)) : String($0) } ?? "–" }
                let raw = s["rawStats"].array
                return StatRow(title: s["title"].str, home: text(vals[0]), away: text(vals[1]),
                               homeValue: raw.first?["value"].double ?? vals[0].double ?? Double(vals[0].str),
                               awayValue: raw.count > 1 ? (raw[1]["value"].double ?? vals[1].double ?? Double(vals[1].str)) : nil)
            }
            if let x = rows.first(where: { $0.title.lowercased().hasPrefix("expected goals (xg)") || $0.title == "Expected goals (xG)" }),
               let h = x.homeValue, let a = x.awayValue, xg == nil { xg = (h, a) }
            if !rows.isEmpty { groups.append((g["title"].str, rows)) }
        }

        let shots: [Shot] = c["shotmap"]["shots"].array.map { s in
            Shot(x: s["x"].double ?? 0, y: s["y"].double ?? 0, xg: s["expectedGoals"].double ?? 0,
                 isGoal: s["eventType"].str == "Goal", onTarget: s["isOnTarget"].bool == true,
                 home: s["teamId"].int == homeId, player: s["playerName"].str, minute: s["min"].int ?? 0)
        }
        let momentum = c["momentum"]["main"]["data"].array.compactMap { p -> (minute: Double, value: Double)? in
            guard let m = p["minute"].double, let v = p["value"].double else { return nil }
            return (m, v)
        }
        var ratings: [Rating] = []
        for (side, home) in [(c["lineup"]["homeTeam"], true), (c["lineup"]["awayTeam"], false)] {
            for p in side["starters"].array + side["subs"].array {
                if let r = p["performance"]["rating"].double {
                    ratings.append(Rating(name: p["name"].str, rating: r, home: home, position: nil))
                }
            }
        }
        let potm = c["matchFacts"]["playerOfTheMatch"]["name"]["fullName"].string

        var h2h: (Int, Int, Int)?
        let summary = c["h2h"]["summary"].array.compactMap(\.int)
        if summary.count == 3 { h2h = (summary[0], summary[1], summary[2]) }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let h2hMatches = c["h2h"]["matches"].array.filter { $0["status"]["finished"].bool == true }.prefix(6).map { m in
            (date: m["time"]["utcTime"].string.flatMap { iso.date(from: $0) ?? ESPNDate.parse($0) },
             home: m["home"]["name"].str, away: m["away"]["name"].str,
             score: m["status"]["scoreStr"].string ?? "–",
             competition: m["league"]["name"].str)
        }

        return Data(matchId: id, homeName: homeName, awayName: awayName,
                    xg: xg.map { (home: $0.0, away: $0.1) }, groups: groups, shots: shots, momentum: momentum,
                    ratings: ratings.sorted { $0.rating > $1.rating }, playerOfTheMatch: potm,
                    h2h: h2h.map { (home: $0.0, draws: $0.1, away: $0.2) }, h2hMatches: Array(h2hMatches))
    }
}
