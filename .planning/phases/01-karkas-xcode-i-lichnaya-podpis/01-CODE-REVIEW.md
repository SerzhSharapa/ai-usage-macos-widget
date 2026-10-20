---
phase: 01-karkas-xcode-i-lichnaya-podpis
reviewed: 2026-10-12T00:59:00Z
review_round: 4
initial_reviewed: 2026-10-11T22:37:28Z
depth: deep
files_reviewed: 19
files_reviewed_list:
  - .gitignore
  - AiUsage.xcodeproj/project.pbxproj
  - AiUsage/AiUsageApp.swift
  - AiUsage/Info.plist
  - AiUsage/AiUsage.entitlements
  - Widget/TestWidget.swift
  - Widget/Info.plist
  - Widget/AiUsageWidget.entitlements
  - Packages/UsageCore/Package.swift
  - Packages/UsageCore/Sources/UsageCore/TestRecord.swift
  - Packages/UsageCore/Tests/UsageCoreTests/TestRecordTests.swift
  - scripts/build.sh
  - scripts/verify-install.sh
  - scripts/stop-installed.sh
  - scripts/diagnostics.sh
  - scripts/tests/preflight-negative.sh
  - docs/phase-01-setup.ru.md
  - scripts/procstop/main.swift
  - scripts/procstop/self-test.sh
findings:
  critical: 0
  warning: 0
  info: 0
  total: 0
status: clean
reviewer_model: openai/gpt-6.1-sol
reviewer_family: OpenAI
requested_effort: high
quality_attempt_count_before_review: 2
remediation_attempt_reviewed: 3
latest_author_family: Kimi
production_edits: false
integration_status: blocked_not_verified
---

# Phase 01: независимый Code Review

## Narrative Findings (AI reviewer) — текущий раунд 4

**NO FINDINGS / REVIEW PASSED — только доступные code/test проверки.**
Текущие активные counts: **0 critical, 0 warning, 0 info; high=0, medium=0,
low=0, total=0**. CR-04 и WR-06 закрыты на уровне исходников и независимых
фикстурных проверок. Все **11 исходных IDs + WR-06 = 12** имеют resolved
source/test/fixture status; прежние 7+3 закрытых issues не переоткрыты: доказанной
материальной регрессии не найдено. Это **не PASS фазы, PLAT-01 или интеграции**.

Прочитаны целиком все 19 текущих файлов из frontmatter, полная роль
`~/.config/kilo/agents/gsd-code-reviewer.md`, workflow `code-review.md`, references
`agent-skills-bootstrap.md` и `response-language-directive.md`, AGENTS/CLAUDE и
наследуемые HQ/build правила, CONTEXT, все пять PLAN, VALIDATION, актуальный
SUMMARY 03, CODE-REVIEW/machinefindings с историей и REMEDIATION **attempt 3**.
Отдельных project skills нет; configured agent_skills mapping пуст. Проведён
deep cross-file trace: build → staged verify → stop wrapper → native boundary
→ path/birth revalidation → TERM; app → общий TestRecord → widget reader.

**Независимость:** runtime-reported reviewer **OpenAI / openai/gpt-6.1-sol**;
автор текущего targeted ремонта — **Kimi / kimi-coding/k3-256k** по briefing и
REMEDIATION, прежних ремонтов — GLM. Cross-family условие выполнено; author route
не выдаётся за собственную host-event аттестацию. High запрошен, отдельно
инструментально не аттестован. Это quality escalation после **двух неудачных
GLM fixes CR-04**, затем Kimi attempt 3, не availability fallback. Kimi attempt 3
по данному review успешен для двух оставшихся IDs; никаких новых quality failures,
других моделей, metered API, Task или silent model replacement нет.

### CR-04 — resolved_source_native_boundary_probe

**Source:** `scripts/procstop/main.swift:114-141` (особенно :120-139), вызовы
до enumeration :399-406. Граница теперь строится от неподвижного canonical root
как **литерал** `rootCanonical + "/Contents/MacOS"`. Realpath этого каталога
сравнивается именно с литералом, а не используется как новая разрешённая
граница. Parent executable сверяется с тем же литералом; полный canonical
executable — с его точным child. Сохранены wrapper basename/integrity checks,
kernel exact path и microsecond birth сверки перед TERM; production KILL нет.

**Независимые held-out пробы оригинального compiled helper:** абсолютные И
относительные symlink-каталоги **MacOS** и **Contents**, каждый проверен в
`--list` и `--stop`, и через alias executable, и через canonical внешний путь.
Все **16 вызовов → rc=7**. Test-only interposer на `proc_listpids` пишет marker
при перечислении: **0 marker hits**, следовательно отказ до enumeration
наблюдался, а не выводился только из текста ошибки. Каждая внешняя собственная
пустая finite-lived C-фикстура имела проверенный kernel path и UID; TERM handler
с marker не сработал; все четыре остались живы после проб и **сами вышли rc=0**.
Никаких установленных приложений или чужих процессов не сигналилось.

Положительный контроль: обычный бандл с пробелами + symlink самого **корня**
бандла, canonical `/var → /private/var`: **list rc=0**, точный PID найден,
собственная фикстура завершилась естественно. Легитимная canonical root alias
не перепутана с запрещённым переносом внутренней границы. Исходный native
self-test без safety patch/guard прошёл **28/28**, включая старые 19 assertions.
Обычный wrapper/bundle signing bypass не тестировался и не заявляется.

### WR-06 — resolved_source_fixture_cleanup

**Source:** `scripts/procstop/self-test.sh:40-93,154-165,222-249,264-339`.
Активный набор содержит snapshot birth+comm, UID сверяется с MY_UID. После
каждого штатного wait/reap выполняется untrack. Cleanup проверяет live instance,
UID, lstart и comm перед TERM, повторяет проверки при ожидании и перед KILL;
безусловного сигнала всем историческим номерам больше нет.

**Независимые пробы verbatim текущих функций, без production main и без
настоящих сигналов:** stale PID и раздельные несовпадения UID/birth/comm →
**0 TERM/KILL** во всех четырёх случаях. Положительный контроль same identity
→ ровно один stub TERM и отсутствие KILL после выхода. Смена comm **после TERM**
→ ровно один начальный stub TERM и **0 дополнительных сигналов/KILL**. Отдельно
на настоящей собственной пустой фикстуре зафиксирован текущий snapshot,
проверен естественный выход, выполнен original untrack и cleanup: активный
набор пуст, **0 signal calls**. Это проверяет реальную ветку удаления после reap,
а не только заранее придуманную таблицу PID. Новые штатные (14a)/(14b) также
прошли в исходном 28/28 запуске.

**Остаточные границы, не новые findings:** ps lstart имеет секундную точность,
comm — наблюдаемый snapshot (не удостоверенный kernel executable path);
проверки полей не атомарны с сигналом. Production helper использует kernel
birth seconds+microseconds, но тоже не имеет атомарного check-and-signal.
Фактический PID reuse/коллизия, причиняющая чужой сигнал, **не доказаны и не
провоцировались**. После устранения historical PID retention и с повторной
identity сверкой этот теоретический предел не считается материальным
контрпримером безопасности коротких собственных тестовых фикстур; невозможная
pidfd-grade гарантия macOS не требуется. Cleanup wait до крайнего KILL может
дождаться естественного завершения: все создаваемые здесь фикстуры конечноживущие.

### Независимо выполненные проверки раунда 4

В следующих командах `SCRATCH=/var/folders/1b/3fg5ss5s6zn21df_141fkfmm0000gn/T/kilo`.
Все временные fixtures — только внутри этого approved scratch.

| Команда / проверка | Наблюдаемый результат, не подмена платформенной приёмки |
|---|---|
| `TMPDIR=$SCRATCH bash scripts/procstop/self-test.sh` (cwd scratch, CLANG cache scratch) | **28/28, rc=0**, original harness/native source, без прежнего memory kill guard; только собственные пустые C-фикстуры. Сообщение shell `Terminated: 15` относится к ожидаемой точной фикстуре теста 7. |
| `TMPDIR=$SCRATCH bash scripts/stop-installed.sh --self-test` | **54/54 assertions, rc=0**, helper/codesign/kill/open stubs. |
| `TMPDIR=$SCRATCH bash scripts/verify-install.sh --self-test` | **31/31, rc=0**, synthetic metadata/registration, не live codesign. |
| `TMPDIR=$SCRATCH bash scripts/diagnostics.sh --self-test` | **26/26, rc=0**, fake HOME/PATH, не реальные Group Containers. |
| `TMPDIR=$SCRATCH bash scripts/tests/preflight-negative.sh` | **6/6 прогонов, rc=0**, независимые fake HOME/PATH/CWD. |
| `swift test --package-path <absolute-repo>/Packages/UsageCore --scratch-path $SCRATCH/sol-r4-swift-build --cache-path $SCRATCH/sol-r4-spm-cache --config-path $SCRATCH/sol-r4-spm-config --security-path $SCRATCH/sol-r4-spm-security -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing` | **23 tests / 1 suite, rc=0**, build 17.76 s; cwd, TMPDIR, CLANG_MODULE_CACHE_PATH, SWIFTPM_MODULECACHE_OVERRIDE — scratch. ld CLT search-path warnings наблюдались, не скрывались; actual macOS15 runtime не утверждается. |
| `python3 $SCRATCH/sol-r4-probes.py` | **rc=0, PROBES_COMPLETE**: 16 negative boundary calls + positive root alias, 6 cleanup stub cases + real reap/untrack; sandbox `sol-r4-probes.gvbkwv8h` (canonical `/private/var/...`). |
| `plutil -lint` project + оба Info.plist + оба entitlements | **5/5 OK**, не Xcode object model / signed rights acceptance. |
| `bash -n` build/verify/stop/diagnostics/preflight/native self-test | **6/6 rc=0**. |
| `swiftc -parse AiUsage/AiUsageApp.swift Widget/TestWidget.swift` | **rc=0**, app full typecheck с Xcode macros не пройден. |
| `swiftc -typecheck -target arm64-apple-macos15.0 -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk scripts/procstop/main.swift` | **rc=0**, SDK compatibility; probes на текущей host macOS27. |
| `swiftc -emit-module … -D DEBUG -module-name UsageCore`; `swiftc -typecheck … Widget/TestWidget.swift` с `-D DEBUG` и без него | **3 команды rc=0**, обе widget branches против DEBUG-built dependency; не весь signed Release app. |

