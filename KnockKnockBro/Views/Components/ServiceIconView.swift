import SwiftUI

/// Небольшой цветной "чип" с иконкой сервиса — НЕ логотип (логотипы
/// сервисов видеосвязи защищены товарными знаками и не воспроизводятся
/// приложением), а стилизованный значок в характерной для каждого
/// сервиса цветовой гамме.
struct ServiceIconView: View {
    let service: MeetingService
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Self.tintColor(for: service))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: service.systemImageName)
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(Self.iconColor(for: service))
            }
    }

    /// Цветовая гамма фона чипа, характерная для каждого сервиса.
    static func tintColor(for service: MeetingService) -> Color {
        switch service {
        case .yandexTelemost:
            return Color(hex: "00AC47") // зелёный, отличается от Meet цветом иконки внутри
        case .googleMeet:
            return Color(hex: "00AC47") // характерный зелёный Google Meet
        case .zoom:
            return Color(hex: "2D8CFF") // характерный синий Zoom
        case .microsoftTeams:
            return Color(hex: "6264A7") // характерный фиолетовый Microsoft Teams
        case .unknown:
            return Color.secondary
        }
    }

    /// Цвет символа внутри чипа — для Телемоста и Meet отличается,
    /// так как оба сервиса используют одинаковый
    /// зелёный фон и различаются именно цветом иконки.
    static func iconColor(for service: MeetingService) -> Color {
        switch service {
        case .yandexTelemost:
            return .black
        default:
            return .white
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        ServiceIconView(service: .yandexTelemost)
        ServiceIconView(service: .googleMeet)
        ServiceIconView(service: .zoom)
        ServiceIconView(service: .microsoftTeams)
        ServiceIconView(service: .unknown(hostname: "example.com"))
    }
    .padding()
}
