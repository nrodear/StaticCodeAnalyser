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
//
// Die Ruempfe der einfachen Hilfen der Tabelle uRdxFixTable (TRdxFixRunner,
// MapFix, AppendUses ...) stehen seit Charge B2S-b in uRdxFixRunner
// (Review R6-12); hier bleiben SCA044, SCA003 und die uses-Klauseln samt
// den Ergebnistypen, die beide teilen (TRdxFixOutcome, TRdxUsesPlan).

interface

uses
  System.Classes, System.Generics.Collections,
  uEngineApi, uRefactorInfo, uFindingActions, uRdxRecipes,
  uMethodd12,       // TLeakFinding
  uRdxScopeTable,   // TRdxScopeTable (QualifyUses)
  uRdxBufferMath;   // TRdxEdit

const
  // So viele Provide-Chargen haelt der Anbieter am Leben: ein Menue fragt
  // hoechstens MAX_FINDINGS_PER_MENU Funde (Vertrag uFindingActions), dazu
  // reichlich Reserve fuer Abfragen zwischen Aufbau und Klick (Gluehbirne
  // im Hintergrund). Review reDelphiX 2026-10-07, Blocker 2.
  RDX_ACTION_BATCHES = 8 * MAX_FINDINGS_PER_MENU;
  // Der Grund ohne offene Datei ist seit E29 (C-Gruppen G6/G7)
  // uRdxText.MsgNoFileOpen - bis dahin hier R_NO_FILE.

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

  // Ergebnis einer einfachen Hilfe (TRdxFixRunner, Planer der Tabelle
  // uRdxFixTable): die Ersetzungen fuer EINEN Undo-Schritt und ein Hinweis
  // fuers Menue - oder der Grund, warum es keine Hilfe gibt.
  TRdxFixOutcome = record
    Enabled : Boolean;
    Edits   : TArray<TRdxEdit>;
    // Was fuer '%s' im Menuetext der Zeile steht (uRdxFixTable,
    // FIX_CAPTIONS - die Liste je Art dort): X bei SCA085 (wie im Puffer)
    // und SCA139 (wie in der Meldung), die Unit, der Cast-Typ, die
    // Direktive, Routine, Variable, Sperre, der Wert, die Zahl ... - auch,
    // wenn abgelehnt wird, soweit der Planer ihn schon kennt.
    Name    : string;
    Hint    : string;    // bei Enabled = True
    Reason  : string;    // bei Enabled = False
    // 0 = die Hilfe (FixFor), 1 = der zweite Eintrag (AlternativeFixFor:
    // SCA168 else mit raise, SCA020 raise ENotImplemented).
    Variant : Integer;
    // Entscheid E2 (Konzept Editorhilfen): der Menuetext traegt die
    // Kennzeichnung (msgid '(changes behavior)', uRdxFixTable.CAP_CHANGES).
    // Gesetzt von der Zeile (FIX_ROWS.Changes: fest bei SCA007, SCA120,
    // SCA009/SCA001/SCA109/SCA153/SCA156, SCA121, SCA196) oder vom Planer
    // je nach Fund (SCA149 override, SCA096/SCA097, die zweiten Eintraege
    // von SCA168 und SCA020 mit raise). Massgeblich ist FIX_ROWS - diese
    // Aufzaehlung ist nur die Uebersicht (Stand Charge FB).
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

  // Was TRdxRecipeRunner.SqlTemplate liefert: die Vorlage und den Hinweis
  // fuers Menue, sonst den Grund (Charge SQc: ein Ergebnis statt drei
  // out-Parameter, SCA013).
  TRdxSqlOffer = record
    Template : string;
    Hint     : string;
    Reason   : string;
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

    // Rezept 5.2: parametrisierte Vorlage (nur Text; uRdxSqlTemplate),
    // eingerueckt wie die Anweisung (Tabs bleiben, Minor 31). Die Fakten
    // (Konstanten, FireDAC-/ADO-Objekt, Kette Q.SQL.Add) sammelt
    // AddSqlFacts auf ALines, dem Text von APlaces (Gegen-Review S1, Minor
    // 8: bis dahin eine zweite Kopie); im with-Block ist nichts bewiesen.
    class function SqlTemplate(APlaces: TSourcePlaces; ALines: TStrings;
      AInfo: TRefactorInfo; AIsCall: Boolean; out AOffer: TRdxSqlOffer): Boolean; static;
  end;

