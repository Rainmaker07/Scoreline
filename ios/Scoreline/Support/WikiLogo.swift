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

    private static let imgRegex = try? NSRegularExpression(pattern: #"<img[^>]*?src="(?:https:)?(//(?:upload|thumb)\.wikimedia\.org/[^"?]+)[^"]*"[^>]*>"#)

    private static func images(_ s: String) -> [(url: String, tag: String)] {
        let ns = s as NSString
        return (imgRegex?.matches(in: s, range: NSRange(location: 0, length: ns.length)) ?? []).map {
            (ns.substring(with: $0.range(at: 1)), ns.substring(with: $0.range))
        }
    }

    private static func usable(_ u: String, _ tag: String) -> Bool {
        let l = u.lowercased()
        if ["flag", "flagge", "icon", "symbol", "pictogram", "commons-logo", "wiktionary", "edit-", "ambox", "question_book",
            "padlock", "wikidata", "loudspeaker", "disambig"].contains(where: { l.contains($0) }) { return false }
        if l.contains("current_event") { return false }
        // Series logos (ATP 250, UCI World Tour) aren't the event's own logo.
        let file = (URL(string: "https:" + u)?.lastPathComponent ?? l).lowercased()
        if file.contains("atp") && ["250", "500", "1000", "world_tour", "tour_logo", "masters"].contains(where: { file.contains($0) }) { return false }
        if file.contains("uci") && ["world", "tour", "logo", "proseries"].contains(where: { file.contains($0) }) { return false }
        // Thumbnail size in the path ("/40px-Name.svg.png"): small ones are icons.
        if let r = u.range(of: #"/\d+px-"#, options: .regularExpression),
           let n = Int(u[r].filter(\.isNumber)), n < 60 { return false }
        if let w = tag.range(of: #"width="(\d+)""#, options: .regularExpression),
           let n = Int(tag[w].filter(\.isNumber)), n < 50 { return false }
        return true
    }

    /// The HTML of the article's infobox: the first table whose class says infobox,
    /// else the first table that isn't a maintenance box.
    static func infobox(in html: String) -> String? {
        var from = html.startIndex
        var fallback: String?
        while let start = html.range(of: "<table", range: from..<html.endIndex) {
            let tagEnd = html.range(of: ">", range: start.upperBound..<html.endIndex)?.upperBound ?? html.endIndex
            let tag = html[start.lowerBound..<tagEnd].lowercased()
            // Find the matching </table> (infoboxes can contain nested tables).
            var depth = 1
            var cursor = tagEnd
            var end = html.endIndex
            while depth > 0 {
                guard let close = html.range(of: "</table>", range: cursor..<html.endIndex) else { break }
                if let open = html.range(of: "<table", range: cursor..<close.lowerBound) {
                    depth += 1
                    cursor = open.upperBound
                } else {
                    depth -= 1
                    cursor = close.upperBound
                    if depth == 0 { end = close.upperBound }
                }
            }
            let box = String(html[start.lowerBound..<end])
            if tag.contains("infobox") || tag.contains("toccolours") { return box }
            if fallback == nil, !["ambox", "metadata", "box-", "navbox", "sidebar", "mbox"].contains(where: { tag.contains($0) }) {
                fallback = box
            }
            if html.distance(from: html.startIndex, to: start.lowerBound) > 200_000 { break }
            from = end
        }
        return fallback
    }

    /// The article's lead section (before the first heading), which holds the infobox.
    static func lead(in html: String) -> String {
        let markers = ["data-mw-section-id=\"1\"", "<h2"]
        let cut = markers.compactMap { html.range(of: $0)?.lowerBound }.min() ?? html.endIndex
        return String(html[html.startIndex..<cut])
    }

    /// Images of the infobox, else of the lead section.
    private static func boxImages(_ html: String) -> [(url: String, tag: String)] {
        let box = images(infobox(in: html) ?? "").filter { usable($0.url, $0.tag) }
        return box.isEmpty ? images(lead(in: html)).filter { usable($0.url, $0.tag) } : box
    }

    /// File names of the usable images in the infobox (for diagnostics).
    static func infoboxImages(in html: String) -> [String] {
        boxImages(html).map { URL(string: "https:" + $0.url)?.lastPathComponent ?? $0.url }
    }

    /// Raw facts for diagnostics: image count and the first image tags.
    static func imageDebug(in html: String) -> String {
        let all = html.components(separatedBy: "<img").dropFirst()
        let leadCount = lead(in: html).components(separatedBy: "<img").count - 1
        let firstTags = all.prefix(2).map { "<img" + String($0.prefix(220)) }
        return "\(all.count) img (\(leadCount) in lead), box \(infobox(in: html)?.count ?? 0) chars: " + firstTags.joined(separator: " ")
    }

    /// The infobox logo of an article: an image named "...logo...", else (unless `strict`)
    /// the first real image inside the infobox, skipping flags and small icons.
    /// `strict` only accepts images named logo or drawings (SVG), not photos.
    static func infoboxLogo(in html: String, strict: Bool = false, title: String? = nil) -> URL? {
        let inBox = boxImages(html)
        func name(_ u: String) -> String { (URL(string: "https:" + u)?.lastPathComponent ?? u).lowercased() }
        let notLogo = ["map", "karte", "location", "route", "profile", "profil", "jersey", "maillot", "kit_", "trikot", "trophy", "pokal"]
        let named = inBox.first { name($0.url).contains("logo") }
        let drawing = inBox.first { img in let n = name(img.url); return n.contains(".svg") && !notLogo.contains { w in n.contains(w) } }
            ?? inBox.first { img in let n = name(img.url); return n.hasSuffix(".png") && !notLogo.contains { w in n.contains(w) } }
            ?? title.flatMap { (t: String) -> (url: String, tag: String)? in
                // A photo-format file named after the event itself ("UAE_Tour.jpg") is its logo.
                let key = t.lowercased().filter { $0.isLetter || $0.isNumber }
                return key.count < 4 ? nil : inBox.first { img in
                    let stem = name(img.url).replacingOccurrences(of: #"^\d+px-"#, with: "", options: .regularExpression)
                        .components(separatedBy: ".").first?.filter { $0.isLetter || $0.isNumber } ?? ""
                    return stem == key
                }
            }
        let any = inBox.first { img in let n = name(img.url); return !notLogo.contains { w in n.contains(w) } }
        let pick = named ?? drawing ?? (strict ? nil : any)
            ?? images(html).first { name($0.url).contains("logo") && usable($0.url, $0.tag) }
        return pick.flatMap { URL(string: "https:" + $0.url) }
    }

    /// Logo for an event: English article first, then the German article found by search.
    static func eventLogo(english: String, germanQueries: [String]) async -> URL? {
        let key = english + "|" + germanQueries.joined(separator: "|")
        if let hit = cache[key] { return hit }
        var url: URL?
        if !english.isEmpty, let u = articleURL(english, lang: "en"), let html = try? await HTTP.shared.text(u, maxAge: 86_400 * 14) {
            url = infoboxLogo(in: html, strict: true, title: english)
        }
        var tried = Set<String>()
        queries: for query in germanQueries where url == nil {
            guard let q = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
                  let s = URL(string: "https://de.wikipedia.org/w/rest.php/v1/search/page?q=\(q)&limit=3"),
                  let j = try? await HTTP.shared.json(s, maxAge: 86_400 * 14) else { continue }
            for page in j["pages"].array {
                guard let t = page["title"].string, tried.insert(t).inserted, let u = articleURL(t, lang: "de"),
                      let html = try? await HTTP.shared.text(u, maxAge: 86_400 * 14),
                      let logo = infoboxLogo(in: html, strict: true, title: t) else { continue }
                url = logo
                break queries
            }
        }
        cache[key] = url
        return url
    }

    /// Step-by-step report of the logo lookup (for the data checks).
    static func eventLogoTrace(english: String, germanQueries: [String]) async -> String {
        var out: [String] = []
        if let u = articleURL(english, lang: "en") {
            do {
                let html = try await HTTP.shared.text(u, maxAge: 86_400 * 14)
                out.append("en ok, images [\(infoboxImages(in: html).prefix(4).joined(separator: ","))] {\(imageDebug(in: html))}")
            } catch { out.append("en \(error)") }
        }
        guard let germanQuery = germanQueries.first, let q = germanQuery.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let s = URL(string: "https://de.wikipedia.org/w/rest.php/v1/search/page?q=\(q)&limit=3") else { return out.joined(separator: "; ") }
        do {
            let j = try await HTTP.shared.json(s, maxAge: 86_400 * 14)
            for page in j["pages"].array {
                let t = page["title"].str
                guard let u = articleURL(t, lang: "de") else { continue }
                do {
                    let html = try await HTTP.shared.text(u, maxAge: 86_400 * 14)
                    out.append("de '\(t)' box \(infobox(in: html) != nil), images [\(infoboxImages(in: html).prefix(4).joined(separator: ","))]")
                } catch { out.append("de '\(t)' \(error)") }
            }
            if j["pages"].array.isEmpty { out.append("de search '\(germanQuery)': no results") }
        } catch { out.append("de search \(error)") }
        return out.joined(separator: "; ")
    }
}
