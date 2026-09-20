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
    // T2b (Review 2026-07-30): Generic-Argumente der Elternliste stehen
    // nicht mehr in TypeRef - der nkGenericArgs-Marker MUSS sie als
    // Verwendungsnachweis erhalten (Waechter gegen 'Vereinfachung' des
    // Eltern-Loop-Zweigs auf SkipGenericParams).
    [Test] procedure Uses_GenericParentArg_H2_NoFinding;
    // Voll-Review 2026-09-12 (Major 90): korrigierte KnownIdents-Eintraege
    [Test] procedure Uses_HashedStringList_H2_NoFinding;
    [Test] procedure Uses_IdSslIoHandlerSocket_H2_NoFinding;
    [Test] procedure Uses_UnknownIdentOfMappedUnit_StillReported;
    // Paket 9003: Vcl.Themes-Whitelist um die zwei haeufigsten
    // Bezeichner erweitert (TStyleManager, TCustomStyleServices)
    [Test] procedure Uses_VclThemes_StyleManagerUsed_H2_NoFinding;
    [Test] procedure Uses_VclThemes_CustomStyleServicesUsed_H2_NoFinding;
    [Test] procedure Uses_VclThemes_NothingUsed_ReportsWarning;
    // pinnt die Doppelfuehrung tstylemanager im Vcl.Styles-Zweig
    [Test] procedure Uses_FmxStyles_StyleManagerUsed_NoFinding;
    // ---- Kurznamen-Fallback nur fuer RTL-Namespaces (C-Charge 19.09.) ----
    [Test] procedure Uses_FremdeDottedUnit_KeinFallback_NoFinding;
    [Test] procedure Uses_FmxStyles_NothingUsed_ReportsWarning;
    // ---- D4: Quelltext-Kanal (Rumpf-Statements zaehlen als Nachweis) ----
    [Test] procedure Datei_QualifizierterRumpfAufruf_H1_NoFinding;
    [Test] procedure Datei_IdentNurInNestedProc_H2_NoFinding;
    [Test] procedure Datei_OhneNutzung_UsesZeileIstKeinNachweis;
    // ---- F2 (2026-09-19): KnownIdents-Luecken variants/dbctrls ----
    [Test] procedure Uses_Variants_VariantVar_H2_NoFinding;
    [Test] procedure Uses_Variants_OleVariantVar_H2_NoFinding;
    [Test] procedure Uses_DbCtrls_TFieldDataLink_H2_NoFinding;
    [Test] procedure Uses_Variants_NothingUsed_ReportsWarning;
    // ---- F3 (2026-09-19): uses-Klauseln naehren den Textkanal nicht ----
    [Test] procedure Datei_ElternUnit_NurUsesZeileDeckt_ReportsWarning;
    [Test] procedure Datei_ElternUnit_QualifizierteNutzung_NoFinding;
    [Test] procedure BlankeUsesKlauseln_OhneSemikolon_LaesstTextStehen;
    // ---- I2 (2026-09-20): Literaltext ist kein Nachweis ----
    [Test] procedure Uses_IdentNurImStringLiteral_ReportsWarning;
    [Test] procedure Uses_IdentImCode_BleibtNachweis;
  end;

implementation

uses
  System.IOUtils,   // TPath/TFile (D4-Tempdatei-Harness)
  uAstNode, uParser2,
  uUnusedUses;      // direkter AnalyzeUnit-Ruf (D4-Quelltext-Kanal)

{ ---- UnusedUses ---- }

{ --- Paket 9003: Vcl.Themes-Whitelist ---------------------------- }
//
// Die Liste fuehrte fuer Vcl.Themes nur TThemeServices. Die zwei
// haeufigsten Bezeichner der Unit - TStyleManager und
// TCustomStyleServices - fehlten, und ohne Nachweis meldete die
// Regel die uses-Zeile als ungenutzt.
//
// ERWARTUNGEN AUS DEM CODE ABGELEITET, NICHT AN DER EXE GEMESSEN -
// und das ist hier kein Versaeumnis, sondern der Befund selbst:
// SCA007 laeuft im CLI ueberhaupt nicht (uConsoleRunner setzt
// Req.UsesCheck nie, siehe Kopfkommentar von uUnusedUses). Es gibt
// keinen Kommandozeilenweg, auf dem man diese Regel messen koennte.
// Im Test-Harness laeuft sie, weil FindingsOf den Detektor direkt
// ruft und das Gate in uStaticAnalyzer2 umgeht.

