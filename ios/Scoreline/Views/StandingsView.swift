import SwiftUI

// MARK: - Columns

private struct Col {
    let key: String
    let label: String
    var strong = false
    var width: CGFloat = 30
}

private func columns(_ league: League) -> [Col] {
    switch league.family {
    case .soccer:
        return [Col(key: "gamesPlayed", label: "P", width: 24), Col(key: "wins", label: "W", width: 24),
                Col(key: "ties", label: "D", width: 24), Col(key: "losses", label: "L", width: 24),
                Col(key: "pointDifferential", label: "GD", width: 34), Col(key: "points", label: "Pts", strong: true, width: 32)]
    case .baseball:
        return [Col(key: "wins", label: "W", width: 28), Col(key: "losses", label: "L", width: 28),
                Col(key: "winPercent", label: "PCT", strong: true, width: 40), Col(key: "gamesBehind", label: "GB", width: 32),
                Col(key: "Last Ten Games", label: "L10", width: 34), Col(key: "streak", label: "STRK", width: 36)]
    default:
        if league.provider == .bbl {
            return [Col(key: "wins", label: "W", width: 26), Col(key: "losses", label: "L", width: 26),
                    Col(key: "winPercent", label: "PCT", strong: true, width: 40), Col(key: "differential", label: "+/-", width: 40),
                    Col(key: "Last Ten Games", label: "L10", width: 32), Col(key: "streak", label: "STRK", width: 36)]
        }
        return [Col(key: "wins", label: "W", width: 26), Col(key: "losses", label: "L", width: 26),
                Col(key: "winPercent", label: "PCT", strong: true, width: 40), Col(key: "gamesBehind", label: "GB", width: 32),
                Col(key: "Last Ten Games", label: "L10", width: 32), Col(key: "streak", label: "STRK", width: 36)]
    }
}

/// Extra stats shown when a row is tapped.
private func details(_ league: League) -> [Col] {
    switch league.family {
    case .soccer:
        return [Col(key: "pointsFor", label: "Goals for"), Col(key: "pointsAgainst", label: "Goals against"),
                Col(key: "ppg", label: "Points per game")]
    case .baseball:
        return [Col(key: "Home", label: "Home"), Col(key: "Road", label: "Away"), Col(key: "pointsFor", label: "Runs scored"),
                Col(key: "pointsAgainst", label: "Runs allowed"), Col(key: "pointDifferential", label: "Run differential"),
                Col(key: "vs. Div.", label: "vs. Division")]
    default:
        if league.provider == .bbl {
            return [Col(key: "Home", label: "Home"), Col(key: "Road", label: "Away"), Col(key: "pointsFor", label: "Points scored"),
                    Col(key: "pointsAgainst", label: "Points allowed"), Col(key: "gamesPlayed", label: "Games")]
        }
        return [Col(key: "Home", label: "Home"), Col(key: "Road", label: "Away"), Col(key: "avgPointsFor", label: "Points per game"),
                Col(key: "avgPointsAgainst", label: "Opp. points per game"), Col(key: "differential", label: "Point differential"),
                Col(key: "vs. Conf.", label: "vs. Conference")]
    }
}

// MARK: - Zones

struct Zone: Equatable {
    let label: String
    let color: Color
}

private func soccerZone(_ text: String?) -> Zone? {
    guard let text, !text.isEmpty else { return nil }
    let t = text.lowercased()
    let color: Color
    if t.contains("relegation playoff") || t.contains("relegation play-off") { color = Color(hex: "ff9f0a") }
    else if t.contains("relegation") || t.contains("eliminated") { color = Color(hex: "ff453a") }
    else if t.contains("promotion playoff") || t.contains("promotion play-off") { color = Color(hex: "64d2ff") }
    else if t.contains("promotion") || t.contains("round of 16") { color = Color(hex: "30d158") }
    else if t.contains("champions league") { color = Color(hex: "0a84ff") }
    else if t.contains("europa") { color = Color(hex: "ff9f0a") }
    else if t.contains("conference") { color = Color(hex: "30d158") }
    else if t.contains("unseeded") { color = Color(hex: "5e5ce6") }
    else if t.contains("playoff") { color = Color(hex: "64d2ff") }
    else { color = Color(white: 0.6) }
    var label = text
    label = label.replacingOccurrences(of: "Qualifies for round of 16", with: "Round of 16")
    label = label.replacingOccurrences(of: "Knockout phase playoffs", with: "Knockout play-offs")
    return Zone(label: label, color: color)
}

