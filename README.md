-----

# Netify

**Netify: Swift 네트워킹의 새로운 패러다임.**

Netify는 현대적인 Swift 애플리케이션을 위한 정교하고 유연한 네트워킹 솔루션입니다. Swift Concurrency(`async/await`)의 힘을 빌려, 개발자는 타입에 안전하면서도 효율적인 네트워크 통신 계층을 직관적으로 구축할 수 있습니다. 복잡성은 Netify에 맡기고, 핵심 가치 구현에 집중하십시오.

## Netify가 제공하는 핵심 가치

  * **현대적 API 설계**: `async/await`를 중심으로 비동기 코드를 명료하고 우아하게 작성합니다.
  * **선언적 요청 구성**: 메소드 체이닝을 통해 요청을 선언적으로 구성하여, 코드의 가독성과 의도의 명확성을 극대화합니다.
  * **견고한 실행 환경**: 자동 재시도 메커니즘(서버 오류, 타임아웃 대응) 및 Bearer 토큰 자동 갱신을 포함한 다층적 인증 지원으로 안정적인 통신을 보장합니다.
  * **통찰력 있는 디버깅**: 상세한 요청/응답 로그 및 cURL 명령어 출력을 제공하여 문제 해결 과정을 효율화합니다. (민감 정보는 안전하게 마스킹 처리)
  * **타입 안전성 및 동시성 지원**: `Codable`을 통한 데이터 무결성을 확보하고, 다수의 핵심 타입이 `Sendable`을 준수하여 Swift Concurrency 환경과의 완벽한 조화를 이룹니다.
  * **유연한 멀티파트 요청**: 파일 업로드 등 `multipart/form-data` 요청을 손쉽게 구성할 수 있습니다.
  * **세밀한 제어**: 타임아웃, 캐시 정책, 사용자 정의 인코더/디코더 등 다양한 설정을 전역 또는 요청별로 유연하게 적용할 수 있습니다.

## 프로젝트 통합 가이드

### Swift Package Manager (SPM)

1.  **Xcode 프로젝트에 통합:**
      * Xcode에서 `File` \> `Add Packages...`를 선택합니다.
      * 검색창에 `https://github.com/AidenJLee/Netify.git`를 입력하고, 버전 규칙(예: `Up to Next Major`)을 선택하여 패키지를 추가합니다.
2.  **Package.swift를 통한 통합:**
    ```swift
    // Package.swift
    dependencies: [
        .package(url: "https://github.com/AidenJLee/Netify.git", from: "1.2.0") // 프로젝트에 맞는 최신 버전을 명시하십시오.
    ]
    ```
    타겟의 `dependencies`에도 `.product(name: "Netify", package: "Netify")`를 추가하는 것을 잊지 마십시오.

## Netify 시작하기: 기본 원리 이해

### 1\. `NetifyClient`: 통신의 시작점

모든 네트워크 요청은 `NetifyClient` 인스턴스를 통해 관리됩니다. 클라이언트 생성 시, `NetifyConfiguration` 객체를 통해 기본 설정을 정의합니다.

```swift
import Netify

// Netify 클라이언트의 기본 동작을 정의하는 설정 객체 생성
let netifyConfiguration = NetifyConfiguration(
    baseURL: "https://api.yourdomain.com/v1",      // API 서버의 기본 URL
    logLevel: .debug,                             // 개발 환경에서는 .debug로 상세 로그 확인
    maxRetryCount: 2,                              // 오류 발생 시 최대 2회 추가 재시도
    timeoutInterval: 25.0,                         // 요청 타임아웃 25초
    defaultHeaders: ["X-Client-Type": "iOS-App"]  // 모든 요청에 포함될 기본 헤더
    // 이 외에도 커스텀 인코더/디코더, 인증 프로바이더 등을 설정할 수 있습니다.
)

// 설정 객체를 사용하여 NetifyClient 인스턴스 생성
let client = NetifyClient(configuration: netifyConfiguration)
```

### 2\. 요청 정의: `NetifyRequest` 프로토콜 (기본 접근 방식)

Netify에서 요청을 정의하는 근본적인 방법은 `NetifyRequest` 프로토콜을 채택하는 구조체를 만드는 것입니다. 이 방식은 각 API 엔드포인트의 명세를 명확하고 타입-세이프하게 표현하며, 요청의 모든 측면을 정밀하게 제어할 수 있게 합니다.

#### 응답 데이터 모델 준비

