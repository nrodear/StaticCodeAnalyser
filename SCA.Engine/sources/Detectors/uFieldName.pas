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
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TFieldNameDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, ClassPerFile, CyclomaticComplexity, GroupedDeclaration, LongMethod, MultipleExit, NilComparison, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uFileTextCache,
  uDetectorUtils;   // BlankStringLiterals (ParenDelta)

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

// Paren-Delta einer Zeile ('(' minus ')'), String-Literale und
// //-Kommentare ausgenommen, '(*'/'*)'-Delimiter nicht mitgezaehlt.
// Gleiche Aufgabe wie die Fassung in uConsecutiveSection, aber ueber
// die geteilte BlankStringLiterals-Infrastruktur statt eines eigenen
// Quote-Toggles. Hier gebraucht, um OFFENE Parameterlisten
// mehrzeiliger Methodenkoepfe zu erkennen - deren Fortsetzungszeilen
// ('B: string;') sind Parameter, keine Felder.
function ParenDelta(const Line: string): Integer;
var
  S    : string;
  i, n : Integer;
  p    : Integer;
begin
  Result := 0;
  S := TDetectorUtils.BlankStringLiterals(Line);
  p := Pos('//', S);
  if p > 0 then S := Copy(S, 1, p - 1);
  n := Length(S);
  for i := 1 to n do
  begin
    if (S[i] = '(') and not ((i < n) and (S[i + 1] = '*')) then Inc(Result);
    if (S[i] = ')') and not ((i > 1) and (S[i - 1] = '*')) then Dec(Result);
  end;
end;

type
  // Sektions-Zustand des zeilenweisen Scans: offene Parameterliste
  // eines mehrzeiligen Kopfs (InParamList/ParenBal) und laufende
  // const-/type-Untersektion (InConstType). Als Record gebuendelt,
  // damit die Nachfuehr-Routine unter der Parameter-Schwelle bleibt.
  TSectionState = record
    InParamList : Boolean;
    ParenBal    : Integer;
    InConstType : Boolean;
  end;

// Sektions-Zustand beim Ueberspringen einer Deklarations-Zeile
// (IsMethodOrPropertyDecl-Treffer) nachfuehren:
// (a) bleibt die Klammerbilanz der Zeile offen, folgen
//     Parameterzeilen eines mehrzeiligen Kopfs;
// (b) 'const'/'type' eroeffnen eine Untersektion - alles bis zum
//     naechsten Abschnitts-Keyword sind (typisierte) Konstanten bzw.
//     Typen, keine Felder. 'var' und Methoden-Koepfe beenden sie;
//     'out'/'inout'/'case'/'strict' (Parameter-Continuation bzw.
//     Varianten-Teil) lassen sie unveraendert; bei 'class'
//     entscheidet das zweite Wort ('class const' vs. 'class var').
procedure TrackDeclLine(const Line, Lower: string; ACol: Integer;
  var St: TSectionState);
begin
  St.ParenBal := ParenDelta(Line);
  St.InParamList := St.ParenBal > 0;
  if (Lower = 'const') or (Lower = 'type') then
    St.InConstType := True
  else if (Lower = 'var') or (Lower = 'procedure')
       or (Lower = 'function') or (Lower = 'constructor')
       or (Lower = 'destructor') or (Lower = 'property') then
    St.InConstType := False
  else if Lower = 'class' then
    St.InConstType := SecondWordIsConstOrType(Line, ACol);
end;

// Zweites Wort der Zeile hinter dem ersten (ab AFirstCol) ist 'const'
// oder 'type' - unterscheidet 'class const'/'class type' (eroeffnen
// eine Konstanten-/Typ-Untersektion) von 'class var'/'class function'
// (beenden sie).
function SecondWordIsConstOrType(const Line: string;
  AFirstCol: Integer): Boolean;
var
  p, Dummy : Integer;
  W2       : string;
begin
  p := AFirstCol;
  while (p <= Length(Line)) and
        CharInSet(Line[p], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Inc(p);
  W2 := LowerCase(ExtractFirstWord(Copy(Line, p, MaxInt), Dummy));
  Result := (W2 = 'const') or (W2 = 'type');
end;

class procedure TFieldNameDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
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
  St          : TSectionState;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    InClass     := False;
    InCheckVis  := False;
    St          := Default(TSectionState);
    for i := 0 to Lines.Count - 1 do
    begin
      Word := ExtractFirstWord(Lines[i], Col);
      // Offene Parameterliste eines mehrzeiligen Methodenkopfs: alle
      // Zeilen bis zur schliessenden ')' sind Parameter, keine Felder
      // ('B: string;' mitten im Kopf passierte bis zum Voll-Review
      // 2026-09-12 alle Guards -> FP, Blocker). VOR dem Leerwort-Gate:
      // auch eine Zeile, die mit ')' beginnt (Word=''), muss die
      // Bilanz nachfuehren.
      if St.InParamList then
      begin
        Inc(St.ParenBal, ParenDelta(Lines[i]));
        if St.ParenBal <= 0 then St.InParamList := False;
        Continue;
      end;
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
        St.InConstType := False;
        Continue;
      end;
      if not InClass then Continue;
      // Visibility-Tracking; eine neue Sichtbarkeit beendet auch eine
      // laufende const-/type-Untersektion (Felder folgen wieder).
      if Lower = 'private' then
        begin InCheckVis := True; St.InConstType := False; Continue; end;
      if Lower = 'protected' then
        begin InCheckVis := True; St.InConstType := False; Continue; end;
      if Lower = 'public' then
        begin InCheckVis := False; St.InConstType := False; Continue; end;
      if Lower = 'published' then
        begin InCheckVis := False; St.InConstType := False; Continue; end;
      if Lower = 'strict' then Continue;
      if Lower = 'end' then
      begin
        InClass := False;
        InCheckVis := False;
        St.InConstType := False;
        Continue;
      end;
      if not InCheckVis then Continue;
      // Skip method/property/const/type/etc declarations - und dabei
      // den Sektions-Zustand nachfuehren (Voll-Review 2026-09-12,
      // Begruendung an TrackDeclLine):
      if IsMethodOrPropertyDecl(Lower) then
      begin
        TrackDeclLine(Lines[i], Lower, Col, St);
        Continue;
      end;
      // Typisierte Konstante bzw. Typ-Deklaration in einer laufenden
      // const-/type-Untersektion: 'Timeout: Integer = 500;' traegt ':'
      // und ';' wie ein Feld, ist aber keins (zweite FP-Klasse des
      // Blockers).
      if St.InConstType then Continue;
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
