import Foundation
import OSLog // 로깅 프레임워크 임포트

// MARK: - Core Protocols

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

/// `URLSession`의 `data(for:delegate:)` 메소드에 대한 인터페이스를 제공하여 테스트 중 Mock 객체 주입을 용이하게 합니다.
@available(iOS 15, macOS 12, *)
public protocol NetworkSessionProtocol {
    /// 지정된 URL 요청에 따라 URL의 내용을 비동기적으로 검색합니다.
    /// `URLSession.data(for:delegate:)`에 해당합니다.
    func data(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws -> (Data, URLResponse)
}

// MARK: - URLSession Conformance

@available(iOS 15, macOS 12, *)
extension URLSession: NetworkSessionProtocol {} // URLSession이 NetworkSessionProtocol을 준수하도록 합니다.

// MARK: - Internal Constants

@available(iOS 15, macOS 12, *)
internal enum NetifyInternalConstants {
    /// 로깅 및 cURL 명령어 출력 시 마스킹할 민감한 HTTP 헤더 키 목록 (소문자)
    static let sensitiveHeaderKeys: Set<String> = [
        HTTPHeaderField.authorization.rawValue.lowercased(),
        "proxy-authorization",
        "cookie",
        "set-cookie",
        "x-api-key",
        "api-key",
        "x-auth-token",
        "x-csrf-token",
        "client-secret",
        "access-token",
        "refresh-token",
        "bearer-token",
        "password",
        "secret",
        "token",
        "private-token",
        "session-id",
        "session-token"
    ]
    
    /// 로깅 시 요약할 최대 데이터 길이 (바이트)
    static let maxLogSummaryLength = 1024
    
    /// 기본 재시도 전 대기 시간 (초)
    static let defaultRetryDelaySeconds: TimeInterval = 1.0
    /// 지수 백오프 기본 배율
    static let exponentialBackoffMultiplier: Double = 2.0
    /// 최대 재시도 대기 시간 (초)
    static let maxRetryDelaySeconds: TimeInterval = 30.0
}

// MARK: - Public Configuration & Basic Types

/// Netify 클라이언트의 설정을 정의하는 구조체입니다. `Sendable`을 준수하여 동시성 환경에서 안전하게 사용될 수 있습니다.
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
    public let waitsForConnectivity: Bool
    public let responseCache: ResponseCache?
    public let plugins: [NetifyPlugin]
    public let metrics: NetworkMetrics
    public let varyIndex: VaryIndex?
    
    public init(
        baseURL: String,
        sessionConfiguration: URLSessionConfiguration = .default,
        defaultEncoder: JSONEncoder = JSONEncoder(),
        defaultDecoder: JSONDecoder = JSONDecoder(),
        defaultHeaders: HTTPHeaders = [:],
        logLevel: NetworkingLogLevel = .info,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
        maxRetryCount: Int = 0, // 기본적으로 재시도 안 함
        timeoutInterval: TimeInterval = 30.0,
        authenticationProvider: AuthenticationProvider? = nil,
        waitsForConnectivity: Bool = false, // 기본값은 false로 설정 (시스템 기본값은 true)
        responseCache: ResponseCache? = nil,
        plugins: [NetifyPlugin] = [],
        metrics: NetworkMetrics = NoopMetrics(),
        varyIndex: VaryIndex? = nil
    ) {
        // baseURL의 마지막 '/' 문자 제거
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.sessionConfiguration = sessionConfiguration
        self.defaultEncoder = defaultEncoder
        self.defaultDecoder = defaultDecoder
        self.defaultHeaders = defaultHeaders
        self.logLevel = logLevel
        self.cachePolicy = cachePolicy
        self.maxRetryCount = max(0, maxRetryCount) // 음수 방지
        self.timeoutInterval = timeoutInterval
        self.authenticationProvider = authenticationProvider
        self.waitsForConnectivity = waitsForConnectivity
        self.responseCache = responseCache
        self.plugins = plugins
        self.metrics = metrics
        self.varyIndex = varyIndex
        
        // sessionConfiguration에 waitsForConnectivity 명시적 적용
        self.sessionConfiguration.waitsForConnectivity = waitsForConnectivity
        // 기본 타임아웃도 sessionConfiguration에 반영 (요청별 타임아웃이 우선됨)
        self.sessionConfiguration.timeoutIntervalForRequest = timeoutInterval
    }
}

/// 네트워크 로깅의 상세 수준을 정의합니다. `Sendable`을 준수합니다.
@available(iOS 15, macOS 12, *)
public enum NetworkingLogLevel: Int, Comparable, Sendable {
    case off = 0    // 로깅 비활성화
    case error = 1  // 에러만 로깅
    case info = 2   // 정보성 로깅 (요청/응답 요약)
    case debug = 3  // 상세 디버그 로깅 (헤더, 바디, cURL 등)
    
    public static func < (lhs: NetworkingLogLevel, rhs: NetworkingLogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Response Cache Protocol & Implementation

/// 응답 캐시 저장소를 정의하는 프로토콜입니다.
@available(iOS 15, macOS 12, *)
public protocol ResponseCache: Sendable {
    /// 캐시된 응답을 조회합니다.
    func getCachedResponse(for key: String) async -> CachedResponse?
    /// 응답을 캐시에 저장합니다.
    func setCachedResponse(_ response: CachedResponse, for key: String) async
    /// 특정 키의 캐시를 삭제합니다.
    func removeCachedResponse(for key: String) async
    /// 모든 캐시를 삭제합니다.
    func clearCache() async
}

/// 캐시된 응답 데이터를 나타내는 구조체입니다.
@available(iOS 15, macOS 12, *)
public struct CachedResponse: Sendable {
    public let data: Data
    public let response: HTTPURLResponse
    public let cachedAt: Date
    public let etag: String?
    public let maxAge: TimeInterval?
    
    public init(data: Data, response: HTTPURLResponse, etag: String? = nil, maxAge: TimeInterval? = nil) {
        self.data = data
        self.response = response
        self.cachedAt = Date()
        self.etag = etag
        self.maxAge = maxAge
    }
    
    /// 캐시된 응답이 여전히 유효한지 확인합니다.
    public var isValid: Bool {
        guard let maxAge = maxAge else { return true }
        return Date().timeIntervalSince(cachedAt) < maxAge
    }
}

/// 메모리 기반 응답 캐시 구현체입니다.
@available(iOS 15, macOS 12, *)
public actor InMemoryResponseCache: ResponseCache {
    private var cache: [String: CachedResponse] = [:]
    private let maxCacheSize: Int
    private let defaultTTL: TimeInterval
    
    public init(maxCacheSize: Int = 100, defaultTTL: TimeInterval = 300) {
        self.maxCacheSize = maxCacheSize
        self.defaultTTL = defaultTTL
    }
    
    public func getCachedResponse(for key: String) async -> CachedResponse? {
        guard let cached = cache[key], cached.isValid else {
            cache.removeValue(forKey: key)
            return nil
        }
        return cached
    }
    
    public func setCachedResponse(_ response: CachedResponse, for key: String) async {
        if cache.count >= maxCacheSize {
            evictOldestEntry()
        }
        cache[key] = response
    }
    
    public func removeCachedResponse(for key: String) async {
        cache.removeValue(forKey: key)
    }
    
    public func clearCache() async {
        cache.removeAll()
    }
    
    private func evictOldestEntry() {
        guard let oldestKey = cache.min(by: { $0.value.cachedAt < $1.value.cachedAt })?.key else { return }
        cache.removeValue(forKey: oldestKey)
    }
}

/// Vary 헤더를 기반으로 캐시 키를 관리하는 액터입니다.
@available(iOS 15, macOS 12, *)
public actor VaryIndex: Sendable {
    private var varyHeaders: [String: Set<String>] = [:]
    
    /// URL과 Vary 헤더를 기반으로 캐시 키를 생성합니다.
    public func generateCacheKey(url: String, headers: [String: String], varyHeaders: [String]) async -> String {
        var keyComponents = [url]
        
        for varyHeader in varyHeaders.sorted() {
            let headerValue = headers[varyHeader] ?? ""
            keyComponents.append("\(varyHeader):\(headerValue)")
        }
        
        return keyComponents.joined(separator: "|")
    }
    
    /// URL에 대한 Vary 헤더를 저장합니다.
    public func setVaryHeaders(_ headers: Set<String>, for url: String) async {
        varyHeaders[url] = headers
    }
    
    /// URL에 대한 Vary 헤더를 조회합니다.
    public func getVaryHeaders(for url: String) async -> Set<String> {
        return varyHeaders[url] ?? []
    }
}

// MARK: - Plugin System

/// 플러그인 실패 시 전달되는 컨텍스트 정보입니다.
@available(iOS 15, macOS 12, *)
public struct PluginFailureContext: Sendable {
    /// 마스킹된 요청 요약 (구성 실패 시 nil일 수 있음)
    public let requestSummary: RequestSummary?
    /// 에러 요약 문자열 (민감정보 마스킹 적용된 안전한 요약)
    public let errorSummary: String
    /// 요청 시작 시각
    public let startedAt: Date
    /// 현재 재시도 횟수 (nil이면 재시도 아님)
    public let attemptCount: Int?
    /// 요청 URL (request가 nil인 경우를 위한 백업)
    public let targetURL: String?
    
    public init(
        requestSummary: RequestSummary?,
        errorSummary: String,
        startedAt: Date,
        attemptCount: Int? = nil,
        targetURL: String? = nil
    ) {
        self.requestSummary = requestSummary
        self.errorSummary = errorSummary
        self.startedAt = startedAt
        self.attemptCount = attemptCount
        self.targetURL = targetURL ?? requestSummary?.url
    }
}

/// Netify 플러그인을 정의하는 프로토콜입니다.
@available(iOS 15, macOS 12, *)
public protocol NetifyPlugin: Sendable {
    /// 요청 전송 전에 호출됩니다.
    func willSend(request: URLRequest) async throws -> URLRequest
    /// 응답 수신 후에 호출됩니다.
    func didReceive(response: URLResponse, data: Data, for request: URLRequest) async throws
    /// 에러 발생 시 호출됩니다.
    func didFail(with context: PluginFailureContext) async throws
}

/// 기본 플러그인 구현 (모든 메서드가 기본 동작)
@available(iOS 15, macOS 12, *)
public struct DefaultNetifyPlugin: NetifyPlugin {
    public init() {}
    
    public func willSend(request: URLRequest) async throws -> URLRequest {
        return request
    }
    
    public func didReceive(response: URLResponse, data: Data, for request: URLRequest) async throws {
        // 기본 동작: 아무것도 하지 않음
    }
    
    public func didFail(with context: PluginFailureContext) async throws {
        // 기본 동작: 아무것도 하지 않음
    }
}

/// 플러그인 실행을 안전하게 처리하는 헬퍼
@available(iOS 15, macOS 12, *)
internal struct SafePluginExecutor {
    private let logger: NetifyLogging
    
    init(logger: NetifyLogging) {
        self.logger = logger
    }
    
    /// 플러그인의 willSend를 안전하게 실행합니다.
    func executeWillSend(plugins: [NetifyPlugin], request: URLRequest) async -> URLRequest {
        var currentRequest = request
        
        for (index, plugin) in plugins.enumerated() {
            do {
                currentRequest = try await plugin.willSend(request: currentRequest)
            } catch {
                logger.logForOperation("플러그인 [\(index)] willSend에서 에러 발생, 무시함: \(error.localizedDescription)")
                // 에러를 무시하고 기존 request 유지
            }
        }
        
        return currentRequest
    }
    
    /// 플러그인의 didReceive를 안전하게 실행합니다.
    func executeDidReceive(plugins: [NetifyPlugin], response: URLResponse, data: Data, request: URLRequest) async {
        for (index, plugin) in plugins.enumerated() {
            do {
                try await plugin.didReceive(response: response, data: data, for: request)
            } catch {
                logger.logForOperation("플러그인 [\(index)] didReceive에서 에러 발생, 무시함: \(error.localizedDescription)")
                // 에러를 무시하고 계속 진행
            }
        }
    }
    
    /// 플러그인의 didFail을 안전하게 실행합니다.
    func executeDidFail(plugins: [NetifyPlugin], context: PluginFailureContext) async {
        for (index, plugin) in plugins.enumerated() {
            do {
                try await plugin.didFail(with: context)
            } catch {
                logger.logForOperation("플러그인 [\(index)] didFail에서 에러 발생, 무시함: \(error.localizedDescription)")
                // 에러를 무시하고 계속 진행
            }
        }
    }
}

/// 메트릭 실행을 안전하게 처리하는 헬퍼
@available(iOS 15, macOS 12, *)
internal struct SafeMetricsExecutor {
    private let logger: NetifyLogging
    
    init(logger: NetifyLogging) {
        self.logger = logger
    }
    
    /// 요청 성공 메트릭을 안전하게 기록합니다.
    func recordRequest(metrics: NetworkMetrics, url: String, method: String, statusCode: Int, duration: TimeInterval, responseSize: Int) async {
        do {
            try await metrics.recordRequest(url: url, method: method, statusCode: statusCode, duration: duration, responseSize: responseSize)
        } catch {
            logger.logForOperation("메트릭 recordRequest에서 에러 발생, 무시함: \(error.localizedDescription)")
        }
    }
    
    /// 요청 실패 메트릭을 안전하게 기록합니다.
    func recordError(metrics: NetworkMetrics, url: String, method: String, error: Error, duration: TimeInterval) async {
        do {
            try await metrics.recordError(url: url, method: method, error: error, duration: duration)
        } catch {
            logger.logForOperation("메트릭 recordError에서 에러 발생, 무시함: \(error.localizedDescription)")
        }
    }
    
    /// 재시도 메트릭을 안전하게 기록합니다.
    func recordRetry(metrics: NetworkMetrics, url: String, method: String, attempt: Int, error: Error) async {
        do {
            try await metrics.recordRetry(url: url, method: method, attempt: attempt, error: error)
        } catch {
            logger.logForOperation("메트릭 recordRetry에서 에러 발생, 무시함: \(error.localizedDescription)")
        }
    }
}

// MARK: - Metrics System

/// 네트워크 메트릭을 수집하기 위한 프로토콜입니다.
@available(iOS 15, macOS 12, *)
public protocol NetworkMetrics: Sendable {
    /// 요청 성공을 기록합니다.
    func recordRequest(url: String, method: String, statusCode: Int, duration: TimeInterval, responseSize: Int) async throws
    /// 요청 실패를 기록합니다.
    func recordError(url: String, method: String, error: Error, duration: TimeInterval) async throws
    /// 재시도를 기록합니다.
    func recordRetry(url: String, method: String, attempt: Int, error: Error) async throws
}

/// 기본 메트릭 구현체 (아무것도 하지 않음)
@available(iOS 15, macOS 12, *)
public struct NoopMetrics: NetworkMetrics {
    public init() {}
    
    public func recordRequest(url: String, method: String, statusCode: Int, duration: TimeInterval, responseSize: Int) async throws {
        // 기본 동작: 아무것도 하지 않음
    }
    
    public func recordError(url: String, method: String, error: Error, duration: TimeInterval) async throws {
        // 기본 동작: 아무것도 하지 않음
    }
    
    public func recordRetry(url: String, method: String, attempt: Int, error: Error) async throws {
        // 기본 동작: 아무것도 하지 않음
    }
}

/// HTTP 요청 메서드를 정의합니다. `Sendable`을 준수합니다.
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
    public init(rawValue: String) { self.rawValue = rawValue.uppercased() } // 일관성을 위해 대문자로 저장
}

/// 표준 HTTP 요청/응답 헤더 필드를 정의합니다. `Sendable`을 준수합니다.
@available(iOS 15, macOS 12, *)
public enum HTTPHeaderField: String, Sendable, CaseIterable {
    case authorization = "Authorization"
    case contentType = "Content-Type"
    case acceptType = "Accept"
    case acceptEncoding = "Accept-Encoding"
    case userAgent = "User-Agent"
    case cacheControl = "Cache-Control"
    case eTag = "ETag"
    case ifNoneMatch = "If-None-Match"
    // 필요시 추가
}

/// HTTP 요청 본문의 Content-Type을 정의합니다. `Sendable`을 준수합니다.
@available(iOS 15, macOS 12, *)
public enum HTTPContentType: String, Sendable {
    case json = "application/json; charset=utf-8"
    case urlEncoded = "application/x-www-form-urlencoded; charset=utf-8"
    case multipart = "multipart/form-data" // Boundary는 동적으로 추가됨
    case plainText = "text/plain; charset=utf-8"
    case xml = "application/xml; charset=utf-8"
    case octetStream = "application/octet-stream" // 바이너리 데이터
    // 필요시 추가
}

/// 빈 응답 본문을 나타내는 타입입니다. 성공했지만 내용이 없는 경우 (예: 204 No Content) 사용될 수 있습니다.
/// `Decodable` 및 `Sendable`을 준수합니다.
@available(iOS 15, macOS 12, *)
public struct EmptyResponse: Decodable, Sendable {}

/// 쿼리 파라미터 타입 별칭입니다. ([String: String])
@available(iOS 15, macOS 12, *)
public typealias QueryParameters = [String: String]

/// HTTP 헤더 타입 별칭입니다. ([String: String])
@available(iOS 15, macOS 12, *)
public typealias HTTPHeaders = [String: String]

/// 사용자 자격 증명 (기본 인증용). `Sendable`을 준수합니다.
@available(iOS 15, macOS 12, *)
public struct UserCredentials: Sendable {
    let username: String
    let password: String
    
