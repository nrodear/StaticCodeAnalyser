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
    // Posten 294: der case-else als bekannte Grenze
    [Test] procedure CaseElseSingleStatement_Reported_KnownLimit;
    [Test] procedure CaseElseStatementList_Reported_KnownLimit;
    [Test] procedure IfElseWithoutBegin_Kontrolle_Reported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

{ --- Posten 294: der case-else ist KEIN if-else ------------------ }
//
// Der Detektor unterscheidet nicht zwischen if-else und case-else. In
// einem case nimmt der else-Zweig aber eine ANWEISUNGSLISTE: alles bis
// zum 'end' gehoert dazu. Die Begruendung der Regel - 'ein spaeter
// angefuegtes Statement faellt sonst aus dem Zweig heraus' - trifft
// dort also gar nicht zu.
//
// An der Exe gemessen:
//   case K of 1: DoA; else DoB; end;            1 Fund
//   case K of 1: DoA; else DoB; DoC; end;       1 Fund  <-- auch mit
//       ZWEI Anweisungen, obwohl beide zum else gehoeren
//   if C then DoA else DoB;                     2 Funde (korrekt)
//   if C then begin ... end else begin ... end; 0       (korrekt)
//
// NICHT GEAENDERT, und der Grund ist eine Messung: 4.681 der 285.942
// SCA045-Funde des Korpus (1,6 %) haengen an einem case-else. Das ist
// ein Recall-Paket mit eigenem Zweig, eigenem Bau und eigener
// FP-Stichprobe - nicht ein Nebenbei-Fix in einer gemischten Charge.
// Dazu kommt: SCA045 ist im Meilenstein-Katalog als "Konvention statt
// Korrektheit - Profil ist die Antwort" eingeordnet und im
// Projekt-eigenen Profil abgewaehlt. Ob die 4.681 verschwinden sollen,
// ist eine Produktentscheidung.
//
// Die beiden Tests pinnen das IST-Verhalten. Sie werden rot, sobald
// jemand das Paket umsetzt - und genau dann soll das auffallen.

procedure TTestBeginEndRequired.CaseElseSingleStatement_Reported_KnownLimit;
// Gemessen: 1.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  case K of'#13#10+
  '    1: DoA;'#13#10+
  '  else'#13#10+
  '    DoB;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkBeginEndRequired),
      'BEKANNTE GRENZE: der case-else wird wie ein if-else behandelt');
  finally F.Free; end;
end;

procedure TTestBeginEndRequired.CaseElseStatementList_Reported_KnownLimit;
// Der schaerfere Fall: ZWEI Anweisungen im else-Zweig. Beide gehoeren
// zum else - ein begin..end wuerde daran nichts aendern. Gemessen: 1.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  case K of'#13#10+
  '    1: DoA;'#13#10+
  '  else'#13#10+
  '    DoB;'#13#10+
  '    DoC;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkBeginEndRequired),
      'BEKANNTE GRENZE: auch eine Anweisungsliste im case-else wird gemeldet');
  finally F.Free; end;
end;

procedure TTestBeginEndRequired.IfElseWithoutBegin_Kontrolle_Reported;
// Die Kontrolle: beim if-else ist die Meldung richtig - ein
// angefuegtes Statement fiele dort wirklich aus dem Zweig.
// Gemessen: 2 (then-Zweig und else-Zweig).
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  if C then'#13#10+
  '    DoA'#13#10+
  '  else'#13#10+
  '    DoB;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(2,
      TFindingHelper.Count(F, fkBeginEndRequired),
      'beim if-else ist die Forderung nach begin..end berechtigt');
  finally F.Free; end;
end;


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
