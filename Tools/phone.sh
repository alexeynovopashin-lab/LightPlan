#!/bin/bash
# Сборка на iPhone Алексея — одним скриптом, по слову Алексея в конце итерации.
# Инцидент 28.09 (итерация 24): один идентификатор на все ветки, и установка
# ветки затёрла проверяемую правку. Теперь имя и идентификатор берутся из ветки,
# а основной идентификатор скрипт даёт только из `main`.
#
#   Tools/phone.sh install [--main] [--dry-run]   собрать, поставить, запустить
#   Tools/phone.sh uninstall [--main|<slug>]      снять приложение (ветка закрыта)
#   Tools/phone.sh list                           что стоит на телефоне и из какого коммита
#   make phone ARGS="install"
#
# Ветка → приложение (Latin, коротко):
#   main      → «Light Plan», Novopashin.LightPlan          (только из main)
#   wt/26     → «LP 26»,      Novopashin.LightPlan.wt26
#   wt/24a    → «LP 24a»,     Novopashin.LightPlan.wt24a
# `--main` просит основное приложение явно; из ветки — отказ (код 2).
# Телефон должен быть «available (paired)»; нет — код 3, просим подключить и разблокировать.
# Второй рубеж — Tools/check_boundaries.sh: сборка для телефона с основным
# идентификатором не из main — ошибка фазы сборки, даже если скрипт обойти.

set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE_ID="5A94DA8F-B9E0-5DB8-BECF-14F387CFE24F"   # iPhone ALno (15 Pro Max). Не «iPhone Elena».
DEVICE_NAME="iPhone ALno"
MAIN_BID="Novopashin.LightPlan"
RECORD="${LP_PHONE_RECORD:-$HOME/.light_plan_phone.tsv}"   # bid<TAB>branch<TAB>sha<TAB>время

die() { echo "phone.sh: $1" >&2; exit "${2:-1}"; }

cmd="${1:-}"; [ $# -gt 0 ] && shift
want_main=0; dry=0; slug_arg=""
for a in "$@"; do
  case "$a" in
    --main) want_main=1 ;;
    --dry-run) dry=1 ;;
    -*) die "не знаю флага $a" ;;
    *) slug_arg="$a" ;;
  esac
done

branch="${LP_BRANCH:-$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null)}"
sha="$(git -C "$root" rev-parse --short HEAD 2>/dev/null)"
dirty=""; [ -n "$(git -C "$root" status --porcelain --untracked-files=no 2>/dev/null)" ] && dirty=" (+ не закоммиченное)"

# Ветка → "slug|имя". main → пустой slug.
branch_app() {
  local b="$1" rest s
  if [ "$b" = "main" ]; then echo "|Light Plan"; return; fi
  rest="${b#wt/}"; rest="${rest#*/}"
  [ "$b" = "HEAD" ] && die "ветка не выбрана (detached HEAD) — на телефон только из ветки или main" 2
  s="wt$(printf '%s' "$rest" | tr -cd 'A-Za-z0-9')"
  echo "$s|LP $rest"
}

need_phone() {
  if xcrun devicectl list devices 2>/dev/null | grep -E "^$DEVICE_NAME[[:space:]]" | grep -qE '[[:space:]]available \(paired\)'; then return 0; fi
  echo "phone.sh: $DEVICE_NAME не «available (paired)» — попросить Алексея подключить кабель и разблокировать экран." >&2
  exit 3
}

case "$cmd" in
  install)
    IFS='|' read -r slug name < <(branch_app "$branch")
    bid="$MAIN_BID${slug:+.$slug}"
    if [ "$want_main" = 1 ] && [ "$branch" != "main" ]; then
      die "основное приложение «Light Plan» ($MAIN_BID) ставится только из main, сейчас ветка $branch. Из ветки — без --main: получится «$name»." 2
    fi
    [ "$dry" = 1 ] && echo "dry-run: ветка $branch @ $sha$dirty → «$name», $bid" && exit 0
    need_phone
    dd="/tmp/cc-phone-${slug:-main}"
    log="/tmp/cc-phone-${slug:-main}.log"
    echo "сборка «$name» ($bid) из $branch @ $sha$dirty…"
    ( cd "$root" && xcodebuild -project LightPlan.xcodeproj -scheme LightPlan-iOS -configuration Debug \
        -destination "platform=iOS,id=$DEVICE_ID" -derivedDataPath "$dd" -allowProvisioningUpdates \
        PRODUCT_BUNDLE_IDENTIFIER="$bid" INFOPLIST_KEY_CFBundleDisplayName="$name" build ) > "$log" 2>&1
    code=$?
    grep -nE 'error:|BUILD (SUCCEEDED|FAILED)' "$log" | head -10
    [ $code -eq 0 ] || die "сборка не прошла (exit=$code), журнал $log" 4
    xcrun devicectl device install app --device "$DEVICE_ID" "$dd/Build/Products/Debug-iphoneos/LightPlan.app" \
      > "$log.install" 2>&1 || { tail -5 "$log.install"; die "установка не прошла (лимит бесплатной команды? тогда снять закрытые ветки: phone.sh list / uninstall)" 5; }
    printf '%s\t%s\t%s\t%s\n' "$bid" "$branch" "$sha$dirty" "$(date '+%Y-%m-%d %H:%M')" >> "$RECORD"
    if xcrun devicectl device process launch --device "$DEVICE_ID" "$bid" > "$log.launch" 2>&1; then
      launched="запущено"
    else
      launched="стоит, но не запустилось (телефон заблокирован?) — открыть значок вручную"
    fi
    echo "на телефоне: «$name» ($bid) из $branch @ $sha$dirty — $launched"
    ;;

  uninstall)
    if [ "$want_main" = 1 ]; then bid="$MAIN_BID"
    elif [ -n "$slug_arg" ]; then
      s="$(printf '%s' "${slug_arg#wt/}" | tr -cd 'A-Za-z0-9')"; case "$s" in wt*) ;; *) s="wt$s" ;; esac
      bid="$MAIN_BID.$s"
    else
      IFS='|' read -r slug name < <(branch_app "$branch"); bid="$MAIN_BID${slug:+.$slug}"
      [ "$branch" = "main" ] && die "из main основное приложение снимается только явно: uninstall --main" 2
    fi
    [ "$dry" = 1 ] && echo "dry-run: снять $bid" && exit 0
    need_phone
    xcrun devicectl device uninstall app --device "$DEVICE_ID" "$bid" 2>&1 | tail -3
    echo "снято: $bid"
    ;;

  list)
    need_phone
    out="/tmp/cc-phone-apps.json"
    xcrun devicectl device info apps --device "$DEVICE_ID" --json-output "$out" > /tmp/cc-phone-apps.log 2>&1 \
      || { tail -3 /tmp/cc-phone-apps.log; die "не прочитал список приложений" 4; }
    echo "на $DEVICE_NAME (коммит — по записи установок $RECORD):"
    jq -r '.result.apps[]? | select(.bundleIdentifier|startswith("Novopashin.LightPlan")) | [.bundleIdentifier,.name]|@tsv' "$out" \
    | while IFS=$'\t' read -r bid name; do
        rec="$(grep -F "$bid"$'\t' "$RECORD" 2>/dev/null | tail -1)"
        if [ -n "$rec" ]; then IFS=$'\t' read -r _ b s t <<<"$rec"; echo "  «$name» $bid — $b @ $s, $t"
        else echo "  «$name» $bid — записи об установке нет (ставилось не скриптом)"; fi
      done
    ;;

  *) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; [ -z "$cmd" ] || exit 1 ;;
esac
