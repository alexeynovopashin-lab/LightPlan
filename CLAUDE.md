# native — Light Plan in Swift

**Reply to Alexey in Russian.** This file is English (tokens). Workspace rules
(`ws:CLAUDE.md`) apply; this file adds to them.

## Where things are

- **Read first, after `git log`:** `light_plan:Light_Plan/docs/NEXT_SESSION.md` —
  what runs now, what the roadmap chat decided for upcoming iterations, open
  threads. Short; the roadmap chat rewrites it after every iteration report.
- Architecture: `light_plan:Light_Plan/docs/17_NATIVE_ARCHITECTURE.md`.
  Plan by iterations: `light_plan:Light_Plan/SWIFT_MIGRATION_PLAN.md` — do only
  the iteration you were asked for; every iteration ends with a commit named in
  its «Checkpoint».
- Product decisions: `light_plan:Light_Plan/DECISIONS.md` (append-only; native
  decisions go there too). The web PWA in `light_plan:Light_Plan/` is the
  parity reference; don't edit it from here.
- Git: remote `origin` = `git@github.com:alexeynovopashin-lab/LightPlan.git`,
  **public**, created by Alexey 2026-09-20. It is a different repo from the
  web's `Light-Plan` — the two histories stay separate on purpose. Push after
  each iteration's checkpoint; no secrets in this tree, keep it that way.
- **Session size.** Every reply re-reads the whole context, so cost grows
  faster than length (19б: 650–670K, compact, +400K ≈ 25 % of the weekly
  limit). Near **300K** write an interim result into the plan («сделано /
  осталось / где остановился») and `SESSIONS_CHAT.md`, then tell Alexey to
  continue in a fresh chat — don't grow to 600K, don't re-compact. Compare
  shots by `make shots` numbers; put an image into context only where the
  numbers disagree. Measured iterations record the weekly % before/after and
  peak context (`get_usage`).
- **Hand over only committed work** (Alexey, 2026-09-24). An iteration works
  in its own worktree (`.claude/worktrees/<task>`, branch `wt/<task>`), never
  uncommitted in the main folder. Before handing over, commit the work in
  progress to that branch (`wip:` title, tests may be red — say so in the
  body); the next chat continues the branch. Merge into `main` at the
  checkpoint only. Two iterations in parallel each keep their own branch.

## Layout and rules

- `App-iOS/`, `App-macOS/` — thin targets, synchronized folders: a new file
  there needs no pbxproj edit. `Packages/LightPlan{Core,Domain,Timeline,Data,UI}`
  — SPM packages. `Config/*.xcconfig` — **all build settings live here**, not in
  the pbxproj or Xcode's settings UI. `Spikes/`, `Tools/`.
- Layers: `Core ← Domain ← Data`, `Core ← Timeline`, `UI` depends on all.
  Core/Domain/Timeline import only Foundation. SwiftPM enforces the direction
  between packages, but NOT system frameworks (`import SwiftUI` compiles in
  Core — measured). `Tools/check_boundaries.sh` enforces them; it runs as a
  build phase of both apps. Rules are in its two functions.
  Drawn glass shine (`glassShine`) is allowed outside `Timebar/` only in `Screens/Planner/PlannerMonthView.swift` (month plate; Alexey, DECISIONS 03.10), held by `Tools/check_glass.sh`.
- Structure changes to `LightPlan.xcodeproj` (targets, phases, package refs):
  propose in text, Alexey does them in Xcode. Never read the pbxproj in full.
- Devices: first priority is regular iPhones, 14 through 17 Pro Max, portrait
  (`TARGETED_DEVICE_FAMILY = 1`). Landscape versions for iPadOS and iPhone Duo
  come later: Alexey has no real iPad or Duo and no mockups exist; his hint is
  the landscape iOS Calendar (day timeline left, event card right). Duo also
  waits for the next stable Xcode. Start neither, don't guess their sizes
  (Alexey, 2026-09-19; DECISIONS «Устройства…»).
- **Screen layers close by edge swipe (28з).** A new layer over the tabs (anything with a «Назад»/✕ that is not
  system navigation) needs one line: `.edgeBack(app, z: BackZ.<name>) { <plain state change, no animation> }`
  next to its `.zIndex` (heights live in `BackZ`, `App/EdgeBack.swift`). One `UIScreenEdgePanGestureRecognizer`
  on the window (`EdgeBackHost`) moves the top registered layer; sheets, alerts and full-screen photo viewers
  (`edgeBackBlocked`) refuse it. Settings' `NavigationStack` keeps the system gesture — don't register it.
  Measure with `-LPEdgeBackLog <file>` (Debug): begin / end dx v / closed / `gate no` lines, and per gesture one
  `meter` line (CADisplayLink frames missed / p95 + main-thread CPU ms per frame + `body` re-evaluations, `App/EdgeBackMeter.swift`).
  `node Tools/edge_back_bench.js --app <.app>` drives all 18 layer screens without a finger (table: frames, missed, p95, CPU);
  `--shade` compares a layer at rest with its first gesture frame pixel by pixel. **In the simulator trust CPU ms, not frame
  intervals**: ~60 % of a late frame there is the main thread sleeping on the sim's renderer (`wait_image_queue`).
  Layer shadow is a 20 pt gradient strip left of the edge (`EdgeShade`), never `.shadow` on the content (that shades every
  child). Only the visible tab moves under a layer (`.edgeBackBase(app, .tabs, shown:)`): moving all four cost ~9 ms/frame.
- **Who took a touch (29.4).** `-LPMapGestureLog <file>` (Debug, `App/TouchWitness.swift`): a passive recognizer on the
  window writes one line per touch — where the fingers landed (view), which recognizers began/ended, which stayed quiet,
  and the «Карта» state before/after (zoom, centre, bare, fold, name bar, rotor). Drive it with `touch_path` /
  `touch2_path` one call at a time (calls sent together overlap). Anything hit-testable drawn over the map canvas eats
  pan and pinch that start on it: taps on map things come from the canvas (`onTap`) and are hit-tested in code
  (`MapSpots.hit`, `MapInstrumentView.bodyAt`).
- **One sky time for AR (29.8в.21).** Every AR layer (Sun `SunTrack`, Moon `MoonTrack`/`MoonSample(time: .iau)`, planets, stars,
  constellations, Milky Way band/core/frame) goes through `SkyFrame` (`Sky/SiderealTime.swift`): IAU sidereal time, J2000 catalog
  points precessed to the date (`horizontal(j2000:)`), Sun/Moon/planets already of date (`horizontal(ofDate:)`). Sun and Moon use
  `Sky/SunMoonTheory.swift` (Meeus ch. 25 / 47), ≤ 0.02° vs Horizons. The AR Moon is topocentric (29.8в.23: `horizontal(ofDate:distanceKm:)`, Meeus ch. 40 parallax up to 0.95°, ≤ 0.013° vs Horizons topocentric); Sun and planets take no parallax (< 9″). `Sky.horizontal`, `SolarDay`, and `MoonSample`/`MilkyWay.corePosition`
  with the default `time: .web` keep the web's numbers for parity (Map instrument sky, dome constellations, Moon on the Light screen).
  A new AR layer must not call `Sky.horizontal`. Reference: `python3 Tools/sky_time_ref.py` → `Fixtures/sky_time_horizons.json`, read by `SkyTimeTests`.
