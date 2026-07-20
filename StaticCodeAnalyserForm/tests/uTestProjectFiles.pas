unit uTestProjectFiles;

// Tests fuer TProjectFiles (uProjectFiles): .dproj-/.groupproj-Aufloesung
// des Scan-Scope-Konzepts (Konzept_ScanScope_2026-07-20).
//
// Fixture-Strategie: die dproj/groupproj-XMLs werden ON-THE-FLY in ein
// Temp-Verzeichnis geschrieben (TPath.GetTempPath + GUID) - deterministisch,
// kein Repo-Fixture-Sync, und die relativen '..'-Faelle lassen sich mit
// echten Unterverzeichnissen nachbauen (Review-Vorgabe Konzept §8).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestProjectFiles = class
  private
    FDir : string;   // Temp-Wurzel dieses Tests (Setup/TearDown)
    function WriteFile(const ARelPath, AContent: string): string;
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;

    // ---- FromDproj --------------------------------------------------------
    [Test] procedure Dproj_ThreeRefs_OneMissing_TwoResolved_WarningForMissing;
    [Test] procedure Dproj_RelativeParentPath_ResolvedAgainstDprojDir;
    [Test] procedure Dproj_XmlEscapes_And_Namespace_Handled;
    [Test] procedure Dproj_MacroInclude_SkippedWithWarning;
    [Test] procedure Dproj_NonPasRefs_Ignored;
    [Test] procedure Dproj_DuplicateRefs_CaseInsensitive_Deduped;
    [Test] procedure Dproj_MissingFile_ErrorMsg_EmptyList;
    [Test] procedure Dproj_BrokenXml_ErrorMsg_EmptyList;
    // ---- FromGroupproj ----------------------------------------------------
    [Test] procedure Group_TwoProjects_SharedUnit_Deduped;
    [Test] procedure Group_RelativeProjectPath_Resolved;
    [Test] procedure Group_OneBrokenProject_WarnsAndContinues;
    [Test] procedure Group_NothingResolvable_ErrorMsg;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  uProjectFiles;

const
  // Minimal-dproj: MSBuild-Namespace wie im Original; %s = ItemGroup-Inhalt.
  DPROJ_TPL =
    '<?xml version="1.0" encoding="utf-8"?>' + sLineBreak +
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <ItemGroup>' + sLineBreak +
    '%s' + sLineBreak +
    '  </ItemGroup>' + sLineBreak +
    '</Project>';

  GROUP_TPL =
    '<?xml version="1.0" encoding="utf-8"?>' + sLineBreak +
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <ItemGroup>' + sLineBreak +
    '%s' + sLineBreak +
    '  </ItemGroup>' + sLineBreak +
    '</Project>';

procedure TTestProjectFiles.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath,
    'sca_projfiles_' + TGUID.NewGuid.ToString.Trim(['{', '}']));
  TDirectory.CreateDirectory(FDir);
end;

procedure TTestProjectFiles.TearDown;
begin
  try
    if (FDir <> '') and TDirectory.Exists(FDir) then
      TDirectory.Delete(FDir, True);
  except
    // Temp-Aufraeumen darf nie einen Test reissen.
  end;
end;

function TTestProjectFiles.WriteFile(const ARelPath, AContent: string): string;
begin
  Result := TPath.Combine(FDir, ARelPath);
  TDirectory.CreateDirectory(ExtractFilePath(Result));
  TFile.WriteAllText(Result, AContent, TEncoding.UTF8);
end;

{ ---- FromDproj ---- }

procedure TTestProjectFiles.Dproj_ThreeRefs_OneMissing_TwoResolved_WarningForMissing;
var
  Dproj : string;
  Err   : string;
  Warn  : TStringList;
  L     : TStringList;
begin
  WriteFile('src\uA.pas', 'unit uA; interface implementation end.');
  WriteFile('src\uB.pas', 'unit uB; interface implementation end.');
  Dproj := WriteFile('proj\Test.dproj', Format(DPROJ_TPL, [
    '    <DCCReference Include="..\src\uA.pas"/>' + sLineBreak +
    '    <DCCReference Include="..\src\uB.pas"/>' + sLineBreak +
    '    <DCCReference Include="..\src\uFehlt.pas"/>']));
  Warn := TStringList.Create;
  L := TProjectFiles.FromDproj(Dproj, Err, Warn);
  try
    Assert.AreEqual('', Err, 'kein harter Fehler');
    Assert.AreEqual(2, L.Count, 'zwei existierende Dateien');
    Assert.AreEqual(1, Warn.Count, 'eine Warnung fuer die fehlende');
    Assert.IsTrue(Warn[0].Contains('uFehlt.pas'), Warn.Text);
  finally
    L.Free;
    Warn.Free;
  end;
