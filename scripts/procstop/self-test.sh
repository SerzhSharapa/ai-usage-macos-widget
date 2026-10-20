#!/bin/bash
# procstop/self-test.sh — НАТИВНАЯ самопроверка помощника scripts/procstop/main.swift
# (CR-04/WR-02, 01-CODE-REVIEW раунды 2–3). Компилирует НЕизменяемый исходник и
# гоняет его на СОБСТВЕННЫХ короткоживущих пустых C-фикстурах во временном каталоге:
#   • граница цели: traversal/symlink-файл/symlink КАТАЛОГОВ MacOS и Contents
#     наружу → rc=7 БЕЗ единого сигнала (раунд 3: symlink-каталог переопределял
#     авторизованную границу — теперь корень неподвижен);
#   • точное совпадение пути ядра (список/остановка), argv-подмена не совпадает;
#   • неоднозначность (>1 экземпляра) → rc=4 без сигналов;
#   • TERM-игнорирующая фикстура → rc=6, ровно один TERM, без KILL;
#   • WR-02: отказ чтения пути ядра (DYLD-interpose, только собственный PID)
#     при живой цели → rc=2 «отказ инспекции», НЕ rc=3 «не запущен», сигнал не отправляется.
#
# WR-06 (раунд 3) — ИЗОЛЯЦИЯ CLEANUP: учёт ведётся по identity-снимку
# (владелец uid + время рождения lstart + comm) в момент старта; завершённая/
# reaped фикстура НЕМЕДЛЕННО исключается из набора; аварийный cleanup сигналит
# только ЖИВОМУ экземпляру, чья identity подтверждена НЕПОСРЕДСТВЕННО перед
# каждым сигналом (TERM, затем повторная сверка перед крайним KILL). Исторические
# номера PID и процессы с изменённой identity не получают ни одного сигнала.
#
# Ошибки компиляции/инструментов НЕ маскируются: отсутствие swiftc/cc — FAIL (нет
# фиктивного успеха). Реальные приложения/процессы пользователя не затрагиваются.
#
# Выход: 0 — все проверки PASS; 1 — есть нарушения. bash 3.2 совместим.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/main.swift"
[ -f "$SRC" ] || { printf 'FAIL self-test: исходник не найден: %s\n' "$SRC" >&2; exit 1; }

T="$(mktemp -d "${TMPDIR:-/tmp}/aiusage-procstop-selftest.XXXXXX")"
PIDS_FILE="$T/pids"   # строки: PID<TAB>BIRTH<TAB>COMM — только ЖИВЫЕ tracked фикстуры
: > "$PIDS_FILE"
TAB="$(printf '\t')"
MY_UID="$(id -u)"

# --- identity собственных фикстур (WR-06) -------------------------------------
# uid + birth (ps lstart) + comm — снимок в момент старта; повторная сверка
# перед любым сигналом. PID re-use до другого процесса ломает минимум одно поле.
fixture_uid()   { ps -o uid=    -p "$1" 2>/dev/null | tr -d '[:space:]'; }
fixture_birth() { ps -o lstart= -p "$1" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }
fixture_comm()  { ps -o comm=   -p "$1" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }

track_fixture() { # PID — зафиксировать identity СОБСТВЕННОЙ живой фикстуры
  local pid="$1" uid birth comm
  uid="$(fixture_uid "$pid")"
  [ "$uid" = "$MY_UID" ] || return 1
  birth="$(fixture_birth "$pid")"
  [ -n "$birth" ] || return 1
  comm="$(fixture_comm "$pid")"
  [ -n "$comm" ] || return 1
  printf '%s\t%s\t%s\n' "$pid" "$birth" "$comm" >> "$PIDS_FILE"
}

untrack_fixture() { # PID — завершённая/reaped фикстура НЕМЕДЛЕННО уходит из набора
  local pid="$1"
  grep -v "^${pid}${TAB}" "$PIDS_FILE" > "$PIDS_FILE.new" 2>/dev/null || true
  mv "$PIDS_FILE.new" "$PIDS_FILE"
}

fixture_identity_ok() { # PID BIRTH COMM → 0 только если это всё ещё ТОТ ЖЕ наш живой экземпляр
  local pid="$1" birth="$2" comm="$3"
  kill -0 "$pid" 2>/dev/null || return 1
  [ "$(fixture_uid "$pid")" = "$MY_UID" ] || return 1
  [ "$(fixture_birth "$pid")" = "$birth" ] || return 1
  [ "$(fixture_comm "$pid")" = "$comm" ] || return 1
  return 0
}

