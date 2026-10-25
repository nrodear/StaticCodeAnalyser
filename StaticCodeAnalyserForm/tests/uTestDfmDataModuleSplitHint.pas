unit uTestDfmDataModuleSplitHint;

// Tests fuer den TDfmDataModuleSplitHintDetector (Aggregat-Hint).
// Wird nach TDfmDbInUiFormDetector aufgerufen und zaehlt dessen Findings.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmDataModuleSplitHint = class
  public
    [Setup]    procedure SetUp;
    [TearDown] procedure TearDown;

    // --- Positive ---
    [Test] procedure Test_ThreeDbComponentsOnForm_AggregateHintReported;
    [Test] procedure Test_FiveDbComponentsOnForm_HintListsThemAll;
    [Test] procedure Test_TenComponents_HintTruncatesAtFive;

    // --- Negative ---
    [Test] procedure Test_TwoDbComponentsBelowThreshold_NoAggregateHint;
    [Test] procedure Test_DataModuleRoot_NoAggregateHint;
    [Test] procedure Test_NoDbComponents_NoAggregateHint;

    // --- Konfig ---
    [Test] procedure Test_CustomThreshold_RespectedFromConfig;

    // --- Finding-Inhalt ---
    [Test] procedure Test_Finding_KindAndSeverity;
    [Test] procedure Test_Hint_MentionsCountAndExtractName;
    [Test] procedure Test_BothIndividualAndAggregate_Coexist;
    // Minor 238: das Unit-Praefix nur bei KLEINEM u kappen
    [Test] procedure Test_LowercaseUPrefix_Stripped;
    [Test] procedure Test_UppercaseUName_NotStripped;
    [Test] procedure Test_LowercaseUThenLowercase_StillStripped;

    // --- Perf Charge Q3: begrenzte Aggregat-Suche (AFromIdx) ---
    [Test] procedure Test_FromIdx_EarlierFindingsOfSameFileNotCounted;
    [Test] procedure Test_FromIdx_AtCallStart_SameHintAsFullScan;
    [Test] procedure Test_FromIdx_Negative_ActsAsFullScan;
    [Test] procedure Test_Ctx_FirstDfmFormVisit_OnlyFirstCallTrue;
    [Test] procedure Test_Ctx_FirstDfmFormVisit_FoldsCaseLikeSameText;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uDfmParser, uComponentGraph,
  uDfmDbInUiForm, uDfmDataModuleSplitHint,
  uAnalyzeContext;   // Perf Charge Q3: FirstDfmFormVisit

// Haengt die DbInUiForm-Befunde von Src unter FileName an L an (ohne
// Aggregat) - mehrfach aufgerufen entsteht die kumulative Liste wie im
// seriellen Scan (Perf Charge Q3).
procedure AppendDbInUi(const Src, FileName: string;
  L: TObjectList<TLeakFinding>);
var
  Parser : TDfmParser;
  Graph  : TComponentGraph;
begin
  Parser := TDfmParser.Create;
  try
    Graph := Parser.ParseSource(Src);
    try
      // Binding = nil: dieser Harness prueft die Aggregation, nicht die
      // Wurzel-Erkennung. Ohne Bindung entscheidet der Klassenname wie vor
      // dem 2026-09-12 - die Fixturen hier heissen darum weiter TForm1.
      TDfmDbInUiFormDetector.Analyze(Graph, nil, FileName, L);
    finally
      Graph.Free;
    end;
  finally
    Parser.Free;
  end;
end;

function RunDbInUiThenAggregate(const Src: string;
  const FileName: string = 'uMainForm.dfm'): TObjectList<TLeakFinding>;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  AppendDbInUi(Src, FileName, Result);
  TDfmDataModuleSplitHintDetector.Aggregate(FileName, Result);
end;

function Count(F: TObjectList<TLeakFinding>; K: TFindingKind): Integer;
var X: TLeakFinding;
begin
  Result := 0;
  for X in F do if X.Kind = K then Inc(Result);
end;

var
  GOldDbHintMax: Integer;

procedure TTestDfmDataModuleSplitHint.SetUp;
begin
  // Alt-Wert sichern statt hartkodiertem Default-Restore (Audit F4,
  // Begruendung siehe uTestDfmGodHandler.SetUp).
  GOldDbHintMax := DetectorMaxDbInUiFormHint;
  DetectorMaxDbInUiFormHint := 3;
end;

procedure TTestDfmDataModuleSplitHint.TearDown;
begin
  DetectorMaxDbInUiFormHint := GOldDbHintMax;
