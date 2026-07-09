unit uTestUnusedUses;

// Tests fuer den TUnusedUsesDetector.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestSrcBuilder,
  uTestFindingHelper;

type
  // ---- UnusedUses (TUnusedUsesDetector) -----------------------------------------------
  [TestFixture]
  TTestUnusedUses = class
  public
    // --- Grundfunktionen ---
    [Test] procedure Uses_UnknownUnit_ReportsWarning;
    [Test] procedure Uses_KnownTypeUsed_H2_NoFinding;
    [Test] procedure Uses_QualifiedCall_H1_NoFinding;
    [Test] procedure Uses_GlobalVarUsed_NoFinding;
    [Test] procedure Uses_ParentClass_NoFinding;
    [Test] procedure Uses_AlwaysNeededUnit_NoFinding;
    [Test] procedure Uses_MultipleUnits_OnlyUnusedReported;
    // --- H1: Qualifizierter Bezeichner ---
    [Test] procedure Uses_H1_ShortName_Qualifier_NoFinding;
    [Test] procedure Uses_H1_FullQualName_Qualifier_NoFinding;
    // --- H2: System-Einheiten ---
    [Test] procedure Uses_H2_Generics_TDictionary_NoFinding;
    [Test] procedure Uses_H2_Generics_TList_NoFinding;
    [Test] procedure Uses_H2_Generics_TObjectList_NoFinding;
    [Test] procedure Uses_H2_Math_Floor_NoFinding;
    [Test] procedure Uses_H2_StrUtils_PosEx_NoFinding;
    [Test] procedure Uses_H2_DateUtils_DaysBetween_NoFinding;
    [Test] procedure Uses_H2_IOUtils_TFile_NoFinding;
    [Test] procedure Uses_H2_JSON_TJSONObject_NoFinding;
    [Test] procedure Uses_H2_RegEx_TRegEx_NoFinding;
    [Test] procedure Uses_H2_Zip_TZipFile_NoFinding;
    [Test] procedure Uses_H2_Diagnostics_TStopwatch_NoFinding;
    [Test] procedure Uses_H2_Threading_TTask_NoFinding;
    [Test] procedure Uses_H2_Classes_TStringList_NoFinding;
    [Test] procedure Uses_H2_Registry_TRegistry_NoFinding;
    // --- H2: VCL-Einheiten ---
    [Test] procedure Uses_H2_VclDialogs_ShowMessage_NoFinding;
    [Test] procedure Uses_H2_VclGraphics_TBitmap_NoFinding;
    [Test] procedure Uses_H2_VclComCtrls_TTabSheet_NoFinding;
    [Test] procedure Uses_H2_VclMenus_TPopupMenu_NoFinding;
    // --- H2: Datenbank ---
    [Test] procedure Uses_H2_DataDB_TDataSet_NoFinding;
    // --- Randfaelle ---
    [Test] procedure Uses_UnknownUnit_NoMapping_NoFinding;
    [Test] procedure Uses_TypeAlias_NoFinding;
    [Test] procedure Uses_WithStatement_NoFinding;
    [Test] procedure Uses_RegSuffix_NeverReported;
    [Test] procedure Uses_ShortNameUsed_LongNameInUses_NoFinding;
    [Test] procedure Uses_TypeParam_Generic_NoFinding;
    [Test] procedure Uses_InterfaceAndImpl_OnlyOnceReported;
    [Test] procedure Uses_AllUnused_AllReported;
  end;

implementation

{ ---- UnusedUses ---- }

procedure TTestUnusedUses.Uses_UnknownUnit_ReportsWarning;
// Unit die im Code nirgends vorkommt → Warning
const SRC =
  'unit t;'#13#10+
  'uses System.IniFiles;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  DoSomething;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedUses),
      'System.IniFiles ohne TIniFile-Verwendung – Warning');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_KnownTypeUsed_H2_NoFinding;