먼저, API 응답을 담을 `Codable` 및 `Sendable`을 준수하는 모델을 정의합니다.

```swift
struct User: Codable, Sendable, Identifiable {
    let id: Int; let name: String; let email: String; let username: String
}

struct Post: Codable, Sendable, Identifiable {
    let id: Int; let userId: Int; let title: String; let body: String
}

struct PostPayload: Codable, Sendable { // POST/PUT 요청 본문용 모델
    let title: String; let body: String; let userId: Int
}

struct FileUploadConfirmation: Codable, Sendable { // 파일 업로드 응답용 모델
    let fileId: String; let persistedFileName: String; let downloadURL: String
}

struct CustomEvent: Codable, Sendable { // 커스텀 디코딩 예제용
    let eventTitle: String; let eventTimestamp: Date
}
```

#### 예제 1: 기본 GET 요청 – 특정 사용자 정보 조회

```swift
struct FetchUserRequest: NetifyRequest {
    typealias ReturnType = User // 이 요청의 결과는 User 타입입니다.

    let userID: Int
    var path: String { "/users/\(userID)" } // BaseURL에 추가될 경로

    // method는 기본값이 .get이므로 명시하지 않아도 됩니다.
    // GET 요청이므로 body, contentType 등도 필요 없습니다.
}

// 사용 예:
// Task {
//     do {
//         let user = try await client.send(FetchUserRequest(userID: 1))
//         print("사용자 정보: \(user.name), 이메일: \(user.email)")
//     } catch {
//         // 오류 처리 (handleNetifyError 함수는 아래 '오류 처리' 섹션 참조)
//         handleNetifyError(error, context: "FetchUserRequest")
//     }
// }
```

#### 예제 2: GET 요청 확장 – 쿼리 파라미터 및 커스텀 헤더 활용

특정 사용자의 게시물 목록을 조회하며, 결과 개수 제한 및 정렬 순서를 쿼리 파라미터로, 추적 ID를 커스텀 헤더로 전달합니다.

```swift
struct FetchUserPostsRequest: NetifyRequest {
    typealias ReturnType = [Post] // Post 객체의 배열을 기대합니다.

    let userID: Int
    let limit: Int
    let sortBy: String // 예: "date", "title"
    let traceID: String

    var path: String { "/users/\(userID)/posts" }
    var queryParams: QueryParameters? {
        ["_limit": String(limit), "_sort": sortBy]
    }
    var headers: HTTPHeaders? {
        ["X-App-Trace-ID": traceID]
    }
    var requiresAuthentication: Bool = false // 이 API는 인증이 필요 없다고 가정
}
```

#### 예제 3: 데이터 생성 – POST 요청과 `Encodable` 본문

`Encodable`을 준수하는 객체를 요청 본문으로 사용하여 새로운 게시물을 생성합니다.

```swift
struct CreateNewPostRequest: NetifyRequest {
    typealias ReturnType = Post // 생성된 Post 객체를 응답으로 받습니다.

    let path: String = "/posts"
    let method: HTTPMethod = .post // POST 메소드를 명시합니다.
    var body: Any? // Encodable 객체를 할당합니다.

    init(payload: PostPayload) {
        self.body = payload // PostPayload 인스턴스를 body로 설정
    }
    // contentType은 NetifyRequest의 기본값(.json)을 사용합니다.
    // Netify의 RequestBuilder가 Encodable body를 감지하고 JSON으로 인코딩합니다.
}
```

#### 예제 4: 파일 전송 – 멀티파트 POST 요청

이미지 파일과 추가적인 텍스트 데이터를 함께 업로드합니다.

```swift
// MultipartData에 텍스트 파트를 쉽게 추가하기 위한 편의 이니셜라이저
public extension MultipartData { // 라이브러리 또는 프로젝트의 유틸리티 파일에 추가
    init(name: String, stringData: String, mimeType: String = "text/plain; charset=utf-8") {
        self.init(name: name, fileData: stringData.data(using: .utf8) ?? Data(), fileName: "", mimeType: mimeType)
    }
}

struct UploadProfileImageRequest: NetifyRequest {
    typealias ReturnType = FileUploadConfirmation

    let userID: String
    var path: String { "/users/\(userID)/profile-image" }
    let method: HTTPMethod = .post
    var contentType: HTTPContentType { .multipart } // 멀티파트 요청임을 명시합니다.

    var multipartData: [MultipartData]? // 파일 및 추가 데이터를 담습니다.

    init(userID: String, image: Data, imageName: String, caption: String) {
        self.userID = userID
        self.multipartData = [
            MultipartData(name: "profileImage", fileData: image, fileName: imageName, mimeType: "image/png"), // MIME 타입은 실제 파일 형식에 맞게!
            MultipartData(name: "caption", stringData: caption)
        ]
    }
}
```

