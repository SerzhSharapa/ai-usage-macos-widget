# Project Research Summary

**Project:** ai-usage-macos-widget
**Domain:** Нативное macOS-приложение (меню-бар + виджет Notification Center) — расход лимитов AI-подписок (Codex/OpenAI, Kimi Code, Z.ai GLM, баланс OpenRouter)
**Researched:** 2026-10-11
**Confidence:** HIGH

## Executive Summary

Это нативное macOS-приложение-компаньон из двух таргетов: постоянно живущий агент строки меню (SwiftUI `MenuBarExtra`, `LSUIElement`) и WidgetKit-виджет Notification Center. Эксперты строят такие продукты именно так: приложение — единственный владелец сети, секретов и планировщика; виджет — «тонкий» потребитель, читающий подготовленный снимок из общего App Group контейнера. Все четыре эндпоинта провайдеров известны и проверены машинно по локальному референсу `@linxin666/dsh-usage` (11.10.2026) и независимо подтверждены в CodexBar — состав данных и парсеры не требуют изысканий, это перенос проверенной логики на Swift.

Рекомендуемый подход: Swift 6.4 + Xcode 27, SwiftUI lifecycle, локальный SwiftPM-пакет UsageCore (модели + адаптеры + SnapshotStore) без единой внешней зависимости; URLSession+Codable, Keychain (`kSecUseDataProtectionKeychain`, только в app-процессе), App Group контейнер как единственный канал данных в виджет, `WidgetCenter.reloadTimelines` только по факту изменения данных. Сборка в порядке «горизонтальных слоёв»: UsageCore → адаптеры → меню-бар (уже полезный продукт) → виджет → сборка и полировка.

Ключевые риски и их гашение: (1) бюджет WidgetKit 40–70 reload/сутки нельзя принимать за гарантию свежести — данные всегда несут `fetchedAt`, возраст и countdown рендерятся динамическими датами бесплатно; (2) OAuth-токен Codex протухает, а refresh параллельно с Codex CLI разлогинивает пользователя — позиция read-only, 401 → внятная подсказка; (3) схемы ответов дрейфуют — лёгкие парсеры (строки вместо enum, опциональные окна, ключи окон по смыслу полей) + фикстуры; (4) бесплатная личная подпись: ~7-дневные профили, team-префикс App Group, ограниченные capabilities — скрипт пересборки одной командой с Ф-0 и честный README.

## Key Findings

### Recommended Stack

См. [STACK.md](STACK.md). Стек минимален и полностью на официальной документации Apple/swift.org: Swift 6.4 (подтверждён локально на машине владельца), Xcode 27, Swift 6 language mode с Approachable Concurrency (`defaultIsolation MainActor`), deployment target macOS 15. Внешних зависимостей нет — URLSession/Codable, Security.framework (свой ~100-строчный враппер SecItem), WidgetKit покрывают все требования.

**Core technologies:**
- Swift 6.4 + Xcode 27: язык и тулчейн — стабильная линейка, машинно проверена; виджет-таргет без Xcode не собирается
- SwiftUI `MenuBarExtra` (`.window`): пункт строки меню с popover-карточками; `LSUIElement=true` — агент без Dock
- WidgetKit + Widget Extension: единственный путь в Notification Center; бюджет 40–70 обновлений/сутки (~15–60 мин)
- Foundation URLSession (async/await) + Codable: 4 простых JSON-эндпоинта — HTTP-библиотеки не нужны
- Keychain Services (`kSecClassGenericPassword`, data-protection keychain): хранение 4 токенов, только app-процесс
- Локальный SwiftPM-пакет UsageCore: общий код обоих таргетов, тестируется `swift test` без Xcode
- Swift Testing (`@Test`/`#expect`): юнит-тесты адаптеров и парсеров (XCTest — легаси)

### Expected Features