- **Exact Sun on every screen (29.8в.25).** `SolarDay(date:place:)` (and `MilkyWayWindow`/`MoonVsStars(date:place:)`, `WeatherDay.buildDays(time: .iau)`,
  `AstroNight(time: .iau)`) default to `.iau`: the AR Sun (`Solar/ExactSun.swift`: Meeus ch. 25 + IAU sidereal time, 3 theory evaluations per day,
  parabola in between), ≤ 0.01° and ≤ 0.12 min vs Horizons (Tromsø polar edge ≤ 0.54 min), 11 µs per day. The bench init
  `SolarDay(date:latitude:longitude:utcOffsetHours:)` stays `.web` (NOAA port, bit-for-bit; parity tolerances 1e-6 min / 1e-9°). **The screens now
  show a Sun more exact than the web's — by design they no longer equal it** (web: up to 0.55° / 5 min / 23 min at Tromsø). Reference:
  `python3 Tools/sun_horizons_ref.py` → `Fixtures/sun_horizons.json`, read by `SolarDayExactTests`; a web-parity test that feeds a screen
  component passes `time: .web` (e.g. `MapSceneParityTests`). Not yet moved: Moon and planets on Light/Map/dome (`.web` sidereal time).
- **Glass never takes a rotation (28п).** `.glassEffect` under `rotationEffect` (or `scaleEffect`) swells into the
  bounding rectangle of the whole layer at angles that are not multiples of 90° (measured: three spot plates → one
  ≈ 420 × 415 pt slab). On «Карта» the rotor is two halves with the same angle (canvas, veil, road / instrument)
  and the spots layer (pins, name plates, route numbers) sits between them, **not rotated**: each mark is placed at
  `MapSpots.screenTip` and stays upright. A new glass element near the rotor goes outside both halves.
  `node Tools/rotor.js --spots --bare --angles 0,45,…,33 --motion 4` measures plate size and place per angle (red on a swell).
- **Calendar mirror (30.1–4).** Shoots, meetings and blocks → the iPhone Calendar; since 30.4 time/place and hand-made events come back (see the 30.4 paragraph below). 30.1–3: one way (`LightPlanData/Calendar/`:
  `CalendarPlan` records → events, `CalendarMirror` actor reconciles, `EventKitCalendarStore` is the only EventKit user,
  `InMemoryCalendarStore` is the fake for tests/shots; UI side `AppModel+CalendarMirror`, Settings «Съёмки» →
  `CalendarMirrorSection`). **Full Calendar access, not write-only** — measured on iOS 26.5 (`Tools/calendar_probe/README.md`):
  write-only gives one virtual calendar, no `saveCalendar`, and a saved event cannot be found again to update or delete.
  Link record↔event = `lightplan://shoot/<id>` inside the event (truth) + a device-local hint in `UserDefaults`
  (`CalendarMirrorRecord`), never in the snapshot. Real EventKit check: `python3 Tools/calendar_sim.py --app <.app>`
  (the app walks `-LPCalendarProbe <file>`; `--selftest` checks the checker).
- **Calendar both ways (30.4).** Alexey: the calendar is personal → client phones + shoot notes go into the event (`CalendarNotes`: international
  phones, no money/docs). Back from the Calendar: **time and place of a shoot/meeting** (`CalendarPlan.applying`; not titles/notes — those snap back) and
  **events made by hand in the «Light Plan» calendar → draft shoots** (`Session.fromCalendar`, key `calTitle`; draft = `fromCalendar` + no genre + no client;
  `kind == .shoot`; planner shows «Черновик» via `PlannerWords`). Who moved, decided by `CalendarMirrorRecord.facts` (device-local fingerprint of time/place at the last
  meeting of both sides): event off the fingerprint, record on it → event wins; both moved → later `mt` / `lastModifiedDate` wins; no fingerprint → record wins. The mirror
  only *reports* (`Report.incoming`); `AppModel.takeCalendarIncoming` applies, stamps `mt`, flushes to disk, and only then `adopt`s the event (links it to the new record).
  All-day-event drafts, recurring and >24 h events are left alone. **Busy-time blocks come back too** (`applying(_:to: Block)`; all-day compared by days). A move
  accepted from the Calendar sets the same «Время сдвинуто в календаре: было → стало» mark as a finger drag (`DayDrag.commit(day:)`, now also keeps the old day in
  `DayMoved.day`; card plate + ✕); blocks keep `Block.movedFrom` (key `mvd`), shown as the third line of the day row and a plate in the block sheet (`blockMovedText`).
  **No «Фотосъёмка» genre code in data** (the web would show the raw code: `genreName` falls back to the code, no icon, not in pickers): a shoot with `genre == nil`
  is *labelled* «Фотосъёмка» (`PlannerWords`, key `genre.photoshoot`), rules are the web's empty-genre ones (people group, 7 days); `EventForm.genreUnset` keeps nil on save. Zones: `learnCalendarZones` asks the geocoder for unknown 0.5° cells before a pass
  (≤ 6 per pass, once per launch each), so Tomsk is +7 not the longitude estimate +6 once online. `-LPCalendarProbe` drives the whole thing on real EventKit
  (`calendar_sim.py`: hand move / rename / hand-added draft / reinstall / draft event deleted).
