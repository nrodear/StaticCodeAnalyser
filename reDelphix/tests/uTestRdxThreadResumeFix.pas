unit uTestRdxThreadResumeFix;

// Editorhilfe SCA113 ThreadResumeDeprecated (uRdxThreadResumeFix):
// 'X.Resume' -> 'X.Start', nur mit Beweis 'X := T.Create(True)' davor in
// derselben Routine. Zwei Fixtures:
//   TTestRdxThreadResumeFix          der Planer auf Text (Code-Sicht aus
//                                    einer TStringList), ohne Parser und
//                                    Detektor - FPC-tauglich;
//   TTestRdxThreadResumeFixDetector  Rundlaeufe mit dem ECHTEN Detektor
//                                    (uConcurrencyExt) ueber den Einstieg
//                                    der Tabelle (TRdxFixTable.FixFor,
//                                    Adapter PlanThreadResume) - nur
//                                    Delphi.
// Prueft: Umformung (Variable, Inline-Variable, Zweig, Schreibweise,
// eigener Konstruktor mit Weitergabe, Vorfahrenkette in der Datei) und die
// Sperren: Create(False)/andere Zuweisung, keine Erzeugung, Erzeugung im
// Zweig, Schleife, Gebrauch dazwischen, zweimal, Suspend, kein Thread-Typ,
// eigener Konstruktor ohne Weitergabe, alter Compiler, Bedingungsblock,
// Direktive, verschobene/mehrdeutige/qualifizierte Zeile, keine Routine.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxThreadResumeFix = class
  public
    // ---- Umformung ----
    [Test] procedure Sca113_Resume_ToStart;
    [Test] procedure Sca113_InlineVar_ToStart;
    [Test] procedure Sca113_BranchAndCase_ToStart;
    [Test] procedure Sca113_OwnCtorPassesOn_ToStart;
    [Test] procedure Sca113_ReceiverOf;
    // ---- Gegenproben: keine Hilfe ----
    [Test] procedure Sca113_LastAssign_NoHelp;
    [Test] procedure Sca113_NoCreate_NoHelp;
    [Test] procedure Sca113_CreateInBranch_NoHelp;
    [Test] procedure Sca113_Loop_NoHelp;
    [Test] procedure Sca113_UsedBetween_NoHelp;
    [Test] procedure Sca113_TwiceOrSuspend_NoHelp;
    [Test] procedure Sca113_NotThread_NoHelp;
    [Test] procedure Sca113_OwnCtor_NoHelp;
    [Test] procedure Sca113_OldCompiler_NoHelp;
    [Test] procedure Sca113_Conditional_NoHelp;
    [Test] procedure Sca113_Moved_NoHelp;
    [Test] procedure Sca113_NoRoutine_NoHelp;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxThreadResumeFixDetector = class
  public
    [Test] procedure Sca113_Detector_RoundTrip;
    [Test] procedure Sca113_Detector_CatalogExample;
    [Test] procedure Sca113_Detector_CreateFalse_NoHelp;
    [Test] procedure Sca113_Detector_CompilerBranch_NoHelp;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uConcurrencyExt,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uRdxFixTable,          // TRdxFixTable.FixFor
  uTestRdxDetectorKit,   // TSeen, CatalogText, DetectSource
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxThreadResumeFix,
  uRdxText,              // _() und die gemeinsamen Gruende (E29)
  uTestRdxTextKit;       // Join, Apply, LineOf

// ---- Helfer ----

// Die Meldung des Detektors fuer den Empfaenger AName (uConcurrencyExt).
function MsgFor(const AName: string): string;
begin
  Result := Format('%s.Resume is deprecated since Delphi 2010 - prefer '
    + '%s.Start or pass CreateSuspended=False to the constructor. Suppress '
    + 'per line if this is not a TThread reference: // noinspection '
    + 'ThreadResumeDeprecated', [AName, AName]);
end;

