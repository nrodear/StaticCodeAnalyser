unit uTestFreeWithoutNil;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFreeWithoutNil = class
  public
    [Test] procedure FreeWithoutNil_Reported;
    [Test] procedure FreeAndNil_NotReported;
    [Test] procedure FreeAtMethodEnd_NotReported;
    [Test] procedure FreeFollowedByNilAssign_NotReported;
    [Test] procedure FreeInDestructor_NotReported;
    // Real-World FP-Audit 2026-07-10: class destructor + OnDestroy-Handler
    [Test] procedure FreeInClassDestructor_NotReported;
    [Test] procedure FreeInFormDestroy_NotReported;
    [Test] procedure MethodResultFree_NotReported;
    [Test] procedure ParamFree_NotReported;
    [Test] procedure IndexedElementFree_NotReported;
    [Test] procedure TypecastFree_NotReported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestFreeWithoutNil.FreeWithoutNil_Reported;
// HINWEIS: Detector flaggt seit Round-5-Fix nur FELDER, nicht Locals
// (Locals fallen beim Method-End aus dem Scope, kein Dangling-Risiko).
// Daher SRC mit FFoo-Feld statt 'var L: TStringList;'.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FList: TStringList;'#13#10 +
  '  public'#13#10 +
  '    procedure DoStuff;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.DoStuff;'#13#10 +
  'begin'#13#10 +
  '  FList.Free;'#13#10 +
  '  WriteLn(''after free'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFreeWithoutNil),
      'genau 1 FreeWithoutNil-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'FList.Free'),
      TFindingHelper.FirstOf(F, fkFreeWithoutNil).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.FreeAndNil_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  FreeAndNil(L);'#13#10 +
  '  WriteLn(''after'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil));
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.FreeAtMethodEnd_NotReported;
// Free als letzte Anweisung -> kein Folge-Use moeglich -> kein Befund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  L.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil));
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.FreeFollowedByNilAssign_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  L.Free;'#13#10 +
  '  L := nil;'#13#10 +
  '  WriteLn(''after'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil));
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.IndexedElementFree_NotReported;
// FP-Fix (Real-World 2026-06-23): Collection-Item-Free im Loop
// (`Objects[i].Free`) - kein simpler Var-Receiver, "var := nil" trifft nicht
// zu. ~100+ Real-World-FPs (TStringList.Objects[], TList Items[], Controls[]).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to FList.Count - 1 do'#13#10 +
  '    FList.Objects[i].Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil),
      'Indexed-Element-Free (Objects[i].Free) ist kein Free-Without-Nil');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.TypecastFree_NotReported;
// FP-Fix (Real-World 2026-06-23): Typecast-Free (`TFoo(List[i]).Free`) -
// nil-Out eines Casts ist syntaktisch unmoeglich.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to FItems.Count - 1 do'#13#10 +
  '    TObject(FItems[i]).Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil),
      'Typecast-Free (TObject(X).Free) ist kein Free-Without-Nil');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.Finding_KindAndSeverity;
// Field-Pattern - analog zu FreeWithoutNil_Reported (Round-5-Fix).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FList: TStringList;'#13#10 +
  '  public'#13#10 +
  '    procedure DoStuff;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.DoStuff;'#13#10 +
  'begin'#13#10 +
  '  FList.Free;'#13#10 +
  '  WriteLn(''after'');'#13#10 +
  'end;'#13#10 +
  'end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkFreeWithoutNil then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkFreeWithoutNil finding expected');
    Assert.AreEqual(lsWarning, Hit.Severity);
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.FreeInDestructor_NotReported;
// FP-Fix (Real-World 2026-06-21): im Destruktor ist Nil-Out nach Free
// sinnlos - das Objekt selbst wird zerstoert. Ein Destruktor mit mehreren
// Field.Free erzeugte sonst je ein Finding.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FA, FB: TObject;'#13#10 +
  '  public'#13#10 +
  '    destructor Destroy; override;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  FA.Free;'#13#10 +
  '  FB.Free;'#13#10 +
  '  inherited;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil),
      'Field.Free im Destruktor braucht kein Nil-Out - kein Finding');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.MethodResultFree_NotReported;
// FP-Fix (Self-Scan 2026-06-21): `Stack.Pop.Free` gibt das ERGEBNIS eines
// Methodenaufrufs frei - es gibt keine Variable 'Pop'. Die Wurzel 'Stack'
// ist lokal -> method-scoped, kein Nil-Out-Smell.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'var Stack: TStack;'#13#10 +
  'begin'#13#10 +
  '  Stack := TStack.Create;'#13#10 +
  '  Stack.Pop.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil),
      'X.Pop.Free (Methoden-Ergebnis, lokale Wurzel) ist kein Free-Without-Nil');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.ParamFree_NotReported;
// FP-Fix (Self-Scan 2026-06-21): ein Parameter (Methode uebernimmt Ownership)
// ist method-scoped - Nil-Out beim Method-Ende ist sinnlos.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Consume(Items: TObjectList);'#13#10 +
  'begin'#13#10 +
  '  Items.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil),
      'Free eines Parameters ist kein Free-Without-Nil-Smell');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.FreeInClassDestructor_NotReported;
// Real-World FP-Audit 2026-07-10: 'class destructor' (TypeRef 'class destructor')
// wurde vom exakten SameText('destructor') verfehlt. Die class-var stirbt am
// Klassen-Teardown -> Nil-Out wirkungslos.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '    class var FList: TStringList;'#13#10 +
  '    class destructor Destroy;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'class destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  FList.Free;'#13#10 +
  '  WriteLn(''done'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil),
    'class destructor -> Nil-Out wirkungslos, kein Fund');
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.FreeInFormDestroy_NotReported;
// Real-World FP-Audit 2026-07-10: OnDestroy-Handler 'FormDestroy' (ein normales
// procedure) zerstoert die Form -> Feld-Free braucht kein Nil-Out.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TForm1 = class(TForm)'#13#10 +
  '    FList: TStringList;'#13#10 +
  '    procedure FormDestroy(Sender: TObject);'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TForm1.FormDestroy(Sender: TObject);'#13#10 +
  'begin'#13#10 +
  '  FList.Free;'#13#10 +
  '  WriteLn(''done'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeWithoutNil),
    'FormDestroy (OnDestroy-Handler) -> Feld-Free ohne Nil-Out ok');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFreeWithoutNil);

end.
