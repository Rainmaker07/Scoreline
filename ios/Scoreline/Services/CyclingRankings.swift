import Foundation

/// UCI World Tour rankings (from the season's Wikipedia article) and win leaders
/// (counted from the WorldTour calendar: one-day wins, stage wins and overall wins).
enum CyclingRankings {
    struct Entry: Identifiable, Hashable {
        var id: String { name }
        let rank: Int
        let name: String
        let team: String?
        let country: String?
        let value: String
    }

    struct WinLeader: Identifiable, Hashable {
        var id: String { name }
        let name: String
        let country: String?
        let wins: Int
        let detail: String   // "2 races · 5 stages"
    }

    /// Individual and team ranking tables of "<year> UCI World Tour" (empty if the article has none).
    static func rankings(_ year: Int) async throws -> (riders: [Entry], teams: [Entry]) {
        guard let url = CyclingService.wikiURL("\(year) UCI World Tour") else { return ([], []) }
        let past = year < Calendar.current.component(.year, from: Date())
        let html = try await HTTP.shared.text(url, maxAge: past ? 86_400 * 60 : 21_600, permanent: past)
        let tables = WikiHTML.tables(in: html)
        func points(_ t: WikiTable) -> Int? { t.column("points") ?? t.column("pts") }
        let riderTable = tables.first { ($0.column("rider") != nil || $0.column("name") != nil) && points($0) != nil }
        let teamTable = tables.first { $0.column("team") != nil && $0.column("rider") == nil && $0.column("name") == nil && points($0) != nil }
        func parse(_ t: WikiTable?, riders: Bool) -> [Entry] {
            guard let t, let pc = points(t) else { return [] }
            let nameCol = riders ? (t.column("rider") ?? t.column("name") ?? 1) : (t.column("team") ?? 1)
            let teamCol = riders ? t.column("team") : nil
            return t.rows.dropFirst().enumerated().compactMap { i, r in
                guard r.count > max(nameCol, pc) else { return nil }
                let (name, country) = CyclingService.splitRider(r[nameCol])
                guard !name.isEmpty else { return nil }
                return Entry(rank: Int(r.first?.filter(\.isNumber) ?? "") ?? i + 1, name: name,
                             team: teamCol.flatMap { r.count > $0 ? r[$0] : nil },
                             country: country, value: r[pc])
            }
        }
        return (parse(riderTable, riders: true), parse(teamTable, riders: false))
    }

    /// Riders with the most wins this season across WorldTour races (one-day wins,
    /// stage wins and overall wins of stage races). Finished races are cached on device.
    static func winLeaders(_ year: Int) async throws -> [WinLeader] {
        let races = try await WorldTour.calendar(year).filter { ($0.start ?? .distantFuture) <= Date() }
        var raceWins: [String: Int] = [:], stageWins: [String: Int] = [:], countries: [String: String] = [:]
        // One-day races and overall winners straight from the calendar.
        for r in races { if let w = r.winner, !w.isEmpty { raceWins[w, default: 0] += 1 } }
        // Stage winners from each stage race (four at a time).
        let stageRaces = races.filter { !$0.isOneDay }
        let results: [[CyclingStage]] = await withTaskGroup(of: [CyclingStage].self) { group in
            var next = 0
            var out: [[CyclingStage]] = []
            while next < min(4, stageRaces.count) {
                let race = stageRaces[next]
                group.addTask { (try? await CyclingService.load(WorldTour.def(for: race), year: race.year))?.stages ?? [] }
                next += 1
            }
            for await stages in group {
                out.append(stages)
                if next < stageRaces.count {
                    let race = stageRaces[next]
                    group.addTask { (try? await CyclingService.load(WorldTour.def(for: race), year: race.year))?.stages ?? [] }
                    next += 1
                }
            }
            return out
        }
        for stages in results {
            for s in stages {
                guard let w = s.winner, !w.isEmpty, !w.lowercased().contains("team") else { continue }
                stageWins[w, default: 0] += 1
                if let c = s.winnerCountry { countries[w] = c }
            }
        }
        let names = Set(raceWins.keys).union(stageWins.keys)
        return names.map { n in
            let r = raceWins[n] ?? 0, s = stageWins[n] ?? 0
            let parts = [r > 0 ? "\(r) \(r == 1 ? "race" : "races")" : nil, s > 0 ? "\(s) \(s == 1 ? "stage" : "stages")" : nil]
            return WinLeader(name: n, country: countries[n], wins: r + s, detail: parts.compactMap { $0 }.joined(separator: " · "))
        }
        .sorted { ($0.wins, $1.name) > ($1.wins, $0.name) }
        .prefix(25).map { $0 }
    }
}
