# native — Light Plan in Swift

**Reply to Alexey in Russian.** This file is English (tokens). Workspace rules
(`ws:CLAUDE.md`) apply; this file adds to them.

## Where things are

- Architecture: `light_plan:Light_Plan/docs/17_NATIVE_ARCHITECTURE.md`.
  Plan by iterations: `light_plan:Light_Plan/SWIFT_MIGRATION_PLAN.md` — do only
  the iteration you were asked for; every iteration ends with a commit named in
  its «Checkpoint».
- Product decisions: `light_plan:Light_Plan/DECISIONS.md` (append-only; native
  decisions go there too). The web PWA in `light_plan:Light_Plan/` is the
  parity reference; don't edit it from here.
- Git: local only, no remote (decided 2026-09-19). Nothing to push.

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
- Structure changes to `LightPlan.xcodeproj` (targets, phases, package refs):
  propose in text, Alexey does them in Xcode. Never read the pbxproj in full.
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
