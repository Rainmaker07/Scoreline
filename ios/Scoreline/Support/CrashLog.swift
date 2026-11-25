import Foundation
import MetricKit
import SwiftUI
import UIKit

/// Crash reports you can read in Settings → Crash Log and send with Copy / Share.
///
/// Two sources:
/// - Our own record: uncaught exceptions and fatal signals write a short report (with the
///   last screens visited) to a file at the moment of the crash.
/// - Apple's crash diagnostics (MetricKit), which iOS delivers on a later launch with the
///   full call stack.
enum CrashLog {
    struct Entry: Codable, Identifiable, Hashable {
        var id: String
        let date: Date
        let version: String
        let kind: String          // "Crash (SIGSEGV)", "Exception: NSRangeException", "Apple crash report"
        let summary: String
        let lastScreens: [String]
        let detail: String
    }

    // MARK: Files

    private static var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("CrashLog", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private static var entriesFile: URL { dir.appendingPathComponent("entries.json") }
    private static var pendingFile: URL { dir.appendingPathComponent("pending.txt") }
    private static let seenKey = "crashLogSeen"

    static func entries() -> [Entry] {
        guard let data = try? Data(contentsOf: entriesFile),
              let list = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return list.sorted { $0.date > $1.date }
    }

    private static func save(_ list: [Entry]) {
        if let data = try? JSONEncoder().encode(Array(list.sorted { $0.date > $1.date }.prefix(30))) {
            try? data.write(to: entriesFile, options: .atomic)
        }
    }

    static func add(_ e: Entry) {
        var list = entries()
        guard !list.contains(where: { $0.id == e.id }) else { return }
        list.append(e)
        save(list)
    }

    static func delete(_ e: Entry) { save(entries().filter { $0.id != e.id }) }
    static func clear() { save([]) }

    /// True when a crash was recorded that the banner hasn't shown yet.
    static var hasUnseen: Bool {
        guard let newest = entries().first else { return false }
        return UserDefaults.standard.string(forKey: seenKey) != newest.id
    }
    static func markSeen() {
        if let newest = entries().first { UserDefaults.standard.set(newest.id, forKey: seenKey) }
    }

    // MARK: Breadcrumbs (last screens)

    private static let lock = NSLock()
    private static var crumbs: [String] = []
    /// C buffer with the current breadcrumbs, written as-is by the signal handler.
    private static let crumbBufferSize = 4096
    nonisolated(unsafe) private static var crumbBuffer: UnsafeMutablePointer<CChar> = {
        let p = UnsafeMutablePointer<CChar>.allocate(capacity: 4096)
        p.initialize(repeating: 0, count: 4096)
        return p
    }()
    nonisolated(unsafe) private static var pendingFD: Int32 = -1

    static func crumb(_ s: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        lock.lock()
        crumbs.append("\(stamp) \(s)")
        if crumbs.count > 15 { crumbs.removeFirst(crumbs.count - 15) }
        let text = crumbs.joined(separator: "\n")
        _ = text.withCString { strncpy(crumbBuffer, $0, crumbBufferSize - 1) }
        lock.unlock()
    }

    static var lastScreens: [String] {
        lock.lock(); defer { lock.unlock() }
        return crumbs
    }

    // MARK: Install

    private static let metrics = MetricsSubscriber()

    static func install() {
        collectPending()
        // Opened now so the signal handler only has to write().
        pendingFD = open(pendingFile.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        NSSetUncaughtExceptionHandler { e in
            let text = "EXCEPTION \(e.name.rawValue): \(e.reason ?? "")\n"
                + e.callStackSymbols.prefix(40).joined(separator: "\n")
                + "\n---\n" + CrashLog.lastScreens.joined(separator: "\n")
            if let data = text.data(using: .utf8) { try? data.write(to: CrashLog.pendingFile) }
        }
        for sig in [SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGABRT, SIGFPE] {
            signal(sig) { s in
                // Async-signal-safe: plain write() of prepared buffers.
                let fd = CrashLog.pendingFD
                if fd >= 0 {
                    var header = "SIGNAL \(s)\n---\n"
                    header.withUTF8 { _ = write(fd, $0.baseAddress, $0.count) }
                    _ = write(fd, CrashLog.crumbBuffer, strlen(CrashLog.crumbBuffer))
                    close(fd)
                }
                signal(s, SIG_DFL)
                raise(s)
            }
        }
        MXMetricManager.shared.add(metrics)
    }

    /// Turns a report written during the last crash into a log entry.
    private static func collectPending() {
        guard let text = try? String(contentsOf: pendingFile, encoding: .utf8), !text.isEmpty else { return }
        let parts = text.components(separatedBy: "\n---\n")
        let head = parts.first ?? ""
        let screens = parts.count > 1 ? parts[1].split(separator: "\n").map(String.init) : []
        let firstLine = head.split(separator: "\n").first.map(String.init) ?? "Crash"
        let kind: String
        if firstLine.hasPrefix("SIGNAL ") {
            let n = Int32(firstLine.dropFirst(7)) ?? 0
            kind = "Crash (\(signalName(n)))"
        } else {
            kind = "Exception"
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: pendingFile.path)
        let date = (attrs?[.modificationDate] as? Date) ?? Date()
        add(Entry(id: "local-\(Int(date.timeIntervalSince1970))", date: date, version: AppVersion.display, kind: kind,
                  summary: firstLine.replacingOccurrences(of: "EXCEPTION ", with: ""),
                  lastScreens: screens, detail: head))
        try? FileManager.default.removeItem(at: pendingFile)
    }

    static func signalName(_ n: Int32) -> String {
        switch n {
        case SIGSEGV: return "SIGSEGV"
        case SIGBUS: return "SIGBUS"
        case SIGILL: return "SIGILL"
        case SIGTRAP: return "SIGTRAP"
        case SIGABRT: return "SIGABRT"
        case SIGFPE: return "SIGFPE"
        default: return "signal \(n)"
        }
    }

    /// Plain-text report for Copy / Share.
    static func report(_ e: Entry) -> String {
        var s = "Scoreline crash report\n"
        s += "Date: \(e.date.formatted(date: .abbreviated, time: .standard))\n"
        s += "Version: \(e.version)\n"
        s += "Device: \(UIDevice.current.model), iOS \(UIDevice.current.systemVersion)\n"
        s += "Type: \(e.kind)\n"
        s += "Summary: \(e.summary)\n"
        if !e.lastScreens.isEmpty { s += "\nLast screens:\n" + e.lastScreens.joined(separator: "\n") + "\n" }
        s += "\nDetails:\n" + e.detail
        return s
    }
}

/// Receives Apple's crash diagnostics (delivered on a later launch).
final class MetricsSubscriber: NSObject, MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for p in payloads {
            for c in p.crashDiagnostics ?? [] {
                let sig = c.signal.map { CrashLog.signalName($0.int32Value) } ?? "?"
                let exc = c.exceptionType.map { "exception \($0)" } ?? ""
                let reason = c.terminationReason ?? ""
                let stack = String(data: c.callStackTree.jsonRepresentation(), encoding: .utf8) ?? ""
                let version = "\(c.metaData.applicationBuildVersion)"
                let date = p.timeStampEnd
                CrashLog.add(CrashLog.Entry(
                    id: "mx-\(Int(date.timeIntervalSince1970))-\(sig)", date: date, version: version,
                    kind: "Apple crash report (\(sig))",
                    summary: [exc, reason].filter { !$0.isEmpty }.joined(separator: " · ").isEmpty ? sig
                        : [exc, reason].filter { !$0.isEmpty }.joined(separator: " · "),
                    lastScreens: [], detail: String(stack.prefix(60_000))))
            }
        }
    }
}

