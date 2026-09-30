import Foundation
import Observation

/// Номер версии вида "0.6.0" / "v0.6.0", сравниваемый по числам:
/// 0.10.0 > 0.9.0, 1.0 == 1.0.0.
struct AppVersion: Comparable, CustomStringConvertible {
    let components: [Int]

    init?(_ string: String) {
        var trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            trimmed.removeFirst()
        }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Int($0) }
        guard !parts.isEmpty, numbers.count == parts.count, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        components = numbers
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

/// Последний опубликованный релиз.
struct ReleaseInfo: Equatable {
    let version: AppVersion
    /// Страница релиза на GitHub — там описание и zip для скачивания.
    let pageURL: URL
}

/// Итог проверки обновлений.
enum UpdateCheckResult: Equatable {
    case upToDate(current: String)
    case updateAvailable(ReleaseInfo)
    case failed(String)
}

/// Проверка обновлений через GitHub Releases (v0.6.0).
///
/// Приложение ничего не скачивает и не устанавливает само: если на GitHub
/// есть версия новее, пользователю предлагается открыть страницу релиза.
///
/// Когда проверяет:
/// - автоматически — только при открытии Настроек и не чаще раза в сутки
///   (`checkIfNeeded`); при запуске приложения — никогда. Ошибки
///   автоматической проверки (нет сети и т. п.) молча игнорируются;
/// - вручную — кнопкой "Проверить обновления" (`check`), всегда с ответом.
///
/// Источник версии — одна константа `latestReleaseURL`: при переходе на
/// свой домен достаточно заменить адрес и формат разбора ответа.
@MainActor
@Observable
final class UpdateChecker {

    static let latestReleaseURL = URL(string: "https://api.github.com/repos/le0hard/KnockKnockBro/releases/latest")!
    static let automaticCheckInterval: TimeInterval = 24 * 60 * 60

    private(set) var isChecking = false
    private(set) var lastResult: UpdateCheckResult?

    /// Загрузка данных — вынесена параметром, чтобы тесты работали без сети.
    typealias Fetch = (URL) async throws -> (Data, URLResponse)

    private let defaults: UserDefaults
    private let fetch: Fetch
    private let currentVersionString: String

    private static let lastCheckKey = "lastUpdateCheckDate"

    init(
        defaults: UserDefaults = .standard,
        currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
        fetch: Fetch? = nil
    ) {
        self.defaults = defaults
        self.currentVersionString = currentVersion
        self.fetch = fetch ?? { url in
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("KnockKnockBro/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            return try await URLSession.shared.data(for: request)
        }
    }

    /// Время последней УСПЕШНОЙ проверки.
    var lastCheckDate: Date? {
        defaults.object(forKey: Self.lastCheckKey) as? Date
    }

    /// Автоматическая проверка: только если с прошлой успешной прошло
    /// больше суток. Ошибку не показывает — в следующий раз попробуем снова.
    func checkIfNeeded(now: Date = Date()) async {
        if let lastCheckDate, now.timeIntervalSince(lastCheckDate) < Self.automaticCheckInterval {
            return
        }
        let result = await performCheck(now: now)
        if case .failed = result { return }
        lastResult = result
    }

    /// Ручная проверка — всегда, с результатом (в том числе ошибкой).
    func check(now: Date = Date()) async {
        lastResult = await performCheck(now: now)
    }

    private func performCheck(now: Date) async -> UpdateCheckResult {
        guard !isChecking else { return lastResult ?? .failed("Проверка уже идёт.") }
        isChecking = true
        defer { isChecking = false }

        do {
            let (data, response) = try await fetch(Self.latestReleaseURL)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                return .failed(Self.message(forStatusCode: http.statusCode))
            }
            let release = try Self.parseLatestRelease(from: data)
            defaults.set(now, forKey: Self.lastCheckKey)
            return Self.evaluate(release: release, currentVersion: currentVersionString)
        } catch let error as UpdateParseError {
            return .failed(error.message)
        } catch {
            return .failed("Не удалось проверить обновления: \(error.localizedDescription)")
        }
    }

    // MARK: - Чистая логика (тестируется без сети)

    struct UpdateParseError: Error {
        let message: String
    }

    /// Разбирает ответ `GET /repos/{owner}/{repo}/releases/latest`:
    /// нужны только `tag_name` ("v0.6.0") и `html_url` (страница релиза).
    nonisolated static func parseLatestRelease(from data: Data) throws -> ReleaseInfo {
        struct Payload: Decodable {
            let tag_name: String
            let html_url: URL
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw UpdateParseError(message: "GitHub вернул неожиданный ответ.")
        }
        guard let version = AppVersion(payload.tag_name) else {
            throw UpdateParseError(message: "Не удалось разобрать номер версии «\(payload.tag_name)».")
        }
        return ReleaseInfo(version: version, pageURL: payload.html_url)
    }

    nonisolated static func evaluate(release: ReleaseInfo, currentVersion: String) -> UpdateCheckResult {
        guard let current = AppVersion(currentVersion), current < release.version else {
            return .upToDate(current: currentVersion)
        }
        return .updateAvailable(release)
    }

    nonisolated static func message(forStatusCode code: Int) -> String {
        switch code {
        case 404:
            return "На GitHub пока нет опубликованных релизов."
        case 403, 429:
            return "GitHub временно ограничил запросы. Попробуйте позже."
        default:
            return "GitHub ответил с ошибкой (код \(code)). Попробуйте позже."
        }
    }
}
