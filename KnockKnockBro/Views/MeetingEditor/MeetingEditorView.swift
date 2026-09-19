import SwiftUI
import AppKit
import Foundation

/// Форма создания и редактирования встречи.
///
/// Используется и для Quick Room, и для Scheduled Meeting — переключение
/// типа встречи прямо в форме показывает/скрывает поля расписания,
/// напоминаний и Auto Join, которые осмысленны только для Scheduled.
struct MeetingEditorView: View {
    @Environment(MeetingStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let editingMeetingID: UUID?

    @State private var name: String
    @State private var urlText: String
    @State private var meetingType: MeetingType
    @State private var enabled: Bool
    @State private var hour: Int
    @State private var minute: Int
    @State private var recurrenceKind: RecurrenceKind
    @State private var weeklyDay: Weekday
    @State private var customDays: Set<Weekday>
    @State private var reminders: [MeetingReminder]
    @State private var autoJoinEnabled: Bool
    @State private var autoJoinCountdownOption: CountdownOption
    @State private var customCountdownSeconds: String
    @State private var validationError: String?

    /// Создание новой встречи.
    init() {
        editingMeetingID = nil
        _name = State(initialValue: "")
        _urlText = State(initialValue: "")
        _meetingType = State(initialValue: .quickRoom)
        _enabled = State(initialValue: true)
        _hour = State(initialValue: 10)
        _minute = State(initialValue: 0)
        _recurrenceKind = State(initialValue: .daily)
        _weeklyDay = State(initialValue: .monday)
        _customDays = State(initialValue: [])
        _reminders = State(initialValue: [])
        _autoJoinEnabled = State(initialValue: false)
        _autoJoinCountdownOption = State(initialValue: .useDefault)
        _customCountdownSeconds = State(initialValue: "")
        _validationError = State(initialValue: nil)
    }

    /// Редактирование существующей встречи.
    init(editing meeting: Meeting) {
        editingMeetingID = meeting.id
        _name = State(initialValue: meeting.name)
        _urlText = State(initialValue: meeting.url.absoluteString)
        _meetingType = State(initialValue: meeting.type)
        _enabled = State(initialValue: meeting.enabled)
        _hour = State(initialValue: meeting.schedule?.hour ?? 10)
        _minute = State(initialValue: meeting.schedule?.minute ?? 0)
        _reminders = State(initialValue: meeting.reminders)
        _validationError = State(initialValue: nil)

        if let recurrence = meeting.schedule?.recurrence {
            switch recurrence {
            case .daily:
                _recurrenceKind = State(initialValue: .daily)
                _weeklyDay = State(initialValue: .monday)
                _customDays = State(initialValue: [])
            case .weekdays:
                _recurrenceKind = State(initialValue: .weekdays)
                _weeklyDay = State(initialValue: .monday)
                _customDays = State(initialValue: [])
            case .weekly(let day):
                _recurrenceKind = State(initialValue: .weekly)
                _weeklyDay = State(initialValue: day)
                _customDays = State(initialValue: [])
            case .customDays(let days):
                _recurrenceKind = State(initialValue: .customDays)
                _weeklyDay = State(initialValue: .monday)
                _customDays = State(initialValue: days)
            }
        } else {
            _recurrenceKind = State(initialValue: .daily)
            _weeklyDay = State(initialValue: .monday)
            _customDays = State(initialValue: [])
        }

        _autoJoinEnabled = State(initialValue: meeting.autoJoin?.isEnabled ?? false)

        if let override = meeting.autoJoin?.countdownOverride {
            if let preset = CountdownOption.presets.first(where: { $0.seconds == override }) {
                _autoJoinCountdownOption = State(initialValue: preset)
                _customCountdownSeconds = State(initialValue: "")
            } else {
                _autoJoinCountdownOption = State(initialValue: .custom)
                _customCountdownSeconds = State(initialValue: String(Int(override)))
            }
        } else {
            _autoJoinCountdownOption = State(initialValue: .useDefault)
            _customCountdownSeconds = State(initialValue: "")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(editingMeetingID == nil ? "Новая встреча" : "Редактирование встречи")
                    .font(.title2.bold())
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 4)

            Form {
                Section("Основное") {
                    TextField("Название", text: $name)

                    HStack {
                        TextField("https://...", text: $urlText)
                            .autocorrectionDisabled()

                        Button {
                            if let clipboardString = NSPasteboard.general.string(forType: .string) {
                                urlText = clipboardString
                            }
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                        }
                        .buttonStyle(.plain)
                        .help("Вставить ссылку из буфера обмена")
                    }

                    if let service = detectedService {
                        HStack(spacing: 8) {
                            ServiceIconView(service: service, size: 20)
                            Text(service.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle("Включена", isOn: $enabled)
                }

                Section("Тип встречи") {
                    Picker("Тип", selection: $meetingType) {
                        Text("Быстрый доступ").tag(MeetingType.quickRoom)
                        Text("Запланированная").tag(MeetingType.scheduled)
                    }
                    .pickerStyle(.segmented)
                }

                if meetingType == .scheduled {
                    Section("Расписание") {
                        DatePicker("Время", selection: timeBinding, displayedComponents: .hourAndMinute)

                        Picker("Повторение", selection: $recurrenceKind) {
                            ForEach(RecurrenceKind.allCases) { kind in
                                Text(kind.displayName).tag(kind)
                            }
                        }

                        if recurrenceKind == .weekly {
                            Picker("День недели", selection: $weeklyDay) {
                                ForEach(Weekday.mondayFirstOrder) { day in
                                    Text(day.shortDisplayName).tag(day)
                                }
                            }
                        }

                        if recurrenceKind == .customDays {
                            WeekdaySelector(selectedDays: $customDays)
                        }
                    }

                    Section("Напоминания") {
                        if reminders.isEmpty {
                            Text("Напоминаний нет")
                                .foregroundStyle(.secondary)
                        }

                        ForEach(reminders) { reminder in
                            ReminderRow(
                                reminder: bindingForReminder(id: reminder.id),
                                onDelete: { reminders.removeAll { $0.id == reminder.id } }
                            )
                        }

                        Button {
                            reminders.append(MeetingReminder(offsetBeforeStart: 15 * 60))
                        } label: {
                            Label("Добавить напоминание", systemImage: "plus")
                        }
                    }

                    Section("Автоподключение") {
                        Toggle("Автоматически подключаться", isOn: $autoJoinEnabled)

                        if autoJoinEnabled {
                            Picker("Отсчёт перед подключением", selection: $autoJoinCountdownOption) {
                                Text("По умолчанию").tag(CountdownOption.useDefault)
                                ForEach(CountdownOption.presets) { preset in
                                    Text(preset.displayName).tag(preset)
                                }
                                Text("Другое").tag(CountdownOption.custom)
                            }

                            if autoJoinCountdownOption == .custom {
                                LabeledContent("Секунд") {
                                    TextField("", text: $customCountdownSeconds)
                                        .frame(width: 60)
                                        .multilineTextAlignment(.trailing)
                                }
                            }
                        }
                    }
                }

                if let validationError {
                    Section {
                        Text(validationError)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Отмена") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Сохранить") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 480)
    }

    // MARK: - Derived state

    private var detectedService: MeetingService? {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.host != nil else { return nil }
        return MeetingProviderDetector.detectService(from: url)
    }

    private var timeBinding: Binding<Date> {
        Binding<Date>(
            get: {
                var components = DateComponents()
                components.hour = hour
                components.minute = minute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                hour = components.hour ?? hour
                minute = components.minute ?? minute
            }
        )
    }

    private func bindingForReminder(id: UUID) -> Binding<MeetingReminder> {
        Binding<MeetingReminder>(
            get: {
                reminders.first(where: { $0.id == id }) ?? MeetingReminder(offsetBeforeStart: 0)
            },
            set: { newValue in
                if let index = reminders.firstIndex(where: { $0.id == id }) {
                    reminders[index] = newValue
                }
            }
        )
    }

    // MARK: - Saving

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationError = "Введите название встречи"
            return
        }

        let trimmedURLText = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURLText), url.scheme != nil, url.host != nil else {
            validationError = "Введите корректную ссылку, например https://..."
            return
        }

        let service = MeetingProviderDetector.detectService(from: url)

        var schedule: MeetingSchedule?
        var resolvedReminders: [MeetingReminder] = []
        var autoJoin: AutoJoinSettings?

        if meetingType == .scheduled {
            let recurrence: Recurrence
            switch recurrenceKind {
            case .daily:
                recurrence = .daily
            case .weekdays:
                recurrence = .weekdays
            case .weekly:
                recurrence = .weekly(weeklyDay)
            case .customDays:
                guard !customDays.isEmpty else {
                    validationError = "Выберите хотя бы один день недели"
                    return
                }
                recurrence = .customDays(customDays)
            }

            schedule = MeetingSchedule(hour: hour, minute: minute, recurrence: recurrence)
            resolvedReminders = reminders

            if autoJoinEnabled {
                var countdownOverride: TimeInterval?
                switch autoJoinCountdownOption {
                case .useDefault:
                    countdownOverride = nil
                case .preset(let seconds):
                    countdownOverride = seconds
                case .custom:
                    let trimmedSeconds = customCountdownSeconds.trimmingCharacters(in: .whitespaces)
                    guard let seconds = TimeInterval(trimmedSeconds), seconds > 0 else {
                        validationError = "Введите корректное количество секунд"
                        return
                    }
                    countdownOverride = seconds
                }
                autoJoin = AutoJoinSettings(isEnabled: true, countdownOverride: countdownOverride)
            } else {
                autoJoin = AutoJoinSettings(isEnabled: false, countdownOverride: nil)
            }
        }

        let meeting = Meeting(
            id: editingMeetingID ?? UUID(),
            name: trimmedName,
            url: url,
            service: service,
            type: meetingType,
            enabled: enabled,
            schedule: schedule,
            reminders: resolvedReminders,
            autoJoin: autoJoin
        )

        if editingMeetingID != nil {
            store.update(meeting)
        } else {
            store.add(meeting)
        }

        dismiss()
    }
}

// MARK: - Recurrence kind (UI-only discriminator)

private enum RecurrenceKind: String, CaseIterable, Identifiable {
    case daily, weekdays, weekly, customDays

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .daily: return "Каждый день"
        case .weekdays: return "По будням"
        case .weekly: return "Еженедельно"
        case .customDays: return "Выбранные дни"
        }
    }
}

