#!/bin/sh
# # x-ash -- a POSIX shell on x-lang
#
# ## tests/spec-gate.sh -- the bundle's shim
#
# @description Sources the platform's spec gate; vendors nothing.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
#     ., .,
#     {O,O}
#     (   )
#      " "
#
# The gate lives in the lang kit, not in this repo: the platform maintains one
# copy (x-lang#564, from v0.10.0) so a fix reaches every bundle at once.
# X_LANG_KIT names a checkout's tools/lang-kit directly -- what CI uses, having
# checked x-lang out already; otherwise the kit is found where x says its share
# tree is. This gate runs the suite, so an x is needed either way.
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
