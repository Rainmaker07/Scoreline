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
                    try dcExpect(!rounds.isEmpty, "no rounds in the calendar")
                    let days = rounds.flatMap { ESPN.matchDays($0) }
                    try dcExpect(!days.isEmpty, "round labels no longer parse into match days")
                    return "\(rounds.count) rounds"
                }
            } else {
                add("ESPN", "\(l.short) standings") {
                    let groups = try await ESPN.standings(l, divisions: false)
                    let rows = groups.flatMap(\.rows)
                    try dcExpect(rows.count >= 8, "only \(rows.count) rows")
                    try dcExpect(rows.allSatisfy { !$0.name.isEmpty }, "rows without team names")
                    return "\(groups.count) groups, \(rows.count) teams"
                }
            }
            add("ESPN", "\(l.short) scoreboard") {
                // Off-season leagues may have no games; the request and parse must still work.
                let games = try await GameFeed.days(l, dcDaysBack(2))
                try dcExpect(games.allSatisfy { !$0.home.name.isEmpty && !$0.away.name.isEmpty }, "games without team names")
                return "\(games.count) games in the last 3 days"
            }
        }

        add("ESPN", "NBA results have scores") {
            let games = try await GameFeed.days(dcLeague("nba"), dcDaysBack(6)).filter { $0.state == .post }
            try dcExpect(!games.isEmpty, "no finished games in the last week")
            try dcExpect(games.allSatisfy { !($0.home.score ?? "").isEmpty }, "finished games without scores")
            return "\(games.count) finished games"
        }
        add("ESPN", "Football results have scores") {
            let games = try await GameFeed.days(dcLeague("epl"), dcDaysBack(9)).filter { $0.state == .post }
            try dcExpect(!games.isEmpty, "no finished Premier League games in 10 days")
            try dcExpect(games.allSatisfy { !($0.home.score ?? "").isEmpty }, "finished games without scores")
            return "\(games.count) finished games"
        }
        add("ESPN", "NBA game summary") {
            let g = try await GameFeed.days(dcLeague("nba"), dcDaysBack(6)).first { $0.state == .post }
            guard let g else { throw DataCheckFailure(message: "no finished game to open") }
            let s = try await ESPN.summary(dcLeague("nba"), id: g.id)
            try dcExpect(!s["boxscore"]["players"].array.isEmpty, "box score missing")
            return "\(g.away.abbr) @ \(g.home.abbr): box score OK"
        }
        add("ESPN", "Football match summary") {
            let g = try await GameFeed.days(dcLeague("epl"), dcDaysBack(9)).first { $0.state == .post }
            guard let g else { throw DataCheckFailure(message: "no finished game to open") }
            let s = try await ESPN.summary(dcLeague("epl"), id: g.id)
            try dcExpect(!s["rosters"].array.isEmpty, "lineups missing")
            return "\(g.home.abbr) v \(g.away.abbr): lineups OK"
        }
        for id in ["nba", "mlb", "epl", "bl1"] {
            let l = dcLeague(id)
            add("ESPN", "\(l.short) stat leaders") {
                let cats = try await ESPN.leaders(l)
                try dcExpect(!cats.isEmpty, "no categories")
                try dcExpect(cats.allSatisfy { !$0.leaders.isEmpty }, "empty category")
                return "\(cats.count) categories"
            }
        }
        for (g, label) in [(7, "AL"), (8, "NL")] {
            add("ESPN", "MLB \(label) leaders") {
                let cats = try await ESPN.leaders(dcLeague("mlb"), group: g)
                try dcExpect(cats.count >= 10, "only \(cats.count) categories")
                return "\(cats.count) categories, AVG leader \(cats.first?.leaders.first?.name ?? "?")"
            }
        }
        add("ESPN", "MLB fielding leaders") {
            let cats = try await ESPN.mlbFielding(group: nil)
            try dcExpect(cats.count >= 4, "only \(cats.count) categories")
            return "\(cats.count) categories"
        }
        add("ESPN", "NBA play-by-play + win probability") {
            guard let g = try await GameFeed.days(dcLeague("nba"), dcDaysBack(6)).last(where: { $0.state == .post }) else {
                throw DataCheckFailure(message: "no finished game")
            }
            let s = try await ESPN.summary(dcLeague("nba"), id: g.id)
            try dcExpect(s["plays"].array.count > 100, "only \(s["plays"].array.count) plays")
            try dcExpect(s["winprobability"].array.count > 20, "no win probability")
            return "\(s["plays"].array.count) plays"
        }
        add("ESPN", "NBA preview") {
            let today = Calendar.current.startOfDay(for: Date())
            let days = (1...3).map { Calendar.current.date(byAdding: .day, value: $0, to: today)! }
            guard let g = try await GameFeed.days(dcLeague("nba"), days).first(where: { $0.state == .pre }) else { return "no upcoming game" }
            let s = try await ESPN.summary(dcLeague("nba"), id: g.id)
            try dcExpect(!s["lastFiveGames"].array.isEmpty, "no recent form")
            return "predictor \(s["predictor"].exists ? "yes" : "no"), odds \(s["pickcenter"].array.isEmpty ? "no" : "yes"), injuries \(s["injuries"].array.count)"
        }
        add("FotMob", "Champions League match data") {
            guard let g = try await GameFeed.days(dcLeague("ucl"), dcDaysBack(14)).last(where: { $0.state == .post }) else {
                return "no finished CL game in 2 weeks"
            }
            guard let d = await FotMobMatch.load(g) else { throw DataCheckFailure(message: "\(g.home.name) v \(g.away.name) (\(g.date)): not found on FotMob") }
            try dcExpect(d.xg != nil && d.momentum.count > 5, "no xG or momentum")
            return "\(g.home.abbr) v \(g.away.abbr): xG \(String(format: "%.2f-%.2f", d.xg!.home, d.xg!.away)), \(d.events.count) events"
        }
        add("FotMob", "Match data (xG, shots, ratings)") {
            guard let g = try await GameFeed.days(dcLeague("epl"), dcDaysBack(9)).last(where: { $0.state == .post }) else {
                throw DataCheckFailure(message: "no finished game")
            }
            guard let d = await FotMobMatch.load(g) else { throw DataCheckFailure(message: "\(g.home.name) v \(g.away.name): match not found on FotMob") }
            try dcExpect(d.xg != nil, "no xG")
            try dcExpect(!d.shots.isEmpty, "no shot map")
            try dcExpect(!d.ratings.isEmpty, "no ratings")
            return "\(g.home.abbr) v \(g.away.abbr): xG \(String(format: "%.2f-%.2f", d.xg?.home ?? 0, d.xg?.away ?? 0)), \(d.shots.count) shots"
        }
        add("ESPN", "Team page") {
            let l = dcLeague("nba")
            guard let row = try await ESPN.standings(l, divisions: false).flatMap(\.rows).first else {
                throw DataCheckFailure(message: "no team to open")
            }
            let t = try await ESPN.team(l, id: row.id)
            try dcExpect(!t.games.isEmpty, "no schedule")
            try dcExpect(!t.roster.isEmpty, "no roster")
            return "\(t.name): \(t.games.count) games, \(t.roster.count) players"
        }
        add("ESPN", "Football team across competitions") {
            let l = dcLeague("epl")
            guard let row = try await ESPN.standings(l, divisions: false).flatMap(\.rows).first else {
                throw DataCheckFailure(message: "no team to open")
            }
            let t = try await ESPN.team(l, id: row.id)
            try dcExpect(!t.games.isEmpty, "no schedule")
            return "\(t.name): \(t.games.count) games"
        }
        add("ESPN", "Player page") {
            let l = dcLeague("nba")
            guard let id = try await ESPN.leaders(l).first?.leaders.first?.athleteId else {
                throw DataCheckFailure(message: "no player to open")
            }
            let p = try await ESPN.player(l, id: id)
            try dcExpect(!p.name.isEmpty, "no name")
            try dcExpect(!p.seasonStats.isEmpty || !p.tables.isEmpty, "no stats")
            return p.name
        }
        add("ESPN", "Search") {
            let hits = await ESPN.search("Arsenal")
            try dcExpect(hits.contains { $0.kind == "team" }, "no team found for 'Arsenal'")
            return "\(hits.count) results"
        }
        add("ESPN", "NBA Cup") {
            let d = try await NBACup.load(year: ESPN.nbaCupYear())
            try dcExpect(d.groups.count == 6, "\(d.groups.count) groups instead of 6")
            try dcExpect(d.groups.allSatisfy { $0.rows.count == 5 }, "a group doesn't have 5 teams")
            return "6 groups"
        }

        // MARK: easyCredit BBL
        add("BBL", "Standings") {
            let rows = try await BBL.standings().flatMap(\.rows)
            try dcExpect(rows.count >= 16, "only \(rows.count) teams")
            return "\(rows.count) teams"
        }
        add("BBL", "Games") {
            let games = try await BBL.games()
            try dcExpect(!games.isEmpty, "no games")
            return "\(games.count) games"
        }
        add("BBL", "Stat leaders") {
            let cats = try await BBL.leaders()
            try dcExpect(cats.count >= 6, "only \(cats.count) categories")
            try dcExpect(cats.allSatisfy { !$0.leaders.isEmpty }, "empty category")
            return "\(cats.count) categories, top scorer \(cats.first?.leaders.first?.name ?? "?")"
        }
        add("BBL", "Game detail") {
            guard let g = try await BBL.games().last(where: { $0.state == .post }) else { return "no finished game yet" }
            _ = try await BBL.gameDetail(g.id)
            return "\(g.home.abbr) v \(g.away.abbr)"
        }

        // MARK: Tennis
        add("Tennis", "ATP season") {
            let s = try await Tennis.season(dcYear)
            try dcExpect(s.count >= 40, "only \(s.count) tournaments")
            try dcExpect(s.contains { $0.tier == .slam }, "no Grand Slams found")
            try dcExpect(s.contains { $0.tier == .masters }, "no Masters 1000 found")
            return "\(s.count) tournaments"
        }
        add("Tennis", "Tournament draw") {
            let s = try await Tennis.season(dcYear)
            guard let t = s.last(where: { $0.end < Date() && $0.wikiTitle == nil && $0.tier == .slam })
                    ?? s.last(where: { $0.end < Date() && $0.wikiTitle == nil }) else {
                throw DataCheckFailure(message: "no finished tournament")
            }
            let ev = try await Tennis.tournament(t, grouping: "mens-singles")
            try dcExpect((ev?.matches.count ?? 0) >= 15, "draw has \(ev?.matches.count ?? 0) matches")
            return "\(t.name): \(ev?.matches.count ?? 0) matches"
        }
        add("Tennis", "Race to the Finals") {
            let r = try await ATPRace.load(year: dcYear)
            if r.entries.isEmpty {
                // Report the tables near "Race to" so the parser can be fixed.
                guard let url = CyclingService.wikiURL("\(dcYear) ATP Tour") else { return "bad title" }
                let html = try await HTTP.shared.text(url, maxAge: 3600)
                let heads = WikiHTML.tables(in: html).prefix(14).map { "[" + ($0.rows.first ?? []).prefix(5).joined(separator: "/") + "]" }
                throw DataCheckFailure(message: "no race table (\(html.lowercased().contains("race to") ? "has" : "no") 'race to'); tables: " + heads.joined(separator: " "))
            }
            return "\(r.title): \(r.entries.count) players, leader \(r.entries[0].name) \(r.entries[0].points), \(r.entries.filter(\.qualified).count) marked Q"
        }
        add("Tennis", "Rankings") {
            let r = try await Tennis.rankings()
            try dcExpect(r.count >= 50, "only \(r.count) players")
            try dcExpect(r.prefix(20).filter { $0.flag != nil }.count >= 15, "flags missing")
            try dcExpect(r.prefix(20).filter { $0.headshot != nil }.count >= 10, "photos missing")
            return "\(r.count) players"
        }
        add("Diagnostics", "Tennis headshots") {
            // Top 100: how many photos each source delivers (ESPN, then ATP Tour, then SofaScore).
            let r = try await Tennis.rankings().prefix(100)
            var espn = 0, atp = 0, sofa = 0, none: [String] = []
            for p in r {
                if let h = p.headshot, await ImageStore.shared.image(h) != nil { espn += 1; continue }
                if await TennisPhotos.atpHeadshot(p.name) != nil { atp += 1; continue }
                if await TennisPhotos.sofascoreHeadshot(p.name) != nil { sofa += 1; continue }
                none.append(p.name)
            }
            return "\(espn + atp + sofa) of \(r.count) have photos: ESPN \(espn), ATP Tour \(atp), SofaScore \(sofa)"
                + (none.isEmpty ? "" : " || none: " + none.prefix(30).joined(separator: ", "))
        }
        add("Tennis", "Laver Cup") {
            let y = Calendar.current.component(.month, from: Date()) >= 10 ? dcYear : dcYear - 1
            let d = try await LaverCup.load(year: y, finished: true)
            try dcExpect(!d.matches.isEmpty, "no matches")
            return "\(y): Europe \(d.europe) – World \(d.world)"
        }
        add("Tennis", "Davis Cup") {
            let y = dcYear - 1   // last finished Finals
            let ties = try await DavisCup.load("\(y) Davis Cup Finals", finished: true)
            try dcExpect(!ties.isEmpty, "no ties")
            return "\(y): \(ties.count) ties"
        }

        // MARK: Cycling (Wikipedia)
        add("Cycling", "Grand Tours") {
            var out: [String] = []
            for def in TourDef.all {
                let y = CyclingService.isFinished(def, dcYear) ? dcYear : dcYear - 1
                let e = try await CyclingService.load(def, year: y)
                try dcExpect(e.stages.count >= 18, "\(def.short) \(y): \(e.stages.count) stages")
                try dcExpect(!(e.classifications[.gc] ?? []).isEmpty, "\(def.short) \(y): no GC")
                out.append("\(def.short) \(e.stages.count)")
            }
            return out.joined(separator: ", ")
        }
        add("Cycling", "WorldTour calendar") {
            let races = try await WorldTour.calendar(dcYear)
            try dcExpect(races.count >= 25, "only \(races.count) races")
            return "\(races.count) races"
        }
        add("Cycling", "One-day race") {
            let races = try await WorldTour.calendar(dcYear)
            guard let r = races.last(where: { $0.start != nil && $0.start == $0.end && ($0.end ?? .distantFuture) < Date() }) else {
                throw DataCheckFailure(message: "no finished one-day race")
            }
            let res = try await WorldTour.oneDay(r)
            try dcExpect(res.results.count >= 5, "\(r.name): \(res.results.count) results")
            return "\(r.name): winner \(res.results.first?.name ?? "?")"
        }
        add("Cycling", "Rider page") {
            let p = try await CyclingPeople.rider("Tadej Pogačar")
            try dcExpect(!p.teams.isEmpty, "no team history")
            try dcExpect(!p.majorWins.isEmpty, "no major wins")
            return "\(p.teams.count) teams, \(p.majorWins.count) win categories"
        }
        add("Cycling", "Team page") {
            let p = try await CyclingPeople.rider("Tadej Pogačar")
            guard let team = p.currentTeam else { throw DataCheckFailure(message: "rider has no current team") }
            let t = try await CyclingPeople.team(team)
            try dcExpect(t.roster != nil, "\(team): no roster")
            return team
        }

        // MARK: Diagnostics (always pass; the detail shows what the sources contain)
        add("Diagnostics", "Standings names") {
            // iPhone 13: the team column is ~98 pt wide. Names use 14 pt, then 12.5 pt, then a short form.
            let big = UIFont.systemFont(ofSize: 14, weight: .semibold)
            let small = UIFont.systemFont(ofSize: 12.5, weight: .semibold)
            let column: CGFloat = 98
            var smaller: [String] = []
            var shortened: [String] = []
            for id in ["epl", "bl1", "bl2", "ucl", "uel", "uecl", "prem"] {
                guard let league = League.byId(id) else { continue }
                let groups = (try? await ESPN.standings(league, divisions: false)) ?? []
                for row in groups.flatMap(\.rows) {
                    let name = tableName(row.short)
                    func w(_ f: UIFont) -> CGFloat { (name as NSString).size(withAttributes: [.font: f]).width }
                    if w(small) > column { shortened.append("\(name) → \(shortForm(name))") }
                    else if w(big) > column { smaller.append(name) }
                }
            }
            return "\(shortened.count) shortened, \(smaller.count) in smaller text" +
                (shortened.isEmpty ? "" : " || shortened: " + Set(shortened).sorted().joined(separator: ", ")) +
                (smaller.isEmpty ? "" : " || smaller: " + Set(smaller).sorted().joined(separator: ", "))
        }
        add("Diagnostics", "Rugby squads") {
            let names = try await ESPN.standings(dcLeague("prem"), divisions: false).flatMap(\.rows).map(\.name)
            var out: [String] = []
            for n in names {
                let squad = await RugbySquad.load(teamName: n)
                if squad.isEmpty {
                    let why = await RugbySquad.diagnose(teamName: n)
                    out.append("\(n): EMPTY -> \(why)")
                }
                else { out.append("\(n): \(squad.count)") }
            }
            return out.joined(separator: " || ")
        }
        add("Diagnostics", "Tennis logos") {
            let season = try await Tennis.season(dcYear)
            var missing: [String] = []
            var found = 0
            for t in season where t.tier != .team {
                let logo = await TournamentLogos.logo(t)
                if logo != nil { found += 1 } else { missing.append(t.name) }
            }
            var traces: [String] = []
            for t in season where t.tier != .team && missing.contains(t.name) {
                guard traces.count < 3 else { break }
                let title = TournamentLogos.articleTitle(t)
                traces.append("\(t.name): " + (await WikiLogo.eventLogoTrace(english: title, germanQueries: TournamentLogos.germanQueries(t))))
            }
            return "\(found) of \(found + missing.count) have logos || " + traces.joined(separator: " || ") + " || missing: " + missing.joined(separator: ", ")
        }
        add("Diagnostics", "Race logos") {
            let races = try await WorldTour.calendar(dcYear)
            var missing: [String] = []
            for r in races {
                let logo = await RaceLogos.logo(r)
                if logo == nil { missing.append(r.name) }
            }
            var traces: [String] = []
            for name in missing.prefix(3) {
                traces.append("\(name): " + (await WikiLogo.eventLogoTrace(english: name, germanQueries: RaceLogos.germanQueries(name))))
            }
            return "\(races.count - missing.count) of \(races.count) have logos || " + traces.joined(separator: " || ") + " || missing: " + missing.joined(separator: ", ")
        }
        add("Diagnostics", "Cycling teams") {
            let tour = TourDef.all[1]
            let y = CyclingService.isFinished(tour, dcYear) ? dcYear : dcYear - 1
            let e = try await CyclingService.load(tour, year: y)
            var out: [String] = []
            var names = e.teams.prefix(24).map(\.name)
            if !names.contains(where: { $0.contains("Movistar") }) { names.append("Movistar Team") }
            var bad = 0
            for n in names {
                let (title, s) = await CyclingPeople.teamArticle(n)
                let p = try? await CyclingPeople.team(n)
                let ok = s != nil && p?.image != nil && p?.roster != nil && p?.wins != nil
                if !ok { bad += 1 }
                out.append("\(ok ? "OK" : "MISSING") \(n) -> '\(title)' logo=\(p?.image?.lastPathComponent ?? "-") roster=\(p?.roster != nil) wins=\(p?.wins != nil)" + (ok ? "" : " [\(p?.trace ?? "")]"))
            }
            out.insert("\(names.count - bad) of \(names.count) complete", at: 0)
            return out.joined(separator: " || ")
        }

        add("Cycling", "UCI World Tour ranking") {
            for y in [dcYear, dcYear - 1] {
                let r = try await CyclingRankings.rankings(y)
                if !r.riders.isEmpty { return "\(y): \(r.riders.count) riders (\(r.riders.first?.name ?? "?")), \(r.teams.count) teams" }
            }
            // Report what the article has, to fix the parser.
            var report: [String] = []
            for title in CyclingRankings.articles(dcYear) {
                guard let url = CyclingService.wikiURL(title) else { continue }
                do {
                    let html = try await HTTP.shared.text(url, maxAge: 3600)
                    let heads = WikiHTML.tables(in: html).prefix(12).map { "[" + ($0.rows.first ?? []).prefix(6).joined(separator: "/") + "]" }
                    report.append("\(title): " + heads.joined(separator: " "))
                } catch { report.append("\(title): \(error)") }
            }
            throw DataCheckFailure(message: "no ranking table || " + report.joined(separator: " || "))
        }
        add("Cycling", "Team lists") {
            let wt = try await CyclingTeams.worldTeams()
            let pro = (try? await CyclingTeams.proTeams()) ?? []
            try dcExpect(wt.count >= 15, "only \(wt.count) WorldTeams: \(wt.prefix(5).map(\.name))")
            return "\(wt.count) WorldTeams (\(wt.first?.name ?? "?")), \(pro.count) ProTeams"
        }
        add("Cycling", "Win leaders") {
            let list = try await CyclingRankings.winLeaders(dcYear)
            try dcExpect(!list.isEmpty, "no wins counted")
            return "\(list.first?.name ?? "?") \(list.first?.wins ?? 0) wins"
        }

        // MARK: Photos and logos
        add("Images", "FotMob player photo") {
            let url = await FotMob.photo(name: "Erling Haaland", team: "Manchester City")
            guard let url else { throw DataCheckFailure(message: "player not found") }
            let img = await ImageStore.shared.image(url)
            try dcExpect(img != nil, "photo doesn't load")
            return "OK"
        }
        add("Images", "Competition logos") {
            let urls: [URL?] = [LogoAssets.nbaCup, LogoAssets.atp, LogoAssets.uciWorldTour,
                                LogoAssets.australianOpen, LogoAssets.rolandGarros, LogoAssets.wimbledon, LogoAssets.usOpen,
                                LogoAssets.giro, LogoAssets.tour, LogoAssets.vuelta]
            var broken: [String] = []
            for case let u? in urls {
                if await ImageStore.shared.image(u) == nil { broken.append(u.lastPathComponent) }
            }
            try dcExpect(broken.isEmpty, "not loading: " + broken.joined(separator: ", "))
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
                group.addTask { await dcRun(c) }
                next += 1
            }
            for await r in group {
                results.append(r)
                await progress(r)
                if next < checks.count {
                    let c = checks[next]
                    group.addTask { await dcRun(c) }
                    next += 1
                }
            }
        }
        let order = Dictionary(uniqueKeysWithValues: checks.enumerated().map { ($1.group + "/" + $1.name, $0) })
        return results.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
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

// File-level helpers (names inside the check closures resolve more reliably than enum members).

/// Throws with `message` unless `condition` holds.
func dcExpect(_ condition: Bool, _ message: @autoclosure () -> String) throws {
    if !condition { throw DataCheckFailure(message: message()) }
}

func dcLeague(_ id: String) -> League { League.byId(id)! }

var dcYear: Int { Calendar.current.component(.year, from: Date()) }

func dcDaysBack(_ n: Int) -> [Date] {
    let today = Calendar.current.startOfDay(for: Date())
    return (0...n).map { Calendar.current.date(byAdding: .day, value: -$0, to: today)! }
}

func dcRun(_ c: DataChecks.Check) async -> DataCheckResult {
    let t0 = Date()
    do {
        let detail = try await c.run()
        return DataCheckResult(group: c.group, name: c.name, ok: true, detail: detail, seconds: Date().timeIntervalSince(t0))
    } catch {
        return DataCheckResult(group: c.group, name: c.name, ok: false, detail: error.localizedDescription, seconds: Date().timeIntervalSince(t0))
    }
}
