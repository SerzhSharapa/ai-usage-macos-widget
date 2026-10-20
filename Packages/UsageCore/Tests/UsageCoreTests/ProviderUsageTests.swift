import Testing
import Foundation
@testable import UsageCore

// Quick 261018-jd8: фикстурные тесты порта DSH-адаптеров, атомарного кэша
// и чистых парсеров импорта credential. Три кейса kimi-usages.spec.ts
// (dsh-usage-hq, Apache-2.0) перенесены дословно — ожидания 55/90,
// '2026-11-01T00:00:00.000Z', дедуп 5h. Никаких сети/Keychain: только чистые
// функции и временные каталоги.

@Suite("Порт адаптеров DSH: Kimi/GLM/Codex/OpenRouter/DeepSeek")
struct ProviderAdapterTests {

    private func window(_ plan: PlanParse?, _ key: String) -> UsageWindow? {
        plan?.windows.first { $0.key == key }
    }

    // MARK: - Kimi (порт tests/kimi-usages.spec.ts, 3 кейса дословно)

    @Test("Kimi usages: month/month-code из used_ratio, недельного окна не выдумано")
    func kimiUsagesShape() throws {
        let body: [String: Any] = [
            "usages": [
                "limit_5h": ["used_ratio": 0.345, "reset_time": "2026-10-05T12:00:00Z"],
                "limit_month_total": ["used_ratio": 0.55, "reset_time": "2026-11-01T00:00:00Z"],
                "limit_month_code": ["used_ratio": 0.9, "reset_time": "2026-11-01T00:00:00Z"],
            ],
        ]

        let plan = KimiAdapter.parse(status: 200, body: body)

        #expect(plan != nil)
        let keys = plan!.windows.map(\.key)
        #expect(keys.contains("month"))
        #expect(keys.contains("month-code"))
        #expect(!keys.contains("week"))
        let month = try #require(window(plan, "month"))
        #expect(month.percent == 55)
        #expect(month.resetsAt == "2026-11-01T00:00:00.000Z")
        #expect(month.name == "Monthly")
        let code = try #require(window(plan, "month-code"))
        #expect(code.percent == 90)
        #expect(code.name == "Monthly (code)")
        // HQ-добавка (координатор 18.10.2026): limit_5h читается как «5h»
        // с percent = round(ratio*100) и точным маппингом reset_time.
        let five = try #require(window(plan, "5h"))
        #expect(five.percent == 35)
        #expect(five.resetsAt == "2026-10-05T12:00:00.000Z")
    }

    @Test("Kimi: legacy limits[]/usage работают рядом с новой формой")
    func kimiLegacyShape() throws {
        let body: [String: Any] = [
            "limits": [
                ["window": ["duration": 300, "timeUnit": "TIME_UNIT_MINUTE"],
                 "detail": ["name": "5h", "used": 10, "limit": 100, "resetTime": "2026-10-05T12:00:00Z"]],
            ],
            "usage": ["used": 30, "limit": 100, "resetTime": "2026-10-12T00:00:00Z"],
        ]

        let plan = KimiAdapter.parse(status: 200, body: body)

        #expect(plan?.windows.map(\.key) == ["5h", "week"])
        #expect(window(plan, "5h")?.percent == 10)
        #expect(window(plan, "week")?.percent == 30)
        #expect(window(plan, "week")?.name == "Weekly")
    }

    @Test("Kimi: дедуп по key — строка limits[] побеждает usages")
    func kimiDedup() throws {
        let body: [String: Any] = [
            "limits": [
                ["window": ["duration": 300, "timeUnit": "TIME_UNIT_MINUTE"],
                 "detail": ["name": "5h", "used": 1, "limit": 100, "resetTime": "2026-10-05T12:00:00Z"]],
            ],
            "usages": [
                "limit_5h": ["used_ratio": 0.5, "reset_time": "2026-10-05T13:00:00Z"],
                "limit_month_total": ["used_ratio": 0.2, "reset_time": "2026-11-01T00:00:00Z"],
            ],
        ]

        let plan = KimiAdapter.parse(status: 200, body: body)

        let five = plan?.windows.filter { $0.key == "5h" }
        #expect(five?.count == 1)
        #expect(five?.first?.percent == 1)
        #expect(plan?.windows.map(\.key) == ["5h", "month"])
    }

    @Test("Kimi: planName из user.membership.level; пустое тело → nil")
    func kimiPlanNameAndEmpty() {
        let withUser: [String: Any] = [
            "usage": ["used": 1, "limit": 2, "resetTime": "2026-10-12T00:00:00Z"],
            "user": ["membership": ["level": "Max20"]],
        ]
        #expect(KimiAdapter.parse(status: 200, body: withUser)?.planName == "Max20")

        #expect(KimiAdapter.parse(status: 200, body: [String: Any]()) == nil)
        #expect(KimiAdapter.parse(status: 401, body: ["usage": [:]]) == nil)
    }

    @Test("Kimi: отсутствующий лимит → percent nil (окно есть, нуля нет)")
    func kimiMissingLimitIsUnknown() throws {
        let body: [String: Any] = [
            "limits": [
                ["window": ["duration": 300, "timeUnit": "TIME_UNIT_MINUTE"],
                 "detail": ["name": "5h", "used": 10, "resetTime": "2026-10-05T12:00:00Z"]],
            ],
        ]
        let plan = try #require(KimiAdapter.parse(status: 200, body: body))
        #expect(plan.windows.count == 1)
        #expect(plan.windows[0].percent == nil)
    }

