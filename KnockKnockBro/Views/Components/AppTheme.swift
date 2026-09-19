import SwiftUI

/// Design tokens KnockKnockBro.
///
/// `accent` держится отдельно от системного accent color и НЕ применяется
/// как глобальный tint для интерактивных элементов — HIG прямо просит
/// уважать accent color, выбранный пользователем в System Settings, для
/// кнопок и выделений. Сайдбар, `.borderedProminent`-кнопки и выбор дней
/// недели в редакторе используют системный `Color.accentColor` напрямую,
/// без переопределения. `accent` предназначен только для точечного
/// брендинга (например, если понадобится акцентный элемент в About).
enum AppTheme {
    static let accent = Color(hex: "FC3F1D")

    /// Фон карточки строки списка. В тёмной теме — глубокий сине-угольный
    /// оттенок вместо стандартного серого; в светлой — обычный системный
    /// цвет фона группы. Это НЕ конфликтует с точкой 5 (материалы для
    /// плавающих панелей) — карточки в списке лежат на обычном фоне окна,
    /// а не парят отдельно, поэтому нативный custom-тон здесь уместен
    /// (тот же паттерн, что цветные группы в Reminders/Notes).
    static func cardBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "1C1F2A") : Color(nsColor: .controlBackgroundColor)
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
