# Netify

Netify는 Swift를 위한 강력하고 유연한 네트워킹 라이브러리입니다. 최신 Swift Concurrency(`async/await`)를 기반으로 설계되어, 타입-세이프하고 효율적인 네트워크 통신 계층을 쉽게 구축할 수 있도록 돕습니다.

## 주요 기능

- ✨ **모던한 API:** `async/await` 기반으로 비동기 코드를 간결하고 읽기 쉽게 작성할 수 있습니다.
- 🔄 **자동 재시도:** 서버 오류(5xx), 타임아웃 등 특정 네트워크 오류 발생 시 자동으로 요청을 재시도합니다.
- 🔐 **인증 처리:** Bearer 토큰(자동 갱신 포함), 기본 인증 등 다양한 인증 방식을 지원합니다.
- 📝 **상세한 로깅:** 요청/응답 정보와 cURL 명령어 로그를 통해 디버깅을 용이하게 합니다. (민감 정보 자동 마스킹)
- 🎯 **타입 세이프:** `Codable`을 활용하여 요청과 응답 데이터를 안전하게 처리합니다.
- 📦 **멀티파트 요청:** 파일 업로드 등을 위한 `multipart/form-data` 요청을 간편하게 구성할 수 있습니다.
- ⚙️ **유연한 설정:** 타임아웃, 캐시 정책, 커스텀 인코더/디코더 등 다양한 설정을 클라이언트 또는 요청별로 지정할 수 있습니다.

## 설치 방법

### Swift Package Manager (SPM)

다음 두 가지 방법 중 하나를 사용하여 Netify를 프로젝트에 추가할 수 있습니다.

1.  **Xcode:**
    * Xcode에서 프로젝트를 엽니다.
    * `File` > `Add Packages...` 메뉴를 선택합니다.
    * 검색창에 저장소 URL `https://github.com/AidenJLee/Netify.git` 를 붙여넣습니다.
    * 원하는 버전 규칙(예: `Up to Next Major`)을 선택하고 `Add Package`를 클릭합니다.
2.  **Package.swift:**
    * `Package.swift` 파일의 `dependencies` 배열에 다음 라인을 추가합니다.
        ```swift
        // Package.swift
        dependencies: [
            .package(url: "https://github.com/AidenJLee/Netify.git", from: "2.0.0") // TODO: 사용하려는 최신 버전을 확인하세요
        ]
        ```
    * 해당 라이브러리가 필요한 타겟의 `dependencies`에도 `.product(name: "Netify", package: "Netify")`를 추가합니다.

## 기본 사용법

### 1. Netify 클라이언트 설정

`NetifyClient`를 생성하기 전에 `NetifyConfiguration`을 통해 API의 기본 URL, 로그 레벨 등 공통 설정을 정의합니다.

```swift
import Netify

// Netify 클라이언트 설정 생성
let configuration = NetifyConfiguration(
    baseURL: "https://jsonplaceholder.typicode.com", // API의 기본 URL
    logLevel: .debug, // 로그 레벨 설정 (.off, .error, .info, .debug)
    timeoutInterval: 30.0, // 요청 타임아웃 (초)
    maxRetryCount: 1 // 실패 시 재시도 횟수 (0이면 재시도 안 함)
    // 필요시 기본 헤더, 커스텀 인코더/디코더, 인증 프로바이더 등 추가 설정 가능
)

// Netify 클라이언트 인스턴스 생성
let netifyClient = NetifyClient(configuration: configuration)
```

### 2. 요청 정의

`NetifyRequest` 프로토콜을 채택하여 각 API 엔드포인트에 대한 요청 명세를 정의합니다. `ReturnType`으로 응답 본문을 디코딩할 `Codable` 타입을 지정합니다.

```swift
// 응답 데이터를 담을 모델 (Codable 준수)
struct User: Codable {
    let id: Int
    let name: String
    let email: String
}

struct Post: Codable {
    let id: Int
    let title: String
    let body: String
    let userId: Int
}

// GET 요청 예시
struct GetUserRequest: NetifyRequest {
    typealias ReturnType = User // 응답으로 User 객체를 기대

    let path: String // BaseURL 뒤에 붙는 경로

    // 기본값 method = .get, requiresAuthentication = true 이므로 생략 가능

    init(userId: Int) {
        self.path = "/users/\(userId)"
    }
}

// POST 요청 예시 (JSON Body 사용)
struct CreatePostRequest: NetifyRequest {
    typealias ReturnType = Post // 생성된 Post 객체를 반환받음

    let path = "/posts"
    let method: HTTPMethod = .post
    let body: [String: Any]? // Dictionary 또는 Encodable 객체 사용 가능

    init(title: String, body: String, userId: Int) {
        self.body = [
            "title": title,
            "body": body,
            "userId": userId
        ]
    }
}
```

