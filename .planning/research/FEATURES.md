# Feature Research

**Domain:** нативное macOS-приложение (menubar + Notification Center widget) для мониторинга расхода лимитов AI-подписок — Codex/ChatGPT, Z.ai GLM Coding Plan, Kimi For Coding, баланс OpenRouter
**Researched:** 2026-10-11
**Confidence:** HIGH (основные выводы)

Метод: экосистема сверена по шести независимым продуктам (ccusage 19k★, Claude-Code-Usage-Monitor 8.7k★, CodexBar ~100 провайдеров, Brink 52★, AIQuota 12★, Stats) и по локальному референсу — карточке LIMITS плагина `@linxin666/dsh-usage` (адаптеры проверены машинно 11.10.2026). Состав данных провайдеров — HIGH (проверенный код + независимое подтверждение в CodexBar). Наблюдения по UX конкурентов — из README (несколько независимых источников согласны), помечены как MEDIUM/LOW в разделе «Источники».

## Feature Landscape

### Table Stakes (Users Expect These)

Отсутствие любого пункта делает продукт ощутимо неполным на фоне конкурентов.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Проценты по каждому окну лимита (5h / week / month — как сообщает провайдер) | Базовая сущность домена: есть у dsh-usage, Brink, AIQuota, CodexBar | LOW | Codex отдаёт `used_percent` для primary/secondary; GLM — `percentage` или отношение кредитов; Kimi — `used/limit` по окнам. Данные уже нормализованы в референсе: ключи окон `5h`/`week`/`month` |
| Время сброса окна + живой обратный отсчёт | «Plan around resets» — главный вопрос пользователя (CodexBar); все конкуренты показывают reset | LOW | В виджете использовать `Text(timerInterval:)` (dynamic dates) — тикает без расхода бюджета WidgetKit (офиц. докуменентация Apple) |
| Пункт в строке меню с выпадающей детализацией | Ядро категории: menubar app без dropdown — просто иконка | MEDIUM | SwiftUI `MenuBarExtra`; строки: провайдер → окна с процентом и reset → баланс OpenRouter → возраст данных |
| Ручной refresh («Refresh now») | Есть у всех: dsh-usage, Brink, CodexBar, AIQuota; единственный способ получить свежие данные немедленно | LOW | Кнопка в dropdown + context menu иконки |
| Фоновый опрос с настраиваемым интервалом (приложение) | Приложение-компаньон — единственный источник постоянной свежести: бюджет виджета 40–70 обновлений/сутки (Apple); конкуренты дают 1–30 мин | LOW | Дефолт 5–15 мин; таймер в главном приложении; после каждого успеха — `WidgetCenter.reloadTimelines` |
| Кэш последнего успеха + возраст данных («обновлено N мин назад») | AIQuota прямо называет: «see when a reading was last updated»; dsh-usage хранит `updatedAt` по каждому факту | LOW | Одно требование PROJECT.md. Возраст — и в dropdown, и в виджете |
| Ошибка ≠ ноль: неудачный опрос сохраняет последние хорошие цифры + строку ошибки | Критичная семантика: dsh-usage («a failed probe keeps the previous fact visible»), AIQuota («unreported values remain unavailable rather than appearing as zero») | MEDIUM | Отдельный слот ошибки на провайдер/факт (у dsh-usage — `balanceError`/`planError` отдельно, чтобы успех одного не маскировал сбой другого). 401 Codex = «токен протух, запусти Codex один раз» — понятная подсказка |
| Ключи/токены в Keychain, ни в git/логах/UserDefaults | Конвенция домена (CodexBar, Brink читают Keychain; PROJECT.md — жёсткое требование) | MEDIUM | Codex: OAuth access token (+ опц. `chatgpt-account-id`); GLM: «сырой» ключ без Bearer; Kimi и OpenRouter: Bearer |
| Launch at login | Есть у всех (Brink — SMAppService, совместимо с System Settings → Login Items) | LOW | `SMAppService` + тумблер в настройках |
| Скрытие неподключённых провайдеров | Brink: «providers you're not signed in to are hidden»; нули вводят в заблуждение | LOW | Настройка «какие провайдеры показывать»; неподключённый = скрыт, а не 0% |
| Цветовая индикация уровня расхода | Brink (green→yellow→red rings), CodexBar (meter icons), карточка LIMITS | LOW | Пороги 70/90% как дефолт; единая шкала для dropdown и виджета |
| Виджет Notification Center с процентами и reset | Прямое требование PROJECT.md; AIQuota и CodexBar подтверждают: WidgetKit-виджеты — стандарт категории | MEDIUM | systemSmall/systemMedium; строки провайдеров с мини-гейджем и countdown |
| Баланс OpenRouter в USD | Учетная величина, а не окно: показывается отдельно от планов (так же в dsh-usage: balance ≠ plan) | LOW | `total_credits − total_usage`, USD; без процента — абсолютное число |

