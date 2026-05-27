import AppKit
import SwiftUI
import FolderPeekCore

struct PreferencesView: View {
    let updaterController: UpdaterController

    @AppStorage("fontSize") private var fontSize = PreviewPreferences.default.fontSize
    @AppStorage("appearanceMode") private var appearanceMode = PreviewPreferences.default.appearanceMode.rawValue
    @AppStorage("showHiddenFiles") private var showHiddenFiles = PreviewPreferences.default.showHiddenFiles
    @AppStorage("foldersFirst") private var foldersFirst = PreviewPreferences.default.foldersFirst
    @AppStorage("itemLimit") private var itemLimit = PreviewPreferences.default.itemLimit
    @AppStorage("autoShowOnDrag") private var autoShowOnDrag = true
    @AppStorage("shelfHotkeyCode") private var hotkeyCode = 49
    @AppStorage("shelfHotkeyModifiers") private var hotkeyModifiers = 786432
    @AppStorage("shelfHotkeyDisplayName") private var hotkeyDisplayName = "Space"

    var body: some View {
        Form {
            Section("Tema do app") {
                Picker("Quando usar tema escuro", selection: $appearanceMode) {
                    ForEach(PreviewAppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Text(PreviewAppearanceMode(storedValue: appearanceMode).description)
                    .foregroundStyle(.secondary)
            }

            Slider(value: $fontSize, in: 11...18, step: 1) {
                Text("Tamanho do texto")
            }
            Toggle("Mostrar arquivos ocultos", isOn: $showHiddenFiles)
            Toggle("Pastas primeiro", isOn: $foldersFirst)
            Stepper("Limite: \(itemLimit) itens", value: $itemLimit, in: 100...5000, step: 100)

            Section("Bandeja temporária") {
                Toggle("Abrir bandeja ao iniciar drag no Finder", isOn: $autoShowOnDrag)
                HotkeyRecorderRow(
                    hotkeyCode: $hotkeyCode,
                    hotkeyModifiers: $hotkeyModifiers,
                    hotkeyDisplayName: $hotkeyDisplayName
                )
            }

            Section("Atualizacoes") {
                Text("Versao instalada: \(installedVersion)")
                    .foregroundStyle(.secondary)

                Button("Verificar atualizacoes…") {
                    updaterController.checkForUpdates()
                }

                if let releaseNotesURL {
                    Link("Abrir release notes", destination: releaseNotesURL)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private var installedVersion: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(shortVersion) (\(build))"
    }

    private var releaseNotesURL: URL? {
        URL(string: "https://github.com/alisoncardosoo/FolderPeek/releases")
    }
}

// MARK: - Hotkey Recorder

extension Notification.Name {
    fileprivate static let shelfHotkeyRecorded = Notification.Name("folderPeekShelfHotkeyRecorded")
}

@MainActor
private final class HotkeyRecorder: ObservableObject {
    @Published var isRecording = false
    private nonisolated(unsafe) var monitor: Any?

    func start() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !event.isARepeat else { return event }
            if event.keyCode == 53 { // Escape — cancel recording
                MainActor.assumeIsolated { self.stop() }
                return nil
            }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !mods.isEmpty else { return event }
            let userInfo: [String: Any] = [
                "code": Int(event.keyCode),
                "modifiers": Int(mods.rawValue),
                "name": HotkeyRecorder.keyName(for: event)
            ]
            MainActor.assumeIsolated { self.stop() }
            NotificationCenter.default.post(name: .shelfHotkeyRecorded, object: nil, userInfo: userInfo)
            return nil
        }
    }

    func stop() {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    deinit { if let m = monitor { NSEvent.removeMonitor(m) } }

    static func keyName(for event: NSEvent) -> String {
        switch event.keyCode {
        case 36: return "↩"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "Esc"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return event.charactersIgnoringModifiers?.uppercased() ?? "Key\(event.keyCode)"
        }
    }
}

private struct HotkeyRecorderRow: View {
    @Binding var hotkeyCode: Int
    @Binding var hotkeyModifiers: Int
    @Binding var hotkeyDisplayName: String
    @StateObject private var recorder = HotkeyRecorder()

    var body: some View {
        HStack {
            Text("Atalho da bandeja")
            Spacer()
            Button {
                if recorder.isRecording { recorder.stop() } else { recorder.start() }
            } label: {
                Text(recorder.isRecording ? "Pressione a combinação…" : hotkeyLabel)
                    .foregroundStyle(recorder.isRecording ? .orange : .primary)
                    .frame(minWidth: 110, alignment: .center)
            }
            .buttonStyle(.bordered)
        }
        .onReceive(NotificationCenter.default.publisher(for: .shelfHotkeyRecorded)) { notif in
            guard let info = notif.userInfo,
                  let code = info["code"] as? Int,
                  let mods = info["modifiers"] as? Int,
                  let name = info["name"] as? String else { return }
            hotkeyCode = code
            hotkeyModifiers = mods
            hotkeyDisplayName = name
        }
    }

    private var hotkeyLabel: String {
        let mods = NSEvent.ModifierFlags(rawValue: UInt(hotkeyModifiers))
        var parts: [String] = []
        if mods.contains(.control) { parts.append("⌃") }
        if mods.contains(.option) { parts.append("⌥") }
        if mods.contains(.shift) { parts.append("⇧") }
        if mods.contains(.command) { parts.append("⌘") }
        parts.append(hotkeyDisplayName)
        return parts.joined()
    }
}