const
  // Die Thread-Klasse der meisten Faelle (Name endet auf Thread) ...
  WORKER_DECL: array[0..3] of string = ('  TWorkerThread = class(TThread)',
    '  protected', '    procedure Execute; override;', '  end;');
  // ... und ihre Implementierung.
  WORKER_IMPL: array[0..2] of string = ('procedure TWorkerThread.Execute;',
    'begin', 'end;');
  // Die Klasse des Katalog-Beispiels (TWorker erbt in der Datei von
  // TThread) und ihre Implementierung.
  CATALOG_DECL: array[0..3] of string = ('  TWorker = class(TThread)',
    '  protected', '    procedure Execute; override;', '  end;');
  CATALOG_IMPL: array[0..2] of string = ('procedure TWorker.Execute;',
    'begin', 'end;');

// Eine Unit: AIntf im type-Teil des interface, AImpl am Anfang des
// implementation-Teils, dahinter 'procedure Run(A: Boolean);' mit den
// Variablen AVars und dem Rumpf ABody.
function UnitText(const AIntf, AImpl, AVars, ABody: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'uses', '  System.Classes;', 'type'])
    + #13#10 + Join(AIntf) + #13#10 + 'implementation' + #13#10 + Join(AImpl)
    + #13#10 + Join(['procedure Run(A: Boolean);', 'var']) + #13#10
    + Join(AVars) + #13#10 + 'begin' + #13#10 + Join(ABody) + #13#10
    + Join(['end;', 'end.']);
end;

// Die uebliche Unit: TWorkerThread, 'Worker: TWorkerThread', Rumpf ABody.
function InRun(const ABody: array of string): string;
begin
  Result := UnitText(WORKER_DECL, WORKER_IMPL,
    ['  Worker: TWorkerThread;', '  I: Integer;'], ABody);
end;

// Der Planer an Zeile ALine fuer den Empfaenger AName: der neue Text, bei
// einer Ablehnung '' und der Grund in AReason.
function FixAt(const ASource: string; ALine: Integer; const AName: string;
  out AReason: string): string;
var
  SL   : TStringList;
  Map  : TRdxCodeMap;
  Edit : TRdxEdit;
begin
  Result := '';
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    if TRdxThreadResumeFix.ResumeToStart(Map, ALine, MsgFor(AName), Edit,
         AReason) then
      Result := Apply(ASource, Edit);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Dasselbe an der ersten Zeile mit '<AName>.Resume'.
function Fix(const ASource, AName: string; out AReason: string): string;
begin
  Result := FixAt(ASource, LineOf(ASource, AName + '.Resume'), AName, AReason);
end;

// Die Hilfe muss Text liefern und ohne Grund auskommen.
function Fixed(const ASource, AName: string): string;
var
  Reason : string;
begin
  Result := Fix(ASource, AName, Reason);
  Assert.AreEqual('', Reason);
end;

// Keine Hilfe, der Grund ist AReason.
procedure AssertRefused(const ASource, AName, AReason: string);
var
  Reason : string;
begin
  Assert.AreEqual('', Fix(ASource, AName, Reason));
  Assert.AreEqual(AReason, Reason);
end;

// ---- Umformung ----

procedure TTestRdxThreadResumeFix.Sca113_Resume_ToStart;
var
  S : string;
begin
  // Angehalten erzeugt, dazwischen nur Eigenschaften gesetzt: Start.
  S := InRun(['  Worker := TWorkerThread.Create(True);',
    '  Worker.FreeOnTerminate := True;', '  Worker.Priority := tpLower;',
    '  Worker.Resume;']);
  Assert.AreEqual(StringReplace(S, 'Worker.Resume', 'Worker.Start', []),
    Fixed(S, 'Worker'));
  // Auf einer Zeile, Unit-qualifizierter Typ.
  S := InRun(['  Worker := t.TWorkerThread.Create(True); Worker.Resume;']);
  Assert.AreEqual(StringReplace(S, 'Worker.Resume', 'Worker.Start', []),
    Fixed(S, 'Worker'));
end;

procedure TTestRdxThreadResumeFix.Sca113_InlineVar_ToStart;
var
  S : string;
