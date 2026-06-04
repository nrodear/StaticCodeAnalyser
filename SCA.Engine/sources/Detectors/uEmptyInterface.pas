unit uEmptyInterface;

// Detektor fuer leere Interface-Deklarationen.
//
// SonarDelphi-Aequivalent: communitydelphi:EmptyInterface. Ein
// `IFoo = interface end;` ohne Methoden bietet keinerlei Vertrag - das
// ist entweder ein Refactor-Rest oder ein Marker-Interface (das man
// dann mit einer leeren Annotation-Klasse modellieren sollte).
//
// Erkennung: Source wird zeilenweise komment-bereinigt und mit
// Linebreak-Markierung gejoined; auf dem resultierenden String wird
// nach dem Pattern `= interface (..parents..)? ['{GUID}']? \s* end`
// gesucht. Zwischen `interface`-Eroeffnung und `end` darf nur
// Whitespace stehen.
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TEmptyInterfaceDetector = class
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

// Entfernt //, {...}, (*..*) Kommentare aus einer Source. Ersetzt sie
// durch ein Leerzeichen, damit Spalten-Position grob erhalten bleibt.
// Linebreak bleibt #10.
function StripCommentsFile(Lines: TStringList; out LineForChar: TArray<Integer>): string;
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
          if pClose = 0 then begin Buf.Append(' '); Chars.Add(i); Break; end;
          InBlk := False;
          j := pClose + 1; Continue;
        end;
        if InParen then
        begin
          pClose := PosEx('*)', Line, j);
          if pClose = 0 then begin Buf.Append(' '); Chars.Add(i); Break; end;
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

class procedure TEmptyInterfaceDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines      : TStringList;
  Cached     : Boolean;
  Code       : string;
  Lwr        : string;
  LineFor    : TArray<Integer>;
  pInt, pEnd : Integer;
  j, k       : Integer;
  Between    : string;
  IsEmpty    : Boolean;
  c          : Char;
  pLeftEq    : Integer;
  LineNumber : Integer;
  F          : TLeakFinding;
  pStart     : Integer;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    Code := StripCommentsFile(Lines, LineFor);
    Lwr := LowerCase(Code);
    pInt := 1;
    while True do
    begin
      pInt := PosEx('interface', Lwr, pInt);
      if pInt = 0 then Break;
      pStart := pInt;
      // Wortgrenzen
      if (pInt > 1) and IsIdent(Code[pInt - 1]) then
      begin Inc(pInt); Continue; end;
      if (pInt + 9 <= Length(Code)) and IsIdent(Code[pInt + 9]) then
      begin Inc(pInt); Continue; end;
      // Linker Kontext: `=` davor (mit Whitespace) -> Typ-Deklaration
      pLeftEq := pInt - 1;
      while (pLeftEq >= 1) and CharInSet(Code[pLeftEq], [' ', #9, #10]) do
        Dec(pLeftEq);
      if (pLeftEq < 1) or (Code[pLeftEq] <> '=') then
      begin Inc(pInt, 9); Continue; end;
      // Nach `interface` skippen
      j := pInt + 9;
      while (j <= Length(Code)) and CharInSet(Code[j], [' ', #9, #10]) do Inc(j);
      // Optionale `(parents)`
      if (j <= Length(Code)) and (Code[j] = '(') then
      begin
        Inc(j);
        while (j <= Length(Code)) and (Code[j] <> ')') do Inc(j);
        if j <= Length(Code) then Inc(j);
      end;
      while (j <= Length(Code)) and CharInSet(Code[j], [' ', #9, #10]) do Inc(j);
      // Optionale GUID `[...]`
      if (j <= Length(Code)) and (Code[j] = '[') then
      begin
        Inc(j);
        while (j <= Length(Code)) and (Code[j] <> ']') do Inc(j);
        if j <= Length(Code) then Inc(j);
      end;
      // Naechstes `end` (Wortgrenze)
      pEnd := PosEx('end', Lwr, j);
      while pEnd > 0 do
      begin
        if ((pEnd = 1) or not IsIdent(Code[pEnd - 1])) and
           ((pEnd + 3 > Length(Code)) or not IsIdent(Code[pEnd + 3])) then
          Break;
        pEnd := PosEx('end', Lwr, pEnd + 1);
      end;
      if pEnd = 0 then begin Inc(pInt, 9); Continue; end;
      Between := Copy(Code, j, pEnd - j);
      IsEmpty := True;
      for c in Between do
        if not CharInSet(c, [' ', #9, #10, #13]) then
        begin IsEmpty := False; Break; end;
      if IsEmpty then
      begin
        k := pStart - 1;
        if (k >= 0) and (k < Length(LineFor)) then
          LineNumber := LineFor[k]
        else
          LineNumber := 0;
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := '';
        F.LineNumber := IntToStr(LineNumber + 1);
        F.MissingVar := 'Empty interface declaration - add a contract ' +
          '(methods/properties) or use an attribute class instead.';
        F.SetKind(fkEmptyInterface);
        Results.Add(F);
      end;
      pInt := pEnd + 3;
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
