import Foundation

// MARK: - Request Processing Pipeline

@available(iOS 15, macOS 12, *)
internal protocol RequestProcessor {
    func process<Request: NetifyRequest>(
        _ request: Request,
        context: RequestContext
    ) async throws -> Request.ReturnType
}

@available(iOS 15, macOS 12, *)
internal struct RequestContext {
    let client: NetifyClient
    let attempt: Int
    let authRetryCount: Int
    let startTime: Date
    
    func withRetry(attempt: Int, authRetry: Int) -> RequestContext {
        RequestContext(
            client: client,
            attempt: attempt,
            authRetryCount: authRetry,
            startTime: startTime
        )
    }
}

// MARK: - Cache Processor

@available(iOS 15, macOS 12, *)
internal struct CacheProcessor: RequestProcessor {
    private let nextProcessor: RequestProcessor?
    
    init(next: RequestProcessor? = nil) {
        self.nextProcessor = next
    }
    
    func process<Request: NetifyRequest>(
        _ request: Request,
        context: RequestContext
    ) async throws -> Request.ReturnType {
        
        // Cache lookup and validation
        if let cachedResult = try await handleCacheRead(request: request, context: context) {
            return cachedResult
        }
        
        // Proceed to next processor
        guard let next = nextProcessor else {
            throw NetworkRequestError.invalidRequest(reason: "No network processor configured")
        }
        
        let result = try await next.process(request, context: context)
        
        // Cache write
        try await handleCacheWrite(request: request, result: result, context: context)
        
        return result
    }
    
    private func handleCacheRead<Request: NetifyRequest>(
        request: Request,
        context: RequestContext
    ) async throws -> Request.ReturnType? {
        
        let config = context.client.configuration
        guard let responseCache = config.responseCache,
              request.method == .get else { return nil }
        
        let urlRequest = try await context.client.requestBuilder.buildURLRequest(from: request)
        guard let url = urlRequest.url else { return nil }
        
        let cacheManager = CacheManager(
            cache: responseCache,
            varyIndex: context.client.varyIndex,
            policy: config.cache
        )
        
        return try await cacheManager.readFromCache(
            request: request,
            urlRequest: urlRequest,
            url: url
        )
    }
    
    private func handleCacheWrite<Request: NetifyRequest>(
        request: Request,
        result: Request.ReturnType,
        context: RequestContext
    ) async throws {
        // Cache write implementation
        // ... (separated from main flow)
    }
}

// MARK: - Network Processor

@available(iOS 15, macOS 12, *)
internal struct NetworkProcessor: RequestProcessor {
    private let nextProcessor: RequestProcessor?
    
    init(next: RequestProcessor? = nil) {
        self.nextProcessor = next
    }
    
    func process<Request: NetifyRequest>(
        _ request: Request,
        context: RequestContext
    ) async throws -> Request.ReturnType {
        
        let urlRequest = try await context.client.requestBuilder.buildURLRequest(from: request)
        
        // Plugin: willSend
        context.client.configuration.plugins.forEach { $0.willSend(urlRequest) }
        
        do {
            let (data, response) = try await context.client.networkSession.data(for: urlRequest, delegate: nil)
            context.client.logger.log(response: response, data: data, level: .debug)
            
            let result = try context.client.handleResponse(response: response, data: data, for: request)
            
            // Plugin: didReceive (success)
            context.client.configuration.plugins.forEach { 
                $0.didReceive(.success((data, response)), for: urlRequest) 
            }
            
            // Metrics: success
            context.client.recordSuccessMetrics(
                request: request,
                response: response,
                context: context
            )
            
            return result
            
        } catch {
            let netifyError = context.client.mapToNetifyError(error)
            context.client.logger.log(error: netifyError, level: .error)
            
            // Plugin: didReceive (failure)
            context.client.configuration.plugins.forEach {
                $0.didReceive(.failure(netifyError), for: urlRequest)
            }
            
            throw netifyError
        }
    }
}

// MARK: - Auth Retry Processor

@available(iOS 15, macOS 12, *)
internal struct AuthRetryProcessor: RequestProcessor {
    private let coreProcessor: RequestProcessor
    
    init(coreProcessor: RequestProcessor) {
        self.coreProcessor = coreProcessor
    }
    
    func process<Request: NetifyRequest>(
        _ request: Request,
        context: RequestContext
    ) async throws -> Request.ReturnType {
        
        do {
            return try await coreProcessor.process(request, context: context)
        } catch let netifyError as NetworkRequestError {
            
            // Check for auth retry eligibility
            if shouldRetryForAuth(request: request, error: netifyError, context: context) {
                return try await retryWithAuthRefresh(request: request, context: context)
            }
            
            throw netifyError
        }
    }
    
    private func shouldRetryForAuth<Request: NetifyRequest>(
        request: Request,
        error: NetworkRequestError,
        context: RequestContext
    ) -> Bool {
        return request.requiresAuthentication &&
               context.client.configuration.authenticationProvider != nil &&
               context.authRetryCount < 1 &&
               isAuthError(error)
    }
    
    private func isAuthError(_ error: NetworkRequestError) -> Bool {
        if case .unauthorized = error { return true }
        return context.client.configuration.authenticationProvider?.isAuthenticationExpired(from: error) ?? false
    }
    
