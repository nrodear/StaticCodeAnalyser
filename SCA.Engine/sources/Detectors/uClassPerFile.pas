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
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TClassPerFileDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, CyclomaticComplexity, DeepNesting, GroupedDeclaration, IfElseBegin, LegacyInitializationSection, LongMethod, NilComparison, RedundantJump, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils,
  uDetectorUtils,
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;

function IsIdent(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z','a'..'z','0'..'9','_']);
end;

class procedure TClassPerFileDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
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
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    Code := TDetectorUtils.StripFileCommentsKeepStringsCached(Lines, LineFor, AContext, FileName);
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
