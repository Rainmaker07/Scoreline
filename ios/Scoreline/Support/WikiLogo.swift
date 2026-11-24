import Foundation

/// Team logos from Wikipedia for clubs ESPN has no logo for.
///
/// The URL `wikilogo:<article title>` is resolved by ImageStore: it reads the
/// article's summary (the infobox image, which is the club crest) and loads it.
enum WikiLogo {
    static let scheme = "wikilogo"

    /// ESPN name -> Wikipedia article, where they differ.
    static let titles: [String: String] = [
        "Bristol Rugby": "Bristol Bears",
        "Bristol Bears": "Bristol Bears",
        "Newcastle Falcons": "Newcastle Red Bulls",
    ]

    static func url(for title: String) -> URL? {
        let enc = title.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? title
        return URL(string: "\(scheme):\(enc)")
    }

    static func title(of url: URL) -> String? {
        guard url.scheme == scheme else { return nil }
        return String(url.absoluteString.dropFirst(scheme.count + 1)).removingPercentEncoding
    }

    /// The real image URL behind a `wikilogo:` URL.
    static func resolve(_ url: URL) async -> URL? {
        guard let title = title(of: url),
              let api = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/" +
                            (title.replacingOccurrences(of: " ", with: "_").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title)),
              let j = try? await HTTP.shared.json(api, maxAge: 86_400 * 30) else { return nil }
        return j["thumbnail"]["source"].url ?? j["originalimage"]["source"].url
    }
}
