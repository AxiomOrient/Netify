import Foundation

// MARK: - Enhanced Error Context Preservation

@available(iOS 15, macOS 12, *)
public struct ErrorContext: Sendable {
    public let requestURL: URL?
    public let requestMethod: String?
    public let requestHeaders: [String: String]?
    public let responseHeaders: [String: String]?
    public let statusCode: Int?
    public let requestBody: Data?
    public let responseBody: Data?
    public let timestamp: Date
    public let attemptNumber: Int
    public let totalAttempts: Int
    
    public init(
        requestURL: URL? = nil,
        requestMethod: String? = nil,
        requestHeaders: [String: String]? = nil,
        responseHeaders: [String: String]? = nil,
        statusCode: Int? = nil,
        requestBody: Data? = nil,
        responseBody: Data? = nil,
        timestamp: Date = Date(),
        attemptNumber: Int = 1,
        totalAttempts: Int = 1
    ) {
        self.requestURL = requestURL
        self.requestMethod = requestMethod
        self.requestHeaders = requestHeaders
        self.responseHeaders = responseHeaders
        self.statusCode = statusCode
        self.requestBody = requestBody
        self.responseBody = responseBody
        self.timestamp = timestamp
        self.attemptNumber = attemptNumber
        self.totalAttempts = totalAttempts
    }
}

// MARK: - Enhanced Network Request Error

@available(iOS 15, macOS 12, *)
public enum EnhancedNetworkRequestError: LocalizedError, Equatable {
    // Basic errors with enhanced context
    case invalidRequest(reason: String, context: ErrorContext?)
    case invalidResponse(response: URLResponse?, context: ErrorContext?)
    case badRequest(data: Data?, context: ErrorContext?)
    case unauthorized(data: Data?, context: ErrorContext?)
    case forbidden(data: Data?, context: ErrorContext?)
    case notFound(data: Data?, context: ErrorContext?)
    case clientError(statusCode: Int, data: Data?, retryAfter: TimeInterval?, context: ErrorContext?)
    case serverError(statusCode: Int, data: Data?, retryAfter: TimeInterval?, context: ErrorContext?)
    
    // Enhanced decoding error with original type information
    case decodingError(
        underlyingError: Error,
        expectedType: String, // Preserve original type name
        data: Data?,
        context: ErrorContext?
    )
    
    // Enhanced encoding error with type information
    case encodingError(
        underlyingError: Error,
        attemptedType: String, // Preserve attempted type name
        context: ErrorContext?
    )
    
