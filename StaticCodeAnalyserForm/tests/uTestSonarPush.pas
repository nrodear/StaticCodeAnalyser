unit uTestSonarPush;

// Tests fuer uSonarPush - den Per-Issue-Push ins .sonar\external-Verzeichnis.
//
// Warum es diese Unit gibt: uSonarPush hatte bis 2026-08-09 KEINEN einzigen
// Test, und ausgerechnet dort sass der folgenreichste Fehler des
// Sonar-Wegs. Der Ordner wurde nie geleert, der sonar-scanner sammelt aber
// ALLE .json daraus ein - ein behobener Fund kam beim naechsten Push
// wortlos wieder ins Dashboard. Diese Klasse Fehler faellt niemandem auf,
// weil jede einzelne Datei fuer sich gueltig ist.
//
// Der Push selbst laeuft nur ueber das GUI-Export-Menue, aus der CLI ist er
// nicht erreichbar - hier ist der Test also die einzige Absicherung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSonarPush = class
  private
    FDir : string;
    function TouchFile(const AName: string): string;
    function CountFiles(const AMask: string): Integer;
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure ClearExternalDir_RemovesJsonFiles;
    [Test] procedure ClearExternalDir_KeepsForeignFiles;
    [Test] procedure ClearExternalDir_OnMissingDir_ReturnsZero;
    [Test] procedure WriteIndividual_LeavesOnlyCurrentPush;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Generics.Collections,
  uMethodd12, uSCAConsts, uSonarPush;

const
  STALE_JSON = 'error-uAlt-L1-deadbeef.json';
  MASK_JSON  = '*.json';
  KEEP_TXT   = 'notizen.txt';

function TTestSonarPush.TouchFile(const AName: string): string;
begin
  Result := TPath.Combine(FDir, AName);
  TFile.WriteAllText(Result, '{}', TEncoding.UTF8);
end;

function TTestSonarPush.CountFiles(const AMask: string): Integer;
begin
  Result := Length(TDirectory.GetFiles(FDir, AMask));
end;

procedure TTestSonarPush.Setup;
// GUID-Verzeichnis: ein zweiter TestProject-Prozess hat hier schon einmal
// ein festes Temp-Verzeichnis mitten im Lauf weggeloescht.
begin
  FDir := TPath.Combine(TPath.GetTempPath,
    'sca_push_' + TGuid.NewGuid.ToString.Replace('{', '').Replace('}', ''));
  ForceDirectories(FDir);
end;

procedure TTestSonarPush.TearDown;
begin
  if (FDir <> '') and TDirectory.Exists(FDir) then
  begin
    TDirectory.Delete(FDir, True);
  end;
end;

procedure TTestSonarPush.ClearExternalDir_RemovesJsonFiles;
var
  Removed : Integer;
begin
  TouchFile(STALE_JSON);
  TouchFile('warning-uAlt2-L9-cafe0000.json');
  Removed := TSonarPush.ClearExternalDir(FDir);
  Assert.AreEqual<Integer>(2, Removed, 'beide .json muessen geloescht werden');
  Assert.AreEqual<Integer>(0, CountFiles(MASK_JSON));
end;

procedure TTestSonarPush.ClearExternalDir_KeepsForeignFiles;
// Nur *.json und nicht rekursiv - was ein Nutzer sonst im Ordner ablegt,
// geht ihn etwas an und uns nichts.
begin
  TouchFile(STALE_JSON);
  TouchFile(KEEP_TXT);
  TSonarPush.ClearExternalDir(FDir);
  Assert.AreEqual<Integer>(0, CountFiles(MASK_JSON));
  Assert.AreEqual<Integer>(1, CountFiles('*.txt'), 'fremde Datei muss bleiben');
end;

procedure TTestSonarPush.ClearExternalDir_OnMissingDir_ReturnsZero;
// Erster Push in ein frisches Repo: den Ordner gibt es noch nicht.
begin
  Assert.AreEqual<Integer>(0,
    TSonarPush.ClearExternalDir(TPath.Combine(FDir, 'gibtsnicht')));
end;

procedure TTestSonarPush.WriteIndividual_LeavesOnlyCurrentPush;
// Der eigentliche Regressionstest: nach dem Push darf im Ordner NUR stehen,
// was gerade gepusht wurde. Vorher blieb die Altlast liegen und der
// Scanner holte den behobenen Fund zurueck ins Dashboard.
var
  F       : TLeakFinding;
  Ext     : string;
  Written : Integer;
begin
  // Altlast eines frueheren Pushs an genau der Stelle, an der sie entsteht.
  Ext := TSonarPush.EnsureExternalDir(FDir);
  TFile.WriteAllText(TPath.Combine(Ext, STALE_JSON), '{}', TEncoding.UTF8);

  F := TLeakFinding.Create;
  try
    F.SetKind(fkMemoryLeak);
    F.FileName   := 'src\uNeu.pas';
    F.LineNumber := '12';
    F.MissingVar := 'leak';
    Written := TSonarPush.WriteIndividual([F], FDir, FDir);
  finally
    F.Free;
  end;

  Assert.AreEqual<Integer>(1, Written);
  Assert.AreEqual<Integer>(1, Length(TDirectory.GetFiles(Ext, MASK_JSON)),
    'nach dem Push darf nur die Datei dieses Pushs im Ordner liegen');
  Assert.IsFalse(TFile.Exists(TPath.Combine(Ext, STALE_JSON)),
    'die Altlast des frueheren Pushs muss weg sein');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSonarPush);

end.
