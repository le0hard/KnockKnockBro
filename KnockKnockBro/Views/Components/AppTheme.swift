import SwiftUI

/// Design tokens KnockKnockBro.
///
/// Приложение остаётся adaptive (следует системной теме пользователя, а
/// не принудительно тёмное) — но когда система находится в тёмном режиме,
/// используется собственная, более глубокая тёмно-синяя палитра, близкая
/// к макету интерфейса, вместо стандартного системного тёмно-серого фона.
/// В светлой теме используются обычные системные цвета без кастомизации.
enum AppTheme {
    /// Фирменный акцентный цвет — красный, как деталь на иконке
    /// приложения. Используется одинаково в обеих темах.
    static let accent = Color(hex: "FC3F1D")

    /// Фон карточки строки списка. В тёмной теме — глубокий
    /// сине-угольный оттенок вместо стандартного серого; в светлой —
    /// обычный системный цвет фона группы.
    static func cardBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "1C1F2A") : Color(nsColor: .controlBackgroundColor)
    }

    /// Фон панели/попапа (Auto Join countdown, Menu Bar попап).
    static func panelBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "12141C") : Color(nsColor: .windowBackgroundColor)
    }
}

extension Color {
    /// Инициализирует цвет из hex-строки вида "RRGGBB".
    init(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized = sanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&rgb)

        let red = Double((rgb & 0xFF0000) >> 16) / 255.0
        let green = Double((rgb & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgb & 0x0000FF) / 255.0

        self.init(red: red, green: green, blue: blue)
    }
}
