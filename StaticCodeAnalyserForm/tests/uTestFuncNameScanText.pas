unit uTestFuncNameScanText;

// Tests fuer TFuncNameScan.ScanText (SCA204/SCA205, Scanner ohne AST): die
// Randfaelle des Tempo-Umbaus Charge R / R1 (2026-10-25) - Token als
// Spannen, Vorfilter CanHit ('Funktionsname :=' als notwendige Bedingung,
// Namensmenge aus dem Kopf, Vergleich ohne Gross/Klein), Direktiven-Rumpf
// als Spanne, AWantAssign. Jede Quelle ist mit dem echten Scanner (FPC-
// Harness, scratchpad chargeR/R1/h) vor und nach dem Umbau nachgerechnet
// (gleiche Treffer). Die Detektor-Tests stehen in uTestFunctionNameResult.

interface

uses
  DUnitX.TestFramework,
  uFuncNameResultScan;

type
  [TestFixture]
  TTestFuncNameScanText = class
  public
    // '&Begin' im Kopf: der kurze Name ohne '&' steht in der Namensmenge.
    [Test] procedure Filter_EscapedHeadName_Scanned;
    // 'TFoo<T: class>.Get', 'TBar<A; B>.Sub.Item': der kurze Name hinter
    // Typargumenten und Punkten.
    [Test] procedure Filter_GenericAndDottedHead_Scanned;
    // 'case'-Label ('1: Foo :=') und jede Schreibweise ('foo:=', 'FOO:=').
    [Test] procedure Filter_CaseLabelAndAnyCase_Scanned;
    // Kommentar bzw. nicht gelesener IFDEF-Zweig zwischen Name und ':='.
    [Test] procedure Filter_CommentOrSkippedBranchBeforeAssign_Scanned;
    // Der Name wird nur in einer FREMDEN Routine zugewiesen: kein Treffer.
    [Test] procedure Filter_NameAssignedOutsideOwnBody_NoHit;
    // AWantAssign = False (SCA204 nicht im Profil): nur die Lese-Treffer.
    [Test] procedure WantAssign_False_OnlyReads;
    // '(*$mode objfpc*)' zaehlt als Direktive; Kommentare, offenes '(*'.
    [Test] procedure Lexer_DirectiveInParenStarComment_Counts;
    // 3000 verschiedene Woerter gleicher Laenge: jedes Token behaelt seinen
    // Text (MaterializeAll teilt Zeichenketten nur bei gleichen Zeichen).
    [Test] procedure Materialize_ManyNamesOfEqualLength_KeepTheirText;
  end;

implementation

uses
  System.SysUtils;

