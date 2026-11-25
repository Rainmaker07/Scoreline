import Foundation

/// Basketball Bundesliga (easyCredit BBL).
///
/// ESPN doesn't cover the BBL, and the league's JSON API requires
/// authorization, so we read the public pages of easycredit-bbl.de, which
/// embed their data as JSON (`<script id="__NEXT_DATA__">`), exactly what any
/// browser receives.
enum BBL {
    static let base = "https://www.easycredit-bbl.de"
    static var league: League { League.byId("bbl")! }

    /// The `pageProps` object embedded in a page.
    static func page(_ path: String, maxAge: TimeInterval) async throws -> J {
        guard let url = URL(string: base + path) else { throw FetchError.parse("Bad path") }
        let html = try await HTTP.shared.text(url, maxAge: maxAge)
        let marker = #"<script id="__NEXT_DATA__" type="application/json">"#
        guard let start = html.range(of: marker),
              let end = html.range(of: "</script>", range: start.upperBound..<html.endIndex) else {
            throw FetchError.parse("Page format changed")
        }
        let json = try J(data: Data(html[start.upperBound..<end.lowerBound].utf8))
        return json["props"]["pageProps"]
    }

    /// First value of `preloadedWidgetData` (keys embed a block id).
    private static func widget(_ props: J) -> J {
        props["preloadedWidgetData"].dict.values.first ?? J(nil)
    }

    // MARK: Games

    private static func side(_ t: J, score: Int?, home: Bool, record: String? = nil) -> Side {
        Side(
            id: t["teamId"].string ?? t["id"].str,
            name: t["name"].string ?? t["nameFull"].str,
            short: shortName(t["name"].string ?? t["nameFull"].str, tlc: t["tlc"].str),
            abbr: t["tlc"].str,
            logo: t["logoUrl"].url,
            color: nil, altColor: nil,
            score: score.map(String.init),
            winner: nil,
            record: record,
            linescores: [],
            isHome: home
        )
    }

    /// "Veolia Towers Hamburg" -> "Hamburg"; keep short names as they are.
    static func shortName(_ name: String, tlc: String) -> String {
        let known: [String: String] = [
            "FCB": "München", "BER": "ALBA Berlin", "ULM": "Ulm", "LUD": "Ludwigsburg", "BON": "Bonn",
            "OLD": "Oldenburg", "WÜR": "Würzburg", "WUE": "Würzburg", "HAM": "Hamburg", "HAG": "Hagen",
            "BRA": "Braunschweig", "BAM": "Bamberg", "CHE": "Chemnitz", "GÖT": "Göttingen", "GOE": "Göttingen",
            "HEI": "Heidelberg", "VEC": "Vechta", "BAY": "Bayreuth", "WEI": "Weißenfels", "MBC": "Weißenfels",
            "TRI": "Trier", "JEN": "Jena", "ROS": "Rostock", "HRO": "Rostock", "MIT": "Mitteldeutscher BC", "FRA": "Frankfurt", "BHV": "Bremerhaven",
        ]
        if let k = known[tlc.uppercased()] { return k }
        let last = name.split(separator: " ").last.map(String.init) ?? name
        // "SEAWOLVES" -> "Seawolves"
        return last == last.uppercased() && last.count > 3 ? last.capitalized : last
    }

    static func state(_ status: String) -> GameState {
        switch status.uppercased() {
        case "LIVE", "RUNNING", "IN_PROGRESS": return .live
        case "OFFICIAL", "ENDED", "FINISHED", "POST", "FINAL": return .post
        default: return .pre
        }
    }

