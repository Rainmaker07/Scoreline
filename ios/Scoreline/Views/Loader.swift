import SwiftUI

/// Loads a value when `id` changes, optionally re-polling on an interval that
/// depends on the last result (e.g. faster while a game is live).
struct Loader<T, Content: View>: View {
    let id: String
    var poll: (T) -> TimeInterval? = { _ in nil }
    let load: () async throws -> T
    @ViewBuilder let content: (T) -> Content

    @State private var value: T?
    @State private var failure: String?
    @State private var loadedID: String?

    var body: some View {
        Group {
            if let value {
                content(value)
            } else if let failure {
                MessageCard(text: "Couldn’t load: \(failure)", isError: true)
            } else {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(30)
            }
        }
        .task(id: id) {
            if loadedID != id {
                value = nil
                failure = nil
            }
            while !Task.isCancelled {
                do {
                    let v = try await load()
                    if Task.isCancelled { return }
                    value = v
                    failure = nil
                    loadedID = id
                    guard let next = poll(v) else { return }
                    try await Task.sleep(nanoseconds: UInt64(next * 1_000_000_000))
                } catch {
                    if Task.isCancelled { return }
                    if value == nil { failure = error.localizedDescription }
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                }
            }
        }
    }
}
