unit uTestUninitVar;

// Tests fuer TUninitVarDetector (SCA166 fkUninitVar).
// Siehe Konzept_SCA166_UninitVar.md §12 fuer die Test-Strategie.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12, uTestFindingHelper;

type
  [TestFixture]
  TTestUninitVar = class
  public
    // ---- POSITIV (MUST flag fkUninitVar) ----
    [Test] procedure NeverWritten_OnlyRead_Flagged;
    [Test] procedure ConditionalWriteInIf_ReadAfter_Flagged;
    [Test] procedure ReadBeforeWrite_SequentialLines_Flagged;
    [Test] procedure CaseWriteWithoutElse_ReadAfter_Flagged;
    [Test] procedure TryExceptWriteOnly_ReadAfter_Flagged;
    [Test] procedure ClassInstanceUsedBeforeCreate_Flagged;
    // 2026-07-05 Gegenprobe: in-Unit-KLASSE wird NICHT breit gegated
    [Test] procedure InUnitClassReceiverMethod_StillFlagged;

    // ---- NEGATIV (MUST NOT flag) ----
    [Test] procedure CleanAssignThenRead_NoFinding;
    [Test] procedure UnderscorePrefix_NoFinding;
    [Test] procedure ManagedString_NoFinding;
    [Test] procedure ManagedDynamicArray_NoFinding;
    [Test] procedure ReadLnInitialisesVar_NoFinding;
    [Test] procedure ForLoopInitialisesVar_NoFinding;
    [Test] procedure ForInInlineVar_NoFinding;
    [Test] procedure TryGetGenericOutArg_NoFinding;
    [Test] procedure MultiLineVarDeclContinuation_NoFinding;
    [Test] procedure AbsoluteAlias_NoFinding;
    [Test] procedure ReceiverInitMethod_NoFinding;
    // 2026-07-05: in-Unit-Record-Receiver -> JEDER Methodenaufruf initialisiert
    [Test] procedure InUnitRecordReceiverMethod_AnyName_NoFinding;
    // 2026-07-05: cross-unit record via Allowlist-Verb 'prepare' (mORMot TMatch)
    [Test] procedure CrossUnitRecordPrepare_NoFinding;
    [Test] procedure FillCharInitialisesVar_NoFinding;
    [Test] procedure WriteBeforeRead_TryFinally_NoFinding;
    [Test] procedure DeclaredButNeverReferenced_NoFinding;
    [Test] procedure MultiLineVarDecl_CommaList_NoFinding;
    [Test] procedure VarDeclWithInit_NoFinding;

    // ---- EDGE CASES ----
    [Test] procedure AsmBlock_NoCrash;
    [Test] procedure EmptyMethod_NoCrash;
    [Test] procedure MultipleVarsSomeClean_OnlyDirtyFlagged;
    // Real-World 2026-06-23: Array-Element-Write + @/SizeOf kein Read
    [Test] procedure ArrayElementWrite_NoFinding;
    [Test] procedure SizeOfAndAddressOf_NoFinding;
    // Root-Cause-Fix Parser nested routine (2026-06-24)
    [Test] procedure NestedRoutine_OuterVarWrittenBeforeNestedRead_NoFinding;
    // Parser nkNestedRange-Marker -> exakte nested-Range-Skips (2026-06-25)
    [Test] procedure NestedProcWithTry_OuterVarInLaterNested_NoFinding;
    // Real-World 2026-06-28: Auto-init-Record (TRttiContext) + escaped-field
    // Array-Element-Write (name[0].&Type := ...)
    [Test] procedure RttiContextRecord_NoFinding;
    [Test] procedure NonAutoInitRecord_StillFlagged;
    [Test] procedure EscapedFieldArrayElementWrite_NoFinding;
    // Real-World 2026-06-28: Read-Family-Fill (Stream.Read fuellt Buffer)
    [Test] procedure StreamReadFillsIndexedBuffer_NoFinding;
    [Test] procedure StreamReadFillsBareBuffer_NoFinding;
    [Test] procedure ReadBeforeStreamFill_StillFlagged;
    [Test] procedure StreamFillThenLaterArgWrite_NoFinding;
    // Real-World 2026-06-28: Nested-Closure unter Headless-Method-Pattern
    [Test] procedure OuterVarReadOnlyInNestedRoutine_NoFinding;
    [Test] procedure OuterVarUninitDespiteNestedRoutine_StillFlagged;
  end;

