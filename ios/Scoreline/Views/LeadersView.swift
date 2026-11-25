import SwiftUI

/// Player face with a small team badge. Football photos come from FotMob
/// (ESPN has none), matched by name and club.
struct PlayerPhoto: View {
    let headshot: URL?
    let name: String
    var isFootball = false
    let teamLogo: URL?
    let team: String
    var size: CGFloat = 40
    @State private var lookedUp: (name: String, url: URL?)?

    var body: some View {
        // Only use a looked-up photo if it belongs to *this* player (rows get reused).
        let found = lookedUp?.name == name ? lookedUp?.url : nil
        let photo = lookedUp?.name == name ? found : headshot
        ZStack(alignment: .bottomTrailing) {
            if let photo {
                CachedImage(url: photo) { $0.resizable().scaledToFill() } placeholder: { Theme.card2 }
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
            guard lookedUp?.name != name else { return }
            // Also replaces headshots that don't load (ESPN lists some that 404).
            let url = await PlayerPhotos.best(primary: headshot, name: name, team: team, football: isFootball)
            lookedUp = (name, url)
        }
    }
}

struct LeadersSection: View {
    let league: League
    var refresh = 0
    var limit: Int? = nil
    @State private var category: String?
    /// MLB filters: league (0 MLB, 1 AL, 2 NL) and type (0 hitting, 1 pitching, 2 fielding).
    @AppStorage("mlbStatsLeague") private var mlbLeague = 0
    @AppStorage("mlbStatsType") private var mlbType = 0

    private var isMLB: Bool { league.id == "mlb" }
    private var mlbGroup: Int? { mlbLeague == 1 ? 7 : mlbLeague == 2 ? 8 : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isMLB {
                VStack(alignment: .leading, spacing: 8) {
                    TextTabs(items: [0, 1, 2], selection: $mlbLeague) { ["MLB", "AL", "NL"][$0] }
                    TextTabs(items: [0, 1, 2], selection: $mlbType) { ["Hitting", "Pitching", "Fielding"][$0] }
                }
            }
            leadersBody
        }
    }

    private var leadersBody: some View {
        Loader(id: "\(league.id)-leaders-\(refresh)" + (isMLB ? "-\(mlbLeague)-\(mlbType)" : ""),
               load: { () async throws -> [LeaderCategory] in
                   if league.provider == .bbl { return try await BBL.leaders() }
                   if league.family == .rugby { return try await RugbyStats.leaders(league) }
                   if isMLB {
                       if mlbType == 2 { return try await ESPN.mlbFielding(group: mlbGroup) }
                       let all = try await ESPN.leaders(league, group: mlbGroup)
                       return all.filter { ESPN.mlbPitchingCategories.contains($0.name) == (mlbType == 1) }
                   }
                   return try await ESPN.leaders(league)
               }) { cats in
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
                Text([l.position, l.team, l.detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
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
