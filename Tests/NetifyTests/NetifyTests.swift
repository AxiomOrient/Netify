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
        // Use a consistent encoder/decoder setup for mock client
        let sharedEncoder = JSONEncoder()
        sharedEncoder.dateEncodingStrategy = .iso8601
        // Ensure other relevant encoder settings are mirrored if necessary (e.g., outputFormatting for body comparison)
        let sharedDecoder = JSONDecoder()
        sharedDecoder.dateDecodingStrategy = .iso8601
        let mockConfig = NetifyConfiguration(
            baseURL: mockBaseURL,
            sessionConfiguration: .ephemeral,
            defaultEncoder: sharedEncoder, // Use the shared encoder
            defaultDecoder: sharedDecoder, // 설정된 디코더 사용
            logLevel: .debug // 문제 확인을 위해 debug로 변경 (필요시 .off)
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
    /**
     * @Intent: `NetifyClient`가 `MockNetworkSession`을 통해 성공적인 GET 요청을 처리하고, 응답 데이터를 올바르게 디코딩하는지 검증합니다.
     * @Given: `MockNetworkSession`에 예상되는 `MockUser` 데이터와 200 OK 응답이 설정되어 있습니다. `GetMockUserRequest`가 준비됩니다.
     * @When: `mockNetifyClient.send()`를 통해 `GetMockUserRequest`를 전송합니다.
     * @Then: 반환된 `MockUser` 객체가 예상된 값과 일치하고, `MockNetworkSession`에 전달된 요청의 URL과 HTTP 메서드가 올바른지 단언합니다.
     */
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

    /**
     * @Intent: `NetifyClient`가 `MockNetworkSession`을 통해 성공적인 POST 요청을 처리하고, 요청 본문을 올바르게 인코딩하며, 응답 데이터를 디코딩하는지 검증합니다.
     * @Given: `MockNetworkSession`에 예상되는 `MockUserResponse` 데이터와 201 Created 응답이 설정되어 있습니다. `CreateMockUserRequest`와 입력 페이로드가 준비됩니다.
     * @When: `mockNetifyClient.send()`를 통해 `CreateMockUserRequest`를 전송합니다.
     * @Then: 반환된 `MockUserResponse` 객체의 속성들이 예상된 값과 일치하고, `MockNetworkSession`에 전달된 요청의 URL, HTTP 메서드, HTTP 바디, Content-Type 헤더가 올바른지 단언합니다.
     */
    func testMock_SuccessfulPOSTRequest() async throws {
        // Given
        let inputUserPayload = MockUserInput(name: "Jane Doe", job: "Developer")
        // Use an encoder consistent with the mockNetifyClient's configuration for creating mock data
        let testEncoder = JSONEncoder()
        testEncoder.dateEncodingStrategy = .iso8601 // NetifyClient의 디코더와 일치

        // createdAt은 서버 응답처럼 처리하기 위해 테스트 시점의 Date 사용
        // 실제 응답은 문자열로 오므로, 비교를 위해 Date를 문자열로 변환 후 다시 Date로 파싱하거나, TimeInterval로 비교
        let now = Date()
        let expectedResponseUser = MockUserResponse(id: "123", name: "Jane Doe", job: "Developer", createdAt: now)
        
        // Mock 응답 데이터 생성 시에도 동일한 인코딩 전략 사용
        let mockRequestData = try testEncoder.encode(inputUserPayload)
        let mockResponseData = try testEncoder.encode(expectedResponseUser) // 이제 createdAt이 ISO8601 문자열로 인코딩됨

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
        // Date 비교 시 TimeIntervalSince1970 사용, ISO8601은 초 단위까지는 보통 정확하므로 accuracy를 1.0 (1초) 정도로 설정
        // 또는 더 정밀하게 하려면 인코딩/디코딩 과정을 정확히 이해하고 그에 맞는 accuracy 설정
        XCTAssertEqual(createdUserResponse.createdAt.timeIntervalSince1970, expectedResponseUser.createdAt.timeIntervalSince1970, accuracy: 1.0)

        XCTAssertEqual(mockNetworkSession.lastRequest?.url?.absoluteString, "\(mockBaseURL)/users")
        XCTAssertEqual(mockNetworkSession.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(mockNetworkSession.lastRequest?.httpBody, mockRequestData)
        XCTAssertEqual(mockNetworkSession.lastRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")
    }

    /**
     * @Intent: `NetifyClient`가 HTTP 404 Not Found 응답을 `NetworkRequestError.notFound`로 올바르게 매핑하고, 오류 응답 데이터를 포함하는지 검증합니다.
     * @Given: `MockNetworkSession`에 404 응답과 오류 JSON 데이터가 설정되어 있습니다. 존재하지 않는 아이템을 요청하는 `GetMockItemRequest`가 준비됩니다.
     * @When: `mockNetifyClient.send()`를 통해 요청을 전송합니다.
     * @Then: `NetworkRequestError.notFound` 오류가 발생하고, 해당 오류에 포함된 데이터가 `MockNetworkSession`에 설정된 오류 데이터와 일치하는지 단언합니다.
     */
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

    /**
     * @Intent: `NetifyClient`가 HTTP 400 Bad Request 응답을 `NetworkRequestError.badRequest`로 올바르게 매핑하고, 오류 응답 데이터를 포함하는지 검증합니다.
     * @Given: `MockNetworkSession`에 400 응답과 오류 JSON 데이터가 설정되어 있습니다. 유효하지 않은 사용자 입력을 포함하는 `CreateMockUserRequest`가 준비됩니다.
     * @When: `mockNetifyClient.send()`를 통해 요청을 전송합니다.
     * @Then: `NetworkRequestError.badRequest` 오류가 발생하고, 해당 오류에 포함된 데이터가 `MockNetworkSession`에 설정된 오류 데이터와 일치하는지 단언합니다.
     */
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

    /**
     * @Intent: `NetifyClient`가 HTTP 500 Internal Server Error 응답을 `NetworkRequestError.serverError`로 올바르게 매핑하고, 상태 코드와 오류 응답 데이터를 포함하는지 검증합니다.
     * @Given: `MockNetworkSession`에 500 응답과 오류 JSON 데이터가 설정되어 있습니다. 서버 오류를 시뮬레이션하는 `GetMockStatusRequest`가 준비됩니다.
     * @When: `mockNetifyClient.send()`를 통해 요청을 전송합니다.
     * @Then: `NetworkRequestError.serverError` 오류가 발생하고, 해당 오류에 포함된 상태 코드가 500이고 데이터가 `MockNetworkSession`에 설정된 오류 데이터와 일치하는지 단언합니다.
     */
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

    /**
     * @Intent: `NetifyClient`가 잘못된 형식의 JSON 응답을 수신했을 때 `NetworkRequestError.decodingError`를 올바르게 발생시키고, 원본 디코딩 오류와 데이터를 포함하는지 검증합니다.
     * @Given: `MockNetworkSession`에 200 OK 응답과 디코딩할 수 없는 잘못된 형식의 JSON 데이터가 설정되어 있습니다. `MockUser`를 기대하는 `GetMockUserRequest`가 준비됩니다.
     * @When: `mockNetifyClient.send()`를 통해 요청을 전송합니다.
     * @Then: `NetworkRequestError.decodingError` 오류가 발생하고, 내재된 오류가 `DecodingError` 타입이며 연관된 데이터가 원본의 잘못된 데이터와 일치하는지 단언합니다.
     */
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

    /**
     * @Intent: `NetifyClient`가 HTTP 204 No Content와 같이 본문이 없는 성공적인 응답을 `EmptyResponse` 타입으로 올바르게 처리하는지 검증합니다.
     * @Given: `MockNetworkSession`에 204 응답과 빈 데이터가 설정되어 있습니다. `EmptyResponse`를 기대하는 `DeleteMockItemRequest`가 준비됩니다.
     * @When: `mockNetifyClient.send()`를 통해 요청을 전송합니다.
     * @Then: `EmptyResponse` 타입의 결과가 성공적으로 반환되는지 단언합니다 (nil이 아님).
     */
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

    /**
     * @Intent: `NetifyClient`가 `EmptyResponse`나 `Data`가 아닌 타입을 기대할 때 빈 응답 데이터를 수신하면 `NetworkRequestError.decodingError`를 발생시키는지 검증합니다.
     * @Given: `MockNetworkSession`에 200 OK 응답과 빈 데이터가 설정되어 있습니다. `MockUser`를 기대하는 `GetMockUserRequest`가 준비됩니다.
     * @When: `mockNetifyClient.send()`를 통해 요청을 전송합니다.
     * @Then: `NetworkRequestError.decodingError` 오류가 발생하고, 연관된 데이터가 비어 있으며, 내재된 오류의 설명에 "Expected non-empty response body"가 포함되어 있는지 단언합니다.
     */
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

    /**
     * @Intent: `NetifyClient`가 `URLError.notConnectedToInternet` 오류를 `NetworkRequestError.noInternetConnection`으로 올바르게 매핑하는지 검증합니다.
     * @Given: `MockNetworkSession`이 `URLError.notConnectedToInternet` 오류를 시뮬레이션하도록 설정됩니다.
     * @When: `mockNetifyClient.send()`를 통해 요청을 전송합니다.
     * @Then: `NetworkRequestError.noInternetConnection` 오류가 발생하는지 단언합니다.
     */
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

    /**
     * @Intent: `NetifyClient`가 `URLError.timedOut` 오류를 `NetworkRequestError.timedOut`으로 올바르게 매핑하는지 검증합니다.
     * @Given: `MockNetworkSession`이 `URLError.timedOut` 오류를 시뮬레이션하도록 설정됩니다.
     * @When: `mockNetifyClient.send()`를 통해 요청을 전송합니다.
     * @Then: `NetworkRequestError.timedOut` 오류가 발생하는지 단언합니다.
     */
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

    /**
     * @Intent: `NetifyClient`가 `URLError.badURL`과 같은 기타 `URLError`를 `NetworkRequestError.urlSessionFailed`로 올바르게 매핑하고, 원본 `URLError`를 포함하는지 검증합니다.
     * @Given: `MockNetworkSession`이 `URLError.badURL` 오류를 시뮬레이션하도록 설정됩니다.
     * @When: `mockNetifyClient.send()`를 통해 요청을 전송합니다.
     * @Then: `NetworkRequestError.urlSessionFailed` 오류가 발생하고, 내재된 오류가 `URLError` 타입이며 코드가 `.badURL`인지 단언합니다.
     */
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

    /**
     * @Intent: `integrationNetifyClient`를 사용하여 JSONPlaceholder API에서 특정 게시물을 성공적으로 가져오고, 해당 게시물의 내용을 검증합니다.
     * @Given: `integrationNetifyClient`가 JSONPlaceholder API를 대상으로 설정되어 있고, ID가 1인 게시물을 요청하는 `GetPlaceholderPostRequest`가 준비됩니다.
     * @When: `integrationNetifyClient.send()`를 통해 요청을 전송합니다.
     * @Then: 반환된 `PlaceholderPost` 객체의 `id`, `userId`, `title`, `body`가 JSONPlaceholder의 ID 1 게시물 데이터와 일치하는지 단언합니다.
     */
    func testIntegration_fetchSinglePost_Success() async throws {
        // Given
        let postIdToFetch = 1
        let request = GetPlaceholderPostRequest(postId: postIdToFetch)

        // When
        let post = try await integrationNetifyClient.send(request)

        // Then
        XCTAssertEqual(post.id, postIdToFetch)
        XCTAssertEqual(post.userId, 1) // JSONPlaceholder post 1 has userId 1
        XCTAssertEqual(post.title, "sunt aut facere repellat provident occaecati excepturi optio reprehenderit")
        XCTAssertFalse(post.body.isEmpty)
        // For more specific body check if needed:
        // XCTAssertTrue(post.body.starts(with: "quia et suscipit\nsuscipit recusandae consequuntur expedita et cum"))
    }

    /**
     * @Intent: `integrationNetifyClient`를 사용하여 JSONPlaceholder API에서 모든 게시물을 성공적으로 가져오고, 반환된 목록의 크기와 첫 번째 게시물의 내용을 검증합니다.
     * @Given: `integrationNetifyClient`가 JSONPlaceholder API를 대상으로 설정되어 있고, 모든 게시물을 요청하는 `GetAllPlaceholderPostsRequest`가 준비됩니다.
     * @When: `integrationNetifyClient.send()`를 통해 요청을 전송합니다.
     * @Then: 반환된 `PlaceholderPost` 배열이 비어있지 않고, 100개의 게시물을 포함하며, 첫 번째 게시물의 `id`와 `title`이 올바른지 단언합니다.
     */
    func testIntegration_fetchAllPosts_Success() async throws {
        // Given
        let request = GetAllPlaceholderPostsRequest()

        // When
        let posts = try await integrationNetifyClient.send(request)

        // Then
        XCTAssertFalse(posts.isEmpty, "Post list should not be empty")
        XCTAssertEqual(posts.count, 100, "JSONPlaceholder should return 100 posts for /posts")
        if let firstPost = posts.first {
             XCTAssertEqual(firstPost.id, 1) // First post usually has ID 1
             XCTAssertFalse(firstPost.title.isEmpty)
        } else {
            XCTFail("Fetched posts array was empty or nil, which is unexpected for JSONPlaceholder /posts.")
        }
    }

    /**
     * @Intent: `integrationNetifyClient`를 사용하여 JSONPlaceholder API에 새 게시물을 성공적으로 생성하고, 반환된 게시물 객체의 내용을 검증합니다.
     * @Given: `integrationNetifyClient`가 JSONPlaceholder API를 대상으로 설정되어 있고, 새 게시물 데이터를 포함하는 `CreatePlaceholderPostRequest`가 준비됩니다.
     * @When: `integrationNetifyClient.send()`를 통해 요청을 전송합니다.
     * @Then: 반환된 `PlaceholderPost` 객체가 새로운 `id` (JSONPlaceholder는 보통 101을 반환)를 가지고, `title`, `body`, `userId`가 요청 시 보낸 값과 일치하는지 단언합니다.
     */
    func testIntegration_createPost_Success() async throws { // throws 추가
        // Given
        let newPostInput = PlaceholderPostInput(userId: 5, title: "Netify Integration Test", body: "This post was created during an integration test.")
        let request = CreatePlaceholderPostRequest(postInput: newPostInput)

        // When
        let createdPost: PlaceholderPost = try await integrationNetifyClient.send(request)

        // Then
        XCTAssertNotNil(createdPost.id) // JSONPlaceholder는 새 ID를 반환 (보통 101)
        XCTAssertGreaterThanOrEqual(createdPost.id, 101) // JSONPlaceholder는 보통 101부터 시작
        XCTAssertEqual(createdPost.title, newPostInput.title)
        XCTAssertEqual(createdPost.body, newPostInput.body)
        XCTAssertEqual(createdPost.userId, newPostInput.userId)
    }

    /**
     * @Intent: `NetifyClient`를 사용하여 HTTPBin API의 `/status/404` 엔드포인트가 올바르게 HTTP 404 오류를 반환하는지 검증합니다.
     * @Given: HTTPBin API (`https://httpbin.org`)를 대상으로 하는 `NetifyClient` 인스턴스와, 상태 코드 404를 요청하는 `GetHttpBinStatusRequest`가 준비됩니다.
     * @When: 해당 클라이언트로 `send()`를 통해 요청을 전송합니다.
     * @Then: `NetworkRequestError.notFound` 오류가 발생하고, 해당 오류에 포함된 데이터가 (HTTPBin의 경우 보통 비어있거나 HTML) nil이 아닌지 단언합니다.
     */
    func testIntegration_HttpBin_Returns404Error() async throws {
        // Given
        let httpBinBaseURL = "https://httpbin.org"
        let httpBinConfig = NetifyConfiguration(
            baseURL: httpBinBaseURL,
            logLevel: .debug, // HTTPBin 테스트 시 로깅 레벨
            maxRetryCount: 1   // HTTPBin에 대한 재시도 횟수 (선택 사항)
        )
        let httpBinClient = NetifyClient(configuration: httpBinConfig)
        
        let request = GetHttpBinStatusRequest(statusCode: 404)

        // When/Then
        do {
            _ = try await httpBinClient.send(request) // Expecting EmptyResponse or Data
            XCTFail("Request to HTTPBin /status/404 should have failed with .notFound error.")
        } catch let error as NetworkRequestError {
            if case .notFound(let data) = error {
                XCTAssertNotNil(data, "Data from HTTPBin 404 should not be nil, though it might be empty or HTML.")
                // HTTPBin /status/404는 보통 빈 본문 또는 HTML 오류 페이지를 반환합니다.
                // print("HTTPBin 404 response data string: \(String(data: data ?? Data(), encoding: .utf8) ?? "nil or non-UTF8")")
            } else {
                XCTFail("Expected .notFound error from HTTPBin but received \(error)")
            }
        } catch {
            XCTFail("Expected NetworkRequestError but got a different error type: \(error)")
        }
    }
}

// MARK: - Helper Functions for Tests
@available(iOS 15, macOS 12, *)
extension NetifyTests {
    /// Creates a NetifyClient instance configured for integration tests against JSONPlaceholder.
    func makeRealNetifyClient() -> NetifyClient {
        let config = NetifyConfiguration(
            baseURL: integrationBaseURL,
            logLevel: .debug, // 통합 테스트 시 로깅 레벨 조정 가능
            maxRetryCount: 2, // JSONPlaceholder에 대한 재시도 횟수 추가
            timeoutInterval: 45.0, // 타임아웃 약간 증가 (선택 사항)
            waitsForConnectivity: false // 네트워크 연결 대기 옵션 활성화
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
     typealias ReturnType = Data // Mock 서버가 에러 본문을 반환할 수 있으므로 Data로 받는 것이 더 유연할 수 있음
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

// HTTPBin 테스트용 NetifyRequest
@available(iOS 15, macOS 12, *)
struct GetHttpBinStatusRequest: NetifyRequest {
    typealias ReturnType = Data // HTTPBin은 HTML이나 다른 내용을 반환할 수 있으므로 Data로 받음
    let statusCode: Int
    var path: String { "/status/\(statusCode)" }
    var requiresAuthentication: Bool = false
}