begin
  S := InRun(['  var W := TWorkerThread.Create(True);', '  W.Resume;']);
  Assert.AreEqual(StringReplace(S, 'W.Resume', 'W.Start', []), Fixed(S, 'W'));
  S := InRun(['  var W2: TThread := TWorkerThread.Create(True);',
    '  W2.Resume;']);
  Assert.AreEqual(StringReplace(S, 'W2.Resume', 'W2.Start', []),
    Fixed(S, 'W2'));
end;

procedure TTestRdxThreadResumeFix.Sca113_BranchAndCase_ToStart;
var
  S, Reason : string;
begin
  // Resume in einem Zweig hinter der Erzeugung - hoechstens einmal.
  S := InRun(['  Worker := TWorkerThread.Create(True);', '  if A then',
    '  begin', '    Worker.Resume;', '  end;']);
  Assert.AreEqual(StringReplace(S, 'Worker.Resume', 'Worker.Start', []),
    Fixed(S, 'Worker'));
  // Schreibweise wie im Text; der Name der Meldung passt ohne Gross/klein.
  S := InRun(['  Worker := TWorkerThread.Create(True);', '  Worker.RESUME;']);
  Assert.AreEqual(StringReplace(S, 'Worker.RESUME', 'Worker.START', []),
    FixAt(S, LineOf(S, 'Worker.RESUME'), 'Worker', Reason));
  Assert.AreEqual('', Reason);
  S := InRun(['  worker := TWorkerThread.Create(true);', '  worker.resume;']);
  Assert.AreEqual(StringReplace(S, 'worker.resume', 'worker.start', []),
    Fixed(S, 'worker'));
end;

procedure TTestRdxThreadResumeFix.Sca113_OwnCtorPassesOn_ToStart;
var
  S : string;
begin
  // TWorker endet nicht auf Thread - die Vorfahrenkette in der Datei
  // erreicht TThread; der eigene Konstruktor reicht den Parameter weiter.
  S := UnitText(['  TWorker = class(TThread)', '  public',
    '    constructor Create(const ASuspended: Boolean);', '  end;'],
    ['constructor TWorker.Create(const ASuspended: Boolean);', 'begin',
     '  inherited Create(ASuspended);', '  FreeOnTerminate := True;', 'end;'],
    ['  Job: TWorker;'],
    ['  Job := TWorker.Create(True);', '  Job.Resume;']);
  Assert.AreEqual(StringReplace(S, 'Job.Resume', 'Job.Start', []),
    Fixed(S, 'Job'));
  // 'inherited;' reicht dieselben Argumente weiter.
  S := StringReplace(S, 'inherited Create(ASuspended);', 'inherited;', []);
  Assert.AreEqual(StringReplace(S, 'Job.Resume', 'Job.Start', []),
    Fixed(S, 'Job'));
end;

procedure TTestRdxThreadResumeFix.Sca113_ReceiverOf;
begin
  Assert.AreEqual('Worker', TRdxThreadResumeFix.ReceiverOf(MsgFor('Worker')));
  Assert.AreEqual('FThread', TRdxThreadResumeFix.ReceiverOf(MsgFor('FThread')));
  Assert.AreEqual('', TRdxThreadResumeFix.ReceiverOf('Worker.Resume'));
  Assert.AreEqual('', TRdxThreadResumeFix.ReceiverOf(MsgFor('')));
  AssertRefused(InRun(['  Worker.Resume;']), '', _(R_TR_NO_NAME));
end;

// ---- Gegenproben: keine Hilfe ----

procedure TTestRdxThreadResumeFix.Sca113_LastAssign_NoHelp;
var
  S : string;
