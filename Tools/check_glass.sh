#!/bin/bash
# Стекло без подделки (план миграции § 5.4, итерация 20д).
#
# Там, где у веба имитация стекла (`backdrop-filter`), натив ставит встроенное
# стекло `.glassEffect`: тон веба поверх него, блик и тень у стекла свои.
# Подделка — системный материал под тоном (`.ultraThinMaterial` и родня) и
# нарисованный блик `glassShine`. Блик пускается только в `Timebar/`: там он
# часть рецепта ручки и окна барабана (решения 19б), и оттуда же его берут
# булавки и центр компаса «Карты» (`KnobGlass`).
#
# Вызывается из Tools/check_boundaries.sh — фазы сборки обоих приложений:
# подделка — ошибка сборки. Вручную: Tools/check_glass.sh или make glass.

set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/Packages/LightPlanUI/Sources"

errors=""
files=0
while IFS= read -r file; do
  files=$((files + 1))
  # Комментарии не в счёт: в них подделку называют по имени.
  while IFS= read -r hit; do
    line="${hit%%:*}"
    code="${hit#*:}"
    code="${code%%//*}"
    if printf '%s\n' "$code" | grep -qE '(ultraThin|thin|regular|thick|ultraThick|bar)Material\b|Material\.'; then
      errors="$errors$file:$line: error: системный материал вместо встроенного стекла — .glassEffect с тоном веба (план § 5.4)\n"
    fi
    case "$file" in
      */Timebar/*) ;;
      *)
        # Объявление цвета в палитре — не рисунок.
        if printf '%s\n' "$code" | grep -qE '\bglassShine\b' && ! printf '%s\n' "$code" | grep -qE 'var glassShine\b'; then
          errors="$errors$file:$line: error: нарисованный блик вне Timebar/ — у встроенного стекла блик свой; ручке подобное — KnobGlass (план § 5.4)\n"
        fi ;;
    esac
  done < <(grep -nE 'Material|glassShine' "$file")
done < <(find "$src" -name '*.swift' | sort)

if [ -n "$errors" ]; then
  printf '%b' "$errors"
  exit 1
fi
echo "стекло без подделки: ок ($files файлов)"
