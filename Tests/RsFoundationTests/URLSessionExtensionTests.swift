import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import RsFoundation
import Testing

/// 为 URLSession+Extension 模拟响应的 URLProtocol;handler 由测试逐个注入。
final class MockURLProtocol: URLProtocol {
    /// 由 startLoading 调用,返回 (状态码, 响应体);抛错则模拟传输失败。
    /// 仅供 `.serialized` 的测试套件使用,避免并发交叉污染。
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?

    /// 记录协议层收到的请求,供测试断言方法、头、超时与请求体。
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)

        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        do {
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/plain"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite("URLSession Extension Tests", .serialized)
struct URLSessionExtensionTests {
    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func resetMock() {
        MockURLProtocol.handler = nil
        MockURLProtocol.requests = []
    }

    /// URLSession 会把请求体挪进 httpBodyStream,两处都取一下。
    private func bodyData(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    // MARK: async get

    @Test("get returns body on 2xx")
    func testGetSuccess() async {
        defer { resetMock() }
        let expected = Data("hello".utf8)
        MockURLProtocol.handler = { _ in (200, expected) }

        let (success, data) = await makeSession().get(urlString: "http://example.com/data")

        #expect(success)
        #expect(data == expected)
        #expect(MockURLProtocol.requests.count == 1)
        #expect(MockURLProtocol.requests.first?.httpMethod == "GET")
    }

    @Test("get treats 204 as success")
    func testGetNoContent() async {
        defer { resetMock() }
        MockURLProtocol.handler = { _ in (204, Data()) }

        let (success, data) = await makeSession().get(urlString: "http://example.com/data")

        #expect(success)
        #expect(data.isEmpty)
    }

    @Test("get reports non-2xx failure with the error body")
    func testGetServerError() async {
        defer { resetMock() }
        let errorBody = Data("boom".utf8)
        MockURLProtocol.handler = { _ in (500, errorBody) }

        let (success, data) = await makeSession().get(urlString: "http://example.com/data")

        #expect(!success)
        #expect(data == errorBody)
    }

    @Test("get applies the timeout to the request")
    func testGetAppliesTimeout() async {
        defer { resetMock() }
        MockURLProtocol.handler = { _ in (200, Data()) }

        _ = await makeSession().get(urlString: "http://example.com/data", timeout: 7)

        #expect(MockURLProtocol.requests.first?.timeoutInterval == 7)
    }

    @Test("get with malformed URL fails with the error description as data")
    func testGetBadURL() async {
        defer { resetMock() }
        MockURLProtocol.handler = { _ in (200, Data()) }

        // 路径里的空格会被 corelibs 自动编码,主机名里的空格才是非法 URL。
        let (success, data) = await makeSession().get(urlString: "http://exa mple.com/data")

        #expect(!success)
        #expect(!data.isEmpty)
        #expect(MockURLProtocol.requests.isEmpty)
    }

    @Test("get returns the error description on transport failure")
    func testGetTransportError() async {
        defer { resetMock() }
        // 不挂 mock,走真实网络:端口 9(discard)通常无人监听,本机连接立即被拒。
        let plain = URLSession(configuration: .ephemeral)
        let (success, data) = await plain.get(urlString: "http://127.0.0.1:9/open", timeout: 2)

        #expect(!success)
        #expect(!data.isEmpty)
        #expect(MockURLProtocol.requests.isEmpty)
    }

    // MARK: async put

    private struct Payload: Codable, Equatable {
        let title: String
        let value: Int
    }

    @Test("put encodes the body as JSON and returns body on 2xx")
    func testPutSuccess() async throws {
        defer { resetMock() }
        let expected = Data("saved".utf8)
        MockURLProtocol.handler = { _ in (201, expected) }

        let (success, data) = await makeSession().put(
            urlString: "http://example.com/defaults", body: Payload(title: "Default", value: 3))

        #expect(success)
        #expect(data == expected)

        let request = MockURLProtocol.requests.first
        #expect(request?.httpMethod == "PUT")
        #expect(request?.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(try JSONDecoder().decode(Payload.self, from: bodyData(of: request!)) == Payload(title: "Default", value: 3))
    }

    @Test("put reports non-2xx failure with the error body")
    func testPutServerError() async {
        defer { resetMock() }
        let errorBody = Data("conflict".utf8)
        MockURLProtocol.handler = { _ in (409, errorBody) }

        let (success, data) = await makeSession().put(
            urlString: "http://example.com/defaults", body: Payload(title: "x", value: 0))

        #expect(!success)
        #expect(data == errorBody)
    }

    private struct BrokenBody: Encodable {
        func encode(to encoder: Encoder) throws { throw URLError(.cannotDecodeContentData) }
    }

    @Test("put fails with the error description when encoding fails")
    func testPutEncodingFailure() async {
        defer { resetMock() }
        MockURLProtocol.handler = { _ in (200, Data()) }

        let (success, data) = await makeSession().put(
            urlString: "http://example.com/defaults", body: BrokenBody())

        #expect(!success)
        #expect(!data.isEmpty)
        #expect(MockURLProtocol.requests.isEmpty)
    }

    // MARK: async delete

    @Test("delete returns success on 204")
    func testDeleteSuccess() async {
        defer { resetMock() }
        MockURLProtocol.handler = { _ in (204, Data()) }

        let (success, _) = await makeSession().delete(urlString: "http://example.com/item/1")

        #expect(success)
        #expect(MockURLProtocol.requests.first?.httpMethod == "DELETE")
    }

    @Test("delete reports non-2xx failure with the error body")
    func testDeleteServerError() async {
        defer { resetMock() }
        let errorBody = Data("missing".utf8)
        MockURLProtocol.handler = { _ in (404, errorBody) }

        let (success, data) = await makeSession().delete(urlString: "http://example.com/item/1")

        #expect(!success)
        #expect(data == errorBody)
    }

    // MARK: main-actor callbacks

    /// 挂起当前测试,直到主线程回调触发并带回结果;本工具链的 confirmation 不等待
    /// 注册之后才发生的异步回调,故用 AsyncStream 充当一次性信号。
    private func awaitMainActorCallback<Result: Sendable>(
        _ register: @escaping (@escaping @MainActor @Sendable (Result) -> Void) -> Void
    ) async -> Result {
        let stream = AsyncStream<Result> { continuation in
            register { continuation.yield($0) }
        }
        return await stream.first { _ in true }!
    }

    @Test("get callback delivers the result on the main actor")
    func testGetCallback() async {
        defer { resetMock() }
        let expected = Data("hello".utf8)
        MockURLProtocol.handler = { _ in (200, expected) }

        let (success, data): (Bool, Data) = await awaitMainActorCallback { completion in
            makeSession().get(urlString: "http://example.com/data") { success, data in
                MainActor.assertIsolated()
                completion((success, data))
            }
        }

        #expect(success)
        #expect(data == expected)
    }

    @Test("delete callback delivers failures on the main actor")
    func testDeleteCallback() async {
        defer { resetMock() }
        let errorBody = Data("missing".utf8)
        MockURLProtocol.handler = { _ in (404, errorBody) }

        let (success, data): (Bool, Data) = await awaitMainActorCallback { completion in
            makeSession().delete(urlString: "http://example.com/item/1") { success, data in
                MainActor.assertIsolated()
                completion((success, data))
            }
        }

        #expect(!success)
        #expect(data == errorBody)
    }
}
