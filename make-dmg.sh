#!/bin/bash
# Erstellt eine DMG mit App, Programme-Verknüpfung und Retina-Hintergrund.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
BUILD_ARGS=()
SKIP_BUILD=0
for OPTION in "$@"; do
    case "$OPTION" in
        --native|--universal) BUILD_ARGS+=("$OPTION") ;;
        --skip-build) SKIP_BUILD=1 ;;
        *) printf 'Unbekannte Option: %s\nAufruf: ./make-dmg.sh [--native|--universal] [--skip-build]\n' "$OPTION" >&2; exit 2 ;;
    esac
done
if [[ "$SKIP_BUILD" -eq 0 ]]; then
    if [[ "${#BUILD_ARGS[@]}" -gt 0 ]]; then "$ROOT/build.sh" "${BUILD_ARGS[@]}"; else "$ROOT/build.sh"; fi
fi
SOURCE_APP="$ROOT/build/Mischpult.app"
test -d "$SOURCE_APP"
# Die iCloud-Kopie kann Finder-Attribute tragen. Prüfung erst am bereinigten,
# identischen Bundle im Staging-Ordner außerhalb von iCloud.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$SOURCE_APP/Contents/Info.plist")"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then printf 'Ungültige App-Version.\n' >&2; exit 1; fi

# Finder erzeugt nur unter /Volumes einen nach dem Aushängen stabilen
# Hintergrund-Bookmark. Einen vorhandenen gleichnamigen Mount nie übernehmen.
MOUNT="/Volumes/Mischpult"
if [[ -e "$MOUNT" || -L "$MOUNT" ]]; then
    printf 'Das Volume %s ist bereits vorhanden. Bitte vor dem DMG-Bau aushängen.\n' "$MOUNT" >&2
    exit 1
