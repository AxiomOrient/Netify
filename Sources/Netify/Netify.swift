import Foundation
import OSLog  // 로깅 프레임워크 임포트

/// Netify 클라이언트의 핵심 기능을 정의하는 프로토콜입니다.
/// 테스트 용이성을 위해 구체적인 클라이언트 구현 대신 이 프로토콜에 의존할 수 있습니다.
@available(iOS 15, macOS 12, *)
public protocol NetifyClientProtocol {
    /// Netify 클라이언트의 설정을 가져옵니다. (Mock 객체 등에서 필요할 수 있음)
    var configuration: NetifyConfiguration { get }
    
    /// 특정 NetifyRequest를 비동기적으로 보내고 응답을 처리합니다.
    func send<Request: NetifyRequest>(_ request: Request) async throws -> Request.ReturnType
}

// MARK: - Network Session Protocol Definition (for Testing)
@available(iOS 15, macOS 12, *)
public protocol NetworkSessionProtocol {
	/// Asynchronously retrieves the contents of a URL based on the specified URL request.
	/// Corresponds to URLSession.data(for:delegate:).
	func data(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws -> (Data, URLResponse)
}

// MARK: - URLSession Conformance
@available(iOS 15, macOS 12, *)
extension URLSession: NetworkSessionProtocol {} // Make URLSession conform to the protocol

// MARK: - Internal Constants
@available(iOS 15, macOS 12, *)
internal enum NetifyInternalConstants {
	/// 로깅 및 cURL 명령어 출력 시 마스킹할 민감한 HTTP 헤더 키 목록 (소문자)
	static let sensitiveHeaderKeys: Set<String> = [
		HTTPHeaderField.authorization.rawValue.lowercased(),
		"cookie",
		"set-cookie",
		"x-api-key",
		"client-secret",
		"access-token",
		"refresh-token",
		"password",
		"secret",
	]

	/// 로깅 시 요약할 최대 데이터 길이
	static let maxLogSummaryLength = 1024

	/// 기본 재시도 전 대기 시간 (나노초)
	static let defaultRetryDelayNanoseconds: UInt64 = 1_000_000_000  // 1초
}

// MARK: - Public Configuration & Basic Types

/// Netify 클라이언트의 설정을 정의하는 구조체입니다.
@available(iOS 15, macOS 12, *)
public struct NetifyConfiguration: Sendable {
	public let baseURL: String
	public let sessionConfiguration: URLSessionConfiguration
	public let defaultEncoder: JSONEncoder
	public let defaultDecoder: JSONDecoder
	public let defaultHeaders: HTTPHeaders
	public let logLevel: NetworkingLogLevel
	public let cachePolicy: URLRequest.CachePolicy
	public let maxRetryCount: Int
	public let timeoutInterval: TimeInterval
	public let authenticationProvider: AuthenticationProvider?
	public let waitsForConnectivity: Bool // URLSessionConfiguration의 waitsForConnectivity 설정

	public init(
		baseURL: String,
		sessionConfiguration: URLSessionConfiguration = .default,
		defaultEncoder: JSONEncoder = JSONEncoder(),
		defaultDecoder: JSONDecoder = JSONDecoder(),
		defaultHeaders: HTTPHeaders = [:],
		logLevel: NetworkingLogLevel = .info,
		cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
		maxRetryCount: Int = 0,
		timeoutInterval: TimeInterval = 30.0,
		authenticationProvider: AuthenticationProvider? = nil,
		waitsForConnectivity: Bool = false // 기본값은 false
	) {
		self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
		self.sessionConfiguration = sessionConfiguration
		self.defaultEncoder = defaultEncoder
		self.defaultDecoder = defaultDecoder
		self.defaultHeaders = defaultHeaders
		self.logLevel = logLevel
		self.cachePolicy = cachePolicy
		self.maxRetryCount = max(0, maxRetryCount)
		self.timeoutInterval = timeoutInterval
		self.authenticationProvider = authenticationProvider
		self.waitsForConnectivity = waitsForConnectivity

		// sessionConfiguration에 waitsForConnectivity 적용
		self.sessionConfiguration.waitsForConnectivity = waitsForConnectivity
	}
}

/// 네트워크 로깅의 상세 수준을 정의합니다.
@available(iOS 15, macOS 12, *)
public enum NetworkingLogLevel: Int, Comparable, Sendable {
	case off = 0
	case error = 1
	case info = 2
	case debug = 3

	public static func < (lhs: NetworkingLogLevel, rhs: NetworkingLogLevel) -> Bool {
		return lhs.rawValue < rhs.rawValue
	}
}

/// HTTP 요청 메서드를 정의합니다.
@available(iOS 15, macOS 12, *)
public struct HTTPMethod: RawRepresentable, Equatable, Hashable, Sendable {
	public static let get = HTTPMethod(rawValue: "GET")
	public static let post = HTTPMethod(rawValue: "POST")
	public static let put = HTTPMethod(rawValue: "PUT")
	public static let delete = HTTPMethod(rawValue: "DELETE")
	public static let patch = HTTPMethod(rawValue: "PATCH")
	public static let head = HTTPMethod(rawValue: "HEAD")
	public static let options = HTTPMethod(rawValue: "OPTIONS")

	public let rawValue: String
	public init(rawValue: String) { self.rawValue = rawValue }
}

/// HTTP 요청/응답 헤더 필드를 정의합니다.
@available(iOS 15, macOS 12, *)
public enum HTTPHeaderField: String {
	case authorization = "Authorization"
	case contentType = "Content-Type"
	case acceptType = "Accept"
	case acceptEncoding = "Accept-Encoding"
	case userAgent = "User-Agent"
	case cacheControl = "Cache-Control"
	// 필요시 추가
}

/// HTTP 요청 본문의 Content-Type을 정의합니다.
@available(iOS 15, macOS 12, *)
public enum HTTPContentType: String {
	case json = "application/json; charset=utf-8"
	case urlEncoded = "application/x-www-form-urlencoded; charset=utf-8"
	case multipart = "multipart/form-data"  // Boundary는 동적으로 추가됨
	case plainText = "text/plain; charset=utf-8"
	case xml = "application/xml; charset=utf-8"
	// 필요시 추가
}

/// 빈 응답 본문을 나타내는 타입입니다. 성공했지만 내용이 없는 경우 (예: 204 No Content) 사용될 수 있습니다.
@available(iOS 15, macOS 12, *)
public struct EmptyResponse: Decodable {}

/// 쿼리 파라미터 타입 별칭입니다.
@available(iOS 15, macOS 12, *)
public typealias QueryParameters = [String: String]

/// HTTP 헤더 타입 별칭입니다.
@available(iOS 15, macOS 12, *)
public typealias HTTPHeaders = [String: String]

/// 사용자 자격 증명 (기본 인증용)
@available(iOS 15, macOS 12, *)
public struct UserCredentials: Sendable {
	let username: String
	let password: String

