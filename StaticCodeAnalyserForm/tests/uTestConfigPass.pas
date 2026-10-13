unit uTestConfigPass;

// SCA201-Wege der Engine (Review Bereich C Engine-Kern, Major 4,
// 2026-10-14): das Gate ConfigPassActive (Profil UND Mindestschwere), eine
// Dateiliste nur aus .ini mit IndexRoot, SCA201 abgeschaltet, eine
// verschwundene und eine zu grosse .ini. Diese Entscheidungen in
// uStaticAnalyzer2 (2683-2689) waren schon einmal falsch (b32b3196) und
// hatten keinen Test.
//
// KEIN rekursiver Pfad (AnalyzeLeaksRecursive): im residenten Testprozess
// tabu (uTestEngineApi, Unit-Kopf). "Ordner nur mit .ini" laeuft hier als
// Liste nur aus .ini - denselben Konfigurations-Durchlauf faehrt der
// rekursive Pfad nach seiner Sammlung. Der Fehlerpfad von
// ScanConfigFileGuarded (Ausnahme im Detektor) ist ohne Injektion nicht
// erreichbar und bleibt der CLI-A/B ueberlassen.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12;

type
  [TestFixture]
  TTestConfigPass = class
  strict private
    FDir      : string;
    FAltKinds : TFindingKinds;
    FAltSev   : TLeakSeverity;
    FAltMax   : Integer;
    function Schreibe(const AName, AText: string): string;
    function Zaehle(L: TObjectList<TLeakFinding>; K: TFindingKind): Integer;
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure ConfigPassActive_FollowsProfileAndSeverity;
    [Test] procedure FileListOnlyIni_WithIndexRoot_ReportsSca201_NoReadError;
    [Test] procedure FileListOnlyIni_Sca201Disabled_NoFindings_NoReadError;
    [Test] procedure SingleIni_VanishedFile_NoReadError;
    [Test] procedure SingleIni_Oversized_Skipped;
  end;

implementation

uses
  System.Classes, System.IOUtils,
  uStaticAnalyzer2;

const
  INI_MIT_IP = '[Database]'#13#10'Server=10.20.30.40'#13#10;

function TTestConfigPass.Schreibe(const AName, AText: string): string;
begin
  Result := TPath.Combine(FDir, AName);
  TFile.WriteAllText(Result, AText, TEncoding.ASCII);
end;

function TTestConfigPass.Zaehle(L: TObjectList<TLeakFinding>;
  K: TFindingKind): Integer;
var
  F : TLeakFinding;
begin
  Result := 0;
  for F in L do
    if F.Kind = K then Inc(Result);
end;

procedure TTestConfigPass.Setup;
begin
  // Prozessweite Schalter sichern - der Testprozess ist resident.
  FAltKinds := uSCAConsts.DetectorEnabledKinds;
  FAltSev   := uSCAConsts.DetectorMinSeverity;
  FAltMax   := uSCAConsts.DetectorMaxFileBytes;
  uSCAConsts.DetectorEnabledKinds := [];
  uSCAConsts.DetectorMinSeverity  := lsHint;
  // Kein Segment, das das Testpfad-Gate (test/tests/fixtures) traefe.
  FDir := TPath.Combine(TPath.GetTempPath, 'sca_cfgpass_' +
    TGuid.NewGuid.ToString.Replace('{', '').Replace('}', ''));
  TDirectory.CreateDirectory(FDir);
end;

procedure TTestConfigPass.TearDown;
begin
  uSCAConsts.DetectorEnabledKinds := FAltKinds;
  uSCAConsts.DetectorMinSeverity  := FAltSev;
  uSCAConsts.DetectorMaxFileBytes := FAltMax;
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
end;

