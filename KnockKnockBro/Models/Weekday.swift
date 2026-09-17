import Foundation

/// День недели, пронумерованный так же, как `Calendar`'s `weekday`-компонент
/// (1 = воскресенье ... 7 = субботa) — это системная нумерация, не зависящая
/// от локали пользователя (какой день считается "первым" в неделе — вопрос
/// отображения, а не хранения).
enum Weekday: Int, Codable, CaseIterable, Identifiable, Comparable, Equatable, Hashable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    var id: Int { rawValue }

    static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Короткое название для UI ("Пн", "Вт", ...), как на макете экрана
    /// "Новая встреча".
    var shortDisplayName: String {
        switch self {
        case .sunday: return "Вс"
        case .monday: return "Пн"
        case .tuesday: return "Вт"
        case .wednesday: return "Ср"
        case .thursday: return "Чт"
        case .friday: return "Пт"
        case .saturday: return "Сб"
        }
    }
}

extension Weekday {
    /// Дни недели в порядке "понедельник — воскресенье", как принято
    /// отображать в русскоязычном интерфейсе. В отличие от `allCases`
    /// (который идёт в порядке системной нумерации Calendar, начиная с
    /// воскресенья), этот порядок используется только для отображения —
    /// хранение и сравнение всегда идут через `rawValue`/`Comparable`.
    static let mondayFirstOrder: [Weekday] = [
        .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday,
    ]
}