### Артефакты, fingerprint и остающиеся обязательные проверки

Итоговый machine artifact содержит 19 точных paths, **4 review rounds**, active
`findings=[]`, нулевые counts и сохранённые initial/round2/round3 findings/tests.
Новая гипотеза ремонта не нужна: CR-04/WR-06 accepted_source_test в attempt 3.
Теоретические residuals выше сохранены как limits, без изобретения новых IDs.
Уверенность **высокая в закрытии конкретных двух контрпримеров и nonregression
доступных проверок**, но это не математическое доказательство всех OS races.

SHA-256 списка `shasum -a 256` по 19 files в порядке frontmatter **до и после
тестов/записи review неизменен**:
`ac280cfd87c8deb304c2524aea7ba82a8114afc682bef50cd64b56536e94d856`.
Native source: `a8c5cf20bf4370908deb7eb0efd4c81a7a57f0ebd80f71936fe9f033107ce074`;
self-test: `c1a1809c4a39bfe32f75e0a00e2340e51c44dfa2e0c82ab2bc4b3d86c15121e3`.
HEAD прежний `7583e3ae4e34c68c2c4b642031a84a069bed5b18`.
Единственные authored repo mutations — **этот CODE-REVIEW и machinefindings**;
production, SUMMARY/REMEDIATION/plans, config/ROADMAP/STATE/state.json/routing
ledger не правились. Прежние compiler-generated root entries присутствовали
уже в исходном git status; не удалялись и не маскировались. SwiftPM запущен
из scratch, не из repo; полная трасса всех cache writes инструмента не снималась.
Staging/commit/push=0. CLI JSON state correction оставлена координатору.

**01-04 = blocked_not_verified, 01-05 = pending, PLAT-01 = pending.**
`xcode-select -p` по-прежнему `/Library/Developer/CommandLineTools`, Swift 6.4.
Не выполнены обязательные live Xcode project/scheme loading, personal-team
signing, signed app/appex layout/GID/capabilities, install/registration именно
нашего продукта, Центр уведомлений и двухпроцессная App Group приёмка.
Не измерены actual expiry и пересборка после неё. Никакие human checkpoints
не закрыты; реальные приложения/аккаунты/контейнеры/ОС не менялись. Прежние
unverified rollback/concurrency/compiler/interrupt checks не названы PASS.
Goal report и 01-04/01-05 SUMMARY не созданы.

---

## История раунда 3 — findings и evidence сохранены

Ниже неизменённая evidence-часть review **2026-10-12T00:21:17Z**, 19 файлов,
два active findings после GLM attempt 2. Counts/status/номера строк ниже
исторические, текущий вердикт и закрытие IDs находятся в раунде 4 выше.

## Narrative Findings (AI reviewer) — текущий раунд 3

**Вердикт: issues_found / REVIEW NOT PASSED.** Прочитаны целиком текущие 18
файлов прежнего scope и новый native self-test, полная роль и её workflow/reference,
наследуемые правила, пять PLAN, CONTEXT, SUMMARY 01–03, VALIDATION, предыдущие
CODE-REVIEW/machinefindings и REMEDIATION attempt 2. Семейство reviewer —
**OpenAI / openai/gpt-6.1-sol**, независимо от авторов GLM/Flash и GLM-fixer;
high запрошен, отдельной инструментальной аттестации effort нет. Другие модели,
агенты и metered API не вызывались. Это программное review, не научный ARIS-аудит.

Из четырёх оставшихся исходных IDs **WR-01, WR-02, WR-04 закрыты на уровне кода и
изолированных probes**. CR-04 остаётся **partially_fixed / BLOCKER/high** с новым
контрпримером именно контракта native helper; защищённая обёртка исправлена.
Добавлено одно **WARNING/medium, WR-06** в новом тестовом harness. Семь ранее
закрытых IDs не переоткрыты. Текущий итог: **1 BLOCKER + 1 WARNING**, десять из
11 исходных findings resolved_source/test/fixture, один исходный открыт.

### CR-04 — BLOCKER / high / partially_fixed: native helper переносит границу в symlink-каталог MacOS

**File:** `/Users/serzhsharapa/hq/build/ai-usage-macos-widget/scripts/procstop/main.swift:99-120`
(особенно :105–110), сигнал :318–329; обёртка
`scripts/stop-installed.sh:138-195`.

**Что исправлено:** wrapper требует безопасный **точный** `CFBundleExecutable`
`AI Usage Widget` (:144–153), проверяет целостность старого бандла через
`codesign --verify --strict --deep` (:169), удостоверяет канонический MacOS-каталог
внутри app и точный executable (:180–186). Литерал соответствует PRODUCT_NAME
обеих конфигураций app в `project.pbxproj:221,240`, Info.plist использует
`$(EXECUTABLE_NAME)`. Прежние traversal/sibling/executable-symlink и failed-integrity
ветки не разрешают вызов helper. Это реальная source-remediation, не повтор
старого обвинения про argv или отсутствие codesign --verify.

**Оставшийся дефект:** helper вычисляет `macosCanonical = realpath(root +
"/Contents/MacOS")`, но **не проверяет** равенство этого каталога литералу
`canonical(root) + "/Contents/MacOS"`. При symlink самого MacOS-каталога наружу
оба parentCanonical и macosCanonical становятся внешним каталогом. Затем
`required` строится уже от внешнего каталога; полный regular executable проходит
:114–119. Новый обязательный аргумент root не ограничивает самостоятельный
helper своим корнем. Аналогично возможен symlink промежуточного Contents.

**Независимая native-проба:** неизменённый `main.swift`, собранный `swiftc -O
-target arm64-apple-macos15.0`, собственный fake `Boundary.app/Contents/MacOS →
<scratch>/outside`, там собственная пустая C-фикстура `AI Usage Widget`.
Её PID и фактический путь ядра проверены перед пробой. Получено:

- `NATIVE_PARENT_SYMLINK_LIST_RC=0`, единственный PID/путь находится **вне app**;
- `NATIVE_PARENT_SYMLINK_STOP_RC=6`, но **TERM действительно отправлен**;
- `NATIVE_PARENT_SYMLINK_FIXTURE_EXIT=-15` — собственная фикстура завершилась TERM.

Код 6 здесь связан с тем, что Python-родитель reap (забирает статус вышедшего
дочернего процесса) только после возвращения helper: зомби до этого числится в
таблице. Это **не новый finding про таймаут** и не доказательство успешного
подтверждения выхода. Для CR-04 существенно фактическое получение сигнала внешней
целью, которое произошло до любого exit status.

**Граница вывода:** оригинальный wrapper на том же parent-symlink дал rc=1,
`helper_called=False`; отдельный отказ integrity также rc=1 до helper. Не доказан
обычный end-to-end обход wrapper/build.sh и не утверждается, что реальный
подписанный продукт допускает такую раскладку. Finding — воспроизводимое нарушение
явно заявленного самостоятельного root/path контракта native helper, а не
абстрактное требование устранить все TOCTOU/PID races.

**Fix / новая проверяемая гипотеза для следующего ремонта:** root должен быть
неподвижной точкой отсчёта. До перечисления PID потребовать
`canonical(root/Contents/MacOS) == canonical(root) + "/Contents/MacOS"`, затем
точный parent/executable относительно **этого** пути; ошибки разрешения/инспекции
не выдавать за доказательство допустимости. Добавить held-out native-тесты
symlink **каталога MacOS** и **Contents**, не только symlink конечного файла:
ожидание rc=7 и живой внешний собственный процесс без сигнала. Сохранить точное
сравнение пути ядра, start identity, один TERM и отсутствие KILL в production.

### WR-06 — WARNING / medium / open: новый native self-test сигналит историческим PID без проверки экземпляра

**File:** `/Users/serzhsharapa/hq/build/ai-usage-macos-widget/scripts/procstop/self-test.sh:23-35,90-99,129-137,156-180,193-202`.

