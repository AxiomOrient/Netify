import Foundation

@available(iOS 15, macOS 12, *)
public enum Netify {
    /// 제네릭 선언적 태스크 시작점
    public static func task<R: Decodable>(expecting: R.Type = R.self) -> DeclarativeNetifyTask<R> {
        DeclarativeNetifyTask<R>.new()
    }
    /// 편의 메서드 (HTTP Method 프리셋)
    public static func get<R: Decodable>(expecting: R.Type = R.self) -> DeclarativeNetifyTask<R> {
        DeclarativeNetifyTask<R>.new().method(.get)
    }
    public static func post<R: Decodable>(expecting: R.Type = R.self) -> DeclarativeNetifyTask<R> {
        DeclarativeNetifyTask<R>.new().method(.post)
    }
    public static func put<R: Decodable>(expecting: R.Type = R.self) -> DeclarativeNetifyTask<R> {
        DeclarativeNetifyTask<R>.new().method(.put)
    }
    public static func delete<R: Decodable>(expecting: R.Type = R.self) -> DeclarativeNetifyTask<R> {
        DeclarativeNetifyTask<R>.new().method(.delete)
    }
    public static func patch<R: Decodable>(expecting: R.Type = R.self) -> DeclarativeNetifyTask<R> {
        DeclarativeNetifyTask<R>.new().method(.patch)
    }
}

