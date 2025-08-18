import Foundation
import Testing
@testable import Netify

@Suite("Plugin & Logging", .tags(.unit, .plugin, .logging, .fast))
struct PluginAndLoggingTests {
    struct Ping: NetifyRequest { typealias ReturnType = EmptyResponse; var path: String { "/ping" } }

    @Test("willSend/didReceive 호출 시퀀스")
    func testPluginHooks() async throws {
        // Arrange
        let spy = SpyPlugin()
        let cfg = NetifyConfiguration(
            baseURL: "https://api.example.com",
            sensitiveHeaderKeys: ["authorization","cookie","x-api-key"], plugins: [spy]
        )
        let url = URL(string:"https://api.example.com/ping")!
        let session = MockNetworkSession(records: [
            .init(requestMatcher: { _ in true }, responder: { _ in (Data(), httpResponse(url: url, status: 200)) })
        ])
        let client = NetifyClient(configuration: cfg, networkSession: session)

        // Act
        let _ = try await client.send(Ping())

        // Assert - wait for async plugin operations to complete
        try await spy.waitForExpected(
            willSendCount: 1,
            didSuccessCount: 1, 
            didFailureCount: 0,
            lastURL: "https://api.example.com/ping"
        )
        
        // Final verification
        #expect((await spy.store.willSendCount) == 1)
        #expect((await spy.store.didSuccessCount) == 1)
        #expect((await spy.store.didFailureCount) == 0)
        #expect((await spy.store.lastURL)?.absoluteString == "https://api.example.com/ping")
    }

    @Test("cURL/헤더 마스킹 적용")
    func testMasking() {
        // Arrange
        var req = URLRequest(url: URL(string:"https://api.example.com/secure")!)
        req.setValue("Bearer secret", forHTTPHeaderField: HTTPHeaderField.authorization.rawValue)
        // Act
        let curl = req.toCurlCommand(masking: ["authorization"]) // 인자 우선
        // Assert
        #expect(curl.contains("Authorization: <masked>"))
        #expect(!curl.contains("secret"))
    }
}
