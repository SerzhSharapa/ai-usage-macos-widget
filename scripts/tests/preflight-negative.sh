#!/bin/bash
# preflight-negative.sh — детерминированный НЕГАТИВНЫЙ harness preflight-а build.sh
# (план 01-03-T2, п. 3; угрозы T-01-05/T-01-06 — тихая подмена и обход неготовности).
#
# Пять НЕЗАВИСИМЫХ сценариев, каждый в своей песочнице (mktemp -d: свои bin/, home/, cwd/):
# все ПРЕДЫДУЩИЕ проверки succeed с реалистичным выводом заглушек, целевая — отказывает.
#   (1) xcode-select → /Library/Developer/CommandLineTools (не Xcode)
#   (2) xcode-select ок, но xcodebuild -version выходит 1
#   (3) инструменты ок, но find-identity без «Apple Development» («0 valid identities»)
#   (4) инструменты ок и expected-team есть, но AiUsage.xcodeproj отсутствует в cwd
#   (5) всё ок, но scripts/expected-team.local отсутствует; (5b) вариант: файл пуст
#
# Каждый сценарий требует: ненулевой exit, причину ИМЕННО этого сценария, фразу следующего
# шага и отсутствие причин БОЛЕЕ РАННИХ проверек (независимость). Реальная машина, реальные
# инструменты и реальный ~/Applications не затрагиваются: PATH="$sandbox/bin:/usr/bin:/bin",
# HOME="$sandbox/home", cwd="$sandbox/cwd", копия build.sh.
# Дополнительно (сценарии 3–5): лог сборки в песочнице НЕ содержит email из вывода
# identity-заглушки — поведенческая проверка редакции до персистенции (D-04, T-01-03).
#
# bash 3.2 совместим. Выход: 0 — все сценарии воспроизвели отказ корректно; 1 — иначе.
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HARNESS_DIR/../.." && pwd)"
BUILD_SRC="$REPO_ROOT/scripts/build.sh"
[ -f "$BUILD_SRC" ] || { printf 'FAIL harness: build.sh не найден: %s\n' "$BUILD_SRC" >&2; exit 1; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aiusage-preflight-negative.XXXXXX")"
trap 'if [ -n "${ROOT:-}" ]; then rm -rf "$ROOT"; fi' EXIT

FAILED=0

make_ok_stubs() { # sandbox/bin — реалистичные «успешные» инструменты
  local B="$1/bin"; mkdir -p "$B"
  cat > "$B/xcode-select" <<'EOF'
#!/bin/bash
printf '%s\n' '/Applications/Xcode.app/Contents/Developer'
EOF
  cat > "$B/xcodebuild" <<'EOF'
#!/bin/bash
printf '%s\n' 'Xcode 27.0' 'Build version 27A100'
EOF
  cat > "$B/security" <<'EOF'
#!/bin/bash
printf '%s\n' '     1) AAAABBBBCCCCDDDD0000000000000000000000000000000000000000 "Apple Development: fixture@example.com (TESTTEAMID)" iOS' '       1 valid identities found'
EOF
  chmod +x "$B/xcode-select" "$B/xcodebuild" "$B/security"
}

make_cwd_base() { # sandbox/cwd — проект (пустой каталог-имитация) + валидный конфиг команды
  mkdir -p "$1/cwd/AiUsage.xcodeproj" "$1/cwd/scripts"
  printf '%s\n' 'TESTTEAMID' > "$1/cwd/scripts/expected-team.local"
}

setup_1() { make_ok_stubs "$1"
  cat > "$1/bin/xcode-select" <<'EOF'
#!/bin/bash
printf '%s\n' '/Library/Developer/CommandLineTools'
EOF
  chmod +x "$1/bin/xcode-select"; make_cwd_base "$1"; }
setup_2() { make_ok_stubs "$1"
  cat > "$1/bin/xcodebuild" <<'EOF'
#!/bin/bash
printf "xcodebuild: error: tool 'xcodebuild' requires Xcode, but the active developer directory is a Command Line Tools instance\n" >&2
exit 1
EOF
  chmod +x "$1/bin/xcodebuild"; make_cwd_base "$1"; }
setup_3() { make_ok_stubs "$1"
  cat > "$1/bin/security" <<'EOF'
#!/bin/bash
printf '%s\n' '     0 valid identities found'
exit 0
EOF
  chmod +x "$1/bin/security"; make_cwd_base "$1"; }
setup_4() { make_ok_stubs "$1"
  # expected-team есть, проекта в cwd нет
  mkdir -p "$1/cwd/scripts"; printf '%s\n' 'TESTTEAMID' > "$1/cwd/scripts/expected-team.local"; }
setup_5() { make_ok_stubs "$1"
  mkdir -p "$1/cwd/AiUsage.xcodeproj" "$1/cwd/scripts"
  : > "$1/cwd/scripts/expected-team.local"; }   # 5b: пустой файл (5a: rm)

run_scenario() { # id, причина-ERE, причины-ранее-ERE(чтобы НЕ было), проверять-редакцию(0|1)
  local id="$1" must="$2" mustnot="$3" check_redact="$4"
  local S="$ROOT/$id" rc out log
  mkdir -p "$S/home" "$S/cwd"
  "setup_$id" "$S"
  cp "$BUILD_SRC" "$S/cwd/scripts/build.sh"
  set +e
  ( cd "$S/cwd" && PATH="$S/bin:/usr/bin:/bin" HOME="$S/home" bash scripts/build.sh ) > "$S/out.txt" 2>&1
  rc=$?
  set -e
  out="$(cat "$S/out.txt")"

  local ok=1 why=""
  [ "$rc" -ne 0 ]                     || { ok=0; why="build.sh вышел нулём в негативной среде ($id)"; }
  printf '%s\n' "$out" | grep -q 'Следующий шаг' || { ok=0; why="$why; нет фразы следующего шага"; }
  printf '%s\n' "$out" | grep -Eq "$must" || { ok=0; why="$why; нет своей причины ($must)"; }
  if [ "$mustnot" != "-" ]; then
    if printf '%s\n' "$out" | grep -Eq "$mustnot"; then ok=0; why="$why; отказался на более РАННЕЙ проверке (независимость нарушена)"; fi
  fi
  if [ "$check_redact" = "1" ]; then
    log="$(ls -t "$S/home/Library/Logs/ai-usage/"build-*.log 2>/dev/null | head -n 1 || true)"
    if [ -n "$log" ]; then
      if grep -q 'fixture@example.com' "$log"; then ok=0; why="$why; email попал в лог (редакция до персистенции не работает)"; fi
      if ! grep -q 'REDACTED' "$log"; then ok=0; why="$why; маркер редакции не найден в логе"; fi
    else
      ok=0; why="$why; лог в песочнице не создан"
    fi
  fi

  if [ "$ok" = "1" ]; then
    printf '  ok   сценарий %s: exit=%s; причина: %s\n' "$id" "$rc" "$(printf '%s\n' "$out" | grep -m1 'ОШИБКА' | cut -c1-100)"
  else
    printf '  FAIL сценарий %s: %s\n--- вывод ---\n%s\n--------------\n' "$id" "${why#; }" "$out" >&2
    FAILED=$((FAILED+1))
  fi
}

printf 'негативный harness preflight (изолированные PATH/HOME/CWD, копия build.sh, заглушки):\n'

R1='Xcode не выбран|developer dir'
R2='xcodebuild не выполняется|xcodebuild'
R3='identity не найдена|Apple Development'
R4='проект не найден|AiUsage\.xcodeproj'
R5='не задана ожидаемая команда|expected-team'

run_scenario 1 "$R1" '-'                                   0
run_scenario 2 "$R2" "$R1"                                 0
run_scenario 3 "$R3" "$R1|$R2"                             0
run_scenario 4 "$R4" "$R1|$R2|$R3"                         1
run_scenario 5 "$R5" "$R1|$R2|$R3|$R4"                     1

# (5b) вариант пустого файла уже покрыт setup_5; отдельный запуск с УДАЛЁННЫМ файлом:
setup_5b() { setup_5 "$1"; rm -f "$1/cwd/scripts/expected-team.local"; }
run_5b() {
  local S="$ROOT/5b" rc out
  mkdir -p "$S/home" "$S/cwd"; setup_5b "$S"; cp "$BUILD_SRC" "$S/cwd/scripts/build.sh"
  set +e
  ( cd "$S/cwd" && PATH="$S/bin:/usr/bin:/bin" HOME="$S/home" bash scripts/build.sh ) > "$S/out.txt" 2>&1
  rc=$?
  set -e
  out="$(cat "$S/out.txt")"
  if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -Eq "$R5" && printf '%s\n' "$out" | grep -q 'Следующий шаг'; then
    printf '  ok   сценарий 5b (файл отсутствует): exit=%s\n' "$rc"
  else
    printf '  FAIL сценарий 5b: отсутствие файла не воспроизведено (rc=%s)\n%s\n' "$rc" "$out" >&2
    FAILED=$((FAILED+1))
  fi
}
run_5b

if [ "$FAILED" -ne 0 ]; then
  printf 'harness ЗАВЕРШЁН С ОШИБКАМИ: %d сценариев не воспроизвели отказ\n' "$FAILED" >&2
  exit 1
fi
printf 'harness: 6 прогонов (5 сценариев + вариант 5b) PASS; реальная машина не затрагивалась (PATH/HOME/cwd — песочницы)\n'
exit 0
