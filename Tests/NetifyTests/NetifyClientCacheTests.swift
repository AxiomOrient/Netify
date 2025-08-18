import Foundation
import Testing
@testable import Netify

@Suite("NetifyClient Cache", .tags(.unit, .cache, .fast))
struct NetifyClientCacheTests {
    struct User: Codable, Sendable { let id: Int }
    struct GetUser: NetifyRequest { typealias ReturnType = User; var path: String { "/users/1" } }

    @Test("TTL 캐시 히트")
    func testTTLHit() async throws {
        let url = URL(string:"https://api.example.com/users/1")!
        let cache = MockResponseCache()
        let cfg = NetifyConfiguration(baseURL: "https://api.example.com", cache: .ttl(seconds: 60), responseCache: cache)
        let client = NetifyClient(configuration: cfg, networkSession: MockNetworkSession(records: []))

        let payload = try JSONEncoder().encode(User(id: 1))
        await cache.write(key: CacheKey.make(method: "GET", url: url), status: 200, headers: [:], data: payload, storedAt: Date())

        let u = try await client.send(GetUser())
        #expect(u.id == 1)
    }

    @Test("ETag → If-None-Match → 304 캐시 반환")
    func testEtag304Flow() async throws {
        let url = URL(string:"https://api.example.com/users/1")!
        let expected = User(id: 10)
        let data = try JSONEncoder().encode(expected)

        // 첫 호출: 200 + ETag
        // 두 번째 호출: 304 (If-None-Match가 포함됐는지 확인)
        actor Obs { private var v: String? = nil; func set(_ s: String?) { v = s }; func get() -> String? { v } }
        actor Flag { private var v: Bool; init(_ initial: Bool) { v = initial } ; func set(_ b: Bool) { v = b } ; func get() -> Bool { v } }
        let obs = Obs()
        let first = Flag(true)
        let session = MockNetworkSession(records: [
            .init(requestMatcher: { _ in true }, responder: { req in
                if await first.get() {
                    await first.set(false)
                    return (data, httpResponse(url: url, status: 200, headers: ["ETag":"tag-xyz", "Content-Type":"application/json"]))
                } else {
                    await obs.set(req.value(forHTTPHeaderField: "If-None-Match"))
                    return (Data(), httpResponse(url: url, status: 304))
                }
            })
        ])
        let cfg = NetifyConfiguration(baseURL: "https://api.example.com", cache: .etag, responseCache: MockResponseCache())
        let client = NetifyClient(configuration: cfg, networkSession: session)

        let _ = try await client.send(GetUser())           // 200 + 캐시 저장
        let u2 = try await client.send(GetUser())          // 304 → 캐시 반환
        #expect((await obs.get()) == "tag-xyz")
        #expect(u2.id == 10)
    }

    @Test("Vary: Accept-Language 분기")
    func testVaryAcceptLanguage() async throws {
        struct Article: Codable, Sendable { let id: Int; let title: String }
        struct GetArticle: NetifyRequest { typealias ReturnType = Article; var path: String { "/articles/1" } }

        let url = URL(string:"https://api.example.com/articles/1")!
        let session = MockNetworkSession(records: [
            .init(requestMatcher: { _ in true }, responder: { req in
                let lang = req.value(forHTTPHeaderField: "Accept-Language") ?? "en"
                let payload = try JSONEncoder().encode(Article(id: 1, title: lang))
                let resp = httpResponse(url: url, status: 200, headers: ["Vary":"Accept-Language", "Content-Type":"application/json"])
                return (payload, resp)
            })
        ])
        let cache = MockResponseCache()
        let cfg = NetifyConfiguration(baseURL: "https://api.example.com", cache: .ttl(seconds: 60), responseCache: cache)
        let client = NetifyClient(configuration: cfg, networkSession: session)

        let a1 = try await client.send(Netify.get(expecting: Article.self).path("/articles/1").header("Accept-Language", "en"))
        #expect(a1.title == "en")
        let a2 = try await client.send(Netify.get(expecting: Article.self).path("/articles/1").header("Accept-Language", "ko"))
        #expect(a2.title == "ko")
        let a3 = try await client.send(Netify.get(expecting: Article.self).path("/articles/1").header("Accept-Language", "en"))
        #expect(a3.title == "en")
    }
}