    /// 기본 인증 헤더 값을 생성합니다 (예: "Basic dXNlcjpwYXNzd29yZA==").
    var basicAuthHeaderValue: String {
        let loginString = "\(username):\(password)"
        guard let data = loginString.data(using: .utf8) else { return "" } // UTF-8 인코딩 실패 시 빈 문자열 반환
        return "Basic \(data.base64EncodedString())"
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
    
    /// 운영용 간소 로그 (민감정보 자동 마스킹)
    func logForOperation(_ message: String)
    /// 디버깅용 상세 로그 (민감정보 마스킹 + 상세 컨텍스트)
    func logForDebug(_ message: String)
    /// 에러의 향상된 디버그 정보 로그
    func logEnhancedError(_ netifyError: NetifyError)
}

/// `os.Logger`를 사용하는 `NetifyLogging`의 기본 구현체입니다.
@available(iOS 15, macOS 12, *)
public struct DefaultNetifyLogger: NetifyLogging {
    public let logLevel: NetworkingLogLevel
    private let logger: Logger // os.Logger 인스턴스
    
    /// `DefaultNetifyLogger`를 초기화합니다.
    /// - Parameters:
    ///   - logLevel: 로깅 상세 수준.
    ///   - subsystem: `os.Logger`에 사용할 서브시스템 문자열. 기본값은 앱 번들 ID.
    ///   - category: `os.Logger`에 사용할 카테고리 문자열. 기본값은 "Netify".
    public init(
        logLevel: NetworkingLogLevel,
        subsystem: String = Bundle.main.bundleIdentifier ?? "com.unknown.netify", // 기본 서브시스템 개선
        category: String = "Netify"
    ) {
        self.logLevel = logLevel
        self.logger = Logger(subsystem: subsystem, category: category)
    }
    
    public func log(message: String, level: OSLogType = .debug) {
        guard shouldLog(for: level) else { return }
        logger.log(level: level, "\(message)")
    }
    
    public func log(request: URLRequest, level: OSLogType = .debug) {
        guard shouldLog(for: level) else { return }
        
        var logMessage = "\n➡️ Request: \(request.httpMethod ?? "UNKNOWN_METHOD") \(request.url?.absoluteString ?? "UNKNOWN_URL")"
        
        if self.logLevel >= .debug { // logLevel에 따라 상세 정보 로깅 결정
            if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
                logMessage += "\n    Headers: \(maskSensitiveHeaders(headers))"
            }
            if let bodyData = request.httpBody, !bodyData.isEmpty {
                let bodySummary = summarizeData(bodyData, contentType: request.value(forHTTPHeaderField: HTTPHeaderField.contentType.rawValue))
                logMessage += "\n    Body: \(bodySummary)"
            } else if request.httpBodyStream != nil {
                logMessage += "\n    Body: InputStream data (length unknown)" // 스트림은 길이 알 수 없음 명시
            }
            logMessage += "\n    cURL: \(request.toCurlCommand())"
        }
        logger.log(level: level, "\(logMessage)")
    }
    
    public func log(response: URLResponse, data: Data?, level: OSLogType = .debug) {
        guard shouldLog(for: level) else { return }
        
        var logMessage = "\n⬅️ Response:"
        if let httpResponse = response as? HTTPURLResponse {
            let statusIcon = (200...299).contains(httpResponse.statusCode) ? "✅" : "⚠️"
            logMessage += " \(statusIcon) Status \(httpResponse.statusCode) from \(response.url?.absoluteString ?? "UNKNOWN_URL")"
            
            if self.logLevel >= .debug {
                if let headers = httpResponse.allHeaderFields as? HTTPHeaders, !headers.isEmpty { // 모든 헤더 필드를 HTTPHeaders로 캐스팅
                    logMessage += "\n    Headers: \(maskSensitiveHeaders(headers))"
                }
                if let data = data, !data.isEmpty {
                    let dataSummary = summarizeData(data, contentType: httpResponse.value(forHTTPHeaderField: HTTPHeaderField.contentType.rawValue))
                    logMessage += "\n    Data: \(dataSummary)"
                } else {
                    logMessage += (data == nil) ? "\n    Data: (No data)" : "\n    Data: (Empty data: 0 bytes)"
                }
            } else if self.logLevel >= .info, let data = data { // .info 레벨에서는 데이터 크기만 로깅
                logMessage += " (\(data.count) bytes)"
            }
        } else {
            logMessage += " Non-HTTP response from \(response.url?.absoluteString ?? "UNKNOWN_URL") (\(type(of: response)))"
        }
        logger.log(level: level, "\(logMessage)")
    }
    
    public func log(error: Error, level: OSLogType = .error) {
        guard shouldLog(for: level) else { return }
        var logMessage = "\n❌ Error: "
        if let netifyError = error as? NetworkRequestError {
            logMessage += "\(netifyError.localizedDescription)"
            if self.logLevel >= .debug { // 상세 에러 정보는 .debug 레벨에서
                logMessage += "\n    Debug Info: \(netifyError.debugDescription)"
            }
        } else {
            logMessage += "\(error.localizedDescription)"
            if self.logLevel >= .debug {
                logMessage += "\n    Error Type: \(type(of: error))\n    Raw Error: \(error)"
            }
        }
        logger.log(level: level, "\(logMessage)")
    }
    
    /// 지정된 `OSLogType`에 대해 로깅을 수행해야 하는지 여부를 결정합니다.
    private func shouldLog(for targetLevel: OSLogType) -> Bool {
        guard self.logLevel != .off else { return false } // 로깅 꺼져있으면 항상 false
        
        let currentOsLogEquivalent: OSLogType
        switch self.logLevel {
        case .error: currentOsLogEquivalent = .error
        case .info: currentOsLogEquivalent = .info
        case .debug: currentOsLogEquivalent = .debug
        default: return false // .off는 위에서 처리
        }
        // targetLevel이 현재 설정된 로그 레벨보다 같거나 중요할 때만 로깅 (숫자가 클수록 덜 중요)
        return targetLevel.rawValue <= currentOsLogEquivalent.rawValue
    }
    
    // MARK: - 새로운 로깅 메서드들
    
    /// 운영용 간소 로그 (민감정보 자동 마스킹)
    public func logForOperation(_ message: String) {
        guard logLevel >= .info else { return }
        let sanitizedMessage = sanitizeForOperation(message)
        logger.log(level: .info, "[운영] \(sanitizedMessage)")
    }
    
