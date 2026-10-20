# Phase 1: Каркас Xcode и личная подпись - Research

**Researched:** 2026-10-11
**Domain:** macOS Xcode-каркас: подпись personal team, WidgetKit extension, App Group, xcodebuild-сборка и переустановка вне Xcode
**Confidence:** MEDIUM (платформенные API — HIGH; личная подпись на этой машине — LOW до установки Xcode владельцем)

**Метод и честное ограничение:** research-plan seam направил все 10 вопросов на провайдер `context7`, который в этом рантайме недоступен (нет MCP-инструмента). Подменять маршрут на другие поисковые провайдеры запрет не позволил. Использована прямая авторизация задачи: встроенный `webfetch` официальной документации developer.apple.com (контент получен и процитирован в этой сессии — теги `[VERIFIED: developer.apple.com/…]`), локальные man-страницы macOS и машинные пробы. Seam `classify-confidence` оценивает id «webfetch» как LOW-tier; расхождение зафиксировано: содержимое взято из первоисточника Apple, поэтому применены правила тегов роли (инструмент + авторитетный источник), а не оценка по id провайдера.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions (D-01…D-12, дословно)

**Сборка и переустановка**
- **D-01:** После ручной первичной настройки Apple ID и personal team в Xcode повторная сборка и установка выполняются одной командой. Сценарий проверяет готовность Xcode и собирает через `xcodebuild`.
- **D-02:** Личная сборка устанавливается в `~/Applications`, без необходимости прав администратора. Приложение запускается независимо от Xcode.
- **D-03:** Повторный вызов команды означает согласие на автоматическое закрытие текущего экземпляра этого приложения, замену сборки и запуск новой. Дополнительное подтверждение замены не требуется. Данные не очищаются; чужие приложения и файлы не затрагиваются.
- **D-04:** В терминале показываются краткая понятная причина ошибки и следующий шаг; подробный вывод сохраняется в локальном логе вне git. Секреты в лог не записываются.

**Тестовое приложение и виджет**
- **D-05:** Каркас приложения сразу представлен тестовым пунктом в строке меню с небольшой диагностической панелью, без Dock-иконки и без карточек провайдеров. Это не реализация требований MENU-01/MENU-02 фазы 4.
- **D-06:** Кнопка в панели записывает новый номер проверки и время записи в App Group. Виджет показывает те же значения с явной пометкой теста. Наблюдаемый результат должен доказывать чтение записи приложения, а не встроенного примера.
- **D-07:** Отсутствие контрольной записи и ошибка доступа к общему контейнеру отображаются разными понятными состояниями. Без записи предлагается открыть приложение и записать тест. При ошибке доступа показывается проблема контейнера. Встроенные данные не подставляются вместо отсутствующей или недоступной записи.
- **D-08:** В фазе 1 проверяется только небольшой виджет `systemSmall`. Продуктовые `systemSmall` и `systemMedium` с лимитами остаются в фазе 5.

**Имя и язык каркаса**
- **D-09:** Отображаемое имя приложения в Finder: `AI Usage Widget`.
- **D-10:** Кнопки и сообщения тестового каркаса на русском языке; полноценная локализация интерфейса в фазу 1 не входит.
- **D-11:** Имя виджета в галерее содержит пометку «Тест»: `AI Usage Widget - Тест`. Описание объясняет проверку общей папки. При появлении настоящих лимитов тестовая пометка убирается.
- **D-12:** Инструкция фазы подробная, на русском языке: первичная настройка Apple ID, подпись, widget extension, общий контейнер, команды, ожидаемые результаты и действия при ошибках. Названия пунктов Xcode приводятся как в интерфейсе. Знание Swift не требуется. Окончательный README EN/RU/ZH остаётся в фазе 6.

### the agent's Discretion (дословно)
Специального делегирования пользовательских предпочтений не было. Технические
детали вне перечисленных решений определяют исследователь и планировщик:
структура проекта, идентификаторы таргетов/App Group, реализация тестовой записи,
имя команды и место локального лога. Это не разрешение обходить personal team,
изоляцию расширения, границы фаз или менять зафиксированные решения.

### Deferred Ideas (OUT OF SCOPE)
Новых возможностей вне объёма фазы в обсуждении не предложено.
Оба продуктовых размера виджета остаются в фазе 5, окончательный трёхъязычный
README в фазе 6, как уже определено дорожной картой.

### Границы фазы (CONTEXT.md, domain)
- В фазу: воспроизводимая сборка macOS 15+, два таргета, установка и работа вне Xcode, тестовый снимок в App Group, проверка entitlements через `codesign`.
- Вне фазы: продуктовые адаптеры, формат снимка UsageCore, ключи, карточки лимитов, фоновый опрос, интерактивное обновление виджета. Тестовый снимок НЕ фиксирует контракт фазы 2. Horizontal Layers сохраняется; тестовая связь двух таргетов — проверка платформы.
- Явный блокер: недоступность требуемой подписи или App Group показывается явно, без скрытой смены команды или схемы доступа (см. Pitfall 7).
- Срок действия профиля «семь дней» из PLAT-01 — не факт, а гипотеза: фактический срок проверяется на машине (ROADMAP, критерий 3).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PLAT-01 | Сборка из исходников по инструкции (`xcodebuild`, личный Apple ID, personal team): два таргета (app + widget extension), App Group entitlements, сценарий пересборки при 7-дневных профилях; владелец не программист — путь сборки часть продукта | Официальная таблица capabilities macOS: App Groups и App Sandbox доступны бесплатному тиру Apple Developer [VERIFIED]. Формат group id `<team-id>.<name>` без регистрации в портале [VERIFIED]. Точные команды проверки: `codesign -d --entitlements`, `security cms -D`, `pluginkit -m -i` [VERIFIED: man]. Паттерн xcodebuild-сборки [CITED: TN2339]. Срок профиля — машинное измерение, команда зафиксирована; декларации «7 дней» в официальных страницах не найдено [ASSUMED] |
</phase_requirements>

## Project Constraints (from AGENTS.md)

Директивы, обязательные для плана (источник: AGENTS.md + глобальные правила `~/.claude/CLAUDE.md`):

1. **Стек:** SwiftUI + WidgetKit, SwiftPM; без тяжёлых сторонних зависимостей. Нулевые внешние зависимости — соблюдается.
2. **Deployment target:** macOS 15.0+; старые системы не нужны.
3. **Xcode ставит владелец из App Store** — без него виджет не собрать и не подписать. Блокер сохраняется, не обходится.
4. **Security:** ключи только в Keychain; ничего секретного в git, логах, UserDefaults. (В фазе 1 ключей нет, но дисциплина логов D-04 действует сразу.)
5. **Обновления виджета** — по бюджету WidgetKit (~15–60 мин); частая проверка только в строке меню и по ручному refresh.
6. **Дистрибуция:** личная сборка бесплатным Apple ID (personal team); без нотаризации и Developer ID.
7. **AGENTS.md прямо предупреждает:** версии из Stack-документа не заменяют фактическую проверку установленного Xcode и SDK — машинные факты ниже датированы и приоритетны.
8. **Workflow GSD:** прямые правки репо вне GSD-команд запрещены.
9. **Глобальные правила:** удаление — по возможности в Корзину, не `rm` (важно для сценария замены старой сборки, D-03); секреты в документах/логах запрещены; факты с датой проверки.

