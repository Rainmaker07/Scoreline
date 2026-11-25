import SwiftUI
import UIKit

enum Theme {
    static let bg = Color.black
    /// Cards are a darker, see-through version of the page colour behind them (Apple Sports style).
    static let card = Color.black.opacity(0.28)
    static let card2 = Color.white.opacity(0.08)
    static let separator = Color.white.opacity(0.12)
    static let secondary = Color.white.opacity(0.62)
    static let tertiary = Color.white.opacity(0.36)
    static let live = Color(hex: "ff3b30")
    static let win = Color(hex: "30d158")
    static let radius: CGFloat = 22
}

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        let r, g, b: Double
        if h.count == 6 {
            r = Double((v >> 16) & 0xff) / 255
            g = Double((v >> 8) & 0xff) / 255
            b = Double(v & 0xff) / 255
        } else {
            r = 0.3; g = 0.3; b = 0.3
        }
        self = Color(red: r, green: g, blue: b)
    }

    /// Team colour softened for a dark UI: a little less saturated, never too dark to read
    /// (Apple Sports style). Nil for near-black or near-white colours.
    static func visibleTint(_ hex: String?) -> Color? {
        guard let hex, hex.count >= 6 else { return nil }
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xff) / 255, g = Double((v >> 8) & 0xff) / 255, b = Double(v & 0xff) / 255
        let lum = 0.299 * r + 0.587 * g + 0.114 * b
        if lum < 0.08 || lum > 0.92 { return nil }
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, a: CGFloat = 0
        UIColor(red: r, green: g, blue: b, alpha: 1).getHue(&hue, saturation: &sat, brightness: &bri, alpha: &a)
        return Color(hue: hue, saturation: sat * 0.82, brightness: max(bri, 0.62))
    }

    /// The page colour darkened (bottom of the page gradient).
    static func deep(_ hex: String, _ factor: Double = 0.38) -> Color {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xff) / 255, g = Double((v >> 8) & 0xff) / 255, b = Double(v & 0xff) / 255
        return Color(red: r * factor, green: g * factor, blue: b * factor)
    }
}

struct CardBackground: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardBackground(padding: padding)) }
}

struct CardTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.footnote.weight(.bold))
            .foregroundStyle(Theme.secondary)
            .tracking(0.4)
            .padding(.bottom, 6)
    }
}

struct LivePulse: View {
    @State private var on = false
    var body: some View {
        Circle()
            .fill(Theme.live)
            .frame(width: 7, height: 7)
            .opacity(on ? 0.3 : 1)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

/// ESPN serves a dark-mode version of most team logos (light outline, built
/// for black backgrounds). Try that first, then fall back to the standard one.
enum LogoURL {
    static func candidates(_ url: URL?) -> [URL] {
        guard let url else { return [] }
        let s = url.absoluteString
        if s.contains("a.espncdn.com/i/teamlogos/"), s.contains("/500/") {
            let dark = s.replacingOccurrences(of: "/500/", with: "/500-dark/")
            if let d = URL(string: dark) { return [d, url] }
        }
        return [url]
    }
}

/// Remote logo with dark-mode preference and a lettered fallback.
struct LogoView: View {
    let url: URL?
    let fallback: String
    var size: CGFloat = 44

    @State private var attempt = 0

    var body: some View {
        let urls = LogoURL.candidates(url)
        Group {
            if attempt < urls.count {
                CachedImage(url: urls[attempt]) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFit()
                    case .failure:
                        Color.clear.onAppear { attempt += 1 }
                    default:
                        Color.clear
                    }
                }
                .id(urls[attempt])
            } else {
                ZStack {
                    Circle().fill(Theme.card2)
                    Text(String(fallback.prefix(3)).uppercased())
                        .font(.system(size: size * 0.28, weight: .heavy))
                }
            }
        }
        .frame(width: size, height: size)
        .onChange(of: url) { attempt = 0 }
    }
}

extension Font {
    /// Tall condensed numerals, like Apple Sports scores.
    static func score(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold).width(.condensed)
    }
}

/// Wraps content in a NavigationLink to a team page, with a long-press
/// menu to follow / unfollow the team.
struct TeamLink<Content: View>: View {
    let leagueId: String
    let teamId: String
    let name: String
    let abbr: String
    let logo: URL?
    @ViewBuilder let content: () -> Content
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let fav = Favorite(leagueId: leagueId, entityId: teamId, name: name, abbr: abbr, logo: logo)
        let isFav = store.isFavorite(league: leagueId, id: teamId)
        NavigationLink(value: Route.team(leagueId: leagueId, teamId: teamId)) {
            content()
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                store.toggle(fav)
            } label: {
                Label(isFav ? "Remove from My Teams" : "Add to My Teams", systemImage: isFav ? "star.slash" : "star")
            }
        }
    }
}

