import Foundation

// MARK: - Definitions

enum JerseyKey: String, CaseIterable, Hashable {
    case gc, points, kom, youth
}

struct JerseyDef: Hashable {
    let key: JerseyKey
    let label: String
    let color: String
}

struct TourDef: Identifiable, Hashable {
    let id: String
    let name: String
    let short: String
    /// Wikipedia article suffix, e.g. "Tour de France" -> "2025 Tour de France"
    let wiki: String
    let color: String
    let endMonth: Int
    let jerseys: [JerseyDef]

    func jersey(_ k: JerseyKey) -> JerseyDef { jerseys.first { $0.key == k }! }

    static let all: [TourDef] = [
        TourDef(id: "giro", name: "Giro d'Italia", short: "Giro", wiki: "Giro d'Italia", color: "f4a6c1", endMonth: 6, jerseys: [
            JerseyDef(key: .gc, label: "Maglia Rosa", color: "f4a6c1"),
            JerseyDef(key: .points, label: "Maglia Ciclamino", color: "8e44ad"),
            JerseyDef(key: .kom, label: "Maglia Azzurra", color: "2f80ed"),
            JerseyDef(key: .youth, label: "Maglia Bianca", color: "f2f2f2"),
        ]),
        TourDef(id: "tour", name: "Tour de France", short: "Tour", wiki: "Tour de France", color: "ffd60a", endMonth: 7, jerseys: [
            JerseyDef(key: .gc, label: "Maillot Jaune", color: "ffd60a"),
            JerseyDef(key: .points, label: "Maillot Vert", color: "22c55e"),
            JerseyDef(key: .kom, label: "Maillot à Pois", color: "ef4444"),
            JerseyDef(key: .youth, label: "Maillot Blanc", color: "f2f2f2"),
        ]),
        TourDef(id: "vuelta", name: "La Vuelta", short: "Vuelta", wiki: "Vuelta a España", color: "ef4444", endMonth: 9, jerseys: [
            JerseyDef(key: .gc, label: "Maillot Rojo", color: "ef4444"),
            JerseyDef(key: .points, label: "Maillot Verde", color: "22c55e"),
            JerseyDef(key: .kom, label: "Maillot de Lunares", color: "2f80ed"),
            JerseyDef(key: .youth, label: "Maillot Blanco", color: "f2f2f2"),
        ]),
    ]
}

// MARK: - Parsed data

enum StageKind: String, Hashable {
    case flat, hilly, mountain, itt, ttt

    var label: String {
        switch self {
        case .flat: return "Flat"
        case .hilly: return "Hilly"
        case .mountain: return "Mountain"
        case .itt: return "ITT"
        case .ttt: return "TTT"
        }
    }

    var symbol: String {
        switch self {
        case .flat: return "arrow.right"
        case .hilly: return "chart.line.uptrend.xyaxis"
        case .mountain: return "mountain.2.fill"
        case .itt, .ttt: return "stopwatch"
        }
    }

    static func from(_ text: String) -> StageKind {
        let t = text.lowercased()
        if t.contains("team time trial") { return .ttt }
        if t.contains("time trial") { return .itt }
        if t.contains("medium") || t.contains("hill") || t.contains("intermediate") { return .hilly }
        if t.contains("mountain") || t.contains("summit") { return .mountain }
        if t.contains("flat") || t.contains("plain") { return .flat }
        return .hilly
    }
}

struct RiderResult: Hashable, Identifiable {
    var id: String { "\(rank)-\(name)" }
    let rank: Int
    let name: String
    let country: String?
    let team: String
    let value: String
}

struct CyclingStage: Identifiable, Hashable {
    var id: Int { n }
    let n: Int
    let date: Date?
    let start: String
    let finish: String
    let km: Double?
    let kind: StageKind
    let typeText: String
    let winner: String?
    let winnerCountry: String?
    var leaders: [JerseyKey: String] = [:]
    var result: [RiderResult] = []
    var gcAfter: [RiderResult] = []
    var report: [String] = []

    var route: String {
        func short(_ s: String) -> String { s.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression) }
        return start == finish || finish.isEmpty ? short(start) : "\(short(start)) → \(short(finish))"
    }
    var isRaced: Bool { winner != nil && !(winner ?? "").isEmpty }
}

struct Edition: Hashable {
    let def: TourDef
    let year: Int
    let dates: String?
    let stages: [CyclingStage]
    /// Final (or latest available) classifications
    let classifications: [JerseyKey: [RiderResult]]
    let teams: [RiderResult]
    let finalStandings: Bool

    var lastRaced: CyclingStage? { stages.last { $0.isRaced } }

