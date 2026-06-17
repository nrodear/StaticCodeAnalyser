unit uLowercaseKeyword;

// Detektor fuer Pascal-Keywords, die NICHT in Kleinschreibung stehen.
//
// Style-Rule: Object-Pascal-Konvention seit Wirth ist all-lowercase fuer
// Keywords (begin/end/procedure/...). PascalCase-Keywords (Begin, End,
// Procedure) sind Style-Drift aus Turbo-Pascal/Delphi-1-Aera und heute
// in allen ernsthaften Style-Guides untersagt - vgl. SonarDelphi-Rule
// communitydelphi:LowercaseKeyword sowie das offizielle Object-Pascal-
// Style-Guide von Embarcadero (DocWiki).
//
// Erkennung: lexikalischer Scan mit String-/Kommentar-Awareness analog
// zu uGotoStatement. Pro Treffer wird die Spalte des Keywords gemeldet.
// Mehrere Findings pro Zeile moeglich (anders als die Tab-/Whitespace-
// Detektoren).
//
// Whitelist: nur "kernige" Keywords, die niemals als Identifier
// verwendet werden duerfen (begin/end/if/then/.../var/const/...). Context-
// sensitive Worte wie `default`, `read`, `write`, `name`, `message`
// sind ausgenommen, da sie als Property-Specifier-Token oder als
// Identifier zulaessig sind.
//
// Schweregrad: lsHint - reines Style/Formatting.
//
// SonarDelphi-Mapping: communitydelphi:LowercaseKeyword
// (MQR MAINTAINABILITY-LOW, cca CONVENTIONAL).

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TLowercaseKeywordDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file BeginEndRequired, ConsecutiveSection, CyclomaticComplexity, GroupedDeclaration, IfElseBegin, LongMethod, MultipleExit, NilComparison, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils,
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;

  // Kuratierte Keyword-Liste. Reihenfolge egal (Lookup ist linear, N<100
  // ist klein genug). Bewusst NICHT enthalten:
  //   * Property-Specifier / kontext-abhaengig (auch als Identifier
  //     erlaubt): `default`, `read`, `write`, `name`, `message`,
  //     `index`, `stored`, `nodefault`, ...
  //   * Idiomatisch PascalCase im Delphi-RTL/VCL: `Self`, `Result`,
  //     `True`, `False` - diese wuerden False-Positives auf praktisch
  //     jeder Delphi-Codebase erzeugen.
  KEYWORDS: array[0..79] of string = (
    'absolute', 'abstract', 'and', 'array', 'as', 'asm',
    'begin', 'case', 'cdecl', 'class', 'const', 'constructor',
    'contains', 'destructor', 'dispinterface', 'div', 'do', 'downto',
    'else', 'end', 'except', 'exports', 'file', 'final',
    'finalization', 'finally', 'for', 'forward', 'function',
    'goto', 'helper', 'if', 'implementation', 'implements',
    'in', 'inherited', 'initialization', 'inline', 'interface',
    'is', 'label', 'library', 'mod', 'nil', 'not',
    'object', 'of', 'on', 'operator', 'or', 'out',
    'overload', 'override', 'packed', 'pascal', 'private',
    'procedure', 'program', 'property', 'protected', 'public',
    'published', 'raise', 'record', 'register', 'reintroduce',
    'repeat', 'requires', 'resourcestring', 'safecall', 'sealed',
    'set', 'shl', 'shr', 'stdcall', 'strict', 'string',
    'then', 'threadvar', 'to'
  );
  KEYWORDS2: array[0..10] of string = (
    'try', 'type', 'unit', 'until', 'uses', 'var', 'varargs',
    'virtual', 'while', 'with', 'xor'
  );