    static func game(_ g: J, liveResult: J? = nil) -> Game {
        let result = (liveResult?.exists == true) ? liveResult! : g["result"]
        let st = state(g["status"].str)
        var home = side(g["homeTeam"], score: result["homeTeamFinalScore"].int, home: true)
        var away = side(g["guestTeam"], score: result["guestTeamFinalScore"].int, home: false)
        if result.exists {
            home.linescores = periodScores(result, prefix: "homeTeam")
            away.linescores = periodScores(result, prefix: "guestTeam")
            if st == .post, let h = result["homeTeamFinalScore"].int, let a = result["guestTeamFinalScore"].int {
                home.winner = h > a
                away.winner = a > h
            }
        }
        var status = ""
        switch st {
        case .post: status = (result["latestPeriod"].str.hasPrefix("OT") ? "Final/OT" : "Final")
        case .live:
            let period = result["latestPeriod"].string ?? ""
            let clock = g["gameTime"].string.map { String($0.suffix(5)) } ?? ""
            status = [period, clock == "00:00" ? "" : clock].filter { !$0.isEmpty }.joined(separator: " · ")
            if status.isEmpty { status = "Live" }
        case .pre: status = ""
        }
        let venue = g["venue"]["name"].string
        return Game(
            id: g["id"].str,
            leagueId: "bbl",
            date: ESPNDate.parse(g["scheduledTime"].string?.replacingOccurrences(of: ".000Z", with: "Z")) ?? Date(),
            state: st,
            statusText: status,
            home: home,
            away: away,
            note: g["matchDay"].int.map { "Matchday \($0)" + (venue.map { " · \($0)" } ?? "") },
            broadcast: g["tvChannel"].string,
            scorers: []
        )
    }

    static func periodScores(_ r: J, prefix: String) -> [String] {
        var out: [String] = []
        for q in 1...4 { out.append(r["\(prefix)Q\(q)Score"].int.map(String.init) ?? "") }
        for ot in 1...9 {
            if let v = r["\(prefix)OT\(ot)Score"].int, v > 0 { out.append(String(v)) }
        }
        // Drop trailing empty quarters for games in progress.
        while let last = out.last, last.isEmpty { out.removeLast() }
        return out
    }

    /// Current round: finished + scheduled (+ live, with scores from each game page).
    static func games() async throws -> [Game] {
        let w = widget(try await page("/saison/aktuelle-spiele", maxAge: 30))
        let items = w["finishedGames"]["items"].array + w["scheduledGames"]["items"].array
        var seen = Set<String>()
        var out: [Game] = []
        for item in items where seen.insert(item["id"].str).inserted {
            var g = game(item)
            if g.state == .live, let detail = try? await page("/spiele/\(g.id)", maxAge: 20) {
                g = game(detail["initialGameData"])
            }
            out.append(g)
        }
        return out.sorted { $0.date < $1.date }
    }