	var basicAuthHeaderValue: String {
		let loginString = "\(username):\(password)"
		return "Basic \(Data(loginString.utf8).base64EncodedString())"
	}

	public init(username: String, password: String) {
		self.username = username
		self.password = password
	}
}

// MARK: - Logging Protocol & Implementation

/// Netify 내에서 네트워크 요청 및 응답 로깅을 위한 프로토콜입니다.
@available(iOS 15, macOS 12, *)
public protocol NetifyLogging {
	var logLevel: NetworkingLogLevel { get }
	func log(message: String, level: OSLogType)
	func log(request: URLRequest, level: OSLogType)
	func log(response: URLResponse, data: Data?, level: OSLogType)
	func log(error: Error, level: OSLogType)
}

/// os.Logger를 사용하는 NetifyLogging의 기본 구현체입니다.
@available(iOS 15, macOS 12, *)
public struct DefaultNetifyLogger: NetifyLogging {
	public let logLevel: NetworkingLogLevel
	private let logger: Logger

	public init(
		logLevel: NetworkingLogLevel,
		subsystem: String = Bundle.main.bundleIdentifier ?? "com.example.netify",
		category: String = "Netify"
	) {
		self.logLevel = logLevel
		self.logger = Logger(subsystem: subsystem, category: category)
	}

	public func log(message: String, level: OSLogType = .debug) {
		guard shouldLog(level: level) else { return }
		logger.log(level: level, "\(message)")
	}

	public func log(request: URLRequest, level: OSLogType = .debug) {
		guard shouldLog(level: level) else { return }

		var logMessage =
			"\n➡️ Request: \(request.httpMethod ?? "Unknown") \(request.url?.absoluteString ?? "Unknown URL")"

		if logLevel >= .debug {
			if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
				logMessage += "\n    Headers: \(maskSensitiveHeaders(headers))"
			}
			if let bodyData = request.httpBody, !bodyData.isEmpty {
				let bodySummary = summarizeData(
					bodyData,
					contentType: request.value(
						forHTTPHeaderField: HTTPHeaderField.contentType.rawValue))
				logMessage += "\n    Body: \(bodySummary)"
			} else if let stream = request.httpBodyStream {
				logMessage += "\n    Body: InputStream \(stream.description)"
			}
			logMessage += "\n    cURL: \(request.toCurlCommand())"
		}
		logger.log(level: level, "\(logMessage)")
	}

	public func log(response: URLResponse, data: Data?, level: OSLogType = .debug) {
		guard shouldLog(level: level) else { return }

		var logMessage = "\n⬅️ Response:"
		if let httpResponse = response as? HTTPURLResponse {
			logMessage +=
				" Status Code \(httpResponse.statusCode) from \(response.url?.absoluteString ?? "Unknown URL")"
			if logLevel >= .debug {
				if let headers = httpResponse.allHeaderFields as? HTTPHeaders, !headers.isEmpty {
					logMessage += "\n    Headers: \(maskSensitiveHeaders(headers))"
				}
				if let data = data, !data.isEmpty {
					let dataSummary = summarizeData(
						data,
						contentType: httpResponse.value(
							forHTTPHeaderField: HTTPHeaderField.contentType.rawValue))
					logMessage += "\n    Data: \(dataSummary)"
				} else {
					logMessage += data == nil ? " (No data)" : " (Empty data: \(data!.count) bytes)"
				}
			} else if logLevel >= .info, let data = data {
				logMessage += " (\(data.count) bytes)"
			}
		} else {
			logMessage +=
				" \(response.url?.absoluteString ?? "Unknown URL") (\(type(of: response)))"
		}
		logger.log(level: level, "\(logMessage)")
	}

	// Error logging now consistently handles NetworkRequestError and other errors
	public func log(error: Error, level: OSLogType = .error) {
		guard shouldLog(level: level) else { return }
		var logMessage = "\n❌ Error:"
		if let netifyError = error as? NetworkRequestError {
			logMessage += " \(netifyError.localizedDescription)"  // Use localizedDescription first
			if logLevel >= .debug {
				logMessage += "\n    Details: \(netifyError.debugDescription)"  // Add debug details if needed
			}
		} else {
			// For non-NetworkRequestError types
			logMessage += " \(error.localizedDescription)"
			if logLevel >= .debug {
				logMessage += "\n    Type: \(type(of: error))\n    Raw Error Details: \(error)"  // Show raw error in debug
			}
		}
		logger.log(level: level, "\(logMessage)")
	}

	private func shouldLog(level: OSLogType) -> Bool {
		let currentLevelValue = self.logLevel.rawValue
		let targetLevelValue: Int
		switch level {
		case .debug: targetLevelValue = NetworkingLogLevel.debug.rawValue
		case .info: targetLevelValue = NetworkingLogLevel.info.rawValue  // .notice 제거
		case .error, .fault: targetLevelValue = NetworkingLogLevel.error.rawValue
		default: targetLevelValue = NetworkingLogLevel.off.rawValue
		}
		return currentLevelValue >= targetLevelValue
	}

	private func maskSensitiveHeaders(_ headers: HTTPHeaders) -> HTTPHeaders {
		var maskedHeaders = headers
		// Use the centralized sensitive keys constant
		for (key, _) in headers
		where NetifyInternalConstants.sensitiveHeaderKeys.contains(key.lowercased()) {
			maskedHeaders[key] = "<masked>"
		}
		return maskedHeaders
	}

	private func summarizeData(_ data: Data, contentType: String?) -> String {
		let maxLen = NetifyInternalConstants.maxLogSummaryLength
		if let contentType = contentType?.lowercased(),
			contentType.contains("json") || contentType.contains("text")
				|| contentType.contains("xml") || contentType.contains("urlencoded"),
			let stringValue = String(data: data, encoding: .utf8)
		{
			return stringValue.count > maxLen
				? "\(stringValue.prefix(maxLen))... (\(data.count) bytes total)" : stringValue
		}
		return "<binary data: \(data.count) bytes>"
	}
}

// MARK: - Network Request Error