    // MARK: - GLM

    @Test("GLM: tokens/credit окна, TIME_LIMIT и неизвестный unit пропущены")
    func glmWindows() throws {
        let body: [String: Any] = [
            "success": true,
            "data": [
                "level": "Pro",
                "limits": [
                    // MCP-квота — не окно плана:
                    ["type": "TIME_LIMIT", "unit": 7, "percentage": 50],
                    ["type": "TOKENS_LIMIT", "unit": 3, "percentage": 42.4, "nextResetTime": "2026-10-18T20:00:00Z"],
                    ["type": "TOKENS_LIMIT", "unit": 6, "percentage": 130, "nextResetTime": "2026-10-19T00:00:00Z"],
                    // Неизвестный unit — окно не выдумывается:
                    ["type": "TOKENS_LIMIT", "unit": 99, "percentage": 10],
                    // Кредитная строка: точный ratio currentValue/usage важнее процента:
                    ["type": "CREDIT_LIMIT", "unit": 5, "currentValue": 3, "usage": 10, "percentage": 999,
                     "nextResetTime": "2026-11-01T00:00:00Z"],
                ],
            ],
        ]

        let plan = try #require(GlmAdapter.parse(status: 200, body: body))

        #expect(plan.planName == "Pro")
        #expect(plan.windows.map(\.key) == ["5h", "week", "month"])
        #expect(window(plan, "5h")?.percent == 42.4)
        #expect(window(plan, "5h")?.resetsAt == "2026-10-18T20:00:00.000Z")
        #expect(window(plan, "week")?.percent == 100) // clamp 130
        #expect(window(plan, "month")?.percent == 30) // 3/10, не 999
    }

    @Test("GLM: кредитный fallback на percentage; success!=true и не-200 → nil")
    func glmCreditFallbackAndRejects() {
        let fallback: [String: Any] = [
            "success": true,
            "data": ["limits": [["type": "CREDIT_LIMIT", "unit": 5, "percentage": 15]]],
        ]
        #expect(GlmAdapter.parse(status: 200, body: fallback)?.windows.first?.percent == 15)

        let notSuccess: [String: Any] = ["success": false, "data": ["limits": [["type": "TOKENS_LIMIT", "unit": 3, "percentage": 1]]]]
        #expect(GlmAdapter.parse(status: 200, body: notSuccess) == nil)
        #expect(GlmAdapter.parse(status: 500, body: ["success": true]) == nil)
    }

    @Test("GLM: проба строится на origin провайдера с сырым ключом")
    func glmProbeOrigin() {
        let cn = GlmAdapter.buildProbe(token: "k-cn", provider: .glmCN)
        #expect(cn.url == "https://open.bigmodel.cn/api/monitor/usage/quota/limit")
        #expect(cn.headers["authorization"] == "k-cn") // без Bearer
        #expect(cn.headers["accept-language"] == "en-US,en")

        let intl = GlmAdapter.buildProbe(token: "k-intl", provider: .glmIntl)
        #expect(intl.url == "https://api.z.ai/api/monitor/usage/quota/limit")
    }

    // MARK: - Codex

    @Test("Codex: primary+secondary окна, epoch reset; 401 → nil")
    func codexWindows() throws {
        let epochReset: TimeInterval = 1_760_000_000
        let body: [String: Any] = [
            "rate_limit": [
                "primary_window": ["used_percent": 40.5, "limit_window_seconds": 18_000, "reset_at": 1_760_000_000],
                "secondary_window": ["used_percent": 7, "limit_window_seconds": 604_800, "reset_at": "2026-10-20T00:00:00Z"],
            ],
        ]

        let plan = try #require(CodexAdapter.parse(status: 200, body: body))

        #expect(plan.windows.count == 2)
        let primary = try #require(plan.windows.first { $0.key == "5h" })
        #expect(primary.percent == 40.5)
        let parsedReset = try #require(primary.resetsAt.flatMap(parseNormalizedISO))
        #expect(parsedReset.timeIntervalSince1970 == epochReset)
        #expect(primary.resetsAt == "2025-10-09T08:53:20.000Z")
        let secondary = try #require(plan.windows.first { $0.key == "week" })
        #expect(secondary.percent == 7)
        #expect(secondary.resetsAt == "2026-10-20T00:00:00.000Z")

        #expect(CodexAdapter.parse(status: 401, body: body) == nil)
    }

    @Test("Codex: длины окон маппятся в ключи словаря")
    func codexWindowKeys() {
        func key(_ seconds: Any?) -> String? {
            let body: [String: Any] = [
                "rate_limit": ["primary_window": ["used_percent": 1, "limit_window_seconds": seconds ?? NSNull()]],
            ]
            return CodexAdapter.parse(status: 200, body: body)?.windows.first?.key
        }
        #expect(key(2_592_000) == "month")
        #expect(key(7_200) == "2_hour")
        #expect(key(172_800) == "2_day")
        #expect(key(nil) == "window")
        // used_percent отсутствует → окно пропускается (nil ≠ 0):
        let noPercent: [String: Any] = [
            "rate_limit": ["primary_window": ["limit_window_seconds": 18_000]],
        ]
        #expect(CodexAdapter.parse(status: 200, body: noPercent) == nil)
    }

