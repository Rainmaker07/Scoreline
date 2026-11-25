import Foundation

/// UCI WorldTeams and ProTeams of the current season, from the "Current teams" tables of
/// Wikipedia's "UCI WorldTeam" and "UCI ProTeam" articles.
enum CyclingTeams {
    struct Team: Identifiable, Hashable {
        var id: String { name }
        let name: String
        let country: String?
    }

    /// Every table in the article that has a "Team" column, parsed into teams.
    static func tables(_ article: String) async throws -> [[Team]] {
        guard let url = CyclingService.wikiURL(article) else { return [] }
        let html = try await HTTP.shared.text(url, maxAge: 86_400)
        return WikiHTML.tables(in: html).compactMap { t -> [Team]? in
            guard let nameCol = t.column("team") else { return nil }
            let countryCol = t.column("countr") ?? t.column("nation") ?? t.column("licen")
            var seen = Set<String>()
            let teams: [Team] = t.rows.dropFirst().compactMap { r in
                guard r.count > nameCol else { return nil }
                let name = r[nameCol].replacingOccurrences(of: #"\[.*?\]"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, name.count < 60, seen.insert(name).inserted else { return nil }
                let country = countryCol.flatMap { r.count > $0 ? r[$0].trimmingCharacters(in: .whitespaces) : nil }
                return Team(name: name, country: country?.isEmpty == true ? nil : country)
            }
            return teams.count >= 5 ? teams : nil
        }
    }

    static func list(_ article: String) async throws -> [Team] {
        try await tables(article).first ?? []
    }

    static func key(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    }

    static func worldTeams() async throws -> [Team] { try await list("UCI WorldTeam") }
    /// ProTeams: the table in the ProTeam article with the fewest WorldTeams in it, without
    /// any WorldTeams that are listed there too.
    static func proTeams() async throws -> [Team] {
        let world = Set(((try? await worldTeams()) ?? []).map { key($0.name) }.filter { !$0.isEmpty })
        func isWorld(_ t: Team) -> Bool {
            let k = key(t.name)
            return world.contains(k) || world.contains { $0.count > 5 && (k.contains($0) || $0.contains(k)) }
        }
        var candidates = try await tables("UCI ProTeam")
        if candidates.allSatisfy({ $0.allSatisfy(isWorld) }) {
            candidates += (try? await tables("List of UCI ProTeams")) ?? []
        }
        let best = candidates.map { $0.filter { !isWorld($0) } }.max { $0.count < $1.count } ?? []
        return best
    }
}
