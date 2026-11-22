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
