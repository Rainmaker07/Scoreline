import Charts
import SwiftUI

// MARK: - Plays, win probability and key moments (NBA, MLB)

/// One play, parsed once from ESPN's JSON (filtering and grouping then stay cheap).
struct PlayItem: Identifiable, Hashable {
    let id: String
    let period: Int
    let periodName: String     // "1st Quarter", "Top 3rd"
    let periodShort: String    // "Q1", "OT", "T3"
    let clock: String
    let text: String
    let scoring: Bool
    let teamId: String
    let away: Int
    let home: Int
    /// Groups halves of an inning separately in baseball ("Top 3rd" vs "Bottom 3rd").
    let groupKey: String
}

/// A point on the win probability line (for the away team, which is on the left).
struct WinPoint: Identifiable {
    let id: Int
    let away: Double
    let play: PlayItem?
}

struct KeyMoment: Identifiable {
    enum Kind { case run, turnaround, play }
    var id: Int { index }
    let index: Int              // point where the swing starts (its first play)
    var endIndex: Int? = nil    // where a run ends
    let change: Double          // change of the away team's chance, in points
    let play: PlayItem
    var endPlay: PlayItem? = nil
    var kind: Kind = .play
}

enum KeyMoments {
    /// Swings in the win probability: runs of at least `minSwing` points (a reversal of that
    /// size ends a run), lead changes (crossing 50 % inside a run), and big single plays.
    static func find(_ pts: [WinPoint], awayId: String, homeId: String, minSwing: Double = 10, limit: Int = 5) -> [KeyMoment] {
        guard pts.count > 2 else { return [] }
        // Zigzag pivots: a trend ends when the line reverses by at least minSwing.
        var pivots: [Int] = []
        var dir = 0     // +1 up, -1 down, 0 not yet known
        var lo = 0, hi = 0, ext = 0
        for i in 1..<pts.count {
            let v = pts[i].away
            switch dir {
            case 0:
                if v < pts[lo].away { lo = i }
                if v > pts[hi].away { hi = i }
                if pts[hi].away - pts[lo].away >= minSwing {
                    if hi > lo { pivots = [lo]; dir = 1; ext = hi } else { pivots = [hi]; dir = -1; ext = lo }
                }
            case 1:
                if v > pts[ext].away { ext = i }
                else if pts[ext].away - v >= minSwing { pivots.append(ext); dir = -1; ext = i }
            default:
                if v < pts[ext].away { ext = i }
                else if v - pts[ext].away >= minSwing { pivots.append(ext); dir = 1; ext = i }
            }
        }
        if dir != 0 { pivots.append(ext) }
        var out: [KeyMoment] = []
        for k in stride(from: 1, to: pivots.count, by: 1) {
            let a = pivots[k - 1], b = pivots[k]
            let change = pts[b].away - pts[a].away
            guard abs(change) >= minSwing else { continue }
            // The run starts with the first play after the low / high point.
            guard b > a else { continue }
            // The run starts with the gaining team's first score (else its first play that helped).
            let gainer = change > 0 ? awayId : homeId
            let range = Array(a + 1...b)
            let start = range.first(where: { pts[$0].play?.scoring == true && pts[$0].play?.teamId == gainer })
                ?? range.first(where: { pts[$0].play?.teamId == gainer && (pts[$0].away - pts[$0 - 1].away) * change > 0 })
                ?? range.first(where: { pts[$0].play != nil })
            guard let start, let play = pts[start].play else { continue }
            let crossed = (pts[a].away - 50) * (pts[b].away - 50) < 0
            out.append(KeyMoment(index: start, endIndex: b, change: change, play: play, endPlay: pts[b].play,
                                 kind: crossed ? .turnaround : .run))
        }
        // Big single plays not already inside a listed run.
        for i in 1..<pts.count {
            let d = pts[i].away - pts[i - 1].away
            guard abs(d) >= 8, let play = pts[i].play,
                  !out.contains(where: { $0.index <= i && i <= ($0.endIndex ?? $0.index) }) else { continue }
            out.append(KeyMoment(index: i, change: d, play: play))
        }
        // Lead changes first among equals, then size.
        let ranked = out.sorted {
            let wa = abs($0.change) + ($0.kind == .turnaround ? 10 : 0)
            let wb = abs($1.change) + ($1.kind == .turnaround ? 10 : 0)
            return wa > wb
        }
        return Array(ranked.prefix(limit)).sorted { $0.index < $1.index }
    }
}

