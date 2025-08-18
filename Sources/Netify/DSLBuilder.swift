import Foundation

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
public struct Path: NetifyModifier {
    let p: String; public init(_ p: String) { self.p = p }
    public func apply<R>(_ t: DeclarativeNetifyTask<R>) -> DeclarativeNetifyTask<R> { t.path(p) }
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

@available(iOS 15, macOS 12, *)
public enum NetifyDSL {
    public static func request<R: Decodable>(expecting: R.Type = R.self, @NetifyBuilder _ content: () -> [NetifyModifier]) -> DeclarativeNetifyTask<R> {
        content().reduce(DeclarativeNetifyTask<R>.new()) { acc, m in m.apply(acc) }
    }
}

@available(iOS 15, macOS 12, *)
public extension NetifyClient {
    func send<R: Decodable>(expecting: R.Type = R.self, @NetifyBuilder _ content: () -> [NetifyModifier]) async throws -> R {
        let task: DeclarativeNetifyTask<R> = NetifyDSL.request(expecting: R.self, content)
        return try await send(task)
    }
}

