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
        "cookie",
        "set-cookie",
        "x-api-key",
        "api-key", // 일반적인 API 키 헤더 추가
        "client-secret",
        "access-token",
        "refresh-token",
        "password",
        "secret",
        "token" // 일반적인 토큰 헤더 추가
    ]
    
    /// 로깅 시 요약할 최대 데이터 길이 (바이트)
    static let maxLogSummaryLength = 1024
    
    /// 기본 재시도 전 대기 시간 (나노초)
    static let defaultRetryDelayNanoseconds: UInt64 = 1_000_000_000  // 1초
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
    public let metrics: NetworkMetrics
    public let cache: NetifyCachePolicy
    public let responseCache: ResponseCache?
    public let sensitiveHeaderKeys: Set<String>
    public let plugins: [NetifyPlugin]
    
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
        metrics: NetworkMetrics = NoopMetrics(),
        cache: NetifyCachePolicy = .none,
        responseCache: ResponseCache? = nil,
        sensitiveHeaderKeys: Set<String>? = nil,
        plugins: [NetifyPlugin] = []
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
        self.metrics = metrics
        self.cache = cache
        self.responseCache = responseCache
        self.sensitiveHeaderKeys = sensitiveHeaderKeys ?? NetifyInternalConstants.sensitiveHeaderKeys
        self.plugins = plugins
        
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
}

/// `os.Logger`를 사용하는 `NetifyLogging`의 기본 구현체입니다.
@available(iOS 15, macOS 12, *)
public struct DefaultNetifyLogger: NetifyLogging {
    public let logLevel: NetworkingLogLevel
    private let logger: Logger // os.Logger 인스턴스
    private let sensitiveHeaderKeys: Set<String>
    
