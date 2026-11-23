import Foundation
import Network
import Observation
import UIKit

/// The app's single source of truth: how we reach the light controller, and what it last told us.
@Observable
@MainActor
final class Station {
    enum Link: Equatable {
        case connecting, home, away, offline
    }

    private(set) var link: Link = .connecting
    private(set) var linkNote: String?
    private(set) var relayError: String?
    private(set) var hubOnline: Bool?

    private(set) var light: LightState?
    private(set) var ir: IRState?
    private(set) var remotes: [RemoteProfile] = []
    private(set) var info: StationInfo?
    private(set) var infoAt: Date?
    private(set) var logLines: [LogLine] = []
    var toast: String?

    let settings: SettingsStore
    let history: HistoryStore
    let adafruit: AdafruitStore

    private let local: LocalHTTP
    private let relay: RelayClient
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var refreshAgain = false
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var lightSeq = 0
    @ObservationIgnored private var infoMissingAt: Date?
    @ObservationIgnored private var logCursor = 0
    @ObservationIgnored private var logPartial: [UInt8] = []
    @ObservationIgnored private var logNextID = 0
    @ObservationIgnored private var logPrimed = false

    init() {
        settings = SettingsStore()
        history = HistoryStore()
        adafruit = AdafruitStore()
        local = LocalHTTP()
        relay = RelayClient()
        relay.onHubStatus = { [weak self] online in
            self?.hubStatusChanged(online)
        }
        relay.onInfo = { [weak self] data in
            self?.receiveInfo(data)
        }
        relay.onDrop = { [weak self] in
            self?.relayDropped()
        }
        startPathMonitor()
    }

    var isConnected: Bool { link == .home || link == .away }

    // MARK: - Finding the light controller

    func refreshLink() async {
        if refreshing {
            refreshAgain = true
            return
        }
        refreshing = true
        repeat {
            refreshAgain = false
            await checkLink()
        } while refreshAgain
        refreshing = false
    }

