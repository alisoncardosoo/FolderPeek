import AppKit
import SwiftUI
import UniformTypeIdentifiers
import FolderPeekCore

fileprivate let transferTrayItemExportedNotification = Notification.Name("FolderPeekTransferTrayItemExported")

struct TransferTrayWindowView: View {
    @ObservedObject var store: TransferTrayStore
    let hideWindow: () -> Void
    let configureWindow: (NSWindow) -> Void

    @State private var isDropTarget = false
    @State private var selectedItemIDs: Set<String> = []
    @State private var selectionAnchorID: String?

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 10)

            if store.isProcessing {
                progressView
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            gridContent
                .padding(.horizontal, 14)

            if let msg = store.statusMessage {
                statusBar(msg)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                Spacer(minLength: 8)
            }
        }
        .frame(minWidth: 220, minHeight: 200)
        .background(shelfBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(borderOverlay)
        .shadow(color: .black.opacity(0.16), radius: 20, y: 10)
        .overlay(dropTargetHighlight)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTarget, perform: handleDrop(providers:))
        .alert("Mover arquivos?", isPresented: $store.showMoveConfirmation) {
            Button("Cancelar", role: .cancel) { store.cancelMoveTransfer() }
            Button("Mover", role: .destructive) { store.confirmMoveTransfer() }
        } message: {
            Text("Esta ação remove os arquivos da origem. Use Desfazer no menu para reverter.")
        }
        .background(
            TransferTrayWindowAccessor(onResolveWindow: configureWindow).frame(width: 0, height: 0)
        )
        .ignoresSafeArea()
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: store.isProcessing)
        .animation(.easeInOut(duration: 0.18), value: store.statusMessage != nil)
        .onReceive(NotificationCenter.default.publisher(for: transferTrayItemExportedNotification)) { notification in
            guard let sourceURL = notification.object as? URL else { return }
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
    }

    // MARK: - Background

    private var shelfBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.ultraThinMaterial)
            .opacity(0.72)
    }

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
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
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.trayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                Text(
                    store.items.isEmpty
                        ? "Arraste arquivos para cá"
                        : "\(store.items.count) item(ns)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
            headerActions
        }
    }

    private var headerActions: some View {
        HStack(spacing: 6) {
            if !store.items.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        store.clearItems()
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Devolver tudo para a origem")
            }

            Menu {
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
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button(action: hideWindow) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Fechar bandeja")
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

    // MARK: - Grid

    private var gridContent: some View {
        Group {
            if store.items.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 88, maximum: 118), spacing: 10)],
                        alignment: .leading,
                        spacing: 12
                    ) {
                        ForEach(store.items) { item in
                            TransferTrayTile(
                                item: item,
                                thumbnail: store.thumbnail(for: item),
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
                            .transition(
                                .asymmetric(
                                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                                    removal: .scale(scale: 0.7).combined(with: .opacity)
                                )
                            )
                        }
                    }
                    .animation(.spring(response: 0.32, dampingFraction: 0.78), value: store.items.map(\.id))
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
                // Prevents isMovableByWindowBackground from intercepting item drags
                .background(WindowDragBlocker())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Selection

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
        extractURLs(from: providers) { urls in
            guard !urls.isEmpty else { return }
            Task { @MainActor in
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
    let isSelected: Bool
    let selectedCount: Int
    let selectItem: (NSEvent.ModifierFlags) -> Void
    let prepareDragItems: (NSEvent.ModifierFlags) -> [TransferTrayDragItem]
    let removeItem: () -> Void
    let removeSelectedItems: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    // FileDragLayer covers only the 58×58 image; the X button sits at
                    // offset(x:6,y:-6) which places it outside this area — no event conflict.
                    .overlay(
                        FileDragLayer(
                            defaultDragItems: [
                                TransferTrayDragItem(
                                    id: item.id,
                                    url: item.url,
                                    suggestedName: item.name,
                                    thumbnail: thumbnail
                                )
                            ],
                            prepareDragItems: prepareDragItems
                        )
                    )

                if isHovered {
                    Button(action: removeItem) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .gray)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
                } else if isSelected {
                    selectionBadge
                } else {
                    statusBadge
                }
            }

            Text(item.name)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
                .foregroundStyle(item.status == .ready ? .primary : .secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
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

    private var selectionBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
    }

    private var selectionBorder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(isSelected ? Color.accentColor.opacity(0.58) : Color.clear, lineWidth: 1.2)
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
        // The X button lives outside the 58×58 image bounds so it is unaffected.
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
                let normalizedDestination = normalizedFilePathURL(from: destURL)
                let destinationIsDirectory = (try? normalizedDestination.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                let baseDestinationURL = destinationIsDirectory
                    ? normalizedDestination.appendingPathComponent(payload.name)
                    : normalizedDestination
                let finalDestinationURL = availableDestinationURL(from: baseDestinationURL)

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

                do {
                    try FileManager.default.moveItem(at: sourceURL, to: finalDestinationURL)
                } catch {
                    try FileManager.default.copyItem(at: sourceURL, to: finalDestinationURL)
                    do {
                        if FileManager.default.fileExists(atPath: sourceURL.path(percentEncoded: false)) {
                            try FileManager.default.removeItem(at: sourceURL)
                        }
                    } catch {
                        try? FileManager.default.removeItem(at: finalDestinationURL)
                        throw error
                    }
                }

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

        private func availableDestinationURL(from baseURL: URL) -> URL {
            let manager = FileManager.default
            guard manager.fileExists(atPath: baseURL.path) else {
                return baseURL
            }

            let fileExtension = baseURL.pathExtension
            let baseName = baseURL.deletingPathExtension().lastPathComponent
            let parentURL = baseURL.deletingLastPathComponent()

            for attempt in 1...999 {
                let candidateName = "\(baseName) \(attempt)"
                let candidateURL: URL
                if fileExtension.isEmpty {
                    candidateURL = parentURL.appendingPathComponent(candidateName)
                } else {
                    candidateURL = parentURL
                        .appendingPathComponent(candidateName)
                        .appendingPathExtension(fileExtension)
                }

                if !manager.fileExists(atPath: candidateURL.path) {
                    return candidateURL
                }
            }

            return baseURL
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            context == .outsideApplication ? [.copy, .move, .link] : [.copy, .move, .link]
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