См. [FEATURES.md](FEATURES.md). Категория сверена по 6 продуктам (ccusage, Claude-Code-Usage-Monitor, CodexBar, Brink, AIQuota, Stats) и локальному референсу dsh-usage. Ниша проекта — ровно 4 провайдера владельца по прямому API, без cookie-скрейпинга и чужих keychain-записей.

**Must have (table stakes):**
- Проценты по каждому окну лимита (5h/week/month) + время сброса с живым обратным отсчётом
- Dropdown строки меню: провайдер → окна → баланс OpenRouter → возраст данных; ручной Refresh
- Фоновый опрос с настраиваемым интервалом (дефолт 5–15 мин) в приложении
- Кэш последнего успеха + возраст («обновлено N мин назад»); ошибка ≠ 0% (снимок не затирается, ошибка — отдельным слотом)
- Ключи только в Keychain; Launch at login; скрытие неподключённых провайдеров; цветовая шкала 70/90%
- Виджет NC (small+medium) с гейджами и живым countdown (`Text(timerInterval:)` — не тратит бюджет)
- Баланс OpenRouter в USD как деньги (`total_credits − total_usage`), отдельно от окон планов
- Сборка из исходников по инструкции — владелец не программист, путь сборки часть продукта

**Should have (competitive):**
- Кнопка Refresh прямо в виджете (App Intent — исключение из бюджета WidgetKit)
- Пороговые уведомления (80%) + уведомление о сбросе (scheduled, `UNUserNotificationCenter`)
- Прогноз опустошения окна без истории (percent ÷ доля прошедшего окна, после ~15% elapsed)
- Порядок «худшее окно сверху» + компактный текст иконки меню-бара

**Defer (v2+):**
- История/burndown-графики (требует склада снапшотов; интерфейс кэша заложить под расширение)
- Новые провайдеры по `ProviderAdapter`-протоколу (DeepSeek, MiniMax — парсеры есть в референсе)
- Дополнительные семейства виджетов; iOS — отдельный проект

**Anti-features (осознанно НЕ):** поминутное автообновление виджета (невозможно по бюджету), cost-tracking по прайсбукам, чтение транскриптов CLI, cookie/скрейпинг, мультиаккаунт, каталог десятков провайдеров, телеметрия.

### Architecture Approach

См. [ARCHITECTURE.md](ARCHITECTURE.md). Горизонтальные слои: L1 Platform (URLSession/Keychain/App Group/WidgetCenter) → L2 Domain (пакет UsageCore: модели, адаптеры-парсеры, SnapshotStore с атомарной записью) → L3 Application (ProbeScheduler, RefreshCoordinator, KeychainStore) → L4 Presentation (две тонкие оболочки: меню-бар и виджет, каждая в своём процессе). Главный архитектурный узел: виджет — отдельный процесс без сети и Keychain; единственные каналы — App Group контейнер (данные) и `reloadTimelines` (сигнал). Снимок пишется атомарно (tmp+rename), несёт `fetchedAt`, и никогда не затирается ошибкой.

**Major components:**
1. UsageCore (SwiftPM) — модели `UsageSnapshot`, 4 адаптера `ProviderAdapter` (parse-only, чистые функции над Data), SnapshotStore
2. App target — MenuBarExtra-агент: ProbeScheduler (Task-цикл), RefreshCoordinator, Settings + KeychainStore, ручной refresh
3. Widget target — WidgetBundle + TimelineProvider: читает только контейнер, placeholder/stale/age-состояния, политика `.after(+30 мин)`
4. Entitlements как файлы первого класса — app: sandbox+network.client+app-group; widget: sandbox+app-group (без сети, без keychain)

### Critical Pitfalls

См. [PITFALLS.md](PITFALLS.md) — там полная таблица с фазами и приёмкой.

