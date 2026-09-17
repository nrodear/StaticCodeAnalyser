unit uTestDfmLayerViolation;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmLayerViolation = class
  public
    [Test] procedure Test_EditDirectlyOnForm_Detected;
    [Test] procedure Test_DBEditDirectlyOnForm_Detected;
    [Test] procedure Test_EditInPanel_NoFinding;
    [Test] procedure Test_PanelOnForm_NoFinding;
    [Test] procedure Test_DataModuleRoot_Silent;
    [Test] procedure Test_ActionListOnForm_NoFinding;
    [Test] procedure Test_MultipleDirectInputs_AllReported;
    [Test] procedure Test_Finding_KindAndSeverity;

    // --- Mehr Varianten ---
    [Test] procedure Test_GroupBoxAsContainer_EditInside_NoFinding;
    [Test] procedure Test_Finding_MissingVarMentionsComponentAndClass;
    // Testluecke 135: die Wurzel-Suffix-Heuristik als Grenze festnageln
    [Test] procedure Test_IdeDefaultRootName_KnownGap_NoFinding;
    [Test] procedure Test_FormSuffixRootName_SameLayout_Reported;
    // FPC-Dialekt-Gate (A6/C3)
    [Test] procedure FpcDialect_EditOnForm_NotReported;
    [Test] procedure DelphiDialect_EditOnForm_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uDfmParser, uComponentGraph,
  uStaticFiles,   // ScanDialect (FPC-Dialekt-Gate-Tests)
  uDfmLayerViolation;

function RunOn(const Src: string): TObjectList<TLeakFinding>;
var Parser: TDfmParser; Graph: TComponentGraph;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  Parser := TDfmParser.Create;
  try
    Graph := Parser.ParseSource(Src);
    try TDfmLayerViolationDetector.Analyze(Graph, 'test.dfm', Result);
    finally Graph.Free; end;
  finally Parser.Free; end;
end;

function Count(F: TObjectList<TLeakFinding>; K: TFindingKind): Integer;
var X: TLeakFinding;
begin
  Result := 0;
  for X in F do if X.Kind = K then Inc(Result);
end;

procedure TTestDfmLayerViolation.Test_EditDirectlyOnForm_Detected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn('object frmMain: TMainForm object ed: TEdit end end');
  try Assert.AreEqual<Integer>(1, Count(F, fkDfmLayerViolation));
  finally F.Free; end;
end;

procedure TTestDfmLayerViolation.Test_DBEditDirectlyOnForm_Detected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn('object frmMain: TMainForm object ed: TDBEdit end end');
  try Assert.AreEqual<Integer>(1, Count(F, fkDfmLayerViolation));
  finally F.Free; end;
end;

procedure TTestDfmLayerViolation.Test_EditInPanel_NoFinding;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object frmMain: TMainForm'#13#10 +
    '  object pnl: TPanel'#13#10 +
    '    object ed: TEdit end'#13#10 +
    '  end'#13#10 +
    'end');
  try Assert.AreEqual<Integer>(0, Count(F, fkDfmLayerViolation));
  finally F.Free; end;
end;

procedure TTestDfmLayerViolation.Test_PanelOnForm_NoFinding;
// TPanel selbst ist Container, kein Input - keine Layer-Violation.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn('object frmMain: TMainForm object pnl: TPanel end end');
  try Assert.AreEqual<Integer>(0, Count(F, fkDfmLayerViolation));
  finally F.Free; end;
end;

procedure TTestDfmLayerViolation.Test_DataModuleRoot_Silent;
// DataModule darf direkte 'Inputs' tragen (auch wenn TEdit auf DM
// untypisch ist - der Layer-Detektor ist nur fuer Forms gedacht).
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn('object dm: TDataModule object ed: TEdit end end');
  try Assert.AreEqual<Integer>(0, Count(F, fkDfmLayerViolation));
  finally F.Free; end;
end;

