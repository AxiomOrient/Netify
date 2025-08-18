import Foundation

// MARK: - Enhanced Error Context

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

// MARK: - Enhanced Error Builder

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

// MARK: - Enhanced Error Extensions

@available(iOS 15, macOS 12, *)
extension NetworkRequestError {
    /// Enhanced debugging information with full context
    public func enhancedDebugDescription(with context: ErrorContext? = nil) -> String {
        var desc = localizedDescription
        
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
        case .decodingError(let underlyingError, let data):
            desc += "\n\n🔧 Decoding Details:"
            desc += "\n  Underlying Error: \(underlyingError)"
            if let data = data, let rawString = String(data: data, encoding: .utf8) {
                let preview = rawString.count > 500 ? "\(rawString.prefix(500))..." : rawString
                desc += "\n  Raw Response: \(preview)"
            }
        case .encodingError(let underlyingError):
            desc += "\n\n🔧 Encoding Details:"
            desc += "\n  Underlying Error: \(underlyingError)"
        default:
            break
        }
        
        return desc
    }
    
    /// Create enhanced error with type information preserved
    public static func decodingErrorWithType<T>(
        from underlyingError: Error,
        expectedType: T.Type,
        data: Data?
    ) -> NetworkRequestError {
        // Store type information in error description for debugging
        let enhancedError = NSError(
            domain: "Netify.Decoding",
            code: -1,
            userInfo: [
                NSLocalizedDescriptionKey: "Failed to decode \(String(describing: expectedType)): \(underlyingError.localizedDescription)",
                "expectedType": String(describing: expectedType),
                "underlyingError": underlyingError
            ]
        )
        return .decodingError(underlyingError: enhancedError, data: data)
    }
    
    /// Create enhanced encoding error with type information
    public static func encodingErrorWithType<T>(
        from underlyingError: Error,
        attemptedType: T.Type
    ) -> NetworkRequestError {
        let enhancedError = NSError(
            domain: "Netify.Encoding",
            code: -1,
            userInfo: [
                NSLocalizedDescriptionKey: "Failed to encode \(String(describing: attemptedType)): \(underlyingError.localizedDescription)",
                "attemptedType": String(describing: attemptedType),
                "underlyingError": underlyingError
            ]
        )
        return .encodingError(underlyingError: enhancedError)
    }
}

// MARK: - Debugging Helpers

@available(iOS 15, macOS 12, *)
public extension NetifyClient {
    /// Create error context from current request state
    func createErrorContext<Request: NetifyRequest>(
        for request: Request,
        urlRequest: URLRequest,
        response: URLResponse? = nil,
        responseData: Data? = nil,
        attemptNumber: Int = 1,
        totalAttempts: Int = 1
    ) -> ErrorContext {
        
        var builder = ErrorContextBuilder()
            .request(urlRequest)
            .attempt(attemptNumber, total: totalAttempts)
        
        if let httpResponse = response as? HTTPURLResponse {
            builder = builder.response(httpResponse, data: responseData)
        }
        
        return builder.build()
    }
}