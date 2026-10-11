<!-- GSD:project-start source:PROJECT.md -->

## Project

**ai-usage-macos-widget**

Нативное приложение macOS (SwiftUI + WidgetKit), которое показывает расход
подписочных лимитов AI-провайдеров — виджетом в Центре уведомлений и пунктом
в строке меню. Повторяет карточку LIMITS плагина DSH `@linxin666/dsh-usage`,
но независимо от кодинг-харнесса: работая в Kilo, DSH или другом клиенте,
владелец видит одни и те же цифры, потому что данные запрашиваются у
провайдеров напрямую.

**Core Value:** Работая в любом кодинг-агенте, в один взгляд видеть актуальный расход лимитов
подписок (OpenAI/Codex, Z.ai GLM, Kimi Code) и баланс OpenRouter — без
открывания веб-кабинетов провайдеров.

### Constraints

- **Tech stack**: SwiftUI + WidgetKit, SwiftPM; без тяжёлых сторонних
  зависимостей
- **Compatibility**: минимальная версия macOS 15 — свежие API WidgetKit,
  поддержка старых систем не нужна
- **Dependencies**: Xcode (владелец ставит из App Store) — без него виджет
  не собрать и не подписать
- **Security**: ключи только в Keychain; не попадают в git, логи,
  UserDefaults и код виджета
- **Platform**: обновления виджета по бюджету WidgetKit (~15–60 мин);
  частая проверка — только в строке меню и по ручному refresh
- **Distribution**: личная сборка с бесплатным Apple ID (personal team)

<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->

## Technology Stack

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Swift | 6.4 (stable) | Язык проекта | Текущий стабильный релиз swift.org («Install 6.4.0»), локально подтверждён: Command Line Tools машины = Apple Swift 6.4.0, target arm64-apple-macosx27.0.0. Xcode из App Store в той же линейке (Xcode 27) несёт ровно этот тулчейн — расхождений между CLI и IDE не будет. **Confidence: HIGH** (машинная проверка + swift.org) |
| Языковой режим Swift 6 + Approachable Concurrency | Swift 6 mode, `defaultIsolation MainActor` | Режим компиляции | Swift 6.2+ ввёл «Approachable Concurrency» (официальный блог swift.org): изоляция на MainActor по умолчанию, `@concurrent` для уходов в пул потоков. Для SwiftUI-приложения это дефолт новых проектов Xcode 26/27 и самый дешёвый способ получить data-race-safe код без ручных `@MainActor`. Альтернатива — ретро-режим Swift 5 — не нужна для greenfield. **Confidence: HIGH** (блог swift.org + release notes Xcode 26/27) |
| Xcode | 27.x (App Store) | IDE, SDK, подпись, сборка | Официальные релиз-ноты Apple: линейка Xcode 27 актуальна (27.0 → 27.1 → 27.2 beta); Xcode 26 включал Swift 6.2 и macOS 26 SDK, значит Xcode 27 = Swift 6.4 + macOS 27 SDK — совпадает с локальным CLT. Виджет extension нельзя собрать без Xcode (CLT не содержит WidgetKit-шаблоны, подпись и `xcodebuild` для appex). Без него проект не собирается — это зафиксировано в Constraints PROJECT.md. **Confidence: HIGH** |
| SwiftUI lifecycle (`App` protocol) | macOS 15+ | Каркас приложения | Штатный lifecycle для нового greenfield-приложения: `@main App` + сцены. AppKit lifecycle (NSApplicationDelegate + xib) устарел для новых проектов; AppDelegate-хук (`@NSApplicationDelegateAdaptor`) остаётся доступен для точечных нужд. **Confidence: HIGH** |
| SwiftUI `MenuBarExtra` | macOS 13+ (API), macOS 15+ (деплой) | Пункт в строке меню | Официальная документация SwiftUI: Scene «persistent control in the system menu bar». Стиль `.window` даёт popover-окно с произвольным SwiftUI-контентом (карточки лимитов, кнопка refresh) — ровно потребность проекта. `LSUIElement=true` скрывает приложение из Dock. Прямая замена ручному `NSStatusItem`. **Confidence: HIGH** |
| WidgetKit + Widget Extension target | macOS 11+ (фреймворк), iOS-стиль API | Виджет в Notification Center | Единственный способ получить виджет в Notification Center macOS. Подтверждено: WidgetKit доступен на macOS 11+, нативные виджеты Mac размещаются на desktop и в Notification Center. Обновления по таймлайнам с бюджетом системы (см. ниже). **Confidence: HIGH** |
| Deployment target | macOS 15.0 | Минимальная версия ОС | Зафиксировано в Constraints PROJECT.md: свежие WidgetKit API, поддержка старых систем не нужна. Xcode 27 собирает с deployment target macOS 15 без оговорок (стандартная поддержка нескольких версий назад). **Confidence: HIGH** |
| Foundation `URLSession` (async/await) + `Codable` | в составе SDK | HTTP к провайдерам | Штатный URL loading system; Apple в статье «Making network requests in a widget extension» прямо рекомендует URLSession для виджетов. Современный API: `URLSession.data(for:)` с async/await. Для четырёх JSON-эндпоинтов (OpenAI wham/usage, Kimi coding usages, Z.ai plan, OpenRouter credits) этого достаточно — библиотеки вроде Alamofire не нужны. **Confidence: HIGH** |
| Security.framework Keychain Services | в составе SDK | Хранение API-токенов | Официальный механизм «small chunks of data securely»: `SecItemAdd` / `SecItemCopyMatching` / `SecItemUpdate` с `kSecClassGenericPassword`, `kSecAttrService`, `kSecAttrAccount`. Первая-party Swift-обёртки нет — пишем свой компактный враппер (~100 строк), это нормальная практика. **Confidence: HIGH** (символ kSecClassGenericPassword подтверждён в докам; API стабилен много лет) |
| SwiftPM (локальный пакет) | swift-tools-version 6.x | Общий код app + widget | Штатный менеджер зависимостей. Локальный пакет `Packages/UsageKit` в репо, его library product линкуется в оба таргета — стандартный паттерн для кода, разделяемого между app и extension. `swift package init` из CLI работает без Xcode (проверено машинно). **Confidence: HIGH** |

