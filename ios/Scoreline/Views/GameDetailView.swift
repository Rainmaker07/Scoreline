import SwiftUI

struct GameDetailView: View {
    let game: Game
    /// True when pushed inside a navigation stack (no close button).
    var embedded = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            if game.league.provider == .bbl {
                Loader(id: game.id,
                       poll: { (d: BBL.GameDetail) in d.game.state == .live ? 20 : nil },
                       load: { try await BBL.gameDetail(game.id) }) { d in
                    BBLGameDetailContent(detail: d, embedded: embedded, dismiss: { dismiss() })
                }
            } else {
                Loader(id: game.id,
                       poll: { (s: J) in s["header"]["competitions"][0]["status"]["type"]["state"].str == "in" ? 15 : nil },
                       load: { try await ESPN.summary(game.league, id: game.id) }) { summary in
                    GameDetailContent(game: game, summary: summary, embedded: embedded, dismiss: { dismiss() })
                }
            }
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(embedded ? .visible : .hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Header shared by ESPN and BBL games: logos, one-line scores, status.
struct GameHero: View {
    let game: Game
    let left: Side
    let right: Side
    var note: String?
    var embedded = false
    let dismiss: () -> Void

    var body: some View {
        let lc = Color.visibleTint(left.tintHex) ?? Color(white: 0.25)
        let rc = Color.visibleTint(right.tintHex) ?? Color(white: 0.25)
        let ln = Double(left.score ?? "") ?? 0
        let rn = Double(right.score ?? "") ?? 0
        VStack(spacing: 14) {
            if !embedded {
                HStack {
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 32, height: 32)
                            .background(.white.opacity(0.18), in: Circle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text(game.league.name).font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    Color.clear.frame(width: 32, height: 32)
                }
            }
            HStack(spacing: 4) {
                heroTeam(left).frame(width: 96)
                Group {
                    if game.state == .pre {
                        Text(left.record ?? "").font(.subheadline).foregroundStyle(.white.opacity(0.7))
                    } else {
                        ScoreText(text: left.score ?? "-", dim: game.state == .post && ln < rn, size: 58)
                    }
                }
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
                VStack(spacing: 3) {
                    if game.state == .pre {
                        Text(Fmt.time(game.date)).font(.title3.weight(.bold)).monospacedDigit()
                        Text(Fmt.day(game.date)).font(.caption).foregroundStyle(.white.opacity(0.75))
                    } else {
                        StatusLine(state: game.state, text: game.statusText)
                    }
                }
                .frame(width: 70)
                Group {
                    if game.state == .pre {
                        Text(right.record ?? "").font(.subheadline).foregroundStyle(.white.opacity(0.7))
                    } else {
                        ScoreText(text: right.score ?? "-", dim: game.state == .post && rn < ln, size: 58)
                    }
                }
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
                heroTeam(right).frame(width: 96)
            }
            if let note, !note.isEmpty {
                Text(note).font(.footnote).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, embedded ? 8 : 18)
        .padding(.bottom, 22)
        .background(LinearGradient(colors: [lc, .black, rc], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private func heroTeam(_ s: Side) -> some View {
        TeamLink(leagueId: game.leagueId, teamId: s.id, name: s.name, abbr: s.abbr, logo: s.logo) {
            VStack(spacing: 6) {
                LogoView(url: s.logo, fallback: s.abbr, size: 64)
                Text(s.short).font(.system(size: 15, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                if game.state != .pre, let r = s.record, !r.isEmpty {
                    Text(r).font(.caption).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }
}

private struct GameDetailContent: View {
    let game: Game
    let summary: J
    var embedded = false
    let dismiss: () -> Void

    private var league: League { game.league }
    private var comp: J { summary["header"]["competitions"][0] }

    private var sides: (home: Side, away: Side) {
        let cs = comp["competitors"].array
        guard cs.count == 2 else { return (game.home, game.away) }
        var h = ESPN.side(cs.first { $0["homeAway"].str == "home" } ?? cs[0])
        var a = ESPN.side(cs.first { $0["homeAway"].str == "away" } ?? cs[1])
        if h.logo == nil { h.logo = game.home.logo }
        if a.logo == nil { a.logo = game.away.logo }
        if h.color == nil { h.color = game.home.color }
        if a.color == nil { a.color = game.away.color }
        return (h, a)
    }

    private var live: Game {
        var g = game
        let s = sides
        g.home = s.home
        g.away = s.away
        if comp["status"].exists {
            let st = statusInfo(comp["status"], family: league.family)
            g.state = st.state
            g.statusText = st.text
        }
        return g
    }

    var body: some View {
        let g = live
        let left = g.ordered.left
        let right = g.ordered.right
        VStack(spacing: 14) {
            GameHero(game: g, left: left, right: right, note: g.note ?? comp["series"]["summary"].string,
                     embedded: embedded, dismiss: dismiss)
            Group {
                if league.family != .soccer {
                    LineScoreCard(league: league, left: left, right: right, comp: comp, hitsErrors: true)
                }
                if league.family == .soccer { TimelineCard(league: league, summary: summary, homeId: g.home.id) }
                if league.family == .baseball { DecisionsCard(league: league, comp: comp) }
                if league.family == .basketball { GameLeadersCard(league: league, summary: summary, left: left, right: right) }
                TeamStatsCard(league: league, summary: summary, left: left, right: right)
                if league.family == .soccer { LineupsCard(league: league, summary: summary, left: left, right: right) }
                if league.family != .soccer {
                    BoxScoreCards(league: league, summary: summary, side: left)
                    BoxScoreCards(league: league, summary: summary, side: right)
                }
                GameInfoCard(summary: summary)
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 40)
    }
}

/// Basketball Bundesliga game page.
private struct BBLGameDetailContent: View {
    let detail: BBL.GameDetail
    var embedded = false
    let dismiss: () -> Void

    var body: some View {
        let g = detail.game
        let left = g.away
        let right = g.home
        let league = g.league
        VStack(spacing: 14) {
            GameHero(game: g, left: left, right: right, note: g.note, embedded: embedded, dismiss: dismiss)
            Group {
                LineScoreCard(league: league, left: left, right: right, comp: J(nil), hitsErrors: false)
                if let lm = detail.teamStats[left.id], let rm = detail.teamStats[right.id] {
                    TeamStatsBars(league: league, left: left, right: right, lm: lm, rm: rm)
                }
                ForEach([left, right], id: \.id) { side in
                    if let players = detail.box[side.id], !players.isEmpty {
                        BoxTable(
                            title: side.short + (detail.coaches[side.id].map { " · Coach \($0)" } ?? ""),
                            logo: side.logo, abbr: side.abbr,
                            labels: BBL.boxLabels,
                            rows: players.map { p in
                                BoxRow(id: p.id, name: p.name, sub: "#\(p.number)", bench: !p.starter, stats: p.stats,
                                       route: .player(leagueId: "bbl", playerId: p.id))
                            },
                            totals: []
                        )
                    }
                }
                if !detail.info.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        CardTitle("Game Info")
                        ForEach(detail.info, id: \.label) { row in
                            HStack(alignment: .top) {
                                Text(row.label).foregroundStyle(Theme.secondary)
                                Spacer()
                                Text(row.value).multilineTextAlignment(.trailing)
                            }
                            .font(.subheadline)
                            .padding(.vertical, 7)
                            .overlay(alignment: .top) { Divider().overlay(Theme.separator) }
                        }
                    }
                    .card()
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 40)
    }
}

// MARK: - Line score

/// Scoring by period. Fills the card's width; only scrolls sideways when even
/// the compact version doesn't fit (e.g. extra innings).
private struct LineScoreCard: View {
    let league: League
    let left: Side
    let right: Side
    let comp: J
    var hitsErrors = true

    private func raw(_ s: Side) -> J {
        comp["competitors"].array.first { $0["team"]["id"].str == s.id } ?? J(nil)
    }

    private func he(_ s: Side) -> (String, String) {
        let c = raw(s)
        let ls = c["linescores"].array
        let h = c["hits"].string ?? String(ls.reduce(0) { $0 + ($1["hits"].int ?? 0) })
        let e = c["errors"].string ?? String(ls.reduce(0) { $0 + ($1["errors"].int ?? 0) })
        return (h, e)
    }

    private func label(_ i: Int) -> String {
        if league.family == .basketball && i >= 4 { return i == 4 ? "OT" : "OT\(i - 3)" }
        return "\(i + 1)"
    }

    var body: some View {
        let isBase = league.family == .baseball && hitsErrors
        let n = max(left.linescores.count, right.linescores.count, league.family == .baseball ? 9 : 4)
        if !left.linescores.isEmpty || !right.linescores.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                CardTitle(isBase ? "Line Score" : "Scoring")
                ViewThatFits(in: .horizontal) {
                    table(n: n, isBase: isBase, cell: isBase ? 22 : 30)
                    ScrollView(.horizontal, showsIndicators: false) { table(n: n, isBase: isBase, cell: 24, flexible: false) }
                }
            }
            .card()
        }
    }

    private func table(n: Int, isBase: Bool, cell: CGFloat, flexible: Bool = true) -> some View {
        let font: Font = isBase ? .footnote : .subheadline
        return VStack(spacing: 10) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 58, height: 1)
                ForEach(0..<n, id: \.self) { i in cellText(label(i), width: cell, flexible: flexible) }
                cellText(isBase ? "R" : "T", width: cell + 6, flexible: flexible)
                if isBase {
                    cellText("H", width: cell, flexible: flexible)
                    cellText("E", width: cell, flexible: flexible)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.secondary)
            ForEach([left, right], id: \.id) { s in
                let x = he(s)
                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        LogoView(url: s.logo, fallback: s.abbr, size: 20)
                        Text(s.abbr).fontWeight(.bold).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(width: 58, alignment: .leading)
                    ForEach(0..<n, id: \.self) { i in
                        cellText(i < s.linescores.count ? s.linescores[i] : "", width: cell, flexible: flexible)
                    }
                    cellText(s.score ?? "", width: cell + 6, flexible: flexible).fontWeight(.heavy)
                    if isBase {
                        cellText(x.0, width: cell, flexible: flexible)
                        cellText(x.1, width: cell, flexible: flexible)
                    }
                }
                .font(font)
                .monospacedDigit()
            }
        }
    }

    @ViewBuilder private func cellText(_ t: String, width: CGFloat, flexible: Bool) -> some View {
        if flexible {
            Text(t).lineLimit(1).frame(minWidth: width, maxWidth: .infinity)
        } else {
            Text(t).lineLimit(1).frame(width: width)
        }
    }
}

// MARK: - Team stats

private struct StatPick {
    let key: String
    let label: String
    var pct = false
}

private let statPicks: [Family: [StatPick]] = [
    .soccer: [
        StatPick(key: "possessionPct", label: "Possession", pct: true),
        StatPick(key: "totalShots", label: "Shots"),
        StatPick(key: "shotsOnTarget", label: "Shots on Target"),
        StatPick(key: "wonCorners", label: "Corners"),
        StatPick(key: "totalPasses", label: "Passes"),
        StatPick(key: "passPct", label: "Pass Accuracy", pct: true),
        StatPick(key: "totalCrosses", label: "Crosses"),
        StatPick(key: "totalTackles", label: "Tackles"),
        StatPick(key: "interceptions", label: "Interceptions"),
        StatPick(key: "totalClearance", label: "Clearances"),
        StatPick(key: "saves", label: "Saves"),
        StatPick(key: "foulsCommitted", label: "Fouls"),
        StatPick(key: "offsides", label: "Offsides"),
        StatPick(key: "yellowCards", label: "Yellow Cards"),
        StatPick(key: "redCards", label: "Red Cards"),
    ],
    .basketball: [
        StatPick(key: "fieldGoalPct", label: "Field Goal %", pct: true),
        StatPick(key: "threePointFieldGoalPct", label: "3-Point %", pct: true),
        StatPick(key: "freeThrowPct", label: "Free Throw %", pct: true),
        StatPick(key: "totalRebounds", label: "Rebounds"),
        StatPick(key: "offensiveRebounds", label: "Offensive Rebounds"),
        StatPick(key: "assists", label: "Assists"),
        StatPick(key: "steals", label: "Steals"),
        StatPick(key: "blocks", label: "Blocks"),
        StatPick(key: "turnovers", label: "Turnovers"),
        StatPick(key: "pointsInPaint", label: "Points in Paint"),
        StatPick(key: "fastBreakPoints", label: "Fast Break Points"),
        StatPick(key: "turnoverPoints", label: "Points off Turnovers"),
        StatPick(key: "largestLead", label: "Largest Lead"),
        StatPick(key: "fouls", label: "Fouls"),
    ],
    .baseball: [
        StatPick(key: "hits", label: "Hits"),
        StatPick(key: "homeRuns", label: "Home Runs"),
        StatPick(key: "RBIs", label: "RBIs"),
        StatPick(key: "walks", label: "Walks"),
        StatPick(key: "strikeouts", label: "Strikeouts"),
        StatPick(key: "stolenBases", label: "Stolen Bases"),
        StatPick(key: "leftOnBase", label: "Left on Base"),
    ],
]

private func teamStatMap(_ t: J) -> [String: String] {
    var m: [String: String] = [:]
    for s in t["statistics"].array {
        if s["stats"].exists {
            if s["name"].str == "batting" { for x in s["stats"].array { m[x["name"].str] = x["displayValue"].str } }
        } else {
            m[s["name"].str] = s["displayValue"].str
        }
    }
    return m
}

private struct TeamStatsCard: View {
    let league: League
    let summary: J
    let left: Side
    let right: Side

    var body: some View {
        let teams = summary["boxscore"]["teams"].array
        let lt = teams.first { $0["team"]["id"].str == left.id }
        let rt = teams.first { $0["team"]["id"].str == right.id }
        if let lt, let rt {
            TeamStatsBars(league: league, left: left, right: right, lm: teamStatMap(lt), rm: teamStatMap(rt))
        }
    }
}

struct TeamStatsBars: View {
    let league: League
    let left: Side
    let right: Side
    let lm: [String: String]
    let rm: [String: String]

    var body: some View {
        let extra: [StatPick] = league.provider == .bbl ? [StatPick(key: "efficiency", label: "Efficiency")] : []
        let picks = ((statPicks[league.family] ?? []) + extra).filter { lm[$0.key] != nil && rm[$0.key] != nil }
        let lc = Color.visibleTint(left.tintHex) ?? .white
        let rc0 = Color.visibleTint(right.tintHex) ?? Color(white: 0.6)
        let rc = left.tintHex == right.tintHex ? Color(white: 0.6) : rc0
        if !picks.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(left.abbr)
                    Spacer()
                    Text("TEAM STATS")
                    Spacer()
                    Text(right.abbr)
                }
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.secondary)
                ForEach(picks, id: \.key) { p in
                    StatBar(label: p.label, left: lm[p.key]!, right: rm[p.key]!, lc: lc, rc: rc, pct: p.pct)
                }
            }
            .card()
        }
    }
}

struct StatBar: View {
    let label: String
    let left: String
    let right: String
    let lc: Color
    let rc: Color
    var pct = false

    private func num(_ s: String) -> Double { Double(s.replacingOccurrences(of: "%", with: "")) ?? 0 }

    private func display(_ s: String, _ v: Double) -> String {
        guard pct else { return s }
        if v <= 1, v > 0, !s.contains("%"), num(left) <= 1, num(right) <= 1 { return "\(Int((v * 100).rounded()))%" }
        return s.contains("%") ? s : "\(s)%"
    }

    var body: some View {
        let a = num(left), b = num(right)
        let total = max(a + b, 0.0001)
        VStack(spacing: 6) {
            HStack {
                Text(display(left, a)).opacity(a >= b ? 1 : 0.6)
                Spacer()
                Text(label).font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary)
                Spacer()
                Text(display(right, b)).opacity(b >= a ? 1 : 0.6)
            }
            .font(.system(size: 15, weight: .bold))
            .monospacedDigit()
            GeometryReader { geo in
                let half = (geo.size.width - 4) / 2
                HStack(spacing: 4) {
                    HStack { Spacer(minLength: 0); Capsule().fill(a >= b ? lc : Color(white: 0.28)).frame(width: half * a / total * 2 > half ? half : half * a / total * 2) }
                        .frame(width: half)
                    HStack { Capsule().fill(b >= a ? rc : Color(white: 0.28)).frame(width: half * b / total * 2 > half ? half : half * b / total * 2); Spacer(minLength: 0) }
                        .frame(width: half)
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Box score

private struct BoxScoreCards: View {
    let league: League
    let summary: J
    let side: Side

    var body: some View {
        let p = summary["boxscore"]["players"].array.first { $0["team"]["id"].str == side.id }
        if let p {
            ForEach(Array(p["statistics"].array.enumerated()), id: \.offset) { _, grp in
                let athletes = grp["athletes"].array
                if !athletes.isEmpty {
                    BoxTable(
                        title: side.short + (grp["type"].string.map { " · \($0.capitalized)" } ?? ""),
                        logo: side.logo, abbr: side.abbr,
                        labels: grp["labels"].array.map(\.str),
                        rows: athletes.map { a in
                            let stats = a["stats"].array.map(\.str)
                            return BoxRow(
                                id: a["athlete"]["id"].str,
                                name: a["athlete"]["shortName"].string ?? a["athlete"]["displayName"].str,
                                sub: a["position"]["abbreviation"].str,
                                bench: a["starter"].bool == false,
                                stats: stats,
                                note: stats.isEmpty ? (a["reason"].string.flatMap { $0.isEmpty ? nil : $0 } ?? "DNP") : nil,
                                route: .player(leagueId: league.id, playerId: a["athlete"]["id"].str)
                            )
                        },
                        totals: grp["totals"].array.map(\.str)
                    )
                }
            }
        }
    }
}

struct BoxRow: Identifiable {
    let id: String
    let name: String
    let sub: String
    let bench: Bool
    let stats: [String]
    var note: String? = nil
    let route: Route?
}

/// Player stat table: names pinned on the left, stats scroll sideways.
struct BoxTable: View {
    let title: String
    let logo: URL?
    let abbr: String
    let labels: [String]
    let rows: [BoxRow]
    let totals: [String]

    private let rowHeight: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                LogoView(url: logo, fallback: abbr, size: 18)
                CardTitle(title)
            }
            HStack(alignment: .top, spacing: 0) {
                // Names column (tappable)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Player").font(.caption2.weight(.semibold)).foregroundStyle(Theme.secondary)
                        .frame(height: 24, alignment: .leading)
                    ForEach(rows) { r in
                        nameCell(r).frame(height: rowHeight, alignment: .leading)
                    }
                    if !totals.isEmpty {
                        Text("Team").font(.footnote.weight(.bold)).frame(height: rowHeight, alignment: .leading)
                    }
                }
                .frame(width: 128, alignment: .leading)
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .trailing, spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(Array(labels.enumerated()), id: \.offset) { cell($0.element) }
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.secondary)
                        .frame(height: 24)
                        ForEach(rows) { r in
                            HStack(spacing: 0) {
                                if let note = r.note {
                                    Text(note).foregroundStyle(Theme.secondary).frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    ForEach(Array(r.stats.enumerated()), id: \.offset) { cell($0.element) }
                                }
                            }
                            .font(.footnote)
                            .frame(height: rowHeight)
                        }
                        if !totals.isEmpty {
                            HStack(spacing: 0) {
                                ForEach(Array(totals.enumerated()), id: \.offset) { cell($0.element) }
                            }
                            .font(.footnote.weight(.bold))
                            .frame(height: rowHeight)
                        }
                    }
                    .monospacedDigit()
                }
            }
        }
        .card()
    }