function IsIdent(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z','a'..'z','0'..'9','_']);
end;

function IsIdentStart(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z','a'..'z','_']);
end;

// Liefert True, falls Word (lowercase) ein Pascal-Keyword aus der
// kuratierten Liste ist.
function IsKeyword(const Lower: string): Boolean;
var
  i : Integer;
begin
  for i := Low(KEYWORDS) to High(KEYWORDS) do
    if KEYWORDS[i] = Lower then Exit(True);
  for i := Low(KEYWORDS2) to High(KEYWORDS2) do
    if KEYWORDS2[i] = Lower then Exit(True);
  Result := False;
end;

type
  TKwHit = record
    Col  : Integer;       // 1-basierte Spalte
    Word : string;        // Original-Schreibweise
  end;

// Scannt eine Zeile und liefert alle Keywords, deren Schreibweise NICHT
// lowercase ist. Beruecksichtigt String-Literale und Kommentare. Block-
// Comm-State wird ueber Zeilen mitgefuehrt.
procedure CollectMixedCaseKeywords(const Line: string;
  var InBlockComm: Boolean; var InParenStarComm: Boolean;
  Hits: TList<TKwHit>);
var
  i, n, wStart : Integer;
  InStr        : Boolean;
  pClose       : Integer;
  c            : Char;
  Word, Lower  : string;
  Hit          : TKwHit;
begin
  InStr := False;
  i := 1;
  n := Length(Line);
  while i <= n do
  begin
    if InBlockComm then
    begin
      pClose := PosEx('}', Line, i);
      if pClose = 0 then Exit;
      InBlockComm := False;
      i := pClose + 1;
      Continue;
    end;
    if InParenStarComm then
    begin
      pClose := PosEx('*)', Line, i);
      if pClose = 0 then Exit;
      InParenStarComm := False;
      i := pClose + 2;
      Continue;
    end;
    c := Line[i];
    if InStr then
    begin
      if c = '''' then
      begin
        if (i < n) and (Line[i + 1] = '''') then Inc(i, 2)
        else begin InStr := False; Inc(i); end;
      end
      else Inc(i);
      Continue;
    end;
    if c = '''' then begin InStr := True; Inc(i); Continue; end;
    if (c = '/') and (i < n) and (Line[i + 1] = '/') then Exit;
    if c = '{' then
    begin
      pClose := PosEx('}', Line, i + 1);
      if pClose = 0 then begin InBlockComm := True; Exit; end;
      i := pClose + 1; Continue;
    end;
    if (c = '(') and (i < n) and (Line[i + 1] = '*') then
    begin
      pClose := PosEx('*)', Line, i + 2);
      if pClose = 0 then begin InParenStarComm := True; Exit; end;
      i := pClose + 2; Continue;
    end;
    // Compiler-Direktive {$...} ist schon ueber `{` oben geskippt.
    // String mit #-Codes (#13#10): einfach durch das #-Zeichen lassen,
    // der nachfolgende Identifier-Test schlaegt fehl da '#' kein Ident-
    // Start ist.
    if IsIdentStart(c) then
    begin
      wStart := i;
      while (i <= n) and IsIdent(Line[i]) do Inc(i);
      Word := Copy(Line, wStart, i - wStart);
      Lower := LowerCase(Word);
      if IsKeyword(Lower) and (Word <> Lower) then
      begin
        Hit.Col  := wStart;
        Hit.Word := Word;
        Hits.Add(Hit);
      end;
      Continue;
    end;
    Inc(i);
  end;
end;

class procedure TLowercaseKeywordDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines          : TStringList;
  Hits           : TList<TKwHit>;
  i              : Integer;
  InBlk, InParen : Boolean;
  Cached         : Boolean;
  Hit            : TKwHit;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  Hits := TList<TKwHit>.Create;
  try
    InBlk   := False;
    InParen := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Hits.Clear;
      CollectMixedCaseKeywords(Lines[i], InBlk, InParen, Hits);
      for Hit in Hits do
        Results.Add(TLeakFinding.New(FileName, '', i + 1,
          Format('Keyword "%s" should be lowercase ("%s") at column %d.',
            [Hit.Word, LowerCase(Hit.Word), Hit.Col]),
          fkLowercaseKeyword));
    end;
  finally
    Hits.Free;
    ReleaseLines(Lines, Cached);
  end;
end;

end.