    /// 디버깅용 상세 로그 (민감정보 마스킹 + 상세 컨텍스트)
    public func logForDebug(_ message: String) {
        guard logLevel >= .debug else { return }
        let sanitizedMessage = sanitizeForDebug(message)
        logger.log(level: .debug, "[디버그] \(sanitizedMessage)")
    }
    
    /// 에러의 향상된 디버그 정보 로그
    public func logEnhancedError(_ netifyError: NetifyError) {
        guard logLevel >= .debug else { return }
        let enhancedDescription = netifyError.enhancedDebugDescription
        logger.log(level: .error, "[향상된 에러 정보]\n\(enhancedDescription)")
    }
    
    // MARK: - 메시지 정화 헬퍼들
    
    /// 운영용 메시지에서 민감정보 제거
    private func sanitizeForOperation(_ message: String) -> String {
        var s = message
        let patterns: [(String, String)] = [
            // Bearer/Basic 토큰류
            ("(?i)\\bBearer\\s+[A-Za-z0-9\\-._~+/]+=*", "Bearer <masked>"),
            ("(?i)\\bBasic\\s+[A-Za-z0-9+/]+=*", "Basic <masked>"),
            // token/password/secret 등 키워드 기반 값 마스킹
            ("(?i)\\b(token|access[_-]?token|password|secret)[\"':\\s=]+[^\\s\"']+", "$1: <masked>"),
            // JWT 토큰
            ("\\b[A-Za-z0-9-_]+?\\.[A-Za-z0-9-_]+?\\.[A-Za-z0-9-_]+\\b", "<jwt:masked>"),
            // 쿼리스트링 apiKey, key, access_token 마스킹
            ("([?&](?i)(api[_-]?key|key|access[_-]?token)=)[^&]+", "$1<masked>"),
            // Cookie 헤더 전체 마스킹
            ("(?i)(cookie:\\s*)(.+)", "$1<masked>")
        ]
        for (re, rep) in patterns {
            s = s.replacingOccurrences(of: re, with: rep, options: [.regularExpression])
        }
        return s
    }
    
    /// 디버깅용 메시지에서 민감정보 제거 (현재는 운영과 동일 정책)
    private func sanitizeForDebug(_ message: String) -> String {
        return sanitizeForOperation(message)
    }
    
    /// 민감한 정보를 마스킹 처리한 헤더를 반환합니다.
    private func maskSensitiveHeaders(_ headers: HTTPHeaders) -> HTTPHeaders {
        var maskedHeaders = headers
        for (key, _) in headers where NetifyInternalConstants.sensitiveHeaderKeys.contains(key.lowercased()) {
            maskedHeaders[key] = "<masked>"
        }
        return maskedHeaders
    }
    
    /// 데이터를 요약하여 문자열로 반환합니다. 너무 길면 잘라냅니다.
    private func summarizeData(_ data: Data, contentType: String?) -> String {
        let maxLen = NetifyInternalConstants.maxLogSummaryLength
        if let contentType = contentType?.lowercased(),
           (contentType.contains("json") || contentType.contains("text") || contentType.contains("xml") || contentType.contains("urlencoded")),
           let stringValue = String(data: data, encoding: .utf8) {
            return stringValue.count > maxLen ? "\(stringValue.prefix(maxLen))... (총 \(data.count) bytes)" : stringValue
        }
        return "<binary data: \(data.count) bytes>"
    }
}

// MARK: - Network Request Error

/// 에러 발생 시점의 요청/응답 컨텍스트 정보를 담는 구조체입니다.
@available(iOS 15, macOS 12, *)
public struct ErrorContext: Sendable, Codable {
    public let url: String?
    public let method: String?
    public let requestHeaders: [String: String]?
    public let requestBody: String? // 민감하지 않은 경우만
    public let responseHeaders: [String: String]?
    public let statusCode: Int?
    public let timestamp: Date
    public let attemptCount: Int
    public let totalDuration: TimeInterval?
    
    public init(
        url: String? = nil,
        method: String? = nil,
        requestHeaders: [String: String]? = nil,
        requestBody: String? = nil,
        responseHeaders: [String: String]? = nil,
        statusCode: Int? = nil,
        attemptCount: Int = 1,
        totalDuration: TimeInterval? = nil
    ) {
        self.url = url
        self.method = method
        self.requestHeaders = requestHeaders?.maskingSensitiveHeaders()
        self.requestBody = requestBody
        self.responseHeaders = responseHeaders
        self.statusCode = statusCode
        self.timestamp = Date()
        self.attemptCount = attemptCount
        self.totalDuration = totalDuration
    }
}

/// HTTPHeaders에 민감한 헤더 마스킹 기능을 추가하는 확장입니다.
@available(iOS 15, macOS 12, *)
extension Dictionary where Key == String, Value == String {
    func maskingSensitiveHeaders() -> [String: String] {
        var masked = self
        for (key, _) in self where NetifyInternalConstants.sensitiveHeaderKeys.contains(key.lowercased()) {
            masked[key] = "<masked>"
        }
        return masked
    }
}

/// Netify 에러 포맷터 유틸리티입니다.
@available(iOS 15, macOS 12, *)
public enum NetifyErrorFormatter {
    /// 향상된 디버그 설명을 생성합니다.
    public static func enhanced(kind: NetworkRequestError, context: ErrorContext?) -> String {
        let description = kind.debugDescription
        
        guard let ctx = context else {
            return description + "\n\n[컨텍스트 정보 없음]"
        }
        
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        var lines: [String] = []
        lines.append("=== 에러 컨텍스트 정보 ===")
        lines.append("• 시간: \(formatter.string(from: ctx.timestamp))")
        
        if let url = ctx.url { lines.append("• URL: \(url)") }
        if let method = ctx.method { lines.append("• 메서드: \(method)") }
        if let statusCode = ctx.statusCode { lines.append("• 상태 코드: \(statusCode)") }
        lines.append("• 시도 횟수: \(ctx.attemptCount)")
        
        if let duration = ctx.totalDuration {
            lines.append("• 총 소요 시간: \(String(format: "%.3f", duration))초")
        }
        
        if let headers = ctx.requestHeaders, !headers.isEmpty {
            lines.append("• 요청 헤더:")
            for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
                lines.append("    \(key): \(value)")
            }
        }
        
        if let headers = ctx.responseHeaders, !headers.isEmpty {
            lines.append("• 응답 헤더:")
            for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
                lines.append("    \(key): \(value)")
            }
        }
        
        if let body = ctx.requestBody {
            lines.append("• 요청 본문: \(body)")
        }
        
        return description + "\n\n" + lines.joined(separator: "\n")
    }
}

/// Netify 라이브러리의 통합 에러 타입입니다. 기존 NetworkRequestError를 래핑하고 컨텍스트 정보를 포함합니다.
@available(iOS 15, macOS 12, *)
public struct NetifyError: LocalizedError, CustomDebugStringConvertible, Equatable {
    public let kind: NetworkRequestError
    public let context: ErrorContext?
    
    public init(kind: NetworkRequestError, context: ErrorContext? = nil) {
        self.kind = kind
        self.context = context
    }
    
    // LocalizedError 준수
    public var errorDescription: String? { kind.errorDescription }
    
    // CustomDebugStringConvertible 준수
    public var debugDescription: String { kind.debugDescription }
    
    /// 향상된 디버그 설명 (컨텍스트 정보 포함)
    public var enhancedDebugDescription: String {
        NetifyErrorFormatter.enhanced(kind: kind, context: context)
    }
    
    // Equatable 준수 (컨텍스트는 비교에서 제외)
    public static func == (lhs: NetifyError, rhs: NetifyError) -> Bool {
        return lhs.kind == rhs.kind
    }
    
    // NetworkRequestError의 편의 속성들을 위임
    public var isRetryable: Bool { kind.isRetryable }
    public var retryAfter: TimeInterval? { kind.retryAfter }
}

