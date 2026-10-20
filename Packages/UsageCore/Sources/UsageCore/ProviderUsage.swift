import Foundation

// Quick 261018-jd8 (PROV-01, WIDG-01): продуктовый снимок расхода лимитов.
// Приложение — единственный писатель usage-snapshot.json в контейнере группы,
// виджет — только читатель (та же изоляция писателя/читателя, что в фазе 1).
//
// ВНИМАНИЕ: тип сознательно не содержит НИ ОДНОГО секрета (токенов, заголовков,
// account id, имён аккаунтов). Снимок лежит в общем контейнере, который читает
// другой процесс; любые новые поля проходят через это ограничение (тест
// «снимок без секретов» фиксирует его машинно).

/// Имя файла продуктового снимка в контейнере группы (единый литерал app+widget).
public let usageSnapshotFileName = "usage-snapshot.json"

/// Текущая версия схемы снимка. Неизвестная/чужая версия — corrupt, а не нули.
public let usageSnapshotSchemaVersion = 1

/// Одно окно расхода лимита (порт PlanWindowView из dsh-usage-hq).
/// `percent == nil` — провайдер не сообщил процент; это НЕ 0 и не «расхода нет».
public struct UsageWindow: Codable, Equatable, Sendable, Hashable {
    /// Словарный ключ окна как у DSH: «5h», «week», «month», «month-code», «w-<duration>», «window», «N_hour»/«N_day».
    public let key: String
    /// Человекочитаемое имя окна («Monthly», «Weekly»), если провайдер его сообщил.
    public let name: String?
    /// Процент расхода 0…100; nil — неизвестно (никогда не подставляется 0).
    public let percent: Double?
    /// Нормализованный ISO 8601 сброса (мс, Z), если провайдер сообщил.
    public let resetsAt: String?

    public init(key: String, name: String? = nil, percent: Double? = nil, resetsAt: String? = nil) {
        self.key = key
        self.name = name
        self.percent = percent
        self.resetsAt = resetsAt
    }
}

/// Одна строка провайдера в снимке: last-good факты + состояние последней попытки.
/// Секретов нет по типу; ошибки — короткая санитизированная строка (HTTP-статус +
/// ≤120 символов message), без тел, URL и заголовков.
public struct ProviderRow: Codable, Equatable, Sendable, Hashable, Identifiable {
    public let providerID: ProviderID
    /// Идентичность строки = провайдер (в снимке строка одна на провайдера).
    public var id: ProviderID { providerID }
    /// Статичное отображаемое имя провайдера («Kimi», «GLM (bigmodel.cn)») — не имя аккаунта.
    public let displayName: String
    /// Уровень подписки (Kimi membership.level, GLM data.level), если сообщён.
    public let planName: String?
    /// Окна расхода (подписочные лимиты). Пусто для балансных провайдеров и строк без фактов.
    public let windows: [UsageWindow]
    /// Валюта баланса («USD», «CNY») — только у балансных провайдеров.
    public let balanceCurrency: String?
    /// Баланс двумя знаками — только у балансных провайдеров.
    public let balanceTotal: String?
    /// Когда получены показанные факты (успешный опрос). nil — фактов ещё не было.
    public let fetchedAt: Date?
    /// Ошибка последней попытки; nil — последняя попытка успешна. Факты при этом остаются last-good.
    public let error: String?
    /// Когда была последняя попытка опроса (успешная или нет).
    public let lastAttemptAt: Date?

    public init(
        providerID: ProviderID,
        displayName: String,
        planName: String? = nil,
        windows: [UsageWindow] = [],
        balanceCurrency: String? = nil,
        balanceTotal: String? = nil,
        fetchedAt: Date? = nil,
        error: String? = nil,
        lastAttemptAt: Date? = nil
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.planName = planName
        self.windows = windows
        self.balanceCurrency = balanceCurrency
        self.balanceTotal = balanceTotal
        self.fetchedAt = fetchedAt
        self.error = error
        self.lastAttemptAt = lastAttemptAt
    }

    /// Копия строки с ошибкой новой попытки: last-good факты сохраняются,
    /// ошибка и время попытки обновляются (nil ≠ 0, факт не затирается).
    public func withError(_ message: String, attemptedAt: Date) -> ProviderRow {
        ProviderRow(
            providerID: providerID,
            displayName: displayName,
            planName: planName,
            windows: windows,
            balanceCurrency: balanceCurrency,
            balanceTotal: balanceTotal,
            fetchedAt: fetchedAt,
            error: message,
            lastAttemptAt: attemptedAt
        )
    }
}

/// Целый снимок: версиированная схема + строки провайдеров + время записи.
public struct UsageSnapshot: Codable, Equatable, Sendable {
    public let schema: Int
    public let rows: [ProviderRow]
    public let writtenAt: Date

    public init(schema: Int = usageSnapshotSchemaVersion, rows: [ProviderRow], writtenAt: Date) {
        self.schema = schema
        self.rows = rows
        self.writtenAt = writtenAt
    }

