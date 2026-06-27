unit uCaseStatementSize;

// Detektor fuer ueberlange `case ... of`-Statements.
//
// SonarDelphi-Aequivalent: communitydelphi:CaseStatementSize. Ein
// `case` mit vielen Branches verbirgt typischerweise einen Polymorphismus-
// oder Strategie-Pattern-Hint: der Code waere lesbarer wenn die N
// Faelle in Klassen / Methoden-Tabellen / Dictionary<Key, Proc>
// verteilt waeren.
//
// Schwelle: Default 10 Branches, konfigurierbar via INI
// [Detectors] MaxCaseBranches.
//
// Erkennung:
//   * Kommentbereinigtes Joinen
//   * Suche nach `case`-Wort gefolgt von `<expr> of`
//   * Zaehle Label-Lines: jede Zeile, die mit `<Wert>:` (oder mit
//     `<Wert1>, <Wert2>:`) endet, ist ein Branch.
//   * Bei >= Schwelle melden.
//
// Heuristik bewusst lexikalisch - der Parser-State (Begin/End-Tiefe
// in den Branches) muss nicht getrackt werden, weil Case-Branches
// strukturell auf eigene Zeilen kommen.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TCaseStatementSizeDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, CyclomaticComplexity, DeepNesting, GroupedDeclaration, IfElseBegin, LegacyInitializationSection, LongMethod, NilComparison, RedundantJump, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils,
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;
  // Konfigurierbar via INI [Detectors] MaxCaseBranches=N.
  // DetectorMaxCaseBranches in uSCAConsts wird von RepoSettings gesetzt;
  // Default 10. <=0 = Fallback auf 10.
  DEFAULT_MAX_BRANCH_FALLBACK = 10;

function IsIdent(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z','a'..'z','0'..'9','_']);
end;

function StripFileComments(Lines: TStringList; out LineForChar: TArray<Integer>): string;
var
  Buf            : TStringBuilder;
  i, n, j        : Integer;
  Line           : string;
  InBlk, InParen : Boolean;
  InStr          : Boolean;
  c              : Char;
  pClose         : Integer;
  Chars          : TList<Integer>;
begin
  Buf := TStringBuilder.Create;
  Chars := TList<Integer>.Create;
  try
    InBlk := False; InParen := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];
      InStr := False;
      j := 1;
      n := Length(Line);
      while j <= n do
      begin
        if InBlk then
        begin
          pClose := PosEx('}', Line, j);
          if pClose = 0 then Break;
          InBlk := False;
          j := pClose + 1; Continue;
        end;
        if InParen then
        begin
          pClose := PosEx('*)', Line, j);
          if pClose = 0 then Break;
          InParen := False;
          j := pClose + 2; Continue;
        end;
        c := Line[j];
        if InStr then
        begin
          Buf.Append(c); Chars.Add(i);
          if c = '''' then
          begin
            if (j < n) and (Line[j + 1] = '''') then
            begin Buf.Append(''''); Chars.Add(i); Inc(j, 2); end
            else begin InStr := False; Inc(j); end;
          end
          else Inc(j);
          Continue;
        end;
        if c = '''' then
        begin Buf.Append(c); Chars.Add(i); InStr := True; Inc(j); Continue; end;
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
    Chars.Free;
    Buf.Free;
  end;
end;

function FindOfAfter(const Code: string; Start: Integer): Integer;
var
  i : Integer;
begin
  Result := 0;
  i := Start;
  while i + 1 <= Length(Code) do
  begin
    if CharInSet(Code[i], ['o','O']) and
       SameText(Copy(Code, i, 2), 'of') and
       ((i = 1) or not IsIdent(Code[i - 1])) and
       ((i + 2 > Length(Code)) or not IsIdent(Code[i + 2])) then
    begin
      Result := i;
      Exit;
    end;
    Inc(i);
  end;
end;

// Findet den schliessenden `end` eines case-Blocks ab Position Start
// (= direkt nach `of`). Liefert die Position des matching `end`, 0 wenn
// nicht gefunden. Heuristisches Tiefe-Tracking ueber `begin`/`case`/
// `try`/`record` vs `end` - reicht fuer "normalen" Code.
function FindMatchingEnd(const Code: string; Start: Integer): Integer;
var
  i, q, depth : Integer;
  W           : string;
begin
  Result := 0;
  i := Start;
  depth := 1;
  while i <= Length(Code) do
  begin
    while (i <= Length(Code)) and not IsIdent(Code[i]) do Inc(i);
    if i > Length(Code) then Exit;
    q := i;
    while (q <= Length(Code)) and IsIdent(Code[q]) do Inc(q);
    W := LowerCase(Copy(Code, i, q - i));
    if (W = 'begin') or (W = 'case') or (W = 'try') or (W = 'record') then
      Inc(depth)
    else if W = 'end' then
    begin
      Dec(depth);
      if depth = 0 then
      begin
        Result := i;
        Exit;
      end;
    end;
    i := q;
  end;
end;

function CountBranches(const Code: string; pFrom, pTo: Integer): Integer;
var
  p, paren : Integer;
  c        : Char;
begin
  Result := 0;
  paren := 0;
  p := pFrom;
  while p < pTo do
  begin
    c := Code[p];
    if c = '(' then Inc(paren)
    else if c = ')' then begin if paren > 0 then Dec(paren); end
    else if c = ':' then
    begin
      if (paren = 0) and ((p + 1 > Length(Code)) or (Code[p + 1] <> '=')) then
        Inc(Result);
    end;
    Inc(p);
  end;
end;

class procedure TCaseStatementSizeDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines       : TStringList;
  Cached      : Boolean;
  Code        : string;
  Lwr         : string;
  LineFor     : TArray<Integer>;
  pCase       : Integer;
  pOf, pEnd   : Integer;
  i           : Integer;
  BranchCount : Integer;
  LineNumber  : Integer;
  MaxBr       : Integer;
  F           : TLeakFinding;
begin
  // Konfigurierbar via INI [Detectors] MaxCaseBranches=N, Default 10.
  MaxBr := DetectorMaxCaseBranches;
  if MaxBr <= 0 then MaxBr := DEFAULT_MAX_BRANCH_FALLBACK;
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    Code := StripFileComments(Lines, LineFor);
    Lwr := LowerCase(Code);
    pCase := 1;
    while True do
    begin
      pCase := PosEx('case', Lwr, pCase);
      if pCase = 0 then Break;
      if (pCase > 1) and IsIdent(Code[pCase - 1]) then
      begin Inc(pCase); Continue; end;
      if (pCase + 4 <= Length(Code)) and IsIdent(Code[pCase + 4]) then
      begin Inc(pCase); Continue; end;
      pOf := FindOfAfter(Code, pCase + 4);
      if pOf = 0 then begin Inc(pCase, 4); Continue; end;
      pEnd := FindMatchingEnd(Code, pOf + 2);
      if pEnd = 0 then begin Inc(pCase, 4); Continue; end;
      BranchCount := CountBranches(Code, pOf + 2, pEnd);
      if BranchCount >= MaxBr then
      begin
        i := pCase - 1;
        if (i >= 0) and (i < Length(LineFor)) then
          LineNumber := LineFor[i]
        else
          LineNumber := 0;
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := '';
        F.LineNumber := IntToStr(LineNumber + 1);
        F.MissingVar := Format(
          '`case` statement with %d branches (>= %d) - consider ' +
          'polymorphism, a dispatch table, or split into smaller ' +
          'cases.', [BranchCount, MaxBr]);
        F.SetKind(fkCaseStatementSize);
        Results.Add(F);
      end;
      pCase := pEnd + 3;
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
