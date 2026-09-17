import SwiftUI

/// Главное окно приложения. Помимо самого списка встреч, принимает
/// Drag & Drop JSON-файла конфигурации прямо на окно — второй способ
/// импорта наряду со стандартным выбором файла в Settings.
struct ContentView: View {
    @Environment(MeetingStore.self) private var store

    @State private var pendingImport: ValidatedImport?
    @State private var existingMeetingsCountAtImportStart = 0
    @State private var importErrorMessage: String?

    var body: some View {
        MeetingListView()
            .frame(minWidth: 560, minHeight: 420)
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first(where: { $0.pathExtension.lowercased() == "json" }) else {
                    importErrorMessage = "Перетащите файл в формате .json."
                    return false
                }
                handleImportFile(at: url)
                return true
            }
            .confirmationDialog(
                "Импортировать встречи?",
                isPresented: Binding(
                    get: { pendingImport != nil },
                    set: { isPresented in if !isPresented { pendingImport = nil } }
                ),
                presenting: pendingImport
            ) { validated in
                Button("Импортировать", role: .destructive) {
                    store.replaceAll(meetings: validated.meetings, exceptions: validated.exceptions)
                    pendingImport = nil
                }
                Button("Отмена", role: .cancel) {
                    pendingImport = nil
                }
            } message: { validated in
                Text("Текущие \(existingMeetingsCountAtImportStart) встреч(и) будут заменены на \(validated.meetings.count) из файла. Это действие нельзя отменить.")
            }
            .alert(
                "Не удалось импортировать файл",
                isPresented: Binding(
                    get: { importErrorMessage != nil },
                    set: { isPresented in if !isPresented { importErrorMessage = nil } }
                )
            ) {
                Button("ОК", role: .cancel) { importErrorMessage = nil }
            } message: {
                Text(importErrorMessage ?? "")
            }
    }

    private func handleImportFile(at url: URL) {
        do {
            let data = try Data(contentsOf: url)
            switch ImportExportService.validate(data: data) {
            case .success(let validated):
                existingMeetingsCountAtImportStart = store.meetings.count
                pendingImport = validated
            case .failure(let error):
                importErrorMessage = error.localizedDescription
            }
        } catch {
            importErrorMessage = "Не удалось прочитать файл: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ContentView()
        .environment(MeetingStore())
}