## Machine Facts (пробы 2026-10-11)

Машинные факты этой сессии — база планирования. Всё, что изменится после установки Xcode, подлежит повторной пробе.

| Факт | Значение | Команда пробы | Вывод |
|------|----------|---------------|-------|
| Активный developer dir | `/Library/Developer/CommandLineTools` | `xcode-select -p` | **Xcode НЕ установлен** — активен только CLT [VERIFIED: probe] |
| `xcodebuild` | `error: tool 'xcodebuild' requires Xcode…` | `xcodebuild -version` | Сборка сейчас невозможна; ожидаемый блокер [VERIFIED: probe] |
| Swift (CLT) | Apple Swift version **6.4** (swiftlang-6.4.0.34.1), target `arm64-apple-macosx27.0.0` | `swift --version` | CLT-тулчейн 6.4; совпадает с линейкой Xcode 27 по STACK.md, но Xcode-версию подтверждать после установки [VERIFIED: probe] |
| ОС | macOS **27.0.1** (26A434), arm64 | `sw_vers; uname -m` | [VERIFIED: probe] |
| Сертификаты подписи | **0 valid identities found** | `security find-identity -v -p codesigning` | Apple ID/personal team ещё не настроены; первичная настройка (D-01) не выполнена [VERIFIED: probe] |
| `codesign` | присутствует (системный) | `codesign -h` | Проверка entitlements доступна уже сейчас [VERIFIED: probe] |
| `security` | присутствует; `cms -D` декодирует CMS | `man security` | Декодирование provisioning profile доступно [VERIFIED: man security] |
| `pluginkit` | присутствует, БД плагинов читается | `pluginkit -m` | Регистрацию extension можно проверять командой [VERIFIED: probe] |
| SwiftPM | «Swift Package Manager - Swift 6.4.0-dev» | `swift package --version` | `swift test`/`swift build` пакета работают без Xcode [VERIFIED: probe] |
| `~/Applications` | существует (не пуст) | `ls ~/Applications` | Цель установки D-02 готова [VERIFIED: probe] |
| Группа контейнеров на машине | `~/Library/Group Containers/` содержит `<TEAMID>.<name>`-папки сторонних приложений (напр. `3L68KQB4HG.group.com.readdle.smartemail`) | `ls ~/Library/Group Containers` | Эмпирическое подтверждение конвенции именования [VERIFIED: probe] |
| Исходники проекта | только `.md`/`LICENSE`; нет Swift, `.pbxproj`, plist, entitlements | `git ls-files` | Greenfield: каркас создаётся с нуля [VERIFIED: probe] |

**Следствие для плана:** два блокера до любой сборки — (1) владелец устанавливает Xcode из App Store и выполняет `xcode-select -s /Applications/Xcode.app` (CLT сейчас активен), (2) владелец входит Apple ID в Xcode и настраивает personal team (сейчас 0 сертификатов). Оба шага только вручную — сохраняются как явные предусловия, не обходятся (D-01, ADP-задача владельца).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Запись тестового снимка (номер+время) | App (меню-бар процесс) | Database/Storage (App Group контейнер) | Единственный писатель — приложение; расширение ничего не пишет |
| Чтение снимка и показ | Extension (widget extension процесс) | — | WidgetKit рендерит в отдельном процессе; читает только контейнер [VERIFIED: WidgetKit doc] |
| Сигнал обновления виджета | App | OS WidgetKit (бюджет) | `WidgetCenter.reloadTimelines` из приложения; при активном приложении не тратит бюджет [VERIFIED] |
| Подпись, профили, entitlements | Build tooling (Xcode/xcodebuild) | OS (codesign/ampers) | Настраивается в Signing & Capabilities; факт — только в подписанных бинарях |
| Переустановка одной командой | Build tooling (скрипт) | App (graceful quit/relaunch) | D-01/D-03: quit → build → replace → launch |
| Регистрация виджета в галерее | OS (LaunchServices/pluginkit) | App (первый запуск) | Виджет появляется в галерее только после запуска приложения [VERIFIED: widget doc] |

## Standard Stack

### Core
| Компонент | Версия | Назначение | Основание |
|-----------|--------|------------|-----------|
| Xcode | актуальная App Store-линейка (на 2026-10: 27.x по релиз-нотам; **машина: не установлен**) | Проект, таргеты, SDK, подпись, `xcodebuild` | Ставит владелец (Constraints). Версию подтвердить `xcodebuild -version` после установки [VERIFIED: probe — отсутствие; CITED: AGENTS/STACK для линейки] |
| Swift language mode 6 + `defaultIsolation MainActor` | 6.4 (CLT машинно) | Языковой режим | CLT уже 6.4; настройкаApproachable Concurrency — билд-сеттинг нового проекта [VERIFIED: probe; CITED: AGENTS/STACK] |
| SwiftUI `App` + `MenuBarExtra(.window)` | macOS 13+ API | D-05: пункт в строке меню с панелью, без Dock | `MenuBarExtra` — Scene «persistent control in the system menu bar»; `.window` — popover-окно; `LSUIElement=true` — без Dock [VERIFIED: developer.apple.com/documentation/swiftui/menubarextra] |
| WidgetKit extension + `StaticConfiguration` | macOS 11+ (framework) | D-06/D-08: тестовый `systemSmall` виджет | Шаблон File > New > Target > Application Extension > **Widget Extension** [VERIFIED: creating-a-widget-extension] |
| App Group (`com.apple.security.application-groups`) | macOS 10.7+ | Общий контейнер app↔extension | Формат `<team-id>.<name>` не требует регистрации в портале [VERIFIED: entitlement doc] |
| `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` | macOS 10.8+ | Доступ к `~/Library/Group Containers/<gid>` | Единственный корректный способ получить путь [VERIFIED: foundation doc] |
| `URLSession`/`Foundation`/`Codable` | в составе SDK | JSON тестовой записи | Без сети в фазе 1 — только файловый JSON [CITED: AGENTS/STACK] |
| локальный SwiftPM-пакет | tools 6.x | Общий код двух таргетов | `swift test` работает даже на CLT [VERIFIED: probe]; см. «Shared code vs .xcodeproj» ниже |

