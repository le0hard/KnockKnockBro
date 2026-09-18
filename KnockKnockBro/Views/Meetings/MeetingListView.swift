import SwiftUI

/// Раздел sidebar главного окна.
private enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case today, allMeetings, quickRooms

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Сегодня"
        case .allMeetings: return "Все встречи"
        case .quickRooms: return "Быстрый доступ"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "calendar"
        case .allMeetings: return "list.bullet"
        case .quickRooms: return "bolt.fill"
        }
    }
}

/// Главный экран приложения: sidebar-навигация между "Сегодня", "Все
/// встречи" и "Быстрый доступ".
struct MeetingListView: View {
    @Environment(MeetingStore.self) private var store
    @Environment(AppSettingsStore.self) private var settings
    @Environment(\.openSettings) private var openSettings

    @State private var selection: SidebarSection? = .today
    @State private var isCreatingMeeting = false
    @State private var editingMeeting: Meeting?
    @State private var meetingPendingDeletion: Meeting?
    @State private var copiedMeetingID: UUID?

    private var scheduledMeetings: [Meeting] {
        store.meetings
            .filter { $0.type == .scheduled }
            .sorted { lhs, rhs in
                let lhsMinutes = (lhs.schedule?.hour ?? 0) * 60 + (lhs.schedule?.minute ?? 0)
                let rhsMinutes = (rhs.schedule?.hour ?? 0) * 60 + (rhs.schedule?.minute ?? 0)
                return lhsMinutes < rhsMinutes
            }
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
            .navigationTitle("KnockKnockBro")
        } detail: {
            detailContent
                .navigationTitle(selection?.title ?? "KnockKnockBro")
                .toolbar {
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
                primaryEmptyText: "Тишина в календаре. Свободный день."
            )
        case .allMeetings:
            combinedList(
                primary: scheduledMeetings,
                primaryEmptyText: "Тишина в календаре. Нажмите «Новая встреча», чтобы это исправить."
            )
        case .quickRooms:
            List {
                if quickRooms.isEmpty {
                    Text("Постоянных комнат/ссылок пока нет.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(quickRooms) { meeting in
                        meetingRow(for: meeting)
                    }
                }
            }
        case nil:
            ContentUnavailableView("Выберите раздел", systemImage: "sidebar.left")
        }
    }

    private func combinedList(primary: [Meeting], primaryEmptyText: String) -> some View {
        List {
            Section {
                if primary.isEmpty {
                    Text(primaryEmptyText)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(primary) { meeting in
                        meetingRow(for: meeting)
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

    private func meetingRow(for meeting: Meeting) -> some View {
        MeetingRow(
            meeting: meeting,
            didCopy: copiedMeetingID == meeting.id,
            hasOccurrenceToday: hasOccurrenceToday(meeting),
            isSkippedToday: store.isSkipped(meetingID: meeting.id),
            isAutoJoinCancelledToday: store.isAutoJoinCancelled(meetingID: meeting.id),
            connectOptions: MeetingLauncher.connectOptions(for: meeting, telemostMode: settings.telemostConnectionMode),
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
        case .allMeetings: return scheduledMeetings.count
        case .quickRooms: return quickRooms.count
        }
    }

    private func copy(_ meeting: Meeting) {
        MeetingLauncher.copyURL(meeting.url)
        copiedMeetingID = meeting.id

        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedMeetingID == meeting.id {
                copiedMeetingID = nil
            }
        }
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
    let didCopy: Bool
    let hasOccurrenceToday: Bool
    let isSkippedToday: Bool
    let isAutoJoinCancelledToday: Bool
    /// Одна или две кнопки подключения — вторая появляется только для
    /// встреч Яндекс Телемоста в режиме "оба варианта", когда десктопное
    /// приложение доступно (см. `MeetingLauncher.connectOptions`).
    let connectOptions: [MeetingLauncher.ConnectOption]
    let onCopy: () -> Void
    let onToggleEnabled: (Bool) -> Void
    let onToggleSkipToday: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            ServiceIconView(service: meeting.service, size: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.name)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(didCopy ? "Скопировано" : "Копировать ссылку", action: onCopy)
                .buttonStyle(.bordered)

            ForEach(connectOptions) { option in
                ConnectOptionButton(
                    option: option,
                    isPrimary: option.id == connectOptions.first?.id,
                    isEnabled: meeting.enabled
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
            parts.append(scheduleDescription(schedule))
        }
        if isSkippedToday {
            parts.append("пропущена сегодня")
        } else if isAutoJoinCancelledToday && (meeting.autoJoin?.isEnabled ?? false) {
            parts.append("автоподключение отменено сегодня")
        }
        return parts.joined(separator: " · ")
    }

    private func scheduleDescription(_ schedule: MeetingSchedule) -> String {
        let time = String(format: "%02d:%02d", schedule.hour, schedule.minute)
        let recurrence: String
        switch schedule.recurrence {
        case .daily:
            recurrence = "каждый день"
        case .weekdays:
            recurrence = "по будням"
        case .weekly(let day):
            recurrence = "еженедельно, \(day.shortDisplayName)"
        case .customDays(let days):
            recurrence = days.sorted().map(\.shortDisplayName).joined(separator: ", ")
        }
        return "\(time) · \(recurrence)"
    }
}

/// Одна кнопка подключения. Вынесена в отдельный View, а не тернарный
/// оператор внутри `.buttonStyle(...)`, — `.borderedProminent` и `.bordered`
/// разные конкретные типы, и унификация через тернарный оператор в общем
/// generic-параметре заставляла компилятор превышать разумное время
/// проверки типов ("unable to type-check in reasonable time").
private struct ConnectOptionButton: View {
    let option: MeetingLauncher.ConnectOption
    let isPrimary: Bool
    let isEnabled: Bool

    var body: some View {
        Group {
            if isPrimary {
                Button(option.title) {
                    MeetingLauncher.open(option.url)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(option.title) {
                    MeetingLauncher.open(option.url)
                }
                .buttonStyle(.bordered)
            }
        }
        .disabled(!isEnabled)
    }
}

#Preview {
    MeetingListView()
        .environment(MeetingStore())
        .environment(AppSettingsStore())
        .frame(width: 760, height: 480)
}