implementation

function CountKind(L: TObjectList<TLeakFinding>; K: TFindingKind): Integer;
var
  F : TLeakFinding;
begin
  Result := 0;
  for F in L do
    if F.Kind = K then Inc(Result);
end;

procedure RunOn(const Src: string; out Findings: TObjectList<TLeakFinding>);
begin
  Findings := TFindingHelper.FindingsOfFile(Src);
end;

// ============================================================
// POSITIV
// ============================================================

procedure TTestUninitVar.NeverWritten_OnlyRead_Flagged;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var n: Integer;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(n);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.IsTrue(CountKind(L, fkUninitVar) >= 1,
      'Variable nur gelesen, nie geschrieben - muss SCA166 ausloesen');
  finally L.Free; end;
end;

procedure TTestUninitVar.ConditionalWriteInIf_ReadAfter_Flagged;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(c: Boolean);'#13#10 +
    'var n: Integer;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(n);'#13#10 +
    '  if c then n := 1;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.IsTrue(CountKind(L, fkUninitVar) >= 1,
      'Read VOR conditional-Write - muss flaggen');
  finally L.Free; end;
end;

procedure TTestUninitVar.ReadBeforeWrite_SequentialLines_Flagged;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var n: Integer;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(n);'#13#10 +
    '  n := 42;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.IsTrue(CountKind(L, fkUninitVar) >= 1,
      'Read VOR Write - klassischer UninitVar');
  finally L.Free; end;
end;

procedure TTestUninitVar.CaseWriteWithoutElse_ReadAfter_Flagged;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(k: Integer);'#13#10 +
    'var n: Integer;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(n);'#13#10 +
    '  case k of'#13#10 +
    '    1: n := 10;'#13#10 +
    '    2: n := 20;'#13#10 +
    '  end;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.IsTrue(CountKind(L, fkUninitVar) >= 1,
      'Read vor case-Write ohne else - muss flaggen');
  finally L.Free; end;
end;

procedure TTestUninitVar.TryExceptWriteOnly_ReadAfter_Flagged;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var n: Integer;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(n);'#13#10 +
    '  try'#13#10 +
    '    DoSomething();'#13#10 +
    '  except'#13#10 +
    '    n := 0;'#13#10 +
    '  end;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.IsTrue(CountKind(L, fkUninitVar) >= 1,
      'Read vor try-except-Write - muss flaggen');
  finally L.Free; end;
end;

procedure TTestUninitVar.ClassInstanceUsedBeforeCreate_Flagged;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'uses System.Classes;'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var L: TStringList;'#13#10 +
    'begin'#13#10 +
    '  L.Add(''x'');'#13#10 +
    '  L := TStringList.Create;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  Findings : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, Findings);
  try
    Assert.IsTrue(CountKind(Findings, fkUninitVar) >= 1,
      'Klassen-Instanz gelesen vor Create - muss flaggen');
  finally Findings.Free; end;
end;

// ============================================================
// NEGATIV
// ============================================================

procedure TTestUninitVar.CleanAssignThenRead_NoFinding;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var n: Integer;'#13#10 +
    'begin'#13#10 +
    '  n := 0;'#13#10 +
    '  WriteLn(n);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'Sauber initialisiert - kein SCA166');
  finally L.Free; end;
end;

procedure TTestUninitVar.UnderscorePrefix_NoFinding;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var _temp: Integer;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(_temp);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      '_-Prefix Konvention - kein Flag');
  finally L.Free; end;
end;

procedure TTestUninitVar.ManagedString_NoFinding;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var s: string;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(s);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'Managed type (string) - Pascal initialisiert - kein Flag');
  finally L.Free; end;
end;

procedure TTestUninitVar.ManagedDynamicArray_NoFinding;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var arr: TArray<Integer>;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(Length(arr));'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'TArray<T> ist managed - kein Flag');
  finally L.Free; end;
end;

procedure TTestUninitVar.ReadLnInitialisesVar_NoFinding;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var n: Integer;'#13#10 +
    'begin'#13#10 +
    '  ReadLn(n);'#13#10 +
    '  WriteLn(n);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'ReadLn ist Write (Allowlist) - kein Flag');
  finally L.Free; end;
end;