    // Network errors with context
    case urlSessionFailed(underlyingError: Error, context: ErrorContext?)
    case unknownError(underlyingError: Error?, context: ErrorContext?)
    case cancelled(context: ErrorContext?)
    case timedOut(context: ErrorContext?)
    case noInternetConnection(context: ErrorContext?)
    
    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let reason, _): return "Invalid request: \(reason)"
        case .invalidResponse(_, _): return "Invalid response (non-HTTP or malformed)"
        case .badRequest(_, _): return "Bad Request (400)"
        case .unauthorized(_, _): return "Unauthorized (401)"
        case .forbidden(_, _): return "Forbidden (403)"
        case .notFound(_, _): return "Not Found (404)"
        case .clientError(let code, _, _, _): return "Client Error (\(code))"
        case .serverError(let code, _, _, _): return "Server Error (\(code))"
        case .decodingError(_, let type, _, _): return "Failed to decode response as \(type)"
        case .encodingError(_, let type, _): return "Failed to encode \(type) as request body"
        case .urlSessionFailed(let error, _): return "Network error: \(error.localizedDescription)"
        case .unknownError(let error, _): return "Unknown error: \(error?.localizedDescription ?? "No details")"
        case .cancelled(_): return "Request cancelled"
        case .timedOut(_): return "Request timed out"
        case .noInternetConnection(_): return "No internet connection"
        }
    }
    
    // Enhanced debugging information
    public var enhancedDebugDescription: String {
        var desc = errorDescription ?? "Unknown error"
        
        let context = self.context
        if let ctx = context {
            desc += "\n\n🔍 Request Context:"
            if let url = ctx.requestURL {
                desc += "\n  URL: \(url.absoluteString)"
            }
            if let method = ctx.requestMethod {
                desc += "\n  Method: \(method)"
            }
            if ctx.attemptNumber > 1 {
                desc += "\n  Attempt: \(ctx.attemptNumber)/\(ctx.totalAttempts)"
            }
            if let statusCode = ctx.statusCode {
                desc += "\n  Status Code: \(statusCode)"
            }
            if let headers = ctx.responseHeaders, !headers.isEmpty {
                desc += "\n  Response Headers: \(headers)"
            }
            desc += "\n  Timestamp: \(ctx.timestamp.ISO8601Format())"
        }
        
        // Add specific error details
        switch self {
        case .decodingError(let underlyingError, let type, let data, _):
            desc += "\n\n🔧 Decoding Details:"
            desc += "\n  Expected Type: \(type)"
            desc += "\n  Underlying Error: \(underlyingError)"
            if let data = data, let rawString = String(data: data, encoding: .utf8) {
                let preview = rawString.count > 500 ? "\(rawString.prefix(500))..." : rawString
                desc += "\n  Raw Response: \(preview)"
            }
        case .encodingError(let underlyingError, let type, _):
            desc += "\n\n🔧 Encoding Details:"
            desc += "\n  Attempted Type: \(type)"
            desc += "\n  Underlying Error: \(underlyingError)"
        default:
            break
        }
        
        return desc
    }
    
    // Context accessor
    public var context: ErrorContext? {
        switch self {
        case .invalidRequest(_, let context): return context
        case .invalidResponse(_, let context): return context
        case .badRequest(_, let context): return context
        case .unauthorized(_, let context): return context
        case .forbidden(_, let context): return context
        case .notFound(_, let context): return context
        case .clientError(_, _, _, let context): return context
        case .serverError(_, _, _, let context): return context
        case .decodingError(_, _, _, let context): return context
        case .encodingError(_, _, let context): return context
        case .urlSessionFailed(_, let context): return context
        case .unknownError(_, let context): return context
        case .cancelled(let context): return context
        case .timedOut(let context): return context
        case .noInternetConnection(let context): return context
        }
    }
    
    // Preserve retryability logic
    public var isRetryable: Bool {
        switch self {
        case .serverError: return true
        case .clientError(let code, _, _, _): return code == 429
        case .timedOut, .noInternetConnection: return true
        case .urlSessionFailed(let error, _):
            if let urlError = error as? URLError {
                return [
                    .timedOut, .networkConnectionLost, .notConnectedToInternet,
                    .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
                    .resourceUnavailable, .internationalRoamingOff
                ].contains(urlError.code)
            }
            return false
        default: return false
        }
    }
    
    // Equatable implementation (context excluded for comparison)
    public static func == (lhs: EnhancedNetworkRequestError, rhs: EnhancedNetworkRequestError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidRequest(let l, _), .invalidRequest(let r, _)): return l == r
        case (.invalidResponse, .invalidResponse): return true
        case (.badRequest, .badRequest): return true
        case (.unauthorized, .unauthorized): return true
        case (.forbidden, .forbidden): return true
        case (.notFound, .notFound): return true
        case (.clientError(let lc, _, _, _), .clientError(let rc, _, _, _)): return lc == rc
        case (.serverError(let lc, _, _, _), .serverError(let rc, _, _, _)): return lc == rc
        case (.decodingError(let lErr, let lType, _, _), .decodingError(let rErr, let rType, _, _)):
            return lType == rType && (lErr as NSError) == (rErr as NSError)
        case (.encodingError(let lErr, let lType, _), .encodingError(let rErr, let rType, _)):
            return lType == rType && (lErr as NSError) == (rErr as NSError)
        case (.urlSessionFailed(let lErr, _), .urlSessionFailed(let rErr, _)):
            return (lErr as NSError) == (rErr as NSError)
        case (.unknownError(let le, _), .unknownError(let re, _)):
            if let le = le, let re = re {
                return (le as NSError) == (re as NSError)
            }
            return le == nil && re == nil
        case (.cancelled, .cancelled): return true
        case (.timedOut, .timedOut): return true
        case (.noInternetConnection, .noInternetConnection): return true
        default: return false
        }
    }
}

// MARK: - Type-Safe Error Builder

@available(iOS 15, macOS 12, *)
public struct ErrorContextBuilder {
    private var context: ErrorContext
    
    public init() {
        self.context = ErrorContext()
    }
    
