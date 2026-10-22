#!/bin/bash
# Проверка шага: пять строк да/нет вместо «кажется, готово» (итерация 26т,
# метод работы 29.09: правила про ревью и про тесты держались на памяти треда).
#
#   Tools/check_step.sh <ветка> [<база>] [--type код|данные|документы] [--tests] [--full]
#   make checkstep ARGS="wt/26 main --type код --tests --full"
#
#   1. коммит в ветке впереди базы (база по умолчанию — main);
#   2. дифф без сгенерированного не пустой (N файлов) — тот же отбор, что у ревью GPT;
#   3. ревью GPT к последнему ОТПРАВЛЕННОМУ коммиту есть, запуск не красный
#      (открытый API GitHub через curl, без gh; GITHUB_TOKEN — если упрётесь в лимит);
#   4. новые тесты падают на родительском коммите — это сборка, поэтому по флагу
#      --tests. Без флага строка «не проверялась», а не «да».
#   5. полный набор тестов не краснее базы (общий предок ветки и базы): упавшие на ветке против упавших на базе,
#      поимённо. «Нет» — только если на ветке упал тест, который на базе проходил. Тест, красный и на базе, —
#      «да» с пометкой «уже красный на базе». Это два полных прогона `xcodebuild test` на симуляторе `LP checkstep`
#      (минуты), поэтому по флагу --full; без флага — «не проверялась». Доп. аргументы xcodebuild (сузить набор,
#      например для самопроверки): LP_FULL_TESTING_ARGS="-only-testing:LightPlanUITests/FormFlowTests".
# Тип шага (по умолчанию код): у «кода» жёлтый запуск ревью (в пуше только
# данные) = «нет»; у «данных» и «документов» жёлтое — да, а тесты не требуются.
#
# Коды: 0 — всё да; 1 — есть «нет»; 2 — «нет» нет, но что-то не проверялось.

set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 1

branch=""; base=""; type="код"; run_tests=0; run_full=0
while [ $# -gt 0 ]; do
  case "$1" in
    --type) type="${2:-}"; shift ;;
    --tests) run_tests=1 ;;
    --full) run_full=1 ;;
    -*) echo "check_step.sh: не знаю флага $1" >&2; exit 1 ;;
    *) if [ -z "$branch" ]; then branch="$1"; else base="$1"; fi ;;
  esac
  shift
done
base="${base:-main}"
case "$type" in код|данные|документы) ;; *) echo "check_step.sh: --type код|данные|документы" >&2; exit 1 ;; esac
[ -n "$branch" ] || { sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
git rev-parse -q --verify "$branch^{commit}" >/dev/null || { echo "check_step.sh: нет ветки $branch" >&2; exit 1; }
git rev-parse -q --verify "$base^{commit}" >/dev/null || { echo "check_step.sh: нет базы $base" >&2; exit 1; }

# Что ревью GPT не читает: сгенерированное и данные (см. .github/workflows/openai-review.yml).
EXCL=(':(exclude)*.generated.swift' ':(exclude)*.xcstrings' ':(exclude)*.json' ':(exclude)*.pbxproj'
      ':(exclude)**/Fixtures/**' ':(exclude)*.png' ':(exclude)*.jpg' ':(exclude)*.pdf')

fails=0; skipped=0
WTS=(); TMPS=()
cleanup() {
  local w
  for w in ${WTS[@]+"${WTS[@]}"}; do git worktree remove --force "$w" >/dev/null 2>&1; rm -rf "$(dirname "$w")"; done
  for w in ${TMPS[@]+"${TMPS[@]}"}; do rm -rf "$w"; done
}
trap cleanup EXIT
row() { # да|нет|?  текст
  case "$1" in да) ;; нет) fails=$((fails + 1)) ;; *) skipped=$((skipped + 1)) ;; esac
  printf '%-3s %s\n' "$1" "$2"
}

echo "шаг: $branch против $base, тип «$type»"

# 1. Коммит впереди базы.
ahead="$(git rev-list --count "$base..$branch")"
if [ "$ahead" -gt 0 ]; then row да "1. в ветке впереди $base коммитов: $ahead (последний $(git rev-parse --short "$branch"))"
else row нет "1. в ветке нет коммитов впереди $base"; fi

