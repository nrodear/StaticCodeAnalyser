unit uTestMarkerTarget;

// Tests fuer TSuppression.MarkerTargetFor (Review 2026-10-14, MAJOR 2):
// wohin ein Werkzeug den Unterdrueck-Marker schreibt. Pascal und
// Konfigurationsdatei: in die Datei selbst vor die Fundzeile. Formular-
// datei (.dfm): in die Schwester-Unit, und zwar so, dass der LESER
// (ApplyToFindings haelt die .dfm-Fundzeile gegen die Zielzeilen der
// Marker in der .pas) den Marker auch findet - sonst Ablehnung mit Grund.
// Eigene Fixture: MarkerLineFor wird in uTestHardcodedIpInConfig geprueft,
// die ist aber mit 16 Tests und Helfern schon an der Klassen-Grenze.

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
    // der naechste ApplyToFindings den .dfm-Fund wirklich.
    [Test] procedure Dfm_UnitAboveLine_SuppressesOnRescan;
    [Test] procedure Dfm_Rejected_NoUnit_EmptyLine_Comment_Line1_TooShort;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  System.Generics.Collections,
  uSCAConsts, uMethodd12, uSuppression,
  uFileTextCache;   // RemoveFile - der Test schreibt die Unit nach dem Lesen um

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
  // Zeile 1..7; Zeile 2 ('interface') ist Code, Zeile 3 ('type') auch.
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

procedure TTestMarkerTarget.Dfm_UnitAboveLine_SuppressesOnRescan;
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
    'vor Zeile 2 der Unit: der Marker zielt dann auf Zeile 3');
  Assert.AreEqual('// noinspection DfmHardcodedCaption', T.MarkerLine);

  // Schreiben wie der Host (Zeile VOR T.Line einfuegen) ...
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(Pas, TEncoding.UTF8);
    Lines.Insert(T.Line - 1, T.MarkerLine);
    Lines.SaveToFile(Pas, TEncoding.UTF8);
  finally
    Lines.Free;
  end;
  gFileTextCache.RemoveFile(Pas);   // MarkerTargetFor hat die alte Fassung gelesen

  // ... und wie der naechste Scan lesen.
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

procedure TTestMarkerTarget.Dfm_Rejected_NoUnit_EmptyLine_Comment_Line1_TooShort;
var
  Dfm, Why : string;
  T        : TMarkerTarget;
begin
  // Keine Schwester-Unit: nie in die .dfm schreiben.
  Dfm := WriteFile('Lonely.dfm', FORM_DFM_SRC);
  Assert.IsFalse(TSuppression.MarkerTargetFor(Dfm, 2, fkDfmHardcodedCaption,
    T, Why));
  Assert.IsTrue(Pos('no unit', Why) > 0, Why);

  WriteFile('Form2.pas', 'unit Form2;'#13#10#13#10'interface'#13#10 +
    '// nur Kommentar'#13#10'implementation'#13#10'end.');
  Dfm := WriteFile('Form2.dfm', FORM_DFM_SRC);
  // Fundzeile 3: Zeile 2 der Unit ist leer - der Marker traefe Zeile 3
  // nicht (seine Zielzeile waere 4).
  Assert.IsFalse(TSuppression.MarkerTargetFor(Dfm, 3, fkDfmHardcodedCaption,
    T, Why));
  Assert.IsTrue(Pos('empty or a comment', Why) > 0, Why);
  // Fundzeile 5: Zeile 4 der Unit ist ein Kommentar - SCA165 meldete den
  // Marker sonst als unbenutzt.
  Assert.IsFalse(TSuppression.MarkerTargetFor(Dfm, 5, fkDfmHardcodedCaption,
    T, Why));
  Assert.IsTrue(Pos('empty or a comment', Why) > 0, Why);
  // Fundzeile 1: keine Zeile davor.
  Assert.IsFalse(TSuppression.MarkerTargetFor(Dfm, 1, fkDfmHardcodedCaption,
    T, Why));
  Assert.IsTrue(Pos('line 1', Why) > 0, Why);
  // Fundzeile 50: die Unit ist kuerzer.
  Assert.IsFalse(TSuppression.MarkerTargetFor(Dfm, 50, fkDfmHardcodedCaption,
    T, Why));
  Assert.IsTrue(Pos('lines', Why) > 0, Why);
  // Fundzeile 4: Zeile 3 ('interface') ist Code - das geht.
  Assert.IsTrue(TSuppression.MarkerTargetFor(Dfm, 4, fkDfmHardcodedCaption,
    T, Why), Why);
  Assert.AreEqual<Integer>(3, T.Line);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMarkerTarget);

end.