    var winner: String? { finalStandings ? classifications[.gc]?.first?.name : nil }

    func leader(_ k: JerseyKey) -> String? {
        classifications[k]?.first?.name ?? lastRaced?.leaders[k]
    }
}

// MARK: - Loader

enum CyclingService {
    static func wikiURL(_ title: String) -> URL? {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~()'!")
        let t = title.replacingOccurrences(of: " ", with: "_")
        guard let enc = t.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://en.wikipedia.org/api/rest_v1/page/html/\(enc)")
    }

    /// "Racing: Tour de France" / "Next: Giro d'Italia · May" for the league menu.
    static func statusLine(_ now: Date = Date()) -> String {
        let m = Calendar.current.component(.month, from: now)
        let d = Calendar.current.component(.day, from: now)
        let windows: [(TourDef, Int, Int)] = [(TourDef.all[0], 509, 601), (TourDef.all[1], 704, 727), (TourDef.all[2], 822, 914)]
        let key = m * 100 + d
        if let live = windows.first(where: { key >= $0.1 && key <= $0.2 }) { return "Racing: \(live.0.name)" }
        let next = windows.first { $0.1 > key } ?? windows[0]
        return "Next: \(next.0.name)"
    }

    static func isFinished(_ def: TourDef, _ year: Int, now: Date = Date()) -> Bool {
        let c = Calendar.current.dateComponents([.year, .month], from: now)
        guard let y = c.year, let m = c.month else { return false }
        return year < y || (year == y && m > def.endMonth)
    }

    private static func fetch(_ title: String, finished: Bool) async throws -> String {
        guard let url = wikiURL(title) else { throw FetchError.parse("Bad title") }
        // Finished races never change: keep them forever. Running races: 10 min.
        return try await HTTP.shared.text(url, maxAge: finished ? 86_400 * 365 : 600, permanent: finished)
    }

    static func load(_ def: TourDef, year: Int) async throws -> Edition {
        let finished = isFinished(def, year)
        let title = "\(year) \(def.wiki)"
        let html = try await fetch(title, finished: finished)

        // Stage articles (e.g. "2025 Tour de France, Stage 1 to Stage 11")
        let prefix = "\(year)_\(def.wiki.replacingOccurrences(of: " ", with: "_")),_Stage"
        let stageTitles = WikiHTML.links(in: html, containing: prefix).map { $0.replacingOccurrences(of: "_", with: " ") }
        var stageHTML: [String] = []
        for t in stageTitles {
            if let h = try? await fetch(t, finished: finished) { stageHTML.append(h) }
        }

        return await Task.detached(priority: .userInitiated) {
            CyclingService.parse(def: def, year: year, main: html, stagePages: stageHTML, finished: finished)
        }.value
    }

    static func invalidate(_ def: TourDef, year: Int) async {
        if let url = wikiURL("\(year) \(def.wiki)") { await HTTP.shared.invalidate(url) }
    }

    // MARK: Parsing

    private static let riderRe = try! NSRegularExpression(pattern: #"^(.*?)\s*\(([A-Z]{3})\)\s*$"#)

    static func splitRider(_ s: String) -> (String, String?) {
        let ns = s as NSString
        if let m = riderRe.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) {
            return (ns.substring(with: m.range(at: 1)), ns.substring(with: m.range(at: 2)))
        }
        return (s, nil)
    }

    private static func riders(_ t: WikiTable) -> [RiderResult] {
        let teamOnly = t.column("rider") == nil
        let riderCol = t.column("rider") ?? t.column("team") ?? 1
        let teamCol = teamOnly ? nil : t.column("team")
        let valueCol = (t.rows.first?.count ?? 1) - 1
        return t.rows.dropFirst().compactMap { r in
            guard r.count > max(riderCol, valueCol), let rank = Int(r[0].trimmingCharacters(in: .whitespaces)) else { return nil }
            let (name, country) = splitRider(r[riderCol])
            return RiderResult(rank: rank, name: name, country: country, team: teamCol.map { r.count > $0 ? r[$0] : "" } ?? "", value: r[valueCol])
        }
    }

    private static func firstNumber(_ s: String) -> Int? {
        let digits = s.prefix { $0.isNumber }
        return Int(digits)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "d MMMM yyyy"
        return f
    }()

