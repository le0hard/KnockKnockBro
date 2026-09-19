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
            .frame(width: 340)
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
            Text("KnockKnockBro")
                .font(.title3.bold())
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 8)

            if let nextOccurrence {
                Divider()
                sectionHeader(nextOccurrenceSectionTitle(nextOccurrence, now: now, calendar: calendar))
                occurrenceRow(
                    nextOccurrence,
                    subtitle: "\(UpcomingMeetingsProvider.relativeTimeDescription(from: now, to: nextOccurrence.startDate)) · \(Self.timeFormatter.string(from: nextOccurrence.startDate))"
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func nextOccurrenceSectionTitle(_ occurrence: MeetingOccurrence, now: Date, calendar: Calendar) -> String {
        let isToday = calendar.isDate(occurrence.startDate, inSameDayAs: now)
        return isToday ? "Следующая встреча · Сегодня" : "Следующая встреча"
    }

    private func occurrenceRow(_ occurrence: MeetingOccurrence, subtitle: String) -> some View {
        let connectOptions = MeetingLauncher.connectOptions(for: occurrence.meeting, telemostMode: settings.telemostConnectionMode)
        return HStack {
            ServiceIconView(service: occurrence.meeting.service, size: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(occurrence.meeting.name)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

#Preview {
    MenuBarContentView()
        .environment(MeetingStore())
        .environment(AppSettingsStore())
}
