import SwiftUI
import Charts

struct OverviewView: View {
    @Environment(Station.self) var station
    @Environment(HistoryStore.self) var history
    @Environment(SettingsStore.self) var settings
    @Binding var tab: AppTab
    @State var range: HistoryRange = .day

    var body: some View {
        let readings = station.readings
        ScrollView {
            VStack(spacing: 14) {
                TopBar()
                PageHeading(eyebrow: "Environmental overview",
                            title: "Your space, at a glance.",
                            subtitle: subtitle(for: readings))
                OfflineCard()
                OutdoorCard(value: readings.outdoor)
                IndoorCard(indoor: readings.indoor, bme: readings.bmeTemp, outdoor: readings.outdoor)
                ReadingsGrid(readings: readings)
                HistoryCard(range: $range)
                QuickLinks(tab: $tab)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Theme.background)
        .refreshable {
            await station.pollInfo()
            await refreshCloud(force: true)
        }
        .task(id: station.link) {
            // Straight from the ESP32: eCO₂ and TVOC change every second there.
            while !Task.isCancelled {
                await station.pollInfo()
                try? await Task.sleep(nanoseconds: station.link == .away ? 3_000_000_000 : 2_000_000_000)
            }
        }
        .task {
            // Adafruit IO every 20 s; ThingSpeak limits itself to about every 2 minutes.
            while !Task.isCancelled {
                await refreshCloud(force: false)
                try? await Task.sleep(nanoseconds: 20_000_000_000)
            }
        }
    }

    func refreshCloud(force: Bool) async {
        await station.adafruit.refresh(settings: settings.value, force: force)
        await history.refresh(settings: settings.value, force: force)
    }

    func subtitle(for readings: ReadingsSnapshot) -> Text {
        guard let at = readings.at else {
            if let problem = station.adafruit.problem {
                return Text(problem)
            }
            if settings.value.adafruitConfigured || settings.value.thingSpeakConfigured {
                return Text("Waiting for the first readings")
            }
            return Text("Add Adafruit IO or ThingSpeak in More to see readings")
        }
        return Text("\(readings.source.title) · updated ") + Text(at, style: .relative) + Text(" ago")
    }
}

// MARK: - Outdoor

struct OutdoorCard: View {
    let value: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 300)) { context in
            card(day: Sun.isDay(context.date))
        }
    }

    func card(day: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: day
                           ? [Color(hex: 0xC0DEF0), Color(hex: 0xDCEBF3), Color(hex: 0xE8F0E6)]
                           : [Color(hex: 0x8FA6C9), Color(hex: 0xAEBEDA), Color(hex: 0xC7D1E3)],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
            if day {
                SunArt()
            } else {
                MoonArt()
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("OUTDOOR PROBE")
                    .font(.system(size: 10, weight: .black))
                    .kerning(2.2)
                Text("Outside your home")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.top, 8)
                Spacer(minLength: 30)
                TemperatureText(value: value, size: 84, unitSize: 40)
                Text("DS18B20 probe")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.6)))
                    .padding(.top, 12)
            }
            .foregroundStyle(Color(hex: 0x1D3A4E))
            .padding(26)
        }
        .frame(maxWidth: .infinity, minHeight: 286, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Outdoor temperature")
        .accessibilityValue(value.map { String(format: "%.1f degrees", $0) } ?? "No reading")
    }
}

struct SunArt: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xFFF8C4), Color(hex: 0xFFDB7C), Color(hex: 0xF5C06F)],
                                     center: UnitPoint(x: 0.38, y: 0.34),
                                     startRadius: 2,
                                     endRadius: 52))
                .frame(width: 92, height: 92)
                .background(
                    Circle()
                        .fill(Color(hex: 0xFFF1B7, opacity: 0.3))
                        .frame(width: 124, height: 124)
                )
                .shadow(color: Color(hex: 0xFFC669, opacity: 0.5), radius: 30)
                .padding(.top, 30)
                .padding(.trailing, 28)
            Cloud()
                .offset(x: 8, y: 106)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .accessibilityHidden(true)
    }
}

struct Cloud: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Capsule().frame(width: 150, height: 40)
            Circle().frame(width: 64, height: 62).offset(x: 34, y: -18)
            Circle().frame(width: 52, height: 50).offset(x: 84, y: -12)
        }
        .foregroundStyle(Color.white.opacity(0.72))
        .frame(width: 150, height: 82, alignment: .bottomLeading)
    }
}

