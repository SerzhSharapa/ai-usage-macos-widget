# Phase 1: Каркас Xcode и личная подпись - Pattern Map

**Mapped:** 2026-10-11
**Files analyzed:** 16 (все — новые, создаваемые в фазе)
**Analogs found:** 0 / 16 — проект greenfield

## Честное ограничение: аналогов в кодовой базе НЕТ

`git ls-files` (проба 2026-10-11) показывает только `.md`-документы, `LICENSE`
и planning-артефакты. В репозитории **нет ни одного** Swift-исходника,
`.pbxproj`, `.plist`, `.entitlements` или shell-скрипта. Специализированного
поиска не требуется: классификация по Glob/Grep невозможна и не проводилась.

Все «паттерны» ниже взяты **из `01-RESEARCH.md`** — это цитаты официальной
документации developer.apple.com (fetched 2026-10-11) и man-страниц этой
машины, а НЕ существующий код проекта. Планировщик должен воспринимать их как
референсные шаблоны для новых файлов, не как «скопировать из кодовой базы».

Дополнительно: команды верификации из RESEARCH.md (codesign, security cms,
pluginkit) подтверждены как **присутствующие на машине**, но их корректный
вывод на собранных продуктах — не доказан (Xcode не установлен, сборки нет).
Это шаблоны команд, не свидетельства работающей установки.

## Locked Decisions (D-01…D-12 — неизменны, источник: 01-CONTEXT.md)

Планировщик обязан сохранить дословно:

- **D-01:** повторная сборка/установка одной командой; сценарий проверяет готовность Xcode, собирает `xcodebuild`.
- **D-02:** установка в `~/Applications`, без прав администратора, запуск вне Xcode.
- **D-03:** повторный вызов = согласие на автозакрытие текущего экземпляра, замену и запуск; данные не очищаются, чужое не затрагивается.
- **D-04:** в терминале — краткая причина и следующий шаг; подробный лог вне git; секретов в логе нет.
- **D-05:** тестовый пункт в строке меню с диагностической панелью; без Dock-иконки; не реализация MENU-01/MENU-02 фазы 4.
- **D-06:** кнопка пишет номер проверки + время в App Group; виджет показывает те же значения с пометкой теста; результат доказывает чтение записи приложения, не встроенного примера.
- **D-07:** «нет записи» и «ошибка доступа к контейнеру» — разные состояния; без записи — предложение открыть приложение; встроенные данные не подставляются.
- **D-08:** в фазе 1 только `systemSmall`; продуктовые размеры — фаза 5.
- **D-09:** имя приложения в Finder: `AI Usage Widget`.
- **D-10:** кнопки и сообщения каркаса на русском; локализация не входит.
- **D-11:** имя виджета в галерее: `AI Usage Widget - Тест`; описание про проверку общей папки; пометка снимается в продуктовых фазах.
- **D-12:** подробная инструкция на русском: Apple ID, подпись, widget extension, общий контейнер, команды, ожидания, действия при ошибках; пункты Xcode как в интерфейсе.

Граница объёма: **только платформенное доказательство (PLAT-01)** — macOS 15+,
app + WidgetKit extension, подпись personal team, App Group, работа вне Xcode.
Виджет — read-only: без сети и без Keychain. Продуктовые адаптеры, контракт
UsageCore, ключи, карточки лимитов, фоновый опрос, интерактивное обновление —
вне фазы; тестовый снимок НЕ фиксирует контракт фазы 2.

## File Classification

