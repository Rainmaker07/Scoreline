import SwiftUI

struct NBACupView: View {
    @State private var tab = 0
    @State private var openGame: Game?
    @EnvironmentObject private var store: AppStore
    private let year = ESPN.nbaCupYear()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    LogoView(url: LogoAssets.nbaCup, fallback: "Cup", size: 56)
                    Text("NBA Cup").font(.title.weight(.heavy))
                }
                .padding(.horizontal, 4)
                Picker("", selection: $tab) {
                    Text("Groups").tag(0)
                    Text("Knockout").tag(1)
                }
                .pickerStyle(.segmented)
                Loader(id: "nbacup-\(year)",
                       poll: { (d: NBACupData) in d.groups.contains { $0.games.contains { $0.state == .live } } ? 30 : nil },
                       load: { try await NBACup.load(year: year) }) { data in
                    if tab == 0 {
                        if data.groups.isEmpty { MessageCard(text: "Groups not available yet.") }
                        ForEach(data.groups) { g in
                            CupGroupTable(group: g, qualified: data.qualified)
                            if !g.games.isEmpty {
                                GameList(games: g.games, openGame: $openGame, showDayHeaders: true)
                                    .padding(.horizontal, 14)
                                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                            }
                        }
                    } else {
                        if data.knockout.isEmpty {
                            MessageCard(text: "The knockout rounds start after the group stage. Quarterfinals, semifinals and the championship game appear here.")
                        }
                        ForEach(Array(data.knockout.enumerated()), id: \.offset) { _, round in
                            SectionHeader(title: round.round)
                            GameList(games: round.games, openGame: $openGame, showDayHeaders: true)
                                .padding(.horizontal, 14)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(PageBackground(color: "1d428a"))
        .navigationTitle("NBA Cup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(item: $openGame) { g in
            NavigationStack {
                GameDetailView(game: g).navigationDestination(for: Route.self) { RouteView(route: $0) }
            }
            .presentationBackground(Theme.bg)
            .environmentObject(store)
        }
    }
}

private struct CupGroupTable: View {
    let group: NBACupGroup
    let qualified: Set<String>
    @EnvironmentObject private var store: AppStore

    private let cols: [(String, String, CGFloat)] = [("wins", "W", 26), ("losses", "L", 26), ("pointsFor", "PF", 40),
                                                     ("pointsAgainst", "PA", 40), ("differential", "PD", 40)]

    var body: some View {
        let favs = store.favoriteTeamIds("nba")
        VStack(alignment: .leading, spacing: 0) {
            Text(group.name).font(.headline).padding(.bottom, 10)
            HStack(spacing: 4) {
                Text("#").frame(width: 24, alignment: .leading)
                Text("Team").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(cols, id: \.0) { Text($0.1).frame(width: $0.2, alignment: .trailing) }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.secondary)
            .padding(.bottom, 6)
            ForEach(Array(group.rows.enumerated()), id: \.element.id) { i, r in
                let zone: Zone? = i == 0 ? Zone(label: "Group Winner", color: Color(hex: "30d158"))
                    : (qualified.contains(r.id) ? Zone(label: "Wild Card", color: Color(hex: "64d2ff")) : nil)
                if i > 0 { Divider().overlay(Theme.separator) }
                NavigationLink(value: Route.team(leagueId: "nba", teamId: r.id)) {
                    HStack(spacing: 4) {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 1.5).fill(zone?.color ?? .clear).frame(width: 3, height: 18)
                            Text("\(i + 1)").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary)
                        }
                        .frame(width: 24, alignment: .leading)
                        HStack(spacing: 6) {
                            LogoView(url: r.logo, fallback: r.abbr, size: 20)
                            Text(r.abbr).font(.system(size: 14, weight: .semibold))
                            if let zone { Text(zone.label.uppercased()).font(.system(size: 8, weight: .bold)).foregroundStyle(zone.color) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(cols, id: \.0) { c in
                            Text(r.stats[c.0] ?? "–").frame(width: c.2, alignment: .trailing)
                                .fontWeight(c.0 == "wins" ? .heavy : .regular)
                        }
                    }
                    .font(.subheadline)
                    .monospacedDigit()
                    .padding(.vertical, 8)
                    .background(favs.contains(r.id) ? Color.yellow.opacity(0.10) : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    let on = favs.contains(r.id)
                    Button {
                        store.toggle(Favorite(leagueId: "nba", entityId: r.id, name: r.name, abbr: r.abbr, logo: r.logo))
                    } label: {
                        Label(on ? "Remove from My Teams" : "Add to My Teams", systemImage: on ? "star.slash" : "star")
                    }
                }
            }
        }
        .card()
    }
}