/// 네트워크 요청 처리 중 발생할 수 있는 에러 타입입니다.
@available(iOS 15, macOS 12, *)
public enum NetworkRequestError: LocalizedError, Equatable {
	/// 요청 구성 오류 (URL 생성 실패, 미지원 인코딩 등).
	case invalidRequest(reason: String)
	/// HTTP 응답이 아닌 경우 또는 응답 객체 자체가 없는 경우.
	case invalidResponse(response: URLResponse?)
	/// 400 Bad Request.
	case badRequest(data: Data?)
	/// 401 Unauthorized.
	case unauthorized(data: Data?)
	/// 403 Forbidden.
	case forbidden(data: Data?)
	/// 404 Not Found.
	case notFound(data: Data?)
	/// 기타 4xx 클라이언트 에러.
	case clientError(statusCode: Int, data: Data?)
	/// 5xx 서버 에러.
	case serverError(statusCode: Int, data: Data?)
	/// 응답 데이터 디코딩 실패. `underlyingError`에 원본 `Error` 포함. `data`는 디코딩 시도된 데이터.
	case decodingError(underlyingError: Error, data: Data?)
	/// 요청 본문 인코딩 실패. `underlyingError`에 원본 `Error` 포함.
	case encodingError(underlyingError: Error)
	/// URLSession 레벨 에러 (네트워크 연결 문제 등). `underlyingError`에 원본 `Error` 포함.
	case urlSessionFailed(underlyingError: Error)
	/// 기타 알 수 없는 에러. `underlyingError`에 원본 `Error` 포함 가능.
	case unknownError(underlyingError: Error?)
	/// 사용자 또는 시스템에 의해 취소됨.
	case cancelled
	/// 요청 시간 초과.
	case timedOut
	/// 인터넷 연결 없음.
	case noInternetConnection

	public var errorDescription: String? {
		switch self {
		case .invalidRequest(let reason): return "Invalid Request: \(reason)"
		case .invalidResponse: return "Invalid Response (Non-HTTP or malformed)"
		case .badRequest: return "Bad Request (400)"
		case .unauthorized: return "Unauthorized (401)"
		case .forbidden: return "Forbidden (403)"
		case .notFound: return "Not Found (404)"
		case .clientError(let code, _): return "Client Error (\(code))"
		case .serverError(let code, _): return "Server Error (\(code))"
		case .decodingError(let error, _): return "Decoding Error: \(error.localizedDescription)"
		case .encodingError(let error): return "Encoding Error: \(error.localizedDescription)"
		case .urlSessionFailed(let error): return "URLSession Failed: \(error.localizedDescription)"
		case .unknownError(let error):
			return "Unknown Error: \(error?.localizedDescription ?? "N/A")"
		case .cancelled: return "Request Cancelled"
		case .timedOut: return "Request Timed Out"
		case .noInternetConnection: return "No Internet Connection"
		}
	}

	// Provides more detailed debugging information, including underlying errors and data snippets.
	public var debugDescription: String {
        var desc = "\(self.localizedDescription) : \(String(describing: self))"
		switch self {
		case .invalidRequest(let reason): desc += "\nReason: \(reason)"
		case .invalidResponse(let resp): desc += "\nResponse: \(String(describing: resp))"
		case .badRequest(let d), .unauthorized(let d), .forbidden(let d), .notFound(let d),
			.clientError(_, let d), .serverError(_, let d):
			if let data = d { desc += formatDataForDebug(data) }
		case .decodingError(let err, let d):
			desc += "\nUnderlying Error: \(err)"
			if let data = d {
				desc += formatDataForDebug(data, prefix: "Response Body (Decoding Failed On)")
			}
		case .encodingError(let err): desc += "\nUnderlying Error: \(err)"
		case .urlSessionFailed(let err):
			desc += "\nUnderlying Error: \(err)"
			if let urlError = err as? URLError {
				desc += "\nURLError Code: \(urlError.code.rawValue), UserInfo: \(urlError.userInfo)"
			}
		case .unknownError(let err):
			if let error = err { desc += "\nUnderlying Error: \(error)" }
		default: break  // No extra details for cancelled, timedOut, noInternetConnection
		}
		return desc
	}

	// Helper to format data for debugDescription
	private func formatDataForDebug(_ data: Data, prefix: String = "Response Body") -> String {
		if let body = String(data: data, encoding: .utf8) {
			let maxLen = NetifyInternalConstants.maxLogSummaryLength
			return
				"\n\(prefix): \(body.prefix(maxLen))\(body.count > maxLen ? "..." : "") (\(data.count) bytes)"
		} else {
			return "\n\(prefix) Data: \(data.count) bytes (Non-UTF8)"
		}
	}

	public var isRetryable: Bool {
		switch self {
		case .serverError: return true  // 5xx errors are often temporary
		case .timedOut: return true
		case .noInternetConnection: return true  // Can retry when connection is back
		case .urlSessionFailed(let error):
			// Retry for specific network-related URLErrors
			if let urlError = error as? URLError {
				return [
					.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotFindHost,
					.cannotConnectToHost,
				].contains(urlError.code)
			}
			return false
		default: return false  // Client errors, decoding/encoding errors, invalid requests are generally not retryable
		}
	}

	// Equatable conformance for testing and comparison
	public static func == (lhs: NetworkRequestError, rhs: NetworkRequestError) -> Bool {
		switch (lhs, rhs) {
		case (.invalidRequest(let l), .invalidRequest(let r)): return l == r
		// Compare only the type for errors with associated objects/data
		case (.invalidResponse, .invalidResponse): return true
		case (.badRequest, .badRequest): return true
		case (.unauthorized, .unauthorized): return true
		case (.forbidden, .forbidden): return true
		case (.notFound, .notFound): return true
		case (.clientError(let lc, _), .clientError(let rc, _)): return lc == rc
		case (.serverError(let lc, _), .serverError(let rc, _)): return lc == rc
		// For errors with underlying errors, comparing types might be enough, or compare underlying NSError domain/code
		// For non-optional underlying errors, 'as NSError' is safe due to Swift's bridging if the compiler warning
		// "Conditional cast from 'any Error' to 'NSError' always succeeds" is heeded.
		case (.decodingError(let lhsError, _), .decodingError(let rhsError, _)):
			let lns = lhsError as NSError
			let rns = rhsError as NSError
			return lns.domain == rns.domain && lns.code == rns.code
		case (.encodingError(let lhsError), .encodingError(let rhsError)):
			let lns = lhsError as NSError
			let rns = rhsError as NSError
			return lns.domain == rns.domain && lns.code == rns.code
		case (.urlSessionFailed(let lhsError), .urlSessionFailed(let rhsError)):
			let lns = lhsError as NSError
			let rns = rhsError as NSError
			return lns.domain == rns.domain && lns.code == rns.code
		case (.unknownError(let le), .unknownError(let re)):
			// For optional underlying errors, 'as? NSError' correctly handles nil.
			// The warning on this line is about the cast itself if 'le' or 're' are non-nil,
			// but the if-let structure is sound for handling optionality.
			if le == nil && re == nil { return true }
			if let lerr = le as NSError?, let rerr = re as NSError? {
				return lerr.domain == rerr.domain && lerr.code == rerr.code
			}
			return false  // Can't compare reliably
		case (.cancelled, .cancelled): return true
		case (.timedOut, .timedOut): return true
		case (.noInternetConnection, .noInternetConnection): return true
		default: return false
		}
	}
}

