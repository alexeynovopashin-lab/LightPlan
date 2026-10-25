#!/bin/bash
# Iteration 30b probe: what a widget extension and a Live Activity can do on the free team.
# Results: docs/30b_widget_cut.md. Registers nothing with Apple: no -allowProvisioningUpdates anywhere.
#
#   Spikes/WidgetSpike/probe.sh sim      build, install, run the Live Activity scenarios, print the shared log
#   Spikes/WidgetSpike/probe.sh device   iphoneos build unsigned (compiles?) and signed (which profiles are missing?)
#   Spikes/WidgetSpike/probe.sh log      print the shared log (the widget writes there too)
#   Spikes/WidgetSpike/probe.sh lock     30б.3а: start the lock-screen probe on the simulator, press «+1 час» and «Студия» by launch argument, print the log
#   LP_SPIKE_PHONE=yes Spikes/WidgetSpike/probe.sh phone   30б.3а: signed build + install on iPhone ALno (registers 2 App IDs) — ONLY on Alexey's word
#
# The widget itself runs only once it is in the gallery or on the home screen: long-press the
# home screen, «+», «Spike30b», «Добавить виджет»; then `probe.sh log` shows its `snapshot` / `timeline` lines.
# By hand: `-LA phase` (staleDate after 20 s; does the island switch to «до конца»? It did not in 35 s).
# Simulator: LP_SIM or this branch's own (`node Tools/sim.js`). DerivedData: $DD or the system temp folder.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
ID=Novopashin.LightPlan.spike30b
DD="${DD:-${TMPDIR:-/tmp}/lp-widget-spike-dd}"
sim() { node "$root/Tools/sim.js" | awk -F' · ' '{print $NF}' | tail -1; }
log_path() { echo "$(xcrun simctl get_app_container "$1" "$ID" groups | cut -f2)/spike.log"; }
launch() { xcrun simctl launch --terminate-running-process "$S" "$ID" "$@" > /dev/null; }
home() { xcrun simctl launch "$S" com.apple.Preferences > /dev/null; }  # sends the spike to the background

python3 "$here/make_project.py" --check > /dev/null || { echo "WidgetSpike.xcodeproj differs from make_project.py — rerun it"; exit 1; }
case "${1:-sim}" in
sim)
    S="$(sim)"
    xcrun simctl boot "$S" 2> /dev/null; xcrun simctl bootstatus "$S" -b > /dev/null
    xcodebuild -project "$here/WidgetSpike.xcodeproj" -scheme Spike30b -destination "id=$S" \
        -derivedDataPath "$DD" build > /tmp/cc-spike-sim.log 2>&1 || { grep -m5 'error:' /tmp/cc-spike-sim.log; exit 1; }
    xcrun simctl install "$S" "$DD/Build/Products/Debug-iphonesimulator/Spike30b.app"
    : > "$(log_path "$S")"
    echo "· start in the foreground, then end";  launch -LA start; sleep 4; launch -LA end; sleep 2
    echo "· request 8 s after launch, app sent home at 3 s"; launch -LA bgstart; sleep 3; home; sleep 30
    launch -LA end; sleep 2
    echo "· start, go home, update every 5 s";   launch -LA bgupdate; sleep 3; home; sleep 35
    launch -LA end; sleep 2
    grep -v 'container=' "$(log_path "$S")"
    ;;
device)
    xcodebuild -project "$here/WidgetSpike.xcodeproj" -scheme Spike30b -destination 'generic/platform=iOS' \
        -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO build > /tmp/cc-spike-dev-unsigned.log 2>&1
    echo "unsigned iphoneos build: exit $?"
    xcodebuild -project "$here/WidgetSpike.xcodeproj" -scheme Spike30b -destination 'generic/platform=iOS' \
        -derivedDataPath "$DD" build > /tmp/cc-spike-dev-signed.log 2>&1
    echo "signed iphoneos build without registration: exit $?"
    grep -o "No profiles for '[^']*' were found" /tmp/cc-spike-dev-signed.log | sort -u
    ;;
log)
    S="$(sim)"; grep -v 'container=' "$(log_path "$S")"
    ;;
lock)
    S="$(sim)"
    xcrun simctl boot "$S" 2> /dev/null; xcrun simctl bootstatus "$S" -b > /dev/null
    xcodebuild -project "$here/WidgetSpike.xcodeproj" -scheme Spike30b -destination "id=$S" \
        -derivedDataPath "$DD" build > /tmp/cc-spike-sim.log 2>&1 || { grep -m5 'error:' /tmp/cc-spike-sim.log; exit 1; }
    xcrun simctl install "$S" "$DD/Build/Products/Debug-iphonesimulator/Spike30b.app"
    : > "$(log_path "$S")"
    echo "· start the activity";            launch -LA probe; sleep 4
    echo "· «+1 час» by launch argument";   launch -LA plus; sleep 3
    echo "· studio mode by launch argument"; launch -LA studio; sleep 3
    launch -LA end; sleep 2
    grep -E 'probe|notice' "$(log_path "$S")"
    ;;
phone)
    # The signed build registers `spike30b` and `spike30b.Widget` (2 of the free team's 10 new App IDs per 7 days).
    [ "${LP_SPIKE_PHONE:-}" = yes ] || { echo "phone: only on Alexey's word — rerun with LP_SPIKE_PHONE=yes"; exit 2; }
    DEV=5A94DA8F-B9E0-5DB8-BECF-14F387CFE24F   # iPhone ALno. Not «iPhone Elena».
    xcodebuild -project "$here/WidgetSpike.xcodeproj" -scheme Spike30b -destination "platform=iOS,id=$DEV" \
        -derivedDataPath "$DD" -allowProvisioningUpdates build > /tmp/cc-spike-phone.log 2>&1 \
        || { grep -m8 -E 'error:|No profiles' /tmp/cc-spike-phone.log; exit 1; }
    xcrun devicectl device install app --device "$DEV" "$DD/Build/Products/Debug-iphoneos/Spike30b.app" > /tmp/cc-spike-install.log 2>&1 \
        || { tail -3 /tmp/cc-spike-install.log; exit 1; }
    xcrun devicectl device process launch --device "$DEV" "$ID" > /dev/null 2>&1 || echo "installed; phone locked? open «LP 30b-3a» by hand"
    echo "on iPhone ALno: «LP 30b-3a» ($ID) from $(git -C "$root" rev-parse --short HEAD)"
    ;;
*) sed -n '2,14p' "$0"; exit 2 ;;
esac
