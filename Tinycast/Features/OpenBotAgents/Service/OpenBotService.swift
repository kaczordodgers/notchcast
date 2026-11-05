import Foundation

struct OpenBotCredentials: Sendable {
    let baseURL: URL
    let token: String

    init(url: String, token: String) throws {
        guard let parts = URLComponents(string: url), parts.scheme == "http", parts.host == "127.0.0.1",
              let port = parts.port, (1...65535).contains(port), parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, parts.path.isEmpty || parts.path == "/",
              let baseURL = parts.url else { throw OpenBotFailure.invalidURL }
        guard !token.isEmpty, !token.contains("\r"), !token.contains("\n") else { throw OpenBotFailure.off }
        self.baseURL = baseURL
        self.token = token
    }

    @concurrent
    static func read() async throws -> Self {
        let folder = ProcessInfo.processInfo.environment["OPENBOT_AUTOMATION_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/OpenBot/automation")
        guard let url = try? String(contentsOf: folder.appendingPathComponent("url"), encoding: .utf8),
              let token = try? String(contentsOf: folder.appendingPathComponent("token"), encoding: .utf8)
        else { throw OpenBotFailure.off }
        return try Self(url: url.trimmingCharacters(in: .whitespacesAndNewlines),
                        token: token.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

protocol OpenBotTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

final class OpenBotURLTransport: NSObject, OpenBotTransport, URLSessionTaskDelegate {
    private let session: URLSession

    override init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 15
        session = URLSession(configuration: configuration)
        super.init()
    }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request, delegate: self)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct OpenBotService: Sendable {
    let transport: any OpenBotTransport
    let credentials: @Sendable () async throws -> OpenBotCredentials

    init(transport: any OpenBotTransport = OpenBotURLTransport(),
         credentials: @escaping @Sendable () async throws -> OpenBotCredentials = OpenBotCredentials.read) {
        self.transport = transport
        self.credentials = credentials
    }

    func agents() async throws -> [OpenBotAgent] { try await request(["agents"]) }

    func pending(agent: String) async throws -> OpenBotPending {
        try await request(["agents", agent, "pending"])
    }

    func delivery(agent: String, id: String) async throws -> OpenBotDelivery {
        try await request(["agents", agent, "deliveries", id])
    }

    func send(agent: String, text: String) async throws -> OpenBotReceipt {
        struct Message: Encodable { let text: String; let clientMessageId: UUID }
        let body = try JSONEncoder().encode(Message(text: text, clientMessageId: UUID()))
        guard body.count <= 32768 else { throw OpenBotFailure.oversized }
        return try await request(["agents", agent, "messages"], body: body)
    }

    private func request<Value: Decodable & Sendable>(_ path: [String], body: Data? = nil) async throws -> Value {
        do {
            for attempt in 0...1 {
                try Task.checkCancellation()
                let access = try await credentials()
                var url = access.baseURL.appendingPathComponent("v1")
                for component in path {
                    guard !component.isEmpty, component != ".", component != "..",
                          !component.contains("/"), !component.contains("%") else { throw OpenBotFailure.input }
                    url.appendPathComponent(component)
                }
                var request = URLRequest(url: url)
                request.httpMethod = body == nil ? "GET" : "POST"
                request.httpBody = body
                request.setValue("Bearer " + access.token, forHTTPHeaderField: "Authorization")
                if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
                let (data, status) = try await transport.send(request)
                try Task.checkCancellation()
                if status == 401 && attempt == 0 { continue }
                switch status {
                case body == nil ? 200 : 202:
                    guard let value = try? JSONDecoder().decode(Value.self, from: data) else {
                        throw OpenBotFailure.malformed
                    }
                    return value
                case 400: throw OpenBotFailure.input
                case 401: throw OpenBotFailure.unauthorized
                case 403: throw OpenBotFailure.forbidden
                case 404: throw OpenBotFailure.missing
                case 405: throw OpenBotFailure.method
                case 409: throw OpenBotFailure.conflict
                case 413: throw OpenBotFailure.oversized
                case 415: throw OpenBotFailure.mediaType
                case 429: throw OpenBotFailure.rateLimited
                case 500...599: throw OpenBotFailure.server
                default: throw OpenBotFailure.unexpected
                }
            }
            throw OpenBotFailure.unauthorized
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as OpenBotFailure {
            throw failure
        } catch {
            try Task.checkCancellation()
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw OpenBotFailure.unreachable
        }
    }
}
