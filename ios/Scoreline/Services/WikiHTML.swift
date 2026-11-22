import Foundation

/// Minimal HTML table / section extraction for Wikipedia's Parsoid HTML
/// (https://en.wikipedia.org/api/rest_v1/page/html/<title>).
///
/// Handles nested tables, rowspan/colspan and attribute values that contain `>`
/// (Parsoid stores JSON in `data-mw` attributes).
struct WikiTable {
    let caption: String
    let rows: [[String]]

    /// Index of the first column whose header contains `name` (case-insensitive).
    func column(_ name: String) -> Int? {
        guard let header = rows.first else { return nil }
        return header.firstIndex { $0.lowercased().contains(name.lowercased()) }
    }

    /// All column indexes whose header contains `name`.
    func columns(_ name: String) -> [Int] {
        guard let header = rows.first else { return [] }
        return header.indices.filter { header[$0].lowercased().contains(name.lowercased()) }
    }
}

struct WikiSection {
    let title: String
    let level: Int
    let paragraphs: [String]
}

enum WikiHTML {
    private static let tagPattern = #"<(?:[^>"']|"[^"]*"|'[^']*')*>"#

    private static func regex(_ p: String, _ opts: NSRegularExpression.Options = [.dotMatchesLineSeparators, .caseInsensitive]) -> NSRegularExpression {
        // Patterns are compile-time constants; a failure here is a programming error.
        try! NSRegularExpression(pattern: p, options: opts)
    }