begin
  // Create(False): der Thread laeuft schon - Start wuerfe EThread.
  S := InRun(['  Worker := TWorkerThread.Create(False);', '  Worker.Resume;']);
  AssertRefused(S, 'Worker', _(R_TR_LAST_ASSIGN,
    ['Worker', LineOf(S, 'Create(False)')]));
  // Nach der Erzeugung ein anderer Wert.
  S := InRun(['  Worker := TWorkerThread.Create(True);', '  Worker := Other;',
    '  Worker.Resume;']);
  AssertRefused(S, 'Worker', _(R_TR_LAST_ASSIGN,
    ['Worker', LineOf(S, 'Worker := Other')]));
  // Ein Parameter statt True.
  S := InRun(['  Worker := TWorkerThread.Create(A);', '  Worker.Resume;']);
  AssertRefused(S, 'Worker', _(R_TR_LAST_ASSIGN,
    ['Worker', LineOf(S, 'Create(A)')]));
end;

procedure TTestRdxThreadResumeFix.Sca113_NoCreate_NoHelp;
begin
  // Das Feld kam von woanders - ob angehalten erzeugt, weiss niemand.
  AssertRefused(InRun(['  Worker.Resume;']), 'Worker',
    _(R_TR_NO_CREATE, ['Worker']));
end;

procedure TTestRdxThreadResumeFix.Sca113_CreateInBranch_NoHelp;
begin
  AssertRefused(InRun(['  if A then', '    Worker := TWorkerThread.Create(True);',
    '  Worker.Resume;']), 'Worker', _(R_TR_BRANCH, ['Worker']));
  AssertRefused(InRun(['  if A then', '  begin',
    '    Worker := TWorkerThread.Create(True);', '  end;', '  Worker.Resume;']),
    'Worker', _(R_TR_BRANCH, ['Worker']));
  AssertRefused(InRun(['  if A then Worker := TWorkerThread.Create(False) else',
    '    Worker := TWorkerThread.Create(True);', '  Worker.Resume;']),
    'Worker', _(R_TR_BRANCH, ['Worker']));
end;

procedure TTestRdxThreadResumeFix.Sca113_Loop_NoHelp;
begin
  // Eine Schleife dazwischen bzw. um das Resume: es liefe mehrfach.
  AssertRefused(InRun(['  Worker := TWorkerThread.Create(True);',
    '  while A do', '  begin', '    Worker.Resume;', '  end;']), 'Worker',
    _(R_TR_FLOW, ['while']));
  AssertRefused(InRun(['  Worker := TWorkerThread.Create(True);',
    '  for I := 1 to 2 do Worker.Resume;']), 'Worker',
    _(R_TR_LOOP, ['Worker', 'do']));
  // with vor der Erzeugung: Worker koennte ein Feld des with-Objekts sein.
  AssertRefused(InRun(['  with Pool do', '  begin',
    '    Worker := TWorkerThread.Create(True);', '    Worker.Resume;',
    '  end;']), 'Worker', _(R_TR_FLOW, ['with']));
end;

procedure TTestRdxThreadResumeFix.Sca113_UsedBetween_NoHelp;
var
  S : string;
begin
  S := InRun(['  Worker := TWorkerThread.Create(True);', '  Register(Worker);',
    '  Worker.Resume;']);
  AssertRefused(S, 'Worker', _(R_TR_USED,
    ['Worker', LineOf(S, 'Register(Worker)')]));
  S := InRun(['  Worker := TWorkerThread.Create(True);',
    '  Worker.Suspended := False;', '  Worker.Resume;']);
  AssertRefused(S, 'Worker', _(R_TR_USED,
    ['Worker', LineOf(S, 'Suspended')]));
  // Eine Direktive dazwischen.
  AssertRefused(InRun(['  Worker := TWorkerThread.Create(True);', '  {$R-}',
    '  Worker.Resume;']), 'Worker', _(R_TR_DIRECTIVE));
end;

procedure TTestRdxThreadResumeFix.Sca113_TwiceOrSuspend_NoHelp;
begin
  AssertRefused(InRun(['  Worker := TWorkerThread.Create(True);',
    '  Worker.Resume;', '  if A then', '    Worker.Resume;']), 'Worker',
    _(R_TR_TWICE, ['Worker']));
  AssertRefused(InRun(['  Worker := TWorkerThread.Create(True);',
    '  Worker.Resume;', '  if A then', '    Worker.Suspend;']), 'Worker',
    _(R_TR_SUSPEND, ['Worker']));
