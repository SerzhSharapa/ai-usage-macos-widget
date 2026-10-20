---
phase: 01-karkas-xcode-i-lichnaya-podpis
plan: "03"
subsystem: infra
tags: [bash, macos, codesign, entitlements, app-groups, widgetkit, xcodebuild, shell-3-2, security-verification]

requires:
  - phase: 01-01
    provides: "AiUsage.xcodeproj с двумя таргетами и именами продуктов (AI Usage Widget.app / AiUsageWidget.appex), ключ AppGroupID — метаданные читаны, файлы не менялись"
provides:
  - scripts/verify-install.sh — платформенная приёмка по подписанным бинарям с независимой ожидаемой командой, четырёхсторонней сверкой групп, точными множествами прав, режимами --app-path/--self-test
  - scripts/build.sh — идемпотентная пересборка+переустановка одной командой: preflight ×5, Release/--debug, полная staged-верификация до закрытия/замены, откат, лог вне git с редакцией до персистенции
  - scripts/stop-installed.sh — точный stop-only переход: канонический путь, identity до сигнала, процесс — по ФАКТИЧЕСКОМУ пути исполняемого файла ядра через native-помощник procstop (идентичность экземпляра по времени старта, перепроверка перед TERM; ремедиация CR-04 от 2026-10-12), отказ инспекции процессов = FAIL (WR-02), TERM → подтверждённый выход, таймаут = FAIL без эскалации, запусков нет
  - scripts/tests/preflight-negative.sh — негативный harness: пять независимых сценариев отказа preflight в изолированных PATH/HOME/CWD (+ вариант пустого конфига; + поведенческая проверка редакции лога)
  - scripts/diagnostics.sh — диагностика без секретов и персональных данных (количество identity вместо списка)
  - docs/phase-01-setup.ru.md — подробная русская инструкция первичной настройки D-12 (включая expected-team.local до первой сборки и безопасный Debug-сценарий состояния контейнера)
  - .gitignore — дополнен (существующие строки сохранены): scripts/expected-team.local и /build/
affects: [01-04, 01-05, phase-2]

actuals:
  tokens: 25800     # chars/4 по фактически созданным файлам (~103 КБ: 5 сценариев + док + дельта .gitignore)
  tasks: 3
  commits: 0        # коммиты запрещены явным scope родителя («No git commits/staging»); HEAD не двигался: 7583e3a до и после — SHA не имитировался
  plan_head_before: 7583e3ae4e34c68c2c4b642031a84a069bed5b18
  plan_head_after: 7583e3ae4e34c68c2c4b642031a84a069bed5b18

tech-stack:
  added: []          # только предустановленные системные инструменты (codesign, security, pluginkit, plutil, ps, ditto, openssl/LibreSSL из состава macOS) — T-01-SC
  patterns:
    - "Ожидаемая команда — независимая точка отсчёта: scripts/expected-team.local (вне git) сверяется с TeamIdentifier каждого бинаря; согласованная чужая команда отвергается"
    - "Приёмка только по подписанным бинарям и развёрнутым значениям: подписи ×2 + Info.plist ×2 (четырёхсторонняя сверка), не по настройкам проекта"
    - "Замена с доказательством до действия: staged-копия проходит ПОЛНУЮ верификацию до закрытия процесса и перемещения прежнего бандла в Корзину; откат при сбое mv"
    - "Точность остановки (после ремедиации CR-04): сигнал — только PID, чей ФАКТИЧЕСКИЙ путь исполняемого файла от ядра (proc_pidpath, немутабелен argv) ТОЧНО равен каноническому якорю, с идентичностью экземпляра (время старта) и перепроверкой перед TERM; ps command= и argv-префиксы не используются; приманки и подменённые argv не совпадают; ровно один экземпляр — иначе отказ без сигналов"
    - "Редакция до персистенции: email/имена identity/токены/ключи вырезаются до записи в лог и до вывода; сравнение команды — да/нет, содержимое конфига не дублируется"
    - "Тестируемость без окружения: self-test'ы и harness работают на синтетических фикстурах и заглушках в изолированных PATH/HOME/CWD — реальная машина не затрагивается"

key-files:
  created:
    - scripts/verify-install.sh
    - scripts/build.sh
    - scripts/stop-installed.sh
    - scripts/tests/preflight-negative.sh
    - scripts/diagnostics.sh
    - docs/phase-01-setup.ru.md
  modified:
    - .gitignore

