#!/bin/bash
# verify-install.sh — платформенная приёмка AI Usage Widget по ПОДПИСАННЫМ бинарям (план 01-03-T1, PLAT-01).
#
# Режимы:
#   (без аргументов)      — проверка УСТАНОВЛЕННОГО "$HOME/Applications/AI Usage Widget.app"
#                           (+ pluginkit-регистрация и наблюдение контейнера группы)
#   --app-path <bundle>   — те же бандл-локальные проверки (a–e) по пути staged-копии;
#                           системные проверки (pluginkit, контейнер) пропускаются — staged ещё не установлен
#   --self-test           — поведенческая самопроверка на синтетических фикстурах и заглушке codesign
#                           во временном каталоге; реальные бинари и установка не затрагиваются
#
# Ожидаемая команда (независимая точка отсчёта): файл scripts/expected-team.local — одна строка TeamID
# (10 латинских букв/цифр), создаётся владельцем ДО первой сборки по docs/phase-01-setup.ru.md (раздел 6а).
# Происхождение TeamID — Xcode/аккаунт владельца, НЕ подпись продукта и НЕ вывод этого скрипта.
# Содержимое конфига в вывод не дублируется (сравнение — да/нет).
# Личные данные не печатаются: Authority выводится редацированным (вид подписи и TeamID допустимы).
#
# Срок подписи (шаг g) — наблюдение, не PASS/FAIL: измеренные даты профиля ИЛИ фактическая NotAfter
# применимого сертификата подписи (сертификат извлекается из подписи: codesign --extract-certificates).
# security find-identity источником срока НЕ является. «Профиля нет» — факт, не бессрочность.
#
# bash 3.2 совместим (без bash4-конструкций). Выход: 0 — PASS; 1 — нарушение; 2 — использование.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

APP_BUNDLE_NAME="AI Usage Widget.app"
APPEX_NAME="AiUsageWidget.appex"
APP_BUNDLE_ID="com.serzhsharapa.aiusage"
APPEX_BUNDLE_ID="com.serzhsharapa.aiusage.widget"
GROUP_SUFFIX="group.aiusage"
WIDGET_EXTENSION_POINT="com.apple.widgetkit-extension"

KEY_SANDBOX="com.apple.security.app-sandbox"
KEY_NETWORK_CLIENT="com.apple.security.network.client"
KEY_GROUPS="com.apple.security.application-groups"
# Quick 261018-jd8: read-only доступ к файлам, ЯВНО выбранным владельцем в
# NSOpenPanel (импорт auth.json Codex CLI / Kilo). Только чтение пользовательского
# выбора; read-write и прочие файловые права остаются посторонними.
KEY_USER_SELECTED_RO="com.apple.security.files.user-selected.read-only"

# Служебные метаданные подписи ОС: подпись может добавить их сама; правами приложения они
# НЕ считаются и учитываются этим отдельным явным списком исключений (план 01-03-T1, п. c).
SIG_METADATA_KEYS="com.apple.security.get-task-allow"

# openssl системный (LibreSSL): только чтение DER-сертификата, извлечённого из подписи.
OPENSSL_BIN="${AIUSAGE_OPENSSL:-/usr/bin/openssl}"

vf_fail() { # правило, деталь
  printf 'FAIL: %s: %s\n' "$1" "$2" >&2
  return 1
}

print_step() { printf '  %s\n' "$1"; }

# ---------------------------------------------------------------------------
# Ожидаемая команда владельца (план 01-03-T1, п. b)
# ---------------------------------------------------------------------------
load_expected_team() { # печатает TeamID; при проблемах печатает FAIL-причину и следующий шаг, rc!=0
  local cfg="${AIUSAGE_EXPECTED_TEAM_FILE:-$SCRIPT_DIR/expected-team.local}"
  local team
  if [ ! -f "$cfg" ]; then
    printf 'FAIL: конфиг-ожидаемой-команды: файл %s не найден.\n' "$cfg" >&2
    printf 'Следующий шаг: создай файл по инструкции docs/phase-01-setup.ru.md (раздел 6а) — одна строка TeamID из Xcode > Settings > Accounts.\n' >&2
    return 1
  fi
  team="$(tr -d '[:space:]' < "$cfg")"
  if [ -z "$team" ]; then
    printf 'FAIL: конфиг-ожидаемой-команды: файл %s пуст.\n' "$cfg" >&2
    printf 'Следующий шаг: впиши в файл одну строку — свой TeamID (10 латинских букв/цифр) из Xcode > Settings > Accounts.\n' >&2
    return 1
  fi
  if ! printf '%s' "$team" | grep -Eq '^[A-Za-z0-9]{10}$'; then
    printf 'FAIL: конфиг-ожидаемой-команды: содержимое не похоже на TeamID (ожидается ровно 10 латинских букв/цифр, одна строка).\n' >&2
    printf 'Следующий шаг: исправь %s — TeamID берётся из Xcode > Settings > Accounts (или код в скобках в выводе security find-identity), НЕ из подписи продукта.\n' "$cfg" >&2
    return 1
  fi
  printf '%s' "$team"
}

# ---------------------------------------------------------------------------
# Разбор вывода codesign -dv --verbose=4 (b). WR-03: DV держится ТОЛЬКО в памяти —
# сырой текст с именем identity (Authority) не персистится ни в один файл;
# в лог/терминал Authority попадает исключительно через redact_authority.
# ---------------------------------------------------------------------------
dv_team() { # текст DV; печатает TeamIdentifier или NOTSET (ad-hoc/без команды)
  local t
  t="$(printf '%s\n' "$1" | grep -m1 '^TeamIdentifier=' | cut -d= -f2- || true)"
  case "$t" in ""|"not set"|"NOT SET") printf 'NOTSET' ;; *) printf '%s' "$t" ;; esac
}
dv_is_adhoc() { printf '%s\n' "$1" | grep -m1 -q '^Signature=adhoc'; }
dv_leaf_authority() { printf '%s\n' "$1" | grep -m1 '^Authority=' | cut -d= -f2- || true; }
dv_identifier() { printf '%s\n' "$1" | grep -m1 '^Identifier=' | cut -d= -f2- || true; }
redact_authority() { # печатает Authority без личного имени (вид подписи и TeamID остаются)
  sed -E 's/^(Apple Development|Apple Distribution|Mac Developer|iPhone Developer): [^(]*\(([A-Za-z0-9]{10})[^)]*\).*/\1: [REDACTED] (\2)/' <<< "$1"
}

