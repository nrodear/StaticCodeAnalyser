unit uTestFreeWithoutNil;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFreeWithoutNil = class
  public
    [Test] procedure FreeWithoutNil_Reported;
    [Test] procedure FreeAndNil_NotReported;
    [Test] procedure FreeAtMethodEnd_Reported;
    [Test] procedure FreeFollowedByNilAssign_NotReported;
    // Voll-Review 2026-09-12 (Blocker): nil-Out auf DERSELBEN Zeile.
    [Test] procedure FreeAndNilOutOnOneLine_NotReported;
    [Test] procedure FreeInDestructor_NotReported;
    // Real-World FP-Audit 2026-07-10: class destructor + OnDestroy-Handler
    [Test] procedure FreeInClassDestructor_NotReported;
    [Test] procedure FreeInFormDestroy_NotReported;
    [Test] procedure MethodResultFree_NotReported;
    [Test] procedure ParamFree_NotReported;
    [Test] procedure IndexedElementFree_NotReported;
    [Test] procedure TypecastFree_NotReported;
    [Test] procedure Finding_KindAndSeverity;
    // --- Real-World FP-Audit Runde 4 (2026-07-11) Regression ---
    [Test] procedure ReassignedAfterFree_NotReported;
    [Test] procedure ReassignAfterUseAfterFree_Reported;
    // --- Welle 1 5%-FP-Konzept 2026-07-18 (non-lvalue method-result receiver) ---
    [Test] procedure MethodResultFreeOnField_NotReported;
    [Test] procedure SelfFieldFree_StillReported;    // TP-Gegenprobe (Self-Ausnahme)
    [Test] procedure PlainFieldFree_StillReported;    // TP-Regression (1 Punkt)
    // Posten 203: die fehlenden Klammern zu den Bestands-Nullen,
    // drei gemessene Grenzen und der bisher unberuehrte Destroy-Pfad
    [Test] procedure FreeAndNil_Kontrolle;
    [Test] procedure FreeFollowedByNilAssign_Kontrolle;
    [Test] procedure FreeAtMethodEnd_Kontrolle;
    [Test] procedure FreeAndNilOutOnOneLine_Kontrolle;
    [Test] procedure SelfQualifiedNilOut_NotReported;
    [Test] procedure SelfQualifiedNilOut_Kontrolle;
    [Test] procedure FreeAndNilWithSpaces_NotReported;
    [Test] procedure FreeAndNilWithSpaces_Kontrolle;
    [Test] procedure FreeAndNilOfOtherField_StillReported;
    [Test] procedure ReadBetweenFreeAndNilOut_KnownLimit;
    [Test] procedure ReadBetweenFreeAndNilOut_Kontrolle;
    [Test] procedure NilOutBeforeFreeOnOneLine_KnownLimit;
    [Test] procedure NilOutBeforeFreeOnPreviousLine_Kontrolle;
    [Test] procedure TrailingAssignAfterLastCall_Reported;
    [Test] procedure TrailingAssignAfterLastCall_Kontrolle;
    [Test] procedure FreeOfFieldViaDestroy_StillReported;
    [Test] procedure DestroyFollowedByNilOut_NotReported;
    [Test] procedure ReassignWithForeignReadBetween_NotReported;
    [Test] procedure ReassignWithRealReadBetween_Reported;
  end;

  // Ohne die Ausnahme "Free ist der letzte Aufruf der Methode"
  // (2026-10-22): jedes Feld-Free am Methodenende ist ein Fund. Eigene
  // Fixture - TTestFreeWithoutNil traegt schon 37 Faelle.
  [TestFixture]
  TTestFreeWithoutNilLetzterAufruf = class
  public
    [Test] procedure Ctor_ExceptFreeVorRaise_BeideGemeldet;
    [Test] procedure Ctor_FreeAlsLetzteAnweisung_Gemeldet;
    [Test] procedure Methode_FreeVorRaise_Gemeldet;
    [Test] procedure TearDown_BeideFelder_Gemeldet;
    [Test] procedure TearDown_LocalAmEnde_NichtGemeldet;
    // Korpus-Stichprobe 2026-10-22: die vier FP-Klassen der Erweiterung
    [Test] procedure FreieRoutine_GlobalAmEnde_NichtGemeldet;
    [Test] procedure FreieRoutine_GlobalVorRaise_Gemeldet;
    [Test] procedure ConstParam_NichtGemeldet;
    [Test] procedure VarUndOutParam_Gemeldet;
    [Test] procedure InlineConst_NichtGemeldet;
    [Test] procedure BeforeDestruction_NichtGemeldet;
    [Test] procedure DoFreeUndFinalizeClass_NichtGemeldet;
    [Test] procedure FreieRoutineFinalize_NichtGemeldet;
    [Test] procedure MethodeFinalize_Gemeldet;
  end;

  // U12 (2026-10-27): zwei Restklassen der Stichprobe vom 22.10. -
  // Nil-Test-Schleife (W) und Locals anonymer Methoden (A). Eigene
  // Fixture; die beiden anderen tragen 37 bzw. 14 Faelle. (A) traegt seit
  // der Parser-Charge P2 der Parser, nicht mehr ein Detektor-Gate.
  [TestFixture]
  TTestFreeWithoutNilU12 = class
  public
    [Test] procedure WhileNotNilSelfUnlink_NotReported;
    [Test] procedure WhileAssignedBlockBody_NotReported;
    [Test] procedure WhileCountCondition_StillReported;   // Gegenprobe
    [Test] procedure WhileNilTestOfOtherField_StillReported;   // Gegenprobe
    [Test] procedure AnonMethodVarLocal_NotReported;
    [Test] procedure AnonMethodConstParam_NotReported;
    [Test] procedure AnonMethodVarParam_BodyIsRhsText_NotReported;   // seit P2
    [Test] procedure FieldFreedAfterAnonMethodEnds_StillReported;   // Gegenprobe
    [Test] procedure PlainFieldFree_FileHarness_Reported;
  end;

implementation

