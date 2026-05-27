import AppKit
import Foundation

final class GlobalHotKeyMonitor {
    private let onHotKey: () -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(onHotKey: @escaping () -> Void) {
        self.onHotKey = onHotKey
    }

    func start() {
        stop()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event: event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event: event)
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    deinit {
        stop()
    }

    private func handle(event: NSEvent) {
        guard matchesHotKey(event: event) else {
            return
        }

        onHotKey()
    }

    private func matchesHotKey(event: NSEvent) -> Bool {
        guard !event.isARepeat else { return false }

        let storedCode = UserDefaults.standard.integer(forKey: "shelfHotkeyCode")
        let keyCode: UInt16 = storedCode > 0 ? UInt16(storedCode) : 49

        let storedMod = UserDefaults.standard.integer(forKey: "shelfHotkeyModifiers")
        let requiredModifiers: NSEvent.ModifierFlags = storedMod != 0
            ? NSEvent.ModifierFlags(rawValue: UInt(storedMod))
            : [.control, .option]

        let activeModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard activeModifiers == requiredModifiers else { return false }

        return event.keyCode == keyCode
    }
}
