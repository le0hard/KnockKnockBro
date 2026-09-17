import SwiftUI

/// Небольшой цветной "чип" с иконкой сервиса — НЕ логотип (логотипы
/// сервисов видеосвязи защищены товарными знаками и не воспроизводятся
/// приложением), а стилизованный значок в характерной для каждого
/// сервиса цветовой гамме. Этого достаточно, чтобы встречи разных
/// сервисов визуально различались на глаз, не копируя саму графику
/// бренда.
///
/// Цвет вынесен сюда, в View-слой, а не в модель `MeetingService` — это
/// сохраняет `Models` framework-agnostic: они не зависят от SwiftUI/`Color`
/// и продолжают свободно использоваться в сервисах и тестах без
/// UI-зависимостей.
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
                    .foregroundStyle(.white)
            }
    }

    /// Цветовая гамма, характерная для каждого сервиса.
    static func tintColor(for service: MeetingService) -> Color {
        switch service {
        case .yandexTelemost:
            return Color(hex: "FC3F1D") // фирменный красный Яндекса
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
