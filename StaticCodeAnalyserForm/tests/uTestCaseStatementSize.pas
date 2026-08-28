unit uTestCaseStatementSize;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCaseStatementSize = class
  public
    [Test] procedure SmallCase_NoFinding;
    [Test] procedure LargeCase_Reported;
    [Test] procedure CaseStatementSize_KindAndSeverity;
    [Test] procedure SqlLiteralCase_NoPhantomFinding;
    [Test] procedure LiteralEndBeforeRealCase_StillReported;
    // FP-Gates 2026-08-28 - je Klasse ein Drop-Test und ein
    // Ueberreichweiten-Waechter, siehe Kopf von uCaseStatementSize.pas.
    [Test] procedure NestedCase_InnerLabelsNotCounted;
    [Test] procedure LargeCaseWithBeginBlocks_StillReported;
    [Test] procedure QualifiedEnumLabel_DoesNotOpenBlock;
    [Test] procedure AsmBlockInBranch_EndDoesNotCloseCase;
    [Test] procedure RecordVariantPart_NoFinding;
    [Test] procedure ParenExprInBranch_StillReported;
    [Test] procedure InlineVarInBranch_NotCounted;
    [Test] procedure OnHandlerInBranch_NotCounted;
    [Test] procedure GotoLabelInBranch_NotCounted;
    [Test] procedure PhantomCaseInDisabledRegion_RealCaseReported;
    [Test] procedure TwoLineSelector_StillReported;
    // ABSTIEG 2026-08-28 - der Scan springt nicht mehr hinter das `end`,
    // sondern laeuft im Rumpf weiter. Jedes case wird nach seiner EIGENEN
    // Groesse beurteilt.
    [Test] procedure NestedCaseOverThreshold_ReportedSeparately;
    [Test] procedure OuterAndInnerBothOverThreshold_BothReported;
    [Test] procedure ThreeLevelNesting_InnermostReported;
    // Bezeichner-Schutz: zwei reale Schreibweisen, die die Block-Tiefe
    // faelschlich erhoehen und den Fund verschwinden lassen.
    [Test] procedure QualifiedLabelAcrossLineBreak_DoesNotOpenBlock;
    [Test] procedure AmpersandEscapedKeyword_DoesNotOpenBlock;
    [Test] procedure ThreeDottedLabels_MatchingEndStillFound;
    // Restklasse geschlossen: nackte inline-var direkt im Zweig.
    [Test] procedure NakedInlineVarInBranch_NotCounted;
    // K6-Spielraum nach der Neukalibrierung auf 20 Zeilen.
    [Test] procedure EightLineSelector_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestCaseStatementSize.SmallCase_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; var X: Integer;'#13#10 +
  'begin'#13#10 +
  '  case X of'#13#10 +
  '    1: A;'#13#10 +
  '    2: B;'#13#10 +
  '    3: C;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCaseStatementSize));
  finally F.Free; end;
end;

procedure TTestCaseStatementSize.LargeCase_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; var X: Integer;'#13#10 +
  'begin'#13#10 +
  '  case X of'#13#10 +
  '    1: A1;  2: A2;  3: A3;  4: A4;  5: A5;'#13#10 +
  '    6: A6;  7: A7;  8: A8;  9: A9; 10: A10;'#13#10 +
  '   11: A11;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCaseStatementSize));
  finally F.Free; end;
end;

procedure TTestCaseStatementSize.CaseStatementSize_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; var X: Integer;'#13#10 +
  'begin'#13#10 +
  '  case X of'#13#10 +
  '    1: A; 2: B; 3: C; 4: D; 5: E;'#13#10 +
  '    6: F; 7: G; 8: H; 9: I; 10: J;'#13#10 +
  '  end;'#13#10 +
  'end;';
var
  Findings : TObjectList<TLeakFinding>;
  Fnd      : TLeakFinding;