end;

procedure TTestRdxThreadResumeFix.Sca113_NotThread_NoHelp;
begin
  // TTask erbt von TObject - Resume und Start sind dort eigene Methoden.
  AssertRefused(UnitText(['  TTask = class(TObject)', '  public',
    '    procedure Resume;', '  end;'],
    ['procedure TTask.Resume;', 'begin', 'end;'], ['  Job: TTask;'],
    ['  Job := TTask.Create(True);', '  Job.Resume;']), 'Job',
    _(R_TR_NOT_THREAD, ['TTask']));
  // Typ aus einer anderen Unit, Name ohne Thread: nicht beweisbar.
  AssertRefused(UnitText([], [], ['  Job: TWorker;'],
    ['  Job := TWorker.Create(True);', '  Job.Resume;']), 'Job',
    _(R_TR_NOT_THREAD, ['TWorker']));
end;

procedure TTestRdxThreadResumeFix.Sca113_OwnCtor_NoHelp;
var
  S : string;
begin
  // Der eigene Konstruktor startet immer (inherited Create(False)) - True
  // heisst hier etwas anderes.
  S := UnitText(['  TWorkerThread = class(TThread)', '  public',
    '    constructor Create(AAutoFree: Boolean);', '  end;'],
    ['constructor TWorkerThread.Create(AAutoFree: Boolean);', 'begin',
     '  inherited Create(False);', '  FreeOnTerminate := AAutoFree;', 'end;'],
    ['  Worker: TWorkerThread;'],
    ['  Worker := TWorkerThread.Create(True);', '  Worker.Resume;']);
  AssertRefused(S, 'Worker', _(R_TR_OWN_CTOR, ['TWorkerThread']));
end;

procedure TTestRdxThreadResumeFix.Sca113_OldCompiler_NoHelp;
var
  S : string;
begin
  // Die Datei fragt nach Delphi 2010 - sie baut auch mit 2009 (ohne Start).
  S := UnitText(WORKER_DECL,
    ['{$IF CompilerVersion >= 21}{$DEFINE HAS_START}{$IFEND}'],
    ['  Worker: TWorkerThread;'],
    ['  Worker := TWorkerThread.Create(True);', '  Worker.Resume;']);
  AssertRefused(S, 'Worker', _(R_TR_OLD_COMPILER,
    ['COMPILERVERSION >= 21', LineOf(S, 'CompilerVersion')]));
  // Ein Kit-Include (JEDI baut ab Delphi 5).
  S := UnitText(WORKER_DECL, ['{$I jedi.inc}'], ['  Worker: TWorkerThread;'],
    ['  Worker := TWorkerThread.Create(True);', '  Worker.Resume;']);
  AssertRefused(S, 'Worker', _(R_TR_OLD_COMPILER,
    ['jedi.inc', LineOf(S, 'jedi.inc')]));
  // Altes FPC (Start erst ab 2.6) - 'FPC_FULLVERSION >= 20600' zaehlt mit.
  S := UnitText(WORKER_DECL, ['{$IF FPC_FULLVERSION >= 20600}{$IFEND}'],
    ['  Worker: TWorkerThread;'],
    ['  Worker := TWorkerThread.Create(True);', '  Worker.Resume;']);
  AssertRefused(S, 'Worker', _(R_TR_OLD_COMPILER,
    ['FPC_FULLVERSION >= 20600', LineOf(S, 'FPC_FULLVERSION')]));
  // Gegenprobe: eine Frage nach einem juengeren Compiler sperrt nicht.
  S := UnitText(WORKER_DECL, ['{$IF CompilerVersion >= 22}{$IFEND}'],
    ['  Worker: TWorkerThread;'],
    ['  Worker := TWorkerThread.Create(True);', '  Worker.Resume;']);
  Assert.AreEqual(StringReplace(S, 'Worker.Resume', 'Worker.Start', []),
    Fixed(S, 'Worker'));
end;