// MARK: - Netify Request Protocol

/// API 요청 명세를 정의하는 프로토콜입니다.
@available(iOS 15, macOS 12, *)
public protocol NetifyRequest {
	/// 응답으로 기대하는 타입 (**Decodable** 준수). `EmptyResponse`를 사용하여 내용 없는 성공 응답을 나타낼 수 있습니다.
	associatedtype ReturnType: Decodable

	var path: String { get }
	var method: HTTPMethod { get }
	var contentType: HTTPContentType { get }  // 요청 본문 타입
	var queryParams: QueryParameters? { get }
	/// 요청 본문. JSON으로 보내려면 `Encodable`이어야 하고, URL 인코딩은 `[String: String]`, PlainText는 `String`이어야 함.
	var body: Any? { get }
	var headers: HTTPHeaders? { get }
	var multipartData: [MultipartData]? { get }
	var decoder: JSONDecoder? { get }  // 요청별 디코더 (기본값: 클라이언트 설정 사용)
	var cachePolicy: URLRequest.CachePolicy? { get }
	var timeoutInterval: TimeInterval? { get }
	var requiresAuthentication: Bool { get }
}

// Default implementations for NetifyRequest protocol
@available(iOS 15, macOS 12, *)
extension NetifyRequest {
	public var method: HTTPMethod { .get }
	public var contentType: HTTPContentType { .json }  // Default assumes JSON body if 'body' is provided
	public var queryParams: QueryParameters? { nil }
	public var body: Any? { nil }
	public var headers: HTTPHeaders? { nil }
	public var multipartData: [MultipartData]? { nil }
	public var decoder: JSONDecoder? { nil }
	public var cachePolicy: URLRequest.CachePolicy? { nil }
	public var timeoutInterval: TimeInterval? { nil }
	public var requiresAuthentication: Bool { true }  // Default to requiring authentication
}

// MARK: - Authentication Provider Protocol & Implementations

/// 인증 관련 동작을 정의하는 프로토콜입니다.
@available(iOS 15, macOS 12, *)
public protocol AuthenticationProvider: Sendable {
	/// 요청에 인증 정보를 비동기적으로 추가합니다.
	/// - Throws: 인증 정보 추가 중 발생할 수 있는 오류 (예: 자격 증명 로드 실패).
	func authenticate(request: URLRequest) async throws -> URLRequest

	/// 인증 토큰 만료 시 호출되어 비동기적으로 갱신을 시도합니다.
	/// - Returns: 갱신 성공 여부.
	/// - Throws: 갱신 중 발생한 오류 (예: 네트워크 오류, 서버 오류).
	func refreshAuthentication() async throws -> Bool

	/// 주어진 에러가 인증 만료(예: 401 Unauthorized)를 나타내는지 확인합니다.
	func isAuthenticationExpired(from error: Error) -> Bool
}

/// HTTP 기본 인증 프로바이더입니다.
@available(iOS 15, macOS 12, *)
public struct BasicAuthenticationProvider: AuthenticationProvider, Sendable {
	private let credentials: UserCredentials

	public init(credentials: UserCredentials) {
		self.credentials = credentials
	}

	public func authenticate(request: URLRequest) async throws -> URLRequest {
		var req = request
		req.setValue(
			credentials.basicAuthHeaderValue,
			forHTTPHeaderField: HTTPHeaderField.authorization.rawValue)
		return req
	}

	// Basic Auth does not support refreshing
	public func refreshAuthentication() async throws -> Bool { false }

	public func isAuthenticationExpired(from error: Error) -> Bool {
		// Consider 401 Unauthorized as expired for Basic Auth
		if let netErr = error as? NetworkRequestError, case .unauthorized = netErr { return true }
		return false
	}
}

/// Bearer 토큰 인증 프로바이더입니다. (토큰 관리 및 갱신 로직 포함)
@available(iOS 15, macOS 12, *)
public actor BearerTokenAuthenticationProvider: AuthenticationProvider {
	private var accessToken: String
	private var refreshToken: String?
	private let refreshHandler: RefreshTokenHandler?
	private var refreshTask: Task<Bool, Error>?  // Task to prevent concurrent refresh attempts

	/// 리프레시 토큰을 사용하여 새 토큰 정보를 가져오는 클로저 타입.
	/// - Parameter refreshToken: 현재 리프레시 토큰.
	/// - Returns: 새로 발급받은 토큰 정보 (`TokenInfo`).
	/// - Throws: 토큰 갱신 중 발생한 오류.
	public typealias RefreshTokenHandler = @Sendable (String) async throws -> TokenInfo

	/// 갱신된 토큰 정보를 담는 구조체.
	public struct TokenInfo: Codable, Sendable {
		public let accessToken: String
		public let refreshToken: String?
		public let expiresIn: TimeInterval?  // Optional expiration time (seconds)

		public init(
			accessToken: String, refreshToken: String? = nil, expiresIn: TimeInterval? = nil
		) {
			self.accessToken = accessToken
			self.refreshToken = refreshToken
			self.expiresIn = expiresIn
		}
	}

	public init(
		accessToken: String, refreshToken: String? = nil, refreshHandler: RefreshTokenHandler? = nil
	) {
		self.accessToken = accessToken
		self.refreshToken = refreshToken
		self.refreshHandler = refreshHandler
	}

	public func authenticate(request: URLRequest) async throws -> URLRequest {
		var req = request
		req.setValue(
			"Bearer \(accessToken)", forHTTPHeaderField: HTTPHeaderField.authorization.rawValue)
		return req
	}

	public func refreshAuthentication() async throws -> Bool {
		// If a refresh task is already running, wait for its result
		if let existingTask = refreshTask {
			return try await existingTask.value
		}

		// Check if refresh is possible
		guard let currentRefreshToken = refreshToken, let handler = refreshHandler else {
			return false  // Cannot refresh without refresh token or handler
		}

		// Create a new Task to perform the refresh
		let task = Task { () -> Bool in
			// Use defer to ensure refreshTask is nilled out when the task completes
			defer { self.refreshTask = nil }

			// Call the handler to get new tokens
			let newTokens = try await handler(currentRefreshToken)

			// Update the tokens within the actor
			self.accessToken = newTokens.accessToken
			// Keep the old refresh token if the handler didn't provide a new one
			self.refreshToken = newTokens.refreshToken ?? currentRefreshToken

			// Optionally handle expiresIn (e.g., schedule next refresh)

			return true  // Indicate refresh was successful
		}

		// Store the reference to the running task
		self.refreshTask = task

		// Wait for the task to complete and return its result
		return try await task.value
	}

	// Checks if the error specifically indicates an expired token (e.g., 401)
	public nonisolated func isAuthenticationExpired(from error: Error) -> Bool {  // nonisolated 추가
		if let netErr = error as? NetworkRequestError, case .unauthorized = netErr { return true }
		// Optionally check for specific underlying error codes if the API provides them
		return false
	}

	// Allows external updates to tokens (e.g., after login)
	public func updateTokens(accessToken: String, refreshToken: String?) {
		self.accessToken = accessToken
		self.refreshToken = refreshToken
	}

	// Provides read-only access to the current access token
	public func getCurrentAccessToken() -> String { accessToken }
}