begin
  Findings := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in Findings do
      if Fnd.Kind = fkCaseStatementSize then
      begin
        Assert.AreEqual<TFindingKind>(fkCaseStatementSize, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,             Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkCaseStatementSize finding');
  finally Findings.Free; end;
end;

procedure TTestCaseStatementSize.SqlLiteralCase_NoPhantomFinding;
// Review-HIGH 2026-08-08: 'CASE WHEN ... END' in einem SQL-Literal
// startete einen Phantom-case - Literale werden jetzt geblankt.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  Q.SQL.Text := ''SELECT CASE WHEN a=1 THEN 1 WHEN a=2 THEN 2'' +'#13#10 +
  '    '' WHEN a=3 THEN 3 WHEN a=4 THEN 4 WHEN a=5 THEN 5 WHEN a=6'' +'#13#10 +
  '    '' THEN 6 WHEN a=7 THEN 7 WHEN a=8 THEN 8 WHEN a=9 THEN 9'' +'#13#10 +
  '    '' WHEN b=1 THEN 10 WHEN b=2 THEN 11 ELSE 0 END FROM t'';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCaseStatementSize));
  finally F.Free; end;
end;

procedure TTestCaseStatementSize.LiteralEndBeforeRealCase_StillReported;
// Ein 'END' in einem Literal darf das ECHTE case nicht vorzeitig
// schliessen - das grosse case danach muss weiter gemeldet werden.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; var Y: Integer;'#13#10 +
  'begin'#13#10 +
  '  Log(''outer CASE x END marker'');'#13#10 +
  // Zweignamen bewusst ANDERS als in LargeCase_Reported - sonst
  // meldet der Self-Scan die beiden Fixtures als DuplicateBlock.
  '  case Y of'#13#10 +
  '    1: C1;  2: C2;  3: C3;  4: C4;  5: C5;'#13#10 +
  '    6: C6;  7: C7;  8: C8;  9: C9; 10: C10;'#13#10 +
  '   11: C11;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCaseStatementSize));
  finally F.Free; end;
end;

// --- K1: Tiefe-1-Gate in CountBranches --------------------------------

procedure TTestCaseStatementSize.NestedCase_InnerLabelsNotCounted;
// Der aeussere case hat 6 eigene Zweige, das innere 5. Vor dem Gate
// zaehlte CountBranches beide zusammen (11 >= 10) und meldete den
// AEUSSEREN case mit einer Zahl, die ihm nicht gehoert.
// OHNE Gate rot: gemeldet wuerde 1 Fund in Zeile 4 mit 11 Zweigen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; var X, Y: Integer;'#13#10 +
  'begin'#13#10 +
  '  case X of'#13#10 +
  '    1: P1;'#13#10 +
  '    2: P2;'#13#10 +
  '    3: P3;'#13#10 +
  '    4: P4;'#13#10 +
  '    5: P5;'#13#10 +
  '    6: begin'#13#10 +
  '         case Y of'#13#10 +
  '           1: Q1; 2: Q2; 3: Q3; 4: Q4; 5: Q5;'#13#10 +
  '         end;'#13#10 +
  '       end;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCaseStatementSize));
  finally F.Free; end;
end;

procedure TTestCaseStatementSize.LargeCaseWithBeginBlocks_StillReported;
// Ueberreichweiten-Waechter zum Tiefenzaehler: 11 EIGENE Tiefe-1-Labels,
// jeder Zweig ein begin/end-Block. Der Zaehler muss nach jedem `end`
// sauber auf Tiefe 1 zurueckkommen, sonst verschwindet dieser echte Fund.
// OHNE Gate gruen (der Test war vorher schon gruen) - er faellt erst um,
// wenn der neue Tiefenzaehler ueberreicht.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; var X: Integer;'#13#10 +
  'begin'#13#10 +
  '  case X of'#13#10 +
  '     1: begin R1; end;'#13#10 +
  '     2: begin R2; end;'#13#10 +
  '     3: begin R3; end;'#13#10 +
  '     4: begin R4; end;'#13#10 +
  '     5: begin R5; end;'#13#10 +
  '     6: begin R6; end;'#13#10 +
  '     7: begin R7; end;'#13#10 +
  '     8: begin R8; end;'#13#10 +
  '     9: begin R9; end;'#13#10 +
  '    10: begin R10; end;'#13#10 +
  '    11: begin R11; end;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCaseStatementSize));
  finally F.Free; end;
end;

procedure TTestCaseStatementSize.QualifiedEnumLabel_DoesNotOpenBlock;
// Waechter fuer den Punkt-Schutz im Tiefenzaehler, nachgebaut nach
// python4delphi/Source/PythonDocs.pas:561: `TSymKind.Record:` ist ein
// case-LABEL, kein record-Blockanfang. Ohne den Punkt-Schutz erhoeht
// `Record` die Tiefe, die restlichen Labels zaehlen nicht mehr mit, der
// Fund faellt von 10 auf 8 Zweige - und verschwindet.
// OHNE den Punkt-Schutz rot: 0 Funde statt 1.
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo(K: TSymKind): string;'#13#10 +
  'begin'#13#10 +
  '  case K of'#13#10 +
  '    TSymKind.Constructor: Result := ''ctor'';'#13#10 +
  '    TSymKind.Destructor:  Result := ''dtor'';'#13#10 +
  '    TSymKind.Procedure:   Result := ''proc'';'#13#10 +
  '    TSymKind.Function:    Result := ''func'';'#13#10 +
  '    TSymKind.Enum:        Result := ''enum'';'#13#10 +
  '    TSymKind.Sett:        Result := ''sett'';'#13#10 +
  '    TSymKind.Record:      Result := ''rec'';'#13#10 +
  '    TSymKind.Klass:       Result := ''cls'';'#13#10 +
  '    TSymKind.Alias:       Result := ''alias'';'#13#10 +
  '    TSymKind.Unknown:     Result := ''unk'';'#13#10 +
  '  end;'#13#10 +
  'end;'#13#10 +
  ''#13#10 +
  'procedure Bar;'#13#10 +
  'begin'#13#10 +
  '  Baz;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCaseStatementSize));
  finally F.Free; end;
end;

procedure TTestCaseStatementSize.AsmBlockInBranch_EndDoesNotCloseCase;
// `asm` ist in dieser Runde NEU als Block-Oeffner - in FindMatchingEnd wie
// in CountBranches (das vor K1 gar keine Block-Tiefe kannte). Ein asm-Block
// wird mit `end` geschlossen wie jeder andere; zaehlt er nicht als Oeffner,
// schliesst SEIN `end` das umgebende case vorzeitig.
// Nachbau von cnwizards/Source/ThirdParty/PascalScript/uPSCompiler.pas:1844
// (`asm int 3; end;`); im Korpus berechnen 22 case-Stellen mit dem Oeffner
// ein anderes `end`.
// OHNE den asm-Oeffner rot: FindMatchingEnd liefert das `end` des
// asm-Blocks, CountBranches sieht nur noch den ersten Zweig - 1 statt 10
// Zweige, also 0 Funde. Beide Haelften des Oeffners fallen mit diesem
// einen Fixture um: nimmt man ihn nur aus CountBranches heraus, zieht
// dasselbe `end` die Tiefe auf 0 und die Labels 2..10 zaehlen ebenfalls
// nicht mehr mit.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; var X: Integer;'#13#10 +
  'begin'#13#10 +
  '  case X of'#13#10 +
  '     1: asm'#13#10 +
  '          nop'#13#10 +
  '        end;'#13#10 +
  '     2: S2;  3: S3;  4: S4;  5: S5;'#13#10 +
  '     6: S6;  7: S7;  8: S8;  9: S9; 10: S10;'#13#10 +
  '  end;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCaseStatementSize));
    Fnd := TFindingHelper.FirstOf(F, fkCaseStatementSize);
    Assert.IsNotNull(Fnd, 'expected fkCaseStatementSize finding');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'case X of'), Fnd.LineNumber);
  finally F.Free; end;