#### 예제 5: 요청별 특수 설정 – 타임아웃, 캐시 정책 변경

클라이언트 기본 설정을 특정 요청에 한해 오버라이드합니다.

```swift
struct FetchCriticalReportRequest: NetifyRequest {
    typealias ReturnType = Data // 보고서 파일을 Data로 받는다고 가정

    let reportID: String
    var path: String { "/reports/\(reportID)/critical" }

    var timeoutInterval: TimeInterval? { 90.0 } // 이 요청은 90초까지 기다립니다.
    var cachePolicy: URLRequest.CachePolicy? { .reloadIgnoringLocalCacheData } // 캐시를 사용하지 않고 항상 새로 요청합니다.
    var requiresAuthentication: Bool = true // 민감한 정보이므로 인증이 필수입니다.
}
```

#### 예제 6: 사용자 정의 디코딩 전략 – 특정 날짜 형식 처리

서버가 표준적이지 않은 날짜 형식을 사용할 경우, 요청별로 `JSONDecoder`를 커스터마이징합니다.

```swift
struct FetchCustomEventRequest: NetifyRequest {
    typealias ReturnType = CustomEvent

    let eventID: String
    var path: String { "/events/\(eventID)/custom-date" }
    var decoder: JSONDecoder? {
        let customDecoder = JSONDecoder()
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy 'at' HH:mm:ss Z" // 예: "25.12.2025 at 15:30:00 +0900"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        customDecoder.dateDecodingStrategy = .formatted(formatter)
        return customDecoder
    }
}
```

`NetifyRequest` 프로토콜을 사용하면 요청의 모든 세부사항을 명확하게 정의하고 제어할 수 있습니다.

-----

### 3\. 요청 정의 및 실행 (대안): 선언적 API – 흐르는 듯한 코드 작성 (간결함 \#2)

매번 `NetifyRequest` 프로토콜을 채택하는 구조체를 만드는 대신, Netify는 더욱 간결하고 유려한 **선언적 API**를 제공합니다. `Netify.task(expecting:)` 또는 HTTP 메소드별 단축키(`Netify.get`, `Netify.post` 등)로 시작하여, 메소드 체이닝을 통해 필요한 설정을 물 흐르듯 추가해 나갈 수 있습니다.

```swift
// --- 선언적 API 사용 예시 ---

func manageDataWithDeclarativeAPI(userID: Int, newPost: PostPayload) async {
    do {
        // 기본 GET: 특정 사용자 정보 조회
        let user = try await client.send(
            Netify.get(expecting: User.self)
                .path("/users/{id}")
                .pathArgument("id", userID) // 경로 내 {id} 부분을 userID 값으로 치환
        )
        print("👤 [선언] 사용자: \(user.name)")

        // GET + 쿼리 파라미터 + 헤더: 사용자 게시물 목록 (최근 3개)
        let posts = try await client.send(
            Netify.get(expecting: [Post].self)
                .path("/posts")
                .queryParam("userId", userID)    // /posts?userId=...
                .queryParam("_sort", "id")       // &_sort=id
                .queryParam("_order", "desc")    // &_order=desc
                .queryParam("_limit", 3)         // &_limit=3
                .header("X-Request-Source", "Netify-Declarative")
        )
        print("📝 [선언] 사용자 \(userID)의 최근 게시물 \(posts.count)개 조회 완료.")

        // POST + Encodable 본문: 새 게시물 작성
        let createdPost = try await client.send(
            Netify.post(expecting: Post.self)
                .path("/posts")
                .body(newPost) // PostPayload 객체를 JSON 본문으로 자동 변환
        )
        print("🎉 [선언] 새 게시물 생성: \(createdPost.title)")

        // 멀티파트 POST: 파일 업로드
        let dummyImageData = "선언적 API로 업로드하는 이미지 데이터!".data(using: .utf8)!
        let imagePart = MultipartData(name: "photo", fileData: dummyImageData, fileName: "declarative.txt", mimeType: "text/plain")
        let titlePart = MultipartData(name: "title", stringData: "선언적 업로드 테스트")
        
        let uploadResult = try await client.send(
            Netify.post(expecting: FileUploadConfirmation.self)
                .path("/photos") // 가상 업로드 경로
                .multipart([imagePart, titlePart])
        )
        print("🖼️ [선언] 파일 업로드 확인: \(uploadResult.persistedFileName)")

        // 요청별 설정 오버라이드: 커스텀 디코더 및 타임아웃
        let customDecoder = JSONDecoder()
        customDecoder.keyDecodingStrategy = .convertFromSnakeCase // 예: event_title -> eventTitle
        
        let event = try await client.send(
            Netify.get(expecting: CustomEvent.self) // CustomEvent는 eventTimestamp: Date 가짐
                .path("/events/special-promo")
                .customDecoder(customDecoder) // 이 요청에만 적용
                .timeout(10.0)                // 10초 타임아웃
                .authentication(required: false) // 인증 불필요
        )
        print("🗓️ [선언] 특별 이벤트: '\(event.eventTitle)' at \(event.eventTimestamp)")

    } catch {
        handleNetifyError(error, context: "선언적 API 종합")
    }
}

// 사용 예:
// Task {
//     await manageDataWithDeclarativeAPI(userID: 1, newPost: PostPayload(title: "선언적 API 탐험", body: "Netify는 정말 멋져!", userId: 1))
// }
```

