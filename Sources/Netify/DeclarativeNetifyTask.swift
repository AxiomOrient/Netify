import Foundation

@available(iOS 15, macOS 12, *)
final class _Box<T> {
    var value: T
    init(_ v: T) { self.value = v }
}

@available(iOS 15, macOS 12, *)
public struct DeclarativeNetifyTask<ReturnType: Decodable> {
    // 기존: private var configuration: DeclarativeNetifyTaskConfiguration<ReturnType>
    // 변경: CoW 박스 사용
    private var _box: _Box<DeclarativeNetifyTaskConfiguration<ReturnType>>
    
    // Mutating CoW accessor for write paths (modifiers)
    private var configuration: DeclarativeNetifyTaskConfiguration<ReturnType> {
        mutating get {
            if !isKnownUniquelyReferenced(&_box) {
                _box = _Box(_box.value) // copy-on-write
            }
            return _box.value
        }
        set { _box.value = newValue }
    }
    // Non-mutating accessor for read-only paths (NetifyRequest conformance)
    private var readConfiguration: DeclarativeNetifyTaskConfiguration<ReturnType> { _box.value }
    
    internal init() {
        self._box = _Box(DeclarativeNetifyTaskConfiguration<ReturnType>())
    }
    
    internal static func new() -> DeclarativeNetifyTask<ReturnType> {
        DeclarativeNetifyTask<ReturnType>()
    }
    
    // DRY: Copy-on-Write 캡슐화 헬퍼
    private func withConfig(_ update: (inout DeclarativeNetifyTaskConfiguration<ReturnType>) -> Void) -> Self {
        var s = self
        var cfg = s.configuration
        update(&cfg)
        s.configuration = cfg
        return s
    }
    
    // ===== 기존 modifier 들은 아래와 같이 configuration 경유 =====
    public func method(_ method: HTTPMethod) -> Self { withConfig { $0.method = method } }
    public func path(_ pathTemplate: String) -> Self { withConfig { $0.pathTemplate = pathTemplate } }
    public func pathArgument(_ key: String, _ value: CustomStringConvertible) -> Self { withConfig { $0.pathArguments[key] = value } }
    public func pathArguments(_ args: [String: CustomStringConvertible]) -> Self { withConfig { $0.pathArguments.merge(args) { _, new in new } } }
    public func header(_ name: String, _ value: String) -> Self { withConfig { $0.headers[name] = value } }
    public func headers(_ headersToAdd: HTTPHeaders) -> Self { withConfig { $0.headers.merge(headersToAdd) { _, new in new } } }
    public func queryParam(_ name: String, _ value: CustomStringConvertible?) -> Self {
        guard let value = value else { return self }
        return withConfig { $0.queryParams[name] = value.description }
    }
    public func queryParams(_ paramsToAdd: QueryParameters) -> Self { withConfig { $0.queryParams.merge(paramsToAdd) { _, new in new } } }
    // Phase 3 typed body modifiers (Sendable payloads)
    public func bodyJSON<T: Encodable & Sendable>(_ value: T) -> Self {
        var s = self; var cfg = s.configuration
        cfg.requestBody = .json(AnyEncodable(value))
        cfg.explicitContentType = .json
        cfg.multipartItems = nil
        s.configuration = cfg
        return s
    }
    public func bodyURLEncoded(_ params: QueryParameters) -> Self { withConfig { $0.requestBody = .urlEncoded(params); $0.explicitContentType = .urlEncoded; $0.multipartItems = nil } }
    public func bodyText(_ text: String) -> Self { withConfig { $0.requestBody = .text(text); $0.explicitContentType = .plainText; $0.multipartItems = nil } }
    public func bodyData(_ data: Data, contentType: HTTPContentType) -> Self { withConfig { $0.requestBody = .data(data, contentType); $0.explicitContentType = contentType; $0.multipartItems = nil } }
    /// Unified body entry
    public func body(_ body: RequestBody) -> Self {
        withConfig {
            $0.requestBody = body; $0.multipartItems = nil
            switch body {
            case .json: $0.explicitContentType = .json
            case .urlEncoded: $0.explicitContentType = .urlEncoded
            case .text: $0.explicitContentType = .plainText
            case .xml: $0.explicitContentType = .xml
            case .data(_, let type): $0.explicitContentType = type
            }
        }
    }
    public func multipart(_ parts: [MultipartData]) -> Self { withConfig { $0.multipartItems = parts.isEmpty ? nil : parts; $0.explicitContentType = HTTPContentType.multipart } }
    public func contentType(_ type: HTTPContentType) -> Self { withConfig { $0.explicitContentType = type } }
    public func customDecoder(_ decoder: JSONDecoder) -> Self { withConfig { $0.customDecoder = decoder } }
    public func cachePolicy(_ policy: URLRequest.CachePolicy) -> Self { withConfig { $0.cachePolicy = policy } }
    public func timeout(_ interval: TimeInterval) -> Self { withConfig { $0.timeoutInterval = interval } }
    public func authentication(required: Bool) -> Self { withConfig { $0.requiresAuth = required } }
}

// ===== NetifyRequest 적합성 + 안전한 경로 치환/인코딩 =====
@available(iOS 15, macOS 12, *)
extension DeclarativeNetifyTask: NetifyRequest {
    public var path: String {
        func allowedSet() -> CharacterSet {
            var set = CharacterSet.urlPathAllowed
            set.remove(charactersIn: "/") // 슬래시도 인코딩
            return set
        }
        func encode(_ v: CustomStringConvertible) -> String {
            v.description.addingPercentEncoding(withAllowedCharacters: allowedSet()) ?? v.description
        }
        let resolved = readConfiguration.pathArguments.reduce(readConfiguration.pathTemplate) { cur, arg in
            cur.replacingOccurrences(of: "{\(arg.key)}", with: encode(arg.value))
        }
        return resolved
    }
    public var method: HTTPMethod { readConfiguration.method }
    public var contentType: HTTPContentType { readConfiguration.resolveContentType() }
    public var queryParams: QueryParameters? { readConfiguration.queryParams.isEmpty ? nil : readConfiguration.queryParams }
        public var headers: HTTPHeaders? { readConfiguration.headers.isEmpty ? nil : readConfiguration.headers }
    public var multipartData: [MultipartData]? { readConfiguration.multipartItems }
    public var decoder: JSONDecoder? { readConfiguration.customDecoder }
    public var cachePolicy: URLRequest.CachePolicy? { readConfiguration.cachePolicy }
    public var timeoutInterval: TimeInterval? { readConfiguration.timeoutInterval }
    public var requiresAuthentication: Bool { readConfiguration.requiresAuth }
}

@available(iOS 15, macOS 12, *)
extension DeclarativeNetifyTask: NetifyRequestBodyProviding {
    public var requestBody: RequestBody? { readConfiguration.requestBody }
}
