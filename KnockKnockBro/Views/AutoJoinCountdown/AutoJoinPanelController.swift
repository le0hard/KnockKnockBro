import AppKit
import SwiftUI

/// Управляет отдельным плавающим окном (NSPanel) для countdown-панели
/// Auto Join.
///
/// Независима от главного окна SwiftUI-сцены (`WindowGroup`) — панель
/// видна, даже если оно закрыто. Это прямое следствие требования "никогда
/// не открывать встречу без предупреждения" независимо от состояния
/// остального интерфейса; `.sheet`, привязанный к окну, для этого не
/// подходил бы.
///
/// Стиль `.nonactivatingPanel` позволяет панели стать key window и
/// показаться поверх остальных окон, не переключая фокус всего
/// приложения — это менее навязчиво, чем полная активация KnockKnockBro.
@MainActor
final class AutoJoinPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var onCancelHandler: (() -> Void)?

    func show(
        occurrence: MeetingOccurrence,
        countdown: TimeInterval,
        onJoinNow: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        onCancelHandler = onCancel

        let contentView = AutoJoinCountdownView(
            occurrence: occurrence,
            countdown: countdown,
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
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 220),
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
        newPanel.delegate = self
        newPanel.contentView = hosting
        newPanel.center()
        newPanel.makeKeyAndOrderFront(nil)

        panel = newPanel
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Закрытие панели системным крестиком трактуется как "Отмена" — это
    /// то же самое действие, что и явная кнопка "Отмена", а не отдельное
    /// недокументированное поведение.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onCancelHandler?()
        return false // сами скрываем через hide(), не разрушаем панель насовсем
    }
}
