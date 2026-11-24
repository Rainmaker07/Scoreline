import SwiftUI

// MARK: - Tennis home: tournaments + rankings

struct TennisView: View {
    var refresh = 0
    @State private var tab = UserDefaults.standard.integer(forKey: "shotTennisTab")

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $tab) {
                Text("Tournaments").tag(0)
                Text("Rankings").tag(1)
            }
            .pickerStyle(.segmented)
            if tab == 0 { TournamentList(refresh: refresh) } else { RankingsList(refresh: refresh) }
        }
    }
}

private struct TournamentList: View {
    var refresh = 0
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var tier: TennisTier?

    var body: some View {
        let thisYear = Calendar.current.component(.year, from: Date())
        VStack(alignment: .leading, spacing: 12) {
            ChipRow(items: [thisYear, thisYear - 1, thisYear - 2], selected: year, title: { String($0) }) { year = $0 }
            ChipScroll {
                    Chip(title: "All", selected: tier == nil) { tier = nil }
                    ForEach(TennisTier.allCases, id: \.self) { t in
                        Chip(title: t.label, selected: tier == t) { tier = t }
                    }
                }
            Loader(id: "season-\(year)-\(refresh)", load: { try await Tennis.season(year) }) { all in
                let list = all.filter { tier == nil || $0.tier == tier }
                let live = list.filter(\.isLive)
                VStack(alignment: .leading, spacing: 14) {
                    if !live.isEmpty {
                        SectionHeader(title: "This Week")
                        VStack(spacing: 0) {
                            ForEach(Array(live.enumerated()), id: \.element.id) { i, t in
                                if i > 0 { Divider().overlay(Theme.separator) }
                                TournamentRow(t: t)
                            }
                        }
                        .card(padding: 14)
                    }
                    let months = Dictionary(grouping: list) { Calendar.current.component(.month, from: $0.start) }
                    ForEach(months.keys.sorted(), id: \.self) { m in
                        let items = months[m] ?? []
                        VStack(alignment: .leading, spacing: 0) {
                            CardTitle(Calendar.current.monthSymbols[m - 1])
                            ForEach(Array(items.enumerated()), id: \.element.id) { i, t in
                                if i > 0 { Divider().overlay(Theme.separator) }
                                TournamentRow(t: t)
                            }
                        }
                        .card(padding: 14)
                    }
                    if list.isEmpty { MessageCard(text: "No tournaments found.") }
                }
            }
        }
    }
}

struct TierBadge: View {
    let tier: TennisTier
    var body: some View {
        if tier == .t500, let url = LogoAssets.atp500 {
            LogoView(url: url, fallback: "500", size: 22)
        } else {
            textBadge
        }
    }

    private var textBadge: some View {
        Text(tier.badge)
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(Color(hex: tier.color))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color(hex: tier.color).opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
    }
}

