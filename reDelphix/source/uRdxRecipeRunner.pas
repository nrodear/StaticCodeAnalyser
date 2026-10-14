unit uRdxRecipeRunner;

// reDelphix - der Rezept-Laeufer: fuehrt die Rezepte (uRdxRecipes) gegen
// den Quellstellen-Dienst des SCA-Cores (TSourcePlaces) aus. Ohne
// ToolsAPI, ohne Clipboard, ohne Menue - damit ist dieser Weg vom Fund
// bis zum fertigen Ersatztext in reDelphix.Test ohne IDE pruefbar. Der
// Anbieter (uRdxProvider) baut daraus nur noch Menuepunkte.
//
// ABLAUF FUER SCA044 (Rezept 5.1)
//
//   Describe        NodesAt(Zeile, Anker) -> genau ein Knoten -> Gegen-
//                   probe gegen den Fund (Ziel, '+'-Zahl; QueryOf) ->
//                   ChainOf mit der '+'-Zahl des Knotens (TypeRef)
//   FormatRewrite   Parts -> BuildFormatCall (Kompilat-Regel, AH20);
//                   Bereich = erster bis letzter Term, Expected = dessen
//                   Text, NewText = Format(...); bei 'X := X + ...' nur
//                   der Rest hinter 'X +'
//
// Ein Ergebnis mit Enabled = False traegt den Grund (Operand mit Zahl-,
// Variant- oder AnsiString-Typ, Klammerausdruck, Kommentar oder Direktive
// im Bereich, SQL-Text, Zeile mehrdeutig, ...).

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uEngineApi, uRefactorInfo, uFindingActions, uRdxRecipes,
  uMethodd12,       // TLeakFinding
  uSCAConsts,       // TFindingKind
  uRdxScopeTable,   // TRdxScopeTable (QualifyUses)
  uRdxBufferMath,   // TRdxEdit
  uRdxCodeMap,      // TRdxCodeMap: Bausteine der Tabelle uRdxFixTable (Charge R8)
  uRdxFlowFixes;    // TRdxFlowPlan (FlowFix)

const
  // So viele Provide-Chargen haelt der Anbieter am Leben: ein Menue fragt
  // hoechstens MAX_FINDINGS_PER_MENU Funde (Vertrag uFindingActions), dazu
  // reichlich Reserve fuer Abfragen zwischen Aufbau und Klick (Gluehbirne
  // im Hintergrund). Review reDelphiX 2026-10-07, Blocker 2.
  RDX_ACTION_BATCHES = 8 * MAX_FINDINGS_PER_MENU;
  // Grund ohne offene Datei (MapFix, uRdxFixTable.RoutineFix; bis Charge
  // H3c stand er dort als R_NO_FILE_OPEN doppelt - Minor 6).
  R_NO_FILE = 'keine Datei geoeffnet';

