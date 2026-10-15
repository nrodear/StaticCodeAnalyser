# reDelphix - Source Refactor fuer den Static Code Analyser

IDE-Package (Delphi 12, Win32), das an Funden des SCA-Plugins Aktionen
anbietet: `Format()` aus einer Verkettung bilden, parametrisierte
SQL-Vorlage, `uses`-Eintraege qualifizieren, die Quick-Fixes
`FreeAndNil(X)`, `Assigned()`, `(TObject)` entfernen, Assert-Meldung,
leeren Sichtbarkeitsabschnitt, leere Klammern und ueberfluessige Vergleiche
mit True/False bzw. nil entfernen, `if C then X := True else X := False`
durch `X := C` ersetzen, ueberfluessige `Exit;`/`Continue;` und
Selbstzuweisungen entfernen, auskommentierten Code und ungenutzte lokale
Variablen loeschen, Freigaben (Free, UnLock/Leave, FreeMem) in try/finally
setzen, `inherited` in Konstruktor und Destruktor ergaenzen, `Result`
initialisieren, Unterdruecken und Stelle zeigen. Es liest die Stellen ueber den Quellstellen-Dienst
`TSourcePlaces` der SCA-Engine und schreibt nur in den IDE-Editor - nie in
eine Datei und nie, ohne vorher jeden Bereich im Puffer mit dem Text zu
vergleichen, auf dem die Aktion beim Menueaufbau beschrieben wurde (siehe
"Welcher Text gilt").

Alle Quick-Fixes mit Menuetext (en/de/fr), Wirkung, Sperren und einem
Beispiel vorher/nachher: [QUICKFIXES.md](QUICKFIXES.md) - erzeugt aus dem
Quelltext und `data\quickfixes-doc.json` von `tools\gen-quickfix-doc.py`
(Repo-Wurzel).

