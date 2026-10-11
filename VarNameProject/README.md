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
| `source/uVnpProbe.pas` | Sonden ohne Sync-Sitzung: Einheit von `CharIndex` (M10), was `CreateClass` liefert (M21) |
| `source/uVnpRegister.pas` | Menue Tools > VarNameProject |
| `demo/VarNameDemo.pas` | Uebungsdatei mit fuenf Faellen (ASCII) |
| `demo/VarNameDemoUmlaut.pas` | Fall 6: Umlaute und Euro-Zeichen VOR dem Literal - absichtlich UTF-8 mit BOM (misst Bytes gegen Zeichen) |

## Vorbild ReSharper (Recherche 2026-10-11, Kurzfassung)

- Introduce Variable (Strg+R,V): bei mehreren Vorkommen erst die Wahl
  "nur dieses / alle"; die Variable entsteht sofort vor der ersten
  nutzenden Anweisung; danach eine "Hotspot-Sitzung" fuer Typ und Name mit
  Vorschlagsliste. Rahmen: rot = aktive Stelle, schwarz = gekoppelte
  Stellen (aendern sich mit). Tab/Enter uebernimmt und springt weiter,
  Umschalt+Tab zurueck, Esc beendet mit den Vorgabewerten.
- Delphi hat dasselbe eingebaut: **Sync Edit** (Strg+Umschalt+J) - erste
  Stelle hervorgehoben, die anderen umrandet, Caret auf der ersten Stelle,
  Tippen ERSETZT den Namen, Tab springt, Esc beendet. Live Templates mit
  editierbaren Punkten laufen ueber denselben Modus. Die ToolsAPI dazu ist
  undokumentiert (DocWiki: "no additional information"), im Netz gibt es
  kein Beispiel mit eigenen Punkten - darum dieses Projekt.
- Delphi 13 hat die eingebauten Refactorings und das Template-Skripting
  entfernt (Nutzerberichte, Refactoring-DLLs fehlen in 37.0\bin); die
  Sync-Edit-API und die Template-Dateien sind in 12 und 13 gleich.

## Bedienung

1. `package/VarNameProject.d12.dproj` oeffnen, bauen, installieren.
2. ZUERST die Sonden: `demo/VarNameDemoUmlaut.pas` oeffnen, Caret direkt
   hinter das Euro-Zeichen, Tools > VarNameProject > "Sonde: CharIndex am
   Caret"; danach "Sonde: CreateClass".
3. `demo/VarNameDemo.pas` im Editor oeffnen.
4. Caret auf eine Zahl setzen (siehe Faelle in der Datei).
5. Tools > VarNameProject > eine Variante waehlen; danach wiederholt
   **Strg+Alt+Umschalt+M** die zuletzt gewaehlte (Start: B1a).
6. Neuen Namen tippen, mit Enter/Tab/Esc bzw. Klick daneben beenden.
7. Mit Strg+Z zuruecksetzen (zaehlen, wie oft - M7), naechste Variante.
   Stuerzt Strg+Z ab: Variante notieren, IDE neu starten (sie kann danach
   instabil sein), weiter mit der naechsten.
8. Tools > VarNameProject > "Protokolldatei im Editor oeffnen" und den
   Inhalt zurueckmelden.

## Varianten (nur Schritt 3 unterscheidet sich)

Alle mit eigenen Punkt-Klassen und absoluten Offsets (Lauf 1 bestaetigt).
Lauf 1 stuerzte bei Strg+Z nach der Sitzung ab (TSyncEditManager.
SendSyncEvent); damals waren die Punkte nur lokal gehalten und der Notifier
wurde bei Exit abgemeldet. Die Varianten trennen die beiden Verdaechtigen:

| Variante | Punkte | Notifier | erwartet |
|---|---|---|---|
| B1a | gehalten bis zum Entladen | angemeldet, bleibt | Kandidat: Strg+Z ohne Absturz |
| B1b | gehalten | keiner | stuerzt sie nicht ab, ist der Notifier unbeteiligt |
| B1d | NICHT gehalten | angemeldet, bleibt | stuerzt sie ab, war die Lebensdauer der Punkte schuld |
| C | die IDE legt sie an (`SyncEditBlock(nil)`, wie Strg+Umschalt+J) | angemeldet, bleibt | Referenz: Undo mit IDE-eigenen Punkten |

Entfallen: A1/A2 (Punkte per `IOTACodeTemplateServices.CreateClass` -
Ergebnis M21) und B2 (relative Offsets - absolute funktionieren).

