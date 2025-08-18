import Foundation

@available(iOS 15, macOS 12, *)
actor VaryIndex {
    private var index: [String: [String]] = [:]
    func set(_ names: [String], for baseKey: String) { index[baseKey] = names.map { $0.lowercased() } }
    func get(for baseKey: String) -> [String] { index[baseKey] ?? [] }
}

