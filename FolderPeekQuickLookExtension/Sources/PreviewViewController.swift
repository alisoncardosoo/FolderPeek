import AppKit
import FolderPeekCore
import QuickLookUI
import Quartz

@objc(PreviewViewController)
final class PreviewViewController: NSViewController, @preconcurrency QLPreviewingController {

    // MARK: - UI

    private let headerIconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let warningLabel = NSTextField(labelWithString: "")
    private let breadcrumbLabel = NSTextField(labelWithString: "")
    private let tableView = NSTableView()

    // MARK: - State

    private var items: [PreviewItem] = []
    private var preferences = PreviewPreferences.default

    private let columnDefs: [(id: String, title: String, weight: CGFloat)] = [
        ("name",     "Nome",                260),
        ("modified", "Data de Modificação", 160),
        ("size",     "Tamanho",              80),
        ("kind",     "Tipo",               130),
    ]

    // MARK: - QLPreviewingController

    override var preferredContentSize: NSSize {
        get { NSSize(width: 860, height: 540) }
        set { }
    }

    override func loadView() {
        let effectView = NSVisualEffectView()
        effectView.material = .underWindowBackground
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        view = effectView
        buildLayout()
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        preferences = loadPreferences()
        applyAppearance(preferences.appearanceMode)
        do {
            let result = try PreviewScanner().scan(url: url, preferences: preferences)
            render(result: result)
        } catch {
            renderError(error, title: url.lastPathComponent)
        }
        handler(nil)
    }

    // MARK: - Layout

