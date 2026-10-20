import Foundation
import Security
import AppKit
import UsageCore
import WidgetKit

// Quick 261018-jd8 (Task 2 + циклы исправлений REVIEW.md): сеть, Keychain и
// импорт credential — ТОЛЬКО в app-таргете. Виджет остаётся читателем снимка.
//
// Цикл исправлений:
// - CR-01: каждый запрос захватывает эпоху credential (ProviderRowBoard);
//   успех И ошибка применяются только при актуальной эпохе; disconnect/replace/
//   импорт инвалидируют эпоху и немедленно убирают строку старого аккаунта;
//   публикация исключает только достоверно absent-провайдеров.
// - CR-02: Codex хранится ОДНИМ атомарным Keychain-элементом — Codable-конверт
//   {schemaVersion, accessToken, accountId?}, заменяемый ОДНОЙ операцией
//   SecItem (update или add), целиком или никак. Legacy-пара v3–v5
//   (token + account-id) НЕ угадывается, НЕ смешивается, НЕ мигрирует:
//   без канонического конверта Codex показывает «требуется повторный импорт»,
//   HTTP по legacy-значениям не выполняется никогда. Неуспешная запись
//   оставляет прежний конверт нетронутым; board инвалидируется только после
//   подтверждённой записи.
// - WR-01: сообщения провайдера — фиксированные строки («HTTP N», транспорт);
//   произвольный text тела не переносится (см. ProviderAdapters.providerErrorMessage).
// - WR-04: запрос refresh во время идущего прохода коалесцируется
//   (RefreshGate, UsageCore) в один немедленный повторный проход.
// - FIX5 (parent): статусы SecItem проверяются; сохранение/удаление бросают
//   типизированную ошибку с фиксированным сообщением; отсутствие (notFound)
//   отличается от недоступности (Keychain недоступна строки не удаляет).
// - Keychain: КЛАССИЧЕСКИЙ macOS keychain (login) для собственного сервиса —
//   kSecUseDataProtectionKeychain НЕ ставится: DP-хранилище без entitlement
//   application-identifier/keychain-access-groups отклоняет записи при
//   personal-team подписи (selftest v5: отказ SecItemAdd). Продуктовое
//   требование — Keychain, не DP; старые DP-записи не читаются и не
//   трогаются: пустой classic-стор честно показывает «Не подключён».

// MARK: - Keychain (сервис своего бандла; account = слот провайдера)

/// Узкий самопроверочный режим подписанного приложения (parent-запрос):
/// write→read→delete по СЛУЧАЙНОМУ выделенному fixture-слоту + отдельный
/// roundtrip атомарного JSON-конверта Codex в НОВОМ fixture-слоте (без живого
/// ключа), фиксированный вывод PASS/FAIL с ЧИСЛОВЫМ OSStatus (без
/// localizedDescription/имён/значений — безопасная диагностика), cleanup даже
/// при отказе. Реальные слоты провайдеров не читаются, логов секретов нет.
enum KeychainSelfTest {
    static func run() -> Int32 {
        let keychain = KeychainStore()
        let account = "selftest.fixture.\(UUID().uuidString)"
        let value = "aiusage-selftest-\(UUID().uuidString)"
        defer { try? keychain.delete(account: account) }
        do {
            try keychain.write(value, account: account)
            guard try keychain.read(account: account) == value else {
                print("KEYCHAIN-SELFTEST: FAIL (чтение вернуло не записанное)")
                return 1
            }
            try keychain.delete(account: account)
            // Контрольное чтение после удаления: ОШИБКА чтения — это FAIL,
            // а не «слота нет» (nil допустим только как подтверждённый notFound).
            let afterDelete = try keychain.read(account: account)
            guard afterDelete == nil else {
                print("KEYCHAIN-SELFTEST: FAIL (слот жив после удаления)")
                return 1
            }
            // Парный fixture: атомарный конверт Codex в НОВОМ слоте —
            // запись одной операцией, чтение, decode и сравнение обеих частей.
            let envelopeAccount = "selftest.fixture.envelope.\(UUID().uuidString)"
            defer { try? keychain.delete(account: envelopeAccount) }
            let fixture = CodexCredentialEnvelope(accessToken: value, accountId: "fixture-account")
            try keychain.write(try fixture.encoded(), account: envelopeAccount)
            guard let stored = try keychain.read(account: envelopeAccount) else {
                print("KEYCHAIN-SELFTEST: FAIL (конверт не читается после записи)")
                return 1
            }
            guard (try? CodexCredentialEnvelope.decode(stored)) == fixture else {
                print("KEYCHAIN-SELFTEST: FAIL (конверт не совпал после roundtrip)")
                return 1
            }
            try keychain.delete(account: envelopeAccount)
            guard try keychain.read(account: envelopeAccount) == nil else {
                print("KEYCHAIN-SELFTEST: FAIL (слот конверта жив после удаления)")
                return 1
            }
            print("KEYCHAIN-SELFTEST: PASS")
            return 0
        } catch let error as KeychainError {
            print("KEYCHAIN-SELFTEST: FAIL op=\(error.operation.rawValue) status=\(error.status)")
            return 1
        } catch {
            print("KEYCHAIN-SELFTEST: FAIL (неизвестная ошибка)")
            return 1
        }
    }
}