# ---------------------------------------------------------------------------
# Identity Info.plist (CR-05): точные bundle id / package type / extension point
# ---------------------------------------------------------------------------
plist_bid() { # Info.plist; печатает CFBundleIdentifier или пусто
  plutil -extract CFBundleIdentifier raw -o - "$1" 2>/dev/null || true
}
plist_package_type() { # Info.plist; печатает CFBundlePackageType или пусто
  plutil -extract CFBundlePackageType raw -o - "$1" 2>/dev/null || true
}
plist_extension_point() { # Info.plist appex; печатает NSExtension.NSExtensionPointIdentifier или пусто
  plutil -extract NSExtension.NSExtensionPointIdentifier raw -o - "$1" 2>/dev/null || true
}
check_identity_plists() { # app-plist appex-plist — чужой продукт отвергается ДО подписи
  local papp="$1" pappex="$2" bid ptype ep
  bid="$(plist_bid "$papp")"
  if [ "$bid" != "$APP_BUNDLE_ID" ]; then
    vf_fail "identity-app" "CFBundleIdentifier приложения '${bid:-отсутствует}' != ожидаемому $APP_BUNDLE_ID (чужой продукт)"; return 1
  fi
  ptype="$(plist_package_type "$papp")"
  if [ "$ptype" != "APPL" ]; then
    vf_fail "identity-app" "CFBundlePackageType приложения '${ptype:-отсутствует}' != APPL"; return 1
  fi
  bid="$(plist_bid "$pappex")"
  if [ "$bid" != "$APPEX_BUNDLE_ID" ]; then
    vf_fail "identity-appex" "CFBundleIdentifier расширения '${bid:-отсутствует}' != ожидаемому $APPEX_BUNDLE_ID (чужой продукт)"; return 1
  fi
  ptype="$(plist_package_type "$pappex")"
  if [ "$ptype" != "XPC!" ]; then
    vf_fail "identity-appex" "CFBundlePackageType расширения '${ptype:-отсутствует}' != XPC!"; return 1
  fi
  ep="$(plist_extension_point "$pappex")"
  if [ "$ep" != "$WIDGET_EXTENSION_POINT" ]; then
    vf_fail "identity-appex" "NSExtensionPointIdentifier '${ep:-отсутствует}' != ожидаемому $WIDGET_EXTENSION_POINT"; return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Права подписанных бинарей (c)
# ---------------------------------------------------------------------------
ent_keys() { grep -o '<key>[^<]*</key>' "$1" 2>/dev/null | sed -e 's/^<key>//' -e 's|</key>$||'; }
esc_key() { printf '%s' "$1" | sed 's/\./\\./g'; } # plutil keypath: литеральные точки экранируются
ent_bool() { plutil -extract "$(esc_key "$2")" raw -o - "$1" 2>/dev/null || true; }
ent_groups_value() { # файл; печатает единственную группу; rc=1 нет/пусто, rc=2 больше одной
  local json arr
  json="$(plutil -extract "$(esc_key "$KEY_GROUPS")" json -o - "$1" 2>/dev/null)" || return 1
  arr="$(printf '%s' "$json" | sed -e 's/^\[//' -e 's/\]$//' -e 's/^"//' -e 's/"$//' -e 's/[[:space:]]//g')"
  case "$arr" in *'","'*) return 2 ;; esac
  [ -n "$arr" ] || return 1
  printf '%s\n' "$arr"
}

is_sig_metadata() { # ключ — служебное метаданное подписи ОС?
  case " $SIG_METADATA_KEYS " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

check_entitlements_app() { # файл-права app: ровно sandbox+network.client+group+user-selected.read-only(+метаданные ОС)
  local f="$1" k keys
  [ -s "$f" ] || { vf_fail "права-app" "права приложения не найдены в подписи"; return 1; }
  keys="$(ent_keys "$f")"
  while read -r k; do
    [ -n "$k" ] || continue
    case "$k" in
      "$KEY_SANDBOX"|"$KEY_NETWORK_CLIENT"|"$KEY_GROUPS"|"$KEY_USER_SELECTED_RO") : ;;
      *) if ! is_sig_metadata "$k"; then vf_fail "права-app" "посторонний ключ прав: $k"; return 1; fi ;;
    esac
  done <<< "$keys"
  printf '%s\n' "$keys" | grep -qx "$KEY_SANDBOX" || { vf_fail "права-app" "нет $KEY_SANDBOX"; return 1; }
  printf '%s\n' "$keys" | grep -qx "$KEY_NETWORK_CLIENT" || { vf_fail "права-app" "нет $KEY_NETWORK_CLIENT (Outgoing Connections)"; return 1; }
  printf '%s\n' "$keys" | grep -qx "$KEY_GROUPS" || { vf_fail "права-app" "нет $KEY_GROUPS"; return 1; }
  printf '%s\n' "$keys" | grep -qx "$KEY_USER_SELECTED_RO" || { vf_fail "права-app" "нет $KEY_USER_SELECTED_RO (импорт auth.json через NSOpenPanel)"; return 1; }
  [ "$(ent_bool "$f" "$KEY_SANDBOX")" = "true" ] || { vf_fail "права-app" "песочница не включена ($KEY_SANDBOX != true)"; return 1; }
  [ "$(ent_bool "$f" "$KEY_NETWORK_CLIENT")" = "true" ] || { vf_fail "права-app" "network.client не true"; return 1; }
  [ "$(ent_bool "$f" "$KEY_USER_SELECTED_RO")" = "true" ] || { vf_fail "права-app" "user-selected.read-only не true"; return 1; }
  local g
  g="$(ent_groups_value "$f")" || { vf_fail "права-app" "группа отсутствует или её больше одной"; return 1; }
  printf '%s\n' "$g"
  return 0
}

check_entitlements_appex() { # файл-права appex: ДОПУСТИМОЕ МНОЖЕСТВО РОВНО {app-sandbox, application-groups}
  local f="$1" k keys
  [ -s "$f" ] || { vf_fail "права-appex" "права расширения не найдены в подписи"; return 1; }
  keys="$(ent_keys "$f")"
  while read -r k; do
    [ -n "$k" ] || continue
    case "$k" in
      "$KEY_SANDBOX"|"$KEY_GROUPS") : ;;
      com.apple.security.network.*) vf_fail "права-appex" "сетевое право у расширения: $k"; return 1 ;;
      keychain-access-groups) vf_fail "права-appex" "keychain-access-groups у расширения запрещены"; return 1 ;;
      *) if ! is_sig_metadata "$k"; then vf_fail "права-appex" "посторонний ключ прав расширения: $k"; return 1; fi ;;
    esac
  done <<< "$keys"
  printf '%s\n' "$keys" | grep -qx "$KEY_SANDBOX" || { vf_fail "права-appex" "нет $KEY_SANDBOX"; return 1; }
  printf '%s\n' "$keys" | grep -qx "$KEY_GROUPS" || { vf_fail "права-appex" "нет $KEY_GROUPS"; return 1; }
  [ "$(ent_bool "$f" "$KEY_SANDBOX")" = "true" ] || { vf_fail "права-appex" "песочница расширения не включена"; return 1; }
  local g
  g="$(ent_groups_value "$f")" || { vf_fail "права-appex" "группа отсутствует или её больше одной"; return 1; }
  printf '%s\n' "$g"
  return 0
}