| Новый файл | Роль | Data Flow | Ближайший аналог | Match |
|------------|------|-----------|------------------|-------|
| `AiUsage.xcodeproj` (2 таргета: app, appex) | config/build | — | нет — greenfield | none |
| `Packages/UsageKit/Package.swift` | config (SwiftPM) | — | нет | none |
| `Packages/UsageKit/Sources/UsageKit/TestRecord.swift` | model | transform (Codable JSON) | нет — шаблон из RESEARCH | none |
| `Packages/UsageKit/Tests/.../TestRecordTests.swift` | test | — | нет (Swift Testing, фаза 1 — 1 тривиальный тест) | none |
| `AiUsage/AiUsageApp.swift` | app entry (SwiftUI `App`) | event-driven | нет — шаблон RESEARCH Pattern «Меню-бар каркас» | none |
| `AiUsage/TestPanelView.swift` | component (SwiftUI) | request-response (кнопка→запись) | нет | none |
| `AiUsage/TestRecordStore.swift` | service | file-I/O (App Group, атомарная запись) | нет — шаблон RESEARCH Pattern 3 | none |
| `AiUsage/Info.plist` (+ LSUIElement=true) | config | — | нет | none |
| `AiUsage/AiUsage.entitlements` (sandbox + network.client + app-groups) | config | — | нет | none |
| `Widget/TestWidgetBundle.swift` | app entry (WidgetBundle) | — | нет | none |
| `Widget/TestWidget.swift` (StaticConfiguration, `.systemSmall`) | component (WidgetKit) | — | нет — шаблон RESEARCH Pattern 4 | none |
| `Widget/TestWidgetProvider.swift` (TimelineProvider, 3 состояния D-07) | provider | file-I/O (только чтение) | нет | none |
| `Widget/Info.plist` + `Widget/AiUsageWidget.entitlements` (sandbox + app-groups, БЕЗ network/Keychain) | config | — | нет | none |
| `scripts/build.sh` | utility/build (preflight→build→quit→replace→launch→лог) | batch | нет — псевдокод RESEARCH Pattern 2 | none |
| `scripts/verify-install.sh` | utility/verification (codesign×2, profile, pluginkit, контейнер) | batch | нет — команды RESEARCH «Верификационные команды» | none |
| `scripts/diagnostics.sh` | utility/diagnostics (без секретов, D-04) | batch | нет | none |
| `docs/phase-01-setup.ru.md` | documentation (D-12) | — | нет | none |

Ни один файл не имеет аналога: оценка «none» для всех — честный результат, а не
пробел анализа. Планировщик строит план на RESEARCH-паттернах ниже.

## Pattern Assignments (источник всехexcerpt'ов — 01-RESEARCH.md, не кодовая база)

### `AiUsageApp.swift` + `TestPanelView.swift` (app entry / component, D-05, D-10)

**Источник:** RESEARCH, Code Examples «Меню-бар каркас» — цитата developer.apple.com/documentation/swiftui/menubarextra:

```swift
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

### `TestRecordStore.swift` (service, file-I/O, D-06/D-07)

**Источник:** RESEARCH, Pattern 3 + Code Examples «Запись тестового снимка» — цитата containerURL-документации Apple («URL ожидаемой формы возвращается всегда, даже для неверной группы — проверяйте доступ к каталогу перед использованием»):

```swift
let groupID = "<TEAMID>.group.aiusage"             // литерал из entitlements; discretion планировщика
guard let dir = FileManager.default
    .containerURL(forSecurityApplicationGroupIdentifier: groupID) else { /* на macOS недостижимо */ }
// ОБЯЗАТЕЛЬНО: фактическая проверка доступа (создание каталога/временного файла),
// иначе состояние «ошибка доступа к контейнеру» (D-07)
// запись: временный файл + rename (атомарно) — JSON {номер: Int, recordedAt: Date}
WidgetCenter.shared.reloadTimelines(ofKind: testWidgetKind)  // из app; при активном app бюджет не тратится
```

Три состояния провайдера/вью (D-07): (1) запись прочитана и декодирована →
номер+время с пометкой «Тест»; (2) файла нет / не декодируется → «откройте
приложение и запишите тест», без подстановки данных; (3) каталог недоступен →
отдельное состояние «проблема контейнера».

### `TestWidgetBundle.swift` + `TestWidget.swift` + `TestWidgetProvider.swift` (widget, D-06/D-08/D-11)

**Источник:** RESEARCH, Code Examples «Виджет» — цитата creating-a-widget-extension:

```swift
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

Extension **только читает** контейнер; writer один — app (Anti-Pattern:
дублирование записи в extension). Никакой сети и Keychain в extension-коде.

### `scripts/build.sh` (utility, batch, D-01–D-04)

**Источник:** RESEARCH, Pattern 2 — псевдокод потока (не реализация):

```
preflight: xcode-select -p == /Applications/Xcode.app/Contents/Developer?
           xcodebuild -version ок?  identity Apple Development есть?   → иначе: краткая причина + следующий шаг, полный лог в файл вне git (D-04)
build:     xcodebuild -project AiUsage.xcodeproj -scheme AiUsage -configuration Release build
           (SYMROOT — верифицированный флаг [CITED: TN2339]; -derivedDataPath — [ASSUMED] A3)
quit:      osascript -e 'quit app "AI Usage Widget"'; fallback — pkill ПО ТОЧНОМУ пути бандла (D-03)
replace:   старый бандл → ~/.Trash («в Корзину, не rm»), новый → ~/Applications/ (D-02)
launch:    open ~/Applications/"AI Usage Widget.app"   (обязателен — Pitfall 2)
```

