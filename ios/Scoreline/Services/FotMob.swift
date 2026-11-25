import Foundation

/// Football player headshots from FotMob (ESPN has none).
enum FotMob {
    private static let cache = LockedCache<String, URL?>()

    static func photo(name: String, team: String) async -> URL? {
        let key = "\(name)|\(team)"
        if let hit = cache[key] { return hit }
        let teamWords = Set(normalize(team).split(separator: " ").map(String.init).filter { $0.count > 2 && !["fc", "afc", "sc", "the", "club"].contains($0) })
        func teamMatches(_ p: J) -> Bool {
            let words = Set(normalize(p["teamName"].str).split(separator: " ").map(String.init))
            return !teamWords.isEmpty && !teamWords.isDisjoint(with: words)
        }
        func players(_ term: String) async -> [J] {
            guard let q = term.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
                  let url = URL(string: "https://www.fotmob.com/api/data/search/suggest?term=\(q)&lang=en"),
                  let d = try? await HTTP.shared.json(url, maxAge: 86_400 * 14) else { return [] }
            return d.array.flatMap { $0["suggestions"].array }.filter { $0["type"].str == "player" && $0["isCoach"].bool != true }
        }
        let surname = lastName(name)
        // 1. Full name: same name at the same club, else one unambiguous result.
        let full = await players(name)
        let byName = full.filter { normalize($0["name"].str) == normalize(name) }
        var pick = byName.first(where: teamMatches) ?? (byName.count == 1 ? byName.first : nil)
            ?? full.first { teamMatches($0) && lastName($0["name"].str) == surname }
        // 2. Spelling variants ("Tasos" / "Anastasios", "Alexey" / "Aleksei"): surname and club.
        if pick == nil, surname.count >= 3 {
            pick = await players(surname).first { teamMatches($0) && similar(lastName($0["name"].str), surname) }
        }
        let result = pick.flatMap { URL(string: "https://images.fotmob.com/image_resources/playerimages/\($0["id"].str).png") }
        cache[key] = result
        return result
    }

    private static func lastName(_ s: String) -> String {
        normalize(s).split(separator: " ").last.map(String.init) ?? ""
    }

    /// Same surname allowing transliteration differences (ks/x, ei/ey, y/i).
    private static func similar(_ a: String, _ b: String) -> Bool {
        func fold(_ s: String) -> String {
            s.replacingOccurrences(of: "x", with: "ks").replacingOccurrences(of: "y", with: "i")
                .replacingOccurrences(of: "j", with: "i").replacingOccurrences(of: "ii", with: "i")
        }
        return a == b || fold(a) == fold(b)
    }

    private static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en"))
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Finds a player photo: the given headshot if it loads, else FotMob (football),
/// else the Wikipedia lead image. Results are remembered per player.
enum PlayerPhotos {
    private static let cache = LockedCache<String, URL?>()

    static func best(primary: URL?, name: String, team: String, football: Bool) async -> URL? {
        let key = "\(name)|\(team)"
        if let hit = cache[key] { return hit }
        var url: URL?
        if let primary, await ImageStore.shared.image(primary) != nil {
            url = primary
        }
        if url == nil, football {
            url = await FotMob.photo(name: name, team: team)
        }
        if url == nil, let s = await Wiki.summary(name),
           let d = s.description?.lowercased(),
           ["football", "soccer", "basketball", "baseball", "rugby", "tennis", "cyclist", "player"].contains(where: { d.contains($0) }) {
            url = s.image
        }
        cache[key] = url
        return url
    }
}
