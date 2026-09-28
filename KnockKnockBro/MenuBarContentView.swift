import SwiftUI
import AppKit
import Combine

/// Контент попапа Menu Bar: ближайшая встреча, встречи на сегодня и
/// Quick Rooms.
struct MenuBarContentView: View {
    @Environment(MeetingStore.self) private var store
    @Environment(AppSettingsStore.self) private var settings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss
    @State private var now = Date()

    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        content(now: now)
            // Ширина по содержимому: окно `MenuBarExtra(.window)` берёт
            // идеальный размер контента, а гибкий frame ограничивает его
            // диапазоном. Если всё помещается — попап узкий (не меньше
            // `minPopupWidth`); длинные названия / две кнопки Телемоста
            // расширяют его, но не больше `maxPopupWidth` — дальше
            // название переносится на вторую строку.
            .frame(minWidth: Self.minPopupWidth, maxWidth: Self.maxPopupWidth)
            .background(.regularMaterial)
            .onReceive(timer) { newDate in
                now = newDate
            }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let calendar = Calendar.current
        let todayOccurrences = UpcomingMeetingsProvider.todayOccurrences(
            meetings: store.meetings, exceptions: store.exceptions, now: now, calendar: calendar
        )
        let nextOccurrence = UpcomingMeetingsProvider.nextUpcomingOccurrence(
            meetings: store.meetings, exceptions: store.exceptions, now: now, calendar: calendar
        )
        let remainingTodayOccurrences = todayOccurrences.filter { $0.id != nextOccurrence?.id }
        let isTodaySectionRedundant = remainingTodayOccurrences.isEmpty && !todayOccurrences.isEmpty
        let quickRooms = store.meetings.filter { $0.type == .quickRoom && $0.enabled }

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("KnockKnockBro")
                    .font(.title3.bold())
                Spacer()
                Button {
                    openCalendarWindow()
                } label: {
                    Image(systemName: "calendar")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .help("Календарь")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            if let nextOccurrence {
                Divider()
                sectionHeader(nextOccurrenceSectionTitle(nextOccurrence, now: now, calendar: calendar))
                occurrenceRow(nextOccurrence, now: now)
            }

            if !isTodaySectionRedundant {
                Divider()
                sectionHeader("Сегодня")
                if remainingTodayOccurrences.isEmpty {
                    Text("На сегодня встреч нет")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                } else {
                    ForEach(remainingTodayOccurrences) { occurrence in
                        occurrenceRow(occurrence, now: now)
                    }
                }
            }

            if !quickRooms.isEmpty {
                Divider()
                sectionHeader("Быстрый доступ")
                ForEach(quickRooms) { meeting in
                    quickRoomRow(meeting)
                }
            }

            Divider()

            Button {
                openMainWindow()
            } label: {
                Label("Открыть KnockKnockBro", systemImage: "macwindow")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Button {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Настройки", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Выйти", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .padding(.bottom, 6)
        }
    }

    /// Открывает главное окно и переводит на него фокус, одновременно
    /// закрывая сам попап Menu Bar — без этого попап оставался бы
    /// визуально открытым поверх появившегося окна. У `MenuBarExtra` нет
    /// публичного API "закрыть себя программно", поэтому имитируем
    /// нажатие Escape — тот же способ, которым AppKit штатно закрывает
    /// popover-стиль расширений строки меню.
    private func openMainWindow() {
        dismiss()
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) }) {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }

    /// Открывает окно "Календарь" (или выводит на передний план уже
    /// открытое, разворачивая из Dock при необходимости).
    private func openCalendarWindow() {
        dismiss()
        CalendarWindow.show(using: openWindow)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func nextOccurrenceSectionTitle(_ occurrence: MeetingOccurrence, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(occurrence.startDate, inSameDayAs: now) {
            return "Следующая встреча · Сегодня"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(occurrence.startDate, inSameDayAs: tomorrow) {
            return "Следующая встреча · Завтра"
        }
        return "Следующая встреча"
    }

    /// Строка запланированной встречи: слева выровненная колонка времени
    /// (крупное HH:MM и под ним — сколько осталось/прошло), затем иконка
    /// сервиса, название и кнопки подключения.
    private func occurrenceRow(_ occurrence: MeetingOccurrence, now: Date) -> some View {
        let connectOptions = MeetingLauncher.connectOptions(for: occurrence.meeting, telemostMode: settings.telemostConnectionMode)
        let hasStarted = occurrence.startDate <= now
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                BlinkingClockText(date: occurrence.startDate)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(hasStarted ? .secondary : .primary)
                Text(UpcomingMeetingsProvider.timeColumnCaption(from: now, to: occurrence.startDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: Self.timeColumnWidth, alignment: .leading)

            ServiceIconView(service: occurrence.meeting.service, size: 22)

            Text(occurrence.meeting.name)
                .font(.headline)
                .lineLimit(2)
            Spacer(minLength: 8)
            ForEach(connectOptions) { option in
                ConnectOptionButton(
                    title: option.title,
                    isPrimary: option.id == connectOptions.first?.id,
                    action: { MeetingLauncher.open(option.url) }
                )
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func quickRoomRow(_ meeting: Meeting) -> some View {
        let connectOptions = MeetingLauncher.connectOptions(for: meeting, telemostMode: settings.telemostConnectionMode)
        return HStack {
            ServiceIconView(service: meeting.service, size: 22)
            Text(meeting.name)
                .font(.headline)
            Spacer()
            ForEach(connectOptions) { option in
                ConnectOptionButton(
                    title: option.title,
                    isPrimary: option.id == connectOptions.first?.id,
                    action: { MeetingLauncher.open(option.url) }
                )
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    /// Минимальная ширина попапа — прежняя фиксированная ширина до v0.4.0.
    private static let minPopupWidth: CGFloat = 340

    /// Максимальная ширина попапа: до неё попап расширяется, только если
    /// содержимое (колонка времени + название + кнопки) не помещается.
    private static let maxPopupWidth: CGFloat = 460

    /// Фиксированная ширина колонки времени — именно она выравнивает
    /// время и названия встреч по вертикали между строками.
    private static let timeColumnWidth: CGFloat = 84

}

#Preview {
    MenuBarContentView()
        .environment(MeetingStore())
        .environment(AppSettingsStore())
}
