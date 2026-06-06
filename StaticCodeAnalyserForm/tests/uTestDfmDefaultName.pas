unit uTestDfmDefaultName;

// Smoke-Tests für TDfmDefaultNameDetector - End-to-End-Validierung der
// Phase-1-Pipeline: TDfmParser -> TComponentGraph -> Detektor -> Findings.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmDefaultName = class
  public
    [Test] procedure Test_Button1_Detected;
    [Test] procedure Test_Edit3_Detected;
    [Test] procedure Test_Panel2_Detected;

    [Test] procedure Test_CustomName_NotDetected;
    [Test] procedure Test_PrefixedName_NotDetected;
    [Test] procedure Test_NameWithoutTrailingDigit_NotDetected;
    [Test] procedure Test_FormItselfWithDigit_NotDetected;

    [Test] procedure Test_DefaultNameInDeeplyNested_StillDetected;
    [Test] procedure Test_MultipleDefaultNames_AllReported;

    [Test] procedure Test_Finding_LineNumberMatchesObjectHeader;
    [Test] procedure Test_Finding_MissingVarContainsNameAndClass;
    [Test] procedure Test_Finding_SeverityIsHint;
    [Test] procedure Test_Finding_KindIsDfmDefaultName;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uDfmParser, uComponentGraph,
  uDfmDefaultName;

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
      TDfmDefaultNameDetector.Analyze(Graph, 'test.dfm', Result);
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

{ --- Treffer-Fälle --- }

procedure TTestDfmDefaultName.Test_Button1_Detected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form2: TForm2'#13#10 +
    '  object Button1: TButton'#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual(1, CountKind(F, fkDfmDefaultName));
  finally F.Free; end;
end;

procedure TTestDfmDefaultName.Test_Edit3_Detected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form2: TForm2'#13#10 +
    '  object Edit3: TEdit'#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual(1, CountKind(F, fkDfmDefaultName));
  finally F.Free; end;
end;

procedure TTestDfmDefaultName.Test_Panel2_Detected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form2: TForm2'#13#10 +
    '  object Panel2: TPanel'#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual(1, CountKind(F, fkDfmDefaultName));
  finally F.Free; end;
end;

{ --- Nicht-Treffer-Fälle --- }

procedure TTestDfmDefaultName.Test_CustomName_NotDetected;
// 'btnSave' folgt nicht dem 'Button<n>'-Muster -> kein Befund.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form2: TForm2'#13#10 +
    '  object btnSave: TButton'#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual(0, CountKind(F, fkDfmDefaultName));
  finally F.Free; end;
end;

procedure TTestDfmDefaultName.Test_PrefixedName_NotDetected;
// 'SaveButton1' enthaelt 'Button1' am Ende, beginnt aber nicht mit 'Button'
// -> Heuristik wird nur an exakter Praefix-Position ausgewertet, kein Treffer.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form2: TForm2'#13#10 +
    '  object SaveButton1: TButton'#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual(0, CountKind(F, fkDfmDefaultName));
  finally F.Free; end;
end;

procedure TTestDfmDefaultName.Test_NameWithoutTrailingDigit_NotDetected;
// 'Button' ohne Zahl -> kein Default-Name.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form2: TForm2'#13#10 +
    '  object Button: TButton'#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual(0, CountKind(F, fkDfmDefaultName));
  finally F.Free; end;
end;

procedure TTestDfmDefaultName.Test_FormItselfWithDigit_NotDetected;
// 'Form2: TForm2' - Klassen-Suffix 'Form2' enthaelt selbst Ziffer; nach
// Abzug bleibt nichts uebrig -> kein Default-Name. Wenn die Form als
// 'Form2: TForm' deklariert ist, wuerde der Detektor allerdings 'Form2'
// als Default ansehen (siehe Folgetest).
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn('object Form2: TForm2 end');
  try
    Assert.AreEqual(0, CountKind(F, fkDfmDefaultName));
  finally F.Free; end;
end;

{ --- Vorkommen in Verschachtelung --- }

procedure TTestDfmDefaultName.Test_DefaultNameInDeeplyNested_StillDetected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object pnlOuter: TPanel'#13#10 +
    '    object pnlInner: TPanel'#13#10 +
    '      object Memo1: TMemo'#13#10 +
    '      end'#13#10 +
    '    end'#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual(1, CountKind(F, fkDfmDefaultName));
  finally F.Free; end;
end;

procedure TTestDfmDefaultName.Test_MultipleDefaultNames_AllReported;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object Button1: TButton'#13#10 +
    '  end'#13#10 +
    '  object Button2: TButton'#13#10 +
    '  end'#13#10 +
    '  object Edit1: TEdit'#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual(3, CountKind(F, fkDfmDefaultName));
  finally F.Free; end;
end;

{ --- Finding-Inhalt --- }

procedure TTestDfmDefaultName.Test_Finding_LineNumberMatchesObjectHeader;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +       // Zeile 1
    '  Caption = ''X'''#13#10 +        // Zeile 2
    '  object Button1: TButton'#13#10 +// Zeile 3
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(1, F.Count);
    Assert.AreEqual('3', F[0].LineNumber);
  finally F.Free; end;
end;

procedure TTestDfmDefaultName.Test_Finding_MissingVarContainsNameAndClass;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object Button1: TButton'#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(1, F.Count);
    Assert.Contains(F[0].MissingVar, 'Button1');
    Assert.Contains(F[0].MissingVar, 'TButton');
  finally F.Free; end;
end;

procedure TTestDfmDefaultName.Test_Finding_SeverityIsHint;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object Button1: TButton'#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual(lsHint, F[0].Severity);
  finally F.Free; end;
end;

procedure TTestDfmDefaultName.Test_Finding_KindIsDfmDefaultName;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object Button1: TButton'#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual(fkDfmDefaultName, F[0].Kind);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmDefaultName);

end.