// noinspection-file GodClass, LargeClass, DuplicateBlock
// Mit Posten 203 fuehrt die Fixture 37 Faelle. Die Paare MUESSEN sich
// aehneln - jede Klammer unterscheidet sich von ihrer Null in genau
// EINER Zeile, sonst belegt sie nichts. DuplicateBlock stand aus
// demselben Grund schon vorher mit fuenf Funden in dieser Datei.

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

{ --- Posten 203: die drei blinden Nullen und drei Grenzen -------- }
//
// Der Posten sagt, drei Bestandstests seien durch den
// Lokale-Variablen-Skip blind. Das war zutreffend und ist mit der
// ersten Runde dieser Charge behoben - die Fixtures tragen jetzt
// Felder. Was fehlte, sind die KLAMMERN: eine Null ohne Nachbarn,
// der 1 liefert, belegt nichts.
//
// Die Blindheitsprobe zum Nachlesen: die alte Fixture MIT nil-Out
// und dieselbe OHNE liefern beide 0 - zwei gegensaetzliche
// Quelltexte, dieselbe Zahl. Genau daran erkennt man einen Test,
// der seinen Pfad nie erreicht.
//
// Alle Zahlen an der Exe gemessen, Harness FindingsOf wie im
// gesamten Bestand dieser Datei.

procedure TTestFreeWithoutNil.FreeAndNil_Kontrolle;
// Klammer zu FreeAndNil_NotReported: dieselbe Fixture ohne
// den FreeAndNil-Aufruf. Gemessen: 1.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Reset;'#13#10 +
  'begin'#13#10 +
  '  FList.Free;'#13#10 +
  '  DoLog;'#13#10 +
  '  WriteLn(''after'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkFreeWithoutNil),
      'ohne FreeAndNil bleibt der Fund stehen');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.FreeFollowedByNilAssign_Kontrolle;
// Klammer zu FreeFollowedByNilAssign_NotReported: dieselbe
// Fixture ohne die nil-Zuweisung. Gemessen: 1.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Reset;'#13#10 +
  'begin'#13#10 +
  '  FList.Free;'#13#10 +
  '  WriteLn(''after'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkFreeWithoutNil),
      'ohne nil-Out bleibt der Fund stehen');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.FreeAtMethodEnd_Kontrolle;
// Klammer zu FreeAtMethodEnd_Reported: dieselbe Fixture mit einer
// Anweisung HINTER dem Free. Bis 2026-10-22 unterschied die Ausnahme
// "letzter Aufruf" die beiden (0 gegen 1); seither melden beide.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Shutdown;'#13#10 +
  'begin'#13#10 +
  '  DoLog;'#13#10 +
  '  FList.Free;'#13#10 +
  '  WriteLn(''after'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkFreeWithoutNil),
      'steht das Free nicht am Ende, wird gemeldet');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.FreeAndNilOutOnOneLine_Kontrolle;
// Klammer zum Einzeiler-Test: dieselbe Zeile ohne das
// nil-Out. Gemessen: 1. Sie belegt zugleich, dass der
// Blocker-Fix von 2026-09-12 (Zeilenvergleich) wirkt und
// nicht einfach alles auf einer Zeile schweigt.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Reset;'#13#10 +
  'begin'#13#10 +
  '  FTimer.Free; RestartUI;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkFreeWithoutNil),
      'ohne nil-Out meldet auch der Einzeiler');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.SelfQualifiedNilOut_NotReported;
// Self-qualifiziertes nil-Out zaehlt als nil-Out.
// Gemessen: 0.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FList: TStringList;'#13#10 +
  '    FCount: Integer;'#13#10 +
  '  public'#13#10 +
  '    procedure Reset;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Reset;'#13#10 +
  'begin'#13#10 +
  '  FList.Free;'#13#10 +
  '  Self.FList := nil;'#13#10 +
  '  WriteLn(''after'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkFreeWithoutNil),
      'Self.FList := nil ist ein nil-Out wie jedes andere');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.SelfQualifiedNilOut_Kontrolle;
// DIE KLAMMER dazu, und die wichtigste dieser Runde:
// dieselbe Fixture minus AUSSCHLIESSLICH der Zeile
// "Self.FList := nil;". Gemessen: 1.
//
// Ein Bestandstest mit anderem Aufbau taugt hier nicht als
// Klammer - nur die Ein-Zeilen-Differenz schliesst aus, dass
// die Null von etwas anderem kommt.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FList: TStringList;'#13#10 +
  '    FCount: Integer;'#13#10 +
  '  public'#13#10 +
  '    procedure Reset;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Reset;'#13#10 +
  'begin'#13#10 +
  '  FList.Free;'#13#10 +
  '  WriteLn(''after'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkFreeWithoutNil),
      'ohne das Self-nil-Out meldet dieselbe Fixture');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.FreeAndNilWithSpaces_NotReported;
// FreeAndNil mit Leerzeichen in den Klammern. Gemessen: 0.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FList: TStringList;'#13#10 +
  '    FCount: Integer;'#13#10 +
  '  public'#13#10 +
  '    procedure Reset;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Reset;'#13#10 +
  'begin'#13#10 +
  '  FList.Free;'#13#10 +
  '  DoLog;'#13#10 +
  '  FreeAndNil( FList );'#13#10 +
  '  WriteLn(''after'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkFreeWithoutNil),
      'Leerzeichen im Aufruf aendern nichts');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.FreeAndNilWithSpaces_Kontrolle;
// Klammer dazu: dieselbe Fixture ohne den Aufruf.
// Gemessen: 1.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FList: TStringList;'#13#10 +
  '    FCount: Integer;'#13#10 +
  '  public'#13#10 +
  '    procedure Reset;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Reset;'#13#10 +
  'begin'#13#10 +
  '  FList.Free;'#13#10 +
  '  DoLog;'#13#10 +
  '  WriteLn(''after'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkFreeWithoutNil),
      'ohne den Aufruf bleibt der Fund');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.FreeAndNilOfOtherField_StillReported;