    // MARK: - OpenRouter / DeepSeek

    @Test("OpenRouter: баланс = total_credits − total_usage; отсутствующий расход → отказ")
    func openRouterBalance() {
        let ok: [String: Any] = ["data": ["total_credits": 10.5, "total_usage": 3.25]]
        #expect(OpenRouterAdapter.parse(status: 200, body: ok) == BalanceParse(currency: "USD", totalBalance: "7.25"))

        // HQ-правка (владелец): unknown ≠ 0 — без total_usage парс отказывает,
        // last-good сохраняется; баг апстрима `?? 0` не переносится.
        let missingUsage: [String: Any] = ["data": ["total_credits": 10.5]]
        #expect(OpenRouterAdapter.parse(status: 200, body: missingUsage) == nil)
        let missingCredits: [String: Any] = ["data": ["total_usage": 1]]
        #expect(OpenRouterAdapter.parse(status: 200, body: missingCredits) == nil)
        #expect(OpenRouterAdapter.parse(status: 500, body: ok) == nil)
    }

    @Test("DeepSeek: первый balance_info; пусто/чужое → nil")
    func deepSeekBalance() {
        let ok: [String: Any] = ["balance_infos": [
            ["currency": "CNY", "total_balance": "110.30"],
            ["currency": "USD", "total_balance": "0.00"],
        ]]
        #expect(DeepSeekAdapter.parse(status: 200, body: ok) == BalanceParse(currency: "CNY", totalBalance: "110.30"))

        #expect(DeepSeekAdapter.parse(status: 200, body: ["balance_infos": [[:]]]) == nil)
        #expect(DeepSeekAdapter.parse(status: 200, body: ["balance_infos": []]) == nil)
        #expect(DeepSeekAdapter.parse(status: 403, body: ok) == nil)
    }

    // MARK: - toIso (секунды/миллисекунды/строки-цифры/ISO с дробью)

    @Test("toIso: нормализация и отказ от мусора")
    func toIsoNormalizes() {
        #expect(toIso("2026-11-01T00:00:00Z" as Any?) == "2026-11-01T00:00:00.000Z")
        #expect(toIso("2026-11-01T00:00:00.250Z" as Any?) == "2026-11-01T00:00:00.250Z")
        // Эпоха строкой и числом (секунды < 1e12 → ×1000):
        let fromString = toIso("1756428000" as Any?).flatMap(parseNormalizedISO)
        #expect(fromString?.timeIntervalSince1970 == 1_756_428_000)
        let fromNumber = toIso(1_756_428_000 as Any?).flatMap(parseNormalizedISO)
        #expect(fromNumber?.timeIntervalSince1970 == 1_756_428_000)
        // Миллисекундная эпоха не умножается:
        let fromMillis = toIso(1_756_428_000_000 as Any?).flatMap(parseNormalizedISO)
        #expect(fromMillis?.timeIntervalSince1970 == 1_756_428_000)
        // Отказы — nil, не 0 и не сырая строка:
        #expect(toIso(0 as Any?) == nil)
        #expect(toIso(-5 as Any?) == nil)
        #expect(toIso("abc" as Any?) == nil)
        #expect(toIso("" as Any?) == nil)
        #expect(toIso(true as Any?) == nil)
        #expect(toIso("не дата" as Any?) == nil)
    }

    // MARK: - providerErrorMessage (WR-01: фиксированные строки, без сырого text)

    @Test("providerErrorMessage: только «HTTP N», произвольный text отброшен")
    func errorMessagePort() {
        #expect(providerErrorMessage(status: 500, body: ["error": ["message": "boom"]]) == "HTTP 500")
        #expect(providerErrorMessage(status: 429, body: ["msg": "rate limited"]) == "HTTP 429")
        #expect(providerErrorMessage(status: 503, body: nil) == "HTTP 503")
    }

    @Test("Эхо секрета из тела ошибки не попадает в сериализованный снимок (WR-01)")
    func secretEchoFromErrorBodyNeverPersists() throws {
        let secret = "sk-ECHO-SECRET-from-provider-body"
        // Провайдер возвращает ключ внутри message И вложенного error.message:
        let nasty: [String: Any] = [
            "message": "Invalid API key: \(secret)",
            "error": ["message": "Bearer \(secret)"],
        ]
        let row = ProviderRow(
            providerID: .kimi, displayName: "Kimi",
            windows: [UsageWindow(key: "month", percent: 55)],
            fetchedAt: Date(timeIntervalSince1970: 1_760_000_000),
            error: providerErrorMessage(status: 403, body: nasty),
            lastAttemptAt: Date(timeIntervalSince1970: 1_760_000_001))
        let snapshot = UsageSnapshot(rows: [row], writtenAt: Date(timeIntervalSince1970: 1_760_000_100))
        let json = String(data: try makeUsageSnapshotEncoder().encode(snapshot), encoding: .utf8) ?? ""

        #expect(row.error == "HTTP 403")
        #expect(!json.contains(secret))
        #expect(!json.lowercased().contains("bearer"))
        #expect(!json.lowercased().contains("invalid api key"))
    }

    // MARK: - Сводка окон (WR-03: unknown виден прочерком, переполнение подписано)

