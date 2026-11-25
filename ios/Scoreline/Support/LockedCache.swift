import Foundation

/// A dictionary that is safe to read and write from several tasks at once.
/// (Plain static dictionaries written by concurrent loads can crash the app.)
final class LockedCache<Key: Hashable, Value>: @unchecked Sendable {
    private var storage: [Key: Value] = [:]
    private let lock = NSLock()

    subscript(key: Key) -> Value? {
        get { lock.lock(); defer { lock.unlock() }; return storage[key] }
        set { lock.lock(); storage[key] = newValue; lock.unlock() }
    }

    func removeAll() { lock.lock(); storage.removeAll(); lock.unlock() }
}
