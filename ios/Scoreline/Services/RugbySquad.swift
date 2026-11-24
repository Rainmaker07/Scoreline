import Foundation

/// Premiership squads from each club's Wikipedia article ("Current squad").
/// ESPN publishes no rugby rosters.
enum RugbySquad {
    /// ESPN team name -> Wikipedia article.
    static let articles: [String: String] = [
        "Bath Rugby": "Bath Rugby", "Bristol Rugby": "Bristol Bears", "Bristol Bears": "Bristol Bears",
        "Exeter Chiefs": "Exeter Chiefs", "Gloucester Rugby": "Gloucester Rugby", "Harlequins": "Harlequin F.C.",
        "Leicester Tigers": "Leicester Tigers", "Newcastle Falcons": "Newcastle Red Bulls",
        "Newcastle Red Bulls": "Newcastle Red Bulls", "Northampton Saints": "Northampton Saints",
        "Sale Sharks": "Sale Sharks", "Saracens": "Saracens F.C.",
    ]

    /// Position groups in the order they are listed.
    static let groups: [(name: String, keys: [String])] = [
        ("Props", ["prop"]), ("Hookers", ["hooker"]), ("Locks", ["lock", "second row"]),
        ("Back row", ["flanker", "number 8", "number eight", "back row"]), ("Scrum-halves", ["scrum"]),
        ("Fly-halves", ["fly"]), ("Centres", ["centre", "center"]), ("Wings", ["wing"]), ("Full-backs", ["full"]),
    ]

    static let flags: [String: String] = [
        "england": "🏴󠁧󠁢󠁥󠁮󠁧󠁿", "scotland": "🏴󠁧󠁢󠁳󠁣󠁴󠁿", "wales": "🏴󠁧󠁢󠁷󠁬󠁳󠁿", "ireland": "🇮🇪", "france": "🇫🇷",
        "italy": "🇮🇹", "south africa": "🇿🇦", "new zealand": "🇳🇿", "australia": "🇦🇺", "argentina": "🇦🇷",
        "fiji": "🇫🇯", "samoa": "🇼🇸", "tonga": "🇹🇴", "georgia": "🇬🇪", "japan": "🇯🇵", "united states": "🇺🇸",
        "usa": "🇺🇸", "canada": "🇨🇦", "uruguay": "🇺🇾", "portugal": "🇵🇹", "spain": "🇪🇸", "namibia": "🇳🇦",
        "zimbabwe": "🇿🇼", "chile": "🇨🇱", "romania": "🇷🇴", "germany": "🇩🇪", "netherlands": "🇳🇱", "kenya": "🇰🇪",
    ]

    static func group(for position: String) -> String {
        let p = position.lowercased()
        return groups.first { g in g.keys.contains { p.contains($0) } }?.name ?? "Squad"
    }

    static func load(teamName: String) async -> [RosterPlayer] {
        let title = articles[teamName] ?? teamName
        guard let url = CyclingService.wikiURL(title),
              let html = try? await HTTP.shared.text(url, maxAge: 86_400) else { return [] }
        // The current squad section (not academy, not former players).
        let chunk = WikiHTML.chunks(in: html).first {
            let t = $0.title.lowercased()
            return t.contains("squad") && !t.contains("academy") && !t.contains("former")
        }
        guard let chunk else { return [] }
        var players: [RosterPlayer] = []
        for t in WikiHTML.tables(in: chunk.html) {
            guard let pc = t.column("player"), let posc = t.column("position") else { continue }
            let uc = t.column("union") ?? t.column("nation")
            for r in t.rows.dropFirst() where r.count > max(pc, posc) {
                let name = r[pc].replacingOccurrences(of: #"\s*\(.*?\)"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                let pos = r[posc]
                guard !name.isEmpty, !pos.isEmpty, name.lowercased() != "player" else { continue }
                let union = uc.flatMap { $0 < r.count ? r[$0] : nil } ?? ""
                let flag = flags[union.lowercased()] ?? ""
                players.append(RosterPlayer(
                    id: name, name: name, jersey: nil, position: pos, age: nil, height: nil, headshot: nil,
                    group: group(for: pos),
                    statLine: [pos, union.isEmpty ? nil : "\(flag) \(union)".trimmingCharacters(in: .whitespaces)]
                        .compactMap { $0 }.joined(separator: " · ")
                ))
            }
        }
        // Keep the position order, one entry per player.
        var seen = Set<String>()
        players = players.filter { seen.insert($0.name).inserted }
        let order = groups.map(\.name) + ["Squad"]
        return players.sorted { (order.firstIndex(of: $0.group ?? "") ?? 99) < (order.firstIndex(of: $1.group ?? "") ?? 99) }
    }

    /// What the club article contains (for the data checks when no squad is found).
    static func diagnose(teamName: String) async -> String {
        let title = articles[teamName] ?? teamName
        guard let url = CyclingService.wikiURL(title) else { return "bad title" }
        guard let html = try? await HTTP.shared.text(url, maxAge: 86_400) else { return "\(title): page not loaded" }
        let chunks = WikiHTML.chunks(in: html)
        let squadish = chunks.filter { $0.title.lowercased().contains("squad") || $0.title.lowercased().contains("player") }
        var parts: [String] = ["\(title): \(chunks.count) sections"]
        for c in squadish.prefix(4) {
            let tables = WikiHTML.tables(in: c.html)
            let heads = tables.prefix(3).map { "[" + ($0.rows.first ?? []).prefix(5).joined(separator: "/") + "] r\($0.rows.count)" }
            parts.append("'\(c.title)': \(tables.count) tables \(heads.joined(separator: " "))")
        }
        if squadish.isEmpty { parts.append("sections: " + chunks.prefix(25).map(\.title).joined(separator: ", ")) }
        return parts.joined(separator: " ; ")
    }
}
