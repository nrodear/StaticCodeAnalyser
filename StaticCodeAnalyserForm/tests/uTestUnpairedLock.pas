unit uTestUnpairedLock;

// Tests fuer SCA153 (Acquire ohne try/finally).
//
// WAS DIESE TESTS PRUEFEN UND WAS NICHT (gemessen 2026-09-14, Posten
// 220): der Harness FindingsOfFile ruft den Detektor DIREKT. In der
// Produktion liegt davor ein Token-Vorfilter -
// ['tcriticalsection', 'tmonitor', '.enter', '.acquire'],
// uStaticAnalyzer2.pas:505. Von den Fixtures dieser Datei tragen ELF
// keines dieser Token; sie erreichen den Detektor im echten Lauf also
// nie, darunter vier POSITIV-Tests (LockWithoutTryFinally_Reported,
// EnterCriticalSectionWithoutTry_Reported, Finding_KindAndSeverity,
// MethodNamedLockWithRealAcquire_StillReported).
//
// Das ist keine dritte Detektormenge, sondern eine dritte EBENE: die
// Tests hier sind richtig und pruefen den Detektor, sie beweisen aber
// nichts ueber den Auslieferungspfad. An der Exe belegt, dieselbe
// Routine zweimal: 'FLocker.Lock;' -> 0 Funde, 'FLocker.Acquire;'
// -> 1.
//
// Der fehlende Token '.lock' verdeckt am Korpus 51 echte Funde in 21
// Dateien (Messung: jede Kandidatendatei mit einer Kommentarzeile
// 'tcriticalsection' versehen, sonst unveraendert, und gescannt).
// Das ist ein RECALL-Paket mit eigenem Zweig - siehe die Notiz an der
// Registrierung. Hier wird es ausdruecklich NICHT als bekannte Grenze
// gepinnt: ein gruener Test auf einen gemessenen Defekt zementiert ihn.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestUnpairedLock = class
  public
    [Test] procedure LockWithoutTryFinally_Reported;
    [Test] procedure EnterCriticalSectionWithoutTry_Reported;
    [Test] procedure LockInTryFinally_NotReported;
    [Test] procedure LockWithoutMatchingUnlock_NotReported;
    [Test] procedure Finding_KindAndSeverity;
    [Test] procedure TryEnclosesLock_NoFinding;
    [Test] procedure BareLockNoTry_StillReported;
    // Real-World FP-Audit 2026-07-10: 'declaration-not-call' (15/19 FP)
    [Test] procedure LockMethodDeclaration_NotReported;
    [Test] procedure InterfaceForwardDecl_NotReported;
    [Test] procedure AcquireFunctionDeclaration_NotReported;
    [Test] procedure MethodNamedLockWithRealAcquire_StillReported;
    // FP-Audit Stufe 2 2026-08-16: Fenster endet an der Routinengrenze
    [Test] procedure LockFacadeReleaseInSiblingMethod_NotReported;
    [Test] procedure RaiiCtorDtorPair_NotReported;
    [Test] procedure AcquireReleaseSameRoutineWithSiblingBelow_StillReported;

    // Voll-Review 2026-09-12 (Major 87): Events sind bewusst NICHT
    // abgedeckt - dokumentierender Test, kein Vertrag auf Abdeckung
    [Test] procedure RtlEventWaitFor_NotCovered_ByDesign;
    // Posten 220: die fehlende Klammer zur Event-Grenze und der
    // bis dahin ungeprueffte Fund-Anker
    [Test] procedure RtlEventWaitFor_AcquireInstead_Kontrolle;
    [Test] procedure Finding_LineNumberIsAcquireLine;
    [Test] procedure LineNumberSurvivesBlockComment;
    [Test] procedure LineNumberSurvivesStringLiterals;
    [Test] procedure TwoBareLocks_BothLinesReported;
  end;

implementation

uses
  // System.Classes: TwoBareLocks_BothLinesReported sammelt die
  // Fundzeilen selbst - TFindingHelper hat kein NthOf (Posten 220).
  System.Classes,
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

{ --- Posten 220: die Klammer zur Grenze und der Fund-Anker ------- }
//
// Teil (a) des Postens ist ueberholt: die Behauptung, das
// Event-Muster sei abgedeckt, steht seit dem Voll-Review nicht mehr
// im Kopf, und RtlEventWaitFor_NotCovered_ByDesign pinnt die Null.
// Was fehlte, ist die KLAMMER daneben - ohne sie belegt die Null
// nichts.
//
// Teil (b) ist frisch: kein einziger Test hat je die Fundzeile
// geprueft. Der Anker kommt aus LineForPos ueber den GESTRIPPTEN
// Text (uUnpairedLock.pas:248-249, 326) - Kommentare und Literale
// werden durch Leerzeichen ersetzt, damit die Zeilenzaehlung haelt.
// Genau das pruefen die zwei letzten Tests.
//
// Alle Zahlen und Zeilen an der Exe gemessen.