procedure TTestUninitVar.ForLoopInitialisesVar_NoFinding;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var i: Integer;'#13#10 +
    'begin'#13#10 +
    '  for i := 0 to 10 do'#13#10 +
    '    WriteLn(i);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'for-Loop initialisiert Index-Var - kein Flag');
  finally L.Free; end;
end;

procedure TTestUninitVar.ForInInlineVar_NoFinding;
// Regression LogStats_plugin MainForm.pas:352 - 'for var Pair in ADict do'
// darf NIE UninitVar werfen. Die LoopVar wird implizit vom Enumerator
// vor jedem Body-Durchlauf zugewiesen.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'uses System.Generics.Collections;'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var D: TDictionary<string,Integer>;'#13#10 +
    'begin'#13#10 +
    '  D := TDictionary<string,Integer>.Create;'#13#10 +
    '  for var Pair in D do'#13#10 +
    '    WriteLn(Pair.Key);'#13#10 +
    '  D.Free;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'for-in mit inline-var darf kein UninitVar werfen');
  finally L.Free; end;
end;

procedure TTestUninitVar.TryGetGenericOutArg_NoFinding;
// Regression DUnitX.TestFramework.pas:851 - das Pattern
//   if rType.TryGetAttributeOfType<TestFixtureAttribute>(attrib) then
//     sName := attrib.Name;
// darf KEIN UninitVar werfen. ParseCallsInExpr muss den Generic-Type-
// Parameter <T> zwischen Funktionsname und '(' ueberspringen, damit
// 'attrib' als Call-Arg erkannt und pessimistic als Write registriert
// wird.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var attrib: TObject; sName: string;'#13#10 +
    'begin'#13#10 +
    '  if TryGet<TObject>(attrib) then'#13#10 +
    '    sName := attrib.ClassName;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'TryGet<T>(out arg) im if-Condition darf kein UninitVar werfen');
  finally L.Free; end;
end;

procedure TTestUninitVar.MultiLineVarDeclContinuation_NoFinding;
// Regression TCodeReader RGBLuminanceSource.pas (20 FPs in einer Datei):
// Multi-line var-Decl mit Ein-Ident-pro-Zeile - Continuation-Zeilen
// (nur 'name,' am Zeilenende) duerfen NICHT als Reads interpretiert
// werden. IsVarDeclLine erkennt nur die finale Zeile mit ':type;'.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var'#13#10 +
    '  byte1,'#13#10 +
    '  byte2,'#13#10 +
    '  b5, g5, r5,'#13#10 +
    '  r8, g8, b8 : Byte;'#13#10 +
    'begin'#13#10 +
    '  byte1 := 0;'#13#10 +
    '  byte2 := 0;'#13#10 +
    '  b5 := byte1; g5 := byte1; r5 := byte1;'#13#10 +
    '  r8 := r5; g8 := g5; b8 := b5;'#13#10 +
    '  WriteLn(r8 + g8 + b8);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'multi-line var-decl continuation darf kein UninitVar werfen');
  finally L.Free; end;
end;

procedure TTestUninitVar.AbsoluteAlias_NoFinding;
// Regression Img32.Extra BlendAverage/AlphaAverage (~30 FPs):
// 'c1: TARGB absolute color1;' macht c1 zum Alias der bestehenden
// Variable - eigene Storage gibt es nicht, also auch keine Init-Pflicht.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'function Foo(color: Cardinal): Cardinal;'#13#10 +
    'var c: Cardinal absolute color;'#13#10 +
    'begin'#13#10 +
    '  Result := c shr 8;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'absolute-Alias darf nicht als UninitVar gewertet werden');
  finally L.Free; end;
end;

procedure TTestUninitVar.ReceiverInitMethod_NoFinding;
// Regression mORMot TDocVariantData.InitJson - 'doc.Init<...>(args)' am
// Receiver behandelt mORMot/Spring als Stack-Init: KEINE Init-Pflicht
// vor dem Aufruf.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(const data: string);'#13#10 +
    'var doc: TDocVariantData;'#13#10 +
    'begin'#13#10 +
    '  doc.InitJson(data);'#13#10 +
    '  WriteLn(doc.Count);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'doc.InitJson(...) als erstes Statement = Init des Receivers');
  finally L.Free; end;
end;