# 2. Дифф без сгенерированного.
mb="$(git merge-base "$base" "$branch")"
# Для «данных» и «документов» json и Fixtures — это и есть содержание шага: отбрасываем только то, что пишет генератор кода.
if [ "$type" = "код" ]; then excl=("${EXCL[@]}"); else excl=(':(exclude)*.generated.swift' ':(exclude)*.xcstrings' ':(exclude)*.pbxproj'); fi
nfiles="$(git diff --name-only "$mb" "$branch" -- . "${excl[@]}" | wc -l | tr -d ' ')"
if [ "$nfiles" -gt 0 ]; then row да "2. дифф без сгенерированного: $nfiles файлов"
else row нет "2. дифф без сгенерированного пустой (в ветке только данные или ничего)"; fi

# 3. Ревью GPT к последнему отправленному коммиту.
remote_url="$(git remote get-url origin 2>/dev/null)"
repo="$(printf '%s' "$remote_url" | sed -E 's#^.*github\.com[:/]##; s#\.git$##')"
pushed="$(git ls-remote origin "refs/heads/$branch" 2>/dev/null | awk '{print $1}' | head -1)"
if [ -z "$pushed" ]; then
  row нет "3. ветка не отправлена в GitHub — ревью GPT ещё не было"
else
  short="${pushed:0:7}"
  extra=""; unpushed=0
  if [ "$pushed" != "$(git rev-parse "$branch")" ]; then
    unpushed=1; extra=" (локально ветка впереди отправленного: $(git rev-list --count "$pushed..$branch" 2>/dev/null || echo '?') коммитов без ревью)"
  fi
  auth=(); [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  api() { curl -sS -m 30 ${auth[@]+"${auth[@]}"} -H 'Accept: application/vnd.github+json' -o "$2" -w '%{http_code}' "https://api.github.com/repos/$repo/$1" 2>/dev/null; }
  tmp="$(mktemp -d)"; TMPS+=("$tmp")
  c1="$(api "commits/$pushed/comments?per_page=100" "$tmp/c.json")"
  c2="$(api "actions/runs?head_sha=$pushed&per_page=20" "$tmp/r.json")"
  if [ "$unpushed" = 1 ]; then
    row нет "3. в ветке есть неотправленные коммиты — ревью GPT смотрело только $short$extra"
  elif [ "$c1" != 200 ] || [ "$c2" != 200 ]; then
    row нет "3. GitHub ответил $c1/$c2 (лимит без ключа? задать GITHUB_TOKEN) — ревью к $short не проверено"
  else
    body="$(jq -r '[.[] | select(.body | test("^(### Второе мнение OpenAI|ℹ️ Ревью не нужно|⛔ Ревью не было)"))] | last | .body // empty' "$tmp/c.json" | head -1)"
    run="$(jq -r '[.workflow_runs[] | select(.name=="OpenAI review")] | first | "\(.status // "-") \(.conclusion // "-")"' "$tmp/r.json")"
    rstatus="${run%% *}"; rconc="${run##* }"
    case "$body" in
      "### Второе мнение"*) kind=review ;;
      "ℹ️"*) kind=yellow ;;
      "⛔"*) kind=lost ;;
      *) kind=none ;;
    esac
    if [ "$rstatus" = "-" ] || [ "$rstatus" = "null" ]; then
      row нет "3. запуска ревью GPT к $short нет$extra"
    elif [ "$rstatus" != "completed" ]; then
      row нет "3. ревью GPT к $short ещё идёт ($rstatus) — подождать комментария$extra"
    elif [ "$rconc" = "failure" ] || [ "$rconc" = "cancelled" ] || [ "$rconc" = "timed_out" ] || [ "$kind" = lost ]; then
      row нет "3. запуск ревью GPT к $short красный ($rconc)$extra"
    else
      case "$kind" in
        review) row да "3. ревью GPT к $short есть, запуск зелёный$extra" ;;
        yellow)
          if [ "$type" = "код" ]; then row нет "3. запуск ревью к $short жёлтый («ревью не нужно, только данные») — для шага «код» это «нет»$extra"
          else row да "3. запуск ревью к $short жёлтый — для типа «$type» допустимо$extra"; fi ;;
        *) row нет "3. запуск зелёный, а комментария ревью к $short нет$extra" ;;
      esac
    fi
  fi
fi

# 4. Новые тесты падают на родительском коммите.
if [ "$type" != "код" ]; then
  row да "4. тесты не требуются (тип «$type»)"
elif [ "$run_tests" = 0 ]; then
  row "?" "4. не проверялась: это сборка, запускать с --tests"
