import SwiftUI

/// Подсветка строк попапа Menu Bar при наведении курсора — как в
/// нативных меню macOS.
///
/// Два вида:
/// - `PopupMenuItemButtonStyle` — для пунктов меню ("Открыть KnockKnockBro",
///   "Настройки", "Выйти"): заливка акцентным цветом и белый текст, как
///   выделенный пункт системного меню.
/// - `.popupRowHoverHighlight()` — для строк встреч и Quick Rooms: мягкая
///   серая подложка. Акцентная заливка здесь не подходит — внутри строки
///   есть свои кнопки "Подключиться", они слились бы с фоном.
///
/// Обе подсветки отступают от краёв попапа на 6pt и скруглены — внешний
/// отступ строки (6 + 6 = 12pt) совпадает с прежним `.padding(.horizontal, 12)`,
/// поэтому содержимое не сдвигается.
struct PopupMenuItemButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuItemBody(configuration: configuration)
    }

    private struct MenuItemBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .foregroundStyle(isHovered ? AnyShapeStyle(Color.white) : AnyShapeStyle(HierarchicalShapeStyle.primary))
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isHovered ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.clear))
                        .opacity(configuration.isPressed ? 0.8 : 1)
                }
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
                .padding(.horizontal, 6)
        }
    }
}

/// Иконка-кнопка в шапке попапа (календарь): при наведении — та же мягкая
/// серая подложка, что у строк встреч, только компактная и квадратная.
struct PopupIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconBody(configuration: configuration)
    }

    private struct IconBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 22)
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : (isHovered ? 0.08 : 0)))
                }
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }
    }
}

private struct PopupRowHoverHighlight: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 6)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .padding(.horizontal, 6)
    }
}

extension View {
    /// Мягкая подсветка строки встречи / Quick Room в попапе при наведении.
    func popupRowHoverHighlight() -> some View {
        modifier(PopupRowHoverHighlight())
    }
}
