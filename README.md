# Mischpult

Eine kostenlose Menüleisten-App für macOS, inspiriert von SoundSource: Jede App bekommt ihren eigenen Lautstärkeregler, auf Wunsch ihr eigenes Ausgabegerät und einen Equalizer. Auf Deutsch und Englisch.

## Features

- **Lautstärke pro App:** Jede App, die Ton abspielt, erscheint mit eigenem Regler von 0 bis 200 %. Über 100 % wird verstärkt (Boost), ein weicher Begrenzer verhindert hartes Übersteuern. Bei 100 % rastet der Regler leicht ein.
- **Stummschalten pro App:** Ein Klick auf das App-Symbol schaltet nur diese App stumm.
- **Eigenes Ausgabegerät pro App:** Zum Beispiel Musik auf die Lautsprecher, Discord auf die Kopfhörer. Standard ist „Systemausgabe“; die App folgt dann dem Gerät, das in macOS gewählt ist.
- **Equalizer pro App:** Bässe, Mitten und Höhen jeweils ±12 dB.
- **Pegelanzeige:** Unter jedem Regler zeigt ein Balken, wie laut die App gerade ist.
- **Geräte im Griff:** Aus- und Eingabegerät des Systems wechseln, Gesamtlautstärke und Mikrofonpegel regeln, alles im selben Fenster.
- **Merkt sich alles:** Einstellungen gelten pro App und werden beim nächsten Start der App wieder angewendet.
- **Greift nur ein, wenn nötig:** Apps mit unveränderten Reglern laufen ganz normal direkt zum Gerät. Erst wenn du etwas änderst, leitet Mischpult den Ton dieser App um.
- **Beim Anmelden starten** auf Wunsch, **Alle Apps anzeigen** auch ohne laufenden Ton.
- **Lokal:** keine Telemetrie, keine Internetverbindung, kein Treiber, keine Systemerweiterung.

## Installation

### macOS 14.2 Sonoma oder neuer

Mischpult nutzt Apples „Process Taps“, die es erst ab macOS 14.2 gibt.

### Herunterladen

1. Die neueste `Mischpult-<version>.dmg` von der [Release-Seite](https://github.com/Cramleo234/mischpult/releases/latest) laden.
2. Die DMG öffnen und **Mischpult** auf **Programme** ziehen.
3. Mischpult starten. Das Symbol mit den drei Schiebereglern erscheint oben in der Menüleiste.

> **Warnung beim ersten Start:** Mischpult ist ein kostenloses Hobbyprojekt ohne Apple-Entwicklerkonto. Die App ist deshalb nur ad hoc signiert und **nicht von Apple notarisiert**. macOS meldet beim ersten Öffnen, dass die App nicht überprüft werden kann. So öffnest du sie trotzdem: **Systemeinstellungen → Datenschutz & Sicherheit**, ganz nach unten scrollen und bei Mischpult auf **Trotzdem öffnen** klicken. Unter macOS 14 reicht auch Rechtsklick auf die App → **Öffnen**.

Updates gibt es ebenfalls auf der Release-Seite. Zum Aktualisieren Mischpult beenden und die neue Version über die alte ziehen.

### Homebrew (nur für den Entwickler)

Die Cask liegt in einem privaten Tap und funktioniert nur mit Zugriff darauf:

```bash
brew tap Cramleo234/tap
brew trust Cramleo234/tap
brew install --cask cramleo234/tap/mischpult
brew upgrade --cask cramleo234/tap/mischpult   # aktualisieren
```

> **Warum `brew trust`?** Ab Homebrew 6 müssen Taps anderer Anbieter freigegeben werden, sonst überspringt Homebrew sie kommentarlos.
>
> **Warum das Token?** Der Tap ist privat. Homebrew braucht dafür `HOMEBREW_GITHUB_API_TOKEN="$(gh auth token)"` in der `~/.zshrc`. Das Token stammt aus dem `gh`-Login und wird weder in Mischpult noch im Repo gespeichert.

### Erlaubnis „Systemaudio“

Sobald du zum ersten Mal einen Regler veränderst, fragt macOS, ob Mischpult **Systemaudio aufnehmen** darf. Das ist nötig, damit Mischpult den Ton einer App abgreifen und mit neuer Lautstärke wiedergeben kann; aufgenommen oder gespeichert wird nichts. Wurde die Frage abgelehnt: **Systemeinstellungen → Datenschutz & Sicherheit → Bildschirm- & Systemaudioaufnahme → Nur Systemaudio** und Mischpult einschalten. Weil die App nicht notarisiert ist, kann macOS nach einem Update erneut fragen.

Einstellungen liegen in `~/Library/Preferences/local.private.mischpult.plist`.

## Aus dem Quellcode bauen

Benötigt macOS 14.2+ und die Xcode-Entwicklungswerkzeuge (Swift 5.10+). **Die Xcode-Oberfläche wird nicht geöffnet** – das Projekt ist ein Swift Package.

```bash
./build.sh                 # universal: Apple Silicon + Intel
./build.sh --native --run  # nur aktuelle Architektur, danach starten
./make-dmg.sh              # App bauen und DMG erzeugen
swift test                 # Tests der Klangverarbeitung
```

Prüfung ohne Oberfläche (listet Geräte, Audio-Apps und den Status der Erlaubnis):

```bash
MISCHPULT_SELFTEST=1 build/Mischpult.app/Contents/MacOS/Mischpult
```

### Wie es funktioniert

Für jede App mit veränderten Reglern legt Mischpult einen privaten **Process Tap** an, der den Ton dieser App abgreift und das Original stumm schaltet. Ein privates Aggregat-Gerät spielt den Ton dann – mit neuer Lautstärke und Equalizer – auf dem gewünschten Ausgabegerät wieder ab. Hilfsprozesse (z. B. Browser-Tabs) werden der zuständigen App zugeordnet. Beim Beenden von Mischpult wird alles wieder abgebaut und die Apps klingen wie vorher.

### Aufbau

- `Sources/MischpultCore/` – Core-Audio-Zugriff: Geräte, Audio-Prozesse, Process Taps, Klangverarbeitung (Lautstärke, Boost, Equalizer, Pegel).
- `Sources/Mischpult/` – SwiftUI-Menüleisten-Oberfläche und Steuerung.
- `Tests/MischpultCoreTests/` – Tests der Klangverarbeitung.
- `Support/` – Info.plist, deutsche/englische Texte, Icon- und DMG-Hintergrund-Generator.
- `build.sh` / `make-dmg.sh` / `release.sh` – Bundle, Signatur, DMG und Veröffentlichung.
- `packaging/` – [Release-Anleitung](packaging/RELEASING.md) und Cask-Vorlage.

## Rechtliches

Mischpult ist ein inoffizielles Hobbyprojekt und steht in keiner Verbindung zu Rogue Amoeba oder SoundSource. „SoundSource“ ist eine Marke von Rogue Amoeba und wird hier nur zum Vergleich genannt. Mischpult enthält keinen fremden Code und keine fremden Grafiken; Icon und DMG-Hintergrund sind eigenes Artwork. Die Nutzung erfolgt ohne Gewähr (siehe Lizenz).

Copyright © 2026 Cramleo

## Lizenz

[MIT](LICENSE)
