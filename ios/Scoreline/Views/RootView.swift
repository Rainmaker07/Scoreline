import SwiftUI

struct RootView: View {
    @ObservedObject private var store = AppStore.shared
    @AppStorage("selectedLeague") private var selected = "home"
    @State private var openGame: Game?
    @State private var refresh = 0
    @State private var menuOpen = false
    @State private var path = NavigationPath()
    @State private var sheet: MenuSheet?

    private var league: League? { League.byId(selected) }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .topTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        topBar
                        content
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
                .refreshable { refresh += 1 }
                .background(PageBackground(color: league?.color ?? "1c2a4a"))

                if menuOpen {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { menuOpen = false } }
                    LeagueMenu(selected: selected,
                               onSelect: { id in
                                   withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { menuOpen = false }
                                   selected = id
                               },
                               onSheet: { s in
                                   withAnimation { menuOpen = false }
                                   sheet = s
                               },
                               onMyTeams: {
                                   withAnimation { menuOpen = false }
                                   path.append(Route.favorites)
                               })
                        .padding(.top, 4)
                        .padding(.trailing, 12)
                        .transition(.scale(scale: 0.6, anchor: .topTrailing).combined(with: .opacity))
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        .sheet(item: $openGame) { g in
            NavigationStack {
                GameDetailView(game: g)
                    .navigationDestination(for: Route.self) { RouteView(route: $0) }
            }
            .presentationDragIndicator(.visible)
            .presentationBackground(Theme.bg)
            .environmentObject(store)
        }
        .sheet(item: $sheet) { s in
            Group {
                switch s {
                case .search:
                    SearchView { route in
                        sheet = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { path.append(route) }
                    }
                case .edit:
                    EditLeaguesView()
                case .settings:
                    SettingsView()
                }
            }
            .environmentObject(store)
            .preferredColorScheme(.dark)
        }
        .environmentObject(store)
        .preferredColorScheme(.dark)
        .tint(.white)
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            Text("Scoreline")
                .font(.system(size: 34, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 12)
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { menuOpen.toggle() }
            } label: {
                HStack(spacing: 8) {
                    if let league {
                        LeagueIcon(league: league, size: 22)
                        Text(league.short).lineLimit(1)
                    } else {
                        Image(systemName: "house.fill")
                        Text("Home")
                    }
                }
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    @ViewBuilder private var content: some View {
        if let league {
            switch league.family {
            case .tennis:
                TennisView(refresh: refresh)
            case .cycling:
                CyclingView(refresh: refresh)
            default:
                LeaguePage(league: league, refresh: refresh, openGame: $openGame)
            }
        } else {
            HomeView(refresh: refresh, openGame: $openGame) { selected = $0 }
        }
    }
}

/// League-tinted backdrop that fades to black, like Apple Sports.
struct PageBackground: View {
    let color: String
    var body: some View {
        LinearGradient(colors: [Color(hex: color).opacity(0.95), Color(hex: color).opacity(0.45), .black],
                       startPoint: .top, endPoint: .init(x: 0.5, y: 0.75))
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.35), value: color)
    }
}

struct LeagueIcon: View {
    let league: League
    var size: CGFloat = 24
    var body: some View {
        if let logo = league.logo {
            LogoView(url: logo, fallback: league.short, size: size)
        } else {
            Image(systemName: league.glyph ?? "sportscourt")
                .font(.system(size: size * 0.8))
                .frame(width: size, height: size)
        }
    }
}

enum MenuSheet: String, Identifiable {
    case search, edit, settings
    var id: String { rawValue }
}