/// 네트워크 요청 처리 중 발생할 수 있는 다양한 에러 타입을 정의합니다.
@available(iOS 15, macOS 12, *)
public enum NetworkRequestError: LocalizedError, Equatable {
    /// 요청 구성 오류 (URL 생성 실패, 미지원 인코딩 등). 연관값으로 실패 사유(String)를 가집니다.
    case invalidRequest(reason: String)
    /// HTTP 응답이 아니거나 응답 객체 자체가 없는 경우. 연관값으로 원본 `URLResponse` (옵셔널)를 가집니다.
    case invalidResponse(response: URLResponse?)
    /// 400 Bad Request. 연관값으로 응답 데이터(옵셔널 `Data`)를 가집니다.
    case badRequest(data: Data?)
    /// 401 Unauthorized. 연관값으로 응답 데이터(옵셔널 `Data`)를 가집니다.
    case unauthorized(data: Data?)
    /// 403 Forbidden. 연관값으로 응답 데이터(옵셔널 `Data`)를 가집니다.
    case forbidden(data: Data?)
    /// 404 Not Found. 연관값으로 응답 데이터(옵셔널 `Data`)를 가집니다.
    case notFound(data: Data?)
    /// 429 Too Many Requests. 연관값으로 응답 데이터와 Retry-After 값을 가집니다.
    case tooManyRequests(data: Data?, retryAfter: TimeInterval?)
    /// 400번대 기타 클라이언트 에러. 연관값으로 상태 코드(Int), 응답 데이터(옵셔널 `Data`), Retry-After 값을 가집니다.
    case clientError(statusCode: Int, data: Data?, retryAfter: TimeInterval?)
    /// 500번대 서버 에러. 연관값으로 상태 코드(Int), 응답 데이터(옵셔널 `Data`), Retry-After 값을 가집니다.
    case serverError(statusCode: Int, data: Data?, retryAfter: TimeInterval?)
    /// 응답 데이터 디코딩 실패. 연관값으로 원본 디코딩 에러(`Error`)와 디코딩 시도된 데이터(옵셔널 `Data`)를 가집니다.
    case decodingError(underlyingError: Error, data: Data?)
    /// 요청 본문 인코딩 실패. 연관값으로 원본 인코딩 에러(`Error`)를 가집니다.
    case encodingError(underlyingError: Error)
    /// URLSession 레벨 에러 (네트워크 연결 문제 등). 연관값으로 원본 `URLError`를 가집니다.
    case urlSessionFailed(underlyingError: Error) // URLError로 제한하지 않고 일반 Error로 받음
    /// 기타 알 수 없는 에러. 연관값으로 원본 에러(옵셔널 `Error`)를 가집니다.
    case unknownError(underlyingError: Error?)
    /// 사용자 또는 시스템에 의해 요청이 취소됨.
    case cancelled
    /// 요청 시간 초과.
    case timedOut
    /// 인터넷 연결 없음.
    case noInternetConnection
    
    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let reason): return "잘못된 요청: \(reason)"
        case .invalidResponse: return "잘못된 응답 (HTTP 응답이 아니거나 형식이 맞지 않음)"
        case .badRequest: return "잘못된 요청 (400)"
        case .unauthorized: return "인증 실패 (401)"
        case .forbidden: return "접근 금지 (403)"
        case .notFound: return "찾을 수 없음 (404)"
        case .tooManyRequests: return "너무 많은 요청 (429)"
        case .clientError(let code, _, _): return "클라이언트 에러 (\(code))"
        case .serverError(let code, _, _): return "서버 에러 (\(code))"
        case .decodingError(let error, _): return "디코딩 에러: \(error.localizedDescription)"
        case .encodingError(let error): return "인코딩 에러: \(error.localizedDescription)"
        case .urlSessionFailed(let error): return "URLSession 실패: \(error.localizedDescription)"
        case .unknownError(let error): return "알 수 없는 에러: \(error?.localizedDescription ?? "정보 없음")"
        case .cancelled: return "요청 취소됨"
        case .timedOut: return "요청 시간 초과"
        case .noInternetConnection: return "인터넷 연결 없음"
        }
    }
    
    public var debugDescription: String {
        var desc = "\(errorDescription ?? "알 수 없는 에러") (NetifyError.\(String(describing: self).components(separatedBy: "(").first ?? "")))"
        switch self {
        case .invalidRequest(let reason): desc += "\n  사유: \(reason)"
        case .invalidResponse(let resp): desc += "\n  응답 객체: \(String(describing: resp))"
        case .badRequest(let d), .unauthorized(let d), .forbidden(let d), .notFound(let d), .tooManyRequests(let d, _):
            if let data = d, !data.isEmpty { desc += formatDataForDebug(data) }
            else { desc += "\n  응답 데이터: 없음" }
        case .clientError(_, let d, _), .serverError(_, let d, _):
            if let data = d, !data.isEmpty { desc += formatDataForDebug(data) }
            else { desc += "\n  응답 데이터: 없음" }
        case .decodingError(let err, let d):
            desc += "\n  원본 에러: \(err)"
            if let data = d, !data.isEmpty { desc += formatDataForDebug(data, prefix: "디코딩 시도 데이터") }
            else { desc += "\n  디코딩 시도 데이터: 없음"}
        case .encodingError(let err): desc += "\n  원본 에러: \(err)"
        case .urlSessionFailed(let err):
            desc += "\n  원본 에러: \(err)"
            if let urlError = err as? URLError {
                desc += "\n  URLError 코드: \(urlError.code.rawValue), 상세: \(urlError.localizedDescription)"
            }
        case .unknownError(let err):
            if let error = err { desc += "\n  원본 에러: \(error)" }
        default: break // .cancelled, .timedOut, .noInternetConnection는 추가 정보 없음
        }
        return desc
    }
    
    private func formatDataForDebug(_ data: Data, prefix: String = "응답 본문") -> String {
        if let body = String(data: data, encoding: .utf8) {
            let maxLen = NetifyInternalConstants.maxLogSummaryLength
            return "\n  \(prefix): \(body.prefix(maxLen))\(body.count > maxLen ? "..." : "") (총 \(data.count) bytes)"
        } else {
            return "\n  \(prefix) (바이너리 데이터): \(data.count) bytes"
        }
    }
    
    /// 이 에러가 재시도 가능한 유형인지 여부를 반환합니다.
    public var isRetryable: Bool {
        switch self {
        case .serverError: return true // 5xx 서버 에러는 종종 일시적임
        case .tooManyRequests: return true // 429 에러는 재시도 가능 (Retry-After 고려)
        case .timedOut: return true
        case .noInternetConnection: return true // 연결 복구 시 재시도 가능
        case .urlSessionFailed(let error):
            if let urlError = error as? URLError {
                // 재시도 가능한 특정 URLError 코드들
                return [
                    .timedOut, .networkConnectionLost, .notConnectedToInternet,
                    .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
                    .resourceUnavailable, .internationalRoamingOff
                ].contains(urlError.code)
            }
            return false // 일반적인 URLSession 에러는 재시도하지 않음
        default: return false // 클라이언트 에러, 디코딩/인코딩 에러 등은 일반적으로 재시도 불가
        }
    }
    
    /// Retry-After 값을 반환합니다 (있는 경우).
    public var retryAfter: TimeInterval? {
        switch self {
        case .tooManyRequests(_, let retryAfter): return retryAfter
        case .clientError(_, _, let retryAfter): return retryAfter
        case .serverError(_, _, let retryAfter): return retryAfter
        default: return nil
        }
    }
    
    public static func == (lhs: NetworkRequestError, rhs: NetworkRequestError) -> Bool {
        // Equatable 비교 로직 (기존 코드와 동일하게 유지)
        // ... (이 부분은 사용자가 제공한 원래 코드의 Equatable 구현을 그대로 사용합니다) ...
        switch (lhs, rhs) {
        case (.invalidRequest(let l), .invalidRequest(let r)): return l == r
        case (.invalidResponse, .invalidResponse): return true // 데이터 없이 타입만 비교
        case (.badRequest, .badRequest): return true
        case (.unauthorized, .unauthorized): return true
        case (.forbidden, .forbidden): return true
        case (.notFound, .notFound): return true
        case (.tooManyRequests, .tooManyRequests): return true
        case (.clientError(let lc, _, _), .clientError(let rc, _, _)): return lc == rc // 데이터 없이 코드만 비교
        case (.serverError(let lc, _, _), .serverError(let rc, _, _)): return lc == rc // 데이터 없이 코드만 비교
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
            if le == nil && re == nil { return true }
            if let lerr = le as NSError?, let rerr = re as NSError? {
                return lerr.domain == rerr.domain && lerr.code == rerr.code
            }
            return false
        case (.cancelled, .cancelled): return true
        case (.timedOut, .timedOut): return true
        case (.noInternetConnection, .noInternetConnection): return true
        default: return false
        }
    }
}

// MARK: - Netify Request Protocol

/// API 요청 명세를 정의하는 프로토콜입니다.
/// 이 프로토콜을 준수하여 특정 API 요청을 모델링할 수 있습니다.
@available(iOS 15, macOS 12, *)
public protocol NetifyRequest {
    /// 응답으로 기대하는 타입. `Decodable`을 준수해야 합니다.
    /// 내용 없는 성공 응답(예: 204 No Content)은 `EmptyResponse`를 사용합니다.
    associatedtype ReturnType: Decodable
    
    /// BaseURL을 제외한 API 경로 (예: "/users/1").
    var path: String { get }
    /// HTTP 요청 메소드 (기본값: `.get`).
    var method: HTTPMethod { get }
    /// 요청 본문의 `Content-Type` (기본값: `.json` - `body`가 제공될 경우).
    var contentType: HTTPContentType { get }
    /// URL 쿼리 파라미터 (예: `["page": "1", "limit": "20"]`).
    var queryParams: QueryParameters? { get }
    /// 요청 본문.
    /// - JSON: `Encodable` 객체.
    /// - URL Encoded: `[String: String]` (QueryParameters).
    /// - Plain Text/XML: `String`.
    /// - Data: `Data` (이 경우 `contentType`을 명시적으로 설정해야 함).
    var body: Any? { get }
    /// 커스텀 HTTP 헤더. 클라이언트 기본 헤더에 병합되며, 중복 시 이 헤더가 우선합니다.
    var headers: HTTPHeaders? { get }
    /// 멀티파트 요청 데이터. `body`와 함께 사용될 수 없으며, `multipartData`가 있으면 `body`는 무시됩니다.
    var multipartData: [MultipartData]? { get }
    /// 이 요청에만 사용할 특정 `JSONDecoder`. `nil`이면 클라이언트 기본 디코더를 사용합니다.
    var decoder: JSONDecoder? { get }
    /// 이 요청의 캐시 정책. `nil`이면 클라이언트 기본 캐시 정책을 사용합니다.
    var cachePolicy: URLRequest.CachePolicy? { get }
    /// 이 요청의 타임아웃 간격(초). `nil`이면 클라이언트 기본 타임아웃을 사용합니다.
    var timeoutInterval: TimeInterval? { get }
    /// 이 요청이 인증을 필요로 하는지 여부 (기본값: `true`).
    var requiresAuthentication: Bool { get }
}

// NetifyRequest 프로토콜의 기본 구현
@available(iOS 15, macOS 12, *)
extension NetifyRequest {
    public var method: HTTPMethod { .get }
    // contentType은 body 유무와 타입에 따라 RequestBuilder에서 더 정확히 결정될 수 있으나,
    // 프로토콜에서는 일반적인 기본값인 .json을 제공합니다.
    public var contentType: HTTPContentType { .json }
    public var queryParams: QueryParameters? { nil }
    public var body: Any? { nil }
    public var headers: HTTPHeaders? { nil }
    public var multipartData: [MultipartData]? { nil }
    public var decoder: JSONDecoder? { nil }
    public var cachePolicy: URLRequest.CachePolicy? { nil }
    public var timeoutInterval: TimeInterval? { nil }
    public var requiresAuthentication: Bool { true } // 대부분의 요청은 인증이 필요하다고 가정
}

// MARK: - Declarative API Layer - Configuration (새로운 코드)
@available(iOS 15, macOS 12, *)
internal struct DeclarativeNetifyTaskConfiguration<ReturnType: Decodable> {
    var pathTemplate: String = ""
    var method: HTTPMethod = .get
    var headers: HTTPHeaders = [:]
    var queryParams: QueryParameters = [:]
    var body: Any? = nil // Encodable, String, Data 등 다양한 타입 저장
    var explicitContentType: HTTPContentType? = nil
    var multipartItems: [MultipartData]? = nil
    var customDecoder: JSONDecoder? = nil
    var cachePolicy: URLRequest.CachePolicy? = nil
    var timeoutInterval: TimeInterval? = nil
    var requiresAuth: Bool = true
    var pathArguments: [String: CustomStringConvertible] = [:]
    
    /// 최종적으로 사용할 ContentType을 결정합니다.
    func resolveContentType() -> HTTPContentType {
        if let explicit = explicitContentType { // 1. 명시적 ContentType 최우선
            return explicit
        }
        if multipartItems != nil && !multipartItems!.isEmpty { // 2. 멀티파트 데이터가 있으면 .multipart
            return .multipart
        }
        if let body = body { // 3. body가 있으면 추론 시도
            if body is Data { // Data 타입이면 명시적 설정이 필요했어야 함, 없으면 octet-stream 가정
                return .octetStream // 또는 에러 처리. 여기서는 기본값 제공.
            }
            // Encodable, String 등은 .json, .plainText 등으로 .body() modifier에서 설정됨
            // 여기서 contentType이 결정 안되면 프로토콜 기본값(.json) 사용
            return .json // 기본 추론 (JSON)
        }
        // body가 없고 명시적 타입도 없으면 프로토콜 기본값(.json) 따름 (주로 GET 요청)
        return .json
    }
}

// MARK: - Declarative API Layer - Task Builder (새로운 코드)
/// 선언적 방식으로 네트워크 요청을 구성하는 빌더입니다.
/// 이 빌더를 통해 생성된 작업은 `NetifyRequest` 프로토콜을 준수합니다.
@available(iOS 15, macOS 12, *)
public struct DeclarativeNetifyTask<ReturnType: Decodable> {
    private var configuration: DeclarativeNetifyTaskConfiguration<ReturnType>
    
    private init() {
        self.configuration = DeclarativeNetifyTaskConfiguration<ReturnType>()
    }
    
    /// 내부적으로 빌더 인스턴스를 생성합니다. `Netify.task()`를 통해 사용하세요.
    internal static func new() -> DeclarativeNetifyTask<ReturnType> {
        DeclarativeNetifyTask<ReturnType>()
    }
    
    // --- Modifier Methods ---
    
    /// 요청의 HTTP 메소드를 설정합니다.
    public func method(_ method: HTTPMethod) -> Self {
        var newRequest = self; newRequest.configuration.method = method; return newRequest
    }
    
    /// 요청 경로 템플릿을 설정합니다. (예: "/users/{id}")
    public func path(_ pathTemplate: String) -> Self {
        var newRequest = self; newRequest.configuration.pathTemplate = pathTemplate; return newRequest
    }
    
    /// 경로 템플릿 내의 특정 인자 값을 설정합니다.
    public func pathArgument(_ key: String, _ value: CustomStringConvertible) -> Self {
        var newRequest = self; newRequest.configuration.pathArguments[key] = value; return newRequest
    }
    
    /// 여러 경로 인자들을 한 번에 설정합니다.
    public func pathArguments(_ args: [String: CustomStringConvertible]) -> Self {
        var newRequest = self; newRequest.configuration.pathArguments.merge(args) { (_, new) in new }; return newRequest
    }
    
    /// 요청에 커스텀 HTTP 헤더를 추가합니다.
    public func header(_ name: String, _ value: String) -> Self {
        var newRequest = self; newRequest.configuration.headers[name] = value; return newRequest
    }
    
    /// 여러 커스텀 HTTP 헤더를 한 번에 설정합니다.
    public func headers(_ headersToAdd: HTTPHeaders) -> Self {
        var newRequest = self; newRequest.configuration.headers.merge(headersToAdd) { (_, new) in new }; return newRequest
    }
    
    /// 요청 URL에 쿼리 파라미터를 추가합니다. 값이 `nil`이면 추가하지 않습니다.
    public func queryParam(_ name: String, _ value: CustomStringConvertible?) -> Self {
        guard let value = value else { return self }
        var newRequest = self; newRequest.configuration.queryParams[name] = value.description; return newRequest
    }
    
