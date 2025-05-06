import XCTest

// TODO: 'Netify'를 실제 프로젝트의 모듈 이름으로 변경하세요.
// 예: @testable import MyApp 또는 @testable import MyNetifyLibrary
@testable import Netify // 실제 프로젝트 모듈 이름

// MARK: - Main Test Class
@available(iOS 15, macOS 12, *) // async/await 사용 위해 클래스 레벨에 적용
final class NetifyTests: XCTestCase {

    // MARK: Properties for Mock Tests
    var mockNetworkSession: MockNetworkSession!
    var mockNetifyClient: NetifyClient!
    let mockBaseURL = "https://mock.api.example.com"

    // MARK: Properties for Integration Tests
    var integrationNetifyClient: NetifyClient!
    let integrationBaseURL = "https://jsonplaceholder.typicode.com"

    // MARK: Test Lifecycle
    override func setUpWithError() throws {
        try super.setUpWithError()

        // Mock Test Setup
        mockNetworkSession = MockNetworkSession()
        let mockConfig = NetifyConfiguration(
            baseURL: mockBaseURL,
            sessionConfiguration: .ephemeral,
            logLevel: .off // 테스트 중에는 로깅 최소화
        )
        // 수정된 NetifyClient init 사용 (NetworkSessionProtocol 주입)
        mockNetifyClient = NetifyClient(configuration: mockConfig, networkSession: mockNetworkSession)

        // Integration Test Setup
        integrationNetifyClient = makeRealNetifyClient()
    }

    override func tearDownWithError() throws {
        mockNetifyClient = nil
        mockNetworkSession = nil
        integrationNetifyClient = nil
        try super.tearDownWithError()
    }

    // MARK: - Mock Based Unit Tests

    // !!! 모든 테스트 함수 시그니처에 throws 추가 !!!
    func testMock_SuccessfulGETRequest() async throws {
        // Given
        let expectedUser = MockUser(id: 1, name: "John Doe")
        let mockData = try JSONEncoder().encode(expectedUser)
        let url = try XCTUnwrap(URL(string: "\(mockBaseURL)/users/1"))
        let mockResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!

        mockNetworkSession.mockData = mockData
        mockNetworkSession.mockResponse = mockResponse

        let request = GetMockUserRequest(userId: 1)

        // When
        let user: MockUser = try await mockNetifyClient.send(request)

        // Then
        XCTAssertEqual(user, expectedUser)
        XCTAssertEqual(mockNetworkSession.lastRequest?.url?.absoluteString, "\(mockBaseURL)/users/1")
        XCTAssertEqual(mockNetworkSession.lastRequest?.httpMethod, "GET")
    }