/// Floating league switcher.
struct LeagueMenu: View {
    let selected: String
    let onSelect: (String) -> Void
    let onSheet: (MenuSheet) -> Void
    let onMyTeams: () -> Void
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button { onSheet(.settings) } label: { Image(systemName: "gearshape").font(.body) }
                    .buttonStyle(.plain)
                    .padding(.trailing, 14)
                Button("Edit") { onSheet(.edit) }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.plain)
            }
            .foregroundStyle(Color(hex: "8ab4ff"))
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    item(icon: AnyView(Image(systemName: "magnifyingglass").font(.body)), title: "Search", subtitle: nil, on: false) { onSheet(.search) }
                    item(icon: AnyView(Image(systemName: "house.fill").font(.body)), title: "Home", subtitle: nil, on: selected == "home") { onSelect("home") }
                    item(icon: AnyView(Image(systemName: "star.fill").font(.body)), title: "My Teams", subtitle: nil, on: false) { onMyTeams() }
                    ForEach(store.visibleLeagues) { l in
                        item(icon: AnyView(LeagueIcon(league: l, size: 22)), title: l.name, subtitle: l, on: selected == l.id) { onSelect(l.id) }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
            .frame(maxHeight: UIScreen.main.bounds.height * 0.6)
        }
        .frame(width: 250)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
    }

    private func item(icon: AnyView, title: String, subtitle: League?, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                icon.frame(width: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.body.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
                    if let subtitle { LeagueStatusText(league: subtitle) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(on ? Color.white.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// "Off Season", "2 live", "Next: Sat 29 Nov" … under each league in the menu.
struct LeagueStatusText: View {
    let league: League
    @State private var text: String?

    var body: some View {
        // Always render (even empty): an empty view never runs its .task.
        Text(text ?? " ")
            .font(.caption.weight(.semibold))
            .foregroundStyle((text ?? "").hasSuffix("live") ? Theme.live : Theme.secondary)
            .lineLimit(1)
            .task(id: league.id) { text = await Self.status(league) }
    }

    static func status(_ league: League) async -> String? {
        switch league.provider {
        case .espn:
            return await ESPN.status(league)
        case .bbl:
            guard let games = try? await BBL.games() else { return nil }
            let live = games.filter { $0.state == .live }.count
            if live > 0 { return "\(live) live" }
            if let next = games.first(where: { $0.state == .pre }) { return "Next: \(Fmt.day(next.date))" }
            return nil
        case .tennis:
            return Slam.statusLine()
        case .cycling:
            return CyclingService.statusLine()
        }
    }
}

struct EditLeaguesView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.orderedLeagues) { l in
                        HStack(spacing: 12) {
                            LeagueIcon(league: l, size: 26)
                            Text(l.name)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { !store.hiddenLeagues.contains(l.id) },
                                set: { on in
                                    if on { store.hiddenLeagues.remove(l.id) } else { store.hiddenLeagues.insert(l.id) }
                                }
                            ))
                            .labelsHidden()
                        }
                    }
                    .onMove { from, to in store.leagueOrder.move(fromOffsets: from, toOffset: to) }
                } footer: {
                    Text("Drag to reorder. Hidden leagues disappear from the menu and Home.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Leagues")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cleared = false

    var body: some View {
        NavigationStack {
            List {
                Section("Data") {
                    Button(cleared ? "Cache cleared" : "Clear cached data") {
                        Task {
                            await HTTP.shared.clearAll()
                            URLCache.shared.removeAllCachedResponses()
                            cleared = true
                        }
                    }
                    .disabled(cleared)
                }
                Section("Sources") {
                    Text("Scores, standings and stats: ESPN")
                    Text("easyCredit BBL: easycredit-bbl.de")
                    Text("Grand Tours and logos: Wikipedia (CC BY-SA)")
                }
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct SearchView: View {
    let open: (Route) -> Void
    @State private var query = ""
    @State private var hits: [ESPN.SearchHit] = []
    @State private var searching = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(hits) { h in
                    Button {
                        open(h.kind == "team" ? .team(leagueId: h.leagueId, teamId: h.entityId)
                                              : .player(leagueId: h.leagueId, playerId: h.entityId))
                    } label: {
                        HStack(spacing: 12) {
                            if h.kind == "team" {
                                LogoView(url: h.image, fallback: h.name, size: 30)
                            } else {
                                AsyncImage(url: h.image) { $0.resizable().scaledToFill() } placeholder: { Theme.card2 }
                                    .frame(width: 30, height: 30).clipShape(Circle())
                            }
                            VStack(alignment: .leading) {
                                Text(h.name).font(.body.weight(.semibold))
                                Text(h.subtitle).font(.caption).foregroundStyle(Theme.secondary)
                            }
                        }
                    }
                }
                if hits.isEmpty && !query.isEmpty && !searching {
                    Text("No teams or players found.").foregroundStyle(Theme.secondary)
                }
            }
            .overlay { if searching { ProgressView() } }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Teams and players")
            .task(id: query) {
                let q = query.trimmingCharacters(in: .whitespaces)
                guard q.count >= 2 else { hits = []; return }
                try? await Task.sleep(nanoseconds: 350_000_000)
                if Task.isCancelled { return }
                searching = true
                var results = await ESPN.search(q)
                results += await BBLSearch.teams(matching: q)
                if !Task.isCancelled { hits = results }
                searching = false
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

enum BBLSearch {
    static func teams(matching q: String) async -> [ESPN.SearchHit] {
        guard let groups = try? await BBL.standings() else { return [] }
        let needle = q.lowercased()
        return groups.flatMap(\.rows).filter { $0.name.lowercased().contains(needle) || $0.short.lowercased().contains(needle) }.map {
            ESPN.SearchHit(id: "bbl-\($0.id)", kind: "team", name: $0.name, subtitle: "easyCredit BBL",
                           leagueId: "bbl", entityId: $0.id, image: $0.logo)
        }
    }
}

/// Resolves navigation routes to screens.
struct RouteView: View {
    let route: Route
    var body: some View {
        switch route {
        case .team(let leagueId, let teamId):
            TeamView(leagueId: leagueId, teamId: teamId)
        case .player(let leagueId, let playerId):
            PlayerView(leagueId: leagueId, playerId: playerId)
        case .tennisPlayer(let id, let name):
            TennisPlayerView(id: id, name: name)
        case .rider(let name):
            RiderView(name: name)
        case .favorites:
            FavoritesView()
        case .game(let game):
            GameDetailView(game: game, embedded: true)
        case .tournament(let t):
            TournamentView(t: t)
        case .league(let id):
            LeagueScreen(league: League.byId(id)!)
        case .wiki(let title, let name):
            ScrollView {
                WikiEventView(title: title).padding(16)
            }
            .background(PageBackground(color: "1d428a"))
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
        }
    }
}