### 3. 요청 실행

`NetifyClient`의 `send` 메서드를 사용하여 정의된 요청을 비동기적으로 실행하고 응답을 받습니다. (`async/await` 사용)

```swift
func fetchUserData(userId: Int) async {
    // netifyClient는 이 함수 외부에서 미리 생성되어 있다고 가정
    do {
        let userRequest = GetUserRequest(userId: userId)
        let user = try await netifyClient.send(userRequest)
        print("✅ User Fetched: \(user.name)")

        let createPostRequest = CreatePostRequest(title: "New Post", body: "Hello Netify!", userId: user.id)
        let createdPost = try await netifyClient.send(createPostRequest)
        print("✅ Post Created: \(createdPost.title) (ID: \(createdPost.id))")

    } catch {
        // 에러 처리 (NetworkRequestError)
        handleNetifyError(error, context: "Fetch User Data")
    }
}

// 에러 처리 헬퍼 함수 예시
func handleNetifyError(_ error: Error, context: String) {
    print("\n❌ Netify 요청 중 오류 발생 (Context: \(context)):")
    guard let netifyError = error as? NetworkRequestError else {
        // NetifyError가 아닌 다른 오류 (예: Task 취소 등)
        print("   - Non-Netify Error: \(error.localizedDescription)")
        print("   - Error Type: \(type(of: error))")
        return
    }

    // NetifyError의 상세 정보 출력
    print("   - Error Type: \(netifyError)") // enum case 이름
    print("   - Description: \(netifyError.localizedDescription)") // 사용자 친화적 설명

    // Debug 레벨에서는 더 상세한 정보 제공
    #if DEBUG
    print("   - Debug Info: \(netifyError.debugDescription)")
    #endif

    // 특정 오류 유형에 따른 추가 처리 예시
    switch netifyError {
    case .decodingError(let underlyingError, let data):
        print("   - Decoding Failed: \(underlyingError)")
        if let data = data, let dataString = String(data: data, encoding: .utf8) {
            print("   - Received Data (String): \(dataString.prefix(200))...")
        }
    case .unauthorized:
        print("   - Action: 인증 실패. 로그인 화면으로 이동하거나 토큰 갱신 로직 확인 필요.")
    case .noInternetConnection:
        print("   - Action: 인터넷 연결 상태 확인 메시지 표시.")
    default:
        break // 다른 케이스는 기본 정보만 출력
    }
}

// 함수 호출 (async context 내에서)
Task {
    await fetchUserData(userId: 1)
}
```

## 상세 설정 및 기능

### NetifyConfiguration

클라이언트 생성 시 `NetifyConfiguration`을 통해 다양한 옵션을 설정할 수 있습니다.

-   `baseURL`: 모든 요청의 기본 URL (필수)
-   `sessionConfiguration`: `URLSessionConfiguration` 커스터마이징 (기본값: `.default`)
-   `defaultEncoder`: 기본 JSON 인코더 (기본값: `JSONEncoder()`)
-   `defaultDecoder`: 기본 JSON 디코더 (기본값: `JSONDecoder()`)
-   `defaultHeaders`: 모든 요청에 포함될 기본 HTTP 헤더 (`[String: String]`, 기본값: `[:]`)
-   `logLevel`: 로깅 상세 수준 (`.off`, `.error`, `.info`, `.debug`, 기본값: `.info`)
-   `cachePolicy`: 기본 URL 캐시 정책 (기본값: `.useProtocolCachePolicy`)
-   `maxRetryCount`: 실패 시 최대 재시도 횟수 (기본값: 0)
-   `timeoutInterval`: 요청 타임아웃 시간 (초, 기본값: 30.0)
-   `authenticationProvider`: 인증 처리를 위한 프로바이더 (아래 참조)

### 요청 커스터마이징 (NetifyRequest)

`NetifyRequest` 프로토콜을 채택하여 각 요청의 세부 사항을 정의합니다. 프로토콜은 많은 속성에 기본값을 제공합니다.

