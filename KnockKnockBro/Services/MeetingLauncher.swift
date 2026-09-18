import Foundation
import AppKit

/// Открывает URL встречи средствами macOS.
///
/// Вынесен в отдельный компонент намеренно: `Meeting` ничего не знает о
/// механизме запуска, а этот единственный сервис используется и
/// UI-кнопкой "Подключиться", и action'ом уведомления, и Auto Join.
struct MeetingLauncher {

    /// Одна кнопка подключения: подпись + URL, который она открывает.
    /// Для большинства сервисов таких кнопок ровно одна ("Подключиться" →
    /// исходный URL); для Яндекс Телемоста, в зависимости от настройки
    /// пользователя и наличия установленного приложения, их может быть
    /// одна или две.
    struct ConnectOption: Identifiable, Equatable {
        let id: String
        let title: String
        let url: URL

        init(title: String, url: URL) {
            self.id = title
            self.title = title
            self.url = url
        }
    }

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

    // MARK: - Яндекс Телемост: deep link в нативное приложение

    /// Строит deep link для открытия встречи сразу в нативном приложении
    /// Яндекс Телемоста, минуя браузер — эмпирически подтверждённый формат:
    /// `telemost://` + исходный `https://...`-URL с удалённым двоеточием
    /// сразу после `https`. Публичной документации на этот формат нет —
    /// он найден опытным путём, поэтому при изменениях на стороне
    /// Яндекса может перестать работать.
    static func telemostDeepLink(from url: URL) -> URL? {
        let absolute = url.absoluteString
        let prefix = "https:"
        guard absolute.hasPrefix(prefix) else { return nil }

        let withoutColon = "https" + absolute.dropFirst(prefix.count)
        return URL(string: "telemost://" + withoutColon)
    }

    /// `true`, если в системе зарегистрирован обработчик схемы `telemost://`
    /// — то есть приложение Яндекс Телемоста установлено. Используется
    /// как проверка перед тем, как предлагать пользователю deep link
    /// вместо обычной веб-ссылки.
    static func telemostAppIsInstalled() -> Bool {
        guard let probeURL = URL(string: "telemost://") else { return false }
        return NSWorkspace.shared.urlForApplication(toOpen: probeURL) != nil
    }

    /// Возвращает кнопки подключения для встречи с учётом настройки
    /// пользователя (`telemostMode`) — применимо только к встречам
    /// Яндекс Телемоста, для остальных сервисов всегда одна кнопка
    /// "Подключиться" на исходный URL.
    ///
    /// Если desktop-приложение недоступно (не установлено), режимы
    /// `.both` и `.desktopOnly` автоматически схлопываются до одной
    /// веб-кнопки — показывать две кнопки, обе ведущие в браузер, было бы
    /// избыточно и вводило бы в заблуждение.
    ///
    /// - Parameter appAvailabilityCheck: проверка наличия приложения,
    ///   вынесена параметром (а не вызывается напрямую) для тестируемости
    ///   — тесты подставляют детерминированное `{ true }`/`{ false }`,
    ///   не завися от реального состояния машины, на которой они гоняются.
    static func connectOptions(
        for meeting: Meeting,
        telemostMode: TelemostConnectionMode,
        appAvailabilityCheck: () -> Bool = telemostAppIsInstalled
    ) -> [ConnectOption] {
        guard meeting.service == .yandexTelemost else {
            return [ConnectOption(title: "Подключиться", url: meeting.url)]
        }

        switch telemostMode {
        case .webOnly:
            return [ConnectOption(title: "Подключиться", url: meeting.url)]

        case .desktopOnly:
            if let deepLink = telemostDeepLink(from: meeting.url), appAvailabilityCheck() {
                return [ConnectOption(title: "Подключиться", url: deepLink)]
            }
            return [ConnectOption(title: "Подключиться", url: meeting.url)]

        case .both:
            if let deepLink = telemostDeepLink(from: meeting.url), appAvailabilityCheck() {
                return [
                    ConnectOption(title: "Подключиться", url: deepLink),
                    ConnectOption(title: "Подключиться web", url: meeting.url),
                ]
            }
            return [ConnectOption(title: "Подключиться", url: meeting.url)]
        }
    }
}
