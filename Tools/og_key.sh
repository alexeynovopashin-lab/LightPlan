#!/bin/bash
# Ключ читалки Pinterest (28м) → `pinterest_reader.plist` рядом с приложением.
#
#   Tools/og_key.sh <папка ресурсов приложения>   вызывает build_stamp.sh из фазы сборки
#   Tools/og_key.sh selftest                      проверка
#
# Ключ берётся из файла ВНЕ репозитория (репозиторий публичный): по умолчанию
# `~/.config/lightplan/og_key`, другой — `LP_OG_KEY_FILE`. Значение
# нигде не печатается и не пишется в git. Нет файла или он пуст — plist не
# создаётся, Pinterest в приложении выключен («Pinterest не подключён в этой сборке»), без падений
# (`PinterestConfig.load` вернёт nil). Адрес сервера не секрет, он в коде
# (`PinterestConfig.defaultURL`).

set -u

# 0 — plist записан, 1 — ключа нет. Печатает только число знаков, не значение.
write_key() { # файл-ключ  файл-plist
  rm -f "$2"
  [ -r "$1" ] || { echo "og_key: файла ключа нет — Pinterest в приложении выключен"; return 1; }
  local key; key="$(tr -d '[:space:]' < "$1")"
  [ -n "$key" ] || { echo "og_key: файл ключа пуст — Pinterest в приложении выключен"; return 1; }
  plutil -create xml1 "$2" && plutil -insert LPPinterestKey -string "$key" "$2" || { rm -f "$2"; return 1; }
  echo "og_key: ключ положен (${#key} знаков)"
}

if [ "${1:-}" = selftest ]; then
  t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
  out="$(write_key "$t/нет" "$t/a.plist")"
  [ ! -e "$t/a.plist" ] || { echo "selftest: без файла ключа появился plist" >&2; exit 1; }
  : > "$t/empty"; write_key "$t/empty" "$t/b.plist" > /dev/null
  [ ! -e "$t/b.plist" ] || { echo "selftest: из пустого файла появился plist" >&2; exit 1; }
  printf 'SELFTEST-VALUE-123\n' > "$t/key"
  out="$(write_key "$t/key" "$t/c.plist")"
  [ "$(plutil -extract LPPinterestKey raw "$t/c.plist")" = "SELFTEST-VALUE-123" ] || { echo "selftest: ключ не лёг в plist" >&2; exit 1; }
  case "$out" in *SELFTEST-VALUE-123*) echo "selftest: значение ключа попало в вывод" >&2; exit 1 ;; esac
  echo "selftest: ок"; exit 0
fi

dir="${1:?папка ресурсов приложения}"
write_key "${LP_OG_KEY_FILE:-$HOME/.config/lightplan/og_key}" "$dir/pinterest_reader.plist"
exit 0
