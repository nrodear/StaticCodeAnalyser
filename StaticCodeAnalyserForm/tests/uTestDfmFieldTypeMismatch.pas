unit uTestDfmFieldTypeMismatch;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmFieldTypeMismatch = class
  public
    // --- Boolean ---
    [Test] procedure Test_DBEdit_OnBoolean_Detected;
    [Test] procedure Test_DBComboBox_OnBoolean_Detected;
    [Test] procedure Test_DBCheckBox_OnBoolean_NoFinding;

    // --- Memo / Blob ---
    [Test] procedure Test_DBEdit_OnMemo_Detected;
    [Test] procedure Test_DBEdit_OnBlob_Detected;
    [Test] procedure Test_DBMemo_OnMemo_NoFinding;
    [Test] procedure Test_DBRichEdit_OnMemo_NoFinding;

    // --- Phase-1-Schweigen bei tolerierten Kombinationen ---
    [Test] procedure Test_DBEdit_OnInteger_NoFinding;
    [Test] procedure Test_DBEdit_OnString_NoFinding;
    [Test] procedure Test_DBEdit_OnDate_StillSilent_Phase1;

    // --- Robustheit ---
    [Test] procedure Test_UnknownFieldClass_Silent;
    [Test] procedure Test_NoDataSource_Silent;

    // --- Finding-Inhalt ---
    [Test] procedure Test_Finding_KindAndSeverity;
    [Test] procedure Test_Finding_MissingVarMentionsControlAndField;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uDfmParser, uComponentGraph,
  uDfmFieldTypeMismatch;

function RunOn(const Src: string): TObjectList<TLeakFinding>;
var
  Parser : TDfmParser;
  Graph  : TComponentGraph;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  Parser := TDfmParser.Create;
  try
    Graph := Parser.ParseSource(Src);
    try
      TDfmFieldTypeMismatchDetector.Analyze(Graph, 'test.dfm', Result);
    finally
      Graph.Free;
    end;
  finally
    Parser.Free;
  end;
end;

function Count(F: TObjectList<TLeakFinding>; K: TFindingKind): Integer;
var Fnd: TLeakFinding;
begin
  Result := 0;
  for Fnd in F do
    if Fnd.Kind = K then Inc(Result);
end;

function MakeDfm(const FieldCls, ControlCls: string): string;
// Bequemer Builder fuer einfache Tests: DataSet + Field + DataSource +
// ein einzelnes UI-Control gebunden.
begin
  Result :=
    'object Form: TForm'#13#10 +
    '  object q: TADOQuery'#13#10 +
    '    object qX: ' + FieldCls + ' FieldName = ''X'' end'#13#10 +
    '  end'#13#10 +
    '  object ds: TDataSource DataSet = q end'#13#10 +
    '  object c: ' + ControlCls + ' DataSource = ds DataField = ''X'' end'#13#10 +
    'end';
end;

{ --- Boolean --- }

procedure TTestDfmFieldTypeMismatch.Test_DBEdit_OnBoolean_Detected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(MakeDfm('TBooleanField', 'TDBEdit'));
  try
    Assert.AreEqual(1, Count(F, fkDfmFieldTypeMismatch));
  finally F.Free; end;
end;

procedure TTestDfmFieldTypeMismatch.Test_DBComboBox_OnBoolean_Detected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(MakeDfm('TBooleanField', 'TDBComboBox'));
  try
    Assert.AreEqual(1, Count(F, fkDfmFieldTypeMismatch));
  finally F.Free; end;
end;

procedure TTestDfmFieldTypeMismatch.Test_DBCheckBox_OnBoolean_NoFinding;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(MakeDfm('TBooleanField', 'TDBCheckBox'));
  try
    Assert.AreEqual(0, Count(F, fkDfmFieldTypeMismatch));
  finally F.Free; end;
end;

{ --- Memo / Blob --- }

