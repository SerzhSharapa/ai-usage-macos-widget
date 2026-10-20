#!/bin/bash
# diagnostics.sh — сбор диагностики установки БЕЗ секретов и персональных данных
# (план 01-03-T3; D-04, угроза T-01-07; исправление WR-04 из 01-CODE-REVIEW).
#
# Собирает: xcode-select -p; xcodebuild -version; swift --version; sw_vers; КОЛИЧЕСТВО
# codesigning-identity (только число, не список); pluginkit-строку своего bundle id;
# entitlements обоих бандлов (после вырезания имён identity); имена файлов в контейнере
# группы (ТОЛЬКО для доверенном бандле — см. ниже); хвост последнего лога сборки.
#
# WR-04: AppGroupID читается из НЕдоверенного Info.plist установленного бандла.
# Диагностика запускается именно при сломанной/чужой установке, поэтому до любого
# чтения/листинга каталога проверяются:
#   • identity бандла: CFBundleIdentifier == com.serzhsharapa.aiusage И
#     TeamIdentifier подписи == ожидаемой команде из scripts/expected-team.local;
#   • GID ТОЧНО вида <TeamID>.group.aiusage для ожидаемой команды (без ../ и пр.);
#   • канонический конечный путь контейнера (pwd -P) лежит строго внутри
#     ~/Library/Group Containers/<GID> — symlink-побег за границу не допускается.
# При нарушении любого условия секция контейнера ПРОПУСКАЕТСЯ с явным объяснением;
# имена файлов за пределами доверенного контейнера не выгружаются.
#
# Редакция ДО вывода и сохранения: email-адреса, имена identity («Apple Development: <имя>…»),
# токены, приватные ключи, содержимое scripts/expected-team.local. Ничего из связки ключей
# и аккаунтов не выгружается. Отчёт печатается в терминал и сохраняется (отредактированным)
# в $HOME/Library/Logs/ai-usage/diagnostics-<дата>.txt — вне git.
#
# bash 3.2 совместим. Выход: 0 (отчёт собран), 2 — использование.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$HOME/Applications/AI Usage Widget.app"
APPEX_PATH="$APP_PATH/Contents/PlugIns/AiUsageWidget.appex"
APPEX_BUNDLE_ID="com.serzhsharapa.aiusage.widget"
APP_BUNDLE_ID="com.serzhsharapa.aiusage"
GROUP_SUFFIX="group.aiusage"
EXPECTED_TEAM_CFG="${AIUSAGE_EXPECTED_TEAM_FILE:-$SCRIPT_DIR/expected-team.local}"
LOG_DIR="$HOME/Library/Logs/ai-usage"
OUT="$LOG_DIR/diagnostics-$(date +%Y%m%d-%H%M%S).txt"

redact() { # тот же фильтр, что в build.sh — до вывода/сохранения
  sed -E \
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[REDACTED-EMAIL]/g' \
    -e 's/(Apple Development|Apple Distribution|Mac Developer|iPhone Developer): [^(]*\(([A-Za-z0-9]{10})[^)]*\)/\1: [REDACTED] (\2)/g' \
    -e 's/sk-[A-Za-z0-9_-]{8,}/[REDACTED-TOKEN]/g' \
    -e 's/gh[pousr]_[A-Za-z0-9]{16,}/[REDACTED-TOKEN]/g' \
    -e 's/xox[baprs]-[A-Za-z0-9-]{10,}/[REDACTED-TOKEN]/g' \
    -e 's/AKIA[0-9A-Z]{16}/[REDACTED-TOKEN]/g' \
    | awk 'BEGIN{p=0}
        /-----BEGIN [A-Z ]*PRIVATE KEY-----/{p=1; print "[REDACTED-PRIVATE-KEY]"; next}
        /-----END [A-Z ]*PRIVATE KEY-----/{if(p){p=0; next}}
        p{next}
        {print}'
}

section() { # заголовок, команда...
  local title="$1"; shift
  printf '\n== %s ==\n' "$title"
  set +e
  "$@" 2>&1
  set -e
}