procedure TTestUnusedUses.Uses_VclThemes_StyleManagerUsed_H2_NoFinding;
// H2: TStyleManager als Typ -> Vcl.Themes wird gebraucht.
// Vor der Whitelist-Erweiterung: 1 Fund (kein Nachweis, weil
// der Name nicht in der Liste stand). Danach: 0.
//
// Bewusst UNQUALIFIZIERT geschrieben - ein
// "Vcl.Themes.TStyleManager" haette schon ueber H1 einen
// Nachweis geliefert und den Test wertlos gemacht.
const SRC =
  'unit t;'#13#10+
  'uses Vcl.Themes;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var svc: TStyleManager;'#13#10+
  'begin'#13#10+
  '  svc := nil;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkUnusedUses),
      'TStyleManager beweist Vcl.Themes - kein Befund');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_VclThemes_CustomStyleServicesUsed_H2_NoFinding;
// Der zweite neue Name, gleiche Mechanik. Vorher 1, jetzt 0.
const SRC =
  'unit t;'#13#10+
  'uses Vcl.Themes;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var svc: TCustomStyleServices;'#13#10+
  'begin'#13#10+
  '  svc := nil;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkUnusedUses),
      'TCustomStyleServices beweist Vcl.Themes - kein Befund');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_VclThemes_NothingUsed_ReportsWarning;
// DIE KLAMMER: dieselbe uses-Zeile, aber kein Bezeichner der
// Unit im Code. Muss weiterhin melden - sonst haette die
// Erweiterung die Regel fuer Vcl.Themes stillgelegt statt
// praeziser gemacht.
const SRC =
  'unit t;'#13#10+
  'uses Vcl.Themes;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  DoSomething;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkUnusedUses),
      'ohne jeden Nachweis bleibt Vcl.Themes ein Befund');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_FmxStyles_StyleManagerUsed_NoFinding;
// REGRESSIONSSCHUTZ, heute schon gruen - und genau deshalb
// hier: er pinnt etwas, das wie Redundanz aussieht und keine
// ist.
//
// Der Vcl.Styles-Zweig fuehrt tstylemanager ebenfalls. Das
// sieht nach einer Dublette zum Vcl.Themes-Zweig aus, seit
// dieser den Namen auch hat - aber der Zweig wird ueber den
// Kurznamen-Fallback KnownIdents(ShortLow) AUCH fuer
// FMX.Styles gezogen, und FMX.Styles hat ein EIGENES
// TStyleManager (class sealed). Wer die vermeintliche
// Doppelfuehrung aufraeumt, macht aus dieser Fixture einen
// Fehlfund. Gemessen: die Entfernung kostet 4 Adds, einer
// davon nachweislich falsch (python4delphi
// Source/fmx/WrapFmxStyles.pas).
const SRC =
  'unit t;'#13#10+
  'uses FMX.Styles;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var svc: TStyleManager;'#13#10+
  'begin'#13#10+
  '  svc := nil;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkUnusedUses),
      'FMX.Styles hat ein eigenes TStyleManager - kein Befund');
  finally F.Free; end;
end;

{ --- Kurznamen-Fallback nur fuer RTL-Namespaces (C-Charge 19.09.) --- }

procedure TTestUnusedUses.Uses_FremdeDottedUnit_KeinFallback_NoFinding;
// FP-Muster 1 der SCA007-Recall-Freigabe: 'Alcinoe.FMX.StdCtrls' fiel
// auf KnownIdents('stdctrls') - die VCL-Identliste - zurueck; TButton
// & Co. kommen in der Fremd-Unit nicht vor, und die uses-Zeile wurde
// trotz Nutzung ihrer EIGENEN Typen (TALButton-Cast) gemeldet.
// Jetzt: kein Fallback fuer Nicht-RTL-Namespaces -> ohne verlaessliche
// Identliste KEINE Meldung (die dokumentierte Detektor-Politik
// 'lieber false negative als false positive').
// Vor dem Gate: 1 Fund - dieser Test war ROT.
const SRC =
  'unit t;'#13#10+
  'uses Alcinoe.FMX.StdCtrls;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var b: TALButton;'#13#10+
  'begin'#13#10+
  '  b := nil;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkUnusedUses),
      'fremde dotted Unit ohne eigene Identliste darf nicht ueber '
      + 'die VCL-Kurznamenliste gemeldet werden');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_FmxStyles_NothingUsed_ReportsWarning;
