import SwiftUI

/// Время "HH:MM", у которого двоеточие плавно гаснет и появляется —
/// как на электронных часах.
///
/// Все экземпляры мигают синхронно без общего состояния: прозрачность
/// двоеточия вычисляется из абсолютного времени (`Date`), а не из
/// момента появления вью, — поэтому все часы в попапе всегда в одной фазе,
/// в том числе строки, появившиеся позже.
///
/// Шрифт и цвет задаются снаружи, как у обычного `Text`. Цифры не
/// двигаются: меняется только прозрачность двоеточия, а не его ширина.
/// При включённом "Уменьшить движение" (Универсальный доступ) двоеточие
/// статичное.
struct BlinkingClockText: View {
    let date: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Полный цикл "видно → погасло → видно", в секундах.
    static let blinkPeriod: TimeInterval = 2

    /// Минимальная прозрачность двоеточия — не гаснет до нуля полностью,
    /// чтобы время оставалось читаемым.
    static let minimumColonOpacity: Double = 0.15

    var body: some View {
        HStack(spacing: 0) {
            Text(Self.hourFormatter.string(from: date))
            colon
            Text(Self.minuteFormatter.string(from: date))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityFormatter.string(from: date))
    }

    @ViewBuilder
    private var colon: some View {
        if reduceMotion {
            Text(":")
        } else {
            // 30 кадров в секунду с запасом хватает для плавного
            // затухания; TimelineView сам останавливается, когда попап
            // закрыт и вью не на экране.
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                Text(":")
                    .opacity(Self.colonOpacity(at: context.date))
            }
        }
    }

    /// Прозрачность двоеточия в момент `date`: косинусоида от 1 (начало
    /// цикла) до `minimumColonOpacity` (середина) и обратно.
    static func colonOpacity(at date: Date) -> Double {
        let phase = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: blinkPeriod) / blinkPeriod
        let wave = (1 + cos(phase * 2 * .pi)) / 2
        return minimumColonOpacity + (1 - minimumColonOpacity) * wave
    }

    // MARK: - Formatting

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH"
        return formatter
    }()

    private static let minuteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "mm"
        return formatter
    }()

    private static let accessibilityFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

#Preview {
    VStack(alignment: .leading) {
        BlinkingClockText(date: Date())
        BlinkingClockText(date: Date().addingTimeInterval(3600))
    }
    .font(.system(size: 22, weight: .semibold, design: .rounded))
    .monospacedDigit()
    .padding()
}