// Schaerfer als die Klammer darueber: derselbe Aufruf mit
// denselben Leerzeichen, aber auf einem ANDEREN Feld.
// Gemessen: 1 - der Vergleich prueft den Bezeichner, nicht
// nur das Praefix des Aufrufs.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FList: TStringList;'#13#10 +
  '    FCount: Integer;'#13#10 +
  '  public'#13#10 +
  '    procedure Reset;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Reset;'#13#10 +
  'begin'#13#10 +
  '  FList.Free;'#13#10 +
  '  DoLog;'#13#10 +
  '  FreeAndNil( FOther );'#13#10 +
  '  WriteLn(''after'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkFreeWithoutNil),
      'FreeAndNil eines anderen Feldes rettet dieses hier nicht');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.ReadBetweenFreeAndNilOut_KnownLimit;
// GRENZE: zwischen Free und nil-Out steht ein LESENDER
// Zugriff auf dasselbe Feld - genau das Muster, vor dem die
// Regel warnt. Trotzdem 0, weil die nil-Out-Pruefung vor der
// Reassign-Pruefung laeuft und das nil-Out im Fenster
// findet. Gemessen: 0.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FList: TStringList;'#13#10 +
  '    FCount: Integer;'#13#10 +
  '  public'#13#10 +
  '    procedure Reset;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Reset;'#13#10 +
  'begin'#13#10 +
  '  FList.Free;'#13#10 +
  '  DoLog(FList);'#13#10 +
  '  FList := nil;'#13#10 +
  '  WriteLn(''after'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkFreeWithoutNil),
      'BEKANNTE GRENZE: ein Lesezugriff vor dem nil-Out wird nicht gesehen');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.ReadBetweenFreeAndNilOut_Kontrolle;
// Klammer dazu: dieselbe Fixture ohne das nil-Out.
// Gemessen: 1.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FList: TStringList;'#13#10 +
  '    FCount: Integer;'#13#10 +
  '  public'#13#10 +
  '    procedure Reset;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Reset;'#13#10 +
  'begin'#13#10 +
  '  FList.Free;'#13#10 +
  '  DoLog(FList);'#13#10 +
  '  WriteLn(''after'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkFreeWithoutNil),
      'ohne nil-Out meldet dieselbe Fixture');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.NilOutBeforeFreeOnOneLine_KnownLimit;
// GRENZE: das nil-Out steht VOR dem Free, auf derselben
// Zeile. Der Vergleich prueft auf gleiche oder groessere
// Zeile, nicht auf echte Nachfolge. Gemessen: 0.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FList: TStringList;'#13#10 +
  '    FCount: Integer;'#13#10 +
  '  public'#13#10 +
  '    procedure Reset;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Reset;'#13#10 +
  'begin'#13#10 +
  '  DoLog;'#13#10 +
  '  FList := nil; FList.Free; RestartUI;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkFreeWithoutNil),
      'BEKANNTE GRENZE: nil-Out vor dem Free auf derselben Zeile zaehlt mit');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.NilOutBeforeFreeOnPreviousLine_Kontrolle;
// Klammer dazu: dasselbe nil-Out eine Zeile FRUEHER.
// Gemessen: 1 - damit haengt die Null oben an der
// Zeilengleichheit und an nichts anderem.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FList: TStringList;'#13#10 +
  '    FCount: Integer;'#13#10 +
  '  public'#13#10 +
  '    procedure Reset;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Reset;'#13#10 +
  'begin'#13#10 +
  '  DoLog;'#13#10 +
  '  FList := nil;'#13#10 +
  '  FList.Free; RestartUI;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkFreeWithoutNil),
      'eine Zeile frueher zaehlt das nil-Out nicht mehr');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.TrailingAssignAfterLastCall_Reported;
// Bis 2026-10-22 eine GRENZE (0): hinter dem Free stand nur noch eine
// Zuweisung, fuer die Ausnahme "letzter Aufruf" war das Free damit das
// Ende. Die Ausnahme ist weg - das Feld bleibt haengend, Fund.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FList: TStringList;'#13#10 +
  '    FCount: Integer;'#13#10 +
  '  public'#13#10 +
  '    procedure Reset;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Reset;'#13#10 +
  'begin'#13#10 +
  '  DoLog;'#13#10 +
  '  FList.Free;'#13#10 +
  '  FCount := 0;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkFreeWithoutNil),
      'das Feld bleibt nach dem Free haengend - auch ohne Aufruf dahinter');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.TrailingAssignAfterLastCall_Kontrolle;
// Klammer dazu: statt der Zuweisung ein Aufruf.
// Gemessen: 1.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FList: TStringList;'#13#10 +
  '    FCount: Integer;'#13#10 +
  '  public'#13#10 +
  '    procedure Reset;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Reset;'#13#10 +
  'begin'#13#10 +
  '  DoLog;'#13#10 +
  '  FList.Free;'#13#10 +
  '  FCount := 0;'#13#10 +
  '  WriteLn(''after'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkFreeWithoutNil),
      'ein Aufruf dahinter macht das Free zur Mitte');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.FreeOfFieldViaDestroy_StillReported;
// Der Destroy-Pfad des Empfaengers - kein Bestandstest
// beruehrt ihn. Gemessen: 1.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FFoo: TObject;'#13#10 +
  '  public'#13#10 +
  '    procedure Reset;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Reset;'#13#10 +
  'begin'#13#10 +
  '  FFoo.Destroy;'#13#10 +
  '  WriteLn(''after'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkFreeWithoutNil),
      'auch Destroy auf einem Feld verlangt ein nil-Out');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.DestroyFollowedByNilOut_NotReported;
// Klammer dazu: dasselbe Destroy mit nil-Out dahinter.
// Gemessen: 0.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FFoo: TObject;'#13#10 +
  '  public'#13#10 +
  '    procedure Reset;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Reset;'#13#10 +
  'begin'#13#10 +
  '  FFoo.Destroy;'#13#10 +
  '  FFoo := nil;'#13#10 +
  '  WriteLn(''after'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkFreeWithoutNil),
      'mit nil-Out ist auch Destroy in Ordnung');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.ReassignWithForeignReadBetween_NotReported;
