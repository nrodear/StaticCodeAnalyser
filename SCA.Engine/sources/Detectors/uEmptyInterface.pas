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
// Der Strip laeuft ueber TDetectorUtils.StripFileCommentsKeepStringsCached
// (Strings verbatim, Kommentare ersatzlos weg, pro Quellzeile ein #10 +
// LineForChar-Map) - Restschulden-Audit 2026-07-26: bis dahin lag hier
// eine gedriftete lokale Kopie (StripCommentsFile), die bei einer Zeile
// KOMPLETT innerhalb eines `{..}`/`(*..*)`-Blocks zusaetzlich ein
// Leerzeichen ausgab. Fund-neutral (das Zeichen stand immer zwischen zwei
// #10 und ist wie diese Whitespace), aber es kostete pro Datei einen
// eigenen Voll-Strip am gemeinsamen Per-Scan-Cache vorbei.
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext,
  uDetectorUtils;   // H2445: inline-Expansion braucht iface-Sichtbarkeit

type
  TEmptyInterfaceDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, CyclomaticComplexity, DeepNesting, GroupedDeclaration, IfElseBegin, LegacyInitializationSection, LongMethod, NilComparison, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils,
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;

function IsIdent(C: Char): Boolean; inline;
begin
  // Backlog-Welle 1, 2026-07-26: Zeichenklasse zentralisiert - die
  // lokale Fassung war zeichenweise identisch zu
  // TDetectorUtils.IsIdentChar (a..z, A..Z, 0..9, _). Der Wrapper
  // bleibt, damit die Aufrufer in dieser Unit unveraendert bleiben.
  Result := TDetectorUtils.IsIdentChar(C);
end;

class procedure TEmptyInterfaceDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
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
  pStart     : Integer;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    Code := TDetectorUtils.StripFileCommentsKeepStringsCached(
      Lines, LineFor, AContext, FileName);
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
        Results.Add(TLeakFinding.New(FileName, '', LineNumber + 1,
          'Empty interface declaration - add a contract ' +
          '(methods/properties) or use an attribute class instead.',
          fkEmptyInterface));
      end;
      pInt := pEnd + 3;
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