Konzept: `Konzept_SourceRefactor_Quellstellen_2026-10-02.md`, Abschnitt 15
(in `reDelphix\`), Code-Aktionen (frueher "Editorhilfen"): `Konzept_Editorhilfen_2026-10-08.md`
(Repo-Wurzel) - beide lokal, gitignored.

## Aufbau

```
reDelphix.d12.dpk / .dproj        {$DESIGNONLY}, requires rtl, vcl, designide, SCA.Engine
source\uRdxRegister.pas           Register -> Anbieter an TFindingActions anmelden; finalization: abmelden
source\uRdxProvider.pas           je Fund die Aktionen bauen (Anker/fixMode aus dem Regelkatalog); Quell-Cache TRdxSourceCache
source\uRdxRecipeRunner.pas       Rezept-Laeufer auf TSourcePlaces: Fund -> Beschreibung -> Ersetzung; ohne ToolsAPI, testbar
source\uRdxFixTable.pas           Tabelle der einfachen Hilfen: je Fundart Planer, Hinweis, Kennzeichnung (E2), zweiter Eintrag, Menuetext (Charge R8); EIN Geruest fuer die Planer mit Plan-Record (TRdxFixFrame, generisch, Charge H5c); ohne ToolsAPI, nur Delphi
source\uRdxRecipes.pas            reine Textlogik: Literal-Codec, Format() nach der Kompilat-Regel, Query-Objekt eines SQL-Ziels, uses-Schreibweise, Rahmenwerk
source\uRdxScopeTable.pas         Kurzname -> qualifizierte Unit (Compiler-Reihenfolge der Scope-Liste); Index der Projekt-Units TRdxProjectUnits (Gegenprobe, Netzpfade ungelesen - uRdxPaths)
source\uRdxSimpleFixes.pas        Quick-Fixes SCA066/SCA072/SCA074/SCA075/SCA084/SCA085/SCA087/SCA126/SCA139 (reine Textlogik)
source\uRdxRtlTypes.pas           Klassen und Interfaces der Delphi-Quellen (E27): Beweis fuer SCA084/SCA126 bei Fremdtypen; Liste uRdxRtlTypes.inc erzeugt von tools\gen-rtl-types.py (Repo-Wurzel)
source\uRdxStructFixes.pas        Quick-Fixes SCA007 (uses-Eintrag), SCA168 (case-else), SCA101/SCA099 (begin..end), reine Textlogik
source\uRdxLineFixes.pas          Quick-Fixes an einer Zeile SCA082/SCA071/SCA088/SCA123, reine Textlogik
source\uRdxRaiseFixes.pas         Quick-Fixes an Ausnahmen und leeren Rumpfen SCA020/SCA120/SCA122, reine Textlogik
source\uRdxDeclFixes.pas          Quick-Fixes an Deklarationen SCA117/SCA197/SCA149, reine Textlogik
source\uRdxFlowFixes.pas          Quick-Fixes an ganzen Anweisungen SCA098/SCA080/SCA047 (Charge H2), reine Textlogik
source\uRdxRoutineFixes.pas       Quick-Fixes SCA164/SCA147 (ungenutzte Routine / private Methode loeschen, Charge H3b) und die Bausteine Routinengrenzen, Decl/Impl-Finder und (seit Charge H5) Klassenkopf - Textlogik bis auf den Include-Leser (IncludeChainReason): er liest Includes von der Platte - fuer SCA164/SCA147 die vor implementation ohne die im Kopf der Unit (IncludesUpTo), fuer SCA014 alle (AllIncludes; eine Durchsicht, IncludesWhere) -, nie auf einem Netzpfad (uRdxPaths.IsNetworkPath), `{$I \datei.inc}` auf dem Laufwerk der Unit (IncludeSearchPath); eine eigene Unit dafuer folgt mit der Schichtung (R6-12)
source\uRdxCleanupFixes.pas       Quick-Fixes "Aufraeumen" SCA070/SCA053 (Charge H3a) und der Baustein CutEdit (loeschen und aufraeumen), reine Textlogik
source\uRdxTryFixes.pas           Quick-Fixes try/finally SCA009/SCA001/SCA109/SCA153/SCA156 (Charge H4) und der Baustein B5 (Anweisung und Freigabe in try/finally), reine Textlogik
source\uRdxSqlTemplate.pas        SQL-Vorlage zu SCA003 (Rezept 5.2, Charge S1, Nacharbeit SQc): nur Werte werden Parameter (DDL - auch hinter ';' -, Namen, Join-Bedingung, unbekannte Anweisungsart lehnen ab), Konstanten mitgelesen, ihr Name bleibt, FireDAC-ExecSQL, ADO-Parameters, Kette Q.SQL.Add, Namen aus dem Operanden; Nachweise am Quelltext (Konstante mit Sichtbarkeit ueber Routinen/Klassen, FireDAC-/ADO-Objekt), reine Textlogik
source\uRdxResultFixes.pas        Quick-Fixes SCA096/SCA097 (inherited in Konstruktor/Destruktor) und SCA121/SCA196 (Result initialisieren, Charge H5) und die Bausteine erste/letzte Anweisung des Rumpfs, reine Textlogik
source\uRdxCompilerTraces.pas     Spuren alter Compiler je Sprachmittel (Default() ab Delphi 2009, Inline-Konstante ab 10.3; dazu die ProjectVersion der .dproj, Charge SQc) und Skript-Units, reine Textlogik (Charge Q14; bis dahin in uRdxResultFixes)
source\uRdxMagicFixes.pas         Quick-Fix SCA014 "Lokale Konstante einfuehren" (Charge Q14, E28): Ziel aus dem Fund, dann uRdxIntroPlan/uRdxIntroEdits ohne Sync-Edit-Sitzung; Platte: Lazarus-Projekt, alte Delphi-Projekte (.dof/.bdsproj/.bpr/.bpg, .dproj vor 10.3) und Includes neben der Unit, kein Netzpfad (Charge SQc; seit Charge B1-FD auch kein Include auf einem Netzpfad; `\\?\C:\..` ist seit Charge B2S-a lokal)
source\uRdxIntroPlan.pas          Code-Aktion "Lokale Variable einfuehren" (ohne Fund; seit Charge Q14 auch der Quick-Fix SCA014): Literal am Caret, Deklaration, Spalten, Ablehnungen (reine Textlogik)
source\uRdxIntroEdits.pas         dieselbe Aktion: Puffertext, Ziel am Caret, Ersetzungen des Writers, Ende des Sync-Blocks (reine Textlogik; IDE-Teil folgt)
source\uRdxSuppress.pas           Unterdrueck-Marker setzen und entfernen (reine Textlogik)
source\uRdxCodeMap.pas            Code-Sicht der Datei (Kommentare, Strings, mehrzeilige Strings) und Token-Leser
source\uRdxBufferMath.pas         Zeile/Spalte -> Byte im UTF-8-Puffer, Pruefung aller Ersetzungen, Spaltengrenze, Textwahl
source\uRdxPaths.pas              die EINE Netzpfad-Regel (Charge B2S-a): UNC, auch mit `/` und als `\\?\UNC\..`, und Netzlaufwerke (GetDriveType, selbst deklariert, mit Naht fuer Tests) - `\\?\C:\..` ist lokal; fuer Include-, Form- und Projektdateien und die Projekt-Units, ohne Winapi.Windows (FPC-Pruefstand)
source\uRdxEditor.pas             ToolsAPI: Puffer lesen, Bereich markieren, Bereiche ersetzen (ein Undo-Schritt), Projekt-Units
source\uRdxLog.pas                Protokoll %TEMP%\reDelphix.log + DebugView
source\uRdxText.pas               Sprache der Texte: _() in die reDelphix-Sprache (wie die SCA-Oberflaeche oder redelphix.ini [UI] Language), redelphix.ini samt Vorlage (Entscheid E29, siehe "Sprache und redelphix.ini"); ohne ToolsAPI
data\unitscopes.txt               die Scope-Tabelle (erzeugt), als RCDATA eingelinkt (data\unitscopes.rc)
data\quickfixes-doc.json          Titel, Wirkung, Sperren und Beispiele je Quick-Fix (von Hand gepflegt) - Quelle fuer QUICKFIXES.md
QUICKFIXES.md                     alle Quick-Fixes mit Menuetext en/de/fr, Kennzeichnung, Sperren, Beispiel - ERZEUGT von tools\gen-quickfix-doc.py (Repo-Wurzel)
tests\reDelphix.Test.dpr/.dproj   DUnitX-Testprojekt mit 53 Testunits und einer Hilfs-Unit (siehe "Pruefen"); Konfigurationen Debug/Release (TestInsight) und CI (Konsole, Exit-Code)
tools\gen_unitscopes.py           erzeugt data\unitscopes.txt aus der Delphi-Installation
tools\fpc-pruefstand\build.sh     baut Core-Units + Modul-Textlogik unter FPC 3.2.2 in einem eigenen Arbeitsverzeichnis je Lauf und fuehrt Tests aus (Sprache 'de', Stub uLocalization.pas liest die echten i18n\*.po); neben dem Skript nur Grabsteine der Kopien (siehe "Pruefen")
tools\fpc-pruefstand\selftest.sh  Selbsttest von build.sh (zwei Laeufe zugleich, FPC-Exit, Testzahl, Registrierung, Test ohne Assert, PRUEFSTAND_DIR, Grabsteine, TMPDIR mit Backslashes)
tools\probe\RdxCorpusProbe.dpr    Korpus-Probe: Rezept 5.1 ueber eine Liste von Fundstellen, CSV
tools\probe\sites_from_sarif.py   Fundstellen einer Regel aus einem SARIF-Lauf ziehen
```

## Voraussetzungen in der IDE

* **Plugin-Variante B**: `StaticCodeAnalyser.IDE.d12` (requires `SCA.Engine`,
  `SCA.SharedUI`) muss installiert sein, nicht der Monolith
  `StaticCodeAnalyser.Plugin.d12`. reDelphix linkt gegen `SCA.Engine.bpl`;
  neben dem Monolithen liesse sich die Engine nicht laden (doppelte Units).
* SCA-Stand mit Quellstellen-Dienst (AH2 `uSourcePlaces`) und Registry
  "Aktionen am Fund" (AH6 `uFindingActions`, mit `fakNavigate` und
  `fakSuppress`), `SCA.Engine.dcp` im Dcp-Verzeichnis der IDE.
* reDelphix ist gegen Version 1 des Quellstellen-Vertrags geschrieben.
  `uRdxRecipeRunner` prueft `SOURCE_PLACES_VERSION` beim Uebersetzen
  (`{$IF SOURCE_PLACES_VERSION <> 1}` mit `{$MESSAGE ERROR}`): hebt die
  Engine die Version, bricht der Bau von reDelphix ab, bis der Laeufer
  gegen den neuen Vertrag geprueft ist. Eine zur Laufzeit getauschte BPL
  erkennt die Konstante nicht - das leistet die Paketbindung.

## Bauen und installieren

Das Package ist Teil von `StaticCodeAnalyser.d12.groupproj` und liegt im
SCA-Repo unter `reDelphix\`. In der Gruppe steht es nach dem IDE-Plugin;
danach folgen TestProject, reDelphix.Test und RdxCorpusProbe. Es haengt von
`SCA.Engine` ab (das Package bindet `SCA.Engine.dcp`); die Gruppe traegt
das als Abhaengigkeit, ein einzelnes "Erzeugen" von `reDelphix_d12` baut
die Engine also vorher. DCUs landen wie bei den anderen Projekten in
`..\Output\reDelphix\`.

1. Die Gruppe bauen (Engine, SharedUI, IDE-Plugin, reDelphix, Tests) und
   das Plugin `StaticCodeAnalyser.IDE.d12` installieren.
2. `reDelphix.d12` im Project Manager **Installieren**.
   BRCC32 erzeugt `unitscopes.res` aus `data\unitscopes.rc`. Nach einer
   Aenderung an `data\unitscopes.txt` das Package bereinigen und neu
   erzeugen - die IDE bemerkt die geaenderte Tabelle nicht, und die alte
   Ressource bliebe eingelinkt.
3. Datei im Editor oeffnen und mit dem SCA-Plugin scannen. Die Aktionen
   stehen an drei Stellen:
   * Rechtsklick auf einen Fund im Dock-Grid oder im Editor-Kontextmenue:
     hinter dem Trenner alle Aktionen von reDelphix. Ein ausgegrauter
     Eintrag nennt den Grund in Klammern.
   * Die Gluehbirne im Editor (an der Caret-Zeile) zeigt nur die
     ausfuehrbaren Hilfen - ohne "Stelle zeigen", ohne ausgegraute
     Eintraege. Unterdruecken steht dort nur, wenn es zum Fund auch eine
     Hilfe gibt.
   * Ein `&` in einem Menuetext (aus einem Meldetext, Bezeichner oder
     Grund) erscheint woertlich, nicht als Tastenkuerzel: das Plugin
     verdoppelt es fuer das Menue.

## Was die Aktionen tun

Details je Hilfe (Menuetexte en/de/fr, Sperren, Beispiel vorher/nachher):
[QUICKFIXES.md](QUICKFIXES.md).

| Aktion | Regel | Verhalten |
|---|---|---|
| Stelle zeigen | alle mit beschreibbarer Anweisung (Anker der Regel) | markiert den exakten Bereich im Editor. Nur Kontextmenue und Dock-Grid (`fakNavigate`), nicht die Gluehbirne. Ausgegraut, wenn der Bereich hinter Spalte 32767 bzw. hinter 32766 Bytes seiner Zeile liegt (die Editor-Markierung rechnet in SmallInt); liegt er beim Klick hinter dem Pufferende, meldet die Aktion das und markiert nichts |
| Format() aus Verkettung bilden | SCA044 (`fixMode: auto`) | ersetzt die Terme durch `Format('...%s...', [..])` nach der Kompilat-Regel (unten). `IntToStr(n)` mit bekanntem Ganzzahltyp wird `%d`/`%u` mit `n`; `n.ToString` bleibt `%s`. Ein Char-Operand bekannten Typs geht als `string(c)` hinein, damit ein `#0` erhalten bleibt. `X := X + ...` wird `X := X + Format(...)`. Kein Literal im Formatstring traegt mehr als 255 Elemente (Charge FB, Review R2-02: bis Delphi 11 E2056 - die Literale der Kette sind einzeln kurz, zusammen nicht; Korpus-Harness ohne Resolver: 16 Angebote mit einem Lauf bis 1.832 Elementen, die Probe des Pruefers: 8 aktive Stellen): ein laengerer Lauf wird mit ` + ` geteilt, bevorzugt hinter einem Leerzeichen, der Wert bleibt (`uRdxRecipes.SplitLongLiteral`; gezaehlt wird vorsichtig nach UTF-8 - ein CJK-Zeichen drei, ein Surrogat-Paar vier -, denn ob Delphi bis 11 Zeichen oder UTF-8-Bytes zaehlt, ist nicht belegt; Nachpruefung FB). Gesperrt bei SQL-Literalen, einem Zeiger am Kettenanfang (Kompilat-Regel, unten - nicht hinter `X +` beim Selbst-Anhaengen, dort ist X der Anfang), Kommentar oder Direktive im ersetzten Bereich, Variant-Anzeichen, Zahl-Operanden, Nicht-Unicode-Strings. Fehlt `System.SysUtils` (dort lebt `Format`), wird es als zweite Ersetzung in die uses-Klausel eingefuegt (unten) - der Menuetext sagt `+ uses System.SysUtils` bzw. `+ uses SysUtils` |
| Parametrisierte Vorlage in die Zwischenablage | SCA003 (`fixMode: assisted`) | `uRdxSqlTemplate` (Charge S1, Nacharbeit SQc): ein Operand wird nur dort Parameter, wo SQL einen WERT erwartet - hinter `=`, `<>`, `<`, `>`, `LIKE`, `BETWEEN`/`AND`, als Element von `IN (..)`/`VALUES (..)`, hinter `LIMIT`/`OFFSET` nur `IntToStr(x)` (ein Text wird bei MySQL `'10'`; TOP/FIRST/SKIP nicht: dort nimmt SQL Server bzw. Access nur eine Zahl); ein Operand IN einem SQL-String macht den ganzen String zum Parameter (`LIKE ''%' + X + '%''` -> `LIKE :X`, Wert `'%' + X + '%'`; auch `N'..'`, ein `::typ` dahinter bleibt), `IntToStr(x)`/`QuotedStr(x)`/`AnsiQuotedStr(x, '''')` binden `x`; verdoppelt ein Operand IN einem SQL-String die Apostrophe (`StringReplace(x, '''', '''''', [rfReplaceAll])`, `ReplaceStr`/`ReplaceText`, `x.Replace(..)`, auch hinter einem Aufruf: `Trim(x).Replace(..)` bindet `Trim(x)`), ist der Wert `x`, sofern `x` nicht selbst maskiert (Charge FB, Review R2-06 und Nachpruefung). Ausgegraut mit Grund: jeder andere Aufruf mit `quote`/`escape` im Namen (`EscapeString`, `QuotedStr` im String, `AnsiQuotedStr(x, '"')`, auch ohne Klammern als Glied hinter einem Punkt: `x.QuotedString`, vorsichtig auch `Obj.QuoteChar`) und jedes andere Literal mit Apostroph im Operanden (`StringReplace` ohne `rfReplaceAll`, `x.Replace(..).Trim`, `Format('''%s''', [x])`) - der Parameter truege die Maskierung in die Daten; den Inhalt einer Variable und Konstanten als Argumente (`StringReplace(x, Q, QQ, ..)`) sieht die Vorlage nicht -, DDL/DCL (CREATE, ALTER, DROP, TRUNCATE, RENAME, COMMENT, GRANT, REVOKE) und prozedurale Bloecke (BEGIN, DECLARE, EXECUTE BLOCK) - fuer den REST des Texts, auch hinter `;` (Prozedur- und Triggerrumpf) -, Bezeichner-Positionen (FROM, INTO, UPDATE, ORDER BY, Spalten-/SELECT-Liste, Funktionsargument), ein nackter Operand in einer Join-Bedingung (`ON a.id = ' + X`), ein Operand, der an einem Bezeichner klebt oder in einem gequoteten Namen/Kommentar steht, ein Operand bzw. SQL-String allein in `IN (..)`/`VALUES (..)` (kann eine ganze Liste sein; `IntToStr`/`QuotedStr` sind EIN Wert), eine Anweisung, die nicht mit DML oder einer Klausel (WHERE, AND, ...) beginnt (`'ENGINE=' + X`, `PRAGMA`), ein `?` im Text, eine Kette ohne SQL-Literal (`FormatUtf8(..)`), "nur Konstanten". Ein SQL-Text ueber 255 Elemente wird in der Vorlage mit ` + ` geteilt (wie bei SCA044, Charge FB). Konstanten (am Quelltext nachgewiesen: untypisiert, sichtbar - Unit ab der Deklaration, aber nicht in einer Methode einer Klasse mit Vorfahr von ausserhalb (`class(TForm)`, Helper; dort bindet ein geerbtes Member wie `Name`/`Caption` vor der Konstante - Charge FB, Review R2-05), lokal bis zum Ende ihrer Routine, Klassenkonstante nur in den Methoden ihrer Klasse -, kein anderer Name gleich deklariert, auch keine Inline-Variable `var X := ..`/`for var X in ..`) werden mitgelesen, ihr NAME bleibt in der Vorlage (`'.. FROM ' + TBL + ' WHERE id = :Id'`); ebenso bleiben `sLineBreak` (beendet einen `--`-Kommentar) und bei `S := S + ..` der bisherige Text. Namen aus dem Operanden (`AColumnTypes` -> `:ColumnTypes`, `FId` -> `:Id`, `Edit1.Text` -> `:Edit1Text`, Kollision -> `2`, `3`, hoechstens 30 Zeichen; ein Oracle-/SQL-92-Wort bekommt ein `p` davor, z. B. `:pRows`; Umlaute -> `:p1`). Ziel Query-Objekt (`.SQL`, `.CommandText`): `ParamByName`-Zeilen - bei nachgewiesenem ADO-Objekt (`TADOQuery`/`TADOCommand`/`TADODataSet`/`TADOStoredProc`, `Data.Win.ADODB` in uses) `X.Parameters.ParamByName`; bei `Q.SQL.Add(..)` liest die Vorlage die frueheren `Q.SQL.Add`-Zeilen derselben Routine bis `Q.SQL.Clear`/`Q.SQL.Text :=` mit (Anweisungsart, DDL-Sperre; ihre und die spaeteren Platzhalter sind vergeben); String-Puffer: Zeilen `// Parameter binden: ParamByName(..).Value := ..;`; `X.ExecSQL(..)` nur mit FireDAC.Comp.Client in uses und X ueberall als TFDConnection deklariert: `X.ExecSQL('..:Id..', [Wert])`; jeder andere Aufruf bindet nichts - ausgegraut. Schreibt NIE in den Editor |
| uses: X -> Scope.X | Fund in einer uses-Klausel, auch der Programm-Klausel einer .dpr/.lpr | qualifiziert den Eintrag, dazu "uses: alle n Eintraege qualifizieren". Mehrdeutiges (Forms: VCL/FMX) nur bei erkennbarem Rahmenwerk, nie bei gleichnamiger Projekt-Unit und nie, wenn die Reihenfolge System/Vcl der Projekt-Scopes entscheiden wuerde. Gesperrt, wenn eine uses-Klausel Compiler-Direktiven traegt oder in einem `$IFDEF`-Zweig liegt, und in einer Datei mit FPC-Weiche oder FPC-Modus (FPC 3.2 kennt keine Unit-Scopes). Macht der Eintrag (bzw. "alle") eine sortierte Klausel unsortiert, steht er gesperrt da (sonst kaeme ein neuer SCA142-Fund). Ein Umbau, keine Hilfe zum Fund (`fakRefactor`): nur Kontextmenue und Dock-Grid, nie die Gluehbirne, und je Menue nur einmal, auch wenn mehrere Funde auf der Zeile stehen |
| FreeAndNil(X) verwenden | SCA085 | `X.Free;` + `X := nil;` -> `FreeAndNil(X);`. X muss in der Unit deklariert sein (keine Property, kein geerbtes Feld); gesperrt in einem `with`-Block. Seit Charge FB (Review R2-01/R3-01) dieselbe Typ-Sperre wie SCA139: kein `record`/`object`/`interface`, kein Zeiger (`PFoo = ^TFoo`) und kein eigener Typ (`PFoo = type ^TFoo`) dieser Unit, auch ueber ihre Aliasse (`TA = TB`; Nachpruefung FB), keine eigene Routine `Free` in der Unit (auch einer anderen Klasse - ohne Parser nicht unterscheidbar), kein Typ einer anderen Unit, der nach Konvention ein Zeiger ist (`P` + Grossbuchstabe/Ziffer/`_` in der Schreibweise des Quelltexts, keine Klasse der Delphi-Quellen: `PEVP_PKEY`, `PSSL_CTX` aus mORMot; auch hinter einem Alias der Unit, `PMyKey = PEVP_PKEY`) - FreeAndNil nimmt nur ein TObject (Delphi 12: E2010; FPC und Delphi bis 10.3: TObject.Free auf der Struktur). Korpus ab8: 10 von 1.103 Planer-Angeboten fallen weg (9 mORMot-OpenSSL-Zeiger, 1 Alcinoe `dwsUtils` - eigene `Free` einer anderen Klasse, dort unnoetig). Fremde Records/objects ohne Konventionsnamen bleiben unsichtbar (Delphi 12 meldet E2010), ebenso ein klein geschriebener Alias (`pmykey = pevp_pkey`). Ein Kommentar im Ausdruck (`X{owned}.Free;`, `X.{c}Free;`, `X.Free {c};` - der Detektor liest ohne Kommentare und meldet diese Formen) sperrt mit dem Grund `Kommentar im Ausdruck X.Free;` (bis Review R6-04 hiess er `X.Free; steht nicht mehr an der gemeldeten Stelle`). Fehlt `System.SysUtils`, kommt die uses-Einfuegung mit (unten) |
| Assigned() statt Vergleich mit nil verwenden | SCA126 | schreibt ALLE nil-Vergleiche der einen Anweisung um, die auf der Fundzeile beginnt (`X = nil` -> `not Assigned(X)`). Zwei solche Anweisungen auf der Zeile heissen mehrdeutig; ein Operand vom Typ String, Variant, Menge, Array oder Prozedur/Ereignis sperrt, ebenso ein blosser Bezeichner ohne beweisbaren Typ (geerbt aus einer anderen Unit). Bewiesen ist ein Typ, den die Unit als Klasse, Interface oder Zeiger deklariert (auch ueber Alias) oder der eine Klasse/ein Interface der Delphi-Quellen ist (Entscheid E27, `uRdxRtlTypes`: RTL, VCL, FMX, Data, Winapi ... aus Delphi 12 und 13, erzeugt von `tools\gen-rtl-types.py`; ein Typ in einer generischen Klasse zaehlt mit seinem eigenen Namen - `TList<Integer>.TEmptyFunc` ist nicht TList, Charge FC); ein Kundentyp aus einer anderen Unit sperrt - ein Funktionstyp dort riefe `= nil` auf, `Assigned()` nicht. Gesperrt in einem `with`-Block (ein Operand koennte ein Member des with-Ausdrucks sein) |
| (TObject) aus der Klassendeklaration entfernen | SCA075 | `class(TObject)` -> `class` an der Spalte aus der Meldung (nur Zeilen, ohne Parser) |
| FreeAndNil(X) verwenden | SCA139 | `X.Free` -> `FreeAndNil(X)`, auch hinter `then`/`else`/`do` (ersetzt wird nur der Ausdruck). Dieselbe Variablen-Pruefung wie SCA085; X muss ein blosser Bezeichner sein (kein `Self.X`, kein Pfad), `Free` ohne Klammern und genau einmal auf der Zeile. Gesperrt, wenn der Typ von X in der Unit ein `record`, `object`, `interface`, ein Zeiger (`PFoo = ^TFoo`, seit Charge FB) oder ein eigener Typ (`= type ..`) ist, auch ueber Aliasse der Unit (`Free` ist dort eine eigene Methode bzw. die des Ziels), die Unit eine Routine `Free` deklariert, der Typ nach Konvention ein fremder Zeiger ist (wie SCA085, auch hinter einem Alias der Unit), X ein `const`- bzw. `constref`-Parameter der Routine oder einer umschliessenden ist (Charge FB, Review R2-03: FPC meldet einen Fehler, Delphi bis 10.3 E2197, ab 10.4 wird nur die lokale Kopie nil - der Aufrufer behaelt den haengenden Zeiger; Korpus ab8: 15 von 363 Funden, 2 in FPC-Dateien von doublecmd; ein Attribut vor dem Kopf auf derselben Zeile zaehlt mit, eine anonyme Methode im Ausdruck sieht das nicht), und bei `X.Destroy`. Fehlt `System.SysUtils`, kommt die uses-Einfuegung mit |
| Bedingung als Assert-Meldung verwenden | SCA074 | `Assert(c)` -> `Assert(c, 'c')` an der Spalte aus der Meldung; Apostrophe der Bedingung werden verdoppelt. Nur, wenn die Klammer auf derselben Zeile schliesst und kein Kommentar darin steht; nicht bei `Obj.Assert`, nicht, wenn die Unit selbst eine Routine `Assert` deklariert, nicht im `with`-Block. Ein Literal ueber 255 Zeichen (E2056) sperrt |
| Unit X aus uses entfernen (aendert Verhalten) | SCA007 | loescht den Eintrag der Meldung aus seiner uses-Klausel: vor dem letzten Eintrag samt Komma bis zum naechsten - steht er allein auf seiner Zeile, die ganze Zeile samt `//`-Kommentar -, den letzten ab dem Komma davor, den einzigen mit der ganzen Klausel (ganze Zeilen, wenn sie allein steht); ein `in`-Pfad geht mit. Vorher wird der Fund am aktuellen Puffer nachgeprueft (dieselben Spuren wie der Detektor: `Unit.`-Bezug, bekannte Bezeichner) - ein Fund aus einem aelteren Scan bietet nichts an. Gesperrt bei einem Kommentar im geloeschten Bereich (auch `{Form1}` hinter einer Formular-Unit), bei Direktiven in einer uses-Klausel und wenn im Bereich mehr steht als dieser Eintrag. Gekennzeichnet nach Entscheid E2: der Fund ist heuristisch (danach kompilieren - ein Typ, den der Detektor nicht kennt, etwa `TDataModule`, macht ihn falsch), und ein `initialization`-Abschnitt der Unit laeuft danach nicht mehr. Strg+Alt+F fuehrt gekennzeichnete Hilfen nicht aus |
| Leeren else-Zweig ergaenzen / else-Zweig mit Exception ergaenzen (aendert Verhalten) | SCA168 | zwei Eintraege (Nico 2026-10-10): ein leeres `else` vor das `end` des case (bedeutungsgleich) bzw. `else raise EProgrammerError.Create('Unhandled case');` (+ `System.SysUtils` bei Bedarf). Das `end` findet eine Token-Bilanz (begin/case/try/asm/record; `&End` und `@@End` zaehlen nicht); steht es allein auf der Zeile, kommt das `else` in eine eigene Zeile mit derselben Einrueckung, die raise-Zeile eingerueckt wie die Arme. Endet der letzte Arm nicht auf `;`, setzt die Hilfe es mit - sonst bande das `else` an ein `if` im Arm (`1: if B then DoA`). Gesperrt bei einer Direktive zwischen `case` und `end`, wenn schon ein `else` oder (FPC) `otherwise` hinter `;` steht, bei einem case ohne Zweige, bei zwei `case` auf der Zeile, bei einem case, das keine Anweisung ist (Variantenteil eines Records - ein verschobener Fund; ohne umschliessenden Block, etwa in einem Fragment, ebenso), bei einer offenen `(` vor dem case mit einer Direktive dazwischen (ein Zweig kann sie offen lassen - die Lage ist unklar); die raise-Variante nicht in Dateien mit FPC-Weiche oder FPC-Modus (FPC kennt EProgrammerError nicht) |
| Ueberzaehliges Semikolon entfernen | SCA082 | `; ;` an der Spalte aus der Meldung -> `;` (das zweite war eine leere Anweisung). Nur, wenn dort beide `;` Code sind (kein String) |
| Schluesselwort an Spalte 1 setzen | SCA071 | loescht die Einrueckung vor dem Unit-Schluesselwort aus der Meldung. Nicht, wenn davor mehr als Leerraum steht (ein Kommentar ginge verloren), die Zeile in einem Kommentar bzw. mehrzeiligen String beginnt oder das `interface` zu einem Typ gehoert (`IFoo =` davor - das meldet der Detektor auch) |
| begin durch initialization ersetzen | SCA088 | das `begin` des Unit-Rumpfs (`begin .. end.`) wird `initialization`, Schreibweise wie das `begin`. Nur in einer Unit (in `program`/`library` ist es der Rumpf), nur wenn das `end` zu genau diesem `begin` (Token-Bilanz) vor dem Punkt steht, nicht bei einer Direktive auf der Zeile |
| Cast nach T vor Free entfernen | SCA123 | `TFoo(X).Free` -> `X.Free` - nur, wenn X ein blosser Bezeichner ist, ausserhalb eines `with`-Blocks, und schon als genau `TFoo` deklariert (`DeclaredTypeOf`): nur dann binden beide dasselbe `Free`. Ein anderer Typ kann `Free` verdecken (`TRefCountedObject.Free` in dwsUtils zaehlt nur herunter - aus `TRefCountedObject(Obj).Free` mit `Obj: TObject` wuerde eine Zerstoerung), ein Pointer-Operand braucht den Cast zum Uebersetzen (Gegen-Review 2026-10-10: von 58 sonst angebotenen Korpusfaellen uebersetzten 36 nicht). Das Katalog-Beispiel (`L: TObject`) bekommt deshalb keine Hilfe. Nur fuer Free, kein Interface-Cast |
| Leeren Rumpf als beabsichtigt kennzeichnen / ENotImplemented im leeren Rumpf ausloesen (aendert Verhalten) | SCA020 | zwei Eintraege wie bei SCA168: `// intentionally empty` in eine eigene Zeile zwischen `begin` und `end` (eine Stufe tiefer; stehen beide auf einer Zeile, `{ intentionally empty }` inline) - der Detektor wertet einen solchen Kommentar als Absicht, bedeutungsgleich - bzw. `raise ENotImplemented.Create('<Name>');` mit dem Namen aus dem Methodenkopf (+ `System.SysUtils` bei Bedarf; FPC kennt die Klasse ebenfalls). Gesperrt bei zwei Routinenkoepfen auf der Zeile (der Fund koennte jeden meinen), bei einer lokalen Routine zwischen Kopf und Rumpf, bei `asm`, wenn hinter dem `begin` noch Code steht, wenn der Rumpf nicht leer ist (Code unter einer inaktiven Direktive oder ein asm-Block - der Detektor sieht nur den aktiven Zweig; im Korpus 288 von 3.945 Funden) und bei einem Kommentar im Rumpf (er ist keine Absicht, sonst schwiege der Detektor - meist auskommentierter Code, den der Absichtskommentar fuer SCA070 verdeckte; 726 Funde); die raise-Variante nicht in constructor/destructor und nur mit dem Namen auf der Kopfzeile |
| Exception ausloesen (aendert Verhalten) | SCA120 | `raise ` vor `EFoo.Create(..)` (auch `CreateFmt`, Argumente ueber Zeilen) - nur als ganze Anweisung: davor ein Anweisungsanfang (im then-Zweig nur, wenn auch das `if` eine Anweisung beginnt - nicht im bedingten Ausdruck von Delphi 13), hinter der `)` ihr Ende (kein `X := EFoo.Create`, kein `EFoo.Create(..).Free`); nur die Create-Varianten des Detektors (`Create`, `CreateFmt`, `CreateRes`, `CreateHelp` ...). Gekennzeichnet nach E2: der Code dahinter laeuft im Fehlerfall nicht mehr - das ist der Fix |
| raise; verwenden (Original-Stack-Trace bleibt) | SCA122 | `raise E;` -> `raise;` - nur, wenn rueckwaerts der eigene Handler `on E: T do` kommt, bevor ein `except`/`finally` (im except eines inneren try wuerfe `raise;` die innere Exception), der Handler einer anderen Variablen, eine anonyme Methode oder ein `with` (der Name koennte ein Member sein); ganze Bloecke davor zaehlen nicht. Gesperrt auch, wenn E dazwischen neu zugewiesen wird (`E := EWrapped.Create(..)`: `raise E` wirft dann das neue Objekt, `raise;` die urspruengliche Exception); eine Uebergabe als var-Argument sieht die Hilfe nicht (Grenze) |
| Dokumentationsgeruest einfuegen | SCA117 | setzt ueber die Deklaration `/// <summary></summary>`, je Typparameter `/// <typeparam name="T"></typeparam>`, je Parameter (bei einer Property: je Index-Parameter) `/// <param name="X"></param>` und bei einer Funktion `/// <returns></returns>` - eingerueckt wie die Deklaration, die Platzhalter leer (ein `TODO` riefe SCA019). Die Namen kommen aus dem Kopf, auch ueber Zeilen; `const`/`var`/`out`/`constref` und Attribute zaehlen nicht mit. Bedeutungsgleich. Gesperrt, wenn die Zeile in einem Kommentar beginnt, der Name nicht mehr zur Meldung passt, darueber ein Kommentar ueber Zeilen endet (der Detektor haelt dessen Schlusszeile fuer Code), ueber Attributzeilen schon XMLDoc (`///`) steht (der Detektor bricht an der Attributzeile ab und meldet trotz Doku - delphimvcframework; sonst entstuende ein zweiter summary-Block; andere Kommentare dort sind meist Abschnittsueberschriften, dann kommt das Geruest) oder eine Direktive im Kopf bis zu dessen `;` steht (dahinter zaehlt nicht). Ohne Attribut-Doku kommt das Geruest unter die Attribute, direkt ueber die Deklaration (dort sucht der Detektor) |
| Neue GUID einfuegen | SCA197 | eine frisch erzeugte GUID `['{...}']` in eine eigene Zeile hinter den Interface-Kopf (eingerueckt wie die Member; steht der Rumpf auf derselben Zeile, inline). Bedeutungsgleich. Gesperrt bei generischen Interfaces (eine GUID gaelte fuer alle Auspraegungen), Vorwaertsdeklarationen, `[` hinter dem Kopf (GUID oder Attribut), COM-Merkmalen im Rumpf (`stdcall`/`safecall`/`winapi`/`dispid` - ein COM-Import braucht die echte IID), `{$INTERFACES CORBA}` bzw. `{$CALLING STDCALL}` in der Datei (auch als `(*$..*)`, nur innerhalb der Direktive), wenn hinter dem Kopf kein Rumpf beginnt (`procedure`/`function`/`property`/`end`) und bei einer Direktive vom Kopf bis zum ersten Member - beides fangt Koepfe, die unter `{$IFDEF}` doppelt stehen (die GUID kaeme sonst nur in einen Zweig) |
| "override;" bzw. "reintroduce;" an die Deklaration anfuegen | SCA149 | nach dem Rat der Meldung: bei gleicher Signatur `override` (gekennzeichnet nach E2 - der virtuelle Aufruf landet danach in dieser Methode; das ist der Fix), bei abweichender `reintroduce` (bedeutungsgleich, nur W1010 entfaellt). Nie beide als Eintraege: Strg+Alt+F liesse das gekennzeichnete `override` aus und deckte den Polymorphie-Fehler mit `reintroduce` still zu. `reintroduce` kommt direkt hinter das `;` des Kopfs (vor vorhandene Direktiven), `override` hinter ein vorhandenes `overload` (sonst ebenfalls direkt hinter den Kopf) - die Reihenfolge der Sprachreferenz (reintroduce; overload; virtual/override; ...). `override` nur, wenn im Rumpf der Elternklasse (der Detektor sucht sie in derselben Unit) eine Methode gleichen Namens dieselbe Form hat: `class`, Parameter-Modifier, Typen und Defaults (Namen duerfen abweichen), Rueckgabe, Aufrufkonvention - der Detektor vergleicht nur die Typen, `const A` gegen `A` oder `class procedure` gegen `procedure` uebersetzten mit `override` nicht. `reintroduce` nicht bei generischem Vorfahren (`class(TBase<Integer>)`: der Detektor haelt `T` und `Integer` fuer verschieden, `override` waere dort der Fix; Typ-Aliase wie `Integer`/`Longint` erkennt er ebenso nicht - Restrisiko). Gesperrt ausserdem, wenn `override`/`reintroduce` schon dasteht, bei `override` neben `virtual`/`dynamic`/`static`/`message`/`inline`, wenn der Name nicht mehr passt, bei einer Property, bei einer Direktive im Kopf und bei unbekanntem Meldungstext |
| Zweig in begin..end setzen | SCA101, SCA099 | setzt die Anweisung hinter `then`/`else`/`do` in `begin..end` (Entscheid E7, bedeutungsgleich). SCA101: das Schluesselwort an der Spalte aus der Meldung; SCA099: das `else` hinter dem einen `end else` der Fundzeile, das der Detektor meldet (`end else if`/`end else begin` zaehlen nicht mit). Die Anweisung endet mit `;` (das `end` bekommt dann eines) oder vor `else`/`end`/`until`/`except`/`finally` (sie bekommt ein `;`, das `end` keines). Hinter dem `else` eines `case` oder `except` steht eine Anweisungsliste - dann kommt alles bis vor dessen `end` in den Block, nicht nur die erste Anweisung. Wem ein `else` gehoert, entscheidet eine Rueckwaerts-Suche wie der Compiler (dangling else: das naechste `then` ohne eigenes `else`; Bloecke und `repeat..until` werden uebersprungen); ein `;` auf oberster Ebene schliesst ein if-else aus, entscheidend ist erst das `of` bzw. `except` davor. Form: endet die Zeile des Schluesselworts mit ihm und die letzte Zeile der Anweisung mit ihr, kommen `begin` und `end` in eigene Zeilen (eingerueckt wie die Zeile des `if`/`for`/`while`/`with`/`on` bzw. des `else`; Kommentarzeilen dazwischen kommen mit in den Block); steht die Anweisung ganz auf der Zeile des Schluesselworts, kommt sie eine Stufe tiefer in eine eigene Zeile (ein folgendes `else` in die naechste); sonst inline (`begin X; end`). Gesperrt bei einem bedingten Ausdruck (Delphi 13: `X := if A then B else C`, auch verschachtelt oder als `Write`-Breite hinter `:`), wenn hinter einem `;` vor dem `else` eine Deklaration steht (`var`, `procedure` ... - der Kopf einer anonymen Methode; wem das `else` gehoert, waere unklar), bei `record` vor dem `else`, wenn in der Anweisung eine Struktur, eine anonyme Methode oder eine Inline-Deklaration steht (`var`/`const` auch in der Liste eines case-else: `begin..end` engte ihren Gueltigkeitsbereich ein), bei einer Direktive in den Zeilen vom entscheidenden Token (beim `else` das `then` bzw. `of`/`except`, sonst das Schluesselwort) bis zum Ende der Anweisung (`{$` in einem `//`-Kommentar zaehlt nicht), bei schon vorhandenem `begin` und bei leerer Anweisung |
| Leere Klammern entfernen | SCA066 | `Foo()` -> `Foo` an der Spalte aus der Meldung, auch in Deklarationen (`procedure Foo();`). Nur, wo Delphi den Namen ohne Klammern genauso aufruft: als ganze Anweisung (`Obj.Foo();`), als ganze Bedingung von `if`/`while`/`until` oder als ganze rechte Seite einer Zuweisung an eine einfache Variable, deren Typ bekannt und nicht prozedural ist (sonst liest Delphi den Namen als Zeiger). Gesperrt als Argument oder Teil eines Ausdrucks (etwa bei einer Ueberladung mit `TFunc`), bei `Arr[0]()` und `F()()`, wenn der Name eine Variable (Prozedurvariable) ist, wie ein Ereignis heisst (`OnIdle()`) oder die Unit ihn als Property deklariert (auch hinter einem Pfad: `Dlg.RefProc()` - ob Delphi eine Property mit Prozedurtyp ohne () aufruft, ist ohne Delphi-12-Probe nicht belegt; Grenze: eine Property einer anderen Unit mit unauffaelligem Namen sieht die Sperre nicht), in der eigenen Funktion, im `with`-Block und in Dateien mit FPC-Weiche oder FPC-Modus. Nachfolger des alten Strg+Alt+F (uQuickFix) |
| Ueberfluessigen Vergleich mit True/False entfernen | SCA072 | `X = True` / `X <> False` -> `X`, `X = False` / `X <> True` -> `not X`. Nur fuer einen blossen Bezeichner (kein Pfad, auch nicht `Self.X`), der in der Unit als `Boolean` deklariert ist (bei Variant und LongBool ist `= True` nicht dasselbe); links davon muss ein Ausdruck beginnen und rechts von True/False einer enden - `X = True and Y` heisst `X = (True and Y)`. Gesperrt im `with`-Block. Nachfolger von uQuickFix, der auch Pfade ohne Typpruefung umschrieb |
| Ueberfluessigen Vergleich mit nil entfernen | SCA084 | `Assigned(X) and (X <> nil)` bzw. `(X <> nil) and Assigned(X)` -> `Assigned(X)`, alles auf einer Zeile und der Vergleich geklammert. X muss als Klasse, Interface oder Zeiger bewiesen sein (`TObject`, `Pointer`, `IInterface`, in der Unit so deklariert, auch ueber Alias, oder eine Klasse/ein Interface der Delphi-Quellen - E27, `uRdxRtlTypes`, derselbe Beweis wie bei SCA126) - bei einem Funktionstyp ruft `X <> nil` ihn auf, `Assigned(X)` nicht. Gesperrt bei `not` davor (es bindet nur an den ersten Teil), bei einer Aufruf- oder Cast-Klammer (`Boolean(X <> nil) and ...`), bei einer eigenen Routine `Assigned` und im `with`-Block. Nachfolger von uQuickFix |
| Bedingung direkt an X zuweisen | SCA098 | `if C then X := True else X := False` -> `X := C`, Gegenrichtung (`then False else True`) -> `X := not C`. Klammern nur um ein zusammengesetztes C (`not (A > B)`; `not Ready` und schon geklammertes `not (A and B)` ohne weitere), Zeilenumbrueche in C bleiben, Ziel und Zuweisung wie im then-Zweig (`Result:=`). Bedeutungsgleich. Gegenprobe wie der Detektor: Ziel und beide Werte wie in der Meldung, kein `;` vor dem `else`, hinter dem zweiten Wert endet die Anweisung. X muss als `Boolean` deklariert sein (DeclaredTypeOf; bei Variant bekaeme X den Wert der Bedingung statt True/False). In der Gegenrichtung auch C: der Form nach Boolean - ein Vergleich auf oberster Ebene oder `and`/`or`/`xor`/`not` ueber solchen Teilen, `True`/`False` und blossen Bezeichnern - und jeder dieser Bezeichner als `Boolean` deklariert; bei einem Variant waere `not` bitweise (`not 1` ist wieder wahr), ein Aufruf als C bleibt in der Gegenrichtung deshalb aus. Gesperrt bei einem Kommentar oder einer Direktive in der Anweisung, `begin..end`-Zweigen, einem Ausdruck hinter dem zweiten Wert (`X := False or Y`), einem bedingten Ausdruck (Delphi 13), im `with`-Block und bei zwei solchen Anweisungen auf der Zeile (die Meldung nennt keine Spalte). Folgefund: stand das if hinter `end else`, meldet SCA099 danach `end else X := C` (Korpus 2 von 220) |
| Ueberfluessiges Exit/Continue entfernen | SCA080 | loescht `Exit;` bzw. `Continue;` - allein auf der Zeile die ganze Zeile; hinter dem `else` eines `if` faellt `else Exit` weg (`if C then Foo else Exit;` -> `if C then Foo;`). Bedeutungsgleich. Gegenprobe wie uRedundantJump: dahinter nur die end-Kette bis zum Routinenende, `end.` oder `until`; Exit nicht im Rumpf einer Schleife. Gesperrt als einzige Anweisung hinter `then`/`do` (`if C then Exit;` - es bliebe `if C then` stehen, und C kann Seiteneffekte haben), eines case-Zweigs, des `else` von case/except und eines Blocks (`begin Exit; end`, `except Exit; end` - es bliebe ein leerer Block), bei mehreren Sprunganweisungen auf der Zeile, bei einem Kommentar auf der Zeile (er erklaert den Sprung) und bei einer eigenen Routine `Exit`/`Continue` in der Unit (`Exit;` riefe sie auf; eine geerbte Methode dieses Namens aus einer anderen Unit sieht die Hilfe nicht - Restrisiko). Im `finally`-Teil gesperrt, obwohl dort kein Sprung uebersetzt (Delphi 12 E2126, FPC 3.2.2 Fehler 06040 - Mikroprobe 2026-10-12): Code unter einer inaktiven Direktive sieht kein Compiler. Folgefunde: ohne das Exit melden SCA121 bzw. SCA132 vereinzelt, was das Exit vorher verdeckte (Korpus je 1) |
| Selbstzuweisung von X entfernen | SCA047 | loescht `X := X;` - allein auf der Zeile die ganze Zeile -, auch Pfade (`Pt.Y := Pt.Y;`, `R^.F := R^.F;`). Bedeutungsgleich; war ein anderer Wert gemeint (Tippfehler, Katalog: `FCount := ACount`), fehlt er weiterhin - der Hinweis sagt es. Gegenprobe: links und rechts derselbe Pfad wie in der Meldung (ohne Leerraum, Gross/klein egal), dahinter endet die Anweisung. Die Wurzel muss eine Variable sein (DeclaredTypeOf oder Inline-Variable), kein Pfadteil eine Property der Unit (ihr Setter liefe sonst nicht mehr). Gesperrt fuer `Result := Result` (stillt vielleicht W1035 bzw. den FPC-Hinweis "Function result does not seem to be set" - der Katalog empfiehlt dort das Unterdruecken), wenn X auch eine Routine der Unit ist (rechts koennte ein rekursiver Aufruf stehen), bei einem `class operator Assign` in der Unit (verwaltete Records: die Zuweisung fuehrt Code aus; ein Record aus einer anderen Unit mit Assign-Operator ist nicht erkennbar - Restrisiko), bei einem Kommentar auf der Zeile (`Pt.Y := Pt.Y; // + Scroll` traegt die Absicht), als einzige Anweisung hinter `then`/`else`/`do`, eines case-Zweigs oder eines Blocks, ueber mehrere Zeilen und im `with`-Block |
| Ungenutzte Routine X loeschen | SCA164 | loescht die freie Routine des implementation-Teils vom Kopf bis zu ihrem `end;` - samt lokaler Abschnitte und Routinen (Baustein Routinengrenzen: Variantenrecord, Prozedurtypen, Direktiven auf Folgezeilen, `asm` mit `@@end`), der `///`-Doku- und Attributzeilen darueber und der Kommentarzeilen direkt darueber, wenn sie die Routine beim Namen nennen und keinen Marker tragen (`// Name: X()`, `{ X }` gehen mit; ein Abschnittsmarker `{ Helpers }`, eine Ueberschrift wie `(* === run-time registration functions === *)`, `// noinspection-file` und TODO/FIXME/HACK/XXX bleiben stehen, ebenso jeder Kommentar ohne den Namen - eine Ueberschrift ist von einer Beschreibung nicht sicher zu unterscheiden; Korpus: bei 101 von 897 Angeboten bleibt der Kommentar seit Charge H3c stehen), EINER Leerzeile (dahinter, sonst davor) und einer `forward`-Deklaration; ein Einzeiler `procedure X; begin end;` als ganze Zeile. Bedeutungsgleich. Den Beweis fuehrt die Hilfe neu am Puffer: der Name steht ausserhalb der Routine nirgends als Code - auch nicht in einem inaktiven `$IFDEF`-Zweig (Korpus: mORMot `ExchgLen`, der Detektor meldete trotz Aufruf), als `@X`, in `exports` oder im interface-Teil -, in keinem String-Literal (`GetProcAddress`, RTTI, Skript-Registrierung) und in keiner Direktive (`{$EXTERNALSYM X}`). Ein Aufruf in anderer Gross/klein-Schreibung mit Umlaut zaehlt als Verwendung. Gesperrt bei Overloads, Methoden (das meldet SCA147), globalen FPC-Operatoren, `export`/`public`/`alias`/`external`/`forward`/`interrupt` (auch in FPC-Klammern `procedure X; [public, alias: 'X_C'];`), `{$L}`/`{$LINK}` in der Datei (der C-Code ruft per Name), `{$I}` im implementation-Teil (dort kann ein Aufrufer stehen), einem `{$I}` davor, das die Routine nennt oder neben der Unit nicht zu finden ist (verschachtelte Includes ebenso; es kann sie im interface-Teil deklarieren - nach dem Loeschen E2065; Includes im Kopf der Unit vor `interface` bzw. `uses` liest die Hilfe nicht, dort stehen nur Direktiven - `jcl.inc`, `CnWizards.inc`; Korpus: 5 von 897 Angeboten fallen weg; `{$I \datei.inc}` sucht die Hilfe seit der Nachpruefung B1-FD ab der Wurzel des Laufwerks der Unit - vorher auf dem aktuellen Laufwerk der IDE - und wie bisher neben der Unit) oder das bzw. dessen Unit auf einem Netzpfad liegt (UNC oder Netzlaufwerk: die Hilfe liest dort nichts, der Menueaufbau laeuft im Hauptthread - bis Charge B1-FD wartete er 9 bis 16 s je Include auf einen nicht erreichbaren Server; `\\?\C:\..` gilt als lokal - seit Charge B2S-a auch beim Lesen der Includes, bis dahin lehnte die Hilfe dort ab -, `\\?\UNC\..` als Netzpfad), einer Direktive im Bereich ausser ausgeglichenem `$IF..`/`$ENDIF` bzw. `$REGION` (`{$DEFINE}`, `{$R-}` wirkten weiter), einem Marker-Kommentar, der ausserhalb wirkt (Charge B1-FD: `end; // noinspection X` auf der letzten Zeile gilt der Zeile dahinter, ebenso hinter einer `forward`-Deklaration; ein Absichtskommentar TODO/FIXME/HACK/XXX dort bleibt wie ueber dem Kopf stehen; `// noinspection-file` im Bereich gilt der ganzen Datei; Korpus: kein Angebot betroffen) oder von aussen in den Bereich zielt (Nachpruefung B1-FD: ein `// noinspection X` ueber dem Kopf bzw. der `forward`-Deklaration - auf eigener Zeile, hinter Leerzeilen oder hinter dem `end;` davor - gilt der Routine; der Kommentar-Lauf bleibt stehen, und geloescht galt er still der Routine dahinter; Korpus: kein `noinspection`), zwei Routinen auf einer Zeile, einem Kopf vor `implementation` (Programme meldet der Detektor nicht) und unsicheren Grenzen (lokaler Klassentyp, Kopf im Rumpf, `$IFDEF`-geteilter Rumpf) |
| Ungenutzte private Methode X loeschen | SCA147 | loescht die Deklaration im Klassenrumpf (samt `///`-Doku; ein Gruppenkommentar wie `{ Private declarations }` bleibt) und die Implementierung wie bei SCA164 (Baustein Decl/Impl-Finder: verschachtelte Klassen `TOuter.TInner.X`, generische `TFoo<T>.X`, `class procedure`). Bedeutungsgleich. Nur unter `private`/`strict private`; der Name steht nur in Deklaration und Implementierung (rekursive Aufrufe im eigenen Rumpf zaehlen nicht). Gesperrt bei `virtual`/`dynamic`/`override`/`abstract`/`reintroduce`/`message`/`overload`/`dispid`, Konstruktor, Destruktor und Operator, mehr als einer Deklaration oder Implementierung, keiner Implementierung in der Datei (Include, abstract), Property-Accessor, Name als String-Literal (`MethodAddress`), `{$RTTI}` in der Datei, Attribut an Methode oder Klasse, `{$I}` im Klassenrumpf (dort kann `property P read X` stehen) oder im implementation-Teil, einem `{$I}` davor, das den Namen nennt, neben der Unit fehlt oder auf einem Netzpfad liegt (seit Charge B1-FD wie bei SCA164, `\\?\C:\..` seit Charge B2S-a lokal - im interface-Teil kann es eine Nachfahrenklasse mit `property X read GetX` tragen, private ist in der ganzen Unit sichtbar; nach dem Loeschen E2003 im Include; Includes im Kopf der Unit liest die Hilfe nicht; Korpus: kein Angebot betroffen), einem Marker-Kommentar hinter der Deklaration oder dem `end;` der Implementierung (er gilt der Zeile dahinter) bzw. einem `// noinspection` darueber (er zielt auf sie, Nachpruefung B1-FD) wie bei SCA164, einem Interface der Klasse aus einer anderen Unit (die Methode kann sein Member sein; wie Gate E des Detektors auch `class(IFremd)` mit dem Interface als erstem Eintrag und der fremde Vorfahr eines lokalen Interfaces), einem Member von `IInterface`/`IDispatch` als Name (`_AddRef`) und einer `.dfm`/`.fmx`/`.lfm` neben der Unit, die den Namen nennt (der Detektor liest nur `.dfm`); auf einem Netzpfad bzw. Netzlaufwerk liest die Hilfe keine Formdatei und lehnt ab (Charge FB, Review R2-07: dreimal FileExists im Hauptthread je Menueaufbau, auf einer nicht erreichbaren Freigabe Sekunden; `\\?\C:\..` gilt als lokal, `\\?\UNC\..` als Netzpfad). Der leere private-Abschnitt, der bleiben kann, meldet danach SCA087 (eigene Hilfe) |
| Auskommentierten Code loeschen | SCA070 | loescht die Region der Meldung ab Zeile und Spalte (`Comment at column C` bzw. `block of N lines starting at column C`): eine `//`-Zeile ganz, einen Kommentar hinter Code ab seiner Spalte (kein Leerraum am Zeilenende), die Inhaltszeilen eines mehrzeiligen `{ }`/`(* *)` (41 % der Korpusfunde zeigen auf eine Inhaltszeile). Bedeutungsgleich. Nur, was der Fund abdeckt: der Detektor bewertet jede Zeile einzeln und fasst gemeldete Zeilen zu einer Region zusammen, solange dazwischen nur reine Kommentarzeilen stehen - Prosa vor oder hinter der Region bleibt im Kommentar, ein langer Block mit Leerzeilen ergibt mehrere Funde. Die Begrenzer gehen erst mit, wenn der Kommentar danach nur noch Leerraum traegt (der letzte Fund raeumt auf); traegt er davor bzw. dahinter Text, bleibt der Oeffner bzw. Schliesser. Gegenprobe: ab der Spalte bis zum Ende der letzten Zeile nur Kommentar und Leerraum (Code-Sicht, ueber Zeilen; ein Delphi-12-Mehrzeilenstring ist kein Kommentar - der Detektor kennt ihn nicht), die Spalte am Anfang eines Kommentars bzw. einer Inhaltszeile, erste und letzte Zeile mit Code-Merkmal wie im Detektor (`;` am Ende, `:=`, begin, procedure/function). Gesperrt bei einer Direktive im Bereich, einem Doku-Kommentar (`///`, `{*`, `(**`), einem Kommentar vor dem ersten Code der Datei (Lizenz-/Kopfkommentar), `noinspection` oder TODO/FIXME/HACK/XXX im geloeschten Text (Absichtskommentare wie bei SCA019) und wenn mehrere Kommentare in der Region stehen und einer mit Text ueber sie hinausreicht (der Schnitt waere nicht zusammenhaengend). Zwischen zwei Token bleibt ein Leerzeichen, wo sie sonst verschmoelzen (`begin{x}end` -> `begin end`). Grenze (Nachpruefung B1-FD, nicht gesperrt): ein `// noinspection` direkt ueber der Region zielt danach auf die naechste nicht leere Zeile - meist die Code-Zeile, die er ohnehin traf; nur wenn dort wieder ein `//`-Kommentar steht oder die Region aus Zeilen eines `{ }` bestand, wandert er. Folgefunde (Korpus-Rundlauf): SCA117, wo der Kommentar ueber einer public-Deklaration stand und ihr als Doku galt (54 von 6.696), SCA020, wo er der einzige Inhalt eines Rumpfs war (2), SCA021 DuplicateBlock (Bloecke werden gleich bzw. ungleich) und SCA070 selbst, wo ein Adapter-Doku-Kopf `{ procedure X; }` seine auskommentierte Routine verliert (3) |
| Ungenutzte Variable X entfernen | SCA053 | loescht die Deklaration: `X: T;` samt Zeile (ein `//`-Kommentar dahinter geht mit - ausser er traegt einen Marker, `noinspection` oder TODO/FIXME/HACK/XXX: ein `// noinspection` hinter Code gilt der Zeile dahinter, ein Absichtskommentar bleibt wie bei SCA070; dann bleibt er als eigene Zeile an der Einrueckung stehen, Charge B1-FD), `A, X, B: T;` -> `A, B: T;` (erstes, mittleres, letztes Element, auch ueber Zeilen), `var` mit, wenn die Section dadurch leer wird, inline `var X: T;` als ganze Anweisung. Bedeutungsgleich. Gegenprobe auf dem Rohtext: der Name kommt vom Routinenkopf vor der Section (inline: vom `var`) bis zum Ende des Rumpfs bzw. Blocks (in `repeat..until` bis zum Ende der until-Bedingung) sonst nirgends als Code vor - lokale Routinen, Code unter einer inaktiven Direktive und `asm` zaehlen mit, ein Name hinter `.` ist ein Member. Gesperrt bei `for var` (der Detektor meldet die Laufvariable, Korpus 75 von 757), einem Schluesselwort als Name (`resourcestring`: der Parser liest die Section als Variable, 17 Funde), einer const-/resourcestring-Section, einem Initialisierer (`= 5`, `:= F()`), `absolute`, einem Typ ueber mehrere Zeilen (`record`), einem Attribut, einer Aufrufkonvention hinter dem Typ, einem Kommentar in der Deklaration, einem `// noinspection` darueber, der auf ihre Zeile zielt (auf eigener Zeile oder hinter dem Code darueber - geloescht gaelte er der Zeile dahinter, Nachpruefung B1-FD; bleibt die Zeile, wie bei `A, X: T;`, sperrt er nicht; Korpus: kein `noinspection`), einer Direktive in der Deklaration bzw. ihrer var-Section (ein Zweig koennte leer werden), einem `class operator Initialize/Finalize` in der Unit (verwalteter Record: die Variable fuehrt Code aus; ein solcher Typ aus einer anderen Unit ist nicht erkennbar - Restrisiko), als einzige Anweisung eines Blocks, ausserhalb einer Routine, in einer offenen Klammer (`F: function(` bzw. `procedure Inner(` und auf der Folgezeile `var X: T;` - ein Parameter, keine Variable), bei einem `{$I}`-Include im Gueltigkeitsbereich (die Hilfe sieht es nicht; mit einer globalen Variablen gleichen Namens bindet es danach still an sie), einer Direktive, die den Namen nennt, `asm` im Gueltigkeitsbereich (`[ebp-4]` spricht die Variable ohne Namen an) und einem FPC-Makro `{$DEFINE M := X}` in der Datei (Charge H3c; Korpus: keines der 629 Angebote betroffen). Das Ende des Gueltigkeitsbereichs liest seit Charge H3c der Baustein Routinengrenzen (`ReadRoutine`): ein `end` als Bezeichner (`Range(start := 0, End := 0)`, benanntes OLE-Argument) beendete ihn vorher still mitten im Rumpf, eine Verwendung dahinter blieb ungesehen - jetzt keine Hilfe (Korpus: 4 Angebote in einer Formatierer-Testdatei). Das galt bis Charge B1-FD nur fuer var-Sections: bei einer Inline-Deklaration endete der Block weiter am `End` des Arguments, und die Hilfe loeschte eine benutzte Variable - mit einem Feld oder einer globalen Variablen gleichen Namens band die Verwendung danach still an sie (Code-Review R4-01). Seitdem zaehlt im Block ein Schluesselwort mit `:=` dahinter nicht (`IsKeywordAt`, vorwaerts bis zum Blockende wie rueckwaerts bei der Frage, ob die Deklaration inline steht); Korpus: kein Angebot betroffen. Ein `with` im Gueltigkeitsbereich sperrt nicht - kommt der Name nirgends vor, kann es ihn nicht binden. Im Korpus-Rundlauf verschwand jeder der 629 Funde (528 im Lauf der Charge H3a, die 101 nach dem Wegfall der with-Sperre im Gegen-Review H3), ohne dass ein anderer derselben Regel kam. Folgefunde anderer Regeln: SCA021 DuplicateBlock (28 Bloecke werden ungleich), SCA001 (die Zaehlung verschiebt sich: 15 Funde weniger, 13 mehr), SCA009 (6 weniger) und SCA007 (1 mehr - die geloeschte `TList<Integer>`-Variable war der letzte Nutzer von `System.Generics.Collections`) |
| X in einem try/finally-Block freigeben (aendert Verhalten) | SCA009, SCA001 (nur Variante freed-outside-finally) | Baustein B5 (Charge H4): die Erzeugung `X := TFoo.Create..;` (auch `var X[: T] := ..`, CreateFmt & Co., ueber Zeilen) bleibt stehen, die Zeilen bis zur Freigabe `X.Free`/`X.Destroy`/`FreeAndNil(X)` (auch `SysUtils.FreeAndNil(X)`) kommen eine Stufe tiefer in den `try`-Teil, die Freigabe ins `finally` (ein direkt folgendes `X := nil;` geht mit, wenn es allein auf seiner Zeile steht bzw. die Zeile der Freigabe beschliesst - sonst bleibt es hinter dem `end;` stehen). `try`/`finally`/`end;` stehen in eigenen Zeilen, eingerueckt wie die Erzeugung; die Stufe ist die der Liste (Einrueckung der Erzeugung gegen ihren Oeffner `begin`/`try`/`except`/..., hoechstens vier Zeichen, sonst zwei Leerzeichen bzw. ein Tab; sie kommt hinter den Leerraum, den eine Zeile mit der Erzeugung teilt - gemischte Einrueckung aus Tab und Leerzeichen bleibt in ihrer Art), Leerzeilen bleiben leer, Kommentarzeilen ruecken mit. Gekennzeichnet nach E2: Free laeuft danach auch bei einer Ausnahme und bei Exit - das ist der Fix. Nachweis am Puffer: die Erzeugung ist eine ganze Anweisung einer Anweisungsliste (nicht hinter then/else/do, kein case-Zweig), allein auf ihrer Zeile, die rechte Seite traegt ein `.Create..`; die Freigabe steht als ganze, UNBEDINGTE Anweisung in DERSELBEN Liste dahinter (Blocktiefe 0, hinter `;`), allein auf ihrer Zeile. Gesperrt: keine solche Freigabe (sie steht tiefer, in einem Zweig oder fehlt), eine bedingte, tiefer liegende oder zweite Freigabe bzw. eine zweite Zuweisung an X im Bereich (Doppelfreigabe), nichts zwischen Erzeugung und Freigabe (es gaebe nichts zu schuetzen), Direktive, Marke/goto (ein Sprung in einen try-Block uebersetzt nicht), asm, Inline-`var`/`const` auf der Ebene der Erzeugung (ihr Gueltigkeitsbereich schrumpfte auf den try-Teil), mehrzeiliges `'''`-Literal (Einruecken aenderte es), Break/Continue, deren Schleife den Bereich umschliesst (X waere hinter der Schleife frei; in einer Schleife ganz im Bereich gehen sie), Exit, wenn X im Bereich weitergegeben wird (`if Liste.TryAdd(X) then Exit;` - der Ausstieg uebergibt vielleicht den Besitz; die Spruenge seit Charge B1-FE auch als `System.Exit`/`System.Break`/`System.Continue` - hinter dem Punkt sah die Hilfe sie vorher nicht, Gegen-Review R5), X in einem raise-Ausdruck (`raise X`, `raise TObject(X)`, `raise X at ..`, `Exception.RaiseOuterException(X)`), eine Freigabe in anderer Schreibweise im Bereich (`TObject(X).Free`, `Self.X.Free`, `FreeAndNil(Self.X)` - mit finally liefe sie doppelt), ein umschliessendes try, dessen except- bzw. finally-Teil X nennt (er liefe danach hinter dem finally: zweite Freigabe bzw. Zugriff auf ein freies Objekt), und eine Weitergabe auch OHNE Ausstieg (seit Charge H4c, Gegen-Review H4 Blocker 1 - im Fehlerfall gaebe finally X frei, waehrend ein Halter es noch kennt: aus einem Leck wuerde ein Use-after-free): X als direktes Argument eines Aufrufs, dessen Name mit add/insert/push/enqueue/register/attach/subscribe/put beginnt (nicht `InsertComponent` - der Destruktor meldet sich beim Owner ab - und `AddStrings`, das nur kopiert), X als ganze rechte Seite einer Zuweisung an etwas anderes als eine lokale Variable der Routine (Feld, Property, Element, `Result`, globale Variable, Parameter) - beides auch in einer Huelle aus Cast, Klammern und `as` (`List.Add(TObject(X))`, `List.Add(X as TObject)`, `FCurrent := TFoo(X)`, `FObj := (X)`; bis Charge B1-FE nur der Cast im Aufruf, Gegen-Review R5), ein Methodenzeiger `X.M` an ein Ereignis (`Btn.OnClick := X.Handler`) und `@X` bzw. `@X.M`. Bewusst eng: die breite Fassung (jedes Argument, jede Zuweisung) kostete 372 von 909 Objekt-Angeboten. Das Meldungs-Suffix `(try/except instead of try/finally)` sagt nur, dass die Methode irgendwo ein try/except hat (uMissingFinally), nichts ueber den Ort - die Hilfe prueft wie ohne; bis Charge H4c verlangte sie ein try/except im Bereich und keines drumherum (ein Lesefehler des Detektors, Gegen-Review H4 Major 1). SCA001: never-freed, return-value und proven-leak stehen gesperrt mit ihrer Variante da (massgeblich ist das Feld `TLeakFinding.LeakVariant`, das uLeakDetector2 setzt - ein Fund ohne Feld, etwa von uFieldLeak, bekommt keine Hilfe). Restrisiko: eine Weitergabe, die die Sperre nicht sieht - ueber einen Alias (`Y := X; Liste.Add(Y)`), an einen Konstruktor, der den Besitz uebernimmt (`TReader.Create(X)`), an einen Aufruf anderen Namens (`Store(X)`) oder als Methodenzeiger im Argument (`Subscribe(X.Handler)`). Korpus: SCA009 894 von 1.102 (Charge H4: 857; +49 ohne die Suffix-Regel, -12 durch die Weitergabe-Sperre), SCA001 52 von 67 (freed-outside-finally); im Rundlauf verschwand jeder Fund (auch die 49 neuen der Charge H4c; dort Folgefunde SCA090 NestedTry bei 39 - das try/except umschliesst jetzt ein try/finally - und SCA001 freed-outside-finally bei 17). Folgefunde: SCA001 freed-outside-finally fuer weitere Variablen derselben Routine (sie hat jetzt ein try/finally, deren Free steht daneben - 212 Angebote), SCA090 NestedTry, SCA012 LongMethod |
| Sperre X in einem try/finally-Block freigeben (aendert Verhalten) | SCA109, SCA153 | derselbe Baustein fuer Sperren: Lock/UnLock, Enter/Leave, Acquire/Release, BeginWrite/EndWrite, `TMonitor.Enter(O)`/`TMonitor.Exit(O)`, `EnterCriticalSection(CS)`/`LeaveCriticalSection(CS)` (auch qualifiziert) und die eigene Methode `Lock;`/`UnLock;`. Die Freigabe bestimmt die Hilfe selbst: derselbe Empfaenger bzw. dasselbe Argument, als Text ohne Leerraum gleich (`Self.FLock` und `FLock` sind verschieden; steht dieselbe Sperre im Bereich in anderer Schreibweise frei - `Self.FLock.Leave`, `TFoo(FLock).Leave`, `FLock.Release` nach `FLock.Enter` (TCriticalSection kennt beide), `LeaveCriticalSection(Self.FCS)` -, sperrt das: mit finally liefe sie doppelt) - SCA153 nimmt jedes `unlock`/`release` im 200-Zeichen-Fenster, auch das fremder Objekte. Die Sperre der Meldung wird auf der Zeile nachgeprueft (SCA153: `FLocker.Lock`, `Lock`, `EnterCriticalSection`; SCA109: das Wort vor `.Enter`/`.Acquire`/`.BeginWrite`, `TMonitor.Enter(o)`, `EnterCriticalSection(...)`). Gesperrt wie oben, dazu: Exit im Bereich (Konzept; auch `System.Exit`), eine zweite Sperre derselben Sperre, `Lock(..)` mit Argumenten (keine Sperre), `TMonitor.Enter(O, Timeout)` bzw. `TMonitor.TryEnter(O)` (eine Bedingung, mit eigenem Grund) und ein umschliessender Handler, der sie freigibt (auch in anderer Schreibweise). Korpus: SCA109 30 von 35, SCA153 219 von 241; ein Fund an beiden Regeln verschwindet mit der einen Hilfe aus beiden |
| Puffer X in einem try/finally-Block freigeben (aendert Verhalten) | SCA156 | derselbe Baustein fuer `GetMem(P, N)`, `P := AllocMem(N)`, `var P[: T] := AllocMem(N)` und `P := GetMem(N)` (FPC) mit `FreeMem(P[, N])` bzw. `FreeMemAndNil(P)`; ein direkt folgendes `P := nil;` geht mit ins `finally` wie bei Objekten (seit Charge B1-FE). Gesperrt wie oben, dazu: P ist keine lokale Variable der Routine (Feld, globale Variable, Parameter - nach dem finally kennte der Halter den freigegebenen Puffer, eine finalization bzw. ein Destruktor gaebe ihn ein zweites Mal frei; seit Charge B1-FE, Gegen-Review R5), ReallocMem (der Puffer bestand schon vorher), `Result := ..` (der Puffer verlaesst die Routine), ein erstes Argument, das kein einfacher Bezeichner ist (`Pointer(P)`), ein qualifizierter Aufruf (eigener Speichermanager; `System.GetMem`/`System.FreeMem` sind die RTL und gehen), `Inc`/`Dec`/`GetMem`/`ReallocMem`/`@` auf P im Bereich, auch durch einen Cast (`Inc(PByte(P), 4)` - FreeMem gaebe einen anderen Zeiger frei), eine Freigabe in anderer Schreibweise (`FreeMem(PByte(P))`) und eine Weitergabe ohne Ausstieg wie bei Objekten (`FBuf := P`, `Liste.Add(P)`). Korpus: 36 von 85 (Charge H4: 38; die zwei Weitergaben `RegisterClipboardFormat(P)`/`RegisterWindowMessage(P)` sind WinAPI-Aufrufe, die nur kopieren - der Preis der Namensregel) |
| inherited Create bzw. inherited als Erstes im Konstruktor aufrufen (inherited: aendert Verhalten) | SCA096 | Charge H5, Baustein "erste Anweisung": eine eigene Zeile hinter dem `begin`, eingerueckt wie die erste Anweisung (sonst eine Stufe tiefer als `begin`); steht hinter `begin` auf seiner Zeile Code oder eine Direktive - auch im Einzeiler `begin end;` -, inline direkt dahinter (`begin inherited Create; end;`: die Zeilen des Autors bleiben, wie bei SCA020). Ein Eintrag je Fund, die Variante waehlt die Hilfe (wie SCA149): ruft `inherited Create` in dieser Unit belegt TObject.Create - die Klasse erbt DIREKT von TObject (`class`, `class(TObject)`, `class sealed`, generisch, als erster Eintrag ein unqualifiziertes Interface DIESER Unit auf Unit-Ebene - ein in einer anderen Klasse geschachteltes Interface ist dort nicht sichtbar, seit Charge B1-FE) oder von einem Vorfahren ohne eigenen Konstruktor (TPersistent, TInterfacedObject, TCustomAttribute; in den Delphi-Quellen 23.0 und 37.0 nachgesehen, feste Liste; nicht, wenn die Unit den Namen selbst deklariert - Charge H5c) -, `inherited Create;` - bedeutungsgleich, TObject.Create ist leer, auch bei Overloads; nie nacktes `inherited;` (es reichte die eigenen Parameter weiter, TObject hat keinen Konstruktor mit Parametern). Traegt die Deklaration `override`, `inherited;` - gekennzeichnet nach E2: der ueberschriebene Elternkonstruktor laeuft danach zuerst, mit denselben Argumenten (Delphi uebersetzt `inherited;` gegen ihn; `override` an der Deklaration ist der Beleg, die Elternklasse liegt meist in einer anderen Unit). Gesperrt: ein anderer Vorfahr ohne `override` (welcher Elternkonstruktor mit welchen Argumenten laufen soll, ist Entwurf - im Korpus 735 von 1.977 Funden), `override` mit `overload`, mehr als eine Deklaration (Overload), ein Aufruf `Create..` in Anweisungsstellung bzw. `Self.Create..` oder eines Konstruktors, den die Klasse bzw. ein Vorfahr in der Unit deklariert, auch ohne `Create` im Namen (Delegation an einen anderen Konstruktor, der die Elternklasse schon initialisiert - `TCustomForm.CreateNew` laedt danach keine .dfm, ein `inherited;` davor taete es; mORMot `THttpClientSocket.OpenFrom` ruft `OpenOptions`, ein `inherited;` davor oeffnete eine zweite Verbindung; der Detektor kennt nur `Create(`; Korpus 18), eine geerbte Methode, die in der Unit `abstract` ist (FPC objfpc uebersetzt `inherited;` darauf nicht, Delphi-Modus laesst es still weg; Korpus 11), unter `{$mode objfpc}`/`{$mode fpc}` eine Vorfahrenkette, die die Unit verlaesst (abstrakt oder nicht ist dann nicht beweisbar), eine Direktive in der Vorfahrenliste (`class({$IFDEF FPC}TPersistent{$ELSE}TObject{$ENDIF})` - der Vorfahr haengt an einem Zweig), eine erste Anweisung, die abbricht (`raise`, `Assert(False..)`, ein Aufruf `..Raise..(`: blockierter Konstruktor, Korpus 3), `inherited` irgendwo im Text der Routine (Kommentar, inaktiver Zweig, lokale Routine - `// inherited Create; use AfterCreate instead`, Korpus 24), `object`-Typ, Record, class helper, Klasse nicht oder mehrfach in der Unit, `class constructor`, asm, eine Direktive zwischen Kopf und `begin`, zwei Koepfe auf der Zeile. Korpus: 1.069 von 1.977 (1.027 `inherited Create`, davon 255 seit Charge H5c ueber TPersistent/TInterfacedObject/TCustomAttribute; 42 `inherited`); im Rundlauf verschwand jeder Fund. Folgefunde: SCA020 EmptyMethod faellt weg (der Rumpf ist nicht mehr leer), SCA054 UnusedParameter faellt weg (`inherited;` reicht die Parameter weiter) |
| inherited als Letztes im Destruktor aufrufen (aendert Verhalten, ausser bei TObject) | SCA097 | Baustein "letzte Anweisung": `inherited;` in eine eigene Zeile direkt vor das `end` des Rumpfs (eingerueckt wie die erste Anweisung; Kommentarzeilen davor bleiben davor), steht `end` nicht am Zeilenanfang, inline hinter der letzten Anweisung; fehlt ihr das `;`, kommt es mit (zweite Ersetzung) - hinter ihr letztes Zeichen aus Code oder String (`FState := 'x';`; bis Charge B1-FE kam es vor ein abschliessendes String-Literal: `FState :=; 'x'`, Gegen-Review R5). Leerer Rumpf: wie die erste Anweisung. Nur mit `override` an der Deklaration im Klassenrumpf - sonst verdeckt Destroy die virtuelle Methode (eigentlich SCA149). Gekennzeichnet nach E2: der Elterndestruktor laeuft danach und gibt die geerbten Felder frei; erbt die Klasse direkt von TObject, bedeutungsgleich und nicht gekennzeichnet (TObject.Destroy ist leer). Gesperrt: kein `override`, eine letzte Anweisung `Exit`/`raise`/`Halt`/`Abort`/`goto`, auch `System.Exit`, `System.Halt`, `SysUtils.Abort` (inherited liefe nie; ein `FConn.Abort` ist eine Methode), `Exit` (auch `System.Exit`) oder `goto` auf jeder Tiefe (der Ablauf verlaesst den Destruktor vor dem Ende - Abbrevia `TMultiTree.Destroy`), eine in der Unit abstrakte geerbte Methode und unter `{$mode objfpc}` eine Vorfahrenkette ausserhalb der Unit (wie SCA096; Korpus 9, doublecmd), eine Direktive zwischen letzter Anweisung und `end` (das Ende kann je Zweig anders aussehen), `inherited` im Text der Routine (`//inherited Destroy; not needed`, `fSafe^.DoneAndFreeMem; // = inherited Destroy` - Korpus 16), `object`-Typ, `class destructor`, asm, eine Direktive zwischen Kopf und `begin`. Korpus: 128 von 156 (90 bedeutungsgleich); im Rundlauf verschwand jeder Fund; Folgefund SCA020 EmptyMethod faellt weg |
| Result mit dem Anfangswert initialisieren (aendert Verhalten) | SCA121 | `Result := <Wert>;` als erste Anweisung (Baustein wie SCA096), der Wert nach dem Rueckgabetyp T aus dem Kopf wie im Quelltext (generisch, qualifiziert, der Typparameter `T`, `class operator`; ein Implementierungskopf ohne Signatur `function TFoo.Bar;` nimmt T aus der Deklaration im Klassenrumpf): seit Charge H5c ein Literal, wo der Typ es traegt - `False` (Boolean-Familie), `0` (Ganzzahl-, Gleitkomma-, Datums- und Waehrungstypen der RTL), `''` (string-Familie, `string[n]`), `#0` (Char), `nil` (Pointer, PChar, TObject, TClass, TBytes, TArray<..>, *DynArray, Klassen und Interfaces der Delphi-Quellen), `[]` bzw. `System.Low(T)` fuer eine schlichte Aufzaehlung (Typen der Unit; deklariert die Unit einen Namen selbst, gilt ihre Definition - nur auf Unit-Ebene) -, sonst `Default(T)` (Records, Typparameter, Unbekanntes, ein Name, den die Unit auch in einer anderen Routine oder einem Klassenrumpf definiert: welche Definition gilt, haengt am Gueltigkeitsbereich). Seit Charge B1-FE (Gegen-Review R5) `System.Low(T)` statt des ersten Werts - ein Member gleichen Namens (property bzw. Feld `None`) verdeckte ihn, `Result := None;` uebersetzte nicht bzw. nahm still den Feldwert. Qualifiziert seit der Nachpruefung: ein unqualifiziertes `Low(T)` verdeckt ebenso jedes andere `Low` im Gueltigkeitsbereich (Property bzw. Feld der Klasse, eines Vorfahren oder eines Records, Variable der Unit - `Result := Low(TKind);` neben `property Low` uebersetzte nicht). `System.Low(T)` verdeckt nur ein Bezeichner `System`: nennt die Unit selbst einen, `Default(T)`; einen aus einer anderen Unit (Member eines Vorfahren) sieht die Hilfe nicht, der Compiler meldet es. Unit-qualifiziert stehen Compiler-Funktionen auch in den Delphi-Quellen (`System.Length`, `System.SizeOf`), JCL/JVCL und DWScript (`System.High(Self)`); FPC 3.2.2 uebersetzt `System.Low(T)` neben property, Feld und Parameter `Low`. Gekennzeichnet nach E2: Result ist danach definiert statt zufaellig; spaetere Zuweisungen gelten weiter (die Einfuegung am Anfang ueberschreibt nichts, auch nicht eine Zuweisung in einem `$IFDEF`-Zweig, den der Detektor nicht sah). `Default()` gibt es ab Delphi 2009 bzw. FPC 3.0 - in einer Datei mit Spuren aelterer Compiler (`{$I jvcl.inc}`, `jedi.inc`, `jcl.inc`, `CnPack.inc`, `CnWizards.inc`, `IdCompilerDefines.inc`, `{$IFDEF DELPHI2007_UP}`, `VER150`, `COMPILER6_UP`, `{$IF CompilerVersion < 20}` ...) ist es gesperrt (Korpus 11; JVCL und CnWizards bauen ab Delphi 5/6). Gesperrt ausserdem: eine Zuweisung an Result bzw. den Funktionsnamen oder `Exit(Wert)` (auch `System.Exit(Wert)`) im Rumpf - auch im inaktiven `$IFDEF`-Zweig, ohne lokale Routinen (der Detektor sah sie nicht, der Fund ist fraglich: Indy `IdStackDotNet`; Korpus 32), eine Datei ohne `implementation`-Teil bzw. ohne unit/program/library-Kopf (xEdit-/JvInterpreter-Skripte und Includes - ihr Interpreter kennt Default() nicht; Korpus 128 von 277), `{$mode fpc/tp/macpas/iso}` und `{$X-}`/`{$EXTENDEDSYNTAX OFF}` (dort gibt es kein Result), asm-Rumpf oder asm-Block im Rumpf, eine Direktive zwischen Kopf und `begin` (Korpus 15), ein Rueckgabetyp, der kein einfacher Typbezeichner ist (FPC `specialize`, ueber Zeilen, mit Kommentar) bzw. den die Funktion in ihrem Deklarationsteil selbst definiert (`function GetMode: TMode; type TMode = (..);` - im Rumpf meint der Name den lokalen Typ, im Kopf den aeusseren; seit der Nachpruefung), eine freie Funktion ohne Signatur im Kopf (die Deklaration im interface-Teil liest die Hilfe nicht), mehrere Deklarationen. Korpus: 89 von 277 (43 `''`, 17 `nil`, 13 `False`, 7 `0`, 9 `Default(T)`); im Rundlauf verschwand jeder Fund; Folgefund SCA020 EmptyMethod faellt weg |
| Result zuerst initialisieren (aendert Verhalten) | SCA196 | als erste Anweisung `Result := '';` (die string-Familie des Detektors: string, UnicodeString, AnsiString, WideString, ShortString, RawUtf8 ...), `Result := nil;` (TArray<..>, TBytes, die *DynArray der RTL bzw. `Name = array of` in der Unit, ein Interface der Unit bzw. der Delphi-Quellen; deklariert die Unit den Namen selbst, gilt nur ihre Definition - `TBytes = array[0..3] of Byte` ist gesperrt, Charge H5c; steht eine Definition des Namens in einer Routine oder einem Klassenrumpf, sperrt das, Charge B1-FE - auch in einem Include ohne unit-Kopf, wo Routinen ab dem Dateianfang stehen, seit der Nachpruefung) oder `VarClear(Result);` (Variant, OleVariant - fehlt Variants in uses, kommt `System.Variants` bzw. `Variants` mit, wie SysUtils bei FreeAndNil: FPC kennt VarClear nur dort). Die Meldung zeigt auf die Lese-Zeile: die Hilfe sucht die innerste Routine um sie (Koepfe aufwaerts, Routinengrenzen wie SCA164), Name und Rueckgabetyp muessen zur Meldung passen, auf der Zeile muss `Result` stehen. Lokale Routinen zwischen Kopf und `begin` sperren nicht mehr (das Konzept nannte sie, als nur leere Rumpfe lesbar waren): eingefuegt wird hinter dem `begin` der aeusseren Routine, vor jedem Aufruf einer lokalen. Gekennzeichnet: Result haengt danach nicht mehr am alten Inhalt der Zielvariable des Aufrufers - fuer jeden Aufrufer mit leerem Ziel identisch. Gesperrt: ein Typ, der nicht als String, dynamisches Array, Interface oder Variant bewiesen ist (ein fremdes `IFoo` kann ein Record sein), `absolute Result`, asm, eine Direktive zwischen Kopf und `begin`, ein FPC-Modus ohne Result. Korpus: 43 von 43; im Rundlauf verschwand jeder Fund; Folgefund SCA012 LongMethod (2 - die Routine waechst um eine Zeile) |
| Lokale Konstante fuer N einfuehren | SCA014 | Charge Q14 (E28): `const MagicNr01 = N;` als eigene Anweisung direkt vor der Anweisung mit der if-Bedingung, das Literal der Bedingung durch den Namen - nur DAS eine, gleiche Literale hinter `then` bleiben; ein Zweig ohne `begin` bekommt `begin..end`. Die Logik ist die der Code-Aktion "Lokale Konstante einfuehren" (`uRdxIntroPlan`/`uRdxIntroEdits`, unten) - ohne Sync-Edit-Sitzung, EINE Ersetzung, ein Undo-Schritt. Name: der erste `MagicNrNN`, der in der Datei nicht als Wort vorkommt; umbenennen von Hand oder mit Refactor > Rename (Strg+Umschalt+E) - nicht Sync Edit, dort zerstoert Esc Text (Hinweis; Charge SQc). Bedeutungsgleich nach der Praemisse von E26: die untypisierte Konstante haelt Faltung, Ueberladungswahl und vorzeichenlose Rechnung des Literals - fuer den Quick-Fix (ersetzt wird nur ein Vergleichswert einer if-Bedingung) gilt das als sicher; gemessen ist es noch nicht (Teil P6 der Kompilierprobe des Labors, Bau offen - `VarNameProject\README.md`), und fuer die Code-Aktion ohne Fund (alle gleichen Literale, Arithmetik, Ueberladungen) entscheidet erst P6. Ziel aus dem Fund: die Zahl der Meldung als Vergleichswert (hinter `>=`, `<=`, `<>`, `>`, `<`, `=`) in den if-Bedingungen der Fundzeile, auch ueber Folgezeilen bis `then` - kein Teil von `200.5`, `$200`, `#200`, `-200`, `200_000`; keiner: Zeile verschoben - ausser ein Vergleichswert mit Zifferntrennern beginnt mit der Zahl: `200_000` (auch `200_000.5`) meldet der Detektor als `200` (er liest `_000` als Bezeichner), ein Fehlalarm, und der Grund sagt das samt dem Literal (Review R6-05; Korpus 1, `ISSigFunc.pas`) -, mehrere: mehrdeutig (Korpus 102), einer in einer Folgezeile der Bedingung: gesperrt (193 - die Konstante gehoerte vor die if-Zeile). Gesperrt ausserdem: die Sperren der Code-Aktion (`else if` 319, Zweig ueber mehrere Zeilen 261, Zeile darueber ohne Anweisungsende 74, Direktive davor 28, case-Zweig, asm, initialization, mehrzeilige Strings und Kommentare ...), eine FPC-Weiche in der Datei (1.724) oder einem Include (63), Spuren von Compilern vor Delphi 10.3 in der Datei (1.275) oder einem Include (108: `jvcl.inc` & Co., `VER320`, `CompilerVersion >= 33`, `DELPHIXE2_UP`, `CONDITIONALEXPRESSIONS` ... - die Schwelle selbst zaehlt mit, so schuetzt `dmvcframework.inc` Delphi 10.0 bis 10.2), ein Include, das nicht neben der Unit liegt (55), ein Lazarus-Projekt/-Paket (`.lpi`/`.lpk`/`.lpr`) bis zwei Verzeichnisse ueber der Unit (88, doublecmd/CnWizards/mORMot/Indy), `.pp`/`.lpr`, xEdit-Skripte (18); seit Charge SQc (Gegen-Review Q14) auch ein altes Delphi-Projekt im selben Fenster - das naechste Verzeichnis mit Delphi-Projektdateien entscheidet: `.dproj` mit `ProjectVersion` unter 18.5 (vor 10.3) oder ohne lesbare Version, ohne `.dproj` eine `.dof`/`.bdsproj`/`.bpr`/`.bpg` (120: CnWizards 72, JVCL 37, GExperts 2 ...) -, ein Netzpfad bzw. Netzlaufwerk (kein Plattenzugriff im Hauptthread; seit Charge B1-FD auch ein Include auf einem Netzpfad in einer lokalen Unit - vorher 9 bis 16 s Wartezeit je Menueaufbau; `\\?\C:\..` ist lokal, bis Charge B2S-a lehnte die Hilfe ihn als Netzpfad ab) und der Hauptblock eines Programms bzw. einer Bibliothek (ob dort eine Inline-Deklaration gilt, ist nicht gemessen; ein `End := 1` als benanntes Argument verdeckt ihn seit Charge B1-FD nicht mehr). Steht zwischen Zweigzeile und Anweisung eine Leerzeile, beginnt die eine Ersetzung an der Zweigzeile (bis Charge B1-FD begann sie auf der Leerzeile, und jeder Klick scheiterte mit "Menue neu oeffnen"). Korpus: 576 von 5.036 (vor Charge SQc 696; 1 mit `begin..end`); im Rundlauf verschwand jeder Fund, 23-mal meldet der Detektor danach die naechste Zahl derselben Bedingung (er meldet je if eine); Folgefunde SCA021 DuplicateBlock (+-), SCA144 FloatEquality -2 (sieht nur Literale), SCA072 RedundantBoolean -2 (Nebenbefund: sein const-Abschnitt-Tracker haelt die Inline-Konstante fuer einen const-Abschnitt) |
| Leeren Sichtbarkeitsabschnitt entfernen | SCA087 | loescht die Zeile des leeren Abschnitts (`public`, `strict private` ...). Nur, wenn sie genau diesen Abschnitt traegt, ohne Kommentar; gesperrt bei `strict` allein auf der Zeile (es gehoert zur naechsten) und bei einer Compiler-Direktive bis zum naechsten Abschnitt (der Abschnitt waere vielleicht nur in einem Zweig leer) |
| Hier / In dieser Datei unterdruecken | jeder Fund in Pascal-Quelltext | setzt `// noinspection <Art>` ueber die Fundzeile bzw. `// noinspection-file <Art>` hinter die Kopfanweisung (`fakSuppress`); ein vorhandener Marker bekommt die Art dazu, ausser er lautet `All`/`*` (dann eine eigene Zeile). Nicht angeboten, wenn die Fundzeile in einem Block-Kommentar oder mehrzeiligen String liegt. Auf einer Kommentarzeile (`//`, etwa ein TODO) bekommt der Marker, der sie schon traegt, die Art auch ueber Leerzeilen hinweg; einer, der sich nicht erweitern laesst (`All`, Marker hinter Code), sperrt, wenn eine seiner Arten dort gemeldet werden kann (s. unten) - eine neue Zeile dazwischen naehme ihm sein Ziel, die Unterdrueckung eines anderen Funds fiele weg (Review R1-03; der Core vereinigt gestapelte Marker nur fuer das Code-Ziel). Einen wirkungslosen Marker (SCA165) entfernt "Wirkungslosen Unterdrueck-Marker entfernen" stattdessen - nur, wenn er genau EINE Art nennt; ein Mehrarten- oder `All`-Marker steht gesperrt mit Grund da, denn SCA165 kommt auch, wenn nur die Arten des aktiven Scan-Profils nichts unterdrueckt haben. Gesperrt auch, wenn die naechste nicht-leere Zeile hinter dem Marker eine Kommentarzeile vor dem Code ist (auch die Markerzeile darunter bei gestapelten Markern) UND seine Art auf einer Kommentarzeile gemeldet werden kann - TodoComment, CommentedOutCode, NoSonarMarker, die Zeilenregeln TabulationCharacter/TooLongLine/TrailingWhitespace, CustomRule, die Kodierungsregeln SCA185-SCA193 und UnusedSuppression: SCA165 prueft nur das Code-Ziel, dort wirkt der Marker vielleicht doch - sonst entfernte die Hilfe den Marker, den "Hier unterdruecken" ueber einer TODO-Zeile eben gesetzt hat, und der Fund kaeme zurueck (Review R1-01; den Fehlalarm SCA165 selbst behebt erst der Core). Ein Marker einer Code-Art mit Warum-Kommentar darunter (`// noinspection ExceptionTooGeneral`, Kommentar, `on E: Exception do`) wirkt nur auf dem Code - meldet der Core ihn, ist das echt, und die Hilfe entfernt ihn (Nachbesserung; die erste Fassung sperrte auch dort: 41 der 116 reinen Zeilen-Marker im eigenen Code). Eine Zeile mit `{`/`(*` ist fuer den Core Code, dort bleibt das Entfernen. Korpus (ab8, 5.441 Funde auf `//`-Zeilen, 3.000 auf Code-Zeilen): "Hier unterdruecken" unveraendert; das Entfernen des eben gesetzten Markers bot die Hilfe vor R1-01 5.416-mal an (Ergebnis byte-gleich zum Ausgang), jetzt 59-mal - nur fuer Arten, die auf keiner Kommentarzeile gemeldet werden (56 Funde einer Datei, die nach dem Referenzlauf geaendert wurde - Zeilen verschoben -, 3-mal EmptyFile auf Zeile 1, wo der neue Marker ohnehin nicht wirkt); auf Code-Zeilen weiter 2.977 von 2.977 |

**Verschachtelte Sperren und Puffer** (Nebenbefund, Charge H4): die lexikalischen Detektoren SCA153/SCA109/SCA156 sehen eine zweite, noch ungeschuetzte Sperre bzw. Allokation derselben Routine nach der Hilfe nicht mehr - SCA153 haelt sie hinter einem offenen `try` bzw. vor einem `try` fuer geschuetzt, SCA156 genuegt ein `finally` vor IRGENDEINEM FreeMem. Im Korpus-Rundlauf verschwanden so 7 Funde, ohne behoben zu sein (`aBitmap.Canvas.Lock` neben `FBuffer.Canvas.Lock` in uCEFBufferPanel, `GetMem(OutPutBuffer)` neben `GetMem(InPutBuffer)` in JvUIBObj). Die Hilfe ist dort richtig; die andere Stelle von Hand nachsehen. Die innere zuerst zu schuetzen hilft nicht - dann verdeckt sie die aeussere ebenso; eine Sperre in der Hilfe brachte deshalb nichts.

**SCA150 BoolAlwaysTrue** bekommt bewusst keine Hilfe (in Charge H2
optional): die Meldung nennt weder Spalte noch Ausdruck; im Realwelt-Korpus
gibt es keinen Fund, im Lazarus-Korpus einen - der Korpus-Harness, das Mass
jeder Charge, kann sie nicht messen. Die bedeutungsgleiche Variante
(`if Length(s) >= 0 then A else B` -> `A`, `if Length(s) < 0 then A;` -> weg)
loescht einen ganzen Zweig und braucht dafuer den Baustein Blockpaarung
(Zweigende, haengendes `else`), den H2 nicht bringt; ausserdem muss `Length`
die RTL-Funktion sein - eine Methode `Length` aus einer anderen Unit ist im
Text nicht auszuschliessen (dasselbe Restrisiko wie bei SCA080/`Exit`, hier
aber ohne Korpus, es zu wiegen). Die gekennzeichnete Variante (`>= 0` ->
`> 0`) raet die Absicht ohne einen einzigen Beleg.

**uses-Ergaenzung im Einzelnen** (`TRdxRecipeRunner.PlanUses`, fuer
`Format()` und `FreeAndNil(X)`):

* **Welche Klausel:** die des implementation-Abschnitts, sonst die des
  interface-Abschnitts, sonst die Programm-Klausel (.dpr, .lpr, library).
  Ohne jede uses-Klausel wird hinter `implementation` (sonst hinter
  `interface`) eine neue angelegt. Ein Programm oder eine Library ohne
  uses-Klausel bekommt keine: der Eintrag bleibt ausgegraut
  (`System.SysUtils fehlt in uses: keine uses-Klausel und kein
  interface/implementation`).
* **Welcher Name:** `System.SysUtils`, wenn die Datei Delphi-Unit-Scopes
  schreibt (ein Eintrag unter `System.`, `Winapi.`, `Vcl.`, `FMX.`,
  `Data.`, ...) oder noch keinen uses-Eintrag hat, sonst `SysUtils` - ein
  Punkt allein ist kein Scope (`Generics.Collections`, `MyLib.Utils`). Eine
  Datei mit FPC-Weiche oder FPC-Modus (`{$IFDEF FPC}`, `{$IFNDEF FPC}`,
  `DEFINED(FPC)`, `{$mode ..}`, auch als `(*$..*)`) bekommt immer
  `SysUtils`: FPC 3.2 kennt keine Unit-Scopes.
* **Wohin in der Liste:** eine sortierte Liste bleibt sortiert (dasselbe
  Kriterium wie SCA142), eine unsortierte bekommt den Namen vorn. Gehoert
  der Name ans Ende, wird hinter dem letzten Eintrag angehaengt - samt
  `in`-Pfad und Block-Kommentar ohne `$` (`Main in 'Main.pas' {Form1}`),
  wenn danach auf derselben Zeile das `;` folgt, oder wenn die Zeile hinter
  dem Eintrag endet und die naechste nicht leere Zeile mit `;` beginnt.
  Steht dort etwas anderes (ein `//`-Kommentar, das `;` erst nach weiterem
  Text), wird VOR dem letzten Eintrag eingefuegt: immer gueltig, aber die
  Sortierung kann dann brechen.
* **Gesperrt** (Handarbeit): eine Compiler-Direktive in der Klausel (`{$..}`
  oder `(*$..*)`, von der Zeile des `uses` bis zum letzten Eintrag) oder
  eine Klausel, die ganz oder teilweise in einem `$IFDEF`-Zweig liegt - ein
  Eintrag dort kann in einem Zweig fuer ein anderes Ziel stehen.
* Beide Ersetzungen (Kette und Klausel) werden vor dem Schreiben gegen den
  Puffer geprueft und dann in EINEM Undo-Schritt geschrieben.

**Kompilat-Regel** (`TRdxRecipes.JudgeOperand`, Realworld-Stichprobe
2026-10-06): mit "nur beweisbar String" waeren am Korpus hoechstens 17 %
der SCA044-Stellen umformbar - der haeufigste Blocker waren Bezeichner
wie `sLineBreak` und Member wie `E.Message`, die in der Datei keinen
deklarierten Typ haben. Das Kompilat buergt aber: eine `+`-Kette mit einem
String-Literal uebersetzt nur, wenn jeder Operand String-vertraeglich ist
(String, Char, PChar, AnsiString, ...) oder ein Variant - und `%s` nimmt
all das, Variant eingeschlossen. Die einzige Luecke: hinter einem Variant
darf auch eine Zahl oder ein Boolean stehen, und daran scheitert `%s` zur
Laufzeit. Ebenso am Kettenanfang hinter einem Zeiger (Charge FB, Review
R2-04): `P + FOffset + '.txt'` mit `P: PChar` rechnet zuerst Zeiger-
Arithmetik und verkettet erst dann - gesperrt, wenn der erste Term als
PChar/PWideChar/PAnsiChar deklariert oder ein Cast darauf ist und der
zweite weder Literal noch bewiesener String; ein PChar unbekannten Typs
(Feld oder Funktion einer anderen Unit) bleibt unsichtbar - Format wirft
dann zur Laufzeit. Beim Selbst-Anhaengen (`X := X + P + ..`) ist X der
Kettenanfang, ein String - dort gilt die Sperre nicht (Nachpruefung FB:
bis dahin lehnte der erste Term hinter `X +` ab). Deshalb gilt ein Operand unbekannten Typs, wenn seine Form ein
Operand ist (Bezeichner, Member, Aufruf, Index, Cast) und er keine
Variant-Anzeichen traegt (`.Value`, `.AsVariant`, `FieldValues`, `Null`,
`Unassigned`, `True`/`False`/`nil`, `Variant(...)`, deklariert `Variant`,
`V.Name` mit `V: Variant`, `DS['Name']` = `TDataSet.FieldValues`). Warum
Variant sperrt: ist der Wert Null oder keine Zeichenkette, wirft das
Original (`NullStrictConvert`, Variant-Arithmetik String+Zahl) oder die
ganze Kette wird leer - `Format` gaebe still die uebrigen Teile aus.
Gesperrt bleiben Zahlen, Zahl-Casts, Aufrufe mit Zahl-Ergebnis (`Length`,
`Ord`, `Pos`, `StrToInt`, ...), blosse Klammerausdruecke, Mengen und
Nicht-Unicode-Strings - deklariert (`AnsiString`, `RawByteString`,
`UTF8String`, `ShortString`, `RawUtf8`) oder als Cast bzw. Funktion
(`AnsiString(x)`, `UTF8Encode(s)`, ...) - als Ziel immer und als Operand,
wenn das Ziel nicht nachweislich Unicode ist: `Format` liefert
`UnicodeString`. Ein `AnsiChar`-Operand sperrt immer (`Format` wandelt ihn
ohne Codepage). `(Sender as TButton).Caption` ist ein Operand. Der
Menuetext nennt die Herkunft: `5 Terme, 2 laut Kompilat (E.Message,
Edit1.Text)` oder `alle bewiesen`. Bewiesen sind Literale, deklarierte
String-Typen, RTL-Funktionen mit String-Ergebnis (`IntToStr`,
`ExtractFileName`, `Copy`, `TPath.Combine`, ...), RTL-Konstanten
(`sLineBreak`, `PathDelim`) und `.ToString`. In einem `with`-Block ist
kein Name bewiesen (er kann an ein Member des with-Ausdrucks binden), und
der Core nimmt den RTL-Beweis zurueck, wenn die Unit selbst eine
gleichnamige Funktion ohne String-Ergebnis deklariert
(`function Trim(..): Variant`): dort buergt nur das Kompilat, und
`IntToStr(x)` bleibt als Operand stehen statt `%d` zu werden. Nachbildung
am Korpus: 83 % statt 17 %.

Bekannte Grenzen: ein Record mit Implicit-Operator (`Nullable<string>`)
uebersetzt in der Kette, aber nicht im `Format`-Aufruf - der Compiler
meldet es, Strg+Z nimmt es zurueck; ohne Typinformation fremder Units ist
das nicht erkennbar. `x.ToString` bleibt `%s` (ein eigener Integer-Helper
koennte anders formatieren); nur `IntToStr(x)` wird `%d`/`%u`. Ein
Char-Operand unbekannten Typs (`S[i]`, `Obj.Ch`) geht ohne `string()`
hinein. Eine unit-lokale Funktion, die einen Namen aus der eigenen
RTL-Liste des Moduls verdeckt (`Copy`, `ExtractFileName`, ...), erkennt
reDelphix ausserhalb von with-Bloecken nicht - das betrifft nur den Hinweis
`alle bewiesen`, umgeformt wuerde auch laut Kompilat. Die Literale werden
Token fuer Token in den Formatstring uebernommen (`#$2103` bleibt
`#$2103`, `#37` wird `%%`), Leerraum in String-Literalen eines Operanden
bleibt erhalten. Ein Kommentar sperrt nur, wenn er im ERSETZTEN Bereich
steht; `{$` in einem String-Literal sperrt nicht.

## Welcher Text gilt

* **Beschrieben** werden die Stellen auf dem **Editor-Puffer** der offenen
  Datei (`TRdxEditor.ReadBuffer` -> `TSourcePlaces.OpenSource`), auch mit
  ungespeicherten Aenderungen; ist die Datei nicht im Editor offen, auf
  der Platte wie beim Scan. Ist sie offen, ihr Puffer aber leer oder nicht
  lesbar, kommt nur der ausgegraute Eintrag `reDelphix: Editor-Puffer leer
  oder nicht lesbar` - kein stiller Rueckfall auf die Platte.
* **Geparst** wird nur, wenn sich etwas geaendert hat: die zuletzt
  geoeffnete Quelle bleibt offen (`TRdxSourceCache`), gleicher Name,
  gleiche Herkunft (Puffer/Platte) und gleicher Text heissen kein neuer
  Parse. Gelesen wird der Puffer trotzdem je Fund neu - die ToolsAPI hat
  keinen Aenderungszaehler.
* **Gegenprobe gegen den Fund:** die Fundliste kann aelter sein als der
  Puffer. Fuer SCA044 und SCA003 muss die Anweisung auf der Fundzeile das
  Ziel tragen, das die Meldung nennt, bei SCA044 auch genau so viele `+`
  wie gemeldet (`TRdxRecipeRunner.QueryOf`/`Describe`). Sonst entfallen
  die Umformungen mit dem Grund `Zeile n traegt X, der Fund nennt Y -
  Zeile verschoben? Datei neu pruefen` bzw. `Kette auf Zeile n hat a x
  '+', der Fund nennt b - Zeile veraendert? Datei neu pruefen`. Zerfaellt
  die Kette im Quelltext anders als im Parser-Knoten (zweite
  `+`-Zaehlung in `TSourcePlaces.ChainOf`), bleibt nur "Stelle zeigen",
  und `Format()` nennt `keine Zuweisung mit Kette: <Grund>`.
* **Vor dem Schreiben** prueft `TRdxEditor.ReplaceSpans` JEDEN Bereich
  einer Aktion gegen den Text, auf dem sie beim Menueaufbau beschrieben
  wurde - als Zeilen und als die Bytes, die tatsaechlich ersetzt werden
  (`uRdxBufferMath.PlanByteEdits`). Weicht einer ab (Puffer seit dem
  Oeffnen des Menues geaendert, auch ein inzwischen leerer Puffer), wird
  KEINER geschrieben, und die Meldung nennt die erste abweichende Stelle.
* **Geschrieben** wird ueber `IOTAEditWriter` mit Byte-Positionen, die aus
  demselben Puffer gerechnet sind; alle Ersetzungen einer Aktion laufen
  durch EINEN Writer - ein Strg+Z nimmt die ganze Aktion zurueck.
* **Markiert** ("Stelle zeigen") wird ueber die Cursor-API, deren Spalten
  SmallInt sind: hinter Spalte 32767 bzw. hinter 32766 Bytes einer Zeile
  ist der Eintrag ausgegraut (`Zeile zu lang fuer die Editor-Markierung`),
  hinter dem Pufferende meldet die Aktion `... liegt hinter dem Ende des
  Editor-Puffers ... - Datei neu pruefen`.
* Die Fundliste des Plugins wird nicht neu geladen - nach einer Umformung
  die Datei erneut scannen.

**Protokoll:** `%TEMP%\reDelphix.log` (und DebugView) - jeder Schritt von
Anbieter, Markieren und Ersetzen mit Quelle (Puffer/Platte, neu geparst
oder wiederverwendet), Bytes, Offsets und Gruenden. Ist die Datei vor dem
Anhaengen groesser als 1 MiB, wird sie zu `reDelphix.log.1` (ein
frueheres `.1` entfaellt) und eine neue begonnen; beide zusammen bleiben
so bei etwa 2 MB, auch wenn die Gluehbirne bei jeder Caret-Zeile fragt.
Bei einer Fehlermeldung zuerst dort nachsehen.

## Sprache und redelphix.ini

Die Texte von reDelphix - Menuetexte, Hinweise, Gruende ausgegrauter
Eintraege, Meldungen - erscheinen in der Sprache der SCA-Oberflaeche
(Entscheid E29): englische msgids ueber `uRdxText._()`, Uebersetzungen in
`i18n\de.po` und `i18n\fr.po` wie in der SCA. Uebersetzt sind bisher die
Menuetexte und ein Teil der Meldungen (Diagnosen des Anbieters,
Spaltengrenze und Pufferende im Editor); Hinweise und Gruende der Hilfen
und die uebrigen Meldungen stehen noch deutsch im Quelltext (Umstellung in
den Chargen C1..Cn).

Eigene Einstellungen stehen in `%APPDATA%\StaticCodeAnalyser\redelphix.ini`,
neben `analyser.ini`. Fehlt die Datei, legt reDelphix sie beim ersten Text
mit einer kommentierten Vorlage an (UTF-8 mit BOM, englische Kommentare,
Aufbau wie `analyser.ini`); misslingt das (Schreibschutz, Ordner nicht
anlegbar), gilt die Vorgabe - nie eine Ausnahme im Menue. Aenderungen
wirken beim naechsten Menue ohne Neustart: die Datei wird nur bei neuer
Dateizeit neu gelesen.

### `[UI]`

| Schluessel | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `Language` | String | `auto` | Sprache der reDelphix-Texte. `auto` (auch leer): wie die SCA - die Sprache, die die SCA-Oberflaeche gesetzt hat (ein Wechsel in den Optionen gilt beim naechsten Menue), vor dem ersten Analyser-Fenster `analyser.ini [UI] Language`, sonst Englisch. `en`, `de`, `fr` (jedes Kuerzel, `de-DE` -> `de`): fest; ein Kuerzel ohne Uebersetzung zeigt Englisch, Unsinn heisst Englisch. Auskommentierte Zeilen (`;Language=de`) zaehlen in beiden Dateien nie. |

Technik: `uRdxText.RdxLanguage` entscheidet bei jedem Text,
`uLocalization.TranslateTo` (SCA.Engine) uebersetzt in diese Sprache, ohne
die Sprache der SCA umzustellen - beide teilen den .po-Cache. Eine
reDelphix-Unit bindet `uRdxText` statt `uLocalization` (stuenden beide im
uses, hinge `_` an der Reihenfolge; Tests, die beide brauchen, schreiben
`uRdxText._` aus). Die Tests setzen
`SetRdxLanguageOverride('de')` (reDelphix.Test.dpr und der Runner des
FPC-Pruefstands): mit Override liest und schreibt reDelphix keine
`redelphix.ini`. Eine neue Einstellung wird mit `RdxIniValue` gelesen, in
`RDX_INI_TEMPLATE` (uRdxText) erklaert und hier in einer Tabelle unter
`` ### `[Sektion]` `` eingetragen - `tools\config_doc_gate.py` gleicht die
drei ab.

## Scope-Tabelle pflegen

```
python reDelphix\tools\gen_unitscopes.py            # Studio 23.0 (Delphi 12)
python reDelphix\tools\gen_unitscopes.py "C:\Program Files (x86)\Embarcadero\Studio\37.0"
```

Fehlt `source` oder `lib\win32\release` der Installation oder findet das
Skript keine Unit, bricht es mit Exit 2 ab und laesst die Tabelle stehen;
sonst ersetzt es sie in einem Zug. Danach `reDelphix.d12` bereinigen und
neu erzeugen (siehe "Bauen und installieren"). Eine `unitscopes.txt` neben
der BPL hat Vorrang vor der eingelinkten Ressource.

## RTL-Typliste pflegen

```
python tools\gen-rtl-types.py              # schreibt source\uRdxRtlTypes.inc neu
python tools\gen-rtl-types.py --check      # Gate: byte-genau vergleichen, nichts schreiben
python tools\gen-rtl-types.py --source 23.0=D:\pfad\source --source 37.0=E:\pfad\source
```

`source\uRdxRtlTypes.inc` (Entscheid E27) traegt die Namen aller Klassen und
Interfaces aus `<Studio>\source` von Delphi 12 (23.0) und Delphi 13 (37.0) -
der zweite Typbeweis fuer SCA126/SCA084 (`uRdxRtlTypes`, "Was die Aktionen
tun"). Das Skript liegt im SCA-Repo unter `tools\` (Repo-Wurzel); ohne
`--source` liest es die Quellen der Standardinstallation. Nach einem neuen
Delphi oder Update die Liste neu erzeugen und mit committen. `--check`
endet mit Exit 1 bei Drift (die Meldung nennt die erste abweichende Zeile
bzw. die Zeilenzahl) und mit Exit 2, wenn eine Quelle fehlt - ohne die
Delphi-Quellen laeuft das Gate nicht. Der Kopf der Datei traegt das Datum
der letzten Listenaenderung. Danach `reDelphix.d12` und `reDelphix.Test` neu
erzeugen; der FPC-Pruefstand kopiert die `.inc` je Lauf mit.

## Code-Aktionen in der IDE ausprobieren

Profil **`code-aktionen`** in `data\profile-code-aktionen.json`: nur die
Regeln, zu denen reDelphix eine Hilfe anbietet, plus `FileReadError`
(Lesefehler bleiben sichtbar). Einspielen: Analyser-Fenster ->
Profile -> **Import...** -> die Datei waehlen -> bestaetigen; danach im
Analyser das Profil `code-aktionen` waehlen und die Datei bzw. das
Projekt scannen. Gluehbirne oder Editor-Kontextmenue auf der Fundzeile:

| Regel | Fund | Erwartete Hilfe |
|---|---|---|
| SCA044 ConcatToFormat | `s := 'a' + x + 'b';` | Format() aus Verkettung bilden (fehlt System.SysUtils, kommt es in uses) |
| SCA003 SQLInjection | `Q.SQL.Text := 'SELECT * FROM t WHERE id = ' + IntToStr(Id);` | Parametrisierte Vorlage `.. WHERE id = :Id` mit `Q.ParamByName('Id').Value := Id;` (in die Zwischenablage, schreibt nichts); `'.. FROM ' + Tbl` oder DDL: ausgegraut mit Grund |
| SCA075 ExplicitTObjectInheritance | `TFoo = class(TObject)` | (TObject) entfernen |
| SCA085 FreeAndNilHint | `X.Free; X := nil;` | FreeAndNil(X) |
| SCA126 NilComparison | `if X <> nil then` | Assigned(X) |
| SCA074 AssertMessage | `Assert(X > 0);` | Bedingung als Assert-Meldung |
| SCA087 EmptyVisibilitySection | `public` direkt vor `private` | leeren Abschnitt entfernen |
| SCA139 FreeWithoutNil | `FList.Free;` (Feld, ohne `FList := nil`) | FreeAndNil(FList) |
| SCA066 EmptyArgumentList | `DoStuff();` | leere Klammern entfernen |
| SCA007 UnusedUses | ungenutzte Unit in uses | Unit aus uses entfernen (gekennzeichnet) - daneben "uses qualifizieren" im Kontextmenue |
| SCA168 DefaultCaseInCaseStatement | `case` ohne `else` | leerer else-Zweig bzw. else mit Exception (gekennzeichnet) |
| SCA101 BeginEndRequired | `if Active then DoStuff;` | Zweig in begin..end setzen |
| SCA099 IfElseBegin | `end else DoC;` | Zweig in begin..end setzen |
| SCA082 SuperfluousSemicolon | `DoStuff;;` | ueberzaehliges Semikolon entfernen |
| SCA071 UnitLevelKeywordIndent | `  implementation` | Schluesselwort an Spalte 1 setzen |
| SCA088 LegacyInitializationSection | `begin ... end.` am Ende einer Unit | begin durch initialization ersetzen |
| SCA123 CastAndFree | `TStringList(L).Free;` mit `L: TStringList` | Cast vor Free entfernen |
| SCA020 EmptyMethod | `procedure P; begin end;` | Rumpf als beabsichtigt kennzeichnen bzw. ENotImplemented ausloesen (gekennzeichnet) |
| SCA120 MissingRaise | `EFoo.Create('x');` | Exception ausloesen (gekennzeichnet) |
| SCA122 ReRaiseException | `on E: EFoo do ... raise E;` | `raise;` verwenden |
| SCA117 PublicMemberWithoutDoc | `procedure Run(A: Integer);` im public-Teil | Dokumentationsgeruest einfuegen |
| SCA197 InterfaceWithoutGuid | `IFoo = interface` ohne GUID | Neue GUID einfuegen |
| SCA149 MissingOverride | `procedure DoWork;` verdeckt `TBase.DoWork; virtual;` | `override;` anfuegen (gekennzeichnet) bzw. `reintroduce;` |
| SCA072 RedundantBoolean | `if Active = True then` (Active: Boolean) | Vergleich mit True/False entfernen |
| SCA084 AssignedAndAssignedNil | `if Assigned(Obj) and (Obj <> nil) then` | Vergleich mit nil entfernen |
| SCA098 RedundantConditional | `if Active then Result := True else Result := False;` (Result: Boolean) | Bedingung direkt an Result zuweisen |
| SCA080 RedundantJump | `Exit;` als letzte Anweisung der Routine | Ueberfluessiges Exit entfernen |
| SCA047 SelfAssignment | `FCount := FCount;` (Feld der Unit) | Selbstzuweisung von FCount entfernen |
| SCA164 UnusedRoutine | `procedure Helper; begin end;` im implementation-Teil, nirgends gerufen | Ungenutzte Routine Helper loeschen |
| SCA147 UnusedPrivateMethod | private Methode ohne Aufruf in der Unit | Ungenutzte private Methode X loeschen (danach SCA087: leeren Abschnitt entfernen) |
| SCA070 CommentedOutCode | `// X := 1;` allein zwischen Code | Auskommentierten Code loeschen |
| SCA053 UnusedLocalVar | `var Tmp: Integer;` ohne Verwendung | Ungenutzte Variable Tmp entfernen |
| SCA009 MissingFinally | `L := TStringList.Create; L.Add('a'); ShowMessage(L.Text); L.Free;` | L in einem try/finally-Block freigeben (gekennzeichnet) |
| SCA001 MemoryLeak | `L := TStringList.Create; S := TStringList.Create; try .. finally S.Free; end; L.Free;` (Variante freed-outside-finally) | L in einem try/finally-Block freigeben (gekennzeichnet); bei den anderen Varianten gesperrt mit Grund |
| SCA153 UnpairedLock | `FLocker.Lock; DoStuff; FLocker.UnLock;` | Sperre FLocker in einem try/finally-Block freigeben (gekennzeichnet) |
| SCA109 LockWithoutTryFinally | `FLock.Enter; DoWork; FLock.Leave;` | Sperre FLock in einem try/finally-Block freigeben (gekennzeichnet) |
| SCA156 GetMemWithoutFreeMem | `GetMem(P, 1024); DoStuff(P); FreeMem(P);` | Puffer P in einem try/finally-Block freigeben (gekennzeichnet) |
| SCA096 ConstructorWithoutInherited | `constructor TFoo.Create; begin FX := 0; end;` mit `TFoo = class` | inherited Create als Erstes im Konstruktor aufrufen; mit `override` an der Deklaration inherited (gekennzeichnet) |
| SCA097 DestructorWithoutInherited | `destructor TFoo.Destroy; begin FreeAndNil(FBar); end;` mit `destructor Destroy; override;` | inherited als Letztes im Destruktor aufrufen (gekennzeichnet, ausser bei direktem TObject-Erben) |
| SCA121 RoutineResultUnassigned | `function GetCount(L: TList): Integer; begin if L = nil then LogMessage('nil list'); end;` | Result mit 0 initialisieren (gekennzeichnet) |
| SCA196 ManagedResultUninit | `for I := 0 to High(A) do Result := Result + A[I];` (Result: string) | Result zuerst initialisieren: Result := '' (gekennzeichnet) |
| SCA014 MagicNumber | `if Count > 200 then` (Unit ohne FPC-Weiche, ohne Spuren aelterer Compiler) | Lokale Konstante fuer 200 einfuehren: `const MagicNr01 = 200;` davor |
| SCA165 UnusedSuppression | wirkungsloser `// noinspection`-Marker | Marker entfernen - nur bei genau einer Art und nur, wenn kein `//`-Kommentar vor der Code-Zeile sein Ziel ist, auf dem seine Art gemeldet werden kann; Mehrarten- und `All`-Marker stehen gesperrt da (unter diesem Teilprofil wirken sie vielleicht nur scheinbar nicht), ebenso ein TodoComment-/CommentedOutCode-Marker ueber einer TODO-/Kommentarzeile (SCA165 prueft nur die Code-Zeile); ein Marker einer Code-Art mit Warum-Kommentar darunter wird entfernt |
| SCA142 UnsortedUses, SCA007 UnusedUses | Fund auf einer uses-Zeile | uses: Eintraege qualifizieren (Winapi.Windows, System.SysUtils ...) - nur im Kontextmenue, nicht in der Gluehbirne: es behebt den Fund nicht |
| jede Regel ausser SCA165 | beliebig | Hier / in dieser Datei unterdruecken; Stelle zeigen (Kontextmenue) |

SCA007 laeuft nur mit eingeschaltetem uses-Check (Optionen bzw.
`[Detectors] UsesCheck=1`); SCA142 reicht fuer die uses-Hilfe. Den
Ablauf je Aktion protokolliert `%TEMP%\reDelphix.log` (`Provide ...`,
`neu geparst` / `wiederverwendet`).

## Lokale Variable einfuehren (Refactoring ohne Fund, in Arbeit)

Code-Aktion ohne Fund - seit Entscheid E26 (Nico 2026-10-13) heisst sie
**"Lokale Konstante einfuehren"**: aus dem Zahl-Literal unter dem Caret wird
`const MagicNr01 = <Literal>;` direkt ueber der Anweisung, alle gleichen
Literale der Zeile werden durch den Namen ersetzt, der Name steht danach
im Sync Edit zum Umbenennen (Variante C1h; ein Zweig ohne `begin` bekommt
`begin..end`). Eine Inline-Konstante statt der Variablen, weil keine
Typregel das Literal trifft (Kompilierprobe des Labors, Win32 D12:
`var MagicNr01 := 1` rechnete `C - MagicNr01` mit `C: Cardinal` als -1
statt 4294967295, waehlte Integer- statt ShortInt-/Byte-Ueberladungen).
Dass die untypisierte Inline-Konstante Faltung, Ueberladungswahl und die
vorzeichenlose Rechnung des Literals behaelt, ist die PRAEMISSE von E26,
noch nicht gemessen: Beleg soll Teil P6 der Kompilierprobe sein (Bau
offen, `VarNameProject\README.md`; das Protokoll vom 2026-10-11 hat nur
P1-P5). Fuer den Quick-Fix SCA014 (nur ein Vergleichswert einer
if-Bedingung) gilt sie als sicher, fuer diese Aktion (alle gleichen
Literale der Zeile, Arithmetik, Ueberladungen) entscheidet P6 (Code-Review
R4-10).

* **Stand (Bereich C, 2026-10-14; gebaut und gruen mit f42462e6):** nur Logik und Tests.
  `uRdxIntroPlan` und `uRdxIntroEdits` sind 1:1 aus dem Labor
  `VarNameProject` uebernommen (Entscheid E24: erst der im Labor
  gemessene Stand), nur umbenannt (`TVnp*` -> `TRdxIntro*`,
  `ApplyByteEdits` -> `ApplyIntroEdits`, weil `uRdxBufferMath` schon eine
  `ApplyByteEdits` hat). Stand 2026-10-14 nach dem Review F/B vom
  2026-10-13: Inline-const (E26), mehrzeilige Strings mit mehr als drei
  Quotes, Kommentargrenzen eines `begin..end`, Kopf-Fortsetzungen
  (`message`/`dispid`/`external` auf der Folgezeile), zweite `var`/`const`
  hinter einer Anweisung, asm-Block, initialization-Abschnitt, Direktive
  zwischen Zeile darueber und Anweisung fuer jeden Plan, die Zeile
  darueber ab ihrem Kommentar-Zustand, `*)` in Spalte 1, else-Arm eines
  Bedingungsausdrucks (Delphi 13), FPC-Weiche (FPC 3.2 kennt keine
  Inline-Konstante), Zeilenende je Zeile (`RowEol`, wie
  `uRdxBufferMath.BufferEol`), Vorbedingung `Plan.Ok` von `IntroduceEdits`,
  Namen jenseits von `MagicNr99`. Die Tests `uTestRdxIntro*` (fuenf
  Units, 79 Tests: Plan 15, Refuse 9, Guards 18, Edits 20, Context 17)
  stehen in reDelphix.Test und laufen im FPC-Pruefstand (Kommando unter
  "Pruefen").
  Das Package bietet die Aktion ohne Fund noch nicht an.
* **Quick-Fix SCA014 (Charge Q14, Entscheid E28):** dieselbe Logik schreibt
  die Konstante zu einem SCA014-Fund - `TargetAt` mit dem Literal der
  if-Bedingung als Caret, `IntroduceEdits` nur fuer dieses eine Literal,
  OHNE Sync-Edit-Sitzung, ueber den Schreibweg der Tabelle
  (`uRdxMagicFixes`, Zeile `fkMagicNumber` in `uRdxFixTable`; Aktionen-
  Tabelle oben).
* **Die IDE-Aktion folgt** nach dem Prototyp fuer Enter und Esc im Labor
  (E25: Esc zerstoert im Sync Edit der IDE Text, auch ohne unseren Code -
  UI-Test 2026-10-11).
* **Variante D1** (Live Template) bleibt im Labor, ebenso ihre Tests
  (`uTestVnpTemplate`).
* **Grenzen:** siehe `VarNameProject\README.md`, Abschnitt "Grenzen" (ein
  Zeilen-Leser ohne Parser - was er nicht sicher abgrenzt, lehnt er ab).
  Eigener Zeilenleser und Schreibweg bleiben bis zur Zusammenlegung mit
  `uRdxCodeMap`/`uRdxBufferMath` stehen (Bericht B, Befund 2: drei
  Kommentar-/String-Leser; ein einzelnes CR ist in `uRdxBufferMath` ein
  Zeilenende, in `uRdxIntroEdits` nicht - im Kopf von `uRdxIntroEdits`
  festgehalten).

## Pruefen

**`tests\reDelphix.Test.dproj`** (DUnitX, in der d12-Projektgruppe): prueft
den ToolsAPI-freien Teil gegen den echten Core. Die Konfigurationen Debug
und Release definieren `TESTINSIGHT`: der Lauf geht an TestInsight, der
Exit-Code ist immer 0. Einen auswertbaren Exit-Code (1 bei einem roten Test
oder einer Ausnahme im Runner) liefert nur die Konfiguration **CI** (ohne
`TESTINSIGHT`, mit `CI`: Konsole, NUnit-XML, keine Pause) - nach
`rsvars.bat` etwa `msbuild reDelphix.Test.dproj /t:Build /p:Config=CI
/p:Platform=Win32`, dann `Output\reDelphixTest\Win32 CI\reDelphix.Test.exe`
(Review R6-09; bis dahin galt `TESTINSIGHT` fuer alle Konfigurationen).
TestInsight, Konsolen-Runner und FPC-Pruefstand werten einen Test ohne
Assert als rot (`FailsOnNoAsserts`). Jede Testunit meldet ihre Fixture im
initialization-Teil mit `TDUnitX.RegisterTestFixture` an - ein Runner mit
`UseRTTI = False` (DUnitX-Vorgabe) liesse sie sonst still aus; der
FPC-Pruefstand prueft das fuer alle Units in `tests\` (Review R6-06).

* `uTestRdxRecipes` - Literal-Codec, Format()-Bau, Query-Objekt eines SQL-Ziels,
  Scope-Tabelle (auch die echte `data\unitscopes.txt`),
  uses-Schreibweise/-Sortierung/-Einfuegestelle, Kompilat-Regel
  (Operandenform, Variant-Anzeichen, RTL-Konstanten und -Funktionen,
  Herkunft der Argumente, `%d`/`%u`) - reine Textlogik.
* `uTestRdxBench` - Selbstpruefung des FPC-Pruefstands (Review R6-03):
  Unitnamen, `[Test]`/`[TestFixture]` und `Assert.AreEqual<Integer>(` in
  einem String-Literal kommen unangepasst an - 3 Tests; mit dem build.sh vor
  Charge FF alle rot, in reDelphix.Test trivial gruen.
* `uTestRdxSca044` - Ende zu Ende je Variante des Detektors SCA044:
  Parser, Detektor, `TSourcePlaces`, `uRdxRecipeRunner` - aktiv bei
  String-Lokalen/Parametern/Feldern, Char, `.ToString`, bekannten
  RTL-Aufrufen, mehrzeilig, Steuerzeichen, `%`, Anweisung in einem
  `$IFDEF`-Zweig, Member/unbekanntem Aufruf (Kompilat), `sLineBreak`,
  `IntToStr(Integer)` als `%d` und `IntToStr(Cardinal)` als `%u`,
  `X := X + ...` (auch mit `PChar(..)` als erstem Term hinter `X +`,
  Nachpruefung FB); ausgegraut mit Grund bei Integer, Variant (deklariert
  oder `.Value`), AnsiString als Ziel oder Operand, Kommentar oder
  Direktive im Bereich, SQL-Text, mehrdeutiger Zeile, nur Literalen
  hinter `X +`, Kette ohne Literal, Kette mit `Format()` darin (ein
  zweiter Lauf ueber eine umgeformte Zeile findet nichts mehr), Ziel oder
  `+`-Zahl passt nicht zum Fund; `with`-Block nur laut Kompilat;
  Idempotenz nach dem Umschreiben. uses-Ergaenzung: vorhanden
  (qualifiziert/unqualifiziert) -> nichts; fehlend -> sortiert eingefuegt,
  Schreibweise der Datei (FPC-Weiche, Punktnamen ohne Scope),
  implementation vor interface, mehrzeilige Klausel, `in`-Pfad und
  Block-Kommentar hinter dem letzten Eintrag (angehaengt), `//`-Kommentar
  (vor dem letzten), Direktive oder `$IFDEF`-Zweig (gesperrt), keine
  Klausel -> neue hinter `implementation`, Programm ohne Klausel
  (gesperrt); zweite Kette nach der ersten Umformung braucht nichts mehr.
  Die Tests wenden beide Ersetzungen auf den Text an und lassen den
  Detektor erneut laufen. Dazu die SCA003-Vorlage Ende zu Ende (Aufruf
  und Zuweisung, Tabs, Mehrdeutigkeit).
* `uTestRdxFormatGuards` - Nacharbeit Review FB an der Format()-Umformung: kein
  Literal ueber 255 Elemente (zwei Literale von je 200 Zeichen), eine kurze Kette
  bleibt EIN Literal, der Baustein `SplitLongLiteral` (Wert gleich, Teilung hinter
  einem Leerzeichen, `#`-Codes und `''` zaehlen mit, Surrogat-Paar ganz, gezaehlt
  nach UTF-8: Umlaut zwei, CJK drei, Surrogat-Paar vier; andere Formen
  unveraendert), Zeiger am Kettenanfang gesperrt bzw. mit Literal/String dahinter
  und beim Selbst-Anhaengen (`csBehindTarget`) angeboten - 10 Tests: die beiden
  Befund-Tests zu BuildFormatCall gegen 4358b769 rot, die Split-Tests pruefen den
  neuen Baustein, zwei Gegenproben (kurze Kette, Zeiger mit Literal dahinter); die
  beiden der Nachpruefung gegen 3d753de6 rot (`Split_Utf8Widths`) bzw. ueber eine
  Mutante (ohne die Ausnahme scheitert `Format_SelfAppend_PointerFirst_Allowed`).
* `uTestRdxActionRing` - der Ring, in dem der Anbieter seine
  Aktionsobjekte haelt (Besitz, Chargen, Grenzen).
* `uTestRdxBufferMath` - Zeile/Spalte -> Byte im UTF-8-Puffer mit
  Tabulator, Umlaut, Surrogatpaar und kombinierendem Zeichen (CRLF, LF,
  CR), Pruefung aller Ersetzungen einer Aktion, Spaltengrenze 32767,
  Textwahl Puffer/Platte/gesperrt, nur Pascal-Quelltext wird gelesen
  (`IsPascalSource`, Review R1-04).
* `uTestRdxSuppress` - Unterdrueck-Marker setzen und entfernen, auch in
  Block-Kommentar, mehrzeiligem String, Lizenzkopf und mit `All`.
* `uTestRdxSuppressTargets` - die Ziele eines Markers wie im Core (naechste
  nicht-leere und naechste Code-Zeile, Kommentarzeile = `//`-Zeile):
  Entfernen gesperrt ueber einer Kommentarzeile, auch ueber Leerzeilen,
  hinter Code und gestapelt, nicht ueber `{`-Zeilen, Datei-Marker und
  Dateiende; der Kreislauf "Hier unterdruecken" -> Entfernen ueber den
  Schreibweg; "Hier unterdruecken" auf einer Kommentarzeile erweitert den
  Marker ueber Leerzeilen hinweg und sperrt bei `All`/Marker hinter Code;
  beide Sperren nur fuer Arten, die auf Kommentarzeilen gemeldet werden -
  ein Marker einer Code-Art mit Warum-Kommentar wird entfernt, auch
  gestapelt, und jedes Wort der Artenliste zaehlt wie im Core (Review
  R1-01/R1-03 und Nachbesserung, 20 Tests, FPC-Pruefstand).
* `uTestRdxSuppressCore` - Drift-Waechter dazu (nur Delphi: `uSuppression`
  uebersetzt unter FPC nicht): die Ergebnisse von LineMarker/RemoveMarker
  laufen durch den ECHTEN Core (`TSuppression.CollectMarkersForScan` +
  `ApplyToFindings`) - der gesetzte Marker unterdrueckt, auch erweitert
  ueber eine Leerzeile; RemoveMarker sperrt genau dann, wenn der Core
  einen Fund ueber das Kommentar-Ziel unterdrueckt und den Marker trotzdem
  meldet (je Form); nach dem Entfernen eines Code-Art-Markers kommt kein
  Fund zurueck. Wird rot, wenn eine Core-Charge den SCA165-Fehlalarm
  behebt - dann entfaellt die Sperre (Pruefer B1-FA, 6 Tests).
* `uTestRdxCodeMap` - die Code-Sicht gegen `TDetectorUtils.ScanCodeLine`
  des Cores (Drift-Waechter), der Zustand am Zeilenanfang und die
  geteilten Laeufe der Planer (Charge R8): Klammerabgleich (`MatchClose`,
  `AfterClose`), "genau ein Token auf der Zeile" (`OneTokenOnLine`),
  end-Bilanz (`BlockEnd`), `DirectiveInLines`.
* `uTestRdxProjectUnits` - der Index der Projekt-Units fuer "uses: X ->
  Scope.X" (`TRdxProjectUnits`, Review R1-02): Module (Pfad, Endung, gross/
  klein egal), Dateien `.pas`/`.pp` im Verzeichnis, Suchpfad relativ/absolut/
  mit `..` und ohne Projektverzeichnis, Makro-Eintraege aussen vor, UNC und
  Netzlaufwerk (Attrappe ueber die Naht der Netzpfad-Regel `uRdxPaths`, seit
  Charge B2S-a) ungelesen - dann ist jede Antwort offen -, ein lokales
  Verzeichnis im Win32-Namensraum (`\\?\C:\..`, Charge B2S-a, gegen 9713942b
  rot) gelesen, auch im Suchpfad (8 Tests, FPC-Pruefstand).
* `uTestRdxPaths` - die eine Netzpfad-Regel (`uRdxPaths`, Charge B2S-a): lokal,
  UNC mit `\` und `/`, `\\?\C:\..` und `\\.\C:\..` lokal, `\\?\UNC\..` und
  `\\.\UNC\..` Netzpfad, ein Netzlaufwerk ueber die Naht (`SetRdxRemoteDriveTest`), relative
  Pfade auch dann nicht, wenn jedes Laufwerk eines waere, das echte GetDriveType an
  TEMP; dazu SCA164 mit Include (`IncludeReason`, dieselbe Kette liest die
  Includes von SCA147) und SCA014 (`FileReason`, `IncludeReason`) auf einem
  lokalen langen Pfad - beide gegen 9713942b rot ("Netzpfad"), je mit einer
  Gegenprobe, dass die Datei ueber den langen Pfad gelesen wird (10 Tests,
  FPC-Pruefstand).
* `uTestRdxQualifyUses` - die Planung von "uses: X -> Scope.X"
  (`TRdxRecipeRunner.QualifyUses`): Eintraege der Zeile, alle,
  Sortierung, FPC-Weiche, Direktiven, eigene Unit.
* `uTestRdxFixTable` - die Tabelle der einfachen Hilfen (`uRdxFixTable`,
  Charge R8): jede Zeile mit Planer, Hinweis (fest oder vom Planer) und
  Menuetext, zweiter Eintrag genau mit zweitem Menuetext, Arten eindeutig
  und gleich `Handles`; Menuetexte mit Name, Variante und Kennzeichnung;
  Einstieg ohne Fund und ohne Zeile; einer der vier Hinweise, die es erst
  seit der Tabelle gibt (SCA075, SCA074, SCA087 und SCA066 hatten bis
  Charge R8 keinen), woertlich (Charge R9). Seit Charge C0 erwarten die
  Menuetext-Tests (auch in den Detektor-Rundlaeufen) die deutschen Texte
  aus `i18n\de.po` - der Lauf steht auf `de`; `RawCaption` liefert die
  englische msgid. Seit Charge FB pinnt `ResultDefaultHint_NamesShownValue` den
  festen Hinweis von SCA121 (er nennt keinen Default(T) mehr, der Menuetext
  nennt den Wert).
* `uTestRdxText` - die Sprache der Texte (`uRdxText`, Charge C0, Entscheid
  E29): Override (de/fr/en, Kuerzel ohne Uebersetzung, Normalisierung wie
  in der SCA), `auto` ueber die gesetzte Sprache der SCA, ohne sie ueber
  `analyser.ini`, sonst Englisch; fester Wert schlaegt die SCA;
  Kommentarzeilen, Sektionen und Zeilenenden im ini-Text; die Vorlage beim
  ersten Zugriff (Ordner, BOM, woertlich); neues Lesen nur bei neuer
  Dateizeit; ein nicht anlegbarer Ordner ohne Ausnahme; mit Override bleibt
  die Platte unberuehrt - 13 Tests, in reDelphix.Test (echte
  `uLocalization`) und im FPC-Pruefstand (Stub). Die ini-Tests lenken das
  Verzeichnis nach `TEMP\rdx_c0_<GUID>` um (`SetRdxConfigDir`).
* `uTestRdxSimpleFixes` / `uTestRdxNilFix` / `uTestRdxExprFixes` /
  `uTestRdxStructFixes` / `uTestRdxBlockFixes` / `uTestRdxLineFixes` /
  `uTestRdxRaiseFixes` / `uTestRdxDeclFixes` / `uTestRdxFlowFixes` /
  `uTestRdxRoutineFixes` / `uTestRdxMethodFixes` - die
  Quick-Fixes SCA074/SCA075/SCA085/SCA087/SCA139, SCA126,
  SCA066/SCA072/SCA084, SCA007/SCA168, SCA101/SCA099,
  SCA082/SCA071/SCA088/SCA123, SCA020/SCA120/SCA122, SCA117/SCA197/SCA149,
  SCA098/SCA080/SCA047 bzw. SCA164 (samt den Bausteinen Routinengrenzen
  und Decl/Impl-Finder) und SCA147 auf Text, ohne Parser. Charge FC (Review
  R3/R6, je Befund gegen 4358b769 rot belegt): SCA066 an einer Property mit
  Prozedurtyp, SCA168 im Variantenteil eines Records, SCA122 mit neu
  zugewiesener Variable, SCA075 mit einer Spalte hinter dem Zeilenende,
  Typen in generischen Klassen (`uRdxRtlTypes`, `FieldTypeOf`); dazu die
  Gleichwertigkeit des Zeilen-Vorfilters der Fragen an die ganze Datei
  (`DeclarationQueries_LineFilter`, `FieldTypeOf_LineFilter` - fuenf
  Mutanten des Vorfilters, alle rot; seit der Nachpruefung sucht er den
  Namen als Wort ohne Kopie der Zeile: Wortgrenze an Satzzeichen und
  Kommentar-Ende, Sprung ueber Zeilen ohne Token - acht weitere Mutanten,
  alle rot). Die Nachpruefung pinnt ausserdem den Grund der On/FOn-Sperre
  von SCA066 (Feld oder Property) und die offene `(` mit Direktive vor
  einem SCA168-case (kein Variantenteil). Seit Charge B1-FD
  (Code-Review R4, je gegen 4358b769 rot) dazu: Marker hinter dem letzten
  Code bzw. `noinspection-file` im Bereich sperren (SCA164, SCA147), Include
  bzw. Unit auf einem Netzpfad ohne Plattenzugriff abgelehnt (SCA164), das
  Include vor implementation im Plan von SCA147; seit der Nachpruefung
  B1-FD (gegen 64ab9869 rot) ein `// noinspection` ueber Kopf, forward-
  Deklaration bzw. Deklaration im Klassenrumpf (SCA164, SCA147) und der
  Suchort von `{$I \datei.inc}` (IncludeSearchPath). Jede Ablehnung
  prueft auch ihren Grund (Review R6-04: ohne ihn blieb gruen, dass die
  SCA085-Sperre "Kommentar im Ausdruck" nie griff).
* `uTestRdxRoutineFixesDetector` - SCA164/SCA147 gegen die echten
  Detektoren: Fund -> Hilfe -> Fund weg, die Katalog-Beispiele (SCA147
  mit Implementierung, danach SCA087 -> genau `good`), Funde, die der
  Detektor meldet und die Hilfe ablehnt (Name als String-Literal, eine
  `.fmx` nennt die Methode). Eigene Unit, nur Delphi.
* `uTestRdxFreeGatesDetector` - die Sperren der Charge FB, die den Resolver
  brauchen, gegen die echten Detektoren (nur Delphi): SCA085 mit Zeiger auf ein
  `object` mit eigenem Free (mORMot), Klasse mit eigener Free (Pool), fremder
  P-Typ (`PEVP_PKEY`); SCA139 mit Zeiger-Alias der Unit, fremdem P-Typ,
  `const`-Parameter (ein `var`-Parameter bleibt Hilfe); SCA147/SCA164 auf einem
  Netzpfad; dazu ein Pin: ein Unit-Global, das wie ein geerbtes Member heisst,
  ist in einer Methode einer TForm-Ableitung nicht bewiesen (strenger Resolver);
  Nachpruefung: fremder Zeiger hinter einem Alias der Unit (`PMyKey = PEVP_PKEY`),
  Attribut vor dem Kopf auf derselben Zeile, `\\?\C:\..` lokal und `\\?\UNC\..`
  Netzpfad - 13 Tests. Ohne Delphi gegengeprueft: die Sperr-Funktionen woertlich unter FPC
  an denselben Fixtures (alt Hilfe, neu Sperre) und an allen 1.540
  SCA085/SCA139-Funden des Korpus.
* `uTestRdxFreeTypes` - `DeclaresValueType` mit Zeigertyp der Unit (`PX509_CRL =
  ^X509_CRL`, auch auf eine Klasse; Klasse, Alias und Feld nicht), Aliasse der
  Unit und `= type ^` (Nachpruefung) - 3 Tests, alle gegen 4358b769 rot, der
  dritte auch gegen 3d753de6.
* `uTestRdxCleanupFixes` - die Quick-Fixes SCA070/SCA053 der Charge H3a auf
  Text, ohne Parser: `//`-Zeile, Kommentar hinter Code, Inhaltszeilen eines
  Blockkommentars (leerer Rest samt Begrenzern, Prosa bleibt, Oeffner bzw.
  Schliesser bleiben), mehrere Kommentare, letzte Zeile der Datei;
  Einzeldeklaration, leer werdende Section, Gruppen (auch ueber Zeilen),
  Inline-var; jede Sperre; dazu der Baustein `CutEdit` (20 Tests).
* `uTestRdxCleanupScope` - die SCA053-Sperren der Charge H3c je mit der
  Pruefer-Fixture des Gegen-Reviews H3: Include, Direktive mit dem
  Namen und asm im Gueltigkeitsbereich, FPC-Makro in der Datei,
  Parameter in offener Klammer, Umlaut-Schreibung, Ende des
  Gueltigkeitsbereichs ueber `ReadRoutine`; dazu Charge B1-FD (Code-Review
  R4, je gegen 4358b769 rot): Inline-Deklaration mit `End := 1` dahinter
  (auch Feld bzw. globale Variable gleichen Namens) bzw. davor, Verwendung
  nur in der until-Bedingung, Marker-Kommentar hinter der Deklaration
  bleibt stehen, SCA070 am Dateiende hinter einem Surrogatpaar (unter FPC
  mit UTF-8 als Systemcodepage; die Nachbildung von PlanByteEdits lehnt
  eine Spalte mitten im Paar selbst ab, sonst trennte die Byte-Pruefung
  unter FPC nicht); Nachpruefung B1-FD (gegen 64ab9869 bzw. 4358b769 rot):
  ein `// noinspection` ueber der Deklaration sperrt, die until-Bedingung
  mit Klammerbilanz (anonyme Methode) und Halt am Listenende - 16 Tests.
* `uTestRdxCleanupDetector` - dieselben Hilfen gegen die echten Detektoren
  `uCommentedOutCode`/`uUnusedLocal` (nur Delphi): Rundlauf bis der Detektor
  schweigt, Katalog-Beispiel SCA053 `bad` -> `good`, Sperren an echten
  Funden (for var, resourcestring, Kopfkommentar, TODO, Mehrzeilenstring,
  Attribut), dazu der with-Rundlauf (with sperrt nicht). Das Katalog-Beispiel von SCA070 meldet der Detektor
  nicht (zwei benachbarte `//`-Zeilen gelten ihm als Doku-Block).
* `uTestRdxTryFixes` / `uTestRdxTryLocks` / `uTestRdxTryGates` - die Quick-Fixes try/finally der Charge H4
  (Baustein B5) auf Text, ohne Parser: die Form (Stufe zwei/vier Zeichen bzw. Tab,
  ausgerichtete Zeilen, Leerzeilen, Kommentare, `X := nil`, FreeAndNil/Destroy, B ohne `;`,
  A ueber Zeilen, Inline-var), Strukturen im Bereich, Exit und innere Schleifen,
  umschliessendes try, SCA009-Suffix, die SCA001-Form und je Sperre ein Fall; Sperren
  SCA153/SCA109 (Paare, Partner per Text, Frueh-Freigabe auch in anderer Schreibweise,
  zweite Sperre, Exit, Break, TMonitor mit Timeout bzw. TryEnter, Handler) und Puffer
  SCA156 (GetMem/AllocMem/FPC-Form, `System.`, ReallocMem, Result, Zeiger veraendert auch
  per Cast, Exit mit Weitergabe, Weitergabe ohne Ausstieg); `uTestRdxTryGates` die
  Sperren und Formen aus dem Gegen-Review H4 (Charge H4c, je Befund die Pruefer-Fixture):
  Weitergabe ohne Ausstieg (sechs schaedliche Formen abgelehnt, harmlose angeboten, Ziele
  einer Zuweisung, `@X`, Casts), raise-Ausdruck, Freigaben in anderer Schreibweise,
  Suffix und Handler, `End := 1`, gemischte Einrueckung, `SysUtils.FreeAndNil`,
  `X := nil; Foo;`, Gruende in Quelltext-Schreibweise, Surrogatpaar am Zeilenende; seit
  Charge B1-FE (Gegen-Review R5, je gegen 4358b769 rot) X in einer Huelle aus Cast, Klammern
  und `as` bei Zuweisung und Speicher-Aufruf, `System.Exit`/`System.Break`, nur lokale
  Puffer samt `P := nil` im finally, Puffer als Inline-var, `%` im Sperrtext der
  Meldung und (Nachpruefung, gegen d840f1e5 rot) Huellen beliebig tief - 20, 20 und 19
  Tests. `uTestRdxTryLocks` deklariert seitdem P und Buf als
  lokale Variablen.
* `uTestRdxTryFixesDetector` - dieselben Hilfen gegen die echten Detektoren (nur
  Delphi): Rundlauf SCA009 (auch mit Suffix - try/except im Bereich bzw. umschliessend),
  SCA001 freed-outside-finally (Variante
  aus dem Fund, gekennzeichnet, Menuetext), Katalog-Beispiele SCA153/SCA109/SCA156
  `bad` -> `good` (SCA109 ohne den Kommentar in `bad`; SCA009: `good` ist einzeilig),
  Funde, die die Hilfe ablehnt (bedingtes Free, never-freed, fremde Freigabe,
  ReallocMem) - 14 Tests; ohne Delphi gegengeprueft (CLI-Exe und FPC-Planer, 12/12; der
  Rundlauf der Charge H4c ebenso, und das SCA156-Katalogbeispiel der Charge B1-FE, das seitdem
  in einer Routine mit `var P: Pointer;` steht).
* `uTestRdxResultFixes` / `uTestRdxInheritedFixes` - die Quick-Fixes der Charge H5 auf
  Text, ohne Parser: SCA121 (Einrueckung wie die erste Anweisung bzw. eine Stufe, Tab,
  Einzeiler inline, Kommentar bzw. Direktive hinter begin, Typ aus der Deklaration,
  generisch/qualifiziert/Operator, lokale Routine; Sperren Skript/Include, FPC-Modus und
  `{$X-}`, asm, Direktive, specialize, veraltete Zeile), SCA196 (`''`/`nil`/VarClear,
  innerste Routine um die Lese-Zeile, Typbeweise; Sperren), SCA096 (TObject-Formen,
  override; Sperren Entwurf, overload, Delegation, blockierter Konstruktor, inherited im
  Text, Typarten, Kopf und Rumpf) und SCA097 (Baustein letzte Anweisung: eigene Zeile,
  fehlendes `;`, inline, leerer Rumpf, Kommentare, try als letzte Anweisung;
  Kennzeichnung nach Vorfahr; Sperren) - 17 und 17 Tests. Mutanten-Selbstpruefung: 18
  gezielte Mutanten, alle rot. Seit Charge B1-FE (Gegen-Review R5, je gegen 4358b769 rot):
  SCA097 mit fehlendem `;` hinter einem String-Literal (eigene Zeile und inline) und
  `System.Exit`/`System.Halt`/`SysUtils.Abort` als Ende, SCA196 mit lokal bzw. geschachtelt
  definiertem Typnamen und die Laufzeit von SCA096/SCA097 auf einer Unit von gut 20.000
  Zeilen (Schranke 1,5 s; 4358b769: 3,3 s, jetzt rund 0,1 s); nach der Nachpruefung (je
  gegen d840f1e5 rot) Klassenkoepfe `TGen<T: class; U>` im Index des Planerlaufs (SCA096
  Delegation und SCA097 abstrakt gesperrt, SCA097 an `TMulti<T1: class; T2: class>`
  angeboten) und SCA196 in einem Include ohne Kopf - 20 und 20 Tests.
* `uTestRdxResultGuards` - die Fixtures aus dem Gegen-Review H5 (Charge H5c), je gegen
  111fed9d rot belegt: SCA096 Delegation an einen eigenen Konstruktor ohne `Create` im
  Namen (auch aus dem Vorfahren der Unit), abstrakte geerbte Methode (auch zwei Stufen
  hoeher), `{$mode objfpc}` mit Vorfahr ausserhalb der Unit, Direktive in der
  Vorfahrenliste, qualifiziertes Interface als erster Eintrag, TPersistent/
  TInterfacedObject/TCustomAttribute; SCA097 abstrakt/objfpc, Exit und goto auf jeder
  Tiefe; SCA121 Literal statt Default(T), Typen der Unit, Sperre alter Compiler,
  Zuweisung im Rumpf; SCA196 Typdefinition der Unit - 17 Tests (drei davon Grenzen, die
  schon vorher gruen waren: Prozeduraufruf ist keine Delegation, eigenes TPersistent,
  TPersistent.Destroy bleibt gekennzeichnet). Seit Charge B1-FE (Gegen-Review R5): SCA121
  `System.Low(T)` statt eines von einem Member verdeckten ersten Werts (qualifiziert seit
  der Nachpruefung: ein `Low` der Klasse bzw. der Unit verdeckte `Low(T)`; ein eigenes
  `System` gibt `Default(T)`), Typdefinitionen nur auf Unit-Ebene, keine Hilfe bei einem
  Rueckgabetyp, den die Funktion selbst definiert, `System.Exit(Wert)`, SCA096
  `class(IFoo)` nur mit einem Interface auf Unit-Ebene - 20 Tests.
* `uTestRdxSqlTemplate` - die SQL-Vorlage zu SCA003 (Charge S1): Nicos Fall
  (`FConn.ExecSQL('CREATE TABLE ' + KONSTANTE + .. + AColumnTypes ..)`: DDL
  ausgegraut), Bezeichner-Positionen, Konstante im Text bzw. als Verkettung,
  "nur Konstanten", kein SQL-Literal, LIKE mit `'%' + X + '%'`, IN-/VALUES-Liste,
  FireDAC-Overload und Aufruf ohne Bindung, PostgreSQL-`::`, Namenskollision,
  klebende Operanden, Bruchstuecke (`S := S + ..`), LIMIT/TOP, BETWEEN - 20 Tests,
  davon 19 gegen e788e0c7 rot (die sechs alten `SqlTemplate_*` aus
  `uTestRdxRecipes` mit sprechenden Namen statt `:p1`).
* `uTestRdxSqlFacts` - ihre Nachweise am Quelltext: Konstante der Unit, der
  Routine, aus dem interface; nicht bewiesen bei Parameter/Feld/typisierter
  Konstante gleichen Namens, lokaler Konstante einer anderen Routine, Deklaration
  hinter der Verwendung; zwei Zweige; FireDAC-Verbindung (uses und Typ);
  Parameternamen; Platzhalter nach SCA199; AddSqlFacts - 16 Tests.
* `uTestRdxSqlGuards` - die Nacharbeit des Gegen-Reviews der Charge S1 (Charge SQc), die
  Fixtures des Pruefers als Tests: Inline-Variable `var X := ..`/`for var X in ..` und
  `on X: E do` verdecken die Konstante, Sichtbarkeit (lokale Konstante einer inneren
  Routine, Inline-Konstante, Klassenkonstante nur in den eigenen Methoden), der Name der
  Konstante bleibt (samt Leerzeichen vor dem Platzhalter, zerschnittene Konstante
  abgelehnt), DDL-/Block-Sperre hinter `;`, die Kette `Q.SQL.Add` (fruehere Zeile mit
  CREATE VIEW, Clear, Anweisungsart; Namen der Kette vergeben), ganze Liste in Quotes,
  Join-Bedingung, reservierte Namen und 30 Zeichen, Umlaut -> pN, `--` + sLineBreak,
  `VALUES (QuotedStr(x))`, `N'..'`, `::typ`, ADO-Parameters, LIMIT/OFFSET nur
  IntToStr, `?` - 19 Tests, alle gegen b1d16991 rot.
* `uTestRdxSqlBinds` - Nacharbeit Review FB an der SQL-Vorlage: SQL-Text ueber 255
  Elemente geteilt, Unit-Konstante in einer Methode mit fremdem Vorfahr (auch einer
  lokalen Routine, einem Helper) nicht bewiesen - in einer Klasse mit Vorfahr der
  Unit, einem Record und einer freien Routine schon -, verdoppelte Apostrophe im
  SQL-String und `AnsiQuotedStr(x, '''')` binden x, andere Maskierungen gesperrt;
  Nachpruefung: `x.QuotedString` ohne Klammern, `Trim(x).Replace(..)` bindet
  `Trim(x)`, Literale mit Apostroph (`StringReplace` ohne `rfReplaceAll`,
  `x.Replace(..).Trim`, `\'`, `Format('''%s''', ..)`), verschachtelte
  Maskierungen - 10 Tests, alle gegen 4358b769 rot, die vier der Nachpruefung
  auch gegen 3d753de6.
* `uTestRdxResultFixesDetector` - dieselben Hilfen gegen die echten Detektoren (nur
  Delphi): Rundlauf und Katalog-Beispiele (SCA097 `bad` -> genau `good`; SCA096: `good`
  zeigt `inherited;`, die Hilfe setzt bei direktem TObject-Erben `inherited Create;`;
  SCA121: `good` schreibt die Logik um - verglichen wird die Initialisierung), Menuetext
  und Kennzeichnung je Variante, die uses-Ergaenzung fuer VarClear, Ablehnungen (anderer
  Vorfahr, kein override, Skript) - 14 Tests; ohne Delphi gegengeprueft (CLI-Exe und
  FPC-Planer, 13/13).
* `uTestRdxDetectorKit` - keine Fixture: die gemeinsamen Helfer der
  Detektor-Rundlaeufe (Datei schreiben, echter Detektor auf echtem AST,
  Hilfe ueber `TRdxFixTable.FixFor`, anwenden wie der Editor, Fund fuer Fund
  bis der Detektor schweigt); bis Charge H3c je eine Kopie. Seit Charge H4
  traegt `TSeen` die Variante des Funds (SCA001). Nur Delphi.
* `uTestRdxSimpleFixesDetector` - dieselben Hilfen gegen den echten
  Detektor: nach der Hilfe meldet er nichts mehr; die Katalog-Beispiele
  `bad` werden genau `good` (SCA074 und SCA139: das `good` traegt eine
  Begruendung in Worten bzw. laesst Zeilen weg - dort wird die Ersetzung
  verglichen; SCA047: das `good` zeigt den gemeinten Wert, die Hilfe
  loescht die Zuweisung). Fixture 9 prueft dazu die Sperren des Laeufers
  fuer SCA098/SCA047 (Boolean bewiesen, Variable, with-Block). SCA085 mit
  Kommentar im Ausdruck (`FList{owned}.Free;`, `FList.{c}Free;`,
  `FList.Free {c};`): der Detektor meldet, die Hilfe nennt den Kommentar
  (Nachbesserung FF; ohne Delphi gegengeprueft: CLI-Exe und FPC-Planer 3/3).
* `uTestRdxIntroPlan` / `uTestRdxIntroRefuse` / `uTestRdxIntroGuards` /
  `uTestRdxIntroEdits` / `uTestRdxIntroContext` - "Lokale Variable
  einfuehren" (Abschnitt oben): das
  Literal am Caret, Deklaration und Spalten, Zweig ohne `begin`, alle
  Ablehnungen und Schutzregeln, Ende des Sync-Blocks und die Ersetzungen
  des Writers Ende zu Ende auf UTF-8-Pufferbytes (CRLF, LF, BOM,
  Mehrbyte-Zeichen), Kontext ueber Zeilen (mehrzeilige Strings, asm,
  initialization, FPC-Weiche, Direktiven, Kommentargrenzen) - 79 Tests, reine
  Textlogik.
* `uTestRdxMagicFix` - der Quick-Fix SCA014 der Charge Q14 auf Text, ohne Parser:
  Nicos Fall (Alcinoe ALCipher Unit1.pas:268), Einzug, Zweig mit begin..end, nur das
  Literal der Bedingung, zwei if auf einer Zeile, Nicht-ASCII davor; Ziel aus dem Fund
  (Hex/Float/Vorzeichen/Zifferntrenner, mehrdeutig auch ueber Zeilen, Folgezeile,
  veraltete Zeile, Meldung ohne Zahl), Name kollisionsfrei, Spuren alter Compiler
  (Schwelle 10.3; SCA121 bleibt bei 2009), FPC-Weiche, xEdit-Skript, Sperren der
  Code-Aktion, Lazarus-Projekt neben der Unit, Includes (FPC, alt, verschachtelt,
  fehlend) - 20 Tests; Mutanten-Selbstpruefung: 16 gezielte Mutanten, alle rot.
* `uTestRdxMagicGuards` - die Nacharbeit des Gegen-Reviews der Charge Q14 (Charge SQc):
  alte Delphi-Projektdatei (`.dof`/`.bdsproj`/`.bpr`/`.bpg`) bis zwei Ebenen ueber der
  Unit, `.dproj` mit ProjectVersion 18.4/18.5/ohne Version, das naechste Verzeichnis mit
  Delphi-Projekt entscheidet, Lazarus vor Delphi, Netzpfad, Hauptblock von program/library
  (m22 des Pruefers) - 6 Tests, alle gegen b1d16991 rot; jeder Test in einem eigenen
  Baum `TEMP\rdx_sqc_<GUID>` drei Ebenen ueber der Unit, danach abgeraeumt (Minor 14).
  Dazu 3 der Charge B1-FD (Code-Review R4, gegen 4358b769 rot): Leerzeile zwischen
  Zweigzeile und Anweisung (Ersetzung ueber PlanByteEdits angewendet, CRLF und LF),
  `End := 1` im Hauptblock, Include auf einem Netzpfad in einer lokalen Unit - 9 Tests.
* `uTestRdxMagicFixDetector` - dieselbe Hilfe gegen den echten Detektor
  `uMagicNumbers` (nur Delphi): Katalog-Beispiel (mit 42 - die 3 ist trivial),
  Nicos Fall, zwei Funde nacheinander (MagicNr02), Zweig, Menuetext/Hinweis/keine
  Kennzeichnung, mehrdeutig, Zifferntrenner (`200_000`, `200_000.5`: der Detektor
  meldet `200`, die Hilfe nennt den Fehlalarm - faellt, sobald eine Detektor-Charge
  ihn behebt), alte Compiler, Lazarus-Paket und FPC-Include ueber den Check der
  Tabelle - 10 Tests; ohne Delphi gegengeprueft (CLI-Exe und FPC-Planer, 6/6 der
  Rundlauf- und Sperrfaelle, die Trenner-Formen 2/2 in der Nachbesserung FF).

Ohne Delphi (FPC 3.2.2):

```
bash reDelphix/tools/fpc-pruefstand/build.sh uTestRdxRecipes uTestRdxBufferMath uTestRdxSuppress uTestRdxSuppressTargets uTestRdxProjectUnits uTestRdxSimpleFixes uTestRdxNilFix uTestRdxCodeMap uTestRdxExprFixes uTestRdxStructFixes uTestRdxBlockFixes uTestRdxLineFixes uTestRdxRaiseFixes uTestRdxDeclFixes uTestRdxFlowFixes uTestRdxRoutineFixes uTestRdxMethodFixes uTestRdxCleanupFixes uTestRdxCleanupScope uTestRdxTryFixes uTestRdxTryLocks uTestRdxResultFixes uTestRdxInheritedFixes uTestRdxResultGuards uTestRdxTryGates uTestRdxIntroPlan uTestRdxIntroRefuse uTestRdxIntroGuards uTestRdxIntroEdits uTestRdxIntroContext uTestRdxMagicFix uTestRdxSqlTemplate uTestRdxSqlFacts uTestRdxSqlGuards uTestRdxMagicGuards uTestRdxText uTestRdxBench uTestRdxFormatGuards uTestRdxSqlBinds uTestRdxFreeTypes uTestRdxPaths
```

Erwartet (Stand 2026-10-15, Chargen H5+H4c+H5c+S1+Q14+SQc+C0+B1-FA+FB+FC+B1-FD+B1-FE+FF+B2S-a): `PASSED 642  FAILED 0` - 41 Testunits,
davon 11 der Charge B2S-a (`uTestRdxPaths` 10, `uTestRdxProjectUnits` 1),
28 der Charge B1-FA (`uTestRdxSuppressTargets` 20, Review R1-01/R1-03
und Nachbesserung; `uTestRdxBufferMath` 1, R1-04; `uTestRdxProjectUnits` 7,
R1-02),
13 der Charge C0 (`uTestRdxText`, Sprache der Texte),
23 der Charge FB (`uTestRdxFormatGuards` 10, `uTestRdxSqlBinds` 10, `uTestRdxFreeTypes` 3),
6 der Charge FC
(`uTestRdxExprFixes` 2, `uTestRdxNilFix` 2, `uTestRdxStructFixes` 1, `uTestRdxRaiseFixes` 1),
15 der Charge B1-FD
(`uTestRdxCleanupScope` 7, `uTestRdxMagicGuards` 3, `uTestRdxRoutineFixes` 2,
`uTestRdxMethodFixes` 3; 3 davon aus der Nachpruefung),
15 der Charge B1-FE (Gegen-Review R5 und Nachpruefung: `uTestRdxTryGates` 6,
`uTestRdxInheritedFixes` 3, `uTestRdxResultGuards` 3, `uTestRdxResultFixes` 3),
3 der Charge FF (`uTestRdxBench`, Selbstpruefung des Pruefstands),
79 Tests fuer "Lokale Variable einfuehren", 12 fuer die Quick-Fixes der
Charge H2, 25 der Charge H3b (SCA164 und Bausteine 13 in
`uTestRdxRoutineFixes`, SCA147 12 in `uTestRdxMethodFixes`), 18 der
Charge H3c (SCA164 5 in `uTestRdxRoutineFixes`, SCA147 4 in
`uTestRdxMethodFixes`, SCA053 9 in `uTestRdxCleanupScope`), 7 der Charge R8 (6 fuer die geteilten Laeufe in
`uTestRdxCodeMap`, 1 fuer den Fremdtyp-Beweis von SCA126 in `uTestRdxNilFix`),
1 der Charge R9 (SCA085: `{$` hinter `//` ist keine Direktive, in
`uTestRdxSimpleFixes`) und 2 der Charge R10 (E27: Klassen der Delphi-Quellen
als Beweis fuer SCA126, `uRdxRtlTypes`, in `uTestRdxNilFix`), 20 der
Charge H3a (`uTestRdxCleanupFixes`), 37 der Charge H4 (`uTestRdxTryFixes` 20,
`uTestRdxTryLocks` 17), 34 der Charge H5 (`uTestRdxResultFixes` 17,
`uTestRdxInheritedFixes` 17), 17 der Charge H4c (`uTestRdxTryGates` 13,
`uTestRdxTryLocks` 3, `uTestRdxCodeMap` 1 fuer TokBefore/TokText/IsKeywordAt), 17
der Charge H5c (`uTestRdxResultGuards`), 36 der Charge S1 (`uTestRdxSqlTemplate` 20,
`uTestRdxSqlFacts` 16; die sechs SQL-Vorlagen-Tests aus `uTestRdxRecipes` sind dorthin
umgezogen), 20 der Charge Q14 (`uTestRdxMagicFix`) und 25 der Charge SQc
(`uTestRdxSqlGuards` 19, `uTestRdxMagicGuards` 6).

Der Pruefstand uebersetzt die Core-Units des Quellstellen-Dienstes
(`uRefactor*`, `uSourcePlaces`, `uFindingActions`, `ScanCodeLine` aus
`uDetectorUtils`) mit Stubs fuer Parser und Resolver sowie die Textlogik
des Moduls (`uRdxRecipes`, `uRdxPaths`, `uRdxScopeTable` samt `TRdxProjectUnits`, `uRdxBufferMath`,
`uRdxSuppress`, `uRdxSimpleFixes`, `uRdxRtlTypes` samt der erzeugten
`uRdxRtlTypes.inc`, `uRdxStructFixes`, `uRdxLineFixes`, `uRdxRaiseFixes`,
`uRdxDeclFixes`, `uRdxFlowFixes`, `uRdxRoutineFixes`, `uRdxCleanupFixes`, `uRdxTryFixes`,
`uRdxResultFixes`, `uRdxSqlTemplate`, `uRdxCompilerTraces`, `uRdxMagicFixes`,
`uRdxCodeMap`,
`uRdxIntroPlan`, `uRdxIntroEdits`, `uRdxText`). Testunits kommen aus `reDelphix\tests`,
sonst aus `StaticCodeAnalyserForm\tests` (Core-Tests wie
`uTestSourcePlaces`, `uTestRefactorConcat`).

* **Sprache (Charge C0):** der Runner setzt `SetRdxLanguageOverride('de')`
  vor den Tests, wie `reDelphix.Test.dpr`. Die echte `uLocalization`
  uebersetzt unter FPC 3.2.2 nicht (TMonitor fehlt, TStringBuilder ist dort
  ein AnsiString-Bauer, kein `string.Split` fuer UnicodeString); an ihrer
  Stelle steht der eingecheckte Stub `tools\fpc-pruefstand\uLocalization.pas`
  (nur SetLanguage, CurrentLanguage, NormalizeLangCode, TranslateTo, eigener
  kleiner .po-Leser, bewusst kein `_()`). Das Skript kopiert je Lauf die
  echten `i18n\*.po` nach `out\i18n\` neben den Runner - eine deutsche
  Erwartung prueft so zugleich, dass ihre msgid in `i18n\de.po` steht.
  (`out\` liegt im Arbeitsverzeichnis des Laufs, s. u.)

* **Pfadregel:** die SCA-Wurzel ist der Checkout, in dem das Skript liegt
  (das Verzeichnis ueber `reDelphix`) - Core, Rezepte und Tests kommen so
  immer aus EINEM Stand, auch in einem Worktree oder zweiten Klon.
  `SCA_ROOT=<pfad>` ueberschreibt das bewusst. Die erste Zeile des Laufs
  nennt beide Wurzeln mit Branch und Commit.
* **Arbeitsverzeichnis (Review R6-02):** jeder Lauf kopiert, erzeugt und
  baut in einem eigenen Verzeichnis unter `TMPDIR` (Kopien, Stubs,
  `runner.pas`, `out\`) und loescht es danach; die erste Zeile nennt es.
  Zwei Laeufe im selben Checkout stoeren sich nicht mehr - bis dahin
  loeschte ein zweiter Lauf die Kopien des ersten, und der meldete fremde
  Tests als eigenes Gruen (oder scheiterte an einem halb geschriebenen
  `runner.pas`). Ein `TMPDIR` im Windows-Stil (`C:\Users\..`) wird zum
  POSIX-Pfad - awk las die Backslashes darin als Escapes und brach ab
  (Nachbesserung FF). `PRUEFSTAND_DIR=<pfad>` nimmt ein eigenes Verzeichnis
  und laesst es stehen - fuer einen Korpus-Harness, der gegen die
  angepassten Units baut; das Skript verwaltet es ganz (Marke `.pruefstand`;
  ein fremdes, nicht leeres Verzeichnis lehnt es ab). Ein Harness baut so,
  je Bau mit einem leeren `-FU`-Verzeichnis:

  ```
  PRUEFSTAND_DIR=<eigen> bash reDelphix/tools/fpc-pruefstand/build.sh uTestRdxCodeMap
  fpc -Mdelphiunicode -Fu<eigen> -FU<frisch> -FE<frisch> harness.pas
  ```

  Neben dem Skript liegen keine Kopien mehr (bis Charge FF lagen sie dort),
  sondern je kopierter Unit ein **Grabstein** (`<unit>.pas` mit
  `{$FATAL ...}`, von denselben `.gitignore`-Mustern erfasst wie die
  Kopien): ein Harness nach altem Muster (`-Fu<Skriptverzeichnis>` und ein
  bleibendes `-FU`) bricht daran mit dem Hinweis auf `PRUEFSTAND_DIR` ab.
  Ohne Grabstein naehme FPC zu einer `.ppu`, deren Quelle es nicht mehr
  findet, still die alte - auch mit `-B` -, und der Harness pruefte alten
  Planer-Code (Nachbesserung FF). Der Runner selbst laeuft im
  Skriptverzeichnis: Tests suchen Daten des Checkouts von dort aus
  (`data\unitscopes.txt`).
* **Anpassung fuer FPC 3.2.2 (Review R6-03):** `System.SysUtils` ->
  `SysUtils` und die anderen Unitnamen, `Assert.AreEqual<Integer>(` ->
  `Assert.AreEqualInt(`, `[TestFixture]`/`[Test]` am Zeilenanfang weg - nur
  AUSSERHALB von String-Literalen. Ein Test, der einen qualifizierten
  Unitnamen oder ein Attribut als Text prueft, sieht unter FPC dieselben
  Daten wie unter Delphi (bis dahin wurde aus `'System.Classes'` im Literal
  `'Classes'` und aus `'    [Test]'` eine Leerzeile; `uTestRdxBench` haelt
  das fest).
* Eine fehlende Pflichtquelle oder Testunit bricht ab, statt still eine
  alte Kopie zu uebersetzen.
* **Exit:** 0 alle Tests gruen; 1 Test rot (auch ein Test ohne Assert),
  Bau gescheitert (der FPC-Exit zaehlt) oder der Lauf zaehlt nicht genau so
  viele Tests, wie die Testunits `[Test]`-Attribute tragen (Review R6-02);
  2 Aufruf- oder Quellfehler, auch wenn die Zahl der `[Test]`-Attribute
  einer Testunit nicht zur Zahl der erkannten Testmethoden passt oder eine
  Testunit - aufgerufen oder in `reDelphix\tests` - eine Fixture nicht mit
  `TDUnitX.RegisterTestFixture` anmeldet (Review R6-06).
* **Selbsttest** der Regeln oben an kleinen Laeufen (zwei Laeufe zugleich,
  FPC-Exit, fehlende Suite, Registrierung, Test ohne Assert,
  `PRUEFSTAND_DIR`, Harness nach altem Muster mit und ohne `-B`, `TMPDIR`
  mit Backslashes); das build.sh vor Charge FF besteht keine der elf
  Pruefungen, das des ersten Durchgangs der Charge die letzten drei nicht:

  ```
  bash reDelphix/tools/fpc-pruefstand/selftest.sh
  ```

`uRdxEditor` und `uRdxProvider` sind ToolsAPI und nur im Package
uebersetzbar; `uRdxRecipeRunner` ist der testbare Kern dazwischen (in
reDelphix.Test, nicht im FPC-Pruefstand).

**Doku der Quick-Fixes** (`QUICKFIXES.md`, Entscheid E30), ohne Delphi
(Repo-Wurzel; auch in der CI, `.github/workflows/quickfix-doc.yml`):

```
python tools/gen-quickfix-doc.py --check
python tools/gen-quickfix-doc.py --selftest
```

`--check` meldet KONSISTENZ (Exit 1), wenn eine Zeile in `FIX_ROWS` oder ein
Rezept des Anbieters keinen Eintrag in `data\quickfixes-doc.json` hat (oder
ein Eintrag keine Hilfe), eine Regel mit `editorHelp` im Katalog keine Hilfe
hat oder ein Pflichtfeld fehlt, und DRIFT mit der ersten abweichenden
Zeile, wenn die Datei nicht mehr byte-gleich neu erzeugt waere. Eine
fehlende Uebersetzung ist kein Fehler: sie steht als `(fehlt)` in der
Datei. `--selftest` belegt an Mutanten (auch am Quelltext: neue Zeile in
`FIX_ROWS`, neues Rezept), dass das Gate rot wird. Nach einer neuen Hilfe,
einem geaenderten Menuetext oder einer geaenderten Uebersetzung:
`python tools/gen-quickfix-doc.py` und `QUICKFIXES.md` mit committen.

## Korpus-Probe

**`tools\probe\RdxCorpusProbe.dproj`** (Konsole, in der d12-Projektgruppe)
faehrt Rezept 5.1 ueber eine Liste von Fundstellen (`Datei<TAB>Zeile`)
und schreibt je Stelle eine CSV-Zeile plus eine Zusammenfassung mit den
Gruenden - der echte Weg des Moduls ohne ToolsAPI, also die echten Zahlen
zu jeder Regelaenderung. Eine Ausnahme kostet nur die betroffene Datei
bzw. Stelle (Kategorie `Parser: <Klasse>` bzw. `Ausnahme: <Klasse>`), nie
den Lauf; ein Pfad mit `;` steht in der CSV in Anfuehrungszeichen. Die
Liste kommt aus einem SARIF-Referenzlauf:

```
python reDelphix\tools\probe\sites_from_sarif.py rw137_ae.sarif SCA044 D:\git-sca-realworld sites.txt
python reDelphix\tools\probe\sites_from_sarif.py rw137_ae.sarif SCA044 D:\git-sca-realworld sample.txt 200 44
Output\RdxCorpusProbe\Win32 Release\RdxCorpusProbe.exe sites.txt probe.csv
```

Die zweite Form zieht eine reproduzierbare Stichprobe (N, seed). Die
Korpuswurzel ersetzt die `uriBaseId` des Laufs. `sites_from_sarif.py`
dekodiert die uri, wie der SARIF-Export sie kodiert: Prozent-Kodierung
(`%20`, `%25`, `%23`, `%3F`) wird aufgeloest, `file:///C:/...`- und
`file://server/...`-uris (Dateien ausserhalb der Scanwurzel) bleiben
absolut, fuer sie gilt die Korpuswurzel nicht. Stellen, deren Datei es
nicht gibt, meldet das Skript am Ende als `WARNUNG: n Stellen: Datei
fehlt` - ein falscher Wurzelpfad faellt so sofort auf, statt nur die
Aktiv-Quote der Probe zu druecken. Exit 2 bei falschem Aufruf, nicht
lesbarer Eingabe oder nicht schreibbarer Ausgabe. Die Python-Nachbildung
der Regeln (Audit 2026-10-06) ist eine Obergrenze; was zaehlt, ist die
Probe.

## Grenzen (Stand 2026-10-15)

* Nur Delphi 12 / Win32. Fuer Delphi 13 (64-Bit-IDE) braucht es ein zweites
  Paket mit Win64-Ziel.
* Die Scope-Aufloesung bildet die VORGABE-Listen der Unit-Scopes nach; ein
  Projekt mit eigener `DCC_Namespace`-Liste wird nicht gelesen. Wo die
  Reihenfolge System/Vcl entscheiden wuerde (heute nur `Skia`), wird
  deshalb nicht geraten.
* Delphi-12-Mehrzeilen-Literale (`'''`) kennt der Literal-Codec nicht; eine
  Anweisung mit einem solchen Literal beschreibt der Core gar nicht, es
  gibt dort also keine Umformung.
* In einem `with`-Block gilt kein Name als bewiesen (Kompilat-Regel oben),
  und jede Hilfe, die einen Namen der Unit zuordnet, sperrt dort (er
  koennte ein Member des with-Ausdrucks sein): `FreeAndNil(X)` (SCA085,
  SCA139), Assert-Meldung (SCA074), `Assigned()` (SCA126), leere Klammern
  (SCA066), Vergleich mit True/False bzw. nil (SCA072, SCA084), Cast vor
  `Free` (SCA123), Bedingung zuweisen (SCA098), Selbstzuweisung (SCA047).
  SCA053 sperrt dort nicht: der Name kommt im Bereich nicht vor, ein `with`
  kann ihn nicht binden.
* "uses: X -> Scope.X" kennt nur die Units des PROJEKTS (Datei neben der
  Unit, Module der Gruppe, Unit-Suchpfad ohne Makro-Eintraege). Bringt eine
  Bibliothek im Bibliotheks- oder Browsing-Pfad der IDE oder hinter einem
  `$(..)`-Eintrag des Projekts (`$(DMVC)`, `$(DUnitX)`, `$(Kastri)` ...) eine
  Unit mit dem Kurznamen einer RTL-Unit mit (JEDI-DirectX `Direct3D9`,
  `pngimage`, die alte Borland-`ZLib`; im Korpus 54 Dateien mit 45 solchen
  Namen), wird der Eintrag trotzdem angeboten - der Compiler faende vorher
  die Bibliothek. Offen (Review R1-07, ohne IDE nicht entscheidbar): ein
  IDE-Test mit einer Bibliothek nur im Library Path und eine Uebersetzung
  vor und nach dem Umbau; dann den Pfad der IDE in `TRdxProjectUnits`
  aufnehmen (Netzpfade wie dort gesperrt).
* "Stelle zeigen" nimmt Cursor, Block und Spaltenumrechnung seit Review
  R1-06 aus EINER Ansicht (der obersten des Puffers, sonst der ersten);
  bis dahin kam der Cursor aus der obersten, der Block aus der ersten. Mit
  einem Editorfenster ist das dieselbe Ansicht wie vorher; mit zwei
  Fenstern auf derselben Unit (View > New Edit Window) ist es ungetestet.
  IDE-Test: Unit in zwei Editorfenstern, das zweite vorn, "Stelle zeigen"
  aus dem Dock-Grid - erwartet ist die Markierung im vorderen Fenster an
  der Fundstelle (bis R1-06 begann sie dort an der Cursorstelle des
  ersten Fensters).
* Der Unit-Suchpfad der Gegenprobe ("uses: X -> Scope.X") ist gegen die
  ToolsAPI von Delphi 12 und 13 geschrieben und gegen eine Attrappe
  geprueft, in der IDE aber ungetestet: gelesen wird jede Ebene einzeln
  (aktive Konfiguration bis Base, je fuer alle Plattformen und die aktive)
  und der geerbte Wert der Plattform-Konfiguration - so findet die
  Gegenprobe einen Pfad in `Base_Win32` auch dann, wenn die geerbten Werte
  der IDE ihn nicht einschliessen (ungeprueft). Nach einer Plattform wird
  nur gefragt, wenn sie in `Platforms` steht. IDE-Test: Projekt mit einer
  Unit `Types.pas` in einem Verzeichnis, das NUR unter "Alle
  Konfigurationen - Windows 32 Bit" im Suchpfad steht, eine Unit mit `uses
  Types` - erwartet: der Eintrag fuer `Types` steht gesperrt da ("eigene
  Unit Types im Projekt") statt "uses: Types -> System.Types".
