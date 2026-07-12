unit uTestConcurrencyExt;

// Tests fuer TConcurrencyExtDetector (SCA113-114).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestConcurrencyExt = class
  public
    // ThreadResumeDeprecated
    [Test] procedure Resume_Reported;
    [Test] procedure Start_NotReported;
    [Test] procedure ResumeAssignment_NotReported;

    // TThreadDestroyWithoutTerminate
    [Test] procedure FreeAndNilWithoutTerminate_Reported;
    [Test] procedure FreeAndNilWithTerminateAndWait_NotReported;
    [Test] procedure FreeAndNilWithOnlyWaitFor_NotReported;
    // Type-Filter: nur feuern wenn Identifier-Typ nach TThread aussieht.
    [Test] procedure FreeAndNilObjectList_NotReported;
    [Test] procedure FreeAndNilStringList_NotReported;
    [Test] procedure FreeAndNilThreadTyped_Reported;
    // FP-Regression Real-World 2026-06-26: thread-BENENNENDE Nicht-Thread-
    // Klassen (Name enthaelt 'Thread', endet aber nicht darauf; Basis=TObject),
    // generische Container deren Typargumente 'Thread' leaken, sowie
    // compound-/cross-unit-deklarierte (unaufloesbare) Felder.
    [Test] procedure FreeAndNilThreadNamedNonThread_NotReported;
    [Test] procedure FreeAndNilGenericThreadDict_NotReported;
    [Test] procedure FreeAndNilCompoundDecl_NotReported;
    // TP via in-file Basisklassen-Aufloesung: Descendant heisst NICHT *Thread.
    [Test] procedure FreeAndNilThreadDescendantNoThreadName_Reported;
    // Spezialfall Result: Typ kommt aus dem Function-Header.
    [Test] procedure FreeAndNilResult_StringListReturn_NotReported;
    [Test] procedure FreeAndNilResult_ThreadReturn_Reported;
    // Cross-Unit-Global: Identifier nicht im File deklariert, aber via
    // Konstruktor-Call instanziiert -> Typ aus `:= TXxx.Create` ableiten.
    [Test] procedure FreeAndNilCrossUnitGlobal_NotReported;
    // FP-Regression: dxgettext-msgid mit 'FreeAndNil(X)' in Quotes darf
    // den Detector nicht ausloesen - Strings werden via
    // TDetectorUtils.StripStringsAndComments wegmaskiert.
    [Test] procedure FreeAndNilInsideStringLiteral_NotReported;
    // --- Real-World FP-Audit 2026-07-10 Regression (Welle 1+2) ---
    [Test] procedure Resume_OnDeclHeader_NotReported;
    [Test] procedure Resume_ThreadTypedReceiver_Reported;
    // --- Real-World FP-Audit 2026-07-12, FP-Klasse 'wrong-type-receiver' ---
    // Inline-var-Deklaration 'var X: <Typ> := <init>;' - Empfaenger-Typ wird
    // jetzt zwischen ':' und ':=' aufgeloest.
    [Test] procedure Resume_InlineVarNonThreadReceiver_NotReported;
    [Test] procedure Resume_InlineVarProcessReceiver_NotReported;
    [Test] procedure Resume_InlineVarThreadReceiver_Reported;
    // --- Track C (Cross-Unit-TypeIndex) Opt-in, Runde 2 ---
    // FP-Klasse 'not-a-tthread': '...thread'-benannter Nicht-Thread. Der
    // TypeIndex wird NUR im vollen Pipeline-Weg (FindingsViaPipeline) gebaut;
    // FindingsOf/FindingsOfFile rufen den Detektor mit AContext=nil auf, dort
    // ist das Opt-in inaktiv (nil-Fallback = bisheriges Verhalten).
    [Test] procedure FreeAndNilJvThreadChain_ViaPipeline_Suppressed;
    [Test] procedure FreeAndNilJvThreadChain_NoContext_StillReported;
    [Test] procedure FreeAndNilRealThreadDescendant_ViaPipeline_Reported;
    [Test] procedure FreeAndNilThreadOutOfScopeBase_ViaPipeline_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestConcurrencyExt.Resume_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  MyWorker.Resume;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkThreadResumeDeprecated),
      'genau 1 ThreadResume-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'MyWorker.Resume'),
      TFindingHelper.FirstOf(F, fkThreadResumeDeprecated).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestConcurrencyExt.Start_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  MyWorker.Start;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkThreadResumeDeprecated));
  finally F.Free; end;
