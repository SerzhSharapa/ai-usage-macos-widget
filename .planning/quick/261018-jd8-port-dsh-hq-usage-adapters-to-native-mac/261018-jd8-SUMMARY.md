---
phase: 261018-jd8-port-dsh-hq-usage-adapters-to-native-mac
plan: 01
subsystem: usage-core+app+widget
tags: [providers, adapters, keychain, widget, dsh-port]
requires: [PLAT-01 skeletons, build/verify scripts]
provides: [PROV-01, MENU-01, MENU-02, WIDG-01, WIDG-04]
affects: []
key-files:
  created:
    - Packages/UsageCore/Sources/UsageCore/ProviderUsage.swift
    - Packages/UsageCore/Sources/UsageCore/ProviderAdapters.swift
    - Packages/UsageCore/Sources/UsageCore/CredentialImport.swift
    - Packages/UsageCore/Tests/UsageCoreTests/ProviderUsageTests.swift
    - AiUsage/ProviderAccess.swift
  modified:
    - AiUsage/AiUsageApp.swift
    - AiUsage/AiUsage.entitlements
    - AiUsage/Info.plist
    - Widget/TestWidget.swift
    - Widget/Info.plist
    - AiUsage.xcodeproj/project.pbxproj
    - scripts/verify-install.sh
status: complete
duration: not aggregated; signed v6 installed and runtime Keychain fixture passed
live_accounts: verified_glm_cn_kimi_openrouter_codex_source_reauth_pending
---

# Quick 261018-jd8: порт DSH-адаптеров в нативный macOS-виджет — Summary

## Текущий статус (2026-10-18)

Установлена, подписана и запущена Release-сборка **7**. Фактический installed
verify PASS: обе подписи, ожидаемая команда, права и точная регистрация appex.
Родитель повторил `swift test`: **66/66 PASS**, Ruby fixtures: **11/88 PASS**.
Подписанный бинарник v6 успешно
выполнил `--self-test-keychain`: **KEYCHAIN-SELFTEST: PASS** (новые случайные
fixture-слоты, write/read/delete и атомарный roundtrip пары, без настоящих аккаунтов).
После теста обычное приложение вновь открыто.

Codex хранится одним atomic envelope в собственном classic macOS Keychain.
Непроверенная legacy-пара не используется; требуется явный повторный импорт.
Права не расширялись: у виджета по-прежнему нет сети/Keychain. Пароль, ACL,
доверие и исходные credential-файлы агент не менял/не читал.

Прежние блокеры закрыты; WR-06 исправлен в v7. Отдельное Kimi-ревью нового
импорта: **0 critical / 1 availability warning** (`DSH-IMPORT-REVIEW.md`).

По явному разрешению владельца от 21:07 выполнен реальный импорт DSH через
приватный stdin-pipe, без секретных аргументов/временных файлов/вывода. В Keychain
сохранены Codex, GLM CN, Kimi, OpenRouter. **GLM CN, Kimi и OpenRouter успешно
ответили живыми данными**, общий кэш записан, GUI открыт. Codex-запрос не прошёл;
сохранённый DSH access истёк, refresh не копировался и не вызывался. DeepSeek
API-ключ в поддерживаемом формате не найден; посторонние account-platform,
browser/device и локальные model-gateway записи не переносились.

Импорт завершён с честно обозначенными ограничениями исходной авторизации.
Текущие факты без личных финансовых значений: `DSH-IMPORT-RESULT.json` и
`CHECKPOINT.json`. Ниже — история реализации и проверок;
старые номера сборок и результаты не заменяют текущий статус выше.

Пять провайдеров (Kimi/GLM CN+Intl/Codex/OpenRouter/DeepSeek) опрашиваются напрямую
фиксированными GET-пробами, парсеры — чистый порт dsh-usage-hq с фикстурными тестами,
меню-бар и виджет (тот же kind) читают один атомарный снимок App Group, секреты —
только в Keychain app-таргета; live-цифры ждут подключения аккаунтов владельцем.

