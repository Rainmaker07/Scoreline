import SwiftUI

// MARK: - Shared pieces

struct InfoList: View {
    let title: String
    let rows: [InfoRow]
    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                CardTitle(title)
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                    if i > 0 { Divider().overlay(Theme.separator) }
                    HStack(alignment: .top) {
                        Text(r.label).foregroundStyle(Theme.secondary)
                        Spacer(minLength: 12)
                        Text(r.value).multilineTextAlignment(.trailing).monospacedDigit()
                    }
                    .font(.subheadline)
                    .padding(.vertical, 8)
                }
            }
            .card()
        }
    }
}

/// Wide stat table: first column pinned, values scroll sideways if needed.
struct StatTableView: View {
    let table: StatTable
    /// Optional destination per row (game log rows open the game).
    var routes: [Route?] = []

    private func route(_ i: Int) -> Route? {
        if i < routes.count { return routes[i] }
        return i < table.rowRoutes.count ? table.rowRoutes[i] : nil
    }

    @ViewBuilder private func linked<C: View>(_ i: Int, @ViewBuilder _ c: () -> C) -> some View {
        if let r = route(i) {
            NavigationLink(value: r) { c().contentShape(Rectangle()) }.buttonStyle(.plain)
        } else {
            c()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(table.title)
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("").frame(height: 22)
                    ForEach(Array(table.rows.enumerated()), id: \.offset) { i, r in
                        linked(i) {
                            HStack(spacing: 5) {
                                if i < table.rowLogos.count {
                                    if let logo = table.rowLogos[i] {
                                        LogoView(url: logo, fallback: "", size: 16)
                                    } else {
                                        Image(systemName: "soccerball").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                                            .frame(width: 16, height: 16)
                                    }
                                }
                                Text(r.name).font(.footnote.weight(.semibold)).lineLimit(1).truncationMode(.tail)
                                if route(i) != nil {
                                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.tertiary)
                                }
                            }
                            .frame(height: 30, alignment: .leading)
                        }
                    }
                }
                .frame(width: table.rowLogos.isEmpty && routes.isEmpty && table.rowRoutes.isEmpty ? 104 : 138, alignment: .leading)
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .trailing, spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(Array(table.labels.enumerated()), id: \.offset) { cell($0.element, $0.offset) }
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.secondary)
                        .frame(height: 22)
                        ForEach(Array(table.rows.enumerated()), id: \.offset) { i, r in
                            linked(i) {
                                HStack(spacing: 0) {
                                    ForEach(Array(r.values.enumerated()), id: \.offset) { cell($0.element, $0.offset) }
                                }
                                .font(.footnote)
                                .frame(height: 30)
                            }
                        }
                    }
                    .monospacedDigit()
                }
            }
        }
        .card()
    }

    /// Every row uses the same width per column, so values line up ("235-365" no longer shifts).
    private var widths: [CGFloat] {
        let n = max(table.labels.count, table.rows.map(\.values.count).max() ?? 0)
        return (0..<n).map { i in
            let longest = ([i < table.labels.count ? table.labels[i] : ""] + table.rows.map { i < $0.values.count ? $0.values[i] : "" })
                .map(\.count).max() ?? 0
            return max(34, CGFloat(longest) * 7.6 + 10)
        }
    }

    private func cell(_ t: String, _ i: Int) -> some View {
        let w = i < widths.count ? widths[i] : 46
        return Text(t).lineLimit(1).frame(width: w, alignment: .trailing)
    }
}

struct DetailHeader: View {
    let image: URL?
    let isLogo: Bool
    let title: String
    let subtitle: String?
    let color: String?
    var trailing: AnyView? = nil
    /// Player pages: look further (FotMob, Wikipedia) when the headshot is missing.
    var football = false
    var lookUpPhoto = false
    @State private var resolved: URL??

