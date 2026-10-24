#!/bin/bash
# Значок тестовых сборок (24.10): у основного «Light Plan» (Novopashin.LightPlan) — чистый AppIcon,
# у любой другой сборки iOS («LP …» в слотах, старые wt…) — AppIconAlpha с биркой «α».
# Выбор — в Config/iOS.xcconfig; этот скрипт ловит, если выбор обойдут или сломают.
#
#   Tools/check_app_icon.sh                 фаза сборки (через check_boundaries.sh): настройки сборки
#   Tools/check_app_icon.sh <LightPlan.app> собранное приложение: идентификатор ↔ значок (phone.sh перед установкой)
#   Tools/check_app_icon.sh --selftest      xcconfig даёт слоту α, основному — чистый; проверка ловит подмену
#
# Mac не проверяется: у него свой набор значков и один идентификатор.

set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
MAIN_BID="Novopashin.LightPlan"

want_for() { [ "$1" = "$MAIN_BID" ] && echo AppIcon || echo AppIconAlpha; }

verdict() {   # идентификатор, значок, где
  local want; want="$(want_for "$1")"
  if [ "$2" != "$want" ]; then
    echo "$3: error: у сборки $1 значок «${2:-нет}», нужен «$want» — чистый значок только у основного «Light Plan», остальные с «α» (Config/iOS.xcconfig, Tools/app_icon_alpha.py)."
    return 1
  fi
  echo "значок: $1 → $2 — ок"
}

case "${1:-}" in
  "")
    case "${PLATFORM_NAME:-}" in iphoneos|iphonesimulator) ;; *) exit 0 ;; esac
    verdict "${PRODUCT_BUNDLE_IDENTIFIER:-}" "${ASSETCATALOG_COMPILER_APPICON_NAME:-}" "$root/Config/iOS.xcconfig:1"
    ;;
  --selftest)
    fail=0
    expect() {   # ждём код, идентификатор, значок
      local got
      PLATFORM_NAME=iphoneos PRODUCT_BUNDLE_IDENTIFIER="$2" ASSETCATALOG_COMPILER_APPICON_NAME="$3" "$0" > /dev/null; got=$?
      [ "$got" = "$1" ] || { echo "selftest: $2 + $3 → код $got, ждали $1"; fail=1; }
    }
    expect 0 "$MAIN_BID" AppIcon
    expect 0 "$MAIN_BID.slotA" AppIconAlpha
    expect 1 "$MAIN_BID.slotA" AppIcon
    expect 1 "$MAIN_BID" AppIconAlpha
    for bid in "$MAIN_BID" "$MAIN_BID.slotA" "$MAIN_BID.slotD" "$MAIN_BID.wt26"; do
      # Только таргет приложения: у схемы ещё и виджет (30б.1) со своим пустым значком. Адрес — как у phone.sh, через LP_APP_ID.
      got="$(cd "$root" && xcodebuild -project LightPlan.xcodeproj -target LightPlan-iOS -configuration Debug -showBuildSettings \
        LP_APP_ID="$bid" 2>/dev/null | sed -n 's/^ *ASSETCATALOG_COMPILER_APPICON_NAME = //p')"
      verdict "$bid" "$got" "Config/iOS.xcconfig" || fail=1
    done
    [ "$fail" = 0 ] && echo "selftest значка: ок"
    exit $fail
    ;;
  *)
    plist="$1/Info.plist"
    [ -f "$plist" ] || { echo "$1: нет Info.plist"; exit 1; }
    bid="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null)"
    icon="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName' "$plist" 2>/dev/null)"
    verdict "$bid" "$icon" "$1" || exit 1
    # Каталог положил рядом картинку для старых систем — значит, набор не пустой и собран.
    ls "$1/$icon"60x60@*.png > /dev/null 2>&1 || { echo "$1: error: нет $icon""60x60@*.png — набор значков не скомпилирован"; exit 1; }
    ;;
esac
