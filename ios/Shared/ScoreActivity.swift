import ActivityKit
import Foundation

/// A live game on the Lock Screen / Dynamic Island. Shared by the app and the
/// widget extension. Designed so a future push server can send the same
/// ContentState over APNs (ActivityKit push updates) without changes.
struct ScoreActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var homeScore: String
        var awayScore: String
        /// Short status: "67'", "Q3 4:12", "HT", "Final"
        var status: String
        /// "pre", "in" or "post"
        var state: String
        /// Latest event, e.g. "⚽ Kane 67'"
        var lastEvent: String?
    }

    let gameId: String
    let leagueId: String
    let leagueName: String
    let homeName: String
    let homeAbbr: String
    let homeColor: String
    let awayName: String
    let awayAbbr: String
    let awayColor: String
    let start: Date
    /// Football lists the home team first, US sports the away team.
    let homeFirst: Bool
}
