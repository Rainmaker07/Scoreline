import UIKit
import SwiftUI

// MARK: - WorldTour calendar

struct WorldTourList: View {
    var refresh = 0
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var filter = 0 // 0 all, 1 grand tours, 2 stage races, 3 one-day

    var body: some View {
        let thisYear = Calendar.current.component(.year, from: Date())
        VStack(alignment: .leading, spacing: 12) {
            ChipRow(items: [thisYear, thisYear - 1, thisYear - 2], selected: year, title: { String($0) }) { year = $0 }
            ChipScroll {
                    ForEach(Array(["All", "Grand Tours", "Stage races", "One-day races"].enumerated()), id: \.offset) { i, t in
                        Chip(title: t, selected: filter == i) { filter = i }
                    }
                }
            if filter == 1 {
                GrandToursPanel(year: year, refresh: refresh).id(year)
            } else {
            Loader(id: "wt-\(year)-\(refresh)", load: { try await WorldTour.calendar(year) }) { races in
                let list = races.filter { r in
                    switch filter {
                    case 1: return r.isGrandTour
                    case 2: return !r.isGrandTour && !r.isOneDay
                    case 3: return r.isOneDay
                    default: return true
                    }
                }
                let live = list.filter(\.isLive)
                VStack(alignment: .leading, spacing: 14) {
                    if races.isEmpty { MessageCard(text: "The \(String(year)) WorldTour calendar isn’t available yet.") }
                    if !live.isEmpty {
                        SectionHeader(title: "This Week")
                        raceCard(live)
                    }
                    let months = Dictionary(grouping: list.filter { $0.start != nil }) { Calendar.current.component(.month, from: $0.start!) }
                    ForEach(months.keys.sorted(), id: \.self) { m in
                        VStack(alignment: .leading, spacing: 0) {
                            CardTitle(Calendar.current.monthSymbols[m - 1])
                            ForEach(Array((months[m] ?? []).enumerated()), id: \.element.id) { i, r in
                                if i > 0 { Divider().overlay(Theme.separator) }
                                RaceRow(race: r)
                            }
                        }
                        .card(padding: 14)
                    }
                }
            }
            }
        }
    }

    private func raceCard(_ list: [WTRace]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element.id) { i, r in
                if i > 0 { Divider().overlay(Theme.separator) }
                RaceRow(race: r)
            }
        }
        .card(padding: 14)
    }
}

