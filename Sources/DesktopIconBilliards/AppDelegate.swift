import AppKit
import BilliardsCore
import Carbon.HIToolbox

/// Borderless panel that can take key events without activating the app, so the
/// game lives on the desktop instead of stealing focus from the current window.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private var hotKeyRef: EventHotKeyRef?

private func hotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?,
                           _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    DispatchQueue.main.async { NSApp.terminate(nil) }
    return noErr
}

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: OverlayPanel?
    private var view: GameView?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let demo = CommandLine.arguments.contains("--demo")
        let items = DesktopItems.load(demo: demo)
        guard !items.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "桌面上没有图标"
            alert.informativeText = "把文件或文件夹放到桌面后再启动;或在终端加 --demo 参数,用示例图标体验。"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        guard let screen = NSScreen.main else { NSApp.terminate(nil); return }
        let frame = screen.frame, visible = screen.visibleFrame
        let work = TableRect(Double(visible.minX - frame.minX), Double(frame.maxY - visible.maxY),
                             Double(visible.maxX - frame.minX), Double(frame.maxY - visible.minY))
        let table = BilliardsMotion(workArea: work, sizes: items.map(\.size))
        let view = GameView(items: items, table: table, screen: screen)
        view.onQuit = { NSApp.terminate(nil) }

        let panel = OverlayPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        // One step above the Finder icon layer: hides the real icons while playing,
        // stays below every normal window, and restores the desktop on close.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.contentView = view
        panel.orderFrontRegardless()
        panel.makeKey()
        view.start()
        self.panel = panel
        self.view = view

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x44494231), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_X), UInt32(controlKey | optionKey), id,
                            GetApplicationEventTarget(), 0, &hotKeyRef)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil,
            queue: .main) { _ in NSApp.terminate(nil) }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        view?.stop()
        panel?.orderOut(nil)
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
    }
}