end;

procedure TTestConcurrencyExt.ResumeAssignment_NotReported;
// `OnResume := xxx` ist eine Property-Zuweisung - das `.Resume` ist
// kein Method-Call. Detector erkennt das per Negative-Lookahead `(?!=)`.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  MyObj.Resume := True;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkThreadResumeDeprecated));
  finally F.Free; end;
end;

procedure TTestConcurrencyExt.FreeAndNilWithoutTerminate_Reported;
// Unaufloesbarer Typ, aber Identifier-Name traegt den Thread-Hinweis ->
// feuert ueber den Name-Fallback (Real-World 2026-06-26 Policy).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  FreeAndNil(FWorkerThread);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate),
      'genau 1 ThreadDestroy-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'FreeAndNil(FWorkerThread'),
      TFindingHelper.FirstOf(F, fkTThreadDestroyWithoutTerminate).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestConcurrencyExt.FreeAndNilWithTerminateAndWait_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  FWorkerThread.Terminate;'#13#10 +
  '  FWorkerThread.WaitFor;'#13#10 +
  '  FreeAndNil(FWorkerThread);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate));
  finally F.Free; end;
end;

procedure TTestConcurrencyExt.FreeAndNilWithOnlyWaitFor_NotReported;
// Regression MVCFramework.Console.TConsoleSpinner.Hide:
//   FThread.WaitFor;
//   FreeAndNil(FThread);
// Thread laeuft endlichen Job, beendet sich natuerlich. KEIN Terminate
// noetig. Detector soll WaitFor alleine als protective intent werten.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  FWorkerThread.WaitFor;'#13#10 +
  '  FreeAndNil(FWorkerThread);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate),
    'WaitFor alleine reicht als protective intent');
  finally F.Free; end;
end;

procedure TTestConcurrencyExt.FreeAndNilObjectList_NotReported;
// Spiegelt den realen FP aus uIDEWatchMode.FResults: FreeAndNil auf einer
// TObjectList ist KEIN TThread-Free und darf nicht flaggen.
const SRC =
  'unit t; interface'#13#10 +
  'uses System.Generics.Collections;'#13#10 +
  'type TFoo = class'#13#10 +
  '  FResults: TObjectList<Integer>;'#13#10 +
  '  procedure Do_;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Do_;'#13#10 +
  'begin'#13#10 +
  '  FreeAndNil(FResults);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate));
  finally F.Free; end;
end;

procedure TTestConcurrencyExt.FreeAndNilStringList_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'uses System.Classes;'#13#10 +
  'type TFoo = class'#13#10 +
  '  FLines: TStringList;'#13#10 +
  '  procedure Do_;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Do_;'#13#10 +
  'begin'#13#10 +
  '  FreeAndNil(FLines);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate));
  finally F.Free; end;
end;

procedure TTestConcurrencyExt.FreeAndNilThreadTyped_Reported;
// Typname enthaelt 'Thread' -> Detector flaggt weiterhin (echter Treffer).
const SRC =
  'unit t; interface'#13#10 +
  'uses System.Classes;'#13#10 +
  'type TFoo = class'#13#10 +
  '  FWorker: TMyWorkerThread;'#13#10 +
  '  procedure Do_;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Do_;'#13#10 +
  'begin'#13#10 +
  '  FreeAndNil(FWorker);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate),
      'genau 1 ThreadDestroy-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'FreeAndNil(FWorker)'),
      TFindingHelper.FirstOf(F, fkTThreadDestroyWithoutTerminate).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestConcurrencyExt.FreeAndNilThreadNamedNonThread_NotReported;
// Real-World FP: doublecmd TMultiThreadProcItem = class (TObject) - Name
// enthaelt 'Thread', ist aber kein TThread-Descendant. Frueher feuerte der
// reine 'enthaelt thread'-Substring-Test. Jetzt: endet nicht auf 'thread'
// UND in-file Basisklasse ist TObject -> kein Befund.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TMultiThreadProcItem = class(TObject)'#13#10 +
  '  end;'#13#10 +
  '  TFoo = class'#13#10 +
  '    FItem: TMultiThreadProcItem;'#13#10 +
  '    procedure Do_;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Do_;'#13#10 +
  'begin'#13#10 +
  '  FreeAndNil(FItem);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate),
    'Thread-benennende TObject-Klasse darf nicht flaggen');
  finally F.Free; end;
