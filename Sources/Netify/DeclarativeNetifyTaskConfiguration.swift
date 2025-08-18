import Foundation

@available(iOS 15, macOS 12, *)
internal struct DeclarativeNetifyTaskConfiguration<ReturnType: Decodable> {
    var pathTemplate: String = ""
    var method: HTTPMethod = .get
    var headers: HTTPHeaders = [:]
    var queryParams: QueryParameters = [:]
        var requestBody: RequestBody? = nil
    var explicitContentType: HTTPContentType? = nil
    var multipartItems: [MultipartData]? = nil
    var customDecoder: JSONDecoder? = nil
    var cachePolicy: URLRequest.CachePolicy? = nil
    var timeoutInterval: TimeInterval? = nil
    var requiresAuth: Bool = true
    var pathArguments: [String: CustomStringConvertible] = [:]

    /// 최종 Content-Type 결정
    func resolveContentType() -> HTTPContentType {
        if let explicit = explicitContentType { return explicit }
        if let items = multipartItems, !items.isEmpty { return .multipart }
        if let requestBody = requestBody {
            switch requestBody {
            case .json: return .json
            case .urlEncoded: return .urlEncoded
            case .text: return .plainText
            case .xml: return .xml
            case .data(_, let type): return type
            }
        }
        return .json
    }
}