// Die Wortgrenze der Zwischen-Lesepruefung: zwischen Free
// und Neuzuweisung steht ein Bezeichner, der den Feldnamen
// als TEIL enthaelt. Er darf nicht als Lesezugriff zaehlen.
// Gemessen: 0.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    L: TObject;'#13#10 +
  '    FList: TStringList;'#13#10 +
  '  public'#13#10 +
  '    procedure Reset;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Reset;'#13#10 +
  'begin'#13#10 +
  '  L.Free;'#13#10 +
  '  DoLog(FList);'#13#10 +
  '  L := TObject.Create;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkFreeWithoutNil),
      'ein laengerer Bezeichner ist kein Lesezugriff auf das Feld');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.ReassignWithRealReadBetween_Reported;
// Klammer dazu: derselbe Aufbau mit einem ECHTEN
// Lesezugriff. Gemessen: 1.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    L: TObject;'#13#10 +
  '    FList: TStringList;'#13#10 +
  '  public'#13#10 +
  '    procedure Reset;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Reset;'#13#10 +
  'begin'#13#10 +
  '  L.Free;'#13#10 +
  '  DoLog(L);'#13#10 +
  '  L := TObject.Create;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkFreeWithoutNil),
      'ein echter Lesezugriff dazwischen bleibt ein Fund');
  finally F.Free; end;
end;


procedure TTestFreeWithoutNil.FreeWithoutNil_Reported;
// HINWEIS: Detector flaggt seit Round-5-Fix nur FELDER, nicht Locals
// (Locals fallen beim Method-End aus dem Scope, kein Dangling-Risiko).
// Daher SRC mit FFoo-Feld statt 'var L: TStringList;'.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FList: TStringList;'#13#10 +
  '  public'#13#10 +
  '    procedure DoStuff;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.DoStuff;'#13#10 +
  'begin'#13#10 +
  '  FList.Free;'#13#10 +
  '  WriteLn(''after free'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFreeWithoutNil),
      'genau 1 FreeWithoutNil-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'FList.Free'),
      TFindingHelper.FirstOf(F, fkFreeWithoutNil).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.FreeAndNil_NotReported;
// FELD-Receiver, nicht lokale Variable (Voll-Review 2026-09-12,
// Major): lokale Variablen nimmt schon der Local-Var-Skip - der Test
// prueft sonst NICHT den FreeAndNil-Pfad, den er zu pruefen behauptet.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Reset;'#13#10 +
  'begin'#13#10 +
  '  FList.Free;'#13#10 +
  '  DoLog;'#13#10 +
  '  FreeAndNil(FList);'#13#10 +
  '  WriteLn(''after'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil));
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.FreeAtMethodEnd_Reported;
// Free eines FELDES als letzte Anweisung: das Objekt lebt weiter, das
// Feld zeigt auf freigegebenen Speicher - Fund. Bis 2026-10-22 hiess der
// Test FreeAtMethodEnd_NotReported (Ausnahme "letzter Aufruf"); Locals
// und Parameter bleiben ueber den Local-Var-Skip ohne Fund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Shutdown;'#13#10 +
  'begin'#13#10 +
  '  DoLog;'#13#10 +
  '  FList.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFreeWithoutNil));
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.FreeFollowedByNilAssign_NotReported;
// FELD-Receiver (Voll-Review 2026-09-12, Major): erst damit laeuft
// HasNilOutAfter - lokale Variablen nimmt der Local-Var-Skip vorher.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Reset;'#13#10 +
  'begin'#13#10 +
  '  FList.Free;'#13#10 +
  '  FList := nil;'#13#10 +
  '  WriteLn(''after'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil));
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.IndexedElementFree_NotReported;
// FP-Fix (Real-World 2026-06-23): Collection-Item-Free im Loop
// (`Objects[i].Free`) - kein simpler Var-Receiver, "var := nil" trifft nicht
// zu. ~100+ Real-World-FPs (TStringList.Objects[], TList Items[], Controls[]).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to FList.Count - 1 do'#13#10 +
  '    FList.Objects[i].Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil),
      'Indexed-Element-Free (Objects[i].Free) ist kein Free-Without-Nil');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.TypecastFree_NotReported;
// FP-Fix (Real-World 2026-06-23): Typecast-Free (`TFoo(List[i]).Free`) -
// nil-Out eines Casts ist syntaktisch unmoeglich.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to FItems.Count - 1 do'#13#10 +
  '    TObject(FItems[i]).Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil),
      'Typecast-Free (TObject(X).Free) ist kein Free-Without-Nil');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.Finding_KindAndSeverity;
// Field-Pattern - analog zu FreeWithoutNil_Reported (Round-5-Fix).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FList: TStringList;'#13#10 +
  '  public'#13#10 +
  '    procedure DoStuff;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.DoStuff;'#13#10 +
  'begin'#13#10 +
  '  FList.Free;'#13#10 +
  '  WriteLn(''after'');'#13#10 +
  'end;'#13#10 +
  'end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkFreeWithoutNil then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkFreeWithoutNil finding expected');
    Assert.AreEqual(lsWarning, Hit.Severity);
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.FreeAndNilOutOnOneLine_NotReported;
// 'FTimer.Free; FTimer := nil; RestartUI;' auf EINER Zeile: das
// nil-Assign traegt dieselbe Zeilennummer wie der Free-Call - der
// alte '<='-Vergleich sprang darueber und meldete genau das Muster,
// das die Regel empfiehlt.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Reset;'#13#10 +
  'begin'#13#10 +
  '  FTimer.Free; FTimer := nil; RestartUI;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkFreeWithoutNil),
    'das Einzeiler-nil-Out ist genau das empfohlene Muster');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.FreeInDestructor_NotReported;