procedure TTestDfmLayerViolation.Test_ActionListOnForm_NoFinding;
// TActionList ist Non-Visual und gehoert legitim auf die Form.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn('object frmMain: TMainForm object al: TActionList end end');
  try Assert.AreEqual<Integer>(0, Count(F, fkDfmLayerViolation));
  finally F.Free; end;
end;

procedure TTestDfmLayerViolation.Test_MultipleDirectInputs_AllReported;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object frmMain: TMainForm'#13#10 +
    '  object ed1: TEdit end'#13#10 +
    '  object ed2: TEdit end'#13#10 +
    '  object cb: TComboBox end'#13#10 +
    'end');
  try Assert.AreEqual<Integer>(3, Count(F, fkDfmLayerViolation));
  finally F.Free; end;
end;

procedure TTestDfmLayerViolation.Test_Finding_KindAndSeverity;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn('object frmMain: TMainForm object ed: TEdit end end');
  try
    Assert.AreEqual(fkDfmLayerViolation, F[0].Kind);
    Assert.AreEqual(lsHint, F[0].Severity);
  finally F.Free; end;
end;

procedure TTestDfmLayerViolation.Test_GroupBoxAsContainer_EditInside_NoFinding;
// Containerklassen wie TGroupBox kapseln Inputs - die Form selbst
// traegt also keinen direkten Input mehr.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object frmMain: TMainForm'#13#10 +
    '  object gb: TGroupBox'#13#10 +
    '    object ed: TEdit end'#13#10 +
    '  end'#13#10 +
    'end');
  try Assert.AreEqual<Integer>(0, Count(F, fkDfmLayerViolation));
  finally F.Free; end;
end;

procedure TTestDfmLayerViolation.Test_Finding_MissingVarMentionsComponentAndClass;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn('object frmMain: TMainForm object edUser: TEdit end end');
  try
    Assert.Contains(F[0].MissingVar, 'edUser');
    Assert.Contains(F[0].MissingVar, 'TEdit');
  finally F.Free; end;
end;

{ --- Wurzel-Suffix-Heuristik: die Phase-1-Grenze ---------------------------- }
//
// Testluecke 135 (Voll-Review 2026-09-12). IsFormOrFrameRoot fragt
// EndsText('Form') bzw. EndsText('Frame') am Klassennamen. 'TForm1' - der
// Name, den die IDE jeder neuen Form gibt - endet auf '1', und der
// Detektor verlaesst die Datei komplett.
//
// Das ist die im Unit-Kopf dokumentierte Phase-1-Vereinfachung, war aber
// nirgends als Test fixiert: wer die Heuristik "verbessert", saehe keine
// rote Ampel und wuesste nicht, dass er eine gemessene Grenze verschiebt.
//
// GEMESSEN, damit die Groesse der Grenze im Text steht und nicht geraten
// wird: von 949 direkten TForm/TFrame-Nachfahren im Korpus tragen 647
// keinen Form/Frame-Suffix. Auf die DFM-Wurzeln gerechnet sieht der
// Detektor 607 Formen und uebergeht 1.372 - also knapp ein Drittel
// Abdeckung.
//
// Die Behebung (Wurzel ueber die Klassenkette bestimmen, wie es
// uDfmDbInUiForm seit dem 2026-09-12 tut) ERHOEHT den Recall statt FPs
// zu senken und braucht deshalb einen eigenen Zweig mit FP-Stichprobe -
// Posten 9005 im Restposten-Verzeichnis.