### Supporting
| Компонент | Назначение | Когда |
|-----------|------------|-------|
| `codesign -d --entitlements` | Проверка фактических прав подписанных продуктов | Приёмка (CONTEXT требует codesign) [VERIFIED: man codesign] |
| `security cms -D` + `plutil` | Декодирование provisioning profile, чтение ExpirationDate | Измерение фактического срока профиля [VERIFIED: man security] |
| `pluginkit -m -i <bundle-id>` | Проверка регистрации extension в системе | Диагностика «виджета нет в галерее» [VERIFIED: man pluginkit + probe] |
| Activity Monitor, колонка Sandbox | Визуальная проверка включённости песочницы | Диагностика [VERIFIED: sandbox doc] |

### Alternatives Considered
| Вместо | Можно | Трейдофф |
|--------|-------|----------|
| `MenuBarExtra(.window)` | `NSStatusItem` + `NSPopover` | Полный контроль ценой boilerplate; план Б при подтверждённых квирках .window — фаза 4, не сейчас [CITED: AGENTS/STACK, MEDIUM] |
| `<team-id>.<name>` App Group | `group.<name>` с регистрацией в портале | Portal-регистрация недоступна/неудобна для free-аккаунта; на macOS формат с team id легален и не требует регистрации [VERIFIED] |
| Раздельные Swift-файлы в обоих таргетах | Локальный SwiftPM-пакет | Пакет = locked stack и `swift test` на CLT; файлы проще на bring-up. Рекомендация ниже |

**Installation:**
```bash
# Внешних зависимостей НЕТ. Единственная установка — владельцем, вручную:
# 1) Xcode из App Store
# 2) sudo xcode-select -s /Applications/Xcode.app   # иначе xcodebuild указывает на CLT [VERIFIED: probe 2026-10-11]
# 3) Xcode > Settings > Accounts > вход Apple ID (personal team)
```

## Package Legitimacy Audit

> Раздел требуется при установке внешних пакетов. **Фаза 1 не устанавливает ни одного внешнего пакета** — стек целиком из состава Xcode/macOS SDK (SwiftUI, WidgetKit, Foundation, Security). Проверка skipped-by-design, не пропущена.

**Packages removed due to [SLOP] verdict:** none — внешних пакетов нет.
**Packages flagged as suspicious [SUS]:** none.

## Architecture Patterns

### System Architecture Diagram

```
                 ┌──────────────────────────────────────────────┐
                 │            владелец (вне Xcode)              │
                 └──────┬───────────────────────────┬───────────┘
                        │ кнопка «Записать тест»    │ добавляет виджет в Центр уведомлений
                        ▼                           ▼
   ┌─────────────────────────────┐        ┌──────────────────────────────┐
   │  App-таргет (LSUIElement)   │        │  Notification Center         │
   │  MenuBarExtra(.window)      │        │  ┌────────────────────────┐  │
   │  панель: номер, время,      │        │  │ WidgetKit systemSmall  │  │
   │  кнопка записи              │        │  │ «AI Usage Widget - Тест»│  │
   └──────┬──────────────┬───────┘        │  │ 3 состояния: запись /  │  │
          │              │                │  │ нет записи / ошибка    │  │
          │ пишет JSON   │ WidgetCenter   │  └───────────▲────────────┘  │
          │ (атомарно)   │ .reload-       │              │ timeline:     │
          │              │ Timelines      │              │ читает файл   │
          ▼              │                └──────────────┼───────────────┘
   ┌─────────────────────┴───────────────────┐          │
   │  App Group контейнер                    │──────────┘
   │  ~/Library/Group Containers/            │   путь ТОЛЬКО через
   │  <TEAMID>.<group>/test-snapshot.json    │   containerURL(...); запись
   └─────────────────────────────────────────┘   только app, чтение — extension

   Build/Install (D-01..D-03):  scripts/build.sh
     preflight (Xcode? identity?) → xcodebuild → quit app → заменить .app
     (старый — в Корзину) → cp в ~/Applications → open → владелец видит
     «номер в панели == номер в виджете»
```

Читатель может проследить основной сценарий: кнопка → файл в контейнере → reload → перерисовка виджета в NC; приёмка сравнивает числа на концах цепочки.

### Recommended Project Structure

```
AiUsage.xcodeproj               # два таргета: AiUsage (app), AiUsageWidget (appex)
Packages/UsageKit/              # локальный пакет (фаза 1: только тривиальный тип записи;
│                               #  контракт UsageCore НЕ фиксируется здесь — это фаза 2)
│ Package.swift                 #   + Swift Testing тесты, гоняются `swift test` на CLT
└ Sources/UsageKit/
   TestRecord.swift             #   Codable {номер, recordedAt} — имя «тестовое», не продуктовое
AiUsage/                        # app-таргет
   AiUsageApp.swift             # @main App, MenuBarExtra(.window), LSUIElement в настройках таргета
   TestPanelView.swift          # D-05/D-06/D-10: панель, кнопка, русский текст
   TestRecordStore.swift        # containerURL + проверка ДОСТУПА (не nil!) + атомарная запись
   Info.plist / AiUsage.entitlements
Widget/                         # extension-таргет
   TestWidgetBundle.swift       # @main WidgetBundle
   TestWidget.swift             # StaticConfiguration, .supportedFamilies([.systemSmall]), D-08/D-11
   TestWidgetProvider.swift     # TimelineProvider: 3 состояния D-07
   Info.plist / AiUsageWidget.entitlements
scripts/
   build.sh                     # D-01..D-04: preflight → xcodebuild → quit → replace → launch → лог
   verify-install.sh            # приёмка: codesign x2, profile, pluginkit, контейнер
   diagnostics.sh               # сбор диагностики без секретов
docs/phase-01-setup.ru.md       # D-12: подробная инструкция первичной настройки
```

### Pattern 1: Первичная настройка подписи (один раз, вручную — D-01)
**What:** владелец в Xcode настраивает personal team для ОБОИХ таргетов.
**Когда:** единственный ручной этап; после него rebuild — одна команда.
**Шаги (названия пунктов — как в интерфейсе Xcode, [VERIFIED] по официальным статьям):**
1. Xcode > Settings > Accounts > «+» > вход Apple ID.
2. Проект > таргет > **Signing & Capabilities** > «Automatically manage signing» + Team = personal team — отдельно для `AiUsage` и `AiUsageWidget`.
3. + Capability: **App Sandbox** (оба таргета); в app дополнительно **Outgoing Connections (Client)** (нужен с фазы 2, допустим с фазы 1 по CONTEXT); **App Groups** (оба таргета), одна и та же группа.
4. App Groups в Xcode впишет литерал `<TEAMID>.<group>` в `.entitlements` — файл коммитится; team id не секрет (виден в подписи любого приложения).
**Проверка факта:** `security find-identity -v -p codesigning` должен показать «Apple Development: …» — сейчас на машине 0 идентичностей [VERIFIED: probe].

