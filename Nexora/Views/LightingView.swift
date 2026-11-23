import SwiftUI
import UIKit

struct LightingView: View {
    @Environment(Station.self) var station
    @State var brightness: Double = 50
    @State var balance: Double = 50
    @State var editing = false
    @State var lastLiveSend = Date.distantPast
    @State var customColor = Color(red: 1, green: 0.55, blue: 0.1)
    @State var colorTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                TopBar()
                PageHeading(eyebrow: "Ambient control",
                            title: "Set the mood.",
                            subtitle: Text("RGB + warm white + cool white"))
                OfflineCard()
                VStack(spacing: 14) {
                    LightPreview(state: station.light)
                    controlsCard
                    ScenesCard()
                    ledsCard
                }
                .disabled(station.light == nil || !station.isConnected)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Theme.background)
        .refreshable { await station.pollLight() }
        .task(id: station.link) {
            while !Task.isCancelled {
                if !editing {
                    await station.pollLight()
                }
                try? await Task.sleep(nanoseconds: station.link == .away ? 5_000_000_000 : 2_000_000_000)
            }
        }
        .onChange(of: station.light) { _, state in
            sync(state)
        }
        .onAppear { sync(station.light) }
    }

    func sync(_ state: LightState?) {
        guard let state, !editing else { return }
        brightness = Double(state.brightness)
        balance = Double(state.balance)
    }

    // MARK: Controls

    var controlsCard: some View {
        let on = station.light?.on ?? false
        return VStack(alignment: .leading, spacing: 18) {
            Toggle(isOn: powerBinding) {
                SectionHeader(title: "Light controls", subtitle: on ? "Light — on" : "Light — off")
            }
            .toggleStyle(PillToggleStyle())
            VStack(alignment: .leading, spacing: 18) {
                brightnessRow
                balanceRow
                colorRow
            }
            .disabled(!on)
        }
        .card()
    }

    var powerBinding: Binding<Bool> {
        Binding(
            get: { station.light?.on ?? false },
            set: { newValue in send("on=\(newValue ? 1 : 0)") }
        )
    }

    var brightnessRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            SliderHeader(title: "Brightness", value: "\(Int(brightness))%")
            NexoraSlider(value: $brightness,
                         range: 0...100,
                         step: 1,
                         accessibilityStep: 5,
                         label: "Brightness",
                         valueText: "\(Int(brightness)) percent",
                         onEditingChanged: { editing = $0 },
                         onChange: { value in sendLive("brightness=\(Int(value))") },
                         onCommit: { value in send("brightness=\(Int(value))") })
            SliderFooter(left: "Dim", right: "Maximum")
        }
    }

    var balanceRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            SliderHeader(title: "White temperature", value: "\(Int(balance))% cool")
            NexoraSlider(value: $balance,
                         range: 0...100,
                         step: 1,
                         accessibilityStep: 5,
                         track: LinearGradient(colors: [Color(hex: 0xFFC470), Color(hex: 0xFFF0B9), Color(hex: 0xAAD4FA)],
                                               startPoint: .leading,
                                               endPoint: .trailing),
                         label: "White temperature",
                         valueText: "\(Int(balance)) percent cool",
                         onEditingChanged: { editing = $0 },
                         onChange: { value in sendLive(balanceQuery(value)) },
                         onCommit: { value in send(balanceQuery(value)) })
            SliderFooter(left: "Warm white", right: "Cool white")
        }
    }

    /// On a color or an effect, the white slider switches the light back to white first.
    func balanceQuery(_ value: Double) -> String {
        if let light = station.light, !light.usesWhiteBalance {
            return "color=000000&balance=\(Int(value))"
        }
        return "balance=\(Int(value))"
    }

    var colorRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RGB color")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(colorText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }
            HStack(spacing: 10) {
                ForEach(Swatch.all) { swatch in
                    swatchButton(swatch)
                }
                ColorPicker("Custom color", selection: colorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .scaleEffect(1.3)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Custom color")
                Spacer(minLength: 0)
            }
        }
    }

    func swatchButton(_ swatch: Swatch) -> some View {
        let current = station.light.map { $0.isColor && $0.hex == swatch.hex } ?? false
        return Button {
            send("color=\(swatch.hex)")
        } label: {
            Circle()
                .fill(swatch.color)
                .frame(width: 44, height: 44)
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 3))
                .overlay(
                    Circle()
                        .strokeBorder(current ? Theme.teal : Color(hex: 0xDFE9E3), lineWidth: current ? 2.5 : 1)
                        .padding(-1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(swatch.name)
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    var colorText: String {
        guard let light = station.light else { return "—" }
        return light.isColor ? "#" + light.hex.uppercased() : "White"
    }

    var colorBinding: Binding<Color> {
        Binding(
            get: { customColor },
            set: { newColor in
                customColor = newColor
                let hex = ColorHex.string(from: newColor)
                colorTask?.cancel()
                colorTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    await station.setLight("color=\(hex)")
                }
            }
        )
    }

    var ledsCard: some View {
        Toggle(isOn: ledsBinding) {
            VStack(alignment: .leading, spacing: 3) {
                Text("ESP32 status LEDs")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text("Green Wi-Fi blink and blue upload pulse")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
        }
        .toggleStyle(PillToggleStyle())
        .card(padding: 16)
    }

    var ledsBinding: Binding<Bool> {
        Binding(
            get: { station.light?.leds ?? false },
            set: { newValue in send("leds=\(newValue ? 1 : 0)") }
        )
    }

    // MARK: Sending

    func send(_ query: String) {
        Task { await station.setLight(query) }
    }

    /// While a slider moves at home, update the light a few times a second.
    func sendLive(_ query: String) {
        guard station.link == .home else { return }
        let now = Date()
        guard now.timeIntervalSince(lastLiveSend) > 0.25 else { return }
        lastLiveSend = now
        send(query)
    }
}

struct Swatch: Identifiable {
    let name: String
    let hex: String

    var id: String { hex }
    var color: Color { Color(hex: UInt32(hex, radix: 16) ?? 0) }

    static let all: [Swatch] = [
        Swatch(name: "Amber", hex: "ff8c1a"),
        Swatch(name: "Rose", hex: "ff3d7f"),
        Swatch(name: "Violet", hex: "8a4dff"),
        Swatch(name: "Sky blue", hex: "1e90ff"),
        Swatch(name: "Mint", hex: "1fd6a0")
    ]
}

enum ColorHex {
    static func string(from color: Color) -> String {
        let ui = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        ui.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "%02lx%02lx%02lx", channel(red), channel(green), channel(blue))
    }

    static func channel(_ value: CGFloat) -> Int {
        Int((min(max(value, 0), 1) * 255).rounded())
    }
}

