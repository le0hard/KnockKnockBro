import SwiftUI

/// Раздел sidebar главного окна.
private enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case today, allMeetings, quickRooms, archive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Сегодня"
        case .allMeetings: return "Все встречи"
        case .quickRooms: return "Быстрый доступ"
        case .archive: return "Архив"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "calendar"
        case .allMeetings: return "list.bullet"
        case .quickRooms: return "bolt.fill"
        case .archive: return "archivebox"
        }
    }
}

/// Главный экран приложения: sidebar-навигация между "Сегодня", "Все
/// встречи" и "Быстрый доступ".
struct MeetingListView: View {
    @Environment(MeetingStore.self) private var store
    @Environment(AppSettingsStore.self) private var settings
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    @State private var selection: SidebarSection? = .today
    @State private var isCreatingMeeting = false
    @State private var editingMeeting: Meeting?
    @State private var meetingPendingDeletion: Meeting?
    @State private var copiedMeetingID: UUID?

    /// Все запланированные встречи: сначала повторяющиеся по времени
    /// начала, затем разовые по дате и времени.
    private var scheduledMeetings: [Meeting] {
        store.meetings
            .filter { $0.type == .scheduled }
            .sorted { sortKey(for: $0) < sortKey(for: $1) }
    }

    /// Запланированные встречи без прошедших разовых — основной список
    /// раздела "Все встречи".
    private var activeScheduledMeetings: [Meeting] {
        let now = Date()
        return scheduledMeetings.filter { !$0.isPastOneTimeMeeting(now: now) }
    }

    /// Разовые встречи, чей день уже прошёл, — раздел "Архив", от самой
    /// свежей к старой.
    private var pastOneTimeMeetings: [Meeting] {
        let now = Date()
        return Array(scheduledMeetings
            .filter { $0.isPastOneTimeMeeting(now: now) }
            .reversed())
    }

    private var todayMeetings: [Meeting] {
        scheduledMeetings.filter { hasOccurrenceToday($0) }
    }

