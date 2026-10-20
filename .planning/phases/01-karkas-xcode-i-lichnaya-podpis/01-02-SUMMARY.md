---
phase: 01-karkas-xcode-i-lichnaya-podpis
plan: "02"
subsystem: infra
tags: [entitlements, info-plist, app-groups, app-sandbox, swift-testing, swift-package-manager, widgetkit, macos]

requires:
  - phase: 01-01
    provides: "AiUsage.xcodeproj с дословными ссылками INFOPLIST_FILE/CODE_SIGN_ENTITLEMENTS на четыре конфиг-файла; UsageCore с TestRecord/TestSnapshotState, appGroupID(from:), #if DEBUG allowlist-инъекцией и константами маркера"
provides:
  - Четыре конфигурационных файла подписи и списков (2 entitlements + 2 Info.plist), подключённые project.pbxproj плана 01-01 дословно по путям
  - Изоляция таргетов: у app ровно три права (sandbox, network.client, одна App Group), у расширения ровно два (sandbox, та же группа); сетевых и keychain-ключей у расширения нет (PLAT-01, T-01-01/T-01-02)
  - Единый литерал группы $(DEVELOPMENT_TEAM).group.aiusage ровно в одной форме во всех четырёх файлах (ключ AppGroupID читается appGroupID(from:) в рантайме)
  - 14 Swift Testing-тестов UsageCoreTests: декодирование valid/empty/мусор/null/неверные типы + roundtrip; allowlist-инъекция — точный аргумент/среди других/пустой массив/обычные аргументы/опечатка/чужое значение/чужие формы; константы маркера
  - Тестовый таргет UsageCoreTests в Package.swift (минимальное Rule 3-дополнение манифеста 01-01)
affects: [01-04, 01-05, phase-2]

actuals:
  tokens: 3600      # chars/4 по 5 созданным файлам (14 349 байт, wc -c) + дельта манифеста ~10 строк
  tasks: 2
  commits: 0        # коммиты запрещены явным scope родителя («No git commits/staging/tag/push»); HEAD не двигался: 7583e3ae… до и после — SHA не имитировался
  plan_head_before: 7583e3ae4e34c68c2c4b642031a84a069bed5b18
  plan_head_after: 7583e3ae4e34c68c2c4b642031a84a069bed5b18

tech-stack:
  added: []         # внешних зависимостей нет; Swift Testing — штатная библиотека CLT (T-01-SC: новых установок и зависимостей конфиги и тесты не вводят)
  patterns:
    - "Единый литерал группы: $(DEVELOPMENT_TEAM).group.aiusage в обоих entitlements и обоих Info.plist — одна форма, четыре файла (Pitfall 6)"
    - "Рантайм-ключ AppGroupID в Info.plist использует сборочный параметр (DEVELOPMENT_TEAM), а не codesign-плейсхолдер — подстановку делает обработка Info.plist, читает appGroupID(from:)"
    - "Негативные grep-ограничители ('network|keychain') — часть контракта файлов: слова-триггеры не встречаются даже в комментариях конфигов"

key-files:
  created:
    - AiUsage/AiUsage.entitlements
    - Widget/AiUsageWidget.entitlements
    - AiUsage/Info.plist
    - Widget/Info.plist
    - Packages/UsageCore/Tests/UsageCoreTests/TestRecordTests.swift
  modified:
    - Packages/UsageCore/Package.swift   # только .testTarget — Rule 3, уведомление родителю отправлено до правки