    private func retryWithAuthRefresh<Request: NetifyRequest>(
        request: Request,
        context: RequestContext
    ) async throws -> Request.ReturnType {
        
        guard let authProvider = context.client.configuration.authenticationProvider else {
            throw NetworkRequestError.invalidRequest(reason: "No auth provider configured")
        }
        
        context.client.logger.log(message: "Authentication expired. Attempting token refresh...", level: .info)
        
        let refreshSuccess = await context.client.attemptAuthRefresh(using: authProvider)
        
        if refreshSuccess {
            context.client.logger.log(message: "Token refresh successful. Retrying original request...", level: .info)
            let newContext = context.withRetry(attempt: context.attempt, authRetry: context.authRetryCount + 1)
            return try await coreProcessor.process(request, context: newContext)
        } else {
            context.client.logger.log(message: "Token refresh failed. Returning original error.", level: .error)
            throw NetworkRequestError.unauthorized(data: nil)
        }
    }
}

// MARK: - Standard Retry Processor

@available(iOS 15, macOS 12, *)
internal struct StandardRetryProcessor: RequestProcessor {
    private let coreProcessor: RequestProcessor
    
    init(coreProcessor: RequestProcessor) {
        self.coreProcessor = coreProcessor
    }
    
    func process<Request: NetifyRequest>(
        _ request: Request,
        context: RequestContext
    ) async throws -> Request.ReturnType {
        
        do {
            return try await coreProcessor.process(request, context: context)
        } catch let netifyError as NetworkRequestError {
            
            if shouldRetryForError(error: netifyError, context: context) {
                return try await retryWithBackoff(request: request, error: netifyError, context: context)
            }
            
            // Record error metrics before throwing
            context.client.configuration.metrics.recordError(
                path: request.path,
                method: request.method.rawValue,
                error: netifyError
            )
            
            throw netifyError
        }
    }
    
    private func shouldRetryForError(error: NetworkRequestError, context: RequestContext) -> Bool {
        return error.isRetryable && context.attempt < context.client.configuration.maxRetryCount
    }
    
    private func retryWithBackoff<Request: NetifyRequest>(
        request: Request,
        error: NetworkRequestError,
        context: RequestContext
    ) async throws -> Request.ReturnType {
        
        let retryAfter = extractRetryAfter(from: error)
        let delayNs = context.client.computeRetryDelayNanoseconds(
            attempt: context.attempt + 1,
            retryAfter: retryAfter
        )
        
        context.client.logger.log(
            message: "Retryable error occurred. Retry (\(context.attempt + 1)/\(context.client.configuration.maxRetryCount)), delay: \(Double(delayNs)/1_000_000_000)s. Error: \(error.localizedDescription)",
            level: .info
        )
        
        try? await Task.sleep(nanoseconds: delayNs)
        try Task.checkCancellation()
        
        let newContext = context.withRetry(attempt: context.attempt + 1, authRetry: context.authRetryCount)
        return try await coreProcessor.process(request, context: newContext)
    }
    
    private func extractRetryAfter(from error: NetworkRequestError) -> TimeInterval? {
        switch error {
        case .clientError(_, _, let retryAfter), .serverError(_, _, let retryAfter):
            return retryAfter
        default:
            return nil
        }
    }
}

// MARK: - Cache Manager (Separated Responsibility)

@available(iOS 15, macOS 12, *)
internal struct CacheManager {
    private let cache: ResponseCache
    private let varyIndex: VaryIndex
    private let policy: NetifyCachePolicy
    
    init(cache: ResponseCache, varyIndex: VaryIndex, policy: NetifyCachePolicy) {
        self.cache = cache
        self.varyIndex = varyIndex
        self.policy = policy
    }
    
    func readFromCache<Request: NetifyRequest>(
        request: Request,
        urlRequest: URLRequest,
        url: URL
    ) async throws -> Request.ReturnType? {
        
        let baseKey = CacheKey.make(method: request.method.rawValue, url: url)
        let varyHeaders = await varyIndex.get(for: baseKey)
        
        let effectiveKey = buildEffectiveKey(
            baseKey: baseKey,
            varyHeaders: varyHeaders,
            urlRequest: urlRequest,
            url: url
        )
        
        guard let cached = await cache.read(key: effectiveKey) else { return nil }
        
        switch policy {
        case .none:
            return nil
        case .ttl(let seconds):
            return try handleTTLCache(cached: cached, seconds: seconds, request: request)
        case .etag:
            return try await handleETagCache(cached: cached, request: request, urlRequest: urlRequest)
        case .etagOrTtl(let seconds):
            return try await handleHybridCache(cached: cached, seconds: seconds, request: request, urlRequest: urlRequest)
        }
    }
    
    // Private helper methods for different cache strategies
    // ... (implementation details)
}

// MARK: - Refactored NetifyClient

@available(iOS 15, macOS 12, *)
extension NetifyClient {
    
    /// Simplified main entry point - now just 10 lines!
    public func send<Request: NetifyRequest>(_ request: Request) async throws -> Request.ReturnType {
        let context = RequestContext(
            client: self,
            attempt: 0,
            authRetryCount: 0,
            startTime: Date()
        )
        
        let pipeline = buildProcessingPipeline()
        return try await pipeline.process(request, context: context)
    }
    
    /// Build the processing pipeline based on configuration
    private func buildProcessingPipeline() -> RequestProcessor {
        let networkProcessor = NetworkProcessor()
        let cacheProcessor = CacheProcessor(next: networkProcessor)
        let authRetryProcessor = AuthRetryProcessor(coreProcessor: cacheProcessor)
        let standardRetryProcessor = StandardRetryProcessor(coreProcessor: authRetryProcessor)
        
        return standardRetryProcessor
    }
}