    private var quickRooms: [Meeting] {
        store.meetings.filter { $0.type == .quickRoom }
    }

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .badge(count(for: section))
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle("KnockKnockBro")
        } detail: {
            detailContent
                .navigationTitle(selection?.title ?? "KnockKnockBro")
                .toolbar {
                    ToolbarItem {
                        Button {
                            CalendarWindow.show(using: openWindow)
                        } label: {
                            Label("Календарь", systemImage: "calendar")
                        }
                        .help("Календарь")
                    }
                    ToolbarItem {
                        Button {
                            isCreatingMeeting = true
                        } label: {
                            Label("Новая встреча", systemImage: "plus")
                        }
                    }
                    ToolbarItem {
                        Button {
                            openSettings()
                        } label: {
                            Label("Настройки", systemImage: "gearshape")
                        }
                    }
                }
        }
        .sheet(isPresented: $isCreatingMeeting) {
            MeetingEditorView()
                .environment(store)
        }
        .sheet(item: $editingMeeting) { meeting in
            MeetingEditorView(editing: meeting)
                .environment(store)
        }
        .alert(
            "Удалить встречу?",
            isPresented: Binding(
                get: { meetingPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented { meetingPendingDeletion = nil }
                }
            ),
            presenting: meetingPendingDeletion
        ) { meeting in
            Button("Удалить", role: .destructive) {
                store.delete(id: meeting.id)
                meetingPendingDeletion = nil
            }
            Button("Отмена", role: .cancel) {
                meetingPendingDeletion = nil
            }
        } message: { meeting in
            Text("«\(meeting.name)» будет удалена без возможности восстановления.")
        }
    }

    // MARK: - Detail content

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .today:
            combinedList(
                primary: todayMeetings,
                strikesRecurringStartedToday: true,
                emptyIcon: "calendar",
                emptyTitle: "Тишина в календаре",
                emptyDescription: "Свободный день."
            )
        case .allMeetings:
            combinedList(
                primary: activeScheduledMeetings,
                emptyIcon: "list.bullet",
                emptyTitle: "Тишина в календаре",
                emptyDescription: "Нажмите «Новая встреча», чтобы это исправить."
            )
        case .quickRooms:
            List {
                if quickRooms.isEmpty {
                    ContentUnavailableView(
                        "Постоянных комнат/ссылок пока нет.",
                        systemImage: "bolt.fill"
                    )
                } else {
                    ForEach(quickRooms) { meeting in
                        meetingRow(for: meeting)
                    }
                }
            }
        case .archive:
            List {
                if pastOneTimeMeetings.isEmpty {
                    ContentUnavailableView(
                        "Архив пуст",
                        systemImage: "archivebox",
                        description: Text("Здесь окажутся разовые встречи, когда их день пройдёт.")
                    )
                } else {
                    ForEach(pastOneTimeMeetings) { meeting in
                        meetingRow(for: meeting, isPast: true)
                    }
                }
            }
        case nil:
            ContentUnavailableView("Выберите раздел", systemImage: "sidebar.left")
        }
    }

    /// - Parameter strikesRecurringStartedToday: в разделе "Сегодня"
    ///   зачёркивается и повторяющаяся встреча, чей сегодняшний экземпляр
    ///   уже начался; в "Все встречи" повторяющиеся не зачёркиваются —
    ///   правило повторения не "проходит".
    private func combinedList(
        primary: [Meeting],
        strikesRecurringStartedToday: Bool = false,
        emptyIcon: String,
        emptyTitle: String,
        emptyDescription: String
    ) -> some View {
        List {
            Section {
                if primary.isEmpty {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: emptyIcon,
                        description: Text(emptyDescription)
                    )
                } else {
                    ForEach(primary) { meeting in
                        meetingRow(for: meeting, isPast: hasStarted(meeting, includingRecurringToday: strikesRecurringStartedToday))
                    }
                }
            }

            if !quickRooms.isEmpty {
                Section("Быстрый доступ") {
                    ForEach(quickRooms) { meeting in
                        meetingRow(for: meeting)
                    }
                }
            }
        }
    }

    private func meetingRow(for meeting: Meeting, isPast: Bool = false) -> some View {
        MeetingRow(
            meeting: meeting,
            isPast: isPast,
            didCopy: copiedMeetingID == meeting.id,
            hasOccurrenceToday: hasOccurrenceToday(meeting),
            isSkippedToday: store.isSkipped(meetingID: meeting.id),
            isAutoJoinCancelledToday: store.isAutoJoinCancelled(meetingID: meeting.id),
            isJoinedToday: store.isJoined(meetingID: meeting.id),
            shareStartDate: shareStartDate(for: meeting),
            connectOptions: MeetingLauncher.connectOptions(for: meeting, telemostMode: settings.telemostConnectionMode),
            onJoin: { url in
                MeetingLauncher.open(url)
                store.recordJoinIfEligible(meeting: meeting, windowMinutes: settings.joinCountingWindowMinutes)
            },
            onCopy: { copy(meeting) },
            onToggleEnabled: { store.setEnabled(id: meeting.id, enabled: $0) },
            onToggleSkipToday: { store.toggleSkip(meetingID: meeting.id) },
            onEdit: { editingMeeting = meeting },
            onDelete: { meetingPendingDeletion = meeting }
        )
    }

    private func count(for section: SidebarSection) -> Int {
        switch section {
        case .today: return todayMeetings.count
        case .allMeetings: return activeScheduledMeetings.count
        case .quickRooms: return quickRooms.count
        case .archive: return pastOneTimeMeetings.count
        }
    }

    /// Копирует название и ссылку — тот же текст, что и значок копирования
    /// в попапе. Для запланированной встречи в названии указывается время
    /// начала (у разовой — её собственное, у повторяющейся — время по
    /// расписанию).
    private func copy(_ meeting: Meeting) {
        MeetingLauncher.copyShareText(for: meeting, startDate: shareStartDate(for: meeting))
        copiedMeetingID = meeting.id

        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedMeetingID == meeting.id {
                copiedMeetingID = nil
            }
        }
    }

    /// Время начала для текста "название — время + ссылка": у разовой
    /// встречи — её собственное, у повторяющейся — время по расписанию
    /// (на сегодня), у Quick Room — нет.
    private func shareStartDate(for meeting: Meeting) -> Date? {
        meeting.oneTimeStartDate() ?? meeting.schedule.flatMap { schedule in
            Calendar.current.date(bySettingHour: schedule.hour, minute: schedule.minute, second: 0, of: Date())
        }
    }

    /// Ключ сортировки: повторяющиеся (0) — по минутам от начала суток,
    /// разовые (1) — по моменту начала.
    private func sortKey(for meeting: Meeting) -> (Int, Double) {
        if let start = meeting.oneTimeStartDate() {
            return (1, start.timeIntervalSinceReferenceDate)
        }
        let minutes = (meeting.schedule?.hour ?? 0) * 60 + (meeting.schedule?.minute ?? 0)
        return (0, Double(minutes))
    }

    /// Встреча уже началась: разовая — по своему моменту начала;
    /// повторяющаяся — только если `includingRecurringToday` и её
    /// сегодняшний экземпляр уже начался.
    private func hasStarted(_ meeting: Meeting, includingRecurringToday: Bool) -> Bool {
        let now = Date()
        if let start = meeting.oneTimeStartDate() {
            return start <= now
        }
        guard includingRecurringToday else { return false }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        return OccurrenceEngine.occurrences(for: meeting, in: DateInterval(start: dayStart, end: dayEnd), calendar: calendar)
            .contains { $0.startDate <= now }
    }

    private func hasOccurrenceToday(_ meeting: Meeting) -> Bool {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return false }
        let range = DateInterval(start: start, end: end)
        return !OccurrenceEngine.occurrences(for: meeting, in: range, calendar: calendar).isEmpty
    }
}

