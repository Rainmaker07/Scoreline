import SwiftUI

/// A league page pushed from elsewhere (e.g. a team's competition list).
struct LeagueScreen: View {
    let league: League
    @State private var openGame: Game?
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            LeaguePage(league: league, openGame: $openGame).padding(16)
        }
        .background(PageBackground(color: league.color))
        .navigationTitle(league.name)
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

/// One league's page: scores card, then standings and stat leaders below.
struct LeaguePage: View {
    let league: League
    var refresh = 0
    @Binding var openGame: Game?
    /// Standings (0) or Stats (1), remembered per league.
    @AppStorage private var tab: Int

    init(league: League, refresh: Int = 0, openGame: Binding<Game?>) {
        self.league = league
        self.refresh = refresh
        self._openGame = openGame
        self._tab = AppStorage(wrappedValue: 0, "leagueTab-\(league.id)")
    }

    var body: some View {
        let firstTitle = league.isCup ? "Rounds" : league.isUEFA ? "League Phase" : "Standings"
        VStack(alignment: .leading, spacing: 18) {
            ScoresCard(league: league, refresh: refresh, openGame: $openGame)
            if league.id == "nba" {
                NavigationLink(value: Route.nbaCup) {
                    HStack(spacing: 12) {
                        NBACupLogo(height: 34)
                        Text("NBA Cup").font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.secondary)
                    }
                    .card()
                }
                .buttonStyle(.plain)
            }
            HStack {
                Spacer()
                Text("Alerts").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary)
                AlertBell(key: "league:\(league.id)", title: league.name, competition: true)
            }
            if league.hasStatLeaders {
                Picker("", selection: $tab) {
                    Text(firstTitle).tag(0)
                    Text("Stats").tag(1)
                }
                .pickerStyle(.segmented)
            } else {
                SectionHeader(title: firstTitle)
            }
            if league.hasStatLeaders && tab == 1 {
                LeadersSection(league: league, refresh: refresh)
            } else if league.isCup {
                CupRoundsSection(league: league, refresh: refresh, openGame: $openGame)
            } else {
                StandingsSection(league: league, refresh: refresh)
            }
        }
    }
}

/// Knockout cup: results and fixtures grouped by round.
struct CupRoundsSection: View {
    let league: League
    var refresh = 0
    @Binding var openGame: Game?
    @State private var selected: String?

    var body: some View {
        Loader(id: "\(league.id)-rounds-\(refresh)", load: { try await ESPN.cupRounds(league) }) { rounds in
            if rounds.isEmpty {
                MessageCard(text: "No rounds scheduled yet.")
            } else {
                // Default: the latest round that has started.
                let current = rounds.last { $0.start <= Date() } ?? rounds[0]
                let round = rounds.first { $0.label == selected } ?? current
                VStack(alignment: .leading, spacing: 12) {
                    ChipRow(items: rounds.map(\.label), selected: round.label, title: { $0 }) { selected = $0 }
                    Text(Fmt.text(round.detail)).font(.footnote).foregroundStyle(Theme.secondary).padding(.horizontal, 4)
                    Loader(id: "\(league.id)-round-\(round.label)-\(refresh)",
                           poll: { (games: [Game]) in games.contains(where: { $0.state == .live }) ? 20 : nil },
                           load: { try await ESPN.cupGames(league, round: round) }) { games in
                        if games.isEmpty {
                            MessageCard(text: round.start > Date() ? "Draw not made yet." : "No results found for this round.")
                        } else {
                            GameList(games: games, openGame: $openGame, showDayHeaders: true)
                                .padding(.horizontal, 14)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                        }
                    }
                }
            }
        }
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.title2.weight(.bold))
            .padding(.horizontal, 4)
            .padding(.top, 6)
    }
}

/// Home: your teams first, then every league with games today.
struct HomeView: View {
    var refresh: Int
    @Binding var openGame: Game?
    let go: (String) -> Void
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            let teams = store.favorites.filter { $0.kind == .team }
            if !teams.isEmpty {
                FavoritesStrip(favorites: teams)
                SectionHeader(title: "My Teams")
                MyTeamsCard(favorites: teams, refresh: refresh, openGame: $openGame)
            } else {
                NavigationLink(value: Route.favorites) {
                    HStack(spacing: 12) {
                        Image(systemName: "star.circle.fill").font(.title).foregroundStyle(.yellow)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add your teams").font(.headline)
                            Text("Follow teams to see their games first.").font(.footnote).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.secondary)
                    }
                    .card()
                }
                .buttonStyle(.plain)
            }
            ForEach(store.visibleLeagues.filter(\.isTeamSport)) { l in
                TodaySection(league: l, refresh: refresh, openGame: $openGame) { go(l.id) }
            }
            SectionHeader(title: "More Sports")
            HStack(spacing: 10) {
                moreCard(league: League.byId("atp")!, subtitle: "Grand Slam draws & results")
                moreCard(league: League.byId("cycling")!, subtitle: "Stages & classifications")
            }
        }
    }

    private func moreCard(league: League, subtitle: String) -> some View {
        Button { go(league.id) } label: {
            VStack(alignment: .leading, spacing: 6) {
                LeagueIcon(league: league, size: 34)
                Text(league.name).font(.headline.weight(.heavy))
                Text(subtitle).font(.footnote).foregroundStyle(Theme.secondary)
            }
            .card()
        }
        .buttonStyle(.plain)
    }
}

