import Foundation
import AppKit

/// Реагирует на пробуждение Mac из сна и приводит состояние приложения в
/// порядок: пересчитывает pending-уведомления на новый горизонт от
/// текущего момента и обнаруживает встречи, которые должны были начаться,
/// пока Mac спал.
///
/// Намеренно отделён от `AppDelegate`: `AppDelegate` отвечает только за
/// lifecycle самого процесса, а этот компонент — за бизнес-логику,
/// запускаемую системным событием пробуждения. Такое разделение делает
/// возможным тестирование самой логики обнаружения "пропущенных" встреч
/// без необходимости эмулировать реальный sleep/wake.
@Observable
final class WakeObserver {

    /// Если Mac проснулся не позднее этого времени после начала встречи,
    /// считаем её "пропущенной из-за сна" и показываем мягкий промпт.
    /// Более старые встречи молча игнорируются — показывать пользователю
    /// напоминание о встрече, прошедшей несколько часов назад, было бы
    /// не полезно, а раздражающе.
    static let missedMeetingWindow: TimeInterval = 10 * 60

    /// Встреча, которую нужно предложить пользователю после пробуждения —
    /// если такая была обнаружена. `nil`, если ничего показывать не нужно.
    private(set) var missedOccurrence: MeetingOccurrence?

    private var observer: NSObjectProtocol?

    /// Начинает слушать `NSWorkspace.didWakeNotification`. Вызывается один
    /// раз при старте приложения; снятие подписки не требуется, так как
    /// сервис живёт всё время работы процесса (как и `NotificationService`).
    func startObserving(
        meetingsProvider: @escaping () -> [Meeting],
        exceptionsProvider: @escaping () -> [MeetingOccurrenceException],
        onWake: @escaping () -> Void
    ) {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let now = Date()
            self.missedOccurrence = Self.findMissedOccurrence(
                meetings: meetingsProvider(),
                exceptions: exceptionsProvider(),
                now: now
            )
            onWake()
        }
    }

    /// Пользователь разобрался с промптом (подключился или пропустил) —
    /// скрываем его.
    func dismissMissedOccurrence() {
        missedOccurrence = nil
    }

    /// Находит ближайшую встречу, которая должна была начаться недавно
    /// (в пределах `missedMeetingWindow` до `now`), но ещё не была
    /// "закрыта" пользователем. Это чистая функция — вынесена отдельно
    /// от `startObserving`, чтобы её можно было протестировать напрямую,
    /// без эмуляции реального системного уведомления о пробуждении.
    static func findMissedOccurrence(
        meetings: [Meeting],
        exceptions: [MeetingOccurrenceException],
        now: Date,
        calendar: Calendar = .current
    ) -> MeetingOccurrence? {
        let windowStart = now.addingTimeInterval(-missedMeetingWindow)
        guard windowStart < now else { return nil }

        let range = DateInterval(start: windowStart, end: now)
        let scheduledMeetings = meetings.filter { $0.type == .scheduled }
        let occurrences = OccurrenceEngine.occurrences(
            for: scheduledMeetings, in: range, exceptions: exceptions, calendar: calendar
        )

        // Если случайно набралось несколько таких встреч (например, две
        // начинались в пределах одного окна), показываем ближайшую по
        // времени начала — остальные пользователь сможет открыть вручную
        // из главного окна или Menu Bar.
        return occurrences.last
    }
}
