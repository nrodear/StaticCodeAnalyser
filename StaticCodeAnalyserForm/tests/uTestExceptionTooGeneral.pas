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
    // 30%-Audit 2026-07-31 / User-Entscheidung 2026-08-01: Semantik
    // schaerfen. Catch-all an einer ABI-Grenze ist Pflicht, kein Smell.
    [Test] procedure CdeclDispatcherForwardingExc_NotReported;
    [Test] procedure SafecallDispatcherForwardingExc_NotReported;
    [Test] procedure CdeclHandlerThatActs_NotReported;
    [Test] procedure CdeclHandlerThatIsEmpty_StillReported;
    [Test] procedure PascalHandlerForwardingExc_StillReported;
    // FP-Audit Stufe 2 (2026-08-16): die Aufrufkonvention steht nur an der
    // DEKLARATION - der Implementierungs-Kopf traegt sie nicht.
    [Test] procedure AbiFromClassDeclaration_NotReported;
    [Test] procedure DeclWithoutAbiForwardingExc_StillReported;
    [Test] procedure AmbiguousMethodNameAcrossClasses_StillReported;
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

procedure TTestExceptionTooGeneral.CdeclDispatcherForwardingExc_NotReported;
// Korpus-Beleg Firebird.pas (4-6x vendored, 14 der 16 Sample-FPs): ein
// generierter cdecl-Dispatcher MUSS jede Exception fangen und in einen
// Statuscode wandeln - eine Delphi-Exception darf nicht in den C-Code
// propagieren. 'prefer a specific subclass' waere dort ein Bug.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure serverModeDispatcher(this: Pointer); cdecl;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    DoWork;'#13#10 +
  '  except'#13#10 +
  '    on e: Exception do FbException.catchException(nil, e);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkExceptionTooGeneral),
    'Catch-all an der C-ABI-Grenze ist Pflicht, kein Smell');
  finally F.Free; end;
end;

procedure TTestExceptionTooGeneral.SafecallDispatcherForwardingExc_NotReported;
// safecall gehoert zur selben Klasse - dort baut der Compiler den Handler
// sogar selbst, ein expliziter ist die dokumentierte Ergaenzung.
const SRC =
  'unit t; implementation'#13#10 +
  'function GetValue(out V: Integer): HResult; safecall;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    V := Compute;'#13#10 +
  '  except'#13#10 +
  '    on E: Exception do Result := ToHResult(E);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkExceptionTooGeneral));
  finally F.Free; end;
end;

procedure TTestExceptionTooGeneral.CdeclHandlerThatActs_NotReported;
// UMGEDREHT am 2026-08-21. Vorher hielt dieser Test fest, die
// Aufrufkonvention allein reiche nicht - der Handler muesse E an einen
// Konverter durchreichen. Das widersprach dem Kommentar an
// RoutineHasForeignAbi, der den Catch-all an einer fremden Konvention
// seit jeher "Pflicht" nennt: eine Delphi-Exception darf nicht in
// fremden Code propagieren.
//
// Aufgeloest zugunsten des Kommentars. Wer an dieser Grenze faengt und
// ETWAS TUT - hier einen Zaehler fuehren -, erfuellt seine Pflicht.
// Die Gegenprobe steht direkt darunter.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Callback(this: Pointer); cdecl;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    DoWork;'#13#10 +
  '  except'#13#10 +
  '    on E: Exception do Counter := Counter + 1;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkExceptionTooGeneral),
    'an der ABI-Grenze ist der breite Fang Pflicht, sobald der Handler handelt');
  finally F.Free; end;
end;

procedure TTestExceptionTooGeneral.CdeclHandlerThatIsEmpty_StillReported;
// DIE LINIE. Wer faengt und NICHTS tut, verschluckt - auch an der
// ABI-Grenze. Ohne diesen Test waere die Lockerung oben ein Freibrief
// fuer jeden cdecl-Handler.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Callback(this: Pointer); cdecl;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    DoWork;'#13#10 +
  '  except'#13#10 +
  '    on E: Exception do ;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkExceptionTooGeneral) >= 1,
    'ein leerer Handler bleibt ein Swallow, auch an der ABI-Grenze');
  finally F.Free; end;
end;

procedure TTestExceptionTooGeneral.PascalHandlerForwardingExc_StillReported;
// WAECHTER der anderen Richtung: das Durchreichen von E allein reicht auch
// nicht. Ohne fremde Aufrufkonvention ist es eine gewoehnliche Routine, und
// 'HandleError(E)' ist genau das Log-und-Weiter-Muster der Regel.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    DoWork;'#13#10 +
  '  except'#13#10 +
  '    on E: Exception do HandleError(E);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkExceptionTooGeneral),
    'Ohne ABI-Grenze bleibt das Durchreichen ein gewoehnlicher Handler');
  finally F.Free; end;
end;

// ============================================================
// FP-Audit Stufe 2 (2026-08-16): Delphi verlangt cdecl/stdcall/safecall nur
// an der DEKLARATION. python4delphi & Co. schreiben sie ausschliesslich dort,
// der Implementierungs-Kopf traegt sie nicht - das ABI-Gate lief dort leer.
// ============================================================

procedure TTestExceptionTooGeneral.AbiFromClassDeclaration_NotReported;
// cdecl steht in der Klassen-Deklaration, der Impl-Kopf hat sie nicht.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TWrapper = class'#13#10 +
  '  public'#13#10 +
  '    function Do_FieldByName(args: PPyObject): PPyObject; cdecl;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'function TWrapper.Do_FieldByName(args: PPyObject): PPyObject;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    Result := Fetch(args);'#13#10 +
  '  except'#13#10 +
  '    on E: Exception do RaiseDBError(E);'#13#10 +
  '  end;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkExceptionTooGeneral),
    'cdecl an der Deklaration ist dieselbe ABI-Grenze wie am Impl-Kopf');
  finally F.Free; end;
end;

procedure TTestExceptionTooGeneral.DeclWithoutAbiForwardingExc_StillReported;
// WAECHTER: ohne Direktive an der Deklaration bleibt es eine gewoehnliche
// Methode - das Durchreichen von E allein oeffnet kein Tor.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TPlainDataset = class'#13#10 +
  '  public'#13#10 +
  '    procedure DoUnPrepare(Cmd: TObject);'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TPlainDataset.DoUnPrepare(Cmd: TObject);'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    Cmd.Close;'#13#10 +
  '  except'#13#10 +
  '    on E: Exception do RaiseDBError(E);'#13#10 +
  '  end;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkExceptionTooGeneral),
    'ohne Aufrufkonvention bleibt der Handler ein Fund');
  finally F.Free; end;
end;

procedure TTestExceptionTooGeneral.AmbiguousMethodNameAcrossClasses_StillReported;
// Der Bare-Name-Fallback darf NICHT ueber Klassengrenzen wirken: zwei Klassen
// mit gleichnamiger Methode, nur eine davon cdecl - die andere bleibt Fund.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TAbi = class'#13#10 +
  '  public'#13#10 +
  '    procedure Handle; cdecl;'#13#10 +
  '  end;'#13#10 +
  '  TPlain = class'#13#10 +
  '  public'#13#10 +
  '    procedure Handle;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TPlain.Handle;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    Step;'#13#10 +
  '  except'#13#10 +
  '    on E: Exception do Translate(E);'#13#10 +
  '  end;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkExceptionTooGeneral),
    'gleichnamige Methode einer anderen Klasse vererbt keine Aufrufkonvention');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestExceptionTooGeneral);

end.
