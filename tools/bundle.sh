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
# THE STAMP IS THE ONE THING THE COMMIT CANNOT CARRY.  Everything else in
# this archive is exactly what was committed, deliberately -- but a version
# row in lang.xon could only be true at the single commit that gets tagged,
# and would be a lie in the tree both before and after it.  So the tag says
# what this is, and the archive carries that as a file the checkout has not
# got, matching what `make install` writes from git describe.
#
# git archive --add-file (2.38+) keeps the determinism: entries are sorted
# and stamped with the COMMIT's time, added ones included.  The one thing it
# takes from the local file is its MODE, so that is pinned -- otherwise two
# rollers with different umasks produce different bytes, which is precisely
# the failure the -n on gzip below exists to prevent.
STAMP=$(mktemp -d)/version
trap 'rm -rf "$(dirname "$STAMP")"' EXIT
printf '%s\n' "$TAG" > "$STAMP"
chmod 644 "$STAMP"

# Probed with the REAL stamp, not with /dev/null: git rejects a non-regular
# file for being non-regular, which looks exactly like not supporting the
# option at all and quietly drops the stamp from every tarball.
if git archive "--add-file=$STAMP" --format=tar "$TAG" >/dev/null 2>&1; then
	ADD_STAMP="--add-file=$STAMP"
else
	ADD_STAMP=""
	echo "bundle: git $(git --version | sed 's/.* //') has no --add-file (needs 2.38);" >&2
	echo "  the tarball will carry no version stamp, so a consumer's" >&2
	echo "  (requires-lang \"...\" \"$TAG\") cannot be checked against it." >&2
fi

git archive --format=tar --prefix="$NAME/" $ADD_STAMP "$TAG" \
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
