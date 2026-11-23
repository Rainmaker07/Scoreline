import Foundation

/// Competition logos, loaded at runtime from Wikimedia and cached on device.
/// They are never bundled with the app or committed to the repository.
enum LogoAssets {
    private static func u(_ s: String) -> URL? { URL(string: s) }

    static let nbaCup = u("https://upload.wikimedia.org/wikipedia/en/5/5f/NBA_Cup_logo.png")
    static let atp = u("https://upload.wikimedia.org/wikipedia/commons/thumb/3/3f/ATP_Tour_logo.svg/330px-ATP_Tour_logo.svg.png")
    static let uciWorldTour = u("https://upload.wikimedia.org/wikipedia/en/thumb/e/e8/UCI_World_Tour_logo.svg/330px-UCI_World_Tour_logo.svg.png")

    static let australianOpen = u("https://upload.wikimedia.org/wikipedia/commons/thumb/b/b4/Australian_Open_Logo_2017.svg/330px-Australian_Open_Logo_2017.svg.png")
    static let rolandGarros = u("https://upload.wikimedia.org/wikipedia/en/thumb/1/1d/Logo_Roland-Garros.svg/330px-Logo_Roland-Garros.svg.png")
    static let wimbledon = u("https://upload.wikimedia.org/wikipedia/en/thumb/b/b9/Wimbledon.svg/330px-Wimbledon.svg.png")
    static let usOpen = u("https://upload.wikimedia.org/wikipedia/commons/thumb/c/cd/Usopen-horizontal-logo.svg/330px-Usopen-horizontal-logo.svg.png")

    static let giro = u("https://upload.wikimedia.org/wikipedia/commons/thumb/b/b3/Giro_d%27Italia_-_Logo_2018.svg/330px-Giro_d%27Italia_-_Logo_2018.svg.png")
    static let tour = u("https://upload.wikimedia.org/wikipedia/commons/thumb/5/50/Tour_de_France_logo_%28black_background%29.svg/330px-Tour_de_France_logo_%28black_background%29.svg.png")
    static let vuelta = u("https://upload.wikimedia.org/wikipedia/commons/thumb/4/4b/La_Vuelta_%28Spain%29_logo.svg/330px-La_Vuelta_%28Spain%29_logo.svg.png")

    static let atp500 = u("https://upload.wikimedia.org/wikipedia/commons/b/b5/ATP_500_logo_%28as_of_2026%29.png")

    static func slam(_ id: String) -> URL? {
        switch id {
        case "ao": return australianOpen
        case "rg": return rolandGarros
        case "wim": return wimbledon
        case "uso": return usOpen
        default: return nil
        }
    }

    static func grandTour(_ id: String) -> URL? {
        switch id {
        case "giro": return giro
        case "tour": return tour
        case "vuelta": return vuelta
        default: return nil
        }
    }
}
