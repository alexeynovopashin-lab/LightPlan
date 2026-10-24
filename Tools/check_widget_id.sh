#!/bin/bash
# Адреса виджета (30б.1, docs/30b_widget_cut.md): одна переменная LP_APP_ID (Config/Shared.xcconfig) даёт приложению
# свой адрес, расширению LightPlanWidgetExtension — <адрес>.Widget, обоим — общую папку group.<адрес>. phone.sh
# задаёт только её: PRODUCT_BUNDLE_IDENTIFIER в командной строке лёг бы на оба таргета, и виджет получил бы адрес
# приложения — установка не прошла бы.
#
#   Tools/check_widget_id.sh --ids <адрес>     что даст сборка с LP_APP_ID=<адрес>: приложение, виджет, папка
#   Tools/check_widget_id.sh <LightPlan.app>   собранное приложение: виджет внутри, его адрес и папка у обоих
#   Tools/check_widget_id.sh --selftest        основной и четыре слота по настройкам сборки; проверка ловит подмену

set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
MAIN_BID="Novopashin.LightPlan"
APPEX="LightPlanWidgetExtension.appex"

setting() {   # таргет, адрес, имя настройки
  (cd "$root" && xcodebuild -project LightPlan.xcodeproj -target "$1" -configuration Debug -showBuildSettings \
    LP_APP_ID="$2" 2>/dev/null) | sed -n "s/^ *$3 = //p" | head -1
}

# Папка из файла прав таргета: $(LP_APP_ID) подставляет подпись — здесь то же самое руками.
group_of() {   # таргет, адрес
  local f; f="$(setting "$1" "$2" CODE_SIGN_ENTITLEMENTS)"
  [ -n "$f" ] && [ -f "$root/$f" ] || { echo "нет-файла-прав"; return; }
  /usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' "$root/$f" 2>/dev/null | sed "s/\$(LP_APP_ID)/$2/"
}

verdict() {   # ждём адрес; приложение, виджет, папка приложения, папка виджета; где
  local bad=0
  [ "$2" = "$1" ] || { echo "$6: error: приложение $2, ждали $1"; bad=1; }
  [ "$3" = "$1.Widget" ] || { echo "$6: error: виджет ${3:-нет}, ждали $1.Widget"; bad=1; }
  [ "$4" = "group.$1" ] || { echo "$6: error: папка приложения ${4:-нет}, ждали group.$1"; bad=1; }
  [ "$5" = "group.$1" ] || { echo "$6: error: папка виджета ${5:-нет}, ждали group.$1"; bad=1; }
  [ $bad = 0 ] && echo "адреса: приложение $2, виджет $3, папка $4 — ок"
  return $bad
}

ids() {
  verdict "$1" "$(setting LightPlan-iOS "$1" PRODUCT_BUNDLE_IDENTIFIER)" "$(setting LightPlanWidgetExtension "$1" PRODUCT_BUNDLE_IDENTIFIER)" \
    "$(group_of LightPlan-iOS "$1")" "$(group_of LightPlanWidgetExtension "$1")" "Config/Widget.xcconfig"
}

# Права из подписи; у сборки для симулятора их кладут в раздел __entitlements исполняемого файла, его читаем запасным путём
# (otool -X печатает его словами по 4 байта в обратном порядке).
signed_group() {   # путь к .app или .appex
  local x
  x="$(codesign -d --entitlements :- "$1" 2>/dev/null)"
  # Подпись симулятора пустая (`[Dict]` без ключей) — тогда раздел.
  printf '%s' "$x" | grep -q application-groups || x="$(otool -X -s __TEXT __entitlements "$1/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$1/Info.plist")" 2>/dev/null \
    | awk '{for(i=2;i<=NF;i++){w=$i; for(j=length(w)-1;j>0;j-=2) printf "%s", substr(w,j,2)}}' | xxd -r -p 2>/dev/null)"
  # plutil не берёт ключ с точками внутри — первая строка массива после ключа.
  printf '%s' "$x" | grep -A3 '<key>com.apple.security.application-groups</key>' | sed -n 's/.*<string>\(.*\)<\/string>.*/\1/p' | head -1
}

case "${1:-}" in
  --ids)
    [ -n "${2:-}" ] || { echo "нужен адрес: --ids Novopashin.LightPlan.slotA"; exit 2; }
    ids "$2"
    ;;
  --selftest)
    fail=0
    for bid in "$MAIN_BID" "$MAIN_BID.slotA" "$MAIN_BID.slotB" "$MAIN_BID.slotC" "$MAIN_BID.slotD"; do
      ids "$bid" || fail=1
    done
    # Проверка ловит подмену: виджет с адресом приложения, папка основного у слота.
    verdict "$MAIN_BID.slotA" "$MAIN_BID.slotA" "$MAIN_BID.slotA" "group.$MAIN_BID.slotA" "group.$MAIN_BID.slotA" self > /dev/null \
      && { echo "selftest: виджет с адресом приложения не пойман"; fail=1; }
    verdict "$MAIN_BID.slotA" "$MAIN_BID.slotA" "$MAIN_BID.slotA.Widget" "group.$MAIN_BID" "group.$MAIN_BID.slotA" self > /dev/null \
      && { echo "selftest: чужая папка не поймана"; fail=1; }
    [ "$fail" = 0 ] && echo "selftest адресов виджета: ок"
    exit $fail
    ;;
  ""|-*)
    sed -n '2,10p' "$0"; exit 2
    ;;
  *)
    app="$1"; ext="$app/PlugIns/$APPEX"
    [ -f "$app/Info.plist" ] || { echo "$app: нет Info.plist"; exit 1; }
    [ -f "$ext/Info.plist" ] || { echo "$app: error: внутри нет $APPEX — виджет не встроен"; exit 1; }
    bid="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")"
    verdict "$bid" "$bid" "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$ext/Info.plist")" \
      "$(signed_group "$app")" "$(signed_group "$ext")" "$app"
    ;;
esac
