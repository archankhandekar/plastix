#!/bin/sh
# Screenshots of every DEBUG route-harness screen, for design review.
#
# Builds the Debug app for the simulator, installs it, then launches it once per route,
# appearance and text size with the harness arguments (-UIRoute ...) and saves
# build/screens/<route>-<appearance>-<size>.png. Every launch uses fresh temporary roots and
# the wiped "RouteHarness" UserDefaults suite, never real study data; each launch's log line
# (with the temporary roots) is kept in build/screens/logs/ and gathered in
# build/screens/harness.log. It ends with the contact sheet and the copy guard.
#
# Usage: sh scripts/screens.sh [route-name ...]
#   With names, only those rows of the routes table are shot (for example: sh scripts/screens.sh home mark).
# Environment: UDID (simulator), SCHEMES (default "light dark"), SIZES (default
#   "large xxxLarge accessibility3"), SETTLE (seconds to wait before each shot, default 3).
# Needs: Xcode, xcodegen, uv (the contact sheet runs with uv run --with pillow).

set -u

cd "$(dirname "$0")/.." || exit 2

UDID="${UDID:-1DBAA185-213F-4245-A30E-87BB25080697}"
SCHEMES="${SCHEMES:-light dark}"
SIZES="${SIZES:-large xxxLarge accessibility3}"
SETTLE="${SETTLE:-3}"
OUT=build/screens

[ -f Config/Local.xcconfig ] || cp Config/Local.xcconfig.example Config/Local.xcconfig
BUNDLE=$(sed -n 's/^PRODUCT_BUNDLE_IDENTIFIER *= *//p' Config/Local.xcconfig | tr -d ' ' | head -n 1)
[ -n "$BUNDLE" ] || BUNDLE=org.research.symmetry.SymmetryPrototype

xcodegen generate || exit 1
mkdir -p build
if ! xcodebuild build -project SymmetryPrototype.xcodeproj -scheme SymmetryPrototype -configuration Debug \
    -destination "id=$UDID" -derivedDataPath build/dd CODE_SIGNING_ALLOWED=NO > build/screens-build.log 2>&1; then
    grep -E "error:" build/screens-build.log | sort -u | head -n 40
    echo "screens: build failed, see build/screens-build.log" >&2
    exit 1
fi

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1 || true
xcrun simctl install "$UDID" build/dd/Build/Products/Debug-iphonesimulator/SymmetryPrototype.app || exit 1
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryLevel 100 || true

rm -rf "$OUT"
mkdir -p "$OUT/logs"
: > "$OUT/crashes.txt"
abs_out="$(pwd)/$OUT"

FILTER="$*"
# True when no route names were given, or when $1 is one of them.
wanted() {
    [ -z "$FILTER" ] && return 0
    for w in $FILTER; do [ "$w" = "$1" ] && return 0; done
    return 1
}

count=0
while IFS='|' read -r name args <&3; do
    [ -n "$name" ] || continue
    wanted "$name" || continue
    for s in $SCHEMES; do
        for t in $SIZES; do
            shot="$name-$s-$t"
            xcrun simctl ui "$UDID" appearance "$s" < /dev/null
            # shellcheck disable=SC2086
            launched=$(xcrun simctl launch --terminate-running-process \
                --stdout="$abs_out/logs/$shot.log" --stderr="$abs_out/logs/$shot.err" \
                "$UDID" "$BUNDLE" -UIStatic 1 -UIScheme "$s" -UITextSize "$t" $args < /dev/null 2>&1)
            pid=$(printf '%s\n' "$launched" | sed -n 's/^.*: *\([0-9][0-9]*\)$/\1/p' | tail -n 1)
            sleep "$SETTLE"
            if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
                echo "$shot: not running after launch ($launched)" | tee -a "$OUT/crashes.txt"
            fi
            xcrun simctl io "$UDID" screenshot "$OUT/$shot.png" > /dev/null 2>&1 < /dev/null \
                || echo "$shot: screenshot failed" | tee -a "$OUT/crashes.txt"
            count=$((count + 1))
            echo "screens: $shot"
        done
    done
done 3<<'ROUTES'
notice|-UIRoute notice
sessions|-UIRoute sessions
sessions-study|-UIRoute sessions -UISeedStudy 1
home|-UIRoute home
home-complete|-UIRoute home -UIState complete
symmetry|-UIRoute symmetry -UIStage 1
symmetry-nipple|-UIRoute symmetry -UIStage 1 -UIFocus nippleHeight
symmetry-midline|-UIRoute symmetry -UIStage 1 -UIFocus nippleMidline
symmetry-fold|-UIRoute symmetry -UIStage 1 -UIFocus foldHeight
symmetry-outlines|-UIRoute symmetry -UIStage 1 -UIFocus outlines
symmetry-s2-signflip|-UIRoute symmetry -UIStage 2 -UIFocus nippleHeight
symmetry-missingfold|-UIRoute symmetry -UIStage 2 -UIState missingFold
symmetry-nooutlines|-UIRoute symmetry -UIStage 2 -UIState noOutlines
symmetry-blurredkept|-UIRoute symmetry -UIStage 1 -UIState blurredKept
obliques|-UIRoute obliques -UIStage 1
obliques-wipe|-UIRoute obliques -UIStage 1 -UIObliqueMode wipe
obliques-switch|-UIRoute obliques -UIStage 1 -UIObliqueMode switch
stages|-UIRoute stages
compare|-UIRoute compare
capture|-UIRoute capture -UIStage 4
capture-oblique|-UIRoute capture -UIStage 4 -UICaptureAngle leftOblique
photocheck|-UIRoute photocheck -UIStage 4
photocheck-retake|-UIRoute photocheck -UIStage 4 -UIPracticeRetake 1
review|-UIRoute review -UIStage 1
mark|-UIRoute mark -UIStage 3
mark-truth|-UIRoute mark -UIStage 3 -UIShowTruth 1
mark-s1|-UIRoute mark -UIStage 1 -UIShowTruth 1
export-practice|-UIRoute export
export-study|-UIRoute export -UISeedStudy 1 -UIDemo 0
settings|-UIRoute settings
explainer|-UIRoute explainer
newsession-reserved|-UIRoute newSession -UIStudyCode DEMO-7
newset|-UIRoute newSet
gallery|-UIRoute gallery
ROUTES

xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl status_bar "$UDID" clear 2>/dev/null || true
cat "$OUT"/logs/*.log 2>/dev/null | grep 'RouteHarness:' > "$OUT/harness.log" || true
echo "screens: $count screenshot(s) in $OUT; harness log lines in $OUT/harness.log"

status=0
if [ -s "$OUT/crashes.txt" ]; then
    echo "screens: some launches did not stay up, see $OUT/crashes.txt" >&2
    status=1
fi

uv run --with pillow python3 scripts/contact-sheet.py "$OUT" "$OUT/contact-sheet.png" || status=1
sh scripts/check-copy.sh || status=1
exit $status