// MARK: - Multipart Data Structures

/// HTTP 요청 본문의 일부를 나타내는 프로토콜입니다 (주로 멀티파트).
@available(iOS 15, macOS 12, *)
public protocol HttpBodyConvertible {
	func buildHttpBodyPart(boundary: String) -> Data
}

/// 멀티파트 요청에 포함될 파일 또는 데이터 청크를 나타냅니다.
@available(iOS 15, macOS 12, *)
public struct MultipartData: Identifiable, HttpBodyConvertible {
	public let id = UUID()
	let name: String  // The name of the form field
	let fileData: Data  // The actual data for the part
	let fileName: String  // The filename to associate with the data
	let mimeType: String  // The MIME type of the data (e.g., "image/jpeg")

	public init(name: String, fileData: Data, fileName: String, mimeType: String) {
		self.name = name
		self.fileData = fileData
		self.fileName = fileName
		self.mimeType = mimeType
	}

	// Builds the Data representation for this part in a multipart/form-data request
	public func buildHttpBodyPart(boundary: String) -> Data {
		let body = NSMutableData()
		// Boundary marker
		body.appendString("--\(boundary)\r\n")
		// Content-Disposition header
		body.appendString(
			"Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n")
		// Content-Type header
		body.appendString("Content-Type: \(mimeType)\r\n\r\n")  // Extra CRLF before data
		// Actual data
		body.append(fileData)
		// CRLF after data
		body.appendString("\r\n")
		return body as Data
	}
}

// MARK: - URL Utilities & Extensions

/// URL 경로 결합을 위한 헬퍼 구조체입니다.
@available(iOS 15, macOS 12, *)
public struct URLPathBuilder {
	/// Combines a base URL string and a path string into a URL object.
	/// Handles potential slashes between the base URL path and the provided path.
	public static func buildURL(baseURL: String, path: String) throws -> URL {
		guard var components = URLComponents(string: baseURL) else {
			throw NetworkRequestError.invalidRequest(reason: "Invalid base URL string: \(baseURL)")
		}

		// Ensure the path component combination is correct
		let basePath = components.path  // Path from the base URL itself
		let separator =
			(basePath.isEmpty || basePath.hasSuffix("/") || path.starts(with: "/")) ? "" : "/"
		let combinedPath = basePath + separator + path

		// Normalize path: remove duplicate slashes if any resulted
		components.path = combinedPath.split(separator: "/", omittingEmptySubsequences: true)
			.joined(separator: "/")
		// Ensure path starts with / if it's not empty
		if !components.path.isEmpty && !components.path.starts(with: "/") {
			components.path = "/" + components.path
		}

		guard let url = components.url else {
			// This should rarely fail if components were valid initially
			throw NetworkRequestError.invalidRequest(
				reason:
					"Failed to construct final URL from baseURL ('\(baseURL)') and path ('\(path)')"
			)
		}
		return url
	}
}

@available(iOS 15, macOS 12, *)
extension CharacterSet {
	/// Character set allowed in URL query value encoding according to RFC 3986.
	/// Includes alphanumerics and '-', '.', '_', '~'. Excludes general delimiters and sub-delimiters.
	public static let urlQueryValueAllowed: CharacterSet = {
		// Start with the base set allowed in query components
		var allowed = CharacterSet.urlQueryAllowed
		// Remove characters that should be percent-encoded in query *values*
		// According to RFC 3986, '&' and '=' can be part of a query key/value pair itself,
		// but often need encoding if they appear *within* a value. '+' is often used for space.
		// Common practice is to encode: '&', '=', '+', ';', '/', '?', ':', '@', '$', ',', '#', '['. ']'
		allowed.remove(charactersIn: "!$&'()*+,/:;=?@#[]")  // Removed space as well, use %20 or '+' encoding handled by addingPercentEncoding
		return allowed
	}()
}

/// QueryParameters ([String: String])를 URL 쿼리 문자열 또는 URLQueryItem 배열로 변환하는 확장입니다.
@available(iOS 15, macOS 12, *)
extension Dictionary where Key == String, Value == String {
	/// Converts the dictionary into a URL-encoded query string (e.g., "key1=value1&key2=value2").
	/// Values are percent-encoded using `CharacterSet.urlQueryValueAllowed`.
	public func toUrlEncodedQueryString() -> String? {
		guard !isEmpty else { return nil }
		return map { key, value in
			// Key encoding might also be needed depending on server, but less common
			let escapedKey =
				key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
			let escapedValue =
				value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? value
			return "\(escapedKey)=\(escapedValue)"
		}.joined(separator: "&")
	}

	/// Converts the dictionary into an array of URLQueryItem objects.
	public func toURLQueryItems() -> [URLQueryItem]? {
		guard !isEmpty else { return nil }
		// URLQueryItem handles encoding internally based on context
		return map { URLQueryItem(name: $0.key, value: $0.value) }
	}
}

/// NSMutableData에 문자열을 UTF-8 데이터로 추가하는 내부 확장 기능입니다.
extension NSMutableData {
	/// Appends the specified string to the mutable data using UTF-8 encoding.
	func appendString(_ string: String) {
		if let data = string.data(using: .utf8) {
			self.append(data)
		}
		// Consider logging a warning if string.data(using:) returns nil
	}
}