## Выполнено

- **UsageCore (Task 1)**: `ProviderUsage.swift` — UsageWindow/ProviderRow/UsageSnapshot
  (версиированная схема, decode-валидация) + SnapshotStore (атомарный tmp+rename,
  ENOENT/I/O/decode разведены); `ProviderAdapters.swift` — порт Kimi/GLM/Codex/
  OpenRouter/DeepSeek с атрибуцией Apache-2.0 в шапке (LICENSE/NOTICE — координатор);
  `CredentialImport.swift` — чистые парсеры Codex auth.json и Kilo auth.json.
- **App (Task 2)**: `ProviderAccess.swift` (только app-таргет): KeychainStore
  (DataProtection, сервис бандла), ProviderFetcher (GET, 10 с, https+origin allowlist,
  редиректы отменяются делегатом — токен не уходит на чужой хост), UsageModel
  (@Observable, старт при запуске приложения, таймер 5 мин + ручной refresh с
  in-flight guard, last-good+error по-провайдерно, reloadTimelines после каждого
  прохода), CredentialFilePicker (NSOpenPanel, только файлы, read-only).
  Entitlement app: +`com.apple.security.files.user-selected.read-only` (ровно четыре
  права); виджет — прежние ровно два. ProviderAccess.swift добавлен в pbxproj одним
  source-вхождением в таргет AiUsage.
- **UI (Task 3)**: тёмный дашборд «Подписки»/«Балансы» (процент-бары с цветами 70/90,
  reset-даты, возраст relative, ошибки не прячут last-good), пусто → «Подключите
  аккаунты» + кнопка настроек; Settings: SecureField→Keychain (сохранение только по
  кнопке), GLM-регион — ровно 2 фиксированных origin, импорт файла Codex/Kilo,
  отключение удаляет только свой credential и свою строку. Виджет: тот же
  `testWidgetKind` литерал, small (худшие окна, unknown ранжируется как худший, не 0)
  + medium (две колонки подписки|балансы), возраст нативным relative-текстом,
  15-мин policy; DisplayName «AI Usage» (без «Тест», D-11 снята). CFBundleVersion
  2→3 в ОБОИХ Info.plist (кэш галереи). TestPanelView/«Записать тест» убраны из UI;
  TestRecord.swift и его тесты в пакете сохранены.
- **verify-install.sh**: app-allowlist расширен ровно до
  {sandbox, network.client, groups, files.user-selected.read-only(true)};
  appex-набор неизменен (любой файловый ключ у appex — FAIL). Self-test: 34/34
  (31 прежний + V20 read-write у app отвергнут, V21 read-only=false отвергнут,
  V22 отсутствие права отвергнуто; V4 appex read-only по-прежнему отвергается).

## Отклонения от плана

- **[владелец] Коммитов нет** — прямой запрет в задании; все изменения в рабочем дереве.
- **[координатор] Кimi usages limit_5h→«5h»** — порт реализует обещанное комментарием
  апстрима (код его не читал); дедуп против limits[] сохранён, тест фиксирует 0.345→35%.
- **[владелец] OpenRouter total_usage обязателен** — баг апстрима `?? 0` не перенесён:
  отсутствующий расход = отказ, last-good сохраняется (тест).
- **[координатор] Единый импорт Codex/Kilo** — один NSOpenPanel-выбор файла,
  парсинг публичной схемы Kilo auth.json (provider-словарь); refresh-токены не
  сохраняются по типу; DSH-vault парсер сознательно отсутствует (схема не подтверждена).
- **[Rule 2] Пустой снимок в виджете** → «Подключите аккаунты» (не пустой экран).
- Не сделано (осознанно, вне бюджета): widgetURL custom scheme на настройки,
  security-scoped bookmark для автоперечитывания auth.json, история/автозапуск/уведомления —
  остаются в своих фазах ROADMAP.

## Проверки

