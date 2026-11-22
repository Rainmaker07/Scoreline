import SwiftUI

private let roundShort: [String: String] = [
    "Round 1": "R128", "Round 2": "R64", "Round 3": "R32", "Round 4": "R16",
    "Quarterfinal": "QF", "Semifinal": "SF", "Final": "Final",
]
private let doublesShort: [String: String] = ["Round 1": "R64", "Round 2": "R32", "Round 3": "R16"]

struct TennisView: View {
    var refresh = 0
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var slam = Slam.current()
    @State private var draw = "mens-singles"
    @State private var round: String?

    var body: some View {
        let thisYear = Calendar.current.component(.year, from: Date())
        VStack(alignment: .leading, spacing: 12) {
            ChipRow(items: [thisYear, thisYear - 1, thisYear - 2], selected: year, title: { String($0) }) {
                year = $0
                round = nil
            }
            HStack(spacing: 8) {
                ForEach(Slam.all) { s in
                    Button {
                        slam = s
                        round = nil
                    } label: {
                        VStack(spacing: 6) {
                            SlamLogo(slam: s, size: 40)
                            Text(s.short == "WIM" ? "Wimbledon" : s.short == "USO" ? "US Open" : s.short == "AO" ? "Aus Open" : "Roland-Garros")
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text(s.surface).font(.caption2).foregroundStyle(Theme.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 96)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 4)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(s == slam ? Color.white : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            Picker("", selection: $draw) {
                Text("Men's Singles").tag("mens-singles")
                Text("Men's Doubles").tag("mens-doubles")
            }
            .pickerStyle(.segmented)
            .onChange(of: draw) { round = nil }

            Loader(id: "\(slam.id)-\(year)-\(draw)-\(refresh)",
                   poll: { (ev: TennisEvent?) in (ev?.matches.contains(where: { $0.state == .live }) ?? false) ? 30 : nil },
                   load: { try await ESPN.slam(slam, year: year, grouping: draw) }) { ev in
                if let ev {
                    SlamBody(event: ev, slam: slam, draw: draw, round: $round)
                } else {
                    MessageCard(text: "\(slam.name) \(year) hasn’t started yet. Check back during the tournament.")
                }
            }
        }
    }
}

private struct SlamBody: View {
    let event: TennisEvent
    let slam: Slam
    let draw: String
    @Binding var round: String?

    var body: some View {
        let present = Set(event.matches.map(\.round))
        let rounds = ESPN.roundOrder.filter { present.contains($0) }
        let started = rounds.last { r in event.matches.contains { $0.round == r && $0.state != .pre } }
        let active = round.flatMap { rounds.contains($0) ? $0 : nil } ?? started ?? rounds.first
        let matches = event.matches.filter { $0.round == active }.sorted { ($0.state.sortRank, $0.date) < ($1.state.sortRank, $1.date) }

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                SlamLogo(slam: slam, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.name).font(.title3.weight(.heavy))
                    if let s = event.start, let e = event.end {
                        Text("\(Fmt.day(s)) – \(Fmt.day(e))\(event.venue.map { " · \($0)" } ?? "")")
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
            .background(
                LinearGradient(colors: [Color(hex: slam.color).opacity(0.35), .clear], startPoint: .topLeading, endPoint: .center)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            )

            if rounds.isEmpty {
                MessageCard(text: "The main draw hasn’t been published yet.")
            } else {
                ChipRow(items: rounds, selected: active, title: { r in (draw == "mens-doubles" ? doublesShort[r] : nil) ?? roundShort[r] ?? r }) {
                    round = $0
                }
                ForEach(matches) { MatchCard(match: $0) }
            }
        }
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
                    AsyncImage(url: f) { $0.resizable().scaledToFill() } placeholder: { Theme.card2 }
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
            HStack(spacing: 12) {
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
