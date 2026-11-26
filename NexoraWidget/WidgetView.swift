import SwiftUI
import WidgetKit

/// Small widget, design 5 "Small, sky": outdoor temperature and humidity against the same time yesterday,
/// eCO₂ and TVOC colored by air quality, on the sky with today's sun or moon.
struct NexoraWidgetView: View {
    let entry: NexoraEntry

    private var ink: Color { Color(hex: 0x1D3A4E) }

    var body: some View {
        Group {
            switch entry.status {
            case .ready:
                readings
            case .setup:
                setup
            }
        }
        .containerBackground(for: .widget) {
            SkyBackground(isDay: entry.isDay, moonPhase: entry.moonPhase)
        }
    }

    private var readings: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(updatedText)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(Color(hex: 0x2C4A60))
                .lineLimit(1)
                .frame(height: 24, alignment: .leading)
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 3) {
                GridRow {
                    Eyebrow(icon: "thermometer.medium", title: "OUTSIDE", iconColor: ink)
                    Spacer(minLength: 6)
                    Eyebrow(icon: "drop", title: "HUMIDITY", iconColor: Color(hex: 0x2A5590))
                }
                GridRow(alignment: .lastTextBaseline) {
                    (Text(format(entry.readings?.outdoor, decimals: 1))
                        .font(.system(size: 32, weight: .bold))
                     + Text("°")
                        .font(.system(size: 15, weight: .bold))
                        .baselineOffset(14))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 6)
                    (Text(format(entry.readings?.humidity, decimals: 0))
                        .font(.system(size: 21, weight: .bold))
                     + Text("%")
                        .font(.system(size: 11, weight: .bold)))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                GridRow {
                    ChangeChip(change: entry.outdoorChange, unit: "°", decimals: 1)
                    Spacer(minLength: 6)
                    ChangeChip(change: entry.humidityChange, unit: "%", decimals: 0)
                }
            }
            .padding(.top, 4)
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                AirChip(title: "eCO₂", icon: "wind", value: entry.readings?.eco2, unit: "ppm",
                        level: AirLevel.eco2(entry.readings?.eco2))
                AirChip(title: "TVOC", icon: "leaf", value: entry.readings?.tvoc, unit: "ppb",
                        level: AirLevel.tvoc(entry.readings?.tvoc))
            }
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("nexora.")
                .font(.system(size: 16, weight: .heavy))
            Spacer(minLength: 0)
            Text("Open Nexora once to set up this widget.")
                .font(.system(size: 12, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
    }

    /// "Live · 2m", "Adafruit · 14m", "ThingSpeak · 1h"
    private var updatedText: String {
        guard let readings = entry.readings else { return "No readings yet" }
        let minutes = max(0, Int(entry.date.timeIntervalSince(readings.at) / 60))
        let age: String
        if minutes < 1 {
            age = "now"
        } else if minutes < 60 {
            age = "\(minutes)m"
        } else if minutes < 48 * 60 {
            age = "\(minutes / 60)h"
        } else {
            age = "\(minutes / 1440)d"
        }
        return readings.source.isEmpty ? age : readings.source + " · " + age
    }

    private func format(_ value: Double?, decimals: Int) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.\(decimals)f", value)
    }
}

private struct Eyebrow: View {
    let icon: String
    let title: String
    let iconColor: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(iconColor)
            Text(title)
                .font(.system(size: 8, weight: .black))
                .kerning(0.8)
                .lineLimit(1)
        }
        .fixedSize()
    }
}

/// ↓2.5° or ↑6%: the change since the same time yesterday.
private struct ChangeChip: View {
    let change: Double?
    let unit: String
    let decimals: Int

    var body: some View {
        if let change, change.isFinite {
            let scale = pow(10, Double(decimals))
            let rounded = (change * scale).rounded() / scale
            HStack(spacing: 2) {
                Image(systemName: rounded > 0 ? "arrow.up" : (rounded < 0 ? "arrow.down" : "arrow.right"))
                    .font(.system(size: 8, weight: .heavy))
                Text(String(format: "%.\(decimals)f", abs(rounded)) + unit)
                    .font(.system(size: 10, weight: .heavy))
                    .monospacedDigit()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.55)))
            .fixedSize()
        } else {
            // Yesterday isn't known (no ThingSpeak yet): keep the space so nothing jumps.
            Color.clear.frame(width: 1, height: 15)
        }
    }
}

enum AirLevel {
    case good, moderate, bad