end;

// --- K2: record-Variantenteil -----------------------------------------

procedure TTestCaseStatementSize.RecordVariantPart_NoFinding;
// `case Integer of 0: (A0: Byte);` ist eine Typdeklaration, kein
// Statement - da gibt es nichts in Methoden aufzuteilen.
// OHNE Gate rot: gemeldet wuerde 1 Fund in Zeile 6 mit 11 Zweigen.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TRec = record'#13#10 +
  '    Tag: Integer;'#13#10 +
  '    case Integer of'#13#10 +
  '       0: (A0: Byte);'#13#10 +
  '       1: (A1: Byte);'#13#10 +
  '       2: (A2: Byte);'#13#10 +
  '       3: (A3: Byte);'#13#10 +
  '       4: (A4: Byte);'#13#10 +
  '       5: (A5: Byte);'#13#10 +
  '       6: (A6: Byte);'#13#10 +
  '       7: (A7: Byte);'#13#10 +
  '       8: (A8: Byte);'#13#10 +
  '       9: (A9: Byte);'#13#10 +
  '      10: (A10: Byte);'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCaseStatementSize));
  finally F.Free; end;
end;

procedure TTestCaseStatementSize.ParenExprInBranch_StillReported;
// Ueberreichweiten-Waechter zu K2: geklammerte AUSDRUECKE in den Zweigen
// sind voellig normal. Verworfen werden darf nur, wenn direkt hinter dem
// ERSTEN gezaehlten ':' eine '(' steht. Hier steht dort ein Bezeichner.
// OHNE Gate gruen - der Test faellt erst um, wenn K2 zu breit greift.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; var X, A, B: Integer;'#13#10 +
  'begin'#13#10 +
  '  case X of'#13#10 +
  '     1: V1 := (A + B);'#13#10 +
  '     2: V2 := (A - B);'#13#10 +
  '     3: V3;'#13#10 +
  '     4: V4;'#13#10 +
  '     5: V5;'#13#10 +
  '     6: V6;'#13#10 +
  '     7: V7;'#13#10 +
  '     8: V8;'#13#10 +
  '     9: V9;'#13#10 +
  '    10: V10;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCaseStatementSize));
  finally F.Free; end;