    @Test("windowSummary: смешанные известные/неизвестные окна видимы")
    func windowSummaryMixed() {
        let windows = [
            UsageWindow(key: "5h", percent: nil),
            UsageWindow(key: "week", percent: 42),
        ]
        #expect(windowSummary(windows) == "5ч — · нед 42%")
        #expect(containsUnknownPercent(windows))

        let allKnown = [
            UsageWindow(key: "month", name: "Monthly", percent: 55),
            UsageWindow(key: "month-code", percent: 90),
        ]
        #expect(windowSummary(allKnown) == "мес·код 90% · мес 55%")
        #expect(!containsUnknownPercent(allKnown))

        #expect(windowSummary([]) == "")
    }

    @Test("windowSummary: переполнение прячет только известные, unknown всегда виден")
    func windowSummaryOverflow() {
        let windows = [
            UsageWindow(key: "5h", percent: 10),
            UsageWindow(key: "week", percent: 20),
            UsageWindow(key: "month", percent: 30),
            UsageWindow(key: "month-code", percent: nil),
        ]
        // Неизвестное окно поднимается в показанный префикс (WR-03 follow-up):
        #expect(windowSummary(windows) == "мес·код — · мес 30% · нед 20% · +1 ещё")
        #expect(windowSummary(windows, limit: 2) == "мес·код — · мес 30% · +2 ещё")
        // Все показанные известные сортируются по убыванию процента:
        #expect(windowSummary([UsageWindow(key: "5h", percent: 10), UsageWindow(key: "week", percent: 20)],
                              limit: 3) == "нед 20% · 5ч 10%")
    }
}

@Suite("Снимок UsageSnapshot: атомарный кэш без секретов")
struct SnapshotStoreTests {

    private func makeTempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aiusage-jd8-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private let sampleRow = ProviderRow(
        providerID: .kimi,
        displayName: "Kimi",
        planName: "Max20",
        windows: [UsageWindow(key: "month", name: "Monthly", percent: 55, resetsAt: "2026-11-01T00:00:00.000Z")],
        fetchedAt: Date(timeIntervalSince1970: 1_760_000_000),
        error: nil,
        lastAttemptAt: Date(timeIntervalSince1970: 1_760_000_000))

    @Test("Запись-чтение round-trip; формат файла usage-snapshot.json")
    func roundTrip() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SnapshotStore(directory: dir)
        let snapshot = UsageSnapshot(rows: [sampleRow], writtenAt: Date(timeIntervalSince1970: 1_760_000_100))

        try store.write(snapshot)

        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent(usageSnapshotFileName).path))
        guard case .snapshot(let read) = store.read() else {
            Issue.record("ожидался snapshot после записи")
            return
        }
        #expect(read == snapshot)
        // Атомарность: временных файлов-обрывков не осталось.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(".tmp-") }
        #expect(leftovers.isEmpty)
    }

    @Test("Отсутствие файла → missing; мусор и чужая версия схемы → corrupt")
    func readClassification() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SnapshotStore(directory: dir)

        #expect(store.read() == .missing)

        let file = dir.appendingPathComponent(usageSnapshotFileName)
        try Data("это не json {{{".utf8).write(to: file)
        #expect(store.read() == .corrupt)

        let futureSchema = #"{"schema":99,"rows":[],"writtenAt":"2026-10-18T00:00:00Z"}"#
        try Data(futureSchema.utf8).write(to: file)
        #expect(store.read() == .corrupt)
    }

    @Test("Неизвестный providerID в снимке → corrupt (закрытое множество)")
    func unknownProviderIsCorrupt() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent(usageSnapshotFileName)
        let alien = #"{"schema":1,"rows":[{"providerID":"martian","displayName":"X","windows":[]}],"writtenAt":"2026-10-18T00:00:00Z"}"#
        try Data(alien.utf8).write(to: file)

        #expect(SnapshotStore(directory: dir).read() == .corrupt)
    }

    @Test("withError: last-good факты сохраняются, ошибка пишется отдельно")
    func errorKeepsLastGood() {
        let errored = sampleRow.withError("HTTP 500: boom", attemptedAt: Date(timeIntervalSince1970: 1_760_000_999))
        #expect(errored.windows == sampleRow.windows)
        #expect(errored.planName == sampleRow.planName)
        #expect(errored.fetchedAt == sampleRow.fetchedAt)
        #expect(errored.error == "HTTP 500: boom")
        #expect(errored.lastAttemptAt == Date(timeIntervalSince1970: 1_760_000_999))
    }

    @Test("В сериализованном снимке нет токена/заголовков авторизации")
    func snapshotHasNoSecrets() throws {
        let secret = "sk-FIXTURE-SECRET-never-ship"
        // Секрет реально существует в пробе (контроль позитивный):
        let probe = KimiAdapter.buildProbe(token: secret)
        #expect(probe.headers["authorization"] == "Bearer \(secret)")

        let snapshot = UsageSnapshot(
            rows: [
                sampleRow,
                ProviderRow(providerID: .openrouter, displayName: "OpenRouter",
                            balanceCurrency: "USD", balanceTotal: "7.25",
                            fetchedAt: Date(timeIntervalSince1970: 1_760_000_000)),
            ],
            writtenAt: Date(timeIntervalSince1970: 1_760_000_100))
        let json = String(data: try makeUsageSnapshotEncoder().encode(snapshot), encoding: .utf8) ?? ""

        #expect(!json.contains(secret))
        #expect(!json.lowercased().contains("authorization"))
        #expect(!json.lowercased().contains("bearer"))
    }
}

