import Foundation

/// Управляет жизненным циклом Auto Join: раз в секунду проверяет, не пора
/// ли показать countdown-панель для какой-то встречи, и выполняет
/// автоматическое подключение по достижении нуля.
///
/// Держит `AutoJoinPanelController` (независимую NSPanel) и делегирует ей
/// сам показ; вся логика "когда" и "какую встречу" приходит из чистого,
/// протестированного отдельно `AutoJoinService`.
///
/// Периодическая проверка реализована через `Task`-цикл с
/// `Task.sleep`, создаваемый внутри уже `@MainActor`-метода — такой `Task`
/// автоматически наследует изоляцию актора, в отличие от
/// `Timer.scheduledTimer`, чьё замыкание не изолировано к `@MainActor` и
/// требовало бы обходных путей для безопасного вызова `tick()`.
@MainActor
final class AutoJoinRuntime {
    private let panelController = AutoJoinPanelController()
    private var tickTask: Task<Void, Never>?

    private var activeOccurrence: MeetingOccurrence?
    private var triggeredOccurrenceIDs: [String: Date] = [:]

    private var meetingsProvider: (() -> [Meeting])?
    private var exceptionsProvider: (() -> [MeetingOccurrenceException])?
    private var defaultCountdownProvider: (() -> TimeInterval)?
    private var onCancelRequested: ((UUID, Date) -> Void)?

    /// Начинает опрос раз в секунду. Вызывается один раз при старте
    /// приложения; работает всё время жизни процесса, независимо от
    /// состояния главного окна.
    func start(
        meetingsProvider: @escaping () -> [Meeting],
        exceptionsProvider: @escaping () -> [MeetingOccurrenceException],
        defaultCountdownProvider: @escaping () -> TimeInterval,
        onCancelRequested: @escaping (UUID, Date) -> Void
    ) {
        self.meetingsProvider = meetingsProvider
        self.exceptionsProvider = exceptionsProvider
        self.defaultCountdownProvider = defaultCountdownProvider
        self.onCancelRequested = onCancelRequested

        tickTask?.cancel()
        tickTask = Task {
            while !Task.isCancelled {
                tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func tick() {
        let now = Date()
        purgeOldTriggeredIDs(now: now)

        if let occurrence = activeOccurrence {
            // Панель уже показана — только проверяем момент срабатывания;
            // сам отсчёт на экране панель считает независимо, по своему
            // собственному таймеру.
            if now >= occurrence.startDate {
                MeetingLauncher.open(occurrence.meeting.url)
                dismissPanel()
            }
            return
        }

        guard
            let meetingsProvider, let exceptionsProvider, let defaultCountdownProvider
        else { return }

        let defaultCountdown = defaultCountdownProvider()

        guard let occurrence = AutoJoinService.occurrenceToTrigger(
            meetings: meetingsProvider(),
            exceptions: exceptionsProvider(),
            defaultCountdown: defaultCountdown,
            alreadyTriggeredOccurrenceIDs: Set(triggeredOccurrenceIDs.keys),
            now: now
        ) else { return }

        let countdown = AutoJoinService.resolvedCountdown(for: occurrence.meeting, defaultCountdown: defaultCountdown)
        activeOccurrence = occurrence
        triggeredOccurrenceIDs[occurrence.id] = now

        panelController.show(
            occurrence: occurrence,
            countdown: countdown,
            onJoinNow: { [weak self] in
                MeetingLauncher.open(occurrence.meeting.url)
                self?.dismissPanel()
            },
            onCancel: { [weak self] in
                self?.onCancelRequested?(occurrence.meeting.id, occurrence.startDate)
                self?.dismissPanel()
            }
        )
    }

    private func dismissPanel() {
        panelController.hide()
        activeOccurrence = nil
    }

    /// Не даёт `triggeredOccurrenceIDs` расти неограниченно за долгое
    /// время работы приложения — записи старше суток удаляются, так как
    /// `MeetingOccurrence.id` привязан к конкретному календарному дню и
    /// не может повториться для того же дня.
    private func purgeOldTriggeredIDs(now: Date) {
        let cutoff = now.addingTimeInterval(-24 * 60 * 60)
        triggeredOccurrenceIDs = triggeredOccurrenceIDs.filter { $0.value > cutoff }
    }
}
