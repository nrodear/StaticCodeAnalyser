# VarNameProject - Testprojekt "Lokale Konstante einfuehren"

Zweck: klaeren, wie reDelphix einen NEUEN Namen erfragt, ohne Dialog -
so wie ReSharper "Introduce Variable" (Nico 2026-10-11, Entscheid E17 im
Konzept "Editorhilfen ohne Fund" - seit 2026-10-11 heissen sie Code-Aktionen,
zu einem Fund Quick-Fix, ohne Fund Refactoring; diese hier hiess "Lokale
Variable einfuehren" und heisst seit Entscheid E26 (2026-10-13) **"Lokale
Konstante einfuehren"**: die Deklaration ist `const MagicNr01 = 42;`, keine
Variable - siehe "Entscheide" und die Kompilierprobe):

1. Der Code entsteht mit einem vorlaeufigen Namen, z. B. `MagicNr01`.
2. Es geht inline weiter - kein Fenster.
3. `MagicNr01` wird umrandet, der Caret steht darauf.
4. Tippen aendert den Namen, alle Stellen von `MagicNr01` aendern sich mit.

Die Delphi-IDE hat dafuer einen eingebauten Mechanismus: **Sync Edit**
(Strg+Umschalt+J) bzw. die editierbaren Punkte der **Live Templates**. Die
ToolsAPI legt ihn offen: `IOTAEditBlock.SyncEditBlock(Points)` mit
`IOTASyncEditPoints`/`IOTASyncEditPoint` (Name, Text, mehrere Offsets,
editierbar), `IOTASyncEditNotifier` fuer die Ereignisse und
`IOTACodeTemplateServices` fuer die Templates. Dieses Projekt misst, welcher
Weg stabil traegt.

## Aufbau

| Datei | Inhalt |
|---|---|
| `package/VarNameProject.d12.dpk/.dproj` | Entwurfszeit-Paket (rtl, vcl, designide) - eigenstaendig, ohne SCA.Engine und reDelphix |
| `source/uVnpPlan.pas` | reine Textlogik (auch unter FPC): Zahl-Literal am Caret, gleiche Literale der Zeile, Deklarationszeile `const MagicNrNN = <Literal>;` (E26), Spalten danach, freier Name, begin..end fuer Zweige, Ablehnungen der Zeile, FPC-Weiche, Template-Code fuer D1 |
| `source/uVnpEdits.pas` | was am Puffer geaendert wird, ohne ToolsAPI (auch unter FPC): Text-Schnappschuss (Zeilen, Byte-Anfaenge, Zeilenende je Zeile), Ziel an der Caret-Position samt dem Zusammenhang ueber Zeilen (mehrzeilige Strings und Kommentare, asm, initialization, FPC-Weiche, Direktiven, Kommentargrenzen eines begin..end, Bedingungsausdruck), die Ersetzungen des Writers fuer C1h, Loeschen/Zurueckschreiben der Anweisung fuer D1, Template-Datei, eigenes Template erkennen; `ApplyByteEdits` stellt den Writer fuer die Tests nach |
| `source/uVnpIntroduce.pas` | Ablauf in der IDE: Sperren pruefen, Fokus, planen, dann C1h (Ersetzungen mit einem Writer, Block markieren, IDE-Sync-Edit) oder D1 (Live Template laden, Anweisung ersetzen per `InsertCode`); Sonde "Sitzung jetzt" |
| `source/uVnpSync.pas` | Prozess-Merker nach einer Zugriffsverletzung; Sonde N1 (Dummy-Notifier fuer Hypothese H1) |
| `source/uVnpLog.pas` | Protokoll: `%TEMP%\VarNameProject.log` (jede Zeile mit PID, Kopfzeile je Ladung) und Meldungsansicht (Gruppe "VarNameProject") |
| `source/uVnpProbe.pas` | Sonden ohne Sitzung: Einheit von `CharIndex` (M10), was `CreateClass` liefert (M21); Zeile frisch aus dem Puffer |
| `source/uVnpRegister.pas` | Menue Tools > VarNameProject; Abbau im Destruktor eines Wizards |
| `tests/VarNameProject.Test.dpr/.dproj` | DUnitX-Testprojekt (Konsole bzw. TestInsight) fuer den ToolsAPI-freien Teil, siehe "Tests" |
| `tools/fpc-pruefstand/build.sh` | dieselben Tests ohne IDE unter FPC 3.2.2 |
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
  Sync-Edit-API und die Template-Dateien sind in 12 und 13 gleich. Ob die
  Sprungpunkte der Templates in 13 noch gehen, ist offen (D-M9).

## Varianten

| Variante | Weg | gekoppelt | Ende der Sitzung |
|---|---|---|---|
| C1h | eigener Writer (ein Strg+Z), Block vom Namen in der Deklaration bis hinter seine letzte Verwendung, dann `SyncEditBlock(nil)` = Strg+Umschalt+J | JEDER Bezeichner, der im Block mehrfach vorkommt (in Fall 1 nur `MagicNr01`) | der Knopf im Rand. Gemessen (UI-Test 2026-10-11): Enter tut nichts, **Esc zerstoert Text** - eine Sitzung der Code-Aktion darf Esc nie an das Sync Edit durchlassen |
| D1 | Live Template zur Laufzeit: XML nach `%TEMP%\VarNameProject\tpl`, `LoadTemplates`, Anweisung loeschen, `InsertCode` | nur der Name (ein Punkt, alle Stellen gleichnamig) | laut Hilfe Enter oder Tab am letzten Punkt (ungemessen - D1 lief nicht; Esc dort ungeprueft) |

Beide nur mit IDE-eigenen Objekten und ohne Notifier. Vor jedem Lauf:
Abbruch, wenn der Prozess-Merker gesetzt ist (Zugriffsverletzung in einem
frueheren Lauf) oder schon eine Sitzung laeuft; der Editor bekommt den
Fokus, bevor die Sitzung startet.

