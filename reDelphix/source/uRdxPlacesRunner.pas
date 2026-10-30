unit uRdxPlacesRunner;

// reDelphix - der Teil des Rezept-Laeufers, der nur den Quellstellen-Dienst
// (TSourcePlaces) und die Rezepte (uRdxRecipes) braucht: die Anweisung
// einer Zeile beschreiben (Describe), die Teile einer Kette mit Typen
// (PartsOf), Format() aus der Kette (FormatRewrite, Rezept 5.1 = SCA044)
// und die uses-Fragen dazu (PlanUses, Klauseln, Direktiven, FPC-Weiche).
// Ohne Fund, ohne Katalog, ohne ToolsAPI - darum auch im FPC-Pruefstand
// (tools\fpc-pruefstand\build.sh, gegen den Stub-Parser).
//
// WARUM EINE EIGENE UNIT (Charge N, C16, 2026-10-25): "Format() aus
// Verkettung" gibt es seit C16 auch als Code-Aktion ohne Fund am Caret
// (uRdxContextRunner, ckConcatToFormat) - mit DERSELBEN Kette wie die
// Fund-Hilfe SCA044. uRdxRecipeRunner bindet Fund (uMethodd12), Katalog
// (uSCAConsts) und uEngineApi und laeuft nicht unter FPC; der Code stand
// bis dahin dort und ist 1:1 hierher umgezogen. TRdxRecipeRunner
// delegiert mit denselben Signaturen hierher (Anbieter, uRdxFixRunner und
// Tests unveraendert); die Typen TRdxUsesPlan, TRdxAnchorQuery und
// TRdxFormatOutcome fuehrt er als Aliase. Neu sind nur die Felder
// NoOperand und FileWide von TRdxFormatOutcome (fuer den Laeufer am Caret;
// das Rezept des Anbieters liest sie nicht).
//
// ABLAUF FUER SCA044 (Rezept 5.1)
//
//   Describe        NodesAt(Zeile, Anker) -> genau ein Knoten -> Gegen-
//                   probe gegen den Fund (Ziel, '+'-Zahl) -> ChainOf mit
//                   der '+'-Zahl des Knotens (TypeRef)
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
  uAstNode,        // TNodeKind (Werte qualifiziert: TNodeKind.nkAssign)
  uAstSpans,       // TNodeKinds
  uRefactorInfo,   // TRefactorInfo, TRefactorSpan, ROLE_*
  uSourcePlaces,   // TSourcePlaces, TNodeRef, TUsesSection
  uRdxRecipes,     // TRdxParts
  uRdxBufferMath;  // TRdxEdit

const
  // PlanUses (Realworld-Test rwE29): die Unit steht im Text der uses-
  // Klauseln nur unter {$IF..}/{$IFDEF..} - ob im gebauten Zweig, bleibt
  // offen. Der Satz folgt hinter '%s is missing in uses: ' (AppendUses in
  // uRdxFixRunner, FormatUsesReason in uRdxRecipeRunner); %d die Zeile, %s
  // MsgByHand.
  R_USES_CONDITIONAL = 'it stands there only under a compiler condition '
    + '(line %d); %s';
  // Der ganze Satz dazu (TRdxPlacesRunner.UsesReason, Fix-Runde 4 nach
  // rwE32: Dev-Cpp ClassBrowser.pas:507 - "System.SysUtils fehlt in uses"
  // stimmte nicht, die Unit steht in '{$IFDEF WIN32}' UND '{$IFDEF LINUX}',
  // nur gilt keiner der beiden sicher). %s die Unit, %d die Zeile des
  // ersten Eintrags, %s MsgByHand.
  R_USES_ONLY_CONDITIONAL = '%s stands in uses only under a compiler '
    + 'condition (line %d), not in every branch around this place; %s';

