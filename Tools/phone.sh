#!/bin/bash
# Сборка на iPhone Алексея — одним скриптом, по слову Алексея в конце итерации.
# Инцидент 28.09 (итерация 24): один идентификатор на все ветки, и установка
# ветки затёрла проверяемую правку. Теперь имя и идентификатор берутся из ветки,
# а основной идентификатор скрипт даёт только из `main`.
#
#   Tools/phone.sh install [--main] [--dry-run]   собрать, поставить, запустить
#   Tools/phone.sh uninstall [--main|slotA|<ветка>|<старый слаг>]   снять приложение (ветка закрыта)
#   Tools/phone.sh list                           слот, ветка, sha, что стоит на телефоне; свободные слоты
#   make phone ARGS="install"
#
# Ветка → приложение. Бесплатная подпись Apple даёт 10 новых App ID за 7 дней, а идентификатор
# «из имени ветки» тратил по одному на каждый шаг (12.10 лимит кончился). Поэтому пул из
# четырёх постоянных идентификаторов — слоты Novopashin.LightPlan.slotA … slotD:
#   main      → «Light Plan», Novopashin.LightPlan          (только из main, слот не занимает)
#   wt/29-3g  → «LP 29-3g»,   один из слотов; имя — из записи «слот → ветка → sha → время»
# Слот выбирается так: тот же, что у этой ветки → свободный → самый старый слот ветки,
# уже слитой в main (его приложение заменится) → иначе стоп, называем, что снять.
# Запись — `~/.light_plan_phone.tsv` (идентификатор, ветка, sha, время). Старые идентификаторы
# `Novopashin.LightPlan.wt…` в пул не входят, но `uninstall wt26` и `list` с ними работают.
# `--main` просит основное приложение явно; из ветки — отказ (код 2).
# `list` печатает у каждого приложения ту же запись, что строка «Сборка» в его «Настройках».
# Телефон должен быть «available (paired)»; нет — код 3, просим подключить и разблокировать.
# Второй рубеж — Tools/check_boundaries.sh: сборка для телефона с основным
# идентификатором не из main — ошибка фазы сборки, даже если скрипт обойти.

set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE_ID="5A94DA8F-B9E0-5DB8-BECF-14F387CFE24F"   # iPhone ALno (15 Pro Max). Не «iPhone Elena».
DEVICE_NAME="iPhone ALno"
MAIN_BID="Novopashin.LightPlan"
RECORD="${LP_PHONE_RECORD:-$HOME/.light_plan_phone.tsv}"   # bid<TAB>branch<TAB>sha<TAB>время