D1 im Einzelnen: findet sich das Template nach `LoadTemplates` nicht in der
Liste der IDE (oder ersetzt der Aufruf die Liste), greift der Rueckfall
B-b: dieselbe Datei nach `Documents\Embarcadero\Studio\code_templates\VarNameProject`
und `ReloadTemplates`. Das eigene Template (`vnpintro`, `invoke="none"`)
wird beim naechsten D1-Lauf und beim Abbau wieder aus der Liste genommen,
die Dateien geloescht. Liefert `InsertCode` False, kommt die geloeschte
Anweisung zurueck; der Originaltext steht ausserdem im Protokoll.

Entfallen: A1/A2 (Punkte per `IOTACodeTemplateServices.CreateClass` -
Ergebnis M21), B2 (relative Offsets), alle Notifier-Varianten (Lauf 4),
**B1** (eigene Punkt-Klassen: die IDE liest ihre Offsets als Bytes, Lauf 3,
und haelt die Objekte in Sitzung und Undo-Liste - D1 erreicht denselben
Template-Modus mit IDE-eigenen Objekten), C1 (jetzt C1h).

## Bedienung

1. `package/VarNameProject.d12.dproj` bauen und installieren, danach die
   **IDE komplett beenden und neu starten** (im Task-Manager pruefen, dass
   keine bds.exe mehr laeuft).
2. Kopfzeile im Protokoll: `### VarNameProject: PID ..., Prozessstart ...,
   Ladung 1 ...`. Eine neue PID heisst neuer Prozess; "Ladung 2" heisst:
   im selben Prozess neu installiert.
3. `demo/VarNameDemo.pas` im Editor oeffnen, Caret auf eine Zahl setzen
   (siehe Faelle in der Datei).
4. Tools > VarNameProject > C1h oder D1; danach wiederholt
   **Strg+Alt+Umschalt+M** die zuletzt gewaehlte (Start: C1h).
5. **Strg+Alt+Umschalt+O** ("Sonde: Sitzung jetzt") - SyncMode, Caret,
   Datei, Geaendert-Zustand und die beiden Zeilen frisch aus dem Puffer.
   Schreibt NUR in die Protokolldatei (fasst die Sitzung nicht an); die
   Meldungsansicht holt die Zeilen beim naechsten Eintrag nach.
6. Das Protokoll ueber Tools > VarNameProject > "Protokolldatei ausserhalb
   der IDE oeffnen" lesen (Standardprogramm fuer .log). NICHT im IDE-Editor
   oeffnen: dann waere es die oberste Ansicht, und die IDE fragt beim
   Weiterschreiben nach dem Neuladen.
7. Nach einer Zugriffsverletzung: Schritt notieren, im selben Prozess nicht
   weitertesten (alle Laeufe sind dann ohnehin gesperrt), Dateien sichern,
   IDE beenden.

## Testplan dieser Iteration (Gutachten 2026-10-11, Abschnitt 4)

0. Die Demo-Dateien muessen auf dem Repo-Stand sein: in VarNameDemo.pas
   Fall 5 als `<TAB>Result := Value and $FF00;` (nicht schon umgewandelt -
   sonst lehnt die Hilfe ab: "hat bereits einen Namen"), in
   VarNameDemoUmlaut.pas Fall 6 als `Count * 42` ohne Leerzeile davor.
   Zuruecksetzen per `git checkout -- VarNameProject/demo` (schreibt CR LF,
   `.gitattributes`; dann sagt auch D1s Zeile "Einzelne LF" etwas) oder in
   der IDE die Aenderungen verwerfen.
1. Alle bds.exe beenden (Task-Manager).
2. IDE starten, VarNameProject nicht anfassen, IDE schliessen. Notieren:
   Fehlermeldung ja/nein.
3. IDE starten, bauen, Paket installieren, IDE schliessen. Notieren:
   Fehlermeldung ja/nein.
4. IDE starten: neue PID und "Ladung 1" in der Kopfzeile, im Menue C1h, D1,
   N1 an/ab, kein B1.
5. Referenz ohne unseren Code: in VarNameDemo.pas die Zeilen 17-21
   markieren, Strg+Umschalt+J, `Value` umbenennen, Enter (bricht die Zeile
   um oder endet die Sitzung?), Esc, Strg+Z bis zum Ausgangszustand
   (zaehlen).
6. C1h, Fall 1: Caret auf die erste 42, Strg+Alt+Umschalt+M, dann
   Strg+Alt+Umschalt+O.
7. Neuen Namen tippen, O.
8. Enter, O.
9. Esc, in die Meldungsansicht klicken, zurueck in den Editor.
10. Strg+Z, bis die 42 wieder dasteht (Anzahl notieren), O.
11. Schritte 6-10 mit Fall 6 (VarNameDemoUmlaut.pas): sitzen die Rahmen
    hinter dem Euro-Zeichen richtig?
12. Schritte 6-10 mit D1 fuer die Faelle 1, 6 und 5: ist nur MagicNr
    gekoppelt? Beendet Enter, ohne umzubrechen? Stimmt die Einrueckung in
    Fall 5 (Tab)? D1 zweimal nacheinander: steht `vnpintro` danach nur
    einmal in Strg+J? Kommt beim Entfernen eine Rueckfrage?
13. Waehrend einer laufenden C1h-Sitzung Strg+Alt+Umschalt+M. Erwartet:
    "Abbruch: Sync-Sitzung laeuft".
14. IDE schliessen. Notieren: Fehlermeldung ja/nein; im Protokoll muss
    "Abbau (Wizard-Destruktor)" mit allen Schritten stehen und danach
    "Abbau (finalization): schon erledigt".