    static func parse(def: TourDef, year: Int, main: String, stagePages: [String], finished: Bool) -> Edition {
        let tables = WikiHTML.tables(in: main)

        // Infobox dates
        var dates: String?
        for t in tables {
            if let row = t.rows.first(where: { $0.first == "Dates" && $0.count > 1 }) { dates = row[1]; break }
        }

        // Stage list
        var stages: [CyclingStage] = []
        if let st = tables.first(where: { t in
            guard let h = t.rows.first, h.first?.lowercased().hasPrefix("stage") == true else { return false }
            return t.column("distance") != nil && t.column("winner") != nil
        }) {
            let dateCol = st.column("date")
            let courseCol = st.column("course") ?? st.column("route")
            let distCol = st.column("distance")
            let typeCols = st.columns("type")
            let winCol = st.column("winner")
            for r in st.rows.dropFirst() {
                guard let n = firstNumber(r.first ?? ""), r.count >= st.rows[0].count - 1 else { continue }
                func cell(_ i: Int?) -> String { guard let i, i < r.count else { return "" }; return r[i] }
                let course = cell(courseCol)
                let parts = course.components(separatedBy: " to ")
                let typeText = typeCols.map { cell($0) }.first { !$0.isEmpty } ?? ""
                let (winner, wc) = splitRider(cell(winCol))
                let kmText = cell(distCol).components(separatedBy: " km").first ?? ""
                stages.append(CyclingStage(
                    n: n,
                    date: dayFormatter.date(from: "\(cell(dateCol)) \(year)"),
                    start: parts.first ?? course,
                    finish: parts.count > 1 ? parts[1] : (parts.first ?? ""),
                    km: Double(kmText.trimmingCharacters(in: .whitespaces)),
                    kind: StageKind.from(typeText),
                    typeText: typeText,
                    winner: winner.isEmpty ? nil : winner,
                    winnerCountry: wc
                ))
            }
        }

        // Leaders after each stage
        if let lt = tables.first(where: { t in
            t.rows.first?.first?.lowercased().hasPrefix("stage") == true && t.column("general classification") != nil
        }) {
            let cols: [(JerseyKey, Int?)] = [(.gc, lt.column("general")), (.points, lt.column("points")),
                                             (.kom, lt.column("mountain")), (.youth, lt.column("young"))]
            for r in lt.rows.dropFirst() {
                guard let n = firstNumber(r.first ?? ""), let idx = stages.firstIndex(where: { $0.n == n }) else { continue }
                for (k, c) in cols {
                    if let c, c < r.count { stages[idx].leaders[k] = r[c] }
                }
            }
        }

        // Classifications (prefer "Final ..." tables)
        func classTable(_ needle: String) -> WikiTable? {
            let candidates = tables.filter {
                let c = $0.caption.lowercased()
                return c.contains(needle) && !c.contains("after stage") && !c.contains("leadership")
            }
            return candidates.first { $0.caption.lowercased().hasPrefix("final") } ?? candidates.first
        }
        var classifications: [JerseyKey: [RiderResult]] = [:]
        if let t = classTable("general classification") { classifications[.gc] = riders(t) }
        if let t = classTable("points classification") { classifications[.points] = riders(t) }
        if let t = classTable("mountains classification") ?? classTable("mountain classification") { classifications[.kom] = riders(t) }
        if let t = classTable("young rider classification") ?? classTable("youth classification") { classifications[.youth] = riders(t) }
        let teams = classTable("team classification").map(riders) ?? []
        let hasFinal = tables.contains { $0.caption.lowercased().hasPrefix("final general") }

        // Stage-by-stage results, GC after each stage, and reports
        for page in [main] + stagePages {
            for t in WikiHTML.tables(in: page) {
                let c = t.caption.lowercased()
                if c.hasPrefix("stage"), c.contains("result"), let n = firstNumber(String(c.dropFirst(6))),
                   let i = stages.firstIndex(where: { $0.n == n }) {
                    stages[i].result = riders(t)
                } else if c.contains("general classification after stage"),
                          let n = firstNumber(c.components(separatedBy: "after stage ").last ?? ""),
                          let i = stages.firstIndex(where: { $0.n == n }) {
                    stages[i].gcAfter = riders(t)
                }
            }
            for s in WikiHTML.sections(in: page) where s.title.lowercased().hasPrefix("stage") {
                guard let n = firstNumber(String(s.title.dropFirst(6))), let i = stages.firstIndex(where: { $0.n == n }) else { continue }
                // First paragraph repeats date/route/distance; keep the narrative.
                let paras = s.paragraphs.filter { !($0.contains(" km (") && $0.count < 140) }
                stages[i].report = paras
            }
        }

        // While a race is running there are no final tables yet: use latest GC.
        if classifications[.gc] == nil, let latest = stages.last(where: { !$0.gcAfter.isEmpty }) {
            classifications[.gc] = latest.gcAfter
        }

        return Edition(def: def, year: year, dates: dates, stages: stages, classifications: classifications,
                       teams: teams, finalStandings: hasFinal || finished)
    }
}
