# Handover 30з.2а («Свет»: пульт в плашке «время», плашки как у месяца, два вида) — branch `claude/30z-2a-light-console-07cbb0`

Base: `claude/30z-2-light-sky-plates-93d5b9 @ 5e794f1`. wip, **not pushed**. On Alexey's phone: slot B «LP claude/30z-2a-light-console-07cbb0».
No `make lightfit/shots/checkstep`, no full test suite (only `swift test --filter SettingsTests` in LightPlanData: green).

## What changed
- **Пульт.** `TimebarView(plate: true, console:)`: top row of plate 3 = capsule «Запланировать съёмку · время» + round «↺» (40 pt, `consoleRow`).
  «↺» is always there: dim when `!nowButtonVisible`, accent when active, calls `jumpToNow()`. Floating «↺ Сейчас», `nowGap` 50, `NowGlass`,
  `CapsuleAnchor`, `PlateProbe.rest/grouped`, `capsuleSlot` are gone. Gap plate 2 → plate 3 = `plateGap` 8 (clear strip at the top of the bottom inset).
- **Ручка «Подробно»** (`LightSpoilerView.handle`): 28 pt visible, 44 pt hit (`padding(-8)`), caption 12/600 + chevron 12, sits at the bottom edge of plate 2
  (plate bottom inset 0 when the handle exists). Simple: no handle, plate has 4 pt insets.
- **Расчёт строк** (`refreshCollapsedRows`): `limit = plate3Top − plateGap` (both in `viewportSpace`, now set AFTER `safeAreaInset`), `room = limit − contentTop`,
  `tail = 0`. `plate3Top` comes from `onGeometryChange` on the timebar. Plate 2 reports via `LightSpoilerView.onPlate`. `visibleHeight` is only the scroll frame now (no minHeight stretch).
  Trap: the `light.scroll` frame ends at the TOP of the bottom inset (= plate3Top − 8), not at the screen bottom.
- **Плашки как у месяца** (`Theme/Plate.swift`, `glassPlate`): fill `pal.sheetGlass` + `.glassEffect` (clipped: no shadow), edge `hairline` 1 (dark) / white rim 1.5 (light), radius 22. Dark shadow of the month plate NOT taken.
  `GlassPlateTokens.darkVeil` removed.
- **Два вида.** `AppSettings.lightBlocks` (snapshot key `lightView` = `"flat"`; no key = blocks), `LightScreenModel.blocks`, `LightScreenView.body` = `blocksBody | flatBody`
  (flatBody = body of `e6a5ccd`, own `refreshFlatRows`, `actionButton(flat: true)`, `actionReserve`/`nowLift`). TimebarView without `plate` draws the 30з.1 floating «↺ Сейчас» again.
  Settings row «Вид» → «Экран «Свет»» (Pro/Astro chapters only; the Simple sheet has no «Вид»). Launch arg `-LPLightBlocks YES|NO` (not persisted). Strings `set.lightView*` in 5 languages.
- Node `plate.now` added (plate 1). Scripts: scratchpad `table2.py`, `shot.sh` (not in repo).
