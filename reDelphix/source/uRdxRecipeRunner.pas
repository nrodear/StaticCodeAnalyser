unit uRdxRecipeRunner;

// reDelphix - der Rezept-Laeufer: fuehrt die Rezepte (uRdxRecipes) gegen
// den Quellstellen-Dienst des SCA-Cores (TSourcePlaces) aus. Ohne
// ToolsAPI, ohne Clipboard, ohne Menue - damit ist dieser Weg vom Fund
// bis zum fertigen Ersatztext in reDelphix.Test ohne IDE pruefbar. Der
// Kern des Anbieters (uRdxActionCore, seit E3) baut daraus die Eintraege,
// uRdxProvider nur noch die Menuepunkte.
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
//
// Seit Charge N (C16, 2026-10-25) steht der Code von Describe, PartsOf,
// FormatRewrite und den uses-Fragen (PlanUses, Klauseln, Direktiven,
// FPC-Weiche) in uRdxPlacesRunner - er braucht nur den Quellstellen-
// Dienst und laeuft so auch im FPC-Pruefstand, und die Code-Aktion ohne
// Fund "Format() aus Verkettung" (uRdxContextRunner) nimmt dieselbe Kette.
// Die Methoden hier delegieren mit unveraenderten Signaturen; die
// Beschreibungen stehen dort. Hier bleiben, was Fund oder Katalog braucht
// (QueryOf), die SQL-Vorlage (SqlTemplate) und QualifyUses.

interface

uses
  System.Classes, System.Generics.Collections,
  uEngineApi, uRefactorInfo, uFindingActions, uRdxRecipes,
  uMethodd12,       // TLeakFinding
  uRdxScopeTable,   // TRdxScopeTable (QualifyUses)
  uRdxPlacesRunner, // TRdxPlacesRunner: Describe, Format, uses (C16)
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

  // Was fuer eine fehlende Unit in der uses-Klausel zu tun ist (AH19) -
  // seit C16 in uRdxPlacesRunner, der Alias haelt die Verwender stabil.
  TRdxUsesPlan = uRdxPlacesRunner.TRdxUsesPlan;

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
    // Die Hilfe steht nur im Menue, nicht in der Gluehbirne (Nico
    // 2026-10-29, Realworld-Test rwE30 Stufe 2): ihr Beweis ist nicht
    // vollstaendig - SCA007, wenn die Datei Bezeichner nutzt, die der Planer
    // keiner anderen Unit zuordnen kann (TRdxStructFixes.ForeignIdent). Der
    // Anbieter gibt dem Eintrag dafuer die Art fakRefactor
    // (uRdxActionCore.AddSimpleFix): Kontextmenue und Dock-Grid zeigen ihn,
    // die Gluehbirne und Ctrl+Alt+F nicht.
    MenuOnly : Boolean;
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

  // Die Anfrage an Describe und das Ergebnis von FormatRewrite - seit C16
  // in uRdxPlacesRunner (dort beschrieben), die Aliase halten die
  // Verwender stabil.
  TRdxAnchorQuery   = uRdxPlacesRunner.TRdxAnchorQuery;
  TRdxFormatOutcome = uRdxPlacesRunner.TRdxFormatOutcome;

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
    // ---- delegiert an TRdxPlacesRunner (uRdxPlacesRunner, seit C16; die
    // Beschreibungen stehen dort) ----
    class function HeadOf(const ACallName: string): string; static;
    class function UsesNamesOf(APlaces: TSourcePlaces): TArray<string>; static;
    class function DescribeAnchor(APlaces: TSourcePlaces; ALine: Integer;
      const AAnchor: string; out AIsCall: Boolean;
      out AWhy: string): TRefactorInfo; static;
    class function Describe(APlaces: TSourcePlaces;
      const AQuery: TRdxAnchorQuery; out AIsCall: Boolean;
      out AWhy: string): TRefactorInfo; static;
    class function PartsOf(APlaces: TSourcePlaces;
      AInfo: TRefactorInfo): TRdxParts; static;
    class function TargetTypeOf(APlaces: TSourcePlaces; AInfo: TRefactorInfo;
      const ATargetText: string): string; static;
    class function FormatRewrite(APlaces: TSourcePlaces; AInfo: TRefactorInfo;
      const AWhy: string;
      const AUsesNames: TArray<string>): TRdxFormatOutcome; static;
    class function PlanUses(APlaces: TSourcePlaces;
      const AShortName, AQualifiedName: string;
      AAtLine: Integer = 0): TRdxUsesPlan; static;
    class function DirectiveLineIn(APlaces: TSourcePlaces;
      const AEntries: TArray<TRefactorSpan>): Integer; static;
    class function UsesDirectiveLine(APlaces: TSourcePlaces): Integer; static;
    class function LineInUsesClause(APlaces: TSourcePlaces;
      ALine: Integer): Boolean; static;
    class function SourceLooksFpcAware(APlaces: TSourcePlaces): Boolean; static;

    // Die Anfrage zu einem Fund: Zeile aus AFinding, Ziel und '+'-Zahl aus
    // seiner Meldung - SCA044 'Concat (n x ''+'') -> Format(...) Ziel',
    // SCA003 'Ziel  [Fix ..]' (TRdxRecipes.ConcatFindingTarget/
    // SqlFindingTarget). Andere Regeln oder eine fremde Meldungsform:
    // keine Gegenprobe.
    class function QueryOf(AFinding: TLeakFinding;
      const AAnchor: string): TRdxAnchorQuery; static;

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
  uRdxText;          // _ (E29)

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
begin
  Result := TRdxPlacesRunner.HeadOf(ACallName);
