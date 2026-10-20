#!/bin/bash
# stop-installed.sh — ТОЧНЫЙ stop-only переход (план 01-03-T2, ревизия 5; угроза T-01-12,
# исправления CR-04/WR-02 из 01-CODE-REVIEW).
#
# Останавливает РОВНО экземпляр СВОЕГО установленного приложения и НИЧЕГО не запускает.
#   • Цель фиксирована: канонический путь "$HOME/Applications/AI Usage Widget.app".
#     Аргументов пути НЕТ (в т.ч. --self-test) — защита от наведения на чужие пути.
#   • Identity ДО любого сигнала: CFBundleIdentifier = com.serzhsharapa.aiusage и
#     TeamIdentifier (codesign) == ожидаемой команде из scripts/expected-team.local,
#     плюс ЦЕЛОСТНОСТЬ старого бандла (codesign --verify: правленый Info.plist ломает
#     seal) и CFBundleExecutable — РОВНО имя нашего продукта «AI Usage Widget»
#     (pbxproj PRODUCT_NAME; безопасный basename: без «/», «.», «..» — traversal
#     невозможен; пробелы в имени легитимны). Чужой объект / кривой конфиг = FAIL
#     без единого сигнала и без перемещений.
#   • Поиск и остановка процесса — НЕ через строку `ps … command=` (это argv процесса:
#     подменяется и не различает имена с пробелами), а через native-помощник
#     scripts/procstop/main.swift: ФАКТИЧЕСКИЙ путь исполняемого файла от ядра
#     (proc_pidpath) + идентичность ЭКЗЕМПЛЯРА (время старта, PROC_PIDTBSDINFO) —
#     точное строковое равенство с якорем «<бандл>/Contents/MacOS/<CFBundleExecutable>»,
#     перепроверка НЕПОСРЕДСТВЕННО перед TERM и на каждом шаге ожидания (CR-04).
#     ГРАНИЦА (CR-04, раунд 2): канонический якорь обязан быть РОВНО
#     <canonical-root>/Contents/MacOS/<basename> — traversal в CFBundleExecutable и
#     symlink-побег executable отвергаются ДО помощника; помощник дополнительно
#     проверяет ту же границу сам (--stop <bundle-root> <exe> <timeout>: цель вне
#     Contents/MacOS данного бандла не выражается никаким путём).
#     Стартовые аргументы процесса (например, Debug-инъекция 01-04-T3) поддерживаются
#     естественно: аргументы не участвуют в сравнении.
#   • Ровно ОДИН экземпляр: ни одного совпадения — «не запущен» (rc 0); несколько —
#     неоднозначно, НИ ОДНОГО сигнала (fail closed).
#   • Отказ перечисления процессов — ОТДЕЛЬНЫЙ отказ инспекции (WR-02): НЕ «не запущен»
#     и НЕ подтверждённый выход; замена установки в этом состоянии не разрешена.
#   • TERM → ожидание ФАКТИЧЕСКОГО выхода с фиксированным таймаутом
#     (AIUSAGE_STOP_TIMEOUT, по умолчанию 10 с; тестовое переопределение, не ослабляет
#     безопасность). Таймаут или смена идентичности PID = FAIL, БЕЗ эскалации на KILL,
#     БЕЗ запуска.
#
# Помощник procstop: переопределение AIUSAGE_PROCSTOP_BIN (полный путь к исполняемому
# файлу) для тестов; по умолчанию — сборка по требованию из scripts/procstop/main.swift
# в $HOME/Library/Caches/ai-usage/procstop-helper (пересборка при изменении исходника,
# контрольная сумма SHA-256; только системные фреймворки, внешних зависимостей нет).
#
# Выход: 0 — не установлено / не запущен / подтверждённый выход; 1 — FAIL; 2 — использование.
# bash 3.2 совместим.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$HOME/Applications/AI Usage Widget.app"
EXPECT_BUNDLE_ID="com.serzhsharapa.aiusage"
# Имя исполняемого файла продукта (pbxproj: PRODUCT_NAME = "AI Usage Widget").
# Литерал — не taken из Info.plist: «допустимое имя» не может быть выбрано входом.
EXPECT_EXECUTABLE="AI Usage Widget"
STOP_TIMEOUT="${AIUSAGE_STOP_TIMEOUT:-10}"

