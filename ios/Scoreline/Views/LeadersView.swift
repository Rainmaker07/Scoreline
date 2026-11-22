import SwiftUI

/// Player face with a small team badge. Football photos come from Wikipedia
/// (ESPN has none); only used when the article is about a footballer.
struct PlayerPhoto: View {
    let headshot: URL?
    let name: String
    var isFootball = false
    let teamLogo: URL?
    let team: String
    var size: CGFloat = 40
    @State private var wikiImage: URL?
    @State private var looked = false

    var body: some View {
        let photo = headshot ?? wikiImage
        ZStack(alignment: .bottomTrailing) {
            if let photo {
                AsyncImage(url: photo) { $0.resizable().scaledToFill() } placeholder: { Theme.card2 }
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                if teamLogo != nil {
                    LogoView(url: teamLogo, fallback: team, size: size * 0.42)
                        .padding(2)
                        .background(Theme.card, in: Circle())
                        .offset(x: 4, y: 3)
                }
            } else {
                LogoView(url: teamLogo, fallback: team.isEmpty ? name : team, size: size)
            }
        }
        .frame(width: size, height: size)
        .task(id: name) {
            guard headshot == nil, isFootball, !looked else { return }
            looked = true
            if let s = await Wiki.summary(name), (s.description ?? "").lowercased().contains("footballer") {
                wikiImage = s.image
            }
        }
    }
}

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
            PlayerPhoto(headshot: l.headshot, name: l.name, isFootball: league.family == .soccer,
                        teamLogo: l.teamLogo, team: l.team ?? "")
            VStack(alignment: .leading, spacing: 1) {
                Text(l.name).font(.subheadline.weight(.bold)).lineLimit(1)
                Text([l.team, l.detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
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
