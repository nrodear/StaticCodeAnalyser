unit uTestLeakInConstructor;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestLeakInConstructor = class
  public
    [Test] procedure FieldCreateThenRaise_Reported;
    [Test] procedure FieldCreateWithoutRaise_NoFinding;
    [Test] procedure RaiseWithoutFieldCreate_NoFinding;
    [Test] procedure ProtectedByTryExcept_NoFinding;
    [Test] procedure ClassConstructor_NoFinding;
    [Test] procedure ValidateThenAllocate_NoFinding;
    [Test] procedure Finding_KindAndSeverity;

    // ---- FP-Gates 2026-07-31 (30%-Real-World-Audit) -----------------------
    // [G1] Destruktor-Deckung
    [Test] procedure DestructorFreesField_NoFinding;
    [Test] procedure DestructorFreesFieldViaFreeAndNil_NoFinding;
    [Test] procedure DestructorMissesOneField_StillReported;
    [Test] procedure NoDestructorInUnit_StillReported;
    [Test] procedure DestructorOfOtherClass_StillReported;
    // [G1a] Destruktor dereferenziert ein evtl. nil-Feld vor der Freigabe
    [Test] procedure DestructorDerefsFieldUnguarded_StillReported;
    [Test] procedure DestructorDerefsFieldGuarded_NoFinding;
    // [G1b] inherited Create erst nach dem raise (TThread-Muster)
    [Test] procedure ThreadCtorInheritedCreateAfterRaise_StillReported;
    [Test] procedure PlainInheritedAtCtorEnd_NoFinding;
    // [G2] Werttyp-Factory
    [Test] procedure RtlRecordFactory_NoFinding;
    [Test] procedure UnitRecordFactory_NoFinding;
    // [G3] Static-Factory mit Create-Suffix
    [Test] procedure SuffixFactoryNeverFreed_NoFinding;
    [Test] procedure SuffixFactoryFreedInUnit_StillReported;

    // ---- Review-MEDIUM 2026-08-09: String-Literale blanken ----------------
  end;

  // Literal-Stripping-Welle A (2026-08-09) - eigene Fixture, damit die Basisklasse unter der GodClass-Schwelle bleibt.
  [TestFixture]
  TTestLeakInConstructorLiterals = class
  public
    [Test] procedure LiteralDotCreateInAssign_NoFinding;
    [Test] procedure LiteralFreeTextInDestructor_StillReported;
  end;

implementation

// noinspection-file ClassPerFile
// Zwei thematisch getrennte Fixtures in einer Unit.

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestLeakInConstructor.FieldCreateThenRaise_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  FList := TStringList.Create;'#13#10 +
  '  if Bad then'#13#10 +
  '    raise EInvalidOp.Create(''bad'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkLeakInConstructor) >= 1);
  finally F.Free; end;
end;

procedure TTestLeakInConstructor.FieldCreateWithoutRaise_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  FList := TStringList.Create;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLeakInConstructor));
  finally F.Free; end;
end;

procedure TTestLeakInConstructor.RaiseWithoutFieldCreate_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  if Bad then'#13#10 +
  '    raise EInvalidOp.Create(''bad'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLeakInConstructor));
  finally F.Free; end;
end;

procedure TTestLeakInConstructor.ProtectedByTryExcept_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  FList := TStringList.Create;'#13#10 +
  '  try'#13#10 +
  '    if Bad then raise EInvalidOp.Create(''bad'');'#13#10 +
  '  except'#13#10 +
  '    FreeAndNil(FList);'#13#10 +
  '    raise;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLeakInConstructor));
  finally F.Free; end;
end;

procedure TTestLeakInConstructor.ClassConstructor_NoFinding;
// class constructor laeuft einmal pro Klasse, kein Instance-Init -
// LeakInConstructor-Pattern nicht anwendbar.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '    class constructor Create;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'class constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  FStaticThing := TStringList.Create;'#13#10 +
  '  if Bad then raise EInvalidOp.Create(''bad'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLeakInConstructor));
  finally F.Free; end;
end;

