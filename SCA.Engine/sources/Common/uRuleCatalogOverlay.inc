// ==========================================================================
// GENERIERT von tools/gen-rules-inc.py - NICHT VON HAND EDITIEREN.
// Quelle: rules/sca-rules.<lang>.json (dort aendern, Generator laufen lassen)
//
// Einkompilierte Sprach-Overlays (Name, ShortDescription und
// FullDescription je Regel; leer = englischer Rueckfall).
// Rangfolge im Leser (TRuleCatalog.EnsureOverlay): lose Datei schlaegt
// diese Tabelle; die Tabelle schlaegt Englisch.
// ==========================================================================

const
  // Index == Ord(TFindingKind), Drift-Guard im Leser wie bei
  // RULE_CATALOG_DATA (RuleID muss zur Position passen).
  RULE_OVERLAY_DE : array[0..204] of TRuleOverlayData = (
    // SCA001
    (
      RuleID   : 'SCA001';
      Name     : 'Objekt ohne ausnahmesichere Freigabe erzeugt';
      ShortDesc: 'Objekt erzeugt, aber nicht zuverl' + #$00E4 + 'ssig freigegeben (m' + #$00F6 +
        'gliches Speicherleck)';
      FullDesc : ''
    ),
    // SCA002
    (
      RuleID   : 'SCA002';
      Name     : 'Leerer except-Block';
      ShortDesc: 'Leerer except-Block schluckt jede Exception ohne Reaktion';
      FullDesc : ''
    ),
    // SCA003
    (
      RuleID   : 'SCA003';
      Name     : 'SQL-String per Verkettung gebaut';
      ShortDesc: 'SQL-String mit ''+'' aus beeinflussbarer Eingabe zusammengesetzt (Injection-Risiko)';
      FullDesc : ''
    ),
    // SCA004
    (
      RuleID   : 'SCA004';
      Name     : 'Hartkodierte Zugangsdaten / API-Token';
      ShortDesc: 'Passwort, API-Schl' + #$00FC + 'ssel oder Token als String-Literal im Quelltext';
      FullDesc : ''
    ),
    // SCA005
    (
      RuleID   : 'SCA005';
      Name     : 'Format(): Platzhalterzahl passt nicht';
      ShortDesc: 'Zahl der Platzhalter in Format() / FormatUtf8() weicht von der Zahl der Argumente ab';
      FullDesc : ''
    ),
    // SCA006
    (
      RuleID   : 'SCA006';
      Name     : 'Datei konnte nicht gelesen oder geparst werden';
      ShortDesc: 'Parser-/IO-Fehler - Quelldatei unlesbar oder syntaktisch defekt';
      FullDesc : ''
    ),
    // SCA007
    (
      RuleID   : 'SCA007';
      Name     : 'Ungenutzte Unit in der uses-Klausel';
      ShortDesc: 'uses-Eintrag vermutlich ungenutzt (kein Bezeichner daraus wird referenziert)';
      FullDesc : ''
    ),
    // SCA008
    (
      RuleID   : 'SCA008';
      Name     : 'M' + #$00F6 + 'gliche nil-Dereferenzierung';
      ShortDesc: 'Zugriff auf eine Variable, die an dieser Stelle nil sein kann';
      FullDesc : ''
    ),
    // SCA009
    (
      RuleID   : 'SCA009';
      Name     : 'Objekt ohne sch' + #$00FC + 'tzendes try/finally erzeugt';
      ShortDesc: '.Create ohne umschlie' + #$00DF + 'endes try/finally - Leck-Risiko im Ausnahmefall';
      FullDesc : ''
    ),
    // SCA010
    (
      RuleID   : 'SCA010';
      Name     : 'M' + #$00F6 + 'gliche Division durch null';
      ShortDesc: 'Ganzzahl-Division (div / mod) durch eine Variable, die null sein kann';
      FullDesc : ''
    ),
    // SCA011
    (
      RuleID   : 'SCA011';
      Name     : 'Code nach Exit/Raise ist unerreichbar';
      ShortDesc: 'Anweisung nach Exit, raise oder Halt ist toter Code';
      FullDesc : ''
    ),
    // SCA012
    (
      RuleID   : 'SCA012';
      Name     : 'Methode ' + #$00FC + 'berschreitet die Zeilengrenze';
      ShortDesc: 'Methodenrumpf l' + #$00E4 +
        'nger als das konfigurierte Maximum (Vorgabe: mehr als 50 Zeilen und mehr als 30 Anweisungen)';
      FullDesc : ''
    ),
    // SCA013
    (
      RuleID   : 'SCA013';
      Name     : 'Zu viele Parameter';
      ShortDesc: 'Methode hat mehr Parameter als konfiguriert erlaubt (Vorgabe 5)';
      FullDesc : ''
    ),
    // SCA014
    (
      RuleID   : 'SCA014';
      Name     : 'Zahlenliteral ohne benannte Konstante';
      ShortDesc: 'Zahlenliteral im Ausdruck - in eine benannte Konstante herausziehen';
      FullDesc : ''
    ),
    // SCA015
    (
      RuleID   : 'SCA015';
      Name     : 'String-Literal an mehreren Stellen wiederholt';
      ShortDesc: 'Dasselbe String-Literal kommt in einer Datei dreimal oder ' + #$00F6 +
        'fter vor - in eine Konstante herausziehen';
      FullDesc : ''
    ),
    // SCA016
    (
      RuleID   : 'SCA016';
      Name     : 'Dateisystempfad als String-Literal';
      ShortDesc: 'Hartkodierter C:\-, UNC- oder Linux-Pfad im Quelltext';
      FullDesc : ''
    ),
    // SCA017
    (
      RuleID   : 'SCA017';
      Name     : 'WriteLn/ShowMessage im Produktivcode';
      ShortDesc: 'Debug-Ausgabe in einer Produktiv-Unit gefunden';
      FullDesc : ''
    ),
    // SCA018
    (
      RuleID   : 'SCA018';
      Name     : 'Blockverschachtelung ' + #$00FC + 'berschreitet die Grenze';
      ShortDesc: 'Verschachtelungstiefe von if/for/while h' + #$00F6 + 'her als konfiguriert (Vorgabe 4)';
      FullDesc : ''
    ),
    // SCA019
    (
      RuleID   : 'SCA019';
      Name     : 'TODO/FIXME-Marker im Kommentar';
      ShortDesc: 'Offener TODO-, FIXME-, HACK- oder XXX-Marker - vor dem Release aufl' + #$00F6 + 'sen';
      FullDesc : ''
    ),
    // SCA020
    (
      RuleID   : 'SCA020';
      Name     : 'Leerer Methodenrumpf';
      ShortDesc: 'Methodenrumpf enth' + #$00E4 + 'lt keine Anweisung';
      FullDesc : ''
    ),
    // SCA021
    (
      RuleID   : 'SCA021';
      Name     : 'Duplizierter Codeblock';
      ShortDesc: 'Mehrere identische Codebl' + #$00F6 + 'cke (ab der konfigurierten Mindestzeilenzahl)';
      FullDesc : ''
    ),
    // SCA022
    (
      RuleID   : 'SCA022';
      Name     : 'Methode ' + #$00FC + 'berschreitet die McCabe-Komplexit' + #$00E4 + 't';
      ShortDesc: 'Zyklomatische Komplexit' + #$00E4 + 't ' + #$00FC +
        'ber der konfigurierten Schwelle (Vorgabe 10)';
      FullDesc : ''
    ),
    // SCA023
    (
      RuleID   : 'SCA023';
      Name     : 'Selbst definierte Regel';
      ShortDesc: 'Muster aus einer Regel getroffen, die aus analyser-rules.yml geladen wurde';
      FullDesc : ''
    ),
    // SCA024
    (
      RuleID   : 'SCA024';
      Name     : 'Komponente mit Vorgabenamen';
      ShortDesc: 'Komponente tr' + #$00E4 +
        'gt noch den Assistenten-Vorgabenamen (Button1, Edit3, Panel2 ...)';
      FullDesc : ''
    ),
    // SCA025
    (
      RuleID   : 'SCA025';
      Name     : 'Hartkodierter UI-Text im DFM';
      ShortDesc: 'Caption, Hint oder Text als Literal im DFM statt ' + #$00FC + 'ber die i18n-Schicht';
      FullDesc : ''
    ),
    // SCA026
    (
      RuleID   : 'SCA026';
      Name     : 'Hartkodierte DB-Zugangsdaten im DFM';
      ShortDesc: 'Klartext-Password oder ConnectionString mit Pwd= an einer DB-Komponente';
      FullDesc : ''
    ),
    // SCA027
    (
      RuleID   : 'SCA027';
      Name     : 'Doppelte (DataSource, DataField)-Bindung';
      ShortDesc: 'Zwei oder mehr Controls binden dasselbe Paar aus DataSource und DataField';
      FullDesc : ''
    ),
    // SCA028
    (
      RuleID   : 'SCA028';
      Name     : 'DFM-Ereignisbehandler zeigt auf fehlende Methode';
      ShortDesc: 'OnClick / On... verweist auf eine Methode, die es in der Formularklasse nicht gibt';
      FullDesc : ''
    ),
    // SCA029
    (
      RuleID   : 'SCA029';
      Name     : 'Verwaister Ereignisbehandler';
      ShortDesc: 'Published-Methode in TNotifyEvent-Form hat keine DFM-Bindung';
      FullDesc : ''
    ),
    // SCA030
    (
      RuleID   : 'SCA030';
      Name     : 'Leerer gebundener Ereignisbehandler';
      ShortDesc: 'Ereignis ist im DFM verdrahtet, die Methode existiert, der Rumpf ist leer';
      FullDesc : ''
    ),
    // SCA031
    (
      RuleID   : 'SCA031';
      Name     : 'DFM-Komponente ohne published-Feld';
      ShortDesc: 'Komponente im DFM hat kein passendes published-Feld in der Formularklasse - veralteter DFM-Eintrag (Schema-Drift)';
      FullDesc : ''
    ),
    // SCA032
    (
      RuleID   : 'SCA032';
      Name     : 'Zyklische DataSource-/Master-Detail-Schleife';
      ShortDesc: 'Zyklus in den Kanten DataSource.DataSet / DataSet.MasterSource';
      FullDesc : ''
    ),
    // SCA033
    (
      RuleID   : 'SCA033';
      Name     : 'SQL-Property aus UI-Eingabe gebaut';
      ShortDesc: 'Query.SQL aus Text- oder Caption-Properties von Formular-Controls zusammengesetzt';
      FullDesc : ''
    ),
    // SCA034
    (
      RuleID   : 'SCA034';
      Name     : 'Pflichtfeld ohne UI-Bindung';
      ShortDesc: 'TField mit Required=True hat kein gebundenes Eingabe-Control';
      FullDesc : ''
    ),
    // SCA035
    (
      RuleID   : 'SCA035';
      Name     : 'Pflichtfeld nur an unsichtbaren Controls';
      ShortDesc: 'TField mit Required=True ist nur an Controls mit Visible=False gebunden';
      FullDesc : ''
    ),
    // SCA036
    (
      RuleID   : 'SCA036';
      Name     : 'UI-Control passt nicht zum TField-Typ';
      ShortDesc: 'Klasse des DB-Controls passt nicht zu TField.DataType (TDBEdit f' + #$00FC +
        'r ein TBooleanField)';
      FullDesc : ''
    ),
    // SCA037
    (
      RuleID   : 'SCA037';
      Name     : 'Doppelte TabOrder unter Geschwistern';
      ShortDesc: 'Zwei Geschwister-Controls im selben Parent teilen sich denselben TabOrder-Wert';
      FullDesc : ''
    ),
    // SCA038
    (
      RuleID   : 'SCA038';
      Name     : 'Komponente nutzt eine verbotene Klasse';
      ShortDesc: 'Komponentenklasse steht auf der ForbiddenClasses-Liste des Projekts';
      FullDesc : ''
    ),
    // SCA039
    (
      RuleID   : 'SCA039';
      Name     : 'DB-Komponente auf einem UI-Formular';
      ShortDesc: 'TFDQuery / TFDConnection direkt auf einem TForm oder TFrame statt in einem DataModule';
      FullDesc : ''
    ),
    // SCA040
    (
      RuleID   : 'SCA040';
      Name     : 'Formular' + #$00FC + 'bergreifender Feldzugriff';
      ShortDesc: 'Code in Form1 liest oder schreibt Form2.<published_field> direkt';
      FullDesc : ''
    ),
    // SCA041
    (
      RuleID   : 'SCA041';
      Name     : 'Eingabe-Control direkt auf dem TForm';
      ShortDesc: 'Eingabe-Control sitzt auf dem Formular, statt in einem TPanel oder TGroupBox eingebettet zu sein';
      FullDesc : ''
    ),
    // SCA042
    (
      RuleID   : 'SCA042';
      Name     : 'Ereignisbehandler mit zu vielen Bindungen';
      ShortDesc: 'Eine einzelne Methode h' + #$00E4 +
        'ngt an N oder mehr Komponenten-Ereignissen (Vorgabe N=5)';
      FullDesc : ''
    ),
    // SCA043
    (
      RuleID   : 'SCA043';
      Name     : 'Komponente hat Action und OnClick';
      ShortDesc: 'Action und OnClick sind beide gesetzt - der explizite OnClick gewinnt, die TAction-Verdrahtung ist tot';
      FullDesc : ''
    ),
    // SCA044
    (
      RuleID   : 'SCA044';
      Name     : 'Lange String-Verkettung - besser Format()';
      ShortDesc: 'Mehrteilige String-Verkettung - in einen Format()-Aufruf ' + #$00FC + 'berf' + #$00FC +
        'hren';
      FullDesc : ''
    ),
    // SCA045
    (
      RuleID   : 'SCA045';
      Name     : 'with X do ...';
      ShortDesc: 'with-Anweisung - Scope-Verdeckung, vor der der Compiler nicht warnt';
      FullDesc : ''
    ),
    // SCA046
    (
      RuleID   : 'SCA046';
      Name     : 'for i := High to Low - downto fehlt';
      ShortDesc: 'for i := 10 to 1 do - der Schleifenrumpf l' + #$00E4 + 'uft nie';
      FullDesc : ''
    ),
    // SCA047
    (
      RuleID   : 'SCA047';
      Name     : 'x := x';
      ShortDesc: 'Selbstzuweisung - wirkungslos oder ein Copy-Paste-Vertipper';
      FullDesc : ''
    ),
    // SCA048
    (
      RuleID   : 'SCA048';
      Name     : 'Virtueller Aufruf im Konstruktor';
      ShortDesc: 'Virtuelle Methode aus dem Konstruktor gerufen - die Ableitung sieht ein halb initialisiertes Self';
      FullDesc : ''
    ),
    // SCA049
    (
      RuleID   : 'SCA049';
      Name     : 'Length(s) - N ohne Absicherung';
      ShortDesc: '`Length(s) - K` bzw. `.Count - K` mit K >= 2 ohne Absicherung - negativer Index oder negative Anzahl, wenn die Eingabe k' +
        #$00FC + 'rzer als K ist';
      FullDesc : ''
    ),
    // SCA050
    (
      RuleID   : 'SCA050';
      Name     : 'Public-Member k' + #$00F6 + 'nnte unit-private sein';
      ShortDesc: 'Public-Member wird nur innerhalb der aktuellen Unit referenziert - Delphi-klassisches `private` (Unit-Scope) reicht';
      FullDesc : ''
    ),
    // SCA051
    (
      RuleID   : 'SCA051';
      Name     : 'Public-Member k' + #$00F6 + 'nnte protected sein';
      ShortDesc: 'Public-Member wird nur aus Ableitungen referenziert, nie von au' + #$00DF + 'en';
      FullDesc : ''
    ),
    // SCA052
    (
      RuleID   : 'SCA052';
      Name     : 'Ungenutzter Public-Member (tote API)';
      ShortDesc: 'Public-Member wird von keiner Ableitung und ' + #$00FC +
        'ber keine Unit-Grenze referenziert';
      FullDesc : ''
    ),
    // SCA053
    (
      RuleID   : 'SCA053';
      Name     : 'Ungenutzte lokale Variable';
      ShortDesc: 'Lokale Variable deklariert, aber im Methodenrumpf nie referenziert';
      FullDesc : ''
    ),
    // SCA054
    (
      RuleID   : 'SCA054';
      Name     : 'Ungenutzter Methodenparameter';
      ShortDesc: 'Methodenparameter wird im Rumpf nie verwendet';
      FullDesc : ''
    ),
    // SCA055
    (
      RuleID   : 'SCA055';
      Name     : 'Tautologischer boolescher Ausdruck';
      ShortDesc: 'Bin' + #$00E4 +
        'rer Operator mit identischer linker und rechter Seite: x = x, a and a, (p <> p)';
      FullDesc : ''
    ),
    // SCA056
    (
      RuleID   : 'SCA056';
      Name     : 'Master-Detail ohne MasterFields';
      ShortDesc: 'TDataSet hat MasterSource gesetzt, aber weder MasterFields noch IndexFieldNames';
      FullDesc : ''
    ),
    // SCA057
    (
      RuleID   : 'SCA057';
      Name     : 'Formular mit vielen DB-Komponenten - DataModule abspalten';
      ShortDesc: 'Sammelhinweis: das Formular h' + #$00E4 + 'lt N oder mehr DB-Komponenten';
      FullDesc : ''
    ),
    // SCA058
    (
      RuleID   : 'SCA058';
      Name     : 'UPDATE / DELETE / TRUNCATE ohne WHERE';
      ShortDesc: 'SQL-Anweisung ' + #$00E4 + 'ndert jede Zeile - die WHERE-Klausel fehlt';
      FullDesc : ''
    ),
    // SCA059
    (
      RuleID   : 'SCA059';
      Name     : 'Format()-Gleitkommaformat ohne TFormatSettings';
      ShortDesc: '%.2f / %.3f ohne explizite TFormatSettings - die Falle Komma gegen Punkt als Dezimaltrenner';
      FullDesc : ''
    ),
    // SCA060
    (
      RuleID   : 'SCA060';
      Name     : 'goto-Anweisung';
      ShortDesc: '`goto` schw' + #$00E4 + 'cht den strukturierten Kontrollfluss';
      FullDesc : ''
    ),
    // SCA061
    (
      RuleID   : 'SCA061';
      Name     : 'Tabulator im Quelltext';
      ShortDesc: 'Tabulatoren werden je Editor unterschiedlich dargestellt - Leerzeichen verwenden';
      FullDesc : ''
    ),
    // SCA062
    (
      RuleID   : 'SCA062';
      Name     : 'Quelltextzeile zu lang';
      ShortDesc: 'Zeile l' + #$00E4 + 'nger als 120 Zeichen - umbrechen oder einen Teilausdruck herausziehen';
      FullDesc : ''
    ),
    // SCA063
    (
      RuleID   : 'SCA063';
      Name     : 'Leerraum am Zeilenende';
      ShortDesc: 'Zeile endet mit Leerzeichen oder Tabulator - Hygiene f' + #$00FC + 'r Diffs';
      FullDesc : ''
    ),
    // SCA064
    (
      RuleID   : 'SCA064';
      Name     : 'Pascal-Schl' + #$00FC + 'sselwort nicht klein geschrieben';
      ShortDesc: 'Pascal-Schl' + #$00FC + 'sselw' + #$00F6 + 'rter (`begin`/`end`/`procedure`/...) geh' +
        #$00F6 + 'ren klein geschrieben';
      FullDesc : ''
    ),
    // SCA065
    (
      RuleID   : 'SCA065';
      Name     : 'NOSONAR-Unterdr' + #$00FC + 'ckungsmarker';
      ShortDesc: '`// NOSONAR` sollte keine Befunde stillstellen - Verwendung pr' + #$00FC + 'fen';
      FullDesc : ''
    ),
    // SCA066
    (
      RuleID   : 'SCA066';
      Name     : 'Leere Argumentliste';
      ShortDesc: '`Foo()` sollte `Foo;` hei' + #$00DF + 'en - leere Klammern weglassen';
      FullDesc : ''
    ),
    // SCA067
    (
      RuleID   : 'SCA067';
      Name     : 'Inline-Assembler-Block';
      ShortDesc: '`asm...end`-Block - besser Pascal und Compiler-Intrinsics';
      FullDesc : ''
    ),
    // SCA068
    (
      RuleID   : 'SCA068';
      Name     : 'Trailing-Komma in der Argument-Liste';
      ShortDesc: '`Foo(A, B,)` - das Komma weglassen oder das fehlende Argument erg' + #$00E4 + 'nzen';
      FullDesc : ''
    ),
    // SCA069
    (
      RuleID   : 'SCA069';
      Name     : 'Ganzzahlliteral ohne Ziffergruppierung';
      ShortDesc: 'Gro' + #$00DF + 'e Ganzzahlliterale sollten den Trenner `_` verwenden';
      FullDesc : ''
    ),
    // SCA070
    (
      RuleID   : 'SCA070';
      Name     : 'Auskommentierter Code';
      ShortDesc: 'Kommentar sieht wie Pascal-Code aus - l' + #$00F6 + 'schen oder begr' + #$00FC + 'nden';
      FullDesc : ''
    ),
    // SCA071
    (
      RuleID   : 'SCA071';
      Name     : 'Unit-Section-Keyword nicht in Spalte 1';
      ShortDesc: '`unit`/`interface`/`uses`/`implementation`/`initialization`/`finalization` sollten in Spalte 1 beginnen';
      FullDesc : ''
    ),
    // SCA072
    (
      RuleID   : 'SCA072';
      Name     : #$00DC + 'berfl' + #$00FC + 'ssiger Boolean-Vergleich';
      ShortDesc: '`X = True` sollte `X` hei' + #$00DF + 'en (und `X <> False` entsprechend)';
      FullDesc : ''
    ),
    // SCA073
    (
      RuleID   : 'SCA073';
      Name     : 'Leere Interface-Deklaration';
      ShortDesc: 'Interface ohne Methoden und Properties tr' + #$00E4 + 'gt keinen Vertrag';
      FullDesc : ''
    ),
    // SCA074
    (
      RuleID   : 'SCA074';
      Name     : 'Assert ohne Meldung';
      ShortDesc: '`Assert(cond);` - eine `''warum''`-Meldung f' + #$00FC + 'r die Diagnose erg' + #$00E4 +
        'nzen';
      FullDesc : ''
    ),
    // SCA075
    (
      RuleID   : 'SCA075';
      Name     : 'Explizite TObject-Ableitung';
      ShortDesc: '`class(TObject)` ist ' + #$00FC + 'berfl' + #$00FC + 'ssig - Klammern weglassen';
      FullDesc : ''
    ),
    // SCA076
    (
      RuleID   : 'SCA076';
      Name     : 'Gruppierte Variablen-, Feld- oder Parameterdeklaration';
      ShortDesc: '`A, B: Type` in eine Deklaration je Zeile aufteilen';
      FullDesc : ''
    ),
    // SCA077
    (
      RuleID   : 'SCA077';
      Name     : 'Leerer begin..end-Block';
      ShortDesc: 'Leerer `begin..end` - l' + #$00F6 + 'schen oder die Anweisung erg' + #$00E4 + 'nzen';
      FullDesc : ''
    ),
    // SCA078
    (
      RuleID   : 'SCA078';
      Name     : 'Catch-all auf der Wurzelklasse Exception';
      ShortDesc: '`on E: Exception do` schluckt alles, auch AV und Speicherersch' + #$00F6 + 'pfung';
      FullDesc : ''
    ),
    // SCA079
    (
      RuleID   : 'SCA079';
      Name     : 'Aufeinanderfolgende const/type/var-Sektion';
      ShortDesc: 'Zwei `const`-, `type`- oder `var`-Bl' + #$00F6 + 'cke hintereinander geh' + #$00F6 +
        'ren zusammengefasst';
      FullDesc : ''
    ),
    // SCA080
    (
      RuleID   : 'SCA080';
      Name     : #$00DC + 'berfl' + #$00FC + 'ssiges Exit/Continue vor end';
      ShortDesc: '`Exit;` / `Continue;` direkt vor `end` ist wirkungslos';
      FullDesc : ''
    ),
    // SCA081
    (
      RuleID   : 'SCA081';
      Name     : 'Mehrere Klassendeklarationen in einer Datei';
      ShortDesc: 'Eine Klasse je Unit erleichtert das Refactoring';
      FullDesc : ''
    ),
    // SCA082
    (
      RuleID   : 'SCA082';
      Name     : 'Doppeltes Semikolon';
      ShortDesc: '`;;` - das ' + #$00FC + 'berz' + #$00E4 + 'hlige Semikolon weglassen';
      FullDesc : ''
    ),
    // SCA083
    (
      RuleID   : 'SCA083';
      Name     : 'Leerer finally-Block';
      ShortDesc: '`try ... finally end;` r' + #$00E4 + 'umt nichts auf - entweder f' + #$00FC +
        'llen oder das finally weglassen';
      FullDesc : ''
    ),
    // SCA084
    (
      RuleID   : 'SCA084';
      Name     : #$00DC + 'berfl' + #$00FC + 'ssige Assigned- plus nil-Pr' + #$00FC + 'fung';
      ShortDesc: '`Assigned(X) and (X <> nil)` - die nil-Pr' + #$00FC + 'fung weglassen';
      FullDesc : ''
    ),
    // SCA085
    (
      RuleID   : 'SCA085';
      Name     : 'X.Free; X := nil; sollte FreeAndNil(X) sein';
      ShortDesc: '`FreeAndNil(X)` statt `X.Free; X := nil;` verwenden';
      FullDesc : ''
    ),
    // SCA086
    (
      RuleID   : 'SCA086';
      Name     : 'out-Parameter vermeiden';
      ShortDesc: '`var` ist `out` vorzuziehen (out hat ' + #$00FC + 'berraschende Semantik)';
      FullDesc : ''
    ),
    // SCA087
    (
      RuleID   : 'SCA087';
      Name     : 'Leere Sichtbarkeitssektion in der Klasse';
      ShortDesc: 'Sektionskopf `public`/`private`/... ohne Member darunter';
      FullDesc : ''
    ),
    // SCA088
    (
      RuleID   : 'SCA088';
      Name     : 'Alte Unit-Initialisierung begin..end.';
      ShortDesc: '`initialization..end.` statt des alten `begin..end.` verwenden';
      FullDesc : ''
    ),
    // SCA089
    (
      RuleID   : 'SCA089';
      Name     : 'Public-Feld in der Klasse';
      ShortDesc: 'Ein public-Feld bricht die Kapselung - eine Property verwenden';
      FullDesc : ''
    ),
    // SCA090
    (
      RuleID   : 'SCA090';
      Name     : 'Verschachtelter try-Block';
      ShortDesc: 'Verschachteltes `try..end` - das innere try in eine eigene Methode herausziehen';
      FullDesc : ''
    ),
    // SCA091
    (
      RuleID   : 'SCA091';
      Name     : 'Gro' + #$00DF + 'e case-Anweisung';
      ShortDesc: '`case` mit 10 oder mehr Zweigen - Polymorphie oder eine Dispatch-Tabelle erw' + #$00E4 +
        'gen';
      FullDesc : ''
    ),
    // SCA092
    (
      RuleID   : 'SCA092';
      Name     : 'Unit ohne Deklarationen';
      ShortDesc: 'Unit hat weder type, const, var noch procedure/function - l' + #$00F6 + 'schen oder f' +
        #$00FC + 'llen';
      FullDesc : ''
    ),
    // SCA093
    (
      RuleID   : 'SCA093';
      Name     : 'Mehrere inherited-Aufrufe in einer Methode';
      ShortDesc: 'Zwei oder mehr `inherited;` in derselben Methode - die Seiteneffekte der Basis laufen doppelt';
      FullDesc : ''
    ),
    // SCA094
    (
      RuleID   : 'SCA094';
      Name     : #$00DC + 'berfl' + #$00FC + 'ssige doppelte Klammern';
      ShortDesc: '`((Ident))` - die inneren Klammern weglassen';
      FullDesc : ''
    ),
    // SCA095
    (
      RuleID   : 'SCA095';
      Name     : 'Wiederholte Sichtbarkeitssektion';
      ShortDesc: 'Dieselbe Sektion `public`/`private`/... kommt in einer Klasse zweimal vor';
      FullDesc : ''
    ),
    // SCA096
    (
      RuleID   : 'SCA096';
      Name     : 'Konstruktor ohne inherited-Aufruf';
      ShortDesc: 'Dem Konstruktor fehlt `inherited Create` - die Basis bleibt uninitialisiert';
      FullDesc : ''
    ),
    // SCA097
    (
      RuleID   : 'SCA097';
      Name     : 'Destruktor ohne inherited-Aufruf';
      ShortDesc: 'Dem Destruktor fehlt `inherited Destroy` - das Aufr' + #$00E4 + 'umen der Basis entf' +
        #$00E4 + 'llt (Leck-Risiko)';
      FullDesc : ''
    ),
    // SCA098
    (
      RuleID   : 'SCA098';
      Name     : #$00DC + 'berfl' + #$00FC + 'ssige bedingte Zuweisung';
      ShortDesc: '`if Cond then X := True else X := False` sollte `X := Cond` hei' + #$00DF + 'en';
      FullDesc : ''
    ),
    // SCA099
    (
      RuleID   : 'SCA099';
      Name     : 'Unsymmetrisches begin/end in if/else';
      ShortDesc: 'Der then-Zweig nutzt `begin..end`, der else-Zweig ist eine einzelne Anweisung';
      FullDesc : ''
    ),
    // SCA100
    (
      RuleID   : 'SCA100';
      Name     : 'Zeigertyp-Alias ohne P-Pr' + #$00E4 + 'fix';
      ShortDesc: '`Foo = ^Bar` sollte `PBar = ^Bar` hei' + #$00DF + 'en (P-Pr' + #$00E4 + 'fix-Konvention)';
      FullDesc : ''
    ),
    // SCA101
    (
      RuleID   : 'SCA101';
      Name     : 'Zweig ohne begin..end-Block';
      ShortDesc: '`then`/`else`/`do <Anweisung>` - besser ein ausdr' + #$00FC + 'ckliches `begin..end`';
      FullDesc : ''
    ),
    // SCA102
    (
      RuleID   : 'SCA102';
      Name     : 'Verschachtelte Routine in einer Methode';
      ShortDesc: 'Lokale verschachtelte Prozedur oder Funktion - auf Unit-Ebene herausziehen';
      FullDesc : ''
    ),
    // SCA103
    (
      RuleID   : 'SCA103';
      Name     : 'Klassenfeld ohne F-Pr' + #$00E4 + 'fix';
      ShortDesc: 'Klassenfelder sollten der Konvention `F<Name>` folgen';
      FullDesc : ''
    ),
    // SCA104
    (
      RuleID   : 'SCA104';
      Name     : 'Klassen-/Record-Typ ohne T-Pr' + #$00E4 + 'fix';
      ShortDesc: 'Klassen- und Record-Typaliase sollten mit `T` beginnen';
      FullDesc : ''
    ),
    // SCA105
    (
      RuleID   : 'SCA105';
      Name     : 'Interface-Typ ohne I-Pr' + #$00E4 + 'fix';
      ShortDesc: 'Interface-Aliase sollten mit `I` beginnen (`IFoo = interface`)';
      FullDesc : ''
    ),
    // SCA106
    (
      RuleID   : 'SCA106';
      Name     : 'Methode nicht in PascalCase';
      ShortDesc: 'Methoden sollten mit einem Gro' + #$00DF + 'buchstaben beginnen (PascalCase)';
      FullDesc : ''
    ),
    // SCA107
    (
      RuleID   : 'SCA107';
      Name     : 'Public-Member k' + #$00F6 + 'nnte strict private sein';
      ShortDesc: 'Public-Member wird NUR von Methoden der eigenen Klasse referenziert - `strict private` erreicht die st' +
        #$00E4 + 'rkste Kapselung';
      FullDesc : ''
    ),
    // SCA108
    (
      RuleID   : 'SCA108';
      Name     : 'TThread.Synchronize aus dem Destruktor';
      ShortDesc: 'Synchronize() aus dem Destruktor Destroy gerufen - ein sich selbst freigebender Thread blockiert dort, bis der Hauptthread den Aufruf ausf' +
        #$00FC + 'hrt, und h' + #$00E4 + 'ngt, wenn er es nicht tut';
      FullDesc : ''
    ),
    // SCA109
    (
      RuleID   : 'SCA109';
      Name     : 'Sperre ohne try/finally freigegeben';
      ShortDesc: 'TCriticalSection, Monitor oder WinAPI-Sperre ohne umschlie' + #$00DF +
        'endes try..finally genommen - eine Ausnahme l' + #$00E4 + 'sst sie gesperrt';
      FullDesc : ''
    ),
    // SCA110
    (
      RuleID   : 'SCA110';
      Name     : 'String-Verkettung in der Schleife';
      ShortDesc: '`s := s + x` in for/while/repeat - quadratisch viele Neuallokationen';
      FullDesc : ''
    ),
    // SCA111
    (
      RuleID   : 'SCA111';
      Name     : 'ParamByName(...) in der Schleife gerufen';
      ShortDesc: '`Query.ParamByName(''x'').AsXxx := ...` in einer Schleife - lineare Suche je Durchlauf';
      FullDesc : ''
    ),
    // SCA112
    (
      RuleID   : 'SCA112';
      Name     : 'FieldByName(...) in der Schleife gerufen';
      ShortDesc: '`DataSet.FieldByName(''x'').AsXxx` in einer Schleife - lineare Suche je Datensatz';
      FullDesc : ''
    ),
    // SCA113
    (
      RuleID   : 'SCA113';
      Name     : 'TThread.Resume ist veraltet';
      ShortDesc: '`MyThread.Resume` - `MyThread.Start` verwenden (seit Delphi 2010)';
      FullDesc : ''
    ),
    // SCA114
    (
      RuleID   : 'SCA114';
      Name     : 'TThread per FreeAndNil freigegeben - Beendigung pr' + #$00FC + 'fen';
      ShortDesc: '`FreeAndNil(MyThread)` ohne nahes `Terminate` - ein Pr' + #$00FC +
        'fhinweis, kein bewiesener Defekt: `TThread.Destroy` beendet den Thread selbst; `Execute`, den Thread-Destruktor und `FreeOnTerminate` pr' +
        #$00FC + 'fen';
      FullDesc : ''
    ),
    // SCA115
    (
      RuleID   : 'SCA115';
      Name     : 'HTTP-URL im Klartext';
      ShortDesc: 'Literal `''http://...''` f' + #$00FC + 'r einen entfernten Endpunkt - anf' + #$00E4 +
        'llig f' + #$00FC + 'r Man-in-the-Middle';
      FullDesc : ''
    ),
    // SCA116
    (
      RuleID   : 'SCA116';
      Name     : 'TLS-Pr' + #$00FC + 'fung abgeschaltet';
      ShortDesc: 'Leeres `SecureProtocols`, `IgnoreCertificateErrors := True` oder `OnVerifyPeer := nil`';
      FullDesc : ''
    ),
    // SCA117
    (
      RuleID   : 'SCA117';
      Name     : 'Public-Member ohne Doku-Kommentar';
      ShortDesc: 'Public-Methode oder -Property in der `interface`-Sektion ohne Doku-Kommentar direkt dar' +
        #$00FC + 'ber';
      FullDesc : ''
    ),
    // SCA118
    (
      RuleID   : 'SCA118';
      Name     : 'Exception-Klasse ohne `E`-Pr' + #$00E4 + 'fix';
      ShortDesc: 'Eine `class(Exception)`-Ableitung sollte der RTL-Konvention `E<Name>` folgen';
      FullDesc : ''
    ),
    // SCA119
    (
      RuleID   : 'SCA119';
      Name     : 'Lokale Konstante nicht in UPPER_SNAKE_CASE';
      ShortDesc: '`const X = 42;` in einer Methode - f' + #$00FC +
        'r Zahlenkonstanten ist UPPER_SNAKE_CASE vorzuziehen';
      FullDesc : ''
    ),
    // SCA120
    (
      RuleID   : 'SCA120';
      Name     : 'Exception erzeugt, aber nie ausgel' + #$00F6 + 'st';
      ShortDesc: '`EFoo.Create(''msg'');` legt ein Exception-Objekt an, ohne es zu `raise`n - der Fehlerpfad wird stillschweigend ' +
        #$00FC + 'bersprungen';
      FullDesc : ''
    ),
    // SCA121
    (
      RuleID   : 'SCA121';
      Name     : 'Funktion weist Result nie zu';
      ShortDesc: 'Der Funktionsrumpf endet, ohne `Result` (oder `<Funktionsname> := ...`) zu schreiben - der R' +
        #$00FC + 'ckgabewert ist undefiniert';
      FullDesc : ''
    ),
    // SCA122
    (
      RuleID   : 'SCA122';
      Name     : 'Erneutes raise der gebundenen Exception-Variablen';
      ShortDesc: '`on E: T do ... raise E;` verwirft den urspr' + #$00FC +
        'nglichen Stack Trace - das blanke `raise;` erh' + #$00E4 + 'lt ihn';
      FullDesc : ''
    ),
    // SCA123
    (
      RuleID   : 'SCA123';
      Name     : 'Typumwandlung direkt vor Free / Destroy';
      ShortDesc: '`TFoo(x).Free` - die Typumwandlung beeinflusst nicht, welches Destroy l' + #$00E4 +
        'uft (Destroy ist virtuell)';
      FullDesc : ''
    ),
    // SCA124
    (
      RuleID   : 'SCA124';
      Name     : 'Konstruktor auf einer Instanz statt der Klasse aufgerufen';
      ShortDesc: '`obj.Create` - ruft den Konstruktor als Methode auf einer bestehenden Instanz, ' + #$00FC +
        'berspringt die Allokation und initialisiert Felder ' + #$00FC + 'ber lebenden Daten neu';
      FullDesc : ''
    ),
    // SCA125
    (
      RuleID   : 'SCA125';
      Name     : 'Override, dessen Rumpf nur aus `inherited;` besteht';
      ShortDesc: 'Ein Override, das nur an die Basis weiterreicht, hat keinen Zweck - entfernen';
      FullDesc : ''
    ),
    // SCA126
    (
      RuleID   : 'SCA126';
      Name     : 'Assigned() statt `= nil` / `<> nil` verwenden';
      ShortDesc: 'Pascal-Konvention: `Assigned(x)` und `not Assigned(x)` sind die kanonischen nil-Pr' +
        #$00FC + 'fungen';
      FullDesc : ''
    ),
    // SCA127
    (
      RuleID   : 'SCA127';
      Name     : 'Basisklasse `Exception` statt einer eigenen Ableitung ausgel' + #$00F6 + 'st';
      ShortDesc: '`raise Exception.Create(''...'')` - die Basisklasse tr' + #$00E4 +
        'gt keine Semantik, Aufrufer k' + #$00F6 + 'nnen nicht gezielt filtern';
      FullDesc : ''
    ),
    // SCA128
    (
      RuleID   : 'SCA128';
      Name     : 'Gebietsschema-abh' + #$00E4 + 'ngiger Formataufruf ohne TFormatSettings';
      ShortDesc: '`StrToDate(s)`, `FormatFloat(...)` und Verwandte ohne TFormatSettings h' + #$00E4 +
        'ngen am System-Gebietsschema - je Rechner und Benutzer verschieden';
      FullDesc : ''
    ),
    // SCA129
    (
      RuleID   : 'SCA129';
      Name     : 'String-Umwandlung in einen 8-Bit-Typ ohne explizite Kodierung';
      ShortDesc: '`AnsiString(s)` / `RawByteString(s)` / `ShortString(s)` verwirft stillschweigend alle Zeichen au' +
        #$00DF + 'erhalb der aktiven Codepage';
      FullDesc : ''
    ),
    // SCA130
    (
      RuleID   : 'SCA130';
      Name     : 'Char-Wert nach PChar umgewandelt - Codepoint wird zur Adresse';
      ShortDesc: '`PChar(''A'')` ist nicht `PChar("A")` - die Umwandlung deutet den 16-Bit-Codepoint als rohe Speicheradresse';
      FullDesc : ''
    ),
    // SCA131
    (
      RuleID   : 'SCA131';
      Name     : 'IfThen() wertet beide Zweige aus - keine Kurzschlussauswertung';
      ShortDesc: '`Math.IfThen(cond, A(), B())` und `StrUtils.IfThen` sind normale Funktionen - beide Arme laufen vor dem Aufruf';
      FullDesc : ''
    ),
    // SCA132
    (
      RuleID   : 'SCA132';
      Name     : 'except on E: Exception f' + #$00E4 + 'ngt jeden Fehler';
      ShortDesc: '`on E: Exception do ...` f' + #$00E4 +
        'ngt die Basisklasse und damit jede Ableitung, auch System-Ausnahmen, die nicht stillgestellt werden d' +
        #$00FC + 'rfen (EOutOfMemory, EAccessViolation, EAbort)';
      FullDesc : ''
    ),
    // SCA133
    (
      RuleID   : 'SCA133';
      Name     : 'Blankes raise au' + #$00DF + 'erhalb eines except/on-Handlers';
      ShortDesc: '`raise;` ohne Exception-Ausdruck ist nur INNERHALB eines except-Handlers g' + #$00FC +
        'ltig (erneutes Ausl' + #$00F6 + 'sen) - ' + #$00FC +
        'berall sonst lehnen Delphi (E2145) und FPC es ab';
      FullDesc : ''
    ),
    // SCA134
    (
      RuleID   : 'SCA134';
      Name     : 'Variable nach Free / FreeAndNil verwendet';
      ShortDesc: 'Eine Variable nach `Free` oder `FreeAndNil` zu dereferenzieren liest einen h' + #$00E4 +
        'ngenden Zeiger und erzeugt eine Access Violation';
      FullDesc : ''
    ),
    // SCA135
    (
      RuleID   : 'SCA135';
      Name     : 'Konkrete Ableitung erbt eine abstrakte Methode ohne override';
      ShortDesc: 'Die Klasse leitet von einer Basis mit `abstract`-Methode ab, ' + #$00FC +
        'berschreibt sie aber nicht - der Aufruf auf der Instanz l' + #$00F6 +
        'st zur Laufzeit EAbstractError aus';
      FullDesc : ''
    ),
    // SCA136
    (
      RuleID   : 'SCA136';
      Name     : 'Konstruktor belegt Felder und l' + #$00F6 + 'st ohne try/except aus';
      ShortDesc: 'Der Konstruktor weist Felder per `<Klasse>.Create` zu und l' + #$00F6 + 'st sp' + #$00E4 +
        'ter ohne try/except aus - die Felder lecken, wenn der Destruktor sie nicht freigibt';
      FullDesc : ''
    ),
    // SCA137
    (
      RuleID   : 'SCA137';
      Name     : 'Int64-Ziel bekommt das Produkt zweier 32-Bit-Operanden';
      ShortDesc: '`<Int64-Var> := <a> * <b>` rechnet die Multiplikation in 32 Bit, bevor erweitert wird - ein ' +
        #$00DC + 'berlauf schneidet stillschweigend ab';
      FullDesc : ''
    ),
    // SCA138
    (
      RuleID   : 'SCA138';
      Name     : 'Klasse hat zu viele Methoden oder Felder';
      ShortDesc: 'Eine Klasse mit mehr als 20 Methoden oder mehr als 15 Instanzfeldern b' + #$00FC +
        'ndelt zu viele Zust' + #$00E4 + 'ndigkeiten - schwer zu testen, zu ' + #$00E4 +
        'ndern und zu pr' + #$00FC + 'fen';
      FullDesc : ''
    ),
    // SCA139
    (
      RuleID   : 'SCA139';
      Name     : 'Free ohne anschlie' + #$00DF + 'endes nil-Setzen';
      ShortDesc: '`obj.Free;` ohne `obj := nil;` (oder ohne FreeAndNil) hinterl' + #$00E4 + 'sst einen h' +
        #$00E4 + 'ngenden Zeiger - jede weitere Verwendung ist ein Use-After-Free';
      FullDesc : ''
    ),
    // SCA140
    (
      RuleID   : 'SCA140';
      Name     : 'Methode hat zu viele Exit-Anweisungen';
      ShortDesc: 'Eine Methode mit mehr als 6 Exit-Aufrufen hat zu viele R' + #$00FC +
        'cksprungpfade - schwer zu lesen, schwer zu testen, leicht einen zu ' + #$00FC + 'bersehen';
      FullDesc : ''
    ),
    // SCA141
    (
      RuleID   : 'SCA141';
      Name     : 'Klassenimplementierung ' + #$00FC + 'berschreitet 500 Zeilen';
      ShortDesc: 'Eine Klasse, deren Deklaration und Implementierungsmethoden zusammen ' + #$00FC +
        'ber 500 Zeilen umfassen, hat zu viele Zust' + #$00E4 + 'ndigkeiten';
      FullDesc : ''
    ),
    // SCA142
    (
      RuleID   : 'SCA142';
      Name     : 'uses-Klausel ist nicht alphabetisch sortiert';
      ShortDesc: 'Eintr' + #$00E4 +
        'ge einer `uses`-Klausel stehen nicht alphabetisch - Merges werden unvorhersehbar und Reviews schwerer';
      FullDesc : ''
    ),
    // SCA143
    (
      RuleID   : 'SCA143';
      Name     : 'Unit hat keinen erkl' + #$00E4 + 'renden Header-Kommentar';
      ShortDesc: 'Die Unit beginnt direkt mit `interface`, ohne erkl' + #$00E4 +
        'renden Kommentarblock zwischen `unit ...;` und `interface`';
      FullDesc : ''
    ),
    // SCA144
    (
      RuleID   : 'SCA144';
      Name     : 'Gleichheits-/Ungleichheitsvergleich von Gleitkommazahlen';
      ShortDesc: '`a = b` oder `a <> b` zwischen Single/Double/Extended ist wegen der IEEE-754-Rundung unzuverl' +
        #$00E4 + 'ssig - SameValue oder Math.IsZero verwenden';
      FullDesc : ''
    ),
    // SCA145
    (
      RuleID   : 'SCA145';
      Name     : 'raise im Destruktor ohne try/except';
      ShortDesc: 'Ein ungesch' + #$00FC + 'tztes `raise` im Destruktor bricht die Aufr' + #$00E4 +
        'umkette ab - inherited Destroy und nachfolgende FreeAndNil-Aufrufe entfallen, der Zustand bleibt inkonsistent';
      FullDesc : ''
    ),
    // SCA146
    (
      RuleID   : 'SCA146';
      Name     : 'Boolean-Parameter als interner Verzweigungsschalter';
      ShortDesc: 'Ein Boolean-Parameter, dessen Wert zwischen zwei v' + #$00F6 +
        'llig verschiedenen Codepfaden w' + #$00E4 +
        'hlt, ist eine verdeckte Strategie - besser zwei Methoden mit sprechenden Namen';
      FullDesc : ''
    ),
    // SCA147
    (
      RuleID   : 'SCA147';
      Name     : 'Private Methode ohne Aufrufer in der Unit';
      ShortDesc: 'Eine private Methode, die von keiner anderen Methode derselben Unit referenziert wird, ist toter Code - l' +
        #$00F6 + 'schen oder anbinden';
      FullDesc : ''
    ),
    // SCA148
    (
      RuleID   : 'SCA148';
      Name     : 'Instanzmethode greift nie auf Self zu - k' + #$00F6 + 'nnte Klassenmethode sein';
      ShortDesc: 'Eine Methode, die nur ihre Parameter nutzt (kein Self, keine Instanzfelder, keine virtuelle Kette), ist funktional eine Klassenmethode - als solche kennzeichnen';
      FullDesc : ''
    ),
    // SCA149
    (
      RuleID   : 'SCA149';
      Name     : 'Methode verdeckt eine virtuelle Basismethode ohne `override`';
      ShortDesc: 'Eine in der Ableitung mit demselben Namen wie eine virtuelle oder dynamische Basismethode neu deklarierte Methode ohne `override` bricht die Polymorphie - der Compiler meldet W1010';
      FullDesc : ''
    ),
    // SCA150
    (
      RuleID   : 'SCA150';
      Name     : 'Boolescher Vergleich ist immer wahr / immer falsch';
      ShortDesc: 'Vergleiche wie `Length(s) >= 0` sind Tautologien - das Ergebnis von Length ist nie negativ, die Bedingung also nie falsch';
      FullDesc : ''
    ),
    // SCA151
    (
      RuleID   : 'SCA151';
      Name     : 'Funktion liefert immer dasselbe Literal';
      ShortDesc: 'Alle Pfade der Funktion weisen Result dasselbe Literal zu - die Verzweigung ' + #$00E4 +
        'ndert nichts am Verhalten, die Funktion durch eine Konstante ersetzen';
      FullDesc : ''
    ),
    // SCA152
    (
      RuleID   : 'SCA152';
      Name     : 'Benutzersichtbarer Text als Literal zugewiesen';
      ShortDesc: 'Zuweisungen an Caption/Hint/Text und Aufrufe von ShowMessage/MessageDlg mit Literaltext umgehen resourcestring und i18n - der Text ist nicht ' +
        #$00FC + 'bersetzbar';
      FullDesc : ''
    ),
    // SCA153
    (
      RuleID   : 'SCA153';
      Name     : 'Lock/Unlock-Paar ohne try/finally';
      ShortDesc: 'Lock / EnterCriticalSection / TMonitor.Enter mit passender Freigabe in derselben Routine, aber ohne try/finally - der Ausnahmepfad l' +
        #$00E4 + 'sst die Sperre stehen und blockiert den n' + #$00E4 + 'chsten Aufrufer';
      FullDesc : ''
    ),
    // SCA154
    (
      RuleID   : 'SCA154';
      Name     : 'Move/FillChar mit SizeOf eines Zeigertyps';
      ShortDesc: 'Move, FillChar, CopyMemory oder ZeroMemory mit SizeOf(PXxx), wobei PXxx ein Zeigertyp ist - kopiert nur 4 oder 8 Byte (die Zeigergr' +
        #$00F6 + #$00DF + 'e) statt des gemeinten Puffers';
      FullDesc : ''
    ),
    // SCA155
    (
      RuleID   : 'SCA155';
      Name     : 'with-Anweisung mit mehreren Zielen';
      ShortDesc: '`with A, B do` (zwei oder mehr durch Komma getrennte Empf' + #$00E4 +
        'nger) macht die Member-Aufl' + #$00F6 + 'sung mehrdeutig - eine neue Methode an A oder B ' +
        #$00E4 + 'ndert stillschweigend die Bedeutung des Rumpfs';
      FullDesc : ''
    ),
    // SCA156
    (
      RuleID   : 'SCA156';
      Name     : 'GetMem / AllocMem ohne try/finally';
      ShortDesc: 'GetMem / AllocMem / ReallocMem mit passendem FreeMem in derselben Routine, aber ohne umschlie' +
        #$00DF + 'endes try/finally - der Ausnahmepfad verliert den Puffer dauerhaft';
      FullDesc : ''
    ),
    // SCA157
    (
      RuleID   : 'SCA157';
      Name     : 'SetLength(arr, Length(arr) + N) in der Schleife';
      ShortDesc: 'Ein dynamisches Array in einer for/while/repeat-Schleife um eins (oder N) zu vergr' +
        #$00F6 + #$00DF + 'ern kostet quadratisch - einmal vor der Schleife vergr' + #$00F6 + #$00DF +
        'ern oder blockweise wachsen';
      FullDesc : ''
    ),
    // SCA158
    (
      RuleID   : 'SCA158';
      Name     : 'PChar(s) +/- Offset ohne Leerpr' + #$00FC + 'fung';
      ShortDesc: '`PChar(s) + n` und Verwandte ohne vorherige Leerpr' + #$00FC +
        'fung auf `s` - bei einem String k' + #$00FC +
        'rzer als n zeigt der Zeiger hinter den Terminator';
      FullDesc : ''
    ),
    // SCA159
    (
      RuleID   : 'SCA159';
      Name     : 'Typisierter Exception-Handler mit leerem Rumpf';
      ShortDesc: '`on E: SomeException do ;` schluckt eine bestimmte Exception-Klasse stillschweigend - schlimmer als ein blankes `except end`, weil die Typangabe absichtsvoll aussieht';
      FullDesc : ''
    ),
    // SCA160
    (
      RuleID   : 'SCA160';
      Name     : 'String-Cast aus Raw-Pointer';
      ShortDesc: '`string(P)` und Verwandte aus einem P-pr' + #$00E4 +
        'fixierten Zeiger setzen einen Nullterminator voraus, den es nicht geben muss - ' + #$00DC +
        'berlesen des Heaps';
      FullDesc : ''
    ),
    // SCA161
    (
      RuleID   : 'SCA161';
      Name     : 'Zeigersubtraktion ' + #$00FC + 'ber eine 32-Bit-Umwandlung';
      ShortDesc: '`Cardinal(P1) - Cardinal(P2)` (auch Integer/LongWord/LongInt) schneidet unter Win64 die oberen 32 Bit ab - die Differenz ist zeitweise falsch';
      FullDesc : ''
    ),
    // SCA162
    (
      RuleID   : 'SCA162';
      Name     : 'Schwaches oder veraltetes Kryptoverfahren verwendet';
      ShortDesc: 'Algorithmusname (''MD5'', ''SHA1'', ''DES'', ''RC4'', ''TLS1.0'', ''SSLv3'') oder Wrapper-Klasse (THashMD5, TIdHashSHA1, ...) referenziert - anf' +
        #$00E4 + 'llig f' + #$00FC + 'r Kollisions- und Known-Plaintext-Angriffe';
      FullDesc : ''
    ),
    // SCA163
    (
      RuleID   : 'SCA163';
      Name     : 'Shell-API mit String-Verkettung im Argument gerufen';
      ShortDesc: 'ShellExecute / CreateProcess / WinExec mit `+` in den Argumenten - ist ein Operand beeinflussbar, wird daraus ein Command-Injection-Vektor';
      FullDesc : ''
    ),
    // SCA164
    (
      RuleID   : 'SCA164';
      Name     : 'Routine auf oberster Ebene wird nie gerufen';
      ShortDesc: 'Eine eigenst' + #$00E4 +
        'ndige Prozedur oder Funktion in der implementation-Sektion wird nirgends in der Unit gerufen und ist nicht ' +
        #$00FC + 'ber die interface-Sektion exportiert - toter Code';
      FullDesc : ''
    ),
    // SCA165
    (
      RuleID   : 'SCA165';
      Name     : 'Ungenutzter noinspection-Marker';
      ShortDesc: 'Ein `// noinspection X` unterdr' + #$00FC +
        'ckt an seiner Zielzeile keinen Befund - entweder ist der Detektor besser geworden oder das Ziel war falsch';
      FullDesc : ''
    ),
    // SCA166
    (
      RuleID   : 'SCA166';
      Name     : 'Uninitialisierte lokale Variable';
      ShortDesc: 'Lokale Variable wird vor ihrer ersten Zuweisung in Quelltext-Reihenfolge gelesen oder nie zugewiesen';
      FullDesc : ''
    ),
    // SCA167
    (
      RuleID   : 'SCA167';
      Name     : 'Random-Aufruf ohne vorheriges Randomize';
      ShortDesc: 'Random / RandomRange / RandomFrom ohne Randomize - Seed=0 liefert bei jedem Lauf dieselbe Folge';
      FullDesc : ''
    ),
    // SCA168
    (
      RuleID   : 'SCA168';
      Name     : 'case-Anweisung ohne else-Zweig';
      ShortDesc: 'Die case-Anweisung hat keinen else-Zweig - unbehandelte Werte fallen stillschweigend durch; ein else nach einem if im letzten Arm ist das else des case';
      FullDesc : ''
    ),
    // SCA169
    (
      RuleID   : 'SCA169';
      Name     : 'Assert-Argument enth' + #$00E4 + 'lt einen Aufruf mit Seiteneffekt';
      ShortDesc: 'Assert(SomeCall) - der Aufruf entf' + #$00E4 +
        'llt im Release-Build und sein Seiteneffekt geht stillschweigend verloren';
      FullDesc : ''
    ),
    // SCA170
    (
      RuleID   : 'SCA170';
      Name     : 'string-Parameter ohne const';
      ShortDesc: 'string-Parameter ohne const deklariert - erzwingt bei jedem Aufruf eine Refcount-Erh' +
        #$00F6 + 'hung';
      FullDesc : ''
    ),
    // SCA171
    (
      RuleID   : 'SCA171';
      Name     : 'Compilerschalter OFF ohne passendes ON in derselben Datei';
      ShortDesc: '{$WARNINGS OFF} (oder HINTS/RANGECHECKS/...) ohne schlie' + #$00DF +
        'endes ON - wirkt in die folgenden Units hinein';
      FullDesc : ''
    ),
    // SCA172
    (
      RuleID   : 'SCA172';
      Name     : 'Boolean-Property ohne Is-/Has-/Can-/Should-Pr' + #$00E4 + 'fix';
      ShortDesc: 'Der Name der Boolean-Property liest sich als Substantiv - besser ein Verb-Pr' + #$00E4 +
        'fix, das sich als Frage liest';
      FullDesc : ''
    ),
    // SCA173
    (
      RuleID   : 'SCA173';
      Name     : 'Variant in einer leistungskritischen Methode (enth' + #$00E4 + 'lt Schleife)';
      ShortDesc: 'Variant-Variable in einer Methode mit Schleife - jede Variant-Operation zahlt den 10- bis 100-fachen COM-Dispatch-Aufwand';
      FullDesc : ''
    ),
    // SCA174
    (
      RuleID   : 'SCA174';
      Name     : 'TList<T> mit T.Create gef' + #$00FC + 'llt - Elemente lecken beim Freigeben';
      ShortDesc: 'TList<TFoo>.Create plus Add(TFoo.Create) - die Liste besitzt ihre Elemente nicht, jede TFoo-Instanz leckt';
      FullDesc : ''
    ),
    // SCA175
    (
      RuleID   : 'SCA175';
      Name     : 'Anonyme Methode f' + #$00E4 + 'ngt die Schleifenvariable per Referenz';
      ShortDesc: 'Anonyme Methode in `for i := ... do` referenziert i - alle Closures sehen denselben Endwert';
      FullDesc : ''
    ),
    // SCA176
    (
      RuleID   : 'SCA176';
      Name     : 'Methode mit hoher kognitiver Komplexit' + #$00E4 + 't (verschachtelter Kontrollfluss)';
      ShortDesc: 'Kognitive Komplexit' + #$00E4 + 't ' + #$00FC +
        'ber 15 (Sonar-Stil) - verschachtelte if/for/while/case sind mental schwer zu folgen';
      FullDesc : ''
    ),
    // SCA177
    (
      RuleID   : 'SCA177';
      Name     : 'Thread-Variable nach FreeOnTerminate := True verwendet';
      ShortDesc: 'Nach T.FreeOnTerminate := True riskiert jeder weitere T.-Zugriff eine Access-Violation, wenn der Thread bereits beendet ist';
      FullDesc : ''
    ),
    // SCA178
    (
      RuleID   : 'SCA178';
      Name     : 'Datei-Open-API bekommt verkettete Benutzereingabe';
      ShortDesc: 'Datei-Open mit Pfad aus Benutzereingabe zusammengesetzt - Path-Traversal-Risiko; Eingabe validieren/normalisieren';
      FullDesc : ''
    ),
    // SCA179
    (
      RuleID   : 'SCA179';
      Name     : 'DUnitX-Attribut [Ignore] ohne Begr' + #$00FC + 'ndung';
      ShortDesc: '[Ignore] ohne Begr' + #$00FC + 'ndungs-String ' + #$00FC +
        'berspringt den Test stillschweigend - Nachricht erg' + #$00E4 +
        'nzen, warum er deaktiviert ist';
      FullDesc : ''
    ),
    // SCA180
    (
      RuleID   : 'SCA180';
      Name     : 'Dasselbe Attribut zweimal am selben Member';
      ShortDesc: 'Zwei identische [X]-Attribute am selben Member - Copy-Paste-Rest ohne Wirkung';
      FullDesc : ''
    ),
    // SCA181
    (
      RuleID   : 'SCA181';
      Name     : 'DUnitX-Attribut [Category] ohne Kategorienamen';
      ShortDesc: '[Category] ohne Argument ist in DUnitX ein Compile-Fehler - immer einen Kategorienamen ' +
        #$00FC + 'bergeben';
      FullDesc : ''
    ),
    // SCA182
    (
      RuleID   : 'SCA182';
      Name     : '[TestFixture]-Klasse ohne [Test]-Methode';
      ShortDesc: 'Klasse ist [TestFixture], enth' + #$00E4 +
        'lt aber keine [Test]-Methoden - Zombie-Fixture: sichtbar in TestInsight, wird aber nie ausgef' +
        #$00FC + 'hrt';
      FullDesc : ''
    ),
    // SCA183
    (
      RuleID   : 'SCA183';
      Name     : 'Attribut mit Leerzeile vor dem Ziel-Member';
      ShortDesc: 'Attributzeile gefolgt von einer Leerzeile - optisch losgel' + #$00F6 +
        'st, oft ein Refactoring-Rest';
      FullDesc : ''
    ),
    // SCA184
    (
      RuleID   : 'SCA184';
      Name     : 'Ungenutzte DFM-Komponente';
      ShortDesc: 'DFM-Komponente wird weder im Code noch in anderen Units noch im DFM referenziert - vermutlich ein Refactoring-Rest';
      FullDesc : ''
    ),
    // SCA185
    (
      RuleID   : 'SCA185';
      Name     : 'UTF-8-Quelldatei ohne BOM';
      ShortDesc: 'UTF-8-Datei ohne BOM mit Nicht-ASCII - der Compiler liest sie als ANSI (Mojibake)';
      FullDesc : ''
    ),
    // SCA186
    (
      RuleID   : 'SCA186';
      Name     : 'Ung' + #$00FC + 'ltige UTF-8-Folge in der Quelldatei';
      ShortDesc: 'Fehlerhaftes UTF-8 (' + #$00FC + 'berlang, Surrogat oder au' + #$00DF +
        'erhalb des Bereichs) unter einem UTF-8-BOM';
      FullDesc : ''
    ),
    // SCA187
    (
      RuleID   : 'SCA187';
      Name     : 'NUL- oder Steuerbyte in der Quelldatei';
      ShortDesc: 'NUL oder unzul' + #$00E4 + 'ssiges Steuerbyte - Bin' + #$00E4 +
        'rdatei oder falsch erkannte Kodierung';
      FullDesc : ''
    ),
    // SCA188
    (
      RuleID   : 'SCA188';
      Name     : 'Bidirektionales Steuerzeichen (Trojan Source)';
      ShortDesc: 'Bidi-Override- oder Isolate-Steuerzeichen - der Quelltext liest sich anders, als er kompiliert';
      FullDesc : ''
    ),
    // SCA189
    (
      RuleID   : 'SCA189';
      Name     : 'ANSI-Quelldatei mit Nicht-ASCII-Inhalt';
      ShortDesc: '8-Bit-Quelltext (kein BOM, kein g' + #$00FC + 'ltiges UTF-8) - codepage-abh' + #$00E4 +
        'ngig und nicht portabel';
      FullDesc : ''
    ),
    // SCA190
    (
      RuleID   : 'SCA190';
      Name     : 'UTF-16-Quelldatei';
      ShortDesc: 'UTF-16-Quelltext - kompiliert, aber ungew' + #$00F6 + 'hnlich und werkzeug-unfreundlich';
      FullDesc : ''
    ),
    // SCA191
    (
      RuleID   : 'SCA191';
      Name     : 'UTF-32-/UCS-4-Quelldatei';
      ShortDesc: 'UTF-32-Quelltext - der Delphi-Compiler weist ihn mit dem fatalen Fehler F2438 zur' + #$00FC +
        'ck';
      FullDesc : ''
    ),
    // SCA192
    (
      RuleID   : 'SCA192';
      Name     : 'Unsichtbares Zeichen ohne Breite im Quelltext';
      ShortDesc: 'Unsichtbares Unicode-Zeichen ohne Breite - Vektor f' + #$00FC +
        'r versteckten Text und Homoglyphen-Missbrauch';
      FullDesc : ''
    ),
    // SCA193
    (
      RuleID   : 'SCA193';
      Name     : 'Nicht-ASCII-Zeichen im Bezeichner';
      ShortDesc: 'Der Bezeichner enth' + #$00E4 +
        'lt einen Nicht-ASCII-Buchstaben - Risiko durch Homoglyphen und verwechselbare Zeichen';
      FullDesc : ''
    ),
    // SCA194
    (
      RuleID   : 'SCA194';
      Name     : 'Quelldatei geh' + #$00F6 + 'rt nicht zum Projekt';
      ShortDesc: 'Eine .pas-/.dfm-Datei liegt im Projektordner, ist aber nicht im Projekt (.dproj/.groupproj) referenziert - vermutlich verwaist';
      FullDesc : ''
    ),
    // SCA195
    (
      RuleID   : 'SCA195';
      Name     : 'Unit wird vom Projekt genutzt, ist aber nicht darin enthalten';
      ShortDesc: 'Eine .pas-Datei wird von Projekt-Units per uses gezogen (kompiliert ' + #$00FC +
        'ber den Suchpfad), steht aber nicht in der Projektdatei (.dproj/.groupproj) - ins Projekt aufnehmen';
      FullDesc : ''
    ),
    // SCA196
    (
      RuleID   : 'SCA196';
      Name     : 'Result eines verwalteten Typs wird gelesen, bevor es zugewiesen wurde';
      ShortDesc: 'Result eines verwalteten R' + #$00FC +
        'ckgabetyps wird vor der ersten Zuweisung gelesen - es ist ein Alias der Zielvariablen des Aufrufers und tr' +
        #$00E4 + 'gt deren ALTEN Wert. Zuerst initialisieren (nil / [] / '''')';
      FullDesc : ''
    ),
    // SCA197
    (
      RuleID   : 'SCA197';
      Name     : 'Interface ohne GUID deklariert';
      ShortDesc: 'Interface hat keine GUID - Supports() und QueryInterface() k' + #$00F6 +
        'nnen zur Laufzeit nicht danach fragen. Mit Strg+Umschalt+G eine erzeugen';
      FullDesc : ''
    ),
    // SCA198
    (
      RuleID   : 'SCA198';
      Name     : 'Zwei Interfaces teilen sich dieselbe GUID';
      ShortDesc: 'Dieselbe GUID steht an mehr als einem Interface - Supports() liefert das zuerst registrierte, ohne Compilerfehler. Mit Strg+Umschalt+G eine neue erzeugen';
      FullDesc : ''
    ),
    // SCA199
    (
      RuleID   : 'SCA199';
      Name     : 'ParamByName-Name passt nicht zu den SQL-Platzhaltern';
      ShortDesc: 'ParamByName(''x'') an einer Query, deren SQL kein :x hat (zur Laufzeit ''Parameter nicht gefunden''), oder ein :y im SQL, das die Routine nie zuweist, obwohl sie die anderen Parameter der Query setzt';
      FullDesc : ''
    ),
    // SCA200
    (
      RuleID   : 'SCA200';
      Name     : 'IP-Adresse als String-Literal';
      ShortDesc: 'Hartcodierte IPv4- oder IPv6-Adresse (privat, geteilt oder ' + #$00F6 +
        'ffentlich) in einem String-Literal - in die Konfiguration auslagern oder einen Hostnamen verwenden';
      FullDesc : ''
    ),
    // SCA201
    (
      RuleID   : 'SCA201';
      Name     : 'IP-Adresse in einer versionierten Konfigurationsdatei';
      ShortDesc: 'IPv4- oder IPv6-Adresse (privat, geteilt oder ' + #$00F6 +
        'ffentlich) als Wert in einer .ini-Datei des Quellbaums';
      FullDesc : ''
    ),
    // SCA202
    (
      RuleID   : 'SCA202';
      Name     : 'not, and, or oder xor bindet vor dem Vergleich';
      ShortDesc: '''not Count > 0'' oder ''A = True or B = False'' - not/and/or/xor binden st' + #$00E4 +
        'rker als Vergleiche, der Ausdruck kompiliert, pr' + #$00FC + 'ft aber etwas anderes';
      FullDesc : ''
    ),
    // SCA203
    (
      RuleID   : 'SCA203';
      Name     : 'for-Schleife l' + #$00E4 + 'uft einen Index ' + #$00FC + 'ber das Ende';
      ShortDesc: 'for-Schleife l' + #$00E4 +
        'uft bis Count, Length() oder High() + 1 und indiziert dieselbe Sammlung mit der Schleifenvariablen - der letzte Durchlauf liegt au' +
        #$00DF + 'erhalb';
      FullDesc : ''
    ),
    // SCA204
    (
      RuleID   : 'SCA204';
      Name     : 'Ergebnis ' + #$00FC + 'ber den Funktionsnamen zugewiesen';
      ShortDesc: 'Funktionsergebnis durch Zuweisung an den Funktionsnamen gesetzt (''GetCount := ...'') - die alte Pascal-Form; Delphi schreibt Result';
      FullDesc : ''
    ),
    // SCA205
    (
      RuleID   : 'SCA205';
      Name     : 'Funktionsname im eigenen Rumpf gelesen ist ein rekursiver Aufruf';
      ShortDesc: '''Total := Total + X'' in der Funktion Total: rechts ist der Name ein rekursiver Aufruf, nicht das bisherige Ergebnis';
      FullDesc : ''
    )
  );

  // Index == Ord(TFindingKind), Drift-Guard im Leser wie bei
  // RULE_CATALOG_DATA (RuleID muss zur Position passen).
  RULE_OVERLAY_FR : array[0..204] of TRuleOverlayData = (
    // SCA001
    (
      RuleID   : 'SCA001';
      Name     : 'Objet cr' + #$00E9 + #$00E9 + ' sans lib' + #$00E9 + 'ration s' + #$00FB +
        're face aux exceptions';
      ShortDesc: 'Objet cr' + #$00E9 + #$00E9 + ' mais pas lib' + #$00E9 + 'r' + #$00E9 + ' de mani' + #$00E8 +
        're fiable (fuite m' + #$00E9 + 'moire possible)';
      FullDesc : ''
    ),
    // SCA002
    (
      RuleID   : 'SCA002';
      Name     : 'Bloc except vide';
      ShortDesc: 'Un bloc except vide avale silencieusement toutes les exceptions';
      FullDesc : ''
    ),
    // SCA003
    (
      RuleID   : 'SCA003';
      Name     : 'Cha' + #$00EE + 'ne SQL construite par concat' + #$00E9 + 'nation';
      ShortDesc: 'Cha' + #$00EE + 'ne SQL concat' + #$00E9 + 'n' + #$00E9 + 'e avec ''+'' ' + #$00E0 +
        ' partir d''une saisie contr' + #$00F4 + 'lable (risque d''injection)';
      FullDesc : ''
    ),
    // SCA004
    (
      RuleID   : 'SCA004';
      Name     : 'Identifiant / jeton d''API en dur';
      ShortDesc: 'Mot de passe, cl' + #$00E9 + ' d''API ou jeton sous forme de litt' + #$00E9 + 'ral cha' +
        #$00EE + 'ne dans le code source';
      FullDesc : ''
    ),
    // SCA005
    (
      RuleID   : 'SCA005';
      Name     : 'Format() : nombre de marqueurs incoh' + #$00E9 + 'rent';
      ShortDesc: 'Le nombre de marqueurs de Format() / FormatUtf8() ne correspond pas au nombre d''arguments';
      FullDesc : ''
    ),
    // SCA006
    (
      RuleID   : 'SCA006';
      Name     : 'Le fichier n''a pas pu ' + #$00EA + 'tre lu ou analys' + #$00E9;
      ShortDesc: 'Erreur d''analyse ou d''E/S - fichier source illisible ou syntaxiquement cass' + #$00E9;
      FullDesc : ''
    ),
    // SCA007
    (
      RuleID   : 'SCA007';
      Name     : 'Unit inutilis' + #$00E9 + 'e dans la clause uses';
      ShortDesc: 'Entr' + #$00E9 + 'e uses probablement inutilis' + #$00E9 +
        'e (aucun identifiant qui en provienne n''est r' + #$00E9 + 'f' + #$00E9 + 'renc' + #$00E9 +
        ')';
      FullDesc : ''
    ),
    // SCA008
    (
      RuleID   : 'SCA008';
      Name     : 'D' + #$00E9 + 'r' + #$00E9 + 'f' + #$00E9 + 'rencement nil possible';
      ShortDesc: 'Acc' + #$00E8 + 's a une variable qui peut valoir nil a cet endroit';
      FullDesc : ''
    ),
    // SCA009
    (
      RuleID   : 'SCA009';
      Name     : 'Objet cr' + #$00E9 + #$00E9 + ' sans try/finally protecteur';
      ShortDesc: 'Appel .Create sans try/finally englobant - risque de fuite en cas d''exception';
      FullDesc : ''
    ),
    // SCA010
    (
      RuleID   : 'SCA010';
      Name     : 'Division par z' + #$00E9 + 'ro possible';
      ShortDesc: 'Division enti' + #$00E8 + 're (div / mod) par une variable pouvant valoir z' + #$00E9 +
        'ro';
      FullDesc : ''
    ),
    // SCA011
    (
      RuleID   : 'SCA011';
      Name     : 'Le code apr' + #$00E8 + 's Exit/Raise est inatteignable';
      ShortDesc: 'L''instruction qui suit Exit, raise ou Halt est du code mort';
      FullDesc : ''
    ),
    // SCA012
    (
      RuleID   : 'SCA012';
      Name     : 'La m' + #$00E9 + 'thode d' + #$00E9 + 'passe le seuil de lignes';
      ShortDesc: 'Corps de m' + #$00E9 + 'thode plus long que le maximum configur' + #$00E9 + ' (par d' +
        #$00E9 + 'faut : plus de 50 lignes et plus de 30 instructions)';
      FullDesc : ''
    ),
    // SCA013
    (
      RuleID   : 'SCA013';
      Name     : 'Trop de param' + #$00E8 + 'tres';
      ShortDesc: 'La m' + #$00E9 + 'thode a plus de param' + #$00E8 + 'tres que le maximum configur' + #$00E9 +
        ' (5 par d' + #$00E9 + 'faut)';
      FullDesc : ''
    ),
    // SCA014
    (
      RuleID   : 'SCA014';
      Name     : 'Litt' + #$00E9 + 'ral num' + #$00E9 + 'rique sans constante nomm' + #$00E9 + 'e';
      ShortDesc: 'Litt' + #$00E9 + 'ral num' + #$00E9 +
        'rique dans une expression - extraire vers une constante nomm' + #$00E9 + 'e';
      FullDesc : ''
    ),
    // SCA015
    (
      RuleID   : 'SCA015';
      Name     : 'Litt' + #$00E9 + 'ral cha' + #$00EE + 'ne r' + #$00E9 + 'p' + #$00E9 + 't' + #$00E9 +
        ' a plusieurs endroits';
      ShortDesc: 'Le m' + #$00EA + 'me litt' + #$00E9 + 'ral cha' + #$00EE + 'ne appara' + #$00EE +
        't au moins 3 fois dans un fichier - extraire vers une constante';
      FullDesc : ''
    ),
    // SCA016
    (
      RuleID   : 'SCA016';
      Name     : 'Chemin de fichier en litt' + #$00E9 + 'ral cha' + #$00EE + 'ne';
      ShortDesc: 'Chemin C:\, UNC ou Linux ' + #$00E9 + 'crit en dur dans le source';
      FullDesc : ''
    ),
    // SCA017
    (
      RuleID   : 'SCA017';
      Name     : 'WriteLn/ShowMessage en code de production';
      ShortDesc: 'Instruction de sortie de d' + #$00E9 + 'bogage trouv' + #$00E9 +
        'e dans une unit de production';
      FullDesc : ''
    ),
    // SCA018
    (
      RuleID   : 'SCA018';
      Name     : 'L''imbrication de blocs d' + #$00E9 + 'passe le seuil';
      ShortDesc: 'Profondeur d''imbrication if/for/while sup' + #$00E9 + 'rieure au maximum configur' +
        #$00E9 + ' (4 par d' + #$00E9 + 'faut)';
      FullDesc : ''
    ),
    // SCA019
    (
      RuleID   : 'SCA019';
      Name     : 'Marqueur TODO/FIXME en commentaire';
      ShortDesc: 'Marqueur TODO, FIXME, HACK ou XXX ouvert - a traiter avant la livraison';
      FullDesc : ''
    ),
    // SCA020
    (
      RuleID   : 'SCA020';
      Name     : 'Corps de m' + #$00E9 + 'thode vide';
      ShortDesc: 'Le corps de la m' + #$00E9 + 'thode ne contient aucune instruction';
      FullDesc : ''
    ),
    // SCA021
    (
      RuleID   : 'SCA021';
      Name     : 'Bloc de code dupliqu' + #$00E9;
      ShortDesc: 'Plusieurs blocs de code identiques (' + #$00E0 +
        ' partir du nombre minimal de lignes configur' + #$00E9 + ')';
      FullDesc : ''
    ),
    // SCA022
    (
      RuleID   : 'SCA022';
      Name     : 'La m' + #$00E9 + 'thode d' + #$00E9 + 'passe le seuil de complexit' + #$00E9 + ' de McCabe';
      ShortDesc: 'Complexit' + #$00E9 + ' cyclomatique sup' + #$00E9 + 'rieure au seuil configur' + #$00E9 +
        ' (10 par d' + #$00E9 + 'faut)';
      FullDesc : ''
    ),
    // SCA023
    (
      RuleID   : 'SCA023';
      Name     : 'R' + #$00E8 + 'gle personnalis' + #$00E9 + 'e';
      ShortDesc: 'Motif d' + #$00E9 + 'tect' + #$00E9 + ' par une r' + #$00E8 + 'gle charg' + #$00E9 +
        'e depuis analyser-rules.yml';
      FullDesc : ''
    ),
    // SCA024
    (
      RuleID   : 'SCA024';
      Name     : 'Composant au nom par d' + #$00E9 + 'faut';
      ShortDesc: 'Le composant porte encore le nom par d' + #$00E9 +
        'faut de l''assistant (Button1, Edit3, Panel2 ...)';
      FullDesc : ''
    ),
    // SCA025
    (
      RuleID   : 'SCA025';
      Name     : 'Texte d''interface en dur dans le DFM';
      ShortDesc: 'Caption, Hint ou Text sous forme de litt' + #$00E9 +
        'ral dans le DFM, sans passer par la couche i18n';
      FullDesc : ''
    ),
    // SCA026
    (
      RuleID   : 'SCA026';
      Name     : 'Identifiants de base de donn' + #$00E9 + 'es en dur dans le DFM';
      ShortDesc: 'Password en clair ou ConnectionString avec Pwd= sur un composant de base de donn' + #$00E9 +
        'es';
      FullDesc : ''
    ),
    // SCA027
    (
      RuleID   : 'SCA027';
      Name     : 'Liaison (DataSource, DataField) en double';
      ShortDesc: 'Deux contr' + #$00F4 + 'les ou plus lient le m' + #$00EA +
        'me couple DataSource / DataField';
      FullDesc : ''
    ),
    // SCA028
    (
      RuleID   : 'SCA028';
      Name     : 'Le gestionnaire d''' + #$00E9 + 'v' + #$00E9 + 'nement DFM pointe vers une m' + #$00E9 +
        'thode absente';
      ShortDesc: 'OnClick / On... renvoie a une m' + #$00E9 +
        'thode qui n''existe pas dans la classe de la fiche';
      FullDesc : ''
    ),
    // SCA029
    (
      RuleID   : 'SCA029';
      Name     : 'Gestionnaire d''' + #$00E9 + 'v' + #$00E9 + 'nement orphelin';
      ShortDesc: 'M' + #$00E9 + 'thode published de forme TNotifyEvent sans liaison DFM';
      FullDesc : ''
    ),
    // SCA030
    (
      RuleID   : 'SCA030';
      Name     : 'Gestionnaire d''' + #$00E9 + 'v' + #$00E9 + 'nement li' + #$00E9 + ' mais vide';
      ShortDesc: 'L''' + #$00E9 + 'v' + #$00E9 + 'nement est c' + #$00E2 + 'bl' + #$00E9 +
        ' dans le DFM, la m' + #$00E9 + 'thode existe, le corps est vide';
      FullDesc : ''
    ),
    // SCA031
    (
      RuleID   : 'SCA031';
      Name     : 'Composant DFM sans champ published';
      ShortDesc: 'Le composant du DFM n''a pas de champ published correspondant dans la classe de la fiche - entr' +
        #$00E9 + 'e DFM p' + #$00E9 + 'rim' + #$00E9 + 'e (d' + #$00E9 + 'rive de sch' + #$00E9 +
        'ma)';
      FullDesc : ''
    ),
    // SCA032
    (
      RuleID   : 'SCA032';
      Name     : 'Boucle DataSource / ma' + #$00EE + 'tre-detail circulaire';
      ShortDesc: 'Cycle dans les ar' + #$00EA + 'tes DataSource.DataSet / DataSet.MasterSource';
      FullDesc : ''
    ),
    // SCA033
    (
      RuleID   : 'SCA033';
      Name     : 'Propri' + #$00E9 + 't' + #$00E9 + ' SQL construite depuis une saisie d''interface';
      ShortDesc: 'Query.SQL assembl' + #$00E9 + 'e ' + #$00E0 + ' partir des propri' + #$00E9 + 't' + #$00E9 +
        's Text ou Caption de contr' + #$00F4 + 'les de fiche';
      FullDesc : ''
    ),
    // SCA034
    (
      RuleID   : 'SCA034';
      Name     : 'Champ obligatoire sans liaison d''interface';
      ShortDesc: 'Un TField avec Required=True n''a aucun contr' + #$00F4 + 'le de saisie li' + #$00E9;
      FullDesc : ''
    ),
    // SCA035
    (
      RuleID   : 'SCA035';
      Name     : 'Champ obligatoire li' + #$00E9 + ' uniquement a des contr' + #$00F4 + 'les cach' + #$00E9 +
        's';
      ShortDesc: 'Un TField avec Required=True n''est li' + #$00E9 + ' qu''a des contr' + #$00F4 +
        'les ayant Visible=False';
      FullDesc : ''
    ),
    // SCA036
    (
      RuleID   : 'SCA036';
      Name     : 'Type de contr' + #$00F4 + 'le incompatible avec le TField';
      ShortDesc: 'La classe du contr' + #$00F4 + 'le de donn' + #$00E9 +
        'es ne correspond pas a TField.DataType (TDBEdit pour un TBooleanField)';
      FullDesc : ''
    ),
    // SCA037
    (
      RuleID   : 'SCA037';
      Name     : 'TabOrder en double entre fr' + #$00E8 + 'res';
      ShortDesc: 'Deux contr' + #$00F4 + 'les fr' + #$00E8 + 'res du m' + #$00EA + 'me parent partagent la m' +
        #$00EA + 'me valeur TabOrder';
      FullDesc : ''
    ),
    // SCA038
    (
      RuleID   : 'SCA038';
      Name     : 'Le composant utilise une classe interdite';
      ShortDesc: 'La classe du composant figure dans la liste ForbiddenClasses du projet';
      FullDesc : ''
    ),
    // SCA039
    (
      RuleID   : 'SCA039';
      Name     : 'Composant de base de donn' + #$00E9 + 'es sur une fiche d''interface';
      ShortDesc: 'TFDQuery / TFDConnection directement sur un TForm ou TFrame au lieu d''un DataModule';
      FullDesc : ''
    ),
    // SCA040
    (
      RuleID   : 'SCA040';
      Name     : 'Acc' + #$00E8 + 's a un champ d''une autre fiche';
      ShortDesc: 'Du code dans Form1 lit ou ' + #$00E9 + 'crit directement Form2.<champ_published>';
      FullDesc : ''
    ),
    // SCA041
    (
      RuleID   : 'SCA041';
      Name     : 'Contr' + #$00F4 + 'le de saisie directement sur le TForm';
      ShortDesc: 'Le contr' + #$00F4 + 'le de saisie est pos' + #$00E9 + ' sur la fiche au lieu d''' + #$00EA +
        'tre plac' + #$00E9 + ' dans un TPanel ou un TGroupBox';
      FullDesc : ''
    ),
    // SCA042
    (
      RuleID   : 'SCA042';
      Name     : 'Gestionnaire d''' + #$00E9 + 'v' + #$00E9 + 'nement surcharge';
      ShortDesc: 'Une seule m' + #$00E9 + 'thode est c' + #$00E2 + 'bl' + #$00E9 + 'e sur N ' + #$00E9 + 'v' +
        #$00E9 + 'nements de composants ou plus (N=5 par d' + #$00E9 + 'faut)';
      FullDesc : ''
    ),
    // SCA043
    (
      RuleID   : 'SCA043';
      Name     : 'Le composant a Action et OnClick';
      ShortDesc: 'Action et OnClick sont tous deux d' + #$00E9 +
        'finis - le OnClick explicite l''emporte, le c' + #$00E2 + 'blage TAction est mort';
      FullDesc : ''
    ),
    // SCA044
    (
      RuleID   : 'SCA044';
      Name     : 'Longue concat' + #$00E9 + 'nation - pr' + #$00E9 + 'f' + #$00E9 + 'rer Format()';
      ShortDesc: 'Concat' + #$00E9 + 'nation de cha' + #$00EE +
        'ne en plusieurs segments - a transformer en appel a Format()';
      FullDesc : ''
    ),
    // SCA045
    (
      RuleID   : 'SCA045';
      Name     : 'with X do ...';
      ShortDesc: 'Instruction with - pi' + #$00E8 + 'ge de masquage de port' + #$00E9 +
        'e contre lequel le compilateur n''avertit pas';
      FullDesc : ''
    ),
    // SCA046
    (
      RuleID   : 'SCA046';
      Name     : 'for i := High to Low - downto manquant';
      ShortDesc: 'for i := 10 to 1 do - le corps de boucle ne s''ex' + #$00E9 + 'cute jamais';
      FullDesc : ''
    ),
    // SCA047
    (
      RuleID   : 'SCA047';
      Name     : 'x := x';
      ShortDesc: 'Auto-affectation - sans effet, ou faute de copier-coller';
      FullDesc : ''
    ),
    // SCA048
    (
      RuleID   : 'SCA048';
      Name     : 'Appel virtuel dans le constructeur';
      ShortDesc: 'M' + #$00E9 + 'thode virtuelle appel' + #$00E9 + 'e depuis le constructeur - la classe d' +
        #$00E9 + 'riv' + #$00E9 + 'e voit un Self ' + #$00E0 + ' moiti' + #$00E9 + ' initialis' +
        #$00E9;
      FullDesc : ''
    ),
    // SCA049
    (
      RuleID   : 'SCA049';
      Name     : 'Length(s) - N sans garde';
      ShortDesc: '`Length(s) - K` ou `.Count - K` avec K >= 2 sans garde - index ou nombre n' + #$00E9 +
        'gatif quand l''entr' + #$00E9 + 'e est plus courte que K';
      FullDesc : ''
    ),
    // SCA050
    (
      RuleID   : 'SCA050';
      Name     : 'Le membre public pourrait ' + #$00EA + 'tre priv' + #$00E9 + ' a l''unit';
      ShortDesc: 'Ce membre public n''est r' + #$00E9 + 'f' + #$00E9 + 'renc' + #$00E9 +
        ' que dans l''unit courante - le `private` classique de Delphi (port' + #$00E9 +
        'e unit) suffit';
      FullDesc : ''
    ),
    // SCA051
    (
      RuleID   : 'SCA051';
      Name     : 'Le membre public pourrait ' + #$00EA + 'tre protected';
      ShortDesc: 'Membre public r' + #$00E9 + 'f' + #$00E9 + 'renc' + #$00E9 +
        ' uniquement depuis des classes d' + #$00E9 + 'riv' + #$00E9 + 'es, jamais de l''ext' +
        #$00E9 + 'rieur';
      FullDesc : ''
    ),
    // SCA052
    (
      RuleID   : 'SCA052';
      Name     : 'Membre public inutilis' + #$00E9 + ' (API morte)';
      ShortDesc: 'Le membre public n''est r' + #$00E9 + 'f' + #$00E9 + 'renc' + #$00E9 +
        ' par aucune classe d' + #$00E9 + 'riv' + #$00E9 + 'e ni par aucun chemin inter-unit';
      FullDesc : ''
    ),
    // SCA053
    (
      RuleID   : 'SCA053';
      Name     : 'Variable locale inutilis' + #$00E9 + 'e';
      ShortDesc: 'Variable locale d' + #$00E9 + 'clar' + #$00E9 + 'e mais jamais r' + #$00E9 + 'f' + #$00E9 +
        'renc' + #$00E9 + 'e dans le corps de la m' + #$00E9 + 'thode';
      FullDesc : ''
    ),
    // SCA054
    (
      RuleID   : 'SCA054';
      Name     : 'Param' + #$00E8 + 'tre de m' + #$00E9 + 'thode inutilis' + #$00E9;
      ShortDesc: 'Le param' + #$00E8 + 'tre de la m' + #$00E9 + 'thode n''est jamais utilise dans le corps';
      FullDesc : ''
    ),
    // SCA055
    (
      RuleID   : 'SCA055';
      Name     : 'Expression bool' + #$00E9 + 'enne tautologique';
      ShortDesc: 'Op' + #$00E9 +
        'rateur binaire avec membres gauche et droit identiques : x = x, a and a, (p <> p)';
      FullDesc : ''
    ),
    // SCA056
    (
      RuleID   : 'SCA056';
      Name     : 'Ma' + #$00EE + 'tre-detail sans MasterFields';
      ShortDesc: 'Le TDataSet a MasterSource mais ni MasterFields ni IndexFieldNames';
      FullDesc : ''
    ),
    // SCA057
    (
      RuleID   : 'SCA057';
      Name     : 'Fiche charg' + #$00E9 + 'e de composants de donn' + #$00E9 + 'es - extraire un DataModule';
      ShortDesc: 'Indication agr' + #$00E9 + 'g' + #$00E9 + 'e : la fiche porte N composants de base de donn' +
        #$00E9 + 'es ou plus';
      FullDesc : ''
    ),
    // SCA058
    (
      RuleID   : 'SCA058';
      Name     : 'UPDATE / DELETE / TRUNCATE sans WHERE';
      ShortDesc: 'L''instruction SQL modifie toutes les lignes - clause WHERE manquante';
      FullDesc : ''
    ),
    // SCA059
    (
      RuleID   : 'SCA059';
      Name     : 'Format flottant dans Format() sans TFormatSettings';
      ShortDesc: '%.2f / %.3f sans TFormatSettings explicite - le pi' + #$00E8 + 'ge du s' + #$00E9 +
        'parateur d' + #$00E9 + 'cimal virgule ou point';
      FullDesc : ''
    ),
    // SCA060
    (
      RuleID   : 'SCA060';
      Name     : 'Instruction goto';
      ShortDesc: '`goto` affaiblit le flot de contr' + #$00F4 + 'le structure';
      FullDesc : ''
    ),
    // SCA061
    (
      RuleID   : 'SCA061';
      Name     : 'Tabulation dans le source';
      ShortDesc: 'Les tabulations s''affichent diff' + #$00E9 + 'remment selon l''' + #$00E9 +
        'diteur - utiliser des espaces';
      FullDesc : ''
    ),
    // SCA062
    (
      RuleID   : 'SCA062';
      Name     : 'Ligne de source trop longue';
      ShortDesc: 'La ligne d' + #$00E9 + 'passe 120 caract' + #$00E8 +
        'res - couper ou extraire une sous-expression';
      FullDesc : ''
    ),
    // SCA063
    (
      RuleID   : 'SCA063';
      Name     : 'Espaces en fin de ligne';
      ShortDesc: 'La ligne se termine par une espace ou une tabulation - hygi' + #$00E8 + 'ne pour les diffs';
      FullDesc : ''
    ),
    // SCA064
    (
      RuleID   : 'SCA064';
      Name     : 'Mot-cl' + #$00E9 + ' Pascal pas en minuscules';
      ShortDesc: 'Les mots-cl' + #$00E9 + 's Pascal (`begin`/`end`/`procedure`/...) doivent ' + #$00EA +
        'tre en minuscules';
      FullDesc : ''
    ),
    // SCA065
    (
      RuleID   : 'SCA065';
      Name     : 'Marqueur de suppression NOSONAR';
      ShortDesc: '`// NOSONAR` ne devrait pas faire taire des r' + #$00E9 + 'sultats - v' + #$00E9 +
        'rifier l''usage';
      FullDesc : ''
    ),
    // SCA066
    (
      RuleID   : 'SCA066';
      Name     : 'Liste d''arguments vide';
      ShortDesc: '`Foo()` devrait s''' + #$00E9 + 'crire `Foo;` - supprimer les parenth' + #$00E8 +
        'ses vides';
      FullDesc : ''
    ),
    // SCA067
    (
      RuleID   : 'SCA067';
      Name     : 'Bloc assembleur en ligne';
      ShortDesc: 'Bloc `asm...end` - pr' + #$00E9 + 'f' + #$00E9 + 'rer Pascal et les intrins' + #$00E8 +
        'ques du compilateur';
      FullDesc : ''
    ),
    // SCA068
    (
      RuleID   : 'SCA068';
      Name     : 'Virgule finale dans la liste d''arguments';
      ShortDesc: '`Foo(A, B,)` - supprimer la virgule ou ajouter l''argument manquant';
      FullDesc : ''
    ),
    // SCA069
    (
      RuleID   : 'SCA069';
      Name     : 'Litt' + #$00E9 + 'ral entier sans s' + #$00E9 + 'parateur de milliers';
      ShortDesc: 'Les grands litt' + #$00E9 + 'raux entiers devraient utiliser le s' + #$00E9 +
        'parateur `_`';
      FullDesc : ''
    ),
    // SCA070
    (
      RuleID   : 'SCA070';
      Name     : 'Code en commentaire';
      ShortDesc: 'Le commentaire ressemble a du code Pascal - supprimer ou justifier';
      FullDesc : ''
    ),
    // SCA071
    (
      RuleID   : 'SCA071';
      Name     : 'Mot-cl' + #$00E9 + ' de section d''unit qui n''est pas en colonne 1';
      ShortDesc: '`unit`/`interface`/`uses`/`implementation`/`initialization`/`finalization` doivent commencer en colonne 1';
      FullDesc : ''
    ),
    // SCA072
    (
      RuleID   : 'SCA072';
      Name     : 'Comparaison bool' + #$00E9 + 'enne redondante';
      ShortDesc: '`X = True` devrait s''' + #$00E9 + 'crire `X` (et `X <> False` de m' + #$00EA + 'me)';
      FullDesc : ''
    ),
    // SCA073
    (
      RuleID   : 'SCA073';
      Name     : 'D' + #$00E9 + 'claration d''interface vide';
      ShortDesc: 'Une interface sans m' + #$00E9 + 'thode ni propri' + #$00E9 + 't' + #$00E9 +
        ' ne porte aucun contrat';
      FullDesc : ''
    ),
    // SCA074
    (
      RuleID   : 'SCA074';
      Name     : 'Assert sans message';
      ShortDesc: '`Assert(cond);` - ajouter un message `''pourquoi''` pour le diagnostic';
      FullDesc : ''
    ),
    // SCA075
    (
      RuleID   : 'SCA075';
      Name     : 'H' + #$00E9 + 'ritage explicite de TObject';
      ShortDesc: '`class(TObject)` est redondant - supprimer les parenth' + #$00E8 + 'ses';
      FullDesc : ''
    ),
    // SCA076
    (
      RuleID   : 'SCA076';
      Name     : 'D' + #$00E9 + 'claration group' + #$00E9 + 'e de variables, champs ou param' + #$00E8 +
        'tres';
      ShortDesc: 'S' + #$00E9 + 'parer `A, B: Type` en une d' + #$00E9 + 'claration par ligne';
      FullDesc : ''
    ),
    // SCA077
    (
      RuleID   : 'SCA077';
      Name     : 'Bloc begin..end vide';
      ShortDesc: '`begin..end` vide - le supprimer ou ' + #$00E9 + 'crire l''instruction';
      FullDesc : ''
    ),
    // SCA078
    (
      RuleID   : 'SCA078';
      Name     : 'Capture g' + #$00E9 + 'n' + #$00E9 + 'rale sur la classe racine Exception';
      ShortDesc: '`on E: Exception do` avale tout, y compris les violations d''acc' + #$00E8 + 's et l''' +
        #$00E9 + 'puisement m' + #$00E9 + 'moire';
      FullDesc : ''
    ),
    // SCA079
    (
      RuleID   : 'SCA079';
      Name     : 'Sections const/type/var cons' + #$00E9 + 'cutives';
      ShortDesc: 'Deux blocs `const`, `type` ou `var` qui se suivent devraient ' + #$00EA + 'tre fusionn' +
        #$00E9 + 's';
      FullDesc : ''
    ),
    // SCA080
    (
      RuleID   : 'SCA080';
      Name     : 'Exit/Continue redondant avant end';
      ShortDesc: '`Exit;` / `Continue;` juste avant `end` est sans effet';
      FullDesc : ''
    ),
    // SCA081
    (
      RuleID   : 'SCA081';
      Name     : 'Plusieurs d' + #$00E9 + 'clarations de classe dans un fichier';
      ShortDesc: 'Une classe par unit facilite le remaniement';
      FullDesc : ''
    ),
    // SCA082
    (
      RuleID   : 'SCA082';
      Name     : 'Point-virgule double';
      ShortDesc: '`;;` - supprimer le point-virgule superflu';
      FullDesc : ''
    ),
    // SCA083
    (
      RuleID   : 'SCA083';
      Name     : 'Bloc finally vide';
      ShortDesc: '`try ... finally end;` ne lib' + #$00E9 + 'r' + #$00E9 + ' rien - compl' + #$00E9 +
        'ter ou supprimer le finally';
      FullDesc : ''
    ),
    // SCA084
    (
      RuleID   : 'SCA084';
      Name     : 'Test Assigned + nil redondant';
      ShortDesc: '`Assigned(X) and (X <> nil)` - supprimer le test nil';
      FullDesc : ''
    ),
    // SCA085
    (
      RuleID   : 'SCA085';
      Name     : 'X.Free; X := nil; devrait ' + #$00EA + 'tre FreeAndNil(X)';
      ShortDesc: 'Utiliser `FreeAndNil(X)` au lieu de `X.Free; X := nil;`';
      FullDesc : ''
    ),
    // SCA086
    (
      RuleID   : 'SCA086';
      Name     : #$00C9 + 'viter le modificateur out';
      ShortDesc: 'Pr' + #$00E9 + 'f' + #$00E9 + 'rer `var` a `out` (out a une s' + #$00E9 +
        'mantique surprenante)';
      FullDesc : ''
    ),
    // SCA087
    (
      RuleID   : 'SCA087';
      Name     : 'Section de visibilit' + #$00E9 + ' vide dans la classe';
      ShortDesc: 'En-t' + #$00EA + 'te de section `public`/`private`/... sans aucun membre';
      FullDesc : ''
    ),
    // SCA088
    (
      RuleID   : 'SCA088';
      Name     : 'Initialisation d''unit ' + #$00E0 + ' l''ancienne begin..end.';
      ShortDesc: 'Utiliser `initialization..end.` plut' + #$00F4 + 't que l''ancien `begin..end.`';
      FullDesc : ''
    ),
    // SCA089
    (
      RuleID   : 'SCA089';
      Name     : 'Champ public dans la classe';
      ShortDesc: 'Un champ public rompt l''encapsulation - utiliser une propri' + #$00E9 + 't' + #$00E9;
      FullDesc : ''
    ),
    // SCA090
    (
      RuleID   : 'SCA090';
      Name     : 'Bloc try imbriqu' + #$00E9;
      ShortDesc: '`try..end` imbriqu' + #$00E9 + ' - extraire le try interne dans une m' + #$00E9 + 'thode';
      FullDesc : ''
    ),
    // SCA091
    (
      RuleID   : 'SCA091';
      Name     : 'Instruction case volumineuse';
      ShortDesc: '`case` avec 10 branches ou plus - envisager le polymorphisme ou une table de dispatch';
      FullDesc : ''
    ),
    // SCA092
    (
      RuleID   : 'SCA092';
      Name     : 'Unit sans aucune d' + #$00E9 + 'claration';
      ShortDesc: 'L''unit n''a ni type, ni const, ni var, ni proc' + #$00E9 +
        'dure/function - supprimer ou compl' + #$00E9 + 'ter';
      FullDesc : ''
    ),
    // SCA093
    (
      RuleID   : 'SCA093';
      Name     : 'Plusieurs appels inherited dans une m' + #$00E9 + 'thode';
      ShortDesc: 'Deux `inherited;` ou plus dans la m' + #$00EA + 'me m' + #$00E9 +
        'thode - les effets de bord du parent s''ex' + #$00E9 + 'cutent deux fois';
      FullDesc : ''
    ),
    // SCA094
    (
      RuleID   : 'SCA094';
      Name     : 'Doubles parenth' + #$00E8 + 'ses redondantes';
      ShortDesc: '`((Ident))` - supprimer les parenth' + #$00E8 + 'ses int' + #$00E9 + 'rieures';
      FullDesc : ''
    ),
    // SCA095
    (
      RuleID   : 'SCA095';
      Name     : 'Section de visibilit' + #$00E9 + ' r' + #$00E9 + 'p' + #$00E9 + 't' + #$00E9 + 'e';
      ShortDesc: 'La m' + #$00EA + 'me section `public`/`private`/... appara' + #$00EE +
        't deux fois dans une classe';
      FullDesc : ''
    ),
    // SCA096
    (
      RuleID   : 'SCA096';
      Name     : 'Constructeur sans appel a inherited';
      ShortDesc: 'Il manque `inherited Create` au constructeur - le parent reste non initialis' + #$00E9;
      FullDesc : ''
    ),
    // SCA097
    (
      RuleID   : 'SCA097';
      Name     : 'Destructeur sans appel a inherited';
      ShortDesc: 'Il manque `inherited Destroy` au destructeur - le nettoyage du parent est saut' + #$00E9 +
        ' (risque de fuite)';
      FullDesc : ''
    ),
    // SCA098
    (
      RuleID   : 'SCA098';
      Name     : 'Affectation conditionnelle redondante';
      ShortDesc: '`if Cond then X := True else X := False` devrait s''' + #$00E9 + 'crire `X := Cond`';
      FullDesc : ''
    ),
    // SCA099
    (
      RuleID   : 'SCA099';
      Name     : 'begin/end asym' + #$00E9 + 'trique dans if/else';
      ShortDesc: 'La branche then utilise `begin..end` mais la branche else est une instruction unique';
      FullDesc : ''
    ),
    // SCA100
    (
      RuleID   : 'SCA100';
      Name     : 'Alias de type pointeur sans pr' + #$00E9 + 'fixe P';
      ShortDesc: '`Foo = ^Bar` devrait s''' + #$00E9 + 'crire `PBar = ^Bar` (convention du pr' + #$00E9 +
        'fixe P)';
      FullDesc : ''
    ),
    // SCA101
    (
      RuleID   : 'SCA101';
      Name     : 'Branche sans bloc begin..end';
      ShortDesc: '`then`/`else`/`do <instruction>` - pr' + #$00E9 + 'f' + #$00E9 +
        'rer un `begin..end` explicite';
      FullDesc : ''
    ),
    // SCA102
    (
      RuleID   : 'SCA102';
      Name     : 'Routine imbriqu' + #$00E9 + 'e dans une m' + #$00E9 + 'thode';
      ShortDesc: 'Proc' + #$00E9 + 'dure ou fonction locale imbriqu' + #$00E9 +
        'e - a extraire au niveau de l''unit';
      FullDesc : ''
    ),
    // SCA103
    (
      RuleID   : 'SCA103';
      Name     : 'Champ de classe sans pr' + #$00E9 + 'fixe F';
      ShortDesc: 'Les champs de classe doivent suivre la convention `F<Nom>`';
      FullDesc : ''
    ),
    // SCA104
    (
      RuleID   : 'SCA104';
      Name     : 'Type classe ou record sans pr' + #$00E9 + 'fixe T';
      ShortDesc: 'Les alias de type classe et record doivent commencer par `T`';
      FullDesc : ''
    ),
    // SCA105
    (
      RuleID   : 'SCA105';
      Name     : 'Type interface sans pr' + #$00E9 + 'fixe I';
      ShortDesc: 'Les alias d''interface doivent commencer par `I` (`IFoo = interface`)';
      FullDesc : ''
    ),
    // SCA106
    (
      RuleID   : 'SCA106';
      Name     : 'M' + #$00E9 + 'thode pas en PascalCase';
      ShortDesc: 'Les m' + #$00E9 + 'thodes doivent commencer par une majuscule (PascalCase)';
      FullDesc : ''
    ),
    // SCA107
    (
      RuleID   : 'SCA107';
      Name     : 'Le membre public pourrait ' + #$00EA + 'tre strict private';
      ShortDesc: 'Le membre public n''est r' + #$00E9 + 'f' + #$00E9 + 'renc' + #$00E9 + ' QUE par des m' +
        #$00E9 +
        'thodes de sa propre classe - `strict private` atteint l''encapsulation la plus forte';
      FullDesc : ''
    ),
    // SCA108
    (
      RuleID   : 'SCA108';
      Name     : 'TThread.Synchronize depuis le destructeur';
      ShortDesc: 'Synchronize() appel' + #$00E9 + ' depuis le destructeur Destroy - un thread qui se lib' +
        #$00E8 + 're lui-m' + #$00EA + 'me y reste bloqu' + #$00E9 + ' jusqu''' + #$00E0 +
        ' ce que le thread principal ex' + #$00E9 + 'cute l''appel, et se fige s''il ne le fait pas';
      FullDesc : ''
    ),
    // SCA109
    (
      RuleID   : 'SCA109';
      Name     : 'Verrou pris sans lib' + #$00E9 + 'ration par try/finally';
      ShortDesc: 'TCriticalSection, Monitor ou verrou WinAPI pris sans try..finally englobant - une exception laisse le verrou pos' +
        #$00E9;
      FullDesc : ''
    ),
    // SCA110
    (
      RuleID   : 'SCA110';
      Name     : 'Concat' + #$00E9 + 'nation de cha' + #$00EE + 'ne dans une boucle';
      ShortDesc: '`s := s + x` dans for/while/repeat - r' + #$00E9 + 'allocations quadratiques';
      FullDesc : ''
    ),
    // SCA111
    (
      RuleID   : 'SCA111';
      Name     : 'ParamByName(...) appel' + #$00E9 + ' dans une boucle';
      ShortDesc: '`Query.ParamByName(''x'').AsXxx := ...` dans une boucle - recherche lin' + #$00E9 + 'aire ' +
        #$00E0 + ' chaque it' + #$00E9 + 'ration';
      FullDesc : ''
    ),
    // SCA112
    (
      RuleID   : 'SCA112';
      Name     : 'FieldByName(...) appel' + #$00E9 + ' dans une boucle';
      ShortDesc: '`DataSet.FieldByName(''x'').AsXxx` dans une boucle - recherche lin' + #$00E9 + 'aire ' +
        #$00E0 + ' chaque enregistrement';
      FullDesc : ''
    ),
    // SCA113
    (
      RuleID   : 'SCA113';
      Name     : 'TThread.Resume est obsol' + #$00E8 + 'te';
      ShortDesc: '`MyThread.Resume` - utiliser `MyThread.Start` (depuis Delphi 2010)';
      FullDesc : ''
    ),
    // SCA114
    (
      RuleID   : 'SCA114';
      Name     : 'TThread lib' + #$00E9 + 'r' + #$00E9 + ' par FreeAndNil - v' + #$00E9 + 'rifier l''arr' +
        #$00EA + 't';
      ShortDesc: '`FreeAndNil(MyThread)` sans `Terminate` ' + #$00E0 + ' proximit' + #$00E9 +
        ' - une indication ' + #$00E0 + ' v' + #$00E9 + 'rifier, pas un d' + #$00E9 + 'faut prouv' +
        #$00E9 + ' : `TThread.Destroy` arr' + #$00EA + 'te lui-m' + #$00EA + 'me le thread ; v' +
        #$00E9 + 'rifier `Execute`, le destructeur du thread et `FreeOnTerminate`';
      FullDesc : ''
    ),
    // SCA115
    (
      RuleID   : 'SCA115';
      Name     : 'URL HTTP en clair';
      ShortDesc: 'Litt' + #$00E9 + 'ral `''http://...''` pour un point d''acc' + #$00E8 + 's distant - vuln' +
        #$00E9 + 'rable a l''interception';
      FullDesc : ''
    ),
    // SCA116
    (
      RuleID   : 'SCA116';
      Name     : 'V' + #$00E9 + 'rification TLS d' + #$00E9 + 'sactiv' + #$00E9 + 'e';
      ShortDesc: '`SecureProtocols` vide, `IgnoreCertificateErrors := True` ou `OnVerifyPeer := nil`';
      FullDesc : ''
    ),
    // SCA117
    (
      RuleID   : 'SCA117';
      Name     : 'Membre public sans commentaire de documentation';
      ShortDesc: 'M' + #$00E9 + 'thode ou propri' + #$00E9 + 't' + #$00E9 +
        ' publique dans la section `interface` sans commentaire de documentation juste au-dessus';
      FullDesc : ''
    ),
    // SCA118
    (
      RuleID   : 'SCA118';
      Name     : 'Classe d''exception sans pr' + #$00E9 + 'fixe `E`';
      ShortDesc: 'Un descendant de `class(Exception)` doit suivre la convention `E<Nom>` de la RTL Delphi';
      FullDesc : ''
    ),
    // SCA119
    (
      RuleID   : 'SCA119';
      Name     : 'Constante locale pas en UPPER_SNAKE_CASE';
      ShortDesc: '`const X = 42;` dans une m' + #$00E9 + 'thode - pr' + #$00E9 + 'f' + #$00E9 +
        'rer UPPER_SNAKE_CASE pour les constantes num' + #$00E9 + 'riques';
      FullDesc : ''
    ),
    // SCA120
    (
      RuleID   : 'SCA120';
      Name     : 'Exception construite mais jamais lev' + #$00E9 + 'e';
      ShortDesc: '`EFoo.Create(''msg'');` alloue un objet exception sans `raise` - le chemin d''erreur est saut' +
        #$00E9 + ' silencieusement';
      FullDesc : ''
    ),
    // SCA121
    (
      RuleID   : 'SCA121';
      Name     : 'La fonction n''affecte jamais Result';
      ShortDesc: 'Le corps de la fonction se termine sans ' + #$00E9 +
        'crire `Result` (ni `<NomFonction> := ...`) - la valeur de retour est ind' + #$00E9 +
        'finie';
      FullDesc : ''
    ),
    // SCA122
    (
      RuleID   : 'SCA122';
      Name     : 'Relev' + #$00E9 + 'e de la variable d''exception li' + #$00E9 + 'e';
      ShortDesc: '`on E: T do ... raise E;` perd la pile d''appels d''origine - le `raise;` nu la conserve';
      FullDesc : ''
    ),
    // SCA123
    (
      RuleID   : 'SCA123';
      Name     : 'Transtypage juste avant Free / Destroy';
      ShortDesc: '`TFoo(x).Free` - le transtypage ne change pas quel Destroy s''ex' + #$00E9 +
        'cute (Destroy est virtuel)';
      FullDesc : ''
    ),
    // SCA124
    (
      RuleID   : 'SCA124';
      Name     : 'Constructeur appel' + #$00E9 + ' sur une instance au lieu de la classe';
      ShortDesc: '`obj.Create` - appelle le constructeur comme m' + #$00E9 +
        'thode sur une instance existante, saute l''allocation et r' + #$00E9 +
        'initialise les champs par-dessus des donn' + #$00E9 + 'es vivantes';
      FullDesc : ''
    ),
    // SCA125
    (
      RuleID   : 'SCA125';
      Name     : 'Red' + #$00E9 + 'finition dont le corps se r' + #$00E9 + 'duit a `inherited;`';
      ShortDesc: 'Une red' + #$00E9 + 'finition qui ne fait que transmettre au parent ne sert ' + #$00E0 +
        ' rien - la supprimer';
      FullDesc : ''
    ),
    // SCA126
    (
      RuleID   : 'SCA126';
      Name     : 'Utiliser Assigned() plut' + #$00F4 + 't que `= nil` / `<> nil`';
      ShortDesc: 'Convention Pascal : `Assigned(x)` et `not Assigned(x)` sont les tests nil canoniques';
      FullDesc : ''
    ),
    // SCA127
    (
      RuleID   : 'SCA127';
      Name     : 'Lev' + #$00E9 + 'e de la classe de base `Exception` au lieu d''une sous-classe';
      ShortDesc: '`raise Exception.Create(''...'')` - la classe de base ne porte aucune information s' +
        #$00E9 + 'mantique, les appelants ne peuvent pas filtrer s' + #$00E9 + 'lectivement';
      FullDesc : ''
    ),
    // SCA128
    (
      RuleID   : 'SCA128';
      Name     : 'Appel de formatage d' + #$00E9 + 'pendant de la locale sans TFormatSettings';
      ShortDesc: '`StrToDate(s)`, `FormatFloat(...)` et consorts sans TFormatSettings d' + #$00E9 +
        'pendent de la locale syst' + #$00E8 + 'me - le r' + #$00E9 +
        'sultat change d''une machine ou d''un utilisateur ' + #$00E0 + ' l''autre';
      FullDesc : ''
    ),
    // SCA129
    (
      RuleID   : 'SCA129';
      Name     : 'Transtypage de cha' + #$00EE + 'ne vers un type 8 bits sans encodage explicite';
      ShortDesc: '`AnsiString(s)` / `RawByteString(s)` / `ShortString(s)` supprime silencieusement les caract' +
        #$00E8 + 'res hors de la page de codes active';
      FullDesc : ''
    ),
    // SCA130
    (
      RuleID   : 'SCA130';
      Name     : 'Transtypage d''un Char en PChar : le point de code devient une adresse';
      ShortDesc: '`PChar(''A'')` n''est pas `PChar("A")` - le transtypage traite le point de code 16 bits comme une adresse m' +
        #$00E9 + 'moire brute';
      FullDesc : ''
    ),
    // SCA131
    (
      RuleID   : 'SCA131';
      Name     : 'IfThen() ' + #$00E9 + 'value les deux branches - pas de court-circuit';
      ShortDesc: '`Math.IfThen(cond, A(), B())` et `StrUtils.IfThen` sont des fonctions ordinaires - les deux bras s''ex' +
        #$00E9 + 'cutent avant l''appel';
      FullDesc : ''
    ),
    // SCA132
    (
      RuleID   : 'SCA132';
      Name     : 'except on E: Exception attrape toutes les erreurs';
      ShortDesc: '`on E: Exception do ...` attrape la classe de base et donc tous ses descendants, y compris les exceptions syst' +
        #$00E8 + 'me qui ne doivent pas ' + #$00EA + 'tre ' + #$00E9 + 'touff' + #$00E9 +
        'es (EOutOfMemory, EAccessViolation, EAbort)';
      FullDesc : ''
    ),
    // SCA133
    (
      RuleID   : 'SCA133';
      Name     : 'raise nu hors d''un gestionnaire except/on';
      ShortDesc: '`raise;` sans expression d''exception n''est valide qu''' + #$00E0 + ' l''int' + #$00E9 +
        'rieur d''un gestionnaire except (pour relancer l''exception) - ailleurs, Delphi (E2145) et FPC le refusent';
      FullDesc : ''
    ),
    // SCA134
    (
      RuleID   : 'SCA134';
      Name     : 'Variable utilisee apr' + #$00E8 + 's Free / FreeAndNil';
      ShortDesc: 'D' + #$00E9 + 'r' + #$00E9 + 'f' + #$00E9 + 'rencer une variable apr' + #$00E8 +
        's `Free` ou `FreeAndNil` lit un pointeur pendant et provoque une violation d''acc' + #$00E8 +
        's';
      FullDesc : ''
    ),
    // SCA135
    (
      RuleID   : 'SCA135';
      Name     : 'Classe concr' + #$00E8 + 'te h' + #$00E9 + 'ritant d''une m' + #$00E9 +
        'thode abstraite sans override';
      ShortDesc: 'La classe d' + #$00E9 + 'rive d''une base ayant une m' + #$00E9 +
        'thode `abstract` mais ne la red' + #$00E9 + 'finit pas - l''appel sur l''instance l' +
        #$00E8 + 've EAbstractError ' + #$00E0 + ' l''ex' + #$00E9 + 'cution';
      FullDesc : ''
    ),
    // SCA136
    (
      RuleID   : 'SCA136';
      Name     : 'Constructeur qui alloue des champs et l' + #$00E8 + 've sans try/except';
      ShortDesc: 'Le constructeur affecte des champs par `<Classe>.Create` puis l' + #$00E8 +
        've sans try/except - les champs fuient si le destructeur ne les lib' + #$00E8 + 're pas';
      FullDesc : ''
    ),
    // SCA137
    (
      RuleID   : 'SCA137';
      Name     : 'Cible Int64 recevant le produit de deux op' + #$00E9 + 'randes 32 bits';
      ShortDesc: '`<var-Int64> := <a> * <b>` ' + #$00E9 + 'value la multiplication en 32 bits avant l''' +
        #$00E9 + 'largissement - un d' + #$00E9 + 'passement tronque silencieusement';
      FullDesc : ''
    ),
    // SCA138
    (
      RuleID   : 'SCA138';
      Name     : 'La classe a trop de m' + #$00E9 + 'thodes ou de champs';
      ShortDesc: 'Une classe de plus de 20 m' + #$00E9 +
        'thodes ou de plus de 15 champs d''instance concentre trop de responsabilit' + #$00E9 +
        's - difficile ' + #$00E0 + ' tester, ' + #$00E0 + ' faire ' + #$00E9 + 'voluer et ' +
        #$00E0 + ' relire';
      FullDesc : ''
    ),
    // SCA139
    (
      RuleID   : 'SCA139';
      Name     : 'Free sans mise ' + #$00E0 + ' nil ensuite';
      ShortDesc: '`obj.Free;` sans `obj := nil;` (ni FreeAndNil) laisse un pointeur pendant - toute utilisation ult' +
        #$00E9 + 'rieure est un Use-After-Free';
      FullDesc : ''
    ),
    // SCA140
    (
      RuleID   : 'SCA140';
      Name     : 'La m' + #$00E9 + 'thode a trop d''instructions Exit';
      ShortDesc: 'Une m' + #$00E9 + 'thode avec plus de 6 appels ' + #$00E0 +
        ' Exit a trop de chemins de sortie - difficile ' + #$00E0 + ' lire, difficile ' + #$00E0 +
        ' tester, facile d''en oublier un';
      FullDesc : ''
    ),
    // SCA141
    (
      RuleID   : 'SCA141';
      Name     : 'L''implementation de la classe d' + #$00E9 + 'passe 500 lignes';
      ShortDesc: 'Une classe dont la d' + #$00E9 + 'claration et les m' + #$00E9 +
        'thodes d''implementation totalisent plus de 500 lignes a trop de responsabilit' + #$00E9 +
        's';
      FullDesc : ''
    ),
    // SCA142
    (
      RuleID   : 'SCA142';
      Name     : 'La clause uses n''est pas dans l''ordre alphab' + #$00E9 + 'tique';
      ShortDesc: 'Les entr' + #$00E9 + 'es d''une clause `uses` ne sont pas dans l''ordre alphab' + #$00E9 +
        'tique - les fusions deviennent non d' + #$00E9 +
        'terministes et la relecture plus difficile';
      FullDesc : ''
    ),
    // SCA143
    (
      RuleID   : 'SCA143';
      Name     : 'L''unit n''a pas de commentaire d''en-t' + #$00EA + 'te descriptif';
      ShortDesc: 'L''unit commence directement par `interface`, sans bloc de commentaire explicatif entre `unit ...;` et `interface`';
      FullDesc : ''
    ),
    // SCA144
    (
      RuleID   : 'SCA144';
      Name     : 'Comparaison d''' + #$00E9 + 'galit' + #$00E9 + ' ou d''in' + #$00E9 + 'galit' + #$00E9 +
        ' entre flottants';
      ShortDesc: '`a = b` ou `a <> b` entre Single/Double/Extended n''est pas fiable a cause de l''arrondi IEEE-754 - utiliser SameValue ou Math.IsZero';
      FullDesc : ''
    ),
    // SCA145
    (
      RuleID   : 'SCA145';
      Name     : 'raise dans un destructeur sans try/except';
      ShortDesc: 'Un `raise` non prot' + #$00E9 + 'g' + #$00E9 + ' dans un destructeur interrompt la cha' +
        #$00EE + 'ne de nettoyage - inherited Destroy et les FreeAndNil suivants sont saut' + #$00E9 +
        's, l''' + #$00E9 + 'tat reste incoh' + #$00E9 + 'rent';
      FullDesc : ''
    ),
    // SCA146
    (
      RuleID   : 'SCA146';
      Name     : 'Param' + #$00E8 + 'tre bool' + #$00E9 + 'en servant d''aiguillage interne';
      ShortDesc: 'Un param' + #$00E8 + 'tre bool' + #$00E9 +
        'en dont la valeur choisit entre deux chemins de code compl' + #$00E8 + 'tement diff' +
        #$00E9 + 'rents est une strat' + #$00E9 + 'gie d' + #$00E9 + 'guis' + #$00E9 + 'e - pr' +
        #$00E9 + 'f' + #$00E9 + 'rer deux m' + #$00E9 + 'thodes aux noms parlants';
      FullDesc : ''
    ),
    // SCA147
    (
      RuleID   : 'SCA147';
      Name     : 'M' + #$00E9 + 'thode priv' + #$00E9 + 'e sans appelant dans l''unit';
      ShortDesc: 'Une m' + #$00E9 + 'thode priv' + #$00E9 + 'e que nulle autre m' + #$00E9 + 'thode de la m' +
        #$00EA + 'me unit ne r' + #$00E9 + 'f' + #$00E9 +
        'rence est du code mort - la supprimer ou la brancher';
      FullDesc : ''
    ),
    // SCA148
    (
      RuleID   : 'SCA148';
      Name     : 'M' + #$00E9 + 'thode d''instance n''acc' + #$00E9 + 'dant jamais a Self - pourrait ' +
        #$00EA + 'tre de classe';
      ShortDesc: 'Une m' + #$00E9 + 'thode qui n''utilise que ses param' + #$00E8 +
        'tres (ni Self, ni champs d''instance, ni cha' + #$00EE +
        'ne virtuelle) est fonctionnellement une m' + #$00E9 + 'thode de classe - la d' + #$00E9 +
        'clarer comme telle';
      FullDesc : ''
    ),
    // SCA149
    (
      RuleID   : 'SCA149';
      Name     : 'La m' + #$00E9 + 'thode masque une m' + #$00E9 + 'thode virtuelle parente sans `override`';
      ShortDesc: 'Une m' + #$00E9 + 'thode red' + #$00E9 + 'clar' + #$00E9 + 'e dans une classe d' + #$00E9 +
        'riv' + #$00E9 + 'e avec le m' + #$00EA + 'me nom qu''une m' + #$00E9 +
        'thode parente virtuelle ou dynamique, mais sans `override`, casse le polymorphisme - le compilateur ' +
        #$00E9 + 'met W1010';
      FullDesc : ''
    ),
    // SCA150
    (
      RuleID   : 'SCA150';
      Name     : 'La comparaison bool' + #$00E9 + 'enne est toujours vraie / toujours fausse';
      ShortDesc: 'Des comparaisons comme `Length(s) >= 0` sont des tautologies - le r' + #$00E9 +
        'sultat de Length n''est jamais n' + #$00E9 + 'gatif, la condition ne peut donc jamais ' +
        #$00EA + 'tre fausse';
      FullDesc : ''
    ),
    // SCA151
    (
      RuleID   : 'SCA151';
      Name     : 'La fonction renvoie toujours le m' + #$00EA + 'me litt' + #$00E9 + 'ral';
      ShortDesc: 'Tous les chemins de la fonction affectent le m' + #$00EA + 'me litt' + #$00E9 +
        'ral a Result - la logique conditionnelle ne change rien au comportement, remplacer la fonction par une constante';
      FullDesc : ''
    ),
    // SCA152
    (
      RuleID   : 'SCA152';
      Name     : 'Texte visible par l''utilisateur affect' + #$00E9 + ' en litt' + #$00E9 + 'ral';
      ShortDesc: 'Les affectations a Caption/Hint/Text et les appels a ShowMessage/MessageDlg avec du texte litt' +
        #$00E9 + 'ral contournent resourcestring et i18n - la cha' + #$00EE +
        'ne n''est pas traduisible';
      FullDesc : ''
    ),
    // SCA153
    (
      RuleID   : 'SCA153';
      Name     : 'Paire Lock/Unlock sans try/finally';
      ShortDesc: 'Lock / EnterCriticalSection / TMonitor.Enter avec sa lib' + #$00E9 + 'ration dans la m' +
        #$00EA + 'me routine mais sans try/finally - le chemin d''exception laisse le verrou pos' +
        #$00E9 + ' et bloque l''appelant suivant';
      FullDesc : ''
    ),
    // SCA154
    (
      RuleID   : 'SCA154';
      Name     : 'Move/FillChar avec SizeOf d''un type pointeur';
      ShortDesc: 'Move, FillChar, CopyMemory ou ZeroMemory appel' + #$00E9 +
        ' avec SizeOf(PXxx) ou PXxx est un type pointeur - ne copie que 4 ou 8 octets (la taille du pointeur) au lieu du tampon vis' +
        #$00E9;
      FullDesc : ''
    ),
    // SCA155
    (
      RuleID   : 'SCA155';
      Name     : 'Instruction with sur plusieurs cibles';
      ShortDesc: '`with A, B do` (deux receveurs ou plus s' + #$00E9 + 'par' + #$00E9 +
        's par des virgules) rend la resolution des membres ambigu' + #$00EB + ' - ajouter une m' +
        #$00E9 + 'thode ' + #$00E0 + ' A ou ' + #$00E0 +
        ' B change silencieusement le sens du corps';
      FullDesc : ''
    ),
    // SCA156
    (
      RuleID   : 'SCA156';
      Name     : 'GetMem / AllocMem sans try/finally';
      ShortDesc: 'GetMem / AllocMem / ReallocMem suivi du FreeMem correspondant dans la m' + #$00EA +
        'me routine mais sans try/finally englobant - le chemin d''exception perd le tampon d' +
        #$00E9 + 'finitivement';
      FullDesc : ''
    ),
    // SCA157
    (
      RuleID   : 'SCA157';
      Name     : 'SetLength(arr, Length(arr) + N) dans une boucle';
      ShortDesc: 'Agrandir un tableau dynamique d''un ' + #$00E9 + 'l' + #$00E9 +
        'ment (ou de N) dans une boucle for/while/repeat co' + #$00FB +
        'te quadratiquement - agrandir une fois avant la boucle ou proc' + #$00E9 + 'der par blocs';
      FullDesc : ''
    ),
    // SCA158
    (
      RuleID   : 'SCA158';
      Name     : 'PChar(s) +/- d' + #$00E9 + 'calage sans test de cha' + #$00EE + 'ne vide';
      ShortDesc: '`PChar(s) + n` et variantes sans test pr' + #$00E9 + 'alable de `s` vide - pour une cha' +
        #$00EE + 'ne plus courte que n, le pointeur pointe au-del' + #$00E0 + ' du terminateur';
      FullDesc : ''
    ),
    // SCA159
    (
      RuleID   : 'SCA159';
      Name     : 'Gestionnaire d''exception typ' + #$00E9 + 'e au corps vide';
      ShortDesc: '`on E: SomeException do ;` avale silencieusement une classe d''exception pr' + #$00E9 +
        'cise - pire qu''un `except end` nu, car l''annotation typ' + #$00E9 + 'e a l''air d' +
        #$00E9 + 'lib' + #$00E9 + 'r' + #$00E9 + 'e';
      FullDesc : ''
    ),
    // SCA160
    (
      RuleID   : 'SCA160';
      Name     : 'Transtypage en cha' + #$00EE + 'ne depuis un pointeur brut';
      ShortDesc: '`string(P)` et variantes depuis un pointeur pr' + #$00E9 +
        'fixe P supposent un terminateur nul qui peut ne pas exister - lecture au-del' + #$00E0 +
        ' du tas';
      FullDesc : ''
    ),
    // SCA161
    (
      RuleID   : 'SCA161';
      Name     : 'Soustraction de pointeurs via un transtypage 32 bits';
      ShortDesc: '`Cardinal(P1) - Cardinal(P2)` (ou Integer/LongWord/LongInt) tronque les 32 bits de poids fort d''un pointeur 64 bits sous Win64 - la diff' +
        #$00E9 + 'rence est parfois fausse';
      FullDesc : ''
    ),
    // SCA162
    (
      RuleID   : 'SCA162';
      Name     : 'Utilisation d''un algorithme cryptographique faible ou obsol' + #$00E8 + 'te';
      ShortDesc: 'Nom d''algorithme (''MD5'', ''SHA1'', ''DES'', ''RC4'', ''TLS1.0'', ''SSLv3'') ou classe d''encapsulation (THashMD5, TIdHashSHA1, ...) r' +
        #$00E9 + 'f' + #$00E9 + 'renc' + #$00E9 + 'e - vuln' + #$00E9 +
        'rable aux collisions et aux attaques a texte clair connu';
      FullDesc : ''
    ),
    // SCA163
    (
      RuleID   : 'SCA163';
      Name     : 'API shell appel' + #$00E9 + 'e avec concat' + #$00E9 + 'nation dans les arguments';
      ShortDesc: 'ShellExecute / CreateProcess / WinExec avec `+` dans les arguments - si un op' + #$00E9 +
        'rande est contr' + #$00F4 + 'lable, cela devient un vecteur d''injection de commande';
      FullDesc : ''
    ),
    // SCA164
    (
      RuleID   : 'SCA164';
      Name     : 'Routine de premier niveau jamais appel' + #$00E9 + 'e';
      ShortDesc: 'Une proc' + #$00E9 + 'dure ou fonction autonome de la section implementation n''est appel' +
        #$00E9 + 'e nulle part dans l''unit et n''est pas export' + #$00E9 +
        'e par la section interface - code mort';
      FullDesc : ''
    ),
    // SCA165
    (
      RuleID   : 'SCA165';
      Name     : 'Marqueur noinspection inutilis' + #$00E9;
      ShortDesc: 'Un `// noinspection X` ne supprime aucun r' + #$00E9 +
        'sultat sur sa ligne cible - soit le d' + #$00E9 + 'tecteur s''est am' + #$00E9 + 'lior' +
        #$00E9 + ', soit la cible ' + #$00E9 + 'tait mauvaise';
      FullDesc : ''
    ),
    // SCA166
    (
      RuleID   : 'SCA166';
      Name     : 'Variable locale non initialis' + #$00E9 + 'e';
      ShortDesc: 'Variable locale lue avant sa premi' + #$00E8 +
        're affectation dans l''ordre du source, ou jamais affect' + #$00E9 + 'e';
      FullDesc : ''
    ),
    // SCA167
    (
      RuleID   : 'SCA167';
      Name     : 'Appel a Random sans Randomize pr' + #$00E9 + 'alable';
      ShortDesc: 'Random / RandomRange / RandomFrom sans Randomize - un germe a 0 produit la m' + #$00EA +
        'me suite ' + #$00E0 + ' chaque ex' + #$00E9 + 'cution';
      FullDesc : ''
    ),
    // SCA168
    (
      RuleID   : 'SCA168';
      Name     : 'Instruction case sans branche else';
      ShortDesc: 'L''instruction case n''a pas de branche else - les valeurs non trait' + #$00E9 +
        'es passent silencieusement ; un else suivant un if dans le dernier bras est le else du case';
      FullDesc : ''
    ),
    // SCA169
    (
      RuleID   : 'SCA169';
      Name     : 'L''argument d''Assert contient un appel a effet de bord';
      ShortDesc: 'Assert(SomeCall) - l''appel dispara' + #$00EE +
        't en build Release et son effet de bord est perdu silencieusement';
      FullDesc : ''
    ),
    // SCA170
    (
      RuleID   : 'SCA170';
      Name     : 'Param' + #$00E8 + 'tre string sans const';
      ShortDesc: 'Param' + #$00E8 + 'tre string d' + #$00E9 + 'clar' + #$00E9 +
        ' sans const - provoque une incr' + #$00E9 + 'mentation du compteur de r' + #$00E9 + 'f' +
        #$00E9 + 'rences ' + #$00E0 + ' chaque appel';
      FullDesc : ''
    ),
    // SCA171
    (
      RuleID   : 'SCA171';
      Name     : 'Directive de compilation OFF sans ON correspondant dans le fichier';
      ShortDesc: '{$WARNINGS OFF} (ou HINTS/RANGECHECKS/...) sans ON de fermeture - d' + #$00E9 +
        'borde sur les units suivantes';
      FullDesc : ''
    ),
    // SCA172
    (
      RuleID   : 'SCA172';
      Name     : 'Propri' + #$00E9 + 't' + #$00E9 + ' bool' + #$00E9 + 'enne sans pr' + #$00E9 +
        'fixe Is / Has / Can / Should';
      ShortDesc: 'Le nom de la propri' + #$00E9 + 't' + #$00E9 + ' bool' + #$00E9 +
        'enne se lit comme un substantif - pr' + #$00E9 + 'f' + #$00E9 + 'rer un pr' + #$00E9 +
        'fixe verbal qui se lit comme une question';
      FullDesc : ''
    ),
    // SCA173
    (
      RuleID   : 'SCA173';
      Name     : 'Variant dans une m' + #$00E9 + 'thode sensible aux performances (avec boucle)';
      ShortDesc: 'Variable Variant dans une m' + #$00E9 + 'thode contenant une boucle - chaque op' + #$00E9 +
        'ration Variant paie un surco' + #$00FB + 't de dispatch COM de 10 ' + #$00E0 + ' 100 fois';
      FullDesc : ''
    ),
    // SCA174
    (
      RuleID   : 'SCA174';
      Name     : 'TList<T> rempli de T.Create - les ' + #$00E9 + 'l' + #$00E9 + 'ments fuient a la lib' +
        #$00E9 + 'ration';
      ShortDesc: 'TList<TFoo>.Create plus Add(TFoo.Create) - la liste ne poss' + #$00E8 + 'de pas ses ' +
        #$00E9 + 'l' + #$00E9 + 'ments, chaque instance TFoo fuit';
      FullDesc : ''
    ),
    // SCA175
    (
      RuleID   : 'SCA175';
      Name     : 'M' + #$00E9 + 'thode anonyme capturant la variable de boucle par r' + #$00E9 + 'f' + #$00E9 +
        'rence';
      ShortDesc: 'Une m' + #$00E9 + 'thode anonyme dans `for i := ... do` r' + #$00E9 + 'f' + #$00E9 +
        'rence i - toutes les closures voient la m' + #$00EA + 'me valeur finale';
      FullDesc : ''
    ),
    // SCA176
    (
      RuleID   : 'SCA176';
      Name     : 'M' + #$00E9 + 'thode a forte complexit' + #$00E9 + ' cognitive (flot de contr' + #$00F4 +
        'le imbriqu' + #$00E9 + ')';
      ShortDesc: 'La complexit' + #$00E9 + ' cognitive (style Sonar) d' + #$00E9 +
        'passe 15 - les if/for/while/case imbriqu' + #$00E9 + 's sont difficiles ' + #$00E0 +
        ' suivre mentalement';
      FullDesc : ''
    ),
    // SCA177
    (
      RuleID   : 'SCA177';
      Name     : 'Variable de thread utilisee apr' + #$00E8 + 's FreeOnTerminate := True';
      ShortDesc: 'Apr' + #$00E8 + 's T.FreeOnTerminate := True, tout acc' + #$00E8 + 's ult' + #$00E9 +
        'rieur ' + #$00E0 + ' T.Field/T.Method risque une Access Violation si le thread s''est d' +
        #$00E9 + 'j' + #$00E0 + ' auto-d' + #$00E9 + 'truit';
      FullDesc : ''
    ),
    // SCA178
    (
      RuleID   : 'SCA178';
      Name     : 'API d''ouverture de fichier recevant une saisie utilisateur concat' + #$00E9 + 'n' + #$00E9 +
        'e';
      ShortDesc: 'Ouverture de fichier (TFileStream.Create, AssignFile, ...) avec un chemin construit ' +
        #$00E0 +
        ' partir d''une saisie utilisateur (Edit.Text, Request.Params, ...) - risque de path traversal';
      FullDesc : ''
    ),
    // SCA179
    (
      RuleID   : 'SCA179';
      Name     : 'Attribut DUnitX [Ignore] sans argument de justification';
      ShortDesc: '[Ignore] sans argument cha' + #$00EE +
        'ne ignore le test silencieusement - ajouter un message expliquant pourquoi il est d' +
        #$00E9 + 'sactiv' + #$00E9;
      FullDesc : ''
    ),
    // SCA180
    (
      RuleID   : 'SCA180';
      Name     : 'Le m' + #$00EA + 'me attribut applique deux fois au m' + #$00EA + 'me membre';
      ShortDesc: 'Deux attributs [X] identiques sur le m' + #$00EA +
        'me membre - reste de copier-coller, sans effet';
      FullDesc : ''
    ),
    // SCA181
    (
      RuleID   : 'SCA181';
      Name     : 'Attribut DUnitX [Category] sans nom de cat' + #$00E9 + 'gorie';
      ShortDesc: '[Category] sans argument est une erreur de compilation dans DUnitX - toujours passer un nom de cat' +
        #$00E9 + 'gorie';
      FullDesc : ''
    ),
    // SCA182
    (
      RuleID   : 'SCA182';
      Name     : 'Classe [TestFixture] sans aucune m' + #$00E9 + 'thode [Test]';
      ShortDesc: 'La classe est marqu' + #$00E9 + 'e [TestFixture] mais ne contient aucune m' + #$00E9 +
        'thode [Test] - fixture zombie, visible dans TestInsight mais qui n''ex' + #$00E9 +
        'cute rien';
      FullDesc : ''
    ),
    // SCA183
    (
      RuleID   : 'SCA183';
      Name     : 'Attribut suivi d''une ligne vide avant le membre cible';
      ShortDesc: 'Ligne d''attribut suivie d''une ligne vide - visuellement d' + #$00E9 + 'tach' + #$00E9 +
        'e, souvent un reste de refactoring';
      FullDesc : ''
    ),
    // SCA184
    (
      RuleID   : 'SCA184';
      Name     : 'Composant DFM inutilis' + #$00E9;
      ShortDesc: 'Le composant DFM n''est r' + #$00E9 + 'f' + #$00E9 + 'renc' + #$00E9 +
        ' ni dans le code, ni dans d''autres units, ni dans le DFM lui-m' + #$00EA +
        'me - probablement un reste de refactoring';
      FullDesc : ''
    ),
    // SCA185
    (
      RuleID   : 'SCA185';
      Name     : 'Fichier source UTF-8 sans BOM';
      ShortDesc: 'Fichier UTF-8 sans BOM contenant du non-ASCII - le compilateur le lit comme de l''ANSI (mojibake)';
      FullDesc : ''
    ),
    // SCA186
    (
      RuleID   : 'SCA186';
      Name     : 'S' + #$00E9 + 'quence UTF-8 invalide dans le fichier source';
      ShortDesc: 'UTF-8 mal forme (surlong, substitut ou hors plage) sous un BOM UTF-8';
      FullDesc : ''
    ),
    // SCA187
    (
      RuleID   : 'SCA187';
      Name     : 'Octet NUL ou de contr' + #$00F4 + 'le dans le fichier source';
      ShortDesc: 'NUL ou octet de contr' + #$00F4 + 'le interdit - fichier binaire ou encodage mal d' +
        #$00E9 + 'tect' + #$00E9;
      FullDesc : ''
    ),
    // SCA188
    (
      RuleID   : 'SCA188';
      Name     : 'Caract' + #$00E8 + 're de contr' + #$00F4 + 'le bidirectionnel (Trojan Source)';
      ShortDesc: 'Caract' + #$00E8 + 're de contr' + #$00F4 +
        'le bidi override ou isolate - le source se lit autrement qu''il ne compile';
      FullDesc : ''
    ),
    // SCA189
    (
      RuleID   : 'SCA189';
      Name     : 'Fichier source ANSI avec du contenu non-ASCII';
      ShortDesc: 'Source 8 bits (sans BOM, pas de l''UTF-8 valide) - d' + #$00E9 +
        'pendant de la page de codes, non portable';
      FullDesc : ''
    ),
    // SCA190
    (
      RuleID   : 'SCA190';
      Name     : 'Fichier source UTF-16';
      ShortDesc: 'Source UTF-16 - compile, mais inhabituel et peu commode pour les outils texte';
      FullDesc : ''
    ),
    // SCA191
    (
      RuleID   : 'SCA191';
      Name     : 'Fichier source UTF-32 / UCS-4';
      ShortDesc: 'Source UTF-32 - le compilateur Delphi le rejette avec l''erreur fatale F2438';
      FullDesc : ''
    ),
    // SCA192
    (
      RuleID   : 'SCA192';
      Name     : 'Caract' + #$00E8 + 're invisible ou de largeur nulle dans le source';
      ShortDesc: 'Caract' + #$00E8 + 're Unicode invisible ou de largeur nulle - vecteur de texte cach' +
        #$00E9 + ' et d''abus par homoglyphes';
      FullDesc : ''
    ),
    // SCA193
    (
      RuleID   : 'SCA193';
      Name     : 'Caract' + #$00E8 + 're non-ASCII dans un identifiant';
      ShortDesc: 'L''identifiant contient une lettre non-ASCII - risque d''homoglyphes et de caract' + #$00E8 +
        'res confondables';
      FullDesc : ''
    ),
    // SCA194
    (
      RuleID   : 'SCA194';
      Name     : 'Fichier source hors du projet';
      ShortDesc: 'Un fichier .pas/.dfm se trouve dans le dossier du projet mais n''est pas r' + #$00E9 + 'f' +
        #$00E9 + 'renc' + #$00E9 +
        ' par le projet (.dproj/.groupproj) - probablement un fichier source orphelin';
      FullDesc : ''
    ),
    // SCA195
    (
      RuleID   : 'SCA195';
      Name     : 'Unit utilisee par le projet mais non incluse dedans';
      ShortDesc: 'Un fichier .pas est tir' + #$00E9 + ' par les units du projet via uses (il compile gr' +
        #$00E2 +
        'ce au chemin de recherche) mais n''est pas liste dans le fichier projet (.dproj/.groupproj) - l''ajouter au projet';
      FullDesc : ''
    ),
    // SCA196
    (
      RuleID   : 'SCA196';
      Name     : 'Result de type manag' + #$00E9 + ' est lu avant d''avoir ' + #$00E9 + 't' + #$00E9 +
        ' affect' + #$00E9;
      ShortDesc: 'Le Result d''un type de retour manag' + #$00E9 + ' est lu avant la premi' + #$00E8 +
        're affectation - il est un alias de la variable cible de l''appelant et porte son ANCIENNE valeur. L''initialiser d''abord (nil / [] / '''')';
      FullDesc : ''
    ),
    // SCA197
    (
      RuleID   : 'SCA197';
      Name     : 'Interface d' + #$00E9 + 'clar' + #$00E9 + 'e sans GUID';
      ShortDesc: 'L''interface n''a pas de GUID - Supports() et QueryInterface() ne peuvent pas la demander ' +
        #$00E0 + ' l''ex' + #$00E9 + 'cution. En g' + #$00E9 + 'n' + #$00E9 +
        'rer un avec Ctrl+Maj+G';
      FullDesc : ''
    ),
    // SCA198
    (
      RuleID   : 'SCA198';
      Name     : 'Deux interfaces partagent le m' + #$00EA + 'me GUID';
      ShortDesc: 'Le m' + #$00EA +
        'me GUID figure sur plusieurs interfaces - Supports() renvoie celle enregistr' + #$00E9 +
        'e en premier, sans erreur de compilation. En g' + #$00E9 + 'n' + #$00E9 +
        'rer un nouveau avec Ctrl+Maj+G';
      FullDesc : ''
    ),
    // SCA199
    (
      RuleID   : 'SCA199';
      Name     : 'Le nom pass' + #$00E9 + ' ' + #$00E0 + ' ParamByName ne correspond pas aux param' + #$00E8 +
        'tres du SQL';
      ShortDesc: 'ParamByName(''x'') sur une requ' + #$00EA + 'te dont le SQL n''a pas de :x (erreur ' +
        #$00AB + ' param' + #$00E8 + 'tre introuvable ' + #$00BB + ' ' + #$00E0 + ' l''ex' + #$00E9 +
        'cution), ou un :y dans le SQL que la routine n''affecte jamais alors qu''elle renseigne les autres param' +
        #$00E8 + 'tres de la requ' + #$00EA + 'te';
      FullDesc : ''
    ),
    // SCA200
    (
      RuleID   : 'SCA200';
      Name     : 'Adresse IP en litt' + #$00E9 + 'ral de cha' + #$00EE + 'ne';
      ShortDesc: 'Adresse IPv4 ou IPv6 cod' + #$00E9 + 'e en dur (priv' + #$00E9 + 'e, partag' + #$00E9 +
        'e ou publique) dans un litt' + #$00E9 + 'ral de cha' + #$00EE + 'ne - la d' + #$00E9 +
        'placer dans la configuration ou utiliser un nom d''h' + #$00F4 + 'te';
      FullDesc : ''
    ),
    // SCA201
    (
      RuleID   : 'SCA201';
      Name     : 'Adresse IP dans un fichier de configuration versionn' + #$00E9;
      ShortDesc: 'Adresse IPv4 ou IPv6 (priv' + #$00E9 + 'e, partag' + #$00E9 +
        'e ou publique) comme valeur dans un fichier .ini de l''arborescence des sources';
      FullDesc : ''
    ),
    // SCA202
    (
      RuleID   : 'SCA202';
      Name     : 'not, and, or ou xor s''applique avant la comparaison';
      ShortDesc: '''not Count > 0'' ou ''A = True or B = False'' - not/and/or/xor sont prioritaires sur les comparaisons, l''expression compile mais teste autre chose';
      FullDesc : ''
    ),
    // SCA203
    (
      RuleID   : 'SCA203';
      Name     : 'La boucle for d' + #$00E9 + 'passe le dernier indice';
      ShortDesc: 'La boucle for va jusqu''' + #$00E0 + ' Count, Length() ou High() + 1 et indexe la m' +
        #$00EA + 'me collection avec la variable de boucle - le dernier passage est hors limites';
      FullDesc : ''
    ),
    // SCA204
    (
      RuleID   : 'SCA204';
      Name     : 'R' + #$00E9 + 'sultat affect' + #$00E9 + ' via le nom de la fonction';
      ShortDesc: 'R' + #$00E9 + 'sultat de la fonction d' + #$00E9 + 'fini par affectation ' + #$00E0 +
        ' son nom (''GetCount := ...'') - l''ancienne forme Pascal ; Delphi ' + #$00E9 +
        'crit Result';
      FullDesc : ''
    ),
    // SCA205
    (
      RuleID   : 'SCA205';
      Name     : 'Le nom de la fonction lu dans son propre corps est un appel r' + #$00E9 + 'cursif';
      ShortDesc: '''Total := Total + X'' dans la fonction Total : ' + #$00E0 +
        ' droite, le nom est un appel r' + #$00E9 + 'cursif, pas le r' + #$00E9 + 'sultat courant';
      FullDesc : ''
    )
  );

