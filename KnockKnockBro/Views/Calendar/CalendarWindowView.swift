import SwiftUI
import AppKit
import Combine

/// Открытие окна "Календарь" — общее для попапа Menu Bar и тулбара
/// главного окна.
enum CalendarWindow {
    /// Идентификатор сцены `Window` в `KnockKnockBroApp`.
    static let id = "calendar"

    /// Выводит уже открытое (или свёрнутое в Dock) окно на передний план,
    /// иначе открывает его. `Window`-сцена и так существует в одном
    /// экземпляре, но `openWindow` не разворачивает свёрнутое окно —
    /// поэтому сначала ищем его сами.
    @MainActor
    static func show(using openWindow: OpenWindowAction) {
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == id && ($0.isVisible || $0.isMiniaturized) }) {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: id)
        }
    }
}

/// Окно "Календарь": сетка месяца сверху (сегодня выделен, точки — дни
/// со встречами), список встреч выбранного дня снизу. По умолчанию
/// выбран сегодняшний день.
///
/// Открывается значком календаря в попапе Menu Bar. Только просмотр и
/// подключение — создание/редактирование встреч остаётся в главном окне.
struct CalendarWindowView: View {
    @Environment(MeetingStore.self) private var store
    @Environment(AppSettingsStore.self) private var settings

