import Foundation

// Quick 261018-jd8: чистые (без сети и Keychain) парсеры файлов-credential,
// которые владелец ЯВНО выбирает через NSOpenPanel либо передаёт явной
// локальной командой через bounded stdin pipe в app-таргете.
//
// Два поддержанных формата:
// 1) Codex CLI auth.json: {"tokens": {"access_token", "account_id", "refresh_token", ...}};
//    импортируются ТОЛЬКО access_token и account_id. Корневой OPENAI_API_KEY —
//    это API-ключ, не OAuth-токен подписки → отказ.
// 2) Kilo auth.json (публичная схема packages/opencode/src/auth/index.ts, проверена
//    координатором 18.10.2026): словарь providerID → {type: "api", key} |
//    {type: "oauth", access, refresh, expires, accountId?}. Маппинг:
//    openai(oauth) → codex; glmodingplan | zai-coding-cn(api) → glmCN;
//    zai | zai-coding(api) → glmIntl; kimi-coding(api) → kimi;
//    openrouter(api) → openrouter; deepseek(api) → deepseek.
//    refresh_token НИКОГДА не читается и не сохраняется; чужие/несогласованные
//    по type записи пропускаются (не угадываем). DSH YAML остаётся в отдельном
//    локальном Ruby helper: в приложение поступает только минимальный словарь.
//
// Все типы ниже не содержат секретов дольше вызова: результат сразу уходит в
// Keychain app-таргета; в снимок/логи эти значения попасть не могут по типу.

/// Импортированный credential одного провайдера.
public struct ImportedCredential: Equatable, Sendable {
    public let token: String
    public let accountID: String?

    public init(token: String, accountID: String? = nil) {
        self.token = token
        self.accountID = accountID
    }
}

// MARK: - Атомарный конверт credential Codex (CR-02)

/// Ошибка конверта Codex: запись НЕ трактуется как отсутствие credential —
/// corrupt/чужая схема = данные повреждены, требуется повторный импорт.
public enum CodexCredentialEnvelopeError: Error, Equatable, Sendable {
    case corrupt
    case unsupportedSchema(Int)
}

/// Атомарный конверт Codex (CR-02): access token + ОПЦИОНАЛЬНЫЙ account id —
/// ОДНА сериализованная единица, записываемая ОДНОЙ операцией SecItem
/// (update ИЛИ add), целиком или никак. Частичной пары «token B + account A»
/// не существует по построению; неуспешная запись оставляет прежнюю запись
/// нетронутой (SecItemUpdate с ошибкой предмет не меняет). `accountId == nil`
/// валиден только как ЯВНО отсутствующий ключ JSON (не подавленная ошибка);
/// чтение токена и account id для одного запроса происходит из ОДНОГО
/// декодированного конверта — смешение идентичностей исключено.
public struct CodexCredentialEnvelope: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public let schemaVersion: Int
    public let accessToken: String
    public let accountId: String?

    public init(accessToken: String, accountId: String?) {
        self.schemaVersion = Self.currentSchemaVersion
        self.accessToken = accessToken
        self.accountId = accountId
    }

    /// Каноническая сериализация (сортированные ключи) — одна строка для одной
    /// Keychain-записи. Секрет живёт только в этом вызове и в Keychain.
    public func encoded() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CodexCredentialEnvelopeError.corrupt
        }
        return string
    }

    /// Разбор записи. nil-пустота НЕ возвращается: любая ошибка — throws
    /// (отсутствие слота различается уровнем Keychain errSecItemNotFound).
    public static func decode(_ string: String) throws -> CodexCredentialEnvelope {
        guard let data = string.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(CodexCredentialEnvelope.self, from: data) else {
            throw CodexCredentialEnvelopeError.corrupt
        }
        guard envelope.schemaVersion == currentSchemaVersion else {
            throw CodexCredentialEnvelopeError.unsupportedSchema(envelope.schemaVersion)
        }
        guard !envelope.accessToken.isEmpty else {
            throw CodexCredentialEnvelopeError.corrupt
        }
        return envelope
    }
}

/// Результат разбора выбранного владельцем файла: провайдер → credential.
public struct CredentialImport: Equatable, Sendable {
    /// Найденные аккаунты по провайдерам (пустой — в файле нет знакомых).
    public let credentials: [ProviderID: ImportedCredential]
    /// Человекочитаемые имена пропущенных записей (без значений секретов).
    public let skippedEntries: [String]

    public init(credentials: [ProviderID: ImportedCredential], skippedEntries: [String] = []) {
        self.credentials = credentials
        self.skippedEntries = skippedEntries
    }

