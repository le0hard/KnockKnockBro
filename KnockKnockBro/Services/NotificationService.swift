import Foundation
import UserNotifications
import AVFoundation

/// Планирует и обрабатывает системные уведомления-напоминания о встречах.
///
/// Ключевое архитектурное решение: для Scheduled Meeting планируются
/// ТОЛЬКО одноразовые (`repeats: false`) запросы на конкретные предстоящие
/// даты в ближнем горизонте (`schedulingHorizon`), а не один повторяющийся
/// триггер на всю серию. Это прямое следствие ограничения UserNotifications:
/// у repeating-триггера нельзя отменить одно отдельное вхождение без отмены
/// всей серии — а нам это понадобится для "Пропустить сегодня" и для
/// Enable/Disable. Идентификатор каждого запроса детерминирован и построен
/// из (meetingID, дата, reminderID) — именно это позволит точечно отменять
/// уведомления одного конкретного дня без пересборки всего остального.
@Observable
final class NotificationService: NSObject {

    /// Как далеко в будущее планируются уведомления за один проход.
    /// Выбрано с запасом ниже документированного системного лимита в 64
    /// pending-уведомления на приложение — с этим горизонтом разумное
    /// количество встреч и напоминаний не рискует упереться в лимит.
    private let schedulingHorizon: TimeInterval = 48 * 60 * 60

    private let center = UNUserNotificationCenter.current()
    private let launcher: MeetingLauncher.Type

    /// Удерживает плеер, пока звук не доиграет — иначе `AVAudioPlayer`
    /// будет деинициализирован сразу после вызова `play()`.
    private var audioPlayer: AVAudioPlayer?

    /// `true`, если пользователь разрешил уведомления. `nil` — статус ещё
    /// не запрошен/не определён.
    private(set) var isAuthorized: Bool?

    private static let categoryIdentifier = "MEETING_REMINDER"
    private static let joinActionIdentifier = "JOIN_ACTION"
    private static let snoozeActionIdentifier = "SNOOZE_ACTION"

    /// Ключи `userInfo` для восстановления контекста при обработке нажатия.
    private enum UserInfoKey {
        static let meetingID = "meetingID"
        static let meetingURL = "meetingURL"
        static let meetingName = "meetingName"
        static let startDate = "startDate"
        static let soundOption = "soundOption"
    }

    init(launcher: MeetingLauncher.Type = MeetingLauncher.self) {
        self.launcher = launcher
        super.init()
        center.delegate = self
        registerCategories()
    }

    // MARK: - Authorization

    /// Запрашивает разрешение на показ уведомлений. Безопасно вызывать
    /// повторно — система сама не показывает диалог дважды, если решение
    /// уже принято пользователем.
    ///
    /// Использует нативный `async`-вариант API вместо completion handler'а
    /// с вложенным `Task` — это устраняет необходимость в `[weak self]` и
    /// связанное с ней предупреждение о конкурентном доступе к состоянию.
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

    // MARK: - Scheduling

    /// Полностью пересчитывает и переустанавливает pending-уведомления для
    /// всех переданных встреч на горизонт `schedulingHorizon` от `now`, с
    /// учётом точечных исключений "Пропустить сегодня".
    ///
    /// Стратегия "с нуля": сначала отменяются все текущие pending-запросы,
    /// затем планируются заново на основе актуального состояния встреч и
    /// исключений. Для десятков записей это дешевле и надёжнее точечного
    /// diff'а и исключает рассинхронизацию между тем, что должно быть
    /// запланировано, и тем, что реально запланировано.
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

        // Момент напоминания уже в прошлом (например, "за 15 минут" для
        // встречи, которая начинается через 5 минут после перезапуска
        // планирования) — такое напоминание не имеет смысла ставить в
        // очередь, система бы показала его "с опозданием" немедленно.
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

    /// Детерминированный идентификатор запроса. Использует ту же
    /// гранулярность дня, что и `MeetingOccurrence.id`, так что уведомления
    /// одной встречи на один день всегда узнаваемы по префиксу.
    private func requestIdentifier(meetingID: UUID, startDate: Date, reminderID: UUID) -> String {
        let day = Calendar.current.startOfDay(for: startDate)
        return "\(meetingID.uuidString)|\(Int(day.timeIntervalSince1970))|\(reminderID.uuidString)"
    }

    // MARK: - Snooze

    /// Планирует одноразовое напоминание через 5 минут от текущего момента
    /// — используется action'ом "Через 5 минут" из уведомления.
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

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {

    /// Показывать уведомление, даже если приложение сейчас активно и на
    /// переднем плане — без этого система по умолчанию не показала бы
    /// alert/sound, если у KnockKnockBro сейчас открыто главное окно.
    ///
    /// Кастомный звук на macOS проигрывается САМИМ приложением через
    /// AVAudioPlayer, читающим файл прямо из бандла — в отличие от
    /// системного пути `UNNotificationSound(named:)`, это не требует
    /// записи в защищённую sandbox'ом папку Library/Sounds. Системный
    /// звук в этом случае подавляется, чтобы не было дублирования;
    /// `content.sound` (системный звук по умолчанию) остаётся как
    /// запасной вариант на случай редкого сценария, когда приложение
    /// не было запущено в момент показа уведомления.
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
            // Не критично — в худшем случае просто не будет звука у этого
            // конкретного уведомления.
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
            // Совпадает и с явным нажатием кнопки "Подключиться", и с
            // кликом по самому уведомлению (стандартное поведение системы).
            launcher.open(url)
        case Self.snoozeActionIdentifier:
            scheduleSnooze(meetingID: meetingID, meetingName: meetingName, meetingURLString: urlString, originalStartDate: startDate)
        default:
            break
        }

        completionHandler()
    }
}

// MARK: - NotificationSoundOption mapping

private extension NotificationSoundOption {
    /// Сопоставление пользовательского пресета звука с реальным
    /// `UNNotificationSound`. Для `.short` этот системный звук — лишь
    /// ЗАПАСНОЙ вариант на случай, если приложение не было запущено в
    /// момент показа уведомления; в основном сценарии кастомный звук
    /// проигрывается вручную через `AVAudioPlayer` в `willPresent`
    /// (см. `NotificationService`), так как `UNNotificationSound(named:)`
    /// на macOS требует записи в `Library/Sounds`, что блокирует App
    /// Sandbox.
    var unNotificationSound: UNNotificationSound? {
        switch self {
        case .system: return .default
        case .short: return .default
        case .none: return nil
        }
    }
}
