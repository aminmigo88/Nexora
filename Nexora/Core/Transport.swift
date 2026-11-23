import Foundation

struct HTTPReply {
    var status: Int
    var body: Data
    /// X-Log-Total from /log.
    var logTotal: Int?
}

enum StationError: LocalizedError {
    case offline
    case unreachable
    case timeout
    case badData
    case http(Int)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .offline: return "Not connected to your light controller."
        case .unreachable: return "Couldn't reach the light controller."
        case .timeout: return "The hub didn't answer in time."
        case .badData: return "Got an answer the app couldn't read."
        case .http(let code): return "The light controller answered with error \(code)."
        case .message(let text): return text
        }
    }
}

/// Form and query encoding that matches the browser's URLSearchParams (a "+" in a name stays a "+").
enum FormEncoding {
    static let allowed: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return set
    }()

    static func escape(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    static func encode(_ pairs: [(String, String)]) -> String {
        pairs.map { pair in escape(pair.0) + "=" + escape(pair.1) }.joined(separator: "&")
    }
}

/// Plain HTTP to the light controller on home Wi-Fi.
final class LocalHTTP {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 12
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 1
        session = URLSession(configuration: config)
    }

    static func normalizeHost(_ raw: String) -> String {
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = host.range(of: "://") {
            host = String(host[range.upperBound...])
        }
        while host.hasSuffix("/") {
            host.removeLast()
        }
        return host.isEmpty ? "light-controller.local" : host
    }

    func send(host: String, method: String, path: String, form: String?, timeout: TimeInterval) async throws -> HTTPReply {
        guard let url = URL(string: "http://" + host + path) else {
            throw StationError.message("The light controller address isn't valid.")
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        if let form {
            request.httpBody = Data(form.utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw StationError.badData }
        let total = http.value(forHTTPHeaderField: "X-Log-Total").flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return HTTPReply(status: http.statusCode, body: data, logTotal: total)
    }
}

/// "host", "host:port" or a pasted URL from the EMQX console.
struct BrokerAddress {
    var host: String
    var port: Int

    init(_ raw: String, defaultPort: Int) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: "://") {
            text = String(text[range.upperBound...])
        }
        if let slash = text.firstIndex(of: "/") {
            text = String(text[..<slash])
        }
        var port = defaultPort
        if let colon = text.lastIndex(of: ":"), let parsed = Int(text[text.index(after: colon)...]) {
            port = parsed
            text = String(text[..<colon])
        }
        host = text
        self.port = port
    }
}

/// Away from home: requests go app → EMQX → hub ESP32 → light controller, and back.
///
/// Topics (all under "nexora/"):
/// - app publishes  nexora/req           {"id","r","m","p","b"}  (r = reply topic, m = GET/POST, p = path, b = form body)
/// - hub publishes  nexora/res/<client>  {"id","s","t","b"}      (s = HTTP status, t = X-Log-Total, b = body text)
/// - hub publishes  nexora/status        "online" / "offline"    (retained, offline is its last will)
/// - hub publishes  nexora/info          the /api/info JSON      (retained, every 20 s)
@MainActor
final class RelayClient {
    var onHubStatus: ((Bool) -> Void)?
    var onInfo: ((Data) -> Void)?
    var onDrop: (() -> Void)?

    private let mqtt: MQTTClient
    private let clientID: String
    private var pending: [String: CheckedContinuation<HTTPReply, Error>] = [:]

    private var replyTopic: String { "nexora/res/" + clientID }

    init() {
        mqtt = MQTTClient()
        let random = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        clientID = "nexora-" + String(random.prefix(10))
        mqtt.onMessage = { [weak self] topic, payload in
            self?.handle(topic: topic, payload: payload)
        }
        mqtt.onClose = { [weak self] _ in
            self?.dropped()
        }
    }

    var isConnected: Bool { mqtt.isConnected }

    func connect(_ settings: ConnectionSettings) async throws {
        let address = BrokerAddress(settings.emqxHost, defaultPort: settings.emqxPort)
        try await mqtt.connect(host: address.host,
                               port: address.port,
                               username: settings.emqxUser,
                               password: settings.emqxPassword,
                               clientID: clientID)
        mqtt.subscribe([replyTopic, "nexora/status", "nexora/info"])
    }

    func disconnect() {
        mqtt.disconnect()
        failAll(StationError.offline)
    }

    func request(method: String, path: String, form: String?) async throws -> HTTPReply {
        guard mqtt.isConnected else { throw StationError.offline }
        let id = String(UUID().uuidString.prefix(8)).lowercased()
        var message: [String: Any] = ["id": id, "r": replyTopic, "m": method, "p": path]
        if let form {
            message["b"] = form
        }
        let payload = try JSONSerialization.data(withJSONObject: message)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HTTPReply, Error>) in
            pending[id] = continuation
            mqtt.publish(topic: "nexora/req", payload: payload)
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 9_000_000_000)
                self?.finish(id, with: .failure(StationError.timeout))
            }
        }
    }

    private func finish(_ id: String, with result: Result<HTTPReply, Error>) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(with: result)
    }

    private func failAll(_ error: Error) {
        let waiting = pending
        pending.removeAll()
        for continuation in waiting.values {
            continuation.resume(throwing: error)
        }
    }

    private func handle(topic: String, payload: Data) {
        if topic == "nexora/status" {
            let text = String(decoding: payload, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            onHubStatus?(text == "online")
        } else if topic == "nexora/info" {
            onInfo?(payload)
        } else if topic == replyTopic {
            guard let reply = try? JSONDecoder().decode(RelayReply.self, from: payload) else { return }
            let body = Data((reply.b ?? "").utf8)
            finish(reply.id, with: .success(HTTPReply(status: reply.s, body: body, logTotal: reply.t)))
        }
    }

    private func dropped() {
        failAll(StationError.offline)
        onDrop?()
    }
}

private struct RelayReply: Decodable {
    var id: String
    var s: Int
    var t: Int?
    var b: String?
}