type
  // Was fuer eine fehlende Unit in der uses-Klausel zu tun ist (AH19).
  TRdxUsesPlan = record
    Needed : Boolean;     // False = die Unit steht schon in einer uses-Klausel
    Name   : string;      // der einzufuegende Name ('System.SysUtils' / 'SysUtils')
    Edit   : TRdxEdit;    // die Ersetzung, wenn Needed und Reason = ''
    Reason : string;      // wenn Needed, aber keine Stelle bestimmbar
    // > 0: die Unit steht nur unter bedingter Uebersetzung in uses (die
    // Zeile des ersten Eintrags), Reason ist R_USES_CONDITIONAL - den
    // ganzen Satz fuer den Benutzer baut UsesReason.
    CondLine : Integer;
  end;

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
    // Gesperrt, weil die Kette (hinter 'X +') nur Literale traegt
    // (TRdxFormatBuild.NoOperand) - fuer den Laeufer am Caret kein
    // Kandidat (Charge N, C16).
    NoOperand  : Boolean;
    // Gesperrt, weil System.SysUtils fehlt und sich nicht einfuegen laesst
    // (Direktive in der Klausel, keine Klausel ...): das gilt jeder Kette
    // der Datei - der Laeufer am Caret zeigt dann keinen Eintrag, wie
    // TRdxMagicPlan.FileWide bei der Lokalen Konstante (C16).
    FileWide   : Boolean;
  end;

  TRdxPlacesRunner = class
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
    // einem $IFDEF-Zweig sperrt (DirectiveLineIn) - seit rwE31 nicht mehr,
    // wenn das Schluesselwort 'uses' und ein Eintrag, vor bzw. hinter dem
    // eingefuegt wird, ausserhalb jedes bedingten Zweigs stehen und die
    // Klausel kein {$I} traegt (UnconditionalPlace; JvCalc.pas:487 'uses
    // {$IFNDEF WIN32} JvStr16, {$ENDIF} JvVCLUtils, .. JvToolEdit;' - der
    // neue Name gilt dann in jedem Zweig - als Kurzname, die Zweige
    // koennen Compiler ohne Unit-Scopes bedienen). Ohne jede uses-Klausel
    // wird hinter 'implementation' (sonst 'interface') eine neue angelegt;
    // ein Programm oder eine Library ohne uses-Klausel bekommt keine -
    // Reason 'keine uses-Klausel und kein interface/implementation'; steht
    // das Schluesselwort selbst in einem bedingten Zweig, sperrt PlanUses
    // (die neue Klausel galte nur dort - ConditionLineOf, rwE29), ebenso,
    // wenn der Text eine uses-Klausel traegt, die der Baum nicht sah (in
    // einem bedingten Zweig - die neue Klausel kaeme davor, zwei
    // Klauseln hintereinander, rwE31 CnAICoderConfig.pas:649).
    // Ob die Unit schon da ist, fragt PlanUses den Baum UND den Text der
    // uses-Klauseln (TextUsesLine, Realworld-Test rwE29): steht sie nur
    // im Text, ist sie da; steht sie dort nur unter einer bedingten
    // Uebersetzung, sperrt PlanUses (Needed mit Reason) - ausser AAtLine
    // (die Zeile der Stelle, die die Unit braucht; 0 = unbekannt) liegt in
    // JEDEM bedingten Zweig, in dem der Eintrag steht (rwE31: gexperts
    // '{$IFDEF GX_EII}' um die ganze Unit, GX_Toolbar.pas:167): wo die
    // Stelle uebersetzt wird, ist die Unit eingebunden. Geht der Code, der
    // die Unit braucht, ueber mehrere Zeilen, ist AAtEndLine die letzte
    // (0 = wie AAtLine): JEDE Zeile von AAtLine bis AAtEndLine muss in den
    // Zweigen liegen, dazu das Ende von AAtEndLine hinter ihren
    // Direktiven (TextCovers; Fix-Runde 4: die Ersetzungen von SCA168.2
    // stehen auf der Zeile des letzten Arms und des 'end'). Steht die Unit
    // in jedem Zweig von '{$IFDEF X} .. {$ELSE} .. {$ENDIF}' (CEF4Delphi:
    // '{$IFDEF DELPHI16_UP} System.SysUtils, .. {$ELSE} SysUtils, ..
    // {$ENDIF}'), sieht sie schon der Baum - er parst genau einen der
    // Zweige (Ein-Zweig-Sicht), die Unit ist da (geprueft Fix-Runde 4 nach
    // rwE32, PlanUses_EntryInEachElseBranch_Present). Zwei getrennte
    // Bloecke ohne {$ELSE} ('{$IFDEF WIN32} .. SysUtils .. {$ENDIF}
    // {$IFDEF LINUX} .. SysUtils .. {$ENDIF}', Dev-Cpp ClassBrowser.pas)
    // beweisen nichts - es kann keiner gelten: gesperrt. Gesperrt wegen
    // eines nur bedingten Eintrags traegt der Plan CondLine (UsesReason).
    class function PlanUses(APlaces: TSourcePlaces;
      const AShortName, AQualifiedName: string;
      AAtLine: Integer = 0; AAtEndLine: Integer = 0): TRdxUsesPlan; static;

    // Der Grund fuer den Benutzer zu einem gesperrten Plan (Needed, Reason
    // gesetzt) der Unit AQualifiedName: mit CondLine R_USES_ONLY_CONDITIONAL
    // ("steht nur unter bedingter Uebersetzung"), sonst '%s is missing in
    // uses: <Reason>' - fuer AppendUses (uRdxFixRunner) und
    // FormatUsesReason.
    class function UsesReason(const APlan: TRdxUsesPlan;
      const AQualifiedName: string): string; static;

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
  end;

