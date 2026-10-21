# iPhone Duo — adaptation plan for Light Plan (native)

Written 2026-10-21 from Apple's primary sources, in a cloud session with **no Xcode**: this is
documentation research plus a read-only look at the code. Nothing here was run on a Duo
simulator or device. App code is untouched.

Conventions used below:

- **[Apple]** — stated on a developer.apple.com page I read; the URL is next to it.
- **[derived]** — arithmetic on Apple's numbers; the assumption is written next to it.
- **[blog]** — third-party estimate, not Apple. Treated as a hint only.
- **[not verified]** — I could not read it, or Apple does not say it. Check before relying on it.
- **[repo]** — read from this repository (`file:line` at `88f9cd2`, `main`).

How the sources were read: developer.apple.com pages are JS-rendered, so `WebFetch` returned
only page titles for the HIG and failed on the guide. Apple's JSON documentation endpoint
(`https://developer.apple.com/tutorials/data/<path>.json`) returned the full text of every
documentation and HIG page; Tech Talk transcripts and App Store Connect help pages are plain
HTML and were read directly. The full source list is in § 7; what I could not read is in § 7.2.

---

## 1. The device and its poses

### 1.1 What Apple states

- Two displays, each with its own front camera; a hinge in the centre; the inner camera sits
  behind the display and is hidden until active. The outer camera sits in a corner, is always
  visible, and expands into the Dynamic Island for Live Activities.
  [Apple] HIG «Designing for iPhone Duo», sections *Anatomy*, *Reserved regions* —
  <https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo>
  (change log: «September 9, 2026 — New page»).
- On sale 2026-10-23. [Apple] <https://developer.apple.com/news/?id=kkphp5qo> (dated 2026-10-05).
- Poses named by Apple: closed (outer display); open (inner display, portrait or landscape);
  partially folded «like a book» (fold runs vertically through the centre, content sits side by
  side); partially folded «like a laptop» / seated on a table (fold runs horizontally, content
  above and below); standing on its edges «like a tent»; two apps in a 50/50 Split View on the
  inner display; Picture-in-Picture video pinned to the top of the screen.
  [Apple] HIG (*Device poses*), guide
  <https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo>,
  Tech Talk «Design for iPhone Duo» <https://developer.apple.com/videos/play/tech-talks/111466/>.