procedure TTestLeakInConstructor.ValidateThenAllocate_NoFinding;
// Regression LoggerPro.MemoryAppender/WebhookAppender:
//   begin
//     if N < 1 then raise Exception.Create('bad');
//     FList := TList.Create;   <- raise feuert vor jeder Allocation
//   end;
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create(N: Integer);'#13#10 +
  'begin'#13#10 +
  '  if N < 1 then raise Exception.Create(''bad'');'#13#10 +
  '  FList := TList.Create;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLeakInConstructor),
    'raise VOR der ersten Allocation = nichts zum leaken');
  finally F.Free; end;
end;

procedure TTestLeakInConstructor.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  FList := TStringList.Create;'#13#10 +
  '  raise EFoo.Create(''bad'');'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkLeakInConstructor then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkLeakInConstructor finding expected');
    Assert.AreEqual(fkLeakInConstructor, Hit.Kind);
    Assert.AreEqual(lsError,             Hit.Severity);
  finally F.Free; end;
end;

// ---------------------------------------------------------------------------
// FP-Gates 2026-07-31 (30%-Real-World-Audit sca-rw-after119, 86% FP im Sample)
// Alle Sourcen laufen ueber FindingsOf - SCA136 ist im AST-Harness
// registriert (uTestFindingHelper Z.172), nicht im File-Harness.
// ---------------------------------------------------------------------------

const
  // Gemeinsamer Kopf fuer die Gate-Tests. Klassen-Deklaration ist bewusst
  // dabei: OwnerTypeLow matcht Ctor- und Dtor-Impl ueber den qualifizierten
  // Namen, die Deklaration selbst spielt keine Rolle - sie haelt die Sourcen
  // aber realistisch.
  HEAD_TFOO =
    'unit t;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TFoo = class'#13#10 +
    '  public'#13#10 +
    '    constructor Create;'#13#10 +
    '    destructor Destroy; override;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10;

procedure TTestLeakInConstructor.DestructorFreesField_NoFinding;
// [G1] Regression JvBouncingLabel.pas:130 - der Destruktor gibt das im Ctor
// allokierte Feld frei; die RTL ruft Destroy bei einer Ctor-Exception
// automatisch -> nichts leakt.
const SRC = HEAD_TFOO +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  FList := TStringList.Create;'#13#10 +
  '  if Bad then'#13#10 +
  '    raise EInvalidOp.Create(''bad'');'#13#10 +
  'end;'#13#10 +
  'destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  FList.Free;'#13#10 +
  '  inherited;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLeakInConstructor),
    'Destruktor deckt das allokierte Feld ab - Auto-Destroy raeumt auf');
  finally F.Free; end;
end;

procedure TTestLeakInConstructor.DestructorFreesFieldViaFreeAndNil_NoFinding;
// [G1] Regression Alcinoe/mORMot: Freigabe per (AL)FreeAndNil(Feld) statt
// Feld.Free.
const SRC = HEAD_TFOO +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  FValueRange := TValueRange.Create(Self);'#13#10 +
  '  if Bad then'#13#10 +
  '    raise EInvalidOp.Create(''bad'');'#13#10 +
  'end;'#13#10 +
  'destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  ALFreeAndNil(FValueRange);'#13#10 +
  '  inherited;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLeakInConstructor));
  finally F.Free; end;
end;

procedure TTestLeakInConstructor.DestructorMissesOneField_StillReported;
// Gegenprobe zu [G1]: deckt der Destruktor nur EINES der beiden allokierten
// Felder ab, bleibt der Fund.
const SRC = HEAD_TFOO +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  FA := TStringList.Create;'#13#10 +
  '  FB := TStringList.Create;'#13#10 +
  '  if Bad then'#13#10 +
  '    raise EInvalidOp.Create(''bad'');'#13#10 +
  'end;'#13#10 +
  'destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  FA.Free;'#13#10 +
  '  inherited;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkLeakInConstructor) >= 1,
    'FB wird nirgends freigegeben - der Fund muss bleiben');
  finally F.Free; end;
end;

procedure TTestLeakInConstructor.NoDestructorInUnit_StillReported;
// Gegenprobe zu [G1]: ohne Destruktor in der Unit gibt es keinen Beweis
// fuer Aufraeumen - der Fund bleibt.
const SRC = HEAD_TFOO +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  FList := TStringList.Create;'#13#10 +
  '  if Bad then'#13#10 +
  '    raise EInvalidOp.Create(''bad'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkLeakInConstructor) >= 1);
  finally F.Free; end;
