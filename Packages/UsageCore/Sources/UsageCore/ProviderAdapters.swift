import Foundation

// ============================================================================
// Порт адаптеров провайдеров из dsh-usage-hq (HQ-форк https://github.com/linxin666/dsh-usage),
// src/core/adapters.ts — Apache License 2.0. Portions adapted from the upstream
// TypeScript source; семантика парсеров воспроизведена 1:1 и зафиксирована
// фикстурными тестами (tests/kimi-usages.spec.ts перенесены дословно).
// Лицензионные файлы LICENSE/NOTICE ведёт координатор родительской сессии.
//
// Осознанные отклонения от апстрима (решение владельца, 2026-10-18):
// 1) OpenRouter: отсутствующий total_usage НЕ заменяется на 0 (в апстриме `?? 0`
//    — баг): неизвестный расход = отказ, last-good сохраняется (unknown ≠ 0).
// 2) Kimi usages-ветка: чтение limit_5h → «5h» — заголовочный комментарий
//    апстрима объявляет limit_5h, но код его не читал; дедуп против limits[]
//    сохранён (строка из limits[] побеждает).
// Перенесены ТОЛЬКО пять нужных провайдеров; moonshot/opencode-go/minimax/
// siliconflow/zenmux не портируются.
// ============================================================================

/// Идентификатор провайдера = ключ credential в Keychain и строка в снимке.
/// Каждый id несёт фиксированный origin — единственный хост, куда уходит токен.
public enum ProviderID: String, Codable, Sendable, CaseIterable, Hashable {
    case kimi
    case glmCN = "glm-cn"
    case glmIntl = "glm-intl"
    case codex
    case openrouter
    case deepseek
}

extension ProviderID {
    /// Статичное отображаемое имя провайдера (не данные аккаунта).
    public var displayName: String {
        switch self {
        case .kimi: return "Kimi"
        case .glmCN: return "GLM (CN)"
        case .glmIntl: return "GLM (Intl)"
        case .codex: return "Codex"
        case .openrouter: return "OpenRouter"
        case .deepseek: return "DeepSeek"
        }
    }

    /// Единственный допустимый origin (scheme + host) проб этого провайдера.
    public var origin: String {
        switch self {
        case .kimi: return "https://api.kimi.com"
        case .glmCN: return "https://open.bigmodel.cn"
        case .glmIntl: return "https://api.z.ai"
        case .codex: return "https://chatgpt.com"
        case .openrouter: return "https://openrouter.ai"
        case .deepseek: return "https://api.deepseek.com"
        }
    }

    /// Провайдер подписочных окон (Kimi/GLM/Codex) или баланса (OpenRouter/DeepSeek).
    public var isBalanceProvider: Bool {
        switch self {
        case .openrouter, .deepseek: return true
        case .kimi, .glmCN, .glmIntl, .codex: return false
        }
    }

    /// Фиксированный порядок отображения, заданный владельцем 20.10.2026:
    /// Codex → GLM → Kimi, балансы последними.
    public var displayOrder: Int {
        switch self {
        case .codex: return 0
        case .glmCN: return 1
        case .glmIntl: return 2
        case .kimi: return 3
        case .openrouter: return 10
        case .deepseek: return 11
        }
    }
}

/// Один HTTP-проб: фиксированный URL + строго заданные заголовки. Строится
/// ТОЛЬКО функциями ниже — токен никогда не попадает на чужой хост.
public struct ProbeSpec: Equatable, Sendable {
    public let url: String
    public let headers: [String: String]

    public init(url: String, headers: [String: String]) {
        self.url = url
        self.headers = headers
    }
}

/// Распарсенный план-квота (порт PlanParse).
public struct PlanParse: Equatable, Sendable {
    public let planName: String?
    public let windows: [UsageWindow]

    public init(planName: String? = nil, windows: [UsageWindow]) {
        self.planName = planName
        self.windows = windows
    }
}

/// Распарсенный баланс (порт BalanceParse).
public struct BalanceParse: Equatable, Sendable {
    public let currency: String
    public let totalBalance: String

    public init(currency: String, totalBalance: String) {
        self.currency = currency
        self.totalBalance = totalBalance
    }
}

// MARK: - Общие помощники (порт 1:1; nil ≠ 0 везде)

