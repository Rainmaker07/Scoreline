import Foundation
import UIKit

/// Live checks of every data source and parser the app depends on.
///
/// They run against the real services (ESPN, easycredit-bbl.de, Wikipedia,
/// FotMob), so a change on their side shows up as a failed check instead of
/// an empty screen. Run from Settings → Data sources, and on every GitHub build
/// (launch argument `-runDataChecks`, results written to Documents/data-checks.json).
struct DataCheckResult: Codable, Identifiable, Hashable {
    var id: String { group + "/" + name }
    let group: String
    let name: String
    let ok: Bool
    let detail: String
    let seconds: Double
}

struct DataCheckFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum DataChecks {
    struct Check {
        let group: String
        let name: String
        let run: () async throws -> String
    }

    /// Throws with `message` unless `condition` holds.
    static func expect(_ condition: Bool, _ message: @autoclosure () -> String) throws {
        if !condition { throw DataCheckFailure(message: message()) }
    }

    static func league(_ id: String) -> League { League.byId(id)! }
    static var year: Int { Calendar.current.component(.year, from: Date()) }
    private static func DataChecks.daysBack(_ n: Int) -> [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        return (0...n).map { Calendar.current.date(byAdding: .day, value: -$0, to: today)! }
    }

    static var all: [Check] {
        var checks: [Check] = []
        func add(_ group: String, _ name: String, _ run: @escaping () async throws -> String) {
            checks.append(Check(group: group, name: name, run: run))
        }

        // MARK: ESPN, every league
        for l in League.all where l.provider == .espn {
            if l.isCup {
                add("ESPN", "\(l.short) rounds") {
                    let rounds = try await ESPN.cupRounds(l)
                    try DataChecks.expect(!rounds.isEmpty, "no rounds in the calendar")
                    let days = rounds.flatMap { ESPN.matchDays($0) }
                    try DataChecks.expect(!days.isEmpty, "round labels no longer parse into match days")
                    return "\(rounds.count) rounds"
                }
            } else {
                add("ESPN", "\(l.short) standings") {
                    let groups = try await ESPN.standings(l, divisions: false)
                    let rows = groups.flatMap(\.rows)
                    try DataChecks.expect(rows.count >= 8, "only \(rows.count) rows")
                    try DataChecks.expect(rows.allSatisfy { !$0.name.isEmpty }, "rows without team names")
                    return "\(groups.count) groups, \(rows.count) teams"
                }
            }
            add("ESPN", "\(l.short) scoreboard") {
                // Off-season leagues may have no games; the request and parse must still work.
                let games = try await GameFeed.days(l, DataChecks.daysBack(2))
                try DataChecks.expect(games.allSatisfy { !$0.home.name.isEmpty && !$0.away.name.isEmpty }, "games without team names")
                return "\(games.count) games in the last 3 days"
            }
        }

        add("ESPN", "NBA results have scores") {
            let games = try await GameFeed.days(DataChecks.league("nba"), DataChecks.daysBack(6)).filter { $0.state == .post }
            try DataChecks.expect(!games.isEmpty, "no finished games in the last week")
            try DataChecks.expect(games.allSatisfy { !($0.home.score ?? "").isEmpty }, "finished games without scores")
            return "\(games.count) finished games"
        }
        add("ESPN", "Football results have scores") {
            let games = try await GameFeed.days(DataChecks.league("epl"), DataChecks.daysBack(9)).filter { $0.state == .post }
            try DataChecks.expect(!games.isEmpty, "no finished Premier League games in 10 days")
            try DataChecks.expect(games.allSatisfy { !($0.home.score ?? "").isEmpty }, "finished games without scores")
            return "\(games.count) finished games"
        }
        add("ESPN", "NBA game summary") {
            let g = try await GameFeed.days(DataChecks.league("nba"), DataChecks.daysBack(6)).first { $0.state == .post }
            guard let g else { throw DataCheckFailure(message: "no finished game to open") }
            let s = try await ESPN.summary(DataChecks.league("nba"), id: g.id)
            try DataChecks.expect(!s["boxscore"]["players"].array.isEmpty, "box score missing")
            return "\(g.away.abbr) @ \(g.home.abbr): box score OK"
        }
        add("ESPN", "Football match summary") {
            let g = try await GameFeed.days(DataChecks.league("epl"), DataChecks.daysBack(9)).first { $0.state == .post }
            guard let g else { throw DataCheckFailure(message: "no finished game to open") }
            let s = try await ESPN.summary(DataChecks.league("epl"), id: g.id)
            try DataChecks.expect(!s["rosters"].array.isEmpty, "lineups missing")
            return "\(g.home.abbr) v \(g.away.abbr): lineups OK"
        }
        for id in ["nba", "mlb", "epl", "bl1"] {
            let l = league(id)
            add("ESPN", "\(l.short) stat leaders") {
                let cats = try await ESPN.leaders(l)
                try DataChecks.expect(!cats.isEmpty, "no categories")
                try DataChecks.expect(cats.allSatisfy { !$0.leaders.isEmpty }, "empty category")
                return "\(cats.count) categories"
            }
        }
        add("ESPN", "Team page") {
            let l = DataChecks.league("nba")
            guard let row = try await ESPN.standings(l, divisions: false).flatMap(\.rows).first else {
                throw DataCheckFailure(message: "no team to open")
            }
            let t = try await ESPN.team(l, id: row.id)
            try DataChecks.expect(!t.games.isEmpty, "no schedule")
            try DataChecks.expect(!t.roster.isEmpty, "no roster")
            return "\(t.name): \(t.games.count) games, \(t.roster.count) players"
        }
        add("ESPN", "Football team across competitions") {
            let l = DataChecks.league("epl")
            guard let row = try await ESPN.standings(l, divisions: false).flatMap(\.rows).first else {
                throw DataCheckFailure(message: "no team to open")
            }
            let t = try await ESPN.team(l, id: row.id)
            try DataChecks.expect(!t.games.isEmpty, "no schedule")
            return "\(t.name): \(t.games.count) games"
        }
        add("ESPN", "Player page") {
            let l = DataChecks.league("nba")
            guard let id = try await ESPN.leaders(l).first?.leaders.first?.athleteId else {
                throw DataCheckFailure(message: "no player to open")
            }
            let p = try await ESPN.player(l, id: id)
            try DataChecks.expect(!p.name.isEmpty, "no name")
            try DataChecks.expect(!p.seasonStats.isEmpty || !p.tables.isEmpty, "no stats")
            return p.name
        }
        add("ESPN", "Search") {
            let hits = await ESPN.search("Arsenal")
            try DataChecks.expect(hits.contains { $0.kind == "team" }, "no team found for 'Arsenal'")
            return "\(hits.count) results"
        }
        add("ESPN", "NBA Cup") {
            let d = try await NBACup.load(year: ESPN.nbaCupYear())
            try DataChecks.expect(d.groups.count == 6, "\(d.groups.count) groups instead of 6")
            try DataChecks.expect(d.groups.allSatisfy { $0.rows.count == 5 }, "a group doesn't have 5 teams")
            return "6 groups"
        }

        // MARK: easyCredit BBL
        add("BBL", "Standings") {
            let rows = try await BBL.standings().flatMap(\.rows)
            try DataChecks.expect(rows.count >= 16, "only \(rows.count) teams")
            return "\(rows.count) teams"
        }
        add("BBL", "Games") {
            let games = try await BBL.games()
            try DataChecks.expect(!games.isEmpty, "no games")
            return "\(games.count) games"
        }
        add("BBL", "Game detail") {
            guard let g = try await BBL.games().last(where: { $0.state == .post }) else { return "no finished game yet" }
            _ = try await BBL.gameDetail(g.id)
            return "\(g.home.abbr) v \(g.away.abbr)"
        }

        // MARK: Tennis
        add("Tennis", "ATP season") {
            let s = try await Tennis.season(DataChecks.year)
            try DataChecks.expect(s.count >= 40, "only \(s.count) tournaments")
            try DataChecks.expect(s.contains { $0.tier == .slam }, "no Grand Slams found")
            try DataChecks.expect(s.contains { $0.tier == .masters }, "no Masters 1000 found")
            return "\(s.count) tournaments"
        }
        add("Tennis", "Tournament draw") {
            let s = try await Tennis.season(DataChecks.year)
            guard let t = s.last(where: { $0.end < Date() && $0.wikiTitle == nil && $0.tier == .slam })
                    ?? s.last(where: { $0.end < Date() && $0.wikiTitle == nil }) else {
                throw DataCheckFailure(message: "no finished tournament")
            }
            let ev = try await Tennis.tournament(t, grouping: "mens-singles")
            try DataChecks.expect((ev?.matches.count ?? 0) >= 15, "draw has \(ev?.matches.count ?? 0) matches")
            return "\(t.name): \(ev?.matches.count ?? 0) matches"
        }
        add("Tennis", "Rankings") {
            let r = try await Tennis.rankings()
            try DataChecks.expect(r.count >= 50, "only \(r.count) players")
            try DataChecks.expect(r.prefix(20).filter { $0.flag != nil }.count >= 15, "flags missing")
            try DataChecks.expect(r.prefix(20).filter { $0.headshot != nil }.count >= 10, "photos missing")
            return "\(r.count) players"
        }
        add("Tennis", "Laver Cup") {
            let y = Calendar.current.component(.month, from: Date()) >= 10 ? DataChecks.year : DataChecks.year - 1
            let d = try await LaverCup.load(year: y, finished: true)
            try DataChecks.expect(!d.matches.isEmpty, "no matches")
            return "\(y): Europe \(d.europe) – World \(d.world)"
        }
        add("Tennis", "Davis Cup") {
            let y = DataChecks.year - 1   // last finished Finals
            let ties = try await DavisCup.load("\(y) Davis Cup Finals", finished: true)
            try DataChecks.expect(!ties.isEmpty, "no ties")
            return "\(y): \(ties.count) ties"
        }

        // MARK: Cycling (Wikipedia)
        add("Cycling", "Grand Tours") {
            var out: [String] = []
            for def in TourDef.all {
                let y = CyclingService.isFinished(def, DataChecks.year) ? DataChecks.year : DataChecks.year - 1
                let e = try await CyclingService.load(def, year: y)
                try DataChecks.expect(e.stages.count >= 18, "\(def.short) \(y): \(e.stages.count) stages")
                try DataChecks.expect(!(e.classifications[.gc] ?? []).isEmpty, "\(def.short) \(y): no GC")
                out.append("\(def.short) \(e.stages.count)")
            }
            return out.joined(separator: ", ")
        }
        add("Cycling", "WorldTour calendar") {
            let races = try await WorldTour.calendar(DataChecks.year)
            try DataChecks.expect(races.count >= 25, "only \(races.count) races")
            return "\(races.count) races"
        }
        add("Cycling", "One-day race") {
            let races = try await WorldTour.calendar(DataChecks.year)
            guard let r = races.last(where: { $0.start != nil && $0.start == $0.end && ($0.end ?? .distantFuture) < Date() }) else {
                throw DataCheckFailure(message: "no finished one-day race")
            }
            let res = try await WorldTour.oneDay(r)
            try DataChecks.expect(res.results.count >= 5, "\(r.name): \(res.results.count) results")
            return "\(r.name): winner \(res.results.first?.name ?? "?")"
        }
        add("Cycling", "Rider page") {
            let p = try await CyclingPeople.rider("Tadej Pogačar")
            try DataChecks.expect(!p.teams.isEmpty, "no team history")
            try DataChecks.expect(!p.majorWins.isEmpty, "no major wins")
            return "\(p.teams.count) teams, \(p.majorWins.count) win categories"
        }
        add("Cycling", "Team page") {
            let p = try await CyclingPeople.rider("Tadej Pogačar")
            guard let team = p.currentTeam else { throw DataCheckFailure(message: "rider has no current team") }
            let t = try await CyclingPeople.team(team)
            try DataChecks.expect(t.roster != nil, "\(team): no roster")
            return team
        }

        // MARK: Photos and logos
        add("Images", "FotMob player photo") {
            let url = await FotMob.photo(name: "Erling Haaland", team: "Manchester City")
            guard let url else { throw DataCheckFailure(message: "player not found") }
            let img = await ImageStore.shared.image(url)
            try DataChecks.expect(img != nil, "photo doesn't load")
            return "OK"
        }
        add("Images", "Competition logos") {
            let urls: [URL?] = [LogoAssets.nbaCup, LogoAssets.atp, LogoAssets.uciWorldTour, LogoAssets.atp500,
                                LogoAssets.australianOpen, LogoAssets.rolandGarros, LogoAssets.wimbledon, LogoAssets.usOpen,
                                LogoAssets.giro, LogoAssets.tour, LogoAssets.vuelta]
            var broken: [String] = []
            for case let u? in urls {
                if await ImageStore.shared.image(u) == nil { broken.append(u.lastPathComponent) }
            }
            try DataChecks.expect(broken.isEmpty, "not loading: " + broken.joined(separator: ", "))
            return "\(urls.count) logos"
        }
        return checks
    }