    var body: some View {
        let tint = Color.visibleTint(color) ?? Color.white.opacity(0.12)
        let photo: URL? = lookUpPhoto ? (resolved ?? image) : image
        VStack(spacing: 10) {
            if isLogo {
                LogoView(url: image, fallback: title, size: 88)
            } else {
                CachedImage(url: photo) { $0.resizable().scaledToFill() } placeholder: {
                    Image(systemName: "person.fill").font(.system(size: 40)).foregroundStyle(Theme.secondary)
                }
                .frame(width: 104, height: 104)
                .background(Theme.card2)
                .clipShape(Circle())
                .task(id: title) {
                    guard lookUpPhoto else { return }
                    resolved = .some(await PlayerPhotos.best(primary: image, name: title, team: subtitle ?? "", football: football))
                }
            }
            Text(title).font(.title2.weight(.heavy)).multilineTextAlignment(.center)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
            }
            if let trailing { trailing }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(LinearGradient(colors: [tint.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom))
    }
}

// MARK: - Team

struct TeamView: View {
    let leagueId: String
    let teamId: String
    @State private var tab = 0
    @State private var competition: String?

    var body: some View {
        let league = League.byId(leagueId)!
        ScrollView {
            Loader(id: "team-\(leagueId)-\(teamId)",
                   load: { () async throws -> TeamPage in
                       if league.provider == .bbl { return try await BBL.team(teamId) }
                       return try await ESPN.team(league, id: teamId)
                   }) { t in
                VStack(spacing: 14) {
                    DetailHeader(
                        image: t.logo, isLogo: true, title: t.name,
                        subtitle: [t.record, t.standing].compactMap { $0 }.joined(separator: " · "),
                        color: t.color,
                        trailing: AnyView(HStack(spacing: 10) {
                            FormBadges(form: t.form)
                            FavoriteButton(favorite: Favorite(leagueId: leagueId, entityId: teamId, name: t.name, abbr: t.abbr, logo: t.logo))
                            let fav = Favorite(leagueId: leagueId, entityId: teamId, name: t.name, abbr: t.abbr, logo: t.logo)
                            AlertBell(key: fav.id, title: t.name, favorite: fav)
                        })
                    )
                    VStack(spacing: 14) {
                        if t.competitions.count > 1 {
                            CompetitionSwitcher(competitions: t.competitions, selected: $competition)
                        }
                        Picker("", selection: $tab) {
                            Text("Games").tag(0)
                            Text("Roster").tag(1)
                            Text("Stats").tag(2)
                        }
                        .pickerStyle(.segmented)
                        let games = competition.map { c in t.games.filter { $0.leagueId == c } } ?? t.games
                        switch tab {
                        case 0: TeamGames(games: games, showCompetition: t.competitions.count > 1 && competition == nil)
                        case 1: TeamRoster(league: league, team: t.name, roster: t.roster)
                        default:
                            if let c = competition.flatMap(League.byId) {
                                CompetitionRecord(team: t, league: c, games: games)
                            } else {
                                InfoList(title: "Season", rows: t.stats)
                                ForEach(Array(t.statSections.enumerated()), id: \.offset) { _, sec in
                                    InfoList(title: sec.title, rows: sec.rows)
                                }
                                if t.competitions.count > 1 {
                                    ForEach(t.competitions) { c in
                                        CompetitionRecord(team: t, league: c, games: t.games.filter { $0.leagueId == c.id })
                                    }
                                }
                            }
                            InfoList(title: "Injuries", rows: t.injuries)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 40)
            }
        }
        .background(PageBackground())
        .navigationTitle(league.short)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

struct FormBadges: View {
    let form: [String]
    var body: some View {
        if !form.isEmpty {
            HStack(spacing: 4) {
                ForEach(Array(form.enumerated()), id: \.offset) { _, f in
                    Text(f)
                        .font(.system(size: 11, weight: .heavy))
                        .frame(width: 20, height: 20)
                        .background(f == "W" ? Theme.win : f == "L" ? Theme.live : Color(white: 0.45), in: RoundedRectangle(cornerRadius: 5))
                }
            }
        }
    }
}

/// "All · Bundesliga · Champions League · DFB-Pokal" filter, with a link to each competition.
struct CompetitionSwitcher: View {
    let competitions: [League]
    @Binding var selected: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ChipScroll {
                    Chip(title: "All", selected: selected == nil) { selected = nil }
                    ForEach(competitions) { c in
                        Button { selected = c.id } label: {
                            HStack(spacing: 5) {
                                LeagueIcon(league: c, size: 16)
                                Text(c.short).lineLimit(1)
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .foregroundStyle(selected == c.id ? Color.black : Theme.secondary)
                            .background(selected == c.id ? Color.white : Theme.card, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            if let id = selected, let c = League.byId(id) {
                NavigationLink(value: Route.league(c.id)) {
                    HStack(spacing: 6) {
                        Text("Open \(c.name)").font(.footnote.weight(.semibold))
                        Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(Color(hex: "8ab4ff"))
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }
        }
    }
}

/// Played / won / drawn / lost and goals in one competition, from the team's games.
private struct CompetitionRecord: View {
    let team: TeamPage
    let league: League
    let games: [Game]

    var body: some View {
        let done = games.filter { $0.state == .post }
        var w = 0, d = 0, l = 0, gf = 0, ga = 0, clean = 0, failed = 0
        for g in done {
            let me = g.home.id == team.id ? g.home : g.away
            let them = g.home.id == team.id ? g.away : g.home
            let a = Int(me.score ?? "") ?? 0, b = Int(them.score ?? "") ?? 0
            gf += a; ga += b
            if b == 0 { clean += 1 }
            if a == 0 { failed += 1 }
            if a > b { w += 1 } else if a == b { d += 1 } else { l += 1 }
        }
        let n = max(done.count, 1)
        let rows = [InfoRow(label: "Played", value: "\(done.count)"),
                    InfoRow(label: "Won – drawn – lost", value: "\(w) – \(d) – \(l)"),
                    InfoRow(label: "Goals", value: "\(gf):\(ga)"),
                    InfoRow(label: "Goals per game", value: String(format: "%.1f : %.1f", Double(gf) / Double(n), Double(ga) / Double(n))),
                    InfoRow(label: "Clean sheets", value: "\(clean)"),
                    InfoRow(label: "Failed to score", value: "\(failed)"),
                    InfoRow(label: "Next", value: games.first { $0.state != .post }.map { g in
                        "\(g.home.id == team.id ? "vs" : "@") \(g.home.id == team.id ? g.away.short : g.home.short) · \(Fmt.day(g.date))"
                    } ?? "–")]
        return InfoList(title: league.name, rows: rows)
    }
}

private struct TeamGames: View {
    let games: [Game]
    var showCompetition = false
    @State private var showAll = false

    var body: some View {
        let past = games.filter { $0.state == .post }
        let upcoming = games.filter { $0.state != .post }
        VStack(alignment: .leading, spacing: 14) {
            if !upcoming.isEmpty {
                section("Upcoming", Array(upcoming.prefix(showAll ? 100 : 5)))
            }
            if !past.isEmpty {
                section("Results", Array(past.reversed().prefix(showAll ? 100 : 8)))
            }
            if games.count > 13 && !showAll {
                Button("Show full season") { showAll = true }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            if games.isEmpty { MessageCard(text: "No games scheduled.") }
        }
    }

    private func section(_ title: String, _ list: [Game]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CardTitle(title)
            ForEach(Array(list.enumerated()), id: \.element.id) { i, g in
                if i > 0 { Divider().overlay(Theme.separator) }
                NavigationLink(value: Route.game(g)) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) {
                            Text(Fmt.day(g.date))
                            if showCompetition {
                                LeagueIcon(league: g.league, size: 12)
                                Text(g.league.short)
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondary)
                        .padding(.top, 8)
                        GameRow(game: g, showDate: false)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .card(padding: 14)
    }
}

private struct TeamRoster: View {
    let league: League
    var team = ""
    let roster: [RosterPlayer]

    var body: some View {
        let groups = Dictionary(grouping: roster) { $0.group ?? "" }
        let order = roster.reduce(into: [String]()) { acc, p in if !acc.contains(p.group ?? "") { acc.append(p.group ?? "") } }
        VStack(spacing: 14) {
            if roster.isEmpty {
                MessageCard(text: isRugby ? "No current squad found on the club’s Wikipedia page." : "Roster not available.")
            }
            ForEach(order, id: \.self) { g in
                VStack(alignment: .leading, spacing: 0) {
                    CardTitle(g.isEmpty ? "Roster" : g)
                    ForEach(Array((groups[g] ?? []).enumerated()), id: \.element.id) { i, p in
                        if i > 0 { Divider().overlay(Theme.separator) }
                        if isRugby {
                            // Squads come from Wikipedia: no player pages for rugby.
                            row(p, chevron: false)
                        } else {
                            NavigationLink(value: Route.player(leagueId: league.id, playerId: p.id)) { row(p, chevron: true) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .card(padding: 14)
            }
            if isRugby && !roster.isEmpty {
                Text("Squad from Wikipedia (CC BY-SA)").font(.caption2).foregroundStyle(Theme.tertiary)
            }
        }
    }

    private var isRugby: Bool { league.family == .rugby }

    private func row(_ p: RosterPlayer, chevron: Bool) -> some View {
        HStack(spacing: 12) {
            if isRugby {
                Text(p.statLine.flatMap { line in RugbySquad.flags.values.first { line.contains($0) } } ?? "🏉")
                    .font(.system(size: 20))
                    .frame(width: 38, height: 38)
                    .background(Theme.card2, in: Circle())
            } else {
                // ESPN photo first; football players without one get their FotMob photo.
                PlayerPhoto(headshot: p.headshot, name: p.name, isFootball: league.family == .soccer,
                            teamLogo: nil, team: team, size: 38)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(p.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(p.statLine ?? [p.position, p.age.map { "Age \($0)" }, p.height].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer()
            if let j = p.jersey { Text("#\(j)").font(.subheadline.weight(.bold)).foregroundStyle(Theme.secondary) }
            if chevron {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.tertiary)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - Player

extension PlayerView {
    /// "2026-27 German Bundesliga" -> "Bundesliga"
    static func shortName(_ s: String) -> String {
        var n = s
        if let r = n.range(of: #"^\d{4}(-\d{2})?\s+"#, options: .regularExpression) { n.removeSubrange(r) }
        for p in ["German ", "English ", "UEFA "] where n.hasPrefix(p) { n.removeFirst(p.count) }
        return n
    }

    static func matches(_ league: String, _ competition: String) -> Bool {
        let a = shortName(league).lowercased(), b = shortName(competition).lowercased()
        return !a.isEmpty && (a.contains(b) || b.contains(a))
    }
}

struct PlayerView: View {
    let leagueId: String
    let playerId: String
    @State private var competition: String?

    var body: some View {
        let league = League.byId(leagueId)!
        ScrollView {
            Loader(id: "player-\(leagueId)-\(playerId)",
                   load: { () async throws -> PlayerPage in
                       if league.provider == .bbl { return try await BBL.player(playerId) }
                       return try await ESPN.player(league, id: playerId)
                   }) { p in
                VStack(spacing: 14) {
                    DetailHeader(image: p.headshot, isLogo: false, title: p.name, subtitle: p.team, color: nil,
                                 football: league.family == .soccer, lookUpPhoto: true)
                    VStack(spacing: 14) {
                        if let teamId = p.teamId, let team = p.team {
                            NavigationLink(value: Route.team(leagueId: leagueId, teamId: teamId)) {
                                HStack(spacing: 10) {
                                    LogoView(url: p.teamLogo, fallback: team, size: 28)
                                    Text(team).font(.headline)
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(Theme.secondary)
                                }
                                .card()
                            }
                            .buttonStyle(.plain)
                        }
                        if p.competitionStats.count > 1 {
                            ChipRow(items: ["All"] + p.competitionStats.map(\.name),
                                    selected: competition ?? "All",
                                    title: { Self.shortName($0) }) { competition = $0 == "All" ? nil : $0 }
                        }
                        if let c = competition, let split = p.competitionStats.first(where: { $0.name == c }) {
                            InfoList(title: Self.shortName(c), rows: split.rows)
                        } else {
                            InfoList(title: "This season", rows: p.seasonStats)
                        }
                        let log = competition.map { c in p.gameLog.filter { Self.matches($0.league, c) } } ?? p.gameLog
                        if !log.isEmpty { GameLogView(league: league, labels: p.gameLogLabels, entries: Array(log.prefix(10))) }
                        ForEach(Array(p.tables.enumerated()), id: \.offset) { _, t in StatTableView(table: t) }
                        if p.seasonStats.isEmpty && p.tables.isEmpty && p.gameLog.isEmpty && p.competitionStats.isEmpty {
                            MessageCard(text: "\(p.name) hasn’t played in the \(league.short) yet, so there are no stats.")
                        }
                        InfoList(title: "Bio", rows: p.bio)
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 40)
            }
        }
        .background(PageBackground())
        .navigationTitle(league.short)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

private struct GameLogView: View {
    let league: League
    let labels: [String]
    let entries: [GameLogEntry]

    /// A stand-in game: the game page loads everything else from the event id.
    private func route(_ e: GameLogEntry) -> Route? {
        guard league.provider == .espn, !e.id.isEmpty else { return nil }
        let blank = ESPN.side(J(nil))
        return .game(Game(id: e.id, leagueId: league.id, date: e.date ?? Date(), state: .post, statusText: "Final",
                          home: blank, away: blank, note: nil, broadcast: nil, scorers: []))
    }

    var body: some View {
        let rows = entries.map { e -> (name: String, values: [String]) in
            let date = e.date.map { Fmt.numeric($0) } ?? ""
            return ("\(date) \(e.atVs) \(e.opponent)", [e.result + " " + e.score] + e.stats)
        }
        StatTableView(table: StatTable(title: "Last \(entries.count) games", labels: ["Result"] + labels, rows: rows),
                      routes: entries.map(route))
    }
}

// MARK: - Favourites

struct FavoritesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var league: League = League.all.first { $0.isTeamSport }!

    var body: some View {
        List {
            Section("My Teams") {
                if store.favorites.isEmpty {
                    Text("No favourites yet. Pick a league below and tap the star next to a team.")
                        .foregroundStyle(Theme.secondary)
                }
                ForEach(store.favorites) { f in
                    HStack(spacing: 12) {
                        if f.kind == .team {
                            LogoView(url: f.logo, fallback: f.abbr, size: 28)
                        } else {
                            Image(systemName: f.kind == .rider ? "bicycle" : "tennis.racket").frame(width: 28)
                        }
                        VStack(alignment: .leading) {
                            Text(f.name)
                            Text(f.league?.name ?? "").font(.caption).foregroundStyle(Theme.secondary)
                        }
                    }
                }
                .onMove { store.favorites.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { store.favorites.remove(atOffsets: $0) }
            }
            Section {
                Picker("League", selection: $league) {
                    ForEach(League.all.filter(\.isTeamSport)) { Text($0.name).tag($0) }
                }
                TeamPicker(league: league)
            } header: {
                Text("Add teams")
            }
        }
        .navigationTitle("My Teams")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { EditButton() }
        .scrollContentBackground(.hidden)
        .background(PageBackground())
    }
}

private struct TeamPicker: View {
    let league: League
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Loader(id: "picker-\(league.id)",
               load: { () async throws -> [StandingRow] in
                   let groups: [StandingGroup]
                   if league.provider == .bbl { groups = try await BBL.standings() }
                   else { groups = try await ESPN.standings(league, divisions: false) }
                   var seen = Set<String>()
                   return groups.flatMap(\.rows).filter { seen.insert($0.id).inserted }.sorted { $0.name < $1.name }
               }) { teams in
            ForEach(teams) { t in
                let on = store.isFavorite(league: league.id, id: t.id)
                Button {
                    store.toggle(Favorite(leagueId: league.id, entityId: t.id, name: t.name, abbr: t.abbr, logo: t.logo))
                } label: {
                    HStack(spacing: 12) {
                        LogoView(url: t.logo, fallback: t.abbr, size: 26)
                        Text(t.name).foregroundStyle(.white)
                        Spacer()
                        Image(systemName: on ? "star.fill" : "star").foregroundStyle(on ? .yellow : Theme.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Tennis player / rider

struct TennisPlayerView: View {
    let id: String
    let name: String

    var body: some View {
        ScrollView {
            Loader(id: "tennis-\(id)", load: { try await TennisPlayerInfo.load(id: id, name: name) }) { info in
                VStack(spacing: 14) {
                    DetailHeader(image: info.headshot, isLogo: false, title: info.name, subtitle: info.country, color: "1b4d3e",
                                 trailing: AnyView(FavoriteButton(favorite: Favorite(kind: .tennisPlayer, leagueId: "atp", entityId: id, name: info.name, abbr: "", logo: nil))))
                        .padding(.top, 6)
                    VStack(spacing: 14) {
                        InfoList(title: "Ranking", rows: info.ranking)
                        if let s = info.season {
                            InfoList(title: "\(info.seasonYear) season", rows: [
                                InfoRow(label: "Win – loss", value: "\(s.wins) – \(s.losses)"),
                                InfoRow(label: "Titles", value: "\(s.titles.count)"),
                                InfoRow(label: "Finals", value: "\(s.finals)"),
                            ])
                            let finalsWon = s.matches.filter { $0.round == "Final" && $0.won }
                            if !finalsWon.isEmpty { TennisTitlesCard(finals: finalsWon, year: info.seasonYear) }
                            if !s.results.isEmpty { TennisResultsCard(results: s.results, year: info.seasonYear) }
                            if !s.matches.isEmpty { TennisMatchesCard(matches: Array(s.matches.prefix(10))) }
                        }
                        InfoList(title: "Career", rows: info.career)
                        InfoList(title: "Best results", rows: info.majors)
                        InfoList(title: "Bio", rows: info.bio)
                        if let extract = info.extract {
                            VStack(alignment: .leading, spacing: 8) {
                                CardTitle("About")
                                Text(extract).font(.subheadline)
                                Text("Wikipedia (CC BY-SA)").font(.caption2).foregroundStyle(Theme.tertiary)
                            }
                            .card()
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 40)
            }
        }
        .background(PageBackground())
        .navigationTitle("ATP")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

private struct TennisResultsCard: View {
    let results: [(tournament: String, tier: TennisTier, result: String)]
    var year: Int = Calendar.current.component(.year, from: Date())

    var body: some View {
        // Tournament rows open the draw (matched by name in the season calendar).
        Loader(id: "tennis-season-\(year)", load: { (try? await Tennis.season(year)) ?? [] }) { season in
            VStack(alignment: .leading, spacing: 0) {
                CardTitle("Tournaments")
                ForEach(Array(results.enumerated()), id: \.offset) { i, r in
                    if i > 0 { Divider().overlay(Theme.separator) }
                    let t = season.first { Tennis.cleanName($0.name) == r.tournament || $0.name == r.tournament }
                    Group {
                        if let t {
                            NavigationLink(value: Route.tournament(t)) { row(r, link: true) }.buttonStyle(.plain)
                        } else {
                            row(r, link: false)
                        }
                    }
                }
            }
            .card()
        }
    }

    private func row(_ r: (tournament: String, tier: TennisTier, result: String), link: Bool) -> some View {
        HStack(spacing: 8) {
            Text(r.tournament).font(.subheadline.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.85)
            TierBadge(tier: r.tier, name: r.tournament)
            Spacer(minLength: 8)
            Text(r.result == "Won" ? "🏆 Won" : r.result)
                .font(.subheadline.weight(r.result == "Won" ? .bold : .regular))
                .foregroundStyle(r.result == "Won" ? Color.yellow : Theme.secondary)
            if link { Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.tertiary) }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

/// One row per title of the season: tier badge, tournament, date and the final
/// ("d. J. Sinner 6-4 7-6"). Rows open the draw; the opponent opens their page.
private struct TennisTitlesCard: View {
    let finals: [Tennis.PlayerMatch]
    let year: Int

    var body: some View {
        Loader(id: "tennis-season-\(year)", load: { (try? await Tennis.season(year)) ?? [] }) { season in
            VStack(alignment: .leading, spacing: 0) {
                CardTitle("Titles")
                ForEach(Array(finals.enumerated()), id: \.element.id) { i, m in
                    if i > 0 { Divider().overlay(Theme.separator) }
                    let t = season.first { Tennis.cleanName($0.name) == m.tournament || $0.name == m.tournament }
                    HStack(alignment: .top, spacing: 10) {
                        Text("🏆").font(.title3)
                        VStack(alignment: .leading, spacing: 3) {
                            Group {
                                if let t {
                                    NavigationLink(value: Route.tournament(t)) { titleLine(m, link: true) }.buttonStyle(.plain)
                                } else {
                                    titleLine(m, link: false)
                                }
                            }
                            HStack(spacing: 4) {
                                Text("\(Fmt.date(m.date)) · d.").foregroundStyle(Theme.secondary)
                                NavigationLink(value: Route.tennisPlayer(id: m.opponentId, name: m.opponent)) {
                                    Text(m.opponent).underline(false).foregroundStyle(.white)
                                }
                                .buttonStyle(.plain)
                                .disabled(m.opponentId.isEmpty)
                                Text(m.score).foregroundStyle(Theme.secondary).monospacedDigit()
                            }
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .card()
        }
    }

    private func titleLine(_ m: Tennis.PlayerMatch, link: Bool) -> some View {
        HStack(spacing: 6) {
            Text(m.tournament).font(.subheadline.weight(.semibold)).lineLimit(2)
            TierBadge(tier: m.tier, name: m.tournament)
            Spacer(minLength: 4)
            if link { Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.tertiary) }
        }
        .contentShape(Rectangle())
    }
}

private struct TennisMatchesCard: View {
    let matches: [Tennis.PlayerMatch]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardTitle("Recent matches")
            ForEach(Array(matches.enumerated()), id: \.offset) { i, m in
                if i > 0 { Divider().overlay(Theme.separator) }
                NavigationLink {
                    TennisMatchView(match: m)
                } label: {
                    HStack(spacing: 10) {
                        Text(m.won ? "W" : "L")
                            .font(.caption.weight(.heavy)).foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(m.won ? Color(hex: "30d158") : Color(hex: "ff453a"), in: RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("vs \(m.opponent)").font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text("\(m.tournament) · \(m.round)")
                                .font(.caption).foregroundStyle(Theme.secondary).lineLimit(2)
                            Text(Fmt.date(m.date)).font(.caption).foregroundStyle(Theme.tertiary)
                        }
                        Spacer(minLength: 6)
                        Text(m.score).font(.footnote.weight(.semibold)).monospacedDigit().lineLimit(1).fixedSize()
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.tertiary)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }
}

/// One singles match: both players, set by set with tiebreaks, round, tournament and date.
/// (ESPN has no per-match statistics for tennis.)
struct TennisMatchView: View {
    let match: Tennis.PlayerMatch

    var body: some View {
        let m = match
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Text(m.tournament).font(.headline)
                        TierBadge(tier: m.tier, name: m.tournament)
                    }
                    Text("\(m.round) · \(Fmt.date(m.date))").font(.subheadline).foregroundStyle(Theme.secondary)
                }
                .padding(.top, 8)
                VStack(spacing: 0) {
                    playerRow(name: m.playerName.isEmpty ? "Player" : m.playerName, id: m.playerId, flag: m.playerFlag,
                              won: m.won, games: m.sets.map { ($0.mine, $0.theirs, $0.tiebreak) })
                    Divider().overlay(Theme.separator)
                    playerRow(name: m.opponent, id: m.opponentId, flag: m.opponentFlag,
                              won: !m.won, games: m.sets.map { ($0.theirs, $0.mine, $0.tiebreak) })
                }
                .card()
                Text("Tiebreak points of the set's loser are shown small. ESPN has no detailed match statistics for tennis.")
                    .font(.caption2).foregroundStyle(Theme.tertiary).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .background(PageBackground())
        .navigationTitle(m.round)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func playerRow(name: String, id: String, flag: URL?, won: Bool, games: [(Int, Int, Int?)]) -> some View {
        HStack(spacing: 10) {
            NavigationLink(value: Route.tennisPlayer(id: id, name: name)) {
                HStack(spacing: 8) {
                    TennisPhoto(name: name, espn: URL(string: "https://a.espncdn.com/i/headshots/tennis/players/full/\(id).png"), size: 40)
                    if let flag { CachedImage(url: flag) { $0.resizable().scaledToFit() } placeholder: { Color.clear }.frame(width: 20, height: 14) }
                    Text(name).font(.subheadline.weight(won ? .heavy : .regular)).lineLimit(2)
                        .foregroundStyle(won ? .white : Theme.secondary)
                    if won { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Theme.win) }
                }
            }
            .buttonStyle(.plain)
            .disabled(id.isEmpty)
            Spacer(minLength: 6)
            ForEach(Array(games.enumerated()), id: \.offset) { _, g in
                HStack(alignment: .top, spacing: 0) {
                    Text("\(g.0)").font(.title3.weight(g.0 > g.1 ? .heavy : .regular)).monospacedDigit()
                        .foregroundStyle(g.0 > g.1 ? .white : Theme.secondary)
                    if let tb = g.2, g.0 < g.1 {
                        Text("\(tb)").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondary)
                    }
                }
                .frame(minWidth: 26)
            }
        }
        .padding(.vertical, 10)
    }
}

struct TennisPlayerInfo {
    let name: String
    let headshot: URL?
    let country: String?
    let bio: [InfoRow]
    let ranking: [InfoRow]
    let season: Tennis.PlayerSeason?
    let seasonYear: Int
    let career: [InfoRow]
    let majors: [InfoRow]
    let extract: String?

    static func load(id: String, name: String) async throws -> TennisPlayerInfo {
        let cal = Calendar.current
        var year = cal.component(.year, from: Date())
        async let athlete = try? HTTP.shared.json(URL(string: "\(ESPN.common)/tennis/atp/athletes/\(id)")!, maxAge: 86_400)
        async let rankings = try? Tennis.rankings()
        async let careerInfo = Tennis.career(name: name)
        async let wiki = Wiki.summary(name + " (tennis)")
        var season = try? await Tennis.playerSeason(id: id, year: year)
        // Early in January the new season has no matches yet: show last season.
        if (season?.matches.isEmpty ?? true), cal.component(.month, from: Date()) <= 1 {
            year -= 1
            season = try? await Tennis.playerSeason(id: id, year: year)
        }

        let a = (await athlete)?["athlete"] ?? J(nil)
        var bio: [InfoRow] = []
        func add(_ l: String, _ v: String?) { if let v, !v.isEmpty { bio.append(InfoRow(label: l, value: v)) } }
        add("Age", a["age"].int.map(String.init))
        add("Born", Units.birthDate(a["displayDOB"].string, dayFirst: true))
        add("Height / Weight", [Units.height(a["displayHeight"].string), Units.weight(a["displayWeight"].string)].compactMap { $0 }.joined(separator: " · "))
        add("Plays", a["hand"]["displayValue"].string)
        add("Turned pro", a["debutYear"].int.map(String.init))

        var ranking: [InfoRow] = []
        if let r = (await rankings)?.first(where: { $0.playerId == id }) {
            ranking.append(InfoRow(label: "ATP ranking", value: "#\(r.rank)"))
            ranking.append(InfoRow(label: "Points", value: Int(r.points).formatted(.number.locale(Fmt.locale))))
            let mv = r.movement
            ranking.append(InfoRow(label: "Movement", value: mv > 0 ? "▲ \(mv)" : mv < 0 ? "▼ \(-mv)" : "–"))
        }
        let (career, majors) = await careerInfo
        let w = await wiki
        var extract = w?.extract
        if !(w?.description ?? "").lowercased().contains("tennis") { extract = await Wiki.summary(name)?.extract }
        let photo = await TennisPhotos.url(name: name, espn: URL(string: "https://a.espncdn.com/i/headshots/tennis/players/full/\(id).png"))
        let espnPhoto = URL(string: "https://a.espncdn.com/i/headshots/tennis/players/full/\(id).png")
        return TennisPlayerInfo(
            name: a["displayName"].string ?? name,
            headshot: photo ?? espnPhoto,
            country: a["citizenship"].string ?? a["flag"]["alt"].string,
            bio: bio, ranking: ranking,
            season: season, seasonYear: year,
            career: career, majors: majors,
            extract: extract
        )
    }
}

struct RiderView: View {
    let name: String

    var body: some View {
        ScrollView {
            Loader(id: "rider-\(name)", load: { await Wiki.summary(name) }) { w in
                VStack(spacing: 14) {
                    DetailHeader(image: w?.image, isLogo: false, title: w?.title ?? name, subtitle: w?.description, color: "5a4a00",
                                 trailing: AnyView(FavoriteButton(favorite: Favorite(kind: .rider, leagueId: "cycling", entityId: name, name: name, abbr: "", logo: nil))))
                    VStack(spacing: 14) {
                        if let e = w?.extract {
                            VStack(alignment: .leading, spacing: 8) {
                                CardTitle("About")
                                Text(e).font(.subheadline)
                                Text("Wikipedia (CC BY-SA)").font(.caption2).foregroundStyle(Theme.tertiary)
                            }
                            .card()
                        } else {
                            MessageCard(text: "No profile found for \(name).")
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 40)
            }
        }
        .background(PageBackground())
        .navigationTitle("Rider")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

/// Wikipedia page summaries (title, short description, extract, image).
enum Wiki {
    struct Summary {
        let title: String
        let description: String?
        let extract: String?
        let image: URL?
    }

    static func summary(_ title: String) async -> Summary? {
        guard let base = CyclingService.wikiURL(title)?.absoluteString.replacingOccurrences(of: "/page/html/", with: "/page/summary/"),
              let url = URL(string: base),
              let d = try? await HTTP.shared.json(url, maxAge: 86_400 * 7),
              d["type"].str != "disambiguation" else { return nil }
        return Summary(title: d["title"].str, description: d["description"].string,
                       extract: d["extract"].string, image: d["thumbnail"]["source"].url)
    }
}
