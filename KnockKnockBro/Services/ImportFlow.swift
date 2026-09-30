import Foundation

/// Загруженный и полностью проверенный файл импорта, ожидающий
/// подтверждения пользователя в `ImportSheetView`.
struct PendingImport: Identifiable {
    let id = UUID()
    let fileName: String
    let validated: ValidatedImport

    /// Читает и проверяет файл. Ничего не меняет в данных приложения —
    /// применение идёт только после подтверждения (`ImportApplier`).
    static func load(from url: URL) -> Result<PendingImport, ImportLoadFailure> {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .failure(ImportLoadFailure(message: "Не удалось прочитать файл: \(error.localizedDescription)"))
        }
        switch ImportExportService.validate(data: data) {
        case .success(let validated):
            return .success(PendingImport(fileName: url.lastPathComponent, validated: validated))
        case .failure(let error):
            return .failure(ImportLoadFailure(message: error.localizedDescription))
        }
    }
}

/// Понятная пользователю причина, по которой файл нельзя импортировать.
struct ImportLoadFailure: Error {
    let message: String
}

/// Применяет подтверждённый импорт — единая точка для главного окна и
/// Настроек (раньше каждое место делало `replaceAll` само).
@MainActor
enum ImportApplier {

    /// - Parameters:
    ///   - meetingIDs: выбранные встречи из файла; `nil` — встречи не
    ///     импортировать вовсе.
    ///   - includeSettings: применить настройки приложения из файла
    ///     (включая автозапуск при входе).
    /// - Returns: сообщение об ошибке, если что-то применить не удалось
    ///   (на практике — только автозапуск: его может запретить система);
    ///   `nil` — всё применено.
    static func apply(
        _ imported: ValidatedImport,
        meetingIDs: Set<UUID>?,
        mode: MeetingsImportMode,
        includeSettings: Bool,
        store: MeetingStore,
        settings: AppSettingsStore
    ) -> String? {
        if let meetingIDs {
            let chosen = ImportExportService.filtered(imported, keepingMeetingIDs: meetingIDs)
            switch mode {
            case .replace:
                store.replaceAll(meetings: chosen.meetings, exceptions: chosen.exceptions)
            case .merge:
                let result = ImportExportService.merged(
                    currentMeetings: store.meetings,
                    currentExceptions: store.exceptions,
                    imported: chosen
                )
                store.replaceAll(meetings: result.meetings, exceptions: result.exceptions)
            }
        }

        if includeSettings, let snapshot = imported.settings {
            settings.apply(snapshot)
            do {
                try LoginItemService.setEnabled(snapshot.launchAtLogin)
            } catch {
                return "Данные импортированы, но изменить автозапуск при входе не удалось: \(error.localizedDescription)"
            }
        }
        return nil
    }
}