end;

// --- Positive ---

procedure TTestDfmDataModuleSplitHint.Test_ThreeDbComponentsOnForm_AggregateHintReported;
const DFM =
  'object F: TForm'#13#10 +
  '  object Conn: TADOConnection end'#13#10 +
  '  object Qry: TADOQuery end'#13#10 +
  '  object DS: TDataSource end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunDbInUiThenAggregate(DFM);
  try Assert.AreEqual<Integer>(1, Count(F, fkDfmDataModuleSplitHint));
  finally F.Free; end;
end;

procedure TTestDfmDataModuleSplitHint.Test_FiveDbComponentsOnForm_HintListsThemAll;
const DFM =
  'object F: TForm'#13#10 +
  '  object Conn1: TADOConnection end'#13#10 +
  '  object Conn2: TFDConnection end'#13#10 +
  '  object Q1: TADOQuery end'#13#10 +
  '  object Q2: TFDQuery end'#13#10 +
  '  object DS1: TDataSource end'#13#10 +
  'end';
var
  F : TObjectList<TLeakFinding>;
  Fnd, Hit : TLeakFinding;
begin
  F := RunDbInUiThenAggregate(DFM);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkDfmDataModuleSplitHint then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit);
    Assert.Contains(Hit.MissingVar, 'Conn1');
    Assert.Contains(Hit.MissingVar, 'DS1');
  finally F.Free; end;
end;

procedure TTestDfmDataModuleSplitHint.Test_TenComponents_HintTruncatesAtFive;
const DFM =
  'object F: TForm'#13#10 +
  '  object c1: TADOConnection end'#13#10 +
  '  object c2: TADOConnection end'#13#10 +
  '  object c3: TADOConnection end'#13#10 +
  '  object c4: TADOConnection end'#13#10 +
  '  object c5: TADOConnection end'#13#10 +
  '  object c6: TADOConnection end'#13#10 +
  '  object c7: TADOConnection end'#13#10 +
  '  object c8: TADOConnection end'#13#10 +
  'end';
var
  F : TObjectList<TLeakFinding>;
  Fnd, Hit : TLeakFinding;
begin
  F := RunDbInUiThenAggregate(DFM);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkDfmDataModuleSplitHint then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit);
    Assert.Contains(Hit.MissingVar, '... (+');
    Assert.Contains(Hit.MissingVar, 'more)');
  finally F.Free; end;
end;

// --- Negative ---

procedure TTestDfmDataModuleSplitHint.Test_TwoDbComponentsBelowThreshold_NoAggregateHint;
// 2 < 3 (Default-Threshold) -> kein Aggregat-Hint
const DFM =
  'object F: TForm'#13#10 +
  '  object Conn: TADOConnection end'#13#10 +
  '  object Qry: TADOQuery end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunDbInUiThenAggregate(DFM);
  try Assert.AreEqual<Integer>(0, Count(F, fkDfmDataModuleSplitHint));
  finally F.Free; end;
end;

procedure TTestDfmDataModuleSplitHint.Test_DataModuleRoot_NoAggregateHint;
// uDfmDbInUiForm emittiert auf DataModule-Roots gar nichts -> Aggregat
// hat keinen Input -> kein Hint.
const DFM =
  'object DM: TDataModule'#13#10 +
  '  object Conn: TADOConnection end'#13#10 +
  '  object Qry: TADOQuery end'#13#10 +
  '  object DS: TDataSource end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunDbInUiThenAggregate(DFM);
  try Assert.AreEqual<Integer>(0, Count(F, fkDfmDataModuleSplitHint));
  finally F.Free; end;
end;

procedure TTestDfmDataModuleSplitHint.Test_NoDbComponents_NoAggregateHint;
const DFM =
  'object F: TForm'#13#10 +
  '  object b: TButton end'#13#10 +
  '  object lbl: TLabel end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunDbInUiThenAggregate(DFM);
  try Assert.AreEqual<Integer>(0, Count(F, fkDfmDataModuleSplitHint));
  finally F.Free; end;
end;

// --- Konfig ---

procedure TTestDfmDataModuleSplitHint.Test_CustomThreshold_RespectedFromConfig;
const DFM =
  'object F: TForm'#13#10 +
  '  object Conn: TADOConnection end'#13#10 +
  '  object Qry: TADOQuery end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  DetectorMaxDbInUiFormHint := 2;
  F := RunDbInUiThenAggregate(DFM);
  try Assert.AreEqual<Integer>(1, Count(F, fkDfmDataModuleSplitHint),
    'Threshold=2 macht 2 Komponenten zum Treffer');
  finally F.Free; end;