/// Одна строка списка встреч.
private struct MeetingRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let meeting: Meeting
    /// Встреча уже прошла/началась — название зачёркнуто (время в
    /// подзаголовке — нет).
    let isPast: Bool
    let didCopy: Bool
    let hasOccurrenceToday: Bool
    let isSkippedToday: Bool
    let isAutoJoinCancelledToday: Bool
    let isJoinedToday: Bool
    let shareStartDate: Date?
    let connectOptions: [MeetingLauncher.ConnectOption]
    let onJoin: (URL) -> Void
    let onCopy: () -> Void
    let onToggleEnabled: (Bool) -> Void
    let onToggleSkipToday: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            ServiceIconView(service: meeting.service, size: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(meeting.name)
                        .font(.headline)
                        .pastMeetingNameStyle(isPast)
                    if isJoinedToday {
                        JoinedBadge()
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(didCopy ? "Скопировано" : "Копировать", action: onCopy)
                .buttonStyle(.bordered)
                .help("Копировать название и ссылку")

            MeetingShareButton(meeting: meeting, startDate: shareStartDate)
                .buttonStyle(.bordered)

            ForEach(connectOptions) { option in
                ConnectOptionButton(
                    title: option.title,
                    isPrimary: !isJoinedToday && option.id == connectOptions.first?.id,
                    isEnabled: meeting.enabled,
                    action: { onJoin(option.url) }
                )
            }

            Toggle(
                "",
                isOn: Binding(
                    get: { meeting.enabled },
                    set: { onToggleEnabled($0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(10)
        .background(AppTheme.cardBackground(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onEdit()
        }
        .contextMenu {
            Button("Редактировать", action: onEdit)
            if hasOccurrenceToday {
                Button(isSkippedToday ? "Отменить пропуск сегодня" : "Пропустить сегодня", action: onToggleSkipToday)
            }
            Button("Удалить", role: .destructive, action: onDelete)
        }
    }

    private var subtitle: String {
        var parts: [String] = [meeting.service.displayName]
        if let schedule = meeting.schedule {
            parts.append(schedule.displayDescription)
        }
        if isJoinedToday {
            parts.append("подключились сегодня")
        } else if isSkippedToday {
            parts.append("пропущена сегодня")
        } else if isAutoJoinCancelledToday && (meeting.autoJoin?.isEnabled ?? false) {
            parts.append("автоподключение отменено сегодня")
        }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    MeetingListView()
        .environment(MeetingStore())
        .environment(AppSettingsStore())
        .frame(width: 760, height: 480)
}
