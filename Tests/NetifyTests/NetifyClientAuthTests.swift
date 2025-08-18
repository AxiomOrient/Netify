import Foundation
import Testing
@testable import Netify

@Suite("NetifyClient Auth Flow", .tags(.unit, .auth, .fast))
struct NetifyClientAuthTests {
    struct Me: NetifyRequest { typealias ReturnType = EmptyResponse; var path: String { "/me" }; var requiresAuthentication: Bool { true } }

    actor Counter { var value = 0; func inc() { value += 1 } }
    actor Flag { private var v = false; func set(_ b: Bool) { v = b }; func get() -> Bool { v } }

    @Test("401 → refresh 1회 → 성공")
    func testAuthRefreshOnce() async throws {
        let url = URL(string:"https://api.example.com/me")!
        let refreshCount = Counter()
        let authed = Flag()

        let auth = MockAuthProvider(
            authenticateImpl: { req in
                var r = req
                let isAuthed = await authed.get()
                r.setValue("Bearer \(isAuthed ? "NEW" : "OLD")", forHTTPHeaderField: HTTPHeaderField.authorization.rawValue)
                return r
            },
            refreshImpl: {
                await refreshCount.inc()
                await authed.set(true)
                return true
            },
            expiredImpl: { err in
                if case .unauthorized = (err as? NetworkRequestError) { return true }
                return false
            }
        )

        let session = MockNetworkSession(records: [
            .init(requestMatcher: { _ in true }, responder: { _ in
            if await authed.get() { return (Data(), httpResponse(url: url, status: 200)) }
            return (Data(), httpResponse(url: url, status: 401))
        })
        ])

        let cfg = NetifyConfiguration(baseURL: "https://api.example.com", authenticationProvider: auth)
        let client = NetifyClient(configuration: cfg, networkSession: session)
        _ = try await client.send(Me())
        #expect((await refreshCount.value) == 1)
    }

    @Test("401 → refresh 실패 → 401 유지")
    func testAuthRefreshFailReturnsOriginal() async {
        let url = URL(string:"https://api.example.com/me")!
        let auth = MockAuthProvider(
            authenticateImpl: { req in
                var r = req; r.setValue("Bearer OLD", forHTTPHeaderField: HTTPHeaderField.authorization.rawValue); return r
            },
            refreshImpl: { false },
            expiredImpl: { err in if case .unauthorized = (err as? NetworkRequestError) { return true } ; return false }
        )
        let session = MockNetworkSession(records: [
            .init(requestMatcher: { _ in true }, responder: { _ in (Data(), httpResponse(url: url, status: 401)) })
        ])
        let cfg = NetifyConfiguration(baseURL: "https://api.example.com", authenticationProvider: auth)
        let client = NetifyClient(configuration: cfg, networkSession: session)
        await #expect(throws: NetworkRequestError.self) { _ = try await client.send(Me()) }
    }
}