fi
# Kurzer Pfad: der native Hintergrund-Bookmark enthält auch den Image-Pfad.
WORK="$(mktemp -d "/tmp/Mischpult-dmg.XXXXXX")"
MOUNTED=0
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
cleanup() {
    "$LSREG" -u "$MOUNT/Mischpult.app" >/dev/null 2>&1 || true
    if [[ "$MOUNTED" -eq 1 ]]; then
        hdiutil detach -quiet "$MOUNT" >/dev/null 2>&1 || true
    fi
    if mount | grep -Fq " on $MOUNT "; then
        printf 'Hinweis: Temporäres Volume ist noch eingehängt: %s\n' "$MOUNT" >&2
    else
        rm -rf "${WORK:?}"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

STAGE="$WORK/stage"
RW="$WORK/Mischpult-rw.dmg"
FINAL="$WORK/Mischpult-$VERSION.dmg"
DMG="$ROOT/build/Mischpult-$VERSION.dmg"
mkdir -p "$STAGE/.background"
ditto --norsrc --noextattr --noqtn "$SOURCE_APP" "$STAGE/Mischpult.app"
xattr -cr "$STAGE/Mischpult.app"
codesign --verify --deep --strict "$STAGE/Mischpult.app"
ln -s /Applications "$STAGE/Programme"
swift "$ROOT/Support/make-dmg-background.swift" "$STAGE/.background/bg"
tiffutil -cathidpicheck "$STAGE/.background/bg.png" "$STAGE/.background/bg@2x.png" \
    -out "$STAGE/.background/background.tiff" >/dev/null
rm -f "$STAGE/.background/bg.png" "$STAGE/.background/bg@2x.png"
cp "$SOURCE_APP/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
hdiutil create -quiet -srcfolder "$STAGE" -volname Mischpult -fs HFS+ -format UDRW -ov "$RW"
hdiutil attach -quiet -readwrite -noverify -noautoopen -mountpoint "$MOUNT" "$RW"
MOUNTED=1
# Ohne "activate": Finder wird nicht ausdrücklich in den Vordergrund geholt.
# Scheitert die Automation, bleibt die DMG benutzbar; das wird sichtbar gemeldet.
if ! osascript - "$MOUNT" <<'APPLESCRIPT'
on run argv
    set mountedPath to item 1 of argv
    set mountedFolder to POSIX file mountedPath as alias
    set backgroundFile to POSIX file (mountedPath & "/.background/background.tiff") as alias
    tell application "Finder"
        set volumeFolder to folder mountedFolder
        open volumeFolder
        set volumeWindow to container window of volumeFolder
        tell volumeWindow
            set current view to icon view
            set toolbar visible to false
            set statusbar visible to false
            set bounds to {240, 140, 940, 580}
        end tell
        -- Die Optionen ausdrücklich an das konkrete Fenster binden.
        set viewOptions to icon view options of volumeWindow
        -- Neue Finder-Versionen erlauben diesen Setter nicht auf jedem Volume.
        -- Der Fehler darf Hintergrund und feste Iconpositionen nicht verhindern.
        try
            set arrangement of viewOptions to not arranged
        end try
        set icon size of viewOptions to 112
        set text size of viewOptions to 13
        set background picture of viewOptions to backgroundFile
        set position of item "Mischpult.app" of volumeFolder to {180, 210}
        set position of item "Programme" of volumeFolder to {520, 210}
        update volumeFolder without registering applications
        delay 1
        close volumeWindow
    end tell
end run
APPLESCRIPT
then
    printf 'Hinweis: Finder-Layout konnte nicht gespeichert werden; App und Programme-Verknüpfung sind enthalten.\n' >&2
fi
# Finder 27 kann den pBBk-Hintergrund-Bookmark abgeschnitten speichern.
# Einen gültigen nativen Bookmark ohne Security-Scope erzeugen und nur innerhalb
# des bereits reservierten .DS_Store-Blob ersetzen; keine neuen Abhängigkeiten.
swift - "$MOUNT/.background/background.tiff" "$WORK/background.bookmark" <<'SWIFT'
import Foundation
do {
    let image = URL(fileURLWithPath: CommandLine.arguments[1])
    let data = try image.bookmarkData(options: [.minimalBookmark, .withoutImplicitSecurityScope],
                                    includingResourceValuesForKeys: nil, relativeTo: nil)
    try data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
} catch {
    fputs("Hintergrund-Bookmark konnte nicht erzeugt werden: \(error)\n", stderr)
    exit(1)
}
SWIFT
python3 - "$MOUNT/.DS_Store" "$WORK/background.bookmark" <<'PYTHON'
from pathlib import Path
import struct, sys

store_path, bookmark_path = map(Path, sys.argv[1:])
if not store_path.is_file():
    print("Hinweis: Kein Finder-Layout vorhanden; Standardlayout wird verwendet.")
    sys.exit(0)
store = bytearray(store_path.read_bytes())
bookmark = bookmark_path.read_bytes()
cursor = repaired = 0
while True:
    at = store.find(b"pBBkblob", cursor)
    if at < 0:
        break
    cursor = at + 8
    if at + 12 > len(store):
        continue
    size = struct.unpack_from(">I", store, at + 8)[0]
    start, end = at + 12, at + 12 + size
    if size < 16 or end > len(store) or store[start:start + 4] not in (b"book", b"alis"):
        continue
    declared = struct.unpack_from("<I", store, start + 4)[0]
    if declared == size:
        continue
    if len(bookmark) > size:
        raise SystemExit("Nativer Hintergrund-Bookmark passt nicht in den vorhandenen .DS_Store-Blob.")
    replacement = bytearray(bookmark + bytes(size - len(bookmark)))
    struct.pack_into("<I", replacement, 4, size)
    store[start:end] = replacement
    repaired += 1
if repaired:
    store_path.write_bytes(store)
    print("Finder-Hintergrund-Bookmark repariert.")
PYTHON
if ! xcrun SetFile -a C "$MOUNT" 2>/dev/null; then
    printf 'Hinweis: Das Laufwerkssymbol konnte nicht gesetzt werden.\n' >&2
fi
sync
"$LSREG" -u "$MOUNT/Mischpult.app" >/dev/null 2>&1 || true
hdiutil detach -quiet "$MOUNT"
MOUNTED=0
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$FINAL"
hdiutil verify -quiet "$FINAL"
ditto --norsrc --noextattr --noqtn "$FINAL" "$DMG"
printf 'Fertig: %s\n' "$DMG"