procedure TTestUninitVar.InUnitRecordReceiverMethod_AnyName_NoFinding;
// Der Typ TMatch ist in DIESER Unit als record deklariert (nkRecord). Ein
// Methodenaufruf am Record-Receiver initialisiert dessen Felder (Self ist
// var) - das gilt fuer JEDEN Methodennamen, nicht nur die Init-Verb-
// Allowlist. 'Configure' steht bewusst NICHT auf der Allowlist; allein der
// Record-Typ-Check traegt. (Analog mORMot record-with-methods.)
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TMatch = record'#13#10 +
    '    FData: Integer;'#13#10 +
    '    procedure Configure(v: Integer);'#13#10 +
    '    function Run: Boolean;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure TMatch.Configure(v: Integer); begin FData := v; end;'#13#10 +
    'function TMatch.Run: Boolean; begin Result := FData > 0; end;'#13#10 +
    'function IsIt: Boolean;'#13#10 +
    'var m: TMatch;'#13#10 +
    'begin'#13#10 +
    '  m.Configure(42);'#13#10 +
    '  Result := m.Run;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'in-Unit-Record: Methodenaufruf initialisiert den Receiver (jeder Name)');
  finally L.Free; end;
end;

procedure TTestUninitVar.CrossUnitRecordPrepare_NoFinding;
// Exakter Real-World-FP: mORMot mormot.core.search.IsMatch. TMatch ist in
// einer ANDEREN Unit deklariert (hier nicht sichtbar) -> faellt auf die
// Init-Verb-Allowlist zurueck; 'prepare' ist jetzt drin. match.Prepare(...)
// initialisiert den Record, match.Match(...) liest danach.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'function IsMatch(const Pattern, Text: RawUtf8; ci: boolean): boolean;'#13#10 +
    'var match: TMatch;'#13#10 +
    'begin'#13#10 +
    '  match.Prepare(pointer(Pattern), length(Pattern), ci, false);'#13#10 +
    '  result := match.Match(Text);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'match.Prepare(...) initialisiert den Record - kein UninitVar');
  finally L.Free; end;
end;

procedure TTestUninitVar.InUnitClassReceiverMethod_StillFlagged;
// Gegenprobe zum Record-Gate: TFoo ist in dieser Unit eine KLASSE (nkClass,
// NICHT nkRecord). Der Record-Broad-Gate darf hier NICHT greifen - 'f.Go'
// auf einer nie zugewiesenen Klassen-Referenz bleibt ein echter Fund
// (Read vor Write). 'Go' ist zudem kein Allowlist-Verb.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TFoo = class'#13#10 +
    '    procedure Go;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure TFoo.Go; begin end;'#13#10 +
    'procedure P;'#13#10 +
    'var f: TFoo;'#13#10 +
    'begin'#13#10 +
    '  f.Go;'#13#10 +
    '  f := TFoo.Create;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.IsTrue(CountKind(L, fkUninitVar) >= 1,
      'in-Unit-Klasse: Methodenaufruf auf uninit. Referenz bleibt ein Fund');
  finally L.Free; end;
end;

procedure TTestUninitVar.FillCharInitialisesVar_NoFinding;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'type TRec = record A: Integer; end;'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var r: TRec;'#13#10 +
    'begin'#13#10 +
    '  FillChar(r, SizeOf(r), 0);'#13#10 +
    '  WriteLn(r.A);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'FillChar ist Write (Allowlist) - kein Flag');
  finally L.Free; end;
end;

procedure TTestUninitVar.WriteBeforeRead_TryFinally_NoFinding;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'uses System.Classes;'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var L: TStringList;'#13#10 +
    'begin'#13#10 +
    '  L := TStringList.Create;'#13#10 +
    '  try'#13#10 +
    '    L.Add(''x'');'#13#10 +
    '  finally'#13#10 +
    '    L.Free;'#13#10 +
    '  end;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  Findings : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, Findings);
  try
    Assert.AreEqual<Integer>(0, CountKind(Findings, fkUninitVar),
      'Write VOR Read im try-finally - kein Flag');
  finally Findings.Free; end;
end;

procedure TTestUninitVar.DeclaredButNeverReferenced_NoFinding;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var n: Integer;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(''hi'');'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    // Variable n wird nirgends referenziert - das ist UnusedLocal-Domain
    // (SCA019), KEIN UninitVar. Wir muessen sicherstellen dass kein
    // SCA166 emittiert wird.
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'Nicht referenziert - faellt unter UnusedLocal, nicht UninitVar');
  finally L.Free; end;