procedure TTestUnpairedLock.RtlEventWaitFor_AcquireInstead_Kontrolle;
// DIE KLAMMER zu RtlEventWaitFor_NotCovered_ByDesign: dieselbe
// Routine, die zwei Event-Aufrufe durch ein Paar aus Acquire und
// Release ersetzt. Gemessen: 1 auf Zeile 4. Damit gehoert die
// Null dort dem Regex und nicht der Fixture.
//
// Die Klammer gilt auf HARNESS-Ebene: FindingsOfFile ruft den
// Detektor direkt und kennt den Vorfilter nicht. In der
// Produktion traegt diese Fixture das Token ".acquire", die
// gepinnte daneben gar keines - beide waeren dort stumm, aber
// aus verschiedenen Gruenden.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Warte;'#13#10 +
  'begin'#13#10 +
  '  FGuard.Acquire;'#13#10 +
  '  DoStuff;'#13#10 +
  '  FGuard.Release;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkUnpairedLock),
      'ein echtes Acquire ohne try/finally wird gemeldet');
  finally F.Free; end;
end;

procedure TTestUnpairedLock.Finding_LineNumberIsAcquireLine;
// Der Fund-Anker ist die Zeile des Acquire, nicht die des
// Methodenkopfs und nicht die des Release. Gemessen:
// Zeile 4.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure P;'#13#10 +
  'begin'#13#10 +
  '  FCS.Acquire;'#13#10 +
  '  DoStuff;'#13#10 +
  '  FCS.Release;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Hit := TFindingHelper.FirstOf(F, fkUnpairedLock);
    Assert.IsNotNull(Hit, 'kein UnpairedLock-Fund');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'FCS.Acquire'),
      Hit.LineNumber,
      'der Fund muss auf der Acquire-Zeile stehen');
  finally F.Free; end;
end;

procedure TTestUnpairedLock.LineNumberSurvivesBlockComment;
// Der Anker wird ueber den GESTRIPPTEN Text berechnet.
// Wuerde der Strip Zeichen entfernen statt sie durch
// Leerzeichen zu ersetzen, verschoebe ein mehrzeiliger
// Kommentar davor die Zeilennummer. Gemessen: Zeile 7.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure P;'#13#10 +
  'begin'#13#10 +
  '  { ein'#13#10 +
  '    mehrzeiliger'#13#10 +
  '    Kommentar }'#13#10 +
  '  FCS.Acquire;'#13#10 +
  '  DoStuff;'#13#10 +
  '  FCS.Release;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Hit := TFindingHelper.FirstOf(F, fkUnpairedLock);
    Assert.IsNotNull(Hit, 'kein UnpairedLock-Fund');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'FCS.Acquire'),
      Hit.LineNumber,
      'ein mehrzeiliger Kommentar darf den Anker nicht verschieben');
  finally F.Free; end;
end;

procedure TTestUnpairedLock.LineNumberSurvivesStringLiterals;
// Dasselbe fuer ausgeblendete Zeichenkettenliterale.
// Gemessen: Zeile 6.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure P;'#13#10 +
  'begin'#13#10 +
  '  Log(''erste Zeile'');'#13#10 +
  '  Log(''zweite'');'#13#10 +
  '  FCS.Acquire;'#13#10 +
  '  DoStuff;'#13#10 +
  '  FCS.Release;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Hit := TFindingHelper.FirstOf(F, fkUnpairedLock);
    Assert.IsNotNull(Hit, 'kein UnpairedLock-Fund');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'FCS.Acquire'),
      Hit.LineNumber,
      'ausgeblendete Literale duerfen den Anker nicht verschieben');
  finally F.Free; end;
end;

procedure TTestUnpairedLock.TwoBareLocks_BothLinesReported;
// Zwei Routinen, zwei Funde - und beide muessen ihre EIGENE
// Zeile tragen. Gemessen: Zeile 4 und Zeile 10, in
// Dokumentreihenfolge.
//
// TFindingHelper hat kein NthOf; die Liste wird deshalb hier
// selbst gefiltert.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure P;'#13#10 +
  'begin'#13#10 +
  '  FCS.Acquire;'#13#10 +
  '  DoStuff;'#13#10 +
  '  FCS.Release;'#13#10 +
  'end;'#13#10 +
  'procedure Q;'#13#10 +
  'begin'#13#10 +
  '  FOther.Acquire;'#13#10 +
  '  DoMore;'#13#10 +
  '  FOther.Release;'#13#10 +
  'end;';
