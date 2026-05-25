import SwiftUI
import AppKit
import CoreImage
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
    case home, settings, about, donation

    var label: String {
        switch self {
        case .home:     "Home"
        case .settings: "Configurações"
        case .about:    "Sobre"
        case .donation: "Doação"
        }
    }

    var icon: String {
        switch self {
        case .home:     "house.fill"
        case .settings: "gearshape.fill"
        case .about:    "info.circle.fill"
        case .donation: "heart.fill"
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
            HomeTab(onDonateTap: { selectedTab = .donation })
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
        case .donation:
            DonationTab()
        }
    }
}

// MARK: - Home Tab

private struct HomeTab: View {
    let onDonateTap: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                appHeader
                extensionStatusCard
                appLocationCard
                activationStepsCard
                donationCTA
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            Text("FolderPeek v1.1")
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

    private var donationCTA: some View {
        PeekCard {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.pink)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gostou do FolderPeek?")
                        .font(.headline)
                    Text("Abra a aba de doação para apoiar o desenvolvimento com PIX.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Doar") {
                    onDonateTap()
                }
                .buttonStyle(.borderedProminent)
            }
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
                Text("FolderPeek v1.1.0")
                    .font(.system(.body, design: .monospaced))
                Text("Build 2  ·  macOS 14+")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Donation Tab

private struct DonationTab: View {
    private let pixKey = "d6d63f9b-5e12-4b96-8f33-d2b83a23e86d"
    @State private var didCopyKey = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroCard
                pixCard
                qrCard
                supportCard
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            Text("Obrigado por apoiar o projeto")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)
        }
    }

    private var heroCard: some View {
        PeekCard {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.pink)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Apoie o desenvolvedor")
                        .font(.title3.bold())
                    Text("Se o FolderPeek te ajudou, uma doação via PIX mantém o projeto vivo, leve e independente.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var pixCard: some View {
        PeekCard {
            Label("Chave PIX", systemImage: "qrcode")
                .font(.headline)
            Text(pixKey)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 10) {
                Button {
                    copyPixKey()
                } label: {
                    Label(didCopyKey ? "Copiado" : "Copiar chave PIX", systemImage: didCopyKey ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)

                Text("Abra o app do banco ou use o QR code abaixo.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var qrCard: some View {
        PeekCard {
            Label("QR Code", systemImage: "camera.viewfinder")
                .font(.headline)
            Text("Escaneie com seu app de pagamento ou copie a chave acima.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Group {
                if let qrImage = DonationQRCodeRenderer.makeImage(text: pixKey) {
                    Image(nsImage: qrImage)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .padding(18)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(.quaternary, lineWidth: 1)
                        )
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 38))
                            .foregroundStyle(.secondary)
                        Text("Não foi possível gerar o QR code.")
                            .font(.headline)
                        Text("Use a chave PIX acima para concluir a doação.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var supportCard: some View {
        PeekCard {
            Label("Obrigado por ajudar", systemImage: "sparkles")
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                Text("Toda contribuição ajuda a manter o app disponível, corrigido e com novas melhorias.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Doação livre, sem valor mínimo.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func copyPixKey() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pixKey, forType: .string)
        didCopyKey = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            didCopyKey = false
        }
    }
}

private enum DonationQRCodeRenderer {
    static func makeImage(text: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return nil }
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: scaledImage.extent.width, height: scaledImage.extent.height))
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
