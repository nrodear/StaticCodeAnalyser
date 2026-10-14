unit uTestMarkerTarget;

// Tests fuer TSuppression.MarkerTargetFor (Review 2026-10-14, MAJOR 2):
// wohin ein Werkzeug den Unterdrueck-Marker schreibt. Pascal und
// Konfigurationsdatei: der Zeilenmarker in die Datei selbst vor die
// Fundzeile. Formulardatei (.dfm): der DATEIWEITE Marker in die
// Schwester-Unit (Gegen-Review Welle 1, Major 3 - ein Zeilenmarker vor
// .pas-Zeile N-1 verschoebe mit jedem weiteren Marker die Ziele aller
// tieferen DFM-Marker), und zwar so, dass der LESER (ApplyToFindings ->
// BuildMap, Map[0]) ihn findet; ein zweiter Marker derselben Art wird
// abgelehnt. Eigene Fixture: MarkerLineFor wird in
// uTestHardcodedIpInConfig geprueft, die ist aber mit 16 Tests und Helfern
// schon an der Klassen-Grenze.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMarkerTarget = class
  private
    FDir : string;
    function WriteFile(const ARelPath, AText: string): string;
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure PasAndIni_SameFileSameLine;
    // Der Konsistenz-Beweis: an das gelieferte Ziel geschrieben, entfernt
    // der naechste ApplyToFindings den .dfm-Fund wirklich; ein zweiter
    // Aufruf derselben Form meldet "already".
    [Test] procedure Dfm_FileWideMarkerInUnit_SuppressesOnRescan_ThenAlready;
    // Platz des Markers: vor dem ersten vorhandenen dateiweiten Marker,
    // sonst vor 'interface', sonst Zeile 1; ohne Schwester-Unit Ablehnung.
    [Test] procedure Dfm_Slot_ExistingMarker_Interface_Line1_NoUnit;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  System.Generics.Collections,
  uSCAConsts, uMethodd12, uSuppression,
  uFileTextCache;   // RemoveFile - ApplyToFindings liest wie ein Scan (ohne Stat)

const
  UNIT_SRC =
    'unit Unit1;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure Run;'#13#10 +
    'begin'#13#10 +
    '  Host := ''10.9.8.7'';'#13#10 +
    'end;'#13#10 +
    'end.';
  INI_SRC = '[Database]'#13#10'Server=10.20.30.40';
  // Zeile 1..7; Zeile 2 ist die 'interface'-Zeile.
  FORM_UNIT_SRC =
    'unit Form1;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TForm1 = class'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';
  FORM_DFM_SRC =
    'object Form1: TForm1'#13#10 +
    '  Left = 10'#13#10 +
    '  Caption = ''Hallo'''#13#10 +
    'end';
  MARKER_CAPTION = '// noinspection-file DfmHardcodedCaption';

procedure TTestMarkerTarget.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'sca_mt_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FDir);
end;

procedure TTestMarkerTarget.TearDown;
begin
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
end;

function TTestMarkerTarget.WriteFile(const ARelPath, AText: string): string;
begin
  Result := TPath.Combine(FDir, ARelPath);
  TFile.WriteAllText(Result, AText, TEncoding.UTF8);
end;

procedure TTestMarkerTarget.PasAndIni_SameFileSameLine;
var
  Pas, Ini, Why : string;
  T             : TMarkerTarget;
begin
  Pas := WriteFile('Unit1.pas', UNIT_SRC);
  Ini := WriteFile('App.ini', INI_SRC);
  Assert.IsTrue(TSuppression.MarkerTargetFor(Pas, 6, fkHardcodedIpAddress,
    T, Why), Why);
  Assert.AreEqual(Pas, T.HostFile);
  Assert.AreEqual<Integer>(6, T.Line, 'Pascal: vor die Fundzeile selbst');
  Assert.AreEqual('// noinspection HardcodedIpAddress', T.MarkerLine);
  Assert.IsTrue(TSuppression.MarkerTargetFor(Ini, 2, fkHardcodedIpInConfig,
    T, Why), Why);
  Assert.AreEqual(Ini, T.HostFile);
  Assert.AreEqual<Integer>(2, T.Line);
  Assert.AreEqual('; noinspection HardcodedIpInConfig', T.MarkerLine);
  Assert.IsFalse(TSuppression.MarkerTargetFor(Pas, 0, fkHardcodedIpAddress,
    T, Why), 'ohne Fundzeile kein Ziel');
  Assert.IsTrue(Why <> '', 'mit Grund');
end;

procedure TTestMarkerTarget.Dfm_FileWideMarkerInUnit_SuppressesOnRescan_ThenAlready;
var
  Pas, Dfm, Why : string;
  T             : TMarkerTarget;
  Lines         : TStringList;
  List          : TObjectList<TLeakFinding>;
