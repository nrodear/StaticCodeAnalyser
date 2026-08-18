unit uTestBaselineScope;

// Tests fuer TBaselineScope (uBaseline) - den Zuschnitt des
// Baseline-Fingerprints als EINEN Wert.
//
// WARUM DIESER TYP UND DIESE TESTS EXISTIEREN
//
// Der Zuschnitt bestand aus zwei unabhaengig setzbaren Prozess-Globals:
// uSCAConsts.BaselinePathFingerprint (Modus) und BaselineFingerprintRoot
// (Wurzel). Ein Code-Review am 2026-08-18 hat gezeigt, dass genau diese
// Trennung der Fehler war:
//
//   * Den MODUS setzte TRepoSettings.ApplyDetectorThresholds - also bei
//     jedem Lauf.
//   * Die WURZEL setzte nur TAnalyserFrame.RefreshBaselineSet - und die
//     steigt frueh aus, solange "nur neue Funde" ausgeschaltet ist.
//
// Beim SCHREIBEN einer Baseline stand die Wurzel damit auf Leerstring. Der
// Token fiel still auf den blossen Dateinamen zurueck; gelesen wurde
// danach mit Relativpfad-Tokens. Ergebnis: das Feature meldete "Baseline
// written (N findings)" und filterte anschliessend nichts. Der Fehler ist
// fail-open und an das Opt-in [Baseline] PathInFingerprint=1 gebunden -
// im Auslieferungszustand schlafend, fuer Opt-in-Nutzer vollstaendig.
//
// WAS DIE TESTS HIER FESTHALTEN
//
// Vier Zusagen, die ein Wert leisten kann und zwei Globals nicht:
//   1. Ohne Pfad-Modus zaehlt nur der Dateiname (Bestandsverhalten).
//   2. Mit Modus UND Wurzel entsteht ein normalisierter Relativpfad.
//   3. Modus OHNE Wurzel ist KEIN Pfad-Modus - Effective sagt das, statt
//      es stillschweigend zurueckfallen zu lassen. Das ist der Kern.
//   4. Die Wurzel-Regel (Projektverzeichnis, sonst Scan-Wurzel) gilt an
//      einer Stelle statt in vier Kopien in CLI, EXE und Plugin.
//
// KEIN Test hier fasst ein Global an. Die bestehenden PathMode_*-Tests in
// uTestFindingFingerprint tun das noch - sie pruefen den alten Weg, und
// genau daran ist der Vertrag damals durchgerutscht: sie setzen die
// Globals selbst, unmittelbar vor dem Aufruf, und lassen die
// Consumer-Seite ("wer setzt die Wurzel, und wann") unbelegt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestBaselineScope = class
  public
    [Test] procedure ByFileName_TokenIsFileNameOnly;
    [Test] procedure ByPath_TokenIsRelativePath;
    [Test] procedure ByPathEmptyRoot_NotEffective;
    [Test] procedure ForProject_RootIsProjectDir;
    [Test] procedure ForProjectWithoutProject_RootIsScanRoot;
    // Review-Nachtrag 2026-08-19.
    [Test] procedure ByPathFileOutsideRoot_FallsBackToFileName;
    [Test] procedure RawDeclaration_BehavesLikeByFileName;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  uBaseline;

const
  // Pfade zur Laufzeit zusammensetzen: ein Literal wie 'C:\proj\Unit1.pas'
  // waere im Selbstscan selbst ein HardcodedPath-Fund.
  DRIVE = 'C:';
  DIR_PROJ = 'proj';
  DIR_SUB = 'sub';
  DIR_SCAN = 'scan';
  FILE_UNIT = 'Unit1.pas';
  // Erwarteter Token im Dateiname-Modus: FileToken normalisiert auf
  // Kleinschreibung. Als Konstante, weil ihn inzwischen vier Tests
  // erwarten und DuplicateString sonst im Selbstscan anschlaegt.
  TOKEN_UNIT = 'unit1.pas';

function DriveRoot: string;
// 'C:' ALLEIN ist laufwerks-relativ: TPath.Combine('C:', 'proj') liefert
// 'C:proj', und ExpandFileName loest das gegen das aktuelle Verzeichnis
// von Laufwerk C auf. Die Tests haetten damit an der CWD des Testlaufs
// gehangen statt an ihrer Eingabe - gruen oder rot je nachdem, wo der
// Runner gerade steht (Review-Minor 2026-08-19). Der Trenner wird aus
// PathDelim zusammengesetzt, damit kein Pfad-Literal im Quelltext steht.
begin
  Result := DRIVE + PathDelim;
end;

function ProjDir: string;
begin
  Result := TPath.Combine(DriveRoot, DIR_PROJ);
end;

procedure TTestBaselineScope.ByFileName_TokenIsFileNameOnly;
// Bestandsverhalten - checkout-tolerant: derselbe Fund in einem anders
// ausgecheckten Baum behaelt seinen Fingerprint.
begin
  Assert.AreEqual(TOKEN_UNIT,
    TBaselineScope.ByFileName.FileToken(TPath.Combine(ProjDir, FILE_UNIT)),
    'ohne Pfad-Modus zaehlt nur der Dateiname');