/// A league's games today on the home screen (hidden when there are none).
struct TodaySection: View {
    let league: League
    var refresh = 0
    @Binding var openGame: Game?
    let open: () -> Void

    var body: some View {
        Loader(id: "home-\(league.id)-\(refresh)",
               poll: { (games: [Game]) in games.contains(where: { $0.state == .live }) ? 20 : 180 },
               load: { try await GameFeed.load(league, tab: .today) }) { games in
            if !games.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Button(action: open) {
                        HStack(spacing: 10) {
                            LeagueIcon(league: league, size: 24)
                            Text(league.name).font(.title3.weight(.bold))
                            let live = games.filter { $0.state == .live }.count
                            if live > 0 {
                                HStack(spacing: 5) { LivePulse(); Text("\(live) live") }
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Theme.live)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary)
                        }
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                    GameList(games: games, openGame: $openGame)
                        .padding(.horizontal, 14)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                }
            }
        }
    }
}

/// Circular logos of followed teams, like Apple Sports' My Teams row.
struct FavoritesStrip: View {
    let favorites: [Favorite]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(favorites) { f in
                    NavigationLink(value: Route.team(leagueId: f.leagueId, teamId: f.entityId)) {
                        VStack(spacing: 6) {
                            LogoView(url: f.logo, fallback: f.abbr, size: 36)
                                .frame(width: 58, height: 58)
                                .background(Theme.card, in: Circle())
                            Text(f.abbr.isEmpty ? f.name : f.abbr).font(.caption2.weight(.semibold)).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
                NavigationLink(value: Route.favorites) {
                    VStack(spacing: 6) {
                        Image(systemName: "pencil").font(.title3)
                            .frame(width: 58, height: 58)
                            .background(Theme.card, in: Circle())
                        Text("Edit").font(.caption2.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Today's game for each followed team, or its last result and next game.
struct MyTeamsCard: View {
    let favorites: [Favorite]
    var refresh = 0
    @Binding var openGame: Game?

    var body: some View {
        Loader(id: "myteams-\(favorites.map(\.id).joined())-\(refresh)",
               poll: { (games: [Game]) in games.contains(where: { $0.state == .live }) ? 30 : 300 },
               load: { await Self.load(favorites) }) { games in
            if games.isEmpty {
                MessageCard(text: "No recent or upcoming games for your teams.")
            } else {
                GameList(games: games, openGame: $openGame)
                    .padding(.horizontal, 14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
        }
    }

    static func load(_ favorites: [Favorite]) async -> [Game] {
        // All teams in parallel, then merged in the order they were followed.
        let picks = await withTaskGroup(of: (Int, [Game]).self) { group in
            for (i, f) in favorites.enumerated() {
                group.addTask { (i, await Self.games(for: f)) }
            }
            var byIndex: [Int: [Game]] = [:]
            for await (i, g) in group { byIndex[i] = g }
            return favorites.indices.flatMap { byIndex[$0] ?? [] }
        }
        var out: [Game] = []
        var seen = Set<String>()
        for g in picks where seen.insert(g.id).inserted { out.append(g) }
        return out.sorted { ($0.state.sortRank, $0.date) < ($1.state.sortRank, $1.date) }
    }

    private static func games(for f: Favorite) async -> [Game] {
        do {
            guard let league = f.league else { return [] }
            let games: [Game]
            if league.provider == .bbl {
                games = (try? await BBL.team(f.entityId).games) ?? []
            } else {
                games = (try? await ESPN.team(league, id: f.entityId).games) ?? []
            }
            let today = games.filter { Calendar.current.isDateInToday($0.date) }
            var pick = today
            if pick.isEmpty {
                if let last = games.last(where: { $0.state == .post }) { pick.append(last) }
                if let next = games.first(where: { $0.state != .post && $0.date > Date().addingTimeInterval(-3 * 3600) }) { pick.append(next) }
            }
            // Team schedules lack records and lag behind live scores: use the
            // scoreboard version of each game when it's within the next week.
            if league.provider == .espn {
                let cal = Calendar.current
                var days = Set<Date>()
                for g in pick where g.state != .post || cal.isDateInToday(g.date) {
                    let d = cal.startOfDay(for: g.date)
                    if d.timeIntervalSinceNow < 8 * 86_400 {
                        days.insert(d)
                        days.insert(cal.date(byAdding: .day, value: -1, to: d)!)
                    }
                }
                if !days.isEmpty, let board = try? await GameFeed.days(league, Array(days)) {
                    pick = pick.map { g in board.first { $0.id == g.id } ?? g }
                }
            }
            return pick
        }
    }
}
