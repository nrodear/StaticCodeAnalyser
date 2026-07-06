unit uTestLongParamList;

// Tests fuer TLongParamListDetector. Schwellwert (Default 5 Parameter)
// kommt aus FRepoSettings.LongParamListMaxParams.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestLongParamList = class
  public
    [Test] procedure FewParams_NoFinding;
    [Test] procedure ManyParams_Reported;
    [Test] procedure Finding_KindAndSeverity;
    // TD-1 (Thread-Safety Inkrement 1): der Detektor liest seine Schwelle aus
    // AContext.Config statt direkt vom uSCAConsts-Prozess-Global.
    [Test] procedure ContextConfig_OverridesGlobal;
    [Test] procedure NilContext_FallsBackToGlobal;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uParser2, uAstNode, uAnalyzeContext, uLongParamList,
  uTestFindingHelper;

procedure TTestLongParamList.FewParams_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(A, B: Integer); begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLongParamList));
  finally F.Free; end;
end;

procedure TTestLongParamList.ManyParams_Reported;
// 8 Parameter weit ueber dem Default-Schwellwert (5).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(A, B, C, D, E, F, G, H: Integer); begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkLongParamList) >= 1);
  finally F.Free; end;
end;

procedure TTestLongParamList.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(A, B, C, D, E, F, G, H: Integer); begin end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkLongParamList then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkLongParamList finding expected');
    Assert.AreEqual(fkLongParamList, Hit.Kind);
  finally F.Free; end;
end;

procedure TTestLongParamList.ContextConfig_OverridesGlobal;
// TD-1 (Inkrement 1): der Detektor liest die Param-Schwelle aus AContext.Config,
// NICHT mehr direkt vom uSCAConsts-Global. Beweis: eine 4-Parameter-Methode;
// Global HOCH (4 <= 10 -> Global allein wuerde NICHT melden), Context NIEDRIG
// (4 > 2 -> Context MELDET). Kommt der Fund, hat der Detektor den Context-Wert
// benutzt und nicht das Global.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(A, B, C, D: Integer); begin end;';   // 4 Parameter
var
  Parser : TParser2;
  Root   : TAstNode;
  Ctx    : TAnalyzeContext;
  Res    : TObjectList<TLeakFinding>;
  OldMax : Integer;
begin
  OldMax := uSCAConsts.DetectorMaxParams;
  Parser := TParser2.Create;
  Ctx    := TAnalyzeContext.Create;
  Res    := TObjectList<TLeakFinding>.Create(True);
  try
    uSCAConsts.DetectorMaxParams := 10;   // Global wuerde NICHT melden (4 <= 10)
    Ctx.Config.MaxParams         := 2;    // Context MELDET (4 > 2)
    Root := Parser.ParseSource(SRC);
    try
      TLongParamListDetector.AnalyzeUnit(Root, 'sample.pas', Res, Ctx);
    finally
      Root.Free;
    end;
    Assert.IsTrue(TFindingHelper.Count(Res, fkLongParamList) >= 1,
      'Fund muss sich nach Ctx.Config.MaxParams (=2) richten, nicht nach dem Global (=10)');
  finally
    uSCAConsts.DetectorMaxParams := OldMax;   // Global restaurieren
    Res.Free;
    Ctx.Free;
    Parser.Free;
  end;
end;

procedure TTestLongParamList.NilContext_FallsBackToGlobal;
// TD-1 (Inkrement 1): AContext=nil MUSS weiter das uSCAConsts-Global lesen
// (Tests/Single-File-Pfad, byte-identisch zum Alt-Verhalten). Dieselbe
// 4-Parameter-Methode: mit Global=2 kommt ein Fund, mit Global=10 keiner -
// das Verhalten folgt also exakt dem Global, nicht dem (nil-)Context.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(A, B, C, D: Integer); begin end;';   // 4 Parameter
var
  Parser     : TParser2;
  Root       : TAstNode;
  Res1, Res2 : TObjectList<TLeakFinding>;
  OldMax     : Integer;
begin
  OldMax := uSCAConsts.DetectorMaxParams;
  Parser := TParser2.Create;
  Res1   := TObjectList<TLeakFinding>.Create(True);
  Res2   := TObjectList<TLeakFinding>.Create(True);
  try
    Root := Parser.ParseSource(SRC);
    try
      uSCAConsts.DetectorMaxParams := 2;    // 4 > 2  -> Fund erwartet
      TLongParamListDetector.AnalyzeUnit(Root, 'sample.pas', Res1, nil);
      uSCAConsts.DetectorMaxParams := 10;   // 4 <= 10 -> kein Fund erwartet
      TLongParamListDetector.AnalyzeUnit(Root, 'sample.pas', Res2, nil);
    finally
      Root.Free;
    end;
    Assert.IsTrue(TFindingHelper.Count(Res1, fkLongParamList) >= 1,
      'AContext=nil bei Global=2 muss melden (Global-Fallback)');
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(Res2, fkLongParamList),
      'AContext=nil bei Global=10 darf NICHT melden (Global-Fallback)');
  finally
    uSCAConsts.DetectorMaxParams := OldMax;   // Global restaurieren
    Res1.Free;
    Res2.Free;
    Parser.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLongParamList);

end.
