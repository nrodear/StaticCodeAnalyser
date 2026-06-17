unit uEmptyFile;

// Detektor fuer "leere" Pascal-Units: kein einziger Typ, Konstante,
// Variable oder Methode.
//
// SonarDelphi-Aequivalent: communitydelphi:EmptyFile. Eine Unit, die
// nichts deklariert, ist Refactor-Rest oder Test-Fixture-Vergessen.
//
// Erkennung: pro Zeile (kommentbereinigt) pruefen, ob ein Section-
// Keyword (`type`/`const`/`var`/`resourcestring`/`procedure`/`function`/
// `constructor`/`destructor`/`property`) auftaucht. Wenn nicht und das
// File enthaelt `interface` + `implementation` + `end.`, gilt es als
// leer.
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TEmptyFileDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file BeginEndRequired, CyclomaticComplexity, DeepNesting, GroupedDeclaration, MultipleExit, NilComparison, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;

function ExtractFirstWord(const Line: string): string;
var
  i, n, wStart : Integer;
  c            : Char;
begin
  Result := '';
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
  while (i <= n) and CharInSet(Line[i], ['A'..'Z','a'..'z','0'..'9','_']) do
    Inc(i);
  Result := Copy(Line, wStart, i - wStart);
end;

function IsDeclarationKw(const Lower: string): Boolean; inline;
begin
  Result := (Lower = 'type')           or (Lower = 'const')
         or (Lower = 'var')            or (Lower = 'resourcestring')
         or (Lower = 'procedure')      or (Lower = 'function')
         or (Lower = 'constructor')    or (Lower = 'destructor')
         or (Lower = 'property')       or (Lower = 'threadvar')
         or (Lower = 'class');
end;

class procedure TEmptyFileDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines     : TStringList;
  Cached    : Boolean;
  i         : Integer;
  Word, L   : string;
  HasUnit   : Boolean;
  HasIface  : Boolean;
  HasImpl   : Boolean;
  HasDecl   : Boolean;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    HasUnit  := False;
    HasIface := False;
    HasImpl  := False;
    HasDecl  := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Word := ExtractFirstWord(Lines[i]);
      if Word = '' then Continue;
      L := LowerCase(Word);
      if L = 'unit' then HasUnit := True
      else if L = 'interface' then HasIface := True
      else if L = 'implementation' then HasImpl := True
      else if IsDeclarationKw(L) then HasDecl := True;
    end;
    // Es muss eine echte Unit sein UND keine Deklaration enthalten
    if HasUnit and HasIface and HasImpl and (not HasDecl) then
      Results.Add(TLeakFinding.New(FileName, '', 1,
        'Unit contains no declarations (no type/const/var/' +
        'procedure/function) - delete the file or fill it in.',
        fkEmptyFile));
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
