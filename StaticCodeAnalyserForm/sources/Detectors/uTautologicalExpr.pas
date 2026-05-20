unit uTautologicalExpr;

// Detector: tautologische binaere Ausdruecke wie `x = x`, `a and a`,
// `(b or b)`, `(p <> p)`. Klassischer Copy-Paste-Bug oder vergessener
// Index (`arr[i] = arr[j]` -> `arr[i] = arr[i]` durch Tippfehler).
//
// Erkennung:
//   * File-Scan (analog uWithStatement / uReversedForRange) - der Parser
//     flacht Ausdruecke in Token-Strings, ein verlaesslicher AST-Pattern-
//     Match auf Binary-Op ist hier teuer.
//   * Pattern: `<expr> <op> <expr>` wobei beide `<expr>` identisch sind
//     (case-insensitive, whitespace-tolerant) und `<op>` aus der Liste
//     der relevanten Operatoren stammt: `=`, `<>`, `and`, `or`, `<`, `>`,
//     `<=`, `>=`, `xor`. Mathematische Operatoren (`+`, `-`, ...) sind
//     ausgeschlossen, weil `x + x` und `a * a` legitime Idiome sind.
//   * Strings/Kommentare ueberspringen (analog Lexer in uTodoComment).
//
// Severity: lsError (das ist ein echter Bug, kein Stil-Issue).

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TTautologicalExprDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  uFileTextCache;

const
  EMIT_SEVERITY = lsError;