**Issue:** каждый fixture PID навсегда добавляется в `PIDS_FILE`, но после
`wait/stop_fixture` не удаляется. EXIT cleanup перебирает **все исторические**
числа и без текущей проверки владельца, kernel path или birth identity вызывает
`kill "$p"`, затем **безусловно `kill -9 "$p"`**. Даже первый отказ TERM не
отменяет KILL. Утверждение «точные PID собственных фикстур» на :26 не удостоверяет,
что это всё ещё собственные процессы: после reap PID может быть переиспользован.
Это существенно более широкое окно до конца теста, не минимальный промежуток
между финальной проверкой production helper и одним TERM.

**Изолированная проба без сигналов:** исполнена исходная cleanup-функция с
`PIDS_FILE=987654`, stub kill/rm; результат rc=0 и **обе** записи
`SIGNAL_CALL 987654`, `SIGNAL_CALL -9 987654` без единого запроса identity.
Настоящего PID reuse и повреждения чужого процесса review не вызывал и не заявляет;
доказаны алгоритм и его нарушение обещанной изоляции при таком состоянии.

**Fix:** исключать завершённые/reaped экземпляры из активного набора; для аварийного
cleanup удостоверять текущую принадлежность и kernel path/birth сохранённого
экземпляра непосредственно перед сигналом. Для finite-lived пустых фикстур
предпочтительно дождаться собственного завершения, без blanket KILL. Добавить
детерминированный stub-тест смены identity: при старом PID нового экземпляра
должно быть **0 сигналов**, включая KILL. Это рекомендация, не разрешение на правку.

**Безопасность запуска в этом review:** оригинальный native self-test с его
непроверяемым cleanup не запускался без защиты. Все его **19 исходных assertions**
повторены с временным, только в памяти, перехватом shell `kill`: KILL запрещён,
для остальных вызовов требуется current child PPID и kernel path внутри текущего
fixture scratch. Native helper/его исходник и все assertions не изменялись.
Итог **19/19, rc=0 в трёх прогонах** — ограниченное доказательство native-сценариев,
**не PASS безопасности оригинального cleanup**. Реальные app/processes не сигналились.

## Статусы исходных IDs после раунда 3

| ID | Текущий статус | Основание текущего кода/проверок |
|---|---|---|
| CR-01 | resolved_source; Xcode pending | `project.pbxproj:89-91,151-153,319-321`: XCLocalSwiftPackageReference, две связи продуктов; plist lint OK, не live Xcode. |
| CR-02 | resolved_source; Xcode pending | `project.pbxproj:132`: app-extension; реальный продукт ещё не собран. |
| CR-03 | resolved_source; layout pending | `project.pbxproj:22-24`: пустой dstPath, subfolder 13; физический signed layout pending. |
| CR-04 | partially_fixed / open | Wrapper закрыт; parent-directory symlink направляет самостоятельный native helper на внешнюю фикстуру с TERM. |
| CR-05 | resolved_source_fixture | `verify-install.sh:106-129,304-314`: Info/signed IDs обеих сторон, package types/WidgetKit point; V14–V19 повторно отвергнуты. |
| CR-06 | resolved_source_test | `TestRecord.swift:38-70`, `AiUsageApp.swift:69-71`: range validation и checked increment; 23/23, no overflow regression. |
| WR-01 | resolved_source_fixture | `verify-install.sh:349-406`: -mDvv, немедленный commit пары, canonical exact path/election; обе перестановки и SDK-before-Path дают rc=0; `-`, `=`, `?`, `!` дают rc=1. |
| WR-02 | resolved_source_native_fault_probe | `main.swift:151-167,188-263,274-281,305-368`: tri-state, owner/kernel comm, unknown fail closed; EACCES собственного целевого PID → rc=2, жив/no signal; unknown BSD → rc=2. |
| WR-03 | resolved_source_fixture | DV в памяти; `build.sh:159-161,178-179`: redaction до log; прежние raw-DV negative cases в 31/31 не регрессировали. |
| WR-04 | resolved_source_fixture | `diagnostics.sh:93-116`: точное GID string equality; groupXaiusage и TESTTEAMIDXgroup.aiusage не экспортируют имя marker-файла, правильный GID экспортирует. |
| WR-05 | resolved_source_test | `AiUsageApp.swift:98-111`, `TestWidget.swift:73-87`, `TestRecord.swift:120-124`: read/decode разделены; реальные scratch missing/denied tests проходят. |

### Практические owner/unknown и PID-limits (не самостоятельные findings)

- Read-only metadata реальных root-процессов: в финальной строгой пробе **нет
  доступной BSD owner-записи для root PID > 0**. Фактический отказ пути реального
  защищённого root PID даёт **rc=2**; отказ также BSD owner — **rc=2**, не ложный
  PASS. Оба fault-interposer вызова удостоверены отдельными scratch hit markers,
  не предположены по exit code. Source-ветка исключения заведомо чужого root
  с доступным BSD owner/comm существует, но её практический успех на таком
  **реальном доступном root PID этой машины не доказан**.
  Никаких root/signals/sudo, имена/argv/пути системных процессов не экспортированы.
- Для собственного продукта kernel `pbi_comm` вмещает литерал **15 символов**
  `AI Usage Widget`; native EACCES probe подтверждает rc=2, не rc=3. Prefix/argv
  spoof тест не совпадает. Программа продукта не меняет kernel comm. Произвольная
  нечитаемая программа с другим kernel именем не объявляется hidden target без
  evidence; unknown owner не считается safe. Root-executed exact app с denied
  path остаётся вне принятой модели обычного пользовательского приложения;
  его фактический запуск не тестировался. Это не универсальная гарантия для root.
- Production повторно проверяет kernel path + birth seconds/microseconds перед
  TERM и при ожидании. **Атомарного pidfd/check-and-signal нет**; остаточное малое
  окно PID reuse признано, но без actual exploitable evidence не переоткрывает
  исходный argv finding. SIGKILL/blanket process stop в `main.swift` нет.

### Независимо повторённые команды и результаты раунда 3

Все временные результаты — в approved scratch; ни build.sh на реальном HOME,
ни live signing, installation, registry mutation или Group Containers не выполнялись.

| Команда/проверка | Наблюдаемый результат и граница |
|---|---|
| `TMPDIR=<approved scratch> bash scripts/verify-install.sh --self-test` | **31/31**, rc=0; synthetic codesign/pluginkit, не реальная подпись. |
| Та же среда, `bash scripts/stop-installed.sh --self-test` | **54/54 assertions**, rc=0; helper/signals/open — stubs. |
| `bash scripts/diagnostics.sh --self-test` | **26/26**, rc=0; fake HOME/PATH, не реальный контейнер. |
| `bash scripts/tests/preflight-negative.sh` | **6 прогонов**, rc=0, независимые fake HOME/PATH/CWD. |
| `TMPDIR=<scratch> swift test --package-path Packages/UsageCore --scratch-path <scratch>/sol-r3-swift.2w0Ene -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing` | **23 tests / 1 suite**, rc=0; 17.87 s build, ld warnings CLT search paths не скрывались. Реальное размещение default swiftbuild output этим review не удостоверено: указанный scratch после прогона пуст; не называю его доказанно изолированной сборкой. |
| Native self-test через memory-only safety guard, runner ниже | **19/19**, rc=0, три успешных прогона; assertions/native source оригинальные, cleanup safety не PASS (WR-06). |
| `plutil -lint` project.pbxproj, оба Info.plist, оба entitlements | **5/5 OK**; не семантика объектной модели Xcode. |
| `bash -n` шести скриптов, включая новый native self-test | Все rc=0. |
| `swiftc -parse AiUsage/AiUsageApp.swift Widget/TestWidget.swift` | rc=0; не полный app typecheck. |
| `swiftc -typecheck -target arm64-apple-macos15.0 -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk scripts/procstop/main.swift` | rc=0; SDK/header compatibility, не macOS15 runtime. |
| `swiftc -O -target arm64-apple-macos15.0 -o <scratch>/procstop scripts/procstop/main.swift` | rc=0; настоящие kernel probes выше, только собственные finite-lived fixtures. |
| Самостоятельный `swiftc -emit-module -parse-as-library -swift-version 6 -module-name UsageCore -D DEBUG -target arm64-apple-macos15.0 … TestRecord.swift`, затем `swiftc -typecheck -parse-as-library -swift-version 6 -target arm64-apple-macos15.0 -I <scratch> [-D DEBUG] Widget/TestWidget.swift` | Все rc=0, обе ветки виджета; non-DEBUG widget против DEBUG-built dependency, не full Release app. |
| Read-only `/usr/bin/pluginkit -mDvv -p com.apple.widgetkit-extension` | rc=0; **39 Path= / 39 SDK=com.apple.widgetkit-extension**. Сохранены только counts, не private names/paths. Man :47–49,57–81,106–118 подтверждает -D и election tags. |

Runner: `/var/folders/1b/3fg5ss5s6zn21df_141fkfmm0000gn/T/kilo/sol-r3-probes.py`;
финальный sandbox `sol-r3-probes.ac2wto9v`, runner rc=0, `PROBES_COMPLETE`.
Дополнительные 6 parser probes и 3 GID probes — исходные production функции
в памяти; для parser изолированы предыдущие signature/identity/expiry проверки,
не весь signed verifier. Wrapper проверялся оригинальным скриптом с fake HOME
и codesign stub; native helper — оригинальным скомпилированным исходником.

