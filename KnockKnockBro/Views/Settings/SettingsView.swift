import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Экран настроек KnockKnockBro, открываемый через нативную SwiftUI
/// `Settings` сцену.
struct SettingsView: View {
    @Environment(AppSettingsStore.self) private var settings
    @Environment(MeetingStore.self) private var store

    @State private var loginItemStatus: LoginItemService.Status = LoginItemService.currentStatus
    @State private var loginItemError: String?

    @State private var exportErrorMessage: String?
    @State private var pendingImport: ValidatedImport?
    @State private var existingMeetingsCountAtImportStart = 0
    @State private var importErrorMessage: String?
    @State private var isDropTargeted = false

    private static let countdownPresets: [TimeInterval] = [5, 10, 15, 30, 60]

    var body: some View {
        Form {
            Section("Общие") {
                Toggle(isOn: Binding(
                    get: { loginItemStatus == .enabled || loginItemStatus == .requiresApproval },
                    set: { toggleLoginItem($0) }
                )) {
                    Text("Запускать KnockKnockBro при входе в macOS")
                        .fixedSize(horizontal: false, vertical: true)
                }
                if loginItemStatus == .requiresApproval {
                    Text("Подтвердите автозапуск в системных Настройках → Основные → Элементы входа.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle(isOn: Binding(
                    get: { settings.showInMenuBar },
                    set: { settings.showInMenuBar = $0 }
                )) {
                    Text("Показывать KnockKnockBro в строке меню")
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle(isOn: Binding(
                    get: { settings.openMainWindowOnLaunch },
                    set: { settings.openMainWindowOnLaunch = $0 }
                )) {
                    Text("Открывать главное окно при запуске")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Автоподключение") {
                Picker(
                    "Отсчёт по умолчанию",
                    selection: Binding(
                        get: { settings.defaultAutoJoinCountdown },
                        set: { settings.defaultAutoJoinCountdown = $0 }
                    )
                ) {
                    ForEach(Self.countdownPresets, id: \.self) { seconds in
                        Text("\(Int(seconds)) секунд").tag(seconds)
                    }
                }
                Text("Применяется ко всем встречам, у которых не задано собственное значение отсчёта.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Сервисы видеосвязи") {
                Picker(
                    "Яндекс Телемост",
                    selection: Binding(
                        get: { settings.telemostConnectionMode },
                        set: { settings.telemostConnectionMode = $0 }
                    )
                ) {
                    ForEach(TelemostConnectionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            Section("Импорт / Экспорт") {
                Button("Экспортировать в JSON") {
                    exportToFile()
                }
                Button("Импортировать из файла") {
                    importFromFile()
                }
                if let exportErrorMessage {
                    Text(exportErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
                    .frame(height: 56)
                    .overlay {
                        Text("Перетащите JSON файл сюда")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .dropDestination(for: URL.self) { urls, _ in
                        guard let url = urls.first(where: { $0.pathExtension.lowercased() == "json" }) else {
                            importErrorMessage = "Перетащите файл в формате .json."
                            return false
                        }
                        handleImportFile(at: url)
                        return true
                    } isTargeted: { targeted in
                        isDropTargeted = targeted
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog(
            "Импортировать встречи?",
            isPresented: Binding(
                get: { pendingImport != nil },
                set: { isPresented in if !isPresented { pendingImport = nil } }
            ),
            presenting: pendingImport
        ) { validated in
            Button("Импортировать", role: .destructive) {
                store.replaceAll(meetings: validated.meetings, exceptions: validated.exceptions)
                pendingImport = nil
            }
            Button("Отмена", role: .cancel) { pendingImport = nil }
        } message: { validated in
            Text("Текущие \(existingMeetingsCountAtImportStart) встреч(и) будут заменены на \(validated.meetings.count) из файла. Это действие нельзя отменить.")
        }
        .alert(
            "Не удалось импортировать файл",
            isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { isPresented in if !isPresented { importErrorMessage = nil } }
            )
        ) {
            Button("ОК", role: .cancel) { importErrorMessage = nil }
        } message: {
            Text(importErrorMessage ?? "")
        }
    }

    private func toggleLoginItem(_ enabled: Bool) {
        do {
            try LoginItemService.setEnabled(enabled)
            loginItemStatus = LoginItemService.currentStatus
            loginItemError = nil
        } catch {
            loginItemError = "Не удалось изменить автозапуск: \(error.localizedDescription)"
            loginItemStatus = LoginItemService.currentStatus
        }
    }

    private func exportToFile() {
        do {
            let data = try ImportExportService.export(meetings: store.meetings, exceptions: store.exceptions)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "KnockKnockBro-Export.json"
            panel.canCreateDirectories = true
            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url, options: .atomic)
                exportErrorMessage = nil
            }
        } catch {
            exportErrorMessage = "Не удалось экспортировать данные: \(error.localizedDescription)"
        }
    }

    private func importFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        handleImportFile(at: url)
    }

    private func handleImportFile(at url: URL) {
        do {
            let data = try Data(contentsOf: url)
            switch ImportExportService.validate(data: data) {
            case .success(let validated):
                existingMeetingsCountAtImportStart = store.meetings.count
                pendingImport = validated
            case .failure(let error):
                importErrorMessage = error.localizedDescription
            }
        } catch {
            importErrorMessage = "Не удалось прочитать файл: \(error.localizedDescription)"
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppSettingsStore())
        .environment(MeetingStore())
}