-   `path`: Base URL 뒤에 추가될 경로 (필수)
-   `method`: HTTP 메서드 (`.get`, `.post`, `.put`, `.delete` 등, 기본값: `.get`)
-   `contentType`: 요청 본문의 타입 (`.json`, `.urlEncoded`, `.multipart` 등, 기본값: `.json`)
-   `queryParams`: URL에 추가될 쿼리 파라미터 (`[String: String]?`, 기본값: `nil`)
-   `body`: 요청 본문 (`Encodable` 객체, `[String: Any]`, `String`, `Data` 등, 기본값: `nil`)
-   `headers`: 요청별 HTTP 헤더 (`HTTPHeaders?`, 기본값: `nil`)
-   `multipartData`: 멀티파트 요청 데이터 (`[MultipartData]?`, 기본값: `nil`)
-   `decoder`: 요청별 커스텀 JSON 디코더 (`JSONDecoder?`, 기본값: `nil` - 클라이언트 기본값 사용)
-   `cachePolicy`: 요청별 캐시 정책 (`URLRequest.CachePolicy?`, 기본값: `nil` - 클라이언트 기본값 사용)
-   `timeoutInterval`: 요청별 타임아웃 (`TimeInterval?`, 기본값: `nil` - 클라이언트 기본값 사용)
-   `requiresAuthentication`: 인증 필요 여부 (`Bool`, 기본값: `true`)

### 인증 처리

`NetifyConfiguration`에 `AuthenticationProvider` 프로토콜을 준수하는 객체를 설정하여 인증 로직을 중앙에서 관리할 수 있습니다. Netify는 `BasicAuthenticationProvider`와 `BearerTokenAuthenticationProvider`를 기본 제공합니다.

#### 1. Bearer 토큰 인증 (자동 갱신 포함)

`BearerTokenAuthenticationProvider`는 Access Token을 자동으로 헤더에 추가하고, 401 오류 발생 시 Refresh Token을 사용하여 토큰 갱신을 시도합니다.

```swift
// 토큰 갱신 로직 정의 (실제 API 호출 필요)
let refreshHandler: BearerTokenAuthenticationProvider.RefreshTokenHandler = { currentRefreshToken in
    print("🔄 Attempting to refresh token...")
    // --- 실제 토큰 갱신 API 호출 ---
    // 예시: let newTokens = try await AuthService.refreshToken(using: currentRefreshToken)
    // 성공 시 새로운 TokenInfo 반환, 실패 시 에러 throw
    // -----------------------------

    // 이 예제에서는 더미 데이터 반환
    try await Task.sleep(nanoseconds: 1_000_000_000) // 1초 지연 시뮬레이션
    return BearerTokenAuthenticationProvider.TokenInfo(
        accessToken: "NEW_DUMMY_ACCESS_TOKEN_\(Int.random(in: 1...100))",
        refreshToken: "NEW_DUMMY_REFRESH_TOKEN"
    )
}

let tokenProvider = BearerTokenAuthenticationProvider(
    accessToken: "INITIAL_ACCESS_TOKEN", // 초기 Access Token
    refreshToken: "INITIAL_REFRESH_TOKEN", // 초기 Refresh Token
    refreshHandler: refreshHandler // 토큰 갱신 로직 클로저
)

let authConfig = NetifyConfiguration(
    baseURL: "https://your-auth-api.com", // 인증이 필요한 API의 Base URL
    authenticationProvider: tokenProvider,
    logLevel: .debug
)
let authClient = NetifyClient(configuration: authConfig)

// 이제 authClient.send(YourRequest()) 호출 시 자동으로 'Authorization: Bearer ...' 헤더가 추가됩니다.
// 401 오류가 발생하면 refreshHandler가 호출되어 토큰 갱신 후 원래 요청을 재시도합니다.
// (단, YourRequest의 requiresAuthentication이 true여야 합니다 - 기본값)
```

#### 2. 기본 인증 (Basic Authentication)

`BasicAuthenticationProvider`는 사용자 이름과 비밀번호를 사용하여 `Authorization: Basic ...` 헤더를 추가합니다.

```swift
let credentials = UserCredentials(username: "myuser", password: "mypassword")
let basicAuthProvider = BasicAuthenticationProvider(credentials: credentials)

let basicAuthConfig = NetifyConfiguration(
    baseURL: "https://your-basic-auth-api.com",
    authenticationProvider: basicAuthProvider
)
let basicAuthClient = NetifyClient(configuration: basicAuthConfig)
```

