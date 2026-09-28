import SwiftUI

@main
struct KnockKnockBroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var meetingStore = MeetingStore()
    @State private var notificationService: NotificationService
    @State private var wakeObserver = WakeObserver()
    @State private var appSettingsStore: AppSettingsStore
    @State private var autoJoinRuntime = AutoJoinRuntime()
    @State private var oneTimeMeetingCleaner = OneTimeMeetingCleaner()
    @State private var isShowingAbout = false

    init() {
        let settingsStore = AppSettingsStore()
        _appSettingsStore = State(initialValue: settingsStore)
        _notificationService = State(initialValue: NotificationService(
            telemostModeProvider: { settingsStore.telemostConnectionMode }
        ))
        appDelegate.shouldOpenMainWindowOnLaunch = { settingsStore.openMainWindowOnLaunch }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(meetingStore)
                .environment(appSettingsStore)
                .task {
                    await notificationService.requestAuthorizationIfNeeded()
                    notificationService.rescheduleAll(for: meetingStore.meetings, exceptions: meetingStore.exceptions)
                    wakeObserver.startObserving(
                        meetingsProvider: { meetingStore.meetings },
                        exceptionsProvider: { meetingStore.exceptions },
                        onWake: {
                            notificationService.rescheduleAll(for: meetingStore.meetings, exceptions: meetingStore.exceptions)
                        }
                    )
                    autoJoinRuntime.start(
                        meetingsProvider: { meetingStore.meetings },
                        exceptionsProvider: { meetingStore.exceptions },
                        defaultCountdownProvider: { appSettingsStore.defaultAutoJoinCountdown },
                        telemostModeProvider: { appSettingsStore.telemostConnectionMode },
                        onCancelRequested: { meetingID, date in
                            meetingStore.cancelAutoJoin(meetingID: meetingID, on: date)
                        }
                    )
                    oneTimeMeetingCleaner.start(store: meetingStore)
                }
                .onChange(of: meetingStore.meetings) { _, newMeetings in
                    notificationService.rescheduleAll(for: newMeetings, exceptions: meetingStore.exceptions)
                }
                .onChange(of: meetingStore.exceptions) { _, newExceptions in
                    notificationService.rescheduleAll(for: meetingStore.meetings, exceptions: newExceptions)
                }
                .sheet(item: Binding(
                    get: { wakeObserver.missedOccurrence },
                    set: { newValue in
                        if newValue == nil { wakeObserver.dismissMissedOccurrence() }
                    }
                )) { occurrence in
                    MissedMeetingPromptView(
                        occurrence: occurrence,
                        onJoin: {
                            MeetingLauncher.open(occurrence.meeting.url)
                            wakeObserver.dismissMissedOccurrence()
                        },
                        onDismiss: {
                            wakeObserver.dismissMissedOccurrence()
                        }
                    )
                }
                .sheet(isPresented: $isShowingAbout) {
                    AboutView()
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("О KnockKnockBro") {
                    isShowingAbout = true
                }
            }
        }

        // Окно "Календарь" (v0.4.0). `Window`, а не `WindowGroup` — окно
        // всегда одно: повторное открытие из попапа выводит на передний
        // план уже открытое, а не создаёт второе.
        Window("Календарь", id: CalendarWindow.id) {
            CalendarWindowView()
                .environment(meetingStore)
                .environment(appSettingsStore)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            SettingsView()
                .environment(appSettingsStore)
                .environment(meetingStore)
        }

        MenuBarExtra(isInserted: Binding(
            get: { appSettingsStore.showInMenuBar },
            set: { appSettingsStore.showInMenuBar = $0 }
        )) {
            MenuBarContentView()
                .environment(meetingStore)
                .environment(appSettingsStore)
        } label: {
            MenuBarLabelView()
                .environment(meetingStore)
        }
        .menuBarExtraStyle(.window)
    }
}
