import Foundation

/// Launch options that open a specific screen, used by the GitHub build to
/// take simulator screenshots. Passed as launch arguments, e.g.
/// `-selectedLeague nba -shotRoute team:nba:13`. They are read from the
/// argument domain only and never stored, so a normal launch is unaffected.
///
/// - `-shotRoute`: `team:<league>:<id>`, `player:<league>:<id>`, `game:<league>`
///   (latest finished game), `nbaCup`, `favorites`, `rider:<name>`,
///   `cyclingTeam:<name>`, `tournament:<name contains>`, `race:<name contains>`
/// - `-shotGameTab Lineups`, `-shotTennisTab 1`, `-shotMenu YES`, `-shotSettings YES`
/// - `-runDataChecks YES`: run DataChecks, write Documents/data-checks.json, quit.
enum ScreenshotMode {
    static func route(_ spec: String) async -> Route? {
        let parts = spec.split(separator: ":", maxSplits: 2).map(String.init)
        guard let kind = parts.first else { return nil }
        let arg1 = parts.count > 1 ? parts[1] : ""
        let arg2 = parts.count > 2 ? parts[2] : ""
        switch kind {
        case "team": return .team(leagueId: arg1, teamId: arg2)
        case "player": return .player(leagueId: arg1, playerId: arg2)
        case "nbaCup": return .nbaCup
        case "favorites": return .favorites
        case "rider": return .rider(name: arg1)
        case "cyclingTeam": return .cyclingTeam(arg1)
        case "game":
            guard let league = League.byId(arg1) else { return nil }
            let today = Calendar.current.startOfDay(for: Date())
            let days = (0...9).map { Calendar.current.date(byAdding: .day, value: -$0, to: today)! }
            let games = league.provider == .bbl ? ((try? await BBL.games()) ?? []) : ((try? await GameFeed.days(league, days)) ?? [])
            return games.last { $0.state == .post }.map { .game($0) }
        case "tournament":
            let year = Calendar.current.component(.year, from: Date())
            let season = (try? await Tennis.season(year)) ?? []
            return season.first { $0.name.localizedCaseInsensitiveContains(arg1) }.map { .tournament($0) }
        case "race":
            let year = Calendar.current.component(.year, from: Date())
            let races = (try? await WorldTour.calendar(year)) ?? []
            return races.first { $0.name.localizedCaseInsensitiveContains(arg1) }.map { .cyclingRace($0) }
        default: return nil
        }
    }
}