- **Other calendars as ghosts (30.5).** Events of the phone's other calendars (work, kids, matches) show on the day strip and the week
  (not the month) as dashed ink-coloured read-only blocks; tap on the day lane → info-only `GhostSheet` (no action; «Занять» was removed in 30.5c on Alexey's word). Week: rows expand
  inline («Ещё N ⌄» / «Свернуть ⌃», per day, memory only), no sheet; a day with ghosts is not labelled «свободно». Code: `LightPlanData/Calendar/GhostCalendars.swift` (policy, reader actor with cache, `GhostDay`, `GhostOverlap`), UI `Screens/Planner/PlannerGhosts.swift` (`GhostRail`, `GhostBlock`, all-day band, week rows, sheet),
  `App/AppModel+Ghosts.swift`. **Default is one constant:** `GhostPolicy.ghostCalendarsDefault = .allPersonal | .none` (shipped
  `.allPersonal`); the person's own ticks live apart (`GhostRecord.picks`, UserDefaults, not in the mirror record — mirror-off wipes
  that one) and beat either default. Personal = EKCalendarType local/calDAV/exchange; subscription + birthday are listed but off
  by default; «Light Plan» (by mirror id and by title) never listed. Google-account holiday calendars arrive as ordinary calDAV —
  the person unticks them. Ghosts live in `AppModel.ghostList` only (memory): never in `snapshot`, never written to the Calendar.
  Privacy: only title, time, place, calendar name are read (`Ghost.make`); no notes/attendees/URLs; titles are never logged.
  Declined invites (the phone owner's own attendee status, `GhostEvent.declined`) and cancelled events are not ghosts (30.5b); tentative/pending/
  accepted/no-invite show. The simulator calendar cannot represent attendee status (EKParticipant is not creatable) — covered by the fake store only.
  All calendar settings live in the Settings chapter «Календарь» (`SettingsView.Chapter.calendar`, right after «Съёмки»; `Chapter.parts` states its
  content: `CalendarMirrorSection` + dimmed `.ics` import) — 30.5d; «Съёмки» and «Данные» no longer hold them.
  Reading needs full access: «Другие календари» switch asks with a plain explanation first (`ghostAsk`), then the system prompt;
  denied earlier → row leads to iPhone Settings. Strip layout: ghosts get their own right rail ≤ 40 % of the lane after the 70 pt
  hour column, columns ≥ 56 pt (`GhostRail.capacity`: 2 on 393 pt, 1 on 320 pt); shoots narrow by the rail width **only on days with
  ghosts**; a cluster with more columns than fit collapses into one «+N» block. Form: soft amber note between the clash and weather
  notes (`formGhostWarning`, compares moments, not wall clocks). Real EventKit check: `calendar_sim.py` stages `ghost-*`
  (second calendars «Сын»/«Работа», recurring, all-day, night, change notification).
- **Forecast changed (30.6).** One rule, two channels, one memory: `WeatherWatch.pass` (Domain; web `wxAnnounce`) over the shoots
  `AppModel.weatherWatched()` returns; banner on launch (1.5 s) and return (≥ 30 min between network passes) via `NoticeQueue` (cap 2,
  «И ещё N») and `NoticeBanner`; local notification from `BGAppRefreshTask` (`WeatherRefreshTask`, id in `Config/Info-iOS.plist`, mode
  `fetch` — no entitlement, signs on the free team), one per shoot, `wxTold` written only for what the system accepted (`WeatherMemory`).
  The BG handler uses the same model as the screens (`AppModel.sharedLive`) — a second writer would overwrite `wxTold`. Simulator never
  wakes the task (`submit` fails; lldb `_simulateLaunchForTaskWithIdentifier` runs but calls nothing): Debug `-LPWxBgRun 1` runs the handler
  on going home instead; `-LPWxLog <file>` logs each pass, schedule result and delivered notifications. Seed a change by editing `wxSeen`
  in the sim's `light-plan.json`.
- **Private clients (К1).** `Snapshot.clients` (`Client`, `LightPlanDomain/Records/Client.swift`: `id` `c…`, `kind` couple/family/person, `people[]`, `mt`) +
  `Session.clientId`, same `light-plan.json`, same `persist()`; web does not know the section and drops it on re-save (the pass below rebuilds it). Glue by
  phone number lives in `ClientBook.bind` (Domain, rules of `docs/clients_reference.md` § 3): called by `saveForm` before repeat copies are made
  (`AppModel.bindClient`); the one-time pass over saved shoots is `AppModel.assembleClients` (`live()` on start, `Snapshot.clientsAssembled`; a shoot whose
  `clientId` points at a missing client is bound again). A client without a number is created but never glued by name. Genre → kind table in `ClientBook.kind(for:)`;
  org-only shoots, meetings, landscape/street make no client. Own number never becomes a client (`myKeys`). The screen is the layer `ClientsScreen`
  (`Screens/Org/`, z `BackZ.orgList`): tabs «Частные | Компании», «Компании» = the old `OrgListScreen` unchanged (node `org.list` kept for the web pair);
  `openOrgs()` opens that layer on «Компании», `openClients()` on «Частные». Settings chapter `Chapter.clients` (`opensLayer`) stands after «Календарь»; «Организации» left
  «Хранилище» (`Chapter.parts`). Check: `node Tools/shots/clients.js`
  (native only: tabs vs «Назад», fields 24, row 64, kinds add up to «Все»; К2 adds the card shots below).
- **Client card (К2).** A row of «Частные» opens `ClientCardScreen` (`Screens/Org/`, layer z `BackZ.clientCard`, state in `OrgState.clientCardId`,
  `AppModel+ClientCard.swift`); edits write at once, like the org card. Kind segment, people (name, phone with a call button), own links + links
  of the client's shoots, shoots and sums — **computed** (`ClientBook.shoots`/`line`/`shootLinks`), never stored. Rules in `ClientCard.swift` (Domain):
  `merge` (the open card stays, the picked one is poured in: its live and trashed shoots move, same number = one person, filled fields win, kind
  of the target; graves the source), `delete` (shoots stay, `clientId` dropped, as `OrgBook.detach`), `twins` («номер есть у клиента …» plate, § 3.4),
  `keeps`/`isBlank` (a blank client without shoots is not kept; «+ Клиент» is a draft until a word is written, like «+ Организация»). A phone changed in
  the card goes to the client's `telLog` on «Назад»/background (`commitClientTels`); `bind` checks the client's own archived number **before** «номер
  сменился», so re-saving an old shoot never rolls the card's number back. **Check mark (Поле-1 п.6):** after the first real write (`editClient` that changed data or turned a draft into a client, a merge, a contact fill — `OrgState.clientEdited`, reset on open)
  a ✓ stands top right (`clc.done`); tap = `doneClientCard()` = «Назад» + a 1.4 s «Сохранено» sign (`SavedSign`, over the layers; Debug `-LPSavedSignHold`). Edits still write at once; an edit that
  changes nothing or a blank draft shows no ✓. Shots: `-LPShotSheet clientcard -LPShotWay couple+msg+edited[+sign]`.
  Not here: birthdays, anniversary, «Поздравлять» (К6), messengers and
  «Пишем» (К4), entries from a shoot (К3). Shots: `clients.js` cases `card-couple|family|person|twin|pick|new` (`-LPShotSheet clientcard -LPShotWay …`).
- **Entries from a shoot (К3).** Card head (`CardHead`): a shoot whose `clientId` is in `snapshot.clients` gets a tappable name with a
  hanging «›» (overlay, symmetric padding — the name stays where the web pair `card.name` has it) → `openShootClient` opens
  `ClientCardScreen` over the shoot card, «Назад» (`OrgState.clientBackKey`); a shoot tapped there replaces the open card. Room next
  to the call button stays for the messenger (К4). Form: plate under the name (under both people for a couple), computed per render
  from `EventForm.session` by `ClientBook.hint` (Domain `Rules/ClientHint.swift`), writes nothing — a cancelled form leaves no client.
  **Matching = two of three (Alexey 23.10, К3б)**: first name, last name, phone, per person. Phone (live or `telLog`) + a shared name
  word with **the owner of that phone** (archived: the name in `telLog`) → linked at once («По номеру — …», no buttons; `ClientBook.linkedHits`, used by `bind`, `hint`, `twins`); two
  shared name words (first + last, any order, case/ё/initials ignored; in 3+ words one patronymic drops by position — 2nd word, else last, if …вич/…вна/…чна; a «-вич» surname stays; 2-word names keep both — `nameFactors`), phone absent or different →
  «Это …? N» + «Да» / «Другой»; one factor only → new client, so one phone may live in two clients (`phoneOwners` keeps all).
  Diminutives («Оля»/«Ольга») and nameless clients are not matched. The client the shoot already has or «Да» picked → «Это … · N» +
  «Другой». The answer is `EventForm.clientChoice` (not in the draft), applied by `ClientBook.applying` in `saveForm` before `bind`;
  phone + name still beats it. `bind` fills an empty phone of the same-named person instead of appending a second one — after
  «номер сменился», so a namesake never takes a changed number. Shots: `clients.js` cases `head-*`, `form-*` (`-LPShotSheet clienthead|clientform`).
- **Messengers (К4).** Per person `msg[]` (one per kind: telegram/vk/instagram/whatsapp/max) + `pref` (★); rules in `ClientReach` (Domain,
  `Rules/ClientReach.swift`): `parse` pulls the handle out of a pasted profile link (`vk.com/id123` → `id123`, `wa.me/7916…` → `+7916…`;
  MAX and foreign text stay as typed), `url` builds § 7.1 universal links (`t.me`, `vk.me`, `ig.me/m`, `wa.me`; empty Telegram/WhatsApp
  field = by the person's phone; MAX = its own web link), `primary` = ★ → first messenger → `sms:`; `writer` = `main` if reachable, else the
  first reachable. UI: `ReachButton` (`Screens/Org/`, `Menu` + `primaryAction`: tap opens, long press lists call/SMS/each messenger, per
  person) in the shoot header next to the number (`CardHead.contactRow`, `AppModel.shootReach`: client's plan, else SMS to the header number)
  and in the client card's phone row (`personReach`); card rows + «+ мессенджер» + «Пишем» segment (`AppModel+ClientReach.swift`). **Button glyph (Поле-1 п.5, Alexey 25.10: «значок выбранного мессенджера»):** `ReachButton` shows the glyph of `plan.primary.messenger`
  (`ReachItem.messenger`, set only for a messenger way) — Telegram plane, WhatsApp bubble+handset, VK square+«VK», Instagram, MAX bubble+«M» — one colour like every
  card glyph, **not brand colours**; SMS keeps `chat`. Drawn by hand in `Icons/MessengerGlyph.swift` (same string format and 24×24 canvas as `IconLibrary`, drawn by
  `Icon(messenger:)`): **outside `IconLibrary.generated.swift`, so `make icons` never erases them** (`glyphsLiveOutsideTheGeneratedLibrary` holds it); the web has none (frozen).
  Same `ClientReach.primary` as the stars, so a star, a removal or «Пишем» changes the glyph at once. Shots `clients.js` `head-msg`, `card-msg`, SMS in `head-couple|person`.
- **Debts stack (К5, Wallet-like — Alexey 23.10: «подобно стопкам Wallet», «перспектива не нужна»).** Rule `Debts` (Domain): work
  kind, genre with delivery or none, phase `.after` by the card's clock (manual end respected), «сдана» not pressed; the deadline never
  changes it; order oldest first. A tap in the calendar (month row, week row, day lane → `PlanMotion.openFromCalendar` →
  `openCardFromCalendar`) on a debt opens view 1: `cardStackMode = .debts`, no edges above the sheet (`CardStack.edges`), the other
  debts as `DebtPile` pinned at the bottom (`safeAreaInset`; ≤ 3 same-width plates + «Ещё несданных: N»). Pile tap → view 2
  `DebtsListScreen` (own layer `BackZ.debtsList` over the card, edge-back/✕ return to the card): every debt as a band (`PeekLabel`,
  step 52 of 74), oldest on top, no cap; band tap → that debt as view 1. Anything else opens the day stack, unchanged. The mode is
  set on open, so a card marked «сдана» stays open and is gone from pile/list once you move on; `closeCard` resets both. Shots:
  `clients.js --cases debts,debts-list,debts-few,debts-done` (20 debts via `LPShotWay many`).
- **Greetings (К6).** Birthday per person (`bd`, `Birthday`: day+month, year optional → age), couple anniversary = earliest wedding
  unless hand-edited (`annivManual`; cleared by hand stays cleared), «Поздравлять» per card (`greet`, turns on by itself when a date
  is first written by hand — `Greetings.turnsGreetOn`; К6б, Alexey's option 3: a wedding turns it on only when «Сохранить» links it to the client for the first time — `AppModel.greetNewWedding` in `saveForm`, never the one-time `assemble` pass, so past couples stay off and nothing re-evaluates on reinstall/cloud; no system prompt there, the card offers «разрешите уведомления»; `greetHand` = the toggle was touched by hand → no auto-on ever again). Rules: `LightPlanDomain/Rules/Greetings.swift`
  (`days`: one `Day` per date with all occasions, 29 Feb → 28 Feb, nearest 40). One notification per day `lp.greet.<YYYY-MM-DD>` at 10:00
  **phone clock**: `ScheduledAlert(wall:)` → calendar trigger without zone/calendar. Tap → client card (all occasions of one client) or
  «Клиенты» (`NotificationPresenter.Tap`, `openGreetClient`). **The 64 pending slots are shared by one sync of all lanes**
  (`NotificationScheduler.lanes`: greet cap 40, studio = the rest ≥ 24; unknown foreign requests still count): `AppModel.syncAlerts`
  (was `syncStudioAlerts`) plans studio + greetings together on launch, return and every `persist()` — never sync one lane alone.
  Debug `-LPTravelTo <ISO>`: the app clock starts there and every request is moved by the same shift (`SystemNotificationCenter.debugShift`,
  interval trigger) — a «tomorrow 10:00» greeting is delivered a minute later on the simulator; log with `-LPAlertLog <file>`.
  Shots: `clients.js --cases card-greet,card-greet-person`.
- **iPhone Contacts (К7).** Each person of a client **with a number** = one contact (name split first/middle/last, one e164 mobile
  number, birthday, messengers as social profiles, couple anniversary in «Dates» of both); never Notes. Rules `ClientContacts` (Domain:
  `phoneKey` = `TelFormat.full` with extension cut — «8…» = «+7…»; `cards`, `plan`, `fill`). Number already in the book (not ours) → no
  contact, theirs untouched, only missing birthday/messengers read into the client. Edits go only to own contacts (link person key
  `clientId#i` → contact id + last written card, device-local `ContactsRecord` in UserDefaults, never the snapshot); own contact deleted by
  hand → `dropped`, never recreated; deleting a client leaves its contact. Data: `ContactsMirror` actor, `CNContactsStore` (only `Contacts`
  user, `unifyResults = false`), fake `InMemoryContactsStore`. App: `AppModel+ClientContacts.swift` (`AppModel+Contacts.swift` is the old
  «Контакты» number list of iteration 28 — different thing). **Three protections (Alexey 23.10):** (1) only `ClientContacts.mainBundleID`
  writes (same constant decides the seed) — slots «LP …» get no toggle, a note instead; (2) every client existing at the first K7 launch
  is `past`, written only after «Сохранить в Контакты N … из прошлых съёмок?» → «Да» (plate over the list; «Нет» → line under the toggle);
  (3) «Убрать из Контактов всё, что записало приложение» (confirm) deletes by link only, turns the toggle off and re-marks all clients past.
  Toggle default on; permission asked at the first «Клиенты» opening; limited/denied → shown off with a note, tap → iPhone Settings.
  «Из Контактов» = `CNContactPickerViewController` (no permission): form phone rows (extras land in the client on «Сохранить»,
  `takeFormPicked`) and card person rows. Real book check: `python3 Tools/contacts_sim.py --app <.app>` (`-LPContactsProbe`, `--selftest`).
  Shots: `clients.js --cases contacts-past,contacts-on,contacts-no,contacts-limited,contacts-denied,contacts-test` (`-LPShotContacts`); captions never name the screen's own controls (К7б), the shot checks it.
- **Widget of the day (30б.2).** `LightPlanWidget/` (extension, links Core + Domain only) shows `WidgetFeed.frame(at:)` (Domain `Rules/WidgetFrame.swift`,
  pure, tested): no shoots → next dawn, then sunset (3 days ahead, polar → a word); a shoot today/tomorrow by its own place's clock
  (`WidgetFrame.horizonDays`, Alexey's words 24.10 + orchestrator's variant) → genre (never the client name), start, place, golden hour if the
  shoot wishes `.sunset`; shoot running → studio-hour countdown (`Rent.deadline`, else to the end; none for a shoot closed by hand), next point,
  rest of the route. File `widget.json` (`Rules/WidgetFeed.swift`, built by `WidgetFeed.make` from sessions on every `persist()` / place change;
  `AppModel.publishWidget`, `WidgetShare`): place, shoots of 7 days (moments in ms, per-shoot zone `fixed:<s>`), words in the app's language
  (`AppModel.widgetWords` from the Lexicon), `lang`, `clock12`. Timeline = `feed.changes(from:)` (starts/ends, stops, deadline, sunrise/golden/sunset,
  midnights), 36 h, then `.after`; countdown seconds tick by themselves (`CountdownText`: range from the entry's `now`). Families: small, medium,
  `accessoryInline` («☀︎ 17:02 · съёмка 15:00»). Tap → `lightplan://shoot/<id>` or `lightplan://day/YYYY-MM-DD` (`AppModel.openDayLink`).
  Brass «α» on every build but `Novopashin.LightPlan` (`WidgetFeed.isMainApp`). **Views are tested from the app's UI suite**:
  `Packages/LightPlanUI/Tests/LightPlanUITests/WidgetViews` is a symlink to `LightPlanWidget/Views` (the extension is not importable) —
  `WidgetViewsTests` measures ideal height ≤ plate − 16 pt margins at 158/170 (small) and 338/364 (medium), three text sizes (the views cap Dynamic Type at
  `.xxxLarge`: a widget does not scroll). Pictures: make `/tmp/lp-widget-shots` and run the suite.
- **Widget sizes (30б.2в).** Six forms, one provider, one root: `WidgetRoot` (`LightPlanWidget/Views/`) picks the view by `WidgetShape`
  (Domain `WidgetFrame.swift`; the extension maps `WidgetFamily` in `DayEntry.shape`). Small/medium: shoot running → **ring**
  (`SmallLiveView`/`MediumLiveView`: two tick layers along the perimeter, whole shoot + current point; Alexey 26.10 chose it over
  «plain», which was removed), otherwise the 30б.2 light/next-shoot views with `WidgetRoot` giving them the 16 pt margin (the widget
  runs `.contentMarginsDisabled()` because the ticks live in the margin). Large: day timeline with a shoot, sun arc without
  (`LargeView`). Lock screen: `LockCircularView` (time to the golden hour, `4:10`), `LockRectangularView` (Calendar style; no shoot →
  next sunrise/sunset in the same drawing), inline unchanged; they paint with `Color.primary` (the system tints them), the container
  background is clear there. **Client names (`Shoot.names`, as the card head) only on Home** — lock views never read them
  (`WidgetLiveTests.clientNamesAreOnlyOnTheHomeScreen` compares pixels with and without names). The file also carries `Shoot.genre`
  (`wedding` → «до конца свадьбы», else «съёмки») and `Stop.sign` (the point sign name, `PointSign.name` computed by the app). **The
  extension has no `LightPlanUI`**: its signs are `WidgetIcons.generated.swift` (`python3 Tools/widget_icons.py`, part of `make icons`:
  the app's own icon lines, only those `PointSign` can name) drawn by `WidgetIcon.swift` (a copy of the `IconArt` parser; the
  `WidgetLiveTests` icon tests compare paths sign by sign — drift = red). New words are `widget.*` in `Tools/lang_native.json`
  (`{n}`/`{t}` templates, word order differs by language). **Feed:** `WidgetFeed.timeline(from:shape:)` adds a moment every minute
  while a shoot runs (small/medium), every minute to the golden hour (circular), every 10 minutes of daylight when the large view is
  the sun arc; the digits are static («62 мин» — system `Text(timerInterval:)` can only print «62:00»), so the feed changes them.
  `entryLimit = 180` entries per timeline, reload on the last shown moment when cut; WidgetKit names no entry cap, only the reload
  budget (40–70 a day per widget), so the cap is ours — a 12.5 h wedding with the ring is ~5 reloads. Views are `Shape`s, not `Canvas`.
  Pictures: `docs/30b2v_sketches/built/` (`WidgetLiveTests.writesTheBuiltSheetsWhenAsked`, folder `/tmp/lp-built-out` must exist).
- **Activity screen (30б.3).** Live Activity on the lock screen and in Dynamic Island while a shoot runs (words of Alexey 25–26.10). Rules in Domain:
  `ActivityFrame` (the state the system keeps — ≤ 4 KB, ≤ 16 points, short coding keys; `ActivityFrame.make(feed:shoot:now:mode:words:reach:)` from the same
  `WidgetFeed` the widget reads) and `ActivityRules` (`wanted` = the widget's `.live` shoot, `decide` start / update / restart / end; a day > 8 h is restarted on every
  return to the app, not twice within 60 s). View = the card's day tile without the date column (`LightPlanWidget/Views/ActivityViews.swift`, also built by the UI
  suite through the `WidgetViews` link): status, range, lane (sign, rail, time, word). **Only two things move without the app:** `Text(timerInterval:)` («до <точки>»,
  exit from the hall) and one `ProgressView(timerInterval:)` per segment between two points; the highlighted point, the status line and the mode change when the
  app is open (no paid Push on the free team, cut 30б row 7/9) — a plate left alone shows `0:00` after its point until the next open. Extension `ShootActivity.swift`;
  attributes `ShootActivityAttributes.swift` are **one file** in `LightPlanWidget/`, symlinked into `LightPlanUI/Sources/LightPlanUI/Activity/` (no pbxproj edit; the system
  matches by type name). App: `AppModel+Activity.swift` — `syncActivity(.foreground|.change)` from RootView (scene active) and `persist()`, seam `ActivityHosting`
  (`ActivityKitHost` is the only ActivityKit user; fake in `ActivityAppTests`), a plate the person swiped away is not started again for that shoot, `NSSupportsLiveActivities`
  in `Config/Info-iOS.plist`. Buttons are links `lightplan://activity/admin|playlist`: a Link on the plate opens the app itself (spike 30б.3а), so the app dials / opens
  the player (`openActivityLink`). Studio: notification stage 0 «Студийный час» at rent start (`StudioSchedule.starts`, id `lp.studio.<id>.<cell>.0`, studio lane); a tap
  (any `lp.studio.` notice) → `Tap.studio(sid)` → `switchActivityToStudio` — buttons appear only in this mode. Island: collapsed = `frame.island` (next point; within
  `goldenLead` = 1 h of the golden hour — the golden hour). **Plate height** (SwiftUI ideal height, same at 330 / 358 / 361 / 408 pt wide; the 160 pt cap is from
  documentation, **not measured on a real lock screen** — the simulator panel was not granted): wedding 143.3, with rent 143.3, studio `full` 181.3 (over), `icons` 155.0,
  `compact` 150.3. `ActivityStudioStyle.current` picks (`.icons` until Alexey chooses). Debug: `-LPActivityDemo wedding|rent|studio|many`, `-LPActivityStyle full|icons|compact`.
  Not here: «+30 минут» (needs the BroniOS link), a Settings switch, push updates.
- **Music (step «Музыка», 25.10).** As in the web: default player (`Snapshot.musicApp`: `yandex|spotify|apple|off`, unknown string kept as written) and
  a shared library of ≤ 10 playlists (`Snapshot.playlists`, `{n,u}` as the web writes them) in Settings «Съёмки» (`SettingsMusic.swift`); a shoot remembers
  its playlist **by name** (`Session.playlist`, `EventForm.playlist`). Rules live in `Music` (Domain, `Rules/Music.swift`): `choice` (own playlist by exact name,
  else the player, else no button — a playlist named «Spotify» keeps its own link), `isOpen` (work only, on the shoot's own time scale from start to end − 5 min — past midnight too, Alexey 25.10; `doneAt`
  ends it earlier), `add/rename/setURL/remove` (empty name → service name «Spotify 2»; rename goes into shoots and the bin; empty/taken name refused; delete leaves
  shoots with a name nobody answers to). Names are compared exactly — «Ёлка»/«Елка», «Сборы»/«сборы» are different playlists (web parity). Card button = `AppModel.musicButton`
  by the **place's wall clock** (same as the phase), `CardScreen.musicPill`. Form row only while the library is non-empty; a form drops a playlist that left it on open
  (`refreshPlaylist`). Pairs: `make shots ARGS="--screens settings,card --chapters shoots --forms portrait+music --cards music,musicapp"` (the web tool `tools/shot.js` gained
  `form.music*`, `card.music`, `pl.*`; web «Календарь» sits first in its chapter, so native `sec.4/5` pair with a constant Δy ≈ −134).
- **Field-1 (25.10, first shoot in the field).** Guests: `Guests` (Domain `Rules/Guests.swift`) — «+» by 1 up to 10, then by 10, ceiling 2000; «−» by 1 from 10 to «—»,
  above 10 by 10 but never below 10; the number is a text field (digits 0–9 only, ≤ 4, as the web's `fGuestsVal`); the form calls `EventForm.moreGuests/fewerGuests/typeGuests`.
  Sub-genres the web lacks (`birthday` in «Семья», `bachelorette`, `bachelor` in «Праздник») are listed in `SubGenre.nativeAdditions`, stand last in their list,
  and their words live in `Tools/lang_native.json`; `DomainTablesTests.subGenres` compares the web table without them. Messenger stars (`ClientReach.starred`): only with
  two or more reachable ways, only on reachable rows. Settings chapter `Chapter.playlists` (player + library) sits between «Язык и регион» and «О приложении»; the web
  nodes `sec.4/5`, `seg.4`, `note.4/5`, `pl.*` are dropped from the «Съёмки» shot pair on purpose. Shots: `clients.js --cases card-msg,card-msg1`, form `-LPShotGuests <n>`.
- **On the line through someone (Поле-2, Alexey 25.10).** `Session.via` (`ContactVia`: relation organizer/girlfriend/friend/relative + name + phone, key `via` `{r,n,tel}`;
  web does not know it and drops it on re-save — like К1) — form row «На связи через» (`EventForm.viaRelation/viaName/viaPhone`, `FormShape.showsVia`: the six genres with a private
  client; deliberately **not** a `FormField` case — that enum is compared with the web's table), collapsed while empty. In the dossier the person is a `ClientPerson` with
  `relation != nil` («На связи · подруга»), after the heroes; it takes no seat in the kind's capacity (`ClientBook.heroCount`), is not written to iPhone Contacts (К7 only if asked)
  and its `telLog` entries carry field `via`. **Gluing rules** (`ClientBook.via/viaHits/placeVia`): a friend's number never recognises a *hero* (`phoneOwners`, `linked`, `nameMatch` skip
  via persons), so «Алёна orders her own portrait» is a new client, not a guest in Olga's card; a shoot joins a client by the friend's number only together with a hero name word
  (`viaHits`) — one friend organising two birthdays gives two cards; a hero without a name never joins by the number alone. Same number on hero and friend → the number stays on the hero.
  Head of the card: call and «написать» go to the friend if she has a number (`PlannerWords.callPhone`, `AppModel.shootReach/shootVia`, messengers from her dossier row), line
  `card.via` «на связи: Алёна, подруга». Shots: `node Tools/shots/pole2.js` (form, collapsed form, dossier, head; numbers from node frames).
- **Studio tile (Поле-1 п.7–8).** `Screens/Card/CardStudio.swift`: the countdown colon is **lifted by font metrics** (`StudioColon.lift` — middle of the colon glyph to the middle of the digits, any size),
  measured on frames: colon centre − digit centre +2.67 pt (sat on the baseline) → 0.00 pt, digits did not move (`.padding(.top, -lift)` keeps the line height). The colon **blinks 0.5 s on / 0.5 s off**
  (Alexey 29.09; the web does not blink at all — `paintStudio` repaints every 20 s, per second only in the last 15 min), so a screenshot can catch it off: shoot several frames. The admin's number is no
  longer shown: a button «Позвонить админу» (`studio.callAdmin`, `Tools/lang_native.json`) dials the same number; no number — no button. Node `card.studioTel` is kept for the web pair (frame differs now).
- **Shoot reminder (Напоминание-1, decision 27.10).** N minutes before every shoot and meeting (`ReminderSchedule`, Data `Notify/`): Settings
  «Уведомления» → «Напоминать о съёмке», `notif.remind` (minutes, choices 0/5/10/15/30/60, default 15; the web drops the key on re-save → 15 again;
  independent of the web's master `notif.all` both ways: choosing never writes `all`, `all = false` does not silence it).
  Fire = start on the **place's** clock − N (a moment); none for calendar drafts (the Calendar reminds of its own events), `.event`, closed-by-hand,
  or a moment already past. One request per record `lp.remind.<id>`, text from `CardHeadText` (`ReminderAlertText`: «name · 12:00» / «genre · place»
  + the number the card head calls); tap → `.card(id)`. Lanes (`NotificationScheduler.lanes`): remind 16, greet 40, studio the rest (≥ 8), remind
  first so foreign requests squeeze greetings, not tomorrow's reminder. **Time Sensitive is refused by the free team** (measured 27.10: «Personal
  development teams … do not support the Time Sensitive Notifications capability») — the entitlement is NOT in `Config/`. `syncAlerts` asks
  `NotificationCentering.timeSensitiveAllowed()` and puts the granted level into the request (and its signature), so adding the entitlement on a
  paid team rewrites standing reminders on the next sync with no code change.
- Signing: team `4A3PUKS9R9`, bundle id `Novopashin.LightPlan`, free team. On it
  App Groups work; iCloud, Push, WeatherKit do not (measured 2026-09-19).

## Commands (output always filtered, see `light_plan:Light_Plan/.claude/rules/xcode.md`)

```
xcodebuild -project LightPlan.xcodeproj -scheme LightPlan-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build \
  > /tmp/cc-xcodebuild.log 2>&1; echo "exit=$?"
grep -nE 'error:|\*\* BUILD (SUCCEEDED|FAILED) \*\*' /tmp/cc-xcodebuild.log | head -40
```

`test` instead of `build` runs the tests of all five packages through either
scheme (`LightPlan-macOS` with `-destination 'platform=macOS'`). One package on
the Mac host: `swift test` inside `Packages/<name>`.

```
make parity     rebuild Fixtures/ from the live beta and prove the run repeats
make blocks     show what is cut out of the beta (cheap anchor check)
make lang       rebuild the string catalog and the text fixtures, prove they repeat
make icons      rebuild the Swift icon library from the web's beta/icons.js + the Chromium reference sheet
make domain     rebuild Fixtures/domain.json (shoot tables and rules, iteration 11) and prove the run repeats
make shots      web / native screenshot pairs of «Свет», «Карта», «Съёмки», «Настройки», compared by numbers
make mapstyle   rebuild the map canvas style (LightPlanMapCanvas/Resources) from the web's beta/mapstyle.js
make mapref     rebuild map_scene_ref.json (the web's #mapLight markup as numbers) for MapSceneParityTests
make tapspot    tap a pin on the live canvas (network), MapLibre and MapKit: the name bar must open and hold (20е)
make pinch      five pinches on the live MapLibre canvas: each zoom holds, the centre doesn't jump back (21б)
make rotor      «Карта» under a scripted compass, 8 headings: north on screen within 1°, no void wedge (21а)
make sims       this branch's simulator; ARGS=--prune deletes simulators of deleted branches
make shots ARGS="--screens ar"   AR with a synthetic camera (29.8в.4): day, night+moon, night+Milky Way, entry plate, checked by numbers; `Tools/ar_contrast.py` (29.8в.9б: icon contrast of every AR button on white sky / blue sky / asphalt / night sky, goal ≥ 3:1, plus «glass, not a black plate» = button luminance ≥ 0.2 of the backdrop; `--variants regular,clear.s,black70,…` picks the glass via `-LPSunARButtonGlass`, `--appearance`; red exit when a black tint comes back), `Tools/ar_disc_sat.py` (sun disc saturation on white/gray/black, 29.8в.6), `Tools/planets_ref.py` (29.8в.15: planet reference from JPL Horizons → `Fixtures/planets_horizons.json`, read by `PlanetEphemerisTests`; scenarios `planets_*`), `Tools/ar_lens_bench.py` (fps and CPU of the lens layer; `--planets` 29.8в.15: planets layer on vs off, three pairs; `--stars` 29.8в.13: night, star layers on vs off; `--milkyway` 29.8в.14: three runs with and without the Milky Way band, phone swept around the core), stars and constellations scenarios `night_stars*`, `dusk_stars`, `day_stars*` (29.8в.13, see `Tools/shots/README.md`), `Tools/ar_milkyway.py` (29.8в.14: the procedural band by simulator frames — centre line vs `MilkyWay.band` ≤ 0.5° on 5 moments, core vs `corePosition`, cross profile vs `MilkyWayLook.smooth`, empty by day, `--frames` night / city / twilight / day; debug args `-LPSunARMWParts smooth,texture,dust,label`, `-LPSunARGlow <ratio>`; south latitudes in `-LPSunARPhone` need a leading space; 29.8в.17б planning: the band is drawn at any visibility — day, city, glow 40 — with a dark edge outline for bright skies, `--contrast` measures band vs backdrop on white / blue sky / asphalt / night, `--lists` dumps the «Слоёв» rows per place and language; 29.8в.19 Gaia: `--contrast` adds city 12/27 and Moon 62 % scenes, `--scenes`, `--extra`; `Tools/mw_gaia_frames.py` shoots the Gaia layer (night, city, dusk, day, «Как в тёмном месте», core, Cygnus, Crux; `--sim` for SE 3); Debug `-LPSunARMWFloor` / `-LPSunARMWUnder` tune the planning floor and underlay, `-LPSunARMWSource formula` forces the fallback, `-LPSunARCycle N -LPSunARCycleLog <file>` closes and reopens AR N times and logs phys_footprint, Gaia loads and GPU builds; `Tools/mw_core_ref.py` = astropy reference of core rise/set → `Fixtures/mw_core_astropy.json`, read by `MilkyWayCoreTrackTests`; `-LPSunARMWParts` also takes `edge`), `Tools/ar_glass.py` (disc glass by pixels, 29.8в.9а: shadow ring outside the disc, highlight angle under roll ±20°, lower disc edge under the upper one, line bend under a disc placed by `-LPSunARMarkPos`). Disc glass: system `.glassEffect` by default, own (Metal + lens copy) behind the Debug flag `lightplan.native.sunar.glass own` / the «Стекло» button on the AR screen; the three ar_* tools take `--extra "<launch args>"`
make lightfit   «Подробно» on «Свет» (Astro), closed and open: MEASURES gap button↔bottom panel (not a pass/fail; `--min-gap` makes it one), open list starts at the button bottom, header not covered, button doesn't move; 7 models × 2 themes × 4 texts; ARGS="--app <.app> [--views closed,open] [--cases calm,wind,night,haze] [--ribbon lane] [--mode simple] [--min-gap 0]"; `node Tools/light_fit.js --selftest` checks the checker (29.2г, 29.2г-3); 29.8в.27: «Астро» adapts to the MEASURED height (`LightCollapsedList.plan`, no device models): header always compact (no «область» line; name / date / «сегодня» one per line; weather on two lines), «Тени», «Небо», «Ветер» return to the collapsed list in that order while the «Запланировать съёмку» button fits above the panel (gap 8; the rest lives in the expanded list), the arc strip grows 22 → 34 pt only if even the important set does not fit; «Просто» unchanged. lightfit columns «строки» (Т Н В), «шапка», «провал» (spare over the 8 pt) and «действие» (`timebar` top − `action` bottom); red if a hidden row would have fitted, the strip is raised needlessly, or «Просто» lost a row. Native adaptation, web unchanged
```

Build on Alexey's iPhone — for his word at the end of an iteration. Device: **iPhone ALno**
(15 Pro Max, `5A94DA8F-B9E0-5DB8-BECF-14F387CFE24F`). Never «iPhone Elena» — not his.
Free signing team until the Developer Program is paid: the build expires in 7 days, reinstall.

**Branches sit side by side on the phone (Alexey, 2026-09-28; pool since 2026-10-12).** One bundle id
for every branch meant each install replaced the previous one. So:
- `Novopashin.LightPlan` («Light Plan» on the home screen) = `main` only;
  reinstall it after a merge to `main`.
- A branch installs into one of **four permanent slots**, bundle ids `Novopashin.LightPlan.slotA` … `slotD`,
  home-screen name `LP <branch>` (`wt/24a` → «LP 24a»; the name comes from the record, not from the id).
  An id made from the branch name spent one of the free team's 10 new App IDs per 7 days on every step
  (limit hit 03.10 and 12.10); four fixed ids are all it ever registers.
- Slot choice (26.10): the branch's own slot → a free slot **already registered with Apple** → the oldest registered slot
  whose branch is merged into `main` (its app is replaced) → a free never-registered slot → a merged slot whose
  registration lapsed → otherwise the script stops and names the four branches and the `uninstall` to run. A first
  build under an id costs two of the 10 new App IDs per 7 days (app + `.Widget`), so unregistered goes last (26.10: slot C
  was picked, the limit was spent, A and B held merged branches). «Registered» = the record shows an install of that id
  within 7 days of the first install of its current registration (free-team registration lives 7 days and builds do not
  renew it — read off the record, not measured at Apple; `LP_PHONE_REG_DAYS`). The printed reason names the rule. If the
  build still hits the limit, the message lists the registered slots of merged branches: `uninstall slotX`, install again.
  Held by `make phoneslots` (shell only; `ARGS=<old phone.sh>` must fail).
  The record `slot → branch → sha → time` is `~/.light_plan_phone.tsv`.
- Each copy has its own data: seed it there if the check needs data.
- Branch merged or dropped → `uninstall` it (commands below); the slot frees up.
- Old per-branch ids (`Novopashin.LightPlan.wt…`) are not in the pool; `uninstall wt26` and `list` still work with them.
- Tell Alexey the icon name he is checking.
- **Icon (24.10):** only `Novopashin.LightPlan` gets the clean `AppIcon`; every other iOS bundle id gets `AppIconAlpha`
  (same icon + brass «α» badge, placed like the web beta's «B»). Chosen by id in `Config/iOS.xcconfig`; held by
  `Tools/check_app_icon.sh` (build phase: settings; `phone.sh`: the built .app before install; `--selftest`).
  Main icon changed → `make appicon` regenerates the α set (`ARGS=--check` only checks it).

One script does all of it — do not hand-build for the phone:

```
make phone ARGS="install"          # slot + name from the branch, build, install, launch
make phone ARGS="list"             # slot, «Сборка · branch · sha · DD.MM» (same line as at the bottom of its Settings), free slots
make phone ARGS="uninstall slotB" # a slot, or a branch standing in one (`wt/24a`); uninstall --main only from Alexey's word
make checkstep ARGS="wt/26 main --type код --tests --full"   # step check: five lines yes/no
make clocksweep ARGS="--targeted"  # date mines: tests on a faked «now» (Tools/clock_sweep.py); a test model reads the real clock unless built with `now:`
```

`Tools/phone.sh`: `main` → «Light Plan»; any other branch → `LP <rest>` in a pool slot (see above);
`--main` from a branch is refused (exit 2); the phone must be «available (paired)» (else exit 3 —
ask him to plug in and unlock); prints what stands and from which commit. Second barrier,
independent of the script: the build phase (`Tools/check_phone_id.sh` via `check_boundaries.sh`)
fails a device build (`PLATFORM_NAME=iphoneos`) with `Novopashin.LightPlan` from any branch but
`main`; simulator and Mac are not checked. Never pass the main id by hand from a branch.
`Tools/check_step.sh <branch> [<base>] [--type код|данные|документы] [--tests]`: commit ahead,
non-empty diff, GPT review of the last pushed commit present and not red (public GitHub API,
`curl`), new tests fail on the parent commit (`--tests` = a build; without it the line says
«не проверялась», exit 2), full set not redder than the base (`--full` = two `xcodebuild test` runs on
simulator `LP checkstep`; failed tests of the branch vs the merge-base by name — «нет» only for a test that is red
on the branch and green on the base; a test already red on the base is «да» with a note; without the flag
«не проверялась», exit 2). Any «нет» → exit 1. Run it before the report.

`launch` fails with «Locked» when the phone is locked — the app is installed anyway; tell him to
open it. Say which build it is (commit) and what to check, in product words.

Simulators: every branch gets its own, `LP <branch>` (iPhone 17 Pro Max model and iOS, created on
first run by `Tools/sim.js`); `shots`, `tapspot`, `pinch`, `rotor` use it, so parallel worktrees don't collide.
`LP_SIM=<name>` overrides. Tools leave the base iPhone 17 Pro Max alone — someone may be using it.

A screen iteration closes with `make shots` pairs (plan § 5.4): names in the web's
`tools/shot.js` `NODES`, `.shotNode("name")` on the Swift side. `Tools/shots/README.md`.
Pairs check frames on screen; what is drawn inside the map instrument is checked element by element
against the live beta's SVG (`MapSceneParityTests`). Map canvas: MapLibre on iOS, MapKit on the Mac,
only inside the `LightPlanMapCanvas` module (`check_boundaries.sh` holds it).

`LightPlanUI/Icons/IconLibrary.generated.swift` and `point_sign.json`, `icons_ref.*` beside the UI
tests are generated (`Tools/icons2assets.js`, `Tools/icons_ref.js`) — never hand-edit. Icons are
stored as vector paths, not as an asset catalog: the web sets line width per context and paints
weather parts separately, a catalog bakes both (from code, catalog not measured). Use
`Icon("name", size:, line:)`; colour comes from `.foregroundStyle`. The generator stops if the
copy of `icons.js` pasted into `beta/index.html` drifted from the file.

`LightPlanUI/Resources/Localizable.xcstrings` is generated from the web's
`beta/lang.js` (`Tools/lang2xcstrings.js`) — never hand-edit it; a word changes
on the web and comes here by `make lang`. Exception: a web word the web keeps but the app must
not show (Alexey 24.10, «правим только приложение») goes to `Tools/lang_fixes.json`
(`{lang: {key: {web, app, why}}}`); it applies only while the web still holds `web`, else the
generator stops. Only Xcode compiles a catalog: under
`swift test` on the host the catalog tests skip (with a note), so run
`xcodebuild test` before calling the strings verified. Scripts find the web
folder next to the repo; **from a worktree set `LIGHT_PLAN_WEB=<path to Light_Plan>`**.

Parity bench: `Tools/parity/README.md`. It cuts the math out of the web's
`beta/index.html` by anchor strings on every run — never copy that code into
the native tree, a copy drifts silently. Fixtures are regenerated, not
hand-edited; a parity failure is a porting bug until measured otherwise.
