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
    case invalidOneTimeDate(meetingName: String)
    case emptyMeetingName
    case invalidReminder(meetingName: String)
    case invalidAutoJoinCountdown(meetingName: String)
    case invalidException
    case duplicateException
    case invalidSettings
    case duplicateMeetingID(meetingName: String)
    case exceptionReferencesUnknownMeeting

    var localizedDescription: String {
        switch self {
        case .malformedJSON:
            return "Файл повреждён или не является корректным JSON."
        case .unsupportedFormatVersion(let found, let supported):
            return "Неподдерживаемая версия формата (\(found)). Эта версия KnockKnockBro поддерживает форматы до \(supported) включительно."
        case .invalidURL(let meetingName):
            return "Некорректная ссылка у встречи «\(meetingName)»."
        case .missingScheduleForScheduledMeeting(let meetingName):
            return "У запланированной встречи «\(meetingName)» отсутствует расписание."
        case .invalidScheduleTime(let meetingName):
            return "Некорректное время начала у встречи «\(meetingName)»."
        case .emptyCustomDaysRecurrence(let meetingName):
            return "У встречи «\(meetingName)» не выбран ни один день недели для повторения."
        case .invalidOneTimeDate(let meetingName):
            return "У разовой встречи «\(meetingName)» указана несуществующая дата."
        case .emptyMeetingName:
            return "В файле есть встреча без названия."
        case .invalidReminder(let meetingName):
            return "Некорректное напоминание у встречи «\(meetingName)» (время до начала должно быть от 0 до 24 часов, без повторяющихся идентификаторов)."
        case .invalidAutoJoinCountdown(let meetingName):
            return "Некорректный отсчёт автоподключения у встречи «\(meetingName)» (от 1 секунды до часа)."
        case .invalidException:
            return "Файл содержит отметку расписания с несуществующей датой."
        case .duplicateException:
            return "Файл содержит повторяющиеся отметки расписания (один и тот же день одной встречи или одинаковый идентификатор)."
        case .invalidSettings:
            return "Некорректные значения в настройках приложения (отсчёт автоподключения — от 1 секунды до часа, окно засчитывания подключения — от 0 до 120 минут)."
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
    /// Настройки приложения из файла (формат 3+); `nil` — в файле их нет.
    let settings: AppSettingsSnapshot?
}

/// Режим применения импортированных встреч (v0.6.0).
enum MeetingsImportMode: Hashable {
    /// Все текущие встречи заменяются встречами из файла.
    case replace
    /// Встречи из файла добавляются к текущим: совпадающие по ID
    /// обновляются, точные дубликаты с другим ID пропускаются, остальные
    /// текущие встречи остаются как есть.
    case merge
}

/// Статус одной встречи из файла при объединении.
enum MergeStatus: Equatable {
    /// Новая — будет добавлена.
    case added
    /// Тот же ID, другое содержимое — будет обновлена.
    case updated
    /// Тот же ID и то же содержимое.
    case unchanged
    /// Другой ID, но такая встреча уже есть — будет пропущена.
    case duplicate
}

/// Что изменит объединение — для сводки в диалоге импорта.
struct MergeSummary: Equatable {
    /// Новые встречи, которых ещё нет.
    var added = 0
    /// Встречи с тем же ID, но другим содержимым — будут обновлены.
    var updated = 0
    /// Встречи с тем же ID и тем же содержимым — без изменений.
    var unchanged = 0
    /// Встречи с другим ID, но совпадающие с существующими по названию,
    /// ссылке, типу и расписанию — пропускаются как дубликаты.
    var skippedDuplicates = 0
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
    /// - Parameter settings: настройки приложения (формат 3); `nil` — без
    ///   блока настроек.
    static func export(
        meetings: [Meeting],
        exceptions: [MeetingOccurrenceException],
        settings: AppSettingsSnapshot? = nil
    ) throws -> Data {
        let file = StorageFile(
            formatVersion: MeetingStore.currentFormatVersion,
            meetings: meetings,
            exceptions: exceptions,
            settings: settings
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

        guard MeetingStore.supportedFormatVersions.contains(file.formatVersion) else {
            return .failure(.unsupportedFormatVersion(found: file.formatVersion, supported: MeetingStore.currentFormatVersion))
        }

        var seenIDs = Set<UUID>()
        for meeting in file.meetings {
            if seenIDs.contains(meeting.id) {
                return .failure(.duplicateMeetingID(meetingName: meeting.name))
            }
            seenIDs.insert(meeting.id)

            guard !meeting.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.emptyMeetingName)
            }

            guard meeting.url.scheme != nil, meeting.url.host != nil else {
                return .failure(.invalidURL(meetingName: meeting.name))
            }

            var reminderIDs = Set<UUID>()
            for reminder in meeting.reminders {
                guard reminderOffsetRange.contains(reminder.offsetBeforeStart),
                      reminderIDs.insert(reminder.id).inserted
                else {
                    return .failure(.invalidReminder(meetingName: meeting.name))
                }
            }

            if let countdown = meeting.autoJoin?.countdownOverride,
               !AppSettingsSnapshot.countdownRange.contains(countdown) {
                return .failure(.invalidAutoJoinCountdown(meetingName: meeting.name))
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
                if case .once(let day, _) = schedule.recurrence, !day.isValid() {
                    return .failure(.invalidOneTimeDate(meetingName: meeting.name))
                }
            }
        }

        let knownMeetingIDs = seenIDs
        var exceptionIDs = Set<UUID>()
        var exceptionDays = Set<String>()
        for exception in file.exceptions {
            guard knownMeetingIDs.contains(exception.meetingID) else {
                return .failure(.exceptionReferencesUnknownMeeting)
            }
            guard CalendarDay(year: exception.year, month: exception.month, day: exception.day).isValid() else {
                return .failure(.invalidException)
            }
            // Хранилище рассчитывает на одну отметку на встречу и день
            // (`firstIndex(where:)` в Skip Today / Auto Join / joined) —
            // две отметки одного дня сделали бы поведение непредсказуемым.
            let dayKey = "\(exception.meetingID.uuidString)|\(exception.year)-\(exception.month)-\(exception.day)"
            guard exceptionIDs.insert(exception.id).inserted,
                  exceptionDays.insert(dayKey).inserted
            else {
                return .failure(.duplicateException)
            }
        }

        if let settings = file.settings, !settings.isValid {
            return .failure(.invalidSettings)
        }

        return .success(ValidatedImport(meetings: file.meetings, exceptions: file.exceptions, settings: file.settings))
    }

    /// Допустимое время напоминания до начала встречи — от 0 до суток.
    static let reminderOffsetRange: ClosedRange<TimeInterval> = 0...(24 * 60 * 60)

    // MARK: - Объединение (v0.6.0)

    /// Результат объединения текущих данных с импортированными.
    ///
    /// - Встреча с тем же ID заменяется версией из файла, вместе со своими
    ///   отметками по дням (отметки из файла заменяют текущие отметки этой
    ///   встречи).
    /// - Встреча с новым ID добавляется — если только она не точный
    ///   дубликат существующей (см. `isDuplicate`), тогда пропускается
    ///   вместе со своими отметками.
    /// - Текущие встречи, которых нет в файле, остаются как есть.
    static func merged(
        currentMeetings: [Meeting],
        currentExceptions: [MeetingOccurrenceException],
        imported: ValidatedImport
    ) -> (meetings: [Meeting], exceptions: [MeetingOccurrenceException]) {
        var meetings = currentMeetings
        var appliedIDs = Set<UUID>()

        for meeting in imported.meetings {
            if let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
                meetings[index] = meeting
                appliedIDs.insert(meeting.id)
            } else if !currentMeetings.contains(where: { isDuplicate($0, of: meeting) }) {
                meetings.append(meeting)
                appliedIDs.insert(meeting.id)
            }
        }

        var exceptions = currentExceptions.filter { !appliedIDs.contains($0.meetingID) }
        exceptions += imported.exceptions.filter { appliedIDs.contains($0.meetingID) }
        return (meetings, exceptions)
    }

    /// Сводка для диалога: что сделает `merged`.
    static func mergeSummary(currentMeetings: [Meeting], imported: ValidatedImport) -> MergeSummary {
        var summary = MergeSummary()
        for meeting in imported.meetings {
            switch mergeStatus(of: meeting, currentMeetings: currentMeetings) {
            case .added: summary.added += 1
            case .updated: summary.updated += 1
            case .unchanged: summary.unchanged += 1
            case .duplicate: summary.skippedDuplicates += 1
            }
        }
        return summary
    }

    /// Что случится с одной встречей из файла при объединении.
    static func mergeStatus(of meeting: Meeting, currentMeetings: [Meeting]) -> MergeStatus {
        if let existing = currentMeetings.first(where: { $0.id == meeting.id }) {
            return existing == meeting ? .unchanged : .updated
        }
        if currentMeetings.contains(where: { isDuplicate($0, of: meeting) }) {
            return .duplicate
        }
        return .added
    }

    /// Только выбранные в диалоге встречи — вместе со своими отметками.
    static func filtered(_ imported: ValidatedImport, keepingMeetingIDs ids: Set<UUID>) -> ValidatedImport {
        ValidatedImport(
            meetings: imported.meetings.filter { ids.contains($0.id) },
            exceptions: imported.exceptions.filter { ids.contains($0.meetingID) },
            settings: imported.settings
        )
    }

    /// Две встречи с РАЗНЫМИ ID считаются дубликатами, если совпадают
    /// название (без учёта регистра и пробелов по краям), ссылка, тип и
    /// расписание — например, одну и ту же встречу создали вручную на двух
    /// Mac, а потом объединили экспорт.
    static func isDuplicate(_ lhs: Meeting, of rhs: Meeting) -> Bool {
        lhs.id != rhs.id
            && normalizedName(lhs.name) == normalizedName(rhs.name)
            && lhs.url == rhs.url
            && lhs.type == rhs.type
            && lhs.schedule == rhs.schedule
    }

    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
