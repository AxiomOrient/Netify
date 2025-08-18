import Foundation

@available(iOS 15, macOS 12, *)
public protocol NetifyPlugin: Sendable {
    func willSend(_ request: URLRequest)
    func didReceive(_ result: Result<(Data, URLResponse), NetworkRequestError>, for request: URLRequest)
}

@available(iOS 15, macOS 12, *)
public struct NoopPlugin: NetifyPlugin {
    public init() {}
    public func willSend(_ request: URLRequest) {}
    public func didReceive(_ result: Result<(Data, URLResponse), NetworkRequestError>, for request: URLRequest) {}
}