private struct RaceRow: View {
    let race: WTRace
    var body: some View {
        NavigationLink(value: Route.cyclingRace(race)) {
            HStack(spacing: 12) {
                RaceLogo(race: race, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(race.name).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        if race.isMonument {
                            Text("MONUMENT").font(.system(size: 8, weight: .heavy)).foregroundStyle(.yellow)
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    Text([Fmt.text(race.dates), race.country, race.winner.map { "🏆 \($0)" }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if race.isLive {
                    HStack(spacing: 4) { LivePulse(); Text("Racing") }.font(.caption.weight(.bold)).foregroundStyle(Theme.live)
                }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.tertiary)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A WorldTour race: stage races use the Grand Tour page, one-day races show the result.
struct RaceView: View {
    let race: WTRace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if race.start != nil && race.start == race.end {
                    Loader(id: "oneday-\(race.id)", load: { try await WorldTour.oneDay(race) }) { r in
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 10) {
                                    RaceLogo(race: race, size: 44)
                                    Text(verbatim: "\(r.name) \(r.year)").font(.title2.weight(.heavy))
                                }
                                Text([r.dates.map(Fmt.text), r.distance].compactMap { $0 }.joined(separator: " · ")).font(.footnote).foregroundStyle(Theme.secondary)
                                if let w = r.results.first { Text("Winner: \(w.name)").font(.subheadline.weight(.bold)).padding(.top, 4) }
                            }
                            .card()
                            if r.results.isEmpty {
                                MessageCard(text: (race.start ?? Date()) > Date() ? "Results appear after the race." : "No result table on Wikipedia yet.")
                            } else {
                                VStack(alignment: .leading, spacing: 0) {
                                    CardTitle("Result")
                                    RiderList(riders: r.results)
                                }
                                .card()
                            }
                            if !r.summary.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    CardTitle("Race summary")
                                    ForEach(Array(r.summary.prefix(4).enumerated()), id: \.offset) { _, p in Text(p).font(.subheadline) }
                                }
                                .card()
                            }
                        }
                    }
                } else {
                    let def = WorldTour.def(for: race)
                    Loader(id: "stagerace-\(race.id)", load: { try await CyclingService.load(def, year: race.year) }) { edition in
                        EditionBody(edition: edition)
                    }
                }
                Text("From Wikipedia (CC BY-SA).").font(.caption2).foregroundStyle(Theme.tertiary)
            }
            .padding(16)
        }
        .background(PageBackground(color: "5a4a00"))
        .navigationTitle(race.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

// MARK: - Rider page

struct RiderPageView: View {
    let name: String

    var body: some View {
        ScrollView {
            Loader(id: "riderpage-\(name)", load: { try await CyclingPeople.rider(name) }) { p in
                VStack(spacing: 14) {
                    DetailHeader(image: p.image, isLogo: false, title: p.name, subtitle: p.description, color: "5a4a00",
                                 trailing: AnyView(FavoriteButton(favorite: Favorite(kind: .rider, leagueId: "cycling", entityId: name, name: name, abbr: "", logo: nil))))
                    VStack(spacing: 14) {
                        if let team = p.currentTeam {
                            NavigationLink(value: Route.cyclingTeam(team)) {
                                HStack {
                                    Image(systemName: "person.3.fill").foregroundStyle(Theme.secondary)
                                    Text(team).font(.headline)
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(Theme.secondary)
                                }
                                .card()
                            }
                            .buttonStyle(.plain)
                        }
                        InfoList(title: "Profile", rows: p.info)
                        RiderSeasonCard(name: name)
                        if !p.teams.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                CardTitle("Teams")
                                ForEach(Array(p.teams.enumerated()), id: \.offset) { i, t in
                                    if i > 0 { Divider().overlay(Theme.separator) }
                                    NavigationLink(value: Route.cyclingTeam(t.team)) {
                                        HStack {
                                            Text(t.years).font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary).frame(width: 90, alignment: .leading)
                                            Text(t.team).font(.subheadline)
                                            Spacer()
                                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.tertiary)
                                        }
                                        .padding(.vertical, 8)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .card()
                        }
                        ForEach(Array(p.majorWins.enumerated()), id: \.offset) { _, group in
                            DisclosureCard(title: "Major wins · \(group.category)", items: group.items)
                        }
                        if let e = p.extract {
                            VStack(alignment: .leading, spacing: 8) {
                                CardTitle("About")
                                Text(e).font(.subheadline)
                                Text("Wikipedia (CC BY-SA)").font(.caption2).foregroundStyle(Theme.tertiary)
                            }
                            .card()
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 40)
            }
        }
        .background(PageBackground())
        .navigationTitle("Rider")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

struct DisclosureCard: View {
    let title: String
    let items: [String]
    @State private var open = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.snappy) { open.toggle() } } label: {
                HStack {
                    CardTitle(title)
                    Spacer()
                    Text("\(items.count)").font(.footnote.weight(.bold)).foregroundStyle(Theme.secondary)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.secondary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                    Text(it).font(.subheadline).padding(.vertical, 5)
                        .overlay(alignment: .top) { Divider().overlay(Theme.separator) }
                }
            }
        }
        .card()
    }
}

/// The rider's stage wins, top-10s and classification placings in this season's Grand Tours.
private struct RiderSeasonCard: View {
    let name: String
    var body: some View {
        Loader(id: "season-\(name)", load: { await Self.load(name) }) { rows in
            if !rows.isEmpty {
                InfoList(title: "This season · Grand Tours", rows: rows)
            }
        }
    }