    private static let reSup = regex(#"<sup\b(?:[^>"']|"[^"]*"|'[^']*')*>.*?</sup>"#)
    private static let reStyle = regex(#"<style\b.*?</style>"#)
    private static let reBr = regex(#"<br\s*/?>"#)
    private static let reTag = regex(tagPattern)
    private static let reSpace = regex(#"\s+"#)
    private static let reTableToken = regex(#"<table\b|</table>"#)
    private static let reCaption = regex(#"<caption\b(?:[^>"']|"[^"]*"|'[^']*')*>(.*?)</caption>"#)
    private static let reRow = regex(#"<tr\b(?:[^>"']|"[^"]*"|'[^']*')*>(.*?)</tr>"#)
    private static let reCell = regex(#"<(t[hd])\b((?:[^>"']|"[^"]*"|'[^']*')*)>(.*?)</t[hd]>"#)
    private static let reColspan = regex(#"colspan="?(\d+)"#)
    private static let reRowspan = regex(#"rowspan="?(\d+)"#)
    private static let reHeading = regex(#"<h([23])\b(?:[^>"']|"[^"]*"|'[^']*')*>(.*?)</h[23]>"#)
    private static let reParagraph = regex(#"<p\b(?:[^>"']|"[^"]*"|'[^']*')*>(.*?)</p>"#)

    private static func replace(_ re: NSRegularExpression, in s: String, with t: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: t)
    }

    private static func matches(_ re: NSRegularExpression, in s: String) -> [NSTextCheckingResult] {
        re.matches(in: s, range: NSRange(s.startIndex..., in: s))
    }

    private static func group(_ m: NSTextCheckingResult, _ i: Int, in s: String) -> String {
        guard let r = Range(m.range(at: i), in: s) else { return "" }
        return String(s[r])
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = s
        let named: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
            "&nbsp;": " ", "&ndash;": "–", "&mdash;": "—", "&minus;": "−", "&prime;": "′", "&Prime;": "″",
        ]
        for (k, v) in named { out = out.replacingOccurrences(of: k, with: v) }
        // numeric entities
        let re = regex(#"&#(x?)([0-9a-fA-F]+);"#)
        var result = ""
        var last = out.startIndex
        for m in matches(re, in: out) {
            guard let full = Range(m.range, in: out) else { continue }
            result += out[last..<full.lowerBound]
            let hex = !group(m, 1, in: out).isEmpty
            let digits = group(m, 2, in: out)
            if let code = UInt32(digits, radix: hex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                result.unicodeScalars.append(scalar)
            }
            last = full.upperBound
        }
        result += out[last...]
        return result
    }

    static func clean(_ html: String) -> String {
        var s = replace(reSup, in: html, with: "")
        s = replace(reStyle, in: s, with: "")
        s = replace(reBr, in: s, with: " ")
        s = replace(reTag, in: s, with: "")
        s = decodeEntities(s).replacingOccurrences(of: "\u{00a0}", with: " ")
        s = replace(reSpace, in: s, with: " ")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Every table in the document (any nesting depth), in document order.
    static func tables(in html: String) -> [WikiTable] {
        var stack: [String.Index] = []
        var found: [(start: String.Index, text: Substring)] = []
        for m in matches(reTableToken, in: html) {
            guard let r = Range(m.range, in: html) else { continue }
            if html[r].lowercased().hasPrefix("<table") {
                stack.append(r.lowerBound)
            } else if let start = stack.popLast() {
                found.append((start, html[start..<r.upperBound]))
            }
        }
        return found.sorted { $0.start < $1.start }.map { parseTable(String($0.text)) }
    }

    /// Removes nested tables so rows/cells only come from this table.
    private static func stripNested(_ table: String) -> String {
        guard let open = table.firstIndex(of: ">"), let close = table.range(of: "</table>", options: .backwards) else { return table }
        let inner = String(table[table.index(after: open)..<close.lowerBound])
        var out = ""
        var depth = 0
        var last = inner.startIndex
        for m in matches(reTableToken, in: inner) {
            guard let r = Range(m.range, in: inner) else { continue }
            if inner[r].lowercased().hasPrefix("<table") {
                if depth == 0 { out += inner[last..<r.lowerBound] }
                depth += 1
            } else {
                depth -= 1
                if depth == 0 { last = r.upperBound }
            }
        }
        if depth == 0 { out += inner[last...] }
        return out
    }

    private static func parseTable(_ table: String) -> WikiTable {
        let body = stripNested(table)
        let caption = matches(reCaption, in: body).first.map { clean(group($0, 1, in: body)) } ?? ""
        var grid: [[String]] = []
        var pending: [Int: (remaining: Int, text: String)] = [:]
        for rowMatch in matches(reRow, in: body) {
            let rowHTML = group(rowMatch, 1, in: body)
            let cells = matches(reCell, in: rowHTML).map { m -> (attrs: String, text: String) in
                (group(m, 2, in: rowHTML), clean(group(m, 3, in: rowHTML)))
            }
            var row: [String] = []
            var col = 0
            var ci = 0
            while ci < cells.count || pending[col] != nil {
                if let p = pending[col] {
                    row.append(p.text)
                    pending[col] = p.remaining <= 1 ? nil : (p.remaining - 1, p.text)
                    col += 1
                    continue
                }
                let cell = cells[ci]
                ci += 1
                let colspan = matches(reColspan, in: cell.attrs).first.flatMap { Int(group($0, 1, in: cell.attrs)) } ?? 1
                let rowspan = matches(reRowspan, in: cell.attrs).first.flatMap { Int(group($0, 1, in: cell.attrs)) } ?? 1
                for _ in 0..<max(1, min(colspan, 20)) {
                    row.append(cell.text)
                    if rowspan > 1 { pending[col] = (rowspan - 1, cell.text) }
                    col += 1
                }
            }
            grid.append(row)
        }
        return WikiTable(caption: caption, rows: grid)
    }

    /// h2/h3 sections with their paragraphs, for stage reports.
    static func sections(in html: String) -> [WikiSection] {
        let heads = matches(reHeading, in: html)
        var out: [WikiSection] = []
        for (i, h) in heads.enumerated() {
            guard let hr = Range(h.range, in: html) else { continue }
            let end = i + 1 < heads.count ? (Range(heads[i + 1].range, in: html)?.lowerBound ?? html.endIndex) : html.endIndex
            let chunk = String(html[hr.upperBound..<end])
            let paras = matches(reParagraph, in: chunk).map { clean(group($0, 1, in: chunk)) }.filter { !$0.isEmpty }
            out.append(WikiSection(title: clean(group(h, 2, in: html)), level: Int(group(h, 1, in: html)) ?? 2, paragraphs: paras))
        }
        return out
    }

    /// Relative article links (`./Title`) whose title contains `needle`.
    static func links(in html: String, containing needle: String) -> [String] {
        let re = regex(##"href="\./([^"#]+)""##)
        var seen = Set<String>()
        var out: [String] = []
        for m in matches(re, in: html) {
            let raw = group(m, 1, in: html)
            let title = (raw.removingPercentEncoding ?? raw)
            if title.contains(needle), !title.hasPrefix("File:"), seen.insert(title).inserted { out.append(title) }
        }
        return out
    }
}
