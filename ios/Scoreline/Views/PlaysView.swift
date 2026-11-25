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
    var id: Int { index }
    let index: Int
    let change: Double          // change of the away team's chance, in points
    let play: PlayItem
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
        // Key moments: the plays that moved the win probability most.
        var swings: [KeyMoment] = []
        for i in 1..<max(1, pts.count) {
            guard let play = pts[i].play, !play.text.isEmpty else { continue }
            swings.append(KeyMoment(index: i, change: pts[i].away - pts[i - 1].away, play: play))
        }
        moments = swings.sorted { abs($0.change) > abs($1.change) }.prefix(5).sorted { $0.index < $1.index }
    }

    private var periods: [Int] { Array(Set(plays.map(\.period))).sorted() }

    private func label(_ n: Int) -> String {
        if PlayData.isBaseball(league) { return "\(n)" }
        return n <= 4 ? "Q\(n)" : (n == 5 ? "OT" : "\(n - 4)OT")
    }

    var body: some View {
        VStack(spacing: 14) {
            if points.count > 3 {
                WinProbabilityCard(points: points, moments: moments, left: left, right: right,
                                   baseball: PlayData.isBaseball(league), selected: $selected)
                if !moments.isEmpty {
                    KeyMomentsCard(moments: moments, left: left, right: right, selected: $selected)
                }
            }
            if plays.isEmpty {
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
        var out: [(Int, String)] = []
        var last: Int?
        for p in points {
            guard let play = p.play else { continue }
            if let l = last, play.period != l { out.append((p.id, play.periodShort)) }
            last = play.period
        }
        return out
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
            .chartYScale(domain: 0...100)
            .chartXScale(domain: 0...max(1, points.count - 1))
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
            Text("Drag along the chart to follow the game. Dots mark the key moments.")
                .font(.caption2).foregroundStyle(Theme.tertiary)
        }
        .card()
    }
}

/// The plays that changed the win probability most.
private struct KeyMomentsCard: View {
    let moments: [KeyMoment]
    let left: Side
    let right: Side
    @Binding var selected: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardTitle("Key moments")
            ForEach(Array(moments.enumerated()), id: \.element.id) { i, m in
                if i > 0 { Divider().overlay(Theme.separator) }
                Button {
                    selected = selected == m.index ? nil : m.index
                } label: {
                    row(m).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }

    private func row(_ m: KeyMoment) -> some View {
        // Positive change favours the left (away) team.
        let gainer = m.change >= 0 ? left : right
        let side = m.play.teamId == left.id ? left : m.play.teamId == right.id ? right : gainer
        return HStack(alignment: .top, spacing: 10) {
            LogoView(url: side.logo, fallback: side.abbr, size: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(m.play.periodShort) \(m.play.clock) · \(m.play.away)-\(m.play.home)")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary).monospacedDigit()
                Text(m.play.text).font(.footnote.weight(.semibold))
            }
            Spacer(minLength: 6)
            Text(String(format: "%@ +%.0f%%", gainer.abbr, abs(m.change)))
                .font(.caption.weight(.bold)).monospacedDigit()
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.white.opacity(selected == m.index ? 0.25 : 0.1), in: Capsule())
        }
        .padding(.vertical, 8)
    }
}