    private func buildLayout() {
        // Header — transparent, no background view
        headerIconView.imageScaling = .scaleProportionallyDown
        headerIconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        warningLabel.font = .systemFont(ofSize: 11)
        warningLabel.textColor = .systemOrange
        warningLabel.lineBreakMode = .byTruncatingTail
        warningLabel.maximumNumberOfLines = 1
        warningLabel.isHidden = true
        warningLabel.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView(views: [titleLabel, subtitleLabel, warningLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.translatesAutoresizingMaskIntoConstraints = false

        // Table — solid background with rounded corners, floats over transparent areas
        let tableContainer = RoundedContainerView()
        tableContainer.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .controlBackgroundColor

        tableView.backgroundColor = .controlBackgroundColor
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 28
        tableView.headerView = NSTableHeaderView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.allowsColumnResizing = true
        tableView.allowsColumnReordering = false
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.style = .inset
        tableView.gridStyleMask = []

        for def in columnDefs {
            let col = NSTableColumn(identifier: .init(def.id))
            col.title = def.title
            col.width = def.weight
            col.minWidth = 60
            tableView.addTableColumn(col)
        }
        scrollView.documentView = tableView
        tableContainer.addSubview(scrollView)

        // Footer — transparent, no separator
        breadcrumbLabel.font = .systemFont(ofSize: 11)
        breadcrumbLabel.textColor = .secondaryLabelColor
        breadcrumbLabel.lineBreakMode = .byTruncatingHead
        breadcrumbLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(headerIconView)
        view.addSubview(textStack)
        view.addSubview(tableContainer)
        view.addSubview(breadcrumbLabel)

        NSLayoutConstraint.activate([
            headerIconView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            headerIconView.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            headerIconView.widthAnchor.constraint(equalToConstant: 48),
            headerIconView.heightAnchor.constraint(equalToConstant: 48),

            textStack.leadingAnchor.constraint(equalTo: headerIconView.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            textStack.centerYAnchor.constraint(equalTo: headerIconView.centerYAnchor),

            tableContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            tableContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            tableContainer.topAnchor.constraint(equalTo: headerIconView.bottomAnchor, constant: 12),
            tableContainer.bottomAnchor.constraint(equalTo: breadcrumbLabel.topAnchor, constant: -8),

            scrollView.leadingAnchor.constraint(equalTo: tableContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: tableContainer.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: tableContainer.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: tableContainer.bottomAnchor),

            breadcrumbLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            breadcrumbLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            breadcrumbLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
        ])
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        redistributeColumns()
    }

    private func redistributeColumns() {
        guard let scrollView = tableView.enclosingScrollView else { return }
        let available = scrollView.contentSize.width
        guard available > 0 else { return }
        let totalWeight = columnDefs.reduce(0) { $0 + $1.weight }
        for def in columnDefs {
            guard let col = tableView.tableColumn(withIdentifier: .init(def.id)) else { continue }
            col.width = max(col.minWidth, floor(available * def.weight / totalWeight))
        }
    }

    // MARK: - Render

    private func render(result: PreviewResult) {
        if let url = result.sourceURL {
            headerIconView.image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            headerIconView.image = NSImage(systemSymbolName: "archivebox", accessibilityDescription: nil)
        }
        titleLabel.stringValue = result.title
        subtitleLabel.stringValue = result.subtitle
        warningLabel.stringValue = result.warnings.joined(separator: " ")
        warningLabel.isHidden = result.warnings.isEmpty
        items = result.items
        tableView.reloadData()
        breadcrumbLabel.stringValue = breadcrumb(for: result.sourceURL)
    }

    private func renderError(_ error: Error, title: String) {
        headerIconView.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
        titleLabel.stringValue = title
        subtitleLabel.stringValue = "Nao foi possivel gerar a previa"
        warningLabel.stringValue = error.localizedDescription
        warningLabel.isHidden = false
        items = []
        tableView.reloadData()
        breadcrumbLabel.stringValue = ""
    }

    private func breadcrumb(for url: URL?) -> String {
        guard let url else { return "" }
        let home = FileManager.default.homeDirectoryForCurrentUser
        var components = url.pathComponents
        let homeComponents = home.pathComponents
        if components.starts(with: homeComponents) {
            let username = homeComponents.last ?? "~"
            components = [username] + Array(components.dropFirst(homeComponents.count))
        } else {
            components = Array(components.dropFirst())
        }
        return components.joined(separator: "  ›  ")
    }

    // MARK: - Preferences & Appearance

    private func loadPreferences() -> PreviewPreferences {
        let d = UserDefaults.standard
        return PreviewPreferences(
            fontSize: d.object(forKey: "fontSize") as? Double ?? PreviewPreferences.default.fontSize,
            appearanceMode: PreviewAppearanceMode(
                storedValue: d.string(forKey: "appearanceMode") ?? PreviewPreferences.default.appearanceMode.rawValue
            ),
            showHiddenFiles: d.object(forKey: "showHiddenFiles") as? Bool ?? PreviewPreferences.default.showHiddenFiles,
            foldersFirst: d.object(forKey: "foldersFirst") as? Bool ?? PreviewPreferences.default.foldersFirst,
            itemLimit: d.object(forKey: "itemLimit") as? Int ?? PreviewPreferences.default.itemLimit
        )
    }

    private func applyAppearance(_ mode: PreviewAppearanceMode) {
        let name: NSAppearance.Name?
        switch mode {
        case .system: name = nil
        case .light:  name = .aqua
        case .dark:   name = .darkAqua
        }
        view.appearance = name.flatMap(NSAppearance.init(named:))
    }
}

// MARK: - Rounded Container

private final class RoundedContainerView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Table Data Source & Delegate

extension PreviewViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < items.count, let id = tableColumn?.identifier.rawValue else { return nil }
        let item = items[row]
        switch id {
        case "name":     return nameCell(for: item)
        case "modified": return textCell(FolderPeekFormatters.dateString(item.modifiedAt), secondary: true)
        case "size":     return textCell(FolderPeekFormatters.sizeString(item.byteSize), secondary: true)
        case "kind":     return textCell(item.kind, secondary: false)
        default:         return nil
        }
    }

    private func nameCell(for item: PreviewItem) -> NSView {
        let cell = NSTableCellView()

        let indentBase: CGFloat = 8
        let depthIndent = CGFloat(item.depth) * 20
        var nextLeading = indentBase + depthIndent

        if item.isDirectory {
            let chevron = NSImageView()
            chevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
            chevron.contentTintColor = .tertiaryLabelColor
            chevron.imageScaling = .scaleProportionallyDown
            chevron.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(chevron)
            NSLayoutConstraint.activate([
                chevron.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: nextLeading),
                chevron.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                chevron.widthAnchor.constraint(equalToConstant: 9),
                chevron.heightAnchor.constraint(equalToConstant: 9),
            ])
            nextLeading += 13
        }

        let iconView = NSImageView()
        iconView.image = fileIcon(for: item)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: item.name)
        label.font = .systemFont(ofSize: preferences.fontSize)
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(iconView)
        cell.addSubview(label)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: nextLeading),
            iconView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func textCell(_ text: String, secondary: Bool) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: preferences.fontSize)
        label.lineBreakMode = .byTruncatingMiddle
        label.textColor = secondary ? .secondaryLabelColor : .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        let container = NSTableCellView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    private func fileIcon(for item: PreviewItem) -> NSImage {
        switch item.source {
        case .fileSystem(let url):
            return NSWorkspace.shared.icon(forFile: url.path)
        case .archiveEntry:
            if item.isDirectory {
                return NSWorkspace.shared.icon(for: .folder)
            }
            return NSWorkspace.shared.icon(forFileType: URL(fileURLWithPath: item.name).pathExtension)
        }
    }
}
