# Netify

<div align="center">

**🚀 Modern Swift Networking Library for the Future**

[![Swift 6.0+](https://img.shields.io/badge/Swift-6.0+-orange.svg)](https://swift.org)
[![iOS 15+](https://img.shields.io/badge/iOS-15+-blue.svg)](https://developer.apple.com/ios/)
[![macOS 12+](https://img.shields.io/badge/macOS-12+-blue.svg)](https://developer.apple.com/macos/)
[![Swift Package Manager](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)](https://swift.org/package-manager/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

*Type-Safe • Declarative • Concurrent • Cached*

</div>

---

## 🌟 Why Netify?

**Netify**는 Swift 6 동시성 모델을 완벽히 구현한 차세대 네트워킹 라이브러리입니다. 단순한 HTTP 클라이언트를 넘어선 **enterprise-grade** 네트워킹 솔루션을 제공합니다.

### ✨ Core Features

| Feature | Description |
|---------|-------------|
| 🎯 **Type-Safe DSL** | SwiftUI-inspired declarative API with compile-time safety |
| ⚡ **Swift 6 Ready** | Full `Sendable` compliance and actor-based concurrency |
| 🔄 **Smart Retry** | Exponential backoff with jitter + `Retry-After` header support |
| 🗄️ **Advanced Caching** | HTTP-compliant caching with ETag, TTL, and Vary header support |
| 🔐 **Auto Authentication** | Bearer token refresh on 401 with 1-retry limit |
| 🔌 **Plugin System** | Extensible middleware for logging, metrics, and custom logic |
| 🏎️ **Performance Optimized** | Copy-on-Write semantics and memory-efficient design |
| 🧪 **Test-Friendly** | Protocol-based architecture with perfect mockability |

---

## 📦 Installation

### Swift Package Manager

**Xcode Integration:**
```
File → Add Packages → Enter URL: https://github.com/AidenJLee/Netify.git
```

**Package.swift:**
```swift
dependencies: [
    .package(url: "https://github.com/AidenJLee/Netify.git", from: "2.0.0")
]
```

---

## 🚀 Quick Start

### 1. Basic Setup

```swift
import Netify

let configuration = NetifyConfiguration(
    baseURL: "https://api.github.com",
    logLevel: .debug,
    maxRetryCount: 2,
    cache: .etagOrTtl(seconds: 300),
    responseCache: InMemoryResponseCache()
)

let client = NetifyClient(configuration: configuration)
```

### 2. Three Powerful API Styles

**🎯 Protocol-Based (Best for reusable requests)**
```swift
struct GitHubUser: Codable, Sendable {
    let id: Int
    let login: String
    let name: String?
}

struct FetchUserRequest: NetifyRequest {
    typealias ReturnType = GitHubUser
    
    let username: String
    var path: String { "/users/\(username)" }
}

// Usage
let user = try await client.send(FetchUserRequest(username: "octocat"))
print("Hello, \(user.login)!")
```

**⛓️ Method Chaining (Best for simple requests)**
```swift
let user = try await client.send(
    Netify.get(expecting: GitHubUser.self)
        .path("/users/{username}")
        .pathArgument("username", "octocat")
        .header("Accept", "application/vnd.github.v3+json")
)
```

**🎨 Declarative DSL (Best for dynamic requests)**
```swift
let user: GitHubUser = try await client.send(expecting: GitHubUser.self) {
    Method(.get)
    Path("/users/{username}")
    PathArgument("username", "octocat")
    Header("Accept", "application/vnd.github.v3+json")
    
    if enableTracing {
        Header("X-Trace-ID", UUID().uuidString)
    }
}
```

---

## 📚 Advanced Features

### 🔐 Authentication

**Bearer Token with Auto-Refresh:**
```swift
let authProvider = BearerTokenAuthenticationProvider(
    accessToken: "your_access_token",
    refreshToken: "your_refresh_token"
) { refreshToken in
    // Custom refresh logic
    let response = try await MyAuthAPI.refreshToken(refreshToken)
    return .init(
        accessToken: response.accessToken,
        refreshToken: response.refreshToken
    )
}

let config = NetifyConfiguration(
    baseURL: "https://api.secure.com",
    authenticationProvider: authProvider
)
```

### 🗄️ Intelligent Caching

**HTTP-Compliant Multi-Layer Caching:**
```swift
let config = NetifyConfiguration(
    baseURL: "https://api.example.com",
    cache: .etagOrTtl(seconds: 300),  // Use ETag or 5-minute TTL
    responseCache: InMemoryResponseCache()
)

// Automatic Vary header handling
let articles = try await client.send(
    Netify.get(expecting: [Article].self)
        .path("/articles")
        .header("Accept-Language", "ko")  // Creates separate cache entry
)
```

### 🔌 Plugin System

**Custom Request/Response Interceptor:**
```swift
struct LoggingPlugin: NetifyPlugin {
    func willSend(_ request: URLRequest) {
        print("🚀 Sending: \(request.httpMethod ?? "GET") \(request.url?.path ?? "")")
    }
    
    func didReceive(_ result: Result<(Data, URLResponse), NetworkRequestError>, 
                    for request: URLRequest) {
        switch result {
        case .success((_, let response as HTTPURLResponse)):
            print("✅ Success: \(response.statusCode)")
        case .failure(let error):
            print("❌ Failed: \(error)")
        }
    }
}

let config = NetifyConfiguration(
    baseURL: "https://api.example.com",
    plugins: [LoggingPlugin()]
)
```

### 📊 Request Body Types

**Type-Safe Request Bodies:**
```swift
struct CreatePost: Codable, Sendable {
    let title: String
    let content: String
}

// JSON Body
let post = try await client.send(
    Netify.post(expecting: Post.self)
        .path("/posts")
        .bodyJSON(CreatePost(title: "Hello", content: "World"))
)

// URL Encoded
let result = try await client.send(
    Netify.post(expecting: LoginResponse.self)
        .path("/auth/login")
        .bodyURLEncoded([
            "username": "user@example.com",
            "password": "secret123"
        ])
)

// Multipart
let profileUpdate = try await client.send(
    Netify.put(expecting: User.self)
        .path("/profile/avatar")
        .multipart([
            MultipartData(
                name: "avatar",
                fileData: imageData,
                fileName: "profile.jpg",
                mimeType: "image/jpeg"
            )
        ])
)
```

---

## 🛠️ Error Handling

**Comprehensive Error Types:**
```swift
do {
    let data = try await client.send(someRequest)
} catch let error as NetworkRequestError {
    switch error {
    case .unauthorized:
        // Handle authentication failure
        redirectToLogin()
        
    case .serverError(let statusCode, _, let retryAfter):
        // Server error with retry information
        if let delay = retryAfter {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            // Retry logic
        }
        
    case .noInternetConnection:
        // Handle offline state
        showOfflineMessage()
        
    case .decodingError(let underlyingError, let data):
        // Handle JSON parsing errors
        logDecodingFailure(underlyingError, rawData: data)
        
    default:
        // Handle other network errors
        showGenericErrorMessage()
    }
}
```

---

## 🏗️ Architecture Highlights

### 🎯 Protocol-Oriented Design
- **NetifyClientProtocol**: Perfect for dependency injection and testing
- **NetworkSessionProtocol**: URLSession abstraction for mocking
- **AuthenticationProvider**: Strategy pattern for various auth methods

### ⚡ Swift 6 Concurrency
- All public types are `Sendable` compliant
- Actor-based cache and plugin state management
- Zero data races guaranteed

### 🚀 Performance Optimized
- **Copy-on-Write** semantics for immutable request builders
- **Type Erasure** (`AnyEncodable`) to prevent generic explosion
- Memory-efficient caching with automatic cleanup

### 🧪 Test-Friendly Architecture
```swift
// Perfect mockability
let mockSession = MockNetworkSession()
let testClient = NetifyClient(
    configuration: config,
    networkSession: mockSession
)
```

---

## 📖 Configuration Reference

### NetifyConfiguration Options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `baseURL` | `String` | **Required** | Base URL for all requests |
| `logLevel` | `NetworkingLogLevel` | `.info` | Logging verbosity (`.off`, `.error`, `.info`, `.debug`) |
| `maxRetryCount` | `Int` | `0` | Maximum retry attempts for retryable errors |
| `timeoutInterval` | `TimeInterval` | `30.0` | Default request timeout |
| `authenticationProvider` | `AuthenticationProvider?` | `nil` | Authentication strategy |
| `cache` | `NetifyCachePolicy` | `.none` | Caching policy (`.none`, `.etag`, `.ttl`, `.etagOrTtl`) |
| `responseCache` | `ResponseCache?` | `nil` | Cache storage implementation |
| `plugins` | `[NetifyPlugin]` | `[]` | Request/response middleware |
| `metrics` | `NetworkMetrics` | `NoopMetrics()` | Performance monitoring |

### Cache Policies

```swift
// No caching
.cache(.none)

// ETag-based conditional requests
.cache(.etag)

// Time-based caching (5 minutes)
.cache(.ttl(seconds: 300))

// Hybrid: Use ETag if available, fallback to TTL
.cache(.etagOrTtl(seconds: 300))
```

---

## 🔄 Migration Guide

### From Alamofire

```swift
// Alamofire
AF.request("https://api.github.com/users/octocat")
    .validate()
    .responseDecodable(of: User.self) { response in
        // Handle response
    }

// Netify
let user = try await client.send(
    Netify.get(expecting: User.self)
        .path("/users/octocat")
)
```

### From URLSession

```swift
// URLSession
let url = URL(string: "https://api.github.com/users/octocat")!
let (data, _) = try await URLSession.shared.data(from: url)
let user = try JSONDecoder().decode(User.self, from: data)

// Netify
let user = try await client.send(
    Netify.get(expecting: User.self)
        .path("/users/octocat")
)
```

---

## 🎯 Best Practices

### 1. **Use Protocol-Based Requests for Reusability**
```swift
// ✅ Good: Reusable and testable
struct FetchUserRequest: NetifyRequest {
    typealias ReturnType = User
    let userID: Int
    var path: String { "/users/\(userID)" }
}

// ❌ Avoid: Repeated inline requests
let user1 = try await client.send(Netify.get(expecting: User.self).path("/users/1"))
let user2 = try await client.send(Netify.get(expecting: User.self).path("/users/2"))
```

### 2. **Leverage Caching for Performance**
```swift
// ✅ Good: Enable appropriate caching
let config = NetifyConfiguration(
    baseURL: "https://api.example.com",
    cache: .etagOrTtl(seconds: 300),
    responseCache: InMemoryResponseCache()
)
```

### 3. **Implement Proper Error Handling**
```swift
// ✅ Good: Specific error handling
do {
    let user = try await client.send(request)
} catch NetworkRequestError.unauthorized {
    await refreshTokenAndRetry()
} catch NetworkRequestError.noInternetConnection {
    showOfflineMode()
} catch {
    logError(error)
}
```

---

## 🧪 Testing

### Unit Testing with Mocks

```swift
import XCTest
@testable import Netify

class NetworkingTests: XCTestCase {
    func testUserFetch() async throws {
        let mockSession = MockNetworkSession()
        let client = NetifyClient(
            configuration: NetifyConfiguration(baseURL: "https://api.test.com"),
            networkSession: mockSession
        )
        
        let expectedUser = User(id: 1, name: "Test User")
        mockSession.mockResponse(expectedUser, for: "/users/1")
        
        let user = try await client.send(FetchUserRequest(userID: 1))
        XCTAssertEqual(user.name, "Test User")
    }
}
```

---

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Setup
```bash
git clone https://github.com/AidenJLee/Netify.git
cd Netify
swift build
swift test
```

---

## 📄 License

Netify is released under the MIT License. See [LICENSE](LICENSE) for details.

---

## 🔗 Resources

- 📖 [Documentation](https://aidenlee.github.io/Netify/)
- 🐛 [Issue Tracker](https://github.com/AidenJLee/Netify/issues)
- 💬 [Discussions](https://github.com/AidenJLee/Netify/discussions)
- 🚀 [Roadmap](https://github.com/AidenJLee/Netify/projects/1)

---

<div align="center">

**Made with ❤️ by the Swift community**

[⭐ Star us on GitHub](https://github.com/AidenJLee/Netify) • [🐦 Follow updates](https://twitter.com/NetifySwift)

</div>