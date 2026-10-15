unit uTestRdxProjectUnits;

// Review reDelphix R1-02 (Quick-Fix-Modul, 2026-10-15): der Index der
// Projekt-Units fuer 'uses: X -> Scope.X' (TRdxProjectUnits in
// uRdxScopeTable). Bis dahin fragte uRdxEditor.ProjectHasUnit je
// uses-Eintrag alle Module und Suchpfade aller Projekte der Gruppe ueber
// die ToolsAPI ab - im Hauptthread, auch fuer die Gluehbirne und auch auf
// Netzpfaden. Jetzt fuellt uRdxEditor.ProjectUnits den Index einmal je
// Menueaufbau; hier geprueft: Module (Pfad, Endung, gross/klein egal),
// Dateien in den Verzeichnissen, der Suchpfad (relativ, absolut, Makros
// aussen vor) und dass ein Netzpfad nicht gelesen wird, sondern jede
// Antwort offen laesst. Die Verzeichnisse liegen unter TEMP\rdx_fa_<GUID>.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxProjectUnits = class
  public
    [Test] procedure Knows_ModuleNames;
    [Test] procedure Knows_UnitFileInDir;
    [Test] procedure SearchPath_RelativeAbsoluteMacro;
    [Test] procedure UncDir_NotRead_AnswerOpen;
    [Test] procedure RemoteDir_NotRead_AnswerOpen;
    [Test] procedure NoNetwork_NoReason;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxScopeTable;

// Ein frisches Verzeichnis TEMP\rdx_fa_<GUID>\ (angelegt).
function FreshDir: string;
var
  G : TGUID;
begin
  CreateGUID(G);
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP'))
    + 'rdx_fa_' + GUIDToString(G) + PathDelim;
  ForceDirectories(Result);
end;

// Loescht den Baum ADir (mit Trenner) samt Inhalt.
procedure RemoveTree(const ADir: string);
var
  SR : TSearchRec;
