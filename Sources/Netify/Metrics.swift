import Foundation

@available(iOS 15, macOS 12, *)
public protocol NetworkMetrics: Sendable {
    func recordRequest(path: String, method: String, duration: TimeInterval, status: Int?, retryCount: Int)
    func recordError(path: String, method: String, error: NetworkRequestError)
}

@available(iOS 15, macOS 12, *)
public struct NoopMetrics: NetworkMetrics {
    public init() {}
    public func recordRequest(path: String, method: String, duration: TimeInterval, status: Int?, retryCount: Int) {}
    public func recordError(path: String, method: String, error: NetworkRequestError) {}
}