struct FavoriteButton: View {
    let favorite: Favorite
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let on = store.favorites.contains { $0.id == favorite.id }
        Button {
            withAnimation(.snappy) { store.toggle(favorite) }
        } label: {
            Image(systemName: on ? "star.fill" : "star")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(on ? .yellow : .white)
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.18), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? Color.black : Theme.secondary)
                .background(selected ? Color.white : Theme.card, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Horizontal chip row that scrolls edge to edge: chips slide under the screen edge
/// instead of being cut off at the page's 16-pt margin.
struct ChipScroll<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) { content() }
                .padding(.horizontal, 16)
        }
        .padding(.horizontal, -16)
    }
}

/// Light secondary tabs (text with an underline), used under a segmented control
/// so two switches don't stack as heavy bars.
struct TextTabs<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String

    var body: some View {
        HStack(spacing: 18) {
            ForEach(items, id: \.self) { item in
                let on = item == selection
                Button { withAnimation(.snappy) { selection = item } } label: {
                    VStack(spacing: 4) {
                        Text(title(item))
                            .font(.subheadline.weight(on ? .bold : .medium))
                            .foregroundStyle(on ? Color.white : Theme.secondary)
                        Capsule().fill(on ? Color.white : .clear).frame(height: 2)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }
}

struct ChipRow<Item: Hashable>: View {
    let items: [Item]
    let selected: Item?
    let title: (Item) -> String
    let onSelect: (Item) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ChipScroll {
                    ForEach(items, id: \.self) { item in
                        Chip(title: title(item), selected: item == selected) { onSelect(item) }
                            .id(item)
                    }
                }
            .onAppear { if let selected { proxy.scrollTo(selected, anchor: .center) } }
        }
    }
}

struct MessageCard: View {
    let text: String
    var isError = false
    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(isError ? Color.orange : Theme.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(22)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

/// One date style for the whole app (German): "Di., 24. Nov.", "00:30", "22. Aug. – 13. Sep.".
enum Fmt {
    static let locale = Locale(identifier: "de_DE")

    private static func formatter(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate(pattern)
        return f
    }
    private static let timeF: DateFormatter = { let f = DateFormatter(); f.locale = locale; f.dateFormat = "HH:mm"; return f }()
    private static let dayF = formatter("EEEdMMM")          // Di., 24. Nov.
    private static let dayLongF = formatter("EEEEdMMMM")    // Sonntag, 29. November
    private static let dateF = formatter("dMMM")            // 24. Nov.
    private static let dateYearF = formatter("dMMMyyyy")    // 20. Apr. 1997
    private static let numericF: DateFormatter = { let f = DateFormatter(); f.locale = locale; f.dateFormat = "d.M."; return f }()
    private static let monthF = formatter("MMM")            // Nov.

    /// 00:30, 21:00
    static func time(_ d: Date) -> String { timeF.string(from: d) }
    /// Di., 24. Nov.
    static func day(_ d: Date) -> String { dayF.string(from: d) }
    static func dayOnly(_ d: Date) -> String { day(d) }
    /// Sonntag, 29. November
    static func dayLong(_ d: Date) -> String { dayLongF.string(from: d) }
    /// 24. Nov.
    static func date(_ d: Date) -> String { dateF.string(from: d) }
    /// 20. Apr. 1997
    static func dateYear(_ d: Date) -> String { dateYearF.string(from: d) }
    /// 23.11.
    static func numeric(_ d: Date) -> String { numericF.string(from: d) }
    /// Nov.
    static func month(_ d: Date) -> String { monthF.string(from: d) }

    /// 22. Aug. – 13. Sep. / 20.–25. Jan. / 5. Apr.
    static func range(_ a: Date, _ b: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(a, inSameDayAs: b) { return date(a) }
        if cal.isDate(a, equalTo: b, toGranularity: .month) {
            return "\(cal.component(.day, from: a)).–\(date(b))"
        }
        return "\(date(a)) – \(date(b))"
    }

    private static let germanMonths = ["Jan.", "Feb.", "März", "Apr.", "Mai", "Juni", "Juli", "Aug.", "Sep.", "Okt.", "Nov.", "Dez."]
    private static let englishMonths = ["january", "february", "march", "april", "may", "june", "july", "august",
                                        "september", "october", "november", "december"]
    private static func monthIndex(_ name: String) -> Int? {
        let n = name.lowercased()
        return englishMonths.firstIndex { $0 == n || ($0.hasPrefix(n) && n.count >= 3) }
    }

    /// Rewrites English dates in text from Wikipedia or ESPN into the app's style:
    /// "22 August – 13 September" → "22. Aug. – 13. Sep.", "20–25 January" → "20.–25. Jan.",
    /// "25 November 2026" → "25. Nov. 2026", "Dec 1-2" → "1.–2. Dez.", "Aug 21-Sep 2" → "21. Aug. – 2. Sep.".
    static func text(_ s: String) -> String {
        var out = s
        let monthPat = "(January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)\\.?"
        // "Aug 21-Sep 2" / "Dec 1-2" / "Oct 27"
        if let re = try? NSRegularExpression(pattern: "\\b\(monthPat) (\\d{1,2})(?:\\s*[-–]\\s*(?:\(monthPat) )?(\\d{1,2}))?\\b") {
            out = replace(re, in: out) { g in
                guard let m1 = monthIndex(g[1] ?? ""), let d1 = g[2] else { return nil }
                if let d2 = g[4] {
                    if let m2name = g[3], let m2 = monthIndex(m2name), m2 != m1 {
                        return "\(d1). \(germanMonths[m1]) – \(d2). \(germanMonths[m2])"
                    }
                    return "\(d1).–\(d2). \(germanMonths[m1])"
                }
                return "\(d1). \(germanMonths[m1])"
            }
        }
        // "20–25 January 2026" / "22 August" / "28 April – 3 May"
        if let re = try? NSRegularExpression(pattern: "\\b(\\d{1,2})(?:\\s*[–-]\\s*(\\d{1,2}))? \(monthPat)(?: (\\d{4}))?\\b") {
            out = replace(re, in: out) { g in
                guard let d1 = g[1], let m = monthIndex(g[3] ?? "") else { return nil }
                let year = g[4].map { " \($0)" } ?? ""
                if let d2 = g[2] { return "\(d1).–\(d2). \(germanMonths[m])\(year)" }
                return "\(d1). \(germanMonths[m])\(year)"
            }
        }
        return out
    }

    private static func replace(_ re: NSRegularExpression, in s: String, _ f: ([String?]) -> String?) -> String {
        let ns = s as NSString
        var result = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let groups: [String?] = (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            result += f(groups) ?? ns.substring(with: m.range)
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    /// "SuperTennis Arena, Bologna 25 November 2026" → "SuperTennis Arena, Bologna · 25. Nov. 2026"
    static func venueAndDate(_ s: String) -> String {
        let t = text(s)
        guard let r = t.range(of: #"\s+(\d{1,2}\.(–\d{1,2}\.)? [A-ZÄa-zä]+\.?( \d{4})?)$"#, options: .regularExpression) else { return t }
        let date = t[r].trimmingCharacters(in: .whitespaces)
        let place = t[..<r.lowerBound].trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
        return place.isEmpty ? date : "\(place) · \(date)"
    }
}

/// Metric units and German dates for ESPN's US-style bio fields.
enum Units {
    /// 6' 8" -> 203 cm (already-metric values are kept).
    static func height(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        let ns = s as NSString
        if let re = try? NSRegularExpression(pattern: #"(\d+)\s*'\s*(\d+)?"#),
           let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) {
            let ft = Double(ns.substring(with: m.range(at: 1))) ?? 0
            let inch = m.range(at: 2).location == NSNotFound ? 0 : Double(ns.substring(with: m.range(at: 2))) ?? 0
            return "\(Int(((ft * 12 + inch) * 2.54).rounded())) cm"
        }
        return s
    }

    /// 203 lbs -> 92 kg
    static func weight(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        if s.lowercased().contains("lb"), let n = Double(s.filter { $0.isNumber || $0 == "." }) {
            return "\(Int((n * 0.45359237).rounded())) kg"
        }
        return s
    }

    /// ESPN "2/11/2001" (US month/day) or "20/4/1997" (day first) -> "11. Feb. 2001".
    static func birthDate(_ s: String?, dayFirst: Bool = false) -> String? {
        guard let s, !s.isEmpty else { return nil }
        let parts = s.split(separator: "/").compactMap { Int($0) }
        guard parts.count == 3 else { return s }
        var (m, d) = dayFirst ? (parts[1], parts[0]) : (parts[0], parts[1])
        if m > 12 { swap(&m, &d) }
        guard let date = Calendar.current.date(from: DateComponents(year: parts[2], month: m, day: d)) else { return s }
        return Fmt.dateYear(date)
    }
}


/// The colour of the current page (league or team), handed down to pushed screens.
private struct PageColorKey: EnvironmentKey { static let defaultValue = "1c2a4a" }
extension EnvironmentValues {
    var pageColor: String {
        get { self[PageColorKey.self] }
        set { self[PageColorKey.self] = newValue }
    }
}
