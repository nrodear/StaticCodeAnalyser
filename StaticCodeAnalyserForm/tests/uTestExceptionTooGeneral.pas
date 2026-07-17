unit uTestExceptionTooGeneral;

// Tests fuer den TExceptionTooGeneralDetector.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestExceptionTooGeneral = class
  public
    [Test] procedure OnException_Reported;
    [Test] procedure OnSpecificException_NotReported;
    [Test] procedure MixedHandlers_OnlyExceptionFlagged;
    [Test] procedure BareExceptBlock_NotReported;
    [Test] procedure Finding_KindAndSeverity;
    // --- Real-World FP-Audit Runde 4 (2026-07-11) Regression ---
    [Test] procedure ReraiseAfterCleanup_NotReported;
    [Test] procedure ConditionalReraiseViaHelper_NotReported;
    [Test] procedure TranslateToNewException_StillReported;
    // Core-Audit 2026-07-17 (SCA132): praefigierter Logger (ALLog/WriteLog)
    // + Leave = legitimer Top-Level-Handler, kein Finding.
    [Test] procedure PrefixedLoggerWithLeave_NotReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestExceptionTooGeneral.OnException_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    Bar;'#13#10 +
  '  except'#13#10 +
  '    on E: Exception do Log(E.Message);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkExceptionTooGeneral));
  finally F.Free; end;
end;

procedure TTestExceptionTooGeneral.OnSpecificException_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    Bar;'#13#10 +
  '  except'#13#10 +
  '    on E: EConvertError do Log(E.Message);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkExceptionTooGeneral));
  finally F.Free; end;
end;

procedure TTestExceptionTooGeneral.MixedHandlers_OnlyExceptionFlagged;
// Spezifischer Handler zuerst, dann generischer Fallback - der generische
// soll geflaggt werden, der spezifische nicht.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    Bar;'#13#10 +
  '  except'#13#10 +
  '    on E: EConvertError do Handle1(E);'#13#10 +
  '    on E: Exception do Handle2(E);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkExceptionTooGeneral));
  finally F.Free; end;
end;

procedure TTestExceptionTooGeneral.BareExceptBlock_NotReported;
// except ohne on - faengt zwar auch alles, ist aber Top-Level-Crash-Handler-
// Pattern und liegt ausserhalb des Scopes dieses Detektors.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    Bar;'#13#10 +
  '  except'#13#10 +
  '    Log(''crash'');'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkExceptionTooGeneral));
  finally F.Free; end;
end;

procedure TTestExceptionTooGeneral.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try Bar; except on E: Exception do; end;'#13#10 +
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
      if Fnd.Kind = fkExceptionTooGeneral then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkExceptionTooGeneral finding expected');
    Assert.AreEqual(fkExceptionTooGeneral, Hit.Kind);
    Assert.AreEqual(lsWarning,             Hit.Severity);
  finally F.Free; end;
end;


// --- Real-World FP-Audit Runde 4 (2026-07-11) Regression ---

procedure TTestExceptionTooGeneral.ReraiseAfterCleanup_NotReported;
// FP-Regression (reraise-cleanup): breiter Catch NUR fuer Fehler-Pfad-
// Cleanup (Rollback), danach unbedingtes bare `raise;`. Der Handler gibt
// die Original-Exception weiter und verschluckt nichts -> kein Finding.
// Geerdet in Alcinoe.Sqlite3.Client.pas:2022 / Alcinoe.MemCached.Client.pas:2275.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    DoWork;'#13#10 +
  '  except'#13#10 +
  '    on E: Exception do'#13#10 +
  '    begin'#13#10 +
  '      Rollback;'#13#10 +
  '      raise;'#13#10 +
  '    end;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkExceptionTooGeneral));
  finally F.Free; end;
end;

procedure TTestExceptionTooGeneral.ConditionalReraiseViaHelper_NotReported;
// FP-Regression (log-reraise-helper): `if Helper(...) then raise;` - der
// bare Re-Raise steckt im then-Zweig eines if IM Handler-Subtree. Auch das
// gibt die Exception weiter (kein Swallow) -> kein Finding, UNABHAENGIG
// davon dass der Helper-Name keinem Log-Muster entspricht. Geerdet im
// CEF4Delphi-WndProc-Idiom (uMiniBrowser.pas:1820, uSimpleFMXBrowser.pas:301 u.a.).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    DoWork;'#13#10 +
  '  except'#13#10 +
  '    on E: Exception do'#13#10 +
  '      if CustomExceptionHandler(''Foo'', E) then raise;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkExceptionTooGeneral));
  finally F.Free; end;
end;

procedure TTestExceptionTooGeneral.TranslateToNewException_StillReported;
// TP-Guard: breiter Catch der die Original-Exception NICHT weitergibt,
// sondern in einen neuen Typ uebersetzt (`raise ENew.Create(...)`). Faengt
// weiterhin EAbort/EOutOfMemory breit ab und verliert Original-Typ und
// -Stack -> weiterhin ein Finding. Stellt sicher, dass der neue bare-raise-
// Guard NUR das nackte `raise;` (nkRaise.Name='raise') unterdrueckt und
// nicht jeden nkRaise. Geerdet in Audit-TP 'Uebersetzung in Error-Callbacks'.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    DoWork;'#13#10 +
  '  except'#13#10 +
  '    on E: Exception do'#13#10 +
  '      raise EMyError.Create(E.Message);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkExceptionTooGeneral));
  finally F.Free; end;
end;
procedure TTestExceptionTooGeneral.PrefixedLoggerWithLeave_NotReported;
// Core-Audit 2026-07-17 (SCA132): ein Top-Level-Handler, der ueber einen
// PRAEFIGIERTEN Logger loggt (Alcinoe 'ALLog', auch 'WriteLog'/'AppLog') UND
// beendet (Result-Zuweisung), ist legitim. Vor dem CallIdLooksLikeLogger-Guard
// erkannte HasLog nur StartsWith('log') und verpasste 'ALLog' -> der Handler
// wurde faelschlich als 'zu generisch' gemeldet. Geerdet in
// Alcinoe.FMX.Dynamic.Controls.pas:1652 (ALLog(...) + Result := ...).
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo: Boolean;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    Result := DoWork;'#13#10 +
  '  except'#13#10 +
  '    on E: Exception do'#13#10 +
  '    begin'#13#10 +
  '      ALLog(''Foo'', E);'#13#10 +
  '      Result := False;'#13#10 +
  '    end;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkExceptionTooGeneral),
    'praefigierter Logger (ALLog) + Leave ist ein legitimer Top-Level-Handler');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestExceptionTooGeneral);

end.