    static func games(on date: Date) async throws -> [Game] {
        try await games().filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    // MARK: Standings

    static func standings() async throws -> [StandingGroup] {
        let w = widget(try await page("/saison/tabelle", maxAge: 300))
        let rows: [StandingRow] = w["standings"].array.map { s in
            let t = s["seasonTeam"]
            let pct = (s["totalVictoryPercentage"].double ?? 0) / 100
            var pctText = String(format: "%.3f", pct)
            if pctText.hasPrefix("0") { pctText.removeFirst() }
            let stats: [String: String] = [
                "rank": s["rank"].str,
                "playoffSeed": s["rank"].str,
                "gamesPlayed": s["totalGames"].str,
                "wins": s["totalVictories"].str,
                "losses": s["totalLosses"].str,
                "winPercent": pctText,
                "pointsFor": s["totalGoalsMade"].str,
                "pointsAgainst": s["totalGoalsAgainst"].str,
                "differential": signed(s["totalGoalDifference"].int ?? 0),
                "Home": "\(s["homeVictories"].str)-\(s["homeLosses"].str)",
                "Road": "\(s["awayVictories"].str)-\(s["awayLosses"].str)",
                "Last Ten Games": "\(s["last10Victories"].str)-\(s["last10Losses"].str)",
                "streak": "\(s["streak"].str)\(s["streakCount"].str)",
                "points": "\(s["totalPointsMade"].str):\(s["totalPointsAgainst"].str)",
            ]
            return StandingRow(
                id: t["teamId"].string ?? t["id"].str,
                name: t["name"].str,
                short: t["nameShort"].string ?? shortName(t["name"].str, tlc: t["tlc"].str),
                abbr: t["tlc"].str,
                logo: t["logoUrl"].url,
                stats: stats,
                noteColor: nil,
                noteText: nil
            )
        }
        return [StandingGroup(name: "easyCredit BBL", rows: rows)]
    }

    static func signed(_ v: Int) -> String { v > 0 ? "+\(v)" : "\(v)" }

    // MARK: Game detail

    struct BoxPlayer: Hashable {
        let id: String
        let name: String
        let number: String
        let starter: Bool
        let stats: [String]
        var position: String = ""
        var headshot: URL? = nil
        var played: Bool = true
    }

    struct GameDetail {
        let game: Game
        let teamStats: [String: [String: String]]   // teamId -> stat -> value
        let box: [String: [BoxPlayer]]               // teamId -> players
        let coaches: [String: String]
        let info: [InfoRow]
    }

    static let boxLabels = ["MIN", "PTS", "FG", "3PT", "FT", "REB", "AST", "STL", "BLK", "TO", "PF", "+/-", "EFF"]

    /// Whole minutes ("23:41" -> "24").
    private static func minutes(_ seconds: Int) -> String {
        String(Int((Double(seconds) / 60).rounded()))
    }

    static func boxLine(_ p: J) -> [String] {
        [
            minutes(p["secondsPlayed"].int ?? 0),
            p["points"].str,
            "\(p["fieldGoalsMade"].str)-\(p["fieldGoalsAttempted"].str)",
            "\(p["threePointShotsMade"].str)-\(p["threePointShotsAttempted"].str)",
            "\(p["freeThrowsMade"].str)-\(p["freeThrowsAttempted"].str)",
            p["totalRebounds"].str, p["assists"].str, p["steals"].str, p["blocks"].str,
            p["turnovers"].str, p["foulsCommitted"].str, p["plusMinus"].str, p["efficiency"].str,
        ]
    }

    static func gameDetail(_ id: String) async throws -> GameDetail {
        let props = try await page("/spiele/\(id)", maxAge: 15)
        let g = game(props["initialGameData"])
        let stats = props["initialGameStats"]
        var teamStats: [String: [String: String]] = [:]
        var box: [String: [BoxPlayer]] = [:]
        var coaches: [String: String] = [:]
        for key in ["homeTeam", "guestTeam"] {
            let t = stats[key]
            let tid = t["id"].str
            let gs = t["gameStat"]
            func pct(_ k: String) -> String { gs[k].double.map { String(format: "%.0f%%", $0) } ?? "" }
            teamStats[tid] = [
                "fieldGoalPct": pct("fieldGoalsSuccessPercent"),
                "threePointFieldGoalPct": pct("threePointShotSuccessPercent"),
                "freeThrowPct": pct("freeThrowsSuccessPercent"),
                "totalRebounds": gs["totalRebounds"].str,
                "offensiveRebounds": gs["offensiveRebounds"].str,
                "assists": gs["assists"].str,
                "steals": gs["steals"].str,
                "blocks": gs["blocks"].str,
                "turnovers": gs["turnovers"].str,
                "fouls": gs["foulsCommitted"].str,
                "efficiency": gs["efficiency"].str,
            ].filter { !$0.value.isEmpty }
            box[tid] = t["playerStats"].array.map { p in
                let sp = p["seasonPlayer"]
                return BoxPlayer(
                    id: sp["id"].str,
                    name: "\(sp["firstName"].str.prefix(1)). \(sp["lastName"].str)",
                    number: p["shirtNumber"].string ?? sp["shirtNumber"].str,
                    starter: p["isStartingFive"].bool ?? false,
                    stats: boxLine(p),
                    position: sp["position"].string.map(positionShort) ?? "",
                    headshot: sp["imageUrl"].url,
                    played: (p["secondsPlayed"].int ?? 0) > 0
                )
            }.sorted { ($0.starter ? 0 : 1, -(Int($0.stats[1]) ?? 0)) < ($1.starter ? 0 : 1, -(Int($1.stats[1]) ?? 0)) }
            if let c = t["headCoachName"].string { coaches[tid] = c }
        }
        let gd = props["initialGameData"]
        var info: [InfoRow] = []
        if let v = gd["venue"]["name"].string { info.append(InfoRow(label: "Venue", value: v)) }
        if let s = gd["result"]["spectators"].int, s > 0 { info.append(InfoRow(label: "Attendance", value: s.formatted())) }
        let refs = ["referee1", "referee2", "referee3"].compactMap { k -> String? in
            let r = gd[k]
            return r.exists ? "\(r["firstName"].str) \(r["lastName"].str)" : nil
        }
        if !refs.isEmpty { info.append(InfoRow(label: "Referees", value: refs.joined(separator: ", "))) }
        if let tv = gd["tvChannel"].string, !tv.isEmpty { info.append(InfoRow(label: "TV", value: tv)) }
        return GameDetail(game: g, teamStats: teamStats, box: box, coaches: coaches, info: info)
    }

    // MARK: Team / player pages

    static func team(_ id: String) async throws -> TeamPage {
        let p = try await page("/teams/\(id)", maxAge: 600)
        let t = p["team"]
        let st = p["seasonTeam"]["mainRoundStanding"]
        let games = (p["games"]["items"].array + p["scheduledGames"]["items"].array).map { game($0) }
        let roster: [RosterPlayer] = p["playerStatistics"].array.map { s in
            let sp = s["seasonPlayer"]
            let line = String(format: "%.1f PTS · %.1f REB · %.1f AST",
                              s["pointsPerGame"].double ?? 0, s["totalReboundsPerGame"].double ?? 0, s["assistsPerGame"].double ?? 0)
            return RosterPlayer(
                id: sp["id"].str,
                name: "\(sp["firstName"].str) \(sp["lastName"].str)",
                jersey: sp["shirtNumber"].string,
                position: positionShort(sp["position"].str),
                age: nil, height: nil,
                headshot: sp["imageUrl"].url,
                group: nil,
                statLine: line
            )
        }
        var stats: [InfoRow] = []
        let ts = p["teamSeasonStatComparison"]["teamSeasonStat"]
        let os = p["teamSeasonStatComparison"]["opponentSeasonStat"]
        func per(_ j: J, _ k: String) -> String { j[k].double.map { String(format: "%.1f", $0) } ?? "–" }
        if ts.exists {
            stats.append(InfoRow(label: "Points per game", value: per(ts, "pointsPerGame")))
            stats.append(InfoRow(label: "Opp. points per game", value: per(os, "pointsPerGame")))
            stats.append(InfoRow(label: "Rebounds per game", value: per(ts, "totalReboundsPerGame")))
            stats.append(InfoRow(label: "Assists per game", value: per(ts, "assistsPerGame")))
            stats.append(InfoRow(label: "3-point %", value: ts["threePointShotSuccessPercent"].double.map { String(format: "%.1f%%", $0) } ?? "–"))
        }
        if st.exists {
            stats.append(InfoRow(label: "Home", value: "\(st["homeVictories"].str)-\(st["homeLosses"].str)"))
            stats.append(InfoRow(label: "Away", value: "\(st["awayVictories"].str)-\(st["awayLosses"].str)"))
        }
        let form = st["last10Outcomes"].array.map(\.str).suffix(5)
        return TeamPage(
            league: league, id: id,
            name: t["nameFull"].str,
            abbr: t["tlc"].str,
            logo: p["seasonLogoUrl"].url ?? t["logoUrl"].url,
            color: nil,
            record: st.exists ? "\(st["totalVictories"].str)-\(st["totalLosses"].str)" : nil,
            standing: st["rank"].int.map { "\(ordinal($0)) in easyCredit BBL" },
            games: games.sorted { $0.date < $1.date },
            roster: roster, stats: stats, injuries: [], form: Array(form)
        )
    }

    static func positionShort(_ p: String) -> String {
        switch p.uppercased() {
        case "POINT_GUARD": return "PG"
        case "SHOOTING_GUARD": return "SG"
        case "GUARD": return "G"
        case "SMALL_FORWARD": return "SF"
        case "POWER_FORWARD": return "PF"
        case "FORWARD": return "F"
        case "CENTER": return "C"
        default: return p.capitalized
        }
    }

    static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 100, n % 10) {
        case (11...13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }

    // MARK: Stat leaders

    /// Top 10 per category from the season player stats on easycredit-bbl.de/statistiken/spieler.
    /// Season stats of every player (one row each) from the statistics page.
    static func seasonPlayerRows() async throws -> [J] {
        let props = try await page("/statistiken/spieler", maxAge: 3600)
        guard let widget = props["preloadedWidgetData"].dict.first(where: { $0.key.contains("season-players-statistics") })?.value else {
            throw FetchError.parse("Stats widget missing")
        }
        return widget["data"].array
    }

    static func leaders() async throws -> [LeaderCategory] {
        let rows = try await seasonPlayerRows()
        let maxGames = rows.map { $0["gamesPlayed"].int ?? 0 }.max() ?? 0
        // Averages only count players with at least 40 % of the games.
        let qualified = rows.filter { Double($0["gamesPlayed"].int ?? 0) >= Double(maxGames) * 0.4 }

        func entry(_ r: J, value: String) -> LeaderEntry {
            let p = r["seasonPlayer"], t = r["seasonTeam"]
            return LeaderEntry(
                name: "\(p["firstName"].str) \(p["lastName"].str)".trimmingCharacters(in: .whitespaces),
                athleteId: p["playerId"].string ?? p["id"].string,
                position: p["position"].string.map(positionShort),
                team: t["name"].string,
                teamLogo: t["logoUrl"].url,
                headshot: p["imageUrl"].url,
                value: value,
                detail: nil
            )
        }
        func category(_ key: String, _ label: String, pool: [J], format: String = "%.1f", minAttempts: (String, Double)? = nil) -> LeaderCategory? {
            var list = pool
            if let m = minAttempts { list = list.filter { ($0[m.0].double ?? 0) >= m.1 } }
            let top = list.sorted { ($0[key].double ?? 0) > ($1[key].double ?? 0) }.prefix(10)
            guard !top.isEmpty else { return nil }
            return LeaderCategory(name: key, label: label,
                                  leaders: top.map { entry($0, value: String(format: format, $0[key].double ?? 0)) })
        }
        let games = Double(maxGames)
        return [
            category("pointsPerGame", "Points per game", pool: qualified),
            category("totalReboundsPerGame", "Rebounds per game", pool: qualified),
            category("assistsPerGame", "Assists per game", pool: qualified),
            category("efficiencyPerGame", "Efficiency per game", pool: qualified),
            category("stealsPerGame", "Steals per game", pool: qualified),
            category("blocksPerGame", "Blocks per game", pool: qualified),
            category("threePointShotsMadePerGame", "3-pointers per game", pool: qualified),
            category("fieldGoalsSuccessPercent", "Field goal %", pool: qualified, minAttempts: ("fieldGoalsAttempted", games * 4)),
            category("threePointShotSuccessPercent", "3-point %", pool: qualified, minAttempts: ("threePointShotsAttempted", games * 2)),
            category("freeThrowsSuccessPercent", "Free throw %", pool: qualified, minAttempts: ("freeThrowsAttempted", games * 1.5)),
        ].compactMap { $0 }
    }

    static func player(_ id: String) async throws -> PlayerPage {
        let p = try await page("/spieler/\(id)", maxAge: 600)
        let pl = p["player"]
        var bio: [InfoRow] = []
        func add(_ l: String, _ v: String?) { if let v, !v.isEmpty { bio.append(InfoRow(label: l, value: v)) } }
        add("Position", pl["position"].string.map { $0.replacingOccurrences(of: "_", with: " ").capitalized })
        add("Number", pl["shirtNumber"].string)
        if let b = pl["birthDate"].string {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
            if let d = f.date(from: b) {
                let age = Calendar.current.dateComponents([.year], from: d, to: Date()).year ?? 0
                add("Born", "\(Fmt.dateYear(d)) (age \(age))")
            }
        }
        if let h = pl["height"].double { add("Height", String(format: "%.2f m", h)) }
        if let w = pl["weight"].int { add("Weight", "\(w) kg") }
        let nats = pl["nationalities"].array.map(\.str).joined(separator: ", ")
        add("Nationality", nats)
        add("BBL games", pl["bblGamesPlayed"].int.map(String.init))

        let avg = p["averageStatistics"]["playerAverage"]
        // League rank among qualified players (the site's own "league average" is all zeros).
        let pool = (try? await seasonPlayerRows()) ?? []
        let maxGames = pool.map { $0["gamesPlayed"].int ?? 0 }.max() ?? 0
        let qualified = pool.filter { Double($0["gamesPlayed"].int ?? 0) >= Double(maxGames) * 0.4 }
        let me = qualified.first { r in
            let sp = r["seasonPlayer"]
            return sp["playerId"].str == id || sp["id"].str == id || String(sp["realPlayerId"].int ?? -1) == id
        }
        func rank(_ key: String) -> String? {
            guard let me, let mine = me[key].double else { return nil }
            let lowerIsBetter = key.hasPrefix("turnovers")
            let better = qualified.filter { lowerIsBetter ? ($0[key].double ?? 0) < mine : ($0[key].double ?? 0) > mine }.count
            return " (\(BBL.ordinal(better + 1)))"
        }
        let names: [(String, String)] = [("pointsPerGame", "Points"), ("totalReboundsPerGame", "Rebounds"), ("assistsPerGame", "Assists"),
                                         ("stealsPerGame", "Steals"), ("blocksPerGame", "Blocks"), ("turnoversPerGame", "Turnovers"),
                                         ("efficiencyPerGame", "Efficiency")]
        let season = names.compactMap { pair -> InfoRow? in
            let (k, label) = pair
            guard let v = avg[k].double else { return nil }
            return InfoRow(label: label + " per game", value: String(format: "%.1f", v) + (rank(k) ?? ""))
        }
        let labels = ["GP", "MIN", "PTS", "REB", "AST", "STL", "BLK", "FG%", "3P%", "FT%", "EFF"]
        let rows = p["seasonStatistics"].array.map { s -> (name: String, values: [String]) in
            let stage = s["stage"].str.replacingOccurrences(of: "_", with: " ").capitalized
            return (stage.isEmpty ? "Season" : stage, [
                s["gamesPlayed"].str,
                minutes(Int(s["secondsPerGame"].double ?? 0)),
                String(format: "%.1f", s["pointsPerGame"].double ?? 0),
                String(format: "%.1f", s["totalReboundsPerGame"].double ?? 0),
                String(format: "%.1f", s["assistsPerGame"].double ?? 0),
                String(format: "%.1f", s["stealsPerGame"].double ?? 0),
                String(format: "%.1f", s["blocksPerGame"].double ?? 0),
                String(format: "%.1f", s["fieldGoalsSuccessPercent"].double ?? 0),
                String(format: "%.1f", s["threePointShotSuccessPercent"].double ?? 0),
                String(format: "%.1f", s["freeThrowsSuccessPercent"].double ?? 0),
                String(format: "%.1f", s["efficiencyPerGame"].double ?? 0),
            ])
        }
        let team = p["team"]
        return PlayerPage(
            league: league, id: id,
            name: "\(pl["firstName"].str) \(pl["lastName"].str)",
            headshot: pl["imageUrl"].url,
            team: team["nameFull"].string,
            teamId: team["id"].string,
            teamLogo: team["logoUrl"].url,
            bio: bio,
            seasonStats: season,
            tables: rows.isEmpty ? [] : [StatTable(title: "Season averages", labels: labels, rows: rows)],
            gameLogLabels: [],
            gameLog: []
        )
    }
}
