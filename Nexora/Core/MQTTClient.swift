import Foundation

/// Small MQTT 3.1.1 client over secure WebSocket (EMQX port 8084, path /mqtt). QoS 0 only.
@MainActor
final class MQTTClient {
    enum MQTTError: LocalizedError {
        case refused(UInt8)
        case timeout
        case closed
        case badAddress
        case network(String)

        var errorDescription: String? {
            switch self {
            case .refused(let code):
                switch code {
                case 4: return "EMQX refused the app login: wrong username or password."
                case 5: return "EMQX says the app login isn't allowed."
                default: return "EMQX refused the connection (code \(code))."
                }
            case .timeout: return "EMQX didn't answer. Check the address and port."
            case .closed: return "The connection to EMQX closed."
            case .badAddress: return "The EMQX address isn't valid."
            case .network(let text): return text
            }
        }
    }

    var onMessage: ((String, Data) -> Void)?
    var onClose: ((Error?) -> Void)?
    private(set) var isConnected = false

    private let session = URLSession(configuration: .default)
    private var task: URLSessionWebSocketTask?
    private var buffer: [UInt8] = []
    private var connectWaiter: CheckedContinuation<Void, Error>?
    private var pingTask: Task<Void, Never>?
    private var packetID: UInt16 = 1
    private var generation = 0

