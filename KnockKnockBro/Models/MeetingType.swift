import Foundation

/// Тип встречи: постоянная комната без расписания или запланированная
/// повторяющаяся встреча.
enum MeetingType: String, Codable, Equatable, Hashable {
    case quickRoom
    case scheduled
}
