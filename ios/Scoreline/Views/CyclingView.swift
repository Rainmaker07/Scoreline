import SwiftUI

/// Cycling: "Race Calendar" (all WorldTour races; the Grand Tours filter opens the
/// Grand Tour view) and "Rankings" (UCI World Tour ranking and win leaders).
struct CyclingView: View {
    var refresh = 0
    @AppStorage("cyclingTabV2") private var tab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $tab) {
                Text("Race Calendar").tag(0)
                Text("Teams").tag(2)
                Text("Rankings").tag(1)
            }
            .pickerStyle(.segmented)
            if tab == 1 {
                CyclingRankingsView(refresh: refresh)
            } else if tab == 2 {
                CyclingTeamsView(refresh: refresh)
            } else {
                WorldTourList(refresh: refresh)
            }
        }
    }
}

/// Giro / Tour / Vuelta cards and the selected edition (stages, jerseys, classifications).
struct GrandToursPanel: View {
    let year: Int
    var refresh = 0
    @State private var tour: TourDef

    init(year: Int, refresh: Int = 0) {
        self.year = year
        self.refresh = refresh
        // Default: the most recent Grand Tour that has started that year (else the Giro).
        let cal = Calendar.current
        let thisYear = cal.component(.year, from: Date())
        let m = year < thisYear ? 12 : cal.component(.month, from: Date())
        let startMonths = ["giro": 5, "tour": 7, "vuelta": 8]
        _tour = State(initialValue: TourDef.all.last { (startMonths[$0.id] ?? 13) <= m } ?? TourDef.all[0])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(TourDef.all) { t in
                    Button { tour = t } label: {
                        VStack(spacing: 6) {
                            TourLogo(tour: t, size: 44)
                            Text(t.short).font(.subheadline.weight(.bold))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 92, maxHeight: 92)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(t == tour ? Color.white : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            Loader(id: "\(tour.id)-\(year)-\(refresh)",
                   poll: { (e: Edition) in CyclingService.isFinished(e.def, e.year) ? nil : 600 },
                   load: { () async throws -> Edition in
                       if refresh > 0, !CyclingService.isFinished(tour, year) { await CyclingService.invalidate(tour, year: year) }
                       return try await CyclingService.load(tour, year: year)
                   }) { edition in
                EditionBody(edition: edition)
            }
            Text("Results from Wikipedia (CC BY-SA). Finished races are stored on this iPhone and never re-downloaded.")
                .font(.caption2)
                .foregroundStyle(Theme.tertiary)
                .padding(.horizontal, 4)
        }
    }
}

struct JerseyBadge: View {
    let color: String
    var size: CGFloat = 26
    var body: some View {
        Image(systemName: "tshirt.fill")
            .font(.system(size: size))
            .foregroundStyle(Color(hex: color))
            .shadow(color: .black.opacity(0.4), radius: 1)
    }
}

struct EditionBody: View {
    let edition: Edition
    @State private var tab = 0
    @State private var jersey: JerseyKey = .gc
    @State private var showTeams = false

    var body: some View {
        let def = edition.def
        VStack(alignment: .leading, spacing: 12) {
            header
            if edition.stages.isEmpty {
                MessageCard(text: "\(def.name) \(edition.year) isn’t on Wikipedia yet. The route usually appears after it’s presented.")
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(def.jerseys, id: \.key) { j in
                        let leader = edition.leader(j.key)
                        let card = HStack(spacing: 10) {
                            JerseyBadge(color: j.color)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(j.label).font(.caption2).foregroundStyle(Theme.secondary)
                                    .lineLimit(1).minimumScaleFactor(0.75)
                                Text(leader ?? "—").font(.footnote.weight(.bold))
                                    .lineLimit(2).minimumScaleFactor(0.7)
                            }
                            Spacer(minLength: 0)
                            if leader != nil {
                                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(Theme.tertiary)
                            }
                        }
                        // Same height for all four cards, whatever the name length.
                        .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46, alignment: .leading)
                        .padding(12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .contentShape(Rectangle())
                        if let leader {
                            NavigationLink(value: Route.rider(name: leader)) { card }.buttonStyle(.plain)
                        } else {
                            card
                        }
                    }
                }
                Picker("", selection: $tab) {
                    Text("Stages").tag(0)
                    Text("Classifications").tag(1)
                }
                .pickerStyle(.segmented)
                if tab == 0 { stageList } else { classifications }
            }
        }
    }

