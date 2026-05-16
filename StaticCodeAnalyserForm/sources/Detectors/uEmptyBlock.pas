unit uEmptyBlock;

// Detektor fuer leere `begin..end`-Bloecke.
//
// SonarDelphi-Aequivalent: communitydelphi:EmptyBlock. Ein `begin end`
// ohne Anweisungen dazwischen ist meistens ein vergessener Refactor-
// Rest oder ein Platzhalter, der nie ausgefuellt wurde. In jedem Fall
// ist es Toter Code, der dem Reviewer Fragezeichen liefert.
//
// Erkennung: zeilenweise Tokenstream-Scan ueber die ganze Unit
// (kommentbereinigt). Wir suchen Vorkommen von `begin` Wort, gefolgt
// von nur Whitespace, dann `end` Wort.
//
// Ausgenommen: `begin..end` im Top-Level-Initialization-Pattern
// (`begin\nEnd.`) - das ist die syntaktisch erlaubte aber leere
// Initialization-Section, kein Refactor-Rest.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TEmptyBlockDetector = class
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

class procedure TEmptyBlockDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines      : TStringList;
  Cached     : Boolean;
  Code       : string;
  Lwr        : string;
  LineFor    : TArray<Integer>;
  pBeg, pEnd : Integer;
  j          : Integer;
  Between    : string;
  IsEmpty    : Boolean;
  c          : Char;
  LineNumber : Integer;
  F          : TLeakFinding;
  IsInitSec  : Boolean;
  k          : Integer;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    Code := StripFileComments(Lines, LineFor);
    Lwr := LowerCase(Code);
    pBeg := 1;
    while True do
    begin
      pBeg := PosEx('begin', Lwr, pBeg);
      if pBeg = 0 then Break;
      // Wortgrenzen
      if (pBeg > 1) and IsIdent(Code[pBeg - 1]) then
      begin Inc(pBeg); Continue; end;
      if (pBeg + 5 <= Length(Code)) and IsIdent(Code[pBeg + 5]) then
      begin Inc(pBeg); Continue; end;
      // Nach `begin` whitespace skippen
      j := pBeg + 5;
      while (j <= Length(Code)) and CharInSet(Code[j], [' ', #9, #10, #13]) do
        Inc(j);
      // `end` Wort suchen ab j
      pEnd := PosEx('end', Lwr, j);
      while pEnd > 0 do
      begin
        if ((pEnd = 1) or not IsIdent(Code[pEnd - 1])) and
           ((pEnd + 3 > Length(Code)) or not IsIdent(Code[pEnd + 3])) then
          Break;
        pEnd := PosEx('end', Lwr, pEnd + 1);
      end;
      if pEnd = 0 then begin Inc(pBeg, 5); Continue; end;
      // Inhalt zwischen begin und end: nur Whitespace?
      Between := Copy(Code, pBeg + 5, pEnd - pBeg - 5);
      IsEmpty := True;
      for c in Between do
        if not CharInSet(c, [' ', #9, #10, #13]) then
        begin IsEmpty := False; Break; end;
      if IsEmpty then
      begin
        // Top-Level Initialization-Section ausschliessen: `end.` direkt
        // nach diesem `end` waere die Unit-Terminierung.
        IsInitSec := False;
        k := pEnd + 3;
        while (k <= Length(Code)) and CharInSet(Code[k], [' ', #9, #10, #13]) do
          Inc(k);
        if (k <= Length(Code)) and (Code[k] = '.') then IsInitSec := True;
        if not IsInitSec then
        begin
          k := pBeg - 1;
          if (k >= 0) and (k < Length(LineFor)) then
            LineNumber := LineFor[k]
          else
            LineNumber := 0;
          F            := TLeakFinding.Create;
          F.FileName   := FileName;
          F.MethodName := '';
          F.LineNumber := IntToStr(LineNumber + 1);
          F.MissingVar := 'Empty `begin..end` block - delete it or fill ' +
            'in the missing statement.';
          F.SetKind(fkEmptyBlock);
          Results.Add(F);
        end;
      end;
      pBeg := pEnd + 3;
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
