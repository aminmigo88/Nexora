import SwiftUI

enum IRScanMode: String, Hashable {
    case flipper, brute
}

struct MapTarget: Identifiable, Hashable {
    let code: String
    var id: String { code }
}

struct IRFinderView: View {
    @Environment(Station.self) var station
    @State var selectedMode: IRScanMode = .brute
    @State var speed: Double = 300
    @State var startAddress: Double = 0
    @State var editingSpeed = false
    @State var editingStart = false
    @State var manualCode = ""
    @State var manualError: String?
    @State var mapTarget: MapTarget?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                TopBar()
                PageHeading(eyebrow: "Infrared toolkit",
                            title: "Find the signal.",
                            subtitle: Text("Sweep the Flipper fan list or every NEC code, then pin the one your device reacts to."))
                OfflineCard()
                VStack(spacing: 14) {
                    explorerCard
                    tuningCard
                    nowSendingCard
                    tryCard
                    sentCard
                    receivedCard
                }
                .disabled(!station.isConnected || station.ir == nil)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .refreshable { await station.pollIR() }
        .task(id: station.link) {
            if station.remotes.isEmpty {
                await station.loadRemotes()
            }
            while !Task.isCancelled {
                await station.pollIR()
                try? await Task.sleep(nanoseconds: station.link == .away ? 1_500_000_000 : 500_000_000)
            }
        }
        .onChange(of: station.ir) { _, state in
            sync(state)
        }
        .onAppear { sync(station.ir) }
        .sheet(item: $mapTarget) { target in
            MapCodeSheet(code: target.code)
                .environment(station)
        }
    }

    // MARK: State helpers

    var state: IRState? { station.ir }
    var running: Bool { (state?.mode ?? "idle") != "idle" }
    var paused: Bool { state?.paused ?? false }

    var activeMode: IRScanMode {
        if let mode = state?.mode, let parsed = IRScanMode(rawValue: mode) {
            return parsed
        }
        return selectedMode
    }

    /// The firmware only accepts a new start address while idle or while NEC is paused.
    var canSeek: Bool {
        guard let state else { return false }
        return state.mode == "idle" || (state.mode == "brute" && state.paused)
    }

    var progress: (index: Int, total: Int) {
        if editingStart {
            return (Int(startAddress) << 8, 65_536)
        }
        guard let state else {
            return (0, selectedMode == .brute ? 65_536 : 146)
        }
        if running {
            return (state.index, max(state.total, 1))
        }
        if selectedMode == .brute {
            if state.total == 65_536 && state.index < 65_536 {
                return (state.index, 65_536)
            }
            return (0, 65_536)
        }
        return (0, 146)
    }

    func sync(_ state: IRState?) {
        guard let state else { return }
        if !editingSpeed {
            speed = Double(min(max(state.rateMs, 80), 1000))
        }
        if !editingStart && state.total == 65_536 && state.index < 65_536 {
            startAddress = Double(state.index >> 8)
        }
        if state.mode != "idle", let mode = IRScanMode(rawValue: state.mode) {
            selectedMode = mode
        }
    }

    func command(_ query: String) {
        Task { await station.irCommand(query) }
    }

    // MARK: Explorer

    var explorerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Code explorer", subtitle: "Choose a scanning strategy")
            SegmentedPicker(options: [SegmentOption(value: IRScanMode.flipper, title: "Flipper list · 146"),
                                      SegmentOption(value: IRScanMode.brute, title: "NEC brute · 65,536")],
                            selection: modeBinding)
                .disabled(running)
            progressBlock
            Button {
                mainAction()
            } label: {
                Label(mainTitle, systemImage: mainIcon)
            }
            .buttonStyle(PrimaryButtonStyle())
            HStack(spacing: 10) {
                Button {
                    command("do=restart")
                } label: {
                    Label("Restart", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(SecondaryButtonStyle())
                Button {
                    command("do=stop")
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(SecondaryButtonStyle(tone: .danger))
            }
            .disabled(!running)
        }
        .card()
    }

    var modeBinding: Binding<IRScanMode> {
        Binding(
            get: { running ? activeMode : selectedMode },
            set: { selectedMode = $0 }
        )
    }

    var mainTitle: String {
        if !running { return "Start search" }
        return paused ? "Resume" : "Pause"
    }

    var mainIcon: String {
        (!running || paused) ? "play.fill" : "pause.fill"
    }

    func mainAction() {
        if !running {
            command(selectedMode == .flipper ? "do=flipper" : "do=brute")
        } else {
            command(paused ? "do=resume" : "do=pause")
        }
    }

    var pill: (text: String, background: Color, foreground: Color) {
        if !running { return ("READY", Color(hex: 0xEEF1F6), Color(hex: 0x3D5470)) }
        if paused { return ("PAUSED", Color(hex: 0xFFF4E3), Color(hex: 0x8A5A14)) }
        return ("SCANNING", Color(hex: 0xDCECE5), Color(hex: 0x2F6B5E))
    }

    var progressBlock: some View {
        let current = progress
        let fraction = current.total > 0 ? Double(current.index) / Double(current.total) : 0
        let status = pill
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Scan progress")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Spacer()
                StatusPill(text: status.text, background: status.background, foreground: status.foreground)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: 0xE9EEE8))
                    Capsule()
                        .fill(LinearGradient(colors: [Color(hex: 0x87CFB4), Color(hex: 0x168F83)],
                                             startPoint: .leading,
                                             endPoint: .trailing))
                        .frame(width: fraction > 0 ? max(9, geo.size.width * fraction) : 0)
                }
            }
            .frame(height: 9)
            .accessibilityElement()
            .accessibilityLabel("Scan progress")
            .accessibilityValue("\(Int(fraction * 100)) percent")
            HStack {
                Text("\(current.index.formatted()) / \(current.total.formatted()) codes")
                Spacer()
                Text(String(format: "%.1f%%", fraction * 100))
                    .fontWeight(.heavy)
                    .foregroundStyle(Theme.ink)
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.muted)
            Text(metaText)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
        }
    }

    var metaText: String {
        guard let state else { return "Waiting for the light controller" }
        let current = progress
        var parts: [String] = []
        if current.total == 65_536 && current.index < 65_536 {
            parts.append(String(format: "Address 0x%02lX", current.index >> 8))
        }
        if running {
            parts.append(IRFinderView.duration(Double(state.elapsedMs) / 1000))
        }
        if running && !state.paused && current.index > 0 {
            let left = Double(current.total - current.index) * Double(state.rateMs) / 1000
            parts.append("about " + IRFinderView.duration(left) + " left")
        }
        if parts.isEmpty {
            return selectedMode == .brute ? "Starts at the address below" : "Fan power codes come first"
        }
        return parts.joined(separator: " · ")
    }

    static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        if total >= 3600 {
            return "\(total / 3600) h \((total % 3600) / 60) m"
        }
        if total >= 60 {
            return "\(total / 60) m \(total % 60) s"
        }
        return "\(total) s"
    }

    static func age(_ milliseconds: Int) -> String {
        if milliseconds < 500 { return "now" }
        let seconds = Double(milliseconds) / 1000
        if seconds < 60 { return String(format: "%.1f s ago", seconds) }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        return "\(Int(seconds / 3600)) h ago"
    }

    // MARK: Tuning

    var tuningCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Scan tuning", subtitle: "Speed works any time; the start address while idle or while NEC is paused")
            VStack(alignment: .leading, spacing: 4) {
                SliderHeader(title: "Speed", value: "\(Int(speed)) ms per code")
                NexoraSlider(value: $speed,
                             range: 80...1000,
                             step: 20,
                             accessibilityStep: 20,
                             label: "Speed",
                             valueText: "\(Int(speed)) milliseconds per code",
                             onEditingChanged: { editingSpeed = $0 },
                             onCommit: { value in command("ms=\(Int(value))") })
                SliderFooter(left: "80 ms", right: "1000 ms")
            }
            Rectangle().fill(Theme.divider).frame(height: 1)
            VStack(alignment: .leading, spacing: 4) {
                SliderHeader(title: "NEC start address", value: String(format: "0x%02lX", Int(startAddress)), mono: true)
                NexoraSlider(value: $startAddress,
                             range: 0...255,
                             step: 1,
                             accessibilityStep: 1,
                             label: "NEC start address",
                             valueText: String(format: "0x%02lX", Int(startAddress)),
                             onEditingChanged: { editingStart = $0 },
                             onCommit: { value in command("do=seek&a=\(Int(value))") })
                    .disabled(!canSeek)
                SliderFooter(left: "0x00", center: "256 codes per address", right: "0xFF")
            }
        }
        .card()
    }

    // MARK: Now sending

    var nowSending: (code: String, label: String)? {
        guard let state else { return nil }
        let top = state.sent.first
        if let tried = state.tried, tried.age <= (top?.age ?? Int.max) {
            return (tried.code, "Tried by hand")
        }
        if let top {
            return (top.code, top.label)
        }
        return nil
    }

    var nowSendingCard: some View {
        let now = nowSending
        return VStack(alignment: .leading, spacing: 0) {
            Text("NOW SENDING")
                .font(.system(size: 10, weight: .black))
                .kerning(2.2)
                .foregroundStyle(Color(hex: 0xBFE3D9))
            Text(now?.code ?? "—")
                .font(.system(size: 32, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .textSelection(.enabled)
                .padding(.top, 16)
                .padding(.bottom, 6)
            Text(now?.label ?? "Nothing sent yet")
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: 0xCFE7E0))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) {
            Circle()
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 28)
                .frame(width: 170, height: 170)
                .offset(x: 50, y: -50)
                .accessibilityHidden(true)
        }
        .background(Theme.deepTeal)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Try a code

    var tryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Try a code", subtitle: "Send one NEC code by hand; the sweep pauses")
            FieldLabel("Hexadecimal code")
            TextField("0xFE011AE5", text: $manualCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .submitLabel(.send)
                .onSubmit { tryManual() }
                .nexoraField(mono: true)
            if let manualError {
                Text(manualError)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.dangerText)
            }
            Button {
                tryManual()
            } label: {
                Label("Try code", systemImage: "dot.radiowaves.right")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .card()
    }

    func tryManual() {
        guard let value = Hex.parse(manualCode) else {
            manualError = "Type a hex code like 0xFE011AE5."
            return
        }
        manualError = nil
        let code = Hex.string(value)
        Task { await station.irTry(code) }
    }

    // MARK: Lists

    var sentCard: some View {
        let rows = Array((state?.sent ?? []).prefix(20))
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Last 20 sent", subtitle: "Tap Try when the device reacts")
                .padding(.bottom, 8)
            if rows.isEmpty {
                Text("No codes sent yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .padding(.vertical, 14)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { item in
                CodeRow(code: item.element.code,
                        detail: item.element.label + " · " + IRFinderView.age(item.element.age)) {
                    Button("Try") {
                        Task { await station.irTry(item.element.code) }
                    }
                    .buttonStyle(SmallButtonStyle())
                }
            }
        }
        .card()
    }

    var receivedCard: some View {
        let codes = state?.recv ?? []
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Received", subtitle: "Last 10 from the IR receiver · Map puts a code into a remote key")
                .padding(.bottom, 8)
            if codes.isEmpty {
                Text("No codes yet. Press a key on a remote.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .padding(.vertical, 14)
            }
            ForEach(Array(codes.enumerated()), id: \.offset) { item in
                CodeRow(code: item.element, detail: describe(item.element)) {
                    Button("Map") {
                        mapTarget = MapTarget(code: item.element)
                    }
                    .buttonStyle(SmallButtonStyle())
                }
            }
        }
        .card()
    }

    func describe(_ code: String) -> String {
        guard let value = Hex.parse(code) else { return "Unknown remote" }
        for remote in station.remotes {
            for key in remote.keys where Hex.parse(key.gen) == value {
                let keyName = key.name.isEmpty ? "a key" : key.name
                return "Generic code for \(remote.name) · \(keyName)"
            }
        }
        if let name = KnownCodes.lightRemote[value] {
            return "Light remote · \(name)"
        }
        return "Unknown remote"
    }
}

