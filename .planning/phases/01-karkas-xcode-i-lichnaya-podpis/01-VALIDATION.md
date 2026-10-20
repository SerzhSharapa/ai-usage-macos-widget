---
phase: "01"
slug: "karkas-xcode-i-lichnaya-podpis"
status: partial/manual-pending
nyquist_compliant: false
wave_0_complete: true
created: "2026-10-11"
---

# Phase 01 - Validation Strategy

Контракт проверок при выполнении фазы. Основание: `01-RESEARCH.md`, раздел
Validation Architecture; нумерация задач и угроз согласована с PLAN-файлами
01-01…01-05 (ревизия 2, 2026-10-11). Документ не означает успешную сборку или
приёмку. Код проверен 2026-10-12: `swift test` с макрос-плагином (23 pass);
быстрые команды валидны; Wave 0 артефакты 9/9 присутствуют; 01-04/01-05 —
manual/предшественник.

## Test Infrastructure

| Property | Value |
|----------|-------|
| Framework | Swift Testing для контрольной записи и allowlist-инъекции (пакет UsageCore); shell-проверки, негативный harness и системные macOS-инструменты (codesign, security, pluginkit, plutil) для платформы |
| Config file | `Packages/UsageCore/Package.swift` (создаёт 01-01-T1) |
| Quick run command | `swift test --package-path Packages/UsageCore -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`; `bash -n scripts/build.sh scripts/stop-installed.sh scripts/verify-install.sh scripts/diagnostics.sh && bash scripts/verify-install.sh --self-test && bash scripts/stop-installed.sh --self-test && bash scripts/diagnostics.sh --self-test && bash scripts/procstop/self-test.sh && bash scripts/tests/preflight-negative.sh` |
| Full suite command | `bash scripts/build.sh && bash scripts/verify-install.sh` (требует установленного Xcode и personal team — 01-04) |
| Estimated runtime | Полная длительность батареи не измерена; сборка и ручная приёмка отдельно, после 01-04-T1 |

Примечание об имени пакета: вместо предложенного в исследовании `UsageKit`
планировщик выбрал `UsageCore` (discretion, 01-PATTERNS.md) — исключает
переименование в фазе 2; все команды этого документа обновлены согласованно.

Примечания к тестам (2026-10-12):
- Фактические результаты и счётчики: `01-CODE-REVIEW.md`, раунд 4 (0 active / 12 resolved). Swift Testing, verifier, stop-wrapper, diagnostics, native и preflight являются разными батареями, не одним суммарным тестом.
- Обычный `swift test --package-path Packages/UsageCore` на текущем CLT не обнаруживает TestingMacros. Штатный TestingMacros установлен в подкаталоге `plugins/testing`; явный путь в команде выше даёт 23/23 PASS. Это отдельная проблема от отсутствия SwiftUI macro plugin.
- Полная `app` typecheck требует плагин SwiftUI macro, доступный в Xcode; `widget` typecheck проходит через CLT.
- Канонический источник результатов: `01-CODE-REVIEW.md`; проверка кода не подтверждает подпись и работу установленного продукта.

## Sampling Rate