var
  F     : TObjectList<TLeakFinding>;
  Fnd   : TLeakFinding;
  Zeilen: TStringList;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  Zeilen := TStringList.Create;
  try
    for Fnd in F do
      if Fnd.Kind = fkUnpairedLock then Zeilen.Add(Fnd.LineNumber);
    Assert.AreEqual<Integer>(2, Zeilen.Count,
      'beide Routinen muessen je einen Fund liefern');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'FCS.Acquire'),
      Zeilen[0], 'erster Fund auf der ersten Acquire-Zeile');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'FOther.Acquire'),
      Zeilen[1], 'zweiter Fund auf der zweiten Acquire-Zeile');
  finally
    Zeilen.Free;
    F.Free;
  end;
end;


procedure TTestUnpairedLock.LockWithoutTryFinally_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  FLocker.Lock;'#13#10 +
  '  DoStuff;'#13#10 +
  '  FLocker.UnLock;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkUnpairedLock) >= 1);
  finally F.Free; end;
end;

procedure TTestUnpairedLock.EnterCriticalSectionWithoutTry_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  EnterCriticalSection(FCS);'#13#10 +
  '  DoStuff;'#13#10 +
  '  LeaveCriticalSection(FCS);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkUnpairedLock) >= 1);
  finally F.Free; end;
end;

procedure TTestUnpairedLock.LockInTryFinally_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  FLocker.Lock;'#13#10 +
  '  try'#13#10 +
  '    DoStuff;'#13#10 +
  '  finally'#13#10 +
  '    FLocker.UnLock;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnpairedLock));
  finally F.Free; end;
end;

procedure TTestUnpairedLock.LockWithoutMatchingUnlock_NotReported;
// Wenn KEIN unlock im Lookahead-Fenster ist, skipt der Detector
// (koennte ein anderer Pattern sein, z.B. Lock-Helper).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  FLocker.Lock;'#13#10 +
  '  // viele Zeilen Code ohne unlock...'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnpairedLock));
  finally F.Free; end;
end;

procedure TTestUnpairedLock.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  FLocker.Lock;'#13#10 +
  '  DoStuff;'#13#10 +
  '  FLocker.UnLock;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkUnpairedLock then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkUnpairedLock finding expected');
    Assert.AreEqual(lsWarning, Hit.Severity);
  finally F.Free; end;
end;

// FP-Guard (2026-06-29): das try/finally UMSCHLIESST den Lock - `try` steht VOR
// dem Acquire und ist noch offen (kein finally/except/end dazwischen). Der Lock
// liegt im try-Body -> Exception leakt ihn nicht -> kein bare-Lock.
procedure TTestUnpairedLock.TryEnclosesLock_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure P;'#13#10 +
  'begin'#13#10 +
  '  FCS := TCriticalSection.Create;'#13#10 +
  '  try'#13#10 +
  '    FCS.Acquire;'#13#10 +
  '    DoStuff;'#13#10 +
  '  finally'#13#10 +
  '    FCS.Release;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnpairedLock));
  finally F.Free; end;
end;

// Kein try ueberhaupt: Acquire ... Release ohne Schutz -> Finding bleibt.
procedure TTestUnpairedLock.BareLockNoTry_StillReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure P;'#13#10 +
  'begin'#13#10 +
  '  FCS.Acquire;'#13#10 +
  '  DoStuff;'#13#10 +
  '  FCS.Release;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkUnpairedLock) >= 1);
  finally F.Free; end;
end;

// ============================================================
// Real-World FP-Audit 2026-07-10: 'declaration-not-call'
// 'procedure Lock;' / 'function Acquire(...)' / Interface-Forward-Decls
// matchen den Regex, sind aber Methodennamen, keine Acquire-Aufrufe.
// ============================================================

procedure TTestUnpairedLock.LockMethodDeclaration_NotReported;
// 'procedure Lock;' gefolgt von 'procedure UnLock;' in der Klassen-Decl sah
// wie ein bare-Lock aus (Lookahead fand 'unlock' im UnLock-Header).
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    procedure Lock;'#13#10 +
  '    procedure UnLock;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnpairedLock),
    'procedure Lock; ist eine Deklaration, kein Acquire-Aufruf');
  finally F.Free; end;
end;

procedure TTestUnpairedLock.InterfaceForwardDecl_NotReported;
// Interface-Section-Forward-Decls von EnterCriticalSection/LeaveCriticalSection.
const SRC =
  'unit t; interface'#13#10 +
  'procedure EnterCriticalSection(var cs: TRTLCriticalSection); stdcall;'#13#10 +
  'procedure LeaveCriticalSection(var cs: TRTLCriticalSection); stdcall;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnpairedLock),
    'EnterCriticalSection(...) Forward-Decl ist kein Aufruf');
  finally F.Free; end;
end;