/// Ошибка Keychain: фиксированное пользовательское сообщение (без сырых
/// NSError-описаний и значений) + операция и ЧИСЛОВОЙ OSStatus для безопасной
/// технической диагностики (число статуса приватных данных не раскрывает).
struct KeychainError: Error {
    let operation: KeychainOperation
    let status: Int32
    let message: String

    init(_ operation: KeychainOperation, status: Int32 = 0) {
        self.operation = operation
        self.status = status
        self.message = keychainFailureMessage(operation)
    }
}

struct KeychainStore {
    /// Сервис = bundle id приложения; аккаунты именуются по слотам провайдеров.
    private let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "com.serzhsharapa.aiusage") {
        self.service = service
    }

    /// Слот токена провайдера (для Codex — LEGACY-слот v3–v5, см. ниже).
    static func tokenAccount(_ provider: ProviderID) -> String {
        "provider.\(provider.rawValue).token"
    }

    /// Канонический слот Codex (CR-02): ОДИН элемент с JSON-конвертом
    /// {schemaVersion, accessToken, accountId?}; суффикс «.credentials.v1»
    /// исключает коллизию формы со старыми слотами.
    static let codexEnvelopeAccount = "provider.codex.credentials.v1"

    /// LEGACY-слот account id Codex (v3–v5): читается ТОЛЬКО для детекта
    /// «требуется повторный импорт» и удаляется по явному «Отключить» —
    /// никогда не участвует в опросе и не мигрирует.
    static let codexAccountIDAccount = "provider.codex.account-id"

    /// Фиксированное сообщение: канонического конверта нет, а legacy-пара
    /// есть (или конверт повреждён) — владельцу нужен явный повторный импорт.
    static let codexReimportMessage = "Codex: импортируйте auth.json заново (формат хранения обновлён)"

    /// Чтение: nil — слота нет (notFound); бросает при реальном отказе Keychain.
    func read(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        let value: String?
        if status == errSecSuccess, let data = item as? Data {
            value = String(data: data, encoding: .utf8)
        } else {
            value = nil
        }
        // Чистый маппинг статуса (Core) — read не маскирует отказы как «пусто».
        switch keychainPresence(status: status, hasValue: value != nil && !(value?.isEmpty ?? true)) {
        case .present:
            return value
        case .absent:
            return nil
        case .unavailable:
            throw KeychainError(.read, status: status)
        case .needsReimport:
            // needsReimport — решение уровня providerPresence, не сырого чтения.
            throw KeychainError(.read, status: status)
        }
    }

    /// Запись: update, при отсутствии — add; любой неуспешный статус — ошибка.
    /// Неуспешный update предмет НЕ меняет: прежняя запись остаётся нетронутой.
    func write(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError(.write)
        }
        let query = baseQuery(account: account)
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError(.write, status: updateStatus)
        }
        var add = query
        add[kSecValueData as String] = data
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError(.write, status: addStatus)
        }
    }

    /// Удаление ТОЛЬКО своего слота; отсутствующий слот — успех (идемпотентно).
    func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(.delete, status: status)
        }
    }

    /// Присутствие credential: present/absent/unavailable (для статуса и фильтров).
    func presence(account: String) -> KeychainPresence {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        let hasValue = status == errSecSuccess && (item as? Data).map { !$0.isEmpty } == true
        return keychainPresence(status: status, hasValue: hasValue)
    }

    func isConnected(_ provider: ProviderID) -> Bool {
        providerPresence(provider) == .present
    }

    /// Присутствие credential провайдера (FIX5: недоступная Keychain ≠ «не
    /// подключён»; CR-02: у Codex канон — атомарный конверт; legacy-пара
    /// v3–v5 без конверта — needsReimport, опрос по ней не выполняется).
    func providerPresence(_ provider: ProviderID) -> KeychainPresence {
        guard provider == .codex else {
            return presence(account: Self.tokenAccount(provider))
        }
        switch presence(account: Self.codexEnvelopeAccount) {
        case .present:
            return .present
        case .unavailable:
            return .unavailable
        case .needsReimport:
            return .unavailable // недостижимо для сырого чтения; консервативно
        case .absent:
            // Конверта нет: проверяем СВОИ legacy-слоты только для детекта
            // «нужен реимпорт». Значения legacy не читаются и не смешиваются.
            let legacyToken = presence(account: Self.tokenAccount(.codex))
            let legacyID = presence(account: Self.codexAccountIDAccount)
            if legacyToken == .present || legacyID == .present {
                return .needsReimport
            }
            if legacyToken == .unavailable || legacyID == .unavailable {
                return .unavailable
            }
            return .absent
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        // КЛАССИЧЕСКИЙ macOS keychain: kSecUseDataProtectionKeychain НЕ
        // устанавливается (по умолчанию false на macOS — файловая login
        // keychain). DP-флаг требует application-identifier/keychain-access-
        // groups, которых у personal-team dev-подписи нет (отказ записи,
        // selftest v5). Entitlements при этом НЕ расширяются.
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

// MARK: - Импорт credential-файла (явный выбор владельцем через NSOpenPanel)

enum CredentialFilePicker {
    /// Открывает NSOpenPanel (только файлы, не каталоги), читает выбранный файл
    /// read-only (entitlement user-selected.read-only) и парсит чистым
    /// CredentialImportFile. Файл не копируется и не логируется; refresh-токены
    /// не сохраняются по типу парсера. nil — владелец отменил выбор.
    static func pickAndParse() -> CredentialImport? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Импорт аккаунтов"
        panel.message = "Выберите файл auth.json (Codex CLI или Kilo).\nПуть можно ввести через ⌘⇧G. Файл только читается; refresh-токены не сохраняются."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        // Read-only чтение явно выбранного файла; ошибки разбора = пустой импорт.
        guard let data = try? Data(contentsOf: url) else { return CredentialImport(credentials: [:]) }
        return CredentialImportFile.parse(data: data)
    }
}

// MARK: - Fetcher: GET на фиксированный origin, редиректы запрещены

/// Ошибка опроса с санитизированным сообщением: без URL, без сырых тел,
/// без localizedDescription — только короткие фиксированные строки и
/// «HTTP N» (произвольный text провайдера отброшен, WR-01).
struct FetchFailure: Error {
    let message: String
}

/// Блокировщик редиректов: completion(nil) отменяет переход — заголовки
/// (включая Authorization) не пересылаются на другой хост.
private final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

struct ProviderFetcher {
    /// GETProbeSpec с 10-секундным таймаутом. Двойная проверка origin:
    /// URL обязан совпасть (scheme+host) с фиксированным origin провайдера.
    func fetch(_ spec: ProbeSpec, expectedOrigin: String) async -> Result<(Int, Data?), FetchFailure> {
        guard let url = URL(string: spec.url),
              url.scheme == "https",
              url.host.map({ host in
                  URL(string: expectedOrigin)?.host == host && URL(string: expectedOrigin)?.scheme == url.scheme
              }) == true else {
            return .failure(FetchFailure(message: "Отклонён недопустимый адрес запроса"))
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        for (name, value) in spec.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        // Сессия на один запрос: делегат-блокировщик живёт ровно до ответа.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: RedirectBlocker(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status > 0 else {
                return .failure(FetchFailure(message: "Пустой ответ провайдера"))
            }
            return .success((status, data.isEmpty ? nil : data))
        } catch let error as URLError {
            return .failure(FetchFailure(message: Self.transportMessage(error)))
        } catch {
            return .failure(FetchFailure(message: "Ошибка сети"))
        }
    }

    /// Фиксированные короткие строки (никаких localizedDescription/URL в тексте).
    private static func transportMessage(_ error: URLError) -> String {
        switch error.code {
        case .timedOut: return "Превышено время ожидания"
        case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost,
             .networkConnectionLost, .dnsLookupFailed: return "Нет соединения с провайдером"
        case .cancelled: return "Запрос отменён"
        default: return "Ошибка сети"
        }
    }
}

