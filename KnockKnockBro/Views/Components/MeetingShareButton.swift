import SwiftUI

/// Кнопка-значок "Поделиться" в главном окне — стандартное меню отправки
/// macOS (`ShareLink`): Сообщения, Почта, AirDrop, Заметки и приложения со
/// своим расширением отправки (Telegram, Slack и т. п.).
///
/// Отправляется тот же текст, что копирует кнопка "Копировать" —
/// `MeetingLauncher.shareText`: название (со временем начала) и ссылка.
/// Название дополнительно передаётся как тема — её подставляет Почта.
struct MeetingShareButton: View {
    let meeting: Meeting
    var startDate: Date?

    var body: some View {
        ShareLink(
            item: MeetingLauncher.shareText(for: meeting, startDate: startDate),
            subject: Text(meeting.name)
        ) {
            Image(systemName: "square.and.arrow.up")
        }
        .help("Поделиться названием и ссылкой")
    }
}
