import Foundation

// MARK: - Compile-Time Validation DSL

@available(iOS 15, macOS 12, *)
public protocol ValidatedNetifyModifier: NetifyModifier {
    /// Compile-time validation - returns validation errors if any
    func validate() -> [ValidationError]
}

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

// MARK: - Enhanced Path with Template Validation

@available(iOS 15, macOS 12, *)
public struct ValidatedPath: ValidatedNetifyModifier {
    private let template: String
    private let requiredArguments: Set<String>
    
    public init(_ template: String) {
        self.template = template
        self.requiredArguments = Self.extractTemplateArguments(from: template)
    }
    
    public func validate() -> [ValidationError] {
        var errors: [ValidationError] = []
        
        // Check for malformed templates
        if template.contains("{") != template.contains("}") {
            errors.append(ValidationError("Malformed path template: unmatched braces", field: "path"))
        }
        
        // Check for empty template arguments
        let emptyArgs = template.matches(of: /\{\s*\}/).count
        if emptyArgs > 0 {
            errors.append(ValidationError("Empty template arguments found in path", field: "path"))
        }
        
        return errors
    }
    
    public func apply<R>(_ task: DeclarativeNetifyTask<R>) -> DeclarativeNetifyTask<R> {
        task.path(template)
    }
    
    private static func extractTemplateArguments(from template: String) -> Set<String> {
        let matches = template.matches(of: /\{([^}]+)\}/)
        return Set(matches.map { String($0.output.1) })
    }
    
    /// Compile-time check for required arguments
    public func requiring(_ args: String...) -> ValidatedPathWithArgs {
        ValidatedPathWithArgs(template: template, requiredArgs: Set(args))
    }
}

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

// MARK: - Conditional DSL Builders

@available(iOS 15, macOS 12, *)
@resultBuilder
public enum ConditionalNetifyBuilder {
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
    
    // New: Support for loops and complex conditionals
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

// MARK: - Enhanced Request Builder with Validation

@available(iOS 15, macOS 12, *)
public struct ValidatedRequestBuilder<ReturnType: Decodable> {
    private let modifiers: [NetifyModifier]
    private let validationErrors: [ValidationError]
    
    private init(modifiers: [NetifyModifier] = [], validationErrors: [ValidationError] = []) {
        self.modifiers = modifiers
        self.validationErrors = validationErrors
    }
    
    public static func build(@ConditionalNetifyBuilder _ content: () -> [NetifyModifier]) -> ValidatedRequestBuilder<ReturnType> {
        let modifiers = content()
        let errors = modifiers
            .compactMap { $0 as? ValidatedNetifyModifier }
            .flatMap { $0.validate() }
        
        return ValidatedRequestBuilder(modifiers: modifiers, validationErrors: errors)
    }
    
    /// Compile-time validation check
    public func validated() throws -> DeclarativeNetifyTask<ReturnType> {
        guard validationErrors.isEmpty else {
            let errorMessages = validationErrors.map(\.message).joined(separator: "; ")
            throw NetworkRequestError.invalidRequest(reason: "Validation failed: \(errorMessages)")
        }
        
        return modifiers.reduce(DeclarativeNetifyTask<ReturnType>.new()) { task, modifier in
            modifier.apply(task)
        }
    }
    
    /// Runtime-validated build (for backward compatibility)
    public func build() -> DeclarativeNetifyTask<ReturnType> {
        return modifiers.reduce(DeclarativeNetifyTask<ReturnType>.new()) { task, modifier in
            modifier.apply(task)
        }
    }
    
    /// Get validation errors for debugging
    public var errors: [ValidationError] { validationErrors }
    public var isValid: Bool { validationErrors.isEmpty }
}

// MARK: - Enhanced DSL Usage Examples

@available(iOS 15, macOS 12, *)
public enum ImprovedNetifyDSL {
    
    /// Type-safe validated request builder
    public static func validatedRequest<R: Decodable>(
        expecting: R.Type = R.self,
        @ConditionalNetifyBuilder _ content: () -> [NetifyModifier]
    ) throws -> DeclarativeNetifyTask<R> {
        return try ValidatedRequestBuilder<R>.build(content).validated()
    }
    
    /// Runtime-validated request builder (backward compatible)
    public static func request<R: Decodable>(
        expecting: R.Type = R.self,
        @ConditionalNetifyBuilder _ content: () -> [NetifyModifier]
    ) -> DeclarativeNetifyTask<R> {
        return ValidatedRequestBuilder<R>.build(content).build()
    }
}

// MARK: - Advanced Conditional Modifiers

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

// MARK: - Usage Examples

/*
// ✅ Compile-time validated requests
let validatedTask = try ImprovedNetifyDSL.validatedRequest(expecting: User.self) {
    Method(.get)
    ValidatedPath("/users/{id}")
        .requiring("id")
        .bind("id", userID)
    
    if includeTracing {
        Header("X-Trace-ID", UUID().uuidString)
    }
    
    // Complex conditionals now supported
    IterativeModifier(forEach: customHeaders) { header in
        Header(header.name, header.value)
    }
}

// ✅ Advanced conditional logic
let dynamicTask = ImprovedNetifyDSL.request(expecting: SearchResults.self) {
    Method(.get)
    Path("/search")
    
    QueryParam("q", searchTerm)
    
    // Conditional parameters
    ConditionalModifier(if: useAdvancedSearch) {
        QueryParam("advanced", "true")
    }
    
    // Iterative parameters
    IterativeModifier(forEach: filters) { filter in
        QueryParam(filter.key, filter.value)
    }
    
    // Nested conditions
    if userPreferences.enablePersonalization {
        Header("X-User-ID", userID)
        QueryParam("personalize", "true")
        
        if userPreferences.locationEnabled {
            Header("X-Location", currentLocation.description)
        }
    }
}
*/