enum PlayData {
    static func isBaseball(_ league: League) -> Bool { league.family == .baseball }

    /// MLB lists every pitch: keep at-bat results and other real events.
    static func isEvent(_ p: J, baseball: Bool) -> Bool {
        if p["text"].str.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        guard baseball else { return true }
        let t = p["type"]["type"].str
        if ["ball", "strike", "foul", "start-", "end-"].contains(where: { t.hasPrefix($0) }) { return false }
        return !p["text"].str.hasPrefix("Pitch ")
    }

    static func parse(_ p: J, baseball: Bool) -> PlayItem {
        let per = p["period"]
        let n = per["number"].int ?? 0
        let name: String
        let short: String
        let key: String
        if baseball {
            let half = per["type"].str  // "Top" / "Bottom"
            name = [half, per["displayValue"].str].filter { !$0.isEmpty }.joined(separator: " ")
            short = "\(n)"
            key = "\(n)-\(half)"
        } else {
            name = per["displayValue"].string ?? "Period \(n)"
            short = n <= 4 ? "Q\(n)" : (n == 5 ? "OT" : "\(n - 4)OT")
            key = "\(n)"
        }
        return PlayItem(id: p["id"].str, period: n, periodName: name, periodShort: short,
                        clock: p["clock"]["displayValue"].string ?? "", text: p["text"].str,
                        scoring: p["scoringPlay"].bool == true, teamId: p["team"]["id"].str,
                        away: p["awayScore"].int ?? 0, home: p["homeScore"].int ?? 0, groupKey: key)
    }
}

struct PlaysSection: View {
    let league: League
    let left: Side
    let right: Side
    let live: Bool
    private let plays: [PlayItem]
    private let points: [WinPoint]
    private let moments: [KeyMoment]

    @State private var scoringOnly = true
    @State private var period: Int? = nil       // nil = all periods
    @State private var didPickDefault = false
    @State private var selected: Int? = nil     // selected win probability point
    @State private var highlighted: String? = nil   // play opened from a key moment
    @AppStorage("playsTab") private var tab = 0  // 0 win probability, 1 play-by-play

    init(league: League, summary: J, left: Side, right: Side) {
        self.league = league
        self.left = left
        self.right = right
        self.live = summary["header"]["competitions"][0]["status"]["type"]["state"].str == "in"
        let baseball = PlayData.isBaseball(league)
        let all = summary["plays"].array
        var byId: [String: PlayItem] = [:]
        var list: [PlayItem] = []
        list.reserveCapacity(all.count)
        for p in all {
            let item = PlayData.parse(p, baseball: baseball)
            byId[item.id] = item
            if PlayData.isEvent(p, baseball: baseball) { list.append(item) }
        }
        plays = list
        let raw = summary["winprobability"].array.compactMap { w -> (Double, PlayItem?)? in
            guard let h = w["homeWinPercentage"].double else { return nil }
            return (100 - h * 100, byId[w["playId"].str])
        }
        let pts = raw.enumerated().map { WinPoint(id: $0.offset, away: $0.element.0, play: $0.element.1) }
        points = pts
        moments = KeyMoments.find(pts, awayId: left.isHome ? right.id : left.id, homeId: left.isHome ? left.id : right.id)
    }

    private var periods: [Int] { Array(Set(plays.map(\.period))).sorted() }

    private func label(_ n: Int) -> String {
        if PlayData.isBaseball(league) { return "\(n)" }
        return n <= 4 ? "Q\(n)" : (n == 5 ? "OT" : "\(n - 4)OT")
    }