end;

procedure TTestConcurrencyExt.FreeAndNilGenericThreadDict_NotReported;
// Real-World FP: FMX.Skia.Canvas.GL FThreadDictionary: TDictionary<TThreadID,
// TThreadContextInfo>. Generische Typargumente leakten 'thread' in die
// Heuristik. StripGenerics entfernt sie -> Basis 'TDictionary' -> kein Befund.
const SRC =
  'unit t; interface'#13#10 +
  'uses System.Generics.Collections;'#13#10 +
  'type TFoo = class'#13#10 +
  '  FThreadDictionary: TDictionary<TThreadID, TThreadContextInfo>;'#13#10 +
  '  procedure Do_;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Do_;'#13#10 +
  'begin'#13#10 +
  '  FreeAndNil(FThreadDictionary);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate),
    'Generic-Container mit Thread-Typargument darf nicht flaggen');
  finally F.Free; end;
end;

procedure TTestConcurrencyExt.FreeAndNilCompoundDecl_NotReported;
// Real-World FP: doublecmd `FFileR, FFileL: TFile;` - compound-Deklaration,
// der `<Ident> : <Type>`-Regex findet den Typ von FFileR nicht (Komma statt
// Doppelpunkt). Unaufloesbarer Typ zaehlt jetzt als Nicht-Thread.
const SRC =
  'unit t; interface'#13#10 +
  'uses System.Classes;'#13#10 +
  'type TFoo = class'#13#10 +
  '  FFileR, FFileL: TFile;'#13#10 +
  '  procedure Do_;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Do_;'#13#10 +
  'begin'#13#10 +
  '  FreeAndNil(FFileR);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate),
    'Compound-/unaufloesbare Deklaration darf nicht flaggen');
  finally F.Free; end;
end;

procedure TTestConcurrencyExt.FreeAndNilThreadDescendantNoThreadName_Reported;
// Gegenkontrolle: ein echter TThread-Descendant der NICHT auf 'Thread' endet
// muss weiterhin (per in-file Basisklassen-Aufloesung) feuern - sonst waere
// der Fix ein Detektions-Verlust.
const SRC =
  'unit t; interface'#13#10 +
  'uses System.Classes;'#13#10 +
  'type'#13#10 +
  '  TBackgroundJob = class(TThread)'#13#10 +
  '  end;'#13#10 +
  '  TFoo = class'#13#10 +
  '    FJob: TBackgroundJob;'#13#10 +
  '    procedure Do_;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Do_;'#13#10 +
  'begin'#13#10 +
  '  FreeAndNil(FJob);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate) >= 1,
    'TThread-Descendant ohne Thread-Suffix muss per Basisklasse erkannt werden');
  finally F.Free; end;
end;

procedure TTestConcurrencyExt.FreeAndNilResult_StringListReturn_NotReported;
// Spiegelt den realen FP aus uExportHtml.GetSourceLines: nested function
// liefert TStringList, FreeAndNil(Result) ist kein Thread-Free.
const SRC =
  'unit t; implementation'#13#10 +
  'function Load(const APath: string): TStringList;'#13#10 +
  'begin'#13#10 +
  '  Result := TStringList.Create;'#13#10 +
  '  try'#13#10 +
  '    Result.LoadFromFile(APath);'#13#10 +
  '  except'#13#10 +
  '    FreeAndNil(Result);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate));
  finally F.Free; end;
end;

procedure TTestConcurrencyExt.FreeAndNilResult_ThreadReturn_Reported;
// Return-Type enthaelt 'Thread' -> echter Treffer, weiterhin flaggen.
const SRC =
  'unit t; implementation'#13#10 +
  'function Spawn: TWorkerThread;'#13#10 +
  'begin'#13#10 +
  '  Result := TWorkerThread.Create(True);'#13#10 +
  '  FreeAndNil(Result);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate),
      'genau 1 ThreadDestroy-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'FreeAndNil(Result)'),
      TFindingHelper.FirstOf(F, fkTThreadDestroyWithoutTerminate).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestConcurrencyExt.FreeAndNilCrossUnitGlobal_NotReported;
