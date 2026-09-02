#!/bin/sh
# # x-ash -- a POSIX shell on x-lang
#
# ## tests/spec-gate.sh -- the bundle's shim
#
# @description Sources the PLATFORM's spec gate; vendors nothing.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
#     ., .,
#     {O,O}
#     (   )
#      " "
#
# THE SAME RULING AS tools/check/release-refs.sh, and this file is the case
# that proved it right: three bundles carried a byte-identical copy differing
# only in the name on line 2, and the trap bug -- a killed suite that could
# report SUCCESS -- had to be fixed in all three on the same day.  The kit's
# copy (x-lang#564) is the one that keeps the fix; v0.10.0 is the first
# release to carry it, which is the release this bundle pairs with.
#
# X_LANG_KIT names a checkout's tools/lang-kit directly -- what CI uses,
# having checked x-lang out already; otherwise the kit is found where x says
# its share tree is.  Unlike release-refs this gate RUNS the suite, so an x
# is needed either way -- the fallback costs nothing extra.
set -e

BUNDLE="$(cd "$(dirname "$0")/.." && pwd)"
export BUNDLE

if [ -n "$X_LANG_KIT" ]; then
	KIT="$X_LANG_KIT"
else
	X="${X:-x}"
	command -v "$X" >/dev/null 2>&1 || {
		echo "x-ash: no x on PATH, and X_LANG_KIT is unset." >&2
		echo "  Set X=/path/to/x.sh, or X_LANG_KIT=/path/to/x-lang/tools/lang-kit" >&2
		exit 1
	}
	KIT="$("$X" --share-dir)/tools/lang-kit"
fi

[ -f "$KIT/spec-gate.sh" ] || {
	echo "x-ash: no spec-gate.sh under $KIT" >&2
	echo "  The lang kit ships it as of x-lang v0.10.0; this bundle declares which release." >&2
	exit 1
}

. "$KIT/spec-gate.sh"
