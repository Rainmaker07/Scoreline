import Foundation

/// NBA Cup: groups from Wikipedia, games and live scores from ESPN.
/// ESPN's scoreboard doesn't mark Cup games, so a group game is the first
/// meeting of two same-group teams inside the Cup window (finished ones are
/// confirmed against Wikipedia's results).
struct NBACupGroup: Identifiable {
    var id: String { name }
    let name: String          // "East Group A"
    let conference: String    // "East" / "West"
    var rows: [StandingRow]
    var games: [Game]
}

struct NBACupData {
    let year: Int
    var groups: [NBACupGroup]
    var knockout: [(round: String, games: [Game])]
    let qualified: Set<String>
    /// True once every group game is played; until then winners and wild cards are provisional.
    var groupStageDone = false
}

enum NBACup {
    struct TeamRef { let id: String; let name: String; let short: String; let abbr: String; let logo: URL? }

    static func teams() async throws -> [TeamRef] {
        guard let url = URL(string: "\(ESPN.site)/basketball/nba/teams") else { return [] }
        let d = try await HTTP.shared.json(url, maxAge: 86_400 * 7)
        return d["sports"][0]["leagues"][0]["teams"].array.map { t in
            let x = t["team"]
            return TeamRef(id: x["id"].str, name: x["displayName"].str, short: x["shortDisplayName"].str,
                           abbr: x["abbreviation"].str, logo: x["logos"][0]["href"].url)
        }
    }

    static func load(year: Int) async throws -> NBACupData {
        let finishedSeason = Date() > (Calendar.current.date(from: DateComponents(year: year, month: 12, day: 31)) ?? Date())
        let html = try await WikiEvents.page("\(year) NBA Cup", finished: finishedSeason)
        let nba = League.byId("nba")!
        let teamRefs = try await teams()
        func ref(_ name: String) -> TeamRef? {
            let n = name.replacingOccurrences(of: #"\s*\(.*\)$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces).lowercased()
            return teamRefs.first { $0.name.lowercased() == n }
                ?? teamRefs.first { n.hasSuffix($0.short.lowercased()) || $0.name.lowercased().hasSuffix(n) }
        }

        // Groups and Wikipedia results ("Detroit Pistons 110, Brooklyn Nets 94")
        var groupTeams: [(name: String, conference: String, ids: [String])] = []
        var wikiResults: [(a: String, aScore: Int, b: String, bScore: Int)] = []
        let resultRe = try NSRegularExpression(pattern: #"^(.+?) (\d+), (.+?) (\d+)"#)
        for chunk in WikiHTML.chunks(in: html) {
            let title = chunk.title
            let tables = WikiHTML.tables(in: chunk.html)
            for t in tables {
                guard let header = t.rows.first else { continue }
                if let first = header.first, header.allSatisfy({ $0 == first }), first.contains(",") {
                    let ns = first as NSString
                    if let m = resultRe.firstMatch(in: first, range: NSRange(location: 0, length: ns.length)) {
                        wikiResults.append((ns.substring(with: m.range(at: 1)), Int(ns.substring(with: m.range(at: 2))) ?? 0,
                                            ns.substring(with: m.range(at: 3)), Int(ns.substring(with: m.range(at: 4))) ?? 0))
                    }
                }
            }
            let lower = title.lowercased()
            guard lower.contains("group"), !lower.contains("ranking"),
                  let table = tables.first(where: { $0.column("team") != nil && $0.column("pld") != nil }),
                  let teamCol = table.column("team") else { continue }
            let ids = table.rows.dropFirst().compactMap { r in r.count > teamCol ? ref(r[teamCol])?.id : nil }
            if ids.count >= 4 {
                let conf = lower.hasPrefix("west") ? "West" : "East"
                let letter = title.split(separator: " ").last.map(String.init)?.uppercased() ?? ""
                groupTeams.append(("\(conf) Group \(letter)", conf, ids))
            }
        }

        // Cup window: Oct 28 – Dec 20 of that year (fetched day by day, up to two weeks ahead).
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: year, month: 10, day: 28))!
        let end = min(cal.date(from: DateComponents(year: year, month: 12, day: 20))!, cal.date(byAdding: .day, value: 14, to: Date())!)
        var days: [Date] = []
        var d = start
        while d <= end { days.append(d); d = cal.date(byAdding: .day, value: 1, to: d)! }
        let all = (try? await GameFeed.days(nba, days)) ?? []

        // Group games
        var groups: [NBACupGroup] = []
        var usedGames = Set<String>()
        var lastGroupGame = start
        for g in groupTeams {
            let members = Set(g.ids)
            var picked: [Game] = []
            var seenPairs = Set<String>()
            for game in all where members.contains(game.home.id) && members.contains(game.away.id) {
                let pair = [game.home.id, game.away.id].sorted().joined(separator: "-")
                if seenPairs.contains(pair) { continue }
                if game.state == .post, !wikiResults.isEmpty {
                    let hs = Int(game.home.score ?? "") ?? -1, as_ = Int(game.away.score ?? "") ?? -1
                    let matches = wikiResults.contains { r in
                        let a = ref(r.a)?.id, b = ref(r.b)?.id
                        return (a == game.home.id && b == game.away.id && r.aScore == hs && r.bScore == as_)
                            || (a == game.away.id && b == game.home.id && r.aScore == as_ && r.bScore == hs)
                    }
                    if !matches { continue }
                }
                seenPairs.insert(pair)
                picked.append(game)
                usedGames.insert(game.id)
                lastGroupGame = max(lastGroupGame, game.date)
            }
            let rows = table(for: g.ids, games: picked, refs: teamRefs)
            groups.append(NBACupGroup(name: g.name, conference: g.conference, rows: rows, games: picked))
        }

        // Qualified: group winners + best second-placed team per conference.
        var qualified = Set<String>()
        for conf in ["East", "West"] {
            let gs = groups.filter { $0.conference == conf }
            gs.compactMap { $0.rows.first?.id }.forEach { qualified.insert($0) }
            let seconds = gs.compactMap { $0.rows.count > 1 ? $0.rows[1] : nil }
            if let wc = seconds.sorted(by: rankOrder).first { qualified.insert(wc.id) }
        }

        // Knockout: only games ESPN labels as Cup knockout games ("NBA Cup - Quarterfinals",
        // "NBA Cup - Semifinals", "NBA Cup Championship"). Regular-season games between the
        // same teams are not knockout games.
        func round(_ g: Game) -> String? {
            let n = (g.note ?? "").lowercased()
            guard n.contains("nba cup") else { return nil }
            if n.contains("quarterfinal") { return "Quarterfinals" }
            if n.contains("semifinal") { return "Semifinals" }
            if n.contains("championship") || n.contains("final") { return "Championship" }
            return nil
        }
        var knockout: [(round: String, games: [Game])] = []
        for name in ["Quarterfinals", "Semifinals", "Championship"] {
            let games = all.filter { round($0) == name }.sorted { $0.date < $1.date }
            if !games.isEmpty { knockout.append((round: name, games: games)) }
        }
        // Each group of five plays ten games.
        let done = !groups.isEmpty && groups.allSatisfy { $0.games.filter { $0.state == .post }.count >= 10 }
        _ = lastGroupGame
        return NBACupData(year: year, groups: groups, knockout: knockout, qualified: qualified, groupStageDone: done)
    }

