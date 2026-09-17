import SwiftUI

/// Небольшая панель, показываемая после пробуждения Mac, если встреча
/// должна была начаться, пока он спал.
///
/// Никогда не открывает URL автоматически — только по явному нажатию
/// "Подключиться". Это прямая реализация требования: после сна
/// приложение не запускает встречу автоматически задним числом.
struct MissedMeetingPromptView: View {
    let occurrence: MeetingOccurrence
    let onJoin: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "bell.badge.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(occurrence.meeting.name)
                        .font(.headline)
                    Text(startedAgoDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Подключиться") {
                    onJoin()
                }
                .buttonStyle(.borderedProminent)

                Button("Пропустить") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private var startedAgoDescription: String {
        let minutes = max(0, Int(Date().timeIntervalSince(occurrence.startDate) / 60))
        if minutes == 0 {
            return "началась только что"
        } else if minutes == 1 {
            return "началась минуту назад"
        } else {
            return "началась \(minutes) минут назад"
        }
    }
}

#Preview {
    MissedMeetingPromptView(
        occurrence: MeetingOccurrence(
            meeting: Meeting(
                name: "Daily",
                url: URL(string: "https://telemost.yandex.ru/j/1")!,
                service: .yandexTelemost,
                type: .scheduled
            ),
            startDate: Date().addingTimeInterval(-3 * 60)
        ),
        onJoin: {},
        onDismiss: {}
    )
}
