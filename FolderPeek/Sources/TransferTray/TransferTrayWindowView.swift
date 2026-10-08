import AppKit
import SwiftUI
import UniformTypeIdentifiers
import FolderPeekCore

fileprivate let transferTrayItemExportedNotification = Notification.Name("FolderPeekTransferTrayItemExported")

enum TransferTrayViewMode: String, CaseIterable, Identifiable {
    case list
    case grid

    static let preferenceKey = "transferTrayViewMode"
    var id: String { rawValue }
    var title: String { self == .list ? "Lista" : "Grade" }
    var symbol: String { self == .list ? "list.bullet" : "square.grid.2x2" }

    static var saved: Self {
        Self(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "") ?? .list
    }

    func windowSize(itemCount: Int) -> CGSize {
        switch self {
        case .list:
            return CGSize(width: 360, height: max(240, 110 + min(max(0, itemCount), 6) * 66))
        case .grid:
            let layout = TransferTrayLayout(itemCount: itemCount)
            return CGSize(width: max(300, layout.windowSize.width), height: layout.windowSize.height + 42)
        }
    }
}

struct TransferTrayWindowView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: TransferTrayStore
    let hideWindow: () -> Void
    let configureWindow: (NSWindow) -> Void
    let resizeWindow: (Int) -> Void

    @AppStorage(TransferTrayViewMode.preferenceKey) private var viewMode = TransferTrayViewMode.list

    @State private var isDropTarget = false
    @State private var selectedItemIDs: Set<String> = []
    @State private var selectionAnchorID: String?

    var body: some View {
        VStack(spacing: 0) {
            header
                .zIndex(2)
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 10)

            if store.isProcessing {
                progressView
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            trayContent
                .padding(.horizontal, 14)

            if let msg = store.statusMessage {
                statusBar(msg)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                if !store.items.isEmpty {
                    Text("Arraste para adicionar ou retirar")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                } else {
                    Spacer(minLength: 8)
                }
            }
        }
        .frame(minWidth: 220, minHeight: 200)
        .background(shelfBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(borderOverlay)
        .overlayPreferenceValue(TrayTooltipPreference.self) { tips in
            GeometryReader { geometry in
                if let tip = tips.last {
                    TrayTooltipOverlay(tip: tip, geometry: geometry)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .shadow(color: .black.opacity(0.24), radius: 22, y: 10)
        .overlay(dropTargetHighlight.allowsHitTesting(false))
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTarget, perform: handleDrop(providers:))
        .alert("Mover arquivos?", isPresented: $store.showMoveConfirmation) {
            Button("Cancelar", role: .cancel) { store.cancelMoveTransfer() }
            Button("Mover", role: .destructive) { store.confirmMoveTransfer() }
        } message: {
            Text("Esta ação remove os arquivos da origem. Use Desfazer no menu para reverter.")
        }
        .background(TransferTraySelectionShortcuts(selectAll: selectAllItems).frame(width: 0, height: 0))
        .background(
            TransferTrayWindowAccessor(onResolveWindow: configureWindow).frame(width: 0, height: 0)
        )
        .ignoresSafeArea()
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: store.isProcessing)
        .animation(.easeInOut(duration: 0.18), value: store.statusMessage != nil)
        .onReceive(NotificationCenter.default.publisher(for: transferTrayItemExportedNotification)) { notification in
            guard let sourceURL = notification.object as? URL else { return }
            if let error = notification.userInfo?["error"] as? String {
                store.statusMessage = "Não foi possível entregar \(sourceURL.lastPathComponent): \(error)"
                return
            }
            let destinationURL = notification.userInfo?["destinationURL"] as? URL
            let exportedItemID = TransferItemCollection.canonicalPath(for: sourceURL)
            selectedItemIDs.remove(exportedItemID)
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                store.consumeItemAfterExternalDrop(sourceURL: sourceURL, destinationURL: destinationURL)
            }
        }
        .onChange(of: store.items.map(\.id)) { _, itemIDs in
            pruneSelection(validItemIDs: itemIDs)
        }
        .onChange(of: viewMode) { _, _ in
            resizeWindow(store.items.count)
        }
        .onChange(of: store.items.count) { _, count in
            resizeWindow(count)
        }
    }

    // MARK: - Background

    private var shelfBackground: some View {
        ZStack {
            TrayFrostedBackground()
            // A light tint over the native blur; keep the material at full strength.
            (colorScheme == .dark
                ? Color(red: 0.10, green: 0.12, blue: 0.15)
                : Color.white)
                .opacity(0.10)
        }
        .allowsHitTesting(false)
    }

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(LinearGradient(
                colors: colorScheme == .dark
                    ? [Color.white.opacity(0.42), Color.white.opacity(0.08), Color.white.opacity(0.20)]
                    : [Color.white.opacity(0.75), Color.black.opacity(0.08), Color.black.opacity(0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ), lineWidth: 0.75)
            .allowsHitTesting(false)
    }

    private var dropTargetHighlight: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(
                isDropTarget ? Color.accentColor : Color.clear,
                style: StrokeStyle(lineWidth: 2, dash: [7, 5])
            )
            .animation(.easeInOut(duration: 0.15), value: isDropTarget)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.trayTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                    Text(store.items.isEmpty ? "Arraste arquivos para cá" : "\(store.items.count) \(store.items.count == 1 ? "item" : "itens")")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 4)
                headerActions
            }

            Rectangle()
                .fill(.primary.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    private var headerActions: some View {
        HStack(spacing: 6) {
            ForEach(TransferTrayViewMode.allCases) { mode in
                Button {
                    viewMode = mode
                } label: {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(viewMode == mode ? .primary : .secondary)
                        .frame(width: 26, height: 26)
                        .background(.primary.opacity(viewMode == mode ? 0.20 : 0.07), in: Circle())
                        .overlay {
                            Circle().stroke(.primary.opacity(viewMode == mode ? 0.32 : 0), lineWidth: 0.75)
                        }
                }
                .buttonStyle(.plain)
                .trayTooltip("Visualizar em \(mode.title.lowercased())")
                .accessibilityLabel("Visualizar em \(mode.title.lowercased())")
                .accessibilityAddTraits(viewMode == mode ? [.isSelected] : [])
            }

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    store.clearItems()
                }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(.primary.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(store.items.isEmpty || store.isProcessing)
            .trayTooltip("Devolver tudo para a origem")
            .accessibilityLabel("Devolver tudo para a origem")

            Menu {
                Button("Selecionar tudo", action: selectAllItems)
                    .help("Selecionar todos os itens (⌘A)")
                    .disabled(store.items.isEmpty)

                Divider()

                Button {
                    store.revealTrayFolderInFinder()
                } label: {
                    Label("Abrir pasta da Bandeja", systemImage: "folder")
                }

                Divider()

                Button {
                    store.undoLastMove()
                } label: {
                    Label("Desfazer último move", systemImage: "arrow.uturn.backward")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 26, height: 26)
            .background(.primary.opacity(0.07), in: Circle())
            .trayTooltip("Mais opções da bandeja")
            .accessibilityLabel("Opções da bandeja")

            Button(action: hideWindow) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(.primary.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .trayTooltip("Fechar bandeja")
            .accessibilityLabel("Fechar bandeja")
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: store.items.isEmpty)
    }

    // MARK: - Progress

    private var progressView: some View {
        VStack(spacing: 5) {
            ProgressView(value: store.transferProgress)
                .progressViewStyle(.linear)
                .tint(.accentColor)
                .animation(.easeOut(duration: 0.25), value: store.transferProgress)

            HStack {
                Text(store.currentTransferName.isEmpty ? "Processando…" : store.currentTransferName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text("\(Int(store.transferProgress * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Items

    private var trayContent: some View {
        Group {
            if store.items.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    Group {
                        if viewMode == .list {
                            LazyVStack(spacing: 4) {
                                ForEach(store.items) { item in
                                    itemView(item)
                                }
                            }
                        } else {
                            LazyVGrid(
                                columns: Array(
                                    repeating: GridItem(.flexible(), spacing: 10),
                                    count: TransferTrayLayout(itemCount: store.items.count).columns
                                ),
                                spacing: 12
                            ) {
                                ForEach(store.items) { item in
                                    itemView(item)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
                .background(WindowDragBlocker())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func itemView(_ item: TransferTrayStore.Item) -> some View {
        TransferTrayTile(
            item: item,
            thumbnail: store.thumbnail(for: item),
            viewMode: viewMode,
            isSelected: selectedItemIDs.contains(item.id),
            selectedCount: selectedItemIDs.count,
            selectItem: { modifiers in
                applySelection(for: item, modifiers: modifiers)
            },
            prepareDragItems: { modifiers in
                prepareDragItems(for: item, modifiers: modifiers)
            },
            removeItem: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    store.removeItem(item)
                }
            },
            removeSelectedItems: removeSelectedItems
        )
    }

    // MARK: - Selection

    private func selectAllItems() {
        selectedItemIDs = Set(store.items.map(\.id))
        if selectionAnchorID == nil {
            selectionAnchorID = store.items.first?.id
        }
    }

    @discardableResult
    private func applySelection(for item: TransferTrayStore.Item, modifiers: NSEvent.ModifierFlags) -> Set<String> {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        let additive = flags.contains(.command)
        let ranged = flags.contains(.shift)

        let nextSelection: Set<String>
        if ranged {
            let rangeIDs = rangeSelectionIDs(to: item)
            if additive {
                nextSelection = selectedItemIDs.union(rangeIDs)
            } else {
                nextSelection = rangeIDs
            }
        } else if additive {
            var updatedSelection = selectedItemIDs
            if updatedSelection.contains(item.id) {
                updatedSelection.remove(item.id)
            } else {
                updatedSelection.insert(item.id)
            }
            nextSelection = updatedSelection.isEmpty ? [item.id] : updatedSelection
        } else {
            nextSelection = [item.id]
        }

        selectedItemIDs = nextSelection
        if !ranged {
            selectionAnchorID = item.id
        } else if selectionAnchorID == nil {
            selectionAnchorID = item.id
        }
        return nextSelection
    }

    private func prepareDragItems(
        for item: TransferTrayStore.Item,
        modifiers: NSEvent.ModifierFlags
    ) -> [TransferTrayDragItem] {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        let shouldKeepCurrentSelection = selectedItemIDs.contains(item.id)
            && !flags.contains(.command)
            && !flags.contains(.shift)

        let dragIDs = shouldKeepCurrentSelection
            ? selectedItemIDs
            : applySelection(for: item, modifiers: modifiers)

        return dragItems(for: dragIDs, primaryItemID: item.id)
    }

    private func rangeSelectionIDs(to item: TransferTrayStore.Item) -> Set<String> {
        guard let anchorID = selectionAnchorID,
              let anchorIndex = store.items.firstIndex(where: { $0.id == anchorID }),
              let itemIndex = store.items.firstIndex(where: { $0.id == item.id }) else {
            return [item.id]
        }

        let bounds = anchorIndex <= itemIndex
            ? anchorIndex...itemIndex
            : itemIndex...anchorIndex
        return Set(store.items[bounds].map(\.id))
    }

    private func pruneSelection(validItemIDs: [String]) {
        let validIDs = Set(validItemIDs)
        selectedItemIDs.formIntersection(validIDs)
        if let selectionAnchorID, !validIDs.contains(selectionAnchorID) {
            self.selectionAnchorID = selectedItemIDs.first
        }
    }

    private func dragItems(for ids: Set<String>, primaryItemID: String? = nil) -> [TransferTrayDragItem] {
        var items = store.items.filter { ids.contains($0.id) }
        if let primaryItemID,
           let index = items.firstIndex(where: { $0.id == primaryItemID }) {
            let primary = items.remove(at: index)
            items.insert(primary, at: 0)
        }

        return items.map { item in
            TransferTrayDragItem(
                id: item.id,
                url: item.url,
                suggestedName: item.name,
                thumbnail: store.thumbnail(for: item)
            )
        }
    }

    private func removeSelectedItems() {
        let selectedIDs = selectedItemIDs
        guard !selectedIDs.isEmpty else {
            return
        }

        let itemsToRemove = store.items.filter { selectedIDs.contains($0.id) }
        for item in itemsToRemove {
            store.removeItem(item)
        }
        selectedItemIDs.subtract(selectedIDs)
        if let selectionAnchorID, selectedIDs.contains(selectionAnchorID) {
            self.selectionAnchorID = selectedItemIDs.first
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            Image(systemName: "tray")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
                .scaleEffect(isDropTarget ? 1.14 : 1.0)
                .animation(.spring(response: 0.22, dampingFraction: 0.55), value: isDropTarget)

            Text("Bandeja vazia")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Arraste arquivos ou pastas aqui\nUse ⌃⌥Space para abrir / fechar")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            if let dest = store.destinationURL {
                Label(dest.lastPathComponent, systemImage: "folder.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Status Bar

    private func statusBar(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                withAnimation { store.statusMessage = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .trayTooltip("Ocultar mensagem", above: true)
            .accessibilityLabel("Ocultar mensagem")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.secondary.opacity(0.1))
        )
    }

    // MARK: - Drop Handler

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard providers.contains(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        store.beginReceivingDrop()
        extractURLs(from: providers) { urls in
            Task { @MainActor in
                defer { store.finishReceivingDrop() }
                guard !urls.isEmpty else {
                    store.statusMessage = "Não foi possível ler os arquivos deste arraste."
                    return
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    store.addFiles(urls)
                }
            }
        }
        return true
    }

    private func extractURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        final class URLBox: @unchecked Sendable {
            private var urls: [URL] = []
            private let lock = NSLock()
            func append(_ url: URL) { lock.withLock { urls.append(url) } }
            func all() -> [URL] { lock.withLock { urls } }
        }

        let group = DispatchGroup()
        let box = URLBox()

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data,
                   let text = String(data: data, encoding: .utf8),
                   let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                   url.isFileURL {
                    box.append(url)
                    return
                }
                if let url = (item as? NSURL) as URL? { box.append(url); return }
                if let url = item as? URL { box.append(url) }
            }
        }

        group.notify(queue: .main) {
            completion(box.all().filter(\.isFileURL))
        }
    }
}

// MARK: - File Tile

private struct TransferTrayTile: View {
    let item: TransferTrayStore.Item
    let thumbnail: NSImage
    let viewMode: TransferTrayViewMode
    let isSelected: Bool
    let selectedCount: Int
    let selectItem: (NSEvent.ModifierFlags) -> Void
    let prepareDragItems: (NSEvent.ModifierFlags) -> [TransferTrayDragItem]
    let removeItem: () -> Void
    let removeSelectedItems: () -> Void

    @State private var isHovered = false

    var body: some View {
        Group {
            if viewMode == .list {
                listContent
            } else {
                gridContent
            }
        }
        .padding(.vertical, viewMode == .list ? 9 : 8)
        .padding(.horizontal, viewMode == .list ? 10 : 6)
        .contentShape(Rectangle())
        .background(selectionBackground)
        .overlay(selectionBorder)
        .onTapGesture {
            selectItem(NSEvent.modifierFlags)
        }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .animation(.spring(response: 0.2, dampingFraction: 0.78), value: isSelected)
        .contextMenu {
            if isSelected && selectedCount > 1 {
                Button("Remover \(selectedCount) selecionados", role: .destructive) {
                    removeSelectedItems()
                }
                Divider()
            }
            Button("Remover da bandeja", role: .destructive) { removeItem() }
        }
        .help(item.url.path(percentEncoded: false))
    }

    private var listContent: some View {
        HStack(spacing: 10) {
            HStack(spacing: 12) {
                filePreview(size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(item.status == .ready ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(fileDetail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .overlay(dragLayer)

            removeButton
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
                .accessibilityHidden(!isHovered)
        }
    }

    private var gridContent: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                filePreview(size: 58)
                    .overlay(dragLayer)
                if isHovered {
                    removeButton.offset(x: 8, y: -8)
                }
            }
            Text(item.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
                .frame(height: 28)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
                .foregroundStyle(item.status == .ready ? .primary : .secondary)
        }
    }

    private func filePreview(size: CGFloat) -> some View {
        Image(nsImage: thumbnail)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 3, y: 1)
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    selectionBadge
                } else {
                    statusBadge
                }
            }
    }

    private var dragLayer: some View {
        FileDragLayer(
            defaultDragItems: [TransferTrayDragItem(
                id: item.id,
                url: item.url,
                suggestedName: item.name,
                thumbnail: thumbnail
            )],
            prepareDragItems: prepareDragItems
        )
    }

    private var removeButton: some View {
        Button(action: removeItem) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(.primary.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .trayTooltip("Devolver para a origem", above: true)
        .accessibilityLabel("Devolver \(item.name) para a origem")
    }

    private var fileDetail: String {
        if case .failure(let message) = item.status { return message }
        if item.status == .success { return "Concluído" }
        let isDirectory = (try? item.url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        if isDirectory { return "Pasta" }
        let kind = item.url.pathExtension.isEmpty ? "Arquivo" : item.url.pathExtension.uppercased()
        guard let byteSize = item.byteSize else { return kind }
        return "\(kind) · \(FolderPeekFormatters.sizeString(byteSize))"
    }

    private var selectionBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
    }

    private var selectionBorder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(isSelected ? Color.accentColor.opacity(0.38) : Color.clear, lineWidth: 1.2)
    }

    private var selectionBadge: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 14))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color.accentColor)
            .offset(x: 5, y: -5)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch item.status {
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.white, .green)
                .offset(x: 5, y: -5)
        case .failure:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.white, .red)
                .offset(x: 5, y: -5)
        case .ready:
            EmptyView()
        }
    }
}

// MARK: - Visible Button Tooltips

private struct TrayTooltipEntry {
    let text: String
    let above: Bool
    let bounds: Anchor<CGRect>
}

private struct TrayTooltipPreference: PreferenceKey {
    static var defaultValue: [TrayTooltipEntry] { [] }
    static func reduce(value: inout [TrayTooltipEntry], nextValue: () -> [TrayTooltipEntry]) {
        value.append(contentsOf: nextValue())
    }
}

// Position within the window, independently of the item's scroll viewport.
enum TrayTooltipPlacement {
    static func frame(button: CGRect, container: CGSize, size: CGSize, above: Bool) -> CGRect {
        let margin: CGFloat = 10
        let gap: CGFloat = 6
        let width = min(size.width, max(0, container.width - margin * 2))
        let height = min(size.height, max(0, container.height - margin * 2))
        let upperY = button.minY - gap - height
        let lowerY = button.maxY + gap
        let preferredY: CGFloat
        if above {
            preferredY = upperY >= margin ? upperY : lowerY
        } else {
            preferredY = lowerY + height <= container.height - margin ? lowerY : upperY
        }
        let x = min(max(margin, button.maxX - width), max(margin, container.width - margin - width))
        let y = min(max(margin, preferredY), max(margin, container.height - margin - height))
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

private struct TrayTooltipOverlay: View {
    let tip: TrayTooltipEntry
    let geometry: GeometryProxy

    var body: some View {
        let textSize = (tip.text as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium)
        ])
        let frame = TrayTooltipPlacement.frame(
            button: geometry[tip.bounds],
            container: geometry.size,
            size: CGSize(width: ceil(textSize.width) + 18, height: ceil(textSize.height) + 12),
            above: tip.above
        )
        Text(tip.text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .frame(width: frame.width, height: frame.height)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(.primary.opacity(0.12), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
            .position(x: frame.midX, y: frame.midY)
    }
}

private struct TrayTooltipModifier: ViewModifier {
    let text: String
    let above: Bool
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovered = $0 }
            .anchorPreference(key: TrayTooltipPreference.self, value: .bounds) { bounds in
                isHovered ? [TrayTooltipEntry(text: text, above: above, bounds: bounds)] : []
            }
            .accessibilityHint(text)
    }
}

private extension View {
    func trayTooltip(_ text: String, above: Bool = false) -> some View {
        modifier(TrayTooltipModifier(text: text, above: above))
    }
}

// MARK: - Selection Keyboard Shortcut

struct TransferTraySelectionShortcuts: NSViewRepresentable {
    let selectAll: () -> Void

    func makeNSView(context: Context) -> ShortcutView {
        ShortcutView(selectAll: selectAll)
    }

    func updateNSView(_ view: ShortcutView, context: Context) {
        view.selectAll = selectAll
    }

    static func dismantleNSView(_ view: ShortcutView, coordinator: ()) {
        view.stopMonitoring()
    }

    final class ShortcutView: NSView {
        var selectAll: () -> Void
        private var monitor: Any?

        init(selectAll: @escaping () -> Void) {
            self.selectAll = selectAll
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.handle(event, from: event.window) else { return event }
                return nil
            }
        }

        func handle(_ event: NSEvent, from eventWindow: NSWindow?) -> Bool {
            guard let window, window.isKeyWindow, eventWindow === window,
                  window.attachedSheet == nil,
                  event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
                  event.charactersIgnoringModifiers?.lowercased() == "a" else {
                return false
            }
            // Let native editors keep their own Select All behavior.
            if let editor = window.firstResponder as? NSTextView,
               editor.isEditable || editor.isSelectable {
                return false
            }
            selectAll()
            return true
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

// MARK: - Window Drag Blocker

private struct WindowDragBlocker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragBlockView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private class DragBlockView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
    }
}

// MARK: - File Drag Layer
// Uses NSFilePromiseProvider so Finder (and other apps) receive the real file, not a URL shortcut.

private struct TransferTrayDragItem {
    let id: String
    let url: URL
    let suggestedName: String
    let thumbnail: NSImage
}

private struct FileDragLayer: NSViewRepresentable {
    let defaultDragItems: [TransferTrayDragItem]
    let prepareDragItems: (NSEvent.ModifierFlags) -> [TransferTrayDragItem]

    func makeNSView(context: Context) -> _DragSourceView {
        _DragSourceView(defaultDragItems: defaultDragItems, prepareDragItems: prepareDragItems)
    }

    func updateNSView(_ nsView: _DragSourceView, context: Context) {
        nsView.defaultDragItems = defaultDragItems
        nsView.prepareDragItems = prepareDragItems
    }

    // MARK: Drag source view

    final class _DragSourceView: NSView {
        var defaultDragItems: [TransferTrayDragItem]
        var prepareDragItems: (NSEvent.ModifierFlags) -> [TransferTrayDragItem]
        // Retained for the lifetime of the drag session.
        private var activeDelegate: _PromiseDelegate?
        private var pendingDragItems: [TransferTrayDragItem]?

        init(
            defaultDragItems: [TransferTrayDragItem],
            prepareDragItems: @escaping (NSEvent.ModifierFlags) -> [TransferTrayDragItem]
        ) {
            self.defaultDragItems = defaultDragItems
            self.prepareDragItems = prepareDragItems
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }

        // Transparent to background-window dragging; clicks handled by SwiftUI above.
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        // Accept mouseDown without calling super so AppKit keeps this view as the
        // event owner, which is required for mouseDragged to fire on this view.
        // Remove controls live outside this drag layer's bounds.
        // Right-click (context menu) uses rightMouseDown — also unaffected.
        override func mouseDown(with event: NSEvent) {
            pendingDragItems = prepareDragItems(event.modifierFlags)
        }

        override func mouseDragged(with event: NSEvent) {
            let dragItems = nonEmptyDragItems()
            guard !dragItems.isEmpty else {
                return
            }

            let delegate = _PromiseDelegate()
            activeDelegate = delegate

            let draggingItems = dragItems.enumerated().map { index, dragItem in
                let provider = NSFilePromiseProvider(
                    fileType: fileTypeIdentifier(for: dragItem.url),
                    delegate: delegate
                )
                provider.userInfo = [
                    "url": dragItem.url,
                    "name": dragItem.suggestedName
                ]

                let draggingItem = NSDraggingItem(pasteboardWriter: provider)
                draggingItem.setDraggingFrame(
                    draggingFrame(for: event, index: index),
                    contents: dragPreviewImage(for: dragItem)
                )
                return draggingItem
            }

            pendingDragItems = nil
            beginDraggingSession(with: draggingItems, event: event, source: delegate)
        }

        override func mouseUp(with event: NSEvent) {
            pendingDragItems = nil
        }

        private func nonEmptyDragItems() -> [TransferTrayDragItem] {
            if let pendingDragItems, !pendingDragItems.isEmpty {
                return pendingDragItems
            }
            return defaultDragItems
        }

        private func fileTypeIdentifier(for url: URL) -> String {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            if isDir {
                return UTType.folder.identifier
            }
            return UTType(filenameExtension: url.pathExtension)?.identifier ?? UTType.data.identifier
        }

        private func draggingFrame(for event: NSEvent, index: Int) -> NSRect {
            let previewSize = NSSize(width: 58, height: 58)
            let point = convert(event.locationInWindow, from: nil)
            let visualOffset = CGFloat(min(index, 5)) * 4
            return NSRect(
                x: point.x - previewSize.width / 2 + visualOffset,
                y: point.y - previewSize.height / 2 - visualOffset,
                width: previewSize.width,
                height: previewSize.height
            )
        }

        private func dragPreviewImage(for item: TransferTrayDragItem) -> NSImage {
            let image = (item.thumbnail.copy() as? NSImage)
                ?? NSWorkspace.shared.icon(forFile: item.url.path(percentEncoded: false))
            image.size = NSSize(width: 58, height: 58)
            return image
        }
    }

    // MARK: Promise delegate + drag source

    final class _PromiseDelegate: NSObject, NSFilePromiseProviderDelegate, NSDraggingSource {
        func filePromiseProvider(
            _ filePromiseProvider: NSFilePromiseProvider,
            fileNameForType fileType: String
        ) -> String {
            promisePayload(from: filePromiseProvider)?.name ?? "Arquivo"
        }

        func filePromiseProvider(
            _ filePromiseProvider: NSFilePromiseProvider,
            writePromiseTo destURL: URL,
            completionHandler: @escaping (Error?) -> Void
        ) {
            guard let payload = promisePayload(from: filePromiseProvider) else {
                completionHandler(NSError(
                    domain: "FolderPeekTransferTray",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Arquivo da bandeja não encontrado para arraste."]
                ))
                return
            }

            let sourceURL = payload.url
            do {
                let finalDestinationURL = normalizedFilePathURL(from: destURL)
                let sourceAccess = sourceURL.startAccessingSecurityScopedResource()
                let destinationParent = finalDestinationURL.deletingLastPathComponent()
                let destinationAccess = destinationParent.startAccessingSecurityScopedResource()
                defer {
                    if sourceAccess {
                        sourceURL.stopAccessingSecurityScopedResource()
                    }
                    if destinationAccess {
                        destinationParent.stopAccessingSecurityScopedResource()
                    }
                }

                try FileTransferCoordinator().fulfillPromise(from: sourceURL, to: finalDestinationURL)

                completionHandler(nil)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: transferTrayItemExportedNotification,
                        object: sourceURL,
                        userInfo: ["destinationURL": finalDestinationURL]
                    )
                }
            } catch {
                completionHandler(error)
                let message = error.localizedDescription
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: transferTrayItemExportedNotification,
                        object: sourceURL,
                        userInfo: ["error": message]
                    )
                }
            }
        }

        private func promisePayload(from provider: NSFilePromiseProvider) -> (url: URL, name: String)? {
            guard let payload = provider.userInfo as? [String: Any],
                  let url = payload["url"] as? URL else {
                return nil
            }

            let name = payload["name"] as? String
            return (url, (name?.isEmpty == false ? name : nil) ?? url.lastPathComponent)
        }

        private func normalizedFilePathURL(from url: URL) -> URL {
            guard url.isFileURL else { return url }
            if let filePathURL = (url as NSURL).filePathURL {
                return filePathURL.standardizedFileURL
            }
            return url.standardizedFileURL
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            // File promises materialize a file at the receiver's destination.
            // Link/move are not implemented by this source; reject drops into itself.
            context == .outsideApplication ? .copy : []
        }
    }
}

// MARK: - Window Accessor

private struct TransferTrayWindowAccessor: NSViewRepresentable {
    let onResolveWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            onResolveWindow(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            onResolveWindow(window)
        }
    }
}

/// Samples the desktop behind the tray, rather than its SwiftUI contents.
private struct TrayFrostedBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = TrayBackgroundEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        configure(view)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = .popover
        view.blendingMode = .behindWindow
        // Finder stays active during a drag; the tray must keep its full blur.
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 20
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}

private final class TrayBackgroundEffectView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