// Regression: gDfmRepoIndex / gAstFileCache / gSymbolRefIndex sind in
// anderen Units deklariert, werden im uStaticAnalyzer2 nur instanziiert
// und freigegeben. Vor dem Detector-Fix hat der `<Ident> : <Type>;`-
// Regex die Deklaration im selben File nicht gefunden und konservativ
// geflaggt. Jetzt zieht der Konstruktor-Call-Fallback den Typ aus
// `:= TXxx.Create`.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure DoStuff;'#13#10 +
  'begin'#13#10 +
  '  gFoo := TMyIndex.Create;'#13#10 +
  '  try gFoo.Build;'#13#10 +
  '  except FreeAndNil(gFoo);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate));
  finally F.Free; end;
end;

procedure TTestConcurrencyExt.FreeAndNilInsideStringLiteral_NotReported;
// FP-Regression aus Real-World-Code (uLocalization.pas Z.283):
//   GDeMap.Add('X.Free; X := nil; -> use FreeAndNil(X)',
//              'X.Free; X := nil; -> FreeAndNil(X) nutzen');
// Vor dem Strip-Fix hat der Detector den Text INSIDE der msgid-Strings als
// echte FreeAndNil-Calls interpretiert und geflaggt. Nach Umstellung auf
// TDetectorUtils.StripStringsAndComments (statt lokalem StripFileComments
// der Strings 1:1 erhielt) werden String-Inhalte mit '~' aufgefuellt und
// das Regex-Match schweigt korrekt.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure SetupMap;'#13#10 +
  'begin'#13#10 +
  '  Map.Add(''X.Free; X := nil; -> use FreeAndNil(X)'','#13#10 +
  '          ''X.Free; X := nil; -> FreeAndNil(X) nutzen'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate),
        'FreeAndNil in String-Literal darf den Detector nicht ausloesen');
  finally F.Free; end;
end;


// --- Real-World FP-Audit 2026-07-10 Regression (Welle 1+2) ---

procedure TTestConcurrencyExt.Resume_OnDeclHeader_NotReported;
// Real-World FP-Audit 2026-07-10 (Alcinoe.FMX.Ani.pas:1666): der Methoden-
// HEADER 'procedure TALAnimation.Resume;' ist die Deklaration einer Animations-
// State-Machine (Start/Stop/Pause/Resume via FPaused) - KEIN deprecated
// TThread.Resume-Aufruf. Der neue Decl-Header-Guard (IsResumeNonCallContext
// Fall a: vorheriges Token ist 'procedure'/'function') unterdrueckt das.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TALAnimation.Resume;'#13#10 +
  'begin'#13#10 +
  '  FPaused := False;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkThreadResumeDeprecated),
    'Methoden-Deklarationsheader .Resume ist kein TThread.Resume-Aufruf');
  finally F.Free; end;
end;

procedure TTestConcurrencyExt.Resume_ThreadTypedReceiver_Reported;
// Must-stay TP (Real-World tp_examples_must_stay: aBenchThread = TBenchThread,
// ein TThread). Ein echter TThread.Resume-Aufruf, dessen Empfaenger-Typ in-file
// auf einen TThread-Descendant aufloest, muss trotz der neuen Empfaenger-Typ-
// Aufloesung weiter feuern (LooksLikeThreadType-Accept-Zweig). Gegenstueck zu
// den unterdrueckten FMX-Animation/NSURLSessionTask-Empfaengern.
const SRC =
  'unit t; interface'#13#10 +
  'uses System.Classes;'#13#10 +
  'type'#13#10 +
  '  TBenchThread = class(TThread)'#13#10 +
  '  end;'#13#10 +
  '  TFoo = class'#13#10 +
  '    aBenchThread: TBenchThread;'#13#10 +
  '    procedure Run;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Run;'#13#10 +
  'begin'#13#10 +
  '  aBenchThread.Resume;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkThreadResumeDeprecated) >= 1,
    'echter TThread.Resume-Aufruf (Empfaenger-Typ endet auf Thread) muss feuern');
  finally F.Free; end;
end;
// --- Real-World FP-Audit 2026-07-12, FP-Klasse 'wrong-type-receiver' ---