const
  CRLF = #13#10;

  SRC_ESCAPED =
    'unit t;' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    'function &Begin: Integer;' + CRLF +
    'begin' + CRLF +
    '  &Begin := 1;' + CRLF +
    '  Begin := 2;' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;

  SRC_GENERIC =
    'unit t;' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    'function TFoo<T: class>.Get: T;' + CRLF +
    'begin' + CRLF +
    '  Get := nil;' + CRLF +
    'end;' + CRLF +
    'function TBar<A; B>.Sub.Item: Integer;' + CRLF +
    'begin' + CRLF +
    '  Item := Item + 1;' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;

  SRC_CASELABEL =
    'unit t;' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    'function Foo(X: Integer): Integer;' + CRLF +
    'begin' + CRLF +
    '  case X of' + CRLF +
    '    1: Foo := 2;' + CRLF +
    '  else Result := 3;' + CRLF +
    '  end;' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;

  SRC_ANYCASE =
    'unit t;' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    'FUNCTION Foo: Integer;' + CRLF +
    'BEGIN' + CRLF +
    '  foo:=1;' + CRLF +
    '  FOO:=foo+1' + CRLF +
    'END;' + CRLF +
    'end.' + CRLF;

  SRC_COMMENT =
    'unit t;' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    'function Foo: Integer;' + CRLF +
    'begin' + CRLF +
    '  Foo {c} := 1;' + CRLF +
    '  Foo (*d*) := Foo + 1;' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;

  // Delphi-Scan: der FPC-Zweig wird nicht gelesen, 'Foo' und ':=' stehen
  // in der Token-Folge nebeneinander.
  SRC_SKIPPED =
    'unit t;' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    'function Foo: Integer;' + CRLF +
    'begin' + CRLF +
    '  Foo {$IFDEF FPC} bar {$ENDIF} := 1;' + CRLF +
    '  Foo := Foo + 1;' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;

  // Gegenprobe: der gelesene Zweig trennt Name und ':='.
  SRC_READBRANCH =
    'unit t;' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    'function Foo: Integer;' + CRLF +
    'begin' + CRLF +
    '  Foo {$IFNDEF FPC} bar {$ENDIF} := 1;' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;

  // 'Count' steht im Kopf und wird zugewiesen - aber in P, nicht im
  // eigenen Rumpf (der Vorfilter laesst die Datei durch, der Scanner
  // meldet nichts).
  SRC_FOREIGN =
    'unit t;' + CRLF +
    'interface' + CRLF +
    'function Count: Integer;' + CRLF +
    'implementation' + CRLF +
    'procedure P;' + CRLF +
    'begin' + CRLF +
    '  Count := 1;' + CRLF +
    'end;' + CRLF +
    'function Count: Integer;' + CRLF +
    'begin' + CRLF +
    '  Result := 0;' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;

  SRC_TOTAL =
    'unit t;' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    'function Total: Integer;' + CRLF +
    'var' + CRLF +
    '  I: Integer;' + CRLF +
    'begin' + CRLF +
    '  Total := 0;' + CRLF +
    '  for I := 1 to 3 do' + CRLF +
    '    Total := Total + I;' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;

  SRC_OBJFPC =
    'unit t;' + CRLF +
    '{$mode objfpc}' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    'function Foo: Integer;' + CRLF +
    'begin' + CRLF +
    '  Foo := 1;' + CRLF +
    '  Foo := Foo + 1;' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;

  SRC_PARENSTAR =
    'unit t;' + CRLF +
    '(*$mode objfpc*)' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    'function Foo: Integer;' + CRLF +
    'begin' + CRLF +
    '  { Foo := Foo + 1; }' + CRLF +
    '  Foo := 1;' + CRLF +
    '  Foo := Foo + 1;' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF +
    '(* offen';

function CountOf(const AHits: TFuncNameHits; AUse: TFuncNameUse): Integer;
var
  H : TFuncNameHit;
begin
  Result := 0;
  for H in AHits do
    if H.Use = AUse then
      Inc(Result);
end;

procedure CheckCounts(const AHits: TFuncNameHits; AAssign, ARead: Integer;
  const AWhy: string);
begin
  Assert.AreEqual<Integer>(AAssign, CountOf(AHits, fnuAssign),
    'Zuweisungen: ' + AWhy);
  Assert.AreEqual<Integer>(ARead, CountOf(AHits, fnuRead),
    'Lese-Stellen: ' + AWhy);
end;

procedure TTestFuncNameScanText.Filter_EscapedHeadName_Scanned;
var
  H : TFuncNameHits;
begin
  H := TFuncNameScan.ScanText(SRC_ESCAPED, True);
  // '&Begin :=' ist ein anderes Wort als der Name; 'Begin :=' traegt ihn.
  CheckCounts(H, 1, 0, '&Begin');
  Assert.AreEqual<Integer>(7, H[0].Line, 'Zeile');
  Assert.AreEqual('Begin', H[0].Routine, 'Routine');
end;

procedure TTestFuncNameScanText.Filter_GenericAndDottedHead_Scanned;
var
  H : TFuncNameHits;
begin
  H := TFuncNameScan.ScanText(SRC_GENERIC, True);
  CheckCounts(H, 2, 1, 'TFoo<T: class>.Get / TBar<A; B>.Sub.Item');
  Assert.AreEqual('TFoo.Get', H[0].Routine, 'erste Routine');
  Assert.AreEqual('TBar.Sub.Item', H[2].Routine, 'Lese-Stelle in Item');
  Assert.AreEqual<Integer>(10, H[2].Line, 'Zeile der Lese-Stelle');
end;

procedure TTestFuncNameScanText.Filter_CaseLabelAndAnyCase_Scanned;
var
  H : TFuncNameHits;
begin
  H := TFuncNameScan.ScanText(SRC_CASELABEL, True);
  CheckCounts(H, 1, 0, 'nur hinter dem case-Label');
  Assert.AreEqual<Integer>(7, H[0].Line, 'Zeile hinter dem case-Label');
  H := TFuncNameScan.ScanText(SRC_ANYCASE, True);
  CheckCounts(H, 2, 1, 'foo:= / FOO:=foo+1');
  Assert.AreEqual('FOO', H[1].Written, 'wie geschrieben');