    public var isEmpty: Bool { credentials.isEmpty }
}

public enum CredentialImportFile {
    /// Разбор файла по формату: Codex auth.json (корневой объект с "tokens")
    /// или Kilo auth.json (словарь провайдеров). Никаких обращений к диску —
    /// только переданные Data. Бросать не должен: битый файл = пустой импорт.
    public static func parse(data: Data) -> CredentialImport {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return CredentialImport(credentials: [:])
        }
        // Формат Codex native опознаётся и по «tokens», и по корневому
        // OPENAI_API_KEY (который мы отвергаем как не-OAuth): словарь провайдеров
        // Kilo таких ключей не содержит никогда.
        if root["tokens"] is [String: Any] || root["OPENAI_API_KEY"] != nil {
            return parseCodexNative(root)
        }
        return parseProviderDictionary(root)
    }

    /// Codex CLI auth.json: импорт access_token + account_id; refresh_token не
    /// читается; корневой OPENAI_API_KEY — не OAuth → отказ (пустой импорт).
    private static func parseCodexNative(_ root: [String: Any]) -> CredentialImport {
        if str(root["OPENAI_API_KEY"]) != nil {
            return CredentialImport(credentials: [:], skippedEntries: ["OPENAI_API_KEY (API-ключ, не OAuth)"])
        }
        guard let tokens = root["tokens"] as? [String: Any],
              let accessToken = str(tokens["access_token"]) else {
            return CredentialImport(credentials: [:])
        }
        guard validAccountID(tokens["account_id"]) else {
            return CredentialImport(credentials: [:], skippedEntries: ["openai (неверный account ID)"])
        }
        let accountID = str(tokens["account_id"])
        return CredentialImport(credentials: [.codex: ImportedCredential(token: accessToken, accountID: accountID)])
    }

    /// Kilo auth.json: словарь providerID → {type, key|access, accountId?}.
    /// Согласованность type обязательна; refresh НЕ читается; неизвестные id
    /// и не-объекты пропускаются с записью имени (имя — не секрет).
    private static func parseProviderDictionary(_ root: [String: Any]) -> CredentialImport {
        // (ключ файла, допустимый type, целевой провайдер)
        let mapping: [(fileKey: String, kind: String, provider: ProviderID)] = [
            ("openai", "oauth", .codex),
            ("glmodingplan", "api", .glmCN),
            ("zai-coding-cn", "api", .glmCN),
            ("zai", "api", .glmIntl),
            ("zai-coding", "api", .glmIntl),
            ("kimi-coding", "api", .kimi),
            ("openrouter", "api", .openrouter),
            ("deepseek", "api", .deepseek),
        ]
        var credentials: [ProviderID: ImportedCredential] = [:]
        var skipped: [String] = []
        for (fileKey, kind, provider) in mapping {
            guard let entry = root[fileKey] else { continue }
            guard let row = entry as? [String: Any] else {
                skipped.append(fileKey)
                continue
            }
            guard str(row["type"]) == kind else {
                if row["type"] != nil { skipped.append("\(fileKey) (неожиданный type)") }
                continue
            }
            let token: String?
            var accountID: String? = nil
            if kind == "oauth" {
                guard validAccountID(row["accountId"]) else {
                    skipped.append("openai (неверный account ID)")
                    continue
                }
                token = str(row["access"])
                accountID = str(row["accountId"])
            } else {
                token = str(row["key"])
            }
            guard let token else {
                skipped.append("\(fileKey) (нет ключа)")
                continue
            }
            // Первый согласованный ключ выигрывает (повторная запись того же
            // провайдера не перетирает уже взятую — выбор детерминирован).
            if credentials[provider] == nil {
                credentials[provider] = ImportedCredential(token: token, accountID: accountID)
            }
        }
        return CredentialImport(credentials: credentials, skippedEntries: skipped)
    }

    private static func validAccountID(_ value: Any?) -> Bool {
        value == nil || value is NSNull || (value is String && str(value) != nil)
    }

    /// Bounded, EOF-driven pipe input. A short read is NOT EOF.
    public static func readBounded(read: (Int) throws -> Data) throws -> Data {
        var data = Data()
        while true {
            let chunk = try read(min(4096, 65_537 - data.count))
            if chunk.isEmpty { return data }
            guard data.count + chunk.count <= 65_536 else { throw StdinError.tooLarge }
            data.append(chunk)
        }
    }

    public enum StdinError: Error { case tooLarge }
}