fail() { # причина, следующий шаг
  printf 'FAIL: %s\n' "$1" >&2
  [ -n "${2:-}" ] && printf 'Следующий шаг: %s\n' "$2" >&2
  exit 1
}

# Ожидаемая команда владельца — тот же контракт, что в verify-install.sh (план 01-03-T1, п. b)
load_expected_team() {
  local cfg="${AIUSAGE_EXPECTED_TEAM_FILE:-$SCRIPT_DIR/expected-team.local}" team
  if [ ! -f "$cfg" ]; then
    printf 'FAIL: конфиг-ожидаемой-команды: файл %s не найден — сигналов не отправлено.\n' "$cfg" >&2
    printf 'Следующий шаг: создай файл по docs/phase-01-setup.ru.md (раздел 6а) — одна строка TeamID из Xcode > Settings > Accounts.\n' >&2
    return 1
  fi
  team="$(tr -d '[:space:]' < "$cfg")"
  if [ -z "$team" ]; then
    printf 'FAIL: конфиг-ожидаемой-команды: файл пуст — сигналов не отправлено.\n' >&2
    printf 'Следующий шаг: впиши одну строку TeamID (10 латинских букв/цифр) из Xcode > Settings > Accounts.\n' >&2
    return 1
  fi
  if ! printf '%s' "$team" | grep -Eq '^[A-Za-z0-9]{10}$'; then
    printf 'FAIL: конфиг-ожидаемой-команды: содержимое не похоже на TeamID — сигналов не отправлено.\n' >&2
    printf 'Следующий шаг: исправь %s (TeamID — из Xcode/аккаунта, НЕ из подписи продукта).\n' "$cfg" >&2
    return 1
  fi
  printf '%s' "$team"
}

# Бинарник помощника procstop: явное переопределение или сборка по требованию с контролем версии.
procstop_resolve() { # печатает путь к исполняемому файлу помощника; rc≠0 = FAIL с причиной
  local override src cache bin sha
  override="${AIUSAGE_PROCSTOP_BIN:-}"
  if [ -n "$override" ]; then
    if [ ! -x "$override" ]; then
      printf 'FAIL: помощник procstop не исполняем: %s — сигналов не отправлено.\n' "$override" >&2
      printf 'Следующий шаг: укажи существующий бинарник в AIUSAGE_PROCSTOP_BIN или сними переопределение (сборка из scripts/procstop/main.swift выполнится сама).\n' >&2
      return 1
    fi
    printf '%s' "$override"
    return 0
  fi
  src="$SCRIPT_DIR/procstop/main.swift"
  if [ ! -f "$src" ]; then
    printf 'FAIL: исходник помощника не найден: %s — сигналов не отправлено.\n' "$src" >&2
    printf 'Следующий шаг: восстанови файл из репозитория и повтори.\n' >&2
    return 1
  fi
  cache="$HOME/Library/Caches/ai-usage"
  bin="$cache/procstop-helper"
  sha="$(shasum -a 256 "$src" | cut -d' ' -f1)"
  if [ -x "$bin" ] && [ "$(cat "$cache/procstop-helper.sha" 2>/dev/null || true)" = "$sha" ]; then
    printf '%s' "$bin"
    return 0
  fi
  if ! command -v swiftc >/dev/null 2>&1; then
    printf 'FAIL: swiftc не найден — помощника procstop нечем собрать, сигналов не отправлено.\n' >&2
    printf 'Следующий шаг: установи Xcode (или Command Line Tools: xcode-select --install) и повтори.\n' >&2
    return 1
  fi
  mkdir -p "$cache" || { printf 'FAIL: не создан каталог кэша %s.\n' "$cache" >&2; return 1; }
  if ! swiftc -O -o "$bin.new" "$src"; then
    rm -f "$bin.new"
    printf 'FAIL: сборка помощника procstop не удалась — сигналов не отправлено.\n' >&2
    printf 'Следующий шаг: проверь сообщения компилятора выше; файл-источник scripts/procstop/main.swift.\n' >&2
    return 1
  fi
  mv -f "$bin.new" "$bin"
  printf '%s\n' "$sha" > "$cache/procstop-helper.sha"
  printf '%s' "$bin"
}

