#!/bin/sh
# Copy guard for user-facing text in the app target.
#
# Pass 1 looks inside double-quoted string literals in App/SymmetryPrototype/**/*.swift.
# No literal may contain:
#
#   1. any of these case-insensitive, word-bounded terms:
#        better, worse, improve, improved, improvement, normal, abnormal,
#        mm, millimetre, millimeter, percent, percentage, score
#      or a literal percent sign that is not a format conversion (a "%" that is not
#      followed by [-+ #0-9.]*[dfsgxX@l%], so "%.3f", "%d", "%@" and "%%" pass and
#      "12%" fails);
#   2. any of these case-insensitive, word-bounded judging terms:
#        symmetric, asymmetric, symmetrical, asymmetrical, grade, graded, ideal,
#        optimal, target, good, bad, correct, incorrect, accurate, accuracy, success,
#        successful, worsened, deteriorated, excellent, poor
#      (the bare word "symmetry" stays allowed);
#   3. the phrases "more even", "less even", "more balanced", "less balanced",
#      "closer to zero", "closer to equal" or "nearer equal" (copy never compares stages
#      or sides by distance from zero);
#   4. a middle dot (U+00B7, written or as \u{B7}); meta is a short sentence instead;
#   5. an arrow: U+2192, U+2190 or U+21D2 (written or as \u{...}), or the ASCII " ->" /
#      "-> " between words (buttons are verbs with no arrows);
#   6. an ALL-CAPS label: two or more consecutive words of three or more capital letters,
#      such as "PATIENT RIGHT" (single codes such as "IRB", "S-014" and "DEMO-" pass);
#   7. the side badges "L nipple", "R nipple", "L fold", "R fold", "L outline",
#      "R outline" (regex \b[LR] (nipple|fold|outline)\b). L is the reference length, so
#      sides are always "Patient left" / "Patient right" or "Left nipple" / "Right nipple".
#      MetricFormatter's "± %.3f L" formats pass because no such word follows.
#
# Pass 2 looks at code outside string literals: no font below the .subheadline floor,
# that is ".font(.caption)", ".font(.caption2)", ".font(.footnote)" or Font.caption,
# Font.caption2, Font.footnote. Swift Charts axis labels must set .scaleTick explicitly.
#
# Why: this is a research prototype, not a medical device. Nothing on screen may read
# as a clinical judgement (better, worse, normal, good), a physical measurement (mm), a
# percentage, or a single symmetry score. Every number is image geometry with its
# uncertainty, formatted by MetricFormatter.
#
# A line that ends in "// copy-guard: allow" is skipped by both passes (use sparingly,
# for example an identifier string that is never shown; never for user-facing copy).
# Lines that are entirely a "//" comment are ignored. Multi-line ("""), raw (#"..."#) and
# escaped-quote literals are not parsed; keep user-facing copy in plain one-line literals
# so the guard can see it.
#
# Usage: sh scripts/check-copy.sh [directory]   (default: App/SymmetryPrototype)
# Exit status: 0 when clean, 1 with one "file:line: message" per hit.

set -u

root="${1:-App/SymmetryPrototype}"
cd "$(dirname "$0")/.." || exit 2

if [ ! -d "$root" ]; then
    echo "check-copy: directory not found: $root" >&2
    exit 2
fi

hits=0
tmp="${TMPDIR:-/tmp}/check-copy.$$"
trap 'rm -f "$tmp"' EXIT INT TERM

# UTF-8 byte sequences, so awk can run byte-wise under LC_ALL=C.
mdot=$(printf '\302\267')
arrow_right=$(printf '\342\206\222')
arrow_left=$(printf '\342\206\220')
arrow_double=$(printf '\342\207\222')

