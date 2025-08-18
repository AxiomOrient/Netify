import Foundation

// MARK: - Validation Infrastructure

@available(iOS 15, macOS 12, *)
public struct ValidationError: LocalizedError, Sendable {
    public let message: String
    public let field: String?
    
    public var errorDescription: String? { message }
    
    public init(_ message: String, field: String? = nil) {
        self.message = message
        self.field = field
    }
}

@available(iOS 15, macOS 12, *)
public protocol ValidatedNetifyModifier: NetifyModifier {
    /// Compile-time validation - returns validation errors if any
    func validate() -> [ValidationError]
}

@available(iOS 15, macOS 12, *)
public protocol NetifyModifier {
    func apply<R: Decodable>(_ task: DeclarativeNetifyTask<R>) -> DeclarativeNetifyTask<R>
}

@available(iOS 15, macOS 12, *)
@resultBuilder
public enum NetifyBuilder {
    public static func buildBlock(_ components: NetifyModifier...) -> [NetifyModifier] { components }
    public static func buildOptional(_ component: [NetifyModifier]?) -> [NetifyModifier] { component ?? [] }
    public static func buildEither(first: [NetifyModifier]) -> [NetifyModifier] { first }
    public static func buildEither(second: [NetifyModifier]) -> [NetifyModifier] { second }
    public static func buildArray(_ components: [[NetifyModifier]]) -> [NetifyModifier] { components.flatMap { $0 } }
}

// Primitive modifiers
@available(iOS 15, macOS 12, *)
public struct Method: NetifyModifier {
    let m: HTTPMethod; public init(_ m: HTTPMethod) { self.m = m }
    public func apply<R>(_ t: DeclarativeNetifyTask<R>) -> DeclarativeNetifyTask<R> { t.method(m) }
}
@available(iOS 15, macOS 12, *)
public struct Path: ValidatedNetifyModifier {
    let p: String
    private let requiredArguments: Set<String>
    
    public init(_ p: String) { 
        self.p = p
        self.requiredArguments = Self.extractTemplateArguments(from: p)
    }
    
    public func apply<R>(_ t: DeclarativeNetifyTask<R>) -> DeclarativeNetifyTask<R> { 
        t.path(p) 
    }
    
    public func validate() -> [ValidationError] {
        var errors: [ValidationError] = []
        
        // Check for malformed templates
        let openBraces = p.filter { $0 == "{" }.count
        let closeBraces = p.filter { $0 == "}" }.count
        if openBraces != closeBraces {
            errors.append(ValidationError("Malformed path template: unmatched braces", field: "path"))
        }
        
        // Check for empty template arguments
        if p.contains("{}") {
            errors.append(ValidationError("Empty template arguments found in path", field: "path"))
        }
        
        return errors
    }
    
    private static func extractTemplateArguments(from template: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: "\\{([^}]+)\\}", options: []) else {
            return []
        }
        
        let range = NSRange(template.startIndex..., in: template)
        let matches = regex.matches(in: template, options: [], range: range)
        
        return Set(matches.compactMap { match -> String? in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: template) else {
                return nil
            }
            return String(template[range])
        })
    }
    
    /// Create validated path with required arguments
    public func requiring(_ args: String...) -> ValidatedPathWithArgs {
        ValidatedPathWithArgs(template: p, requiredArgs: Set(args))
    }
}
@available(iOS 15, macOS 12, *)
public struct PathArgument: NetifyModifier {
    let k: String, v: CustomStringConvertible
    public init(_ k: String, _ v: CustomStringConvertible) { self.k = k; self.v = v }
    public func apply<R>(_ t: DeclarativeNetifyTask<R>) -> DeclarativeNetifyTask<R> { t.pathArgument(k, v) }
}
@available(iOS 15, macOS 12, *)
public struct Header: NetifyModifier {
    let n: String, v: String
    public init(_ n: String, _ v: String) { self.n = n; self.v = v }
    public func apply<R>(_ t: DeclarativeNetifyTask<R>) -> DeclarativeNetifyTask<R> { t.header(n, v) }
}
@available(iOS 15, macOS 12, *)
public struct Headers: NetifyModifier {
    let h: HTTPHeaders; public init(_ h: HTTPHeaders) { self.h = h }
    public func apply<R>(_ t: DeclarativeNetifyTask<R>) -> DeclarativeNetifyTask<R> { t.headers(h) }
}
@available(iOS 15, macOS 12, *)
public struct QueryParam: NetifyModifier {
    let n: String, v: CustomStringConvertible?
    public init(_ n: String, _ v: CustomStringConvertible?) { self.n = n; self.v = v }
    public func apply<R>(_ t: DeclarativeNetifyTask<R>) -> DeclarativeNetifyTask<R> { t.queryParam(n, v) }
}
@available(iOS 15, macOS 12, *)
public struct QueryParams: NetifyModifier {
    let q: QueryParameters; public init(_ q: QueryParameters) { self.q = q }
    public func apply<R>(_ t: DeclarativeNetifyTask<R>) -> DeclarativeNetifyTask<R> { t.queryParams(q) }
}