# Ожидаемая команда владельца: печатает TeamID или пусто (причина — в вызывающий вывод).
diag_expected_team() {
  local team
  if [ ! -f "$EXPECTED_TEAM_CFG" ]; then printf 'конфиг не найден: %s\n' "$EXPECTED_TEAM_CFG"; return 1; fi
  team="$(tr -d '[:space:]' < "$EXPECTED_TEAM_CFG")"
  if [ -z "$team" ]; then printf 'конфиг пуст: %s\n' "$EXPECTED_TEAM_CFG"; return 1; fi
  if ! printf '%s' "$team" | grep -Eq '^[A-Za-z0-9]{10}$'; then printf 'конфиг не похож на TeamID: %s\n' "$EXPECTED_TEAM_CFG"; return 1; fi
  printf '%s' "$team"
}

# Секция контейнера группы (WR-04): листинг ТОЛЬКО доверенного бандла и канонического пути.
group_container_section() {
  printf '\n== контейнер группы (имена файлов) ==\n'
  if [ ! -d "$APP_PATH" ]; then
    printf 'приложение не установлено: %s\n' "$APP_PATH"
    return 0
  fi
  local bid team gid root cdir root_real cdir_real
  bid="$(plutil -extract CFBundleIdentifier raw -o - "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
  if [ "$bid" != "$APP_BUNDLE_ID" ]; then
    printf 'бандл по каноническому пути НЕ является нашим приложением (CFBundleIdentifier=%s) — перечисление контейнера группы пропущено\n' "${bid:-не прочитан}"
    return 0
  fi
  team="$(diag_expected_team)" || { printf '→ перечисление контейнера группы пропущено (нет доверенной точки отсчёта команды)\n'; return 0; }
  local signed_team dv
  dv="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1 || true)"
  signed_team="$(printf '%s\n' "$dv" | grep -m1 '^TeamIdentifier=' | cut -d= -f2- || true)"
  if [ "$signed_team" != "$team" ]; then
    printf 'бандл подписан другой командой/без команды (TeamIdentifier=%s ≠ ожидаемой) — перечисление контейнера группы пропущено\n' "${signed_team:-не прочитан}"
    return 0
  fi
  gid="$(plutil -extract AppGroupID raw -o - "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
  # WR-04 (раунд 2): ТОЧНОЕ строковое равенство, не regex — в прежнем
  # "^${team}\.${GROUP_SUFFIX}$" вторая точка suffix'а оставалась wildcard и
  # пропускала подмены вида groupXaiusage. Строка сравнивается целиком;
  # канонические проверки пути ниже сохранены.
  if [ "$gid" != "$team.$GROUP_SUFFIX" ]; then
    printf 'AppGroupID не равен В ТОЧНОСТИ <TeamID>.%s ожидаемой команды — перечисление контейнера группы пропущено (значение не выводится)\n' "$GROUP_SUFFIX"
    return 0
  fi
  root="$HOME/Library/Group Containers"
  cdir="$root/$gid"
  if [ ! -d "$cdir" ]; then
    printf 'каталог контейнера не найден: %s (записи ещё не было?)\n' "$cdir"
    return 0
  fi
  # Канонический конечный путь: pwd -P разрешает symlink-и; контейнер обязан
  # разрешаться РОВНО в <корень>/<GID> внутри Group Containers — иначе побег.
  root_real="$(cd "$root" 2>/dev/null && pwd -P || true)"
  cdir_real="$(cd "$cdir" 2>/dev/null && pwd -P || true)"
  if [ -z "$root_real" ] || [ -z "$cdir_real" ] || [ "$cdir_real" != "$root_real/$gid" ]; then
    printf 'канонический путь контейнера выходит за пределы Group Containers (symlink?) — перечисление пропущено\n'
    return 0
  fi
  ls -1 "$cdir" 2>/dev/null || printf '(пусто или не читается)\n'
}

