# 30б — widget of the day and Dynamic Island: probe and cut (step 0)

Measured 2026-10-24 on Xcode 27.1, simulator iOS 26.5 (iPhone 17 Pro Max model, own simulator
`LP wt-30b-probe`), free team `4A3PUKS9R9`. Spike: `Spikes/WidgetSpike/` — app + WidgetKit extension,
project written by `make_project.py` (`--check` proves the committed pbxproj repeats), scenarios in
`probe.sh` (`sim`, `device`, `log`). The spike registered **nothing** with Apple: no
`-allowProvisioningUpdates` anywhere. **App IDs spent: 0.** Screenshots: shared notes folder
`30b_shots/` (outside the repo).

Alexey's word (DECISIONS 29.09, «Б. Вынести отдельной итерацией сразу после 30»): widget of the day and
Dynamic Island with the golden-hour countdown, no Watch (Watch stays in 36).

## Measured

| # | Question | Answer | How |
|---|---|---|---|
| 1 | Widget extension signs and installs on the simulator, free team | **yes** | `probe.sh sim`: BUILD SUCCEEDED, `simctl install` ok. Simulator signing is «Sign to Run Locally» (ad hoc), entitlements go into `*-Simulated.xcent` — no profile, no registration |
| 2 | Same for a device | **compiles yes; signing needs 2 new profiles, not spent** | `probe.sh device`: unsigned iphoneos build SUCCEEDED; signed build without registration → `No profiles for 'Novopashin.LightPlan.spike30b' were found` and the same for `….spike30b.Widget`. Every extension bundle id = its own App ID |
| 3 | App Group shared folder app → widget | **yes (simulator)** | app wrote `feed.json` (79 B) into `group.<id>`; the widget process logged `read=Томск 20:55` from it. Device: the 19.09 probe got a group into a free-team profile (`Novopashin.LightPlan.probe`); the 5 current profiles (main, slotA–D) carry **no** group yet |
| 4 | Live Activity start / update / end locally, no push | **yes (simulator)** | `Activity.request(…, pushType: nil)` → ok; lock screen and Dynamic Island show it; `update` and `end` work. No entitlement needed, only `NSSupportsLiveActivities` in the app's Info.plist |
| 5 | Countdown without updates | **yes** | `Text(timerInterval:countsDown:)` ticked by itself: 1:35 → 1:22 → 1:14 on three screenshots, no update sent. Dim lock screen shows `1:––` (seconds hidden) |
| 6 | First Live Activity asks the person | **yes** | lock screen: «Разрешить Эфир активности для приложения «Spike30b»?» — Не разрешать / Разрешить |
| 7 | Start a Live Activity while the app is in the background | **no** | `bgstart`: app in background (`applicationState` 2) with a background task → `LA bg request FAILED visibility`. Push-to-start needs Push — not on the free team (19.09) |
| 8 | Update while in the background | **only while the app still has time** | `bgupdate`: 5 updates over 30 s from the background, all applied (`active`); rerun by `probe.sh sim`: 6 over 31 s, the last one right as the background task expired; then the app is suspended. `BGAppRefreshTask` wake-ups are not measurable on the simulator (30.6) |
| 9 | `staleDate` switches the view by itself (before → during golden hour) | **no (simulator, 35 s)** | `-LA phase` (by hand: launch with it, send the app home, screenshot): staleDate = start + 20 s; 35 s later the island still showed the pre-stale view frozen at `0:00` |
| 10 | Extension links our Foundation-only packages and computes light itself | **yes** | widget links LightPlanCore + LightPlanDomain; `SolarDay` in the extension 592 µs cold, 4–16 µs warm (Debug); Tomsk 24.10 golden hour 17:02:48–18:22:03 (+7), next two days in the same timeline |
| 11 | App tells the widget to redraw | **yes, at once** | `WidgetCenter.reloadAllTimelines()` at app launch → widget `timeline` lines in the same second |
| 12 | One id drives app, extension and group | **yes** | `LP_SPIKE_ID=Novopashin.LightPlan.slotD` on the command line → app `…slotD`, extension `…slotD.Widget`, group `group.Novopashin.LightPlan.slotD` |
| 13 | Extension size | 4.7 MB Debug iphoneos (4.6 MB of it the debug dylib) | `du`. Release not measured. Core's resource bundle (`eclipses.json`) is copied into the extension too (8 KB) |