// Die uses-Klauseln der Datei, je Klausel ihre Eintraege (interface und
// implementation; ohne beide die Klausel der Programmdatei), leere fehlen.
// Seit Charge B2S-b oeffentlich: TRdxFixRunner.UnusedUsesFix (SCA007,
// uRdxFixRunner) sucht darin den Eintrag des Funds.
function ClausesOf(APlaces: TSourcePlaces): TArray<TArray<TRefactorSpan>>;
// Die Zeile des Schluesselworts 'uses' der Klausel mit dem ersten
// Eintrag AFirst. Seit Charge B2S-b oeffentlich (wie ClausesOf).
function UsesKeywordLine(APlaces: TSourcePlaces;
  const AFirst: TRefactorSpan): Integer;

implementation

uses
  System.SysUtils,
  uSCAConsts,        // fkConcatToFormat, fkSQLInjection (QueryOf)
  uRdxCodeMap,       // TRdxCodeMap (SqlRequestOf)
  // Rezept 5.2 (Charge S1): BuildSqlTemplate, AddSqlFacts - nur hier
  // gebraucht, nicht in der Schnittstelle (Gegen-Review S1, Minor 7).
  uRdxSqlTemplate,
  uRdxSqlFacts,      // AddSqlFacts (seit Review Woche G01-03 eigene Unit)
  uSourcePlaces,     // SOURCE_PLACES_VERSION (Vertragspruefung unten)
  uRdxText;          // _, MsgNoFileOpen, MsgMovedSuffix (E29)

