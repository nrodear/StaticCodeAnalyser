unit uClassPerFile;

// Detektor fuer Units mit mehreren Top-Level-Klassen-Deklarationen.
//
// SonarDelphi-Aequivalent: communitydelphi:ClassPerFile. Die Konvention
// "eine Klasse pro Unit" macht den Codebase strukturierter und macht
// Refactorings (z.B. Move-to-Unit) trivial.
//
// Erkennung: Source kommentbereinigt einlesen, dann zaehle wieviele
// `=`-`class`-Deklarationen es gibt (also Type-Definitionen). Forward-
// Declarations `class;` werden ausgenommen. Bei >= 2 erfolgt ein
// Finding auf der zweiten Klasse.
//
// Achtung: Nested Klassen-Deklarationen innerhalb einer aeusseren
// Klasse zaehlen nicht als zweite Top-Level-Klasse - sind aber nur
// erkennbar wenn man den Brace-/Type-Block-State trackt. Hier
// pragmatisch: nur Klassen mit linker Wortgrenze und `=` davor.
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TClassPerFileDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, CyclomaticComplexity, DeepNesting, GroupedDeclaration, IfElseBegin, LegacyInitializationSection, LongMethod, NilComparison, RedundantJump, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

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

class procedure TClassPerFileDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines      : TStringList;
  Cached     : Boolean;
  Code       : string;
  Lwr        : string;
  LineFor    : TArray<Integer>;
  p, pEq, k  : Integer;
  ClassCount : Integer;
  LineNumber : Integer;
  pAfter     : Integer;
  c          : Char;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    Code := StripFileComments(Lines, LineFor);
    Lwr := LowerCase(Code);
    p := 1;
    ClassCount := 0;
    while True do
    begin
      p := PosEx('class', Lwr, p);
      if p = 0 then Break;
      // Wortgrenzen
      if (p > 1) and IsIdent(Code[p - 1]) then begin Inc(p); Continue; end;
      if (p + 5 <= Length(Code)) and IsIdent(Code[p + 5]) then
      begin Inc(p); Continue; end;
      // `=` davor (Type-Definition)?
      pEq := p - 1;
      while (pEq >= 1) and CharInSet(Code[pEq], [' ', #9, #10, #13]) do
        Dec(pEq);
      if (pEq < 1) or (Code[pEq] <> '=') then begin Inc(p, 5); Continue; end;
      // Forward-Declaration ausschliessen: `class;` direkt nach
      pAfter := p + 5;
      while (pAfter <= Length(Code)) and CharInSet(Code[pAfter], [' ', #9]) do
        Inc(pAfter);
      if (pAfter <= Length(Code)) then
      begin
        c := Code[pAfter];
        if c = ';' then begin Inc(p, 5); Continue; end;
        // `class of` ist auch keine Klassen-Definition (sondern class
        // reference type)
        if SameText(Copy(Code, pAfter, 2), 'of') and
           ((pAfter + 2 > Length(Code)) or not IsIdent(Code[pAfter + 2])) then
        begin Inc(p, 5); Continue; end;
      end;
      Inc(ClassCount);
      if ClassCount >= 2 then
      begin
        k := p - 1;
        if (k >= 0) and (k < Length(LineFor)) then
          LineNumber := LineFor[k]
        else
          LineNumber := 0;
        Results.Add(TLeakFinding.New(FileName, '', LineNumber + 1,
          'Second class declaration in this unit - prefer one class per ' +
          'file for clearer module boundaries.',
          fkClassPerFile));
      end;
      Inc(p, 5);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