/// Число из JSON-значения: NSNumber (не Bool) или непустая строка-число; иначе nil.
func toNum(_ value: Any?) -> Double? {
    if let number = value as? NSNumber {
        // JSON true/false приходит NSNumber — в JS typeof boolean → undefined.
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }
    if let text = value as? String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let parsed = Double(trimmed), parsed.isFinite else { return nil }
        return parsed
    }
    return nil
}

/// Непустая строка (trimmed), иначе nil.
func str(_ value: Any?) -> String? {
    guard let text = value as? String else { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

/// Кламп процента в отображаемый диапазон 0…100.
func clampPercent(_ value: Double) -> Double {
    min(100, max(0, value))
}

/// Число двумя знаками (порт money/toFixed(2)).
func money(_ value: Double) -> String {
    String(format: "%.2f", value)
}

/// ISO 8601 с ровно тремя разрядами миллисекунд, UTC — как JS Date#toISOString.
func formatISOMilliseconds(_ date: Date) -> String {
    let milliseconds = date.timeIntervalSince1970 * 1000
    let rounded = (milliseconds).rounded()
    let wholeSeconds = Int(rounded / 1000)
    let fraction = Int(rounded.truncatingRemainder(dividingBy: 1000))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                             from: Date(timeIntervalSince1970: TimeInterval(wholeSeconds)))
    return String(
        format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
        components.year!, components.month!, components.day!,
        components.hour!, components.minute!, components.second!, fraction)
}

/// Эпоха (секунды/миллисекунды, число или строка-цифра) или ISO-строка →
/// нормализованный ISO 8601, иначе nil (порт toIso; эпоха < 1e12 → ×1000).
func toIso(_ value: Any?) -> String? {
    if let number = value as? NSNumber {
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        let raw = number.doubleValue
        guard raw.isFinite, raw > 0 else { return nil }
        let ms = raw < 1e12 ? raw * 1000 : raw
        let date = Date(timeIntervalSince1970: ms / 1000)
        return formatISOMilliseconds(date)
    }
    guard let text = str(value) else { return nil }
    // Эпохи приходят и строками («1756428000») — числовая ветка; /^\d+$/ апстрима — ASCII-цифры.
    if !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }) {
        return toIso(Double(text).map { NSNumber(value: $0) })
    }
    guard let date = parseNormalizedISO(text) else { return nil }
    return formatISOMilliseconds(date)
}

/// Разбор ISO 8601 (с дробными долями и без) для отображения resetsAt.
public func parseNormalizedISO(_ text: String) -> Date? {
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFraction.date(from: text) { return date }
    let plain = ISO8601DateFormatter()
    return plain.date(from: text)
}

/// Процент расхода с защитой нулевого/отсутствующего лимита (порт usedPercent).
func usedPercent(_ used: Any?, _ limit: Any?) -> Double? {
    guard let usedNum = toNum(used), let limitNum = toNum(limit), limitNum > 0 else { return nil }
    return clampPercent((usedNum / limitNum) * 100)
}

private func bearer(_ apiKey: String) -> [String: String] {
    ["authorization": "Bearer \(apiKey)"]
}

// MARK: - Kimi For Coding (порт KIMI_CODING)

public enum KimiAdapter {
    public static func buildProbe(token: String) -> ProbeSpec {
        ProbeSpec(url: "https://api.kimi.com/coding/v1/usages", headers: bearer(token))
    }

