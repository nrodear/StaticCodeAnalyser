unit uTestAssignedAndAssignedNil;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestAssignedAndAssignedNil = class
  public
    [Test] procedure JustAssigned_NoFinding;
    [Test] procedure AssignedAndNotNil_Reported;
    [Test] procedure AssignedAndNotNil_NoParens_Reported;
    [Test] procedure DifferentIdentifiers_NoFinding;
    [Test] procedure AssignedAndAssignedNil_KindAndSeverity;
    // Voll-Review 2026-09-12 (Major 44): die versprochene Spiegel-Form
    [Test] procedure NotNilThenAssigned_Reported;
    [Test] procedure NotNilThenAssignedDifferentIds_NoFinding;
    // Charge P 2026-10-25 (Tempo-Umbau, Verhalten identisch): Waechter
    // fuer den Sprung hinter gescheiterte Bezeichner, die '<>'-Vorpruefung
    // und die vorgezogene Wortgrenze in ParseAssignedCall.
    [Test] procedure IdentDirectlyBeforeParen_MirrorReported;
    [Test] procedure MirrorAfterLongIdentifiers_Reported;
    [Test] procedure IdentSuffixMatchesAssigned_NoFinding;
    [Test] procedure AssignedAsIdentSuffix_NoFinding;
    [Test] procedure LineWithoutNotEq_CommentStateCarried;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestAssignedAndAssignedNil.JustAssigned_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; if Assigned(Obj) then DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAssignedAndAssignedNil));
  finally F.Free; end;
end;

procedure TTestAssignedAndAssignedNil.AssignedAndNotNil_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; if Assigned(Obj) and (Obj <> nil) then DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkAssignedAndAssignedNil));
  finally F.Free; end;
end;

procedure TTestAssignedAndAssignedNil.AssignedAndNotNil_NoParens_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; if Assigned(Obj) and Obj <> nil then DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkAssignedAndAssignedNil));
  finally F.Free; end;
end;

procedure TTestAssignedAndAssignedNil.DifferentIdentifiers_NoFinding;
// `Assigned(A) and (B <> nil)` - unterschiedliche Identifier, kein Bug.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; if Assigned(A) and (B <> nil) then DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAssignedAndAssignedNil));
  finally F.Free; end;
end;

procedure TTestAssignedAndAssignedNil.AssignedAndAssignedNil_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; if Assigned(Obj) and (Obj <> nil) then DoStuff; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkAssignedAndAssignedNil then
      begin
        Assert.AreEqual<TFindingKind>(fkAssignedAndAssignedNil, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,                  Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkAssignedAndAssignedNil finding');
  finally F.Free; end;
end;

procedure TTestAssignedAndAssignedNil.NotNilThenAssigned_Reported;
// Voll-Review 2026-09-12 (Major 44): Header und Helfer-Kommentar
// versprachen die Spiegel-Form '(X <> nil) and Assigned(X)' seit
// jeher - geparst wurde nur die Assigned-zuerst-Form (Bestands-Exe:
// 0 Funde, empirisch belegt).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure P(Obj: TObject);'#13#10 +
  'begin'#13#10 +
  '  if (Obj <> nil) and Assigned(Obj) then'#13#10 +
  '    Tu;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1,
    TFindingHelper.Count(F, fkAssignedAndAssignedNil),
    'die Spiegel-Form ist genauso redundant und muss gemeldet werden');
  finally F.Free; end;
end;

procedure TTestAssignedAndAssignedNil.NotNilThenAssignedDifferentIds_NoFinding;
// Gegenrichtung: verschiedene Bezeichner sind KEINE Redundanz - ein
// Spiegel-Pfad, der die Id nicht vergleicht, waere hier rot.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure P(A, B: TObject);'#13#10 +
  'begin'#13#10 +
  '  if (A <> nil) and Assigned(B) then'#13#10 +
  '    Tu;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkAssignedAndAssignedNil),
    'verschiedene Bezeichner - keine Redundanz');
  finally F.Free; end;
end;

procedure TTestAssignedAndAssignedNil.IdentDirectlyBeforeParen_MirrorReported;
// Der Sprung hinter einen gescheiterten Bezeichner endet VOR dem '(' -
// dort beginnt die Spiegel-Form. Ein Sprung, der das '(' mitnaehme,
// verloere den Fund.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure P(Obj: TObject);'#13#10 +
  'begin'#13#10 +
  '  if Check(Obj <> nil) and Assigned(Obj) then'#13#10 +
  '    Tu;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1,
    TFindingHelper.Count(F, fkAssignedAndAssignedNil),
    'Spiegel-Form direkt hinter einem Bezeichner');
  finally F.Free; end;
end;

procedure TTestAssignedAndAssignedNil.MirrorAfterLongIdentifiers_Reported;
// Mehrere gescheiterte Bezeichner (inkl. 'and' und Ziffern) vor der
// Spiegel-Form: jeder Sprung landet auf dem naechsten Nicht-Bezeichner-
// zeichen, der Fund am Zeilenende bleibt.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure P(Obj: TObject);'#13#10 +
  'begin'#13#10 +
  '  if FooBar1.Baz_2 and 9Qux and (Obj <> nil) and Assigned(Obj) then'#13#10 +
  '    Tu;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1,
    TFindingHelper.Count(F, fkAssignedAndAssignedNil),
    'Spiegel-Form hinter langen Bezeichnern');
  finally F.Free; end;
end;

procedure TTestAssignedAndAssignedNil.IdentSuffixMatchesAssigned_NoFinding;
// 'xObj <> nil and Assigned(Obj)': der Bezeichner ist xObj, nicht sein
// Suffix Obj - auch nach dem Umbau beginnt kein Versuch mitten im Wort.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure P(Obj, xObj: TObject);'#13#10 +
  'begin'#13#10 +
  '  if (xObj <> nil) and Assigned(Obj) then Tu;'#13#10 +
  '  if xObj <> nil and Assigned(Obj) then Tu;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkAssignedAndAssignedNil),
    'xObj und Obj sind verschiedene Bezeichner');
  finally F.Free; end;
end;

procedure TTestAssignedAndAssignedNil.AssignedAsIdentSuffix_NoFinding;
// 'MyAssigned(Obj)' ist nicht Assigned - die Wortgrenze steht jetzt VOR
// dem Copy und muss weiter greifen.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure P(Obj: TObject);'#13#10 +
  'begin'#13#10 +
  '  if MyAssigned(Obj) and (Obj <> nil) then Tu;'#13#10 +
  '  if (Obj <> nil) and MyAssigned(Obj) then Tu;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkAssignedAndAssignedNil),
    'MyAssigned ist kein Assigned');
  finally F.Free; end;
end;

procedure TTestAssignedAndAssignedNil.LineWithoutNotEq_CommentStateCarried;
// Die '<>'-Vorpruefung schaltet nur die Parser ab, nicht die
// Kommentar-Maschine: der in Zeile 6 (ohne '<>') geoeffnete Kommentar
// verschluckt Zeile 7, nur Zeile 9 zaehlt.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure P(Obj: TObject);'#13#10 +
  'begin'#13#10 +
  '  Tu; { Kommentar ohne Vergleich'#13#10 +
  '  if Assigned(Obj) and (Obj <> nil) then Tu;'#13#10 +
  '  }'#13#10 +
  '  if Assigned(Obj) and (Obj <> nil) then Tu;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1,
    TFindingHelper.Count(F, fkAssignedAndAssignedNil),
    'nur der Fund ausserhalb des Kommentars');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestAssignedAndAssignedNil);

end.
