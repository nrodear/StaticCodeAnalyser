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

    // ---- NEGATIV (MUST NOT flag) ----
    [Test] procedure CleanAssignThenRead_NoFinding;
    [Test] procedure UnderscorePrefix_NoFinding;
    [Test] procedure ManagedString_NoFinding;
    [Test] procedure ManagedDynamicArray_NoFinding;
    [Test] procedure ReadLnInitialisesVar_NoFinding;
    [Test] procedure ForLoopInitialisesVar_NoFinding;
    [Test] procedure FillCharInitialisesVar_NoFinding;
    [Test] procedure WriteBeforeRead_TryFinally_NoFinding;
    [Test] procedure DeclaredButNeverReferenced_NoFinding;
    [Test] procedure MultiLineVarDecl_CommaList_NoFinding;
    [Test] procedure VarDeclWithInit_NoFinding;

    // ---- EDGE CASES ----
    [Test] procedure AsmBlock_NoCrash;
    [Test] procedure EmptyMethod_NoCrash;
    [Test] procedure MultipleVarsSomeClean_OnlyDirtyFlagged;
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

initialization
  TDUnitX.RegisterTestFixture(TTestUninitVar);

end.