SLOTS=(slotA slotB slotC slotD)

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
  [ "$b" = "HEAD" ] && die "ветка не выбрана (detached HEAD) — на телефон только из ветки или main" 2
  case "$b" in
    wt/*) rest="${b#wt/}"; s="wt$(printf '%s' "$rest" | tr -cd 'A-Za-z0-9')" ;;
    *)    rest="$b";       s="br$(printf '%s' "$b" | tr -cd 'A-Za-z0-9')" ;;   # release/26 ≠ wt/26
  esac
  echo "$s|LP $rest"
}

# Последняя запись идентификатора. Вторым аргументом `all` — вместе с бронью (5-е поле `reserved`).
rec_last() {
  awk -F'\t' -v b="$1" -v all="${2:-}" '$1==b && (all=="all" || $5!="reserved")' "$RECORD" 2>/dev/null | tail -1
}

# Ветка слита в main (локальный или origin/main)? sha — запасной след, если ветку уже удалили.
branch_closed() {
  local b="$1" s="${2%% *}" ref="" m
  s="${s%+}"
  for r in "refs/heads/$b" "refs/remotes/origin/$b"; do
    git -C "$root" rev-parse -q --verify "$r^{commit}" >/dev/null 2>&1 && { ref="$r"; break; }
  done
  if [ -z "$ref" ] && [ -n "$s" ] && git -C "$root" rev-parse -q --verify "$s^{commit}" >/dev/null 2>&1; then ref="$s"; fi
  [ -n "$ref" ] || return 1
  for m in refs/heads/main refs/remotes/origin/main; do
    git -C "$root" rev-parse -q --verify "$m^{commit}" >/dev/null 2>&1 \
      && git -C "$root" merge-base --is-ancestor "$ref" "$m" 2>/dev/null && return 0
  done
  return 1
}

# Слот для ветки → в stdout «slotX<TAB>почему». Нет слота — отчёт в stderr, код 2.
pick_slot() {
  local branch="$1" s bid rec b sh t oldest="" oldest_t="" free=""
  for s in "${SLOTS[@]}"; do
    bid="$MAIN_BID.$s"; rec="$(rec_last "$bid" all)"
    b="$(cut -f2 <<<"$rec")"
    [ -n "$rec" ] && [ "$b" = "$branch" ] && { printf '%s\tтот же слот, что у этой ветки\n' "$s"; return 0; }
  done
  for s in "${SLOTS[@]}"; do
    bid="$MAIN_BID.$s"; rec="$(rec_last "$bid" all)"; b="$(cut -f2 <<<"$rec")"
    if [ -z "$rec" ] || [ "$b" = "-" ]; then free="$s"; break; fi
  done
  [ -n "$free" ] && { printf '%s\tсвободный слот\n' "$free"; return 0; }
  for s in "${SLOTS[@]}"; do
    bid="$MAIN_BID.$s"; rec="$(rec_last "$bid" all)"
    b="$(cut -f2 <<<"$rec")"; sh="$(cut -f3 <<<"$rec")"; t="$(cut -f4 <<<"$rec")"
    if branch_closed "$b" "$sh"; then
      if [ -z "$oldest" ] || [[ "$t" < "$oldest_t" ]]; then oldest="$s"; oldest_t="$t"; fi
    fi
  done
  [ -n "$oldest" ] && { printf '%s\tсамый старый слот закрытой ветки (%s, слита в main)\n' "$oldest" "$(cut -f2 <<<"$(rec_last "$MAIN_BID.$oldest" all)")"; return 0; }
  {
    echo "phone.sh: все четыре слота заняты ветками, не слитыми в main. Снять одну (если она закрыта):"
    for s in "${SLOTS[@]}"; do
      rec="$(rec_last "$MAIN_BID.$s" all)"
      echo "  $s — $(cut -f2 <<<"$rec") @ $(cut -f3 <<<"$rec") · $(cut -f4 <<<"$rec")   →   Tools/phone.sh uninstall $s"
    done
  } >&2
  return 2
}

# Блокировка на выбор слота: две сессии не берут один слот.
lock_slots() {
  local d="$RECORD.lock" i=0
  until mkdir "$d" 2>/dev/null; do
    i=$((i + 1)); [ $i -gt 50 ] && { rm -rf "$d"; mkdir "$d" 2>/dev/null || die "не взял блокировку $d" 1; break; }
    sleep 0.2
  done
  trap 'rm -rf "$RECORD.lock"' EXIT
}

need_phone() {
  if xcrun devicectl list devices 2>/dev/null | grep -E "^$DEVICE_NAME[[:space:]]" | grep -qE '[[:space:]]available \(paired\)'; then return 0; fi
  echo "phone.sh: $DEVICE_NAME не «available (paired)» — попросить Алексея подключить кабель и разблокировать экран." >&2
  exit 3
}

case "$cmd" in
  install)
    IFS='|' read -r slug name < <(branch_app "$branch")
    if [ "$want_main" = 1 ] && [ "$branch" != "main" ]; then
      die "основное приложение «Light Plan» ($MAIN_BID) ставится только из main, сейчас ветка $branch. Из ветки — без --main: получится «$name»." 2
    fi
    if [ "$branch" = "main" ]; then
      bid="$MAIN_BID"; why="основное приложение"
    else
      [ "$dry" = 1 ] || lock_slots
      pick="$(pick_slot "$branch")" || exit $?
      slot="${pick%%$'\t'*}"; why="${pick#*$'\t'}"; bid="$MAIN_BID.$slot"
      # Бронь сразу (5-е поле `reserved`): параллельная сессия увидит слот занятым, а `list` не покажет чужое «до».
      [ "$dry" = 1 ] || printf '%s\t%s\t%s\t%s\treserved\n' "$bid" "$branch" "$sha$dirty" "$(date '+%Y-%m-%d %H:%M')" >> "$RECORD"
      rm -rf "$RECORD.lock"
    fi
    [ "$dry" = 1 ] && echo "dry-run: ветка $branch @ $sha$dirty → «$name», $bid (${slot:+слот ${slot#slot} — }$why)" && exit 0
    need_phone
    dd="/tmp/cc-phone-${slug:-main}"
    log="/tmp/cc-phone-${slug:-main}.log"
    echo "сборка «$name» ($bid) из $branch @ $sha$dirty…"
    ( cd "$root" && xcodebuild -project LightPlan.xcodeproj -scheme LightPlan-iOS -configuration Debug \
        -destination "platform=iOS,id=$DEVICE_ID" -derivedDataPath "$dd" -allowProvisioningUpdates \
        PRODUCT_BUNDLE_IDENTIFIER="$bid" INFOPLIST_KEY_CFBundleDisplayName="$name" build ) > "$log" 2>&1
    code=$?
    grep -nE 'error:|BUILD (SUCCEEDED|FAILED)' "$log" | head -10
    if [ $code -ne 0 ] && grep -q "maximum App ID limit" "$log"; then
      die "сборка не прошла: лимит Apple бесплатной команды (10 новых App ID за 7 дней). Слот $bid ещё не зарегистрирован — подождать, пока окно в 7 дней освободит места, либо поставить ветку под уже зарегистрированным: LP_BRANCH=<старая ветка> (приложение будет носить её имя). Журнал $log" 4
    fi
    [ $code -eq 0 ] || die "сборка не прошла (exit=$code), журнал $log" 4
    xcrun devicectl device install app --device "$DEVICE_ID" "$dd/Build/Products/Debug-iphoneos/LightPlan.app" \
      > "$log.install" 2>&1 || { tail -5 "$log.install"; die "установка не прошла (лимит бесплатной команды? тогда снять закрытые ветки: phone.sh list / uninstall)" 5; }
    # В записи — штамп собранного приложения (то же, что строка в его «Настройках»; файл build_stamp.plist), а не «сейчас»:
    # установка в другой день или с новым неотслеженным файлом не разводит `list` и экран (ревью GPT 28в).
    pl="$dd/Build/Products/Debug-iphoneos/LightPlan.app/build_stamp.plist"
    st_sha="$(/usr/libexec/PlistBuddy -c 'Print :LPBuildSha' "$pl" 2>/dev/null)"
    st_day="$(/usr/libexec/PlistBuddy -c 'Print :LPBuildDate' "$pl" 2>/dev/null)"
    printf '%s\t%s\t%s\t%s\n' "$bid" "$branch" "${st_sha:-$sha$dirty}" "${st_day:-$(date '+%Y-%m-%d')} $(date '+%H:%M')" >> "$RECORD"
    if xcrun devicectl device process launch --device "$DEVICE_ID" "$bid" > "$log.launch" 2>&1; then
      launched="запущено"
    else
      launched="стоит, но не запустилось (телефон заблокирован?) — открыть значок вручную"
    fi
    echo "на телефоне: «$name» ($bid${slot:+, слот ${slot#slot}}) из $branch @ $sha$dirty — $launched"
    ;;

  uninstall)
    # Слот («slotA»), ветка, которая сейчас стоит в слоте («wt/29-3g»), старый слаг («wt26», «br…») или ветка по-старому.
    holder_of() {   # ветка → идентификатор слота, где она записана последней
      local sl r
      for sl in "${SLOTS[@]}"; do
        r="$(rec_last "$MAIN_BID.$sl" all)"
        [ "$(cut -f2 <<<"$r")" = "$1" ] && { echo "$MAIN_BID.$sl"; return 0; }
      done
      return 1
    }
    if [ "$want_main" = 1 ]; then bid="$MAIN_BID"
    elif [ -n "$slug_arg" ]; then
      case "$slug_arg" in
        slot[A-D]) bid="$MAIN_BID.$slug_arg" ;;
        *)
          if bid="$(holder_of "$slug_arg")"; then :
          else
            case "$slug_arg" in
              */*)                            IFS='|' read -r s _ < <(branch_app "$slug_arg") ;;   # полное имя ветки — как при установке
              wt[A-Za-z0-9]*|br[A-Za-z0-9]*) s="$(printf '%s' "$slug_arg" | tr -cd 'A-Za-z0-9')" ;;
              *)                             s="wt$(printf '%s' "$slug_arg" | tr -cd 'A-Za-z0-9')" ;;
            esac
            bid="$MAIN_BID.$s"
          fi ;;
      esac
    else
      [ "$branch" = "main" ] && die "из main основное приложение снимается только явно: uninstall --main" 2
      if ! bid="$(holder_of "$branch")"; then
        IFS='|' read -r slug name < <(branch_app "$branch"); bid="$MAIN_BID.$slug"
      fi
    fi
    [ "$dry" = 1 ] && echo "dry-run: снять $bid" && exit 0
    need_phone
    xcrun devicectl device uninstall app --device "$DEVICE_ID" "$bid" > /tmp/cc-phone-uninstall.log 2>&1 \
      || { tail -3 /tmp/cc-phone-uninstall.log; die "не снято: $bid (devicectl вернул ошибку)" 5; }
    case "$bid" in "$MAIN_BID".slot[A-D]) printf '%s\t-\t-\t%s\n' "$bid" "$(date '+%Y-%m-%d %H:%M')" >> "$RECORD" ;; esac   # слот свободен
    echo "снято: $bid"
    ;;

  list)
    need_phone
    out="/tmp/cc-phone-apps.json"
    xcrun devicectl device info apps --device "$DEVICE_ID" --json-output "$out" > /tmp/cc-phone-apps.log 2>&1 \
      || { tail -3 /tmp/cc-phone-apps.log; die "не прочитал список приложений" 4; }
    echo "на $DEVICE_NAME (коммит — по записи установок $RECORD):"
    seen=" "
    while IFS=$'\t' read -r bid name; do
      seen="$seen$bid "
      case "$bid" in "$MAIN_BID".slot[A-D]) where="слот ${bid##*slot} · " ;; *) where="" ;; esac
      rec="$(rec_last "$bid")"
      if [ -n "$rec" ]; then
        IFS=$'\t' read -r _ b s t <<<"$rec"
        s="${s% (+ не закоммиченное)}"; [ "$s" != "$(cut -f3 <<<"$rec")" ] && s="$s+"   # старая запись: «(+ не закоммиченное)» = «+»
        echo "  «$name» $bid — ${where}Сборка · $("$root/Tools/build_stamp.sh" line "$b" "$s" "${t%% *}")"
      else echo "  «$name» $bid — записи об установке нет (ставилось не скриптом)"; fi
    done < <(jq -r '.result.apps[]? | select(.bundleIdentifier|startswith("Novopashin.LightPlan")) | [.bundleIdentifier,.name]|@tsv' "$out")
    for sl in "${SLOTS[@]}"; do
      case "$seen" in *" $MAIN_BID.$sl "*) ;; *) echo "  слот ${sl#slot} ($MAIN_BID.$sl) — свободен" ;; esac
    done
    ;;

  *) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; [ -z "$cmd" ] || exit 1 ;;
esac
