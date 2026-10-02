unit uSourcePlaces;

// Quellstellen-Dienst: liefert einem Fremd-Konsumenten (Modul "Source
// Refactor", reDelphix) beschriebene Stellen einer Quelldatei - auf
// Anfrage, ausserhalb des Scans, ohne Detektor und ohne Fund.
// Konzept_SourceRefactor_Quellstellen 2026-10-02, entschieden 2026-10-03.
//
// WARUM PULL
//
// Der Vorgaenger (Branch ag-refactorinfo) liess DETEKTOREN ihre
// Refactoring-Informationen an den Fund haengen. Das kostete je
// liefernder Regel eine Detektor-Aenderung - Signatur, Registrierung,
// Zeilenzugriff, Tests. Hier fragt stattdessen der Konsument: er hat
// Datei, Zeile und Regel-ID (aus SARIF, JSON oder TScanResult) und holt
// sich die Beschreibung. Eine neue Umformung ist dann ein Rezept aus den
// Primitiven dieser Klasse im Modul - kein Code im Core.
//
// WAS DIESE KLASSE NICHT TUT
//
//   * Sie meldet nichts, aendert keinen Fund, kein Feld, keinen Export.
//     Fundzahl, FP-Quote, Baselines und SARIF koennen sich durch sie
//     nicht bewegen. Kein Detektor darf sie importieren.
//   * Sie benutzt NICHT den Datei-Cache des Scans und keinen Engine-Lock:
//     Open liest die Datei selbst (LoadFileSmart, TParser2.ParseFile).
//     Dadurch ist sie auch aus einem residenten Host (IDE-Plugin) heraus
//     jederzeit aufrufbar - die Doku_01-Leitplanke "Engine nur fuer
//     kurzlebige Ein-Scan-Prozesse" betrifft den Scan, nicht das Lesen
//     einer Datei. Preis: ein Datei-Read je Open.
//   * Sie schreibt nichts. Das Umschreiben ist Sache des Moduls.
//
// DIE PRIMITIVE
//
//   StatementAt   Anweisung an Position: Bereich, Flags, Einfuegepunkt,
//                 Hash (uRefactorInfoBuilder)
//   ChainOf       '+'-Kette einer Zuweisung: Ziel, Literale, Operanden,
//                 FixSafe (uRefactorConcat)
//   CallOf        Aufruf mit EINEM Argument: Kopf + Kette
//   NodesAt       AST-Knoten einer Art auf einer Zeile - der Weg vom Fund
//                 (Zeile) zur Startposition (Spalte) und zum Zielnamen
//   CodeViewOf / TextOf / HashOf   Sicht, Text und Hash eines Bereichs
//   ConditionalRanges              {$IFDEF}-Bereiche der Datei
//
// Jedes Primitiv ist total: nil bzw. leeres Array statt Exception, auch
// wenn keine Datei geoeffnet ist. Einzige Ausnahme: ein Parser-Fehler in
// Open laeuft als Exception zum Aufrufer (TParser2.ParseFile), die
// Nicht-Lesbarkeit der Datei dagegen ist ein False.
//
// KOORDINATEN wie uRefactorInfo: 1-basiert, EndCol zeigt HINTER das
// letzte Zeichen. Der Vertrag traegt eine Versionsnummer
// (SOURCE_PLACES_VERSION); ein Konsument prueft sie.

interface

uses
  System.Classes,
  uAstNode, uAstSpans, uRefactorInfo;   // TNodeKinds kommt aus uAstSpans

const
  // Vertragsversion. Aenderungen an Signaturen, Rollen oder Koordinaten
  // erhoehen sie.
  SOURCE_PLACES_VERSION = 1;

