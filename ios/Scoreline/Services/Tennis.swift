import Foundation
import SwiftUI

// MARK: - Tournament tiers

enum TennisTier: String, CaseIterable, Hashable {
    case slam = "Grand Slam", masters = "1000", t500 = "500", t250 = "250", finals = "Finals", team = "Team"

    var label: String {
        switch self {
        case .slam: return "Grand Slams"
        case .masters: return "Masters 1000"
        case .t500: return "ATP 500"
        case .t250: return "ATP 250"
        case .finals: return "Finals"
        case .team: return "Team events"
        }
    }

    var badge: String {
        switch self {
        case .slam: return "GS"
        case .masters: return "1000"
        case .t500: return "500"
        case .t250: return "250"
        case .finals: return "FINALS"
        case .team: return "TEAM"
        }
    }

    var color: String {
        switch self {
        case .slam: return "d4af37"
        case .masters: return "5e5ce6"
        case .t500: return "0a84ff"
        case .t250: return "30d158"
        case .finals: return "ff9f0a"
        case .team: return "ff375f"
        }
    }

    /// ESPN doesn't label tiers: match on the tournament name.
    static func of(name: String, major: Bool) -> TennisTier {
        if major { return .slam }
        let n = name.lowercased()
        if n.contains("atp finals") || n.contains("next gen") { return .finals }
        let masters = ["bnp paribas open", "miami open", "monte-carlo", "madrid open", "internazionali bnl",
                       "national bank open", "omnium banque nationale", "canadian open", "cincinnati",
                       "shanghai masters", "paris masters"]
        if masters.contains(where: n.contains) { return .masters }
        let five = ["abn amro", "rio open", "dallas open", "qatar", "dubai", "abierto mexicano", "barcelona open",
                    "bmw open", "hamburg open", "terra wortmann", "hsbc championships", "queen's", "cinch championships",
                    "citi dc open", "citi open", "china open", "japan open", "swiss indoors", "erste bank open"]
        if five.contains(where: n.contains) { return .t500 }
        return .t250
    }
}

// MARK: - Tournament logos

enum TournamentLogos {
    /// ESPN's sponsor names -> Wikipedia article (whose lead image is the logo).
    private static let titles: [(String, String)] = [
        ("bnp paribas open", "Indian Wells Open"), ("miami open", "Miami Open"), ("monte-carlo", "Monte-Carlo Masters"),
        ("madrid open", "Madrid Open"), ("internazionali", "Italian Open (tennis)"), ("banque nationale", "Canadian Open (tennis)"),
        ("national bank open", "Canadian Open (tennis)"), ("cincinnati", "Cincinnati Open"), ("shanghai", "Shanghai Masters (tennis)"),
        ("paris masters", "Paris Masters"), ("next gen", "Next Generation ATP Finals"), ("atp finals", "ATP Finals"),
        ("abn amro", "Rotterdam Open"), ("rio open", "Rio Open"), ("dallas open", "Dallas Open"),
        ("dubai", "Dubai Tennis Championships"), ("qatar", "Qatar Open (tennis)"), ("abierto mexicano", "Mexican Open (tennis)"),
        ("barcelona open", "Barcelona Open (tennis)"), ("bmw open", "Bavarian International Tennis Championships"),
        ("hamburg open", "Hamburg European Open"), ("terra wortmann", "Halle Open"), ("hsbc championships", "Queen's Club Championships"),
        ("citi dc open", "Washington Open (tennis)"), ("china open", "China Open (tennis)"), ("japan open", "Japan Open (tennis)"),
        ("swiss indoors", "Swiss Indoors"), ("erste bank", "Vienna Open"), ("brisbane", "Brisbane International"),
        ("asb classic", "ASB Classic"), ("hong kong", "Hong Kong Open (tennis)"), ("adelaide", "Adelaide International (tennis)"),
        ("occitanie", "Open Sud de France"), ("argentina open", "Argentina Open"), ("delray beach", "Delray Beach Open"),
        ("chile open", "Chile Open (tennis)"), ("clay court", "U.S. Men's Clay Court Championships"),
        ("hassan ii", "Grand Prix Hassan II"), ("tiriac", "Romanian Open"), ("geneva open", "Geneva Open"),
        ("boss open", "Stuttgart Open"), ("libéma", "Rosmalen Grass Court Championships"), ("eastbourne", "Eastbourne International"),
        ("mallorca", "Mallorca Championships"), ("nordea", "Swedish Open"), ("gstaad", "Swiss Open Gstaad"),
        ("umag", "Croatia Open"), ("generali open", "Austrian Open Kitzbühel"), ("estoril", "Estoril Open"),
        ("mifel", "Los Cabos Open"), ("winston-salem", "Winston-Salem Open"), ("chengdu", "Chengdu Open"),
        ("hangzhou", "Hangzhou Open"), ("european open", "European Open (tennis)"), ("almaty", "Almaty Open"),
        ("auvergne", "Lyon Open (tennis)"), ("stockholm", "Stockholm Open"), ("davis cup", "Davis Cup"), ("laver cup", "Laver Cup"),
    ]