## Ergebnisse

- **M10 (2026-10-11):** `TOTACharPos.CharIndex` aus `ConvertPos` zaehlt
  **Zeichen**, nicht UTF-8-Bytes: hinter dem Euro-Zeichen in Fall 6 (20
  Zeichen, 24 Bytes davor) meldet die IDE CharIndex 20, die Rueckrechnung ergibt dieselbe
  Anzeigespalte. **`CharPosToPos` addiert CharIndex aber als Bytes** zum
  Zeilenanfang (Differenz 20 statt 24) - auf Zeilen mit Nicht-ASCII vor der
  Stelle ist es also falsch; Pufferpositionen selbst rechnen (Reader-Bytes).
  Die erste Fassung bestimmte die Caret-Spalte ueber `CharPosToPos` und lag
  dadurch hinter dem Euro-Zeichen 4 Spalten daneben ("kein Zahl-Literal am
  Caret") - behoben. Dieselbe Byte-Annahme stand in reDelphix
  (`uRdxEditor.DisplayPosOf`, Markieren per `SelectSpan`) - dort ebenfalls
  korrigiert.
- **M21 (2026-10-11):** `CreateClass` liefert fuer `IOTASyncEditPoints`,
  `IOTASyncEditPoint` und `IOTASyncEditPoint100` **nil**; fuer
  `IOTACodeTemplate`, `IOTACodeTemplatePoint` und `IOTACodeTemplateObject`
  je ein Objekt (die Fabrik baut das Template-Objektmodell).
- **Lauf 1 (2026-10-11, B1, Fall 6):** eigene Punkt-Klassen mit absoluten
  Offsets in Zeichen ((23,6) (24,42)) starten die Sitzung im
  Template-Modus (SyncMode 2); die IDE setzt den Caret selbst auf den
  ersten Offset (Name in der Deklaration, 23:7); der Notifier meldet Enter
  und Exit. **Strg+Z danach stuerzt ab** (`TSyncEditUndoRedo.Execute` ->
  `TSyncButton.SetDown` -> `TSyncEditPainter.SyncEditEvent` ->
  `TSyncEditManager.SendSyncEvent`): Undo belebt die Sitzung wieder und
  ruft dabei etwas auf, das es nicht mehr gibt - siehe Varianten.

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
- **M10** Sonde Caret: welche der drei "Vor dem Caret"-Zeilen endet genau
  am Caret - zaehlt `CharIndex` Bytes oder Zeichen? Danach Fall 6: umranden
  die Varianten die richtigen Stellen hinter dem Euro-Zeichen?
- **M11** Ist der Name nach dem Start vorausgewaehlt? (Das Projekt setzt
  den Caret danach bewusst NICHT mehr - das koennte die Vorauswahl
  aufheben.)
- **M12/M13** Tab und Enter bei nur EINEM Punkt: springt Tab ins Leere,
  beendet Enter die Sitzung oder bricht es die Zeile um?
- **M14** Notifier: kommen "Ereignis"-Zeilen (Enter/Leave/Exit), steht der
  neue Name im Exit-Ereignis?
- **M17** Code-Insight-Popup waehrend des Tippens: nimmt Enter dann den
  Vorschlag statt die Sitzung zu beenden?
- **M18** Ein Offset ausserhalb des markierten Blocks - ignoriert oder
  Fehler? (bei Bedarf nachreichen)
- **M20** Startet die Sitzung auf dem ERSTEN Offset (Deklaration)?
- **M21** Sonde CreateClass: welche Interfaces kommen zurueck?
- **M22** Undo-Zaehlung: ein oder zwei Strg+Z fuer Einfuehren + Umbenennen?

## Grenzen (bewusst - es ist ein Testprojekt)

- Nur Zahl-Literale; nur gleiche Literale DERSELBEN Zeile werden ersetzt.
- Die Deklaration kommt als Inline-`var` (Delphi 10.3+) direkt ueber die
  Zeile; die Zeile darueber muss eine Anweisung beenden (`;`, `begin`,
  `try` ...), sonst Abbruch (die Deklaration wuerde sonst zum then-Zweig).
- Typ: `var X := 3.5` wird Extended, `$FFFFFFFF` Cardinal/Int64 - fuer den
  Test egal, fuer die echte Hilfe in reDelphix nicht.
- Kommentare ueber Zeilen vor der Caret-Zeile sieht der Leser nicht.
