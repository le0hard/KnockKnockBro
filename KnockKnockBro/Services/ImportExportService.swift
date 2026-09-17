import Foundation

/// Конкретная причина, по которой импортируемый JSON был отклонён.
/// Каждый случай несёт текст, понятный человеку, а не разработчику —
/// показывается прямо в UI.
enum ImportValidationError: Error, Equatable {
    case malformedJSON
    case unsupportedFormatVersion(found: Int, supported: Int)
    case invalidURL(meetingName: String)
    case missingScheduleForScheduledMeeting(meetingName: String)
    case invalidScheduleTime(meetingName: String)
    case emptyCustomDaysRecurrence(meetingName: String)
    case duplicateMeetingID(meetingName: String)
    case exceptionReferencesUnknownMeeting

    var localizedDescription: String {
        switch self {
        case .malformedJSON:
            return "Файл повреждён или не является корректным JSON."
        case .unsupportedFormatVersion(let found, let supported):
            return "Неподдерживаемая версия формата (\(found)). KnockKnockBro поддерживает версию \(supported)."
        case .invalidURL(let meetingName):
            return "Некорректная ссылка у встречи «\(meetingName)»."
        case .missingScheduleForScheduledMeeting(let meetingName):
            return "У запланированной встречи «\(meetingName)» отсутствует расписание."
        case .invalidScheduleTime(let meetingName):
            return "Некорректное время начала у встречи «\(meetingName)»."
        case .emptyCustomDaysRecurrence(let meetingName):
            return "У встречи «\(meetingName)» не выбран ни один день недели для повторения."
        case .duplicateMeetingID(let meetingName):
            return "В файле дважды встречается одна и та же встреча «\(meetingName)» (совпадающий идентификатор)."
        case .exceptionReferencesUnknownMeeting:
            return "Файл содержит исключение расписания, не относящееся ни к одной из встреч в этом же файле."
        }
    }
}

/// Результат успешной валидации — данные, готовые к применению через
/// `MeetingStore.replaceAll`.
struct ValidatedImport {
    let meetings: [Meeting]
    let exceptions: [MeetingOccurrenceException]
}

/// Экспорт текущей конфигурации в человекочитаемый JSON и строгая,
/// многоступенчатая валидация импортируемого JSON.
///
/// Использует тот же тип `StorageFile`, что `MeetingStore` пишет на диск —
/// формат хранения и формат экспорта совпадают, что избавляет от
/// необходимости поддерживать два независимых представления одних и тех
/// же данных.
///
/// `validate` — ЧИСТАЯ функция: она ничего не записывает в `MeetingStore`
/// и не имеет иных побочных эффектов. Применение импортированных данных —
/// отдельный, следующий шаг, который вызывающий код (UI) выполняет только
/// после успешного получения `ValidatedImport`. Это прямая реализация
/// требования "весь импортируемый JSON сначала полностью валидируется" —
/// невозможно случайно применить часть данных до завершения проверки.
struct ImportExportService {

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    /// Сериализует текущее состояние в человекочитаемый JSON.
    static func export(meetings: [Meeting], exceptions: [MeetingOccurrenceException]) throws -> Data {
        let file = StorageFile(
            formatVersion: MeetingStore.currentFormatVersion,
            meetings: meetings,
            exceptions: exceptions
        )
        return try encoder.encode(file)
    }

    /// Полностью валидирует импортируемый JSON, ничего не изменяя в
    /// текущих данных приложения. Возвращает провалидированные данные при
    /// успехе или конкретную причину отказа.
    static func validate(data: Data) -> Result<ValidatedImport, ImportValidationError> {
        let file: StorageFile
        do {
            file = try decoder.decode(StorageFile.self, from: data)
        } catch {
            return .failure(.malformedJSON)
        }

        guard file.formatVersion == MeetingStore.currentFormatVersion else {
            return .failure(.unsupportedFormatVersion(found: file.formatVersion, supported: MeetingStore.currentFormatVersion))
        }

        var seenIDs = Set<UUID>()
        for meeting in file.meetings {
            if seenIDs.contains(meeting.id) {
                return .failure(.duplicateMeetingID(meetingName: meeting.name))
            }
            seenIDs.insert(meeting.id)

            guard meeting.url.scheme != nil, meeting.url.host != nil else {
                return .failure(.invalidURL(meetingName: meeting.name))
            }

            if meeting.type == .scheduled {
                guard let schedule = meeting.schedule else {
                    return .failure(.missingScheduleForScheduledMeeting(meetingName: meeting.name))
                }
                guard (0...23).contains(schedule.hour), (0...59).contains(schedule.minute) else {
                    return .failure(.invalidScheduleTime(meetingName: meeting.name))
                }
                if case .customDays(let days) = schedule.recurrence, days.isEmpty {
                    return .failure(.emptyCustomDaysRecurrence(meetingName: meeting.name))
                }
            }
        }

        let knownMeetingIDs = seenIDs
        for exception in file.exceptions {
            guard knownMeetingIDs.contains(exception.meetingID) else {
                return .failure(.exceptionReferencesUnknownMeeting)
            }
        }

        return .success(ValidatedImport(meetings: file.meetings, exceptions: file.exceptions))
    }
}