### 재시도 정책 설정

`NetifyConfiguration`의 `maxRetryCount`를 설정하여 재시도 횟수를 지정합니다. Netify는 기본적으로 서버 오류(5xx), 타임아웃, 특정 네트워크 연결 오류(`noInternetConnection`, `urlSessionFailed` 중 일부) 발생 시 재시도를 시도합니다 (`NetworkRequestError.isRetryable` 확인).

```swift
let configWithRetry = NetifyConfiguration(
    baseURL: "https://api.example.com",
    maxRetryCount: 3 // 실패 시 최대 3번 재시도 (총 4번 요청 시도)
)
```

### 로깅 설정

`NetifyConfiguration`의 `logLevel`을 설정하여 로그 상세 수준을 제어합니다.

-   `.off`: 로깅 비활성화
-   `.error`: 오류만 로깅
-   `.info`: 오류 및 기본 정보(요청 시작/종료, 상태 코드 등) 로깅
-   `.debug`: 오류, 정보 및 상세 디버그 정보(헤더, 본문 요약, cURL 명령어) 로깅

```swift
let config = NetifyConfiguration(
    baseURL: "https://api.example.com",
    logLevel: .debug // 개발 중에는 .debug 추천
)
```

`.debug` 레벨에서는 요청/응답 헤더, 본문 요약, 그리고 cURL 명령어까지 출력되어 디버깅에 매우 유용합니다. 민감한 헤더(`Authorization`, `Cookie` 등)는 자동으로 `<masked>` 처리됩니다.

### 멀티파트 요청 (파일 업로드)

파일 업로드 등 멀티파트 요청은 `NetifyRequest`의 `contentType`을 `.multipart`로 설정하고 `multipartData` 배열에 `MultipartData` 객체를 담아 보냅니다.

```swift
import Netify

// 서버 응답 예시 (내용 없을 경우 EmptyResponse 사용)
struct UploadResponse: Decodable {
    let message: String
    let fileUrl: String?
}

struct UploadImageRequest: NetifyRequest {
    typealias ReturnType = UploadResponse // 서버 응답에 맞는 타입 지정

    let path: String = "/upload" // 실제 업로드 경로로 변경
    let method: HTTPMethod = .post
    var contentType: HTTPContentType { .multipart } // ContentType을 multipart로 명시
    var multipartData: [MultipartData]? // 실제 파일 데이터
    var requiresAuthentication: Bool = true // 보통 업로드는 인증 필요

    init(imageData: Data, fileName: String, mimeType: String, userId: String) {
        self.multipartData = [
            // 파일 데이터 파트
            MultipartData(name: "file", fileData: imageData, fileName: fileName, mimeType: mimeType),
            // 추가 텍스트 필드 파트 (필요시)
            MultipartData(name: "userId", stringData: userId) // 텍스트 데이터용 편의 init 사용
        ]
    }
}

// MultipartData 편의 이니셜라이저 (텍스트 데이터용)
extension MultipartData {
    init(name: String, stringData: String) {
        self.init(name: name, fileData: stringData.data(using: .utf8) ?? Data(), fileName: "", mimeType: "text/plain")
    }
}


// 사용 예시
func uploadImage(data: Data, userId: String) async {
    // netifyClient는 미리 생성되어 있어야 함
    let request = UploadImageRequest(imageData: data, fileName: "profile.jpg", mimeType: "image/jpeg", userId: userId)
    do {
        let response = try await netifyClient.send(request)
        print("✅ Image uploaded successfully! Message: \(response.message)")
    } catch {
        handleNetifyError(error, context: "Upload Image")
    }
}
```

### 커스텀 디코더 사용

특정 요청에 대해 기본 디코더(`NetifyConfiguration.defaultDecoder`) 대신 다른 `JSONDecoder` 설정을 사용해야 할 경우, 요청 정의 시 `decoder` 속성을 지정합니다. 예를 들어, 날짜 형식이 다를 때 유용합니다.

```swift
struct PostWithCustomDate: Codable {
    let id: Int
    let title: String
    let publishedAt: Date // 서버가 ISO8601 형식으로 날짜를 준다고 가정
}

extension PostWithCustomDate {
    struct GetPostWithDateRequest: NetifyRequest {
        typealias ReturnType = PostWithCustomDate

        let path: String
        var decoder: JSONDecoder? // 커스텀 디코더 지정

        init(postId: Int) {
            self.path = "/posts/\(postId)" // 실제 API 경로에 맞게 수정
            // ISO8601 날짜 형식을 처리하는 커스텀 디코더 설정
            let customDecoder = JSONDecoder()
            customDecoder.dateDecodingStrategy = .iso8601
            self.decoder = customDecoder
        }
    }
}
```