begin
  Pas := WriteFile('Form1.pas', FORM_UNIT_SRC);
  Dfm := WriteFile('Form1.dfm', FORM_DFM_SRC);
  Assert.IsTrue(TSuppression.MarkerTargetFor(Dfm, 3, fkDfmHardcodedCaption,
    T, Why), Why);
  Assert.AreEqual(Pas, T.HostFile, 'Marker in die Schwester-Unit');
  Assert.AreEqual<Integer>(2, T.Line,
    'vor die interface-Zeile - an keine Fundzeile gebunden');
  Assert.AreEqual(MARKER_CAPTION, T.MarkerLine, 'der dateiweite Marker');

  // Schreiben wie der Host (Zeile VOR T.Line einfuegen) ...
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(Pas, TEncoding.UTF8);
    Lines.Insert(T.Line - 1, T.MarkerLine);
    Lines.SaveToFile(Pas, TEncoding.UTF8);
  finally
    Lines.Free;
  end;
  // Der zweite Marker derselben Sitzung liest mit Stat-Zwang (Major 2) -
  // ohne RemoveFile - und sieht den Marker: kein zweiter.
  Assert.IsFalse(TSuppression.MarkerTargetFor(Dfm, 3, fkDfmHardcodedCaption,
    T, Why), 'schon vorhanden: kein zweiter Marker');
  Assert.IsTrue(Pos('already', Why) > 0, Why);
  // Eine andere Art bekommt ihren Marker direkt VOR den vorhandenen.
  Assert.IsTrue(TSuppression.MarkerTargetFor(Dfm, 2, fkDfmHardcodedDbCreds,
    T, Why), Why);
  Assert.AreEqual<Integer>(2, T.Line, 'vor den vorhandenen Marker');

  // ... und wie der naechste Scan lesen. Der Scan startet mit Clear; hier
  // ersetzt RemoveFile das (gFileTextCache ist nil, bis ein Scan lief).
  if Assigned(gFileTextCache) then
    gFileTextCache.RemoveFile(Pas);
  List := TObjectList<TLeakFinding>.Create(True);
  try
    List.Add(TLeakFinding.New(Dfm, '', 3, 'Caption ''Hallo''',
      fkDfmHardcodedCaption));
    TSuppression.ApplyToFindings(List);
    Assert.AreEqual<Integer>(0, List.Count,
      'der .dfm-Fund ist unterdrueckt, der Marker gilt als benutzt');
  finally
    List.Free;
  end;
end;

procedure TTestMarkerTarget.Dfm_Slot_ExistingMarker_Interface_Line1_NoUnit;
var
  Dfm, Why : string;
  T        : TMarkerTarget;
begin
  // Keine Schwester-Unit: nie in die .dfm schreiben.
  Dfm := WriteFile('Lonely.dfm', FORM_DFM_SRC);
  Assert.IsFalse(TSuppression.MarkerTargetFor(Dfm, 2, fkDfmHardcodedCaption,
    T, Why));
  Assert.IsTrue(Pos('no unit', Why) > 0, Why);
  // Ohne Fundzeile kein Ziel - wie bei Pascal.
  WriteFile('Form2.pas', 'unit Form2;'#13#10#13#10'interface'#13#10 +
    'implementation'#13#10'// noinspection-file DfmHardcodedDbCreds'#13#10 +
    '// noinspection-file DfmHardcodedCaption'#13#10'end.');
  Dfm := WriteFile('Form2.dfm', FORM_DFM_SRC);
  Assert.IsFalse(TSuppression.MarkerTargetFor(Dfm, 0, fkDfmSqlFromUserInput,
    T, Why));
  Assert.IsTrue(Pos('no source line', Why) > 0, Why);
  // Vorhandene dateiweite Marker: eine neue Art kommt vor den ERSTEN
  // (Zeile 5), nicht vor 'interface'.
  Assert.IsTrue(TSuppression.MarkerTargetFor(Dfm, 3, fkDfmSqlFromUserInput,
    T, Why), Why);
  Assert.AreEqual<Integer>(5, T.Line, 'vor den ersten vorhandenen Marker');
  Assert.AreEqual('// noinspection-file DfmSqlFromUserInput', T.MarkerLine);
  // Dieselbe Art wie der zweite Marker: schon vorhanden.
  Assert.IsFalse(TSuppression.MarkerTargetFor(Dfm, 3, fkDfmHardcodedCaption,
    T, Why));
  Assert.IsTrue(Pos('already', Why) > 0, Why);
  // Der Marker zaehlt nur, wo BuildMap ihn liest: im String nicht.
  WriteFile('Form3.pas', 'unit Form3;'#13#10'interface'#13#10 +
    'const S = ''// noinspection-file DfmHardcodedCaption'';'#13#10 +
    'implementation'#13#10'end.');
  Dfm := WriteFile('Form3.dfm', FORM_DFM_SRC);
  Assert.IsTrue(TSuppression.MarkerTargetFor(Dfm, 3, fkDfmHardcodedCaption,
    T, Why), Why);
  Assert.AreEqual<Integer>(2, T.Line, 'Marker im String zaehlt nicht');
  // Ohne 'interface' (kein Unit-Kopf): Zeile 1.
  WriteFile('Form4.pas', 'program Form4;'#13#10'begin'#13#10'end.');
  Dfm := WriteFile('Form4.dfm', FORM_DFM_SRC);
  Assert.IsTrue(TSuppression.MarkerTargetFor(Dfm, 3, fkDfmHardcodedCaption,
    T, Why), Why);
  Assert.AreEqual<Integer>(1, T.Line, 'ohne interface-Zeile: Zeile 1');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMarkerTarget);

end.