    var color: Color {
        switch self {
        case .good: return Color(hex: 0x1E7A46)
        case .moderate: return Color(hex: 0xB45A0C)
        case .bad: return Color(hex: 0xB3261E)
        }
    }

    /// Good up to 1000 ppm, moderate up to 1500 ppm, bad above.
    static func eco2(_ value: Double?) -> AirLevel? {
        guard let value else { return nil }
        if value <= 1000 { return .good }
        if value <= 1500 { return .moderate }
        return .bad
    }

    /// Good up to 220 ppb, moderate up to 660 ppb, bad above.
    static func tvoc(_ value: Double?) -> AirLevel? {
        guard let value else { return nil }
        if value <= 220 { return .good }
        if value <= 660 { return .moderate }
        return .bad
    }
}

private struct AirChip: View {
    let title: String
    let icon: String
    let value: Double?
    let unit: String
    let level: AirLevel?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 7.5, weight: .bold))
                Text(title)
                    .font(.system(size: 8, weight: .heavy))
                    .lineLimit(1)
            }
            .foregroundStyle(Color(hex: 0x3A5368))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value.map { String(Int($0.rounded())) } ?? "—")
                    .font(.system(size: 14, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(level?.color ?? Color(hex: 0x1D3A4E))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(unit)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color(hex: 0x4A5F70))
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.78)))
    }
}

/// The outdoor card's sky: sun by day; moon in today's phase and stars at night.
struct SkyBackground: View {
    let isDay: Bool
    let moonPhase: Double

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(stops: isDay
                           ? [.init(color: Color(hex: 0xC0DEF0), location: 0),
                              .init(color: Color(hex: 0xDCEBF3), location: 0.44),
                              .init(color: Color(hex: 0xE8F0E6), location: 1)]
                           : [.init(color: Color(hex: 0x8FA6C9), location: 0),
                              .init(color: Color(hex: 0xAEBEDA), location: 0.5),
                              .init(color: Color(hex: 0xC7D1E3), location: 1)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if isDay {
                ZStack {
                    Circle()
                        .fill(Color(hex: 0xFFF1B7).opacity(0.3))
                        .frame(width: 34, height: 34)
                    Circle()
                        .fill(RadialGradient(colors: [Color(hex: 0xFFF8C4), Color(hex: 0xFFDB7C), Color(hex: 0xF5C06F)],
                                             center: UnitPoint(x: 0.38, y: 0.34), startRadius: 0, endRadius: 15))
                        .frame(width: 24, height: 24)
                        .shadow(color: Color(hex: 0xFFC669).opacity(0.55), radius: 10)
                }
                .padding(.top, 7)
                .padding(.trailing, 9)
            } else {
                star(size: 3, top: 15, trailing: 54)
                star(size: 2, top: 36, trailing: 46)
                star(size: 2, top: 46, trailing: 9)
                MoonView(phase: moonPhase)
                    .frame(width: 24, height: 24)
                    .padding(.top, 12)
                    .padding(.trailing, 14)
            }
        }
    }

    private func star(size: CGFloat, top: CGFloat, trailing: CGFloat) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: size, height: size)
            .padding(.top, top)
            .padding(.trailing, trailing)
    }
}

/// The moon as it looks tonight: the lit part from the phase, the rest faint.
struct MoonView: View {
    let phase: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0xFFF1C2).opacity(0.2))
            MoonLitShape(phase: phase)
                .fill(Color(hex: 0xFFF1C2))
        }
        .shadow(color: Color(hex: 0xFFF1C2).opacity(0.5), radius: 9)
    }
}

/// Lit on the right while the moon grows, on the left while it shrinks (as seen from the northern half of the Earth).
struct MoonLitShape: Shape {
    let phase: Double

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let side: Double = phase < 0.5 ? 1 : -1
        let terminator = cos(2 * Double.pi * phase)   // 1 new, 0 half, -1 full
        let steps = 48
        var path = Path()
        for i in 0...steps {
            let t = -Double.pi / 2 + Double.pi * Double(i) / Double(steps)
            let point = CGPoint(x: center.x + CGFloat(side * cos(t)) * radius,
                                y: center.y + CGFloat(sin(t)) * radius)
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        for i in 0...steps {
            let t = Double.pi / 2 - Double.pi * Double(i) / Double(steps)
            path.addLine(to: CGPoint(x: center.x + CGFloat(side * terminator * cos(t)) * radius,
                                     y: center.y + CGFloat(sin(t)) * radius))
        }
        path.closeSubpath()
        return path
    }
}