key-decisions:
  - "Якорь PID допускает стартовые аргументы процесса: ^<полный путь исполняемого файла>( |$) вместо жёсткого $ — иначе нельзя остановить Debug-экземпляр инъекции 01-04-T3 (open --args -aiusage-sim-state=…); точность пути сохранена (приманка по другому пути и sibling-путь не совпадают — доказано self-test'ом ST1)"
  - "Сигнал отправляется через `env kill` (PATH-поиск), никогда через builtin — единственный способ дать self-test'у заглушку kill без риска для реальных процессов"
  - "Тестовые швы задокументированы в заголовках: AIUSAGE_EXPECTED_TEAM_FILE (путь конфига команды), AIUSAGE_STOP_TIMEOUT (таймаут ожидания выхода, default 10), AIUSAGE_OPENSSL; инварианты не ослабляют"
  - "Служебные метаданные подписи ОС — отдельный явный список исключений SIG_METADATA_KEYS (com.apple.security.get-task-allow): правами не считаются (план 01-03-T1 п. c)"
  - "Провал staged-верификации: staged-копия перемещается в Корзину (mv), а не удаляется — план разрешает «удалить ТОЛЬКО staged-копию», домашнее правило «в Корзину, а не rm» требует перемещения"
  - "Отказ open оставляет НОВЫЙ бандл на месте (дословно по плану: «установленный бандл остаётся на месте»); откат прежнего из Корзины — только при отказе финального mv"
  - "Негативный harness и behavioral-тесты отката запускают build.sh из зеркальной реальности раскладки (cwd/scripts/build.sh, конфиг в cwd/scripts/) — ранний вариант с копией в корне cwd дал бы ложный PASS сценария 5 по чужому пути"

patterns-established:
  - "Пять независимых preflight-проверок с русской причиной и «Следующий шаг:» — единый формат для harness-детекции"
  - "SELF-TEST сценария: mktemp-песочница + PATH-заглушки + журнал сигналов/запусков как поведенческое доказательство (не grep по тексту сценария)"

requirements-completed: []   # PLAT-01 закрывается приёмкой 01-04/01-05; этот план — сценарии и инструкция платформы