# ---------------------------------------------------------------------------
# Четырёхсторонняя сверка групп (d)
# ---------------------------------------------------------------------------
plist_gid() { # Info.plist; печатает AppGroupID или пусто
  plutil -extract AppGroupID raw -o - "$1" 2>/dev/null || true
}
check_four_way() { # g1 g2 g3 g4 expected_team — подпись app, подпись appex, Info.plist app, Info.plist appex
  local g1="$1" g2="$2" g3="$3" g4="$4" team="$5"
  [ -n "$g1" ] && [ -n "$g2" ] && [ -n "$g3" ] && [ -n "$g4" ] || { vf_fail "сверка-групп" "не все четыре значения группы определены"; return 1; }
  if [ "$g1" != "$g2" ] || [ "$g1" != "$g3" ] || [ "$g1" != "$g4" ]; then
    vf_fail "сверка-групп" "четырёхстороннее равенство нарушено (подпись app / подпись appex / Info.plist app / Info.plist appex)"
    return 1
  fi
  if [ "$g1" != "$team.$GROUP_SUFFIX" ]; then
    vf_fail "формат-gid" "группа '$g1' не имеет вида <TeamIdentifier>.$GROUP_SUFFIX для ожидаемой команды"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Срок подписи — наблюдение (g)
# ---------------------------------------------------------------------------
observe_expiry() { # bundle label
  local bundle="$1" label="$2" prof cre exp na pfx
  prof="$bundle/Contents/embedded.provisionprofile"
  if [ -f "$prof" ]; then
    cre="$(security cms -D -i "$prof" 2>/dev/null | plutil -extract CreationDate raw -o - - 2>/dev/null || true)"
    exp="$(security cms -D -i "$prof" 2>/dev/null | plutil -extract ExpirationDate raw -o - - 2>/dev/null || true)"
    if [ -n "$exp" ]; then
      printf '  наблюдение: %s: профиль: создан %s, истекает %s\n' "$label" "${cre:-неизвестно}" "$exp"
    else
      printf '  наблюдение: %s: профиль присутствует, но даты не читаются (security cms / plutil)\n' "$label"
    fi
  else
    printf '  наблюдение: %s: embedded.provisionprofile отсутствует (это НЕ бессрочность — срок диктует сертификат подписи)\n' "$label"
    # WR-03: извлечённый листовой сертификат содержит имя владельца (CN) —
    # это identity-данные; файл удаляется НЕМЕДЛЕННО после чтения срока,
    # не дожидаясь EXIT-cleanup.
    pfx="$TMPDIR_WORK/cert-$label"
    if codesign -d --extract-certificates="$pfx" "$bundle" >/dev/null 2>&1 && [ -f "${pfx}0" ]; then
      na="$("$OPENSSL_BIN" x509 -inform der -noout -enddate -in "${pfx}0" 2>/dev/null | sed 's/^notAfter=//')"
      rm -f "${pfx}0" "${pfx}1" "${pfx}2"
      if [ -n "$na" ]; then
        printf '  наблюдение: %s: сертификат подписи (NotAfter, из подписи): %s\n' "$label" "$na"
      else
        printf '  наблюдение: %s: сертификат извлечён, но срок не прочитан (openssl)\n' "$label"
      fi
    else
      rm -f "${pfx}0" "${pfx}1" "${pfx}2"
      printf '  наблюдение: %s: срок сертификата определить не удалось (сертификат не извлекается из подписи)\n' "$label"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Основная проверка бандла (используется в обоих живых режимах)
# ---------------------------------------------------------------------------
TMPDIR_WORK=""
cleanup() { [ -n "${TMPDIR_WORK:-}" ] && rm -rf "$TMPDIR_WORK"; return 0; }
trap cleanup EXIT

verify_bundle() { # $1 = путь к .app; $2 = режим (installed|staged); ожидаемая команда в $3
  local APP="$1" MODE="$2" EXPECTED_TEAM="$3"
  local APPEX="$APP/Contents/PlugIns/$APPEX_NAME"

  printf 'Режим: %s; бандл: %s\n' "$MODE" "$APP"

  # a) структура
  [ -d "$APP" ] || { vf_fail "бандл-структура" "бандл не найден: $APP"; return 1; }
  [ -d "$APPEX" ] || { vf_fail "бандл-структура" "расширение не найдено: $APPEX"; return 1; }
  print_step "[a] структура бандла и appex — ok"

  # a2) identity Info.plist (CR-05): чужой продукт той же команды отвергается
  #     ДО любых проверок подписи и, в вызове из build.sh, ДО закрытия старой
  #     установки и замены: точные bundle id, package type, extension point.
  check_identity_plists "$APP/Contents/Info.plist" "$APPEX/Contents/Info.plist" || return 1
  print_step "[a2] identity Info.plist: app=$APP_BUNDLE_ID (APPL), appex=$APPEX_BUNDLE_ID (XPC!), точка расширения $WIDGET_EXTENSION_POINT — ok"

  # b) подпись: данные codesign -dv ТОЛЬКО в памяти (WR-03: сырой DV с именем
  #    identity не пишется на диск ни в какой точке)
  local dv_app dv_appex
  if ! dv_app="$(codesign -dv --verbose=4 "$APP" 2>&1)"; then
    vf_fail "подпись" "codesign -dv не прочитал подпись app"; return 1
  fi
  if ! dv_appex="$(codesign -dv --verbose=4 "$APPEX" 2>&1)"; then
    vf_fail "подпись" "codesign -dv не прочитал подпись appex"; return 1
  fi

  if dv_is_adhoc "$dv_app" || dv_is_adhoc "$dv_appex"; then
    vf_fail "подпись-adhoc" "подпись ad-hoc недопустима (требуется Apple Development личной команды)"; return 1
  fi
  local team_app team_appex auth_app auth_appex id_app id_appex
  team_app="$(dv_team "$dv_app")"
  team_appex="$(dv_team "$dv_appex")"
  if [ "$team_app" = "NOTSET" ]; then { vf_fail "подпись-adhoc" "у app пустой/not set TeamIdentifier"; return 1; }; fi
  if [ "$team_appex" = "NOTSET" ]; then { vf_fail "подпись-adhoc" "у appex пустой/not set TeamIdentifier"; return 1; }; fi
  auth_app="$(dv_leaf_authority "$dv_app")"
  auth_appex="$(dv_leaf_authority "$dv_appex")"
  printf '%s' "$auth_app" | grep -q 'Apple Development' || { vf_fail "authority" "у app нет Authority «Apple Development» (получено: $(redact_authority "$auth_app"))"; return 1; }
  printf '%s' "$auth_appex" | grep -q 'Apple Development' || { vf_fail "authority" "у appex нет Authority «Apple Development»"; return 1; }
  print_step "[b] Authority: app — $(redact_authority "$auth_app"); appex — $(redact_authority "$auth_appex")"
  if [ "$team_app" != "$team_appex" ]; then
    vf_fail "team-несовпадение-app-appex" "TeamIdentifier app ($team_app) != appex ($team_appex)"; return 1
  fi
  if [ "$team_app" != "$EXPECTED_TEAM" ]; then
    vf_fail "team-несовпадение-с-ожидаемой" "TeamIdentifier бинарей ($team_app) НЕ совпадает с ожидаемой командой владельца (согласованность подписей между собой недостаточна)"; return 1
  fi
  print_step "[b] TeamIdentifier: app=$team_app, appex=$team_appex; совпадение с ожидаемой командой: да"

  # b2) signed Identifier (CR-05): подпись обязана указывать на ТОТ ЖЕ продукт,
  #     что и Info.plist — подписанный чужой бандл не проходит приёмку.
  id_app="$(dv_identifier "$dv_app")"
  id_appex="$(dv_identifier "$dv_appex")"
  if [ "$id_app" != "$APP_BUNDLE_ID" ]; then
    vf_fail "identity-подписи" "signed Identifier app '${id_app:-отсутствует}' != $APP_BUNDLE_ID (чужой продукт)"; return 1
  fi
  if [ "$id_appex" != "$APPEX_BUNDLE_ID" ]; then
    vf_fail "identity-подписи" "signed Identifier appex '${id_appex:-отсутствует}' != $APPEX_BUNDLE_ID (чужой продукт)"; return 1
  fi
  print_step "[b2] signed Identifier: app=$id_app, appex=$id_appex — совпадает с Info.plist"

  # c) фактические права подписанных бинарей
  local ent_app="$TMPDIR_WORK/ent-app.xml" ent_appex="$TMPDIR_WORK/ent-appex.xml"
  codesign -d --entitlements - --xml "$APP" > "$ent_app" 2>/dev/null || { vf_fail "права-app" "codesign не прочитал права app"; return 1; }
  codesign -d --entitlements - --xml "$APPEX" > "$ent_appex" 2>/dev/null || { vf_fail "права-appex" "codesign не прочитал права appex"; return 1; }
  local group_app_signed group_appex_signed
  group_app_signed="$(check_entitlements_app "$ent_app")" || return 1
  group_appex_signed="$(check_entitlements_appex "$ent_appex")" || return 1
  print_step "[c] права app: {app-sandbox, network.client, application-groups=[1], files.user-selected.read-only} — ok"
  print_step "[c] права appex: ровно {app-sandbox, application-groups} — ok"

  # d) четырёхсторонняя сверка групп: подписи ×2 + Info.plist ×2
  local gid_plist_app gid_plist_appex
  gid_plist_app="$(plist_gid "$APP/Contents/Info.plist")"
  gid_plist_appex="$(plist_gid "$APPEX/Contents/Info.plist")"
  check_four_way "$group_app_signed" "$group_appex_signed" "$gid_plist_app" "$gid_plist_appex" "$EXPECTED_TEAM" || return 1
  print_step "[d] сверка групп 4 стороны: подпись app = подпись appex = Info.plist app = Info.plist appex = $gid_plist_app — ok"

  # e) целостность подписи
  codesign -vvv --deep "$APP" >/dev/null 2>&1 || { vf_fail "целостность-подписи" "codesign -vvv --deep не прошёл"; return 1; }
  print_step "[e] целостность подписи (codesign -vvv --deep) — ok"

  if [ "$MODE" = "installed" ]; then
    # f) регистрация расширения (WR-01, раунд 2): доказательство — запись pluginkit
    #    с ТОЧНЫМ (каноническим) путём установленного appex, верной точкой расширения
    #    и допустимым election-состоянием. Формат verbose-ответа — записи
    #    «header: id(версия) [+/-состояние] + поля Path/SDK» (структура сверена
    #    read-only запросом к системе; man pluginkit.8: '+' — выбран, '-' — игнор,
    #    '!' — только отладка, '=' — замещён, '?' — неизвестно; header без маркера —
    #    явного election нет). Парсер коммитит КАЖДУЮ пару Path+SDK при получении
    #    второго поля, граница записи — header: порядок версий не влияет, никакая
    #    запись не затирается, ignored/superseded не принимаются.
    #    Ключ -mD: man — «с -D возвращаются все eligible-экземпляры» (без него
    #    сокращение до последнего); нужны все физические копии идентификатора.
    local want_path want_real pk_out pk_rc pk_records exact stale_other rpath rstate rsdk
    want_path="$APP/Contents/PlugIns/$APPEX_NAME"
    want_real="$(realpath "$want_path" 2>/dev/null || printf '%s' "$want_path")"
    set +e
    pk_out="$(pluginkit -mDvv -i "$APPEX_BUNDLE_ID" 2>&1)"
    pk_rc=$?
    set -e
    if [ "$pk_rc" -ne 0 ]; then
      vf_fail "регистрация-расширения" "pluginkit завершился с кодом $pk_rc — регистрация не подтверждена (проверять вывод при ошибке инструмента нельзя)"; return 1
    fi
    if printf '%s\n' "$pk_out" | grep -q '(no matches)'; then
      vf_fail "регистрация-расширения" "расширение не зарегистрировано (pluginkit: no matches; запусти приложение)"; return 1
    fi
    # Разбор записей → строки «state<TAB>path<TAB>sdk»; сравнение путей ТОЧНОЕ
    # (после канонизации realpath: несуществующий путь остаётся как есть и не
    # совпадёт с каноническим установленным appex).
    pk_records="$(printf '%s\n' "$pk_out" | awk '
      function resetpending() { path = ""; sdk = "" }
      function maybecommit()  { if (path != "" && sdk != "") { print state "\t" path "\t" sdk; resetpending() } }
      /^[[:space:]]*Path[[:space:]]*=[[:space:]]*/ { path = $0; sub(/^[[:space:]]*Path[[:space:]]*=[[:space:]]*/, "", path); maybecommit(); next }
      /^[[:space:]]*SDK[[:space:]]*=[[:space:]]*/  { sdk = $0; sub(/^[[:space:]]*SDK[[:space:]]*=[[:space:]]*/, "", sdk); maybecommit(); next }
      /^[[:space:]]*[-+!=?]?[[:space:]]*[A-Za-z0-9][A-Za-z0-9.]*\([^)]*\)[[:space:]]*$/ {
        resetpending(); line = $0; sub(/^[[:space:]]*/, "", line)
        state = (line ~ /^[-+!=?]/) ? substr(line, 1, 1) : ""
        next
      }
      { next }
    ')"
    exact=""; stale_other=0
    # Разбиваем строки вручную (не IFS=tab: пустой первый поле-маркер иначе
    # схлопывается — ведущие IFS-пробелы съедаются read).
    while IFS= read -r recline; do
      [ -n "$recline" ] || continue
      case "$recline" in
        *$'\t'*) ;;
        *) continue ;; # строка без разделителя — не запись
      esac
      rstate="${recline%%$'\t'*}"
      rest="${recline#*$'\t'}"
      rpath="${rest%%$'\t'*}"
      rsdk="${rest#*$'\t'}"
      [ -n "$rpath" ] || continue
      rpath="$(realpath "$rpath" 2>/dev/null || printf '%s' "$rpath")"
      if [ "$rpath" = "$want_real" ] && [ "$rsdk" = "$WIDGET_EXTENSION_POINT" ] && { [ -z "$rstate" ] || [ "$rstate" = "+" ]; }; then
        exact="${rstate:-нет-маркера}"
      else
        stale_other=$((stale_other+1))
      fi
    done <<EOF