cleanup_tracked_pids() {
  # Сигнал — ТОЛЬКО живому экземпляру, чья identity (uid + birth + comm)
  # подтверждена НЕПОСРЕДСТВЕННО перед ним; исторические/чужие PID не получают
  # ни TERM, ни KILL. KILL — крайняя мера и тоже только после повторной сверки.
  local pid birth comm i
  while IFS="$TAB" read -r pid birth comm; do
    [ -n "${pid:-}" ] || continue
    fixture_identity_ok "$pid" "$birth" "$comm" || continue
    kill "$pid" 2>/dev/null
    i=0
    while [ "$i" -lt 30 ]; do
      fixture_identity_ok "$pid" "$birth" "$comm" || break
      sleep 0.1
      i=$((i+1))
    done
    wait "$pid" 2>/dev/null
    if fixture_identity_ok "$pid" "$birth" "$comm"; then
      kill -9 "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
    fi
  done < "$PIDS_FILE"
  : > "$PIDS_FILE"
  return 0
}
cleanup() {
  cleanup_tracked_pids
  rm -rf "$T"
  return 0
}
trap cleanup EXIT

total=0; failed=0
say()  { printf '%s\n' "$*"; }
assert() { # описание, команда-проверка…
  local desc="$1"; shift
  total=$((total+1))
  if "$@"; then printf '  ok   %s\n' "$desc"; else printf '  FAIL %s\n' "$desc" >&2; failed=$((failed+1)); fi
}

die_hard() { printf 'FAIL self-test: %s\n' "$1" >&2; exit 1; }

command -v swiftc >/dev/null 2>&1 || die_hard "swiftc не найден — нативная проверка невозможна (фиктивный SUCCESS не допускается)"
command -v cc >/dev/null 2>&1 || die_hard "cc не найден — нативные фикстуры не собрать"

# --- сборка помощника и фикстур (любая ошибка — FAIL, не пропуск) --------------
say 'self-test procstop (нативная компиляция и собственные C-фикстуры):'
swiftc -O -target arm64-apple-macos15.0 -o "$T/procstop" "$SRC" 2>"$T/swiftc.log" \
  || { cat "$T/swiftc.log" >&2; die_hard "компиляция помощника не удалась"; }

cat > "$T/sleeper.c" <<'EOF'
#include <signal.h>
#include <stdlib.h>
#include <unistd.h>
int main(int argc, char **argv){
  if (argc > 2) signal(SIGTERM, SIG_IGN);
  sleep((argc > 1) ? atoi(argv[1]) : 6);
  return 0;
}
EOF
cc -mmacosx-version-min=15.0 "$T/sleeper.c" -o "$T/sleeper" 2>"$T/cc.log" \
  || { cat "$T/cc.log" >&2; die_hard "компиляция фикстуры не удалась"; }

# WR-02: interpose-библиотека, отрицающая proc_pidpath ТОЛЬКО для PID из
# AIUSAGE_DENY_PID (все прочие вызовы остаются системными).
cat > "$T/deny-path.c" <<'EOF'
#include <libproc.h>
#include <stdlib.h>
#include <errno.h>
static int denied(int pid, void *buf, uint32_t size) {
  if (pid == atoi(getenv("AIUSAGE_DENY_PID"))) { errno=EACCES; return 0; }
  return proc_pidpath(pid,buf,size);
}
__attribute__((used)) static const struct { const void *replacement; const void *original; }
interpose __attribute__((section("__DATA,__interpose"))) = {(void *)denied,(void *)proc_pidpath};
EOF
cc -dynamiclib "$T/deny-path.c" -o "$T/deny-path.dylib" 2>>"$T/cc.log" \
  || { cat "$T/cc.log" >&2; die_hard "компиляция interpose-библиотеки не удалась"; }

# «Бандл» фикстуры: executable с реальным именем продукта (пробелы легитимны)
ROOT="$T/AI Usage Widget.app"
EXE="$ROOT/Contents/MacOS/AI Usage Widget"
mkdir -p "$ROOT/Contents/MacOS"
cp "$T/sleeper" "$EXE"