1. **Бюджет WidgetKit ≠ гарантия свежести** — в отладчике бюджет не действует; проектировать «снимок + возраст», countdown динамическими датами, `reloadTimelines` только по изменению данных, приёмку виджета проводить вне Xcode.
2. **Протухший OAuth Codex / гонка refresh-токена** — read-only позиция: никогда не вызывать refresh и не писать `auth.json`; 401 → отдельное состояние «запустите codex / вставьте свежий токен»; свежесть оценивать по JWT `exp`.
3. **Жёсткое Codable-декодирование ломается schema drift'ом** — строки вместо enum, все окна опциональны, ключ окна по смыслу поля (`unit`/`duration`/`limit_window_seconds`), фикстуры реальных ответов с первого дня.
4. **Keychain после переподписи** — `kSecUseDataProtectionKeychain: true` во всех запросах с первого дня; виджет вообще без Keychain; `kSecAttrAccessible` не лечит ACL-несовпадения.
5. **Бесплатная личная команда** — только App Sandbox + App Groups; App Group id создаёт Xcode с team-префиксом; профили живут ~7 дней → скрипт пересборки одной командой и честный README; entitlements обоих таргетов сверять `codesign -d --entitlements :-`.
6. **Z.ai-диалект** — два происхождения (`api.z.ai` / `open.bigmodel.cn`, ключи несовместимы), «голый» ключ без Bearer, `TIME_LIMIT` не является окном, смешанные форматы времени (epoch s/ms / ISO) — единый нормализатор.

## Implications for Roadmap

На основе совмещённых исследований (build order из ARCHITECTURE.md + фазы Ф-0…Ф-5 из PITFALLS.md + зависимости из FEATURES.md):

### Phase 1: Каркас и подпись (Xcode targets, entitlements, сборка)
**Rationale:** Всё остальное зависит от работающей пары таргетов с корректными entitlements; это фаза с самым «платформенным» риском (бесплатная подпись, App Group id, provisioning), и её надо разрешить до любой логики. Скрипт `xcodebuild` — с первого дня.
**Delivers:** Xcode-проект, два таргета (app + widget extension), entitlements-файлы, App Group, CLI-сборка одной командой, запуск вне Xcode.
**Addresses:** (платформенная база; фичи — ни одной, но блокирует все).
**Avoids:** Pitfalls 5, 6 (capabilities бесплатной команды, 7-дневные профили, несовпадение entitlements).

### Phase 2: Движок опроса (UsageCore: модели, SnapshotStore, 4 адаптера)
**Rationale:** Ядро данных — источник всех остальных фич; схема снимка (`fetchedAt`, `resetsAt` на окно) замораживается здесь, от неё зависят обе оболочки. Тестируется чистым `swift test` без Xcode-таргетов. OpenRouter — первый вертикальный срез (простейший адаптер).
**Delivers:** Пакет UsageCore, адаптеры Codex/GLM/Kimi/OpenRouter с фикстурами и негативными тестами, атомарный SnapshotStore, нормализатор времени.
**Addresses:** Адаптеры 4 провайдеров (P1), семантика «ошибка ≠ 0» на уровне данных.
**Avoids:** Pitfalls 2, 3, 7 (read-only OAuth + классификация 401/403, лёгкие парсеры + фикстуры, Z.ai-диалект, Kimi путь `/coding/v1/usages`, формула OpenRouter).
**Research flag:** да — машинно проверить фактические запросы (UA/Cloudflare для `chatgpt.com`), сверить заголовки с датой.

### Phase 3: Учётные данные (Keychain + настройки)
**Rationale:** Адаптеры требуют защищённого хранилища; data-protection keychain должна быть с первого коммита хранения — миграции токенов потом болезненны.
**Delivers:** KeychainStore (`kSecUseDataProtectionKeychain`), окно настроек: ввод ключей, метка происхождения Z.ai, интервал опроса, тумблеры провайдеров, launch at login (`SMAppService`).
**Addresses:** Keychain-хранилище + форма настроек (P1), скрытие неподключённых, Launch at login.
**Avoids:** Pitfall 4 (Keychain и переподпись), хранение происхождения Z.ai рядом с ключом.
**Research flag:** частично — проверить поведение App Group / data-protection keychain на personal team (MEDIUM в STACK.md).