procedure TTestConfigPass.ConfigPassActive_FollowsProfileAndSeverity;
// SCA201 ist ein Hint: unter der Schwelle Warning oder ohne SCA201 im
// Profil laeuft kein Konfigurations-Durchlauf.
begin
  Assert.IsTrue(TStaticAnalyzer2.ConfigPassActive,
    'alle Regeln, Schwelle Hint');
  uSCAConsts.DetectorMinSeverity := lsWarning;
  Assert.IsFalse(TStaticAnalyzer2.ConfigPassActive,
    'Schwelle Warning schliesst den Hint SCA201 aus');
  uSCAConsts.DetectorMinSeverity := lsHint;
  uSCAConsts.DetectorEnabledKinds := [fkMemoryLeak];
  Assert.IsFalse(TStaticAnalyzer2.ConfigPassActive,
    'Profil ohne SCA201');
  uSCAConsts.DetectorEnabledKinds := [fkMemoryLeak, fkHardcodedIpInConfig];
  Assert.IsTrue(TStaticAnalyzer2.ConfigPassActive, 'Profil mit SCA201');
end;

procedure TTestConfigPass.FileListOnlyIni_WithIndexRoot_ReportsSca201_NoReadError;
// Eine Liste ohne einzige .pas: kein Projektindex, kein Lesefehler, der
// Konfigurations-Durchlauf liefert den SCA201-Fund.
var
  Dateien : TStringList;
  Funde   : TObjectList<TLeakFinding>;
begin
  Dateien := TStringList.Create;
  try
    Dateien.Add(Schreibe('App.ini', INI_MIT_IP));
    Funde := TStaticAnalyzer2.AnalyzeLeaksFromList(Dateien, nil, False, FDir);
    try
      Assert.AreEqual<Integer>(0, Zaehle(Funde, fkFileReadError),
        'weder "Keine Dateien" noch ein Index-Fehler');
      Assert.AreEqual<Integer>(1, Zaehle(Funde, fkHardcodedIpInConfig));
      Assert.AreEqual<Integer>(1, Funde.Count, 'nur der SCA201-Fund');
    finally
      Funde.Free;
    end;
  finally
    Dateien.Free;
  end;
end;

procedure TTestConfigPass.FileListOnlyIni_Sca201Disabled_NoFindings_NoReadError;
var
  Dateien : TStringList;
  Funde   : TObjectList<TLeakFinding>;
begin
  uSCAConsts.DetectorEnabledKinds := [fkMemoryLeak];
  Dateien := TStringList.Create;
  try
    Dateien.Add(Schreibe('App.ini', INI_MIT_IP));
    Funde := TStaticAnalyzer2.AnalyzeLeaksFromList(Dateien, nil, False, FDir);
    try
      Assert.AreEqual<Integer>(0, Funde.Count,
        'SCA201 aus dem Profil: kein Fund, aber auch kein Lesefehler');
    finally
      Funde.Free;
    end;
  finally
    Dateien.Free;
  end;
end;

procedure TTestConfigPass.SingleIni_VanishedFile_NoReadError;
// Eine .ini, die zwischen Sammlung und Durchlauf verschwindet, kostet nur
// sich selbst (Kontrakt von ScanConfigFile).
var
  Funde : TObjectList<TLeakFinding>;
begin
  Funde := TStaticAnalyzer2.AnalyzeLeaks(TPath.Combine(FDir, 'weg.ini'), False);
  try
    Assert.AreEqual<Integer>(0, Funde.Count);
  finally
    Funde.Free;
  end;
end;

procedure TTestConfigPass.SingleIni_Oversized_Skipped;
// Oberhalb von MaxFileBytes laeuft der Detektor nicht - wie bei Units.
var
  Funde : TObjectList<TLeakFinding>;
  Datei : string;
begin
  Datei := Schreibe('Gross.ini', INI_MIT_IP);
  uSCAConsts.DetectorMaxFileBytes := 4;
  Funde := TStaticAnalyzer2.AnalyzeLeaks(Datei, False);
  try
    Assert.AreEqual<Integer>(0, Zaehle(Funde, fkHardcodedIpInConfig),
      'zu gross: uebersprungen');
  finally
    Funde.Free;
  end;
  uSCAConsts.DetectorMaxFileBytes := FAltMax;
  Funde := TStaticAnalyzer2.AnalyzeLeaks(Datei, False);
  try
    Assert.AreEqual<Integer>(1, Zaehle(Funde, fkHardcodedIpInConfig),
      'Gegenprobe: mit normalem Deckel gefunden');
  finally
    Funde.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConfigPass);

end.
