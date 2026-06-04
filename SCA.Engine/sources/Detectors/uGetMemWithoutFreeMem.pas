unit uGetMemWithoutFreeMem;

// Detektor: GetMem / AllocMem / ReallocMem ohne paired FreeMem im
// gleichen Routinen-Body.
//
// Pattern (Bug, klassischer Memory-Leak in Low-Level Delphi-Code):
//   GetMem(P, 1024);
//   FillBuffer(P);          // <-- wirft -> P bleibt fuer immer haengen
//   ProcessBuffer(P);
//   FreeMem(P);
//
// Korrekt:
//   GetMem(P, 1024);
//   try
//     FillBuffer(P);
//   finally
//     FreeMem(P);
//   end;
//
// Folge: Jede Exception zwischen GetMem und FreeMem leakt den allokierten
// Speicher dauerhaft. mORMot benutzt GetMem an ueber 20 Stellen in core/
// fuer hochperformante Buffer-Manipulation - jedes Vorkommen ohne
// try/finally-Wrapper ist ein Production-Leak.
//
// Erkennung (lexisch, narrow):
//   * Strip Strings + Kommentare.
//   * Pro Vorkommen von GetMem|AllocMem|ReallocMem:
//     - 400 Zeichen Lookahead-Fenster nach dem Call.
//     - Erwarte FreeMem|FreeMemAndNil im Fenster.
//     - Erwarte `try` VOR dem FreeMem (try kommt VOR FreeMem im Snippet).
//     - Wenn FreeMem fehlt -> Skip (custom Allocator oder Ownership-Transfer).
//     - Wenn FreeMem da ist aber kein try davor -> Finding.
//
// Limitierungen:
//   * Single-File-lexisch. Keine AST-Analyse.
//   * GetMem in Konstruktoren mit FreeMem in Destruktoren wird nicht erkannt
//     - dafuer ist das Lookahead-Fenster zu klein, gewollt: Ownership-
//     Transfer braucht andere Patterns (FieldLeak / LeakInConstructor).
//   * Custom-Allocators (GetMemoryManager swapping) sind nicht modelliert.
//
// Schweregrad: lsWarning - Memory-Leak.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TGetMemWithoutFreeMemDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

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

class procedure TGetMemWithoutFreeMemDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
const
  LOOK_AHEAD = 400;  // groesseres Fenster als UnpairedLock - Buffer-Code
                     // hat oft mehr Zeilen zwischen Acquire und Release.
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
  TryPos   : Integer;
  FreePos  : Integer;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    Code := StripStringsAndComments(Lines, LineFor);
    CodeLow := LowerCase(Code);

    // Pattern: GetMem(P, n) / AllocMem(n) / ReallocMem(P, n).
    RE := TRegEx.Create('(?i)\b(GetMem|AllocMem|ReallocMem)\s*\(');
    for M in RE.Matches(Code) do
    begin
      AfterPos := M.Index + M.Length;
      if AfterPos > Length(Code) then Continue;

      // Snippet nach dem Alloc (max 400 Zeichen) lowercased.
      Snippet := Copy(CodeLow, AfterPos, LOOK_AHEAD);
      TryPos  := Pos('try',     Snippet);
      FreePos := Pos('freemem', Snippet);
      // Kein Folge-FreeMem -> Ownership-Transfer / Custom-Allocator
      // -> Skip (nicht flaggen).
      if FreePos = 0 then Continue;
      // try kommt VOR FreeMem -> Pattern OK
      if (TryPos > 0) and (TryPos < FreePos) then Continue;

      LineNo := LineForPos(LineFor, M.Index);
      if LineNo <= 0 then LineNo := 1;

      Detail := Format(
        '%s without surrounding try/finally - exception leaks the buffer',
        [Trim(M.Groups[1].Value)]);

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(LineNo);
      F.MissingVar := Detail;
      F.SetKind(fkGetMemWithoutFreeMem);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
