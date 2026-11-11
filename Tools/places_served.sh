#!/bin/bash
# Общий список студий (30е.1) → `places_served.json` рядом с приложением.
#
#   Tools/places_served.sh <папка ресурсов приложения>   вызывает build_stamp.sh из фазы сборки
#   Tools/places_served.sh selftest                      проверка
#
# Источник — самый свежий `places_served_ГГГГ-ММ-ДД.json` в папке `ws:20_shared`
# (по умолчанию `~/Documents/workspace/20_shared`, другая — `LP_PLACES_DIR`).
# Файл ядра Event OS, формат версии 1 (`event_os:16_Place_Registry.md`). В git он
# не кладётся (`.gitignore`): решение Алексея «призрак хранить у меня на Яндекс
# сервере», на закрытый тест копия в сборке (DECISIONS 06.11). Нет файла или не
# формат 1 — копии нет, приложение работает без списка, сборка проходит.

set -u

# 0 — файл положен, 1 — списка нет. Печатает имя источника и размер, не содержимое.
put() { # папка-источник  файл-назначение
  rm -f "$2"
  local src
  src="$(ls -1 "$1"/places_served_*.json 2>/dev/null | sort | tail -n 1)"
  [ -n "$src" ] && [ -r "$src" ] || { echo "places_served: файла списка нет — приложение без общего списка"; return 1; }
  [ "$(plutil -extract format raw -o - "$src" 2>/dev/null)" = "1" ] \
    || { echo "places_served: $(basename "$src") не формат 1 — приложение без общего списка"; return 1; }
  # Права источника (600) в приложении не нужны: файл читает само приложение — 644.
  cp "$src" "$2" && chmod 644 "$2" || { rm -f "$2"; return 1; }
  echo "places_served: $(basename "$src") положен ($(wc -c < "$2" | tr -d ' ') байт)"
}

if [ "${1:-}" = selftest ]; then
  t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
  mkdir "$t/src" "$t/out"
  put "$t/src" "$t/out/p.json" > /dev/null
  [ ! -e "$t/out/p.json" ] || { echo "selftest: без источника появился файл" >&2; exit 1; }
  echo '{"format":2,"places":[]}' > "$t/src/places_served_2026-11-07.json"
  put "$t/src" "$t/out/p.json" > /dev/null
  [ ! -e "$t/out/p.json" ] || { echo "selftest: чужой формат положен" >&2; exit 1; }
  echo '{"format":1,"etag":1,"places":[]}' > "$t/src/places_served_2026-11-06.json"
  echo '{"format":1,"etag":2,"places":[]}' > "$t/src/places_served_2026-11-08.json"
  put "$t/src" "$t/out/p.json" > /dev/null
  [ "$(plutil -extract etag raw -o - "$t/out/p.json")" = "2" ] || { echo "selftest: взят не самый свежий" >&2; exit 1; }
  [ "$(stat -f %Lp "$t/out/p.json")" = "644" ] || { echo "selftest: права копии не 644" >&2; exit 1; }
  echo stale > "$t/out/q.json"; rm "$t"/src/*.json
  put "$t/src" "$t/out/q.json" > /dev/null
  [ ! -e "$t/out/q.json" ] || { echo "selftest: старая копия осталась без источника" >&2; exit 1; }
  echo "selftest: ок"; exit 0
fi

dir="${1:?папка ресурсов приложения}"
put "${LP_PLACES_DIR:-$HOME/Documents/workspace/20_shared}" "$dir/places_served.json"
exit 0
