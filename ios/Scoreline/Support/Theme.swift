import SwiftUI

enum Theme {
    static let bg = Color.black
    static let card = Color(hex: "1c1c1e")
    static let card2 = Color(hex: "2c2c2e")
    static let separator = Color(white: 0.33, opacity: 0.45)
    static let secondary = Color(white: 0.92, opacity: 0.6)
    static let tertiary = Color(white: 0.92, opacity: 0.3)
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

    /// Returns nil for colours that would be invisible on black or glaring white.
    static func visibleTint(_ hex: String?) -> Color? {
        guard let hex, hex.count >= 6 else { return nil }
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xff), g = Double((v >> 8) & 0xff), b = Double(v & 0xff)
        let lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255
        if lum < 0.08 || lum > 0.92 { return nil }
        return Color(hex: h)
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

struct ChipRow<Item: Hashable>: View {
    let items: [Item]
    let selected: Item?
    let title: (Item) -> String
    let onSelect: (Item) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(items, id: \.self) { item in
                        Chip(title: title(item), selected: item == selected) { onSelect(item) }
                            .id(item)
                    }
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

enum Fmt {
    static func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }
    static func day(_ d: Date) -> String { d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
    static func dayOnly(_ d: Date) -> String { d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
}
