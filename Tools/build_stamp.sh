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

# «+», если в сборку может войти то, чего нет в коммите: правка отслеживаемого или новый,
# ещё не добавленный файл исходников (ревью GPT 28в). Игнорируемое (.build, DerivedData) не в счёт.
dirty_mark() { # папка репозитория
  [ -n "$(git -C "$1" status --porcelain -- Packages App-iOS App-macOS Config Tools LightPlan.xcodeproj 2>/dev/null)" ] && printf '+'
}

case "${1:-}" in
  line) line "${2:?ветка}" "${3:?коммит}" "${4:?день}"; exit 0 ;;
  selftest)
    [ "$(line main a8ee911 2026-10-01)" = "main · a8ee911 · 01.10" ] || { echo "selftest: формат разошёлся" >&2; exit 1; }
    [ "$(line wt/28v a8ee911+ 2026-10-01)" = "wt/28v · a8ee911+ · 01.10" ] || { echo "selftest: ветка с косой чертой" >&2; exit 1; }
    t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
    git -C "$t" init -q && mkdir -p "$t/Packages" && echo a > "$t/Packages/a.swift" \
      && git -C "$t" add . && git -C "$t" -c user.name=t -c user.email=t@t commit -qm t
    [ -z "$(dirty_mark "$t")" ] || { echo "selftest: чистая папка помечена «+»" >&2; exit 1; }
    echo b > "$t/Packages/b.swift"
    [ "$(dirty_mark "$t")" = "+" ] || { echo "selftest: новый неотслеживаемый файл не помечен «+»" >&2; exit 1; }
    rm "$t/Packages/b.swift"; echo c >> "$t/Packages/a.swift"
    [ "$(dirty_mark "$t")" = "+" ] || { echo "selftest: правка отслеживаемого файла не помечена «+»" >&2; exit 1; }
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
sha="$sha$(dirty_mark "$root")"
day="$(date '+%Y-%m-%d')"
for kv in "LPBuildBranch=$branch" "LPBuildSha=$sha" "LPBuildDate=$day"; do
  k="${kv%%=*}"; v="${kv#*=}"
  "$pb" -c "Set :$k $v" "$plist" 2>/dev/null || "$pb" -c "Add :$k string $v" "$plist" || exit 1
done
echo "stamp_build: $(line "$branch" "$sha" "$day")"