// Die uses-Klauseln der Datei, je Klausel ihre Eintraege (interface und
// implementation; ohne beide die Klausel der Programmdatei), leere fehlen.
// uRdxRecipeRunner reicht sie unter demselben Namen weiter (uRdxFixRunner:
// SCA007).
function ClausesOf(APlaces: TSourcePlaces): TArray<TArray<TRefactorSpan>>;
// Die Zeile des Schluesselworts 'uses' der Klausel mit dem ersten
// Eintrag AFirst.
function UsesKeywordLine(APlaces: TSourcePlaces;
  const AFirst: TRefactorSpan): Integer;

implementation

uses
  System.SysUtils,
  System.Classes,    // TStringList (PlacesLines)
  uRdxCodeMap,       // TRdxCodeMap, Token, Direktiven (PlanUses)
  uRdxText;          // _, MsgNoFileOpen, MsgMovedSuffix, MsgByHand (E29)

// Gegen Version 1 des Quellstellen-Vertrags geschrieben (uSourcePlaces,
// Abschnitt VERTRAGSVERSION) - wie uRdxRecipeRunner und uRdxFixRunner:
// steigt die Version, bricht der Bau hier ab.
{$IF SOURCE_PLACES_VERSION <> 1}
  {$MESSAGE ERROR 'reDelphix: SOURCE_PLACES_VERSION hat sich geaendert - Vertrag in uSourcePlaces (VERTRAGSVERSION) pruefen, uRdxPlacesRunner anpassen'}
{$IFEND}

{ TRdxPlacesRunner }

class function TRdxPlacesRunner.HeadOf(const ACallName: string): string;
var
  P : Integer;
begin
  Result := ACallName;
  P := Pos('(', Result);
  if P > 0 then
    Result := Copy(Result, 1, P - 1);
  Result := Trim(Result);
end;

class function TRdxPlacesRunner.UsesNamesOf(
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
      TRdxPlacesRunner.HeadOf(ANode.Name));
  if Result = nil then
    Result := APlaces.StatementAt(ANode.Line, ANode.Col);
  if (Result = nil) and (AWhy = '') then
    AWhy := _('the statement cannot be described');
end;

