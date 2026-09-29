import SwiftUI

/// Одна кнопка подключения — переиспользуется в главном окне, попапе
/// Menu Bar и countdown-панели Auto Join.
///
/// Реализована через `if/else`, а не тернарный оператор внутри
/// `.buttonStyle(...)` — `.borderedProminent` и `.bordered` разные
/// конкретные типы, и их унификация через тернарный оператор в одном
/// generic-выражении заставляла компилятор Swift превышать разумное
/// время проверки типов ("unable to type-check in reasonable time").
///
/// `iconSystemName` (v0.5.0) — компактный вариант для попапа Menu Bar:
/// вместо текста значок, а полная подпись — в подсказке и для VoiceOver.
struct ConnectOptionButton: View {
    let title: String
    let isPrimary: Bool
    var isEnabled: Bool = true
    var iconSystemName: String? = nil
    let action: () -> Void

    var body: some View {
        Group {
            if isPrimary {
                Button(action: action) { label }
                    .buttonStyle(.borderedProminent)
            } else {
                Button(action: action) { label }
                    .buttonStyle(.bordered)
            }
        }
        .disabled(!isEnabled)
        .help(title)
    }

    @ViewBuilder
    private var label: some View {
        if let iconSystemName {
            Image(systemName: iconSystemName)
                .accessibilityLabel(title)
        } else {
            Text(title)
        }
    }
}