    private func cell(_ t: String) -> some View {
        Text(t).lineLimit(1).frame(minWidth: 44, alignment: .trailing).padding(.horizontal, 2)
    }

    @ViewBuilder private func nameCell(_ r: BoxRow) -> some View {
        let label = HStack(spacing: 4) {
            Text(r.name).lineLimit(1).minimumScaleFactor(0.8)
            Text(r.sub).font(.caption2).foregroundStyle(Theme.secondary)
        }
        .font(.footnote)
        .foregroundStyle(r.bench ? Theme.secondary : .white)
        if let route = r.route {
            NavigationLink(value: route) { label }.buttonStyle(.plain)
        } else {
            label
        }
    }
}

// MARK: - Leaders / decisions

private struct GameLeadersCard: View {
    let league: League
    let summary: J
    let left: Side
    let right: Side

    var body: some View {
        let all = summary["leaders"].array
        let l = all.first { $0["team"]["id"].str == left.id }
        let r = all.first { $0["team"]["id"].str == right.id }
        if let l, let r, !l["leaders"].array.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                CardTitle("Game Leaders")
                ForEach(0..<min(4, l["leaders"].array.count), id: \.self) { i in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(l["leaders"][i]["displayName"].str).font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
                        HStack {
                            leader(l["leaders"][i]["leaders"][0], trailing: false)
                            Spacer()
                            leader(r["leaders"][i]["leaders"][0], trailing: true)
                        }
                    }
                }
            }
            .card()
        }
    }

    @ViewBuilder private func leader(_ x: J, trailing: Bool) -> some View {
        if x.exists {
            NavigationLink(value: Route.player(leagueId: league.id, playerId: x["athlete"]["id"].str)) {
                HStack(spacing: 8) {
                    if !trailing { headshot(x) }
                    VStack(alignment: trailing ? .trailing : .leading, spacing: 1) {
                        Text(x["athlete"]["shortName"].str).font(.subheadline.weight(.bold))
                        Text(x["displayValue"].str).font(.caption).foregroundStyle(Theme.secondary)
                    }
                    if trailing { headshot(x) }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func headshot(_ x: J) -> some View {
        AsyncImage(url: x["athlete"]["headshot"]["href"].url) { img in img.resizable().scaledToFill() } placeholder: { Theme.card2 }
            .frame(width: 36, height: 36)
            .background(Theme.card2)
            .clipShape(Circle())
    }
}

private struct DecisionsCard: View {
    let league: League
    let comp: J

    var body: some View {
        let fa = comp["status"]["featuredAthletes"].array
        if !fa.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle("Decisions")
                ForEach(Array(fa.enumerated()), id: \.offset) { _, f in
                    NavigationLink(value: Route.player(leagueId: league.id, playerId: f["athlete"]["id"].str)) {
                    HStack(spacing: 12) {
                        AsyncImage(url: f["athlete"]["headshot"]["href"].url) { $0.resizable().scaledToFill() } placeholder: { Theme.card2 }
                            .frame(width: 38, height: 38).clipShape(Circle())
                        VStack(alignment: .leading) {
                            Text(f["athlete"]["displayName"].str).font(.subheadline.weight(.bold))
                            Text("\(f["displayName"].str) · \(f["team"]["name"].str)").font(.caption).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        Text(f["record"].str).font(.subheadline.weight(.bold))
                    }
                    }
                    .buttonStyle(.plain)
                }
            }
            .card()
        }
    }
}

// MARK: - Soccer

private struct TimelineCard: View {
    let league: League
    let summary: J
    let homeId: String

    var body: some View {
        let events = summary["keyEvents"].array.filter { e in
            let t = e["type"]["text"].str.lowercased()
            return e["scoringPlay"].bool == true || t.contains("card") || t.contains("substitution")
        }
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                CardTitle("Match Events")
                ForEach(Array(events.enumerated()), id: \.offset) { i, e in
                    if i > 0 { Divider().overlay(Theme.separator) }
                    if let id = e["participants"][0]["athlete"]["id"].string {
                        NavigationLink(value: Route.player(leagueId: league.id, playerId: id)) { row(e) }
                            .buttonStyle(.plain)
                    } else {
                        row(e)
                    }
                }
            }
            .card()
        }
    }

    private func row(_ e: J) -> some View {
        let isHome = e["team"]["id"].str == homeId
        let t = e["type"]["text"].str.lowercased()
        let who = e["participants"].array.map { $0["athlete"]["displayName"].str }
        var icon = ""
        var what = e["type"]["text"].str
        if e["scoringPlay"].bool == true {
            icon = "⚽"
            what = t.contains("own") ? "Own goal" : t.contains("penalty") ? "Penalty" : (who.count > 1 ? "Assist: \(who[1])" : "Goal")
        } else if t.contains("yellow") {
            icon = "🟨"
        } else if t.contains("red") {
            icon = "🟥"
        } else if t.contains("substitution") {
            icon = "⇄"
            what = who.count > 1 ? "Off: \(who[1])" : "Substitution"
        }
        let content = VStack(alignment: isHome ? .trailing : .leading, spacing: 1) {
            Text(isHome ? "\(who.first ?? "") \(icon)" : "\(icon) \(who.first ?? "")").font(.subheadline.weight(.semibold))
            Text(what).font(.caption).foregroundStyle(Theme.secondary)
        }
        return HStack {
            Group { if isHome { content } else { Color.clear } }.frame(maxWidth: .infinity, alignment: .trailing)
            Text(e["clock"]["displayValue"].str).font(.footnote.weight(.bold)).foregroundStyle(Theme.secondary).frame(width: 44)
            Group { if !isHome { content } else { Color.clear } }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
    }
}

private struct LineupsCard: View {
    let league: League
    let summary: J
    let left: Side
    let right: Side

    var body: some View {
        let rosters = summary["rosters"].array
        let l = rosters.first { $0["team"]["id"].str == left.id }
        let r = rosters.first { $0["team"]["id"].str == right.id }
        if let l, let r, !l["roster"].array.isEmpty, !r["roster"].array.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle("Lineups")
                HStack(alignment: .top, spacing: 14) {
                    column(l, left)
                    column(r, right)
                }
            }
            .card()
        }
    }

    private func column(_ r: J, _ s: Side) -> some View {
        let roster = r["roster"].array
        let starters = roster.filter { $0["starter"].bool == true }.sorted { ($0["formationPlace"].int ?? 0) < ($1["formationPlace"].int ?? 0) }
        let subs = roster.filter { $0["starter"].bool != true && $0["subbedIn"].bool == true }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                LogoView(url: s.logo, fallback: s.abbr, size: 18)
                Text(s.short).font(.subheadline.weight(.bold)).lineLimit(1)
            }
            Text(r["formation"].str).font(.caption).foregroundStyle(Theme.secondary).padding(.bottom, 6)
            ForEach(Array((starters + subs).enumerated()), id: \.offset) { _, p in
                let sub = p["starter"].bool != true
                NavigationLink(value: Route.player(leagueId: league.id, playerId: p["athlete"]["id"].str)) {
                HStack(spacing: 6) {
                    Text(p["jersey"].str).foregroundStyle(Theme.secondary).frame(width: 20, alignment: .trailing)
                    Text(p["athlete"]["displayName"].str + (p["subbedOut"].bool == true ? " ↓" : "") + (sub ? " ↑" : ""))
                        .lineLimit(1)
                        .foregroundStyle(sub ? Theme.secondary : .white)
                    Spacer(minLength: 2)
                    Text(p["position"]["abbreviation"].str).font(.caption2).foregroundStyle(Theme.secondary)
                }
                .font(.caption)
                .padding(.vertical, 5)
                .overlay(alignment: .top) { Divider().overlay(Theme.separator) }
                .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GameInfoCard: View {
    let summary: J

    var body: some View {
        let gi = summary["gameInfo"]
        var rows: [(String, String)] = []
        if let v = gi["venue"]["fullName"].string {
            let city = gi["venue"]["address"]["city"].string.map { ", \($0)" } ?? ""
            rows.append(("Venue", v + city))
        }
        if let a = gi["attendance"].int, a > 0 { rows.append(("Attendance", a.formatted())) }
        let refs = gi["officials"].array.compactMap { $0["displayName"].string ?? $0["fullName"].string }
        if !refs.isEmpty { rows.append(("Officials", refs.prefix(3).joined(separator: ", "))) }
        return Group {
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    CardTitle("Game Info")
                    ForEach(rows, id: \.0) { row in
                        HStack(alignment: .top) {
                            Text(row.0).foregroundStyle(Theme.secondary)
                            Spacer()
                            Text(row.1).multilineTextAlignment(.trailing)
                        }
                        .font(.subheadline)
                        .padding(.vertical, 7)
                        .overlay(alignment: .top) { Divider().overlay(Theme.separator) }
                    }
                }
                .card()
            }
        }
    }
}
