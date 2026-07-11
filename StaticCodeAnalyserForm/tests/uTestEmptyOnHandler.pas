unit uTestEmptyOnHandler;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEmptyOnHandler = class
  public
    [Test] procedure OnHandlerWithSemicolon_Reported;
    [Test] procedure OnHandlerWithEmptyBeginEnd_Reported;
    [Test] procedure OnHandlerWithBody_NotReported;
    [Test] procedure Finding_KindAndSeverity;
    // --- Real-World FP-Audit Runde 4 (2026-07-11) Regression ---
    [Test] procedure OnEAbortHandler_NotReported;
    [Test] procedure OnHandlerBodyStartingWithEnd_NotReported;
    [Test] procedure EmptyTypedHandler_StillReported_AfterGuards;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestEmptyOnHandler.OnHandlerWithSemicolon_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    DoStuff;'#13#10 +
  '  except'#13#10 +
  '    on E: EDatabaseError do ;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkEmptyOnHandler) >= 1);
  finally F.Free; end;
end;

procedure TTestEmptyOnHandler.OnHandlerWithEmptyBeginEnd_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    DoStuff;'#13#10 +
  '  except'#13#10 +
  '    on E: EFileNotFound do'#13#10 +
  '    begin'#13#10 +
  '    end;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkEmptyOnHandler) >= 1);
  finally F.Free; end;
end;

procedure TTestEmptyOnHandler.OnHandlerWithBody_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    DoStuff;'#13#10 +
  '  except'#13#10 +
  '    on E: EDatabaseError do'#13#10 +
  '      Logger.Error(E.Message);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyOnHandler));
  finally F.Free; end;
end;

procedure TTestEmptyOnHandler.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try DoStuff; except on E: EX do ; end;'#13#10 +
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
      if Fnd.Kind = fkEmptyOnHandler then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkEmptyOnHandler finding expected');
    Assert.AreEqual(lsWarning, Hit.Severity);
  finally F.Free; end;
end;


// --- Real-World FP-Audit Runde 4 (2026-07-11) Regression ---

procedure TTestEmptyOnHandler.OnEAbortHandler_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    DoStuff;'#13#10 +
  '  except'#13#10 +
  '    on EAbort do ;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  // FP-Regression (eabort-idiomatic-cancel): stilles Schlucken von EAbort ist
  // das bestimmungsgemaesse VCL-Cancel-Signal, kein Silent-Failure-Bug.
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyOnHandler),
    'on EAbort do ; ist idiomatisches VCL-Cancel - kein Fund erwartet');
  finally F.Free; end;
end;

procedure TTestEmptyOnHandler.OnHandlerBodyStartingWithEnd_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var EndLogin: Boolean;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    DoStuff;'#13#10 +
  '  except'#13#10 +
  '    on E: EDbEngineError do'#13#10 +
  '    begin'#13#10 +
  '      EndLogin := True;'#13#10 +
  '    end;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  // FP-Regression (end-prefixed-identifier): Body beginnt mit dem Identifier
  // EndLogin - ohne Wortgrenze nach `end` matchte begin\s*end das `End` aus
  // `EndLogin` und las den nicht-leeren Block als leer.
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyOnHandler),
    'begin EndLogin ist kein leerer Block - Wortgrenze nach end noetig');
  finally F.Free; end;
end;

procedure TTestEmptyOnHandler.EmptyTypedHandler_StillReported_AfterGuards;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var EndLogin: Boolean;'#13#10 +
  'begin'#13#10 +
  '  EndLogin := False;'#13#10 +
  '  try'#13#10 +
  '    DoStuff;'#13#10 +
  '  except'#13#10 +
  '    on E: EDatabaseError do'#13#10 +
  '    begin'#13#10 +
  '    end;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  // TP-Guard: echter leerer typisierter Handler (Nicht-EAbort, echtes begin/end)
  // muss trotz EAbort-Allowlist UND Wortgrenze-Fix weiter feuern. Die EndLogin-
  // Variable ist bewusst vorhanden, um zu beweisen dass der Wortgrenze-Guard nur
  // End-praefigierte Body-Anfaenge, nicht echte leere Bloecke unterdrueckt.
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkEmptyOnHandler) >= 1,
    'echter leerer EDatabaseError-Handler muss weiter gemeldet werden');
  finally F.Free; end;
end;
initialization
  TDUnitX.RegisterTestFixture(TTestEmptyOnHandler);

end.