    /// 여러 쿼리 파라미터를 한 번에 설정합니다.
    public func queryParams(_ paramsToAdd: QueryParameters) -> Self {
        var newRequest = self; newRequest.configuration.queryParams.merge(paramsToAdd) { (_, new) in new }; return newRequest
    }
    
    /// `Encodable` 객체를 요청 본문으로 설정합니다. 기본 Content-Type은 `.json`입니다.
    public func body<B: Encodable>(_ encodableBody: B, contentType: HTTPContentType = .json) -> Self {
        var newRequest = self
        newRequest.configuration.body = encodableBody
        newRequest.configuration.explicitContentType = contentType
        newRequest.configuration.multipartItems = nil
        return newRequest
    }
    
    /// 문자열을 요청 본문으로 설정합니다. 기본 Content-Type은 `.plainText`입니다.
    public func body(_ stringBody: String, contentType: HTTPContentType = .plainText) -> Self {
        var newRequest = self
        newRequest.configuration.body = stringBody
        newRequest.configuration.explicitContentType = contentType
        newRequest.configuration.multipartItems = nil
        return newRequest
    }
    
    /// `Data`를 요청 본문으로 설정합니다. `contentType`을 명시적으로 지정해야 합니다.
    public func body(_ data: Data, contentType: HTTPContentType) -> Self {
        var newRequest = self
        newRequest.configuration.body = data
        newRequest.configuration.explicitContentType = contentType
        newRequest.configuration.multipartItems = nil
        return newRequest
    }
    
    /// 멀티파트 데이터를 요청 본문으로 설정합니다. Content-Type은 자동으로 `.multipart`로 설정됩니다.
    public func multipart(_ parts: [MultipartData]) -> Self {
        var newRequest = self
        newRequest.configuration.multipartItems = parts.isEmpty ? nil : parts // 빈 배열이면 nil로 설정
        newRequest.configuration.explicitContentType = .multipart
        newRequest.configuration.body = nil
        return newRequest
    }
    
    /// 요청의 `Content-Type`을 명시적으로 설정합니다.
    public func contentType(_ type: HTTPContentType) -> Self {
        var newRequest = self; newRequest.configuration.explicitContentType = type; return newRequest
    }
    
    /// 이 요청에 사용할 커스텀 `JSONDecoder`를 지정합니다.
    public func customDecoder(_ decoder: JSONDecoder) -> Self {
        var newRequest = self; newRequest.configuration.customDecoder = decoder; return newRequest
    }
    
    /// 이 요청의 `URLRequest.CachePolicy`를 설정합니다.
    public func cachePolicy(_ policy: URLRequest.CachePolicy) -> Self {
        var newRequest = self; newRequest.configuration.cachePolicy = policy; return newRequest
    }
    
    /// 이 요청의 타임아웃 간격(초)을 설정합니다.
    public func timeout(_ interval: TimeInterval) -> Self {
        var newRequest = self; newRequest.configuration.timeoutInterval = interval; return newRequest
    }
    
    /// 이 요청이 인증을 필요로 하는지 여부를 지정합니다.
    public func authentication(required: Bool) -> Self {
        var newRequest = self; newRequest.configuration.requiresAuth = required; return newRequest
    }
}

// MARK: - Declarative API Layer - NetifyRequest Conformance (새로운 코드)
@available(iOS 15, macOS 12, *)
extension DeclarativeNetifyTask: NetifyRequest {
    // ReturnType은 이미 구조체의 제네릭 파라미터로 정의됨
    
    public var path: String {
        configuration.pathArguments.reduce(configuration.pathTemplate) { currentPath, argument in
            currentPath.replacingOccurrences(of: "{\(argument.key)}", with: argument.value.description)
        }
    }
    public var method: HTTPMethod { configuration.method }
    public var contentType: HTTPContentType { configuration.resolveContentType() }
    public var queryParams: QueryParameters? { configuration.queryParams.isEmpty ? nil : configuration.queryParams }
    public var body: Any? { configuration.body }
    public var headers: HTTPHeaders? { configuration.headers.isEmpty ? nil : configuration.headers }
    public var multipartData: [MultipartData]? { configuration.multipartItems }
    public var decoder: JSONDecoder? { configuration.customDecoder }
    public var cachePolicy: URLRequest.CachePolicy? { configuration.cachePolicy }
    public var timeoutInterval: TimeInterval? { configuration.timeoutInterval }
    public var requiresAuthentication: Bool { configuration.requiresAuth }
}

// MARK: - Declarative API Layer - Entry Point (새로운 코드)
/// Netify의 선언적 API 진입점을 제공하는 네임스페이스입니다.
@available(iOS 15, macOS 12, *)
public enum Netify {
    /// 특정 `Decodable` 응답 타입을 기대하는 선언적 네트워크 작업을 빌드하기 시작합니다.
    public static func task<R: Decodable>(expecting responseType: R.Type = R.self) -> DeclarativeNetifyTask<R> {
        return DeclarativeNetifyTask<R>.new()
    }
    
    /// 선언적 GET 네트워크 작업을 빌드하기 시작합니다.
    public static func get<R: Decodable>(expecting responseType: R.Type = R.self) -> DeclarativeNetifyTask<R> {
        return DeclarativeNetifyTask<R>.new().method(.get)
    }
    /// 선언적 POST 네트워크 작업을 빌드하기 시작합니다.
    public static func post<R: Decodable>(expecting responseType: R.Type = R.self) -> DeclarativeNetifyTask<R> {
        return DeclarativeNetifyTask<R>.new().method(.post)
    }
    /// 선언적 PUT 네트워크 작업을 빌드하기 시작합니다.
    public static func put<R: Decodable>(expecting responseType: R.Type = R.self) -> DeclarativeNetifyTask<R> {
        return DeclarativeNetifyTask<R>.new().method(.put)
    }
    /// 선언적 DELETE 네트워크 작업을 빌드하기 시작합니다.
    public static func delete<R: Decodable>(expecting responseType: R.Type = R.self) -> DeclarativeNetifyTask<R> {
        return DeclarativeNetifyTask<R>.new().method(.delete)
    }
    /// 선언적 PATCH 네트워크 작업을 빌드하기 시작합니다.
    public static func patch<R: Decodable>(expecting responseType: R.Type = R.self) -> DeclarativeNetifyTask<R> {
        return DeclarativeNetifyTask<R>.new().method(.patch)
    }
}

// MARK: - Authentication Provider Protocol & Implementations

/// 인증 관련 동작을 정의하는 프로토콜입니다. `Sendable`을 준수합니다.
@available(iOS 15, macOS 12, *)
public protocol AuthenticationProvider: Sendable {
    /// 요청에 인증 정보를 비동기적으로 추가합니다.
    func authenticate(request: URLRequest) async throws -> URLRequest
    /// 인증 토큰 만료 시 호출되어 비동기적으로 갱신을 시도합니다.
    func refreshAuthentication() async throws -> Bool
    /// 주어진 에러가 인증 만료(예: 401 Unauthorized)를 나타내는지 확인합니다.
    func isAuthenticationExpired(from error: Error) -> Bool
}

/// HTTP 기본 인증 프로바이더입니다. `Sendable`을 준수합니다.
@available(iOS 15, macOS 12, *)
public struct BasicAuthenticationProvider: AuthenticationProvider { // Sendable은 이미 UserCredentials에 의해 암시적으로 준수
    private let credentials: UserCredentials
    
    public init(credentials: UserCredentials) {
        self.credentials = credentials
    }
    
    public func authenticate(request: URLRequest) async throws -> URLRequest {
        var req = request
        req.setValue(credentials.basicAuthHeaderValue, forHTTPHeaderField: HTTPHeaderField.authorization.rawValue)
        return req
    }
    
    // 기본 인증은 토큰 갱신 개념이 없습니다.
    public func refreshAuthentication() async throws -> Bool { return false }
    
    // 기본 인증에서 401은 일반적으로 자격 증명 실패 또는 만료를 의미합니다.
    public func isAuthenticationExpired(from error: Error) -> Bool {
        if let netErr = error as? NetworkRequestError, case .unauthorized = netErr { return true }
        return false
    }
}

/// Bearer 토큰 인증 프로바이더입니다. 토큰 관리 및 갱신 로직을 포함하며, `actor`로 구현되어 동시 접근에 안전합니다.
@available(iOS 15, macOS 12, *)
public actor BearerTokenAuthenticationProvider: AuthenticationProvider {
    private var accessToken: String
    private var refreshToken: String?
    private let refreshHandler: RefreshTokenHandler? // 토큰 갱신 로직을 담는 클로저
    private var refreshTask: Task<Bool, Error>? // 동시 토큰 갱신 방지를 위한 Task
    
    /// 리프레시 토큰을 사용하여 새 토큰 정보를 가져오는 클로저 타입 정의. `@Sendable`을 준수합니다.
    public typealias RefreshTokenHandler = @Sendable (String) async throws -> TokenInfo
    
    /// 갱신된 토큰 정보를 담는 구조체. `Codable` 및 `Sendable`을 준수합니다.
    public struct TokenInfo: Codable, Sendable {
        public let accessToken: String
        public let refreshToken: String? // 옵셔널: 리프레시 토큰이 갱신되지 않을 수도 있음
        public let expiresIn: TimeInterval? // 옵셔널: 토큰 만료 시간(초)
        
        public init(accessToken: String, refreshToken: String? = nil, expiresIn: TimeInterval? = nil) {
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            self.expiresIn = expiresIn
        }
    }
    
    public init(accessToken: String, refreshToken: String? = nil, refreshHandler: RefreshTokenHandler? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.refreshHandler = refreshHandler
    }
    
    public func authenticate(request: URLRequest) async throws -> URLRequest {
        var req = request
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: HTTPHeaderField.authorization.rawValue)
        return req
    }
    
    public func refreshAuthentication() async throws -> Bool {
        // 이미 갱신 작업이 진행 중이면 해당 작업의 결과를 기다림
        if let existingTask = refreshTask {
            return try await existingTask.value
        }
        
        // 리프레시 토큰이나 핸들러가 없으면 갱신 불가
        guard let currentRefreshToken = refreshToken, let handler = refreshHandler else {
            return false
        }
        
        // 새로운 Task를 생성하여 토큰 갱신 수행
        let task = Task<Bool, Error> {
            defer { self.refreshTask = nil } // 작업 완료 시 refreshTask를 nil로 설정
            
            let newTokens = try await handler(currentRefreshToken) // 핸들러 호출
            
            self.accessToken = newTokens.accessToken // 새 액세스 토큰으로 업데이트
            // 핸들러가 새 리프레시 토큰을 제공하면 업데이트, 아니면 기존 값 유지 (nil일 수도 있음)
            self.refreshToken = newTokens.refreshToken ?? self.refreshToken
            
            // TODO: expiresIn을 사용하여 다음 자동 갱신 스케줄링 등의 로직 추가 가능
            return true // 갱신 성공
        }
        self.refreshTask = task // 현재 진행 중인 작업으로 저장
        return try await task.value // 작업 결과 반환
    }
    
    // isAuthenticationExpired는 외부 상태에 의존하지 않으므로 nonisolated로 선언 가능
    public nonisolated func isAuthenticationExpired(from error: Error) -> Bool {
        if let netErr = error as? NetworkRequestError, case .unauthorized = netErr { return true }
        // TODO: API가 특정 에러 코드로 토큰 만료를 알리는 경우 추가 검사 로직 구현 가능
        return false
    }
    
    /// 외부에서 토큰을 직접 업데이트할 수 있는 메소드 (예: 로그인 성공 후).
    public func updateTokens(accessToken: String, refreshToken: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
    
    /// 현재 액세스 토큰을 안전하게 가져옵니다.
    public func getCurrentAccessToken() -> String {
        return accessToken
    }
}


// MARK: - Multipart Data Structures