class function TRdxPlacesRunner.DescribeAnchor(APlaces: TSourcePlaces;
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

class function TRdxPlacesRunner.Describe(APlaces: TSourcePlaces;
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

class function TRdxPlacesRunner.PartsOf(APlaces: TSourcePlaces;
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

class function TRdxPlacesRunner.TargetTypeOf(APlaces: TSourcePlaces;
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
// oder der Grund, wenn die Einfuegung nicht planbar ist. Die Stelle, die
// SysUtils braucht, ist der ersetzte Bereich AOutcome.Span (der Format-
// Aufruf ersetzt ihn): steht SysUtils nur bedingt in uses, genuegt es,
// wenn jeder Zweig um den Eintrag seine Zeilen umfasst (PlanUses, Fix-
// Runde 4 - bis dahin ohne Zeile, gesperrt).
function FormatUsesReason(APlaces: TSourcePlaces;
  const AUsesNames: TArray<string>; var AOutcome: TRdxFormatOutcome): string;
var
  Plan : TRdxUsesPlan;
begin
  Result := '';
  if TRdxRecipes.HasUnit(AUsesNames, 'SysUtils') then Exit;
  Plan := TRdxPlacesRunner.PlanUses(APlaces, 'SysUtils', 'System.SysUtils',
    AOutcome.Span.StartLine, AOutcome.Span.EndLine);
  if not Plan.Needed then Exit;
  if Plan.Reason <> '' then
  begin
    // Gilt jeder Kette der Datei (C16: kein Eintrag am Caret) - auch
    // R_USES_CONDITIONAL, das seit Fix-Runde 4 von der Stelle abhaengt:
    // eine Kette in einem anderen Zweig gibt den Eintrag dann frei, ein
    // gesperrter Eintrag auf jeder Kette ausserhalb waere Rauschen.
    AOutcome.FileWide := True;
    Exit(TRdxPlacesRunner.UsesReason(Plan, 'System.SysUtils'));
  end;
  AOutcome.NeedsUses := True;
  AOutcome.UsesName  := Plan.Name;
  AOutcome.UsesEdit  := Plan.Edit;
  AOutcome.Hint := AOutcome.Hint + ' + uses ' + Plan.Name;
end;

class function TRdxPlacesRunner.FormatRewrite(APlaces: TSourcePlaces;
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
    Result.NoOperand := Build.NoOperand;
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

class function TRdxPlacesRunner.DirectiveLineIn(APlaces: TSourcePlaces;
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

class function TRdxPlacesRunner.UsesDirectiveLine(APlaces: TSourcePlaces): Integer;
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

class function TRdxPlacesRunner.LineInUsesClause(APlaces: TSourcePlaces;
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

class function TRdxPlacesRunner.SourceLooksFpcAware(
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

function UnconditionalPlace(APlaces: TSourcePlaces;
  const AEntries: TArray<TRefactorSpan>; var AAnchor: TRefactorSpan;
  var AAppend: Boolean): Boolean; forward;

// Die Einfuegung in eine bestehende Klausel (PlanUses). APlan.Name steht.
procedure PlanIntoClause(APlaces: TSourcePlaces;
  const AEntries: TArray<TRefactorSpan>; var APlan: TRdxUsesPlan);
var
  Names  : TArray<string>;
  i, Idx : Integer;
  Dir    : Integer;
  E      : TRefactorSpan;
  Append : Boolean;
  Old    : string;
begin
  Dir := TRdxPlacesRunner.DirectiveLineIn(APlaces, AEntries);
  // Eine Klausel mit Direktiven kann Compiler-Zweige tragen ('{$IF
  // CompilerVersion >= 23} System.SysUtils, {$ELSE} SysUtils, {$IFEND}',
  // '{$IFDEF D16} Vcl.Forms, {$ELSE} Forms, {$ENDIF}' - uChildForm.pas):
  // der Name kommt unbedingt hinein (UnconditionalPlace) und gilt in
  // jedem Zweig, einen Unit-Scope-Namen kennen Compiler vor XE2 nicht.
  // Darum der Kurzname wie in einer Datei mit FPC-Weiche - Delphi loest
  // ihn ueber die Vorgabe-Scopes ebenso auf (Review e/HilfeFixL).
  if (Dir > 0) and TRdxRecipes.IsRtlScopedName(APlan.Name) then
    APlan.Name := Copy(APlan.Name, Pos('.', APlan.Name) + 1, MaxInt);
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
  // Compiler-Direktiven in der Klausel ('uses A {$IFDEF X}, B{$ENDIF};')
  // oder eine Klausel in einem bedingten Zweig: eine Einfuegestelle kann
  // in einem Zweig liegen, der fuer ein anderes Ziel nicht uebersetzt
  // wird - dann von Hand. Seit rwE31 nicht, wenn 'uses' und ein Eintrag,
  // vor bzw. hinter den der Name kommt, ausserhalb jedes Zweigs stehen
  // (UnconditionalPlace; E und Append koennen dafuer wechseln): der Name
  // steht dann in jedem Zweig.
  if (Dir > 0) and not UnconditionalPlace(APlaces, AEntries, E, Append) then
  begin
    // Dieselbe msgid wie der Sperrgrund 'uses qualifizieren' des Anbieters
    // (uRdxActionCore, bis E3 uRdxProvider) - derselbe Satz, schon in
    // de.po/fr.po.
    APlan.Reason := _('uses clause contains compiler directives (line %d)',
      [Dir]);
    Exit;
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

// ---- Die uses-Klauseln im Text (PlanUses, Realworld-Test rwE29) ----
// WARUM: der Baum kann einen Eintrag verlieren. uParser2.ParseUses bricht
// eine Klausel an einem Namensglied ab, das ein Schluesselwort ist
// ('MVCFramework.Serializer.Abstract,' - der Knoten heisst dann
// 'MVCFramework.Serializer', alle Eintraege dahinter fehlen; Korpus:
// MVCFramework.Serializer.JsonDataObjects.pas mit 'System.SysUtils;' als
// letztem Eintrag des interface-uses). PlanUses fuegte die Unit dann ein
// zweites Mal ein (E2004 - SCA127 und SCA168.2). Der Text der Klauseln
// (Code-Sicht: Kommentare und Strings zaehlen nicht) entscheidet mit.

// Offene bedingte Bloecke ({$IF}, {$IFDEF}, {$IFNDEF}, {$IFOPT} ohne ihr
// {$ENDIF}/{$IFEND}) vor (ALine, ACol); AOuterLine ist die Zeile des
// aeussersten davon (0 = keiner) - fuer den Grund in PlanNewClause.
function ConditionDepthAt(AMap: TRdxCodeMap; ALine, ACol: Integer;
  out AOuterLine: Integer): Integer; overload;
var
  Li, Co : Integer;
  W      : string;
  Arg    : Boolean;
begin
  Result := 0;
  AOuterLine := 0;
  Li := 1;
  Co := 1;
  while NextDirective(AMap, Li, Co) do
  begin
    if (Li > ALine) or ((Li = ALine) and (Co >= ACol)) then
      Exit;
    W := DirectiveWord(AMap, Li, Co, Arg);
    if InList(W, COND_OPENERS) then
    begin
      if Result = 0 then
        AOuterLine := Li;
      Inc(Result);
    end
    else if InList(W, COND_CLOSERS) and (Result > 0) then
    begin
      Dec(Result);
      if Result = 0 then
        AOuterLine := 0;
    end;
    Inc(Co);
  end;
end;

function ConditionDepthAt(AMap: TRdxCodeMap; ALine, ACol: Integer): Integer;
  overload;
var
  Outer : Integer;
begin
  Result := ConditionDepthAt(AMap, ALine, ACol, Outer);
end;

// Die Eintraege AShortName (letztes Glied, Gross/klein egal - wie
// TRdxRecipes.HasUnit) in den uses-Klauseln des Codes, je ihr erstes
// Token, in der Reihenfolge der Datei. Eine Klausel endet am ';'; ein
// 'in'-Pfad ist ein String, kein Code-Token. Bis rwE31 der Lauf von
// UsesLineInMap selbst (TextCovers fragt jeden Treffer).
function UsesHitsInMap(AMap: TRdxCodeMap;
  const AShortName: string): TArray<TRdxToken>;
var
  T, N, First : TRdxToken;
  Name        : string;
begin
  Result := nil;
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), 'uses');
  while T.Low <> '' do
  begin
    if (T.Low = 'uses') and IsKeywordAfter(T, Before(AMap, T)) then
    begin
      Name := '';
      First := Default(TRdxToken);
      N := After(AMap, T);
      while N.Low <> '' do
      begin
        if (N.Low = ',') or (N.Low = ';') or (N.Low = 'in') then
        begin
          if (Name <> '') and SameText(LastPart(Name), AShortName) then
            AddToken(Result, First);
          Name := '';
          if N.Low = ';' then
            Break;
        end
        else
        begin
          if Name = '' then
            First := N;
          Name := Name + N.Low;
        end;
        N := After(AMap, N);
      end;
    end;
    T := NextTokenOnLineWith(AMap, T, 'uses');
  end;
end;

// Die Zeile des ersten Eintrags AShortName (UsesHitsInMap) ausserhalb
// jedes bedingten Zweigs; ACond: es gibt nur Eintraege unter bedingter
// Uebersetzung (ConditionDepthAt > 0 - jeder Treffer), dann die Zeile des
// ersten. 0 ohne Treffer.
function UsesLineInMap(AMap: TRdxCodeMap; const AShortName: string;
  out ACond: Boolean): Integer;
var
  Hits : TArray<TRdxToken>;
  i    : Integer;
begin
  Result := 0;
  ACond := False;
  Hits := UsesHitsInMap(AMap, AShortName);
  for i := 0 to High(Hits) do
    if ConditionDepthAt(AMap, Hits[i].Line, Hits[i].Col) = 0 then
      Exit(Hits[i].Line);
  if Length(Hits) > 0 then
  begin
    ACond := True;
    Result := Hits[0].Line;
  end;
end;

// Die bedingten Zweige, in denen (ALine, ACol) steht, von aussen nach
// innen: je Zweig die Stelle der Direktive, die ihn beginnt ({$IF..}/
// {$IFDEF..}, im Else-Teil das {$ELSE}/{$ELSEIF}), als Zahl (Zeile oben,
// Spalte unten). Zwei Stellen liegen im selben Zweig, wenn die Listen
// gleich anfangen (CoversBranches).
function BranchKeysAt(AMap: TRdxCodeMap; ALine, ACol: Integer): TArray<Int64>;
var
  Li, Co, n : Integer;
  W         : string;
  Arg       : Boolean;
begin
  Result := nil;
  n := 0;
  Li := 1;
  Co := 1;
  while NextDirective(AMap, Li, Co) do
  begin
    if (Li > ALine) or ((Li = ALine) and (Co >= ACol)) then
      Break;
    W := DirectiveWord(AMap, Li, Co, Arg);
    if InList(W, COND_OPENERS) then
    begin
      Inc(n);
      SetLength(Result, n);
      Result[n - 1] := (Int64(Li) shl 32) or Co;
    end
    else if ((W = 'else') or (W = 'elseif')) and (n > 0) then
      Result[n - 1] := (Int64(Li) shl 32) or Co
    else if InList(W, COND_CLOSERS) and (n > 0) then
    begin
      Dec(n);
      SetLength(Result, n);
    end;
    Inc(Co);
  end;
end;

// Liegt die Stelle mit den Zweigen AAt in JEDEM Zweig von AEntry (die
// Liste von AEntry ist der Anfang der von AAt)? Dann wird sie nur
// uebersetzt, wo auch der Eintrag uebersetzt wird.
function CoversBranches(const AEntry, AAt: TArray<Int64>): Boolean;
var
  i : Integer;
begin
  Result := Length(AEntry) <= Length(AAt);
  if Result then
    for i := 0 to High(AEntry) do
      if AEntry[i] <> AAt[i] then
        Exit(False);
end;

// Die Zeilen von APlaces als neue Liste - fuer eine eigene Code-Sicht (der
// Dienst reicht seine Zeilen nur einzeln heraus). Der Aufrufer gibt sie
// frei.
function PlacesLines(APlaces: TSourcePlaces): TStringList;
var
  Li : Integer;
begin
  Result := TStringList.Create;
  for Li := 1 to APlaces.LineCount do
    Result.Add(APlaces.LineText(Li));
end;

// UsesLineInMap auf den Zeilen von APlaces.
function TextUsesLine(APlaces: TSourcePlaces; const AShortName: string;
  out ACond: Boolean): Integer;
var
  Lines : TStringList;
  Map   : TRdxCodeMap;
begin
  Lines := PlacesLines(APlaces);
  try
    Map := TRdxCodeMap.Create(Lines);
    try
      Result := UsesLineInMap(Map, AShortName, ACond);
    finally
      Map.Free;
    end;
  finally
    Lines.Free;
  end;
end;

// Die Stelle, an der der Code der Zeile ALine beginnt (das erste Token;
// ohne Code auf der Zeile Spalte 1) - fuer BranchKeysAt.
function LineStartKeys(AMap: TRdxCodeMap; ALine: Integer): TArray<Int64>;
var
  T : TRdxToken;
begin
  T := NextToken(AMap, ALine, 1);
  if (T.Low <> '') and (T.Line = ALine) then
    Result := BranchKeysAt(AMap, ALine, T.Col)
  else
    Result := BranchKeysAt(AMap, ALine, 1);
end;

// Steht ein Eintrag AShortName der uses-Klauseln im Text so, dass jeder
// bedingte Zweig um ihn auch die Zeilen AAtLine bis AAtEndLine umfasst
// (CoversBranches)? Dann ist die Unit dort eingebunden, wo diese Zeilen
// uebersetzt werden (rwE31: gexperts GX_Toolbar.pas - '{$IFDEF GX_EII}'
// ab Zeile 5 um die ganze Unit, SysUtils in Zeile 14, die Stelle in Zeile
// 167). Geprueft werden die beiden Enden: der Code am Anfang von AAtLine
// (LineStartKeys) und das Ende von AAtEndLine HINTER jeder Direktive der
// Zeile ('X.Free; {$ENDIF}' liegt dort schon ausserhalb - eine Einfuegung
// hinter dem Zeilenende auch). Liegen beide Enden in denselben Zweigen
// des Eintrags, dann auch alles dazwischen: ein Zweig, der dazwischen
// endet ({$ENDIF}) oder wechselt ({$ELSE}), traegt danach eine andere
// Direktive als Schluessel (BranchKeysAt). Die Startzeile allein genuegte
// nicht: Direktiven duerfen mitten in einer Anweisung stehen, die
// Ersetzungen einer Hilfe koennen ueber mehrere Zeilen gehen
// (uRdxFixRunner.EditLines).
function TextCovers(APlaces: TSourcePlaces; const AShortName: string;
  AAtLine, AAtEndLine: Integer): Boolean;
var
  Lines   : TStringList;
  Map     : TRdxCodeMap;
  Hits    : TArray<TRdxToken>;
  At, Fin : TArray<Int64>;
  Entry   : TArray<Int64>;
  i       : Integer;
begin
  Result := False;
  if (AAtLine < 1) or (AAtEndLine < AAtLine)
     or (AAtEndLine > APlaces.LineCount) then
    Exit;
  Lines := PlacesLines(APlaces);
  try
    Map := TRdxCodeMap.Create(Lines);
    try
      Hits := UsesHitsInMap(Map, AShortName);
      At := LineStartKeys(Map, AAtLine);
      Fin := BranchKeysAt(Map, AAtEndLine, MaxInt);
      for i := 0 to High(Hits) do
      begin
        Entry := BranchKeysAt(Map, Hits[i].Line, Hits[i].Col);
        if CoversBranches(Entry, At) and CoversBranches(Entry, Fin) then
          Exit(True);
      end;
    finally
      Map.Free;
    end;
  finally
    Lines.Free;
  end;
end;

// Das Schluesselwort 'uses' auf ALine (Code); Low = '' ohne.
function UsesKeywordOn(AMap: TRdxCodeMap; ALine: Integer): TRdxToken;
var
  T : TRdxToken;
begin
  Result := Default(TRdxToken);
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if (T.Low = 'uses') and IsKeywordAfter(T, Before(AMap, T)) then
      Exit(T);
    T := After(AMap, T);
  end;
end;

// Steht AAnchor (Anfang und Ende, ohne Direktive darin) als Code
// ausserhalb jedes bedingten Zweigs (UnconditionalPlace)? Code: nicht in
// einem Kommentar oder einer Direktive - der Stub-Parser des FPC-
// Pruefstands liefert Direktivenwoerter als Eintraege.
function AnchorUnconditional(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  const AAnchor: TRefactorSpan): Boolean;
begin
  Result := AMap.IsCode(AAnchor.StartLine, AAnchor.StartCol)
    and not HasDirectiveText(APlaces.TextOf(AAnchor))
    and (ConditionDepthAt(AMap, AAnchor.StartLine, AAnchor.StartCol) = 0)
    and (ConditionDepthAt(AMap, AAnchor.EndLine, AAnchor.EndCol) = 0);
end;

// Wohin in eine Klausel mit Direktiven (DirectiveLineIn) eingefuegt werden
// darf (rwE31, JvCalc.pas:487 'uses {$IFNDEF WIN32} JvStr16, {$ENDIF}
// JvVCLUtils, .. JvToolEdit;', DW.Camera.pas:533 mit '{$IF
// Defined(ANDROID)}'-Bloecken mitten in der Klausel): das Schluesselwort
// 'uses' steht ausserhalb jedes bedingten Zweigs, die Klausel traegt kein
// {$I} (ein Include koennte die Unit schon bringen), und der Eintrag, vor
// bzw. hinter den der Name kommt, steht ausserhalb jedes Zweigs
// (AnchorUnconditional) - 'Name, A' bzw. 'A, Name' gilt dann in jedem
// Zweig. Erst die geplante Stelle (AAnchor, AAppend), dann hinter dem
// letzten Eintrag (AppendSpanOf), dann vor dem ersten unbedingten - die
// Sortierung kann dabei brechen. True mit der Stelle in AAnchor/AAppend,
// False ohne.
function UnconditionalPlace(APlaces: TSourcePlaces;
  const AEntries: TArray<TRefactorSpan>; var AAnchor: TRefactorSpan;
  var AAppend: Boolean): Boolean;
var
  Lines  : TStringList;
  Map    : TRdxCodeMap;
  Lo, Hi : Integer;
  i      : Integer;
  U      : TRdxToken;
  S      : TRefactorSpan;
begin
  Result := False;
  if Length(AEntries) = 0 then
    Exit;
  Lo := UsesKeywordLine(APlaces, AEntries[0]);
  Hi := ClauseLastLine(AEntries);
  Lines := PlacesLines(APlaces);
  try
    Map := TRdxCodeMap.Create(Lines);
    try
      U := UsesKeywordOn(Map, Lo);
      if (U.Low = '') or (IncludeInLines(Map, Lo, Hi) > 0)
         or (ConditionDepthAt(Map, U.Line, U.Col) > 0) then
        Exit;
      if AnchorUnconditional(APlaces, Map, AAnchor) then
        Exit(True);
      if AppendSpanOf(APlaces, AEntries[High(AEntries)], S)
         and AnchorUnconditional(APlaces, Map, S) then
      begin
        AAnchor := S;
        AAppend := True;
        Exit(True);
      end;
      for i := 0 to High(AEntries) do
        if AnchorUnconditional(APlaces, Map, AEntries[i]) then
        begin
          AAnchor := AEntries[i];
          AAppend := False;
          Exit(True);
        end;
    finally
      Map.Free;
    end;
  finally
    Lines.Free;
  end;
end;

// Die Zeile des ersten Schluesselworts 'uses' im Code; 0 ohne. PlanNewClause:
// sah der Baum keine Klausel, steht sie dann in einem Zweig, den er nicht
// las.
function TextUsesKeywordLine(APlaces: TSourcePlaces): Integer;
var
  Lines : TStringList;
  Map   : TRdxCodeMap;
  T     : TRdxToken;
begin
  Result := 0;
  Lines := PlacesLines(APlaces);
  try
    Map := TRdxCodeMap.Create(Lines);
    try
      T := NextTokenOnLineWith(Map, Default(TRdxToken), 'uses');
      while T.Low <> '' do
      begin
        if (T.Low = 'uses') and IsKeywordAfter(T, Before(Map, T)) then
          Exit(T.Line);
        T := NextTokenOnLineWith(Map, T, 'uses');
      end;
    finally
      Map.Free;
    end;
  finally
    Lines.Free;
  end;
end;

// Die Zeile des aeussersten bedingten Blocks, in dem der Code der Zeile
// ALine von APlaces steht (ConditionDepthAt vor ihrem ersten Zeichen);
// 0 = in keinem.
function ConditionLineOf(APlaces: TSourcePlaces; ALine: Integer): Integer;
var
  Lines : TStringList;
  Map   : TRdxCodeMap;
  Text  : string;
begin
  Text := APlaces.LineText(ALine);
  Lines := PlacesLines(APlaces);
  try
    Map := TRdxCodeMap.Create(Lines);
    try
      ConditionDepthAt(Map, ALine, Length(Text) - Length(TrimLeft(Text)) + 1,
        Result);
    finally
      Map.Free;
    end;
  finally
    Lines.Free;
  end;
end;

// Keine uses-Klausel (PlanUses): eine neue hinter 'implementation', sonst
// hinter 'interface' anlegen - als Ersetzung der Schluesselwort-Zeile. Ein
// Programm oder eine Library hat keinen der beiden Abschnitte: Reason.
procedure PlanNewClause(APlaces: TSourcePlaces; var APlan: TRdxUsesPlan);
var
  Line, CondLine : Integer;
  Text           : string;
begin
  Line := APlaces.SectionLine(TUsesSection.usImplementation);
  if Line = 0 then
    Line := APlaces.SectionLine(TUsesSection.usInterface);
  if Line = 0 then
  begin
    APlan.Reason := _('no uses clause and no interface/implementation');
    Exit;
  end;
  // Der Baum sah keine Klausel, der Text traegt eine: sie steht in einem
  // Zweig, den der Baum nicht las (rwE31, cnwizards CnAICoderConfig.pas:
  // 'implementation' / '{$IFDEF CNWIZARDS_CNAICODERWIZARD}' / 'uses
  // CnSM4, ..' - die neue Klausel kam zwischen 'implementation' und den
  // Zweig, zwei Klauseln hintereinander, E2029).
  CondLine := TextUsesKeywordLine(APlaces);
  if CondLine > 0 then
  begin
    APlan.Reason := _('the uses clause in line %d is not read here (it lies '
      + 'in a conditional branch) - add the unit by hand', [CondLine]);
    Exit;
  end;
  // Ein Abschnitts-Schluesselwort in einem bedingten Zweig: die neue
  // Klausel galte nur dort (rwE29, mORMot2 mormot.crypt.openssl.pas: das
  // zweite 'implementation' im {$else}-Zweig des leeren Moduls bekam die
  // Klausel, der Code der Fundstelle steht im {$ifdef}-Zweig).
  CondLine := ConditionLineOf(APlaces, Line);
  if CondLine > 0 then
  begin
    APlan.Reason := _('the section keyword in line %d is inside a '
      + 'conditional branch (line %d) - add the uses clause by hand',
      [Line, CondLine]);
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

class function TRdxPlacesRunner.PlanUses(APlaces: TSourcePlaces;
  const AShortName, AQualifiedName: string;
  AAtLine, AAtEndLine: Integer): TRdxUsesPlan;
var
  AllNames : TArray<string>;
  Entries  : TArray<TRefactorSpan>;
  Li, Last : Integer;
  Cond     : Boolean;
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
  // Im Text da, der Baum sah sie nicht (s. TextUsesLine): nicht noetig;
  // nur unter einer Bedingung: offen - gesperrt.
  Li := TextUsesLine(APlaces, AShortName, Cond);
  if (Li > 0) and not Cond then Exit;
  // Nur bedingt eingebunden, aber in jedem Zweig, der die Stelle AAtLine
  // (bis AAtEndLine) umfasst (rwE31): dort ist sie da.
  Last := AAtEndLine;
  if Last < AAtLine then
    Last := AAtLine;
  if (Li > 0) and (AAtLine > 0)
     and TextCovers(APlaces, AShortName, AAtLine, Last) then
    Exit;
  Result.Needed := True;
  if Li > 0 then
  begin
    Result.Reason := _(R_USES_CONDITIONAL, [Li, MsgByHand]);
    Result.CondLine := Li;
    Exit;
  end;
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

class function TRdxPlacesRunner.UsesReason(const APlan: TRdxUsesPlan;
  const AQualifiedName: string): string;
begin
  if APlan.CondLine > 0 then
    Result := _(R_USES_ONLY_CONDITIONAL, [AQualifiedName, APlan.CondLine,
      MsgByHand])
  else
    Result := _('%s is missing in uses: %s', [AQualifiedName, APlan.Reason]);
end;

end.
