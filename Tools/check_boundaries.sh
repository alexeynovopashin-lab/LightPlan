#!/bin/bash
# Границы слоёв (light_plan:Light_Plan/docs/17_NATIVE_ARCHITECTURE.md § 1).
#
# SwiftPM не запрещает пакету `import SwiftUI`: замер 19.09.2026 — LightPlanCore
# собирается с таким импортом. Запрещает он только модули чужих пакетов, которых
# нет в зависимостях. Поэтому границу по системным фреймворкам держит этот скрипт.
# Он стоит фазой сборки в обоих приложениях: нарушение — ошибка сборки.
# Вручную: Tools/check_boundaries.sh
#
# Правила меняются здесь, в двух функциях ниже.

set -u
root="$(cd "$(dirname "$0")/.." && pwd)"

# Что пакету можно импортировать. allow — только перечисленное, deny — всё, кроме
# перечисленного, any — без ограничений. Модули своих слоёв — в layer_deps.
import_rule() {
  case "$1" in
    LightPlanCore)     echo "allow Foundation" ;;
    LightPlanDomain)   echo "allow Foundation" ;;
    LightPlanTimeline) echo "allow Foundation" ;;
    LightPlanData)     echo "deny SwiftUI UIKit AppKit WebKit PhotosUI Charts" ;;
    LightPlanUI)       echo "any" ;;
    *)                 echo "unknown" ;;
  esac
}

# От каких пакетов слоя зависит пакет: Core ← Domain ← Data, Core ← Timeline, UI — от всех.
layer_deps() {
  case "$1" in
    LightPlanCore)     echo "" ;;
    LightPlanDomain)   echo "LightPlanCore" ;;
    LightPlanTimeline) echo "LightPlanCore" ;;
    LightPlanData)     echo "LightPlanCore LightPlanDomain" ;;
    LightPlanUI)       echo "LightPlanCore LightPlanDomain LightPlanTimeline LightPlanData" ;;
  esac
}

contains() { # слово в списке через пробел
  case " $2 " in *" $1 "*) return 0 ;; esac
  return 1
}

# Модули, которые импортирует файл: "строка модуль". Ловит `import X`, `@_exported import X`,
# `import struct X.Y`, `#if canImport(X)`: в чистом слое условный импорт тоже запах.
modules_in() {
  grep -nE 'import[[:space:]]+[A-Za-z_]|canImport\(' "$1" | while IFS= read -r hit; do
    line="${hit%%:*}"
    text="${hit#*:}"
    mod="$(printf '%s\n' "$text" | sed -nE '
      s/^[[:space:]]*((@[A-Za-z_]+(\([^)]*\))?|public|package|internal|fileprivate|private)[[:space:]]+)*import[[:space:]]+((typealias|struct|class|enum|protocol|let|var|func)[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*).*/\6/p
      s/.*canImport\(([A-Za-z_][A-Za-z0-9_]*)\).*/\1/p
    ' | head -1)"
    [ -n "$mod" ] && echo "$line $mod"
  done
}

errors=""
files=0
packages=0

for dir in "$root"/Packages/*/; do
  dir="${dir%/}"
  pkg="$(basename "$dir")"
  packages=$((packages + 1))
  rule="$(import_rule "$pkg")"
  kind="${rule%% *}"
  list="${rule#* }"
  layers="$(layer_deps "$pkg")"

  if [ "$kind" = "unknown" ]; then
    errors="$errors$dir/Package.swift:1: error: для пакета $pkg нет правила границ, добавьте его в Tools/check_boundaries.sh\n"
    continue
  fi

  # Манифест: пакет может зависеть только от своих слоёв.
  for dep in $(grep -oE '\.package\(path: "\.\./[A-Za-z0-9_]+"' "$dir/Package.swift" | sed -E 's/.*\.\.\/([A-Za-z0-9_]+)"/\1/'); do
    if ! contains "$dep" "$layers"; then
      errors="$errors$dir/Package.swift:1: error: $pkg не может зависеть от $dep (слои: docs/17 § 1)\n"
    fi
  done

  # Исходники: импорты.
  while IFS= read -r file; do
    files=$((files + 1))
    while read -r line mod; do
      [ -z "${mod:-}" ] && continue
      ok=1
      case "$kind" in
        allow) contains "$mod" "$list $layers" || ok=0 ;;
        deny)  contains "$mod" "$list" && ok=0 ;;
      esac
      # Модуль соседнего слоя, которого нет в зависимостях, — тоже нарушение.
      case "$mod" in
        LightPlan*) contains "$mod" "$layers" || ok=0 ;;
      esac
      [ "$pkg" = "LightPlanUI" ] && [ "$mod" = "LightPlanUI" ] && ok=1
      # Холст карты (docs/17 § 10): поставщики живут только в LightPlanMapCanvas,
      # а сам он не знает ни одного слоя продукта — говорит координатами и углом.
      if [ "$pkg" = "LightPlanUI" ]; then
        case "$file" in
          */Sources/LightPlanMapCanvas/*)
            case "$mod" in LightPlan*) [ "$mod" = "LightPlanMapCanvas" ] || ok=0 ;; esac ;;
          *)
            [ "$mod" = "LightPlanMapCanvas" ] && ok=1
            case "$mod" in MapLibre|MapKit) ok=0 ;; esac ;;
        esac
      fi
      [ "$mod" = "$pkg" ] && ok=1
      if [ "$ok" = 0 ]; then
        errors="$errors$file:$line: error: $pkg не должен импортировать $mod (docs/17 § 1)\n"
      fi
    done < <(modules_in "$file")
  done < <(find "$dir/Sources" -name '*.swift' 2>/dev/null | sort)
done

if [ -n "$errors" ]; then
  printf '%b' "$errors"
  exit 1
fi
echo "границы слоёв: ок ($packages пакетов, $files файлов)"

# Стекло без подделки (20д) — та же фаза сборки, чтобы не заводить вторую.
exec "$root/Tools/check_glass.sh"
