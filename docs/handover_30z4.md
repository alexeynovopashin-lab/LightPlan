# Handover 30з.4 («Свет»: шкала времени = календарные сутки + по часу с краёв) — branch `claude/30z-4-scale-855204`

Base: `claude/30z-2a-light-console-07cbb0 @ 49918e1`. wip, **not pushed**. Tests run: Core `DayScaleTests`, Timeline `TimelineMachineCalendarTests` (swift test),
UI `Scale30z4Tests` + `LightPlanShootButtonTests` + `LightLayout30z1Tests` + `DomeDragTests` (xcodebuild, simulator, green). Not run: `make lightfit/shots/checkstep`, full suite, light theme, phone check.

## What the scale is now
- `DayScale` (Core `Solar/DayScale.swift`): `.calendar` = window −60…1500 min of the chosen day in the place's time (26 h, same in every city/season; no sun involved);
  `.solar` = the old window `SolarDay.mint…maxt`. `.calendar` is on for `light.timebar` (Light + Map share it, `AppModel`: `scale: .calendar`); AR keeps `.solar` (own `TimebarState`).
- Marks (`DayScale.marks(start:end:)`): hourly ticks −1…25 h; long 0/6/12/18/24, medium 3/9/15/21, short the rest + both ends (23:00, 01:00). Digits 0,3,…,24 are on the same marks (digit x = tick x).
- `TimelineMachine(scale:)` holds `mint/maxt` = the scale window. Crossing the window flips the day by ±1440 (minute stays the same moment). Wind-up fire in `.calendar` keeps the moment
  (right end 01:00 → next day minute 60), not "opposite edge" (that would jump 26 h back). `show(day:minute:)` never moves a minute of the day to a neighbour now.
- `TimebarState`: `scale/scaleStart/scaleEnd/scaleMarks`; click counter uses `hourIndex` (floor) — `Int(m)/60` merged −59…59 into hour 0.
- `RulerView/RulerDigits/ScrubView/PathStops.railGradient` read the scale window, not `solarDay`. Dome drag: arc = the arc the dome draws (moon without arc → solar day), clamp = scale window (`LightScreenModel.domeMinute`).
- Debug `-LPShotKnob <minute>` (negative with a leading space: `-LPShotKnob " -40"`) puts the knob on a minute of the chosen day.

## Readers of `SolarDay.mint/maxt` (all of them) — see the report; `SolarDay` numbers untouched (web parity).
Left on the solar window on purpose: `DomeView` star rotation `(t − sun.mint)`, `DomeView` moon-without-arc fallback `posOn(t, sun.mint, sun.maxt)`, `MapInstrument` core track, `MilkyWayWindow` (Core: a card/list fact),
`TimebarState.riseEdge/setEdge` polar fallbacks, `TimebarState.bounds(offset:)` (unused), `LightTrack.gradient` (unused), `TimelineMachine` default `.solar` (AR, old tests).

## Traps
- `swift test` in `Packages/LightPlanUI` does not build on the Mac host (pre-existing: `PlannerMotionBench`/`PlannerMonthView`); UI tests go through `xcodebuild test -only-testing:LightPlanUITests/<Suite>`.
- `-LPShotKnob -40`: UserDefaults eats the minus — pass `" -40"`.
- The simulator panel was not granted to the executor: shots by `xcrun simctl io … screenshot`, no taps.

## Round 2 (13.11, orchestrator: «переводи AR» + 12 h)
- AR = calendar scale: `TimebarState` default is now `.calendar` (AR passes nothing). Nothing uses `.solar` any more; it stays only as the default of `TimelineMachine`
  (the old mechanics tests are written against the solar window) — not removed on purpose, see `DayScale` doc.
- AR layers in the margins: formulas of absolute time, no change needed. Core test `DayScaleTests.arLayersInTheMargins` (sun, moon, planets, stars, Milky Way core + centre line at −60/−40/1480/1500
  = neighbour day at 1380/1400/40/60); UI test `arUsesTheCalendarScale`; old `SunARTests` (56 tests with the rest) green.
- 12 h rule: `ClockText.is12` (setting `AppSettings.clock` → `ClockPreference`, `.auto` = locale `j` template) — `TimebarState.clock`, fed by `setClockPreference`. Scale digits: `ClockText.scaleLabel(hour:)`
  (hour field + AM/PM field of the app's own `hmm` template, no space; period only at 0/12/24): 12AM,3,6,9,12PM,3,6,9,12AM. `DayScale.Mark.hour` replaced the string digit (`digit` = 24 h text).
- Still 24 h in 12 h mode: only the hour numbers 6/12/18 of the lane ribbon (`RibbonView` line ~158, `Text("\(hour)")`). Seen fine in 12 h: dome clock, plan button, rise/set, golden hour range.
- Simple sheet: item `.clock` after `.units` (`SimpleSheet`, inventory row № 34 moved from «нет» to «есть» in `SimpleSettingsSheetTests`), same `settings.clock`, words `set.clock*` as the chapter, no note under it.

## Round 3 (13.11, «цифры надо починить везде»)
- Leaks of 24 h digits in 12 h mode found by grep (`%02d`, `% 24`, `/ 60 … :`, `DateFormatter`, `Text(date…)`, every `ClockText` user) and fixed: lane ribbon 6/12/18 (`RibbonView`, `TimebarState.hourLabel` =
  `scaleLabel`), hour grid of «Съёмки» day (`PlannerDayView.slot`, `ClockText.hourLine`: «07:00» / «7 AM»), hour digits on the Map instrument arc (`MapInstrument.Input.hourLabel`, 24 h «03», 12 h = `scaleLabel`).
- Left 24 h on purpose: `AppModel+FormTrip.hm24` (machine format of the booking query), durations/countdowns (`StudioHour.clock`, `ColonCount`, `MapSummary.gap`, widget `RemainText`), minute wheel «00…59».
- Widget/Activity: `clock12` comes from the same `settings.clock` (`WidgetShare.makeWidgetFeed`), republished on every `persist()` (which `update` calls).
- Tests: `Scale30z4Tests` gridHourLine, ribbonDigitsFollowTheClock, mapInstrumentHourDigits (xcodebuild, simulator; 32 tests green with AzimuthsSwitch/MapInstrumentFrame).