// MARK: - Preview

struct LightPreview: View {
    let state: LightState?

    var body: some View {
        let glow = previewColor
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(hex: 0xF5F6EE))
            Circle()
                .fill(RadialGradient(gradient: Gradient(stops: [
                    .init(color: glow, location: 0),
                    .init(color: glow.opacity(0.45), location: 0.3),
                    .init(color: glow.opacity(0.16), location: 0.52),
                    .init(color: glow.opacity(0), location: 0.71)
                ]), center: .center, startRadius: 0, endRadius: 170))
                .frame(width: 340, height: 340)
                .opacity(glowOpacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: 40, y: -70)
            VStack(alignment: .leading, spacing: 0) {
                Text("Live light preview")
                    .font(.system(size: 10, weight: .black))
                    .kerning(2.3)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.eyebrow)
                Spacer(minLength: 12)
                Image(systemName: state?.on == true ? "lightbulb.fill" : "lightbulb")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(state?.on == true ? Theme.sceneIcon : Color(hex: 0x8E9692))
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                Spacer(minLength: 12)
                Text("Current scene")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                Text(label)
                    .font(.system(size: 30, weight: .bold))
                    .kerning(-1)
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 2)
                HStack {
                    Text(state.map { "\($0.brightness)% brightness" } ?? "—")
                    Spacer()
                    Text("5 PWM channels")
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .padding(.top, 6)
            }
            .padding(24)
        }
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    var label: String {
        guard let state else { return "—" }
        return state.on ? state.label : "Off"
    }

    var glowOpacity: Double {
        guard let state, state.on else { return 0.25 }
        return 0.4 + 0.6 * Double(state.brightness) / 100
    }

    var previewColor: Color {
        guard let state, state.on else { return Color(hex: 0xC8CDC8) }
        switch state.type {
        case 2: return Color(red: 1, green: 0.71, blue: 0.35)      // Candle
        case 3: return Color(red: 0.5, green: 0.66, blue: 1)       // TV
        case 4: return Color(red: 1, green: 0.35, blue: 0.35)      // Police
        case 5: return Color(red: 1, green: 0.82, blue: 0.54)      // Faulty bulb
        case 6: return Color(red: 0.91, green: 0.94, blue: 1)      // Lightning
        default: break
        }
        if state.isColor {
            return Color(red: Double(state.r) / 255, green: Double(state.g) / 255, blue: Double(state.b) / 255)
        }
        let t = Double(state.balance) / 100
        return Color(red: (255 - 85 * t) / 255, green: (196 + 16 * t) / 255, blue: (112 + 138 * t) / 255)
    }
}

// MARK: - Scenes

struct ScenesCard: View {
    @Environment(Station.self) var station

    var body: some View {
        let names = station.sceneNames
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Scenes", subtitle: "All \(names.count) from your light")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(Array(names.enumerated()), id: \.offset) { item in
                    SceneTile(name: item.element, active: isActive(item.offset)) {
                        Task { await station.setLight("scene=\(item.offset)") }
                    }
                }
            }
        }
        .card()
    }

    func isActive(_ index: Int) -> Bool {
        guard let light = station.light, light.on else { return false }
        return light.sceneIndex == index
    }
}

struct SceneTile: View {
    let name: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: SceneCatalog.icon(for: name))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.sceneIcon)
                    .accessibilityHidden(true)
                Text(name)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Theme.label)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(active ? Theme.tileActive : Theme.tile)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(active ? Theme.tileActiveBorder : Theme.tileBorder, lineWidth: active ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
