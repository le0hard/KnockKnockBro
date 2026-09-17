import SwiftUI
import Combine
import AppKit

/// Лейбл Menu Bar: иконка приложения плюс, если есть ЕЩЁ НЕ НАЧАВШАЯСЯ
/// встреча СЕГОДНЯ, оставшееся до неё время в компактном виде ("12m").
///
/// Специально использует `nextOccurrenceToday`, а не `nextUpcomingOccurrence`
/// (48-часовой горизонт) — если сегодня встреч больше нет, а следующая
/// только завтра (даже в 00:01), в строке меню остаётся только иконка,
/// без обратного отсчёта.
struct MenuBarLabelView: View {
    @Environment(MeetingStore.self) private var store
    @State private var now = Date()

    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private static let menuBarIcon: NSImage = {
        let image = NSImage(named: "MenuBarIcon") ?? NSImage()
        image.size = NSSize(width: 18, height: 18)
        return image
    }()

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: Self.menuBarIcon)
            if let next {
                Text(UpcomingMeetingsProvider.compactRemainingLabel(from: now, to: next.startDate))
            }
        }
        .onReceive(timer) { newDate in
            now = newDate
        }
    }

    private var next: MeetingOccurrence? {
        UpcomingMeetingsProvider.nextOccurrenceToday(
            meetings: store.meetings, exceptions: store.exceptions, now: now
        )
    }
}

#Preview {
    MenuBarLabelView()
        .environment(MeetingStore())
}
