import Foundation

@available(iOS 15, macOS 12, *)
/// 제네릭 JSONEncoder가 Encodable & Sendable 값을 타입 소거하여 인코딩할 수 있도록 하는 래퍼.
public struct AnyEncodable: Encodable, Sendable {
    private let _encode: @Sendable (Encoder) throws -> Void

    public init<T: Encodable & Sendable>(_ value: T) {
        self._encode = { encoder in try value.encode(to: encoder) }
    }

    public func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