    /// limits[] → окна (5h при duration 300 + TIME_UNIT_MINUTE, иначе w-<duration>);
    /// usage → week; HQ usages-ветка → month/month-code (+5h) с used_ratio.
    /// Дедуп по key: строка из limits[] побеждает usages. Пусто → nil.
    public static func parse(status: Int, body: Any?) -> PlanParse? {
        guard status == 200, let root = body as? [String: Any] else { return nil }
        var windows: [UsageWindow] = []

        if let limits = root["limits"] as? [Any] {
            for entry in limits {
                guard let row = entry as? [String: Any],
                      let detail = row["detail"] as? [String: Any] else { continue }
                let window = row["window"] as? [String: Any]
                let duration = window.flatMap { toNum($0["duration"]) }
                let unit = window.flatMap { str($0["timeUnit"]) }
                let key: String
                if duration == 300 && unit == "TIME_UNIT_MINUTE" {
                    key = "5h"
                } else if let duration {
                    // JS template literal пишет число как есть: 300 → w-300, 300.5 → w-300.5.
                    key = duration == duration.rounded() ? "w-\(Int(duration))" : "w-\(duration)"
                } else {
                    key = "window"
                }
                windows.append(UsageWindow(
                    key: key,
                    name: str(detail["name"]),
                    percent: usedPercent(detail["used"], detail["limit"]),
                    resetsAt: toIso(detail["resetTime"])))
            }
        }

        if let weekly = root["usage"] as? [String: Any] {
            windows.append(UsageWindow(
                key: "week",
                name: "Weekly",
                percent: usedPercent(weekly["used"], weekly["limit"]),
                resetsAt: toIso(weekly["resetTime"])))
        }

        // HQ-ветка: usages с used_ratio (limit_5h/limit_month_total/limit_month_code).
        if let usages = root["usages"] as? [String: Any] {
            let fields: [(field: String, key: String, name: String?)] = [
                ("limit_5h", "5h", nil), // см. шапку: комментарий апстрима обещал, код не читал — читаем
                ("limit_month_total", "month", "Monthly"),
                ("limit_month_code", "month-code", "Monthly (code)"),
            ]
            for field in fields {
                guard let detail = usages[field.field] as? [String: Any],
                      let ratio = toNum(detail["used_ratio"]) else { continue }
                let percent = clampPercent((ratio * 100).rounded())
                if windows.contains(where: { $0.key == field.key }) { continue }
                windows.append(UsageWindow(
                    key: field.key,
                    name: field.name,
                    percent: percent,
                    resetsAt: toIso(detail["reset_time"])))
            }
        }

        guard !windows.isEmpty else { return nil }
        let membership = (root["user"] as? [String: Any])?["membership"] as? [String: Any]
        return PlanParse(planName: membership.flatMap { str($0["level"]) }, windows: windows)
    }
}

// MARK: - GLM Coding Plan (порт glmPlan; хост выбирается ProviderID)

public enum GlmAdapter {
    /// unit → ключ окна: 3 = 5h, 5 = month, 6 = week; неизвестный unit пропускается.
    static let unitKeys: [Int: String] = [3: "5h", 5: "month", 6: "week"]

    public static func buildProbe(token: String, provider: ProviderID) -> ProbeSpec {
        let host: String
        switch provider {
        case .glmCN: host = "open.bigmodel.cn"
        case .glmIntl: host = "api.z.ai"
        default: host = "open.bigmodel.cn"
        }
        // Авторизация — СЫРОЙ ключ без префикса Bearer (семантика апстрима).
        return ProbeSpec(
            url: "https://\(host)/api/monitor/usage/quota/limit",
            headers: ["authorization": token, "accept-language": "en-US,en"])
    }

    /// success==true обязателен; TIME_LIMIT (MCP-квота) пропускается;
    /// TOKENS_LIMIT → percentage; CREDIT_LIMIT → currentValue/usage иначе percentage.
    public static func parse(status: Int, body: Any?) -> PlanParse? {
        guard status == 200, let root = body as? [String: Any],
              root["success"] as? Bool == true,
              let data = root["data"] as? [String: Any],
              let limits = data["limits"] as? [Any] else { return nil }
        var windows: [UsageWindow] = []
        for entry in limits {
            guard let row = entry as? [String: Any] else { continue }
            let kind = str(row["type"])
            if kind == "TIME_LIMIT" { continue }
            guard let unitNumber = toNum(row["unit"]),
                  let unitKey = Int(exactly: unitNumber).flatMap({ unitKeys[$0] }) else { continue }
            if kind != "TOKENS_LIMIT" && kind != "CREDIT_LIMIT" { continue }
            let percent: Double?
            if kind == "CREDIT_LIMIT" {
                percent = creditPercent(row)
            } else {
                percent = toNum(row["percentage"]).map { clampPercent($0) }
            }
            windows.append(UsageWindow(key: unitKey, percent: percent, resetsAt: toIso(row["nextResetTime"])))
        }
        guard !windows.isEmpty else { return nil }
        return PlanParse(planName: str(data["level"]), windows: windows)
    }

    /// Точный процент кредитной строки: currentValue/usage, иначе процент провайдера.
    private static func creditPercent(_ row: [String: Any]) -> Double? {
        if let used = toNum(row["currentValue"]), let limit = toNum(row["usage"]), limit > 0 {
            return clampPercent((used / limit) * 100)
        }
        return toNum(row["percentage"]).map { clampPercent($0) }
    }
}