    static func load(_ name: String) async -> [InfoRow] {
        let year = Calendar.current.component(.year, from: Date())
        let key = name.lowercased()
        var out: [InfoRow] = []
        for def in TourDef.all {
            guard let e = try? await CyclingService.load(def, year: year) else { continue }
            if let gc = e.classifications[.gc]?.first(where: { $0.name.lowercased() == key }) {
                out.append(InfoRow(label: "\(def.short) · GC", value: BBL.ordinal(gc.rank)))
            }
            for k in [JerseyKey.points, .kom, .youth] {
                if let r = e.classifications[k]?.first(where: { $0.name.lowercased() == key }), r.rank <= 3 {
                    out.append(InfoRow(label: "\(def.short) · \(def.jersey(k).label)", value: BBL.ordinal(r.rank)))
                }
            }
            for s in e.stages {
                if s.winner?.lowercased() == key {
                    out.append(InfoRow(label: "\(def.short) · Stage \(s.n)", value: "🏆 Won"))
                } else if let r = s.result.first(where: { $0.name.lowercased() == key }), r.rank <= 10 {
                    out.append(InfoRow(label: "\(def.short) · Stage \(s.n)", value: BBL.ordinal(r.rank)))
                }
            }
        }
        return out
    }
}

// MARK: - Cycling team page

struct CyclingTeamView: View {
    let name: String
    var body: some View {
        ScrollView {
            Loader(id: "cteam-\(name)", load: { try await CyclingPeople.team(name) }) { t in
                VStack(spacing: 14) {
                    DetailHeader(image: t.image, isLogo: true, title: t.name, subtitle: nil, color: "5a4a00")
                    VStack(spacing: 14) {
                        InfoList(title: "Team", rows: t.info)
                        if let roster = t.roster { WikiTableCard(table: WikiTable(caption: "Roster", rows: roster.rows)) }
                        if let wins = t.wins { WikiTableCard(table: WikiTable(caption: "Season wins", rows: wins.rows)) }
                        if t.roster == nil && t.wins == nil && t.info.isEmpty {
                            MessageCard(text: "No team details found on Wikipedia for \(name).")
                        }
                        if let e = t.extract {
                            VStack(alignment: .leading, spacing: 8) {
                                CardTitle("About")
                                Text(e).font(.subheadline)
                                Text("Wikipedia (CC BY-SA)").font(.caption2).foregroundStyle(Theme.tertiary)
                            }
                            .card()
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 40)
            }
        }
        .background(PageBackground())
        .navigationTitle("Team")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

// MARK: - Rankings

/// UCI World Tour ranking (riders, teams) and the season's win leaders.
struct CyclingRankingsView: View {
    var refresh = 0
    @State private var year = Calendar.current.component(.year, from: Date())
    @AppStorage("cyclingRankingKind") private var kind = 0   // 0 riders, 1 teams, 2 wins

    var body: some View {
        let thisYear = Calendar.current.component(.year, from: Date())
        VStack(alignment: .leading, spacing: 12) {
            ChipRow(items: [thisYear, thisYear - 1, thisYear - 2], selected: year, title: { String($0) }) { year = $0 }
            TextTabs(items: [0, 1, 2], selection: $kind) { ["Riders", "Teams", "Most wins"][$0] }
            if kind == 2 {
                Loader(id: "wins-\(year)-\(refresh)", load: { try await CyclingRankings.winLeaders(year) }) { list in
                    if list.isEmpty {
                        MessageCard(text: "No WorldTour results for \(String(year)) yet.")
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            CardTitle("Most wins · WorldTour")
                            ForEach(Array(list.enumerated()), id: \.element.id) { i, w in
                                if i > 0 { Divider().overlay(Theme.separator) }
                                NavigationLink(value: Route.rider(name: w.name)) {
                                    HStack(spacing: 12) {
                                        Text("\(i + 1)").font(.footnote.weight(.bold)).foregroundStyle(Theme.secondary).frame(width: 22)
                                        RiderPhoto(name: w.name)
                                        VStack(alignment: .leading, spacing: 1) {
                                            HStack(spacing: 5) {
                                                Text(w.name).font(.subheadline.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.85)
                                                if let c = w.country { Text(c).font(.caption2).foregroundStyle(Theme.secondary) }
                                            }
                                            Text(w.detail).font(.caption).foregroundStyle(Theme.secondary)
                                        }
                                        Spacer()
                                        Text("\(w.wins)").font(.title3.weight(.heavy)).monospacedDigit()
                                    }
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .card(padding: 14)
                    }
                }
                Text("Counts one-day wins, overall wins and stage wins in WorldTour races (Wikipedia).")
                    .font(.caption2).foregroundStyle(Theme.tertiary).padding(.horizontal, 4)
            } else {
                Loader(id: "uci-rank-\(year)-\(refresh)", load: { try await CyclingRankings.rankings(year) }) { r in
                    let list = kind == 0 ? r.riders : r.teams
                    if list.isEmpty {
                        MessageCard(text: kind == 0 ? "The \(String(year)) UCI ranking isn’t on Wikipedia yet."
                                    : "Wikipedia has no \(String(year)) team ranking yet.")
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            CardTitle(kind == 0 ? "UCI ranking · Riders" : "UCI ranking · Teams")
                            ForEach(Array(list.enumerated()), id: \.offset) { i, e in
                                if i > 0 { Divider().overlay(Theme.separator) }
                                NavigationLink(value: kind == 0 ? Route.rider(name: e.name) : Route.cyclingTeam(e.name)) {
                                    HStack(spacing: 12) {
                                        Text("\(e.rank)").font(.footnote.weight(.bold)).foregroundStyle(Theme.secondary).frame(width: 26)
                                        if kind == 0 { RiderPhoto(name: e.name) } else { TeamLogoBadge(name: e.name, logo: nil) }
                                        VStack(alignment: .leading, spacing: 1) {
                                            HStack(spacing: 5) {
                                                Text(e.name).font(.subheadline.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.85)
                                                if let c = e.country { Text(c).font(.caption2).foregroundStyle(Theme.secondary) }
                                            }
                                            if let t = e.team, !t.isEmpty { Text(t).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1) }
                                        }
                                        Spacer()
                                        Text(e.value).font(.subheadline.weight(.bold)).monospacedDigit()
                                    }
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .card(padding: 14)
                    }
                }
            }
        }
    }
}

/// Race logo from Wikipedia (English article, then German). Transparent logos sit
/// directly on the card; dark ones and logos with their own white background get a
/// soft light tile (white margins trimmed). The flag / map icon when no logo exists.
struct RaceLogo: View {
    let race: WTRace
    var size: CGFloat = 34
    @State private var prepared: PreparedLogo?

    var body: some View {
        Group {
            if let p = prepared {
                Image(uiImage: p.image).resizable().scaledToFit()
                    .padding(p.needsTile ? 3 : 0)
                    .frame(width: size, height: size)
                    .background(p.needsTile ? Color.white.opacity(0.92) : .clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: race.isOneDay ? "flag.checkered" : "map")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(race.isGrandTour ? Color.yellow : Theme.secondary)
            }
        }
        .frame(width: size, height: size)
        .task(id: race.id) {
            guard let url = await RaceLogos.logo(race), let img = await ImageStore.shared.image(url) else { return }
            prepared = await LogoPrep.prepare(img, key: url.absoluteString)
        }
    }
}

struct PreparedLogo {
    let image: UIImage
    let needsTile: Bool
}

/// Looks at a logo once: trims empty or white margins, and decides whether it needs a
/// light tile (no transparency, or dark artwork that would vanish on a dark card).
enum LogoPrep {
    private static let cache = LockedCache<String, PreparedLogo>()

    static func prepare(_ img: UIImage, key: String) async -> PreparedLogo {
        if let hit = cache[key] { return hit }
        let result = await Task.detached(priority: .utility) { analyse(img) }.value
        cache[key] = result
        return result
    }

    private static func analyse(_ img: UIImage) -> PreparedLogo {
        guard let cg = img.cgImage else { return PreparedLogo(image: img, needsTile: true) }
        // Draw into a small RGBA buffer to inspect the pixels.
        let w = min(cg.width, 160), h = max(1, Int(Double(cg.height) * Double(w) / Double(max(cg.width, 1))))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return PreparedLogo(image: img, needsTile: true) }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let raw = ctx.data else { return PreparedLogo(image: img, needsTile: true) }
        // Rows in memory run top to bottom.
        let px = raw.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var transparent = 0, opaque = 0, lumSum = 0.0
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let a = Double(px[i + 3]) / 255
                if a < 0.1 { transparent += 1; continue }
                let r = Double(px[i]) / 255 / a, g = Double(px[i + 1]) / 255 / a, b = Double(px[i + 2]) / 255 / a
                let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
                let isWhite = lum > 0.94 && a > 0.9
                if !isWhite {
                    opaque += 1
                    lumSum += lum
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        let hasAlpha = Double(transparent) / Double(w * h) > 0.08
        let meanLum = opaque > 0 ? lumSum / Double(opaque) : 1
        // Transparent and light enough for a dark card: no tile.
        let needsTile = !hasAlpha || meanLum < 0.38
        // Trim margins (white or transparent) with a little breathing room.
        var out = img
        if maxX > minX, maxY > minY {
            let sx = Double(cg.width) / Double(w), sy = Double(cg.height) / Double(h)
            let pad = 2.0
            let rect = CGRect(x: max(0, (Double(minX) - pad) * sx),
                              y: max(0, (Double(minY) - pad) * sy),
                              width: (Double(maxX - minX) + 2 * pad + 1) * sx,
                              height: (Double(maxY - minY) + 2 * pad + 1) * sy)
                .intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            if let c = cg.cropping(to: rect.integral) { out = UIImage(cgImage: c, scale: img.scale, orientation: img.imageOrientation) }
        }
        return PreparedLogo(image: out, needsTile: needsTile)
    }

    /// A logo on a plain background (white box, black box): that background colour made
    /// transparent, flood-filled from the corners. Logos with transparency are returned as-is.
    static func knockOut(_ img: UIImage, key: String) async -> UIImage {
        if let hit = knocked[key] { return hit }
        let result = await Task.detached(priority: .utility) { () -> UIImage in
            guard let cg = img.cgImage else { return img }
            let w = cg.width, h = cg.height
            guard w > 4, h > 4, w * h < 4_000_000,
                  let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let raw = ctx.data else { return img }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            let px = raw.bindMemory(to: UInt8.self, capacity: w * h * 4)
            func at(_ x: Int, _ y: Int) -> Int { (y * w + x) * 4 }
            // Already transparent at a corner: nothing to do.
            if px[at(0, 0) + 3] < 250 { return img }
            let bg = (Int(px[0]), Int(px[1]), Int(px[2]))
            func close(_ i: Int) -> Bool {
                abs(Int(px[i]) - bg.0) + abs(Int(px[i + 1]) - bg.1) + abs(Int(px[i + 2]) - bg.2) < 60 && px[i + 3] > 200
            }
            var seen = [Bool](repeating: false, count: w * h)
            var stack = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
            while let point = stack.popLast() {
                let x = point.0, y = point.1
                guard x >= 0, y >= 0, x < w, y < h, !seen[y * w + x] else { continue }
                seen[y * w + x] = true
                let i = at(x, y)
                guard close(i) else { continue }
                px[i] = 0; px[i + 1] = 0; px[i + 2] = 0; px[i + 3] = 0
                stack.append((x + 1, y)); stack.append((x - 1, y)); stack.append((x, y + 1)); stack.append((x, y - 1))
            }
            guard let out = ctx.makeImage() else { return img }
            return UIImage(cgImage: out, scale: img.scale, orientation: img.imageOrientation)
        }.value
        knocked[key] = result
        return result
    }
    private static let knocked = LockedCache<String, UIImage>()
}

/// Competition logo with its plain background removed (e.g. ESPN's World Cup logo).
struct CleanLogo: View {
    let url: URL?
    var size: CGFloat = 16
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() } else { Color.clear }
        }
        .frame(width: size, height: size)
        .task(id: url) {
            guard let url, let img = await ImageStore.shared.image(url) else { return }
            image = await LogoPrep.knockOut(img, key: url.absoluteString)
        }
    }
}

enum RaceLogos {
    static func logo(_ race: WTRace) async -> URL? {
        if let gt = TourDef.all.first(where: { race.name.lowercased().contains($0.name.lowercased()) || race.name.lowercased().contains($0.wiki.lowercased()) }),
           race.isGrandTour {
            return LogoAssets.grandTour(gt.id)
        }
        return await WikiLogo.eventLogo(english: race.name, germanQueries: germanQueries(race.name))
    }

    /// German article searches: the race name, then the name with "Radrennen".
    static func germanQueries(_ name: String) -> [String] {
        let n = name.replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "/ ", with: "")
        return [n, "\(n) Radrennen"]
    }
}


/// Small round rider photo (Wikipedia lead image), silhouette if none.
struct RiderPhoto: View {
    let name: String
    var size: CGFloat = 32
    @State private var found: (name: String, url: URL?)?

    var body: some View {
        let url = found?.name == name ? found?.url : nil
        CachedImage(url: url) { $0.resizable().scaledToFill() } placeholder: {
            Image(systemName: "person.fill").font(.system(size: size * 0.45)).foregroundStyle(Theme.secondary)
        }
        .frame(width: size, height: size)
        .background(Theme.card2)
        .clipShape(Circle())
        .task(id: name) {
            guard found?.name != name else { return }
            let u = await PlayerPhotos.best(primary: nil, name: name, team: "", football: false)
            found = (name, u)
        }
    }
}
