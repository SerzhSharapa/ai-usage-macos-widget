---
phase: quick-261018-jd8
reviewed: 2026-10-18T21:30:00Z
depth: standard
files_reviewed: 6
files_reviewed_list:
  - scripts/import-dsh-credentials.rb
  - scripts/tests/dsh-import-test.rb
  - scripts/verify-install.sh
  - scripts/stop-installed.sh
  - AiUsage/AiUsageApp.swift
  - AiUsage/ProviderAccess.swift
  - Packages/UsageCore/Sources/UsageCore/CredentialImport.swift
findings:
  critical: 0
  warning: 1
  info: 3
  total: 4
status: issues_found
---

# DSH Import Dataflow: Независимый security review (Kimi, независимо от Sol-авторства)

**Reviewed:** 2026-10-18T21:30Z
**Depth:** standard (bounded, по заданному dataflow)
**Files Reviewed:** 7
**Status:** issues_found (0 Critical / 1 Warning / 3 Info) — **утечки секрета не доказана ни по одному каналу**

## Summary

Проверен только заданный контур: Ruby-helper → (verify/stop) → приватный stdin-pipe →
CLI-ветка app (`--import-credentials-stdin`) → Keychain/один явный проход опроса →
whitelisted stdout-отчёт → sanitize в helper → гарантированный reopen. Живые чтения
`~/.dsh/.credentials.yaml`, реальные `--import`/`--inspect`, Keychain- и
provider-вызовы, сборки и процессы НЕ выполнялись (read-only ревью; живые аккаунты
не задействованы — NoLiveAccounts до фактического прогона владельцем).

Все обязательные свойства из задания подтверждены чтением кода (см. «Границы»).
Критических дефектов, при которых root-secret import мог бы утечь, не найдено.
Единственное предупреждение — отсутствие таймаута ожидания child в `receive`
(риск доступности GUI, не утечки).

## Проверка обязательных свойств (все PASS, если не сказано иное)

1. **Секреты только в private stdin-pipe** — `import-dsh-credentials.rb:117-131`:
   `Open3.popen2` с scrubbed env (`unsetenv_others: true`, только HOME+PATH),
   stderr child → `File::NULL`, argv без секретов, временных plaintext-файлов нет.
   Ошибки helper'а — фиксированные строки с пустым backtrace (`raise Failure, '...', []`).
2. **safe_load без aliases/классов + cap 2MB + без дампов YAML-исключений** —
   `:10, :67-78`: `YAML.safe_load(raw, [], [], false)` (Psych 3 / system Ruby 2.6),
   чтение `SOURCE_LIMIT+1`, rescue любого StandardError → `'source_invalid'`.
   Файл только `rb`, `stat.file? && uid == Process.uid` на открытом дескрипторе.
3. **Whitelist: только Codex grant.access+accountId (алиасы согласованы) и 3+1 известных ref** —
   `:30-64`: только `llm-pi-ai/openai-codex` с `kind=='grant'`/`type=='oauth'`;
   `accountId|chatgpt_account_id|account_id` обязаны совпадать (`ids.uniq.length > 1` → reject),
   нестроковый id → reject; payload собирается заново — `refresh` и чужие records/refs
   физически не копируются. REFS — ровно 4 известных имени (DeepSeek — только при явном ref).
4. **Identity-гейт до секрета, версия, канонический путь** — `:92-100, :161-173`:
   verify ДО stop и повторно ПОСЛЕ stop, до spawn приёмника; realpath-якорь бинаря;
   `verify-install.sh` (team == expected-team.local, Apple Development authority,
   точные bundle id/Identifier подписи, закрытые множества entitlements,
   `codesign -vvv --deep`); CFBundleVersion == '7' (v6 проигнорировал бы флаг и
   ушёл бы в GUI — корректно отвергнут). См. IN-01 про `==` vs `>=`.
5. **Отчёт child парсится и whitelist'ится, не эхо** — `:133, :138-159`: closed-формы
   (provider ∈ PROVIDERS, enums import/request_status, только percent/resets_at числа,
   ≤32 окна, error → фиксированный литерал); переполнение stdout → Failure без
   сохранения данных. Root-отчёт в `main` = sanitize-результат + metadata + reopened.
6. **Жизненный цикл: свой stop verified, reopen при любом исходе** — `stop-installed.sh`
   (identity до сигнала, ровно один экземпляр, без KILL, без запуска, коды 2/4/5/6/7 —
   fail closed); `import()` — `ensure reopened = reopen` после входа в begin;
   `success && reopened` в итоге. Если stop упал — begin не входили, GUI нами не
   останавливался, reopen не нужен: корректно. Источник не модифицируется.
7. **CLI-ветка: init до activate, bounded 64KiB, без UI/таймера/двойного писателя** —
   `AiUsageApp.swift:21-30` (ветка до создания модели/сцен, `RunLoop.main.run()` внутри
   init — SwiftUI-сцены не конструируются, `activate()` не вызывается);
   `ProviderAccess.swift:752-818`: single-instance guard по bundle id + resolved exe
   path; `readBounded` (65_536, короткое чтение ≠ EOF, пустой/битый ввод →
   `invalid_input` до любой записи в Keychain); закрытое множество корневых ключей;
   `applyImport(autoRefreshAfterImport: false)` + ровно один `await refreshAll()`
   через RefreshGate (без параллельных проходов); Codex — тот же атомарный конверт
   (CR-02), парсер — чистый `CredentialImportFile` без сети/Keychain.
8. **Replace только по явному флагу; чужие аккаунты не трогаются; экспорта нет** —
   `:501-518, :773-774`: `replaceExisting` только из `--replace-existing`;
   без него present/needsReimport → `skipped_existing`, unavailable → `keychain_failed`;
   пишутся только слоты провайдеров из payload; whole-account export отсутствует.
