import Foundation

/// Известный поставщик услуг видеосвязи, определяемый по hostname ссылки.
/// Используется только для отображения в UI (иконка, подпись) — сама встреча
/// хранит оригинальный URL целиком и работает независимо от того, распознан
/// сервис или нет.
enum MeetingService: Equatable, Hashable {
    case yandexTelemost
    case googleMeet
    case zoom
    case microsoftTeams
    case unknown(hostname: String?)

    /// Название для отображения в UI.
    var displayName: String {
        switch self {
        case .yandexTelemost: return "Яндекс Телемост"
        case .googleMeet: return "Google Meet"
        case .zoom: return "Zoom"
        case .microsoftTeams: return "Microsoft Teams"
        case .unknown(let hostname):
            return hostname ?? "Неизвестный сервис"
        }
    }

    /// Системная SF Symbol-иконка как fallback для отображения рядом с
    /// названием. Более точное визуальное решение (цветные значки в
    /// фирменных цветах сервисов) реализовано во View-слое, в
    /// `ServiceIconView`.
    var systemImageName: String {
        switch self {
        case .yandexTelemost, .googleMeet, .zoom, .microsoftTeams:
            return "video.fill"
        case .unknown:
            return "questionmark.video.fill"
        }
    }
}

// MARK: - Codable

extension MeetingService: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case hostname
    }

    private enum Kind: String, Codable {
        case yandexTelemost, googleMeet, zoom, microsoftTeams, unknown
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .yandexTelemost: self = .yandexTelemost
        case .googleMeet: self = .googleMeet
        case .zoom: self = .zoom
        case .microsoftTeams: self = .microsoftTeams
        case .unknown:
            let hostname = try container.decodeIfPresent(String.self, forKey: .hostname)
            self = .unknown(hostname: hostname)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .yandexTelemost:
            try container.encode(Kind.yandexTelemost, forKey: .type)
        case .googleMeet:
            try container.encode(Kind.googleMeet, forKey: .type)
        case .zoom:
            try container.encode(Kind.zoom, forKey: .type)
        case .microsoftTeams:
            try container.encode(Kind.microsoftTeams, forKey: .type)
        case .unknown(let hostname):
            try container.encode(Kind.unknown, forKey: .type)
            try container.encodeIfPresent(hostname, forKey: .hostname)
        }
    }
}
