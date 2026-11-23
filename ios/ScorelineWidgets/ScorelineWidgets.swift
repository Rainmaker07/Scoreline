import ActivityKit
import SwiftUI
import WidgetKit

@main
struct ScorelineWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ScoreLiveActivity()
    }
}

private extension Color {
    init(hexString: String) {
        var v: UInt64 = 0
        Scanner(string: hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&v)
        self = hexString.count >= 6
            ? Color(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
            : Color.gray
    }
}

struct ScoreLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScoreActivityAttributes.self) { context in
            LockScreenScore(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let a = context.attributes, s = context.state
            let left = a.homeFirst ? (a.homeAbbr, s.homeScore) : (a.awayAbbr, s.awayScore)
            let right = a.homeFirst ? (a.awayAbbr, s.awayScore) : (a.homeAbbr, s.homeScore)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(left.0).font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(right.0).font(.headline)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("\(left.1) – \(right.1)").font(.title2.weight(.heavy)).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(s.lastEvent ?? s.status).font(.caption).foregroundStyle(.secondary)
                }
            } compactLeading: {
                Text("\(left.0) \(left.1)").font(.caption.weight(.bold)).monospacedDigit()
            } compactTrailing: {
                Text("\(right.1) \(right.0)").font(.caption.weight(.bold)).monospacedDigit()
            } minimal: {
                Text("\(left.1)-\(right.1)").font(.caption2.weight(.bold)).monospacedDigit()
            }
        }
    }
}

private struct LockScreenScore: View {
    let attributes: ScoreActivityAttributes
    let state: ScoreActivityAttributes.ContentState

    var body: some View {
        let a = attributes
        let left = a.homeFirst ? (a.homeName, a.homeAbbr, a.homeColor, state.homeScore) : (a.awayName, a.awayAbbr, a.awayColor, state.awayScore)
        let right = a.homeFirst ? (a.awayName, a.awayAbbr, a.awayColor, state.awayScore) : (a.homeName, a.homeAbbr, a.homeColor, state.homeScore)
        VStack(spacing: 8) {
            HStack {
                Text(a.leagueName).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                Spacer()
                HStack(spacing: 4) {
                    if state.state == "in" { Circle().fill(.red).frame(width: 6, height: 6) }
                    Text(state.state == "pre" ? a.start.formatted(date: .omitted, time: .shortened) : state.status)
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(state.state == "in" ? .red : .white.opacity(0.8))
            }
            HStack(spacing: 10) {
                team(left.0, left.1, left.2)
                Text(state.state == "pre" ? "vs" : "\(left.3)  –  \(right.3)")
                    .font(.system(size: 34, weight: .heavy).width(.condensed))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                team(right.0, right.1, right.2)
            }
            if let e = state.lastEvent, !e.isEmpty {
                Text(e).font(.caption).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
            }
        }
        .padding(14)
    }

    private func team(_ name: String, _ abbr: String, _ color: String) -> some View {
        VStack(spacing: 4) {
            Text(abbr)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color(hexString: color), in: Circle())
            Text(name).font(.caption2.weight(.semibold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}