- После каждой задачи: соответствующий тест пакета или проверка сценария (см. карту ниже); при явном разрешении коммитов те же проверки после коммита.
- После каждой волны: доступные быстрые проверки; сборка и проверка установки — волна 3 (после настройки Xcode и подписи в 01-04-T1).
- Перед `/gsd-verify-work`: полный прогон и ручная сверка установленного виджета вне отладчика Xcode (шаги — 01-04-T3, checkpoint:human-verify blocking-human).
- Отсутствие Xcode, подписи или тестов означает BLOCKED/MISSING, не PASS. Проверка синтаксиса не заменяет поведенческую проверку сценария установки.

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 01-01-T1 | 01-01 | 1 | PLAT-01 | T-01-04, T-01-10 | Трассер: типизированное декодирование с состоянием corrupt; Debug-инъекция закрыта #if DEBUG во всех трёх файлах и подменяет только вход производственного маппинга; виджет без встроенной записи и без записей в контейнер | build+syntax+gate | `swift build --package-path Packages/UsageCore && plutil -lint AiUsage.xcodeproj/project.pbxproj && swiftc -parse AiUsage/AiUsageApp.swift Widget/TestWidget.swift && for f in Packages/UsageCore/Sources/UsageCore/TestRecord.swift AiUsage/AiUsageApp.swift Widget/TestWidget.swift; do grep -q '#if DEBUG' "$f" || exit 1; done` | Да — 01-01 | passed/code-verified |
| 01-02-T1 | 01-02 | 2 | PLAT-01 | T-01-01, T-01-02 | Права appex строго песочница+группа (негативные grep по файлу прав и plist); единый литерал группы в 4 файлах; LSUIElement=true | lint+negative-grep | `plutil -lint AiUsage/AiUsage.entitlements Widget/AiUsageWidget.entitlements AiUsage/Info.plist Widget/Info.plist && ! grep -Eq 'network\|keychain' Widget/AiUsageWidget.entitlements && ! grep -Eq 'network\|keychain' AiUsage/Info.plist Widget/Info.plist` | Да — 01-02 | passed/code-verified |
| 01-02-T2 | 01-02 | 2 | PLAT-01 | T-01-04, T-01-10 | Отказоустойчивое декодирование: пустые/повреждённые входы ≠ дефолтные данные и ≠ нули; allowlist инъекции — единственное допущенное значение аргумента, всё прочее nil | unit | `swift test --package-path Packages/UsageCore -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing && ! grep -q 'TestRecord(number:' Widget/TestWidget.swift` | Да — 01-02 | passed/code-verified; TestingMacros override |
| 01-03-T1 | 01-03 | 1 | PLAT-01 | T-01-11, T-01-01 (ref), T-01-02 (ref), T-01-08 (ref) | Верификатор: ожидаемая команда из scripts/expected-team.local (вне git) сравнивается с TeamIdentifier каждого бандла — согласованная чужая команда FAIL; четырёхсторонняя сверка групп (подписи ×2 + Info.plist ×2); точное множество прав appex; срок по каждому бинарю как наблюдение; режим --app-path для staged | syntax+behavior (self-test на фикстурах) | `bash -n scripts/verify-install.sh && bash scripts/verify-install.sh --self-test && grep -q 'expected-team.local' .gitignore && grep -q '/build/' .gitignore` | Да — 01-03 | passed/code-verified |
| 01-03-T2 | 01-03 | 1 | PLAT-01 | T-01-05, T-01-06, T-01-12, T-01-03 | Preflight из пяти независимых проверок; staged-копия проходит ПОЛНУЮ верификацию (--app-path) до закрытия приложения и замены; откат при отказе mv/open; прав каталогов данных не меняет; лог редактируется до персистенции; точный stop-only переход scripts/stop-installed.sh (создаётся этой же задачей): канонический путь без аргументов пути, identity против expected-team ДО любого сигнала, PID только по якорю полного пути исполняемого файла с перепроверкой перед TERM, подтверждённый выход, таймаут=FAIL без эскалации, запуска нет, копии того же bundle id по другому пути не затрагиваются; build.sh делегирует ему шаг закрытия | syntax+behavior (негативный harness, 5 сценариев; self-test stop-only, 6 случаев) | `bash -n scripts/build.sh && bash -n scripts/stop-installed.sh && test -x scripts/build.sh && test -x scripts/stop-installed.sh && test -x scripts/tests/preflight-negative.sh && bash scripts/tests/preflight-negative.sh && bash scripts/stop-installed.sh --self-test` | Да — 01-03 | passed/code-verified |
| 01-03-T3 | 01-03 | 1 | PLAT-01 | T-01-07, T-01-03 | Диагностика редактирует персональные данные до вывода; инструкция D-12 полна (включая expected-team.local ДО первой сборки и Debug-сценарий состояния контейнера с запуском одного экземпляра с аргументом); секретов и непроверенных обещаний нет | doc-structure+syntax | Единая fail-fast цепочка `bash -n scripts/diagnostics.sh && DOC=docs/phase-01-setup.ru.md && grep` обязательных разделов docs (xcode-select, Signing & Capabilities, App Groups, scripts/build.sh, expected-team.local, aiusage-sim-state, Центр уведомлений) `&&` негативный скан секретов — DOC присваивается внутри цепочки, синтаксическая ошибка не перекрывается успехом проверок документа | Да — 01-03 | passed/code-verified |
| 01-04-T1 | 01-04 | 3 | PLAT-01 | T-01-05 (регистр 01-03), T-01-11 (регистр 01-03) | Единственный ручной этап (App Store/Apple ID — только владелец) И запись TeamID в scripts/expected-team.local из Xcode/аккаунта ДО первой сборки (не из подписи продукта); отказ App Groups/автоподписи — явный блокер без обходов | checkpoint human-action (blocking-human) | Проверка агентом после возобновления: `xcode-select -p`, `xcodebuild -version`, `security find-identity -v -p codesigning` (≥1 «Apple Development»), scripts/expected-team.local непуст и содержит одну строку вида TeamID | — | blocked/manual |
| 01-04-T2 | 01-04 | 3 | PLAT-01 | T-01-08, T-01-09 | Интеграция read-only (code-immutable): отказ = находка в SUMMARY + остановка, ремонт — отдельным целевым маршрутом с авторизацией; приёмка по подписанным бинарям против expected-team; срок подписи — измеренное наблюдение по каждому бинарю; durable-статус pending→01-05 | build+integration | `xcodebuild -list -project AiUsage.xcodeproj && bash scripts/build.sh && bash scripts/verify-install.sh && grep -q 'pending' .planning/phases/01-karkas-xcode-i-lichnaya-podpis/01-04-SUMMARY.md` | Создан в 01-03 (сценарии) | blocked/manual |
| 01-04-T3 | 01-04 | 3 | PLAT-01 | T-01-08, T-01-10, T-01-12 (регистр 01-03) | Живой виджет вне отладчика: совпадение номеров, различимость «нет записи»/«запись повреждена» безопасными файловыми сценариями с восстановлением; «ошибка контейнера» — ОБЯЗАТЕЛЬНО на обеих поверхностях через Debug-инъекцию (--debug-сборка, точная stop-only остановка своего Debug-экземпляра scripts/stop-installed.sh: точный путь/identity/PID, подтверждённый выход, таймаут=FAIL, копии того же bundle id не тронуты; AppleScript по bundle id и повторный build.sh --debug не используются), запуск ЕДИНСТВЕННОГО экземпляра с аргументом при старте процесса строго после подтверждённого выхода, БЕЗ изменения прав контейнера; пропуска нет — недоказанность держит checkpoint pending; повторная установка сохраняет запись (после её создания — шаг 7) | checkpoint human-verify (blocking-human) | Шаги 1–8 инструкции задачи; подтверждение владельца фиксируется в SUMMARY с честной пометкой способа демонстрации состояний | — | blocked/manual |
| 01-05-T1 | 01-05 | 4 | PLAT-01 | T-01-09 (регистр 01-04) | Отдельный WAITING.json содержит измеренные даты, waiting-статус, условие возобновления и «не заменители»; итоговый SUMMARY отсутствует до закрытия checkpoint | record+JSON | Команда из 01-05-PLAN.md: Swift/Foundation JSONSerialization, проверки полей и отсутствие completion SUMMARY. Plist-lint для JSON не применяется | — | pending/predecessor |
| 01-05-T2 | 01-05 | 4 | PLAT-01 | T-01-09 (регистр 01-04) | Пересборка после ФАКТИЧЕСКОГО истечения: одна команда по инструкции, verify-install зелёный, запись сохранена; «на следующий день»/далёкая NotAfter/отсутствие профиля — не заменители; изменение критерия — только владельцем, дословно | checkpoint human-verify (blocking-human, отложенный) | По наступлении измеренной даты: `bash scripts/build.sh && bash scripts/verify-install.sh` + результат и дословные наблюдения в итоговом 01-05-SUMMARY.md (создаётся по закрытии checkpoint) | — | pending/predecessor |

