import AppKit
import SwiftUI
import UniformTypeIdentifiers
import FolderPeekCore

struct TransferTrayWindowView: View {
    @ObservedObject var store: TransferTrayStore
    let hideWindow: () -> Void
    let configureWindow: (NSWindow) -> Void

    @State private var isDropTarget = false
    @State private var showingHistory = false

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
        .frame(minWidth: 300, minHeight: 220)
        .background(shelfBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(borderOverlay)
        .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
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
        .sheet(isPresented: $showingHistory) {
            TransferHistoryView(store: store)
        }
    }

    // MARK: - Background

    private var shelfBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.ultraThinMaterial)
    }

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
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
                .help("Limpar bandeja")

                Menu {
                    Picker("Operação", selection: $store.operation) {
                        Label("Copiar", systemImage: "doc.on.doc").tag(TransferOperation.copy)
                        Label("Mover", systemImage: "arrow.right.doc.on.clipboard").tag(TransferOperation.move)
                    }
                    .pickerStyle(.inline)

                    Divider()

                    Button("Desfazer último move") { store.undoLastMove() }
                    Button("Ver histórico…") { showingHistory = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Button(action: store.chooseDestination) {
                Label(
                    store.destinationURL == nil ? "Destino" : store.destinationURL!.lastPathComponent,
                    systemImage: "folder"
                )
                .lineLimit(1)
                .frame(maxWidth: 100)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(store.isProcessing)

            if store.canExecuteTransfer {
                Button(action: store.requestExecuteTransfer) {
                    Image(systemName: store.operation == .copy
                          ? "doc.on.doc.fill"
                          : "arrow.right.doc.on.clipboard.fill")
                    .font(.system(size: 12))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(store.operation == .move ? .orange : .accentColor)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: store.canExecuteTransfer)
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
                                removeItem: {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                        store.removeItem(item)
                                    }
                                }
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
    let removeItem: () -> Void

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
                    .overlay(FileDragLayer(url: item.url, suggestedName: item.name))

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
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .contextMenu {
            Button("Remover da bandeja", role: .destructive) { removeItem() }
        }
        .help(item.url.path(percentEncoded: false))
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

// MARK: - History Sheet

private struct TransferHistoryView: View {
    @ObservedObject var store: TransferTrayStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Histórico de transferências")
                    .font(.headline)
                Spacer()
                if !store.transferHistory.isEmpty {
                    Button("Limpar") { store.clearHistory() }
                        .foregroundStyle(.red)
                        .buttonStyle(.plain)
                        .font(.subheadline)
                }
                Button("Fechar") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            if store.transferHistory.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("Nenhuma transferência registrada")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(store.transferHistory) { record in
                    HistoryRecordRow(record: record)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 400, height: 480)
    }
}

private struct HistoryRecordRow: View {
    let record: TransferTrayStore.TransferRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: record.operation == .copy
                      ? "doc.on.doc"
                      : "arrow.right.doc.on.clipboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(record.destinationName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text(record.date, format: .dateTime.day().month(.abbreviated).hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text("\(record.succeededCount) arquivo(s)"
                 + (record.failedCount > 0 ? " · \(record.failedCount) falha(s)" : ""))
                .font(.caption)
                .foregroundStyle(.secondary)

            if !record.fileNames.isEmpty {
                let preview = record.fileNames.prefix(3).joined(separator: " · ")
                    + (record.fileNames.count > 3 ? " · +\(record.fileNames.count - 3)" : "")
                Text(preview)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - File Drag Layer
// Uses NSFilePromiseProvider so Finder (and other apps) receive the real file, not a URL shortcut.

private struct FileDragLayer: NSViewRepresentable {
    let url: URL
    let suggestedName: String

    func makeNSView(context: Context) -> _DragSourceView {
        _DragSourceView(url: url, suggestedName: suggestedName)
    }

    func updateNSView(_ nsView: _DragSourceView, context: Context) {
        nsView.url = url
        nsView.suggestedName = suggestedName
    }

    // MARK: Drag source view

    final class _DragSourceView: NSView {
        var url: URL
        var suggestedName: String
        // Retained for the lifetime of the drag session.
        private var activeDelegate: _PromiseDelegate?

        init(url: URL, suggestedName: String) {
            self.url = url
            self.suggestedName = suggestedName
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }

        // Transparent to background-window dragging; clicks handled by SwiftUI above.
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }

        // Accept mouseDown without calling super so AppKit keeps this view as the
        // event owner, which is required for mouseDragged to fire on this view.
        // The X button lives outside the 58×58 image bounds so it is unaffected.
        // Right-click (context menu) uses rightMouseDown — also unaffected.
        override func mouseDown(with event: NSEvent) {
            // intentionally accepts event without forwarding
        }

        override func mouseDragged(with event: NSEvent) {
            let delegate = _PromiseDelegate(url: url)
            activeDelegate = delegate

            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            let fileType = isDir
                ? UTType.folder.identifier
                : (UTType(filenameExtension: url.pathExtension)?.identifier ?? UTType.data.identifier)

            let provider = NSFilePromiseProvider(fileType: fileType, delegate: delegate)
            provider.userInfo = ["name": suggestedName]

            let item = NSDraggingItem(pasteboardWriter: provider)
            item.setDraggingFrame(bounds, contents: nil)
            beginDraggingSession(with: [item], event: event, source: delegate)
        }
    }

    // MARK: Promise delegate + drag source

    final class _PromiseDelegate: NSObject, NSFilePromiseProviderDelegate, NSDraggingSource {
        let url: URL
        init(url: URL) { self.url = url }

        func filePromiseProvider(
            _ filePromiseProvider: NSFilePromiseProvider,
            fileNameForType fileType: String
        ) -> String {
            url.lastPathComponent
        }

        func filePromiseProvider(
            _ filePromiseProvider: NSFilePromiseProvider,
            writePromiseTo destURL: URL,
            completionHandler: @escaping (Error?) -> Void
        ) {
            do {
                try FileManager.default.copyItem(at: url, to: destURL)
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            context == .outsideApplication ? [.copy, .link] : [.copy, .move, .link]
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