### Project Structure (Xcode targets)

- Таргет виджета создаётся штатно: **File > New > Target > Application Extension > Widget Extension** (подтверждено официальной статьёй «Creating a widget extension»); Xcode сам встраивает appex в `App.app/Contents/PlugIns` и настраивает Embed.
- Один extension с `WidgetBundle`: несколько видов виджетов (small/medium) живут в одном appex — Apple рекомендует именно так.
- App-таргет в Info.plist: `LSUIElement = true` (agent-приложение без Dock-иконки; подтверждено доками MenuBarExtra).
- Сборка из CLI: `xcodebuild -project AiUsage.xcodeproj -scheme AiUsage -configuration Debug build` (после установки Xcode и `xcode-select -s /Applications/Xcode.app`). **Confidence: HIGH** (шаблонная структура Apple; MEDIUM только в деталях имён фаз сборки)

### Entitlements (критично для виджета с сетью)

| Entitlement | App target | Widget target | Зачем |
|-------------|-----------|---------------|-------|
| `com.apple.security.app-sandbox` = true | да | да | Обязательная база песочницы macOS |
| `com.apple.security.network.client` = true | да | **да, если виджет сам ходит в сеть** | «Outgoing Connections (Client)»: право открывать исходящие соединения. Без него в таргете виджета любой URLSession-запрос из `getTimeline` упадёт с sandbox-ошибкой — это и есть ответ на вопрос «какие entitlements нужны виджету для своих сетевых запросов»: **свой App Sandbox + свой network.client в entitlements extension-таргета** |
| `com.apple.security.application-groups` = `[<TEAMID>.group.aiusage]` | да | да | Общий контейнер для кэша последнего опроса (JSON + timestamp), который виджет читает и показывает с возрастом. Имя группы с префиксом Team ID — безопасный вариант для personal team. **Confidence: MEDIUM** (механизм подтверждён доками; поведение с бесплатным personal team при локальной подписи — проверить в фазе настройки таргетов) |
| `keychain-access-groups` | только если виджет читает ключи сам | только если виджет читает ключи сам | Шэринг keychain-элементов между таргетами требует общего access group `$(AppIdentifierPrefix)<group>` в обоих таргетах (официальная статья «Configuring keychain sharing»). **Проекту не нужен по умолчанию**: требование PROJECT.md — виджет показывает кэш и возраст, ключи остаются в app-таргете. Включать только если решим, что виджет сам ходит в провайдеры |

### WidgetKit факты, влияющие на дизайн (все — официальная документация «Keeping a widget up to date»)