**A trap found in the code (from code, not measured on the real project):** `Tools/phone.sh` passes
`PRODUCT_BUNDLE_IDENTIFIER=` and `INFOPLIST_KEY_CFBundleDisplayName=` on the xcodebuild command line.
Command-line settings apply to **every** target, so the extension would get the app's own id and the
install would fail. 30б.1 replaces them with `LP_APP_ID` / `LP_APP_NAME` (measured in row 12 with
`LP_SPIKE_ID`).

Not measured (and why): device install (rule: stop before spending App IDs); memory of the widget
process on a phone (the simulator has no extension memory limit; Apple's limit ≈ 30 MB — from
documentation); Live Activity 8-hour limit (documentation); whether the free team limits App Group
registrations; the «3 apps per device» limit reported for free accounts — the phone record
(`~/.light_plan_phone.tsv`) shows main + three slots installed together on 22–23.10, so it did not bite
Xcode installs; whether an extension counts towards it is unknown.

## App ID budget

The real app needs **5 new App IDs, once**: `Novopashin.LightPlan.Widget` and
`Novopashin.LightPlan.slotA…D.Widget`. Each is registered by automatic signing at the first phone
install of that app after the extension lands (`phone.sh` already passes `-allowProvisioningUpdates`).
The App Group capability is added to the 5 existing App IDs (a change, not a new ID) — from code, not
measured on a device. Weekly cap 10. Week of 30б.1: main + the step's slot = 2; the other slots pay
1 each when next used. Never more than 5: slots are permanent ids (the pool rule of 12.10 holds).

## Data: how the widget knows what to show without the network

- The widget **computes light itself** (row 10): `SolarDay(date:place:)` (`.iau`) per day in the
  extension, so a timeline can run days ahead with the app closed.
- What it cannot compute, the app writes: one small file `widget.json` in the group container —
  the place «Свет» shows (name, lat, lon, zone) and the shoots of the next 7 days (id, start/end,
  genre label, place). Written on `persist()` and on a place change, followed by
  `reloadAllTimelines()`. Rule + format in Domain (Foundation only, unit-tested), so the app and the
  extension share it.
- `light-plan.json` stays where it is (`Application Support/LightPlan/`). Moving the main store into
  the group would move Alexey's real data — not needed for a read-only widget.
- Weather: the widget gets none by itself (no network in the plan); a saved last forecast could ride in
  `widget.json` later — not in this cut.

## What 30б takes without App Intents (35а)

Takes: static widgets (`StaticConfiguration`), a tap opens the app at the right day/card through the
existing `lightplan://` scheme (`widgetURL` / `Link`), Live Activity started from inside the app.
Leaves to 35а/36 (all need App Intents): buttons inside a widget or a Live Activity, starting a Live
Activity from a widget button (`LiveActivityIntent`), Siri / Shortcuts. A widget where the person picks
a place needs only a `WidgetConfigurationIntent`, not 35а's entities — can be added later if asked.

## The cut

Model for every step: Sonnet 5.5 (plan); Opus only where the store/zone logic argues with Domain.

**30б.1 — Extension skeleton and addresses.** Size **M**.
Goal: the extension target lives in the project and installs into main and every slot without
breaking the pool. Alexey adds the target (clicks below); the agent: `Config/Widget.xcconfig`,
`LP_APP_ID` / `LP_APP_NAME` in `Shared.xcconfig`, `iOS.xcconfig` and `phone.sh` (app id
`$(LP_APP_ID)`, extension `$(LP_APP_ID).Widget`, group `group.$(LP_APP_ID)`), entitlements files for
both, `check_app_icon.sh` / `check_phone_id.sh` keep reading the app's id, a placeholder widget
«☀︎ <start of golden hour today>» at the «Свет» place computed in the extension.
Done when: simulator build + full test set green (`checkstep --type код --tests --full`); the widget
shows in the simulator gallery for main id and for a slot id; `make phone ARGS="install"` of the branch
puts «LP 30b-1» with the widget on the phone (spends 1 App ID: `slotX.Widget`) — on Alexey's word only.

**30б.2 — Widget of the day.** Size **M**.
Goal: what Alexey picks in Q1–Q3 below. `WidgetFeed` (Domain, pure: next shoots, empty day, polar day
without golden hour, other zone), written by the app, read by the widget; small (+ medium, + Lock
Screen per answers); tap → day or card. Slot widgets carry the brass «α» like the slot icon (decided:
trivial, reversible — two widgets on one home screen must be told apart).
Done when: feed unit tests; widget views rendered in tests by numbers (sizes, no clipping in 3 text
sizes); phone check by Alexey.