/// URLRequest를 cURL 명령어 문자열로 변환하는 확장 기능입니다 (디버깅 목적).
@available(iOS 15, macOS 12, *)
extension URLRequest {
	/// Generates a cURL command string representation of the URLRequest for debugging.
	/// Sensitive headers (Authorization, Cookie, etc.) are masked.
	public func toCurlCommand() -> String {
		guard let url = url else { return "# Netify: Invalid URL for cURL command" }
		var command = [#"curl -v "\#(url.absoluteString)""#]  // Use -v for verbose output

		// Add method if not GET (default for curl)
		if let httpMethod = httpMethod, httpMethod != "GET" {
			command.append("-X \(httpMethod)")
		}

		// Add headers, masking sensitive ones
		allHTTPHeaderFields?.sorted(by: { $0.key < $1.key }).forEach { key, value in
			// Use the centralized sensitive keys constant for masking
			let displayValue =
				NetifyInternalConstants.sensitiveHeaderKeys.contains(key.lowercased())
				? "<masked>" : value
			// Escape single quotes in header values if necessary
			let escapedValue = displayValue.replacingOccurrences(of: "'", with: "'\\''")
			command.append("-H '\(key): \(escapedValue)'")
		}

		// Add body data
		if let data = httpBody {
			// Try to represent as UTF-8 string if possible, otherwise indicate binary data
			if let bodyString = String(data: data, encoding: .utf8), !bodyString.isEmpty {
				let maxLen = NetifyInternalConstants.maxLogSummaryLength
				let truncatedBody = bodyString.prefix(maxLen)
				// Escape single quotes in body for the command line
				let escapedBody = String(truncatedBody).replacingOccurrences(of: "'", with: "'\\''")
				command.append("-d '\(escapedBody)\(bodyString.count > maxLen ? "..." : "")'")
			} else if !data.isEmpty {
				command.append("--data-binary @'<binary_data>' # Body contains \(data.count) bytes")
			}
		} else if let stream = httpBodyStream {
			// Indicate that body comes from a stream
			command.append(
				"--data-binary @'<input_stream_data>' # Body from InputStream: \(stream.description)"
			)
		}

		// Join parts with line continuation for readability
		return command.joined(separator: " \\\n    ")
	}
}

// MARK: - Netify Client (Core Logic)

/// 실제 네트워크 요청 실행 및 관리를 담당하는 클라이언트입니다.
@available(iOS 15, macOS 12, *)
public final class NetifyClient: NetifyClientProtocol { // 프로토콜 준수 추가
    public let configuration: NetifyConfiguration
	// private let urlSession: URLSession // <-- 기존 라인 제거
	private let networkSession: NetworkSessionProtocol // <-- 프로토콜 타입으로 변경
	private let logger: NetifyLogging
	private let requestBuilder: RequestBuilder

	/// Netify 클라이언트를 초기화합니다.
	/// - Parameter configuration: 클라이언트 동작을 정의하는 설정 객체.
	/// - Parameter networkSession: 네트워크 요청을 처리할 세션 객체 (테스트 목적으로 주입 가능).
	///                           기본값은 `configuration`에 기반한 `URLSession`입니다.
	public init(configuration: NetifyConfiguration, networkSession: NetworkSessionProtocol? = nil) {
		self.configuration = configuration
		// 주입받은 세션 사용, 없으면 configuration 기반으로 생성
		self.networkSession = networkSession ?? URLSession(configuration: configuration.sessionConfiguration)
		self.logger = DefaultNetifyLogger(logLevel: configuration.logLevel) // 필요시 커스텀 로거 주입 가능하도록 개선 가능
		self.requestBuilder = RequestBuilder(configuration: configuration, logger: logger)
		logger.log(
			message:
				"NetifyClient Initialized. BaseURL: \(configuration.baseURL), LogLevel: \(configuration.logLevel)",
			level: .info)
	}

	/// 특정 NetifyRequest를 비동기적으로 보내고 응답을 처리합니다.
	/// 재시도 및 인증 토큰 갱신 로직을 포함합니다.
	/// - Parameter request: 보낼 NetifyRequest 구현체.
	/// - Returns: 요청의 ReturnType으로 지정된 디코딩된 객체.
	/// - Throws: NetworkRequestError 또는 인증/요청 생성 중 발생한 기타 오류.
	public func send<Request: NetifyRequest>(_ request: Request) async throws -> Request.ReturnType
	{
		try await sendRequestWithRetry(request, currentRetry: 0)
	}

	/// 재시도 및 인증 갱신 로직을 포함하여 요청을 처리하는 내부 메서드입니다.
	private func sendRequestWithRetry<Request: NetifyRequest>(_ request: Request, currentRetry: Int)
		async throws -> Request.ReturnType
	{
		// 1. Build URLRequest
		var urlRequest: URLRequest
		do {
			urlRequest = try await requestBuilder.buildURLRequest(from: request)
			logger.log(request: urlRequest, level: .debug)  // Log the built request
		} catch {
			// Consistently map any request building error
			let netifyError = mapToNetifyError(error)
			logger.log(error: netifyError, level: .error)
			throw netifyError
		}

		// 2. Perform Network Request and Handle Response/Errors
		do {
			let (data, response) = try await performDataTask(for: urlRequest)
			logger.log(response: response, data: data, level: .debug)  // Log response summary

			// Process the response (checks status code, decodes data)
			// This can throw NetworkRequestError (e.g., decodingError, badResponse)
			return try handleResponse(response: response, data: data, request: request)

		} catch let error {
			// Map any error occurred during data task or response handling
			let netifyError = mapToNetifyError(error)
			logger.log(error: netifyError, level: .error)  // Log the mapped error

			// 3. Handle Authentication Failure (if applicable)
			if request.requiresAuthentication,
				let authProvider = configuration.authenticationProvider,
				authProvider.isAuthenticationExpired(from: netifyError)
			{

				logger.log(
					message: "Authentication expired detected. Attempting refresh...", level: .info)
				// Attempt to refresh authentication. Extracted to a helper function.
				let refreshSuccess = await attemptAuthRefresh(authProvider: authProvider)

				if refreshSuccess {
					logger.log(
						message: "Authentication refreshed. Retrying original request...",
						level: .info)
					// If refresh succeeded, retry the request immediately *without* incrementing the retry count for this specific failure.
					// Pass the *same* currentRetry count to the recursive call.
					return try await sendRequestWithRetry(request, currentRetry: currentRetry)
				} else {
					logger.log(
						message:
							"Authentication refresh failed or not supported. Throwing original error.",
						level: .error)
					// If refresh failed, throw the original error that triggered the refresh attempt (e.g., .unauthorized)
					throw netifyError
				}
			}

			// 4. Handle General Retries (if applicable)
			if netifyError.isRetryable && currentRetry < configuration.maxRetryCount {
				logger.log(
					message:
                        "Request failed with retryable error. Retrying (\(currentRetry + 1)/\(configuration.maxRetryCount)). Error: \(netifyError.localizedDescription)",
					level: .info)

				// Wait before retrying (simple delay)
				try? await Task.sleep(
					nanoseconds: NetifyInternalConstants.defaultRetryDelayNanoseconds)

				// Check if the task was cancelled during sleep
				try Task.checkCancellation()  // Throws CancellationError if cancelled

				// Perform the recursive call, incrementing the retry count
				return try await sendRequestWithRetry(request, currentRetry: currentRetry + 1)
			}

			// If not retryable, or max retries reached, or refresh failed, throw the final error
			throw netifyError
		}
	}

