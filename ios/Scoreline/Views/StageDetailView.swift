import SwiftUI

struct StageDetailView: View {
    let edition: Edition
    let stage: CyclingStage
    @State private var showGC = false

    var body: some View {
        let def = edition.def
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        KindBadge(kind: stage.kind)
                        if !stage.typeText.isEmpty { Text(stage.typeText).font(.caption).foregroundStyle(Theme.secondary) }
                    }
                    Text(stage.route).font(.title2.weight(.heavy))
                    HStack(spacing: 14) {
                        if let d = stage.date { Label(Fmt.dayLong(d), systemImage: "calendar") }
                        if let km = stage.km { Label(String(format: "%.1f km", km), systemImage: "ruler") }
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                }
                .card()
                .background(
                    LinearGradient(colors: [Color(hex: def.color).opacity(0.3), .clear], startPoint: .topLeading, endPoint: .center)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                )

                StageProfileCard(edition: edition, stage: stage)

                if let w = stage.winner {
                    HStack(spacing: 12) {
                        Image(systemName: "trophy.fill").font(.title2).foregroundStyle(.yellow)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Stage winner").font(.caption).foregroundStyle(Theme.secondary)
                            Text(w + (stage.winnerCountry.map { " (\($0)) " } ?? "")).font(.headline)
                        }
                    }
                    .card()
                }

                if !stage.leaders.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        CardTitle("Jerseys after stage \(stage.n)")
                        ForEach(def.jerseys, id: \.key) { j in
                            if let name = stage.leaders[j.key] {
                                HStack(spacing: 10) {
                                    JerseyBadge(color: j.color, size: 20)
                                    Text(j.label).font(.caption).foregroundStyle(Theme.secondary)
                                    Spacer()
                                    Text(name).font(.subheadline.weight(.semibold))
                                }
                            }
                        }
                    }
                    .card()
                }

                if !stage.result.isEmpty || !stage.gcAfter.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("", selection: $showGC) {
                            Text("Stage result").tag(false)
                            Text("GC after stage").tag(true)
                        }
                        .pickerStyle(.segmented)
                        VStack(alignment: .leading, spacing: 0) {
                            RiderList(riders: showGC ? stage.gcAfter : stage.result)
                        }
                        .card()
                    }
                }

                if !stage.report.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        CardTitle("Stage report")
                        ForEach(Array(stage.report.enumerated()), id: \.offset) { _, p in
                            Text(p).font(.subheadline).foregroundStyle(.white.opacity(0.9))
                        }
                    }
                    .card()
                }

                if !stage.isRaced {
                    MessageCard(text: "Results appear here after the stage finishes.")
                }
            }
            .padding(16)
        }
        .background(PageBackground())
        .navigationTitle("Stage \(stage.n)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Stage profile. Free sources don't publish elevation data, so this shows a
/// summary card for now; see `StageProfiles` for where images plug in.
struct StageProfileCard: View {
    let edition: Edition
    let stage: CyclingStage

    var body: some View {
        if let url = StageProfiles.imageURL(for: edition, stage: stage) {
            VStack(alignment: .leading, spacing: 8) {
                CardTitle("Profile")
                CachedImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFit()
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    case .failure:
                        Text("Profile image unavailable.").font(.footnote).foregroundStyle(Theme.secondary)
                    default:
                        ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
            }
            .card()
        }
    }
}

enum StageProfiles {
    /// Returns a profile image URL when a source is known for this stage.
    static func imageURL(for edition: Edition, stage: CyclingStage) -> URL? {
        nil
    }
}
