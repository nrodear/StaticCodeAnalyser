unit uPointerName;

// Detektor fuer Pointer-Typen, deren Name nicht mit `P` beginnt.
//
// SonarDelphi-Aequivalent: communitydelphi:PointerName (Naming-
// Convention). Delphi-Konvention seit Anfang: ein Pointer-Alias auf
// `TXxx` heisst `PXxx` - so erkennt der Leser am Namen die Indirektion.
//   * GUT:   PInteger = ^Integer;
//   * SCHLECHT: TIntPtr = ^Integer;
//
// Erkennung: lexikalisch ueber komment-bereinigten Code. Pattern
//   `<Ident> = ^<Type>` wo `<Ident>` nicht mit `P`/`p` beginnt.
//
// Schweregrad: lsHint - reines Convention/Naming.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext,
  uDetectorUtils;   // H2445: inline-Expansion braucht iface-Sichtbarkeit

type
  TPointerNameDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file BeginEndRequired, ConsecutiveSection, CyclomaticComplexity, GroupedDeclaration, IfElseBegin, LongMethod, MultipleExit, NilComparison, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils,
  uFileTextCache;

function IsIdent(C: Char): Boolean; inline;
begin
  // Backlog-Welle 1, 2026-07-26: Zeichenklasse zentralisiert - die
  // lokale Fassung war zeichenweise identisch zu
  // TDetectorUtils.IsIdentChar (a..z, A..Z, 0..9, _). Der Wrapper
  // bleibt, damit die Aufrufer in dieser Unit unveraendert bleiben.
  Result := TDetectorUtils.IsIdentChar(C);
end;

function IsIdentStart(C: Char): Boolean; inline;
begin
  // Voll-Review 2026-09-12: Zeichenklasse zentralisiert - die lokale
  // Fassung war zeichenweise identisch zu
  // TDetectorUtils.IsIdentStartChar (A..Z, a..z, _). Der Wrapper
  // bleibt, damit die Aufrufer in dieser Unit unveraendert bleiben.
  Result := TDetectorUtils.IsIdentStartChar(C);
end;

// Erstes Wort der Zeile, lowercased; leer bei Leer-/Kommentar-/
// Sonderzeichen-Zeilen. Fuer das Sektions-Gate in AnalyzeUnit.
function FirstWordLow(const Line: string): string;
var
  i, n, w : Integer;
