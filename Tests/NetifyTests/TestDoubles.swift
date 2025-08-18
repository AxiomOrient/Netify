import Foundation
import Testing
@testable import Netify

// MARK: - Mock NetworkSession
@available(iOS 15, macOS 12, *)
struct MockNetworkSession: NetworkSessionProtocol, Sendable {
    struct Record: Sendable {
        let requestMatcher: @Sendable (URLRequest) -> Bool
        let responder: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    }
    let records: [Record]

    func data(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws -> (Data, URLResponse) {
        for r in records where r.requestMatcher(request) {
            return try await r.responder(request)
        }
        throw URLError(.unsupportedURL)
    }
}

// MARK: - Mock Auth Providers
@available(iOS 15, macOS 12, *)
struct MockAuthProvider: AuthenticationProvider {
    let authenticateImpl: @Sendable (URLRequest) async throws -> URLRequest
    let refreshImpl: @Sendable () async throws -> Bool
    let expiredImpl: @Sendable (Error) -> Bool

    func authenticate(request: URLRequest) async throws -> URLRequest { try await authenticateImpl(request) }
    func refreshAuthentication() async throws -> Bool { try await refreshImpl() }
    func isAuthenticationExpired(from error: Error) -> Bool { expiredImpl(error) }
}

// MARK: - Mock Metrics
@available(iOS 15, macOS 12, *)
struct MockMetrics: NetworkMetrics, Sendable {
    actor Store {
        var requests: [(path: String, method: String, duration: TimeInterval, status: Int?, retry: Int)] = []
        var errors: [(path: String, method: String, error: NetworkRequestError)] = []
        func appendRequest(path: String, method: String, duration: TimeInterval, status: Int?, retry: Int) {
            requests.append((path, method, duration, status, retry))
        }
        func appendError(path: String, method: String, error: NetworkRequestError) {
            errors.append((path, method, error))
        }
    }
    let store = Store()

    func recordRequest(path: String,
                       method: String,
                       duration: TimeInterval,
                       status: Int?,
                       retryCount: Int) {
        Task { await store.appendRequest(path: path, method: method, duration: duration, status: status, retry: retryCount) }
    }

    func recordError(path: String,
                     method: String,
                     error: NetworkRequestError) {
        Task { await store.appendError(path: path, method: method, error: error) }
    }
}

// MARK: - Mock Plugin
@available(iOS 15, macOS 12, *)
struct SpyPlugin: NetifyPlugin {
    actor Store {
        var willSendCount = 0
        var didSuccessCount = 0
        var didFailureCount = 0
        var lastURL: URL?
        func recordWillSend(url: URL?) { willSendCount += 1; lastURL = url }
        func recordSuccess() { didSuccessCount += 1 }
        func recordFailure() { didFailureCount += 1 }
    }
    let store = Store()

    func willSend(_ request: URLRequest) {
        Task { await store.recordWillSend(url: request.url) }
    }
    func didReceive(_ result: Result<(Data, URLResponse), NetworkRequestError>, for request: URLRequest) {
        Task {
            switch result {
            case .success: await store.recordSuccess()
            case .failure: await store.recordFailure()
            }
        }
    }
}

// MARK: - Test Helper for waiting async operations
@available(iOS 15, macOS 12, *)
extension SpyPlugin {
    func waitForExpected(willSendCount expectedWillSend: Int,
                        didSuccessCount expectedSuccess: Int,
                        didFailureCount expectedFailure: Int,
                        lastURL expectedURL: String?,
                        timeout: TimeInterval = 0.2) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        
        while Date() < deadline {
            let currentWillSend = await store.willSendCount
            let currentSuccess = await store.didSuccessCount  
            let currentFailure = await store.didFailureCount
            let currentURL = await store.lastURL?.absoluteString
            
            if currentWillSend == expectedWillSend &&
               currentSuccess == expectedSuccess &&
               currentFailure == expectedFailure &&
               currentURL == expectedURL {
                return
            }
            
            await Task.yield()
            try await Task.sleep(nanoseconds: 1_000_000) // 1ms
        }
    }
}

// MARK: - Mock Response Cache (actor)
@available(iOS 15, macOS 12, *)
actor MockResponseCache: ResponseCache {
    typealias Entry = (status: Int, headers: HTTPHeaders, data: Data, storedAt: Date)
    private var store: [String: Entry] = [:]

    func read(key: String) async -> Entry? { store[key] }
    func write(key: String, status: Int, headers: HTTPHeaders, data: Data, storedAt: Date) async {
        store[key] = (status, headers, data, storedAt)
    }
    func remove(key: String) async { store[key] = nil }
}

// Helpers
@available(iOS 15, macOS 12, *)
func httpResponse(url: URL, status: Int, headers: [String:String] = [:]) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
}