    enum CodingKeys: String, CodingKey {
        case schema, rows, writtenAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchema = try container.decode(Int.self, forKey: .schema)
        // Чужая/будущая версия — corrupt: читатель не тракует неизвестное как нули.
        guard decodedSchema == usageSnapshotSchemaVersion else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [CodingKeys.schema],
                debugDescription: "неизвестная версия схемы снимка: \(decodedSchema)"
            ))
        }
        self.schema = decodedSchema
        self.rows = try container.decode([ProviderRow].self, forKey: .rows)
        self.writtenAt = try container.decode(Date.self, forKey: .writtenAt)
    }
}

/// Состояние чтения снимка (паттерн WR-05 из TestRecord.swift):
/// missing — файла нет; unavailable — нет контейнера/отказ I/O;
/// corrupt — файл есть, но не декодируется (включая чужую версию схемы).
public enum UsageSnapshotState: Equatable, Sendable {
    case snapshot(UsageSnapshot)
    case missing
    case corrupt
    case unavailable
}

/// Читатель/писатель снимка в контейнере группы. Приложение пишет (атомарно,
/// tmp+rename — виджет не видит обрывков), виджет читает. Каталог инъекцируется
/// для тестов; по умолчанию — контейнер группы по AppGroupID своего бандла.
public struct SnapshotStore: Sendable {
    private let directory: URL?

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            self.directory = Self.defaultGroupContainer()
        }
    }

    /// Контейнер группы по AppGroupID своего Info.plist; nil — ключа нет.
    private static func defaultGroupContainer() -> URL? {
        guard let groupID = appGroupID(from: .main) else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }

    private var snapshotURL: URL? {
        directory?.appendingPathComponent(usageSnapshotFileName)
    }

    /// Чтение с разведением ошибок (WR-05): ENOENT → missing; прочий I/O →
    /// unavailable; ошибка декодирования/версии схемы → corrupt.
    public func read() -> UsageSnapshotState {
        guard let url = snapshotURL else { return .unavailable }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            if let cocoaError = error as? CocoaError, cocoaError.code == .fileReadNoSuchFile {
                return .missing
            }
            return .unavailable
        }
        do {
            let snapshot = try makeUsageSnapshotDecoder().decode(UsageSnapshot.self, from: data)
            return .snapshot(snapshot)
        } catch {
            return .corrupt
        }
    }

    /// Атомарная запись (tmp+rename по паттерну TestRecordStore): читатель либо
    /// видит прежний целый файл, либо новый целый.
    public func write(_ snapshot: UsageSnapshot) throws {
        guard let url = snapshotURL else {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try makeUsageSnapshotEncoder().encode(snapshot)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(
            usageSnapshotFileName + ".tmp-" + UUID().uuidString)
        try data.write(to: temporary)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: url)
        }
    }
}

/// Кодек снимка: даты ISO 8601 (без долей секунды — точность до секунды
/// достаточна для возрастов), ключи сортированы (стабильный diff/отладка).
public func makeUsageSnapshotEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return encoder
}

/// Парный декодер (см. `makeUsageSnapshotEncoder()`).
public func makeUsageSnapshotDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

// MARK: - Сводка окон для компактного отображения (WR-03: unknown виден)

extension UsageWindow {
    /// Короткая русская метка окна по словарю ключей DSH; неизвестный ключ
    /// показывается как есть — окно не исчезает.
    public var shortLabel: String {
        switch key {
        case "5h": return "5ч"
        case "week": return "нед"
        case "month": return "мес"
        case "month-code": return "мес·код"
        default: return key
        }
    }
}

/// Компактная сводка окон: «5ч — · нед 42% · мес·код 55%». Неизвестный процент —
/// прочерк «—», НЕ 0 и не пропуск (WR-03). Неизвестные окна стоят ПЕРВЫМИ:
/// усечение по лимиту прячет только известные — неизвестное не исчезает
/// невидимо; переполнение честно подписывается «+N ещё».
public func windowSummary(_ windows: [UsageWindow], limit: Int = 3) -> String {
    guard !windows.isEmpty else { return "" }
    let ordered = windows.enumerated().sorted { lhs, rhs in
        switch (lhs.element.percent, rhs.element.percent) {
        case (nil, nil): return lhs.offset < rhs.offset
        case (nil, _): return true
        case (_, nil): return false
        default: return lhs.element.percent! > rhs.element.percent!
        }
    }.map(\.element)
    let shown = ordered.prefix(limit)
    var parts = shown.map { window in
        if let percent = window.percent {
            return "\(window.shortLabel) \(Int(percent.rounded()))%"
        }
        return "\(window.shortLabel) —"
    }
    if ordered.count > limit {
        parts.append("+\(ordered.count - limit) ещё")
    }
    return parts.joined(separator: " · ")
}

/// Есть ли среди окон неизвестный процент (для явного сигнала неполноты).
public func containsUnknownPercent(_ windows: [UsageWindow]) -> Bool {
    windows.contains { $0.percent == nil }
}