15. IDE starten, Test N1 (zerstoert den Prozess, wenn H1 stimmt):
    alles speichern; in VarNameDemo.pas "N1 an"; Zeilen 17-21 markieren,
    Strg+Umschalt+J, Esc (Ereignisse stehen in der Datei); "N1 ab"; in
    VarNameDemoUmlaut.pas die Funktion `Greeting` markieren, 2 s warten,
    Strg+Umschalt+J; ohne Absturz danach in VarNameDemo.pas Zeilen 17-21
    markieren, Strg+Umschalt+J. Danach die IDE beenden.
16. Protokoll und Notizen zu den Schritten 2, 3, 5, 14 und 15
    zurueckmelden.

Auswertung H7: Fehler in Schritt 2, keiner in Schritt 3 -> belegt und
behoben. Kein Fehler in Schritt 2 -> der Absturz braucht vorherige
Sitzungen, dann zaehlt Schritt 14.
Auswertung N1: AV ("Lesen von Adresse 00000000") schon in der anderen Datei
-> H1 belegt, die Liste gilt fuer den ganzen Prozess; erst in derselben
Datei -> H1 belegt, je Ansicht; keine AV -> H1 widerlegt.

## Tests

Nico 2026-10-11: "erstelle auch tests um die editorhelper zu testen". Der
ToolsAPI-freie Teil (`uVnpPlan`, `uVnpEdits` - genau die Units, die das
Paket benutzt) hat ein DUnitX-Testprojekt, `tests/VarNameProject.Test.dproj`
(Konsole; mit TestInsight in der IDE). Die Tests pruefen den TEXT, der
danach im Puffer steht - `uVnpEdits.ApplyByteEdits` stellt den
IOTAEditWriter nach -, nicht nur Offsets.

| Testunit | Tests | Inhalt |
|---|---|---|
| `uTestVnpPlan` | 15 | Literal am Caret, gleiche Literale (nur Code), Formen (hex, Bruch, Exponent, `_`, Bereich), Spalten, Kommentare (auch `*)` in Spalte 1), freier Name (auch ueber 99 hinaus), FPC-Weiche, Bytes/Zeichen; alle 44 Pruefungen des frueheren Ad-hoc-Tests |
| `uTestVnpRefuse` | 9 | begin..end fuer den Zweig, alle Ablehnungen (case-Zweig, Sprungmarke, on-Handler, Zeilenanfang, schon benannt - `var X := 42;` wie `const X = 42;`, Konstanten, Deklarationszeilen, Zeile darueber) |
| `uTestVnpGuards` | 18 | Schutzregeln aus dem Korpus-A/B und dem Review vom 2026-10-13: Routinen-Koepfe und Eigenschaften (auch Fortsetzungen `message`/`dispid`/`external`/`stdcall` auf der Folgezeile; `Register<Integer>(42)` und `Register; X := 42` sind Anweisungen), Typ-/Sprungmarken-/asm-/exports-/Attribut-Zeilen, typisierte Konstanten, generische Deklarationen, case-Marken hinter `for`, on-Handler ohne Variable, zweite `var`/`const` hinter einer Anweisung, Zeilen, die einen Ausdruck oder eine Liste fortsetzen, Schluesselwoerter hinter Kommentaren, `initialization` darueber, `else` des eigenen `if`, offene Bloecke, Bedingungsausdruck in der Zeile darueber, Direktiven zwischen Zweig und Anweisung, mehrzeilige Strings, Ende des Sync-Blocks |
| `uTestVnpEdits` | 20 | C1h Ende zu Ende: Demo-Faelle 1-6 (CR LF, LF, BOM, Umlaute und Euro VOR dem Literal), Text-Schnappschuss (Zeilenende je Zeile, BOM in Zeile 1), Zeile darueber, Ziel am Caret, Writer-Vertrag |
| `uTestVnpContext` | 17 | Zusammenhang ueber Zeilen in `TargetAt` (Review 2026-10-13, Gegen-Review 2026-10-14): mehrzeilige Strings mit fuenf Quotes und `''' + '''`, Kommentar- und String-Zustand in einem Lauf, asm-Block (auch Sprungmarke `@end:`), initialization-Abschnitt, FPC-Weiche, Direktive auch ohne Block und auf der Zeile darueber, Zeile darueber ab ihrem Kommentar-Zustand, `*)` in Spalte 1, Kommentargrenzen eines begin..end, Bedingungsausdruck mit Armen auf eigenen Zeilen, Zeilenenden je Zeile, Vorbedingung von `IntroduceEdits` |
| `uTestVnpTemplate` | 20 | D1: Template-Code, Template-XML (wie `ifnil.xml`), eigenes Template erkennen, Anweisung loeschen/zurueckschreiben, Modell der Template-Expansion (Annahme D-M3 - in der IDE zu bestaetigen) |

Ohne IDE: `bash VarNameProject/tools/fpc-pruefstand/build.sh` (alle
`tests/uTestVnp*.pas`; `WORK=<ordner>` fuer parallele Laeufe). Stand
2026-10-14: 92 von 92 gruen (2026-10-11: 73 von 73). Die Erwartungen haben
unabhaengige Agenten von Hand aus dem Vertrag abgeleitet
(Interface-Kommentare, README, Demo-Dateien); Gegenpruefer haben mit
Mutationstests nachgesehen, dass die Tests Fehler auch finden. Dazu lief ein
Korpus-A/B: alter gegen neuen Plan ueber 8 Mio. Zeilen von
`D:\git-sca-realworld` (1,07 Mio. Caret-Positionen) - jede Abweichung musste
eine beabsichtigte Regel erklaeren. Das Review vom 2026-10-13 (Bericht F,
FPC-Harness mit 24 Gegenbeispielen) fand weitere Luecken des Zeilen-Lesers;
alle 24 Faelle verhalten sich seit 2026-10-14 wie beabsichtigt.

Gefunden und behoben, alles mit Test:
- zwei Anweisungen in der Zweigzeile (`Y := 42; Z := 1;`): begin..end um
  die ganze Zeile - `Z := 1` lief danach nur noch im Zweig (still
  geaendertes Verhalten); ebenso eine Zweigzeile, die einen Block oeffnet
  (`for ... do begin X := 42;` - der Rest des Schleifenrumpfs fiele
  heraus);
