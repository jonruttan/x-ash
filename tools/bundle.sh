#!/bin/sh
# # x-ash -- the ASH lang for x-lang
#
# ## tools/bundle.sh -- roll the release tarball, and print the pin it needs
#
# @description Builds x-ash-<tag>.tar.gz from a clean tree and prints the
#   (bundle ...) row a consumer's lang.pin.xon must carry.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
# Usage: sh tools/bundle.sh [TAG] [OUTDIR]
#
# FROM GIT, NOT FROM THE WORKING TREE.  `git archive` ships exactly what is
# committed at the tag: no .git, no generated harness, no editor droppings, and
# nothing a dirty checkout happened to be carrying.  A tarball whose contents
# depend on whose machine rolled it is a tarball whose digest means nothing.
#
# DETERMINISTIC, so two people rolling the same tag get the same bytes and so
# the same digest.  git archive sorts its entries and stamps every file with
# the COMMIT's time rather than the clock; gzip is told -n so it does not
# record a timestamp of its own.  Without that last flag the digest changes
# every run and the pin becomes unverifiable by anyone but the roller.
set -e

cd "$(cd "$(dirname "$0")/.." && pwd)"

TAG="${1:-$(git describe --tags --exact-match 2>/dev/null || echo HEAD)}"
OUT="${2:-dist}"
NAME="x-ash-$TAG"

git rev-parse --verify "$TAG" >/dev/null 2>&1 || {
	echo "bundle: no such commit or tag: $TAG" >&2
	exit 1
}

mkdir -p "$OUT"
# The prefix is a plain directory name so the archive unpacks into one place;
# Pin bundle unpacks into a staging directory it owns, so the prefix is for a
# human untarring it by hand, not for the tool.
git archive --format=tar --prefix="$NAME/" "$TAG" \
	| gzip -n -9 > "$OUT/$NAME.tar.gz"

if command -v shasum >/dev/null 2>&1; then
	DG=$(shasum -a 256 "$OUT/$NAME.tar.gz" | cut -d' ' -f1)
else
	DG=$(sha256sum "$OUT/$NAME.tar.gz" | cut -d' ' -f1)
fi
printf '%s  %s\n' "$DG" "$NAME.tar.gz" > "$OUT/$NAME.tar.gz.sha256"

DECLARED=$(sed -n 's/^(lang "\(.*\)")$/\1/p' lang.xon)
URL="https://github.com/jonruttan/x-ash/releases/download/$TAG/$NAME.tar.gz"

# THE PIN IS AN ARTIFACT, not just something printed for a human to retype.
# `x --install-lang <url>` fetches exactly this file, reads the digest and the
# tarball URL out of it, and installs -- so publishing it beside the tarball is
# what makes a release installable without cloning anything.
{
	printf '(lang "%s")\n' "$DECLARED"
	printf '(release "%s")\n' "$TAG"
	printf '(bundle "sha256:%s" "%s")\n' "$DG" "$URL"
	printf '(source "https://github.com/jonruttan/x-ash.git")\n'
} > "$OUT/lang.pin.xon"

echo "bundle: $OUT/$NAME.tar.gz"
echo "bundle: $OUT/lang.pin.xon"
echo "bundle: $DG"
echo
echo "Install it with:"
echo "  x --install-lang https://github.com/jonruttan/x-ash/releases/download/$TAG/lang.pin.xon"
echo
echo "Or pin it, by putting $OUT/lang.pin.xon in your project:"
echo
sed 's/^/  /' "$OUT/lang.pin.xon"