Правила карты (из исследования, подтверждены планами ревизии 2): проверочный
сценарий завершается ненулевым кодом при нарушении обязательных условий; даты
подписи измеряются у обоих продуктов — профиль, если присутствует, иначе
фактическая NotAfter применимого сертификата подписи; отсутствие профиля —
наблюдение, не доказательство бессрочности; `security find-identity` срок не
сообщает. У всех runnable-команд PLAN.md задан наблюдаемый сигнал отказа
(`fails_when`). Фаза не завершается до результата 01-05-T2 (или дословного
изменения критерия владельцем).

## Wave 0 Requirements → назначение

- [x] `Packages/UsageCore/Package.swift` + TestRecord с состояниями и allowlist-инъекцией (без контракта фазы 2) → 01-01-T1.
- [x] `AiUsage/AiUsage.entitlements`, `Widget/AiUsageWidget.entitlements`, `AiUsage/Info.plist`, `Widget/Info.plist` → 01-02-T1.
- [x] `Packages/UsageCore/Tests/UsageCoreTests/TestRecordTests.swift` (состояния + allowlist) → 01-02-T2.
- [x] `scripts/verify-install.sh` (+ `.gitignore` для expected-team.local и /build/): подпись, ожидаемая команда, четырёхсторонняя сверка групп, фактические entitlements обоих продуктов, регистрация расширения, срок подписи как наблюдение → 01-03-T1.
- [x] `scripts/build.sh`: preflight из пяти проверок, сборка (Release/--debug), полная staged-верификация до закрытия/замены, безопасная замена, запуск, локальный лог (шаг закрытия делегирует stop-installed.sh) → 01-03-T2.
- [x] `scripts/stop-installed.sh` и `scripts/procstop/main.swift`: stop-only переход, identity и целостность бандла до сигнала, canonical boundary без symlink-побегов; путь процесса из ядра (`proc_pidpath`) и birth identity перепроверяются перед TERM; отказ инспекции и таймаут дают FAIL, запуска нет. Wrapper и native self-tests проверяют отдельные контракты → 01-03-T2 и ремедиация.
- [x] `scripts/tests/preflight-negative.sh`: пять независимых негативных сценариев в изолированных песочницах → 01-03-T2.
- [x] `scripts/diagnostics.sh`: диагностика без ключей, токенов и персональных данных → 01-03-T3.
- [x] `docs/phase-01-setup.ru.md` (D-12, включая expected-team.local и Debug-сценарий) пишется вместе с кодом, не Wave 0 → 01-03-T3.

