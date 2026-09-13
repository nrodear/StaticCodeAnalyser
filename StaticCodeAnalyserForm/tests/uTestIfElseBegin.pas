unit uTestIfElseBegin;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestIfElseBegin = class
  public
    [Test] procedure SymmetricBoth_NoFinding;
    [Test] procedure SymmetricNeither_NoFinding;
    [Test] procedure ElseIfChain_NoFinding;
    [Test] procedure AsymmetricEndElseStmt_Reported;
    [Test] procedure IfElseBegin_KindAndSeverity;
    // Testluecke 157: die sechs ungetesteten Opener
    [Test] procedure ElseOpener_Case_NoFinding;
    [Test] procedure ElseOpener_Try_NoFinding;
    [Test] procedure ElseOpener_For_NoFinding;
    [Test] procedure ElseOpener_While_NoFinding;
    [Test] procedure ElseOpener_Repeat_NoFinding;
    [Test] procedure ElseOpener_With_NoFinding;
    [Test] procedure ElseBareCall_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestIfElseBegin.SymmetricBoth_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if Active then'#13#10 +
  '  begin DoA; DoB; end'#13#10 +
  '  else'#13#10 +
  '  begin DoC; DoD; end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkIfElseBegin));
  finally F.Free; end;
end;

procedure TTestIfElseBegin.SymmetricNeither_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if Active then DoA else DoB;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkIfElseBegin));
  finally F.Free; end;
end;

procedure TTestIfElseBegin.ElseIfChain_NoFinding;
// `end else if` ist die idiomatische Else-If-Kette und KEIN Treffer.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if A then'#13#10 +
  '  begin DoA; end'#13#10 +
  '  else if B then'#13#10 +
  '  begin DoB; end'#13#10 +
  '  else'#13#10 +
  '  begin DoC; end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkIfElseBegin));
  finally F.Free; end;
end;

procedure TTestIfElseBegin.AsymmetricEndElseStmt_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if Active then'#13#10 +
  '  begin DoA; DoB; end'#13#10 +
  '  else DoC;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkIfElseBegin) >= 1);
  finally F.Free; end;
end;

procedure TTestIfElseBegin.IfElseBegin_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if A then begin X; end else Y;'#13#10 +
  'end;';
var
  Findings : TObjectList<TLeakFinding>;
  Fnd      : TLeakFinding;
begin
  Findings := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in Findings do
      if Fnd.Kind = fkIfElseBegin then
      begin
        Assert.AreEqual<TFindingKind>(fkIfElseBegin, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,       Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkIfElseBegin finding');
  finally Findings.Free; end;
end;

{ --- Testluecke 157: die Opener-Erlaubnisliste ---------------------- }
//
// Nach 'end else' zaehlt nicht nur 'begin' als symmetrischer Opener,
// sondern jedes Statement mit eigenem implizitem Blockcharakter:
// case, try, for, while, repeat, with (Detektor Z.115-117). Belegt
// waren davon nur 'begin' und 'else if' - die sechs uebrigen sind ein
// eigener Logikpfad, den kein Test beruehrte.
//
// Sechs Tests statt einem Sammeltest: faellt ein Opener aus der Liste,
// soll genau EIN Test rot werden und beim Namen sagen, welcher.
// Gegenprobe ist der siebte - ein nackter Aufruf MUSS melden, sonst
// waeren die sechs Nullen auch ohne Detektor zu haben.
// Alle sieben am gebauten Stand nachgemessen.
//
// Die sieben Fixturen sind bis auf das Schluesselwort nach 'else'
// gleich - dafuer meldet der Selbstscan einen DuplicateBlock. Das IST
// der Aufbau: sieben Mal derselbe Rahmen, sieben verschiedene Opener.
// In Testunits per Profil-Politik kein Mangel.

procedure TTestIfElseBegin.ElseOpener_Case_NoFinding;
// 'case' ist ein erlaubter Opener - kein Asymmetrie-Fund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  if A then'#13#10 +
  '  begin'#13#10 +
  '    DoA;'#13#10 +
  '  end'#13#10 +
  '  else case B of'#13#10 +
  '    1: DoB;'#13#10 +
  '  end;'#13#10 +
  'end;'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkIfElseBegin),
    'else case ist ein eigener Block, keine Asymmetrie');
  finally F.Free; end;
end;

procedure TTestIfElseBegin.ElseOpener_Try_NoFinding;
// 'try' ist ein erlaubter Opener - kein Asymmetrie-Fund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  if A then'#13#10 +
  '  begin'#13#10 +
  '    DoA;'#13#10 +
  '  end'#13#10 +
  '  else try'#13#10 +
  '    DoB;'#13#10 +
  '  finally'#13#10 +
  '    DoC;'#13#10 +
  '  end;'#13#10 +
  'end;'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkIfElseBegin),
    'else try ist ein eigener Block, keine Asymmetrie');
  finally F.Free; end;
end;

procedure TTestIfElseBegin.ElseOpener_For_NoFinding;
// 'for' ist ein erlaubter Opener - kein Asymmetrie-Fund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  if A then'#13#10 +
  '  begin'#13#10 +
  '    DoA;'#13#10 +
  '  end'#13#10 +
  '  else for I := 1 to 3 do'#13#10 +
  '    DoB;'#13#10 +
  'end;'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkIfElseBegin),
    'else for ist ein eigener Block, keine Asymmetrie');
  finally F.Free; end;
end;

procedure TTestIfElseBegin.ElseOpener_While_NoFinding;
// 'while' ist ein erlaubter Opener - kein Asymmetrie-Fund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  if A then'#13#10 +
  '  begin'#13#10 +
  '    DoA;'#13#10 +
  '  end'#13#10 +
  '  else while B do'#13#10 +
  '    DoC;'#13#10 +
  'end;'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkIfElseBegin),
    'else while ist ein eigener Block, keine Asymmetrie');
  finally F.Free; end;
end;

procedure TTestIfElseBegin.ElseOpener_Repeat_NoFinding;
// 'repeat' ist ein erlaubter Opener - kein Asymmetrie-Fund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  if A then'#13#10 +
  '  begin'#13#10 +
  '    DoA;'#13#10 +
  '  end'#13#10 +
  '  else repeat'#13#10 +
  '    DoB;'#13#10 +
  '  until C;'#13#10 +
  'end;'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkIfElseBegin),
    'else repeat ist ein eigener Block, keine Asymmetrie');
  finally F.Free; end;
end;

procedure TTestIfElseBegin.ElseOpener_With_NoFinding;
// 'with' ist ein erlaubter Opener - kein Asymmetrie-Fund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  if A then'#13#10 +
  '  begin'#13#10 +
  '    DoA;'#13#10 +
  '  end'#13#10 +
  '  else with B do'#13#10 +
  '    DoC;'#13#10 +
  'end;'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkIfElseBegin),
    'else with ist ein eigener Block, keine Asymmetrie');
  finally F.Free; end;
end;

procedure TTestIfElseBegin.ElseBareCall_StillReported;
// DIE GEGENPROBE: ein nackter Aufruf nach else ist die Asymmetrie,
// um die es der Regel geht.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  if A then'#13#10 +
  '  begin'#13#10 +
  '    DoA;'#13#10 +
  '  end'#13#10 +
  '  else DoB;'#13#10 +
  'end;'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1,
    TFindingHelper.Count(F, fkIfElseBegin),
    'nackter Aufruf nach else ist asymmetrisch');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestIfElseBegin);

end.
