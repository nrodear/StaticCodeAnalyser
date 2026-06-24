unit uTestParserRobustness;

// Tests fuer Parser-Robustheit gegen Real-World-mORMot2-Konstrukte.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestSrcBuilder,
  uTestFindingHelper;

type
  // ---- Parser-Robustheit (Real-World mORMot2-Konstrukte) -----------------------------
  // Probe: jeder Test hat einen Memory-Leak in einer Methode, die DURCH oder
  // NACH dem zu testenden Konstrukt definiert ist. Wenn der Parser das
  // Konstrukt korrekt verarbeitet, wird der Leak gefunden; wenn nicht, geht
  // der Body verloren und der Leak verschwindet.
  [TestFixture]
  TTestParserRobustness = class
  public
    [Test] procedure Parser_InterfaceDecl_FollowingMethodLeakDetected;
    [Test] procedure Parser_GenericTypeDecl_MethodLeakDetected;
    [Test] procedure Parser_GenericMethodSig_LeakDetected;
    [Test] procedure Parser_PackedRecord_FollowingMethodLeakDetected;
    [Test] procedure Parser_LabelSection_BodyLeakDetected;
    [Test] procedure Parser_ClassHelperFor_FollowingMethodLeakDetected;
    [Test] procedure Parser_IfdefDuplicatedHeaders_NoPhantomDuplicate;
    [Test] procedure Parser_InlineRecordVarType_BodyNotLost;
    [Test] procedure Parser_NestedInlineRecordVarType_BodyNotLost;
    [Test] procedure Parser_InlineRecordTypeInLocalConst_BodyNotLost;
    [Test] procedure Parser_NestedRoutine_OuterBodyLeakDetected;
    [Test] procedure Parser_NestedRoutine_NestedBodyNotAnalyzed;
  end;

implementation

{ ---- TTestParserRobustness ---- }

procedure TTestParserRobustness.Parser_InterfaceDecl_FollowingMethodLeakDetected;
// Vorher: `IFoo = interface ... end;` hatte keinen Case in ParseTypeSection,
// fiel in TypeAlias-else-Branch, dessen Schleife beim ersten internen `;`
// brach -> komplettes Interface verloren UND der nachfolgende `end;` schloss
// einen ueberraschenden Block. Heute: tkKwInterface-Case ruft ParseClassBody
// und liest das Interface sauber - die nachfolgende Methode bleibt
// erkennbar.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  IFoo = interface'#13#10+
  '    procedure Bar;'#13#10+
  '    function Baz: Integer;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Test;'#13#10+
  'var L: TStringList;'#13#10+
  'begin'#13#10+
  '  L := TStringList.Create;'#13#10+
  '  // L.Free fehlt!'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMemoryLeak),
      'Leak in Methode nach Interface-Decl muss erkannt werden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_GenericTypeDecl_MethodLeakDetected;
// Vorher: `TFoo<T> = class` -> Eat(tkEq) schlug am `<` fehl -> SkipToSemicolon
// -> komplette Generic-Klasse verloren. Heute: SkipGenericParams konsumiert
// `<T>` vor dem `=`.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TBox<T> = class'#13#10+
  '    procedure Add(Item: T);'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'procedure TBox<T>.Add(Item: T);'#13#10+
  'var Tmp: TStringList;'#13#10+
  'begin'#13#10+
  '  Tmp := TStringList.Create;'#13#10+
  '  // Tmp.Free fehlt!'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMemoryLeak),
      'Leak in qualifizierter Generic-Methode muss erkannt werden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_GenericMethodSig_LeakDetected;
// Generic-Methode `function Get<T>: T;`. SkipGenericParams konsumiert das
// `<T>` nach dem Methodennamen, sodass die Param-Liste / Rueckgabetyp
// nicht verschoben werden.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure DoIt;'#13#10+
  'var L: TStringList;'#13#10+
  'begin'#13#10+
  '  L := TStringList.Create;'#13#10+
  'end;'#13#10+
  'function Get<T>: T;'#13#10+
  'begin'#13#10+
  '  Result := Default(T);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMemoryLeak),
      'DoIt vor Generic-Method muss als Leak erkannt werden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_PackedRecord_FollowingMethodLeakDetected;
// `packed record` wurde vorher als TypeAlias missinterpretiert weil
// tkKwPacked keinen Case hatte. Heute: optionales Eat(tkKwPacked) vor dem
// class/record-Switch.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TPoint = packed record'#13#10+
  '    X: Integer;'#13#10+
  '    Y: Integer;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'procedure UseLeak;'#13#10+
  'var L: TStringList;'#13#10+
  'begin'#13#10+
  '  L := TStringList.Create;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMemoryLeak),
      'Leak nach packed record muss erkannt werden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_LabelSection_BodyLeakDetected;
// `label x;` zwischen var-Block und begin liess vorher die Outer-Schleife
// in ParseLocalVarSection enden und ParseMethodImpl sah `label` statt
// `begin` -> Body verloren. Heute: tkKwLabel wird wie var/const/type als
// Section akzeptiert und bis zum naechsten ; geskippt.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure Tricky;'#13#10+
  'label'#13#10+
  '  loop1, loop2;'#13#10+
  'var'#13#10+
  '  L: TStringList;'#13#10+
  'begin'#13#10+
  '  L := TStringList.Create;'#13#10+
  '  // L.Free fehlt!'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMemoryLeak),
      'Leak in Methode mit label-Section muss erkannt werden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_ClassHelperFor_FollowingMethodLeakDetected;
