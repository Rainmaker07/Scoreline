import SwiftUI

/// A team (or tennis player / rider) the user follows.
struct Favorite: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case team, tennisPlayer, rider }

    var kind: Kind = .team
    let leagueId: String
    let entityId: String
    var name: String
    var abbr: String
    var logo: URL?

    var id: String { "\(kind.rawValue):\(leagueId):\(entityId)" }
    var league: League? { League.byId(leagueId) }
}

/// User preferences persisted in UserDefaults: favourites, league order, hidden leagues.
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var favorites: [Favorite] { didSet { save(favorites, "favorites") } }
    @Published var leagueOrder: [String] { didSet { save(leagueOrder, "leagueOrder") } }
    @Published var hiddenLeagues: Set<String> { didSet { save(Array(hiddenLeagues), "hiddenLeagues") } }

    private init() {
        favorites = Self.load("favorites") ?? []
        let order: [String] = Self.load("leagueOrder") ?? League.all.map(\.id)
        // Add leagues introduced after the user saved an order.
        leagueOrder = order.filter { League.byId($0) != nil } + League.all.map(\.id).filter { !order.contains($0) }
        hiddenLeagues = Set(Self.load("hiddenLeagues") ?? [String]())
    }

    var visibleLeagues: [League] {
        leagueOrder.compactMap(League.byId).filter { !hiddenLeagues.contains($0.id) }
    }

    var orderedLeagues: [League] { leagueOrder.compactMap(League.byId) }

    // MARK: Favourites

    func isFavorite(league: String, id: String, kind: Favorite.Kind = .team) -> Bool {
        favorites.contains { $0.kind == kind && $0.leagueId == league && $0.entityId == id }
    }

    func toggle(_ f: Favorite) {
        if let i = favorites.firstIndex(where: { $0.id == f.id }) {
            favorites.remove(at: i)
        } else {
            favorites.append(f)
        }
    }

    func favoriteTeamIds(_ leagueId: String) -> Set<String> {
        Set(favorites.filter { $0.kind == .team && $0.leagueId == leagueId }.map(\.entityId))
    }

    func favoriteNames(kind: Favorite.Kind) -> Set<String> {
        Set(favorites.filter { $0.kind == kind }.map { $0.name.lowercased() })
    }

    // MARK: Persistence

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

/// Navigation destinations shared by every screen.
enum Route: Hashable {
    case team(leagueId: String, teamId: String)
    case player(leagueId: String, playerId: String)
    case tennisPlayer(id: String, name: String)
    case rider(name: String)
    case favorites
    case game(Game)
}
