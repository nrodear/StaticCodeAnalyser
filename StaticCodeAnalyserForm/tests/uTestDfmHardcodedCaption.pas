unit uTestDfmHardcodedCaption;

// Smoke-Tests für TDfmHardcodedCaptionDetector.
// Validiert die Property-Capture-Pipeline aus Iteration 2:
// Lexer -> Parser -> ComponentGraph (mit Properties) -> Detektor -> Findings.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmHardcodedCaption = class
  public
    // --- Treffer ---
    [Test] procedure Test_Caption_Detected;
    [Test] procedure Test_Hint_Detected;
    [Test] procedure Test_Text_Detected;
    [Test] procedure Test_Caption_OnNestedChild_Detected;
    [Test] procedure Test_MultipleProps_OnSameComponent_AllReported;

    // --- Nicht-Treffer ---
    [Test] procedure Test_EmptyCaption_NotDetected;
    [Test] procedure Test_WhitespaceOnlyCaption_NotDetected;
    [Test] procedure Test_NonStringValue_NotDetected;       // Ident wie 'clRed'
    [Test] procedure Test_NonWhitelistedProp_NotDetected;   // 'Filter' etc.
    [Test] procedure Test_NumericProp_NotDetected;          // 'Top = 42'

    // --- Finding-Inhalt ---
    [Test] procedure Test_Finding_LineNumberMatchesValueLine;
    [Test] procedure Test_Finding_MissingVarContainsComponentAndValue;
    [Test] procedure Test_Finding_SeverityIsHint;
    [Test] procedure Test_Finding_KindIsHardcodedCaption;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uDfmParser, uComponentGraph,
  uDfmHardcodedCaption;

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
      TDfmHardcodedCaptionDetector.Analyze(Graph, 'test.dfm', Result);
    finally
      Graph.Free;
    end;
  finally
    Parser.Free;
  end;
end;

function CountKind(F: TObjectList<TLeakFinding>; K: TFindingKind): Integer;
var Fnd: TLeakFinding;
begin
  Result := 0;
  for Fnd in F do
    if Fnd.Kind = K then Inc(Result);
end;

{ --- Treffer --- }

procedure TTestDfmHardcodedCaption.Test_Caption_Detected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form2: TForm2'#13#10 +
    '  Caption = ''Static Code Analysis Tool'''#13#10 +
    'end');
  try
    Assert.AreEqual(1, CountKind(F, fkDfmHardcodedCaption));
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Test_Hint_Detected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form2: TForm2'#13#10 +
    '  object btnSave: TButton'#13#10 +
    '    Hint = ''Save the current file'''#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual(1, CountKind(F, fkDfmHardcodedCaption));
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Test_Text_Detected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form2: TForm2'#13#10 +
    '  object lblWelcome: TLabel'#13#10 +
    '    Text = ''Welcome'''#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual(1, CountKind(F, fkDfmHardcodedCaption));
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Test_Caption_OnNestedChild_Detected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object pnlOuter: TPanel'#13#10 +
    '    object pnlInner: TPanel'#13#10 +
    '      object btn: TButton'#13#10 +
    '        Caption = ''Speichern'''#13#10 +
    '      end'#13#10 +
    '    end'#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual(1, CountKind(F, fkDfmHardcodedCaption));
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Test_MultipleProps_OnSameComponent_AllReported;
// Eine Komponente mit Caption UND Hint UND Text -> 3 Befunde.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object btn: TButton'#13#10 +
    '    Caption = ''OK'''#13#10 +
    '    Hint = ''Confirm action'''#13#10 +
    '    Text = ''btn-text'''#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual(3, CountKind(F, fkDfmHardcodedCaption));
  finally F.Free; end;
end;

{ --- Nicht-Treffer --- }

procedure TTestDfmHardcodedCaption.Test_EmptyCaption_NotDetected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object btn: TButton'#13#10 +
    '    Caption = '''''#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual(0, CountKind(F, fkDfmHardcodedCaption));
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Test_WhitespaceOnlyCaption_NotDetected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object btn: TButton'#13#10 +
    '    Caption = ''   '''#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual(0, CountKind(F, fkDfmHardcodedCaption));
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Test_NonStringValue_NotDetected;
// 'Color = clRed' ist pvkIdent, kein String -> kein UI-Text-Befund.
// Selbst wenn Color hypothetisch in der Whitelist waere, wuerde der Wert-
// Kind-Filter greifen.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  Color = clBtnFace'#13#10 +
    'end');
  try
    Assert.AreEqual(0, CountKind(F, fkDfmHardcodedCaption));
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Test_NonWhitelistedProp_NotDetected;
// 'Filter' bei TOpenDialog ist auch UI-Text, ist aber bewusst nicht in der
// Phase-1-Whitelist. Wenn jemand das ergaenzt, wuerde dieser Test rot - das
// ist absichtlich der Pin-Test fuer die aktuelle Whitelist-Politik.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Dlg: TOpenDialog'#13#10 +
    '  Filter = ''All files (*.*)|*.*'''#13#10 +
    'end');
  try
    Assert.AreEqual(0, CountKind(F, fkDfmHardcodedCaption));
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Test_NumericProp_NotDetected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  Top = 42'#13#10 +
    '  Left = 100'#13#10 +
    'end');
  try
    Assert.AreEqual(0, CountKind(F, fkDfmHardcodedCaption));
  finally F.Free; end;
end;

{ --- Finding-Inhalt --- }

procedure TTestDfmHardcodedCaption.Test_Finding_LineNumberMatchesValueLine;
// Befund-Zeile zeigt auf die Property-Zeile (nicht die Object-Header-Zeile),
// damit IDE-Marker bzw. Editor-Sprung zum richtigen Ort fuehrt.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +    // Zeile 1
    '  object btn: TButton'#13#10 + // Zeile 2
    '    Caption = ''OK'''#13#10 +  // Zeile 3
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(1, F.Count);
    Assert.AreEqual('3', F[0].LineNumber);
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Test_Finding_MissingVarContainsComponentAndValue;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object btn: TButton'#13#10 +
    '    Caption = ''Speichern'''#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(1, F.Count);
    Assert.Contains(F[0].MissingVar, 'btn');
    Assert.Contains(F[0].MissingVar, 'Caption');
    Assert.Contains(F[0].MissingVar, 'Speichern');
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Test_Finding_SeverityIsHint;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm Caption = ''X'' end');
  try
    Assert.AreEqual(lsHint, F[0].Severity);
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Test_Finding_KindIsHardcodedCaption;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm Caption = ''X'' end');
  try
    Assert.AreEqual(fkDfmHardcodedCaption, F[0].Kind);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmHardcodedCaption);

end.