    /// Runs all checks, four at a time.
    static func runAll(progress: @escaping @MainActor (DataCheckResult) -> Void = { _ in }) async -> [DataCheckResult] {
        let checks = all
        var results: [DataCheckResult] = []
        await withTaskGroup(of: DataCheckResult.self) { group in
            var next = 0
            while next < min(4, checks.count) {
                let c = checks[next]
                group.addTask { await DataChecks.run(c) }
                next += 1
            }
            for await r in group {
                results.append(r)
                await progress(r)
                if next < checks.count {
                    let c = checks[next]
                    group.addTask { await DataChecks.run(c) }
                    next += 1
                }
            }
        }
        let order = Dictionary(uniqueKeysWithValues: checks.enumerated().map { ($1.group + "/" + $1.name, $0) })
        return results.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
    }

    static func run(_ c: Check) async -> DataCheckResult {
        let t0 = Date()
        do {
            let detail = try await c.run()
            return DataCheckResult(group: c.group, name: c.name, ok: true, detail: detail, seconds: Date().timeIntervalSince(t0))
        } catch {
            return DataCheckResult(group: c.group, name: c.name, ok: false, detail: error.localizedDescription, seconds: Date().timeIntervalSince(t0))
        }
    }

    /// CI entry point: run, write the results to Documents/data-checks.json, quit.
    @MainActor static func runForCI() async {
        let results = await runAll()
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(results).write(to: docs.appendingPathComponent("data-checks.json"), options: .atomic)
        exit(0)
    }
}
