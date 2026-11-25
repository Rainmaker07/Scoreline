import Foundation

// MARK: - UCI WorldTour calendar

struct WTRace: Identifiable, Hashable {
    var id: String { "\(year)-\(name)" }
    let name: String
    let year: Int
    let dates: String
    let start: Date?
    let end: Date?
    let winner: String?
    let country: String?

    /// Only the Giro, the Tour de France and the Vuelta (not every race with "Tour" in its name).
    var isGrandTour: Bool {
        let n = name.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        return ["giro d'italia", "giro d’italia", "tour de france", "vuelta a espana", "la vuelta"].contains { n.hasPrefix($0) }
    }
    var isOneDay: Bool { start != nil && start == end }
    var isMonument: Bool {
        ["milan–san remo", "milan-san remo", "tour of flanders", "paris–roubaix", "paris-roubaix", "liège–bastogne–liège",
         "liege–bastogne–liege", "il lombardia", "giro di lombardia"].contains { name.lowercased().contains($0) }
    }
    var isLive: Bool { if let s = start, let e = end { return Date() >= s && Date() <= e.addingTimeInterval(86_399) } else { return false } }
    var wikiTitle: String { "\(year) \(name)" }
}

struct OneDayResult {
    let name: String
    let year: Int
    let dates: String?
    let distance: String?
    let results: [RiderResult]
    let summary: [String]
}

enum WorldTour {
    static func calendar(_ year: Int) async throws -> [WTRace] {
        let past = year < Calendar.current.component(.year, from: Date())
        guard let url = CyclingService.wikiURL("\(year) UCI World Tour") else { return [] }
        let html = try await HTTP.shared.text(url, maxAge: past ? 86_400 * 60 : 21_600, permanent: past)
        return await Task.detached(priority: .userInitiated) { () -> [WTRace] in
            let tables = WikiHTML.tables(in: html)
            guard let t = tables.first(where: { ($0.column("race") != nil || $0.column("event") != nil) && $0.column("date") != nil }) else { return [] }
            let raceCol = t.column("race") ?? t.column("event") ?? 0
            let dateCol = t.column("date")
            let winCol = t.column("winner")
            var out: [WTRace] = []
            for r in t.rows.dropFirst() {
                guard r.count > raceCol else { continue }
                var name = r[raceCol]
                var country: String?
                if let m = name.range(of: #"\s*\(([A-Z]{3})\)\s*$"#, options: .regularExpression) {
                    country = String(name[m]).trimmingCharacters(in: CharacterSet(charactersIn: " ()"))
                    name.removeSubrange(m)
                }
                if name.isEmpty || name.lowercased() == "race" { continue }
                let dates = dateCol.flatMap { r.count > $0 ? r[$0] : nil } ?? ""
                let (s, e) = WorldTour.parseDates(dates, year: year)
                let winner = winCol.flatMap { r.count > $0 ? CyclingService.splitRider(r[$0]).0 : nil }
                out.append(WTRace(name: name, year: year, dates: dates, start: s, end: e,
                                  winner: (winner?.isEmpty ?? true) ? nil : winner, country: country))
            }
            return out
        }.value
    }

    /// "21–26 January", "18 March", "30 March – 5 April"
    static func parseDates(_ s: String, year: Int) -> (Date?, Date?) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "d MMMM yyyy"
        let clean = s.replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-")
        let parts = clean.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let lastPart = parts.last, let end = f.date(from: "\(lastPart) \(year)") else { return (nil, nil) }
        if parts.count == 1 { return (end, end) }
        let month = lastPart.split(separator: " ").dropFirst().joined(separator: " ")
        let first = parts[0].contains(" ") ? parts[0] : "\(parts[0]) \(month)"
        return (f.date(from: "\(first) \(year)") ?? end, end)
    }

    /// A one-day race's result (top 10) from its Wikipedia article.
    static func oneDay(_ race: WTRace) async throws -> OneDayResult {
        guard let url = CyclingService.wikiURL(race.wikiTitle) else { throw FetchError.parse("Bad title") }
        let finished = (race.end ?? Date()) < Date().addingTimeInterval(-86_400 * 3)
        let html = try await HTTP.shared.text(url, maxAge: finished ? 86_400 * 365 : 1800, permanent: finished)
        return await Task.detached(priority: .userInitiated) { () -> OneDayResult in
            let tables = WikiHTML.tables(in: html)
            let result = tables.first { t in
                let c = t.caption.lowercased()
                return (c.contains("result") || c.contains("classification")) && t.column("rider") != nil
            } ?? tables.first { $0.column("rider") != nil && $0.column("rank") != nil }
            var distance: String?
            for t in tables {
                if let row = t.rows.first(where: { $0.first == "Distance" && $0.count > 1 }) { distance = row[1]; break }
            }
            let paras = WikiHTML.sections(in: html).first { $0.title.lowercased() == "race summary" || $0.title.lowercased() == "summary" }?.paragraphs ?? []
            return OneDayResult(name: race.name, year: race.year, dates: race.dates, distance: distance,
                                results: result.map(CyclingService.riderResults) ?? [], summary: paras)
        }.value
    }

    /// A stage race's TourDef so the Grand Tour loader can parse it.
    static func def(for race: WTRace) -> TourDef {
        if let gt = TourDef.all.first(where: { race.name.lowercased().contains($0.wiki.lowercased()) }) { return gt }
        let month = race.end.map { Calendar.current.component(.month, from: $0) } ?? 12
        return TourDef(id: race.name.lowercased().replacingOccurrences(of: " ", with: "-"), name: race.name, short: race.name,
                       wiki: race.name, color: "5a4a00", endMonth: month, jerseys: [
                           JerseyDef(key: .gc, label: "Leader", color: "ffd60a"),
                           JerseyDef(key: .points, label: "Points", color: "22c55e"),
                           JerseyDef(key: .kom, label: "Mountains", color: "ef4444"),
                           JerseyDef(key: .youth, label: "Young rider", color: "f2f2f2"),
                       ])
    }
}