- `else` in der Zweigzeile: begin..end schloss das else ein - ausser es
  gehoert zu einem `if` derselben Zeile (`if C then A else B;` ist EINE
  Anweisung);
- ein Bezeichner mit Nicht-ASCII-Buchstaben vor einer Ziffer (`Mass2` mit
  sz): die Ziffer galt als Literal, der Bezeichner wurde zerstoert;
- `(*)` schloss den Kommentar sofort wieder - Literale im Kommentar wurden
  ersetzt;
- mehrzeilige Strings (Delphi 12): die Hilfe aenderte still ihren Inhalt;
- Zahlen, die Konstanten bleiben muessen, wurden angeboten (E2026):
  `const`-Zeilen, der Typ einer Inline-var, Deklarationen `Name = ...`,
  Routinen-Koepfe mit Vorgabewerten, dispid, message, `property ...
  default`, case-Marken-Listen, `goto`/`label`, Attribute;
- `{$IFDEF}` zwischen Zweig und Anweisung: begin und end landeten in
  verschiedenen Zweigen;
- die obere Grenze eines Bereichs (`0..9`) war kein Literal; `for var I:
  Integer := ...` und `Writeln(X:8:2)` wurden als Sprungmarke abgelehnt.

Review 2026-10-13 (Bericht F, behoben 2026-10-14, alles mit Test):
- `var MagicNr01 := 1;` rechnete anders als das Literal (`C - 1` mit `C:
  Cardinal` ergab -1 statt 4294967295; Integer- statt ShortInt-/Byte-
  Ueberladung) - seit E26 eine Inline-Konstante;
- ein mehrzeiliger String mit fuenf Quotes galt an einer Inhaltszeile mit
  drei Quotes als beendet - die Deklaration landete IM String;
- begin..end um einen Zweig, dessen Zeile in einem offenen Kommentar
  endet (`X := 42; { Kommentar`): `end;` landete im Kommentar, Code hinter
  dem Kommentarende rutschte in den Block; ebenso `begin` hinter einer
  Zweigzeile mit offenem Kommentar;
- Fortsetzungen eines Routinen-Kopfs auf der Folgezeile (`message WM_USER
  + 5;`, `dispid 5;`, `external 'x.dll' index 5;`), Zeilen im asm-Block,
  eine zweite Deklaration hinter einer Anweisung (`Foo; var A: array[0..9]
  of Byte;`, `Foo; const C = 5;`) bekamen eine Deklaration;
- eine Direktive zwischen der Zeile darueber und der Anweisung wurde nur
  mit Block geprueft (`{$IFDEF A} if B then {$ELSE} Foo; {$ENDIF}`);
- die Zeile darueber wurde ab Code gelesen, auch wenn sie in einem
  Kommentar beginnt (`{ Bsp:` / `Foo; // } if A then`);
- `*)` in Spalte 1 schloss den Kommentar schon am `*`, das `)` galt als Code;
- der else-Arm eines Bedingungsausdrucks (Delphi 13: `X := if C then A` /
  `else` / `Foo(42);`) bekam begin..end mitten im Ausdruck;
- eingefuegte Zeilen bekamen CR LF, sobald es irgendwo in der Datei vorkam
  - jetzt das Zeilenende ihrer Nachbarzeile;
- der Rueckfall `MagicNrX` nach 99 Namen war ungeprueft - jetzt `MagicNr100`
  usw. gegen den Text geprueft;
- `IntroduceEdits` ohne gueltigen Plan lief in einen Bereichsfehler;
- Dateien mit FPC-Weiche: eine Inline-Konstante gibt es in FPC 3.2 nicht.

Nicht ohne IDE pruefbar: Sync Edit, `InsertCode`, Fokus, Abbau - dafuer der
Testplan oben.

## Ergebnisse

- **M10 (2026-10-11):** `TOTACharPos.CharIndex` aus `ConvertPos` zaehlt
  **Zeichen**, nicht UTF-8-Bytes: hinter dem Euro-Zeichen in Fall 6 (20
  Zeichen, 24 Bytes davor) meldet die IDE CharIndex 20, die Rueckrechnung
  ergibt dieselbe Anzeigespalte. **`CharPosToPos` addiert CharIndex aber
  als Bytes** zum Zeilenanfang (Differenz 20 statt 24) - auf Zeilen mit
  Nicht-ASCII vor der Stelle ist es also falsch; Pufferpositionen selbst
  rechnen (Reader-Bytes). Die erste Fassung bestimmte die Caret-Spalte ueber
  `CharPosToPos` und lag dadurch hinter dem Euro-Zeichen 4 Spalten daneben
  ("kein Zahl-Literal am Caret") - behoben. Dieselbe Byte-Annahme stand in
  reDelphix (`uRdxEditor.DisplayPosOf`, Markieren per `SelectSpan`) - dort
  ebenfalls korrigiert.
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
  `TSyncEditManager.SendSyncEvent`).
- **Lauf 2 (2026-10-11, B1a: Punkte und Notifier gehalten):** Sitzung wie
  in Lauf 1. Absturz diesmal beim **Fokuswechsel** (Klick in eine
  Baumansicht -> `EditorControl.WMKillFocus` ->
  `KbClient.TIDEKBDChildAPI.KBDClearPrimFocus`), im selben Prozess nach der
  AV aus Lauf 1. Ungeklaert: eine andere Absturzstelle, und der Notifier
  war dort noch angemeldet - H1 (unten) erklaert ihn NICHT; vermutlich
  Folgeschaden der ersten AV (H5) oder Altlast der eigenen Punkte (H6).