	/// Executes the URLSession data task using the injected NetworkSessionProtocol.
	/// Uses `networkSession.data(for:delegate:)`.
	private func performDataTask(for request: URLRequest) async throws -> (Data, URLResponse) {
		// This method throws errors like URLError, which will be caught and mapped by the caller.
		try await networkSession.data(for: request, delegate: nil) // <-- networkSession 사용
	}

	/// Processes the URLResponse and Data, handling status codes and decoding.
	/// Throws `NetworkRequestError` for non-2xx status codes or decoding issues.
	/// Handles `EmptyResponse` correctly.
	private func handleResponse<Request: NetifyRequest>(
		response: URLResponse, data: Data, request: Request
	) throws -> Request.ReturnType {
		guard let httpResponse = response as? HTTPURLResponse else {
			// Should not happen with standard HTTP requests, but handle defensively.
			throw NetworkRequestError.invalidResponse(response: response)
		}

		// Validate status code range (200-299 indicate success)
		guard (200...299).contains(httpResponse.statusCode) else {
			// Map non-success status codes to specific errors
			throw mapStatusCodeToError(statusCode: httpResponse.statusCode, data: data)
		}

		// Handle successful response (2xx)
		if data.isEmpty {
			// If data is empty, check if the expected type is EmptyResponse or Data
			if Request.ReturnType.self == EmptyResponse.self {
				// Safely cast and return EmptyResponse instance
				guard let empty = EmptyResponse() as? Request.ReturnType else {
					// This cast should theoretically always succeed due to the type check
					throw NetworkRequestError.unknownError(
						underlyingError: NSError(
							domain: "Netify", code: -2,
							userInfo: [
								NSLocalizedDescriptionKey:
									"Internal error: Failed to cast EmptyResponse"
							]))
				}
				return empty
			} else if Request.ReturnType.self == Data.self {
				// Safely cast and return the empty Data object
				guard let emptyData = data as? Request.ReturnType else {
					throw NetworkRequestError.unknownError(
						underlyingError: NSError(
							domain: "Netify", code: -3,
							userInfo: [
								NSLocalizedDescriptionKey:
									"Internal error: Failed to cast empty Data"
							]))
				}
				return emptyData
			} else {
				// If expecting any other Decodable type, empty data is an error.
				throw NetworkRequestError.decodingError(
					underlyingError: NSError(
						domain: "Netify", code: -1,
						userInfo: [
							NSLocalizedDescriptionKey:
								"Expected non-empty response body for type \(Request.ReturnType.self) but received empty data."
						]),
					data: data
				)
			}
		} else {
			// Non-empty data, attempt to decode
			do {
				let decoder = request.decoder ?? configuration.defaultDecoder
				return try decoder.decode(Request.ReturnType.self, from: data)
			} catch let decodingError {
				// Wrap the actual decoding error from the JSONDecoder
				throw NetworkRequestError.decodingError(underlyingError: decodingError, data: data)
			}
		}
	}

	/// Extracted helper function to attempt authentication refresh.
	/// Returns `true` if refresh was successful, `false` otherwise.
	/// Logs errors internally if refresh fails.
	private func attemptAuthRefresh(authProvider: AuthenticationProvider) async -> Bool {
		do {
			logger.log(message: "Calling authProvider.refreshAuthentication()", level: .debug)
			// Wait for the provider's refresh logic to complete
			let success = try await authProvider.refreshAuthentication()
			logger.log(message: "Auth refresh attempt finished. Success: \(success)", level: .info)
			return success
		} catch {
			// Map and log any error during the refresh process
			let refreshError = mapToNetifyError(error)
			logger.log(error: refreshError, level: .error)
			return false  // Indicate refresh failed
		}
	}

	/// Consistently maps various `Error` types to `NetworkRequestError`.
	/// Handles common errors like `URLError`, `EncodingError`, `DecodingError`, and `CancellationError`.
	private func mapToNetifyError(_ error: Error) -> NetworkRequestError {
		switch error {
		// If it's already a NetworkRequestError, return it directly
		case let netifyError as NetworkRequestError:
			return netifyError

		// Handle URLSession specific errors
		case let urlError as URLError:
			switch urlError.code {
			case .cancelled: return .cancelled
			case .timedOut: return .timedOut
			case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotFindHost,
				.cannotConnectToHost:
				return .noInternetConnection  // Group common connectivity issues
			// Add more specific URLError mappings if needed
			default:
				return .urlSessionFailed(underlyingError: urlError)
			}

		// Handle standard Swift encoding/decoding errors
		case let encodingError as EncodingError:
			return .encodingError(underlyingError: encodingError)
		case let decodingError as DecodingError:
			// Note: Our handleResponse usually wraps this in .decodingError with data.
			// This handles cases where DecodingError might be thrown elsewhere.
			return .decodingError(underlyingError: decodingError, data: nil)  // Data might not be available here

		// Handle Task cancellation
		case is CancellationError:
			return .cancelled

		// Fallback for any other error type
		default:
			return .unknownError(underlyingError: error)
		}
	}

	/// Maps HTTP status codes (outside the 2xx success range) to `NetworkRequestError`.
	private func mapStatusCodeToError(statusCode: Int, data: Data?) -> NetworkRequestError {
		switch statusCode {
		case 400: return .badRequest(data: data)
		case 401: return .unauthorized(data: data)
		case 403: return .forbidden(data: data)
		case 404: return .notFound(data: data)
		case 405...499: return .clientError(statusCode: statusCode, data: data)  // Other 4xx errors
		case 500...599: return .serverError(statusCode: statusCode, data: data)  // All 5xx errors
		default:
			// Handle unexpected status codes (e.g., 1xx, 3xx - though 3xx are often handled by URLSession)
			logger.log(
				message: "Received unhandled HTTP status code: \(statusCode)", level: .info) // .warning -> .info
			return .unknownError(
				underlyingError: NSError(
					domain: "Netify", code: statusCode,
					userInfo: [
						NSLocalizedDescriptionKey: "Unhandled HTTP status code: \(statusCode)"
					]))
		}
	}
}

// MARK: - Request Builder (Internal Helper)

/// URLRequest 생성을 담당하는 내부 헬퍼 클래스입니다.
@available(iOS 15, macOS 12, *)
internal struct RequestBuilder {
	let configuration: NetifyConfiguration
	let logger: NetifyLogging  // Used for logging warnings, etc.

