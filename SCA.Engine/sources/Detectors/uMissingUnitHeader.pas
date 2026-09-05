unit uMissingUnitHeader;

// Detektor: Unit beginnt ohne erklaerenden Kommentar-Block.
//
// Pattern (Code Smell, Sonar-50 #48):
//   unit MyUnit;
//
//   interface                       // <-- direkt zur Sache, kein Kommentar
//
//   uses ...;
//
// Korrekt:
//   unit MyUnit;
//
//   // Diese Unit verwaltet die Verbindung zur Datenbank. Sie kapselt
//   // die FireDAC-Connection-Pool-Logik und liefert eine schmale API
//   // fuer hoehere Layer.
//
//   interface
//
// Erkennung (Lexer/Lines):
//   * Lies Zeilen bis zum ersten `interface`-Keyword.
//   * Erwarte mindestens EINE nicht-leere Kommentarzeile (`//` oder
//     `{ ... }` oder `(* ... *)`) zwischen `unit X;` und `interface`.
//   * Falls keine Kommentarzeile -> Finding auf Zeile 1.
//
// Limitierungen:
//   * Multi-line block-comments mit { kombiniert mit Code in einer Zeile
//     werden grob erkannt - kein voller Lexer.
//   * Generated-code-Marker (`{ ... do not edit ... }`) zaehlen mit.
//
// Schweregrad: lsHint - Empfehlung, viele Legacy-Units haben kein Header.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TMissingUnitHeaderDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file CyclomaticComplexity, GroupedDeclaration, NilComparison, RedundantJump, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uDetectorUtils,   // IsTestFixturePath (Geltungsbereich-Gate)
  uFileTextCache;

function LineHasComment(const ALine: string): Boolean;
var
  T : string;
begin
  T := Trim(ALine);
  Result := (T <> '')
            and ((Copy(T, 1, 2) = '//')
                 or (Copy(T, 1, 1) = '{')
                 or (Copy(T, 1, 2) = '(*'));
end;

function LineIsUnitDecl(const ALine: string): Boolean;
// Eine ECHTE unit-Klausel: "unit" + Bezeichner (qualifiziert erlaubt) +
// optionale Hint-Direktive + Semikolon.
//
// Der alte Test war nur Copy(T,1,5) = 'unit ' und traf damit jede
// Kommentarzeile, die mit dem Wort beginnt. pyscripters Kopfvorlage
// schreibt in Zeile 2 ' Unit Name: frmProjectExplorer' - der Detektor
// hielt das fuer die Klausel und prueste anschliessend den Bereich
// DAHINTER auf einen Kopfkommentar. Der beschreibende Kopf steht dort
// aber DAVOR und blieb unsichtbar (AQL-Messung Hint-Tier 03.09.:
// frmProjectExplorer.pas:2, uEditAppIntfs.pas:2).
//
// Bewusst ohne Regex und ohne Kommentar-Zustand: es genuegt, dass eine
// Prosazeile die Form nicht erfuellt. ' Unit Name: X' scheitert am
// fehlenden Semikolon und am Leerzeichen im "Bezeichner".
var
  T    : string;
  i, n : Integer;
begin
  Result := False;
  T := LowerCase(Trim(ALine));
  if Copy(T, 1, 5) <> 'unit ' then Exit;
  i := 6;
  n := Length(T);
  while (i <= n) and (T[i] = ' ') do Inc(i);
  if i > n then Exit;
  // Bezeichner, Punkte fuer qualifizierte Namen erlaubt
  if not CharInSet(T[i], ['a'..'z', '_']) then Exit;
  while (i <= n) and CharInSet(T[i], ['a'..'z', '0'..'9', '_', '.']) do Inc(i);
  while (i <= n) and (T[i] = ' ') do Inc(i);
  // optionale Hint-Direktiven vor dem Semikolon
  for var Hint in ['deprecated', 'platform', 'library', 'experimental'] do
    if Copy(T, i, Length(Hint)) = Hint then
    begin
      Inc(i, Length(Hint));
      while (i <= n) and (T[i] <> ';') do Inc(i);
      Break;
    end;
  Result := (i <= n) and (T[i] = ';');
end;

function LineIsInterface(const ALine: string): Boolean;
var
  T : string;
begin
  T := LowerCase(Trim(ALine));
  Result := (T = 'interface') or (Copy(T, 1, 10) = 'interface ');
end;

class procedure TMissingUnitHeaderDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines  : TStringList;
  Cached : Boolean;
  i, UnitLine, IfaceLine : Integer;
  HasComment : Boolean;
begin
  // Geltungsbereich-Gate (Produktentscheidung Nico 2026-09-05, analog
  // dem SCA001-Gate vom 2026-08-05): Testunits dokumentieren sich
  // ueber ihre Testnamen - ein fehlender Unit-Header in Test-,
  // Sample- und Demo-Pfaden ist kein Fund. Beleg am eigenen Repo:
  // SCA143 feuerte 90x, ausnahmslos headerlose Testunits.
  // GEMESSEN rw63 VOR dem Bau: 4.084 von 6.860 Korpus-Funden
  // (59,5 %) liegen in tplFixtureDir-Segmenten ('tests' 2.360,
  // 'samples' 1.140, 'demos' 290, 'unittests' 164, 'test' 130).
  // Stufe tplFixtureDir = NUR Verzeichnis-Segmente, an der
  // Scanwurzel verankert - Begruendung der Stufe steht am
  // SCA001-Gate (uLeakDetector2.AnalyzeUnit).
  if TDetectorUtils.IsTestFixturePath(FileName,
       CtxScanRoot(AContext), tplFixtureDir) then Exit;

  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    UnitLine  := -1;
    IfaceLine := -1;
    for i := 0 to Lines.Count - 1 do
    begin
      if (UnitLine < 0) and LineIsUnitDecl(Lines[i]) then
        UnitLine := i;
      if LineIsInterface(Lines[i]) then
      begin
        IfaceLine := i;
        Break;
      end;
    end;
    if (UnitLine < 0) or (IfaceLine < 0) then Exit;

    HasComment := False;
    for i := UnitLine + 1 to IfaceLine - 1 do
      if LineHasComment(Lines[i]) then
      begin
        HasComment := True;
        Break;
      end;
    if HasComment then Exit;

    Results.Add(TLeakFinding.New(FileName, '', UnitLine + 1,
      'Unit has no descriptive header comment between `unit ...;` and `interface`',
      fkMissingUnitHeader));
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