stop_installed_instance() {
  [ -d "$APP_PATH" ] || { printf 'не установлено: бандл не найден (%s); ни одного сигнала.\n' "$APP_PATH"; return 0; }

  local EXPECTED_TEAM
  EXPECTED_TEAM="$(load_expected_team)" || return 1

  # identity ДО любого сигнала
  local bid
  bid="$(plutil -extract CFBundleIdentifier raw -o - "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
  if [ "$bid" != "$EXPECT_BUNDLE_ID" ]; then
    fail "чужой объект по каноническому пути: CFBundleIdentifier='${bid:-отсутствует}', ожидался $EXPECT_BUNDLE_ID. НИ ОДНОГО сигнала, объект не тронут и не перемещён." \
         "это не наше приложение — проверь ~/Applications вручную; подмена/конфликт имён требует решения владельца"
  fi
  local exe
  exe="$(plutil -extract CFBundleExecutable raw -o - "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
  [ -n "$exe" ] || fail "не читается CFBundleExecutable бандла — сигналов не отправлено." "проверь целостность $APP_PATH"
  # CR-04 (раунд 2): строго безопасный basename И ровно имя нашего продукта.
  # Пробелы легитимны («AI Usage Widget»); «/», «.»/«..» и любые чужие имена — нет:
  # traversal не выражается, sibling-имя («… Helper») не проходит.
  case "$exe" in
    */*|"."|".."|*..*)
      fail "CFBundleExecutable='$exe' не является безопасным именем файла (traversal/составной путь) — целостность бандла нарушена; НИ ОДНОГО сигнала." \
           "проверь установку: bash scripts/verify-install.sh; при подозрении на подмену — реши владельцем"
      ;;
  esac
  if [ "$exe" != "$EXPECT_EXECUTABLE" ]; then
    fail "CFBundleExecutable='$exe' не равен имени продукта '$EXPECT_EXECUTABLE' — целостность бандла нарушена; НИ ОДНОГО сигнала." \
         "проверь установку: bash scripts/verify-install.sh"
  fi

  local dv team
  dv="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1 || true)"
  team="$(printf '%s\n' "$dv" | grep -m1 '^TeamIdentifier=' | cut -d= -f2- || true)"
  case "$team" in ""|"not set"|"NOT SET")
    fail "бандл по каноническому пути подписан без TeamIdentifier (ad-hoc?) — сигналов не отправлено." "проверь установку: bash scripts/verify-install.sh"
    ;;
  esac
  if [ "$team" != "$EXPECTED_TEAM" ]; then
    fail "чужой объект по каноническому пути: TeamIdentifier='$team' не равен ожидаемой команде владельца (сравнение — да/нет; значение конфига не печатается). НИ ОДНОГО сигнала, объект не тронут." \
         "это не наша сборка — проверь ~/Applications вручную; дальнейшие действия решает владелец"
  fi
  # Целостность СТАРОГО бандла (CR-04, раунд 2): codesign -dv читает только
  # метаданные; --verify проверяет seal подписи — правленый Info.plist (в т.ч.
  # подменённый CFBundleExecutable) делает проверку неудачной.
  if ! codesign --verify --strict --deep "$APP_PATH" >/dev/null 2>&1; then
    fail "целостность подписи установленного бандла не подтверждена (codesign --verify) — возможно, бандл правлен; НИ ОДНОГО сигнала." \
         "проверь установку: bash scripts/verify-install.sh; при подтверждении подмены — удали и пересобери (bash scripts/build.sh)"
  fi
  printf 'identity подтверждена: CFBundleIdentifier=%s, TeamIdentifier=%s == ожидаемой команде; целостность подписи — ok.\n' "$bid" "$team"

  # Граница цели (CR-04, раунд 2): канонические пути ДО любого обращения к
  # помощнику. Contents и MacOS обязаны быть реальными каталогами ВНУТРИ
  # канонического корня бандла, а исполняемый файл — НЕ symlink (realpath
  # совпадает с литеральной конкатенацией) — иначе traversal/symlink-побег.
  local app_real macos_real exe_real anchor
  app_real="$(cd "$APP_PATH" && pwd -P)" || fail "не удалось канонизировать путь бандла — сигналов не отправлено." "проверь $APP_PATH"
  macos_real="$(cd "$APP_PATH/Contents/MacOS" && pwd -P)" || fail "в бандле нет Contents/MacOS — сигналов не отправлено." "проверь целостность $APP_PATH"
  [ "$macos_real" = "$app_real/Contents/MacOS" ] || fail "Contents/MacOS разрешается вне канонического корня бандла (symlink?) — НИ ОДНОГО сигнала." "проверь целостность $APP_PATH"
  anchor="$APP_PATH/Contents/MacOS/$exe"
  [ -e "$anchor" ] || fail "исполняемый файл бандла не найден: $anchor — сигналов не отправлено." "проверь целостность $APP_PATH"
  exe_real="$(realpath "$anchor")" || fail "не удалось канонизировать путь исполняемого файла — сигналов не отправлено." "проверь права на $APP_PATH"
  [ "$exe_real" = "$macos_real/$exe" ] || fail "исполняемый файл разрешается за пределами Contents/MacOS (symlink-побег?) — НИ ОДНОГО сигнала." "проверь целостность $APP_PATH; при подозрении на подмену — реши владельцем"

  # Помощник: единственный источник сигнала; коды выхода — контракт ниже.
  # Аргументы: --stop <bundle-root> <exe-path> <timeout> — помощник сам
  # дополнительно проверяет границу «canonical(exe) == canonical(root)/Contents/MacOS/<basename>».
  local helper
  helper="$(procstop_resolve)" || return 1
  printf 'поиск и остановка по фактическому пути исполняемого файла ядра (граница — Contents/MacOS бандла): %s\n' "$anchor"
  set +e
  "$helper" --stop "$APP_PATH" "$anchor" "$STOP_TIMEOUT"
  local hrc=$?
  set -e
  case "$hrc" in
    0)
      printf 'остановлено: подтверждён фактический выход единственного точного экземпляра.\n'
      return 0
      ;;
    3)
      printf 'не запущен: ни один процесс не имеет точного пути исполняемого файла; ни одного сигнала.\n'
      return 0
      ;;
    2)
      fail "не удалось перечислить процессы/пути ядра или инспекция неопределена (нечитаемый путь собственного PID?) — состояние НЕ известно: ни «не запущен», ни «вышел» не подтверждено; замена НЕ разрешена." \
           "проверь систему (proc_listpids/proc_pidpath) и повтори; замена сборки не выполнялась"
      ;;
    4)
      fail "несколько процессов исполняют точный путь бандла — неоднозначно; НИ ОДНОГО сигнала." \
           "закрой лишние экземпляры вручную (Activity Monitor) и повтори"
      ;;
    5)
      fail "идентичность экземпляра изменилась до/после сигнала (re-use PID?) — сигнал не отправлен/не повторён." \
           "повтори запуск позже; процесс не наш — трогать его нельзя"
      ;;
    6)
      fail "процесс не вышел за ${STOP_TIMEOUT} с после TERM — FAIL без эскалации (KILL не отправляется, ничего не запускается)." \
           "закрой приложение вручную и повтори; замена сборки не выполнялась"
      ;;
    7)
      fail "цель вне границы Contents/MacOS бандла (traversal/symlink) — НИ ОДНОГО сигнала." \
           "проверь целостность $APP_PATH; при подозрении на подмену — реши владельцем"
      ;;
    *)
      fail "помощник procstop завершился с неожидаемым кодом $hrc — сигналы не подтверждены, замена НЕ разрешена." \
           "см. сообщение помощника выше; повтори запуск"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# SELF-TEST (план 01-03-T2, п. 2e; ревизия 5 — CR-04/WR-02): синтетические
# фикстуры и заглушка помощника procstop в изолированном HOME/PATH; реальные
# процессы, настоящие сигналы и реальная установка не затрагиваются.
# Живые проверки самого помощника (точное совпадение, argv-spoof, неоднозначность,
# таймаут) выполняются отдельной пробой scripts/procstop/main.swift на
# собственном фикстурном процессе — см. 01-REMEDIATION.json.
# ---------------------------------------------------------------------------
self_test() {
  local S SCRIPT_ABS total=0 failed=0
  T="$(mktemp -d "${TMPDIR:-/tmp}/aiusage-stop-selftest.XXXXXX")"   # T глобальная — trap EXIT дочистит
  trap 'if [ -n "${T:-}" ]; then rm -rf "$T"; fi' EXIT
  SCRIPT_ABS="$SCRIPT_DIR/stop-installed.sh"

  st_setup() { # имя сценария → готовит песочницу $S; бандл с нашей identity по умолчанию
    S="$T/$1"
    mkdir -p "$S/bin" "$S/home/Applications/AI Usage Widget.app/Contents/MacOS" \
             "$S/home/Applications/AI Usage Widget.app/Contents/PlugIns"
    cat > "$S/bin/codesign" <<'STUB'
#!/bin/bash
# codesign stub (self-test)
cat "$AIUSAGE_STUB_DV" >&2
exit 0
STUB
    cat > "$S/bin/procstop-stub" <<'STUB'
#!/bin/bash
# procstop stub (self-test): фиксирует вызов и печатает/выходит по окружению
printf '%s\n' "$*" >> "$AIUSAGE_STUB_CALLS"
[ -n "${AIUSAGE_STUB_OUT:-}" ] && printf '%s\n' "$AIUSAGE_STUB_OUT"
exit "${AIUSAGE_STUB_EXIT:-0}"
STUB
    cat > "$S/bin/kill" <<'STUB'
#!/bin/bash
# kill canary (self-test): настоящий скрипт НИКОГДА не должен звать kill сам
printf 'kill %s\n' "$*" >> "$AIUSAGE_STUB_SIGNALS"
exit 0
STUB
    cat > "$S/bin/open" <<'STUB'
#!/bin/bash
# open stub (self-test): запускать ничего не должен; фиксирует вызовы
printf 'open %s\n' "$*" >> "$AIUSAGE_STUB_LAUNCHES"
exit 1
STUB
    chmod +x "$S/bin/"*
    # Info.plist бандла: наша identity по умолчанию
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n\t<key>CFBundleIdentifier</key>\n<string>com.serzhsharapa.aiusage</string>\n\t<key>CFBundleExecutable</key>\n\t<string>AI Usage Widget</string>\n\t<key>AppGroupID</key>\n\t<string>TESTTEAMID.group.aiusage</string>\n</dict>\n</plist>\n' > "$S/home/Applications/AI Usage Widget.app/Contents/Info.plist"
    # Реальный (пустой) файл исполняемого имени: обёртка проверяет его существование
    # и отсутствие symlink-побега ДО любого обращения к помощнику.
    printf '#!/bin/sh\n' > "$S/home/Applications/AI Usage Widget.app/Contents/MacOS/AI Usage Widget"
    printf 'TESTTEAMID\n' > "$S/expected-team.local"
    printf 'Executable=/fixture/AI Usage Widget.app/Contents/MacOS/AI Usage Widget\nIdentifier=com.serzhsharapa.aiusage\nAuthority=Apple Development: Fixture Owner (TESTTEAMID)\nTeamIdentifier=TESTTEAMID\n' > "$S/team-dv.txt"
    : > "$S/calls.log"; : > "$S/signals.log"; : > "$S/launches.log"
  }

  st_run() { # запускает stop-installed.sh в песочнице; код возврата — в $ST_RC (всегда return 0)
    set +e
    ( PATH="$S/bin:/usr/bin:/bin" \
        HOME="$S/home" \
        AIUSAGE_EXPECTED_TEAM_FILE="$S/expected-team.local" \
        AIUSAGE_STOP_TIMEOUT="${ST_TIMEOUT:-2}" \
        AIUSAGE_PROCSTOP_BIN="$S/bin/procstop-stub" \
        AIUSAGE_STUB_CALLS="$S/calls.log" \
        AIUSAGE_STUB_SIGNALS="$S/signals.log" \
        AIUSAGE_STUB_LAUNCHES="$S/launches.log" \
        AIUSAGE_STUB_EXIT="${ST_EXIT:-0}" \
        AIUSAGE_STUB_OUT="${ST_OUT:-}" \
        AIUSAGE_STUB_DV="$S/team-dv.txt" \
        bash "$SCRIPT_ABS" ) > "$S/out.txt" 2>&1
    ST_RC=$?
    set -e
    return 0
  }

  assert() { # описание, команда-проверка…
    local desc="$1"; shift
    total=$((total+1))
    if "$@"; then printf '  ok   %s\n' "$desc"; else printf '  FAIL %s\n' "$desc" >&2; failed=$((failed+1)); fi
  }
  signals_empty()  { [ ! -s "$S/signals.log" ]; }
  no_launches()    { [ ! -s "$S/launches.log" ]; }
  out_contains()   { grep -q "$1" "$S/out.txt"; }
  helper_calls()   { [ "$(wc -l < "$S/calls.log" | tr -d ' ')" = "$1" ]; }
  helper_got_stop_anchor() { # ровно один --stop <root> <anchor> с точным якорем бандла
    grep -c -- "--stop $S/home/Applications/AI Usage Widget.app $S/home/Applications/AI Usage Widget.app/Contents/MacOS/AI Usage Widget " "$S/calls.log" | grep -qx '1'
  }

  printf 'self-test stop-installed.sh (заглушка procstop/codesign/kill/open, изолированный HOME):\n'

  # (1) запущен ровно один наш экземпляр → помощник подтверждает выход
  st_setup "ok-stop"
  ST_OUT=$'TERM отправлен точному экземпляру PID 1111 (путь ядра совпал, старт 1791759632).\nподтверждён фактический выход PID 1111.'
  ST_EXIT=0
  st_run; RC1=$ST_RC
  ST_OUT=""; ST_EXIT=0
  assert "(1) подтверждён выход, rc=0"                    [ "$RC1" -eq 0 ]
  assert "(1) сообщение о подтверждённом выходе"          out_contains 'подтверждён фактический выход PID 1111'
  assert "(1) помощник вызван ровно один раз"             helper_calls 1
  assert "(1) якорь — точный путь бандла (--stop)"        helper_got_stop_anchor
  assert "(1) скрипт не звал kill сам"                    signals_empty
  assert "(1) ничего не запущено"                         no_launches

  # (2a) чужой CFBundleIdentifier по каноническому пути → FAIL ДО помощника
  st_setup "foreign-bid"
  sed -i '' 's/com.serzhsharapa.aiusage/com.evil.other.app/' "$S/home/Applications/AI Usage Widget.app/Contents/Info.plist"
  st_run; RC2=$ST_RC
  assert "(2a) чужой CFBundleIdentifier → FAIL"          [ "$RC2" -ne 0 ]
  assert "(2a) явная причина"                            out_contains 'FAIL: чужой объект'
  assert "(2a) помощник не вызывался"                    helper_calls 0
  assert "(2a) ничего не запущено"                       no_launches

  # (2b) чужой TeamIdentifier → FAIL ДО помощника
  st_setup "foreign-team"
  sed -i '' 's/TeamIdentifier=TESTTEAMID/TeamIdentifier=OTHERTEAM1/' "$S/team-dv.txt"
  st_run; RC2B=$ST_RC
  assert "(2b) чужой TeamIdentifier → FAIL"              [ "$RC2B" -ne 0 ]
  assert "(2b) помощник не вызывался"                    helper_calls 0
  assert "(2b) ничего не запущено"                       no_launches

  # (2c) CR-04: CFBundleExecutable с traversal → FAIL ДО помощника
  st_setup "traversal-exe"
  sed -i '' 's#<string>AI Usage Widget</string>#<string>../../evil</string>#' "$S/home/Applications/AI Usage Widget.app/Contents/Info.plist"
  st_run; RC2C=$ST_RC
  assert "(2c) traversal CFBundleExecutable → FAIL"      [ "$RC2C" -ne 0 ]
  assert "(2c) причина — небезопасное имя"               out_contains 'не является безопасным именем файла'
  assert "(2c) помощник не вызывался"                    helper_calls 0
  assert "(2c) ничего не запущено"                       no_launches

  # (2d) CR-04: executable — symlink наружу → FAIL ДО помощника
  st_setup "symlink-exe"
  printf 'external fixture\n' > "$S/external-target"
  rm "$S/home/Applications/AI Usage Widget.app/Contents/MacOS/AI Usage Widget"
  ln -s "$S/external-target" "$S/home/Applications/AI Usage Widget.app/Contents/MacOS/AI Usage Widget"
  st_run; RC2D=$ST_RC
  assert "(2d) symlink-побег executable → FAIL"          [ "$RC2D" -ne 0 ]
  assert "(2d) причина — выход за Contents/MacOS"        out_contains 'за пределами Contents/MacOS'
  assert "(2d) помощник не вызывался"                    helper_calls 0
  assert "(2d) ничего не запущено"                       no_launches

  # (2e) CR-04: безопасное, но ЧУЖОЕ имя (sibling «… Helper») → FAIL ДО помощника
  st_setup "sibling-exe"
  sed -i '' 's#<string>AI Usage Widget</string>#<string>AI Usage Widget Helper</string>#' "$S/home/Applications/AI Usage Widget.app/Contents/Info.plist"
  mv "$S/home/Applications/AI Usage Widget.app/Contents/MacOS/AI Usage Widget" "$S/home/Applications/AI Usage Widget.app/Contents/MacOS/AI Usage Widget Helper"
  st_run; RC2E=$ST_RC
  assert "(2e) sibling-имя executable → FAIL"            [ "$RC2E" -ne 0 ]
  assert "(2e) причина — не имя продукта"                out_contains 'не равен имени продукта'
  assert "(2e) помощник не вызывался"                    helper_calls 0
  assert "(2e) ничего не запущено"                       no_launches

  # (3) отказ/неопределённость инспекции процессов (WR-02) — НЕ «не запущен»
  st_setup "inspect-fail"; ST_EXIT=2; st_run; RC3=$ST_RC; ST_EXIT=0
  assert "(3) отказ инспекции → FAIL"                    [ "$RC3" -ne 0 ]
  assert "(3) причина — неизвестность состояния"         out_contains 'состояние НЕ известно'
  assert "(3) ничего не запущено"                        no_launches

  # (4) таймаут выхода → FAIL, без эскалации
  st_setup "timeout"
  ST_EXIT=6
  ST_OUT='FAIL: PID 4444 не вышел за 2 с после TERM — эскалации нет (KILL не отправляется, ничего не запускается).'
  st_run; RC4=$ST_RC
  ST_OUT=""; ST_EXIT=0
  assert "(4) таймаут выхода → FAIL"                     [ "$RC4" -ne 0 ]
  assert "(4) причина названа"                           out_contains 'не вышел'
  assert "(4) помощник вызван один раз (без повторов)"   helper_calls 1
  assert "(4) ничего не запущено"                        no_launches

  # (5) смена идентичности (re-use PID) → FAIL без повторных сигналов
  st_setup "pidreuse"; ST_EXIT=5; st_run; RC5=$ST_RC; ST_EXIT=0
  assert "(5) re-use PID → FAIL"                         [ "$RC5" -ne 0 ]
  assert "(5) причина названа"                           out_contains 'идентичность'
  assert "(5) ничего не запущено"                        no_launches

  # (6) несколько экземпляров — неоднозначно, сигналов нет
  st_setup "ambiguous"; ST_EXIT=4; st_run; RC6=$ST_RC; ST_EXIT=0
  assert "(6) несколько экземпляров → FAIL"              [ "$RC6" -ne 0 ]
  assert "(6) причина — неоднозначность"                 out_contains 'неоднозначно'
  assert "(6) ничего не запущено"                        no_launches

  # (7a) не установлено
  st_setup "notinstalled"
  rm -rf "$S/home/Applications/AI Usage Widget.app"
  st_run; RC7A=$ST_RC
  assert "(7a) не установлено → rc=0"                    [ "$RC7A" -eq 0 ]
  assert "(7a) сообщение «не установлено»"               out_contains 'не установлено'
  assert "(7a) помощник не вызывался"                    helper_calls 0
  assert "(7a) ничего не запущено"                       no_launches

  # (7b) установлено, но не запущен (helper rc=3)
  st_setup "notrunning"; ST_EXIT=3; st_run; RC7B=$ST_RC; ST_EXIT=0
  assert "(7b) не запущен → rc=0"                        [ "$RC7B" -eq 0 ]
  assert "(7b) сообщение «не запущен»"                   out_contains 'не запущен'
  assert "(7b) ничего не запущено"                       no_launches

  # (8) конфиг ожидаемой команды: отсутствует / пустой
  st_setup "nocfg"; rm -f "$S/expected-team.local"; st_run; RC8A=$ST_RC
  assert "(8a) конфиг отсутствует → FAIL"                [ "$RC8A" -ne 0 ]
  assert "(8a) помощник не вызывался"                    helper_calls 0
  assert "(8a) ничего не запущено"                       no_launches

  st_setup "emptycfg"; : > "$S/expected-team.local"; st_run; RC8B=$ST_RC
  assert "(8b) конфиг пуст → FAIL"                       [ "$RC8B" -ne 0 ]
  assert "(8b) помощник не вызывался"                    helper_calls 0
  assert "(8b) ничего не запущено"                       no_launches

  # (9) переопределённый помощник не исполняем — отказ ДО любых сигналов
  st_setup "badhelper"
  set +e
  ( PATH="$S/bin:/usr/bin:/bin" HOME="$S/home" \
      AIUSAGE_EXPECTED_TEAM_FILE="$S/expected-team.local" \
      AIUSAGE_STUB_DV="$S/team-dv.txt" \
      AIUSAGE_PROCSTOP_BIN="$S/bin/отсутствует" \
      bash "$SCRIPT_ABS" ) > "$S/out.txt" 2>&1
  RC9=$?
  set -e
  assert "(9) неисполняемый помощник → FAIL"             [ "$RC9" -ne 0 ]
  assert "(9) причина названа"                           out_contains 'не исполняем'
  assert "(9) ничего не запущено"                        no_launches

  if [ "$failed" -ne 0 ]; then
    printf 'self-test ЗАВЕРШЁН С ОШИБКАМИ: %d/%d проверок нарушено\n' "$failed" "$total" >&2
    rm -rf "$T"; T=""; exit 1
  fi
  printf 'self-test: %d/%d проверок PASS; изоляция: процессы — только заглушки procstop/kill, настоящих сигналов нет, запусков нет\n' "$total" "$total"
  rm -rf "$T"; T=""
  return 0
}

# ------------------------------- main ---------------------------------------
case "${1:-}" in
  --self-test) self_test ;;
  "") stop_installed_instance ;;
  *)
    printf 'Использование: bash scripts/stop-installed.sh [--self-test]\nАргументов пути НЕТ: цель всегда канонический путь ~/Applications/AI Usage Widget.app.\n' >&2
    exit 2
    ;;
esac