### Непрошедшие exploratory checks (не скрыты и не quality attempts производства)

- Предварительная root-проба включала PID 0 и дала rc=3; это **не evidence
  исключения реального root PID > 0**, поскольку production enumeration убирает
  PID 0. Финальная проба фильтрует PID > 0, проверяет kernel UID==0 и сохраняет
  fault-hit markers; результат реального защищённого процесса rc=2. Ошибочное
  предварительное толкование исправлено, не используется как PASS.
- Первый safety guard reviewer запросил proc_pidpath с **8192**-байтовым буфером,
  больше Darwin PROC_PIDPATHINFO_MAXSIZE=4096: ложные inspector failures, пять
  native assertions fail и собственный runner AssertionError. Исправлен **только
  scratch guard** на 4096; исходники/19 assertions не менялись, затем три 19/19.
- Первая stub-cleanup probe имела лишний `;` после определения функции и rc=2;
  исправлена только scratch-композиция. Финальная probe rc=0, оба signal calls
  записаны заглушкой. Это не claim реального PID reuse.
- Первая widget typecheck пыталась импортировать модуль из пустого scratch и
  дала `no such module UsageCore`. Затем модуль независимо собран swiftc в
  scratch, обе widget ветки прошли; предыдущий отказ не называется PASS.
- Дополнительный эксперимент `swift test … --build-system native` дал
  `no such module Testing` и warning deprecated build-system. Он **НЕ PASS**,
  не установлен новый тулчейн и не подменён основной успешный 23-test run.

### Unresolved checks / human blockers и scope раунда 3

**01-04 blocked_not_verified, PLAT-01 pending, 01-05 pending сохраняются.**
`xcode-select -p` = `/Library/Developer/CommandLineTools`, Apple Swift 6.4,
host arm64 macOS27. Нет живой загрузки проекта/схемы AiUsage, сборки signed
app/appex, развёртывания GID, personal-team capabilities, регистрации именно
нашего продукта, UI Центра уведомлений и двухпроцессной проверки общей папки.
Полный SwiftUI app typecheck с Xcode macros не сертифицирован.
Нет измеренных дат истечения/послеистечной пересборки; сроки не выдуманы,
checkpoint владельца не закрыт, Goal report/01-04/01-05 SUMMARY не созданы.
Прочие прежние limits (live rollback/open, concurrency/cache/compiler failure,
interrupt certificate cleanup, process-table saturation) не объявлены PASS.

CR-04 пережил **две GLM quality fix attempts (high → max по briefing)**.
Следующий ремонт требует quality escalation **Kimi high** для boundary contract,
**Sol high** при security-boundary цене ошибки согласно HQ policy :161–168,
с новой гипотезой выше. WR-06 — новый issue, его quality failure count=0;
errors scratch harness/CLT не повышают production счётчик. Сам review ничего
не исправляет и новых исполнителей не запускает.

Единственные **авторские правки repo-файлов** — `01-CODE-REVIEW.md` и `machinefindings.json`;
production/config/REMEDIATION/SUMMARY/ROADMAP/STATE не правились,
staging/commit/push=0. HEAD `7583e3ae4e34c68c2c4b642031a84a069bed5b18`.
Fingerprint 19 source paths в frontmatter (SHA-256 вывода `shasum -a 256`):
`b62e98d9ec97221e945c37368b421738a092e6306cc84867e16f1df6340d583b`.
После SwiftPM-прогонов git также показывает compiler-generated build entries в
корне (`.buildSystem_debug`, `.lock`, `CACHEDIR.TAG`, `debug`, `manifest.pif`,
`out/`, `workspace-state.json`), несмотря на --scratch-path. Поэтому **полной
изоляции всех записей тестового инструмента не утверждаю**. Исходники не изменены;
build entries не staged и не удалялись/не маскировались изменением .gitignore.
История прежних раундов ниже сохранена; их active counts/status не текущие.

---

## История раунда 2 — findings и evidence сохранены

Ниже evidence-часть review **2026-10-11T23:27:09Z**, 18 файлов,
4 active IDs после GLM attempt 1. Все counts, статусы и номера строк в этой
части — исторические; актуальные статусы и evidence находятся в раунде 3 выше.

## Narrative Findings (AI reviewer) — исторический раунд 2

**Вердикт: issues_found.** Независимо перепроверены все прежние 17 файлов и новый
`scripts/procstop/main.swift`, после одной заявленной попытки GLM-ремедиации.
Из 11 исходных issues **7 устранены на уровне исходников/изолированных проверок,
4 исправлены частично и остаются открытыми**: 1 BLOCKER/high, 3 WARNING/medium.
Новых отдельных issue IDs не добавлено; уточнения ниже продолжают исходные ID.
Это не принятие «all 11 fixed» из 01-REMEDIATION.json и не платформенный PASS.

### CR-04 — BLOCKER / high / partially_fixed: realpath нормализует чужую цель вместо ограничения своим бандлом

**File:** `/Users/serzhsharapa/hq/build/ai-usage-macos-widget/scripts/stop-installed.sh:119-149`;
`/Users/serzhsharapa/hq/build/ai-usage-macos-widget/scripts/procstop/main.swift:220-236`.

**Устранённая часть:** argv/ps-префиксы действительно удалены. Штатный C-тип
`proc_bsdinfo`, `proc_pidpath`, время старта и повторная сверка используются реально;
приманка `Empty Fixture Helper` с argv[0] точного пути цели не совпала (rc=3).

**Оставшийся source effect:** `CFBundleExecutable` проверяется лишь на непустоту,
затем без проверки имени/границы включается в anchor. `canonicalPath` разрешает
`../` и symlink, но не проверяет принадлежность результата авторизованному
`~/Applications/AI Usage Widget.app/Contents/MacOS`. Проверка TeamIdentifier через
`codesign -dv` — чтение метаданных, не проверка целостности изменённого Info.plist.
Поэтому подправленный/сломанный старый бандл может направить остановщик на
исполняемый файл вне себя; staged-проверка новой сборки этого не удостоверяет.

**Независимый контрпример:** настоящий неизменённый stop-wrapper и настоящий
скомпилированный procstop исполнены со своим fake HOME. Info.plist имел правильный
bundle ID и `CFBundleExecutable=../../../../../Empty Fixture`; codesign был
заглушкой ожидаемой команды. Единственная цель — собственный трёхсекундный пустой
C-процесс во временном каталоге, **вне fake app**. Получено
`ESCAPING_EXECUTABLE_TERM_RC=0`, `TERM отправлен точному экземпляру`, выход фикстуры
`-15`. Значит, путь ядра совпал точно, но с **неавторизованной целью**. Реальные
подписанные продукты и установленные приложения не использовались.

**Fix:** до вызова помощника проверить целостность старого бандла и его identity,
допустимое точное basename исполняемого файла; нормализовать корень авторизованной
установки и executable, отвергать traversal/выход symlink и другой корень, а не
просто превращать их в допустимую цель. Добавить held-out traversal и symlink
фикстуры с требованием нуля сигналов. Сохранить стартовые аргументы, один TERM,
проверку экземпляра и отказ без KILL. Рекомендация не разрешает правку производства.

### WR-01 — WARNING / medium / partially_fixed: parser сохраняет только последнюю регистрацию и не проверяет election

**File:** `/Users/serzhsharapa/hq/build/ai-usage-macos-widget/scripts/verify-install.sh:337-372,620-636`.

**Устранённая часть:** ненулевой exit pluginkit и единственный stale-путь теперь
отвергаются. **Формат Path/SDK не выдуман:** read-only запрос системного
`/usr/bin/pluginkit -mAvv -p com.apple.widgetkit-extension` дал rc=0, 39 полей
`Path =`, 39 полей `SDK = com.apple.widgetkit-extension`, 0 строк с голым
абсолютным appex-путём. Идентификаторы, пути и имена держались в памяти; в вывод
попали только структура и очищенные поля. SDK сопоставляется с правильной точкой.
Гипотеза «обычный verbose всегда печатает голый путь» **отклонена**, не finding.

**Оставшийся дефект:** обычные headers записей тоже начинаются с пробелов.
Первое правило awk `^[[:space:]]` делает `next` и для header; ветка flush на
границе записи не выполняется. Следующие Path/SDK затирают предыдущие, END выдаёт
лишь последнюю пару. Штатный P4 кладёт exact последним и маскирует эту ошибку.
Кроме того, state из header вообще не разбирается: `-` (ignore) даёт PASS.

**Независимые пробы оригинального verify_bundle с fixture codesign:** при двух
версиях одного ID, exact `(1.0)` первым и stale `(2.0)` последним —
`EXACT_FIRST_STALE_LAST_RC=1`; те же записи наоборот —
`EXACT_LAST_POSITIVE_RC=0`, PASS. Оба Path/SDK имеют формат и отступы системного
ответа. Exact-запись с `-` — `IGNORED_REGISTRATION_RC=0`, PASS.
Настоящая регистрация собственного виджета не выполнялась.

