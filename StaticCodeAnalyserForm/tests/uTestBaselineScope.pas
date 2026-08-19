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
//
// NACHTRAG SCHRITTE 2-6 (2026-08-19): Write, Apply und
// TBaselineSet.LoadFromFile nehmen den Zuschnitt seither als expliziten
// Parameter. Drei Vertraege sind damit NEU und werden unten festgehalten:
//   5. Write/Apply rechnen mit dem UEBERGEBENEN Zuschnitt - die
//      Prozess-Globals bleiben in diesen Tests unangetastet auf Default.
//   6. Der pathFingerprint-Marker der Datei meldet die WIRKUNG
//      (Effective), nicht den Wunsch (IsPathMode) - beim halb gesetzten
//      Zuschnitt stand bisher eine Luege in der Datei.
//   7. TBaselineSet speichert den Zuschnitt beim Laden; Contains haengt
//      nicht mehr am Prozess-Zustand zum Abfragezeitpunkt.

interface

uses
  DUnitX.TestFramework,
  uMethodd12;

type
  [TestFixture]
  TTestBaselineScope = class
  strict private
    // Zieldatei des laufenden Tests - TearDown raeumt sie weg. Das haelt
    // die Testruempfe frei von try-in-try-Aufraeumketten.
    FTempFile : string;
    function TempBaselineFile: string;
    function NewFinding(const ARoot: string): TLeakFinding;
  public
    [TearDown] procedure TearDown;
    [Test] procedure ByFileName_TokenIsFileNameOnly;
    [Test] procedure ByPath_TokenIsRelativePath;
    [Test] procedure ByPathEmptyRoot_NotEffective;
    [Test] procedure ForProject_RootIsProjectDir;
    [Test] procedure ForProjectWithoutProject_RootIsScanRoot;
    // Review-Nachtrag 2026-08-19.
    [Test] procedure ByPathFileOutsideRoot_FallsBackToFileName;
    [Test] procedure RawDeclaration_BehavesLikeByFileName;
    // Schritte 2-6: Vertraege der scope-expliziten Operationen.
    [Test] procedure WriteApply_RoundTripWithExplicitScope;
    [Test] procedure HalfSetScope_MarkerSaysNotEffective;
    [Test] procedure BaselineSet_ContainsUsesLoadedScope;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  System.Generics.Collections,
  uSCAConsts, uBaseline;

const
  // Pfade zur Laufzeit zusammensetzen: ein Literal wie 'C:\proj\Unit1.pas'
  // waere im Selbstscan selbst ein HardcodedPath-Fund.
  DRIVE = 'C:';
  DIR_PROJ = 'proj';
  DIR_SUB = 'sub';
  DIR_SCAN = 'scan';
  FILE_UNIT = 'Unit1.pas';
  // Fixtures der Roundtrip-Tests (Schritte 2-6): Wurzel unterhalb von
  // TempPath, Methoden-/Detail-Konstanten gegen DuplicateString.
  DIR_SCOPE_ROOT = 'sca_scope_root';
  METHOD_NAME    = 'M';
  DETAIL_TXT     = 'detail';
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

procedure TTestBaselineScope.TearDown;
// Zieldatei des Tests wegzuraeumen ist Rahmen-Arbeit: hier statt in
// jedem Test ein eigenes finally (das waere in jedem Rumpf eine
// try-in-try-Kette nur fuers Aufraeumen).
begin
  if (FTempFile <> '') and TFile.Exists(FTempFile) then
  begin
    TFile.Delete(FTempFile);
  end;
  FTempFile := '';
end;

function TTestBaselineScope.TempBaselineFile: string;
// Eindeutiger Zielpfad pro Testlauf - gemerkt in FTempFile, damit
// TearDown die Datei nach dem Test wegraeumt.
begin
  Result := TPath.Combine(TPath.GetTempPath,
    'sca_scope_' + TGuid.NewGuid.ToString + '.baseline.json');
  FTempFile := Result;
end;

function TTestBaselineScope.NewFinding(const ARoot: string): TLeakFinding;
// Fund unterhalb von ARoot\sub. Die Quelldatei existiert BEWUSST nicht:
// ohne lesbare Datei entsteht kein contextHash, und die Tests belegen die
// Legacy-Fingerprint-Strecke - genau die haengt am Zuschnitt.
begin
  Result := TLeakFinding.New(
    TPath.Combine(TPath.Combine(ARoot, DIR_SUB), FILE_UNIT),
    METHOD_NAME, 10, DETAIL_TXT, fkEmptyBlock);
end;