type
  // Haelt Objekte in Chargen: BeginBatch eroeffnet eine Charge (ein
  // Provide-Aufruf), Keep legt Objekte hinein; sind mehr als AMaxBatches
  // Chargen offen, wird die aelteste samt Objekten freigegeben. Der
  // Anbieter legt hier seine Aktionsobjekte ab: ein Host, der die
  // Aktionen MEHRERER Funde in ein Menue stellt (Editor-Kontextmenue mit
  // zwei Funden auf einer Zeile, Gluehbirne), ruft Provide je Fund - bis
  // Stufe B gab jedes Provide die Objekte des vorigen frei, und die
  // Menuepunkte des ersten Funds zeigten auf freigegebene Objekte
  // (Konzept Editor-Gluehbirne 2026-10-06, 3.3). Chargen statt einer
  // Objektzahl (Verifikations-Workflow 2026-10-07): ein Fund mit vielen
  // Aktionen kann so innerhalb EINES Menueaufbaus nichts verdraengen.
  // Wie viele Funde ein Menue hoechstens umfasst, legt der Vertrag in
  // uFindingActions fest (MAX_FINDINGS_PER_MENU); der Anbieter haelt
  // RDX_ACTION_BATCHES Chargen, ein Vielfaches davon.
  TRdxObjectRing = class
  private
    FBatches : TObjectList<TObjectList<TObject>>;
    FMax     : Integer;
    function Current: TObjectList<TObject>;
  public
    constructor Create(AMaxBatches: Integer);
    destructor Destroy; override;
    // Eroeffnet eine neue Charge; die aelteste faellt heraus, wenn es
    // mehr als Max werden.
    procedure BeginBatch;
    // Nimmt das Objekt in die aktuelle Charge (ohne BeginBatch: in die
    // erste); faellt die Charge aus dem Ring, wird das Objekt frei.
    procedure Keep(AObject: TObject);
    // Zahl der gehaltenen Objekte ueber alle Chargen.
    function Count: Integer;
    // Zahl der offenen Chargen (hoechstens Max).
    function BatchCount: Integer;
    // True, solange das Objekt noch im Ring liegt.
    function Contains(AObject: TObject): Boolean;
    // Obergrenze der Chargen, mindestens 1.
    property Max: Integer read FMax;
  end;

  // Eine Ersetzung im Editor: Bereich, erwarteter alter Text, neuer Text.
  // Zeilenumbrueche im neuen Text sind #10; der Editor setzt sie auf die
  // Zeilenenden des Puffers um.
  // Seit Stufe 0 (Editorhilfen) in uRdxBufferMath, ToolsAPI-frei und
  // getestet; der Alias haelt alle Verwender quelltext-stabil.
  TRdxEdit = uRdxBufferMath.TRdxEdit;

  // Was fuer eine fehlende Unit in der uses-Klausel zu tun ist (AH19).
  TRdxUsesPlan = record
    Needed : Boolean;     // False = die Unit steht schon in einer uses-Klausel
    Name   : string;      // der einzufuegende Name ('System.SysUtils' / 'SysUtils')
    Edit   : TRdxEdit;    // die Ersetzung, wenn Needed und Reason = ''
    Reason : string;      // wenn Needed, aber keine Stelle bestimmbar
  end;

  // Ergebnis einer einfachen Hilfe (TRdxFixRunner): die Ersetzungen fuer
  // EINEN Undo-Schritt und ein Hinweis fuers Menue - oder der Grund, warum
  // es keine Hilfe gibt.
  TRdxFixOutcome = record
    Enabled : Boolean;
    Edits   : TArray<TRdxEdit>;
    Name    : string;    // X fuer den Menuetext: SCA085 wie im Puffer, SCA139 wie in der Meldung
    Hint    : string;    // bei Enabled = True
    Reason  : string;    // bei Enabled = False
    // 0 = die Hilfe (FixFor), 1 = der zweite Eintrag (AlternativeFixFor:
    // SCA168 else mit raise, SCA020 raise ENotImplemented).
    Variant : Integer;
    // Entscheid E2 (Konzept Editorhilfen): der Menuetext traegt
    // '(aendert Verhalten)' - SCA007 (initialization-Abschnitt der Unit),
    // SCA168 und SCA020 mit raise, SCA120 (raise davor).
    ChangesBehavior : Boolean;
  end;

  // uses-Eintraege qualifizieren ('uses: X -> Scope.X', QualifyUses):
  // warum gar nichts geht ...
  TRdxQualifyBlock = (qbNone, qbNoTable, qbDirectives, qbFpcSwitch);
  // ... und warum ein einzelner Eintrag nicht geht.
  TRdxQualifyWhy = (qwOk, qwScopeTable, qwOwnUnit, qwUnsorts);

  TRdxQualifyItem = record
    Short       : string;          // Name wie in der Klausel
    Qualified   : string;          // Ziel ('' wenn die Tabelle keins kennt)
    Why         : TRdxQualifyWhy;  // qwOk = anbietbar
    ScopeReason : string;          // bei qwScopeTable: Grund der Scope-Tabelle
    Edit        : TRdxEdit;        // bei qwOk
  end;

  TRdxQualifyPlan = record
    InClause   : Boolean;          // False: die Zeile liegt in keiner uses-Klausel
    Block      : TRdxQualifyBlock;
    BlockLine  : Integer;          // bei qbDirectives: Zeile der Direktive
    Items      : TArray<TRdxQualifyItem>;   // Eintraege auf der gefragten Zeile
    All        : TArray<TRdxEdit>; // alle qualifizierbaren Eintraege der Datei
    AllPreview : string;           // die ersten drei Ziele, ', ...' bei mehr
    // 'alle qualifizieren' machte eine sortierte Klausel unsortiert.
    AllUnsorts : Boolean;
  end;

  // Kennt das Projekt eine eigene Unit dieses Kurznamens? (ToolsAPI, vom
  // Anbieter gereicht; nil = nein.)
  TRdxOwnUnitCheck = reference to function(const AShortName: string): Boolean;

  // Die Anfrage an Describe: Zeile und Anker der Regel ('assign', 'call',
  // 'assign-or-call'), dazu aus dem Fund Ziel und '+'-Zahl fuer die
  // Gegenprobe (Review reDelphiX 2026-10-07, Minor 20). Target = '' bzw.
  // Plus < 0: keine Gegenprobe.
  TRdxAnchorQuery = record
    Line   : Integer;
    Anchor : string;
    Target : string;
    Plus   : Integer;
  end;

  TRdxFormatOutcome = record
    Enabled   : Boolean;
    Reason    : string;          // bei Enabled = False
    Hint      : string;          // bei Enabled = True
    Span      : TRefactorSpan;   // zu ersetzender Bereich (erster bis letzter Term)
    Expected  : string;          // Text des Bereichs laut Scan
    NewText   : string;          // Format(...)
    // Format() braucht System.SysUtils: fehlt die Unit in der uses-Klausel,
    // wird sie mit eingefuegt (zweite Ersetzung, oberhalb der ersten).
    NeedsUses : Boolean;
    UsesName  : string;
    UsesEdit  : TRdxEdit;
    // Herkunft der Argumente (AH20, Kompilat-Regel): wie viele Operanden,
    // wie viele davon bewiesen, wie viele als %d/%u, und fuer welche nur
    // das Kompilat buergt. SelfAppend: 'X := X + ...' - Format nur ueber
    // den Rest, der Bereich beginnt hinter 'X +'.
    Operands   : Integer;
    Proven     : Integer;
    Numeric    : Integer;
    ByCompiler : TArray<string>;
    SelfAppend : Boolean;
  end;

  TRdxRecipeRunner = class
  public
    // Der Kopf eines nkCall-Knotens: der Teil von TNodeRef.Name vor '('.
    class function HeadOf(const ACallName: string): string; static;

    // Qualifizierte/rohe Namen aller uses-Eintraege der geoeffneten Datei.
    class function UsesNamesOf(APlaces: TSourcePlaces): TArray<string>; static;

    // Beschreibt die Anweisung auf ALine nach dem Anker der Regel
    // ('assign', 'call', 'assign-or-call', sonst beides) - ohne Gegenprobe
    // gegen einen Fund (Describe mit leerem Ziel). nil mit Grund, wenn
    // kein oder mehr als ein Knoten auf der Zeile liegt oder die Anweisung
    // sich nicht beschreiben laesst. Der Aufrufer besitzt das Ergebnis.
    class function DescribeAnchor(APlaces: TSourcePlaces; ALine: Integer;
      const AAnchor: string; out AIsCall: Boolean;
      out AWhy: string): TRefactorInfo; static;

    // Die Anfrage zu einem Fund: Zeile aus AFinding, Ziel und '+'-Zahl aus
    // seiner Meldung - SCA044 'Concat (n x ''+'') -> Format(...) Ziel',
    // SCA003 'Ziel  [Fix ..]' (TRdxRecipes.ConcatFindingTarget/
    // SqlFindingTarget). Andere Regeln oder eine fremde Meldungsform:
    // keine Gegenprobe.
    class function QueryOf(AFinding: TLeakFinding;
      const AAnchor: string): TRdxAnchorQuery; static;

    // DescribeAnchor mit Gegenprobe gegen den Fund (Minor 20): der Puffer
    // kann juenger sein als die Fundliste, nach dem Einfuegen von Zeilen
    // steht auf der Fundzeile eine andere Anweisung. Nennt die Anfrage ein
    // Ziel, muss der Knoten der Zeile genau dieses Ziel tragen
    // (TRdxRecipes.TargetKey) - verglichen nur, wenn beide Formen reines
    // ASCII sind (TRdxRecipes.TargetsComparable: Scan und Dienst
    // dekodieren eine UTF-8-Datei ohne BOM verschieden); nennt sie eine
    // '+'-Zahl, muss die Kette des Knotens (TNodeRef.TypeRef) genau so
    // viele '+' haben - sonst nil mit Grund 'Zeile verschoben?' bzw.
    // 'Zeile veraendert?'.
    // Eine Zuweisung beschreibt ChainOf mit der '+'-Zahl des Knotens
    // (TopLevelPlusCount, die Zaehlung von SCA044) als zweiter Gegenprobe
    // (strittiger Minor 2). Zerfaellt der Quelltext anders, kommt nur die
    // Anweisung (fuer "Stelle zeigen") und AWhy nennt den Grund - AWhy
    // kann also auch neben einer Beschreibung stehen.
    class function Describe(APlaces: TSourcePlaces;
      const AQuery: TRdxAnchorQuery; out AIsCall: Boolean;
      out AWhy: string): TRefactorInfo; static;

    // Teilbereiche mit Quelltext - die Eingabe der Rezepte. Operanden
    // tragen ihren deklarierten Typ (Resolved) und bei IntToStr(x) /
    // x.ToString den Typ von x (ArgResolved). In einem with-Block
    // (TSourcePlaces.InWithBlock) ist kein Name bewiesen: InWith ist
    // gesetzt, ArgResolved bleibt leer (strittiger Minor 1).
    class function PartsOf(APlaces: TSourcePlaces;
      AInfo: TRefactorInfo): TRdxParts; static;

    // Deklarierter Typ des Ziels (nackter Bezeichner oder Result), sonst ''.
    // Im with-Block nur ein Typ, der sperrt (Nicht-Unicode-String): ein
    // Unicode-Ziel waere dort nicht bewiesen (strittiger Minor 1).
    class function TargetTypeOf(APlaces: TSourcePlaces; AInfo: TRefactorInfo;
      const ATargetText: string): string; static;

    // Rezept 5.1: Format() aus der Kette nach der Kompilat-Regel
    // (uRdxRecipes.JudgeOperand). AInfo darf nil sein (AWhy wird dann
    // zum Grund; steht AWhy neben einer Beschreibung ohne Kette, haengt
    // er am Grund 'keine Zuweisung mit Kette'). Gesperrt: Kommentar oder
    // Direktive im Bereich (SpanHasComment zaehlt beide; ein '{$' IN
    // einem String-Literal sperrt nicht - Review Minor 16), Ziel
    // oder Operand mit Nicht-Unicode-String-Typ, Operand mit Variant-
    // Anzeichen, Zahl, Klammerausdruck. Dass die Anweisung in einem
    // $IFDEF-Zweig liegt, sperrt nicht - ersetzt wird ihr exakter Text.
    // 'X := X + ...' wird 'X := X + Format(...)'. Fehlt System.SysUtils,
    // traegt das Ergebnis die Einfuegung in die uses-Klausel.
    class function FormatRewrite(APlaces: TSourcePlaces; AInfo: TRefactorInfo;
      const AWhy: string;
      const AUsesNames: TArray<string>): TRdxFormatOutcome; static;

    // Plant die Ergaenzung der uses-Klausel um eine RTL-Unit (Kurzname und
    // qualifizierter Name; der Kurzname, wenn die Datei keine Delphi-
    // Scopes schreibt oder eine FPC-Weiche traegt - Minor 35). Reihenfolge
    // der Stellen: die uses-Klausel des implementation-Abschnitts, sonst
    // die des interface-Abschnitts, sonst die Programm-Klausel (.dpr,
    // .lpr, library). Eine sortierte Liste bleibt sortiert (SCA142), eine
    // unsortierte bekommt den Namen vorn. Ist der Name groesser als alle,
    // wird hinter dem letzten Eintrag angehaengt - samt 'in'-Pfad und
    // Block-Kommentar ('Main in ''Main.pas'' {Form1}'), wenn danach auf
    // derselben Zeile das ';' folgt (Minor 42); steht dort etwas anderes
    // (ein '//'-Kommentar, das ';' erst nach weiterem Text), wird VOR dem
    // letzten eingefuegt - immer gueltig, die Sortierung kann dann
    // brechen. Eine Compiler-Direktive in der Klausel oder eine Klausel in
    // einem $IFDEF-Zweig sperrt (DirectiveLineIn). Ohne jede uses-Klausel
    // wird hinter 'implementation' (sonst 'interface') eine neue angelegt;
    // ein Programm oder eine Library ohne uses-Klausel bekommt keine -
    // Reason 'keine uses-Klausel und kein interface/implementation'.
    class function PlanUses(APlaces: TSourcePlaces;
      const AShortName, AQualifiedName: string): TRdxUsesPlan; static;

    // Erste Zeile mit einer Compiler-Direktive ('{$' oder '(*$') in der
    // Klausel von AEntries - von der Zeile des Schluesselworts 'uses' bis
    // zum letzten Eintrag -, oder die Zeile des '{$IFDEF..}', in dessen
    // Zweig die Klausel (auch nur teilweise) liegt (ConditionalRanges,
    // Review Minor 17); 0 = keine. Ein Eintrag dort kann in einem Zweig
    // fuer ein anderes Ziel liegen (FPC, Delphi vor XE2) - eine Ersetzung
    // oder Einfuegung gehoert dann in Handarbeit.
    class function DirectiveLineIn(APlaces: TSourcePlaces;
      const AEntries: TArray<TRefactorSpan>): Integer; static;

    // Dasselbe ueber JEDE uses-Klausel der Datei (interface,
    // implementation; ohne beide die Programm-Klausel) - fuer Aktionen,
    // die alle Eintraege anfassen (Review reDelphiX 2026-10-07, Major 7).
    class function UsesDirectiveLine(APlaces: TSourcePlaces): Integer; static;

    // True, wenn ALine in einer uses-Klausel liegt: von der Zeile des
    // Schluesselworts 'uses' (Knoten nkUses - steht der erste Eintrag mit
    // auf dieser Zeile, beginnt das Fenster dort und nicht eine Zeile
    // davor; Minor 19) bis zur Zeile des letzten Eintrags. Klauseln wie
    // UsesDirectiveLine: interface und implementation, ohne beide die
    // Programm-Klausel (.dpr/.lpr/library; Minor 18).
    class function LineInUsesClause(APlaces: TSourcePlaces;
      ALine: Integer): Boolean; static;

    // True, wenn die Datei eine FPC-Weiche oder einen FPC-Modus traegt
    // (TRdxRecipes.LineLooksFpcAware, Review Minor 35) - irgendwo, auch
    // ausserhalb der uses-Klauseln ('{$mode objfpc}' am Dateikopf).
    class function SourceLooksFpcAware(APlaces: TSourcePlaces): Boolean; static;

    // Was 'uses: X -> Scope.X' fuer die Zeile ALine anbieten kann (Review
    // reDelphiX nach Bereichen 2026-10-10, Minor 11-14; bis dahin im
    // Anbieter und ungetestet). Nichts (InClause = False) ausserhalb einer
    // uses-Klausel. Gesperrt (Block) ohne Scope-Tabelle, bei Direktiven in
    // einer Klausel und in einer Datei mit FPC-Weiche (FPC 3.2 kennt keine
    // Unit-Scopes). Ein Eintrag geht nicht, wenn die Tabelle ihn nicht
    // eindeutig aufloest, das Projekt eine eigene Unit dieses Namens hat
    // (AIsOwnUnit) oder er eine SORTIERTE Klausel unsortiert machte (neuer
    // SCA142-Fund; dieselbe Regel wie uUnsortedUses: CompareText ueber die
    // Namen je Klausel). Dasselbe fuer 'alle qualifizieren' (AllUnsorts).
    class function QualifyUses(APlaces: TSourcePlaces; AScopes: TRdxScopeTable;
      ALine: Integer; const AIsOwnUnit: TRdxOwnUnitCheck): TRdxQualifyPlan; static;

    // Rezept 5.2: parametrisierte Vorlage (nur Text). Eingerueckt wie die
    // Anweisung - Tabs bleiben Tabs (Minor 31).
    class function SqlTemplate(APlaces: TSourcePlaces; AInfo: TRefactorInfo;
      AIsCall: Boolean; out ATemplate, AHint, AReason: string): Boolean; static;
  end;

  // Editorhilfen Stufe 2a: die einfachen Hilfen aus uRdxSimpleFixes, mit
  // dem Quellstellen-Dienst verbunden - die Ruempfe je Regel. Den Einstieg
  // (Handles, FixFor, AlternativeFixFor), Hinweise und Menuetexte fuehrt
  // seit Charge R8 die Tabelle uRdxFixTable: eine weitere Regel ist dort
  // eine Zeile und hier eine Routine, kein Zweig in einem Verteiler.
  // ALines ist immer derselbe Text, aus dem APlaces geoeffnet wurde.
  TRdxFixRunner = class
  public
    // SCA075: 'class(TObject)' -> 'class' an der Spalte aus der Meldung
    // (nur die Zeilen, kein Parser noetig).
    class function ExplicitTObjectFix(ALines: TStrings; ALine: Integer;
      const AMessage: string): TRdxFixOutcome; static;

    // SCA085: 'X.Free;' (ALine) + 'X := nil;' -> 'FreeAndNil(X);'. X muss
    // in dieser Unit deklariert sein (DeclaredTypeOf): eine Property
    // uebersetzt als Argument nicht, ein geerbtes Feld ist nicht pruefbar -
    // beides keine Hilfe. Fehlt SysUtils, kommt die uses-Einfuegung mit.
    class function FreeAndNilFix(APlaces: TSourcePlaces; ALines: TStrings;
      ALine: Integer; const AUsesNames: TArray<string>): TRdxFixOutcome; static;

    // SCA126: der Fund traegt keine Spalte - umgeschrieben wird die EINE
    // Anweisung, die auf ALine beginnt und einen nil-Vergleich traegt
    // (NodesAt, Knotentext wie uNilComparison), und zwar mit ALLEN ihren
    // Vergleichen. Zwei solche Anweisungen heissen mehrdeutig. Jeder
    // Operand geht durch TRdxNilFix.NilOperandRisk.
    class function NilComparisonFix(APlaces: TSourcePlaces; ALines: TStrings;
      ALine: Integer): TRdxFixOutcome; static;

    // SCA074: 'Assert(c)' -> 'Assert(c, ''c'')' an der Spalte aus der
    // Meldung. Keine Hilfe, wenn die Unit selbst eine Routine Assert
    // deklariert oder ein with den Namen an ein Member binden kann.
    class function AssertMessageFix(APlaces: TSourcePlaces; ALines: TStrings;
      ALine: Integer; const AMessage: string): TRdxFixOutcome; static;

    // SCA087: die leere Sichtbarkeitszeile ALine loeschen (nur die Zeilen).
    class function EmptySectionFix(ALines: TStrings; ALine: Integer;
      const AMessage: string): TRdxFixOutcome; static;

    // SCA139: 'X.Free' -> 'FreeAndNil(X)', X aus der Meldung. Dieselbe
    // Variablen-Pruefung wie SCA085; dazu kein record/object/interface
    // dieser Unit als Typ und keine eigene Methode Free in der Unit ('X.Free'
    // riefe sie, FreeAndNil nicht). Fehlt SysUtils, kommt die uses-
    // Einfuegung mit.
    class function FreeWithoutNilFix(APlaces: TSourcePlaces; ALines: TStrings;
      ALine: Integer; const AMessage: string;
      const AUsesNames: TArray<string>): TRdxFixOutcome; static;

    // SCA066: 'Foo()' -> 'Foo' (TRdxExprFixes.EmptyArgs). Dazu die Typen:
    // ein blosser Name ist keine Variable (Prozedurvariable, CallReason),
    // links von ':=' kein prozeduraler oder unbekannter Typ; kein with-
    // Block. Nicht in einer Datei mit FPC-Weiche oder FPC-Modus: in objfpc
    // ruft erst 'Foo()' eine Prozedurvariable auf.
    class function EmptyArgsFix(APlaces: TSourcePlaces; ALines: TStrings;
      ALine: Integer; const AMessage: string): TRdxFixOutcome; static;

    // SCA072 und SCA084: der Planer liefert die Ersetzung und den Namen X,
    // hier die Pruefung von X - kein with; SCA072: X als Boolean deklariert
    // (bei Variant und LongBool ist 'X = True' nicht dasselbe wie X);
    // SCA084: X als Klasse, Interface oder Zeiger bewiesen (ein Funktionstyp
    // riefe 'X <> nil' auf), keine eigene Routine Assigned.
    class function OperandFix(AKind: TFindingKind; APlaces: TSourcePlaces;
      ALines: TStrings; ALine: Integer;
      const AMessage: string): TRdxFixOutcome; static;

    // SCA007: den uses-Eintrag AUnit (die Meldung) auf ALine loeschen
    // (TRdxStructFixes.RemoveUsesEntry). Gesperrt bei Direktiven in einer
    // uses-Klausel. Aendert evtl. das Verhalten: der initialization-
    // Abschnitt der Unit laeuft nicht mehr (Kennzeichnung in uRdxFixTable).
    class function UnusedUsesFix(APlaces: TSourcePlaces; ALines: TStrings;
      ALine: Integer; const AUnit: string): TRdxFixOutcome; static;

    // SCA168: ein leeres else vor das end des case auf ALine
    // (TRdxStructFixes.CaseElse) - bedeutungsgleich.
    class function CaseElseFix(APlaces: TSourcePlaces; ALines: TStrings;
      ALine: Integer): TRdxFixOutcome; static;
    // SCA168, zweiter Eintrag: else mit RAISE_UNHANDLED - aendert das
    // Verhalten; SysUtils kommt bei Bedarf mit; nicht in Dateien mit
    // FPC-Weiche oder FPC-Modus (FPC kennt EProgrammerError nicht).
    class function CaseRaiseFix(APlaces: TSourcePlaces; ALines: TStrings;
      ALine: Integer; const AUsesNames: TArray<string>): TRdxFixOutcome; static;

    // SCA101 und SCA099: die Anweisung hinter then/else/do in begin..end
    // (TRdxStructFixes.WrapInBlock) - bedeutungsgleich, nur die Zeilen.
    // SCA101: das Schluesselwort an der Spalte aus der Meldung; SCA099:
    // das else hinter dem 'end else' auf ALine.
    class function BlockFix(AKind: TFindingKind; ALines: TStrings;
      ALine: Integer; const AMessage: string): TRdxFixOutcome; static;
  end;

  // Bausteine der Tabelle (uRdxFixTable, Charge R8). Die Planer der
  // Zeilen- und Deklarations-Hilfen haben alle diese Form
  // (TRdxLineFixes.DoubleSemicolon, TRdxDeclFixes.DocSkeleton ...); MapFix
  // oeffnet ihnen die Code-Sicht.
  TRdxMapPlanner = function(AMap: TRdxCodeMap; ALine: Integer;
    const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
  // Die Planer der Anweisungs-Hilfen (uRdxFlowFixes) und die Typpruefung
  // dazu (FlowFix).
  TRdxFlowPlanner = function(AMap: TRdxCodeMap; ALine: Integer;
    const AMessage: string; out APlan: TRdxFlowPlan;
    out AReason: string): Boolean;
  TRdxFlowReason = function(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
    ALine: Integer; const APlan: TRdxFlowPlan): string;

// SCA075, SCA087 und die Zeilen-Hilfen SCA082/SCA071/SCA088, SCA020/SCA120/
// SCA122, SCA117/SCA197/SCA149: APlan arbeitet nur auf den Zeilen, ohne
// Parser - Spalte bzw. Abschnitt stehen in der Meldung, die Code-Sicht
// kennt den Kommentar-Zustand der Zeilen davor. Ohne ALines R_NO_FILE; die
// Ersetzung nach Edits[0], sonst der Grund.
function MapFix(ALines: TStrings; ALine: Integer; const AMessage: string;
  APlan: TRdxMapPlanner): TRdxFixOutcome;
// SCA098, SCA080, SCA047 (Charge H2): APlan auf den Zeilen, danach AReason
// (nil = keine) mit dem Quellstellen-Dienst - Typen, with-Bloecke. Name ist
// das Ziel bzw. Exit/Continue (Menuetext).
function FlowFix(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; APlan: TRdxFlowPlanner;
  AReason: TRdxFlowReason): TRdxFixOutcome;
// SCA123: 'TFoo(X).Free' -> 'X.Free' - Bedingungen am Rumpf.
function CastFreeFix(APlaces: TSourcePlaces; ALines: TStrings;
  ALine: Integer; const AMessage: string): TRdxFixOutcome;
// SCA020, zweiter Eintrag: raise ENotImplemented im leeren Rumpf.
function EmptyRaiseFix(APlaces: TSourcePlaces; ALines: TStrings;
  ALine: Integer; const AUsesNames: TArray<string>): TRdxFixOutcome;
// SCA098: X und (in der Gegenrichtung) die Bedingung als Boolean bewiesen?
// '' oder der Grund.
function CondAssignReason(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  ALine: Integer; const APlan: TRdxFlowPlan): string;
// SCA047: ist das Ziel ein Speicherplatz? '' oder der Grund.
function SelfAssignReason(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  ALine: Integer; const ATarget: string): string;

implementation

uses
  System.StrUtils,   // IndexText (UnitStillUsed)
  uRdxSimpleFixes,   // Planer der einfachen Hilfen (reine Textlogik)
  uRdxStructFixes,   // Planer SCA007/SCA168 (uses-Eintrag, case-else)
  uRdxLineFixes,     // Planer SCA123 (CastFreeFix)
  uRdxRaiseFixes,    // Planer SCA020 mit raise (EmptyRaiseFix)
  uUnusedUses,       // KnownIdents: SCA007-Fund am Puffer nachpruefen
  uSourcePlaces;     // SOURCE_PLACES_VERSION (Vertragspruefung unten)

// Dieser Laeufer ist gegen Version 1 des Quellstellen-Vertrags geschrieben
// (uSourcePlaces, Abschnitt VERTRAGSVERSION). Steigt die Version, bricht
// der Bau hier ab, statt still gegen geaenderte Signaturen, Rollen,
// Koordinaten oder eine schwaechere Typableitung zu laufen. Eine zur
// Laufzeit getauschte BPL erkennt das nicht - das leistet die Paket-
// bindung (Review reDelphiX 2026-10-07, Nit 27).
{$IF SOURCE_PLACES_VERSION <> 1}
  {$MESSAGE ERROR 'reDelphix: SOURCE_PLACES_VERSION hat sich geaendert - Vertrag in uSourcePlaces (VERTRAGSVERSION) pruefen, uRdxRecipeRunner anpassen'}
{$IFEND}

const
  R_NIL_TYPE_UNKNOWN = 'Typ von %s unbekannt - bei einem Funktions- oder '
    + 'Methodenzeiger ruft ''= nil'' ihn auf, Assigned() nicht';
  R_NIL_IN_WITH = 'with-Anweisung - ein Operand koennte ein Member des '
    + 'with-Ausdrucks sein';
  // Der Unterschied, den der Benutzer kennen sollte (SCA085, SCA139):
  // FreeAndNil setzt ERST nil, dann laeuft der Destruktor.
  R_FREENIL_HINT = 'FreeAndNil setzt %s auf nil, bevor der Destruktor laeuft';
  R_WITH_MEMBER  = 'with-Anweisung in der Routine - %s koennte ein Member sein';
  R_NO_HELP      = 'keine Hilfe an dieser Stelle';
  // Hinweise, die der Rumpf selbst setzt - vor dem ' + uses ...' bzw. mit
  // dem Namen; die festen Hinweise je Art fuehrt uRdxFixTable (Charge R8).
  R_CASE_RAISE_HINT = 'unbehandelte Werte loesen EProgrammerError aus';
  R_CAST_HINT   = '%s ist schon als %s deklariert - der Cast aendert nichts';
  R_EMPTY_RAISE_HINT = 'ein Aufruf loest ENotImplemented aus statt nichts zu '
    + 'tun';
  R_PROC_TYPE    = '%s hat einen Prozedurtyp - "%s <> nil" ruft ihn auf, '
    + 'Assigned() nicht';

{ TRdxObjectRing }

constructor TRdxObjectRing.Create(AMaxBatches: Integer);
begin
  inherited Create;
  if AMaxBatches < 1 then AMaxBatches := 1;
  FMax     := AMaxBatches;
  FBatches := TObjectList<TObjectList<TObject>>.Create(True);
end;

destructor TRdxObjectRing.Destroy;
begin
  FBatches.Free;   // gibt die Chargen und darin die Objekte frei
  inherited;
end;

function TRdxObjectRing.Current: TObjectList<TObject>;
begin
  if FBatches.Count = 0 then
    FBatches.Add(TObjectList<TObject>.Create(True));
  Result := FBatches[FBatches.Count - 1];
end;

procedure TRdxObjectRing.BeginBatch;
begin
  FBatches.Add(TObjectList<TObject>.Create(True));
  while FBatches.Count > FMax do
    FBatches.Delete(0);   // aelteste Charge, OwnsObjects gibt alles frei
end;

procedure TRdxObjectRing.Keep(AObject: TObject);
begin
  if not Assigned(AObject) then Exit;
  Current.Add(AObject);
end;

function TRdxObjectRing.Count: Integer;
var
  i : Integer;
begin
  Result := 0;
  for i := 0 to FBatches.Count - 1 do
    Inc(Result, FBatches[i].Count);
end;

function TRdxObjectRing.BatchCount: Integer;
begin
  Result := FBatches.Count;
end;

function TRdxObjectRing.Contains(AObject: TObject): Boolean;
var
  i : Integer;
begin
  Result := False;
  for i := 0 to FBatches.Count - 1 do
    if FBatches[i].IndexOf(AObject) >= 0 then
      Exit(True);
end;

{ TRdxRecipeRunner }

class function TRdxRecipeRunner.HeadOf(const ACallName: string): string;
var
  P : Integer;
begin
  Result := ACallName;
  P := Pos('(', Result);
  if P > 0 then
    Result := Copy(Result, 1, P - 1);
  Result := Trim(Result);
end;

class function TRdxRecipeRunner.UsesNamesOf(
  APlaces: TSourcePlaces): TArray<string>;
var
  Entries : TArray<TRefactorSpan>;
  i       : Integer;
begin
  Result := nil;
  if not Assigned(APlaces) or not APlaces.IsOpen then Exit;
  Entries := APlaces.UsesEntries(TUsesSection.usAny);
  SetLength(Result, Length(Entries));
  for i := 0 to High(Entries) do
    Result[i] := Entries[i].Resolved;
end;

// Der EINE Knoten der Anker-Arten auf der Zeile der Anfrage; False mit
// Grund bei keinem oder mehreren.
function SingleNodeAt(APlaces: TSourcePlaces; const AQuery: TRdxAnchorQuery;
  out ANode: TNodeRef; out AWhy: string): Boolean;
var
  Kinds : TNodeKinds;
  Nodes : TArray<TNodeRef>;
begin
  Result := False;
  ANode  := Default(TNodeRef);
  AWhy   := '';
  if AQuery.Anchor = 'assign' then
    Kinds := [TNodeKind.nkAssign]
  else if AQuery.Anchor = 'call' then
    Kinds := [TNodeKind.nkCall]
  else
    Kinds := [TNodeKind.nkAssign, TNodeKind.nkCall];
  Nodes := APlaces.NodesAt(AQuery.Line, Kinds);
  if Length(Nodes) = 0 then
    AWhy := Format('keine Anweisung auf Zeile %d gefunden', [AQuery.Line])
  else if Length(Nodes) > 1 then
    AWhy := Format('Zeile %d ist mehrdeutig (%d Anweisungen)',
      [AQuery.Line, Length(Nodes)])
  else
  begin
    ANode  := Nodes[0];
    Result := True;
  end;
end;

// Gegenprobe des Knotens gegen den Fund (Minor 20): '' oder der Grund.
// Das Ziel vergleicht TargetKey (ein Aufruf zaehlt als 'Kopf()' wie in der
// SCA003-Meldung), die '+'-Zahl gilt nur fuer eine Zuweisung. Das Ziel nur
// bei reinem ASCII auf beiden Seiten (TRdxRecipes.TargetsComparable, Review-
// Nachlese 2026-10-09): die Meldung las der Scan als ANSI, den Knoten der
// Dienst als UTF-8 - ein Umlaut sperrte sonst eine gueltige Aktion. Dann
// traegt die '+'-Zahl die Gegenprobe allein.
function MismatchOf(const AQuery: TRdxAnchorQuery;
  const ANode: TNodeRef): string;
var
  Plus     : Integer;
  NodeKey  : string;
  QueryKey : string;
  Same     : Boolean;
begin
  Result := '';
  if AQuery.Target <> '' then
  begin
    NodeKey  := TRdxRecipes.TargetKey(ANode.Name);
    QueryKey := TRdxRecipes.TargetKey(AQuery.Target);
    // Mit Nicht-ASCII im Ziel wenigstens der ASCII-Anteil - sonst entfiel
    // fuer SCA003 (ohne '+'-Probe) jede Gegenprobe (Nit 25).
    if TRdxRecipes.TargetsComparable(NodeKey, QueryKey) then
      Same := SameText(NodeKey, QueryKey)
    else
      Same := SameText(TRdxRecipes.AsciiOnly(NodeKey),
        TRdxRecipes.AsciiOnly(QueryKey));
    if not Same then
      Exit(Format('Zeile %d traegt %s, der Fund nennt %s - Zeile verschoben? '
        + 'Datei neu pruefen', [AQuery.Line, NodeKey, AQuery.Target]));
  end;
  if (AQuery.Plus < 0) or (ANode.Kind <> TNodeKind.nkAssign) then Exit;
  Plus := TRdxRecipes.TopLevelPlusCount(ANode.TypeRef);
  if Plus <> AQuery.Plus then
    Result := Format('Kette auf Zeile %d hat %d x ''+'', der Fund nennt %d - '
      + 'Zeile veraendert? Datei neu pruefen', [AQuery.Line, Plus, AQuery.Plus]);
end;

// Kette bzw. Aufruf des Knotens, sonst wenigstens die Anweisung (fuer
// "Stelle zeigen"). Eine Zuweisung beschreibt ChainOf mit der '+'-Zahl,
// die der Parser fuer den Knoten sieht (TypeRef - dieselbe Zaehlung wie
// SCA044; negativ = keine Gegenprobe). Weicht die Zerlegung des
// Quelltexts davon ab, beschreiben beide nicht dieselbe Kette: dann nur
// die Anweisung, und AWhy sagt warum (strittiger Minor 2).
function DescribeNode(APlaces: TSourcePlaces; const ANode: TNodeRef;
  out AWhy: string): TRefactorInfo;
var
  Plus  : Integer;
  Probe : TRefactorInfo;
begin
  AWhy := '';
  if ANode.Kind = TNodeKind.nkAssign then
  begin
    Plus := TRdxRecipes.TopLevelPlusCount(ANode.TypeRef);
    Result := APlaces.ChainOf(ANode.Line, ANode.Col, ANode.Name, Plus);
    if (Result = nil) and (Plus >= 0) then
    begin
      Probe := APlaces.ChainOf(ANode.Line, ANode.Col, ANode.Name);
      if Assigned(Probe) then
        AWhy := Format('Kette auf Zeile %d: der Quelltext zerfaellt anders '
          + 'als der Parser sie sieht (%d x ''+'')', [ANode.Line, Plus]);
      Probe.Free;
    end;
  end
  else
    Result := APlaces.CallOf(ANode.Line, ANode.Col,
      TRdxRecipeRunner.HeadOf(ANode.Name));
  if Result = nil then
    Result := APlaces.StatementAt(ANode.Line, ANode.Col);
  if (Result = nil) and (AWhy = '') then
    AWhy := 'Anweisung laesst sich nicht beschreiben';
end;

class function TRdxRecipeRunner.DescribeAnchor(APlaces: TSourcePlaces;
  ALine: Integer; const AAnchor: string; out AIsCall: Boolean;
  out AWhy: string): TRefactorInfo;
var
  Q : TRdxAnchorQuery;
begin
  Q := Default(TRdxAnchorQuery);
  Q.Line   := ALine;
  Q.Anchor := AAnchor;
  Q.Plus   := TSourcePlaces.ANY_PLUS_COUNT;
  Result := Describe(APlaces, Q, AIsCall, AWhy);
end;

class function TRdxRecipeRunner.QueryOf(AFinding: TLeakFinding;
  const AAnchor: string): TRdxAnchorQuery;
begin
  Result := Default(TRdxAnchorQuery);
  Result.Anchor := AAnchor;
  Result.Plus   := TSourcePlaces.ANY_PLUS_COUNT;
  if not Assigned(AFinding) then Exit;
  Result.Line := AFinding.LineInt;
  // Nur SCA044 und SCA003 nennen ihr Ziel in der Meldung; passt die Form
  // nicht, bleibt die Anfrage ohne Gegenprobe (Ziel '', Zahl -1).
  if AFinding.Kind = fkConcatToFormat then
    TRdxRecipes.ConcatFindingTarget(AFinding.MissingVar, Result.Target,
      Result.Plus)
  else if AFinding.Kind = fkSQLInjection then
    Result.Target := TRdxRecipes.SqlFindingTarget(AFinding.MissingVar);
end;

class function TRdxRecipeRunner.Describe(APlaces: TSourcePlaces;
  const AQuery: TRdxAnchorQuery; out AIsCall: Boolean;
  out AWhy: string): TRefactorInfo;
var
  N : TNodeRef;
begin
  Result  := nil;
  AIsCall := False;
  AWhy    := '';
  if not Assigned(APlaces) or not APlaces.IsOpen then
  begin
    AWhy := R_NO_FILE;
    Exit;
  end;
  if not SingleNodeAt(APlaces, AQuery, N, AWhy) then Exit;
  AWhy := MismatchOf(AQuery, N);
  if AWhy <> '' then Exit;
  AIsCall := N.Kind = TNodeKind.nkCall;
  Result  := DescribeNode(APlaces, N, AWhy);
end;

// Ein Operand fuer PartsOf: die deklarierten Typen von Argument
// (IntToStr(x) -> %d/%u) und Kopf (V.Name mit V: Variant). Im with-Block
// (APart.InWith, vom Aufrufer gesetzt) kann x ein Member sein - Cardinal
// statt Integer machte %d negativ -, deshalb dort kein ArgResolved;
// HeadResolved sperrt nur (Variant) und bleibt (strittiger Minor 1).
procedure ResolveOperandPart(APlaces: TSourcePlaces; AAnchorLine: Integer;
  var APart: TRdxPart);
var
  Arg : string;
begin
  Arg := TRdxRecipes.IntegerArgumentOf(APart.Text);
  if (Arg <> '') and not APart.InWith then
    APart.ArgResolved := APlaces.DeclaredTypeOf(AAnchorLine, Arg);
  if TRdxRecipes.IsPlainIdent(Trim(APart.Text)) then Exit;
  Arg := TRdxRecipes.HeadIdentOf(APart.Text);
  if Arg <> '' then
    APart.HeadResolved := APlaces.DeclaredTypeOf(AAnchorLine, Arg);
end;

class function TRdxRecipeRunner.PartsOf(APlaces: TSourcePlaces;
  AInfo: TRefactorInfo): TRdxParts;
var
  i      : Integer;
  InWith : Boolean;
begin
  Result := nil;
  if not Assigned(APlaces) or not Assigned(AInfo) then Exit;
  InWith := APlaces.InWithBlock(AInfo.Span.StartLine);
  SetLength(Result, Length(AInfo.Parts));
  for i := 0 to High(AInfo.Parts) do
  begin
    Result[i] := TRdxRecipes.MakePart(AInfo.Parts[i].Role,
      APlaces.TextOf(AInfo.Parts[i]), AInfo.Parts[i].ValueType,
      AInfo.Parts[i].Resolved);
    if AInfo.Parts[i].Role = ROLE_OPERAND then
    begin
      Result[i].InWith := InWith;
      Result[i].Shadowed := APlaces.DeclaresNonStringFunc(
        TRdxRecipes.ShadowNameOf(Result[i].Text));
      ResolveOperandPart(APlaces, AInfo.Span.StartLine, Result[i]);
    end
    else if (AInfo.Parts[i].Role = ROLE_TARGET) and (Result[i].Resolved = '') then
      Result[i].Resolved := TargetTypeOf(APlaces, AInfo, Result[i].Text);
  end;
end;

class function TRdxRecipeRunner.TargetTypeOf(APlaces: TSourcePlaces;
  AInfo: TRefactorInfo; const ATargetText: string): string;
var
  T : string;
begin
  Result := '';
  T := Trim(ATargetText);
  if not Assigned(APlaces) or not Assigned(AInfo) then Exit;
  if not TRdxRecipes.IsPlainIdent(T) then Exit;
  Result := APlaces.DeclaredTypeOf(AInfo.Span.StartLine, T);
  // with-Block: das Ziel kann ein Member sein. Ein sperrender Typ bleibt
  // (vorsichtig), ein Unicode-Ziel gilt dort nicht als bewiesen - es
  // liesse sonst AnsiString-Operanden zu (TargetU in BuildFormatCall).
  if APlaces.InWithBlock(AInfo.Span.StartLine)
     and not TRdxRecipes.IsNonUnicodeStringType(Result) then
    Result := '';
end;

// S ohne Leerraum (alles <= ' ') - vorab bemessen statt verkettet (SCA110).
function WithoutBlanks(const S: string): string;
var
  i, n : Integer;
begin
  SetLength(Result, Length(S));
  n := 0;
  for i := 1 to Length(S) do
    if S[i] > ' ' then
    begin
      Inc(n);
      Result[n] := S[i];
    end;
  SetLength(Result, n);
end;

// Gleicher Operand ohne Leerraum und Schreibung: 'Result' = 'result'.
function SameOperandText(const A, B: string): Boolean;
var
  SA : string;
begin
  SA := WithoutBlanks(A);
  Result := (SA <> '') and SameText(SA, WithoutBlanks(B));
end;

const
  // So viele Operanden "laut Kompilat" nennt der Hinweis mit Namen.
  MAX_HINT_NAMES = 3;

// Die ersten MAX_HINT_NAMES Namen, mit ', ' verbunden; ', ...' bei mehr.
function ByCompilerNames(const ANames: TArray<string>): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(ANames) do
    begin
      if i = MAX_HINT_NAMES then
      begin
        SB.Append(', ...');
        Break;
      end;
      if SB.Length > 0 then SB.Append(', ');
      SB.Append(ANames[i]);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Hinweis eines aktiven Format-Eintrags: Termzahl, bei Selbst-Anhaengen
// das Ziel (ABehind, sonst ''), Herkunft der Argumente.
function FormatHintOf(const ABuild: TRdxFormatBuild; ATerms: Integer;
  const ABehind: string): string;
begin
  Result := Format('%d Terme', [ATerms]);
  if ABehind <> '' then
    Result := Result + ' hinter ' + ABehind;
  if Length(ABuild.ByCompiler) = 0 then
    Result := Result + ', alle bewiesen'
  else
    Result := Result + Format(', %d laut Kompilat (%s)',
      [Length(ABuild.ByCompiler), ByCompilerNames(ABuild.ByCompiler)]);
  if ABuild.Numeric > 0 then
    Result := Result + Format(', %d numerisch (%%d/%%u)', [ABuild.Numeric]);
end;

// Ohne Beschreibung: der Grund aus Describe, sonst 'keine Beschreibung'.
function NoInfoReason(const AWhy: string): string;
begin
  Result := AWhy;
  if Result = '' then
    Result := 'keine Beschreibung';
end;

// Keine Zuweisung mit Kette - dazu der Grund aus Describe, wenn er neben
// einer Beschreibung steht (die Kette passte nicht).
function NoChainReason(const AWhy: string): string;
begin
  Result := 'keine Zuweisung mit Kette';
  if AWhy <> '' then
    Result := Result + ': ' + AWhy;
end;

// Selbst-Anhaengen 'X := X + ...' (ein Drittel der Korpus-Stellen): der
// erste Operand ist das Ziel.
function IsSelfAppend(const AParts: TRdxParts; AInfo: TRefactorInfo;
  ALast: Integer): Boolean;
begin
  Result := (ALast >= 3) and (AInfo.Parts[1].Role = ROLE_OPERAND)
    and SameOperandText(AParts[1].Text, AParts[0].Text);
end;

// Der Grund, wenn BuildFormatCall ablehnt: hinter 'X +' nur Literale heisst
// anders als 'kein Operand'.
function BuildReasonOf(const ABuild: TRdxFormatBuild;
  const ABehind: string): string;
begin
  Result := ABuild.Reason;
  if (ABehind <> '') and (ABuild.Operands = 0)
     and (Pos('kein Operand', ABuild.Reason) > 0) then
    Result := 'hinter ' + ABehind + ' stehen nur Literale';
end;

// Format() lebt in System.SysUtils: fehlt die Unit, kommt sie mit - nicht
// ausgrauen, sondern die uses-Klausel ergaenzen (Nico, 2026-10-06). ''
// oder der Grund, wenn die Einfuegung nicht planbar ist.
function FormatUsesReason(APlaces: TSourcePlaces;
  const AUsesNames: TArray<string>; var AOutcome: TRdxFormatOutcome): string;
var
  Plan : TRdxUsesPlan;
begin
  Result := '';
  if TRdxRecipes.HasUnit(AUsesNames, 'SysUtils') then Exit;
  Plan := TRdxRecipeRunner.PlanUses(APlaces, 'SysUtils', 'System.SysUtils');
  if not Plan.Needed then Exit;
  if Plan.Reason <> '' then
    Exit('System.SysUtils fehlt in uses: ' + Plan.Reason);
  AOutcome.NeedsUses := True;
  AOutcome.UsesName  := Plan.Name;
  AOutcome.UsesEdit  := Plan.Edit;
  AOutcome.Hint := AOutcome.Hint + ' + uses ' + Plan.Name;
end;

class function TRdxRecipeRunner.FormatRewrite(APlaces: TSourcePlaces;
  AInfo: TRefactorInfo; const AWhy: string;
  const AUsesNames: TArray<string>): TRdxFormatOutcome;
var
  Parts  : TRdxParts;
  Last   : Integer;
  First  : Integer;
  Build  : TRdxFormatBuild;
  TType  : string;
  Behind : string;
begin
  Result := Default(TRdxFormatOutcome);
  if AInfo = nil then
  begin
    Result.Reason := NoInfoReason(AWhy);
    Exit;
  end;
  Parts := PartsOf(APlaces, AInfo);
  Last  := High(AInfo.Parts);
  // Eine Kette hat mindestens zwei Terme (Ziel + zwei Parts). Ein
  // einzelner Term - etwa das schon umgeformte 'X := Format(...)' -
  // ist keine (zweiter Lauf, Rewrite_AppliedOnce_NoSecondFinding).
  if (Last < 2) or (AInfo.Parts[0].Role <> ROLE_TARGET) then
  begin
    Result.Reason := NoChainReason(AWhy);
    Exit;
  end;
  // Ziel mit Nicht-Unicode-String-Typ: Format liefert UnicodeString, die
  // Zuweisung wuerde konvertieren (Alcinoe, Indy: AnsiString-Ketten).
  TType := Parts[0].Resolved;
  if TRdxRecipes.IsNonUnicodeStringType(TType) then
  begin
    Result.Reason := Format('Ziel ''%s'' ist %s - Format liefert UnicodeString',
      [TRdxRecipes.CollapseWhitespace(Parts[0].Text), TType]);
    Exit;
  end;
  // Selbst-Anhaengen: Format nur ueber den Rest, X bleibt vorn -
  // 'X := X + Format(...)'.
  First := 1;
  Result.SelfAppend := IsSelfAppend(Parts, AInfo, Last);
  if Result.SelfAppend then
    First := 2;
  // Ersetzt wird vom ersten (bzw. zweiten) bis zum letzten Term; Ziel und
  // ':=' (und bei Selbst-Anhaengen 'X +') bleiben.
  Result.Span := TRefactorSpan.Make(ROLE_STATEMENT,
    AInfo.Parts[First].StartLine, AInfo.Parts[First].StartCol,
    AInfo.Parts[Last].EndLine, AInfo.Parts[Last].EndCol);
  Result.Expected := APlaces.TextOf(Result.Span);
  if Result.Expected = '' then
  begin
    Result.Reason := 'Bereich nicht lesbar';
    Exit;
  end;
  // Ein Kommentar im ERSETZTEN Bereich ginge verloren - ein Kommentar
  // zwischen ':=' und dem ersten Term bleibt stehen und sperrt nicht
  // (AH22; rfHasComment der Anweisung gilt ab dem Ziel). Eine Compiler-
  // Direktive im Bereich zaehlt wie ein Kommentar: SpanHasComment sieht
  // jedes '{..}' und '(*..*)' ausserhalb von Strings, auch '{$..}'. Ein
  // '{$' IN einem String-Literal ist keine Direktive und sperrt nicht
  // (Review reDelphiX 2026-10-07, Minor 16 - die fruehere Rohtext-Suche
  // nach '{$' traf nur noch diesen Fall). Dass die Anweisung in
  // einem $IFDEF-Zweig LIEGT, sperrt seit AH20 nicht mehr. Die Pruefung
  // steht VOR dem Format-Aufbau: ein Operand mit Kommentar darin
  // ('{alt} Marker') hat keine Operandenform, und der Grund soll
  // "Kommentar" heissen, nicht "kein einfacher Operand"
  // (reDelphix.Test Rewrite_CommentInChain_Disabled, rot 2026-10-07).
  if APlaces.SpanHasComment(Result.Span) then
  begin
    Result.Reason := 'Kommentar im Bereich';
    Exit;
  end;
  Behind := '';
  if Result.SelfAppend then
    Behind := TRdxRecipes.CollapseWhitespace(Parts[0].Text);
  if not TRdxRecipes.BuildFormatCall(Copy(Parts, First, Last - First + 1),
       Build, TType) then
  begin
    Result.Reason := BuildReasonOf(Build, Behind);
    Exit;
  end;
  Result.NewText    := Build.NewText;
  Result.Operands   := Build.Operands;
  Result.Proven     := Build.Proven;
  Result.Numeric    := Build.Numeric;
  Result.ByCompiler := Build.ByCompiler;
  Result.Hint := FormatHintOf(Build, Last - First + 1, Behind);
  Result.Reason := FormatUsesReason(APlaces, AUsesNames, Result);
  Result.Enabled := Result.Reason = '';
end;

// Die uses-Klauseln der Datei, je Klausel ihre Eintraege: interface und
// implementation; hat die Datei keine von beiden (Programm, Library - die
// Klausel haengt am Wurzelknoten), die Klausel, die usAny liefert. Leere
// Klauseln fehlen.
function ClausesOf(APlaces: TSourcePlaces): TArray<TArray<TRefactorSpan>>;
var
  Intf, Impl : TArray<TRefactorSpan>;
begin
  Result := nil;
  Intf := APlaces.UsesEntries(TUsesSection.usInterface);
  Impl := APlaces.UsesEntries(TUsesSection.usImplementation);
  if (Length(Intf) = 0) and (Length(Impl) = 0) then
    Intf := APlaces.UsesEntries(TUsesSection.usAny);
  if Length(Intf) > 0 then
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Intf;
  end;
  if Length(Impl) > 0 then
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Impl;
  end;
end;

// Zeile des Schluesselworts 'uses' der Klausel, deren erster Eintrag
// AFirst ist: der Knoten nkUses (uParser2.ParseUses legt ihn am 'uses'
// ab), gesucht von der Zeile des Eintrags aufwaerts - dazwischen stehen
// hoechstens Leerzeilen und Kommentare. Ohne Knoten (sollte nicht
// vorkommen) die Zeile davor, die fruehere Naeherung.
function UsesKeywordLine(APlaces: TSourcePlaces;
  const AFirst: TRefactorSpan): Integer;
const
  MAX_LOOKBACK = 64;
var
  L : Integer;
begin
  L := AFirst.StartLine;
  while (L >= 1) and (L > AFirst.StartLine - MAX_LOOKBACK) do
  begin
    if Length(APlaces.NodesAt(L, [TNodeKind.nkUses])) > 0 then
      Exit(L);
    Dec(L);
  end;
  Result := AFirst.StartLine - 1;
  if Result < 1 then Result := 1;
end;

// Letzte Zeile der Eintraege einer Klausel.
function ClauseLastLine(const AEntries: TArray<TRefactorSpan>): Integer;
var
  i : Integer;
begin
  Result := 0;
  for i := 0 to High(AEntries) do
    if AEntries[i].EndLine > Result then
      Result := AEntries[i].EndLine;
end;

// '{$' oder '(*$' im Zeilentext - eine Direktive (oder ihr Text).
function HasDirectiveText(const ALine: string): Boolean;
begin
  Result := (Pos('{$', ALine) > 0) or (Pos('(*$', ALine) > 0);
end;

class function TRdxRecipeRunner.DirectiveLineIn(APlaces: TSourcePlaces;
  const AEntries: TArray<TRefactorSpan>): Integer;
var
  Lo, Hi : Integer;
  i      : Integer;
  Ranges : TArray<TSourceLineRange>;
begin
  Result := 0;
  if (APlaces = nil) or (Length(AEntries) = 0) then Exit;
  Lo := UsesKeywordLine(APlaces, AEntries[0]);
  Hi := ClauseLastLine(AEntries);
  for i := Lo to Hi do
    if HasDirectiveText(APlaces.LineText(i)) then
    begin
      Result := i;
      Break;
    end;
  // Liegt die Klausel (auch nur teilweise) in einem bedingten Zweig, steht
  // vielleicht keine Direktive zwischen den Eintraegen: '{$IFDEF X}' /
  // 'uses A;' / '{$ENDIF}' (Review reDelphiX 2026-10-07, Minor 17).
  Ranges := APlaces.ConditionalRanges;
  for i := 0 to High(Ranges) do
    if (Ranges[i].StartLine <= Hi) and (Ranges[i].EndLine >= Lo)
       and ((Result = 0) or (Ranges[i].StartLine < Result)) then
      Result := Ranges[i].StartLine;
end;

class function TRdxRecipeRunner.UsesDirectiveLine(APlaces: TSourcePlaces): Integer;
var
  Clauses : TArray<TArray<TRefactorSpan>>;
  i       : Integer;
begin
  Result := 0;
  if (APlaces = nil) or not APlaces.IsOpen then Exit;
  Clauses := ClausesOf(APlaces);
  for i := 0 to High(Clauses) do
  begin
    Result := DirectiveLineIn(APlaces, Clauses[i]);
    if Result > 0 then Exit;
  end;
end;

class function TRdxRecipeRunner.LineInUsesClause(APlaces: TSourcePlaces;
  ALine: Integer): Boolean;
var
  Clauses : TArray<TArray<TRefactorSpan>>;
  i       : Integer;
begin
  Result := False;
  if (APlaces = nil) or not APlaces.IsOpen or (ALine < 1) then Exit;
  Clauses := ClausesOf(APlaces);
  for i := 0 to High(Clauses) do
    if (ALine >= UsesKeywordLine(APlaces, Clauses[i][0]))
       and (ALine <= ClauseLastLine(Clauses[i])) then
      Exit(True);
end;

class function TRdxRecipeRunner.SourceLooksFpcAware(
  APlaces: TSourcePlaces): Boolean;
var
  L : Integer;
begin
  Result := False;
  for L := 1 to APlaces.LineCount do
    if TRdxRecipes.LineLooksFpcAware(APlaces.LineText(L)) then
      Exit(True);
end;

// True, wenn die naechste nicht leere Zeile nach ALine mit ';' beginnt.
function SemicolonStartsNextLine(APlaces: TSourcePlaces;
  ALine: Integer): Boolean;
var
  L : Integer;
  T : string;
begin
  Result := False;
  for L := ALine + 1 to APlaces.LineCount do
  begin
    T := Trim(APlaces.LineText(L));
    if T <> '' then
      Exit(T[1] = ';');
  end;
end;

// Darf hinter dem letzten Eintrag ALast angehaengt werden? Ja, wenn auf
// seiner Zeile - hinter einem 'in'-Pfad und Block-Kommentaren, die dann zum
// Bereich gehoeren (ASpan) - das ';' folgt (TRdxRecipes.UsesTailLength),
// oder wenn die Zeile hinter dem Namen endet und die naechste nicht leere
// mit ';' beginnt. Sonst ('//'-Kommentar, ein Pfad auf der Folgezeile ...)
// False: dann VOR dem letzten einfuegen.
function AppendSpanOf(APlaces: TSourcePlaces; const ALast: TRefactorSpan;
  out ASpan: TRefactorSpan): Boolean;
var
  Rest : string;
  Tail : Integer;
begin
  ASpan := ALast;
  Rest  := Copy(APlaces.LineText(ALast.EndLine), ALast.EndCol, MaxInt);
  if Trim(Rest) = '' then
    Exit(SemicolonStartsNextLine(APlaces, ALast.EndLine));
  Tail   := TRdxRecipes.UsesTailLength(Rest);
  Result := Tail >= 0;
  if Result then
    ASpan.EndCol := ALast.EndCol + Tail;
end;

// Die Einfuegung in eine bestehende Klausel (PlanUses). APlan.Name steht.
procedure PlanIntoClause(APlaces: TSourcePlaces;
  const AEntries: TArray<TRefactorSpan>; var APlan: TRdxUsesPlan);
var
  Names  : TArray<string>;
  i, Idx : Integer;
  E      : TRefactorSpan;
  Append : Boolean;
  Old    : string;
begin
  // Compiler-Direktiven in der Klausel ('uses A {$IFDEF X}, B{$ENDIF};')
  // oder eine Klausel in einem bedingten Zweig: jede Einfuegestelle kann
  // in einem Zweig liegen, der fuer ein anderes Ziel nicht uebersetzt
  // wird - dann von Hand.
  i := TRdxRecipeRunner.DirectiveLineIn(APlaces, AEntries);
  if i > 0 then
  begin
    APlan.Reason := Format('uses-Klausel traegt Compiler-Direktiven (Zeile %d)', [i]);
    Exit;
  end;
  SetLength(Names, Length(AEntries));
  for i := 0 to High(AEntries) do
    Names[i] := AEntries[i].Resolved;
  Idx := TRdxRecipes.SortedInsertIndex(Names, APlan.Name);
  // Groesser als alle: anhaengen, wenn das geht (samt Pfad/Kommentar,
  // Minor 42) - sonst VOR dem letzten Eintrag, das ist immer gueltig.
  Append := False;
  if Idx >= Length(AEntries) then
    Append := AppendSpanOf(APlaces, AEntries[High(AEntries)], E);
  if not Append then
  begin
    if Idx > High(AEntries) then Idx := High(AEntries);
    E := AEntries[Idx];
  end;
  // Ersetzt wird der Eintrag so, wie er im Puffer steht (TextOf), nicht
  // der aufgeloeste Name - der Editor vergleicht Zeichen fuer Zeichen.
  Old := APlaces.TextOf(E);
  if Old = '' then
  begin
    APlan.Reason := Format('uses-Eintrag in Zeile %d nicht lesbar',
      [E.StartLine]);
    Exit;
  end;
  APlan.Edit.Span     := E;
  APlan.Edit.Expected := Old;
  if Append then
    APlan.Edit.NewText := Old + ', ' + APlan.Name
  else
    APlan.Edit.NewText := APlan.Name + ', ' + Old;
end;

// Keine uses-Klausel (PlanUses): eine neue hinter 'implementation', sonst
// hinter 'interface' anlegen - als Ersetzung der Schluesselwort-Zeile. Ein
// Programm oder eine Library hat keinen der beiden Abschnitte: Reason.
procedure PlanNewClause(APlaces: TSourcePlaces; var APlan: TRdxUsesPlan);
var
  Line : Integer;
  Text : string;
begin
  Line := APlaces.SectionLine(TUsesSection.usImplementation);
  if Line = 0 then
    Line := APlaces.SectionLine(TUsesSection.usInterface);
  if Line = 0 then
  begin
    APlan.Reason := 'keine uses-Klausel und kein interface/implementation';
    Exit;
  end;
  Text := APlaces.LineText(Line);
  if Trim(Text) = '' then
  begin
    APlan.Reason := Format('Zeile %d des Abschnitts nicht lesbar', [Line]);
    Exit;
  end;
  APlan.Edit.Span     := TRefactorSpan.Make(ROLE_STATEMENT, Line, 1, Line,
    Length(Text) + 1);
  APlan.Edit.Expected := Text;
  APlan.Edit.NewText  := Text + #10 + #10 + 'uses' + #10 + '  '
    + APlan.Name + ';';
end;

class function TRdxRecipeRunner.PlanUses(APlaces: TSourcePlaces;
  const AShortName, AQualifiedName: string): TRdxUsesPlan;
var
  AllNames : TArray<string>;
  Entries  : TArray<TRefactorSpan>;
begin
  Result := Default(TRdxUsesPlan);
  if not Assigned(APlaces) or not APlaces.IsOpen then
  begin
    Result.Needed := True;
    Result.Reason := R_NO_FILE;
    Exit;
  end;
  AllNames := UsesNamesOf(APlaces);
  if TRdxRecipes.HasUnit(AllNames, AShortName) then Exit;   // schon da
  Result.Needed := True;
  // FPC 3.2 kennt keine Unit-Scopes: eine Datei mit FPC-Weiche bekommt
  // den Kurznamen, Delphi loest ihn ueber die Vorgabe-Scopes ebenso auf.
  if SourceLooksFpcAware(APlaces) then
    Result.Name := AShortName
  else
    Result.Name := TRdxRecipes.UsesNameFor(AllNames, AShortName, AQualifiedName);

  // Die Klausel: implementation vor interface vor beliebig (Programm).
  Entries := APlaces.UsesEntries(TUsesSection.usImplementation);
  if Length(Entries) = 0 then
    Entries := APlaces.UsesEntries(TUsesSection.usInterface);
  if Length(Entries) = 0 then
    Entries := APlaces.UsesEntries(TUsesSection.usAny);
  if Length(Entries) > 0 then
    PlanIntoClause(APlaces, Entries, Result)
  else
    PlanNewClause(APlaces, Result);
end;

class function TRdxRecipeRunner.SqlTemplate(APlaces: TSourcePlaces;
  AInfo: TRefactorInfo; AIsCall: Boolean;
  out ATemplate, AHint, AReason: string): Boolean;
var
  Parts : TRdxParts;
  i, N  : Integer;
begin
  Result    := False;
  ATemplate := '';
  AHint     := '';
  AReason   := '';
  if AInfo = nil then
  begin
    AReason := 'keine Beschreibung';
    Exit;
  end;
  Parts := PartsOf(APlaces, AInfo);
  if (Length(Parts) = 0) or (Parts[0].Role <> ROLE_TARGET) then
  begin
    AReason := 'kein Ziel erkannt';
    Exit;
  end;
  // Einrueckung wie vor der Anweisung - Tabs bleiben Tabs (Minor 31).
  if not TRdxRecipes.BuildSqlTemplate(Parts[0].Text, AIsCall, Parts,
       TRdxRecipes.IndentTextOf(Copy(APlaces.LineText(AInfo.Span.StartLine),
         1, AInfo.InsertIndent)), ATemplate, AReason) then
    Exit;
  N := 0;
  for i := 0 to High(Parts) do
    if Parts[i].Role = ROLE_OPERAND then Inc(N);
  AHint  := Format('%d Parameter, nichts wird geschrieben', [N]);
  Result := True;
end;

{ TRdxFixRunner }

function MapFix(ALines: TStrings; ALine: Integer; const AMessage: string;
  APlan: TRdxMapPlanner): TRdxFixOutcome;
var
  Map : TRdxCodeMap;
begin
  Result := Default(TRdxFixOutcome);
  if not Assigned(ALines) then
  begin
    Result.Reason := R_NO_FILE;
    Exit;
  end;
  SetLength(Result.Edits, 1);
  Map := TRdxCodeMap.Create(ALines);
  try
    Result.Enabled := APlan(Map, ALine, AMessage, Result.Edits[0], Result.Reason);
  finally
    Map.Free;
  end;
  if not Result.Enabled then
    Result.Edits := nil;
end;

class function TRdxFixRunner.ExplicitTObjectFix(ALines: TStrings;
  ALine: Integer; const AMessage: string): TRdxFixOutcome;
begin
  Result := MapFix(ALines, ALine, AMessage, TRdxSimpleFixes.ExplicitTObject);
end;

// SCA085: ist AName an ALine sicher eine Variable? FreeAndNil braucht eine;
// eine Property uebersetzt als Argument nicht (vor 10.4) bzw. umgeht ihren
// Setter (const [ref]). Gesperrt: irgendwo in der Unit als Property
// deklariert, ein 'with' davor in der Routine oder ein with-Block um die
// Zeile (auch 'with X do Y.Free;' auf EINER Zeile - InWithBlock; dort
// bindet der Name evtl. an ein Member), weder deklariert (DeclaredTypeOf:
// Parameter, lokal, Result, Feld oder Global der Unit) noch Inline-
// Variable ohne Typ. '' oder der Grund.
function VariableCheck(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  ALine: Integer; const AName: string): string;
begin
  Result := '';
  if TRdxSimpleFixes.DeclaresProperty(AMap, AName) then
    Exit(Format('%s ist in dieser Unit als Property deklariert - FreeAndNil '
      + 'braucht eine Variable', [AName]));
  if TRdxSimpleFixes.WithBefore(AMap, ALine) or APlaces.InWithBlock(ALine) then
    Exit(Format(R_WITH_MEMBER, [AName]));
  if (APlaces.DeclaredTypeOf(ALine, AName) = '')
     and not TRdxSimpleFixes.DeclaresInlineVar(AMap, ALine, AName) then
    Result := Format('%s ist hier nicht als Variable bekannt (Property oder '
      + 'Feld aus einer anderen Unit?)', [AName]);
end;

// FreeAndNil steht in SysUtils: fehlt die Unit in uses, haengt die
// Einfuegung an AOutcome.Edits und an den Hinweis. False (Edits geleert,
// Grund gesetzt), wenn die Einfuegung nicht planbar ist.
function AppendSysUtils(APlaces: TSourcePlaces;
  const AUsesNames: TArray<string>; var AOutcome: TRdxFixOutcome): Boolean;
var
  Plan : TRdxUsesPlan;
begin
  Result := True;
  if TRdxRecipes.HasUnit(AUsesNames, 'SysUtils') then Exit;
  Plan := TRdxRecipeRunner.PlanUses(APlaces, 'SysUtils', 'System.SysUtils');
  if Plan.Needed and (Plan.Reason <> '') then
  begin
    AOutcome.Reason := 'System.SysUtils fehlt in uses: ' + Plan.Reason;
    AOutcome.Edits := nil;
    Exit(False);
  end;
  if Plan.Needed then
  begin
    SetLength(AOutcome.Edits, Length(AOutcome.Edits) + 1);
    AOutcome.Edits[High(AOutcome.Edits)] := Plan.Edit;
    AOutcome.Hint := AOutcome.Hint + ' + uses ' + Plan.Name;
  end;
end;

class function TRdxFixRunner.FreeAndNilFix(APlaces: TSourcePlaces;
  ALines: TStrings; ALine: Integer;
  const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  Map : TRdxCodeMap;
begin
  Result := Default(TRdxFixOutcome);
  if not Assigned(APlaces) or not APlaces.IsOpen or not Assigned(ALines) then
  begin
    Result.Reason := R_NO_FILE;
    Exit;
  end;
  Map := TRdxCodeMap.Create(ALines);
  try
    if not TRdxSimpleFixes.FreeAndNilFix(Map, ALine, Result.Edits,
         Result.Name, Result.Reason) then
      Exit;
    Result.Reason := VariableCheck(APlaces, Map, ALine, Result.Name);
  finally
    Map.Free;
  end;
  if Result.Reason <> '' then
  begin
    Result.Edits := nil;
    Exit;
  end;
  Result.Hint := Format(R_FREENIL_HINT, [Result.Name]);
  Result.Enabled := AppendSysUtils(APlaces, AUsesNames, Result);
end;

class function TRdxFixRunner.AssertMessageFix(APlaces: TSourcePlaces;
  ALines: TStrings; ALine: Integer; const AMessage: string): TRdxFixOutcome;
var
  Map : TRdxCodeMap;
begin
  Result := Default(TRdxFixOutcome);
  if not Assigned(APlaces) or not APlaces.IsOpen or not Assigned(ALines) then
  begin
    Result.Reason := R_NO_FILE;
    Exit;
  end;
  SetLength(Result.Edits, 1);
  Map := TRdxCodeMap.Create(ALines);
  try
    // Eine eigene Routine Assert (Methode oder global) bindet vor
    // System.Assert - ihre Parameter kennt hier niemand.
    if TRdxSimpleFixes.DeclaresRoutine(Map, 'Assert') then
      Result.Reason := 'die Unit deklariert eine eigene Routine Assert'
    else if TRdxSimpleFixes.WithBefore(Map, ALine)
            or APlaces.InWithBlock(ALine) then
      Result.Reason := 'with-Anweisung in der Routine - Assert koennte ein '
        + 'Member sein'
    else
      Result.Enabled := TRdxSimpleFixes.AssertMessage(Map, ALine, AMessage,
        Result.Edits[0], Result.Reason);
  finally
    Map.Free;
  end;
  if not Result.Enabled then
    Result.Edits := nil;
end;

class function TRdxFixRunner.EmptySectionFix(ALines: TStrings; ALine: Integer;
  const AMessage: string): TRdxFixOutcome;
begin
  Result := MapFix(ALines, ALine, AMessage, TRdxSimpleFixes.EmptySection);
end;

// X aus der SCA139-Meldung 'X.Free without subsequent X := nil - ...';
// '' ohne diese Form.
function FreeReceiverOf(const AMessage: string): string;
var
  P : Integer;
begin
  Result := '';
  P := Pos('.Free without', AMessage);
  if P > 1 then
    Result := Trim(Copy(AMessage, 1, P - 1));
end;

// SCA139: ruft 'X.Free' sicher TObject.Free? FreeAndNil(X) uebergeht eine
// eigene Methode Free - in einem record/object/interface dieser Unit oder
// in einer Klasse dieser Unit (etwa ein Pool, der zurueckgibt statt
// freizugeben). Typen aus anderen Units sieht das nicht; ein Record dort
// faellt in Delphi ab 10.4 als Fehler E2010 auf. '' oder der Grund.
function FreeMethodReason(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  ALine: Integer; const AName: string): string;
begin
  Result := '';
  if TRdxSimpleFixes.DeclaresValueType(AMap,
       APlaces.DeclaredTypeOf(ALine, AName)) then
    Result := Format('%s ist kein Objekt (record, object oder interface '
      + 'dieser Unit) - Free ist eine eigene Methode', [AName])
  else if TRdxSimpleFixes.DeclaresRoutine(AMap, 'Free') then
    Result := 'die Unit deklariert eine eigene Methode Free - FreeAndNil '
      + 'riefe sie nicht auf';
end;

class function TRdxFixRunner.FreeWithoutNilFix(APlaces: TSourcePlaces;
  ALines: TStrings; ALine: Integer; const AMessage: string;
  const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  Map : TRdxCodeMap;
begin
  Result := Default(TRdxFixOutcome);
  if not Assigned(APlaces) or not APlaces.IsOpen or not Assigned(ALines) then
  begin
    Result.Reason := R_NO_FILE;
    Exit;
  end;
  // X wie in der Meldung - auch fuer Menuetext und Grund, wenn der Planer
  // ablehnt; die Ersetzung schreibt X so, wie es im Quelltext steht.
  Result.Name := FreeReceiverOf(AMessage);
  SetLength(Result.Edits, 1);
  Map := TRdxCodeMap.Create(ALines);
  try
    if not TRdxSimpleFixes.FreeOnly(Map, ALine, Result.Name,
         Result.Edits[0], Result.Reason) then
    begin
      Result.Edits := nil;
      Exit;
    end;
    Result.Reason := VariableCheck(APlaces, Map, ALine, Result.Name);
    if Result.Reason = '' then
      Result.Reason := FreeMethodReason(APlaces, Map, ALine, Result.Name);
  finally
    Map.Free;
  end;
  if Result.Reason <> '' then
  begin
    Result.Edits := nil;
    Exit;
  end;
  Result.Hint := Format(R_FREENIL_HINT, [Result.Name]);
  Result.Enabled := AppendSysUtils(APlaces, AUsesNames, Result);
end;

// SCA066: die Namen um den Aufruf (TRdxCallEdit). Ein blosser Name mit
// deklariertem Typ ist eine Variable - mit () eine Prozedurvariable oder
// Methodenreferenz, die Delphi ohne () nicht ueberall aufruft. Links von
// ':=' entscheidet der Typ (Gegen-Review 2026-10-10, Korpus cnwizards:
// 'Proc := PrevNextProc()' mit prozeduralem Proc). Im with-Block kann ein
// Name an ein Member binden. '' oder der Grund.
function CallReason(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  ALine: Integer; const APlan: TRdxCallEdit): string;
var
  TypeLow : string;
begin
  Result := '';
  if (APlan.Callee = '') and (APlan.Target = '') then Exit;
  if TRdxSimpleFixes.WithBefore(AMap, ALine) or APlaces.InWithBlock(ALine) then
    Exit(Format(R_WITH_MEMBER, [APlan.Callee + APlan.Target]));
  if (APlan.Callee <> '')
     and (APlaces.DeclaredTypeOf(ALine, APlan.Callee) <> '') then
    Exit(Format('%s ist eine Variable (Prozedurtyp) - erst () ruft sie '
      + 'sicher auf', [APlan.Callee]));
  if APlan.Target = '' then Exit;
  TypeLow := APlaces.DeclaredTypeOf(ALine, APlan.Target);
  if TypeLow = '' then
    Result := Format('Typ von %s unbekannt - ist er prozedural, liest Delphi '
      + 'den Namen ohne () als Zeiger', [APlan.Target])
  else if TRdxExprFixes.ProceduralType(AMap, TypeLow) then
    Result := Format('%s hat einen Prozedurtyp (%s) - ohne () liest Delphi den '
      + 'Namen als Zeiger', [APlan.Target, TypeLow]);
end;

class function TRdxFixRunner.EmptyArgsFix(APlaces: TSourcePlaces;
  ALines: TStrings; ALine: Integer; const AMessage: string): TRdxFixOutcome;
var
  Map  : TRdxCodeMap;
  Plan : TRdxCallEdit;
begin
  Result := Default(TRdxFixOutcome);
  if not Assigned(APlaces) or not APlaces.IsOpen or not Assigned(ALines) then
    Result.Reason := R_NO_FILE
  else if TRdxRecipeRunner.SourceLooksFpcAware(APlaces) then
    Result.Reason := 'Datei mit FPC-Weiche oder FPC-Modus - in objfpc ruft '
      + 'erst Foo() eine Prozedurvariable auf';
  if Result.Reason <> '' then Exit;
  Map := TRdxCodeMap.Create(ALines);
  try
    if TRdxExprFixes.EmptyArgs(Map, ALine, AMessage, Plan, Result.Reason) then
      Result.Reason := CallReason(APlaces, Map, ALine, Plan)
    else if Result.Reason = '' then
      Result.Reason := R_NO_HELP;
  finally
    Map.Free;
  end;
  if Result.Reason <> '' then Exit;
  SetLength(Result.Edits, 1);
  Result.Edits[0] := Plan.Edit;
  Result.Enabled := True;
end;

// SCA084: X muss als Klasse, Interface oder Zeiger BEWIESEN sein - ein
// Funktionstyp riefe 'X <> nil' auf, Assigned(X) nicht. Eine Zulassungs-
// liste (Gegen-Review 2026-10-10: die Ausschlussliste liess Aliasse,
// generische und qualifizierte Funktionstypen durch); im Realwelt-Korpus
// meldet SCA084 nur vier Stellen. Derselbe Beweis wie SCA126
// (TRdxNilFix.NilOperandReason): PointerLikeType kennt seit E27 (Charge
// R10) auch die Klassen und Interfaces der Delphi-Quellen (uRdxRtlTypes) -
// GEWOLLT auch hier: 'Assigned(L) and (L <> nil)' mit 'L: TStringList'
// ist derselbe Fall wie bei SCA126, die Gefahr (ein Funktionstyp aus einer
// anderen Unit) dieselbe, also auch der Beweis. '' oder der Grund.
function AssignedNilReason(AMap: TRdxCodeMap;
  const AName, ATypeLow: string): string;
begin
  if TRdxSimpleFixes.DeclaresRoutine(AMap, 'Assigned') then
    Exit('die Unit deklariert eine eigene Routine Assigned');
  if ATypeLow = '' then
    Exit(Format('Typ von %s unbekannt - bei einem Funktionstyp ruft '
      + '"%s <> nil" ihn auf, Assigned() nicht', [AName, AName]));
  Result := TRdxNilFix.NilOperandRisk(AName, ATypeLow);
  if Result <> '' then Exit;
  if TRdxExprFixes.ProceduralType(AMap, ATypeLow) then
    Exit(Format(R_PROC_TYPE, [AName, AName]));
  if not TRdxExprFixes.PointerLikeType(AMap, ATypeLow) then
    Result := Format('%s: Typ %s ist in dieser Unit nicht als Klasse, '
      + 'Interface oder Zeiger bewiesen und keine Klasse der Delphi-Quellen '
      + '- ein Funktionstyp riefe "%s <> nil" auf', [AName, ATypeLow, AName]);
end;

// SCA072/SCA084: ist X an ALine sicher der Operand, fuer den die Umformung
// gilt (s. OperandFix)? '' oder der Grund.
function OperandReason(AKind: TFindingKind; APlaces: TSourcePlaces;
  AMap: TRdxCodeMap; ALine: Integer; const AName: string): string;
var
  TypeLow : string;
begin
  if TRdxSimpleFixes.WithBefore(AMap, ALine) or APlaces.InWithBlock(ALine) then
    Exit(Format(R_WITH_MEMBER, [AName]));
  TypeLow := APlaces.DeclaredTypeOf(ALine, AName);
  if AKind = fkRedundantBoolean then
  begin
    if TypeLow = 'boolean' then
      Exit('');
    if TypeLow = '' then
      TypeLow := 'unbekannt';
    Exit(Format('%s ist hier nicht als Boolean bewiesen (Typ: %s) - bei '
      + 'Variant oder LongBool ist "= True" nicht dasselbe', [AName, TypeLow]));
  end;
  Result := AssignedNilReason(AMap, AName, TypeLow);
end;

class function TRdxFixRunner.OperandFix(AKind: TFindingKind;
  APlaces: TSourcePlaces; ALines: TStrings; ALine: Integer;
  const AMessage: string): TRdxFixOutcome;
var
  Map  : TRdxCodeMap;
  Plan : TRdxOperandEdit;
  Ok   : Boolean;
begin
  Result := Default(TRdxFixOutcome);
  if not Assigned(APlaces) or not APlaces.IsOpen or not Assigned(ALines) then
  begin
    Result.Reason := R_NO_FILE;
    Exit;
  end;
  Map := TRdxCodeMap.Create(ALines);
  try
    if AKind = fkRedundantBoolean then
      Ok := TRdxExprFixes.RedundantBool(Map, ALine, AMessage, Plan,
        Result.Reason)
    else
      Ok := TRdxExprFixes.AssignedNil(Map, ALine, AMessage, Plan,
        Result.Reason);
    if Ok then
      Result.Reason := OperandReason(AKind, APlaces, Map, ALine, Plan.Name)
    else if Result.Reason = '' then
      Result.Reason := R_NO_HELP;
  finally
    Map.Free;
  end;
  if Result.Reason <> '' then Exit;
  Result.Name := Plan.Name;
  SetLength(Result.Edits, 1);
  Result.Edits[0] := Plan.Edit;
  Result.Hint := Plan.Edit.NewText;
  Result.Enabled := True;
end;

// SCA007: wird die Unit im AKTUELLEN Text doch benutzt? Der Fund kann
// aus einem aelteren Scan stammen (Gegen-Review 2026-10-10). Dieselben
// Spuren wie uUnusedUses: ein qualifizierter Bezug ('Classes.TList') und
// einer der bekannten Bezeichner der Unit als Code-Wort (KnownIdents, mit
// demselben Kurznamen-Rueckfall fuer RTL-Namespaces).
function UnitStillUsed(AMap: TRdxCodeMap; const AUnit: string): Boolean;
var
  Low, Short : string;
  Idents     : TArray<string>;
  T, N       : TRdxToken;
begin
  Result := False;
  Low := LowerCase(AUnit);
  Short := Copy(Low, LastDelimiter('.', Low) + 1, MaxInt);
  Idents := TUnusedUsesDetector.KnownIdents(Low);
  if (Length(Idents) = 0) and TUnusedUsesDetector.IstRtlNamespace(Low) then
    Idents := TUnusedUsesDetector.KnownIdents(Short);
  T := NextToken(AMap, 1, 1);
  while T.Low <> '' do
  begin
    N := After(AMap, T);
    if ((T.Low = Short) and (N.Low = '.'))
       or (IndexText(T.Low, Idents) >= 0) then
      Exit(True);
    T := N;
  end;
end;

// SCA007: die Klausel und der Eintrag zum Unit-Namen AUnit auf ALine.
// '' oder der Grund.
function FindUsesEntry(APlaces: TSourcePlaces; ALine: Integer;
  const AUnit: string; out AClause: TRdxUsesClause; out AIndex: Integer): string;
var
  Clauses : TArray<TArray<TRefactorSpan>>;
  c, k, n : Integer;
begin
  Result := '';
  AClause := Default(TRdxUsesClause);
  AIndex := -1;
  n := 0;
  Clauses := ClausesOf(APlaces);
  for c := 0 to High(Clauses) do
    for k := 0 to High(Clauses[c]) do
      if (Clauses[c][k].StartLine = ALine)
         and SameText(Clauses[c][k].Resolved, AUnit) then
      begin
        Inc(n);
        AClause.Entries := Clauses[c];
        AClause.UsesLine := UsesKeywordLine(APlaces, Clauses[c][0]);
        AIndex := k;
      end;
  if n = 0 then
    Result := Format('%s steht nicht mehr auf Zeile %d einer uses-Klausel - '
      + 'Zeile verschoben? Datei neu pruefen', [AUnit, ALine])
  else if n > 1 then
    Result := Format('%s steht mehrmals auf Zeile %d', [AUnit, ALine]);
end;

class function TRdxFixRunner.UnusedUsesFix(APlaces: TSourcePlaces;
  ALines: TStrings; ALine: Integer; const AUnit: string): TRdxFixOutcome;
var
  Map    : TRdxCodeMap;
  Clause : TRdxUsesClause;
  Index  : Integer;
begin
  Result := Default(TRdxFixOutcome);
  Result.Name := Trim(AUnit);
  Index := -1;
  if not Assigned(APlaces) or not APlaces.IsOpen or not Assigned(ALines) then
    Result.Reason := R_NO_FILE
  else if TRdxRecipeRunner.UsesDirectiveLine(APlaces) > 0 then
    Result.Reason := 'Direktive in einer uses-Klausel - ein Eintrag gilt evtl. '
      + 'nur in einem Zweig'
  else
    Result.Reason := FindUsesEntry(APlaces, ALine, Result.Name, Clause, Index);
  if Result.Reason <> '' then Exit;
  SetLength(Result.Edits, 1);
  Map := TRdxCodeMap.Create(ALines);
  try
    if UnitStillUsed(Map, Result.Name) then
      Result.Reason := Format('%s wird im Text benutzt - der Fund ist aelter '
        + 'als der Text; Datei neu pruefen', [Result.Name])
    else
      Result.Enabled := TRdxStructFixes.RemoveUsesEntry(Map, Clause, Index,
        Result.Edits[0], Result.Reason);
  finally
    Map.Free;
  end;
  if not Result.Enabled then
  begin
    Result.Edits := nil;
    Exit;
  end;
  // Der Detektor ist heuristisch (Bezeichnerliste je Unit): ein Typ, den
  // er nicht kennt (TDataModule, TStream ...), macht den Fund falsch.
  Result.Hint := Format('heuristischer Fund - danach kompilieren; hat %s einen '
    + 'initialization-Abschnitt (Registrierung), laeuft er nicht mehr',
    [Result.Name]);
end;

// Eingang eines Laeufers mit Quellstellen-Dienst: ohne offene Datei nil
// und R_NO_FILE in AOutcome.Reason; sonst die Code-Sicht (der Aufrufer gibt
// sie frei) und Platz fuer eine Ersetzung in AOutcome.Edits.
function OpenMapFor(APlaces: TSourcePlaces; ALines: TStrings;
  var AOutcome: TRdxFixOutcome): TRdxCodeMap;
begin
  Result := nil;
  if not Assigned(APlaces) or not APlaces.IsOpen or not Assigned(ALines) then
  begin
    AOutcome.Reason := R_NO_FILE;
    Exit;
  end;
  SetLength(AOutcome.Edits, 1);
  Result := TRdxCodeMap.Create(ALines);
end;

// SCA168: TRdxStructFixes.CaseElse mit AStatement ('' = leeres else).
function CaseElseOutcome(APlaces: TSourcePlaces; ALines: TStrings;
  ALine: Integer; const AStatement: string): TRdxFixOutcome;
var
  Map : TRdxCodeMap;
begin
  Result := Default(TRdxFixOutcome);
  Map := OpenMapFor(APlaces, ALines, Result);
  if Map = nil then Exit;
  try
    Result.Enabled := TRdxStructFixes.CaseElse(Map, ALine, AStatement,
      Result.Edits, Result.Reason);
  finally
    Map.Free;
  end;
  if not Result.Enabled then
    Result.Edits := nil;
end;

class function TRdxFixRunner.CaseElseFix(APlaces: TSourcePlaces;
  ALines: TStrings; ALine: Integer): TRdxFixOutcome;
begin
  Result := CaseElseOutcome(APlaces, ALines, ALine, '');
end;

class function TRdxFixRunner.CaseRaiseFix(APlaces: TSourcePlaces;
  ALines: TStrings; ALine: Integer;
  const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  if Assigned(APlaces) and APlaces.IsOpen
     and TRdxRecipeRunner.SourceLooksFpcAware(APlaces) then
  begin
    Result := Default(TRdxFixOutcome);
    Result.Reason := 'Datei mit FPC-Weiche oder FPC-Modus - FPC kennt '
      + 'EProgrammerError nicht';
  end
  else
    Result := CaseElseOutcome(APlaces, ALines, ALine, RAISE_UNHANDLED);
  Result.Variant := 1;
  Result.ChangesBehavior := True;
  if not Result.Enabled then Exit;
  Result.Hint := R_CASE_RAISE_HINT;
  Result.Enabled := AppendSysUtils(APlaces, AUsesNames, Result);
end;

class function TRdxFixRunner.BlockFix(AKind: TFindingKind; ALines: TStrings;
  ALine: Integer; const AMessage: string): TRdxFixOutcome;
var
  Map : TRdxCodeMap;
  Kw  : TRdxToken;
begin
  Result := Default(TRdxFixOutcome);
  if not Assigned(ALines) then
  begin
    Result.Reason := R_NO_FILE;
    Exit;
  end;
  Map := TRdxCodeMap.Create(ALines);
  try
    if AKind = fkIfElseBegin then
      Result.Enabled := TRdxStructFixes.ElseAfterEndOn(Map, ALine, Kw,
        Result.Reason)
    else
      Result.Enabled := TRdxStructFixes.BranchKeywordAt(Map, ALine,
        ColumnFromMessage(AMessage), Kw, Result.Reason);
    if Result.Enabled then
      Result.Enabled := TRdxStructFixes.WrapInBlock(Map, Kw, Result.Edits,
        Result.Reason);
  finally
    Map.Free;
  end;
  if not Result.Enabled then
    Result.Edits := nil;
end;

// SCA123: ist der Operand AOperand ein blosser Bezeichner, ausserhalb eines
// with-Blocks und als genau ATarget deklariert? '' oder der Grund.
function CastTypeReason(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  ALine: Integer; const AOperand, ATarget: string): string;
var
  Declared : string;
begin
  Result := '';
  if Pos('.', AOperand) > 0 then
    Exit(Format('%s ist kein blosser Bezeichner - sein Typ ist nicht '
      + 'pruefbar', [AOperand]));
  if TRdxSimpleFixes.WithBefore(AMap, ALine) or APlaces.InWithBlock(ALine) then
    Exit(Format(R_WITH_MEMBER, [AOperand]));
  Declared := APlaces.DeclaredTypeOf(ALine, AOperand);
  if Declared = '' then
    Result := Format('Typ von %s unbekannt - nur ein Cast auf den eigenen Typ '
      + 'ist beweisbar ohne Wirkung', [AOperand])
  else if not SameText(Declared, ATarget) then
    Result := Format('%s ist als %s deklariert, nicht als %s - ein anderer Typ '
      + 'kann Free verdecken, oder der Cast ist zum Uebersetzen noetig',
      [AOperand, Declared, ATarget]);
end;

// SCA123: 'TFoo(X).Free' -> 'X.Free' (TRdxLineFixes.CastFree) - nur, wenn
// X ein blosser Bezeichner ist, ausserhalb eines with-Blocks, und als
// genau TFoo deklariert (DeclaredTypeOf). Nur dann binden beide dasselbe
// Free: ein anderer Typ kann Free verdecken (dwsUtils:
// TRefCountedObject.Free zaehlt nur herunter), und ein Pointer-Operand
// braucht den Cast zum Uebersetzen (Gegen-Review Zeilen-Hilfen).
function CastFreeFix(APlaces: TSourcePlaces; ALines: TStrings;
  ALine: Integer; const AMessage: string): TRdxFixOutcome;
var
  Map : TRdxCodeMap;
begin
  Result := Default(TRdxFixOutcome);
  Result.Name := TRdxLineFixes.CastTargetOf(AMessage);
  Map := OpenMapFor(APlaces, ALines, Result);
  if Map = nil then Exit;
  try
    Result.Enabled := TRdxLineFixes.CastFree(Map, ALine, AMessage,
      Result.Edits[0], Result.Reason);
    if Result.Enabled then
      Result.Reason := CastTypeReason(APlaces, Map, ALine,
        Result.Edits[0].NewText, Result.Name);
  finally
    Map.Free;
  end;
  Result.Enabled := Result.Enabled and (Result.Reason = '');
  if Result.Enabled then
    Result.Hint := Format(R_CAST_HINT, [Result.Edits[0].NewText, Result.Name])
  else
    Result.Edits := nil;
end;

// SCA020, zweiter Eintrag: raise ENotImplemented im leeren Rumpf - aendert
// das Verhalten; SysUtils kommt bei Bedarf mit (FPC kennt ENotImplemented
// ebenfalls).
function EmptyRaiseFix(APlaces: TSourcePlaces; ALines: TStrings;
  ALine: Integer; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  Map : TRdxCodeMap;
begin
  Result := Default(TRdxFixOutcome);
  Map := OpenMapFor(APlaces, ALines, Result);
  if Map <> nil then
  try
    Result.Enabled := TRdxRaiseFixes.EmptyBody(Map, ALine,
      RAISE_NOT_IMPLEMENTED, Result.Edits[0], Result.Reason);
  finally
    Map.Free;
  end;
  Result.Variant := 1;
  Result.ChangesBehavior := True;
  if not Result.Enabled then
  begin
    Result.Edits := nil;
    Exit;
  end;
  Result.Hint := R_EMPTY_RAISE_HINT;
  Result.Enabled := AppendSysUtils(APlaces, AUsesNames, Result);
end;

// SCA098: X muss als Boolean BEWIESEN sein - bei Variant bekaeme X den
// Wert der Bedingung statt True/False (wie SCA072: Variant/LongBool sind
// nicht dasselbe). In der Gegenrichtung muss auch C Boolean sein: der Form
// nach (Vergleiche, and/or/xor/not daraus, TRdxFlowPlan.CondBoolean) und
// jeder blosse Bezeichner darin als Boolean deklariert - bei einem Variant
// waere 'not' bitweise ('not 1' ist wieder wahr). Im with-Block kann ein
// Name ein Member sein. '' oder der Grund.
function CondAssignReason(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  ALine: Integer; const APlan: TRdxFlowPlan): string;
var
  TypeLow, Ident : string;
begin
  Result := '';
  if TRdxSimpleFixes.WithBefore(AMap, ALine) or APlaces.InWithBlock(ALine) then
    Exit(Format(R_WITH_MEMBER, [APlan.Target]));
  TypeLow := APlaces.DeclaredTypeOf(ALine, APlan.Target);
  if TypeLow <> 'boolean' then
  begin
    if TypeLow = '' then
      TypeLow := 'unbekannt';
    Exit(Format('%s ist hier nicht als Boolean bewiesen (Typ: %s) - bei '
      + 'Variant bekaeme %s den Wert der Bedingung statt True/False',
      [APlan.Target, TypeLow, APlan.Target]));
  end;
  if not APlan.Negated then Exit;
  if not APlan.CondBoolean then
    Exit('die Bedingung ist nicht als Boolean bewiesen (ein Aufruf, ein Pfad '
      + 'oder Arithmetik als Operand) - bei einem Variant waere "not" bitweise');
  for Ident in APlan.CondIdents do
    if APlaces.DeclaredTypeOf(ALine, Ident) <> 'boolean' then
      Exit(Format('%s in der Bedingung ist hier nicht als Boolean bewiesen - '
        + 'bei einem Variant waere "not" bitweise', [Ident]));
end;

// SCA047: ist das Ziel ein Speicherplatz? Der Detektor hat es aufgeloest;
// hier am aktuellen Text: kein with-Block (der Name koennte ein Member mit
// Setter sein), kein Pfadteil als Property der Unit deklariert, die Wurzel
// ('Pt' in 'Pt.Y', ohne 'Self.') als Variable bekannt (DeclaredTypeOf oder
// Inline-Variable). '' oder der Grund.
function SelfAssignReason(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  ALine: Integer; const ATarget: string): string;
var
  Parts : TArray<string>;
  Root  : string;
  i     : Integer;
begin
  Result := '';
  if TRdxSimpleFixes.WithBefore(AMap, ALine) or APlaces.InWithBlock(ALine) then
    Exit(Format(R_WITH_MEMBER, [ATarget]));
  Parts := StringReplace(ATarget, '^', '', [rfReplaceAll]).Split(['.']);
  if Length(Parts) = 0 then
    Exit('Ziel fehlt');
  for i := 0 to High(Parts) do
    if TRdxSimpleFixes.DeclaresProperty(AMap, Trim(Parts[i])) then
      Exit(Format('%s ist in dieser Unit als Property deklariert - die '
        + 'Zuweisung ruft vielleicht einen Setter', [Trim(Parts[i])]));
  Root := Trim(Parts[0]);
  if SameText(Root, 'Self') and (Length(Parts) > 1) then
    Root := Trim(Parts[1]);
  if (APlaces.DeclaredTypeOf(ALine, Root) = '')
     and not TRdxSimpleFixes.DeclaresInlineVar(AMap, ALine, Root) then
    Result := Format('%s ist hier nicht als Variable bekannt (Property oder '
      + 'Feld aus einer anderen Unit?)', [Root]);
end;

// SCA098, SCA080, SCA047 (Charge H2): der Planer auf den Zeilen, danach die
// Pruefung mit dem Quellstellen-Dienst. Alle drei bedeutungsgleich - den
// Hinweis setzt die Tabelle.
function FlowFix(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; APlan: TRdxFlowPlanner;
  AReason: TRdxFlowReason): TRdxFixOutcome;
var
  Map  : TRdxCodeMap;
  Plan : TRdxFlowPlan;
begin
  Result := Default(TRdxFixOutcome);
  Map := OpenMapFor(APlaces, ALines, Result);
  if Map = nil then Exit;
  try
    Result.Enabled := APlan(Map, AFinding.LineInt, AFinding.Message, Plan,
      Result.Reason);
    Result.Name := Plan.Target;
    if Result.Enabled and Assigned(AReason) then
      Result.Reason := AReason(APlaces, Map, AFinding.LineInt, Plan);
  finally
    Map.Free;
  end;
  Result.Enabled := Result.Enabled and (Result.Reason = '');
  if not Result.Enabled then
  begin
    Result.Edits := nil;
    Exit;
  end;
  Result.Edits[0] := Plan.Edit;
end;

// Der Text, auf dem uNilComparison den Knoten zaehlt (Analyse
// editorhilfen-2a, Tabelle der Knoten): Aufrufe tragen ihn im Namen,
// raise in beiden Feldern, alle anderen Anweisungen in TypeRef.
function NilTextOf(const ANode: TNodeRef): string;
begin
  case ANode.Kind of
    TNodeKind.nkCall, TNodeKind.nkInherited:
      Result := ANode.Name;
    TNodeKind.nkRaise:
      Result := ANode.Name + ' ' + ANode.TypeRef;
  else
    Result := ANode.TypeRef;
  end;
end;

// Die EINE Anweisung auf ALine mit einem nil-Vergleich als SCA126-Stelle.
// '' oder der Grund (keine, mehrdeutig).
function PickNilSite(APlaces: TSourcePlaces; ALine: Integer;
  out ASite: TRdxNilSite): string;
var
  Nodes : TArray<TNodeRef>;
  N     : TNodeRef;
  Hits  : Integer;
begin
  Result := '';
  ASite := Default(TRdxNilSite);
  Nodes := APlaces.NodesAt(ALine, [TNodeKind.nkIfStmt, TNodeKind.nkWhileStmt,
    TNodeKind.nkCaseStmt, TNodeKind.nkAssign, TNodeKind.nkCall,
    TNodeKind.nkExit, TNodeKind.nkInherited, TNodeKind.nkRaise]);
  Hits := 0;
  for N in Nodes do
    if TRdxNilFix.CountNilComparisons(NilTextOf(N)) > 0 then
    begin
      Inc(Hits);
      ASite.Line     := N.Line;
      ASite.Col      := N.Col;
      ASite.NodeText := NilTextOf(N);
      if N.Kind in [TNodeKind.nkIfStmt, TNodeKind.nkWhileStmt,
         TNodeKind.nkCaseStmt] then
        ASite.Anchor := naCondition
      else
        ASite.Anchor := naStatement;
    end;
  if Hits = 0 then
    Result := Format('keine Anweisung mit nil-Vergleich beginnt auf Zeile %d',
      [ALine])
  else if Hits > 1 then
    Result := Format('Zeile %d ist mehrdeutig (%d Anweisungen mit nil-Vergleich)',
      [ALine, Hits]);
end;

// SCA126, je Operand des Plans: nur ein blosser Bezeichner hat einen
// deklarierten Typ (DeclaredTypeOf) - OHNE beweisbaren Typ (geerbt aus
// einer anderen Unit, Vorfahr von ausserhalb) sperrt er: als Funktions-
// oder Methodenzeiger ruft '= nil' ihn auf, Assigned() nicht - lieber
// keine Hilfe als eine falsche (Review reDelphiX nach Bereichen 2026-10-10,
// Minor 6). Alles Weitere - Ereignis-/Getter-Namen, riskante Typnamen,
// Prozedurtypen DIESER Unit und Pfade ohne bewiesenes Feld - prueft
// TRdxNilFix.NilOperandReason auf der Code-Sicht (Review Quick-Fix-Units
// 2026-10-14, Blocker SCA126). '' oder der Grund.
function NilOperandsReason(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  ALine: Integer; const APlan: TRdxNilPlan): string;
var
  TypeLow : string;
  i       : Integer;
begin
  Result := '';
  for i := 0 to High(APlan.Operands) do
  begin
    TypeLow := '';
    if TRdxRecipes.IsPlainIdent(APlan.Operands[i]) then
    begin
      TypeLow := APlaces.DeclaredTypeOf(ALine, APlan.Operands[i]);
      if TypeLow = '' then
        Exit(Format(R_NIL_TYPE_UNKNOWN, [APlan.Operands[i]]));
    end;
    Result := TRdxNilFix.NilOperandReason(AMap, APlan.Operands[i], TypeLow);
    if Result <> '' then Exit;
  end;
end;

// Der Hint der SCA126-Hilfe: die neuen Ausdruecke, mit ', ' verbunden.
function NilHintOf(const APlan: TRdxNilPlan): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(APlan.Edits) do
    begin
      if i > 0 then SB.Append(', ');
      SB.Append(APlan.Edits[i].NewText);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TRdxFixRunner.NilComparisonFix(APlaces: TSourcePlaces;
  ALines: TStrings; ALine: Integer): TRdxFixOutcome;
var
  Site : TRdxNilSite;
  Map  : TRdxCodeMap;
  Plan : TRdxNilPlan;
begin
  Result := Default(TRdxFixOutcome);
  if not Assigned(APlaces) or not APlaces.IsOpen or not Assigned(ALines) then
  begin
    Result.Reason := R_NO_FILE;
    Exit;
  end;
  Result.Reason := PickNilSite(APlaces, ALine, Site);
  if Result.Reason <> '' then Exit;
  Map := TRdxCodeMap.Create(ALines);
  try
    // Im with-Block kann ein Operand an ein Member des with-Ausdrucks
    // binden (ein Funktionszeiger: '= nil' ruft ihn auf) - der deklarierte
    // Typ beweist dort nichts. Dieselbe Sperre wie SCA085 (VariableCheck;
    // Gegen-Review nach Bereichen 2026-10-10).
    if APlaces.InWithBlock(Site.Line)
       or TRdxSimpleFixes.WithBefore(Map, Site.Line) then
    begin
      Result.Reason := R_NIL_IN_WITH;
      Exit;
    end;
    if not TRdxNilFix.NilComparison(Map, Site, Plan) then
    begin
      Result.Reason := Plan.Reason;
      Exit;
    end;
    Result.Reason := NilOperandsReason(APlaces, Map, Site.Line, Plan);
  finally
    Map.Free;
  end;
  if Result.Reason <> '' then Exit;
  Result.Hint    := NilHintOf(Plan);
  Result.Edits   := Plan.Edits;
  Result.Enabled := True;
end;

{ ---- uses-Eintraege qualifizieren (QualifyUses) ---- }

type
  // Was QualifyUses je Klausel braucht (QualifyClause): die Scope-Tabelle,
  // das Rahmenwerk der Datei, die gefragte Zeile und die Pruefung auf eine
  // eigene Unit des Projekts.
  TRdxQualifyCtx = record
    Scopes    : TRdxScopeTable;
    Fw        : TRdxFramework;
    Line      : Integer;
    IsOwnUnit : TRdxOwnUnitCheck;
  end;

const
  // So viele Ziele nennt die Vorschau von 'alle qualifizieren'.
  MAX_QUALIFY_PREVIEW = 3;

// Die aufgeloesten Namen der Eintraege einer Klausel.
function ClauseNames(const AEntries: TArray<TRefactorSpan>): TArray<string>;
var
  i : Integer;
begin
  SetLength(Result, Length(AEntries));
  for i := 0 to High(AEntries) do
    Result[i] := AEntries[i].Resolved;
end;

// Ein Eintrag als TRdxQualifyItem: Why und Edit nach Scope-Tabelle und
// eigener Unit (qwOk mit Edit, wenn die Tabelle ihn eindeutig aufloest).
// False fuer einen leeren oder schon qualifizierten Eintrag - kein Item.
function QualifyItemOf(const ACtx: TRdxQualifyCtx; const AEntry: TRefactorSpan;
  out AItem: TRdxQualifyItem): Boolean;
var
  Q, Reason : string;
begin
  AItem := Default(TRdxQualifyItem);
  AItem.Short := AEntry.Resolved;
  Result := (AItem.Short <> '') and (Pos('.', AItem.Short) = 0);
  if not Result then Exit;
  if not ACtx.Scopes.Resolve(AItem.Short, ACtx.Fw, Q, Reason) then
  begin
    AItem.Why := qwScopeTable;
    AItem.ScopeReason := Reason;
  end
  else if Assigned(ACtx.IsOwnUnit) and ACtx.IsOwnUnit(AItem.Short) then
    AItem.Why := qwOwnUnit
  else
  begin
    AItem.Qualified     := Q;
    AItem.Edit.Span     := AEntry;
    AItem.Edit.Expected := AItem.Short;
    AItem.Edit.NewText  := Q;
  end;
end;

// Bleibt die sortierte Klausel ANames sortiert, wenn der Eintrag AIndex zu
// AQualified wird? Dieselbe Regel wie uUnsortedUses (SCA142):
// TRdxRecipes.IsSortedUses.
function StaysSorted(const ANames: TArray<string>; AIndex: Integer;
  const AQualified: string): Boolean;
var
  Single : TArray<string>;
begin
  Single := Copy(ANames);
  Single[AIndex] := AQualified;
  Result := TRdxRecipes.IsSortedUses(Single);
end;

// Die Ersetzung AEdit zu 'alle qualifizieren' und ihr Ziel in die Vorschau
// (die ersten MAX_QUALIFY_PREVIEW).
procedure TakeIntoAll(var APlan: TRdxQualifyPlan; const AEdit: TRdxEdit);
begin
  SetLength(APlan.All, Length(APlan.All) + 1);
  APlan.All[High(APlan.All)] := AEdit;
  if Length(APlan.All) > MAX_QUALIFY_PREVIEW then Exit;
  if APlan.AllPreview <> '' then
    APlan.AllPreview := APlan.AllPreview + ', ';
  APlan.AllPreview := APlan.AllPreview + AEdit.NewText;
end;

// EINE Klausel: Items der gefragten Zeile, 'alle qualifizieren' (All,
// Vorschau) und ob das eine sortierte Klausel unsortiert machte. Bis Charge
// R8 der Rumpf der Schleife in QualifyUses (SCA176 46).
procedure QualifyClause(const ACtx: TRdxQualifyCtx;
  const AEntries: TArray<TRefactorSpan>; var APlan: TRdxQualifyPlan);
var
  Names, AllNames : TArray<string>;
  Sorted          : Boolean;
  i               : Integer;
  Item            : TRdxQualifyItem;
begin
  Names := ClauseNames(AEntries);
  Sorted := TRdxRecipes.IsSortedUses(Names);
  AllNames := Copy(Names);
  for i := 0 to High(AEntries) do
  begin
    if not QualifyItemOf(ACtx, AEntries[i], Item) then Continue;
    if Item.Why = qwOk then
    begin
      AllNames[i] := Item.Qualified;
      TakeIntoAll(APlan, Item.Edit);
      // Eine sortierte Klausel bleibt sortiert, sonst kein Angebot - der
      // Klick erzeugte einen neuen SCA142-Fund (Minor 14).
      if Sorted and not StaysSorted(Names, i, Item.Qualified) then
        Item.Why := qwUnsorts;
    end;
    if AEntries[i].StartLine = ACtx.Line then
    begin
      SetLength(APlan.Items, Length(APlan.Items) + 1);
      APlan.Items[High(APlan.Items)] := Item;
    end;
  end;
  if Sorted and not TRdxRecipes.IsSortedUses(AllNames) then
    APlan.AllUnsorts := True;
end;

class function TRdxRecipeRunner.QualifyUses(APlaces: TSourcePlaces;
  AScopes: TRdxScopeTable; ALine: Integer;
  const AIsOwnUnit: TRdxOwnUnitCheck): TRdxQualifyPlan;
var
  Clauses : TArray<TArray<TRefactorSpan>>;
  Ctx     : TRdxQualifyCtx;
  c       : Integer;
begin
  Result := Default(TRdxQualifyPlan);
  if not LineInUsesClause(APlaces, ALine) then Exit;
  Result.InClause := True;
  if (AScopes = nil) or (AScopes.Count = 0) then
  begin
    Result.Block := qbNoTable;
    Exit;
  end;
  // Direktiven in einer Klausel: ein Eintrag kann in einem Zweig fuer ein
  // anderes Ziel stehen - qualifiziert uebersetzte FPC ihn nicht mehr
  // (Review Major 7; dieselbe Sperre wie PlanUses).
  Result.BlockLine := UsesDirectiveLine(APlaces);
  if Result.BlockLine > 0 then
  begin
    Result.Block := qbDirectives;
    Exit;
  end;
  // Eine FPC-Weiche oder ein FPC-Modus irgendwo in der Datei (Minor 12):
  // die Quelle wird auch mit FPC 3.2 uebersetzt, und der kennt keine
  // Unit-Scopes. PlanUses haelt dort die Kurznamen (Minor 35).
  if SourceLooksFpcAware(APlaces) then
  begin
    Result.Block := qbFpcSwitch;
    Exit;
  end;
  Ctx.Scopes    := AScopes;
  Ctx.Fw        := TRdxRecipes.DetectFramework(UsesNamesOf(APlaces));
  Ctx.Line      := ALine;
  Ctx.IsOwnUnit := AIsOwnUnit;
  Clauses := ClausesOf(APlaces);
  for c := 0 to High(Clauses) do
    QualifyClause(Ctx, Clauses[c], Result);
  if Length(Result.All) > MAX_QUALIFY_PREVIEW then
    Result.AllPreview := Result.AllPreview + ', ...';
end;

end.