// Typed body modifiers
@available(iOS 15, macOS 12, *)
public struct BodyJSON<T: Encodable & Sendable>: NetifyModifier {
    let enc: T; public init(_ enc: T) { self.enc = enc }
    public func apply<R>(_ t: DeclarativeNetifyTask<R>) -> DeclarativeNetifyTask<R> { t.bodyJSON(enc) }
}
@available(iOS 15, macOS 12, *)
public struct BodyURLEncoded: NetifyModifier {
    let params: QueryParameters; public init(_ params: QueryParameters) { self.params = params }
    public func apply<R>(_ t: DeclarativeNetifyTask<R>) -> DeclarativeNetifyTask<R> { t.bodyURLEncoded(params) }
}
@available(iOS 15, macOS 12, *)
public struct BodyText: NetifyModifier {
    let text: String; public init(_ text: String) { self.text = text }
    public func apply<R>(_ t: DeclarativeNetifyTask<R>) -> DeclarativeNetifyTask<R> { t.bodyText(text) }
}
@available(iOS 15, macOS 12, *)
public struct BodyData: NetifyModifier {
    let data: Data, type: HTTPContentType
    public init(_ data: Data, _ type: HTTPContentType) { self.data = data; self.type = type }
    public func apply<R>(_ t: DeclarativeNetifyTask<R>) -> DeclarativeNetifyTask<R> { t.bodyData(data, contentType: type) }
}
@available(iOS 15, macOS 12, *)
public struct Multipart: NetifyModifier {
    let parts: [MultipartData]; public init(_ parts: [MultipartData]) { self.parts = parts }
    public func apply<R>(_ t: DeclarativeNetifyTask<R>) -> DeclarativeNetifyTask<R> { t.multipart(parts) }
}
@available(iOS 15, macOS 12, *)
public struct Timeout: NetifyModifier {
    let sec: TimeInterval; public init(_ sec: TimeInterval) { self.sec = sec }
    public func apply<R>(_ t: DeclarativeNetifyTask<R>) -> DeclarativeNetifyTask<R> { t.timeout(sec) }
}
@available(iOS 15, macOS 12, *)
public struct AuthRequired: NetifyModifier {
    let req: Bool; public init(_ req: Bool) { self.req = req }
    public func apply<R>(_ t: DeclarativeNetifyTask<R>) -> DeclarativeNetifyTask<R> { t.authentication(required: req) }
}

// MARK: - Enhanced Path Validation

@available(iOS 15, macOS 12, *)
public struct ValidatedPathWithArgs: ValidatedNetifyModifier {
    private let template: String
    private let requiredArgs: Set<String>
    private let providedArgs: Set<String>
    
    internal init(template: String, requiredArgs: Set<String>, providedArgs: Set<String> = []) {
        self.template = template
        self.requiredArgs = requiredArgs
        self.providedArgs = providedArgs
    }
    
    public func validate() -> [ValidationError] {
        var errors: [ValidationError] = []
        
        let missing = requiredArgs.subtracting(providedArgs)
        if !missing.isEmpty {
            errors.append(ValidationError(
                "Missing required path arguments: \(missing.sorted().joined(separator: ", "))",
                field: "pathArguments"
            ))
        }
        
        return errors
    }
    
    public func apply<R>(_ task: DeclarativeNetifyTask<R>) -> DeclarativeNetifyTask<R> {
        task.path(template)
    }
    
