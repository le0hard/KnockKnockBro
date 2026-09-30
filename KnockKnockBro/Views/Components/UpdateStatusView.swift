import SwiftUI
import AppKit

/// Кнопка "Проверить обновления" + результат последней проверки.
/// Одинаковая в Настройках и в окне "О KnockKnockBro".
struct UpdateStatusView: View {
    @Environment(UpdateChecker.self) private var updateChecker

    /// Выравнивание строк: в Настройках — по левому краю, в "О программе" — по центру.
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 8) {
            resultView

            Button("Проверить обновления") {
                Task { await updateChecker.check() }
            }
            .disabled(updateChecker.isChecking)
        }
    }

    @ViewBuilder
    private var resultView: some View {
        if updateChecker.isChecking {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Проверяю…")
                    .foregroundStyle(.secondary)
            }
        } else if let result = updateChecker.lastResult {
            switch result {
            case .upToDate:
                Label("У вас последняя версия", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .updateAvailable(let release):
                VStack(alignment: alignment, spacing: 6) {
                    Label("Доступна версия \(release.version.description)", systemImage: "arrow.down.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.headline)
                    Button("Открыть страницу загрузки") {
                        NSWorkspace.shared.open(release.pageURL)
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .failed(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(alignment == .center ? .center : .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
