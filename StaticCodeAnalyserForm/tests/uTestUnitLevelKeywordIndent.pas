unit uTestUnitLevelKeywordIndent;

// Tests fuer TUnitLevelKeywordIndentDetector.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestUnitLevelKeywordIndent = class
  public
    [Test] procedure FlushLeftKeywords_NoFinding;
    [Test] procedure IndentedImplementation_Reported;
    [Test] procedure IndentedInitialization_Reported;
    [Test] procedure IndentedInterface_AloneOnLine_Reported;
    [Test] procedure InterfaceInTypeDecl_NotReported;
    [Test] procedure UnitLevelKeywordIndent_KindAndSeverity;
    // FP-Paket 2026-08-27: der Detektor las rohe Zeilen ohne Kommentar-
    // Zustand - 175 der 207 Korpus-Funde standen im Innenraum
    // mehrzeiliger Kommentare.
    [Test] procedure DocHeaderInBraceComment_NoFinding;
    [Test] procedure EnglishProseInBraceComment_NoFinding;
    [Test] procedure SampleCodeInStarComment_NoFinding;
    [Test] procedure CodeAfterCommentBlock_StillReported;
    [Test] procedure UsesWithDirectiveTail_ReportedWithColumn;
    [Test] procedure BraceInsideStringLiteral_DoesNotSwallowFile;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestUnitLevelKeywordIndent.FlushLeftKeywords_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'uses System.SysUtils;'#13#10 +
  'implementation'#13#10 +
  'procedure Foo; begin end;'#13#10 +
  'initialization'#13#10 +
  '  Foo;'#13#10 +
  'finalization'#13#10 +
  '  Foo;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnitLevelKeywordIndent));
  finally F.Free; end;
end;

procedure TTestUnitLevelKeywordIndent.IndentedImplementation_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  '  implementation'#13#10 +
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnitLevelKeywordIndent));
  finally F.Free; end;
end;

procedure TTestUnitLevelKeywordIndent.IndentedInitialization_Reported;
const SRC =
  'unit t;'#13#10 +
  'implementation'#13#10 +
  '  initialization'#13#10 +
  '  Foo;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnitLevelKeywordIndent));
  finally F.Free; end;
end;

procedure TTestUnitLevelKeywordIndent.IndentedInterface_AloneOnLine_Reported;
const SRC =
  'unit t;'#13#10 +
  '  interface'#13#10 +
  'uses x;'#13#10 +
  'implementation';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnitLevelKeywordIndent));
  finally F.Free; end;
end;

procedure TTestUnitLevelKeywordIndent.InterfaceInTypeDecl_NotReported;
// `interface` als Typ-Konstrukt darf eingerueckt sein - es ist NICHT
// Unit-Section. Test: das Wort `interface` ist nicht das einzige auf
// der Zeile (RestEmpty = False), daher kein Treffer.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  IMyService = interface(IUnknown)'#13#10 +
  '    procedure DoStuff;'#13#10 +
  '  end;'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnitLevelKeywordIndent));
  finally F.Free; end;
end;

procedure TTestUnitLevelKeywordIndent.UnitLevelKeywordIndent_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  '   implementation'#13#10 +
  'procedure Foo; begin end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkUnitLevelKeywordIndent then
      begin
        Assert.AreEqual<TFindingKind>(fkUnitLevelKeywordIndent, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,                  Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkUnitLevelKeywordIndent finding');
  finally F.Free; end;
end;

procedure TTestUnitLevelKeywordIndent.DocHeaderInBraceComment_NoFinding;
// Der haeufigste FP im Korpus: der Doku-Kopf, den die Delphi-IDE-Experten
// und diverse Generatoren erzeugen (pyscripter/frmPyIDEMain.pas:2,
// dlgPickList.pas:2, cPyBaseDebugger.pas:2 - gleiche Schablone in 7
// Dateien). Zeile 2 beginnt im Kommentar, ist also niemals Code.
const SRC =
  'unit t;'#13#10 +
  '{--- Unit Name: t'#13#10 +
  '     Unit Description:'#13#10 +
  '     implementation notes for the widget cache'#13#10 +
  '---}'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnitLevelKeywordIndent));
  finally F.Free; end;
end;