// H2: TIniFile als Typ → System.IniFiles ist benoetigt
const SRC =
  'unit t;'#13#10+
  'uses System.IniFiles;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var ini: TIniFile;'#13#10+
  'begin'#13#10+
  '  ini := TIniFile.Create(''cfg.ini'');'#13#10+
  '  ini.Free;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'TIniFile vorhanden – kein Befund');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_QualifiedCall_H1_NoFinding;
// H1: 'system.inifiles.' als Praefix im Code
const SRC =
  'unit t;'#13#10+
  'uses System.IniFiles;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var ini: System.IniFiles.TIniFile;'#13#10+
  'begin'#13#10+
  '  ini := System.IniFiles.TIniFile.Create(''x'');'#13#10+
  '  ini.Free;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'Qualifizierter Bezeichner ''inifiles.'' – kein Befund');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_GlobalVarUsed_NoFinding;
// H2: 'application' (global var aus Vcl.Forms) wird verwendet
const SRC =
  'unit t;'#13#10+
  'uses Vcl.Forms;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  Application.ProcessMessages;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'Application.ProcessMessages – Vcl.Forms benoetigt, kein Befund');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_ParentClass_NoFinding;
// Elternklasse TIniFile im class()-Block → System.IniFiles benoetigt
const SRC =
  'unit t;'#13#10+
  'uses System.IniFiles;'#13#10+
  'type'#13#10+
  '  TMyIni = class(TIniFile)'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'Elternklasse TIniFile – kein Befund (Parser erfasst class()-Block)');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_AlwaysNeededUnit_NoFinding;
// System.SysUtils ist immer benoetigt und wird nie gemeldet
const SRC =
  'unit t;'#13#10+
  'uses System.SysUtils;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'System.SysUtils – immer benoetigt, kein Befund');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_MultipleUnits_OnlyUnusedReported;
// Von drei Units wird eine nie verwendet → genau 1 Befund
const SRC =
  'unit t;'#13#10+
  'uses System.IniFiles, System.Zip, System.Classes;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var sl: TStringList; z: TZipFile;'#13#10+
  'begin'#13#10+
  '  sl := TStringList.Create; sl.Free;'#13#10+
  '  z  := TZipFile.Create;    z.Free;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedUses),
      'System.IniFiles ungenutzt – genau 1 Befund');
    Assert.AreEqual('System.IniFiles',
      (F[0] as TLeakFinding).MissingVar,
      'Befund zeigt korrekten Unit-Namen');
  finally F.Free; end;
end;

{ ---- UnusedUses – H1 ---- }

procedure TTestUnusedUses.Uses_H1_ShortName_Qualifier_NoFinding;
// 'IniFiles.' als Kurzname-Praefix → H1 erkennt Verwendung
const SRC =
  'unit t;'#13#10+
  'uses System.IniFiles;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var x: IniFiles.TIniFile;'#13#10+
  'begin x := IniFiles.TIniFile.Create(''x''); x.Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'Kurzname-Praefix IniFiles. → H1 – kein Befund');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H1_FullQualName_Qualifier_NoFinding;
// 'System.Zip.' als vollstaendiger Praefix → H1 erkennt Verwendung
const SRC =
  'unit t;'#13#10+
  'uses System.Zip;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var z: System.Zip.TZipFile;'#13#10+
  'begin z := System.Zip.TZipFile.Create; z.Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'Vollname-Praefix System.Zip. → H1 – kein Befund');
  finally F.Free; end;
end;

{ ---- UnusedUses – H2 System ---- }

procedure TTestUnusedUses.Uses_H2_Generics_TDictionary_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses System.Generics.Collections;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var d: TDictionary<string,Integer>;'#13#10+
  'begin d := TDictionary<string,Integer>.Create; d.Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'TDictionary → Generics.Collections benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_Generics_TList_NoFinding;
// Regression: TList<string> ohne TDictionary muss Generics.Collections erkennen
const SRC =
  'unit t;'#13#10+
  'uses System.Generics.Collections;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TList<string>;'#13#10+
  'begin list := TList<string>.Create; list.Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'TList<T> → Generics.Collections benoetigt, kein false positive');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_Generics_TObjectList_NoFinding;