**Fix:** разбирать каждую целую запись с header/election, сбрасывать поля на
границе; нормализовать сравниваемые пути; требовать допустимое состояние exact
регистрации. Для перечисления всех физических копий учесть `-D`: официальная
локальная man-страница `/usr/share/man/man8/pluginkit.8:57-81,106-117` говорит,
что `-A` возвращает только последний зарегистрированный экземпляр **каждой версии**,
а `-D` — все eligible экземпляры. Добавить обе перестановки нескольких версий,
дубликаты версии, ignored/superseded и canonical-path fixtures. Не копировать
неподтверждённый bare-path формат в «официальную» фикстуру.

### WR-02 — WARNING / medium / partially_fixed: отказ чтения пути живого PID всё ещё означает «не запущен»

**File:** `/Users/serzhsharapa/hq/build/ai-usage-macos-widget/scripts/procstop/main.swift:84-90,102-113,153-158`;
`/Users/serzhsharapa/hq/build/ai-usage-macos-widget/scripts/stop-installed.sh:152-163`.

**Устранённая часть:** полный отказ proc_listpids возвращает 2; wrapper не
разрешает замену при 2. Ожидание после TERM различает ESRCH и EPERM.

**Оставшийся дефект:** в первоначальном поиске `proc_pidpath` возвращает один
`nil` и при исчезновении PID, и при отказе доступа; matchingInstances просто
`continue`. Пустой массив после ошибок инспекции превращается в rc=3, а wrapper
трактует 3 как успешное «не запущен» и разрешает build продолжить замену.

**Независимый контрпример:** неизменённый native helper с test-only DYLD
interpose-библиотекой в scratch; hook возвращал `0/EACCES` **только** для PID
собственного живого пустого C-процесса, остальные вызовы оставались системными.
Получено `PATH_INSPECTION_DENIED_RC=3`, «не запущен; ни одного сигнала»,
`PATH_INSPECTION_DENIED_TARGET_STILL_ALIVE=True`. Фикстура затем сама вышла по
своему sleep(3), без KILL; hook не применялся к системным приложениям.

**Fix:** различать пропавший PID и ошибку получения пути на этапе поиска;
проверять соответствующие процессы текущего владельца и fail closed при
неопределённой инспекции, а не превращать её в отсутствие цели. Это не означает
«любой недоступный чужой root-процесс должен блокировать установку»: ограничить
перечисление/классификацию владельцем. Добавить именно native отрицательный тест
ошибки пути до TERM, не только wrapper-заглушку с заранее правильным rc=2.

### WR-04 — WARNING / medium / partially_fixed: wildcard в suffix допускает другую App Group

**File:** `/Users/serzhsharapa/hq/build/ai-usage-macos-widget/scripts/diagnostics.sh:93-112`.

**Устранённая часть:** прежние `../../privatefixture` и symlink-побег отвергаются,
ожидаемая команда и bundle ID проверяются до листинга; canonical-directory check
реально добавлен.

**Оставшийся дефект:** regex `^${team}\.${GROUP_SUFFIX}$` экранирует только первую
точку. В `GROUP_SUFFIX=group.aiusage` вторая точка остаётся regex-wildcard, поэтому
`TESTTEAMID.groupXaiusage` проходит. Последующая проверка конечного пути использует
уже ошибочно допущенный gid, а не точный разрешённый ID.

**Независимый контрпример:** оригинальная group_container_section, fake HOME,
правильные bundle ID/ожидаемая команда через codesign-stub, gid
`TESTTEAMID.groupXaiusage`. Реальный каталог фикстуры с этим именем содержал
`FOREIGN_GROUP_FILENAME`; получено `NONEXACT_GROUP_SUFFIX_RC=0` и это имя в выводе.
Реальные Group Containers не читались.

**Fix:** точное строковое сравнение `[ "$gid" = "$team.$GROUP_SUFFIX" ]` до
построения пути, затем сохранить canonical-path/symlink проверки. Добавить
single-character substitutions во всех точках и имени suffix, с маркером в
**имени файла**, а не только содержимом (диагностика экспортирует имена).

## Статусы всех 11 исходных issues после раунда 2

| ID | Статус | Независимое основание |
|---|---|---|
| CR-01 | resolved_source; Xcode pending | `XCLocalSwiftPackageReference` в :89-91, ссылки продуктов сохранены; прежний неправильный ISA отсутствует. Не живая загрузка Xcode. |
| CR-02 | resolved_source; Xcode pending | product type `app-extension` в :132; прежний несуществующий тип отсутствует. |
| CR-03 | resolved_source; layout pending | `dstPath=""`, subfolder 13 в :22-24; реальные build/appex не получены. |
| CR-04 | partially_fixed / open | argv-prefix probe устранена; boundary escape с настоящим TERM собственной фикстуре подтверждён выше. |
| CR-05 | resolved_source_fixture | Точные Info.plist и signed IDs обеих сторон, package types и WidgetKit point проверяются до замены; V14–V19 независимо прошли на отрицательных фикстурах. |
| CR-06 | resolved_source_test | Decoder отвергает Int.max/negative/zero, increment checked; граничные тесты в 23/23. Политика maxSafe → 1 явна в коде и тесте, не wrap/trap. |
| WR-01 | partially_fixed / open | Ошибка инструмента/stale-only отвергаются, но record boundary/election остаются дефектными. |
| WR-02 | partially_fixed / open | Общий enumeration failure обработан; EACCES одного живого целевого PID даёт ложную absence. |
| WR-03 | resolved_source_fixture | Сырых DV-файлов нет; VOUT/SOUT идут через redact до build.log; 24/24 проверяют отсутствие raw-DV persistence. |
| WR-04 | partially_fixed / open | Traversal/symlink защита добавлена, но неточного suffix достаточно для листинга другой группы. |
| WR-05 | resolved_source_test | Read и decode разделены в обоих таргетах, fileExists в read-path убран; реальные missing/permission tests проходят, нечитаемый snapshot больше не corrupt. |

### Независимые проверки текущего раунда и пределы

- `TMPDIR=<approved scratch> bash scripts/verify-install.sh --self-test`: **24/24**,
  rc=0; `stop-installed.sh --self-test`: **42/42 assertions**, rc=0;
  `diagnostics.sh --self-test`: **20/20 assertions**, rc=0;
  `scripts/tests/preflight-negative.sh`: **6 прогонов**, rc=0. Заглушки не стали
  свидетельством живой подписи/регистрации/установки.
- `TMPDIR=<approved scratch> swift test --package-path Packages/UsageCore
  --scratch-path <scratch>/sol-r2-swift.B84QF7 -Xswiftc -plugin-path -Xswiftc
  /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`:
  **23 tests / 1 suite**, rc=0, 17.57 s сборка. Предупреждения ld о недостающих
  CLT search paths наблюдались и не скрывались.
- `plutil -lint` пяти файлов — OK; `bash -n` каждого из пяти скриптов — rc=0;
  `swiftc -parse` app/widget — rc=0; typecheck виджета в DEBUG и без DEBUG,
  Swift 6, arm64 macOS 15 против Debug-модуля UsageCore — оба rc=0.
- Native helper: `swiftc -O -target arm64-apple-macos15.0` — rc=0; отдельно
  `swiftc -typecheck -target arm64-apple-macos15.0 -sdk
  /Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk
  scripts/procstop/main.swift` — rc=0. SDK libproc.h/sys/proc_info.h подтверждают
  штатный proc_bsdinfo и pbi_start_tvsec/usec; ручной выдуманной ABI-структуры нет.
  Это совместимость заголовков/компиляции, не запуск на настоящей macOS 15.
- Настоящий helper на собственных finite-lived C-фикстурах: exact list rc=0,
  prefix+argv spoof rc=3, exact TERM rc=0, игнорирующий TERM процесс rc=6 после
  одного TERM; в исходнике нет SIGKILL. Учитывается обычное минимизированное,
  но **не атомарно устранённое** окно PID re-use между проверкой и kill.
- Настоящий stop-wrapper с default on-demand compilation в fake HOME:
  **ON_DEMAND_NATIVE_STOP_RC=0**, helper и sha-кэш созданы; `.new` после успеха
  отсутствует; следующий вызов rc=0 и mtime binary не изменился (reuse=True).
  Настоящий пользовательский `~/Library/Caches` не менялся.
- WR-05 дополнительная семантическая проба: текущий TestRecordStore извлечён
  целиком, изменён **только URL группы на scratch**; обычная запись №7 →
  permission-denied reading → `.containerUnavailable`; попытка записи также
  `.containerUnavailable`, сохранённый номер после восстановления прав =7.
  Варианты 000/0200 не доказали сброса. Не выдаю теоретическую гонку чтения/
  записи за найденную потерю данных. Полный SwiftUI app всё ещё не typechecked.

Reproducer: `/var/folders/1b/3fg5ss5s6zn21df_141fkfmm0000gn/T/kilo/sol-r2-probes.py`;
последняя успешная песочница `sol-r2-probes.h7t7jtqr`, общий rc=0.
Загрузка функций производится в память до production main; codesign и
signature-expiry в таких probes — заглушки. Системный pluginkit только `-m`,
без `-a/-r/-e`; raw names/paths не сохранялись. Никаких live app signals.
Промежуточный runner завершился TypeError из-за собственной переменной `start`,
затенившей функцию; исправлен только scratch runner, финальный прогон успешен.
Это не дефект производства/провайдера и не дополнительная попытка GLM-fix.

### Unresolved checks / ограничения раунда 2