type
  // Kopie der vier Felder eines AST-Knotens, die ein Konsument braucht.
  // Kein TAstNode nach aussen: der Baum gehoert dem Dienst und lebt nur
  // bis zum naechsten Open/Close.
  TNodeRef = record
    Kind    : TNodeKind;
    Line    : Integer;
    Col     : Integer;
    Name    : string;    // Ziel/Kopf, wie der Parser ihn zusammengefuegt hat
    TypeRef : string;    // rechte Seite bzw. Typbezug, abgeflacht
  end;

  // Eigener Name, weil uUninitVar bereits ein lokales TLineRange fuehrt.
  TSourceLineRange = record
    StartLine : Integer;
    EndLine   : Integer;
  end;

  TSourcePlaces = class
  private
    FFileName : string;
    FLines    : TStringList;   // nil, solange nichts geoeffnet ist
    FRoot     : TAstNode;      // AST der Datei, nil ohne Datei
  public
    constructor Create;
    destructor Destroy; override;

    // Liest Zeilen und AST der Datei. False, wenn die Datei nicht lesbar
    // ist - dann ist nichts geoeffnet. Ein vorher geoeffneter Stand wird
    // in jedem Fall verworfen.
    function Open(const AFileName: string): Boolean;
    procedure Close;
    function IsOpen: Boolean;
    property FileName: string read FFileName;
    function LineCount: Integer;

    // P1 - Anweisung, die an (ALine, ACol) beginnt. nil, wenn ihr Ende
    // nicht sauber bestimmbar ist. Der Aufrufer besitzt das Ergebnis.
    function StatementAt(ALine, ACol: Integer): TRefactorInfo;

    // P3 - Zuweisung mit '+'-Kette an (ALine, ACol). AExpectedTarget <> ''
    // ist die Gegenprobe gegen den Knoten (TNodeRef.Name): passt das Ziel
    // im Quelltext nicht dazu, kommt nil.
    function ChainOf(ALine, ACol: Integer;
      const AExpectedTarget: string = ''): TRefactorInfo;

    // P4 - Aufruf mit genau einem Argument an (ALine, ACol). AExpectedHead
    // ist der Aufrufkopf vor der ersten Klammer (bei nkCall der Teil von
    // TNodeRef.Name vor '('); '' = keine Gegenprobe.
    function CallOf(ALine, ACol: Integer;
      const AExpectedHead: string = ''): TRefactorInfo;

    // P2 - alle Knoten der Arten AKinds, die auf ALine BEGINNEN, nach
    // Spalte aufsteigend. Leer ohne Datei oder ohne Treffer. Zwei Treffer
    // heissen: die Zeile ist mehrdeutig - der Konsument entscheidet.
    function NodesAt(ALine: Integer; const AKinds: TNodeKinds): TArray<TNodeRef>;
    // Dasselbe auf einem fremden Baum - fuer Tests und fuer Konsumenten,
    // die den AST schon haben.
    class function CollectNodesAt(ARoot: TAstNode; ALine: Integer;
      const AKinds: TNodeKinds): TArray<TNodeRef>; static;

    // P6 - Sicht, Text und Hash eines Bereichs der geoeffneten Datei.
    function CodeViewOf(const ASpan: TRefactorSpan): TArray<string>;
    function TextOf(const ASpan: TRefactorSpan): string;
    function HashOf(const ASpan: TRefactorSpan): string;

    // P7 - {$IFDEF}-Bereiche der Datei (Zeile der oeffnenden bis Zeile der
    // schliessenden Direktive), in Quelltext-Reihenfolge.
    function ConditionalRanges: TArray<TSourceLineRange>;
  end;

implementation

// noinspection-file UnusedPublicMember
// Die Primitive sind fuer das Modul reDelphix ausserhalb dieses Repos da;
// der Selbstscan sieht keinen Aufrufer.

uses
  System.SysUtils,
  uParser2, uFileTextCache, uRefactorInfoBuilder, uRefactorConcat;

{ TSourcePlaces }

constructor TSourcePlaces.Create;
begin
  inherited Create;
end;

destructor TSourcePlaces.Destroy;
begin
  Close;
  inherited;
end;

function TSourcePlaces.Open(const AFileName: string): Boolean;
var
  Parser : TParser2;
begin
  Close;
  Result := False;
  FLines := TStringList.Create;
  if not LoadFileSmart(AFileName, FLines) then
  begin
    FreeAndNil(FLines);
    Exit;
  end;
  // Derselbe Lade-/Namenspfad wie in Produktion (ParseFile statt
  // ParseSource): Root.Name = Dateipfad, Encoding-Fallbacks des Parsers.
  Parser := TParser2.Create;
  try
    FRoot := Parser.ParseFile(AFileName);
  finally
    Parser.Free;
  end;
  FFileName := AFileName;
  Result := True;
end;

procedure TSourcePlaces.Close;
begin
  FreeAndNil(FRoot);
  FreeAndNil(FLines);
  FFileName := '';
end;

function TSourcePlaces.IsOpen: Boolean;
begin
  Result := Assigned(FLines);
end;

function TSourcePlaces.LineCount: Integer;
begin
  Result := 0;
  if Assigned(FLines) then
    Result := FLines.Count;
end;

{ ---- P1 / P3 / P4 ---- }

function TSourcePlaces.StatementAt(ALine, ACol: Integer): TRefactorInfo;
begin
  Result := nil;
  if not IsOpen then Exit;
  Result := TRefactorInfoBuilder.TryBuildForStatement(FRoot, FLines,
    ALine, ACol);
end;

function TSourcePlaces.ChainOf(ALine, ACol: Integer;
  const AExpectedTarget: string): TRefactorInfo;