## Edge / Prohibition учёт (spec-less probe fallback, 2026-10-11)

SPEC-файл фазы отсутствует (обе секции не поставлены) — применён протокол
specless-probe-fallback. Проверки детекторов этой сессии:
api-coverage `detected:false` (внешних API в фазе нет — COVERAGE.md не требуется),
assumption-delta `detected:false`, schema-push — ORM отсутствует (skip),
UI plan-gate `block:false` (UI-SPEC не требуется; панель D-05 — диагностическая).

Edge-проба (3 применимых, все разрешены явно, без тихих отбрасываний):

| Edge (PLAT-01) | Вопрос пробы | Разрешение | Куда авторизовано |
|----------------|--------------|------------|-------------------|
| adjacency | Соприкосновение таргетов через общую группу | explicit: один литерал `$(DEVELOPMENT_TEAM).group.aiusage`; verify-install.sh сверяет развёрнутые массивы подписанных бинарей И AppGroupID обоих Info.plist (четырёхсторонне), падает при несовпадении | 01-02 truths, 01-03-T1 (п. d), 01-04 truths; T0112 — map security stop behavior=true, actual corrected |
| empty | Результат для пустого/отсутствующего/повреждённого входа | explicit: пустой объект, мусор, null-поля → состояние «запись повреждена»; файла нет → «нет записи»; никогда дефолтные данные/нули/демо | 01-01 truths, 01-02-T2 тесты, 01-04-T3 human-check |
| ordering | Порядок при равных элементах | explicit: поверхности фазы 1 отображают ровно одну запись целиком; списков и сортировок нет — упорядочивание неприменимо | 01-01 truths |

Счёт no-silent-drop (edges): применимо 3 = авторизовано 3 (explicit) + backstop 0 + неразрешённых/помеченных допущений 0.

Prohibition-проба (recall→precision; canon-элементы переданы по breadcrumbs в
`/gsd-secure-phase` — инъекция путей в shell и общие OWASP-категории; routine-
engineering отброшены: краш на невалидном JSON — вотчина edge-пробы, идемпотентность
и утечки ресурсов — код-ревью). Оставлено 8, все авторизованы descriptor-less
(без check_*-дескрипторов; disposition — unverified/flagged):

| # | Запрет (MUST NOT) | Категория | План |
|---|-------------------|-----------|------|
| 1 | Виджет не подставляет встроенные демо-данные вместо отсутствующей/повреждённой/недоступной записи | transparency | 01-01 |
| 2 | Сценарий сборки не подменяет молча подпись (ad-hoc/локальная/без песочницы) при отказе | transparency | 01-03 |
| 3 | Сценарии не затрагивают ничего кроме ровно одного своего бандла; Корзина вместо удаления; права каталогов данных не меняются | safety | 01-03 |
| 4 | Логи не содержат секретов/персональных данных и не попадают в git | privacy | 01-03 |
| 5 | Приёмка не по чекбоксам Xcode, а по подписанным бинарям обоих продуктов | transparency | 01-04 |
| 6 | Срок подписи не выдумывается: только измеренные даты или факт отсутствия профиля; ожидание до факта живёт в 01-05-WAITING.json, итоговый SUMMARY — только после закрытия checkpoint | transparency | 01-04, 01-05 |
| 7 | Debug-инъекция не существует в Release и не меняет прав реального контейнера; инъекция не выдаётся на приёмке за реальную ошибку контейнера | safety | 01-01, 01-04 |
| 8 | Интеграция (01-04-T2) не правит артефакты планов 01-01/01-02/01-03: отказы маршрутизируются на целевой ремонт с явной авторизацией | scope | 01-04 |