- Виджет рендерится в **отдельном процессе** и не активен постоянно.
- **Бюджет обновлений**: для часто просматриваемого виджета 40–70 refresh/сутки ≈ раз в 15–60 минут; обновления в момент, когда app на переднем плане, не расходуют бюджет. Это совпадает с зафиксированным в PROJECT.md ограничением ~15–60 мин.
- Записи таймлайна — не ближе ~5 минут друг к другу.
- Политики `TimelineReloadPolicy`: `.atEnd` (после последней записи), `.after(date)` (в конкретный момент), `.never` (только по `WidgetCenter.shared.reloadTimelines(ofKind:)` из app).
- Ручной refresh в меню-баре: app делает запрос и вызывает `WidgetCenter.shared.reloadTimelines` — бесплатно вне бюджета виджета. **Confidence: HIGH**

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| — (нет) | — | Внешние зависимости не нужны | URLSession + Codable + Security + WidgetKit покрывают 100% требований проекта. Ограничение «без тяжёлых сторонних зависимостей» соблюдается нулевой зависимостью |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Xcode 27 из App Store | Сборка, шаблоны, подпись | Владелец ставит сам (Constraints). После установки: `xcode-select -s /Applications/Xcode.app`, иначе `xcodebuild` продолжает указывать на CLT (сейчас на машине так) |
| `xcodebuild` | CLI-сборка, автоматизация | Схемы: `AiUsage` (app+widget), `AiUsageWidget` при необходимости |
| Swift Testing (`@Test`, `#expect`) | Юнит-тесты UsageKit | Стандарт тестов на Swift 6 (Xcode 26+ release notes: Swift Testing развивается, XCTest — легаси). Тестировать адаптеры парсинга JSON — дёшево и полезно |
| Xcode Previews | Разработка виджета | Официальный способ итерировать виджет без запуска app (статья «Previewing widgets and Live Activities in Xcode») |
| `swift package` | Работа с UsageKit | Тесты пакета гоняются даже без Xcode: `swift test` в `Packages/UsageKit` (проверено: CLT умеет SwiftPM) |

## Installation

# 1. Xcode — только из App Store (руками владельца), затем:

# 2. Проверка тулчейна (ожидается Apple Swift version 6.4):

# 3. Внешних зависимостей НЕТ — ничего ставить не нужно.

#    Локальный пакет общий для таргетов:

# 4. Сборка всего приложения с виджетом:

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| `MenuBarExtra` (.window) | `NSStatusItem` + `NSPopover` (AppKit) | Если упрёмся в известные шероховатости MenuBarExtra .window (контент popover-окна не всегда перерисовывается при переоткрытии; лечится `TimelineView`/пересозданием) — тогда AppKit даёт полный контроль. Держать как план Б, не как старт. **Confidence: MEDIUM** (квирки — консенсус сообщества, не официальная документация) |
| Собственный враппер SecItem (~100 строк) | Сторонние обёртки (KeychainAccess, SwiftKeychainWrapper) | Только если враппер начнёт обрастать кейсами (биометрия, iCloud keychain) — не наш случай. Для 4 токенов свой враппер проще и снимает зависимость |
| `URLSession` async/await | Alamofire / Auvo / Get | Почти никогда для этого проекта: 4 простых JSON GET/POST с Bearer-заголовком. Библиотека добавила бы зависимость ради нуля ценности |
| Виджет читает App Group кэш | Виджет сам ходит в сеть с ключами из keychain | Только если кэш-схема окажется недостаточно свежей: тогда виджету нужны network.client + keychain-access-groups, но бюджет WidgetKit всё равно ограничит частоту — выигрыш небольшой |
| Свой `Observable`-класс (`@Observable`, Swift Observation) | Combine (`ObservableObject`/`@Published`) | Никогда для нового кода: Observation — современный подход Swift 5.9+/6, Combine остаётся для реактивных стримов (таймеры-издатели), если понадобятся |
| SwiftUI lifecycle | AppKit NSApplication lifecycle | Никогда для greenfield; AppDelegate-хук через `@NSApplicationDelegateAdaptor` закрывает редкие потребности |
| Sparkle-обновления | — | Не нужен: личная сборка без нотаризации, обновление = git pull + сборка (Out of Scope PROJECT.md) |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Alamofire и другие HTTP-библиотеки | Зависимость ради 4 JSON-запросов; тащит версии/совместимость в оба таргета | `URLSession.data(for:)` + `Codable` |
| Хранение ключей в UserDefaults / plist / коде | Прямое нарушение Security-требования PROJECT.md; UserDefaults читается любым процессом пользователя | Keychain (SecItem, kSecClassGenericPassword) |
| Обёртки KeychainAccess/KeychainSwift | Третья сторона ради ~100 строк своего кода; усложняет аудит для публичного репо | Собственный компактный враппер в UsageKit |
| Поминутный таймер в виджете / background URLSession для маленьких JSON | Таймеров вне таймлайна WidgetKit не существует (процесс останавливается); background URLSession избыточно сложен (onBackgroundURLSessionEvents, делегаты) для пары килобайт | Таймлайны + `.after(_:)` + кэш в App Group; ручной refresh из меню-бара |
| `.menu`-стиль MenuBarExtra как основной UI карточек | Стиль .menu — только список пунктов-действий, не произвольный контент | `.window`-стиль (popover с SwiftUI-карточками), `.menu` — для коротких действий |
| Electron / Tauri / кроссплатформа | Виджеты Notification Center — исключительно WidgetKit; обёртки не дают доступа | Нативный Swift + WidgetKit (зафиксировано в PROJECT.md) |
| XCTest для новых тестов | Легаси-фреймворк; Swift Testing — текущий стандарт (быстрее, проще, `#expect`) | Swift Testing |
| Прямое чтение кэша виджетом из контейнера app (`~/Library/Containers/<app>`) | Песочница виджета — другой контейнер; доступ будет запрещён | App Group контейнер: `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` |