### Pattern 2: Сценарий rebuild+install (D-01–D-04)
**What:** идемпотентная замена только своего приложения с сохранением данных.
**Ключевое основание сохранности данных:** контейнеры живут НЕ в бандле — песочница app в `~/Library/Containers`, группа в `~/Library/Group Containers/<gid>`; система создаёт их автоматически и никогда не удаляет [VERIFIED: sandbox doc + containerURL doc]. Замена `.app` в `~/Applications` данные не трогает.
**Flow (псевдокод для плана, не реализация):**
```
preflight: xcode-select -p == /Applications/Xcode.app/Contents/Developer?
           xcodebuild -version ок?  identity Apple Development есть?   → иначе: краткая причина + следующий шаг, полный лог в файл вне git (D-04)
build:     xcodebuild -project AiUsage.xcodeproj -scheme AiUsage -configuration Release build
           (SYMROOT/DSTROOT — верифицированные флаги расположения продуктов [CITED: TN2339];
            -derivedDataPath — распространённая альтернатива, подтвердить `man xcodebuild` после установки Xcode [ASSUMED])
quit:      graceful: osascript -e 'quit app "AI Usage Widget"'; fallback точечный pkill ПО ТОЧНОМУ пути бандла — только своё приложение (D-03)
replace:   старый бандл → ~/.Trash (домашнее правило «в Корзину, не rm»), новый → ~/Applications/
launch:    open ~/Applications/"AI Usage Widget.app"
           (запуск после установки обязателен: без него виджет не появится в галерее [VERIFIED: widget doc])
```
**When to use:** каждый пересбор; после истечения профиля — тот же путь (ROADMAP, критерий 3).

### Pattern 3: Тестовая запись и три состояния (D-06/D-07)
**What:** app пишет атомарный JSON; extension читает и различает состояния.
**Критично:** `containerURL` на macOS возвращает URL ожидаемой формы **даже для неверной группы** (не nil, как в iOS), каталог при этом не существует и sandbox-приложение не может его создать — Apple прямо требует «test that you can access the underlying directory before attempting to use it» [VERIFIED: containerURL doc]. Отсюда D-07:
- проверка записи (write test / `isWritableFile(atPath:)` или создание+удаление временного файла) → при неудаче состояние «ошибка доступа к контейнеру»;
- файл прочитан и декодирован → показ номера+времени с пометкой «Тест»;
- файла нет (или не декодируется) → «откройте приложение и запишите тест»; встроенные данные НЕ подставлять.
Запись — через временный файл + rename (атомарность), чтобы extension никогда не читал обрывок.

### Pattern 4: Timeline виджета и честный reload (D-06)
**What:** provider читает файл; app после записи дёргает reload.
- `StaticConfiguration(kind:provider:)`, `.configurationDisplayName("AI Usage Widget - Тест")`, `.description(...)`, `.supportedFamilies([.systemSmall])` [VERIFIED: widget doc].
- Timeline: одна запись «сейчас» + `policy: .after(now+15мин)` — законно, записи ≥5 мин друг от друга [VERIFIED: keeping-up-to-date doc].
- После записи app вызывает `WidgetCenter.shared.reloadTimelines(ofKind: kind)` [VERIFIED]. Пока приложение на переднем плане, reload НЕ расходует бюджет [VERIFIED] — но сигнал не гарантирует мгновенную перерисовку (система может объединять reload) [VERIFIED: coalesce] — в инструкции D-12 сформулировать ожидание «секунды, не мгновенно; срок не гарантирован» (CONTEXT, specifics).

### Shared code vs real .xcodeproj (вопрос постановки)
- **.xcodeproj обязателен:** app-бандл с embedded `.appex` (Contents/PlugIns), entitlements и встраивание extension — функциональность Xcode-проекта; «голый» SwiftPM этого не выражает.
- **Общий код:** locked stack — локальный SwiftPM-пакет, product линкуется в ОБА таргета. Плюс: `swift test` на CLT ещё до Xcode. Риск: wiring пакета в оба таргета на bring-up подписи. Альтернатива на фазу 1 — один общий Swift-файл с членством в двух таргетах; пакет ввести в фазе 2 как UsageCore. Рекомендация: **создать пакет сразу** (стек locked), держа в нём только тривиальный тип тестовой записи, с комментарием «не контракт фазы 2» — граница CONTEXT соблюдена.
- **Название пакета:** STACK.md исторически называет `UsageKit`, ROADMAP фазы 2 — `UsageCore`. Для фазы 1 имя не принципиально (discretion); предложить `UsageKit`, переименование — фаза 2. Против двойного переименования возражений нет; решает планировщик.

### Anti-Patterns to Avoid
- **Проверять «настройки проекта» вместо подписанного бинаря:** entitlements в `.entitlements`/build settings ≠ факт. Только `codesign -d` по установленному `.app` и `.appex` (CONTEXT требует именно это).
- **nil-check контейнера на macOS:** nil не бывает; проверять доступность каталога [VERIFIED].
- **Дублирование логики записи в extension:** extension только читает; writer один — app (изоляция фазы).
- **Добавление сети/Keychain в widget target:** нарушение границы CONTEXT; код intent'ов сети в расширении запрещён уже проектом.
- **Тихий fallback подписи:** ad-hoc/«Sign to Run Locally»/unsandboxed при отказе App Groups — запрещён (явный блокер).
- **Планировать продуктовые карточки/адаптеры в каркасе:** тестовый снимок не продукт фазы 2.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Проверка фактических entitlements | Парсинг `.entitlements`/Info.plist из билд-папки | `codesign -d --entitlements - --xml <bundle>` | Подпись может отличаться от настроек; DER-entitlements дефолт с macOS 12 [VERIFIED: man codesign] |
| Чтение provisioning profile | Ручной base64/DER-парсинг | `security cms -D -i <profile>` + `plutil` | CMS-декодирование готово в системе [VERIFIED: man security] |
| Поиск зарегистрированного extension | `find` по PlugIns на диске | `pluginkit -m -i <bundle-id>` | БД PlugInKit — источник правды системы [VERIFIED: man pluginkit] |
| Путь к общему контейнеру | Конкатенация `~/Library/Group Containers/…` | `containerURL(forSecurityApplicationGroupIdentifier:)` | Путь может меняться; API всегда верен; ошибки формы пути не ловятся вручную [VERIFIED] |
| Проверка включённости песочницы | Логика в коде | Activity Monitor > колонка Sandbox (диагностика) | Официальная рекомендация Apple [VERIFIED] |

**Key insight:** вся проверка платформы фазы строится на четырёх системных инструментах (codesign, security, pluginkit, plutil) — ни одного самописного детектора; фальсификация приёмки исключается самой методикой.

## Runtime State Inventory

