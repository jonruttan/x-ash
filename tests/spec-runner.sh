#!/bin/sh
# # x-ash -- a POSIX shell on x-lang
#
# ## tests/spec-runner.sh -- the bundle's runner
#
# @description Sources the platform's spec runner; vendors nothing.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
#     ., .,
#     {O,O}
#     (   )
#      " "
#
# No path reaches into an x-lang source tree; everything comes from x itself.
# --share-dir gives the tree x reads from (repo root in a checkout, share/x
# when installed) and --engine-path gives the engine location after the
# wrapper's discovery order.
#
# Set X to point at a particular x; otherwise the one on PATH is used.
set -e

BUNDLE="$(cd "$(dirname "$0")/.." && pwd)"
X="${X:-x}"

command -v "$X" >/dev/null 2>&1 || {
	echo "x-ash: no x on PATH.  Set X=/path/to/x.sh and retry." >&2
	exit 1
}

# --share-dir answers from any cwd.
X_ROOT="$("$X" --share-dir)"
# X_BIN is env-overridable, the way tests/x/spec-runner.sh makes it -- so the
# same runner can drive a variant or patched engine without moving anything.
X_BIN="${X_BIN:-$("$X" --engine-path)}"

# The platform runner locates its awk harness relative to the engine binary,
# which sits beside tests/ in a checkout but under libexec/x in an install; a
# sourced script cannot portably find its own path, so the caller sets this.
SPEC_RUNNER_DIR="$X_ROOT/tests"
export SPEC_RUNNER_DIR

# The harness is generated, never committed: it embeds two absolute paths
# that are facts of this machine, not of the bundle.
sh "$BUNDLE/tests/gen-harness.sh" "$X_ROOT" "$BUNDLE"

LANG_LIB="$BUNDLE/tests/lib/harness.gen.x"
# SPEC_PATH is env-overridable so a single spec file can be run in isolation
# while diagnosing, without moving anything into the suite.
SPEC_PATH="${SPEC_PATH:-$BUNDLE/tests/specs}"

# The suite boots from a state image of the harness when the platform can
# write one. tools/dev/image-build.sh images a child that loaded the harness,
# keyed on everything it depends on (the harness, the platform's lib/, its
# engine, and ash/), so an edit to any of them rewrites the image and a current
# one is reused. Each spec file then loads the image instead of booting from
# source.
#
# The image writer is a checkout tool: an installed tree has none, and a
# library holding words no image can carry is refused; either way the suite
# boots from source and says so on stderr.
#
# The `Ansi repl-own` probe checks for a specific platform fix rather than a
# version: a platform whose Ansi.install moves a REPL printer it does not own
# takes this bundle's %repl-print away when the image loads (x-lang#655), and
# specs then run on the wrong printer. Boot from source on a platform that
# answers no.
#
# IMG=0 runs the same suite from source, one file per process, for when the
# image is the suspect.
if [ "${IMG:-1}" = 0 ]; then
	SPEC_BATCH="${SPEC_BATCH:-1}"; export SPEC_BATCH
else
	_builder="$X_ROOT/tools/dev/image-build.sh"
	_probe="${TMPDIR:-/tmp}/x-imgprobe.$$.x"
	printf '(Ansi repl-own)\n' > "$_probe"
	_keeps_printer=0
	"$X" -f "$_probe" >/dev/null 2>&1 && _keeps_printer=1
	rm -f "$_probe"
	if [ ! -f "$_builder" ]; then
		echo "x-ash: no image writer at $_builder (not a checkout) -- the suite boots from source" >&2
	elif [ "$_keeps_printer" = 0 ]; then
		echo "x-ash: the platform moves a REPL printer it does not own (x-lang#655) -- the suite boots from source" >&2
	elif X_BIN="$X_BIN" sh "$_builder" "$LANG_LIB" "$BUNDLE/tests/lib/.images" "$BUNDLE/ash"; then
		X_IMG_DIR="$BUNDLE/tests/lib/.images"; export X_IMG_DIR
	else
		echo "x-ash: no state image -- the suite boots from source" >&2
	fi
fi

# The suite bounds itself per snippet on the platform's defaults, like every
# other bundle. It once needed a seam-collect switch, an allocation ceiling and
# a batch width because a type registered on an isolated tokenizer base did not
# survive a collect (x-lang#599); the engine fix (x-engine-c v0.2.7, reaching
# this bundle through x-lang v0.12.0) removed the cause and the knobs with it.

. "$X_ROOT/tests/spec-runner.sh"
