import Foundation

/// Периодически удаляет прошедшие разовые встречи с включённым
/// автоудалением (см. `MeetingStore.deleteExpiredOneTimeMeetings`).
///
/// Отдельный маленький компонент, а не часть `AutoJoinRuntime` или
/// `NotificationService`: у автоудаления своя ответственность и свой ритм.
/// Раз в минуту достаточно — удаление через час после начала не требует
/// секундной точности. После sleep/wake первая же итерация цикла удалит
/// всё, что истекло, пока Mac спал.
///
/// Задача живёт независимо от главного окна — как и `AutoJoinRuntime`,
/// продолжает работать после его закрытия.
@MainActor
final class OneTimeMeetingCleaner {
    private var tickTask: Task<Void, Never>?

    func start(store: MeetingStore) {
        tickTask?.cancel()
        tickTask = Task {
            while !Task.isCancelled {
                store.deleteExpiredOneTimeMeetings()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }
}