- `cd Packages/UsageCore && swift test` — **46/46 PASS** (23 фазы 1 не тронуты +
  23 новых: 3 кейса kimi-usages.spec.ts дословно — 55/90, `2026-11-01T00:00:00.000Z`,
  дедуп 5h; GLM tokens/credit/TIME_LIMIT/unknown-unit; Codex окна/ключи/401;
  OpenRouter разность и unknown≠0; DeepSeek; toIso; providerErrorMessage;
  атомарность кэша, corrupt/чужая схема, unknown providerID, last-good при ошибке,
  отсутствие секретов в сериализации; импорт credential — чистые фикстуры без Keychain).
- `bash scripts/verify-install.sh --self-test` — **34/34 PASS**.
- `bash scripts/build.sh` (Release) — подписанная сборка, staged-проверка, замена,
  запуск: **OK ×2** (второй проход после фикса пустого виджета).
- `bash scripts/verify-install.sh` (installed) — **PASS**: подпись Apple Development
  HXCPAD9C53, права app ровно 4 / appex ровно 2, четырёхсторонняя группа
  HXCPAD9C53.group.aiusage, appex зарегистрирован по точному пути (kind активен),
  NotAfter обоих сертификатов 2027-10-18 (зафиксировано, не гейт).

## Ограничения / следующий шаг владельца

- Живые цифры не показываются, пока не подключён ни один аккаунт — это ожидаемое
  честное состояние, НЕ подставные данные: панель и виджет показывают
  «Подключите аккаунты».
- Подключение: меню-бар «AI Usage» → Настройки… → «Импорт из файла (Codex / Kilo)…»
  → выбрать auth.json (⌘⇧G → путь к файлу) ИЛИ ввести ключи вручную (Kimi/GLM/
  OpenRouter/DeepSeek). Codex 401 → один запуск Codex CLI + реимпорт.
- Group Container не читается из чужого shell (EPERM на этой macOS) — контент
  виден только процессам с entitlement; наблюдение verify «(пусто)» может означать
  отказ листинга, а не отсутствие файла.
- Виджет в галерее называется «AI Usage»; уже размещённые виджеты сохранены (kind не менялся).

## Self-Check: PASSED

- Файлы из key-files существуют на диске (проверено сборкой/тестами).
- Коммитов нет по прямой инструкции владельца — `git status` отражает изменения
  в рабочем дереве; SUMMARY фиксирует это честно, без фиктивных SHA.

## Цикл исправлений 3 (261018, вечер — исполнитель Kimi K3, без коммитов по запрету владельца)

Адресный цикл по четырём оставшимся находкам REVIEW.md + parent-свойствам.
Исходники v6; подписанная сборка/установка НЕ выполнялись исполнителем
(право подписи у родителя). Проверки исполнителя: `swift test` — **63/63**
(56 + 7 новых), `xcodebuild … CODE_SIGNING_ALLOWED=NO` — **BUILD SUCCEEDED**
(unsigned compile-only, без установки). Entitlements обоих таргетов,
pbxproj, скрипты, STATE/ROADMAP/CHECKPOINT/REVIEW не изменялись; реальные
Keychain-записи и credential-файлы не читались; сетевых запросов не было.

1. **CR-02 (high) — атомарный конверт Codex.** Пара слотов упразднена:
   `CodexCredentialEnvelope` (UsageCore/CredentialImport.swift) — Codable
   `{schemaVersion, accessToken, accountId?}`, пишется ОДНОЙ операцией
   SecItem update-или-add в слот `provider.codex.credentials.v1`
   (суффикс против коллизии формы). Все пути (presence/read/import/
   disconnect/fetch) работают только с конвертом; токен и accountId для
   запроса берутся из ОДНОГО decode. Неуспешная запись оставляет прежний
   конверт нетронутым, board не инвалидируется, импорт считается failed.
   Legacy-пара v3–v5 (`provider.codex.token` + `…account-id`): НЕ
   угадывается/не смешивается/не мигрирует; есть legacy без конверта →
   `KeychainPresence.needsReimport` → UI «Требуется повторный импорт»
   (оранжевый), HTTP по legacy не выполняется никогда; «Отключить» удаляет
   конверт и свои legacy-слоты по явному действию владельца. In-memory
   `poisoned` удалён как неперсистентный. Ошибки: отказ Keychain —
   типизированная KeychainError (operation+числовой status+фиксированное
   сообщение); повреждённый конверт — фиксированное «импортируйте заново»,
   не «account id отсутствует». `saveCredential(.codex)` отклонён — Codex
   подключается только импортом.
