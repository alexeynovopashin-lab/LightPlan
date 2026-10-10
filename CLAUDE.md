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
  `node Tools/edge_back_bench.js --app <.app>` drives all 16 layer screens without a finger (table: frames, missed, p95, CPU);
  `--shade` compares a layer at rest with its first gesture frame pixel by pixel. **In the simulator trust CPU ms, not frame
  intervals**: ~60 % of a late frame there is the main thread sleeping on the sim's renderer (`wait_image_queue`).
  Layer shadow is a 20 pt gradient strip left of the edge (`EdgeShade`), never `.shadow` on the content (that shades every
  child). Only the visible tab moves under a layer (`.edgeBackBase(app, .tabs, shown:)`): moving all four cost ~9 ms/frame.
- **Glass never takes a rotation (28п).** `.glassEffect` under `rotationEffect` (or `scaleEffect`) swells into the
  bounding rectangle of the whole layer at angles that are not multiples of 90° (measured: three spot plates → one
  ≈ 420 × 415 pt slab). On «Карта» the rotor is two halves with the same angle (canvas, veil, road / instrument)
  and the spots layer (pins, name plates, route numbers) sits between them, **not rotated**: each mark is placed at
  `MapSpots.screenTip` and stays upright. A new glass element near the rotor goes outside both halves.
  `node Tools/rotor.js --spots --bare --angles 0,45,…,33 --motion 4` measures plate size and place per angle (red on a swell).
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
make lightfit   «Подробно» on «Свет» (Astro), closed and open: gap button↔bottom panel (> 0), open list between header bottom and button top, button doesn't move; 15/15 Pro Max/16/16 Pro Max/17/17 Pro Max red, SE 3 for information; ARGS="--app <.app> [--ribbon lane] [--mode simple]" (29.2г, 29.2г-2)
```

Build on Alexey's iPhone — for his word at the end of an iteration. Device: **iPhone ALno**
(15 Pro Max, `5A94DA8F-B9E0-5DB8-BECF-14F387CFE24F`). Never «iPhone Elena» — not his.
Free signing team until the Developer Program is paid: the build expires in 7 days, reinstall.

**Branches sit side by side on the phone (Alexey, 2026-09-28).** One bundle id
for every branch meant each install replaced the previous one: iteration 24
overwrote the dome fix he was checking. So:
- `Novopashin.LightPlan` («Light Plan» on the home screen) = `main` only;
  reinstall it after a merge to `main`.
- A branch installs as its own app: bundle id `Novopashin.LightPlan.<slug>`,
  home-screen name `LP <slug>` (`wt/24a` → `wt24a`, «LP 24a»; Latin, short).
  Tell Alexey the icon name he is checking.
- Each copy has its own data: seed it there if the check needs data.
- Branch merged or dropped → uninstall its app (commands below).
- Free team caps how many apps/App IDs it signs (from Apple docs, not measured
  here); a signing error about the limit → uninstall closed branches, tell him.

One script does all of it — do not hand-build for the phone:

```
make phone ARGS="install"          # name + bundle id from the branch, build, install, launch
make phone ARGS="list"             # what stands on the phone: «Сборка · branch · sha · DD.MM», same line as at the bottom of its Settings (build_stamp phase)
make phone ARGS="uninstall 24a"    # closed branch (uninstall --main only from Alexey's word)
make checkstep ARGS="wt/26 main --type код --tests"   # step check: four lines yes/no
```

`Tools/phone.sh`: `main` → «Light Plan»; any other branch → `LP <rest>` with its own id;
`--main` from a branch is refused (exit 2); the phone must be «available (paired)» (else exit 3 —
ask him to plug in and unlock); prints what stands and from which commit. Second barrier,
independent of the script: the build phase (`Tools/check_phone_id.sh` via `check_boundaries.sh`)
fails a device build (`PLATFORM_NAME=iphoneos`) with `Novopashin.LightPlan` from any branch but
`main`; simulator and Mac are not checked. Never pass the main id by hand from a branch.
`Tools/check_step.sh <branch> [<base>] [--type код|данные|документы] [--tests]`: commit ahead,
non-empty diff, GPT review of the last pushed commit present and not red (public GitHub API,
`curl`), new tests fail on the parent commit (`--tests` = a build; without it the line says
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
on the web and comes here by `make lang`. Only Xcode compiles a catalog: under
`swift test` on the host the catalog tests skip (with a note), so run
`xcodebuild test` before calling the strings verified. Scripts find the web
folder next to the repo; **from a worktree set `LIGHT_PLAN_WEB=<path to Light_Plan>`**.

Parity bench: `Tools/parity/README.md`. It cuts the math out of the web's
`beta/index.html` by anchor strings on every run — never copy that code into
the native tree, a copy drifts silently. Fixtures are regenerated, not
hand-edited; a parity failure is a porting bug until measured otherwise.