procedure TTestRdxThreadResumeFix.Sca113_Conditional_NoHelp;
var
  S : string;
begin
  AssertRefused(InRun(['  Worker := TWorkerThread.Create(True);',
    '  {$IFDEF FPC}', '  Worker.Resume;', '  {$ENDIF}']), 'Worker',
    _(R_TR_CONDITIONAL));
  // Nach dem {$ENDIF} ist der Block zu - und '{$IFDEF X}' in einem
  // Kommentar oeffnet keinen.
  S := InRun(['  // {$IFDEF X}', '  {$IFDEF FPC}', '  Foo;', '  {$ENDIF}',
    '  Worker := TWorkerThread.Create(True);', '  Worker.Resume;']);
  Assert.AreEqual(StringReplace(S, 'Worker.Resume', 'Worker.Start', []),
    Fixed(S, 'Worker'));
end;

procedure TTestRdxThreadResumeFix.Sca113_Moved_NoHelp;
var
  S, Reason : string;
begin
  // Kommentar und String sind kein Aufruf.
  S := InRun(['  Worker := TWorkerThread.Create(True);',
    '  Log(''Worker.Resume''); // Worker.Resume', '  Worker.Start;']);
  Assert.AreEqual('', FixAt(S, LineOf(S, 'Log('), 'Worker', Reason));
  Assert.AreEqual(MsgMovedSuffix(_(R_TR_MOVED, ['Worker'])), Reason);
  // Zwei auf einer Zeile.
  S := InRun(['  Worker := TWorkerThread.Create(True);',
    '  Worker.Resume; Worker.Resume;']);
  AssertRefused(S, 'Worker', _(R_TR_MANY,
    [LineOf(S, 'Worker.Resume'), 2, 'Worker']));
  // Ueber einen Qualifizierer - der Beweis kennt nur die blosse Variable.
  AssertRefused(InRun(['  Pool.Worker := TWorkerThread.Create(True);',
    '  Pool.Worker.Resume;']), 'Worker', _(R_TR_QUALIFIED, ['Worker']));
end;

procedure TTestRdxThreadResumeFix.Sca113_NoRoutine_NoHelp;
var
  S : string;
begin
  S := Join(['unit t;', 'interface', 'implementation', 'var',
    '  Worker: TWorkerThread;', 'initialization',
    '  Worker := TWorkerThread.Create(True);', '  Worker.Resume;', 'end.']);
  AssertRefused(S, 'Worker', _(R_TR_NO_ROUTINE, ['Worker']));
end;

{$IFNDEF FPC}

// ---- Echter Detektor (uConcurrencyExt) ----

procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TConcurrencyExtDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_s113_', ASource, fkThreadResumeDeprecated,
    RunDetector);
end;

// Die Hilfe fuer einen Fund des Detektors ueber den Einstieg der Tabelle
// (TRdxFixTable.FixFor, Adapter PlanThreadResume) - ohne Quellstellen-
// Dienst, den die Hilfe nicht braucht.
function PlanSeen(const ASource: string; const ASeen: TSeen): TRdxFixOutcome;
var
  SL : TStringList;
  F  : TLeakFinding;
begin
  SL := TStringList.Create;
  F := TLeakFinding.New('t.pas', '', ASeen.Line, ASeen.Msg,
    fkThreadResumeDeprecated);
  try
    SL.Text := ASource;
    Result := TRdxFixTable.FixFor(nil, SL, F, nil);
  finally
    F.Free;
    SL.Free;
  end;
end;

// Fund fuer Fund, nach jeder Ersetzung neu gemeldet, bis der Detektor
// schweigt.
function FixAll(const ASource: string): string;
const
  MAX_PASSES = 10;
var
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
  Pass : Integer;
begin
  Result := ASource;
  for Pass := 1 to MAX_PASSES do
  begin
    Seen := Detect(Result);
    if Length(Seen) = 0 then Exit;
    O := PlanSeen(Result, Seen[0]);
    Assert.IsTrue(O.Enabled, Format('Zeile %d: %s', [Seen[0].Line, O.Reason]));
    Result := Apply(Result, O.Edits);
  end;
  Assert.Fail(Format('der Detektor meldet nach %d Runden noch', [MAX_PASSES]));
