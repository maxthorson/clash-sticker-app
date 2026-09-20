//
//  MemoryCache.swift
//
//  A lightweight, generic, in-memory cache built on top of NSCache.
//  Supports optional per-item TTL (expiration), cost-based eviction,
//  and automatic purge on memory pressure.
//
//  Add this file to your project and use `MemoryCache` anywhere you need
//  a fast, thread-safe cache. See usage examples below.
//

import Foundation

/// A generic, thread-safe in-memory cache using NSCache under the hood.
/// - Supports optional TTL (time-to-live) per item and a default TTL for the cache.
/// - Uses NSCache's cost and count limits for efficient eviction.
/// - Automatically purges on memory warnings (on iOS/tvOS/watchOS).
public final class MemoryCache<Key: Hashable, Value> {
    // MARK: - Wrapped key for NSCache (requires NSObject & NSCopying semantics)
    private final class WrappedKey: NSObject {
        let key: Key
        init(_ key: Key) { self.key = key }
        override var hash: Int { key.hashValue }
        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? WrappedKey else { return false }
            return other.key == key
        }
    }

    // MARK: - Cache entry with optional expiration
    private final class Entry {
        let value: Value
        let expirationDate: Date?
        init(value: Value, expirationDate: Date?) {
            self.value = value
            self.expirationDate = expirationDate
        }
        var isExpired: Bool {
            if let expirationDate { return expirationDate <= Date() }
            return false
        }
    }

    // MARK: - Properties
    private let cache = NSCache<WrappedKey, Entry>()
    private let lock = NSLock() // Synchronizes expiration checks & removals

    /// Optional default TTL applied when setting values without an explicit TTL.
    /// If `nil`, entries do not expire by time (but can still be evicted by NSCache).
    private let defaultTTL: TimeInterval?

    // MARK: - Init
    /// - Parameters:
    ///   - name: An optional name for diagnostics.
    ///   - countLimit: Maximum number of entries (0 = no limit).
    ///   - totalCostLimit: Aggregate cost limit in bytes or arbitrary units (0 = no limit).
    ///   - defaultTTL: Optional default TTL for entries. If `nil`, entries never expire by time.
    public init(name: String? = nil,
                countLimit: Int = 0,
                totalCostLimit: Int = 0,
                defaultTTL: TimeInterval? = nil) {
        self.defaultTTL = defaultTTL
        if let name { cache.name = name }
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit

        // Observe memory pressure to clear if needed (platform-dependent)
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        #elseif os(tvOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: NSNotification.Name.UIApplicationDidReceiveMemoryWarning,
            object: nil
        )
        #endif
    }

    deinit {
        #if canImport(UIKit)
        NotificationCenter.default.removeObserver(self)
        #endif
    }

    // MARK: - Public API

    /// Returns the value for `key` if present and not expired; otherwise `nil`.
    public func value(forKey key: Key) -> Value? {
        let wrappedKey = WrappedKey(key)
        lock.lock()
        defer { lock.unlock() }

        guard let entry = cache.object(forKey: wrappedKey) else { return nil }
        if entry.isExpired {
            cache.removeObject(forKey: wrappedKey)
            return nil
        }
        return entry.value
    }

    /// Sets a value for `key` with an optional cost and TTL.
    /// - Parameters:
    ///   - value: The value to cache.
    ///   - key: The cache key.
    ///   - cost: A relative cost used by NSCache for eviction (e.g., bytes for images).
    ///   - ttl: Time-to-live in seconds. If `nil`, uses `defaultTTL`. If both are `nil`, no time-based expiration.
    public func set(_ value: Value, forKey key: Key, cost: Int = 0, ttl: TimeInterval? = nil) {
        let expiration: Date?
        if let ttl = ttl ?? defaultTTL {
            expiration = Date().addingTimeInterval(ttl)
        } else {
            expiration = nil
        }
        let entry = Entry(value: value, expirationDate: expiration)
        let wrappedKey = WrappedKey(key)

        lock.lock()
        cache.setObject(entry, forKey: wrappedKey, cost: cost)
        lock.unlock()
    }

    /// Removes the value for the specified key, if it exists.
    public func removeValue(forKey key: Key) {
        let wrappedKey = WrappedKey(key)
        lock.lock()
        cache.removeObject(forKey: wrappedKey)
        lock.unlock()
    }

    /// Removes all values from the cache.
    public func removeAll() {
        lock.lock()
        cache.removeAllObjects()
        lock.unlock()
    }

    /// Trims any expired entries that are still resident in the cache.
    /// You can call this periodically if you rely on TTL.
    public func trimExpired() {
        // NSCache doesn't expose iteration; to trim expired entries proactively,
        // maintain a side index. To keep this lightweight, we skip proactive trim
        // and rely on read-time checks. This method is a no-op by default.
        // If you need aggressive trimming, consider extending this class to
        // track keys and scan them here.
    }

    // MARK: - Subscript convenience
    public subscript(key: Key) -> Value? {
        get { value(forKey: key) }
        set {
            if let newValue = newValue {
                set(newValue, forKey: key)
            } else {
                removeValue(forKey: key)
            }
        }
    }

    // MARK: - Memory pressure handling
    @objc private func handleMemoryWarning() {
        removeAll()
    }
}

// MARK: - UIKit convenience for image caching
#if canImport(UIKit)
import UIKit

/// A convenience alias for caching UIKit images keyed by URL or other hashable types.
public typealias ImageMemoryCache<Key: Hashable> = MemoryCache<Key, UIImage>
#endif

// MARK: - Usage Examples
/*
// Example: Create a cache with a default TTL of 5 minutes and a 50 MB cost limit
let imageCache = MemoryCache<URL, Data>(name: "ImageDataCache", totalCostLimit: 50 * 1024 * 1024, defaultTTL: 5 * 60)

// Store data (e.g., image bytes) with cost equal to its size
func cacheImageData(_ data: Data, for url: URL) {
    imageCache.set(data, forKey: url, cost: data.count)
}

// Retrieve
if let cached = imageCache.value(forKey: url) {
    // Use cached data
}

// Using subscript
imageCache[url] = data
let maybeData = imageCache[url]

// TTL per item override (e.g., 30 seconds)
imageCache.set(data, forKey: url, cost: data.count, ttl: 30)
*/
