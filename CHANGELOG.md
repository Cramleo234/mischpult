# Versionsverlauf

Alle Änderungen an Mischpult. Der gleiche Verlauf steht in der App unter **„…“ → Versionsverlauf**.

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