// FP-Fix (Real-World 2026-06-21): im Destruktor ist Nil-Out nach Free
// sinnlos - das Objekt selbst wird zerstoert. Ein Destruktor mit mehreren
// Field.Free erzeugte sonst je ein Finding.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FA, FB: TObject;'#13#10 +
  '  public'#13#10 +
  '    destructor Destroy; override;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  FA.Free;'#13#10 +
  '  FB.Free;'#13#10 +
  '  inherited;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil),
      'Field.Free im Destruktor braucht kein Nil-Out - kein Finding');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.MethodResultFree_NotReported;
// FP-Fix (Self-Scan 2026-06-21): `Stack.Pop.Free` gibt das ERGEBNIS eines
// Methodenaufrufs frei - es gibt keine Variable 'Pop'. Die Wurzel 'Stack'
// ist lokal -> method-scoped, kein Nil-Out-Smell.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'var Stack: TStack;'#13#10 +
  'begin'#13#10 +
  '  Stack := TStack.Create;'#13#10 +
  '  Stack.Pop.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil),
      'X.Pop.Free (Methoden-Ergebnis, lokale Wurzel) ist kein Free-Without-Nil');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.ParamFree_NotReported;
// FP-Fix (Self-Scan 2026-06-21): ein Parameter (Methode uebernimmt Ownership)
// ist method-scoped - Nil-Out beim Method-Ende ist sinnlos.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Consume(Items: TObjectList);'#13#10 +
  'begin'#13#10 +
  '  Items.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil),
      'Free eines Parameters ist kein Free-Without-Nil-Smell');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.FreeInClassDestructor_NotReported;
// Real-World FP-Audit 2026-07-10: 'class destructor' (TypeRef 'class destructor')
// wurde vom exakten SameText('destructor') verfehlt. Die class-var stirbt am
// Klassen-Teardown -> Nil-Out wirkungslos.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '    class var FList: TStringList;'#13#10 +
  '    class destructor Destroy;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'class destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  FList.Free;'#13#10 +
  '  WriteLn(''done'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil),
    'class destructor -> Nil-Out wirkungslos, kein Fund');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.FreeInFormDestroy_NotReported;
// Real-World FP-Audit 2026-07-10: OnDestroy-Handler 'FormDestroy' (ein normales
// procedure) zerstoert die Form -> Feld-Free braucht kein Nil-Out.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TForm1 = class(TForm)'#13#10 +
  '    FList: TStringList;'#13#10 +
  '    procedure FormDestroy(Sender: TObject);'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TForm1.FormDestroy(Sender: TObject);'#13#10 +
  'begin'#13#10 +
  '  FList.Free;'#13#10 +
  '  WriteLn(''done'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil),
    'FormDestroy (OnDestroy-Handler) -> Feld-Free ohne Nil-Out ok');
  finally F.Free; end;
end;


// --- Real-World FP-Audit Runde 4 (2026-07-11) Regression ---

procedure TTestFreeWithoutNil.ReassignedAfterFree_NotReported;
// FP-Fix (Real-World-FP-Audit 2026-07-11, dominante Klasse reassigned-after-free):
// FPopUpBitmap.Free; FPopUpBitmap := TBitmap.Create - das Feld wird vor jedem
// Read neu belegt -> kein Dangling-Pointer (CEF4Delphi-FPopUpBitmap-Idiom, 13 FPs).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FBmp: TBitmap;'#13#10 +
  '  public'#13#10 +
  '    procedure Resize;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Resize;'#13#10 +
  'begin'#13#10 +
  '  FBmp.Free;'#13#10 +
  '  FBmp := TBitmap.Create;'#13#10 +
  '  FBmp.SetSize(10, 10);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil),
      'Free direkt gefolgt von Reassign (FBmp := TBitmap.Create) ist kein Dangling-Pointer');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.ReassignAfterUseAfterFree_Reported;
// TP-Guard zur Reassign-FP-Fix: liegt zwischen Free und Reassignment ein READ
// des Feldes, ist es ein echtes Use-After-Free -> Befund MUSS bleiben.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FBmp: TBitmap;'#13#10 +
  '  public'#13#10 +
  '    procedure Resize;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Resize;'#13#10 +
  'begin'#13#10 +
  '  FBmp.Free;'#13#10 +
  '  FBmp.SetSize(10, 10);'#13#10 +
  '  FBmp := TBitmap.Create;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkFreeWithoutNil) >= 1,
      'Read zwischen Free und Reassign = Use-After-Free -> Befund bleibt');
  finally F.Free; end;
end;
procedure TTestFreeWithoutNil.MethodResultFreeOnField_NotReported;
// FP-Fix (Real-World 2026-07-18): FMsgQueue.Pop.Free / FIfStack.Pop.Free -
// mehrsegmentiger, klammerloser Receiver mit FELD-Wurzel. 'FMsgQueue.Pop' ist
// das Ergebnis eines Aufrufs, kein nil-outbares lvalue -> kein Befund.
// (Feld-Wurzel, damit NICHT schon der Local/Param-Skip greift.)
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FMsgQueue: TStack;'#13#10 +
  '  public'#13#10 +
  '    procedure Drain;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Drain;'#13#10 +
  'begin'#13#10 +
  '  FMsgQueue.Pop.Free;'#13#10 +
  '  WriteLn(''after'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil),
      'X.Pop.Free (Methoden-Ergebnis, Feld-Wurzel) ist kein Free-Without-Nil');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.SelfFieldFree_StillReported;
// TP-Gegenprobe: 'Self.FList.Free' hat zwar 2 Punkte, ist aber ueber Self ein
// echtes nil-outbares Feld (Self.FList := nil) -> Befund MUSS bleiben.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FList: TStringList;'#13#10 +
  '  public'#13#10 +
  '    procedure DoStuff;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.DoStuff;'#13#10 +
  'begin'#13#10 +
  '  Self.FList.Free;'#13#10 +
  '  WriteLn(''after'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkFreeWithoutNil) >= 1,
      'Self.FField.Free ist ein echtes nil-outbares Feld -> Befund bleibt');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.PlainFieldFree_StillReported;