    private var header: some View {
        let def = edition.def
        let status: String = {
            if edition.winner != nil { return "Finished" }
            if edition.lastRaced != nil { return "Racing · after stage \(edition.lastRaced!.n)" }
            return "Upcoming"
        }()
        return VStack(alignment: .leading, spacing: 4) {
            TourLogo(tour: def, size: 56)
            Text(verbatim: "\(def.name) \(edition.year)").font(.title2.weight(.heavy))
            if let d = edition.dates { Text(Fmt.text(d)).font(.footnote).foregroundStyle(Theme.secondary) }
            HStack(spacing: 6) {
                if status.hasPrefix("Racing") { LivePulse() }
                Text(status).foregroundStyle(status.hasPrefix("Racing") ? Theme.live : Theme.secondary)
                if let w = edition.winner { Text("· Winner:").foregroundStyle(Theme.secondary); Text(w) }
            }
            .font(.footnote.weight(.bold))
            .padding(.top, 4)
        }
        .card()
        .background(
            LinearGradient(colors: [Color(hex: def.color).opacity(0.35), .clear], startPoint: .topLeading, endPoint: .center)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        )
    }

    private var stageList: some View {
        VStack(spacing: 0) {
            ForEach(Array(edition.stages.enumerated()), id: \.element.id) { i, s in
                if i > 0 { Divider().overlay(Theme.separator) }
                NavigationLink {
                    StageDetailView(edition: edition, stage: s)
                } label: {
                    StageRow(stage: s)
                }
                .buttonStyle(.plain)
            }
        }
        .card(padding: 14)
    }

    private var classifications: some View {
        let def = edition.def
        let list: [RiderResult] = showTeams ? edition.teams : (edition.classifications[jersey] ?? [])
        return VStack(alignment: .leading, spacing: 12) {
            ChipScroll {
                    ForEach(JerseyKey.allCases, id: \.self) { k in
                        Chip(title: classTitle(k), selected: !showTeams && jersey == k) { jersey = k; showTeams = false }
                    }
                    if !edition.teams.isEmpty {
                        Chip(title: "Teams", selected: showTeams) { showTeams = true }
                    }
                }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    if !showTeams { JerseyBadge(color: def.jersey(jersey).color, size: 18) }
                    CardTitle(showTeams ? "Team classification" : def.jersey(jersey).label)
                }
                if list.isEmpty {
                    Text("Not available yet.").font(.subheadline).foregroundStyle(Theme.secondary)
                }
                RiderList(riders: list, teams: showTeams)
            }
            .card()
        }
    }

    private func classTitle(_ k: JerseyKey) -> String {
        switch k {
        case .gc: return "General"
        case .points: return "Points"
        case .kom: return "Mountains"
        case .youth: return "Young Rider"
        }
    }
}

struct TourLogo: View {
    let tour: TourDef
    var size: CGFloat = 44
    var body: some View {
        if let url = LogoAssets.grandTour(tour.id) {
            // Light badge: the Tour and Giro logos are dark lettering.
            LogoView(url: url, fallback: tour.short, size: size)
                .padding(4)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            Capsule().fill(Color(hex: tour.color)).frame(width: size, height: 4)
        }
    }
}

struct RiderList: View {
    let riders: [RiderResult]
    var teams = false
    @EnvironmentObject private var store: AppStore
    var body: some View {
        let starred = store.favoriteNames(kind: .rider)
        ForEach(Array(riders.enumerated()), id: \.offset) { i, r in
            if i > 0 { Divider().overlay(Theme.separator) }
            row(r, starred: !teams && starred.contains(r.name.lowercased()))
        }
    }

