import Foundation

/// Определяет известный сервис видеосвязи по hostname URL встречи.
///
/// Логика намеренно устроена как таблица правил, а не цепочка if/else —
/// чтобы поддержку нового сервиса можно было добавить, дописав одну строку
/// в `rules`, без изменения остального кода.
struct MeetingProviderDetector {

    /// Одно правило сопоставления: если hostname совпадает с одним из
    /// суффиксов (сам домен или его поддомен) — это данный сервис.
    private struct Rule {
        let hostSuffixes: [String]
        let service: MeetingService
    }

    private static let rules: [Rule] = [
        Rule(hostSuffixes: ["telemost.yandex.ru"], service: .yandexTelemost),
        Rule(hostSuffixes: ["meet.google.com"], service: .googleMeet),
        Rule(hostSuffixes: ["zoom.us"], service: .zoom),
        Rule(hostSuffixes: ["teams.microsoft.com", "teams.live.com"], service: .microsoftTeams),
    ]

    /// Определяет сервис по URL. Неизвестный URL не считается ошибкой —
    /// возвращается `.unknown(hostname:)`, встреча при этом сохраняется
    /// и открывается как обычно.
    static func detectService(from url: URL) -> MeetingService {
        guard let host = url.host?.lowercased() else {
            return .unknown(hostname: nil)
        }

        for rule in rules {
            for suffix in rule.hostSuffixes {
                if host == suffix || host.hasSuffix("." + suffix) {
                    return rule.service
                }
            }
        }

        return .unknown(hostname: host)
    }
}
