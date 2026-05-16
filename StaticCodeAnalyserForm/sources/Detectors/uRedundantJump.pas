unit uRedundantJump;

// Detektor fuer redundante `Exit;`/`Continue;`/`Break;` direkt vor dem
// schliessenden `end;` ihres Bloecks.
//
// SonarDelphi-Aequivalent: communitydelphi:RedundantJump. Wenn `Exit`
// das letzte Statement vor `end` ist, fliegt es ohne Effekt - die
// Methode endet ja sowieso. Aequivalent fuer `Continue`/`Break` vor
// dem `end` einer Loop.
//
// Erkennung: kommentbereinigtes Joinen wie in uEmptyInterface,
// dann Pattern `(Exit|Continue|Break);` -> nur Whitespace -> `end`
// Wort. String-/Kommentar-Awareness durch das Joining.
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TRedundantJumpDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  System.StrUtils,
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;

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

// Sucht Wort `Keyword;` direkt gefolgt von Whitespace und `end`.
procedure ScanRedundantJumpKw(const Code, Lwr, Kw: string; KwLen: Integer;
  LineFor: TArray<Integer>; Results: TObjectList<TLeakFinding>;
  const FileName: string);
var
  p, q, k       : Integer;
  LineNumber    : Integer;
  F             : TLeakFinding;
begin
  p := 1;
  while True do
  begin
    p := PosEx(Kw, Lwr, p);
    if p = 0 then Break;
    if (p > 1) and IsIdent(Code[p - 1]) then begin Inc(p); Continue; end;
    if (p + KwLen <= Length(Code)) and IsIdent(Code[p + KwLen]) then
    begin Inc(p); Continue; end;
    // Nach dem Keyword: optional whitespace, dann `;`
    q := p + KwLen;
    while (q <= Length(Code)) and CharInSet(Code[q], [' ', #9]) do Inc(q);
    if (q > Length(Code)) or (Code[q] <> ';') then begin Inc(p); Continue; end;
    Inc(q);
    // Nach `;` whitespace/newline, dann `end` Wort
    while (q <= Length(Code)) and CharInSet(Code[q], [' ', #9, #10, #13]) do
      Inc(q);
    if (q + 2 > Length(Code)) then begin Inc(p); Continue; end;
    if SameText(Copy(Code, q, 3), 'end') and
       ((q + 3 > Length(Code)) or not IsIdent(Code[q + 3])) then
    begin
      k := p - 1;
      if (k >= 0) and (k < Length(LineFor)) then
        LineNumber := LineFor[k]
      else
        LineNumber := 0;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(LineNumber + 1);
      F.MissingVar := Format(
        '`%s;` directly before `end` is redundant - control flow ' +
        'already leaves the block.', [Kw]);
      F.SetKind(fkRedundantJump);
      Results.Add(F);
    end;
    p := q;
  end;
end;

class procedure TRedundantJumpDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines   : TStringList;
  Cached  : Boolean;
  Code    : string;
  Lwr     : string;
  LineFor : TArray<Integer>;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    Code := StripFileComments(Lines, LineFor);
    Lwr := LowerCase(Code);
    ScanRedundantJumpKw(Code, Lwr, 'exit',     4, LineFor, Results, FileName);
    ScanRedundantJumpKw(Code, Lwr, 'continue', 8, LineFor, Results, FileName);
    ScanRedundantJumpKw(Code, Lwr, 'break',    5, LineFor, Results, FileName);
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
