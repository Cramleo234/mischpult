# Versionsverlauf

Alle Änderungen an Mischpult. Der gleiche Verlauf steht in der App unter **Zahnrad → Versionsverlauf …**.

## 1.4.3 – 16.10.2026

- Das Fenster verschiebt sich nicht mehr beim Öffnen und Schließen von Ausgabe und Equalizer. Jede Höhenänderung des Menüleisten-Fensters lässt macOS es verrutschen – deshalb erscheinen die Einstellungen einer App jetzt als Sprechblase neben der Zeile.
- Solange das Fenster offen ist, bleibt die App-Liste fest (nur Werte und Pegel ändern sich); neu startende Apps erscheinen beim nächsten Öffnen.
- Fehlerhinweise als kleines Symbol neben dem App-Namen statt als eigene Zeile.

## 1.4.2 – 16.10.2026

**Bedienungsaudit**
- Feste, alphabetische Reihenfolge der Apps: Vorher sortierten spielende Apps nach oben, und Zeilen sprangen bei offenem Fenster unter dem Mauszeiger weg.
- Bei mehr als sechs Apps ist die letzte sichtbare Zeile angeschnitten und der Scrollbalken immer sichtbar – man erkennt, dass gescrollt werden kann.
- Verständliche Fehlermeldung („Lautstärke für diese App gerade nicht regelbar.“), technische Details im Tooltip.
- Equalizer zeigt „0 dB“ statt „+0 dB“; Lautstärke-Symbole stehen bündig mit den Gerätekreisen.
- Neuer Prüfmodus `MISCHPULT_UIAUDIT=<ordner>` für die Entwicklung: spielt Bedienzustände mit Beispieldaten durch, ohne Ton anzufassen.

## 1.4.1 – 16.10.2026

- Die Optionen sind wieder direkt in der App: Das Zahnrad öffnet ein normales Aufklappmenü wie in Version 1.0 (Alle Apps anzeigen, Beim Anmelden starten, Ton-Einstellungen, Erlaubnis Systemaudio, Versionsverlauf, Beenden).
- Der Regler „Glas-Intensität“ und das eigene Einstellungsfenster sind entfallen.

## 1.4.0 – 16.10.2026

**Neues Design**
- Ruhiger Aufbau im Stil des Ton-Menüs im Kontrollzentrum: Abschnitte „Ausgabe“, „Apps“ und „Eingabe“ mit kleinen Überschriften und feinen Trennlinien. Keine eigenen Glaskacheln mehr – das Menüleisten-Fenster ist selbst schon Glas.
- Alle Aus- und Eingabegeräte als Liste: gewähltes Gerät mit blauem Kreis und Häkchen, Wechsel mit einem Klick.
- Apps wie in 1.0: normaler Regler mit Pegelbalken; Klick auf den Namen klappt Ausgabe und Equalizer auf; über 100 % werden Regler und Zahl orange.
- Die Glas-Intensität regelt jetzt, wie stark der Hintergrund durch das ganze Fenster scheint.

## 1.3.0 – 16.10.2026

**Audit**
- **Wichtig:** Die Lautstärke pro App wirkt wieder. Seit 1.1.0 wartete Mischpult vor jedem Eingriff auf die Meldung „Erlaubnis erteilt“, die macOS bei der ad-hoc signierten App nie schickte – die Regler blieben ohne Wirkung. Jetzt greift Mischpult wie in 1.0 ein, und macOS fragt dabei selbst nach der Erlaubnis.
- Einstellungen öffnen sich in einem eigenen Fenster (Zahnrad). Das Menüleisten-Fenster tauscht seinen Inhalt nicht mehr aus und kann deshalb nicht mehr verrutschen oder Ebenen überlagern.
- Aus- und Eingabe zeigen wieder den Gerätenamen (echte Auswahlliste statt Menü mit eigenem Etikett).
- Glaskacheln verschmelzen nicht mehr zu einer großen Fläche (keine Glas-Gruppe mehr); keine Glasknöpfe mehr auf Glaskacheln.
- „Erlaubnis Systemaudio …“ öffnet die Seite „Bildschirm- & Systemaudioaufnahme“.
- „Beim Anmelden starten“ öffnet die Anmeldeobjekte, wenn macOS eine Bestätigung verlangt, statt sich kommentarlos auszuschalten.

## 1.2.3 – 15.10.2026

- Behebt, dass Einstellungen und Regler gleichzeitig übereinander angezeigt wurden (Glasflächen lassen sich nicht über die Deckkraft ausblenden). Es wird wieder nur eine Ansicht gezeigt; die Einstellungen übernehmen die Höhe der Regler-Ansicht, damit das Fenster an der Menüleiste bleibt.

## 1.2.2 – 15.10.2026

- Das Fenster bleibt jetzt an der Menüleiste, wenn man die Einstellungen (Zahnrad) öffnet oder eine App aufklappt. Vorher änderte sich die Fenstergröße animiert, und das Fenster verrutschte.

## 1.2.1 – 15.10.2026

- Behebt ein leeres oder abgeschnittenes Fenster beim ersten Öffnen (die App-Liste hat jetzt immer eine feste Höhe).
- Die Regler sehen wieder aus wie in Version 1.0: normale macOS-Schieberegler, darunter gut sichtbar der Pegel jeder App. Das Glas-Design drumherum bleibt.

## 1.2.0 – 15.10.2026

- Neuer Regler **Glas-Intensität** in den Einstellungen: von vollem Liquid Glass bis zu ruhigen, deckenden Flächen.
- Die Optionen sind jetzt ein Einstellungsfeld (Zahnrad oben rechts) statt eines Menüs.
- Der Versionsverlauf scrollt jetzt flüssig (keine Glasflächen mehr in der Scroll-Ansicht).

## 1.1.0 – 15.10.2026

**Neues Design**
- Liquid-Glass-Stil von macOS: Glas-Kacheln und große Regler wie im Kontrollzentrum (unter macOS 14/15 mit passendem Material).
- Versionsverlauf direkt in der App.

**Fehlerbehebungen aus dem Audit**
- Mischpult fragt jetzt zuerst nach der Erlaubnis „Systemaudio“ – Apps werden während des Dialogs nicht mehr stumm.
- Wird die Erlaubnis entzogen, gibt Mischpult alle Apps sofort wieder frei (vorher konnten sie stumm bleiben).
- Behebt einen möglichen Absturz beim Erlaubnisdialog.
- Equalizer-Änderungen können keine Störgeräusche mehr verursachen; ein hängender Filter setzt sich selbst zurück.
- Bei 100 % bleibt der Ton völlig unverändert, der Begrenzer greift nur noch beim Verstärken.
- Der Equalizer passt sich an, wenn ein Gerät die Abtastrate wechselt.
- Mono-Lautsprecher geben jetzt beide Stereokanäle wieder.
- Einstellungen für Hintergrundprozesse ohne App werden nicht mehr gespeichert (sie hätten nach einem Neustart eine fremde App treffen können).

**Leistung**
- Ton läuft direkt auf dem Echtzeit-Thread von Core Audio: weniger Verzögerung, weniger Aussetzer.
- App-Symbole werden zwischengespeichert; weniger Rechenlast bei geöffnetem Fenster.

## 1.0.0 – 15.10.2026

- Erste Version.
- Lautstärke pro App von 0 bis 200 %, Stummschalten per Klick auf das App-Symbol.
- Eigenes Ausgabegerät und 3-Band-Equalizer pro App.
- Pegelanzeige, Geräteauswahl, Gesamtlautstärke und Mikrofonpegel.
