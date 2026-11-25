import SwiftUI

/// One player placed on the pitch.
struct PitchPlayer: Identifiable {
    let id: String
    let number: String
    let name: String
    let goals: Int
    let yellow: Bool
    let red: Bool
    let subbedOff: String?   // minute
}

/// Builds pitch lines from an ESPN football roster using the formation string
/// (e.g. "4-2-3-1") and position codes (RB, CD-L, AM-R, F …).
enum Formation {
    /// 1 = defence … 5 = attack
    static func line(_ pos: String) -> Double {
        let p = pos.uppercased()
        if p == "G" || p == "GK" { return 0 }
        if p == "SW" { return 1.5 }
        if ["LB", "RB", "LWB", "RWB", "CD", "CB"].contains(p) || p.hasPrefix("CD-") || p.hasPrefix("CB-") { return 1 }
        if p == "DM" || p.hasPrefix("DM-") { return 2 }
        if ["LM", "RM", "CM"].contains(p) || p.hasPrefix("CM-") { return 3 }
        if p == "AM" || p.hasPrefix("AM-") || p == "LW" || p == "RW" || p == "SS" { return 4 }
        return 5 // F, CF, CF-L, LF, RF, ST
    }

    /// -2 = left touchline … +2 = right touchline
    static func lateral(_ pos: String) -> Double {
        let p = pos.uppercased()
        if p.hasSuffix("-L") { return -1 }
        if p.hasSuffix("-R") { return 1 }
        if p.hasPrefix("L") { return -2 }
        if p.hasPrefix("R") { return 2 }
        return 0
    }

    /// Lines from goalkeeper to attack, each ordered left to right.
    static func lines(roster: [J], formation: String, events: [J]) -> [[PitchPlayer]] {
        let starters = roster.filter { $0["starter"].bool == true }
        guard !starters.isEmpty else { return [] }
        func player(_ p: J) -> PitchPlayer {
            let id = p["athlete"]["id"].str
            func involved(_ e: J, _ i: Int) -> Bool { e["participants"][i]["athlete"]["id"].str == id }
            let goals = events.filter { $0["scoringPlay"].bool == true && involved($0, 0) && !$0["type"]["text"].str.lowercased().contains("own") }.count
            let yellow = events.contains { $0["type"]["text"].str.lowercased().contains("yellow") && involved($0, 0) }
            let red = events.contains { $0["type"]["text"].str.lowercased().contains("red") && involved($0, 0) }
            let off = events.first { $0["type"]["text"].str.lowercased().contains("substitution") && involved($0, 1) }?["clock"]["displayValue"].string
            let last = p["athlete"]["lastName"].string ?? p["athlete"]["displayName"].str.split(separator: " ").last.map(String.init) ?? ""
            return PitchPlayer(id: id, number: p["jersey"].str, name: last, goals: goals, yellow: yellow, red: red,
                               subbedOff: p["subbedOut"].bool == true ? (off ?? "") : nil)
        }
        let pos: (J) -> String = { $0["position"]["abbreviation"].str }
        let place: (J) -> Int = { $0["formationPlace"].int ?? 99 }
        let gk = starters.filter { Formation.line(pos($0)) == 0 }
        let outfield = starters.filter { Formation.line(pos($0)) > 0 }
            .sorted { (Formation.line(pos($0)), place($0)) < (Formation.line(pos($1)), place($1)) }
        var counts = formation.split(separator: "-").compactMap { Int($0) }
        if counts.reduce(0, +) != outfield.count { counts = [outfield.count] }
        var lines: [[PitchPlayer]] = [gk.map(player)]
        var i = 0
        for c in counts {
            let chunk = Array(outfield[i..<min(i + c, outfield.count)])
            i += c
            lines.append(chunk.sorted { (Formation.lateral(pos($0)), place($0)) < (Formation.lateral(pos($1)), place($1)) }.map(player))
        }
        return lines
    }
}

/// Both teams on one pitch: home attacks upward from the bottom, away downward from the top.
struct PitchView: View {
    let league: League
    let home: (side: Side, formation: String, lines: [[PitchPlayer]])
    let away: (side: Side, formation: String, lines: [[PitchPlayer]])