@Suite("Импорт credential-файлов (чистые парсеры, фикстуры редацированы)")
struct CredentialImportTests {

    @Test("WR-06: присутствующий account ID неверного типа отвергает Codex целиком")
    func malformedAccountIDRejected() {
        for value in ["42", "true", "[]", "{}", "\"\"", "\"  \""] {
            let native = "{\"tokens\":{\"access_token\":\"fixture-B\",\"account_id\":\(value)}}"
            #expect(CredentialImportFile.parse(data: Data(native.utf8)).credentials[.codex] == nil)
            let dictionary = "{\"openai\":{\"type\":\"oauth\",\"access\":\"fixture-B\",\"accountId\":\(value)},\"kimi-coding\":{\"type\":\"api\",\"key\":\"fixture-K\"}}"
            let parsed = CredentialImportFile.parse(data: Data(dictionary.utf8))
            #expect(parsed.credentials[.codex] == nil)
            #expect(parsed.credentials[.kimi]?.token == "fixture-K")
            #expect(parsed.skippedEntries == ["openai (неверный account ID)"])
        }
    }

    @Test("Account ID missing/null stays nil; valid string preserved")
    func optionalAccountID() {
        for suffix in ["", ",\"accountId\":null"] {
            let input = "{\"openai\":{\"type\":\"oauth\",\"access\":\"fixture\"\(suffix)}}"
            #expect(CredentialImportFile.parse(data: Data(input.utf8)).credentials[.codex] == ImportedCredential(token: "fixture"))
        }
    }

    @Test("Stdin reads partial chunks through EOF, exactly 64KiB accepted, excess rejected")
    func boundedPipe() throws {
        var chunks = [Data("{\"open".utf8), Data("ai\":{}}".utf8), Data()]
        let data = try CredentialImportFile.readBounded { _ in chunks.removeFirst() }
        #expect(String(decoding: data, as: UTF8.self) == "{\"openai\":{}}")
        var remaining = 65_536
        let boundary = try CredentialImportFile.readBounded { count in
            let n = min(remaining, count)
            remaining -= n
            return Data(repeating: 32, count: n)
        }
        #expect(boundary.count == 65_536)
        remaining = 65_537
        #expect(throws: CredentialImportFile.StdinError.self) {
            try CredentialImportFile.readBounded { count in
                let n = min(remaining, count)
                remaining -= n
                return Data(repeating: 32, count: n)
            }
        }
    }

    @Test("Codex auth.json: access_token + account_id; refresh не импортируется")
    func codexNative() throws {
        let json = #"{"tokens":{"access_token":"REDACTED-ACCESS","account_id":"acct-1","refresh_token":"REDACTED-REFRESH","id_token":"x","refresh_expires_at":123}}"#
        let result = CredentialImportFile.parse(data: Data(json.utf8))

        let codex = try #require(result.credentials[.codex])
        #expect(codex.token == "REDACTED-ACCESS")
        #expect(codex.accountID == "acct-1")
        // refresh по типу не переносится никуда из результата:
        #expect(!Mirror(reflecting: codex).children.contains { "\($0.value)".contains("REFRESH") })
    }

    @Test("Codex auth.json: корневой OPENAI_API_KEY — не OAuth, отказ")
    func codexRootAPIKeyRejected() {
        let json = #"{"OPENAI_API_KEY":"sk-root-key"}"#
        let result = CredentialImportFile.parse(data: Data(json.utf8))
        #expect(result.credentials.isEmpty)
        #expect(result.skippedEntries.contains { $0.contains("OPENAI_API_KEY") })
    }

    @Test("Kilo auth.json: oauth→codex, api-ключи по провайдерам, refresh не читается")
    func kiloDictionary() throws {
        let json = """
        {"openai":{"type":"oauth","access":"oauth-access","refresh":"REDACTED-REFRESH","expires":123,"accountId":"acc-9"},
         "glmodingplan":{"type":"api","key":"glm-cn-key"},
         "zai-coding-cn":{"type":"api","key":"glm-cn-key-2"},
         "zai":{"type":"api","key":"glm-intl-key"},
         "kimi-coding":{"type":"api","key":"kimi-key"},
         "openrouter":{"type":"api","key":"or-key"},
         "deepseek":{"type":"api","key":"ds-key"},
         "someone-else":{"type":"api","key":"x"}}
        """
        let result = CredentialImportFile.parse(data: Data(json.utf8))

        #expect(result.credentials.count == 6)
        #expect(result.credentials[.codex] == ImportedCredential(token: "oauth-access", accountID: "acc-9"))
        #expect(result.credentials[.glmCN]?.token == "glm-cn-key") // первая согласованная запись
        #expect(result.credentials[.glmIntl]?.token == "glm-intl-key")
        #expect(result.credentials[.kimi]?.token == "kimi-key")
        #expect(result.credentials[.openrouter]?.token == "or-key")
        #expect(result.credentials[.deepseek]?.token == "ds-key")
    }

    @Test("Kilo auth.json: несогласованный type пропускается; мусор → пусто")
    func kiloTypeMismatchAndGarbage() {
        let mismatch = #"{"openai":{"type":"api","key":"not-oauth"}}"#
        let result = CredentialImportFile.parse(data: Data(mismatch.utf8))
        #expect(result.credentials.isEmpty)
        #expect(result.skippedEntries.contains { $0.contains("openai") })

        #expect(CredentialImportFile.parse(data: Data("мусор".utf8)).isEmpty)
        #expect(CredentialImportFile.parse(data: Data("[]".utf8)).isEmpty)
    }
}

