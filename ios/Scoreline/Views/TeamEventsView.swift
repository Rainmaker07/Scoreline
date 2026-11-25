import SwiftUI

struct LaverCupView: View {
    let year: Int
    let finished: Bool

    var body: some View {
        Loader(id: "laver-\(year)", load: { try await LaverCup.load(year: year, finished: finished) }) { d in
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(spacing: 4) {
                        Text("Team Europe").font(.subheadline.weight(.semibold))
                        Text("\(d.europe)").font(.score(52)).foregroundStyle(d.europe >= d.world ? .white : Theme.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    Text("–").font(.title).foregroundStyle(Theme.secondary)
                    VStack(spacing: 4) {
                        Text("Team World").font(.subheadline.weight(.semibold))
                        Text("\(d.world)").font(.score(52)).foregroundStyle(d.world >= d.europe ? .white : Theme.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .card()
                if d.matches.isEmpty { MessageCard(text: "The order of play hasn’t been published yet.") }
                let days = Array(Set(d.matches.map(\.day))).sorted()
                ForEach(days, id: \.self) { day in
                    VStack(alignment: .leading, spacing: 0) {
                        CardTitle(day.isEmpty ? "Matches" : "Day \(day)")
                        ForEach(Array(d.matches.filter { $0.day == day }.enumerated()), id: \.element.id) { i, m in
                            if i > 0 { Divider().overlay(Theme.separator) }
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(m.type).font(.caption).foregroundStyle(Theme.secondary)
                                    Spacer()
                                    if !m.pointsAfter.isEmpty { Text(m.pointsAfter).font(.caption.weight(.bold)).foregroundStyle(Theme.secondary) }
                                }
                                side("🇪🇺", m.europe, won: m.europeWon == true, lost: m.europeWon == false)
                                side("🌎", m.world, won: m.europeWon == false, lost: m.europeWon == true)
                                if !m.score.isEmpty { Text(m.score).font(.subheadline.weight(.semibold)).monospacedDigit() }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .card()
                }
            }
        }
    }

    private func side(_ flag: String, _ names: String, won: Bool, lost: Bool) -> some View {
        HStack(spacing: 8) {
            Text(flag)
            Text(names).font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
                .foregroundStyle(lost ? Theme.secondary : .white)
            if won { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Theme.win) }
        }
    }
}

struct DavisCupView: View {
    let title: String
    let finished: Bool

    var body: some View {
        // During the Finals week Wikipedia is re-read every few minutes.
        Loader(id: "davis-\(title)", poll: { _ in finished ? nil : 300 },
               load: { try await DavisCup.load(title, finished: finished) }) { ties in
            VStack(alignment: .leading, spacing: 14) {
                if ties.isEmpty { MessageCard(text: "The draw isn’t on Wikipedia yet.") }
                let rounds = ties.map(\.round).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                if rounds.count > 1 { DavisBracket(rounds: rounds, ties: ties) }
                ForEach(rounds, id: \.self) { round in
                    SectionHeader(title: round)
                    VStack(spacing: 0) {
                        ForEach(Array(ties.filter { $0.round == round }.enumerated()), id: \.element.id) { i, tie in
                            if i > 0 { Divider().overlay(Theme.separator) }
                            NavigationLink {
                                DavisTieView(tie: tie)
                            } label: {
                                TieRow(tie: tie)
                            }
                            .buttonStyle(.plain)
                            .disabled(!tie.decided)
                        }
                    }
                    .card(padding: 14)
                }
                Text(finished ? "Results from Wikipedia." : "From Wikipedia, refreshed every 5 minutes during the event.")
                    .font(.caption2).foregroundStyle(Theme.tertiary)
            }
        }
    }
}

/// Quarterfinals → Semifinals → Final side by side; scroll sideways.
private struct DavisBracket: View {
    let rounds: [String]
    let ties: [DavisTie]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: 12) {
                ForEach(rounds, id: \.self) { round in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(round.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(Theme.secondary)
                        ForEach(ties.filter { $0.round == round }) { tie in
                            cell(tie)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(.vertical, 4)
        }
        .card(padding: 12)
    }

    private func cell(_ tie: DavisTie) -> some View {
        let s = tie.score
        return VStack(alignment: .leading, spacing: 4) {
            line(tie.teamA, code: tie.codeA, score: tie.parsed.isEmpty ? nil : s.a, won: tie.winner == 0, lost: tie.winner == 1)
            line(tie.teamB, code: tie.codeB, score: tie.parsed.isEmpty ? nil : s.b, won: tie.winner == 1, lost: tie.winner == 0)
        }
        .padding(8)
        .frame(width: 112, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func line(_ name: String, code: String, score: Int?, won: Bool, lost: Bool) -> some View {
        HStack(spacing: 6) {
            if let f = DavisCup.flag(name) {
                CachedImage(url: f) { $0.resizable().scaledToFill() } placeholder: { Theme.card2 }
                    .frame(width: 20, height: 14).clipShape(RoundedRectangle(cornerRadius: 2))
            } else {
                Color.clear.frame(width: 20, height: 14)
            }
            Text(name == "TBD" ? "TBD" : code).font(.footnote.weight(won ? .heavy : .semibold))
                .foregroundStyle(lost || name == "TBD" ? Theme.secondary : .white)
            Spacer(minLength: 2)
            if let score { Text("\(score)").font(.footnote.weight(.heavy)).monospacedDigit() }
        }
    }
}

/// A tie: both nations with flags, the tie score and its status.
private struct TieRow: View {
    let tie: DavisTie

    var body: some View {
        let s = tie.score
        let started = !tie.parsed.filter { !$0.sets.isEmpty }.isEmpty
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                nation(tie.teamA, alignment: .leading, dim: tie.winner == 1)
                if started {
                    Text("\(s.a)–\(s.b)").font(.title2.weight(.heavy)).monospacedDigit()
                } else {
                    Text("vs").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondary)
                }
                nation(tie.teamB, alignment: .trailing, dim: tie.winner == 0)
            }
            HStack(spacing: 6) {
                if started && tie.winner == nil {
                    LivePulse(); Text("Live").foregroundStyle(Theme.live)
                    if let r = tie.parsed.first(where: { !$0.sets.isEmpty && $0.winner == nil }) {
                        Text("· \(r.doubles ? "Doubles" : "Singles \(r.number)")").foregroundStyle(Theme.secondary)
                    }
                } else if tie.winner != nil {
                    Text("Final").foregroundStyle(Theme.secondary)
                }
                Text(Fmt.venueAndDate(tie.venue)).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.caption)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func nation(_ name: String, alignment: HorizontalAlignment, dim: Bool) -> some View {
        HStack(spacing: 8) {
            if alignment == .trailing { Spacer(minLength: 0) }
            if alignment == .leading, let f = DavisCup.flag(name) { flagImage(f) }
            Text(name).font(.headline.weight(dim ? .regular : .bold)).lineLimit(1).minimumScaleFactor(0.75)
                .foregroundStyle(name == "TBD" || dim ? Theme.secondary : .white)
            if alignment == .trailing, let f = DavisCup.flag(name) { flagImage(f) }
            if alignment == .leading { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity)
    }

    private func flagImage(_ url: URL) -> some View {
        CachedImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Theme.card2 }
            .frame(width: 28, height: 19)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}


/// One tie: the rubbers with players, flags and set scores (tiebreak points small).
struct DavisTieView: View {
    let tie: DavisTie

    var body: some View {
        let s = tie.score
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    side(tie.teamA)
                    Text(tie.parsed.isEmpty ? "vs" : "\(s.a)–\(s.b)").font(.system(size: 40, weight: .heavy)).monospacedDigit()
                    side(tie.teamB)
                }
                .padding(.top, 12)
                Text("\(tie.round) · \(Fmt.venueAndDate(tie.venue))").font(.footnote).foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
                if tie.parsed.isEmpty {
                    MessageCard(text: "The rubbers appear once the nominations are announced.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(tie.parsed.enumerated()), id: \.offset) { i, r in
                            if i > 0 { Divider().overlay(Theme.separator) }
                            rubber(r)
                        }
                    }
                    .card(padding: 14)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .background(PageBackground())
        .navigationTitle("\(tie.codeA) v \(tie.codeB)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func side(_ name: String) -> some View {
        VStack(spacing: 6) {
            if let f = DavisCup.flag(name) {
                CachedImage(url: f) { $0.resizable().scaledToFill() } placeholder: { Theme.card2 }
                    .frame(width: 54, height: 36).clipShape(RoundedRectangle(cornerRadius: 5))
            }
            Text(name).font(.subheadline.weight(.bold)).lineLimit(2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func rubber(_ r: DavisRubber) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(r.doubles ? "DOUBLES" : "SINGLES \(r.number)").font(.caption2.weight(.bold)).foregroundStyle(Theme.secondary)
            playerLine(r.playersA, won: r.winner == 0, games: r.sets.map { ($0.0, $0.1, $0.2) })
            playerLine(r.playersB, won: r.winner == 1, games: r.sets.map { ($0.1, $0.0, $0.2) })
        }
        .padding(.vertical, 8)
    }

    private func playerLine(_ players: [String], won: Bool, games: [(Int, Int, Int?)]) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(players, id: \.self) { p in
                    Text(p).font(.subheadline.weight(won ? .bold : .regular)).foregroundStyle(won ? .white : Theme.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            if won { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Theme.win) }
            Spacer(minLength: 6)
            ForEach(Array(games.enumerated()), id: \.offset) { _, g in
                HStack(alignment: .top, spacing: 0) {
                    Text("\(g.0)").font(.headline.weight(g.0 > g.1 ? .heavy : .regular)).monospacedDigit()
                        .foregroundStyle(g.0 > g.1 ? .white : Theme.secondary)
                    if let tb = g.2, g.0 < g.1 { Text("\(tb)").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.secondary) }
                }
                .frame(minWidth: 22)
            }
        }
    }
}
