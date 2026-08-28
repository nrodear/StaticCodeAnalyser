// ==========================================================================
// GENERIERT von tools/gen-rules-inc.py - NICHT VON HAND EDITIEREN.
// Quelle: rules/sca-rules.<lang>.json (dort aendern, Generator laufen lassen)
//
// Einkompilierte Sprach-Overlays (Name + ShortDescription je Regel).
// Rangfolge im Leser (TRuleCatalog.EnsureOverlay): lose Datei schlaegt
// diese Tabelle; die Tabelle schlaegt Englisch. FullDescription wird
// bewusst nicht eingebettet - die Overlays uebersetzen sie nicht.
// ==========================================================================

const
  // Index == Ord(TFindingKind), Drift-Guard im Leser wie bei
  // RULE_CATALOG_DATA (RuleID muss zur Position passen).
  RULE_OVERLAY_DE : array[0..197] of TRuleOverlayData = (
    // SCA001
    (
      RuleID   : 'SCA001';
      Name     : 'Objekt ohne try/finally erzeugt';
      ShortDesc: 'Objekt erzeugt, aber nie freigegeben (m' + #$F6 + 'gliches Speicherleck)'
    ),
    // SCA002
    (
      RuleID   : 'SCA002';
      Name     : 'Leerer except-Block';
      ShortDesc: 'Leerer except-Block schluckt jede Exception ohne Reaktion'
    ),
    // SCA003
    (
      RuleID   : 'SCA003';
      Name     : 'SQL-String per Verkettung gebaut';
      ShortDesc: 'SQL-String mit ''+'' aus beeinflussbarer Eingabe zusammengesetzt (Injection-Risiko)'
    ),
    // SCA004
    (
      RuleID   : 'SCA004';
      Name     : 'Hartkodierte Zugangsdaten / API-Token';
      ShortDesc: 'Passwort, API-Schl' + #$FC + 'ssel oder Token als String-Literal im Quelltext'
    ),
    // SCA005
    (
      RuleID   : 'SCA005';
      Name     : 'Format(): Platzhalterzahl passt nicht';
      ShortDesc: 'Zahl der Platzhalter in Format() / FormatUtf8() weicht von der Zahl der Argumente ab'
    ),
    // SCA006
    (
      RuleID   : 'SCA006';
      Name     : 'Datei konnte nicht gelesen oder geparst werden';
      ShortDesc: 'Parser-/IO-Fehler - Quelldatei unlesbar oder syntaktisch defekt'
    ),
    // SCA007
    (
      RuleID   : 'SCA007';
      Name     : 'Ungenutzte Unit in der uses-Klausel';
      ShortDesc: 'uses-Eintrag vermutlich ungenutzt (kein Bezeichner daraus wird referenziert)'
    ),
    // SCA008
    (
      RuleID   : 'SCA008';
      Name     : 'M' + #$F6 + 'gliche nil-Dereferenzierung';
      ShortDesc: 'Zugriff auf eine Variable, die an dieser Stelle nil sein kann'
    ),
    // SCA009
    (
      RuleID   : 'SCA009';
      Name     : 'Objekt ohne sch' + #$FC + 'tzendes try/finally erzeugt';
      ShortDesc: '.Create ohne umschlie' + #$DF + 'endes try/finally - Leck-Risiko im Ausnahmefall'
    ),
    // SCA010
    (
      RuleID   : 'SCA010';
      Name     : 'M' + #$F6 + 'gliche Division durch null';
      ShortDesc: 'Division durch eine Variable oder einen Ausdruck, der null sein kann'
    ),
    // SCA011
    (
      RuleID   : 'SCA011';
      Name     : 'Code nach Exit/Raise ist unerreichbar';
      ShortDesc: 'Anweisung nach Exit, raise oder Halt ist toter Code'
    ),
    // SCA012
    (
      RuleID   : 'SCA012';
      Name     : 'Methode ' + #$FC + 'berschreitet die Zeilengrenze';
      ShortDesc: 'Methode l' + #$E4 + 'nger als das konfigurierte Maximum (Vorgabe 80 Zeilen)'
    ),
    // SCA013
    (
      RuleID   : 'SCA013';
      Name     : 'Zu viele Parameter';
      ShortDesc: 'Methode hat mehr Parameter als konfiguriert erlaubt (Vorgabe 7)'
    ),
    // SCA014
    (
      RuleID   : 'SCA014';
      Name     : 'Zahlenliteral ohne benannte Konstante';
      ShortDesc: 'Zahlenliteral im Ausdruck - in eine benannte Konstante herausziehen'
    ),
    // SCA015
    (
      RuleID   : 'SCA015';
      Name     : 'String-Literal an mehreren Stellen wiederholt';
      ShortDesc: 'Dasselbe String-Literal kommt N-mal oder ' + #$F6 +
        'fter vor - in eine Konstante herausziehen'
    ),
    // SCA016
    (
      RuleID   : 'SCA016';
      Name     : 'Dateisystempfad als String-Literal';
      ShortDesc: 'Hartkodierter C:\-, UNC- oder Linux-Pfad im Quelltext'
    ),
    // SCA017
    (
      RuleID   : 'SCA017';
      Name     : 'WriteLn/ShowMessage im Produktivcode';
      ShortDesc: 'Debug-Ausgabe in einer Produktiv-Unit gefunden'
    ),
    // SCA018
    (
      RuleID   : 'SCA018';
      Name     : 'Blockverschachtelung ' + #$FC + 'berschreitet die Grenze';
      ShortDesc: 'Verschachtelungstiefe von if/for/while h' + #$F6 + 'her als konfiguriert (Vorgabe 4)'
    ),
    // SCA019
    (
      RuleID   : 'SCA019';
      Name     : 'TODO/FIXME-Marker im Kommentar';
      ShortDesc: 'Offener TODO-, FIXME-, HACK- oder XXX-Marker - vor dem Release aufl' + #$F6 + 'sen'
    ),
    // SCA020
    (
      RuleID   : 'SCA020';
      Name     : 'Leerer Methodenrumpf';
      ShortDesc: 'Methodenrumpf enth' + #$E4 + 'lt keine Anweisung'
    ),
    // SCA021
    (
      RuleID   : 'SCA021';
      Name     : 'Duplizierter Codeblock';
      ShortDesc: 'Mehrere identische Codebl' + #$F6 + 'cke (ab der konfigurierten Mindestzeilenzahl)'
    ),
    // SCA022
    (
      RuleID   : 'SCA022';
      Name     : 'Methode ' + #$FC + 'berschreitet die McCabe-Komplexit' + #$E4 + 't';
      ShortDesc: 'Zyklomatische Komplexit' + #$E4 + 't ' + #$FC +
        'ber der konfigurierten Schwelle (Vorgabe 10)'
    ),
    // SCA023
    (
      RuleID   : 'SCA023';
      Name     : 'Selbst definierte Regel';
      ShortDesc: 'Muster aus einer Regel getroffen, die aus analyser-rules.yml geladen wurde'
    ),
    // SCA024
    (
      RuleID   : 'SCA024';
      Name     : 'Komponente mit Vorgabenamen';
      ShortDesc: 'Komponente tr' + #$E4 + 'gt noch den Assistenten-Vorgabenamen (Button1, Edit3, Panel2 ...)'
    ),
    // SCA025
    (
      RuleID   : 'SCA025';
      Name     : 'Hartkodierter UI-Text im DFM';
      ShortDesc: 'Caption, Hint oder Text als Literal im DFM statt ' + #$FC + 'ber die i18n-Schicht'
    ),
    // SCA026
    (
      RuleID   : 'SCA026';
      Name     : 'Hartkodierte DB-Zugangsdaten im DFM';
      ShortDesc: 'Klartext-Password oder ConnectionString mit Pwd= an einer DB-Komponente'
    ),
    // SCA027
    (
      RuleID   : 'SCA027';
      Name     : 'Doppelte (DataSource, DataField)-Bindung';
      ShortDesc: 'Zwei oder mehr Controls binden dasselbe Paar aus DataSource und DataField'
    ),
    // SCA028
    (
      RuleID   : 'SCA028';
      Name     : 'DFM-Ereignisbehandler zeigt auf fehlende Methode';
      ShortDesc: 'OnClick / On... verweist auf eine Methode, die es in der Formularklasse nicht gibt'
    ),
    // SCA029
    (
      RuleID   : 'SCA029';
      Name     : 'Verwaister Ereignisbehandler';
      ShortDesc: 'Published-Methode in TNotifyEvent-Form hat keine DFM-Bindung'
    ),
    // SCA030
    (
      RuleID   : 'SCA030';
      Name     : 'Leerer gebundener Ereignisbehandler';
      ShortDesc: 'Ereignis ist im DFM verdrahtet, die Methode existiert, der Rumpf ist leer'
    ),
    // SCA031
    (
      RuleID   : 'SCA031';
      Name     : 'DFM-Komponente ohne published-Feld';
      ShortDesc: 'Komponente im DFM hat kein passendes published-Feld in der Formularklasse - veralteter DFM-Eintrag (Schema-Drift)'
    ),
    // SCA032
    (
      RuleID   : 'SCA032';
      Name     : 'Zyklische DataSource-/Master-Detail-Schleife';
      ShortDesc: 'Zyklus in den Kanten DataSource.DataSet / DataSet.MasterSource'
    ),
    // SCA033
    (
      RuleID   : 'SCA033';
      Name     : 'SQL-Property aus UI-Eingabe gebaut';
      ShortDesc: 'Query.SQL aus Text- oder Caption-Properties von Formular-Controls zusammengesetzt'
    ),
    // SCA034
    (
      RuleID   : 'SCA034';
      Name     : 'Pflichtfeld ohne UI-Bindung';
      ShortDesc: 'TField mit Required=True hat kein gebundenes Eingabe-Control'
    ),
    // SCA035
    (
      RuleID   : 'SCA035';
      Name     : 'Pflichtfeld nur an unsichtbaren Controls';
      ShortDesc: 'TField mit Required=True ist nur an Controls mit Visible=False gebunden'
    ),
    // SCA036
    (
      RuleID   : 'SCA036';
      Name     : 'UI-Control passt nicht zum TField-Typ';
      ShortDesc: 'Klasse des DB-Controls passt nicht zu TField.DataType (TDBEdit f' + #$FC +
        'r ein TBooleanField)'
    ),
    // SCA037
    (
      RuleID   : 'SCA037';
      Name     : 'Doppelte TabOrder unter Geschwistern';
      ShortDesc: 'Zwei Geschwister-Controls im selben Parent teilen sich denselben TabOrder-Wert'
    ),
    // SCA038
    (
      RuleID   : 'SCA038';
      Name     : 'Komponente nutzt eine verbotene Klasse';
      ShortDesc: 'Komponentenklasse steht auf der ForbiddenClasses-Liste des Projekts'
    ),
    // SCA039
    (
      RuleID   : 'SCA039';
      Name     : 'DB-Komponente auf einem UI-Formular';
      ShortDesc: 'TFDQuery / TFDConnection direkt auf einem TForm oder TFrame statt in einem DataModule'
    ),
    // SCA040
    (
      RuleID   : 'SCA040';
      Name     : 'Formular' + #$FC + 'bergreifender Feldzugriff';
      ShortDesc: 'Code in Form1 liest oder schreibt Form2.<published_field> direkt'
    ),
    // SCA041
    (
      RuleID   : 'SCA041';
      Name     : 'Eingabe-Control direkt auf dem TForm';
      ShortDesc: 'Eingabe-Control sitzt auf dem Formular, statt in einem TPanel oder TGroupBox eingebettet zu sein'
    ),
    // SCA042
    (
      RuleID   : 'SCA042';
      Name     : 'Ereignisbehandler mit zu vielen Bindungen';
      ShortDesc: 'Eine einzelne Methode h' + #$E4 +
        'ngt an N oder mehr Komponenten-Ereignissen (Vorgabe N=5)'
    ),
    // SCA043
    (
      RuleID   : 'SCA043';
      Name     : 'Komponente hat Action und OnClick';
      ShortDesc: 'Action und OnClick sind beide gesetzt - Action gewinnt, OnClick ist toter Code'
    ),
    // SCA044
    (
      RuleID   : 'SCA044';
      Name     : 'Lange String-Verkettung - besser Format()';
      ShortDesc: 'Mehrteilige String-Verkettung - in einen Format()-Aufruf ' + #$FC + 'berf' + #$FC + 'hren'
    ),
    // SCA045
    (
      RuleID   : 'SCA045';
      Name     : 'with X do ...';
      ShortDesc: 'with-Anweisung - Scope-Verdeckung, vor der der Compiler nicht warnt'
    ),
    // SCA046
    (
      RuleID   : 'SCA046';
      Name     : 'for i := High to Low - downto fehlt';
      ShortDesc: 'for i := 10 to 1 do - der Schleifenrumpf l' + #$E4 + 'uft nie'
    ),
    // SCA047
    (
      RuleID   : 'SCA047';
      Name     : 'x := x';
      ShortDesc: 'Selbstzuweisung - wirkungslos oder ein Copy-Paste-Vertipper'
    ),
    // SCA048
    (
      RuleID   : 'SCA048';
      Name     : 'Virtueller Aufruf im Konstruktor';
      ShortDesc: 'Virtuelle Methode aus dem Konstruktor gerufen - die Ableitung sieht ein halb initialisiertes Self'
    ),
    // SCA049
    (
      RuleID   : 'SCA049';
      Name     : 'Length(s) - N ohne Absicherung';
      ShortDesc: 'Length oder .Count mit Subtraktion - Unterlauf des vorzeichenlosen Typs, wenn leer'
    ),
    // SCA050
    (
      RuleID   : 'SCA050';
      Name     : 'Public-Member k' + #$F6 + 'nnte unit-private sein';
      ShortDesc: 'Public-Member wird nur innerhalb der aktuellen Unit referenziert - Delphi-klassisches `private` (Unit-Scope) reicht'
    ),
    // SCA051
    (
      RuleID   : 'SCA051';
      Name     : 'Public-Member k' + #$F6 + 'nnte protected sein';
      ShortDesc: 'Public-Member wird nur aus Ableitungen referenziert, nie von au' + #$DF + 'en'
    ),
    // SCA052
    (
      RuleID   : 'SCA052';
      Name     : 'Ungenutzter Public-Member (tote API)';
      ShortDesc: 'Public-Member wird von keiner Ableitung und ' + #$FC + 'ber keine Unit-Grenze referenziert'
    ),
    // SCA053
    (
      RuleID   : 'SCA053';
      Name     : 'Ungenutzte lokale Variable';
      ShortDesc: 'Lokale Variable deklariert, aber im Methodenrumpf nie referenziert'
    ),
    // SCA054
    (
      RuleID   : 'SCA054';
      Name     : 'Ungenutzter Methodenparameter';
      ShortDesc: 'Methodenparameter wird im Rumpf nie verwendet'
    ),
    // SCA055
    (
      RuleID   : 'SCA055';
      Name     : 'Tautologischer boolescher Ausdruck';
      ShortDesc: 'Bin' + #$E4 +
        'rer Operator mit identischer linker und rechter Seite: x = x, a and a, (p <> p)'
    ),
    // SCA056
    (
      RuleID   : 'SCA056';
      Name     : 'Master-Detail ohne MasterFields';
      ShortDesc: 'TDataSet hat MasterSource gesetzt, aber weder MasterFields noch IndexFieldNames'
    ),
    // SCA057
    (
      RuleID   : 'SCA057';
      Name     : 'Formular mit vielen DB-Komponenten - DataModule abspalten';
      ShortDesc: 'Sammelhinweis: das Formular h' + #$E4 + 'lt N oder mehr DB-Komponenten'
    ),
    // SCA058
    (
      RuleID   : 'SCA058';
      Name     : 'UPDATE / DELETE / TRUNCATE ohne WHERE';
      ShortDesc: 'SQL-Anweisung ' + #$E4 + 'ndert jede Zeile - die WHERE-Klausel fehlt'
    ),
    // SCA059
    (
      RuleID   : 'SCA059';
      Name     : 'Format()-Gleitkommaformat ohne TFormatSettings';
      ShortDesc: '%.2f / %.3f ohne explizite TFormatSettings - die Falle Komma gegen Punkt als Dezimaltrenner'
    ),
    // SCA060
    (
      RuleID   : 'SCA060';
      Name     : 'goto-Anweisung';
      ShortDesc: '`goto` schw' + #$E4 + 'cht den strukturierten Kontrollfluss'
    ),
    // SCA061
    (
      RuleID   : 'SCA061';
      Name     : 'Tabulator im Quelltext';
      ShortDesc: 'Tabulatoren werden je Editor unterschiedlich dargestellt - Leerzeichen verwenden'
    ),
    // SCA062
    (
      RuleID   : 'SCA062';
      Name     : 'Quelltextzeile zu lang';
      ShortDesc: 'Zeile l' + #$E4 + 'nger als 120 Zeichen - umbrechen oder einen Teilausdruck herausziehen'
    ),
    // SCA063
    (
      RuleID   : 'SCA063';
      Name     : 'Leerraum am Zeilenende';
      ShortDesc: 'Zeile endet mit Leerzeichen oder Tabulator - Hygiene f' + #$FC + 'r Diffs'
    ),
    // SCA064
    (
      RuleID   : 'SCA064';
      Name     : 'Pascal-Schl' + #$FC + 'sselwort nicht klein geschrieben';
      ShortDesc: 'Pascal-Schl' + #$FC + 'sselw' + #$F6 + 'rter (`begin`/`end`/`procedure`/...) geh' + #$F6 +
        'ren klein geschrieben'
    ),
    // SCA065
    (
      RuleID   : 'SCA065';
      Name     : 'NOSONAR-Unterdr' + #$FC + 'ckungsmarker';
      ShortDesc: '`// NOSONAR` sollte keine Befunde stillstellen - Verwendung pr' + #$FC + 'fen'
    ),
    // SCA066
    (
      RuleID   : 'SCA066';
      Name     : 'Leere Argumentliste';
      ShortDesc: '`Foo()` sollte `Foo;` hei' + #$DF + 'en - leere Klammern weglassen'
    ),
    // SCA067
    (
      RuleID   : 'SCA067';
      Name     : 'Inline-Assembler-Block';
      ShortDesc: '`asm...end`-Block - besser Pascal und Compiler-Intrinsics'
    ),
    // SCA068
    (
      RuleID   : 'SCA068';
      Name     : 'Trailing-Komma in der Argument-Liste';
      ShortDesc: '`Foo(A, B,)` - das Komma weglassen oder das fehlende Argument erg' + #$E4 + 'nzen'
    ),
    // SCA069
    (
      RuleID   : 'SCA069';
      Name     : 'Ganzzahlliteral ohne Ziffergruppierung';
      ShortDesc: 'Gro' + #$DF + 'e Ganzzahlliterale sollten den Trenner `_` verwenden'
    ),
    // SCA070
    (
      RuleID   : 'SCA070';
      Name     : 'Auskommentierter Code';
      ShortDesc: 'Kommentar sieht wie Pascal-Code aus - l' + #$F6 + 'schen oder begr' + #$FC + 'nden'
    ),
    // SCA071
    (
      RuleID   : 'SCA071';
      Name     : 'Unit-Section-Keyword nicht in Spalte 1';
      ShortDesc: '`unit`/`interface`/`uses`/`implementation`/`initialization`/`finalization` sollten in Spalte 1 beginnen'
    ),
    // SCA072
    (
      RuleID   : 'SCA072';
      Name     : #$DC + 'berfl' + #$FC + 'ssiger Boolean-Vergleich';
      ShortDesc: '`X = True` sollte `X` hei' + #$DF + 'en (und `X <> False` entsprechend)'
    ),
    // SCA073
    (
      RuleID   : 'SCA073';
      Name     : 'Leere Interface-Deklaration';
      ShortDesc: 'Interface ohne Methoden und Properties tr' + #$E4 + 'gt keinen Vertrag'
    ),
    // SCA074
    (
      RuleID   : 'SCA074';
      Name     : 'Assert ohne Meldung';
      ShortDesc: '`Assert(cond);` - eine `''warum''`-Meldung f' + #$FC + 'r die Diagnose erg' + #$E4 + 'nzen'
    ),
    // SCA075
    (
      RuleID   : 'SCA075';
      Name     : 'Explizite TObject-Ableitung';
      ShortDesc: '`class(TObject)` ist ' + #$FC + 'berfl' + #$FC + 'ssig - Klammern weglassen'
    ),
    // SCA076
    (
      RuleID   : 'SCA076';
      Name     : 'Gruppierte Variablen-, Feld- oder Parameterdeklaration';
      ShortDesc: '`A, B: Type` in eine Deklaration je Zeile aufteilen'
    ),
    // SCA077
    (
      RuleID   : 'SCA077';
      Name     : 'Leerer begin..end-Block';
      ShortDesc: 'Leerer `begin..end` - l' + #$F6 + 'schen oder die Anweisung erg' + #$E4 + 'nzen'
    ),
    // SCA078
    (
      RuleID   : 'SCA078';
      Name     : 'Catch-all auf der Wurzelklasse Exception';
      ShortDesc: '`on E: Exception do` schluckt alles, auch AV und Speicherersch' + #$F6 + 'pfung'
    ),
    // SCA079
    (
      RuleID   : 'SCA079';
      Name     : 'Aufeinanderfolgende const/type/var-Sektion';
      ShortDesc: 'Zwei `const`-, `type`- oder `var`-Bl' + #$F6 + 'cke hintereinander geh' + #$F6 +
        'ren zusammengefasst'
    ),
    // SCA080
    (
      RuleID   : 'SCA080';
      Name     : #$DC + 'berfl' + #$FC + 'ssiges Exit/Continue vor end';
      ShortDesc: '`Exit;` / `Continue;` direkt vor `end` ist wirkungslos'
    ),
    // SCA081
    (
      RuleID   : 'SCA081';
      Name     : 'Mehrere Klassendeklarationen in einer Datei';
      ShortDesc: 'Eine Klasse je Unit erleichtert das Refactoring'
    ),
    // SCA082
    (
      RuleID   : 'SCA082';
      Name     : 'Doppeltes Semikolon';
      ShortDesc: '`;;` - das ' + #$FC + 'berz' + #$E4 + 'hlige Semikolon weglassen'
    ),
    // SCA083
    (
      RuleID   : 'SCA083';
      Name     : 'Leerer finally-Block';
      ShortDesc: '`try ... finally end;` r' + #$E4 + 'umt nichts auf - entweder f' + #$FC +
        'llen oder das finally weglassen'
    ),
    // SCA084
    (
      RuleID   : 'SCA084';
      Name     : #$DC + 'berfl' + #$FC + 'ssige Assigned- plus nil-Pr' + #$FC + 'fung';
      ShortDesc: '`Assigned(X) and (X <> nil)` - die nil-Pr' + #$FC + 'fung weglassen'
    ),
    // SCA085
    (
      RuleID   : 'SCA085';
      Name     : 'X.Free; X := nil; sollte FreeAndNil(X) sein';
      ShortDesc: '`FreeAndNil(X)` statt `X.Free; X := nil;` verwenden'
    ),
    // SCA086
    (
      RuleID   : 'SCA086';
      Name     : 'out-Parameter vermeiden';
      ShortDesc: '`var` ist `out` vorzuziehen (out hat ' + #$FC + 'berraschende Semantik)'
    ),
    // SCA087
    (
      RuleID   : 'SCA087';
      Name     : 'Leere Sichtbarkeitssektion in der Klasse';
      ShortDesc: 'Sektionskopf `public`/`private`/... ohne Member darunter'
    ),
    // SCA088
    (
      RuleID   : 'SCA088';
      Name     : 'Alte Unit-Initialisierung begin..end.';
      ShortDesc: '`initialization..end.` statt des alten `begin..end.` verwenden'
    ),
    // SCA089
    (
      RuleID   : 'SCA089';
      Name     : 'Public-Feld in der Klasse';
      ShortDesc: 'Ein public-Feld bricht die Kapselung - eine Property verwenden'
    ),
    // SCA090
    (
      RuleID   : 'SCA090';
      Name     : 'Verschachtelter try-Block';
      ShortDesc: 'Verschachteltes `try..end` - das innere try in eine eigene Methode herausziehen'
    ),
    // SCA091
    (
      RuleID   : 'SCA091';
      Name     : 'Gro' + #$DF + 'e case-Anweisung';
      ShortDesc: '`case` mit 10 oder mehr Zweigen - Polymorphie oder eine Dispatch-Tabelle erw' + #$E4 +
        'gen'
    ),
    // SCA092
    (
      RuleID   : 'SCA092';
      Name     : 'Unit ohne Deklarationen';
      ShortDesc: 'Unit hat weder type, const, var noch procedure/function - l' + #$F6 + 'schen oder f' + #$FC +
        'llen'
    ),
    // SCA093
    (
      RuleID   : 'SCA093';
      Name     : 'Mehrere inherited-Aufrufe in einer Methode';
      ShortDesc: 'Zwei oder mehr `inherited;` in derselben Methode - die Seiteneffekte der Basis laufen doppelt'
    ),
    // SCA094
    (
      RuleID   : 'SCA094';
      Name     : #$DC + 'berfl' + #$FC + 'ssige doppelte Klammern';
      ShortDesc: '`((Ident))` - die ' + #$E4 + 'u' + #$DF + 'eren Klammern weglassen'
    ),
    // SCA095
    (
      RuleID   : 'SCA095';
      Name     : 'Wiederholte Sichtbarkeitssektion';
      ShortDesc: 'Dieselbe Sektion `public`/`private`/... kommt in einer Klasse zweimal vor'
    ),
    // SCA096
    (
      RuleID   : 'SCA096';
      Name     : 'Konstruktor ohne inherited-Aufruf';
      ShortDesc: 'Dem Konstruktor fehlt `inherited Create` - die Basis bleibt uninitialisiert'
    ),
    // SCA097
    (
      RuleID   : 'SCA097';
      Name     : 'Destruktor ohne inherited-Aufruf';
      ShortDesc: 'Dem Destruktor fehlt `inherited Destroy` - das Aufr' + #$E4 + 'umen der Basis entf' + #$E4 +
        'llt (Leck-Risiko)'
    ),
    // SCA098
    (
      RuleID   : 'SCA098';
      Name     : #$DC + 'berfl' + #$FC + 'ssige bedingte Zuweisung';
      ShortDesc: '`if Cond then X := True else X := False` sollte `X := Cond` hei' + #$DF + 'en'
    ),
    // SCA099
    (
      RuleID   : 'SCA099';
      Name     : 'Unsymmetrisches begin/end in if/else';
      ShortDesc: 'Der then-Zweig nutzt `begin..end`, der else-Zweig ist eine einzelne Anweisung'
    ),
    // SCA100
    (
      RuleID   : 'SCA100';
      Name     : 'Zeigertyp-Alias ohne P-Pr' + #$E4 + 'fix';
      ShortDesc: '`Foo = ^Bar` sollte `PBar = ^Bar` hei' + #$DF + 'en (P-Pr' + #$E4 + 'fix-Konvention)'
    ),
    // SCA101
    (
      RuleID   : 'SCA101';
      Name     : 'Zweig ohne begin..end-Block';
      ShortDesc: '`then`/`else`/`do <Anweisung>` - besser ein ausdr' + #$FC + 'ckliches `begin..end`'
    ),
    // SCA102
    (
      RuleID   : 'SCA102';
      Name     : 'Verschachtelte Routine in einer Methode';
      ShortDesc: 'Lokale verschachtelte Prozedur oder Funktion - auf Unit-Ebene herausziehen'
    ),
    // SCA103
    (
      RuleID   : 'SCA103';
      Name     : 'Klassenfeld ohne F-Pr' + #$E4 + 'fix';
      ShortDesc: 'Klassenfelder sollten der Konvention `F<Name>` folgen'
    ),
    // SCA104
    (
      RuleID   : 'SCA104';
      Name     : 'Klassen-/Record-Typ ohne T-Pr' + #$E4 + 'fix';
      ShortDesc: 'Klassen- und Record-Typaliase sollten mit `T` beginnen'
    ),
    // SCA105
    (
      RuleID   : 'SCA105';
      Name     : 'Interface-Typ ohne I-Pr' + #$E4 + 'fix';
      ShortDesc: 'Interface-Aliase sollten mit `I` beginnen (`IFoo = interface`)'
    ),
    // SCA106
    (
      RuleID   : 'SCA106';
      Name     : 'Methode nicht in PascalCase';
      ShortDesc: 'Methoden sollten mit einem Gro' + #$DF + 'buchstaben beginnen (PascalCase)'
    ),
    // SCA107
    (
      RuleID   : 'SCA107';
      Name     : 'Public-Member k' + #$F6 + 'nnte strict private sein';
      ShortDesc: 'Public-Member wird NUR von Methoden der eigenen Klasse referenziert - `strict private` erreicht die st' +
        #$E4 + 'rkste Kapselung'
    ),
    // SCA108
    (
      RuleID   : 'SCA108';
      Name     : 'TThread.Synchronize aus dem Destruktor';
      ShortDesc: 'Synchronize() aus dem Destruktor Destroy gerufen - der klassische Deadlock zwischen Worker und UI-Thread'
    ),
    // SCA109
    (
      RuleID   : 'SCA109';
      Name     : 'Sperre ohne try/finally freigegeben';
      ShortDesc: 'TCriticalSection, Monitor oder WinAPI-Sperre ohne umschlie' + #$DF +
        'endes try..finally genommen - eine Ausnahme l' + #$E4 + 'sst sie gesperrt'
    ),
    // SCA110
    (
      RuleID   : 'SCA110';
      Name     : 'String-Verkettung in der Schleife';
      ShortDesc: '`s := s + x` in for/while/repeat - quadratisch viele Neuallokationen'
    ),
    // SCA111
    (
      RuleID   : 'SCA111';
      Name     : 'ParamByName(...) in der Schleife gerufen';
      ShortDesc: '`Query.ParamByName(''x'').AsXxx := ...` in einer Schleife - lineare Suche je Durchlauf'
    ),
    // SCA112
    (
      RuleID   : 'SCA112';
      Name     : 'FieldByName(...) in der Schleife gerufen';
      ShortDesc: '`DataSet.FieldByName(''x'').AsXxx` in einer Schleife - lineare Suche je Datensatz'
    ),
    // SCA113
    (
      RuleID   : 'SCA113';
      Name     : 'TThread.Resume ist veraltet';
      ShortDesc: '`MyThread.Resume` - `MyThread.Start` verwenden (seit Delphi 2010)'
    ),
    // SCA114
    (
      RuleID   : 'SCA114';
      Name     : 'TThread ohne Terminate+WaitFor freigegeben';
      ShortDesc: '`FreeAndNil(MyThread)` ohne vorheriges `Terminate; WaitFor` - der Worker l' + #$E4 +
        'uft m' + #$F6 + 'glicherweise noch'
    ),
    // SCA115
    (
      RuleID   : 'SCA115';
      Name     : 'HTTP-URL im Klartext';
      ShortDesc: 'Literal `''http://...''` f' + #$FC + 'r einen entfernten Endpunkt - anf' + #$E4 + 'llig f' +
        #$FC + 'r Man-in-the-Middle'
    ),
    // SCA116
    (
      RuleID   : 'SCA116';
      Name     : 'TLS-Pr' + #$FC + 'fung abgeschaltet';
      ShortDesc: 'Leeres `SecureProtocols`, `IgnoreCertificateErrors := True` oder `OnVerifyPeer := nil`'
    ),
    // SCA117
    (
      RuleID   : 'SCA117';
      Name     : 'Public-Member ohne Doku-Kommentar';
      ShortDesc: 'Public-Methode oder -Property in der `interface`-Sektion ohne Doku-Kommentar direkt dar' +
        #$FC + 'ber'
    ),
    // SCA118
    (
      RuleID   : 'SCA118';
      Name     : 'Exception-Klasse ohne `E`-Pr' + #$E4 + 'fix';
      ShortDesc: 'Eine `class(Exception)`-Ableitung sollte der RTL-Konvention `E<Name>` folgen'
    ),
    // SCA119
    (
      RuleID   : 'SCA119';
      Name     : 'Lokale Konstante nicht in UPPER_SNAKE_CASE';
      ShortDesc: '`const X = 42;` in einer Methode - f' + #$FC +
        'r Zahlenkonstanten ist UPPER_SNAKE_CASE vorzuziehen'
    ),
    // SCA120
    (
      RuleID   : 'SCA120';
      Name     : 'Exception erzeugt, aber nie ausgel' + #$F6 + 'st';
      ShortDesc: '`EFoo.Create(''msg'');` legt ein Exception-Objekt an, ohne es zu `raise`n - der Fehlerpfad wird stillschweigend ' +
        #$FC + 'bersprungen'
    ),
    // SCA121
    (
      RuleID   : 'SCA121';
      Name     : 'Funktion weist Result nie zu';
      ShortDesc: 'Der Funktionsrumpf endet, ohne `Result` (oder `<Funktionsname> := ...`) zu schreiben - der R' +
        #$FC + 'ckgabewert ist undefiniert'
    ),
    // SCA122
    (
      RuleID   : 'SCA122';
      Name     : 'Erneutes raise der gebundenen Exception-Variablen';
      ShortDesc: '`on E: T do ... raise E;` verwirft den urspr' + #$FC +
        'nglichen Stack Trace - das blanke `raise;` erh' + #$E4 + 'lt ihn'
    ),
    // SCA123
    (
      RuleID   : 'SCA123';
      Name     : 'Typumwandlung direkt vor Free / Destroy';
      ShortDesc: '`TFoo(x).Free` - die Typumwandlung beeinflusst nicht, welches Destroy l' + #$E4 +
        'uft (Destroy ist virtuell)'
    ),
    // SCA124
    (
      RuleID   : 'SCA124';
      Name     : 'Konstruktor auf einer Instanz statt der Klasse aufgerufen';
      ShortDesc: '`obj.Create` - ruft den Konstruktor als Methode auf einer bestehenden Instanz, ' + #$FC +
        'berspringt die Allokation und initialisiert Felder ' + #$FC + 'ber lebenden Daten neu'
    ),
    // SCA125
    (
      RuleID   : 'SCA125';
      Name     : 'Override, dessen Rumpf nur aus `inherited;` besteht';
      ShortDesc: 'Ein Override, das nur an die Basis weiterreicht, hat keinen Zweck - entfernen'
    ),
    // SCA126
    (
      RuleID   : 'SCA126';
      Name     : 'Assigned() statt `= nil` / `<> nil` verwenden';
      ShortDesc: 'Pascal-Konvention: `Assigned(x)` und `not Assigned(x)` sind die kanonischen nil-Pr' + #$FC +
        'fungen'
    ),
    // SCA127
    (
      RuleID   : 'SCA127';
      Name     : 'Basisklasse `Exception` statt einer eigenen Ableitung ausgel' + #$F6 + 'st';
      ShortDesc: '`raise Exception.Create(''...'')` - die Basisklasse tr' + #$E4 +
        'gt keine Semantik, Aufrufer k' + #$F6 + 'nnen nicht gezielt filtern'
    ),
    // SCA128
    (
      RuleID   : 'SCA128';
      Name     : 'Gebietsschema-abh' + #$E4 + 'ngiger Formataufruf ohne TFormatSettings';
      ShortDesc: '`StrToDate(s)`, `FormatFloat(...)` und Verwandte ohne TFormatSettings h' + #$E4 +
        'ngen am System-Gebietsschema - je Rechner und Benutzer verschieden'
    ),
    // SCA129
    (
      RuleID   : 'SCA129';
      Name     : 'String-Umwandlung in einen 8-Bit-Typ ohne explizite Kodierung';
      ShortDesc: '`AnsiString(s)` / `RawByteString(s)` / `ShortString(s)` verwirft stillschweigend alle Zeichen au' +
        #$DF + 'erhalb der aktiven Codepage'
    ),
    // SCA130
    (
      RuleID   : 'SCA130';
      Name     : 'Char-Wert nach PChar umgewandelt - Codepoint wird zur Adresse';
      ShortDesc: '`PChar(''A'')` ist nicht `PChar("A")` - die Umwandlung deutet den 16-Bit-Codepoint als rohe Speicheradresse'
    ),
    // SCA131
    (
      RuleID   : 'SCA131';
      Name     : 'IfThen() wertet beide Zweige aus - keine Kurzschlussauswertung';
      ShortDesc: '`Math.IfThen(cond, A(), B())` und `StrUtils.IfThen` sind normale Funktionen - beide Arme laufen vor dem Aufruf'
    ),
    // SCA132
    (
      RuleID   : 'SCA132';
      Name     : 'except on E: Exception f' + #$E4 + 'ngt jeden Fehler';
      ShortDesc: '`on E: Exception do ...` f' + #$E4 +
        'ngt die Basisklasse und damit jede Ableitung, auch System-Ausnahmen, die nicht stillgestellt werden d' +
        #$FC + 'rfen (EOutOfMemory, EAccessViolation, EAbort)'
    ),
    // SCA133
    (
      RuleID   : 'SCA133';
      Name     : 'Blankes raise au' + #$DF + 'erhalb eines except/on-Handlers';
      ShortDesc: '`raise;` ohne Exception-Ausdruck funktioniert nur INNERHALB eines except-Handlers (erneutes Ausl' +
        #$F6 + 'sen) - au' + #$DF + 'erhalb l' + #$F6 +
        'st es NIL aus und erzeugt eine Access Violation'
    ),
    // SCA134
    (
      RuleID   : 'SCA134';
      Name     : 'Variable nach Free / FreeAndNil verwendet';
      ShortDesc: 'Eine Variable nach `Free` oder `FreeAndNil` zu dereferenzieren liest einen h' + #$E4 +
        'ngenden Zeiger und erzeugt eine Access Violation'
    ),
    // SCA135
    (
      RuleID   : 'SCA135';
      Name     : 'Konkrete Ableitung erbt eine abstrakte Methode ohne override';
      ShortDesc: 'Die Klasse leitet von einer Basis mit `abstract`-Methode ab, ' + #$FC +
        'berschreibt sie aber nicht - der Aufruf auf der Instanz l' + #$F6 +
        'st zur Laufzeit EAbstractError aus'
    ),
    // SCA136
    (
      RuleID   : 'SCA136';
      Name     : 'Konstruktor belegt Felder und l' + #$F6 + 'st ohne try/except aus';
      ShortDesc: 'Der Konstruktor weist Felder per `<Klasse>.Create` zu und l' + #$F6 + 'st sp' + #$E4 +
        'ter aus - die teilweise belegten Felder lecken auf dem Ausnahmepfad'
    ),
    // SCA137
    (
      RuleID   : 'SCA137';
      Name     : 'Int64-Ziel bekommt das Produkt zweier 32-Bit-Operanden';
      ShortDesc: '`<Int64-Var> := <a> * <b>` rechnet die Multiplikation in 32 Bit, bevor erweitert wird - ein ' +
        #$DC + 'berlauf schneidet stillschweigend ab'
    ),
    // SCA138
    (
      RuleID   : 'SCA138';
      Name     : 'Klasse hat zu viele Methoden oder Felder';
      ShortDesc: 'Eine Klasse mit mehr als 20 Methoden oder mehr als 15 Instanzfeldern b' + #$FC +
        'ndelt zu viele Zust' + #$E4 + 'ndigkeiten - schwer zu testen, zu ' + #$E4 +
        'ndern und zu pr' + #$FC + 'fen'
    ),
    // SCA139
    (
      RuleID   : 'SCA139';
      Name     : 'Free ohne anschlie' + #$DF + 'endes nil-Setzen';
      ShortDesc: '`obj.Free;` ohne `obj := nil;` (oder ohne FreeAndNil) hinterl' + #$E4 + 'sst einen h' +
        #$E4 + 'ngenden Zeiger - jede weitere Verwendung ist ein Use-After-Free'
    ),
    // SCA140
    (
      RuleID   : 'SCA140';
      Name     : 'Methode hat zu viele Exit-Anweisungen';
      ShortDesc: 'Eine Methode mit mehr als 3 Exit-Aufrufen hat zu viele R' + #$FC +
        'cksprungpfade - schwer zu lesen, schwer zu testen, leicht einen zu ' + #$FC + 'bersehen'
    ),
    // SCA141
    (
      RuleID   : 'SCA141';
      Name     : 'Klassenimplementierung ' + #$FC + 'berschreitet 500 Zeilen';
      ShortDesc: 'Eine Klasse, deren Deklaration und Implementierungsmethoden zusammen ' + #$FC +
        'ber 500 Zeilen umfassen, hat zu viele Zust' + #$E4 + 'ndigkeiten'
    ),
    // SCA142
    (
      RuleID   : 'SCA142';
      Name     : 'uses-Klausel ist nicht alphabetisch sortiert';
      ShortDesc: 'Eintr' + #$E4 +
        'ge einer `uses`-Klausel stehen nicht alphabetisch - Merges werden unvorhersehbar und Reviews schwerer'
    ),
    // SCA143
    (
      RuleID   : 'SCA143';
      Name     : 'Unit hat keinen erkl' + #$E4 + 'renden Header-Kommentar';
      ShortDesc: 'Die Unit beginnt direkt mit `interface`, ohne erkl' + #$E4 +
        'renden Kommentarblock zwischen `unit ...;` und `interface`'
    ),
    // SCA144
    (
      RuleID   : 'SCA144';
      Name     : 'Gleichheits-/Ungleichheitsvergleich von Gleitkommazahlen';
      ShortDesc: '`a = b` oder `a <> b` zwischen Single/Double/Extended ist wegen der IEEE-754-Rundung unzuverl' +
        #$E4 + 'ssig - SameValue oder Math.IsZero verwenden'
    ),
    // SCA145
    (
      RuleID   : 'SCA145';
      Name     : 'raise im Destruktor ohne try/except';
      ShortDesc: 'Ein ungesch' + #$FC + 'tztes `raise` im Destruktor bricht die Aufr' + #$E4 +
        'umkette ab - inherited Destroy und nachfolgende FreeAndNil-Aufrufe entfallen, der Zustand bleibt inkonsistent'
    ),
    // SCA146
    (
      RuleID   : 'SCA146';
      Name     : 'Boolean-Parameter als interner Verzweigungsschalter';
      ShortDesc: 'Ein Boolean-Parameter, dessen Wert zwischen zwei v' + #$F6 +
        'llig verschiedenen Codepfaden w' + #$E4 +
        'hlt, ist eine verdeckte Strategie - besser zwei Methoden mit sprechenden Namen'
    ),
    // SCA147
    (
      RuleID   : 'SCA147';
      Name     : 'Private Methode ohne Aufrufer in der Unit';
      ShortDesc: 'Eine private Methode, die von keiner anderen Methode derselben Unit referenziert wird, ist toter Code - l' +
        #$F6 + 'schen oder anbinden'
    ),
    // SCA148
    (
      RuleID   : 'SCA148';
      Name     : 'Instanzmethode greift nie auf Self zu - k' + #$F6 + 'nnte Klassenmethode sein';
      ShortDesc: 'Eine Methode, die nur ihre Parameter nutzt (kein Self, keine Instanzfelder, keine virtuelle Kette), ist funktional eine Klassenmethode - als solche kennzeichnen'
    ),
    // SCA149
    (
      RuleID   : 'SCA149';
      Name     : 'Methode verdeckt eine virtuelle Basismethode ohne `override`';
      ShortDesc: 'Eine in der Ableitung mit demselben Namen wie eine virtuelle oder dynamische Basismethode neu deklarierte Methode ohne `override` bricht die Polymorphie - der Compiler meldet W1010'
    ),
    // SCA150
    (
      RuleID   : 'SCA150';
      Name     : 'Boolescher Vergleich ist immer wahr / immer falsch';
      ShortDesc: 'Vergleiche wie `Length(s) >= 0` sind Tautologien - das Ergebnis von Length ist nie negativ, die Bedingung also nie falsch'
    ),
    // SCA151
    (
      RuleID   : 'SCA151';
      Name     : 'Funktion liefert immer dasselbe Literal';
      ShortDesc: 'Alle Pfade der Funktion weisen Result dasselbe Literal zu - die Verzweigung ' + #$E4 +
        'ndert nichts am Verhalten, die Funktion durch eine Konstante ersetzen'
    ),
    // SCA152
    (
      RuleID   : 'SCA152';
      Name     : 'Benutzersichtbarer Text als Literal zugewiesen';
      ShortDesc: 'Zuweisungen an Caption/Hint/Text und Aufrufe von ShowMessage/MessageDlg mit Literaltext umgehen resourcestring und i18n - der Text ist nicht ' +
        #$FC + 'bersetzbar'
    ),
    // SCA153
    (
      RuleID   : 'SCA153';
      Name     : 'Lock/Unlock-Paar ohne try/finally';
      ShortDesc: 'Lock / EnterCriticalSection / TMonitor.Enter mit passender Freigabe in derselben Routine, aber ohne try/finally - der Ausnahmepfad l' +
        #$E4 + 'sst die Sperre stehen und blockiert den n' + #$E4 + 'chsten Aufrufer'
    ),
    // SCA154
    (
      RuleID   : 'SCA154';
      Name     : 'Move/FillChar mit SizeOf eines Zeigertyps';
      ShortDesc: 'Move, FillChar, CopyMemory oder ZeroMemory mit SizeOf(PXxx), wobei PXxx ein Zeigertyp ist - kopiert nur 4 oder 8 Byte (die Zeigergr' +
        #$F6 + #$DF + 'e) statt des gemeinten Puffers'
    ),
    // SCA155
    (
      RuleID   : 'SCA155';
      Name     : 'with-Anweisung mit mehreren Zielen';
      ShortDesc: '`with A, B do` (zwei oder mehr durch Komma getrennte Empf' + #$E4 +
        'nger) macht die Member-Aufl' + #$F6 + 'sung mehrdeutig - eine neue Methode an A oder B ' +
        #$E4 + 'ndert stillschweigend die Bedeutung des Rumpfs'
    ),
    // SCA156
    (
      RuleID   : 'SCA156';
      Name     : 'GetMem / AllocMem ohne try/finally';
      ShortDesc: 'GetMem / AllocMem / ReallocMem mit passendem FreeMem in derselben Routine, aber ohne umschlie' +
        #$DF + 'endes try/finally - der Ausnahmepfad verliert den Puffer dauerhaft'
    ),
    // SCA157
    (
      RuleID   : 'SCA157';
      Name     : 'SetLength(arr, Length(arr) + N) in der Schleife';
      ShortDesc: 'Ein dynamisches Array in einer for/while/repeat-Schleife um eins (oder N) zu vergr' + #$F6 +
        #$DF + 'ern kostet quadratisch - einmal vor der Schleife vergr' + #$F6 + #$DF +
        'ern oder blockweise wachsen'
    ),
    // SCA158
    (
      RuleID   : 'SCA158';
      Name     : 'PChar(s) +/- Offset ohne Leerpr' + #$FC + 'fung';
      ShortDesc: '`PChar(s) + n` und Verwandte ohne vorherige Leerpr' + #$FC +
        'fung auf `s` - PChar('''') wird zu NIL optimiert, die Rechnung darauf ist eine latente Access Violation'
    ),
    // SCA159
    (
      RuleID   : 'SCA159';
      Name     : 'Typisierter Exception-Handler mit leerem Rumpf';
      ShortDesc: '`on E: SomeException do ;` schluckt eine bestimmte Exception-Klasse stillschweigend - schlimmer als ein blankes `except end`, weil die Typangabe absichtsvoll aussieht'
    ),
    // SCA160
    (
      RuleID   : 'SCA160';
      Name     : 'String-Cast aus Raw-Pointer';
      ShortDesc: '`string(P)` und Verwandte aus einem P-pr' + #$E4 +
        'fixierten Zeiger setzen einen Nullterminator voraus, den es nicht geben muss - ' + #$DC +
        'berlesen des Heaps'
    ),
    // SCA161
    (
      RuleID   : 'SCA161';
      Name     : 'Zeigersubtraktion ' + #$FC + 'ber eine 32-Bit-Umwandlung';
      ShortDesc: '`Cardinal(P1) - Cardinal(P2)` (auch Integer/LongWord/LongInt) schneidet unter Win64 die oberen 32 Bit ab - die Differenz ist zeitweise falsch'
    ),
    // SCA162
    (
      RuleID   : 'SCA162';
      Name     : 'Schwaches oder veraltetes Kryptoverfahren verwendet';
      ShortDesc: 'Algorithmusname (''MD5'', ''SHA1'', ''DES'', ''RC4'', ''TLS1.0'', ''SSLv3'') oder Wrapper-Klasse (THashMD5, TIdHashSHA1, ...) referenziert - anf' +
        #$E4 + 'llig f' + #$FC + 'r Kollisions- und Known-Plaintext-Angriffe'
    ),
    // SCA163
    (
      RuleID   : 'SCA163';
      Name     : 'Shell-API mit String-Verkettung im Argument gerufen';
      ShortDesc: 'ShellExecute / CreateProcess / WinExec mit `+` in den Argumenten - ist ein Operand beeinflussbar, wird daraus ein Command-Injection-Vektor'
    ),
    // SCA164
    (
      RuleID   : 'SCA164';
      Name     : 'Routine auf oberster Ebene wird nie gerufen';
      ShortDesc: 'Eine eigenst' + #$E4 +
        'ndige Prozedur oder Funktion in der implementation-Sektion wird nirgends in der Unit gerufen und ist nicht ' +
        #$FC + 'ber die interface-Sektion exportiert - toter Code'
    ),
    // SCA165
    (
      RuleID   : 'SCA165';
      Name     : 'Ungenutzter noinspection-Marker';
      ShortDesc: 'Ein `// noinspection X` unterdr' + #$FC +
        'ckt an seiner Zielzeile keinen Befund - entweder ist der Detektor besser geworden oder das Ziel war falsch'
    ),
    // SCA166
    (
      RuleID   : 'SCA166';
      Name     : 'Uninitialisierte lokale Variable';
      ShortDesc: 'Lokale Variable wird gelesen, bevor sie auf jedem Pfad durch die Methode zugewiesen wurde'
    ),
    // SCA167
    (
      RuleID   : 'SCA167';
      Name     : 'Random-Aufruf ohne vorheriges Randomize';
      ShortDesc: 'Random / RandomRange / RandomFrom ohne Randomize - Seed=0 liefert bei jedem Lauf dieselbe Folge'
    ),
    // SCA168
    (
      RuleID   : 'SCA168';
      Name     : 'case-Anweisung ohne else-Zweig';
      ShortDesc: 'Die case-Anweisung hat keinen else-Zweig - unbehandelte Werte fallen stillschweigend durch; ein else nach einem if im letzten Arm ist das else des case'
    ),
    // SCA169
    (
      RuleID   : 'SCA169';
      Name     : 'Assert-Argument enth' + #$E4 + 'lt einen Aufruf mit Seiteneffekt';
      ShortDesc: 'Assert(SomeCall) - der Aufruf entf' + #$E4 +
        'llt im Release-Build und sein Seiteneffekt geht stillschweigend verloren'
    ),
    // SCA170
    (
      RuleID   : 'SCA170';
      Name     : 'string-Parameter ohne const';
      ShortDesc: 'string-Parameter ohne const deklariert - erzwingt bei jedem Aufruf eine Refcount-Erh' +
        #$F6 + 'hung'
    ),
    // SCA171
    (
      RuleID   : 'SCA171';
      Name     : 'Compilerschalter OFF ohne passendes ON in derselben Datei';
      ShortDesc: '{$WARNINGS OFF} (oder HINTS/RANGECHECKS/...) ohne schlie' + #$DF +
        'endes ON - wirkt in die folgenden Units hinein'
    ),
    // SCA172
    (
      RuleID   : 'SCA172';
      Name     : 'Boolean-Property ohne Is-/Has-/Can-/Should-Pr' + #$E4 + 'fix';
      ShortDesc: 'Der Name der Boolean-Property liest sich als Substantiv - besser ein Verb-Pr' + #$E4 +
        'fix, das sich als Frage liest'
    ),
    // SCA173
    (
      RuleID   : 'SCA173';
      Name     : 'Variant in einer leistungskritischen Methode (enth' + #$E4 + 'lt Schleife)';
      ShortDesc: 'Variant-Variable in einer Methode mit Schleife - jede Variant-Operation zahlt den 10- bis 100-fachen COM-Dispatch-Aufwand'
    ),
    // SCA174
    (
      RuleID   : 'SCA174';
      Name     : 'TList<T> mit T.Create gef' + #$FC + 'llt - Elemente lecken beim Freigeben';
      ShortDesc: 'TList<TFoo>.Create plus Add(TFoo.Create) - die Liste besitzt ihre Elemente nicht, jede TFoo-Instanz leckt'
    ),
    // SCA175
    (
      RuleID   : 'SCA175';
      Name     : 'Anonyme Methode f' + #$E4 + 'ngt die Schleifenvariable per Referenz';
      ShortDesc: 'Anonyme Methode in `for i := ... do` referenziert i - alle Closures sehen denselben Endwert'
    ),
    // SCA176
    (
      RuleID   : 'SCA176';
      Name     : 'Methode mit hoher kognitiver Komplexit' + #$E4 + 't (verschachtelter Kontrollfluss)';
      ShortDesc: 'Kognitive Komplexit' + #$E4 + 't ' + #$FC +
        'ber 15 (Sonar-Stil) - verschachtelte if/for/while/case sind mental schwer zu folgen'
    ),
    // SCA177
    (
      RuleID   : 'SCA177';
      Name     : 'Thread-Variable nach FreeOnTerminate := True verwendet';
      ShortDesc: 'Nach T.FreeOnTerminate := True riskiert jeder weitere T.-Zugriff eine Access-Violation, wenn der Thread bereits beendet ist'
    ),
    // SCA178
    (
      RuleID   : 'SCA178';
      Name     : 'Datei-Open-API bekommt verkettete Benutzereingabe';
      ShortDesc: 'Datei-Open mit Pfad aus Benutzereingabe zusammengesetzt - Path-Traversal-Risiko; Eingabe validieren/normalisieren'
    ),
    // SCA179
    (
      RuleID   : 'SCA179';
      Name     : 'DUnitX-Attribut [Ignore] ohne Begr' + #$FC + 'ndung';
      ShortDesc: '[Ignore] ohne Begr' + #$FC + 'ndungs-String ' + #$FC +
        'berspringt den Test stillschweigend - Nachricht erg' + #$E4 +
        'nzen, warum er deaktiviert ist'
    ),
    // SCA180
    (
      RuleID   : 'SCA180';
      Name     : 'Dasselbe Attribut zweimal am selben Member';
      ShortDesc: 'Zwei identische [X]-Attribute am selben Member - Copy-Paste-Rest ohne Wirkung'
    ),
    // SCA181
    (
      RuleID   : 'SCA181';
      Name     : 'DUnitX-Attribut [Category] ohne Kategorienamen';
      ShortDesc: '[Category] ohne Argument ist in DUnitX ein Compile-Fehler - immer einen Kategorienamen ' +
        #$FC + 'bergeben'
    ),
    // SCA182
    (
      RuleID   : 'SCA182';
      Name     : '[TestFixture]-Klasse ohne [Test]-Methode';
      ShortDesc: 'Klasse ist [TestFixture], enth' + #$E4 +
        'lt aber keine [Test]-Methoden - Zombie-Fixture: sichtbar in TestInsight, wird aber nie ausgef' +
        #$FC + 'hrt'
    ),
    // SCA183
    (
      RuleID   : 'SCA183';
      Name     : 'Attribut mit Leerzeile vor dem Ziel-Member';
      ShortDesc: 'Attributzeile gefolgt von einer Leerzeile - optisch losgel' + #$F6 +
        'st, oft ein Refactoring-Rest'
    ),
    // SCA184
    (
      RuleID   : 'SCA184';
      Name     : 'Ungenutzte DFM-Komponente';
      ShortDesc: 'DFM-Komponente wird weder im Code noch in anderen Units noch im DFM referenziert - vermutlich ein Refactoring-Rest'
    ),
    // SCA185
    (
      RuleID   : 'SCA185';
      Name     : 'UTF-8-Quelldatei ohne BOM';
      ShortDesc: 'UTF-8-Datei ohne BOM mit Nicht-ASCII - der Compiler liest sie als ANSI (Mojibake)'
    ),
    // SCA186
    (
      RuleID   : 'SCA186';
      Name     : 'Ung' + #$FC + 'ltige UTF-8-Folge in der Quelldatei';
      ShortDesc: 'Fehlerhaftes UTF-8 (' + #$FC + 'berlang, Surrogat oder au' + #$DF +
        'erhalb des Bereichs) unter einem UTF-8-BOM'
    ),
    // SCA187
    (
      RuleID   : 'SCA187';
      Name     : 'NUL- oder Steuerbyte in der Quelldatei';
      ShortDesc: 'NUL oder unzul' + #$E4 + 'ssiges Steuerbyte - Bin' + #$E4 +
        'rdatei oder falsch erkannte Kodierung'
    ),
    // SCA188
    (
      RuleID   : 'SCA188';
      Name     : 'Bidirektionales Steuerzeichen (Trojan Source)';
      ShortDesc: 'Bidi-Override- oder Isolate-Steuerzeichen - der Quelltext liest sich anders, als er kompiliert'
    ),
    // SCA189
    (
      RuleID   : 'SCA189';
      Name     : 'ANSI-Quelldatei mit Nicht-ASCII-Inhalt';
      ShortDesc: '8-Bit-Quelltext (kein BOM, kein g' + #$FC + 'ltiges UTF-8) - codepage-abh' + #$E4 +
        'ngig und nicht portabel'
    ),
    // SCA190
    (
      RuleID   : 'SCA190';
      Name     : 'UTF-16-Quelldatei';
      ShortDesc: 'UTF-16-Quelltext - kompiliert, aber ungew' + #$F6 + 'hnlich und werkzeug-unfreundlich'
    ),
    // SCA191
    (
      RuleID   : 'SCA191';
      Name     : 'UTF-32-/UCS-4-Quelldatei';
      ShortDesc: 'UTF-32-Quelltext - der Delphi-Compiler weist ihn mit dem fatalen Fehler F2438 zur' + #$FC +
        'ck'
    ),
    // SCA192
    (
      RuleID   : 'SCA192';
      Name     : 'Unsichtbares Zeichen ohne Breite im Quelltext';
      ShortDesc: 'Unsichtbares Unicode-Zeichen ohne Breite - Vektor f' + #$FC +
        'r versteckten Text und Homoglyphen-Missbrauch'
    ),
    // SCA193
    (
      RuleID   : 'SCA193';
      Name     : 'Nicht-ASCII-Zeichen im Bezeichner';
      ShortDesc: 'Der Bezeichner enth' + #$E4 +
        'lt einen Nicht-ASCII-Buchstaben - Risiko durch Homoglyphen und verwechselbare Zeichen'
    ),
    // SCA194
    (
      RuleID   : 'SCA194';
      Name     : 'Quelldatei geh' + #$F6 + 'rt nicht zum Projekt';
      ShortDesc: 'Eine .pas-/.dfm-Datei liegt im Projektordner, ist aber nicht im Projekt (.dproj/.groupproj) referenziert - vermutlich verwaist'
    ),
    // SCA195
    (
      RuleID   : 'SCA195';
      Name     : 'Unit wird vom Projekt genutzt, ist aber nicht darin enthalten';
      ShortDesc: 'Eine .pas-Datei wird von Projekt-Units per uses gezogen (kompiliert ' + #$FC +
        'ber den Suchpfad), steht aber nicht in der Projektdatei (.dproj/.groupproj) - ins Projekt aufnehmen'
    ),
    // SCA196
    (
      RuleID   : 'SCA196';
      Name     : 'Result eines verwalteten Typs wird gelesen, bevor es zugewiesen wurde';
      ShortDesc: 'Result eines verwalteten R' + #$FC +
        'ckgabetyps wird vor der ersten Zuweisung gelesen - es ist ein Alias der Zielvariablen des Aufrufers und tr' +
        #$E4 + 'gt deren ALTEN Wert. Zuerst initialisieren (nil / [] / '''')'
    ),
    // SCA197
    (
      RuleID   : 'SCA197';
      Name     : 'Interface ohne GUID deklariert';
      ShortDesc: 'Interface hat keine GUID - Supports() und QueryInterface() k' + #$F6 +
        'nnen zur Laufzeit nicht danach fragen. Mit Strg+Umschalt+G eine erzeugen'
    ),
    // SCA198
    (
      RuleID   : 'SCA198';
      Name     : 'Zwei Interfaces teilen sich dieselbe GUID';
      ShortDesc: 'Dieselbe GUID steht an mehr als einem Interface - Supports() liefert das zuerst registrierte, ohne Compilerfehler. Mit Strg+Umschalt+G eine neue erzeugen'
    )
  );

  // Index == Ord(TFindingKind), Drift-Guard im Leser wie bei
  // RULE_CATALOG_DATA (RuleID muss zur Position passen).
  RULE_OVERLAY_FR : array[0..197] of TRuleOverlayData = (
    // SCA001
    (
      RuleID   : 'SCA001';
      Name     : 'Objet cr' + #$E9 + #$E9 + ' sans try/finally';
      ShortDesc: 'Objet cr' + #$E9 + #$E9 + ' mais jamais lib' + #$E9 + 'r' + #$E9 + ' (fuite m' + #$E9 +
        'moire possible)'
    ),
    // SCA002
    (
      RuleID   : 'SCA002';
      Name     : 'Bloc except vide';
      ShortDesc: 'Un bloc except vide avale silencieusement toutes les exceptions'
    ),
    // SCA003
    (
      RuleID   : 'SCA003';
      Name     : 'Cha' + #$EE + 'ne SQL construite par concat' + #$E9 + 'nation';
      ShortDesc: 'Cha' + #$EE + 'ne SQL concat' + #$E9 + 'n' + #$E9 + 'e avec ''+'' ' + #$E0 +
        ' partir d''une saisie contr' + #$F4 + 'lable (risque d''injection)'
    ),
    // SCA004
    (
      RuleID   : 'SCA004';
      Name     : 'Identifiant / jeton d''API en dur';
      ShortDesc: 'Mot de passe, cl' + #$E9 + ' d''API ou jeton sous forme de litt' + #$E9 + 'ral cha' + #$EE +
        'ne dans le code source'
    ),
    // SCA005
    (
      RuleID   : 'SCA005';
      Name     : 'Format() : nombre de marqueurs incoh' + #$E9 + 'rent';
      ShortDesc: 'Le nombre de marqueurs de Format() / FormatUtf8() ne correspond pas au nombre d''arguments'
    ),
    // SCA006
    (
      RuleID   : 'SCA006';
      Name     : 'Le fichier n''a pas pu ' + #$EA + 'tre lu ou analys' + #$E9;
      ShortDesc: 'Erreur d''analyse ou d''E/S - fichier source illisible ou syntaxiquement cass' + #$E9
    ),
    // SCA007
    (
      RuleID   : 'SCA007';
      Name     : 'Unit inutilis' + #$E9 + 'e dans la clause uses';
      ShortDesc: 'Entr' + #$E9 + 'e uses probablement inutilis' + #$E9 +
        'e (aucun identifiant qui en provienne n''est r' + #$E9 + 'f' + #$E9 + 'renc' + #$E9 + ')'
    ),
    // SCA008
    (
      RuleID   : 'SCA008';
      Name     : 'D' + #$E9 + 'r' + #$E9 + 'f' + #$E9 + 'rencement nil possible';
      ShortDesc: 'Acc' + #$E8 + 's a une variable qui peut valoir nil a cet endroit'
    ),
    // SCA009
    (
      RuleID   : 'SCA009';
      Name     : 'Objet cr' + #$E9 + #$E9 + ' sans try/finally protecteur';
      ShortDesc: 'Appel .Create sans try/finally englobant - risque de fuite en cas d''exception'
    ),
    // SCA010
    (
      RuleID   : 'SCA010';
      Name     : 'Division par z' + #$E9 + 'ro possible';
      ShortDesc: 'Division par une variable ou une expression pouvant valoir z' + #$E9 + 'ro'
    ),
    // SCA011
    (
      RuleID   : 'SCA011';
      Name     : 'Le code apr' + #$E8 + 's Exit/Raise est inatteignable';
      ShortDesc: 'L''instruction qui suit Exit, raise ou Halt est du code mort'
    ),
    // SCA012
    (
      RuleID   : 'SCA012';
      Name     : 'La m' + #$E9 + 'thode d' + #$E9 + 'passe le seuil de lignes';
      ShortDesc: 'M' + #$E9 + 'thode plus longue que le maximum configur' + #$E9 + ' (80 lignes par d' + #$E9 +
        'faut)'
    ),
    // SCA013
    (
      RuleID   : 'SCA013';
      Name     : 'Trop de param' + #$E8 + 'tres';
      ShortDesc: 'La m' + #$E9 + 'thode a plus de param' + #$E8 + 'tres que le maximum configur' + #$E9 +
        ' (7 par d' + #$E9 + 'faut)'
    ),
    // SCA014
    (
      RuleID   : 'SCA014';
      Name     : 'Litt' + #$E9 + 'ral num' + #$E9 + 'rique sans constante nomm' + #$E9 + 'e';
      ShortDesc: 'Litt' + #$E9 + 'ral num' + #$E9 +
        'rique dans une expression - extraire vers une constante nomm' + #$E9 + 'e'
    ),
    // SCA015
    (
      RuleID   : 'SCA015';
      Name     : 'Litt' + #$E9 + 'ral cha' + #$EE + 'ne r' + #$E9 + 'p' + #$E9 + 't' + #$E9 +
        ' a plusieurs endroits';
      ShortDesc: 'Le m' + #$EA + 'me litt' + #$E9 + 'ral cha' + #$EE + 'ne appara' + #$EE +
        't N fois ou plus - extraire vers une constante'
    ),
    // SCA016
    (
      RuleID   : 'SCA016';
      Name     : 'Chemin de fichier en litt' + #$E9 + 'ral cha' + #$EE + 'ne';
      ShortDesc: 'Chemin C:\, UNC ou Linux ' + #$E9 + 'crit en dur dans le source'
    ),
    // SCA017
    (
      RuleID   : 'SCA017';
      Name     : 'WriteLn/ShowMessage en code de production';
      ShortDesc: 'Instruction de sortie de d' + #$E9 + 'bogage trouv' + #$E9 +
        'e dans une unit de production'
    ),
    // SCA018
    (
      RuleID   : 'SCA018';
      Name     : 'L''imbrication de blocs d' + #$E9 + 'passe le seuil';
      ShortDesc: 'Profondeur d''imbrication if/for/while sup' + #$E9 + 'rieure au maximum configur' + #$E9 +
        ' (4 par d' + #$E9 + 'faut)'
    ),
    // SCA019
    (
      RuleID   : 'SCA019';
      Name     : 'Marqueur TODO/FIXME en commentaire';
      ShortDesc: 'Marqueur TODO, FIXME, HACK ou XXX ouvert - a traiter avant la livraison'
    ),
    // SCA020
    (
      RuleID   : 'SCA020';
      Name     : 'Corps de m' + #$E9 + 'thode vide';
      ShortDesc: 'Le corps de la m' + #$E9 + 'thode ne contient aucune instruction'
    ),
    // SCA021
    (
      RuleID   : 'SCA021';
      Name     : 'Bloc de code dupliqu' + #$E9;
      ShortDesc: 'Plusieurs blocs de code identiques (' + #$E0 +
        ' partir du nombre minimal de lignes configur' + #$E9 + ')'
    ),
    // SCA022
    (
      RuleID   : 'SCA022';
      Name     : 'La m' + #$E9 + 'thode d' + #$E9 + 'passe le seuil de complexit' + #$E9 + ' de McCabe';
      ShortDesc: 'Complexit' + #$E9 + ' cyclomatique sup' + #$E9 + 'rieure au seuil configur' + #$E9 +
        ' (10 par d' + #$E9 + 'faut)'
    ),
    // SCA023
    (
      RuleID   : 'SCA023';
      Name     : 'R' + #$E8 + 'gle personnalis' + #$E9 + 'e';
      ShortDesc: 'Motif d' + #$E9 + 'tect' + #$E9 + ' par une r' + #$E8 + 'gle charg' + #$E9 +
        'e depuis analyser-rules.yml'
    ),
    // SCA024
    (
      RuleID   : 'SCA024';
      Name     : 'Composant au nom par d' + #$E9 + 'faut';
      ShortDesc: 'Le composant porte encore le nom par d' + #$E9 +
        'faut de l''assistant (Button1, Edit3, Panel2 ...)'
    ),
    // SCA025
    (
      RuleID   : 'SCA025';
      Name     : 'Texte d''interface en dur dans le DFM';
      ShortDesc: 'Caption, Hint ou Text sous forme de litt' + #$E9 +
        'ral dans le DFM, sans passer par la couche i18n'
    ),
    // SCA026
    (
      RuleID   : 'SCA026';
      Name     : 'Identifiants de base de donn' + #$E9 + 'es en dur dans le DFM';
      ShortDesc: 'Password en clair ou ConnectionString avec Pwd= sur un composant de base de donn' + #$E9 +
        'es'
    ),
    // SCA027
    (
      RuleID   : 'SCA027';
      Name     : 'Liaison (DataSource, DataField) en double';
      ShortDesc: 'Deux contr' + #$F4 + 'les ou plus lient le m' + #$EA + 'me couple DataSource / DataField'
    ),
    // SCA028
    (
      RuleID   : 'SCA028';
      Name     : 'Le gestionnaire d''' + #$E9 + 'v' + #$E9 + 'nement DFM pointe vers une m' + #$E9 +
        'thode absente';
      ShortDesc: 'OnClick / On... renvoie a une m' + #$E9 +
        'thode qui n''existe pas dans la classe de la fiche'
    ),
    // SCA029
    (
      RuleID   : 'SCA029';
      Name     : 'Gestionnaire d''' + #$E9 + 'v' + #$E9 + 'nement orphelin';
      ShortDesc: 'M' + #$E9 + 'thode published de forme TNotifyEvent sans liaison DFM'
    ),
    // SCA030
    (
      RuleID   : 'SCA030';
      Name     : 'Gestionnaire d''' + #$E9 + 'v' + #$E9 + 'nement li' + #$E9 + ' mais vide';
      ShortDesc: 'L''' + #$E9 + 'v' + #$E9 + 'nement est c' + #$E2 + 'bl' + #$E9 + ' dans le DFM, la m' +
        #$E9 + 'thode existe, le corps est vide'
    ),
    // SCA031
    (
      RuleID   : 'SCA031';
      Name     : 'Composant DFM sans champ published';
      ShortDesc: 'Le composant du DFM n''a pas de champ published correspondant dans la classe de la fiche - entr' +
        #$E9 + 'e DFM p' + #$E9 + 'rim' + #$E9 + 'e (d' + #$E9 + 'rive de sch' + #$E9 + 'ma)'
    ),
    // SCA032
    (
      RuleID   : 'SCA032';
      Name     : 'Boucle DataSource / ma' + #$EE + 'tre-detail circulaire';
      ShortDesc: 'Cycle dans les ar' + #$EA + 'tes DataSource.DataSet / DataSet.MasterSource'
    ),
    // SCA033
    (
      RuleID   : 'SCA033';
      Name     : 'Propri' + #$E9 + 't' + #$E9 + ' SQL construite depuis une saisie d''interface';
      ShortDesc: 'Query.SQL assembl' + #$E9 + 'e ' + #$E0 + ' partir des propri' + #$E9 + 't' + #$E9 +
        's Text ou Caption de contr' + #$F4 + 'les de fiche'
    ),
    // SCA034
    (
      RuleID   : 'SCA034';
      Name     : 'Champ obligatoire sans liaison d''interface';
      ShortDesc: 'Un TField avec Required=True n''a aucun contr' + #$F4 + 'le de saisie li' + #$E9
    ),
    // SCA035
    (
      RuleID   : 'SCA035';
      Name     : 'Champ obligatoire li' + #$E9 + ' uniquement a des contr' + #$F4 + 'les cach' + #$E9 + 's';
      ShortDesc: 'Un TField avec Required=True n''est li' + #$E9 + ' qu''a des contr' + #$F4 +
        'les ayant Visible=False'
    ),
    // SCA036
    (
      RuleID   : 'SCA036';
      Name     : 'Type de contr' + #$F4 + 'le incompatible avec le TField';
      ShortDesc: 'La classe du contr' + #$F4 + 'le de donn' + #$E9 +
        'es ne correspond pas a TField.DataType (TDBEdit pour un TBooleanField)'
    ),
    // SCA037
    (
      RuleID   : 'SCA037';
      Name     : 'TabOrder en double entre fr' + #$E8 + 'res';
      ShortDesc: 'Deux contr' + #$F4 + 'les fr' + #$E8 + 'res du m' + #$EA + 'me parent partagent la m' +
        #$EA + 'me valeur TabOrder'
    ),
    // SCA038
    (
      RuleID   : 'SCA038';
      Name     : 'Le composant utilise une classe interdite';
      ShortDesc: 'La classe du composant figure dans la liste ForbiddenClasses du projet'
    ),
    // SCA039
    (
      RuleID   : 'SCA039';
      Name     : 'Composant de base de donn' + #$E9 + 'es sur une fiche d''interface';
      ShortDesc: 'TFDQuery / TFDConnection directement sur un TForm ou TFrame au lieu d''un DataModule'
    ),
    // SCA040
    (
      RuleID   : 'SCA040';
      Name     : 'Acc' + #$E8 + 's a un champ d''une autre fiche';
      ShortDesc: 'Du code dans Form1 lit ou ' + #$E9 + 'crit directement Form2.<champ_published>'
    ),
    // SCA041
    (
      RuleID   : 'SCA041';
      Name     : 'Contr' + #$F4 + 'le de saisie directement sur le TForm';
      ShortDesc: 'Le contr' + #$F4 + 'le de saisie est pos' + #$E9 + ' sur la fiche au lieu d''' + #$EA +
        'tre plac' + #$E9 + ' dans un TPanel ou un TGroupBox'
    ),
    // SCA042
    (
      RuleID   : 'SCA042';
      Name     : 'Gestionnaire d''' + #$E9 + 'v' + #$E9 + 'nement surcharge';
      ShortDesc: 'Une seule m' + #$E9 + 'thode est c' + #$E2 + 'bl' + #$E9 + 'e sur N ' + #$E9 + 'v' + #$E9 +
        'nements de composants ou plus (N=5 par d' + #$E9 + 'faut)'
    ),
    // SCA043
    (
      RuleID   : 'SCA043';
      Name     : 'Le composant a Action et OnClick';
      ShortDesc: 'Action et OnClick sont tous deux d' + #$E9 +
        'finis - Action l''emporte, OnClick est du code mort'
    ),
    // SCA044
    (
      RuleID   : 'SCA044';
      Name     : 'Longue concat' + #$E9 + 'nation - pr' + #$E9 + 'f' + #$E9 + 'rer Format()';
      ShortDesc: 'Concat' + #$E9 + 'nation de cha' + #$EE +
        'ne en plusieurs segments - a transformer en appel a Format()'
    ),
    // SCA045
    (
      RuleID   : 'SCA045';
      Name     : 'with X do ...';
      ShortDesc: 'Instruction with - pi' + #$E8 + 'ge de masquage de port' + #$E9 +
        'e contre lequel le compilateur n''avertit pas'
    ),
    // SCA046
    (
      RuleID   : 'SCA046';
      Name     : 'for i := High to Low - downto manquant';
      ShortDesc: 'for i := 10 to 1 do - le corps de boucle ne s''ex' + #$E9 + 'cute jamais'
    ),
    // SCA047
    (
      RuleID   : 'SCA047';
      Name     : 'x := x';
      ShortDesc: 'Auto-affectation - sans effet, ou faute de copier-coller'
    ),
    // SCA048
    (
      RuleID   : 'SCA048';
      Name     : 'Appel virtuel dans le constructeur';
      ShortDesc: 'M' + #$E9 + 'thode virtuelle appel' + #$E9 + 'e depuis le constructeur - la classe d' +
        #$E9 + 'riv' + #$E9 + 'e voit un Self ' + #$E0 + ' moiti' + #$E9 + ' initialis' + #$E9
    ),
    // SCA049
    (
      RuleID   : 'SCA049';
      Name     : 'Length(s) - N sans garde';
      ShortDesc: 'Length ou .Count avec soustraction - d' + #$E9 +
        'passement par le bas du type non signe quand c''est vide'
    ),
    // SCA050
    (
      RuleID   : 'SCA050';
      Name     : 'Le membre public pourrait ' + #$EA + 'tre priv' + #$E9 + ' a l''unit';
      ShortDesc: 'Ce membre public n''est r' + #$E9 + 'f' + #$E9 + 'renc' + #$E9 +
        ' que dans l''unit courante - le `private` classique de Delphi (port' + #$E9 +
        'e unit) suffit'
    ),
    // SCA051
    (
      RuleID   : 'SCA051';
      Name     : 'Le membre public pourrait ' + #$EA + 'tre protected';
      ShortDesc: 'Membre public r' + #$E9 + 'f' + #$E9 + 'renc' + #$E9 + ' uniquement depuis des classes d' +
        #$E9 + 'riv' + #$E9 + 'es, jamais de l''ext' + #$E9 + 'rieur'
    ),
    // SCA052
    (
      RuleID   : 'SCA052';
      Name     : 'Membre public inutilis' + #$E9 + ' (API morte)';
      ShortDesc: 'Le membre public n''est r' + #$E9 + 'f' + #$E9 + 'renc' + #$E9 + ' par aucune classe d' +
        #$E9 + 'riv' + #$E9 + 'e ni par aucun chemin inter-unit'
    ),
    // SCA053
    (
      RuleID   : 'SCA053';
      Name     : 'Variable locale inutilis' + #$E9 + 'e';
      ShortDesc: 'Variable locale d' + #$E9 + 'clar' + #$E9 + 'e mais jamais r' + #$E9 + 'f' + #$E9 + 'renc' +
        #$E9 + 'e dans le corps de la m' + #$E9 + 'thode'
    ),
    // SCA054
    (
      RuleID   : 'SCA054';
      Name     : 'Param' + #$E8 + 'tre de m' + #$E9 + 'thode inutilis' + #$E9;
      ShortDesc: 'Le param' + #$E8 + 'tre de la m' + #$E9 + 'thode n''est jamais utilise dans le corps'
    ),
    // SCA055
    (
      RuleID   : 'SCA055';
      Name     : 'Expression bool' + #$E9 + 'enne tautologique';
      ShortDesc: 'Op' + #$E9 +
        'rateur binaire avec membres gauche et droit identiques : x = x, a and a, (p <> p)'
    ),
    // SCA056
    (
      RuleID   : 'SCA056';
      Name     : 'Ma' + #$EE + 'tre-detail sans MasterFields';
      ShortDesc: 'Le TDataSet a MasterSource mais ni MasterFields ni IndexFieldNames'
    ),
    // SCA057
    (
      RuleID   : 'SCA057';
      Name     : 'Fiche charg' + #$E9 + 'e de composants de donn' + #$E9 + 'es - extraire un DataModule';
      ShortDesc: 'Indication agr' + #$E9 + 'g' + #$E9 + 'e : la fiche porte N composants de base de donn' +
        #$E9 + 'es ou plus'
    ),
    // SCA058
    (
      RuleID   : 'SCA058';
      Name     : 'UPDATE / DELETE / TRUNCATE sans WHERE';
      ShortDesc: 'L''instruction SQL modifie toutes les lignes - clause WHERE manquante'
    ),
    // SCA059
    (
      RuleID   : 'SCA059';
      Name     : 'Format flottant dans Format() sans TFormatSettings';
      ShortDesc: '%.2f / %.3f sans TFormatSettings explicite - le pi' + #$E8 + 'ge du s' + #$E9 +
        'parateur d' + #$E9 + 'cimal virgule ou point'
    ),
    // SCA060
    (
      RuleID   : 'SCA060';
      Name     : 'Instruction goto';
      ShortDesc: '`goto` affaiblit le flot de contr' + #$F4 + 'le structure'
    ),
    // SCA061
    (
      RuleID   : 'SCA061';
      Name     : 'Tabulation dans le source';
      ShortDesc: 'Les tabulations s''affichent diff' + #$E9 + 'remment selon l''' + #$E9 +
        'diteur - utiliser des espaces'
    ),
    // SCA062
    (
      RuleID   : 'SCA062';
      Name     : 'Ligne de source trop longue';
      ShortDesc: 'La ligne d' + #$E9 + 'passe 120 caract' + #$E8 +
        'res - couper ou extraire une sous-expression'
    ),
    // SCA063
    (
      RuleID   : 'SCA063';
      Name     : 'Espaces en fin de ligne';
      ShortDesc: 'La ligne se termine par une espace ou une tabulation - hygi' + #$E8 + 'ne pour les diffs'
    ),
    // SCA064
    (
      RuleID   : 'SCA064';
      Name     : 'Mot-cl' + #$E9 + ' Pascal pas en minuscules';
      ShortDesc: 'Les mots-cl' + #$E9 + 's Pascal (`begin`/`end`/`procedure`/...) doivent ' + #$EA +
        'tre en minuscules'
    ),
    // SCA065
    (
      RuleID   : 'SCA065';
      Name     : 'Marqueur de suppression NOSONAR';
      ShortDesc: '`// NOSONAR` ne devrait pas faire taire des r' + #$E9 + 'sultats - v' + #$E9 +
        'rifier l''usage'
    ),
    // SCA066
    (
      RuleID   : 'SCA066';
      Name     : 'Liste d''arguments vide';
      ShortDesc: '`Foo()` devrait s''' + #$E9 + 'crire `Foo;` - supprimer les parenth' + #$E8 + 'ses vides'
    ),
    // SCA067
    (
      RuleID   : 'SCA067';
      Name     : 'Bloc assembleur en ligne';
      ShortDesc: 'Bloc `asm...end` - pr' + #$E9 + 'f' + #$E9 + 'rer Pascal et les intrins' + #$E8 +
        'ques du compilateur'
    ),
    // SCA068
    (
      RuleID   : 'SCA068';
      Name     : 'Virgule finale dans la liste d''arguments';
      ShortDesc: '`Foo(A, B,)` - supprimer la virgule ou ajouter l''argument manquant'
    ),
    // SCA069
    (
      RuleID   : 'SCA069';
      Name     : 'Litt' + #$E9 + 'ral entier sans s' + #$E9 + 'parateur de milliers';
      ShortDesc: 'Les grands litt' + #$E9 + 'raux entiers devraient utiliser le s' + #$E9 + 'parateur `_`'
    ),
    // SCA070
    (
      RuleID   : 'SCA070';
      Name     : 'Code en commentaire';
      ShortDesc: 'Le commentaire ressemble a du code Pascal - supprimer ou justifier'
    ),
    // SCA071
    (
      RuleID   : 'SCA071';
      Name     : 'Mot-cl' + #$E9 + ' de section d''unit qui n''est pas en colonne 1';
      ShortDesc: '`unit`/`interface`/`uses`/`implementation`/`initialization`/`finalization` doivent commencer en colonne 1'
    ),
    // SCA072
    (
      RuleID   : 'SCA072';
      Name     : 'Comparaison bool' + #$E9 + 'enne redondante';
      ShortDesc: '`X = True` devrait s''' + #$E9 + 'crire `X` (et `X <> False` de m' + #$EA + 'me)'
    ),
    // SCA073
    (
      RuleID   : 'SCA073';
      Name     : 'D' + #$E9 + 'claration d''interface vide';
      ShortDesc: 'Une interface sans m' + #$E9 + 'thode ni propri' + #$E9 + 't' + #$E9 +
        ' ne porte aucun contrat'
    ),
    // SCA074
    (
      RuleID   : 'SCA074';
      Name     : 'Assert sans message';
      ShortDesc: '`Assert(cond);` - ajouter un message `''pourquoi''` pour le diagnostic'
    ),
    // SCA075
    (
      RuleID   : 'SCA075';
      Name     : 'H' + #$E9 + 'ritage explicite de TObject';
      ShortDesc: '`class(TObject)` est redondant - supprimer les parenth' + #$E8 + 'ses'
    ),
    // SCA076
    (
      RuleID   : 'SCA076';
      Name     : 'D' + #$E9 + 'claration group' + #$E9 + 'e de variables, champs ou param' + #$E8 + 'tres';
      ShortDesc: 'S' + #$E9 + 'parer `A, B: Type` en une d' + #$E9 + 'claration par ligne'
    ),
    // SCA077
    (
      RuleID   : 'SCA077';
      Name     : 'Bloc begin..end vide';
      ShortDesc: '`begin..end` vide - le supprimer ou ' + #$E9 + 'crire l''instruction'
    ),
    // SCA078
    (
      RuleID   : 'SCA078';
      Name     : 'Capture g' + #$E9 + 'n' + #$E9 + 'rale sur la classe racine Exception';
      ShortDesc: '`on E: Exception do` avale tout, y compris les violations d''acc' + #$E8 + 's et l''' +
        #$E9 + 'puisement m' + #$E9 + 'moire'
    ),
    // SCA079
    (
      RuleID   : 'SCA079';
      Name     : 'Sections const/type/var cons' + #$E9 + 'cutives';
      ShortDesc: 'Deux blocs `const`, `type` ou `var` qui se suivent devraient ' + #$EA + 'tre fusionn' +
        #$E9 + 's'
    ),
    // SCA080
    (
      RuleID   : 'SCA080';
      Name     : 'Exit/Continue redondant avant end';
      ShortDesc: '`Exit;` / `Continue;` juste avant `end` est sans effet'
    ),
    // SCA081
    (
      RuleID   : 'SCA081';
      Name     : 'Plusieurs d' + #$E9 + 'clarations de classe dans un fichier';
      ShortDesc: 'Une classe par unit facilite le remaniement'
    ),
    // SCA082
    (
      RuleID   : 'SCA082';
      Name     : 'Point-virgule double';
      ShortDesc: '`;;` - supprimer le point-virgule superflu'
    ),
    // SCA083
    (
      RuleID   : 'SCA083';
      Name     : 'Bloc finally vide';
      ShortDesc: '`try ... finally end;` ne lib' + #$E9 + 'r' + #$E9 + ' rien - compl' + #$E9 +
        'ter ou supprimer le finally'
    ),
    // SCA084
    (
      RuleID   : 'SCA084';
      Name     : 'Test Assigned + nil redondant';
      ShortDesc: '`Assigned(X) and (X <> nil)` - supprimer le test nil'
    ),
    // SCA085
    (
      RuleID   : 'SCA085';
      Name     : 'X.Free; X := nil; devrait ' + #$EA + 'tre FreeAndNil(X)';
      ShortDesc: 'Utiliser `FreeAndNil(X)` au lieu de `X.Free; X := nil;`'
    ),
    // SCA086
    (
      RuleID   : 'SCA086';
      Name     : #$C9 + 'viter le modificateur out';
      ShortDesc: 'Pr' + #$E9 + 'f' + #$E9 + 'rer `var` a `out` (out a une s' + #$E9 + 'mantique surprenante)'
    ),
    // SCA087
    (
      RuleID   : 'SCA087';
      Name     : 'Section de visibilit' + #$E9 + ' vide dans la classe';
      ShortDesc: 'En-t' + #$EA + 'te de section `public`/`private`/... sans aucun membre'
    ),
    // SCA088
    (
      RuleID   : 'SCA088';
      Name     : 'Initialisation d''unit ' + #$E0 + ' l''ancienne begin..end.';
      ShortDesc: 'Utiliser `initialization..end.` plut' + #$F4 + 't que l''ancien `begin..end.`'
    ),
    // SCA089
    (
      RuleID   : 'SCA089';
      Name     : 'Champ public dans la classe';
      ShortDesc: 'Un champ public rompt l''encapsulation - utiliser une propri' + #$E9 + 't' + #$E9
    ),
    // SCA090
    (
      RuleID   : 'SCA090';
      Name     : 'Bloc try imbriqu' + #$E9;
      ShortDesc: '`try..end` imbriqu' + #$E9 + ' - extraire le try interne dans une m' + #$E9 + 'thode'
    ),
    // SCA091
    (
      RuleID   : 'SCA091';
      Name     : 'Instruction case volumineuse';
      ShortDesc: '`case` avec 10 branches ou plus - envisager le polymorphisme ou une table de dispatch'
    ),
    // SCA092
    (
      RuleID   : 'SCA092';
      Name     : 'Unit sans aucune d' + #$E9 + 'claration';
      ShortDesc: 'L''unit n''a ni type, ni const, ni var, ni proc' + #$E9 +
        'dure/function - supprimer ou compl' + #$E9 + 'ter'
    ),
    // SCA093
    (
      RuleID   : 'SCA093';
      Name     : 'Plusieurs appels inherited dans une m' + #$E9 + 'thode';
      ShortDesc: 'Deux `inherited;` ou plus dans la m' + #$EA + 'me m' + #$E9 +
        'thode - les effets de bord du parent s''ex' + #$E9 + 'cutent deux fois'
    ),
    // SCA094
    (
      RuleID   : 'SCA094';
      Name     : 'Doubles parenth' + #$E8 + 'ses redondantes';
      ShortDesc: '`((Ident))` - supprimer les parenth' + #$E8 + 'ses ext' + #$E9 + 'rieures'
    ),
    // SCA095
    (
      RuleID   : 'SCA095';
      Name     : 'Section de visibilit' + #$E9 + ' r' + #$E9 + 'p' + #$E9 + 't' + #$E9 + 'e';
      ShortDesc: 'La m' + #$EA + 'me section `public`/`private`/... appara' + #$EE +
        't deux fois dans une classe'
    ),
    // SCA096
    (
      RuleID   : 'SCA096';
      Name     : 'Constructeur sans appel a inherited';
      ShortDesc: 'Il manque `inherited Create` au constructeur - le parent reste non initialis' + #$E9
    ),
    // SCA097
    (
      RuleID   : 'SCA097';
      Name     : 'Destructeur sans appel a inherited';
      ShortDesc: 'Il manque `inherited Destroy` au destructeur - le nettoyage du parent est saut' + #$E9 +
        ' (risque de fuite)'
    ),
    // SCA098
    (
      RuleID   : 'SCA098';
      Name     : 'Affectation conditionnelle redondante';
      ShortDesc: '`if Cond then X := True else X := False` devrait s''' + #$E9 + 'crire `X := Cond`'
    ),
    // SCA099
    (
      RuleID   : 'SCA099';
      Name     : 'begin/end asym' + #$E9 + 'trique dans if/else';
      ShortDesc: 'La branche then utilise `begin..end` mais la branche else est une instruction unique'
    ),
    // SCA100
    (
      RuleID   : 'SCA100';
      Name     : 'Alias de type pointeur sans pr' + #$E9 + 'fixe P';
      ShortDesc: '`Foo = ^Bar` devrait s''' + #$E9 + 'crire `PBar = ^Bar` (convention du pr' + #$E9 +
        'fixe P)'
    ),
    // SCA101
    (
      RuleID   : 'SCA101';
      Name     : 'Branche sans bloc begin..end';
      ShortDesc: '`then`/`else`/`do <instruction>` - pr' + #$E9 + 'f' + #$E9 +
        'rer un `begin..end` explicite'
    ),
    // SCA102
    (
      RuleID   : 'SCA102';
      Name     : 'Routine imbriqu' + #$E9 + 'e dans une m' + #$E9 + 'thode';
      ShortDesc: 'Proc' + #$E9 + 'dure ou fonction locale imbriqu' + #$E9 +
        'e - a extraire au niveau de l''unit'
    ),
    // SCA103
    (
      RuleID   : 'SCA103';
      Name     : 'Champ de classe sans pr' + #$E9 + 'fixe F';
      ShortDesc: 'Les champs de classe doivent suivre la convention `F<Nom>`'
    ),
    // SCA104
    (
      RuleID   : 'SCA104';
      Name     : 'Type classe ou record sans pr' + #$E9 + 'fixe T';
      ShortDesc: 'Les alias de type classe et record doivent commencer par `T`'
    ),
    // SCA105
    (
      RuleID   : 'SCA105';
      Name     : 'Type interface sans pr' + #$E9 + 'fixe I';
      ShortDesc: 'Les alias d''interface doivent commencer par `I` (`IFoo = interface`)'
    ),
    // SCA106
    (
      RuleID   : 'SCA106';
      Name     : 'M' + #$E9 + 'thode pas en PascalCase';
      ShortDesc: 'Les m' + #$E9 + 'thodes doivent commencer par une majuscule (PascalCase)'
    ),
    // SCA107
    (
      RuleID   : 'SCA107';
      Name     : 'Le membre public pourrait ' + #$EA + 'tre strict private';
      ShortDesc: 'Le membre public n''est r' + #$E9 + 'f' + #$E9 + 'renc' + #$E9 + ' QUE par des m' + #$E9 +
        'thodes de sa propre classe - `strict private` atteint l''encapsulation la plus forte'
    ),
    // SCA108
    (
      RuleID   : 'SCA108';
      Name     : 'TThread.Synchronize depuis le destructeur';
      ShortDesc: 'Synchronize() appel' + #$E9 +
        ' depuis le destructeur Destroy - l''interblocage classique entre le thread de travail et celui de l''interface'
    ),
    // SCA109
    (
      RuleID   : 'SCA109';
      Name     : 'Verrou pris sans lib' + #$E9 + 'ration par try/finally';
      ShortDesc: 'TCriticalSection, Monitor ou verrou WinAPI pris sans try..finally englobant - une exception laisse le verrou pos' +
        #$E9
    ),
    // SCA110
    (
      RuleID   : 'SCA110';
      Name     : 'Concat' + #$E9 + 'nation de cha' + #$EE + 'ne dans une boucle';
      ShortDesc: '`s := s + x` dans for/while/repeat - r' + #$E9 + 'allocations quadratiques'
    ),
    // SCA111
    (
      RuleID   : 'SCA111';
      Name     : 'ParamByName(...) appel' + #$E9 + ' dans une boucle';
      ShortDesc: '`Query.ParamByName(''x'').AsXxx := ...` dans une boucle - recherche lin' + #$E9 + 'aire ' +
        #$E0 + ' chaque it' + #$E9 + 'ration'
    ),
    // SCA112
    (
      RuleID   : 'SCA112';
      Name     : 'FieldByName(...) appel' + #$E9 + ' dans une boucle';
      ShortDesc: '`DataSet.FieldByName(''x'').AsXxx` dans une boucle - recherche lin' + #$E9 + 'aire ' + #$E0 +
        ' chaque enregistrement'
    ),
    // SCA113
    (
      RuleID   : 'SCA113';
      Name     : 'TThread.Resume est obsol' + #$E8 + 'te';
      ShortDesc: '`MyThread.Resume` - utiliser `MyThread.Start` (depuis Delphi 2010)'
    ),
    // SCA114
    (
      RuleID   : 'SCA114';
      Name     : 'TThread lib' + #$E9 + 'r' + #$E9 + ' sans Terminate+WaitFor';
      ShortDesc: '`FreeAndNil(MyThread)` sans `Terminate; WaitFor` pr' + #$E9 +
        'alable - le thread de travail tourne peut-' + #$EA + 'tre encore'
    ),
    // SCA115
    (
      RuleID   : 'SCA115';
      Name     : 'URL HTTP en clair';
      ShortDesc: 'Litt' + #$E9 + 'ral `''http://...''` pour un point d''acc' + #$E8 + 's distant - vuln' +
        #$E9 + 'rable a l''interception'
    ),
    // SCA116
    (
      RuleID   : 'SCA116';
      Name     : 'V' + #$E9 + 'rification TLS d' + #$E9 + 'sactiv' + #$E9 + 'e';
      ShortDesc: '`SecureProtocols` vide, `IgnoreCertificateErrors := True` ou `OnVerifyPeer := nil`'
    ),
    // SCA117
    (
      RuleID   : 'SCA117';
      Name     : 'Membre public sans commentaire de documentation';
      ShortDesc: 'M' + #$E9 + 'thode ou propri' + #$E9 + 't' + #$E9 +
        ' publique dans la section `interface` sans commentaire de documentation juste au-dessus'
    ),
    // SCA118
    (
      RuleID   : 'SCA118';
      Name     : 'Classe d''exception sans pr' + #$E9 + 'fixe `E`';
      ShortDesc: 'Un descendant de `class(Exception)` doit suivre la convention `E<Nom>` de la RTL Delphi'
    ),
    // SCA119
    (
      RuleID   : 'SCA119';
      Name     : 'Constante locale pas en UPPER_SNAKE_CASE';
      ShortDesc: '`const X = 42;` dans une m' + #$E9 + 'thode - pr' + #$E9 + 'f' + #$E9 +
        'rer UPPER_SNAKE_CASE pour les constantes num' + #$E9 + 'riques'
    ),
    // SCA120
    (
      RuleID   : 'SCA120';
      Name     : 'Exception construite mais jamais lev' + #$E9 + 'e';
      ShortDesc: '`EFoo.Create(''msg'');` alloue un objet exception sans `raise` - le chemin d''erreur est saut' +
        #$E9 + ' silencieusement'
    ),
    // SCA121
    (
      RuleID   : 'SCA121';
      Name     : 'La fonction n''affecte jamais Result';
      ShortDesc: 'Le corps de la fonction se termine sans ' + #$E9 +
        'crire `Result` (ni `<NomFonction> := ...`) - la valeur de retour est ind' + #$E9 + 'finie'
    ),
    // SCA122
    (
      RuleID   : 'SCA122';
      Name     : 'Relev' + #$E9 + 'e de la variable d''exception li' + #$E9 + 'e';
      ShortDesc: '`on E: T do ... raise E;` perd la pile d''appels d''origine - le `raise;` nu la conserve'
    ),
    // SCA123
    (
      RuleID   : 'SCA123';
      Name     : 'Transtypage juste avant Free / Destroy';
      ShortDesc: '`TFoo(x).Free` - le transtypage ne change pas quel Destroy s''ex' + #$E9 +
        'cute (Destroy est virtuel)'
    ),
    // SCA124
    (
      RuleID   : 'SCA124';
      Name     : 'Constructeur appel' + #$E9 + ' sur une instance au lieu de la classe';
      ShortDesc: '`obj.Create` - appelle le constructeur comme m' + #$E9 +
        'thode sur une instance existante, saute l''allocation et r' + #$E9 +
        'initialise les champs par-dessus des donn' + #$E9 + 'es vivantes'
    ),
    // SCA125
    (
      RuleID   : 'SCA125';
      Name     : 'Red' + #$E9 + 'finition dont le corps se r' + #$E9 + 'duit a `inherited;`';
      ShortDesc: 'Une red' + #$E9 + 'finition qui ne fait que transmettre au parent ne sert ' + #$E0 +
        ' rien - la supprimer'
    ),
    // SCA126
    (
      RuleID   : 'SCA126';
      Name     : 'Utiliser Assigned() plut' + #$F4 + 't que `= nil` / `<> nil`';
      ShortDesc: 'Convention Pascal : `Assigned(x)` et `not Assigned(x)` sont les tests nil canoniques'
    ),
    // SCA127
    (
      RuleID   : 'SCA127';
      Name     : 'Lev' + #$E9 + 'e de la classe de base `Exception` au lieu d''une sous-classe';
      ShortDesc: '`raise Exception.Create(''...'')` - la classe de base ne porte aucune information s' + #$E9 +
        'mantique, les appelants ne peuvent pas filtrer s' + #$E9 + 'lectivement'
    ),
    // SCA128
    (
      RuleID   : 'SCA128';
      Name     : 'Appel de formatage d' + #$E9 + 'pendant de la locale sans TFormatSettings';
      ShortDesc: '`StrToDate(s)`, `FormatFloat(...)` et consorts sans TFormatSettings d' + #$E9 +
        'pendent de la locale syst' + #$E8 + 'me - le r' + #$E9 +
        'sultat change d''une machine ou d''un utilisateur ' + #$E0 + ' l''autre'
    ),
    // SCA129
    (
      RuleID   : 'SCA129';
      Name     : 'Transtypage de cha' + #$EE + 'ne vers un type 8 bits sans encodage explicite';
      ShortDesc: '`AnsiString(s)` / `RawByteString(s)` / `ShortString(s)` supprime silencieusement les caract' +
        #$E8 + 'res hors de la page de codes active'
    ),
    // SCA130
    (
      RuleID   : 'SCA130';
      Name     : 'Transtypage d''un Char en PChar : le point de code devient une adresse';
      ShortDesc: '`PChar(''A'')` n''est pas `PChar("A")` - le transtypage traite le point de code 16 bits comme une adresse m' +
        #$E9 + 'moire brute'
    ),
    // SCA131
    (
      RuleID   : 'SCA131';
      Name     : 'IfThen() ' + #$E9 + 'value les deux branches - pas de court-circuit';
      ShortDesc: '`Math.IfThen(cond, A(), B())` et `StrUtils.IfThen` sont des fonctions ordinaires - les deux bras s''ex' +
        #$E9 + 'cutent avant l''appel'
    ),
    // SCA132
    (
      RuleID   : 'SCA132';
      Name     : 'except on E: Exception attrape toutes les erreurs';
      ShortDesc: '`on E: Exception do ...` attrape la classe de base et donc tous ses descendants, y compris les exceptions syst' +
        #$E8 + 'me qui ne doivent pas ' + #$EA + 'tre ' + #$E9 + 'touff' + #$E9 +
        'es (EOutOfMemory, EAccessViolation, EAbort)'
    ),
    // SCA133
    (
      RuleID   : 'SCA133';
      Name     : 'raise nu hors d''un gestionnaire except/on';
      ShortDesc: '`raise;` sans expression ne fonctionne qu''a l''Int' + #$E9 +
        'rieur d''un gestionnaire except (relev' + #$E9 + 'e) - a l''ext' + #$E9 + 'rieur il l' +
        #$E8 + 've NIL et provoque une violation d''acc' + #$E8 + 's'
    ),
    // SCA134
    (
      RuleID   : 'SCA134';
      Name     : 'Variable utilisee apr' + #$E8 + 's Free / FreeAndNil';
      ShortDesc: 'D' + #$E9 + 'r' + #$E9 + 'f' + #$E9 + 'rencer une variable apr' + #$E8 +
        's `Free` ou `FreeAndNil` lit un pointeur pendant et provoque une violation d''acc' + #$E8 +
        's'
    ),
    // SCA135
    (
      RuleID   : 'SCA135';
      Name     : 'Classe concr' + #$E8 + 'te h' + #$E9 + 'ritant d''une m' + #$E9 +
        'thode abstraite sans override';
      ShortDesc: 'La classe d' + #$E9 + 'rive d''une base ayant une m' + #$E9 +
        'thode `abstract` mais ne la red' + #$E9 + 'finit pas - l''appel sur l''instance l' + #$E8 +
        've EAbstractError ' + #$E0 + ' l''ex' + #$E9 + 'cution'
    ),
    // SCA136
    (
      RuleID   : 'SCA136';
      Name     : 'Constructeur qui alloue des champs et l' + #$E8 + 've sans try/except';
      ShortDesc: 'Le constructeur affecte des champs par `<Classe>.Create` puis l' + #$E8 +
        've - les champs partiellement initialis' + #$E9 + 's fuient sur le chemin d''exception'
    ),
    // SCA137
    (
      RuleID   : 'SCA137';
      Name     : 'Cible Int64 recevant le produit de deux op' + #$E9 + 'randes 32 bits';
      ShortDesc: '`<var-Int64> := <a> * <b>` ' + #$E9 + 'value la multiplication en 32 bits avant l''' + #$E9 +
        'largissement - un d' + #$E9 + 'passement tronque silencieusement'
    ),
    // SCA138
    (
      RuleID   : 'SCA138';
      Name     : 'La classe a trop de m' + #$E9 + 'thodes ou de champs';
      ShortDesc: 'Une classe de plus de 20 m' + #$E9 +
        'thodes ou de plus de 15 champs d''instance concentre trop de responsabilit' + #$E9 +
        's - difficile ' + #$E0 + ' tester, ' + #$E0 + ' faire ' + #$E9 + 'voluer et ' + #$E0 +
        ' relire'
    ),
    // SCA139
    (
      RuleID   : 'SCA139';
      Name     : 'Free sans mise ' + #$E0 + ' nil ensuite';
      ShortDesc: '`obj.Free;` sans `obj := nil;` (ni FreeAndNil) laisse un pointeur pendant - toute utilisation ult' +
        #$E9 + 'rieure est un Use-After-Free'
    ),
    // SCA140
    (
      RuleID   : 'SCA140';
      Name     : 'La m' + #$E9 + 'thode a trop d''instructions Exit';
      ShortDesc: 'Une m' + #$E9 +
        'thode avec plus de 3 appels a Exit a trop de chemins de sortie - difficile ' + #$E0 +
        ' lire, difficile ' + #$E0 + ' tester, facile d''en oublier un'
    ),
    // SCA141
    (
      RuleID   : 'SCA141';
      Name     : 'L''implementation de la classe d' + #$E9 + 'passe 500 lignes';
      ShortDesc: 'Une classe dont la d' + #$E9 + 'claration et les m' + #$E9 +
        'thodes d''implementation totalisent plus de 500 lignes a trop de responsabilit' + #$E9 +
        's'
    ),
    // SCA142
    (
      RuleID   : 'SCA142';
      Name     : 'La clause uses n''est pas dans l''ordre alphab' + #$E9 + 'tique';
      ShortDesc: 'Les entr' + #$E9 + 'es d''une clause `uses` ne sont pas dans l''ordre alphab' + #$E9 +
        'tique - les fusions deviennent non d' + #$E9 + 'terministes et la relecture plus difficile'
    ),
    // SCA143
    (
      RuleID   : 'SCA143';
      Name     : 'L''unit n''a pas de commentaire d''en-t' + #$EA + 'te descriptif';
      ShortDesc: 'L''unit commence directement par `interface`, sans bloc de commentaire explicatif entre `unit ...;` et `interface`'
    ),
    // SCA144
    (
      RuleID   : 'SCA144';
      Name     : 'Comparaison d''' + #$E9 + 'galit' + #$E9 + ' ou d''in' + #$E9 + 'galit' + #$E9 +
        ' entre flottants';
      ShortDesc: '`a = b` ou `a <> b` entre Single/Double/Extended n''est pas fiable a cause de l''arrondi IEEE-754 - utiliser SameValue ou Math.IsZero'
    ),
    // SCA145
    (
      RuleID   : 'SCA145';
      Name     : 'raise dans un destructeur sans try/except';
      ShortDesc: 'Un `raise` non prot' + #$E9 + 'g' + #$E9 + ' dans un destructeur interrompt la cha' + #$EE +
        'ne de nettoyage - inherited Destroy et les FreeAndNil suivants sont saut' + #$E9 + 's, l''' +
        #$E9 + 'tat reste incoh' + #$E9 + 'rent'
    ),
    // SCA146
    (
      RuleID   : 'SCA146';
      Name     : 'Param' + #$E8 + 'tre bool' + #$E9 + 'en servant d''aiguillage interne';
      ShortDesc: 'Un param' + #$E8 + 'tre bool' + #$E9 +
        'en dont la valeur choisit entre deux chemins de code compl' + #$E8 + 'tement diff' + #$E9 +
        'rents est une strat' + #$E9 + 'gie d' + #$E9 + 'guis' + #$E9 + 'e - pr' + #$E9 + 'f' + #$E9 +
        'rer deux m' + #$E9 + 'thodes aux noms parlants'
    ),
    // SCA147
    (
      RuleID   : 'SCA147';
      Name     : 'M' + #$E9 + 'thode priv' + #$E9 + 'e sans appelant dans l''unit';
      ShortDesc: 'Une m' + #$E9 + 'thode priv' + #$E9 + 'e que nulle autre m' + #$E9 + 'thode de la m' + #$EA +
        'me unit ne r' + #$E9 + 'f' + #$E9 + 'rence est du code mort - la supprimer ou la brancher'
    ),
    // SCA148
    (
      RuleID   : 'SCA148';
      Name     : 'M' + #$E9 + 'thode d''instance n''acc' + #$E9 + 'dant jamais a Self - pourrait ' + #$EA +
        'tre de classe';
      ShortDesc: 'Une m' + #$E9 + 'thode qui n''utilise que ses param' + #$E8 +
        'tres (ni Self, ni champs d''instance, ni cha' + #$EE +
        'ne virtuelle) est fonctionnellement une m' + #$E9 + 'thode de classe - la d' + #$E9 +
        'clarer comme telle'
    ),
    // SCA149
    (
      RuleID   : 'SCA149';
      Name     : 'La m' + #$E9 + 'thode masque une m' + #$E9 + 'thode virtuelle parente sans `override`';
      ShortDesc: 'Une m' + #$E9 + 'thode red' + #$E9 + 'clar' + #$E9 + 'e dans une classe d' + #$E9 + 'riv' +
        #$E9 + 'e avec le m' + #$EA + 'me nom qu''une m' + #$E9 +
        'thode parente virtuelle ou dynamique, mais sans `override`, casse le polymorphisme - le compilateur ' +
        #$E9 + 'met W1010'
    ),
    // SCA150
    (
      RuleID   : 'SCA150';
      Name     : 'La comparaison bool' + #$E9 + 'enne est toujours vraie / toujours fausse';
      ShortDesc: 'Des comparaisons comme `Length(s) >= 0` sont des tautologies - le r' + #$E9 +
        'sultat de Length n''est jamais n' + #$E9 + 'gatif, la condition ne peut donc jamais ' +
        #$EA + 'tre fausse'
    ),
    // SCA151
    (
      RuleID   : 'SCA151';
      Name     : 'La fonction renvoie toujours le m' + #$EA + 'me litt' + #$E9 + 'ral';
      ShortDesc: 'Tous les chemins de la fonction affectent le m' + #$EA + 'me litt' + #$E9 +
        'ral a Result - la logique conditionnelle ne change rien au comportement, remplacer la fonction par une constante'
    ),
    // SCA152
    (
      RuleID   : 'SCA152';
      Name     : 'Texte visible par l''utilisateur affect' + #$E9 + ' en litt' + #$E9 + 'ral';
      ShortDesc: 'Les affectations a Caption/Hint/Text et les appels a ShowMessage/MessageDlg avec du texte litt' +
        #$E9 + 'ral contournent resourcestring et i18n - la cha' + #$EE +
        'ne n''est pas traduisible'
    ),
    // SCA153
    (
      RuleID   : 'SCA153';
      Name     : 'Paire Lock/Unlock sans try/finally';
      ShortDesc: 'Lock / EnterCriticalSection / TMonitor.Enter avec sa lib' + #$E9 + 'ration dans la m' +
        #$EA + 'me routine mais sans try/finally - le chemin d''exception laisse le verrou pos' +
        #$E9 + ' et bloque l''appelant suivant'
    ),
    // SCA154
    (
      RuleID   : 'SCA154';
      Name     : 'Move/FillChar avec SizeOf d''un type pointeur';
      ShortDesc: 'Move, FillChar, CopyMemory ou ZeroMemory appel' + #$E9 +
        ' avec SizeOf(PXxx) ou PXxx est un type pointeur - ne copie que 4 ou 8 octets (la taille du pointeur) au lieu du tampon vis' +
        #$E9
    ),
    // SCA155
    (
      RuleID   : 'SCA155';
      Name     : 'Instruction with sur plusieurs cibles';
      ShortDesc: '`with A, B do` (deux receveurs ou plus s' + #$E9 + 'par' + #$E9 +
        's par des virgules) rend la resolution des membres ambigu' + #$EB + ' - ajouter une m' +
        #$E9 + 'thode ' + #$E0 + ' A ou ' + #$E0 + ' B change silencieusement le sens du corps'
    ),
    // SCA156
    (
      RuleID   : 'SCA156';
      Name     : 'GetMem / AllocMem sans try/finally';
      ShortDesc: 'GetMem / AllocMem / ReallocMem suivi du FreeMem correspondant dans la m' + #$EA +
        'me routine mais sans try/finally englobant - le chemin d''exception perd le tampon d' +
        #$E9 + 'finitivement'
    ),
    // SCA157
    (
      RuleID   : 'SCA157';
      Name     : 'SetLength(arr, Length(arr) + N) dans une boucle';
      ShortDesc: 'Agrandir un tableau dynamique d''un ' + #$E9 + 'l' + #$E9 +
        'ment (ou de N) dans une boucle for/while/repeat co' + #$FB +
        'te quadratiquement - agrandir une fois avant la boucle ou proc' + #$E9 + 'der par blocs'
    ),
    // SCA158
    (
      RuleID   : 'SCA158';
      Name     : 'PChar(s) +/- d' + #$E9 + 'calage sans test de cha' + #$EE + 'ne vide';
      ShortDesc: '`PChar(s) + n` et variantes sans test pr' + #$E9 +
        'alable de `s` vide - PChar('''') est optimis' + #$E9 + ' en NIL, l''arithm' + #$E9 +
        'tique dessus est une violation d''acc' + #$E8 + 's latente'
    ),
    // SCA159
    (
      RuleID   : 'SCA159';
      Name     : 'Gestionnaire d''exception typ' + #$E9 + 'e au corps vide';
      ShortDesc: '`on E: SomeException do ;` avale silencieusement une classe d''exception pr' + #$E9 +
        'cise - pire qu''un `except end` nu, car l''annotation typ' + #$E9 + 'e a l''air d' + #$E9 +
        'lib' + #$E9 + 'r' + #$E9 + 'e'
    ),
    // SCA160
    (
      RuleID   : 'SCA160';
      Name     : 'Transtypage en cha' + #$EE + 'ne depuis un pointeur brut';
      ShortDesc: '`string(P)` et variantes depuis un pointeur pr' + #$E9 +
        'fixe P supposent un terminateur nul qui peut ne pas exister - lecture au-del' + #$E0 +
        ' du tas'
    ),
    // SCA161
    (
      RuleID   : 'SCA161';
      Name     : 'Soustraction de pointeurs via un transtypage 32 bits';
      ShortDesc: '`Cardinal(P1) - Cardinal(P2)` (ou Integer/LongWord/LongInt) tronque les 32 bits de poids fort d''un pointeur 64 bits sous Win64 - la diff' +
        #$E9 + 'rence est parfois fausse'
    ),
    // SCA162
    (
      RuleID   : 'SCA162';
      Name     : 'Utilisation d''un algorithme cryptographique faible ou obsol' + #$E8 + 'te';
      ShortDesc: 'Nom d''algorithme (''MD5'', ''SHA1'', ''DES'', ''RC4'', ''TLS1.0'', ''SSLv3'') ou classe d''encapsulation (THashMD5, TIdHashSHA1, ...) r' +
        #$E9 + 'f' + #$E9 + 'renc' + #$E9 + 'e - vuln' + #$E9 +
        'rable aux collisions et aux attaques a texte clair connu'
    ),
    // SCA163
    (
      RuleID   : 'SCA163';
      Name     : 'API shell appel' + #$E9 + 'e avec concat' + #$E9 + 'nation dans les arguments';
      ShortDesc: 'ShellExecute / CreateProcess / WinExec avec `+` dans les arguments - si un op' + #$E9 +
        'rande est contr' + #$F4 + 'lable, cela devient un vecteur d''injection de commande'
    ),
    // SCA164
    (
      RuleID   : 'SCA164';
      Name     : 'Routine de premier niveau jamais appel' + #$E9 + 'e';
      ShortDesc: 'Une proc' + #$E9 + 'dure ou fonction autonome de la section implementation n''est appel' +
        #$E9 + 'e nulle part dans l''unit et n''est pas export' + #$E9 +
        'e par la section interface - code mort'
    ),
    // SCA165
    (
      RuleID   : 'SCA165';
      Name     : 'Marqueur noinspection inutilis' + #$E9;
      ShortDesc: 'Un `// noinspection X` ne supprime aucun r' + #$E9 +
        'sultat sur sa ligne cible - soit le d' + #$E9 + 'tecteur s''est am' + #$E9 + 'lior' + #$E9 +
        ', soit la cible ' + #$E9 + 'tait mauvaise'
    ),
    // SCA166
    (
      RuleID   : 'SCA166';
      Name     : 'Variable locale non initialis' + #$E9 + 'e';
      ShortDesc: 'Variable locale lue avant d''avoir ' + #$E9 + 't' + #$E9 + ' affect' + #$E9 +
        'e sur tous les chemins traversant la m' + #$E9 + 'thode'
    ),
    // SCA167
    (
      RuleID   : 'SCA167';
      Name     : 'Appel a Random sans Randomize pr' + #$E9 + 'alable';
      ShortDesc: 'Random / RandomRange / RandomFrom sans Randomize - un germe a 0 produit la m' + #$EA +
        'me suite ' + #$E0 + ' chaque ex' + #$E9 + 'cution'
    ),
    // SCA168
    (
      RuleID   : 'SCA168';
      Name     : 'Instruction case sans branche else';
      ShortDesc: 'L''instruction case n''a pas de branche else - les valeurs non trait' + #$E9 +
        'es passent silencieusement ; un else suivant un if dans le dernier bras est le else du case'
    ),
    // SCA169
    (
      RuleID   : 'SCA169';
      Name     : 'L''argument d''Assert contient un appel a effet de bord';
      ShortDesc: 'Assert(SomeCall) - l''appel dispara' + #$EE +
        't en build Release et son effet de bord est perdu silencieusement'
    ),
    // SCA170
    (
      RuleID   : 'SCA170';
      Name     : 'Param' + #$E8 + 'tre string sans const';
      ShortDesc: 'Param' + #$E8 + 'tre string d' + #$E9 + 'clar' + #$E9 + ' sans const - provoque une incr' +
        #$E9 + 'mentation du compteur de r' + #$E9 + 'f' + #$E9 + 'rences ' + #$E0 + ' chaque appel'
    ),
    // SCA171
    (
      RuleID   : 'SCA171';
      Name     : 'Directive de compilation OFF sans ON correspondant dans le fichier';
      ShortDesc: '{$WARNINGS OFF} (ou HINTS/RANGECHECKS/...) sans ON de fermeture - d' + #$E9 +
        'borde sur les units suivantes'
    ),
    // SCA172
    (
      RuleID   : 'SCA172';
      Name     : 'Propri' + #$E9 + 't' + #$E9 + ' bool' + #$E9 + 'enne sans pr' + #$E9 +
        'fixe Is / Has / Can / Should';
      ShortDesc: 'Le nom de la propri' + #$E9 + 't' + #$E9 + ' bool' + #$E9 +
        'enne se lit comme un substantif - pr' + #$E9 + 'f' + #$E9 + 'rer un pr' + #$E9 +
        'fixe verbal qui se lit comme une question'
    ),
    // SCA173
    (
      RuleID   : 'SCA173';
      Name     : 'Variant dans une m' + #$E9 + 'thode sensible aux performances (avec boucle)';
      ShortDesc: 'Variable Variant dans une m' + #$E9 + 'thode contenant une boucle - chaque op' + #$E9 +
        'ration Variant paie un surco' + #$FB + 't de dispatch COM de 10 ' + #$E0 + ' 100 fois'
    ),
    // SCA174
    (
      RuleID   : 'SCA174';
      Name     : 'TList<T> rempli de T.Create - les ' + #$E9 + 'l' + #$E9 + 'ments fuient a la lib' + #$E9 +
        'ration';
      ShortDesc: 'TList<TFoo>.Create plus Add(TFoo.Create) - la liste ne poss' + #$E8 + 'de pas ses ' + #$E9 +
        'l' + #$E9 + 'ments, chaque instance TFoo fuit'
    ),
    // SCA175
    (
      RuleID   : 'SCA175';
      Name     : 'M' + #$E9 + 'thode anonyme capturant la variable de boucle par r' + #$E9 + 'f' + #$E9 +
        'rence';
      ShortDesc: 'Une m' + #$E9 + 'thode anonyme dans `for i := ... do` r' + #$E9 + 'f' + #$E9 +
        'rence i - toutes les closures voient la m' + #$EA + 'me valeur finale'
    ),
    // SCA176
    (
      RuleID   : 'SCA176';
      Name     : 'M' + #$E9 + 'thode a forte complexit' + #$E9 + ' cognitive (flot de contr' + #$F4 +
        'le imbriqu' + #$E9 + ')';
      ShortDesc: 'La complexit' + #$E9 + ' cognitive (style Sonar) d' + #$E9 +
        'passe 15 - les if/for/while/case imbriqu' + #$E9 + 's sont difficiles ' + #$E0 +
        ' suivre mentalement'
    ),
    // SCA177
    (
      RuleID   : 'SCA177';
      Name     : 'Variable de thread utilisee apr' + #$E8 + 's FreeOnTerminate := True';
      ShortDesc: 'Apr' + #$E8 + 's T.FreeOnTerminate := True, tout acc' + #$E8 + 's ult' + #$E9 + 'rieur ' +
        #$E0 + ' T.Field/T.Method risque une Access Violation si le thread s''est d' + #$E9 + 'j' +
        #$E0 + ' auto-d' + #$E9 + 'truit'
    ),
    // SCA178
    (
      RuleID   : 'SCA178';
      Name     : 'API d''ouverture de fichier recevant une saisie utilisateur concat' + #$E9 + 'n' + #$E9 +
        'e';
      ShortDesc: 'Ouverture de fichier (TFileStream.Create, AssignFile, ...) avec un chemin construit ' +
        #$E0 +
        ' partir d''une saisie utilisateur (Edit.Text, Request.Params, ...) - risque de path traversal'
    ),
    // SCA179
    (
      RuleID   : 'SCA179';
      Name     : 'Attribut DUnitX [Ignore] sans argument de justification';
      ShortDesc: '[Ignore] sans argument cha' + #$EE +
        'ne ignore le test silencieusement - ajouter un message expliquant pourquoi il est d' + #$E9 +
        'sactiv' + #$E9
    ),
    // SCA180
    (
      RuleID   : 'SCA180';
      Name     : 'Le m' + #$EA + 'me attribut applique deux fois au m' + #$EA + 'me membre';
      ShortDesc: 'Deux attributs [X] identiques sur le m' + #$EA +
        'me membre - reste de copier-coller, sans effet'
    ),
    // SCA181
    (
      RuleID   : 'SCA181';
      Name     : 'Attribut DUnitX [Category] sans nom de cat' + #$E9 + 'gorie';
      ShortDesc: '[Category] sans argument est une erreur de compilation dans DUnitX - toujours passer un nom de cat' +
        #$E9 + 'gorie'
    ),
    // SCA182
    (
      RuleID   : 'SCA182';
      Name     : 'Classe [TestFixture] sans aucune m' + #$E9 + 'thode [Test]';
      ShortDesc: 'La classe est marqu' + #$E9 + 'e [TestFixture] mais ne contient aucune m' + #$E9 +
        'thode [Test] - fixture zombie, visible dans TestInsight mais qui n''ex' + #$E9 +
        'cute rien'
    ),
    // SCA183
    (
      RuleID   : 'SCA183';
      Name     : 'Attribut suivi d''une ligne vide avant le membre cible';
      ShortDesc: 'Ligne d''attribut suivie d''une ligne vide - visuellement d' + #$E9 + 'tach' + #$E9 +
        'e, souvent un reste de refactoring'
    ),
    // SCA184
    (
      RuleID   : 'SCA184';
      Name     : 'Composant DFM inutilis' + #$E9;
      ShortDesc: 'Le composant DFM n''est r' + #$E9 + 'f' + #$E9 + 'renc' + #$E9 +
        ' ni dans le code, ni dans d''autres units, ni dans le DFM lui-m' + #$EA +
        'me - probablement un reste de refactoring'
    ),
    // SCA185
    (
      RuleID   : 'SCA185';
      Name     : 'Fichier source UTF-8 sans BOM';
      ShortDesc: 'Fichier UTF-8 sans BOM contenant du non-ASCII - le compilateur le lit comme de l''ANSI (mojibake)'
    ),
    // SCA186
    (
      RuleID   : 'SCA186';
      Name     : 'S' + #$E9 + 'quence UTF-8 invalide dans le fichier source';
      ShortDesc: 'UTF-8 mal forme (surlong, substitut ou hors plage) sous un BOM UTF-8'
    ),
    // SCA187
    (
      RuleID   : 'SCA187';
      Name     : 'Octet NUL ou de contr' + #$F4 + 'le dans le fichier source';
      ShortDesc: 'NUL ou octet de contr' + #$F4 + 'le interdit - fichier binaire ou encodage mal d' + #$E9 +
        'tect' + #$E9
    ),
    // SCA188
    (
      RuleID   : 'SCA188';
      Name     : 'Caract' + #$E8 + 're de contr' + #$F4 + 'le bidirectionnel (Trojan Source)';
      ShortDesc: 'Caract' + #$E8 + 're de contr' + #$F4 +
        'le bidi override ou isolate - le source se lit autrement qu''il ne compile'
    ),
    // SCA189
    (
      RuleID   : 'SCA189';
      Name     : 'Fichier source ANSI avec du contenu non-ASCII';
      ShortDesc: 'Source 8 bits (sans BOM, pas de l''UTF-8 valide) - d' + #$E9 +
        'pendant de la page de codes, non portable'
    ),
    // SCA190
    (
      RuleID   : 'SCA190';
      Name     : 'Fichier source UTF-16';
      ShortDesc: 'Source UTF-16 - compile, mais inhabituel et peu commode pour les outils texte'
    ),
    // SCA191
    (
      RuleID   : 'SCA191';
      Name     : 'Fichier source UTF-32 / UCS-4';
      ShortDesc: 'Source UTF-32 - le compilateur Delphi le rejette avec l''erreur fatale F2438'
    ),
    // SCA192
    (
      RuleID   : 'SCA192';
      Name     : 'Caract' + #$E8 + 're invisible ou de largeur nulle dans le source';
      ShortDesc: 'Caract' + #$E8 + 're Unicode invisible ou de largeur nulle - vecteur de texte cach' + #$E9 +
        ' et d''abus par homoglyphes'
    ),
    // SCA193
    (
      RuleID   : 'SCA193';
      Name     : 'Caract' + #$E8 + 're non-ASCII dans un identifiant';
      ShortDesc: 'L''identifiant contient une lettre non-ASCII - risque d''homoglyphes et de caract' + #$E8 +
        'res confondables'
    ),
    // SCA194
    (
      RuleID   : 'SCA194';
      Name     : 'Fichier source hors du projet';
      ShortDesc: 'Un fichier .pas/.dfm se trouve dans le dossier du projet mais n''est pas r' + #$E9 + 'f' +
        #$E9 + 'renc' + #$E9 +
        ' par le projet (.dproj/.groupproj) - probablement un fichier source orphelin'
    ),
    // SCA195
    (
      RuleID   : 'SCA195';
      Name     : 'Unit utilisee par le projet mais non incluse dedans';
      ShortDesc: 'Un fichier .pas est tir' + #$E9 + ' par les units du projet via uses (il compile gr' + #$E2 +
        'ce au chemin de recherche) mais n''est pas liste dans le fichier projet (.dproj/.groupproj) - l''ajouter au projet'
    ),
    // SCA196
    (
      RuleID   : 'SCA196';
      Name     : 'Result de type manag' + #$E9 + ' est lu avant d''avoir ' + #$E9 + 't' + #$E9 + ' affect' +
        #$E9;
      ShortDesc: 'Le Result d''un type de retour manag' + #$E9 + ' est lu avant la premi' + #$E8 +
        're affectation - il est un alias de la variable cible de l''appelant et porte son ANCIENNE valeur. L''initialiser d''abord (nil / [] / '''')'
    ),
    // SCA197
    (
      RuleID   : 'SCA197';
      Name     : 'Interface d' + #$E9 + 'clar' + #$E9 + 'e sans GUID';
      ShortDesc: 'L''interface n''a pas de GUID - Supports() et QueryInterface() ne peuvent pas la demander ' +
        #$E0 + ' l''ex' + #$E9 + 'cution. En g' + #$E9 + 'n' + #$E9 + 'rer un avec Ctrl+Maj+G'
    ),
    // SCA198
    (
      RuleID   : 'SCA198';
      Name     : 'Deux interfaces partagent le m' + #$EA + 'me GUID';
      ShortDesc: 'Le m' + #$EA +
        'me GUID figure sur plusieurs interfaces - Supports() renvoie celle enregistr' + #$E9 +
        'e en premier, sans erreur de compilation. En g' + #$E9 + 'n' + #$E9 +
        'rer un nouveau avec Ctrl+Maj+G'
    )
  );