    /// Type-safe argument binding
    public func bind(_ key: String, _ value: CustomStringConvertible) -> ValidatedPathWithArgs {
        ValidatedPathWithArgs(
            template: template,
            requiredArgs: requiredArgs,
            providedArgs: providedArgs.union([key])
        )
    }
}

// MARK: - Enhanced Result Builder

@available(iOS 15, macOS 12, *)
@resultBuilder
public enum ValidatedNetifyBuilder {
    public static func buildBlock(_ components: NetifyModifier...) -> [NetifyModifier] {
        components
    }
    
    public static func buildOptional(_ component: [NetifyModifier]?) -> [NetifyModifier] {
        component ?? []
    }
    
    public static func buildEither(first: [NetifyModifier]) -> [NetifyModifier] {
        first
    }
    
    public static func buildEither(second: [NetifyModifier]) -> [NetifyModifier] {
        second
    }
    
    public static func buildArray(_ components: [[NetifyModifier]]) -> [NetifyModifier] {
        components.flatMap { $0 }
    }
    
    // Support for loops and complex conditionals
    public static func buildPartialBlock(first: NetifyModifier) -> [NetifyModifier] {
        [first]
    }
    
    public static func buildPartialBlock(accumulated: [NetifyModifier], next: NetifyModifier) -> [NetifyModifier] {
        accumulated + [next]
    }
    
    public static func buildPartialBlock(accumulated: [NetifyModifier], next: [NetifyModifier]) -> [NetifyModifier] {
        accumulated + next
    }
}

// MARK: - Conditional & Iterative Modifiers

@available(iOS 15, macOS 12, *)
public struct ConditionalModifier: NetifyModifier {
    private let condition: Bool
    private let modifier: NetifyModifier
    
    public init(if condition: Bool, then modifier: NetifyModifier) {
        self.condition = condition
        self.modifier = modifier
    }
    
    public func apply<R>(_ task: DeclarativeNetifyTask<R>) -> DeclarativeNetifyTask<R> {
        condition ? modifier.apply(task) : task
    }
}

@available(iOS 15, macOS 12, *)
public struct IterativeModifier: NetifyModifier {
    private let modifiers: [NetifyModifier]
    
    public init<S: Sequence>(forEach sequence: S, _ transform: (S.Element) -> NetifyModifier) {
        self.modifiers = sequence.map(transform)
    }
    
    public func apply<R>(_ task: DeclarativeNetifyTask<R>) -> DeclarativeNetifyTask<R> {
        modifiers.reduce(task) { $1.apply($0) }
    }
}

// MARK: - Enhanced DSL

@available(iOS 15, macOS 12, *)
public enum NetifyDSL {
    public static func request<R: Decodable>(expecting: R.Type = R.self, @NetifyBuilder _ content: () -> [NetifyModifier]) -> DeclarativeNetifyTask<R> {
        content().reduce(DeclarativeNetifyTask<R>.new()) { acc, m in m.apply(acc) }
    }
    
    /// Validated DSL request builder with compile-time checks
    public static func validatedRequest<R: Decodable>(
        expecting: R.Type = R.self,
        @ValidatedNetifyBuilder _ content: () -> [NetifyModifier]
    ) throws -> DeclarativeNetifyTask<R> {
        
        let modifiers = content()
        let errors = modifiers
            .compactMap { $0 as? ValidatedNetifyModifier }
            .flatMap { $0.validate() }
        
        guard errors.isEmpty else {
            let errorMessages = errors.map(\.message).joined(separator: "; ")
            throw NetworkRequestError.invalidRequest(reason: "Validation failed: \(errorMessages)")
        }
        
        return modifiers.reduce(DeclarativeNetifyTask<R>.new()) { task, modifier in
            modifier.apply(task)
        }
    }
}

@available(iOS 15, macOS 12, *)
public extension NetifyClient {
    func sendDSL<R: Decodable>(expecting: R.Type = R.self, @NetifyBuilder _ content: () -> [NetifyModifier]) async throws -> R {
        let task: DeclarativeNetifyTask<R> = NetifyDSL.request(expecting: R.self, content)
        return try await send(task)
    }
}