end;

procedure TTestUninitVar.MultiLineVarDecl_CommaList_NoFinding;
// FP-Fix doublecmd-Audit (EUCSampler.pas:86, nsMBCSMultiProber.pas:277):
// Multi-line var-decl mit Komma-Auflistung listet die Variablen auf
// mehreren Zeilen auf. Der Parser meldet nur EINE DeclLine pro Var.
// Die Zeilen wo die anderen Idents stehen dürfen NICHT als Read
// interpretiert werden.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'function F: Double;'#13#10 +
    'var'#13#10 +
    '   s,'#13#10 +              // Zeile 6: erster Decl-Teil
    '   sum: Double;'#13#10 +   // Zeile 7: zweiter Decl-Teil + Typ
    '   i: Integer;'#13#10 +    // Zeile 8
    'begin'#13#10 +
    '   sum := 0.0;'#13#10 +     // Zeile 10: erster Write
    '   for i := 0 to 10 do'#13#10 +
    '     sum := sum + i;'#13#10 +
    '   Result := sum;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'Multi-line var-decl darf NICHT als Read interpretiert werden');
  finally L.Free; end;
end;

procedure TTestUninitVar.VarDeclWithInit_NoFinding;
// Var-Decl mit Init-Value (`: Type = Value;`) wird als FirstWriteLine
// behandelt - kein UninitVar-Befund.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'function F: Integer;'#13#10 +
    'var n: Integer;'#13#10 +
    'begin'#13#10 +
    '  n := 42;'#13#10 +
    '  Result := n;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'Var-Decl + Assignment + Read ist sauberes Pattern, kein UninitVar');
  finally L.Free; end;
end;

// ============================================================
// EDGE CASES
// ============================================================

procedure TTestUninitVar.AsmBlock_NoCrash;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var n: Integer;'#13#10 +
    'asm'#13#10 +
    '  mov eax, n'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  // Detector soll asm-Block ueberspringen, nicht crashen.
  RunOn(SRC, L);
  try
    Assert.Pass('asm-Block - kein Crash');
  finally L.Free; end;
end;

procedure TTestUninitVar.EmptyMethod_NoCrash;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'begin'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'Leere Methode ohne LocalVars - kein Flag');
  finally L.Free; end;
end;

procedure TTestUninitVar.MultipleVarsSomeClean_OnlyDirtyFlagged;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var'#13#10 +
    '  a: Integer;'#13#10 +
    '  b: Integer;'#13#10 +
    'begin'#13#10 +
    '  a := 1;'#13#10 +
    '  WriteLn(a);'#13#10 +
    '  WriteLn(b);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    // a ist sauber, b ist UninitVar - es soll genau 1 Finding sein.
    Assert.AreEqual<Integer>(1, CountKind(L, fkUninitVar),
      'Nur b sollte geflaggt werden, a ist sauber');
  finally L.Free; end;
end;

procedure TTestUninitVar.ArrayElementWrite_NoFinding;
// FP-Fix (Real-World 2026-06-23): `LActions[0] := ...` ist ein Element-Write
// (Initialisierung), kein Read-Before-Write der Array-Variable.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var LActions: array[0..1] of Integer;'#13#10 +
    'begin'#13#10 +
    '  LActions[0] := 1;'#13#10 +
    '  LActions[1] := 2;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
    'Array-Element-Write ist Initialisierung, kein Uninit-Read');
  finally L.Free; end;
end;

procedure TTestUninitVar.SizeOfAndAddressOf_NoFinding;
// FP-Fix (Real-World 2026-06-23): `SizeOf(Buf)` und `@Buf` lesen NICHT den
// Wert - oft WinAPI-Out-Param der den Buffer erst fuellt.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var Buf: array[0..15] of Byte; n: Integer;'#13#10 +
    'begin'#13#10 +
    '  n := SizeOf(Buf);'#13#10 +
    '  FillStuff(@Buf, n);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
    'SizeOf(var) / @var sind kein Werte-Read');
  finally L.Free; end;
end;