begin
  if FindFirst(ADir + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then
        Continue;
      if (SR.Attr and faDirectory) <> 0 then
        RemoveTree(ADir + SR.Name + PathDelim)
      else
        DeleteFile(ADir + SR.Name);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
  RemoveDir(ADir);
end;

// Eine leere Datei APath.
procedure Touch(const APath: string);
begin
  ForceDirectories(ExtractFilePath(APath));
  TFileStream.Create(APath, fmCreate).Free;
end;

// Attrappe fuer den Netzlaufwerk-Test von uRdxEditor (GetDriveType).
function FakeRemote(const APath: string): Boolean;
begin
  Result := Pos('remote_drive', LowerCase(APath)) > 0;
end;

procedure TTestRdxProjectUnits.Knows_ModuleNames;
var
  U : TRdxProjectUnits;
begin
  U := TRdxProjectUnits.Create;
  try
    U.AddModule('src' + PathDelim + 'Types.pas');
    U.AddModule('Main.dpr');
    U.AddModule('lib' + PathDelim + 'My.Utils.pas');
    Assert.IsTrue(U.Knows('types'), 'Pfad und Endung weg, gross/klein egal');
    Assert.IsTrue(U.Knows('TYPES'));
    Assert.IsTrue(U.Knows('Main'), 'auch das Programm');
    Assert.IsTrue(U.Knows('My.Utils'), 'Punktname');
    Assert.IsFalse(U.Knows('Windows'));
    Assert.IsFalse(U.Knows(''), 'leerer Name');
  finally
    U.Free;
  end;
end;

procedure TTestRdxProjectUnits.Knows_UnitFileInDir;
var
  D : string;
  U : TRdxProjectUnits;
begin
  D := FreshDir;
  U := TRdxProjectUnits.Create;
  try
    Touch(D + 'Mine.pas');
    Touch(D + 'Other.pp');
    Touch(D + 'Form.dfm');
    U.AddDir(D);
    Assert.IsTrue(U.Knows('Mine'));
    Assert.IsTrue(U.Knows('other'), '.pp zaehlt, gross/klein egal');
    Assert.IsFalse(U.Knows('Form'), 'nur .pas und .pp');
    Assert.IsFalse(U.Knows('Absent'));
    Assert.AreEqual('', U.Unreadable);
  finally
    U.Free;
    RemoveTree(D);
  end;
end;

procedure TTestRdxProjectUnits.SearchPath_RelativeAbsoluteMacro;
var
  Base, Abs : string;
  U         : TRdxProjectUnits;
begin
  Base := FreshDir;
  Abs  := FreshDir;
  U := TRdxProjectUnits.Create;
  try
    Touch(Base + 'lib' + PathDelim + 'LibUnit.pas');
    Touch(Base + 'deep' + PathDelim + 'x' + PathDelim + 'DeepUnit.pas');
    Touch(Abs + 'AbsUnit.pas');
    // Ein Verzeichnis, das wie ein Makro heisst: Makro-Eintraege liest der
    // Index nie (dort liegt die Bibliothek, nicht das Projekt).
    Touch(Base + '$(BDS)' + PathDelim + 'MacroUnit.pas');
    U.AddSearchPath(' lib ;deep' + PathDelim + 'y' + PathDelim + '..'
      + PathDelim + 'x;;' + Abs + ';$(BDS)', Base);
    Assert.IsTrue(U.Knows('LibUnit'), 'relativ zum Projekt, Leerraum weg');
    Assert.IsTrue(U.Knows('DeepUnit'), '..\ aufgeloest');
    Assert.IsTrue(U.Knows('AbsUnit'), 'absolut');
    Assert.IsFalse(U.Knows('MacroUnit'), 'Makro-Eintrag bleibt aussen vor');
    Assert.AreEqual('', U.Unreadable);
  finally
    U.Free;
    RemoveTree(Base);
    RemoveTree(Abs);
  end;
end;

procedure TTestRdxProjectUnits.UncDir_NotRead_AnswerOpen;
var
  Unc : string;
  U   : TRdxProjectUnits;
begin
  Unc := PathDelim + PathDelim + 'srv' + PathDelim + 'share' + PathDelim
    + 'lib';
  U := TRdxProjectUnits.Create;
  try
    U.AddModule('Main.dpr');
    U.AddSearchPath('first;' + Unc, GetEnvironmentVariable('TEMP'));
    U.AddDir(Unc + '2');
    Assert.AreEqual(Unc, U.Unreadable, 'der erste Netzpfad');
    Assert.IsTrue(U.Knows('AnyName'), 'ungelesen: offen, kein Angebot');
    Assert.IsTrue(Pos(Unc, U.UnreadableReason) > 0, U.UnreadableReason);
    Assert.IsTrue(Pos('Netzpfad', U.UnreadableReason) > 0, U.UnreadableReason);
  finally
    U.Free;
  end;
end;

procedure TTestRdxProjectUnits.RemoteDir_NotRead_AnswerOpen;
var
  D : string;
  U : TRdxProjectUnits;
begin
  D := FreshDir;
  U := TRdxProjectUnits.Create;
  try
    Touch(D + 'remote_drive' + PathDelim + 'Net.pas');
    U.IsRemote := FakeRemote;
    U.AddDir(D);
    Assert.IsFalse(U.Knows('Net'), 'lokal: nur was da liegt');
    U.AddSearchPath('remote_drive', D);
    Assert.AreEqual(D + 'remote_drive', U.Unreadable);
    Assert.IsTrue(U.Knows('Net'), 'Netzlaufwerk nicht gelesen');
    Assert.IsTrue(U.Knows('Elsewhere'), 'jede Antwort offen');
  finally
    U.Free;
    RemoveTree(D);
  end;
end;

procedure TTestRdxProjectUnits.NoNetwork_NoReason;
var
  U : TRdxProjectUnits;
begin
  U := TRdxProjectUnits.Create;
  try
    U.AddSearchPath('', 'C');
    Assert.AreEqual('', U.UnreadableReason);
    Assert.IsFalse(U.Knows('Anything'), 'nichts bekannt');
  finally
    U.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxProjectUnits);

end.
