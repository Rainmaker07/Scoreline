import Foundation

enum Family: String, CaseIterable {
    case basketball, baseball, soccer, rugby, tennis, cycling

    var title: String {
        switch self {
        case .basketball: return "Basketball"
        case .baseball: return "Baseball"
        case .soccer: return "Football"
        case .rugby: return "Rugby"
        case .tennis: return "Tennis"
        case .cycling: return "Cycling"
        }
    }

    var symbol: String {
        switch self {
        case .basketball: return "basketball.fill"
        case .baseball: return "baseball.fill"
        case .soccer: return "soccerball"
        case .rugby: return "football.fill"
        case .tennis: return "tennisball.fill"
        case .cycling: return "bicycle"
        }
    }
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
    /// Knockout cups have rounds instead of a table.
    var isCup: Bool { id == "dfb" || id == "fac" }
    /// UEFA league-phase competitions.
    var isUEFA: Bool { espn?.hasPrefix("soccer/uefa") == true }
    var hasStatLeaders: Bool { provider == .espn && family != .rugby }

    /// Short form for the header pill when the full name doesn't fit.
    var pillShort: String {
        switch id {
        case "epl": return "PL"
        case "ucl": return "UCL"
        case "uel": return "UEL"
        case "uecl": return "UECL"
        case "bl2": return "2. BL"
        case "bbl": return "BBL"
        case "prem": return "PREM"
        default: return short
        }
    }

    static let all: [League] = [
        League(id: "nba", name: "NBA", short: "NBA", family: .basketball, provider: .espn, espn: "basketball/nba",
               logo: URL(string: "https://a.espncdn.com/i/teamlogos/leagues/500/nba.png"), glyph: nil, color: "1d428a"),
        League(id: "mlb", name: "MLB", short: "MLB", family: .baseball, provider: .espn, espn: "baseball/mlb",
               logo: URL(string: "https://a.espncdn.com/i/teamlogos/leagues/500/mlb.png"), glyph: nil, color: "0a3161"),
        League(id: "bbl", name: "easyCredit BBL", short: "easyCredit BBL", family: .basketball, provider: .bbl, espn: nil,
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
        League(id: "uel", name: "Europa League", short: "Europa League", family: .soccer, provider: .espn, espn: "soccer/uefa.europa",
               logo: URL(string: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/2310.png"), glyph: nil, color: "a85b00"),
        League(id: "uecl", name: "Conference League", short: "Conference League", family: .soccer, provider: .espn, espn: "soccer/uefa.europa.conf",
               logo: URL(string: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/20296.png"), glyph: nil, color: "1f6b3a"),
        League(id: "dfb", name: "DFB-Pokal", short: "DFB-Pokal", family: .soccer, provider: .espn, espn: "soccer/ger.dfb_pokal",
               logo: URL(string: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/2061.png"), glyph: nil, color: "2d5a27"),
        League(id: "fac", name: "FA Cup", short: "FA Cup", family: .soccer, provider: .espn, espn: "soccer/eng.fa",
               logo: URL(string: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/40.png"), glyph: nil, color: "8a1538"),
        League(id: "prem", name: "Premiership Rugby", short: "Premiership", family: .rugby, provider: .espn, espn: "rugby/267979",
               // ESPN's only rugby logo is a near-black wordmark; use the Wikipedia crest instead.
               logo: WikiLogo.url(for: "Premiership Rugby"),
               glyph: "football.fill", color: "1d3c34"),
        League(id: "atp", name: "ATP World Tour", short: "ATP", family: .tennis, provider: .tennis, espn: "tennis/atp",
               logo: LogoAssets.atp, glyph: "tennis.racket", color: "1b4d3e"),
        League(id: "cycling", name: "UCI World Tour", short: "UCI World Tour", family: .cycling, provider: .cycling, espn: nil,
               logo: LogoAssets.uciWorldTour, glyph: "bicycle", color: "5a4a00"),
    ]

    static func byId(_ id: String) -> League? { all.first { $0.id == id } }
}
