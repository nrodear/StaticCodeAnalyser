unit uTestSelfAssignMemberPath;

// W2-Schaerfung SCA047 (2026-08-19): member-genaue Record-Pfade.
// Eigene Unit - fokussiert auf die Pfad-Aufloesung (Wurzel-Slot +
// blanke Record-Felder via Unit-Tabellen/RTL-Whitelist), und die
// Hauptfixture in uTestSelfAssignment bleibt unter der GodClass-
// Schwelle. Die Erwartungen entsprechen den am Korpus ausgezaehlten
// Faellen (Audit_WirkungFpArbeit_2026-08-18): Pt.Y/R^.iType kommen
// zurueck, TRectF.Height (Property!) und a[i] bleiben still.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSelfAssignMemberPath = class
  public
    [Test] procedure Self_RecordFieldPath_RtlPoint_Reported;
    [Test] procedure Self_RecordFieldPath_UnitRecord_Reported;
    [Test] procedure Self_PtrDerefRecordField_Reported;
    [Test] procedure Self_RecordPropertyPath_NotReported;
    [Test] procedure Self_RectFHeight_NotReported;
    [Test] procedure Self_IndexedPath_NotReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestSelfAssignMemberPath.Self_RecordFieldPath_RtlPoint_Reported;
// W2: Wurzel = Local, Segment = blankes RTL-Record-Feld (Whitelist).
// Exakt der JvgLogicsEditorForm-Fall aus dem Audit (Pt.Y := Pt.Y).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Pt: TPoint;'#13#10 +
  'begin Pt.Y := Pt.Y; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkSelfAssignment),
    'Record-Feld-Pfad mit beweisbarer Wurzel muss melden');
  finally F.Free; end;
end;

procedure TTestSelfAssignMemberPath.Self_RecordFieldPath_UnitRecord_Reported;
// W2: Record DIESER Unit - Feld kommt aus der AST-Tabelle, nicht aus
// der Whitelist.
const SRC =
  'unit t; interface'#13#10 +
  'type TVec = record X: Integer; Y: Integer; end;'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var V: TVec;'#13#10 +
  'begin V.X := V.X; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkSelfAssignment),
    'Unit-Record-Feld muss melden');
  finally F.Free; end;
end;

procedure TTestSelfAssignMemberPath.Self_PtrDerefRecordField_Reported;
// W2: '^'-Hop ueber einen Unit-Pointer-Alias (der mormot-Fall
// R^.iType := R^.iType, dort ueber PEnhMetaRecord aus der Whitelist).
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TVec = record X: Integer; end;'#13#10 +
  '  PVec = ^TVec;'#13#10 +
  'implementation'#13#10 +
  'procedure Foo(P: PVec);'#13#10 +
  'begin P^.X := P^.X; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkSelfAssignment),
    'Pointer-Deref auf Unit-Record-Feld muss melden');
  finally F.Free; end;
end;

procedure TTestSelfAssignMemberPath.Self_RecordPropertyPath_NotReported;
// W2-Waechter: Record-PROPERTY im Pfad -> Setter-Aufruf, kein No-op.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TClamp = record'#13#10 +
  '  private'#13#10 +
  '    FH: Integer;'#13#10 +
  '    procedure SetH(AValue: Integer);'#13#10 +
  '  public'#13#10 +
  '    property H: Integer read FH write SetH;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TClamp.SetH(AValue: Integer); begin FH := AValue; end;'#13#10 +
  'procedure Foo;'#13#10 +
  'var C: TClamp;'#13#10 +
  'begin C.H := C.H; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSelfAssignment),
    'Record-Property faehrt einen Setter - muss still bleiben');
  finally F.Free; end;
end;

procedure TTestSelfAssignMemberPath.Self_RectFHeight_NotReported;
// W2-Waechter fuer den Audit-Fall 1 (Alcinoe): TRectF.Height ist eine
// Record-Property mit Setter (schreibt Bottom) - die Whitelist fuehrt
// fuer trectf NUR die blanken Felder Left/Top/Right/Bottom.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var R: TRectF;'#13#10 +
  'begin R.Height := R.Height; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSelfAssignment),
    'TRectF.Height ist Property mit Setter - muss still bleiben');
  finally F.Free; end;
end;

procedure TTestSelfAssignMemberPath.Self_IndexedPath_NotReported;
// W2-Waechter: '[' bleibt pauschal aus (Index-Ausdruecke koennen sich
// zwischen LHS und RHS unterscheiden, Default-Properties laufen Setter).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var A: array[0..3] of TPoint; i: Integer;'#13#10 +
  'begin A[i].X := A[i].X; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSelfAssignment),
    'indizierter Pfad muss still bleiben');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSelfAssignMemberPath);

end.
