#!/bin/bash
# Номер сборки (шаг 28в): ветка · коммит · день. Один формат на три места —
# строка внизу «Настроек», фаза сборки и `make phone ARGS="list"`.
#
#   Tools/build_stamp.sh                    фаза сборки: вписать LPBuildBranch/Sha/Date в Info.plist
#                                           собранного приложения (git — из папки проекта)
#   Tools/build_stamp.sh line <ветка> <коммит> <ГГГГ-ММ-ДД>   строка «main · a8ee911 · 01.10»
#   Tools/build_stamp.sh selftest           проверка формата
#
# Не из git (архив, чужая копия) — ключи не пишутся, приложение скажет
# «Сборка · неизвестна». Не закоммиченное — к коммиту дописывается «+».
# LP_BRANCH — та же подмена ветки, что у phone.sh.

set -u
root="$(cd "$(dirname "$0")/.." && pwd)"

line() { # ветка коммит ГГГГ-ММ-ДД
  local d="$3"
  case "$d" in ????-??-??) d="${d:8:2}.${d:5:2}" ;; esac
  printf '%s · %s · %s\n' "$1" "$2" "$d"
}

case "${1:-}" in
  line) line "${2:?ветка}" "${3:?коммит}" "${4:?день}"; exit 0 ;;
  selftest)
    [ "$(line main a8ee911 2026-10-01)" = "main · a8ee911 · 01.10" ] || { echo "selftest: формат разошёлся" >&2; exit 1; }
    [ "$(line wt/28v a8ee911+ 2026-10-01)" = "wt/28v · a8ee911+ · 01.10" ] || { echo "selftest: ветка с косой чертой" >&2; exit 1; }
    echo "selftest: ок"; exit 0 ;;
esac

plist="${TARGET_BUILD_DIR:-}/${INFOPLIST_PATH:-}"
[ -n "${INFOPLIST_PATH:-}" ] && [ -f "$plist" ] || { echo "stamp_build: нет Info.plist собранного приложения ($plist)" >&2; exit 1; }
pb=/usr/libexec/PlistBuddy

sha="$(git -C "$root" rev-parse --short HEAD 2>/dev/null)"
branch="${LP_BRANCH:-$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null)}"
if [ -z "$sha" ] || [ -z "$branch" ]; then
  for k in LPBuildBranch LPBuildSha LPBuildDate; do "$pb" -c "Delete :$k" "$plist" 2>/dev/null; done
  echo "stamp_build: не git — сборка будет «неизвестна»"; exit 0
fi
[ -n "$(git -C "$root" status --porcelain --untracked-files=no 2>/dev/null)" ] && sha="$sha+"
day="$(date '+%Y-%m-%d')"
for kv in "LPBuildBranch=$branch" "LPBuildSha=$sha" "LPBuildDate=$day"; do
  k="${kv%%=*}"; v="${kv#*=}"
  "$pb" -c "Set :$k $v" "$plist" 2>/dev/null || "$pb" -c "Add :$k string $v" "$plist" || exit 1
done
echo "stamp_build: $(line "$branch" "$sha" "$day")"
