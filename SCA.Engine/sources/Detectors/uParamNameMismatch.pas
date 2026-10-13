unit uParamNameMismatch;

// SCA199 ParamNameMismatch - ParamByName-Namen gegen die :Platzhalter im
// SQL derselben Query, je Routine.
//
// Die eigentliche Pruefung steht in uParamNameScan (ohne AST, einzeln
// testbar). Diese Unit schneidet die Routinen zu: je Methode mit Rumpf
// der Bereich von der Kopfzeile bis vor die naechste Methode, hoechstens
// bis initialization/finalization/'end.' - so bleiben auch mehrzeilige
// letzte Anweisungen ganz drin, die der AST nur mit ihrer Startzeile
// fuehrt. Geschachtelte Routinen werden ausgeblendet - jede von ihrer
// ersten Zeile bis vor den naechsten Deklarationsabschnitt der aeusseren
// (var/const/type/label), die naechste geschachtelte oder das 'begin' der
// aeusseren, damit auch Fortsetzungszeilen ihrer letzten Anweisung und ihr
// 'end;' wegfallen. Ihr Text geht als AHidden an den Scanner: erwaehnt er
// eine Query der aeusseren Routine, wird diese nicht beurteilt (die innere
// kann binden oder SQL anhaengen). Der var-Abschnitt HINTER einer
// geschachtelten Routine bleibt sichtbar: bis 2026-10-14 wurde pauschal
// bis vor das 'begin' ausgeblendet, jede dort deklarierte Query galt damit
// als "erwaehnt" und wurde nie beurteilt.
//
// Anlass (2026-10-07, Nico): eine TOracleQuery, deren ParamByName-Namen
// nicht zu den Platzhaltern im SQL.Add passten. Der Compiler sieht so
// etwas nie, es faellt erst beim Ausfuehren auf.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TParamNameMismatchDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file BeginEndRequired, IfElseBegin, TooLongLine

uses
  System.Math, uFileTextCache, uAstSpans, uParamNameScan;

type
  TRange = record
    Method : TAstNode;
    First  : Integer;   // 1-basiert
    Last   : Integer;
  end;

function IsUnitTail(const ALine: string): Boolean;
var
  T : string;
begin
  T := LowerCase(Trim(ALine));
  Result := (T = 'initialization') or (T = 'finalization') or
            (T = 'end.') or (Copy(T, 1, 15) = 'initialization ') or
            (Copy(T, 1, 13) = 'finalization ');
end;

// Methoden mit Rumpf, nach Kopfzeile sortiert.
function MethodStarts(AUnitNode: TAstNode; ALineCount: Integer): TArray<TRange>;
var
  Methods : TList<TAstNode>;
  M : TAstNode;
  R : TRange;
  i, j, Cnt : Integer;
begin
  Methods := AUnitNode.FindAll(nkMethod);
  try
    SetLength(Result, Methods.Count);
    Cnt := 0;
    for M in Methods do
    begin
      if not Assigned(TAstSpans.FindBodyBlock(M)) then Continue;
      if (M.Line < 1) or (M.Line > ALineCount) then Continue;
      Result[Cnt].Method := M;
      Result[Cnt].First := M.Line;
      Inc(Cnt);
    end;
    SetLength(Result, Cnt);
  finally
    Methods.Free;
  end;
  for i := 1 to High(Result) do
  begin
    R := Result[i];
    j := i - 1;
    while (j >= 0) and (Result[j].First > R.First) do
    begin
      Result[j + 1] := Result[j];
      Dec(j);
    end;
    Result[j + 1] := R;
  end;
end;

// Jede Routine endet vor der naechsten, die letzte vor dem Unit-Schwanz.
procedure SetRangeEnds(var ARanges: TArray<TRange>; ALines: TStrings);
var
  i, Tail : Integer;
begin
  if Length(ARanges) = 0 then Exit;
  Tail := ALines.Count;
  for i := ARanges[High(ARanges)].First to ALines.Count - 1 do
    if IsUnitTail(ALines[i]) then
    begin
      Tail := i;   // Index i = Zeile i+1; die Routine endet auf Zeile i
      Break;
    end;
  for i := 0 to High(ARanges) - 1 do
    ARanges[i].Last := ARanges[i + 1].First - 1;
  ARanges[High(ARanges)].Last := Tail;
end;

// Vorfilter je Routine (Teilstring der kleingeschriebenen Zeile) - dieselbe
// Liste wie der Engine-Vorfilter je Datei (PARAM_ACCESS_WORDS).
function HasParamAccess(ALines: TStrings; const ARange: TRange): Boolean;
var
  j : Integer;
  Low, W : string;
begin
  for j := ARange.First to ARange.Last do
  begin
    Low := LowerCase(ALines[j - 1]);
    for W in PARAM_ACCESS_WORDS do
      if Pos(W, Low) > 0 then Exit(True);
  end;
  Result := False;