end;

procedure TTestProjectFiles.Dproj_RelativeParentPath_ResolvedAgainstDprojDir;
var
  Dproj : string;
  Err   : string;
  L     : TStringList;
  Expected : string;
begin
  Expected := WriteFile('shared\uShared.pas', 'unit uShared; interface implementation end.');
  Dproj := WriteFile('grp\proj\P.dproj', Format(DPROJ_TPL,
    ['    <DCCReference Include="..\..\shared\uShared.pas"/>']));
  L := TProjectFiles.FromDproj(Dproj, Err);
  try
    Assert.AreEqual('', Err);
    Assert.AreEqual(1, L.Count);
    // GetFullPath-kanonisiert: kein '..' mehr im Ergebnis, exakter Pfad.
    Assert.AreEqual(Expected, L[0]);
    Assert.IsFalse(L[0].Contains('..'), 'Pfad kanonisiert');
  finally
    L.Free;
  end;
end;

procedure TTestProjectFiles.Dproj_XmlEscapes_And_Namespace_Handled;
var
  Dproj : string;
  Err   : string;
  L     : TStringList;
begin
  // Verzeichnis mit '&' im Namen: im XML als &amp; escaped - der Parser
  // muss den entschaerften Pfad liefern (Regex-Scraping wuerde &amp; sehen).
  WriteFile('a&b\uEsc.pas', 'unit uEsc; interface implementation end.');
  Dproj := WriteFile('P.dproj', Format(DPROJ_TPL,
    ['    <DCCReference Include="a&amp;b\uEsc.pas"/>']));
  L := TProjectFiles.FromDproj(Dproj, Err);
  try
    Assert.AreEqual('', Err);
    Assert.AreEqual(1, L.Count);
    Assert.IsTrue(L[0].Contains('a&b'), 'XML-Escape aufgeloest: ' + L[0]);
  finally
    L.Free;
  end;
end;

procedure TTestProjectFiles.Dproj_MacroInclude_SkippedWithWarning;
var
  Dproj : string;
  Err   : string;
  Warn  : TStringList;
  L     : TStringList;
begin
  WriteFile('uReal.pas', 'unit uReal; interface implementation end.');
  Dproj := WriteFile('P.dproj', Format(DPROJ_TPL, [
    '    <DCCReference Include="$(SRC)\uMakro.pas"/>' + sLineBreak +
    '    <DCCReference Include="uReal.pas"/>']));
  Warn := TStringList.Create;
  L := TProjectFiles.FromDproj(Dproj, Err, Warn);
  try
    Assert.AreEqual('', Err);
    Assert.AreEqual(1, L.Count, 'nur die reale Datei');
    Assert.AreEqual(1, Warn.Count);
    Assert.IsTrue(Warn[0].Contains('$(SRC)'), Warn.Text);
  finally
    L.Free;
    Warn.Free;
  end;
end;

procedure TTestProjectFiles.Dproj_NonPasRefs_Ignored;
var
  Dproj : string;
  Err   : string;
  L     : TStringList;
begin
  WriteFile('uOnly.pas', 'unit uOnly; interface implementation end.');
  Dproj := WriteFile('P.dproj', Format(DPROJ_TPL, [
    '    <DCCReference Include="uOnly.pas"/>' + sLineBreak +
    '    <DCCReference Include="lib\foo.dcu"/>' + sLineBreak +
    '    <DCCReference Include="res\bar.res"/>']));
  L := TProjectFiles.FromDproj(Dproj, Err);
  try
    Assert.AreEqual('', Err);
    Assert.AreEqual(1, L.Count, 'nur .pas zaehlt');
  finally
    L.Free;
  end;
end;

procedure TTestProjectFiles.Dproj_DuplicateRefs_CaseInsensitive_Deduped;
var
  Dproj : string;
  Err   : string;
  L     : TStringList;
begin
  WriteFile('uDup.pas', 'unit uDup; interface implementation end.');
  Dproj := WriteFile('P.dproj', Format(DPROJ_TPL, [
    '    <DCCReference Include="uDup.pas"/>' + sLineBreak +
    '    <DCCReference Include="UDUP.PAS"/>']));
  L := TProjectFiles.FromDproj(Dproj, Err);
  try
    Assert.AreEqual('', Err);
    Assert.AreEqual(1, L.Count, 'case-insensitiv dedupliziert');
  finally
    L.Free;
  end;
end;

procedure TTestProjectFiles.Dproj_MissingFile_ErrorMsg_EmptyList;
var
  Err : string;
  L   : TStringList;
