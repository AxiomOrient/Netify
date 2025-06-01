import XCTest
@testable import Netify // 실제 프로젝트 모듈 이름으로 변경하세요.

// MARK: - Main Test Class
@available(iOS 15, macOS 12, *)
final class NetifyTests: XCTestCase {
    
    // MARK: Properties
    var mockNetworkSession: MockNetworkSession!
    var mockNetifyClient: NetifyClient!
    let mockBaseURL = "https://mock.api.example.com"
    
    var integrationNetifyClient: NetifyClient!
    let integrationBaseURL = "https://jsonplaceholder.typicode.com"
    
    // MARK: Test Lifecycle
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Mock Test Setup
        mockNetworkSession = MockNetworkSession()
        let sharedEncoder = JSONEncoder()
        sharedEncoder.dateEncodingStrategy = .iso8601
        sharedEncoder.outputFormatting = .sortedKeys // 요청 본문 비교 일관성 확보
        
        let sharedDecoder = JSONDecoder()
        sharedDecoder.dateDecodingStrategy = .iso8601
        
        let mockConfig = NetifyConfiguration(
            baseURL: mockBaseURL,
            sessionConfiguration: .ephemeral, // 테스트 시 네트워크 캐시 등 방지
            defaultEncoder: sharedEncoder,
            defaultDecoder: sharedDecoder,
            logLevel: .debug // 테스트 중 상세 로그 확인 (필요시 .off 또는 .error로 변경)
        )
        mockNetifyClient = NetifyClient(configuration: mockConfig, networkSession: mockNetworkSession)
        