// MARK: - Views

struct CrashLogView: View {
    @State private var entries = CrashLog.entries()

    var body: some View {
        List {
            if entries.isEmpty {
                Text("No crashes recorded. If the app crashes, the report appears here on the next launch.")
                    .foregroundStyle(Theme.secondary)
            }
            ForEach(entries) { e in
                NavigationLink {
                    CrashReportView(entry: e)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(e.kind).font(.subheadline.weight(.semibold))
                        Text("\(e.date.formatted(date: .abbreviated, time: .shortened)) · \(e.version)")
                            .font(.caption).foregroundStyle(Theme.secondary)
                        if let last = e.lastScreens.last {
                            Text("Last screen: \(last)").font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                        }
                    }
                }
            }
            .onDelete { idx in
                for i in idx { CrashLog.delete(entries[i]) }
                entries = CrashLog.entries()
            }
        }
        .navigationTitle("Crash Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !entries.isEmpty {
                Button("Clear") { CrashLog.clear(); entries = [] }
            }
        }
        .onAppear { CrashLog.markSeen() }
    }
}

struct CrashReportView: View {
    let entry: CrashLog.Entry
    @State private var copied = false

    var body: some View {
        let text = CrashLog.report(entry)
        ScrollView {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .navigationTitle(entry.kind)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(copied ? "Copied" : "Copy") {
                    UIPasteboard.general.string = text
                    copied = true
                }
                ShareLink(item: text) { Image(systemName: "square.and.arrow.up") }
            }
        }
    }
}