else
  tfiles="$(git diff --name-only --diff-filter=AM "$mb" "$branch" -- 'Packages/*/Tests/*.swift')"
  # Новые тесты: `@Test` (Swift Testing) над func и `func test…` (XCTest).
  names="$(git diff -U0 "$mb" "$branch" -- 'Packages/*/Tests/*.swift' | grep -E '^\+' | awk '
    /@Test/ { flag = 1 }
    match($0, /func [A-Za-z0-9_]+/) { n = substr($0, RSTART + 5, RLENGTH - 5); if (flag || n ~ /^test/) print n; flag = 0 }
  ' | sort -u)"
  if [ -z "$tfiles" ] || [ -z "$names" ]; then
    row нет "4. в диффе нет новых тестов пакетов (@Test или func test…) — нечего проверять на старом коде"
  else
    wt="$(mktemp -d)/base"
    git worktree add -q --detach "$wt" "$mb" 2>/dev/null || { row нет "4. не смог поднять папку с родительским коммитом"; wt=""; }
    if [ -n "$wt" ]; then
      WTS+=("$wt")
      # Тесты ветки поверх кода родителя.
      while IFS= read -r f; do mkdir -p "$wt/$(dirname "$f")"; git show "$branch:$f" > "$wt/$f"; done <<<"$tfiles"
      pkgs="$(printf '%s\n' "$tfiles" | sed -E 's#^(Packages/[^/]+)/.*#\1#' | sort -u)"
      total="$(printf '%s\n' "$names" | wc -l | tr -d ' ')"
      filt="$(printf '%s\n' "$names" | paste -sd'|' -)"
      failed_any=0; built_any=0; unverified=0; detail=""
      while IFS= read -r p; do
        log="/tmp/cc-checkstep-$(basename "$p").log"
        ( cd "$wt/$p" && swift test --filter "$filt" ) > "$log" 2>&1; code=$?
        if [ $code -ne 0 ]; then
          # Падение считаем только подтверждённое: тест назван в журнале как упавший, либо сборка
          # не находит нового API (тест на новое поведение). Прочее — окружение, «не проверено».
          if grep -qE "Test Case .* failed|✘ Test|✘ Suite" "$log"; then
            failed_any=1; detail="$detail $(basename "$p"): падают ($(grep -cE "Test Case .* failed|✘ Test" "$log"));"
          elif grep -qE 'error:.*(cannot find|has no member|no such module|extra argument|missing argument|cannot be used|is not compatible with expected)' "$log"; then
            failed_any=1; detail="$detail $(basename "$p"): не собирается на старом коде (нового API нет) — слабее падения;"
          else
            unverified=1; detail="$detail $(basename "$p"): swift test упал не по тесту, см. журнал;"
          fi
        else
          built_any=1; detail="$detail $(basename "$p"): ПРОХОДЯТ на старом коде;"
        fi
      done <<<"$pkgs"
      if [ "$built_any" = 1 ]; then row нет "4. новые тесты ($total) проходят и на родительском коде — они ничего не доказывают:$detail журнал /tmp/cc-checkstep-*.log"
      elif [ "$unverified" = 1 ]; then row "?" "4. не удалось проверить: журнал /tmp/cc-checkstep-*.log —$detail"
      elif [ "$failed_any" = 1 ]; then row да "4. новые тесты ($total) падают на родительском коммите ${mb:0:7}:$detail"
      fi
    fi
  fi
fi

# 5. Полный набор не краснее базы.
if [ "$type" != "код" ]; then
  row да "5. полный набор не требуется (тип «$type»)"
elif [ "$run_full" = 0 ]; then
  row "?" "5. не проверялась: полный набор — два прогона xcodebuild test, запускать с --full"