// TP-Regression: einsegmentiges Feld 'FList.Free' (1 Punkt) darf der Guard NIE
// treffen.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FList: TStringList;'#13#10 +
  '  public'#13#10 +
  '    procedure DoStuff;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.DoStuff;'#13#10 +
  'begin'#13#10 +
  '  FList.Free;'#13#10 +
  '  WriteLn(''after'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFreeWithoutNil),
      'Einsegmentiges Feld FList.Free bleibt Befund');
  finally F.Free; end;
end;

{ ---- Die Ausnahme "letzter Aufruf" (2026-10-22) -------------------- }
//
// Gefunden in xml-as-html-final (TXMLProcessingController.Create): der
// except-Zweig gibt zwei Felder frei und wirft weiter. Delphi ruft bei
// einer Ausnahme im Konstruktor den Destruktor, der beide Felder noch
// einmal freigibt - SCA139 meldete nur das erste, das zweite war "der
// letzte Aufruf der Methode". Dasselbe in mvc-database
// (TSQLiteTest.TearDown: 'FQuery.Free; FConnection.Free;' - nur FQuery).
// Die ersten vier Faelle sind mit der Ausnahme rot (1 statt 2, 0 statt 1,
// 0 statt 1, 1 statt 2).

procedure TTestFreeWithoutNilLetzterAufruf.Ctor_ExceptFreeVorRaise_BeideGemeldet;
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  inherited Create;'#13#10 +
  '  try'#13#10 +
  '    FA := TA.Create;'#13#10 +
  '    FB := TB.Create;'#13#10 +
  '  except'#13#10 +
  '    FA.Free;'#13#10 +
  '    FB.Free;'#13#10 +
  '    raise;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkFreeWithoutNil),
    'beide Felder - der Destruktor gibt sie nach dem raise noch einmal frei');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNilLetzterAufruf.Ctor_FreeAlsLetzteAnweisung_Gemeldet;
// Ohne raise: das Feld ist nach dem Konstruktor frei, der Destruktor gibt
// es spaeter noch einmal frei.
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  inherited Create;'#13#10 +
  '  FTmp.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFreeWithoutNil),
    'im Konstruktor schuetzt "letzter Aufruf" nicht');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNilLetzterAufruf.Methode_FreeVorRaise_Gemeldet;
// Gewoehnliche Methode: nach dem raise lebt das Objekt weiter, das Feld
// zeigt auf freigegebenen Speicher.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Load;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    DoLoad;'#13#10 +
  '  except'#13#10 +
  '    FList.Free;'#13#10 +
  '    raise;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFreeWithoutNil),
    'Free vor raise ist kein Methodenende');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNilLetzterAufruf.TearDown_BeideFelder_Gemeldet;
// Der Fall aus mvc-database: zwei Felder am Ende von TearDown - beide
// gleich behandelt.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TSQLiteTest.TearDown;'#13#10 +
  'begin'#13#10 +
  '  FQuery.Free;'#13#10 +
  '  FConnection.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkFreeWithoutNil),
    'beide Felder bleiben haengend');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNilLetzterAufruf.TearDown_LocalAmEnde_NichtGemeldet;
// WAECHTER: die Ausnahme war nur fuer Locals richtig - die faengt der
// Local-Var-Skip weiterhin ab, auch am Methodenende.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Shutdown;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  DoLog(L);'#13#10 +
  '  L.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil),
    'eine lokale Variable faellt mit der Methode aus dem Scope');
  finally F.Free; end;
end;

{ ---- Korpus-Stichprobe 2026-10-22: FP-Klassen der Erweiterung ---------- }
//
// 30 zufaellige Adds aus realworld+Lazarus: 15 echt, 13 FP. Je Klasse ein
// Fall; ohne die zugehoerige Aenderung jeweils rot (1 bzw. 2 statt 0).
// Die beiden Waechter (GlobalVorRaise, VarUndOutParam) sind es nicht.

procedure TTestFreeWithoutNilLetzterAufruf.FreieRoutine_GlobalAmEnde_NichtGemeldet;
// Finalisierungs-Helfer (Alcinoe ALRttiFinalization, doublecmd Finish,
// xEdit-Skripte 'Finalize'): ein globales Objekt am Ende einer freien
// Routine - die Ausnahme "letzter Aufruf" gilt dort weiter.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Finish;'#13#10 +
  'begin'#13#10 +
  '  GCache.Clear;'#13#10 +
  '  GCodecs.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil),
    'freie Routine, globales Objekt am Ende - kein Feld, kein Fund');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNilLetzterAufruf.FreieRoutine_GlobalVorRaise_Gemeldet;
// WAECHTER: vor einem raise schuetzt "letzter Aufruf" auch in der freien
// Routine nicht - das Programm laeuft weiter, das Global haengt.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure LoadAll;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    DoLoad;'#13#10 +
  '  except'#13#10 +
  '    GCache.Free;'#13#10 +
  '    raise;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFreeWithoutNil),
    'Free vor raise - das Global bleibt haengend');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNilLetzterAufruf.ConstParam_NichtGemeldet;
// delphimvcframework Render(const ACollection ..): der Parser legt
// 'const ACollection' als Namen ab - der Parameter-Skip griff nie. Ein
// const-Parameter ist eine lokale Kopie wie einer ohne Modifier.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Fill(const AList: TList; constref ARef: TList);'#13#10 +
  'begin'#13#10 +
  '  AList.Free;'#13#10 +
  '  ARef.Free;'#13#10 +
  '  DoLog;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil),
    'const/constref-Parameter sind lokale Kopien');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNilLetzterAufruf.VarUndOutParam_Gemeldet;
// WAECHTER: var/out sind die Variable des Aufrufers - sie haengt nach dem
// Free, FreeAndNil hilft dort wirklich.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Fill(var AObj: TObject; out AOut: TObject);'#13#10 +
  'begin'#13#10 +
  '  AObj.Free;'#13#10 +
  '  AOut.Free;'#13#10 +
  '  DoLog;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkFreeWithoutNil),
    'var/out bleiben Befund');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNilLetzterAufruf.InlineConst_NichtGemeldet;