private func zones(_ league: League, group: StandingGroup, rows: [StandingRow], divisions: Bool) -> [Zone?] {
    let n = rows.count
    func byIndex(_ f: (Int) -> Zone?) -> [Zone?] { (0..<n).map(f) }
    let playoffs = Zone(label: "Playoffs", color: Color(hex: "30d158"))
    let playIn = Zone(label: "Play-In", color: Color(hex: "ff9f0a"))
    switch league.family {
    case .soccer:
        return rows.map { soccerZone($0.noteText) }
    case .baseball:
        if divisions { return Array(repeating: nil, count: n) }
        return byIndex { i in
            i < 3 ? Zone(label: "Division Leaders", color: Color(hex: "30d158"))
                : i < 6 ? Zone(label: "Wild Card", color: Color(hex: "64d2ff")) : nil
        }
    default:
        if league.provider == .bbl {
            return byIndex { i in
                i < 6 ? playoffs : i < 10 ? playIn : i >= n - 2 ? Zone(label: "Relegation", color: Color(hex: "ff453a")) : nil
            }
        }
        if divisions { return Array(repeating: nil, count: n) }
        return byIndex { i in i < 6 ? playoffs : i < 10 ? playIn : nil }
    }
}

private func sortRows(_ league: League, _ rows: [StandingRow], divisions: Bool) -> [StandingRow] {
    func num(_ r: StandingRow, _ k: String) -> Double { Double(r.stats[k] ?? "") ?? 0 }
    switch league.family {
    case .soccer:
        return rows.sorted { (Int($0.stats["rank"] ?? "") ?? 99) < (Int($1.stats["rank"] ?? "") ?? 99) }
    default:
        if league.provider == .bbl {
            return rows.sorted { (Int($0.stats["rank"] ?? "") ?? 99) < (Int($1.stats["rank"] ?? "") ?? 99) }
        }
        if !divisions {
            return rows.sorted {
                let a = Int($0.stats["playoffSeed"] ?? "") ?? 0, b = Int($1.stats["playoffSeed"] ?? "") ?? 0
                if a > 0, b > 0, a != b { return a < b }
                if (a > 0) != (b > 0) { return a > 0 }
                return num($0, "winPercent") > num($1, "winPercent")
            }
        }
        return rows.sorted {
            let a = num($0, "winPercent"), b = num($1, "winPercent")
            return a != b ? a > b : num($0, "wins") > num($1, "wins")
        }
    }
}

// MARK: - Live football table

struct LiveInfo: Hashable {
    let text: String
    let movement: Int
}

