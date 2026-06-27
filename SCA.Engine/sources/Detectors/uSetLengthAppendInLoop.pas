unit uSetLengthAppendInLoop;

// Detektor: SetLength(arr, Length(arr) + 1) innerhalb einer Schleife.
//
// Pattern (Performance-Bug, O(n*n) statt O(n)):
//   for i := 0 to Source.Count - 1 do
//   begin
//     SetLength(Dest, Length(Dest) + 1);   // <-- realloc auf JEDER Iteration
//     Dest[High(Dest)] := Source[i];
//   end;
//
// Korrekt:
//   SetLength(Dest, Source.Count);         // einmal vorab
//   for i := 0 to Source.Count - 1 do
//     Dest[i] := Source[i];
//
// Folge: Realloc auf jeder Iteration kopiert n*(n+1)/2 Elemente statt n.
// Bei 10000 Elementen: 50_005_000 statt 10_000 Operationen - 5000x langsamer.
// mORMot's Performance-Profile flagt diesen Pattern als haeufigsten
// Real-World-Bottleneck in user-code, der die Library benutzt.
//
// Erkennung (lexisch, narrow):
//   * Strip Strings + Kommentare.
//   * Pro Vorkommen von `for|while|repeat`:
//     - 600 Zeichen Lookahead-Fenster (Schleifen-Body).
//     - Suche `SetLength(<id>, Length(<id>) + <n>)` ODER `SetLength(<id>,
//       <id>.Count + 1)`-style Pattern im Fenster.
//     - Wenn gefunden -> Finding (Position des SetLength-Calls).
//
// Limitierungen:
//   * Single-File-lexisch. Fenster-basiert (600 Zeichen) - sehr lange
//     Schleifen werden nicht voll erfasst.
//   * `SetLength(arr, Length(arr) + Constant)` (Block-Grow) wird ebenfalls
//     geflaggt - das ist OK weil Block-Grow innerhalb einer Schleife
//     ebenfalls suboptimal ist (vorher rechnen + einmal SetLength).
//
// Schweregrad: lsWarning - Performance-Bug, kein Crash aber massive
// Skalierungsfalle.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TSetLengthAppendInLoopDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, ConsecutiveSection, CyclomaticComplexity, DeepNesting, GroupedDeclaration, IfElseBegin, LongMethod, NilComparison, RedundantBoolean, RedundantJump, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.RegularExpressions, System.StrUtils,
  uFileTextCache;

var
  // Lazy-Cache (Round 11): konstante Patterns einmalig kompilieren.
  CachedLoopRE : TRegEx;
  CachedGrowRE : TRegEx;
  CachedReInit : Boolean = False;

procedure EnsureRegexCacheBuilt;
begin
  if CachedReInit then Exit;
  CachedLoopRE := TRegEx.Create('(?i)\b(for|while|repeat)\b');
  CachedGrowRE := TRegEx.Create(
    '(?i)\bSetLength\s*\(\s*(\w+)\s*,\s*Length\s*\(\s*(\w+)\s*\)\s*\+');
  CachedReInit := True;
end;

function StripStringsAndComments(Lines: TStringList; out LineForChar: TArray<Integer>): string;
var
  Buf            : TStringBuilder;
  Chars          : TList<Integer>;
  i, n, j        : Integer;
  Line           : string;
  InBlk, InParen : Boolean;
  InStr          : Boolean;
  c              : Char;
  pClose         : Integer;
begin
  Buf := TStringBuilder.Create;
  Chars := TList<Integer>.Create;
  try
    InBlk := False; InParen := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i]; InStr := False; j := 1; n := Length(Line);
      while j <= n do
      begin
        if InBlk then
        begin
          pClose := PosEx('}', Line, j);
          if pClose = 0 then Break;
          InBlk := False; j := pClose + 1; Continue;
        end;
        if InParen then
        begin
          pClose := PosEx('*)', Line, j);
          if pClose = 0 then Break;
          InParen := False; j := pClose + 2; Continue;
        end;
        c := Line[j];
        if InStr then
        begin
          Buf.Append(' '); Chars.Add(i);
          if c = '''' then
          begin
            if (j < n) and (Line[j + 1] = '''') then
            begin Buf.Append(' '); Chars.Add(i); Inc(j, 2); end
            else begin InStr := False; Inc(j); end;
          end else Inc(j);
          Continue;
        end;
        if c = '''' then
        begin Buf.Append(' '); Chars.Add(i); InStr := True; Inc(j); Continue; end;
        if (c = '/') and (j < n) and (Line[j + 1] = '/') then Break;
        if c = '{' then
        begin
          pClose := PosEx('}', Line, j + 1);
          if pClose = 0 then begin InBlk := True; Break; end;
          j := pClose + 1; Continue;
        end;
        if (c = '(') and (j < n) and (Line[j + 1] = '*') then
        begin
          pClose := PosEx('*)', Line, j + 2);
          if pClose = 0 then begin InParen := True; Break; end;
          j := pClose + 2; Continue;
        end;
        Buf.Append(c); Chars.Add(i);
        Inc(j);
      end;
      Buf.Append(#10); Chars.Add(i);
    end;
    Result := Buf.ToString;
    LineForChar := Chars.ToArray;
  finally
    Chars.Free; Buf.Free;
  end;
end;

function LineForPos(const LineFor: TArray<Integer>; APos: Integer): Integer;
begin
  if (APos >= 1) and (APos - 1 < Length(LineFor)) then
    Result := LineFor[APos - 1] + 1
  else
    Result := 0;
end;

class procedure TSetLengthAppendInLoopDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
const
  LOOK_AHEAD = 600;  // groesseres Fenster als die anderen Detektoren -
                     // Schleifen-Bodies sind oft mehrzeilig.
var
  Lines        : TStringList;
  Cached       : Boolean;
  Code         : string;
  LineFor      : TArray<Integer>;
  LoopM        : TMatch;
  GrowM        : TMatch;
  Snippet      : string;
  ArrayName    : string;
  GrowName     : string;
  LineNo       : Integer;
  F            : TLeakFinding;
  Detail       : string;
  AbsolutePos  : Integer;
begin
  EnsureRegexCacheBuilt;
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    Code := StripStringsAndComments(Lines, LineFor);

    for LoopM in CachedLoopRE.Matches(Code) do
    begin
      AbsolutePos := LoopM.Index + LoopM.Length;
      if AbsolutePos > Length(Code) then Continue;
      Snippet := Copy(Code, AbsolutePos, LOOK_AHEAD);

      for GrowM in CachedGrowRE.Matches(Snippet) do
      begin
        ArrayName := GrowM.Groups[1].Value;
        GrowName  := GrowM.Groups[2].Value;
        // Nur flaggen wenn das Array auf das gewachsen wird = dasselbe
        // Array dessen Length() abgefragt wurde.
        if not SameText(ArrayName, GrowName) then Continue;

        LineNo := LineForPos(LineFor, AbsolutePos + GrowM.Index - 1);
        if LineNo <= 0 then LineNo := 1;

        Detail := Format(
          'SetLength(%s, Length(%s) + ...) inside a %s loop - quadratic realloc; grow once before the loop',
          [ArrayName, GrowName, LowerCase(LoopM.Groups[1].Value)]);

        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := '';
        F.LineNumber := IntToStr(LineNo);
        F.MissingVar := Detail;
        F.SetKind(fkSetLengthAppendInLoop);
        Results.Add(F);
        // Nur das ERSTE Grow pro Loop melden um Spam zu vermeiden.
        Break;
      end;
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
