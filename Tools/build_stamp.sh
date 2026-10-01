#!/bin/bash
# Номер сборки (шаг 28в): ветка · коммит · день. Один формат на три места —
# строка внизу «Настроек», фаза сборки и `make phone ARGS="list"`.
#
#   Tools/build_stamp.sh                    фаза сборки: положить в приложение build_stamp.plist
#                                           с LPBuildBranch/Sha/Date (git — из папки проекта)
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

# Свой файл в приложении, а не правка Info.plist: системный шаг Info.plist идёт ПОСЛЕ этой фазы и
# при инкрементальной сборке пересобирает файл заново, стирая вписанное (замер 28в: второй
# `make phone` из той же папки отдал приложение без ключей).
dir="${TARGET_BUILD_DIR:-}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}"
[ -n "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ] && [ -d "$dir" ] || { echo "stamp_build: нет папки ресурсов приложения ($dir)" >&2; exit 1; }
out="$dir/build_stamp.plist"
pb=/usr/libexec/PlistBuddy
rm -f "$out"

sha="$(git -C "$root" rev-parse --short HEAD 2>/dev/null)"
branch="${LP_BRANCH:-$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null)}"
if [ -z "$sha" ] || [ -z "$branch" ]; then
  echo "stamp_build: не git — сборка будет «неизвестна»"; exit 0
fi
sha="$sha$(dirty_mark "$root")"
day="$(date '+%Y-%m-%d')"
for kv in "LPBuildBranch=$branch" "LPBuildSha=$sha" "LPBuildDate=$day"; do
  "$pb" -c "Add :${kv%%=*} string ${kv#*=}" "$out" > /dev/null || exit 1
done
echo "stamp_build: $(line "$branch" "$sha" "$day")"