- **Lauf 3 (2026-10-11, Fall 6, vermutlich noch B1a aus dem alten Paket):**
  direkt nach dem Start, vor jeder Eingabe, stand im Puffer
  `IntToStr(CounMagicNr01Nr01)` statt `IntToStr(Count * MagicNr01)` - der
  Editor zeigte noch den alten Text, die Datei war nicht als geaendert
  markiert. Unser Schreiben war richtig; im Template-Modus schreibt die IDE
  den Punkttext an jede Fundstelle und las CharIndex 42 dabei als **Byte**
  42 (= Zeichen 39, das 't'). Die ToolsAPI ist also uneinheitlich:
  `ConvertPos` zaehlt Zeichen, die Offsets der Sync-Punkte (wie
  `CharPosToPos`) UTF-8-Bytes.
- **Lauf 4 (2026-10-11, C1 - ohne eigene Objekte):** Absturz schon beim
  Start: `TInterfaceList.Get` -> `TSyncEditManager.SendSyncEvent` ->
  Zugriffsverletzung beim Lesen von Adresse 0. Die IDE war seit den
  Paketen mit Notifiern (e75bfeba..294336a3, An- und Abmelden) NICHT neu
  gestartet (Nico). **Wahrscheinlichste Erklaerung (H1), nicht bewiesen:**
  `IOTAEditBlock.RemoveNotifier` laesst einen nil-Eintrag in der
  Notifier-Liste stehen (die API ist indexstabil), und `SendSyncEvent`
  prueft nicht darauf. Passt auch zu Lauf 1 (Abmelden bei Exit, dann
  Strg+Z). Nico: zwischen Lauf 3 und Lauf 4 war die Demo-Datei
  geschlossen - die Ansicht war also neu und stuerzte trotzdem; das
  spricht dafuer, dass die Liste fuer den ganzen Prozess gilt, nicht je
  Ansicht. Belegen soll es Test N1. Folge: **kein IOTASyncEditNotifier**
  (ausser der Sonde N1); die Sitzung wird per Sonde abgefragt.
- **Lauf 5 (2026-10-11 11:26, C1, Fall 6, derselbe Prozess wie Lauf 4,
  weiter ohne Neustart):** wieder die AV in `SendSyncEvent` - passt zu H1,
  widerlegt sie nicht.
- **Lauf 6 (2026-10-11 ab 11:50, C1, frisch gestarteter Prozess):** sechs
  Starts (Fall 1 mit zwei Ersetzungen, Fall 4 Bruchzahl, Fall 5 Tab/Hex)
  ohne jeden Fehler: SyncMode 1 (normaler Sync Edit), Caret auf dem Namen
  in der Deklaration, Puffer wie geplant; das Umbenennen koppelte alle
  Stellen (`__history`: `var mytest := 42; Result := Value * mytest +
  mytest;`). Nico: EIN Strg+Z nahm Einfuehren und Umbenennen zusammen
  zurueck (M7/M22). In diesem Prozess lief auch B1 (Nico) - Lauf 6 belegt
  also nur: **im frischen Prozess ohne Notifier laeuft C1 stabil**; die
  Ursache der AVs ist damit nicht bewiesen, und die AV beim Schliessen
  kann auch von B1-Altlasten kommen (H6) statt von H7.
  Fall 3 (999 hinter `then`) wurde damals noch abgelehnt (seither
  begin..end, M9). Neu gesehen: C1 auf einem Literal, das schon allein der
  Wert einer Deklaration ist (`var MagicNr01 := 42;`), baute eine zweite
  Variable davor - jetzt abgelehnt ("hat bereits einen Namen"). Die Nummer
  zaehlt hoch, solange aeltere MagicNrNN in der Datei stehen.
- **Beim Schliessen der IDE (H7):** jeder Prozess, in dem VarNameProject
  lief, endete mit einer Zugriffsverletzung in rtl290 (`+0x13211c`,
  Ereignisprotokoll) - auch der Prozess aus Lauf 6 (dort lief aber auch
  B1). Vermutung: die
  finalization gab Menue und Aktionen frei, die MainMenu und ActionList der
  IDE schon freigegeben hatten (eine ActionList gibt ihre Aktionen selbst
  frei; SCA und GExperts bauen deshalb frueher ab). Jetzt: Abbau im
  Wizard-Destruktor, Menue und Aktionen in einer `TComponentList`
  (FreeNotification), finalization nur als Netz; jeder Schritt im
  Protokoll. Testplan Schritte 2, 3 und 14.
- **Sondentaste:** Strg+Alt+Umschalt+P feuerte nie - in der
  Default-Belegung ist sie "Sync Prototypes", und Tastenbindungen gehen
  Menuekuerzeln vor. Jetzt Strg+Alt+Umschalt+O.
- **Pruefen, welches Paket laeuft:** die Kopfzeile im Protokoll (PID,
  Ladung) und im Menue Tools > VarNameProject "C1h ...", "D1 ...", "N1 an"
  und "Sonde: Sitzung jetzt (nur Protokolldatei)". Steht dort noch C1 oder
  B1, ist ein altes Paket geladen - neu bauen, neu installieren, IDE neu
  starten.