    var body: some View {
        let hasChart = points.count > 3
        VStack(spacing: 14) {
            if hasChart {
                TextTabs(items: [0, 1], selection: $tab) { $0 == 0 ? "Win Probability" : "Play-by-Play" }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if hasChart && tab == 0 {
                WinProbabilityCard(points: points, moments: moments, left: left, right: right,
                                   baseball: PlayData.isBaseball(league), selected: $selected)
                if !moments.isEmpty {
                    KeyMomentsCard(moments: moments, left: left, right: right, selected: $selected) { m in
                        // Open the play in the play-by-play list.
                        scoringOnly = false
                        period = m.play.period
                        highlighted = m.play.id
                        tab = 1
                    }
                }
            } else if plays.isEmpty {
                MessageCard(text: "Play-by-play appears once the game starts.")
            } else {
                playList
            }
        }
        .onAppear {
            // Live games open on the current period.
            if !didPickDefault {
                didPickDefault = true
                if live { period = plays.last?.period }
            }
        }
    }

    private var playList: some View {
        let shown = plays.filter { (!scoringOnly || $0.scoring) && (period == nil || $0.period == period) }
        // Newest first, grouped by period (half-inning for MLB).
        var groups: [(key: String, name: String, items: [PlayItem])] = []
        for p in shown.reversed() {
            if groups.last?.key == p.groupKey { groups[groups.count - 1].items.append(p) }
            else { groups.append((p.groupKey, p.periodName, [p])) }
        }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Play-by-play").font(.title3.weight(.bold))
                Spacer()
                TextTabs(items: [true, false], selection: $scoringOnly) { $0 ? "Scoring" : "All" }
                    .fixedSize()
            }
            .padding(.horizontal, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("All", on: period == nil) { period = nil }
                    ForEach(periods, id: \.self) { n in
                        chip(label(n), on: period == n) { period = n }
                    }
                }
            }
            if groups.isEmpty {
                MessageCard(text: scoringOnly ? "No scoring plays in this period." : "No plays in this period.")
            }
            LazyVStack(spacing: 14) {
                ForEach(groups, id: \.key) { g in
                    VStack(alignment: .leading, spacing: 0) {
                        CardTitle(g.name)
                        ForEach(Array(g.items.enumerated()), id: \.element.id) { i, p in
                            if i > 0 { Divider().overlay(Theme.separator) }
                            row(p)
                        }
                    }
                    .card()
                }
            }
        }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .foregroundStyle(on ? .black : .white)
                .background(on ? Color.white : Theme.card2, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func row(_ p: PlayItem) -> some View {
        let side = p.teamId == left.id ? left : p.teamId == right.id ? right : nil
        return HStack(alignment: .top, spacing: 10) {
            Text(p.clock)
                .font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.secondary)
                .frame(width: 38, alignment: .leading)
            if let side { LogoView(url: side.logo, fallback: side.abbr, size: 18) } else { Color.clear.frame(width: 18, height: 18) }
            Text(p.text).font(.footnote.weight(p.scoring ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
            if p.scoring {
                Text("\(p.away)-\(p.home)").font(.footnote.weight(.bold)).monospacedDigit()
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, highlighted == p.id ? 6 : 0)
        .background(highlighted == p.id ? Color.yellow.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Win chance of the left (away) team over the game. Drag along the chart to see
/// the score, chances and play at any moment; key moments are marked with dots.
private struct WinProbabilityCard: View {
    let points: [WinPoint]
    let moments: [KeyMoment]
    let left: Side      // away
    let right: Side     // home
    let baseball: Bool
    @Binding var selected: Int?

    /// First point of each period after the first (faint marks with labels).
    private var periodStarts: [(index: Int, label: String)] {
        var first: [Int: (Int, String)] = [:]
        for p in points {
            guard let play = p.play, play.period > 1 else { continue }
            if let f = first[play.period], f.0 <= p.id { continue }
            first[play.period] = (p.id, play.periodShort)
        }
        return first.keys.sorted().compactMap { first[$0] }.map { (index: $0.0, label: $0.1) }
    }

    var body: some View {
        let current = selected.flatMap { i in points.first { $0.id == i } } ?? points.last!
        let awayPct = current.away
        VStack(alignment: .leading, spacing: 10) {
            CardTitle("Win probability")
            HStack {
                LogoView(url: left.logo, fallback: left.abbr, size: 20)
                Text(String(format: "%@ %.0f%%", left.abbr, awayPct)).font(.subheadline.weight(.bold))
                Spacer()
                Text(String(format: "%@ %.0f%%", right.abbr, 100 - awayPct)).font(.subheadline.weight(.bold))
                LogoView(url: right.logo, fallback: right.abbr, size: 20)
            }
            .monospacedDigit()
            // The moment under the finger (or the latest play).
            if let play = current.play {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(baseball ? play.periodName : play.periodShort) \(play.clock) · \(play.away)-\(play.home)")
                        .font(.caption.weight(.bold)).foregroundStyle(Theme.secondary).monospacedDigit()
                    Text(play.text).font(.footnote).lineLimit(2, reservesSpace: true)
                }
            }
            Chart {
                ForEach(points) { p in
                    AreaMark(x: .value("Play", p.id), yStart: .value("Base", 50), yEnd: .value("Away", p.away))
                        .foregroundStyle(Color.white.opacity(0.12))
                    LineMark(x: .value("Play", p.id), y: .value("Away", p.away))
                        .foregroundStyle(.white)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                RuleMark(y: .value("Even", 50)).foregroundStyle(Theme.tertiary)
                ForEach(periodStarts, id: \.index) { s in
                    RuleMark(x: .value("Period", s.index))
                        .foregroundStyle(Color.white.opacity(0.12))
                        .annotation(position: .bottom, alignment: .center) {
                            Text(s.label).font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.tertiary)
                        }
                }
                ForEach(moments) { m in
                    PointMark(x: .value("Play", m.index), y: .value("Away", points[m.index].away))
                        .symbolSize(40)
                        .foregroundStyle(Color.yellow)
                }
                if let s = selected, let p = points.first(where: { $0.id == s }) {
                    RuleMark(x: .value("Selected", s)).foregroundStyle(Color.white.opacity(0.6))
                    PointMark(x: .value("Play", s), y: .value("Away", p.away)).symbolSize(70).foregroundStyle(.white)
                }
            }
            // A little room above 100 % and below 0 % so dots at the edges aren't cut.
            .chartYScale(domain: -5...105)
            .chartXScale(domain: 0...max(1, points.count - 1))
            .chartPlotStyle { $0.padding(.horizontal, 4) }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { v in
                    AxisValueLabel { Text(v.as(Int.self) == 100 ? left.abbr : v.as(Int.self) == 0 ? right.abbr : "50%") }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { v in
                                    guard let plot = proxy.plotFrame else { return }
                                    let x = v.location.x - geo[plot].origin.x
                                    if let i: Int = proxy.value(atX: x) {
                                        selected = min(max(0, i), points.count - 1)
                                    }
                                }
                                .onEnded { _ in selected = nil }
                        )
                }
            }
            .frame(height: 150)
            .padding(.bottom, 14)
            Text("Drag along the chart to follow the game. Dots mark the key moments.")
                .font(.caption2).foregroundStyle(Theme.tertiary)
        }
        .card()
    }
}

/// Runs, lead changes and big plays in the win probability. Tapping one opens the play.
private struct KeyMomentsCard: View {
    let moments: [KeyMoment]
    let left: Side
    let right: Side
    @Binding var selected: Int?
    var open: (KeyMoment) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardTitle("Key moments")
            ForEach(Array(moments.enumerated()), id: \.element.id) { i, m in
                if i > 0 { Divider().overlay(Theme.separator) }
                Button { open(m) } label: { row(m).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
            }
            Text("Runs and lead changes in the win probability. Tap one to see it in the play-by-play.")
                .font(.caption2).foregroundStyle(Theme.tertiary).padding(.top, 6)
        }
        .card()
    }

    private func row(_ m: KeyMoment) -> some View {
        // Positive change favours the left (away) team.
        let gainer = m.change >= 0 ? left : right
        let side = m.play.teamId == left.id ? left : m.play.teamId == right.id ? right : gainer
        let label: String = {
            switch m.kind {
            case .turnaround: return "Lead change"
            case .run:
                if let e = m.endPlay {
                    return "Run to \(e.periodShort) \(e.clock) · \(e.away)-\(e.home)"
                }
                return "Run"
            case .play: return "Big play"
            }
        }()
        return HStack(alignment: .top, spacing: 10) {
            LogoView(url: side.logo, fallback: side.abbr, size: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(m.play.periodShort) \(m.play.clock) · \(m.play.away)-\(m.play.home)")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary).monospacedDigit()
                Text(m.play.text).font(.footnote.weight(.semibold))
                Text(label).font(.caption).foregroundStyle(m.kind == .turnaround ? Color.yellow : Theme.secondary)
            }
            Spacer(minLength: 6)
            Text(String(format: "%@ +%.0f%%", gainer.abbr, abs(m.change)))
                .font(.caption.weight(.bold)).monospacedDigit()
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.white.opacity(0.1), in: Capsule())
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.tertiary)
                .padding(.top, 5)
        }
        .padding(.vertical, 8)
    }
}
