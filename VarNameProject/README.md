# VarNameProject - Testprojekt Namenseingabe

Zweck: klaeren, wie reDelphix einen NEUEN Namen erfragt, ohne Dialog -
so wie ReSharper "Introduce Variable" (Nico 2026-10-11, Entscheid E17 im
Konzept "Editorhilfen ohne Fund"):

1. Der Code entsteht mit einem vorlaeufigen Namen, z. B. `MagicNr01`.
2. Es geht inline weiter - kein Fenster.
3. `MagicNr01` wird umrandet, der Caret steht darauf.
4. Tippen aendert den Namen, alle Stellen von `MagicNr01` aendern sich mit.

Die Delphi-IDE hat dafuer einen eingebauten Mechanismus: **Sync Edit**
(Strg+Umschalt+J) bzw. die editierbaren Punkte der **Live Templates**. Die
ToolsAPI legt ihn offen: `IOTAEditBlock.SyncEditBlock(Points)` mit
`IOTASyncEditPoints`/`IOTASyncEditPoint` (Name, Text, mehrere Offsets,
editierbar) und `IOTASyncEditNotifier` fuer die Ereignisse. Offen ist,
**wie** man die Punkte erzeugt und **in welchem Koordinatensystem** die
Offsets stehen - das misst dieses Projekt.

## Aufbau

| Datei | Inhalt |
|---|---|
| `package/VarNameProject.d12.dpk/.dproj` | Entwurfszeit-Paket (rtl, vcl, designide) - eigenstaendig, ohne SCA.Engine und reDelphix |
| `source/uVnpPlan.pas` | reine Textlogik (auch unter FPC): Zahl-Literal am Caret, gleiche Literale der Zeile, Deklarationszeile, Spalten danach, freier Name `MagicNrNN` |
| `source/uVnpIntroduce.pas` | Ablauf in der IDE: lesen, planen, schreiben (EIN Undo-Schritt), Block markieren, Sync-Sitzung starten, Caret auf den Namen |
| `source/uVnpSync.pas` | Sync-Punkte: per `IOTACodeTemplateServices.CreateClass` (Variante A) oder eigene Klassen (Variante B); Notifier protokolliert jede Sitzung samt Offsets |
| `source/uVnpLog.pas` | Protokoll: Meldungsansicht (Gruppe "VarNameProject") und `%TEMP%\VarNameProject.log` |
| `source/uVnpRegister.pas` | Menue Tools > VarNameProject |
| `demo/VarNameDemo.pas` | Uebungsdatei mit fuenf Faellen |

## Bedienung

1. `package/VarNameProject.d12.dproj` oeffnen, bauen, installieren.
2. `demo/VarNameDemo.pas` im Editor oeffnen.
3. Caret auf eine Zahl setzen (siehe Faelle in der Datei).
4. Tools > VarNameProject > eine Variante waehlen; danach wiederholt
   **Strg+Alt+Umschalt+M** die zuletzt gewaehlte (Start: A1).
5. Neuen Namen tippen, mit Enter/Tab/Esc bzw. Klick daneben beenden.
6. Mit Strg+Z zuruecksetzen, naechste Variante probieren.
7. Tools > VarNameProject > "Protokolldatei im Editor oeffnen" und den
   Inhalt zurueckmelden.

## Varianten (nur Schritt 3 unterscheidet sich)

| Variante | Punkte | Offsets |
|---|---|---|
| A1 | `IOTACodeTemplateServices.CreateClass(IOTASyncEditPoint[s])` | absolut: Zeile der Datei, CharIndex 0-basiert (UTF-8-Bytes) |
| A2 | wie A1 | relativ: Zeile ab Blockanfang 0-basiert |
| B1 | eigene Klassen `TVnpSyncPoint/TVnpSyncPoints` | absolut |
| B2 | wie B1 | relativ |
| C | `SyncEditBlock(nil)` - die IDE sucht selbst (wie Strg+Umschalt+J) | die IDE legt sie an - der Notifier protokolliert sie: **die Referenz**, in welchem System die IDE rechnet |

## Was zurueckmelden (Messpunkte)

- **M1** Startet eine Sitzung? Protokoll "SyncMode" (0 keine, 1 normal,
  2 Templates) und sichtbar: sind die Stellen umrandet?
- **M2** Welche Variante umrandet GENAU die `MagicNr01`-Stellen (nicht
  daneben, nicht weitere Bezeichner)?
- **M3** Steht der Caret auf dem Namen in der `var`-Zeile? Ueberschreibt
  Tippen den ganzen Namen (vorausgewaehlt) oder fuegt es ein?
- **M4** Aendern sich beim Tippen alle Stellen mit?
- **M5** Tasten: was tun Enter, Tab, Umschalt+Tab, Esc? Bleibt der neue
  Name nach Esc stehen?
- **M6** Variante C: die protokollierten Offsets der IDE (Zeile absolut
  oder relativ? CharIndex 0- oder 1-basiert?) - daran richten sich A/B aus.
- **M7** Undo: nimmt EIN Strg+Z Einfuehren und Umbenennen zurueck, oder
  braucht es zwei?
- **M8** Fall 5 (Tab-Einrueckung): stimmen die Spalten?
- **M9** Fall 3 muss abgelehnt werden (Protokoll "Abbruch: ...").

## Grenzen (bewusst - es ist ein Testprojekt)

- Nur Zahl-Literale; nur gleiche Literale DERSELBEN Zeile werden ersetzt.
- Die Deklaration kommt als Inline-`var` (Delphi 10.3+) direkt ueber die
  Zeile; die Zeile darueber muss eine Anweisung beenden (`;`, `begin`,
  `try` ...), sonst Abbruch (die Deklaration wuerde sonst zum then-Zweig).
- Typ: `var X := 3.5` wird Extended, `$FFFFFFFF` Cardinal/Int64 - fuer den
  Test egal, fuer die echte Hilfe in reDelphix nicht.
- Kommentare ueber Zeilen vor der Caret-Zeile sieht der Leser nicht.
