import Foundation

// Фаза 1 (PLAT-01): контрольная запись платформенной проверки.
// ВНИМАНИЕ: это НЕ контракт UsageCore фазы 2 — продуктовый формат снимка
// будет спроектирован заново в фазе 2 (граница фазы, 01-CONTEXT.md).
//
// Общий код обоих таргетов живёт здесь: приложение — единственный писатель
// контейнера группы, widget extension — только читатель.

/// Имя файла контрольной записи в контейнере группы.
/// Один литерал для обеих сторон — принцип единого источника (как у group id, Pitfall 6).
public let testSnapshotFileName = "test-snapshot.json"

/// Kind тестового виджета: `StaticConfiguration(kind:)` и
/// `WidgetCenter.reloadTimelines(ofKind:)` обязаны ссылаться на одну константу.
public let testWidgetKind = "AiUsageTestWidget"

/// Контрольная запись: номер проверки и время записи (D-06).
/// Новая запись увеличивает номер на единицу; обе поверхности показывают её целиком.
public struct TestRecord: Codable, Equatable, Sendable {
    /// Номер проверки.
    ///
    /// Допустимый диапазон — `1...TestRecord.maxSafeNumber`: номер обязан допускать
    /// последующий инкремент без переполнения, поэтому `Int.max` как ЗНАЧЕНИЕ
    /// отвергается ещё при декодировании (CR-06: контрольный счётчик — не crash).
    public let number: Int
    /// Время записи.
    public let recordedAt: Date

    public init(number: Int, recordedAt: Date) {
        self.number = number
        self.recordedAt = recordedAt
    }

    /// Верхняя граница допустимого номера: инкремент `maxSafeNumber + 1` невозможен,
    /// поэтому записи с номером `maxSafeNumber` достаточно, а `Int.max` — чужой/
    /// повреждённый снимок.
    public static let maxSafeNumber: Int = Int.max - 1

    /// Проверенный инкремент номера (CR-06): отсутствие/чужая запись → 1;
    /// допустимый номер → +1 без возможности переполнения; номер на границе
    /// диапазона → контролируемый перезапуск счёта с 1 (явная политика
    /// восстановления границы: без trap, без тихого wrap).
    public static func nextNumber(after previous: Int) -> Int {
        if previous < 1 { return 1 }
        let result = previous.addingReportingOverflow(1)
        if result.overflow || result.partialValue > maxSafeNumber { return 1 }
        return result.partialValue
    }

    /// Ключи JSON: «number», «recordedAt».
    enum CodingKeys: String, CodingKey {
        case number
        case recordedAt
    }

    /// Декодирование с валидацией диапазона номера (CR-06): синтезированный
    /// `Codable` принял бы любое представимое `Int`, включая `Int.max`, после
    /// которого следующий `+1` переполняется ВНЕ обработки ошибок записи.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let number = try container.decode(Int.self, forKey: .number)
        guard (1...Self.maxSafeNumber).contains(number) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [CodingKeys.number],
                debugDescription: "номер контрольной записи вне допустимого диапазона 1...\(Self.maxSafeNumber)"
            ))
        }
        self.number = number
        self.recordedAt = try container.decode(Date.self, forKey: .recordedAt)
    }
}

/// Наблюдаемое состояние контрольной записи (D-07): четыре различимых состояния,
/// встроенных примеров данных нет ни в одном.
public enum TestSnapshotState: Equatable, Sendable {
    /// Запись прочитана и декодирована — показ номера и времени с пометкой «Тест».
    case record(TestRecord)
    /// Файла записи нет — «нет записи, откройте приложение и запишите тест».
    case missing
    /// Файл есть, но не декодируется — отдельное состояние; повреждённое не выдаётся
    /// за валидную демонстрацию и не смешивается с отсутствием записи.
    case corrupt
    /// Каталог контейнера недоступен или ключ AppGroupID не задан.
    case containerUnavailable
}

/// Идентификатор App Group из Info.plist СВОЕГО бандла (значение подставляет сборка —
/// файлы конфигурации создаёт план 01-02). Каждый таргет читает свой Info.plist:
/// рассинхрон групп виден как явное состояние, а не как тихий обход.
public func appGroupID(from bundle: Bundle) -> String? {
    guard let value = bundle.object(forInfoDictionaryKey: "AppGroupID") as? String,
          !value.isEmpty else {
        return nil
    }
    return value
}

/// Единый кодек контрольной записи: обе стороны обязаны кодировать дату одинаково
/// (ISO 8601), иначе запись приложения не декодируется виджетом.
public func makeSnapshotEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return encoder
}

/// Парная фабрика декодера (см. `makeSnapshotEncoder()`).
public func makeSnapshotDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

/// Классификация ошибки ЧТЕНИЯ файла снимка (WR-05): отсутствие файла — только
/// `NSFileReadNoSuchFile` (ENOENT); отказ доступа/прочие I/O-ошибки — проблема
/// контейнера, а НЕ «повреждённая запись». Единая функция для приложения и
/// виджета: ошибка доступа не предлагает перезаписать данные и не сбрасывает
/// номер счётчика (кнопка записи в этом состоянии заблокирована).
public func classifySnapshotReadError(_ error: Error) -> TestSnapshotState {
    if let cocoaError = error as? CocoaError, cocoaError.code == .fileReadNoSuchFile {
        return .missing
    }
    return .containerUnavailable
}

#if DEBUG
// MARK: - Протокол Debug-инъекции состояния (только Debug; в Release не компилируется)
//
// Безопасный механизм приёмки состояния «ошибка контейнера» для 01-04-T3 (D-07, T-01-10):
// маркер в контейнере пишет и удаляет ТОЛЬКО приложение (единственный писатель) и только
// в Debug; расширение маркер только читает. Инъекция подменяет результат чтения на входе
// производственного кода состояний и НЕ меняет права реального контейнера.
// В Release-сборке этого кода не существует вовсе.

/// Имя файла маркера инъекции в контейнере группы.
public let debugSimStateMarkerFileName = "debug-sim-state.json"

/// Единственное допущенное значение токена инъекции (allowlist из одного значения).
public let debugSimStateToken = "containerUnavailable"

/// Точная форма аргумента запуска приложения, включающего инъекцию.
public let debugSimStateArgument = "-aiusage-sim-state=containerUnavailable"

/// Payload маркера: JSON вида {"state":"containerUnavailable"}.
public struct DebugSimStateMarker: Codable, Equatable, Sendable {
    /// Токен инъекции; валиден только `debugSimStateToken`.
    public let state: String

    public init(state: String) {
        self.state = state
    }
}

/// Чистая функция allowlist-инъекции: `containerUnavailable` — ТОЛЬКО для точного
/// аргумента «-aiusage-sim-state=containerUnavailable»; для любых других значений
/// и его отсутствия — nil. Существует только в Debug-сборке.
public func debugStateOverride(arguments: [String]) -> TestSnapshotState? {
    guard arguments.contains(debugSimStateArgument) else { return nil }
    return .containerUnavailable
}
#endif