- **01-04 blocked_not_verified; PLAT-01 pending; 01-05 pending** сохраняются.
  `xcode-select -p` по-прежнему CLT; никакие build.sh на настоящем HOME, подпись,
  установка, GUI/account/developer-dir действия или изменение пользовательских
  данных не выполнялись. Схема `AiUsage`, реальный продукт `AI Usage Widget.app`
  и встроенный `AiUsageWidget.appex`, GID expansion, подписанные metadata,
  personal-team capabilities и реальная registration остаются unverified.
- Даты подписи/истечение/послеистечная пересборка не наблюдались. Не создано
  01-04/01-05 SUMMARY или Goal report; критерии/human checkpoints не закрыты.
- Native compiler stderr идёт напрямую в standalone stop, в build он захвачен
  и отредактирован. Failed-compiler redaction, SIGINT leftovers/cache concurrency,
  saturation process-list и живые rollback/open failure здесь не доказаны PASS.
  Атака через произвольно изменённые **доверенные исходники репозитория** или
  attacker filename не объявлена самостоятельным vulnerability без обоснования
  иной границы доверия. Это не отменяет CR-04: метаданные установленного старого
  бандла находятся на отдельной явно проверяемой trust boundary.
- DER-сертификат, который временно извлекается для NotAfter, — сертификат с
  публичными ключом и CN, **не приватный ключ/токен**. Намеренное краткое локальное
  извлечение не приравнено к прежнему raw Authority dump; cleanup обычного пути
  виден, его interrupt-path privacy независимо не сертифицирована.
- Модель: настроенный task route Sol/high; runtime-reported
  **openai/gpt-6.1-sol / OpenAI**, источник — developer runtime context. High не
  имеет отдельной инструментальной аттестации. Семейство независимо от GLM/Flash
  авторов и GLM-ремедиации. Другие модели/платные API не вызывались.
- Единственные repo-записи раунда — этот report и `machinefindings.json`;
  production/summary/remediation/locks/config не правились; staging/commits=0.
  Fingerprint 18 current sources в порядке frontmatter:
  `bca25655b3fafc6047de68f2e3a62978ef94ee705786f84602838ad560ccfc21`.
  Следующие рекомендации — только результат review, не разрешение на выполнение.

Финальная проверка артефактов: стандартный JSON parser Python подтвердил 11
initial issues, 4 active issues, 18 paths и 2 rounds; source fingerprint после
записи отчёта совпал. `plutil -lint machinefindings.json` отдельно отверг raw JSON
как plist (`Unexpected character { at line 1`); это не PASS JSON-lint и не
quality failure производства. Валидность JSON доказана именно JSON parser.

---

## История раунда 1 — исходные issues и доказательства сохранены

Ниже неизменённая evidence-часть первого review от **2026-10-11T22:37:28Z**:
11 initial findings (5 high / 5 medium / 1 low), 17 initial files, исходные строки
относятся к тогдашним версиям. Её counts/status/тесты — **исторические**, не
текущий вердикт. Сверка текущего состояния находится выше; issues не вычищены.

## Narrative Findings (AI reviewer)

### BLOCKER / high

#### CR-01 — Неверный ISA локальной SwiftPM-зависимости

**File:** `/Users/serzhsharapa/hq/build/ai-usage-macos-widget/AiUsage.xcodeproj/project.pbxproj:89-91`, ссылки `:151-153,319-321`.

**Issue / evidence:** объект с `relativePath = Packages/UsageCore` объявлен как `PBXLocalPackageReference`. Канонический тип объекта локальной Swift package reference — `XCLocalSwiftPackageReference`: так его определяют и сериализуют два независимо прочитанных парсера [S1], [S2]. Продукты обоих таргетов ссылаются именно на этот объект. `objectVersion = 56` не превращает произвольное имя класса в известный Xcode ISA. `plutil -lint` проверяет синтаксис plist, а не классы объектной модели; поэтому его успешный результат не доказывает загрузку проекта или разрешение UsageCore.

**Counterexample / required property:** открытие этого проекта/`xcodebuild -list` должно разрешать объект локального пакета, а не останавливаться на неизвестном ISA или терять зависимость. Исходный объект не соответствует именам реально реализованных парсеров. Живое сообщение Xcode здесь **не наблюдалось**: Xcode отсутствует; закрытый парсер Xcode независимо не запускался. Официальный пример Apple того же objectVersion [S3] использует другую валидную форму локального пакета — `PBXFileReference` с product dependencies; он не подтверждает утверждение SUMMARY, что `PBXLocalPackageReference` является канонической парой для версии 56.

**Fix (рекомендация, не разрешение на правку):** использовать штатную сериализацию локального пакета, например `isa = XCLocalSwiftPackageReference`, с корректными ссылками; проверить открытие, список схем и реальную сборку обоих таргетов в Xcode. Не заменять этот тест grep-проверкой имени ошибочного класса.

#### CR-02 — У extension указан несуществующий product type

**File:** `/Users/serzhsharapa/hq/build/ai-usage-macos-widget/AiUsage.xcodeproj/project.pbxproj:132`.

**Issue / evidence:** `com.apple.product-type.widget-extension` не является штатным типом WidgetKit-таргета. Официальный WidgetKit-таргет `Widgets` в Apple Food Truck [S3] использует `com.apple.product-type.app-extension`. Официальная спецификация Swift Build [S4] определяет для `app-extension` расширение `appex`, `APPLICATION_EXTENSION_API_ONLY = YES` и `LD_ENTRY_POINT = _NSExtensionMain`; заявленный в проекте `widget-extension` там не определён.

**Counterexample / required property:** после исправления CR-01 сборочная система должна выбрать существующую спецификацию extension и получить корректный executable/appex. Текущий идентификатор не выбирает эту спецификацию. Это дефект конфигурации до проверки личной подписи, а не отсутствие сертификата на машине review.

**Fix:** использовать штатный `app-extension` и проверить build settings/entry point и подписанный продукт. Проверка самого Swift-файла не проверяет product type.

#### CR-03 — Extension встраивается в двойной каталог PlugIns

**File:** `/Users/serzhsharapa/hq/build/ai-usage-macos-widget/AiUsage.xcodeproj/project.pbxproj:22-24`; потребители — `scripts/build.sh:136-139`, `scripts/verify-install.sh:212,218`.

**Issue / evidence:** `dstSubfolderSpec = 13` уже выбирает каталог PlugIns продукта, а `dstPath = PlugIns` добавляет ещё один относительный компонент. Copy Files соединяет destination subfolder и destination subpath [S5]; штатный Apple-проект с тем же `dstSubfolderSpec = 13` имеет `dstPath = ""` [S3]. Результат текущей настройки — `Contents/PlugIns/PlugIns/AiUsageWidget.appex`, не ожидаемый скриптами `Contents/PlugIns/AiUsageWidget.appex`.

**Counterexample / required property:** даже при исправленных ISA/product type и успешной компиляции `build.sh` отвергнет такой продукт как «без расширения»; корректное место регистрации extension также не получается. Проверка наличия строки `PlugIns` в проекте пропускает этот дефект.

**Fix:** оставить пустой `dstPath` при subfolder 13; проверить физическую раскладку собранного `.app` до staged-копирования и регистрацию именно встроенного appex. Реальная сборка не выполнялась.

#### CR-04 — Остановщик проверяет строку argv, а не точный исполняемый файл

**File:** `/Users/serzhsharapa/hq/build/ai-usage-macos-widget/scripts/stop-installed.sh:90-114`.

**Issue / evidence:** якорь `^<anchor>( |$)` применяется к `ps ... command=`. Это строка команды с аргументами, не удостоверенный путь исполняемого файла. Для executable с пробелами невозможно таким способом различить аргумент и продолжение имени файла. Строка `<anchor> Helper` проходит и первоначальный поиск, и повторную проверку, хотя файл `AI Usage Widget Helper` — не `AI Usage Widget`. Кроме того, argv допускает подмену и не связывает найденный процесс с проверенной подписью бандла на диске.

**Independent counterexample:** исполнена **оригинальная функция** остановки с фиктивными `ps/codesign/plutil/env` и своим временным APP_PATH. `ps` возвращал только `.../Contents/MacOS/AI Usage Widget Helper`, PID 12345. Получено `PROBE: would send kill -TERM 12345 to helper-prefix match`, затем «подтверждён фактический выход», `PROBE_STOP_HELPER_RC=0`. `env` был функцией-заглушкой: системный kill и реальные сигналы **не вызывались**.

**Required property / fix:** D-03/T-01-12 требуют остановки только exact executable. Проверять путь процесса через API, возвращающий executable URL/path (например, AppKit/libproc), нормализовать его и сравнивать целиком; удостоверять идентичность экземпляра, повторно проверять непосредственно перед остановкой. Сохранить поддержку стартовых аргументов без разбора имени файла по пробелу. Не обещать абсолютной атомарности пары `ps`/`kill`: повторение того же сравнения argv не устраняет её недостатки.

#### CR-05 — Полная staged-проверка принимает другой продукт той же команды

**File:** `/Users/serzhsharapa/hq/build/ai-usage-macos-widget/scripts/verify-install.sh:210-266`; вызов перед заменой — `scripts/build.sh:155-166,196-210`.