private struct TournamentRow: View {
    let t: TournamentSummary
    var body: some View {
        NavigationLink(value: Route.tournament(t)) {
            HStack(spacing: 12) {
                TournamentLogo(t: t, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(t.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        TierBadge(tier: t.tier)
                    }
                    Text(dates + (t.champion.map { " · 🏆 \($0)" } ?? ""))
                        .font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if t.isLive {
                    HStack(spacing: 4) { LivePulse(); Text("Live") }.font(.caption.weight(.bold)).foregroundStyle(Theme.live)
                }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.tertiary)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var dates: String {
        if t.tier == .team && t.wikiTitle != nil { return Fmt.month(t.start) }
        return Fmt.range(t.start, t.end)
    }
}

// MARK: - Rankings

private struct RankingsList: View {
    var refresh = 0
    @State private var limit = 50
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Loader(id: "rankings-\(refresh)", load: { try await Tennis.rankings() }) { ranks in
            let starred = store.favoriteNames(kind: .tennisPlayer)
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    CardTitle("ATP Rankings")
                    ForEach(Array(ranks.prefix(limit).enumerated()), id: \.element.id) { i, r in
                        if i > 0 { Divider().overlay(Theme.separator) }
                        NavigationLink(value: Route.tennisPlayer(id: r.playerId, name: r.name)) {
                            HStack(spacing: 10) {
                                Text("\(r.rank)").font(.subheadline.weight(.bold)).monospacedDigit().frame(width: 30, alignment: .leading)
                                Group {
                                    if r.movement > 0 { Text("▲\(r.movement)").foregroundStyle(Theme.win) }
                                    else if r.movement < 0 { Text("▼\(-r.movement)").foregroundStyle(Theme.live) }
                                    else { Text("–").foregroundStyle(Theme.tertiary) }
                                }
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 26, alignment: .leading)
                                CachedImage(url: r.headshot) { $0.resizable().scaledToFill() } placeholder: {
                                    Image(systemName: "person.fill").foregroundStyle(Theme.secondary)
                                }
                                .frame(width: 30, height: 30)
                                .background(Theme.card2)
                                .clipShape(Circle())
                                if let f = r.flag {
                                    CachedImage(url: f) { $0.resizable().scaledToFill() } placeholder: { Theme.card2 }
                                        .frame(width: 20, height: 14).clipShape(RoundedRectangle(cornerRadius: 2))
                                }
                                Text(r.name).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
                                if starred.contains(r.name.lowercased()) {
                                    Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.yellow)
                                }
                                Spacer()
                                Text(Int(r.points).formatted()).font(.subheadline).monospacedDigit().foregroundStyle(Theme.secondary)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .card(padding: 14)
                if ranks.count > limit {
                    Button("Show more") { limit += 100 }.font(.subheadline.weight(.semibold))
                }
            }
        }
    }
}

// MARK: - Tournament page

struct TournamentView: View {
    let t: TournamentSummary
    private let draw = "mens-singles"
    @State private var round: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let wiki = t.wikiTitle {
                    if wiki.contains("Laver") {
                        LaverCupView(year: Calendar.current.component(.year, from: t.start), finished: Date() > t.end)
                    } else if wiki.contains("Davis") {
                        DavisCupView(title: wiki, finished: Date() > t.end)
                    } else {
                        WikiEventView(title: wiki, finished: Date() > t.end)
                    }
                } else {
                    Loader(id: "\(t.id)-\(draw)",
                           poll: { (ev: TennisEvent?) in (ev?.matches.contains(where: { $0.state == .live }) ?? false) ? 30 : nil },
                           load: { try await Tennis.tournament(t, grouping: draw) }) { ev in
                        if let ev {
                            DrawBody(event: ev, summary: t, round: $round)
                        } else {
                            MessageCard(text: "\(t.name) hasn’t started yet.")
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(PageBackground(color: "1b4d3e"))
        .navigationTitle(t.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

private struct DrawBody: View {
    let event: TennisEvent
    let summary: TournamentSummary
    @Binding var round: String?

    var body: some View {
        let present = Set(event.matches.map(\.round))
        let rounds = ESPN.tennisRoundOrder.filter { present.contains($0) }
        let started = rounds.last { r in event.matches.contains { $0.round == r && $0.state != .pre } }
        let active = round.flatMap { rounds.contains($0) ? $0 : nil } ?? started ?? rounds.first
        let matches = event.matches.filter { $0.round == active }.sorted { ($0.state.sortRank, $0.date) < ($1.state.sortRank, $1.date) }
        let counts = Dictionary(grouping: event.matches, by: \.round).mapValues(\.count)

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                TournamentLogo(t: summary, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(Tennis.cleanName(event.name)).font(.title3.weight(.heavy)).lineLimit(2).minimumScaleFactor(0.8)
                        TierBadge(tier: summary.tier)
                    }
                    if let s = event.start, let e = event.end {
                        Text("\(Fmt.range(s, e))\(event.venue.map { " · \($0)" } ?? "")")
                            .font(.footnote).foregroundStyle(Theme.secondary)
                    }
                    if let c = event.champion {
                        HStack(spacing: 6) {
                            Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                            (Text("Champion: ") + Text(c).bold())
                        }
                        .font(.subheadline)
                        .padding(.top, 2)
                    }
                }
            }
            .card()

            if rounds.isEmpty {
                MessageCard(text: "The main draw hasn’t been published yet.")
            } else {
                ChipRow(items: rounds, selected: active, title: { ESPN.roundLabel($0, matchesInRound: counts[$0] ?? 0) }) { round = $0 }
                if active == "Group Stage" || active == "Round Robin" {
                    let groups = Tennis.groups(event.matches)
                    ForEach(Array(groups.enumerated()), id: \.offset) { i, rows in
                        GroupTable(title: "Group \(i == 0 ? "A" : i == 1 ? "B" : String(i + 1))", rows: rows)
                    }
                }
                ForEach(matches) { MatchCard(match: $0) }
            }
        }
    }
}

private struct GroupTable: View {
    let title: String
    let rows: [Tennis.GroupRow]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardTitle(title)
            HStack {
                Text("Player").frame(maxWidth: .infinity, alignment: .leading)
                Text("W-L").frame(width: 40)
                Text("Sets").frame(width: 44)
                Text("Games").frame(width: 50)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.secondary)
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                HStack {
                    HStack(spacing: 6) {
                        if let f = r.flag {
                            CachedImage(url: f) { $0.resizable().scaledToFill() } placeholder: { Theme.card2 }
                                .frame(width: 18, height: 12).clipShape(RoundedRectangle(cornerRadius: 2))
                        }
                        Text(r.name).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(r.wins)-\(r.losses)").fontWeight(.bold).frame(width: 40)
                    Text("\(r.setsWon)-\(r.setsLost)").frame(width: 44)
                    Text("\(r.gamesWon)-\(r.gamesLost)").frame(width: 50)
                }
                .font(.subheadline)
                .monospacedDigit()
                .padding(.vertical, 4)
                .overlay(alignment: .leading) {
                    if i < 2 { Rectangle().fill(Theme.win).frame(width: 3).offset(x: -10) }
                }
            }
            Text("Top two advance to the semifinals.").font(.caption2).foregroundStyle(Theme.tertiary)
        }
        .card()
    }
}

// MARK: - Team events from Wikipedia (Davis Cup, Laver Cup, NBA Cup)

struct WikiEventView: View {
    let title: String
    var finished = false

    var body: some View {
        Loader(id: "wiki-\(title)", load: { try await WikiEvents.sections(title, finished: finished) }) { sections in
            VStack(alignment: .leading, spacing: 14) {
                if sections.isEmpty {
                    MessageCard(text: "No results on Wikipedia for \(title) yet.")
                }
                ForEach(sections) { sec in
                    SectionHeader(title: sec.title)
                    ForEach(Array(sec.tables.enumerated()), id: \.offset) { _, t in WikiTableCard(table: t) }
                    if !sec.results.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            CardTitle("Results")
                            ForEach(Array(sec.results.enumerated()), id: \.offset) { i, r in
                                if i > 0 { Divider().overlay(Theme.separator) }
                                Text(r).font(.subheadline).padding(.vertical, 7)
                            }
                        }
                        .card()
                    }
                }
                Text("From Wikipedia (CC BY-SA). Updated by volunteers, usually within a day.")
                    .font(.caption2).foregroundStyle(Theme.tertiary)
            }
        }
    }
}

