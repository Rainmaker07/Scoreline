import SwiftUI

// MARK: - WorldTour calendar

struct WorldTourList: View {
    var refresh = 0
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var filter = 0 // 0 all, 1 grand tours, 2 stage races, 3 one-day

    var body: some View {
        let thisYear = Calendar.current.component(.year, from: Date())
        VStack(alignment: .leading, spacing: 12) {
            ChipRow(items: [thisYear, thisYear - 1, thisYear - 2], selected: year, title: { String($0) }) { year = $0 }
            ChipScroll {
                    ForEach(Array(["All", "Grand Tours", "Stage races", "One-day races"].enumerated()), id: \.offset) { i, t in
                        Chip(title: t, selected: filter == i) { filter = i }
                    }
                }
            if filter == 1 {
                GrandToursPanel(year: year, refresh: refresh).id(year)
            } else {
            Loader(id: "wt-\(year)-\(refresh)", load: { try await WorldTour.calendar(year) }) { races in
                let list = races.filter { r in
                    switch filter {
                    case 1: return r.isGrandTour
                    case 2: return !r.isGrandTour && !r.isOneDay
                    case 3: return r.isOneDay
                    default: return true
                    }
                }
                let live = list.filter(\.isLive)
                VStack(alignment: .leading, spacing: 14) {
                    if races.isEmpty { MessageCard(text: "The \(String(year)) WorldTour calendar isn’t available yet.") }
                    if !live.isEmpty {
                        SectionHeader(title: "This Week")
                        raceCard(live)
                    }
                    let months = Dictionary(grouping: list.filter { $0.start != nil }) { Calendar.current.component(.month, from: $0.start!) }
                    ForEach(months.keys.sorted(), id: \.self) { m in
                        VStack(alignment: .leading, spacing: 0) {
                            CardTitle(Calendar.current.monthSymbols[m - 1])
                            ForEach(Array((months[m] ?? []).enumerated()), id: \.element.id) { i, r in
                                if i > 0 { Divider().overlay(Theme.separator) }
                                RaceRow(race: r)
                            }
                        }
                        .card(padding: 14)
                    }
                }
            }
            }
        }
    }

    private func raceCard(_ list: [WTRace]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element.id) { i, r in
                if i > 0 { Divider().overlay(Theme.separator) }
                RaceRow(race: r)
            }
        }
        .card(padding: 14)
    }
}