/// Adds in-progress matches to the standings as if they ended at the current score.
func applyLive(_ rows: [StandingRow], games: [Game]) -> (rows: [StandingRow], live: [String: LiveInfo]) {
    let live = games.filter { $0.state == .live }
    guard !live.isEmpty else { return (rows, [:]) }
    let before = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($1.id, $0) })
    var info: [String: String] = [:]
    var updated = rows.map { row -> StandingRow in
        guard let g = live.first(where: { $0.home.id == row.id || $0.away.id == row.id }) else { return row }
        let me = g.home.id == row.id ? g.home : g.away
        let other = g.home.id == row.id ? g.away : g.home
        let gf = Int(me.score ?? "") ?? 0, ga = Int(other.score ?? "") ?? 0
        var s = row.stats
        func bump(_ k: String, _ by: Int) { s[k] = String((Int(s[k] ?? "") ?? 0) + by) }
        bump("gamesPlayed", 1)
        bump("pointsFor", gf)
        bump("pointsAgainst", ga)
        if gf > ga { bump("wins", 1); bump("points", 3) } else if gf == ga { bump("ties", 1); bump("points", 1) } else { bump("losses", 1) }
        let gd = (Int(s["pointsFor"] ?? "") ?? 0) - (Int(s["pointsAgainst"] ?? "") ?? 0)
        s["pointDifferential"] = gd > 0 ? "+\(gd)" : "\(gd)"
        info[row.id] = "\(gf)–\(ga) \(g.home.id == row.id ? "vs" : "@") \(other.short) · \(g.statusText)"
        return StandingRow(id: row.id, name: row.name, short: row.short, abbr: row.abbr, logo: row.logo,
                           stats: s, noteColor: row.noteColor, noteText: row.noteText)
    }
    func n(_ r: StandingRow, _ k: String) -> Int { Int((r.stats[k] ?? "").replacingOccurrences(of: "+", with: "")) ?? 0 }
    updated.sort {
        let a = ($0.stats["points"].flatMap { Int($0) } ?? 0, n($0, "pointDifferential"), n($0, "pointsFor"))
        let b = ($1.stats["points"].flatMap { Int($0) } ?? 0, n($1, "pointDifferential"), n($1, "pointsFor"))
        return a > b
    }
    // Zones belong to positions, not teams: keep each position's original zone.
    let zonesByPosition = rows.map { ($0.noteText, $0.noteColor) }
    var result: [StandingRow] = []
    var liveInfo: [String: LiveInfo] = [:]
    for (i, r) in updated.enumerated() {
        var s = r.stats
        s["rank"] = String(i + 1)
        let z = i < zonesByPosition.count ? zonesByPosition[i] : (nil, nil)
        result.append(StandingRow(id: r.id, name: r.name, short: r.short, abbr: r.abbr, logo: r.logo,
                                  stats: s, noteColor: z.1, noteText: z.0))
        let move = (before[r.id] ?? i) - i
        if let t = info[r.id] { liveInfo[r.id] = LiveInfo(text: t, movement: move) }
        else if move != 0 { liveInfo[r.id] = LiveInfo(text: "", movement: move) }
    }
    return (result, liveInfo)
}

// MARK: - View

struct StandingsData {
    let groups: [StandingGroup]
    let liveGames: [Game]
}

struct StandingsSection: View {
    let league: League
    var refresh = 0
    @State private var divisions = false

    var body: some View {
        VStack(spacing: 12) {
            if league.family != .soccer && league.provider == .espn {
                Picker("", selection: $divisions) {
                    Text(league.family == .baseball ? "League" : "Conference").tag(false)
                    Text("Division").tag(true)
                }
                .pickerStyle(.segmented)
            }
            Loader(id: "\(league.id)-standings-\(divisions)-\(refresh)",
                   poll: { (d: StandingsData) in d.liveGames.isEmpty ? nil : 30 },
                   load: { () async throws -> StandingsData in
                       let groups: [StandingGroup]
                       if league.provider == .bbl { groups = try await BBL.standings() }
                       else { groups = try await ESPN.standings(league, divisions: divisions) }
                       var live: [Game] = []
                       if league.family == .soccer {
                           live = ((try? await ESPN.scoreboard(league, date: Date())) ?? []).filter { $0.state == .live }
                       }
                       return StandingsData(groups: groups, liveGames: live)
                   }) { data in
                if data.groups.isEmpty {
                    MessageCard(text: "No standings available.")
                } else {
                    VStack(spacing: 14) {
                        ForEach(data.groups) { g in
                            StandingsTable(league: league, group: g, divisions: divisions, liveGames: data.liveGames)
                        }
                    }
                }
            }
        }
    }
}