procedure TTestUnpairedLock.AcquireFunctionDeclaration_NotReported;
// 'function Acquire(...): Boolean;' Method-Decl, gefolgt von 'procedure Release;'.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TConn = class'#13#10 +
  '  public'#13#10 +
  '    function Acquire(Op: TObject): Boolean;'#13#10 +
  '    procedure Release;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnpairedLock),
    'function Acquire(...) Deklaration ist kein Aufruf');
  finally F.Free; end;
end;

procedure TTestUnpairedLock.MethodNamedLockWithRealAcquire_StillReported;
// Gegenprobe: der Impl-Header 'procedure TFoo.Lock;' wird uebersprungen, ein
// ECHTER bare-Acquire im Rumpf bleibt aber ein Fund (kein Over-Suppress).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Lock;'#13#10 +
  'begin'#13#10 +
  '  FInner.Lock;'#13#10 +
  '  DoStuff;'#13#10 +
  '  FInner.UnLock;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkUnpairedLock) >= 1,
    'echter bare FInner.Lock im Rumpf bleibt SCA153');
  finally F.Free; end;
end;

// ============================================================
// FP-Audit Stufe 2 (2026-08-16): das Lookahead-Fenster lief ueber die
// Routinengrenze und fand das Release der symmetrischen NACHBARmethode.
// 21 von 23 Sample-FP hatten diese Ursache.
// ============================================================

procedure TTestUnpairedLock.LockFacadeReleaseInSiblingMethod_NotReported;
// Lock/UnLock-Fassade: die gemeldete Routine enthaelt selbst gar kein
// Release - der Lock wird bewusst an den Aufrufer weitergereicht.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Lock;'#13#10 +
  'begin'#13#10 +
  '  FCS.Acquire;'#13#10 +
  'end;'#13#10 +
  'procedure TFoo.UnLock;'#13#10 +
  'begin'#13#10 +
  '  FCS.Release;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnpairedLock),
    'Release der Nachbarmethode gehoert nicht zu diesem Acquire');
  finally F.Free; end;
end;

procedure TTestUnpairedLock.RaiiCtorDtorPair_NotReported;
// Scope-Guard: Acquire im Konstruktor, Release im Destruktor - genau der
// Fall, den der Detektor-Vertrag ueberspringen will (mORMot TAutoLock).
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TAutoLock.Create(aLock: PSynLocker);'#13#10 +
  'begin'#13#10 +
  '  fLock := aLock;'#13#10 +
  '  fLock^.Lock;'#13#10 +
  'end;'#13#10 +
  'destructor TAutoLock.Destroy;'#13#10 +
  'begin'#13#10 +
  '  fLock^.UnLock;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnpairedLock),
    'Ctor/Dtor-Scope-Guard ist kein bare-Lock');
  finally F.Free; end;
end;

procedure TTestUnpairedLock.AcquireReleaseSameRoutineWithSiblingBelow_StillReported;
// Gegenprobe gegen Ueber-Kappung: Acquire UND Release liegen in derselben
// Routine, darunter folgt eine weitere - der Fund muss bleiben.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure P;'#13#10 +
  'begin'#13#10 +
  '  FCS.Acquire;'#13#10 +
  '  DoStuff;'#13#10 +
  '  FCS.Release;'#13#10 +
  'end;'#13#10 +
  'procedure Q;'#13#10 +
  'begin'#13#10 +
  '  DoOther;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkUnpairedLock) >= 1,
    'Acquire/Release in EINER Routine bleibt ein Fund');
  finally F.Free; end;
end;

procedure TTestUnpairedLock.RtlEventWaitFor_NotCovered_ByDesign;
// DOKUMENTIERT EINE GEWOLLTE GRENZE (Voll-Review 2026-09-12, Major 87).
// Unit-Kopf und Regex-Kommentar behaupteten seit der Geburt der Unit,
// 'RTLeventWaitFor(' sei abgedeckt - implementiert war es nie. Statt
// die Behauptung nachzubauen, wurde gemessen:
//   * Alle 18 RTLeventWaitFor-Stellen des Korpus haben im
//     200-Zeichen-Fenster kein Release -> die Erweiterung waere dort
//     beweisbar wirkungslos (UnlockPos = 0 -> Continue).
//   * Sie waere auch semantisch schief: ein Event setzt typischerweise
//     ein ANDERER Thread, ein fehlendes Gegenstueck in derselben
//     Routine ist der Normalfall.
// Faellt die Entscheidung spaeter anders, wird dieser Test rot und muss
// bewusst umgestellt werden.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Warte;'#13#10 +
  'begin'#13#10 +
  '  RTLeventWaitFor(FEvent);'#13#10 +
  '  DoStuff;'#13#10 +
  '  RTLeventResetEvent(FEvent);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnpairedLock),
    'GEWOLLTE GRENZE: Events sind kein Lock/Unlock-Paar');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUnpairedLock);

end.
