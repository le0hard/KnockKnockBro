import Foundation
import Observation

/// Контейнер на диске: версия формата + список встреч + исключения. Это
/// ровно то, что содержится в экспортном JSON (см. `ImportExportService`) —
/// хранение и экспорт используют один и тот же тип, чтобы не дублировать
/// формат в двух местах.
///
/// Ручной `Codable` (а не автосинтезированный) — чтобы файлы, сохранённые
/// ДО появления исключений, продолжали загружаться без ошибок:
/// отсутствующий ключ `exceptions` трактуется как пустой список, а не как
/// повод отклонить весь файл.
struct StorageFile: Codable {
    var formatVersion: Int
    var meetings: [Meeting]
    var exceptions: [MeetingOccurrenceException]

    private enum CodingKeys: String, CodingKey {
        case formatVersion, meetings, exceptions
    }

    init(formatVersion: Int, meetings: [Meeting], exceptions: [MeetingOccurrenceException]) {
        self.formatVersion = formatVersion
        self.meetings = meetings
        self.exceptions = exceptions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        meetings = try container.decode([Meeting].self, forKey: .meetings)
        exceptions = try container.decodeIfPresent([MeetingOccurrenceException].self, forKey: .exceptions) ?? []
    }
}

/// Единственный источник правды о списке встреч и их точечных исключениях.
///
/// UI, ScheduleService, NotificationService и остальные компоненты читают
/// данные ТОЛЬКО через этот класс и никогда напрямую не работают с файлом
/// на диске — это то, что позволяет держать UI/расписание/уведомления
/// логически разделёнными.
///
/// Хранение — единый человекочитаемый JSON-файл в Application Support,
/// версионированный полем `formatVersion`.
@Observable
final class MeetingStore {

    /// Текущая версия формата файла на диске и формата экспорта.
    static let currentFormatVersion = 1

    /// Текущий список встреч. UI наблюдает это свойство напрямую благодаря
    /// `@Observable` — без Combine-подписок.
    private(set) var meetings: [Meeting] = []

    /// Точечные исключения "Пропустить сегодня" / "Отменить автоподключение
    /// на сегодня". Хранятся ОТДЕЛЬНО от `Meeting.schedule`/`autoJoin` —
    /// это то, что позволяет отменить один конкретный день, не трогая само
    /// правило повторения или настройки Auto Join.
    private(set) var exceptions: [MeetingOccurrenceException] = []

    /// Заполняется, если последняя попытка загрузки с диска не удалась.
    /// UI может показать мягкое предупреждение, но приложение при этом
    /// не блокируется и продолжает работать с пустым списком встреч.
    private(set) var lastLoadError: String?

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// - Parameter fileURL: путь к файлу хранения. По умолчанию —
    ///   `Application Support/KnockKnockBro/meetings.json`. Параметр вынесен
    ///   наружу, чтобы тесты могли подставить временный файл и не трогать
    ///   реальные данные пользователя.
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()

