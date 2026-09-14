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
    [Test] procedure FreeAtMethodEnd_NotReported;
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
    [Test] procedure TrailingAssignAfterLastCall_KnownLimit;
    [Test] procedure TrailingAssignAfterLastCall_Kontrolle;
    [Test] procedure FreeOfFieldViaDestroy_StillReported;
    [Test] procedure DestroyFollowedByNilOut_NotReported;
    [Test] procedure ReassignWithForeignReadBetween_NotReported;
    [Test] procedure ReassignWithRealReadBetween_Reported;
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
// Klammer zu FreeAtMethodEnd_NotReported: dieselbe Fixture
// mit einer Anweisung HINTER dem Free, damit es nicht mehr
// die letzte ist. Gemessen: 1.
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

procedure TTestFreeWithoutNil.TrailingAssignAfterLastCall_KnownLimit;
// GRENZE: hinter dem Free steht nur noch eine Zuweisung an
// ein anderes Feld - fuer die Ende-Erkennung ist das Free
// damit die letzte relevante Anweisung. Gemessen: 0.
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
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkFreeWithoutNil),
      'BEKANNTE GRENZE: eine Zuweisung dahinter macht das Free nicht zur Mitte');
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

procedure TTestFreeWithoutNil.FreeAtMethodEnd_NotReported;
// Free als letzte Anweisung -> kein Folge-Use moeglich -> kein Befund.
// FELD-Receiver (Voll-Review 2026-09-12, Major): mit lokaler Variable
// griff der Local-Var-Skip, IsLastStmtOfMethod lief nie.
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
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil));
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

initialization
  TDUnitX.RegisterTestFixture(TTestFreeWithoutNil);

end.