// Inno Setup Setup.ScriptRunner: 'const ProcNos = TPSList.Create;' - eine
// Inline-Konstante faellt mit der Methode aus dem Scope.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Run;'#13#10 +
  'begin'#13#10 +
  '  const ProcNos = TList.Create;'#13#10 +
  '  try'#13#10 +
  '    DoRun(ProcNos);'#13#10 +
  '  finally'#13#10 +
  '    ProcNos.Free;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil),
    'Inline-Konstante ist lokal');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNilLetzterAufruf.BeforeDestruction_NichtGemeldet;
// JVCL JvID3v2Base: BeforeDestruction laeuft direkt vor dem Destruktor.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFrame.BeforeDestruction;'#13#10 +
  'begin'#13#10 +
  '  inherited BeforeDestruction;'#13#10 +
  '  FList.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil),
    'die Instanz stirbt wie im Destruktor');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNilLetzterAufruf.DoFreeUndFinalizeClass_NichtGemeldet;
// Lazarus idedebugger DoFree und ZXing-Port FinalizeClass: beide sind ein
// Abbau der Instanz bzw. der Klasse - wie ein Destruktor. Je ein Aufruf
// dahinter, damit "letzter Aufruf" nicht mitspielt.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TStruct.DoFree;'#13#10 +
  'begin'#13#10 +
  '  FAnchestor.Free;'#13#10 +
  '  inherited DoFree;'#13#10 +
  'end;'#13#10 +
  'class procedure TSupport.FinalizeClass;'#13#10 +
  'begin'#13#10 +
  '  FBuffer.Free;'#13#10 +
  '  DoLog;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil),
    'DoFree/FinalizeClass bauen ab wie ein Destruktor');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNilLetzterAufruf.FreieRoutineFinalize_NichtGemeldet;
// xEdit-Skript 'Finalize' raeumt die Globalen am Skriptende ab - auch mit
// Aufrufen hinter dem Free.
const SRC =
  'unit t; implementation'#13#10 +
  'function Finalize: Integer;'#13#10 +
  'begin'#13#10 +
  '  slDump.SaveToFile(''x.txt'');'#13#10 +
  '  slDump.Free;'#13#10 +
  '  AddMessage(''done'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil),
    'freie Finalize-Routine - Programm- bzw. Skriptende');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNilLetzterAufruf.MethodeFinalize_Gemeldet;
// WAECHTER: eine METHODE Finalize ist ein Lebenszyklus-Schritt (doublecmd
// TFileSourceOperation.Finalize) - das Objekt lebt, das Feld haengt.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TCopyOperation.Finalize;'#13#10 +
  'begin'#13#10 +
  '  FHelper.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFreeWithoutNil),
    'Methode Finalize - das Objekt lebt weiter');
  finally F.Free; end;
end;

{ --- U12: Nil-Test-Schleife und anonyme Methoden ------------------- }

procedure TTestFreeWithoutNilU12.WhileNotNilSelfUnlink_NotReported;
// U12-W: sich selbst aushaengende Liste (Lazarus definetemplates/
// lfmtrees). Die Schleife endet nur, weil der Destruktor FFirst
// weiterschaltet - danach ist das Feld nil. Bestehende Exe: 1 Fund.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'uses System.Classes, System.SysUtils;'#13#10 +
  'type'#13#10 +
  '  TNode = class'#13#10 +
  '    FFirst, FOther: TNode;'#13#10 +
  '    FList: TList;'#13#10 +
  '    FData: TStringList;'#13#10 +
  '    procedure Run;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TNode.Run;'#13#10 +
  'begin'#13#10 +
  '  while FFirst <> nil do FFirst.Free;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil));
  finally F.Free; end;
end;

procedure TTestFreeWithoutNilU12.WhileAssignedBlockBody_NotReported;
// U12-W: dieselbe Klasse mit Assigned() und begin..end-Rumpf - das
// Free haengt dann unter einem nkBlock im Schleifenknoten.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'uses System.Classes, System.SysUtils;'#13#10 +
  'type'#13#10 +
  '  TNode = class'#13#10 +
  '    FFirst, FOther: TNode;'#13#10 +
  '    FList: TList;'#13#10 +
  '    FData: TStringList;'#13#10 +
  '    procedure Run;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TNode.Run;'#13#10 +
  'begin'#13#10 +
  '  while Assigned(FFirst) do'#13#10 +
  '  begin'#13#10 +
  '    FFirst.Free;'#13#10 +
  '  end;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil));
  finally F.Free; end;
end;

procedure TTestFreeWithoutNilU12.WhileCountCondition_StillReported;
// GEGENPROBE U12-W: keine Nil-Bedingung. Nach dem ersten Free liest
// FList.Count freigegebenen Speicher - Befund bleibt.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'uses System.Classes, System.SysUtils;'#13#10 +
  'type'#13#10 +
  '  TNode = class'#13#10 +
  '    FFirst, FOther: TNode;'#13#10 +
  '    FList: TList;'#13#10 +
  '    FData: TStringList;'#13#10 +
  '    procedure Run;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TNode.Run;'#13#10 +
  'begin'#13#10 +
  '  while FList.Count > 0 do FList.Free;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFreeWithoutNil));
  finally F.Free; end;
end;

procedure TTestFreeWithoutNilU12.WhileNilTestOfOtherField_StillReported;
// GEGENPROBE U12-W: die Bedingung testet ein ANDERES Feld auf nil.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'uses System.Classes, System.SysUtils;'#13#10 +
  'type'#13#10 +
  '  TNode = class'#13#10 +
  '    FFirst, FOther: TNode;'#13#10 +
  '    FList: TList;'#13#10 +
  '    FData: TStringList;'#13#10 +
  '    procedure Run;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TNode.Run;'#13#10 +
  'begin'#13#10 +
  '  while FOther <> nil do FList.Free;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFreeWithoutNil));
  finally F.Free; end;
end;

