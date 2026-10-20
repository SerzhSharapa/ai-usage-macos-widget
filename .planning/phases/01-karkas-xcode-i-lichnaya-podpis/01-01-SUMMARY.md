---
phase: 01-karkas-xcode-i-lichnaya-podpis
plan: "01"
subsystem: infra
tags: [swift, swiftui, widgetkit, xcodeproj, swift-package-manager, app-group, macos]

requires: []
provides:
  - Локальный пакет UsageCore (tools 6.0, macOS 15, ноль зависимостей) с контрольной записью, состояниями и Debug-инъекцией
  - AiUsage.xcodeproj с двумя native-таргетами (app + widget appex), встраиванием в PlugIns и product-зависимостью UsageCore в обоих таргетах
  - Тонкая сквозная цепочка «панель приложения → атомарная запись в App Group контейнер → чтение виджетом systemSmall»
  - Закрытый #if DEBUG механизм безопасной инъекции состояния «ошибка контейнера» (маркер пишет только приложение)
affects: [01-02, 01-03, 01-04, 01-05, phase-2]

actuals:
  tokens: 9700      # chars/4 по 5 производственным файлам (38 722 байта, wc -c)
  tasks: 1
  commits: 0        # коммиты в этом прогоне ЗАПРЕЩЕНЫ явным scope родителя — «not committed, user no permission»; SHA не имитировался
  plan_head_before: 7583e3ae4e34c68c2c4b642031a84a069bed5b18
  plan_head_after: 7583e3ae4e34c68c2c4b642031a84a069bed5b18

tech-stack:
  added: []          # внешних зависимостей нет — стек целиком из SDK (T-01-SC skipped-by-design)
  patterns:
    - "Писатель один (app), читатель один (widget): файловый обмен только через App Group контейнер"
    - "Единые литералы протокола (имя файла записи, kind виджета, токен инъекции) и фабрики кодека — в UsageCore"
    - "Debug-инъекция состояния: allowlist из одного аргумента + маркер в контейнере; всё тело в #if DEBUG трёх файлов"

key-files:
  created:
    - Packages/UsageCore/Package.swift
    - Packages/UsageCore/Sources/UsageCore/TestRecord.swift
    - AiUsage.xcodeproj/project.pbxproj
    - AiUsage/AiUsageApp.swift
    - Widget/TestWidget.swift
  modified: []

key-decisions:
  - "Имя пакета UsageCore — решение планировщика из discretion (01-PATTERNS.md) исполнено дословно: переименование в фазе 2 не понадобится"
  - "Локальный пакет: XCLocalSwiftPackageReference — канонический ISA (ремедиация CR-01 от 2026-10-12; при исполнении плана ошибочно писали PBXLocalPackageReference «дословно по плану»). Каноничность подтверждена парсерами CocoaPods Xcodeproj и Tuist XcodeProj + примером Apple Food Truck (objectVersion 56); исправление вводилось без живого Xcode — открытие проекта проверит 01-04"
  - "Scheme AiUsage не вынесен в .xcscheme-файл: схема авто-создаётся Xcode/xcodebuild из имени таргета; отдельный файл схемы был бы шестым путём записи за пределами scope плана"
  - "Единые фабрики кодека (ISO 8601) и константы testSnapshotFileName/DebugSimStateMarker добавлены в UsageCore — принцип одного литерала (Pitfall 6): рассинхрон дат/имён между таргетами исключён самой структурой"
  - "Запись маркера инъекции перенесена в TestRecordStore (писатель): весь код записи контейнера в одном месте; файл и поведение — по плану"
  - "Заполнение Color(.windowBackground) заменено на Rectangle().fill(.windowBackground): исходная форма не компилируется (см. Deviations Rule 1)"
patterns-established:
  - "Состояния D-07 как единственный enum TestSnapshotState на обеих поверхностях: инъекция и реальные ошибки показываются одними и теми же производственными view, «демо»-веток UI нет"
  - "Проверка доступа к контейнеру фактической пробой (app — запись временного файла; widget — чтение каталога), не nil-check (Pitfall 1)"

requirements-completed: []   # PLAT-01 охватывает 01-01…01-05 и закрывается только приёмкой 01-04/01-05; этот план — трассер платформы