// DIE KLAMMER zum Gate: der Fallback bleibt fuer RTL-Namespaces
// AKTIV. FMX.Styles hat keinen eigenen Tabelleneintrag und lebt vom
// Kurznamen-Fallback auf 'styles' - ohne jeden Bezeichner im Code
// muss die Meldung weiter kommen, sonst haette das Gate den
// Fallback stillgelegt statt eingegrenzt.
const SRC =
  'unit t;'#13#10+
  'uses FMX.Styles;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  DoSomething;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkUnusedUses),
      'RTL-Namespace behaelt den Kurznamen-Fallback - FMX.Styles '
      + 'ohne Nutzung bleibt ein Befund');
  finally F.Free; end;
end;


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

procedure TTestUnusedUses.Uses_GenericParentArg_H2_NoFinding;
// T2b (Review 2026-07-30): 'TIniFile' kommt AUSSCHLIESSLICH als
// Generic-Argument der Elternliste vor. Der Eltern-Loop haelt die
// Argumente seit T2b aus TypeRef heraus - der Verwendungsnachweis
// kommt jetzt aus dem nkGenericArgs-Marker, den CollectText wie jeden
// Knoten erntet (H2 matcht 'tinifile'). Wuerde der Generic-Zweig auf
// einen puren SkipGenericParams-Aufruf 'vereinfacht', verschwaende die
// Evidenz und dieser Test wird ROT (System.IniFiles faelschlich
// unused) - exakt die im Review dokumentierte Wartungsfalle.
const SRC =
  'unit t;'#13#10+
  'uses System.IniFiles;'#13#10+
  'implementation'#13#10+
  'type'#13#10+
  '  TIniList = class(TObjectList<TIniFile>)'#13#10+
  '  end;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'Generic-Argument der Elternliste ist ein Verwendungsnachweis - ' +
      'System.IniFiles darf nicht als unused gemeldet werden');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_HashedStringList_H2_NoFinding;
// Voll-Review 2026-09-12 (Major 90): in der System.IniFiles-Liste stand
// 'thashedinitfile' - ein Bezeichner, den es nicht gibt (0 Korpus-
// treffer). Eine Unit, die aus System.IniFiles nur THashedStringList
// nutzt (51 Korpustreffer), hatte damit keinen Nachweis und wurde
// faelschlich als unused gemeldet.
const SRC =
  'unit t;'#13#10+
  'uses System.IniFiles;'#13#10+
  'implementation'#13#10+
  'procedure Foo;'#13#10+
  'var L: THashedStringList;'#13#10+
  'begin'#13#10+
  '  L := THashedStringList.Create;'#13#10+
  'end;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
    'THashedStringList ist der Nachweis fuer System.IniFiles');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_IdSslIoHandlerSocket_H2_NoFinding;
// Derselbe Defekt in der Indy-Liste: 'tidssliohannlersocketopenssl'
// (Buchstabendreher) statt TIdSSLIOHandlerSocketOpenSSL - 85
// Korpustreffer fuer die richtige Schreibweise, 0 fuer die falsche.
const SRC =
  'unit t;'#13#10+
  'uses IdSSLOpenSSL;'#13#10+
  'implementation'#13#10+
  'procedure Foo;'#13#10+
  'var H: TIdSSLIOHandlerSocketOpenSSL;'#13#10+
  'begin'#13#10+
  '  H := TIdSSLIOHandlerSocketOpenSSL.Create(nil);'#13#10+
  'end;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
    'TIdSSLIOHandlerSocketOpenSSL ist der Nachweis fuer IdSSLOpenSSL');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_UnknownIdentOfMappedUnit_StillReported;
// Gegenrichtung: die Korrektur darf H2 nicht generell entschaerfen.
// Eine gemappte Unit, aus der KEIN gelisteter Bezeichner vorkommt,
// bleibt ein Fund.
const SRC =
  'unit t;'#13#10+
  'uses System.IniFiles;'#13#10+
  'implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  WriteLn(''nichts aus IniFiles'');'#13#10+
  'end;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedUses),
    'ohne jeden gelisteten Bezeichner bleibt die Unit unused');
  finally F.Free; end;
