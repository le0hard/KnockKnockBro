import Foundation
import UserNotifications
import AVFoundation

/// Планирует и обрабатывает системные уведомления-напоминания о встречах.
@Observable
final class NotificationService: NSObject {

    private let schedulingHorizon: TimeInterval = 48 * 60 * 60

    private let center = UNUserNotificationCenter.current()
    private let launcher: MeetingLauncher.Type

    /// Определяет, какая ссылка "приоритетна" для встречи Яндекс Телемоста
    /// (Desktop/Web/оба) — то же значение, что использует остальной UI.
    /// Системное уведомление физически не может предложить выбор из двух
    /// кнопок (место уже занято "Через 5 минут"), поэтому нажатие
    /// "Подключиться" всегда ведёт по ПРИОРИТЕТНОЙ ссылке — согласованно
    /// с тем, что делает Auto Join при автоматическом срабатывании.
    private let telemostModeProvider: () -> TelemostConnectionMode

    private var audioPlayer: AVAudioPlayer?

    private(set) var isAuthorized: Bool?

    private static let categoryIdentifier = "MEETING_REMINDER"
    private static let joinActionIdentifier = "JOIN_ACTION"
    private static let snoozeActionIdentifier = "SNOOZE_ACTION"

    private enum UserInfoKey {
        static let meetingID = "meetingID"
        static let meetingURL = "meetingURL"
        static let meetingName = "meetingName"
        static let startDate = "startDate"
        static let soundOption = "soundOption"
    }

    init(
        launcher: MeetingLauncher.Type = MeetingLauncher.self,
        telemostModeProvider: @escaping () -> TelemostConnectionMode = { .both }
    ) {
        self.launcher = launcher
        self.telemostModeProvider = telemostModeProvider
        super.init()
        center.delegate = self
        registerCategories()
    }

    @MainActor
    func requestAuthorizationIfNeeded() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            isAuthorized = granted
        } catch {
            isAuthorized = false
        }
    }

    private func registerCategories() {
        let joinAction = UNNotificationAction(
            identifier: Self.joinActionIdentifier,
            title: "Подключиться",
            options: [.foreground]
        )
        let snoozeAction = UNNotificationAction(
            identifier: Self.snoozeActionIdentifier,
            title: "Через 5 минут",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [joinAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func rescheduleAll(
        for meetings: [Meeting],
        exceptions: [MeetingOccurrenceException] = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        center.removeAllPendingNotificationRequests()

        let range = DateInterval(start: now, duration: schedulingHorizon)
        let occurrences = OccurrenceEngine.occurrences(for: meetings, in: range, exceptions: exceptions, calendar: calendar)

        for occurrence in occurrences {
            for reminder in occurrence.meeting.reminders {
                schedule(reminder: reminder, for: occurrence, now: now)
            }
        }
    }

    private func schedule(reminder: MeetingReminder, for occurrence: MeetingOccurrence, now: Date) {
        let fireDate = occurrence.startDate.addingTimeInterval(-reminder.offsetBeforeStart)
        guard fireDate > now else { return }

        let content = makeContent(meeting: occurrence.meeting, startDate: occurrence.startDate, sound: reminder.sound)
        let interval = max(fireDate.timeIntervalSince(now), 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)

        let identifier = requestIdentifier(meetingID: occurrence.meeting.id, startDate: occurrence.startDate, reminderID: reminder.id)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.add(request)
    }

    private func makeContent(meeting: Meeting, startDate: Date, sound: NotificationSoundOption) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = meeting.name
        content.body = "Начало в \(Self.timeFormatter.string(from: startDate))"
        content.categoryIdentifier = Self.categoryIdentifier
        content.sound = sound.unNotificationSound
        content.userInfo = [
            UserInfoKey.meetingID: meeting.id.uuidString,
            UserInfoKey.meetingURL: meeting.url.absoluteString,
            UserInfoKey.meetingName: meeting.name,
            UserInfoKey.startDate: startDate.timeIntervalSince1970,
            UserInfoKey.soundOption: sound.rawValue,
        ]
        return content
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private func requestIdentifier(meetingID: UUID, startDate: Date, reminderID: UUID) -> String {
        let day = Calendar.current.startOfDay(for: startDate)
        return "\(meetingID.uuidString)|\(Int(day.timeIntervalSince1970))|\(reminderID.uuidString)"
    }

    private func scheduleSnooze(meetingID: String, meetingName: String, meetingURLString: String, originalStartDate: Date) {
        let content = UNMutableNotificationContent()
        content.title = meetingName
        content.body = "Начало в \(Self.timeFormatter.string(from: originalStartDate))"
        content.categoryIdentifier = Self.categoryIdentifier
        content.sound = .default
        content.userInfo = [
            UserInfoKey.meetingID: meetingID,
            UserInfoKey.meetingURL: meetingURLString,
            UserInfoKey.meetingName: meetingName,
            UserInfoKey.startDate: originalStartDate.timeIntervalSince1970,
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5 * 60, repeats: false)
        let identifier = "\(meetingID)|snooze|\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.add(request)
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo

        if let rawValue = userInfo[UserInfoKey.soundOption] as? String,
           let soundOption = NotificationSoundOption(rawValue: rawValue),
           soundOption == .short {
            playBundledSound(resource: "notification", extension: "wav")
            completionHandler([.banner, .list])
        } else {
            completionHandler([.banner, .sound, .list])
        }
    }

    private func playBundledSound(resource: String, extension fileExtension: String) {
        guard let url = Bundle.main.url(forResource: resource, withExtension: fileExtension) else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            audioPlayer = player
            player.play()
        } catch {
            // Не критично.
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        guard
            let meetingID = userInfo[UserInfoKey.meetingID] as? String,
            let urlString = userInfo[UserInfoKey.meetingURL] as? String,
            let url = URL(string: urlString),
            let meetingName = userInfo[UserInfoKey.meetingName] as? String,
            let startTimestamp = userInfo[UserInfoKey.startDate] as? TimeInterval
        else {
            completionHandler()
            return
        }

        let startDate = Date(timeIntervalSince1970: startTimestamp)

        switch response.actionIdentifier {
        case Self.joinActionIdentifier, UNNotificationDefaultActionIdentifier:
            let service = MeetingProviderDetector.detectService(from: url)
            let meeting = Meeting(
                id: UUID(uuidString: meetingID) ?? UUID(),
                name: meetingName,
                url: url,
                service: service,
                type: .quickRoom
            )
            let options = launcher.connectOptions(for: meeting, telemostMode: telemostModeProvider())
            let preferredURL = options.first?.url ?? url
            launcher.open(preferredURL)
        case Self.snoozeActionIdentifier:
            scheduleSnooze(meetingID: meetingID, meetingName: meetingName, meetingURLString: urlString, originalStartDate: startDate)
        default:
            break
        }

        completionHandler()
    }
}

private extension NotificationSoundOption {
    var unNotificationSound: UNNotificationSound? {
        switch self {
        case .system: return .default
        case .short: return .default
        case .none: return nil
        }
    }
}
