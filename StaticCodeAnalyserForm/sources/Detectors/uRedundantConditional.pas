unit uRedundantConditional;

// Detektor fuer redundante if-Conditionals der Form
//   if Cond then Result := True else Result := False;
// die auf
//   Result := Cond;
// reduziert werden koennen.
//
// SonarDelphi-Aequivalent: communitydelphi:RedundantConditional. Zwei
// klassische Varianten:
//   * `if X then Result := True else Result := False`
//   * `if X then Result := False else Result := True` (sollte `not X`)
//
// Erkennung: lexikalisch ueber den joined komment-bereinigten Code.
// Pattern:
//   `if` <expr> `then` <Ident> `:=` (True|False) [`;`] `else` <SameIdent>
//   `:=` (True|False) [`;`]
// wobei die beiden Boolean-Werte verschieden sein muessen und der
// Ident auf beiden Seiten gleich.
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TRedundantConditionalDetector = class
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

function IsIdentStart(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z','a'..'z','_']);
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

// Aus Code ab Position p das naechste schreibbare Token extrahieren
// (Ident, True, False, etc.) und Endposition zurueckgeben.
function ScanWordAfter(const Code: string; p: Integer; out Word: string): Integer;
var
  n, Start : Integer;
begin
  Result := p;
  Word := '';
  n := Length(Code);
  while (Result <= n) and CharInSet(Code[Result], [' ', #9, #10, #13]) do
    Inc(Result);
  if (Result > n) or not IsIdentStart(Code[Result]) then Exit;
  Start := Result;
  while (Result <= n) and IsIdent(Code[Result]) do Inc(Result);
  Word := Copy(Code, Start, Result - Start);
end;

// Pruefe ab Position p ob `:=` folgt (mit Whitespace).
function ExpectAssign(const Code: string; var p: Integer): Boolean;
var
  n : Integer;
begin
  Result := False;
  n := Length(Code);
  while (p <= n) and CharInSet(Code[p], [' ', #9, #10, #13]) do Inc(p);
  if (p + 1 > n) then Exit;
  if (Code[p] <> ':') or (Code[p + 1] <> '=') then Exit;
  Inc(p, 2);
  Result := True;
end;

// Pruefe ab Position p ob `then` Keyword folgt (mit Whitespace).
function ExpectKeyword(const Code: string; var p: Integer; const Kw: string): Boolean;
var
  Lower : string;
  q     : Integer;
begin
  q := p;
  q := ScanWordAfter(Code, q, Lower);
  Result := SameText(Lower, Kw);
  if Result then p := q;
end;

// Pruefe ab p ob `;` (optional whitespace davor).
function SkipOptionalSemi(const Code: string; var p: Integer): Boolean;
var
  n : Integer;
begin
  Result := True;
  n := Length(Code);
  while (p <= n) and CharInSet(Code[p], [' ', #9, #10, #13]) do Inc(p);
  if (p <= n) and (Code[p] = ';') then Inc(p);
end;

class procedure TRedundantConditionalDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines      : TStringList;
  Cached     : Boolean;
  Code       : string;
  Lwr        : string;
  LineFor    : TArray<Integer>;
  pIf, p     : Integer;
  q          : Integer;
  Word, W2   : string;
  Lhs1, Lhs2 : string;
  Rhs1, Rhs2 : string;
  LineNumber : Integer;
  F          : TLeakFinding;
  Saved      : Integer;
  parenDepth : Integer;
  n          : Integer;
  IsBool     : Boolean;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    Code := StripFileComments(Lines, LineFor);
    Lwr := LowerCase(Code);
    n := Length(Code);
    pIf := 1;
    while True do
    begin
      pIf := PosEx('if', Lwr, pIf);
      if pIf = 0 then Break;
      // Wortgrenzen
      if (pIf > 1) and IsIdent(Code[pIf - 1]) then begin Inc(pIf); Continue; end;
      if (pIf + 2 <= n) and IsIdent(Code[pIf + 2]) then begin Inc(pIf); Continue; end;
      // Skip Bedingung bis `then`
      p := pIf + 2;
      parenDepth := 0;
      Saved := 0;
      while p <= n do
      begin
        if Code[p] = '(' then Inc(parenDepth)
        else if Code[p] = ')' then
        begin
          if parenDepth > 0 then Dec(parenDepth);
        end
        else if (parenDepth = 0) and CharInSet(Code[p], ['t', 'T']) then
        begin
          if (p + 3 <= n) and SameText(Copy(Code, p, 4), 'then') and
             ((p = 1) or not IsIdent(Code[p - 1])) and
             ((p + 4 > n) or not IsIdent(Code[p + 4])) then
          begin
            Saved := p + 4;
            Break;
          end;
        end;
        Inc(p);
      end;
      if Saved = 0 then begin Inc(pIf, 2); Continue; end;
      p := Saved;
      // `then` <Ident>
      Lhs1 := '';
      q := p;
      q := ScanWordAfter(Code, q, Lhs1);
      if Lhs1 = '' then begin Inc(pIf, 2); Continue; end;
      p := q;
      if not ExpectAssign(Code, p) then begin Inc(pIf, 2); Continue; end;
      // True / False?
      Rhs1 := '';
      q := p;
      q := ScanWordAfter(Code, q, Rhs1);
      IsBool := SameText(Rhs1, 'True') or SameText(Rhs1, 'False');
      if not IsBool then begin Inc(pIf, 2); Continue; end;
      p := q;
      SkipOptionalSemi(Code, p);
      // `else`
      if not ExpectKeyword(Code, p, 'else') then
      begin Inc(pIf, 2); Continue; end;
      // <SameIdent>
      Lhs2 := '';
      q := p;
      q := ScanWordAfter(Code, q, Lhs2);
      if not SameText(Lhs1, Lhs2) then begin Inc(pIf, 2); Continue; end;
      p := q;
      if not ExpectAssign(Code, p) then begin Inc(pIf, 2); Continue; end;
      Rhs2 := '';
      q := p;
      q := ScanWordAfter(Code, q, Rhs2);
      if not (SameText(Rhs2, 'True') or SameText(Rhs2, 'False')) then
      begin Inc(pIf, 2); Continue; end;
      // Boolean-Werte muessen unterschiedlich sein
      if SameText(Rhs1, Rhs2) then begin Inc(pIf, 2); Continue; end;
      // Treffer
      Saved := pIf - 1;
      if (Saved >= 0) and (Saved < Length(LineFor)) then
        LineNumber := LineFor[Saved]
      else
        LineNumber := 0;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(LineNumber + 1);
      F.MissingVar := Format(
        '`if Cond then %s := %s else %s := %s` can be simplified to ' +
        '`%s := Cond` (or `not Cond`).',
        [Lhs1, Rhs1, Lhs1, Rhs2, Lhs1]);
      F.SetKind(fkRedundantConditional);
      Results.Add(F);
      pIf := p;
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