        load()
    }

    // MARK: - Paths

    private static func defaultFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = appSupport.appendingPathComponent("KnockKnockBro", isDirectory: true)
        return directory.appendingPathComponent("meetings.json")
    }

    // MARK: - CRUD (meetings)

    /// Добавляет новую встречу.
    func add(_ meeting: Meeting) {
        meetings.append(meeting)
        persist()
    }

    /// Заменяет существующую встречу (по `id`) на обновлённую версию.
    /// Если встреча с таким `id` не найдена — вызов не имеет эффекта
    /// (это не должно происходить при нормальной работе UI, но безопасно
    /// игнорировать, а не крэшить приложение).
    func update(_ meeting: Meeting) {
        guard let index = meetings.firstIndex(where: { $0.id == meeting.id }) else { return }
        meetings[index] = meeting
        persist()
    }

    /// Удаляет встречу по `id`. Вместе со встречей удаляются и все её
    /// исключения (Skip Today и отмены Auto Join) — они бессмысленны без
    /// самой встречи и иначе накапливались бы как мусор в файле хранения.
    func delete(id: UUID) {
        meetings.removeAll { $0.id == id }
        exceptions.removeAll { $0.meetingID == id }
        persist()
    }

    /// Включает/выключает встречу. Отдельный метод (а не просто
    /// `update`) — потому что это самое частое действие пользователя
    /// (тумблер в UI), и явное имя делает вызывающий код понятнее.
    func setEnabled(id: UUID, enabled: Bool) {
        guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
        meetings[index].enabled = enabled
        persist()
    }

    /// Полностью заменяет список встреч и исключений — используется
    /// Import'ом ПОСЛЕ того, как весь входящий JSON уже полностью
    /// провалидирован `ImportExportService.validate`.
    func replaceAll(meetings newMeetings: [Meeting], exceptions newExceptions: [MeetingOccurrenceException] = []) {
        meetings = newMeetings
        exceptions = newExceptions
        persist()
    }

    // MARK: - Skip Today

    /// `true`, если для этой встречи на указанную дату установлено
    /// исключение "Пропустить сегодня".
    func isSkipped(meetingID: UUID, on date: Date = Date(), calendar: Calendar = .current) -> Bool {
        exceptions.contains { $0.isSkipped && $0.matches(meetingID: meetingID, date: date, calendar: calendar) }
    }

    /// Переключает "Пропустить сегодня" для встречи на указанную дату.
    ///
    /// Это НЕ трогает `Meeting.schedule` — исключение существует отдельно
    /// от правила повторения. Повторный вызов на ту же дату отменяет
    /// пропуск, возвращая обычное расписание в силу для этого дня.
    func toggleSkip(meetingID: UUID, on date: Date = Date(), calendar: Calendar = .current) {
        if let index = exceptions.firstIndex(where: { $0.matches(meetingID: meetingID, date: date, calendar: calendar) }) {
            exceptions.remove(at: index)
        } else {
            exceptions.append(MeetingOccurrenceException(meetingID: meetingID, date: date, isSkipped: true, calendar: calendar))
        }
        persist()
    }

    // MARK: - Auto Join cancellation

    /// `true`, если для этой встречи на указанную дату Auto Join был
    /// отменён (через кнопку "Отмена" на countdown-панели). Не означает,
    /// что вся встреча пропущена — её обычные уведомления (Join/Snooze)
    /// продолжают работать как обычно.
    func isAutoJoinCancelled(meetingID: UUID, on date: Date = Date(), calendar: Calendar = .current) -> Bool {
        exceptions.contains { $0.autoJoinCancelled && $0.matches(meetingID: meetingID, date: date, calendar: calendar) }
    }

    /// Отмечает Auto Join отменённым для встречи на указанную дату.
    ///
    /// Если для этой даты уже существует исключение (например, оно уже
    /// использовалось для Skip Today), просто добавляет к нему флаг
    /// `autoJoinCancelled`, не трогая `isSkipped` — это два независимых
    /// друг от друга флага одного и того же дня.
    func cancelAutoJoin(meetingID: UUID, on date: Date = Date(), calendar: Calendar = .current) {
        if let index = exceptions.firstIndex(where: { $0.matches(meetingID: meetingID, date: date, calendar: calendar) }) {
            exceptions[index].autoJoinCancelled = true
        } else {
            exceptions.append(MeetingOccurrenceException(meetingID: meetingID, date: date, autoJoinCancelled: true, calendar: calendar))
        }
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        do {
            let file = StorageFile(formatVersion: Self.currentFormatVersion, meetings: meetings, exceptions: exceptions)
            let data = try encoder.encode(file)
            try writeAtomically(data)
            lastLoadError = nil
        } catch {
            // Если запись не удалась (например, диск переполнен или нет
            // прав) — не теряем данные в памяти и не крэшим приложение.
            // Пользователь продолжает работать в рамках текущей сессии;
            // ошибка сохраняется, чтобы UI мог её показать.
            lastLoadError = "Не удалось сохранить данные: \(error.localizedDescription)"
        }
    }

    /// Атомарная запись: сначала во временный файл в той же директории,
    /// затем замена целевого файла одной файловой операцией. Это исключает
    /// ситуацию, когда процесс прерывается посередине записи и оставляет
    /// на диске повреждённый наполовину файл.
    private func writeAtomically(_ data: Data) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let tempURL = directory.appendingPathComponent(UUID().uuidString + ".tmp")
        try data.write(to: tempURL, options: .atomic)
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
    }

    /// Загрузка с диска при старте.
    ///
    /// Умышленно "мягкая": отсутствующий файл (первый запуск) — это не
    /// ошибка, а битый/нечитаемый файл не должен блокировать запуск —
    /// приложение продолжает работать с пустым списком, а причина
    /// сохраняется в `lastLoadError` для показа в UI. Это ОТДЕЛЬНАЯ логика
    /// от строгой валидации Import: здесь на кону не "защитить
    /// существующие данные от плохого файла", а "не убить приложение при
    /// старте".
    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            meetings = []
            exceptions = []
            lastLoadError = nil
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let file = try decoder.decode(StorageFile.self, from: data)
            meetings = file.meetings
            exceptions = file.exceptions
            lastLoadError = nil
        } catch {
            meetings = []
            exceptions = []
            lastLoadError = "Не удалось прочитать сохранённые данные: \(error.localizedDescription)"
        }
    }
}