9. **Stdout: только известные статусы/агрегаты, фиксированная ошибка; cache_write_failed
   честный** — `:778-809`: ключи отчёта фиксированы, accountId/токены/сырые тела/заголовки
   отсутствуют по построению; `error` — литерал `usage_request_failed`;
   `cache_write_failed` = фактический флаг модели (не Success при отказе записи);
   exit 0 только при imported или all skipped_existing.
10. **Нестроковый accountID отвергает только свою запись (WR-06)** —
    `CredentialImport.swift:135-137, 172-175, 194-196` + `str()` в
    ProviderAdapters.swift:119: запись пропускается с фиксированным именем, остальные
    провайдеры импортируются; сырые значения пропущенных записей в вывод не попадают.
11. **Expired Codex: без refresh/rotate, без model-API** — `CodexAdapter.buildProbe`
    (ProviderAdapters.swift:320-330): единственный GET `chatgpt.com/backend-api/wham/usage`;
    refresh_token нигде не читается (grep по пакету — ноль вхождений использования);
    401 → фиксированная подсказка о реимпорте. Один GET при явном импорте — в рамках
    авторизации владельца.
12. **Без legacy-DP миграции и broad sharing; entitlements не расширены сверх задуманного** —
    classic keychain без `kSecUseDataProtectionKeychain`; legacy-слоты v3–v5 не
    мигрируют и не участвуют в HTTP; appex-множество прав ровно {sandbox, groups},
    keychain-access-groups отвергаются верификатором; добавление app-права
    user-selected.read-only — задокументированная часть этого change-set (NSOpenPanel).
13. **Тесты** — приняты как заявленные родителем (11 Ruby-файловых кейсов / 88 assert'ов,
    66 Swift), не перезапускались; покрытие соответствует свойствам: sentinel-негативы
    на stdout/stderr/argv/env, YAML-негативы, sanitize-негативы, порядок
    verify→stop→verify→receive→reopen (dsh-import-test.rb:121-133).

## Critical Issues

Отсутствуют.

## Warnings

### WR-01: `Runner#receive` ждёт child без таймаута — при зависшем приёмнике GUI остаётся остановленным

**File:** `scripts/import-dsh-credentials.rb:117-131`
**Issue:** Блокирующий цикл `stdout.read(4096)` ждёт EOF без дедлайна. Приёмник —
верифицированный v7, и его сеть ограничена 10/15-секундными таймаутами
(`ProviderAccess.swift:307-315`), но любое иное зависание (Keychain-блокировка,
RunLoop без выхода) оставляет helper висящим вечно: `ensure reopened = reopen`
выполнится только после возврата/исключения из `receive`, то есть остановленный
GUI не переоткроется без ручного вмешательства. Утечки секрета нет — это риск
доступности собственного GUI владельца.
**Fix:** обернуть чтение в дедлайн, например:
```ruby
require 'timeout'
status = nil
Timeout.timeout(120) do
  # ... цикл чтения stdout ...
  status = wait.value
end
```
Таймаут → `Failure` → сработает `ensure reopen`. 120 с покрывает worst case
(5 провайдеров × 15 с resource-timeout + keychain).

## Info

### IN-01: Проверка версии — точное `== '7'`, а не `>= 7`

**File:** `scripts/import-dsh-credentials.rb:96-100`
**Issue:** Требование задания сформулировано как «>= version 7»; реализовано точное
равенство (намеренно: v6 игнорирует флаг и ушёл бы в GUI вместо stdin). Направление
fail-closed, но сборка v8 потребует правки константы — иначе импорт откажет на
свежей версии.
**Fix:** при переходе на v8+ заменить на разбор числа с нижней границей
(`version.strip.to_i >= 7` при непустом значении).

### IN-02: TOCTOU между вторым `verify` и `popen2` бинаря

**File:** `scripts/import-dsh-credentials.rb:161-167`
**Issue:** Между успешной повторной верификацией и exec `@binary` существует окно
подмены бандла. Практическая эксплуатация требует локальной записи в
`~/Applications` под пользователем владельца в момент ручного запуска — при таких
правах атакующий и так может исполнить произвольный код от имени владельца;
гейт не усиливаем (нет нового тяжёлого сценария).
**Fix:** необязательно; при желании — exec через заранее открытый fd
(`POSIX spawn` по дескриптору), но это усложнение ради уже скомпрометированной модели.

### IN-03: Позиционная сигнатура `YAML.safe_load` привязана к Psych 3

**File:** `scripts/import-dsh-credentials.rb:73`
**Issue:** `YAML.safe_load(raw, [], [], false)` корректна для системного Ruby 2.6
(Psych 3), на который указывает shebang `#!/usr/bin/ruby`. Под Psych 4 (Ruby 3.1+)
позиционные аргументы бросают ArgumentError → generic `source_invalid` — отказ
закрытый, утечки нет, но запуск «другим ruby» молча сломает импорт.
**Fix:** необязательно; либо зафиксировать требование system ruby в usage-строке.

---

_Reviewed: 2026-10-18T21:30Z_
_Reviewer: Kimi (k3-256k), независимый от Sol-авторства; роль gsd-code-reviewer_
_Depth: standard_
_Ограничения: read-only; живые чтения ~/.dsh, реальные --import/--inspect, Keychain,
provider API, сборки, процессы и коммиты НЕ выполнялись. Фоновый build v7
(bgp_150e60e6a001c9722qU3X45nGw) не тронут. NoLiveAccounts — фактический прогон
за владельцем после приёмки._