- **UI-Test 2026-10-11 abends (Testplan oben, Protokoll + Nicos Angaben):**
  - **IDE-Ende ohne Fehlermeldung (H7 behoben):** in jedem Prozess "Abbau
    (Wizard-Destruktor)" mit allen Schritten, danach "finalization: schon
    erledigt"; "die IDE hatte das Menue schon freigegeben" zeigt, dass die
    FreeNotification greift. Einzige Spur: "Meldungsgruppe abmelden" laeuft
    beim IDE-Ende in eine abgefangene Zugriffsverletzung (Lesen von
    00000008) - die Meldungsansicht ist dann schon weg. Nur Labor;
    reDelphix bekommt keine Meldungsgruppe.
  - **H1 belegt (Test N1):** N1 an/ab am Block von VarNameDemoUmlaut.pas,
    danach stuerzte das naechste `SyncEditBlock` in derselben Datei mit
    "Lesen von Adresse 00000000" in coreide290 ab - genau der vorhergesagte
    nil-Eintrag. `IOTASyncEditNotifier` bleibt verboten; ob die Liste je
    Ansicht oder fuer den ganzen Prozess gilt, ist weiter offen.
  - **Fall 6 startete keine Sitzung:** C1h schrieb richtig, aber nach
    `SyncEditBlock` stand `SyncMode 0` und der Caret auf 25:48 statt 25:52
    (sechs Versuche, drei Prozesse; ASCII-Faelle jedes Mal SyncMode 1).
    Der String vor dem Literal (ue, ss, Euro-Zeichen) hat 4 Bytes mehr als
    Zeichen: SyncEditBlock liest das
    Blockende als UTF-8-Bytes, der Block endete mitten im zweiten
    `MagicNr01`. Behoben: `uVnpEdits.SyncBlockEnd` setzt das Ende auf
    solchen Zeilen an den Anfang der Folgezeile (Test
    `Context_SyncBlockEnd`). Nachtest 23:28 (Nico, Schritt 11): Block 25:7 -
    27:1, SyncMode 1, Rahmen um beide Stellen - gruen.
  - **Enter tut in der C1h-Sitzung nichts** (kein Umbruch, die Sitzung
    laeuft weiter); Umbenennen aendert alle Stellen.
  - **Esc macht den Text kaputt - auch im normalen Sync Edit ohne unseren
    Code** (Schritt 5, Fall 1: Zeichen verschoben). Das ist Verhalten der
    IDE; eine Sitzung der Code-Aktion darf Esc nie an das Sync Edit der IDE
    durchlassen. Enter und Esc fangen deshalb erst der Labor-Prototyp
    (Entscheid E25), dann das Produkt ab.
  - **Strg+Z:** einmal - Einfuegen und Umbenennen sind ein Undo-Schritt.
  - **D1 lief nicht** (keine D1-Zeile im Protokoll). Entscheid Nico: nur
    C1h kommt nach reDelphix, D1 bleibt im Labor.

## Entscheide und naechste Iteration (Nico 2026-10-11)

- Name: der Oberbegriff fuer "Editorhilfe" ist **Code-Aktion** - zu einem
  Fund ein **Quick-Fix**, ohne Fund ein **Refactoring**; diese Funktion
  heisst **"Lokale Variable einfuehren"**.
- **Enter beendet die Namenseingabe** (wie ReSharper). Bricht C1h dabei
  die Zeile um (Testplan Schritt 8), wird D1 Pflicht.
- **Dialog "behalten oder verwerfen"**: endet die Eingabe ohne Enter -
  Caret woanders, Klick, Fokuswechsel -, fragt ein Dialog, ob die Variable
  mit dem aktuellen Namen bleibt oder die ganze Einfuehrung zurueckgeht
  (Literale wieder da). **Esc** beendet ohne Dialog mit dem aktuellen
  Namen. Offen fuer den Bau: wie das Projekt das Ende der Sitzung erfaehrt
  ohne IOTASyncEditNotifier (H1) - Kandidat ein Timer, der SyncMode und
  Caret abfragt; Enter/Esc von "Caret woanders" unterscheidet die
  Caret-Position beim Ende (D1: Enter setzt den Caret auf `|end|`).
