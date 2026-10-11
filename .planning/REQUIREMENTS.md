# Requirements — ai-usage-macos-widget

v1 scope confirmed by owner 2026-10-11 (all categories selected, including P2/P3 items —
owner decision: history and extra provider included deliberately; roadmap orders them late).

## v1 Requirements

### Core engine

- [ ] **CORE-01**: Adaptеры четырёх провайдеров по проверенным эндпоинтам — Codex
  `chatgpt.com/backend-api/wham/usage` (OAuth-токен), GLM `api.z.ai` / `open.bigmodel.cn`
  (сырой ключ без Bearer), Kimi `api.kimi.com/coding/v1/usages` (Bearer), OpenRouter
  `openrouter.ai/api/v1/credits` (Bearer); адаптеры чистые: запрос строится из креденшела,
  ответ парсится в нормализованные окна (процент, reset, план/баланс)
- [ ] **CORE-02**: Фоновый опрос из приложения с настраиваемым интервалом (дефолт 5–15 мин);
  после каждого успеха — `WidgetCenter.reloadTimelines`
- [ ] **CORE-03**: Кэш последнего успеха в App Group: данные + `fetchedAt` + отдельные слоты
  ошибок на провайдер/факт; неудачный опрос никогда не затирает последние хорошие цифры
  («ошибка ≠ 0%», «unreported ≠ zero»); возраст данных виден и в меню-баре, и в виджете
- [ ] **CORE-04**: Единая цветовая шкала расхода (пороги 70/90% дефолт) для меню-бара и виджета

### Credentials

- [ ] **CRED-01**: Ключи и токены хранятся только в Keychain (data-protection); никогда
  в git, логи, UserDefaults, код виджета
- [ ] **CRED-02**: Настройки: вставить ключ для GLM / Kimi / OpenRouter; Codex — read-only
  позиция к OAuth (никогда не писать и не ротировать refresh-токен Codex CLI; 401 →
  подсказка «запусти Codex один раз»)
- [ ] **CRED-03**: Неподключённые провайдеры скрыты из UI (не показываются как 0%)

### Menu bar

- [ ] **MENU-01**: Пункт в строке меню (MenuBarExtra, LSUIElement) с выпадающей детализацией:
  провайдер → окна с процентом, временем сброса и планом; баланс OpenRouter в USD; возраст
  данных; строки ошибок с подсказками
- [ ] **MENU-02**: Ручной «Refresh now» в dropdown и в context menu иконки
- [ ] **MENU-03**: Launch at login через SMAppService с тумблером в настройках
- [ ] **MENU-04**: Компактный режим: текст худшего процента на иконке меню-бара
  (сортировка «худшее окно сверху» в dropdown)

### Widget

- [ ] **WIDG-01**: Виджет Notification Center (systemSmall + systemMedium): строки
  провайдеров с мини-гейджем, временем сброса и возрастом данных; читает только App Group
  кэш (виджет без сети и без Keychain)
- [ ] **WIDG-02**: Живой обратный отсчёт до сброса через dynamic dates
  (`Text(timerInterval:)`) — тикает между обновлениями без расхода бюджета WidgetKit
- [ ] **WIDG-03**: Кнопка Refresh в виджете через App Intent (обновление по тапу не тратит
  бюджет WidgetKit)
- [ ] **WIDG-04**: Виджет показывает last-known-good данные с возрастом при недоступности
  свежих (ошибка сети/auth никогда не выглядит как 0%)

### Notifications

- [ ] **NOTIF-01**: Пороговое уведомление: окно достигло N% (дефолт 80%, настраивается)
- [ ] **NOTIF-02**: Уведомление о сбросе, планируемое на `resetsAt` через
  UNUserNotificationCenter (срабатывает при простое приложения)

### Forecast

- [ ] **FCST-01**: Прогноз опустошения окна («при текущем темпе закончится к HH:MM») из
  одного опроса (процент ÷ доля прошедшего окна), показывается только после ~15% elapsed

### History

- [ ] **HIST-01**: Хранение снапшотов опросов с политикой ретеншена и график расхода
  (burndown) окна; интерфейс кэша не переписывается при добавлении истории

### Extensibility

- [ ] **PROV-01**: Чистый `ProviderAdapter`-протокол: новый провайдер = один файл, без
  обязательного каталога; первый дополнительный адаптер — DeepSeek balance (парсер известен
  из референса)

### Platform & delivery

- [ ] **PLAT-01**: Сборка из исходников по инструкции (`xcodebuild`, личный Apple ID,
  personal team): два таргета (app + widget extension), App Group entitlements, сценарий
  пересборки при 7-дневных профилях; владелец не программист — путь сборки часть продукта
- [ ] **PLAT-02**: Трёхъязычный README (EN/RU/ZH) и лицензия MIT в публичном репозитории

## v2 Requirements (deferred)

- Lock Screen / дополнительные семейства виджетов
- Дополнительные провайдеры сверх DeepSeek balance (MiniMax и др.)
- Уточнение прогноза по реальным данным (после недели наблюдений)

## Out of Scope

- Поминутное автообновление виджета — бюджет WidgetKit (40–70 обновлений/сутки) не позволяет; обещать нельзя
- Cost tracking по прайслистам — вечная синхронизация цен; для подписок цифра бессмысленна
- Чтение локальных транскриптов CLI («что сжегло лимит») — противоречит независимости от харнесса
- Cookie/браузерная авторизация и скрейпинг сайтов провайдеров — хрупко, приватно тяжело
- Мультиаккаунт — личный сценарий, один аккаунт на провайдера
- Каталог десятков провайдеров / система плагинов — territory CodexBar, проект личный
- Телеметрия — никаких внешних запросов, кроме API провайдеров, подключённых через
  адаптерный протокол (четыре провайдера v1 + DeepSeek balance по PROV-01)
- iOS/iPadOS-версия — другой lifecycle; архитектура допускает порт позже
- Запись/ротация OAuth-токенов Codex CLI — только read-only

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CORE-01 | Phase 2 | Pending |
| CORE-02 | Phase 4 | Pending |
| CORE-03 | Phase 2 | Pending |
| CORE-04 | Phase 4 | Pending |
| CRED-01 | Phase 3 | Pending |
| CRED-02 | Phase 3 | Pending |
| CRED-03 | Phase 3 | Pending |
| MENU-01 | Phase 4 | Pending |
| MENU-02 | Phase 4 | Pending |
| MENU-03 | Phase 3 | Pending |
| MENU-04 | Phase 4 | Pending |
| WIDG-01 | Phase 5 | Pending |
| WIDG-02 | Phase 5 | Pending |
| WIDG-03 | Phase 5 | Pending |
| WIDG-04 | Phase 5 | Pending |
| NOTIF-01 | Phase 6 | Pending |
| NOTIF-02 | Phase 6 | Pending |
| FCST-01 | Phase 6 | Pending |
| HIST-01 | Phase 6 | Pending |
| PROV-01 | Phase 6 | Pending |
| PLAT-01 | Phase 1 | Pending |
| PLAT-02 | Phase 6 | Pending |

Coverage (validated 2026-10-11): **22/22** v1 requirements mapped; no orphans,
no duplicate phase assignments. All statuses remain Pending until implementation
and acceptance. Shared-layer behavior is rechecked when later UI consumers are
connected; each requirement still has exactly one owning phase.

---
*Initialized: 2026-10-11*