**30б.3 — Golden-hour countdown in Dynamic Island.** Size **M**.
Goal: Live Activity per Q4–Q5. Island compact / expanded / minimal + lock screen. Because the view
cannot switch by itself (row 9), «until start» and «until end» are two timers side by side, each
counting only in its own window; the app ends the activity when it runs, otherwise the system removes
it (8 h limit — documentation). Start rule per Q4 (cannot start with the app closed — row 7).
Done when: simulator screenshots of all four presentations by numbers; the start rule unit-tested;
Alexey sees it on a shoot day.

Optional, only if Alexey wants a ring: **30б.4 — «за N минут до золотого часа» alarm** through
AlarmKit (iOS 26): the system shows its own countdown in Dynamic Island with the app closed and rings
at the end. From documentation, not measured; the free team and AlarmKit permission untested. Size S
probe + S.

## Xcode clicks for Alexey (start of 30б.1, in the step's worktree)

The agent first commits `Config/Widget.xcconfig` and the two entitlements files in the branch, then:

1. Open `LightPlan.xcodeproj` of the step's folder. **File → New → Target…** → iOS → **Widget
   Extension** → Next.
2. Product Name **`LightPlanWidget`**; Team: your personal team; **Include Live Activity — on**;
   Include Control — off; Include Configuration App Intent — off; Project: LightPlan; **Embed in
   Application: LightPlan-iOS** → Finish. «Activate “LightPlanWidgetExtension” scheme?» → **Cancel**
   (stay on LightPlan-iOS).
3. Select target **LightPlanWidgetExtension** → General → **Frameworks and Libraries → +** → add
   **LightPlanCore** and **LightPlanDomain** (not LightPlanUI: it brings the map and is far too big for a
   widget — from code, not measured).
4. Project **LightPlan** (blue icon) → Info → Configurations → open **Debug** → in the row
   LightPlanWidgetExtension pick **Widget**; the same under **Release**.
5. Close Xcode, tell the agent. The agent removes the template's own target settings (bundle id,
   Info.plist keys, versions) from the two configuration blocks of the new target only, so
   `Widget.xcconfig` rules as everywhere else (settings, not structure), and replaces the template
   Swift files in `LightPlanWidget/`.

No capability clicks: the entitlements files carry `group.$(LP_APP_ID)`, automatic signing registers
the group on the first device build (from code, not measured on a device). The template's new scheme
can stay; nothing else changes in the macOS target.

## Questions for Alexey (product)

**Q1. What the small widget shows.**
- A) The next shoot: day, time, genre, and the golden hour at that place on that day. With no shoots
  ahead — empty plate. Pro: the plan at a glance. Con: useless on free days.
- B) Today's golden hour where you are: start, end, countdown. Pro: always useful, also for personal
  shooting. Con: knows nothing about shoots.
- C) Shoot today or tomorrow → the shoot and its light; otherwise → today's light here. Pro: both.
  Con: the plate changes its look from day to day.
- My pick: **C** — a free day still gets a reason to look.

**Q2. Medium widget.** A) today's light + the next 2 shoots in a list; B) a week strip: 7 days, a dot
per shoot, golden-hour time under each day; C) no medium widget for now. My pick: **A** — closest to
the day strip you already read.

**Q3. Lock Screen widget (a line under the clock).** A) yes, «☀︎ 17:02 · съёмка 15:00», genre instead
of client names (seen on a locked phone); B) yes, with the client's name; C) no. My pick: **A**.

**Q4. When the Dynamic Island countdown starts.** (Measured: it cannot start while the app is closed.)
- A) By itself when you open the app on a shoot day within 3 hours before golden hour. Pro: no
  button. Con: if you don't open the app that day, nothing appears.
- B) By a button «Отсчёт до золотого часа» on the shoot card and on «Свет». Pro: always on purpose,
  also on free days. Con: one more button.
- C) Both. My pick: **C**.

**Q5. What it counts down.** A) to the start of golden hour, then to its end (two numbers, row 9);
B) to the shoot's start; C) to sunset. My pick: **A**.

The first Live Activity triggers the system question «Разрешить Эфир активности…» (row 6) — no
choice for us, only where it appears: right after the first start.
