import Foundation

/// Одна встреча в списке дня окна "Календарь".
///
/// Пропущенные ("Пропустить сегодня") экземпляры не выбрасываются, а
/// помечаются `isSkipped` — в календаре полезно видеть, что встреча в этот
/// день была, но пропущена.
struct DayAgendaItem: Identifiable, Equatable {
    let occurrence: MeetingOccurrence
    let isSkipped: Bool

    var id: String { occurrence.id }
}

/// Раскладка месяца для окна "Календарь" и выборка встреч по дням.
///
/// Чистый компонент без состояния (как `OccurrenceEngine` и
/// `UpcomingMeetingsProvider`): вся календарная арифметика здесь, а
/// SwiftUI-вью только рисует результат — это позволяет покрыть сетку
/// месяца тестами без UI.
///
/// Неделя всегда начинается с понедельника — как и выбор дней недели в
/// редакторе (`Weekday.mondayFirstOrder`), независимо от региональных
/// настроек системы.
struct CalendarMonthLayout {

    /// Начало первого дня месяца, содержащего `date`.
    static func startOfMonth(for date: Date, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    /// Начало месяца, сдвинутого на `value` месяцев от `monthStart`.
    static func month(byAdding value: Int, to monthStart: Date, calendar: Calendar = .current) -> Date {
        let shifted = calendar.date(byAdding: .month, value: value, to: monthStart) ?? monthStart
        return startOfMonth(for: shifted, calendar: calendar)
    }

    /// День с номером `preferredDay` в месяце, начинающемся с `monthStart`;
    /// если в месяце столько дней нет — его последний день (31 → 28/29
    /// февраля, 31 → 30 апреля).
    ///
    /// Используется при листании месяцев в окне "Календарь": выбранный
    /// день переносится на то же число нового месяца.
    static func day(_ preferredDay: Int, inMonthStarting monthStart: Date, calendar: Calendar = .current) -> Date {
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 28
        let clampedDay = min(max(preferredDay, 1), daysInMonth)
        return calendar.date(byAdding: .day, value: clampedDay - 1, to: monthStart) ?? monthStart
    }

    /// Ячейки сетки месяца по неделям Пн–Вс: `nil` — пустая ячейка до 1-го
    /// числа и после последнего; иначе — начало соответствующего дня.
    /// Количество ячеек всегда кратно 7.
    static func cells(forMonthStarting monthStart: Date, calendar: Calendar = .current) -> [Date?] {
        guard let dayRange = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }

        // weekday: 1 = воскресенье ... 7 = суббота → смещение от понедельника.
        let weekdayNumber = calendar.component(.weekday, from: monthStart)
        let leadingEmptyCells = (weekdayNumber + 5) % 7

        var cells: [Date?] = Array(repeating: nil, count: leadingEmptyCells)
        for dayNumber in dayRange {
            cells.append(calendar.date(byAdding: .day, value: dayNumber - 1, to: monthStart))
        }
        while cells.count % 7 != 0 {
            cells.append(nil)
        }
        return cells
    }

    /// Дни месяца, в которые есть хотя бы одна НЕ пропущенная встреча —
    /// для точек-индикаторов под числами.
    static func daysWithMeetings(
        meetings: [Meeting],
        exceptions: [MeetingOccurrenceException],
        monthStart: Date,
        calendar: Calendar = .current
    ) -> Set<CalendarDay> {
        let monthEnd = month(byAdding: 1, to: monthStart, calendar: calendar)
        let range = DateInterval(start: monthStart, end: monthEnd)
        let occurrences = OccurrenceEngine.occurrences(for: meetings, in: range, exceptions: exceptions, calendar: calendar)
        return Set(occurrences.map { CalendarDay(date: $0.startDate, calendar: calendar) })
    }

    /// Все встречи дня, содержащего `day`, по времени начала — включая
    /// пропущенные (с пометкой `isSkipped`).
    static func agenda(
        on day: Date,
        meetings: [Meeting],
        exceptions: [MeetingOccurrenceException],
        calendar: Calendar = .current
    ) -> [DayAgendaItem] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        let range = DateInterval(start: dayStart, end: dayEnd)

        // Без исключений — чтобы пропущенные экземпляры тоже попали в
        // результат; пометку ставим ниже.
        return OccurrenceEngine.occurrences(for: meetings, in: range, calendar: calendar).map { occurrence in
            let isSkipped = exceptions.contains {
                $0.isSkipped && $0.matches(meetingID: occurrence.meeting.id, date: occurrence.startDate, calendar: calendar)
            }
            return DayAgendaItem(occurrence: occurrence, isSkipped: isSkipped)
        }
    }
}