// MARK: - Модель приложения: refresh-координатор (жизнь = приложение)

/// Владелец состояния строк провайдеров. Хранилище строк — ProviderRowBoard
/// (UsageCore): применение результатов guarded эпохой credential (CR-01).
@MainActor @Observable
final class UsageModel {
    private var board = ProviderRowBoard()
    private(set) var isRefreshing = false
    /// Сообщение о результате последнего импорта (для настроек; без секретов).
    private(set) var lastImportSummary: String?
    /// Фиксированное сообщение последней ошибки Keychain (FIX5), nil — успех.
    private(set) var lastKeychainError: String?
    private(set) var cacheWriteFailed = false

    private let store: SnapshotStore
    private let keychain: KeychainStore
    private let fetcher = ProviderFetcher()
    /// Вентиль проходов (WR-04): запрос refresh во время идущего прохода
    /// коалесцируется в один немедленный повторный проход (не теряется,
    /// не ждёт 5-минутного тика, без параллельных проходов).
    private var gate = RefreshGate()
    private var loop: Task<Void, Never>?

    /// Интервал автопроверки (5 минут — режим приложения, бюджет WidgetKit не тратится).
    static let autoRefreshInterval: TimeInterval = 5 * 60

    init(store: SnapshotStore = SnapshotStore(), keychain: KeychainStore = KeychainStore()) {
        self.store = store
        self.keychain = keychain
    }

