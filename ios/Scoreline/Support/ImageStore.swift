import CryptoKit
import SwiftUI
import UIKit

/// Image cache for logos, flags and photos.
///
/// Decoded images stay in memory, the downloaded files on disk for 30 days.
/// Repeated requests for the same URL share one download, and a cached image
/// is shown in the same frame (no placeholder flash when scrolling back).
final class ImageStore: @unchecked Sendable {
    static let shared = ImageStore()

    private let memory = NSCache<NSURL, UIImage>()
    private let dir: URL
    private let session: URLSession
    private let inflight = InFlight()
    private let maxAge: TimeInterval = 86_400 * 30
    private let lock = NSLock()
    private var missing = Set<URL>()   // 4xx responses this session (e.g. absent dark logos)

    /// UIImage wrapper so it can cross tasks.
    final class Box: @unchecked Sendable {
        let image: UIImage?
        init(_ image: UIImage?) { self.image = image }
    }

    private actor InFlight {
        var tasks: [URL: Task<Box, Never>] = [:]
        func task(_ url: URL, make: @Sendable @escaping () async -> Box) -> Task<Box, Never> {
            if let t = tasks[url] { return t }
            let t = Task { await make() }
            tasks[url] = t
            return t
        }
        func done(_ url: URL) { tasks[url] = nil }
    }

    init() {
        memory.countLimit = 600
        memory.totalCostLimit = 96 << 20
        dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        config.httpMaximumConnectionsPerHost = 8
        config.httpAdditionalHeaders = ["User-Agent": "Scoreline/1.0 (iOS; personal non-commercial app)"]
        session = URLSession(configuration: config)
    }

    private func file(_ url: URL) -> URL {
        dir.appendingPathComponent(SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined())
    }

    /// True if the server said this image doesn't exist (checked once per launch).
    func isMissing(_ url: URL) -> Bool { lock.lock(); defer { lock.unlock() }; return missing.contains(url) }
    private func markMissing(_ url: URL) { lock.lock(); missing.insert(url); lock.unlock() }

    /// The image if it is already decoded in memory.
    func cached(_ url: URL) -> UIImage? { memory.object(forKey: url as NSURL) }

    /// Memory, then disk, then network. Returns nil if the image can't be loaded.
    func image(_ url: URL) async -> UIImage? {
        if let img = cached(url) { return img }
        if isMissing(url) { return nil }
        let task = await inflight.task(url) { [self] in Box(await self.fetch(url)) }
        let box = await task.value
        await inflight.done(url)
        return box.image
    }

    /// Downloads images ahead of time (e.g. all team logos of a league).
    func prefetch(_ urls: [URL]) {
        Task.detached(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                for u in Set(urls) where self.cached(u) == nil {
                    group.addTask { _ = await self.image(u) }
                }
            }
        }
    }

    private func decode(_ data: Data) -> UIImage? {
        guard let img = UIImage(data: data) else { return nil }
        return img.preparingForDisplay() ?? img
    }

    private func store(_ img: UIImage, _ url: URL) {
        let cost = Int(img.size.width * img.size.height * img.scale * img.scale * 4)
        memory.setObject(img, forKey: url as NSURL, cost: cost)
    }

    private func fetch(_ url: URL) async -> UIImage? {
        let f = file(url)
        let attrs = try? FileManager.default.attributesOfItem(atPath: f.path)
        let age = (attrs?[.modificationDate] as? Date).map { Date().timeIntervalSince($0) }
        if let age, age < maxAge, let data = try? Data(contentsOf: f), let img = decode(data) {
            store(img, url)
            return img
        }
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                if (400..<500).contains(http.statusCode) { markMissing(url) }
                throw FetchError.status(http.statusCode)
            }
            guard let img = decode(data) else { markMissing(url); return nil }
            try? data.write(to: f, options: .atomic)
            store(img, url)
            return img
        } catch {
            // Offline: an expired copy is better than nothing.
            if let data = try? Data(contentsOf: f), let img = decode(data) {
                store(img, url)
                return img
            }
            return nil
        }
    }

    func clear() {
        memory.removeAllObjects()
        lock.lock(); missing.removeAll(); lock.unlock()
        for f in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: f)
        }
    }
}

enum CachedImagePhase {
    case empty
    case success(Image)
    case failure
}

/// Drop-in replacement for AsyncImage backed by ImageStore.
struct CachedImage<Content: View>: View {
    let url: URL?
    @ViewBuilder let content: (CachedImagePhase) -> Content

    @State private var loaded: (url: URL, image: UIImage?)?

    init(url: URL?, @ViewBuilder content: @escaping (CachedImagePhase) -> Content) {
        self.url = url
        self.content = content
    }

    private var phase: CachedImagePhase {
        guard let url else { return .failure }
        if let img = ImageStore.shared.cached(url) { return .success(Image(uiImage: img)) }
        if ImageStore.shared.isMissing(url) { return .failure }
        if let loaded, loaded.url == url {
            return loaded.image.map { .success(Image(uiImage: $0)) } ?? .failure
        }
        return .empty
    }

    var body: some View {
        content(phase)
            .task(id: url) {
                guard let url, ImageStore.shared.cached(url) == nil else { return }
                let img = await ImageStore.shared.image(url)
                if !Task.isCancelled { loaded = (url, img) }
            }
    }
}

extension CachedImage {
    /// Same shape as `AsyncImage(url:content:placeholder:)`.
    init<I: View, P: View>(url: URL?,
                           @ViewBuilder content: @escaping (Image) -> I,
                           @ViewBuilder placeholder: @escaping () -> P) where Content == CachedImageContent<I, P> {
        self.init(url: url) { phase in CachedImageContent(phase: phase, image: content, placeholder: placeholder) }
    }
}

struct CachedImageContent<I: View, P: View>: View {
    let phase: CachedImagePhase
    let image: (Image) -> I
    let placeholder: () -> P

    var body: some View {
        if case .success(let img) = phase { image(img) } else { placeholder() }
    }
}
