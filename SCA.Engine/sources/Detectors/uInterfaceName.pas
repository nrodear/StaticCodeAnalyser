unit uInterfaceName;

// Detektor fuer Interface-Typen ohne `I`-Prefix.
//
// SonarDelphi-Aequivalent: communitydelphi:InterfaceName. Delphi-
// Konvention: Interface-Typen heissen `IFoo` (analog zu `TFoo` fuer
// Klassen, `PFoo` fuer Pointer). Der `I`-Prefix signalisiert Vertrag
// statt Implementierung.
//
// Erkennung: lexikalisch ueber die Zeile. Pattern `<Ident> = interface`
// (optional `<Ident> = interface(IParent)`, auch mit GUID `['{...}']`).
// Name muss mit `I` beginnen. Die Vorwaertsdeklaration
// `<Ident> = interface;` wird UEBERSPRUNGEN - sie deklariert keinen
// eigenen Typ, und die Volldeklaration desselben Namens steht in derselben
// Unit und meldet den Verstoss genau einmal.
//
// AUSNAHMEN (Hebel A, 30%-Audit 2026-07-31 - 15.707 Funde, 100 % FP im
// Sample):
//   * generierte COM-Typelib-Importe (`*_TLB.pas`)
//   * ObjC-/JNI-Bridge-Interfaces - dort IST der Interface-Name der
//     native Klassenname (ObjC) bzw. folgt der offiziellen
//     J<Name>-Konvention der Androidapi-RTL; die I-Konvention ist dort
//     bewusst ausser Kraft und eine Umbenennung braeche die Bridge.
// Beide Gates liegen in TDetectorUtils (IsGeneratedTypelibFile /
// CollectFfiBindingTypes), die Kriterien-Auswahl ist dort dokumentiert.
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext,
  uDetectorUtils;   // H2445: inline-Expansion braucht iface-Sichtbarkeit

type
  TInterfaceNameDetector = class
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

function FindBadInterfaceName(const Line: string; var InBlockComm: Boolean;
  var InParenStarComm: Boolean; out Name: string): Integer;
var
  i, n, j, k : Integer;
  InStr      : Boolean;
  pClose     : Integer;
  c          : Char;
  Start      : Integer;
  NextWord   : string;
begin
  Result := 0;
  Name   := '';
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
      // Skip ws
      j := i;
      while (j <= n) and CharInSet(Line[j], [' ', #9]) do Inc(j);
      // Optional Generic-Klammer `<...>`
      if (j <= n) and (Line[j] = '<') then
      begin
        Inc(j);
        while (j <= n) and (Line[j] <> '>') do Inc(j);
        if j <= n then Inc(j);
        while (j <= n) and CharInSet(Line[j], [' ', #9]) do Inc(j);
      end;
      // Erwarte `=`
      if (j > n) or (Line[j] <> '=') then Continue;
      Inc(j);
      while (j <= n) and CharInSet(Line[j], [' ', #9]) do Inc(j);
      // Erwarte `interface` oder `dispinterface`
      if (j > n) or not IsIdentStart(Line[j]) then Continue;
      k := j;
      while (k <= n) and IsIdent(Line[k]) do Inc(k);
      NextWord := LowerCase(Copy(Line, j, k - j));
      if (NextWord <> 'interface') and (NextWord <> 'dispinterface') then
        Continue;
      // Vorwaertsdeklaration `Foo = interface;` ueberspringen (Voll-Review
      // 2026-09-13). Sie deklariert keinen eigenen Typ und erzeugt keinen
      // AST-Knoten; zusammen mit der Volldeklaration ergab sie ZWEI Funde
      // fuer EINEN Typ (Korpus: cnwizards TestTypeDefs.pas, TBob Z.24+97
      // und TBobDisp Z.25+100 - die einzigen zwei Faelle).
      // Am A/B des Referenzlaufs 2026-09-13 nachgemessen: 35 -> 33.
      // Die frueher hier stehenden 15 -> 13 kamen aus einem anders
      // zugeschnittenen Lauf; die BEWEGUNG von -2 stimmte.
      //
      // Kein Typ geht dabei verloren: von den 4.568 Vorwaertsdeklarationen
      // des Korpus, die Gate 1 passieren, traegt KEINE einen Namen ohne
      // Volldeklaration in derselben Datei. k steht hinter dem Wort
      // 'interface' und wird danach nicht mehr gebraucht - keine neue
      // Variable noetig.
      while (k <= n) and CharInSet(Line[k], [' ', #9]) do Inc(k);
      if (k <= n) and (Line[k] = ';') then Continue;
      // Pruefe Name
      if (Length(Name) >= 1) and CharInSet(Name[1], ['I', 'i']) then Continue;
      Result := Start;
      Exit;
    end;
    Inc(i);
  end;
end;

class procedure TInterfaceNameDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines  : TStringList;
  i, Col : Integer;
  InBlk, InParen : Boolean;
  F      : TLeakFinding;
  Cached : Boolean;
  Name   : string;
  // Hebel A: FFI-Binding-Typnamen der Unit. LAZY - erst beim ersten
  // Kandidaten gebaut, damit die 99 % Dateien ohne Fund keinen
  // AST-Walk bezahlen.
  FfiTypes : TStringList;
begin
  // Gate 1 (Hebel A): generierte Typelib-Importe komplett ausnehmen.
  // Steht VOR dem Lines-Load - spart bei diesen (durchweg riesigen)
  // Dateien auch noch das Einlesen.
  if TDetectorUtils.IsGeneratedTypelibFile(FileName) then Exit;
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  FfiTypes := nil;
  try
    InBlk   := False;
    InParen := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Col := FindBadInterfaceName(Lines[i], InBlk, InParen, Name);
      if Col <= 0 then Continue;
      // Gate 2 (Hebel A): ObjC-/JNI-Bridge-Interface. Nachgeschlagen wird
      // der NAME (`EKEventStore`). Die Vorwaerts-Deklaration erreicht diese
      // Stelle seit dem fwd-Skip in FindBadInterfaceName nicht mehr; sie
      // erzeugt ohnehin keinen AST-Knoten, gegated wird die vollstaendige
      // Deklaration weiter unten in derselben Unit.
      if FfiTypes = nil then
        FfiTypes := TDetectorUtils.CollectFfiBindingTypes(UnitNode);
      if TDetectorUtils.IsFfiBindingTypeName(FfiTypes, Name) then Continue;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(i + 1);
      F.MissingVar := Format(
        'Interface `%s` does not follow `I<Name>` naming convention - ' +
        'rename to start with `I`.', [Name]);
      F.SetKind(fkInterfaceName);
      Results.Add(F);
    end;
  finally
    FfiTypes.Free;
    ReleaseLines(Lines, Cached);
  end;
end;

end.