end;

{ --- F2 (2026-09-19): KnownIdents-Luecken variants/dbctrls --------- }
//
// Zwei Luecken aus der D-Charge-Stichprobe: 'Variants' fuehrte den
// TYP Variant/OleVariant nicht (nur Var*-Funktionen), 'DbCtrls'
// fuehrte TFieldDataLink nicht. Beide Muster sind an der BESTEHENDEN
// Exe belegt (f23_fix: je 1 Fund trotz Nutzung) - nach der
// Listen-Erweiterung 0.

procedure TTestUnusedUses.Uses_Variants_VariantVar_H2_NoFinding;
// Eine Variant-Variable braucht die Variants-Unit zur Laufzeit
// (Operationen auf dem Builtin-Typ). Vorher: 1 Fund. Jetzt: 0.
const SRC =
  'unit t;'#13#10 +
  'uses Variants;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'var v: Variant;'#13#10 +
  'begin'#13#10 +
  '  v := 1;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
    'der Variant-Typ beweist die Variants-Unit - kein Befund');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_Variants_OleVariantVar_H2_NoFinding;
// Der zweite neue Name, gleiche Mechanik.
const SRC =
  'unit t;'#13#10 +
  'uses Variants;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'var v: OleVariant;'#13#10 +
  'begin'#13#10 +
  '  v := 1;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
    'OleVariant beweist die Variants-Unit - kein Befund');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_DbCtrls_TFieldDataLink_H2_NoFinding;
// Eigene DB-Controls nutzen DbCtrls oft NUR ueber TFieldDataLink.
const SRC =
  'unit t;'#13#10 +
  'uses Vcl.DbCtrls;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'var dl: TFieldDataLink;'#13#10 +
  'begin'#13#10 +
  '  dl := nil;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
    'TFieldDataLink beweist Vcl.DbCtrls - kein Befund');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_Variants_NothingUsed_ReportsWarning;
// DIE KLAMMER: dieselbe uses-Zeile ohne jeden Variants-Bezeichner
// muss weiterhin melden - sonst haette die Erweiterung die Regel
// fuer Variants stillgelegt statt praeziser gemacht.
const SRC =
  'unit t;'#13#10 +
  'uses Variants;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  DoSomething;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedUses),
    'ohne jeden Nachweis bleibt Variants ein Befund');
  finally F.Free; end;
end;

{ ---- D4: Quelltext-Kanal (2026-09-19) ---- }
// FP-Muster 2 der Recall-Freigabe: CollectText sieht nur AST-Namen -
// Nutzungen, die allein in Rumpf-STATEMENTS leben, fehlten im Suchtext.
// Der additive Quelltext-Kanal braucht eine ECHTE Datei; FindingsOf
// uebergibt einen Platzhalter-Namen und prueft damit weiter den reinen
// AST-Weg (die 40 Bestandsfixturen behalten so ihren Vertrag). Diese
// Tests gehen deshalb ueber eine Tempdatei + direkten AnalyzeUnit-Ruf.

function FindingsAusDatei(const Source: string): TObjectList<TLeakFinding>;
var
  Parser   : TParser2;
  Root     : TAstNode;
  TempPath : string;
  SL       : TStringList;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  TempPath := TPath.Combine(TPath.GetTempPath,
    'sca_uses_' + TGuid.NewGuid.ToString
      .Replace('{', '').Replace('}', '').Replace('-', '') + '.pas');
  SL := TStringList.Create;
  try
    SL.Text := Source;
    SL.SaveToFile(TempPath, TEncoding.UTF8);
  finally
    SL.Free;
  end;
  try
    Parser := TParser2.Create;
    try
      Root := Parser.ParseFile(TempPath);
      try
        TUnusedUsesDetector.AnalyzeUnit(Root, TempPath, Result);
      finally
        Root.Free;
      end;
    finally
      Parser.Free;
    end;
  finally
    if TFile.Exists(TempPath) then TFile.Delete(TempPath);
  end;
end;

