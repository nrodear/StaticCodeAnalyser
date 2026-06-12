unit uPublicField;

// Detektor fuer oeffentliche Felder in Klassen.
//
// SonarDelphi-Aequivalent: communitydelphi:PublicField. Oeffentliche
// Felder brechen Kapselung - der Aufrufer kann den Wert direkt
// aendern, ohne dass die Klasse das mitbekommt. Stattdessen sollte
// die Klasse eine Property anbieten (getter/setter), damit
// Invarianten geprueft werden koennen und spaetere Refactors (z.B.
// "wir wollen den Wert beim Setzen normalisieren") moeglich sind.
//
// Erkennung: Visibility-Section-Tracking. Wenn nach einem `public`
// (oder `published`) Keyword eine Zeile folgt, die ein Feld
// deklariert (Pattern `Name: Typ;` ohne `function`/`procedure`/
// `property`/`class function`/`const`/`constructor`/`destructor`),
// wird gemeldet.
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TPublicFieldDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, CommentedOutCode, CyclomaticComplexity, GroupedDeclaration, MultipleExit, NilComparison, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils,
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;

function ExtractFirstWord(const Line: string; out StartCol: Integer): string;
var
  i, n, wStart : Integer;
  c            : Char;
begin
  Result := '';
  StartCol := 0;
  n := Length(Line);
  i := 1;
  while (i <= n) and CharInSet(Line[i], [' ', #9]) do Inc(i);
  if i > n then Exit;
  c := Line[i];
  if c = '{' then Exit;
  if (c = '/') and (i < n) and (Line[i + 1] = '/') then Exit;
  if (c = '(') and (i < n) and (Line[i + 1] = '*') then Exit;
  if not CharInSet(c, ['A'..'Z','a'..'z','_']) then Exit;
  wStart := i;
  StartCol := wStart;
  while (i <= n) and CharInSet(Line[i], ['A'..'Z','a'..'z','0'..'9','_']) do
    Inc(i);
  Result := Copy(Line, wStart, i - wStart);
end;

// True wenn die Zeile ein Feld deklariert (kein procedure/function/...)
function LooksLikeField(const Line: string): Boolean;
var
  trimmed : string;
  Lower   : string;
  ColonPos: Integer;
begin
  Result := False;
  trimmed := TrimLeft(Line);
  Lower := LowerCase(trimmed);
  // Methoden / Property / Const / Constructor / Class-Methods ausschliessen
  if Lower.StartsWith('procedure ')   or Lower.StartsWith('procedure(') then Exit;
  if Lower.StartsWith('function ')    or Lower.StartsWith('function(')  then Exit;
  if Lower.StartsWith('constructor ') then Exit;
  if Lower.StartsWith('destructor ')  then Exit;
  if Lower.StartsWith('property ')    then Exit;
  if Lower.StartsWith('const ')       then Exit;
  if Lower.StartsWith('type ')        then Exit;
  if Lower.StartsWith('class ')       then Exit;
  if Lower.StartsWith('strict ')      then Exit;
  // Parameter-Modifier-Continuation-Lines ausschliessen. Multi-line Method-
  // Header schreiben gerne `out X: T; var Y: T):` auf einer Folgezeile -
  // ohne diesen Filter wird 'out' als Field-Name geflaggt.
  if Lower.StartsWith('out ')         then Exit;
  if Lower.StartsWith('var ')         then Exit;
  if Lower.StartsWith('inout ')       then Exit;
  if Lower.StartsWith('array ')       then Exit;
  // Method-Decl-Tail einer Continuation-Zeile: `): TypeName; static;`. Ein
  // `)` VOR dem `:` ist ein starkes Signal das die Zeile keine Field-Decl
  // ist, sondern der Schwanz einer mehrzeiligen Method-Signatur.
  ColonPos := Pos(':', trimmed);
  if (ColonPos > 0) and (Pos(')', Copy(trimmed, 1, ColonPos)) > 0) then Exit;
  // Param-Continuation-Tail: `Param: Type);` oder `Param: Type)` als letzte
  // Param-Zeile einer mehrzeiligen Method-Signatur. Hat `:` und `;`, aber
  // ALSO `)` IRGENDWO in der Zeile. Echte Field-Decls haben nie ')'.
  // (Edge: Methoden-Pointer-Felder `MyEvt: procedure(x: Integer);` haben '(' -
  //  die werden ueber die Inside-Parens-Continuation-Heuristik gefiltert.)
  if Pos(')', trimmed) > 0 then Exit;
  // Muss `:` und `;` enthalten - charakteristisch fuer Feld-Decl
  if (Pos(':', trimmed) = 0) then Exit;
  if (Pos(';', trimmed) = 0) then Exit;
  Result := True;
end;

class procedure TPublicFieldDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines    : TStringList;
  Cached   : Boolean;
  i, Col   : Integer;
  Word     : string;
  Lower    : string;
  InPublic : Boolean;
  F        : TLeakFinding;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    InPublic := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Word := ExtractFirstWord(Lines[i], Col);
      if Word = '' then Continue;
      Lower := LowerCase(Word);
      if (Lower = 'public') or (Lower = 'published') then
        InPublic := True
      else if (Lower = 'private') or (Lower = 'protected') or
              (Lower = 'strict')  or (Lower = 'end') or
              // Section-Boundaries: nach 'implementation' / 'initialization' /
              // 'finalization' gibt es keine Klassen-Felder mehr. Vor v0.9.x
              // blieb InPublic True bis zum naechsten Visibility-Keyword -
              // damit wurden Methoden-Parameter (out X / var Y) in
              // multi-line Method-Headers in der Implementation faelschlich
              // als Public-Field geflaggt.
              (Lower = 'implementation') or
              (Lower = 'initialization') or
              (Lower = 'finalization') then
        InPublic := False
      else if InPublic and LooksLikeField(Lines[i]) then
      begin
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := '';
        F.LineNumber := IntToStr(i + 1);
        F.MissingVar := Format(
          'Public field `%s` - prefer a property for encapsulation ' +
          '(getter/setter can be added later without breaking callers).',
          [Word]);
        F.SetKind(fkPublicField);
        Results.Add(F);
      end;
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