key-decisions:
  - "Литерал группы $(DEVELOPMENT_TEAM).group.aiusage вместо планового $(AppIdentifierPrefix)group.aiusage — прямая директива родителя в dispatch; техническое основание: Info.plist-обработка разворачивает только build settings, $(AppIdentifierPrefix) — плейсхолдер этапа codesign и в Info.plist остался бы литералом → appGroupID(from:) вернул бы неразвёрнутую строку → containerUnavailable везде → четырёхсторонняя сверка 01-03 упала бы в 01-04. Инвариант «одна форма в четырёх файлах» сохранён (edge adjacency); DEVELOPMENT_TEAM — реальный build setting из pbxproj (проверено grep ×4)"
  - "CFBundlePackageType: APPL (app, дословно по плану) и XPC! (appex — пакетный тип extension-бандла); план для виджета требовал только «те же базовые ключи» без значения"
  - "Комментарии конфиг-файлов не содержат латинских слов network/keychain — файлы обязаны проходить собственный негативный grep верификации даже комментариями"
  - "Тесты декодирования доказывают corrupt через #expect(throws:) — дефолтного TestRecord и «нулей» не существует по устройству типа; allowlist покрыт 7 случаями, включая аргумент среди других и константу debugSimStateArgument"
  - "Release-исключение инъекции помечено в тесте честным комментарием (план): функция живёт в #if DEBUG плана 01-01; отдельного Release-теста нет — в Release-компиляции символа не существует (доказано grep: 0 вхождений в Products/Release, 6 в Debug)"

patterns-established:
  - "Конфиг-файлы самодокументированы русскими комментариями с ссылками на Pitfall/Threat-ID — ограничения видны в самом файле"
  - "Верификация конфигов: plutil -lint + негативные grep + структурные plutil -extract с экранированием точек в ключах (esc-форма com\\.apple\\.…) и без экранирования для вложенных keypath (NSExtension.NSExtensionPointIdentifier)"

requirements-completed: []   # PLAT-01 закрывается только приёмкой 01-04/01-05 (включая 01-05 ожидание фактического истечения); этот план — исходная точность конфигов и тестов

coverage:
  - id: D1
    description: "Четыре конфиг-файла валидны (plutil), пути дословно совпадают с INFOPLIST_FILE/CODE_SIGN_ENTITLEMENTS pbxproj; у app LSUIElement=true + LSMinimumSystemVersion 15.0 + имя «AI Usage Widget»; у виджета NSExtensionPointIdentifier=com.apple.widgetkit-extension; ключ AppGroupID в обоих plist"
    requirement: PLAT-01
    verification:
      - kind: other
        ref: "plutil -lint AiUsage/AiUsage.entitlements Widget/AiUsageWidget.entitlements AiUsage/Info.plist Widget/Info.plist — OK×4, rc=0"
        status: pass
      - kind: other
        ref: "plutil -extract: app-sandbox=true, network.client=true (app); appex — ровно 2 ключа {app-sandbox, application-groups}; LSUIElement=true; LSMinimumSystemVersion=15.0; NSExtension.NSExtensionPointIdentifier=com.apple.widgetkit-extension — все rc=0"
        status: pass
      - kind: other
        ref: "grep -c 'group\\.aiusage' — ровно 1 вхождение в каждый из 4 файлов; форма $(DEVELOPMENT_TEAM).group.aiusage; других форм (AppIdentifierPrefix/TeamIdentifierPrefix/жёсткий TeamID) нет — grep CLEAN"
        status: pass
    human_judgment: false
  - id: D2
    description: "Изоляция расширения (T-01-02): в Widget/AiUsageWidget.entitlements нет network.*, keychain* и любых посторонних ключей; негативный grep по всем четырём файлам"
    requirement: PLAT-01
    verification:
      - kind: other
        ref: "! grep -Eq 'network|keychain' Widget/AiUsageWidget.entitlements — rc=0; ! grep -Eq 'network|keychain' AiUsage/Info.plist Widget/Info.plist — rc=0; plutil -convert json: count=2 ключа"
        status: pass
    human_judgment: false
  - id: D3
    description: "23 теста UsageCoreTests (ремедиация 2026-10-12 CR-06/WR-05, было 14): valid/empty/мусор/null/неверные типы → corrupt (throws), roundtrip; границы номера — Int.max/отрицательный/ноль отвергаются декодером, maxSafeNumber допущен, nextNumber — проверенный инкремент с перезапуском на границе; allowlist: точный аргумент → containerUnavailable, всё прочее → nil; классификация ошибок чтения файла — ENOENT → missing, отказ доступа → containerUnavailable (реальные файлы во ВРЕМЕННОМ каталоге теста, не групповой контейнер)"
    requirement: PLAT-01
    verification:
      - kind: unit
        ref: "swift test --package-path Packages/UsageCore (CLT, Debug, с явным plugin-path) — Test run with 23 tests in 1 suite passed, rc=0 (ремедиация: 2026-10-11 — 14/14)"
        status: pass
      - kind: other
        ref: "! grep -q 'TestRecord(number:' Widget/TestWidget.swift — rc=0 (в виджете нет встроенной записи); после ремедиации WR-05 тесты СОДЕРЖАТ файловые проверки классификации ошибок чтения — только NSTemporaryDirectory(), без containerURL и без реального группового контейнера"
        status: pass
    human_judgment: false
  - id: D4
    description: "Развёртывание $(DEVELOPMENT_TEAM) до <TeamID>.group.aiusage в обработанных entitlements и Info.plist подписанных продуктов (четырёхсторонняя сверка verify-install.sh с ожидаемой командой)"
    requirement: PLAT-01
    verification:
      - kind: other
        ref: "DEVELOPMENT_TEAM присутствует в pbxproj ×4 (пуст до ввода TeamID владельцем — docs/phase-01-setup.ru.md); исходный литерал во всех 4 файлах един"
        status: pass
    human_judgment: true
    rationale: "Полная подстановка происходит на этапе сборки/подписи Xcode — xcodebuild на машине недоступен (xcode-select → CommandLineTools, xcodebuild -version: требует Xcode, факт 2026-10-11); доказательство по подписанным бинарям — план 01-04 (verify-install.sh п. c/d)"