// `record helper for string` war ein Stolperstein: nach `record` kam ein
// Ident `helper` der als Feld-Decl ge-misinterpretiert wurde. Heute:
// SkipHelperFor konsumiert `helper for <type>` bevor ParseClassBody startet.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TStringHelper = record helper for string'#13#10+
  '    function MyLen: Integer;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'function TStringHelper.MyLen: Integer;'#13#10+
  'begin'#13#10+
  '  Result := Length(Self);'#13#10+
  'end;'#13#10+
  'procedure UseLeak;'#13#10+
  'var L: TStringList;'#13#10+
  'begin'#13#10+
  '  L := TStringList.Create;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMemoryLeak),
      'Leak nach record helper muss erkannt werden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_IfdefDuplicatedHeaders_NoPhantomDuplicate;
// IFDEF um Method-Header herum ergibt zwei sichtbare Header im Token-Stream
// (Lexer skippt nur Comments). ParseMethodImpl entfernt jetzt einen
// Headless-Knoten wenn der naechste Token wieder ein Method-Keyword ist
// -> kein Phantom-Duplikat im AST mehr.
//
// Wir testen das indirekt: ein Leak in dem (echten) Body soll genau einmal
// gemeldet werden, nicht doppelt durch Phantom-Methode.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  '{$IFDEF FPC}'#13#10+
  'function DoIt: Integer;'#13#10+
  '{$ELSE}'#13#10+
  'function DoIt: Integer;'#13#10+
  '{$ENDIF}'#13#10+
  'var L: TStringList;'#13#10+
  'begin'#13#10+
  '  L := TStringList.Create;'#13#10+
  '  Result := L.Count;'#13#10+
  '  // L.Free fehlt!'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMemoryLeak),
      'Leak darf nicht durch Phantom-Methoden-Duplikat verdoppelt werden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_InlineRecordVarType_BodyNotLost;
// Vorher: anonymer `record`-Typ als Var-Typ - TypeName-Loop in
// ParseLocalVarSection brach am ersten `;` _innerhalb_ des records ab,
// dann las der Outer-Loop das folgende `end` als Section-Grenze und
// ParseMethodImpl verlor den Methodenrumpf -> Leak weg, doppelter Bug.
// Heute: Mini-Parser bis matching `end`.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Test;'#13#10+
  'var'#13#10+
  '  R: record A: Integer; B: Integer; end;'#13#10+
  '  L: TStringList;'#13#10+
  'begin'#13#10+
  '  L := TStringList.Create;'#13#10+
  '  // L.Free fehlt!'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMemoryLeak),
      'Leak nach inline-record-Var-Typ muss erkannt werden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_NestedInlineRecordVarType_BodyNotLost;
// Nested record inside record - Depth-Tracking muss beide `end` zaehlen.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Test;'#13#10+
  'var'#13#10+
  '  R: record'#13#10+
  '    A: record X: Integer; Y: Integer; end;'#13#10+
  '    B: Integer;'#13#10+
  '  end;'#13#10+
  '  L: TStringList;'#13#10+
  'begin'#13#10+
  '  L := TStringList.Create;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMemoryLeak),
      'Leak nach nested-inline-record muss erkannt werden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_InlineRecordTypeInLocalConst_BodyNotLost;
// Inline-record als Typ einer Local-Const-Initialisierung. Section bleibt
// auf var (kein type-Section); der Mini-Parser muss auch hier sauber
// laufen, sonst geht der Body verloren.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Test;'#13#10+
  'var'#13#10+
  '  P: record Key: string; Value: Integer; end;'#13#10+
  '  L: TStringList;'#13#10+
  'begin'#13#10+
  '  L := TStringList.Create;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMemoryLeak),
      'Leak nach Single-Line inline-record muss erkannt werden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_NestedRoutine_OuterBodyLeakDetected;
// Root-Cause-Fix Parser nested routine: eine lokale `procedure` VOR dem
// begin der aeusseren Methode. Vorher fraß ParseLocalVarSection sie als
// Pseudo-Var und ParseMethodImpl nahm den NESTED-Body als Outer-Body ->
// der echte Outer-Body (mit dem Leak) ging verloren. Heute wird die nested
// routine als eigenes nkMethod-Child geparst, der Outer-Body bleibt erhalten.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Test;'#13#10+
  'var L: TStringList;'#13#10+
  '  procedure Helper;'#13#10+
  '  begin'#13#10+
  '    Sleep(1);'#13#10+
  '  end;'#13#10+
  'begin'#13#10+
  '  L := TStringList.Create;'#13#10+
  '  Helper;'#13#10+
  '  // L.Free fehlt!'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMemoryLeak),
      'Outer-Body-Leak darf durch nested routine nicht verschwinden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_NestedRoutine_NestedBodyNotAnalyzed;
// Der Leak steckt IM Body der nested routine. Nested routines werden geparst
// (damit der Outer-Body nicht verloren geht), aber bewusst NICHT als
// analysierbare Methoden im AST belassen (siehe ParseMethodImpl). Daher wird
// der Leak in der nested routine NICHT als fkMemoryLeak gemeldet - konsistent
// mit dem fruehen Verhalten (AST enthielt nie nested routines) und vermeidet
// die Findings-Flut auf nested Helpern. Wichtig ist nur: der Outer-Body bleibt
// intakt (X := 1 wird sauber geparst, kein Crash, kein verlorener Body).
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Test;'#13#10+
  'var X: Integer;'#13#10+
  '  procedure Helper;'#13#10+
  '  var L: TStringList;'#13#10+
  '  begin'#13#10+
  '    L := TStringList.Create;'#13#10+
  '    // L.Free fehlt!'#13#10+
  '  end;'#13#10+
  'begin'#13#10+
  '  X := 1;'#13#10+
  '  Helper;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Leak in nested routine wird nicht standalone gemeldet (nicht analysiert)');
  finally F.Free; end;
end;

end.