- **Umzug nach reDelphix** (Nico: "bei gruen [Testplan] das Projekt und
  die DUnitX-Tests in das reDelphix-Projekt bringen"): eigener Einstieg in
  reDelphix (Wizard, Menue, Taste), erst 1:1, Zusammenfuehren mit
  `uRdxCodeMap`/`WrapInBlock`/`ReplaceSpans` danach mit Korpus-A/B; Enter
  und Dialog entstehen zuerst hier im Labor.
- **Inline-Konstante (E26, Nico 2026-10-13)**: zuerst war eine typisierte
  Variable `var MagicNr01: <Typ> := 42;` vorgesehen. Die Kompilierprobe
  (Win32, D12) zeigte, dass keine Typregel das Literal trifft: `var
  MagicNr01 := 1` bzw. `: Integer` rechnete `C - MagicNr01` mit `C:
  Cardinal` als -1 statt 4294967295 (P2.33/34), waehlte Integer- statt
  ShortInt-/Byte-Ueberladungen (P4.9-16), und `var M := 100000` bekam einen
  anonymen 32-Bit-Typ (P1.2). Entscheid: die Deklaration wird eine
  **Inline-Konstante `const MagicNr01 = 42;`** - sie behaelt Faltung,
  Ueberladungswahl und die vorzeichenlose Rechnung des Literals. Die Aktion
  heisst seither "Lokale Konstante einfuehren". Beleg: Teil P6 der Probe
  (Bau offen). Folge: in Dateien mit FPC-Weiche (FPC 3.2 kennt keine
  Inline-Konstante) lehnt die Aktion ab.

## Kompilierprobe E26 (`probe/VnpTypeProbe.dpr`)

Konsolenprogramm ohne `.dproj` (wie `tools/ResultProbe`): die `.dpr` in der
IDE oeffnen, Win32 bauen, ausfuehren; wenn moeglich Win64 ebenso. Es misst,
wie der Compiler mit dem Code rechnet, den die Code-Aktion schreibt - P1
bis P5 fuer die Variable (Win32-Lauf 2026-10-13, Ergebnis: siehe E26), P6
fuer die Inline-Konstante:

| Teil | Frage |
|---|---|
| P1 | Welchen Typ bekommt die fruehere Form `var M := <Literal>` (42, 2147483648, `$FFFFFFFF`, `$FFFFFFFFFFFFFFFF`, 3.5, `1_000_000` ...)? |
| P2 | Gefaltetes Original (`100000 * 100000`, `1 shl 40`, `$FFFFFFFF + 1`, `1 shl 31`, `(-8) shr 1`) gegen Integer-, Int64- und Cardinal-Variable; Literal neben einer Laufzeit-Variablen (`N * 100000`) |
| P3 | Bitmuster von `0.1` und `0.1 * 3` ueber Extended-, Double- und untypisierte Variable |
| P4 | Ueberladungswahl: Literal gegen Variable (Integer/Int64, ShortInt, Byte, Single/Double[/Extended]) |
| P5 | Kompiliert eine Int64-, UInt64- oder Cardinal-Variable dort, wo Integer erwartet wird (SetLength, Copy, for, Inc, case, in ...)? |
| P6 | **E26:** dieselben Faelle wie P2, P3 und P4 mit `const MagicNr01 = <Literal>;` statt `var`; Sollwert ist jedes Mal das gefaltete Original (`1 shl 40` = 256, `C - 1` = 4294967295, `OvShort3(42)` = ShortInt ...). Wo das Original den Bau abbricht (E2099), ist derselbe Fehler die Erwartung - jeder dieser Faelle hat einen eigenen Schalter (`PROBE_P6_FOLD_*`, `PROBE_P6_BIGLIT_FOLD`), Standard an: bricht der Bau dort ab, ist das der Beleg, Schalter aus, weiter |

Jeder Messpunkt mit Kompilierrisiko steht hinter einem eigenen
`{$DEFINE PROBE_...}` (Standard: alle an; die P2-Originale mit E2099 sind
seit dem ersten Bau aus). Bricht der Bau ab, die betroffenen Schalter in
EINER Runde abschalten (`{.$DEFINE`) und die Fehlertexte melden - der
Fehler ist selbst ein Ergebnis. Die Compiler-Meldungen (vor allem
Warnungen in P2/P5/P6) mitkopieren; das Protokoll steht in
`%TEMP%\VarNameProject_TypeProbe.txt` (nach jedem Lauf in `..._Win32.txt`
bzw. `..._Win64.txt` umbenennen). Die `.dproj` und `.res`, die die IDE
anlegt, sind ignoriert.

## Was zurueckmelden (Messpunkte)

- **M1** Startet eine Sitzung? Protokoll "SyncMode" (0 keine, 1 normal,
  2 Templates) und sichtbar: sind die Stellen umrandet?
- **M2** Umrandet die Variante GENAU die `MagicNr01`-Stellen (nicht
  daneben, nicht weitere Bezeichner)?
- **M3** Steht der Caret auf dem Namen in der `var`-Zeile? Ueberschreibt
  Tippen den ganzen Namen (vorausgewaehlt) oder fuegt es ein?
- **M4** Aendern sich beim Tippen alle Stellen mit?
- **M5** Tasten: was tun Enter, Tab, Umschalt+Tab, Esc? Bleibt der neue
  Name nach Esc stehen?
- **M7/M22** Undo: wie viele Strg+Z bis zum Ausgangszustand (C1h: Schreiben
  ein Schritt; D1: Loeschen und Einfuegen mindestens zwei)?
- **M8** Fall 5 (Tab-Einrueckung): stimmen die Spalten?
- **M9** Fall 3 (999 hinter `then`): seit 2026-10-11 (Nicos Entscheid)
  kein Abbruch mehr - C1h macht den Zweig zum Block: `begin` unter die
  then-Zeile, darin die Deklaration und die Anweisung, `end;` darunter
  (ein Strg+Z). D1 lehnt den Fall ab. Der Kommentar in der Demo sagt noch
  "ABGELEHNT".
- **M11** Ist der Name nach dem Start vorausgewaehlt? (Das Projekt setzt
  den Caret danach bewusst NICHT mehr.)
- **M12/M13** Tab und Enter bei nur EINEM Punkt: springt Tab ins Leere,
  beendet Enter die Sitzung oder bricht es die Zeile um?
- **M17** Code-Insight-Popup waehrend des Tippens: nimmt Enter dann den
  Vorschlag statt die Sitzung zu beenden?
- **D-M1** D1: haengt `LoadTemplates` an oder ersetzt es die Liste?
  (Protokoll "Templates N -> N+1"; sonst "Rueckfall B-b")
- **D-M2** Liefert `InsertCode` True? (Kontext `methodbody`)
- **D-M3** Bekommt die zweite Zeile die Einrueckung der ersten (auch mit
  Tab, Fall 5)? Protokoll "ABWEICHUNG" nach InsertCode.
- **D-M4** Kommen Umlaute und Euro-Zeichen unversehrt an (Fall 6)?
  Protokoll "Code zurueck" und die Zeilen nach InsertCode.
- **D-M5** Undo: Strg+Z zaehlen.
- **D-M7** Steht `vnpintro` in Strg+J und im Templates-Fenster, solange es
  geladen ist?
- **D-M8** Loescht `RemoveTemplate` die Datei selbst? Gibt es eine
  Rueckfrage oder doppelte Eintraege?
- **D-M9** Delphi 13: Sprungpunkte ungeprueft (braucht ein .d13-Paket).

## Grenzen (bewusst - es ist ein Testprojekt)

Der Leser sieht eine Zeile, die Zeile darueber und - in `TargetAt` - die
Zeilen bis zur Caret-Zeile; einen Parser hat er nicht. Was er nicht sicher
abgrenzen kann, lehnt er ab (lieber nichts tun als falschen Code schreiben).

- Nur Zahl-Literale; nur gleiche Literale DERSELBEN Zeile werden ersetzt.
  Die obere Grenze eines Bereichs (`0..9`) ist ein eigenes Literal.
- Die Deklaration kommt als Inline-`const` (Delphi 10.3+, E26) direkt
  ueber die Zeile; die Zeile darueber muss eine Anweisung beenden (`;`,
  `begin`, `try` ...). Beginnt sie in einem Kommentar, zaehlt nur ihr Code
  hinter dessen Ende (`{ Bsp:` / `Foo; // } if A then` ist ein Zweig).
  Steht auf der Zeile darueber oder zwischen ihr und der Anweisung eine
  Direktive (`{$IFDEF}`, auch `Foo; {$ENDIF}` oder `{$IFDEF A} if B then
  {$ELSE} Foo; {$ENDIF}`), Abbruch - mit und ohne Block.
- Eingefuegte Zeilen enden wie die Zeile, vor die sie kommen (`begin` wie
  die Zweigzeile, Deklaration und `end;` wie die Anweisung); eine letzte
  Zeile ohne Zeilenende bekommt das erste Zeilenende der Datei, eine Datei
  ohne jedes CR LF.
- Zweig ohne begin (die Zeile darueber endet mit `then`/`do`/`else`): C1h
  setzt `begin..end` um Deklaration und Anweisung - nur, wenn die Zeile
  genau die EINE Anweisung des Zweigs ist: sie endet auf der Zeile mit
  `;`, ein weiteres `;` steht nur in einem Block, der auf der Zeile
  schliesst, jedes `else` gehoert zu einem `if` derselben Zeile, und es
  schliesst nichts von ausserhalb (`until`, `finally`, `end`). Endet die
  Zweigzeile oder die Anweisung in einem offenen `{`/`(*`-Kommentar,
  Abbruch (`begin` bzw. `end;` landete im Kommentar oder String). Gehoert
  das `then`/`else` zu einem Bedingungsausdruck (Delphi 13: `X := if C
  then A` auf der Zeile darueber, oder weiter oben mit den Armen auf
  eigenen Zeilen - `X := if C then` / `A` / `else`, auch `X :=` / `if C
  then` / ...), Abbruch: der Leser geht von der Zweigzeile aufwaerts bis
  zum `if` oder bis eine Zeile eine Anweisung beendet (`;`) bzw. einen
  Zweig oder Block oeffnet - dann ist das `if` eine Anweisung. Grenze:
  verteilt sich die Bedingung des Ausdrucks selbst ueber Zeilen (`X := if
  (A and` / `B) then` / `Foo(1)` / `else` / `Bar(42);`), endet der Gang an
  `B) then`, das `if` darueber wird nicht erreicht und der Arm wird wie
  bei einer if-Anweisung umschlossen - das Ergebnis uebersetzt nicht (kein
  stiller Fehler). In
  reDelphix soll der vorhandene
  Block-Planer (SCA101, WrapInBlock) einspringen. D1 lehnt Zweige ohne
  begin ganz ab, ebenso Zeilen mit `|` (Trennzeichen des Templates) und
  `]]>` (Ende des CDATA-Abschnitts).
- Nie vor einem case-Zweig, einer Sprungmarke oder einem on-Handler
  (`1: ...`, `Fertig: ...`, `on E: X do ...`, auch `on E do ...` und
  case-Zweige hinter `for ... do`) - dort ist eine Deklaration dazwischen
  ungueltig.
- Nie, wenn das Literal schon allein der Wert einer Deklaration ist
  (`var X := 42;` wie `const X = 42;`, auch typisiert).
- Nie, wo die Zahl Teil einer Deklaration ist: `const`-Zeilen (auch hinter
  einer Anweisung, `Foo; const C = 5;`), der Typ einer Inline-var (auch
  `for var I: 0..9` und `Foo; var A: array[0..9] of Byte;`), Deklarationen
  `Name = ...` (auch generisch und mit `type`), Routinen-Koepfe
  (Vorgabewerte, dispid, message, external index) - auch ihre
  Fortsetzungen auf der Folgezeile (`message WM_USER + 5;`, `dispid 5;`,
  `external 'x.dll' index 5;`, `stdcall; external ...`; dieselben Woerter
  mit `:=`, `.`, `(`, `[` dahinter sind Anweisungen), `property ...
  default`, Attribute `[...]`, `goto`/`label`, `exports`, `asm`-Zeilen und
  Zeilen in einem `asm`-Block.
- Nie in Zeilen, die etwas fortsetzen: beginnt der Code mit einem Wert
  (Zahl, Vorzeichen - etwa der else-Wert eines Bedingungsausdrucks von
  Delphi 13) oder endet er mit `,` ausserhalb von Klammern (case-Marken).
- Nie in einem mehrzeiligen String (Delphi 12, `'''` ... `'''`, auch mit
  fuenf oder mehr Quotes - geschlossen wird er nur von genau so vielen
  Quotes am Zeilenanfang wie der Oeffner hatte; hinter dem Schliesser kann
  auf derselben Zeile ein neuer beginnen, `''' + '''`) und nie in einem
  Kommentar ueber mehrere Zeilen. Kommentar- und String-Zustand laufen in
  einem Lauf: ein `'''` in einem Kommentarblock oeffnet nichts, ein `{`
  oder `(*` im Text eines Strings schliesst nichts auf.
- Nie im `initialization`-/`finalization`-Abschnitt (ob dort eine
  Inline-Deklaration gilt, ist nicht gemessen) und nie in einer Datei mit
  FPC-Weiche (`{$IFDEF FPC}`, `{$MODE ...}`): FPC 3.2 kennt keine
  Inline-Konstante.
- Schluesselwoerter am Zeilenanfang zaehlen auch hinter einem Kommentar
  oder einer Direktive (`{$IFDEF X}const ...`).
- Bewusst abgelehnt, obwohl gueltig (der Leser grenzt es nicht ab): eine
  anonyme Funktion mit Ergebnistyp (`function: Integer`) - ihr `:`
  ausserhalb von Klammern sieht aus wie eine Sprungmarke.
- Typ: eine Inline-Konstante hat den Typ des Literals selbst (E26) - was
  fuer das Literal galt (Faltung in 32 Bit, Ueberladungswahl, Cardinal-
  Rechnung), gilt fuer sie; Beleg Teil P6 der Kompilierprobe (Bau offen).
  Der Name `MagicNrNN` ist ueber den ganzen Puffer frei (auch jenseits
  von 99).