    /// Rider name and team are separate links (a link inside a link doesn't receive taps).
    private func row(_ r: RiderResult, starred: Bool) -> some View {
        HStack(spacing: 10) {
            Text("\(r.rank)").font(.footnote.weight(.bold)).foregroundStyle(Theme.secondary).frame(width: 22, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                NavigationLink(value: teams ? Route.cyclingTeam(r.name) : Route.rider(name: r.name)) {
                    HStack(spacing: 5) {
                        Text(r.name).font(.subheadline.weight(.bold)).lineLimit(1)
                        if let c = r.country { Text(c).font(.caption2.weight(.semibold)).foregroundStyle(Theme.secondary) }
                    }
                }
                .buttonStyle(.plain)
                if !r.team.isEmpty {
                    NavigationLink(value: Route.cyclingTeam(r.team)) {
                        Text(r.team).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
            Text(r.value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .padding(.vertical, 8)
        .background(starred ? Color.yellow.opacity(0.10) : .clear)
    }
}

private struct StageRow: View {
    let stage: CyclingStage
    var body: some View {
        HStack(spacing: 12) {
            Text("\(stage.n)")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Theme.secondary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(stage.route).font(.subheadline.weight(.semibold))
                    .lineLimit(1).minimumScaleFactor(0.6)
                HStack(spacing: 6) {
                    KindBadge(kind: stage.kind)
                    Text([stage.date.map { Fmt.date($0) }, stage.km.map { "\(Int($0.rounded())) km" }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(Theme.secondary)
                        .lineLimit(1).fixedSize()
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(stage.winner ?? "—").font(.footnote.weight(.semibold))
                    .lineLimit(2).multilineTextAlignment(.trailing).minimumScaleFactor(0.85)
                if let c = stage.winnerCountry { Text(c).font(.caption2).foregroundStyle(Theme.secondary) }
            }
            .frame(maxWidth: 96, alignment: .trailing)
            .layoutPriority(-1)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct KindBadge: View {
    let kind: StageKind
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: kind.symbol)
            Text(kind.label.uppercased())
        }
        .lineLimit(1)
        .fixedSize()
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(colors.fg)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(colors.bg, in: RoundedRectangle(cornerRadius: 6))
    }

    private var colors: (fg: Color, bg: Color) {
        switch kind {
        case .flat: return (Color(hex: "4ade80"), Color(hex: "1f3b2a"))
        case .hilly: return (Color(hex: "facc15"), Color(hex: "3b331f"))
        case .mountain: return (Color(hex: "f87171"), Color(hex: "3b1f1f"))
        case .itt, .ttt: return (Color(hex: "60a5fa"), Color(hex: "1f2b3b"))
        }
    }
}


/// All WorldTeams (sorted by season wins) and ProTeams; each opens the team page.
struct CyclingTeamsView: View {
    var refresh = 0

    private struct Row: Identifiable {
        var id: String { team.name }
        let team: CyclingTeams.Team
        let logo: URL?
        let wins: Int?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Loader(id: "wt-teams-\(refresh)", load: { () async throws -> [Row] in
                let teams = try await CyclingTeams.worldTeams()
                // Logo and season wins from each team page (six at a time).
                let rows: [Row] = await withTaskGroup(of: Row.self) { group in
                    var out: [Row] = []
                    var next = 0
                    while next < min(6, teams.count) {
                        let t = teams[next]
                        group.addTask {
                            let p = try? await CyclingPeople.team(t.name)
                            return Row(team: t, logo: p?.image, wins: p?.wins.map { max(0, $0.rows.count - 1) })
                        }
                        next += 1
                    }
                    for await r in group {
                        out.append(r)
                        if next < teams.count {
                            let t = teams[next]
                            group.addTask {
                                let p = try? await CyclingPeople.team(t.name)
                                return Row(team: t, logo: p?.image, wins: p?.wins.map { max(0, $0.rows.count - 1) })
                            }
                            next += 1
                        }
                    }
                    return out
                }
                return rows.sorted { ($0.wins ?? -1, $1.team.name) > ($1.wins ?? -1, $0.team.name) }
            }) { rows in
                section("UCI WorldTeams", rows: rows, showWins: true)
            }
            Text("UCI WorldTeams from Wikipedia; wins from each team's season article.")
                .font(.caption2).foregroundStyle(Theme.tertiary).padding(.horizontal, 4)
        }
    }

    @ViewBuilder private func section(_ title: String, rows: [Row], showWins: Bool) -> some View {
        if rows.isEmpty {
            MessageCard(text: "\(title): not available right now.")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                CardTitle(title)
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                    if i > 0 { Divider().overlay(Theme.separator) }
                    NavigationLink(value: Route.cyclingTeam(r.team.name)) {
                        HStack(spacing: 12) {
                            TeamLogoBadge(name: r.team.name, logo: r.logo)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.team.name).font(.subheadline.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.85)
                                if let c = r.team.country { Text(c).font(.caption).foregroundStyle(Theme.secondary) }
                            }
                            Spacer(minLength: 6)
                            if showWins, let w = r.wins {
                                VStack(spacing: 0) {
                                    Text("\(w)").font(.headline.weight(.heavy)).monospacedDigit()
                                    Text(w == 1 ? "win" : "wins").font(.caption2).foregroundStyle(Theme.secondary)
                                }
                            }
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
}

/// Team logo (looked up from the team page when not given), else initials.
struct TeamLogoBadge: View {
    let name: String
    let logo: URL?
    @State private var found: URL??

    var body: some View {
        let url = logo ?? (found ?? nil)
        LogoView(url: url, fallback: name, size: 32)
            .padding(3)
            .background(Color.white.opacity(url == nil ? 0 : 0.9), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(width: 38, height: 38)
            .task(id: name) {
                guard logo == nil, found == nil else { return }
                found = .some((try? await CyclingPeople.team(name))?.image)
            }
    }
}
