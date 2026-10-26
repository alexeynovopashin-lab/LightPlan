#!/bin/bash
# Сборка на iPhone Алексея — одним скриптом, по слову Алексея в конце итерации.
# Инцидент 28.09 (итерация 24): один идентификатор на все ветки, и установка
# ветки затёрла проверяемую правку. Теперь имя и идентификатор берутся из ветки,
# а основной идентификатор скрипт даёт только из `main`.
#
#   Tools/phone.sh install [--main] [--dry-run]   собрать, поставить, запустить (--dry-run: слот и адреса, без сборки)
#   Tools/phone.sh uninstall [--main|slotA|<ветка>|<старый слаг>]   снять приложение (ветка закрыта)
#   Tools/phone.sh list                           слот, ветка, sha, что стоит на телефоне; свободные слоты
#   make phone ARGS="install"
#
# Ветка → приложение. Бесплатная подпись Apple даёт 10 новых App ID за 7 дней, а идентификатор
# «из имени ветки» тратил по одному на каждый шаг (12.10 лимит кончился). Поэтому пул из
# четырёх постоянных идентификаторов — слоты Novopashin.LightPlan.slotA … slotD:
#   main      → «Light Plan», Novopashin.LightPlan          (только из main, слот не занимает)
#   wt/29-3g  → «LP 29-3g»,   один из слотов; имя — из записи «слот → ветка → sha → время»
# Слот выбирается так: тот же, что у этой ветки → свободный и уже зарегистрированный у Apple → самый старый
# слот ветки, уже слитой в main (зарегистрированный; его приложение заменится) → свободный, ещё не зарегистрированный
# (его первая установка тратит два App ID: приложение и .Widget) → слот слитой ветки без регистрации → иначе стоп,
# называем, что снять. «Зарегистрирован» = в записи есть установка этого идентификатора не старше 7 дней от
# первой установки в текущей регистрации (регистрация бесплатной команды живёт 7 дней и не продлевается сборками;
# из записи, у Apple не мерено; LP_PHONE_REG_DAYS меняет срок). Проверка: Tools/check_phone_slots.sh (make phoneslots).
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

# Регистрация идентификатора у Apple (бесплатная команда): живёт 7 дней с первой сборки и не продлевается — следующая
# сборка после срока регистрирует идентификатор заново и снова тратит из лимита «10 новых App ID за 7 дней» (и приложение,
# и .Widget). Срок считаем по записи: установки (не бронь и не «свободен») идут по времени; установка позже конца
# текущей регистрации открывает новую. Из записи, у Apple не мерено; на 26.10 это объясняет, почему слоты C и D
# (последняя установка 23.10 и 18.10) стали «новыми» при том, что A и B — действовали.
REG_DAYS="${LP_PHONE_REG_DAYS:-7}"