struct MoonArt: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(Color(hex: 0xFFF1C2))
                .frame(width: 80, height: 80)
                .mask(
                    ZStack {
                        Rectangle()
                        Circle()
                            .frame(width: 70, height: 70)
                            .offset(x: 22, y: -16)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                )
                .shadow(color: Color(hex: 0xFFF1C2, opacity: 0.45), radius: 22)
                .padding(.top, 34)
                .padding(.trailing, 34)
            Circle().fill(Color.white).frame(width: 4, height: 4).offset(x: -150, y: 44)
            Circle().fill(Color.white).frame(width: 3, height: 3).offset(x: -128, y: 104)
            Circle().fill(Color.white).frame(width: 3, height: 3).offset(x: -20, y: 140)
            Circle().fill(Color.white).frame(width: 2, height: 2).offset(x: -96, y: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .accessibilityHidden(true)
    }
}

struct TemperatureText: View {
    let value: Double?
    let size: CGFloat
    let unitSize: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            number
                .font(.system(size: size, weight: .bold))
                .monospacedDigit()
            Text("°C")
                .font(.system(size: unitSize, weight: .bold))
                .padding(.top, size * 0.1)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    // Tight spacing between the digits, but none after the last one: kerning after the
    // last character made the text narrower than that digit, and iOS cut its right edge off.
    private var number: Text {
        let text = value.map { String(format: "%.1f", $0) } ?? "—"
        return Text(String(text.dropLast())).kerning(-size * 0.06) + Text(String(text.suffix(1)))
    }
}

// MARK: - Indoor

struct IndoorCard: View {
    let indoor: Double?
    let bme: Double?
    let outdoor: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("INSIDE THE ROOM")
                    .font(.system(size: 10, weight: .black))
                    .kerning(2)
                Spacer()
                Image(systemName: "house")
                    .font(.system(size: 18, weight: .medium))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color(hex: 0x47665A))
            TemperatureText(value: indoor, size: 64, unitSize: 28)
                .padding(.top, 22)
            Text("Indoor DS18B20 probe")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x47665A))
            Rectangle()
                .fill(Color(hex: 0x304C43, opacity: 0.12))
                .frame(height: 1)
                .padding(.top, 14)
            HStack(alignment: .firstTextBaseline) {
                Text("Room air · BME280")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x47665A))
                Spacer()
                Text(bme.map { String(format: "%.1f °C", $0) } ?? "—")
                    .font(.system(size: 20, weight: .bold))
                    .monospacedDigit()
            }
            .padding(.top, 12)
            if let indoor, let outdoor {
                Text(IndoorCard.deltaText(indoor - outdoor))
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Color(hex: 0x2F6B5E))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white.opacity(0.85)))
                    .padding(.top, 14)
            }
        }
        .foregroundStyle(Color(hex: 0x304C43))
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottomTrailing) {
            Circle()
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 34)
                .frame(width: 210, height: 210)
                .offset(x: 80, y: 80)
                .accessibilityHidden(true)
        }
        .background(Color(hex: 0xECF2E8))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    static func deltaText(_ delta: Double) -> String {
        if abs(delta) < 0.05 {
            return "Same as outside"
        }
        let sign = delta > 0 ? "+" : "−"
        let word = delta > 0 ? "warmer" : "cooler"
        return sign + String(format: "%.1f", abs(delta)) + " °C " + word + " than outside"
    }
}

// MARK: - Readings grid

struct ReadingsGrid: View {
    let readings: ReadingsSnapshot

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            StatTile(title: "Humidity", value: ReadingsGrid.format(readings.humidity, "%.0f"), unit: "%",
                     source: "BME280", icon: "drop", tint: Color(hex: 0x4F7BC4), tile: Color(hex: 0xE9F0FC))
            StatTile(title: "Pressure", value: ReadingsGrid.format(readings.pressure, "%.1f"), unit: "hPa",
                     source: "BME280", icon: "gauge.with.dots.needle.33percent", tint: Color(hex: 0xA87A2C), tile: Color(hex: 0xFFF4E3))
            StatTile(title: "eCO₂", value: ReadingsGrid.format(readings.eco2, "%.0f"), unit: "ppm",
                     source: "SGP30 · estimated", icon: "wind", tint: Color(hex: 0x2F7B62), tile: Color(hex: 0xEAF4ED))
            StatTile(title: "TVOC", value: ReadingsGrid.format(readings.tvoc, "%.0f"), unit: "ppb",
                     source: "SGP30", icon: "leaf", tint: Color(hex: 0xB65F49), tile: Color(hex: 0xFFF0E9))
        }
    }

    static func format(_ value: Double?, _ pattern: String) -> String {
        guard let value else { return "—" }
        return String(format: pattern, value)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let unit: String
    let source: String
    let icon: String
    let tint: Color
    let tile: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(tile))
                    .accessibilityHidden(true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 28, weight: .bold))
                    .kerning(-1)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(unit)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.top, 4)
            Text(source)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
        }
        .card(padding: 16)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - History chart