procedure TTestUnusedUses.Datei_QualifizierterRumpfAufruf_H1_NoFinding;
// H1 ueber den Quelltext-Kanal: der qualifizierte Aufruf steht NUR im
// Statement-Rumpf. Vor D4 war das ein Fund (der AST-Suchtext kannte
// die Zeile nicht) - dieser Test war ROT.
var F: TObjectList<TLeakFinding>;
begin
  F := FindingsAusDatei(
    'unit t;'#13#10+
    'interface'#13#10+
    'uses Vcl.Dialogs;'#13#10+
    'implementation'#13#10+
    'procedure Zeige;'#13#10+
    'begin'#13#10+
    '  Vcl.Dialogs.ShowMessage(''hi'');'#13#10+
    'end;'#13#10+
    'end.');
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'der qualifizierte Rumpf-Aufruf ist ein H1-Nachweis');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Datei_IdentNurInNestedProc_H2_NoFinding;
// Exakt die Form von Fund 4 der Freigabe-Stichprobe
// (JvPageSetupTitled): der Forms-Bezeichner lebt in einer NESTED
// procedure - im AST-Suchtext unsichtbar. Vor D4 ROT.
var F: TObjectList<TLeakFinding>;
begin
  F := FindingsAusDatei(
    'unit t;'#13#10+
    'interface'#13#10+
    'uses Forms;'#13#10+
    'implementation'#13#10+
    'procedure Aussen;'#13#10+
    '  procedure Innen;'#13#10+
    '  begin'#13#10+
    '    Application.ProcessMessages;'#13#10+
    '  end;'#13#10+
    'begin'#13#10+
    '  Innen;'#13#10+
    'end;'#13#10+
    'end.');
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'Application in der nested proc ist ein H2-Nachweis fuer Forms');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Datei_OhneNutzung_UsesZeileIstKeinNachweis;
// Gegenprobe der Kanal-Breite: die uses-Zeile selbst steht jetzt im
// Suchtext ('uses vcl.dialogs;') - sie darf WEDER als H1-Praefix
// ('dialogs.' folgt dort nie ein Punkt) NOCH als H2-Ident zaehlen.
// Ohne echte Nutzung bleibt der Fund.
var F: TObjectList<TLeakFinding>;
begin
  F := FindingsAusDatei(
    'unit t;'#13#10+
    'interface'#13#10+
    'uses Vcl.Dialogs;'#13#10+
    'implementation'#13#10+
    'procedure Nix;'#13#10+
    'begin'#13#10+
    '  DoSomething;'#13#10+
    'end;'#13#10+
    'end.');
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedUses),
      'ohne Nutzung meldet die Regel weiter - die eigene uses-Zeile '
      + 'ist kein Nachweis');
  finally F.Free; end;
end;

{ ---- F3 (2026-09-19): uses-Klauseln naehren den Textkanal nicht ---- }
// Das FN-Muster der D4-Abnahme: 'uses FMX.Controls.Presentation;'
// enthaelt 'controls.' und deckte ueber H1 faelschlich die
// Eltern-Unit FMX.Controls. Seit F3 blankt der Textkanal jede
// uses-Klausel - dieselbe Politik, mit der CollectText nkUsesItem
// ausschliesst. An der BESTEHENDEN Exe belegt (f23_fix/eltern.pas:
// heute 0 Funde trotz ungenutztem FMX.Controls).

procedure TTestUnusedUses.Datei_ElternUnit_NurUsesZeileDeckt_ReportsWarning;
// VOR F3: 0 Funde - die uses-Zeile der Kind-Unit deckte die Eltern-
// Unit. Jetzt: FMX.Controls wird gemeldet (kein Ident der Liste im
// Code); FMX.Controls.Presentation bleibt still (TPresentedControl
// nutzt sie real, und ohne eigenes Mapping meldet H2 ohnehin nicht).
var F: TObjectList<TLeakFinding>;
begin
  F := FindingsAusDatei(
    'unit t;'#13#10+
    'interface'#13#10+
    'uses FMX.Controls, FMX.Controls.Presentation;'#13#10+
    'implementation'#13#10+
    'procedure Probe;'#13#10+
    'var p: TPresentedControl;'#13#10+
    'begin'#13#10+
    '  p := nil;'#13#10+
    'end;'#13#10+
    'end.');
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedUses),
      'die uses-Zeile der Kind-Unit ist kein Nachweis fuer die '
      + 'Eltern-Unit - FMX.Controls muss gemeldet werden');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Datei_ElternUnit_QualifizierteNutzung_NoFinding;
