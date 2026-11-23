import SwiftUI

struct LogView: View {
    @Environment(Station.self) var station
    @State var filter: LogKind?
    @State var paused = false
    @State var frozen: [LogLine] = []

    var body: some View {
        let lines = visibleLines
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    PageHeading(eyebrow: "Diagnostics",
                                title: "Live log",
                                subtitle: Text("Everything your ESP32 prints, as it happens"))
                    OfflineCard()
                    filterChips
                    HStack(spacing: 10) {
                        Button {
                            togglePause()
                        } label: {
                            Label(paused ? "Resume" : "Pause", systemImage: paused ? "play.fill" : "pause.fill")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        ShareLink(item: exportText(lines)) {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(SecondaryButtonStyle(tone: .mint))
                    }
                    linesCard(lines)
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .onChange(of: station.logLines.count) { _, _ in
                if !paused {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
        .background(Theme.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: station.link) {
            while !Task.isCancelled {
                await station.pollLog()
                try? await Task.sleep(nanoseconds: station.link == .away ? 3_000_000_000 : 1_000_000_000)
            }
        }
    }

    var visibleLines: [LogLine] {
        let source = paused ? frozen : station.logLines
        guard let filter else { return source }
        return source.filter { $0.kind == filter }
    }

    func togglePause() {
        if paused {
            paused = false
        } else {
            frozen = station.logLines
            paused = true
        }
    }

    var filterChips: some View {
        var options: [(LogKind?, String)] = [(nil, "All")]
        for kind in LogKind.allCases {
            options.append((kind, kind.title))
        }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options.indices, id: \.self) { index in
                    chip(kind: options[index].0, title: options[index].1)
                }
            }
        }
    }

    func chip(kind: LogKind?, title: String) -> some View {
        let selected = kind == filter
        return Button {
            filter = kind
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(selected ? Color.white : Theme.buttonText)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(Capsule().fill(selected ? Theme.teal : Theme.panel))
                .overlay(Capsule().strokeBorder(selected ? Theme.teal : Theme.buttonBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    func linesCard(_ lines: [LogLine]) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if lines.isEmpty {
                Text(station.isConnected ? "Waiting for log lines…" : "No log yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .padding(.vertical, 16)
            }
            ForEach(lines) { line in
                LogRow(line: line)
            }
        }
        .card(padding: 14)
    }

    func exportText(_ lines: [LogLine]) -> String {
        lines.map { line in
            let time = line.time.map { LogRow.timeFormatter.string(from: $0) } ?? "--:--:--"
            return "\(time) [\(line.kind.tag)] \(line.text)"
        }
        .joined(separator: "\n")
    }
}

struct LogRow: View {
    let line: LogLine

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(line.time.map { LogRow.timeFormatter.string(from: $0) } ?? "earlier")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .frame(width: 60, alignment: .leading)
            Text(line.kind.tag)
                .font(.system(size: 9, weight: .heavy))
                .kerning(0.6)
                .foregroundStyle(line.kind.tagForeground)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(line.kind.tagBackground))
            Text(line.text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}

extension LogKind {
    var tagBackground: Color {
        switch self {
        case .system: return Color(hex: 0xEEF1F6)
        case .sensor: return Color(hex: 0xE4F4EB)
        case .light: return Color(hex: 0xFFF4E3)
        case .ir: return Color(hex: 0xFFF0E9)
        }
    }

    var tagForeground: Color {
        switch self {
        case .system: return Color(hex: 0x3D5470)
        case .sensor: return Color(hex: 0x2F6B5E)
        case .light: return Color(hex: 0x8A5A14)
        case .ir: return Color(hex: 0xA3463A)
        }
    }
}