procedure TTestConcurrencyExt.Resume_InlineVarNonThreadReceiver_NotReported;
// Real-World FP-Audit 2026-07-12 (Alcinoe.HTTP.Worker.pas:519): der Empfaenger
// ist per moderner Inline-var deklariert - 'var LNewTask: NSURLSessionTask :=
// nil;' - und 'LNewTask.Resume' ist der NSURLSessionTask-Aufruf (KEIN
// deprecated TThread.Resume). Vor dem Fix scheiterte der Empfaenger-Typ-
// Resolver an der ':='-Form (das ':' vor dem '=' blockte den Decl-Regex), der
// Typ blieb unbekannt und wurde faelschlich als TThread gemeldet. Jetzt loest
// der Inline-var-Zweig 'NSURLSessionTask' auf -> Nicht-Thread -> unterdrueckt.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  var LNewTask: NSURLSessionTask := nil;'#13#10 +
  '  LNewTask.Resume;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkThreadResumeDeprecated),
    'Inline-var Nicht-Thread-Empfaenger (NSURLSessionTask) darf nicht flaggen');
  finally F.Free; end;
end;

procedure TTestConcurrencyExt.Resume_InlineVarProcessReceiver_NotReported;
// Real-World FP-Audit 2026-07-12 (Schwester-Fall TProcess): ein per Inline-var
// deklarierter TProcess ('var LProc: TProcess := TProcess.Create(nil);') hat
// eine eigene, nicht-deprecatete Resume-Methode. Der Inline-var-Resolver
// liefert 'TProcess' -> Nicht-Thread -> unterdrueckt (kein TThread.Resume-FP).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  var LProc: TProcess := TProcess.Create(nil);'#13#10 +
  '  LProc.Resume;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkThreadResumeDeprecated),
    'Inline-var TProcess-Empfaenger darf nicht flaggen');
  finally F.Free; end;
end;

procedure TTestConcurrencyExt.Resume_InlineVarThreadReceiver_Reported;
// TP-Gegenprobe zum Inline-var-Resolver: loest der Empfaenger-Typ per
// 'var X: <Typ> := ...' auf einen echten TThread-Descendant auf, MUSS der
// deprecated Resume-Aufruf weiter feuern (LooksLikeThreadType-Accept). Sonst
// waere die neue Inline-var-Aufloesung ein Detektions-Verlust.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  var LWorker: TMyWorkerThread := TMyWorkerThread.Create(True);'#13#10 +
  '  LWorker.Resume;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkThreadResumeDeprecated) >= 1,
    'Inline-var TThread-Descendant-Empfaenger (endet auf Thread) muss feuern');
  finally F.Free; end;
end;

// --- Track C (Cross-Unit-TypeIndex) Opt-in, Runde 2 -------------------------
// FP-Klasse 'not-a-tthread' (SCA114): die lexikalische Suffix-Heuristik stuft
// jeden '...thread'-Typnamen als TThread ein. Der repo-weite TTypeIndex loest
// die Vererbungskette auf und beweist Nicht-Thread-Typen (TJvThread=class(
// TComponent)). WICHTIG: Der TypeIndex wird NUR im vollen Pipeline-Weg
// (TAnalysisSession.Run, ssSource -> FindingsViaPipeline) aufgebaut.
// FindingsOf/FindingsOfFile rufen TConcurrencyExtDetector direkt mit
// AContext=nil auf -> CtxTypeIndex ist nil, das Opt-in ist inaktiv (Fallback).

procedure TTestConcurrencyExt.FreeAndNilJvThreadChain_ViaPipeline_Suppressed;
// TMyThread erbt (in-file) von TJvThread=class(TComponent) - der Name endet auf
// 'Thread', der Typ ist aber KEIN TThread. Der Pipeline-Scan baut den TypeIndex
// aus derselben Quelle: TypeKindOf(TMyThread)=Class UND NOT IsDescendantOf(
// tmythread, tthread) -> beweisbar kein Thread -> SCA114 unterdrueckt.
// Das 'FCtl: TThread'-Feld erfuellt nur den 'tthread'-Prefilter-Token, damit
// der Detektor im Pipeline-Lauf ueberhaupt anlaeuft; es wird nie freigegeben.
const SRC =
  'unit t; interface'#13#10 +
  'uses System.Classes;'#13#10 +
  'type'#13#10 +
  '  TJvThread = class(TComponent)'#13#10 +
  '  end;'#13#10 +
  '  TMyThread = class(TJvThread)'#13#10 +
  '  end;'#13#10 +
  '  TFoo = class'#13#10 +
  '    FWorker: TMyThread;'#13#10 +
  '    FCtl: TThread;'#13#10 +
  '    procedure Do_;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Do_;'#13#10 +
  'begin'#13#10 +
  '  FreeAndNil(FWorker);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC, fcLow);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate),
    'TypeIndex beweist TMyThread als Nicht-TThread -> SCA114 unterdrueckt');
  finally F.Free; end;
