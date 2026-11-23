import SwiftUI
import UIKit

// MARK: - Cards and fields

struct CardStyle: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Theme.panel)
                    .shadow(color: Theme.shadow, radius: 18, x: 0, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }
}

struct FieldStyle: ViewModifier {
    var mono: Bool

    func body(content: Content) -> some View {
        content
            .font(mono ? .system(size: 15, weight: .medium, design: .monospaced) : .system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 13)
            .frame(minHeight: 46)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Theme.field)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Theme.fieldBorder, lineWidth: 1)
            )
    }
}

struct EnabledOpacity: ViewModifier {
    @Environment(\.isEnabled) var isEnabled

    func body(content: Content) -> some View {
        content.opacity(isEnabled ? 1 : 0.45)
    }
}

extension View {
    func card(padding: CGFloat = 20) -> some View {
        modifier(CardStyle(padding: padding))
    }

    func nexoraField(mono: Bool = false) -> some View {
        modifier(FieldStyle(mono: mono))
    }
}

// MARK: - Header pieces

struct BrandMark: View {
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Theme.brandTile)
                    .frame(width: 34, height: 34)
                HStack(alignment: .center, spacing: 3) {
                    Capsule().fill(Theme.brandBar).frame(width: 4, height: 11)
                    Capsule().fill(Theme.brandBar).frame(width: 4, height: 20)
                    Capsule().fill(Theme.brandBar).frame(width: 4, height: 15)
                }
            }
            .rotationEffect(.degrees(-9))
            (Text("nexora").foregroundStyle(Theme.ink) + Text(".").foregroundStyle(Theme.apricot))
                .font(.system(size: 27, weight: .heavy))
                .kerning(-1.4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nexora")
    }
}

struct ConnectionChip: View {
    let link: Station.Link

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(dotColor).frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 11, weight: .heavy))
                .kerning(0.8)
                .textCase(.uppercase)
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Theme.chipBackground))
        .overlay(Capsule().strokeBorder(Theme.chipBorder, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Connection: \(title)")
    }

    var title: String {
        switch link {
        case .connecting: return "Connecting"
        case .home: return "At home"
        case .away: return "Away · EMQX"
        case .offline: return "Offline"
        }
    }

    var dotColor: Color {
        switch link {
        case .connecting: return Color(hex: 0xD99A5E)
        case .home: return Color(hex: 0x22A06B)
        case .away: return Color(hex: 0x4C92EB)
        case .offline: return Color(hex: 0xA0A8AE)
        }
    }

    var textColor: Color {
        switch link {
        case .connecting: return Color(hex: 0x8A5A14)
        case .home: return Color(hex: 0x2F6B5E)
        case .away: return Color(hex: 0x2D5A8C)
        case .offline: return Theme.muted
        }
    }
}

struct TopBar: View {
    @Environment(Station.self) var station

    var body: some View {
        HStack(spacing: 12) {
            BrandMark()
            Spacer(minLength: 8)
            ConnectionChip(link: station.link)
        }
    }
}

struct PageHeading: View {
    let eyebrow: String
    let title: String
    var subtitle: Text? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow)
                .font(.system(size: 10, weight: .black))
                .kerning(2.3)
                .textCase(.uppercase)
                .foregroundStyle(Theme.eyebrow)
            Text(title)
                .font(.system(size: 34, weight: .bold))
                .kerning(-1.3)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                subtitle
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .kerning(-0.4)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FieldLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(Theme.label)
    }
}

struct SliderHeader: View {
    let title: String
    let value: String
    var mono = false

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Spacer()
            Text(value)
                .font(mono ? .system(size: 13, weight: .heavy, design: .monospaced) : .system(size: 13, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(Theme.tealText)
        }
        .accessibilityHidden(true)
    }
}

struct SliderFooter: View {
    let left: String
    var center: String? = nil
    let right: String

    var body: some View {
        HStack {
            Text(left)
            Spacer()
            if let center {
                Text(center)
                Spacer()
            }
            Text(right)
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.muted)
        .accessibilityHidden(true)
    }
}

struct StatusPill: View {
    let text: String
    let background: Color
    let foreground: Color

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(foreground).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 10, weight: .heavy))
                .kerning(0.6)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(background))
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.teal)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .modifier(EnabledOpacity())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    enum Tone {
        case plain, mint, danger
    }

    var tone: Tone = .plain

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .modifier(EnabledOpacity())
    }

    var foreground: Color {
        switch tone {
        case .plain: return Theme.buttonText
        case .mint: return Theme.mintText
        case .danger: return Theme.dangerText
        }
    }

    var background: Color {
        switch tone {
        case .plain: return Color.white
        case .mint: return Theme.mint
        case .danger: return Theme.danger
        }
    }

    var border: Color {
        switch tone {
        case .plain: return Theme.buttonBorder
        case .mint: return Theme.mint
        case .danger: return Theme.danger
        }
    }
}

struct SmallButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(Theme.smallButtonText)
            .padding(.horizontal, compact ? 0 : 12)
            .frame(minWidth: 44, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.smallButton)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.smallButtonBorder, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .modifier(EnabledOpacity())
    }
}

