# ai-usage-macos-widget

## What This Is

Нативное приложение macOS (SwiftUI + WidgetKit), которое показывает расход
подписочных лимитов AI-провайдеров — виджетом в Центре уведомлений и пунктом
в строке меню. Повторяет карточку LIMITS плагина DSH `@linxin666/dsh-usage`,
но независимо от кодинг-харнесса: работая в Kilo, DSH или другом клиенте,
владелец видит одни и те же цифры, потому что данные запрашиваются у
провайдеров напрямую.

## Core Value

Работая в любом кодинг-агенте, в один взгляд видеть актуальный расход лимитов
подписок (OpenAI/Codex, Z.ai GLM, Kimi Code) и баланс OpenRouter — без
открывания веб-кабинетов провайдеров.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Приложение-компаньон запрашивает лимиты у провайдеров напрямую (HTTP)
- [ ] Ключи/токены хранятся в Keychain macOS
- [ ] Виджет в Центре уведомлений: проценты по окнам + время сброса
- [ ] Пункт в строке меню с более частым обновлением и ручным refresh
- [ ] Кэш последнего успешного опроса: виджет показывает данные и возраст,
      ошибка сети/auth не выдаётся за 0%

### Out of Scope

- App Store / публичные сборки — личное использование, подписка бесплатным
  Apple ID; нотаризация и Developer ID не требуются
- Windows/Linux — платформенно-специфичный WidgetKit
- Поминутное автообновление виджета — ограничение бюджета WidgetKit,
  не обещаем
- Токены и логи с секретами в git — секреты только в Keychain

## Context

- Референс решения — установленный плагин DSH `@linxin666/dsh-usage`
  (`src/core/adapters.ts`): точные эндпоинты и парсеры — OpenAI
  `chatgpt.com/backend-api/wham/usage`, Kimi `api.kimi.com/coding/v1/usages`,
  Z.ai `api.z.ai` / `open.bigmodel.cn` (plan), OpenRouter
  `openrouter.ai/api/v1/credits`. Проверено 11.10.2026. Свою реализацию
  пишем на Swift, транспорт не переиспользуем.
- Владелец уверенно держит инфраструктуру, но не программист: приложение
  должно собираться и работать из понятной документации.
- Машина: macOS 27.0.1, arm64, Swift 6.4 (Command Line Tools); Xcode будет
  установлен владельцем из App Store.
- Проект публичный на GitHub: https://github.com/SerzhSharapa/ai-usage-macos-widget
  (решение владельца 11.10.2026). README трёхъязычный, лицензия MIT.

## Constraints

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

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Публичный GitHub-репозиторий | Полезно сообществу, владелец решил на старте (11.10.2026) | — Pending |
| Данные у провайдеров напрямую, не из DSH/Kilo | Независимость от харнесса: видно в любом клиенте | — Pending |
| Xcode из App Store, личная подписка | Виджет требует Xcode; App Store/Developer ID не нужны для личного использования | — Pending |
| macOS 15+ | Свежие WidgetKit API, старые Mac не нужны | — Pending |
| Horizontal Layers | Решение владельца при инициализации (11.10.2026) | — Pending |
| Виджет + строка меню как два представления одного сборщика | Бюджет WidgetKit не даёт поминутной свежести; меню-бар компенсирует | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-10-11 after initialization*