end;

// --- K3/K4/K5: fallen ohne eigenes Gate mit der Tiefe weg -------------

procedure TTestCaseStatementSize.InlineVarInBranch_NotCounted;
// Inline-var-Deklarationen stehen im begin-Block eines Zweigs, also auf
// Tiefe 2. 4 echte Zweige + 7 var-Doppelpunkte ergaben frueher 11.
// OHNE Gate rot: gemeldet wuerde 1 Fund in Zeile 4 mit 11 Zweigen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; var X: Integer;'#13#10 +
  'begin'#13#10 +
  '  case X of'#13#10 +
  '    1: begin'#13#10 +
  '         var W1: Integer;'#13#10 +
  '         var W2: Integer;'#13#10 +
  '         var W3: Integer;'#13#10 +
  '         var W4: Integer;'#13#10 +
  '         var W5: Integer;'#13#10 +
  '         var W6: Integer;'#13#10 +
  '         var W7: Integer;'#13#10 +
  '         W1 := 0;'#13#10 +
  '       end;'#13#10 +
  '    2: W20;'#13#10 +
  '    3: W30;'#13#10 +
  '    4: W40;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCaseStatementSize));
  finally F.Free; end;
end;

procedure TTestCaseStatementSize.OnHandlerInBranch_NotCounted;
// `on E: Exception do` steht in einem try/except-Block, also auf
// Tiefe 2. 4 echte Zweige + 6 on-Doppelpunkte ergaben frueher 10.
// OHNE Gate rot: gemeldet wuerde 1 Fund in Zeile 4 mit 10 Zweigen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; var X: Integer;'#13#10 +
  'begin'#13#10 +
  '  case X of'#13#10 +
  '    1: try'#13#10 +
  '         D1;'#13#10 +
  '       except'#13#10 +
  '         on E1: Exception do H1;'#13#10 +
  '         on E2: Exception do H2;'#13#10 +
  '         on E3: Exception do H3;'#13#10 +
  '         on E4: Exception do H4;'#13#10 +
  '         on E5: Exception do H5;'#13#10 +
  '         on E6: Exception do H6;'#13#10 +
  '       end;'#13#10 +
  '    2: D2;'#13#10 +
  '    3: D3;'#13#10 +
  '    4: D4;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCaseStatementSize));
  finally F.Free; end;
end;

