#!/bin/bash
# build.sh — пересборка и БЕЗОПАСНАЯ переустановка AI Usage Widget одной командой
# (план 01-03-T2, Pattern 2 из 01-RESEARCH.md; D-01…D-04, Pitfall 4/7/8/9).
#
# Цикл: preflight (5 независимых проверек) → xcodebuild (Release; --debug для безопасного
# негативного сценария 01-04-T3) → staged-копия в ~/Applications → ПОЛНАЯ верификация
# verify-install.sh --app-path ДО закрытия прежнего экземпляра и замены → делегирование
# остановки точному stop-only помощнику stop-installed.sh → поэтапная замена с откатом
# (прежний бандл — в Корзину перемещением, НЕ удалением) → open (без запуска виджет
# не появится в галерее). Никаких rm, никаких путей кроме своего бандла, staged-имени
# и своего лог-каталога; права каталогов данных (включая Group Containers) не меняются.
#
# Лог: полный вывод — в $HOME/Library/Logs/ai-usage/build-<дата>.log ПОСЛЕ РЕДАКЦИИ
# (email, имена identity «Apple Development: <имя>…» — остаётся вид подписи и TeamID,
# токены, приватные ключи; содержимое scripts/expected-team.local не дублируется).
# В терминал — краткий статус; при ошибке — причина и следующий шаг (D-04).
#
# bash 3.2 совместим; без set -x (D-04). Выход: 0 успех; 1 ошибка; 2 использование.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$HOME/Library/Logs/ai-usage"
mkdir -p "$LOG_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="$LOG_DIR/build-$STAMP.log"

# ------------------------------- аргументы ----------------------------------
CONFIG="Release"
if [ $# -gt 1 ]; then
  printf 'Ошибка: ожидается не более одного аргумента. Поддерживается только --debug (произвольные цели сборки не разрешены).\n' >&2
  exit 2
fi
case "${1:-}" in
  "") ;;
  --debug) CONFIG="Debug" ;;
  -h|--help)
    printf 'Использование: bash scripts/build.sh [--debug]\n  (без аргументов) — Release-сборка и переустановка\n  --debug — Debug-сборка (безопасный негативный сценарий состояния контейнера, 01-04-T3)\n'
    exit 0
    ;;
  *)
    printf 'Ошибка: неизвестный аргумент «%s». Поддерживается только --debug.\n' "$1" >&2
    exit 2
    ;;
esac