coverage:
  - id: D1
    description: "verify-install.sh: ожидаемая команда из конфига (вне git), identity-проверки CR-05 (точные CFBundleIdentifier/package type/NSExtensionPointIdentifier в Info.plist + signed Identifier обоих бинарей), Authority/TeamIdentifier, точные множества прав, четырёхсторонняя сверка групп, целостность, регистрация pluginkit ТОЧНЫМ путём установленного appex (WR-01), срок-наблюдение; DV только в памяти (WR-03)"
    requirement: PLAT-01
    verification:
      - kind: other
        ref: "bash -n scripts/verify-install.sh && bash scripts/verify-install.sh --self-test — 13/13 случаев PASS (включая СОГЛАСОВАННУЮ чужую команду OTHERTEAM, ad-hoc/not set, network.server, keychain, посторонний ключ, расхождения групп ×2, отсутствующий/пустой/кривой конфиг, валидная принята)"
        status: pass
      - kind: other
        ref: "grep 'expected-team.local' и '/build/' в .gitignore — PASS (существующие строки сохранены)"
        status: pass
    human_judgment: false
  - id: D2
    description: "build.sh: preflight ×5 → сборка (Release/--debug) → staged-копия + ПОЛНАЯ верификация до закрытия/замены → делегирование stop-installed.sh → замена с откатом (прежний — в Корзину) → open; лог с редакцией до персистенции"
    requirement: PLAT-01
    verification:
      - kind: other
        ref: "bash scripts/tests/preflight-negative.sh — 6 прогонов PASS: пять независимых отказов с своей причиной + следующим шагом (сценарии 1–5 + пустой конфиг 5b); в 4–5 — лог без email, с маркером REDACTED (поведенческая проверка редакции)"
        status: pass
      - kind: other
        ref: "behavioral-тест отката в песочнице (заглушки xcodebuild/verify/stop/open, реальный ditto): T1 staged-провал → rc=1, прежний бандл на месте, staged в Корзине, stop/open не звались; T2 полный путь → rc=0, прежний в Корзине, новый на месте, open ровно 1 раз; T3 обречённый mv → rc=1 явная ошибка"
        status: pass
      - kind: other
        ref: "bash -n + test -x (build.sh, stop-installed.sh, preflight-negative.sh) — PASS"
        status: pass
    human_judgment: true
    rationale: "Живой полный цикл (реальный xcodebuild/подпись/установка) невозможен до установки Xcode владельцем — планом отложен в 01-04-T2; оркестровка доказана на заглушках поведенчески"
  - id: D3
    description: "stop-installed.sh: точный stop-only переход — канонический путь без аргументов пути, identity (CFBundleIdentifier + TeamIdentifier == expected) до любого сигнала, процесс по фактическому пути ядра (native-помощник procstop: точное равенство + время старта экземпляра + перепроверка перед TERM; ровно один экземпляр), отказ инспекции = FAIL (WR-02), подтверждённый выход, таймаут = FAIL без эскалации, запусков нет"
    requirement: PLAT-01
    verification:
      - kind: other
        ref: "bash scripts/stop-installed.sh --self-test — 36/36 проверок PASS: приманка-копия того же bundle id без сигнала, ровно один TERM ровно цели, чужой CFBundleIdentifier/TeamIdentifier → FAIL без сигналов, PID re-use → FAIL без сигнала, таймаут → FAIL с одним TERM и без KILL, не установлено/не запущено → rc=0 без сигналов, отсутствующий/пустой конфиг → FAIL; open-заглушка — 0 вызовов во всех случаях"
        status: pass
      - kind: other
        ref: "аргумент пути отклоняется rc=2 («аргументов пути НЕТ»); в рабочем потоке нет open/запусков (grep-проверка)"
        status: pass
    human_judgment: true
    rationale: "Механика доказана на заглушках поведенчески; остановка реального экземпляра — 01-04-T3 (машина без Xcode/подписи: 0 identities, живой прогон невозможен)"
  - id: D4
    description: "diagnostics.sh: отчёт без секретов и персональных данных — количество identity вместо списка, редакция до вывода и сохранения"
    requirement: PLAT-01
    verification:
      - kind: other
        ref: "bash -n scripts/diagnostics.sh — PASS; живой прогон в изолированном HOME (sandbox): rc=0, все разделы собраны, отчёт сохранён в ~/Library/Logs/ai-usage/diagnostics-<дата>.txt, identity — только число (0)"
        status: pass
    human_judgment: false
  - id: D5
    description: "docs/phase-01-setup.ru.md: полный путь D-12 — Xcode, sudo xcode-select, Apple ID, Signing & Capabilities для КАЖДОГО таргета, контроль capabilities, первая сборка, expected-team.local ДО первой сборки (происхождение TeamID — Xcode/аккаунт, не подпись продукта), виджет в Центре уведомлений, безопасный Debug-сценарий с stop-installed.sh и запуском с аргументом строго после подтверждённого выхода, честные ожидания reload, пересборка, срок-наблюдение, таблица симптом→причина→шаг"
    requirement: PLAT-01
    verification:
      - kind: other
        ref: "дословная цепочка verify задачи 3: bash -n diagnostics + 8 обязательных grep + негативный скан секретов — DOC-OK"
        status: pass
      - kind: manual_procedural
        ref: "пометка «Тест» в имени виджета честная (проверка общей папки, не продуктовые лимиты); инъекция в 8а явно названа имитацией, отдельной от реальной ошибки"
        status: pass
    human_judgment: false
  - id: D6
    description: ".gitignore: личный конфиг ожидаемой команды и каталог сборки исключены из git, чужие строки сохранены"
    requirement: PLAT-01
    verification:
      - kind: other
        ref: "grep -q 'expected-team.local' && grep -q '/build/' .gitignore — PASS; diff: только дополнение 6 строк"
        status: pass
    human_judgment: false

duration: 27 min
completed: 2026-10-11
status: complete
---

# Phase 1 Plan 03: Сценарии владельца — верификатор, пересборка, stop-only, harness, инструкция Summary

**Верификатор приёмки с независимой ожидаемой командой (согласованная чужая команда не проходит), пересборка одной командой с полной staged-верификацией до замены и откатом, точный stop-only остановщик (приманки не трогает), негативный harness preflight и русская инструкция D-12**

## Performance

