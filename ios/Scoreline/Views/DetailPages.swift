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
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(table.title)
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("").frame(height: 22)
                    ForEach(Array(table.rows.enumerated()), id: \.offset) { _, r in
                        Text(r.name).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7).frame(height: 30, alignment: .leading)
                    }
                }
                .frame(width: 104, alignment: .leading)
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .trailing, spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(Array(table.labels.enumerated()), id: \.offset) { cell($0.element) }
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.secondary)
                        .frame(height: 22)
                        ForEach(Array(table.rows.enumerated()), id: \.offset) { _, r in
                            HStack(spacing: 0) {
                                ForEach(Array(r.values.enumerated()), id: \.offset) { cell($0.element) }
                            }
                            .font(.footnote)
                            .frame(height: 30)
                        }
                    }
                    .monospacedDigit()
                }
            }
        }
        .card()
    }

    private func cell(_ t: String) -> some View {
        Text(t).lineLimit(1).frame(minWidth: 46, alignment: .trailing).padding(.horizontal, 2)
    }
}

struct DetailHeader: View {
    let image: URL?
    let isLogo: Bool
    let title: String
    let subtitle: String?
    let color: String?
    var trailing: AnyView? = nil

    var body: some View {
        let tint = Color.visibleTint(color) ?? Color(white: 0.3)
        VStack(spacing: 10) {
            if isLogo {
                LogoView(url: image, fallback: title, size: 88)
            } else {
                AsyncImage(url: image) { $0.resizable().scaledToFill() } placeholder: {
                    Image(systemName: "person.fill").font(.system(size: 40)).foregroundStyle(Theme.secondary)
                }
                .frame(width: 104, height: 104)
                .background(Theme.card2)
                .clipShape(Circle())
            }
            Text(title).font(.title2.weight(.heavy)).multilineTextAlignment(.center)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
            }
            if let trailing { trailing }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(LinearGradient(colors: [tint.opacity(0.85), .black], startPoint: .top, endPoint: .bottom))
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
                        case 1: TeamRoster(league: league, roster: t.roster)
                        default:
                            if let c = competition.flatMap(League.byId) {
                                CompetitionRecord(team: t, league: c, games: games)
                            } else {
                                InfoList(title: "Season", rows: t.stats)
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
        .background(Theme.bg.ignoresSafeArea())
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
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
        var w = 0, d = 0, l = 0, gf = 0, ga = 0
        for g in done {
            let me = g.home.id == team.id ? g.home : g.away
            let them = g.home.id == team.id ? g.away : g.home
            let a = Int(me.score ?? "") ?? 0, b = Int(them.score ?? "") ?? 0
            gf += a; ga += b
            if a > b { w += 1 } else if a == b { d += 1 } else { l += 1 }
        }
        let rows = [InfoRow(label: "Played", value: "\(done.count)"),
                    InfoRow(label: "Won – drawn – lost", value: "\(w) – \(d) – \(l)"),
                    InfoRow(label: "Goals", value: "\(gf):\(ga)"),
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
                            Text(g.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            if showCompetition {
                                LeagueIcon(league: g.league, size: 12)
                                Text(g.league.short)
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondary)
                        .padding(.top, 8)
                        GameRow(game: g)
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
    let roster: [RosterPlayer]

    var body: some View {
        let groups = Dictionary(grouping: roster) { $0.group ?? "" }
        let order = roster.reduce(into: [String]()) { acc, p in if !acc.contains(p.group ?? "") { acc.append(p.group ?? "") } }
        VStack(spacing: 14) {
            if roster.isEmpty { MessageCard(text: "Roster not available.") }
            ForEach(order, id: \.self) { g in
                VStack(alignment: .leading, spacing: 0) {
                    CardTitle(g.isEmpty ? "Roster" : g)
                    ForEach(Array((groups[g] ?? []).enumerated()), id: \.element.id) { i, p in
                        if i > 0 { Divider().overlay(Theme.separator) }
                        NavigationLink(value: Route.player(leagueId: league.id, playerId: p.id)) {
                            HStack(spacing: 12) {
                                AsyncImage(url: p.headshot) { $0.resizable().scaledToFill() } placeholder: { Theme.card2 }
                                    .frame(width: 38, height: 38).clipShape(Circle())
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(p.statLine ?? [p.position, p.age.map { "Age \($0)" }, p.height].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                                }
                                Spacer()
                                if let j = p.jersey { Text("#\(j)").font(.subheadline.weight(.bold)).foregroundStyle(Theme.secondary) }
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.tertiary)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .card(padding: 14)
            }
        }
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
                    DetailHeader(image: p.headshot, isLogo: false, title: p.name, subtitle: p.team, color: nil)
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
                        if !log.isEmpty { GameLogView(labels: p.gameLogLabels, entries: Array(log.prefix(10))) }
                        ForEach(Array(p.tables.enumerated()), id: \.offset) { _, t in StatTableView(table: t) }
                        InfoList(title: "Bio", rows: p.bio)
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 40)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(league.short)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

private struct GameLogView: View {
    let labels: [String]
    let entries: [GameLogEntry]

    var body: some View {
        let rows = entries.map { e -> (name: String, values: [String]) in
            let date = e.date.map { $0.formatted(.dateTime.month(.defaultDigits).day()) } ?? ""
            return ("\(date) \(e.atVs) \(e.opponent)", [e.result + " " + e.score] + e.stats)
        }
        StatTableView(table: StatTable(title: "Last \(entries.count) games", labels: ["Result"] + labels, rows: rows))
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
        .background(Theme.bg.ignoresSafeArea())
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
                    VStack(spacing: 14) {
                        InfoList(title: "Bio", rows: info.bio)
                        InfoList(title: "Summary", rows: info.summary)
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
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("ATP")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

struct TennisPlayerInfo {
    let name: String
    let headshot: URL?
    let country: String?
    let bio: [InfoRow]
    let summary: [InfoRow]
    let extract: String?

    static func load(id: String, name: String) async throws -> TennisPlayerInfo {
        let a = (try? await HTTP.shared.json(URL(string: "\(ESPN.common)/tennis/atp/athletes/\(id)")!, maxAge: 86_400))?["athlete"] ?? J(nil)
        var bio: [InfoRow] = []
        func add(_ l: String, _ v: String?) { if let v, !v.isEmpty { bio.append(InfoRow(label: l, value: v)) } }
        add("Age", a["age"].int.map(String.init))
        add("Born", a["displayDOB"].string)
        add("Height / Weight", [a["displayHeight"].string, a["displayWeight"].string].compactMap { $0 }.joined(separator: " · "))
        add("Plays", a["hand"]["displayValue"].string)
        add("Turned pro", a["debutYear"].int.map(String.init))
        let summary = a["statsSummary"]["statistics"].array.map { InfoRow(label: $0["displayName"].str, value: $0["displayValue"].str) }
        let wiki = await Wiki.summary(name)
        return TennisPlayerInfo(
            name: a["displayName"].string ?? name,
            headshot: URL(string: "https://a.espncdn.com/i/headshots/tennis/players/full/\(id).png"),
            country: a["citizenship"].string ?? a["flag"]["alt"].string,
            bio: bio, summary: summary,
            extract: wiki?.extract
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
        .background(Theme.bg.ignoresSafeArea())
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
