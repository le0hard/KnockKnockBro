import Foundation

/// Календарный день (год-месяц-день) без времени и часового пояса.
///
/// Используется для разовых встреч: дата хранится так же, как время
/// начала в `MeetingSchedule` (`hour`/`minute`), — в локальном времени
/// пользователя, а не как абсолютный момент `Date`. Благодаря этому
/// встреча "5 октября в 10:00" остаётся в 10:00 5 октября, даже если
/// пользователь переехал в другой часовой пояс — ровно так же ведут себя
/// повторяющиеся встречи.
///
/// В JSON кодируется строкой ISO 8601 `"yyyy-MM-dd"` — человекочитаемо
/// и однозначно.
struct CalendarDay: Hashable, Comparable {
    var year: Int
    var month: Int
    var day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Календарный день, содержащий момент `date`, в указанном календаре.
    init(date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = components.year ?? 1970
        self.month = components.month ?? 1
        self.day = components.day ?? 1
    }

    /// `false` для несуществующих дат вроде 30 февраля — такие значения
    /// могут прийти только из импортируемого JSON, UI их создать не может.
    func isValid(in calendar: Calendar = .current) -> Bool {
        let components = DateComponents(year: year, month: month, day: day)
        return components.isValidDate(in: calendar)
    }

    /// Начало этого дня в указанном календаре, либо `nil` для
    /// несуществующей даты.
    func startOfDay(in calendar: Calendar = .current) -> Date? {
        guard isValid(in: calendar) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// Конкретный момент начала встречи в этот день.
    func date(hour: Int, minute: Int, calendar: Calendar = .current) -> Date? {
        guard let start = startOfDay(in: calendar) else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: start)
    }

    static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    // MARK: - ISO string

    /// `"2026-10-05"`.
    var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Строгий разбор `"yyyy-MM-dd"`. Проверяет только формат; существование
    /// даты (30 февраля) проверяется отдельно через `isValid(in:)` — при
    /// валидации импорта, с понятным пользователю сообщением.
    init?(isoString: String) {
        let parts = isoString.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    // MARK: - Display

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.setLocalizedDateFormatFromTemplate("d MMMM yyyy")
        return formatter
    }()

    /// Для UI: "5 октября 2026 г.".
    func displayString(calendar: Calendar = .current) -> String {
        guard let date = startOfDay(in: calendar) else { return isoString }
        return Self.displayFormatter.string(from: date)
    }
}

// MARK: - Codable

extension CalendarDay: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let value = CalendarDay(isoString: string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Ожидается дата в формате yyyy-MM-dd, получено \"\(string)\""
            )
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
