import Testing
import Foundation
import UsageCore

// Фаза 1, план 01-02, задача 2 (PLAT-01, D-06/D-07; T-01-04, T-01-10):
// тесты состояний контрольной записи и allowlist Debug-инъекции.
//
// Чистые функции пакета, без обращения к файловой системе и контейнеру группы
// — бегут на CLT за секунды. Повреждённый вход доказывается тем, что
// типизированное декодирование БРОСАЕТ ошибку (состояние corrupt): дефолтного
// TestRecord и «нулей» не существует по устройству типа — тесты фиксируют это.
//
// Честная пометка про Release: тесты allowlist-инъекции компилируются, потому
// что `swift test` исполняет Debug-конфигурацию; сама функция
// debugStateOverride существует только в #if DEBUG (план 01-01), её
// отсутствие в Release проверено grep-шагом verify плана 01-01 (символ
// debugStateOverride отсутствует в собранном Release-модуле UsageCore).
// Отдельного Release-теста нет — инъекция в Release не компилируется вовсе.

@Suite("Контрольная запись: декодирование и allowlist Debug-инъекции")
struct TestRecordTests {

    // MARK: - Декодирование записи (D-06, D-07; edge «empty»)

    @Test("Валидный JSON декодируется в равный TestRecord")
    func validJSONDecodesToEqualRecord() throws {
        let json = #"{"number":7,"recordedAt":"2025-10-09T08:53:20Z"}"#
        let expectedDate = try Date("2025-10-09T08:53:20Z", strategy: .iso8601)

        let record = try makeSnapshotDecoder().decode(TestRecord.self, from: Data(json.utf8))

        // Равенство целиком и по полям: никаких «нулей по умолчанию».
        #expect(record == TestRecord(number: 7, recordedAt: expectedDate))
        #expect(record.number == 7)
        #expect(record.recordedAt == expectedDate)
    }