// Dieser Laeufer ist gegen Version 1 des Quellstellen-Vertrags geschrieben
// (uSourcePlaces, Abschnitt VERTRAGSVERSION). Steigt die Version, bricht
// der Bau hier ab, statt still gegen geaenderte Signaturen, Rollen,
// Koordinaten oder eine schwaechere Typableitung zu laufen. Eine zur
// Laufzeit getauschte BPL erkennt das nicht - das leistet die Paket-
// bindung (Review reDelphiX 2026-10-07, Nit 27). Die Ruempfe der
// einfachen Hilfen (seit Charge B2S-b in uRdxFixRunner, dort die meisten
// Typ- und with-Fragen an den Vertrag) pruefen dasselbe in ihrer Unit,
// mit deren Namen in der Meldung (Gegenpruefung V-B2S-5).
{$IF SOURCE_PLACES_VERSION <> 1}
  {$MESSAGE ERROR 'reDelphix: SOURCE_PLACES_VERSION hat sich geaendert - Vertrag in uSourcePlaces (VERTRAGSVERSION) pruefen, uRdxRecipeRunner anpassen'}
{$IFEND}

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
    AWhy := _('no statement found on line %d', [AQuery.Line])
  else if Length(Nodes) > 1 then
    AWhy := _('line %d is ambiguous (%d statements)',
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
      Exit(MsgMovedSuffix(_('line %d carries %s, the finding names %s',
        [AQuery.Line, NodeKey, AQuery.Target])));
  end;
  if (AQuery.Plus < 0) or (ANode.Kind <> TNodeKind.nkAssign) then Exit;
  Plus := TRdxRecipes.TopLevelPlusCount(ANode.TypeRef);
  // Eigener Satz statt MsgMovedSuffix: die Zeile ist veraendert, nicht
  // verschoben (Variante, c_groups 3 - der Wortlaut bleibt).
  if Plus <> AQuery.Plus then
    Result := _('chain on line %d has %d x ''+'', the finding names %d - '
      + 'line changed? Analyse the file again',
      [AQuery.Line, Plus, AQuery.Plus]);
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
        AWhy := _('chain on line %d: the source text splits differently '
          + 'than the parser sees it (%d x ''+'')', [ANode.Line, Plus]);
      Probe.Free;
    end;
  end
  else
    Result := APlaces.CallOf(ANode.Line, ANode.Col,
      TRdxRecipeRunner.HeadOf(ANode.Name));
  if Result = nil then
    Result := APlaces.StatementAt(ANode.Line, ANode.Col);
  if (Result = nil) and (AWhy = '') then
    AWhy := _('the statement cannot be described');
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
    AWhy := MsgNoFileOpen;
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
  // Der Hinweis eines aktiven Format-Eintrags (FormatHintOf), msgids (E29):
  // ein Satz je Form - Termzahl mit bzw. ohne Ziel des Selbst-Anhaengens,
  // die Herkunft der Argumente als %s darin, die numerischen als Satzende
  // um den ganzen Hinweis. Deutsch bisher '3 Terme hinter S, alle
  // bewiesen, 1 numerisch (%d/%u)'.
  HINT_TERMS        = '%d terms, %s';
  HINT_TERMS_BEHIND = '%d terms behind %s, %s';
  HINT_ALL_PROVEN   = 'all proven';
  HINT_BY_COMPILER  = '%d according to the compiler (%s)';
  HINT_NUMERIC      = '%s, %d numeric (%%d/%%u)';
  // Ohne Beschreibung der Stelle (NoInfoReason, SqlTemplate).
  R_NO_INFO = 'no description';

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
// das Ziel (ABehind, sonst ''), Herkunft der Argumente. Die Teile sind
// uebersetzte ganze Saetze, verbunden ueber %s (HINT_*) - Namen und Ziel
// stehen als Format-Argumente darin, ein '%' in ihnen bleibt Text. Head
// statt Result als Argument: Format schreibt in das Ziel der Zuweisung,
// das Argument darf nicht dieselbe Variable sein.
function FormatHintOf(const ABuild: TRdxFormatBuild; ATerms: Integer;
  const ABehind: string): string;
var
  Origin, Head : string;
begin
  if Length(ABuild.ByCompiler) = 0 then
    Origin := _(HINT_ALL_PROVEN)
  else
    Origin := _(HINT_BY_COMPILER, [Length(ABuild.ByCompiler),
      ByCompilerNames(ABuild.ByCompiler)]);
  if ABehind = '' then
    Head := _(HINT_TERMS, [ATerms, Origin])
  else
    Head := _(HINT_TERMS_BEHIND, [ATerms, ABehind, Origin]);
  if ABuild.Numeric > 0 then
    Result := _(HINT_NUMERIC, [Head, ABuild.Numeric])
  else
    Result := Head;
end;

// Ohne Beschreibung: der Grund aus Describe, sonst R_NO_INFO.
function NoInfoReason(const AWhy: string): string;
begin
  Result := AWhy;
  if Result = '' then
    Result := _(R_NO_INFO);
end;

// Keine Zuweisung mit Kette - dazu der Grund aus Describe, wenn er neben
// einer Beschreibung steht (die Kette passte nicht).
function NoChainReason(const AWhy: string): string;
begin
  if AWhy = '' then
    Result := _('no assignment with a chain')
  else
    Result := _('no assignment with a chain: %s', [AWhy]);
end;

// Selbst-Anhaengen 'X := X + ...' (ein Drittel der Korpus-Stellen): der
// erste Operand ist das Ziel.
function IsSelfAppend(const AParts: TRdxParts; AInfo: TRefactorInfo;
  ALast: Integer): Boolean;
begin
  Result := (ALast >= 3) and (AInfo.Parts[1].Role = ROLE_OPERAND)
    and SameOperandText(AParts[1].Text, AParts[0].Text);
end;

// Wo die Terme fuer BuildFormatCall in der Kette stehen: beim Selbst-
// Anhaengen hinter 'X +' - X ist der Kettenanfang, ein String, und ein
// Zeiger dahinter verkettet (Nachpruefung FB zu R2-04: 'X := X + P + N'
// lehnte bis dahin als "Zeiger am Kettenanfang" ab); sonst am Anfang.
function ChainStartOf(const AOutcome: TRdxFormatOutcome): TRdxChainStart;
begin
  if AOutcome.SelfAppend then
    Result := csBehindTarget
  else
    Result := csChainHead;
end;

// Der Grund, wenn BuildFormatCall ablehnt: hinter 'X +' nur Literale heisst
// anders als 'kein Operand'. Entschieden an der Kennung NoOperand - bis E29
// per Pos('kein Operand', Reason), das fiele mit dem uebersetzten Grund in
// en/fr still aus (c_groups 2.6).
function BuildReasonOf(const ABuild: TRdxFormatBuild;
  const ABehind: string): string;
begin
  Result := ABuild.Reason;
  if (ABehind <> '') and ABuild.NoOperand then
    Result := _('there are only literals behind %s', [ABehind]);
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
    Exit(_('%s is missing in uses: %s', ['System.SysUtils', Plan.Reason]));
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
    Result.Reason := _('target ''%s'' is %s - Format returns UnicodeString',
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
    Result.Reason := _('range not readable');
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
    Result.Reason := _('comment in the range');
    Exit;
  end;
  Behind := '';
  if Result.SelfAppend then
    Behind := TRdxRecipes.CollapseWhitespace(Parts[0].Text);
  if not TRdxRecipes.BuildFormatCall(Copy(Parts, First, Last - First + 1),
       Build, TType, ChainStartOf(Result)) then
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
    // Dieselbe msgid wie der Sperrgrund 'uses qualifizieren' des Anbieters
    // (uRdxProvider) - derselbe Satz, schon in de.po/fr.po.
    APlan.Reason := _('uses clause contains compiler directives (line %d)',
      [i]);
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
    APlan.Reason := _('uses entry in line %d not readable', [E.StartLine]);
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
    APlan.Reason := _('no uses clause and no interface/implementation');
    Exit;
  end;
  Text := APlaces.LineText(Line);
  if Trim(Text) = '' then
  begin
    APlan.Reason := _('line %d of the section not readable', [Line]);
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
    Result.Reason := MsgNoFileOpen;
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

// Die Anfrage an BuildSqlTemplate: Ziel, Teile mit ihren Zeilen, with-
// Block, uses-Namen, Einrueckung - und die Fakten am Puffertext ALines.
function SqlRequestOf(APlaces: TSourcePlaces; ALines: TStrings;
  AInfo: TRefactorInfo; const AParts: TRdxParts;
  AIsCall: Boolean): TRdxSqlRequest;
var
  i   : Integer;
  Map : TRdxCodeMap;
begin
  Result := Default(TRdxSqlRequest);
  Result.Target := AParts[0].Text;
  Result.IsCall := AIsCall;
  Result.Parts  := AParts;
  // Einrueckung wie vor der Anweisung - Tabs bleiben Tabs (Minor 31).
  Result.Indent := TRdxRecipes.IndentTextOf(Copy(
    APlaces.LineText(AInfo.Span.StartLine), 1, AInfo.InsertIndent));
  SetLength(Result.PartLines, Length(AInfo.Parts));
  for i := 0 to High(AInfo.Parts) do
    Result.PartLines[i] := AInfo.Parts[i].StartLine;
  Result.InWith    := APlaces.InWithBlock(AInfo.Span.StartLine);
  Result.UsesNames := TRdxRecipeRunner.UsesNamesOf(APlaces);
  Map := TRdxCodeMap.Create(ALines);
  try
    AddSqlFacts(Map, Result);
  finally
    Map.Free;
  end;
end;

class function TRdxRecipeRunner.SqlTemplate(APlaces: TSourcePlaces;
  ALines: TStrings; AInfo: TRefactorInfo; AIsCall: Boolean;
  out AOffer: TRdxSqlOffer): Boolean;
var
  Parts : TRdxParts;
  Built : TRdxSqlTemplate;
begin
  Result := False;
  AOffer := Default(TRdxSqlOffer);
  if (AInfo = nil) or (ALines = nil) then
  begin
    AOffer.Reason := _(R_NO_INFO);
    Exit;
  end;
  Parts := PartsOf(APlaces, AInfo);
  if (Length(Parts) = 0) or (Parts[0].Role <> ROLE_TARGET) then
  begin
    AOffer.Reason := _('no target recognized');
    Exit;
  end;
  Result := BuildSqlTemplate(SqlRequestOf(APlaces, ALines, AInfo, Parts,
    AIsCall), Built);
  if Result then
  begin
    AOffer.Template := Built.Text;
    AOffer.Hint     := SqlHintOf(Built);
  end
  else
    AOffer.Reason := Built.Reason;
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