end;

// --- Finding-Inhalt ---

procedure TTestDfmDataModuleSplitHint.Test_Finding_KindAndSeverity;
const DFM =
  'object F: TForm'#13#10 +
  '  object Conn: TADOConnection end'#13#10 +
  '  object Qry: TADOQuery end'#13#10 +
  '  object DS: TDataSource end'#13#10 +
  'end';
var
  F : TObjectList<TLeakFinding>;
  Fnd, Hit : TLeakFinding;
begin
  F := RunDbInUiThenAggregate(DFM);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkDfmDataModuleSplitHint then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit);
    Assert.AreEqual(fkDfmDataModuleSplitHint, Hit.Kind);
    Assert.AreEqual(lsHint, Hit.Severity);
  finally F.Free; end;
end;

procedure TTestDfmDataModuleSplitHint.Test_Hint_MentionsCountAndExtractName;
// Filename 'uMainForm.dfm' -> Vorschlag 'TMainFormDataModule'.
const DFM =
  'object F: TForm'#13#10 +
  '  object Conn: TADOConnection end'#13#10 +
  '  object Qry: TADOQuery end'#13#10 +
  '  object DS: TDataSource end'#13#10 +
  'end';
var
  F : TObjectList<TLeakFinding>;
  Fnd, Hit : TLeakFinding;
begin
  F := RunDbInUiThenAggregate(DFM, 'uMainForm.dfm');
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkDfmDataModuleSplitHint then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit);
    Assert.Contains(Hit.MissingVar, '3 DB');
    Assert.Contains(Hit.MissingVar, 'TMainFormDataModule');
  finally F.Free; end;
end;

procedure TTestDfmDataModuleSplitHint.Test_BothIndividualAndAggregate_Coexist;
// Aggregat ersetzt die Einzelmeldungen NICHT - beides bleibt im Grid.
const DFM =
  'object F: TForm'#13#10 +
  '  object Conn: TADOConnection end'#13#10 +
  '  object Qry: TADOQuery end'#13#10 +
  '  object DS: TDataSource end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunDbInUiThenAggregate(DFM);
  try
    Assert.AreEqual<Integer>(3, Count(F, fkDfmDbInUiForm),
      'Drei Einzel-DbInUiForm-Findings bleiben');
    Assert.AreEqual<Integer>(1, Count(F, fkDfmDataModuleSplitHint),
      'Plus ein Aggregat-Hint');
  finally F.Free; end;
end;

{ --- Minor 238: das Unit-Praefix im Vorschlagsnamen -------------- }
//
// Der Refactor-Vorschlag leitet sich aus dem Dateinamen ab. Das 'u'
// davor wurde mit StartsText geprueft - case-INSENSITIV -, also auch
// ein grosses 'U' gekappt. Aus 'Unit4.dfm' wurde der Vorschlag
// 'Tnit4DataModule'; im Korpus steht dieser Fund wirklich.
//
// Der Fix prueft klein-u, sonst nichts. Die vom Review zusaetzlich
// vorgeschlagene Bedingung "Folgezeichen gross" waere zu scharf: der
// Korpus hat vier Funde aus 'ufJvDBMove.dfm', wo auf das Praefix ein
// kleines 'f' folgt und das Kappen richtig ist. Der dritte Test haelt
// genau diesen Fall.
// Alle drei am gebauten Stand verprobt.
//
// Die drei Fixturen sind identisch bis auf den DATEINAMEN - der ist
// der Prueffall. Der Selbstscan meldet dafuer zwei zusaetzliche
// DuplicateBlock-Hints; in Testunits per Profil-Politik kein Mangel.

procedure TTestDfmDataModuleSplitHint.Test_LowercaseUPrefix_Stripped;
// Der Normalfall, heute schon richtig - als Positiv-Kontrolle.
const DFM =
  'object F: TForm'#13#10 +
  '  object Conn: TADOConnection end'#13#10 +
  '  object Qry: TADOQuery end'#13#10 +
  '  object DS: TDataSource end'#13#10 +
  'end';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := RunDbInUiThenAggregate(DFM, 'uMainForm.dfm');
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkDfmDataModuleSplitHint then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit);
    Assert.IsTrue(Pos('TMainFormDataModule', Hit.MissingVar) > 0,
      'kleines u ist das Unit-Praefix und faellt weg - gemeldet wurde: ' + Hit.MissingVar);
  finally F.Free; end;