/// HTTP 요청 본문의 일부를 나타내는 프로토콜입니다 (주로 멀티파트).
@available(iOS 15, macOS 12, *)
public protocol HttpBodyConvertible {
    /// 멀티파트 요청의 한 부분을 구성하는 데이터를 생성합니다.
    /// - Parameter boundary: 멀티파트 경계 문자열.
    /// - Returns: 생성된 `Data` 객체.
    func buildHttpBodyPart(boundary: String) -> Data
}

/// 멀티파트 요청에 포함될 파일 또는 데이터 청크를 나타냅니다. `Identifiable`, `HttpBodyConvertible`, `Sendable`을 준수합니다.
@available(iOS 15, macOS 12, *)
public struct MultipartData: Identifiable, HttpBodyConvertible, Sendable {
    public let id = UUID() // 각 파트의 고유 식별자
    let name: String       // 폼 필드의 이름 (API 명세에 따름)
    let fileData: Data     // 실제 파일 또는 데이터
    let fileName: String   // 서버에 전달될 파일 이름
    let mimeType: String   // 데이터의 MIME 타입 (예: "image/jpeg", "application/pdf")
    
    public init(name: String, fileData: Data, fileName: String, mimeType: String) {
        self.name = name
        self.fileData = fileData
        self.fileName = fileName
        self.mimeType = mimeType
    }
    
    public func buildHttpBodyPart(boundary: String) -> Data {
        let body = NSMutableData()
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n")
        body.appendString("Content-Type: \(mimeType)\r\n\r\n") // 헤더와 데이터 사이에는 CRLF 두 번
        body.append(fileData)
        body.appendString("\r\n") // 각 파트의 끝
        return body as Data
    }
}

// MARK: - URL Utilities & Extensions

/// URL 경로 결합 및 생성을 위한 헬퍼 구조체입니다.
@available(iOS 15, macOS 12, *)
public struct URLPathBuilder {
    /// 기본 URL 문자열과 경로 문자열을 결합하여 URL 객체를 생성합니다.
    /// 기본 URL과 경로 사이의 슬래시(/)를 적절히 처리합니다.
    public static func buildURL(baseURL: String, path: String) throws -> URL {
        guard var components = URLComponents(string: baseURL) else {
            throw NetworkRequestError.invalidRequest(reason: "잘못된 기본 URL 문자열입니다: \(baseURL)")
        }
        
        let basePath = components.path // 기본 URL 자체의 경로 부분
        let pathToAppend = path.starts(with: "/") ? String(path.dropFirst()) : path // 추가할 경로의 첫 슬래시 제거
        
        // 기본 경로가 비어있거나 슬래시로 끝나면 바로 연결, 아니면 슬래시 추가 후 연결
        if basePath.isEmpty || basePath.hasSuffix("/") {
            components.path = basePath + pathToAppend
        } else {
            components.path = basePath + "/" + pathToAppend
        }
        
        // 경로 정규화: 중복 슬래시 제거 (예: /api//v1/users -> /api/v1/users)
        // URLComponents.path는 자동으로 선행 슬래시를 관리하므로, 수동으로 추가/제거할 필요가 줄어듭니다.
        // 하지만, 여기서 명시적으로 한번 더 정제하여 일관성을 높입니다.
        let normalizedPath = components.path.split(separator: "/", omittingEmptySubsequences: true).joined(separator: "/")
        components.path = normalizedPath.isEmpty ? "/" : "/" + normalizedPath // 비어있지 않으면 항상 슬래시로 시작
        
        guard let url = components.url else {
            throw NetworkRequestError.invalidRequest(reason: "최종 URL 생성 실패: baseURL '\(baseURL)', path '\(path)'")
        }
        return url
    }
}

@available(iOS 15, macOS 12, *)
extension CharacterSet {
    /// RFC 3986에 따른 URL 쿼리 값 인코딩에 허용되는 문자 집합입니다.
    /// 알파벳, 숫자 및 '-', '.', '_', '~'를 포함합니다. 일반 구분자와 하위 구분자는 제외합니다.
    public static let urlQueryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~") // 비예약(unreserved) 문자
        return allowed
    }()
}

/// `QueryParameters` ([String: String])를 URL 쿼리 문자열로 변환하는 확장입니다.
@available(iOS 15, macOS 12, *)
extension Dictionary where Key == String, Value == String {
    /// 딕셔너리를 URL 인코딩된 쿼리 문자열로 변환합니다 (예: "key1=value1&key2=value2").
    /// 키와 값은 `CharacterSet.urlQueryValueAllowed`를 사용하여 퍼센트 인코딩됩니다.
    public func toUrlEncodedQueryString() -> String? {
        guard !self.isEmpty else { return nil }
        return self.map { key, value in
            // 키와 값 모두 퍼센트 인코딩
            let escapedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let escapedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? value
            return "\(escapedKey)=\(escapedValue)"
        }.joined(separator: "&")
    }
    
    // toURLQueryItems()는 URLComponents가 내부적으로 인코딩을 처리하므로 유지합니다.
    public func toURLQueryItems() -> [URLQueryItem]? {
        guard !isEmpty else { return nil }
        return map { URLQueryItem(name: $0.key, value: $0.value) }
    }
}

/// `NSMutableData`에 문자열을 UTF-8 데이터로 추가하는 내부 확장 기능입니다.
internal extension NSMutableData {
    /// 지정된 문자열을 UTF-8 인코딩을 사용하여 `NSMutableData`에 추가합니다.
    func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            self.append(data)
        }
        // UTF-8 인코딩 실패 시 (거의 발생하지 않음) 로깅 또는 에러 처리 고려 가능
    }
}