    private static func rankOrder(_ a: StandingRow, _ b: StandingRow) -> Bool {
        let aw = Int(a.stats["wins"] ?? "") ?? 0, bw = Int(b.stats["wins"] ?? "") ?? 0
        if aw != bw { return aw > bw }
        let ad = Int((a.stats["differential"] ?? "").replacingOccurrences(of: "+", with: "")) ?? 0
        let bd = Int((b.stats["differential"] ?? "").replacingOccurrences(of: "+", with: "")) ?? 0
        return ad > bd
    }

    static func table(for ids: [String], games: [Game], refs: [TeamRef]) -> [StandingRow] {
        var rows: [StandingRow] = ids.compactMap { id in
            guard let r = refs.first(where: { $0.id == id }) else { return nil }
            var w = 0, l = 0, pf = 0, pa = 0
            for g in games where g.state == .post && (g.home.id == id || g.away.id == id) {
                let me = g.home.id == id ? g.home : g.away
                let them = g.home.id == id ? g.away : g.home
                let a = Int(me.score ?? "") ?? 0, b = Int(them.score ?? "") ?? 0
                pf += a; pa += b
                if a > b { w += 1 } else { l += 1 }
            }
            let pd = pf - pa
            return StandingRow(id: id, name: r.name, short: r.short, abbr: r.abbr, logo: r.logo,
                               stats: ["wins": "\(w)", "losses": "\(l)", "pointsFor": "\(pf)", "pointsAgainst": "\(pa)",
                                       "differential": pd > 0 ? "+\(pd)" : "\(pd)", "gamesPlayed": "\(w + l)"],
                               noteColor: nil, noteText: nil)
        }
        rows.sort(by: rankOrder)
        return rows
    }
}