end;

// Beginnt in ALine ein Deklarationsabschnitt der aeusseren Routine? Nur das
// Wort am Zeilenanfang zaehlt - hinter dem 'end;' einer geschachtelten
// Routine stehen sonst nur Fortsetzungszeilen ihrer letzten Anweisung,
// Leerzeilen und Kommentare, und keine davon beginnt mit var/const/type/
// label als eigenem Wort.
function IsDeclSectionStart(const ALine: string): Boolean;
const
  WORDS: array[0..3] of string = ('var', 'const', 'type', 'label');
var
  T, W : string;
begin
  T := LowerCase(Trim(ALine));
  for W in WORDS do
    if (Copy(T, 1, Length(W)) = W) and
       ((Length(T) = Length(W)) or
        not CharInSet(T[Length(W) + 1], ['a'..'z', '0'..'9', '_'])) then
      Exit(True);
  Result := False;
end;

// Erste Zeile HINTER der geschachtelten Routine AIdx: hinter ihrem AST-Ende
// (das nur die Startzeile der letzten Anweisung kennt) bis zum ersten
// Deklarationsabschnitt der aeusseren, zum Beginn der naechsten
// geschachtelten oder bis ALimit (das 'begin' der aeusseren).
function NestedStop(ALines: TStrings; const AStarts, AEnds: TArray<Integer>;
  AIdx, ALimit: Integer): Integer;
var
  m, Stop : Integer;
begin
  Stop := ALimit;
  for m := 0 to High(AStarts) do
    if (AStarts[m] > AStarts[AIdx]) and (AStarts[m] < Stop) then
      Stop := AStarts[m];
  Result := AEnds[AIdx] + 1;
  while (Result < Stop) and not IsDeclSectionStart(ALines[Result - 1]) do
    Inc(Result);
end;

// Welche Zeilen [First..Last] der Routine zu geschachtelten Routinen
// gehoeren (Index = Zeile - First). Ohne Rumpf hinter den geschachtelten
// (AST-Sonderfall) zaehlt nur ihre AST-Spanne.
function HiddenLines(ALines: TStrings; const ARange: TRange): TArray<Boolean>;
var
  Starts, Ends : TArray<Integer>;
  Body : TAstNode;
  k, j, Limit, Stop : Integer;
begin
  SetLength(Result, ARange.Last - ARange.First + 1);
  TAstSpans.CollectNestedSpans(ARange.Method, Starts, Ends);
  if Length(Starts) = 0 then Exit;
  Body := TAstSpans.FindBodyBlock(ARange.Method);
  Limit := 0;
  if Assigned(Body) then Limit := Body.Line;
  for k := 0 to High(Starts) do
  begin
    if Limit > Starts[k] then
      Stop := NestedStop(ALines, Starts, Ends, k, Limit)
    else
      Stop := Ends[k] + 1;
    for j := Max(Starts[k], ARange.First) to Min(Stop - 1, ARange.Last) do
      Result[j - ARange.First] := True;
  end;
end;

// Quelltext der Routine; die Zeilen geschachtelter Routinen bleiben leer,
// damit die Zeilenzaehlung stimmt, und landen in AHidden.
function RoutineText(ALines: TStrings; const ARange: TRange;
  out AHidden: string): string;
var
  Sb, Hidden : TStringBuilder;
  Flags : TArray<Boolean>;
  j : Integer;
begin
  Flags := HiddenLines(ALines, ARange);
  Sb := TStringBuilder.Create;
  Hidden := TStringBuilder.Create;
  try
    for j := ARange.First to ARange.Last do
    begin
      if Flags[j - ARange.First] then
        Hidden.Append(ALines[j - 1]).Append(string(#10))
      else
        Sb.Append(ALines[j - 1]);
      Sb.Append(string(#10));
    end;
    Result := Sb.ToString;
    AHidden := Hidden.ToString;
  finally
    Hidden.Free;
    Sb.Free;
  end;
end;

class procedure TParamNameMismatchDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  AContext: TAnalyzeContext);
var
  Lines  : TStringList;
  Cached : Boolean;
  Ranges : TArray<TRange>;
  R      : TRange;
  Issue  : TParamNameIssue;
  Code, Hidden : string;
begin
  if not Assigned(UnitNode) then Exit;
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if not Assigned(Lines) then Exit;
  try
    Ranges := MethodStarts(UnitNode, Lines.Count);
    SetRangeEnds(Ranges, Lines);
    for R in Ranges do
    begin
      if (R.Last < R.First) or not HasParamAccess(Lines, R) then Continue;
      Code := RoutineText(Lines, R, Hidden);
      for Issue in TParamNameScan.ScanRoutine(Code, R.First, Hidden) do
        Results.Add(TLeakFinding.New(FileName, R.Method.Name, Issue.Line,
          TParamNameScan.MessageOf(Issue), fkParamNameMismatch));
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