end;

procedure TTestDfmDataModuleSplitHint.Test_UppercaseUName_NotStripped;
// DER FEHLERFALL. Heute liefert er TserFormDataModule.
const DFM =
  'object F: TForm'#13#10 +
  '  object Conn: TADOConnection end'#13#10 +
  '  object Qry: TADOQuery end'#13#10 +
  '  object DS: TDataSource end'#13#10 +
  'end';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := RunDbInUiThenAggregate(DFM, 'UserForm.dfm');
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkDfmDataModuleSplitHint then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit);
    Assert.IsTrue(Pos('TUserFormDataModule', Hit.MissingVar) > 0,
      'grosses U gehoert zum Namen - gemeldet wurde: ' + Hit.MissingVar);
  finally F.Free; end;
end;

procedure TTestDfmDataModuleSplitHint.Test_LowercaseUThenLowercase_StillStripped;
// Die Gegenprobe zur verworfenen Zusatzbedingung: nach dem Praefix
// darf auch ein Kleinbuchstabe stehen. Form aus dem Korpus.
const DFM =
  'object F: TForm'#13#10 +
  '  object Conn: TADOConnection end'#13#10 +
  '  object Qry: TADOQuery end'#13#10 +
  '  object DS: TDataSource end'#13#10 +
  'end';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := RunDbInUiThenAggregate(DFM, 'ufJvDBMove.dfm');
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkDfmDataModuleSplitHint then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit);
    Assert.IsTrue(Pos('TfJvDBMoveDataModule', Hit.MissingVar) > 0,
      'auch vor kleinem f ist das u das Praefix - gemeldet wurde: ' + Hit.MissingVar);
  finally F.Free; end;
end;

{ --- Perf Charge Q3: begrenzte Aggregat-Suche ----------------------- }
//
// Im seriellen Scan haengt jede Datei ihre Befunde an EINE kumulative
// Liste; Aggregate durchsuchte sie je Formdatei ganz. Der Runner reicht
// jetzt den Listenstand vor der Formdatei als AFromIdx durch, wenn der
// Context belegt, dass die Formdatei zum ersten Mal besucht wird. Die
// Tests halten: (1) AFromIdx begrenzt wirklich, (2) mit dem Listenstand
// als Start ist das Ergebnis gleich dem Vollscan, (3) negativ = voll,
// (4)+(5) die Vormerkung im Context. Ohne die Aenderung sind alle fuenf
// rot (AFromIdx und FirstDfmFormVisit gibt es nicht - Uebersetzungs-
// fehler).

const
  Q3_DFM_THREE_DB =
    'object F: TForm'#13#10 +
    '  object Conn: TADOConnection end'#13#10 +
    '  object Qry: TADOQuery end'#13#10 +
    '  object DS: TDataSource end'#13#10 +
    'end';

  Q3_MAIN_DFM = 'uMainForm.dfm';

// Fremdbefund (anderer Kind, andere Datei) als Fuellmaterial davor.
procedure Q3AppendOther(const FileName: string; L: TObjectList<TLeakFinding>);
var
  F : TLeakFinding;
begin
  F := TLeakFinding.Create;
  F.FileName   := FileName;
  F.LineNumber := '1';
  F.MissingVar := 'Button1.Caption = ''x''';
  F.SetKind(fkDfmHardcodedCaption);
  L.Add(F);
end;

function Q3HintText(L: TObjectList<TLeakFinding>): string;
var
  F  : TLeakFinding;
  SL : TStringList;
begin
  SL := TStringList.Create;
  try
    for F in L do
    begin
      if F.Kind = fkDfmDataModuleSplitHint then
      begin
        SL.Add(Format('%s|%s|%s', [F.FileName, F.LineNumber, F.MissingVar]));
      end;
    end;
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

procedure TTestDfmDataModuleSplitHint.Test_FromIdx_EarlierFindingsOfSameFileNotCounted;
// Drei DbInUiForm-Befunde VOR AFromIdx: mit Start hinter ihnen zaehlt
// Aggregate nichts (kein Hint), der Vollscan derselben Liste meldet ihn.
var
  L : TObjectList<TLeakFinding>;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    AppendDbInUi(Q3_DFM_THREE_DB, Q3_MAIN_DFM, L);
    TDfmDataModuleSplitHintDetector.Aggregate(Q3_MAIN_DFM, L, L.Count);
    Assert.AreEqual<Integer>(0, Count(L, fkDfmDataModuleSplitHint),
      'Start hinter den Befunden - nichts zu zaehlen');
    TDfmDataModuleSplitHintDetector.Aggregate(Q3_MAIN_DFM, L, 0);
    Assert.AreEqual<Integer>(1, Count(L, fkDfmDataModuleSplitHint),
      'Gegenprobe Vollscan: Hint kommt');
  finally
    L.Free;
  end;
