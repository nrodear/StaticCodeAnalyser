unit uTestTooLongLine;

// Tests fuer TTooLongLineDetector (file-scan).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestTooLongLine = class
  public
    [Test] procedure ShortLines_NoFinding;
    [Test] procedure ExactlyAtLimit_NoFinding;
    [Test] procedure OverLimit_Reported;
    [Test] procedure MultipleOverLimit_AllReported;
    [Test] procedure TooLongLine_KindAndSeverity;
    // Voll-Review 2026-09-12 (Testluecke 112): der Konfig-Pfad
    [Test] procedure ContextConfig_OverridesGlobal;
    [Test] procedure NilContext_FallsBackToGlobal;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  System.Generics.Collections,
  uSCAConsts, uMethodd12, uAstNode, uParser2, uAnalyzeContext,
  uTooLongLine,
  uTestFindingHelper;

// Schreibt SRC in eine temporaere .pas und laesst NUR den
// TooLongLine-Detektor darueber laufen - mit dem uebergebenen Context.
// Eigener Helfer, weil TFindingHelper.FindingsOfFile keinen Context
// durchreicht und der Konfig-Pfad genau daran haengt.
function FindingsMitContext(const SRC: string;
  ACtx: TAnalyzeContext): TObjectList<TLeakFinding>;
var
  Parser   : TParser2;
  Root     : TAstNode;
  TempPath : string;
  SL       : TStringList;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  TempPath := TPath.Combine(TPath.GetTempPath,
    'sca_tll_' + TGuid.NewGuid.ToString.Replace('{','').Replace('}','')
      .Replace('-','') + '.pas');
  SL := TStringList.Create;
  try
    SL.Text := SRC;
    SL.SaveToFile(TempPath, TEncoding.UTF8);
  finally
    SL.Free;
  end;
  try
    Parser := TParser2.Create;
    try
      Root := Parser.ParseFile(TempPath);
      try
        TTooLongLineDetector.AnalyzeUnit(Root, TempPath, Result, ACtx);
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

procedure TTestTooLongLine.ShortLines_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTooLongLine));
  finally F.Free; end;
end;

procedure TTestTooLongLine.ExactlyAtLimit_NoFinding;
// MAX_LINE_LEN = 120 -> 120 Zeichen sind OK, 121 sind Treffer.
var
  Line : string;
  SRC  : string;
  F    : TObjectList<TLeakFinding>;
begin
  Line := 'unit t; implementation' + #13#10;
  // Genau 120 Zeichen
  Line := Line + StringOfChar('A', 120) + #13#10;
  SRC := Line;
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTooLongLine));
  finally F.Free; end;
end;

procedure TTestTooLongLine.OverLimit_Reported;
var
  SRC : string;
  F   : TObjectList<TLeakFinding>;
begin
  // 121 Zeichen = ueber Schwelle
  SRC := 'unit t; implementation' + #13#10 + StringOfChar('A', 121) + #13#10;
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTooLongLine));
  finally F.Free; end;
end;

procedure TTestTooLongLine.MultipleOverLimit_AllReported;
var
  SRC : string;
  F   : TObjectList<TLeakFinding>;
begin
  SRC := 'unit t; implementation' + #13#10 +
         StringOfChar('A', 150) + #13#10 +
         '  short'                + #13#10 +
         StringOfChar('B', 200) + #13#10;
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkTooLongLine));
  finally F.Free; end;
end;

procedure TTestTooLongLine.TooLongLine_KindAndSeverity;
var
  SRC : string;
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  SRC := 'unit t; implementation' + #13#10 + StringOfChar('X', 130) + #13#10;
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkTooLongLine then
      begin
        Assert.AreEqual<TFindingKind>(fkTooLongLine, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,       Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkTooLongLine finding');
  finally F.Free; end;
end;

procedure TTestTooLongLine.ContextConfig_OverridesGlobal;
// Testluecke 112 (Voll-Review 2026-09-12): alle Bestandstests laufen
// gegen den 120er-Default; dass der Detektor die Schwelle wirklich aus
// AContext.Config liest (TD-1) und nicht vom uSCAConsts-Global, war
// nirgends fixiert.
//
// Beweisfuehrung wie in uTestLongParamList.ContextConfig_OverridesGlobal:
// eine 40-Zeichen-Zeile; Global HOCH (40 <= 200 -> Global allein wuerde
// NICHT melden), Context NIEDRIG (40 > 20 -> Context MELDET).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; begin DoSomethingRatherLong; end;';
var
  Ctx    : TAnalyzeContext;
  Res    : TObjectList<TLeakFinding>;
  OldMax : Integer;
begin
  OldMax := uSCAConsts.DetectorMaxLineLength;
  Ctx    := TAnalyzeContext.Create;
  try
    uSCAConsts.DetectorMaxLineLength := 200;   // Global wuerde NICHT melden
    Ctx.Config.MaxLineLength         := 20;    // Context MELDET
    Res := FindingsMitContext(SRC, Ctx);
    try
      Assert.IsTrue(TFindingHelper.Count(Res, fkTooLongLine) >= 1,
        'die Schwelle muss aus Ctx.Config.MaxLineLength kommen (=20), ' +
        'nicht aus dem Global (=200)');
    finally
      Res.Free;
    end;
  finally
    uSCAConsts.DetectorMaxLineLength := OldMax;   // Global restaurieren
    Ctx.Free;
  end;
end;

procedure TTestTooLongLine.NilContext_FallsBackToGlobal;
// Gegenstueck: AContext = nil MUSS weiter das uSCAConsts-Global lesen
// (Tests / Single-File-Pfad). Dieselbe Zeile, zweimal - mit Global 20
// kommt ein Fund, mit Global 200 keiner. Das Verhalten folgt also exakt
// dem Global.
//
// Der Detektor liest die Datei ueber den Zeilen-Cache; beide Laeufe
// bekommen deshalb eine EIGENE temporaere Datei (FindingsMitContext
// erzeugt je Aufruf eine neue) - sonst saehe der zweite Lauf den Inhalt
// des ersten (dokumentierte Cache-Falle des Projekts).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; begin DoSomethingRatherLong; end;';
var
  Res1, Res2 : TObjectList<TLeakFinding>;
  OldMax     : Integer;
begin
  OldMax := uSCAConsts.DetectorMaxLineLength;
  try
    uSCAConsts.DetectorMaxLineLength := 20;
    Res1 := FindingsMitContext(SRC, nil);
    try
      Assert.IsTrue(TFindingHelper.Count(Res1, fkTooLongLine) >= 1,
        'nil-Context: Global 20 muss melden');
    finally
      Res1.Free;
    end;

    uSCAConsts.DetectorMaxLineLength := 200;
    Res2 := FindingsMitContext(SRC, nil);
    try
      Assert.AreEqual<Integer>(0, TFindingHelper.Count(Res2, fkTooLongLine),
        'nil-Context: Global 200 darf nicht melden');
    finally
      Res2.Free;
    end;
  finally
    uSCAConsts.DetectorMaxLineLength := OldMax;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestTooLongLine);

end.