**Issue / evidence:** проверяются TeamIdentifier, Authority, права, группы и целостность, но не `CFBundleIdentifier` приложения/appex, не signed Identifier и не точка расширения. `APP_BUNDLE_ID` объявлен на строке 29, но не участвует в приёмке продукта. Проверка identity в stop-installed относится к **старой** установке и не исправляет отсутствие проверки **новой**.

**Independent counterexample:** self-test преобразован только в памяти: фикстуры получили `com.fixture.otherapp` / `com.fixture.otherapp.widget` в Info.plist и DV Identifier, остальные поля остались штатными multiline XML. Дочерний процесс исполнял неизменённый настоящий `verify-install.sh --app-path`. Наблюдалось `INDEPENDENT_WRONG_BUNDLE_ID=com.fixture.otherapp`, затем `V1 ... принята, PASS` и 13/13. Это демонстрация пропущенного правила на заглушках, **не** принятие настоящей подписи.

**Required property / fix:** до перемещения старой установки удостоверять точные bundle IDs в Info.plist и подписи, executable/package type и `NSExtensionPointIdentifier`. Чужой продукт, пусть подписанный той же personal team, должен дать FAIL. Добавить held-out положительный пример и отрицательные примеры wrong app ID / wrong appex ID / wrong extension point.

### BLOCKER / medium

#### CR-06 — Валидно декодируемый номер записи вызывает арифметический crash

**File:** `/Users/serzhsharapa/hq/build/ai-usage-macos-widget/AiUsage/AiUsageApp.swift:67-69,107-110`; модель — `Packages/UsageCore/Sources/UsageCore/TestRecord.swift:20-35`.

**Issue / evidence:** синтезированный Codable принимает любое представимое `Int`, включая `Int.max`. Следующая запись делает `previous + 1` **вне** do/catch; Swift traps при переполнении, обработчик ошибки записи не достигается.

**Independent counterexample:** оригинальный код декодера исполнен в Swift-пробе с `{"number":9223372036854775807,"recordedAt":"2025-10-09T08:53:20Z"}`. Вывод: `DECODED_NUMBER=9223372036854775807 INCREMENT_OVERFLOW=true`. Для безопасности проверялся `addingReportingOverflow`, а не запускался crash приложения. 14 тестов этого граничного случая не покрывают.

**Required property / fix:** повреждённый/чужой снимок не должен падением завершать приложение (T-01-04). Валидировать допустимый диапазон счётчика и выполнять checked increment, отображая явный ошибочный результат. Добавить тест максимального и отрицательного номера, с явно определённой политикой восстановления; silently wrapping integer не подходит.

### WARNING / medium

#### WR-01 — Регистрация старой копии либо ошибочный pluginkit дают общий PASS

**File:** `/Users/serzhsharapa/hq/build/ai-usage-macos-widget/scripts/verify-install.sh:268-273,291`.

**Issue / evidence:** `pluginkit -m -i ... || true` стирает код отказа, а любой непустой вывод трактуется как регистрация **установленного** продукта. После запусков из Xcode/Downloads существует естественный случай регистрации того же ID по другому пути. Текущий запрос не получает и не сверяет путь, активность и принадлежность проверенному appex; первая строка вывода не доказывает этого.

**Independent counterexample:** оригинальный `verify_bundle` исполнен с нормальными multiline entitlement-фикстурами и fake HOME. Заглушка pluginkit вернула запись того же ID с Path `/fixture/Downloads/Old.app/.../AiUsageWidget.appex` и код **1**. Скрипт напечатал `[f] ... зарегистрировано` и `PASS`, `PROBE_STALE_REGISTRATION_AND_FAILED_TOOL_RC=0`. Реальные pluginkit/codesign/security не вызывались; сроки подписи были явно stubbed.

**Fix:** сохранять exit status, читать полный verbose-ответ с путями, сопоставлять конкретную регистрацию с каноническим установленным appex и её состоянием. Тестировать нормальный многострочный ответ, другой путь того же ID, несколько записей и tool error отдельно. До этого общий PASS нельзя использовать как доказательство интеграции 01-04.

#### WR-02 — Ошибка ps выдаётся за отсутствие процесса и подтверждённый выход

**File:** `/Users/serzhsharapa/hq/build/ai-usage-macos-widget/scripts/stop-installed.sh:94,103-105,110,118-119`.

**Issue / evidence:** ошибки перечисления и чтения процесса подавляются через `|| true`; пустой результат считается «не запущен» или «вышел». `build.sh` после такого нулевого результата продолжает замену, хотя единственный писатель мог остаться живым.

**Independent counterexample:** в той же изолированной пробе оригинальной функции заглушка `ps` всегда возвращала 1. Получено «не запущен ... ни одного сигнала», `PROBE_PS_ERROR_RC=0`.

**Fix:** полный отказ перечисления процессов должен давать явный FAIL. При проверке отдельного PID различать действительно исчезнувший процесс и невозможность получить его состояние; не считать ошибку инструмента доказательством выхода. Добавить сценарии ошибок до и после TERM. Это не требует посылки настоящих сигналов в тесте.

#### WR-03 — Личные имена сохраняются в сыром промежуточном DV-файле

**File:** `/Users/serzhsharapa/hq/build/ai-usage-macos-widget/scripts/verify-install.sh:222-224`; дополнительные точки без фильтра — `scripts/build.sh:159,176`.

**Issue / evidence:** raw `codesign -dv` записывается на диск до редакции Authority. В частности, файл собственной независимой пробы `dv-app.txt` содержал `Authority=Apple Development: Fixture Owner (TESTTEAMID)`, хотя терминальная строка была уже `[REDACTED]`. В реальном прогоне здесь будет имя identity владельца. Cleanup в обычном EXIT уменьшает время хранения, но не отменяет первоначальную персистенцию; при прерывании процесса сырой файл может остаться. D-04/01-03 prohibition требуют редакции **каждой** точки персистенции, а не только финального лога. Кроме того, VOUT/SOUT записываются в build.log напрямую, минуя общий redact.

**Fix:** разбирать DV в памяти или сохранять только необходимые уже очищенные поля; не создавать raw-файл с identity. Пропускать VOUT/SOUT через общий редактор до логирования. В тестах использовать только фиктивные имена/email и проверять временные файлы, итоговый лог и вывод по отдельности. Утечку реального ключа или токена этот review **не наблюдал**.

#### WR-04 — Диагностика экспортирует имена файлов за пределами App Group

**File:** `/Users/serzhsharapa/hq/build/ai-usage-macos-widget/scripts/diagnostics.sh:89-98,123-125`; обещание безопасного экспорта — `docs/phase-01-setup.ru.md:236-241`.

**Issue / evidence:** AppGroupID берётся из непроверенного Info.plist, проверяется только непустота, затем включается в путь для `ls`. Значение `../../Documents` выходит из Group Containers в `$HOME/Documents`. Даже синтаксически валидный GID может указывать на symlink за границу разрешённого каталога. Диагностика запускается как раз при сломанной/чужой установке; здесь нельзя полагаться на ранее успешный verify-install.

**Independent counterexample:** оригинальная collect-функция исполнялась только со своим fake HOME, версиями/подписью/pluginkit-заглушками и AppGroupID `../../privatefixture`. Раздел «контейнер группы» вывел имя каталога `PRIVATE_SENTINEL_DIRECTORY`, созданного вне Group Containers. Реальные пользовательские каталоги не читались; конфиг ожидаемой команды не создавался.

**Fix:** до чтения и экспорта удостоверять собственный бандл и GID точного разрешённого формата относительно ожидаемой команды; проверять нормализованный конечный путь/симлинки. При отсутствии доверенной конфигурации собирать версии инструментов, но пропускать небезопасный контейнер с явным объяснением. Не обещать, что любой нынешний отчёт безопасно пересылать.

### WARNING / low

#### WR-05 — Ошибка чтения файла считается повреждением JSON

**File:** `/Users/serzhsharapa/hq/build/ai-usage-macos-widget/AiUsage/AiUsageApp.swift:92-103`; `/Users/serzhsharapa/hq/build/ai-usage-macos-widget/Widget/TestWidget.swift:69-80`.

**Issue / counterexample:** если каталог доступен, но существующий корректный snapshot не читается из-за разрешений или I/O, ошибка `Data(contentsOf:)` попадает в тот же catch, что и ошибка JSONDecoder, и возвращается `.corrupt`. При ошибке проверки existence возможна также ложная `.missing`. Проба записи приложения/листинг каталога расширения не доказывают читаемость конкретного файла. Пользователю вместо проблемы доступа предлагается перезаписать «повреждённые» данные, а приложение через previousNumber может сбросить номер на 1. Это не требование last-known-good будущей фазы 2, а различимость диагностических состояний D-07 текущего трассера.

**Evidence / fix:** подтверждено трассировкой исходников, отдельная permission-проба не исполнялась. Разнести чтение и декодирование: отсутствие файла → missing, отказ файлового доступа → containerUnavailable/отдельная ошибка доступа, только DecodingError → corrupt. Проверять классификацию синтетическими файловыми ошибками, не меняя права реального Group Container.

## Summary и границы

