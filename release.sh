#!/bin/bash
# Veröffentlicht einen ausdrücklich gestarteten Release; keine automatische Anmeldung.
# Aufruf: ./release.sh 1.0.1 "Notizen" oder ./release.sh 1.0.1 --notes-file notes.md
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'Aufruf: ./release.sh <x.y.z> ["Notizen"|--notes-file <Datei>]\n' >&2
    exit 2
fi
shift
NOTES_FILE=""
NOTES="**Neue Version**"$'\n\n'"Mischpult $VERSION."
if [[ "${1:-}" == "--notes-file" ]]; then
    [[ "$#" -eq 2 ]] || { printf 'Nach --notes-file wird genau ein Dateipfad erwartet.\n' >&2; exit 2; }
    NOTES_FILE="$2"
    test -f "$NOTES_FILE"
elif [[ "$#" -eq 1 ]]; then
    NOTES="$1"
elif [[ "$#" -gt 1 ]]; then
    printf 'Zu viele Argumente.\n' >&2
    exit 2
fi

REPO="Cramleo234/mischpult"
TAP="$ROOT/../homebrew-public"
CASK="$TAP/Casks/mischpult.rb"
TEMPLATE="$ROOT/packaging/homebrew-public/Casks/mischpult.rb"
for TOOL in gh git swift hdiutil lipo; do
    command -v "$TOOL" >/dev/null || { printf 'Benötigtes Werkzeug fehlt: %s\n' "$TOOL" >&2; exit 1; }
done
gh auth status >/dev/null 2>&1 || { printf 'Bitte selbst im Terminal anmelden: gh auth login\n' >&2; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1
git -C "$TAP" rev-parse --is-inside-work-tree >/dev/null 2>&1
for CHECKOUT in "$ROOT" "$TAP"; do
    if [[ -n "$(git -C "$CHECKOUT" status --porcelain)" ]]; then
        printf 'Bitte Änderungen vor dem Release committen: %s\n' "$CHECKOUT" >&2
        exit 1
    fi
done
# Das Repo ist öffentlich: nie unter dem echten Namen committen.
if [[ "$(git config user.email)" != *"@users.noreply.github.com" ]]; then
    printf 'Bitte vorher die anonyme Commit-Adresse setzen (siehe packaging/RELEASING.md).\n' >&2
    exit 1
fi
if gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1; then
    printf 'Release v%s existiert bereits; es wird nichts überschrieben.\n' "$VERSION" >&2
    exit 1
fi
git pull --ff-only
git -C "$TAP" pull --ff-only
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$ROOT/Support/Info.plist")"
[[ "$BUILD" =~ ^[0-9]+$ ]] || { printf 'Ungültige Buildnummer.\n' >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/Mischpult-release.XXXXXX")"
cleanup() { rm -rf "${WORK:?}"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [[ -n "$NOTES_FILE" ]]; then
    cat "$NOTES_FILE" > "$WORK/notes.md"
else
    printf '%s\n' "$NOTES" > "$WORK/notes.md"
fi
cat >> "$WORK/notes.md" <<'NOTES'

## Installation

`Mischpult-<version>.dmg` unten bei den Dateien laden, öffnen und Mischpult auf
„Programme“ ziehen (die alte Version vorher beenden). Mischpult ist nicht
notarisiert: Beim ersten Start unter Systemeinstellungen → Datenschutz &
Sicherheit auf „Trotzdem öffnen“ klicken. Benötigt macOS 14.2 oder neuer.

Per Homebrew: `brew update && brew upgrade --cask cramleo234/public/mischpult`
NOTES

/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $VERSION" "$ROOT/Support/Info.plist"
/usr/libexec/PlistBuddy -c "Set CFBundleVersion $((10#$BUILD + 1))" "$ROOT/Support/Info.plist"
"$ROOT/make-dmg.sh" --universal
DMG="$ROOT/build/Mischpult-$VERSION.dmg"
ARCHES="$(lipo -archs "$ROOT/build/Mischpult.app/Contents/MacOS/Mischpult")"
[[ "$ARCHES" == *"arm64"* && "$ARCHES" == *"x86_64"* ]] || { printf 'Release muss universal gebaut sein.\n' >&2; exit 1; }
SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
[[ "$SHA" =~ ^[a-f0-9]{64}$ ]] || exit 1

git add Support/Info.plist
git commit -m "Mischpult $VERSION veröffentlichen"
git push
COMMIT="$(git rev-parse HEAD)"
gh release create "v$VERSION" "$DMG" --repo "$REPO" --target "$COMMIT" \
    --title "Mischpult $VERSION" --notes-file "$WORK/notes.md"
# Öffentlicher Download: die URL in der Cask enthält nur #{version}.
awk -v version="$VERSION" -v sha="$SHA" '
    /^  version "/ { print "  version \"" version "\""; next }
    /^  sha256 "/ { print "  sha256 \"" sha "\""; next }
    { print }
' "$TEMPLATE" > "$WORK/mischpult.rb"
cp "$WORK/mischpult.rb" "$TEMPLATE"
cp "$WORK/mischpult.rb" "$CASK"
git add packaging/homebrew-public/Casks/mischpult.rb
git commit -m "Homebrew-Vorlage für Mischpult $VERSION aktualisieren"
git push
git -C "$TAP" add Casks/mischpult.rb
git -C "$TAP" commit -m "Mischpult $VERSION im öffentlichen Tap aktualisieren"
git -C "$TAP" push
printf 'Veröffentlicht: Mischpult %s\nAktualisieren nach Beenden der App: brew update && brew upgrade --cask cramleo234/public/mischpult\n' "$VERSION"