2. **Keychain → классический macOS store.** `kSecUseDataProtectionKeychain`
   убран из baseQuery (по умолчанию false → login keychain): DP-хранилище
   без application-identifier/keychain-access-groups отклоняло записи при
   personal-team подписи (selftest v5 FAIL). Entitlements НЕ расширялись.
   Старые DP-записи не читаются и не трогаются; пустой classic-стор честно
   показывает «Не подключён» → повторный ввод/импорт владельцем.
3. **WR-05 + диагностика self-test.** `--self-test-keychain`: выход из
   `App.init` до модели/сети (прежний); контрольное чтение после delete —
   `try` (ошибка чтения = FAIL, не nil); вывод FAIL включает
   `op=<write|read|delete> status=<число OSStatus>` (безопасная числовая
   диагностика, без localizedDescription/значений); добавлен парный fixture —
   атомарный roundtrip JSON-конверта в НОВОМ случайном слоте (без живого
   ключа); cleanup — `try?` только над своими fixture-слотами.
4. **WR-04 — коалесцирование refresh.** In-flight/pendingRerun заменены
   чистым `RefreshGate` (UsageCore): запрос во время прохода коалесцируется
   в ОДИН немедленный повторный проход синхронного while-цикла того же await
   (без рекурсивного порождения задач, без 5-минутного ожидания; новых
   запросов нет — цикл завершается, мёртвых циклов нет). UsageModel.refreshAll
   реально использует вентиль (интеграция подтверждена компиляцией app-таргета).
5. **WR-03 (medium) — неизвестность за переполнением.** small И medium
   вызывают `containsUnknownPercent` на ПОЛНОМ `row.windows` независимо от
   усечённой сводки: бейдж «неизв.» (amber) + известный максимум остаётся
   явным, но при неполноте НЕ зелёный (secondary — частичные данные);
   «+N ещё» остаётся честным количеством, не фейковым нулём.

Тесты-фиксации (7 новых): конверт roundtrip (обе части из одной записи,
явный nil accountId), отказ decode мусора/чужой схемы/нестрокового accountId/
пустого токена (ошибка ≠ «слота нет»), «неуспешная запись не инвалидирует
board» (A→A целы, успешная замена инвалидирует), вентиль (ровно один
повторный проход; нет зацикливания на пустом наборе), overflow-индикатор
(4 окна со скрытым unknown; 4 unknown → прочерки + «+1 ещё», максимум не 0).

### Остаётся за родителем (как и прежде)

- Подписанная сборка v6 + установка + `verify-install.sh` (installed) +
  `--self-test-keychain` подписанного бинарника (теперь classic keychain —
  ожидается PASS; при отказе числовой status в выводе даст точный класс).
- Затем явный выбор auth.json владельцем и проверка живых ответов
  (NoLiveAccounts сохраняется).
- CHECKPOINT.json/REVIEW.md обновляет родитель; коммитов нет по запрету.

## Цикл исправлений по REVIEW.md (261018, вторая половина дня)

По четырём находкам REVIEW (1 high / 3 med) + parent-Keychain + четыре follow-up
находки независимого проверяющего. Все исправления в тех же файлах; тесты
`swift test` — **56/56** (46 + 10 новых: эпохи/last-good/фильтрация публикации,
presence-маппинг, фиксированные сообщения, сводка окон); self-test верификатора —
**34/34**; CFBundleVersion → **5** (app+appex, kind не менялся).