# «ГГГГ-ММ-ДД ЧЧ:ММ» → минуты от условной эры (только для разности; без date, одинаково на macOS и Linux).
ts_min() {
  local d="${1%% *}" hm="${1##* }" y m dd era yoe mp doy
  IFS=- read -r y m dd <<<"$d"
  y=$((10#$y)); m=$((10#$m)); dd=$((10#$dd))
  [ "$m" -le 2 ] && y=$((y - 1))
  era=$((y / 400)); yoe=$((y - era * 400)); mp=$(((m + 9) % 12))
  doy=$(((153 * mp + 2) / 5 + dd - 1))
  echo $(((era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + doy) * 1440 + 10#${hm%%:*} * 60 + 10#${hm##*:}))
}
now_min() { ts_min "${LP_PHONE_NOW:-$(date '+%Y-%m-%d %H:%M')}"; }

# Идентификатор → сколько минут ещё действует регистрация (пусто — не зарегистрирован или срок вышел).
reg_left() {
  local bid="$1" t m start="" span=$((REG_DAYS * 1440)) left
  while IFS= read -r t; do
    m="$(ts_min "$t")"
    if [ -z "$start" ] || [ $((m - start)) -ge "$span" ]; then start="$m"; fi
  done < <(awk -F'\t' -v b="$bid" '$1==b && $2!="-" && $5!="reserved" {print $4}' "$RECORD" 2>/dev/null | sort -u)
  [ -n "$start" ] || return 0
  left=$((start + span - $(now_min)))
  [ "$left" -gt 0 ] && echo "$left"
  return 0
}
days_word() { echo "$(($1 / 1440)) сут. $((($1 % 1440) / 60)) ч"; }

# Слот для ветки → в stdout «slotX<TAB>почему». Нет слота — отчёт в stderr, код 2.
# Порядок: свой слот → свободный зарегистрированный → самый старый слот слитой ветки (зарегистрированный) →
# свободный незарегистрированный → слот слитой ветки без регистрации. Новая регистрация стоит два App ID из десяти,
# поэтому незарегистрированное идёт последним (инцидент 26.10: слот C, лимит исчерпан, A и B со слитыми ветками стояли).
pick_slot() {
  local branch="$1" s bid rec b sh t left
  local free_reg="" free_reg_left="" free_new=""
  local old_reg="" old_reg_t="" old_new="" old_new_t=""
  for s in "${SLOTS[@]}"; do
    bid="$MAIN_BID.$s"; rec="$(rec_last "$bid" all)"
    b="$(cut -f2 <<<"$rec")"
    [ -n "$rec" ] && [ "$b" = "$branch" ] && { printf '%s\tтот же слот, что у этой ветки\n' "$s"; return 0; }
  done
  for s in "${SLOTS[@]}"; do
    bid="$MAIN_BID.$s"; rec="$(rec_last "$bid" all)"
    b="$(cut -f2 <<<"$rec")"; sh="$(cut -f3 <<<"$rec")"; t="$(cut -f4 <<<"$rec")"
    left="$(reg_left "$bid")"
    if [ -z "$rec" ] || [ "$b" = "-" ]; then
      if [ -n "$left" ]; then [ -z "$free_reg" ] && { free_reg="$s"; free_reg_left="$left"; }
      else [ -z "$free_new" ] && free_new="$s"; fi
    elif branch_closed "$b" "$sh"; then
      if [ -n "$left" ]; then
        if [ -z "$old_reg" ] || [[ "$t" < "$old_reg_t" ]]; then old_reg="$s"; old_reg_t="$t"; fi
      else
        if [ -z "$old_new" ] || [[ "$t" < "$old_new_t" ]]; then old_new="$s"; old_new_t="$t"; fi
      fi
    fi
  done
  [ -n "$free_reg" ] && { printf '%s\tсвободный слот, уже зарегистрирован у Apple (ещё %s) — новых App ID не тратит\n' "$free_reg" "$(days_word "$free_reg_left")"; return 0; }
  [ -n "$old_reg" ] && { printf '%s\tсамый старый слот закрытой ветки (%s, слита в main), зарегистрирован у Apple (ещё %s) — новых App ID не тратит\n' \
    "$old_reg" "$(cut -f2 <<<"$(rec_last "$MAIN_BID.$old_reg" all)")" "$(days_word "$(reg_left "$MAIN_BID.$old_reg")")"; return 0; }
  [ -n "$free_new" ] && { printf '%s\tсвободный слот, не зарегистрирован у Apple — первая сборка потратит два App ID (приложение и .Widget)\n' "$free_new"; return 0; }
  [ -n "$old_new" ] && { printf '%s\tслот закрытой ветки (%s, слита в main), регистрация у Apple вышла — сборка потратит два App ID (приложение и .Widget)\n' \
    "$old_new" "$(cut -f2 <<<"$(rec_last "$MAIN_BID.$old_new" all)")"; return 0; }
  {
    echo "phone.sh: все четыре слота заняты ветками, не слитыми в main. Снять одну (если она закрыта):"
    for s in "${SLOTS[@]}"; do
      rec="$(rec_last "$MAIN_BID.$s" all)"
      echo "  $s — $(cut -f2 <<<"$rec") @ $(cut -f3 <<<"$rec") · $(cut -f4 <<<"$rec")   →   Tools/phone.sh uninstall $s"
    done
  } >&2
  return 2
}

# Слоты слитых веток с действующей регистрацией (кроме $1) — что можно занять вместо незарегистрированного слота.
# Печатает строки «  slotX — ветка, слита в main, ещё N → Tools/phone.sh uninstall slotX, потом install снова».
merged_registered_slots() {
  local skip="$1" s bid rec b sh left
  for s in "${SLOTS[@]}"; do
    bid="$MAIN_BID.$s"; [ "$bid" = "$skip" ] && continue
    rec="$(rec_last "$bid" all)"; b="$(cut -f2 <<<"$rec")"; sh="$(cut -f3 <<<"$rec")"
    [ -n "$rec" ] && [ "$b" != "-" ] && branch_closed "$b" "$sh" || continue
    left="$(reg_left "$bid")"; [ -n "$left" ] || continue
    echo "  $s — $b, слита в main, регистрация ещё $(days_word "$left")   →   Tools/phone.sh uninstall $s, затем install снова"
  done
}

# Блокировка на выбор слота: две сессии не берут один слот. Своя — только если mkdir её создал; по тайм-ауту чужую
# не удаляем (её владелец мог быть жив) — выходим с ошибкой и называем папку.
LOCK_HELD=0
lock_slots() {
  local d="$RECORD.lock" i=0
  until mkdir "$d" 2>/dev/null; do
    i=$((i + 1))
    [ $i -gt 100 ] && die "блокировка $d занята другой сессией больше 20 с; если её владелец умер — rm -rf $d" 1
    sleep 0.2
  done
  LOCK_HELD=1
}
unlock_slots() { [ "$LOCK_HELD" = 1 ] && rmdir "$RECORD.lock" 2>/dev/null; LOCK_HELD=0; }

# Бронь слота (строка с 5-м полем `reserved`) снимается при любом выходе без записи об успешной установке:
# возвращаем прежнюю последнюю запись слота (его прежнее приложение на телефоне осталось) либо ставим «свободен».
RESERVED_BID=""; RESERVED_PREV=""
release_reservation() {
  [ -n "$RESERVED_BID" ] || return 0
  if [ -n "$RESERVED_PREV" ]; then printf '%s\n' "$RESERVED_PREV" >> "$RECORD"
  else printf '%s\t-\t-\t%s\n' "$RESERVED_BID" "$(date '+%Y-%m-%d %H:%M')" >> "$RECORD"; fi
  RESERVED_BID=""
}
on_exit() { release_reservation; unlock_slots; }
trap on_exit EXIT

# Телефон «available (paired)» читается сразу после uninstall с задержкой: 26.10 дважды exit 3, а через секунды
# devicectl уже показывал «available». Поэтому до LP_PHONE_WAIT секунд (по умолчанию 10) повторяем проверку раз в секунду.
need_phone() {
  local i=0 max="${LP_PHONE_WAIT:-10}"
  while :; do
    if xcrun devicectl list devices 2>/dev/null | grep -E "^$DEVICE_NAME[[:space:]]" | grep -qE '[[:space:]]available \(paired\)'; then return 0; fi
    [ "$i" -ge "$max" ] && break
    i=$((i + 1)); sleep 1
  done
  echo "phone.sh: $DEVICE_NAME не «available (paired)» (ждали $max с) — попросить Алексея подключить кабель и разблокировать экран." >&2
  exit 3
}

# Подключение как библиотеки (Tools/check_phone_slots.sh): функции есть, команды не выполняются.
[ -n "${LP_PHONE_LIB:-}" ] && return 0

case "$cmd" in
  install)
    IFS='|' read -r slug name < <(branch_app "$branch")
    if [ "$want_main" = 1 ] && [ "$branch" != "main" ]; then
      die "основное приложение «Light Plan» ($MAIN_BID) ставится только из main, сейчас ветка $branch. Из ветки — без --main: получится «$name»." 2
    fi
    if [ "$branch" = "main" ]; then
      bid="$MAIN_BID"; why="основное приложение"
      [ "$dry" = 1 ] && echo "dry-run: ветка $branch @ $sha$dirty → «$name», $bid ($why)" && { "$root/Tools/check_widget_id.sh" --ids "$bid"; exit $?; }
      need_phone
    else
      [ "$dry" = 1 ] || need_phone
      lock_slots
      pick="$(pick_slot "$branch")" || exit $?
      slot="${pick%%$'\t'*}"; why="${pick#*$'\t'}"; bid="$MAIN_BID.$slot"
      # Бронь сразу (5-е поле `reserved`): параллельная сессия, в том числе `--dry-run`, увидит слот занятым, а `list`
      # не покажет чужое «до». Снимается при любом выходе без установки (on_exit); dry-run держит бронь
      # LP_PHONE_DRY_HOLD секунд — этим проверяют параллельные сессии.
      RESERVED_PREV="$(rec_last "$bid" all)"
      printf '%s\t%s\t%s\t%s\treserved\n' "$bid" "$branch" "$sha$dirty" "$(date '+%Y-%m-%d %H:%M')" >> "$RECORD"
      RESERVED_BID="$bid"
      unlock_slots
      if [ "$dry" = 1 ]; then
        echo "dry-run: ветка $branch @ $sha$dirty → «$name», $bid (слот ${slot#slot} — $why)"
        # Адреса виджета и общей папки (30б.1) — из настроек сборки с тем же LP_APP_ID, что уйдёт в xcodebuild.
        "$root/Tools/check_widget_id.sh" --ids "$bid" || exit 1
        sleep "${LP_PHONE_DRY_HOLD:-0}"
        exit 0
      fi
    fi
    dd="/tmp/cc-phone-${slug:-main}"
    log="/tmp/cc-phone-${slug:-main}.log"
    echo "сборка «$name» ($bid${slot:+, слот ${slot#slot} — $why}) из $branch @ $sha$dirty…"
    ( cd "$root" && xcodebuild -project LightPlan.xcodeproj -scheme LightPlan-iOS -configuration Debug \
        -destination "platform=iOS,id=$DEVICE_ID" -derivedDataPath "$dd" -allowProvisioningUpdates \
        LP_APP_ID="$bid" LP_APP_NAME="$name" build ) > "$log" 2>&1
    code=$?
    grep -nE 'error:|BUILD (SUCCEEDED|FAILED)' "$log" | head -10
    if [ $code -ne 0 ] && grep -q "maximum App ID limit" "$log"; then
      alt="$(merged_registered_slots "$bid")"
      if [ -n "$alt" ]; then alt_msg=" Занять вместо него можно слот слитой ветки, уже зарегистрированный — его приложение заменится:
$alt"
      else alt_msg=" Зарегистрированных слотов слитых веток нет — ждать, пока окно в 7 дней освободит места."; fi
      die "сборка не прошла: лимит Apple бесплатной команды (10 новых App ID за 7 дней). Идентификатор $bid у Apple сейчас не зарегистрирован.$alt_msg
Журнал $log" 4
    fi
    [ $code -eq 0 ] || die "сборка не прошла (exit=$code), журнал $log" 4
    # Значок (24.10): «LP …» — с «α», основной — чистый; иначе не ставим (два «Light Plan» без различия на экране).
    "$root/Tools/check_app_icon.sh" "$dd/Build/Products/Debug-iphoneos/LightPlan.app" || die "значок не тот — не ставлю" 4
    # Виджет (30б.1): внутри, с адресом <приложение>.Widget и общей папкой group.<приложение> у обоих — иначе не ставим.
    "$root/Tools/check_widget_id.sh" "$dd/Build/Products/Debug-iphoneos/LightPlan.app" || die "адреса виджета не те — не ставлю" 4
    xcrun devicectl device install app --device "$DEVICE_ID" "$dd/Build/Products/Debug-iphoneos/LightPlan.app" \
      > "$log.install" 2>&1 || { tail -5 "$log.install"; die "установка не прошла (лимит бесплатной команды? тогда снять закрытые ветки: phone.sh list / uninstall)" 5; }
    # В записи — штамп собранного приложения (то же, что строка в его «Настройках»; файл build_stamp.plist), а не «сейчас»:
    # установка в другой день или с новым неотслеженным файлом не разводит `list` и экран (ревью GPT 28в).
    pl="$dd/Build/Products/Debug-iphoneos/LightPlan.app/build_stamp.plist"
    st_sha="$(/usr/libexec/PlistBuddy -c 'Print :LPBuildSha' "$pl" 2>/dev/null)"
    st_day="$(/usr/libexec/PlistBuddy -c 'Print :LPBuildDate' "$pl" 2>/dev/null)"
    printf '%s\t%s\t%s\t%s\n' "$bid" "$branch" "${st_sha:-$sha$dirty}" "${st_day:-$(date '+%Y-%m-%d')} $(date '+%H:%M')" >> "$RECORD"
    RESERVED_BID=""   # установка подтверждена записью — бронь не снимать
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