procedure TTestCaseStatementSize.GotoLabelInBranch_NotCounted;
// Ein goto-Label im begin-Block eines Zweigs steht auf Tiefe 2.
// 9 echte Zweige + 1 Label-Doppelpunkt ergaben frueher genau 10.
// OHNE Gate rot: gemeldet wuerde 1 Fund in Zeile 6 mit 10 Zweigen.
// (Ein Label DIREKT im case-Rumpf, ohne begin, steht auf Tiefe 1 und
//  wird weiter mitgezaehlt - dokumentierte Rest-Ungenauigkeit.)
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'label lbl1;'#13#10 +
  'var X: Integer;'#13#10 +
  'begin'#13#10 +
  '  case X of'#13#10 +
  '    1: begin'#13#10 +
  'lbl1:    G1;'#13#10 +
  '       end;'#13#10 +
  '    2: G2;'#13#10 +
  '    3: G3;'#13#10 +
  '    4: G4;'#13#10 +
  '    5: G5;'#13#10 +
  '    6: G6;'#13#10 +
  '    7: G7;'#13#10 +
  '    8: G8;'#13#10 +
  '    9: G9;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCaseStatementSize));
  finally F.Free; end;
end;

// --- K6: Phantom-case aus einer nie uebersetzten Region ---------------

procedure TTestCaseStatementSize.PhantomCaseInDisabledRegion_RealCaseReported;
// Nachbau von jcl/.../JclStrings.pas:698: in einer {$IFNDEF}-Region
// steht Prosa mit dem Wort `case`. Der Strip entfernt die Direktiven,
// die Prosa bleibt - und ihr `case` griff sich das `of` des ECHTEN case
// weit darunter und verschluckte es per FindMatchingEnd gleich mit.
// OHNE Gate rot: der Fund landete auf der PROSA-Zeile, das echte case
// blieb stumm. Der Assert prueft deshalb die Zeile, nicht nur die Zahl.
//
// Der Abstand Prosa-`case` -> echtes `of` muss ueber MAX_SELECTOR_LINES
// (20) liegen, sonst prueft das Fixture das Gate gar nicht mehr. Das
// Original in jcl/.../JclStrings.pas:698 hat 90 Zeilen Abstand - die 4
// Fuellzeilen von frueher waren die unrealistische Variante.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; var X, Z: Integer;'#13#10 +
  'begin'#13#10 +
  '  {$IFNDEF NEVER_DEFINED}'#13#10 +
  '  Implement case map initialization here'#13#10 +
  '  {$ENDIF ~NEVER_DEFINED}'#13#10 +
  '  Z :=  0;'#13#10 +
  '  Z :=  1;'#13#10 +
  '  Z :=  2;'#13#10 +
  '  Z :=  3;'#13#10 +
  '  Z :=  4;'#13#10 +
  '  Z :=  5;'#13#10 +
  '  Z :=  6;'#13#10 +
  '  Z :=  7;'#13#10 +
  '  Z :=  8;'#13#10 +
  '  Z :=  9;'#13#10 +
  '  Z := 10;'#13#10 +
  '  Z := 11;'#13#10 +
  '  Z := 12;'#13#10 +
  '  Z := 13;'#13#10 +
  '  Z := 14;'#13#10 +
  '  Z := 15;'#13#10 +
  '  Z := 16;'#13#10 +
  '  Z := 17;'#13#10 +
  '  Z := 18;'#13#10 +
  '  Z := 19;'#13#10 +
  '  Z := 20;'#13#10 +
  '  Z := 21;'#13#10 +
  '  case X of'#13#10 +
  '     1: Y1;'#13#10 +
  '     2: Y2;'#13#10 +
  '     3: Y3;'#13#10 +
  '     4: Y4;'#13#10 +
  '     5: Y5;'#13#10 +
  '     6: Y6;'#13#10 +
  '     7: Y7;'#13#10 +
  '     8: Y8;'#13#10 +
  '     9: Y9;'#13#10 +
  '    10: Y10;'#13#10 +
  '  end;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCaseStatementSize));
    Fnd := TFindingHelper.FirstOf(F, fkCaseStatementSize);
    Assert.IsNotNull(Fnd, 'expected fkCaseStatementSize finding');
    // Erwartung aus dem SRC abgeleitet statt hartkodiert.
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'case X of'), Fnd.LineNumber);
  finally F.Free; end;
