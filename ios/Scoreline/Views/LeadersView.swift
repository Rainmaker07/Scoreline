import SwiftUI

struct LeadersSection: View {
    let league: League
    var refresh = 0
    var limit: Int? = nil
    @State private var category: String?

    var body: some View {
        Loader(id: "\(league.id)-leaders-\(refresh)", load: { try await ESPN.leaders(league) }) { cats in
            if cats.isEmpty {
                MessageCard(text: "No stat leaders available yet this season.")
            } else {
                let current = cats.first { $0.name == category } ?? cats[0]
                let leaders = limit.map { Array(current.leaders.prefix($0)) } ?? current.leaders
                VStack(alignment: .leading, spacing: 12) {
                    ChipRow(items: cats.map(\.name), selected: current.name,
                            title: { n in cats.first { $0.name == n }?.label ?? n },
                            onSelect: { category = $0 })
                    VStack(alignment: .leading, spacing: 0) {
                        CardTitle(current.label)
                        ForEach(Array(leaders.enumerated()), id: \.offset) { i, l in
                            if i > 0 { Divider().overlay(Theme.separator) }
                            leaderRow(i, l)
                        }
                    }
                    .card()
                }
            }
        }
    }

    @ViewBuilder private func leaderRow(_ i: Int, _ l: LeaderEntry) -> some View {
        let content = HStack(spacing: 12) {
            Text("\(i + 1)").font(.footnote.weight(.bold)).foregroundStyle(Theme.secondary).frame(width: 20)
            if let h = l.headshot {
                AsyncImage(url: h) { $0.resizable().scaledToFill() } placeholder: { Theme.card2 }
                    .frame(width: 38, height: 38).clipShape(Circle())
            } else {
                LogoView(url: l.teamLogo, fallback: l.team ?? "", size: 38)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(l.name).font(.subheadline.weight(.bold)).lineLimit(1)
                Text([l.team, l.detail].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            // Same size for every row, including the leader.
            Text(l.value)
                .font(.system(size: 20, weight: .heavy))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())

        if let id = l.athleteId {
            NavigationLink(value: Route.player(leagueId: league.id, playerId: id)) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}
