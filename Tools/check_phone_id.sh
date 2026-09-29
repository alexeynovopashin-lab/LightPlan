#!/bin/bash
# Защита основного приложения на телефоне Алексея (итерация 26т, инцидент 28.09).
#
# Сборка для телефона (PLATFORM_NAME=iphoneos) с основным идентификатором
# `Novopashin.LightPlan` допустима только из ветки `main`: любая другая ветка
# затёрла бы приложение, которое Алексей держит как основное. Ветка ставит своё
# приложение — `Tools/phone.sh install`. Симулятор и Mac не проверяются.
# Стоит в фазе сборки через Tools/check_boundaries.sh (pbxproj не тронут), так что
# ручной xcodebuild в обход phone.sh тоже упирается сюда. Вручную:
#   PLATFORM_NAME=iphoneos PRODUCT_BUNDLE_IDENTIFIER=Novopashin.LightPlan Tools/check_phone_id.sh
# LP_BRANCH подменяет ветку (для проверки скрипта).

set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
MAIN_BID="Novopashin.LightPlan"

[ "${PLATFORM_NAME:-}" = "iphoneos" ] || exit 0
[ "${PRODUCT_BUNDLE_IDENTIFIER:-}" = "$MAIN_BID" ] || exit 0

branch="${LP_BRANCH:-$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null)}"
[ "$branch" = "main" ] && { echo "защита телефона: основное приложение собирается из main — ок"; exit 0; }

echo "$root/Config/Shared.xcconfig:1: error: сборка для телефона с основным идентификатором $MAIN_BID из ветки «${branch:-?}» затёрла бы «Light Plan» на телефоне. Ставьте ветку своим приложением: Tools/phone.sh install (make phone ARGS=install); основное — только из main."
exit 1