    var body: some View {
        VStack(spacing: 6) {
            label(away.side, away.formation)
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    pitchMarkings(w: w, h: h)
                    team(away.lines, color: away.side.tintHex, top: true, w: w, h: h)
                    team(home.lines, color: home.side.tintHex, top: false, w: w, h: h)
                }
            }
            // Taller than a real pitch so five lines per team (e.g. 4-2-3-1) have room.
            .aspectRatio(0.56, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            label(home.side, home.formation)
        }
        .card(padding: 12)
    }

    private func label(_ s: Side, _ f: String) -> some View {
        HStack(spacing: 8) {
            LogoView(url: s.logo, fallback: s.abbr, size: 20)
            Text(s.short).font(.subheadline.weight(.bold))
            Spacer()
            Text(f).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondary)
        }
    }

    private func pitchMarkings(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "35663f"), Color(hex: "2b5634")], startPoint: .top, endPoint: .bottom)
            // stripes
            VStack(spacing: 0) {
                ForEach(0..<10, id: \.self) { i in
                    Rectangle().fill(i % 2 == 0 ? Color.white.opacity(0.03) : .clear)
                }
            }
            Group {
                Rectangle().stroke(.white.opacity(0.5), lineWidth: 1.5).padding(6)
                Rectangle().fill(.white.opacity(0.5)).frame(height: 1.5)
                Circle().stroke(.white.opacity(0.5), lineWidth: 1.5).frame(width: w * 0.26)
                Rectangle().stroke(.white.opacity(0.5), lineWidth: 1.5)
                    .frame(width: w * 0.55, height: h * 0.14).position(x: w / 2, y: 6 + h * 0.07)
                Rectangle().stroke(.white.opacity(0.5), lineWidth: 1.5)
                    .frame(width: w * 0.55, height: h * 0.14).position(x: w / 2, y: h - 6 - h * 0.07)
            }
        }
    }

    /// Lines spread over each team's own half (with a gap at the halfway line so the two
    /// front lines don't collide); away mirrored so its left wing is on screen right.
    private func team(_ lines: [[PitchPlayer]], color: String?, top: Bool, w: CGFloat, h: CGFloat) -> some View {
        let half = h / 2
        let n = max(lines.count, 1)
        let edge: CGFloat = 32          // keeper (and name) clear of the goal line
        let centreGap: CGFloat = 30     // forwards stay this far from halfway
        let span = half - edge - centreGap
        return ZStack {
            ForEach(Array(lines.enumerated()), id: \.offset) { li, line in
                let d = n == 1 ? edge : edge + span * CGFloat(li) / CGFloat(n - 1)
                let y = top ? d : h - d
                ForEach(Array(line.enumerated()), id: \.element.id) { pi, p in
                    let xFrac = (CGFloat(pi) + 1) / CGFloat(line.count + 1)
                    let x = top ? w * (1 - xFrac) : w * xFrac
                    NavigationLink(value: Route.player(leagueId: league.id, playerId: p.id)) {
                        marker(p, color: color)
                    }
                    .buttonStyle(.plain)
                    // Anchor on the shirt circle (the name hangs below it).
                    .position(x: x, y: y + 8)
                }
            }
        }
    }

    private func marker(_ p: PitchPlayer, color: String?) -> some View {
        let fill = Color.visibleTint(color) ?? Color(white: 0.85)
        let shadow = Color.black.opacity(0.85)
        return VStack(spacing: 1) {
            Text(p.number)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(fill, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1.5))
                // Goals top right, cards top left: always the same spot on the circle.
                .overlay(alignment: .topTrailing) {
                    if p.goals > 0 {
                        HStack(spacing: 0) {
                            Text("⚽").font(.system(size: 9))
                            if p.goals > 1 { Text("\(p.goals)").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white) }
                        }
                        .padding(.horizontal, 2)
                        .background(Color.black.opacity(0.55), in: Capsule())
                        .offset(x: 9, y: -6)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if p.red || p.yellow {
                        RoundedRectangle(cornerRadius: 1.5).fill(p.red ? Color.red : Color.yellow)
                            .frame(width: 7, height: 10)
                            .overlay(RoundedRectangle(cornerRadius: 1.5).stroke(.black.opacity(0.4), lineWidth: 0.5))
                            .offset(x: -5, y: -4)
                    }
                }
            HStack(spacing: 3) {
                Text(p.name)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                if let off = p.subbedOff {
                    Text("↓\(off)").font(.system(size: 8, weight: .heavy)).foregroundStyle(Color(hex: "ffb340"))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.black.opacity(0.35), in: Capsule())
            .shadow(color: shadow, radius: 1)
            .frame(maxWidth: 76)
        }
    }
}
