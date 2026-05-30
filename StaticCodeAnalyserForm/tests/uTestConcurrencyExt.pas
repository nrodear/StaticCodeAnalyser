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
    // Type-Filter: nur feuern wenn Identifier-Typ nach TThread aussieht.
    [Test] procedure FreeAndNilObjectList_NotReported;
    [Test] procedure FreeAndNilStringList_NotReported;
    [Test] procedure FreeAndNilThreadTyped_Reported;
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
  try Assert.IsTrue(TFindingHelper.Count(F, fkThreadResumeDeprecated) >= 1);
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkThreadResumeDeprecated));
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkThreadResumeDeprecated));
  finally F.Free; end;
end;

procedure TTestConcurrencyExt.FreeAndNilWithoutTerminate_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  FreeAndNil(FWorker);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate) >= 1);
  finally F.Free; end;
end;

procedure TTestConcurrencyExt.FreeAndNilWithTerminateAndWait_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  FWorker.Terminate;'#13#10 +
  '  FWorker.WaitFor;'#13#10 +
  '  FreeAndNil(FWorker);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate));
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate));
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate));
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
  try Assert.IsTrue(TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate) >= 1);
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate));
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
  try Assert.IsTrue(TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate) >= 1);
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate));
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate),
        'FreeAndNil in String-Literal darf den Detector nicht ausloesen');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConcurrencyExt);

end.