coverage:
  - id: D1
    description: "Пакет UsageCore: TestRecord {number, recordedAt}, TestSnapshotState (4 состояния), testWidgetKind, appGroupID(from:), протокол Debug-инъекции"
    requirement: PLAT-01
    verification:
      - kind: other
        ref: "swift build --package-path Packages/UsageCore (debug) — exit 0"
        status: pass
      - kind: other
        ref: "swift build --package-path Packages/UsageCore -c release — exit 0"
        status: pass
      - kind: manual_procedural
        ref: "поведенческая проба (temp): 11/11 PASS — allowlist 7 случаев + JSON round-trip + ключи number/recordedAt + маркер"
        status: pass
    human_judgment: false
  - id: D2
    description: "project.pbxproj: objectVersion 56, ровно 2 native-таргета, appex в PlugIns (dstSubfolderSpec 13, dstPath пуст — CR-03), UsageCore в Frameworks обоих таргетов, deployment 15.0, Swift 6.0, автоподпись, DEVELOPMENT_TEAM пустой"
    requirement: PLAT-01
    verification:
      - kind: other
        ref: "plutil -lint AiUsage.xcodeproj/project.pbxproj — OK"
        status: pass
      - kind: other
        ref: "структурные grep (после ремедиации CR-01/02/03): 2 таргета, wrapper.app-extension, XCLocalSwiftPackageReference+relativePath, 2×XCSwiftPackageProductDependency, dstPath=\"\"+dstSubfolderSpec=13, productType app + app-extension; 6×MACOSX_DEPLOYMENT_TARGET=15.0, 6×SWIFT_VERSION=6.0, 4×CODE_SIGN_STYLE=Automatic, 4×DEVELOPMENT_TEAM=\"\" — PASS (plutil -lint OK; семантику объектного графа без Xcode не доказать — 01-04)"
        status: pass
    human_judgment: true
    rationale: "Полная валидация файла Xcode 27 невозможна: Xcode не установлен (проверка 2026-10-11, xcode-select → CommandLineTools); открытие/сборка проекта — план 01-04"
  - id: D3
    description: "App-каркас: MenuBarExtra(.window), русская тестовая панель, TestRecordStore с атомарной записью (temp+rename) и reloadTimelines, Debug-инъекция только #if DEBUG"
    requirement: PLAT-01
    verification:
      - kind: other
        ref: "swiftc -parse AiUsage/AiUsageApp.swift — exit 0; 4×#if DEBUG в файле"
        status: pass
      - kind: other
        ref: "semantic probe: TestRecordStore (весь код писателя, извлечён во temp) — swiftc -typecheck -swift-version 6 PASS в Debug и Release"
        status: pass
    human_judgment: true
    rationale: "Полный typecheck файла на CLT заблокирован отсутствием плагина SwiftUIMacros (нет в CommandLineTools); поведенческая проверка панели — план 01-04-T3"
  - id: D4
    description: "Виджет: WidgetBundle, StaticConfiguration «AI Usage Widget - Тест», только systemSmall, TimelineProvider только-чтение, 4 различимых состояния"
    requirement: PLAT-01
    verification:
      - kind: other
        ref: "swiftc -typecheck -parse-as-library -swift-version 6 Widget/TestWidget.swift — PASS в Debug (-D DEBUG) и Release против собранного модуля UsageCore"
        status: pass
      - kind: other
        ref: "негативные grep: 0 вызовов записи в Widget/TestWidget.swift; 0 'TestRecord(number:' (нет демо-данных); нет ForEach/sorted (edge ordering)"
        status: pass
    human_judgment: true
    rationale: "Компиляция подтверждена полностью; живое отображение в Центре уведомлений — ручная приёмка 01-04-T3 (blocking-human по плану)"
  - id: D5
    description: "Механизм Debug-инъекции закрыт от Release во всех трёх файлах (T-01-10)"
    requirement: PLAT-01
    verification:
      - kind: other
        ref: "grep '#if DEBUG' в TestRecord.swift/AiUsageApp.swift/TestWidget.swift — 1/4/2 вхождений, exit 0 (шаг plan-verify)"
        status: pass
      - kind: other
        ref: "символ debugStateOverride в собранном модуле: Debug — присутствует (swiftmodule/swiftdoc/.o/.a), Release — 0 вхождений (grep -r по дереву Products/Release)"
        status: pass
      - kind: manual_procedural
        ref: "поведенческая проба allowlist: точный аргумент → containerUnavailable; все прочие значения/отсутствие → nil (7/7 PASS)"
        status: pass
    human_judgment: false

duration: 9 min
completed: 2026-10-11
status: complete
---

# Phase 1 Plan 01: Трассер — UsageCore, Xcode-проект, app→App Group→виджет Summary

**Пакет UsageCore + проект с двумя таргетами + сквозная цепочка «панель → атомарный JSON в контейнере группы → systemSmall-виджет», с закрытой #if DEBUG инъекцией состояния «ошибка контейнера»**