end;

procedure TTestCaseStatementSize.TwoLineSelector_StillReported;
// Ueberreichweiten-Waechter zu K6: ein umgebrochener Selektor ist
// erlaubt. Die Schwelle liegt bei 20 Zeilen (siehe MAX_SELECTOR_LINES) -
// dieser Fund muss bleiben.
// OHNE Gate gruen - er faellt erst um, wenn die Schwelle zu eng wird.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; var X: Integer;'#13#10 +
  'begin'#13#10 +
  '  case'#13#10 +
  '    X of'#13#10 +
  '     1: Z1;  2: Z2;  3: Z3;'#13#10 +
  '     4: Z4;  5: Z5;  6: Z6;'#13#10 +
  '     7: Z7;  8: Z8;  9: Z9;'#13#10 +
  '    10: Z10;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCaseStatementSize));
  finally F.Free; end;
end;

// --- ABSTIEG: jedes case nach seiner EIGENEN Groesse ------------------

procedure TTestCaseStatementSize.NestedCaseOverThreshold_ReportedSeparately;
// Der Kern dieser Runde. Der aeussere case hat 3 eigene Zweige, das
// INNERE 11. Vor dem Abstieg war das ein blinder Fleck: der aeussere
// fiel mit 3 durchs Gate, und `pCase := pEnd + 3` sprang hinter sein
// `end` - das innere case wurde nie besucht. 98 Drops des Tiefe-Gates
// verbargen so 161 echte case.
// OHNE Abstieg rot: 0 Funde. Der Assert prueft die ZEILE, sonst koennte
// der Fund auch am aeusseren case haengen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; var X, Y: Integer;'#13#10 +
  'begin'#13#10 +
  '  case X of'#13#10 +
  '    1: N1;'#13#10 +
  '    2: N2;'#13#10 +
  '    3: begin'#13#10 +
  '         case Y of'#13#10 +
  '            1: M1;  2: M2;  3: M3;  4: M4;  5: M5;'#13#10 +
  '            6: M6;  7: M7;  8: M8;  9: M9; 10: M10;'#13#10 +
  '           11: M11;'#13#10 +
  '         end;'#13#10 +
  '       end;'#13#10 +
  '  end;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCaseStatementSize));
    Fnd := TFindingHelper.FirstOf(F, fkCaseStatementSize);
    Assert.IsNotNull(Fnd, 'expected fkCaseStatementSize finding');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'case Y of'), Fnd.LineNumber);
  finally F.Free; end;
end;

procedure TTestCaseStatementSize.OuterAndInnerBothOverThreshold_BothReported;
// Der Test, der die beiden Abstiegs-Varianten unterscheidet. Aussen 10
// eigene Zweige, innen 11 - BEIDE sind fuer sich zu gross, beide werden
// gemeldet.
// Mit "absteigen nur wenn der aeussere stumm blieb" waere das 1 Fund:
// das innere case verschwaende, weil das aeussere gemeldet wurde. Genau
// diese Kopplung an eine FREMDE Eigenschaft ist der Grund fuer "immer
// absteigen" - im Korpus blieben so 277 echte case stumm, das groesste
// mit 349 Zweigen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; var X, Y: Integer;'#13#10 +
  'begin'#13#10 +
  '  case X of'#13#10 +
  '     1: O1;  2: O2;  3: O3;  4: O4;  5: O5;'#13#10 +
  '     6: O6;  7: O7;  8: O8;  9: O9;'#13#10 +
  '    10: begin'#13#10 +
  '          case Y of'#13#10 +
  '             1: I1;  2: I2;  3: I3;  4: I4;  5: I5;'#13#10 +
  '             6: I6;  7: I7;  8: I8;  9: I9; 10: I10;'#13#10 +
  '            11: I11;'#13#10 +
  '          end;'#13#10 +
  '        end;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkCaseStatementSize));
  finally F.Free; end;
