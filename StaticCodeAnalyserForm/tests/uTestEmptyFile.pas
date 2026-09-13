unit uTestEmptyFile;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEmptyFile = class
  public
    [Test] procedure FileWithDecl_NoFinding;
    [Test] procedure EmptyUnit_Reported;
    [Test] procedure JustConst_NoFinding;
    [Test] procedure EmptyFile_KindAndSeverity;
    // Voll-Review 2026-09-12 (Major 60): Arbeit leistende Units
    [Test] procedure InitializationOnlyUnit_NoFinding;
    [Test] procedure IncludeOnlyUnit_NoFinding;
    // Minor 246: Deklarations-Woerter in Kommentaren zaehlen nicht
    [Test] procedure DeclKeywordOnlyInBlockComment_Reported;
    [Test] procedure DeclKeywordInCodeAfterComment_NoFinding;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestEmptyFile.FileWithDecl_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'procedure Foo;'#13#10 +
  'implementation'#13#10 +
  'procedure Foo; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyFile));
  finally F.Free; end;
end;

procedure TTestEmptyFile.EmptyUnit_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkEmptyFile));
  finally F.Free; end;
end;

procedure TTestEmptyFile.JustConst_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'const X = 1;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyFile));
  finally F.Free; end;
end;

procedure TTestEmptyFile.EmptyFile_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkEmptyFile then
      begin
        Assert.AreEqual<TFindingKind>(fkEmptyFile, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,     Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkEmptyFile finding');
  finally F.Free; end;
end;

procedure TTestEmptyFile.InitializationOnlyUnit_NoFinding;
// Voll-Review 2026-09-12 (Major 60): eine Registrierungs-Unit, deren
// ganzer Zweck der initialization-Seiteneffekt ist, galt als 'leer' -
// der Loeschempfehlung zu folgen braeche das Programm (Bestands-Exe:
// 1 FP, empirisch belegt, ef1.pas).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'initialization'#13#10 +
  '  RegisterFoo;'#13#10 +
  'finalization'#13#10 +
  '  UnregisterFoo;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyFile),
    'initialization-Arbeit ist Inhalt - keine Loeschempfehlung');
  finally F.Free; end;
end;

procedure TTestEmptyFile.IncludeOnlyUnit_NoFinding;
// Zweite Form: Deklarationen kommen aus einem {$I}-Include - die
// '{'-Zeile wurde vorher wie eine Leerzeile uebersprungen.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  '{$I decls.inc}'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyFile),
    'include-basierte Deklarationen sind Inhalt');
  finally F.Free; end;
end;

{ --- Minor 246: kommentbereinigt heisst kommentbereinigt --------- }
//
// Der Unit-Kopf verspricht seit jeher "pro Zeile (kommentbereinigt)",
// die Umsetzung las bis zum Voll-Review 2026-09-12 die ROHZEILE. Eine
// leere Unit, in deren Kopfkommentar irgendwo "procedure Foo;" steht,
// galt damit als gefuellt und wurde nie gemeldet.
//
// Im Korpus zwei echte Faelle, beide von Hand nachgesehen:
// cnwizards IdeInstComp.pas (ein Beispielprogramm im Kommentar) und
// CnPascalGrammar.pas (300 Zeilen Lizenz- und Grammatiktext). Beide
// sind wirklich leere Units.
// Beide Tests am gebauten Stand verprobt.

procedure TTestEmptyFile.DeclKeywordOnlyInBlockComment_Reported;
// Am gebauten Stand nachgemessen: vor dem Fix 0 Funde, danach 1.
const SRC =
  'unit t;'#13#10 +
  '{'#13#10 +
  '  Diese Unit ist leer. Der Text hier erwaehnt'#13#10 +
  '  procedure Foo;'#13#10 +
  '  nur als Beispiel.'#13#10 +
  '}'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'end.'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkEmptyFile),
    'ein procedure im Kommentar ist keine Deklaration');
  finally F.Free; end;
end;

procedure TTestEmptyFile.DeclKeywordInCodeAfterComment_NoFinding;
// Die Gegenprobe, und sie prueft zugleich den Kommentar-ZUSTAND: nach
// dem mehrzeiligen Kommentar folgt eine ECHTE Deklaration. Wuerde der
// Scanner den Kommentar nicht sauber schliessen, hielte er auch sie
// fuer Text - und die Unit gaelte faelschlich als leer.
const SRC =
  'unit t;'#13#10 +
  '{'#13#10 +
  '  Diese Unit ist NICHT leer.'#13#10 +
  '}'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyFile),
    'die Typdeklaration hinter dem Kommentar zaehlt');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEmptyFile);

end.