end;

// Der Detektor meldet, die Hilfe lehnt den ersten Fund mit AReason ab.
procedure AssertDetectorNoHelp(const ASource, AReason: string);
var
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  Seen := Detect(ASource);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet');
  O := PlanSeen(ASource, Seen[0]);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(AReason, O.Reason);
  Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
end;

procedure TTestRdxThreadResumeFixDetector.Sca113_Detector_RoundTrip;
var
  Source : string;
  Seen   : TArray<TSeen>;
begin
  // Zwei Erzeugungen mit Resume - der Detektor meldet beide (Zeile des
  // Empfaengers, Name in der Meldung), nach der Hilfe keine mehr.
  Source := InRun(['  Worker := TWorkerThread.Create(True);',
    '  Worker.FreeOnTerminate := True;', '  Worker.Resume;',
    '  var Other := TWorkerThread.Create(True);', '  Other.Resume;']);
  Seen := Detect(Source);
  Assert.AreEqual<Integer>(2, Length(Seen));
  Assert.AreEqual<Integer>(LineOf(Source, 'Worker.Resume'), Seen[0].Line);
  Assert.AreEqual('Worker', TRdxThreadResumeFix.ReceiverOf(Seen[0].Msg));
  Assert.AreEqual(
    StringReplace(StringReplace(Source, 'Worker.Resume', 'Worker.Start', []),
      'Other.Resume', 'Other.Start', []),
    FixAll(Source));
end;

procedure TTestRdxThreadResumeFixDetector.Sca113_Detector_CatalogExample;
var
  Meta      : TRuleMeta;
  Bad, Good : string;
begin
  // 'bad' des Katalogs ('MyThread := TWorker.Create(True); MyThread.Resume;')
  // wird 'good' - TWorker erbt in der Datei von TThread.
  Meta := TRuleCatalog.GetRuleCanonical(fkThreadResumeDeprecated);
  Bad := CatalogText(Meta.BadExample);
  Good := CatalogText(Meta.GoodExample);
  Assert.IsTrue(Pos('Create(True)', Bad) > 0, Bad);
  Assert.AreEqual<Integer>(1, Length(Detect(UnitText(CATALOG_DECL,
    CATALOG_IMPL, ['  MyThread: TWorker;'], [Bad]))));
  Assert.AreEqual(
    UnitText(CATALOG_DECL, CATALOG_IMPL, ['  MyThread: TWorker;'], [Good]),
    FixAll(UnitText(CATALOG_DECL, CATALOG_IMPL, ['  MyThread: TWorker;'],
      [Bad])));
end;

procedure TTestRdxThreadResumeFixDetector.Sca113_Detector_CreateFalse_NoHelp;
var
  S : string;
begin
  // Der Detektor meldet jedes Resume - die Hilfe nur das bewiesene.
  S := InRun(['  Worker := TWorkerThread.Create(False);', '  Worker.Resume;']);
  AssertDetectorNoHelp(S, _(R_TR_LAST_ASSIGN,
    ['Worker', LineOf(S, 'Create(False)')]));
end;

procedure TTestRdxThreadResumeFixDetector.Sca113_Detector_CompilerBranch_NoHelp;
var
  S : string;
begin
  // Der Altzweig des Korpus: der Detektor sieht durch die Direktiven
  // hindurch und meldet das Resume, die Hilfe nennt den alten Compiler.
  S := InRun(['  Worker := TWorkerThread.Create(True);',
    '  {$IF CompilerVersion >= 21}', '  Worker.Start;', '  {$ELSE}',
    '  Worker.Resume;', '  {$IFEND}']);
  AssertDetectorNoHelp(S, _(R_TR_OLD_COMPILER,
    ['COMPILERVERSION >= 21', LineOf(S, 'CompilerVersion')]));
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxThreadResumeFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxThreadResumeFixDetector);
  {$ENDIF}

end.