### Phase 4: Строка меню (MenuBarExtra + ProbeScheduler)
**Rationale:** После этой фазы продукт уже полезен без виджета — ранняя валидация ядра на реальном использовании владельцем. Меню-бар — «частая» поверхность, виджет строится позже на тех же данных.
**Delivers:** MenuBarExtra `.window` с карточками, ProbeScheduler (5–15 мин), ручной refresh, возраст данных, бейджи ошибок (401 ≠ сеть), цветовая шкала, «худшее окно сверху».
**Addresses:** Dropdown (P1), фоновый опрос (P1), Refresh now (P1), цветовая шкала (P1).
**Avoids:** UX-pitfalls (ошибка как 0%, блокировка UI на опросе, reload-шторм — reloadTimelines только по изменению).
**Research flag:** нет — паттерны стандартные; MEDIUM-квирки MenuBarExtra `.window` (перерисовка popover) держать как план Б через NSStatusItem/NSPopover.

### Phase 5: Виджет Notification Center
**Rationale:** Самый рискованный Xcode-plumbing (второй таргет, App Group, бюджет WidgetKit), но чистое потребление: строится и отлаживается против файлов, которые пишет Phase 4. Приёмка обязательно вне отладчика и на второй день.
**Delivers:** TimelineProvider, виджеты systemSmall/systemMedium, живой countdown и возраст (динамические даты), placeholder/stale-состояния, проводка `WidgetCenter.reloadTimelines` по изменению.
**Addresses:** Виджет NC (P1), живой countdown (дифференциатор).
**Avoids:** Pitfalls 1, 6 и moderate «getSnapshot ходит в сеть», «reloadTimelines шторм», «записи чаще 5 мин».
**Research flag:** да — сверить release notes WidgetKit/macOS 26–27 (Liquid Glass, новые API) перед фазой; приёмка вне отладчика.

### Phase 6: Уведомления и полировка (v1.x-фичи + README)
**Rationale:** Пороговые/reset-уведомления, refresh-кнопка в виджете, прогноз опустошения — по триггерам после валидации ядра. README публичного репозитория (трёхъязычный, `readme-skill`) и честное документирование 7-дневной пересборки — часть продукта.
**Delivers:** UNUserNotificationCenter (порог 80%, reset на `resetsAt−1 мин`), App Intent refresh в виджете, прогноз опустошения, README EN/RU/ZH + MIT, проверка «Looks done but isn't»-чеклиста.
**Addresses:** Все P2-фичи из FEATURES.md; публичная выкладка (grep по `sk-`/`eyJ`/`Bearer ` в истории перед пушем).
**Avoids:** Уведомление о сбросе через scheduled-уведомление, а не таймер; утечки токенов в логи/git.

### Phase Ordering Rationale

- Зависимости из FEATURES.md: Keychain ← адаптеры ← опросчик+кэш ← обе оболочки ← уведомления; это прямо даёт порядок 2→3→4→5→6.
- Горизонтальные слои (выбор владельца): каждый слой завершён и тестируем до потребления следующим; виджет — чистое потребление, поэтому идёт после меню-бара, а не параллельно.
- Платформенные риски (подпись, entitlements, App Group) разрешаются в Phase 1, когда их дёшево чинить; риски данных (парсеры, OAuth) — в Phase 2 с фикстурами и без UI.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 2:** фактические запросы/UA для `chatgpt.com` (Cloudflare-поведение, расхождение референсов) — машинная проверка; Open Questions из PITFALLS.md.
- **Phase 3:** поведение App Group и data-protection keychain на бесплатном personal team (MEDIUM во всех источниках).
- **Phase 5:** release notes WidgetKit/macOS 26–27; наблюдаемый срок жизни provisioning-профиля (закрывается первой неделей Phase 1/5).

