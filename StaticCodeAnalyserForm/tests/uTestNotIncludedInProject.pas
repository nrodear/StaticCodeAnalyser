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
    // Impl-Review 2026-07-24 (5 bestaetigte Testluecken; Cap-Verhalten bleibt
    // bewusst ungetestet - 20k-Fixtures sind Unit-Test-untauglich):
    [Test] procedure IgnoreList_FileAndDirParity;
    [Test] procedure RelativeWalkRoot_CanonicalMatch;
    [Test] procedure DfmAndPasMessages_Distinct;
    [Test] procedure Findings_SortedByPath;
    [Test] procedure CompanionDfm_OtherDirectory_StillOrphan;
    // SCA195 UsedButNotInProject (Abspaltung 2026-07-29): Orphans, die von
    // Projekt-Units per uses gezogen werden, sind "fehlt im Projekt", nicht
    // "verwaist".
    [Test] procedure UsedOrphan_FlaggedAsUsedButNotInProject;
    [Test] procedure TransitiveUsedOrphan_AlsoUsed;
    [Test] procedure DeadAndUsedOrphan_SplitCorrectly;
    [Test] procedure UsesInComment_DoesNotCount;
    [Test] procedure UsesInStringLiteral_DoesNotCount;
    [Test] procedure CompanionDfm_FollowsUsedClassification;
    [Test] procedure DottedUnitName_Matched;
    [Test] procedure UsesMatch_CaseInsensitive;
    [Test] procedure KindGating_UsedOnlyEmits195;
    [Test] procedure KindGating_DeadOnlyEmits194;
    // Review 2026-07-29 (3 bestaetigte Luecken):
    [Test] procedure OrphanCycle_WithoutProjectRef_StaysDead;
    [Test] procedure IfdefAdjacentUses_BothBranchesCount;
    [Test] procedure DprOnlyUsedUnit_Flagged195;
    // Review 2026-07-30: Namensvetter einer PROJEKT-Unit ist eine tote
    // Kopie und bleibt 194 - inkl. Kaskaden-Stopp (ihre uses zaehlen nicht).
    [Test] procedure StaleCopyOfProjectUnit_Stays194;
    [Test] procedure StaleCopyCascade_NotPulledTo195;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  uMethodd12, uSCAConsts, uIgnoreList, uNotIncludedInProject;

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
  out ACount: Integer; AIgnore: TIgnoreList = nil): TStringList;
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
    ACount := TNotIncludedInProjectDetector.Detect(Proj, AWalkRoot, Res, AIgnore);
    for i := 0 to Res.Count - 1 do
    begin
      Assert.AreEqual<Integer>(Ord(fkNotIncludedInProject), Ord(Res[i].Kind),
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
    Assert.AreEqual<Integer>(1, cnt, 'genau ein Orphan');
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
    Assert.AreEqual<Integer>(0, cnt, 'alle im Projekt -> keine Orphans');
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
    Assert.AreEqual<Integer>(2, cnt, 'uForm.pas + uForm.dfm verwaist');
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
    Assert.AreEqual<Integer>(0, cnt, 'Companion-DFM zur eingeschlossenen .pas ist kein Orphan');
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
    Assert.AreEqual<Integer>(0, cnt, 'Dateien in Exclude-Ordnern zaehlen nicht');
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
    Assert.AreEqual<Integer>(1, cnt);
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
    Assert.AreEqual<Integer>(0, cnt, 'case-insensitiver Pfad-Match');
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
    Assert.AreEqual<Integer>(2, cnt);
  finally
    found.Free;
  end;
end;

// --- Impl-Review 2026-07-24: die 5 bestaetigten Testluecken ---

procedure TTestNotIncludedInProject.IgnoreList_FileAndDirParity;
// ignore.txt-Parity war explizite Review-Anforderung des Unit-Headers,
// aber KEIN Test uebergab je eine TIgnoreList: Datei-Skip (Detect ~Z.143)
// und Verzeichnis-Skip via dummy.pas-Trick (~Z.134) waren beide ungedeckt.
var
  incl, orphReal, ignFile : string;
  Proj : TStringList;
  Res  : TObjectList<TLeakFinding>;
  Ign  : TIgnoreList;
begin
  incl     := W('uMain.pas');
  orphReal := W('uReal.pas');            // Kontroll-Orphan: bleibt gemeldet
  W('uSkipped.pas');                     // per Datei-Pattern ignoriert
  W('legacy\uOld.pas');                  // per Verzeichnis-Pattern ignoriert
  ignFile := TPath.Combine(FDir, 'ignore.txt');
  TFile.WriteAllText(ignFile, 'uSkipped.pas'#13#10 + 'legacy/'#13#10);
  Proj := TStringList.Create;
  Res  := TObjectList<TLeakFinding>.Create(True);
  Ign  := TIgnoreList.Create;
  try
    Ign.SkipTests := False;
    Ign.LoadFromFile(ignFile);
    Proj.Add(incl);
    Assert.AreEqual<Integer>(1,
      TNotIncludedInProjectDetector.Detect(Proj, FDir, Res, Ign),
      'nur uReal.pas bleibt Orphan - Datei- UND Verzeichnis-Ignore greifen');
    Assert.AreEqual<string>(orphReal, Res[0].FileName);
  finally
    Ign.Free;
    Res.Free;
    Proj.Free;
  end;
end;

procedure TTestNotIncludedInProject.RelativeWalkRoot_CanonicalMatch;
// NormKey-Kanonisierung (GetFullPath beidseitig): ein Walk-Root mit
// '..'-Segment liefert nicht-kanonische Walk-Pfade - ohne GetFullPath in
// NormKey matcht keine Projektdatei mehr und ALLES wird Orphan (der
// dokumentierte FP-Storm aus dem Review 2026-07-22). Alle bisherigen
// Tests nutzten bereits kanonische Pfade und haetten das nie bemerkt.
var
  incl, subPas, walkRoot : string;
  cnt : Integer;
  found : TStringList;
begin
  incl     := W('uMain.pas');
  subPas   := W('sub\uSub.pas');
  walkRoot := TPath.Combine(FDir, 'sub') + '\..';
  found := RunDetect([incl, subPas], walkRoot, cnt);
  try
    Assert.AreEqual<Integer>(0, cnt,
      'nicht-kanonischer Walk-Root (..-Segment) darf keine FPs erzeugen');
  finally
    found.Free;
  end;
end;

procedure TTestNotIncludedInProject.DfmAndPasMessages_Distinct;
// Tag-Message-Kopplung: die Object-Tags (0=.pas/1=.dfm) wandern beim Sort
// mit und steuern die Message. Bisher pruefte kein Test die Messages -
// eine vertauschte Zuordnung waere unbemerkt geblieben. Diskriminator:
// 'form' kommt NUR in der .dfm-Message vor.
var
  Proj : TStringList;
  Res  : TObjectList<TLeakFinding>;
  i : Integer;
  msgLow : string;
begin
  W('uForm.pas');
  W('uForm.dfm');
  Proj := TStringList.Create;
  Res  := TObjectList<TLeakFinding>.Create(True);
  try
    Assert.AreEqual<Integer>(2, TNotIncludedInProjectDetector.Detect(Proj, FDir, Res));
    for i := 0 to Res.Count - 1 do
    begin
      msgLow := Res[i].MissingVar.ToLower;
      if Res[i].FileName.ToLower.EndsWith('.dfm') then
        Assert.IsTrue(msgLow.Contains('form'),
          '.dfm-Orphan traegt die Form-Message')
      else
        Assert.IsFalse(msgLow.Contains('form file'),
          '.pas-Orphan traegt NICHT die Form-Message');
    end;
  finally
    Res.Free;
    Proj.Free;
  end;
end;

procedure TTestNotIncludedInProject.Findings_SortedByPath;
// Sort-Determinismus (SARIF-Byte-Stabilitaet): die Ausgabe muss exakt der
// TStringList-Sortierung (case-insensitiv) entsprechen - unabhaengig von
// der FS-abhaengigen FindFirst-Reihenfolge. Fixture so gewaehlt, dass die
// Walk-Reihenfolge (Verzeichnis 'a' vor Datei 'a!.pas') von der sortierten
// Pfad-Reihenfolge abweichen kann.
var
  Proj     : TStringList;
  Res      : TObjectList<TLeakFinding>;
  Expected : TStringList;
  i : Integer;
begin
  W('a\x.pas');
  W('a!.pas');
  W('m.pas');
  Proj     := TStringList.Create;
  Res      := TObjectList<TLeakFinding>.Create(True);
  Expected := TStringList.Create;
  Expected.CaseSensitive := False;
  try
    Assert.AreEqual<Integer>(3, TNotIncludedInProjectDetector.Detect(Proj, FDir, Res));
    for i := 0 to Res.Count - 1 do
      Expected.Add(Res[i].FileName);
    Expected.Sort;
    for i := 0 to Res.Count - 1 do
      Assert.AreEqual<string>(Expected[i], Res[i].FileName,
        'Findings exakt in sortierter Pfad-Reihenfolge (Index ' +
        IntToStr(i) + ')');
  finally
    Expected.Free;
    Res.Free;
    Proj.Free;
  end;
end;

procedure TTestNotIncludedInProject.CompanionDfm_OtherDirectory_StillOrphan;
// Companion-Match ist VOLLPFAD-basiert: eine namensgleiche .dfm in einem
// anderen Verzeichnis als die referenzierte .pas ist KEIN Companion und
// bleibt Orphan. Bisher war nur der Gleiches-Verzeichnis-Fall getestet.
var
  incl, dfm : string;
  cnt : Integer;
  found : TStringList;
begin
  incl := W('uForm.pas');
  dfm  := W('sub\uForm.dfm');
  found := RunDetect([incl], FDir, cnt);
  try
    Assert.AreEqual<Integer>(1, cnt,
      'namensgleiche .dfm in anderem Verzeichnis ist kein Companion');
    Assert.IsTrue(found.IndexOf(dfm) >= 0);
  finally
    found.Free;
  end;
end;

{ ---- SCA195 UsedButNotInProject (2026-07-29) ----

  Fixtures brauchen hier ECHTEN Inhalt (uses-Klauseln), deshalb ein zweiter
  Schreib-Helfer. Der zweite Detect-Helfer liefert Kind+Pfad, weil jetzt
  zwei Kinds aus demselben Lauf kommen.                                     }

function WriteWithContent(const ADir, ARel, AContent: string): string;
begin
  Result := TPath.Combine(ADir, ARel);
  TDirectory.CreateDirectory(ExtractFilePath(Result));
  TFile.WriteAllText(Result, AContent);
end;

// Liefert 'K|Pfad' je Fund, K = Ord(TFindingKind).
function RunDetectKinds(const AProjList: array of string;
  const AWalkRoot: string; out ACount: Integer;
  const AProjectFile: string = ''): TStringList;
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
    ACount := TNotIncludedInProjectDetector.Detect(Proj, AWalkRoot, Res, nil,
      AProjectFile);
    for i := 0 to Res.Count - 1 do
      Result.Add(IntToStr(Ord(Res[i].Kind)) + '|' + Res[i].FileName);
  finally
    Res.Free;
    Proj.Free;
  end;
end;

function K194(const APath: string): string;
begin
  Result := IntToStr(Ord(fkNotIncludedInProject)) + '|' + APath;
end;

function K195(const APath: string): string;
begin
  Result := IntToStr(Ord(fkUsedButNotInProject)) + '|' + APath;
end;

procedure TTestNotIncludedInProject.UsedOrphan_FlaggedAsUsedButNotInProject;
var
  main, orph : string;
  cnt : Integer;
  found : TStringList;
begin
  main := WriteWithContent(FDir, 'uMain.pas',
    'unit uMain;'#13#10'interface'#13#10'uses uHelper;'#13#10 +
    'implementation'#13#10'end.');
  orph := WriteWithContent(FDir, 'uHelper.pas',
    'unit uHelper;'#13#10'interface'#13#10'implementation'#13#10'end.');
  found := RunDetectKinds([main], FDir, cnt);
  try
    Assert.AreEqual<Integer>(1, cnt, 'genau ein Fund');
    Assert.IsTrue(found.IndexOf(K195(orph)) >= 0,
      'per uses gezogener Orphan muss fkUsedButNotInProject sein, Ist: '
      + found.Text);
  finally
    found.Free;
  end;
end;

procedure TTestNotIncludedInProject.TransitiveUsedOrphan_AlsoUsed;
var
  main, o1, o2 : string;
  cnt : Integer;
  found : TStringList;
begin
  // uMain (Projekt) -> uHelper (Orphan) -> uDeep (Orphan): der Compiler
  // folgt der Kette ueber den Suchpfad, also sind BEIDE "benutzt".
  main := WriteWithContent(FDir, 'uMain.pas',
    'unit uMain;'#13#10'interface'#13#10'uses uHelper;'#13#10 +
    'implementation'#13#10'end.');
  o1 := WriteWithContent(FDir, 'uHelper.pas',
    'unit uHelper;'#13#10'interface'#13#10'implementation'#13#10 +
    'uses uDeep;'#13#10'end.');
  o2 := WriteWithContent(FDir, 'uDeep.pas',
    'unit uDeep;'#13#10'interface'#13#10'implementation'#13#10'end.');
  found := RunDetectKinds([main], FDir, cnt);
  try
    Assert.AreEqual<Integer>(2, cnt, 'zwei Funde');
    Assert.IsTrue(found.IndexOf(K195(o1)) >= 0, 'uHelper direkt benutzt');
    Assert.IsTrue(found.IndexOf(K195(o2)) >= 0,
      'uDeep transitiv benutzt, Ist: ' + found.Text);
  finally
    found.Free;
  end;
end;

procedure TTestNotIncludedInProject.DeadAndUsedOrphan_SplitCorrectly;
var
  main, used, dead : string;
  cnt : Integer;
  found : TStringList;
begin
  main := WriteWithContent(FDir, 'uMain.pas',
    'unit uMain;'#13#10'interface'#13#10'uses uHelper;'#13#10 +
    'implementation'#13#10'end.');
  used := WriteWithContent(FDir, 'uHelper.pas',
    'unit uHelper;'#13#10'interface'#13#10'implementation'#13#10'end.');
  dead := WriteWithContent(FDir, 'uDead.pas',
    'unit uDead;'#13#10'interface'#13#10'implementation'#13#10'end.');
  found := RunDetectKinds([main], FDir, cnt);
  try
    Assert.AreEqual<Integer>(2, cnt, 'zwei Funde');
    Assert.IsTrue(found.IndexOf(K195(used)) >= 0, 'uHelper = 195');
    Assert.IsTrue(found.IndexOf(K194(dead)) >= 0,
      'uDead bleibt 194, Ist: ' + found.Text);
  finally
    found.Free;
  end;
end;

procedure TTestNotIncludedInProject.UsesInComment_DoesNotCount;
var
  main, orph : string;
  cnt : Integer;
  found : TStringList;
begin
  // Projektregel: Kommentare zaehlen NIE als Code-Use.
  main := WriteWithContent(FDir, 'uMain.pas',
    'unit uMain;'#13#10'interface'#13#10 +
    '// uses uGhost;'#13#10'{ uses uGhost; }'#13#10 +
    'implementation'#13#10'end.');
  orph := WriteWithContent(FDir, 'uGhost.pas',
    'unit uGhost;'#13#10'interface'#13#10'implementation'#13#10'end.');
  found := RunDetectKinds([main], FDir, cnt);
  try
    Assert.AreEqual<Integer>(1, cnt, 'genau ein Fund');
    Assert.IsTrue(found.IndexOf(K194(orph)) >= 0,
      'uses im Kommentar darf nicht zaehlen - uGhost bleibt 194, Ist: '
      + found.Text);
  finally
    found.Free;
  end;
end;

procedure TTestNotIncludedInProject.UsesInStringLiteral_DoesNotCount;
var
  main, orph : string;
  cnt : Integer;
  found : TStringList;
begin
  main := WriteWithContent(FDir, 'uMain.pas',
    'unit uMain;'#13#10'interface'#13#10'implementation'#13#10 +
    'const S = ''uses uGhost;'';'#13#10'end.');
  orph := WriteWithContent(FDir, 'uGhost.pas',
    'unit uGhost;'#13#10'interface'#13#10'implementation'#13#10'end.');
  found := RunDetectKinds([main], FDir, cnt);
  try
    Assert.AreEqual<Integer>(1, cnt, 'genau ein Fund');
    Assert.IsTrue(found.IndexOf(K194(orph)) >= 0,
      'uses im String-Literal darf nicht zaehlen, Ist: ' + found.Text);
  finally
    found.Free;
  end;
end;

procedure TTestNotIncludedInProject.CompanionDfm_FollowsUsedClassification;
var
  main, orph, dfm : string;
  cnt : Integer;
  found : TStringList;
begin
  main := WriteWithContent(FDir, 'uMain.pas',
    'unit uMain;'#13#10'interface'#13#10'uses uForm;'#13#10 +
    'implementation'#13#10'end.');
  orph := WriteWithContent(FDir, 'uForm.pas',
    'unit uForm;'#13#10'interface'#13#10'implementation'#13#10'end.');
  dfm := WriteWithContent(FDir, 'uForm.dfm', 'object Form1: TForm1'#13#10'end');
  found := RunDetectKinds([main], FDir, cnt);
  try
    Assert.AreEqual<Integer>(2, cnt, 'pas + dfm');
    Assert.IsTrue(found.IndexOf(K195(orph)) >= 0, 'uForm.pas = 195');
    Assert.IsTrue(found.IndexOf(K195(dfm)) >= 0,
      'Companion-.dfm folgt der 195-Klassifikation, Ist: ' + found.Text);
  finally
    found.Free;
  end;
end;

procedure TTestNotIncludedInProject.DottedUnitName_Matched;
var
  main, orph : string;
  cnt : Integer;
  found : TStringList;
begin
  main := WriteWithContent(FDir, 'uMain.pas',
    'unit uMain;'#13#10'interface'#13#10'uses App.Core.Helper;'#13#10 +
    'implementation'#13#10'end.');
  orph := WriteWithContent(FDir, 'App.Core.Helper.pas',
    'unit App.Core.Helper;'#13#10'interface'#13#10'implementation'#13#10'end.');
  found := RunDetectKinds([main], FDir, cnt);
  try
    Assert.AreEqual<Integer>(1, cnt, 'genau ein Fund');
    Assert.IsTrue(found.IndexOf(K195(orph)) >= 0,
      'gepunkteter Unit-Name muss matchen, Ist: ' + found.Text);
  finally
    found.Free;
  end;
end;

procedure TTestNotIncludedInProject.UsesMatch_CaseInsensitive;
var
  main, orph : string;
  cnt : Integer;
  found : TStringList;
begin
  main := WriteWithContent(FDir, 'uMain.pas',
    'unit uMain;'#13#10'interface'#13#10'uses UHELPER;'#13#10 +
    'implementation'#13#10'end.');
  orph := WriteWithContent(FDir, 'uhelper.pas',
    'unit uhelper;'#13#10'interface'#13#10'implementation'#13#10'end.');
  found := RunDetectKinds([main], FDir, cnt);
  try
    Assert.AreEqual<Integer>(1, cnt, 'genau ein Fund');
    Assert.IsTrue(found.IndexOf(K195(orph)) >= 0,
      'uses-Match muss case-insensitiv sein, Ist: ' + found.Text);
  finally
    found.Free;
  end;
end;

procedure TTestNotIncludedInProject.KindGating_UsedOnlyEmits195;
var
  main, used, dead : string;
  cnt : Integer;
  found : TStringList;
  Saved : TFindingKinds;
begin
  // Detect gated selbst per Kind (der Dispatch-Pfad umgeht den Post-Filter).
  main := WriteWithContent(FDir, 'uMain.pas',
    'unit uMain;'#13#10'interface'#13#10'uses uHelper;'#13#10 +
    'implementation'#13#10'end.');
  used := WriteWithContent(FDir, 'uHelper.pas',
    'unit uHelper;'#13#10'interface'#13#10'implementation'#13#10'end.');
  dead := WriteWithContent(FDir, 'uDead.pas',
    'unit uDead;'#13#10'interface'#13#10'implementation'#13#10'end.');
  Saved := uSCAConsts.DetectorEnabledKinds;
  try
    uSCAConsts.DetectorEnabledKinds := [fkUsedButNotInProject];
    found := RunDetectKinds([main], FDir, cnt);
    try
      Assert.AreEqual<Integer>(1, cnt, 'nur der 195-Fund darf emittiert werden');
      Assert.IsTrue(found.IndexOf(K195(used)) >= 0, '195 vorhanden');
      Assert.IsTrue(found.IndexOf(K194(dead)) < 0,
        '194 muss weggefiltert sein, Ist: ' + found.Text);
    finally
      found.Free;
    end;
  finally
    uSCAConsts.DetectorEnabledKinds := Saved;
  end;
end;

procedure TTestNotIncludedInProject.OrphanCycle_WithoutProjectRef_StaysDead;
var
  main, a, b : string;
  cnt : Integer;
  found : TStringList;
begin
  // Zyklus A<->B ohne Projekt-Referenz: der Fixpunkt darf nicht haengen,
  // und beide bleiben 194 - benutzt-von-tot ist weiterhin tot.
  main := WriteWithContent(FDir, 'uMain.pas',
    'unit uMain;'#13#10'interface'#13#10'implementation'#13#10'end.');
  a := WriteWithContent(FDir, 'uCycA.pas',
    'unit uCycA;'#13#10'interface'#13#10'uses uCycB;'#13#10 +
    'implementation'#13#10'end.');
  b := WriteWithContent(FDir, 'uCycB.pas',
    'unit uCycB;'#13#10'interface'#13#10'implementation'#13#10 +
    'uses uCycA;'#13#10'end.');
  found := RunDetectKinds([main], FDir, cnt);
  try
    Assert.AreEqual<Integer>(2, cnt, 'beide Zyklus-Orphans gemeldet');
    Assert.IsTrue(found.IndexOf(K194(a)) >= 0,
      'uCycA bleibt 194, Ist: ' + found.Text);
    Assert.IsTrue(found.IndexOf(K194(b)) >= 0,
      'uCycB bleibt 194, Ist: ' + found.Text);
  finally
    found.Free;
  end;
end;

procedure TTestNotIncludedInProject.IfdefAdjacentUses_BothBranchesCount;
var
  main, o1, o2 : string;
  cnt : Integer;
  found : TStringList;
begin
  // Cross-Platform-Idiom: uses {$IFDEF X}uAlt{$ELSE}uNeu{$ENDIF};
  // Der Stripper muss Direktiven durch ein TRENNZEICHEN ersetzen - sonst
  // verschmelzen die Nachbar-Idents zu einem Phantom-Token und BEIDE
  // Units fallen faelschlich auf 194 zurueck (Review 2026-07-29).
  main := WriteWithContent(FDir, 'uMain.pas',
    'unit uMain;'#13#10'interface'#13#10 +
    'uses {$IFDEF FPC}uAlt{$ELSE}uNeu{$ENDIF};'#13#10 +
    'implementation'#13#10'end.');
  o1 := WriteWithContent(FDir, 'uAlt.pas',
    'unit uAlt;'#13#10'interface'#13#10'implementation'#13#10'end.');
  o2 := WriteWithContent(FDir, 'uNeu.pas',
    'unit uNeu;'#13#10'interface'#13#10'implementation'#13#10'end.');
  found := RunDetectKinds([main], FDir, cnt);
  try
    Assert.AreEqual<Integer>(2, cnt, 'zwei Funde');
    Assert.IsTrue(found.IndexOf(K195(o1)) >= 0,
      'IFDEF-Zweig 1 muss als benutzt gelten, Ist: ' + found.Text);
    Assert.IsTrue(found.IndexOf(K195(o2)) >= 0,
      'IFDEF-Zweig 2 muss als benutzt gelten, Ist: ' + found.Text);
  finally
    found.Free;
  end;
end;

procedure TTestNotIncludedInProject.DprOnlyUsedUnit_Flagged195;
var
  dproj, main, orph : string;
  cnt : Integer;
  found : TStringList;
begin
  // Die Programm-Hauptdatei (.dpr) steht nie in der DCCReference-Liste,
  // ihre uses-Klausel ist aber die Wurzel des Kompilats. Eine nur dort
  // gezogene Unit ist 195, nicht 194 (Review 2026-07-29).
  dproj := TPath.Combine(FDir, 'Demo.dproj');
  TFile.WriteAllText(dproj, '<Project/>');
  WriteWithContent(FDir, 'Demo.dpr',
    'program Demo;'#13#10'uses uMain, uConfigLocal;'#13#10'begin'#13#10'end.');
  main := WriteWithContent(FDir, 'uMain.pas',
    'unit uMain;'#13#10'interface'#13#10'implementation'#13#10'end.');
  orph := WriteWithContent(FDir, 'uConfigLocal.pas',
    'unit uConfigLocal;'#13#10'interface'#13#10'implementation'#13#10'end.');
  found := RunDetectKinds([main], FDir, cnt, dproj);
  try
    Assert.AreEqual<Integer>(1, cnt, 'genau ein Fund');
    Assert.IsTrue(found.IndexOf(K195(orph)) >= 0,
      'nur vom .dpr gezogene Unit muss 195 sein, Ist: ' + found.Text);
  finally
    found.Free;
  end;
end;

procedure TTestNotIncludedInProject.StaleCopyOfProjectUnit_Stays194;
var
  app, main, copy : string;
  cnt : Integer;
  found : TStringList;
begin
  // Review 2026-07-30: backup\uMain.pas ist Namensvetter der PROJEKT-Unit
  // src\uMain.pas. Der Compiler kompiliert die im Projekt referenzierte
  // Datei - die Kopie ist tot (194). Ohne das ProjBase-Gate kippte sie
  // auf 195 'add it to the project' (Duplicate-Unit-Rat), weil 'umain'
  // ueber die uses-Klausel von uApp in UsedNames steht.
  app := WriteWithContent(FDir, 'uApp.pas',
    'unit uApp;'#13#10'interface'#13#10'uses uMain;'#13#10 +
    'implementation'#13#10'end.');
  main := WriteWithContent(FDir, 'src\uMain.pas',
    'unit uMain;'#13#10'interface'#13#10'implementation'#13#10'end.');
  copy := WriteWithContent(FDir, 'backup\uMain.pas',
    'unit uMain;'#13#10'interface'#13#10'implementation'#13#10'end.');
  found := RunDetectKinds([app, main], FDir, cnt);
  try
    Assert.AreEqual<Integer>(1, cnt, 'genau ein Fund (die tote Kopie)');
    Assert.IsTrue(found.IndexOf(K194(copy)) >= 0,
      'Namensvetter einer Projekt-Unit muss 194 bleiben, Ist: ' + found.Text);
  finally
    found.Free;
  end;
end;

procedure TTestNotIncludedInProject.StaleCopyCascade_NotPulledTo195;
var
  app, main, copy, oldh : string;
  cnt : Integer;
  found : TStringList;
begin
  // Kaskaden-Stopp: die tote Kopie zieht per uses uOldHelper - da die
  // Kopie nie als 'benutzt' klassifiziert wird, duerfen ihre uses NICHT
  // in den Fixpunkt einfliessen; der ganze Backup-Cluster bleibt 194.
  app := WriteWithContent(FDir, 'uApp.pas',
    'unit uApp;'#13#10'interface'#13#10'uses uMain;'#13#10 +
    'implementation'#13#10'end.');
  main := WriteWithContent(FDir, 'src\uMain.pas',
    'unit uMain;'#13#10'interface'#13#10'implementation'#13#10'end.');
  copy := WriteWithContent(FDir, 'backup\uMain.pas',
    'unit uMain;'#13#10'interface'#13#10'uses uOldHelper;'#13#10 +
    'implementation'#13#10'end.');
  oldh := WriteWithContent(FDir, 'backup\uOldHelper.pas',
    'unit uOldHelper;'#13#10'interface'#13#10'implementation'#13#10'end.');
  found := RunDetectKinds([app, main], FDir, cnt);
  try
    Assert.AreEqual<Integer>(2, cnt, 'beide Backup-Dateien sind Funde');
    Assert.IsTrue(found.IndexOf(K194(copy)) >= 0,
      'tote Kopie bleibt 194, Ist: ' + found.Text);
    Assert.IsTrue(found.IndexOf(K194(oldh)) >= 0,
      'transitiv nur von der Kopie gezogene Unit bleibt 194, Ist: '
      + found.Text);
  finally
    found.Free;
  end;
end;

procedure TTestNotIncludedInProject.KindGating_DeadOnlyEmits194;
var
  main, used, dead : string;
  cnt : Integer;
  found : TStringList;
  Saved : TFindingKinds;
begin
  // Spiegel zu KindGating_UsedOnlyEmits195: nur 194 aktiv -> der
  // 195-Fund wird unterdrueckt, der tote Orphan bleibt.
  main := WriteWithContent(FDir, 'uMain.pas',
    'unit uMain;'#13#10'interface'#13#10'uses uHelper;'#13#10 +
    'implementation'#13#10'end.');
  used := WriteWithContent(FDir, 'uHelper.pas',
    'unit uHelper;'#13#10'interface'#13#10'implementation'#13#10'end.');
  dead := WriteWithContent(FDir, 'uDead.pas',
    'unit uDead;'#13#10'interface'#13#10'implementation'#13#10'end.');
  Saved := uSCAConsts.DetectorEnabledKinds;
  try
    uSCAConsts.DetectorEnabledKinds := [fkNotIncludedInProject];
    found := RunDetectKinds([main], FDir, cnt);
    try
      Assert.AreEqual<Integer>(1, cnt, 'nur der 194-Fund darf emittiert werden');
      Assert.IsTrue(found.IndexOf(K194(dead)) >= 0, '194 vorhanden');
      Assert.IsTrue(found.IndexOf(K195(used)) < 0,
        '195 muss weggefiltert sein, Ist: ' + found.Text);
    finally
      found.Free;
    end;
  finally
    uSCAConsts.DetectorEnabledKinds := Saved;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestNotIncludedInProject);

end.