## Stack Patterns by Variant

- Widget target: `app-sandbox` + `application-groups`, БЕЗ `network.client`
- App target: `app-sandbox` + `network.client` + `application-groups`
- Минимум поверхности атаки и простая отладка
- Widget target дополнительно: `network.client` (+ `keychain-access-groups` при чтении ключей)
- Учитывать: запрос из `getTimeline` могут оборвать; бюджет всё равно ~15–60 мин
- Начинать с кэш-схемы, добавлять только при доказанной потребности
- Fallback: `NSStatusItem` + `NSPopover` + `NSStatusItem.button`
- Потому что AppKit-путь даёт полный контроль над жизненным циклом окна ценой boilerplate

## Version Compatibility

| Component | Compatible With | Notes |
|-----------|-----------------|-------|
| Xcode 27.x | Swift 6.4, macOS 27 SDK | Текущая App Store-линейка (релиз-ноты: 27.0 / 27.1 / 27.2 beta) |
| Xcode 26.x | Swift 6.2–6.3, macOS 26 SDK | Работоспособная замена, если владелец не обновится; код на Swift 6 mode совместим вниз |
| Deployment target macOS 15 | Собирается Xcode 26 и 27 | Ограничения PROJECT.md соблюдены |
| WidgetKit API проекта | macOS 15+ | Таймлайны/бюджет/`WidgetCenter` доступны с macOS 11–14; macOS 15+ даёт свежие API без deprecation-оговорок |
| Swift 6 language mode | Swift 6.0–6.4 тулчейны | Mode не меняется между минорными версиями; Approachable Concurrency-настройки (`defaultIsolation MainActor`) доступны с Xcode 26 |

## Sources

- swift.org — «Install Swift / macOS»: текущий стабильный Swift 6.4.0, список прошлых релизов — https://www.swift.org/install/macos/ (Confidence: HIGH, кросс-проверено локальным `swift --version`)
- swift.org — блог «Swift 6.2 Released»: Approachable Concurrency, default MainActor isolation, `@concurrent`, Swift Testing — https://www.swift.org/blog/swift-6.2-released/ (Confidence: HIGH)
- Apple — «Xcode Release Notes» (индекс): линейка Xcode 27 актуальна, Xcode 26 включает Swift 6.2 и macOS 26 SDK — https://developer.apple.com/documentation/xcode-release-notes (Confidence: HIGH)
- Apple — «Configuring the macOS App Sandbox»: app-sandbox, network.client, entitlements на таргет, контейнеры — https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox (Confidence: HIGH)
- Apple — «Keeping a widget up to date»: бюджет 40–70 refresh/сутки ≈ 15–60 мин, TimelineReloadPolicy, WidgetCenter — https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date (Confidence: HIGH)
- Apple — «Making network requests in a widget extension»: URLSession в виджете, ограничения времени жизни extension — https://developer.apple.com/documentation/widgetkit/making-network-requests-in-a-widget-extension (Confidence: HIGH)
- Apple — «Creating a widget extension»: шаблон File > New > Target > Widget Extension, WidgetBundle — https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension (Confidence: HIGH)
- Apple — SwiftUI «MenuBarExtra»: macOS 13+, стили .menu/.window, LSUIElement — https://developer.apple.com/documentation/swiftui/menubarextra (Confidence: HIGH)
- Apple — «Keychain services» (коллекция Security) и символ kSecClassGenericPassword — https://developer.apple.com/documentation/security/keychain-services (Confidence: HIGH для API; MEDIUM для поведения keychain-access-groups с personal team — проверить в фазе)
- Apple — «Configuring keychain sharing», «Accessing app group containers» (см. also-ссылки статьи App Sandbox) — Confidence: MEDIUM (не открывались отдельно, известны по ссылкам официального индекса; поведение с бесплатным Apple ID — флаг для фазы настройки таргетов)

<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->

## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->

## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->

## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->

## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-fast` for a trivial task inline, with no subagents and no PLAN.md
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->

## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
