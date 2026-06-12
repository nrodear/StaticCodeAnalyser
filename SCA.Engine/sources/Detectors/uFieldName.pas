unit uFieldName;

// Detektor fuer Klassen-Felder, die nicht der F-Prefix-Konvention folgen.
//
// SonarDelphi-Aequivalent: communitydelphi:FieldName. Delphi-Konvention
// seit langer Zeit: Klassen-Felder beginnen mit `F` (Feld), wodurch der
// Aufrufer im Code-Body sofort erkennt "das ist ein Member-Feld, kein
// Local". `FFoo: Integer;` (statt `Foo: Integer;`) macht aus dem
// Klassen-Body lesbarer und vermeidet Naming-Clashes mit Parametern
// und lokalen Variablen.
//
// Erkennung: zeilenweiser Scan mit Klassen-Body-State-Tracking. Wir
// tracken die letzte gesehene Visibility-Section innerhalb eines class/
// record-Blocks. Field-Deklaration in private/protected wird gegen
// F-Prefix gecheckt - public/published-Felder werden vom existierenden
// uPublicField-Detektor abgedeckt (Encapsulation-Bruch).
//
// Heuristik: eine Zeile gilt als Field-Deklaration wenn:
//   * sie nicht mit Methoden-Keyword (procedure/function/constructor/
//     destructor/property/class/const/type/case/var) startet
//   * sie ein `:` und ein `;` enthaelt
//   * sie nicht in einer non-class-Section steht (var/const/type
//     top-level)
//
// Schweregrad: lsHint - reines Naming/Convention.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TFieldNameDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, ClassPerFile, CyclomaticComplexity, GroupedDeclaration, LongMethod, MultipleExit, NilComparison, TooLongLine, UnsortedUses, UnusedParameter
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

function IsMethodOrPropertyDecl(const Lower: string): Boolean; inline;
begin
  Result := (Lower = 'procedure') or (Lower = 'function')
         or (Lower = 'constructor') or (Lower = 'destructor')
         or (Lower = 'property') or (Lower = 'class')
         or (Lower = 'const') or (Lower = 'type') or (Lower = 'case')
         or (Lower = 'var') or (Lower = 'strict')
         // Param-Modifier Continuation-Lines von multi-line Method-Headers
         // ('  out X: T; var Y: T):...') - sonst werden 'out'/'inout' als
         // Field-Name geflaggt.
         or (Lower = 'out') or (Lower = 'inout');
end;

class procedure TFieldNameDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines       : TStringList;
  Cached      : Boolean;
  i, Col      : Integer;
  Word        : string;
  Lower       : string;
  InClass     : Boolean;
  InCheckVis  : Boolean;
  trimmed     : string;
  F           : TLeakFinding;
  ColonPos    : Integer;
  SemiPos     : Integer;
  FirstChar   : Char;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    InClass     := False;
    InCheckVis  := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Word := ExtractFirstWord(Lines[i], Col);
      if Word = '' then Continue;
      Lower := LowerCase(Word);
      // Class/Record startet einen Block
      if (Pos(' = class', LowerCase(Lines[i])) > 0) or
         (Pos(' = record', LowerCase(Lines[i])) > 0) or
         (Lower = 'class') or (Lower = 'record') then
      begin
        InClass := True;
        // Default-Visibility VOR der ersten expliziten Section ist published
        // (TPersistent/TComponent/TForm/TFrame/TDataModule). Diese Felder
        // sind vom Form-Designer/DFM-Binding verwaltet und koennen die
        // F-Prefix-Regel nicht erfuellen. -> Erst nach explizitem
        // 'private'/'protected' anfangen zu checken.
        InCheckVis := False;
        Continue;
      end;
      if not InClass then Continue;
      // Visibility-Tracking
      if Lower = 'private' then begin InCheckVis := True; Continue; end;
      if Lower = 'protected' then begin InCheckVis := True; Continue; end;
      if Lower = 'public' then begin InCheckVis := False; Continue; end;
      if Lower = 'published' then begin InCheckVis := False; Continue; end;
      if Lower = 'strict' then Continue;
      if Lower = 'end' then
      begin
        InClass := False;
        InCheckVis := False;
        Continue;
      end;
      if not InCheckVis then Continue;
      // Skip method/property/const/type/etc declarations
      if IsMethodOrPropertyDecl(Lower) then Continue;
      // Feld-Heuristik: enthaelt `:` und `;`
      trimmed := Lines[i];
      ColonPos := Pos(':', trimmed);
      SemiPos  := Pos(';', trimmed);
      if (ColonPos = 0) or (SemiPos = 0) or (ColonPos > SemiPos) then Continue;
      // Vor `:` darf kein `(` stehen (Parameterlisten)
      if Pos('(', Copy(trimmed, 1, ColonPos)) > 0 then Continue;
      // Method-Decl-Tail einer Continuation-Zeile: `): TypeName; static;`.
      // Ein `)` VOR dem `:` ist starkes Signal fuer Schwanz einer mehrzeiligen
      // Method-Signatur, nicht fuer Field-Decl.
      if Pos(')', Copy(trimmed, 1, ColonPos)) > 0 then Continue;
      // Param-Continuation-Tail: `Param: Type);` oder `Param: Type)` mit
      // ')' irgendwo in der Zeile - echte Field-Decls haben nie ')'.
      if Pos(')', trimmed) > 0 then Continue;
      // Erstes Zeichen des Worts muss `F` sein
      FirstChar := Word[1];
      if (FirstChar = 'F') or (FirstChar = 'f') then Continue;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(i + 1);
      F.MissingVar := Format(
        'Field `%s` does not follow `F<Name>` naming convention - ' +
        'prefix with `F` to mark it as a class field.', [Word]);
      F.SetKind(fkFieldName);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
