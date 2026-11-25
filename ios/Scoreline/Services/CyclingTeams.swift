import Foundation

/// UCI WorldTeams and ProTeams of the current season, from the "Current teams" tables of
/// Wikipedia's "UCI WorldTeam" and "UCI ProTeam" articles.
enum CyclingTeams {
    struct Team: Identifiable, Hashable {
        var id: String { name }
        let name: String
        let country: String?
    }

    static func list(_ article: String) async throws -> [Team] {
        guard let url = CyclingService.wikiURL(article) else { return [] }
        let html = try await HTTP.shared.text(url, maxAge: 86_400)
        let tables = WikiHTML.tables(in: html)
        // The current teams table: a "Team" column and a country / nationality column.
        guard let t = tables.first(where: { $0.column("team") != nil && ($0.column("countr") != nil || $0.column("nation") != nil || $0.column("licen") != nil) })
                ?? tables.first(where: { $0.column("team") != nil }) else { return [] }
        let nameCol = t.column("team") ?? 0
        let countryCol = t.column("countr") ?? t.column("nation") ?? t.column("licen")
        var seen = Set<String>()
        return t.rows.dropFirst().compactMap { r in
            guard r.count > nameCol else { return nil }
            let name = r[nameCol].replacingOccurrences(of: #"\[.*?\]"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count < 60, seen.insert(name).inserted else { return nil }
            let country = countryCol.flatMap { r.count > $0 ? r[$0].trimmingCharacters(in: .whitespaces) : nil }
            return Team(name: name, country: country?.isEmpty == true ? nil : country)
        }
    }

    static func worldTeams() async throws -> [Team] { try await list("UCI WorldTeam") }
    /// ProTeams without the WorldTeams (the ProTeam article's table lists both tiers).
    static func proTeams() async throws -> [Team] {
        let pro = try await list("UCI ProTeam")
        let world = (try? await worldTeams()) ?? []
        func key(_ s: String) -> String {
            s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en"))
                .components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        }
        let worldKeys = Set(world.map { key($0.name) })
        return pro.filter { t in
            let k = key(t.name)
            return !worldKeys.contains(k) && !worldKeys.contains(where: { k.contains($0) || $0.contains(k) })
        }
    }
}
