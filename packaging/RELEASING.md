# Mischpult veröffentlichen

Gebaut wird ohne Xcode-Fenster als Swift Package. Das App-Repo ist **öffentlich** (DMG frei auf der Release-Seite), der Tap bleibt privat.
Commits nur als `Cramleo <89691483+Cramleo234@users.noreply.github.com>` (in `.git/config` dieses Repos eingestellt), damit kein echter Name öffentlich wird.

## Einmalige Einrichtung

1. `gh auth login` und `gh auth setup-git` als **Cramleo234** (macht der Nutzer selbst; keine Tokens in Dateien).
2. Repo anlegen (erst privat, seit 1.0.0 öffentlich): `gh repo create Cramleo234/mischpult --private --source . --push`, später `gh repo edit Cramleo234/mischpult --visibility public --accept-visibility-change-consequences`.
   Anonyme Commit-Adresse: `git config user.name Cramleo` und `git config user.email 89691483+Cramleo234@users.noreply.github.com`.
3. Beschreibung setzen: `gh repo edit Cramleo234/mischpult --description "Lautstärke, Ausgabegerät und Equalizer pro App – inoffizielle SoundSource-Alternative"`.
4. Der Tap liegt daneben unter `../homebrew-tap` (`Cramleo234/homebrew-tap`).

## Erster Release (1.0.0)

```bash
./make-dmg.sh --universal
gh release create v1.0.0 build/Mischpult-1.0.0.dmg --repo Cramleo234/mischpult \
  --title "Mischpult 1.0.0" --notes-file <notizen.md>
gh api repos/Cramleo234/mischpult/releases/tags/v1.0.0 --jq '.assets[].id'
shasum -a 256 build/Mischpult-1.0.0.dmg
```

Asset-ID und SHA256 in `packaging/homebrew-tap/Casks/mischpult.rb` eintragen, nach `../homebrew-tap/Casks/` kopieren, Tap-README ergänzen, beide Repos committen und pushen.

## Spätere Releases

Quellcode und Tap vorher committen (beide Arbeitsverzeichnisse sauber), dann:

```bash
./release.sh 1.0.1 "**Verbesserungen**

Kurze Beschreibung."
```

Das Skript erhöht Version und Build in `Support/Info.plist`, baut ein Universal-DMG, erstellt den GitHub-Release (mit angehängtem Abschnitt `## Installation`) und aktualisiert die Cask im Tap und hier in `packaging/`. Die Versionsanzeige liest die Bundle-Metadaten, im Code muss nichts ersetzt werden.

## Installation prüfen

```bash
brew update
brew fetch --cask --force cramleo234/tap/mischpult
brew install --cask cramleo234/tap/mischpult   # bzw. brew upgrade --cask …
codesign --verify --deep --strict /Applications/Mischpult.app
```

## Hinweise

- Nicht notarisiert, ad hoc signiert → beim ersten Start ggf. Rechtsklick → Öffnen.
- Tests prüfen die Klangverarbeitung; Geräte und Apps lassen sich mit `MISCHPULT_SELFTEST=1` ohne Oberfläche auflisten. Echte Taps brauchen die Erlaubnis „Systemaudio“ und werden von Hand ausprobiert.
- Danach aufräumen: `build/` und `.build/` löschen, `lsregister -u` für die Build-Kopie.