    @State private var now = Date()
    @State private var displayedMonth = CalendarMonthLayout.startOfMonth(for: Date())
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())

    /// Число месяца, которое пользователь выбрал последним кликом (или
    /// "Сегодня"). Хранится отдельно от `selectedDay`, чтобы при листании
    /// 31 января → февраль (28) → март снова получалось 31 марта, а не 28.
    @State private var preferredDayOfMonth = Calendar.current.component(.day, from: Date())

    /// Раз в минуту — чтобы подписи "через N мин" и выделение сегодняшнего
    /// дня (после полуночи) оставались актуальными, пока окно открыто.
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var calendar: Calendar { .current }

    var body: some View {
        VStack(spacing: 0) {
            monthHeader
            weekdayHeader
            monthGrid
            Divider()
                .padding(.top, 10)
            dayAgenda
        }
        .frame(width: 400)
        .frame(minHeight: 580)
        .onReceive(timer) { newDate in
            now = newDate
        }
    }

    // MARK: - Month header

    private var monthHeader: some View {
        HStack(spacing: 8) {
            Text(Self.monthTitle(for: displayedMonth))
                .font(.title2.bold())
            Spacer()
            Button {
                showMonth(byAdding: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .help("Предыдущий месяц")

            Button("Сегодня") {
                displayedMonth = CalendarMonthLayout.startOfMonth(for: now, calendar: calendar)
                selectDay(now)
            }

            Button {
                showMonth(byAdding: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .help("Следующий месяц")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    /// Листание месяцев: выбранный день переходит на то же число нового
    /// месяца (или на его последний день, если такого числа нет), и список
    /// встреч внизу обновляется вместе с сеткой.
    private func showMonth(byAdding value: Int) {
        displayedMonth = CalendarMonthLayout.month(byAdding: value, to: displayedMonth, calendar: calendar)
        selectedDay = CalendarMonthLayout.day(preferredDayOfMonth, inMonthStarting: displayedMonth, calendar: calendar)
    }

    private func selectDay(_ day: Date) {
        selectedDay = calendar.startOfDay(for: day)
        preferredDayOfMonth = calendar.component(.day, from: day)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(Weekday.mondayFirstOrder) { weekday in
                Text(weekday.shortDisplayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Month grid

    private var monthGrid: some View {
        let cells = CalendarMonthLayout.cells(forMonthStarting: displayedMonth, calendar: calendar)
        let busyDays = CalendarMonthLayout.daysWithMeetings(
            meetings: store.meetings, exceptions: store.exceptions, monthStart: displayedMonth, calendar: calendar
        )
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(cells.indices, id: \.self) { index in
                if let day = cells[index] {
                    dayCell(day, hasMeetings: busyDays.contains(CalendarDay(date: day, calendar: calendar)))
                } else {
                    Color.clear
                        .frame(height: 42)
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private func dayCell(_ day: Date, hasMeetings: Bool) -> some View {
        let isToday = calendar.isDate(day, inSameDayAs: now)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isPast = day < calendar.startOfDay(for: now)

        return Button {
            selectDay(day)
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.body.weight(isToday ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? AnyShapeStyle(Color.white) : (isPast ? AnyShapeStyle(HierarchicalShapeStyle.secondary) : AnyShapeStyle(HierarchicalShapeStyle.primary)))
                    .frame(width: 28, height: 28)
                    .background {
                        if isToday {
                            Circle().fill(Color.accentColor)
                        }
                    }

                Circle()
                    .fill(hasMeetings ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.clear))
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.15))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Day agenda

    private var dayAgenda: some View {
        let items = CalendarMonthLayout.agenda(
            on: selectedDay, meetings: store.meetings, exceptions: store.exceptions, calendar: calendar
        )

        return VStack(alignment: .leading, spacing: 0) {
            Text(agendaTitle)
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)

            if items.isEmpty {
                ContentUnavailableView(
                    "Свободный день",
                    systemImage: "cup.and.saucer",
                    description: Text("Никто не стучится.")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            agendaRow(item)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var agendaTitle: String {
        let dateText = Self.agendaDateFormatter.string(from: selectedDay)
        if calendar.isDate(selectedDay, inSameDayAs: now) {
            return "Сегодня · \(dateText)"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(selectedDay, inSameDayAs: tomorrow) {
            return "Завтра · \(dateText)"
        }
        return Self.capitalizedFirstLetter(Self.agendaWeekdayFormatter.string(from: selectedDay)) + " · " + dateText
    }

    /// Строка встречи — тот же ритм, что в попапе Menu Bar: колонка
    /// времени слева, иконка сервиса, название, кнопки подключения.
    /// Подключиться можно только к сегодняшним непропущенным встречам;
    /// подпись "через N мин" тоже только для сегодняшних.
    private func agendaRow(_ item: DayAgendaItem) -> some View {
        let occurrence = item.occurrence
        let isToday = calendar.isDate(occurrence.startDate, inSameDayAs: now)
        let hasStarted = occurrence.startDate <= now
        let connectOptions = (isToday && !item.isSkipped)
            ? MeetingLauncher.connectOptions(for: occurrence.meeting, telemostMode: settings.telemostConnectionMode)
            : []
        let caption: String? = item.isSkipped
            ? "пропущена"
            : (isToday ? UpcomingMeetingsProvider.timeColumnCaption(from: now, to: occurrence.startDate) : nil)

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Self.timeFormatter.string(from: occurrence.startDate))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(hasStarted || item.isSkipped ? .secondary : .primary)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(width: 84, alignment: .leading)

            ServiceIconView(service: occurrence.meeting.service, size: 22)

            Text(occurrence.meeting.name)
                .font(.headline)
                .strikethrough(item.isSkipped)
                .foregroundStyle(item.isSkipped ? .secondary : .primary)
                .lineLimit(2)

            Spacer(minLength: 8)

            ForEach(connectOptions) { option in
                ConnectOptionButton(
                    title: option.title,
                    isPrimary: option.id == connectOptions.first?.id,
                    action: { MeetingLauncher.open(option.url) }
                )
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
    }

    // MARK: - Formatting

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// "октябрь 2026" — `LLLL` даёт название месяца в именительном падеже.
    private static let monthTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    /// "5 октября".
    private static let agendaDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM"
        return formatter
    }()

    /// "среда".
    private static let agendaWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    private static func monthTitle(for date: Date) -> String {
        capitalizedFirstLetter(monthTitleFormatter.string(from: date))
    }

    private static func capitalizedFirstLetter(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}

#Preview {
    CalendarWindowView()
        .environment(MeetingStore())
        .environment(AppSettingsStore())
}