### Differentiators (Competitive Advantage)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Четыре провайдера владельца в одном нативном приложении по прямому API | Ниша: Brink/AIQuota/capbar/usage-menubar — только Claude/Codex; GLM и Kimi For Coding не покрывает почти никто; CodexBar покрывает, но это 100-провайдерный комбайн с cookie-скрейпингом. Прямой API по ключам — без чтения чужих keychain-записей, cookie и транскриптов CLI | MEDIUM | Ровно состав карточки LIMITS dsh-usage, но независимо от харнесса. Адаптерный протокол оставляет место новым провайдерам без обязательного расширения каталога |
| Живой countdown до сброса в виджете между обновлениями | WidgetKit-обновления приходят раз в 15–60 мин, но dynamic dates тикают сами — виджет всегда показывает корректное «сброс через 1:23», а не устаревшее время | LOW | `Text(timerInterval:)` по `resetsAt`; редкость у конкурентов: их виджеты статичны между reloads |
| Кнопка Refresh прямо в виджете (интерактивный App Intent) | Обновление по кнопке не расходует бюджет WidgetKit (Apple: «the widget performs an app intent» — исключение из бюджета); свежие данные по тапу без открытия приложения | MEDIUM | AppIntent дергает общий сборщик и `reloadTimelines`; по Buffer-box iOS 17+/macOS 14+ API доступно |
| Порядок «худшее окно сверху» + компактный режим иконки | Владелец в один взгляд видит самый дефицитный ресурс; CodexBar решает это настройкой «highest-usage auto-selection» — подтверждённый спрос, но у нас это дефолт, а не опция | LOW | Сортировка строк по проценту; опц. текст иконки меню-бара в виде худшего процента |
| Прогноз опустошения окна («при текущем темпе закончится к HH:MM») | Паттерн ccusage/Claude-Code-Usage-Monitor (burn rate, predictions) — самая частая фича-запрос категории; считается из одного опроса: процент ÷ доля прошедшего окна | MEDIUM | Без истории: прогноз = percent / (elapsed/window) с клампом; показывать только после ~15% elapsed, иначе шум |
| Пороговые уведомления (N% по окну) + уведомление о сбросе | Brink: уведомление при заполнении лимита и второе — в момент сброса (scheduled, срабатывает даже когда приложение простаивает); AIQuota: per-service alerts. Для личного сценария «не встать в середина задачи» — главная ценность | MEDIUM | UNUserNotificationCenter; порог по умолчанию 80%; reset-уведомление планировать на `resetsAt − 1 мин` |
| Двухуровневая семантика данных: окно плана ≠ деньги | dsh-usage разводит Plans (окна) и balance (деньги) — провайдеры без плана не врут про окна; OpenRouter показывается деньгами, Codex/GLM/Kimi — процентами | LOW | Архитектурное решение, которое конкуренты-моно-провайдеры не закладывают сразу |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Поминутное автообновление виджета | «Хочу видеть точно» | Невозможно по бюджету WidgetKit (40–70 reloads/сутки, ~15–60 мин) — прямо Out of Scope в PROJECT.md; обещать нельзя | Живой countdown + кнопка Refresh (не тратит бюджет) + частый опрос в приложении |
| Учёт стоимости в деньгах по прайслистам (cost tracking как ccusage) | «Сколько я потратил?» | Требует прайс-бука по моделям и вечной синхронизации цен (dsh-usage содержит его только для DeepSeek); для подписочных планов цифра бессмысленна — плачено подпиской | Показывать только то, что сообщает провайдер: проценты окон и баланс OpenRouter в USD |
| Чтение локальных транскриптов CLI (как ccusage/Brink «what used it») | Детализация «какой проект сжёг лимит» | Привязка к форматам файлов харнессов — прямое противоречие цели «независимость от кодинг-харнесса»; конфиденциальность (транскрипты содержат секреты проектов) | Только данные, которые отдаёт API провайдера |
| Cookie/браузерная авторизация и скрейпинг (путь CodexBar к 100+ провайдерам) | Больше провайдеров без ключей | Хрупко (любой рефактор сайта ломает парсер), требует Full Disk Access / парсинга чужих keychain-хранилищ, приватно тяжело | API-ключи владельца; при появлении нового провайдера — новый адаптер по его API |
| Мультиаккаунт и переключение аккаунтов (ai-guest-list, claude-code-accounts) | «Есть две подписки» | Личный сценарий — один аккаунт на провайдера; UI переключателей удваивает состояние | Структура данных допускает по одному аккаунту на провайдера; расширение не запрещено архитектурой |
| Каталог из десятков провайдеров / система плагинов | «Пригодится всем» | Territory CodexBar; поддержка чужих API — бесконечный treadmill; проект публичный, но личный | Чистый `ProviderAdapter`-протокол: добавить провайдера = один файл; каталог растёт по потребности владельца |
| Телеметрия и аналитика использования | «Понять, как живут пользователи» | Личный privacy-first инструмент; дергать лишние хосты незачем | Никаких внешних запросов, кроме четырёх API провайдеров (пример Stats: явный список хостов) |
| iOS/iPadOS-версия | «Хочу на телефоне» | WidgetKit-специфика macOS 15, отдельный lifecycle, TestFlight-обвязка — чужой проект | macOS-виджет и строка меню; архитектура (общий сборщик) позволяет порт позже |
| История/графики расхода в v1 | «Красиво и полезно» | Требует склада снапшотов и ретеншн-политики (CodexBar: SQLite, 25k записей, 256 MiB cap) — оттягивает MVP | Сначала проценты/сбросы; историю — после валидации ядра (v1.x/v2) |