    /// Один вызов на запуск приложения: last-good + первый проход + таймер.
    func activate() {
        guard loop == nil else { return }
        loadLastGood()
        loop = Task { [weak self] in
            await self?.refreshAll()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.autoRefreshInterval))
                guard !Task.isCancelled else { break }
                await self?.refreshAll()
            }
        }
    }

    /// Провайдеры с достоверно присутствующим credential (absent ≠ unavailable;
    /// Codex считается подключённым ТОЛЬКО по каноническому конверту — legacy
    /// (needsReimport) и недоступная Keychain в опрос не идут).
    var connectedProviders: [ProviderID] {
        ProviderID.allCases.filter { keychain.isConnected($0) }
    }

    /// Статус одного провайдера для настроек (только факт наличия, не секрет).
    func isConnected(_ provider: ProviderID) -> Bool {
        keychain.isConnected(provider)
    }

    /// Присутствие credential провайдера: present/absent/unavailable/
    /// needsReimport (FIX5 + CR-02: legacy-пара Codex ≠ «подключён» и ≠ «нет»).
    func providerPresence(_ provider: ProviderID) -> KeychainPresence {
        keychain.providerPresence(provider)
    }

    /// Строки для UI/снимка: исключаются ТОЛЬКО absent-провайдеры — строка без
    /// credential не воскресает (CR-01 п.3), недоступная Keychain и legacy
    /// Codex (needsReimport) строки не выкидывают (FIX5).
    var orderedRows: [ProviderRow] {
        board.publishedRows(excluding: absentProviders)
    }

    private var absentProviders: Set<ProviderID> {
        Set(ProviderID.allCases.filter {
            keychain.providerPresence($0) == .absent
        })
    }

    // MARK: Действия владельца (настройки)

    /// Сохранить введённый ключ и опросить провайдера. true — сохранено
    /// (поле настроек очищается только тогда); false — Keychain отказал.
    @discardableResult
    func saveCredential(_ provider: ProviderID, token: String) -> Bool {
        // Codex подключается ТОЛЬКО импортом auth.json (атомарный конверт
        // token+accountId): ручной ввод не может молча заменить пару.
        guard provider != .codex else {
            lastKeychainError = "Codex подключается импортом auth.json"
            return false
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            try keychain.write(trimmed, account: KeychainStore.tokenAccount(provider))
        } catch let error as KeychainError {
            lastKeychainError = error.message
            return false
        } catch {
            lastKeychainError = keychainFailureMessage(.write)
            return false
        }
        lastKeychainError = nil
        // Смена/повторное подключение аккаунта: старые факты убираются ТОЛЬКО
        // после успешной записи; незавершённые ответы старого credential гаснут.
        board.invalidate(provider)
        persistAndReload()
        Task { await refreshAll() }
        return true
    }

    /// Отключить провайдера: удалить ТОЛЬКО его credential и ТОЛЬКО его строку.
    /// При отказе Keychain строка и кэш остаются (fail-visible, не молча).
    /// У Codex удаляется канонический конверт, затем — по тому же явному
    /// действию владельца — свои legacy-слоты v3–v5 (опроса по ним нет никогда).
    func disconnect(_ provider: ProviderID) {
        do {
            if provider == .codex {
                try keychain.delete(account: KeychainStore.codexEnvelopeAccount)
            } else {
                try keychain.delete(account: KeychainStore.tokenAccount(provider))
            }
        } catch let error as KeychainError {
            lastKeychainError = error.message
            return
        } catch {
            lastKeychainError = keychainFailureMessage(.delete)
            return
        }
        lastKeychainError = nil
        board.invalidate(provider)
        persistAndReload()
        if provider == .codex {
            // Legacy-слоты — свои; канонического credential уже нет, поэтому
            // их отказ только сообщается (кросс-аккаунтного эха быть не может).
            var legacyFailed = false
            do {
                try keychain.delete(account: KeychainStore.tokenAccount(.codex))
            } catch {
                legacyFailed = true
            }
            do {
                try keychain.delete(account: KeychainStore.codexAccountIDAccount)
            } catch {
                legacyFailed = true
            }
            if legacyFailed {
                lastKeychainError = keychainFailureMessage(.delete)
            }
        }
    }

    /// Импорт из файла (уже распарсен): пишет слоты в Keychain, считает только
    /// реальный успех. Codex пишется ОДНОЙ операцией как атомарный JSON-конверт
    /// {schemaVersion, accessToken, accountId?} (CR-02): при отказе записи
    /// прежний конверт остаётся нетронутым, board НЕ инвалидируется, импорт
    /// честно считается неудачным. Legacy-слоты v3–v5 при импорте не трогаются.
    /// Секреты в сводке не упоминаются.
    @discardableResult
    func applyImport(_ import_: CredentialImport, autoRefreshAfterImport: Bool = true,
                     replaceExisting: Bool = true) -> [ProviderID: String] {
        var imported = 0
        var failed = 0
        var statuses: [ProviderID: String] = [:]
        for (provider, credential) in import_.credentials.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            if !replaceExisting {
                switch keychain.providerPresence(provider) {
                case .absent: break
                case .present, .needsReimport:
                    statuses[provider] = "skipped_existing"
                    continue
                case .unavailable:
                    statuses[provider] = "keychain_failed"
                    failed += 1
                    continue
                }
            }
            if provider == .codex {
                do {
                    let envelope = CodexCredentialEnvelope(accessToken: credential.token,
                                                           accountId: credential.accountID)
                    try keychain.write(try envelope.encoded(),
                                       account: KeychainStore.codexEnvelopeAccount)
                    imported += 1
                    statuses[provider] = "imported"
                    board.invalidate(provider)
                } catch {
                    failed += 1
                    statuses[provider] = "keychain_failed"
                }
                continue
            }
            do {
                try keychain.write(credential.token, account: KeychainStore.tokenAccount(provider))
                imported += 1
                statuses[provider] = "imported"
                board.invalidate(provider)
            } catch {
                failed += 1
                statuses[provider] = "keychain_failed"
            }
        }
        lastKeychainError = failed > 0 ? keychainFailureMessage(.write) : nil
        lastImportSummary = Self.importSummary(imported: imported, failed: failed,
                                               skipped: import_.skippedEntries)
        if imported > 0 || failed > 0 {
            persistAndReload()
        }
        if imported > 0 && autoRefreshAfterImport {
            Task { await refreshAll() }
        }
        return statuses
    }

    private static func importSummary(imported: Int, failed: Int, skipped: [String]) -> String {
        var parts: [String] = ["Импортировано аккаунтов: \(imported)"]
        if failed > 0 {
            parts.append("не сохранено (Keychain): \(failed)")
        }
        if !skipped.isEmpty {
            parts.append("пропущено: \(skipped.joined(separator: ", "))")
        }
        if imported == 0 && failed == 0 {
            parts.append("знакомых аккаунтов в файле не найдено")
        }
        return parts.joined(separator: "; ")
    }

    /// Ручное обновление из панели (сливается с идущим проходом).
    func refreshNow() async {
        await refreshAll()
    }

    // MARK: Проход опроса

    func prepareForStdinImport() {
        loadLastGood()
    }

    private func loadLastGood() {
        switch store.read() {
        case .snapshot(let snapshot):
            // Строки без собственного credential не публикуются после
            // перезапуска (CR-01 п.3): фильтрует publishedRows(excluding:).
            let initial = Dictionary(uniqueKeysWithValues: snapshot.rows.map { ($0.providerID, $0) })
            board = ProviderRowBoard(rows: initial)
        case .missing, .corrupt, .unavailable:
            board = ProviderRowBoard()
        }
    }

    func refreshAll() async {
        // WR-04: запрос во время идущего прохода коалесцируется (begin=false)
        // и обслуживается ОДНИМ немедленным повторным проходом того же
        // await-цикла — без рекурсивного порождения задач и без параллельных
        // проходов. Новых запросов нет → цикл завершается (мёртвых циклов нет).
        guard gate.begin() else { return }
        isRefreshing = true
        while true {
            let now = Date()
            for provider in connectedProviders {
                await refresh(provider: provider, now: now)
            }
            persistAndReload()
            if !gate.end() { break }
        }
        isRefreshing = false
    }

    private func refresh(provider: ProviderID, now: Date) async {
        let epoch = board.currentEpoch(provider) // захвачено ДО чтения/запроса (CR-01)
        let spec: ProbeSpec
        switch provider {
        case .codex:
            // CR-02: чтение ТОЛЬКО атомарного конверта — token и accountId
            // берутся из ОДНОЙ записи одним decode; legacy-пара v3–v5 не
            // угадывается и не смешивается, HTTP по ней не выполняется никогда.
            let envelope: CodexCredentialEnvelope
            do {
                guard let stored = try keychain.read(account: KeychainStore.codexEnvelopeAccount) else {
                    // Конверта нет: если обнаружены свои legacy-слоты —
                    // фиксированная ошибка «нужен реимпорт» (видимо, без HTTP);
                    // иначе провайдер absent и отфильтрован из опроса списком.
                    if keychain.providerPresence(.codex) == .needsReimport {
                        board.applyFailure(provider, epoch: epoch,
                                           message: KeychainStore.codexReimportMessage, now: now)
                    }
                    return
                }
                envelope = try CodexCredentialEnvelope.decode(stored)
            } catch let error as KeychainError {
                // Недоступная Keychain: last-good остаётся, ошибка видна (FIX5).
                board.applyFailure(provider, epoch: epoch, message: error.message, now: now)
                return
            } catch {
                // Конверт повреждён/чужая схема — НЕ «account id отсутствует»:
                // фиксированная ошибка реимпорта, запрос не выполняется.
                board.applyFailure(provider, epoch: epoch,
                                   message: KeychainStore.codexReimportMessage, now: now)
                return
            }
            spec = CodexAdapter.buildProbe(token: envelope.accessToken,
                                           accountID: envelope.accountId)
        default:
            let token: String
            do {
                guard let stored = try keychain.read(account: KeychainStore.tokenAccount(provider)) else {
                    // Слот исчез между построением списка и опросом: строка уйдёт
                    // из публикации фильтром absent; опрашивать нечем.
                    return
                }
                token = stored
            } catch let error as KeychainError {
                // Недоступная Keychain: last-good остаётся, ошибка видна (FIX5).
                board.applyFailure(provider, epoch: epoch,
                                   message: error.message, now: now)
                return
            } catch {
                board.applyFailure(provider, epoch: epoch,
                                   message: keychainFailureMessage(.read), now: now)
                return
            }
            switch provider {
            case .kimi:
                spec = KimiAdapter.buildProbe(token: token)
            case .glmCN, .glmIntl:
                spec = GlmAdapter.buildProbe(token: token, provider: provider)
            case .openrouter:
                spec = OpenRouterAdapter.buildProbe(token: token)
            case .deepseek:
                spec = DeepSeekAdapter.buildProbe(token: token)
            case .codex:
                return // недостижимо: codex обработан выше
            }
        }
        let result = await fetcher.fetch(spec, expectedOrigin: provider.origin)
        // Guard актуальности: и успех, и ошибка устаревшего credential гасятся
        // (disconnect/replace/импорт во время запроса инвалидировали эпоху).
        guard board.currentEpoch(provider) == epoch else { return }
        switch result {
        case .failure(let failure):
            board.applyFailure(provider, epoch: epoch, message: failure.message, now: now)
        case .success((401, _)) where provider == .codex:
            // Протухший OAuth: один запуск codex CLI обновляет токен, затем реимпорт.
            board.applyFailure(provider, epoch: epoch,
                               message: "HTTP 401 — токен истёк. Запустите Codex CLI один раз и импортируйте auth.json заново.",
                               now: now)
        case .success((401, _)):
            board.applyFailure(provider, epoch: epoch, message: "HTTP 401 — проверьте ключ", now: now)
        case .success(let (status, data)):
            let body = data.flatMap { try? JSONSerialization.jsonObject(with: $0) }
            var parsed = false
            if provider.isBalanceProvider {
                let balance: BalanceParse?
                switch provider {
                case .openrouter: balance = OpenRouterAdapter.parse(status: status, body: body)
                case .deepseek: balance = DeepSeekAdapter.parse(status: status, body: body)
                default: balance = nil
                }
                if let balance {
                    board.applySuccess(provider, epoch: epoch, row: ProviderRow(
                        providerID: provider, displayName: provider.displayName,
                        balanceCurrency: balance.currency, balanceTotal: balance.totalBalance,
                        fetchedAt: now, error: nil, lastAttemptAt: now))
                    parsed = true
                }
            } else {
                let plan: PlanParse?
                switch provider {
                case .kimi: plan = KimiAdapter.parse(status: status, body: body)
                case .glmCN, .glmIntl: plan = GlmAdapter.parse(status: status, body: body)
                case .codex: plan = CodexAdapter.parse(status: status, body: body)
                default: plan = nil
                }
                if let plan {
                    board.applySuccess(provider, epoch: epoch, row: ProviderRow(
                        providerID: provider, displayName: provider.displayName,
                        planName: plan.planName, windows: plan.windows,
                        fetchedAt: now, error: nil, lastAttemptAt: now))
                    parsed = true
                }
            }
            // Отказ парсинга (success!=true, пустые окна, отсутствующие поля,
            // unknown ≠ 0): last-good сохраняется, ошибка пишется отдельно.
            if !parsed {
                board.applyFailure(provider, epoch: epoch,
                                   message: providerErrorMessage(status: status, body: body), now: now)
            }
        }
    }

    /// Записать снимок (единый писатель — приложение) и перезагрузить виджет
    /// ТОГО ЖЕ kind. Публикуются строки только не-absent провайдеров; опрос из
    /// активного приложения бюджет WidgetKit не тратит; reload — каждый проход.
    private func persistAndReload() {
        let snapshot = UsageSnapshot(rows: orderedRows, writtenAt: Date())
        do {
            try store.write(snapshot)
            cacheWriteFailed = false
            WidgetCenter.shared.reloadTimelines(ofKind: testWidgetKind)
        } catch {
            cacheWriteFailed = true
        }
    }
}