procedure TTestUnitLevelKeywordIndent.EnglishProseInBraceComment_NoFinding;
// Englische Prosa in einem mehrzeiligen { }-Kommentar: 'Implementation
// of ...' und ein alleinstehendes 'interface' als Fliesstext-Zeile
// (Indy/IdCoderBinHex4.pas:123, JvFillIntf4.pas:66, gifimage.pas:94).
// Das Wort ist Prosa, keine Sektion - und Prosa faengt gerne eingerueckt
// an.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  '{ Diese Unit kapselt den Cache.'#13#10 +
  '  Implementation of the RFC parser is described below;'#13#10 +
  '  interface'#13#10 +
  '  the caller never sees it. }'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnitLevelKeywordIndent));
  finally F.Free; end;
end;

procedure TTestUnitLevelKeywordIndent.SampleCodeInStarComment_NoFinding;
// @longcode-Beispielunit in einem (* *)-Kommentar. Im Korpus lieferte
// EIN solcher Doku-Block (LoggerPro.pas:761-783) 12 Funde - der
// teuerste Einzelfall. Beispielcode in Kommentaren ist per Hausregel
// kein Code.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  '(*'#13#10 +
  '  unit LoggerProConfig;'#13#10 +
  '  interface'#13#10 +
  '  uses'#13#10 +
  '  LoggerPro;'#13#10 +
  '  implementation'#13#10 +
  '  initialization'#13#10 +
  '  finalization'#13#10 +
  '*)'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnitLevelKeywordIndent));
  finally F.Free; end;
end;

procedure TTestUnitLevelKeywordIndent.CodeAfterCommentBlock_StillReported;
// TP-Gegenprobe zum Kommentar-Zustand: derselbe Quelltext enthaelt ein
// eingeruecktes Keyword IM Kommentar (kein Fund) und drei eingerueckte
// Keywords DAHINTER im Code (Funde). Wuerde der Zustand nicht sauber
// zurueckgesetzt, waeren die drei echten Funde still verschwunden.
const SRC =
  'unit t;'#13#10 +
  '{ Kopf:'#13#10 +
  '  implementation of the cache }'#13#10 +
  '  interface'#13#10 +
  '  uses'#13#10 +
  '  System.SysUtils;'#13#10 +
  '  implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(3, TFindingHelper.Count(F, fkUnitLevelKeywordIndent),
      'interface/uses/implementation im Code = 3 Funde, die Kommentar-'
      + 'zeile darueber keiner');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, '  interface'),
      TFindingHelper.FirstOf(F, fkUnitLevelKeywordIndent).LineNumber,
      'erster Fund muss die interface-Zeile NACH dem Kommentar sein');
  finally F.Free; end;
end;

procedure TTestUnitLevelKeywordIndent.UsesWithDirectiveTail_ReportedWithColumn;
// Gewollter Zugewinn des Blankings (pointer/BrainMM.pas:149): ein
// echtes unit-level 'uses' in Spalte 3, dessen Rest nur aus einer
// Compiler-Direktive besteht. Ohne Blanking galt die Zeile als
// "Keyword plus weiterer Code" und blieb stumm.
// Zweiter Zweck: das Blanking ist LAENGENERHALTEND - die gemeldete
// Spalte muss die des Originals sein (3, nicht 1).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  '  uses {$IFDEF MSWINDOWS}'#13#10 +
  '  Winapi.Windows,'#13#10 +
  '  {$ENDIF}'#13#10 +
  '  System.SysUtils;'#13#10 +
  'implementation'#13#10 +
  'end.';
var
  F   : TObjectList<TLeakFinding>;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnitLevelKeywordIndent),
      'das eingerueckte uses mit Direktiven-Rest ist ein Fund');
    Hit := TFindingHelper.FirstOf(F, fkUnitLevelKeywordIndent);
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'uses {$IFDEF'), Hit.LineNumber,
      'Fund muss auf der uses-Zeile liegen');
    Assert.IsTrue(Pos('column 3', Hit.MissingVar) > 0,
      'Spalte muss die Original-Spalte 3 sein - gemeldet wurde: ' +
      Hit.MissingVar);
  finally F.Free; end;
end;

procedure TTestUnitLevelKeywordIndent.BraceInsideStringLiteral_DoesNotSwallowFile;
// TP-Gegenprobe zum Literal-Blanking: die geschweifte Klammer steht in
// einem String, eroeffnet also KEINEN Kommentar. Ohne Literal-Behandlung
// bliebe der Kommentar-Zustand bis zum Dateiende an und das eingerueckte
// 'implementation' darunter waere verloren.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'const'#13#10 +
  '  MARKER = ''{'';'#13#10 +
  '  implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnitLevelKeywordIndent));
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUnitLevelKeywordIndent);

end.