- **Duration:** ~27 min (2026-10-11T21:28:50Z → 21:55:33Z; активная фаза исполнения)
- **Started:** 2026-10-11T21:28:50Z
- **Completed:** 2026-10-11T21:55:33Z
- **Tasks:** 3/3
- **Files created/modified:** 7 (6 создано, 1 дополнен)

## Testing Summary (точные команды и результаты)

| # | Команда (дословно из PLAN/VALIDATION) | Результат |
|---|----------------------------------------|----------|
| 1 | `bash -n scripts/verify-install.sh && bash scripts/verify-install.sh --self-test && grep -q 'expected-team.local' .gitignore && grep -q '/build/' .gitignore` | **PASS** — self-test 13/13 (V1 валидная принята; V2 network.server; V3 keychain-access-groups; V4 посторонний ключ; V5 расхождение подписанных групп; V6 расхождение Info.plist GID; V7 СОГЛАСОВАННАЯ чужая команда OTHERTEAM при expected=TESTTEAMID; V8 ad-hoc; V9 TeamIdentifier not set; V10–V12 отсутствующий/пустой/кривой конфиг; V13 без Authority Apple Development) — каждая негативная падает на СВОЁМ правиле (обязательный FAIL-фрагмент в assert'е) |
| 2 | `bash -n scripts/build.sh && bash -n scripts/stop-installed.sh && test -x … && bash scripts/tests/preflight-negative.sh && bash scripts/stop-installed.sh --self-test` | **PASS** — harness 6 прогонов (5 сценариев + пустой конфиг; независимость: отказ ровно на целевой проверке с причиной и «Следующий шаг:»; в сц. 4–5 лог без email с маркером REDACTED); stop self-test 36/36 |
| 3 | `bash -n scripts/diagnostics.sh && DOC=… && grep -q … && ! grep -Eq 'sk-…\|BEGIN (RSA\|OPENSSH\|PRIVATE)' "$DOC"` | **PASS** — DOC-OK |
| 4 | Behavioral-тест отката build.sh (доп., песочница с заглушками xcodebuild/verify/stop/open, реальный ditto) | **PASS** — T1 staged-провал: rc=1, прежний бандл на месте (OLD.txt жив), staged в Корзине, stop/open не звались; T2 полный путь: rc=0, прежний в Корзине, новый на каноническом пути, open ровно 1 раз, stop делегирован 1 раз; T3 обречённый финальный mv: rc=1 явная ошибка |
| 5 | Негативные коды выхода (доп.) | **PASS** — build.sh --target → 2; build.sh два аргумента → 2; verify --app-path без значения → 2; verify --app-path /nonexistent → 1; verify живой без конфига → 1 (причина+следующий шаг); stop-installed с аргументом пути → 2 |
| 6 | diagnostics.sh живой прогон в изолированном HOME (доп.) | **PASS** — rc=0, отчёт собран и сохранён; identity — только количество (0), без имён |
| 7 | Запреты (доп. grep) | **PASS** — в build.sh нет rm/kill/osascript/pkill; в рабочем потоке stop-installed нет open; find-identity не используется как источник срока (в verify-install только в комментарии-запрете и подсказке происхождения TeamID) |

Итого: 7 проверочных групп, все PASS (счётчики актуальны на момент плана; после ремедиаций code review — см. ниже). Живой прогон verify-install/build против настоящих подписанных бинарей невозможен до установки Xcode (0 identities, машина-факт 2026-10-11) — по плану это 01-04-T2/T3, здесь не имитировался.

> **Актуальные счётчики self-tests после ремедиации-3 (2026-10-12, attempt 3 по
> раунду-3 review):** verify-install **31/31** (было 13/13 в плане, 24/24 после
> attempt 1; добавлены P6–P12: перестановки версий, election-маркеры `-`/`=`/`?`,
> дубликаты, канонизация alias-пути); stop-installed **54/54** (было 36/36 в плане,
> 42/42 после attempt 1; добавлены 2c traversal CFBundleExecutable, 2d symlink-
> побег executable, 2e sibling-имя); diagnostics **26/26** (было 20/20; добавлены
> D8 groupXaiusage и D9 aiusagX с маркерами-ИМЁНАМИ файлов); НАТИВНЫЙ
> `scripts/procstop/self-test.sh` **28/28** (было 19/19; attempt 3 добавил:
> (12) symlink КАТАЛОГА MacOS наружу → rc=7 ×2, внешняя фикстура жива, TERM не
> отправлялся; (13) symlink Contents наружу → rc=7 ×2; (14a)/(14b) cleanup —
> ноль сигналов историческому PID и живому процессу с чужой identity);
> preflight-negative 6 прогонов; swift test UsageCore 23/23. Подробности и
> BEFORE/AFTER-пробы — 01-REMEDIATION.json (attempt 3).

## Accomplishments

- Верификатор приёмки, который не верит внутренней согласованности: TeamIdentifier каждого бинаря сверяется с ожидаемой командой владельца из вне-git конфига; согласованная чужая подпись (оба бандла OTHERTEAM + группа OTHERTEAM.group.aiusage) отвергается — доказано фикстурой.
- Четырёхсторонняя сверка группы (подпись app = подпись appex = AppGroupID Info.plist app = Info.plist appex = `<ожидаемая команда>.group.aiusage`), точное множество прав appex, срок подписи как измеренное наблюдение по каждому бинарю (профиль либо NotAfter сертификата из самой подписи; отсутствие профиля — не бессрочность).
- Пересборка одной командой: пять независимых preflight-проверок, полная staged-верификация ДО закрытия прежнего экземпляра и замены, прежняя сборка — в Корзину, откат при сбое mv, лог с редакцией персональных данных до персистенции.
- Точный stop-only остановщик: identity до сигнала; процесс — по фактическому пути исполняемого файла от ядра (ремедиация CR-04: native-помощник scripts/procstop/main.swift — proc_pidpath + время старта экземпляра, точное равенство строк, перепроверка перед TERM, ровно один экземпляр, argv-подмена не совпадает); отказ перечисления процессов — FAIL, а не «не запущен» (WR-02); подтверждённый выход, таймаут = FAIL без эскалации; копия того же bundle id по другому пути не затронута; ничего не запускает.
- Негативный harness preflight: детерминированные отказы каждой из пяти проверок в изолированных песочницах + поведенческая проверка редакции лога.
- Подробная русская инструкция D-12: весь путь владельца от App Store до Debug-демонстрации состояния «ошибки контейнера» без изменения прав реального контейнера.

## Task Commits

**Коммитов нет — намеренно.** Явный scope родительской задачи запрещает staging/commit/push в этом прогоне; перезапись атомарного commit-протокола роли задокументирована здесь вместо фальшивого SHA (прецедент — SUMMARY 01-01). HEAD не двигался: `7583e3ae4e34c68c2c4b642031a84a069bed5b18` до и после (`git rev-parse HEAD`). Все 6 новых файлов лежат в рабочем дереве (`git status`: `?? scripts/ ?? docs/`, `M .gitignore`); решение о коммите — за родителем.

## Files Created/Modified

- `scripts/verify-install.sh` — приёмка по подписанным бинарям: ожидаемая команда, identity продукта (bundle id/package type/точка расширения + signed Identifier, CR-05), Authority/TeamIdentifier, точные права, 4-сторонняя сверка групп, целостность, регистрация pluginkit точным путём appex с нулевым кодом инструмента (WR-01), срок-наблюдение; сырой codesign-DV только в памяти (WR-03); режимы installed / --app-path / --self-test
- `scripts/build.sh` — preflight ×5 → xcodebuild (Release/--debug) → staged + полная верификация → делегирование stop-installed.sh → замена с откатом (Корзина) → open; лог с редакцией
- `scripts/stop-installed.sh` — точный stop-only переход (native-помощник procstop: путь ядра + идентичность экземпляра, TERM, подтверждённый выход, таймаут=FAIL, отказ инспекции=FAIL); --self-test на заглушке помощника; помощник собирается по требованию в ~/Library/Caches/ai-usage
- `scripts/tests/preflight-negative.sh` — негативный harness: 5 независимых сценариев отказа preflight + пустой конфиг, изолированные PATH/HOME/CWD
- `scripts/diagnostics.sh` — диагностика без секретов: количество identity, права, контейнер, хвост лога; редакция до вывода/сохранения
- `docs/phase-01-setup.ru.md` — инструкция D-12 (разделы 1–12, включая 6а и 8а, таблица ошибок)
- `.gitignore` — дополнен: `scripts/expected-team.local`, `/build/` (чужие строки сохранены)

## Decisions Made

- См. key-decisions в frontmatter (тестовые швы, список метаданных ОС, staged → Корзина, поведение при отказе open, зеркальная раскладка harness). Ремедиация 2026-10-12 (CR-04/WR-02/WR-03): «якорь с границей аргументов» и «env kill» упразднены — сопоставление делегировано native-помощнику по пути ядра; kill вызывается только внутри помощника.

## Deviations from Plan

> Ремедиация после code review (2026-10-12, code-fixer по 01-CODE-REVIEW):
> CR-04/WR-02 — сопоставление процесса по argv-строке ps заменено native-помощником
> scripts/procstop/main.swift (proc_pidpath + время старта; отказ инспекции = FAIL);
> CR-05 — verify-install.sh проверяет точные bundle id/package type/точку расширения
> и signed Identifier до любых действий со старой установкой; WR-01 — регистрация
> доказывается ТОЧНЫМ путём appex и нулевым кодом pluginkit; WR-03 — сырой DV и
> выводы verify/stop проходят редакцию до персистенции, DV живёт только в памяти;
> WR-04 — диагностика листит контейнер группы только для доверенного бандла и
> канонического пути. Подробности — 01-REMEDIATION.json.
>
> Ремедиация-2 (2026-10-12, attempt 2 по раунду-2 review: CR-04/WR-01/WR-02/WR-04
> оставались partially_fixed): CR-04 — CFBundleExecutable строго равен литералу
> продукта «AI Usage Widget» (pbxproj PRODUCT_NAME) и безопасен как basename;
> добавлены codesign --verify целостности старого бандла, каноническая граница
> «canonical(root)/Contents/MacOS/<basename>» в обёртке И в помощнике (новый
> контракт `--stop <bundle-root> <exe> <timeout>`, rc=7 при выходе за границу);
> WR-01 — парсер pluginkit-записей с границей header/election-состоянием
> (man pluginkit.8: `+ - ! = ?`), коммитом каждой пары Path+SDK (инвариантность к
> порядку версий) и канонизацией путей, ключ -mD (все eligible-экземпляры);
> WR-02 — три-состояние proc_pidpath (известен/ESRCH/отказ) с независимой
> классификацией владельца и kernel-имени pbi_comm: свой живой процесс с
> нечитаемым путём и совпадающим именем → rc=2 (fail closed), с чужим именем
> (типовой ENOENT после обновления чужого приложения) — не блокирует, зомби —
> не цель; WR-04 — точное строковое равенство GID вместо regex с wildcard-точкой.
> Все 7 закрытых ранее finder'ов не регрессировали (батареи выше).
>
> Ремедиация-3 (2026-10-12, attempt 3 по раунду-3 review, эскалация Kimi после
> двух попыток GLM по CR-04): CR-04 — корень границы в helper сделан неподвижным:
> авторизованный каталог — ЛИТЕРАЛ canonical(root)+"/Contents/MacOS", требуется
> realpath(литерал)==литерал и canonical(parent(exe))==литералу (symlink самого
> MacOS или Contents больше не переопределяет границу; контрпример раунда 3 с
> TERM внешней фикстуре воспроизведён ДО правки и отвергнут rc=7 после);
> WR-06 — cleanup нативного self-test переведён на identity-снимок
> (uid+birth+comm) с немедленным исключением reaped-фикстур и повторной сверкой
> перед каждым сигналом; историческим PID и процессам с чужой identity — ноль
> сигналов (stub-пробы (14a)/(14b)). Изменены только scripts/procstop/main.swift
> и scripts/procstop/self-test.sh; обёртка не тронута. Подробности —
> 01-REMEDIATION.json (attempt 3).



### Auto-fixed Issues

**1. [Rule 1 - Bug] plutil трактует точки в ключах прав как разделители keypath**
- **Found during:** Task 1 (первый прогон self-test отверг валидную фикстуру)
- **Issue:** `plutil -extract com.apple.security.app-sandbox raw` не находит ключ: точка — разделитель keypath; проверки прав всегда падали
- **Fix:** esc_key() экранирует точки (`com\.apple\.…`) — поведение подтверждено пробой; self-test стал зелёным
- **Files modified:** scripts/verify-install.sh
- **Verification:** self-test 13/13
- **Committed in:** — (коммиты запрещены scope; см. Task Commits)

**2. [Rule 1 - Bug] EXIT-trap в bash 3.2 затирал код выхода (usage возвращал 1 вместо 2)**
- **Found during:** Task 3/финальная проверка (доп. негативные тесты аргументов)
- **Issue:** cleanup-функция трапа заканчивалась `[ -n "$VAR" ] && rm …` → при пустой переменной трап возвращал 1 и process exit status менялся с 2 на 1
- **Fix:** cleanup всегда `return 0`; строковые трапы переписаны if-формой (verify-install, stop-installed, preflight-negative)
- **Files modified:** scripts/verify-install.sh, scripts/stop-installed.sh, scripts/tests/preflight-negative.sh
- **Verification:** usage rc=2, все прежние коды сохранены (таблица №5)
- **Committed in:** — (см. выше)

**3. [Rule 1 - Bug] авторские дефекты self-test'ов (heredoc-ограничители, захват rc, мёртвые переменные pipe-субшелла)**
- **Found during:** Tasks 1–2
- **Issue:** непарные `<<STUB'`; присваивание rc из command substitution под set -e; мёртвый while в pipe-субшелле проверок прав; RC2B снимался после return 0
- **Fix:** кавычные ограничители, set +e-брекеты и глобальный ST_RC, цикл по keys через herestring
- **Files modified:** scripts/verify-install.sh, scripts/stop-installed.sh
- **Verification:** self-test'ы 13/13 и 36/36 без пропусков
- **Committed in:** — (см. выше)

---

**Total deviations:** 3 автофикса (все Rule 1 — баги, пойманные собственными self-test'ами до сдачи) + 6 проектных решений в key-decisions (в рамках контрактов плана).
**Impact on plan:** объём плана не расширен; все правки внутри семи разрешённых путей.

## Issues Encountered

- None blocking. Bash 3.2-совместимость подтверждена прогонами на штатном /bin/bash 3.2.57 (без mapfile/ассоциативных массивов/bash4-конструкций).

## User Setup Required

None в этом плане. Установка Xcode, вход Apple ID и создание scripts/expected-team.local — план 01-04-T1 (checkpoint human-action, инструкция разделы 2–6а).

## Known Stubs

None — заглушки существуют только внутри self-test/harness-режимов и в живых прогонах не участвуют; продукционных заглушек и «демо»-веток нет.

## Threat Flags

None — новой поверхности за пределами threat_model плана не добавлено (T-01-03/05/06/07/11/12/SC закрыты как задумано; тестовые env-швы описаны в key-decisions и заголовках сценариев).

## Next Phase Readiness

- **01-02 (волна 2)** не зависит от этого плана; **01-04** получает готовые инструменты: verify-install.sh (живой прогон по установленным бинарям), build.sh (полный цикл), stop-installed.sh (шаг 6c), docs/phase-01-setup.ru.md (инструкция checkpoint'а T1).
- Конфиг `scripts/expected-team.local` владельцем ещё НЕ создан — так и задумано (01-04-T1, до первой сборки); все сценарии честно отказывают без него с причиной и следующим шагом.
- Живые прогоны против реальной подписи — 01-04-T2/T3 (Xcode отсутствует, 0 identities — машина-факт 2026-10-11).
- Код планов 01-01/01-02 не менялся; метаданные (bundle id, имена продуктов, ключ AppGroupID, суффикс group.aiusage) читаны из project.pbxproj и планов.

## Self-Check: PASSED

- [x] scripts/verify-install.sh — существует, -x, bash -n OK, self-test 13/13
- [x] scripts/build.sh — существует, -x, bash -n OK, harness + behavioral-откат PASS
- [x] scripts/stop-installed.sh — существует, -x, bash -n OK, self-test 36/36
- [x] scripts/tests/preflight-negative.sh — существует, -x, 6 прогонов PASS
- [x] scripts/diagnostics.sh — существует, -x, sandbox-прогон PASS
- [x] docs/phase-01-setup.ru.md — существует, DOC-OK цепочка PASS
- [x] .gitignore — дополнен, существующие строки сохранены
- [x] scripts/expected-team.local НЕ создан (принадлежит владельцу, 01-04-T1)
- [x] HEAD не менялся (7583e3a), коммитов/staging нет; вне семи разрешённых путей + SUMMARY ничего не записано

---
*Phase: 01-karkas-xcode-i-lichnaya-podpis*
*Completed: 2026-10-11*