start_fixture() { # аргументы фикстуре; PID — в глобальной $FIXTURE_PID (для cleanup)
  "$@" &
  FIXTURE_PID=$!
  sleep 0.25
  track_fixture "$FIXTURE_PID" \
    || die_hard "не удалось зафиксировать identity собственной фикстуры PID $FIXTURE_PID"
}
stop_fixture() { # точная собственная фикстура: TERM + reap + НЕМЕДЛЕННО из набора
  kill "$1" 2>/dev/null
  wait "$1" 2>/dev/null
  untrack_fixture "$1"
  return 0
}

# --- (1)–(3) граница цели (CR-04): rc=7, сигналов нет и быть не может ---------
set +e
"$T/procstop" --stop "$ROOT" "$T/sleeper" 2 > "$T/out1.txt" 2>&1
RC1=$?
"$T/procstop" --stop "$ROOT" "$ROOT/Contents/MacOS/../Evil" 2 > "$T/out2.txt" 2>&1
RC2=$?
cp "$T/sleeper" "$T/External Target"
ln -s "$T/External Target" "$ROOT/Contents/MacOS/Sneaky Link"
"$T/procstop" --stop "$ROOT" "$ROOT/Contents/MacOS/Sneaky Link" 2 > "$T/out3.txt" 2>&1
RC3=$?
assert "(1) внешний путь цели → rc=7"                [ "$RC1" -eq 7 ]
assert "(2) traversal в пути цели → rc=7"            [ "$RC2" -eq 7 ]
assert "(3) symlink-файл внутри MacOS → rc=7"        [ "$RC3" -eq 7 ]
rm -f "$ROOT/Contents/MacOS/Sneaky Link"

# --- (4) точное совпадение: список находит ровно свой экземпляр ----------------
start_fixture "$EXE" 6
FP=$FIXTURE_PID
set +e
"$T/procstop" --list "$ROOT" "$EXE" > "$T/out4.txt" 2>&1
RC4=$?
assert "(4) --list точного экземпляра → rc=0"        [ "$RC4" -eq 0 ]
assert "(4) ровно одна строка с этим PID"            bash -c "grep -c '^${FP}[[:space:]]' '$T/out4.txt' | grep -qx 1"

# --- (5) argv-подмена не совпадает (сопоставление — путь ядра, не argv) --------
cp "$T/sleeper" "$T/Decoy"
bash -c 'exec -a "spoofed argv0" "$0" 6' "$T/Decoy" &
DP=$!
sleep 0.25
track_fixture "$DP" || die_hard "не удалось зафиксировать identity decoy-фикстуры PID $DP"
set +e
"$T/procstop" --list "$ROOT" "$EXE" > "$T/out5.txt" 2>&1
RC5=$?
# (4)-фикстура всё ещё жива и совпадает; decoy с подменённым argv0 — не добавился
assert "(5) decoy с argv-подменой не совпал"         bash -c "[ \"\$(grep -c '^[0-9]' '$T/out5.txt')\" = 1 ]"
stop_fixture "$DP"

# --- (6) несколько экземпляров точного пути → rc=4, БЕЗ сигналов ---------------
start_fixture "$EXE" 6; PA=$FIXTURE_PID
start_fixture "$EXE" 6; PB=$FIXTURE_PID
set +e
"$T/procstop" --stop "$ROOT" "$EXE" 2 > "$T/out6.txt" 2>&1
RC6=$?
assert "(6) несколько экземпляров → rc=4"            [ "$RC6" -eq 4 ]
assert "(6) первый экземпляр жив (сигналов не было)" bash -c "kill -0 $FP 2>/dev/null"
assert "(6) новые экземпляры живы (сигналов не было)" bash -c "kill -0 $PA 2>/dev/null && kill -0 $PB 2>/dev/null"
stop_fixture "$PA"; stop_fixture "$PB"

# --- (7) остановка единственного точного экземпляра → rc=0 ---------------------
set +e
"$T/procstop" --stop "$ROOT" "$EXE" 5 > "$T/out7.txt" 2>&1
RC7=$?
assert "(7) TERM единственного экземпляра → rc=0"    [ "$RC7" -eq 0 ]
assert "(7) подтверждён фактический выход"           grep -q 'подтверждён фактический выход' "$T/out7.txt"
wait "$FP" 2>/dev/null   # reap — зомби не остаётся в таблице процессов
untrack_fixture "$FP"    # завершённый экземпляр НЕМЕДЛЕННО уходит из набора (WR-06)

