import AppKit

/// Обрабатывает события уровня приложения, которые SwiftUI `App` напрямую
/// не предоставляет.
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Заполняется приложением при старте (см. `KnockKnockBroApp.init`) —
    /// говорит, нужно ли автоматически открывать главное окно при запуске.
    var shouldOpenMainWindowOnLaunch: (() -> Bool)?

    /// KnockKnockBro обязан продолжать работать в фоне (Menu Bar, расписание,
    /// уведомления) даже после закрытия главного окна пользователем.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Закрывает только окно с identifier "main" (наш `WindowGroup(id: "main")`),
    /// а не все окна подряд через `NSApp.windows.forEach` — обход ВСЕХ окон
    /// в этот момент жизненного цикла, судя по всему, мешает AppKit
    /// корректно завершить инициализацию `MenuBarExtra`, из-за чего его
    /// статус-бар-айтем переставал реагировать на клики. Небольшая
    /// отсрочка (`asyncAfter`) дополнительно даёт системе время закончить
    /// построение сцен до того, как мы начинаем трогать окна.
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard shouldOpenMainWindowOnLaunch?() == false else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.windows
                .first { $0.identifier?.rawValue == "main" }?
                .close()
        }
    }
}