선언적 API는 `.method()`, `.pathArgument()`, `.queryParam()`, `.header()`, `.body()`, `.multipart()`, `.timeout()`, `.cachePolicy()`, `.customDecoder()`, `.authentication(required:)` 등 풍부한 Modifier를 통해 요청을 직관적이고 유연하게 구성할 수 있도록 돕습니다.

-----

### 오류 처리: 예상치 못한 상황에 대한 대비

네트워크 통신은 다양한 변수로 가득합니다. Netify는 발생 가능한 오류들을 `NetworkRequestError` 열거형으로 상세히 정의하여, 개발자가 각 상황에 맞게 정교하게 대응할 수 있도록 지원합니다.

```swift
func handleNetifyError(_ error: Error, context: String) {
    // (기존 README의 handleNetifyError 함수 내용과 동일하게 유지)
    print("\n❌ Netify 요청 중 오류 발생 (Context: \(context)):")
    guard let netifyError = error as? NetworkRequestError else {
        print("   - 일반 오류: \(error.localizedDescription) (타입: \(type(of: error)))")
        return
    }

    print("   - 오류 타입: NetifyError.\(String(describing: netifyError).components(separatedBy: "(").first ?? "")")
    print("   - 상세 설명: \(netifyError.localizedDescription)")

    #if DEBUG
    print("   - 디버그 정보: \(netifyError.debugDescription)")
    #endif

    switch netifyError {
    case .unauthorized:
        print("   - 조치 제안: 인증 정보가 만료되었거나 유효하지 않습니다. 재로그인 또는 토큰 갱신이 필요합니다.")
    case .noInternetConnection:
        print("   - 조치 제안: 디바이스의 네트워크 연결 상태를 확인하십시오.")
    case .timedOut:
        print("   - 조치 제안: 서버 응답이 지연되고 있습니다. 잠시 후 다시 시도하거나 네트워크 상태를 점검하십시오.")
    case .decodingError(let underlyingError, let data):
        print("   - 원인 분석: 서버 응답 데이터를 앱의 모델로 변환하는 데 실패했습니다. 모델과 API 응답 스펙을 확인하십시오.")
        print("     - 내부 오류: \(underlyingError.localizedDescription)")
        if let data = data, let rawString = String(data: data, encoding: .utf8) {
            print("     - 수신 데이터 (일부): \(rawString.prefix(300))...")
        }
    default:
        print("   - 일반 네트워크 오류: 로그를 참조하여 추가적인 원인 분석이 필요합니다.")
    }
}
```

### Netify의 든든한 지원군: `NetifyConfiguration` 🛠️

클라이언트 생성 시 `NetifyConfiguration`으로 다양한 전역 설정을 할 수 있습니다.

  - `baseURL`: API의 심장, 기본 URL (필수\!)
  - `sessionConfiguration`: `URLSessionConfiguration` 커스터마이징.
  - `defaultEncoder`/`defaultDecoder`: JSON 처리의 마법사들.
  - `defaultHeaders`: 모든 요청에 기본으로 실릴 헤더.
  - `logLevel`: Netify의 수다 수준 (`.off`, `.error`, `.info`, `.debug`).
  - `cachePolicy`: 똑똑한 데이터 관리, 캐시 정책.
  - `maxRetryCount`: 실패는 성공의 어머니, 재시도 횟수.
  - `timeoutInterval`: 무한정 기다릴 순 없죠, 타임아웃.
  - `authenticationProvider`: 인증 해결사 (아래에서 자세히\!).
  - `waitsForConnectivity`: 네트워크 연결을 기다릴지 여부.