$pk_records
EOF
    if [ -z "$exact" ]; then
      vf_fail "регистрация-расширения" "нет АКТИВНОЙ регистрации с ТОЧНЫМ путём $want_path и SDK $WIDGET_EXTENSION_POINT (записи с состоянием ignore/superseded/чужим путём доказательством не являются)"; return 1
    fi
    if [ "$stale_other" -gt 0 ]; then
      print_step "[f] наблюдение: посторонних/неактивных записей того же ID: $stale_other"
    fi
    print_step "[f] расширение зарегистрировано: точный путь $want_path, SDK $WIDGET_EXTENSION_POINT (состояние election: активное)"

    # g) срок подписи — измеренное наблюдение ПО КАЖДОМУ бинарю
    observe_expiry "$APP" "app"
    observe_expiry "$APPEX" "appex"

    # h) наблюдение: имена файлов в контейнере группы (прямой путь от GID, без wildcard)
    local cdir="$HOME/Library/Group Containers/$gid_plist_app"
    if [ -d "$cdir" ]; then
      print_step "[h] контейнер группы ($cdir), имена файлов:"
      ls -1 "$cdir" 2>/dev/null | sed 's/^/      /' || print_step "      (пусто)"
    else
      print_step "[h] контейнер группы не найден: $cdir (записи ещё не было?)"
    fi
  else
    print_step "[f/g/h] системные проверки (pluginkit, срок, контейнер) в режиме staged пропущены"
  fi

  printf 'PASS: все обязательные правила выполнены%s\n' "$([ "$MODE" = "installed" ] && printf ' (срок и контейнер — наблюдения выше)' || printf ' (staged)')"
  return 0
}

# ---------------------------------------------------------------------------
# SELF-TEST (план 01-03-T1, п. 4): синтетические фикстуры + заглушка codesign;
# живой вызов codesign/pluginkit/security не выполняется, реальная установка не читается.
# ---------------------------------------------------------------------------
self_test() {
  local T STUBBIN FX rc=0 total=0 failed=0 SCRIPT_ABS
  T="$(mktemp -d "${TMPDIR:-/tmp}/aiusage-verify-selftest.XXXXXX")"
  TMPDIR_WORK="$T" # общий trap cleanup увидит и дочистит при сбое
  STUBBIN="$T/bin"; FX="$T/fx"; mkdir -p "$STUBBIN" "$FX" "$T/kidtmp" "$T/kidtmp-i"
  SCRIPT_ABS="$SCRIPT_DIR/verify-install.sh"

  # ---- заглушка codesign: читает фикстуры по стороне бандла (.appex или нет);
  #      при -dv дополнительно детектирует НЕПРЕДВИДЕННЫЙ сырой DV-файл с именем
  #      identity на диске (WR-03: до правки dv-*.txt писались до редакции) ----
  cat > "$STUBBIN/codesign" <<'STUB'
#!/bin/bash
# codesign stub (self-test only)
for last; do :; done
path="$last"
case "$path" in
  *.appex*) side="appex" ;;
  *) side="app" ;;
