# Netify

Swift async/await 기반 네트워킹 라이브러리. 간단한 API, 안전한 로깅(민감정보 마스킹), 재시도·인증·플러그인 지원.

## 설치

- Xcode: File > Add Packages... > `https://github.com/AidenJLee/Netify.git`
- Package.swift:

```swift
// Package.swift
dependencies: [
  .package(url: "https://github.com/AidenJLee/Netify.git", from: "1.1.2"),
]
targets: [
  .target(
    name: "YourApp",
    dependencies: [ .product(name: "Netify", package: "Netify") ]
  )
]
```

## 빠른 시작

```swift
import Netify

// 1) 클라이언트 생성
let config = NetifyConfiguration(
  baseURL: "https://api.example.com",
  logLevel: .info,          // .debug로 상세 로그(마스킹 적용)
  maxRetryCount: 2          // 재시도 횟수(옵션)
)
let client = NetifyClient(configuration: config)

// 2) 요청 정의
struct User: Codable { let id: Int; let name: String }

struct GetUser: NetifyRequest {
  typealias ReturnType = User
  let id: Int
  var path: String { "/users/\(id)" }
  // method = .get 기본값 사용
}

// 3) 호출
let user = try await client.send(GetUser(id: 1))
```

## 자주 쓰는 패턴

- 쿼리/헤더/타임아웃

```swift
struct SearchPosts: NetifyRequest {
  typealias ReturnType = [Post]
  var path: String { "/posts" }
  var queryParams: QueryParameters? { ["q": keyword, "limit": String(limit)] }
  var headers: HTTPHeaders? { ["X-Trace-ID": traceId] }
  var timeoutInterval: TimeInterval? { 10 }
  let keyword: String; let limit: Int; let traceId: String
}
```

- POST: Encodable 본문

```swift
struct CreatePost: NetifyRequest {
  typealias ReturnType = Post
  let path = "/posts"; let method: HTTPMethod = .post
  let body: NewPost // Encodable
  struct NewPost: Encodable { let title: String; let body: String; let userId: Int }
}

let created = try await client.send(CreatePost(body: .init(title: "Hi", body: "Hello", userId: 1)))
```

- 멀티파트 업로드

```swift
struct UploadImage: NetifyRequest {
  typealias ReturnType = EmptyResponse
  let path = "/upload"; let method: HTTPMethod = .post
  var contentType: HTTPContentType { .multipart }
  var multipartData: [MultipartData]? // 파일 파트 배열
}
```

## 기능 요약(간단)

- 재시도: 지수 백오프 + 지터, `maxRetryCount`/상한값 적용
- 취소: 재시도 대기 전후 `Task.checkCancellation()`
- 인증: `AuthenticationProvider`로 토큰 주입/갱신(Bearer 지원)
- 로깅: `logLevel`로 제어(.error/.info/.debug). 민감정보는 항상 마스킹
- 플러그인: 요청 전/후/실패 훅 제공. 실패 컨텍스트는 요약본만 노출(`errorSummary`, `requestSummary`)

```swift
struct MyPlugin: NetifyPlugin {
  func willSend(request: URLRequest) async throws -> URLRequest { request }
  func didReceive(response: URLResponse, data: Data, for request: URLRequest) async throws {}
  func didFail(with context: PluginFailureContext) async throws {
    print(context.errorSummary)
    if let s = context.requestSummary { print(s.method ?? "?", s.url ?? "?") }
  }
}
```

## 로깅 팁

```swift
let config = NetifyConfiguration(baseURL: "…", logLevel: .debug)
let client = NetifyClient(configuration: config)
// 라이브러리 내부에서 민감정보는 자동 마스킹됩니다.
```

## 라이선스

MIT