-----

### 보안관: 인증 처리 🛡️

`NetifyConfiguration`에 `AuthenticationProvider`를 설정하면 인증이 필요한 요청에 자동으로 적용됩니다.

#### 1\. Bearer 토큰 (자동 갱신 마법 포함)

`BearerTokenAuthenticationProvider`가 알아서 토큰을 헤더에 싣고, 만료 시(`401 Unauthorized`)에는 `refreshHandler`를 통해 새 생명을 불어넣습니다\!

```swift
let refreshHandler: BearerTokenAuthenticationProvider.RefreshTokenHandler = { currentRefreshToken in
    print("🔄 토큰 갱신 시도 중...")
    // !!! 중요: 여기에 실제 토큰 갱신 API 호출 로직을 구현해야 합니다 !!!
    // 예: 다른 NetifyClient 인스턴스나 URLSession 직접 사용하여 /oauth/refresh 엔드포인트 호출
    // 성공 시: return BearerTokenAuthenticationProvider.TokenInfo(accessToken: "새 액세스 토큰", refreshToken: "새 리프레시 토큰 (선택)")
    // 실패 시: throw MyAuthError.tokenRefreshFailed
    
    // 임시 더미 구현 (실제 프로젝트에서는 반드시 실제 로직으로 교체)
    try await Task.sleep(for: .seconds(0.5))
    let newAccessToken = "refreshed_access_token_\(UUID().uuidString.prefix(8))"
    print("✅ 토큰 <em>갱신됨</em>: \(newAccessToken)")
    return BearerTokenAuthenticationProvider.TokenInfo(accessToken: newAccessToken, refreshToken: currentRefreshToken) // 리프레시 토큰은 그대로 사용
}

let tokenProvider = BearerTokenAuthenticationProvider(
    accessToken: "초기_액세스_토큰_값",
    refreshToken: "초기_리프레시_토큰_값",
    refreshHandler: refreshHandler
)

let authenticatedConfig = NetifyConfiguration(
    baseURL: "https://secure.yourdomain.com/api",
    authenticationProvider: tokenProvider,
    logLevel: .debug
)
let authClient = NetifyClient(configuration: authenticatedConfig)

// 이제 authClient를 사용하는 요청은 자동으로 Bearer 토큰을 헤더에 포함합니다.
// 만약 서버가 401을 반환하면, refreshHandler가 동작하여 토큰을 갱신하고 원래 요청을 재시도합니다.
// (단, 요청 구성 시 .authentication(required: true) 이거나 기본값이어야 함)
```

#### 2\. 기본 인증

전통적인 `UserCredentials` (사용자 이름, 비밀번호) 방식도 지원합니다.

```swift
let credentials = UserCredentials(username: "netify_user", password: "secure_password123")
let basicProvider = BasicAuthenticationProvider(credentials: credentials)
// ... NetifyConfiguration에 basicProvider 설정 ...
```

-----

### Netify의 목소리: 로깅과 에러 핸들링 📢

`logLevel` 설정으로 Netify의 상세한 작업 과정을 엿볼 수 있습니다. `.debug` 레벨은 cURL 명령어까지 보여주므로 문제 해결에 큰 도움이 됩니다.

에러가 발생하면 `NetworkRequestError` 타입으로 상세 정보를 알려줍니다. `handleNetifyError` 예제처럼 `switch` 문으로 다양한 상황에 대처하세요.

```swift
// (위에 제공된 handleNetifyError 함수 예시 참조)

// Task {
//     do {
//         let nonExistentUser = try await client.send(Netify.get(expecting: User.self).path("/users/nonexistentuser"))
//     } catch {
//         handleNetifyError(error, context: "Fetching Non Existent User")
//     }
// }
```

## Netify와 함께 성장하기 🌱

Netify는 여러분의 피드백을 기다립니다. 버그 리포트, 기능 제안, Pull Request 등 어떤 형태의 기여든 환영합니다\!

## 라이선스

Netify는 [MIT 라이선스](https://www.google.com/search?q=LICENSE) 하에 제공됩니다.

-----