procedure TTestUninitVar.NestedRoutine_OuterVarWrittenBeforeNestedRead_NoFinding;
// Root-Cause-Fix Parser nested routine: aeussere var `n` wird im OUTER-Body
// geschrieben (`n := 5`) und nur in der nested routine gelesen. Frueher fraß
// ParseLocalVarSection die nested routine als Pseudo-Var und ParseMethodImpl
// nahm den NESTED-Body (`WriteLn(n)`) als Outer-Body -> der echte Outer-Write
// ging verloren -> `n` schien nur gelesen, nie geschrieben -> FP. Jetzt bleibt
// der Outer-Body erhalten, der Write steht vor dem Read.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var n: Integer;'#13#10 +
    '  procedure Helper;'#13#10 +
    '  begin'#13#10 +
    '    WriteLn(n);'#13#10 +
    '  end;'#13#10 +
    'begin'#13#10 +
    '  n := 5;'#13#10 +
    '  Helper;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
    'Outer-Var im Outer-Body geschrieben - nested routine darf Body nicht verschlucken');
  finally L.Free; end;
end;

procedure TTestUninitVar.NestedProcWithTry_OuterVarInLaterNested_NoFinding;
// nkNestedRange-Marker (Parser): eine nested proc MIT try/finally vor einer
// zweiten nested proc, die eine Outer-Var liest (Outer-Var erst im Outer-Body
// zugewiesen). Die line-basierte begin/end-Heuristik balanciert try/case-end
// nicht und konnte die nested-Range abschneiden -> Read galt als Outer-Read ->
// SCA166-FP. Der Parser haengt jetzt EXAKTE nkNestedRange-Marker an die Methode;
// SCA166 skippt damit Reads in nested procs zuverlaessig.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure Outer;'#13#10 +
    'var Data: TStringList;'#13#10 +
    '  procedure First;'#13#10 +
    '  begin'#13#10 +
    '    try'#13#10 +
    '      DoA;'#13#10 +
    '    finally'#13#10 +
    '      DoB;'#13#10 +
    '    end;'#13#10 +
    '  end;'#13#10 +
    '  procedure Second;'#13#10 +
    '  begin'#13#10 +
    '    Data.Add(''x'');'#13#10 +
    '  end;'#13#10 +
    'begin'#13#10 +
    '  Data := TStringList.Create;'#13#10 +
    '  First;'#13#10 +
    '  Second;'#13#10 +
    '  Data.Free;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
    'Read einer Outer-Var in nested proc (nach try-proc) ist kein uninit');
  finally L.Free; end;
end;

procedure TTestUninitVar.RttiContextRecord_NoFinding;
// FP-Fix (Real-World 2026-06-28, Alcinoe.FMX.Controls:1852 / CEF4):
//   var LContext: TRttiContext;
//   LType := LContext.GetType(...);
// TRttiContext ist ein Auto-init-Record (lazy Self-Init / Management-
// Operatoren). Bare-Verwendung ohne explizite Zuweisung ist das Standard-
// RTTI-Idiom und NIE ein uninitialisierter Read.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'uses System.Rtti;'#13#10 +
    'implementation'#13#10 +
    'procedure P(Obj: TObject);'#13#10 +
    'var LContext: TRttiContext;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(LContext.GetType(Obj.ClassType).Name);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
    'TRttiContext ist Auto-init-Record - bare-Verwendung kein UninitVar');
  finally L.Free; end;
end;

procedure TTestUninitVar.NonAutoInitRecord_StillFlagged;
// TP-Gegenkontrolle: die NOINIT_RECORD_TYPES-Denylist ist eng (nur
// TRttiContext). Ein gewoehnlicher Record der vor jedem Write gelesen
// wird MUSS weiter feuern - sonst waere die Denylist zu breit.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'uses System.Types;'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var pt: TPoint;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(pt.X);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.IsTrue(CountKind(L, fkUninitVar) >= 1,
    'gewoehnlicher Record (TPoint) vor Write gelesen - muss weiter flaggen');
  finally L.Free; end;
end;

