import Foundation
import Testing
@testable import Netify

@Suite("RequestBuilder", .tags(.unit, .core, .fast))
struct RequestBuilderTests {
    @Test("URL/메서드/헤더/쿼리/타임아웃 매핑")
    func testCore() async throws {
        // Arrange
        let cfg = NetifyConfiguration(baseURL: "https://api.example.com")
        let logger = DefaultNetifyLogger(logLevel: .off)
        let builder = RequestBuilder(configuration: cfg, logger: logger)

        // Declarative DSL로 요청 구성
        let req = Netify.post(expecting: EmptyResponse.self)
            .path("/ping/{id}")
            .pathArgument("id", 10)
            .queryParams(["q":"1"])
            .headers(["X-K":"V"])
            .timeout(5)
            .cachePolicy(.reloadIgnoringLocalCacheData)

        // Act
        let urlReq = try await builder.buildURLRequest(from: req)

        // Assert
        #expect(urlReq.httpMethod == "POST")
        #expect(urlReq.url?.absoluteString == "https://api.example.com/ping/10?q=1")
        #expect(urlReq.value(forHTTPHeaderField: "X-K") == "V")
        #expect(urlReq.timeoutInterval == 5)
        #expect(urlReq.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test("멀티파트 Content-Type 및 바디 구성")
    func testMultipart() async throws {
        // Arrange
        let cfg = NetifyConfiguration(baseURL: "https://api.example.com")
        let logger = DefaultNetifyLogger(logLevel: .off)
        let builder = RequestBuilder(configuration: cfg, logger: logger)

        let part = MultipartData(name: "file", fileData: Data([0x0, 0x1]), fileName: "a.bin", mimeType: "application/octet-stream")
        let task = Netify.post(expecting: EmptyResponse.self)
            .path("/upload")
            .multipart([part])

        // Act
        let urlReq = try await builder.buildURLRequest(from: task)

        // Assert
        let ct = try #require(urlReq.value(forHTTPHeaderField: HTTPHeaderField.contentType.rawValue))
        #expect(ct.contains(HTTPContentType.multipart.rawValue))
        #expect((urlReq.httpBody?.count ?? 0) > 0)
    }
}