end;

procedure TTestCaseStatementSize.ThreeLevelNesting_InnermostReported;
// Waechter fuer den linearen Scan: der Abstieg darf nicht auf einer
// Ebene stehenbleiben. Aussen 2 Zweige, Mitte 2, innen 10 - nur das
// innerste case ist zu gross.
// OHNE Abstieg rot: 0 Funde.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; var X, Y, W: Integer;'#13#10 +
  'begin'#13#10 +
  '  case X of'#13#10 +
  '    1: E1;'#13#10 +
  '    2: begin'#13#10 +
  '         case Y of'#13#10 +
  '           1: F1;'#13#10 +
  '           2: begin'#13#10 +
  '                case W of'#13#10 +
  '                   1: G1;  2: G2;  3: G3;  4: G4;  5: G5;'#13#10 +
  '                   6: G6;  7: G7;  8: G8;  9: G9; 10: G10;'#13#10 +
  '                end;'#13#10 +
  '              end;'#13#10 +
  '         end;'#13#10 +
  '       end;'#13#10 +
  '  end;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCaseStatementSize));
    Fnd := TFindingHelper.FirstOf(F, fkCaseStatementSize);
    Assert.IsNotNull(Fnd, 'expected fkCaseStatementSize finding');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'case W of'), Fnd.LineNumber);
  finally F.Free; end;
end;

// --- Bezeichner-Schutz: was die Block-Tiefe NICHT erhoehen darf -------

procedure TTestCaseStatementSize.QualifiedLabelAcrossLineBreak_DoesNotOpenBlock;
// Der Punkt-Schutz sah frueher nur Code[p-1] und fiel um, sobald der
// Punkt am Zeilenende stand und der Bezeichner in der naechsten Zeile
// folgte - eine voellig normale Umbruchstelle bei langen Enum-Namen.
// `Record` galt dann als record-Blockanfang, die restlichen Labels
// standen auf Tiefe 2 und zaehlten nicht mehr mit.
// OHNE den erweiterten Schutz rot: 6 statt 10 Zweige, also 0 Funde.
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo(K: TSymKind): string;'#13#10 +
  'begin'#13#10 +
  '  case K of'#13#10 +
  '    TSymKind.Constructor: Q1;'#13#10 +
  '    TSymKind.Destructor:  Q2;'#13#10 +
  '    TSymKind.Procedure:   Q3;'#13#10 +
  '    TSymKind.Function:    Q4;'#13#10 +
  '    TSymKind.Enum:        Q5;'#13#10 +
  '    TSymKind.Sett:        Q6;'#13#10 +
  '    TSymKind.'#13#10 +
  '      Record:             Q7;'#13#10 +
  '    TSymKind.Klass:       Q8;'#13#10 +
  '    TSymKind.Alias:       Q9;'#13#10 +
  '    TSymKind.Unknown:     Q10;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCaseStatementSize));
  finally F.Free; end;
end;

procedure TTestCaseStatementSize.AmpersandEscapedKeyword_DoesNotOpenBlock;
// `&begin` ist ein gueltiger Delphi-Bezeichner - das '&' hebt die
// Schluesselwort-Bedeutung auf. Kein erfundenes Muster: der Korpus
// enthaelt 66-mal `&end`, 10-mal `&record`, 3-mal `&begin` und einmal
// `&try`, und der Lexer dieses Projekts hat dafuer einen eigenen Zweig.
// OHNE den &-Schutz rot: `&begin` erhoeht die Tiefe, die Labels 2..10
// stehen auf Tiefe 2, es bleibt 1 Zweig - also 0 Funde.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; var X: Integer;'#13#10 +
  'begin'#13#10 +
  '  case X of'#13#10 +
  '     1: &begin;'#13#10 +
  '     2: B2;  3: B3;  4: B4;  5: B5;'#13#10 +
  '     6: B6;  7: B7;  8: B8;  9: B9; 10: B10;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCaseStatementSize));
  finally F.Free; end;
end;

