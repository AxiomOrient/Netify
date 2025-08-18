import Foundation

@available(iOS 15, macOS 12, *)
public enum RequestBody: Sendable {
    case json(AnyEncodable)
    case urlEncoded(QueryParameters)
    case text(String)
    case xml(String)
    case data(Data, HTTPContentType)
}

/// Optional protocol: requests can provide a typed RequestBody
@available(iOS 15, macOS 12, *)
public protocol NetifyRequestBodyProviding {
    var requestBody: RequestBody? { get }
}
