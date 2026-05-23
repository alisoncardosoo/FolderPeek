import SwiftUI
import AppKit
import FolderPeekCore

// MARK: - Window Glass Accessor

private struct WindowGlassAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.backgroundColor = .windowBackgroundColor
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - App Tab

private enum AppTab: CaseIterable {
    case home, settings, about

    var label: String {
        switch self {
        case .home:     "Home"
        case .settings: "Configurações"
        case .about:    "Sobre"
        }
    }

    var icon: String {
        switch self {
        case .home:     "house.fill"
        case .settings: "gearshape.fill"
        case .about:    "info.circle.fill"
        }
    }
}

// MARK: - Root View

struct ContentView: View {
    @State private var selectedTab: AppTab = .home
    @AppStorage("fontSize")       private var fontSize       = PreviewPreferences.default.fontSize
    @AppStorage("appearanceMode") private var appearanceMode = PreviewPreferences.default.appearanceMode.rawValue
    @AppStorage("showHiddenFiles") private var showHiddenFiles = PreviewPreferences.default.showHiddenFiles
    @AppStorage("foldersFirst")   private var foldersFirst   = PreviewPreferences.default.foldersFirst
    @AppStorage("itemLimit")      private var itemLimit      = PreviewPreferences.default.itemLimit

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 440, minHeight: 500)
        .background(WindowGlassAccessor().frame(width: 0, height: 0))
    }

    // MARK: Tab Bar

    @ViewBuilder
    private var tabBar: some View {
        if #available(macOS 26.0, *) {
            glassTabBar
        } else {
            fallbackTabBar
        }
    }

    @available(macOS 26.0, *)
    private var glassTabBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(AppTab.allCases, id: \.label) { tab in
                    let isSelected = selectedTab == tab
                    Button { selectedTab = tab } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 18, weight: .medium))
                            Text(tab.label)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 18)
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .glassEffect(
                        isSelected
                            ? .regular.tint(Color.accentColor.opacity(0.15)).interactive()
                            : .regular.interactive(),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var fallbackTabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.label) { tab in
                Button { selectedTab = tab } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: .medium))
                        Text(tab.label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .background(.ultraThinMaterial)
    }

    // MARK: Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .home:
            HomeTab()
        case .settings:
            SettingsTab(
                fontSize: $fontSize,
                appearanceMode: $appearanceMode,
                showHiddenFiles: $showHiddenFiles,
                foldersFirst: $foldersFirst,
                itemLimit: $itemLimit
            )
        case .about:
            AboutTab()
        }
    }
}

// MARK: - Home Tab

