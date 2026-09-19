import AppKit
import SwiftUI

/// Управляет отдельным плавающим окном (NSPanel) для countdown-панели
/// Auto Join.
///
/// `isOpaque = false` + `backgroundColor = .clear` включают настоящую
/// AppKit-vibrancy: SwiftUI `.regularMaterial` внутри контента сможет
/// показать то, что находится позади окна (как у Spotlight/системных
/// уведомлений), а не просто нарисовать полупрозрачный цвет поверх
/// непрозрачного окна.
@MainActor
final class AutoJoinPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var onCancelHandler: (() -> Void)?

    func show(
        occurrence: MeetingOccurrence,
        countdown: TimeInterval,
        connectOptions: [MeetingLauncher.ConnectOption],
        onJoinNow: @escaping (URL) -> Void,
        onCancel: @escaping () -> Void
    ) {
        onCancelHandler = onCancel

        let contentView = AutoJoinCountdownView(
            occurrence: occurrence,
            countdown: countdown,
            connectOptions: connectOptions,
            onJoinNow: onJoinNow,
            onCancel: onCancel
        )
        let hosting = NSHostingView(rootView: contentView)

        if let panel {
            panel.contentView = hosting
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.titleVisibility = .hidden
        newPanel.titlebarAppearsTransparent = true
        newPanel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        newPanel.standardWindowButton(.zoomButton)?.isHidden = true
        newPanel.isReleasedWhenClosed = false
        newPanel.hidesOnDeactivate = false
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.delegate = self
        newPanel.contentView = hosting
        newPanel.center()
        newPanel.makeKeyAndOrderFront(nil)

        panel = newPanel
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onCancelHandler?()
        return false
    }
}