end;

procedure TTestLeakInConstructor.DestructorOfOtherClass_StillReported;
// Gegenprobe zu [G1]: der Destruktor einer FREMDEN Klasse zaehlt nicht -
// OwnerTypeLow muss Ctor und Dtor ueber denselben Typnamen verbinden.
const SRC = HEAD_TFOO +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  FList := TStringList.Create;'#13#10 +
  '  if Bad then'#13#10 +
  '    raise EInvalidOp.Create(''bad'');'#13#10 +
  'end;'#13#10 +
  'destructor TBar.Destroy;'#13#10 +
  'begin'#13#10 +
  '  FList.Free;'#13#10 +
  '  inherited;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkLeakInConstructor) >= 1);
  finally F.Free; end;
end;

procedure TTestLeakInConstructor.DestructorDerefsFieldUnguarded_StillReported;
// [G1a] TP Alcinoe.FMX.VideoPlayer.pas:2069 - der Destruktor schreibt
// 'FListener.Owner := nil' OHNE Nil-Guard. Nach einem Ctor-raise ist
// FListener noch nil -> AV vor der Freigabe -> echter Leak.
const SRC = HEAD_TFOO +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  FListener := TListener.Create(Self);'#13#10 +
  '  if Bad then'#13#10 +
  '    raise EInvalidOp.Create(''bad'');'#13#10 +
  'end;'#13#10 +
  'destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  FListener.Owner := nil;'#13#10 +
  '  FListener.Free;'#13#10 +
  '  inherited;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkLeakInConstructor) >= 1,
    'nicht nil-toleranter Destruktor - der Fund muss bleiben');
  finally F.Free; end;
end;

procedure TTestLeakInConstructor.DestructorDerefsFieldGuarded_NoFinding;
// Gegenprobe zu [G1a]: mit Nil-Guard ist der Destruktor teil-init-tauglich.
const SRC = HEAD_TFOO +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  FListener := TListener.Create(Self);'#13#10 +
  '  if Bad then'#13#10 +
  '    raise EInvalidOp.Create(''bad'');'#13#10 +
  'end;'#13#10 +
  'destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  if Assigned(FListener) then'#13#10 +
  '    FListener.Owner := nil;'#13#10 +
  '  FListener.Free;'#13#10 +
  '  inherited;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLeakInConstructor));
  finally F.Free; end;
end;

procedure TTestLeakInConstructor.ThreadCtorInheritedCreateAfterRaise_StillReported;
// [G1b] TP Alcinoe.FMX.WebRTC.pas:1244 - 'inherited Create(False)' steht erst
// NACH dem raise und die Klasse ist thread-artig (FreeOnTerminate /
// Terminate+WaitFor im Destruktor). Der Auto-Destroy laeuft auf kaputtem
// Zustand -> Fund bleibt trotz Destruktor-Deckung.
const SRC = HEAD_TFOO +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  FreeOnTerminate := True;'#13#10 +
  '  FSignal := TEvent.Create(nil);'#13#10 +
  '  if Bad then'#13#10 +
  '    raise EInvalidOp.Create(''bad'');'#13#10 +
  '  inherited Create(False);'#13#10 +
  'end;'#13#10 +
  'destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  Terminate;'#13#10 +
  '  WaitFor;'#13#10 +
  '  FSignal.Free;'#13#10 +
  '  inherited;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkLeakInConstructor) >= 1,
    'TThread-Muster - der Fund muss bleiben');
  finally F.Free; end;
end;

procedure TTestLeakInConstructor.PlainInheritedAtCtorEnd_NoFinding;
// Gegenprobe zu [G1b]: Regression Alcinoe.FMX.Styles.pas:26991
// (TALStyleManager). Ein blosses 'inherited;' am Ctor-Ende ohne
// Thread-Evidenz darf den Destruktor-Gate NICHT aufheben.
const SRC = HEAD_TFOO +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  FList := TStringList.Create;'#13#10 +
  '  if Bad then'#13#10 +
  '    raise EInvalidOp.Create(''bad'');'#13#10 +
  '  inherited;'#13#10 +
  'end;'#13#10 +
  'destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  FList.Free;'#13#10 +
  '  inherited;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLeakInConstructor));
  finally F.Free; end;
