import SwiftUI

struct CyclingView: View {
    var refresh = 0
    @State private var year: Int
    @State private var tour: TourDef
    @AppStorage("cyclingTab") private var tab = 0

    init(refresh: Int = 0) {
        self.refresh = refresh
        // Default: the most recent Grand Tour that has started.
        let now = Date()
        let cal = Calendar.current
        let y = cal.component(.year, from: now)
        let m = cal.component(.month, from: now)
        let startMonths = ["giro": 5, "tour": 7, "vuelta": 8]
        let started = TourDef.all.last { (startMonths[$0.id] ?? 13) <= m }
        _year = State(initialValue: started == nil ? y - 1 : y)
        _tour = State(initialValue: started ?? TourDef.all[2])
    }

    var body: some View {
        let thisYear = Calendar.current.component(.year, from: Date())
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $tab) {
                Text("Grand Tours").tag(0)
                Text("WorldTour").tag(1)
            }
            .pickerStyle(.segmented)
            if tab == 1 {
                WorldTourList(refresh: refresh)
            } else {
            ChipRow(items: [thisYear, thisYear - 1, thisYear - 2], selected: year, title: { String($0) }) { year = $0 }
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
                        HStack(spacing: 10) {
                            JerseyBadge(color: j.color)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(j.label).font(.caption2).foregroundStyle(Theme.secondary)
                                    .lineLimit(1).minimumScaleFactor(0.75)
                                Text(edition.leader(j.key) ?? "—").font(.footnote.weight(.bold))
                                    .lineLimit(2).minimumScaleFactor(0.7)
                            }
                            Spacer(minLength: 0)
                        }
                        // Same height for all four cards, whatever the name length.
                        .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46, alignment: .leading)
                        .padding(12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