collect() {
  printf 'Диагностика AI Usage Widget — %s\n' "$(date)"
  printf 'Личные данные (email, имена identity, токены, ключи) вырезаны до сохранения.\n'

  section "xcode-select -p" xcode-select -p
  section "xcodebuild -version" xcodebuild -version
  section "swift --version" swift --version
  section "sw_vers" sw_vers

  printf '\n== codesigning identities (только количество) ==\n'
  set +e
  IDENT_COUNT="$(security find-identity -v -p codesigning 2>/dev/null | tail -n 1 | sed -nE 's/[^0-9]*([0-9]+) valid identit.*/\1/p')"
  set -e
  printf 'valid identities found: %s (список имён не выгружается)\n' "${IDENT_COUNT:-неизвестно}"

  printf '\n== pluginkit -m -i %s ==\n' "$APPEX_BUNDLE_ID"
  set +e
  pluginkit -m -i "$APPEX_BUNDLE_ID" 2>&1 | head -n 5
  set -e

  printf '\n== entitlements установленного приложения ==\n'
  if [ -d "$APP_PATH" ]; then
    set +e
    codesign -d --entitlements - --xml "$APP_PATH" 2>&1
    set -e
  else
    printf 'не установлено: %s\n' "$APP_PATH"
  fi

  printf '\n== entitlements расширения ==\n'
  if [ -d "$APPEX_PATH" ]; then
    set +e
    codesign -d --entitlements - --xml "$APPEX_PATH" 2>&1
    set -e
  else
    printf 'расширение не найдено: %s\n' "$APPEX_PATH"
  fi

  group_container_section

  printf '\n== хвост последнего лога сборки (уже отредактирован при записи) ==\n'
  LAST_LOG="$(ls -t "$LOG_DIR/"build-*.log 2>/dev/null | head -n 1 || true)"
  if [ -n "$LAST_LOG" ]; then
    printf '( %s )\n' "$(basename "$LAST_LOG")"
    tail -n 80 "$LAST_LOG"
  else
    printf 'логов сборки пока нет\n'
  fi
  printf '\n== конфиг ожидаемой команды ==\n'
  if [ -f "$EXPECTED_TEAM_CFG" ]; then
    if [ -s "$EXPECTED_TEAM_CFG" ]; then printf '%s существует и непуст (содержимое не показывается)\n' "$EXPECTED_TEAM_CFG"
    else printf '%s ПУСТ — заполни по инструкции, раздел 6а\n' "$EXPECTED_TEAM_CFG"; fi
  else
    printf '%s отсутствует — создай по инструкции, раздел 6а\n' "$EXPECTED_TEAM_CFG"
  fi
}

# ---------------------------------------------------------------------------
# SELF-TEST (WR-04): синтетические фикстуры и заглушки инструментов в песочнице
# $HOME/$PATH; реальные каталоги пользователя и реальная установка не затрагиваются.
# ---------------------------------------------------------------------------
self_test() {
  local S total=0 failed=0
  T="$(mktemp -d "${TMPDIR:-/tmp}/aiusage-diag-selftest.XXXXXX")"
  trap 'if [ -n "${T:-}" ]; then rm -rf "$T"; fi' EXIT
  SCRIPT_ABS="$SCRIPT_DIR/diagnostics.sh"

  dt_setup() { # имя сценария → песочница $S: доверенный бандл + контейнер по умолчанию
    S="$T/$1"
    mkdir -p "$S/bin" "$S/home/Applications/AI Usage Widget.app/Contents/MacOS" \
             "$S/home/Applications/AI Usage Widget.app/Contents/PlugIns/AiUsageWidget.appex/Contents/MacOS" \
             "$S/home/Library/Group Containers/TESTTEAMID.group.aiusage" \
             "$S/home/Library/Logs/ai-usage"
    printf 'GROUP_SENTINEL_OK\n' > "$S/home/Library/Group Containers/TESTTEAMID.group.aiusage/test-snapshot.json"
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n\t<key>CFBundleIdentifier</key>\n<string>com.serzhsharapa.aiusage</string>\n\t<key>AppGroupID</key>\n<string>TESTTEAMID.group.aiusage</string>\n</dict>\n</plist>\n' > "$S/home/Applications/AI Usage Widget.app/Contents/Info.plist"
    printf 'TESTTEAMID\n' > "$S/expected-team.local"
    printf 'Executable=/fixture/AI Usage Widget.app/Contents/MacOS/AI Usage Widget\nIdentifier=com.serzhsharapa.aiusage\nAuthority=Apple Development: Fixture Owner (TESTTEAMID)\nTeamIdentifier=TESTTEAMID\n' > "$S/dv.txt"
    for t in xcode-select xcodebuild swift sw_vers security pluginkit; do
      printf '#!/bin/bash\necho "stub %s"\nexit 0\n' "$t" > "$S/bin/$t"
    done
    cat > "$S/bin/codesign" <<STUB
#!/bin/bash
case "\$*" in
  *--entitlements*) printf '<?xml version="1.0"?><plist version="1.0"><dict/></plist>\n'; exit 0 ;;
  *) cat "$S/dv.txt" >&2; exit 0 ;;