// MARK: - Auto Join countdown option (UI-only discriminator)

private enum CountdownOption: Hashable, Identifiable {
    case useDefault
    case preset(TimeInterval)
    case custom

    static let presets: [CountdownOption] = [.preset(5), .preset(10), .preset(15), .preset(30), .preset(60)]

    var id: String {
        switch self {
        case .useDefault: return "default"
        case .preset(let seconds): return "preset-\(seconds)"
        case .custom: return "custom"
        }
    }

    var seconds: TimeInterval? {
        if case .preset(let seconds) = self { return seconds }
        return nil
    }

    var displayName: String {
        switch self {
        case .useDefault: return "По умолчанию"
        case .preset(let seconds): return "\(Int(seconds)) секунд"
        case .custom: return "Другое"
        }
    }
}

// MARK: - Weekday multi-select control

private struct WeekdaySelector: View {
    @Binding var selectedDays: Set<Weekday>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.mondayFirstOrder) { day in
                let isSelected = selectedDays.contains(day)
                Button {
                    if isSelected {
                        selectedDays.remove(day)
                    } else {
                        selectedDays.insert(day)
                    }
                } label: {
                    Text(day.shortDisplayName)
                        .frame(width: 36, height: 28)
                        .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Reminder row

private struct ReminderRow: View {
    @Binding var reminder: MeetingReminder
    let onDelete: () -> Void

    private var minutesBinding: Binding<Int> {
        Binding<Int>(
            get: { Int(reminder.offsetBeforeStart / 60) },
            set: { reminder.offsetBeforeStart = TimeInterval($0) * 60 }
        )
    }

    var body: some View {
        HStack {
            Stepper(value: minutesBinding, in: 0...180) {
                Text(minutesBinding.wrappedValue == 0 ? "В момент начала" : "За \(minutesBinding.wrappedValue) мин")
            }

            Spacer()

            Picker("", selection: $reminder.sound) {
                ForEach(NotificationSoundOption.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .labelsHidden()
            .frame(width: 160)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    MeetingEditorView()
        .environment(MeetingStore())
}