    func testMock_SuccessfulPOSTRequest() async throws {
        // Given
        let inputUserPayload = MockUserInput(name: "Jane Doe", job: "Developer")
        // 날짜 비교를 위해 DateFormatter 사용 또는 다른 방식의 비교 필요
        let encoder = JSONEncoder()
        let decoder = JSONDecoder() // MockUserResponse 디코딩 시 필요할 수 있음
        encoder.dateEncodingStrategy = .iso8601 // 필요에 따라 설정
        decoder.dateDecodingStrategy = .iso8601 // 필요에 따라 설정

        // createdAt은 서버 응답처럼 처리하기 위해 테스트 시점의 Date 사용
        let expectedResponseUser = MockUserResponse(id: "123", name: "Jane Doe", job: "Developer", createdAt: Date())
        let mockRequestData = try encoder.encode(inputUserPayload)
        let mockResponseData = try encoder.encode(expectedResponseUser)
        let url = try XCTUnwrap(URL(string: "\(mockBaseURL)/users"))
        let mockResponse = HTTPURLResponse(url: url, statusCode: 201, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!

        mockNetworkSession.mockData = mockResponseData
        mockNetworkSession.mockResponse = mockResponse

        let request = CreateMockUserRequest(userInput: inputUserPayload)

        // When
        let createdUserResponse: MockUserResponse = try await mockNetifyClient.send(request)

        // Then
        XCTAssertEqual(createdUserResponse.name, expectedResponseUser.name)
        XCTAssertEqual(createdUserResponse.job, expectedResponseUser.job)
        XCTAssertNotNil(createdUserResponse.id)
        // XCTAssertEqual(createdUserResponse.createdAt, expectedResponseUser.createdAt) // Date 직접 비교는 오차 발생 가능, TimeIntervalSince1970 등으로 비교
        XCTAssertEqual(mockNetworkSession.lastRequest?.url?.absoluteString, "\(mockBaseURL)/users")
        XCTAssertEqual(mockNetworkSession.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(mockNetworkSession.lastRequest?.httpBody, mockRequestData)
        XCTAssertEqual(mockNetworkSession.lastRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")
    }

    func testMock_ClientError_404_NotFound() async throws { // throws 추가
        // Given
        let url = try XCTUnwrap(URL(string: "\(mockBaseURL)/items/999"))
        let mockResponse = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        let errorData = #"{"error": "Item not found", "code": "ITEM_NOT_FOUND"}"#.data(using: .utf8)

        mockNetworkSession.mockResponse = mockResponse
        mockNetworkSession.mockData = errorData

        let request = GetMockItemRequest(itemId: 999)

        // When/Then
        do {
            _ = try await mockNetifyClient.send(request)
            XCTFail("Expected NetworkRequestError.notFound but got success")
        } catch let error as NetworkRequestError {
            // Then
            if case .notFound(let data) = error {
                XCTAssertEqual(data, errorData, "Error data mismatch")
            } else {
                XCTFail("Expected .notFound error but received \(error)")
            }
        } catch {
            XCTFail("Expected NetworkRequestError but got \(error)")
        }
    }

    func testMock_ClientError_400_BadRequest() async throws { // throws 추가
        // Given
        let url = try XCTUnwrap(URL(string: "\(mockBaseURL)/users"))
        let mockResponse = HTTPURLResponse(url: url, statusCode: 400, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        let errorData = #"{"error": "Invalid input: Name is required", "field": "name"}"#.data(using: .utf8)

        mockNetworkSession.mockResponse = mockResponse
        mockNetworkSession.mockData = errorData

        let invalidUserInput = MockUserInput(name: "", job: "Tester")
        let request = CreateMockUserRequest(userInput: invalidUserInput)

        // When/Then
        do {
            _ = try await mockNetifyClient.send(request)
            XCTFail("Expected NetworkRequestError.badRequest but got success")
        } catch let error as NetworkRequestError {
            // Then
            if case .badRequest(let data) = error {
                XCTAssertEqual(data, errorData)
            } else {
                XCTFail("Expected .badRequest error but received \(error)")
            }
        } catch {
            XCTFail("Expected NetworkRequestError but got \(error)")
        }
    }

    func testMock_ServerError_500() async throws { // throws 추가
        // Given
        let url = try XCTUnwrap(URL(string: "\(mockBaseURL)/status/500"))
        let mockResponse = HTTPURLResponse(url: url, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: nil)!
        let errorData = #"{"error": "Something went wrong on the server"}"#.data(using: .utf8)

        mockNetworkSession.mockResponse = mockResponse
        mockNetworkSession.mockData = errorData

        let request = GetMockStatusRequest(code: 500)

        // When/Then
        do {
            _ = try await mockNetifyClient.send(request)
            XCTFail("Expected NetworkRequestError.serverError but got success")
        } catch let error as NetworkRequestError {
            // Then
            if case .serverError(let statusCode, let data) = error {
                XCTAssertEqual(statusCode, 500)
                XCTAssertEqual(data, errorData)
            } else {
                XCTFail("Expected .serverError(statusCode: 500, ...) but received \(error)")
            }
        } catch {
            XCTFail("Expected NetworkRequestError but got \(error)")
        }
    }

    func testMock_DecodingError() async throws { // throws 추가
        // Given
        let malformedData = #"{"message": "Operation successful", "unexpected_field": true}"#.data(using: .utf8)!
        let url = try XCTUnwrap(URL(string: "\(mockBaseURL)/users/1"))
        let mockResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!

        mockNetworkSession.mockData = malformedData
        mockNetworkSession.mockResponse = mockResponse

        let request = GetMockUserRequest(userId: 1) // MockUser를 기대

        // When/Then
        do {
            _ = try await mockNetifyClient.send(request)
            XCTFail("Expected NetworkRequestError.decodingError but got success")
        } catch let error as NetworkRequestError {
            // Then
            if case .decodingError(let underlyingError, let data) = error {
                XCTAssert(underlyingError is DecodingError, "Underlying error should be DecodingError, but was \(type(of: underlyingError))")
                XCTAssertEqual(data, malformedData, "Associated data should be the malformed data")
            } else {
                XCTFail("Expected .decodingError but received \(error)")
            }
        } catch {
            XCTFail("Expected NetworkRequestError but got \(error)")
        }
    }

    func testMock_EmptyResponseSuccess() async throws { // throws 추가
        // Given
        let url = try XCTUnwrap(URL(string: "\(mockBaseURL)/delete/item/5"))
        let mockResponse = HTTPURLResponse(url: url, statusCode: 204, httpVersion: "HTTP/1.1", headerFields: nil)!

        mockNetworkSession.mockResponse = mockResponse
        mockNetworkSession.mockData = Data() // 빈 데이터

        let request = DeleteMockItemRequest(itemId: 5) // EmptyResponse 기대

        // When
        let result: EmptyResponse = try await mockNetifyClient.send(request)

        // Then
        // 성공적으로 EmptyResponse를 받았는지 확인 (별도 값 비교는 불필요)
        XCTAssertNotNil(result) // 타입 캐스팅 및 반환 성공 여부 확인
    }

    func testMock_EmptyResponseForNonEmptyType_DecodingError() async throws { // throws 추가
        // Given
        let url = try XCTUnwrap(URL(string: "\(mockBaseURL)/users/1"))
        let mockResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!

        mockNetworkSession.mockResponse = mockResponse
        mockNetworkSession.mockData = Data() // 빈 데이터

        let request = GetMockUserRequest(userId: 1) // MockUser를 기대하지만 빈 데이터 수신

        // When/Then
        do {
            _ = try await mockNetifyClient.send(request)
            XCTFail("Expected NetworkRequestError.decodingError due to empty data for non-EmptyResponse type, but got success")
        } catch let error as NetworkRequestError {
            // Then
            if case .decodingError(let underlyingError, let data) = error {
                XCTAssertEqual(data, Data(), "Data should be empty")
                // NetifyClient의 handleResponse 로직에서 생성된 에러 메시지 확인
                XCTAssert(underlyingError.localizedDescription.contains("Expected non-empty response body"), "Error description mismatch, got: \(underlyingError.localizedDescription)")
            } else {
                XCTFail("Expected .decodingError but received \(error)")
            }
        } catch {
            XCTFail("Expected NetworkRequestError but got \(error)")
        }
    }

    func testMock_NetworkError_NotConnected() async throws { // throws 추가
        // Given
        let simulatedError = URLError(.notConnectedToInternet)
        mockNetworkSession.simulateError = simulatedError
        let request = GetMockUserRequest(userId: 1)

        // When/Then
        do {
            _ = try await mockNetifyClient.send(request)
            XCTFail("Expected NetworkRequestError.noInternetConnection but got success")
        } catch let error as NetworkRequestError {
            // Then
            // NetifyClient.mapToNetifyError에서 URLError(.notConnectedToInternet)를 .noInternetConnection으로 매핑하는지 확인
            if case .noInternetConnection = error {
                // OK
            } else {
                XCTFail("Expected .noInternetConnection but received \(error)")
            }
        } catch {
            XCTFail("Expected NetworkRequestError but got \(error)")
        }
    }

    func testMock_NetworkError_Timeout() async throws { // throws 추가
        // Given
        let simulatedError = URLError(.timedOut)
        mockNetworkSession.simulateError = simulatedError
        let request = GetMockUserRequest(userId: 1)

        // When/Then
        do {
            _ = try await mockNetifyClient.send(request)
            XCTFail("Expected NetworkRequestError.timedOut but got success")
        } catch let error as NetworkRequestError {
            // Then
            // NetifyClient.mapToNetifyError에서 URLError(.timedOut)을 .timedOut으로 매핑하는지 확인
            if case .timedOut = error {
                // OK
            } else {
                XCTFail("Expected .timedOut but received \(error)")
            }
        } catch {
            XCTFail("Expected NetworkRequestError but got \(error)")
        }
    }

    func testMock_NetworkError_BadURL() async throws { // throws 추가
        // Given
        let simulatedError = URLError(.badURL) // Mock에서 URLSession 레벨 에러 시뮬레이션
        mockNetworkSession.simulateError = simulatedError
        let request = GetMockUserRequest(userId: 1)

        // When/Then
        do {
            _ = try await mockNetifyClient.send(request)
            XCTFail("Expected NetworkRequestError.urlSessionFailed(badURL) but got success")
        } catch let error as NetworkRequestError {
            // Then
            // NetifyClient.mapToNetifyError에서 기타 URLError를 .urlSessionFailed로 매핑하는지 확인
            if case .urlSessionFailed(let underlyingError) = error {
                guard let urlErr = underlyingError as? URLError else {
                    XCTFail("Underlying error should be URLError but was \(type(of: underlyingError))")
                    return
                }
                XCTAssertEqual(urlErr.code, .badURL)
            } else {
                XCTFail("Expected .urlSessionFailed(URLError.badURL) but received \(error)")
            }
        } catch {
            XCTFail("Expected NetworkRequestError but got \(error)")
        }
    }

    // MARK: - Integration Tests (using JSONPlaceholder)

//    func testIntegration_fetchSinglePost_Success() async throws { // throws 추가
//        // Given
//        let postIdToFetch = 1
//        let request = GetPlaceholderPostRequest(postId: postIdToFetch)
//
//        // When
//        let post = try await integrationNetifyClient.send(request) // integrationNetifyClient는 Optional이 아니므로 ! 제거 가능 (setUp에서 초기화 보장)
//
//        // Then
//        XCTAssertEqual(post.id, postIdToFetch)
//        XCTAssertFalse(post.title.isEmpty)
//        XCTAssertFalse(post.body.isEmpty)
//    }
//
//    func testIntegration_fetchAllPosts_Success() async throws { // throws 추가
//        // Given
//        let request = GetAllPlaceholderPostsRequest()
//
//        // When
//        let posts = try await integrationNetifyClient.send(request)
//
//        // Then
//        XCTAssertFalse(posts.isEmpty, "Post list should not be empty")
//        XCTAssertGreaterThan(posts.count, 50, "Should fetch a significant number of posts")
//        if let firstPost = posts.first {
//             XCTAssertNotEqual(firstPost.id, 0)
//             XCTAssertFalse(firstPost.title.isEmpty)
//        } else {
//            XCTFail("Fetched posts array was empty or nil")
//        }
//    }

    func testIntegration_createPost_Success() async throws { // throws 추가
        // Given
        let newPostInput = PlaceholderPostInput(userId: 5, title: "Netify Integration Test", body: "This post was created during an integration test.")
        let request = CreatePlaceholderPostRequest(postInput: newPostInput)

        // When
        let createdPost = try await integrationNetifyClient.send(request)

        // Then
        XCTAssertNotNil(createdPost.id) // JSONPlaceholder는 새 ID를 반환 (보통 101)
        XCTAssertGreaterThanOrEqual(createdPost.id, 101) // JSONPlaceholder는 보통 101부터 시작
        XCTAssertEqual(createdPost.title, newPostInput.title)
        XCTAssertEqual(createdPost.body, newPostInput.body)
        XCTAssertEqual(createdPost.userId, newPostInput.userId)
    }

//    func testIntegration_fetchNonExistentPost_Returns404Error() async throws { // throws 추가
//        // Given
//        let nonExistentPostId = 999999
//        let request = GetPlaceholderPostRequest(postId: nonExistentPostId)
//
//        // When/Then
//        do {
//            _ = try await integrationNetifyClient.send(request)
//            XCTFail("Request should have failed with .notFound error")
//        } catch let error as NetworkRequestError {
//            // Then
//            if case .notFound(let data) = error {
//                 XCTAssertNotNil(data, "Data might be empty or contain {} for 404 from JSONPlaceholder")
//                 // JSONPlaceholder 404 응답 본문은 보통 {} 이므로 데이터 자체는 nil이 아닐 수 있음
//            } else {
//                 XCTFail("Expected .notFound error but received \(error)")
//            }
//        } catch {
//            XCTFail("Expected NetworkRequestError but got a different error type: \(error)")
//        }
//    }
}

// MARK: - Helper Functions for Tests
@available(iOS 15, macOS 12, *)
extension NetifyTests {
    /// Creates a NetifyClient instance configured for integration tests against JSONPlaceholder.
    func makeRealNetifyClient() -> NetifyClient {
        let config = NetifyConfiguration(
            baseURL: integrationBaseURL,
            logLevel: .debug // 통합 테스트 시 로깅 레벨 조정 가능
        )
        // 실제 URLSession을 사용하도록 networkSession 파라미터 생략
        return NetifyClient(configuration: config)
    }
}

// MARK: - Mock Types for Unit Tests

/// Mock NetworkSession conforming to the NetworkSessionProtocol (defined in Netify module)
@available(iOS 15, macOS 12, *)
class MockNetworkSession: NetworkSessionProtocol { // Netify 모듈의 프로토콜 준수

    var lastRequest: URLRequest?
    var mockData: Data?
    var mockResponse: URLResponse?
    var simulateError: Error?

    // NetworkSessionProtocol의 요구사항 구현
    func data(for request: URLRequest, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse) {
        lastRequest = request

        if let error = simulateError {
            throw error // 시뮬레이션할 에러를 throw
        }

        // 응답(mockResponse)이 설정되지 않았으면 테스트 설정 오류로 간주
        guard let response = mockResponse else {
             throw NSError(domain: "MockNetworkSessionError", code: -999, userInfo: [NSLocalizedDescriptionKey: "MockNetworkSession requires a mockResponse to be set for non-error cases."])
        }

        // 설정된 mockData 또는 빈 Data와 mockResponse 반환
        return (mockData ?? Data(), response)
    }
}

// MARK: - Helper Types for Mock Tests (변경 없음)
struct MockUser: Codable, Equatable {
    let id: Int
    let name: String
}

struct MockUserInput: Codable, Equatable {
    let name: String
    let job: String
}

struct MockUserResponse: Codable, Equatable {
    let id: String
    let name: String
    let job: String
    let createdAt: Date // Date 타입은 인코딩/디코딩 전략 및 비교 방식 주의
}

struct MockItem: Codable, Equatable {
    let itemId: Int
    let description: String
}

// MARK: - NetifyRequest Implementations for Mock Tests (변경 없음)
@available(iOS 15, macOS 12, *)
struct GetMockUserRequest: NetifyRequest {
    typealias ReturnType = MockUser
    let userId: Int
    var path: String { "/users/\(userId)" }
}

@available(iOS 15, macOS 12, *)
struct CreateMockUserRequest: NetifyRequest {
    typealias ReturnType = MockUserResponse
    let path = "/users"
    var method: HTTPMethod = .post
    let userInput: MockUserInput
    var body: Any? { userInput }
    // NetifyRequest 기본 구현으로 contentType은 .json으로 가정
}

@available(iOS 15, macOS 12, *)
struct GetMockItemRequest: NetifyRequest {
    typealias ReturnType = MockItem
    let itemId: Int
    var path: String { "/items/\(itemId)" }
}

@available(iOS 15, macOS 12, *)
struct DeleteMockItemRequest: NetifyRequest {
     typealias ReturnType = EmptyResponse
     let itemId: Int
     var path: String { "/delete/item/\(itemId)" }
     var method: HTTPMethod = .delete
}

@available(iOS 15, macOS 12, *)
struct GetMockStatusRequest: NetifyRequest {
     typealias ReturnType = EmptyResponse // 예시: 상태 코드 확인용 요청 (본문 없음)
     let code: Int
     var path: String { "/status/\(code)" }
}


// MARK: - Helper Types for Integration Tests (변경 없음)
struct PlaceholderPost: Codable, Equatable, Identifiable {
    let userId: Int
    let id: Int
    let title: String
    let body: String
}

struct PlaceholderPostInput: Codable, Equatable {
    let userId: Int
    let title: String
    let body: String
}

// MARK: - NetifyRequest Implementations for Integration Tests (변경 없음)
@available(iOS 15, macOS 12, *)
struct GetPlaceholderPostRequest: NetifyRequest {
    typealias ReturnType = PlaceholderPost
    let postId: Int
    var path: String { "/posts/\(postId)" }
    var requiresAuthentication: Bool = false // JSONPlaceholder는 인증 불필요
}

@available(iOS 15, macOS 12, *)
struct GetAllPlaceholderPostsRequest: NetifyRequest {
    typealias ReturnType = [PlaceholderPost]
    let path = "/posts"
    var requiresAuthentication: Bool = false
}

@available(iOS 15, macOS 12, *)
struct CreatePlaceholderPostRequest: NetifyRequest {
    typealias ReturnType = PlaceholderPost // 생성 후 응답으로 Post 객체 받음
    let path = "/posts"
    let method: HTTPMethod = .post
    let postInput: PlaceholderPostInput
    var body: Any? { postInput }
    var requiresAuthentication: Bool = false
    // 기본 contentType = .json 사용
}