## Feature Dependencies

```
[Keychain-хранилище ключей]
    └──requires──> [Адаптеры провайдеров (Codex/GLM/Kimi/OpenRouter)]
                        └──requires──> [Фоновый опросчик + кэш последнего успеха (updatedAt, error-слоты)]
                                            ├──requires──> [Dropdown меню-бара: окна %, reset, баланс, возраст, ошибки, Refresh now]
                                            ├──requires──> [Виджет NC: строки провайдеров + живой countdown (dynamic dates)]
                                            │                    └──enhances──> [Кнопка Refresh в виджете (App Intent)]
                                            └──requires──> [Цветовая шкала 70/90%]
                                                                 └──enhances──> [Пороговые уведомления + уведомление о сбросе]

[Launch at login] ──independent──> (влияет только на UX первого запуска)

[Прогноз опустошения] ──requires──> [Опросчик] (но не требует истории)

[История/графики] ──requires──> [Хранилище снапшотов] ──conflicts──> [минимальность MVP]
```

### Dependency Notes

- **Адаптеры требуют Keychain, а не наоборот:** все четыре API принимают только токен/ключ; без защищённого хранилища адаптер нельзя безопасно вызвать.
- **Виджет требует общего хранилища с приложением:** виджет-расширение — отдельный процесс; данные передаются через App Group (общий файл кэша), а не память приложения. Это главный архитектурный узел: кэш + возраст + ошибки должны жить в формате, читаемом обоими процессами.
- **Countdown не требует данных, только `resetsAt`:** dynamic dates обновляются системой — фича почти бесплатна после того, как адаптеры отдают время сброса (все четыре отдают: `reset_at`, `nextResetTime`, `resetTime`, для OpenRouter не применимо).
- **Уведомления о сбросе конфликтуют с долгим сном системы:** планировать через `UNUserNotificationCenter` на конкретный момент (как Brink), а не надеяться на работающий таймер.
- **История конфликтует с MVP:** хранилище снапшотов — отдельный компонент с ретеншеном; закладывать интерфейс кэша так, чтобы историю можно было добавить, не переписывая кэш.

