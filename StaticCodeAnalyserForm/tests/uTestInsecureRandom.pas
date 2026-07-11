unit uTestInsecureRandom;

// Tests fuer TInsecureRandomDetector (SCA167).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestInsecureRandom = class
  public
    [Test] procedure RandomWithoutRandomize_Reported;
    [Test] procedure RandomRangeWithoutRandomize_Reported;
    [Test] procedure RandomWithRandomize_NotReported;
    [Test] procedure QualifiedRandomize_AlsoCounts;
    [Test] procedure SelfDotRandomCall_StillReported;
    [Test] procedure ForeignObjectRandom_NoFinding;
    [Test] procedure BareRandomRange_StillReported;
    // FP-Guard Klasse A (Todo_FP_SCA167, 2026-07-11): Randomize in einer
    // initialization-Sektion muss den Fund unterdruecken - der nkCall-Pass1
    // sieht diesen Body nicht (Parser skipt ihn), der Roh-Quellen-Guard schon.
    [Test] procedure RandomizeInInitializationSection_NotReported;
    // TP-Guard fuer den Guard selbst: 'Randomize' in Kommentar / String-Literal
    // ist KEIN Code-Use und darf den echten Bug NICHT unterdruecken.
    [Test] procedure RandomizeInComment_StillReported;
    [Test] procedure RandomizeInStringLiteral_StillReported;
    // TP-Kontrolle auf dem file-basierten Pfad: ohne jedes Randomize feuert es.
    [Test] procedure RandomWithoutRandomize_FileBased_Reported;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uAstNode, uParser2, uInsecureRandom,
  uTestFindingHelper;

// Isolierter file-basierter Harness NUR fuer SCA167. Der Klasse-A-FP-Guard
// (SourceHasRandomize) liest die Roh-Quelle per AcquireLines von PLATTE -
// der In-Memory-Harness TFindingHelper.FindingsOf (ParseSource, kein File)
// kann ihn nicht ausueben. Bewusst NICHT ueber TFindingHelper.FindingsOfFile,
// um andere Detektoren (dort registriert) nicht mitlaufen zu lassen.
function Sca167FindingsFromFile(const Source: string): TObjectList<TLeakFinding>;
var
  Parser   : TParser2;
  Root     : TAstNode;
  TempPath : string;
  SL       : TStringList;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  TempPath := TPath.Combine(TPath.GetTempPath,
    'sca167_' + TGuid.NewGuid.ToString
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
        TInsecureRandomDetector.AnalyzeUnit(Root, TempPath, Result);
      finally
        Root.Free;
      end;
    finally
      Parser.Free;
    end;
  finally
    if TFile.Exists(TempPath) then
      TFile.Delete(TempPath);
  end;
end;

procedure TTestInsecureRandom.RandomWithoutRandomize_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  i := Random(100);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkInsecureRandom) >= 1,
      'Random(100) ohne Randomize muss gemeldet werden');
  finally F.Free; end;
end;

procedure TTestInsecureRandom.RandomRangeWithoutRandomize_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  i := RandomRange(1, 6);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkInsecureRandom) >= 1,
      'RandomRange ohne Randomize muss gemeldet werden');
  finally F.Free; end;
end;

procedure TTestInsecureRandom.RandomWithRandomize_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Init;'#13#10 +
  'begin'#13#10 +
  '  Randomize;'#13#10 +
  'end;'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  i := Random(100);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInsecureRandom),
      'Randomize-Aufruf irgendwo in der Unit unterdrueckt Findings');
  finally F.Free; end;
end;

procedure TTestInsecureRandom.QualifiedRandomize_AlsoCounts;
// System.Randomize / Self.Randomize sollten ebenfalls zaehlen (Bare-Name-Strip).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Init;'#13#10 +
  'begin'#13#10 +
  '  System.Randomize;'#13#10 +
  'end;'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  i := Random(100);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInsecureRandom),
      'System.Randomize muss als Randomize zaehlen');
  finally F.Free; end;
end;

procedure TTestInsecureRandom.SelfDotRandomCall_StillReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Init;'#13#10 +
  'begin'#13#10 +
  '  i := Self.Random(100);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkInsecureRandom) >= 1,
      'Self.Random muss als Random-Call zaehlen');
  finally F.Free; end;
end;

procedure TTestInsecureRandom.ForeignObjectRandom_NoFinding;
// FP-Guard (2026-06-28/29): object-qualified Custom-RNG (FRng.Random) verwaltet
// einen EIGENEN Seed -> keine deterministische RTL-Random -> darf NICHT melden,
// auch wenn nirgends Randomize aufgerufen wird.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Roll;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  i := FRng.Random(100);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInsecureRandom),
      'FRng.Random ist Custom-RNG, kein InsecureRandom');
  finally F.Free; end;
end;

procedure TTestInsecureRandom.BareRandomRange_StillReported;
// Unqualified RandomRange ohne Randomize bleibt globale RTL-Random -> Finding.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Roll;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  i := RandomRange(1, 6);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkInsecureRandom) >= 1,
      'bare RandomRange ohne Randomize muss gemeldet werden');
  finally F.Free; end;
end;

procedure TTestInsecureRandom.RandomizeInInitializationSection_NotReported;
// FP-Regression (Todo_FP_SCA167 Klasse A): dieselbe Unit ruft parameterloses
// Randomize in ihrer initialization-Sektion auf. uParser2 skipt den Sektions-
// Body -> KEIN nkCall 'Randomize' -> Pass1 verpasst es. Der Roh-Quellen-Guard
// muss den Random(100)-Fund trotzdem unterdruecken (globaler Seed ist gesetzt).
const SRC =
  'unit t;'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  i := Random(100);'#13#10 +
  'end;'#13#10 +
  'initialization'#13#10 +
  '  Randomize;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := Sca167FindingsFromFile(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInsecureRandom),
      'Randomize in initialization-Sektion unterdrueckt den Fund');
  finally F.Free; end;
end;

procedure TTestInsecureRandom.RandomizeInComment_StillReported;
// TP-Guard: 'Randomize' steht NUR in einem Kommentar -> kein Code-Use ->
// der echte Random(100)-Bug MUSS weiter feuern (Guard skipt Kommentar-Token).
const SRC =
  'unit t;'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  // TODO: call Randomize once at startup'#13#10 +
  '  i := Random(100);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := Sca167FindingsFromFile(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkInsecureRandom) >= 1,
      'Randomize im Kommentar darf den echten Bug NICHT unterdruecken');
  finally F.Free; end;
end;

procedure TTestInsecureRandom.RandomizeInStringLiteral_StillReported;
// TP-Guard: 'Randomize' steht NUR in einem String-Literal -> kein Code-Use ->
// der echte Random(100)-Bug MUSS weiter feuern (Guard blendet Strings aus).
const SRC =
  'unit t;'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  Writeln(''please call Randomize'');'#13#10 +
  '  i := Random(100);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := Sca167FindingsFromFile(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkInsecureRandom) >= 1,
      'Randomize im String-Literal darf den echten Bug NICHT unterdruecken');
  finally F.Free; end;
end;

procedure TTestInsecureRandom.RandomWithoutRandomize_FileBased_Reported;
// TP-Kontrolle: derselbe file-basierte Pfad ohne jedes Randomize feuert -
// beweist, dass der Guard nicht generell alles unterdrueckt.
const SRC =
  'unit t;'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  i := Random(100);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := Sca167FindingsFromFile(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkInsecureRandom) >= 1,
      'Random(100) ohne jedes Randomize muss auch file-basiert feuern');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestInsecureRandom);

end.
