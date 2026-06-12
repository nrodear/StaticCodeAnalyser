unit uUnpairedLock;

// Detektor: Lock/EnterCriticalSection ohne paired UnLock/Leave* im
// try/finally-Block.
//
// Pattern (Bug, concurrency hotspot - mORMot/RTL):
//   FLocker.Lock;
//   DoStuff;            // <-- wirft -> Lock bleibt fuer immer haengen
//   FLocker.UnLock;
//
//   EnterCriticalSection(CS);
//   DoStuff;
//   LeaveCriticalSection(CS);
//
// Korrekt:
//   FLocker.Lock;
//   try
//     DoStuff;
//   finally
//     FLocker.UnLock;
//   end;
//
//   EnterCriticalSection(CS);
//   try
//     DoStuff;
//   finally
//     LeaveCriticalSection(CS);
//   end;
//
// Folge: Exception zwischen Lock und UnLock laesst den Lock fuer immer
// gehalten - Deadlock garantiert beim naechsten Acquire-Versuch.
// mORMot benutzt diese Locking-API ueber 200x in core/os/threads, jeder
// fehlende try/finally-Wrapper ist ein Crash-Latent.
//
// Erkennung (lexisch, narrow):
//   * Strip Strings + Kommentare.
//   * Pro Methode (lexisch via "begin..end"-Klammerung waere zu komplex;
//     stattdessen file-weite Suche):
//     - Finde alle Vorkommen von `<id>.Lock;` oder `<id>.Acquire;` oder
//       `EnterCriticalSection(<id>)` oder `RTLeventWaitFor(<id>)`.
//     - In den 200 Bytes danach: erwarte `try` (case-insensitive).
//     - Fehlt das `try` UND es kommt vor `end;` ein `UnLock`/`Leave*`,
//       war es ein bare-Lock - Finding.
//   * Nur dann flaggen wenn der UnLock-Aufruf NICHT direkt vor `end;`
//     in einem finally-Block sitzt.
//
// Limitierungen:
//   * Single-File-lexisch. Keine AST-Analyse von Try-Finally-Schachtelung.
//   * Re-Entrant locks die bewusst ohne try/finally arbeiten (Performance-
//     Pfad) muessen via `// noinspection UnpairedLock` suppressed werden.
//
// Schweregrad: lsWarning - Concurrency-Bug.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TUnpairedLockDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, ConsecutiveSection, CyclomaticComplexity, DeepNesting, GroupedDeclaration, IfElseBegin, LongMethod, NilComparison, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.RegularExpressions, System.StrUtils,
  uFileTextCache;

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

class procedure TUnpairedLockDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
const
  LOOK_AHEAD = 200;  // Bytes nach dem Lock-Aufruf
var
  Lines    : TStringList;
  Cached   : Boolean;
  Code     : string;
  CodeLow  : string;
  LineFor  : TArray<Integer>;
  RE       : TRegEx;
  M        : TMatch;
  AfterPos : Integer;
  Snippet  : string;
  LineNo   : Integer;
  F        : TLeakFinding;
  Detail   : string;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    Code := StripStringsAndComments(Lines, LineFor);
    CodeLow := LowerCase(Code);

    // Pattern: `<id>.Lock;` oder `<id>.Acquire;` oder `EnterCriticalSection(`
    // oder mORMot's `RTLeventWaitFor(` - jeweils mit folgendem try-fehlt-Check.
    RE := TRegEx.Create(
      '(?i)\b((?:\w+\.)?(?:Lock|Acquire|EnterCriticalSection)|EnterCriticalSection)\s*[\(;]');
    for M in RE.Matches(Code) do
    begin
      AfterPos := M.Index + M.Length;
      if AfterPos > Length(Code) then Continue;

      // Snippet nach dem Lock-Aufruf (max 200 Zeichen) lowercased.
      Snippet := Copy(CodeLow, AfterPos, LOOK_AHEAD);
      // Wenn `try` direkt folgt (mit beliebigen Whitespace + ';' / EOL
      // dazwischen), ist es korrekt. Wir wollen NUR Pattern wo bis zum
      // naechsten `unlock`/`leavecriticalsection` kein `try` kommt.
      var TryPos    := Pos('try', Snippet);
      var UnlockPos := Pos('unlock',     Snippet);
      if UnlockPos = 0 then
        UnlockPos := Pos('leavecriticalsection', Snippet);
      if UnlockPos = 0 then
        UnlockPos := Pos('release',     Snippet);
      // Kein Folge-Unlock gefunden -> entweder uebergebener Lock-Helper
      // oder unbekanntes Pattern -> Skip (nicht flaggen).
      if UnlockPos = 0 then Continue;
      // try kommt VOR unlock -> Pattern OK
      if (TryPos > 0) and (TryPos < UnlockPos) then Continue;

      LineNo := LineForPos(LineFor, M.Index);
      if LineNo <= 0 then LineNo := 1;

      Detail := Format(
        'Lock/Enter without surrounding try/finally - exception leaks the lock (%s)',
        [Trim(M.Groups[1].Value)]);

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(LineNo);
      F.MissingVar := Detail;
      F.SetKind(fkUnpairedLock);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