// Regression: TObjectList<T> muss Generics.Collections erkennen
const SRC =
  'unit t;'#13#10+
  'uses System.Generics.Collections;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var items: TObjectList<TObject>;'#13#10+
  'begin items := TObjectList<TObject>.Create; items.Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'TObjectList<T> → Generics.Collections benoetigt, kein false positive');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_Math_Floor_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses System.Math;'#13#10+
  'implementation'#13#10+
  'function TFoo.Round2(x: Double): Integer;'#13#10+
  'begin Result := Floor(x); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'Floor() → System.Math benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_StrUtils_PosEx_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses System.StrUtils;'#13#10+
  'implementation'#13#10+
  'function TFoo.Find(const S, Sub: string): Integer;'#13#10+
  'begin Result := PosEx(Sub, S, 1); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'PosEx → System.StrUtils benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_DateUtils_DaysBetween_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses System.DateUtils;'#13#10+
  'implementation'#13#10+
  'function TFoo.Age(Born: TDateTime): Integer;'#13#10+
  'begin Result := DaysBetween(Now, Born); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'DaysBetween → System.DateUtils benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_IOUtils_TFile_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses System.IOUtils;'#13#10+
  'implementation'#13#10+
  'function TFoo.Exists(const P: string): Boolean;'#13#10+
  'begin Result := TFile.Exists(P); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'TFile → System.IOUtils benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_JSON_TJSONObject_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses System.JSON;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Parse(const S: string);'#13#10+
  'var j: TJSONObject;'#13#10+
  'begin j := TJSONObject.Create; j.Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'TJSONObject → System.JSON benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_RegEx_TRegEx_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses System.RegularExpressions;'#13#10+
  'implementation'#13#10+
  'function TFoo.Match(const S: string): Boolean;'#13#10+
  'begin Result := TRegEx.IsMatch(S, ''\d+''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'TRegEx → System.RegularExpressions benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_Zip_TZipFile_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses System.Zip;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Compress(const Path: string);'#13#10+
  'var z: TZipFile;'#13#10+
  'begin z := TZipFile.Create; z.Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'TZipFile → System.Zip benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_Diagnostics_TStopwatch_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses System.Diagnostics;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Measure;'#13#10+
  'var sw: TStopwatch;'#13#10+
  'begin sw := TStopwatch.StartNew; DoWork; sw.Stop; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'TStopwatch → System.Diagnostics benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_Threading_TTask_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses System.Threading;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.RunAsync;'#13#10+
  'begin TTask.Run(procedure begin DoWork; end); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'TTask → System.Threading benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_Classes_TStringList_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses System.Classes;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Build;'#13#10+
  'var sl: TStringList;'#13#10+
  'begin sl := TStringList.Create; sl.Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'TStringList → System.Classes benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_Registry_TRegistry_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses System.Win.Registry;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.ReadKey;'#13#10+
  'var r: TRegistry;'#13#10+
  'begin r := TRegistry.Create; r.Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'TRegistry → System.Win.Registry benoetigt');
  finally F.Free; end;
end;

{ ---- UnusedUses – H2 VCL ---- }

procedure TTestUnusedUses.Uses_H2_VclDialogs_ShowMessage_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses Vcl.Dialogs;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Warn(const S: string);'#13#10+
  'begin ShowMessage(S); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'ShowMessage → Vcl.Dialogs benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_VclGraphics_TBitmap_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses Vcl.Graphics;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Draw;'#13#10+
  'var bmp: TBitmap;'#13#10+
  'begin bmp := TBitmap.Create; bmp.Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'TBitmap → Vcl.Graphics benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_VclComCtrls_TTabSheet_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses Vcl.ComCtrls;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.AddTab(PC: TPageControl);'#13#10+
  'var ts: TTabSheet;'#13#10+
  'begin ts := TTabSheet.Create(PC); ts.PageControl := PC; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'TTabSheet → Vcl.ComCtrls benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_VclMenus_TPopupMenu_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses Vcl.Menus;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.BuildMenu;'#13#10+
  'var pm: TPopupMenu;'#13#10+
  'begin pm := TPopupMenu.Create(nil); pm.Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'TPopupMenu → Vcl.Menus benoetigt');
  finally F.Free; end;