> Фаза greenfield, но поток D-01–D-03 управляет runtime-состоянием при переустановке — инвентаризация сужена до него.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | Тестовый JSON в `~/Library/Group Containers/<gid>/` (создаст app) | Ничего — контейнер вне бандла, переживает замену [VERIFIED: containerURL/sandbox docs] |
| Live service config | LaunchServices-регистрация app + запись PlugInKit для appex | Перерегистрация автоматична при `open` после замены (шаг launch в Pattern 2) |
| OS-registered state | Добавленный пользователем экземпляр виджета в NC | Ничего — привязан к bundle id; НЕ менять bundle id между сборками, иначе виджет отвяжется |
| Secrets/env vars | None — verified: в фазе 1 нет ключей/токенов (проба `security find-identity` — 0 идентичностей; секретов в репо нет) | — |
| Build artifacts | DerivedData (воспроизводимо), старый `.app` в `~/Applications` | Старый бандл — в Корзину при замене (домашнее правило) |

## Common Pitfalls

### Pitfall 1: containerURL не возвращает nil на macOS
**What goes wrong:** проверка `guard let url = containerURL(...)` проходит, а каталога нет — запись падает в рантайме у extension.
**Why:** на macOS метод «returns a URL of the expected form, even if the app group is invalid» [VERIFIED: containerURL doc].
**How to avoid:** после получения URL — фактическая проверка доступа (создание/запись временного файла) → отдельное состояние D-07 «проблема контейнера».
**Warning signs:** «отсутствует запись» и «ошибка доступа» показываются одинаково.

### Pitfall 2: виджет не появляется в галерее после установки
**What goes wrong:** приложение установлено, а виджета нет в Центре уведомлений.
**Why:** Apple: «For an app's widget to appear in the widget gallery, a person must launch the app that contains the widget at least once after the app is installed» [VERIFIED: widget doc].
**How to avoid:** шаг `open` в Pattern 2 обязателен после каждой замены; диагностика — `pluginkit -m -i <widget-bundle-id>`.
**Warning signs:** галерея пуста при установленном приложении, которое ни разу не запускалось.

### Pitfall 3: Entitlements «в проекте» ≠ entitlements в подписанном продукте
**What goes wrong:** галочки стоят, а фактический appex подписан без группы/с лишним правом.
**Why:** подпись — отдельная стадия; автоподпись может промолчать или подставить иное.
**How to avoid:** приёмка только по `codesign -d --entitlements - --xml` для app И appex [VERIFIED: man codesign]; негативные проверки для appex (нет network.*, нет keychain-access-groups).
**Warning signs:** проверка «по чекбоксам Xcode» вместо бинарей.

### Pitfall 4: xcodebuild указывает на CLT
**What goes wrong:** сценарий падает с «requires Xcode» даже после установки Xcode.app.
**Why:** сейчас `xcode-select -p` → CommandLineTools [VERIFIED: probe]; установка Xcode сама путь не переключает.
**How to avoid:** preflight в build.sh (D-01) сравнивает путь с `/Applications/Xcode.app/Contents/Developer`; инструкция D-12 даёт команду `sudo xcode-select -s /Applications/Xcode.app` [CITED: TN2339].
**Warning signs:** ошибка «requires Xcode» при установленном Xcode.

### Pitfall 5: Расползание прав extension
**What goes wrong:** виджет получает network.client/Keychain «на будущее».
**Why:** копирование entitlements-файла app в appex.
**How to avoid:** у extension только app-sandbox + application-groups (CONTEXT); негативные codesign-проверки в verify-install.sh.
**Warning signs:** совпадающие .entitlements у двух таргетов.

### Pitfall 6: Рассинхрон group id между таргетами
**What goes wrong:** app пишет в `<TEAMID>.group.a`, extension читает `<TEAMID>.group.b` — «тест» ломается без понятной причины.
**Why:** группа вписывается в два файла отдельно.
**How to avoid:** одна литеральная строка в обоих .entitlements; verify-скрипт сравнивает массивы application-groups из подписанных бинарей между собой.
**Warning signs:** панель показывает запись, виджет — «нет записи» (состояния D-07 различимы — это и есть диагностика).

### Pitfall 7: Тихая подмена подписи при отказе App Groups
**What goes wrong:** Xcode откажет автоподписи с App Groups на personal team → соблазн ad-hoc/«Sign to Run Locally»/отключить sandbox — «и так работает».
**Why:** macOS исторически снисходителен к локально подписанным app; сбой останется незамеченным.
**How to avoid:** ЗАПРЕЩЕНО контрактом фазы: блокер фиксируется явно, решение за владельцем (CONTEXT: «без скрытой смены команды или схемы доступа»). Официальная таблица capabilities предсказывает УСПЕХ (App Groups доступны free-тиру на macOS [VERIFIED]) — но фактическое поведение автоподписи Xcode проверяется только на машине (см. Assumptions A6).
**Warning signs:** предложение «обойти» вместо отчёта о блокере.

### Pitfall 8: Замена задевает чужое / теряет данные
**What goes wrong:** pkill по подстроке имени убивает чужой процесс; `rm -rf` старого бандла против домашнего правила; данные «пропали».
**Why:** небрежный скрипт замены.
**How to avoid:** quit через `osascript quit app` (по точному имени своего приложения), fallback-kill по полному пути бандла; удаление старого бандла в `~/.Trash`; данные в Group Containers вне бандла — сохраняются автоматически [VERIFIED].
**Warning signs:** скрипт трогает что-либо кроме одного bundle path.

### Pitfall 9: Ожидание «reload = мгновенно»
**What goes wrong:** владелец ждёт мгновенной перерисовки и считает фазу проваленной.
**Why:** WidgetKit может коалесцировать reload; бюджет 15–60 мин для фоновых обновлений [VERIFIED: keeping-up-to-date].
**How to avoid:** формулировка ожиданий в D-12-инструкции («появится в течение секунд-минут; срок системой не гарантирован»); ручной reload из активного приложения бюджет не тратит [VERIFIED].
**Warning signs:** претензии к «мгновенности» на приёмке.

### Pitfall 10: Deployment target vs SDK
**What goes wrong:** код фазы 1 компилируется под SDK 27, но падает на macOS 15 (заявленный минимум).
**Why:** API новее deployment target без availability-аннотаций.
**How to avoid:** MACOSX_DEPLOYMENT_TARGET = 15.0; API каркаса (MenuBarExtra, WidgetKit, containerURL) доступны с 13/11/10.8 — запас есть [VERIFIED: availability в .md-докуметах].
**Warning signs:** «работает у меня (27), не проверял на 15». Приёмка на машине владельца — macOS 27; совместимость 15 обеспечивается настройкой, не прогоном.

## Code Examples

Паттерны для планировщика (источники — официальные страницы, полученные в этой сессии; НЕ реализация в этой фазе).

