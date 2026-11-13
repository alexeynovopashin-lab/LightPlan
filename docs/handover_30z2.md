# Handover 30з.2 («Свет»: небо, плашки, капсула) — branch `claude/30z-2-light-sky-plates-93d5b9`

Base: `wt/30z-1-light-layout @ e6a5ccd`. All work is wip, **not pushed**. On Alexey's phone now: slot B
(`Novopashin.LightPlan.slotB`, home-screen name «LP claude/30z-2-light-sky-plates-93d5b9») = build of the last
commit before this note (`4c3a489`, plus this file). No measurement runs were made (no `make lightfit`, `make shots`,
`checkstep`, no `swift test`); numbers below come from simulator reports (`-LPShotReport`) read by a throw-away script.

## Status per queued item

| Item | State | Where / what is left |
|---|---|---|
| Sky wider than the dome, vignette (top corners ×2) | done | `Screens/Light/LightSkyBackdrop.swift`; `DomeView.skyFill` (dome no longer paints its base gradient on «Свет»). Vignette dark 0.62 corners (top ≈0.86), light 0.14 (top ≈0.26). Night in light theme fades to page colour (`presence`). |
| Three glass plates «сейчас» / «условия» / «время» | done | `Theme/Plate.swift` (`glassPlate`, `GlassPlateTokens`), `LightScreenView.nowPlate`, `LightSpoilerView.plate`, `TimebarView(plate:)`. Plate 3 has `hush 0.7` (page tone under glass) because content now scrolls under it. |
| «Подробно» sections each its own plate | done | `LightSpoilerView(plated: true)`; «Карта» uses the same view with `plated = false` (old look). |
| Capsule «Запланировать съёмку» in the «условия» plate | done | Empty plate bottom = `LightSpoilerView.capsuleSlot` 56 + `plateInset` 4 → 10 above/below the button, plate's rounded bottom right under it. |
| Button fixed while scrolling | done (verified in simulator, expanded + scrolled) | `CapsuleAnchor` + `PlateProbe` (end of `LightScreenView.swift`). `rest` = plate bottom in scroll-view coordinates, updated ONLY when scroll offset is 0 (`onScrollGeometryChange` → `atRest`). Capsule bottom = `rest - 10`, clamped to `viewport - 10`. |
| No overlap at rest (definitive rule) | **partly** | Works on 15 Pro Max (430×932) and 17 Pro Max (440×956) in Simple/Pro/Astro, both themes. **iPhone 14 (390×844) does not fit**: short by 22 pt (Pro/Astro) and 66.5 pt (Simple). See table and options. |
| Astro shortening back (`shortensByHeight = true`) | done | `LightCollapsedList` in `LightScreenView.swift`; `refreshCollapsedRows` now plans with `actionHeight = capsuleSlot + plateInset (60)` and `room = visibleHeight − plateProbe.contentTop`. Rows Тени/Небо/Ветер go under «Подробно». Then strip 22→34 (`extraTuck`), then dome lift ≤ 30 pt (`maxDomeLift`, `domeLift` state, applies in Simple too). `LightCollapsedListTests` untouched (rules `plan`/`shown` unchanged) — not run. |
| «↺ Сейчас» right-aligned | done (seen in simulator) | `TimebarView` overlay `.topTrailing`, right edge on the plates' content edge (16 inside plate). Gap above plate 3 = `TimebarView.nowGap` 50 pt, button 34 pt → 8 pt to each side. Own glass (`NowGlass`). |
| Black selected segments in light | done | `WebSeg` (`Settings/SettingsLook.swift`) and `ClientsSeg` (`Org/ClientsScreen.swift`): light → `PlateTokens.blackFill` + white text; `segOn` token and its tests untouched. Seen in simulator on Настройки (mode switch). Not looked at: Организации, client card, music/units segments, but same two structs. |
| No shadows in light | done | `PlateTokens.lightShadowsOn = false` (plateStyle/raisedStyle), `blockShadow` helper (month plate, moodboard covers/strip, undo bar), `flatGlass` clips the built-in glass shadow to the shape in light (plates, capsule, «Сейчас»). Capsule gets a 1 pt `hair4` edge in light. **Left on purpose:** arc/disc shadows in `DomeView` (light), knob shadows (`Timebar/GlassOptics`), drag-lift shadows, glyph shadows. |
| Scroll only when content exceeds the screen | done (checked) | Collapsed + fits (15 Pro Max Astro): a swipe changes zero pixels. Bottom inset is applied only when «Подробно» is open (`plateProbe.grouped`): `max(0, viewport − rest) + 58`. `.scrollBounceBehavior(.basedOnSize)` kept. Where it does not fit (iPhone 14) the page scrolls — expected. |
| «рассвет/закат» captions + bigger icons | done | `baseLabel`, keys `light.baseRise/baseSet` in `Tools/lang_native.json` (5 languages) and catalog rebuilt with `make lang`. Icon 28, time 13, caption 12, centre number 28. Stack centre clamped ≥ 40 pt from plate edges (390 pt screens). |
| 30з.3 (light from under the «сейчас» plate) | **not started** | Waits for Alexey. Ghost sun already shows through the plate glass (`DomeView.overflow`). Backdrop (`LightSkyBackdrop`) already fades the sky into page colour 64 pt below the horizon — put the glow there. |