procedure TTestFreeWithoutNilU12.AnonMethodVarLocal_NotReported;
// U12-A: L ist Local der anonymen Methode (delphimvcframework-Muster).
// Bis zur Parser-Charge P2 kippte der Parser deren Rumpf in Run, L.Free
// sah wie ein Feld-Free aus; ein Quelltext-Gate entlastete. Seit P2
// bleibt der Rumpf RHS-Text der Zuweisung, das Gate ist entfernt.
// Exe 0fe5d84c (Parser alt, ohne Gate): 1 Fund.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'uses System.Classes, System.SysUtils;'#13#10 +
  'type'#13#10 +
  '  TNode = class'#13#10 +
  '    FFirst, FOther: TNode;'#13#10 +
  '    FList: TList;'#13#10 +
  '    FData: TStringList;'#13#10 +
  '    procedure Run;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TNode.Run;'#13#10 +
  'var'#13#10 +
  '  P: TProc;'#13#10 +
  'begin'#13#10 +
  '  P := procedure'#13#10 +
  '    var'#13#10 +
  '      L: TStringList;'#13#10 +
  '    begin'#13#10 +
  '      L := TStringList.Create;'#13#10 +
  '      try'#13#10 +
  '        L.Add(''x'');'#13#10 +
  '      finally'#13#10 +
  '        L.Free;'#13#10 +
  '      end;'#13#10 +
  '    end;'#13#10 +
  '  P();'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil));
  finally F.Free; end;
end;

procedure TTestFreeWithoutNilU12.AnonMethodConstParam_NotReported;
// U12-A: const-Parameter der anonymen Methode - lokale Kopie wie
// bei einer gewoehnlichen Methode (IsLocalCopyParam). Seit der Parser-
// Charge P2 ist der ganze Rumpf RHS-Text (kein Gate mehr noetig).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'uses System.Classes, System.SysUtils;'#13#10 +
  'type'#13#10 +
  '  TNode = class'#13#10 +
  '    FFirst, FOther: TNode;'#13#10 +
  '    FList: TList;'#13#10 +
  '    FData: TStringList;'#13#10 +
  '    procedure Run;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TNode.Run;'#13#10 +
  'var'#13#10 +
  '  P: TProc<TList>;'#13#10 +
  'begin'#13#10 +
  '  P := procedure(const AList: TList)'#13#10 +
  '    var'#13#10 +
  '      I: Integer;'#13#10 +
  '    begin'#13#10 +
  '      I := AList.Count;'#13#10 +
  '      AList.Free;'#13#10 +
  '    end;'#13#10 +
  '  P(nil);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil));
  finally F.Free; end;
end;

procedure TTestFreeWithoutNilU12.AnonMethodVarParam_BodyIsRhsText_NotReported;
// Bis P2 die Gegenprobe des U12-A-Gates (var-Parameter = Variable des
// Aufrufers, Befund blieb). Seit der Parser-Charge P2 ist der Rumpf einer
// anonymen Methode mit var-Sektion RHS-Text - wie der jeder anonymen
// Methode ohne Sektion schon immer; AList.Free ist fuer SCA139 keine
// Anweisung mehr (bekannte Grenze: anonyme Methoden haben keinen eigenen
// Knoten, Paket 9015). Exe 8c3eac8f: 1 Fund (ROT ohne P2).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'uses System.Classes, System.SysUtils;'#13#10 +
  'type'#13#10 +
  '  TNode = class'#13#10 +
  '    FFirst, FOther: TNode;'#13#10 +
  '    FList: TList;'#13#10 +
  '    FData: TStringList;'#13#10 +
  '    procedure Run;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TNode.Run;'#13#10 +
  'var'#13#10 +
  '  P: TProc;'#13#10 +
  'begin'#13#10 +
  '  P := procedure(var AList: TList)'#13#10 +
  '    var'#13#10 +
  '      I: Integer;'#13#10 +
  '    begin'#13#10 +
  '      I := AList.Count;'#13#10 +
  '      AList.Free;'#13#10 +
  '    end;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil));
  finally F.Free; end;
end;

procedure TTestFreeWithoutNilU12.FieldFreedAfterAnonMethodEnds_StillReported;
// GEGENPROBE U12-A: gleichnamiges Local in der anonymen Methode, das
// Free steht aber NACH ihrem Ende - gemeint ist das Feld FData.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'uses System.Classes, System.SysUtils;'#13#10 +
  'type'#13#10 +
  '  TNode = class'#13#10 +
  '    FFirst, FOther: TNode;'#13#10 +
  '    FList: TList;'#13#10 +
  '    FData: TStringList;'#13#10 +
  '    procedure Run;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TNode.Run;'#13#10 +
  'var'#13#10 +
  '  P: TProc;'#13#10 +
  'begin'#13#10 +
  '  P := procedure'#13#10 +
  '    var'#13#10 +
  '      FData: TStringList;'#13#10 +
  '    begin'#13#10 +
  '      FData := nil;'#13#10 +
  '    end;'#13#10 +
  '  FData.Free;'#13#10 +
  '  P();'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFreeWithoutNil));
  finally F.Free; end;
end;

procedure TTestFreeWithoutNilU12.PlainFieldFree_FileHarness_Reported;
// Positiv-Waechter: SCA139 laeuft seit U12 auch in FindingsOfFile.
// Ohne die Registrierung waeren die Gegenproben oben stumm-gruen.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'uses System.Classes, System.SysUtils;'#13#10 +
  'type'#13#10 +
  '  TNode = class'#13#10 +
  '    FFirst, FOther: TNode;'#13#10 +
  '    FList: TList;'#13#10 +
  '    FData: TStringList;'#13#10 +
  '    procedure Run;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TNode.Run;'#13#10 +
  'begin'#13#10 +
  '  FData.Free;'#13#10 +
  '  FList.Clear;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFreeWithoutNil));
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFreeWithoutNil);
  TDUnitX.RegisterTestFixture(TTestFreeWithoutNilLetzterAufruf);
  TDUnitX.RegisterTestFixture(TTestFreeWithoutNilU12);

end.