private struct HomeTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                appHeader
                extensionStatusCard
                appLocationCard
                activationStepsCard
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            Text("FolderPeek v1.0")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)
        }
    }

    private var appHeader: some View {
        HStack(spacing: 14) {
            Image("FolderPeekLogo")
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text("FolderPeek")
                    .font(.title.bold())
                Text("Pré-visualize pastas e arquivos compactados diretamente no Finder.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var extensionStatusCard: some View {
        PeekCard {
            Label("FolderPeek instalado e ativo", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text("Ative a extensão nos Ajustes do Sistema e pressione Espaço sobre qualquer pasta ou ZIP no Finder.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var appLocationCard: some View {
        PeekCard {
            Label("Localização do app", systemImage: "mappin.circle.fill")
                .font(.headline)
            Text(AppActions.appLocationText())
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 10) {
                Button {
                    AppActions.revealAppInFinder()
                } label: {
                    Label("Mostrar no Finder", systemImage: "folder")
                }
                Button {
                    AppActions.openQuickLookExtensionsSettings()
                } label: {
                    Label("Ajustes de Extensões", systemImage: "gearshape")
                }
            }
        }
    }

    private var activationStepsCard: some View {
        PeekCard {
            Label("Ativar no macOS", systemImage: "switch.2")
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                Label("Abra Ajustes do Sistema", systemImage: "1.circle.fill")
                Label("Vá em Geral › Itens de Início e Extensões › Quick Look", systemImage: "2.circle.fill")
                Label("Ative FolderPeek nas Extensões", systemImage: "3.circle.fill")
                Label("No Finder, pressione Espaço ou ⌘Y para visualizar", systemImage: "4.circle.fill")
            }
            .foregroundStyle(.primary)
        }
    }
}

// MARK: - Settings Tab

private struct SettingsTab: View {
    @Binding var fontSize: Double
    @Binding var appearanceMode: String
    @Binding var showHiddenFiles: Bool
    @Binding var foldersFirst: Bool
    @Binding var itemLimit: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                appearanceSection
                behaviorSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PeekSectionLabel(icon: "paintbrush.fill", title: "Aparência")
            PeekCard {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Tema do app", systemImage: "circle.lefthalf.filled")
                        .font(.subheadline.weight(.medium))
                    Picker("Tema do app", selection: $appearanceMode) {
                        ForEach(PreviewAppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                Divider()
                PeekRow(label: "Tamanho do texto", icon: "textformat.size") {
                    HStack {
                        Slider(value: $fontSize, in: 11...18, step: 1)
                            .frame(maxWidth: 140)
                        Text("\(Int(fontSize)) pt")
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PeekSectionLabel(icon: "slider.horizontal.3", title: "Comportamento")
            PeekCard {
                PeekRow(label: "Limite de itens por preview", icon: "list.number") {
                    Stepper("\(itemLimit)", value: $itemLimit, in: 100...5000, step: 100)
                }
                Divider()
                PeekRow(label: "Mostrar arquivos ocultos", icon: "eye") {
                    Toggle("", isOn: $showHiddenFiles).labelsHidden()
                }
                Divider()
                PeekRow(label: "Pastas primeiro", icon: "folder.fill") {
                    Toggle("", isOn: $foldersFirst).labelsHidden()
                }
            }
        }
    }
}

// MARK: - About Tab

private struct AboutTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                appIdentity
                linksCard
                aboutAppCard
                privacyCard
                versionCard
                Text("Made with SwiftUI, Finder APIs and too much coffee ☕")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 8)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var appIdentity: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FolderPeek")
                .font(.title.bold())
            Text("Pré-visualizações nativas de pastas e arquivos compactados no macOS.")
                .foregroundStyle(.secondary)
            Text("Desenvolvido por **Alison Cardoso** — Developer focused on native macOS experiences, SaaS products and modern software design.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var linksCard: some View {
        PeekCard {
            Label("Links", systemImage: "link")
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                PeekLink(icon: "globe",                          label: "Website Portfolio",             url: "https://www.alisoncardoso.dev.br")
                PeekLink(icon: "chevron.left.forwardslash.chevron.right", label: "GitHub  github.com/alisoncardosoo", url: "https://github.com/alisoncardosoo")
                PeekLink(icon: "person.crop.rectangle",          label: "LinkedIn  linkedin.com/in/alisoncardosoo", url: "https://linkedin.com/in/alisoncardosoo")
                PeekLink(icon: "envelope",                       label: "Report an Issue  suporte@alisoncardoso.dev.br", url: "mailto:suporte@alisoncardoso.dev.br")
            }
        }
    }

    private var aboutAppCard: some View {
        PeekCard {
            Label("Sobre o App", systemImage: "app.badge.checkmark")
                .font(.headline)
            Text("FolderPeek traz pré-visualizações nativas de pastas e arquivos compactados diretamente no Finder.\n\nDesenhado para ser leve, rápido e integrado ao macOS.\n\nSem complexidade desnecessária. Basta pressionar Espaço e visualizar.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var privacyCard: some View {
        PeekCard {
            Label("Privacidade", systemImage: "lock.shield.fill")
                .font(.headline)
            Text("FolderPeek nunca faz upload ou leitura dos seus arquivos online. Todas as pré-visualizações acontecem localmente no seu Mac.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var versionCard: some View {
        PeekCard {
            Label("Versão", systemImage: "tag.fill")
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                Text("FolderPeek v1.0.0")
                    .font(.system(.body, design: .monospaced))
                Text("Build 1  ·  macOS 14+")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Shared Components

private struct PeekCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct PeekSectionLabel: View {
    let icon: String
    let title: String

    var body: some View {
        Label(title.uppercased(), systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct PeekRow<Control: View>: View {
    let label: String
    let icon: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack {
            Label(label, systemImage: icon)
            Spacer()
            control
        }
    }
}

private struct PeekLink: View {
    let icon: String
    let label: String
    let url: String

    var body: some View {
        if let destination = URL(string: url) {
            Link(destination: destination) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .frame(width: 18)
                        .foregroundStyle(.secondary)
                    Text(label)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }
}
