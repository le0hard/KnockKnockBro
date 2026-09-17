import Foundation

/// Встреча — центральная модель KnockKnockBro.
///
/// `schedule` и `autoJoin` осмысленны только при `type == .scheduled`;
/// для Quick Room они равны `nil`. Отдельные типы QuickRoom/ScheduledMeeting
/// дали бы более строгую гарантию на уровне компилятора, но для приложения
/// такого размера это усложнило бы CRUD, хранение и JSON-формат сильнее, чем
/// того стоит — поэтому здесь единая модель с опциональными полями, а
/// корректность соотношения type/schedule/autoJoin обеспечивается в местах
/// создания и валидации (MeetingEditor, ImportExportService).
struct Meeting: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var url: URL
    var service: MeetingService
    var type: MeetingType
    var enabled: Bool

    /// `nil` для Quick Room.
    var schedule: MeetingSchedule?
    /// Независимые напоминания. Пустой массив — уведомления не настроены.
    var reminders: [MeetingReminder]
    /// `nil` — автоподключение выключено/не применимо (Quick Room).
    var autoJoin: AutoJoinSettings?

    /// JSON-ключ `reminders` экспортируется как `notifications`, в точном
    /// соответствии со списком полей экспортного формата — при этом в коде
    /// сохраняется более понятное имя `reminders` (это напоминания, а не
    /// абстрактные "уведомления").
    private enum CodingKeys: String, CodingKey {
        case id, name, url, service, type, enabled, schedule, autoJoin
        case reminders = "notifications"
    }

    init(
        id: UUID = UUID(),
        name: String,
        url: URL,
        service: MeetingService,
        type: MeetingType,
        enabled: Bool = true,
        schedule: MeetingSchedule? = nil,
        reminders: [MeetingReminder] = [],
        autoJoin: AutoJoinSettings? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.service = service
        self.type = type
        self.enabled = enabled
        self.schedule = schedule
        self.reminders = reminders
        self.autoJoin = autoJoin
    }
}