begin
  Result := nil;
  if not IsOpen then Exit;
  Result := TRefactorConcat.TryDescribeAssign(FRoot, FLines, ALine, ACol);
  if Assigned(Result) and (AExpectedTarget <> '')
     and not TRefactorConcat.TargetMatches(FLines, Result, AExpectedTarget) then
    FreeAndNil(Result);
end;

function TSourcePlaces.CallOf(ALine, ACol: Integer;
  const AExpectedHead: string): TRefactorInfo;
begin
  Result := nil;
  if not IsOpen then Exit;
  Result := TRefactorConcat.TryDescribeCall(FRoot, FLines, ALine, ACol);
  if Assigned(Result) and (AExpectedHead <> '')
     and not TRefactorConcat.TargetMatches(FLines, Result, AExpectedHead) then
    FreeAndNil(Result);
end;

{ ---- P2 ---- }

class function TSourcePlaces.CollectNodesAt(ARoot: TAstNode; ALine: Integer;
  const AKinds: TNodeKinds): TArray<TNodeRef>;
// Iterativer Pre-Order-Walk (kein Stapelueberlauf bei tiefen Baeumen),
// danach nach Spalte sortiert - zwei Zuweisungen auf einer Zeile kommen
// in Quelltext-Reihenfolge.
var
  Stack : TArray<TAstNode>;
  Top   : Integer;
  N     : TAstNode;
  i, j  : Integer;
  Count : Integer;
  Tmp   : TNodeRef;
begin
  Result := nil;
  if not Assigned(ARoot) or (ALine < 1) then Exit;
  Count := 0;
  SetLength(Stack, 64);
  Stack[0] := ARoot;
  Top := 1;
  while Top > 0 do
  begin
    Dec(Top);
    N := Stack[Top];
    if (N.Line = ALine) and (N.Kind in AKinds) then
    begin
      if Count = Length(Result) then
        SetLength(Result, Count * 2 + 4);
      Result[Count].Kind    := N.Kind;
      Result[Count].Line    := N.Line;
      Result[Count].Col     := N.Col;
      Result[Count].Name    := N.Name;
      Result[Count].TypeRef := N.TypeRef;
      Inc(Count);
    end;
    if Assigned(N.Children) then
      // Kinder in umgekehrter Reihenfolge pushen -> Pre-Order in
      // Quelltext-Reihenfolge.
      for i := N.Children.Count - 1 downto 0 do
      begin
        if Top = Length(Stack) then
          SetLength(Stack, Top * 2);
        Stack[Top] := N.Children[i];
        Inc(Top);
      end;
  end;
  SetLength(Result, Count);
  // Einfuegesortierung nach Spalte - die Trefferzahl je Zeile ist winzig.
  for i := 1 to Count - 1 do
  begin
    Tmp := Result[i];
    j := i - 1;
    while (j >= 0) and (Result[j].Col > Tmp.Col) do
    begin
      Result[j + 1] := Result[j];
      Dec(j);
    end;
    Result[j + 1] := Tmp;
  end;
end;

function TSourcePlaces.NodesAt(ALine: Integer;
  const AKinds: TNodeKinds): TArray<TNodeRef>;
begin
  Result := CollectNodesAt(FRoot, ALine, AKinds);
end;

{ ---- P6 / P7 ---- }

function TSourcePlaces.CodeViewOf(const ASpan: TRefactorSpan): TArray<string>;
begin
  Result := nil;
  if not IsOpen then Exit;
  Result := TRefactorInfoBuilder.CodeViewOf(FLines, ASpan);
end;

function TSourcePlaces.TextOf(const ASpan: TRefactorSpan): string;
begin
  Result := '';
  if not IsOpen then Exit;
  Result := TRefactorInfoBuilder.SpanText(FLines, ASpan);
end;

function TSourcePlaces.HashOf(const ASpan: TRefactorSpan): string;
begin
  Result := '';
  if not IsOpen then Exit;
  Result := TRefactorInfoBuilder.HashOfSpan(FLines, ASpan);
end;

function TSourcePlaces.ConditionalRanges: TArray<TSourceLineRange>;
// Die Marker haengen direkt am Unit-Knoten (uParser2: Root.Add) -
// dieselbe Lesart wie TRefactorInfoBuilder.InConditionalRange.
var
  i     : Integer;
  N     : TAstNode;
  Count : Integer;
begin
  Result := nil;
  if not Assigned(FRoot) or not Assigned(FRoot.Children) then Exit;
  Count := 0;
  for i := 0 to FRoot.Children.Count - 1 do
  begin
    N := FRoot.Children[i];
    if N.Kind <> nkConditionalRange then Continue;
    SetLength(Result, Count + 1);
    Result[Count].StartLine := N.Line;
    Result[Count].EndLine   := StrToIntDef(N.TypeRef, N.Line);
    Inc(Count);
  end;
end;

end.