# --------------------------- редакция до персистенции ------------------------
redact() { # stdin → stdout: email/имена identity/токены/ключи вырезаются ДО записи в лог
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

CAPTURE=""; RC_RUN=0
run_capture() { # cmd… → вывод в $CAPTURE (только в памяти, сырые дампы не персистятся), rc в $RC_RUN
  set +e
  CAPTURE="$("$@" 2>&1)"
  RC_RUN=$?
  set -e
}
log_capture() { # заголовок — редацтированный $CAPTURE дописывается в лог
  { printf '\n===== %s =====\n' "$1"; printf '%s\n' "$CAPTURE"; } | redact >> "$LOG"
}

say()    { printf '%s\n' "$*"; }
die()    { # причина, следующий шаг
  printf 'ОШИБКА: %s\n' "$1" >&2
  printf 'Следующий шаг: %s\n' "$2" >&2
  printf 'Подробности (уже отредактированные): %s\n' "$LOG" >&2
  exit 1
}

say "== AI Usage Widget: сборка и установка ($CONFIG) =="

# --------------------------- preflight (D-01, Pitfall 4) --------------------
# Пять независимых проверок ДО любых изменений файловой системы (кроме своего лог-каталога).

# 1) активный developer dir — именно Xcode
run_capture xcode-select -p
log_capture "preflight 1/5: xcode-select -p"
if [ "$RC_RUN" -ne 0 ] || [ "$CAPTURE" != "/Applications/Xcode.app/Contents/Developer" ]; then
  die "Xcode не выбран активным developer dir (xcode-select -p: «${CAPTURE:-пусто}»), а xcodebuild требует Xcode." \
      "выполни sudo xcode-select -s /Applications/Xcode.app (инструкция docs/phase-01-setup.ru.md, раздел 3)"
fi

# 2) xcodebuild работоспособен
run_capture xcodebuild -version
log_capture "preflight 2/5: xcodebuild -version"
if [ "$RC_RUN" -ne 0 ]; then
  die "xcodebuild не выполняется (rc=$RC_RUN)." \
      "проверь, что Xcode установлен из App Store и выбран: sudo xcode-select -s /Applications/Xcode.app (инструкция, разделы 2–3)"
fi

# 3) сертификат Apple Development (необходимое условие; фактическую подпись и команду
#    по бинарям проверяет verify-install.sh — это только ранняя диагностика)
run_capture security find-identity -v -p codesigning
log_capture "preflight 3/5: security find-identity (в логе имена identity отредактированы)"
if [ "$RC_RUN" -ne 0 ] || ! printf '%s\n' "$CAPTURE" | grep -q 'Apple Development'; then
  die "identity не найдена: в выводе security find-identity нет строки «Apple Development» (сертификата личной команды нет)." \
      "Xcode > Settings > Accounts > «+» > Apple ID, затем выбери personal team для ОБОИХ таргетов в Signing & Capabilities (инструкция, разделы 4–5)"
fi

# 4) проект существует (в текущем каталоге)
if [ ! -d "AiUsage.xcodeproj" ]; then
  { printf '\n===== preflight 4/5: проект =====\nAiUsage.xcodeproj не найден в %s\n' "$PWD"; } >> "$LOG"
  die "проект не найден: AiUsage.xcodeproj отсутствует в текущем каталоге ($PWD)." \
      "запускай из корня репозитория: bash scripts/build.sh"
fi

# 5) конфиг ожидаемой команды существует и непуст (формат полностью разбирает verify-install.sh)
EXPECTED_TEAM_CFG="$SCRIPT_DIR/expected-team.local"
if [ ! -s "$EXPECTED_TEAM_CFG" ]; then
  { printf '\n===== preflight 5/5: expected-team.local =====\nфайл отсутствует или пуст: %s (содержимое в лог не пишется)\n' "$EXPECTED_TEAM_CFG"; } >> "$LOG"
  die "не задана ожидаемая команда: файл scripts/expected-team.local отсутствует или пуст (TeamID владельца)." \
      "создай файл по инструкции (раздел 6а): одна строка TeamID из Xcode > Settings > Accounts — ДО первой сборки"
fi
say "[1/5] preflight — ok (Xcode, инструменты, identity, проект, ожидаемая команда)"

# --------------------------- сборка (SYMROOT — [CITED: TN2339]) --------------
say "[2/5] сборка ($CONFIG)…"
run_capture xcodebuild -project AiUsage.xcodeproj -scheme AiUsage -configuration "$CONFIG" build SYMROOT="$PWD/build"
log_capture "xcodebuild ($CONFIG)"
if [ "$RC_RUN" -ne 0 ]; then
  die "сборка не удалась (xcodebuild, rc=$RC_RUN; полезные строки ошибок — в логе)." \
      "открой лог и найди строки с error: — типовые причины перечислены в инструкции, раздел «Действия при ошибках»"
fi

SRC_APP="$PWD/build/$CONFIG/AI Usage Widget.app"
if [ ! -d "$SRC_APP" ] || [ ! -d "$SRC_APP/Contents/PlugIns/AiUsageWidget.appex" ]; then
  die "сборка завершилась, но продукт не найден или без расширения: $SRC_APP" \
      "проверь лог сборки (схема AiUsage должна собрать оба таргета и встроить appex)"
fi
say "      сборка завершена: $SRC_APP"

# ------------- staged-копия и ПОЛНАЯ верификация ДО любых действий над старой --
say "[3/5] staged-проверка новой сборки (до закрытия прежней)…"
STAGED="$HOME/Applications/.aiusage-staged-$STAMP.app"
if [ -e "$STAGED" ]; then
  die "staged-имя уже занято (не должно случаться): $STAGED" "удали leftovers вручную и повтори"
fi
run_capture ditto "$SRC_APP" "$STAGED"
log_capture "ditto → staged-копия"
if [ "$RC_RUN" -ne 0 ]; then
  die "не удалось создать staged-копию в ~/Applications (ditto, rc=$RC_RUN)." "проверь свободное место и права в ~/Applications"
fi

set +e
VOUT="$(bash "$SCRIPT_DIR/verify-install.sh" --app-path "$STAGED" 2>&1)"
VRC=$?
set -e
# WR-03: вывод верификатора проходит общий редактор ДО любой персистенции —
# как и все прочие захватывания этого скрипта (run_capture/log_capture).
{ printf '\n===== verify-install.sh --app-path (staged) =====\n%s\n' "$VOUT"; } | redact >> "$LOG"
if [ "$VRC" -ne 0 ]; then
  VREASON="$(printf '%s\n' "$VOUT" | grep -m1 '^FAIL:' || true)"
  mv "$STAGED" "$HOME/.Trash/" 2>/dev/null || say "внимание: staged-копию не удалось переместить в Корзину — удали вручную: $STAGED"
  die "staged-проверка НЕ пройдена: ${VREASON:-см. лог}. Прежняя установка НЕ тронута, запущенное приложение продолжает работать." \
      "исправь причину (обычно — подпись/права/группа в настройках таргетов, инструкция, разделы 5–6) и повтори bash scripts/build.sh"
fi
say "      staged-проверка пройдена: подпись, команда, права, группы, целостность"

# ------------------- закрытие ТОЛЬКО своего экземпляра (D-03, Pitfall 8) -----
# Делегируется точному stop-only помощнику: канонический путь, identity до сигнала,
# PID по якорю полного пути с перепроверкой, TERM → подтверждённый выход, таймаут = FAIL.
say "[4/5] остановка своего экземпляра (stop-installed.sh)…"
set +e
SOUT="$(bash "$SCRIPT_DIR/stop-installed.sh" 2>&1)"
SRC_STOP=$?
set -e
# WR-03: вывод stop-помощника — через редактор до лога (единая точка персистенции).
{ printf '\n===== stop-installed.sh =====\n%s\n' "$SOUT"; } | redact >> "$LOG"
if [ "$SRC_STOP" -ne 0 ]; then
  SREASON="$(printf '%s\n' "$SOUT" | grep -m1 'FAIL:' || true)"
  die "не удалось корректно остановить свой экземпляр: ${SREASON:-см. лог}. Замена ОТМЕНЕНА — прежняя сборка и данные на месте." \
      "$(printf '%s\n' "$SOUT" | grep -m1 'Следующий шаг' | sed 's/^Следующий шаг: //' || echo "см. вывод stop-installed.sh в логе")"
fi
# «не установлено»/«не запущен» — помощник завершил нулём; шаг пропускается молча.

# ------------------- поэтапная замена с откатом (Pitfall 8, правило Корзины) -
say "[5/5] замена и запуск…"
TARGET="$HOME/Applications/AI Usage Widget.app"
TRASHED=""
if [ -d "$TARGET" ]; then
  TRASHED="$HOME/.Trash/AI Usage Widget-$STAMP.app"
  if ! mv "$TARGET" "$TRASHED"; then
    die "не удалось переместить прежний бандл в Корзину. Замена отменена: прежняя сборка на месте." \
        "проверь, не открыт ли бандл в Finder; повтори bash scripts/build.sh"
  fi
  { printf '\n===== замена =====\nпрежний бандл → Корзина: %s\n' "AI Usage Widget-$STAMP.app"; } >> "$LOG"
fi
if ! mv "$STAGED" "$TARGET"; then
  if [ -n "$TRASHED" ] && [ -e "$TRASHED" ]; then
    if mv "$TRASHED" "$TARGET"; then
      say "Откат: прежняя сборка возвращена из Корзины на канонический путь."
    else
      say "ВНИМАНИЕ: откат не удался — прежний бандл остался в Корзине: $TRASHED"
    fi
  fi
  die "финальное перемещение staged-копии не удалось." "проверь свободное место и права в ~/Applications, затем повтори bash scripts/build.sh"
fi
# --------------------------- запуск (Pitfall 2) ------------------------------

# Процесс widget extension может переживать замену бандла: WidgetKit держит
# старый бинарник в памяти, и новый рендер не подхватывается (наблюдалось
# 20.10.2026). Завершаем ТОЛЬКО свой extension-процесс — WidgetKit поднимет
# его заново уже из установленного бандла при следующем запросе таймлайна.
killall AiUsageWidget 2>/dev/null || true

if ! open "$TARGET"; then
  die "приложение установлено ($TARGET), но не удалось запустить его автоматически." \
      "запусти вручную: open \"$TARGET\""
fi
say "Готово: установлено и запущено ($CONFIG): $TARGET"
if [ -n "$TRASHED" ]; then
  say "Прежняя сборка — в Корзине: $TRASHED"
fi
say "Лог (отредактированный): $LOG"
exit 0
