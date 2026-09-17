import Foundation

/// Конкретный экземпляр повторяющейся встречи на конкретную дату/время.
///
/// Это НЕ хранимая сущность — она вычисляется на лету из `Meeting`'s
/// правила повторения для заданного диапазона дат `OccurrenceEngine`'ом.
/// Точечные отклонения по дате (например, "Пропустить сегодня") хранятся
/// отдельно, в `MeetingOccurrenceException`, и учитываются самим
/// `OccurrenceEngine` — это не требует, чтобы `MeetingOccurrence` стал
/// персистентной моделью.
struct MeetingOccurrence: Identifiable, Equatable {
    /// Детерминированный идентификатор, полученный из `id` встречи и
    /// календарного дня начала. Это гарантирует, что один и тот же
    /// экземпляр повторяющейся встречи всегда получает один и тот же `id`
    /// при повторном вычислении — важно для диффинга в SwiftUI и, позже,
    /// для однозначной привязки запланированных уведомлений к конкретной
    /// дате этой встречи.
    let id: String
    let meeting: Meeting
    let startDate: Date

    init(meeting: Meeting, startDate: Date, calendar: Calendar = .current) {
        self.meeting = meeting
        self.startDate = startDate

        // Используем гранулярность "день", а не точную секунду: два
        // вычисления одного и того же экземпляра в один и тот же день —
        // это один и тот же экземпляр, даже если секунды startDate
        // отличаются из-за пересчёта с чуть другим Calendar.
        let day = calendar.startOfDay(for: startDate)
        self.id = "\(meeting.id.uuidString)|\(Int(day.timeIntervalSince1970))"
    }
}