### 원시 데이터(Raw Data) 받기

JSON이 아닌 이미지나 파일 등의 원시 데이터를 응답으로 받아야 할 경우, `ReturnType`을 `Data`로 지정합니다.

```swift
import Netify
import UIKit // 예시: UIImage 사용

struct GetRawDataRequest: NetifyRequest {
    typealias ReturnType = Data // 반환 타입을 Data로 지정

    let path: String // 예: 이미지 파일 경로
    let method: HTTPMethod = .get
    var requiresAuthentication: Bool = false // 예시: 인증 불필요

    init(imagePath: String) {
        self.path = imagePath // 예: "/images/logo.png"
    }
}

func fetchImage(imagePath: String) async -> UIImage? {
    // 이미지 URL을 제공하는 API의 BaseURL로 클라이언트 설정 필요
    let imageClientConfig = NetifyConfiguration(baseURL: "https://via.placeholder.com", logLevel: .info) // 예시 이미지 URL
    let imageClient = NetifyClient(configuration: imageClientConfig)

    let request = GetRawDataRequest(imagePath: imagePath) // 예: "/150"
    do {
        let imageData = try await imageClient.send(request)
        print("✅ Raw data fetched: \(imageData.count) bytes")
        return UIImage(data: imageData)
    } catch {
        handleNetifyError(error, context: "Fetch Image Data")
        return nil
    }
}
```

## 에러 처리

Netify는 네트워크 요청 중 발생할 수 있는 다양한 오류 상황을 `NetworkRequestError` 열거형으로 정의하여 제공합니다. `catch` 블록에서 이 타입을 확인하여 구체적인 오류에 따라 분기 처리를 할 수 있습니다.

```swift
func someNetworkCall() async {
    // netifyClient는 미리 생성되어 있어야 함
    // MyRequest는 NetifyRequest를 준수하는 사용자 정의 타입
    struct MyRequest: NetifyRequest {
        typealias ReturnType = User // 예시
        let path = "/some/path"
    }

    do {
        let response = try await netifyClient.send(MyRequest())
        print("Success: \(response)")
    } catch let error as NetworkRequestError {
        switch error {
        case .unauthorized:
            // 인증 에러 처리 (예: 로그인 화면으로 이동)
            print("Authentication failed. Need to re-login.")
        case .notFound:
            print("Resource not found (404). Check the request path.")
        case .decodingError(let underlyingError, let data):
            // 디코딩 실패 처리 (예: 모델과 서버 응답 불일치)
            print("Failed to decode response: \(underlyingError)")
            if let data = data, let str = String(data: data, encoding: .utf8) {
                print("Received data: \(str.prefix(100))...")
            }
        case .noInternetConnection:
            // 인터넷 연결 없음 처리 (예: 사용자에게 알림)
            print("No internet connection. Please check your network settings.")
        case .serverError(let statusCode, _):
            // 서버 내부 오류 처리 (예: 잠시 후 다시 시도 안내)
            print("Server error with status code: \(statusCode)")
        case .timedOut:
            // 요청 시간 초과 처리
            print("Request timed out. The server might be busy or network is slow.")
        case .urlSessionFailed(let underlyingError):
            // URLSession 레벨 오류 (더 상세한 네트워크 문제)
            print("Network session failed: \(underlyingError.localizedDescription)")
        default:
            // 기타 클라이언트 오류, 요청 구성 오류 등
            print("An unexpected network error occurred: \(error.localizedDescription)")
            #if DEBUG
            print("Debug Info: \(error.debugDescription)")
            #endif
        }
    } catch {
        // NetifyError 외 다른 종류의 오류 (드문 경우)
        print("An unknown error occurred: \(error)")
    }
}
```

## 기여하기

버그 리포트, 기능 제안, Pull Request 등 모든 종류의 기여를 환영합니다! 이슈 트래커를 확인하거나 새로운 이슈를 생성해 주세요.

## 라이선스

Netify는 MIT 라이선스 하에 배포됩니다. 자세한 내용은 저장소의 `LICENSE` 파일을 확인하세요.