/// Explicit local authorization command; no source files, refresh tokens, UI,
/// timer, raw responses, account IDs or credential values enter the report.
@MainActor
enum CredentialStdinImport {
    static func run(model: UsageModel) async -> Int32 {
        let ownURL = Bundle.main.executableURL?.resolvingSymlinksInPath()
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "com.serzhsharapa.aiusage")
            .contains { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier &&
                $0.executableURL?.resolvingSymlinksInPath() == ownURL }
        guard !others else { return emitFailure("receiver_already_running") }
        let data: Data
        do {
            data = try CredentialImportFile.readBounded {
                try FileHandle.standardInput.read(upToCount: $0) ?? Data()
            }
        } catch { return emitFailure("invalid_input") }
        // Closed provider dictionary only; native file picker retains its formats.
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              !root.isEmpty,
              Set(root.keys).isSubset(of: ["openai", "glmodingplan", "kimi-coding", "openrouter", "deepseek"]) else {
            return emitFailure("invalid_input")
        }
        let imported = CredentialImportFile.parse(data: data)
        guard !imported.isEmpty else { return emitFailure("invalid_input") }
        model.prepareForStdinImport()
        let statuses = model.applyImport(imported, autoRefreshAfterImport: false,
            replaceExisting: ProcessInfo.processInfo.arguments.contains("--replace-existing"))
        // Exactly one explicit pass; no activate(), hence no automatic second pass.
        let passStart = Date()
        await model.refreshAll()
        var rows: [[String: Any]] = []
        for (provider, status) in statuses.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let row = model.orderedRows.first { $0.providerID == provider }
            let attempted = row?.lastAttemptAt.map { $0 >= passStart } == true
            var result: [String: Any] = ["provider": provider.rawValue, "import_status": status,
                "request_status": !attempted ? "not_requested" :
                    (row?.error == nil && row?.fetchedAt != nil ? "ok" : "failed")]
            if let row {
                result["needs_reauth"] = provider == .codex && row.error?.hasPrefix("HTTP 401") == true
                result["windows"] = row.windows.map { window -> [String: Any] in
                    var value: [String: Any] = [:]
                    if let percent = window.percent, percent.isFinite { value["percent"] = percent }
                    if let reset = window.resetsAt, let date = parseNormalizedISO(reset) {
                        value["resets_at"] = date.timeIntervalSince1970
                    }
                    return value
                }
                if let total = row.balanceTotal, let number = Double(total), number.isFinite {
                    result["balance"] = number
                }
                if let date = row.fetchedAt { result["fetched_at"] = date.timeIntervalSince1970 }
                if row.error != nil { result["error"] = "usage_request_failed" }
            }
            rows.append(result)
        }
        let report: [String: Any] = ["providers": rows, "cache_write_failed": model.cacheWriteFailed,
            "skipped_entries": imported.skippedEntries.count]
        guard let encoded = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) else {
            return emitFailure("report_failed")
        }
        FileHandle.standardOutput.write(encoded + Data([10]))
        return statuses.values.contains("imported") || statuses.values.allSatisfy({ $0 == "skipped_existing" }) ? 0 : 1
    }

    private static func emitFailure(_ code: String) -> Int32 {
        // Call sites pass literals only, never errors or input-derived strings.
        let data = try! JSONSerialization.data(withJSONObject: ["error": code])
        FileHandle.standardOutput.write(data + Data([10]))
        return 1
    }
}

