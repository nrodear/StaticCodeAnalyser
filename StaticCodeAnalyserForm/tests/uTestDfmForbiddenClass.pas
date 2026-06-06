unit uTestDfmForbiddenClass;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmForbiddenClass = class
  public
    [Setup]    procedure SetUp;
    [TearDown] procedure TearDown;

    [Test] procedure Test_EmptyList_Silent;
    [Test] procedure Test_ListedClass_Detected;
    [Test] procedure Test_CaseInsensitiveMatch;
    [Test] procedure Test_NonListedClass_NoFinding;
    [Test] procedure Test_MultipleHits_AllReported;
    [Test] procedure Test_Finding_KindAndSeverity;
    [Test] procedure Test_Finding_MissingVarMentionsClassAndName;

    // --- Mehr Varianten ---
    [Test] procedure Test_NestedComponent_ListedClass_Detected;
    [Test] procedure Test_RootObject_ListedClass_Detected;
    [Test] procedure Test_MultipleListEntries_OnlyMatchReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uDfmParser, uComponentGraph,
  uDfmForbiddenClass;

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
      TDfmForbiddenClassDetector.Analyze(Graph, 'test.dfm', Result);
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

procedure TTestDfmForbiddenClass.SetUp;
begin
  if Assigned(DfmForbiddenClasses) then
    DfmForbiddenClasses.Clear;
end;

procedure TTestDfmForbiddenClass.TearDown;
begin
  // Andere Tests koennen die globale Liste auch verwenden - sauber leeren.
  if Assigned(DfmForbiddenClasses) then
    DfmForbiddenClasses.Clear;
end;

procedure TTestDfmForbiddenClass.Test_EmptyList_Silent;
// Default: DfmForbiddenClasses leer -> Detektor inaktiv.
const DFM =
  'object Form: TForm'#13#10 +
  '  object l: TLabel end'#13#10 +
  '  object q: TQuery end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmForbiddenClass));
  finally F.Free; end;
end;

procedure TTestDfmForbiddenClass.Test_ListedClass_Detected;
const DFM = 'object Form: TForm object l: TLabel end end';
var F: TObjectList<TLeakFinding>;
begin
  DfmForbiddenClasses.Add('TLabel');
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmForbiddenClass));
  finally F.Free; end;
end;

procedure TTestDfmForbiddenClass.Test_CaseInsensitiveMatch;
// DfmForbiddenClasses.CaseSensitive = False -> 'TLABEL' matcht 'TLabel'.
const DFM = 'object Form: TForm object l: TLabel end end';
var F: TObjectList<TLeakFinding>;
begin
  DfmForbiddenClasses.Add('tlabel');
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmForbiddenClass));
  finally F.Free; end;
end;

procedure TTestDfmForbiddenClass.Test_NonListedClass_NoFinding;
const DFM = 'object Form: TForm object e: TEdit end end';
var F: TObjectList<TLeakFinding>;
begin
  DfmForbiddenClasses.Add('TLabel');
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmForbiddenClass));
  finally F.Free; end;
end;

procedure TTestDfmForbiddenClass.Test_MultipleHits_AllReported;
const DFM =
  'object Form: TForm'#13#10 +
  '  object l1: TLabel end'#13#10 +
  '  object l2: TLabel end'#13#10 +
  '  object q: TQuery end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  DfmForbiddenClasses.Add('TLabel');
  DfmForbiddenClasses.Add('TQuery');
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(3, Count(F, fkDfmForbiddenClass));
  finally F.Free; end;
end;

procedure TTestDfmForbiddenClass.Test_Finding_KindAndSeverity;
const DFM = 'object Form: TForm object l: TLabel end end';
var F: TObjectList<TLeakFinding>;
begin
  DfmForbiddenClasses.Add('TLabel');
  F := RunOn(DFM);
  try
    Assert.AreEqual(fkDfmForbiddenClass, F[0].Kind);
    Assert.AreEqual(lsHint, F[0].Severity);
  finally F.Free; end;
end;

procedure TTestDfmForbiddenClass.Test_Finding_MissingVarMentionsClassAndName;
const DFM = 'object Form: TForm object lblTitle: TLabel end end';
var F: TObjectList<TLeakFinding>;
begin
  DfmForbiddenClasses.Add('TLabel');
  F := RunOn(DFM);
  try
    Assert.Contains(F[0].MissingVar, 'lblTitle');
    Assert.Contains(F[0].MissingVar, 'TLabel');
  finally F.Free; end;
end;

procedure TTestDfmForbiddenClass.Test_NestedComponent_ListedClass_Detected;
// Untergeordnete Komponente in einem Panel - Detektor laeuft rekursiv.
const DFM =
  'object Form: TForm'#13#10 +
  '  object pnl: TPanel'#13#10 +
  '    object q: TQuery end'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  DfmForbiddenClasses.Add('TQuery');
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmForbiddenClass));
  finally F.Free; end;
end;

procedure TTestDfmForbiddenClass.Test_RootObject_ListedClass_Detected;
// Das Root-Object selbst kann auch eine verbotene Klasse sein
// (z.B. TFrame, wenn man Frames sperrt).
const DFM = 'object Frame1: TFrame end';
var F: TObjectList<TLeakFinding>;
begin
  DfmForbiddenClasses.Add('TFrame');
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmForbiddenClass));
  finally F.Free; end;
end;

procedure TTestDfmForbiddenClass.Test_MultipleListEntries_OnlyMatchReported;
// Forbidden-List enthaelt drei Klassen, nur eine kommt im DFM vor.
const DFM = 'object F: TForm object q: TQuery end end';
var F: TObjectList<TLeakFinding>;
begin
  DfmForbiddenClasses.Add('TQuery');
  DfmForbiddenClasses.Add('TADOConnection');
  DfmForbiddenClasses.Add('TIBQuery');
  F := RunOn(DFM);
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmForbiddenClass));
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmForbiddenClass);

end.