/// A Wikipedia table: first column wide, the rest compact; scrolls only if it must.
struct WikiTableCard: View {
    let table: WikiTable
    var body: some View {
        let header = table.rows.first ?? []
        let rows = Array(table.rows.dropFirst()).filter { $0 != header }
        VStack(alignment: .leading, spacing: 6) {
            if !table.caption.isEmpty { CardTitle(table.caption) }
            ViewThatFits(in: .horizontal) {
                grid(header, rows, compact: true)
                ScrollView(.horizontal, showsIndicators: false) { grid(header, rows, compact: false) }
            }
        }
        .card()
    }

    private func grid(_ header: [String], _ rows: [[String]], compact: Bool) -> some View {
        let nameCol = header.firstIndex { ["team", "player", "nation", "country", "team / player"].contains($0.lowercased()) } ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            row(header, nameCol: nameCol, isHeader: true, compact: compact)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                Divider().overlay(Theme.separator)
                row(r, nameCol: nameCol, isHeader: false, compact: compact)
            }
        }
    }

    private func row(_ cells: [String], nameCol: Int, isHeader: Bool, compact: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, c in
                if i == nameCol {
                    Text(c).lineLimit(2).minimumScaleFactor(0.8)
                        .frame(minWidth: compact ? 0 : 140, maxWidth: compact ? .infinity : 180, alignment: .leading)
                } else {
                    Text(c).lineLimit(1).minimumScaleFactor(0.7).frame(minWidth: 26, alignment: .trailing)
                }
            }
        }
        .font(isHeader ? .caption2.weight(.semibold) : .footnote)
        .foregroundStyle(isHeader ? Theme.secondary : .white)
        .monospacedDigit()
        .padding(.vertical, 6)
    }
}

