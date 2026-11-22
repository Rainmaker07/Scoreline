import SwiftUI

struct TeamColumn: View {
    let side: Side
    var logoSize: CGFloat = 40
    var showRecord = false

    var body: some View {
        VStack(spacing: 5) {
            LogoView(url: side.logo, fallback: side.abbr.isEmpty ? side.short : side.abbr, size: logoSize)
            Text(side.short)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if showRecord, let r = side.record, !r.isEmpty {
                Text(r).font(.caption).foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct StatusLine: View {
    let state: GameState
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            if state == .live { LivePulse() }
            Text(text)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(state == .live ? Theme.live : .white)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// One score, never wrapping or truncating: three-digit scores start smaller,
/// and anything that still doesn't fit shrinks instead of showing "1…".
struct ScoreText: View {
    let text: String
    let dim: Bool
    var size: CGFloat = 44

    var body: some View {
        let fitted = text.count >= 3 ? size * 0.8 : size
        Text(text)
            .font(.score(fitted))
            .monospacedDigit()
            .foregroundStyle(dim ? Theme.secondary.opacity(0.75) : .white)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .allowsTightening(true)
    }
}

/// A team's record in place of the score before kick-off.
struct RecordText: View {
    let text: String?
    var body: some View {
        Text(text ?? "")
            .font(.subheadline)
            .foregroundStyle(Theme.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

/// Apple Sports-style game row: logo/name, score, status, score, logo/name.
struct GameRow: View {
    let game: Game
    var big = false
    var favorite = false

    var body: some View {
        let l = game.ordered.left
        let r = game.ordered.right
        let ln = Double(l.score ?? "") ?? 0
        let rn = Double(r.score ?? "") ?? 0
        let size: CGFloat = big ? 56 : 44
        // iPhone 13: ~330pt per row = 2×72 (teams) + 64 (status) + 2×~55 (scores).
        HStack(spacing: 4) {
            TeamColumn(side: l, logoSize: big ? 64 : 40)
                .frame(width: big ? 88 : 72)
            Group {
                if game.state == .pre {
                    RecordText(text: l.record)
                } else {
                    ScoreText(text: l.score ?? "-", dim: game.state == .post && ln < rn, size: size)
                }
            }
            .frame(maxWidth: .infinity)
            .layoutPriority(1)
            VStack(spacing: 3) {
                if game.state == .pre {
                    Text(game.statusText.contains("Postponed") ? "PPD" : Fmt.time(game.date))
                        .font(.headline.weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if !Calendar.current.isDateInToday(game.date) {
                        Text(Fmt.day(game.date)).font(.caption).foregroundStyle(Theme.secondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                } else {
                    StatusLine(state: game.state, text: game.statusText)
                }
            }
            .frame(width: 64)
            Group {
                if game.state == .pre {
                    RecordText(text: r.record)
                } else {
                    ScoreText(text: r.score ?? "-", dim: game.state == .post && rn < ln, size: size)
                }
            }
            .frame(maxWidth: .infinity)
            .layoutPriority(1)
            TeamColumn(side: r, logoSize: big ? 64 : 40)
                .frame(width: big ? 88 : 72)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .topLeading) {
            if favorite {
                Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow).padding(.top, 6)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Football scorers under a row.
struct ScorersLine: View {
    let game: Game
    var body: some View {
        let l = game.ordered.left
        let r = game.ordered.right
        let ls = game.scorers.filter { $0.teamId == l.id }
        let rs = game.scorers.filter { $0.teamId == r.id }
        if game.league.family == .soccer, !(ls.isEmpty && rs.isEmpty) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) { ForEach(ls, id: \.self) { Text("⚽ \($0.text)") } }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) { ForEach(rs, id: \.self) { Text("\($0.text) ⚽") } }
            }
            .font(.caption)
            .foregroundStyle(Theme.secondary)
            .padding(.bottom, 10)
        }
    }
}

/// A list of games inside one card, separated by hairlines.
struct GameList: View {
    let games: [Game]
    @Binding var openGame: Game?
    var showDayHeaders = false
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let cal = Calendar.current
        VStack(spacing: 0) {
            ForEach(Array(sortedGames.enumerated()), id: \.element.id) { i, g in
                let newDay = i == 0 || !cal.isDate(g.date, inSameDayAs: sortedGames[i - 1].date)
                if showDayHeaders && newDay {
                    Text(g.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, i == 0 ? 0 : 14)
                } else if i > 0 {
                    Divider().overlay(Theme.separator)
                }
                Button { openGame = g } label: {
                    VStack(spacing: 0) {
                        GameRow(game: g, favorite: isFavorite(g))
                        ScorersLine(game: g)
                        if let note = g.note, !note.isEmpty,
                           g.league.family != .soccer || g.state != .post || note.contains("Penalties") {
                            Text(note).font(.caption).foregroundStyle(Theme.secondary).padding(.bottom, 10)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sortedGames: [Game] {
        let favs = Set(store.favorites.filter { $0.kind == .team }.map { "\($0.leagueId):\($0.entityId)" })
        func fav(_ g: Game) -> Bool { favs.contains("\(g.leagueId):\(g.home.id)") || favs.contains("\(g.leagueId):\(g.away.id)") }
        if showDayHeaders { return games.sorted { $0.date < $1.date } }
        return games.sorted {
            if fav($0) != fav($1) { return fav($0) }
            return ($0.state.sortRank, $0.date) < ($1.state.sortRank, $1.date)
        }
    }

    private func isFavorite(_ g: Game) -> Bool {
        store.isFavorite(league: g.leagueId, id: g.home.id) || store.isFavorite(league: g.leagueId, id: g.away.id)
    }
}

enum ScoreTab: String, CaseIterable {
    case yesterday = "Yesterday", today = "Today", upcoming = "Upcoming"
}

/// Loads games for a league: one day, or the next 10 days.
enum GameFeed {
    static func load(_ league: League, tab: ScoreTab) async throws -> [Game] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        switch league.provider {
        case .bbl:
            let all = try await BBL.games()
            switch tab {
            case .yesterday:
                let y = cal.date(byAdding: .day, value: -1, to: today)!
                let recent = all.filter { cal.isDate($0.date, inSameDayAs: y) }
                // The BBL plays mostly at weekends: fall back to the last finished round.
                return recent.isEmpty ? all.filter { $0.state == .post && $0.date < today } : recent
            case .today:
                return all.filter { cal.isDateInToday($0.date) }
            case .upcoming:
                return all.filter { $0.date >= cal.date(byAdding: .day, value: 1, to: today)! }
            }
        default:
            // ESPN groups games by US date; we group by the local calendar day, so
            // fetch the neighbouring ESPN day too and filter by local date.
            func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: today)! }
            switch tab {
            case .yesterday:
                return try await days(league, [day(-2), day(-1)]).filter { cal.isDate($0.date, inSameDayAs: day(-1)) }
            case .today:
                return try await days(league, [day(-1), day(0)]).filter { cal.isDateInToday($0.date) }
            case .upcoming:
                return try await days(league, (0...7).map(day)).filter { $0.date >= day(1) }
            }
        }
    }

    /// Single-day requests in parallel (ESPN refuses date ranges for team sports).
    static func days(_ league: League, _ dates: [Date]) async throws -> [Game] {
        try await withThrowingTaskGroup(of: [Game].self) { group in
            for d in dates { group.addTask { try await ESPN.scoreboard(league, date: d) } }
            var all: [Game] = []
            var seen = Set<String>()
            for try await games in group {
                for g in games where seen.insert(g.id).inserted { all.append(g) }
            }
            return all.sorted { $0.date < $1.date }
        }
    }
}

/// Yesterday / Today / Upcoming card, like Apple Sports.
struct ScoresCard: View {
    let league: League
    var refresh = 0
    @Binding var openGame: Game?
    @State private var tab: ScoreTab = .today

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ForEach(ScoreTab.allCases, id: \.self) { t in
                    Button { withAnimation(.snappy) { tab = t } } label: {
                        Text(t.rawValue)
                            .font(.headline)
                            .foregroundStyle(t == tab ? .white : Theme.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 16)
            Divider().overlay(Theme.separator)
            Loader(id: "\(league.id)-\(tab.rawValue)-\(refresh)",
                   poll: { (games: [Game]) in games.contains(where: { $0.state == .live }) ? 20 : 180 },
                   load: { try await GameFeed.load(league, tab: tab) }) { games in
                if games.isEmpty {
                    Text(emptyText)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                } else {
                    GameList(games: games, openGame: $openGame, showDayHeaders: tab == .upcoming)
                }
            }
        }
        .padding(.horizontal, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var emptyText: String {
        switch tab {
        case .yesterday: return "No games yesterday."
        case .today: return "No games today."
        case .upcoming: return "No games in the next 7 days."
        }
    }
}
