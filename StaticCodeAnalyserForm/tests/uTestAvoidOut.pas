unit uTestAvoidOut;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestAvoidOut = class
  public
    [Test] procedure NoOutParam_NoFinding;
    [Test] procedure OutParam_Reported;
    [Test] procedure VarParam_NoFinding;
    [Test] procedure AvoidOut_KindAndSeverity;
    // Autopsie 2026-08-26: G1 ABI-Direktiven, G2 Funktionszeiger,
    // G3 untypisiertes out, G4 override + Implementations-Zwilling.
    [Test] procedure StdcallTail_NoFinding;
    [Test] procedure DispidTail_NoFinding;
    [Test] procedure MultiLineDeclStdcall_NoFinding;
    [Test] procedure FuncPtrType_NoFinding;
    [Test] procedure UntypedOut_NoFinding;
    [Test] procedure OverrideAndImplTwin_NoFinding;
    // Gegenpruefung 2026-08-26: der Namensscan stoppte am '<' -
    // Zwilling war fuer generische Klassen wirkungslos.
    [Test] procedure OverrideGenericImplTwin_NoFinding;
    [Test] procedure FreeFunctionOutList_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestAvoidOut.NoOutParam_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(A: Integer); begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAvoidOut));
  finally F.Free; end;
end;

procedure TTestAvoidOut.OutParam_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(out S: string); begin S := ''hi''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkAvoidOut));
  finally F.Free; end;
end;

procedure TTestAvoidOut.VarParam_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(var S: string); begin S := ''hi''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAvoidOut));
  finally F.Free; end;
end;

procedure TTestAvoidOut.AvoidOut_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(out X: Integer); begin X := 0; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkAvoidOut then
      begin
        Assert.AreEqual<TFindingKind>(fkAvoidOut, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,    Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkAvoidOut finding');
  finally F.Free; end;
end;

procedure TTestAvoidOut.StdcallTail_NoFinding;
// G1: stdcall im Deklarations-Tail = ABI-Grenze (COM/DLL) - `out` ist
// dort Vertragsbestandteil, `var` keine Option.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure GetIface(out Obj: IInterface); stdcall;'#13#10 +
  'begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAvoidOut),
    'stdcall-Tail gated den Fund');
  finally F.Free; end;
end;

procedure TTestAvoidOut.DispidTail_NoFinding;
// G1: dispid = Automation-Interface, Signatur vom Typelib-Vertrag fixiert.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  IAuto = dispinterface'#13#10 +
  '    procedure GetValue(out V: OleVariant); dispid 12;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAvoidOut),
    'dispid-Tail gated den Fund');
  finally F.Free; end;
end;

procedure TTestAvoidOut.MultiLineDeclStdcall_NoFinding;
// Join-Probe: `out` auf der Kopfzeile, die Direktive erst hinter der
// schliessenden Klammer auf der FOLGEZEILE - FindOutParam sieht sie
// nie, das Gate joint die Deklaration und findet sie doch.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Ext(out A: Integer;'#13#10 +
  '  B: Integer); stdcall;'#13#10 +
  'begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAvoidOut),
    'gejointe Decl traegt stdcall');
  finally F.Free; end;
end;

procedure TTestAvoidOut.FuncPtrType_NoFinding;
// G2: `= function(...)` ist ein prozeduraler TYP (Callback-/DLL-Import-
// Vertrag), keine aenderbare Methode.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TResolver = function(out Res: Integer): Boolean;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAvoidOut),
    'Funktionszeiger-Signatur ist kein Methoden-Design');
  finally F.Free; end;
end;

procedure TTestAvoidOut.UntypedOut_NoFinding;
// G3: untypisiertes out (QueryInterface-/Supports-Muster) wird nicht
// finalisiert - die Regel-Begruendung greift nicht, var waere falsch.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Resolve(out Obj; const IID: TGUID); begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAvoidOut),
    'untypisiertes out ist kein Fund');
  finally F.Free; end;
end;

procedure TTestAvoidOut.OverrideAndImplTwin_NoFinding;
// G4: override = Basisklassen-Vertrag; der Implementations-Kopf
// wiederholt die Direktive NICHT und muss ueber den Namens-Zwilling
// mitfallen (Korpus-Beleg uwinnetfilesource:153/208).
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TSrc = class'#13#10 +
  '    procedure Fetch(out Data: string); override;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TSrc.Fetch(out Data: string);'#13#10 +
  'begin Data := ''''; end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAvoidOut),
    'override-Decl UND Impl-Zwilling schweigen');
  finally F.Free; end;
end;

procedure TTestAvoidOut.OverrideGenericImplTwin_NoFinding;
// Skeptiker-Fund: `procedure TCache<T>.TryGet(` - der Namensscan
// brach am '<' ab, HasDot blieb False, der Zwilling feuerte nie
// (Korpus-Beleg MVCFramework.LRUCache.pas:145). Generic-Segment
// wird jetzt uebersprungen: Decl gated per override, Impl-Kopf
// der generischen Klasse faellt namensbasiert mit.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TCache<T> = class'#13#10 +
  '    procedure TryGet(out Item: T); override;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TCache<T>.TryGet(out Item: T);'#13#10 +
  'begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAvoidOut),
    'generischer Impl-Zwilling faellt mit der override-Decl');
  finally F.Free; end;
end;

procedure TTestAvoidOut.FreeFunctionOutList_StillReported;
// Gegenprobe (CnIDEVersion-Muster): freie eigene Funktion ohne
// Direktiven ist der ADRESSAT der Regel - Namensliste bleibt Fund,
// G3 darf sie nicht fressen (',' hinter dem ersten Namen).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Split(out Head, Tail: string); begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkAvoidOut),
    'eigene API ohne ABI-Zwang bleibt gemeldet');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestAvoidOut);

end.
