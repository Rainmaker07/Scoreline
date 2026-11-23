import Foundation

/// Competitions read from Wikipedia articles: NBA Cup groups, Davis Cup and
/// Laver Cup results. Generic: each section's tables, minus navigation boxes.
struct WikiSectionTables: Identifiable {
    var id: String { title }
    let title: String
    let tables: [WikiTable]
    let results: [String]
}

enum WikiEvents {
    static func page(_ title: String, finished: Bool) async throws -> String {
        guard let url = CyclingService.wikiURL(title) else { throw FetchError.parse("Bad title") }
        return try await HTTP.shared.text(url, maxAge: finished ? 86_400 * 30 : 1800, permanent: finished)
    }

    /// Sections with standings-like tables and game results ("Team A 110, Team B 94").
    static func sections(_ title: String, finished: Bool) async throws -> [WikiSectionTables] {
        let html = try await page(title, finished: finished)
        return await Task.detached(priority: .userInitiated) { () -> [WikiSectionTables] in
            WikiHTML.chunks(in: html).compactMap { chunk -> WikiSectionTables? in
                let t = chunk.title.lowercased()
                if ["references", "external links", "see also", "notes", "media coverage", "prize money", "broadcasting", "pots", "draw", "draw results", "format", "qualification", "venue", "venues", "team nominations", "seeds", "entrants"].contains(t) { return nil }
                var tables: [WikiTable] = []
                var results: [String] = []
                for table in WikiHTML.tables(in: chunk.html) {
                    guard table.rows.count >= 2, let header = table.rows.first else { continue }
                    let headText = header.joined(separator: " ").lowercased()
                    if headText.contains("vte") || headText.contains("tournament information") || headText.contains("information") { continue }
                    // Game box: first row "Team A 110, Team B 94" repeated across columns.
                    if table.rows.count <= 4, let first = header.first, first.contains(","), header.allSatisfy({ $0 == first }) {
                        results.append(first)
                        continue
                    }
                    // Tie header: "Italy | Venue, date | Venue, date | South Korea".
                    if header.count == 4, header[1] == header[2], !header[0].isEmpty {
                        results.append("\(header[0]) vs \(header[3]) · \(header[1])")
                        continue
                    }
                    // Skip tables that are still empty (future ties, blank brackets).
                    let cells = table.rows.dropFirst().flatMap { $0 }
                    let filled = cells.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
                    if cells.isEmpty || filled * 3 < cells.count { continue }
                    if header.count >= 3 { tables.append(table) }
                }
                if tables.isEmpty && results.isEmpty { return nil }
                return WikiSectionTables(title: chunk.title, tables: tables, results: results)
            }
        }.value
    }
}

// MARK: - Laver Cup

struct LaverMatch: Identifiable {
    let id: Int
    let day: String
    let type: String
    let europe: String
    let world: String
    let score: String
    let europeWon: Bool?
    let pointsAfter: String
}

struct LaverCupData {
    let europe: Int
    let world: Int
    let matches: [LaverMatch]
}

enum LaverCup {
    static func load(year: Int, finished: Bool) async throws -> LaverCupData {
        let html = try await WikiEvents.page("\(year) Laver Cup", finished: finished)
        return await Task.detached(priority: .userInitiated) { () -> LaverCupData in
            let tables = WikiHTML.tables(in: html)
            guard let t = tables.first(where: { $0.column("team europe") != nil && $0.column("team world") != nil }) else {
                return LaverCupData(europe: 0, world: 0, matches: [])
            }
            let c = { (name: String) in t.column(name) }
            var prev = (0, 0)
            var out: [LaverMatch] = []
            for (i, r) in t.rows.dropFirst().enumerated() {
                func cell(_ k: Int?) -> String { guard let k, k < r.count else { return "" }; return r[k] }
                let pts = cell(c("points"))
                let nums = pts.replacingOccurrences(of: "–", with: "-").split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                var won: Bool?
                if nums.count == 2 {
                    if nums[0] > prev.0 { won = true } else if nums[1] > prev.1 { won = false }
                    prev = (nums[0], nums[1])
                }
                let europe = cell(c("team europe")), world = cell(c("team world"))
                if europe.isEmpty && world.isEmpty { continue }
                out.append(LaverMatch(id: i, day: cell(c("day")), type: cell(c("match type")), europe: europe, world: world,
                                      score: cell(c("score")), europeWon: won, pointsAfter: pts))
            }
            return LaverCupData(europe: prev.0, world: prev.1, matches: out)
        }.value
    }
}

// MARK: - Davis Cup

struct DavisTie: Identifiable {
    let id: Int
    let round: String
    let teamA: String
    let teamB: String
    let venue: String
    let rubbers: [[String]]

    var decided: Bool { teamA != "TBD" && teamB != "TBD" }
}

enum DavisCup {
    static let codes: [String: String] = [
        "italy": "ita", "south korea": "kor", "czech republic": "cze", "czechia": "cze", "canada": "can",
        "great britain": "gbr", "germany": "ger", "austria": "aut", "spain": "esp", "argentina": "arg",
        "australia": "aus", "united states": "usa", "france": "fra", "netherlands": "ned", "serbia": "srb",
        "croatia": "cro", "belgium": "bel", "chile": "chi", "finland": "fin", "denmark": "den", "norway": "nor",
        "switzerland": "sui", "japan": "jpn", "portugal": "por", "hungary": "hun", "kazakhstan": "kaz",
        "brazil": "bra", "colombia": "col", "sweden": "swe", "poland": "pol", "greece": "gre", "slovakia": "svk",
    ]

    static func flag(_ country: String) -> URL? {
        codes[country.lowercased()].flatMap { URL(string: "https://a.espncdn.com/i/teamlogos/countries/500/\($0).png") }
    }

    static func load(_ title: String, finished: Bool) async throws -> [DavisTie] {
        let html = try await WikiEvents.page(title, finished: finished)
        return await Task.detached(priority: .userInitiated) { () -> [DavisTie] in
            var ties: [DavisTie] = []
            for chunk in WikiHTML.chunks(in: html) {
                let round = chunk.title
                let lower = round.lowercased()
                guard ["final", "semifinal", "quarterfinal", "round", "knockout"].contains(where: lower.contains),
                      !lower.contains("nomination") else { continue }
                var current: (a: String, b: String, venue: String)?
                var rubbers: [[String]] = []
                func flush() {
                    if let c = current { ties.append(DavisTie(id: ties.count, round: round, teamA: c.a, teamB: c.b, venue: c.venue, rubbers: rubbers)) }
                    current = nil; rubbers = []
                }
                for t in WikiHTML.tables(in: chunk.html) {
                    guard let h = t.rows.first else { continue }
                    if h.count == 4, h[1] == h[2], !h[0].isEmpty {
                        flush()
                        func team(_ s: String) -> String { s.contains("[[") || s.isEmpty ? "TBD" : s }
                        current = (team(h[0]), team(h[3]), h[1])
                    } else if current != nil {
                        for r in t.rows.dropFirst() {
                            let cells = r.map { $0.trimmingCharacters(in: .whitespaces) }
                            // Keep rubbers that have players (text beyond the rubber number and set scores).
                            if cells.dropFirst().contains(where: { !$0.isEmpty && Int($0) == nil }) { rubbers.append(cells.filter { !$0.isEmpty }) }
                        }
                    }
                }
                flush()
            }
            return ties
        }.value
    }
}
