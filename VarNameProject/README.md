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

1. `package/VarNameProject.d12.dproj` oeffnen, bauen, installieren -
   danach die **IDE komplett neu starten** (Lauf 4: die nil-Eintraege
   frueherer Notifier haengen an den offenen Editoransichten und ueberleben
   das Neuinstallieren).
2. Die Sonden (M10/M21) sind erledigt - siehe Ergebnisse.
3. `demo/VarNameDemo.pas` im Editor oeffnen.
4. Caret auf eine Zahl setzen (siehe Faelle in der Datei).
5. Tools > VarNameProject > eine Variante waehlen; danach wiederholt
   **Strg+Alt+Umschalt+M** die zuletzt gewaehlte (Start: C1).
6. **Strg+Alt+Umschalt+P** ("Sonde: Sitzung jetzt") - SyncMode, Caret und
   die beiden Zeilen frisch aus dem Puffer. Nach jedem der folgenden
   Schritte noch einmal.
7. Neuen Namen tippen, Strg+Alt+Umschalt+P, mit Enter beenden,
   Strg+Alt+Umschalt+P.
8. In ein anderes Fenster klicken und zurueck (Fokuswechsel).
9. Mit Strg+Z bis zum Ausgangszustand zuruecksetzen (zaehlen - M7),
   Strg+Alt+Umschalt+P. Stuerzt etwas ab: Variante und Schritt notieren,
   IDE neu starten.
10. Tools > VarNameProject > "Protokolldatei im Editor oeffnen" und den
    Inhalt zurueckmelden.

## Varianten (nur Schritt 3 unterscheidet sich)

Kein Notifier mehr, in keiner Variante (Lauf 4 - siehe Ergebnisse).

| Variante | Sync-Punkte | Block |
|---|---|---|
| C1 | die IDE sucht selbst: `SyncEditBlock(nil)` = Strg+Umschalt+J | vom Namen in der Deklaration bis hinter seine letzte Verwendung |
| B1 | eigene Klassen, absolute Offsets, CharIndex in UTF-8-Bytes (Lauf 3), gehalten | ganze Zeilen |

Entfallen: A1/A2 (Punkte per `IOTACodeTemplateServices.CreateClass` -
Ergebnis M21), B2 (relative Offsets - absolute funktionieren), alle
Notifier-Varianten (Lauf 4).

C1 koppelt JEDEN Bezeichner, der im Block mehrfach vorkommt - deshalb der
knappe Block. In Fall 1 (`Result := Value * MagicNr01 + MagicNr01;`) ist
das nur `MagicNr01`.

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
- **Lauf 2 (2026-10-11, B1a: Punkte und Notifier gehalten):** Sitzung wie
  in Lauf 1. Absturz diesmal beim **Fokuswechsel** (Klick in eine
  Baumansicht -> `EditorControl.WMKillFocus` ->
  `KbClient.TIDEKBDChildAPI.KBDClearPrimFocus`). Zwei verschiedene
  Absturzstellen trotz gehaltener Objekte: die IDE behandelt fremde
  `IOTASyncEditPoint`-Objekte vermutlich intern wie ihre eigenen ->
  eigene Punkt-Klassen sind eine Sackgasse; Kandidat jetzt C1.
- **Lauf 3 (2026-10-11, Fall 6, vermutlich noch B1a aus dem alten Paket):**
  direkt nach dem Start, vor jeder Eingabe, stand im Puffer
  `IntToStr(CounMagicNr01Nr01)` statt `IntToStr(Count * MagicNr01)` - der
  Editor zeigte noch den alten Text, die Datei war nicht als geaendert
  markiert. Unser Schreiben war richtig; im Template-Modus schreibt die IDE
  den Punkttext an jede Fundstelle und las CharIndex 42 dabei als **Byte**
  42 (= Zeichen 39, das 't'). Die ToolsAPI ist also uneinheitlich:
  `ConvertPos` zaehlt Zeichen, die Offsets der Sync-Punkte (wie
  `CharPosToPos`) UTF-8-Bytes. B1a rechnet die Offsets jetzt in Bytes; das
  Protokoll liest nach dem Schreiben und nach dem Sitzungsstart die Zeilen
  frisch aus dem Puffer, meldet den Geaendert-Zustand und jede Abweichung
  vom Plan.