1. **CR-01 (high) — гонки credential**: `ProviderLifecycle.swift` (UsageCore,
   чистый): `ProviderRowBoard` — строки + монотонные эпохи; `UsageModel.refresh`
   захватывает эпоху ДО await и гасит и успех, и ошибку устаревшего credential;
   disconnect/replace/импорт — `invalidate` (эпоха+1, строка старого аккаунта
   убирается немедленно после подтверждённой записи); публикация исключает
   только достоверно absent-провайдеров (нет воскресания после перезапуска).
   Follow-up (high): пара Codex пишется id→токен с проверкой статусов; при
   отказе оба слота удаляются проверенно; при отказе очистки слот «отравлен» и
   не опрашивается до переподключения; ошибка чтения account id отменяет проб.
2. **WR-01 (med) — эхо текста провайдера**: `providerErrorMessage` = ровно
   «HTTP N»; message/msg/error.message не переносятся вовсе (тест: секрет-маркер
   в message отсутствует в сериализованном снимке).
3. **WR-02 (med) — возраст vs факт**: виджеты small/medium показывают возраст
   каждой строки из `row.fetchedAt` (нативный relative); неудачный проход
   возраст не сбрасывает (тест 10:00/11:00); `writtenAt` нигде не выдаётся за
   свежесть; error-only строки подписаны «нет данных»/«данных ещё нет».
   Follow-up (med): refresh во время идущего прохода не теряется —
   коалесцирование `pendingRerun`.
4. **WR-03 (med) — неизвестные окна**: `windowSummary` (UsageCore): «5ч — ·
   нед 42%»; follow-up: неизвестные окна упорядочены первыми — усечение прячет
   только известные; small при смешанном случае показывает «неизв.» рядом с
   известным максимумом; переполнение «+N ещё».
5. **FIX5 (parent) — статусы Keychain**: read/write/delete проверяют статусы
   SecItem и бросают типизированную ошибку с фиксированным сообщением;
   `keychainPresence(status:hasValue:)` (Core, литералы статусов без импорта
   Security — виджет SDK-символов не получает) различает notFound (absent) и
   отказ (unavailable — строки/кэч не удаляются молча); поле настроек
   очищается только при подтверждённом успехе записи; импорт считает
   imported/failed честно; `--self-test-keychain` (узкий режим подписанного
   приложения, случайный fixture-слот, do/catch на контрольном чтении).

### Установка v5 и проверка фактов

- Сборка/подписание v5 (Release) — успешно после ~3 ч ожидания одобрения
  владельцем диалога закрытого ключа (SecurityAgent; агент keychain не трогал,
  конфликтных сборок не запускал; зафиксировано HOLD на board).
- `bash scripts/verify-install.sh` (installed v5): **PASS** — подпись Apple
  Development HXCPAD9C53, права app ровно 4 / appex ровно 2, группа
  HXCPAD9C53.group.aiusage, appex зарегистрирован по точному пути, kind жив.
- `--self-test-keychain` (прямой запуск подписанного бинарника из Terminal):
  **FAIL «Не удалось сохранить ключ (Keychain)»** — SecItem-запись с
  `kSecUseDataProtectionKeychain=true` отклонена в этом контексте запуска.
  Гипотезы: (а) атрибуция Terminal как responsible-процесса при прямом запуске;
  (б) отсутствие entitlement keychain-access-groups/application-identifier у
  dev-подписи (класс -34018). Решение о политике (добавить keychain-access-groups
  в allowlist обоих таргетов vs классический файловый keychain vs проверка в
  реальном контексте приложения через настройки владельцем) — за координатором:
  расширение sharing-entitlements исполнителю запрещено. UI при отказе записи
  показывает фиксированную ошибку и не заявляет успех (FIX5), данные не фейковые.
- Владелец аккаунты ещё не подключал: панель/виджет честно показывают
  «Подключите аккаунты» (NoLiveAccounts), живых цифр нет — по-прежнему ждут
  ручного подключения (Настройки → импорт auth.json / ввод ключей).
