# 30б.3а — lock-screen buttons of the activity screen: probe

Step 30б.3а (2026-10-25, Sonnet 5.5, `wt/30b-3a`). Question for Alexey's phone: **what do the buttons of a Live Activity do from a locked
iPhone — open at once, ask Face ID, or nothing?** The answer cuts 30б.3 (see «What the result decides»).
The spike is an extension of `Spikes/WidgetSpike/` (not the product): app «LP 30b-3a» + widget extension with one new Live Activity
`ProbeLive`. Nothing of it is linked into the real app.

## What was built

- A Live Activity (no push, started from inside the app) with two modes:
  - **Свадьба** — timeline of 4 points (Сборы, Церемония, Прогулка, Банкет) put at *now*, +3, +6, +10 minutes (the real card: 12:00, 14:30, 16:00, 19:00);
    the bar fills by itself (`ProgressView(timerInterval:)`), «до <следующей точки>» counts by itself (`Text(timerInterval:)`).
  - **Студия** — countdown to the end of the rent (now + 15 minutes at start) with the same buttons.
- Three dummy buttons, on the lock screen and in the expanded Dynamic Island:
  1. **Админ** — `Link` to `tel:+70000000000` (a dummy number; the system asks before dialling, nobody is called on purpose).
  2. **+1 час** — `LiveActivityIntent` (`PlusHourIntent`, `authenticationPolicy = .alwaysAllowed`, `openAppWhenRun` off): in the app's process, in the
     background, writes «✓ запрошено +1 час · время · ×N» into the activity state. That line appearing = the intent ran without opening the app.
  3. **Плейлист** — `Link` to `https://music.yandex.ru` (opens another app/browser).
- **Студийный час**: a local notification N minutes after the start (default 2, a stepper in the app). Tap → the app opens, the activity switches to studio mode
  (`ProbeDelegate.didReceive`). Not tapped → nothing switches (by design: the view cannot switch itself, cut doc row 9).
- Opening the app moves the highlighted point to the current one (`ProbeActivity.refresh`, the decision of 25.10).
- In the app: «Запустить активность», «Завершить», the stepper and a journal of the last lines (`probe …` / `notice …`).

## Measured on the simulator (iOS 26.5, `LP wt-30b-3a`, 25.10)

| What | Result | How |
|---|---|---|
| Spike builds (simulator, iphoneos unsigned) | yes / yes | `xcodebuild`, BUILD SUCCEEDED both; the device build was not signed (no App ID spent) |
| App Intent known to the app and to the extension | yes | `PlusHourIntent` in `Metadata.appintents/extract.actionsdata` of both |
| Activity starts, state carries mode / points / next / requests | yes | log `probe start ok … next=1 rentEnd=…` |
| «+1 час» changes the state | yes | log `probe plusHour: requests=1` — **by launch argument, not by a tap on the button** |
| Studio switch changes the state and it survives a relaunch | yes | log `studio via launch arg: mode=studio … requests=1` after `plus` in a separate launch |
| Lock-screen view height | 128 pt (wedding), 147 pt (+ «запрошено»), 79 pt (studio) | the same view drawn in the app at 361 pt wide (`-ProbePreview`, `-ProbePlus`, `-ProbeStudio`); the system's limit ≈ 160 pt is from documentation |
| App name on the home screen | «LP 30b-3a» | screenshot of the permission dialog |

**Not measured on the simulator (the Simulator control was not granted to this thread):** a tap on a lock-screen button, a tap on the notification banner,
the real lock screen and the Dynamic Island pictures. They are exactly what the phone is for. The notification permission dialog is up on the simulator and unanswered.

## App ID budget