private struct RaceRow: View {
    let race: WTRace
    var body: some View {
        NavigationLink(value: Route.cyclingRace(race)) {
            HStack(spacing: 12) {
                RaceLogo(race: race, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(race.name).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        if race.isMonument {
                            Text("MONUMENT").font(.system(size: 8, weight: .heavy)).foregroundStyle(.yellow)
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    Text([Fmt.text(race.dates), race.country, race.winner.map { "🏆 \($0)" }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if race.isLive {
                    HStack(spacing: 4) { LivePulse(); Text("Racing") }.font(.caption.weight(.bold)).foregroundStyle(Theme.live)
                }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.tertiary)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A WorldTour race: stage races use the Grand Tour page, one-day races show the result.
struct RaceView: View {
    let race: WTRace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if race.start != nil && race.start == race.end {
                    Loader(id: "oneday-\(race.id)", load: { try await WorldTour.oneDay(race) }) { r in
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 10) {
                                    RaceLogo(race: race, size: 44)
                                    Text(verbatim: "\(r.name) \(r.year)").font(.title2.weight(.heavy))
                                }
                                Text([r.dates.map(Fmt.text), r.distance].compactMap { $0 }.joined(separator: " · ")).font(.footnote).foregroundStyle(Theme.secondary)
                                if let w = r.results.first { Text("Winner: \(w.name)").font(.subheadline.weight(.bold)).padding(.top, 4) }
                            }
                            .card()
                            if r.results.isEmpty {
                                MessageCard(text: (race.start ?? Date()) > Date() ? "Results appear after the race." : "No result table on Wikipedia yet.")
                            } else {
                                VStack(alignment: .leading, spacing: 0) {
                                    CardTitle("Result")
                                    RiderList(riders: r.results)
                                }
                                .card()
                            }
                            if !r.summary.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    CardTitle("Race summary")
                                    ForEach(Array(r.summary.prefix(4).enumerated()), id: \.offset) { _, p in Text(p).font(.subheadline) }
                                }
                                .card()
                            }
                        }
                    }
                } else {
                    let def = WorldTour.def(for: race)
                    Loader(id: "stagerace-\(race.id)", load: { try await CyclingService.load(def, year: race.year) }) { edition in
                        EditionBody(edition: edition)
                    }
                }
                Text("From Wikipedia (CC BY-SA).").font(.caption2).foregroundStyle(Theme.tertiary)
            }
            .padding(16)
        }
        .background(PageBackground(color: "5a4a00"))
        .navigationTitle(race.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

// MARK: - Rider page

struct RiderPageView: View {
    let name: String

    var body: some View {
        ScrollView {
            Loader(id: "riderpage-\(name)", load: { try await CyclingPeople.rider(name) }) { p in
                VStack(spacing: 14) {
                    DetailHeader(image: p.image, isLogo: false, title: p.name, subtitle: p.description, color: "5a4a00",
                                 trailing: AnyView(FavoriteButton(favorite: Favorite(kind: .rider, leagueId: "cycling", entityId: name, name: name, abbr: "", logo: nil))))
                    VStack(spacing: 14) {
                        if let team = p.currentTeam {
                            NavigationLink(value: Route.cyclingTeam(team)) {
                                HStack {
                                    Image(systemName: "person.3.fill").foregroundStyle(Theme.secondary)
                                    Text(team).font(.headline)
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(Theme.secondary)
                                }
                                .card()
                            }
                            .buttonStyle(.plain)
                        }
                        InfoList(title: "Profile", rows: p.info)
                        RiderSeasonCard(name: name)
                        if !p.teams.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                CardTitle("Teams")
                                ForEach(Array(p.teams.enumerated()), id: \.offset) { i, t in
                                    if i > 0 { Divider().overlay(Theme.separator) }
                                    NavigationLink(value: Route.cyclingTeam(t.team)) {
                                        HStack {
                                            Text(t.years).font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary).frame(width: 90, alignment: .leading)
                                            Text(t.team).font(.subheadline)
                                            Spacer()
                                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.tertiary)
                                        }
                                        .padding(.vertical, 8)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .card()
                        }
                        ForEach(Array(p.majorWins.enumerated()), id: \.offset) { _, group in
                            DisclosureCard(title: "Major wins · \(group.category)", items: group.items)
                        }
                        if let e = p.extract {
                            VStack(alignment: .leading, spacing: 8) {
                                CardTitle("About")
                                Text(e).font(.subheadline)
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
        .navigationTitle("Rider")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

struct DisclosureCard: View {
    let title: String
    let items: [String]
    @State private var open = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.snappy) { open.toggle() } } label: {
                HStack {
                    CardTitle(title)
                    Spacer()
                    Text("\(items.count)").font(.footnote.weight(.bold)).foregroundStyle(Theme.secondary)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.secondary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                    Text(it).font(.subheadline).padding(.vertical, 5)
                        .overlay(alignment: .top) { Divider().overlay(Theme.separator) }
                }
            }
        }
        .card()
    }
}

/// The rider's stage wins, top-10s and classification placings in this season's Grand Tours.
private struct RiderSeasonCard: View {
    let name: String
    var body: some View {
        Loader(id: "season-\(name)", load: { await Self.load(name) }) { rows in
            if !rows.isEmpty {
                InfoList(title: "This season · Grand Tours", rows: rows)
            }
        }
    }

    static func load(_ name: String) async -> [InfoRow] {
        let year = Calendar.current.component(.year, from: Date())
        let key = name.lowercased()
        var out: [InfoRow] = []
        for def in TourDef.all {
            guard let e = try? await CyclingService.load(def, year: year) else { continue }
            if let gc = e.classifications[.gc]?.first(where: { $0.name.lowercased() == key }) {
                out.append(InfoRow(label: "\(def.short) · GC", value: BBL.ordinal(gc.rank)))
            }
            for k in [JerseyKey.points, .kom, .youth] {
                if let r = e.classifications[k]?.first(where: { $0.name.lowercased() == key }), r.rank <= 3 {
                    out.append(InfoRow(label: "\(def.short) · \(def.jersey(k).label)", value: BBL.ordinal(r.rank)))
                }
            }
            for s in e.stages {
                if s.winner?.lowercased() == key {
                    out.append(InfoRow(label: "\(def.short) · Stage \(s.n)", value: "🏆 Won"))
                } else if let r = s.result.first(where: { $0.name.lowercased() == key }), r.rank <= 10 {
                    out.append(InfoRow(label: "\(def.short) · Stage \(s.n)", value: BBL.ordinal(r.rank)))
                }
            }
        }
        return out
    }
}

// MARK: - Cycling team page

struct CyclingTeamView: View {
    let name: String
    var body: some View {
        ScrollView {
            Loader(id: "cteam-\(name)", load: { try await CyclingPeople.team(name) }) { t in
                VStack(spacing: 14) {
                    DetailHeader(image: t.image, isLogo: true, title: t.name, subtitle: nil, color: "5a4a00")
                    VStack(spacing: 14) {
                        InfoList(title: "Team", rows: t.info)
                        if let roster = t.roster { WikiTableCard(table: WikiTable(caption: "Roster", rows: roster.rows)) }
                        if let wins = t.wins { WikiTableCard(table: WikiTable(caption: "Season wins", rows: wins.rows)) }
                        if t.roster == nil && t.wins == nil && t.info.isEmpty {
                            MessageCard(text: "No team details found on Wikipedia for \(name).")
                        }
                        if let e = t.extract {
                            VStack(alignment: .leading, spacing: 8) {
                                CardTitle("About")
                                Text(e).font(.subheadline)
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
        .navigationTitle("Team")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

// MARK: - Rankings

/// UCI World Tour ranking (riders, teams) and the season's win leaders.
struct CyclingRankingsView: View {
    var refresh = 0
    @State private var year = Calendar.current.component(.year, from: Date())
    @AppStorage("cyclingRankingKind") private var kind = 0   // 0 riders, 1 teams, 2 wins

    var body: some View {
        let thisYear = Calendar.current.component(.year, from: Date())
        VStack(alignment: .leading, spacing: 12) {
            ChipRow(items: [thisYear, thisYear - 1, thisYear - 2], selected: year, title: { String($0) }) { year = $0 }
            TextTabs(items: [0, 1, 2], selection: $kind) { ["Riders", "Teams", "Most wins"][$0] }
            if kind == 2 {
                Loader(id: "wins-\(year)-\(refresh)", load: { try await CyclingRankings.winLeaders(year) }) { list in
                    if list.isEmpty {
                        MessageCard(text: "No WorldTour results for \(String(year)) yet.")
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            CardTitle("Most wins · WorldTour")
                            ForEach(Array(list.enumerated()), id: \.element.id) { i, w in
                                if i > 0 { Divider().overlay(Theme.separator) }
                                NavigationLink(value: Route.rider(name: w.name)) {
                                    HStack(spacing: 12) {
                                        Text("\(i + 1)").font(.footnote.weight(.bold)).foregroundStyle(Theme.secondary).frame(width: 22)
                                        VStack(alignment: .leading, spacing: 1) {
                                            HStack(spacing: 5) {
                                                Text(w.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                                if let c = w.country { Text(c).font(.caption2).foregroundStyle(Theme.secondary) }
                                            }
                                            Text(w.detail).font(.caption).foregroundStyle(Theme.secondary)
                                        }
                                        Spacer()
                                        Text("\(w.wins)").font(.title3.weight(.heavy)).monospacedDigit()
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
                Text("Counts one-day wins, overall wins and stage wins in WorldTour races (Wikipedia).")
                    .font(.caption2).foregroundStyle(Theme.tertiary).padding(.horizontal, 4)
            } else {
                Loader(id: "uci-rank-\(year)-\(refresh)", load: { try await CyclingRankings.rankings(year) }) { r in
                    let list = kind == 0 ? r.riders : r.teams
                    if list.isEmpty {
                        MessageCard(text: "The \(String(year)) UCI World Tour ranking isn’t on Wikipedia yet.")
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            CardTitle(kind == 0 ? "UCI World Tour · Riders" : "UCI World Tour · Teams")
                            ForEach(Array(list.enumerated()), id: \.offset) { i, e in
                                if i > 0 { Divider().overlay(Theme.separator) }
                                NavigationLink(value: kind == 0 ? Route.rider(name: e.name) : Route.cyclingTeam(e.name)) {
                                    HStack(spacing: 12) {
                                        Text("\(e.rank)").font(.footnote.weight(.bold)).foregroundStyle(Theme.secondary).frame(width: 26)
                                        VStack(alignment: .leading, spacing: 1) {
                                            HStack(spacing: 5) {
                                                Text(e.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                                if let c = e.country { Text(c).font(.caption2).foregroundStyle(Theme.secondary) }
                                            }
                                            if let t = e.team, !t.isEmpty { Text(t).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1) }
                                        }
                                        Spacer()
                                        Text(e.value).font(.subheadline.weight(.bold)).monospacedDigit()
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
    }
}

/// Race logo from Wikipedia (English article, then German) on a light badge;
/// the flag / map icon when no logo exists.
struct RaceLogo: View {
    let race: WTRace
    var size: CGFloat = 30
    @State private var url: URL?

    var body: some View {
        Group {
            if let url {
                LogoView(url: url, fallback: race.name, size: size - 4)
                    .padding(2)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: race.isOneDay ? "flag.checkered" : "map")
                    .font(.system(size: size * 0.53))
                    .foregroundStyle(race.isGrandTour ? Color.yellow : Theme.secondary)
            }
        }
        .frame(width: size, height: size)
        .task(id: race.id) { url = await RaceLogos.logo(race) }
    }
}

enum RaceLogos {
    static func logo(_ race: WTRace) async -> URL? {
        if let gt = TourDef.all.first(where: { race.name.lowercased().contains($0.name.lowercased()) || race.name.lowercased().contains($0.wiki.lowercased()) }),
           race.isGrandTour {
            return LogoAssets.grandTour(gt.id)
        }
        return await WikiLogo.eventLogo(english: race.name, germanQueries: germanQueries(race.name))
    }

    /// German article searches: the race name, then the name with "Radrennen".
    static func germanQueries(_ name: String) -> [String] {
        let n = name.replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "/ ", with: "")
        return [n, "\(n) Radrennen"]
    }
}
