import SwiftUI

/// Окно импорта (v0.6.0): что именно взять из файла.
///
/// - Встречи — галочкой каждую (по умолчанию выбраны все), режим
///   "Объединить" (по умолчанию) или "Заменить всё". В режиме объединения
///   у каждой встречи виден её статус: новая / обновится / без изменений /
///   уже есть (дубликат — пропускается, галочка недоступна).
/// - Настройки приложения — одной галочкой, если они есть в файле.
///
/// Ничего не меняется, пока не нажата "Импортировать"; применение —
/// `ImportApplier`.
struct ImportSheetView: View {
    let pending: PendingImport

    @Environment(MeetingStore.self) private var store
    @Environment(AppSettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var importsMeetings: Bool
    @State private var mode: MeetingsImportMode = .merge
    @State private var selectedIDs: Set<UUID>
    @State private var importsSettings: Bool
    @State private var errorMessage: String?
    @State private var didApply = false

    init(pending: PendingImport) {
        self.pending = pending
        _importsMeetings = State(initialValue: !pending.validated.meetings.isEmpty)
        _selectedIDs = State(initialValue: Set(pending.validated.meetings.map(\.id)))
        _importsSettings = State(initialValue: pending.validated.settings != nil)
    }

    private var fileMeetings: [Meeting] { pending.validated.meetings }

    /// Выбранные встречи, которые действительно будут применены: в режиме
    /// объединения дубликаты пропускаются, даже если отмечены.
    private var effectiveSelection: Set<UUID> {
        guard mode == .merge else { return selectedIDs }
        return selectedIDs.filter { id in
            guard let meeting = fileMeetings.first(where: { $0.id == id }) else { return false }
            return status(of: meeting) != .duplicate
        }
    }

    private var canImport: Bool {
        let meetingsPart = importsMeetings && !effectiveSelection.isEmpty
        let settingsPart = importsSettings && pending.validated.settings != nil
        return meetingsPart || settingsPart
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Импорт")
                    .font(.title2.bold())
                Text(pending.fileName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 4)

            Form {
                meetingsSection
                settingsSection

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                if didApply {
                    Button("Закрыть") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Отмена") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Импортировать") { performImport() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canImport)
                }
            }
            .padding(16)
        }
        .frame(width: 580, height: 600)
    }

    // MARK: - Встречи

    @ViewBuilder
    private var meetingsSection: some View {
        Section {
            if fileMeetings.isEmpty {
                Text("В файле нет встреч.")
                    .foregroundStyle(.secondary)
            } else {
                Toggle("Импортировать встречи", isOn: $importsMeetings)

                if importsMeetings {
                    Picker("Режим", selection: $mode) {
                        Text("Объединить").tag(MeetingsImportMode.merge)
                        Text("Заменить всё").tag(MeetingsImportMode.replace)
                    }
                    .pickerStyle(.segmented)

                    Text(modeDescription)
                        .font(.caption)
                        .foregroundStyle(mode == .replace ? AnyShapeStyle(Color.orange) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Button("Выбрать все") { selectedIDs = Set(fileMeetings.map(\.id)) }
                        Button("Снять все") { selectedIDs = [] }
                        Spacer()
                        Text("Выбрано: \(effectiveSelection.count) из \(fileMeetings.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.link)

                    ForEach(fileMeetings) { meeting in
                        meetingRow(meeting)
                    }
                }
            }
        } header: {
            Text("Встречи")
        }
    }

    private var modeDescription: String {
        switch mode {
        case .merge:
            return "Выбранные встречи добавятся к вашим; встречи, которые уже есть (тот же идентификатор), обновятся. Остальные ваши встречи останутся без изменений."
        case .replace:
            return "Все текущие встречи (\(store.meetings.count)) будут удалены и заменены выбранными (\(effectiveSelection.count)). Это действие нельзя отменить."
        }
    }

    private func meetingRow(_ meeting: Meeting) -> some View {
        let meetingStatus = status(of: meeting)
        let isSkippedDuplicate = mode == .merge && meetingStatus == .duplicate

        return Toggle(isOn: Binding(
            get: { selectedIDs.contains(meeting.id) && !isSkippedDuplicate },
            set: { isOn in
                if isOn { selectedIDs.insert(meeting.id) } else { selectedIDs.remove(meeting.id) }
            }
        )) {
            HStack(spacing: 10) {
                ServiceIconView(service: meeting.service, size: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(meeting.name)
                    Text(meeting.summaryLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if mode == .merge {
                    statusBadge(meetingStatus)
                }
            }
        }
        .toggleStyle(.checkbox)
        .disabled(isSkippedDuplicate)
    }

    private func status(of meeting: Meeting) -> MergeStatus {
        ImportExportService.mergeStatus(of: meeting, currentMeetings: store.meetings)
    }

    private func statusBadge(_ status: MergeStatus) -> some View {
        let (title, color): (String, Color) = {
            switch status {
            case .added: return ("новая", .green)
            case .updated: return ("обновится", .orange)
            case .unchanged: return ("без изменений", .secondary)
            case .duplicate: return ("уже есть", .secondary)
            }
        }()
        return Text(title)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(color)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    // MARK: - Настройки

    @ViewBuilder
    private var settingsSection: some View {
        if let snapshot = pending.validated.settings {
            Section("Настройки приложения") {
                Toggle("Импортировать настройки", isOn: $importsSettings)
                if importsSettings {
                    LabeledContent("Отсчёт автоподключения", value: "\(Int(snapshot.defaultAutoJoinCountdown)) сек")
                    LabeledContent("Яндекс Телемост", value: snapshot.telemostConnectionMode.displayName)
                    LabeledContent("Засчитывать подключение", value: "за \(snapshot.joinCountingWindowMinutes) мин до начала")
                    LabeledContent("Показывать в строке меню", value: yesNo(snapshot.showInMenuBar))
                    LabeledContent("Открывать окно при запуске", value: yesNo(snapshot.openMainWindowOnLaunch))
                    LabeledContent("Запускать при входе в macOS", value: yesNo(snapshot.launchAtLogin))
                }
            }
        } else {
            Section("Настройки приложения") {
                Text("В файле нет настроек — они экспортируются начиная с KnockKnockBro 0.6.0.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func yesNo(_ value: Bool) -> String {
        value ? "Да" : "Нет"
    }

    // MARK: - Применение

    private func performImport() {
        let message = ImportApplier.apply(
            pending.validated,
            meetingIDs: importsMeetings ? effectiveSelection : nil,
            mode: mode,
            includeSettings: importsSettings,
            store: store,
            settings: settings
        )
        if let message {
            errorMessage = message
            didApply = true
        } else {
            dismiss()
        }
    }
}