// MARK: - Map a received code to a remote key

struct MapCodeSheet: View {
    @Environment(Station.self) var station
    @Environment(\.dismiss) var dismiss
    let code: String
    @State var remoteIndex = 0
    @State var saving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Pick the key this button should control. \(code) goes into its Generic remote code field; when the receiver sees it, the ESP32 sends the key's original code.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if station.remotes.count == 3 {
                        SegmentedPicker(options: remoteOptions, selection: $remoteIndex)
                        VStack(spacing: 0) {
                            ForEach(0..<5, id: \.self) { k in
                                keyButton(k)
                            }
                        }
                        .card(padding: 8)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
                .padding(18)
                .disabled(saving)
            }
            .background(Theme.background)
            .navigationTitle("Map \(code)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                if station.remotes.isEmpty {
                    await station.loadRemotes()
                }
            }
        }
        .tint(Theme.tealText)
    }

    var remoteOptions: [SegmentOption<Int>] {
        (0..<3).map { index in
            let name = station.remotes[index].name
            return SegmentOption(value: index, title: name.isEmpty ? "Remote \(index + 1)" : name)
        }
    }

    func keyButton(_ k: Int) -> some View {
        let key = station.remotes[remoteIndex].keys[k]
        let name = key.name.isEmpty ? "Key \(k + 1)" : key.name
        return Button {
            Task { await save(k) }
        } label: {
            HStack(spacing: 12) {
                Text("\(k + 1)")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Theme.mintText)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Theme.mint))
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text(key.gen.isEmpty ? "No generic code yet" : "Now: \(key.gen)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                    if key.orig.isEmpty {
                        Text("Needs an original code to work")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.dangerText)
                    }
                }
                Spacer()
                Text("Put here")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Theme.tealText)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func save(_ k: Int) async {
        guard remoteIndex < station.remotes.count else { return }
        var profile = station.remotes[remoteIndex].normalized()
        profile.keys[k].gen = code
        saving = true
        let ok = await station.saveRemote(remoteIndex, profile)
        saving = false
        guard ok else { return }
        let keyName = profile.keys[k].name.isEmpty ? "key \(k + 1)" : profile.keys[k].name
        station.show("Saved \(code) to \(profile.name) · \(keyName)")
        dismiss()
    }
}
