unit uTestPathTraversal;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPathTraversal = class
  public
    [Test] procedure FileStreamWithEditText_Reported;
    [Test] procedure FileOpenWithLiteral_NotReported;
    [Test] procedure FileStreamWithoutConcat_NotReported;
    [Test] procedure ConstWithTextSubstring_NotReported;
    // T3-Gate 2026-07-31: User-Input+Concat muessen im ARGUMENTFENSTER
    // der File-API stehen - Mehrstatement-Blobs (Generic-Call mit
    // anonymer Methode) duerfen nicht cross-statement korrelieren.
    [Test] procedure CrossStatementBlob_NotReported;
    [Test] procedure InputInsideApiArgs_StillReported;
    // Review-MEDIUM 2026-08-09: API-Name nur IM String-Literal einer
    // Fehlermeldung - Literal-Inhalt zaehlt nie als Code.
    [Test] procedure ApiNameInsideLiteral_NotReported;
    // Posten 265: das Concat-Gate lief auf dem Rohtext
    [Test] procedure PlusOnlyInsideLiteral_NotReported;
    [Test] procedure EscapedQuoteThenRealConcat_StillReported;
  end;

implementation


uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

{ --- Posten 265: das Concat-Gate auf der geblankten Fassung ----- }
//
// Der Nachweis 'ohne Konkatenation kein Pattern' stand VOR der Zeile,
// die Low berechnet - er lief also auf dem ROHTEXT und hob den
// Literal-Blank fuer sein eigenes Gate wieder auf. Ein Pluszeichen im
// Pfad-Literal genuegte, um den Verdacht zu begruenden.
//
// Reihenfolgefehler aus dem Literal-Blank-Nachruestvorgang
// (Review-MEDIUM 2026-08-09): das Concat-Gate wurde damals nicht
// mitgezogen.
//
// Beide Erwartungen an der gebauten Exe gemessen.

procedure TTestPathTraversal.PlusOnlyInsideLiteral_NotReported;
// Das einzige Pluszeichen steht IM Pfad-Literal. Kein
// zusammengesetzter Pfad, kein User-Input am Code-Operator - und
// trotzdem heute 1 Fund im Error-Tier. Nach dem Fix 0.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  TFile.WriteAllText(''c:\out+log.txt'', Memo1.Lines.Text);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkPathTraversal),
      'ein + im Literal ist keine Konkatenation');
  finally F.Free; end;
end;

procedure TTestPathTraversal.EscapedQuoteThenRealConcat_StillReported;
// GEGENPROBE, und zugleich der Waechter fuer den Blanker: ein Literal
// mit verdoppeltem Apostroph, danach eine ECHTE Konkatenation mit
// User-Input. Vor wie nach dem Fix 1 Fund. Wird rot, wenn jemand
// BlankStringLiterals das Escape-Verhalten nimmt - dann endet das
// Literal zu frueh und das + verschwindet in der geblankten Zone.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  TFile.WriteAllText(''don''''t'' + Edit1.Text, ''x'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkPathTraversal),
      'eine echte Konkatenation mit Edit1.Text bleibt ein Fund');
  finally F.Free; end;
end;


procedure TTestPathTraversal.CrossStatementBlob_NotReported;
// T3-Gate 2026-07-31: seit Statement-Generic-Calls ihren vollen Text
// tragen, enthaelt der nkCall-Name hier ZWEI Statements (anonyme
// Methode als Argument). Das Zuweisungsziel 'LLabel.Text :=' stammt
// aus einem ANDEREN Statement als der ReadAllText-Aufruf mit
// literal-basiertem Pfad - keine Korrelation, kein Fund (die 4
// skia4delphi-FPs des T3-Gates, Error-Tier).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  ChildForm<TfrmDemo>.Show(''Label'','#13#10 +
  '    procedure (const AForm: TfrmDemo)'#13#10 +
  '    begin'#13#10 +
  '      AForm.lblText.Text := TFile.ReadAllText(AssetsPath + ''lorem.txt'');'#13#10 +
  '    end);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkPathTraversal),
      'Zuweisungsziel .Text eines fremden Statements darf nicht mit ' +
      'der File-API korrelieren');
  finally F.Free; end;
end;

procedure TTestPathTraversal.InputInsideApiArgs_StillReported;
// Gegenprobe zum Argumentfenster: steht der User-Input IM Argument der
// File-API, muss der Fund erhalten bleiben - auch im Blob-Kontext.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: string;'#13#10 +
  'begin'#13#10 +
  '  s := TFile.ReadAllText(BaseDir + edPath.Text);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkPathTraversal) >= 1,
      'User-Input im API-Argument muss weiter gemeldet werden');
  finally F.Free; end;
end;

procedure TTestPathTraversal.FileStreamWithEditText_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: TFileStream;'#13#10 +
  'begin'#13#10 +
  '  s := TFileStream.Create(BaseDir + edPath.Text, fmOpenRead);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkPathTraversal) >= 1,
      'TFileStream.Create + edPath.Text muss als Path-Traversal-Risk gemeldet werden');
  finally F.Free; end;
end;

procedure TTestPathTraversal.FileOpenWithLiteral_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: TFileStream;'#13#10 +
  'begin'#13#10 +
  '  s := TFileStream.Create(''C:\fixed\path.log'', fmOpenRead);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkPathTraversal),
      'Literal-only Path ist kein User-Input-Risk');
  finally F.Free; end;
end;

procedure TTestPathTraversal.FileStreamWithoutConcat_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: TFileStream;'#13#10 +
  'begin'#13#10 +
  '  s := TFileStream.Create(edPath.Text, fmOpenRead);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    // Heuristik braucht '+' - ohne Concat kein Finding (vermeidet
    // FP wenn das ganze Edit der intendierte File-Path ist).
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkPathTraversal),
      'Ohne + ist Heuristik nicht aktiv (akzeptierter FN)');
  finally F.Free; end;
end;

procedure TTestPathTraversal.ConstWithTextSubstring_NotReported;
// FP-Fix (Real-World 2026-06-21): '.text' darf NICHT als Substring in
// 'MediaType.TEXT_HTML' matchen (rechts steht '_' = Identifier-Char).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: TFileStream;'#13#10 +
  'begin'#13#10 +
  '  s := TFileStream.Create(BaseDir + MediaType.TEXT_HTML, fmOpenRead);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkPathTraversal),
      '.TEXT_HTML ist kein User-Input-Token (Wortgrenze)');
  finally F.Free; end;
end;

procedure TTestPathTraversal.ApiNameInsideLiteral_NotReported;
// Review-MEDIUM 2026-08-09: 'AssignFile' steht hier nur im Meldungs-Literal,
// das '.Text' + '+' desselben Statements ist eine UI-Meldung, kein File-Open -
// Literal-Inhalt darf keinen Error-Tier-Path-Traversal-FP erzeugen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  ShowMessage(''AssignFile failed: '' + edUser.Text);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkPathTraversal),
      'API-Name im String-Literal ist kein File-Open-Call');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPathTraversal);

end.
