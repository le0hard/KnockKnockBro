import SwiftUI

/// Одна кнопка подключения — переиспользуется в главном окне и в
/// countdown-панели Auto Join.
///
/// Реализована через `if/else`, а не тернарный оператор внутри
/// `.buttonStyle(...)` — `.borderedProminent` и `.bordered` разные
/// конкретные типы, и их унификация через тернарный оператор в одном
/// generic-выражении заставляла компилятор Swift превышать разумное
/// время проверки типов ("unable to type-check in reasonable time").
struct ConnectOptionButton: View {
    let title: String
    let isPrimary: Bool
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Group {
            if isPrimary {
                Button(title, action: action)
                    .buttonStyle(.borderedProminent)
            } else {
                Button(title, action: action)
                    .buttonStyle(.bordered)
            }
        }
        .disabled(!isEnabled)
    }
}