end;

procedure TTestFuncNameScanText.Filter_CommentOrSkippedBranchBeforeAssign_Scanned;
begin
  CheckCounts(TFuncNameScan.ScanText(SRC_COMMENT, True), 2, 1,
    'Kommentar zwischen Name und :=');
  CheckCounts(TFuncNameScan.ScanText(SRC_SKIPPED, True), 2, 1,
    'nicht gelesener FPC-Zweig zwischen Name und :=');
  CheckCounts(TFuncNameScan.ScanText(SRC_READBRANCH, True), 0, 0,
    'gelesener Zweig trennt Name und :=');
end;

procedure TTestFuncNameScanText.Filter_NameAssignedOutsideOwnBody_NoHit;
begin
  CheckCounts(TFuncNameScan.ScanText(SRC_FOREIGN, True), 0, 0,
    'Count := 1 steht in P');
  // Wache: dieselbe Zuweisung im eigenen Rumpf wird gemeldet.
  CheckCounts(TFuncNameScan.ScanText(StringReplace(SRC_FOREIGN,
    'Result := 0', 'Count := 0', []), True), 1, 0, 'Count := 0 in Count');
end;

procedure TTestFuncNameScanText.WantAssign_False_OnlyReads;
var
  H, R : TFuncNameHits;
begin
  H := TFuncNameScan.ScanText(SRC_TOTAL, True);
  CheckCounts(H, 2, 1, 'Total mit SCA204');
  R := TFuncNameScan.ScanText(SRC_TOTAL, True, False);
  CheckCounts(R, 0, 1, 'Total ohne SCA204');
  Assert.AreEqual<Integer>(H[2].Line, R[0].Line, 'dieselbe Lese-Stelle');
  Assert.AreEqual<Integer>(H[2].Col, R[0].Col, 'dieselbe Spalte');
  Assert.AreEqual<Boolean>(H[2].Proven, R[0].Proven, 'dieselbe Schwere');
  CheckCounts(TFuncNameScan.ScanText(SRC_OBJFPC, True), 2, 0,
    'objfpc mit SCA204');
  CheckCounts(TFuncNameScan.ScanText(SRC_OBJFPC, True, False), 0, 0,
    'objfpc ohne SCA204: nichts zu melden');
end;

procedure TTestFuncNameScanText.Lexer_DirectiveInParenStarComment_Counts;
begin
  // objfpc aus '(*$..*)': Lesen ist dort das Ergebnis - nur Zuweisungen;
  // der Kommentar '{ Foo := Foo + 1; }' zaehlt nicht.
  CheckCounts(TFuncNameScan.ScanText(SRC_PARENSTAR, True), 2, 0,
    '(*$mode objfpc*)');
  // Gegenprobe: ohne die Direktive liest Delphi rekursiv.
  CheckCounts(TFuncNameScan.ScanText(StringReplace(SRC_PARENSTAR,
    '(*$mode objfpc*)', '(* mode objfpc *)', []), True), 2, 1,
    'ohne Direktive');
end;

procedure TTestFuncNameScanText.Materialize_ManyNamesOfEqualLength_KeepTheirText;
var
  Src : string;
  H : TFuncNameHits;
  i : Integer;
begin
  Src := 'unit t;' + CRLF + 'interface' + CRLF + 'implementation' + CRLF +
    'procedure P;' + CRLF + 'begin' + CRLF;
  for i := 0 to 2999 do
    Src := Src + Format('  Q%.4d := 0;', [i]) + CRLF;
  Src := Src + 'end;' + CRLF +
    'function Q9999: Integer;' + CRLF +
    'begin' + CRLF +
    '  Q9999 := 1;' + CRLF +
    '  Q9999 := Q9999 + 1;' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;
  H := TFuncNameScan.ScanText(Src, True);
  CheckCounts(H, 2, 1, 'Q9999 neben Q0000..Q2999');
  for i := 0 to High(H) do
  begin
    Assert.AreEqual('Q9999', H[i].Written, 'Text des Treffers');
    Assert.AreEqual('Q9999', H[i].Routine, 'Routine');
  end;
  Assert.AreEqual<Integer>(3009, H[0].Line, 'Zeile der ersten Zuweisung');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFuncNameScanText);

end.
