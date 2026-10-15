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
// Charge B2S-a: der Index fragt die eine Netzpfad-Regel uRdxPaths - das
// Netzlaufwerk kommt ueber deren Naht (SetRdxRemoteDriveTest; bis dahin
// eine eigene Naht IsRemote des Index), und ein lokales Verzeichnis im
// Win32-Namensraum ('\\?\C:\..') wird gelesen (bis dahin "Netzpfad").

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
    [Test] procedure SearchPath_NoBaseDir_LikeExpandFileName;
    [Test] procedure UncDir_NotRead_AnswerOpen;
    [Test] procedure RemoteDir_NotRead_AnswerOpen;
    [Test] procedure NoNetwork_NoReason;
    [Test] procedure LongLocalDir_Read;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxScopeTable,
  uRdxPaths,         // SetRdxRemoteDriveTest (Naht fuer das Netzlaufwerk)
  uTestRdxTextKit;   // NewTempDir, RemoveTree

const
  // Das Netzlaufwerk der Attrappe (FakeRemoteDrive).
  DRIVE_Q = 'Q:';

// Ein frisches Verzeichnis TEMP\rdx_fa_<GUID>\ (angelegt).
function FreshDir: string;
begin
  Result := NewTempDir('rdx_fa_');
end;

// Eine leere Datei APath.
procedure Touch(const APath: string);
begin
  ForceDirectories(ExtractFilePath(APath));
  TFileStream.Create(APath, fmCreate).Free;
end;

// Attrappe fuer GetDriveType in der Netzpfad-Regel (uRdxPaths): nur Q: ist
// ein Netzlaufwerk.
function FakeRemoteDrive(const ADrive: string): Boolean;
begin
  Result := SameText(ADrive, DRIVE_Q);
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

procedure TTestRdxProjectUnits.SearchPath_NoBaseDir_LikeExpandFileName;
var
  D, Old : string;
  U      : TRdxProjectUnits;
begin
  // Ohne Projektverzeichnis (ungespeichertes Projekt) bleibt ein relativer
  // Eintrag relativ zum aktuellen Verzeichnis, wie bis R1-02 - nicht zur
  // Wurzel des Laufwerks ('\lib').
  D := FreshDir;
  Old := GetCurrentDir;
  U := TRdxProjectUnits.Create;
  try
    Touch(D + 'lib' + PathDelim + 'CwdUnit.pas');
    SetCurrentDir(D);
    U.AddSearchPath('lib', '');
    Assert.IsTrue(U.Knows('CwdUnit'));
  finally
    SetCurrentDir(Old);
    U.Free;
    RemoveTree(D);
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
  D, Net : string;
  U      : TRdxProjectUnits;
begin
  // Das Netzlaufwerk ueber die Naht der Regel (Q: gilt als Netzlaufwerk).
  D := FreshDir;
  Net := DRIVE_Q + PathDelim + 'lib';
  SetRdxRemoteDriveTest(FakeRemoteDrive);
  U := TRdxProjectUnits.Create;
  try
    Touch(D + 'Local.pas');
    U.AddDir(D);
    Assert.IsTrue(U.Knows('Local'), 'lokal: gelesen');
    Assert.IsFalse(U.Knows('Net'), 'lokal: nur was da liegt');
    U.AddSearchPath(Net, D);
    Assert.AreEqual(Net, U.Unreadable);
    Assert.IsTrue(U.Knows('Net'), 'Netzlaufwerk nicht gelesen');
    Assert.IsTrue(U.Knows('Elsewhere'), 'jede Antwort offen');
    Assert.IsTrue(Pos(Net, U.UnreadableReason) > 0, U.UnreadableReason);
  finally
    SetRdxRemoteDriveTest(nil);
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

procedure TTestRdxProjectUnits.LongLocalDir_Read;
var
  D, Long : string;
  U       : TRdxProjectUnits;
begin
  // Charge B2S-a: '\\?\C:\..' beginnt mit zwei Trennern und galt dem Index
  // als UNC - ein lokales Verzeichnis, lang geschrieben, blieb ungelesen
  // (jede Antwort offen, der uses-Eintrag gesperrt). Gegen 9713942b rot.
  D := FreshDir;
  Long := PathDelim + PathDelim + '?' + PathDelim + D;
  U := TRdxProjectUnits.Create;
  try
    Touch(D + 'Mine.pas');
    U.AddDir(Long);
    Assert.AreEqual('', U.Unreadable, 'lokal, nur lang geschrieben');
    Assert.IsTrue(U.Knows('Mine'), 'gelesen');
    Assert.IsFalse(U.Knows('Absent'));
    // Im Suchpfad bleibt die Form absolut - kein Projektverzeichnis davor.
    Touch(D + 'sub' + PathDelim + 'Deep.pas');
    U.AddSearchPath(Long + 'sub', PathDelim + 'elsewhere');
    Assert.AreEqual('', U.Unreadable, 'Suchpfad lang geschrieben');
    Assert.IsTrue(U.Knows('Deep'), 'absolut gelesen');
  finally
    U.Free;
    RemoveTree(D);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxProjectUnits);

end.
