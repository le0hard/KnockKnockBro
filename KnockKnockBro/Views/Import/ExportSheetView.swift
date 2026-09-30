import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Окно экспорта (v0.6.0): что положить в файл.
///
/// - Встречи — галочкой каждую (по умолчанию все). Вместе с выбранной
///   встречей экспортируются и её отметки по дням (пропуск, отмена
///   автоподключения, "подключился").
/// - Настройки приложения — одной галочкой, со списком значений.
///
/// После "Экспортировать…" открывается стандартное окно сохранения.
struct ExportSheetView: View {
    @Environment(MeetingStore.self) private var store
    @Environment(AppSettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var selectedIDs: Set<UUID>?
    @State private var includesSettings = true
    @State private var errorMessage: String?

    /// Пока пользователь ничего не менял — выбраны все встречи.
    private var selection: Set<UUID> {
        selectedIDs ?? Set(store.meetings.map(\.id))
    }

    private var snapshot: AppSettingsSnapshot {
        // "Требует подтверждения" в системе тоже считается включённым.
        settings.snapshot(launchAtLogin: LoginItemService.currentStatus != .disabled)
    }

    private var canExport: Bool {
        !selection.isEmpty || includesSettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Экспорт")
                .font(.title2.bold())
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
                Button("Отмена") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Экспортировать…") { performExport() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canExport)
            }
            .padding(16)
        }
        .frame(width: 580, height: 600)
    }

    // MARK: - Встречи

    @ViewBuilder
    private var meetingsSection: some View {
        Section {
            if store.meetings.isEmpty {
                Text("Встреч пока нет.")
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Button("Выбрать все") { selectedIDs = Set(store.meetings.map(\.id)) }
                    Button("Снять все") { selectedIDs = [] }
                    Spacer()
                    Text("Выбрано: \(selection.count) из \(store.meetings.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.link)

                ForEach(store.meetings) { meeting in
                    Toggle(isOn: Binding(
                        get: { selection.contains(meeting.id) },
                        set: { isOn in
                            var updated = selection
                            if isOn { updated.insert(meeting.id) } else { updated.remove(meeting.id) }
                            selectedIDs = updated
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
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
        } header: {
            Text("Встречи")
        } footer: {
            Text("Вместе со встречей сохраняются её отметки по дням: пропуск, отмена автоподключения, «подключился».")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Настройки

    private var settingsSection: some View {
        let current = snapshot
        return Section("Настройки приложения") {
            Toggle("Экспортировать настройки", isOn: $includesSettings)
            if includesSettings {
                LabeledContent("Отсчёт автоподключения", value: "\(Int(current.defaultAutoJoinCountdown)) сек")
                LabeledContent("Яндекс Телемост", value: current.telemostConnectionMode.displayName)
                LabeledContent("Засчитывать подключение", value: "за \(current.joinCountingWindowMinutes) мин до начала")
                LabeledContent("Показывать в строке меню", value: current.showInMenuBar ? "Да" : "Нет")
                LabeledContent("Открывать окно при запуске", value: current.openMainWindowOnLaunch ? "Да" : "Нет")
                LabeledContent("Запускать при входе в macOS", value: current.launchAtLogin ? "Да" : "Нет")
            }
        }
    }

    // MARK: - Сохранение

    private func performExport() {
        let ids = selection
        do {
            let data = try ImportExportService.export(
                meetings: store.meetings.filter { ids.contains($0.id) },
                exceptions: store.exceptions.filter { ids.contains($0.meetingID) },
                settings: includesSettings ? snapshot : nil
            )
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "KnockKnockBro-\(Self.fileDateFormatter.string(from: Date())).json"
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
            dismiss()
        } catch {
            errorMessage = "Не удалось экспортировать данные: \(error.localizedDescription)"
        }
    }

    /// "2026-09-30" для имени файла.
    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
