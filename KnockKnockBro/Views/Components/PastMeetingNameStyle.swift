import SwiftUI

/// Оформление названия прошедшей / пропущенной встречи: зачёркнуто, но
/// читаемо.
///
/// У SwiftUI нет параметра толщины линии зачёркивания — она следует за
/// насыщенностью шрифта, поэтому на жирном `.headline` получалась толстой и
/// "съедала" название. Вместо этого для прошедших встреч:
/// - шрифт становится обычной насыщенности (`.regular`) — линия тоньше;
/// - текст и линия приглушены (`.secondary`) — встреча визуально уходит на
///   второй план, но остаётся разборчивой.
private struct PastMeetingNameStyle: ViewModifier {
    let isPast: Bool

    func body(content: Content) -> some View {
        if isPast {
            content
                .fontWeight(.regular)
                .strikethrough(true, color: .secondary)
                .foregroundStyle(.secondary)
        } else {
            content
        }
    }
}

extension View {
    /// Зачёркнутое приглушённое название, если `isPast`; иначе без изменений.
    func pastMeetingNameStyle(_ isPast: Bool) -> some View {
        modifier(PastMeetingNameStyle(isPast: isPast))
    }
}
