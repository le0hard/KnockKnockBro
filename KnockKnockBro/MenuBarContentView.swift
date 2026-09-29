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
    /// Строка, для которой только что скопировали название и ссылку —
    /// значок на ~1,5 с меняется на галочку.
    @State private var copiedRowID: String?

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
        // Блок "Следующая встреча" — только для СЕГОДНЯШНЕЙ встречи. Если
        // сегодня встреч больше нет, а следующая только завтра, блок не
        // показывается вовсе (как и отсчёт в строке меню).
        let nextOccurrence = UpcomingMeetingsProvider.nextOccurrenceToday(
            meetings: store.meetings, exceptions: store.exceptions, now: now, calendar: calendar
        )
        let remainingTodayOccurrences = todayOccurrences.filter { $0.id != nextOccurrence?.id }
        let quickRooms = store.meetings.filter { $0.type == .quickRoom && $0.enabled }

        VStack(alignment: .leading, spacing: 0) {
            // Шапка — приглушённая подпись "KnockKnockBro 0.5.0", как
            // заголовок у системных меню: не читается как кликабельный пункт.
            HStack {
                Text(Self.headerTitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    openCalendarWindow()
                } label: {
                    Image(systemName: "calendar")
                        .font(.body)
                }
                .buttonStyle(PopupIconButtonStyle())
                .help("Календарь")
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .padding(.top, 8)
            .padding(.bottom, 6)

            if let nextOccurrence {
                Divider()
                sectionHeader("Следующая встреча · Сегодня")
                occurrenceRow(nextOccurrence, now: now, showsSkipButton: true)
            }

            if !remainingTodayOccurrences.isEmpty {
                Divider()
                sectionHeader("Сегодня")
                ForEach(remainingTodayOccurrences) { occurrence in
                    occurrenceRow(occurrence, now: now)
                }
            } else if todayOccurrences.isEmpty {
                Divider()
                Text("Сегодня встреч нет")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }

            if !quickRooms.isEmpty {
                Divider()
                sectionHeader("Быстрый доступ")
                ForEach(quickRooms) { meeting in
                    quickRoomRow(meeting)
                }
            }

            Divider()

            VStack(spacing: 0) {
                Button {
                    openMainWindow()
                } label: {
                    Label("Открыть KnockKnockBro", systemImage: "macwindow")
                }

                Button {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("Настройки", systemImage: "gearshape")
                }
            }
            .buttonStyle(PopupMenuItemButtonStyle())
            .padding(.vertical, 4)

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Выйти", systemImage: "power")
            }
            .buttonStyle(PopupMenuItemButtonStyle())
            .padding(.top, 4)
            .padding(.bottom, 8)
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

    /// Строка запланированной встречи: слева выровненная колонка времени
    /// (крупное HH:MM и под ним — сколько осталось/прошло), затем иконка
    /// сервиса, название и кнопки подключения.
    ///
    /// - Название уже начавшейся встречи зачёркнуто (время — нет).
    /// - `showsSkipButton` — кнопка "Пропустить" (только у блока
    ///   "Следующая встреча"): тот же "Пропустить сегодня", что в главном
    ///   окне; отменить можно там же.
    private func occurrenceRow(_ occurrence: MeetingOccurrence, now: Date, showsSkipButton: Bool = false) -> some View {
        let connectOptions = MeetingLauncher.connectOptions(for: occurrence.meeting, telemostMode: settings.telemostConnectionMode)
        let hasStarted = occurrence.startDate <= now
        let isJoined = store.isJoined(meetingID: occurrence.meeting.id, on: occurrence.startDate)
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
                .pastMeetingNameStyle(hasStarted)
                .lineLimit(2)
            if isJoined {
                JoinedBadge()
            }
            Spacer(minLength: 8)
            copyButton(rowID: occurrence.id) {
                MeetingLauncher.copyShareText(for: occurrence.meeting, startDate: occurrence.startDate)
            }
            if showsSkipButton && !isJoined {
                Button("Пропустить") {
                    store.toggleSkip(meetingID: occurrence.meeting.id, on: occurrence.startDate)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Пропустить эту встречу сегодня. Отменить можно в главном окне.")
            }
            ForEach(connectOptions) { option in
                ConnectOptionButton(
                    title: option.title,
                    isPrimary: !isJoined && option.id == connectOptions.first?.id,
                    iconSystemName: option.systemImage,
                    action: {
                        MeetingLauncher.open(option.url)
                        store.recordJoinIfEligible(
                            meeting: occurrence.meeting,
                            occurrenceStart: occurrence.startDate,
                            windowMinutes: settings.joinCountingWindowMinutes
                        )
                    }
                )
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        .popupRowHoverHighlight()
    }

    /// Маленькая кнопка-значок "Копировать название и ссылку". После
    /// нажатия значок на 1,5 секунды становится галочкой.
    private func copyButton(rowID: String, copy: @escaping () -> Void) -> some View {
        let didCopy = copiedRowID == rowID
        return Button {
            copy()
            copiedRowID = rowID
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                if copiedRowID == rowID {
                    copiedRowID = nil
                }
            }
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .font(.callout)
        }
        .buttonStyle(PopupIconButtonStyle())
        .help(didCopy ? "Скопировано" : "Копировать название и ссылку")
    }

    private func quickRoomRow(_ meeting: Meeting) -> some View {
        let connectOptions = MeetingLauncher.connectOptions(for: meeting, telemostMode: settings.telemostConnectionMode)
        return HStack {
            ServiceIconView(service: meeting.service, size: 22)
            Text(meeting.name)
                .font(.headline)
            Spacer()
            copyButton(rowID: meeting.id.uuidString) {
                MeetingLauncher.copyShareText(for: meeting)
            }
            ForEach(connectOptions) { option in
                ConnectOptionButton(
                    title: option.title,
                    isPrimary: option.id == connectOptions.first?.id,
                    iconSystemName: option.systemImage,
                    action: { MeetingLauncher.open(option.url) }
                )
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        .popupRowHoverHighlight()
    }

    /// "KnockKnockBro 0.5.0" — версия из Info.plist (Marketing Version).
    private static let headerTitle: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return ["KnockKnockBro", version].compactMap { $0 }.joined(separator: " ")
    }()

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