procedure TTestUninitVar.EscapedFieldArrayElementWrite_NoFinding;
// FP-Fix (Real-World 2026-06-28, Alcinoe.ServiceUtils:107):
//   var LActions: array[0..2] of SC_ACTION;
//   LActions[0].&Type := SC_ACTION_RESTART;
// Das escaped-keyword-Feld '&Type' brach den Qualifier-Walk im Array-
// Element-Write-Skip ab -> der Write wurde als Read fehlgedeutet. Mit '&'
// im Charset wird '[0].&Type :=' korrekt als Element-Write erkannt.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'type TAct = record &Type: Integer; Delay: Integer; end;'#13#10 +
    'procedure P;'#13#10 +
    'var LActions: array[0..1] of TAct;'#13#10 +
    'begin'#13#10 +
    '  LActions[0].&Type := 1;'#13#10 +
    '  LActions[0].Delay := 5000;'#13#10 +
    '  LActions[1].&Type := 1;'#13#10 +
    '  LActions[1].Delay := 5000;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
    'name[i].&Field := ... ist Element-Write (escaped keyword), kein Read');
  finally L.Free; end;
end;

procedure TTestUninitVar.StreamReadFillsIndexedBuffer_NoFinding;
// FP-Fix (Real-World 2026-06-28, Abbrevia AbCompnd / zip / ID3 etc.):
//   var Sig: array[..] of AnsiChar;
//   FStream.Read(Sig[0], n);   <- FUELLT den Buffer (out/var), kein Read
//   if Sig[0] = 'A' ...
// Der by-reference Array-Element-Arg 'Sig[0]' wurde als Read fehlgedeutet,
// der Buffer als "never assigned" gemeldet. Read-Family-Calls fuellen ihre
// Argumente -> das ist ein Write.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'uses System.Classes;'#13#10 +
    'implementation'#13#10 +
    'procedure P(FStream: TStream);'#13#10 +
    'var Sig: array[0..3] of AnsiChar;'#13#10 +
    'begin'#13#10 +
    '  FStream.Read(Sig[0], 4);'#13#10 +
    '  if Sig[0] = ''A'' then Exit;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
    'Stream.Read(Buf[0], n) fuellt den Buffer - kein UninitVar');
  finally L.Free; end;
end;

procedure TTestUninitVar.StreamReadFillsBareBuffer_NoFinding;
// Variante mit bare-Buffer-Arg (CnScanners Bom-Pattern, fcMedium):
//   Stream.Read(Bom, SizeOf(Bom));  <- Fill
//   if Bom[0] = #255 ...
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'uses System.Classes;'#13#10 +
    'implementation'#13#10 +
    'procedure P(Stream: TStream);'#13#10 +
    'var Bom: array[0..1] of AnsiChar;'#13#10 +
    'begin'#13#10 +
    '  Stream.Read(Bom, SizeOf(Bom));'#13#10 +
    '  if Bom[0] = #255 then Exit;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
    'Stream.Read(Bom, SizeOf(Bom)) fuellt den Buffer - kein UninitVar');
  finally L.Free; end;
end;

procedure TTestUninitVar.ReadBeforeStreamFill_StillFlagged;
// TP-Gegenkontrolle: ein ECHTER Read VOR dem Read-Family-Fill bleibt ein
// Bug. Die Fill-Erkennung darf nur die Fill-Zeile entschaerfen, nicht einen
// frueheren echten Read verschlucken.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'uses System.Classes;'#13#10 +
    'implementation'#13#10 +
    'procedure P(Stream: TStream);'#13#10 +
    'var n: Integer;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(n);'#13#10 +
    '  Stream.Read(n, SizeOf(n));'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.IsTrue(CountKind(L, fkUninitVar) >= 1,
    'echter Read vor dem Stream.Read-Fill bleibt ein UninitVar-Bug');
  finally L.Free; end;
end;

procedure TTestUninitVar.StreamFillThenLaterArgWrite_NoFinding;
// FP-Fix (Real-World 2026-06-28, SynEdit/Abbrevia relocated FPs): Num wird per
// Stream.Read gefuellt (echter Write), spaeter via Dec(Num) als Pessimistic-
// Arg-Write an SPAETERER Zeile erneut "geschrieben". Frueher maskierte der
// spaetere Dec-Write den echten Fill -> der Befund wurde nur verschoben
// (read 'while Num>0' vor dem Dec-Write). Earliest-Write-gewinnt loest auf.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'uses System.Classes;'#13#10 +
    'implementation'#13#10 +
    'procedure P(AStream: TStream);'#13#10 +
    'var Num: Integer;'#13#10 +
    'begin'#13#10 +
    '  AStream.Read(Num, SizeOf(Num));'#13#10 +
    '  while Num > 0 do'#13#10 +
    '    Dec(Num);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
    'Stream.Read-Fill darf nicht von spaeterem Dec(Num)-Arg-Write maskiert werden');
  finally L.Free; end;