procedure TTestDfmFieldTypeMismatch.Test_DBEdit_OnMemo_Detected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(MakeDfm('TMemoField', 'TDBEdit'));
  try
    Assert.AreEqual(1, Count(F, fkDfmFieldTypeMismatch));
  finally F.Free; end;
end;

procedure TTestDfmFieldTypeMismatch.Test_DBEdit_OnBlob_Detected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(MakeDfm('TBlobField', 'TDBEdit'));
  try
    Assert.AreEqual(1, Count(F, fkDfmFieldTypeMismatch));
  finally F.Free; end;
end;

procedure TTestDfmFieldTypeMismatch.Test_DBMemo_OnMemo_NoFinding;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(MakeDfm('TMemoField', 'TDBMemo'));
  try
    Assert.AreEqual(0, Count(F, fkDfmFieldTypeMismatch));
  finally F.Free; end;
end;

procedure TTestDfmFieldTypeMismatch.Test_DBRichEdit_OnMemo_NoFinding;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(MakeDfm('TMemoField', 'TDBRichEdit'));
  try
    Assert.AreEqual(0, Count(F, fkDfmFieldTypeMismatch));
  finally F.Free; end;
end;

{ --- Phase-1-Schweigen bei tolerierten Kombinationen --- }

procedure TTestDfmFieldTypeMismatch.Test_DBEdit_OnInteger_NoFinding;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(MakeDfm('TIntegerField', 'TDBEdit'));
  try
    Assert.AreEqual(0, Count(F, fkDfmFieldTypeMismatch));
  finally F.Free; end;
end;

procedure TTestDfmFieldTypeMismatch.Test_DBEdit_OnString_NoFinding;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(MakeDfm('TStringField', 'TDBEdit'));
  try
    Assert.AreEqual(0, Count(F, fkDfmFieldTypeMismatch));
  finally F.Free; end;
end;

procedure TTestDfmFieldTypeMismatch.Test_DBEdit_OnDate_StillSilent_Phase1;
// Phase-1-Wahl: TDBEdit auf Date-Feld wird NICHT gemeldet (legitime
// Format-Strings sind verbreitet). Phase 2 kann das verengen.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(MakeDfm('TDateField', 'TDBEdit'));
  try
    Assert.AreEqual(0, Count(F, fkDfmFieldTypeMismatch));
  finally F.Free; end;
end;

{ --- Robustheit --- }

procedure TTestDfmFieldTypeMismatch.Test_UnknownFieldClass_Silent;
// Custom Field-Klasse, die der Detektor nicht klassifizieren kann -
// keine Meldung (konservatives Verhalten).
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(MakeDfm('TWeirdCustomField', 'TDBEdit'));
  try
    Assert.AreEqual(0, Count(F, fkDfmFieldTypeMismatch));
  finally F.Free; end;
end;

procedure TTestDfmFieldTypeMismatch.Test_NoDataSource_Silent;
// Ohne TDataSource kann keine Bindung aufgeloest werden - Detektor
// schweigt, RequiredField-Detektor uebernimmt diesen Fall.
const DFM =
  'object Form: TForm'#13#10 +
  '  object q: TADOQuery'#13#10 +
  '    object qX: TBooleanField FieldName = ''X'' end'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual(0, Count(F, fkDfmFieldTypeMismatch));
  finally F.Free; end;
end;

{ --- Finding-Inhalt --- }

procedure TTestDfmFieldTypeMismatch.Test_Finding_KindAndSeverity;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(MakeDfm('TBooleanField', 'TDBEdit'));
  try
    Assert.AreEqual(fkDfmFieldTypeMismatch, F[0].Kind);
    Assert.AreEqual(lsHint, F[0].Severity);
  finally F.Free; end;
end;

procedure TTestDfmFieldTypeMismatch.Test_Finding_MissingVarMentionsControlAndField;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(MakeDfm('TBooleanField', 'TDBEdit'));
  try
    Assert.Contains(F[0].MissingVar, 'TDBEdit');
    Assert.Contains(F[0].MissingVar, 'TBooleanField');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmFieldTypeMismatch);

end.