Phases with standard patterns (skip research-phase):
- **Phase 1, 4, 6:** шаблонные структуры Apple и стандартные API (MenuBarExtra, SMAppService, UNUserNotificationCenter, readme-skill) — документация подтверждена HIGH.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Официальная документация Apple/swift.org + машинная проверка тулчейна на машине владельца; MEDIUM только в поведении App Group/keychain с personal team |
| Features | HIGH | Локальный проверенный референс dsh-usage + 5 независимых конкурентов; UX-наблюдения из README помечены MEDIUM/LOW и использованы только как паттерны |
| Architecture | HIGH | Каждое несущее утверждение — из актуальной документации Apple (fetched 2026-10-11); MEDIUM — стандартная практика (LSUIElement-цикл, атомарные файлы) |
| Pitfalls | HIGH (эндпоинты), MEDIUM (подпись) | Эндпоинты: референс + ≥3 независимые реализации + живой прогон OpenRouter; 7-дневный срок профиля — консенсус сообщества, официальной страницы нет |

**Overall confidence:** HIGH

### Gaps to Address

- **Срок жизни provisioning-профиля personal team на macOS** (~7 дней — консенсус, не официальный факт): закрыть наблюдением в Phase 1; README обязан документировать пересборку независимо от исхода.
- **Cloudflare/UA для `chatgpt.com`** (референсы расходятся: `codex-cli` vs собственный): машинно проверить в Phase 2, зафиксировать рабочий набор заголовков с датой.
- **App Group / data-protection keychain на бесплатной команде**: механизм подтверждён доками, поведение с personal team — проверить в Phase 1/3 настройкой таргетов.
- **macOS 26/27-специфика WidgetKit** (Liquid Glass, новые API): часовая сверка release notes перед Phase 5 — не блокер.
- **Kimi OAuth CLI-токена** (вместо API-ключа): сознательно out of scope v1; при потребности — отдельное исследование `auth.kimi.ai`.

## Sources

### Primary (HIGH confidence)
- `@linxin666/dsh-usage` (`adapters.ts`, `types.ts`, README) — локальный установленный пакет, проверен машинно 11.10.2026: эндпоинты, заголовки, парсеры, нормализация времени
- Apple Developer docs (fetched 2026-10-11, © 2026): Keeping a widget up to date; TimelineProvider; WidgetCenter; App Groups entitlement; Keychain sharing; Configuring the macOS App Sandbox; MenuBarExtra; Making network requests in a widget extension
- swift.org — Swift 6.4.0 install page + блог Swift 6.2 (Approachable Concurrency, Swift Testing); Xcode Release Notes (линейка 27)
- Apple Account Help — Supported capabilities (таблица извлечена машинно 11.10.2026)
- steipete/CodexBar — `docs/codex-oauth.md`, `docs/KEYCHAIN_FIX.md`, `CodexTokenRefresher.swift`, тесты Zai/Kimi (перекрёстно с openai/codex)
- Живой прогон 11.10.2026: `GET openrouter.ai/api/v1/credits` без Bearer → 401
- Независимые реализации (grep.app, 11.10.2026): sub2api (Kimi 404 без /v1, null-окна), oh-my-claudecode, OmniRoute, codeburn, ai-usagebar — ≥3 источника на факт

### Secondary (MEDIUM confidence)
- CodexBar README — многопровайдерный эталон UX (окна, countdowns, refresh-режимы)
- Brink README — цветовая шкала, scheduled reset-уведомления, скрытие провайдеров
- AIQuota README — paired gauges, возраст данных, «unavailable ≠ zero»
- Консенсус сообщества: 7-дневные provisioning-профили macOS personal team; квирки MenuBarExtra `.window`

### Tertiary (LOW confidence)
- ccusage README, Claude-Code-Usage-Monitor README, Stats README — паттерны категории (burn rate, конвенции menubar), не факты об эндпоинтах

---
*Research completed: 2026-10-11*
*Ready for roadmap: yes*
