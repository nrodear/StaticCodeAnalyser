unit uTestBeginEndRequired;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestBeginEndRequired = class
  public
    [Test] procedure ThenBegin_NoFinding;
    [Test] procedure ThenBareStmt_Reported;
    [Test] procedure ElseIfChain_NoFinding;
    [Test] procedure ThenRaise_NoFinding;
    [Test] procedure ThenExit_NoFinding;
    [Test] procedure DoBareStmt_Reported;
    [Test] procedure BeginEndRequired_KindAndSeverity;
    [Test] procedure NextLineStatement_Reported;
    [Test] procedure NextLineBegin_NotReported;
    [Test] procedure ThenWithLineComment_NextLineStatement_Reported;
    // AQL 31.08.: Zeilenanker bei einer Zeile, die abschliesst UND oeffnet
    [Test] procedure ClosingAndOpeningLine_ReportsOnOwnLine;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestBeginEndRequired.ThenBegin_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if Active then begin DoStuff; end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkBeginEndRequired));
  finally F.Free; end;
end;

procedure TTestBeginEndRequired.ThenBareStmt_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if Active then DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkBeginEndRequired) >= 1);
  finally F.Free; end;
end;

procedure TTestBeginEndRequired.ElseIfChain_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if A then begin DoA; end'#13#10 +
  '  else if B then begin DoB; end'#13#10 +
  '  else begin DoC; end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkBeginEndRequired));
  finally F.Free; end;
end;

procedure TTestBeginEndRequired.ThenRaise_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if Failed then raise EError.Create(''bad'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkBeginEndRequired));
  finally F.Free; end;
end;

procedure TTestBeginEndRequired.ThenExit_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if not Ready then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkBeginEndRequired));
  finally F.Free; end;
end;

procedure TTestBeginEndRequired.DoBareStmt_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  for i := 1 to N do DoStuff(i);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkBeginEndRequired) >= 1);
  finally F.Free; end;
end;

procedure TTestBeginEndRequired.BeginEndRequired_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; if X then DoY; end;';
var
  Findings : TObjectList<TLeakFinding>;
  Fnd      : TLeakFinding;
begin
  Findings := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in Findings do
      if Fnd.Kind = fkBeginEndRequired then
      begin
        Assert.AreEqual<TFindingKind>(fkBeginEndRequired, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,            Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkBeginEndRequired finding');
  finally Findings.Free; end;
end;

procedure TTestBeginEndRequired.NextLineStatement_Reported;
// Review-HIGH 2026-08-08: die haeufigste Formatierung (`if Cond then` +
// Statement auf der Folgezeile) war fuer den Detektor unsichtbar.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  if Cond then'#13#10 +
  '    DoSomething;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkBeginEndRequired));
  finally F.Free; end;
end;

procedure TTestBeginEndRequired.NextLineBegin_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  if Cond then'#13#10 +
  '  begin'#13#10 +
  '    DoSomething;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkBeginEndRequired));
  finally F.Free; end;
end;

procedure TTestBeginEndRequired.ThenWithLineComment_NextLineStatement_Reported;
// `then // Kommentar` + Statement auf der Folgezeile = gleiche Klasse.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  if Cond then // warum auch immer'#13#10 +
  '    DoSomething;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkBeginEndRequired));
  finally F.Free; end;
end;


procedure TTestBeginEndRequired.ClosingAndOpeningLine_ReportsOnOwnLine;
// AQL-Stichprobe 31.08.: eine Zeile, die einen wartenden Branch
// ABSCHLIESST und zugleich einen neuen OEFFNET ('  DoSomething else'),
// hat den Zeilenanker ueberschrieben, bevor der Emit ihn las - der Fund
// des then-Zweigs landete eine Zeile zu tief.
//
// Gemessen betraf das 36 von 41.067 Funden (0,088 %) in den 182 Dateien
// der Stichprobe; bei 17 davon trug die gemeldete Zeile keinen eigenen
// Verstoss, dort war es ein Fehlalarm. Beleg: jvcl JvDBTreeView.pas
// 581/582.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  if Cond then'#13#10 +
  '    DoSomething else'#13#10 +
  '    DoOther;'#13#10 +
  'end;';
var
  F       : TObjectList<TLeakFinding>;
  L       : TLeakFinding;
  AufThen : Boolean;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    AufThen := False;
    for L in F do
      if (L.Kind = fkBeginEndRequired)
         and (L.LineNumber = TFindingHelper.LineOf(SRC, 'if Cond then')) then
        AufThen := True;
    Assert.IsTrue(AufThen,
      'der then-Zweig gehoert auf seine eigene Zeile, nicht auf die, ' +
      'die ihn abschliesst');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestBeginEndRequired);

end.
