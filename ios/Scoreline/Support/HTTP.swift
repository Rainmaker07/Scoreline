import CryptoKit
import Foundation

enum FetchError: LocalizedError {
    case status(Int)
    case parse(String)

    var errorDescription: String? {
        switch self {
        case .status(let c): return "Server returned \(c)"
        case .parse(let m): return m
        }
    }
}

/// Fetches URLs with a two-level cache (memory + disk).
///
/// - `maxAge`: how long a cached copy counts as fresh.
/// - `permanent`: store in Application Support instead of Caches, so iOS never
///   purges it (used for finished cycling races, which never change again).
///
/// If the network fails, any cached copy is returned regardless of age, so the
/// app keeps working offline.
actor HTTP {
    static let shared = HTTP()

    private let session: URLSession
    private var memory: [String: (date: Date, data: Data)] = [:]
    private let cacheDir: URL
    private let permanentDir: URL

    init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = [
            "User-Agent": "Scoreline/1.0 (iOS; personal non-commercial app)",
        ]
        session = URLSession(configuration: config)

        let fm = FileManager.default
        cacheDir = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("http", isDirectory: true)
        permanentDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("http", isDirectory: true)
        try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: permanentDir, withIntermediateDirectories: true)
    }

    private func key(_ url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func diskCopy(_ k: String) -> (date: Date, data: Data)? {
        for dir in [permanentDir, cacheDir] {
            let file = dir.appendingPathComponent(k)
            if let data = try? Data(contentsOf: file),
               let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
               let date = attrs[.modificationDate] as? Date {
                return (date, data)
            }
        }
        return nil
    }

    func data(_ url: URL, maxAge: TimeInterval, permanent: Bool = false) async throws -> Data {
        let k = key(url)
        if let hit = memory[k], Date().timeIntervalSince(hit.date) < maxAge { return hit.data }
        let disk = diskCopy(k)
        if let disk, Date().timeIntervalSince(disk.date) < maxAge {
            memory[k] = disk
            return disk.data
        }
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw FetchError.status(http.statusCode)
            }
            memory[k] = (Date(), data)
            let dir = permanent ? permanentDir : cacheDir
            try? data.write(to: dir.appendingPathComponent(k), options: .atomic)
            return data
        } catch {
            if let disk { return disk.data } // offline fallback
            throw error
        }
    }

    func json(_ url: URL, maxAge: TimeInterval) async throws -> J {
        try J(data: await data(url, maxAge: maxAge))
    }

    func text(_ url: URL, maxAge: TimeInterval, permanent: Bool = false) async throws -> String {
        let d = try await data(url, maxAge: maxAge, permanent: permanent)
        return String(decoding: d, as: UTF8.self)
    }

    /// Removes every cached response (memory, Caches and Application Support).
    func clearAll() {
        memory.removeAll()
        let fm = FileManager.default
        for dir in [cacheDir, permanentDir] {
            for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] { try? fm.removeItem(at: f) }
        }
    }

    /// Removes cached copies so the next request goes to the network.
    func invalidate(_ url: URL) {
        let k = key(url)
        memory[k] = nil
        try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent(k))
        try? FileManager.default.removeItem(at: permanentDir.appendingPathComponent(k))
    }
}
