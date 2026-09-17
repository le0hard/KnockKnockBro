import Foundation

/// Вычисляет предстоящие экземпляры встреч для отображения в Menu Bar (и
/// позже — в главном окне) — тонкая обёртка над `OccurrenceEngine`,
/// которая стандартизирует диапазоны ("сегодня", "ближайшие 48 часов") и
/// добавляет человекочитаемое форматирование оставшегося времени.
///
/// Как и `OccurrenceEngine`, это чистый, не хранящий состояние компонент —
/// никакой персистентности, никаких побочных эффектов, что позволяет
/// тестировать его исчерпывающе без поднятия SwiftUI-контекста.
struct UpcomingMeetingsProvider {

    /// Горизонт поиска "ближайшей встречи" для Menu Bar. Совпадает с
    /// горизонтом планирования уведомлений (`NotificationService`) — этого
    /// достаточно, чтобы всегда находить следующую встречу в пределах
    /// ближайших двух суток.
    static let upcomingHorizon: TimeInterval = 48 * 60 * 60

    /// Все экземпляры запланированных встреч, приходящиеся на календарный
    /// день, содержащий `now` — включая уже прошедшие сегодня.
    static func todayOccurrences(
        meetings: [Meeting],
        exceptions: [MeetingOccurrenceException],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [MeetingOccurrence] {
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        let range = DateInterval(start: dayStart, end: dayEnd)
        return OccurrenceEngine.occurrences(for: scheduledOnly(meetings), in: range, exceptions: exceptions, calendar: calendar)
    }

    /// Самый ближайший ещё не начавшийся экземпляр в пределах
    /// `upcomingHorizon` от `now`, если такой есть.
    static func nextUpcomingOccurrence(
        meetings: [Meeting],
        exceptions: [MeetingOccurrenceException],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MeetingOccurrence? {
        let range = DateInterval(start: now, duration: upcomingHorizon)
        return OccurrenceEngine.occurrences(for: scheduledOnly(meetings), in: range, exceptions: exceptions, calendar: calendar).first
    }
    /// Только сегодняшняя, ещё не начавшаяся встреча — используется
    /// лейблом строки меню (`MenuBarLabelView`), чтобы там НЕ показывался
    /// обратный отсчёт до встречи, которая начнётся только завтра (даже
    /// если формально она "ближайшая" в пределах горизонта поиска).
    /// Отсчёт в строке меню появляется только начиная с того дня, когда
    /// встреча действительно происходит, а не заранее.
    static func nextOccurrenceToday(
        meetings: [Meeting],
        exceptions: [MeetingOccurrenceException],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MeetingOccurrence? {
        todayOccurrences(meetings: meetings, exceptions: exceptions, now: now, calendar: calendar)
            .first { $0.startDate > now }
    }
    
    private static func scheduledOnly(_ meetings: [Meeting]) -> [Meeting] {
        meetings.filter { $0.type == .scheduled }
    }

    // MARK: - Formatting

    /// Компактное представление оставшегося времени для Menu Bar-лейбла,
    /// например "12m" или "4h 42m".
    static func compactRemainingLabel(from now: Date, to date: Date) -> String {
        let totalMinutes = max(0, Int(date.timeIntervalSince(now) / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 {
            return "\(minutes)m"
        } else if minutes == 0 {
            return "\(hours)h"
        } else {
            return "\(hours)h \(minutes)m"
        }
    }

    /// Развёрнутое описание оставшегося времени для попапа Menu Bar,
    /// например "через 12 мин" или "через 4 ч 42 мин".
    static func relativeTimeDescription(from now: Date, to date: Date) -> String {
        let totalMinutes = max(0, Int(date.timeIntervalSince(now) / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours == 0 && minutes == 0 {
            return "сейчас"
        } else if hours == 0 {
            return "через \(minutes) мин"
        } else if minutes == 0 {
            return "через \(hours) ч"
        } else {
            return "через \(hours) ч \(minutes) мин"
        }
    }
}