duration: 17 min
completed: 2026-10-11
status: complete
---

# Phase 1 Plan 02: Права и Info.plist обоих таргетов + тесты состояний записи Summary

**Четыре конфиг-файла с единым литералом группы и изоляцией appex (ровно два права) плюс Swift Testing-тесты декодирования состояний и allowlist Debug-инъекции (14 при исполнении плана; 23 после ремедиации CR-06/WR-05 от 2026-10-12)**

## Performance

- **Duration:** ~17 min (2026-10-11T22:04:56Z → 22:21:59Z)
- **Started:** 2026-10-11T22:04:56Z
- **Completed:** 2026-10-11T22:21:59Z
- **Tasks:** 2/2
- **Files created/modified:** 6 (5 создано, 1 минимально дополнен по Rule 3)

## Testing Summary (точные команды и результаты)

| # | Команда (дословно) | Результат |
|---|--------------------|----------|
| 1 | `plutil -lint AiUsage/AiUsage.entitlements Widget/AiUsageWidget.entitlements AiUsage/Info.plist Widget/Info.plist` | **PASS** — OK ×4, rc=0 |
| 2 | `! grep -Eq 'network\|keychain' Widget/AiUsageWidget.entitlements` и то же для `AiUsage/Info.plist Widget/Info.plist` | **PASS** — rc=0/0 (изоляция расширения; в plist тоже нет сетевых/keychain-ключей) |
| 3 | `plutil -extract` структурно: app-sandbox=true, network.client=true, application-groups=`["$(DEVELOPMENT_TEAM).group.aiusage"]` (app); appex — ровно 2 ключа (plutil -convert json: count=2); LSUIElement=true; LSMinimumSystemVersion=15.0; NSExtension.NSExtensionPointIdentifier=com.apple.widgetkit-extension | **PASS** — все значения точные (ключи с точками — в экранированной форме `com\\.apple\\.…`, вложенный — без экранирования) |
| 4 | `grep -c 'group\\.aiusage'` по 4 файлам + `grep … \| grep -v '\$(DEVELOPMENT_TEAM)\\.group\\.aiusage'` | **PASS** — ровно 1 вхождение в каждый файл, других форм группы нет (CLEAN) |
| 5 | `swift test --package-path Packages/UsageCore` | **PASS** — при исполнении плана 14/14; после ремедиации CR-06/WR-05 (2026-10-12) — 23/23, rc=0 |
| 6 | `swift test … -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing` | **PASS** — 14/14 на момент плана (ремедиация: 23/23); в том числе ПОСЛЕ `swift build -c release` (без флага падал 3/3 — Issues №1); надёжная инвокация для этого CLT |
| 7 | `! grep -q 'TestRecord(number:' Widget/TestWidget.swift` | **PASS** — rc=0 (в коде виджета нет встроенной записи) |
| 8 | `swift build --package-path Packages/UsageCore -c release` | **PASS** — Build complete!, rc=0 |
| 9 | `grep -rl debugStateOverride .build/out/Products/Release` vs `Products/Debug` | **PASS** — 0 вхождений в Release, 6 в Debug: инъекция не существует в Release (T-01-10, продолжение доказательства 01-01) |
| 10 | grep FileManager/Data(contentsOf по тесту | на момент плана — 0 вхождений (чистые функции); после ремедиации WR-05 — файловые проверки классификации ошибок чтения ЕСТЬ, но только во временном каталоге теста (NSTemporaryDirectory), containerURL в тестах нет |
| 11 | Макросы конфигов: `$(DEVELOPMENT_TEAM)` ×4, `$(EXECUTABLE_NAME)` ×2, `$(PRODUCT_BUNDLE_IDENTIFIER)` ×2; в pbxproj есть DEVELOPMENT_TEAM ×4 и PRODUCT_BUNDLE_IDENTIFIER ×2 | **PASS** — каждый макрос — реальный build setting (EXECUTABLE_NAME — штатный); жёстких TeamID нет нигде; читаемость: каждый макрос снабжён комментарием «зачем» |
| 12 | Имена файлов vs pbxproj: INFOPLIST_FILE = AiUsage/Info.plist ×2, Widget/Info.plist ×2; CODE_SIGN_ENTITLEMENTS = AiUsage/AiUsage.entitlements ×2, Widget/AiUsageWidget.entitlements ×2 | **PASS** — дословное совпадение всех четырёх путей |

Полный verify цепочкой (T1 && T2) — PASS в финальном прогоне (rc=0). Заявленный планом verify без флага из №6 проходит, когда авто-обнаружение плагина срабатывает (проверено дважды, №5); флаг делает прогон детерминированным (№6).

## Accomplishments

- Подписочная конфигурация обоих таргетов создана и подключена к существующему project.pbxproj дословно по путям: app — sandbox + network.client + одна App Group; appex — ровно sandbox + та же группа; сетевых и keychain-прав у расширения нет (Pitfall 5, T-01-02).
- Идентификатор группы существует в исходниках ровно в одной форме — `$(DEVELOPMENT_TEAM).group.aiusage` — во всех четырёх файлах (edge «adjacency»); рантайм читает его из ключа AppGroupID через `appGroupID(from:)` плана 01-01.
- App-Info.plist: LSUIElement=true (без Dock, D-05), имя «AI Usage Widget» (D-09), LSMinimumSystemVersion 15.0; Widget-Info.plist: NSExtensionPointIdentifier com.apple.widgetkit-extension без NSExtensionPrincipalClass (вход @main из 01-01).
- Тесты UsageCoreTests доказывают: валидный JSON → равный TestRecord; пустой объект, не-JSON мусор, null-поля, неверные типы → corrupt (бросок, никогда не дефолтные значения и не нули — D-06/D-07); roundtrip сохраняет значения; allowlist-инъекция допускает ТОЛЬКО точный аргумент, всё остальное — nil; константы маркера объявлены и согласованы. Ремедиация CR-06/WR-05 (2026-10-12, 01-CODE-REVIEW): номера вне диапазона 1…Int.max-1 отвергаются декодером; nextNumber — проверенный инкремент (граница → перезапуск с 1); ENOENT → missing, отказ доступа/I-O → containerUnavailable (не corrupt); итого 23 теста.
- Тестовый таргет добавлен в Package.swift минимальной правкой (Rule 3, уведомление родителю с доказательством отправлено до правки); внешних зависимостей не появилось (T-01-SC).

## Task Commits

**Коммитов нет — намеренно.** Явный scope родительской задачи запрещает commits/staging/tag/push в этом прогоне; прецедент честной фиксации — SUMMARY 01-01 и 01-03. HEAD не двигался: `7583e3ae4e34c68c2c4b642031a84a069bed5b18` до и после (`git rev-parse HEAD`). Все шесть файлов лежат в рабочем дереве (`git status`: внутри untracked `AiUsage/`, `Widget/`, `Packages/`); решение о коммите — за родителем.

## Files Created/Modified

- `AiUsage/AiUsage.entitlements` — три права app: app-sandbox, network.client, одна App Group (единый литерал)
- `Widget/AiUsageWidget.entitlements` — ровно два права расширения: app-sandbox + та же App Group; ничего кроме двух ключей
- `AiUsage/Info.plist` — LSUIElement=true, имя «AI Usage Widget», APPL, версия 1.0/1, macOS 15, ключ AppGroupID
- `Widget/Info.plist` — базовые ключи + NSExtension{widgetkit-extension} + AppGroupID; XPC! как пакетный тип appex
- `Packages/UsageCore/Tests/UsageCoreTests/TestRecordTests.swift` — 14 Swift Testing-тестов: декодирование (6) + allowlist (7) + константы (1); чистые функции, без ФС
- `Packages/UsageCore/Package.swift` — добавлен только `.testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"])` (Rule 3)

## Decisions Made

- См. key-decisions в frontmatter: литерал группы по директиве родителя с техническим обоснованием; XPC! для appex; слова-триггеры негативного grep исключены даже из комментариев; corrupt доказывается бросками; честная пометка про Release в тесте.

## Deviations from Plan

> Ремедиация после code review (2026-10-12, исполнитель код-фиксера по 01-CODE-REVIEW):
> в этот SUMMARY внесены только фактические коррекции утверждений о тестах
> (счётчик 14 → 23, появление файловых проверок классификации ошибок чтения).
> Сами правки производства — CR-06 (валидация диапазона номера и проверенный
> инкремент в UsageCore/AiUsageApp.swift) и WR-05 (разведение ошибок чтения и
> декодирования в обоих таргетах); записи — 01-REMEDIATION.json.


### Auto-fixed Issues

**1. [Rule 3 - Blocking] В Package.swift отсутствовал тестовый таргет**
- **Found during:** Task 2 (первый прогон verify)
- **Issue:** манифест 01-01 объявляет только `.target(name: "UsageCore")`; `swift test` завершался «error: no tests found; create a target in the 'Tests' directory» — verify задачи неисполним
- **Fix:** добавлен `.testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"])`; больше в манифесте ничего не менялось; родитель уведомлен дословным доказательством ДО правки (board, 22:05Z), правка предразрешена dispatch
- **Files modified:** Packages/UsageCore/Package.swift
- **Verification:** swift test — 14/14 PASS (таблица №5/№6)
- **Committed in:** — (коммиты запрещены scope; см. Task Commits)

**2. [Директива родителя + Rule 1 - превентивный баг] Литерал группы $(DEVELOPMENT_TEAM)… вместо планового $(AppIdentifierPrefix)…**
- **Found during:** Task 1 (до записи файлов)
- **Issue:** план требовал `$(AppIdentifierPrefix)group.aiusage` во всех четырёх файлах; в Info.plist-обработке разворачиваются только build settings — AppIdentifierPrefix (плейсхолдер codesign) остался бы литералом, рантайм получил бы неразвёрнутый id группы, состояние containerUnavailable везде и провал четырёхсторонней сверки 01-03 в 01-04
- **Fix:** единый литерал `$(DEVELOPMENT_TEAM).group.aiusage` по прямой директиве родителя в dispatch; инвариант «одна форма в четырёх файлах» сохранён; residual-доказательство развёртывания — подписанные бинари 01-04 (честно не заявляется)
- **Files modified:** все четыре конфиг-файла
- **Verification:** таблица №3/№4; pbxproj содержит DEVELOPMENT_TEAM ×4
- **Committed in:** — (см. Task Commits)

---

**Total deviations:** 2 (1 Rule 3 — разрешённый prerequisite; 1 директива родителя с Rule 1-обоснованием) + 2 микрорешения (XPC!, комментарная гигиена grep-ограничителей) в key-decisions.
**Impact on plan:** объём не расширен; все правки в шести путях (5 из них — собственные файлы плана, 6-й — минимальный разрешённый prerequisite).

## Issues Encountered

1. **Ненадёжное авто-обнаружение TestingMacros в CLT SwiftPM 6.4 (новый layout `.build/out`):** чистый `swift test` ПРОХОДИЛ (2/4 попыток: первый прогон и первая чистая пересборка — 14/14), но после любого промежуточного `swift build` (release или debug) следующий `swift test` падал компиляцией «external macro implementation type 'TestingMacros.…' could not be found … plugin for module 'TestingMacros' not found» — в команде фроненда исчезал `-load-resolved-plugin …/plugins/testing/libTestingMacros.dylib` (остались только Observation/Swift). Плагин физически существует (`ls /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/` — libTestingMacros.dylib, 751024 байт). Не дефект кода плана: файл тестов не менялся между PASS и FAIL. **Надёжная инвокация (зафиксирована):** `swift test --package-path Packages/UsageCore -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing` — детерминированно PASS, включая воспроизведённый «падающий» сценарий build release → test. Первоначальная гипотеза «виновата параллельность двух SwiftPM» опровергнута воспроизведением падения и на строго последовательных прогонах. Повреждённые `.build`-каталоги не удалялись, а перемещались в Корзину (`mv .build ~/.Trash/usagecore-dotbuild-<ts>`; листинг Корзины TCC-запрещён, сами mv отработали без ошибок).
2. plutil-ключи с точками — разделители keypath (уже известный с 01-03 факт): проверки прав — в экранированной форме `com\\.apple\\.security\\.…`, вложенный NSExtension-ключ — без экранирования. На файлы не влияет.

## User Setup Required

None в этом плане. Установка Xcode, вход Apple ID и ввод Team в оба таргета (заполнит DEVELOPMENT_TEAM) — план 01-04-T1 (checkpoint human-action, blocking-human, инструкция docs/phase-01-setup.ru.md).

## Known Stubs

None — заглушек, подставленных данных и пустых значений в UI нет; тесты доказывают отсутствие дефолтов на уровне типа (corrupt = бросок декодера).

## Threat Flags

None — новой поверхности вне threat_model плана не создано: T-01-01 закрыт единым литералом в четырёх файлах; T-01-02 — ровно двумя правами расширения (негативные grep); T-01-SC — внешних пакетов/установок нет (Swift Testing — штатная библиотека CLT).

## Next Phase Readiness

- **01-04 получает:** валидные конфиг-файлы по дословным путям pbxproj; ключ AppGroupID развёртывается сборкой в обоих таргетах; тестовый таргет зелёный (надёжная инвокация — Issues №1); после установки Xcode verify-install.sh сверит развёрнутые группы подписанных бинарей и обоих Info.plist (п. d) и точные множества прав (п. c).
- **Для следующих исполнителей:** запускать `swift test` этого пакета с флагом `-Xswiftc -plugin-path …/plugins/testing` (или первым после чистого `.build`) — см. Issues №1; не запускать два SwiftPM-процесса одного пакета параллельно.
- **PLAT-01 остаётся открытым** до приёмки 01-04 и наблюдения истечения 01-05 — requirements-completed пуст намеренно; семидневный срок нигде не заявляется как факт.
- Коммиты по-прежнему за родителем: HEAD 7583e3ae не двигался; файлы плана в рабочем дереве.

## Self-Check: PASSED

- [x] AiUsage/AiUsage.entitlements — существует, plutil OK
- [x] Widget/AiUsageWidget.entitlements — существует, plutil OK, ровно 2 ключа
- [x] AiUsage/Info.plist — существует, plutil OK, LSUIElement=true
- [x] Widget/Info.plist — существует, plutil OK, NSExtensionPointIdentifier точен
- [x] Packages/UsageCore/Tests/UsageCoreTests/TestRecordTests.swift — существует, 14/14 PASS (rc=0)
- [x] Packages/UsageCore/Package.swift — .testTarget добавлен, swift build release rc=0
- [x] Полный plan-verify — rc=0; HEAD 7583e3ae не менялся; вне шести разрешённых путей ничего не записано (`.build` — gitignored артефакт, перемещался только в Корзину)

---
*Phase: 01-karkas-xcode-i-lichnaya-podpis*
*Completed: 2026-10-11*