end;

procedure TTestLeakInConstructor.RtlRecordFactory_NoFinding;
// [G2] Regression Alcinoe.FMX.Dynamic.Controls.pas:675 -
// 'FScale := TPointF.Create(1,1)' ist eine Werttyp-Factory, keine
// Heap-Allokation. Kein Destruktor noetig: es gibt nichts zum Leaken.
const SRC = HEAD_TFOO +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  FScale := TPointF.Create(1, 1);'#13#10 +
  '  if Bad then'#13#10 +
  '    raise EInvalidOp.Create(''bad'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLeakInConstructor),
    'record-Factory allokiert nichts Freigebbares');
  finally F.Free; end;
end;

procedure TTestLeakInConstructor.UnitRecordFactory_NoFinding;
// [G2] Variante: der Werttyp ist in DIESER Unit als record deklariert.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TMyRec = record'#13#10 +
  '    X: Integer;'#13#10 +
  '  end;'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    constructor Create;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  FVal := TMyRec.Create(1);'#13#10 +
  '  if Bad then'#13#10 +
  '    raise EInvalidOp.Create(''bad'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLeakInConstructor));
  finally F.Free; end;
end;

procedure TTestLeakInConstructor.SuffixFactoryNeverFreed_NoFinding;
// [G3] Regression TES5Edit/Core/wbImplementation.pas:3323 -
// 'TwbFileID.CreateLight(..)' ist eine Static-Factory (kein echtes 'Create')
// und das Feld wird unit-weit nirgends freigegeben -> kein besitzendes
// Heap-Feld, nichts kann leaken.
const SRC = HEAD_TFOO +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  FFileId := TFileID.CreateLight(1);'#13#10 +
  '  if Bad then'#13#10 +
  '    raise EInvalidOp.Create(''bad'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLeakInConstructor));
  finally F.Free; end;
end;

procedure TTestLeakInConstructor.SuffixFactoryFreedInUnit_StillReported;
// Gegenprobe zu [G3]: wird das Feld irgendwo in der Unit freigegeben, ist es
// ein besitzendes Heap-Feld - der Suffix-Gate darf NICHT greifen.
const SRC = HEAD_TFOO +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  FStream := TMyStream.CreateFromFile(''x'');'#13#10 +
  '  if Bad then'#13#10 +
  '    raise EInvalidOp.Create(''bad'');'#13#10 +
  'end;'#13#10 +
  'procedure TFoo.Cleanup;'#13#10 +
  'begin'#13#10 +
  '  FStream.Free;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkLeakInConstructor) >= 1);
  finally F.Free; end;
end;

procedure TTestLeakInConstructorLiterals.LiteralDotCreateInAssign_NoFinding;
// Review-MEDIUM 2026-08-09: '.Create' steht nur INNERHALB eines String-
// Literals - das ist keine Feld-Allokation, es darf kein Fund entstehen.
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TWorker.Create;'#13#10 +
  'begin'#13#10 +
  '  FErrText := Format(''%s.Create failed'', [ClassName]);'#13#10 +
  '  if Bad then'#13#10 +
  '    raise EInvalidOp.Create(''nope'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLeakInConstructor),
    '.Create im String-Literal ist keine Allokation');
  finally F.Free; end;
end;

procedure TTestLeakInConstructorLiterals.LiteralFreeTextInDestructor_StillReported;
// Review-MEDIUM 2026-08-09: Gegenprobe im Destruktor - Log(''..free fconn'')
// ist nur ein String-Literal, KEINE Freigabe; [G1] darf nicht greifen,
// der Fund muss bleiben.
const SRC = HEAD_TFOO +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  FConn := TDbConn.Create(Self);'#13#10 +
  '  if Bad then'#13#10 +
  '    raise EInvalidOp.Create(''bad'');'#13#10 +
  'end;'#13#10 +
  'destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  Log(''failed to free fconn'');'#13#10 +
  '  inherited;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkLeakInConstructor) >= 1,
    'Literal-Text im Destruktor ist keine Freigabe - der Fund muss bleiben');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLeakInConstructor);
  TDUnitX.RegisterTestFixture(TTestLeakInConstructorLiterals);

end.
