#!/bin/bash
# Baut eine signierte Mischpult.app ohne Xcode-Oberfläche.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
MODE="universal"
RUN=0
for OPTION in "$@"; do
    case "$OPTION" in
        --native) MODE="native" ;;
        --universal) MODE="universal" ;;
        --run) RUN=1 ;;
        *) printf 'Unbekannte Option: %s\nAufruf: ./build.sh [--universal|--native] [--run]\n' "$OPTION" >&2; exit 2 ;;
    esac
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/Mischpult-build.XXXXXX")"
cleanup() { rm -rf "${WORK:?}"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

APP="$WORK/Mischpult.app"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ "$MODE" == "native" ]]; then
    ARCHES=("$(uname -m)")
else
    ARCHES=("arm64" "x86_64")
fi
BINARIES=()
for ARCH in "${ARCHES[@]}"; do
    SCRATCH="$WORK/build-$ARCH"
    printf 'Baue Mischpult für %s …\n' "$ARCH"
    swift build --package-path "$ROOT" --scratch-path "$SCRATCH" \
        --manifest-cache local --disable-index-store --sdk "$SDK" \
        --triple "$ARCH-apple-macosx14.2" -c release --product Mischpult
    BIN_DIR="$(swift build --package-path "$ROOT" --scratch-path "$SCRATCH" \
        --manifest-cache local --sdk "$SDK" --triple "$ARCH-apple-macosx14.2" \
        -c release --show-bin-path)"
    test -x "$BIN_DIR/Mischpult"
    BINARIES+=("$BIN_DIR/Mischpult")
done
if [[ "${#BINARIES[@]}" -eq 2 ]]; then
    lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/Mischpult"
else
    cp "${BINARIES[0]}" "$APP/Contents/MacOS/Mischpult"
fi
chmod 755 "$APP/Contents/MacOS/Mischpult"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
ditto --norsrc --noextattr --noqtn "$ROOT/Support/de.lproj" "$APP/Contents/Resources/de.lproj"
ditto --norsrc --noextattr --noqtn "$ROOT/Support/en.lproj" "$APP/Contents/Resources/en.lproj"

mkdir -p "$WORK/AppIcon.iconset"
swift "$ROOT/Support/make-icon.swift" "$WORK/AppIcon.iconset"
iconutil -c icns "$WORK/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
xattr -cr "$APP"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"

mkdir -p "$ROOT/build"
OUTPUT="$ROOT/build/Mischpult.app"
# Nur das von diesem Skript erzeugte Bundle wird ersetzt.
rm -rf "${OUTPUT:?}"
ditto --norsrc --noextattr --noqtn "$APP" "$OUTPUT"
# iCloud setzt Finder-Attribute sofort erneut. Die Signatur wurde oben am
# identischen Bundle außerhalb von iCloud geprüft; DMG und installierte App
# werden dort nochmals geprüft. Die Kopie hier ist nur ein Build-Zwischenstand.
xattr -cr "$OUTPUT" || true
lipo -archs "$OUTPUT/Contents/MacOS/Mischpult"
printf 'Fertig: %s\n' "$OUTPUT"
if [[ "$RUN" -eq 1 ]]; then open "$OUTPUT"; fi