procedure TTestCaseStatementSize.ThreeDottedLabels_MatchingEndStillFound;
// Der Bezeichner-Schutz wird in FindMatchingEnd DOCH gebraucht - die
// alte Begruendung "am Korpus ein No-Op, deshalb weg" beschrieb nur die
// Korpuslage, nicht die Sprache. Jedes dotted Blockwort-Label erhoeht
// dort die Tiefe; reichen die folgenden `end` nicht mehr aus, laeuft
// FindMatchingEnd aus der Datei und liefert 0 - der Fund geht KOMPLETT
// verloren, nicht nur mit falscher Zahl.
// Wie viele Labels dafuer noetig sind, haengt an der Zahl der folgenden
// `end`: in dieser Unit (case-end, function-end, unit-end) sind es drei.
// OHNE den Schutz in FindMatchingEnd rot: 0 Funde.
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo(K: TSymKind): string;'#13#10 +
  'begin'#13#10 +
  '  case K of'#13#10 +
  '    TKindOne.Record:  U1;'#13#10 +
  '    TKindTwo.Record:  U2;'#13#10 +
  '    TKindTre.Record:  U3;'#13#10 +
  '    TKindOne.Alpha:   U4;'#13#10 +
  '    TKindOne.Beta:    U5;'#13#10 +
  '    TKindOne.Gamma:   U6;'#13#10 +
  '    TKindOne.Delta:   U7;'#13#10 +
  '    TKindOne.Epsilon: U8;'#13#10 +
  '    TKindOne.Zeta:    U9;'#13#10 +
  '    TKindOne.Eta:     U10;'#13#10 +
  '  end;'#13#10 +
  'end;'#13#10 +
  ''#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCaseStatementSize));
  finally F.Free; end;
end;

// --- Restklasse: nackte inline-var direkt im Zweig --------------------

procedure TTestCaseStatementSize.NakedInlineVarInBranch_NotCounted;
// Eine inline-var OHNE begin-Block steht auf Tiefe 1 und wurde deshalb
// vom Tiefe-Gate nicht erfasst - dieselbe Restklasse wie das nackte
// goto-Label. 8 echte Zweige + 2 Deklarations-Doppelpunkte ergaben 10
// und damit einen Fehlalarm.
// OHNE das var-Gate rot: gemeldet wuerde 1 Fund mit 10 Zweigen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; var X: Integer;'#13#10 +
  'begin'#13#10 +
  '  case X of'#13#10 +
  '     1: var K1: Integer := 0;'#13#10 +
  '     2: var K2: Integer := 0;'#13#10 +
  '     3: K3;'#13#10 +
  '     4: K4;'#13#10 +
  '     5: K5;'#13#10 +
  '     6: K6;'#13#10 +
  '     7: K7;'#13#10 +
  '     8: K8;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCaseStatementSize));
  finally F.Free; end;
end;

// --- K6: Spielraum nach der Neukalibrierung ---------------------------

procedure TTestCaseStatementSize.EightLineSelector_StillReported;
// Nachbau von jvcl/help/tools/GenDtx/DelphiParser.pas:2706 - dem
// laengsten ECHTEN Selektor im Korpus. Ein Array-Literal als Argument
// zieht das `of` acht Zeilen vom `case` weg. Die alte K6-Grenze von 5
// Zeilen haette dieses case verworfen; unauffaellig blieb das nur, weil
// das Original heute 8 Zweige hat und damit ohnehin unter der Schwelle
// liegt - bei einem strengeren MaxCaseBranches waere es ein stiller
// Verlust gewesen. Die Grenze liegt jetzt bei 20.
// MIT der alten Grenze 5 rot: 0 Funde.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  case TokenSymbolIn(['#13#10 +
  '    ''implementation'','#13#10 +
  '    ''procedure'','#13#10 +
  '    ''function'','#13#10 +
  '    ''resourcestring'','#13#10 +
  '    ''const'','#13#10 +
  '    ''type'','#13#10 +
  '    ''threadvar'']) of'#13#10 +
  '     1: L1;  2: L2;  3: L3;  4: L4;  5: L5;'#13#10 +
  '     6: L6;  7: L7;  8: L8;  9: L9; 10: L10;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCaseStatementSize));
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCaseStatementSize);

end.
