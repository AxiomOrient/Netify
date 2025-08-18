import Foundation

@available(iOS 15, macOS 12, *)
public enum NetifyCachePolicy: Sendable {
    case none
    case etag              // If-None-Match 기반
    case ttl(seconds: TimeInterval)
    case etagOrTtl(seconds: TimeInterval)
}

@available(iOS 15, macOS 12, *)
public protocol ResponseCache: Sendable {
    /// actor 구현체와의 호환을 위해 async로 정의합니다.
    func read(key: String) async -> (status: Int, headers: HTTPHeaders, data: Data, storedAt: Date)?
    func write(key: String, status: Int, headers: HTTPHeaders, data: Data, storedAt: Date) async
    func remove(key: String) async
}

@available(iOS 15, macOS 12, *)
public actor InMemoryResponseCache: ResponseCache {
    private struct Entry { let status: Int; let headers: HTTPHeaders; let data: Data; let storedAt: Date }
    private var store: [String: Entry] = [:]
    public init() {}
    public func read(key: String) -> (status: Int, headers: HTTPHeaders, data: Data, storedAt: Date)? {
        guard let e = store[key] else { return nil }
        return (e.status, e.headers, e.data, e.storedAt)
    }
    public func write(key: String, status: Int, headers: HTTPHeaders, data: Data, storedAt: Date) {
        store[key] = Entry(status: status, headers: headers, data: data, storedAt: storedAt)
    }
    public func remove(key: String) {
        store[key] = nil
    }
}

@available(iOS 15, macOS 12, *)
internal struct CacheKey {
    static func make(method: String, url: URL, varyHeaders: [String] = []) -> String {
        let base = "\(method.uppercased()) \(url.absoluteString)"
        if varyHeaders.isEmpty { return base }
        return base + " " + varyHeaders.joined(separator: "|")
    }
}
