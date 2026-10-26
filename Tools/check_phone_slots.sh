#!/bin/bash
# Самопроверка выбора слота в Tools/phone.sh (pick_slot) на подложной записи установок и подложном репозитории.
#
#   Tools/check_phone_slots.sh [путь/к/phone.sh]        make phoneslots
#
# Без аргумента проверяет Tools/phone.sh рядом. Со старым скриптом падает:
#   git show origin/main:Tools/phone.sh > /tmp/old_phone.sh; Tools/check_phone_slots.sh /tmp/old_phone.sh
# Сценарии: свой слот; свободный зарегистрированный раньше ни разу не зарегистрированного; самый старый слот слитой
# ветки раньше незарегистрированного; незарегистрированный — последним (в том числе слот, чья регистрация вышла через
# 7 дней); повтор инцидента 26.10 (слот C тратил последние App ID, хотя A и B держали слитые ветки); стоп, когда
# слоты заняты живыми ветками. «Сейчас» подменяется LP_PHONE_NOW; телефон, Apple и xcodebuild не трогаются.

set -u
here="$(cd "$(dirname "$0")" && pwd)"
PHONE="${1:-$here/phone.sh}"
[ -f "$PHONE" ] || { echo "check_phone_slots.sh: нет $PHONE" >&2; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"; git init -q -b main "$repo"
g() { git -C "$repo" -c user.name=t -c user.email=t@t "$@"; }
g commit -q --allow-empty -m base
g branch wt/old1; g branch wt/old2; g branch wt/old3        # предки main → «слиты»
g commit -q --allow-empty -m next
g checkout -q -b wt/live1; g commit -q --allow-empty -m l1; g checkout -q main     # не слиты
g checkout -q -b wt/live2; g commit -q --allow-empty -m l2; g checkout -q main
g checkout -q -b wt/live3; g commit -q --allow-empty -m l3; g checkout -q main
g checkout -q -b wt/mine;  g commit -q --allow-empty -m m;  g checkout -q main

NOW="2026-10-26 10:20"
B="Novopashin.LightPlan"
fail=0; n=0
rec() { printf '%s\t%s\t%s\t%s\n' "$B.$1" "$2" "${3:-abc1234}" "$4"; }   # слот ветка [sha] время; ветка «-» — слот свободен

# pick <имя> <ветка> <ожидаемый слот|STOP> <слово в причине> ; запись — со stdin (не через конвейер: счётчики должны жить в этой оболочке)
pick() {
  local name="$1" br="$2" want="$3" kw="$4" out code got why
  n=$((n + 1)); cat > "$tmp/rec.tsv"
  # Параметры — через окружение: phone.sh при подключении делает shift и съел бы позиционные.
  out="$( LP_PHONE_LIB=1 LP_PHONE_RECORD="$tmp/rec.tsv" LP_PHONE_NOW="$NOW" T_PHONE="$PHONE" T_REPO="$repo" T_ARG="$br" bash -c '
      source "$T_PHONE" >/dev/null 2>&1; root="$T_REPO"; pick_slot "$T_ARG"' 2>/dev/null )"; code=$?
  if [ "$want" = STOP ]; then
    [ $code -eq 2 ] && [ -z "$out" ] && { echo "да  $name → стоп (код 2)"; return; }
    echo "нет $name: ждали стоп (код 2), получили код $code, «$out»"; fail=$((fail + 1)); return
  fi
  got="${out%%$'\t'*}"; why="${out#*$'\t'}"
  if [ "$got" = "$want" ] && [[ "$why" == *"$kw"* ]]; then echo "да  $name → $got ($why)"
  else echo "нет $name: ждали $want с «$kw», получили «$got» · «$why»"; fail=$((fail + 1)); fi
}

{ rec slotA wt/old1 x "2026-10-25 11:47"; rec slotB wt/mine x "2026-10-25 23:42"; rec slotC wt/live1 x "2026-10-25 12:00"; } > "$tmp/in.tsv"
pick "свой слот раньше всего" wt/mine slotB "тот же слот" < "$tmp/in.tsv"
{ rec slotB wt/mine x "2026-10-25 23:42"; rec slotC - - "2026-10-25 20:00"; } > "$tmp/in.tsv"
pick "свой слот раньше свободного зарегистрированного" wt/mine slotB "тот же слот" < "$tmp/in.tsv"

# A свободен и ни разу не ставился, B свободен и зарегистрирован (ставили позавчера), C и D живые.
{ rec slotB wt/old2 x "2026-10-24 09:00"; rec slotB - - "2026-10-25 09:00"
  rec slotC wt/live1 x "2026-10-25 12:00"; rec slotD wt/live2 x "2026-10-25 13:00"; } > "$tmp/in.tsv"
pick "свободный зарегистрированный раньше ни разу не зарегистрированного" wt/new slotB "свободный слот, уже зарегистрирован" < "$tmp/in.tsv"

# A слитая (ставили 25.10), B слитая и старше (24.10), C живая, D свободен и ни разу не ставился.
{ rec slotA wt/old1 x "2026-10-25 11:47"; rec slotB wt/old2 x "2026-10-24 09:00"
  rec slotC wt/live1 x "2026-10-25 12:00"; } > "$tmp/in.tsv"
pick "самый старый слот слитой ветки раньше ни разу не зарегистрированного" wt/new slotB "закрытой ветки" < "$tmp/in.tsv"

# A, B, C живые; D свободен и ни разу не ставился — только он остался.
{ rec slotA wt/live1 x "2026-10-25 11:47"; rec slotB wt/live2 x "2026-10-25 12:00"; rec slotC wt/live3 x "2026-10-25 13:00"; } > "$tmp/in.tsv"
pick "ни разу не зарегистрированный — последним" wt/new slotD "не зарегистрирован" < "$tmp/in.tsv"

# Регистрация A вышла: ставили 12.10, с тех пор 7 дней прошло; слот свободен — это «новый» слот, не зарегистрированный.
# B свободен и действует (ставили 25.10).
{ rec slotA wt/old1 x "2026-10-12 10:00"; rec slotA - - "2026-10-13 10:00"
  rec slotB wt/old2 x "2026-10-25 10:00"; rec slotB - - "2026-10-25 12:00"
  rec slotC wt/live1 x "2026-10-25 12:00"; rec slotD wt/live2 x "2026-10-25 13:00"; } > "$tmp/in.tsv"
pick "свободный с вышедшей регистрацией не обгоняет действующий" wt/new slotB "уже зарегистрирован" < "$tmp/in.tsv"

# Слитая ветка с вышедшей регистрацией тратит те же App ID, что свободный новый: свободный лучше (приложение не теряется).
{ rec slotA wt/old1 x "2026-10-12 10:00"; rec slotB wt/live1 x "2026-10-25 12:00"; rec slotC wt/live2 x "2026-10-25 13:00"; } > "$tmp/in.tsv"
pick "слитая с вышедшей регистрацией — после свободного новой" wt/new slotD "не зарегистрирован" < "$tmp/in.tsv"
{ rec slotA wt/old1 x "2026-10-12 10:00"; rec slotB wt/live1 x "2026-10-25 12:00"
  rec slotC wt/live2 x "2026-10-25 13:00"; rec slotD wt/live3 x "2026-10-25 14:00"; } > "$tmp/in.tsv"
pick "слитая с вышедшей регистрацией — если больше нечего" wt/new slotA "регистрация у Apple вышла" < "$tmp/in.tsv"

# Повтор инцидента 26.10 по настоящей записи: C свободен, ставили до 23.10 (регистрация с 18.10 вышла), A слита
# (music, 25.10), B живая (pole-1; регистрация с 22.10), D слита (29-8v11, 18.10 — вышла). Старый скрипт брал C.
{ rec slotC wt/29-8v9a x "2026-10-18 19:17"; rec slotD wt/29-8v11 x "2026-10-18 22:16"
  rec slotC wt/30-wx x "2026-10-23 11:11"; rec slotB wt/30-cal5 x "2026-10-22 21:42"
  rec slotA wt/old1 x "2026-10-25 11:47"; rec slotB wt/live1 x "2026-10-25 23:42"
  rec slotC - - "2026-10-24 18:20"; } > "$tmp/in.tsv"
pick "повтор инцидента 26.10: A слитая, C без регистрации" wt/30b-2v slotA "закрытой ветки" < "$tmp/in.tsv"

# Все слоты заняты живыми ветками.
{ rec slotA wt/live1 x "2026-10-25 11:47"; rec slotB wt/live2 x "2026-10-25 12:00"
  rec slotC wt/live3 x "2026-10-25 13:00"; rec slotD wt/mine x "2026-10-25 14:00"; } > "$tmp/in.tsv"
pick "все слоты у живых веток" wt/new STOP "" < "$tmp/in.tsv"

# Подсказка при отказе лимита: слоты слитых веток с действующей регистрацией, кроме выбранного.
n=$((n + 1))
{ rec slotA wt/old1 x "2026-10-25 11:47"; rec slotB wt/live1 x "2026-10-25 23:42"; rec slotC - - "2026-10-24 18:20"
  rec slotD wt/old3 x "2026-10-18 22:16"; } > "$tmp/rec.tsv"
hint="$( LP_PHONE_LIB=1 LP_PHONE_RECORD="$tmp/rec.tsv" LP_PHONE_NOW="$NOW" T_PHONE="$PHONE" T_REPO="$repo" T_ARG="$B.slotC" bash -c '
    source "$T_PHONE" >/dev/null 2>&1; root="$T_REPO"; merged_registered_slots "$T_ARG"' 2>/dev/null )"
if [[ "$hint" == *"slotA"* && "$hint" != *"slotB"* && "$hint" != *"slotD"* && "$hint" == *"uninstall slotA"* ]]; then
  echo "да  подсказка при лимите называет только slotA (слита, зарегистрирована)"
else echo "нет подсказка при лимите: «$hint»"; fail=$((fail + 1)); fi

# Проверка телефона: devicectl не сразу видит «available (paired)» (26.10 после uninstall — exit 3 зря).
# Подложный xcrun: первые N вызовов пусто, дальше «available (paired)». need_phone не должен падать при N < ожидания.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/xcrun" <<'XEOF'
#!/bin/bash
c=$(cat "$FAKE_COUNT" 2>/dev/null || echo 0); echo $((c + 1)) > "$FAKE_COUNT"
[ "$c" -ge "$FAKE_FAILS" ] && echo "iPhone ALno   x   y   available (paired)   iPhone16,2"
exit 0
XEOF
chmod +x "$tmp/bin/xcrun"
need() {   # <имя> <сколько вызовов пусто> <LP_PHONE_WAIT> <ждём код>
  local name="$1" fails="$2" wait="$3" want="$4" code
  n=$((n + 1)); rm -f "$tmp/count"
  ( PATH="$tmp/bin:$PATH" FAKE_COUNT="$tmp/count" FAKE_FAILS="$fails" LP_PHONE_LIB=1 LP_PHONE_WAIT="$wait" LP_PHONE_RECORD="$tmp/rec.tsv" \
      T_PHONE="$PHONE" bash -c 'source "$T_PHONE" >/dev/null 2>&1; need_phone' >/dev/null 2>&1 ); code=$?
  if [ "$code" = "$want" ]; then echo "да  $name → код $code"; else echo "нет $name: ждали код $want, получили $code"; fail=$((fail + 1)); fi
}
need "телефон виден сразу" 0 5 0
need "телефон появился через 2 с — повтор, не exit 3" 2 5 0
need "телефона нет совсем — exit 3 после ожидания" 99 2 3

echo "---"
[ $fail -eq 0 ] && { echo "выбор слота: $n из $n — да"; exit 0; }
echo "выбор слота: нет в $fail из $n"; exit 1