Счёт no-silent-drop (prohibitions): оставлено 8 = авторизовано 8 + помеченных допущений 0.

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Установка Xcode и вход Apple ID/personal team | PLAT-01 | Действия владельца с аккаунтом и App Store | 01-04-T1 (checkpoint, инструкция docs/phase-01-setup.ru.md); отказ фиксировать блокером |
| Виджет в Центре уведомлений читает запись app | PLAT-01 | Системная галерея и визуальное сравнение не автоматизируются | 01-04-T3 (checkpoint:human-verify, blocking) шаги 1–5: запуск вне Xcode, добавление systemSmall, запись теста, сверка номеров, повторная запись |
| Нет записи / повреждена различаются | PLAT-01 | Отображение состояний проверяется отдельно от unit-теста | 01-04-T3 шаги 6a–6b: безопасные файловые сценарии с ОБЯЗАТЕЛЬНЫМ восстановлением (переименование/порча собственного тестового файла); без удаления пользовательского контейнера и без записей расширения |
| «Ошибка контейнера» показана на ОБЕИХ поверхностях | PLAT-01 | GUI двух процессов; реальные мутации прав контейнера запрещены (безопасность данных) | 01-04-T3 шаг 6c: `bash scripts/build.sh --debug`; точная stop-only остановка своего Debug-экземпляра `bash scripts/stop-installed.sh` (канонический путь, identity CFBundleIdentifier+TeamIdentifier против expected-team, PID по точному пути исполняемого файла с перепроверкой, TERM, подтверждённый фактический выход, таймаут=FAIL; копии того же bundle id по другому пути не затрагиваются; AppleScript по bundle id и повторный `build.sh --debug` не используются — не различают копии одного bundle id / запускают новый экземпляр); после подтверждённого выхода `open … --args -aiusage-sim-state=containerUnavailable` — ЕДИНСТВЕННЫЙ экземпляр получает аргумент при старте (ProcessInfo.arguments стартовый): панель и виджет показывают состояние, запись не создаётся; возврат Release обычной пересборкой (автозапуск без аргументов), контрольная запись сохраняется; способ (инъекция) честно помечается в SUMMARY; пропуска нет — недоказанность держит checkpoint pending |
| Повторная установка сохраняет данные и запускает новую сборку | PLAT-01 | Системные процессы на машине владельца | 01-04-T3 шаг 7 (после создания записи); 01-04-T2 шаг 5 до первой записи проверяет лишь отсутствие test-snapshot.json после переустановки (переустановка запись не создаёт) |
| Пересборка при фактическом истечении подписи | PLAT-01 | Срок зависит от полученных профилей/сертификатов; наблюдение невозможно до факта | 01-04-T2 шаг 4 фиксирует измеренные даты ПО КАЖДОМУ бинарю (профиль либо NotAfter применимого сертификата) с durable-статусом pending; 01-05-T1 создаёт отложенный протокол ожидания 01-05-WAITING.json (non-summary — итоговый SUMMARY только после закрытия checkpoint); 01-05-T2 (blocking, отложенный): по наступлении фактического истечения владелец пересобирает одной командой и фиксирует результат; «на следующий день», далёкая NotAfter и отсутствие профиля заменой не являются; предположение о семи днях не используется; изменение критерия — только владельцем, дословно |

## Validation Sign-Off

- [ ] Каждая задача имеет automated verify или явную зависимость от Wave 0.
- [ ] Нет трёх последовательных задач без автоматической проверки.
- [ ] Все MISSING-пути создаются до использования.
- [ ] Нет watch-mode команд.
- [x] Заданы наблюдаемые сигналы отказа (`fails_when`) у всех runnable команд PLAN.md (заполнено при планировании 2026-10-11, перезаписано в ревизии 2; подтверждается исполнением).
- [x] Автоматизированные проверки: наличие/троечность/MISSING/watch — verified true (evidence: CODE-REVIEW); не измерено — mark notmeasured, no estimate.
- [ ] Быстрый feedback измерен; сборка и ручные проверки не выданы за быстрый тест.
- [ ] Ручная приёмка проведена вне отладчика.
- [ ] `nyquist_compliant: true` устанавливается только после соответствующей проверки.

**Approval:** manual receipt = false, nyquist approval = false
