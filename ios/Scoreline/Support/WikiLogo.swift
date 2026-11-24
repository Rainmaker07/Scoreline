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

    // MARK: Logos of events (tennis tournaments, cycling races)

    private static var cache: [String: URL?] = [:]

    static func articleURL(_ title: String, lang: String) -> URL? {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~()'!")
        guard let enc = title.replacingOccurrences(of: " ", with: "_").addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://\(lang).wikipedia.org/api/rest_v1/page/html/\(enc)")
    }

    /// The infobox logo of an article: an image named "...logo...", else the first real
    /// image inside the first table (the infobox), skipping flags and small icons.
    static func infoboxLogo(in html: String) -> URL? {
        let re = try? NSRegularExpression(pattern: #"<img[^>]*?src="(//upload\.wikimedia\.org/[^"]+)"[^>]*>"#)
        func images(_ s: String) -> [(url: String, tag: String)] {
            let ns = s as NSString
            return (re?.matches(in: s, range: NSRange(location: 0, length: ns.length)) ?? []).map {
                (ns.substring(with: $0.range(at: 1)), ns.substring(with: $0.range))
            }
        }
        func usable(_ u: String, _ tag: String) -> Bool {
            let l = u.lowercased()
            if ["flag", "flagge", "icon", "symbol", "pictogram", "commons-logo", "wiktionary", "edit-"].contains(where: { l.contains($0) }) { return false }
            if let w = tag.range(of: #"width="(\d+)""#, options: .regularExpression),
               let n = Int(tag[w].filter(\.isNumber)), n < 50 { return false }
            return true
        }
        guard let start = html.range(of: "<table") else { return nil }
        let end = html.range(of: "</table>", range: start.upperBound..<html.endIndex)?.upperBound ?? html.endIndex
        let box = String(html[start.lowerBound..<end])
        let inBox = images(box).filter { usable($0.url, $0.tag) }
        let pick = inBox.first { $0.url.lowercased().contains("logo") } ?? inBox.first
            ?? images(html).first { $0.url.lowercased().contains("logo") && usable($0.url, $0.tag) }
        return pick.flatMap { URL(string: "https:" + $0.url) }
    }

    /// Logo for an event: English article first, then the German article found by search.
    static func eventLogo(english: String, germanQuery: String) async -> URL? {
        let key = english + "|" + germanQuery
        if let hit = cache[key] { return hit }
        var url: URL?
        if let u = articleURL(english, lang: "en"), let html = try? await HTTP.shared.text(u, maxAge: 86_400 * 14) {
            url = infoboxLogo(in: html)
        }
        if url == nil,
           let q = germanQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let s = URL(string: "https://de.wikipedia.org/w/rest.php/v1/search/page?q=\(q)&limit=3"),
           let j = try? await HTTP.shared.json(s, maxAge: 86_400 * 14) {
            for page in j["pages"].array {
                guard let t = page["title"].string, let u = articleURL(t, lang: "de"),
                      let html = try? await HTTP.shared.text(u, maxAge: 86_400 * 14),
                      let logo = infoboxLogo(in: html) else { continue }
                url = logo
                break
            }
        }
        cache[key] = url
        return url
    }
}
