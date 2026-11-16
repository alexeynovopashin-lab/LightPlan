#!/bin/bash
# ClientID Яндекс ID (31.1) → `yandex_disk.plist` рядом с приложением.
#
#   Tools/yandex_key.sh <папка ресурсов приложения>   вызывает build_stamp.sh из фазы сборки
#   Tools/yandex_key.sh selftest                      проверка
#
# Ключ берётся из файла ВНЕ репозитория (репозиторий публичный): по умолчанию
# `~/.config/lightplan/yandex_client_id`, другой — `LP_YANDEX_ID_FILE`. Значение
# нигде не печатается и не пишется в git. Нет файла или он пуст — plist не
# создаётся, Яндекс в «Облаке» честно «не настроен в этой сборке», без падений
# (`YandexConfig.load` вернёт nil). ClientID и сам не секрет (он в открытом вебе, `CLOUD_IDS.yandex`),
# но настройки сборки живут вне git. Адрес возврата — в коде (`YandexConfig.redirect`).

set -u

# 0 — plist записан, 1 — ключа нет. Печатает только число знаков, не значение.
write_key() { # файл-ключ  файл-plist
  rm -f "$2"
  [ -r "$1" ] || { echo "yandex_key: файла ключа нет — Яндекс в приложении не настроен"; return 1; }
  local key; key="$(tr -d '[:space:]' < "$1")"
  [ -n "$key" ] || { echo "yandex_key: файл ключа пуст — Яндекс в приложении не настроен"; return 1; }
  plutil -create xml1 "$2" && plutil -insert LPYandexClientID -string "$key" "$2" || { rm -f "$2"; return 1; }
  echo "yandex_key: ClientID положен (${#key} знаков)"
}

if [ "${1:-}" = selftest ]; then
  t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
  out="$(write_key "$t/нет" "$t/a.plist")"
  [ ! -e "$t/a.plist" ] || { echo "selftest: без файла ключа появился plist" >&2; exit 1; }
  : > "$t/empty"; write_key "$t/empty" "$t/b.plist" > /dev/null
  [ ! -e "$t/b.plist" ] || { echo "selftest: из пустого файла появился plist" >&2; exit 1; }
  printf 'SELFTEST-VALUE-123\n' > "$t/key"
  out="$(write_key "$t/key" "$t/c.plist")"
  [ "$(plutil -extract LPYandexClientID raw "$t/c.plist")" = "SELFTEST-VALUE-123" ] || { echo "selftest: ключ не лёг в plist" >&2; exit 1; }
  case "$out" in *SELFTEST-VALUE-123*) echo "selftest: значение ключа попало в вывод" >&2; exit 1 ;; esac
  echo "selftest: ок"; exit 0
fi

dir="${1:?папка ресурсов приложения}"
write_key "${LP_YANDEX_ID_FILE:-$HOME/.config/lightplan/yandex_client_id}" "$dir/yandex_disk.plist"
exit 0
