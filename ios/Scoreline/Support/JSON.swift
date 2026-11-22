import Foundation

/// Lightweight, forgiving accessor over `JSONSerialization` output.
/// ESPN payloads are large and loosely structured, so we read them like
/// `json["competitions"][0]["status"]["type"]["state"].str` instead of
/// modelling every field with Codable.
struct J {
    let raw: Any?

    init(_ raw: Any?) { self.raw = raw }

    init(data: Data) throws {
        raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    subscript(key: String) -> J { J((raw as? [String: Any])?[key]) }

    subscript(index: Int) -> J {
        guard let a = raw as? [Any], index >= 0, index < a.count else { return J(nil) }
        return J(a[index])
    }

    var array: [J] { (raw as? [Any])?.map { J($0) } ?? [] }
    var dict: [String: J] { ((raw as? [String: Any]) ?? [:]).mapValues { J($0) } }

    var string: String? {
        if let s = raw as? String { return s }
        if let n = raw as? NSNumber { return n.stringValue }
        return nil
    }

    var str: String { string ?? "" }

    var double: Double? {
        if let n = raw as? NSNumber { return n.doubleValue }
        if let s = raw as? String { return Double(s) }
        return nil
    }

    var int: Int? { double.map { Int($0) } }

    var bool: Bool? {
        if let b = raw as? Bool { return b }
        if let n = raw as? NSNumber { return n.boolValue }
        if let s = raw as? String { return s == "true" }
        return nil
    }

    var exists: Bool { raw != nil && !(raw is NSNull) }

    var url: URL? { string.flatMap { URL(string: $0) } }
}

enum ESPNDate {
    private static let formatters: [DateFormatter] = ["yyyy-MM-dd'T'HH:mmX", "yyyy-MM-dd'T'HH:mm:ssX", "yyyy-MM-dd'T'HH:mm:ss.SSSX"].map {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = $0
        return f
    }

    static func parse(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        for f in formatters { if let d = f.date(from: s) { return d } }
        return nil
    }

    static func ymd(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