else
  simline="$(LP_SIM="LP checkstep" node "$root/Tools/sim.js" 2>/dev/null | tail -1)"
  udid="$(printf '%s' "$simline" | awk -F' · ' '{print $3}')"
  if [ -z "$udid" ]; then
    row "?" "5. не удалось получить симулятор «LP checkstep» (Tools/sim.js): $simline"
  else
    fulldir="$(mktemp -d)"; TMPS+=("$fulldir" /tmp/cc-checkstep-dd-branch /tmp/cc-checkstep-dd-base)
    # boot_wait <udid>: ждёт `simctl bootstatus -b` не дольше 180 с; код 0 — загрузился, иначе — нет (таймер снимается всегда).
    boot_wait() {
      local bpid wpid rc
      xcrun simctl bootstatus "$1" -b > /dev/null 2>&1 & bpid=$!
      ( sleep 180; kill "$bpid" 2>/dev/null ) > /dev/null 2>&1 & wpid=$!
      wait "$bpid" 2>/dev/null; rc=$?
      kill "$wpid" 2>/dev/null; wait "$wpid" 2>/dev/null
      return $rc
    }
    # failed_tests <папка проекта> <метка>  → файл $fulldir/<метка>.failed (имена).
    # Код: 0 — прогон дошёл до итога (TEST SUCCEEDED либо TEST FAILED с набором результатов);
    #      1 — не собралось (BUILD FAILED); 2 — прервано (убит, нет итоговой строки xcodebuild) или нет ни одного теста.
    failed_tests() {
      local dir="$1" lab="$2" bundle log xc
      bundle="$fulldir/$lab.xcresult"; log="$fulldir/$lab.log"
      rm -rf "/tmp/cc-checkstep-dd-$lab"
      # Прогон, не дошедший до итога (симулятор не поднялся за минуту под нагрузкой машины, служба симулятора зависла),
      # повторяем: до трёх попыток, перед каждой — дождаться загрузки симулятора (`bootstatus -b`, не дольше 3 минут), а при
      # повторе — выключить и поднять его заново. Собранный проект остаётся в derived data, повтор дешёв. Итог
      # (TEST SUCCEEDED / TEST FAILED / BUILD FAILED) повтором не лечится: красный тест остаётся красным (29.8в.28).
      # `-collect-test-diagnostics never`: при красном тесте xcodebuild собирал диагностику симулятора и ждал ответа ровно
      # 600 с («Timed out after 600.0 seconds», замер 29.8в.28: прогон 68 с стал 667 с); имена упавших берутся из xcresult.
      local attempt=1 tries=3
      while :; do
        # Ждём загрузку не дольше трёх минут: служба симулятора, которая завесилась, не должна вешать и проверку шага.
        if ! boot_wait "$udid"; then
          echo "    (строка 5, $lab: симулятор не поднялся за 3 минуты — выключаю и поднимаю заново)" >&2
          xcrun simctl shutdown "$udid" > /dev/null 2>&1; sleep 5; xcrun simctl boot "$udid" > /dev/null 2>&1
          boot_wait "$udid" || echo "    (строка 5, $lab: симулятор и после перезапуска не готов — пробую прогон всё равно, повтор ниже подхватит)" >&2
        fi
        rm -rf "$bundle"
        ( cd "$dir" && xcodebuild test -project LightPlan.xcodeproj -scheme LightPlan-iOS \
            -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "/tmp/cc-checkstep-dd-$lab" \
            -resultBundlePath "$bundle" -collect-test-diagnostics never ${LP_FULL_TESTING_ARGS:-} ) > "$log" 2>&1
        xc=$?
        if grep -qE '\*\* (TEST (SUCCEEDED|FAILED)|BUILD FAILED|TEST BUILD FAILED) \*\*' "$log" || [ "$attempt" -ge "$tries" ]; then break; fi
        echo "    (строка 5, $lab: прогон прерван без итога, код $xc; попытка $attempt из $tries, симулятор перезапускаю)" >&2
        cp "$log" "/tmp/cc-checkstep-full-$lab.attempt$attempt.log"
        xcrun simctl shutdown "$udid" > /dev/null 2>&1; sleep 5
        xcrun simctl boot "$udid" > /dev/null 2>&1
        attempt=$((attempt + 1))
      done
      cp "$log" "/tmp/cc-checkstep-full-$lab.log"
      # Итог по самому xcodebuild: частичный набор результатов прерванного прогона не считаем итогом.
      if grep -qE '\*\* (TEST )?BUILD FAILED \*\*' "$log"; then return 1; fi
      if [ "$xc" -eq 0 ]; then grep -q '\*\* TEST SUCCEEDED \*\*' "$log" || return 2
      else grep -q '\*\* TEST FAILED \*\*' "$log" || return 2; fi
      [ -d "$bundle" ] || return 2
      xcrun xcresulttool get test-results tests --path "$bundle" 2>/dev/null | jq -r '
        def w($p): ($p + [.name]) as $q
          | (if .nodeType == "Test Case" and .result == "Failed" then ($q[1:] | join("/")) else empty end),
            (.children[]? | w($q));
        .testNodes[]? | w([])' | sort -u > "$fulldir/$lab.failed" || return 2
      # Прогон без единого теста (фильтр промахнулся, набор не собрался) — не итог.
      xcrun xcresulttool get test-results summary --path "$bundle" 2>/dev/null \
        | jq -e '(.passedTests + .failedTests + .skippedTests) > 0' >/dev/null 2>&1 || return 2
      # Красный код выхода без единого упавшего теста в наборе — тоже не итог (упало что-то кроме тестов).
      if [ "$xc" -ne 0 ] && [ ! -s "$fulldir/$lab.failed" ]; then return 2; fi
      return 0
    }
    bwt="$(mktemp -d)/branch"; basewt="$(mktemp -d)/base"
    git worktree add -q --detach "$bwt" "$branch" 2>/dev/null && WTS+=("$bwt") || bwt=""
    git worktree add -q --detach "$basewt" "$mb" 2>/dev/null && WTS+=("$basewt") || basewt=""
    if [ -z "$bwt" ] || [ -z "$basewt" ]; then
      row "?" "5. не смог поднять папки ветки и общего предка для полного прогона"
    else
      echo "    (строка 5: полный набор на предке ${mb:0:7}, затем на ветке — минуты; журналы /tmp/cc-checkstep-full-{base,branch}.log)"
      failed_tests "$basewt" base; rb=$?
      if [ $rb -ne 0 ]; then
        row "?" "5. не проверялась: на общем предке ${mb:0:7} полный прогон $([ $rb -eq 1 ] && echo 'не собрался' || echo 'прерван или не дал итога') — сравнивать не с чем, журнал /tmp/cc-checkstep-full-base.log"
      else
        failed_tests "$bwt" branch; rr=$?
      fi
      if [ $rb -ne 0 ]; then :
      elif [ $rr -eq 1 ]; then
        row нет "5. на ветке полный набор не собирается (на предке собирался: упало $(wc -l < "$fulldir/base.failed" | tr -d ' ')), журнал /tmp/cc-checkstep-full-branch.log"
      elif [ $rr -ne 0 ]; then
        row "?" "5. не проверялась: прогон на ветке прерван или не дал итога (на предке упало $(wc -l < "$fulldir/base.failed" | tr -d ' ')), журнал /tmp/cc-checkstep-full-branch.log"
      else
        nbase="$(wc -l < "$fulldir/base.failed" | tr -d ' ')"; nbr="$(wc -l < "$fulldir/branch.failed" | tr -d ' ')"
        newred="$(comm -13 "$fulldir/base.failed" "$fulldir/branch.failed")"
        same="$(comm -12 "$fulldir/base.failed" "$fulldir/branch.failed")"
        fixed="$(comm -23 "$fulldir/base.failed" "$fulldir/branch.failed")"
        tail=""
        [ -n "$same" ] && tail="$tail; уже красные на базе: $(printf '%s\n' "$same" | paste -sd',' - | sed 's/,/, /g')"
        [ -n "$fixed" ] && tail="$tail; на ветке починены: $(printf '%s\n' "$fixed" | paste -sd',' - | sed 's/,/, /g')"
        if [ -z "$newred" ]; then
          row да "5. полный набор не краснее базы: упало на базе $nbase, на ветке $nbr, новых 0$tail"
        else
          # Новые красные — ещё раз в одиночку: нестабильный тест (хвост 29б, п. 2) отличается от настоящей поломки.
          alone=""
          while IFS= read -r t; do
            [ -n "$t" ] || continue
            ( cd "$bwt" && xcodebuild test -project LightPlan.xcodeproj -scheme LightPlan-iOS \
                -destination "platform=iOS Simulator,id=$udid" -derivedDataPath /tmp/cc-checkstep-dd-branch \
                -resultBundlePath "$fulldir/alone.xcresult" -only-testing:"$t" ) > "$fulldir/alone.log" 2>&1
            if jq -e '.failedTests == 0 and .passedTests > 0' <(xcrun xcresulttool get test-results summary --path "$fulldir/alone.xcresult" 2>/dev/null) >/dev/null 2>&1
            then alone="$alone [$t: в одиночку проходит — похоже на нестабильный]"
            else alone="$alone [$t: падает и в одиночку]"; fi
            rm -rf "$fulldir/alone.xcresult"
          done <<<"$newred"
          row нет "5. полный набор краснее базы: на базе $nbase, на ветке $nbr, новых упавших $(printf '%s\n' "$newred" | wc -l | tr -d ' '): $(printf '%s\n' "$newred" | paste -sd',' - | sed 's/,/, /g')$alone$tail"
        fi
      fi
    fi
  fi
fi

echo "---"
if [ "$fails" -gt 0 ]; then echo "итог: нет ($fails из 5) — шаг не принят"; exit 1; fi
if [ "$skipped" -gt 0 ]; then echo "итог: «нет» нет, но $skipped строк не проверялось — не «всё да»"; exit 2; fi
echo "итог: да, все пять"
exit 0
