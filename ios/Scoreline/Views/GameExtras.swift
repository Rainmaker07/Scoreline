import Charts
import SwiftUI

// MARK: - Preview (before the game)

/// Pre-game preview from ESPN's summary (and FotMob for football): matchup predictor,
/// odds, recent form, season series / head-to-head, injuries.
struct PreviewSection: View {
    let league: League
    let summary: J
    let left: Side
    let right: Side
    let game: Game

    var body: some View {
        VStack(spacing: 14) {
            PredictorCard(summary: summary, left: left, right: right)
            OddsCard(summary: summary, left: left, right: right)
            FormCard(leagueId: league.id, summary: summary, left: left, right: right)
            SeriesCard(leagueId: league.id, summary: summary)
            // FotMob's all-time head-to-head when ESPN has no recent meetings.
            if league.family == .soccer, summary["seasonseries"].array.first?["events"].array.isEmpty ?? true {
                Loader(id: "fm-h2h-\(game.id)", load: { await FotMobMatch.load(game) }) { data in
                    if let data { HeadToHeadCard(data: data) }
                }
            }
            InjuriesCard(summary: summary, left: left, right: right)
        }
    }
}

private struct PredictorCard: View {
    let summary: J
    let left: Side
    let right: Side

    var body: some View {
        let p = summary["predictor"]
        let pct: (String) -> Double? = { id in
            for side in [p["homeTeam"], p["awayTeam"]] where side["id"].str == id {
                return Double(side["gameProjection"].str)
            }
            return nil
        }
        if let l = pct(left.id), let r = pct(right.id) {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle("Matchup predictor")
                HStack {
                    Text(String(format: "%.0f%%", l)).font(.title3.weight(.heavy)).monospacedDigit()
                    Spacer()
                    Text(String(format: "%.0f%%", r)).font(.title3.weight(.heavy)).monospacedDigit()
                }
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        Rectangle().fill(Color.visibleTint(left.color) ?? .blue)
                            .frame(width: max(4, geo.size.width * l / max(l + r, 1) - 1))
                        Rectangle().fill(Color.visibleTint(right.color) ?? .red)
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 8)
                HStack {
                    Text(left.short); Spacer(); Text(right.short)
                }
                .font(.caption).foregroundStyle(Theme.secondary)
                Text("ESPN Basketball Power Index / Football Power Index win chance.")
                    .font(.caption2).foregroundStyle(Theme.tertiary)
            }
            .card()
        }
    }
}

/// Betting odds in decimal format (European style): moneyline as home · draw · away,
/// over/under with both prices, and the spread for US sports.
private struct OddsCard: View {
    let summary: J
    let left: Side
    let right: Side

    static func decimal(_ american: Double?) -> String? {
        guard let a = american, a != 0 else { return nil }
        let d = a > 0 ? 1 + a / 100 : 1 + 100 / abs(a)
        return String(format: "%.2f", d)
    }

    var body: some View {
        let o = summary["pickcenter"].array.first ?? summary["odds"].array.first ?? J(nil)
        let homeId = summary["header"]["competitions"][0]["competitors"].array.first { $0["homeAway"].str == "home" }?["id"].str
        func side(_ s: Side) -> J { s.id == homeId ? o["homeTeamOdds"] : o["awayTeamOdds"] }
        let l = Self.decimal(side(left)["moneyLine"].double)
        let r = Self.decimal(side(right)["moneyLine"].double)
        let draw = Self.decimal(o["drawOdds"]["moneyLine"].double)
        if o.exists, l != nil || r != nil {
            VStack(alignment: .leading, spacing: 12) {
                CardTitle("Odds")
                HStack(spacing: 8) {
                    price(left.abbr, l, logo: left.logo)
                    if let draw { price("Draw", draw, logo: nil) }
                    price(right.abbr, r, logo: right.logo)
                }
                if let ou = o["overUnder"].double {
                    row("Over/under \(String(format: "%g", ou))",
                        [Self.decimal(o["overOdds"].double).map { "Over \($0)" }, Self.decimal(o["underOdds"].double).map { "Under \($0)" }]
                            .compactMap { $0 }.joined(separator: " · "))
                }
                if draw == nil, let spread = o["details"].string, !spread.isEmpty {
                    let sp = Self.decimal(side(left)["spreadOdds"].double)
                    row("Spread", spread + (sp.map { " · \($0)" } ?? ""))
                }
                if let prov = o["provider"]["name"].string {
                    Text("Decimal odds · \(prov)").font(.caption2).foregroundStyle(Theme.tertiary)
                }
            }
            .card()
        }
    }