- Size classes. [Apple] Tech Talk «Prepare your app for iPhone Duo»
  (<https://developer.apple.com/videos/play/tech-talks/111461/>, chapter 2:46):
  - outer display, portrait: horizontal **compact**, vertical **regular**;
  - outer display, landscape: **compact / compact**;
  - inner display: **regular / regular** (both orientations).
  HIG: «A compact width layout for the outer display and a regular width layout for the inner
  display give you the fundamentals for every pose.»
- Orientation. [Apple] same talk: «The inner display doesn't honor your supported interface
  orientations.» and, a few lines later, «iPhone Duo respects your supported interface
  orientations, but your app will scale on the inner display, including in Split View.»
  The two lines are not fully reconciled on the page; what a **portrait-only** app does on the
  inner display is **[not verified]** — test it first (§ 3.1).
- The outer display is «wider and shorter than the display on other iPhone devices». [Apple] HIG.
  Controls (toolbars, tab bars, back buttons, the status bar, the Dynamic Island) move to a
  vertical strip at the side: the **right** side when closed (talk «Design for iPhone Duo», 0:28:
  «move to the right side of the display … easier to reach with your right thumb»); on the inner
  display in landscape they stay on the side; **the only pose that keeps horizontal bars is the
  inner display in portrait**. In Split View each app puts its controls on its outer edge (left
  app → left edge). The side is fixed to the hardware, not mirrored in right-to-left languages.
  [Apple] HIG *Vertical controls*.
- The fold is a «division» reserved region: active only when partially open, inactive (width 0)
  when flat. The cameras are «occlusion» regions. Scrolling containers do **not** split their
  content around the fold by default. [Apple] ReservedRegion page (§ 7) and Tech Talk
  «Strike a pose with adaptive layouts on iPhone Duo» (111463).

### 1.2 Sizes

| What | Value | Status |
|---|---|---|
| Outer display, App Store screenshot size | 1398 × 2034 px (portrait), 2034 × 1398 px (landscape) | [Apple] screenshot specifications (§ 4.1) |
| Inner display, App Store screenshot size | 2007 × 2853 px (portrait), 2853 × 2007 px (landscape) | [Apple] same page |
| App-preview «device resolution» | 2034 × 1398 and 2853 × 2007 px, listed as «19.5:9 aspect ratio» | [Apple] app-preview specifications. The ratio label does not match the pixel numbers (2034/1398 ≈ 1.45, not 2.17) — Apple's typo or a different meaning; ignore it |
| Outer display in **points** | 466 × 678 | [derived] 1398 / 3, 2034 / 3 **assuming @3x**. Apple's pages I read give no point size and no scale. [blog] <https://blakecrosley.com/blog/iphone-duo-day-two> uses the same numbers and says itself they rest on an assumed 3x until a simulator reports them |
| Inner display in **points** | 669 × 951 | [derived] 2007 / 3, 2853 / 3, same caveat. The same blog also quotes a spec-sheet panel of 1878 × 2670 px and a first guess of 626 × 890 pt — it retracts that guess. **Not verified** |

Rule for the rest of this document: **no layout number may be taken from the table above.** The
project principle «layout by measured available space, not by device model» (and Apple's: «Avoid
fixed widths, breakpoints, or any metrics tied to a specific screen», talk 111466) means the
first task on a Duo simulator is to **measure** `size` + `safeAreaInsets` per pose with the
existing audit tooling (§ 4.4, § 5 step 2) and write the real numbers into this section.

The audit report on branch `wt/audit-heights` (`Tools/audit_heights/REPORT.md`, reachable:
`git show origin/wt/audit-heights:Tools/audit_heights/REPORT.md`) uses the same 466×678 and
669×951 — they are the [derived] values above, not measurements; the report itself says Duo was
not captured.

---

## 2. What changes with the SDK you build against

[Apple] <https://developer.apple.com/iphone-duo/prepare/> («Before you begin») and guide
<https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo>,
confirmed in talk 111461 (0:30).

| Built with | What the user gets on Duo |
|---|---|
| **iOS 26 SDK or earlier** (this app today: built with Xcode 26.6 per the audit) | Runs, does not adapt. Open: the app sits in the **centre** of the inner display with empty space around the window. Closed: the app uses the outer display to the **left of the status bar and camera**. Does not extend under the status bar and camera. |
| **iOS 27 SDK** | Resizes to fill **most** of the inner display, still avoids the status bar on the right edge. |
| **iOS 27.1 SDK** (Xcode 27.1) | Full display; toolbars and tab bars appear **vertically** below the status bar. Apple: «Before shipping an app build with the iOS 27.1 SDK, make sure your app's content adapts to the bars becoming vertical.» |

API availability, [Apple] from each page's platform table:

- **iOS 27.1:** `ReservedRegion` (SwiftUI) / `UIView.ReservedRegion` (UIKit),
  `GeometryProxy.reservedRegions(kind:options:layoutDirectionBehavior:)`,
  `UIView.reservedRegions(kind:options:)`, `ArrangementView`, `UIArrangementViewController`,
  `ToolbarVerticalCompressionBehavior` and `.toolbarVerticalCompressionBehavior(_:)`,
  `.toolbarVerticalBehavior(_:)`, `EnvironmentValues.toolbarVerticalEdge`,
  `UITraitCollection.verticalBarEdge`, `ToolbarContent.axisBehavior(_:)`, `UIHingeInteraction`.
- **iOS 27.0:** `ToolbarItemVisibilityPriority`, `ToolbarOverflowMenu`,
  `ToolbarItemPlacement.topBarPinnedTrailing`, `.defaultTabBarPlacement(_:)`.
- **iOS 26.0:** `UIScreen.main` deprecated, `backgroundExtensionEffect()`, concentricity APIs.
- **Hinge in SwiftUI.** Tech Talk «Leverage multiple displays and scenes on iPhone Duo» (111464)
  says SwiftUI has an `onHingeChange` modifier; I could **not** find its documentation page
  (a guessed JSON path returned 404). Name and availability: **[not verified]**. Light Plan does
  not need it (hinge angle is for effects; for layout Apple says use arrangement/region APIs).
- Scene accessories (`sceneAccessory`, camera capture accessory): talk 111464 and
  <https://developer.apple.com/documentation/avfoundation/registering-a-camera-capture-accessory-on-iphone-duo>.
  Not needed for Light Plan (it uses the rear camera only for AR, no front-camera flow).
- Name mismatch to remember: the page lists `toolbarVerticalCompressionBehavior(_:)`, the talk
  calls it «toolbarCompressionBehavior». Use the page's name.

Consequence for this project: `IPHONEOS_DEPLOYMENT_TARGET = 26.0` ([repo] `Config/iOS.xcconfig:5`).
Everything marked 27.x above needs `if #available(iOS 27.1, *)` or a higher deployment target —
a product decision (§ 6, Q4).

**Xcode side [Apple]:**

- Xcode 27.1 adds the iPhone Duo simulator, run from **Device Hub** (the page
  <https://developer.apple.com/documentation/xcode/device-hub>). Controls under the bezel:
  Closed / Partially Open / Open buttons; hold Option and drag the slider to fold to any angle;
  Rotate Left / Right.
  <https://developer.apple.com/documentation/xcode/interacting-with-your-app-in-device-hub>
- A resizable iOS simulator in Device Hub and iPhone Mirroring on macOS 27 (resize the window to
  extreme sizes in both directions) are listed as test tools in step 3 of the Duo «prepare» page.
  <https://developer.apple.com/iphone-duo/prepare/>
- **The «App Resizability» skill.** In Xcode, ask the coding assistant «get my app ready for
  iPhone Duo»; for another agent run `xcrun agent skills export`. Apple says it finds most
  patterns but not all. (Talk 111461 chapter 9:12: the skill was «app modernization», renamed
  *App Resizability* in Xcode 27.1, now covers SwiftUI.) I cannot run it here — **[not verified]
  what it reports for this repo**; it is step 1 of § 5.
- Window-level sizing tools: Device Hub's iOS resizable simulator can test sizes that no real
  model has — the best candidate to **measure** Duo-like windows before a Duo simulator is
  scripted (the audit report notes that `simctl` cannot set an arbitrary window size).

---

## 3. Checklist for this app

Baseline facts about the app [repo]:

- iPhone only, **portrait only**: `TARGETED_DEVICE_FAMILY = 1`, `UISupportedInterfaceOrientations
  = Portrait` (`Config/iOS.xcconfig:6,16`); deployment target 26.0; no `UIRequiresFullScreen`;
  no multiple-scenes key.
- No size class is read anywhere in `Packages/` (`horizontalSizeClass` / `verticalSizeClass` /
  `userInterfaceIdiom` — zero hits). Layout is computed from `GeometryReader` / `onGeometryChange`
  — a good base, matching Apple's «layout calculations from scene or view bounds» advice.
- Only `UIScreen.main` uses: the two below. `UIScreenEdgePanGestureRecognizer` appears in
  `EdgeBackHost.swift` and `CardStackPull.swift` — that is a gesture, not `UIScreen`.
- 40 `ignoresSafeArea` calls; **safe-area use is almost only vertical** (`safe.top`,
  `safe.bottom`); `leading`/`trailing` are only added to `size` in `MapScreenView.swift:113`
  and `SunARScreen.swift:65`.

### 3.1 First experiment (before any code): build the current app with Xcode 27.1 and look

Cost: small. Everything below is a hypothesis until this is done.

- Build unchanged with the 27.1 SDK, run in the Duo simulator, capture every pose of the four
  tabs, the card, the form, AR, and each sheet.
- Record, per pose: window size, safe-area insets (all four edges), size classes, what happened
  to the custom tab bar and the Light timebar, whether the inner display shows the portrait-only
  app as portrait, letterboxed, or landscape (resolves the contradiction in § 1.1).
- Run the App Resizability skill and compare its list with § 3.2–3.9.

### 3.2 Replace `UIScreen.main` (2 places) — small

Apple: the symbol is deprecated since iOS 26.0, «use a UIScreen instance found through context …
`view.window.windowScene.screen`, or for properties like `UIScreen.scale` with trait
equivalents, use a traitCollection found through context»
(<https://developer.apple.com/documentation/uikit/uiscreen/main>). The Duo «prepare» page says:
«Get scale from the trait collection. Use `traitCollection.displayScale` in UIKit … Don't store
a UIScreen.» Talk 111461 shows `UIScreen.main.scale` → `traitCollection.displayScale`.

| File | Line [repo] | Now | Change |
|---|---|---|---|
| `Packages/LightPlanUI/Sources/LightPlanUI/Screens/SunAR/MilkyWayPano.swift` | 289 | `window?.screen.scale ?? UIScreen.main.scale` inside `PanoSkyUIView.redraw()` | `traitCollection.displayScale` |
| `Packages/LightPlanUI/Sources/LightPlanUI/Screens/SunAR/MilkyWayGaiaRenderer.swift` | 473 | same, inside `GaiaSkyUIView.redraw()` | same |

Notes:

- Both already prefer the window's screen, so on a single-display phone behaviour is unchanged.
  The fallback is the only `UIScreen.main` read, and it fires only when the view has no window
  (nothing to present to anyway).
- A trait collection that is not in a hierarchy may report scale 0 (general UIKit behaviour, not
  from the Apple pages above — **[not verified]**): keep a guard (`scale > 0`, else skip the draw
  — `redraw()` already starts with `guard … bounds.width > 0`).
- Apple: «Re-read the size whenever it changes … a fold can resize your app in the middle of a
  session.» Both views already redraw from `layoutSubviews()` (lines 280 and 466), which covers
  size changes. Moving between the two displays could also change the scale (not stated by
  Apple whether the two displays share a scale — **not verified**); cheap insurance is to
  register for the display-scale trait change and call `redraw()`.
- Other screen reads found by grep: none. `PlannerPartDay.swift:388` uses
  `UIApplication.shared.connectedScenes … isKeyWindow` for a debug section-cut journal — not a
  `UIScreen` use; fine as is.

### 3.3 The custom tab bar «Свет / Карта / Съёмки / Настройки» — large, needs a decision

What it is [repo]: `App/TabBarView.swift` is a hand-drawn `HStack` of four buttons, 84 pt tall
(`TabBarView.height`, line 24) on system glass, mounted by `RootView.swift:164–173` as
`.safeAreaInset(edge: .bottom)` and hidden while a layer (card, gallery, docs, AR, …) is open.
It exists on purpose: the product decision of 23 Sept 2026 («Панель вкладок — вид прототипа на
встроенном стекле», in `light_plan:Light_Plan/DECISIONS.md`, quoted in the file's header) replaced
the system `TabView` that 19б had used. The four screens stay alive in a `ZStack` and are
shown/hidden by opacity (`RootView.swift:60–66`, `screen(_:)` at line 242).

What Apple says [Apple]: the system presents bars vertically only for bars supplied by
navigation containers («If the system doesn't present your bars vertically, check that you're
using the bar support that navigation containers, such as a tab view or navigation stack,
provide… instead of creating a custom bar based on UIToolbar, UINavigationBar, or UITabBar»,
guide, *Optimize bars for vertical presentation*). Talk 111462 (<https://developer.apple.com/videos/play/tech-talks/111462/>):
«content from sub-components like UIToolbar, UINavigationBar, or UITabBar won't be considered»
for custom bars. So **the hand-drawn bar will not move to the side by itself.** Rebuilt with the
27.1 SDK it would stay horizontal at the bottom of a screen that is «wider and shorter», next to
a vertical system strip it knows nothing about.

Options:

| | A. System `TabView` / `Tab` | B. Keep the custom bar, make it axis-aware |
|---|---|---|
| How | `TabView { Tab(...) }`; optionally `.defaultTabBarPlacement(.sidebar)` (27.0) so the inner display gets a sidebar; overflow/compression via `.toolbarVerticalCompressionBehavior(_:)` (27.1) | Read `@Environment(\.toolbarVerticalEdge)` (27.1; `HorizontalEdge?`, «nil … where the system never places a vertical bar», described by Apple as the value to «position custom bars … relative to the system's bar placement»). `nil` → today's horizontal bar. Non-nil → the same four items as a vertical rail on that edge, inside a leading/trailing `safeAreaInset`; UIKit twin: `UITraitCollection.verticalBarEdge` |
| Gets for free [Apple] | Vertical placement, status-bar/Island/camera avoidance, side swap in Split View, overflow menu, RTL-stable side, inner-display sidebar | Keeps the 23-Sept look and the web parity (`shotNode("tab.*")` pairs) |
| Costs | Loses the web-parity look the product owner explicitly asked for on 23 Sept; the 19б system bar was already rejected. Screenshot pairs `tab.*` stop matching. Large | We re-implement placement the system would do: which edge, avoiding the status bar/Island strip, bottom alignment, overflow, Split View. Whether a custom view along that edge automatically gets the right safe-area inset from the vertical status bar is **[not verified]** — measure in § 3.1. Deviates from the HIG advice «In general, don't override the default bar placement». Medium–large |
| Risk | Visual regression; behaviour tied to 27.x APIs | Drift from system behaviour in future OS versions; every layer that reads `TabBarView.height`, `bottomInset` or the `tabbar` node (Map dock, bin circle `BinFlight.swift:14` = 84 + 26, undo bar, `Shell` insets) must learn «no bottom bar» |

Recommendation: finish § 3.1 first, then take **B** if the vertical strip's safe-area inset is
delivered to custom views, because it honours the standing decision and is cheaper to roll
back; fall back to **A** if B needs to guess hardware geometry. This is Alexey's product call
(§ 6, Q1) — the document does not make it.

Either way, before Duo, two independent fixes from the audit apply (it found them on the Pro
line, and they bite harder on a 678-pt-tall outer display): the bar is a fixed 84 pt instead of
«content 50 + measured home-indicator inset» (audit П2), so on a screen with no home strip it
wastes ~34 pt (`TabBarView.swift:24`, `RootView.swift:164–172`).

### 3.4 Light screen: day strip + slider panel — medium

What it is [repo]: `LightScreenView.swift:77` mounts `TimebarView` as
`.safeAreaInset(edge: .bottom, spacing: 8)`. `TimebarView` (`Timebar/TimebarView.swift`) is a
`VStack`: edges row (sunrise · «now» · sunset, 19 pt) → **day strip** (`RibbonView`, 30 pt
drum/lane, only in «Астро» mode) → **slider** (`ScrubView`), padded 24 pt on each side. The
Map tab reuses the same object in its dock (`MapScreenView.swift:41,593`: `timebarTop`).

Apple's position [Apple]: bars should be the system's, but content controls belong to the
content: «Locate controls near the content they affect» (HIG). This is **not** a navigation bar,
so it should **not** be turned into a vertical bar; it should stay a horizontal control at the
bottom of the content area and cope with three new things:

1. **A vertical strip on one side (closed / inner landscape).** The timebar pads a fixed 24 pt
   and its background spans the full width. If the strip contributes a trailing (or leading)
   safe-area inset to the scene — **[not verified]**, see § 3.1 — the `VStack` inside a
   `safeAreaInset` will be inset by SwiftUI automatically, but the fixed 24 pt and the full-width
   hairline/background need checking. Safe-area use must handle each side independently
   (talk 111461: «avoid assuming insets on opposite sides are equal»). Fix pattern: pad with
   `max(24, safeAreaInsets.leading)` / `trailing` read via `onGeometryChange`, not a constant.
2. **Height.** On the outer display in landscape the vertical size class is compact. The
   timebar (about 96 pt per the audit; with the ribbon about 38 pt more) plus the 84-pt tab bar
   can take ~180–220 pt. If the tab bar goes to the side (§ 3.3) only the timebar remains.
   `LightScreenView` already scrolls (`ScrollView` + `.scrollBounceBehavior(.basedOnSize)`), so
   content survives; the real risk is the dome/readout pushed out of sight. Measure.
3. **The fold.** Partially folded «like a book», the fold crosses the middle of a full-width
   slider. Apple: keep each interactive view on one side of a division; interactive elements
   should «nudge aside»; scrolling content need not. Options, cheapest first:
   (a) leave it and test whether the thumb is usable across the curve; (b) use
   `GeometryProxy.reservedRegions(kind: .division)` (27.1) in the view that positions the
   timebar — if a division is active and vertical (`frame.height > frame.width`, Apple's own
   test) put the timebar entirely in the trailing half (the bottom half when the fold is
   horizontal — the «laptop» pose, where Apple says interactive controls belong in the bottom
   region); (c) use `ArrangementView` (27.1) for the whole screen: primary = dome + readout,
   secondary = telemetry list; Apple says it must sit **outside** a scroll view and a navigation
   split view, so it would replace the current outer `ScrollView` structure — large, optional,
   Q3.

`RibbonView` / `ScrubView` already take their widths from a `GeometryReader`
(`RibbonView.swift:40`, `ScrubView.swift:25`), so they should stretch to 669 pt. Fixed sizes
inside them are small drawing constants (lens window 50 × 27, knobs 9–11 pt, 34 × 4) and are not
screen-dependent. One thing to look at on a wide window is `DomeView`: `height = 240` and a
`meet` fit of the 390 × 240 viewBox (`DomeView.swift:46–56`, `DomeFit` at ~485) — it will not
break, but on 669 pt it stays 390 pt wide in the middle with empty bands at the sides.

### 3.5 Other bottom/overlay structures that assume «bottom bar + portrait» — medium

| Where [repo] | Assumption | Duo concern |
|---|---|---|
| `MapScreenView.swift:112–120` | `size = g.size + safe.leading + safe.trailing`; dock top = measured `timebarTop` minus readout; map canvas full-bleed; header uses `safe.top`, bottom items `safe.bottom` | Controls («кружки», name bar, header) are positioned against the full width; with a strip on one side they can sit under it. Use `safeAreaInsets.leading/trailing` for foreground controls and keep the canvas full-bleed (Apple: foreground in the safe area, background extends — talk 111461, 6:06). Canvas overlays «hit-testable over the canvas eat pan» (CLAUDE.md) — new rail/rect overlays must stay out of that |
| `SunARScreen.swift:65–66, 80, 181, 449–456` | Panel at `size.height - panelHeight - max(safe.bottom, 12)`; buttons at `safe.top + 8`; layers popover list is a fixed 320 pt wide `VStack` (`SunARLayersButton.swift:115`) with no height ceiling (audit П3: overlaps the bottom panel by 44 pt at 667 pt height — a Duo outer-display height) | Add scrolling + a height ceiling; read side insets |
| `RootView.swift:164–183` | `bottomInset` is the only inset read; `windowHeight = size.height + safe.top + safe.bottom` | Keep; add `leading/trailing` where foreground content is positioned |
| `UndoBar`, `BinTarget` (`BinFlight.swift:9–14`: bin circle at tab-bar height 84 + 26) | Bottom-anchored to a horizontal tab bar | Depends on § 3.3 outcome |
| `MbFly`, shell overlays using `.ignoresSafeArea()` | Window-space coordinates | Re-check on a wider window |

### 3.6 Edge-back gesture — small–medium (check, likely small)

`EdgeBackHost.swift:40–44` attaches one `UIScreenEdgePanGestureRecognizer` with `edges = .left`
to the window; `CardStackPull.swift:217` also references it. On Duo in Split View the **left**
app's controls sit on the **left** edge (HIG), where a system vertical bar's buttons and this
gesture would compete; and on the outer display the strip is on the **right**, so the left-edge
gesture is unaffected. Verify with the existing `-LPEdgeBackLog` / `make`-tools that the left
edge swipe still begins and that taps on a left-edge vertical bar are not stolen. No Apple page I
read says anything about edge-pan interaction with the vertical bar — **[not verified]**.

### 3.7 Fixed sizes and size assumptions in `Screens/**` — small each

Grep of `.frame(width:/height: ≥150)` plus the audit's list. None is a device-model check
(no `bounds.height == 844`-style tests and no idiom/orientation tests exist). They are fixed
**widths** that were chosen against a 393–440 pt window:

| File:line [repo] | Size | Duo comment |
|---|---|---|
| `Screens/SunAR/SunARLayersButton.swift:115` | popover list `width: 320` | OK on 466 pt; needs height ceiling (above) |
| `Screens/SunAR/SunARCalibration.swift:53, 164` | 220 × 108 and 260 wide cards | OK widths; centre on the safe area, not the full window |
| `Screens/Card/CardQuest.swift:52` | QR `232 × 232` | OK; the sheet height is `min(contentHeight, windowHeight * 0.86)` (`:179`) — good pattern |
| `Screens/Org/OrgCardScreen.swift:145` | field `height: 190` | OK |
| `Screens/Map/MapSpots.swift:538` | spot menu `minWidth: 216, maxWidth: 280`, ≤ 320 high (comment at `:507`) | Check next to a strip |
| `Screens/Moodboard/MoodboardSheets.swift:80` | `.height(min(height, 700))` | 700 pt exceeds a 678-pt window (audit «мелочи»); use a window fraction |
| `Screens/Form/FormKit.swift:349, 447` | `.height(400/468)`, `.height(300)` | Same remark; sheet detents on the outer display move vertical bars to the side (guide, *Sheets*) |
| `Screens/Form/FormScreen.swift:54, 90` | top bar `padding(.top, 46)` + `ignoresSafeArea(.container, edges: .top)` (audit П1; lines checked) | Wrong on every phone already; on Duo the top area is the camera/status region — read the real inset |
| Initial `@State` guesses tied to 17 Pro Max | `RootView.swift:240` (956), `FormScreen.swift:24`, `CardQuest.swift:124`, `MapScreenView.swift:20–28, 68`, `LightPlanMapCanvas/MapKitCanvas.swift:17` (440; the Mac canvas), `EdgeBack.swift:52` (390) | One frame only before the first measurement; harmless but should be neutral |
| Month plate `PlannerMonthView.swift:99` (`cellHeight` 58) and day grid (`DayLanes.hourHeight` 38, `PlannerDay.swift:54`) | Fixed cell **heights**; the audit also claims a fixed 347-pt month plate width — I did not re-verify that | If the plate really has a fixed width it becomes an island on a 669-pt inner display; decide stretch vs. two columns (Q3) |

Not fixed-size problems but still «portrait-shaped»: `GeometryReader` is used in 25 files
(listed in the grep: `RootView`, `Timebar/*`, `Screens/{Light,Map,SunAR,Planner,Card,Moodboard,
Form,Settings}`, `Dome/DomeView`, `App/BinFlight`). Each should be spot-checked for a
`min(width, height)`-style assumption — the existing audit tool is the way (§ 4.4).

### 3.8 AR (camera + motion) is hard-wired to portrait — medium, needs a decision

[repo] `SunARLens.swift:38–44, 479–480`: preview connection `videoRotationAngle = 90`
(«Портрет, кадр заполняет окно целиком»); `SunARCamera.swift:131`: frame output at angle 0 and a
fixed `aspectFillPortrait` mapping; attitude from `CMDeviceMotion` with
`.xTrueNorthZVertical` (`Data/Motion/DeviceAttitude.swift:162,214`). On the outer display
(portrait, honours the orientation list) this is the same as today. On the inner display —
which is wider than tall in landscape and, per Apple, does not follow the supported-orientation
list — the camera image and the sky projection need the interface orientation / window shape.
Apple's guidance is to derive shape from bounds, not from `UIInterfaceOrientation`. Whether
Apple provides an AR/camera-specific route for iPhone Duo beyond «Choosing a camera by the
direction it faces» (<https://developer.apple.com/documentation/avkit/choosing-a-camera-by-the-direction-it-faces>)
I did not read — **[not verified]**. Light Plan uses only the rear camera.
Safe default until measured: keep AR portrait-shaped (centre a portrait-aspect lens in the
window) or hide the AR entry on the inner display. Decision: Q2.

### 3.9 System presentations — small

Sheets, alerts, popovers, context menus adjust to the fold and the strip by themselves
(Apple). The app has about 25 `sheet`/`fullScreenCover`/`popover` call sites; the `FormCover`
full-screen cover (`RootView.swift:266`) and the shell layers
(`BackZ`, `.zIndex` stack) are custom and need the same side-inset check as § 3.5. On the
outer display Apple makes sheet bars vertical by default; a sheet with one close button can opt
out with `.toolbarVerticalBehavior(.disabled)` (27.1, with the warning not to toggle it per
state). Light Plan's sheets use their own header buttons, not `.toolbar`, so they probably will
not turn vertical at all (matches the § 3.3 caveat) — **[not verified]**.

### 3.10 Items that do **not** need work (to avoid busywork)

- No `UIDevice.current.orientation`, `statusBarOrientation`, `interfaceOrientation`,
  `userInterfaceIdiom` anywhere in `Packages/` (grep).
- Hinge API, camera capture accessory, multiple scenes: not applicable (single scene, rear
  camera only).
- `ConcentricRectangle` / corner configuration: nice-to-have for the glass bar corners;
  optional, not a blocker.

---

## 4. App Store Connect and the screenshot plan

### 4.1 Requirements [Apple]

Source: <https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications>
(read 2026-10-21; row «iPhone Duo»):

- **Outer display:** 1398 × 2034 px (portrait) · 2034 × 1398 px (landscape).
- **Inner display:** 2007 × 2853 px (portrait) · 2853 × 2007 px (landscape).
- At least 1 and up to **10** screenshots per device size; `.jpeg` / `.jpg` / `.png`; **no alpha
  channel or transparency** (page-wide rules).
- «Starting in April 2027, screenshots will be required for any app using the iOS 27.1 SDK or
  later.» (same page, Notes column). Submitting Duo screenshots shows an «optimized for iPhone
  Duo» badge.
- App previews (video): accepted resolutions 886 × 1920 (portrait) and 1920 × 886 (landscape)
  for Duo (<https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications>).
  Previews are optional; not part of the plan unless Alexey wants one.
- App Store Connect has a new **preview tool** that shows screenshots and metadata on the Duo
  product page. <https://developer.apple.com/news/?id=kkphp5qo>

Discrepancies and gaps to resolve before April 2027:

- The **news post** says «Starting April 2027, all submitted apps and games must include iPhone
  Duo screenshots»; the **spec page** says required «for any app using the iOS 27.1 SDK or
  later». These are not the same condition (all apps vs. 27.1-SDK apps). Plan for the
  stricter reading; ask Apple / watch the page. **[not verified]**
- Whether **both** displays (outer *and* inner) and **both** orientations are required, or one
  size suffices: the page lists four sizes under one heading and does not say. The generic rule
  on the page is that the highest required resolution is scaled down automatically if the UI is
  the same across sizes — it does not say whether Duo can be derived from another iPhone's
  shots. **[not verified]**
- Existing rule (unchanged): «At least one screenshot for iPhone with Dynamic Island (medium
  display)» stays the base requirement.

### 4.2 What this app can honestly show

The product is portrait-only today. Honest content per size:

- **Outer, portrait (1398 × 2034):** the app as designed for a phone — the cheapest set; also the
  pose that proves the vertical bar.
- **Inner, portrait (2007 × 2853) and landscape (2853 × 2007):** only meaningful after § 3.4–3.8
  work, and only if Alexey decides how the app uses a 669-pt-wide window (Q3). A stretched phone
  layout would be an honest but weak showcase and Apple's own advice is «You don't want just a
  stretched out iPhone app» (talk 111466).

### 4.3 Shot plan (proposal)

Screens, in the order they sell the product (existing `shotNode` scenarios and seed data —
Barnaul, 23 Sept 2026 — in `Tools/shots/README.md` are reused so frames are reproducible):

| # | Screen | Why | Outer portrait | Inner portrait | Inner landscape |
|---|---|---|---|---|---|
| 1 | «Свет» (Просто) — dome, readout, timebar | The hero | yes | yes | yes |
| 2 | «Свет» (Астро) — ribbon open, details | Shows depth | optional | yes | optional |
| 3 | «Карта» — instrument over the map (needs network for tiles; or the offline backdrop used by `make shots`) | The differentiator | yes | yes | yes |
| 4 | «Съёмки» — month / week | Planning | yes | yes | optional |
| 5 | Card of a shoot | Daily use | yes | optional | — |
| 6 | AR (`make shots ARGS="--screens ar"`, synthetic camera) | The wow shot; subject to Q2 | yes | decide | decide |
| 7 | Partially folded «book» pose of screen 1 or 3, if the layout adapts to the fold | Proves Duo adaptation | — | only if § 3.4(b)/(c) is built | — |

Rule: no more than ~6 per size; screenshots 1, 3, 4 first (they must carry the «optimized for
iPhone Duo» story); never show a pose where the app is clipped or sits in the middle of the
display.

### 4.4 How to produce them (and the unknowns)

- Capture: Device Hub's **Screenshot** button «captures the screenshot at the full resolution
  of the simulated or physical device» and saves to the Desktop (<https://developer.apple.com/documentation/xcode/capturing-screenshots-and-videos-from-devices>).
  Whether the full resolution of the Duo simulator equals the pixel sizes in § 4.1, or needs
  scaling/cropping (a [blog] on the same URL as § 1.2 suspects the inner capture may differ),
  is **[not verified]** — check the first capture against § 4.1 before building a pipeline.
- Poses: use the Closed / Open buttons and rotate in Device Hub; fold angle with Option-drag
  (Apple, *Interacting with your app in Device Hub*). Apple documents no scriptable pose
  control; `devicectl` covers install/launch/files on devices and `simctl` starts simulators
  (<https://developer.apple.com/documentation/xcode/interacting-with-devices-using-the-command-line>).
  Whether `simctl` can create/boot/screenshot the Duo model and set the pose is
  **[not verified]** — first command to run on the Mac: `xcrun simctl list devicetypes | grep -i duo`.
- Existing tooling [repo]: `Tools/sim.js` clones **iPhone 17 Pro Max** into `LP <branch>` and
  `make shots` / `Tools/shots/pair.js` drive scenarios by launch arguments; the audit tool
  `Tools/audit_heights/run.js` (branch `wt/audit-heights`) takes per-model snapshots and node
  rectangles. Extending `sim.js` with a Duo base is small *if* `simctl` knows the device,
  otherwise screenshots are manual in Device Hub with the same launch arguments (`-LPShot…`,
  `ShotScenario`) — fine for ≈15 images.
- Do the screenshots last: after layout fixes and after the Xcode 27.1 build is what ships.
- Export check: no alpha channel, exact pixel sizes, PNG; a one-line script (`sips -g
  pixelWidth -g pixelHeight`, `file`) before upload.

---

## 5. Effort and order

Sizes: small = up to a couple of hours, medium = about a day, large = several days.

| # | Item | Size | Depends on | Notes |
|---|---|---|---|---|
| 0 | Xcode 27.1 + Duo simulator on the Mac; `simctl list devicetypes` | small | — | Alexey's Mac; blocks everything measurable |
| 1 | Build current app with the 27.1 SDK; run the Duo simulator; run the App Resizability skill; fill § 1.2 with measured numbers; capture a «before» set | small | 0 | § 3.1. All later estimates are revised here |
| 2 | Replace the 2 × `UIScreen.main` (+ optional trait-change redraw) | small | — | § 3.2; can be done and merged before the SDK bump |
| 3 | Audit fixes П1 (form top inset), П3 (AR list scroll + ceiling), the sheet-height constants; П2 (bar = 50 + measured inset) | small each; П2 small–medium | — | They are Pro-line bugs that Duo's short outer display makes worse; independent of Duo APIs |
| 4 | Read side insets for foreground controls on Map/AR/shell overlays | medium | 1 | § 3.5 |
| 5 | Tab bar decision and implementation (A or B) | large | 1, Q1, Q4 | § 3.3 |
| 6 | Light timebar: side-inset padding, height check, optional fold displacement | medium (fold: +small) | 1, 5 | § 3.4 |
| 7 | Edge-back and gestures check | small | 5 | § 3.6 |
| 8 | AR on the inner display | medium | Q2 | § 3.8 |
| 9 | Inner display design: sidebar tab placement, two-column «Свет», month plate stretch, `ArrangementView` | large (optional) | Q3, 5 | Not needed for the April 2027 requirement; needed for a good inner-display story |
| 10 | Remove «portrait only» (`Config/iOS.xcconfig:16`) or keep it | small to change; the layout work is item 9 | Q3 | Config lives in `Config/*.xcconfig` only (CLAUDE.md) |
| 11 | Screenshots (§ 4) + upload + preview-tool check | medium | all above | Last |
| 12 | Check Apple's page again in early 2027 for the exact requirement | small | — | § 4.1 discrepancies |

Order of work: 0 → 1 → 2 and 3 in parallel (merge on their own) → 4 → 5 → 6 → 7 → 8 → decide 9/10 → 11.
Hard date: April 2027 (screenshots). Soft date: 2026-10-23 (device on sale; the app already
runs there, it just does not look good).

Minimum viable «not embarrassing on Duo»: items 0–3, 5, 6, 7, 11 with portrait kept. That is
mostly one large and a few small/medium pieces.

---

## 6. Open questions for Alexey

1. **Tab bar.** On Duo the hand-drawn bar will not move to the side. Do we (A) go back to the
   system `TabView` on all phones and lose the look decided on 23 Sept, or (B) keep the drawn bar
   and teach it to stand vertically on Duo only? My lean is B, after a measurement on the
   simulator.
2. **AR on the inner display.** Keep AR portrait-shaped inside the big window, hide it on the
   inner display, or build a landscape-aware version? (No Duo device, no landscape mock-ups
   exist — CLAUDE.md says landscape is deferred.)
3. **How much to design for the inner display now?** Minimum: the phone layout simply gets wider
   (dome in the middle, month plate as an island). Next level: sidebar tab placement, two-column
   «Свет» (dome + readout | telemetry), a fold-aware timebar. You said landscape iPad/Duo waits
   for mock-ups and the next stable Xcode; Xcode 27.1 is now out — does that lift the wait, and
   do you want mock-ups first?
4. **Deployment target.** Most Duo APIs are iOS 27.1. Keep 26.0 and gate with
   `#available(iOS 27.1, *)`, or raise the target? Your iPhone 15 Pro Max can run iOS 27, but
   a raise drops iOS 26 users. (The App Store requirement applies to apps built with the 27.1
   SDK, not to apps that deploy on 27.1.)
5. **Portrait-only.** Keep `UISupportedInterfaceOrientations = Portrait`? On the outer display
   Apple suggests supporting landscape («people may want to set the phone down like a tent»).
6. **Store assets.** Do you want the badge and screenshots for both displays, or the minimum
   Apple lets us get away with? (Needs the answer from § 4.1: which sizes are mandatory.)
7. **Device access.** Is there any chance of a real iPhone Duo for the final check
   (Apple calls the simulator «the best way to test the full native experience» but physical
   behaviour — fold feel, strip position — is only certain on the device)?
8. **Decisions record.** If Q1–Q4 are answered, they go into `DECISIONS.md` (append-only,
   native decisions go there too).

---

## 7. Sources

### 7.1 Read in full (all fetched 2026-10-21)

- HIG «Designing for iPhone Duo» (2026-09-09) —
  <https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo>
  (via `…/tutorials/data/design/human-interface-guidelines/designing-for-iphone-duo.json`)
- News «Prepare and submit your apps for iPhone Duo» (2026-10-05) — <https://developer.apple.com/news/?id=kkphp5qo>
- Guide «Preparing your app for iPhone Duo» —
  <https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo>
  (the URL under `documentation/uikit/` returns 404; the Technology Overviews path is right)
- «Three steps to make your app shine on iPhone Duo» (Apple's «prepare» page, includes the
  resizability skill) — <https://developer.apple.com/iphone-duo/prepare/>; hub page <https://developer.apple.com/iphone-duo/>
- API pages (platform tables read for availability):
  [`ReservedRegion`](https://developer.apple.com/documentation/swiftui/reservedregion),
  [`UIView.ReservedRegion`](https://developer.apple.com/documentation/uikit/uiview/reservedregion),
  [`ArrangementView`](https://developer.apple.com/documentation/swiftui/arrangementview),
  [`UIArrangementViewController`](https://developer.apple.com/documentation/uikit/uiarrangementviewcontroller),
  [`ToolbarVerticalCompressionBehavior`](https://developer.apple.com/documentation/swiftui/toolbarverticalcompressionbehavior),
  [`toolbarVerticalCompressionBehavior(_:)`](https://developer.apple.com/documentation/swiftui/view/toolbarverticalcompressionbehavior(_:)),
  [`toolbarVerticalBehavior(_:)`](https://developer.apple.com/documentation/swiftui/view/toolbarverticalbehavior(_:)),
  [`toolbarVerticalEdge`](https://developer.apple.com/documentation/swiftui/environmentvalues/toolbarverticaledge),
  [`verticalBarEdge`](https://developer.apple.com/documentation/uikit/uitraitcollection/verticalbaredge),
  [`axisBehavior(_:)`](https://developer.apple.com/documentation/swiftui/toolbarcontent/axisbehavior(_:)),
  [`ToolbarItemVisibilityPriority`](https://developer.apple.com/documentation/swiftui/toolbaritemvisibilitypriority),
  [`ToolbarOverflowMenu`](https://developer.apple.com/documentation/swiftui/toolbaroverflowmenu),
  [`topBarPinnedTrailing`](https://developer.apple.com/documentation/swiftui/toolbaritemplacement/topbarpinnedtrailing),
  [`defaultTabBarPlacement(_:)`](https://developer.apple.com/documentation/swiftui/view/defaulttabbarplacement(_:)),
  [`GeometryProxy.safeAreaInsets`](https://developer.apple.com/documentation/swiftui/geometryproxy/safeareainsets),
  [`UIHingeInteraction`](https://developer.apple.com/documentation/uikit/uihingeinteraction) (page exists, iOS 27.1; only title/abstract read),
  [`UIScreen.main`](https://developer.apple.com/documentation/uikit/uiscreen/main)
- Xcode: [Device Hub](https://developer.apple.com/documentation/xcode/device-hub),
  [Interacting with your app in Device Hub](https://developer.apple.com/documentation/xcode/interacting-with-your-app-in-device-hub),
  [Capturing screenshots and videos from devices](https://developer.apple.com/documentation/xcode/capturing-screenshots-and-videos-from-devices),
  [Managing … devices in Device Hub](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub),
  [Interacting with devices using the command line](https://developer.apple.com/documentation/xcode/interacting-with-devices-using-the-command-line)
- Tech Talks (transcripts): 111461 «Prepare your app for iPhone Duo», 111462 «Raise the bar with
  iPhone Duo», 111463 «Strike a pose with adaptive layouts on iPhone Duo», 111464 «Leverage
  multiple displays and scenes on iPhone Duo», 111466 «Design for iPhone Duo» —
  `https://developer.apple.com/videos/play/tech-talks/<id>/`. (111465, camera, skimmed only for
  keywords.)
- App Store Connect: [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications),
  [app preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications)
- [blog] <https://blakecrosley.com/blog/iphone-duo-day-two> — read only for the point-size
  question, flagged as an estimate.

### 7.2 Could not read / not verified

- `onHingeChange` (SwiftUI) page — guessed path 404; described only in talk 111464.
  `UIHingeInteraction` described there too; only its title page was read.
- `sceneAccessory` page (404 at the guessed path); camera-capture-accessory page not read in full.
- «Choosing a camera by the direction it faces» — not read.
- WWDC26 «Modernize your UIKit app» (where the resizability skill first appeared) — not read.
- The Duo simulator and Xcode 27.1 themselves — no Xcode in this session; every behaviour claim
  about the *app* on Duo is a hypothesis to test (§ 3.1).
- Points/scale of both displays (§ 1.2); whether both displays are required for screenshots and
  the exact April-2027 condition (§ 4.1); whether `simctl` can drive a Duo simulator (§ 4.4).
- Release notes for Xcode 27.1 / iOS 27.1 — not searched.