esac
scan="$*"
case "$scan" in
  *--entitlements*) cat "$AIUSAGE_STUB_FIXTURES/ent-$side.xml"; exit 0 ;;
  *--verbose=4*|*-dv*)
    cat "$AIUSAGE_STUB_FIXTURES/dv-$side.txt" >&2
    if [ -n "${AIUSAGE_RAW_LEAK_PROBE_DIR:-}" ]; then
      hits="$(grep -rl 'Fixture Owner' "$AIUSAGE_RAW_LEAK_PROBE_DIR"/aiusage-verify.* 2>/dev/null || true)"
      [ -n "$hits" ] && printf 'RAW_DV_ON_DISK %s\n' "$hits" >> "${AIUSAGE_RAW_LEAK_MARKER}"
    fi
    exit 0 ;;
  *-vvv*|*--deep*) echo "... valid on disk"; echo "... satisfied its Designated Requirement"; exit 0 ;;
esac
exit 0
STUB
  chmod +x "$STUBBIN/codesign"

  # ---- заглушка pluginkit: печатает содержимое файла-фикстуры и код из окружения ----
  cat > "$STUBBIN/pluginkit" <<'STUB'
#!/bin/bash
# pluginkit stub (self-test only)
if [ -n "${AIUSAGE_PK_OUT_FILE:-}" ] && [ -f "$AIUSAGE_PK_OUT_FILE" ]; then
  cat "$AIUSAGE_PK_OUT_FILE"