### `scripts/verify-install.sh` (verification, PLAT-01b–01f)

**Источник:** RESEARCH, «Верификационные команды приёмки» — шаблоны команд,
проверка факта только по подписанным бинарям (Pitfall 3):

```bash
APP=~/Applications/"AI Usage Widget.app"
codesign -d --entitlements - --xml "$APP"
codesign -d --entitlements - --xml "$APP/Contents/PlugIns/"*.appex
#    app:     app-sandbox=true, network.client=true, application-groups=[<gid>]
#    appex:   app-sandbox=true, application-groups=[тот же <gid>], НЕТ network.*, НЕТ keychain*
codesign -vvv --deep "$APP"
security cms -D -i "$APP/Contents/embedded.provisionprofile" | plutil -extract ExpirationDate raw -o - -
pluginkit -m -i <widget.bundle.id>
cat ~/Library/Group\ Containers/<TEAMID>.group.aiusage/test-snapshot.json
```

Ограничение: команды — паттерны из man-страниц этой машины; корректный вывод
на реальной сборке появится только после установки Xcode (человеческий шаг,
D-01). Не считать этот список доказательством установленного приложения.

### `docs/phase-01-setup.ru.md` (documentation, D-12)

**Источник:** RESEARCH, Pattern 1 — шаги первичной настройки как в интерфейсе
Xcode: Settings > Accounts; Signing & Capabilities («Automatically manage
signing», Team) отдельно для обоих таргетов; + Capability: App Sandbox (оба),
Outgoing Connections (Client, только app), App Groups (оба, одна группа).
Плюс ожидания reload: «секунды, не мгновенно; срок не гарантирован» (Pitfall 9).

## Shared Patterns

### Изоляция таргетов (критично, применяется ко всем конфигам)
- App: `app-sandbox` + `network.client` + `application-groups`.
- Widget appex: `app-sandbox` + `application-groups`, **БЕЗ** `network.*` и
  `keychain*` (Pitfall 5; негативные codesign-проверки в verify-install.sh).
- App Group — один литерал в обоих `.entitlements`; verify-скрипт сверяет
  массивы application-groups из подписанных бинарей (Pitfall 6).
- Bundle id не менять между сборками — иначе добавленный виджет отвяжется
  (Runtime State Inventory).

### Точность данных и логов (D-04, D-07)
- Лог сборки вне git (например `~/Library/Logs/`, discretion), без `set -x` в
  репо-скриптах, без секретов и персональных данных (Security Domain).
- Ошибки: краткая причина + следующий шаг в терминал, детали — в лог.

### Anti-Patterns (все из RESEARCH)
- nil-check контейнера на macOS вместо проверки доступа (Pitfall 1).
- Проверка entitlements «по чекбоксам» вместо codesign бинарей (Pitfall 3).
- Тихий fallback подписи (ad-hoc/unsandboxed) при отказе App Groups — запрещён,
  только явный блокер (Pitfall 7).
- pkill по подстроке / `rm -rf` старого бандла (Pitfall 8; домашнее правило —
  Корзина).

## No Analog Found

Все 16 файлов — см. таблицу File Classification. Причина единая: greenfield,
первая кодовая фаза проекта. Планировщик использует разделы RESEARCH.md
(Patterns 1–4, Code Examples, Validation Architecture Wave 0) вместо аналогов.

## Вопрос имени пакета: UsageKit vs UsageCore

- RESEARCH.md рекомендует для фазы 1 `Packages/UsageKit` (тривиальный тип
  `TestRecord`, комментарий «не контракт фазы 2»), переименование — фаза 2.
- ROADMAP фаза 2 называет пакет `UsageCore`.
- Ограничение задачи: избегать лишнего переименования UsageKit→UsageCore.
- Оба имени допустимы, выбор — **discretion планировщика**: если он сразу
  назовёт пакет `UsageCore`, переименования не будет вовсе (фаза 1 не
  фиксирует продуктовый контракт — имя пакета контрактом не является).
  Паттерны выше от имени пакета не зависят.

## Metadata

**Analog search scope:** весь репозиторий (подтверждено `git ls-files`:
0 Swift/`pbxproj`/plist/entitlements/скриптов).
**Files scanned:** 18 tracked файлов — все документация/planning.
**Pattern extraction date:** 2026-10-11.
**Источники excerpt'ов:** исключительно `01-RESEARCH.md` (цитаты
developer.apple.com fetched 2026-10-11, man-страницы macOS 27.0.1);
RESEARCH.md — единственный источник паттернов, ни один excerpt не является
существующим кодом проекта.