begin
  L := TProjectFiles.FromDproj(TPath.Combine(FDir, 'gibtsnicht.dproj'), Err);
  try
    Assert.AreNotEqual('', Err);
    Assert.AreEqual(0, L.Count);
  finally
    L.Free;
  end;
end;

procedure TTestProjectFiles.Dproj_BrokenXml_ErrorMsg_EmptyList;
var
  Dproj : string;
  Err   : string;
  L     : TStringList;
begin
  Dproj := WriteFile('Kaputt.dproj', '<Project><ItemGroup><DCC');
  L := TProjectFiles.FromDproj(Dproj, Err);
  try
    Assert.AreNotEqual('', Err, 'Parse-Fehler gemeldet');
    Assert.AreEqual(0, L.Count);
  finally
    L.Free;
  end;
end;

{ ---- FromGroupproj ---- }

procedure TTestProjectFiles.Group_TwoProjects_SharedUnit_Deduped;
var
  Group : string;
  Err   : string;
  L     : TStringList;
begin
  WriteFile('shared\uShared.pas', 'unit uShared; interface implementation end.');
  WriteFile('a\uA.pas', 'unit uA; interface implementation end.');
  WriteFile('b\uB.pas', 'unit uB; interface implementation end.');
  WriteFile('a\A.dproj', Format(DPROJ_TPL, [
    '    <DCCReference Include="uA.pas"/>' + sLineBreak +
    '    <DCCReference Include="..\shared\uShared.pas"/>']));
  WriteFile('b\B.dproj', Format(DPROJ_TPL, [
    '    <DCCReference Include="uB.pas"/>' + sLineBreak +
    '    <DCCReference Include="..\shared\uShared.pas"/>']));
  Group := WriteFile('G.groupproj', Format(GROUP_TPL, [
    '    <Projects Include="a\A.dproj"/>' + sLineBreak +
    '    <Projects Include="b\B.dproj"/>']));
  L := TProjectFiles.FromGroupproj(Group, Err);
  try
    Assert.AreEqual('', Err);
    Assert.AreEqual(3, L.Count, 'uA + uB + uShared (1x, dedupliziert)');
  finally
    L.Free;
  end;
end;

procedure TTestProjectFiles.Group_RelativeProjectPath_Resolved;
var
  Group : string;
  Err   : string;
  L     : TStringList;
begin
  WriteFile('sub\deep\uD.pas', 'unit uD; interface implementation end.');
  WriteFile('sub\deep\D.dproj', Format(DPROJ_TPL,
    ['    <DCCReference Include="uD.pas"/>']));
  Group := WriteFile('grp\G.groupproj', Format(GROUP_TPL,
    ['    <Projects Include="..\sub\deep\D.dproj"/>']));
  L := TProjectFiles.FromGroupproj(Group, Err);
  try
    Assert.AreEqual('', Err);
    Assert.AreEqual(1, L.Count);
  finally
    L.Free;
  end;
end;

procedure TTestProjectFiles.Group_OneBrokenProject_WarnsAndContinues;
var
  Group : string;
  Err   : string;
  Warn  : TStringList;
  L     : TStringList;
begin
  WriteFile('ok\uOk.pas', 'unit uOk; interface implementation end.');
  WriteFile('ok\Ok.dproj', Format(DPROJ_TPL,
    ['    <DCCReference Include="uOk.pas"/>']));
  Group := WriteFile('G.groupproj', Format(GROUP_TPL, [
    '    <Projects Include="ok\Ok.dproj"/>' + sLineBreak +
    '    <Projects Include="fehlt\Nix.dproj"/>']));
  Warn := TStringList.Create;
  L := TProjectFiles.FromGroupproj(Group, Err, Warn);
  try
    Assert.AreEqual('', Err, 'ein Projekt reicht');
    Assert.AreEqual(1, L.Count);
    Assert.IsTrue(Warn.Count >= 1, 'Warnung fuer das kaputte Projekt');
  finally
    L.Free;
    Warn.Free;
  end;
end;

procedure TTestProjectFiles.Group_NothingResolvable_ErrorMsg;
var
  Group : string;
  Err   : string;
  L     : TStringList;
begin
  Group := WriteFile('G.groupproj', Format(GROUP_TPL,
    ['    <Projects Include="fehlt\Nix.dproj"/>']));
  L := TProjectFiles.FromGroupproj(Group, Err);
  try
    Assert.AreNotEqual('', Err, 'kein Projekt aufloesbar -> Fehler');
    Assert.AreEqual(0, L.Count);
  finally
    L.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestProjectFiles);

end.
