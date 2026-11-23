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
        Loader(id: "davis-\(title)", load: { try await DavisCup.load(title, finished: finished) }) { ties in
            VStack(alignment: .leading, spacing: 14) {
                if ties.isEmpty { MessageCard(text: "The draw isn’t on Wikipedia yet.") }
                let rounds = ties.map(\.round).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                ForEach(rounds, id: \.self) { round in
                    SectionHeader(title: round)
                    VStack(spacing: 0) {
                        ForEach(Array(ties.filter { $0.round == round }.enumerated()), id: \.element.id) { i, tie in
                            if i > 0 { Divider().overlay(Theme.separator) }
                            TieRow(tie: tie)
                        }
                    }
                    .card(padding: 14)
                }
            }
        }
    }
}

private struct TieRow: View {
    let tie: DavisTie
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.snappy) { open.toggle() } } label: {
                VStack(spacing: 6) {
                    HStack {
                        nation(tie.teamA, alignment: .leading)
                        Text("vs").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondary)
                        nation(tie.teamB, alignment: .trailing)
                    }
                    Text(tie.venue).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.8)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(tie.rubbers.isEmpty)
            if open {
                ForEach(Array(tie.rubbers.enumerated()), id: \.offset) { _, r in
                    Text(r.joined(separator: "  ")).font(.footnote).monospacedDigit()
                        .padding(.vertical, 4)
                        .overlay(alignment: .top) { Divider().overlay(Theme.separator) }
                }
            }
        }
    }

    private func nation(_ name: String, alignment: HorizontalAlignment) -> some View {
        HStack(spacing: 8) {
            if alignment == .trailing { Spacer(minLength: 0) }
            if alignment == .leading, let f = DavisCup.flag(name) { flagImage(f) }
            Text(name).font(.headline).lineLimit(1).minimumScaleFactor(0.75)
                .foregroundStyle(name == "TBD" ? Theme.secondary : .white)
            if alignment == .trailing, let f = DavisCup.flag(name) { flagImage(f) }
            if alignment == .leading { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity)
    }

    private func flagImage(_ url: URL) -> some View {
        AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Theme.card2 }
            .frame(width: 28, height: 19)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
