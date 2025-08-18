import Foundation
import Testing
@testable import Netify

@Suite("NetifyClient Retry", .tags(.unit, .retry, .fast))
struct NetifyClientRetryTests {
    struct P: NetifyRequest { typealias ReturnType = EmptyResponse; var path: String { "/p" } }

    actor Counter { var value = 0; func inc() { value += 1 }; func get() -> Int { value } }

    @Test("503 재시도 (maxRetryCount=2)")
    func testServerRetry() async throws {
        let url = URL(string:"https://api.example.com/p")!
        let counter = Counter()
        let session = MockNetworkSession(records: [
            .init(requestMatcher: { _ in true }, responder: { _ in
                let current = await counter.get()
                await counter.inc()
                if current < 2 { return (Data(), httpResponse(url: url, status: 503)) }
                return (Data(), httpResponse(url: url, status: 200))
            })
        ])
        let cfg = NetifyConfiguration(baseURL: "https://api.example.com", maxRetryCount: 2)
        let client = NetifyClient(configuration: cfg, networkSession: session)
        _ = try await client.send(P())
        #expect((await counter.get()) == 3) // 최초 1 + 재시도 2
    }

    @Test("429 Retry-After=0 즉시 재시도")
    func testRetryAfterImmediate() async throws {
        let url = URL(string:"https://api.example.com/p")!
        let hits = Counter()
        let session = MockNetworkSession(records: [
             .init(requestMatcher: { _ in true }, responder: { _ in
                let current = await hits.get()
                await hits.inc()
                if current == 0 {
                    return (Data(), httpResponse(url: url, status: 429, headers: ["Retry-After":"0"]))
                }
                return (Data(), httpResponse(url: url, status: 200))
            })
        ])
        let cfg = NetifyConfiguration(baseURL: "https://api.example.com", maxRetryCount: 1)
        let client = NetifyClient(configuration: cfg, networkSession: session)
        _ = try await client.send(P())
        #expect((await hits.get()) == 2)
    }
}