fi
exit "${AIUSAGE_PK_RC:-0}"
STUB
  chmod +x "$STUBBIN/pluginkit"

  # ---- сборка одного fixture-набора: dv-тексты, права, Info.plist, expected ----
  mk_fixtures() { # dir team gid_in_appex_plist appex_plist_gid extra_ent_appex [extra_ent_app]
    local d="$1" team="$2" appex_plist_gid="$3" extra_appex="$4" extra_app="${5:-}"
    mkdir -p "$d"
    printf 'Executable=/fixture/AI Usage Widget.app/Contents/MacOS/AI Usage Widget\nIdentifier=com.serzhsharapa.aiusage\nFormat=bundle with Mach-O universal (arm64)\nSignature size=9078\nAuthority=Apple Development: Fixture Owner (%s)\nAuthority=Apple Worldwide Developer Relations Certification Authority\nAuthority=Apple Root CA\nSigned Time=1 Jan 2026\nTeamIdentifier=%s\n' "$team" "$team" > "$d/dv-app.txt"
    printf 'Executable=/fixture/.../AiUsageWidget.appex/Contents/MacOS/AiUsageWidget\nIdentifier=com.serzhsharapa.aiusage.widget\nFormat=bundle with Mach-O universal\nSignature size=9078\nAuthority=Apple Development: Fixture Owner (%s)\nTeamIdentifier=%s\n' "$team" "$team" > "$d/dv-appex.txt"
    { printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n\t<key>com.apple.security.app-sandbox</key>\n\t<true/>\n\t<key>com.apple.security.network.client</key>\n\t<true/>\n'
      if [ -n "$extra_app" ]; then printf '\t%s\n' "$extra_app"; fi
      printf '\t<key>com.apple.security.files.user-selected.read-only</key>\n\t<true/>\n\t<key>com.apple.security.application-groups</key>\n\t<array>\n\t\t<string>%s.group.aiusage</string>\n\t</array>\n</dict>\n</plist>\n' "$team"; } > "$d/ent-app.xml"
    { printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n\t<key>com.apple.security.app-sandbox</key>\n\t<true/>\n'
      if [ -n "$extra_appex" ]; then printf '\t%s\n' "$extra_appex"; fi
      printf '\t<key>com.apple.security.application-groups</key>\n\t<array>\n\t\t<string>%s.group.aiusage</string>\n\t</array>\n</dict>\n</plist>\n' "$team"; } > "$d/ent-appex.xml"
    mkdir -p "$d/bundle/AI Usage Widget.app/Contents/MacOS" \
             "$d/bundle/AI Usage Widget.app/Contents/PlugIns/$APPEX_NAME/Contents/MacOS"
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n\t<key>CFBundleIdentifier</key>\n\t<string>com.serzhsharapa.aiusage</string>\n\t<key>CFBundlePackageType</key>\n\t<string>APPL</string>\n\t<key>CFBundleExecutable</key>\n\t<string>AI Usage Widget</string>\n\t<key>AppGroupID</key>\n\t<string>%s.group.aiusage</string>\n</dict>\n</plist>\n' "$team" > "$d/bundle/AI Usage Widget.app/Contents/Info.plist"
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n\t<key>CFBundleIdentifier</key>\n\t<string>com.serzhsharapa.aiusage.widget</string>\n\t<key>CFBundlePackageType</key>\n\t<string>XPC!</string>\n\t<key>CFBundleExecutable</key>\n\t<string>AiUsageWidget</string>\n\t<key>NSExtension</key>\n\t<dict>\n\t\t<key>NSExtensionPointIdentifier</key>\n\t\t<string>com.apple.widgetkit-extension</string>\n\t</dict>\n\t<key>AppGroupID</key>\n\t<string>%s</string>\n</dict>\n</plist>\n' "$appex_plist_gid" > "$d/bundle/AI Usage Widget.app/Contents/PlugIns/$APPEX_NAME/Contents/Info.plist"
    printf 'touch\n' > "$d/bundle/AI Usage Widget.app/Contents/MacOS/AI Usage Widget"
    printf 'touch\n' > "$d/bundle/AI Usage Widget.app/Contents/PlugIns/$APPEX_NAME/Contents/MacOS/AiUsageWidget"
    printf '%s\n' "TESTTEAMID" > "$d/expected-team.local"
  }

  run_case() { # имя ожидаемый-rc(0|1) dir-фикстур [обязательный FAIL-фрагмент]
    local name="$1" want_rc="$2" fdir="$3" must="${4:-}" got rc
    total=$((total+1))
    set +e
    got="$(PATH="$STUBBIN:/usr/bin:/bin" \
           AIUSAGE_STUB_FIXTURES="$fdir" \
           AIUSAGE_EXPECTED_TEAM_FILE="$fdir/expected-team.local" \
           HOME="$fdir/home" \
           TMPDIR="$T/kidtmp" \
           AIUSAGE_RAW_LEAK_PROBE_DIR="$T/kidtmp" \
           AIUSAGE_RAW_LEAK_MARKER="$fdir/raw-leak.marker" \
           bash "$SCRIPT_ABS" --app-path "$fdir/bundle/AI Usage Widget.app" 2>&1)"
    rc=$?
    set -e
    if [ "$want_rc" = "0" ]; then
      if [ "$rc" -eq 0 ] && printf '%s' "$got" | grep -q '^PASS'; then
        printf '  ok   %s (принята, PASS)\n' "$name"
      else
        printf '  FAIL %s: валидная фикстура отвергнута (rc=%s)\n%s\n' "$name" "$rc" "$got" >&2; failed=$((failed+1))
      fi
    else
      if [ "$rc" -ne 0 ] && printf '%s' "$got" | grep -q '^FAIL:' \
         && { [ -z "$must" ] || printf '%s' "$got" | grep -q "$must"; }; then
        printf '  ok   %s (отвергнута: %s)\n' "$name" "$(printf '%s' "$got" | grep -m1 '^FAIL:' | cut -c1-90)"
      else
        printf '  FAIL %s: нарушение пропущено или упало на чужом правиле «%s» (rc=%s)\n%s\n' "$name" "$must" "$rc" "$got" >&2; failed=$((failed+1))
      fi
    fi
    # WR-03: сырой DV-файл с именем identity не должен появляться НИГДЕ за прогон
    if [ -s "$fdir/raw-leak.marker" ]; then
      printf '  FAIL %s: сырой DV с именем identity обнаружен на диске (WR-03)\n' "$name" >&2
      failed=$((failed+1))
    fi
    rm -rf "$T/kidtmp"; mkdir -p "$T/kidtmp"
  }

  # installed-режим (WR-01): бандл в $HOME/Applications, pluginkit-заглушка с кодом/выводом
  run_case_installed() { # имя ожидаемый-rc(0|1) dir-фикстур pk-out-файл pk-rc [FAIL-фрагмент]
    local name="$1" want_rc="$2" fdir="$3" pkout="$4" pkrc="$5" must="${6:-}" got rc
    total=$((total+1))
    mkdir -p "$fdir/home/Applications"
    rm -rf "$fdir/home/Applications/AI Usage Widget.app"
    cp -R "$fdir/bundle/AI Usage Widget.app" "$fdir/home/Applications/"
    set +e
    got="$(PATH="$STUBBIN:/usr/bin:/bin" \
           AIUSAGE_STUB_FIXTURES="$fdir" \
           AIUSAGE_EXPECTED_TEAM_FILE="$fdir/expected-team.local" \
           HOME="$fdir/home" \
           TMPDIR="$T/kidtmp-i" \
           AIUSAGE_PK_OUT_FILE="$pkout" \
           AIUSAGE_PK_RC="$pkrc" \
           bash "$SCRIPT_ABS" 2>&1)"
    rc=$?
    set -e
    if [ "$want_rc" = "0" ]; then
      if [ "$rc" -eq 0 ] && printf '%s' "$got" | grep -q '^PASS'; then
        printf '  ok   %s (принята, PASS)\n' "$name"
      else
        printf '  FAIL %s: валидная установка отвергнута (rc=%s)\n%s\n' "$name" "$rc" "$got" >&2; failed=$((failed+1))
      fi
    else
      if [ "$rc" -ne 0 ] && printf '%s' "$got" | grep -q '^FAIL:' \
         && { [ -z "$must" ] || printf '%s' "$got" | grep -q "$must"; }; then
        printf '  ok   %s (отвергнута: %s)\n' "$name" "$(printf '%s' "$got" | grep -m1 '^FAIL:' | cut -c1-90)"
      else
        printf '  FAIL %s: нарушение пропущено или упало на чужом правиле «%s» (rc=%s)\n%s\n' "$name" "$must" "$rc" "$got" >&2; failed=$((failed+1))
      fi
    fi
    rm -rf "$T/kidtmp-i"; mkdir -p "$T/kidtmp-i"
  }

  printf 'self-test verify-install.sh (синтетические фикстуры, заглушка codesign):\n'

  # V1 валидная фикстура — принимается
  mk_fixtures "$FX/v1" "TESTTEAMID" "TESTTEAMID.group.aiusage" ""
  run_case "V1 валидная фикстура" 0 "$FX/v1"

  # V2 appex с network.server
  mk_fixtures "$FX/v2" "TESTTEAMID" "TESTTEAMID.group.aiusage" '<key>com.apple.security.network.server</key><true/>'
  run_case "V2 appex network.server" 1 "$FX/v2" "сетевое право"

  # V3 appex с keychain-access-groups
  mk_fixtures "$FX/v3" "TESTTEAMID" "TESTTEAMID.group.aiusage" '<key>keychain-access-groups</key><array><string>TESTTEAMID.group.aiusage</string></array>'
  run_case "V3 appex keychain-access-groups" 1 "$FX/v3" "keychain-access-groups"

  # V4 appex с посторонним ключом
  mk_fixtures "$FX/v4" "TESTTEAMID" "TESTTEAMID.group.aiusage" '<key>com.apple.security.files.user-selected.read-only</key><true/>'
  run_case "V4 appex посторонний ключ" 1 "$FX/v4" "посторонний ключ прав расширения"

  # V20–V22 (quick 261018-jd8): новое ЛЕГИТИМНОЕ право app — user-selected.read-only
  # (импорт auth.json через NSOpenPanel) — требуем его ровно в этом виде; у appex
  # оно по-прежнему постороннее (V4 выше). Файл операции не расширяют: read-write,
  # false-значение и отсутствие права отвергаются.
  mk_fixtures "$FX/v20" "TESTTEAMID" "TESTTEAMID.group.aiusage" "" '<key>com.apple.security.files.user-selected.read-write</key><true/>'
  run_case "V20 app user-selected.read-write (запись файлов)" 1 "$FX/v20" "посторонний ключ прав"

  mk_fixtures "$FX/v21" "TESTTEAMID" "TESTTEAMID.group.aiusage" ""
  perl -0pi -e 's|(<key>com\.apple\.security\.files\.user-selected\.read-only</key>\s*)<true/>|${1}<false/>|' "$FX/v21/ent-app.xml"
  run_case "V21 app user-selected.read-only = false" 1 "$FX/v21" "user-selected.read-only не true"

  mk_fixtures "$FX/v22" "TESTTEAMID" "TESTTEAMID.group.aiusage" ""
  perl -0pi -e 's|<key>com\.apple\.security\.files\.user-selected\.read-only</key>\s*<true/>||' "$FX/v22/ent-app.xml"
  run_case "V22 app без user-selected.read-only" 1 "$FX/v22" "нет com.apple.security.files.user-selected.read-only"

  # V5 расхождение ПОДПИСАННЫХ групп app/appex (права appex ведут в другую группу той же команды)
  mk_fixtures "$FX/v5" "TESTTEAMID" "TESTTEAMID.group.aiusage" ""
  sed -i '' 's/TESTTEAMID\.group\.aiusage/TESTTEAMID.group.other/' "$FX/v5/ent-appex.xml"
  run_case "V5 расхождение подписанных групп" 1 "$FX/v5" "сверка-групп"

  # V6 расхождение GID между двумя Info.plist при согласованных подписях
  mk_fixtures "$FX/v6" "TESTTEAMID" "TESTTEAMID.group.other" ""
  run_case "V6 расхождение Info.plist GID" 1 "$FX/v6" "сверка-групп"

  # V7 СОГЛАСОВАННАЯ чужая команда: оба бандла OTHERTEAM, группа OTHERTEAM.group.aiusage, expected=TESTTEAMID
  mk_fixtures "$FX/v7" "OTHERTEAM" "OTHERTEAM.group.aiusage" ""
  run_case "V7 согласованная чужая команда (T-01-11)" 1 "$FX/v7" "team-несовпадение-с-ожидаемой"

  # V8 ad-hoc: Signature=adhoc, TeamIdentifier отсутствует
  mk_fixtures "$FX/v8" "TESTTEAMID" "TESTTEAMID.group.aiusage" ""
  printf 'Executable=/fixture\nIdentifier=com.serzhsharapa.aiusage\nSignature=adhoc\nAuthority=(unavailable)\n' > "$FX/v8/dv-app.txt"
  run_case "V8 ad-hoc подпись app" 1 "$FX/v8" "подпись-adhoc"

  # V9 пустой TeamIdentifier (not set) у appex
  mk_fixtures "$FX/v9" "TESTTEAMID" "TESTTEAMID.group.aiusage" ""
  sed -i '' 's/^TeamIdentifier=.*/TeamIdentifier=not set/' "$FX/v9/dv-appex.txt"
  run_case "V9 TeamIdentifier not set (appex)" 1 "$FX/v9" "подпись-adhoc"

  # V10 expected-team.local отсутствует
  mk_fixtures "$FX/v10" "TESTTEAMID" "TESTTEAMID.group.aiusage" ""
  rm -f "$FX/v10/expected-team.local"
  run_case "V10 конфиг ожидаемой команды отсутствует" 1 "$FX/v10" "конфиг-ожидаемой-команды"

  # V11 expected-team.local пустой
  mk_fixtures "$FX/v11" "TESTTEAMID" "TESTTEAMID.group.aiusage" ""
  : > "$FX/v11/expected-team.local"
  run_case "V11 конфиг ожидаемой команды пуст" 1 "$FX/v11" "конфиг-ожидаемой-команды"

  # V12 expected-team.local кривой (не TeamID)
  mk_fixtures "$FX/v12" "TESTTEAMID" "TESTTEAMID.group.aiusage" ""
  printf 'my-team\n' > "$FX/v12/expected-team.local"
  run_case "V12 конфиг кривой (не TeamID)" 1 "$FX/v12" "конфиг-ожидаемой-команды"

  # V13 у app нет Authority «Apple Development» (только WWDR)
  mk_fixtures "$FX/v13" "TESTTEAMID" "TESTTEAMID.group.aiusage" ""
  sed -i '' '/^Authority=Apple Development:/d' "$FX/v13/dv-app.txt"
  run_case "V13 app без Authority Apple Development" 1 "$FX/v13" "authority"

  # V14–V19 (CR-05): чужой продукт/неверная точка расширения той же команды
  mk_fixtures "$FX/v14" "TESTTEAMID" "TESTTEAMID.group.aiusage" ""
  sed -i '' 's#<string>com.serzhsharapa.aiusage</string>#<string>com.fixture.otherapp</string>#' "$FX/v14/bundle/AI Usage Widget.app/Contents/Info.plist"
  run_case "V14 чужой CFBundleIdentifier app (Info.plist)" 1 "$FX/v14" "identity-app"

  mk_fixtures "$FX/v15" "TESTTEAMID" "TESTTEAMID.group.aiusage" ""
  sed -i '' 's#<string>com.serzhsharapa.aiusage.widget</string>#<string>com.fixture.otherapp.widget</string>#' "$FX/v15/bundle/AI Usage Widget.app/Contents/PlugIns/$APPEX_NAME/Contents/Info.plist"
  run_case "V15 чужой CFBundleIdentifier appex (Info.plist)" 1 "$FX/v15" "identity-appex"

  mk_fixtures "$FX/v16" "TESTTEAMID" "TESTTEAMID.group.aiusage" ""
  sed -i '' 's/^Identifier=com.serzhsharapa.aiusage$/Identifier=com.fixture.otherapp/' "$FX/v16/dv-app.txt"
  run_case "V16 чужой signed Identifier app (подпись)" 1 "$FX/v16" "identity-подписи"

  mk_fixtures "$FX/v17" "TESTTEAMID" "TESTTEAMID.group.aiusage" ""
  sed -i '' 's/^Identifier=com.serzhsharapa.aiusage.widget$/Identifier=com.fixture.otherapp.widget/' "$FX/v17/dv-appex.txt"
  run_case "V17 чужой signed Identifier appex (подпись)" 1 "$FX/v17" "identity-подписи"

  mk_fixtures "$FX/v18" "TESTTEAMID" "TESTTEAMID.group.aiusage" ""
  sed -i '' 's#<string>com.apple.widgetkit-extension</string>#<string>com.apple.share-services</string>#' "$FX/v18/bundle/AI Usage Widget.app/Contents/PlugIns/$APPEX_NAME/Contents/Info.plist"
  run_case "V18 неверная NSExtensionPointIdentifier" 1 "$FX/v18" "identity-appex"

  mk_fixtures "$FX/v19" "TESTTEAMID" "TESTTEAMID.group.aiusage" ""
  sed -i '' '/<string>XPC!<\/string>/s#<string>XPC!</string>#<string>APPL</string>#' "$FX/v19/bundle/AI Usage Widget.app/Contents/PlugIns/$APPEX_NAME/Contents/Info.plist"
  run_case "V19 неверный CFBundlePackageType appex" 1 "$FX/v19" "identity-appex"

  # P1–P5 (WR-01): регистрация — только ТОЧНЫЙ путь установленного appex + rc 0
  mk_fixtures "$FX/p1" "TESTTEAMID" "TESTTEAMID.group.aiusage" ""
  CANON_APPEX="$FX/p1/home/Applications/AI Usage Widget.app/Contents/PlugIns/$APPEX_NAME"
  printf '     com.serzhsharapa.aiusage.widget(1.0)\n            Path = %s\n             SDK = com.apple.widgetkit-extension\n\n(1 plug-in)\n' "$CANON_APPEX" > "$FX/p1/pk-exact.out"
  run_case_installed "P1 регистрация точным путём (rc 0)" 0 "$FX/p1" "$FX/p1/pk-exact.out" 0

  mk_fixtures "$FX/p2" "TESTTEAMID" "TESTTEAMID.group.aiusage" ""
  printf '     com.serzhsharapa.aiusage.widget(1.0)\n            Path = /fixture/Downloads/Old.app/Contents/PlugIns/AiUsageWidget.appex\n             SDK = com.apple.widgetkit-extension\n\n(1 plug-in)\n' > "$FX/p2/pk-stale.out"
  run_case_installed "P2 только stale-путь того же ID" 1 "$FX/p2" "$FX/p2/pk-stale.out" 0 "регистрация-расширения"

  mk_fixtures "$FX/p3" "TESTTEAMID" "TESTTEAMID.group.aiusage" ""
  run_case_installed "P3 stale-путь + отказ инструмента (rc 1)" 1 "$FX/p3" "$FX/p2/pk-stale.out" 1 "регистрация-расширения"

  mk_fixtures "$FX/p4" "TESTTEAMID" "TESTTEAMID.group.aiusage" ""
  CANON_APPEX4="$FX/p4/home/Applications/AI Usage Widget.app/Contents/PlugIns/$APPEX_NAME"
  printf '     com.serzhsharapa.aiusage.widget(1.0)\n            Path = /fixture/Downloads/Old.app/Contents/PlugIns/AiUsageWidget.appex\n             SDK = com.apple.widgetkit-extension\n     com.serzhsharapa.aiusage.widget(1.0)\n            Path = %s\n             SDK = com.apple.widgetkit-extension\n\n(2 plug-ins)\n' "$CANON_APPEX4" > "$FX/p4/pk-two.out"
  run_case_installed "P4 точный путь + лишняя stale-запись" 0 "$FX/p4" "$FX/p4/pk-two.out" 0

  mk_fixtures "$FX/p5" "TESTTEAMID" "TESTTEAMID.group.aiusage" ""
  printf ' (no matches)\n' > "$FX/p5/pk-none.out"
  run_case_installed "P5 инструмент отвечает «no matches»" 1 "$FX/p5" "$FX/p5/pk-none.out" 0 "регистрация-расширения"

  # P6–P12 (WR-01, раунд 2): границы записей, election-состояние, порядок версий,
  # дубликаты и канонизация путей. Формат записей — как в системном verbose-ответе
  # (header с отступа, поля Path/SDK; маркеры election — man pluginkit.8).

  # P6/P7: обе перестановки двух версий одного ID — точная запись НЕ затирается
  mk_fixtures "$FX/p6" "TESTTEAMID" "TESTTEAMID.group.aiusage" ""
  CANON6="$FX/p6/home/Applications/AI Usage Widget.app/Contents/PlugIns/$APPEX_NAME"
  printf '     com.serzhsharapa.aiusage.widget(1.0)\n\t            Path = %s\n\t             SDK = com.apple.widgetkit-extension\n     com.serzhsharapa.aiusage.widget(2.0)\n\t            Path = /fixture/stale.appex\n             SDK = com.apple.widgetkit-extension\n\n(2 plug-ins)\n' "$CANON6" > "$FX/p6/pk-order-a.out"
  run_case_installed "P6 exact(1.0) первым, stale(2.0) последним" 0 "$FX/p6" "$FX/p6/pk-order-a.out" 0

  mk_fixtures "$FX/p7" "TESTTEAMID" "TESTTEAMID.group.aiusage" ""
  CANON7="$FX/p7/home/Applications/AI Usage Widget.app/Contents/PlugIns/$APPEX_NAME"
  printf '     com.serzhsharapa.aiusage.widget(2.0)\n\t            Path = /fixture/stale.appex\n             SDK = com.apple.widgetkit-extension\n     com.serzhsharapa.aiusage.widget(1.0)\n\t            Path = %s\n\t             SDK = com.apple.widgetkit-extension\n\n(2 plug-ins)\n' "$CANON7" > "$FX/p7/pk-order-b.out"
  run_case_installed "P7 stale(2.0) первым, exact(1.0) последним" 0 "$FX/p7" "$FX/p7/pk-order-b.out" 0

  # P8: exact-запись с election «-» (пользователь игнорирует) — НЕ доказательство
  mk_fixtures "$FX/p8" "TESTTEAMID" "TESTTEAMID.group.aiusage" ""
  CANON8="$FX/p8/home/Applications/AI Usage Widget.app/Contents/PlugIns/$APPEX_NAME"
  printf ' -   com.serzhsharapa.aiusage.widget(1.0)\n            Path = %s\n             SDK = com.apple.widgetkit-extension\n\n(1 plug-in)\n' "$CANON8" > "$FX/p8/pk-ignored.out"
  run_case_installed "P8 exact с election «-» (ignored)" 1 "$FX/p8" "$FX/p8/pk-ignored.out" 0 "регистрация-расширения"

  # P9: exact-запись с election «=» (superseded) — НЕ доказательство
  mk_fixtures "$FX/p9" "TESTTEAMID" "TESTTEAMID.group.aiusage" ""
  CANON9="$FX/p9/home/Applications/AI Usage Widget.app/Contents/PlugIns/$APPEX_NAME"
  printf ' =   com.serzhsharapa.aiusage.widget(1.0)\n            Path = %s\n             SDK = com.apple.widgetkit-extension\n\n(1 plug-in)\n' "$CANON9" > "$FX/p9/pk-superseded.out"
  run_case_installed "P9 exact с election «=» (superseded)" 1 "$FX/p9" "$FX/p9/pk-superseded.out" 0 "регистрация-расширения"

  # P10: exact с election «?» (unknown) — fail closed
  mk_fixtures "$FX/p10" "TESTTEAMID" "TESTTEAMID.group.aiusage" ""
  CANON10="$FX/p10/home/Applications/AI Usage Widget.app/Contents/PlugIns/$APPEX_NAME"
  printf ' ?   com.serzhsharapa.aiusage.widget(1.0)\n            Path = %s\n             SDK = com.apple.widgetkit-extension\n\n(1 plug-in)\n' "$CANON10" > "$FX/p10/pk-unknown.out"
  run_case_installed "P10 exact с election «?» (unknown)" 1 "$FX/p10" "$FX/p10/pk-unknown.out" 0 "регистрация-расширения"

  # P11: дубликаты версии — две точные записи + stale: PASS, stale наблюдается
  mk_fixtures "$FX/p11" "TESTTEAMID" "TESTTEAMID.group.aiusage" ""
  CANON11="$FX/p11/home/Applications/AI Usage Widget.app/Contents/PlugIns/$APPEX_NAME"
  printf '     com.serzhsharapa.aiusage.widget(1.0)\n            Path = %s\n             SDK = com.apple.widgetkit-extension\n     com.serzhsharapa.aiusage.widget(1.0)\n            Path = %s\n             SDK = com.apple.widgetkit-extension\n     com.serzhsharapa.aiusage.widget(2.0)\n            Path = /fixture/stale.appex\n             SDK = com.apple.widgetkit-extension\n\n(3 plug-ins)\n' "$CANON11" "$CANON11" > "$FX/p11/pk-dup.out"
  run_case_installed "P11 дубликаты версии (exact×2 + stale)" 0 "$FX/p11" "$FX/p11/pk-dup.out" 0

  # P12: канонизация пути — запись через symlink-alias на HOME совпадает с точным
  mk_fixtures "$FX/p12" "TESTTEAMID" "TESTTEAMID.group.aiusage" ""
  ln -s "$FX/p12/home" "$FX/p12/homeAlias"
  ALIAS12="$FX/p12/homeAlias/Applications/AI Usage Widget.app/Contents/PlugIns/$APPEX_NAME"
  printf '     com.serzhsharapa.aiusage.widget(1.0)\n            Path = %s\n             SDK = com.apple.widgetkit-extension\n\n(1 plug-in)\n' "$ALIAS12" > "$FX/p12/pk-alias.out"
  run_case_installed "P12 запись через symlink-alias пути (канонизация)" 0 "$FX/p12" "$FX/p12/pk-alias.out" 0

  if [ "$failed" -ne 0 ]; then
    printf 'self-test ЗАВЕРШЁН С ОШИБКАМИ: %d/%d случаев нарушено\n' "$failed" "$total" >&2
    rm -rf "$T"; TMPDIR_WORK=""; exit 1
  fi
  printf 'self-test: %d/%d случаев PASS; изоляция: фикстуры и HOME во временном каталоге, живой codesign не вызывался\n' "$total" "$total"
  rm -rf "$T"; TMPDIR_WORK=""
  return 0
}