## MVP Definition

### Launch With (v1)

Минимум, валидирующий Core Value («в один взгляд видеть лимиты из любого кодинг-агента»):

- [ ] Адаптеры четырёх провайдеров по проверенным эндпоинтам (Codex `wham/usage` OAuth; GLM `quota/limit` сырой ключ; Kimi `coding/v1/usages` Bearer; OpenRouter `credits` Bearer) — источник всех остальных фич
- [ ] Keychain-хранилище ключей + форма настроек «вставь ключ / войди в Codex» — без этого сборщик не работает
- [ ] Фоновый опросчик + кэш последнего успеха (данные + `updatedAt` + слоты ошибок) — семантика «ошибка ≠ 0%»
- [ ] Dropdown в строке меню: по провайдеру — окна с процентом, временем сброса, план; баланс OpenRouter; возраст данных; Refresh now
- [ ] Виджет Notification Center (small + medium): строки провайдеров, гейдж, живой countdown, возраст данных
- [ ] Launch at login; скрытие неподключённых провайдеров; цветовая шкала
- [ ] Сборка из исходников по инструкции (`xcodebuild`, личный Apple ID) — владелец не программист, путь сборки — часть продукта

### Add After Validation (v1.x)

- [ ] Пороговые уведомления + уведомление о сбросе — триггер: ядро стабильно, владелец начал доверять цифрам
- [ ] Кнопка Refresh в виджете (App Intent) — триггер: заметно желание обновляться не открывая dropdown
- [ ] Прогноз опустошения окна — триггер: неделя реальных данных покажет, шумит ли прогноз
- [ ] Компактный текст иконки меню-бара (худший процент) — триггер: уточнение после жизни с дефолтной иконкой

### Future Consideration (v2+)

- [ ] История расхода / burndown-графики — требует склада снапшотов; ценность подтвердить у себя
- [ ] Дополнительные провайдеры по адаптерному протоколу (DeepSeek balance, MiniMax, OpenCode Go — есть готовые парсеры в референсе)
- [ ] Lock Screen / дополнительные семейства виджетов — если основной формат прижился

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Адаптеры 4 провайдеров + Keychain | HIGH | MEDIUM | P1 |
| Опросчик + кэш «ошибка ≠ 0» + возраст | HIGH | MEDIUM | P1 |
| Dropdown меню-бара с окнами/reset/балансом | HIGH | MEDIUM | P1 |
| Виджет NC с гейджами и живым countdown | HIGH | MEDIUM | P1 |
| Launch at login, скрытие провайдеров, цветовая шкала | MEDIUM | LOW | P1 |
| Ручной refresh (dropdown) | HIGH | LOW | P1 |
| Пороговые + reset уведомления | HIGH | MEDIUM | P2 |
| Refresh-кнопка в виджете | MEDIUM | MEDIUM | P2 |
| Прогноз опустошения | MEDIUM | LOW | P2 |
| Компактный текст иконки | MEDIUM | LOW | P2 |
| История/burndown | MEDIUM | HIGH | P3 |
| Новые провайдеры сверх четырёх | LOW (лично) | MEDIUM | P3 |

**Priority key:** P1 — must have for launch; P2 — should have, add when possible; P3 — nice to have.

