#!/bin/sh
# Copy guard for user-facing text in the app target.
#
# Rule: no string literal in App/SymmetryPrototype/**/*.swift may contain any of these
# case-insensitive, word-bounded terms:
#
#   better, worse, improve, improved, improvement, normal, abnormal,
#   mm, millimetre, millimeter, percent, percentage, score
#
# nor a literal percent sign that is not a format conversion (a "%" that is not followed
# by [-+ #0-9.]*[dfsgxX@l%], so "%.3f", "%d", "%@" and "%%" pass and "12%" fails).
#
# Why: this is a research prototype, not a medical device. Nothing on screen may read
# as a clinical judgement (better, worse, normal), a physical measurement (mm), a
# percentage, or a single symmetry score. Every number is image geometry with its
# uncertainty, formatted by MetricFormatter.
#
# A line that ends in "// copy-guard: allow" is skipped (use sparingly, for example an
# identifier string that is never shown). Lines that are entirely a "//" comment are
# ignored; the check only looks inside double-quoted literals on a line. Multi-line
# ("""), raw (#"..."#) and escaped-quote literals are not parsed; keep user-facing copy
# in plain one-line literals so the guard can see it.
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

find "$root" -type f -name '*.swift' | LC_ALL=C sort | while IFS= read -r file; do
    awk -v file="$file" '
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
done > "$tmp"

if [ -s "$tmp" ]; then
    cat "$tmp"
    hits=$(wc -l < "$tmp" | tr -d ' ')
    echo "check-copy: $hits hit(s) in $root" >&2
    exit 1
fi

echo "check-copy: no forbidden copy in $root"
exit 0