    @Test("Пустой объект — corrupt (декодирование бросает ошибку)")
    func emptyObjectIsCorrupt() {
        let json = #"{}"#
        #expect(throws: (any Error).self) {
            try makeSnapshotDecoder().decode(TestRecord.self, from: Data(json.utf8))
        }
    }

    @Test("Не-JSON мусор — corrupt (декодирование бросает ошибку)")
    func nonJSONGarbageIsCorrupt() {
        let garbage = "это не json {{{"
        #expect(throws: (any Error).self) {
            try makeSnapshotDecoder().decode(TestRecord.self, from: Data(garbage.utf8))
        }
    }

    @Test("Null-поля — corrupt (декодирование бросает ошибку)")
    func nullFieldsAreCorrupt() {
        let json = #"{"number":null,"recordedAt":null}"#
        #expect(throws: (any Error).self) {
            try makeSnapshotDecoder().decode(TestRecord.self, from: Data(json.utf8))
        }
    }

    @Test("Неверные типы — corrupt (декодирование бросает ошибку)")
    func wrongTypesAreCorrupt() {
        // Строка вместо number:
        let stringNumber = #"{"number":"7","recordedAt":"2025-10-09T08:53:20Z"}"#
        #expect(throws: (any Error).self) {
            try makeSnapshotDecoder().decode(TestRecord.self, from: Data(stringNumber.utf8))
        }
        // Число вместо строки ISO 8601:
        let numericDate = #"{"number":7,"recordedAt":1760000000}"#
        #expect(throws: (any Error).self) {
            try makeSnapshotDecoder().decode(TestRecord.self, from: Data(numericDate.utf8))
        }
    }

    @Test("Кодирование-декодирование сохраняет значения (roundtrip)")
    func roundtripPreservesValues() throws {
        let original = TestRecord(number: 42, recordedAt: Date(timeIntervalSince1970: 1_760_000_000))

        let data = try makeSnapshotEncoder().encode(original)
        let decoded = try makeSnapshotDecoder().decode(TestRecord.self, from: data)

        #expect(decoded == original)
        #expect(decoded.number == 42)
        #expect(decoded.recordedAt == original.recordedAt)
    }

    // MARK: - Границы номера счётчика (CR-06: Int.max больше не декодируется)

    @Test("Int.max отвергается при декодировании (переполнение следующего +1)")
    func intMaxNumberIsRejected() {
        let json = #"{"number":9223372036854775807,"recordedAt":"2025-10-09T08:53:20Z"}"#
        #expect(throws: DecodingError.self) {
            _ = try makeSnapshotDecoder().decode(TestRecord.self, from: Data(json.utf8))
        }
    }

    @Test("Отрицательный номер отвергается при декодировании")
    func negativeNumberIsRejected() {
        let json = #"{"number":-5,"recordedAt":"2025-10-09T08:53:20Z"}"#
        #expect(throws: DecodingError.self) {
            _ = try makeSnapshotDecoder().decode(TestRecord.self, from: Data(json.utf8))
        }
    }

    @Test("Ноль отвергается при декодировании (нумерация начинается с 1)")
    func zeroNumberIsRejected() {
        let json = #"{"number":0,"recordedAt":"2025-10-09T08:53:20Z"}"#
        #expect(throws: DecodingError.self) {
            _ = try makeSnapshotDecoder().decode(TestRecord.self, from: Data(json.utf8))
        }
    }

    @Test("maxSafeNumber декодируется (верхняя граница допустима)")
    func maxSafeNumberDecodes() throws {
        let json = #"{"number":9223372036854775806,"recordedAt":"2025-10-09T08:53:20Z"}"#
        let record = try makeSnapshotDecoder().decode(TestRecord.self, from: Data(json.utf8))
        #expect(record.number == TestRecord.maxSafeNumber)
        #expect(TestRecord.maxSafeNumber == Int.max - 1)
    }

    // MARK: - Проверенный инкремент (CR-06: без trap, без тихого wrap)

    @Test("nextNumber: отсутствие записи и чужие значения → 1")
    func nextNumberStartsAtOne() {
        #expect(TestRecord.nextNumber(after: 0) == 1)
        #expect(TestRecord.nextNumber(after: -7) == 1)
    }

    @Test("nextNumber: обычный инкремент")
    func nextNumberIncrements() {
        #expect(TestRecord.nextNumber(after: 1) == 2)
        #expect(TestRecord.nextNumber(after: 41) == 42)
    }

    @Test("nextNumber: граница диапазона — контролируемый перезапуск с 1")
    func nextNumberAtBoundRestarts() {
        #expect(TestRecord.nextNumber(after: TestRecord.maxSafeNumber) == 1)
        #expect(TestRecord.nextNumber(after: TestRecord.maxSafeNumber - 1) == TestRecord.maxSafeNumber)
        #expect(TestRecord.nextNumber(after: Int.max) == 1)
    }

    // MARK: - Классификация ошибок чтения файла (WR-05: read error ≠ corrupt)

    @Test("Отсутствие файла классифицируется как missing (ENOENT)")
    func missingFileClassifiesAsMissing() {
        let absent = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aiusage-wr05-absent-\(UUID().uuidString).json")
        do {
            _ = try Data(contentsOf: absent)
            Issue.record("ожидалась ошибка чтения отсутствующего файла")
        } catch {
            #expect(classifySnapshotReadError(error) == .missing)
        }
    }

    @Test("Отказ доступа классифицируется как containerUnavailable, не corrupt")
    func unreadableFileClassifiesAsContainerUnavailable() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aiusage-wr05-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("test-snapshot.json")
        try Data(#"{"number":7,"recordedAt":"2025-10-09T08:53:20Z"}"#.utf8)
            .write(to: file)
        // Права реального Group Container не меняются: файл во временном каталоге
        // теста лишается бита чтения и восстанавливается в defer.
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            _ = try Data(contentsOf: file)
            Issue.record("ожидался отказ доступа (posix 000)")
        } catch {
            #expect(classifySnapshotReadError(error) == .containerUnavailable)
        }
    }

    // MARK: - Allowlist Debug-инъекции (D-07, T-01-10; приёмка 01-04-T3)

    @Test("Точный аргумент возвращает containerUnavailable")
    func exactArgumentYieldsContainerUnavailable() {
        // Дословный литерал допустимого аргумента (план):
        let state = debugStateOverride(arguments: ["-aiusage-sim-state=containerUnavailable"])
        #expect(state == .containerUnavailable)
    }

    @Test("Аргумент среди других — инъекция включается по точному совпадению")
    func argumentAmongOthersYieldsContainerUnavailable() {
        let state = debugStateOverride(arguments: [
            "-NORMAL", "--other-flag", "-aiusage-sim-state=containerUnavailable", "tail",
        ])
        #expect(state == .containerUnavailable)
    }

    @Test("Пустой массив аргументов возвращает nil")
    func emptyArgumentsYieldNil() {
        #expect(debugStateOverride(arguments: []) == nil)
    }

    @Test("Обычные аргументы запуска без маркера возвращают nil")
    func absentArgumentYieldsNil() {
        #expect(debugStateOverride(arguments: ["-NSDocumentRevisionsDebugMode", "YES"]) == nil)
        #expect(debugStateOverride(arguments: ["/usr/bin/AI Usage Widget"]) == nil)
    }

    @Test("Опечатка в значении возвращает nil")
    func typoValueYieldsNil() {
        #expect(debugStateOverride(arguments: ["-aiusage-sim-state=containerUnvailable"]) == nil)
        #expect(debugStateOverride(arguments: ["-aiusage-sim-state=container unavailable"]) == nil)
    }

    @Test("Любое другое значение возвращает nil")
    func anyOtherValueYieldsNil() {
        #expect(debugStateOverride(arguments: ["-aiusage-sim-state=record"]) == nil)
        #expect(debugStateOverride(arguments: ["-aiusage-sim-state=missing"]) == nil)
        #expect(debugStateOverride(arguments: ["-aiusage-sim-state=corrupt"]) == nil)
        #expect(debugStateOverride(arguments: ["-aiusage-sim-state="]) == nil)
    }

    @Test("Чужие формы аргумента (регистр, без значения, другой флаг) возвращают nil")
    func otherArgumentFormsYieldNil() {
        // Другой регистр — не то же значение:
        #expect(debugStateOverride(arguments: ["-aiusage-sim-state=CONTAINERUNAVAILABLE"]) == nil)
        // Флаг без «=значение»:
        #expect(debugStateOverride(arguments: ["-aiusage-sim-state"]) == nil)
        // Похожий, но другой флаг:
        #expect(debugStateOverride(arguments: ["-aiusage-sim-state2=containerUnavailable"]) == nil)
    }

    // MARK: - Константы маркера (единый источник литералов, план 01-01)

    @Test("Константы маркера объявлены и согласованы с allowlist")
    func markerConstantsAreStable() {
        // Имя файла маркера и имя файла записи доступны приложениям и тестам пакета:
        #expect(testSnapshotFileName == "test-snapshot.json")
        #expect(debugSimStateMarkerFileName == "debug-sim-state.json")
        // Единственный допустимый токен:
        #expect(debugSimStateToken == "containerUnavailable")
        // Константа аргумента совпадает с литералом allowlist-теста выше:
        #expect(debugSimStateArgument == "-aiusage-sim-state=containerUnavailable")
        // Согласованность: константа проходит allowlist, токен внутри неё — единственный.
        #expect(debugStateOverride(arguments: [debugSimStateArgument]) == .containerUnavailable)
    }
}