### Меню-бар каркас (D-05)
```swift
// Source: https://developer.apple.com/documentation/swiftui/menubarextra (fetched 2026-10-11)
@main
struct AiUsageApp: App {
    var body: some Scene {
        MenuBarExtra("AI Usage Widget", systemImage: "gauge") {
            TestPanelView()            // номер, время, кнопка «Записать тест» — русский текст (D-10)
        }
        .menuBarExtraStyle(.window)    // popover-окно с произвольным SwiftUI
    }
}
// LSUIElement = true в Info.plist таргета app → без Dock-иконки (D-05)
```

### Запись тестового снимка с проверкой ДОСТУПА (D-06/D-07)
```swift
// Source: https://developer.apple.com/documentation/foundation/filemanager/containerurl(forsecurityapplicationgroupidentifier:)
// «In macOS, a URL of the expected form is always returned, even if the app group is invalid… 
//  be sure to test that you can access the underlying directory before attempting to use it.»
let groupID = "<TEAMID>.group.aiusage"             // литерал из entitlements; discretion планировщика
guard let dir = FileManager.default
    .containerURL(forSecurityApplicationGroupIdentifier: groupID) else { /* теоретически недостижимо на macOS */ }
// ОБЯЗАТЕЛЬНО: фактическая проверка доступа (создание каталога/временного файла),
// иначе состояние «ошибка доступа к контейнеру» (D-07)
// запись: временный файл + rename (атомарно) — JSON {номер: Int, recordedAt: Date}
WidgetCenter.shared.reloadTimelines(ofKind: testWidgetKind)  // из app; при активном app бюджет не тратится
```

### Виджет: конфигурация и provider (D-08/D-11)
```swift
// Source: https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension (fetched 2026-10-11)
struct TestWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: testWidgetKind, provider: TestProvider()) { entry in
            TestWidgetView(entry: entry)   // три состояния D-07; пометка «Тест» (D-11)
        }
        .configurationDisplayName("AI Usage Widget - Тест")
        .description("Проверка общей папки между приложением и виджетом")
        .supportedFamilies([.systemSmall]) // только small в фазе 1 (D-08)
    }
}
// Timeline: [entry(now)], policy: .after(now+15мин) — записи ≥5 мин [VERIFIED: keeping-up-to-date]
```

### Верификационные команды приёмки (grounded)
```bash
APP=~/Applications/"AI Usage Widget.app"
# 1) Фактические entitlements обоих продуктов (CONTEXT-требование):
codesign -d --entitlements - --xml "$APP"
codesign -d --entitlements - --xml "$APP/Contents/PlugIns/"*.appex
#    app:     app-sandbox=true, network.client=true, application-groups=[<gid>]
#    appex:   app-sandbox=true, application-groups=[тот же <gid>], НЕТ network.*, НЕТ keychain*
# 2) Целостность подписи:
codesign -vvv --deep "$APP"
# 3) Фактический срок профиля (ROADMAP: измерить, не предположить):
security cms -D -i "$APP/Contents/embedded.provisionprofile" \
  | plutil -extract ExpirationDate raw -o - -          # и CreationDate/TeamName по вкусу
#    (если embedded.provisionprofile отсутствует — зафиксировать факт: macOS-сборка без профиля;
#     тогда «срок профиля» заменяется сроком сертификата: security find-identity -v -p codesigning)
# 4) Регистрация extension в системе:
pluginkit -m -i <widget.bundle.id>                     # строка вида "com.xxx.yyy.widget(n)" — значит зарегистрирован
# 5) Тестовый снимок на месте:
cat ~/Library/Group\ Containers/<TEAMID>.group.aiusage/test-snapshot.json
# 6) Песочница включена (визуальная диагностика): Activity Monitor > View > Columns > Sandbox
```
Команды 1–3 синтаксически опираются на man-страницы этой машины [VERIFIED: man codesign / man security]; флаг формы вывода `--xml` подтверждён man'ом; точное поведение `--entitlements -` (stdout) — стандартное употребление, проверить `man codesign` на месте при первом прогоне.

### xcodebuild (базовый паттерн)
```bash
# Source: https://developer.apple.com/library/archive/technotes/tn2339/_index.html (2017, archive)
xcodebuild -list -project AiUsage.xcodeproj                 # увидеть схемы/таргеты
xcodebuild -project AiUsage.xcodeproj -scheme AiUsage \
  -configuration Release build SYMROOT="$PWD/build"         # расположение продуктов — SYMROOT [CITED: TN2339]
# затем: build/Release/AI Usage Widget.app → ~/Applications
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `NSStatusItem` + `NSPopover` вручную | `MenuBarExtra(.window)` | macOS 13 | Каркас app = десятки строк SwiftUI; AppKit остаётся планом Б |
| Ручной NSStatusBar-таймер для виджета | WidgetKit timelines + budget | macOS 11 | Виджет = декларативный таймлайн; частоту диктует система |
| `group.<name>` с portal-регистрацией | на macOS `<team-id>.<name>` без регистрации | документировано в entitlement-статье | Free-команда без портала легально получает App Group [VERIFIED] |
| XCTest для новых тестов | Swift Testing (`@Test`, `#expect`) | Xcode 16+ | Тесты пакета фазы 2 — Swift Testing; фаза 1 тест-фреймворка не требует |

**Deprecated/outdated:** AppKit-lifecycle (xib/NSApplicationDelegate) для новых app; «7 дней» как допущение о сроке профиля macOS — не подтверждено официальной документацией, измеряется на машине.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | «7-дневный» срок provisioning profile — iOS-фольклор; для macOS-личных сборок официальной декларации не найдено (fetched pages не содержат цифры) | Machine Facts / PLAT-01 | Средний: сценарий пересборки может вызываться чаще/реже; дорожная карта УЖЕ требует измерить — команда задана; неверно только если срок окажется несуществующим (без профиля вовсе) — тогда критерий 3 выполняется тривиально, факт фиксируется |
| A2 | Приложение, собранное и скопированное локально, не имеет quarantine-атрибута и запускается без нотаризации | Pattern 2 | Низкий: если Gatekeeper вмешается — инструкция D-12 получит шаг снятия атрибута; влияет только на первое предупреждение запуска |
| A3 | Флаг `-derivedDataPath` xcodebuild (удобнее SYMROOT для связки build+install) | Pattern 2 | Низкий: проверить `man xcodebuild` после установки Xcode (сейчас man недоступен — xcodebuild нет); fallback SYMROOT верифицирован TN2339 |
| A4 | Xcode при входе Apple ID создаёт personal team с Team ID и сертификатом Apple Development (даёт `security find-identity` не-пустой) | Pattern 1 | Средний: это предпосылка всей подписи; проверка одной командой после настройки; если нет — явный блокер владельцу |
| A5 | Автоподпись Xcode для macOS-таргета с App Groups на personal team завершится успехом (не потребует портала) | Pitfall 7 | Высокий, но ограниченный: официальная таблица поддерживает free-тир [VERIFIED], фактического прогона Xcode нет; при отказе — явный блокер по контракту (никаких тихих обходов); checkpoint:human-verify обязателен в плане |
| A6 | Виджет в NC доступен из app, установленного в `~/Applications` (не только /Applications) | Pattern 2 | Низкий/средний: pluginkit-проверка даст ответ сразу; если галерея не увидит — диагностика и (при необходимости) решение владельцем, т.к. D-02 фиксирует ~/Applications |
| A7 | man-синтаксис `codesign -d --entitlements - --xml` и `security cms -D | plutil -extract …` работает как записано на этой ОС | Верификация | Низкий: man-страницы локальные, синтаксис сверён с ними; живой прогон — сразу после первой сборки |
| A8 | Bundle id не зарезервирован и автоподпись free-команды его примет (явная регистрация App ID в портале для free-аккаунтов недоступна/не нужна) | Pattern 1 | Низкий: Xcode предложит правку при конфликте; решается на первичной настройке |