/// `URLRequest`를 cURL 명령어 문자열로 변환하는 확장 기능입니다 (디버깅 목적).
@available(iOS 15, macOS 12, *)
extension URLRequest {
    /// 디버깅을 위해 `URLRequest`의 cURL 명령어 문자열 표현을 생성합니다.
    /// 민감한 헤더(Authorization, Cookie 등)는 마스킹 처리됩니다.
    public func toCurlCommand() -> String {
        guard let url = self.url else { return "# Netify: cURL 명령어 생성 실패 (유효하지 않은 URL)" }
        var command = [#"curl -v "\#(url.absoluteString)""#] // -v 옵션으로 상세 출력
        
        // HTTP 메소드 추가 (GET이 아니면)
        if let httpMethod = self.httpMethod, httpMethod.uppercased() != "GET" {
            command.append("-X \(httpMethod.uppercased())")
        }
        
        // 헤더 추가 (민감 정보 마스킹)
        self.allHTTPHeaderFields?.sorted(by: { $0.key < $1.key }).forEach { key, value in
            let displayValue = NetifyInternalConstants.sensitiveHeaderKeys.contains(key.lowercased()) ? "<masked>" : value
            let escapedValue = displayValue.replacingOccurrences(of: "'", with: #"\'"#) // 작은 따옴표 이스케이프
            command.append("-H '\(key): \(escapedValue)'")
        }
        
        // 본문 데이터 추가
        if let httpBodyData = self.httpBody {
            if let bodyString = String(data: httpBodyData, encoding: .utf8), !bodyString.isEmpty {
                let maxLen = NetifyInternalConstants.maxLogSummaryLength
                let truncatedBody = bodyString.prefix(maxLen)
                let escapedBody = String(truncatedBody).replacingOccurrences(of: "'", with: #"\'"#)
                command.append("-d '\(escapedBody)\(bodyString.count > maxLen ? "..." : "")'")
            } else if !httpBodyData.isEmpty {
                command.append("--data-binary '<바이너리 데이터: \(httpBodyData.count) bytes>'")
            }
        } else if let stream = self.httpBodyStream {
            command.append("--data-binary '<입력 스트림 데이터: \(stream.description)>'")
        }
        
        // 가독성을 위해 줄바꿈 및 들여쓰기 적용
        return command.joined(separator: " \\\n    ")
    }
}

// MARK: - Sanitization Utilities for Plugins

@available(iOS 15, macOS 12, *)
internal func sanitizeForOperationString(_ message: String) -> String {
    var s = message
    let patterns: [(String, String)] = [
        ("(?i)\\bBearer\\s+[A-Za-z0-9\\-._~+/]+=*", "Bearer <masked>"),
        ("(?i)\\bBasic\\s+[A-Za-z0-9+/]+=*", "Basic <masked>"),
        ("(?i)\\b(token|access[_-]?token|password|secret)[\"':\\s=]+[^\\s\"']+", "$1: <masked>"),
        ("\\b[A-Za-z0-9-_]+?\\.[A-Za-z0-9-_]+?\\.[A-Za-z0-9-_]+\\b", "<jwt:masked>"),
        ("([?&](?i)(api[_-]?key|key|access[_-]?token)=)[^&]+", "$1<masked>"),
        ("(?i)(cookie:\\s*)(.+)", "$1<masked>")
    ]
    for (re, rep) in patterns {
        s = s.replacingOccurrences(of: re, with: rep, options: [.regularExpression])
    }
    return s
}

@available(iOS 15, macOS 12, *)
public struct RequestSummary: Sendable {
    public let url: String?
    public let method: String?
    public let headers: [String: String]?
    public let bodyPreview: String?
}

@available(iOS 15, macOS 12, *)
internal extension URLRequest {
    /// 플러그인에 안전하게 전달하기 위한 요청 요약을 생성합니다.
    func toRequestSummaryForPlugins(maxBody: Int = 256) -> RequestSummary {
        let urlString = self.url?.absoluteString
        let maskedURL = urlString.map { sanitizeForOperationString($0) }

        var headersSummary: [String: String]? = nil
        if let headers = self.allHTTPHeaderFields, !headers.isEmpty {
            var masked: [String: String] = [:]
            for (k, v) in headers {
                if NetifyInternalConstants.sensitiveHeaderKeys.contains(k.lowercased()) {
                    masked[k] = "<masked>"
                } else {
                    masked[k] = sanitizeForOperationString(v)
                }
            }
            headersSummary = masked
        }

        var bodyPreview: String? = nil
        if let body = self.httpBody, !body.isEmpty {
            if let s = String(data: body, encoding: .utf8) {
                let truncated = s.prefix(maxBody)
                bodyPreview = sanitizeForOperationString(String(truncated)) + (s.count > maxBody ? "..." : "")
            } else {
                bodyPreview = "<binary data: \(body.count) bytes>"
            }
        } else if self.httpBodyStream != nil {
            bodyPreview = "<input stream>"
        }

        return RequestSummary(
            url: maskedURL,
            method: self.httpMethod,
            headers: headersSummary,
            bodyPreview: bodyPreview
        )
    }
}

// MARK: - Netify Client (Core Logic)

/// 실제 네트워크 요청 실행 및 관리를 담당하는 클라이언트입니다. `NetifyClientProtocol`을 준수합니다.
@available(iOS 15, macOS 12, *)
public final class NetifyClient: NetifyClientProtocol {
    public let configuration: NetifyConfiguration
    private let networkSession: NetworkSessionProtocol // URLSession 대신 프로토콜 사용
    private let logger: NetifyLogging
    private let requestBuilder: RequestBuilder // 내부 RequestBuilder 사용
    private let pluginExecutor: SafePluginExecutor
    private let metricsExecutor: SafeMetricsExecutor
    
    /// Netify 클라이언트를 초기화합니다.
    /// - Parameters:
    ///   - configuration: 클라이언트 동작을 정의하는 설정 객체.
    ///   - networkSession: 네트워크 요청을 처리할 세션 객체 (테스트 목적으로 주입 가능). 기본값은 `configuration`에 기반한 `URLSession`.
    ///   - logger: 로깅을 처리할 로거 객체 (테스트 목적으로 주입 가능). 기본값은 `DefaultNetifyLogger`.
    public init(
        configuration: NetifyConfiguration,
        networkSession: NetworkSessionProtocol? = nil,
        logger: NetifyLogging? = nil // 로거 주입 옵션 추가
    ) {
        self.configuration = configuration
        self.networkSession = networkSession ?? URLSession(configuration: configuration.sessionConfiguration)
        self.logger = logger ?? DefaultNetifyLogger(logLevel: configuration.logLevel) // 주입받거나 기본 로거 사용
        self.requestBuilder = RequestBuilder(configuration: configuration, logger: self.logger) // 빌더에 로거 전달
        self.pluginExecutor = SafePluginExecutor(logger: self.logger)
        self.metricsExecutor = SafeMetricsExecutor(logger: self.logger)
        
        self.logger.logForOperation("NetifyClient 초기화 완료. BaseURL: \(configuration.baseURL), LogLevel: \(configuration.logLevel)")
    }
    
    /// 특정 `NetifyRequest`를 비동기적으로 보내고 응답을 처리합니다.
    /// 재시도 및 인증 토큰 갱신 로직을 포함합니다.
    public func send<Request: NetifyRequest>(_ request: Request) async throws -> Request.ReturnType {
        try await sendRequestWithRetry(request, currentRetryCount: 0)
    }
    
    /// 재시도 및 인증 갱신 로직을 포함하여 요청을 처리하는 내부 메소드입니다.
    private func sendRequestWithRetry<Request: NetifyRequest>(_ request: Request, currentRetryCount: Int) async throws -> Request.ReturnType {
        // 취소 확인
        try Task.checkCancellation()
        
        let startTime = Date()
        var urlRequest: URLRequest
        
        do {
            urlRequest = try await requestBuilder.buildURLRequest(from: request)
            
            // 플러그인 willSend 실행
            urlRequest = await pluginExecutor.executeWillSend(plugins: configuration.plugins, request: urlRequest)
            
            // 간소 디버그 로그로 요청 정보 출력 (민감정보는 내부에서 마스킹)
            let reqMethod = urlRequest.httpMethod ?? "UNKNOWN_METHOD"
            let reqURL = urlRequest.url?.absoluteString ?? "UNKNOWN_URL"
            logger.logForDebug("➡️ Request: \(reqMethod) \(reqURL)\n    cURL: \(urlRequest.toCurlCommand())")
        } catch {
            let netifyError = mapToNetifyError(error) // 에러 매핑
            logger.logForOperation("요청 구성 실패: \(netifyError.localizedDescription)")
            logger.logEnhancedError(netifyError)
            
            // 플러그인 didFail 실행 (요청 구성 실패이므로 request는 nil)
            let context = PluginFailureContext(
                requestSummary: nil,
                errorSummary: netifyError.localizedDescription,
                startedAt: startTime,
                attemptCount: currentRetryCount
            )
            await pluginExecutor.executeDidFail(plugins: configuration.plugins, context: context)
            
            throw netifyError
        }
        
        do {
            let (data, response) = try await performDataTask(for: urlRequest)
            // 간소 디버그 로그로 응답 정보 출력
            if let httpResponse = response as? HTTPURLResponse {
                let status = httpResponse.statusCode
                let resURL = response.url?.absoluteString ?? "UNKNOWN_URL"
                logger.logForDebug("⬅️ Response: Status \(status) from \(resURL) (\(data.count) bytes)")
            } else {
                logger.logForDebug("⬅️ Response: Non-HTTP response (\(type(of: response)))")
            }
            
            let result = try handleResponse(response: response, data: data, for: request)
            
            // 성공 시 플러그인과 메트릭 실행
            await pluginExecutor.executeDidReceive(plugins: configuration.plugins, response: response, data: data, request: urlRequest)
            
            if let httpResponse = response as? HTTPURLResponse {
                let duration = Date().timeIntervalSince(startTime)
                await metricsExecutor.recordRequest(
                    metrics: configuration.metrics,
                    url: urlRequest.url?.absoluteString ?? "",
                    method: urlRequest.httpMethod ?? "",
                    statusCode: httpResponse.statusCode,
                    duration: duration,
                    responseSize: data.count
                )
            }
            
            return result
        } catch let error {
            let duration = Date().timeIntervalSince(startTime)
            let netifyError = mapToNetifyError(error)
            logger.logForOperation("요청 실행 실패: \(netifyError.localizedDescription)")
            logger.logEnhancedError(netifyError)
            
            // 플러그인 didFail 실행
            let context = PluginFailureContext(
                requestSummary: urlRequest.toRequestSummaryForPlugins(),
                errorSummary: netifyError.localizedDescription,
                startedAt: startTime,
                attemptCount: currentRetryCount
            )
            await pluginExecutor.executeDidFail(plugins: configuration.plugins, context: context)
            
            // 메트릭 기록
            await metricsExecutor.recordError(
                metrics: configuration.metrics,
                url: urlRequest.url?.absoluteString ?? "",
                method: urlRequest.httpMethod ?? "",
                error: netifyError,
                duration: duration
            )
            
            // 인증 실패 처리
            if request.requiresAuthentication,
               let authProvider = configuration.authenticationProvider,
               authProvider.isAuthenticationExpired(from: netifyError) {
                
                logger.logForOperation("인증 만료 감지, 토큰 갱신 시도")
                logger.logForDebug("인증 만료 세부사항: \(netifyError.localizedDescription)")
                let refreshSuccess = await attemptAuthRefresh(using: authProvider)
                
                if refreshSuccess {
                    logger.logForOperation("인증 토큰 갱신 성공, 요청 재시도")
                    // 인증 성공 시 재시도 횟수 증가 없이 즉시 재시도
                    return try await sendRequestWithRetry(request, currentRetryCount: currentRetryCount)
                } else {
                    logger.logForOperation("인증 토큰 갱신 실패: \(netifyError.localizedDescription)")
                    throw netifyError // 갱신 실패 시 원본 에러 (예: .unauthorized) 발생
                }
            }
            
            // 일반 재시도 처리
            if netifyError.isRetryable && currentRetryCount < configuration.maxRetryCount {
                let delaySeconds = await calculateRetryDelay(for: netifyError, attempt: currentRetryCount)
                logger.logForOperation("재시도 실행: (\(currentRetryCount + 1)/\(configuration.maxRetryCount)), \(delaySeconds)초 대기")
                logger.logForDebug("재시도 상세정보: \(netifyError.localizedDescription)")
                
                // 재시도 메트릭 기록
                await metricsExecutor.recordRetry(
                    metrics: configuration.metrics,
                    url: urlRequest.url?.absoluteString ?? "",
                    method: urlRequest.httpMethod ?? "",
                    attempt: currentRetryCount + 1,
                    error: netifyError
                )
                
                // 취소 확인 (대기 전)
                try Task.checkCancellation()
                
                try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000)) // 재시도 전 대기
                
                // 취소 확인 (대기 후)
                try Task.checkCancellation()
                
                return try await sendRequestWithRetry(request, currentRetryCount: currentRetryCount + 1) // 재귀 호출 (재시도 횟수 증가)
            }
            
            throw netifyError // 재시도 불가 또는 최대 재시도 도달 시 최종 에러 발생
        }
    }
    
    /// `NetworkSessionProtocol`을 사용하여 실제 데이터 작업을 수행합니다.
    private func performDataTask(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await networkSession.data(for: request, delegate: nil) // URLSessionTaskDelegate는 현재 사용하지 않음
    }
    
    /// `URLResponse` 및 `Data`를 처리하고, 상태 코드를 검증하며, 데이터를 디코딩합니다.
    /// `NetifyRequest` 정보를 사용하여 적절한 디코더를 선택합니다.
    private func handleResponse<Request: NetifyRequest>(response: URLResponse, data: Data, for netifyRequest: Request) throws -> Request.ReturnType {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetifyError(kind: .invalidResponse(response: response))
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw mapStatusCodeToError(statusCode: httpResponse.statusCode, data: data, response: httpResponse)
        }
        
        // 성공 응답 (2xx) 처리
        if data.isEmpty {
            if Request.ReturnType.self == EmptyResponse.self { // 기대 타입이 EmptyResponse인 경우
                guard let empty = EmptyResponse() as? Request.ReturnType else {
                    // 이 캐스팅은 이론적으로 항상 성공해야 함
                    throw NetifyError(kind: .unknownError(underlyingError: NSError(domain: "Netify.HandleResponse", code: -1001, userInfo: [NSLocalizedDescriptionKey: "EmptyResponse 캐스팅 실패"])))
                }
                return empty
            } else if Request.ReturnType.self == Data.self { // 기대 타입이 Data인 경우 (빈 데이터도 유효)
                guard let emptyData = data as? Request.ReturnType else {
                    throw NetifyError(kind: .unknownError(underlyingError: NSError(domain: "Netify.HandleResponse", code: -1002, userInfo: [NSLocalizedDescriptionKey: "빈 Data 객체 캐스팅 실패"])))
                }
                return emptyData
            } else { // 다른 Decodable 타입을 기대하는데 데이터가 비어있으면 에러
                throw NetifyError(kind: .decodingError(underlyingError: NSError(domain: "Netify.HandleResponse", code: -1003, userInfo: [NSLocalizedDescriptionKey: "\(Request.ReturnType.self) 타입을 기대했으나 빈 응답 본문을 받았습니다."]), data: data))
            }
        } else { // 데이터가 있는 경우 디코딩 시도
            do {
                let decoder = netifyRequest.decoder ?? configuration.defaultDecoder // 요청별 디코더 또는 클라이언트 기본 디코더 사용
                return try decoder.decode(Request.ReturnType.self, from: data)
            } catch let decodingError {
                throw NetifyError(kind: .decodingError(underlyingError: decodingError, data: data)) // 원본 디코딩 에러 포함
            }
        }
    }
    
    /// 인증 토큰 갱신을 시도하는 헬퍼 함수입니다.
    private func attemptAuthRefresh(using authProvider: AuthenticationProvider) async -> Bool {
        do {
            logger.logForDebug("AuthenticationProvider.refreshAuthentication() 호출 중")
            let success = try await authProvider.refreshAuthentication()
            if success {
                logger.logForOperation("인증 토큰 갱신 완료")
            } else {
                logger.logForOperation("인증 토큰 갱신 실패: 프로바이더가 false 반환")
            }
            return success
        } catch {
            let refreshError = mapToNetifyError(error) // 갱신 중 발생한 에러 매핑
            logger.logForOperation("인증 토큰 갱신 중 예외 발생: \(refreshError.localizedDescription)")
            logger.logEnhancedError(refreshError)
            return false // 갱신 실패
        }
    }
    
    /// 다양한 `Error` 타입을 일관된 `NetifyError`로 매핑합니다.
    private func mapToNetifyError(_ error: Error, context: ErrorContext? = nil) -> NetifyError {
        let kind: NetworkRequestError
        
        switch error {
        case let netifyError as NetworkRequestError: 
            kind = netifyError // 이미 NetworkRequestError인 경우
        case let netifyError as NetifyError:
            return netifyError // 이미 NetifyError인 경우는 그대로 반환
        case let urlError as URLError:
            switch urlError.code {
            case .cancelled: kind = .cancelled
            case .timedOut: kind = .timedOut
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
                    .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .resourceUnavailable,
                    .internationalRoamingOff, .secureConnectionFailed, .serverCertificateHasBadDate,
                    .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
                kind = .noInternetConnection // 다양한 연결 관련 문제 그룹화
            default: kind = .urlSessionFailed(underlyingError: urlError)
            }
        case let encodingError as EncodingError: 
            kind = .encodingError(underlyingError: encodingError)
        case let decodingError as DecodingError:
            // handleResponse에서 이미 data와 함께 .decodingError로 래핑하므로, 여기서 data는 nil일 수 있음
            kind = .decodingError(underlyingError: decodingError, data: nil)
        case is CancellationError: 
            kind = .cancelled // Task 취소 에러
        default: 
            kind = .unknownError(underlyingError: error)
        }
        
        return NetifyError(kind: kind, context: context)
    }
    
