import Foundation

// Quick 261018-jd8, цикл исправлений по REVIEW.md (CR-01/WR-01/WR-02/WR-03 + parent
// Keychain): ЧИСТЫЕ компоненты границы app-seam — без сети, без Security framework
// (файл линкуется и в widget-таргет: символов SDK Keychain здесь быть не должно).
//
// ProviderRowBoard — единственное хранилище строк модели: каждое применение
// результата опроса (успех ИЛИ ошибка) проходит проверку эпохи credential; смена/
// удаление credential инвалидирует эпоху и немедленно убирает строку старого
// аккаунта; публикация в снимок фильтрует только ОТСУТСТВУЮЩИЕ credential —
// недоступная Keychain строки не выкидывает (FIX5).

/// Присутствие credential в Keychain как чистый маппинг статуса SecItem:
/// статус передаётся числом, чтобы этот файл не импортировал Security.
public enum KeychainPresence: Equatable, Sendable {
    case present
    case absent
    /// Отказ Keychain (занята/недоступна): НЕ трактуется как «не подключён» —
    /// строки и кэш не удаляются молча.
    case unavailable
    /// Канонической записи нет, но обнаружены СВОИ legacy-слоты прежних сборок
    /// (пара Codex token/account-id v3–v5). Они НЕ угадываются, НЕ смешиваются
    /// и НЕ мигрируют: единственный путь — явный повторный импорт владельцем,
    /// записывающий новый атомарный конверт одной операцией.
    case needsReimport
}

/// Статусы SecItem как литералы (errSecSuccess / errSecItemNotFound) — без
/// импорта Security, чтобы виджет не получал SDK-символов из UsageCore.
public let keychainStatusSuccess: Int32 = 0
public let keychainStatusItemNotFound: Int32 = -25300

/// Маппинг статуса чтения Keychain в присутствие credential.
public func keychainPresence(status: Int32, hasValue: Bool) -> KeychainPresence {
    switch status {
    case keychainStatusSuccess:
        return hasValue ? .present : .absent
    case keychainStatusItemNotFound:
        return .absent
    default:
        return .unavailable
    }
}

/// Операция Keychain для фиксированного пользовательского сообщения.
public enum KeychainOperation: String, Sendable {
    case write
    case delete
    case read
}

/// Фиксированные сообщения об ошибках Keychain: без сырых кодов OSStatus,
/// NSError-описаний и путей — эхо приватных данных исключено по построению.
public func keychainFailureMessage(_ operation: KeychainOperation) -> String {
    switch operation {
    case .write: return "Не удалось сохранить ключ (Keychain)"
    case .delete: return "Не удалось удалить ключ (Keychain)"
    case .read: return "Keychain недоступна"
    }
}

/// Доска строк провайдеров с поколениями credential (CR-01).
/// Все мутации детерминированы и синхронны — гонок нет по построению;
/// асинхронные ответы проверяются по эпохе, захваченной ДО запроса.
public struct ProviderRowBoard: Sendable {
    public private(set) var rows: [ProviderID: ProviderRow]
    private var generations: [ProviderID: Int]

    public init(rows: [ProviderID: ProviderRow] = [:]) {
        self.rows = rows
        self.generations = [:]
    }

    /// Эпоха credential провайдера на момент захвата (до запроса).
    public func currentEpoch(_ provider: ProviderID) -> Int {
        generations[provider, default: 0]
    }

    /// Инвалидация при disconnect/replace/импорте: эпоха +1 (монотонно, включая
    /// повторное подключение того же аккаунта) и НЕМЕДЛЕННОЕ удаление строки —
    /// факты старого аккаунта не могут изображать новый.
    public mutating func invalidate(_ provider: ProviderID) {
        generations[provider, default: 0] += 1
        rows.removeValue(forKey: provider)
    }

    /// Применить успешный ответ ТОЛЬКО при актуальной эпохе: устаревший
    /// (после disconnect/replace) успех не воскрешает строку.
    public mutating func applySuccess(_ provider: ProviderID, epoch: Int, row: ProviderRow) {
        guard generations[provider, default: 0] == epoch else { return }
        rows[provider] = row
    }

    /// Применить ошибку ТОЛЬКО при актуальной эпохе: last-good того же
    /// credential сохраняется (fetchedAt не сбрасывается); при отсутствии
    /// фактов — честная строка «только ошибка»; устаревшая ошибка отбрасывается.
    public mutating func applyFailure(_ provider: ProviderID, epoch: Int, message: String, now: Date) {
        guard generations[provider, default: 0] == epoch else { return }
        if let previous = rows[provider] {
            rows[provider] = previous.withError(message, attemptedAt: now)
        } else {
            rows[provider] = ProviderRow(
                providerID: provider, displayName: provider.displayName,
                fetchedAt: nil, error: message, lastAttemptAt: now)
        }
    }

    /// Строки для публикации: порядок словаря провайдеров; исключаются ТОЛЬКО
    /// провайдеры с достоверно отсутствующим credential (absent). Недоступная
    /// Keychain (unavailable) сюда не попадает — строка сохраняется (FIX5).
    public func publishedRows(excluding absent: Set<ProviderID>) -> [ProviderRow] {
        ProviderID.allCases.compactMap { provider in
            absent.contains(provider) ? nil : rows[provider]
        }
    }
}

// MARK: - Коалесцирование проходов опроса (WR-04)

/// Вентиль проходов refresh: запрос, пришедший во время идущего прохода
/// (save/disconnect/импорт), НЕ теряется и НЕ порождает параллельный проход —
/// он коалесцируется в ровно ОДИН немедленный повторный проход по завершении
/// текущего (без ожидания 5-минутного тика). Повторный проход выполняется
/// синхронным продолжением того же await-цикла (без рекурсивного порождения
/// задач): пока новых запросов нет, цикл завершается — мёртвых циклов нет.
public struct RefreshGate: Sendable, Equatable {
    public private(set) var inFlight = false
    public private(set) var pendingRerun = false

    public init() {}

    /// Начало прохода: true — выполнять проход; false — проход уже идёт,
    /// запрос коалесцирован (будет обслужен повторным проходом).
    public mutating func begin() -> Bool {
        if inFlight {
            pendingRerun = true
            return false
        }
        inFlight = true
        return true
    }

    /// Завершение прохода: true — есть коалесцированный запрос, нужен ОДИН
    /// немедленный повторный проход (inFlight остаётся поднятым); false —
    /// запросов нет, вентиль свободен.
    public mutating func end() -> Bool {
        if pendingRerun {
            pendingRerun = false
            return true
        }
        inFlight = false
        return false
    }
}