## Performance

- **Duration:** ~9 min (2026-10-11T21:17:28Z → 21:26:16Z, активная фаза исполнения)
- **Started:** 2026-10-11T21:17:28Z
- **Completed:** 2026-10-11T21:26:16Z
- **Tasks:** 1 (трассер, единственная задача плана)
- **Files created:** 5 производственных (все — новые, greenfield)

## Testing Summary (точные команды и результаты)

| # | Команда (дословно) | Результат |
|---|--------------------|----------|
| 1 | `swift build --package-path Packages/UsageCore` | **PASS** — Build complete! (exit 0; ld-предупреждение CLT о search path — безвредное, известный артефакт CLT) |
| 2 | `swift build --package-path Packages/UsageCore -c release` | **PASS** — Build complete! (exit 0) |
| 3 | `plutil -lint AiUsage.xcodeproj/project.pbxproj` | **PASS** — «OK» (валидный OpenStep-plist) |
| 4 | `swiftc -parse AiUsage/AiUsageApp.swift Widget/TestWidget.swift` | **PASS** — exit 0, синтаксических ошибок нет |
| 5 | `for f in TestRecord.swift AiUsageApp.swift TestWidget.swift; do grep -q '#if DEBUG' "$f" || exit 1; done` | **PASS** — exit 0 (1/4/2 вхождения) |
| 6 | Полная цепочка plan-verify (1&&3&&4&&5) | **PASS** — выполнена 2 раза: первично + повтор для tracer feedback gate (auto-mode off, end-of-phase, verify только automated → перезапуск без чекпоинта) |
| 7 | `swiftc -typecheck -parse-as-library -swift-version 6 … Widget/TestWidget.swift` | **PASS в Debug и Release** — против собранного модуля UsageCore и macOS SDK (CLT) |
| 8 | `swiftc -typecheck -parse-as-library -swift-version 6 … AiUsage/AiUsageApp.swift` | **BLOCKED на CLT** — `external macro implementation type 'SwiftUIMacros.StateMacro' could not be found for macro 'State()'; plugin for module 'SwiftUIMacros' not found` (+2 каскадных «self is immutable» на тех же строках). Плагин SwiftUI-макросов поставляется только с тулчейном Xcode (в `/usr/lib/swift/host/plugins` CLT лишь libSwiftMacros и libObservationMacros — проверено find 2026-10-11). Фактический prerequisite: Xcode. НЕ выдаётся за PASS |
| 9 | semantic probe: извлечённый TestRecordStore (код писателя + #if DEBUG маркер), `swiftc -typecheck -swift-version 6`, temp-файл вне репо | **PASS в Debug и Release** — семантика контейнера/атомарной записи/reload/состояний проверена; из проверки исключён только SwiftUI-клей @main/@State (макросы, см. #8) |
| 10 | Поведенческая проба (temp, скомпилирована с Debug-модулем UsageCore) | **PASS 11/11**: allowlist — точный аргумент → containerUnavailable; отсутствие/другое значение/другой регистр/лишний дефис/хвостовой пробел → nil; аргумент среди других → containerUnavailable; JSON round-trip записи и маркера; ключи «number»/«recordedAt»; вывод: `{"number":7,"recordedAt":"2025-10-09T08:53:20Z"}` |
| 11 | grep по Release-модулю: `debugStateOverride` в Products/Release | **0 вхождений** (в Debug-модуле — присутствует в swiftmodule/swiftdoc/.o/.a): инъекция не существует в Release (T-01-10) |
| 12 | Структурные grep pbxproj (acceptance) | при исполнении плана — PASS по тогдашнему списку; **ремедиация 2026-10-12 (CR-01/02/03, 01-CODE-REVIEW) исправила**: ISA локального пакета → `XCLocalSwiftPackageReference` (канонический, по CocoaPods/Tuist и Apple Food Truck), productType расширения → `com.apple.product-type.app-extension` (штатный тип; `widget-extension` не определён спецификацией Swift Build), copy-фаза → `dstPath = ""` при `dstSubfolderSpec = 13` (иначе двойной PlugIns/PlugIns). Текущее состояние: objectVersion 56; 2 PBXNativeTarget; PRODUCT_NAME «AI Usage Widget» ×2; bundle id com.serzhsharapa.aiusage ×2 / …aiusage.widget ×2; 2×XCSwiftPackageProductDependency; INFOPLIST_FILE/CODE_SIGN_ENTITLEMENTS ×2+×2; MACOSX_DEPLOYMENT_TARGET=15.0 ×6; SWIFT_VERSION=6.0 ×6; CODE_SIGN_STYLE=Automatic ×4; DEVELOPMENT_TEAM="" ×4; plutil -lint OK. Живая загрузка Xcode не проверялась (Xcode отсутствует) — 01-04 |
| 13 | Негативные проверки кода | **PASS**: в Widget/TestWidget.swift нет вызовов записи (removeItem/write/createDirectory/moveItem — 0), нет `TestRecord(number:` (нет подставленных записей), нет ForEach/sorted/sort (edge ordering — ровно одна запись целиком) |
| 14 | Сверка имён конфигурации с планом 01-02 | **PASS**: AiUsage/Info.plist, AiUsage/AiUsage.entitlements, Widget/Info.plist, Widget/AiUsageWidget.entitlements — используются в 01-02-PLAN.md и указаны в pbxproj дословно |

Итого: **14 проверочных групп, 13 PASS, 1 BLOCKED-на-окружении** (№8 — заявленный prerequisite Xcode, отложен в 01-04 планом, не блокирует задачи этого плана).

## Accomplishments

- Локальный пакет UsageCore (tools 6.0, macOS 15, ноль внешних зависимостей) собирается на CLT в Debug и Release.
- Рукописный project.pbxproj (objectVersion 56): два native-таргета, appex встраивается в Contents/PlugIns copy-фазой, product-зависимость UsageCore в Frameworks-фазах ОБЕИХ таргетов, автоподпись с пустым DEVELOPMENT_TEAM (Team впишет владелец в Xcode, Pattern 1).
- Сквозная цепочка проведена через все слои: кнопка «Записать тест» → проба доступа временным файлом внутри приложения-писателя (Pitfall 1) → атомарная запись (временный файл + rename в test-snapshot.json, ISO 8601) → WidgetCenter.reloadTimelines(ofKind:) → TimelineProvider виджета читает тот же файл (только чтение) → одна запись «сейчас» + policy .after(+15 мин).
- Четыре различимых состояния (record/missing/corrupt/containerUnavailable) на обеих поверхностях; демо-данных нет ни в одном (D-07).
- Debug-инъекция «ошибка контейнера»: allowlist из одного точного аргумента, маркер debug-sim-state.json пишет/удаляет только приложение, виджет только читает; машина-доказано отсутствие в Release-компиляции.

## Task Commits

**Коммитов нет — намеренно.** Явный scope родительской задачи запрещает staging/commit/push в этом прогоне («explicit user scope forbids commits»), перезапись atomic-commit-протокола роли gsd-executor задокументирована здесь вместо фальшивого SHA. Все 5 файлов лежат в рабочем дереве (untracked, `git status`: `?? AiUsage.xcodeproj/ ?? AiUsage/ ?? Packages/ ?? Widget/`), HEAD не двигался: `7583e3ae4e34c68c2c4b642031a84a069bed5b18` до и после. Родитель владеет решением о коммите.

## Files Created/Modified

- `Packages/UsageCore/Package.swift` — манифест пакета (tools 6.0, macOS 15, library UsageCore, без зависимостей)
- `Packages/UsageCore/Sources/UsageCore/TestRecord.swift` — TestRecord, TestSnapshotState, testWidgetKind, testSnapshotFileName, appGroupID(from:), фабрики кодека ISO 8601, протокол Debug-инъекции (#if DEBUG)
- `AiUsage.xcodeproj/project.pbxproj` — проект с двумя таргетами, embed-фазой, локальным пакетом и настройками подписи
- `AiUsage/AiUsageApp.swift` — @main MenuBarExtra(.window), TestPanelView (рус.), TestRecordStore (единственный писатель; атомарная запись; reloadTimelines; #if DEBUG маркер)
- `Widget/TestWidget.swift` — @main WidgetBundle, StaticConfiguration «AI Usage Widget - Тест» (только systemSmall), TimelineProvider только-чтение, #if DEBUG чтение маркера

## Decisions Made

- См. key-decisions в frontmatter (имя пакета, локальный пакет — после ремедиации XCLocalSwiftPackageReference, схема через авто-создание, единые литералы/кодек, перенос маркера в стор, форма background).
- Дополнение к протоколу инъекции, не изменившее план: константы `testSnapshotFileName`, `DebugSimStateMarker` и фабрики кодека вынесены в UsageCore — единый источник вместо дублирования строк в двух таргетах (та же логика, которой план защищает group id, Pitfall 6).

## Deviations from Plan

> Ремедиация после code review (2026-10-12, code-fixer по 01-CODE-REVIEW,
> findings CR-01/CR-02/CR-03): три формата project.pbxproj исправлены в производстве —
> ISA локального пакета `XCLocalSwiftPackageReference`, productType расширения
> `com.apple.product-type.app-extension`, `dstPath = ""` при `dstSubfolderSpec = 13`.
> Причины и доказательства — 01-CODE-REVIEW.md и 01-REMEDIATION.json; живая загрузка
> проекта Xcode не выполнялась (Xcode отсутствует) — проверка в 01-04.



### Auto-fixed Issues

**1. [Rule 1 - Bug] Исправлен невызывающийся инициализатор цвета фона виджета**
- **Found during:** Task 1 (дополнительный swiftc -typecheck, инициированный родительским заданием)
- **Issue:** `Color(.windowBackground)` не компилируется — компилятор выбирает `Color<T>(_ color: T) where T: Hashable, T.Resolved == Color.Resolved`, а `WindowBackgroundShapeStyle.Resolved == Never`; ошибка повторялась в обоих состояниях view
- **Fix:** заменено на `Rectangle().fill(.windowBackground)` — корректное употребление ShapeStyle без импорта AppKit
- **Files modified:** Widget/TestWidget.swift
- **Verification:** полный `swiftc -typecheck -parse-as-library -swift-version 6` виджета — PASS в Debug и Release
- **Committed in:** — (коммиты запрещены scope; см. Task Commits)

---

**Total deviations:** 1 автофикс (Rule 1) + 1 уточнение структуры (маркер в стор, тот же файл/поведение).
**Impact on plan:** Правильность восстановлена; объём плана не расширен — все правки внутри пяти разрешённых путей.

## Issues Encountered

- **CLT не содержит плагин SwiftUI-макросов** (`SwiftUIMacros.StateMacro`): полный typecheck `AiUsageApp.swift` невозможен без тулчейна Xcode — точная ошибка приведена в Testing Summary №8. Плановый verify плана (parse-уровень, как определено в 01-01-T1) проходит; полная сборка — 01-04, где отсутствие Xcode = BLOCKED (не PASS). Семантика не-UI логики приложения покрыта пробой стора (№9), семантика виджета — полным typecheck (№7).
- Технический сбой自身的 shell-пробы (zsh не разбивает переменную с флагами на слова) устранён инлайн-флагами; на код не влиял.

## User Setup Required

None — внешние сервисы в этом плане не настраиваются. Установка Xcode и вход Apple ID — план 01-04-T1 (checkpoint human-action, blocking-human, по плану).

## Known Stubs

None — заглушек, пустых значений в UI и подставленных данных нет (проверено негативными grep, Testing Summary №13).

## Next Phase Readiness

- **01-02 готов к исполнению:** pbxproj ссылается на `AiUsage/Info.plist`, `AiUsage/AiUsage.entitlements`, `Widget/Info.plist`, `Widget/AiUsageWidget.entitlements` — имена совпадают с файлами плана 01-02 дословно (сверка проведена). Ключ `AppGroupID` в обоих Info.plist подставит сборка; код читает его через `appGroupID(from: .main)` из своего бандла.
- **Отложено в 01-04 (дизайн плана, не дефект):** валидация pbxproj открытием в Xcode 27, подписанная сборка,_codesign-проверки entitlements, живая приёмка виджета и Debug-демонстрация состояния «ошибка контейнера» (механизм реализован здесь, используется там).
- **Границы соблюдены:** сеть/Keychain не добавлены нигде (network.client появится в AiUsage.entitlements в 01-02 — у app-таргета, не у виджета); тесты пакета не создавались (01-02-T2); прав реального контейнера группы никто не менял; секретов нет.
- Требование PLAT-01 в целом остаётся открытым до приёмки 01-04/01-05 — план 01-01 покрывает свой срез (requirements-completed пуст намеренно).

## Self-Check: PASSED

- [x] `Packages/UsageCore/Package.swift` — существует
- [x] `Packages/UsageCore/Sources/UsageCore/TestRecord.swift` — существует
- [x] `AiUsage.xcodeproj/project.pbxproj` — существует, plutil OK
- [x] `AiUsage/AiUsageApp.swift` — существует, parse OK
- [x] `Widget/TestWidget.swift` — существует, typecheck OK
- [x] Plan-verify целиком — exit 0 (дважды: первично + tracer gate)
- [x] Вне разрешённых путей ничего не записано (temp-пробы — в утверждённом /var/folders/…/T/kilo)

---
*Phase: 01-karkas-xcode-i-lichnaya-podpis*
*Completed: 2026-10-11*
