unit uTestBaselineResolve;

// Tests fuer TBaseline.ResolveBaselinePath - die .sca-Standardort-
// Aufloesung (Konzept_BaselineSca 2026-08-08, Inkrement 1).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestBaselineResolve = class
  private
    FTmp: string;
    procedure MakeFile(const RelPath: string);
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure Group_FoundBesideGroupproj;
    [Test] procedure Project_FoundBesideDproj;
    [Test] procedure Project_FallsBackToParentSca;
    [Test] procedure PathMode_FoundUnderRoot;
    [Test] procedure NotFound_ReturnsEmpty_AndListsProbedPaths;
    [Test] procedure Project_ProbesTwoCandidates;

    // IsBaselineFile - Formatpruefung vor dem Filtern (Audit 2026-08-08:
    // ein verwechselter SARIF-Report filterte still nichts).
    [Test] procedure IsBaseline_AcceptsObjectWithFindings;
    [Test] procedure IsBaseline_AcceptsBareArray_LegacyFormat;
    [Test] procedure IsBaseline_RejectsSarifReport_NamesIt;
    [Test] procedure IsBaseline_RejectsNonJson;
    [Test] procedure IsBaseline_RejectsMissingFile;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  uBaseline;

const
  PROJ_DPROJ = 'ProjA\ProjA.dproj';   // 3x gebraucht (DuplicateString)

procedure TTestBaselineResolve.Setup;
begin
  FTmp := TPath.Combine(TPath.GetTempPath,
    'sca_bl_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FTmp);
end;

procedure TTestBaselineResolve.TearDown;
begin
  if TDirectory.Exists(FTmp) then
    TDirectory.Delete(FTmp, True);
end;

procedure TTestBaselineResolve.MakeFile(const RelPath: string);
var
  Full: string;
begin
  Full := TPath.Combine(FTmp, RelPath);
  TDirectory.CreateDirectory(ExtractFilePath(Full));
  TFile.WriteAllText(Full, '{"findings":[]}');
end;

procedure TTestBaselineResolve.Group_FoundBesideGroupproj;
var
  R: string;
begin
  MakeFile('.sca\MyGroup.baseline.json');
  R := TBaseline.ResolveBaselinePath(
    TPath.Combine(FTmp, 'MyGroup.groupproj'), '');
  Assert.AreEqual(
    TPath.Combine(FTmp, '.sca\MyGroup.baseline.json'), R);
end;

procedure TTestBaselineResolve.Project_FoundBesideDproj;
var
  R: string;
begin
  MakeFile('ProjA\.sca\ProjA.baseline.json');
  R := TBaseline.ResolveBaselinePath(
    TPath.Combine(FTmp, PROJ_DPROJ), '');
  Assert.AreEqual(
    TPath.Combine(FTmp, 'ProjA\.sca\ProjA.baseline.json'), R);
end;

procedure TTestBaselineResolve.Project_FallsBackToParentSca;
// Projekt liegt eine Ebene unter der Gruppe; die zentrale Gruppen-.sca
// traegt die Projekt-Baseline.
var
  R: string;
begin
  MakeFile('.sca\ProjA.baseline.json');
  R := TBaseline.ResolveBaselinePath(
    TPath.Combine(FTmp, PROJ_DPROJ), '');
  Assert.AreEqual(
    TPath.Combine(FTmp, '.sca\ProjA.baseline.json'), R);
end;

procedure TTestBaselineResolve.PathMode_FoundUnderRoot;
var
  R: string;
begin
  MakeFile('.sca\sca.baseline.json');
  R := TBaseline.ResolveBaselinePath('', FTmp);
  Assert.AreEqual(
    TPath.Combine(FTmp, '.sca\sca.baseline.json'), R);
end;

procedure TTestBaselineResolve.NotFound_ReturnsEmpty_AndListsProbedPaths;
var
  R: string;
  Probed: TStringList;
begin
  Probed := TStringList.Create;
  try
    R := TBaseline.ResolveBaselinePath('', FTmp, Probed);
    Assert.AreEqual('', R);
    Assert.AreEqual(1, Probed.Count,
      'Pfad-Modus prueft genau einen Kandidaten');
    Assert.Contains(Probed[0], '.sca');
  finally
    Probed.Free;
  end;
end;

procedure TTestBaselineResolve.Project_ProbesTwoCandidates;
// .dproj ohne Baseline: Projekt-.sca UND Eltern-.sca werden gelistet -
// das traegt die Fehlermeldung des harten CLI-Fehlers (Inkrement 2).
var
  R: string;
  Probed: TStringList;
begin
  Probed := TStringList.Create;
  try
    R := TBaseline.ResolveBaselinePath(
      TPath.Combine(FTmp, PROJ_DPROJ), '', Probed);
    Assert.AreEqual('', R);
    Assert.AreEqual(2, Probed.Count,
      'dproj prueft Projekt- und Eltern-.sca');
  finally
    Probed.Free;
  end;
end;

{ ---- IsBaselineFile ----
  Apply ist bewusst fehlertolerant und liefert bei allem Unbekannten 0.
  Fuer eine VERWECHSELTE Datei ist das falsch: ein versehentlich
  uebergebener SARIF-Report filterte nichts, und das Gate meldete den
  kompletten Bestand als neu (Audit 2026-08-08). }

procedure TTestBaselineResolve.IsBaseline_AcceptsObjectWithFindings;
var
  Fn, Reason: string;
begin
  Fn := TPath.Combine(FTmp, 'ok.json');
  TFile.WriteAllText(Fn, '{"version":"1","findings":[]}');
  Assert.IsTrue(TBaseline.IsBaselineFile(Fn, Reason), Reason);
end;

procedure TTestBaselineResolve.IsBaseline_AcceptsBareArray_LegacyFormat;
var
  Fn, Reason: string;
begin
  Fn := TPath.Combine(FTmp, 'legacy.json');
  TFile.WriteAllText(Fn, '["abc123"]');
  Assert.IsTrue(TBaseline.IsBaselineFile(Fn, Reason), Reason);
end;

procedure TTestBaselineResolve.IsBaseline_RejectsSarifReport_NamesIt;
var
  Fn, Reason: string;
begin
  Fn := TPath.Combine(FTmp, 'report.sarif');
  TFile.WriteAllText(Fn,
    '{"version":"2.1.0","runs":[{"results":[]}]}');
  Assert.IsFalse(TBaseline.IsBaselineFile(Fn, Reason));
  Assert.Contains(Reason, 'SARIF',
    'die Begruendung muss die Verwechslung beim Namen nennen');
end;

procedure TTestBaselineResolve.IsBaseline_RejectsNonJson;
var
  Fn, Reason: string;
begin
  Fn := TPath.Combine(FTmp, 'garbage.json');
  TFile.WriteAllText(Fn, 'this is not json');
  Assert.IsFalse(TBaseline.IsBaselineFile(Fn, Reason));
  Assert.Contains(Reason, 'JSON');
end;

procedure TTestBaselineResolve.IsBaseline_RejectsMissingFile;
var
  Reason: string;
begin
  Assert.IsFalse(TBaseline.IsBaselineFile(
    TPath.Combine(FTmp, 'gibtsnicht.json'), Reason));
  Assert.Contains(Reason, 'not found');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestBaselineResolve);

end.
