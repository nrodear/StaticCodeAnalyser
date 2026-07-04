unit uTestPathOverrides;

// Audit 2026-07 Stufe 3: TPathOverrides.ApplyToFindings ist fester
// Pipeline-Schritt (nach Suppression, vor ConfidenceFilter), hatte aber
// NULL Testabdeckung - ein Glob-/Action-Regressions-Bug haette still die
// Produktions-Ausgabe veraendert. Isolations-Tests via AddRule/Clear.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uPathOverrides;

type
  [TestFixture]
  TTestPathOverrides = class
  private
    function MakeFinding(const AFile: string; AKind: TFindingKind;
      ASev: TLeakSeverity): TLeakFinding;
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure DropAll_RemovesOnlyMatchingPath;
    [Test] procedure DropKind_LeavesOtherKindsOnSamePath;
    [Test] procedure SeverityHint_DowngradesMatchingKind;
    [Test] procedure NoMatch_ListUnchanged;
    [Test] procedure Idempotent_SecondApplyChangesNothing;
  end;

implementation

function TTestPathOverrides.MakeFinding(const AFile: string;
  AKind: TFindingKind; ASev: TLeakSeverity): TLeakFinding;
begin
  Result := TLeakFinding.Create;
  Result.FileName   := AFile;
  Result.MethodName := '';
  Result.LineNumber := '1';
  Result.MissingVar := 'x';
  Result.SetKind(AKind);
  Result.Severity   := ASev;
end;

procedure TTestPathOverrides.Setup;
begin
  TPathOverrides.Clear;
end;

procedure TTestPathOverrides.TearDown;
// Regeln nie in andere Fixtures leaken (globaler Rule-State).
begin
  TPathOverrides.Clear;
end;

procedure TTestPathOverrides.DropAll_RemovesOnlyMatchingPath;
var
  L: TObjectList<TLeakFinding>;
begin
  TPathOverrides.AddRule('tests/*.pas', poaDrop, [], True);
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding('tests\foo.pas', fkMagicNumber, lsHint));
    L.Add(MakeFinding('src\foo.pas',   fkMagicNumber, lsHint));
    TPathOverrides.ApplyToFindings(L);
    Assert.AreEqual<Integer>(1, L.Count, 'nur der tests\-Fund faellt');
    Assert.AreEqual('src\foo.pas', L[0].FileName);
  finally
    L.Free;
  end;
end;

procedure TTestPathOverrides.DropKind_LeavesOtherKindsOnSamePath;
var
  L: TObjectList<TLeakFinding>;
begin
  TPathOverrides.AddRule('gen/*.pas', poaDrop, [fkMagicNumber], False);
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding('gen\a.pas', fkMagicNumber,   lsHint));
    L.Add(MakeFinding('gen\a.pas', fkTooLongLine,   lsHint));
    TPathOverrides.ApplyToFindings(L);
    Assert.AreEqual<Integer>(1, L.Count, 'nur der gelistete Kind faellt');
    Assert.IsTrue(L[0].Kind = fkTooLongLine, 'anderer Kind bleibt');
  finally
    L.Free;
  end;
end;

procedure TTestPathOverrides.SeverityHint_DowngradesMatchingKind;
var
  L: TObjectList<TLeakFinding>;
begin
  TPathOverrides.AddRule('legacy/*.pas', poaSeverityHint, [], True);
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding('legacy\old.pas', fkMagicNumber, lsError));
    TPathOverrides.ApplyToFindings(L);
    Assert.AreEqual<Integer>(1, L.Count, 'Downgrade droppt nicht');
    Assert.IsTrue(L[0].Severity = lsHint, 'Severity auf Hint gedrueckt');
  finally
    L.Free;
  end;
end;

procedure TTestPathOverrides.NoMatch_ListUnchanged;
var
  L: TObjectList<TLeakFinding>;
begin
  TPathOverrides.AddRule('tests/*.pas', poaDrop, [], True);
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding('src\main.pas', fkMagicNumber, lsWarning));
    TPathOverrides.ApplyToFindings(L);
    Assert.AreEqual<Integer>(1, L.Count);
    Assert.IsTrue(L[0].Severity = lsWarning, 'unveraendert ohne Match');
  finally
    L.Free;
  end;
end;

procedure TTestPathOverrides.Idempotent_SecondApplyChangesNothing;
var
  L: TObjectList<TLeakFinding>;
begin
  TPathOverrides.AddRule('tests/*.pas', poaDrop, [], True);
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding('tests\t.pas', fkMagicNumber, lsHint));
    L.Add(MakeFinding('src\s.pas',   fkMagicNumber, lsHint));
    TPathOverrides.ApplyToFindings(L);
    TPathOverrides.ApplyToFindings(L);
    Assert.AreEqual<Integer>(1, L.Count, 'zweiter Apply ist No-op');
  finally
    L.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPathOverrides);

end.