# --- (8) TERM-игнорирующая фикстура → rc=6, один TERM, без KILL, self-exit -----
start_fixture "$EXE" 6 ignore-term
IG=$FIXTURE_PID
set +e
"$T/procstop" --stop "$ROOT" "$EXE" 1 > "$T/out8.txt" 2>&1
RC8=$?
ALIVE8=$(kill -0 "$IG" 2>/dev/null && printf yes || printf no)
assert "(8) не вышел за таймаут → rc=6"              [ "$RC8" -eq 6 ]
assert "(8) фикстура жива (без KILL)"                [ "$ALIVE8" = yes ]
wait "$IG" 2>/dev/null   # конечноживущая фикстура завершается сама; KILL не отправлялся
untrack_fixture "$IG"

# --- (9) WR-02: отказ пути ядра на живом собственном PID → rc=2, не rc=3 -------
start_fixture "$EXE" 6
NP=$FIXTURE_PID
set +e
AIUSAGE_DENY_PID="$NP" DYLD_INSERT_LIBRARIES="$T/deny-path.dylib" \
  "$T/procstop" --stop "$ROOT" "$EXE" 2 > "$T/out9.txt" 2>&1
RC9=$?
ALIVE9=$(kill -0 "$NP" 2>/dev/null && printf yes || printf no)
assert "(9) отказ пути живого PID → rc=2 (не «не запущен»)" [ "$RC9" -eq 2 ]
assert "(9) цель жива — сигнал не отправлялся"       [ "$ALIVE9" = yes ]
assert "(9) причина — неопределённая инспекция"      grep -q 'инспекция неопределена' "$T/out9.txt"
wait "$NP" 2>/dev/null   # фикстура завершается сама
untrack_fixture "$NP"

# --- (10) старый CLI (без bundle-root) больше не существует → usage rc=1 -------
set +e
"$T/procstop" --stop "$EXE" 2 > "$T/out10.txt" 2>&1
RC10=$?
assert "(10) --stop без bundle-root → rc=1 (usage)"  [ "$RC10" -eq 1 ]

# --- (11) WR-02: живой процесс с УДАЛЁННЫМ бинарём (ENOENT пути) и чужим
#     kernel-именем НЕ блокирует вердикт «не запущен» (реальный случай: чужое
#     приложение обновилось, старый бинарий удалён из-под работающего процесса).
#     Совпадение pbi_comm с именем цели обработано секцией (9): это rc=2.
cp "$T/sleeper" "$T/ReplacedApp"
"$T/ReplacedApp" 6 & RP=$!
sleep 0.25
track_fixture "$RP" || die_hard "не удалось зафиксировать identity ENOENT-фикстуры PID $RP"
rm -f "$T/ReplacedApp"   # собственная фикстура: бинарий удалён из-под процесса
set +e
"$T/procstop" --list "$ROOT" "$EXE" > "$T/out11.txt" 2>&1
RC11=$?
assert "(11) ENOENT-процесс с чужим comm → rc=3 (не блокирует)" [ "$RC11" -eq 3 ]
assert "(11) процесс с удалённым бинарём жив (не тронут)" bash -c "kill -0 $RP 2>/dev/null"
stop_fixture "$RP"

# --- (12) CR-04 раунд 3: MacOS — SYMLINK-КАТАЛОГ наружу. Помощник САМ обязан
#     отказать (rc=7) ДО перечисления процессов: граница — литерал от
#     канонического корня и symlink'ом не переопределяется. Внешняя СОБСТВЕННАЯ
#     конечноживущая фикстура должна остаться живой, сигналов нет. --------------
OUTSIDE="$T/outside-dir"; mkdir -p "$OUTSIDE"
cp "$T/sleeper" "$OUTSIDE/AI Usage Widget"
SYROOT="$T/Boundary MacOS Link.app"; mkdir -p "$SYROOT/Contents"
ln -s "$OUTSIDE" "$SYROOT/Contents/MacOS"
"$OUTSIDE/AI Usage Widget" 8 & SYP=$!
sleep 0.25
track_fixture "$SYP" || die_hard "не удалось зафиксировать identity внешней фикстуры PID $SYP"
set +e
"$T/procstop" --list "$SYROOT" "$SYROOT/Contents/MacOS/AI Usage Widget" > "$T/out12a.txt" 2>&1
RC12A=$?
"$T/procstop" --stop "$SYROOT" "$SYROOT/Contents/MacOS/AI Usage Widget" 2 > "$T/out12b.txt" 2>&1
RC12B=$?
assert "(12) MacOS — symlink-каталог наружу: --list → rc=7" [ "$RC12A" -eq 7 ]
assert "(12) MacOS — symlink-каталог наружу: --stop → rc=7" [ "$RC12B" -eq 7 ]
assert "(12) внешняя фикстура ЖИВА (сигналов не было)"      bash -c "kill -0 $SYP 2>/dev/null"
assert "(12) TERM не отправлялся"                           bash -c "! grep -q 'TERM отправлен' '$T/out12b.txt'"
stop_fixture "$SYP"