    func connect(host: String, port: Int, username: String, password: String, clientID: String, keepAlive: UInt16 = 30) async throws {
        teardown()
        guard !host.isEmpty, let url = URL(string: "wss://\(host):\(port)/mqtt") else {
            throw MQTTError.badAddress
        }
        let gen = generation
        let task = session.webSocketTask(with: url, protocols: ["mqtt"])
        task.maximumMessageSize = 4 * 1024 * 1024
        self.task = task
        task.resume()
        receive(on: task)
        let packet = MQTTClient.connectPacket(clientID: clientID, username: username, password: password, keepAlive: keepAlive)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connectWaiter = continuation
            send(packet)
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                self?.finishConnect(.failure(MQTTError.timeout), generation: gen)
            }
        }
        guard generation == gen, self.task != nil else { throw MQTTError.closed }
        isConnected = true
        startPing(seconds: Double(keepAlive) * 0.8)
    }

    func subscribe(_ topics: [String]) {
        var body: [UInt8] = [UInt8(packetID >> 8), UInt8(packetID & 0xFF)]
        packetID = packetID == UInt16.max ? 1 : packetID + 1
        for topic in topics {
            body.append(contentsOf: MQTTClient.encodeString(topic))
            body.append(0)   // QoS 0
        }
        send(MQTTClient.packet(type: 0x82, body: body))
    }

    func publish(topic: String, payload: Data) {
        var body = MQTTClient.encodeString(topic)
        body.append(contentsOf: payload)
        send(MQTTClient.packet(type: 0x30, body: body))
    }

    func disconnect() {
        if isConnected {
            send([0xE0, 0x00])
        }
        teardown()
    }

    // MARK: - Connection handling

    private func teardown() {
        generation += 1
        pingTask?.cancel()
        pingTask = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        buffer.removeAll()
        isConnected = false
        if let waiter = connectWaiter {
            connectWaiter = nil
            waiter.resume(throwing: MQTTError.closed)
        }
    }

    private func finishConnect(_ result: Result<Void, Error>, generation gen: Int? = nil) {
        if let gen, gen != generation { return }
        guard let waiter = connectWaiter else { return }
        connectWaiter = nil
        switch result {
        case .success:
            waiter.resume()
        case .failure(let error):
            waiter.resume(throwing: error)
            teardown()
        }
    }

    private func connectionLost(_ error: Error?) {
        if connectWaiter != nil {
            finishConnect(.failure(MQTTClient.describe(error)))
            return
        }
        let wasConnected = isConnected
        teardown()
        if wasConnected {
            onClose?(error)
        }
    }

    private static func describe(_ error: Error?) -> Error {
        guard let urlError = error as? URLError else { return error ?? MQTTError.closed }
        switch urlError.code {
        case .cannotFindHost, .dnsLookupFailed:
            return MQTTError.network("Can't find the EMQX address. Check it in More → Away access.")
        case .notConnectedToInternet:
            return MQTTError.network("This iPhone isn't online.")
        case .timedOut:
            return MQTTError.timeout
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate:
            return MQTTError.network("The secure connection to EMQX failed.")
        case .badServerResponse:
            return MQTTError.network("EMQX didn't accept the WebSocket. Check the port (8084).")
        default:
            return MQTTError.network("Couldn't connect to EMQX: \(urlError.localizedDescription)")
        }
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.task === task else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .data(let data):
                        self.buffer.append(contentsOf: data)
                    case .string(let text):
                        self.buffer.append(contentsOf: Array(text.utf8))
                    @unknown default:
                        break
                    }
                    self.parseBuffer()
                    if self.task === task {
                        self.receive(on: task)
                    }
                case .failure(let error):
                    self.connectionLost(error)
                }
            }
        }
    }

    private func send(_ bytes: [UInt8]) {
        guard let task else { return }
        task.send(.data(Data(bytes))) { [weak self] error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                guard let self, self.task === task else { return }
                self.connectionLost(error)
            }
        }
    }

    private func startPing(seconds: Double) {
        pingTask?.cancel()
        let gen = generation
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard let self, !Task.isCancelled, self.generation == gen else { return }
                self.send([0xC0, 0x00])
            }
        }
    }

    // MARK: - Packets

    private func parseBuffer() {
        while buffer.count >= 2 {
            var multiplier = 1
            var length = 0
            var index = 1
            var complete = false
            while index < buffer.count {
                let byte = Int(buffer[index])
                length += (byte & 0x7F) * multiplier
                index += 1
                if byte & 0x80 == 0 {
                    complete = true
                    break
                }
                multiplier *= 128
                if multiplier > 128 * 128 * 128 {
                    connectionLost(MQTTError.closed)
                    return
                }
            }
            guard complete else { return }
            let total = index + length
            guard buffer.count >= total else { return }
            let header = buffer[0]
            let body = Array(buffer[index..<total])
            buffer.removeFirst(total)
            handlePacket(type: header >> 4, flags: header & 0x0F, body: body)
        }
    }

    private func handlePacket(type: UInt8, flags: UInt8, body: [UInt8]) {
        switch type {
        case 2:   // CONNACK
            let code: UInt8 = body.count >= 2 ? body[1] : 255
            finishConnect(code == 0 ? .success(()) : .failure(MQTTError.refused(code)))
        case 3:   // PUBLISH
            guard body.count >= 2 else { return }
            let topicLength = Int(body[0]) << 8 | Int(body[1])
            guard body.count >= 2 + topicLength else { return }
            let topic = String(decoding: body[2..<(2 + topicLength)], as: UTF8.self)
            var offset = 2 + topicLength
            let qos = (flags >> 1) & 0x03
            if qos > 0 {
                guard body.count >= offset + 2 else { return }
                let high = body[offset]
                let low = body[offset + 1]
                offset += 2
                if qos == 1 {
                    send([0x40, 0x02, high, low])   // PUBACK
                }
            }
            let payload = Data(body[offset...])
            onMessage?(topic, payload)
        default:
            break   // SUBACK, PUBACK, PINGRESP
        }
    }

    static func encodeString(_ text: String) -> [UInt8] {
        let bytes = Array(text.utf8)
        let count = min(bytes.count, 65_535)
        var out: [UInt8] = [UInt8(count >> 8), UInt8(count & 0xFF)]
        out.append(contentsOf: bytes.prefix(count))
        return out
    }

    static func encodeLength(_ value: Int) -> [UInt8] {
        var out: [UInt8] = []
        var remaining = value
        repeat {
            var byte = UInt8(remaining % 128)
            remaining /= 128
            if remaining > 0 {
                byte |= 0x80
            }
            out.append(byte)
        } while remaining > 0
        return out
    }

    static func packet(type: UInt8, body: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [type]
        out.append(contentsOf: encodeLength(body.count))
        out.append(contentsOf: body)
        return out
    }

    static func connectPacket(clientID: String, username: String, password: String, keepAlive: UInt16) -> [UInt8] {
        var body = encodeString("MQTT")
        body.append(4)      // protocol level: MQTT 3.1.1
        body.append(0xC2)   // username + password + clean session
        body.append(UInt8(keepAlive >> 8))
        body.append(UInt8(keepAlive & 0xFF))
        body.append(contentsOf: encodeString(clientID))
        body.append(contentsOf: encodeString(username))
        body.append(contentsOf: encodeString(password))
        return packet(type: 0x10, body: body)
    }
}