// MARK: - Riders and teams (Wikipedia)

struct RiderProfile {
    let name: String
    let description: String?
    let image: URL?
    let info: [InfoRow]
    let currentTeam: String?
    let teams: [(years: String, team: String)]
    let majorWins: [(category: String, items: [String])]
    let extract: String?
    /// What was looked up (for the data checks).
    var trace: String = ""
}

struct CyclingTeamProfile {
    let name: String
    let image: URL?
    let info: [InfoRow]
    let roster: WikiTable?
    let wins: WikiTable?
    let extract: String?
    /// What was looked up (for the data checks).
    var trace: String = ""
}

enum CyclingPeople {
    static func rider(_ name: String) async throws -> RiderProfile {
        guard let url = CyclingService.wikiURL(name) else { throw FetchError.parse("Bad name") }
        let html = try await HTTP.shared.text(url, maxAge: 86_400 * 3)
        let summary = await Wiki.summary(name)
        return await Task.detached(priority: .userInitiated) { () -> RiderProfile in
            let infobox = WikiHTML.tables(in: html).first { $0.rows.contains { $0.first == "Born" || $0.first == "Current team" } }
            var info: [InfoRow] = []
            var teams: [(years: String, team: String)] = []
            var current: String?
            var inTeams = false
            for r in infobox?.rows ?? [] {
                guard r.count >= 2 else { continue }
                let k = r[0], v = r[1]
                if k == v { inTeams = k.lowercased().contains("professional team") || k.lowercased().contains("amateur team"); continue }
                if k.isEmpty { inTeams = false; continue }
                if inTeams { teams.append((years: k, team: v)); continue }
                switch k {
                case "Born":
                    let cleaned = v.replacingOccurrences(of: #"^\(\d{4}-\d{2}-\d{2}\)\s*"#, with: "", options: .regularExpression)
                    info.append(InfoRow(label: "Born", value: cleaned))
                case "Height", "Weight":
                    info.append(InfoRow(label: k, value: v.components(separatedBy: " (").first ?? v))
                case "Current team":
                    current = v
                case "Rider type", "Discipline", "Nickname":
                    info.append(InfoRow(label: k, value: v))
                default: break
                }
            }
            return RiderProfile(name: summary?.title ?? name, description: summary?.description, image: summary?.image,
                                info: info, currentTeam: current, teams: Array(teams.reversed()),
                                majorWins: CyclingPeople.majorWins(html), extract: summary?.extract)
        }.value
    }

    /// Parses the infobox "Major wins" block: categories → "Race: item (years)".
    static func majorWins(_ html: String) -> [(category: String, items: [String])] {
        guard let start = html.range(of: "Major wins") else { return [] }
        let tail = html[start.upperBound...]
        let end = tail.range(of: "Medal record")?.lowerBound ?? tail.range(of: "</tbody>")?.lowerBound ?? tail.endIndex
        let block = String(tail[..<end])
        var out: [(category: String, items: [String])] = []
        var category = ""
        var race = ""
        var items: [String] = []
        // Tokens: category (<b> at top or <p><b>), race header (<dd><b>…</b><dl>), item (<dd>…</dd>), end of race (</dl></dd>).
        let re = try! NSRegularExpression(pattern: #"<p><b>((?:(?!</b>).)*?)</b></p>|<td[^>]*><b>((?:(?!</b>).)*?)</b>|<dd><b>((?:(?!</b>).)*?)</b>\s*<dl>|</dl></dd>|<dd>((?:(?!<dl>|<dd>).)*?)</dd>"#,
                                          options: [.dotMatchesLineSeparators])
        let ns = block as NSString
        for m in re.matches(in: block, range: NSRange(location: 0, length: ns.length)) {
            func g(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : WikiHTML.clean(ns.substring(with: m.range(at: i))) }
            if let c = g(1) ?? g(2) {
                if !items.isEmpty { out.append((category: category, items: items)) }
                category = c; items = []; race = ""
            } else if let r = g(3) {
                race = r
            } else if let item = g(4) {
                items.append(race.isEmpty ? item : "\(race): \(item)")
            } else {
                race = ""
            }
        }
        if !items.isEmpty { out.append((category: category, items: items)) }
        return out.filter { !$0.category.isEmpty }
    }

    /// Team names in results -> Wikipedia article (the plain names are ambiguous or redirects).
    static let teamArticles: [String: String] = [
        "Lidl–Trek": "Lidl–Trek (men's team)", "Lidl-Trek": "Lidl–Trek (men's team)", "Movistar Team": "Movistar Team (men's team)",
        "Movistar": "Movistar Team (men's team)", "Visma–Lease a Bike": "Visma–Lease a Bike (men's team)", "Team Visma–Lease a Bike": "Visma–Lease a Bike (men's team)",
        "Netcompany INEOS": "Ineos Grenadiers", "INEOS Grenadiers": "Ineos Grenadiers", "Ineos Grenadiers": "Ineos Grenadiers",
        "Decathlon CMA CGM": "Decathlon CMA CGM Team", "Decathlon AG2R La Mondiale": "Decathlon CMA CGM Team", "Soudal–Quick-Step": "Soudal–Quick-Step",
        "Alpecin–Deceuninck": "Alpecin–Premier Tech", "Alpecin–Premier Tech": "Alpecin–Premier Tech", "Groupama–FDJ": "Groupama–FDJ United",
        "Groupama–FDJ United": "Groupama–FDJ United", "Intermarché–Wanty": "Intermarché–Wanty", "XDS Astana Team": "XDS Astana Team",
        "Astana Qazaqstan Team": "XDS Astana Team", "Astana": "XDS Astana Team", "Picnic PostNL": "Team Picnic PostNL",
        "Team Picnic PostNL": "Team Picnic PostNL", "Jayco–AlUla": "Team Jayco–AlUla", "Jayco AlUla": "Team Jayco–AlUla",
        "Arkéa–B&B Hotels": "Arkéa–B&B Hotels", "Arkea–B&B Hotels": "Arkéa–B&B Hotels", "Team Jayco–AlUla": "Team Jayco–AlUla",
        "Cofidis": "Cofidis (cycling team)", "Uno-X Mobility": "Uno-X Mobility", "Tudor Pro Cycling Team": "Tudor Pro Cycling Team",
    ]

    /// Other article names to try (the team was renamed or the article has a suffix).
    static let teamAlternatives: [String: [String]] = [
        "Visma–Lease a Bike": ["Team Visma–Lease a Bike (men's team)", "Team Visma–Lease a Bike"],
        "Team Visma–Lease a Bike": ["Team Visma–Lease a Bike (men's team)", "Team Visma–Lease a Bike"],
        "Lidl–Trek": ["Lidl–Trek"], "Lidl-Trek": ["Lidl–Trek"],
        "Netcompany INEOS": ["Netcompany–Ineos", "Ineos Grenadiers"],
        "Decathlon CMA CGM": ["Decathlon CMA CGM", "Decathlon–AG2R La Mondiale", "Decathlon AG2R La Mondiale", "Decathlon–AG2R La Mondiale Team", "AG2R Citroën Team"],
        "Pinarello–Q36.5 Pro Cycling Team": ["Q36.5 Pro Cycling Team", "Pinarello–Q36.5"],
        "Movistar Team": ["Movistar Team"], "Movistar": ["Movistar Team"],
    ]

    private static func isMen(_ s: Wiki.Summary, for name: String) -> Bool {
        !s.title.lowercased().contains("women") || name.lowercased().contains("women")
    }

    /// The team's Wikipedia article: known mapping, else the name if it is a cycling team,
    /// else a search for "<name> cycling team". Never the women's team for a men's team name.
    static func teamArticle(_ name: String) async -> (title: String, summary: Wiki.Summary?) {
        let candidates = [teamArticles[name]].compactMap { $0 } + (teamAlternatives[name] ?? [])
        for t in candidates {
            if let s = await Wiki.summary(t), isMen(s, for: name) { return (s.title, s) }
        }
        if let s = await Wiki.summary(name), (s.description ?? "").lowercased().contains("cycl"), isMen(s, for: name) { return (s.title, s) }
        if let q = "\(name) men's cycling team".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "https://en.wikipedia.org/w/rest.php/v1/search/page?q=\(q)&limit=6"),
           let j = try? await HTTP.shared.json(url, maxAge: 86_400 * 7),
           let page = j["pages"].array.first(where: {
               ($0["description"].string ?? "").lowercased().contains("cycl") && !($0["title"].string ?? "").lowercased().contains("women")
           }),
           let t = page["title"].string {
            return (t, await Wiki.summary(t))
        }
        return (name, nil)
    }