    /// `DefaultNetifyLogger`를 초기화합니다.
    /// - Parameters:
    ///   - logLevel: 로깅 상세 수준.
    ///   - subsystem: `os.Logger`에 사용할 서브시스템 문자열. 기본값은 앱 번들 ID.
    ///   - category: `os.Logger`에 사용할 카테고리 문자열. 기본값은 "Netify".
    public init(
        logLevel: NetworkingLogLevel,
        subsystem: String = Bundle.main.bundleIdentifier ?? "com.unknown.netify", // 기본 서브시스템 개선
        category: String = "Netify",
        sensitiveHeaderKeys: Set<String>? = nil
    ) {
        self.logLevel = logLevel
        self.logger = Logger(subsystem: subsystem, category: category)
        self.sensitiveHeaderKeys = sensitiveHeaderKeys ?? NetifyInternalConstants.sensitiveHeaderKeys
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
            logMessage += "\n    cURL: \(request.toCurlCommand(masking: sensitiveHeaderKeys))"
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
                // 헤더를 [String: String]으로 안전 변환
                let headers: HTTPHeaders = httpResponse.allHeaderFields.reduce(into: [:]) {
                    dict, kv in
                    dict[String(describing: kv.key)] = String(describing: kv.value)
                }
                if !headers.isEmpty {
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
    /// OSLogType의 rawValue에 의존하지 않고, Netify의 로깅 레벨 의미론으로 게이팅합니다.
    private func shouldLog(for targetLevel: OSLogType) -> Bool {
        switch self.logLevel {
        case .off:   return false
        case .error: return targetLevel == .fault || targetLevel == .error
        case .info:  return targetLevel == .fault || targetLevel == .error || targetLevel == .info
        case .debug: return true
        }
    }
    
    /// 민감한 정보를 마스킹 처리한 헤더를 반환합니다.
    private func maskSensitiveHeaders(_ headers: HTTPHeaders) -> HTTPHeaders {
        var maskedHeaders = headers
        for (key, _) in headers where sensitiveHeaderKeys.contains(key.lowercased()) {
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
    /// 400번대 기타 클라이언트 에러. 연관값으로 상태 코드(Int)와 응답 데이터(옵셔널 `Data`)를 가집니다.
    case clientError(statusCode: Int, data: Data?, retryAfter: TimeInterval?)
    /// 500번대 서버 에러. 연관값으로 상태 코드(Int)와 응답 데이터(옵셔널 `Data`)를 가집니다.
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
        case .badRequest(let d), .unauthorized(let d), .forbidden(let d), .notFound(let d),
                .clientError(_, let d, _), .serverError(_, let d, _):
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
        case .clientError(let code, _, _): return code == 429
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
        case (.clientError(let lc, _, _), .clientError(let rc, _, _)): return lc == rc // 코드만 비교
        case (.serverError(let lc, _, _), .serverError(let rc, _, _)): return lc == rc // 코드만 비교
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
            if let le, let re {
                let lns = le as NSError
                let rns = re as NSError
                return lns.domain == rns.domain && lns.code == rns.code
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
    /// 선언적·타입세이프 본문 (권장)
    var requestBody: RequestBody? { get }
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
    public var requestBody: RequestBody? { nil }
    public var headers: HTTPHeaders? { nil }
    public var multipartData: [MultipartData]? { nil }
    public var decoder: JSONDecoder? { nil }
    public var cachePolicy: URLRequest.CachePolicy? { nil }
    public var timeoutInterval: TimeInterval? { nil }
    public var requiresAuthentication: Bool { true } // 대부분의 요청은 인증이 필요하다고 가정
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
        guard let base = URL(string: baseURL) else {
            throw NetworkRequestError.invalidRequest(reason: "잘못된 기본 URL 문자열입니다: \(baseURL)")
        }
        let append = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return base.appendingPathComponent(append)
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
    public func toCurlCommand(masking sensitive: Set<String>? = nil) -> String {
        guard let url = self.url else { return "# Netify: cURL 명령어 생성 실패 (유효하지 않은 URL)" }
        let mask = sensitive ?? NetifyInternalConstants.sensitiveHeaderKeys
        var command = [#"curl -v "\#(url.absoluteString)""#] // -v 옵션으로 상세 출력
        
        // HTTP 메소드 추가 (GET이 아니면)
        if let httpMethod = self.httpMethod, httpMethod.uppercased() != "GET" {
            command.append("-X \(httpMethod.uppercased())")
        }
        
        // 헤더 추가 (민감 정보 마스킹)
        self.allHTTPHeaderFields?.sorted(by: { $0.key < $1.key }).forEach { key, value in
            let displayValue = mask.contains(key.lowercased()) ? "<masked>" : value
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

// MARK: - Netify Client (Core Logic)

/// 실제 네트워크 요청 실행 및 관리를 담당하는 클라이언트입니다. `NetifyClientProtocol`을 준수합니다.
@available(iOS 15, macOS 12, *)
public final class NetifyClient: NetifyClientProtocol {
    public let configuration: NetifyConfiguration
    private let networkSession: NetworkSessionProtocol // URLSession 대신 프로토콜 사용
    private let logger: NetifyLogging
    private let requestBuilder: RequestBuilder // 내부 RequestBuilder 사용
    private let varyIndex = VaryIndex()
    
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
        self.logger = logger ?? DefaultNetifyLogger(logLevel: configuration.logLevel, sensitiveHeaderKeys: configuration.sensitiveHeaderKeys) // 주입받거나 기본 로거 사용
        self.requestBuilder = RequestBuilder(configuration: configuration, logger: self.logger) // 빌더에 로거 전달
        
        self.logger.log(message: "NetifyClient 초기화 완료. BaseURL: \(configuration.baseURL), LogLevel: \(configuration.logLevel)", level: .info)
    }
    
    /// 특정 `NetifyRequest`를 비동기적으로 보내고 응답을 처리합니다.
    /// 재시도 및 인증 토큰 갱신 로직을 포함합니다.
    public func send<Request: NetifyRequest>(_ request: Request) async throws -> Request.ReturnType {
        try await sendRequestWithRetry(request, currentRetryCount: 0, authRetryCount: 0)
    }
    
    /// 재시도 및 인증 갱신 로직을 포함하여 요청을 처리하는 내부 메소드입니다.
    private func sendRequestWithRetry<Request: NetifyRequest>(
        _ request: Request, currentRetryCount: Int, authRetryCount: Int
    ) async throws -> Request.ReturnType {
        let attemptStarted = Date()
        var urlRequest: URLRequest = try await buildAndLogRequest(from: request)
        
        // ---- Simple Cache (GET만 기본 대상) ----
        let useCache = configuration.responseCache != nil && request.method == .get
        let baseKeyAndEffective: (base: String, key: String)? = {
            guard useCache, let url = urlRequest.url else { return nil }
            let base = CacheKey.make(method: request.method.rawValue, url: url)
            return (base, base)
        }()
        var cacheKey: String? = baseKeyAndEffective?.key
        if let pair = baseKeyAndEffective {
            let names = await varyIndex.get(for: pair.base)
            if let url = urlRequest.url, !names.isEmpty {
                let varyParts: [String] = names.map { name in
                    let v = urlRequest.value(forHTTPHeaderField: name) ?? ""
                    return "\(name)=\(v)"
                }
                cacheKey = CacheKey.make(method: request.method.rawValue, url: url, varyHeaders: varyParts)
            }
        }
        var cached: (status: Int, headers: HTTPHeaders, data: Data, storedAt: Date)?
        if let key = cacheKey, useCache {
            if let cache = configuration.responseCache {
                cached = await cache.read(key: key)
            }
            if let cached, case .ttl(let seconds) = configuration.cache {
                if Date().timeIntervalSince(cached.storedAt) < seconds {
                    logger.log(message: "TTL cache hit for \(key)", level: .info)
                    let result = try self.decodeSuccess(data: cached.data, for: request)
                    if let url = urlRequest.url,
                       let resp = HTTPURLResponse(url: url, statusCode: cached.status, httpVersion: nil, headerFields: cached.headers) {
                        configuration.plugins.forEach { $0.didReceive(.success((cached.data, resp)), for: urlRequest) }
                    }
                    configuration.metrics.recordRequest(
                        path: request.path, method: request.method.rawValue,
                        duration: Date().timeIntervalSince(attemptStarted),
                        status: 200, retryCount: currentRetryCount
                    )
                    return result
                }
            }
            if let cached, case .etag = configuration.cache {
                if let etag = cached.headers["etag"] {
                    var hdrs = urlRequest.allHTTPHeaderFields ?? [:]
                    hdrs["If-None-Match"] = etag
                    urlRequest.allHTTPHeaderFields = hdrs
                }
            }
            if let cached, case .etagOrTtl(let seconds) = configuration.cache {
                if Date().timeIntervalSince(cached.storedAt) < seconds {
                    logger.log(message: "TTL(etagOrTtl) cache hit for \(key)", level: .info)
                    let result = try self.decodeSuccess(data: cached.data, for: request)
                    if let url = urlRequest.url,
                       let resp = HTTPURLResponse(url: url, statusCode: cached.status, httpVersion: nil, headerFields: cached.headers) {
                        configuration.plugins.forEach { $0.didReceive(.success((cached.data, resp)), for: urlRequest) }
                    }
                    configuration.metrics.recordRequest(
                        path: request.path, method: request.method.rawValue,
                        duration: Date().timeIntervalSince(attemptStarted),
                        status: 200, retryCount: currentRetryCount
                    )
                    return result
                }
                if let etag = cached.headers["etag"] {
                    var hdrs = urlRequest.allHTTPHeaderFields ?? [:]
                    hdrs["If-None-Match"] = etag
                    urlRequest.allHTTPHeaderFields = hdrs
                }
            }
        }
        
        // Plugins: willSend
        configuration.plugins.forEach { $0.willSend(urlRequest) }
        do {
            let (data, response) = try await performDataTask(for: urlRequest)
            logger.log(response: response, data: data, level: .debug)
            
            if let http = response as? HTTPURLResponse,
               http.statusCode == 304,
               let key = cacheKey, let hit = cached {
                logger.log(message: "ETag 304 -> cache return for \(key)", level: .info)
                let result = try self.decodeSuccess(data: hit.data, for: request)
                configuration.plugins.forEach { $0.didReceive(.success((hit.data, response)), for: urlRequest) }
                configuration.metrics.recordRequest(
                    path: request.path, method: request.method.rawValue,
                    duration: Date().timeIntervalSince(attemptStarted),
                    status: 304, retryCount: currentRetryCount
                )
                return result
            }
            
            let value: Request.ReturnType = try handleResponse(response: response, data: data, for: request)
            configuration.plugins.forEach { $0.didReceive(.success((data, response)), for: urlRequest) }
            if let http = response as? HTTPURLResponse {
                configuration.metrics.recordRequest(
                    path: request.path, method: request.method.rawValue,
                    duration: Date().timeIntervalSince(attemptStarted),
                    status: http.statusCode, retryCount: currentRetryCount
                )
            } else {
                configuration.metrics.recordRequest(
                    path: request.path, method: request.method.rawValue,
                    duration: Date().timeIntervalSince(attemptStarted),
                    status: nil, retryCount: currentRetryCount
                )
            }
            
            if let http = response as? HTTPURLResponse,
               (200...299).contains(http.statusCode),
               let key = cacheKey, useCache, let cache = configuration.responseCache {
                let headers: HTTPHeaders = requestBuilder.normalizedHeaders(http)
                var writeKey = key
                if let base = baseKeyAndEffective?.base,
                   let varyValue = headers["vary"], !varyValue.isEmpty,
                   let url = urlRequest.url {
                    let names = varyValue
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                        .filter { !$0.isEmpty }
                    if !names.isEmpty {
                        await varyIndex.set(names, for: base)
                        let varyParts: [String] = names.map { name in
                            let v = urlRequest.value(forHTTPHeaderField: name) ?? ""
                            return "\(name)=\(v)"
                        }
                        writeKey = CacheKey.make(method: request.method.rawValue, url: url, varyHeaders: varyParts)
                    }
                }
                switch configuration.cache {
                case .none: break
                case .ttl, .etag, .etagOrTtl:
                    await cache.write(key: writeKey, status: http.statusCode, headers: headers, data: data, storedAt: Date())
                }
            }
            return value
        } catch let error {
            let netifyError = mapToNetifyError(error)
            logger.log(error: netifyError, level: .error)
            configuration.plugins.forEach { $0.didReceive(.failure(netifyError), for: urlRequest) }
            
            if request.requiresAuthentication,
               let authProvider = configuration.authenticationProvider,
               authProvider.isAuthenticationExpired(from: netifyError) {
                guard authRetryCount < 1 else { throw netifyError }
                logger.log(message: "인증 만료 감지. 토큰 갱신 시도...", level: .info)
                let refreshSuccess = await attemptAuthRefresh(using: authProvider)
                
                if refreshSuccess {
                    logger.log(message: "인증 토큰 갱신 성공. 원본 요청 재시도...", level: .info)
                    return try await sendRequestWithRetry(request, currentRetryCount: currentRetryCount, authRetryCount: authRetryCount + 1)
                } else {
                    logger.log(message: "인증 토큰 갱신 실패 또는 미지원. 원본 에러(\(netifyError.localizedDescription)) 발생.", level: .error)
                    throw netifyError
                }
            }
            
            if netifyError.isRetryable && currentRetryCount < configuration.maxRetryCount {
                let retryAfterSeconds: TimeInterval? = {
                    if case let .clientError(code, _, ra) = netifyError, code == 429 { return ra }
                    if case let .serverError(_, _, ra) = netifyError { return ra }
                    return nil
                }()
                let delayNs = computeRetryDelayNanoseconds(attempt: currentRetryCount + 1, retryAfter: retryAfterSeconds)
                logger.log(message: "재시도 가능 에러 발생. 재시도 (\(currentRetryCount + 1)/\(configuration.maxRetryCount)), 대기 (\(Double(delayNs)/1_000_000_000))s. 에러: \(netifyError.localizedDescription)", level: .info)
                try? await Task.sleep(nanoseconds: delayNs)
                try Task.checkCancellation()
                return try await sendRequestWithRetry(request, currentRetryCount: currentRetryCount + 1, authRetryCount: authRetryCount)
            }
            configuration.metrics.recordError(path: request.path, method: request.method.rawValue, error: netifyError)
            throw netifyError
        }
    }

    // MARK: - Small helpers (complexity reduction)
    private func buildAndLogRequest<Request: NetifyRequest>(from request: Request) async throws -> URLRequest {
        do {
            let urlRequest = try await requestBuilder.buildURLRequest(from: request)
            logger.log(request: urlRequest, level: .debug)
            return urlRequest
        } catch {
            let netifyError = mapToNetifyError(error)
            logger.log(error: netifyError, level: .error)
            throw netifyError
        }
    }
    
    private func performDataTask(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await networkSession.data(for: request, delegate: nil)
    }
    
    private func decodeSuccess<Request: NetifyRequest>(data: Data, for request: Request) throws -> Request.ReturnType {
        if data.isEmpty {
            if Request.ReturnType.self == EmptyResponse.self, let empty = EmptyResponse() as? Request.ReturnType {
                return empty
            } else if Request.ReturnType.self == Data.self, let d = data as? Request.ReturnType {
                return d
            } else {
                throw NetworkRequestError.decodingError(
                    underlyingError: NSError(domain: "Netify.Decode", code: -1, userInfo: [NSLocalizedDescriptionKey: "빈 응답 본문"]),
                    data: data
                )
            }
        } else {
            let decoder = request.decoder ?? configuration.defaultDecoder
            do {
                return try decoder.decode(Request.ReturnType.self, from: data)
            } catch {
                throw NetworkRequestError.decodingError(underlyingError: error, data: data)
            }
        }
    }
    
    private func handleResponse<Request: NetifyRequest>(response: URLResponse, data: Data, for netifyRequest: Request) throws -> Request.ReturnType {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkRequestError.invalidResponse(response: response)
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let headers: HTTPHeaders = httpResponse.allHeaderFields.reduce(into: [:]) { dict, kv in
                dict[String(describing: kv.key)] = String(describing: kv.value)
            }
            throw mapStatusCodeToError(statusCode: httpResponse.statusCode, data: data, headers: headers)
        }
        
        return try decodeSuccess(data: data, for: netifyRequest)
    }
    
    /// 인증 토큰 갱신을 시도하는 헬퍼 함수입니다.
    private func attemptAuthRefresh(using authProvider: AuthenticationProvider) async -> Bool {
        do {
            logger.log(message: "authProvider.refreshAuthentication() 호출 중...", level: .debug)
            let success = try await authProvider.refreshAuthentication()
            logger.log(message: "인증 토큰 갱신 시도 완료. 성공: \(success)", level: .info)
            return success
        } catch {
            let refreshError = mapToNetifyError(error) // 갱신 중 발생한 에러 매핑
            logger.log(error: refreshError, level: .error)
            return false // 갱신 실패
        }
    }
    
    /// 다양한 `Error` 타입을 일관된 `NetworkRequestError`로 매핑합니다.
    private func mapToNetifyError(_ error: Error) -> NetworkRequestError {
        switch error {
        case let netifyError as NetworkRequestError: return netifyError // 이미 NetifyError인 경우
        case let urlError as URLError:
            switch urlError.code {
            case .cancelled: return .cancelled
            case .timedOut: return .timedOut
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
                    .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .resourceUnavailable,
                    .internationalRoamingOff, .secureConnectionFailed, .serverCertificateHasBadDate,
                    .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
                return .noInternetConnection // 다양한 연결 관련 문제 그룹화
            default: return .urlSessionFailed(underlyingError: urlError)
            }
        case let encodingError as EncodingError: return .encodingError(underlyingError: encodingError)
        case let decodingError as DecodingError:
            // handleResponse에서 이미 data와 함께 .decodingError로 래핑하므로, 여기서 data는 nil일 수 있음
            return .decodingError(underlyingError: decodingError, data: nil)
        case is CancellationError: return .cancelled // Task 취소 에러
        default: return .unknownError(underlyingError: error)
        }
    }
    
    /// Retry-After(초) 우선, 없으면 지수(1,2,4...) + 지터(0~0.5초) 백오프
    private func computeRetryDelayNanoseconds(attempt: Int, retryAfter: TimeInterval?) -> UInt64 {
        if let ra = retryAfter, ra > 0 {
            return UInt64(ra * 1_000_000_000)
        }
        let base = pow(2.0, Double(max(1, attempt))) // 1,2,4,...
        let jitter = Double.random(in: 0...0.5)
        return UInt64((base + jitter) * 1_000_000_000)
    }
    
    /// HTTP 상태 코드(2xx 범위 외)를 적절한 `NetworkRequestError`로 매핑합니다.
    private func mapStatusCodeToError(statusCode: Int, data: Data?, headers: HTTPHeaders?) -> NetworkRequestError {
        func parseRetryAfter(_ headers: HTTPHeaders?) -> TimeInterval? {
            guard let raw = headers?["Retry-After"] ?? headers?["retry-after"] else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let seconds = TimeInterval(trimmed) { return seconds }
            // HTTP-date (IMF-fixdate) 형식 시도
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.timeZone = TimeZone(secondsFromGMT: 0)
            fmt.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
            if let date = fmt.date(from: trimmed) {
                return max(0, date.timeIntervalSinceNow)
            }
            return nil
        }
        let retryAfter = parseRetryAfter(headers)
        switch statusCode {
        case 400: return .badRequest(data: data)
        case 401: return .unauthorized(data: data)
        case 403: return .forbidden(data: data)
        case 404: return .notFound(data: data)
        case 405...499: return .clientError(statusCode: statusCode, data: data, retryAfter: retryAfter) // 기타 4xx
        case 500...599: return .serverError(statusCode: statusCode, data: data, retryAfter: retryAfter) // 5xx
        default: // 예상치 못한 상태 코드
            logger.log(message: "처리되지 않은 HTTP 상태 코드 수신: \(statusCode)", level: .info)
            return .unknownError(underlyingError: NSError(domain: "Netify.StatusCodeMapping", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "처리되지 않은 HTTP 상태 코드: \(statusCode)"]))
        }
    }
}

// MARK: - Request Builder (Internal Helper)

/// `URLRequest` 생성을 담당하는 내부 헬퍼 클래스/구조체입니다.
/// `NetifyConfiguration`과 `NetifyLogging`을 주입받아 사용합니다.
@available(iOS 15, macOS 12, *)
internal struct RequestBuilder {
    let configuration: NetifyConfiguration
    let logger: NetifyLogging
    
    /// `NetifyRequest`로부터 `URLRequest`를 빌드합니다. (내부 서브 스텝으로 분리)
    func buildURLRequest<Request: NetifyRequest>(from netifyRequest: Request) async throws -> URLRequest {
        // 1) URL 구성
        let url = try buildFinalURL(for: netifyRequest)
        // 2) 베이스 요청 + 헤더 병합
        var urlRequest = makeBaseURLRequest(url: url, request: netifyRequest)
        var headers = makeMergedHeaders(for: netifyRequest)
        
        // 기본 Accept 헤더 설정 (요청자가 지정하지 않은 경우)
        if headers[HTTPHeaderField.acceptType.rawValue] == nil {
            if Request.ReturnType.self == Data.self || Request.ReturnType.self == EmptyResponse.self {
                headers[HTTPHeaderField.acceptType.rawValue] = "*/*"
            } else {
                headers[HTTPHeaderField.acceptType.rawValue] = HTTPContentType.json.rawValue
            }
        }
        
        // 4. 본문 및 Content-Type 헤더 준비
        let boundary = "Boundary-\(UUID().uuidString)" // 멀티파트용 경계 문자열
        
        if let multipartItems = netifyRequest.multipartData, !multipartItems.isEmpty {
            // 멀티파트 데이터 처리
            headers[HTTPHeaderField.contentType.rawValue] = "\(HTTPContentType.multipart.rawValue); boundary=\(boundary)"
            urlRequest.httpBody = buildMultipartBody(parts: multipartItems, boundary: boundary)
        } else if let rb = netifyRequest.requestBody {
            // 타입세이프 RequestBody 우선
            try encodeAndSetRequestBody(&urlRequest, requestBody: rb, headers: &headers)
        }
        // body가 nil이면 아무것도 하지 않음 (예: GET 요청)
        
        // 5. 최종 헤더 설정
        if !headers.isEmpty { urlRequest.allHTTPHeaderFields = headers }
        
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
        
    private func makeBaseURLRequest<Request: NetifyRequest>(url: URL, request: Request) -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = request.method.rawValue
        r.timeoutInterval = request.timeoutInterval ?? configuration.timeoutInterval
        r.cachePolicy = request.cachePolicy ?? configuration.cachePolicy
        return r
    }

    private func makeMergedHeaders<Request: NetifyRequest>(for request: Request) -> HTTPHeaders {
        var h = configuration.defaultHeaders
        request.headers?.forEach { h[$0.key] = $0.value }
        return h
    }
    
    /// 경로와 쿼리 파라미터를 포함한 최종 URL을 빌드하는 헬퍼 함수.
    private func buildFinalURL<Request: NetifyRequest>(for netifyRequest: Request) throws -> URL {
        let baseURL = configuration.baseURL
        let path = netifyRequest.path // NetifyRequest에서 제공된 경로 (예: /users/{id})
        // 미치환 템플릿 가드
        if path.contains("{") || path.contains("}") {
            throw NetworkRequestError.invalidRequest(reason: "경로 템플릿이 완전히 치환되지 않았습니다: \(path)")
        }
        
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
    private func encodeAndSetRequestBody(_ urlRequest: inout URLRequest,
                                         requestBody: RequestBody,
                                         headers: inout HTTPHeaders) throws {
        switch requestBody {
        case .json(let boxed):
            urlRequest.httpBody = try configuration.defaultEncoder.encode(boxed)
            if headers[HTTPHeaderField.contentType.rawValue] == nil {
                headers[HTTPHeaderField.contentType.rawValue] = HTTPContentType.json.rawValue
            }
        case .urlEncoded(let params):
            urlRequest.httpBody = params.toUrlEncodedQueryString()?.data(using: .utf8)
            if headers[HTTPHeaderField.contentType.rawValue] == nil {
                headers[HTTPHeaderField.contentType.rawValue] = HTTPContentType.urlEncoded.rawValue
            }
        case .text(let str):
            urlRequest.httpBody = str.data(using: .utf8)
            headers[HTTPHeaderField.contentType.rawValue] = HTTPContentType.plainText.rawValue
        case .xml(let str):
            urlRequest.httpBody = str.data(using: .utf8)
            headers[HTTPHeaderField.contentType.rawValue] = HTTPContentType.xml.rawValue
        case .data(let data, let type):
            urlRequest.httpBody = data
            headers[HTTPHeaderField.contentType.rawValue] = type.rawValue
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

    /// HTTPURLResponse → 소문자 키 헤더로 정규화
    fileprivate func normalizedHeaders(_ http: HTTPURLResponse) -> HTTPHeaders {
        http.allHeaderFields.reduce(into: [:]) { d, kv in
            d[String(describing: kv.key).lowercased()] = String(describing: kv.value)
        }
    }
    
    /// `AuthenticationProvider.authenticate`에서 발생할 수 있는 에러를 매핑합니다.
    private func mapAuthenticationError(_ error: Error) -> NetworkRequestError {
        if let netifyError = error as? NetworkRequestError { // 인증 프로바이더가 NetifyError를 throw한 경우
            return netifyError
        } else { // 그 외 에러는 알 수 없는 인증 관련 문제로 처리
            logger.log(message: "인증 프로바이더 실행 중 알 수 없는 에러 발생: \(error.localizedDescription)", level: .error)
            return .unknownError(underlyingError: error)
        }
    }
}