	/// NetifyRequest로부터 URLRequest를 빌드합니다.
	/// Handles URL construction, query parameters, headers, body encoding, and authentication.
	/// - Throws: `NetworkRequestError` if building fails (e.g., invalid URL, encoding error).
	func buildURLRequest<Request: NetifyRequest>(from netifyRequest: Request) async throws
		-> URLRequest
	{

		// 1. Construct URL with Path and Query Parameters
		let url = try buildFinalURL(for: netifyRequest)

		// 2. Initialize URLRequest and set basic properties
		var request = URLRequest(url: url)
		request.httpMethod = netifyRequest.method.rawValue
		request.timeoutInterval = netifyRequest.timeoutInterval ?? configuration.timeoutInterval
		request.cachePolicy = netifyRequest.cachePolicy ?? configuration.cachePolicy

		// 3. Prepare Headers (Default + Request Specific)
		var headers = configuration.defaultHeaders
		netifyRequest.headers?.forEach { headers[$0.key] = $0.value }  // Request headers override defaults

		// 4. Prepare Body and Content-Type Header (if applicable)
		let boundary = "Boundary-\(UUID().uuidString)"  // For multipart

		if let multipartData = netifyRequest.multipartData, !multipartData.isEmpty {
			// Handle multipart/form-data
			if netifyRequest.body != nil {
				logger.log(
					message:
						"Warning: Both 'body' and 'multipartData' provided for request path '\(netifyRequest.path)'. Ignoring 'body'.",
					level: .error)  // .warning 대신 .error 사용 (또는 .info)
			}
			headers[HTTPHeaderField.contentType.rawValue] =
				"\(HTTPContentType.multipart.rawValue); boundary=\(boundary)"
			request.httpBody = buildMultipartBody(parts: multipartData, boundary: boundary)

		} else if let body = netifyRequest.body {
			// Handle regular body based on specified contentType
			try encodeAndSetBody(
				&request, body: body, contentType: netifyRequest.contentType, headers: &headers)
		}
		// else: No body provided.

		// 5. Set Final Headers on the request
		if !headers.isEmpty {
			request.allHTTPHeaderFields = headers
		}

		// 6. Apply Authentication (if required) - Do this *after* all other headers/body are set
		if netifyRequest.requiresAuthentication,
			let authProvider = configuration.authenticationProvider
		{
			do {
				request = try await authProvider.authenticate(request: request)
			} catch {
				// Map errors occurring during the authentication process itself
				throw mapAuthenticationError(error)
			}
		}

		return request
	}

	/// Helper to build the final URL including query parameters.
	private func buildFinalURL<Request: NetifyRequest>(for netifyRequest: Request) throws -> URL {
		let baseURL = configuration.baseURL
		let path = netifyRequest.path

		// Build the base URL + path component
		let initialURL = try URLPathBuilder.buildURL(baseURL: baseURL, path: path)

		// Add query parameters if present
		guard let queryParams = netifyRequest.queryParams, !queryParams.isEmpty else {
			return initialURL  // No query params to add
		}

		guard var components = URLComponents(url: initialURL, resolvingAgainstBaseURL: false) else {
			// This should be unlikely if initialURL was valid
			throw NetworkRequestError.invalidRequest(
				reason: "Failed to create URLComponents from apparently valid URL: \(initialURL)")
		}

		var queryItems = components.queryItems ?? []
		queryItems.append(
			contentsOf: queryParams.map { URLQueryItem(name: $0.key, value: $0.value) })

		if !queryItems.isEmpty { components.queryItems = queryItems }

		guard let finalURL = components.url else {
			throw NetworkRequestError.invalidRequest(
				reason: "Failed to construct final URL with query parameters for path: \(path)")
		}

		return finalURL
	}

	/// Helper to encode the body based on ContentType and set it on the request.
	/// Also updates the headers dictionary with the Content-Type if not already set.
	/// - Throws: `NetworkRequestError.encodingError` or `NetworkRequestError.invalidRequest`.
	private func encodeAndSetBody(
		_ request: inout URLRequest, body: Any, contentType: HTTPContentType,
		headers: inout HTTPHeaders
	) throws {
		do {
			switch contentType {
			case .json:
				guard let encodableBody = body as? Encodable else {
					throw NetworkRequestError.invalidRequest(
						reason:
							"Request body type (\(type(of: body))) is not Encodable for JSON content type."
					)
				}
				request.httpBody = try configuration.defaultEncoder.encode(encodableBody)

			case .urlEncoded:
				guard let paramsBody = body as? QueryParameters else {
					throw NetworkRequestError.invalidRequest(
						reason:
							"Request body type (\(type(of: body))) is not [String: String] for URL Encoded content type."
					)
				}
				request.httpBody = paramsBody.toUrlEncodedQueryString()?.data(using: .utf8)

			case .plainText:
				guard let stringBody = body as? String else {
					throw NetworkRequestError.invalidRequest(
						reason:
							"Request body type (\(type(of: body))) is not String for Plain Text content type."
					)
				}
				request.httpBody = stringBody.data(using: .utf8)

			case .xml:  // XML 케이스 추가
				guard let stringBody = body as? String else {
					throw NetworkRequestError.invalidRequest(
						reason:
							"Request body type (\(type(of: body))) is not String for XML content type."
					)
				}
				request.httpBody = stringBody.data(using: .utf8)

			// Add cases for other supported types like .xml
			// case .xml: ...

			case .multipart:
				// Multipart is handled separately before calling this function
				throw NetworkRequestError.invalidRequest(
					reason:
						"Multipart content type should be handled via 'multipartData' property, not 'body'."
				)

			// Consider adding a case for explicit Data if needed:
			// case .octetStream (or similar):
			//    guard let dataBody = body as? Data else { ... }
			//    request.httpBody = dataBody
			}

			// Set Content-Type header if it wasn't manually provided in request headers
			if headers[HTTPHeaderField.contentType.rawValue] == nil {
				headers[HTTPHeaderField.contentType.rawValue] = contentType.rawValue
			}

		} catch let error as NetworkRequestError {
			throw error  // Re-throw specific request errors
		} catch {
			// Wrap underlying encoding errors
			throw NetworkRequestError.encodingError(underlyingError: error)
		}
	}

	/// Builds the complete data object for a multipart/form-data request body.
	private func buildMultipartBody(parts: [MultipartData], boundary: String) -> Data {
		let body = NSMutableData()
		for part in parts {
			body.append(part.buildHttpBodyPart(boundary: boundary))
		}
		// Add the final boundary marker
		body.appendString("--\(boundary)--\r\n")
		return body as Data
	}

	/// Maps errors potentially thrown by `AuthenticationProvider.authenticate`.
	private func mapAuthenticationError(_ error: Error) -> NetworkRequestError {
		if let netifyError = error as? NetworkRequestError {
			// If the provider explicitly threw a NetifyError
			return netifyError
		} else {
			// Treat other errors from the provider as unknown authentication issues
			logger.log(
				message: "Unknown error during authentication provider execution: \(error)",
				level: .error)
			return .unknownError(underlyingError: error)
		}
	}
}