end;

{ ---- UnusedUses – H2 Datenbank ---- }

procedure TTestUnusedUses.Uses_H2_DataDB_TDataSet_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses Data.DB;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Load(DS: TDataSet);'#13#10+
  'begin DS.Open; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'TDataSet → Data.DB benoetigt');
  finally F.Free; end;
end;

{ ---- UnusedUses – Randfaelle ---- }

procedure TTestUnusedUses.Uses_UnknownUnit_NoMapping_NoFinding;
// Eine unbekannte Unit (kein Mapping) → nie melden (kein false positive)
const SRC =
  'unit t;'#13#10+
  'uses MyCompanyUtils;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'Unbekannte Unit ohne Mapping – nie melden (false positive verhindern)');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_TypeAlias_NoFinding;
// TMyEvent = TNotifyEvent – TNotifyEvent muss System.Classes erkennen
const SRC =
  'unit t;'#13#10+
  'uses System.Classes;'#13#10+
  'type'#13#10+
  '  TMyEvent = TNotifyEvent;'#13#10+
  'implementation'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'TNotifyEvent in Typ-Alias – System.Classes benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_WithStatement_NoFinding;
// with DataSet do – TDataSet aus Data.DB muss erkannt werden
const SRC =
  'unit t;'#13#10+
  'uses Data.DB;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Load(DS: TDataSet);'#13#10+
  'begin'#13#10+
  '  with DS do'#13#10+
  '    Open;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'TDataSet im with-Ausdruck – Data.DB benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_RegSuffix_NeverReported;
// Units die auf 'reg' enden werden nie gemeldet (Registrierungs-Units)
const SRC =
  'unit t;'#13#10+
  'uses MyComponentsReg;'#13#10+
  'implementation'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'Unit endet auf ''reg'' → nie melden');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_ShortNameUsed_LongNameInUses_NoFinding;
// uses Vcl.Grids, aber Verwendung als Kurzname 'TStringGrid'
const SRC =
  'unit t;'#13#10+
  'uses Vcl.Grids;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Build;'#13#10+
  'var g: TStringGrid;'#13#10+
  'begin g := TStringGrid.Create(nil); g.Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'TStringGrid aus Vcl.Grids – kein Befund');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_TypeParam_Generic_NoFinding;
// TObjectList<TForm> – TForm kommt aus Vcl.Forms als Typparameter
const SRC =
  'unit t;'#13#10+
  'uses Vcl.Forms, System.Generics.Collections;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Build;'#13#10+
  'var list: TObjectList<TForm>;'#13#10+
  'begin list := TObjectList<TForm>.Create; list.Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'TForm als Typparameter – Vcl.Forms benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_InterfaceAndImpl_OnlyOnceReported;
// Gleiche Unit in interface UND implementation uses – nur 1x melden
const SRC =
  'unit t;'#13#10+
  'uses System.IniFiles;'#13#10+
  'implementation'#13#10+
  'uses System.IniFiles;'#13#10+
  'procedure TFoo.Bar; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedUses),
      'Doppelter uses-Eintrag – nur 1 Befund');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_AllUnused_AllReported;
// Drei unbekannte Units – alle drei werden gemeldet
const SRC =
  'unit t;'#13#10+
  'uses System.IniFiles, System.Zip, Vcl.Menus;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar; begin DoNothing; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(3, TFindingHelper.Count(F, fkUnusedUses),
      'Drei ungenutzte Units – alle drei als Warning');
  finally F.Free; end;
end;

end.