end;

procedure TTestConcurrencyExt.FreeAndNilJvThreadChain_NoContext_StillReported;
// Gegenprobe/Doku: DIESELBE Quelle ueber FindingsOfFile (AContext=nil, kein
// TypeIndex) -> das Opt-in ist inaktiv, die lexikalische Suffix-Heuristik
// greift wie bisher und meldet den '...thread'-Namen. Belegt, dass der
// FindingsOf/FindingsOfFile-Harness KEINEN TypeIndex baut und das bisherige
// (nil-Fallback-)Verhalten unveraendert bleibt.
const SRC =
  'unit t; interface'#13#10 +
  'uses System.Classes;'#13#10 +
  'type'#13#10 +
  '  TJvThread = class(TComponent)'#13#10 +
  '  end;'#13#10 +
  '  TMyThread = class(TJvThread)'#13#10 +
  '  end;'#13#10 +
  '  TFoo = class'#13#10 +
  '    FWorker: TMyThread;'#13#10 +
  '    FCtl: TThread;'#13#10 +
  '    procedure Do_;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Do_;'#13#10 +
  'begin'#13#10 +
  '  FreeAndNil(FWorker);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate),
    'ohne TypeIndex (AContext=nil) bleibt das lexikalische Verhalten erhalten');
  finally F.Free; end;
end;

procedure TTestConcurrencyExt.FreeAndNilRealThreadDescendant_ViaPipeline_Reported;
// TP-Gegenprobe: ein ECHTER TThread-Nachfahre (TWorker=class(TThread)) muss
// auch mit aktivem TypeIndex Kandidat bleiben - IsDescendantOf(tworker, tthread)
// =True -> IsProvablyNotThread=False -> KEINE Suppression. Sonst waere das
// Opt-in ein Detektions-Verlust.
const SRC =
  'unit t; interface'#13#10 +
  'uses System.Classes;'#13#10 +
  'type'#13#10 +
  '  TWorker = class(TThread)'#13#10 +
  '  end;'#13#10 +
  '  TFoo = class'#13#10 +
  '    FWorker: TWorker;'#13#10 +
  '    procedure Do_;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Do_;'#13#10 +
  'begin'#13#10 +
  '  FreeAndNil(FWorker);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC, fcLow);
  try Assert.IsTrue(TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate) >= 1,
    'echter TThread-Nachfahre bleibt trotz TypeIndex SCA114-Kandidat');
  finally F.Free; end;
end;

procedure TTestConcurrencyExt.FreeAndNilThreadOutOfScopeBase_ViaPipeline_StillReported;
// FN-GUARD (Verify-Concern Runde 2): TSyncThread=class(TCustomSyncBase), wobei
// TCustomSyncBase NICHT im Scan-Scope deklariert ist (koennte dort ein TThread
// sein). Die Elternkette bricht bei tcustomsyncbase ab -> erreicht KEINEN
// bekannten Nicht-Thread-Root -> IsProvablyNotThread=False -> KEINE Suppression,
// der echte Fund bleibt. (Mit der alten 'not IsDescendantOf(x,tthread)'-Logik
// waere das faelschlich suppressed worden = TP-Verlust.) FCtl:TThread nur als
// Prefilter-Token 'tthread'.
const SRC =
  'unit t; interface'#13#10 +
  'uses System.Classes;'#13#10 +
  'type'#13#10 +
  '  TSyncThread = class(TCustomSyncBase)'#13#10 +
  '  end;'#13#10 +
  '  TFoo = class'#13#10 +
  '    FSync: TSyncThread;'#13#10 +
  '    FCtl: TThread;'#13#10 +
  '    procedure Do_;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Do_;'#13#10 +
  'begin'#13#10 +
  '  FreeAndNil(FSync);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC, fcLow);
  try Assert.IsTrue(TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate) >= 1,
    'Thread-Subklasse mit out-of-scope-Basis bleibt Fund (Kette erreicht keinen Root)');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConcurrencyExt);

end.
