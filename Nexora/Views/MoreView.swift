import SwiftUI

enum SettingsSheet: String, Identifiable {
    case controller, relay, adafruit, thingSpeak, widget

    var id: String { rawValue }

    var title: String {
        switch self {
        case .controller: return "Light controller"
        case .relay: return "Away access"
        case .adafruit: return "Adafruit IO"
        case .thingSpeak: return "ThingSpeak"
        case .widget: return "Widget"
        }
    }
}

struct MoreView: View {
    @Environment(Station.self) var station
    @Environment(SettingsStore.self) var settings
    @Environment(HistoryStore.self) var history
    @State var sheet: SettingsSheet?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    TopBar()
                    PageHeading(eyebrow: "Device settings",
                                title: "Made for your setup.",
                                subtitle: Text("Log, connections and versions"))
                    NavigationLink {
                        LogView()
                    } label: {
                        logRow
                    }
                    .buttonStyle(.plain)
                    connectionCard
                    aboutCard
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Theme.background)
            .navigationTitle("More")
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $sheet) { which in
                SettingsEditor(kind: which)
                    .environment(station)
                    .environment(settings)
            }
        }
    }

    var logRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color(hex: 0x1B7C70))
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: 0xE4F4EB)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Live log")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("Everything your ESP32 prints")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
        }
        .card(padding: 16)
        .contentShape(Rectangle())
    }

    var connectionCard: some View {
        let controller = controllerStatus
        let relay = station.relayStatus
        let adafruit = adafruitStatus
        let thingSpeak = thingSpeakStatus
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Connection",
                          subtitle: settings.usesFileFallback
                            ? "Saved in the app's protected storage (the Keychain wasn't available)"
                            : "Passwords stay in this iPhone's Keychain")
                .padding(.bottom, 8)
            SettingsRow(title: "Light controller", detail: LocalHTTP.normalizeHost(settings.value.controllerHost),
                        status: controller.text, ok: controller.ok) {
                sheet = .controller
            }
            SettingsRow(title: "Away access", detail: "EMQX", status: relay.text, ok: relay.ok) {
                sheet = .relay
            }
            SettingsRow(title: "Adafruit IO", detail: "Live readings · group \(settings.value.adafruitGroupKey)",
                        status: adafruit.text, ok: adafruit.ok) {
                sheet = .adafruit
            }
            SettingsRow(title: "ThingSpeak", detail: settings.value.thingSpeakChannel.isEmpty ? "Channel" : "Channel \(settings.value.thingSpeakChannel)",
                        status: thingSpeak.text, ok: thingSpeak.ok) {
                sheet = .thingSpeak
            }
            SettingsRow(title: "Widget", detail: "Sun and moon location",
                        status: settings.value.homeConfigured ? "location set" : "not set",
                        ok: settings.value.homeConfigured) {
                sheet = .widget
            }
        }
        .card()
    }

    var controllerStatus: (text: String, ok: Bool) {
        switch station.link {
        case .home: return ("online", true)
        case .connecting: return ("checking", false)
        case .away, .offline: return ("not on this Wi-Fi", false)
        }
    }

    var adafruitStatus: (text: String, ok: Bool) {
        guard settings.value.adafruitConfigured else { return ("not set up", false) }
        if station.adafruit.problem != nil { return ("check settings", false) }
        if station.adafruit.readings.isEmpty { return ("waiting", false) }
        return ("live", true)
    }

    var thingSpeakStatus: (text: String, ok: Bool) {
        guard settings.value.thingSpeakConfigured else { return ("not set up", false) }
        if history.problem != nil { return ("check key", false) }
        return ("key saved", true)
    }

    var aboutCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "About")
                .padding(.bottom, 8)
            InfoRow(title: "Light controller", value: station.info?.version ?? "—", mono: true)
            InfoRow(title: "App", value: "Nexora \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))", mono: false)
        }
        .card()
    }
}

struct SettingsRow: View {
    let title: String
    let detail: String
    let status: String
    let ok: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(status)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(ok ? Theme.tealText : Color(hex: 0x8A5A14))
                    .multilineTextAlignment(.trailing)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 58)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.divider).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    let mono: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 8)
            Text(value)
                .font(mono ? .system(size: 12, design: .monospaced) : .system(size: 13))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .textSelection(.enabled)
        }
        .frame(minHeight: 54)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.divider).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Editing connection settings

struct SettingsEditor: View {
    let kind: SettingsSheet
    @Environment(SettingsStore.self) var store
    @Environment(Station.self) var station
    @Environment(\.dismiss) var dismiss
    @State var draft = ConnectionSettings()
    @State var loaded = false
    @State var saveFailed = false
    @State var locator = LocationFetcher()
    @State var locating = false
    @State var locationError: String?