    static func wikiTitle(_ name: String) -> String {
        let n = name.lowercased()
        return titles.first { n.contains($0.0) }?.1 ?? name
    }

    private static var cache: [String: URL?] = [:]

    static func articleTitle(_ t: TournamentSummary) -> String { wikiTitle(t.name) }

    /// German Wikipedia searches: the article names events "ATP <city>".
    static func germanQueries(_ t: TournamentSummary) -> [String] {
        let plain = wikiTitle(t.name).replacingOccurrences(of: #"\s*\(.*\)$"#, with: "", options: .regularExpression)
        let generic: Set<String> = ["open", "international", "championships", "masters", "classic", "grand", "prix", "tennis", "the", "u.s.", "men's", "court", "clay", "grass", "indoors"]
        let place = plain.split(separator: " ").map(String.init).first { !generic.contains($0.lowercased()) } ?? plain
        return ["ATP \(place)", "\(plain) Tennisturnier"]
    }

    static func logo(_ t: TournamentSummary) async -> URL? {
        if t.tier == .slam, let slam = Slam.all.first(where: { t.name.lowercased().contains($0.name.split(separator: " ").first!.lowercased()) }) {
            return LogoAssets.slam(slam.id)
        }
        let title = wikiTitle(t.name)
        if let hit = cache[title] { return hit }
        // Logos the infobox lookup can't find (named oddly on Wikipedia).
        let files: [(String, String)] = [("abn amro", "de:ABN_Amro_World_Tennis_Tournament.jpg")]
        if let f = files.first(where: { t.name.lowercased().contains($0.0) }) {
            let parts = f.1.split(separator: ":", maxSplits: 1)
            let url = URL(string: "https://\(parts[0]).wikipedia.org/wiki/Special:FilePath/\(parts[1])?width=300")
            cache[title] = url
            return url
        }
        // Only infobox logos (the lead image is often a photo of the venue); English article
        // first, then the German one ("ATP Brisbane" etc.), which has logos for most events.
        let url = await WikiLogo.eventLogo(english: title, germanQueries: germanQueries(t))
        cache[title] = url
        return url
    }

    /// First image in an article whose file name contains "logo" (the infobox logo).
    static func firstLogo(in html: String) -> URL? {
        guard let r = html.range(of: #"//(?:upload|thumb)\.wikimedia\.org/[^"\s]*[Ll]ogo[^"\s]*\.(png|svg\.png|jpg)"#, options: .regularExpression) else { return nil }
        return URL(string: "https:" + html[r])
    }
}

/// Tournament logo, loaded from the tournament's Wikipedia article.
struct TournamentLogo: View {
    let t: TournamentSummary
    private var initials: String {
        let words = t.name.split(separator: " ").filter { $0.first?.isUppercase == true }
        return String(words.prefix(3).compactMap(\.first))
    }
    var size: CGFloat = 34
    @State private var url: URL?
    @State private var loaded = false

    var body: some View {
        ZStack {
            if let url {
                LogoView(url: url, fallback: t.name, size: size)
                    .padding(3)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                // No logo found: a consistent initials badge in the tier colour.
                Text(initials)
                    .font(.system(size: size * 0.3, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: size + 6, height: size + 6)
                    .background(Color(hex: t.tier.color).opacity(0.85), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
        .frame(width: size + 6, height: size + 6)
        .opacity(loaded ? 1 : 0.4)
        .task(id: t.id) {
            url = await TournamentLogos.logo(t)
            loaded = true
        }
    }
}

// MARK: - Season index

struct TournamentSummary: Identifiable, Hashable {
    let id: String
    let name: String
    let start: Date
    let end: Date
    let tier: TennisTier
    let venue: String?
    let champion: String?
    /// Wikipedia article for team events that ESPN doesn't cover.
    var wikiTitle: String? = nil

    var isLive: Bool { Date() >= start && Date() <= end }
}

struct RankingEntry: Identifiable, Hashable {
    var id: String { playerId }
    let rank: Int
    let previous: Int?
    let points: Double
    let playerId: String
    let name: String
    let flag: URL?
    let country: String?
    let headshot: URL?

    var movement: Int { (previous ?? rank) - rank }
}

enum Tennis {
    private static var indexCache: [Int: (date: Date, list: [TournamentSummary])] = [:]

    /// Every ATP tournament in a season (singles champion when finished).
    /// The source is large (~20 MB), so it's cached and parsed off the main thread.
    static func season(_ year: Int) async throws -> [TournamentSummary] {
        if let c = indexCache[year], Date().timeIntervalSince(c.date) < 3600 { return c.list }
        guard let url = URL(string: "\(ESPN.site)/tennis/atp/scoreboard?dates=\(year)") else { return [] }
        let past = year < Calendar.current.component(.year, from: Date())
        let data = try await HTTP.shared.data(url, maxAge: past ? 86_400 * 60 : 43_200, permanent: past)
        let list = try await Task.detached(priority: .userInitiated) { () throws -> [TournamentSummary] in
            let d = try J(data: data)
            var out: [TournamentSummary] = d["events"].array.compactMap { e in
                guard let eventStart = ESPNDate.parse(e["date"].string) else { return nil }
                let name = e["name"].str
                // Champion = winner of the men's singles final.
                let singles = e["groupings"].array.first { $0["grouping"]["slug"].str == "mens-singles" }
                // ESPN's event dates include qualifying: use the first and last main-draw singles match.
                let matchDays = (singles?["competitions"].array ?? [])
                    .filter { !$0["round"]["displayName"].str.lowercased().contains("qualif") }
                    .compactMap { ESPNDate.parse($0["date"].string) }
                let start = matchDays.min().map { Calendar.current.startOfDay(for: $0) } ?? eventStart
                let end = matchDays.max() ?? ESPNDate.parse(e["endDate"].string) ?? eventStart
                let final = singles?["competitions"].array.first { $0["round"]["displayName"].str == "Final" && $0["status"]["type"]["state"].str == "post" }
                let champ = final?["competitors"].array.first { $0["winner"].bool == true }?["athlete"]["displayName"].string
                if singles == nil && !name.lowercased().contains("next gen") && e["groupings"].array.isEmpty { return nil }
                return TournamentSummary(
                    id: e["id"].str, name: Tennis.cleanName(name), start: start, end: end,
                    tier: TennisTier.of(name: name, major: e["major"].bool == true),
                    venue: e["venue"]["fullName"].string ?? e["venue"]["displayName"].string,
                    champion: champ
                )
            }
            // Team events ESPN doesn't cover: results from Wikipedia.
            let cal = Calendar.current
            func date(_ m: Int, _ day: Int) -> Date { cal.date(from: DateComponents(year: year, month: m, day: day)) ?? Date() }
            out.append(TournamentSummary(id: "laver-\(year)", name: "Laver Cup", start: date(9, 18), end: date(9, 27),
                                         tier: .team, venue: nil, champion: nil, wikiTitle: "\(year) Laver Cup"))
            out.append(TournamentSummary(id: "davis-\(year)", name: "Davis Cup Finals", start: date(11, 17), end: date(11, 29),
                                         tier: .team, venue: nil, champion: nil, wikiTitle: "\(year) Davis Cup Finals"))
            return out.sorted { $0.start < $1.start }
        }.value
        indexCache[year] = (Date(), list)
        return list
    }

    // MARK: Player season

    struct PlayerMatch: Identifiable, Hashable {
        var id: String
        let date: Date
        let tournament: String
        let tier: TennisTier
        let round: String
        let opponent: String
        let won: Bool
        let score: String
        var playerId: String = ""
        var playerName: String = ""
        var playerFlag: URL? = nil
        var opponentId: String = ""
        var opponentFlag: URL? = nil
        /// Games per set: (player, opponent, tiebreak points of the set loser if any).
        var sets: [SetScore] = []
    }

    struct SetScore: Hashable {
        let mine: Int
        let theirs: Int
        let tiebreak: Int?
    }

    struct PlayerSeason {
        var matches: [PlayerMatch]        // newest first
        var wins: Int { matches.filter(\.won).count }
        var losses: Int { matches.filter { !$0.won }.count }
        /// Furthest round per tournament, newest first ("Australian Open" -> "Won", "Final", "Semifinal"...).
        var results: [(tournament: String, tier: TennisTier, result: String)]
        var titles: [String]
        var finals: Int
    }

    /// One player's singles matches in a season, from the same ESPN season data as the calendar.
    static func playerSeason(id: String, year: Int) async throws -> PlayerSeason {
        guard let url = URL(string: "\(ESPN.site)/tennis/atp/scoreboard?dates=\(year)") else { throw FetchError.parse("Bad URL") }
        let past = year < Calendar.current.component(.year, from: Date())
        let data = try await HTTP.shared.data(url, maxAge: past ? 86_400 * 60 : 43_200, permanent: past)
        return try await Task.detached(priority: .userInitiated) { () throws -> PlayerSeason in
            let d = try J(data: data)
            var matches: [PlayerMatch] = []
            var results: [(String, TennisTier, String, Date)] = []
            var titles: [String] = []
            var finals = 0
            let order = ["Round 1", "Round 2", "Round 3", "Round 4", "Quarterfinal", "Semifinal", "Final"]
            for e in d["events"].array {
                guard let singles = e["groupings"].array.first(where: { $0["grouping"]["slug"].str == "mens-singles" }) else { continue }
                let name = Tennis.cleanName(e["name"].str)
                let tier = TennisTier.of(name: e["name"].str, major: e["major"].bool == true)
                var best = -1, bestRound = "", lastDate = Date.distantPast, wonFinal = false
                for c in singles["competitions"].array where c["status"]["type"]["state"].str == "post" {
                    let round = c["round"]["displayName"].str
                    if round.lowercased().contains("qualif") { continue }
                    let comps = c["competitors"].array
                    guard let me = comps.first(where: { $0["id"].str == id }),
                          let them = comps.first(where: { $0["id"].str != id }) else { continue }
                    let date = ESPNDate.parse(c["date"].string) ?? Date.distantPast
                    let mine = me["linescores"].array.map { Int($0["value"].double ?? 0) }
                    let theirs = them["linescores"].array.map { Int($0["value"].double ?? 0) }
                    let score = zip(mine, theirs).map { "\($0)-\($1)" }.joined(separator: " ")
                    let won = me["winner"].bool == true
                    let myTB = me["linescores"].array.map { $0["tiebreak"].int }
                    let theirTB = them["linescores"].array.map { $0["tiebreak"].int }
                    let sets = zip(mine, theirs).enumerated().map { i, g in
                        SetScore(mine: g.0, theirs: g.1, tiebreak: (i < myTB.count ? myTB[i] : nil) ?? (i < theirTB.count ? theirTB[i] : nil))
                    }
                    matches.append(PlayerMatch(id: c["id"].str, date: date, tournament: name, tier: tier, round: round,
                                               opponent: them["athlete"]["displayName"].str, won: won, score: score,
                                               playerId: id, playerName: me["athlete"]["displayName"].str,
                                               playerFlag: me["athlete"]["flag"]["href"].url,
                                               opponentId: them["id"].str, opponentFlag: them["athlete"]["flag"]["href"].url,
                                               sets: sets))
                    let idx = order.firstIndex(of: round) ?? (round.contains("Round Robin") || round.contains("Group") ? 4 : 0)
                    if idx >= best { best = idx; bestRound = round }
                    if round == "Final" { finals += 1; if won { wonFinal = true; titles.append(name) } }
                    lastDate = max(lastDate, date)
                }
                if best >= 0 {
                    results.append((name, tier, wonFinal ? "Won" : bestRound, lastDate))
                }
            }
            matches.sort { $0.date > $1.date }
            results.sort { $0.3 > $1.3 }
            return PlayerSeason(matches: matches, results: results.map { (tournament: $0.0, tier: $0.1, result: $0.2) }, titles: titles, finals: finals)
        }.value
    }

    // MARK: Career (Wikipedia infobox)

    /// Singles career rows from the player's Wikipedia infobox: record, titles, rankings,
    /// and best results at the Grand Slams, ATP Finals and Olympics.
    static func career(name: String) async -> (career: [InfoRow], majors: [InfoRow]) {
        var html: String?
        for title in [name + " (tennis)", name] {
            if let u = CyclingService.wikiURL(title), let h = try? await HTTP.shared.text(u, maxAge: 86_400 * 2),
               h.contains("Career record") { html = h; break }
        }
        guard let html, let start = html.range(of: "infobox") else { return ([], []) }
        // The singles block comes before "Doubles"; stop there.
        let rest = html[start.lowerBound...]
        let end = rest.range(of: ">Doubles<")?.lowerBound ?? rest.range(of: "</table>")?.lowerBound ?? rest.endIndex
        let box = String(rest[..<end])
        var pairs: [(String, String)] = []
        let re = try? NSRegularExpression(pattern: #"<th[^>]*>(.*?)</th>\s*<td[^>]*>(.*?)</td>"#, options: [.dotMatchesLineSeparators])
        let ns = box as NSString
        for m in re?.matches(in: box, range: NSRange(location: 0, length: ns.length)) ?? [] {
            let k = WikiHTML.clean(ns.substring(with: m.range(at: 1)))
            let v = WikiHTML.clean(ns.substring(with: m.range(at: 2)))
            if !k.isEmpty, !v.isEmpty { pairs.append((k, v)) }
        }
        func first(_ key: String) -> String? { pairs.first { $0.0.lowercased() == key.lowercased() }?.1 }
        var career: [InfoRow] = []
        for (label, key) in [("Career record", "Career record"), ("Career titles", "Career titles"),
                             ("Highest ranking", "Highest ranking"), ("Current ranking", "Current ranking"),
                             ("Prize money", "Prize money")] {
            if let v = first(key) { career.append(InfoRow(label: label, value: v)) }
        }
        var majors: [InfoRow] = []
        for key in ["Australian Open", "French Open", "Wimbledon", "US Open", "Tour Finals", "Olympic Games"] {
            if let v = first(key) { majors.append(InfoRow(label: key == "Tour Finals" ? "ATP Finals" : key, value: v)) }
        }
        return (career, majors)
    }

    /// "Brisbane International presented by ANZ" -> "Brisbane International"
    static func cleanName(_ n: String) -> String {
        var s = n
        for sep in [" presented by ", " presentado por ", " présenté par ", " by "] {
            if let r = s.range(of: sep) { s = String(s[..<r.lowerBound]) }
        }
        return s
    }

    /// One tournament's draw (the scoreboard for a date inside it).
    static func tournament(_ t: TournamentSummary, grouping: String) async throws -> TennisEvent? {
        let cal = Calendar.current
        let probe = min(cal.date(byAdding: .day, value: 2, to: t.start) ?? t.start, t.end)
        guard let url = URL(string: "\(ESPN.site)/tennis/atp/scoreboard?dates=\(ESPNDate.ymd(probe))") else { return nil }
        let finished = Date() > t.end.addingTimeInterval(86_400 * 2)
        let d = try await HTTP.shared.json(url, maxAge: finished ? 86_400 * 30 : 60)
        guard let ev = d["events"].array.first(where: { $0["id"].str == t.id }) else { return nil }
        return ESPN.tennisEvent(ev, grouping: grouping)
    }

    static func rankings() async throws -> [RankingEntry] {
        guard let url = URL(string: "\(ESPN.site)/tennis/atp/rankings") else { return [] }
        let d = try await HTTP.shared.json(url, maxAge: 3600 * 6)
        let ranks = d["rankings"].array.first { $0["type"].str == "atp" || $0["name"].str == "ATP" } ?? d["rankings"][0]
        return ranks["ranks"].array.map { r in
            let a = r["athlete"]
            // In the rankings feed, flag and headshot are plain URLs (in draws they're objects).
            let id = a["id"].str
            return RankingEntry(
                rank: r["current"].int ?? 0,
                previous: r["previous"].int,
                points: r["points"].double ?? 0,
                playerId: id,
                name: a["displayName"].str,
                flag: a["flag"].url ?? a["flag"]["href"].url,
                country: a["flag"]["alt"].string ?? a["citizenship"].string,
                headshot: a["headshot"].url ?? a["headshot"]["href"].url
                    ?? URL(string: "https://a.espncdn.com/i/headshots/tennis/players/full/\(id).png")
            )
        }
    }

    // MARK: Round robin (ATP Finals)

    struct GroupRow: Hashable {
        let name: String
        let flag: URL?
        var wins = 0, losses = 0, setsWon = 0, setsLost = 0, gamesWon = 0, gamesLost = 0
    }

    /// ESPN labels every group match "Group Stage": rebuild the two groups from who played whom.
    static func groups(_ matches: [TennisMatch]) -> [[GroupRow]] {
        let rr = matches.filter { $0.round.lowercased().contains("group") || $0.round.lowercased().contains("round robin") }
        guard !rr.isEmpty else { return [] }
        var adj: [String: Set<String>] = [:]
        for m in rr where m.players.count == 2 {
            let a = m.players[0].name, b = m.players[1].name
            adj[a, default: []].insert(b)
            adj[b, default: []].insert(a)
        }
        var seen = Set<String>()
        var comps: [[String]] = []
        for start in adj.keys.sorted() where !seen.contains(start) {
            var stack = [start], comp: [String] = []
            while let n = stack.popLast() {
                if !seen.insert(n).inserted { continue }
                comp.append(n)
                stack.append(contentsOf: adj[n] ?? [])
            }
            comps.append(comp)
        }
        var rows: [String: GroupRow] = [:]
        for m in rr where m.players.count == 2 {
            for (i, p) in m.players.enumerated() {
                var r = rows[p.name] ?? GroupRow(name: p.name, flag: p.flag)
                let o = m.players[1 - i]
                if m.state == .post {
                    if p.winner == true { r.wins += 1 } else if o.winner == true { r.losses += 1 }
                }
                for (k, s) in p.sets.enumerated() where k < o.sets.count {
                    r.gamesWon += s.games
                    r.gamesLost += o.sets[k].games
                    if s.games > o.sets[k].games || (s.games == o.sets[k].games && (s.tiebreak ?? 0) > (o.sets[k].tiebreak ?? 0)) { r.setsWon += 1 }
                    else if s.games < o.sets[k].games || (s.tiebreak ?? 0) < (o.sets[k].tiebreak ?? 0) { r.setsLost += 1 }
                }
                rows[p.name] = r
            }
        }
        // Group containing the top seed first.
        let seedOf = Dictionary(rr.flatMap { $0.players.map { ($0.name, $0.seed ?? 99) } }, uniquingKeysWith: min)
        return comps
            .sorted { ($0.compactMap { seedOf[$0] }.min() ?? 99) < ($1.compactMap { seedOf[$0] }.min() ?? 99) }
            .map { names in
                names.compactMap { rows[$0] }.sorted {
                    ($0.wins, $0.setsWon - $0.setsLost, $0.gamesWon - $0.gamesLost) > ($1.wins, $1.setsWon - $1.setsLost, $1.gamesWon - $1.gamesLost)
                }
            }
    }
}

extension ESPN {
    static func roundLabel(_ round: String, matchesInRound: Int) -> String {
        switch round {
        case "Quarterfinal": return "QF"
        case "Semifinal": return "SF"
        case "Final": return "Final"
        case "Group Stage", "Round Robin": return "Groups"
        default:
            if round.hasPrefix("Round "), matchesInRound > 4 { return "R\(matchesInRound * 2)" }
            return round
        }
    }

    static let tennisRoundOrder = ["Group Stage", "Round Robin", "Round 1", "Round 2", "Round 3", "Round 4", "Round 5",
                                   "Quarterfinal", "Semifinal", "Final"]
}
