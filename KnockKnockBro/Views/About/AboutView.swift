import SwiftUI

/// Экран "О приложении" — открывается через стандартный системный пункт
/// меню "О KnockKnockBro", как это принято у нативных macOS-приложений.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            if let icon = NSApplication.shared.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 96, height: 96)
            }

            VStack(spacing: 4) {
                Text("KnockKnockBro")
                    .font(.title.bold())
                Text("Meetings. No surprises.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Следит за созвонами. Напоминает вовремя. Открывает, когда ты готов.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 280)

            Text(versionString)
                .font(.caption)
                .foregroundStyle(.tertiary)

            Divider()
                .frame(width: 200)

            Text("«Ни одна встреча больше не застанет врасплох.»")
                .font(.callout.italic())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            Button("Закрыть") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(32)
        .frame(width: 340)
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Версия \(version) (\(build))"
    }
}

#Preview {
    AboutView()
}