    var body: some View {
        NavigationStack {
            Form {
                fields
                if saveFailed {
                    Section {
                        Text("Couldn't save. Try again.")
                            .foregroundStyle(Theme.dangerText)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                if !loaded {
                    draft = store.value
                    loaded = true
                }
            }
        }
        .tint(Theme.tealText)
    }

    @ViewBuilder
    var fields: some View {
        switch kind {
        case .controller:
            Section {
                TextField("light-controller.local", text: $draft.controllerHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            } header: {
                Text("Address on home Wi-Fi")
            } footer: {
                Text("Its name (light-controller.local) or its IP address. At home the app talks to it directly.")
            }
        case .relay:
            Section {
                TextField("Address", text: $draft.emqxHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("Port", value: $draft.emqxPort, format: IntegerFormatStyle<Int>().grouping(.never))
                    .keyboardType(.numberPad)
            } header: {
                Text("EMQX deployment")
            } footer: {
                Text("From your deployment's Connection Information. The app uses secure WebSocket, port 8084.")
            }
            Section {
                TextField("Username", text: $draft.emqxUser)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $draft.emqxPassword)
            } header: {
                Text("App login")
            } footer: {
                if let error = station.relayError {
                    Text(error)
                        .foregroundStyle(Theme.dangerText)
                } else {
                    Text("The app user from your deployment's Authentication list (not the hub's).")
                }
            }
        case .adafruit:
            Section {
                TextField("Username", text: $draft.adafruitUser)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("AIO Key", text: $draft.adafruitKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Account")
            } footer: {
                Text("On io.adafruit.com, tap the key icon at the top to see your Username and Active Key.")
            }
            Section {
                TextField("room-temperature", text: $draft.adafruitGroup)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Group")
            } footer: {
                if let problem = station.adafruit.problem {
                    Text(problem)
                        .foregroundStyle(Theme.dangerText)
                } else {
                    Text("The group your ESP32 uploads to every 20 s. Your firmware uses room-temperature.")
                }
            }
        case .thingSpeak:
            Section {
                TextField("Channel ID", text: $draft.thingSpeakChannel)
                    .keyboardType(.numberPad)
            } header: {
                Text("Channel")
            }
            Section {
                SecureField("Read API Key", text: $draft.thingSpeakKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Read API Key")
            } footer: {
                Text("On ThingSpeak: open your channel → API Keys tab → copy the Read API Key.")
            }
        case .widget:
            Section {
                Button {
                    Task { await useCurrentLocation() }
                } label: {
                    HStack {
                        Text(locating ? "Finding your location…" : "Use my current location")
                        Spacer()
                        if locating {
                            ProgressView()
                        }
                    }
                }
                .disabled(locating)
                if let latitude = draft.homeLatitude, let longitude = draft.homeLongitude {
                    LabeledContent("Saved spot", value: String(format: "%.2f, %.2f", latitude, longitude))
                }
            } header: {
                Text("Sun and moon")
            } footer: {
                if let locationError {
                    Text(locationError)
                        .foregroundStyle(Theme.dangerText)
                } else {
                    Text("Tap this once at home, then Save. The widget gets each day's sunrise, sunset and moon phase for this spot from MET Norway. Only a rounded spot (about 1 km) is saved.")
                }
            }
        }
    }

    func useCurrentLocation() async {
        locating = true
        locationError = nil
        defer { locating = false }
        do {
            let location = try await locator.current()
            draft.homeLatitude = (location.coordinate.latitude * 100).rounded() / 100
            draft.homeLongitude = (location.coordinate.longitude * 100).rounded() / 100
        } catch {
            locationError = (error as? LocalizedError)?.errorDescription ?? "Couldn't get your location."
        }
    }

    func save() {
        var next = draft
        next.controllerHost = LocalHTTP.normalizeHost(next.controllerHost)
        let broker = BrokerAddress(next.emqxHost, defaultPort: next.emqxPort)
        next.emqxHost = broker.host
        next.emqxPort = broker.port
        next.emqxUser = next.emqxUser.trimmingCharacters(in: .whitespacesAndNewlines)
        next.thingSpeakChannel = next.thingSpeakChannel.trimmingCharacters(in: .whitespacesAndNewlines)
        next.thingSpeakKey = next.thingSpeakKey.trimmingCharacters(in: .whitespacesAndNewlines)
        next.adafruitUser = next.adafruitUser.trimmingCharacters(in: .whitespacesAndNewlines)
        next.adafruitKey = next.adafruitKey.trimmingCharacters(in: .whitespacesAndNewlines)
        next.adafruitGroup = next.adafruitGroupKey
        guard store.save(next) else {
            saveFailed = true
            return
        }
        station.settingsChanged()
        dismiss()
    }
}