    private func checkLink() async {
        let current = settings.value
        let host = LocalHTTP.normalizeHost(current.controllerHost)
        if let reply = try? await local.send(host: host, method: "GET", path: "/api/state", form: nil, timeout: 2.5),
           reply.status == 200,
           let state = try? Station.decode(LightState.self, from: reply.body) {
            light = state
            if link != .home {
                link = .home
                linkNote = nil
                relay.disconnect()
                hubOnline = nil
            }
            return
        }

        guard current.relayConfigured else {
            relay.disconnect()
            hubOnline = nil
            link = .offline
            linkNote = "Not on your home Wi-Fi, and away access isn't set up yet (More → Away access)."
            return
        }

        if !relay.isConnected {
            hubOnline = nil
            do {
                try await relay.connect(current)
                relayError = nil
            } catch {
                relayError = Station.message(for: error)
                link = .offline
                linkNote = relayError
                return
            }
            // EMQX sends the hub's retained status right after subscribing.
            var waited = 0
            while hubOnline == nil && waited < 20 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                waited += 1
            }
        }
        applyRelayLink()
    }

    private func applyRelayLink() {
        switch hubOnline {
        case .some(true):
            link = .away
            linkNote = nil
        case .some(false):
            link = .offline
            linkNote = "Your hub ESP32 is offline."
        case .none:
            link = .offline
            linkNote = "Your hub ESP32 hasn't connected to EMQX yet."
        }
    }

    private func hubStatusChanged(_ online: Bool) {
        hubOnline = online
        if link != .home && relay.isConnected && !refreshing {
            applyRelayLink()
        }
    }

    private func relayDropped() {
        guard link != .home else { return }
        link = .connecting
        Task { await refreshLink() }
    }

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshLink()
            }
        }
        monitor.start(queue: DispatchQueue(label: "nexora.network"))
        pathMonitor = monitor
    }

    func appBecameActive() {
        Task { await refreshLink() }
    }

    func appWentToBackground() {
        if link == .away {
            relay.disconnect()
            hubOnline = nil
            link = .connecting
        }
    }

    func settingsChanged() {
        relay.disconnect()
        hubOnline = nil
        relayError = nil
        infoMissingAt = nil
        link = .connecting
        Task { await refreshLink() }
        Task { await history.refresh(settings: settings.value, force: true) }
        Task { await adafruit.refresh(settings: settings.value, force: true) }
    }

    var relayStatus: (text: String, ok: Bool) {
        guard settings.value.relayConfigured else { return ("not set up", false) }
        switch link {
        case .away: return ("hub online", true)
        case .home: return ("ready", true)
        case .connecting: return ("checking", false)
        case .offline:
            if relayError != nil { return ("can't connect", false) }
            if hubOnline == false { return ("hub offline", false) }
            return ("waiting for hub", false)
        }
    }

    // MARK: - Requests

    func request(_ path: String, method: String = "GET", form: String? = nil) async throws -> HTTPReply {
        switch link {
        case .home:
            do {
                let host = LocalHTTP.normalizeHost(settings.value.controllerHost)
                return try await local.send(host: host, method: method, path: path, form: form, timeout: 6)
            } catch {
                Task { await refreshLink() }
                throw StationError.unreachable
            }
        case .away:
            return try await relay.request(method: method, path: path, form: form)
        case .connecting, .offline:
            throw StationError.offline
        }
    }

    /// Decodes JSON, replacing any broken UTF-8 from the firmware instead of failing.
    static func decode<T: Decodable>(_ type: T.Type, from body: Data) throws -> T {
        let cleaned = Data(String(decoding: body, as: UTF8.self).utf8)
        return try JSONDecoder().decode(T.self, from: cleaned)
    }

    func fetch<T: Decodable>(_ type: T.Type, _ path: String, method: String = "GET", form: String? = nil) async throws -> T {
        let reply = try await request(path, method: method, form: form)
        guard (200..<300).contains(reply.status) else {
            if let apiError = try? Station.decode(APIErrorBody.self, from: reply.body) {
                throw StationError.message(apiError.error)
            }
            throw StationError.http(reply.status)
        }
        do {
            return try Station.decode(T.self, from: reply.body)
        } catch {
            throw StationError.badData
        }
    }

    // MARK: - Light

    func pollLight() async {
        guard isConnected else { return }
        let seq = lightSeq
        if let state = try? await fetch(LightState.self, "/api/state"), seq == lightSeq {
            light = state
        }
    }

    func setLight(_ query: String) async {
        lightSeq += 1
        let seq = lightSeq
        do {
            let state = try await fetch(LightState.self, "/api/state?" + query)
            if seq == lightSeq {
                light = state
            }
        } catch {
            show(error)
        }
    }

    var sceneNames: [String] {
        if let names = info?.scenes, !names.isEmpty {
            return names
        }
        return SceneCatalog.names
    }

    // MARK: - IR

    func pollIR() async {
        guard isConnected else { return }
        if let state = try? await fetch(IRState.self, "/api/ir/state") {
            ir = state
        }
    }

    func irCommand(_ query: String) async {
        do {
            ir = try await fetch(IRState.self, "/api/ir/cmd?" + query)
        } catch {
            show(error)
        }
    }

    @discardableResult
    func irTry(_ code: String) async -> Bool {
        do {
            ir = try await fetch(IRState.self, "/api/ir/send?code=" + FormEncoding.escape(code))
            return true
        } catch {
            show(error)
            return false
        }
    }

    // MARK: - Remotes

    @discardableResult
    func loadRemotes() async -> Bool {
        guard isConnected else { return false }
        do {
            let payload = try await fetch(RemotesPayload.self, "/api/remotes")
            remotes = payload.remotes.map { $0.normalized() }
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func saveRemote(_ index: Int, _ profile: RemoteProfile) async -> Bool {
        let clean = profile.normalized()
        var pairs: [(String, String)] = [("r", String(index)), ("name", clean.name)]
        for k in 0..<5 {
            let key = clean.keys[k]
            pairs.append(("n\(k)", key.name))
            pairs.append(("o\(k)", key.orig.trimmingCharacters(in: .whitespacesAndNewlines)))
            pairs.append(("g\(k)", key.gen.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        do {
            let payload = try await fetch(RemotesPayload.self, "/api/remotes/save", method: "POST", form: FormEncoding.encode(pairs))
            remotes = payload.remotes.map { $0.normalized() }
            return true
        } catch {
            show(error)
            return false
        }
    }

    // MARK: - Readings

    /// Firmware before 2026-11-23-api-info has no /api/info; a 404 is remembered for a minute.
    func pollInfo() async {
        defer { dropStaleInfo() }
        guard isConnected else { return }
        if let missing = infoMissingAt, Date().timeIntervalSince(missing) < 60 { return }
        guard let reply = try? await request("/api/info") else { return }
        if reply.status == 404 {
            infoMissingAt = Date()
            return
        }
        guard reply.status == 200, let fresh = try? Station.decode(StationInfo.self, from: reply.body) else { return }
        infoMissingAt = nil
        info = fresh
        infoAt = Date()
    }

    /// When the ESP32 stops answering, Overview moves on to Adafruit IO, then ThingSpeak.
    private func dropStaleInfo() {
        if let infoAt, Date().timeIntervalSince(infoAt) > 20 {
            self.infoAt = nil
        }
    }

    private func receiveInfo(_ data: Data) {
        guard let fresh = try? Station.decode(StationInfo.self, from: data) else { return }
        info = fresh
        infoAt = Date()
    }

    /// In order: the ESP32's own /api/info, then Adafruit IO, then ThingSpeak.
    var readings: ReadingsSnapshot {
        if let info, let infoAt, Date().timeIntervalSince(infoAt) <= 20 {
            return ReadingsSnapshot(indoor: info.indoor, outdoor: info.outdoor, bmeTemp: info.bmeTemp,
                                    humidity: info.humidity, pressure: info.pressure, eco2: info.eco2,
                                    tvoc: info.tvoc, at: infoAt, source: .controller)
        }
        let adafruitSnapshot = adafruitReadings
        if adafruit.problem == nil, let adafruitSnapshot {
            return adafruitSnapshot
        }
        if let last = history.latest {
            return ReadingsSnapshot(indoor: last.indoor, outdoor: last.outdoor, bmeTemp: last.bmeTemp,
                                    humidity: last.humidity, pressure: last.pressure, eco2: last.eco2,
                                    tvoc: last.tvoc, at: last.date, source: .thingSpeak)
        }
        // Adafruit IO's last values, even though its latest refresh failed, beat showing nothing.
        return adafruitSnapshot ?? ReadingsSnapshot()
    }

    private var adafruitReadings: ReadingsSnapshot? {
        guard let date = adafruit.latestDate else { return nil }
        let live = adafruit.readings
        return ReadingsSnapshot(indoor: live[.indoor]?.value, outdoor: live[.outdoor]?.value,
                                bmeTemp: live[.bmeTemp]?.value, humidity: live[.humidity]?.value,
                                pressure: live[.pressure]?.value, eco2: live[.eco2]?.value,
                                tvoc: live[.tvoc]?.value, at: date, source: .adafruit)
    }

    // MARK: - Log

    func pollLog() async {
        guard isConnected else { return }
        guard let reply = try? await request("/log?since=\(logCursor)"), reply.status == 200 else { return }
        let total = reply.logTotal ?? (logCursor + reply.body.count)
        if total < logCursor {
            // The byte counter went back: the controller restarted. Start again from its first byte.
            logCursor = 0
            logPartial.removeAll()
            appendMarker("The light controller restarted")
            return
        }
        var bytes = [UInt8](reply.body)
        let fellBehind = total - logCursor > 8192
        if !logPrimed || fellBehind {
            if fellBehind {
                logPartial.removeAll()
            }
            if total > 8192, let newline = bytes.firstIndex(of: 10) {
                bytes.removeSubrange(0...newline)
            }
        }
        ingest(bytes, backlog: !logPrimed)
        logCursor = total
        logPrimed = true
    }

    private func ingest(_ bytes: [UInt8], backlog: Bool) {
        var data = logPartial
        data.append(contentsOf: bytes)
        logPartial.removeAll()
        let now = Date()
        var fresh: [LogLine] = []
        var start = 0
        var index = 0
        while index < data.count {
            if data[index] == 10 {
                var line = Array(data[start..<index])
                if line.last == 13 {
                    line.removeLast()
                }
                if let entry = makeLine(String(decoding: line, as: UTF8.self), time: backlog ? nil : now) {
                    fresh.append(entry)
                }
                start = index + 1
            }
            index += 1
        }
        if start < data.count {
            logPartial = Array(data[start..<data.count])
        }
        guard !fresh.isEmpty else { return }
        logLines.append(contentsOf: fresh)
        if logLines.count > 1500 {
            logLines.removeFirst(logLines.count - 1500)
        }
    }

    private func makeLine(_ text: String, time: Date?) -> LogLine? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.allSatisfy({ "═=-.".contains($0) }) { return nil }
        let line = LogLine(id: logNextID, time: time, text: text, kind: LogKind.classify(trimmed))
        logNextID += 1
        return line
    }

    private func appendMarker(_ text: String) {
        logLines.append(LogLine(id: logNextID, time: Date(), text: "— \(text) —", kind: .system))
        logNextID += 1
    }

    // MARK: - Messages

    func show(_ message: String) {
        toast = message
        UIAccessibility.post(notification: .announcement, argument: message)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func show(_ error: Error) {
        show(Station.message(for: error))
    }

    static func message(for error: Error) -> String {
        if let described = error as? LocalizedError, let text = described.errorDescription {
            return text
        }
        return error.localizedDescription
    }
}
