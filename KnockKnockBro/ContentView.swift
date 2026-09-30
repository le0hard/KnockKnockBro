import SwiftUI

/// Главное окно приложения. Помимо самого списка встреч, принимает
/// Drag & Drop JSON-файла конфигурации прямо на окно — второй способ
/// импорта наряду со стандартным выбором файла в Settings.
struct ContentView: View {
    @Environment(MeetingStore.self) private var store
    @Environment(AppSettingsStore.self) private var settings

    @State private var pendingImport: PendingImport?
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
            .sheet(item: $pendingImport) { pending in
                ImportSheetView(pending: pending)
                    .environment(store)
                    .environment(settings)
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
        switch PendingImport.load(from: url) {
        case .success(let pending):
            pendingImport = pending
        case .failure(let failure):
            importErrorMessage = failure.message
        }
    }
}

#Preview {
    ContentView()
        .environment(MeetingStore())
        .environment(AppSettingsStore())
}
