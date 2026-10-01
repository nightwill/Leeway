#!/usr/bin/env bash
# Builds, notarizes and publishes a Leeway release on GitHub, together with the
# Sparkle appcast that installed copies read their updates from.
#
#   scripts/release.sh 1.0.1 [release-notes.md]
#
# The tag is the version — the build phase reads it — so it has to be on HEAD
# and pushed before this runs; the script never moves a tag itself. It needs:
#   - a notarytool profile in the Keychain, named by NOTARY_PROFILE
#     (`xcrun notarytool store-credentials notary --apple-id … --team-id DR3DF4J982`);
#   - the Sparkle signing key in the Keychain under the SPARKLE_ACCOUNT account;
#   - gh, signed in.
# Release notes, when given, go both to the GitHub release and into the appcast,
# where Sparkle shows them in its update window.
set -euo pipefail

VERSION="${1:?usage: scripts/release.sh <version> [release-notes.md]}"
NOTES="${2:-}"
: "${NOTARY_PROFILE:=notary}"
: "${SPARKLE_ACCOUNT:=leeway}"
REPO="nightwill/Leeway"
APP_NAME="Leeway"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() { echo "error: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

###############################################################################
step "Checking the tag"

[ -z "$(git status --porcelain)" ] || fail "the working tree has uncommitted changes"
[ "$(git describe --tags --exact-match HEAD 2>/dev/null)" = "$VERSION" ] \
    || fail "HEAD is not tagged $VERSION"
REMOTE_COMMIT="$(git ls-remote origin "refs/tags/$VERSION^{}" | cut -f1)"
[ -n "$REMOTE_COMMIT" ] || REMOTE_COMMIT="$(git ls-remote origin "refs/tags/$VERSION" | cut -f1)"
[ "$REMOTE_COMMIT" = "$(git rev-parse HEAD)" ] \
    || fail "tag $VERSION on GitHub is missing or points elsewhere: git push origin $VERSION"
! gh release view "$VERSION" -R "$REPO" >/dev/null 2>&1 || fail "release $VERSION already exists"
[ -z "$NOTES" ] || [ -f "$NOTES" ] || fail "no release notes at $NOTES"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/leeway-release.XXXXXX")"
DIST="$WORK/dist"
mkdir -p "$DIST"

###############################################################################
step "Building"

OUTPUT_ROOT="$WORK" ./scripts/build_and_export.sh
APP="$(find "$WORK" -maxdepth 2 -name "$APP_NAME.app" -type d | head -1)"
[ -d "$APP" ] || fail "the export produced no $APP_NAME.app"
BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[ "$BUILT_VERSION" = "$VERSION" ] || fail "the app says $BUILT_VERSION, not $VERSION"

###############################################################################
step "Notarizing"

# notarytool takes an archive; the app it vouches for is stapled and zipped again.
ditto -c -k --keepParent "$APP" "$WORK/notarize.zip"
xcrun notarytool submit "$WORK/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose=2 "$APP"

###############################################################################
step "Signing the update"

ZIP="$APP_NAME-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$DIST/$ZIP"
[ -z "$NOTES" ] || cp "$NOTES" "$DIST/$APP_NAME-$VERSION.md"

GENERATE_APPCAST="$(ls -t "$HOME"/Library/Developer/Xcode/DerivedData/"$APP_NAME"-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast 2>/dev/null | head -1)"
[ -x "$GENERATE_APPCAST" ] || fail "generate_appcast not found — resolve the Sparkle package in Xcode first"

# The appcast lists this release alone: Sparkle only needs the newest one, and
# it lives with the release, so the feed URL in Info.plist follows the latest.
"$GENERATE_APPCAST" \
    --account "$SPARKLE_ACCOUNT" \
    --download-url-prefix "https://github.com/$REPO/releases/download/$VERSION/" \
    --embed-release-notes \
    -o "$DIST/appcast.xml" \
    "$DIST"
grep -q 'sparkle:edSignature' "$DIST/appcast.xml" || fail "the appcast carries no EdDSA signature"

###############################################################################
step "Publishing"

NOTES_ARGS=(--generate-notes)
[ -z "$NOTES" ] || NOTES_ARGS=(--notes-file "$NOTES")
gh release create "$VERSION" "$DIST/$ZIP" "$DIST/appcast.xml" \
    -R "$REPO" \
    --verify-tag \
    --title "$APP_NAME $VERSION" \
    "${NOTES_ARGS[@]}"

echo
echo "Released $APP_NAME $VERSION: https://github.com/$REPO/releases/tag/$VERSION"
echo "Build files: $WORK"
