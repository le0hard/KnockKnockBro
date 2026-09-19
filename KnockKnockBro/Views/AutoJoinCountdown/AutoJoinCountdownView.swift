import SwiftUI
import Combine
import Foundation

/// Контент countdown-панели Auto Join.
struct AutoJoinCountdownView: View {
    let occurrence: MeetingOccurrence
    let countdown: TimeInterval
    let connectOptions: [MeetingLauncher.ConnectOption]
    let onJoinNow: (URL) -> Void
    let onCancel: () -> Void

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var remaining: TimeInterval {
        max(0, occurrence.startDate.timeIntervalSince(now))
    }

    private var progress: Double {
        guard countdown > 0 else { return 1 }
        return min(1, max(0, 1 - remaining / countdown))
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)
                Text(occurrence.meeting.name)
                    .font(.headline)
                Text("Начало в \(Self.timeFormatter.string(from: occurrence.startDate))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                Text("Подключение через \(Int(remaining.rounded(.up))) сек")
                    .font(.subheadline)
                ProgressView(value: progress)
                Text(Self.countdownLabel(remaining))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }

            VStack(spacing: 8) {
                HStack {
                    ForEach(connectOptions) { option in
                        ConnectOptionButton(
                            title: "\(option.title) сейчас",
                            isPrimary: option.id == connectOptions.first?.id,
                            action: { onJoinNow(option.url) }
                        )
                    }
                }
                Button("Отмена", action: onCancel)
                    .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onReceive(timer) { newDate in
            now = newDate
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static func countdownLabel(_ remaining: TimeInterval) -> String {
        let total = Int(remaining.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    AutoJoinCountdownView(
        occurrence: MeetingOccurrence(
            meeting: Meeting(
                name: "Daily",
                url: URL(string: "https://telemost.yandex.ru/j/1")!,
                service: .yandexTelemost,
                type: .scheduled
            ),
            startDate: Date().addingTimeInterval(10)
        ),
        countdown: 10,
        connectOptions: [
            MeetingLauncher.ConnectOption(title: "Подключиться", url: URL(string: "telemost://https//telemost.yandex.ru/j/1")!),
            MeetingLauncher.ConnectOption(title: "Подключиться web", url: URL(string: "https://telemost.yandex.ru/j/1")!),
        ],
        onJoinNow: { _ in },
        onCancel: {}
    )
}