// MARK: - OpenAI Codex (порт OPENAI_CODEX; OAuth-токен из импорта auth.json)

public enum CodexAdapter {
    public static func buildProbe(token: String, accountID: String?) -> ProbeSpec {
        var headers: [String: String] = [
            "authorization": "Bearer \(token)",
            "user-agent": "codex-cli",
            "accept": "application/json",
        ]
        if let accountID {
            headers["chatgpt-account-id"] = accountID
        }
        return ProbeSpec(url: "https://chatgpt.com/backend-api/wham/usage", headers: headers)
    }

    /// rate_limit.primary_window/secondary_window; 401/не-200 → nil
    /// (протухший OAuth: один запуск codex CLI обновляет токен, затем реимпорт).
    public static func parse(status: Int, body: Any?) -> PlanParse? {
        guard status == 200, let root = body as? [String: Any],
              let rateLimit = root["rate_limit"] as? [String: Any] else { return nil }
        let rows: [[String: Any]] = [rateLimit["primary_window"], rateLimit["secondary_window"]]
            .compactMap { $0 as? [String: Any] }
        var windows: [UsageWindow] = []
        for row in rows {
            guard let percent = toNum(row["used_percent"]) else { continue }
            windows.append(UsageWindow(
                key: windowKey(toNum(row["limit_window_seconds"])),
                percent: clampPercent(percent),
                resetsAt: toIso(row["reset_at"])))
        }
        guard !windows.isEmpty else { return nil }
        return PlanParse(windows: windows)
    }

    /// Длина окна в секундах → словарный ключ (18000=5h, 604800=week, 2592000=month).
    private static func windowKey(_ seconds: Double?) -> String {
        guard let seconds else { return "window" }
        if seconds == 18_000 { return "5h" }
        if seconds == 604_800 { return "week" }
        if seconds == 2_592_000 { return "month" }
        let hours = seconds / 3600
        return hours >= 24 ? "\(Int((hours / 24).rounded()))_day" : "\(Int(hours.rounded()))_hour"
    }
}

// MARK: - OpenRouter (порт OPENROUTER; HQ-правка: unknown ≠ 0)

public enum OpenRouterAdapter {
    public static func buildProbe(token: String) -> ProbeSpec {
        ProbeSpec(url: "https://openrouter.ai/api/v1/credits", headers: bearer(token))
    }

    /// balance = total_credits − total_usage (USD, 2 знака). total_usage
    /// ОБЯЗАТЕЛЕН: отсутствующий расход — неизвестность, а не 0 (отклонение от
    /// бага апстрима `?? 0` по решению владельца) → nil, last-good сохраняется.
    public static func parse(status: Int, body: Any?) -> BalanceParse? {
        guard status == 200, let root = body as? [String: Any],
              let data = root["data"] as? [String: Any],
              let credits = toNum(data["total_credits"]),
              let used = toNum(data["total_usage"]) else { return nil }
        return BalanceParse(currency: "USD", totalBalance: money(credits - used))
    }
}

// MARK: - DeepSeek (порт DEEPSEEK)

public enum DeepSeekAdapter {
    public static func buildProbe(token: String) -> ProbeSpec {
        ProbeSpec(url: "https://api.deepseek.com/user/balance", headers: bearer(token))
    }

    /// Первый balance_info: currency + total_balance (строки, оба обязательны).
    public static func parse(status: Int, body: Any?) -> BalanceParse? {
        guard status == 200, let root = body as? [String: Any],
              let infos = root["balance_infos"] as? [Any], let first = infos.first,
              let row = first as? [String: Any],
              let currency = str(row["currency"]),
              let total = str(row["total_balance"]) else { return nil }
        return BalanceParse(currency: currency, totalBalance: total)
    }
}

// MARK: - Сообщение об ошибке провайдера (WR-01: без произвольного текста)

/// Фиксированная строка «HTTP <статус>» — и ТОЛЬКО она. Произвольный text
/// провайдера (message/msg/error.message) сознательно НЕ переносится: он
/// контролируется чужим сервером и может содержать эхо ключа/Bearer/account id;
/// усечение длины не редактирует содержание (WR-01). Детали — по статусу и
/// фиксированным строкам транспорта в app-таргете.
public func providerErrorMessage(status: Int, body: Any?) -> String {
    _ = body // тело не читается: любой message отбрасывается целиком
    return "HTTP \(status)"
}