struct HistoryCard: View {
    @Environment(HistoryStore.self) var history
    @Environment(SettingsStore.self) var settings
    @Binding var range: HistoryRange

    var body: some View {
        let series = history.series(for: range)
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Temperature history", subtitle: "From ThingSpeak · a point every 10 min")
            SegmentedPicker(options: HistoryRange.allCases.map { SegmentOption(value: $0, title: $0.title) },
                            selection: $range)
            legend(series)
            if series.isEmpty {
                placeholder
            } else {
                HistoryChart(points: series, range: range)
                    .frame(height: 170)
            }
        }
        .card()
    }

    func legend(_ series: [HistoryStore.Point]) -> some View {
        let inside = series.last(where: { $0.indoor != nil })?.indoor
        let outside = series.last(where: { $0.outdoor != nil })?.outdoor
        return HStack(spacing: 16) {
            LegendDot(color: Theme.inside, text: "Inside " + (inside.map { String(format: "%.1f°", $0) } ?? "—"))
            LegendDot(color: Theme.outside, text: "Outside " + (outside.map { String(format: "%.1f°", $0) } ?? "—"))
        }
    }

    @ViewBuilder
    var placeholder: some View {
        if !settings.value.thingSpeakConfigured {
            Text("Add your ThingSpeak channel and Read API Key in More → ThingSpeak.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, minHeight: 120)
        } else if history.loading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            Text(history.problem ?? "No readings in this range yet.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }
}

struct LegendDot: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.muted)
        }
    }
}

struct HistoryChart: View {
    let points: [HistoryStore.Point]
    let range: HistoryRange

    var domain: ClosedRange<Double> {
        var values: [Double] = []
        for point in points {
            if let inside = point.indoor { values.append(inside) }
            if let outside = point.outdoor { values.append(outside) }
        }
        let low = (values.min() ?? 0) - 1
        let high = (values.max() ?? 30) + 1
        return low...high
    }

    var body: some View {
        let bounds = domain
        let low = bounds.lowerBound
        let high = bounds.upperBound
        Chart {
            ForEach(points) { point in
                if let inside = point.indoor {
                    AreaMark(x: .value("Time", point.date),
                             yStart: .value("Bottom", low),
                             yEnd: .value("Inside", inside))
                        .foregroundStyle(LinearGradient(colors: [Color(hex: 0xB4E7CD, opacity: 0.5),
                                                                 Color(hex: 0xB4E7CD, opacity: 0)],
                                                        startPoint: .top,
                                                        endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", point.date),
                             y: .value("Temperature", inside),
                             series: .value("Probe", "Inside"))
                        .foregroundStyle(Theme.inside)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
                if let outside = point.outdoor {
                    LineMark(x: .value("Time", point.date),
                             y: .value("Temperature", outside),
                             series: .value("Probe", "Outside"))
                        .foregroundStyle(Theme.outside)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
            }
        }
        .chartYScale(domain: low...high)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 5]))
                AxisValueLabel(format: range.axisFormat)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 5]))
                AxisValueLabel()
            }
        }
        .accessibilityLabel("Indoor and outdoor temperature, \(range.title)")
    }
}

// MARK: - Shortcuts

struct QuickLinks: View {
    @Environment(Station.self) var station
    @Binding var tab: AppTab

    var body: some View {
        HStack(spacing: 12) {
            QuickCard(title: "Light studio",
                      detail: lightDetail,
                      icon: "lightbulb",
                      tint: Color(hex: 0x4C6A98),
                      tile: LinearGradient(colors: [Color(hex: 0xD9E9FA), Color(hex: 0xF1DCBB)],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing)) {
                tab = .lighting
            }
            QuickCard(title: "IR workspace",
                      detail: "Scan and try codes",
                      icon: "dot.radiowaves.right",
                      tint: Color(hex: 0xB26A47),
                      tile: LinearGradient(colors: [Color(hex: 0xFBE6D7), Color(hex: 0xF7DCC8)],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing)) {
                tab = .ir
            }
        }
    }

    var lightDetail: String {
        guard let light = station.light else { return "Scenes and colors" }
        return light.on ? "\(light.label) · \(light.brightness) %" : "Off"
    }
}

struct QuickCard: View {
    let title: String
    let detail: String
    let icon: String
    let tint: Color
    let tile: LinearGradient
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 48, height: 48)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tile))
                    .padding(.bottom, 6)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            .card(padding: 14)
        }
        .buttonStyle(.plain)
    }
}