private struct MatchCard: View {
    let match: TennisMatch

    var body: some View {
        let done = match.state == .post
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(match.court ?? "")
                Spacer()
                if match.state == .live {
                    HStack(spacing: 5) { LivePulse(); Text("Live") }.foregroundStyle(Theme.live)
                } else if done {
                    Text(Fmt.day(match.date))
                } else {
                    Text("\(Fmt.day(match.date)) · \(Fmt.time(match.date))")
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.secondary)
            ForEach(0..<2, id: \.self) { i in
                PlayerLine(p: match.players[i], other: match.players[1 - i], done: done)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct PlayerLine: View {
    let p: TennisPlayer
    let other: TennisPlayer
    let done: Bool
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let single = !p.id.contains("-") && !p.id.isEmpty && p.name != "TBD"
        if single {
            NavigationLink(value: Route.tennisPlayer(id: p.id, name: p.name)) { line }.buttonStyle(.plain)
        } else {
            line
        }
    }

    private var line: some View {
        let lost = done && p.winner != true
        let starred = store.favoriteNames(kind: .tennisPlayer).contains(p.name.lowercased())
        return HStack {
            HStack(spacing: 8) {
                if let f = p.flag {
                    CachedImage(url: f) { $0.resizable().scaledToFill() } placeholder: { Theme.card2 }
                        .frame(width: 20, height: 14)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
                if starred { Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.yellow) }
                Text(p.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                if let s = p.seed { Text("(\(s))").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary) }
                if done && p.winner == true { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Theme.win) }
            }
            .foregroundStyle(lost ? Theme.secondary : .white)
            Spacer()
            HStack(spacing: 14) {
                ForEach(Array(p.sets.enumerated()), id: \.offset) { i, s in
                    let lostSet = i < other.sets.count && s.games < other.sets[i].games
                    Text("\(s.games)")
                        .foregroundStyle(lostSet ? Theme.tertiary : .white)
                        .frame(width: 16)
                        .overlay(alignment: .topTrailing) {
                            if let tb = s.tiebreak {
                                Text("\(tb)").font(.system(size: 9)).foregroundStyle(Theme.secondary).offset(x: 8, y: -3)
                            }
                        }
                }
            }
            .font(.system(size: 17, weight: .bold))
            .monospacedDigit()
            .padding(.trailing, 8) // room for tie-break superscripts
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

struct SlamLogo: View {
    let slam: Slam
    var size: CGFloat = 40
    var body: some View {
        if let url = LogoAssets.slam(slam.id) {
            LogoView(url: url, fallback: slam.short, size: size)
        } else {
            Text(slam.short)
                .font(.system(size: size * 0.28, weight: .heavy))
                .frame(width: size, height: size)
                .background(Color(hex: slam.color), in: Circle())
        }
    }
}
