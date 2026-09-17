import SwiftUI
import AppKit
import Combine

/// Контент попапа Menu Bar: ближайшая встреча, встречи на сегодня и
/// Quick Rooms — с рабочей кнопкой "Подключиться" у каждой записи.
///
/// Обновляется раз в 30 секунд через обычный `Timer`, пока попап открыт —
/// не `TimelineView`, который в роли лейбла статус-бар-айтема провоцирует
/// бесконечную перерисовку.
struct MenuBarContentView: View {
    @Environment(MeetingStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorScheme) private var colorScheme
    @State private var now = Date()

    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        content(now: now)
            .frame(width: 280)
            .background(AppTheme.panelBackground(for: colorScheme))
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
        // Исключаем встречу, уже показанную в "Следующая встреча" — не
        // дублируем её ещё раз в списке "Сегодня".
        let remainingTodayOccurrences = todayOccurrences.filter { $0.id != nextOccurrence?.id }
        // "Сегодня" скрывается ПОЛНОСТЬЮ (без заголовка и без пустого
        // состояния), если единственная причина её пустоты — то, что
        // единственная сегодняшняя встреча уже показана выше как
        // "Следующая встреча" (в этом случае заголовок "Следующая
        // встреча" сам получает пометку "· Сегодня" — см.
        // `nextOccurrenceSectionTitle`). Показывать в этом случае "На
        // сегодня встреч нет" было бы вводящим в заблуждение —
        // противоречило бы блоку прямо над ним. Пустое состояние
        // показывается только тогда, когда на сегодня ДЕЙСТВИТЕЛЬНО нет
        // ни одной встречи.
        let isTodaySectionRedundant = remainingTodayOccurrences.isEmpty && !todayOccurrences.isEmpty
        let quickRooms = store.meetings.filter { $0.type == .quickRoom && $0.enabled }

        VStack(alignment: .leading, spacing: 0) {
            Text("KnockKnockBro")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 8)

            if let nextOccurrence {
                Divider()
                sectionHeader(nextOccurrenceSectionTitle(nextOccurrence, now: now, calendar: calendar))
                occurrenceRow(
                    nextOccurrence,
                    subtitle: UpcomingMeetingsProvider.relativeTimeDescription(from: now, to: nextOccurrence.startDate)
                )
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
                        occurrenceRow(occurrence, subtitle: Self.timeFormatter.string(from: occurrence.startDate))
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
                Text("Открыть KnockKnockBro")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Button {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Text("Настройки")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Выйти")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .padding(.bottom, 6)
        }
    }

    /// Показывает главное окно, приводя в порядок два возможных состояния:
    /// оно уже открыто (просто выводим на передний план) или было закрыто
    /// пользователем (создаём заново через `openWindow`). Без этой
    /// проверки повторные нажатия при уже открытом окне создавали бы
    /// дублирующиеся окна.
    private func openMainWindow() {
        if let window = NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    /// "Следующая встреча", а если она приходится на сегодня — "Следующая
    /// встреча · Сегодня", чтобы явно дать понять, что это одновременно и
    /// ближайшая, и сегодняшняя встреча, даже когда отдельная секция
    /// "Сегодня" из-за этого совпадения скрыта.
    private func nextOccurrenceSectionTitle(_ occurrence: MeetingOccurrence, now: Date, calendar: Calendar) -> String {
        let isToday = calendar.isDate(occurrence.startDate, inSameDayAs: now)
        return isToday ? "Следующая встреча · Сегодня" : "Следующая встреча"
    }

    private func occurrenceRow(_ occurrence: MeetingOccurrence, subtitle: String) -> some View {
        HStack {
            ServiceIconView(service: occurrence.meeting.service, size: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(occurrence.meeting.name)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Подключиться") {
                MeetingLauncher.open(occurrence.meeting.url)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func quickRoomRow(_ meeting: Meeting) -> some View {
        HStack {
            ServiceIconView(service: meeting.service, size: 22)
            Text(meeting.name)
                .font(.body)
            Spacer()
            Button("Подключиться") {
                MeetingLauncher.open(meeting.url)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

#Preview {
    MenuBarContentView()
        .environment(MeetingStore())
}
