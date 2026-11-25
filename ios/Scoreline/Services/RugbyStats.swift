import Foundation

/// Premiership Rugby season stats, counted from every finished game's ESPN summary:
/// scoring events (tries, conversions, penalty and drop goals), cards and the matchday
/// squads (appearances and starts). ESPN has no rugby player stats of its own.
enum RugbyStats {
    struct PlayerLine: Identifiable, Hashable {
        let id: String
        var name: String
        var teamId: String
        var apps = 0, starts = 0
        var tries = 0, conversions = 0, penalties = 0, drops = 0
        var yellow = 0, red = 0
        var points: Int { tries * 5 + conversions * 2 + penalties * 3 + drops * 3 }
    }

    struct TeamLine: Hashable {
        var games = 0
        var triesFor = 0, triesAgainst = 0
        var pointsFor = 0, pointsAgainst = 0
    }

    struct Season {
        let players: [String: PlayerLine]
        let teams: [String: TeamLine]
        let teamInfo: [String: (name: String, abbr: String, logo: URL?)]
    }

    private static let cache = LockedCache<String, (Date, Season)>()

    static func season(_ league: League) async throws -> Season {
        if let hit = cache[league.id], Date().timeIntervalSince(hit.0) < 1800 { return hit.1 }
        let games = try await ESPN.seasonGames(league).filter { $0.state == .post }
        guard let path = league.espn else { return Season(players: [:], teams: [:], teamInfo: [:]) }
        // Summaries of finished games, six at a time (cached for a long time).
        let summaries: [J] = await withTaskGroup(of: J?.self) { group in
            var out: [J] = []
            var next = 0
            while next < min(6, games.count) {
                let g = games[next]
                group.addTask { try? await HTTP.shared.json(URL(string: "\(ESPN.site)/\(path)/summary?event=\(g.id)")!, maxAge: 86_400 * 30) }
                next += 1
            }
            for await s in group {
                if let s { out.append(s) }
                if next < games.count {
                    let g = games[next]
                    group.addTask { try? await HTTP.shared.json(URL(string: "\(ESPN.site)/\(path)/summary?event=\(g.id)")!, maxAge: 86_400 * 30) }
                    next += 1
                }
            }
            return out
        }
        var players: [String: PlayerLine] = [:]
        var teams: [String: TeamLine] = [:]
        var info: [String: (name: String, abbr: String, logo: URL?)] = [:]
        for s in summaries {
            let comp = s["header"]["competitions"][0]
            let cs = comp["competitors"].array
            for c in cs {
                let id = c["team"]["id"].str
                info[id] = (c["team"]["displayName"].str, c["team"]["abbreviation"].str, ESPN.teamLogo(c["team"]))
            }
            if cs.count == 2 {
                let a = cs[0], b = cs[1]
                let sa = Int(a["score"].str) ?? 0, sb = Int(b["score"].str) ?? 0
                teams[a["team"]["id"].str, default: TeamLine()].games += 1
                teams[b["team"]["id"].str, default: TeamLine()].games += 1
                teams[a["team"]["id"].str]!.pointsFor += sa; teams[a["team"]["id"].str]!.pointsAgainst += sb
                teams[b["team"]["id"].str]!.pointsFor += sb; teams[b["team"]["id"].str]!.pointsAgainst += sa
            }
            // Appearances: starters (shirt 1-15) and replacements who came on.
            for r in s["rosters"].array {
                let tid = r["team"]["id"].str
                for p in r["roster"].array {
                    let a = p["athlete"]
                    let id = a["id"].str
                    guard !id.isEmpty else { continue }
                    let jersey = Int(p["jersey"].str) ?? 99
                    let started = p["starter"].bool == true || jersey <= 15
                    let played = started || p["subbedIn"].bool == true
                    var line = players[id] ?? PlayerLine(id: id, name: a["displayName"].str, teamId: tid)
                    if played { line.apps += 1 }
                    if started { line.starts += 1 }
                    players[id] = line
                }
            }
            for d in comp["details"].array {
                let kind = d["type"]["text"].str.lowercased()
                let tid = d["team"]["id"].str
                let a = d["participants"][0]["athlete"]
                let id = a["id"].str
                if kind == "try" || kind == "penalty try" {
                    teams[tid, default: TeamLine()].triesFor += 1
                    if let other = cs.first(where: { $0["team"]["id"].str != tid })?["team"]["id"].str {
                        teams[other, default: TeamLine()].triesAgainst += 1
                    }
                }
                guard !id.isEmpty else { continue }
                var line = players[id] ?? PlayerLine(id: id, name: a["displayName"].str, teamId: tid)
                switch kind {
                case "try": line.tries += 1
                case "conversion": line.conversions += 1
                case "penalty goal", "penalty": line.penalties += 1
                case "drop goal": line.drops += 1
                case "yellow card": line.yellow += 1
                case "red card": line.red += 1
                default: break
                }
                players[id] = line
            }
        }
        let season = Season(players: players, teams: teams, teamInfo: info)
        cache[league.id] = (Date(), season)
        return season
    }

