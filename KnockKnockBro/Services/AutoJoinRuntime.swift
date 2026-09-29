import Foundation

/// Управляет жизненным циклом Auto Join: раз в секунду проверяет, не пора
/// ли показать countdown-панель для какой-то встречи, и выполняет
/// автоматическое подключение по достижении нуля.
///
/// Панель показывает 1 или 2 кнопки подключения — те же
/// `MeetingLauncher.connectOptions`, что видит пользователь в главном
/// окне и попапе Menu Bar, — чтобы выбор режима Телемоста (Desktop/Web/
/// оба) был согласован везде одинаково, включая ручной клик по кнопке
/// внутри самой countdown-панели, а не только автоматическое открытие
/// по истечении таймера.
@MainActor
final class AutoJoinRuntime {
    private let panelController = AutoJoinPanelController()
    private var tickTask: Task<Void, Never>?

    private var activeOccurrence: MeetingOccurrence?
    private var triggeredOccurrenceIDs: [String: Date] = [:]

    private var meetingsProvider: (() -> [Meeting])?
    private var exceptionsProvider: (() -> [MeetingOccurrenceException])?
    private var defaultCountdownProvider: (() -> TimeInterval)?
    private var telemostModeProvider: (() -> TelemostConnectionMode)?
    private var onCancelRequested: ((UUID, Date) -> Void)?
    private var onJoined: ((UUID, Date) -> Void)?

    func start(
        meetingsProvider: @escaping () -> [Meeting],
        exceptionsProvider: @escaping () -> [MeetingOccurrenceException],
        defaultCountdownProvider: @escaping () -> TimeInterval,
        telemostModeProvider: @escaping () -> TelemostConnectionMode,
        onCancelRequested: @escaping (UUID, Date) -> Void,
        onJoined: @escaping (UUID, Date) -> Void
    ) {
        self.meetingsProvider = meetingsProvider
        self.exceptionsProvider = exceptionsProvider
        self.defaultCountdownProvider = defaultCountdownProvider
        self.telemostModeProvider = telemostModeProvider
        self.onCancelRequested = onCancelRequested
        self.onJoined = onJoined

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
            // Пользователь уже подключился другим способом (попап, главное
            // окно, уведомление) — отсчёт больше не нужен, и открывать
            // ссылку второй раз нельзя.
            let isJoinedElsewhere = exceptionsProvider?().contains {
                $0.joined && $0.matches(meetingID: occurrence.meeting.id, date: occurrence.startDate)
            } ?? false
            if isJoinedElsewhere {
                dismissPanel()
            } else if now >= occurrence.startDate {
                openPreferredURL(for: occurrence.meeting)
                onJoined?(occurrence.meeting.id, occurrence.startDate)
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
        let telemostMode = telemostModeProvider?() ?? .both
        let connectOptions = MeetingLauncher.connectOptions(for: occurrence.meeting, telemostMode: telemostMode)

        activeOccurrence = occurrence
        triggeredOccurrenceIDs[occurrence.id] = now

        panelController.show(
            occurrence: occurrence,
            countdown: countdown,
            connectOptions: connectOptions,
            onJoinNow: { [weak self] url in
                MeetingLauncher.open(url)
                self?.onJoined?(occurrence.meeting.id, occurrence.startDate)
                self?.dismissPanel()
            },
            onAlreadyJoined: { [weak self] in
                // "Я уже на встрече": ссылку не открываем, только отмечаем.
                self?.onJoined?(occurrence.meeting.id, occurrence.startDate)
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

    /// Открывает встречу при автоматическом срабатывании таймера (истечении
    /// countdown, без явного нажатия пользователем) — берётся первая
    /// (приоритетная) опция из `connectOptions`, та же логика, что и для
    /// ручного клика по первой кнопке в панели.
    private func openPreferredURL(for meeting: Meeting) {
        let telemostMode = telemostModeProvider?() ?? .both
        let options = MeetingLauncher.connectOptions(for: meeting, telemostMode: telemostMode)
        if let primary = options.first {
            MeetingLauncher.open(primary.url)
        } else {
            MeetingLauncher.open(meeting.url)
        }
    }

    private func purgeOldTriggeredIDs(now: Date) {
        let cutoff = now.addingTimeInterval(-24 * 60 * 60)
        triggeredOccurrenceIDs = triggeredOccurrenceIDs.filter { $0.value > cutoff }
    }
}
