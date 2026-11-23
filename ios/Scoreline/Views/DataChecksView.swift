import SwiftUI

/// Settings → Check data sources: runs DataChecks and lists the results.
struct DataChecksView: View {
    @State private var results: [DataCheckResult] = []
    @State private var running = false
    private let total = DataChecks.all.count

    var body: some View {
        List {
            Section {
                Button(running ? "Checking… \(results.count)/\(total)" : "Run checks") { Task { await run() } }
                    .disabled(running)
                if !results.isEmpty && !running {
                    let failed = results.filter { !$0.ok }.count
                    Label(failed == 0 ? "All \(results.count) checks passed" : "\(failed) of \(results.count) checks failed",
                          systemImage: failed == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(failed == 0 ? .green : .orange)
                }
            } footer: {
                Text("Tests every data source and parser the app uses against the live services. A failure usually means a website changed its format.")
            }
            ForEach(groups, id: \.self) { g in
                Section(g) {
                    ForEach(results.filter { $0.group == g }) { r in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: r.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(r.ok ? .green : .red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name).font(.subheadline.weight(.semibold))
                                Text(r.detail).font(.caption).foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                            Text(String(format: "%.1fs", r.seconds)).font(.caption2).foregroundStyle(Theme.secondary).monospacedDigit()
                        }
                    }
                }
            }
        }
        .navigationTitle("Data sources")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var groups: [String] {
        var seen = Set<String>()
        let present = Set(results.map(\.group))
        return DataChecks.all.map(\.group).filter { present.contains($0) && seen.insert($0).inserted }
    }

    private func run() async {
        running = true
        results = []
        let final = await DataChecks.runAll { r in results.append(r) }
        results = final
        running = false
    }
}