    /// Stat leaders: tries, points, conversions, penalty goals, cards.
    static func leaders(_ league: League) async throws -> [LeaderCategory] {
        let s = try await season(league)
        let all = Array(s.players.values)
        func cat(_ name: String, _ label: String, _ value: (PlayerLine) -> Int, detail: @escaping (PlayerLine) -> String) -> LeaderCategory? {
            let top = all.filter { value($0) > 0 }.sorted { (value($0), $1.name) > (value($1), $0.name) }.prefix(15)
            guard !top.isEmpty else { return nil }
            return LeaderCategory(name: name, label: label, leaders: top.map { p in
                let t = s.teamInfo[p.teamId]
                return LeaderEntry(name: p.name, athleteId: p.id, team: t?.name, teamLogo: t?.logo, headshot: nil,
                                   value: "\(value(p))", detail: detail(p))
            })
        }
        return [
            cat("tries", "Tries", { $0.tries }) { "\($0.apps) apps" },
            cat("points", "Points", { $0.points }) { "\($0.tries) T · \($0.conversions) C · \($0.penalties) P" },
            cat("conversions", "Conversions", { $0.conversions }) { "\($0.apps) apps" },
            cat("penalties", "Penalty goals", { $0.penalties }) { "\($0.apps) apps" },
            cat("cards", "Cards", { $0.yellow + $0.red * 2 }) { "\($0.yellow) yellow · \($0.red) red" },
        ].compactMap { $0 }
    }

    /// Player page from the season stats; photo and bio come from Wikipedia.
    static func playerPage(_ league: League, id: String) async throws -> PlayerPage {
        let s = try await season(league)
        guard let p = s.players[id] else { throw FetchError.parse("Player not found") }
        let team = s.teamInfo[p.teamId]
        var bio: [InfoRow] = []
        for title in [p.name + " (rugby union)", p.name] {
            if let w = await Wiki.summary(title), (w.description ?? "").lowercased().contains("rugby") {
                if let d = w.description { bio.append(InfoRow(label: "About", value: d.prefix(1).uppercased() + d.dropFirst())) }
                break
            }
        }
        let rows: [InfoRow] = [
            InfoRow(label: "Appearances", value: "\(p.apps)"), InfoRow(label: "Starts", value: "\(p.starts)"),
            InfoRow(label: "Tries", value: "\(p.tries)"), InfoRow(label: "Conversions", value: "\(p.conversions)"),
            InfoRow(label: "Penalty goals", value: "\(p.penalties)"), InfoRow(label: "Drop goals", value: "\(p.drops)"),
            InfoRow(label: "Points", value: "\(p.points)"),
            InfoRow(label: "Cards", value: "\(p.yellow) yellow · \(p.red) red"),
        ]
        return PlayerPage(league: league, id: id, name: p.name, headshot: nil, team: team?.name, teamId: p.teamId,
                          teamLogo: team?.logo, bio: bio, seasonStats: rows, tables: [], gameLogLabels: [], gameLog: [])
    }

    /// Extra team rows: tries against, top try and points scorers.
    static func teamRows(_ league: League, teamId: String) async -> [InfoRow] {
        guard let s = try? await season(league), let t = s.teams[teamId] else { return [] }
        let mine = s.players.values.filter { $0.teamId == teamId }
        var rows = [InfoRow(label: "Tries against", value: "\(t.triesAgainst)")]
        if t.games > 0 { rows.append(InfoRow(label: "Points per game", value: String(format: "%.1f", Double(t.pointsFor) / Double(t.games)))) }
        if let top = mine.max(by: { $0.tries < $1.tries }), top.tries > 0 { rows.append(InfoRow(label: "Top try scorer", value: "\(top.name) (\(top.tries))")) }
        if let top = mine.max(by: { $0.points < $1.points }), top.points > 0 { rows.append(InfoRow(label: "Top points scorer", value: "\(top.name) (\(top.points))")) }
        return rows
    }
}
