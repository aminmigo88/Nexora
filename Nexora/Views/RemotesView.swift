import SwiftUI

struct RemotesView: View {
    @Environment(Station.self) var station
    @State var selected = 0
    @State var drafts: [RemoteProfile] = []
    @State var baseline: [RemoteProfile] = []
    @State var saving = false
    @State var savedNote: String?
    @State var formError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                TopBar()
                PageHeading(eyebrow: "Remote translator",
                            title: "Your remotes, simplified.",
                            subtitle: Text("When the IR receiver gets a generic remote code, the ESP32 sends that key's original code (NEC)."))
                OfflineCard()
                if drafts.count == 3 && baseline.count == 3 {
                    VStack(spacing: 14) {
                        remotePicker
                        editorCard
                    }
                    .disabled(!station.isConnected)
                } else if station.isConnected {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .refreshable { await station.loadRemotes() }
        .task(id: station.link) {
            if station.isConnected {
                await station.loadRemotes()
            }
        }
        .onChange(of: station.remotes) { _, fresh in
            adopt(fresh)
        }
        .onAppear { adopt(station.remotes) }
    }

    /// Takes the controller's copy, but keeps keys you're still editing.
    func adopt(_ fresh: [RemoteProfile]) {
        guard fresh.count == 3 else { return }
        guard drafts.count == 3, baseline.count == 3 else {
            drafts = fresh
            baseline = fresh
            return
        }
        for index in 0..<3 where drafts[index] == baseline[index] {
            drafts[index] = fresh[index]
        }
        baseline = fresh
    }

    var isDirty: Bool {
        drafts.count == 3 && baseline.count == 3 && drafts[selected] != baseline[selected]
    }

    // MARK: Picker

    var remotePicker: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Button {
                    selected = index
                    savedNote = nil
                    formError = nil
                } label: {
                    RemoteTab(index: index, profile: drafts[index], selected: selected == index)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected == index ? .isSelected : [])
            }
        }
        .padding(8)
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

    // MARK: Editor

    var editorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Key mapping", subtitle: "5 keys per remote · names up to 19 characters")
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel("Remote name")
                TextField("Remote name", text: nameBinding)
                    .nexoraField()
            }
            ForEach(0..<5, id: \.self) { k in
                KeyEditor(number: k + 1, key: keyBinding(k))
            }
            if let formError {
                Text(formError)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.dangerText)
            }
            HStack(spacing: 12) {
                Button {
                    Task { await save() }
                } label: {
                    Label(saving ? "Saving…" : "Save to ESP32", systemImage: "checkmark")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(saving || !isDirty)
                if let savedNote {
                    Text(savedNote)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Theme.tealText)
                } else if isDirty {
                    Text("Not saved")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Color(hex: 0x8A5A14))
                }
            }
            .padding(.top, 4)
        }
        .card()
    }

    var nameBinding: Binding<String> {
        Binding(
            get: { drafts[selected].name },
            set: { newValue in
                drafts[selected].name = UTF8Limit.clamp(newValue, 19)
                savedNote = nil
            }
        )
    }

    func keyBinding(_ k: Int) -> Binding<RemoteKey> {
        Binding(
            get: { drafts[selected].keys[k] },
            set: { newValue in
                drafts[selected].keys[k] = newValue
                savedNote = nil
            }
        )
    }

    func save() async {
        let profile = drafts[selected]
        for (k, key) in profile.keys.enumerated() {
            if !Hex.isValidOrEmpty(key.orig) || !Hex.isValidOrEmpty(key.gen) {
                formError = "Key \(k + 1): codes must be hex, like 0x00FE0FF0."
                return
            }
        }
        formError = nil
        saving = true
        let ok = await station.saveRemote(selected, profile)
        saving = false
        if ok && station.remotes.count == 3 {
            drafts[selected] = station.remotes[selected]
            baseline = station.remotes
            savedNote = "Saved"
        }
    }
}

struct RemoteTab: View {
    let index: Int
    let profile: RemoteProfile
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: index == 0 ? "fan" : "av.remote")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: 0xB26A47))
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color(hex: 0xF3E6D6)))
                .accessibilityHidden(true)
            Text(profile.name.isEmpty ? "Remote \(index + 1)" : profile.name)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(profile.mappedCount == 1 ? "1 mapped key" : "\(profile.mappedCount) mapped keys")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(selected ? Theme.tileActive : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

struct KeyEditor: View {
    let number: Int
    @Binding var key: RemoteKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("\(number)")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Theme.mintText)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Theme.mint))
                    .accessibilityHidden(true)
                TextField("Key \(number)", text: nameBinding)
                    .nexoraField()
                    .accessibilityLabel("Key \(number) name")
            }
            HStack(alignment: .top, spacing: 8) {
                codeField(title: "Original code", text: $key.orig)
                codeField(title: "Generic remote code", text: $key.gen)
            }
        }
        .padding(.top, 14)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.divider).frame(height: 1)
        }
    }

    var nameBinding: Binding<String> {
        Binding(
            get: { key.name },
            set: { newValue in key.name = UTF8Limit.clamp(newValue, 19) }
        )
    }

    func codeField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            FieldLabel(title)
            TextField("0x…", text: Binding(
                get: { text.wrappedValue },
                set: { newValue in text.wrappedValue = String(newValue.prefix(10)) }
            ))
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .keyboardType(.asciiCapable)
            .nexoraField(mono: true)
            .accessibilityLabel("Key \(number) \(title)")
        }
        .frame(maxWidth: .infinity)
    }
}