// GEGENPROBE: dieselben uses-Zeilen, aber der Rumpf nutzt die
// Eltern-Unit QUALIFIZIERT - das ist ein echter H1-Nachweis und
// muss das Blanken ueberleben.
var F: TObjectList<TLeakFinding>;
begin
  F := FindingsAusDatei(
    'unit t;'#13#10+
    'interface'#13#10+
    'uses FMX.Controls, FMX.Controls.Presentation;'#13#10+
    'implementation'#13#10+
    'procedure Probe;'#13#10+
    'var c: FMX.Controls.TControl;'#13#10+
    '    p: TPresentedControl;'#13#10+
    'begin'#13#10+
    '  c := nil; p := nil;'#13#10+
    'end;'#13#10+
    'end.');
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'qualifizierte Nutzung im Rumpf bleibt ein H1-Nachweis');
  finally F.Free; end;
end;

procedure TTestUnusedUses.BlankeUsesKlauseln_OhneSemikolon_LaesstTextStehen;
// Der Randstein des Blank-Vertrags, direkt an der Routine geprueft:
// (a) eine abgerissene Klausel ohne ';' bleibt stehen (sonst
// verschwaende der halbe Suchtext und erzeugte Fehlfunde), (b) eine
// vollstaendige Klausel wird exakt bis zum ';' geblankt, (c) ein
// Bezeichner, der mit 'uses' nur BEGINNT, ist keine Klausel.
var
  S : string;
begin
  S := 'unit t; uses vcl.forms';                  // kein ';' dahinter
  TUnusedUsesDetector.BlankeUsesKlauseln(S);
  Assert.AreEqual('unit t; uses vcl.forms', S,
    'ohne Abschluss-Semikolon bleibt die Klausel unangetastet');

  S := 'x uses a.b, c; y uses2 z';
  TUnusedUsesDetector.BlankeUsesKlauseln(S);
  // 'uses a.b, c;' (Position 3..14) wird zu 12 Leerzeichen - die
  // Erwartung ist konstruiert statt getippt, damit kein Zaehlfehler
  // im Literal den Test verfaelscht.
  Assert.AreEqual('x ' + StringOfChar(' ', 12) + ' y uses2 z', S,
    'Klausel exakt bis zum Semikolon geblankt; uses2 ist keine Klausel');
end;

{ ---- I2 (2026-09-20): Stringliterale sind kein Nachweis ---------- }
// Der AST-Kanal sammelte Name/TypeRef der Knoten - und der Parser
// legt Stringliterale dort in Pascal-Form ab (QuoteStrLit). Damit
// belegte blosser Literaltext eine uses-Zeile. An der BESTEHENDEN
// Exe belegt: mit dem Wort im Literal 0 Funde, ohne es 1.
// Der D4-Quelltext-Kanal fuehrt diese Politik laengst - seine
// Begruendung nahm nur faelschlich an, der AST-Weg sehe nie Literale.

procedure TTestUnusedUses.Uses_IdentNurImStringLiteral_ReportsWarning;
// Das Wort "variant" steht NUR in einem Stringliteral. Vor I2 war das
// ein Nachweis fuer Variants und der Fund verschwand - dieser Test
// war ROT. (Korpus-Muster: delphimvcframework mainformu.pas,
// Log(...computed-column variant), in der F-Abnahme als
// unerwarteter Drop aufgefallen.)
const SRC =
  'unit t;'#13#10 +
  'uses Variants;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  Log(''computed-column variant'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedUses),
    'ein Bezeichner IN einem Literal ist kein Verwendungsnachweis');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_IdentImCode_BleibtNachweis;
// GEGENPROBE: dasselbe Wort als echter TYP im Code bleibt ein
// Nachweis - das Ausblenden darf nur Literale treffen.
const SRC =
  'unit t;'#13#10 +
  'uses Variants;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'var v: Variant;'#13#10 +
  'begin'#13#10 +
  '  Log(''nichts hier'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
    'der Variant-Typ im CODE beweist die Unit weiterhin');
  finally F.Free; end;
end;


end.
