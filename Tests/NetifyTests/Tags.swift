import Testing

extension Tag {
    // 범주
    @Tag static var unit: Self
    @Tag static var integration: Self
    @Tag static var e2e: Self

    // 컴포넌트
    @Tag static var core: Self           // URL/Request 빌더, 에러 매핑
    @Tag static var auth: Self
    @Tag static var dsl: Self
    @Tag static var cache: Self
    @Tag static var plugin: Self
    @Tag static var logging: Self
    @Tag static var retry: Self
    @Tag static var body: Self

    // 속성
    @Tag static var fast: Self
    @Tag static var slow: Self
    @Tag static var ios: Self
}