esac
STUB
    chmod +x "$S/bin/"*
  }

  dt_run() { # → код возврата в $DT_RC; отчёт — в $S/report.txt
    set +e
    ( PATH="$S/bin:/usr/bin:/bin" \
        HOME="$S/home" \
        AIUSAGE_EXPECTED_TEAM_FILE="$S/expected-team.local" \
        bash "$SCRIPT_ABS" ) > "$S/all-out.txt" 2>&1
    DT_RC=$?
    set -e
    # отчёт дублируется в $HOME песочницы — берём его как канонический вывод
    cp "$(ls -t "$S/home/Library/Logs/ai-usage/"diagnostics-*.txt | head -n 1)" "$S/report.txt" 2>/dev/null || cp "$S/all-out.txt" "$S/report.txt"
    return 0
  }

  assert() {
    local desc="$1"; shift
    total=$((total+1))
    if "$@"; then printf '  ok   %s\n' "$desc"; else printf '  FAIL %s\n' "$desc" >&2; failed=$((failed+1)); fi
  }
  rep_has()   { grep -q "$1" "$S/report.txt"; }
  rep_lacks() { ! grep -q "$1" "$S/report.txt"; }

  printf 'self-test diagnostics.sh (WR-04: заглушки инструментов, изолированный HOME):\n'

  # D1 доверенный бандл: имена файлов контейнера перечисляются
  dt_setup "ok"; dt_run
  assert "D1 rc=0"                       [ "$DT_RC" -eq 0 ]
  assert "D1 имена контейнера выведены"  rep_has 'test-snapshot.json'

  # D2 traversal-GID: ../.. из Group Containers — секция пропущена, sentinel не leaked
  dt_setup "traversal"
  mkdir -p "$S/home/privatefixture"; printf 'PRIVATE_SENTINEL_DIRECTORY\n' > "$S/home/privatefixture/leak.txt"
  sed -i '' 's#<string>TESTTEAMID.group.aiusage</string>#<string>../../privatefixture</string>#' "$S/home/Applications/AI Usage Widget.app/Contents/Info.plist"
  dt_run
  assert "D2 rc=0"                       [ "$DT_RC" -eq 0 ]
  assert "D2 секция пропущена"           rep_has 'пропущено'
  assert "D2 traversal-имена НЕ выведены" rep_lacks 'PRIVATE_SENTINEL_DIRECTORY'

  # D3 symlink-побег: контейнер — symlink наружу
  dt_setup "symlink"
  rm -rf "$S/home/Library/Group Containers/TESTTEAMID.group.aiusage"
  mkdir -p "$S/home/outside"; printf 'OUTSIDE_SENTINEL\n' > "$S/home/outside/x"
  ln -s "$S/home/outside" "$S/home/Library/Group Containers/TESTTEAMID.group.aiusage"
  dt_run
  assert "D3 rc=0"                        [ "$DT_RC" -eq 0 ]
  assert "D3 symlink-побег отклонён"      rep_has 'за пределы Group Containers'
  assert "D3 внешние имена НЕ выведены"   rep_lacks 'OUTSIDE_SENTINEL'

  # D4 чужой CFBundleIdentifier по каноническому пути
  dt_setup "foreign-bid"
  sed -i '' 's/com.serzhsharapa.aiusage</com.evil.other.app</' "$S/home/Applications/AI Usage Widget.app/Contents/Info.plist"
  dt_run
  assert "D4 rc=0"                        [ "$DT_RC" -eq 0 ]
  assert "D4 чужой бандл — секция пропущена" rep_has 'НЕ является нашим приложением'
  assert "D4 имена контейнера НЕ выведены"    rep_lacks 'test-snapshot.json'

  # D5 конфиг ожидаемой команды отсутствует
  dt_setup "nocfg"; rm -f "$S/expected-team.local"; dt_run
  assert "D5 rc=0"                        [ "$DT_RC" -eq 0 ]
  assert "D5 без точки отсчёта секция пропущена" rep_has 'пропущено'
  assert "D5 имена контейнера НЕ выведены"       rep_lacks 'test-snapshot.json'

  # D6 чужая команда в подписи
  dt_setup "foreign-team"
  sed -i '' 's/TeamIdentifier=TESTTEAMID/TeamIdentifier=OTHERTEAM1/' "$S/dv.txt"
  dt_run
  assert "D6 rc=0"                        [ "$DT_RC" -eq 0 ]
  assert "D6 чужая подпись — секция пропущена"  rep_has 'другой командой'
  assert "D6 имена контейнера НЕ выведены"      rep_lacks 'test-snapshot.json'

  # D7 GID чужой команды (даже валидный по форме)
  dt_setup "foreign-gid"
  mkdir -p "$S/home/Library/Group Containers/OTHERTEAM1.group.aiusage"
  printf 'FOREIGN_GROUP_SENTINEL\n' > "$S/home/Library/Group Containers/OTHERTEAM1.group.aiusage/x"
  sed -i '' 's/TESTTEAMID.group.aiusage/OTHERTEAM1.group.aiusage/' "$S/home/Applications/AI Usage Widget.app/Contents/Info.plist"
  dt_run
  assert "D7 rc=0"                            [ "$DT_RC" -eq 0 ]
  assert "D7 чужой GID — секция пропущена"    rep_has 'не равен В ТОЧНОСТИ'
  assert "D7 чужие имена НЕ выведены"         rep_lacks 'test-snapshot.json'

  # D8 (WR-04, раунд 2) подмена во ВТОРОЙ точке suffix'а: groupXaiusage —
  # прежний regex пропускал (wildcard-точка); маркер — ИМЯ файла (диагностика
  # экспортирует имена, не только содержимое).
  dt_setup "suffix-dot-wildcard"
  mkdir -p "$S/home/Library/Group Containers/TESTTEAMID.groupXaiusage"
  printf 'fixture only\n' > "$S/home/Library/Group Containers/TESTTEAMID.groupXaiusage/FOREIGN_GROUP_FILENAME"
  sed -i '' 's#<string>TESTTEAMID.group.aiusage</string>#<string>TESTTEAMID.groupXaiusage</string>#' "$S/home/Applications/AI Usage Widget.app/Contents/Info.plist"
  dt_run
  assert "D8 rc=0"                            [ "$DT_RC" -eq 0 ]
  assert "D8 подмена groupXaiusage — секция пропущена" rep_has 'не равен В ТОЧНОСТИ'
  assert "D8 чужое ИМЯ файла НЕ выведено"     rep_lacks 'FOREIGN_GROUP_FILENAME'

  # D9 подмена в конце suffix'а: group.aiusagX — тоже не точное равенство
  dt_setup "suffix-tail-subst"
  mkdir -p "$S/home/Library/Group Containers/TESTTEAMID.group.aiusagX"
  printf 'fixture only\n' > "$S/home/Library/Group Containers/TESTTEAMID.group.aiusagX/FOREIGN_GROUP_FILE_X9"
  sed -i '' 's#<string>TESTTEAMID.group.aiusage</string>#<string>TESTTEAMID.group.aiusagX</string>#' "$S/home/Applications/AI Usage Widget.app/Contents/Info.plist"
  dt_run
  assert "D9 rc=0"                            [ "$DT_RC" -eq 0 ]
  assert "D9 подмена aiusagX — секция пропущена" rep_has 'не равен В ТОЧНОСТИ'
  assert "D9 чужое ИМЯ файла НЕ выведено"     rep_lacks 'FOREIGN_GROUP_FILE_X9'

  if [ "$failed" -ne 0 ]; then
    printf 'self-test ЗАВЕРШЁН С ОШИБКАМИ: %d/%d проверок нарушено\n' "$failed" "$total" >&2
    rm -rf "$T"; T=""; exit 1
  fi
  printf 'self-test: %d/%d проверок PASS; изоляция: HOME/PATH — песочницы, реальные каталоги не читались\n' "$total" "$total"
  rm -rf "$T"; T=""
  return 0
}

case "${1:-}" in
  --self-test) self_test ;;
  "")
    [ $# -eq 0 ] || { printf 'Использование: bash scripts/diagnostics.sh (аргументов нет)\n' >&2; exit 2; }
    mkdir -p "$LOG_DIR"
    # Собираем в память → редакция → ОДНОВРЕМЕННО в терминал и в файл (до экспорта вырезано всё личное)
    REPORT="$(collect)"
    printf '%s\n' "$REPORT" | redact | tee "$OUT"
    printf '\nОтчёт сохранён (отредактированный): %s\n' "$OUT"
    exit 0
    ;;
  *)
    printf 'Использование: bash scripts/diagnostics.sh (аргументов нет)\n' >&2
    exit 2
    ;;
esac
