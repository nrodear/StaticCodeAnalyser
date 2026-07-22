unit uTestNotIncludedInProject;

// Tests fuer SCA194 - TNotIncludedInProjectDetector (uNotIncludedInProject).
// Fixtures on-the-fly in ein Temp-Verzeichnis (kein Repo-Fixture-Sync).
// Getestet wird die reine Detect-Kernfunktion (Projektliste + Walk-Root ->
// Orphan-Findings); die Scope-Gating-Verdrahtung liegt in uEngineApi und ist
// nicht Teil dieses Units.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestNotIncludedInProject = class
  private
    FDir : string;
    function W(const ARel: string): string;   // schreibt leere Datei, gibt Vollpfad
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure OrphanPas_Flagged;
    [Test] procedure IncludedPas_NotFlagged;
    [Test] procedure OrphanDfm_Flagged_WhenPasNotInProject;
    [Test] procedure CompanionDfm_NotFlagged_WhenPasInProject;
    [Test] procedure ExcludedDirs_Skipped;
    [Test] procedure SubfolderOrphan_Found;
    [Test] procedure CaseInsensitive_Match;
    [Test] procedure EmptyProject_AllDiskFilesOrphan;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  uMethodd12, uSCAConsts, uNotIncludedInProject;

procedure TTestNotIncludedInProject.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath,
    'sca_orphan_' + TGUID.NewGuid.ToString.Trim(['{','}']));
  TDirectory.CreateDirectory(FDir);
end;

procedure TTestNotIncludedInProject.TearDown;
begin
  try
    if (FDir <> '') and TDirectory.Exists(FDir) then
      TDirectory.Delete(FDir, True);
  except
  end;
end;

function TTestNotIncludedInProject.W(const ARel: string): string;
begin
  Result := TPath.Combine(FDir, ARel);
  TDirectory.CreateDirectory(ExtractFilePath(Result));
  TFile.WriteAllText(Result, '// fixture');
end;

// --- Helfer: Detect ausfuehren, verwaiste FileNames zurueckgeben ---
function RunDetect(const AProjList: array of string; const AWalkRoot: string;
  out ACount: Integer): TStringList;
var
  Proj : TStringList;
  Res  : TObjectList<TLeakFinding>;
  s    : string;
  i    : Integer;
begin
  Result := TStringList.Create;
  Result.CaseSensitive := False;
  Proj := TStringList.Create;
  Res  := TObjectList<TLeakFinding>.Create(True);
  try
    for s in AProjList do Proj.Add(s);
    ACount := TNotIncludedInProjectDetector.Detect(Proj, AWalkRoot, Res);
    for i := 0 to Res.Count - 1 do
    begin
      Assert.AreEqual(Ord(fkNotIncludedInProject), Ord(Res[i].Kind),
        'nur fkNotIncludedInProject erwartet');
      Result.Add(Res[i].FileName);
    end;
  finally
    Res.Free;
    Proj.Free;
  end;
end;

procedure TTestNotIncludedInProject.OrphanPas_Flagged;
var
  incl, orph : string;
  cnt : Integer;
  found : TStringList;
begin
  incl := W('uMain.pas');
  orph := W('uOld.pas');
  found := RunDetect([incl], FDir, cnt);
  try
    Assert.AreEqual(1, cnt, 'genau ein Orphan');
    Assert.IsTrue(found.IndexOf(orph) >= 0, 'uOld.pas verwaist');
    Assert.IsTrue(found.IndexOf(incl) < 0, 'uMain.pas gehoert zum Projekt');
  finally
    found.Free;
  end;
end;

procedure TTestNotIncludedInProject.IncludedPas_NotFlagged;
var
  a, b : string;
  cnt : Integer;
  found : TStringList;
begin
  a := W('uA.pas');
  b := W('uB.pas');
  found := RunDetect([a, b], FDir, cnt);
  try
    Assert.AreEqual(0, cnt, 'alle im Projekt -> keine Orphans');
  finally
    found.Free;
  end;
end;

procedure TTestNotIncludedInProject.OrphanDfm_Flagged_WhenPasNotInProject;
var
  incl, orphPas, orphDfm : string;
  cnt : Integer;
  found : TStringList;
begin
  incl    := W('uMain.pas');
  orphPas := W('uForm.pas');
  orphDfm := W('uForm.dfm');
  // uForm.pas NICHT im Projekt -> sowohl .pas als auch .dfm verwaist.
  found := RunDetect([incl], FDir, cnt);
  try
    Assert.AreEqual(2, cnt, 'uForm.pas + uForm.dfm verwaist');
    Assert.IsTrue(found.IndexOf(orphPas) >= 0);
    Assert.IsTrue(found.IndexOf(orphDfm) >= 0);
  finally
    found.Free;
  end;
end;

procedure TTestNotIncludedInProject.CompanionDfm_NotFlagged_WhenPasInProject;
var
  incl, dfm : string;
  cnt : Integer;
  found : TStringList;
begin
  incl := W('uForm.pas');
  dfm  := W('uForm.dfm');
  // uForm.pas IST im Projekt -> Companion .dfm gilt als eingeschlossen.
  found := RunDetect([incl], FDir, cnt);
  try
    Assert.AreEqual(0, cnt, 'Companion-DFM zur eingeschlossenen .pas ist kein Orphan');
  finally
    found.Free;
  end;
end;

procedure TTestNotIncludedInProject.ExcludedDirs_Skipped;
var
  incl : string;
  cnt : Integer;
  found : TStringList;
begin
  incl := W('uMain.pas');
  W('__history\uMain.~pas');   // .~pas ohnehin ignoriert
  W('.git\uSomething.pas');    // in .git -> ganzer Ordner uebersprungen
  W('__recovery\uX.pas');
  found := RunDetect([incl], FDir, cnt);
  try
    Assert.AreEqual(0, cnt, 'Dateien in Exclude-Ordnern zaehlen nicht');
  finally
    found.Free;
  end;
end;

procedure TTestNotIncludedInProject.SubfolderOrphan_Found;
var
  incl, orph : string;
  cnt : Integer;
  found : TStringList;
begin
  incl := W('uMain.pas');
  orph := W('sub\deep\uBuried.pas');
  found := RunDetect([incl], FDir, cnt);
  try
    Assert.AreEqual(1, cnt);
    Assert.IsTrue(found.IndexOf(orph) >= 0, 'Orphan in Unterordner gefunden');
  finally
    found.Free;
  end;
end;

procedure TTestNotIncludedInProject.CaseInsensitive_Match;
var
  onDisk : string;
  cnt : Integer;
  found : TStringList;
begin
  onDisk := W('uMain.pas');
  // Projektliste in anderer Schreibweise -> darf NICHT als Orphan gelten.
  found := RunDetect([UpperCase(onDisk)], FDir, cnt);
  try
    Assert.AreEqual(0, cnt, 'case-insensitiver Pfad-Match');
  finally
    found.Free;
  end;
end;

procedure TTestNotIncludedInProject.EmptyProject_AllDiskFilesOrphan;
var
  cnt : Integer;
  found : TStringList;
begin
  W('uA.pas');
  W('uB.pas');
  // Leere Projektliste -> beide .pas verwaist.
  found := RunDetect([], FDir, cnt);
  try
    Assert.AreEqual(2, cnt);
  finally
    found.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestNotIncludedInProject);

end.