    private func price(_ label: String, _ value: String?, logo: URL?) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                if let logo { LogoView(url: logo, fallback: label, size: 16) }
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
            }
            Text(value ?? "–").font(.title3.weight(.heavy)).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.subheadline)
    }
}

/// A stand-in game for links: the game page loads everything from the event id.
func stubGame(id: String, leagueId: String, date: Date?) -> Game {
    let blank = ESPN.side(J(nil))
    return Game(id: id, leagueId: leagueId, date: date ?? Date(), state: .post, statusText: "Final",
                home: blank, away: blank, note: nil, broadcast: nil, scorers: [])
}

private struct FormCard: View {
    let leagueId: String
    let summary: J
    let left: Side
    let right: Side

    var body: some View {
        let teams = summary["lastFiveGames"].array
        if !teams.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle("Recent form")
                ForEach([left, right], id: \.id) { side in
                    if let t = teams.first(where: { $0["team"]["id"].str == side.id }) {
                        HStack(spacing: 8) {
                            LogoView(url: side.logo, fallback: side.abbr, size: 22)
                            Text(side.abbr).font(.subheadline.weight(.bold)).frame(width: 44, alignment: .leading)
                            ForEach(Array(t["events"].array.prefix(5).enumerated()), id: \.offset) { _, e in
                                let r = e["gameResult"].str
                                NavigationLink(value: Route.game(stubGame(id: e["id"].str, leagueId: leagueId,
                                                                          date: e["gameDate"].string.flatMap(ESPNDate.parse)))) {
                                    VStack(spacing: 2) {
                                        Text(r).font(.caption.weight(.heavy)).foregroundStyle(.white)
                                            .frame(width: 24, height: 22)
                                            .background(r == "W" ? Color(hex: "30d158") : r == "L" ? Color(hex: "ff453a") : Color(white: 0.45),
                                                        in: RoundedRectangle(cornerRadius: 5))
                                        LogoView(url: e["opponent"]["logo"].url, fallback: e["opponent"]["abbreviation"].str, size: 14)
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(e["id"].str.isEmpty)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .card()
        }
    }
}

/// Season series / head-to-head summary and the last meetings (each opens the game).
private struct SeriesCard: View {
    let leagueId: String
    let summary: J
    var body: some View {
        let s = summary["seasonseries"].array.first ?? J(nil)
        let events = Array(s["events"].array.filter { $0["statusType"]["completed"].bool != false }
            .sorted { ($0["date"].str) > ($1["date"].str) }.prefix(5))
        if s.exists, s["summary"].string != nil || !events.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                CardTitle(s["seriesLabel"].string ?? "Head-to-head")
                if let text = s["summary"].string {
                    Text(text).font(.subheadline.weight(.semibold)).padding(.bottom, 8)
                }
                ForEach(Array(events.enumerated()), id: \.offset) { _, e in
                    Divider().overlay(Theme.separator)
                    meeting(e)
                }
            }
            .card()
        }
    }

    private func meeting(_ e: J) -> some View {
        let cs = e["competitors"].array
        let home = cs.first { $0["homeAway"].str == "home" } ?? J(nil)
        let away = cs.first { $0["homeAway"].str == "away" } ?? J(nil)
        let date = e["date"].string.flatMap(ESPNDate.parse)
        func team(_ c: J, trailing: Bool) -> some View {
            HStack(spacing: 6) {
                if !trailing { LogoView(url: c["team"]["logo"].url, fallback: c["team"]["abbreviation"].str, size: 18) }
                Text(c["team"]["abbreviation"].str).font(.footnote.weight(c["winner"].bool == true ? .heavy : .regular))
                    .foregroundStyle(c["winner"].bool == false && (home["winner"].bool == true || away["winner"].bool == true) ? Theme.secondary : .white)
                if trailing { LogoView(url: c["team"]["logo"].url, fallback: c["team"]["abbreviation"].str, size: 18) }
            }
        }
        return NavigationLink(value: Route.game(stubGame(id: e["id"].str, leagueId: leagueId, date: date))) {
            HStack(spacing: 8) {
                Text(date.map { Fmt.dateYear($0) } ?? "").font(.caption).foregroundStyle(Theme.secondary)
                    .frame(width: 86, alignment: .leading)
                team(home, trailing: false).frame(maxWidth: .infinity, alignment: .trailing)
                Text("\(home["score"].str)–\(away["score"].str)").font(.subheadline.weight(.bold)).monospacedDigit()
                    .frame(width: 46)
                team(away, trailing: true).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.tertiary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct InjuriesCard: View {
    let summary: J
    let left: Side
    let right: Side

    var body: some View {
        let all = summary["injuries"].array
        let rows: [(Side, J)] = [left, right].flatMap { side in
            (all.first { $0["team"]["id"].str == side.id }?["injuries"].array ?? []).prefix(6).map { (side, $0) }
        }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                CardTitle("Injuries")
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                    if i > 0 { Divider().overlay(Theme.separator) }
                    HStack(spacing: 10) {
                        LogoView(url: r.0.logo, fallback: r.0.abbr, size: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.1["athlete"]["displayName"].str).font(.subheadline.weight(.semibold))
                            if let t = r.1["details"]["type"].string ?? r.1["type"]["description"].string {
                                Text(t).font(.caption).foregroundStyle(Theme.secondary)
                            }
                        }
                        Spacer()
                        Text(r.1["status"].str).font(.caption.weight(.bold))
                            .foregroundStyle(r.1["status"].str.lowercased().contains("out") ? Color(hex: "ff453a") : Color(hex: "ff9f0a"))
                    }
                    .padding(.vertical, 8)
                }
            }
            .card()
        }
    }
}

private struct HeadToHeadCard: View {
    let data: FotMobMatch.Data
    var body: some View {
        if let h = data.h2h, h.home + h.draws + h.away > 0 {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle("Head to head")
                HStack {
                    stat("\(h.home)", data.homeName)
                    stat("\(h.draws)", "Draws")
                    stat("\(h.away)", data.awayName)
                }
                ForEach(Array(data.h2hMatches.enumerated()), id: \.offset) { _, m in
                    HStack {
                        Text(m.date.map { Fmt.dateYear($0) } ?? "").font(.caption).foregroundStyle(Theme.secondary)
                            .frame(width: 92, alignment: .leading)
                        Text(m.home).lineLimit(1).frame(maxWidth: .infinity, alignment: .trailing)
                        Text(m.score.replacingOccurrences(of: " - ", with: ":")).font(.subheadline.weight(.bold)).monospacedDigit()
                            .frame(width: 44)
                        Text(m.away).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.footnote)
                }
                Text("FotMob").font(.caption2).foregroundStyle(Theme.tertiary)
            }
            .card()
        }
    }

    private func stat(_ v: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.title2.weight(.heavy)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - FotMob match data (football)

struct FotMobStatsSection: View {
    let game: Game
    let homeColor: String?
    let awayColor: String?

    @State private var data: FotMobMatch.Data?
    @State private var loading = true

    var body: some View {
        Group {
            if let data {
                VStack(spacing: 14) {
                    if let xg = data.xg { XGCard(data: data, xg: xg, homeColor: homeColor, awayColor: awayColor) }
                    if data.momentum.count > 5 { MomentumCard(data: data, homeColor: homeColor, awayColor: awayColor) }
                    if !data.shots.isEmpty { ShotMapCard(data: data, homeColor: homeColor, awayColor: awayColor) }
                    if !data.ratings.isEmpty { RatingsCard(data: data) }
                    ForEach(Array(data.groups.dropFirst().enumerated()), id: \.offset) { _, g in
                        StatGroupCard(title: g.title, rows: g.rows, homeColor: homeColor, awayColor: awayColor)
                    }
                    Text("Advanced stats: FotMob").font(.caption2).foregroundStyle(Theme.tertiary)
                }
            } else if loading {
                ProgressView().tint(.white).frame(maxWidth: .infinity).padding(20)
            } else {
                Text("Expected goals and shot map aren’t available for this match.")
                    .font(.caption).foregroundStyle(Theme.tertiary).frame(maxWidth: .infinity)
            }
        }
        .task(id: game.id) {
            while !Task.isCancelled {
                let d = await FotMobMatch.load(game)
                if Task.isCancelled { return }
                if let d { data = d }
                loading = false
                guard game.state == .live else { return }
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }
}

private struct XGCard: View {
    let data: FotMobMatch.Data
    let xg: (home: Double, away: Double)
    let homeColor: String?
    let awayColor: String?
    var body: some View {
        VStack(spacing: 8) {
            CardTitle("Expected goals (xG)")
            HStack {
                Text(String(format: "%.2f", xg.home)).font(.system(size: 30, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(Color.visibleTint(homeColor) ?? .white)
                Spacer()
                Text(String(format: "%.2f", xg.away)).font(.system(size: 30, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(Color.visibleTint(awayColor) ?? .white)
            }
            HStack { Text(data.homeName); Spacer(); Text(data.awayName) }
                .font(.caption).foregroundStyle(Theme.secondary)
            if let p = data.playerOfTheMatch {
                Label("Player of the match: \(p)", systemImage: "star.fill")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.yellow)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .card()
    }
}

/// Pressure by minute. Drag along it to see the minute, the score then and who was
/// on top; goals, cards and big chances are marked above the bars and listed below.
private struct MomentumCard: View {
    let data: FotMobMatch.Data
    let homeColor: String?
    let awayColor: String?
    @State private var minute: Double?

    private var keyEvents: [FotMobMatch.Event] { data.events.filter { $0.kind != .yellow } }

    private func score(at m: Double) -> (Int, Int) {
        var sc = (0, 0)
        for e in data.events where Double(e.minute) <= m {
            if let s = e.score { sc = s }
        }
        return sc
    }

    private func symbol(_ k: FotMobMatch.Event.Kind) -> String {
        switch k {
        case .goal, .penalty: return "⚽️"
        case .ownGoal: return "⚽️"
        case .red: return "🟥"
        case .yellow: return "🟨"
        case .bigChance: return "💥"
        }
    }

    private func label(_ e: FotMobMatch.Event) -> String {
        switch e.kind {
        case .goal: return "Goal"
        case .penalty: return "Penalty goal"
        case .ownGoal: return "Own goal"
        case .red: return "Red card"
        case .yellow: return "Yellow card"
        case .bigChance: return "Big chance"
        }
    }

    var body: some View {
        let hc = Color.visibleTint(homeColor) ?? .blue
        let ac = Color.visibleTint(awayColor) ?? .red
        let last = data.momentum.last?.minute ?? 90
        let shownMinute = minute ?? last
        let point = data.momentum.min { abs($0.minute - shownMinute) < abs($1.minute - shownMinute) }
        let sc = score(at: shownMinute)
        let maxMinute = max(90, last)
        VStack(alignment: .leading, spacing: 8) {
            CardTitle("Momentum")
            HStack {
                Text("\(Int(shownMinute))'").font(.subheadline.weight(.bold)).monospacedDigit()
                Text("\(sc.0)–\(sc.1)").font(.subheadline.weight(.bold)).monospacedDigit()
                Spacer()
                if let v = point?.value, abs(v) >= 5 {
                    Text("\(v >= 0 ? data.homeName : data.awayName) on top")
                        .font(.caption.weight(.semibold)).foregroundStyle(v >= 0 ? hc : ac)
                } else {
                    Text("Even").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
                }
            }
            Chart {
                ForEach(Array(data.momentum.enumerated()), id: \.offset) { _, p in
                    BarMark(x: .value("Minute", p.minute), y: .value("Pressure", p.value), width: .fixed(3))
                        .foregroundStyle(p.value >= 0 ? hc : ac)
                }
                RuleMark(x: .value("Half", 45.0)).foregroundStyle(Theme.tertiary)
                ForEach(Array(keyEvents.enumerated()), id: \.offset) { _, e in
                    PointMark(x: .value("Minute", Double(e.minute)), y: .value("Pressure", e.home ? 118.0 : -118.0))
                        .symbolSize(0)
                        .annotation(position: .overlay) { Text(symbol(e.kind)).font(.system(size: 11)) }
                }
                if let m = minute {
                    RuleMark(x: .value("Selected", m)).foregroundStyle(Color.white.opacity(0.7))
                }
            }
            .chartYScale(domain: -130...130)
            .chartXScale(domain: 0...maxMinute)
            .chartYAxis(.hidden)
            .chartXAxis { AxisMarks(values: [0.0, 45.0, 90.0]) { v in AxisValueLabel { Text("\(Int(v.as(Double.self) ?? 0))'") } } }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { v in
                                    guard let plot = proxy.plotFrame else { return }
                                    if let m: Double = proxy.value(atX: v.location.x - geo[plot].origin.x) {
                                        minute = min(max(0, m), maxMinute)
                                    }
                                }
                                .onEnded { _ in minute = nil }
                        )
                }
            }
            .frame(height: 120)
            HStack { Text(data.homeName).foregroundStyle(hc); Spacer(); Text(data.awayName).foregroundStyle(ac) }
                .font(.caption.weight(.semibold))
            if !keyEvents.isEmpty {
                Divider().overlay(Theme.separator).padding(.vertical, 4)
                Text("KEY MOMENTS").font(.caption.weight(.bold)).foregroundStyle(Theme.secondary)
                ForEach(Array(keyEvents.enumerated()), id: \.offset) { _, e in
                    Button {
                        minute = minute == Double(e.minute) ? nil : Double(e.minute)
                    } label: {
                        HStack(spacing: 10) {
                            Text("\(e.minute)'").font(.caption.weight(.bold)).monospacedDigit()
                                .foregroundStyle(Theme.secondary).frame(width: 32, alignment: .leading)
                            Text(symbol(e.kind)).font(.caption)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(e.player).font(.footnote.weight(.semibold))
                                Text("\(label(e)) · \(e.home ? data.homeName : data.awayName)")
                                    .font(.caption).foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                            if let s = e.score {
                                Text("\(s.0)–\(s.1)").font(.footnote.weight(.bold)).monospacedDigit()
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Drag along the chart to follow the match.").font(.caption2).foregroundStyle(Theme.tertiary)
        }
        .card()
    }
}

/// Both teams' shots on one pitch: home attacks right, away left. Dot size = xG, filled = goal.
private struct ShotMapCard: View {
    let data: FotMobMatch.Data
    let homeColor: String?
    let awayColor: String?

    var body: some View {
        let hc = Color.visibleTint(homeColor) ?? .blue
        let ac = Color.visibleTint(awayColor) ?? .red
        VStack(alignment: .leading, spacing: 8) {
            CardTitle("Shot map")
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color(hex: "256b29"))
                    Group {
                        Rectangle().stroke(.white.opacity(0.45), lineWidth: 1).padding(4)
                        Rectangle().fill(.white.opacity(0.45)).frame(width: 1)
                        Circle().stroke(.white.opacity(0.45), lineWidth: 1).frame(width: h * 0.27)
                        Rectangle().stroke(.white.opacity(0.45), lineWidth: 1)
                            .frame(width: w * 0.157, height: h * 0.59).position(x: 4 + w * 0.0785, y: h / 2)
                        Rectangle().stroke(.white.opacity(0.45), lineWidth: 1)
                            .frame(width: w * 0.157, height: h * 0.59).position(x: w - 4 - w * 0.0785, y: h / 2)
                    }
                    ForEach(Array(data.shots.enumerated()), id: \.offset) { _, s in
                        // FotMob: x 0...105 towards the opponent's goal, y 0...68.
                        let x = s.home ? s.x / 105 * w : (1 - s.x / 105) * w
                        let y = s.home ? s.y / 68 * h : (1 - s.y / 68) * h
                        let d = 6 + CGFloat(min(s.xg, 0.8)) * 26
                        let c = s.home ? hc : ac
                        Circle()
                            .fill(s.isGoal ? c : c.opacity(s.onTarget ? 0.45 : 0.15))
                            .overlay(Circle().stroke(s.isGoal ? Color.white : c, lineWidth: s.isGoal ? 1.5 : 1))
                            .frame(width: d, height: d)
                            .position(x: x, y: y)
                    }
                }
            }
            .aspectRatio(105.0 / 68.0, contentMode: .fit)
            HStack(spacing: 12) {
                legend(hc, data.homeName)
                legend(ac, data.awayName)
                Spacer()
                Text("Filled = goal · size = xG").font(.caption2).foregroundStyle(Theme.secondary)
            }
        }
        .card()
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) { Circle().fill(c).frame(width: 8, height: 8); Text(t).lineLimit(1) }
            .font(.caption.weight(.semibold))
    }
}

private struct RatingsCard: View {
    let data: FotMobMatch.Data
    @State private var showAll = false

    var body: some View {
        let list = showAll ? data.ratings : Array(data.ratings.prefix(8))
        VStack(alignment: .leading, spacing: 0) {
            CardTitle("Player ratings")
            ForEach(Array(list.enumerated()), id: \.offset) { i, r in
                if i > 0 { Divider().overlay(Theme.separator) }
                HStack(spacing: 10) {
                    Text(String(format: "%.1f", r.rating))
                        .font(.subheadline.weight(.heavy)).monospacedDigit().foregroundStyle(.white)
                        .frame(width: 40, height: 24)
                        .background(Self.color(r.rating), in: RoundedRectangle(cornerRadius: 6))
                    Text(r.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer()
                    Text(r.home ? data.homeName : data.awayName).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                .padding(.vertical, 7)
            }
            if data.ratings.count > 8 {
                Button(showAll ? "Show less" : "All \(data.ratings.count) players") { withAnimation { showAll.toggle() } }
                    .font(.footnote.weight(.semibold)).padding(.top, 8)
            }
        }
        .card()
    }

    static func color(_ r: Double) -> Color {
        r >= 8 ? Color(hex: "1e8bff") : r >= 7 ? Color(hex: "30a14e") : r >= 6 ? Color(hex: "c9a227") : Color(hex: "d9534f")
    }
}

private struct StatGroupCard: View {
    let title: String
    let rows: [FotMobMatch.StatRow]
    let homeColor: String?
    let awayColor: String?

    var body: some View {
        let hc = Color.visibleTint(homeColor) ?? .blue
        let ac = Color.visibleTint(awayColor) ?? .red
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(title)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                VStack(spacing: 4) {
                    HStack {
                        Text(r.home).font(.subheadline.weight(.bold)).monospacedDigit()
                        Spacer()
                        Text(r.title).font(.caption).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                        Spacer()
                        Text(r.away).font(.subheadline.weight(.bold)).monospacedDigit()
                    }
                    if let h = r.homeValue, let a = r.awayValue, h + a > 0 {
                        GeometryReader { geo in
                            HStack(spacing: 4) {
                                Capsule().fill(h >= a ? hc : Theme.tertiary)
                                    .frame(width: max(3, (geo.size.width - 4) * h / (h + a)))
                                Capsule().fill(a >= h ? ac : Theme.tertiary)
                            }
                        }
                        .frame(height: 4)
                    }
                }
            }
        }
        .card()
    }
}