end;

procedure TTestDfmDataModuleSplitHint.Test_FromIdx_AtCallStart_SameHintAsFullScan;
// Die Lage im Scan: davor stehen Befunde ANDERER Dateien (auch
// DbInUiForm einer anderen Form), dann die eigenen. Start = Listenstand
// vor der eigenen Form liefert denselben Hint wie der Vollscan.
var
  LFull, LFrom : TObjectList<TLeakFinding>;
  Start, i     : Integer;
begin
  LFull := TObjectList<TLeakFinding>.Create(True);
  LFrom := TObjectList<TLeakFinding>.Create(True);
  try
    for i := 1 to 50 do
    begin
      Q3AppendOther('uOther' + IntToStr(i) + '.dfm', LFull);
      Q3AppendOther('uOther' + IntToStr(i) + '.dfm', LFrom);
    end;
    AppendDbInUi(Q3_DFM_THREE_DB, 'uOtherForm.dfm', LFull);
    AppendDbInUi(Q3_DFM_THREE_DB, 'uOtherForm.dfm', LFrom);
    Start := LFrom.Count;
    AppendDbInUi(Q3_DFM_THREE_DB, Q3_MAIN_DFM, LFull);
    AppendDbInUi(Q3_DFM_THREE_DB, Q3_MAIN_DFM, LFrom);
    TDfmDataModuleSplitHintDetector.Aggregate(Q3_MAIN_DFM, LFull);
    TDfmDataModuleSplitHintDetector.Aggregate(Q3_MAIN_DFM, LFrom, Start);
    Assert.AreEqual<Integer>(1, Count(LFrom, fkDfmDataModuleSplitHint));
    Assert.AreEqual<Integer>(LFull.Count, LFrom.Count);
    Assert.AreEqual(Q3HintText(LFull), Q3HintText(LFrom));
  finally
    LFrom.Free;
    LFull.Free;
  end;
end;

procedure TTestDfmDataModuleSplitHint.Test_FromIdx_Negative_ActsAsFullScan;
var
  L : TObjectList<TLeakFinding>;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    AppendDbInUi(Q3_DFM_THREE_DB, Q3_MAIN_DFM, L);
    TDfmDataModuleSplitHintDetector.Aggregate(Q3_MAIN_DFM, L, -5);
    Assert.AreEqual<Integer>(1, Count(L, fkDfmDataModuleSplitHint));
  finally
    L.Free;
  end;
end;

procedure TTestDfmDataModuleSplitHint.Test_Ctx_FirstDfmFormVisit_OnlyFirstCallTrue;
var
  Ctx : TAnalyzeContext;
begin
  Ctx := TAnalyzeContext.Create;
  try
    Assert.IsTrue(Ctx.FirstDfmFormVisit('C:\p\uMainForm.dfm'), 'Erstbesuch');
    Assert.IsFalse(Ctx.FirstDfmFormVisit('C:\p\uMainForm.dfm'),
      'zweiter Besuch derselben Formdatei');
    Assert.IsTrue(Ctx.FirstDfmFormVisit('C:\p\uOther.dfm'),
      'andere Formdatei ist ein eigener Erstbesuch');
  finally
    Ctx.Free;
  end;
end;

procedure TTestDfmDataModuleSplitHint.Test_Ctx_FirstDfmFormVisit_FoldsCaseLikeSameText;
// Aggregate vergleicht per SameText - zwei Schreibweisen, die SameText
// gleich nennt, muessen als DIESELBE Formdatei gelten (sonst wuerde der
// Zweitbesuch faelschlich begrenzt suchen).
var
  Ctx : TAnalyzeContext;
begin
  Ctx := TAnalyzeContext.Create;
  try
    Assert.IsTrue(SameText('C:\P\UMAINFORM.DFM', 'c:\p\umainform.dfm'));
    Assert.IsTrue(Ctx.FirstDfmFormVisit('c:\p\umainform.dfm'));
    Assert.IsFalse(Ctx.FirstDfmFormVisit('C:\P\UMAINFORM.DFM'));
  finally
    Ctx.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmDataModuleSplitHint);

end.