end;

procedure TTestUninitVar.OuterVarReadOnlyInNestedRoutine_NoFinding;
// FP-Fix (Real-World 2026-06-28, uRuleCatalog.FindJsonFile / uFormatMismatch):
// outer-var 'Cands' wird im OUTER-Body erzeugt, aber nur in der nested routine
// 'AddRoot' gelesen. Die zweite var-Section ('C') triggert das Parser-Headless-
// Pattern -> nkNestedRange-Marker fehlen, AST-Outer-Write geht verloren ->
// frueher fcHigh-FP. Source-basierte Closure-Erkennung faengt das ab.
const
  // Verbatim-getreue Nachbildung von uRuleCatalog.FindJsonFile (Real-World-FP):
  // class function mit qualifiziertem Namen, Kommentar vor der Decl, nested
  // 'AddRoots' (liest Cands in einem for-begin, eigene var Dir/Parent/i),
  // nested function 'ModuleDir', ZWEITE var-Section (C), try/finally, Cands-
  // Create im outer-body. Exakt das Headless-Method-Pattern, das SCA166 frueher
  // als 'Cands never assigned' (fcHigh) fehlmeldete.
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TRuleCatalog = class'#13#10 +
    '    class function FindJsonFile: string; static;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'uses System.Generics.Collections, System.IOUtils;'#13#10 +
    'class function TRuleCatalog.FindJsonFile: string;'#13#10 +
    'var'#13#10 +
    '  // Cands wird im outer-body erstellt; AddRoots (nested) liest es vorher.'#13#10 +
    '  Cands : TList<string>;'#13#10 +
    ''#13#10 +
    '  procedure AddRoots(const BaseDir: string);'#13#10 +
    '  var'#13#10 +
    '    Dir, Parent : string;'#13#10 +
    '    i           : Integer;'#13#10 +
    '  begin'#13#10 +
    '    if BaseDir = '''' then Exit;'#13#10 +
    '    Dir := BaseDir;'#13#10 +
    '    for i := 0 to 8 do'#13#10 +
    '    begin'#13#10 +
    '      Cands.Add(Dir);'#13#10 +
    '      Parent := Dir + ''..'';'#13#10 +
    '      if SameText(Parent, Dir) then Break;'#13#10 +
    '      Dir := Parent;'#13#10 +
    '    end;'#13#10 +
    '  end;'#13#10 +
    ''#13#10 +
    '  function ModuleDir: string;'#13#10 +
    '  begin'#13#10 +
    '    Result := '''';'#13#10 +
    '  end;'#13#10 +
    'var'#13#10 +
    '  C : string;'#13#10 +
    'begin'#13#10 +
    '  Cands := TList<string>.Create;'#13#10 +
    '  try'#13#10 +
    '    AddRoots(''a'');'#13#10 +
    '    C := ModuleDir;'#13#10 +
    '    if C <> '''' then Cands.Add(C);'#13#10 +
    '    Result := '''';'#13#10 +
    '  finally'#13#10 +
    '    Cands.Free;'#13#10 +
    '  end;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
    'outer-var nur in nested routine gelesen, im outer-body erzeugt - kein UninitVar');
  finally L.Free; end;
end;

procedure TTestUninitVar.OuterVarUninitDespiteNestedRoutine_StillFlagged;
// TP-Gegenkontrolle: die Closure-Erkennung darf NUR greifen wenn die Variable
// wirklich in der nested routine vorkommt. 'Total' wird nie geschrieben und im
// OUTER-Body gelesen (nicht in Helper) -> bleibt ein echter UninitVar-Bug,
// auch wenn die Methode eine nested routine enthaelt.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'function F: Integer;'#13#10 +
    'var'#13#10 +
    '  Total: Integer;'#13#10 +
    '  procedure Helper;'#13#10 +
    '  begin'#13#10 +
    '    WriteLn(''hi'');'#13#10 +
    '  end;'#13#10 +
    'begin'#13#10 +
    '  Helper;'#13#10 +
    '  Result := Total;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.IsTrue(CountKind(L, fkUninitVar) >= 1,
    'Total nie geschrieben, im outer-body gelesen - bleibt UninitVar trotz nested routine');
  finally L.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUninitVar);

end.