        // Integration Test Setup
        integrationNetifyClient = makeRealNetifyClient()
    }
    
    override func tearDownWithError() throws {
        mockNetworkSession = nil
        mockNetifyClient = nil
        integrationNetifyClient = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Mock Based Unit Tests (NetifyRequest Protocol Based)
    
    /**
     * @Intent: 프로토콜 기반 GET 요청이 성공적으로 처리되고 응답이 디코딩되는지 검증합니다.
     * @Given: `MockUser` 데이터와 200 OK 응답이 `MockNetworkSession`에 설정됩니다. `GetMockUserRequest`가 준비됩니다.
     * @When: `mockNetifyClient.send()`로 요청을 전송합니다.
     * @Then: 반환된 `MockUser`가 예상과 같고, 요청 URL과 메소드가 올바른지 확인합니다.
     */
    func testMock_SuccessfulGETRequest_ProtocolBased() async throws {
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
     * @Intent: 프로토콜 기반 POST 요청의 본문 인코딩 및 응답 디코딩을 검증합니다.
     * @Given: `MockUserResponse` 데이터와 201 Created 응답이 `MockNetworkSession`에 설정됩니다. `CreateMockUserRequest`가 준비됩니다.
     * @When: `mockNetifyClient.send()`로 요청을 전송합니다.
     * @Then: 반환된 응답이 예상과 같고, 요청 URL, 메소드, 본문, Content-Type이 올바른지 확인합니다.
     */
    func testMock_SuccessfulPOSTRequest_ProtocolBased() async throws {
        // Given
        let inputUserPayload = MockUserInput(name: "Jane Doe", job: "Developer")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = .sortedKeys
        
        let now = Date()
        let expectedResponseUser = MockUserResponse(id: "123", name: "Jane Doe", job: "Developer", createdAt: now)
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
        XCTAssertEqual(createdUserResponse.createdAt.timeIntervalSince1970, expectedResponseUser.createdAt.timeIntervalSince1970, accuracy: 1.0)
        
        XCTAssertEqual(mockNetworkSession.lastRequest?.url?.absoluteString, "\(mockBaseURL)/users")
        XCTAssertEqual(mockNetworkSession.lastRequest?.httpMethod, "POST")
        
        guard let actualBodyData = mockNetworkSession.lastRequest?.httpBody else {
            XCTFail("Actual request body data is nil"); return
        }
        let actualInputPayload = try mockNetifyClient.configuration.defaultDecoder.decode(MockUserInput.self, from: actualBodyData)
        XCTAssertEqual(actualInputPayload, inputUserPayload, "Decoded request body mismatch")
        
        XCTAssertEqual(mockNetworkSession.lastRequest?.value(forHTTPHeaderField: "Content-Type"), HTTPContentType.json.rawValue)
    }
    
    // MARK: - Mock Based Error Handling Tests (Protocol Based)

    func testMock_ClientError_404_NotFound() async throws {
        // Given
        let url = try XCTUnwrap(URL(string: "\(mockBaseURL)/items/999"))
        let mockErrorResponse = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        let errorJSONData = #"{"error": "Item not found"}"#.data(using: .utf8)
        mockNetworkSession.mockResponse = mockErrorResponse
        mockNetworkSession.mockData = errorJSONData
        let request = GetMockItemRequest(itemId: 999)

        // When/Then
        do {
            _ = try await mockNetifyClient.send(request)
            XCTFail("Expected NetworkRequestError.notFound")
        } catch let error as NetworkRequestError {
            if case .notFound(let data) = error { XCTAssertEqual(data, errorJSONData) } else { XCTFail("Expected .notFound, got \(error)") }
        } catch { XCTFail("Expected NetworkRequestError, got \(error)") }
    }

    func testMock_ClientError_400_BadRequest() async throws {
        // Given
        let url = try XCTUnwrap(URL(string: "\(mockBaseURL)/users"))
        let mockErrorResponse = HTTPURLResponse(url: url, statusCode: 400, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        let errorJSONData = #"{"error": "Invalid input"}"#.data(using: .utf8)
        mockNetworkSession.mockResponse = mockErrorResponse
        mockNetworkSession.mockData = errorJSONData
        let request = CreateMockUserRequest(userInput: MockUserInput(name: "", job: "Test"))

        // When/Then
        do {
            _ = try await mockNetifyClient.send(request)
            XCTFail("Expected NetworkRequestError.badRequest")
        } catch let error as NetworkRequestError {
            if case .badRequest(let data) = error { XCTAssertEqual(data, errorJSONData) } else { XCTFail("Expected .badRequest, got \(error)") }
        } catch { XCTFail("Expected NetworkRequestError, got \(error)") }
    }
    
    func testMock_ServerError_500() async throws {
        // Given
        let url = try XCTUnwrap(URL(string: "\(mockBaseURL)/status/500"))
        let mockErrorResponse = HTTPURLResponse(url: url, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: nil)!
        let errorJSONData = #"{"error": "Server issue"}"#.data(using: .utf8)
        mockNetworkSession.mockResponse = mockErrorResponse
        mockNetworkSession.mockData = errorJSONData
        let request = GetMockStatusRequest(code: 500)

        // When/Then
        do {
            _ = try await mockNetifyClient.send(request)
            XCTFail("Expected NetworkRequestError.serverError")
        } catch let error as NetworkRequestError {
            if case .serverError(let statusCode, let data) = error {
                XCTAssertEqual(statusCode, 500)
                XCTAssertEqual(data, errorJSONData)
            } else { XCTFail("Expected .serverError, got \(error)") }
        } catch { XCTFail("Expected NetworkRequestError, got \(error)") }
    }

    func testMock_DecodingError() async throws {
        // Given
        let malformedJSONData = #"{"id":1,"name":"Test" corrupted}"#.data(using: .utf8)! // Corrupted JSON
        let url = try XCTUnwrap(URL(string: "\(mockBaseURL)/users/1"))
        let mockOKResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        mockNetworkSession.mockData = malformedJSONData
        mockNetworkSession.mockResponse = mockOKResponse
        let request = GetMockUserRequest(userId: 1)

        // When/Then
        do {
            _ = try await mockNetifyClient.send(request)
            XCTFail("Expected NetworkRequestError.decodingError")
        } catch let error as NetworkRequestError {
            if case .decodingError(let underlyingError, let data) = error {
                XCTAssert(underlyingError is Swift.DecodingError)
                XCTAssertEqual(data, malformedJSONData)
            } else { XCTFail("Expected .decodingError, got \(error)") }
        } catch { XCTFail("Expected NetworkRequestError, got \(error)") }
    }

    func testMock_EmptyResponseSuccess() async throws {
        // Given
        let url = try XCTUnwrap(URL(string: "\(mockBaseURL)/items/5"))
        let mockNoContentResponse = HTTPURLResponse(url: url, statusCode: 204, httpVersion: "HTTP/1.1", headerFields: nil)!
        mockNetworkSession.mockResponse = mockNoContentResponse
        mockNetworkSession.mockData = Data() // Empty data for 204
        let request = DeleteMockItemRequest(itemId: 5)

        // When
        let result: EmptyResponse = try await mockNetifyClient.send(request)
        
        // Then
        XCTAssertNotNil(result) // Successfully received and mapped to EmptyResponse
    }

    func testMock_EmptyResponseForNonEmptyType_DecodingError() async throws {
        // Given
        let url = try XCTUnwrap(URL(string: "\(mockBaseURL)/users/1"))
        let mockOKEmptyDataResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        mockNetworkSession.mockResponse = mockOKEmptyDataResponse
        mockNetworkSession.mockData = Data() // Empty data
        let request = GetMockUserRequest(userId: 1) // Expects MockUser

        // When/Then
        do {
            _ = try await mockNetifyClient.send(request)
            XCTFail("Expected NetworkRequestError.decodingError for empty data with non-EmptyResponse type")
        } catch let error as NetworkRequestError {
            if case .decodingError(let underlyingError, let data) = error {
                XCTAssertEqual(data, Data())
                XCTAssert(underlyingError.localizedDescription.contains("타입을 기대했으나 빈 응답 본문을 받았습니다"), "Error message mismatch: \(underlyingError.localizedDescription)")
            } else { XCTFail("Expected .decodingError, got \(error)") }
        } catch { XCTFail("Expected NetworkRequestError, got \(error)") }
    }
    
    func testMock_NetworkError_NotConnected() async throws {
        // Given
        mockNetworkSession.simulateError = URLError(.notConnectedToInternet)
        let request = GetMockUserRequest(userId: 1)

        // When/Then
        do {
            _ = try await mockNetifyClient.send(request)
            XCTFail("Expected NetworkRequestError.noInternetConnection")
        } catch let error as NetworkRequestError {
            guard case .noInternetConnection = error else { XCTFail("Expected .noInternetConnection, got \(error)"); return }
        } catch { XCTFail("Expected NetworkRequestError, got \(error)") }
    }

    func testMock_NetworkError_Timeout() async throws {
        // Given
        mockNetworkSession.simulateError = URLError(.timedOut)
        let request = GetMockUserRequest(userId: 1)

        // When/Then
        do {
            _ = try await mockNetifyClient.send(request)
            XCTFail("Expected NetworkRequestError.timedOut")
        } catch let error as NetworkRequestError {
            guard case .timedOut = error else { XCTFail("Expected .timedOut, got \(error)"); return }
        } catch { XCTFail("Expected NetworkRequestError, got \(error)") }
    }

    func testMock_NetworkError_BadURL() async throws {
        // Given
        mockNetworkSession.simulateError = URLError(.badURL)
        let request = GetMockUserRequest(userId: 1)

        // When/Then
        do {
            _ = try await mockNetifyClient.send(request)
            XCTFail("Expected NetworkRequestError.urlSessionFailed")
        } catch let error as NetworkRequestError {
            if case .urlSessionFailed(let underlyingError) = error {
                XCTAssertEqual((underlyingError as? URLError)?.code, .badURL)
            } else { XCTFail("Expected .urlSessionFailed with URLError.badURL, got \(error)")}
        } catch { XCTFail("Expected NetworkRequestError, got \(error)") }
    }
    
    // MARK: - Mock Based Unit Tests (NEW: Declarative API)
    
    /**
     * @Intent: 선언적 API GET 요청(경로 인자, 쿼리 파라미터, 헤더 포함)의 성공 및 응답 디코딩을 검증합니다.
     * @Given: `MockUser` 데이터와 200 OK 응답이 `MockNetworkSession`에 설정됩니다. 선언적 API로 요청이 구성됩니다.
     * @When: `mockNetifyClient.send()`로 선언적 요청을 전송합니다.
     * @Then: 반환된 `MockUser`가 예상과 같고, 요청 URL, 메소드, 헤더가 올바른지 확인합니다.
     */
    func testMock_Declarative_SuccessfulGETRequest_WithParamsAndHeaders() async throws {
        // Given
        let expectedUser = MockUser(id: 7, name: "Declarative User")
        let mockData = try JSONEncoder().encode(expectedUser)
        // URL 구성 시 쿼리 파라미터 순서는 중요하지 않으므로, 검증 시 Set으로 비교
        let url = try XCTUnwrap(URL(string: "\(mockBaseURL)/declarative/users/7?type=active&role=admin"))
        let mockResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!

        mockNetworkSession.mockData = mockData
        mockNetworkSession.mockResponse = mockResponse

        let declarativeRequest = Netify.get(expecting: MockUser.self)
            .path("/declarative/users/{userID}")
            .pathArgument("userID", 7)
            .queryParam("type", "active")
            .queryParam("role", "admin") // 쿼리 파라미터 순서 변경하여 테스트 가능
            .header("X-Custom-ID", "declarative-test-001")
            .authentication(required: false)

        // When
        let user: MockUser = try await mockNetifyClient.send(declarativeRequest)

        // Then
        XCTAssertEqual(user, expectedUser, "Decoded user mismatch")
        
        let lastRequest = try XCTUnwrap(mockNetworkSession.lastRequest)
        let lastURL = try XCTUnwrap(lastRequest.url)
        
        XCTAssertEqual(lastURL.path, "/declarative/users/7", "Request path mismatch")
        
        let expectedQueryItems = Set([URLQueryItem(name: "type", value: "active"), URLQueryItem(name: "role", value: "admin")])
        let actualQueryItems = Set(URLComponents(url: lastURL, resolvingAgainstBaseURL: false)?.queryItems ?? [])
        XCTAssertEqual(actualQueryItems, expectedQueryItems, "Query parameters mismatch")
        
        XCTAssertEqual(lastRequest.httpMethod, "GET", "HTTP method mismatch")
        XCTAssertEqual(lastRequest.value(forHTTPHeaderField: "X-Custom-ID"), "declarative-test-001", "Custom header mismatch")
    }

    /**
     * @Intent: 선언적 API POST 요청(JSON 본문)의 성공, 요청 본문 인코딩, Content-Type 설정, 응답 디코딩을 검증합니다.
     * @Given: `MockUserResponse` 데이터와 201 Created 응답이 `MockNetworkSession`에 설정됩니다. 선언적 API로 POST 요청이 구성됩니다.
     * @When: `mockNetifyClient.send()`로 선언적 요청을 전송합니다.
     * @Then: 반환된 응답이 예상과 같고, 요청 URL, 메소드, 본문(디코딩 후 비교), Content-Type 헤더가 올바른지 확인합니다.
     */
    func testMock_Declarative_SuccessfulPOSTRequest_WithJSONBody() async throws {
        // Given
        let inputUserPayload = MockUserInput(name: "Declarative POST", job: "Architect")
        let now = Date()
        let expectedResponseUser = MockUserResponse(id: "789", name: inputUserPayload.name, job: inputUserPayload.job, createdAt: now)
        
        let mockResponseData = try mockNetifyClient.configuration.defaultEncoder.encode(expectedResponseUser)
        
        let url = try XCTUnwrap(URL(string: "\(mockBaseURL)/declarative/users"))
        let mockResponse = HTTPURLResponse(url: url, statusCode: 201, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!

        mockNetworkSession.mockData = mockResponseData
        mockNetworkSession.mockResponse = mockResponse

        let declarativeRequest = Netify.post(expecting: MockUserResponse.self)
            .path("/declarative/users")
            .body(inputUserPayload) // .json contentType 자동 설정 기대
            .header("X-Action", "CreateUser-Declarative")

        // When
        let createdUserResponse: MockUserResponse = try await mockNetifyClient.send(declarativeRequest)

        // Then
        XCTAssertEqual(createdUserResponse.name, expectedResponseUser.name)
        XCTAssertEqual(createdUserResponse.job, expectedResponseUser.job)
        XCTAssertEqual(createdUserResponse.id, expectedResponseUser.id)
        XCTAssertEqual(createdUserResponse.createdAt.timeIntervalSince1970, expectedResponseUser.createdAt.timeIntervalSince1970, accuracy: 1.0)

        let lastRequest = try XCTUnwrap(mockNetworkSession.lastRequest)
        XCTAssertEqual(lastRequest.url?.absoluteString, "\(mockBaseURL)/declarative/users")
        XCTAssertEqual(lastRequest.httpMethod, "POST")
        
        guard let actualBodyData = lastRequest.httpBody else {
            XCTFail("Actual request body data is nil"); return
        }
        let actualInputPayload = try mockNetifyClient.configuration.defaultDecoder.decode(MockUserInput.self, from: actualBodyData)
        XCTAssertEqual(actualInputPayload, inputUserPayload, "Decoded request body mismatch")
        
        XCTAssertEqual(lastRequest.value(forHTTPHeaderField: HTTPHeaderField.contentType.rawValue), HTTPContentType.json.rawValue)
        XCTAssertEqual(lastRequest.value(forHTTPHeaderField: "X-Action"), "CreateUser-Declarative")
    }

    /**
     * @Intent: 선언적 API 멀티파트 POST 요청의 성공 및 Content-Type, 본문 구성을 검증합니다.
     * @Given: `EmptyResponse`와 200 OK 응답이 `MockNetworkSession`에 설정됩니다. 선언적 API로 멀티파트 요청이 구성됩니다.
     * @When: `mockNetifyClient.send()`로 선언적 요청을 전송합니다.
     * @Then: 요청이 성공하고, Content-Type이 멀티파트 형식(boundary 포함)이며, 본문에 파트 데이터가 포함되었는지 확인합니다.
     */
    func testMock_Declarative_SuccessfulPOSTRequest_WithMultipartBody() async throws {
        // Given
        let textData = "Netify Declarative Multipart Test".data(using: .utf8)!
        let fileDataContent = "Fake image content".data(using: .utf8)!

        let multipartParts = [
            MultipartData(name: "description", fileData: textData, fileName: "", mimeType: "text/plain"),
            MultipartData(name: "image_file", fileData: fileDataContent, fileName: "photo.png", mimeType: "image/png")
        ]
        
        let url = try XCTUnwrap(URL(string: "\(mockBaseURL)/declarative/upload_multipart"))
        let mockResponseData = Data() // EmptyResponse를 기대하므로 빈 데이터
        let mockResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!

        mockNetworkSession.mockData = mockResponseData
        mockNetworkSession.mockResponse = mockResponse

        let declarativeRequest = Netify.post(expecting: EmptyResponse.self)
            .path("/declarative/upload_multipart")
            .multipart(multipartParts)

        // When
        _ = try await mockNetifyClient.send(declarativeRequest)

        // Then
        let lastRequest = try XCTUnwrap(mockNetworkSession.lastRequest)
        XCTAssertEqual(lastRequest.url?.absoluteString, "\(mockBaseURL)/declarative/upload_multipart")
        XCTAssertEqual(lastRequest.httpMethod, "POST")

        let contentTypeHeader = try XCTUnwrap(lastRequest.value(forHTTPHeaderField: HTTPHeaderField.contentType.rawValue))
        XCTAssertTrue(contentTypeHeader.hasPrefix(HTTPContentType.multipart.rawValue))
        XCTAssertTrue(contentTypeHeader.contains("boundary="))

        let actualBodyData = try XCTUnwrap(lastRequest.httpBody)
        XCTAssertFalse(actualBodyData.isEmpty)
        
        let bodyString = String(data: actualBodyData, encoding: .utf8) ?? ""
        XCTAssertTrue(bodyString.contains("name=\"description\""))
        XCTAssertTrue(bodyString.contains(String(data: textData, encoding: .utf8)!))
        XCTAssertTrue(bodyString.contains("name=\"image_file\""))
        XCTAssertTrue(bodyString.contains("filename=\"photo.png\""))
        XCTAssertTrue(bodyString.contains("Content-Type: image/png"))
        XCTAssertTrue(bodyString.contains(String(data: fileDataContent, encoding: .utf8)!))
    }
    
    // MARK: - Integration Tests
    // (기존 통합 테스트 코드는 NetifyRequest 프로토콜을 사용하므로 그대로 유지 또는
    //  선언적 API를 사용하는 버전으로 별도 추가/대체 가능)

    func testIntegration_fetchSinglePost_Success() async throws {
        let postIdToFetch = 1
        // 기존 프로토콜 기반 요청
        // let request = GetPlaceholderPostRequest(postId: postIdToFetch)
        
        // 선언적 API로 변경 (예시)
        let request = Netify.get(expecting: PlaceholderPost.self)
            .path("/posts/{id}")
            .pathArgument("id", postIdToFetch)
            .authentication(required: false) // JSONPlaceholder는 인증 불필요

        let post = try await integrationNetifyClient.send(request)
        
        XCTAssertEqual(post.id, postIdToFetch)
        XCTAssertEqual(post.userId, 1)
        XCTAssertEqual(post.title, "sunt aut facere repellat provident occaecati excepturi optio reprehenderit")
        XCTAssertFalse(post.body.isEmpty)
    }
    
    func testIntegration_fetchAllPosts_Success() async throws {
        // 기존 프로토콜 기반 요청
        // let request = GetAllPlaceholderPostsRequest()
        
        // 선언적 API로 변경 (예시)
        let request = Netify.get(expecting: [PlaceholderPost].self)
            .path("/posts")
            .authentication(required: false)

        let posts = try await integrationNetifyClient.send(request)
        
        XCTAssertFalse(posts.isEmpty)
        XCTAssertEqual(posts.count, 100)
        if let firstPost = posts.first {
            XCTAssertEqual(firstPost.id, 1)
            XCTAssertFalse(firstPost.title.isEmpty)
        } else {
            XCTFail("Fetched posts array was empty.")
        }
    }
    
    func testIntegration_createPost_Success() async throws {
        let newPostInput = PlaceholderPostInput(userId: 5, title: "Netify Declarative Integration Test", body: "This post was created via declarative API.")
        // 기존 프로토콜 기반 요청
        // let request = CreatePlaceholderPostRequest(postInput: newPostInput)
        
        // 선언적 API로 변경 (예시)
        let request = Netify.post(expecting: PlaceholderPost.self)
            .path("/posts")
            .body(newPostInput) // contentType은 .json으로 자동 설정
            .authentication(required: false)
        
        let createdPost: PlaceholderPost = try await integrationNetifyClient.send(request)
        
        XCTAssertNotNil(createdPost.id)
        XCTAssertGreaterThanOrEqual(createdPost.id, 101) // JSONPlaceholder는 보통 101부터 시작
        XCTAssertEqual(createdPost.title, newPostInput.title)
        XCTAssertEqual(createdPost.body, newPostInput.body)
        XCTAssertEqual(createdPost.userId, newPostInput.userId)
    }
    
    func testIntegration_HttpBin_Returns404Error() async throws {
        let httpBinBaseURL = "https://httpbin.org"
        let httpBinConfig = NetifyConfiguration(baseURL: httpBinBaseURL, logLevel: .debug, maxRetryCount: 0) // 재시도 없이 테스트
        let httpBinClient = NetifyClient(configuration: httpBinConfig)
        
        // 기존 프로토콜 기반 요청
        // let request = GetHttpBinStatusRequest(statusCode: 404)
        
        // 선언적 API로 변경 (예시)
        let request = Netify.get(expecting: Data.self) // HTTPBin은 HTML 등을 반환할 수 있어 Data로 받음
            .path("/status/{code}")
            .pathArgument("code", 404)
            .authentication(required: false)
            
        do {
            _ = try await httpBinClient.send(request)
            XCTFail("Request to HTTPBin /status/404 should have failed.")
        } catch let error as NetworkRequestError {
            if case .notFound(let data) = error {
                XCTAssertNotNil(data, "Data from HTTPBin 404 should not be nil.")
            } else {
                XCTFail("Expected .notFound from HTTPBin, got \(error)")
            }
        } catch {
            XCTFail("Expected NetworkRequestError, got \(error)")
        }
    }
}

// MARK: - Helper Functions for Tests
@available(iOS 15, macOS 12, *)
extension NetifyTests {
    func makeRealNetifyClient() -> NetifyClient {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let config = NetifyConfiguration(
            baseURL: integrationBaseURL,
            defaultEncoder: encoder, // 통합 테스트에도 일관된 인코더 적용
            defaultDecoder: decoder,
            logLevel: .debug,
            maxRetryCount: 1, // 통합 테스트 시 재시도 1회
            timeoutInterval: 30.0,
            waitsForConnectivity: false
        )
        return NetifyClient(configuration: config)
    }
}

// MARK: - Mock Types for Unit Tests
@available(iOS 15, macOS 12, *)
class MockNetworkSession: NetworkSessionProtocol {
    var lastRequest: URLRequest?
    var mockData: Data?
    var mockResponse: URLResponse?
    var simulateError: Error?
    
    func data(for request: URLRequest, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse) {
        lastRequest = request
        if let error = simulateError { throw error }
        guard let response = mockResponse else {
            throw NSError(domain: "MockNetworkSessionError", code: 1, userInfo: [NSLocalizedDescriptionKey: "mockResponse is nil."])
        }
        return (mockData ?? Data(), response)
    }
}

// MARK: - Helper Types for Mock Tests
struct MockUser: Codable, Equatable {
    let id: Int; let name: String
}

struct MockUserInput: Codable, Equatable {
    let name: String; let job: String
}

struct MockUserResponse: Codable, Equatable {
    let id: String; let name: String; let job: String; let createdAt: Date
}

struct MockItem: Codable, Equatable {
    let itemId: Int; let description: String
}

// MARK: - NetifyRequest Implementations for Mock Tests (Protocol Based)
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
    // contentType은 .json으로 기본 설정됨
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
    typealias ReturnType = Data // 에러 본문은 Data로 받는 것이 유연함
    let code: Int
    var path: String { "/status/\(code)" }
}

// MARK: - Helper Types for Integration Tests
struct PlaceholderPost: Codable, Equatable, Identifiable {
    let userId: Int; let id: Int; let title: String; let body: String
}

struct PlaceholderPostInput: Codable, Equatable {
    let userId: Int; let title: String; let body: String
}

// MARK: - NetifyRequest Implementations for Integration Tests (Protocol Based)
@available(iOS 15, macOS 12, *)
struct GetPlaceholderPostRequest: NetifyRequest {
    typealias ReturnType = PlaceholderPost
    let postId: Int
    var path: String { "/posts/\(postId)" }
    var requiresAuthentication: Bool = false
}

@available(iOS 15, macOS 12, *)
struct GetAllPlaceholderPostsRequest: NetifyRequest {
    typealias ReturnType = [PlaceholderPost]
    let path = "/posts"
    var requiresAuthentication: Bool = false
}

@available(iOS 15, macOS 12, *)
struct CreatePlaceholderPostRequest: NetifyRequest {
    typealias ReturnType = PlaceholderPost
    let path = "/posts"
    let method: HTTPMethod = .post
    let postInput: PlaceholderPostInput
    var body: Any? { postInput }
    var requiresAuthentication: Bool = false
}

@available(iOS 15, macOS 12, *)
struct GetHttpBinStatusRequest: NetifyRequest {
    typealias ReturnType = Data
    let statusCode: Int
    var path: String { "/status/\(statusCode)" }
    var requiresAuthentication: Bool = false
}