## At-rest numbers (simulator, golden hour 18:50, forecast on, Barnaul seed; dark = light)

pt; negative = overlap. «Нехватка» = scroll bottom − plate bottom (negative = plate runs under the gap).

| Model | Mode | Rows | last→btn top | btn bottom→plate bottom | plate bottom→«Сейчас» top | «Сейчас»→«время» | Нехватка |
|---|---|---|---|---|---|---|---|
| 15 Pro Max | Simple | 7 | 9.5 | 10 | 9 | 8 | +1 |
| 15 Pro Max | Pro / Astro | 4 | 10 | 10 | 20 | 8 | +12 |
| 17 Pro Max (earlier build, no lift) | Simple | 7 | 9.5 | 10 | 8.5 | 8 | +0.5 |
| 17 Pro Max | Pro / Astro | 4 | 10 | 10 | 41 | 8 | +33 |
| iPhone 14 | Simple | 7 | −57 | 76.5 | −58.5 | 8 | −66.5 |
| iPhone 14 | Pro / Astro | 4 | −12 | 32 | −14 | 8 | −22 |

(«Сейчас» geometry is computed from constants: gap 50, button 34; the button itself only appears after a scrub and was seen
in the simulator once, right-aligned. «last» for Simple = bottom of last row value + 9.5.)
Scroll frame heights: 17 Pro Max 645, iPhone 14 548 (frame excludes safe top; screen window height 860 / 763).

## Open decisions (iPhone 14, smallest supported)

After rows→0, strip 12, dome lift 30 pt it is still 22 pt short (Pro/Astro). Options: (1) compact tokens on short screens:
`nowGap` 50→44, `capsuleSlot` 56→52, plate-1 bottom 10→6 and block 72→68, plate gap 8→6 (≈ −22 pt, enough for Pro/Astro);
(2) Simple has no «Подробно», so 7 rows cannot be tucked: hide Небо/Ветер there on short screens, or accept scrolling;
(3) scale the dome instead (up to −44 pt, biggest visual change: readout positions are in viewBox units); (4) declare iPhone 14
out of scope for the at-rest rule. My advice: (1) for Pro/Astro and decide (2) with Alexey.

## Traps hit

- `ScrollView` frame starts at the safe-area top; `contentInsets.top` was NOT usable as the content origin (gave 62 although the
  frame already starts at 62). Use the plate's own viewport frame at offset 0 (`PlateProbe`), never `contentInsets`.
- `@Observable` writes during scroll re-render every reader: `PlateProbe.rest` is written only at offset 0; `vp/contentMax/atRest` are
  `@ObservationIgnored`.
- A scroll view draws content under a `safeAreaInset` (that is why content shows under the gap and plate 3). A `.mask` to cut it
  gave hard cuts / fades Alexey rejected; do not bring masks or gradients back. Content peeking in the 8 pt strip below plate 3 (above
  the tab bar) is the known side effect.
- Generic `View` struct with `static let` stored properties does not compile (`LightSpoilerView` is non-generic, `above` is `AnyView`).
- `.glassEffect` shadow is outside the shape: `flatGlass` (clipShape) removes it; dark theme left as is.
- `make phone` picked slot B (A busy); phone locked → «стоит, но не запустилось» is normal, open the icon by hand.
- Sims created for this: `LP claude-30z-2-light-sky-plates-93d5b9` (17 Pro Max), `LP t15pm`, `LP t14` (delete when done);
  build products in the scratchpad DerivedData only.
- Script that produced the table: scratchpad `table.py` (not in repo): launches each model×mode×theme with `-LPShotReport`, reads nodes
  `light.scroll`, `plate.cond`, `spoiler`, `action`, `timebar`, `tele.*`. Nodes added: `light.scroll`, `plate.cond`, `edge.cap`.

## Files touched

`Screens/Light/{LightScreenView,LightSpoilerView,LightSkyBackdrop}.swift`, `Dome/DomeView.swift`, `Theme/Plate.swift`,
`Timebar/TimebarView.swift`, `Screens/Settings/SettingsLook.swift`, `Screens/Org/ClientsScreen.swift`,
`Screens/Planner/{PlannerMonthView,PlannerLayers}.swift`, `Screens/Moodboard/{MoodboardTiles,MoodboardStrip}.swift`,
`Tools/lang_native.json`, `Resources/Localizable.xcstrings` (generated).