begin
  Result := '';
  n := Length(Line);
  i := 1;
  while (i <= n) and CharInSet(Line[i], [' ', #9]) do Inc(i);
  if (i > n) or not IsIdentStart(Line[i]) then Exit;
  w := i;
  while (i <= n) and IsIdent(Line[i]) do Inc(i);
  Result := LowerCase(Copy(Line, w, i - w));
end;

// True wenn das Wort eine type-Sektion BEENDET (Sektions-Keywords und
// Routinen-Koepfe). 'end' fehlt BEWUSST: das end eines record/class
// beendet die umgebende type-Sektion nicht - 'TRec = record ... end;
// TBad = ^TRec;' ist derselbe Block und muss meldbar bleiben.
// Dokumentierte Grenze: eine Methodenzeile INNERHALB einer
// Klassendeklaration ('    procedure X;') schaltet ebenfalls aus -
// ein Nicht-P-Alias NACH einer Klasse in derselben type-Sektion wird
// dann erst ab dem naechsten 'type' wieder gesehen (seltene Form;
// derselbe Zuschnitt wie der Sektions-Tracker in uRedundantBoolean).
function EndsTypeSection(const W: string): Boolean;
begin
  Result := (W = 'const') or (W = 'resourcestring') or (W = 'var')
         or (W = 'threadvar') or (W = 'label') or (W = 'uses')
         or (W = 'begin') or (W = 'procedure') or (W = 'function')
         or (W = 'constructor') or (W = 'destructor')
         or (W = 'operator') or (W = 'class') or (W = 'property')
         or (W = 'implementation') or (W = 'interface')
         or (W = 'initialization') or (W = 'finalization')
         or (W = 'exports');
end;

// Liefert Spalte des Ident wenn die Zeile ein Pointer-Typ-Alias
// definiert dessen Name NICHT mit `P` beginnt.
function FindBadPointerName(const Line: string; var InBlockComm: Boolean;
  var InParenStarComm: Boolean): Integer;
var
  i, n, j  : Integer;
  InStr    : Boolean;
  pClose   : Integer;
  c        : Char;
  Start    : Integer;
  Name     : string;
begin
  Result := 0;
  InStr  := False;
  i := 1;
  n := Length(Line);
  while i <= n do
  begin
    if InBlockComm then
    begin
      pClose := PosEx('}', Line, i);
      if pClose = 0 then Exit;
      InBlockComm := False;
      i := pClose + 1; Continue;
    end;
    if InParenStarComm then
    begin
      pClose := PosEx('*)', Line, i);
      if pClose = 0 then Exit;
      InParenStarComm := False;
      i := pClose + 2; Continue;
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
    if IsIdentStart(c) then
    begin
      Start := i;
      while (i <= n) and IsIdent(Line[i]) do Inc(i);
      Name := Copy(Line, Start, i - Start);
      // Skip whitespace
      j := i;
      while (j <= n) and CharInSet(Line[j], [' ', #9]) do Inc(j);
      // Erwarte `=`
      if (j > n) or (Line[j] <> '=') then Continue;
      Inc(j);
      // Skip whitespace
      while (j <= n) and CharInSet(Line[j], [' ', #9]) do Inc(j);
      // Erwarte `^`
      if (j > n) or (Line[j] <> '^') then Continue;
      Inc(j);
      // Skip whitespace
      while (j <= n) and CharInSet(Line[j], [' ', #9]) do Inc(j);
      // Erwarte einen Identifier (oder qualifizierte Type-Ref)
      if (j > n) or not IsIdentStart(Line[j]) then Continue;
      // Pruefe Name: muss mit `P`/`p` beginnen.
      if (Length(Name) >= 1) and CharInSet(Name[1], ['P', 'p']) then Continue;
      Result := Start;
      Exit;
    end;
    Inc(i);
  end;
end;

class procedure TPointerNameDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines  : TStringList;
  i, Col : Integer;
  InBlk, InParen : Boolean;
  F      : TLeakFinding;
  Cached : Boolean;
  InTypeSec : Boolean;
  W      : string;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    InBlk   := False;
    InParen := False;
    InTypeSec := False;
    for i := 0 to Lines.Count - 1 do
    begin
      // Sektions-Gate (Voll-Review 2026-09-12, Blocker): das Muster
      // '<Ident> = ^<Ident>' ist nur in einer TYPE-Sektion ein
      // Pointer-Alias. Delphis Caret-Notation fuer Steuerzeichen
      // matcht dasselbe Muster - 'const CR = ^M;' und
      // 'if Key = ^C then' erzeugten den Fund 'rename to start with
      // P', ohne dass irgendwo ein Pointer-Typ deklariert wird.
      // Zustand nur ausserhalb offener Blockkommentare nachfuehren;
      // die Wertung passiert VOR dem Zeilen-Scan (der Zustand gilt am
      // Zeilenanfang), das Melde-Gate NACH ihm, damit InBlk/InParen
      // fuer Folgezeilen immer gepflegt werden.
      if not (InBlk or InParen) then
      begin
        W := FirstWordLow(Lines[i]);
        if W = 'type' then
          InTypeSec := True
        else if EndsTypeSection(W) then
          InTypeSec := False;
      end;
      Col := FindBadPointerName(Lines[i], InBlk, InParen);
      if Col <= 0 then Continue;
      if not InTypeSec then Continue;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(i + 1);
      F.MissingVar := Format(
        'Pointer-type alias at column %d does not follow `P<TypeName>` ' +
        'naming convention - rename to start with `P`.', [Col]);
      F.SetKind(fkPointerName);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