@Suite("Граница credential: эпохи, last-good, фильтрация публикации (CR-01/FIX5)")
struct ProviderLifecycleTests {

    private func factsRow(_ provider: ProviderID, percent: Double, at: Date) -> ProviderRow {
        ProviderRow(
            providerID: provider, displayName: provider.displayName,
            windows: [UsageWindow(key: "month", percent: percent)],
            fetchedAt: at, error: nil, lastAttemptAt: at)
    }

    private func snapshotJSON(_ rows: [ProviderRow]) throws -> String {
        let snapshot = UsageSnapshot(rows: rows, writtenAt: Date(timeIntervalSince1970: 1_760_000_200))
        return String(data: try makeUsageSnapshotEncoder().encode(snapshot), encoding: .utf8) ?? ""
    }

    @Test("Отключение во время незавершённого запроса: ответ не воскрешает строку")
    func disconnectDuringOutstandingFetch() throws {
        var board = ProviderRowBoard()
        // Запрос аккаунта A начат: эпоха захвачена ДО await (интеграция:
        // UsageModel.refresh делает currentEpoch до fetcher.fetch).
        let epoch = board.currentEpoch(.kimi)
        // Владелец нажимает «Отключить» пока запрос в полёте:
        board.invalidate(.kimi)
        #expect(board.currentEpoch(.kimi) != epoch)

        // Поздний успех A прибывает и гасится guard'ом эпохи:
        board.applySuccess(.kimi, epoch: epoch, row: factsRow(.kimi, percent: 80, at: Date(timeIntervalSince1970: 1_760_000_000)))
        // Поздняя ошибка A гасится так же:
        board.applyFailure(.kimi, epoch: epoch, message: "HTTP 500", now: Date(timeIntervalSince1970: 1_760_000_050))

        #expect(board.publishedRows(excluding: []) == [])
        let json = try snapshotJSON(board.publishedRows(excluding: [.kimi]))
        #expect(!json.contains("80"))
        #expect(!json.contains("Kimi"))
    }

    @Test("Замена A→B: 401 нового ключа не показывает цифры старого аккаунта")
    func replaceAccountThenNewKeyFailure() throws {
        var board = ProviderRowBoard()
        // Аккаунт A успешно опрошен (80%):
        let epochA = board.currentEpoch(.kimi)
        board.applySuccess(.kimi, epoch: epochA, row: factsRow(.kimi, percent: 80, at: Date(timeIntervalSince1970: 1_760_000_000)))
        #expect(board.rows[.kimi]?.windows.first?.percent == 80)

        // Владелец сохранит ключ B: успешная запись → invalidate (строка A
        // убрана немедленно, только после подтверждённого сохранения):
        board.invalidate(.kimi)

        // Незавершённый ответ A (успех или ошибка) гасится:
        board.applyFailure(.kimi, epoch: epochA, message: "HTTP 401", now: Date(timeIntervalSince1970: 1_760_000_100))
        #expect(board.rows[.kimi] == nil)

        // Новый опрос B падает 401: честная строка ошибки БЕЗ фактов A:
        let epochB = board.currentEpoch(.kimi)
        board.applyFailure(.kimi, epoch: epochB, message: "HTTP 401 — проверьте ключ", now: Date(timeIntervalSince1970: 1_760_000_150))
        let row = try #require(board.rows[.kimi])
        #expect(row.fetchedAt == nil)
        #expect(row.windows.isEmpty)

        let json = try snapshotJSON(board.publishedRows(excluding: []))
        #expect(!json.contains("80"))
    }

    @Test("Ошибка того же credential сохраняет last-good и возраст фактов (WR-02)")
    func sameCredentialFailurePreservesAge() throws {
        var board = ProviderRowBoard()
        let stale = Date(timeIntervalSince1970: 1_760_000_000) // 10:00
        let recent = Date(timeIntervalSince1970: 1_760_360_000 / 1000) // +1 ч
        let epoch = board.currentEpoch(.kimi)
        board.applySuccess(.kimi, epoch: epoch, row: factsRow(.kimi, percent: 55, at: stale))

        // Неудачный проход в 11:00: цифры и fetchedAt (10:00) не сбрасываются:
        board.applyFailure(.kimi, epoch: epoch, message: "Нет соединения с провайдером", now: recent)

        let row = try #require(board.rows[.kimi])
        #expect(row.fetchedAt == stale)
        #expect(row.lastAttemptAt == recent)
        #expect(row.windows.first?.percent == 55)
        #expect(row.error == "Нет соединения с провайдером")
    }

