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
                // Show the last result for this page at once, then refresh it.
                value = LoaderMemory.get(id) as? T
                failure = nil
            }
            while !Task.isCancelled {
                do {
                    let v = try await load()
                    if Task.isCancelled { return }
                    value = v
                    LoaderMemory.set(id, v)
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

/// Last loaded value per page, so going back or switching tabs is instant.
enum LoaderMemory {
    private final class Box { let value: Any; init(_ v: Any) { value = v } }
    private static let cache: NSCache<NSString, Box> = {
        let c = NSCache<NSString, Box>()
        c.countLimit = 200
        return c
    }()
    static func get(_ id: String) -> Any? { cache.object(forKey: id as NSString)?.value }
    static func set(_ id: String, _ value: Any) { cache.setObject(Box(value), forKey: id as NSString) }
    static func clear() { cache.removeAllObjects() }
}