## Open Questions

1. **Фактический срок действия подписи/профиля на этой машине**
   - What we know: «7 дней» не подтверждён официальной документацией; измерение заложено (команда в Code Examples, критерий 3 ROADMAP).
   - What's unclear: есть ли embedded.provisionprofile у сборки; 7/7+ дней; применяется ли expiry к запуску.
   - Recommendation: fix в плане как наблюдение после первой сборки и после недели простоя; результат — в phase-verification документ.
2. **Поведение автоподписи Xcode 27 c App Groups на personal team (машина владельца)**
   - What we know: официальная таблица — App Groups доступны free-тиру macOS [VERIFIED].
   - What's unclear: фактический прогон Xcode; возможные диалоги/ошибки интерфейса для D-12-инструкции.
   - Recommendation: checkpoint:human-verify после шага первичной настройки; сценарий отказа = явный блокер (Pitfall 7).
3. **Квирки `MenuBarExtra(.window)` на macOS 27**
   - What we know: стиль документирован; известные сообществу шероховатости перерисовки [CITED: AGENTS/STACK, MEDIUM].
   - Recommendation: не блокирует фазу 1 (панель простая); перенести в research фазы 4.

### Planning Resolution (ревизия планов 1, 2026-10-11 — disposition FOR PLANNING, не эмпирика)

Диспозиции закрывают открытые вопросы НА УРОВНЕ ПЛАНИРОВАНИЯ. Они не являются
эмпирическими результатами: живых прогонов Xcode/подписи не было — фактические
данные появятся только на машине владельца при исполнении фазы 1. Источник-факты
выше не переписаны; статус эмпирики указан явно по каждому пункту.

1. **Q1 (срок подписи/профиля) — RESOLVED FOR PLANNING:** обязательное измерение
   ПО КАЖДОМУ бинарю (app и appex; профиль, при отсутствии — фактическая
   NotAfter применимого сертификата подписи) заложено в verify-install.sh
   (01-03-T1, п. g + self-test) и в протокол наблюдений 01-04-T2; пересборка
   после фактического истечения — отдельный ограниченный план 01-05 (blocking
   checkpoint) с durable-протоколом ожидания в отдельном non-summary артефакте
   01-05-WAITING.json (существование *-SUMMARY.md движок исполнения трактует
   как завершение плана и пропустил бы отложенный checkpoint; итоговый
   01-05-SUMMARY.md — только после закрытия checkpoint); «на следующий день» —
   необязательное дополнение, не замена; отдельный файл
   {phase}-UAT.md не используется — доказательства живут в WAITING-протоколе
   и SUMMARY планов 01-04/01-05. Фаза не завершается до результата 01-05.
   Эмпирика: PENDING до первой сборки и фактического истечения.
2. **Q2 (автоподпись Xcode с App Groups на personal team) — RESOLVED FOR
   PLANNING:** обязательный blocking checkpoint первичной настройки (01-04-T1)
   плюс контракт явного блокера без обходов (Pitfall 7); фактическая команда
   и Team проверяются verify-install.sh по подписанным бинарям против
   независимой ожидаемой команды владельца (scripts/expected-team.local,
   01-03-T1, п. b — согласованная чужая команда отвергается), создаваемой
   владельцем из Xcode/аккаунта ДО первого вызова сборки (01-04-T1; не из
   подписи продукта и не из вывода verify-install.sh). Эмпирика:
   PENDING до фактической настройки владельцем.
3. **Q3 (квирки MenuBarExtra(.window)) — RESOLVED FOR PLANNING:** обоснованный
   перенос в research фазы 4 (граница фазы 4 в ROADMAP уже содержит проверку
   NSStatusItem/NSPopover как план Б); фазу 1 не блокирует — панель диагностическая,
   обновление по reload из приложения. Эмпирика: PENDING до фазы 4.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode | сборка, подпись, шаблон widget extension | ✗ (не установлен; активен CLT) | — | **Нет — BLOCKING**, ставит владелец из App Store |
| Apple ID + personal team в Xcode | подпись обеих целей | ✗ (0 identities) | — | **Нет — BLOCKING**, настраивает владелец (D-01) |
| Command Line Tools | `swift package`, `swiftc`, `swift test` | ✓ | 6.4.0 | — |
| `codesign` | проверка entitlements | ✓ | системный | — |
| `security` (cms) | декодирование профиля | ✓ | системный | — |
| `pluginkit` | проверка регистрации appex | ✓ | системный | — |
| `plutil` | чтение полей профиля/plist | ✓ | системный | — |
| `xcodebuild` | сборка | ✗ (требует Xcode) | — | Нет до установки Xcode |
| `~/Applications` | цель установки (D-02) | ✓ | — | — |

**Missing dependencies with no fallback:**
- Xcode (App Store, владелец) и настройка Apple ID/personal team — до них ни один шаг сборки не воспроизводим; в плане оформляются checkpoint:human-verify, не обходятся.

