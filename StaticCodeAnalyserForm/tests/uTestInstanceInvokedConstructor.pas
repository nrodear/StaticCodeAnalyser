unit uTestInstanceInvokedConstructor;

// Tests fuer den TInstanceInvokedConstructorDetector.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestInstanceInvokedConstructor = class
  public
    // ---- Positive Varianten ------------------------------------------------
    [Test] procedure LowercaseVarCreate_Reported;
    [Test] procedure FieldFPrefixCreate_Reported;
    [Test] procedure CreateWithArgs_Reported;
    [Test] procedure MultipleHits_AllReported;

    // ---- Negative Varianten / Guards --------------------------------------
    [Test] procedure ClassTCreate_NoFinding;
    [Test] procedure ClassICreate_NoFinding;
    [Test] procedure SelfCreate_NoFinding;
    [Test] procedure InheritedCreate_NoFinding;
    [Test] procedure ResultCreate_NoFinding;
    [Test] procedure UppercaseVar_NoFinding;
    [Test] procedure CastCreate_NoFinding;
    [Test] procedure NonCreateCall_NoFinding;
    [Test] procedure MultiDotPath_NoFinding;

    // ---- Finding-Inhalt ----------------------------------------------------
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestInstanceInvokedConstructor.LowercaseVarCreate_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var obj: TStringList;'#13#10 +
  'begin obj.Create; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInstanceInvokedConstructor));
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.FieldFPrefixCreate_Reported;
// f-Prefix-Field: 'fItems' beginnt mit Lowercase -> Variable.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin fItems.Create; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInstanceInvokedConstructor));
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.CreateWithArgs_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var obj: TFooBar;'#13#10 +
  'begin obj.Create(42, ''hello''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInstanceInvokedConstructor));
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.MultipleHits_AllReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  a.Create;'#13#10 +
  '  b.Create;'#13#10 +
  '  c.Create;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(3, TFindingHelper.Count(F, fkInstanceInvokedConstructor));
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.ClassTCreate_NoFinding;
// TStringList ist eine Klasse (T-Prefix) -> legitimer Class-Call.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin L := TStringList.Create; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInstanceInvokedConstructor));
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.ClassICreate_NoFinding;
// I-Prefix = Interface, theoretisch nicht createbar, aber kein Bug-Pattern.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin IFoo.Create; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInstanceInvokedConstructor));
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.SelfCreate_NoFinding;
// Self.Create in Constructor ist legitim (Delegation).
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin Self.Create(42); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInstanceInvokedConstructor));
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.InheritedCreate_NoFinding;
// 'inherited Create' wird vom Parser als nkInherited gespeichert,
// nicht als nkCall - keine Detektion noetig. Defensiv getestet.
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin inherited Create; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInstanceInvokedConstructor));
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.ResultCreate_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo: TStringList;'#13#10 +
  'begin Result := TStringList.Create; Result.Create; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInstanceInvokedConstructor));
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.UppercaseVar_NoFinding;
// 'MyList.Create' - uppercase Start, koennte Klasse sein (kein T-Prefix
// aber Konvention nicht zwingend). Heuristik skippt.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin MyList.Create; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInstanceInvokedConstructor));
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.CastCreate_NoFinding;
// `TFoo(x).Create` ist Cast-Form, nicht Instance.Create - eigener Detektor
// (CastAndFreeCheck-Familie). Hier sicherheitshalber kein Doppel-Treffer.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: TObject;'#13#10 +
  'begin TStringList(x).Create; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInstanceInvokedConstructor));
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.NonCreateCall_NoFinding;
// `obj.Add(...)` ist normaler Method-Call, nicht Create.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var obj: TStringList;'#13#10 +
  'begin obj.Add(''x''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInstanceInvokedConstructor));
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.MultiDotPath_NoFinding;
// `owner.sub.Create` - Multi-Dot-Receiver, Heuristik kann nicht
// entscheiden ob owner.sub Class oder Instance ist -> skip.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin owner.sub.Create; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInstanceInvokedConstructor));
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var obj: TStringList;'#13#10 +
  'begin obj.Create; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkInstanceInvokedConstructor then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkInstanceInvokedConstructor finding expected');
    Assert.AreEqual(fkInstanceInvokedConstructor, Hit.Kind);
    Assert.AreEqual(lsError,                      Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestInstanceInvokedConstructor);

end.