The signed build registers **2 new App IDs**: `Novopashin.LightPlan.spike30b` and `Novopashin.LightPlan.spike30b.Widget` (and the group
`group.Novopashin.LightPlan.spike30b`, which is not an App ID). The limit is 10 new App IDs per 7 days. Known registrations of the last week from the
records (not seen in Apple's account): `Novopashin.LightPlan.Widget` and `slotA.Widget` on 25.10 → this makes **4 of 10**, if nothing else registered
that I do not know about. The spike ids stay forever (Apple does not delete free-team ids) and are reusable for later probes.
Apps on the phone after the install: «Light Plan», «LP music», «LP 30b-3a» = 3 (the «3 apps per device» free-team limit from the cut doc did not bite
Xcode installs before, 22–23.10: main + three slots).

Alternative that was rejected: the spike under a free pool slot id (`slotB`): costs 1 new id (`slotB.Widget`), but that one is needed later anyway;
it ties the spike to the pool record `~/.light_plan_phone.tsv` and the next install into slotB silently replaces it. The own ids keep the pool clean.

## Install (only on Alexey's word)

```
LP_SPIKE_PHONE=yes Spikes/WidgetSpike/probe.sh phone      # from the step's worktree; phone cable-connected and unlocked
```
Signed build with `-allowProvisioningUpdates` (registers the 2 ids), `devicectl install`, launch. Uninstall after the measure:
`xcrun devicectl device uninstall app --device 5A94DA8F-B9E0-5DB8-BECF-14F387CFE24F Novopashin.LightPlan.spike30b`.

## Памятка Алексею

На телефоне — значок **«LP 30b-3a»**. Это пробный экран; в нём всё нарочно сырое. Нужно нажать кнопки с **заблокированного** телефона и сказать, что
произошло. Телефон не должен быть с включённым «Не беспокоить».

**Подготовка (1 минута).**
1. Открой «LP 30b-3a». Выбери «Студийный час через 2 мин» (оставь как есть).
2. Нажми «Запустить активность». Телефон спросит два разрешения — **разреши оба** («Эфир активности» и «Уведомления»). Если спросит позже —
   тоже разреши.
3. Сразу заблокируй телефон боковой кнопкой и разбуди (не разблокируй, не смотри в лицо — кнопкой или касанием экрана). На экране блокировки появится
   плашка: сверху «до Церемония» и отсчёт, ниже полоса с четырьмя точками, внизу три кнопки: «Админ», «+1 час», «Плейлист».

**Что нажать (телефон заблокирован, Face ID не пускай — не смотри на него, пока не нажмёшь).** После каждой кнопки запиши в таблицу, что случилось:
открылось сразу / спросило Face ID (или код) / ничего не произошло. Если спросило — после разблокировки скажи, что открылось.
1. **«+1 час»**. Смотри на плашку 2–3 секунды, телефон не разблокируй. Должна появиться строка «✓ запрошено +1 час · время · ×1». Это главная проверка:
   работает ли кнопка без Face ID и без открытия приложения. Нажми ещё раз — должно стать «×2».
2. **«Админ»**. Телефон может спросить «Позвонить?» — **нажми «Отмена»**. Запиши, спросил ли он сперва Face ID.
3. **«Плейлист»**. Должна открыться Яндекс Музыка или сайт. Запиши, спросил ли Face ID.
4. Заблокируй телефон снова и повтори три кнопки ещё раз, если что-то не понял (первый раз Face ID может «запомниться»).

**Потом то же самое с разблокированным телефоном** (экран открыт, приложение «LP 30b-3a» закрыто или на заднем плане):
- нажми и **удерживай остров** (Dynamic Island) — он раскроется; запиши, видны ли там три кнопки и работают ли;
- плашка с таймлайном на разблокированном телефоне видна, если потянуть центр уведомлений вниз; нажми там те же кнопки.

**Полоса и отсчёт сами.** Заблокируй телефон на 1–2 минуты и посмотри: полоса сдвинулась? Отсчёт «до …» идёт? (Таймлайн — 10 минут: точки в «сейчас», +3, +6, +10.)
Когда отсчёт дойдёт до 0:00, надпись «до Церемония» сама не сменится на «до Прогулка» — это известное ограничение, оно нам и нужно подтвердить;
откроешь приложение — подсветка и надпись переключатся.

**Уведомление «Студийный час».** Через 2 минуты после старта придёт уведомление. Телефон заблокирован — **нажми на него**:
- спросило Face ID? открылось приложение?
- потом заблокируй телефон снова: заголовок плашки должен стать «Студия · аренда до …» с отсчётом аренды (15 минут от старта), таймлайн пропадает;
- (если не нажимать на уведомление, плашка сама не переключится — это тоже ответ).

**Конец.** «Завершить» в приложении убирает плашку. В журнале внизу приложения строки `probe plusHour …` показывают, что «+1 час» действительно выполнялся
(с временем): сверь число нажатий.

### Результаты (заполняет оркестратор или следующий тред по словам Алексея)

Кнопки с заблокированного экрана:

| Кнопка | Заблокирован: открылось без Face ID / спросило Face ID / не сработало | Разблокирован (плашка или остров): работает / нет |
|---|---|---|
| Админ (`tel:`) | | |
| +1 час (фоновое действие) | | |
| Плейлист (ссылка) | | |
| Уведомление «Студийный час» (нажатие) | | — |

Остальное:

| Вопрос | Да / нет | Заметка |
|---|---|---|
| Полоса идёт сама (заблокирован) | | |
| Отсчёт «до …» идёт сам | | |
| После 0:00 надпись «до …» сама не сменилась (ожидаемо) | | |
| Нажатие на уведомление переключило плашку на «Студия» | | |
| Плашка сама не переключилась без нажатия (ожидаемо) | | |
| «+1 час» поменял вид (строка «✓ запрошено») без открытия приложения | | |
| Нажатий «+1 час» в плашке = число в журнале приложения | | |
| Плашка уместилась целиком, ничего не обрезано | | |
| Что видно в Dynamic Island (компактно, раскрыто; кнопки внутри) | | |
| Разрешения «Эфир активности» и «Уведомления» спросили один раз | | |

## What the result decides (for the cut of 30б.3)

- **«+1 час» works locked without Face ID and the line appears** → «+1 час» can be a real background request (to BroniOS later) — the lock-screen control
  stays as Alexey drew it; a confirmation line in the activity.
- **«+1 час» asks Face ID** → the button stays but the cut says so: one unlock per press; or move «+1 час» into the app.
- **«Админ» / «Плейлист» ask Face ID** (expected by documentation) → they are «открыть с подтверждением»; the call/playlist stay as links, no workaround.
- **Notification tap does not switch the mode** (or the app does not get the response) → studio mode comes only from opening the app; the notification
  just opens it.
- If the bar or countdown froze when locked → the timeline stays a snapshot refreshed on app open (the 25.10 decision already assumes the label lags).
