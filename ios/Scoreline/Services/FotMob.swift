import Foundation

/// Football player headshots from FotMob (ESPN has none).
enum FotMob {
    private static var cache: [String: URL?] = [:]

    static func photo(name: String, team: String) async -> URL? {
        let key = "\(name)|\(team)"
        if let hit = cache[key] { return hit }
        guard let q = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.fotmob.com/api/data/search/suggest?term=\(q)&lang=en"),
              let d = try? await HTTP.shared.json(url, maxAge: 86_400 * 14) else { return nil }
        let players = d.array.flatMap { $0["suggestions"].array }.filter { $0["type"].str == "player" && $0["isCoach"].bool != true }
        let teamWords = Set(normalize(team).split(separator: " ").map(String.init).filter { $0.count > 2 && !["fc", "afc", "sc", "the"].contains($0) })
        // Same name and the club matches; otherwise a single unambiguous result.
        let byName = players.filter { normalize($0["name"].str) == normalize(name) }
        let pick = byName.first { p in
            let words = Set(normalize(p["teamName"].str).split(separator: " ").map(String.init))
            return !teamWords.isDisjoint(with: words)
        } ?? (byName.count == 1 ? byName.first : nil)
        let result = pick.flatMap { URL(string: "https://images.fotmob.com/image_resources/playerimages/\($0["id"].str).png") }
        cache[key] = result
        return result
    }

    private static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en"))
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