# --- (13) CR-04 раунд 3: symlink ПРОМЕЖУТОЧНОГО Contents наружу → rc=7 --------
OUTSIDE2="$T/outside-contents"; mkdir -p "$OUTSIDE2/MacOS"
cp "$T/sleeper" "$OUTSIDE2/MacOS/AI Usage Widget"
CLROOT="$T/Boundary Contents Link.app"; mkdir -p "$CLROOT"
ln -s "$OUTSIDE2" "$CLROOT/Contents"
"$OUTSIDE2/MacOS/AI Usage Widget" 8 & CLP=$!
sleep 0.25
track_fixture "$CLP" || die_hard "не удалось зафиксировать identity внешней фикстуры PID $CLP"
set +e
"$T/procstop" --list "$CLROOT" "$CLROOT/Contents/MacOS/AI Usage Widget" > "$T/out13a.txt" 2>&1
RC13A=$?
"$T/procstop" --stop "$CLROOT" "$CLROOT/Contents/MacOS/AI Usage Widget" 2 > "$T/out13b.txt" 2>&1
RC13B=$?
assert "(13) Contents — symlink наружу: --list → rc=7"      [ "$RC13A" -eq 7 ]
assert "(13) Contents — symlink наружу: --stop → rc=7, цель жива" \
  bash -c "[ $RC13B -eq 7 ] && kill -0 $CLP 2>/dev/null"
stop_fixture "$CLP"

# --- (14) WR-06: cleanup НЕ сигналит историческим и чужой-identity PID --------
#     Перехват kill фиксирует любой сигнал; -0 (проба состояния) — не сигнал.
: > "$T/cleanup-calls.log"
kill() { # временный перехват ТОЛЬКО для проверок (14); -0 — проба, не логируется
  case " $* " in
    *" -0 "*) builtin kill "$@" ;;
    *) printf '%s\n' "$*" >> "$T/cleanup-calls.log" ;;
  esac
  return 0
}
# (14a) исторический (несуществующий) PID в наборе — НОЛЬ сигналов
STALE=999999
builtin kill -0 "$STALE" 2>/dev/null \
  && { unset -f kill; die_hard "синтетический PID $STALE неожиданно существует — проба невозможна"; }
printf '%s\t%s\t%s\n' "$STALE" "bogus birth" "bogus comm" >> "$PIDS_FILE"
cleanup_tracked_pids
assert "(14a) исторический PID: ноль TERM/KILL"    bash -c "[ ! -s '$T/cleanup-calls.log' ]"
# (14b) ЖИВОЙ процесс с ИЗМЕНЁННОЙ identity (чужой birth/comm) — НОЛЬ сигналов
start_fixture "$EXE" 8
CID=$FIXTURE_PID
untrack_fixture "$CID"
printf '%s\t%s\t%s\n' "$CID" "Thu Jan  1 00:00:00 1970" "bogus comm" >> "$PIDS_FILE"
cleanup_tracked_pids
assert "(14b) изменённая identity: ноль TERM/KILL" bash -c "[ ! -s '$T/cleanup-calls.log' ]"
assert "(14b) процесс с чужой identity не тронут"  bash -c "kill -0 $CID 2>/dev/null"
unset -f kill
stop_fixture "$CID"

if [ "$failed" -ne 0 ]; then
  printf 'self-test ЗАВЕРШЁН С ОШИБКАМИ: %d/%d проверок нарушено\n' "$failed" "$total" >&2
  exit 1
fi
printf 'self-test: %d/%d проверок PASS; изоляция: только собственные короткоживущие C-фикстуры (identity-снимок uid+birth+comm, сверка перед каждым сигналом), настоящие приложения не тронуты\n' "$total" "$total"
exit 0