end;

procedure TTestBaselineScope.ByPath_TokenIsRelativePath;
// Mit Wurzel: normalisierter Relativpfad, damit gleichnamige Dateien in
// verschiedenen Ordnern getrennte Fingerprints bekommen.
begin
  Assert.AreEqual('sub/unit1.pas',
    TBaselineScope.ByPath(ProjDir).FileToken(
      TPath.Combine(TPath.Combine(ProjDir, DIR_SUB), FILE_UNIT)),
    'Relativpfad ab der Wurzel, klein geschrieben, Vorwaerts-Schraegstrich');
end;

procedure TTestBaselineScope.ByPathEmptyRoot_NotEffective;
// DER KERN DES BEFUNDS: Pfad-Modus OHNE Wurzel ist kein Pfad-Modus.
// Genau diese Kombination entstand beim Schreiben einer Baseline. Der
// Unterschied zwischen "angefragt" (IsPathMode) und "wirkt" (Effective)
// ist das, was der Datei-Marker kuenftig melden muss - bisher schrieb er
// den blossen Wunsch, weshalb die Mismatch-Warnung in genau diesem Fall
// schwieg.
var
  Scope : TBaselineScope;
begin
  Scope := TBaselineScope.ByPath('');
  Assert.IsTrue(Scope.IsPathMode, 'der Modus ist angefragt');
  Assert.IsFalse(Scope.Effective, 'ohne Wurzel wirkt er nicht');
  Assert.AreEqual(TOKEN_UNIT,
    Scope.FileToken(TPath.Combine(ProjDir, FILE_UNIT)),
    'und der Token faellt auf den Dateinamen zurueck');
end;

procedure TTestBaselineScope.ForProject_RootIsProjectDir;
// Wurzel-Regel, Fall 1: Projekt-/Gruppendatei vorhanden - ihr Verzeichnis
// gewinnt ueber die Scan-Wurzel.
begin
  Assert.AreEqual(IncludeTrailingPathDelimiter(ProjDir),
    TBaselineScope.ForProject(TPath.Combine(ProjDir, 'App.dproj'),
                              TPath.Combine(DRIVE, DIR_SCAN)).Root,
    'Projektverzeichnis schlaegt die Scan-Wurzel');
end;

procedure TTestBaselineScope.ForProjectWithoutProject_RootIsScanRoot;
// Wurzel-Regel, Fall 2: kein Projekt - dann die Scan-Wurzel.
var
  ScanRoot : string;
begin
  ScanRoot := TPath.Combine(DRIVE, DIR_SCAN);
  Assert.AreEqual(ScanRoot,
    TBaselineScope.ForProject('', ScanRoot).Root,
    'ohne Projektdatei zaehlt die Scan-Wurzel');
end;

procedure TTestBaselineScope.ByPathFileOutsideRoot_FallsBackToFileName;
// Der dokumentierte Rueckfall "Datei nicht unterhalb der Wurzel" war der
// einzige Zweig von FileToken ohne Test. Er ist kein Randfall: sobald ein
// Scan Dateien ausserhalb der Projektwurzel einsammelt (Bibliothekspfade,
// Symlinks, ein zweites Laufwerk), entscheidet er ueber den Fingerprint.
// Faellt er still auf den Dateinamen zurueck, kollidieren gleichnamige
// Units aus verschiedenen Baeumen - genau das, was der Pfad-Modus
// verhindern soll.
var
  Scope : TBaselineScope;
begin
  Scope := TBaselineScope.ByPath(ProjDir);
  Assert.IsTrue(Scope.Effective, 'Modus und Wurzel sind gesetzt');
  Assert.AreEqual(TOKEN_UNIT,
    Scope.FileToken(TPath.Combine(TPath.Combine(DriveRoot, DIR_SCAN),
                                  FILE_UNIT)),
    'ausserhalb der Wurzel bleibt nur der Dateiname');
end;

procedure TTestBaselineScope.RawDeclaration_BehavesLikeByFileName;
// Ein roh deklarierter Record ohne Fabrik-Aufruf. Ohne class operator
// Initialize waere FPathMode uninitialisierter Stack-Inhalt - der
// Zuschnitt haette zufaellig auf Pfad-Modus stehen koennen, und zwar
// genau in der halb gesetzten Form (Modus ja, Wurzel leer), gegen die es
// diesen Typ ueberhaupt gibt.
var
  Scope : TBaselineScope;
begin
  Assert.IsFalse(Scope.IsPathMode, 'Ausgangszustand ist Dateiname-Modus');
  Assert.IsFalse(Scope.Effective, 'und wirkt entsprechend nicht');
  Assert.AreEqual(TOKEN_UNIT,
    Scope.FileToken(TPath.Combine(ProjDir, FILE_UNIT)),
    'Token ist der blosse Dateiname');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestBaselineScope);

end.