// MARK: - Диагностика формы ответов (--debug-shape): лист структуры заменяется
// именем типа; значения (включая токены и проценты) не покидают память.
// Одноразовый CLI: без записи кэша, без activate() и таймеров.

extension UsageModel {
    func debugShapeMain() async -> Int32 {
        let providers: [ProviderID] = connectedProviders.isEmpty
            ? [.codex]
            : connectedProviders.sorted { $0.displayOrder < $1.displayOrder }
        var parts: [String] = []
        for provider in providers {
            let shape = await debugProbeShape(provider: provider)
            parts.append("\"\(provider.rawValue)\": \(shape)")
        }
        let output = "{\(parts.joined(separator: ","))}"
        FileHandle.standardOutput.write(Data(output.utf8) + Data([10]))
        return 0
    }

    /// Один проб указанного провайдера и форма его тела. Читает Keychain так
    /// же, как обычный проход; ответ уходит в память и схлопывается в типы.
    private func debugProbeShape(provider: ProviderID) async -> String {
        let spec: ProbeSpec
        switch provider {
        case .codex:
            guard let stored = try? keychain.read(account: KeychainStore.codexEnvelopeAccount),
                  let envelope = try? CodexCredentialEnvelope.decode(stored) else {
                return #"{"error":"no_envelope"}"#
            }
            spec = CodexAdapter.buildProbe(token: envelope.accessToken, accountID: envelope.accountId)
        default:
            guard let stored = try? keychain.read(account: KeychainStore.tokenAccount(provider)) else {
                return #"{"error":"no_token"}"#
            }
            switch provider {
            case .kimi: spec = KimiAdapter.buildProbe(token: stored)
            case .glmCN, .glmIntl: spec = GlmAdapter.buildProbe(token: stored, provider: provider)
            case .openrouter: spec = OpenRouterAdapter.buildProbe(token: stored)
            case .deepseek: spec = DeepSeekAdapter.buildProbe(token: stored)
            case .codex: return #"{"error":"unreachable"}"#
            }
        }
        let result = await fetcher.fetch(spec, expectedOrigin: provider.origin)
        switch result {
        case .failure: return #"{"error":"transport"}"#
        case .success(let (status, data)):
            let body = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? NSNull()
            var extra = ""
            if provider == .codex, let parsed = CodexAdapter.parse(status: status, body: body) {
                // Проценты/сбросы — данные самого владельца (видны и в UI);
                // нужны, чтобы сверить парсер с тем, что показывает Codex.
                let windows = parsed.windows.map { window -> String in
                    let percent = window.percent.map { "\($0)" } ?? "null"
                    let reset = window.resetsAt ?? "null"
                    return #"{"key":"\#(window.key)","percent":\#(percent),"resets_at":"\#(reset)"}"#
                }
                extra = #","parsed_windows":[\#(windows.joined(separator: ","))]"#
            }
            return #"{"status":"\#(status)","body":\#(Self.shapeJSON(body))\#(extra)}"#
        }
    }

    /// Рекурсивная замена листов типами; глубина и ширина ограничены.
    static func shapeJSON(_ value: Any, depth: Int = 0) -> String {
        if depth > 8 { return "\"…\"" }
        switch value {
        case let dict as [String: Any]:
            let keys = dict.keys.sorted().prefix(24)
            let inner = keys.map { key in
                "\"\(key)\": \(shapeJSON(dict[key] ?? NSNull(), depth: depth + 1))"
            }
            return "{\(inner.joined(separator: ","))}"
        case let array as [Any]:
            let items = array.prefix(6).map { shapeJSON($0, depth: depth + 1) }
            let suffix = array.count > 6 ? ",\"…(+\(array.count - 6))\"" : ""
            return "[\(items.joined(separator: ","))\(suffix)]"
        case is String: return "\"string\""
        case let number as NSNumber:
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? "bool" : "number"
        case is NSNull: return "null"
        default: return "\"\(type(of: value))\""
        }
    }
}
