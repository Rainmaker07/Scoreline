import Foundation

enum Family: String {
    case basketball, baseball, soccer, tennis, cycling
}

/// Where a league's data comes from.
enum Provider: String {
    case espn, bbl, tennis, cycling
}

struct League: Identifiable, Hashable {
    let id: String
    let name: String
    let short: String
    let family: Family
    let provider: Provider
    /// ESPN path segment, e.g. "basketball/nba"
    let espn: String?
    let logo: URL?
    /// SF Symbol used when there is no logo
    let glyph: String?
    /// Page background tint (hex)
    let color: String

    var isTeamSport: Bool { family != .tennis && family != .cycling }
    var hasStatLeaders: Bool { provider == .espn }

    static let all: [League] = [
        League(id: "nba", name: "NBA", short: "NBA", family: .basketball, provider: .espn, espn: "basketball/nba",
               logo: URL(string: "https://a.espncdn.com/i/teamlogos/leagues/500/nba.png"), glyph: nil, color: "1d428a"),
        League(id: "mlb", name: "MLB", short: "MLB", family: .baseball, provider: .espn, espn: "baseball/mlb",
               logo: URL(string: "https://a.espncdn.com/i/teamlogos/leagues/500/mlb.png"), glyph: nil, color: "0a3161"),
        League(id: "bbl", name: "Basketball Bundesliga", short: "BBL", family: .basketball, provider: .bbl, espn: nil,
               logo: URL(string: "https://upload.wikimedia.org/wikipedia/en/1/17/EasyCredit_BBL_logo.png"),
               glyph: "basketball.fill", color: "e2001a"),
        League(id: "epl", name: "Premier League", short: "Premier League", family: .soccer, provider: .espn, espn: "soccer/eng.1",
               logo: URL(string: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/23.png"), glyph: nil, color: "3d195b"),
        League(id: "bl1", name: "Bundesliga", short: "Bundesliga", family: .soccer, provider: .espn, espn: "soccer/ger.1",
               logo: URL(string: "https://a.espncdn.com/i/leaguelogos/soccer/500/10.png"), glyph: nil, color: "a3000f"),
        League(id: "bl2", name: "2. Bundesliga", short: "2. Bundesliga", family: .soccer, provider: .espn, espn: "soccer/ger.2",
               logo: URL(string: "https://a.espncdn.com/i/leaguelogos/soccer/500/97.png"), glyph: nil, color: "7a1f1f"),
        League(id: "ucl", name: "Champions League", short: "Champions League", family: .soccer, provider: .espn, espn: "soccer/uefa.champions",
               logo: URL(string: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/2.png"), glyph: nil, color: "0b1f66"),
        League(id: "atp", name: "Men's Tennis", short: "ATP", family: .tennis, provider: .tennis, espn: "tennis/atp",
               logo: LogoAssets.atp, glyph: "tennis.racket", color: "1b4d3e"),
        League(id: "cycling", name: "Grand Tours", short: "Cycling", family: .cycling, provider: .cycling, espn: nil,
               logo: LogoAssets.uciWorldTour, glyph: "bicycle", color: "5a4a00"),
    ]

    static func byId(_ id: String) -> League? { all.first { $0.id == id } }
}
