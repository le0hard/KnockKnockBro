import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Категория настроек — левая колонка Settings, в паттерне System Settings.
private enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case general, autoJoin, videoServices, importExport

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Общие"
        case .autoJoin: return "Автоподключение"
        case .videoServices: return "Сервисы видеосвязи"
        case .importExport: return "Импорт / Экспорт"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape.fill"
        case .autoJoin: return "bolt.fill"
        case .videoServices: return "video.fill"
        case .importExport: return "arrow.up.arrow.down.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: return .gray
        case .autoJoin: return .orange
        case .videoServices: return .green
        case .importExport: return .blue
        }
    }
}

/// Цветной квадрат-иконка категории.
private struct SettingsCategoryIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(tint.gradient)
            .frame(width: 26, height: 26)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
            }
    }
}

/// Экран настроек KnockKnockBro — sidebar-навигация между категориями.
struct SettingsView: View {
    @Environment(AppSettingsStore.self) private var settings
    @Environment(MeetingStore.self) private var store
    @Environment(UpdateChecker.self) private var updateChecker

    @State private var selectedCategory: SettingsCategory? = .general

    @State private var loginItemStatus: LoginItemService.Status = LoginItemService.currentStatus
    @State private var loginItemError: String?

    @State private var isShowingExport = false
    @State private var pendingImport: PendingImport?
    @State private var importErrorMessage: String?
    @State private var isDropTargeted = false

    private static let countdownPresets: [TimeInterval] = [5, 10, 15, 30, 60]

    /// "0.6.0 (7)".
    private static let installedVersion: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }()

    var body: some View {
        NavigationSplitView {
            List(SettingsCategory.allCases, selection: $selectedCategory) { category in
                Label {
                    Text(category.title)
                } icon: {
                    SettingsCategoryIcon(systemImage: category.systemImage, tint: category.tint)
                }
                .tag(category)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            categoryContent
                .navigationTitle(selectedCategory?.title ?? "Настройки")
        }
        .frame(minWidth: 620, idealWidth: 620, minHeight: 420, idealHeight: 420)
        // Автоматическая проверка обновлений — только здесь, при открытии
        // Настроек (не при запуске приложения), и не чаще раза в сутки.
        .task {
            await updateChecker.checkIfNeeded()
        }
        .sheet(isPresented: $isShowingExport) {
            ExportSheetView()
                .environment(store)
                .environment(settings)
        }
        .sheet(item: $pendingImport, onDismiss: {
            // Импорт мог включить/выключить автозапуск — обновляем тумблер.
            loginItemStatus = LoginItemService.currentStatus
        }) { pending in
            ImportSheetView(pending: pending)
                .environment(store)
                .environment(settings)
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

    @ViewBuilder
    private var categoryContent: some View {
        switch selectedCategory {
        case .general:
            generalSettings
        case .autoJoin:
            autoJoinSettings
        case .videoServices:
            videoServicesSettings
        case .importExport:
            importExportSettings
        case nil:
            ContentUnavailableView("Выберите раздел", systemImage: "gearshape")
        }
    }

    private var generalSettings: some View {
        Form {
            Section("Запуск") {
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
            }

            Section("Интерфейс") {
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

            Section("Обновления") {
                LabeledContent("Установлена версия", value: Self.installedVersion)
                UpdateStatusView()
                Text("KnockKnockBro сам проверяет новую версию на GitHub при открытии настроек, не чаще раза в день. О вас ничего не отправляется, а скачать обновление можно со страницы релиза.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private var autoJoinSettings: some View {
        Form {
            Section {
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

            Section("Учёт подключения") {
                Stepper(
                    value: Binding(
                        get: { settings.joinCountingWindowMinutes },
                        set: { settings.joinCountingWindowMinutes = $0 }
                    ),
                    in: 0...120,
                    step: 5
                ) {
                    Text("Засчитывать подключение за \(settings.joinCountingWindowMinutes) мин до начала")
                }
                Text("Нажатие «Подключиться» в этом окне и позже, до конца дня, отмечает встречу как «уже подключился»: автоподключение, оставшиеся напоминания и вопрос после пробуждения для неё больше не появятся. Более раннее нажатие просто открывает ссылку.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private var videoServicesSettings: some View {
        Form {
            Section("Яндекс Телемост") {
                Picker(
                    "Режим подключения",
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
        }
        .formStyle(.grouped)
    }

    private var importExportSettings: some View {
        Form {
            Section {
                Button("Экспортировать в JSON…") {
                    isShowingExport = true
                }
                Button("Импортировать из файла") {
                    importFromFile()
                }
                Text("При экспорте и импорте можно выбрать, какие встречи взять и нужно ли переносить настройки приложения.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
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

    private func importFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        handleImportFile(at: url)
    }

    private func handleImportFile(at url: URL) {
        switch PendingImport.load(from: url) {
        case .success(let pending):
            pendingImport = pending
        case .failure(let failure):
            importErrorMessage = failure.message
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppSettingsStore())
        .environment(UpdateChecker())
        .environment(MeetingStore())
}