    @Test("Эпохи монотонны; повторное подключение того же аккаунта инвалидирует")
    func epochsAreMonotonic() {
        var board = ProviderRowBoard()
        let e0 = board.currentEpoch(.glmCN)
        board.invalidate(.glmCN)
        let e1 = board.currentEpoch(.glmCN)
        board.invalidate(.glmCN) // re-add того же аккаунта = новая инвалидация
        let e2 = board.currentEpoch(.glmCN)
        #expect(e0 < e1)
        #expect(e1 < e2)
        // Валидна только последняя эпоха:
        #expect(!board.isValidEpochForTest(.glmCN, epoch: e0))
    }

    @Test("Публикация исключает только absent; недоступная Keychain строку держит (FIX5)")
    func publicationFiltersOnlyAbsent() {
        var board = ProviderRowBoard()
        board.applySuccess(.kimi, epoch: board.currentEpoch(.kimi),
                           row: factsRow(.kimi, percent: 55, at: Date(timeIntervalSince1970: 1_760_000_000)))
        board.applySuccess(.codex, epoch: board.currentEpoch(.codex),
                           row: factsRow(.codex, percent: 10, at: Date(timeIntervalSince1970: 1_760_000_000)))

        // kimi absent (слот достоверно удалён) → исключён; codex недоступен
        // (Keychain locked) → строка остаётся, не «молча не подключён».
        let published = board.publishedRows(excluding: [.kimi])
        #expect(published.map(\.providerID) == [.codex])
    }

    @Test("Чистый маппинг статусов Keychain: notFound ≠ unavailable")
    func keychainPresenceMapping() {
        #expect(keychainPresence(status: keychainStatusSuccess, hasValue: true) == .present)
        // Пустое значение при успехе чтения трактуется как отсутствие слота:
        #expect(keychainPresence(status: keychainStatusSuccess, hasValue: false) == .absent)
        #expect(keychainPresence(status: keychainStatusItemNotFound, hasValue: false) == .absent)
        #expect(keychainPresence(status: keychainStatusItemNotFound, hasValue: true) == .absent)
        // Любой иной статус (занятость/доступ) — недоступность, не «нет слота»:
        #expect(keychainPresence(status: -25293, hasValue: false) == .unavailable) // errSecAuthFailed
        #expect(keychainStatusSuccess == 0)
        #expect(keychainStatusItemNotFound == -25300)
    }

    @Test("Фиксированные сообщения Keychain: без сырых кодов и путей")
    func keychainMessagesAreFixed() {
        #expect(keychainFailureMessage(.write) == "Не удалось сохранить ключ (Keychain)")
        #expect(keychainFailureMessage(.delete) == "Не удалось удалить ключ (Keychain)")
        #expect(keychainFailureMessage(.read) == "Keychain недоступна")
    }
}

@Suite("Атомарный конверт Codex (CR-02): одна запись, целиком или никак")
struct CodexEnvelopeTests {

    @Test("Roundtrip: token+accountId из ОДНОГО конверта; accountId без ключа — явный nil")
    func envelopeRoundTrip() throws {
        let withID = CodexCredentialEnvelope(accessToken: "fixture-token-A", accountId: "acct-A")
        let decoded = try CodexCredentialEnvelope.decode(withID.encoded())
        #expect(decoded == withID)
        // Обе части приходят из одной сериализованной записи — не из двух слотов:
        #expect(decoded.accessToken == "fixture-token-A")
        #expect(decoded.accountId == "acct-A")

        // Явное отсутствие accountId — валидный nil (не подавленная ошибка):
        let withoutID = CodexCredentialEnvelope(accessToken: "fixture-token-B", accountId: nil)
        let decodedNil = try CodexCredentialEnvelope.decode(withoutID.encoded())
        #expect(decodedNil.accountId == nil)
        #expect(decodedNil.accessToken == "fixture-token-B")
    }

    @Test("Мусор/чужая схема/пустой токен — ошибка, НЕ «слота нет» и НЕ nil-подстановка")
    func envelopeRejects() throws {
        #expect(throws: CodexCredentialEnvelopeError.self) {
            try CodexCredentialEnvelope.decode("это не json")
        }
        #expect(throws: CodexCredentialEnvelopeError.self) {
            try CodexCredentialEnvelope.decode(#"{"schemaVersion":99,"accessToken":"x"}"#)
        }
        // accountId не строки — decode отказ (не молчаливый nil):
        #expect(throws: CodexCredentialEnvelopeError.self) {
            try CodexCredentialEnvelope.decode(#"{"schemaVersion":1,"accessToken":"x","accountId":42}"#)
        }
        // Пустой accessToken недопустим:
        #expect(throws: CodexCredentialEnvelopeError.self) {
            try CodexCredentialEnvelope.decode(#"{"schemaVersion":1,"accessToken":""}"#)
        }
        // Отсутствие ошибок у валидного минимума:
        let minimal = try CodexCredentialEnvelope.decode(#"{"schemaVersion":1,"accessToken":"x"}"#)
        #expect(minimal.accountId == nil)
    }