- **Lauf 4 (2026-10-11, C1 - ohne eigene Objekte):** Absturz schon beim
  Start: `TInterfaceList.Get` -> `TSyncEditManager.SendSyncEvent` ->
  Zugriffsverletzung beim Lesen von Adresse 0. Die IDE geht ihre
  Notifier-Liste durch und trifft einen **nil-Eintrag**: `IOTAEditBlock.
  RemoveNotifier` setzt den Eintrag auf nil (Indizes bleiben stabil),
  `SendSyncEvent` prueft nicht darauf. Die Liste haengt am Editorblock der
  Ansicht und ueberlebt das Neuinstallieren des Pakets - das alte Paket
  hatte seine Notifier beim Entladen abgemeldet. Erklaert auch Lauf 1
  (Abmelden bei Exit -> Strg+Z stuerzt) und vermutlich Lauf 2. Folge:
  **keine IOTASyncEditNotifier** - ohne Abmelden blieben Verweise auf
  entladenen Code, mit Abmelden entstehen nil-Eintraege. Die Sitzung wird
  per "Sonde: Sitzung jetzt" abgefragt. Ob B1 (eigene Punkte) ohne
  Notifier stabil ist, ist wieder offen.
- **Lauf 5 (2026-10-11, C1, IDE vorher KOMPLETT neu gestartet):** fuenf
  Starts (Fall 1 mit zwei Ersetzungen, Fall 4 Bruchzahl, Fall 5 Tab/Hex)
  ohne jeden Fehler: SyncMode 1 (normaler Sync Edit), Caret auf dem Namen
  in der Deklaration, Puffer wie geplant; Strg+Z stellte Fall 1 und Fall 5
  wieder her. Damit bestaetigt: die Abstuerze kamen von den nil-Eintraegen
  frueherer Paketversionen (Nico: die IDE war vor Lauf 4/5 NICHT neu
  gestartet). Fall 3 (999 hinter 'then') wurde wie vorgesehen abgelehnt.
  Neu gesehen: C1 auf einem Literal, das schon allein der Wert einer
  Deklaration ist ('var MagicNr01 := 42;'), baute eine zweite Variable
  davor ('var MagicNr05 := 42;' / 'var MagicNr01 := MagicNr05;') - jetzt
  abgelehnt ("hat bereits einen Namen"). Die Nummer zaehlt hoch, solange
  aeltere MagicNrNN in der Datei stehen.
- **Pruefen, welches Paket laeuft:** im Menue Tools > VarNameProject
  muessen "C1 ...", "B1 eigene Punkte (Bytes), ohne Notifier" und "Sonde:
  Sitzung jetzt" stehen. Steht dort noch C2 oder B1a, ist ein altes Paket
  geladen - neu bauen, neu installieren, IDE neu starten.

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
- **M9** Fall 3 (999 hinter `then`): seit 2026-10-11 (Nicos Entscheid)
  kein Abbruch mehr - der Zweig wird zum Block: `begin` unter die
  then-Zeile, darin die Deklaration und die Anweisung, `end;` darunter
  (ein Strg+Z). Der Kommentar in der Demo sagt noch "ABGELEHNT".
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
  `try` ...). Endet sie mit `then`/`do`/`else` (Zweig ohne begin), kommt
  ein `begin..end` um Deklaration und Anweisung - nur wenn die Anweisung
  auf ihrer Zeile mit `;` endet (mehrzeilige Anweisungen und solche vor
  `else` grenzt der Text-Leser nicht ab -> Abbruch). In reDelphix soll
  dafuer der vorhandene Block-Planer (SCA101, WrapInBlock) einspringen.
- Nie vor einem case-Zweig, einer Sprungmarke oder einem on-Handler
  (`1: ...`, `Fertig: ...`, `on E: X do ...`) - dort ist eine Deklaration
  dazwischen ungueltig.
- Nie, wenn das Literal schon allein der Wert einer Deklaration ist.
- Typ: `var X := 3.5` wird Extended, `$FFFFFFFF` Cardinal/Int64 - fuer den
  Test egal, fuer die echte Hilfe in reDelphix nicht.
- Kommentare ueber Zeilen vor der Caret-Zeile sieht der Leser nicht.