struct CopyButton: View {
    let text: String
    @State var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = text
            copied = true
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(SmallButtonStyle(compact: true))
        .accessibilityLabel(copied ? "Copied" : "Copy \(text)")
    }
}

// MARK: - Switch

struct PillToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                configuration.label
                Spacer(minLength: 8)
                PillSwitch(isOn: configuration.isOn)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(EnabledOpacity())
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

struct PillSwitch: View {
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(isOn ? Theme.switchOn : Theme.switchOff)
            Circle()
                .fill(Color.white)
                .frame(width: 24, height: 24)
                .padding(4)
                .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
        }
        .frame(width: 55, height: 32)
        .animation(.easeInOut(duration: 0.15), value: isOn)
    }
}

// MARK: - Segmented picker

struct SegmentOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var id: AnyHashable { AnyHashable(value) }
}

struct SegmentedPicker<Value: Hashable>: View {
    let options: [SegmentOption<Value>]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.segment)
        )
    }

    func segment(_ option: SegmentOption<Value>) -> some View {
        let selected = option.value == selection
        return Button {
            selection = option.value
        } label: {
            Text(option.title)
                .font(.system(size: 12, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(selected ? Theme.tealText : Theme.muted)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? Color.white : Color.clear)
                        .shadow(color: selected ? Color(hex: 0x275B40, opacity: 0.08) : Color.clear, radius: 5, x: 0, y: 4)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(EnabledOpacity())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Slider

/// Slider in the design's style: thick track, white thumb with a teal ring.
struct NexoraSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var accessibilityStep: Double? = nil
    var track: LinearGradient? = nil
    let label: String
    let valueText: String
    var onEditingChanged: (Bool) -> Void = { _ in }
    var onChange: (Double) -> Void = { _ in }
    var onCommit: (Double) -> Void = { _ in }

    @Environment(\.isEnabled) var isEnabled
    @State var dragging = false

    let thumb: CGFloat = 26

    var body: some View {
        GeometryReader { geo in
            let usable = max(geo.size.width - thumb, 1)
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? CGFloat((value - range.lowerBound) / span) : 0
            let x = usable * min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                trackView(filled: x + thumb / 2)
                thumbView
                    .offset(x: x)
            }
            .frame(width: geo.size.width, height: 44)
            .contentShape(Rectangle())
            .gesture(dragGesture(usable: usable))
        }
        .frame(height: 44)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(valueText)
        .accessibilityAdjustableAction { direction in
            adjust(direction)
        }
    }

    var thumbView: some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().strokeBorder(Theme.teal, lineWidth: 5))
            .frame(width: thumb, height: thumb)
            .shadow(color: Theme.teal.opacity(0.25), radius: 3, x: 0, y: 2)
    }

    @ViewBuilder
    func trackView(filled: CGFloat) -> some View {
        if let track {
            Capsule()
                .fill(track)
                .frame(height: 8)
        } else {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.track)
                    .frame(height: 8)
                Capsule()
                    .fill(LinearGradient(colors: [Theme.teal, Theme.tealLight], startPoint: .leading, endPoint: .trailing))
                    .frame(width: filled, height: 8)
            }
        }
    }

    func dragGesture(usable: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                guard isEnabled else { return }
                if !dragging {
                    dragging = true
                    onEditingChanged(true)
                }
                let fraction = Double(min(max((gesture.location.x - thumb / 2) / usable, 0), 1))
                var newValue = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
                newValue = (newValue / step).rounded() * step
                newValue = min(max(newValue, range.lowerBound), range.upperBound)
                if newValue != value {
                    value = newValue
                    onChange(newValue)
                }
            }
            .onEnded { _ in
                guard dragging else { return }
                dragging = false
                onEditingChanged(false)
                if isEnabled {
                    onCommit(value)
                }
            }
    }

    func adjust(_ direction: AccessibilityAdjustmentDirection) {
        guard isEnabled else { return }
        let delta = accessibilityStep ?? step
        switch direction {
        case .increment:
            value = min(range.upperBound, value + delta)
        case .decrement:
            value = max(range.lowerBound, value - delta)
        @unknown default:
            return
        }
        onCommit(value)
    }
}

// MARK: - Rows and banners

struct CodeRow<Actions: View>: View {
    let code: String
    let detail: String
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(code)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            actions
            CopyButton(text: code)
        }
        .frame(minHeight: 60)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.divider).frame(height: 1)
        }
    }
}

struct OfflineCard: View {
    @Environment(Station.self) var station

    var body: some View {
        if station.link == .offline {
            VStack(alignment: .leading, spacing: 10) {
                Label("Can't reach your light controller", systemImage: "wifi.exclamationmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                if let note = station.linkNote {
                    Text(note)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    Task { await station.refreshLink() }
                } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .card()
        }
    }
}

struct ToastView: View {
    @Environment(Station.self) var station

    var body: some View {
        if let message = station.toast {
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Capsule().fill(Theme.ink.opacity(0.94)))
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { station.toast = nil }
        }
    }
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var buildNumber: String {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}