function IsIdentChar(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z','a'..'z','0'..'9','_','.']);
end;

// Normalisiert eine Side-Expression: trim + whitespace collapse + lowercase.
// WICHTIG: String-Literal-Inhalte werden CASE-PRESERVING durchgereicht -
// `'F'` bleibt `'F'`, nicht `'f'`. Sonst flaggt ein idiomatic case-check
// wie `(c = 'A') or (c = 'a')` faelschlich als Tautologie. Pascal-Escape
// `''` (verdoppeltes Apostroph) bleibt im String-State.
function Norm(const S: string): string;
var
  i, n   : Integer;
  PrevWs : Boolean;
  InStr  : Boolean;
  C      : Char;
begin
  Result := '';
  PrevWs := True;
  InStr  := False;
  n      := Length(S);
  i      := 1;
  while i <= n do
  begin
    C := S[i];
    if InStr then
    begin
      Result := Result + C;
      PrevWs := False;
      if C = '''' then
      begin
        if (i < n) and (S[i + 1] = '''') then
        begin
          // Pascal-Escape `''` innerhalb eines Strings -> beides emittieren,
          // im String-State bleiben.
          Result := Result + '''';
          Inc(i, 2);
          Continue;
        end;
        // Schliessendes Apostroph - String-State verlassen.
        InStr := False;
      end;
      Inc(i);
      Continue;
    end;
    // Ausserhalb eines String-Literals.
    if C = '''' then
    begin
      Result := Result + C;
      InStr  := True;
      PrevWs := False;
      Inc(i);
      Continue;
    end;
    if CharInSet(C, [' ', #9]) then
    begin
      if not PrevWs then Result := Result + ' ';
      PrevWs := True;
    end
    else
    begin
      Result := Result + LowerCase(C);
      PrevWs := False;
    end;
    Inc(i);
  end;
  Result := Trim(Result);
end;

// Entfernt String-Literale und Kommentare aus einer Code-Zeile - alle
// String- und Comment-Bereiche werden durch Leerzeichen ersetzt, damit
// Positionen / Spalten erhalten bleiben aber der nachgelagerte Operator-
// Scan nichts mehr darin findet.
function StripStringsAndComments(const Line: string;
  var InBlockComm, InParenStarComm: Boolean): string;
var
  i, n, p : Integer;
  InStr   : Boolean;
  c       : Char;
begin
  SetLength(Result, Length(Line));
  for i := 1 to Length(Line) do Result[i] := Line[i];
  n := Length(Line);
  i := 1;
  InStr := False;
  while i <= n do
  begin
    if InBlockComm then
    begin
      p := Pos('}', Line, i);
      if p = 0 then
      begin
        // ganze Zeile in Kommentar -> ausblanken
        for var k := i to n do Result[k] := ' ';
        Exit;
      end;
      for var k := i to p do Result[k] := ' ';
      InBlockComm := False;
      i := p + 1;
      Continue;
    end;
    if InParenStarComm then
    begin
      p := Pos('*)', Line, i);
      if p = 0 then
      begin
        for var k := i to n do Result[k] := ' ';
        Exit;
      end;
      for var k := i to p + 1 do Result[k] := ' ';
      InParenStarComm := False;
      i := p + 2;
      Continue;
    end;

    c := Line[i];
    if InStr then
    begin
      Result[i] := ' ';
      if c = '''' then
      begin
        if (i < n) and (Line[i+1] = '''') then
        begin
          Result[i+1] := ' ';
          Inc(i, 2);
        end
        else
        begin
          InStr := False;
          Inc(i);
        end;
      end
      else Inc(i);
      Continue;
    end;

    case c of
      '''':
        begin
          Result[i] := ' ';
          InStr := True;
          Inc(i);
          Continue;
        end;
      '/':
        if (i < n) and (Line[i+1] = '/') then
        begin
          // Rest der Zeile ist Line-Comment -> ausblanken
          for var k := i to n do Result[k] := ' ';
          Exit;
        end;
      '{':
        begin
          p := Pos('}', Line, i + 1);
          if p = 0 then
          begin
            for var k := i to n do Result[k] := ' ';
            InBlockComm := True;
            Exit;
          end;
          for var k := i to p do Result[k] := ' ';
          i := p + 1;
          Continue;
        end;
      '(':
        if (i < n) and (Line[i+1] = '*') then
        begin
          p := Pos('*)', Line, i + 2);
          if p = 0 then
          begin
            for var k := i to n do Result[k] := ' ';
            InParenStarComm := True;
            Exit;
          end;
          for var k := i to p + 1 do Result[k] := ' ';
          i := p + 2;
          Continue;
        end;
    end;

    Inc(i);
  end;
end;

// Strip alle Pascal-Prefixe (`if `, `while `, `until `, `begin `, ...) vom
// linken Rand eines Lhs-Ausdrucks, damit `if a` zu `a` wird.
function StripLhsPrefix(const S: string): string;
const
  PREFIXES : array[0..7] of string =
    ('if ', 'while ', 'until ', 'begin ', 'then ', 'do ', 'and ', 'or ');
var
  Low : string;
  Changed : Boolean;
  Pref : string;
  SP : Integer;
begin
  Result := S;
  repeat
    Changed := False;
    Low := LowerCase(Result);
    for Pref in PREFIXES do
    begin
      SP := Pos(Pref, Low);
      if SP > 0 then
      begin
        // Alles bis nach dem Praefix wegschneiden
        Result  := Copy(Result, SP + Length(Pref), MaxInt);
        Changed := True;
        Break;
      end;
    end;
  until not Changed;
  Result := Trim(Result);
end;

// Sucht in einer Code-Zeile nach `<lhs> <op> <rhs>`-Pattern mit lhs == rhs
// und op aus der relevanten Liste. Strings/Kommentare werden vorab
// ausgeblendet, damit Op-Vorkommen darin nicht falsch matchen.
function ScanForTautology(const Line: string; var InBlockComm,
  InParenStarComm: Boolean; out MatchCol: Integer; out Detail: string): Boolean;
var
  Clean : string;
  p     : Integer;
const
  OPS : array[0..2] of string = (' and ', ' or ', ' xor ');
  CMP_OPS : array[0..5] of string = ('<=', '>=', '<>', '=', '<', '>');
begin
  Result := False;
  MatchCol := 0;
  Detail := '';

  // Phase 1: Strings + Kommentare ausblanken.
  Clean := StripStringsAndComments(Line, InBlockComm, InParenStarComm);

  // Phase 2: Boolean-Operatoren (` and ` / ` or ` / ` xor `).
  // Op-Position + Stop-Position werden auf Clean gesucht (Strings sind
  // ausgeblendet -> kein false-match auf Token innerhalb String-Literalen).
  // Die finalen Lhs/Rhs-Strings kommen aus Line - so behaelt der
  // Norm()-Vergleich den Original-String-Inhalt, und z.B.
  //   `Foo('function ') or Foo('function(')`
  // wird NICHT als tautologisch gemeldet (Strings sind unterschiedlich).
  for var Op in OPS do
  begin
    p := Pos(Op, LowerCase(Clean));
    if p > 0 then
    begin
      var Lhs       := Copy(Line, 1, p - 1);
      var RhsStart  := p + Length(Op);
      var Rhs       := Copy(Line,  RhsStart, MaxInt);
      var RhsClean  := Copy(Clean, RhsStart, MaxInt);
      // Rhs-Ende beim naechsten Pascal-Stopwort - in RhsClean suchen,
      // damit Stops innerhalb String-Literalen nicht falsch matchen.
      var RhsLower  := LowerCase(RhsClean);
      for var Stop in [';', ' then ', ' then'#13, ' do ', ' do'#13,
                       ' begin', ' and ', ' or '] do
      begin
        var SP := Pos(Stop, RhsLower);
        if SP > 0 then
        begin
          Rhs      := Copy(Rhs,      1, SP - 1);
          RhsLower := Copy(RhsLower, 1, SP - 1);
        end;
      end;
      // Lhs-Prefix-Strip (z.B. `  if a` -> `a`)
      Lhs := StripLhsPrefix(Lhs);
      Rhs := Trim(Rhs);
      if (Lhs <> '') and (Rhs <> '') and (Norm(Lhs) = Norm(Rhs)) then
      begin
        MatchCol := p;
        Detail := Lhs + Op + Rhs;
        Exit(True);
      end;
    end;
  end;

  // Phase 3: Vergleichs-Operatoren mit Whitespace-Kontext (` = `, ` <> ` ...).
  // Reihenfolge wichtig: `<=`/`>=`/`<>` vor `<`/`>`/`=`, sonst matcht der
  // einstellige Variant zuerst.
  //
  // Wie in Phase 2: Op/Stop-Suche auf Clean, finale Lhs/Rhs aus Line.
  for var Op in CMP_OPS do
  begin
    var Search := ' ' + Op + ' ';
    p := Pos(Search, Clean);
    while p > 0 do
    begin
      var Lhs       := Copy(Line, 1, p);
      var RhsStart  := p + Length(Search);
      var Rhs       := Copy(Line,  RhsStart, MaxInt);
      var RhsClean  := Copy(Clean, RhsStart, MaxInt);
      var RhsLower  := LowerCase(RhsClean);
      for var Stop in [' then', ' do', ';', ')', ' and ', ' or ', ' xor '] do
      begin
        var SP := Pos(Stop, RhsLower);
        if SP > 0 then
        begin
          Rhs      := Copy(Rhs,      1, SP - 1);
          RhsLower := Copy(RhsLower, 1, SP - 1);
        end;
      end;
      Lhs := StripLhsPrefix(Lhs);
      Rhs := Trim(Rhs);
      // Doppelt-genullt-vermeiden: `:= x` darf nicht als `= x` matchen.
      // Da wir Op mit umgebenden Spaces suchen (` = `), trifft das nicht zu -
      // bei `x := x` waere die Such-Subsequence `:= x` ohne Vor-Space.
      if (Lhs <> '') and (Rhs <> '') and (Norm(Lhs) = Norm(Rhs)) then
      begin
        MatchCol := p + 1;
        Detail := Lhs + ' ' + Op + ' ' + Rhs;
        Exit(True);
      end;
      p := Pos(Search, Clean, p + 1);
    end;
  end;
end;

class procedure TTautologicalExprDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines : TStringList;
  i : Integer;
  MatchCol : Integer;
  Detail : string;
  Line : string;
  InBlockComm, InParenStarComm : Boolean;
  F : TLeakFinding;
  Cached : Boolean;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try

    // Block-Kommentare spannen ueber Zeilen, daher State mitfuehren.
    // StringLiterale spannen in Pascal nicht ueber Zeilen -> per Line lokal.
    InBlockComm := False;
    InParenStarComm := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];
      if ScanForTautology(Line, InBlockComm, InParenStarComm,
                          MatchCol, Detail) then
      begin
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := '';
        F.LineNumber := IntToStr(i + 1);
        F.MissingVar := Format(
          'Tautological expression: %s (LHS == RHS - copy-paste bug?)',
          [Detail]);
        F.SetKind(fkTautologicalBoolExpr);
        Results.Add(F);
      end;
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