## Competitor Feature Analysis

| Feature | dsh-usage LIMITS (референс) | CodexBar | Brink | AIQuota | Наш подход |
|---------|------------------------------|----------|-------|---------|------------|
| Покрытие провайдеров | Codex, GLM, Kimi, OpenRouter + ещё 8 | ~100 | Claude, Codex, Cursor | Codex, Claude | Ровно 4 провайдера владельца, адаптерный протокол |
| Источник данных | Прямой API по ключам/OAuth | API + cookie-скрейпинг + локальные файлы | Чужой Keychain + API | OAuth-вход + опц. чужой keychain | Прямой API по своим ключам только |
| Окна + reset | Да, все планы | Да + countdowns | Да (rings) | Да (paired gauges) | Да + живой countdown в виджете |
| Виджеты | — (web-карточка) | WidgetKit | — (edge panel) | Desktop + Lock Screen | WidgetKit NC — ядро продукта |
| Ошибка ≠ 0 | Да (per-fact error slots) | Да (dimmed icon) | Скрытие | «unavailable ≠ zero» | Да — требование PROJECT.md |
| Возраст данных | `updatedAt` | capture time | — | «last updated» | Да |
| Уведомления | — | session quota | limit + reset (scheduled) | configurable alerts | v1.x: порог + reset |
| Burn rate / прогноз | — | burndown из снапшотов | — | — | v1.x лёгкий прогноз без истории |
| Cost tracking | DeepSeek-only прайсбук | spend dashboards, scans | нет, осознанно | кредиты как сообщает | нет — anti-feature |
| Мультиаккаунт | — | — | — | — | нет — anti-feature |
| Публичность | npm-плагин | GitHub, Homebrew | GitHub, DMG | GitHub, DMG | GitHub, MIT, личная сборка |

## Sources

- [HIGH] `@linxin666/dsh-usage` `src/core/adapters.ts` + `src/core/types.ts` + README — эндпоинты, поля ответов, семантика ошибок; проверено машинно 11.10.2026 (локальный установленный пакет)
- [HIGH] Apple Developer — WidgetKit «Keeping a widget up to date» (developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date, © 2026): бюджет 40–70 reloads/сутки, dynamic dates без reload, app intent как исключение из бюджета, `WidgetCenter.reloadTimelines`
- [MEDIUM] CodexBar README (github.com/steipete/CodexBar) — многопровайдерный эталон: окна+countdowns, burndown, виджеты, уведомления, refresh-режимы; независимое подтверждение эндпоинтов z.ai/Kimi/OpenRouter/DeepSeek
- [MEDIUM] Brink README (github.com/semihtalii/brink) — rings/цветовая шкала, reset-уведомления по расписанию, launch at login, скрытие неподключённых, Keychain-промпты, осознанный отказ от cost accounting
- [MEDIUM] AIQuota README (github.com/niederme/ai-quota) — paired gauges 5h+week, виджеты small/medium/large, возраст данных, «unreported ≠ zero», onboarding
- [LOW] ccusage README (github.com/ccusage/ccusage) — отчёты daily/weekly/monthly/session, 5-hour blocks, burn rate как паттерн категории
- [LOW] Claude-Code-Usage-Monitor README (github.com/Maciek-roboblog/Claude-Code-Usage-Monitor) — пороговые коды (0/10/11), provenance labels, state-file протокол для внешних tray-компаньонов
- [LOW] Stats README (github.com/exelban/stats) — конвенции menubar-мониторов, тумблер «System Settings → Menu Bar» на macOS 26, опциональность виджетов

Наблюдения с LOW — одиночные README-источники; использованы только для паттернов категории, не для фактов об эндпоинтах. SwiftBar/xbar-экосистема намеренно не углублялась: три нативных Swift-конкурента (CodexBar, Brink, AIQuota) покрывают те же конвенции точнее.

---
*Feature research for: ai-usage-macos-widget*
*Researched: 2026-10-11*