struct StandingsTable: View {
    let league: League
    let group: StandingGroup
    var divisions = false
    var liveGames: [Game] = []
    var compact = false
    @State private var expanded: String?
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let sorted = sortRows(league, group.rows, divisions: divisions)
        let applied: (rows: [StandingRow], live: [String: LiveInfo]) =
            league.family == .soccer ? applyLive(sorted, games: liveGames) : (rows: sorted, live: [:])
        let rows = applied.rows
        let live = applied.live
        let zs = zones(league, group: group, rows: rows, divisions: divisions)
        let cols = columns(league)
        let favs = store.favoriteTeamIds(league.id)

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(group.name).font(.headline)
                Spacer()
                if !live.filter({ !$0.value.text.isEmpty }).isEmpty {
                    HStack(spacing: 5) { LivePulse(); Text("LIVE") }
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(Theme.live)
                }
            }
            .padding(.bottom, 10)

            header(cols)
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                let zone = zs[i]
                let prev = i > 0 ? zs[i - 1] : nil
                if i > 0 && zone != prev {
                    zoneSeparator(zone)
                } else if i == 0, let zone {
                    zoneLabel(zone).padding(.bottom, 2)
                } else if i > 0 {
                    Divider().overlay(Theme.separator)
                }
                row(r, index: i, zone: zone, cols: cols, live: live[r.id], favorite: favs.contains(r.id))
            }
        }
        .card()
    }

    private func header(_ cols: [Col]) -> some View {
        HStack(spacing: 4) {
            Text("#").frame(width: 24, alignment: .leading)
            Text("Team").frame(maxWidth: .infinity, alignment: .leading)
            ForEach(cols, id: \.key) { Text($0.label).frame(width: $0.width, alignment: .trailing) }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Theme.secondary)
        .padding(.bottom, 6)
    }

    private func zoneLabel(_ z: Zone) -> some View {
        HStack(spacing: 6) {
            Circle().fill(z.color).frame(width: 7, height: 7)
            Text(z.label.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(z.color)
        }
        .padding(.top, 4)
    }

    @ViewBuilder private func zoneSeparator(_ z: Zone?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Rectangle().fill(Color.white.opacity(0.55)).frame(height: 1.5)
            if let z { zoneLabel(z) }
        }
        .padding(.vertical, 2)
    }

    private func row(_ r: StandingRow, index: Int, zone: Zone?, cols: [Col], live: LiveInfo?, favorite: Bool) -> some View {
        let isOpen = expanded == r.id
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) { expanded = isOpen ? nil : r.id }
            } label: {
                HStack(spacing: 4) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1.5).fill(zone?.color ?? .clear).frame(width: 3, height: 18)
                        Text(r.stats["rank"].flatMap { league.family == .soccer || league.provider == .bbl ? $0 : nil } ?? "\(index + 1)")
                            .foregroundStyle(Theme.secondary)
                            .font(.footnote.weight(.semibold))
                    }
                    .frame(width: 24, alignment: .leading)
                    HStack(spacing: 6) {
                        LogoView(url: r.logo, fallback: r.abbr, size: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(league.family == .soccer || league.provider == .bbl ? r.short : r.abbr)
                                    .fontWeight(.semibold)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                if let m = live?.movement, m != 0 {
                                    Text(m > 0 ? "▲\(m)" : "▼\(-m)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(m > 0 ? Theme.win : Theme.live)
                                }
                            }
                            if let t = live?.text, !t.isEmpty {
                                Text(t).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.live).lineLimit(1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(cols, id: \.key) { c in
                        Text(r.stats[c.key] ?? "–")
                            .fontWeight(c.strong ? .heavy : .regular)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(width: c.width, alignment: .trailing)
                    }
                }
                .font(.subheadline)
                .monospacedDigit()
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(details(league), id: \.key) { c in
                        if let v = r.stats[c.key], !v.isEmpty {
                            HStack {
                                Text(c.label).foregroundStyle(Theme.secondary)
                                Spacer()
                                Text(v).monospacedDigit()
                            }
                            .font(.footnote)
                        }
                    }
                    if let z = zone {
                        HStack {
                            Text("Zone").foregroundStyle(Theme.secondary)
                            Spacer()
                            Text(z.label).foregroundStyle(z.color)
                        }
                        .font(.footnote)
                    }
                    NavigationLink(value: Route.team(leagueId: league.id, teamId: r.id)) {
                        HStack {
                            Text("Team page").font(.footnote.weight(.semibold))
                            Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                .padding(.leading, 28)
                .padding(.bottom, 10)
                .transition(.opacity)
            }
        }
        .background(favorite ? Color.yellow.opacity(0.10) : .clear)
        .contextMenu {
            let fav = Favorite(leagueId: league.id, entityId: r.id, name: r.name, abbr: r.abbr, logo: r.logo)
            Button {
                store.toggle(fav)
            } label: {
                Label(favorite ? "Remove from My Teams" : "Add to My Teams", systemImage: favorite ? "star.slash" : "star")
            }
        }
    }
}