# ---------------------------------------------------------------------------
usage() {
  cat >&2 <<EOF
Использование:
  bash scripts/verify-install.sh                 — проверить установленное приложение
  bash scripts/verify-install.sh --app-path <путь к .app> — проверить staged-копию (бандл-локально)
  bash scripts/verify-install.sh --self-test     — самопроверка на синтетических фикстурах
EOF
  exit 2
}

# ------------------------------- main --------------------------------------
case "${1:-}" in
  --self-test)
    TMPDIR_WORK="$(mktemp -d "${TMPDIR:-/tmp}/aiusage-verify.XXXXXX")"
    self_test
    ;;
  --app-path)
    [ $# -eq 2 ] || usage
    TMPDIR_WORK="$(mktemp -d "${TMPDIR:-/tmp}/aiusage-verify.XXXXXX")"
    EXPECTED_TEAM="$(load_expected_team)" || exit 1
    verify_bundle "${2%/}" "staged" "$EXPECTED_TEAM" || exit 1
    ;;
  "")
    TMPDIR_WORK="$(mktemp -d "${TMPDIR:-/tmp}/aiusage-verify.XXXXXX")"
    EXPECTED_TEAM="$(load_expected_team)" || exit 1
    verify_bundle "$HOME/Applications/$APP_BUNDLE_NAME" "installed" "$EXPECTED_TEAM" || exit 1
    ;;
  *) usage ;;
esac