**Missing dependencies with fallback:**
- Нет: всё прочее уже на машине.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Нет тест-фреймворка продуктового кода в фазе 1 (Swift Testing войдёт с пакетом фазы 2). Приёмка = скрипты сборки/верификации + системные инструменты |
| Config file | none — см. Wave 0 |
| Quick run command | `bash scripts/verify-install.sh` (после первой успешной сборки) |
| Full suite command | `bash scripts/build.sh && bash scripts/verify-install.sh` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PLAT-01a | Сборка двух таргетов xcodebuild под personal team | build (авто) | `xcodebuild -project AiUsage.xcodeproj -scheme AiUsage -configuration Release build SYMROOT=…` | ❌ Wave 0 (scripts/build.sh) |
| PLAT-01b | Entitlements app: sandbox+network.client+group | unit-like (авто, <5с) | `codesign -d --entitlements - --xml <app>` + grep-проверки | ❌ Wave 0 (scripts/verify-install.sh) |
| PLAT-01c | Entitlements appex: sandbox+group, БЕЗ сети/Keychain | unit-like (авто) | `codesign -d --entitlements - --xml <appex>` + негативные grep | ❌ Wave 0 |
| PLAT-01d | Фактический срок профиля измерен и записан | наблюдение (авто-команда) | `security cms -D -i …/embedded.provisionprofile \| plutil -extract ExpirationDate raw -o - -` | ❌ Wave 0 |
| PLAT-01e | Запись app видима extension (тот же номер/время) | integration (авто-часть) | `cat ~/Library/Group Containers/<gid>/test-snapshot.json` + визуальное сравнение с панелью | ❌ Wave 0 |
| PLAT-01f | Appex зарегистрирован в системе | unit-like (авто) | `pluginkit -m -i <widget.bundle.id>` | ❌ Wave 0 |
| PLAT-01g | Виджет добавлен в Центр уведомлений, значения совпадают | manual-only | — GUI-операция владельца в Центре уведомлений; автоматизация NC отсутствует | — |
| PLAT-01h | Переустановка одной командой после истечения профиля; данные сохраняются | manual+auto | `bash scripts/build.sh` (повторный прогон) + cat JSON | ❌ Wave 0 |

Manual-only обоснование: добавление виджета и визуальная сверка — операции системного GUI; платформа не даёт API-контроля над Центром уведомлений. Автоматизируемая часть (01a–01f, 01h) покрывает подпись, права, регистрацию и данные.

### Sampling Rate
- **Per task commit:** `swift test` в Packages/UsageKit (работает на CLT) + shell-синтаксис скриптов.
- **Per wave merge:** full suite (build + verify-install) — требует уже настроенного Xcode.
- **Phase gate:** полный прогон 01a–01h на машине владельца + ручная 01g; вне Xcode-отладчика (реестр требований ROADMAP).

### Wave 0 Gaps
- [ ] `scripts/build.sh` — preflight (Pitfall 4), сборка, quit/replace/launch (D-01..D-04)
- [ ] `scripts/verify-install.sh` — команды 01b–01f
- [ ] `scripts/diagnostics.sh` — сбор диагностики без секретов (D-04)
- [ ] `Packages/UsageKit/` скелет с тривиальным типом записи и 1 тестом Swift Testing
- [ ] `docs/phase-01-setup.ru.md` — D-12-инструкция (пишется вместе с кодом, не Wave 0)

## Security Domain

> `security_enforcement: true`, ASVS level 1 (config.json). Применимо к фазе 1.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Нет аутентификации в фазе 1 |
| V3 Session Management | no | Нет сессий |
| V4 Access Control | yes (частично) | Изоляция таргетов: appex без network/Keychain-entitlements; app — единственный писатель контейнера; проверка через codesign |
| V5 Input Validation | yes | Типизированное декодирование JSON записи; 3 различимых состояния (D-07); невалидная запись ≠ дефолтные данные |
| V6 Cryptography | no | Криптографии в фазе нет; Keychain — фаза 3 |
| V14 Config/Logging | yes | Лог вне git, без секретов (D-04); team id/имя владельца в логах — персональные данные, не публиковать |

### Known Threat Patterns for macOS app+widget personal build

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Секреты/персональные данные в логе сборки (xcodebuild печатает идентичности с Apple ID) | Information Disclosure | Лог в `~/Library/Logs/` (вне git, discretion места), сокращённый вывод в терминал, никаких `set -x` в репо-скриптах |
| Расширение с избыточными правами | Elevation of Privilege | Минимальные entitlements appex + негативные codesign-проверки в приёмке |
| Рассинхрон/подмена App Group между таргетами | Tampering | Один литерал группы, сверка массивов application-groups из подписанных бинарей |
| Тихий обход sandbox/подписи «чтобы работало» | Repudiation (нарушение контракта фазы) | Явный блокер, human-verify; запрет ad-hoc/unsandboxed fallback (CONTEXT, Pitfall 7) |
| Повреждённая/чужая запись в общем контейнере | DoS (невалидный JSON рушит виджет) | Отказоустойчивое декодирование → состояние «нет записи», не краш и не подмена данных (D-07) |

## Sources

### Primary (HIGH — получены webfetch в этой сессии, 2026-10-11)
- developer.apple.com/help/account/reference/supported-capabilities-macos — таблица capabilities: App groups / App Sandbox / Keychain sharing = доступны free-тиру «Apple Developer»; значения ячеек извлечены из сырого HTML
- developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups (+ `.md`-версия) — форматы group id; macOS `<team-id>.<name>` без регистрации
- developer.apple.com/documentation/foundation/filemanager/containerurl(forsecurityapplicationgroupidentifier:) (+ `.md`) — путь Group Containers; non-nil семантика macOS; обязательная проверка доступа
- developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox (+ `.md`) — entitlements, сеть client, контейнеры ~/Library/Containers, Activity Monitor Sandbox
- developer.apple.com/documentation/widgetkit/creating-a-widget-extension (+ `.md`) — шаблон, StaticConfiguration, gallery-after-launch
- developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date (+ `.md`) — бюджет 40–70/сутки, exemption при foreground-app, reloadTimelines, coalescing, ≥5 мин
- developer.apple.com/documentation/swiftui/menubarextra (+ `.md`) — macOS 13+, .window, LSUIElement

### Secondary (MEDIUM)
- developer.apple.com/library/archive/technotes/tn2339 — xcodebuild паттерны (архив 2017; базовые флаги стабильны)
- AGENTS.md / STACK.md проекта — линейка Xcode 27/Swift 6.4 и квирки MenuBarExtra (внутренние; машинно не перепроверялись в части Xcode — он не установлен)

### Local authoritative (машина, 2026-10-11)
- `man codesign`, `man security`, `man pluginkit` (macOS 27.0.1); пробы из раздела Machine Facts (команды приведены)

### Tertiary (LOW — помечено к валидации)
- «7 дней» срока free-профиля: официального подтверждения не найдено; измерение на машине (A1)

## Metadata

**Confidence breakdown:**
- Platform APIs (WidgetKit, App Groups, sandbox, MenuBarExtra, containerURL): **HIGH** — официальная документация, получена и процитирована в этой сессии
- Signing/personal-team путь: **MEDIUM** — таблица capabilities официальная [VERIFIED], фактического прогона Xcode на машине нет (Xcode не установлен) → human-verify
- Machine facts: **HIGH** — команды и выводы зафиксированы с датой
- Profile expiry: **LOW** — Assumption A1, измерение заложено

**Research date:** 2026-10-11
**Valid until:** 2026-10-25 (или до установки Xcode — после неё перепробовать Machine Facts: версии Xcode/Swift, идентичности)
