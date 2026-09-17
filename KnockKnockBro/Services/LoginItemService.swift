import Foundation
import ServiceManagement

/// Обёртка над `SMAppService.mainApp` — современным штатным механизмом
/// регистрации приложения как login item, доступным с macOS 13.
///
/// Статус регистрации — состояние самой системы (пользователь может
/// включить/выключить автозапуск через системные Settings → General →
/// Login Items в обход нашего UI), поэтому это НЕ значение, которое
/// хранится в `AppSettingsStore` — мы всегда читаем и пишем напрямую через
/// `SMAppService`, чтобы не разойтись с реальным состоянием системы.
struct LoginItemService {

    enum Status: Equatable {
        case enabled
        /// Зарегистрировано, но требует подтверждения пользователем в
        /// системных Settings — например, после обновления приложения.
        case requiresApproval
        case disabled
    }

    static var currentStatus: Status {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered, .notFound:
            return .disabled
        @unknown default:
            return .disabled
        }
    }

    /// Включает или выключает автозапуск при входе в macOS.
    /// - Throws: ошибку `SMAppService`, если регистрация/снятие регистрации
    ///   не удалась (например, отклонена политикой системы).
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else {
            if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
        }
    }
}
