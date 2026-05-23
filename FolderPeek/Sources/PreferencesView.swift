import SwiftUI
import FolderPeekCore

struct PreferencesView: View {
    @AppStorage("fontSize") private var fontSize = PreviewPreferences.default.fontSize
    @AppStorage("appearanceMode") private var appearanceMode = PreviewPreferences.default.appearanceMode.rawValue
    @AppStorage("showHiddenFiles") private var showHiddenFiles = PreviewPreferences.default.showHiddenFiles
    @AppStorage("foldersFirst") private var foldersFirst = PreviewPreferences.default.foldersFirst
    @AppStorage("itemLimit") private var itemLimit = PreviewPreferences.default.itemLimit

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
        }
        .padding(24)
        .frame(width: 420)
    }
}
