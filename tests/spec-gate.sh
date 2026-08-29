#!/bin/sh
# # x-ash -- a POSIX shell on x-lang
#
# ## tests/spec-gate.sh -- the suite, judged against recorded failures
#
# @description Runs the spec suite and compares its failures to
#   tests/contract/known-failures.txt.  Green when they match exactly.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
#     ., .,
#     {O,O}
#     (   )
#      " "
#
# WHY THIS EXISTS.  spec-runner.sh exits non-zero on any failure, which is
# right for a developer at a prompt and wrong for a gate: a bundle carrying
# honest, documented debt is then permanently unreleasable, and release.yml
# refuses to publish anything ever.  The choice that leaves is between fixing
# every last spec before the first release and making the gate advisory, and
# neither is good.
#
# So the gate asks a better question than "did anything fail".  It asks whether
# what failed is what we said would fail.
#
# BY NAME, NOT BY COUNT.  A budget of "9 failures" is satisfied by fixing one
# and breaking another, which is the exact event a ratchet is for.  This
# compares the SET of failing test names, so a swap is caught.
#
# BOTH DIRECTIONS ARE RED.  A failure that is not recorded is a regression.  A
# recorded failure that now passes is a fix that nobody wrote down, and leaving
# it listed would quietly re-authorise the failure later.  x-lang's
# percent-globals gate takes the same line, and for the same reason: an
# unrecorded gain is budget someone can spend without noticing.
#
# Set X to point at a particular x; otherwise the one on PATH is used.  Every
# variable spec-runner.sh honours (X_BIN, SPEC_PATH, ...) is honoured here,
# because this runs that script rather than reimplementing it.
set -e

BUNDLE="$(cd "$(dirname "$0")/.." && pwd)"
CONTRACT="${KNOWN_FAILURES:-$BUNDLE/tests/contract/known-failures.txt}"

[ -f "$CONTRACT" ] || {
	echo "spec-gate: no contract at $CONTRACT" >&2
	exit 2
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM

# The runner exits non-zero on failures, which is the whole reason this wrapper
# exists -- so its status is captured rather than allowed to end the script.
# `set -e` would otherwise kill us before we could read the output.
status=0
sh "$BUNDLE/tests/spec-runner.sh" > "$work/out" 2>&1 || status=$?
sed 's/\x1b\[[0-9;]*m//g' "$work/out" > "$work/clean"
cat "$work/clean"

# A suite that did not run is not a suite that passed.  Without this a crash
# before the first spec produces no FAIL lines, matches an empty diff against a
# contract listing none, and reports green -- the worst possible answer.
totals=$(sed -n 's/^\([0-9][0-9]*\) tests,.*/\1/p' "$work/clean" | tail -1)
if [ -z "$totals" ] || [ "$totals" = 0 ]; then
	echo "" >&2
	echo "spec-gate: FAIL -- the suite reported no totals line, so it did not run" >&2
	echo "  runner exited $status; its output is above" >&2
	exit 1
fi

sed -n 's/^FAIL: //p' "$work/clean" | sort -u > "$work/actual"
grep -v '^[[:space:]]*#' "$CONTRACT" | grep -v '^[[:space:]]*$' | sort -u > "$work/known"

comm -23 "$work/actual" "$work/known" > "$work/new"
comm -13 "$work/actual" "$work/known" > "$work/fixed"

echo ""
echo "spec-gate: $totals tests, $(wc -l < "$work/actual" | tr -d ' ') failed, $(wc -l < "$work/known" | tr -d ' ') recorded"

rc=0
if [ -s "$work/new" ]; then
	echo "" >&2
	echo "spec-gate: REGRESSION -- these failed and are not recorded:" >&2
	sed 's/^/    /' "$work/new" >&2
	rc=1
fi

if [ -s "$work/fixed" ]; then
	echo "" >&2
	echo "spec-gate: these are recorded as failing but PASS now:" >&2
	sed 's/^/    /' "$work/fixed" >&2
	echo "  remove them from $(basename "$CONTRACT") -- the list may only shrink," >&2
	echo "  and a fix left unrecorded re-authorises the failure later." >&2
	rc=1
fi

[ "$rc" = 0 ] || exit 1

echo "spec-gate: ok -- the failures are exactly the recorded ones"