    public func request(_ request: URLRequest) -> ErrorContextBuilder {
        var builder = self
        builder.context = ErrorContext(
            requestURL: request.url,
            requestMethod: request.httpMethod,
            requestHeaders: request.allHTTPHeaderFields,
            responseHeaders: context.responseHeaders,
            statusCode: context.statusCode,
            requestBody: request.httpBody,
            responseBody: context.responseBody,
            timestamp: context.timestamp,
            attemptNumber: context.attemptNumber,
            totalAttempts: context.totalAttempts
        )
        return builder
    }
    
    public func response(_ response: HTTPURLResponse, data: Data?) -> ErrorContextBuilder {
        var builder = self
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { dict, pair in
            dict[String(describing: pair.key)] = String(describing: pair.value)
        }
        
        builder.context = ErrorContext(
            requestURL: context.requestURL,
            requestMethod: context.requestMethod,
            requestHeaders: context.requestHeaders,
            responseHeaders: headers,
            statusCode: response.statusCode,
            requestBody: context.requestBody,
            responseBody: data,
            timestamp: context.timestamp,
            attemptNumber: context.attemptNumber,
            totalAttempts: context.totalAttempts
        )
        return builder
    }
    
    public func attempt(_ current: Int, total: Int) -> ErrorContextBuilder {
        var builder = self
        builder.context = ErrorContext(
            requestURL: context.requestURL,
            requestMethod: context.requestMethod,
            requestHeaders: context.requestHeaders,
            responseHeaders: context.responseHeaders,
            statusCode: context.statusCode,
            requestBody: context.requestBody,
            responseBody: context.responseBody,
            timestamp: context.timestamp,
            attemptNumber: current,
            totalAttempts: total
        )
        return builder
    }
    
    public func build() -> ErrorContext {
        context
    }
}

// MARK: - Enhanced Error Factory

@available(iOS 15, macOS 12, *)
public struct EnhancedErrorFactory {
    
    public static func decodingError<T>(
        from underlyingError: Error,
        expectedType: T.Type,
        data: Data?,
        context: ErrorContext?
    ) -> EnhancedNetworkRequestError {
        return .decodingError(
            underlyingError: underlyingError,
            expectedType: String(describing: expectedType),
            data: data,
            context: context
        )
    }
    
    public static func encodingError<T>(
        from underlyingError: Error,
        attemptedType: T.Type,
        context: ErrorContext?
    ) -> EnhancedNetworkRequestError {
        return .encodingError(
            underlyingError: underlyingError,
            attemptedType: String(describing: attemptedType),
            context: context
        )
    }
    
    public static func httpError(
        statusCode: Int,
        data: Data?,
        headers: [String: String]?,
        context: ErrorContext?
    ) -> EnhancedNetworkRequestError {
        let retryAfter = parseRetryAfter(from: headers)
        
        switch statusCode {
        case 400: return .badRequest(data: data, context: context)
        case 401: return .unauthorized(data: data, context: context)
        case 403: return .forbidden(data: data, context: context)
        case 404: return .notFound(data: data, context: context)
        case 405...499: return .clientError(statusCode: statusCode, data: data, retryAfter: retryAfter, context: context)
        case 500...599: return .serverError(statusCode: statusCode, data: data, retryAfter: retryAfter, context: context)
        default: return .unknownError(underlyingError: nil, context: context)
        }
    }
    
    private static func parseRetryAfter(from headers: [String: String]?) -> TimeInterval? {
        guard let raw = headers?["Retry-After"] ?? headers?["retry-after"] else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let seconds = TimeInterval(trimmed) { return seconds }
        
        // Try HTTP-date format
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        
        if let date = fmt.date(from: trimmed) {
            return max(0, date.timeIntervalSinceNow)
        }
        
        return nil
    }
}

// Usage Example:
/*
// Enhanced error creation with full context preservation
let contextBuilder = ErrorContextBuilder()
    .request(urlRequest)
    .response(httpResponse, data: responseData)
    .attempt(2, total: 3)

let enhancedError = EnhancedErrorFactory.decodingError(
    from: originalDecodingError,
    expectedType: User.self,
    data: responseData,
    context: contextBuilder.build()
)

// Rich debugging information
print(enhancedError.enhancedDebugDescription)
*/