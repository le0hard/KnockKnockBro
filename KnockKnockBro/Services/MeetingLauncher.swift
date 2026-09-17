import Foundation
import AppKit

/// Открывает URL встречи средствами macOS.
///
/// Вынесен в отдельный компонент намеренно: `Meeting` ничего не знает о
/// механизме запуска, а этот единственный сервис будет использоваться и
/// UI-кнопкой "Подключиться", и action'ом уведомления, и Auto Join —
/// так что если в будущем понадобится что-то (логирование запусков,
/// подтверждение для нестандартных схем) — меняется в одном месте.
struct MeetingLauncher {

    /// Открывает URL встречи в браузере/приложении по умолчанию для этой
    /// ссылки — ровно так, как это сделал бы сам пользователь, кликнув по
    /// ссылке где угодно в системе.
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// Копирует ссылку встречи в системный буфер обмена.
    static func copyURL(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
    }
}
