unit uTestMissingRaise;

// Tests fuer den TMissingRaiseDetector.
//
// Positive Faelle: Exception-Klasse via .Create instanziiert ohne raise.
// Negative Faelle: raise davor, oder gar keine Exception-Klasse.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMissingRaise = class
  public
    // ---- Positive Varianten ------------------------------------------------
    [Test] procedure ExceptionCreate_NoRaise_Reported;
    [Test] procedure SpecificExceptionCreate_NoRaise_Reported;
    [Test] procedure ExceptionCreateFmt_NoRaise_Reported;
    [Test] procedure MultipleExceptionCreates_AllReported;

    // ---- Negative Varianten / Guards --------------------------------------
    [Test] procedure RaisedException_NoFinding;
    [Test] procedure NonExceptionCreate_NoFinding;
    [Test] procedure EditCreate_NotMisidentified_NoFinding;
    [Test] procedure EncodingClass_NotMisidentified_NoFinding;

    // ---- Finding-Inhalt ----------------------------------------------------
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestMissingRaise.ExceptionCreate_NoRaise_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin Exception.Create(''boom''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMissingRaise));
  finally F.Free; end;
end;

procedure TTestMissingRaise.SpecificExceptionCreate_NoRaise_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin EConvertError.Create(''bad input''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMissingRaise));
  finally F.Free; end;
end;

procedure TTestMissingRaise.ExceptionCreateFmt_NoRaise_Reported;
// Variante: .Create mit Format-args.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(x: Integer);'#13#10 +
  'begin EFooBar.Create(Format(''%d'', [x])); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMissingRaise));
  finally F.Free; end;
end;

procedure TTestMissingRaise.MultipleExceptionCreates_AllReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  EOne.Create(''a'');'#13#10 +
  '  ETwo.Create(''b'');'#13#10 +
  '  EThree.Create(''c'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(3, TFindingHelper.Count(F, fkMissingRaise));
  finally F.Free; end;
end;

procedure TTestMissingRaise.RaisedException_NoFinding;
// Korrekt: raise konsumiert den Call - kein nkCall-Knoten entsteht.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin raise EConvertError.Create(''bad input''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingRaise));
  finally F.Free; end;
end;

procedure TTestMissingRaise.NonExceptionCreate_NoFinding;
// TStringList.Create ist kein Exception-Constructor.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin TStringList.Create; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingRaise));
  finally F.Free; end;
end;

procedure TTestMissingRaise.EditCreate_NotMisidentified_NoFinding;
// 'Edit' beginnt mit E, aber 2. Zeichen ist Kleinbuchstabe - keine
// Delphi-Exception-Konvention.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(AOwner: TComponent);'#13#10 +
  'begin Edit.Create(AOwner); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingRaise));
  finally F.Free; end;
end;

procedure TTestMissingRaise.EncodingClass_NotMisidentified_NoFinding;
// 'Encoding' - klein nach E. Kein Exception.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin Encoding.Create; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingRaise));
  finally F.Free; end;
end;

procedure TTestMissingRaise.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin EConvertError.Create(''x''); end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkMissingRaise then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkMissingRaise finding expected');
    Assert.AreEqual(fkMissingRaise, Hit.Kind);
    Assert.AreEqual(lsError,        Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMissingRaise);

end.