    private static func plain(_ s: String) -> String {
        s.replacingOccurrences(of: #"\s*\(.*\)$"#, with: "", options: .regularExpression)
    }

    static func team(_ name: String) async throws -> CyclingTeamProfile {
        let year = Calendar.current.component(.year, from: Date())
        let (title, summary) = await teamArticle(name)
        var info: [InfoRow] = []
        var logo: URL?
        var trace: [String] = ["article '\(title)'"]
        if let url = CyclingService.wikiURL(title), let html = try? await HTTP.shared.text(url, maxAge: 86_400 * 3) {
            // Only real logos (some articles lead with a team photo or the jersey).
            logo = WikiLogo.infoboxLogo(in: html, strict: true, title: plain(title))
                ?? WikiLogo.infoboxLogo(in: html).flatMap { $0.pathExtension.lowercased() == "png" ? $0 : nil }
            trace.append("images " + WikiLogo.infoboxImages(in: html).prefix(4).joined(separator: ",") + " {\(WikiLogo.imageDebug(in: html))}")
            let box = WikiHTML.tables(in: html).first { $0.rows.contains { ["UCI code", "Registered", "Founded"].contains($0.first ?? "") } }
            for r in box?.rows ?? [] where r.count >= 2 && r[0] != r[1] && !r[0].isEmpty {
                if ["UCI code", "Registered", "Founded", "Discipline", "Status", "Bicycles", "General manager", "Team manager(s)", "Team manager", "Based"].contains(r[0]) {
                    info.append(InfoRow(label: r[0], value: r[1]))
                }
            }
        } else {
            trace.append("article not loaded")
        }
        var roster: WikiTable?
        var wins: WikiTable?
        // Season articles: "2026 Lidl–Trek season", sometimes with the suffix or an older name.
        var names: [String] = []
        for n in [plain(title), title, plain(name), name] + (teamAlternatives[name] ?? []).flatMap({ [plain($0), $0] })
        where !names.contains(n) { names.append(n) }
        search: for y in [year, year - 1] {
            for n in names {
                guard let url = CyclingService.wikiURL("\(y) \(n) season") else { continue }
                guard let html = try? await HTTP.shared.text(url, maxAge: 86_400) else { continue }
                let tables = WikiHTML.tables(in: html)
                let r = tables.first { $0.column("rider") != nil && ($0.column("born") != nil || $0.column("date of birth") != nil) }
                    ?? tables.first { $0.column("rider") != nil && ($0.column("age") != nil || $0.column("nationality") != nil) }
                let w = tables.first { $0.column("race") != nil && $0.column("rider") != nil && $0.column("date") != nil }
                trace.append("'\(y) \(n) season': \(tables.count) tables, roster \(r != nil), wins \(w != nil)")
                if r == nil && w == nil {
                    trace.append("heads " + tables.prefix(5).map { ($0.rows.first ?? []).prefix(4).joined(separator: "/") }.joined(separator: " | "))
                    continue
                }
                roster = r
                wins = w
                break search
            }
        }
        // No logo in the English article: Wikidata's logo image, then the German article.
        if logo == nil {
            logo = await WikiLogo.wikidataLogo(enwikiTitle: title)
        }
        if logo == nil {
            logo = await WikiLogo.eventLogo(english: "", germanQueries: [plain(title), plain(name) + " Radsportteam"])
        }
        return CyclingTeamProfile(name: plain(title), image: logo, info: info, roster: roster, wins: wins,
                                  extract: summary?.extract, trace: trace.joined(separator: "; "))
    }
}

extension CyclingService {
    /// Public wrapper around the rider table parser (rank, rider (CTY), team, value).
    static func riderResults(_ t: WikiTable) -> [RiderResult] {
        let riderCol = t.column("rider") ?? 1
        let teamCol = t.column("team")
        let valueCol = (t.rows.first?.count ?? 1) - 1
        return t.rows.dropFirst().compactMap { r in
            guard r.count > max(riderCol, valueCol), let rank = Int(r[0].trimmingCharacters(in: .whitespaces)) else { return nil }
            let (name, country) = splitRider(r[riderCol])
            return RiderResult(rank: rank, name: name, country: country, team: teamCol.map { r.count > $0 ? r[$0] : "" } ?? "", value: r[valueCol])
        }
    }
}