    /// 재시도 지연 시간을 계산합니다 (지수 백오프 + 지터 + Retry-After 헤더 고려).
    private func calculateRetryDelay(for error: NetifyError, attempt: Int) async -> TimeInterval {
        // 1. Retry-After 헤더가 있으면 우선 사용
        if let retryAfter = error.retryAfter {
            return min(retryAfter, NetifyInternalConstants.maxRetryDelaySeconds)
        }
        
        // 2. 지수 백오프 계산 (기본 지연 시간 * 2^시도횟수)
        let baseDelay = NetifyInternalConstants.defaultRetryDelaySeconds
        let exponentialDelay = baseDelay * pow(NetifyInternalConstants.exponentialBackoffMultiplier, Double(attempt))
        
        // 3. 지터 추가 (0%~25% 랜덤 변동)
        let jitterFactor = 1.0 + (Double.random(in: 0...0.25))
        let delayWithJitter = exponentialDelay * jitterFactor
        
        // 4. 최대 지연 시간 제한
        return min(delayWithJitter, NetifyInternalConstants.maxRetryDelaySeconds)
    }
    
    /// HTTP 응답에서 Retry-After 헤더를 파싱합니다.
    private func parseRetryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let retryAfterValue = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }
        
        // 1. 초 단위 숫자로 파싱 시도
        if let seconds = TimeInterval(retryAfterValue) {
            return seconds
        }
        
        // 2. HTTP 날짜 형식으로 파싱 시도
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(abbreviation: "GMT")
        
        if let date = formatter.date(from: retryAfterValue) {
            let interval = date.timeIntervalSinceNow
            return max(0, interval) // 과거 날짜면 0 반환
        }
        
        return nil // 파싱 실패
    }
    
    /// HTTP 상태 코드(2xx 범위 외)를 적절한 `NetifyError`로 매핑합니다.
    private func mapStatusCodeToError(statusCode: Int, data: Data?, response: HTTPURLResponse, context: ErrorContext? = nil) -> NetifyError {
        let retryAfter = parseRetryAfter(from: response)
        
        let kind: NetworkRequestError
        switch statusCode {
        case 400: kind = .badRequest(data: data)
        case 401: kind = .unauthorized(data: data)
        case 403: kind = .forbidden(data: data)
        case 404: kind = .notFound(data: data)
        case 429: kind = .tooManyRequests(data: data, retryAfter: retryAfter)
        case 405...499: kind = .clientError(statusCode: statusCode, data: data, retryAfter: retryAfter) // 기타 4xx 에러
        case 500...599: kind = .serverError(statusCode: statusCode, data: data, retryAfter: retryAfter) // 모든 5xx 에러
        default: // 예상치 못한 상태 코드 (예: 1xx, 3xx - 3xx는 URLSession에서 자동 처리되는 경우가 많음)
            logger.logForOperation("처리되지 않은 HTTP 상태 코드 수신: \(statusCode)")
            kind = .unknownError(underlyingError: NSError(domain: "Netify.StatusCodeMapping", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "처리되지 않은 HTTP 상태 코드: \(statusCode)"]))
        }
        
        return NetifyError(kind: kind, context: context)
    }
}

// MARK: - Request Builder (Internal Helper)

/// `URLRequest` 생성을 담당하는 내부 헬퍼 클래스/구조체입니다.
/// `NetifyConfiguration`과 `NetifyLogging`을 주입받아 사용합니다.
@available(iOS 15, macOS 12, *)
internal struct RequestBuilder {
    let configuration: NetifyConfiguration
    let logger: NetifyLogging
    
    /// `NetifyRequest`로부터 `URLRequest`를 빌드합니다.
    /// URL 구성, 쿼리 파라미터, 헤더, 본문 인코딩, 인증 처리를 담당합니다.
    func buildURLRequest<Request: NetifyRequest>(from netifyRequest: Request) async throws -> URLRequest {
        // 1. 최종 URL 구성 (경로 + 쿼리 파라미터)
        let url = try buildFinalURL(for: netifyRequest)
        
        // 2. URLRequest 초기화 및 기본 속성 설정
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = netifyRequest.method.rawValue
        urlRequest.timeoutInterval = netifyRequest.timeoutInterval ?? configuration.timeoutInterval // 요청별 설정 우선
        urlRequest.cachePolicy = netifyRequest.cachePolicy ?? configuration.cachePolicy // 요청별 설정 우선
        
        // 3. 헤더 준비 (클라이언트 기본 헤더 + 요청별 헤더)
        var headers = configuration.defaultHeaders // 기본 헤더로 시작
        netifyRequest.headers?.forEach { headers[$0.key] = $0.value } // 요청별 헤더가 기본 헤더 덮어씀
        
        // 4. 본문 및 Content-Type 헤더 준비
        let boundary = "Boundary-\(UUID().uuidString)" // 멀티파트용 경계 문자열
        
        if let multipartItems = netifyRequest.multipartData, !multipartItems.isEmpty {
            // 멀티파트 데이터 처리
            if netifyRequest.body != nil { // body와 multipartData 동시 제공 경고
                logger.logForOperation("경고: 'body'와 'multipartData'가 동시에 제공되었습니다. 'body'는 무시됩니다. (경로: \(netifyRequest.path))") // .error 대신 운영 로그
            }
            headers[HTTPHeaderField.contentType.rawValue] = "\(HTTPContentType.multipart.rawValue); boundary=\(boundary)"
            urlRequest.httpBody = buildMultipartBody(parts: multipartItems, boundary: boundary)
        } else if let bodyObject = netifyRequest.body {
            // 일반 본문 처리 (NetifyRequest의 contentType 사용)
            try encodeAndSetBody(&urlRequest, body: bodyObject, contentType: netifyRequest.contentType, headers: &headers)
        }
        // body가 nil이면 아무것도 하지 않음 (예: GET 요청)
        
        // 5. 최종 헤더 설정
        if !headers.isEmpty {
            urlRequest.allHTTPHeaderFields = headers
        }
        
        // 6. 인증 처리 (모든 헤더와 본문 설정 후 마지막에 적용)
        if netifyRequest.requiresAuthentication, let authProvider = configuration.authenticationProvider {
            do {
                urlRequest = try await authProvider.authenticate(request: urlRequest)
            } catch {
                throw mapAuthenticationError(error) // 인증 과정 자체의 에러 매핑
            }
        }
        return urlRequest
    }
    
    /// 경로와 쿼리 파라미터를 포함한 최종 URL을 빌드하는 헬퍼 함수.
    private func buildFinalURL<Request: NetifyRequest>(for netifyRequest: Request) throws -> URL {
        let baseURL = configuration.baseURL
        let path = netifyRequest.path // NetifyRequest에서 제공된 경로 (예: /users/{id})
        
        // URLPathBuilder를 사용하여 baseURL과 path 결합
        let initialURL = try URLPathBuilder.buildURL(baseURL: baseURL, path: path)
        
        // 쿼리 파라미터 추가 (있는 경우)
        guard let queryParams = netifyRequest.queryParams, !queryParams.isEmpty else {
            return initialURL // 쿼리 파라미터 없으면 바로 반환
        }
        
        guard var components = URLComponents(url: initialURL, resolvingAgainstBaseURL: false) else {
            throw NetworkRequestError.invalidRequest(reason: "URLComponents 생성 실패: \(initialURL)")
        }
        
        var queryItems = components.queryItems ?? []
        // NetifyRequest의 queryParams ([String: String])를 URLQueryItem 배열로 변환하여 추가
        queryItems.append(contentsOf: queryParams.map { URLQueryItem(name: $0.key, value: $0.value) })
        
        if !queryItems.isEmpty { components.queryItems = queryItems }
        
        guard let finalURL = components.url else {
            throw NetworkRequestError.invalidRequest(reason: "쿼리 파라미터를 포함한 최종 URL 생성 실패 (경로: \(path))")
        }
        return finalURL
    }
    
    /// ContentType에 따라 본문을 인코딩하고 요청에 설정하는 헬퍼 함수.
    /// Content-Type 헤더도 설정 (요청별 헤더에 명시적으로 없으면).
    private func encodeAndSetBody(_ urlRequest: inout URLRequest, body: Any, contentType: HTTPContentType, headers: inout HTTPHeaders) throws {
        do {
            switch contentType {
            case .json:
                guard let encodableBody = body as? Encodable else {
                    throw NetworkRequestError.invalidRequest(reason: "JSON Content-Type에 대해 요청 본문(\(type(of: body)))이 Encodable하지 않습니다.")
                }
                urlRequest.httpBody = try configuration.defaultEncoder.encode(encodableBody)
            case .urlEncoded:
                guard let paramsBody = body as? QueryParameters else { // [String: String] 타입이어야 함
                    throw NetworkRequestError.invalidRequest(reason: "URL Encoded Content-Type에 대해 요청 본문(\(type(of: body)))이 [String: String]이 아닙니다.")
                }
                urlRequest.httpBody = paramsBody.toUrlEncodedQueryString()?.data(using: .utf8)
            case .plainText:
                guard let stringBody = body as? String else {
                    throw NetworkRequestError.invalidRequest(reason: "Plain Text Content-Type에 대해 요청 본문(\(type(of: body)))이 String이 아닙니다.")
                }
                urlRequest.httpBody = stringBody.data(using: .utf8)
            case .xml:
                guard let stringBody = body as? String else { // XML도 보통 문자열로 처리
                    throw NetworkRequestError.invalidRequest(reason: "XML Content-Type에 대해 요청 본문(\(type(of: body)))이 String이 아닙니다.")
                }
                urlRequest.httpBody = stringBody.data(using: .utf8)
            case .octetStream: // 바이너리 데이터 직접 처리
                guard let dataBody = body as? Data else {
                    throw NetworkRequestError.invalidRequest(reason: "Octet Stream Content-Type에 대해 요청 본문(\(type(of: body)))이 Data가 아닙니다.")
                }
                urlRequest.httpBody = dataBody
            case .multipart:
                // 멀티파트는 이 함수를 호출하기 전에 buildURLRequest에서 별도로 처리됨
                throw NetworkRequestError.invalidRequest(reason: "Multipart Content-Type은 'multipartData' 속성을 통해 처리되어야 합니다.")
            }
            
            // Content-Type 헤더 설정 (요청별 헤더에 명시적으로 없거나, 현재 설정된 contentType과 다른 경우)
            if headers[HTTPHeaderField.contentType.rawValue] == nil {
                headers[HTTPHeaderField.contentType.rawValue] = contentType.rawValue
            } else if headers[HTTPHeaderField.contentType.rawValue] != contentType.rawValue && contentType != .multipart {
                // 멀티파트가 아닌데 명시적 헤더와 추론된 contentType이 다르면 경고 또는 로직 수정 필요
                // 여기서는 로깅만 하고, 요청자가 설정한 헤더를 우선시 할 수 있으나, 일관성을 위해 contentType.rawValue 사용
                logger.logForOperation("경고: 요청 헤더에 Content-Type ('\(headers[HTTPHeaderField.contentType.rawValue] ?? "")')이 명시되었으나, body 타입에 따른 Content-Type ('\(contentType.rawValue)')과 다를 수 있습니다. '\(contentType.rawValue)'를 사용합니다.")
                headers[HTTPHeaderField.contentType.rawValue] = contentType.rawValue
            }
            
            
        } catch let error as NetworkRequestError {
            throw error // 이미 NetifyError인 경우 다시 throw
        } catch { // 기타 인코딩 관련 에러 (JSONEncoder.encode 등)
            throw NetworkRequestError.encodingError(underlyingError: error)
        }
    }
    
    /// 멀티파트 요청 본문을 구성합니다.
    private func buildMultipartBody(parts: [MultipartData], boundary: String) -> Data {
        let body = NSMutableData()
        for part in parts {
            body.append(part.buildHttpBodyPart(boundary: boundary)) // 각 파트 데이터 추가
        }
        body.appendString("--\(boundary)--\r\n") // 전체 본문의 끝을 알리는 최종 경계
        return body as Data
    }
    
    /// `AuthenticationProvider.authenticate`에서 발생할 수 있는 에러를 매핑합니다.
    private func mapAuthenticationError(_ error: Error) -> NetworkRequestError {
        if let netifyError = error as? NetworkRequestError { // 인증 프로바이더가 NetifyError를 throw한 경우
            return netifyError
        } else { // 그 외 에러는 알 수 없는 인증 관련 문제로 처리
            logger.logForOperation("인증 프로바이더 실행 중 알 수 없는 에러 발생: \(error.localizedDescription)")
            return .unknownError(underlyingError: error)
        }
    }
}