end;

class function TRdxRecipeRunner.UsesNamesOf(
  APlaces: TSourcePlaces): TArray<string>;
begin
  Result := TRdxPlacesRunner.UsesNamesOf(APlaces);
end;

class function TRdxRecipeRunner.DescribeAnchor(APlaces: TSourcePlaces;
  ALine: Integer; const AAnchor: string; out AIsCall: Boolean;
  out AWhy: string): TRefactorInfo;
begin
  Result := TRdxPlacesRunner.DescribeAnchor(APlaces, ALine, AAnchor,
    AIsCall, AWhy);
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
begin
  Result := TRdxPlacesRunner.Describe(APlaces, AQuery, AIsCall, AWhy);
end;

class function TRdxRecipeRunner.PartsOf(APlaces: TSourcePlaces;
  AInfo: TRefactorInfo): TRdxParts;
begin
  Result := TRdxPlacesRunner.PartsOf(APlaces, AInfo);
end;

class function TRdxRecipeRunner.TargetTypeOf(APlaces: TSourcePlaces;
  AInfo: TRefactorInfo; const ATargetText: string): string;
begin
  Result := TRdxPlacesRunner.TargetTypeOf(APlaces, AInfo, ATargetText);
end;

class function TRdxRecipeRunner.FormatRewrite(APlaces: TSourcePlaces;
  AInfo: TRefactorInfo; const AWhy: string;
  const AUsesNames: TArray<string>): TRdxFormatOutcome;
begin
  Result := TRdxPlacesRunner.FormatRewrite(APlaces, AInfo, AWhy, AUsesNames);
end;

// Ohne Beschreibung der Stelle (SqlTemplate) - dieselbe msgid wie
// R_NO_INFO in uRdxPlacesRunner (der Extraktor loest Konstanten nur in
// ihrer Unit auf).
const
  R_NO_INFO = 'no description';

function ClausesOf(APlaces: TSourcePlaces): TArray<TArray<TRefactorSpan>>;
begin
  Result := uRdxPlacesRunner.ClausesOf(APlaces);
end;

function UsesKeywordLine(APlaces: TSourcePlaces;
  const AFirst: TRefactorSpan): Integer;
begin
  Result := uRdxPlacesRunner.UsesKeywordLine(APlaces, AFirst);
end;

class function TRdxRecipeRunner.DirectiveLineIn(APlaces: TSourcePlaces;
  const AEntries: TArray<TRefactorSpan>): Integer;
begin
  Result := TRdxPlacesRunner.DirectiveLineIn(APlaces, AEntries);
end;

class function TRdxRecipeRunner.UsesDirectiveLine(APlaces: TSourcePlaces): Integer;
begin
  Result := TRdxPlacesRunner.UsesDirectiveLine(APlaces);
end;

class function TRdxRecipeRunner.LineInUsesClause(APlaces: TSourcePlaces;
  ALine: Integer): Boolean;
begin
  Result := TRdxPlacesRunner.LineInUsesClause(APlaces, ALine);
end;

class function TRdxRecipeRunner.SourceLooksFpcAware(
  APlaces: TSourcePlaces): Boolean;
begin
  Result := TRdxPlacesRunner.SourceLooksFpcAware(APlaces);
end;

class function TRdxRecipeRunner.PlanUses(APlaces: TSourcePlaces;
  const AShortName, AQualifiedName: string;
  AAtLine: Integer): TRdxUsesPlan;
begin
  Result := TRdxPlacesRunner.PlanUses(APlaces, AShortName, AQualifiedName,
    AAtLine);
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
  Map := TRdxCodeMap.Acquire(ALines);
  try
    AddSqlFacts(Map, Result);
  finally
    TRdxCodeMap.Release(Map);
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
