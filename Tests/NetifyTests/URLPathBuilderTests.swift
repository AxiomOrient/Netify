import Foundation
import Testing
@testable import Netify

@Suite("URLPathBuilder", .tags(.unit, .core, .fast))
struct URLPathBuilderTests {
    @Test("기본/경로 안전 결합")
    func testJoinAndNormalize() throws {
        let url = try URLPathBuilder.buildURL(baseURL: "https://api.example.com/v1", path: "/users/1")
        #expect(url.absoluteString == "https://api.example.com/v1/users/1")
    }

    @Test("유효하지 않은 baseURL 에러")
    func testInvalidBase() {
        #expect(throws: NetworkRequestError.self) {
            _ = try URLPathBuilder.buildURL(baseURL: "", path: "/ping")
        }
    }
}