procedure TTestBaselineScope.WriteApply_RoundTripWithExplicitScope;
// NEUER VERTRAG (Schritte 2-6): Write und Apply rechnen mit dem
// UEBERGEBENEN Zuschnitt. Die Prozess-Globals stehen waehrend des ganzen
// Tests auf Default (Dateiname-Modus) - vorher waere dieser Pfad-Modus-
// Roundtrip deshalb still im Dateinamen-Modus gelaufen.
var
  Fn      : string;
  Root    : string;
  List    : TObjectList<TLeakFinding>;
  Dropped : Integer;
begin
  Root := TPath.Combine(TPath.GetTempPath, DIR_SCOPE_ROOT);
  Fn   := TempBaselineFile;
  List := TObjectList<TLeakFinding>.Create(True);
  try
    List.Add(NewFinding(Root));
    Assert.AreEqual<Integer>(1,
      TBaseline.Write(List, Fn, TBaselineScope.ByPath(Root)),
      'ein Eintrag geschrieben');
  finally
    List.Free;
  end;
  Assert.Contains(TFile.ReadAllText(Fn), '"pathFingerprint": true',
    'der Marker kommt aus dem Zuschnitt, nicht aus den Globals');
  List := TObjectList<TLeakFinding>.Create(True);
  try
    List.Add(NewFinding(Root));
    Dropped := TBaseline.Apply(List, Fn, TBaselineScope.ByPath(Root));
    Assert.AreEqual<Integer>(1, Dropped,
      'gleicher Zuschnitt beim Lesen - der Fund matcht');
  finally
    List.Free;
  end;
end;

procedure TTestBaselineScope.HalfSetScope_MarkerSaysNotEffective;
// NEUER VERTRAG (Schritte 2-6): der pathFingerprint-Marker meldet die
// WIRKUNG (Effective), nicht den Wunsch (IsPathMode). Der halb gesetzte
// Zuschnitt schreibt Dateinamen-Tokens - genau das muss die Datei auch
// behaupten. Bisher stand der Wunsch im Marker: ein Dateiname-Leser
// bekam die Mismatch-Warnung NICHT und die Tokens matchten trotzdem -
// die stille Form von Befund A.
var
  Fn       : string;
  List     : TObjectList<TLeakFinding>;
  Warnings : TStringList;
  Dropped  : Integer;
begin
  Fn := TempBaselineFile;
  List := TObjectList<TLeakFinding>.Create(True);
  try
    List.Add(NewFinding(TPath.Combine(TPath.GetTempPath, DIR_SCOPE_ROOT)));
    TBaseline.Write(List, Fn, TBaselineScope.ByPath(''));
  finally
    List.Free;
  end;
  Assert.Contains(TFile.ReadAllText(Fn), '"pathFingerprint": false',
    'halb gesetzter Zuschnitt wirkt nicht - der Marker sagt das');
  List := TObjectList<TLeakFinding>.Create(True);
  Warnings := TStringList.Create;
  try
    List.Add(NewFinding(TPath.Combine(TPath.GetTempPath, DIR_SCOPE_ROOT)));
    Dropped := TBaseline.Apply(List, Fn, TBaselineScope.ByFileName,
      Warnings);
    Assert.AreEqual(0, Warnings.Count,
      'Dateiname-Tokens und Dateiname-Leser passen - keine Warnung');
    Assert.AreEqual<Integer>(1, Dropped,
      'und der Fund matcht ueber den Dateinamen-Token');
  finally
    Warnings.Free;
    List.Free;
  end;
end;

procedure TTestBaselineScope.BaselineSet_ContainsUsesLoadedScope;
// NEUER VERTRAG (Schritte 2-6): LoadFromFile speichert den Zuschnitt,
// Contains rechnet damit. Der im Pfad-Modus geschriebene und mit Pfad-
// Zuschnitt geladene Fund muss unter Default-Globals matchen - vorher
// hing Contains am Prozess-Zustand zum Abfragezeitpunkt, und ein
// zwischenzeitlicher Lauf konnte den Anzeige-Filter still entwerten.
var
  Fn   : string;
  Root : string;
  List : TObjectList<TLeakFinding>;
  BSet : TBaselineSet;
  F    : TLeakFinding;
begin
  Root := TPath.Combine(TPath.GetTempPath, DIR_SCOPE_ROOT);
  Fn   := TempBaselineFile;
  List := TObjectList<TLeakFinding>.Create(True);
  try
    List.Add(NewFinding(Root));
    TBaseline.Write(List, Fn, TBaselineScope.ByPath(Root));
  finally
    List.Free;
  end;
  F    := NewFinding(Root);
  BSet := TBaselineSet.Create;
  try
    Assert.AreEqual<Integer>(1,
      BSet.LoadFromFile(Fn, TBaselineScope.ByPath(Root)),
      'ein Fingerprint geladen');
    Assert.IsTrue(BSet.Contains(F),
      'Contains rechnet mit dem Lade-Zuschnitt, nicht mit den Globals');
  finally
    BSet.Free;
    F.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestBaselineScope);

end.