find "$root" -type f -name '*.swift' | LC_ALL=C sort | while IFS= read -r file; do
    # Pass 1: string literals.
    LC_ALL=C awk -v file="$file" -v mdot="$mdot" -v ar="$arrow_right" -v al="$arrow_left" -v ad="$arrow_double" '
    {
        line = $0
        # Skip explicitly allowed lines and comment-only lines.
        if (line ~ /\/\/[ \t]*copy-guard:[ \t]*allow[ \t]*$/) next
        if (line ~ /^[ \t]*\/\//) next

        rest = line
        while (match(rest, /"[^"]*"/)) {
            lit = substr(rest, RSTART + 1, RLENGTH - 2)
            rest = substr(rest, RSTART + RLENGTH)

            lower = " " tolower(lit) " "
            if (match(lower, /[^a-z0-9_](better|worse|improve|improved|improvement|normal|abnormal|mm|millimetre|millimeter|percent|percentage|score)[^a-z0-9_]/)) {
                word = substr(lower, RSTART + 1, RLENGTH - 2)
                printf "%s:%d: forbidden term \"%s\" in string literal: \"%s\"\n", file, NR, word, lit
                next
            }
            if (match(lower, /[^a-z0-9_](symmetric|asymmetric|symmetrical|asymmetrical|grade|graded|ideal|optimal|target|good|bad|correct|incorrect|accurate|accuracy|success|successful|worsened|deteriorated|excellent|poor)[^a-z0-9_]/)) {
                word = substr(lower, RSTART + 1, RLENGTH - 2)
                printf "%s:%d: judging term \"%s\" in string literal: \"%s\"\n", file, NR, word, lit
                next
            }
            if (match(lower, /[^a-z0-9_](more even|less even|more balanced|less balanced|closer to zero|closer to equal|nearer equal)[^a-z0-9_]/)) {
                word = substr(lower, RSTART + 1, RLENGTH - 2)
                printf "%s:%d: comparing phrase \"%s\" in string literal: \"%s\"\n", file, NR, word, lit
                next
            }
            if (index(lit, mdot) > 0 || match(lower, /\\u\{0*b7\}/)) {
                printf "%s:%d: middle dot in string literal (write a short sentence): \"%s\"\n", file, NR, lit
                next
            }
            if (index(lit, ar) > 0 || index(lit, al) > 0 || index(lit, ad) > 0 ||
                match(lower, /\\u\{0*(2192|2190|21d2)\}/) || index(lit, " ->") > 0 || index(lit, "-> ") > 0) {
                printf "%s:%d: arrow in string literal (buttons are verbs with no arrows): \"%s\"\n", file, NR, lit
                next
            }
            padded = " " lit " "
            if (match(padded, /[^A-Za-z0-9_][A-Z][A-Z][A-Z]+[ \t]+[A-Z][A-Z][A-Z]+[^A-Za-z0-9_]/)) {
                printf "%s:%d: ALL-CAPS label in string literal (use sentence case): \"%s\"\n", file, NR, lit
                next
            }
            if (match(padded, /[^A-Za-z0-9_][LR] (nipple|fold|outline)[^A-Za-z0-9_]/)) {
                printf "%s:%d: side abbreviated to L or R in string literal (write Patient left / Patient right): \"%s\"\n", file, NR, lit
                next
            }

            # A percent sign that is not a format conversion.
            s = lit
            while ((p = index(s, "%")) > 0) {
                after = substr(s, p + 1)
                if (match(after, /^[-+ #0-9.]*[dfsgxX@l%]/)) {
                    s = substr(after, RLENGTH + 1)
                } else {
                    printf "%s:%d: literal percent sign in string literal: \"%s\"\n", file, NR, lit
                    next
                }
            }
        }
    }' "$file"

    # Pass 2: fonts below the floor, in code outside string literals.
    LC_ALL=C awk -v file="$file" '
    {
        line = $0
        if (line ~ /\/\/[ \t]*copy-guard:[ \t]*allow[ \t]*$/) next
        if (line ~ /^[ \t]*\/\//) next
        code = line
        gsub(/"[^"]*"/, "\"\"", code)
        sub(/\/\/.*$/, "", code)
        code = code " "
        if (match(code, /\.font\(\.(caption2?|footnote)[^A-Za-z0-9_]/) || match(code, /Font\.(caption2?|footnote)[^A-Za-z0-9_]/)) {
            printf "%s:%d: font below the .subheadline floor: %s\n", file, NR, substr(code, RSTART, RLENGTH - 1)
        }
    }' "$file"
done > "$tmp"

if [ -s "$tmp" ]; then
    cat "$tmp"
    hits=$(wc -l < "$tmp" | tr -d ' ')
    echo "check-copy: $hits hit(s) in $root" >&2
    exit 1
fi

echo "check-copy: no forbidden copy in $root"
exit 0