function LayoutMitWurzel(const AWurzelKlasse: string): string;
// Beide Tests des Paares benutzen DENSELBEN Rumpf - der einzige
// Unterschied ist die Wurzelklasse, und genau das ist die Aussage. Als
// gemeinsame Funktion statt als zwei fast gleiche Literale: so steht der
// Unterschied als ein Argument da, und der Selbstscan meldet keinen
// DuplicateString-Zwilling.
// Drei direkte Kinder: zwei Eingabefelder (INPUT_CONTROLS) und ein Knopf,
// der dort NICHT steht - so belegt die Erwartung 2 statt 3 nebenbei, dass
// die Whitelist greift.
//
// Die Zeile '  end' steht dreimal und der Selbstscan meldet dafuer einen
// DuplicateString. Sie gehoert zur DFM-Syntax und steht so in jeder
// Fixture dieser Datei; in Testunits ist das per Profil-Politik kein
// Mangel. Eine Schleife statt der Literale hat es nur verschoben - dann
// ruegt StringConcatInLoop das Result := Result + ... (ausprobiert und
// wieder verworfen).
begin
  Result :=
    'object F1: ' + AWurzelKlasse + #13#10 +
    '  object edName: TEdit'#13#10 +
    '  end'#13#10 +
    '  object edMail: TEdit'#13#10 +
    '  end'#13#10 +
    '  object btnOk: TButton'#13#10 +
    '  end'#13#10 +
    'end';
end;

procedure TTestDfmLayerViolation.Test_IdeDefaultRootName_KnownGap_NoFinding;
// Die Null hier ist die GRENZE, nicht das Ziel. Am gebauten Stand
// nachgemessen: 0 Funde.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(LayoutMitWurzel('TForm1'));
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmLayerViolation),
      'BEKANNTE GRENZE: TForm1 endet nicht auf Form, der Detektor '
      + 'verlaesst die Datei');
  finally F.Free; end;
end;

procedure TTestDfmLayerViolation.FpcDialect_EditOnForm_NotReported;
// FPC-Dialekt-Gate (A6/C3, Vertrag am Detektor): unter LCL ist das
// Eingabefeld direkt auf der Form die KONVENTION (55,7 % der
// Korpus-LFM). Globaler View-State -> try/finally-Restaurierung.
// Vor dem Gate: 1 Fund (dieser Test war ROT).
var
  F : TObjectList<TLeakFinding>;
  Alt : TSourceDialect;
begin
  Alt := TStaticFiles.ScanDialect;
  TStaticFiles.ScanDialect := dlFpc;
  try
    F := RunOn('object frmMain: TMainForm object ed: TEdit end end');
    try
      Assert.AreEqual<Integer>(0, Count(F, fkDfmLayerViolation),
        'unter dlFpc meldet SCA041 nicht');
    finally F.Free; end;
  finally
    TStaticFiles.ScanDialect := Alt;
  end;
end;

procedure TTestDfmLayerViolation.DelphiDialect_EditOnForm_StillReported;
// DIE KLAMMER: explizit dlDelphi - der Delphi-Pfad (505
// Korpusfunde) bleibt vollstaendig.
var
  F : TObjectList<TLeakFinding>;
  Alt : TSourceDialect;
begin
  Alt := TStaticFiles.ScanDialect;
  TStaticFiles.ScanDialect := dlDelphi;
  try
    F := RunOn('object frmMain: TMainForm object ed: TEdit end end');
    try
      Assert.AreEqual<Integer>(1, Count(F, fkDfmLayerViolation),
        'unter dlDelphi bleibt der Fund');
    finally F.Free; end;
  finally
    TStaticFiles.ScanDialect := Alt;
  end;
end;


procedure TTestDfmLayerViolation.Test_FormSuffixRootName_SameLayout_Reported;
// Die Gegenprobe, und sie traegt die Aussage: GLEICHES Layout, nur die
// Wurzelklasse heisst TMainForm statt TForm1. Ohne sie bliebe offen, ob
// die Null oben am Namen liegt oder am Aufbau der Fixture.
// Am gebauten Stand nachgemessen: 2 Funde (die zwei TEdit; der TButton
// zaehlt nicht als Eingabe-Control).
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(LayoutMitWurzel('TMainForm'));
  try
    Assert.AreEqual<Integer>(2, Count(F, fkDfmLayerViolation),
      'derselbe Aufbau unter passendem Namen wird sehr wohl gemeldet');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmLayerViolation);

end.