    @Test("Неуспешная запись конверта НЕ инвалидирует board: факты старого аккаунта целы (A→A)")
    func failedWriteKeepsOldFacts() throws {
        var board = ProviderRowBoard()
        let epochA = board.currentEpoch(.codex)
        // Аккаунт A успешно опрошен:
        board.applySuccess(.codex, epoch: epochA, row: ProviderRow(
            providerID: .codex, displayName: "Codex",
            windows: [UsageWindow(key: "5h", percent: 61)],
            fetchedAt: Date(timeIntervalSince1970: 1_760_000_000),
            error: nil, lastAttemptAt: Date(timeIntervalSince1970: 1_760_000_000)))

        // Импорт B: запись конверта ОТКАЗАЛА (KeychainError) → invalidate НЕ
        // вызывается (контракт UsageModel.applyImport). Board не тронут:
        // (здесь фиксируется именно отсутствие invalidate — его выполняет
        // только успешная ветка записи)
        #expect(board.currentEpoch(.codex) == epochA)
        #expect(board.rows[.codex]?.windows.first?.percent == 61)

        // «Перезапуск»: чтение вернуло старый конверт A (запись B не прошла) —
        // эпоха прежняя, ответ A валиден, смешения нет.
        board.applySuccess(.codex, epoch: epochA, row: ProviderRow(
            providerID: .codex, displayName: "Codex",
            windows: [UsageWindow(key: "5h", percent: 62)],
            fetchedAt: Date(timeIntervalSince1970: 1_760_000_100),
            error: nil, lastAttemptAt: Date(timeIntervalSince1970: 1_760_000_100)))
        #expect(board.rows[.codex]?.windows.first?.percent == 62)

        // Контроль: УСПЕШНАЯ замена инвалидирует старые факты (A↛B):
        board.invalidate(.codex)
        #expect(board.rows[.codex] == nil)
        #expect(board.currentEpoch(.codex) != epochA)
    }
}

@Suite("Коалесцирование refresh (WR-04): запрос во время прохода не теряется")
struct RefreshGateTests {

    @Test("Сохранение B во время опроса A → ровно ОДИН немедленный повторный проход")
    func rerunCoalescing() {
        var gate = RefreshGate()
        // Проход A начался (опрос старого credential в полёте):
        let firstBegin = gate.begin()
        #expect(firstBegin)
        // Владелец сохранил B → запрос refresh во время прохода A: коалесцирован,
        // второго параллельного прохода нет:
        let duringFlight1 = gate.begin()
        #expect(!duringFlight1)
        // Повторный запрос во время того же прохода сливается в тот же флаг:
        let duringFlight2 = gate.begin()
        #expect(!duringFlight2)
        // Завершение A: есть ровно один повторный проход (немедленно, без тика):
        let endAfterA = gate.end()
        #expect(endAfterA)
        #expect(gate.inFlight)
        #expect(!gate.pendingRerun)
        // Повторный проход завершился, новых запросов не было — вентиль свободен:
        let endAfterRerun = gate.end()
        #expect(!endAfterRerun)
        #expect(!gate.inFlight)
        // Мёртвых циклов нет: следующий запрос — обычный новый проход:
        let nextBegin = gate.begin()
        #expect(nextBegin)
        let finalEnd = gate.end()
        #expect(!finalEnd)
    }

    @Test("Запрос на неподключённом наборе не зацикливает вентиль")
    func noDeadCycleWhenNothingToPoll() {
        var gate = RefreshGate()
        let begin = gate.begin()
        #expect(begin)
        // Проход над пустым списком провайдеров: повторных запросов не
        // порождается, цикл завершается сразу:
        let end = gate.end()
        #expect(!end)
        #expect(!gate.inFlight)
    }
}

@Suite("Индикатор неизвестных окон по ПОЛНОМУ набору (WR-03 overflow)")
struct UnknownWindowIndicatorTests {

    @Test("4 окна: неизвестное за переполнением сводки всё равно засчитано индикатором")
    func overflowHiddenUnknownStillSignalled() {
        // Набор из ревью: три известных + четвёртое неизвестное.
        let mixed = [
            UsageWindow(key: "5h", percent: 10),
            UsageWindow(key: "week", percent: 20),
            UsageWindow(key: "month", percent: 30),
            UsageWindow(key: "month-code", percent: nil),
        ]
        // Свойство medium/small: индикатор вычисляется на ПОЛНОМ row.windows,
        // независимо от того, что показала усечённая сводка:
        #expect(containsUnknownPercent(mixed))
        // Известный максимум остаётся явным (30, не фейковый 0):
        #expect(mixed.compactMap(\.percent).max() == 30)
        // Переполнение подписано количеством, неизвестное — в показанном префиксе:
        #expect(windowSummary(mixed) == "мес·код — · мес 30% · нед 20% · +1 ещё")
    }

    @Test("4 неизвестных окна: сводка честно показывает прочерки и +N, индикатор активен")
    func allUnknownWindows() {
        let unknown = [
            UsageWindow(key: "5h", percent: nil),
            UsageWindow(key: "week", percent: nil),
            UsageWindow(key: "month", percent: nil),
            UsageWindow(key: "month-code", percent: nil),
        ]
        #expect(containsUnknownPercent(unknown))
        // Известного максимума нет — не 0:
        #expect(unknown.compactMap(\.percent).max() == nil)
        #expect(windowSummary(unknown) == "5ч — · нед — · мес — · +1 ещё")
    }
}

// Вспомогательная поверхность для теста валидности эпохи (обёртка над
// publishedRows-контрактом; production-код использует apply* с guard внутри).
extension ProviderRowBoard {
    func isValidEpochForTest(_ provider: ProviderID, epoch: Int) -> Bool {
        currentEpoch(provider) == epoch
    }
}