- **11 findings:** 5 high, 5 medium, 1 low; по схеме роли — 6 BLOCKER/Critical и 5 WARNING. Cosmetic/style findings не добавлялись.
- Рассмотрены **все 17 исходных файлов**, включая новые untracked файлы, а не только git diff. Прочитаны AGENTS/CLAUDE и наследуемые правила, PROJECT/ROADMAP/REQUIREMENTS, CONTEXT с D-01…D-12, все пять PLAN и SUMMARY 01-01/02/03, VALIDATION, полный reviewer role и honest-verifier rubric. Project skills не обнаружены, agent_skills mapping пуст.
- Реальный маршрут из контекста среды — **openai/gpt-6.1-sol, OpenAI**; high — запрошенный task override, не отдельное измерение effort инструментом. Review независим по семейству от заявленных GLM/Flash-авторов. Другой модели, metered API или subagent не вызывалось. Сообщённый transport reset — environment event, не quality failure; начальный счёт попыток реализации/исправления 0, исправлений этот review не делал.
- Граф данных прослежен: app → TestRecordStore → файл App Group → TestProvider → widget; install-граф: build → staged verify → stop old instance → Trash/mv → open. У расширения по исходникам нет сети, Keychain и записи контейнера. API провайдеров и Keychain ещё не реализованы и не сертифицировались.
- `$(DEVELOPMENT_TEAM).group.aiusage` одинаков в четырёх текущих файлах; это осознанное отклонение от планового AppIdentifierPrefix, не самостоятельный найденный дефект. Реальная подстановка Xcode остаётся unverified. `get-task-allow` в явном списке служебных метаданных не объявлялся запрещённым дополнительным capability.
- D-01…D-04/D-12 затронуты конфигурацией сборки, безопасностью остановки/приёмки и диагностикой; D-06/D-07 — контрпримером счётчика и классификацией ошибок. D-05/D-08…D-11 статически присутствуют, но визуальная приёмка и фактическая работа двух процессов не заменены чтением символов.

## Независимо исполненные проверки

| Проверка | Результат и предел доказательства |
|---|---|
| `TMPDIR=<approved scratch> bash scripts/verify-install.sh --self-test` | **13/13**, rc=0. Штатная положительная фикстура действительно содержит multiline plist; базовый парсер не отвергает его. Поэтому «весь plist/многострочный формат не работает» здесь **не finding**. Codesign — заглушка. |
| `TMPDIR=<approved scratch> bash scripts/stop-installed.sh --self-test` | **36/36 assertions**, rc=0. Это 36 проверок нескольких сценариев, не 36 живых остановок. Все kill/open перехвачены. |
| `TMPDIR=<approved scratch> bash scripts/tests/preflight-negative.sh` | **6 прогонов**, rc=0; пять независимых веток плюс вариант отсутствующего/пустого файла. Только fake HOME/PATH/CWD. |
| `swift test --package-path Packages/UsageCore --scratch-path <mktemp approved scratch> -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing` | **14 tests / 1 suite**, rc=0; собственная изолированная сборка, около 20 s. Предупреждения ld о отсутствующих CLT search paths не скрывались. |
| `plutil -lint` project.pbxproj, оба Info.plist, оба entitlements | Все пять OK. Не семантическая проверка Xcode object graph/подписи. |
| `swiftc -parse AiUsage/AiUsageApp.swift Widget/TestWidget.swift` | rc=0, только синтаксис. |
| `swiftc -typecheck -parse-as-library -swift-version 6 -target arm64-apple-macos15.0 -I <scratch Products/Debug> ... Widget/TestWidget.swift`, с `-D DEBUG` и без него | Оба rc=0. Проверены семантика виджета и доступность API для deployment macOS 15 против CLT SDK; Release-ветка виджета проверялась с Debug-built модулем UsageCore, это **не** сборка всего Release-продукта. |
| `bash -n` build/diagnostics; self-test-исполнение verify/stop/preflight | Синтаксические проверки прошли. |
| Held-out probes CR-04/05/06, WR-01/02/03/04 | Контрпримеры, приведённые выше, независимо наблюдались. Это обнаружение дефектов, а не дополнительный integration PASS. |

Точные безопасные схемы воспроизведения: для stop/registration/diagnostics в память загружались только определения оригинальных функций (`sed` → shell eval), production main не запускался; внешние ps/codesign/plutil/pluginkit/security/kill заменялись функциями или штатными test-stubs. В CR-05 в памяти менялась **генерация фикстур**, дочерний verifier оставался исходным. Путь всех новых песочниц: `/var/folders/1b/3fg5ss5s6zn21df_141fkfmm0000gn/T/kilo/sol-*`; временные результаты reviewer не удалял через rm -rf. Штатные self-tests чистили только собственные mktemp-фикстуры своим предусмотренным cleanup.

## Unresolved checks / честное воздержание

- **01-04 — BLOCKED / not verified:** собственная проверка `xcode-select -p` дала `/Library/Developer/CommandLineTools`; Swift — Apple Swift 6.4, arm64. Не выполнялись настоящие build.sh, подпись, установка, запуск приложения, остановка настоящего процесса, изменение developer dir/аккаунтов/HOME/данных. Живых signed app/appex доказательств нет.
- **01-05 — pending:** фактические CreationDate/ExpirationDate/NotAfter и пересборка после истечения не наблюдались. Срок «7 дней» не утверждается. PLAT-01/фаза не закрываются этим review.
- Полный typecheck SwiftUI-приложения не объявляется PASS: отсутствующий SwiftUIMacros/CLT environment — известный prerequisite Xcode. Обычный `swift test` без explicit Testing plugin не заявляется надёжным: этот review запускал именно детерминированную команду с plugin-path.
- Ошибки exploratory tools не считаются успехом: отсутствует локальный Ruby `xcodeproj` (`cannot load such file -- xcodeproj`); несколько первоначальных URL дали 404, корректные источники перечислены ниже. Первые варианты decoder-пробы через stdin/JIT не слинковались (`_main` / Symbols not found); приведённое доказательство CR-06 получено последующим успешным исполнением оригинального декодера через `swift -e`. Первое source/process-substitution испытание shell-функции не загрузило её; доказательства stop получены отдельным успешным вызовом через eval. Зависимости для обхода ошибок не устанавливались.
- Риск пути/symlink и конкурентной замены при install полностью не покрыт штатным preflight harness; live rollback/open failure, registration timing, automatic scheme AiUsage, правильные signed metadata и развёрнутые GID требуют проверки после исправлений и установки Xcode. Сам факт наличия кода rollback не означает успешный E2E rollback. Поведение при отказе open (оставить новую установку на месте с ошибкой) соответствует явному PLAN 01-03, поэтому отдельным дефектом не объявлено.
- В must_haves нет явных `verification: backstop`; не выдумывался ни такой тег, ни его PASS. Неисполнимые интеграционные/GUI-предикаты имеют insufficient evidence и сохраняют human checkpoint. Источники/фикстуры не заменяют непосредственного наблюдения.

## Источники сверки конфигурации (read-only, проверены 2026-10-11)

- **S1:** CocoaPods Xcodeproj, `XCLocalSwiftPackageReference`: https://raw.githubusercontent.com/CocoaPods/Xcodeproj/master/lib/xcodeproj/project/object/swift_package_local_reference.rb . Поддерживаемый сторонний парсер, не закрытый Xcode SDK.
- **S2:** Tuist XcodeProj, сериализация `XCLocalSwiftPackageReference.isa` и `relativePath`: https://raw.githubusercontent.com/tuist/XcodeProj/main/Sources/XcodeProj/Objects/SwiftPackage/XCLocalSwiftPackageReference.swift . Поддерживаемый сторонний парсер, не живая проверка Xcode.
- **S3:** официальный Apple Food Truck, objectVersion 56, WidgetKit-таргет `Widgets`, copy phase и локальный FoodTruckKit; закреплён commit `3954a769e99f3cc53297d94f2b960ceb2665b3d6`: https://raw.githubusercontent.com/apple/sample-food-truck/3954a769e99f3cc53297d94f2b960ceb2665b3d6/Food%20Truck.xcodeproj/project.pbxproj . `productType = app-extension`, copy `dstPath = ""`, `dstSubfolderSpec = 13`.
- **S4:** официальная спецификация Apple/Swift Build: https://raw.githubusercontent.com/swiftlang/swift-build/main/Sources/SWBApplePlatform/Specs/DarwinProductTypes.xcspec . Определение `app-extension`, его entry point/extension-safe defaults.
- **S5:** официальный Swift Build, `CopyFilesTaskProducer.computeOutputDirectory`: https://raw.githubusercontent.com/swiftlang/swift-build/main/Sources/SWBTaskConstruction/TaskProducers/BuildPhaseTaskProducers/CopyFilesTaskProducer.swift . Соединение subfolder + destinationSubpath.

## Scope preservation

Единственные repo-записи reviewer — этот канонический `01-CODE-REVIEW.md` и `machinefindings.json` рядом. Второй REVIEW/SUMMARY/goal_report не создавался; production не правился, staging/commit/push не выполнялись. Fingerprint 17 исходных файлов в порядке files_reviewed_list (SHA-256 списка `shasum -a 256`): `4904c44addd2eecba4b5ea794cd6446b4b4f471fd5c87036e7eacdb5f0116364`. Рекомендации исправлений не являются новой авторизацией действий.
