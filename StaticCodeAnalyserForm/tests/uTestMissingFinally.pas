unit uTestMissingFinally;

// Tests fuer TMissingFinallyDetector. Pattern: Object .Create + try/except
// ABER kein try/finally rund um den Free.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMissingFinally = class
  public
    [Test] procedure CreateWithoutTryFinally_Reported;
    [Test] procedure CreateWithTryFinally_NotReported;
    [Test] procedure NoCreate_NotReported;
    [Test] procedure Finding_KindAndSeverity;
    // --- Welle 2 strukturell 2026-07-18 (Konsistenz-Ports aus uLeakDetector2) ---
    // finally-Region-by-Source: nested try/except vor dem finally -> AST-Mis-Attach
    [Test] procedure NestedTryExceptBeforeFinally_NoFinding;
    // IsOwnerParamCreate: Create(Self) = owner-managed
    [Test] procedure OwnerParamCreate_NoFinding;
    // TP-Gegenprobe: Create(nil) = caller owns -> Befund bleibt
    [Test] procedure CreateNilOwnerNoFinally_StillReported;
    // --- Auto-Runde 2026-07-19: Source-Anker fuer FreeInFinallyRegionBySource ---
    // Direkt-Tests gegen die Routine (manuelle ASTs simulieren den Parser-
    // Mis-Attach; der FindingsOf-Harness kann das nicht scharf).
    [Test] procedure SourceGuard_FreeInOuterFinally_MisAttach_True;
    [Test] procedure SourceGuard_ForLoopFreeThenVarFree_True;
    [Test] procedure SourceGuard_FreeOutsideFinally_False;   // TP-Gegenprobe
    // --- A2 (Triage 2026-07-24): with-Free-Idiom (bare Free ohne Receiver) ---
    [Test] procedure WithDoTryFinallyBareFree_NotReported;
    [Test] procedure WithDoBareFreeNoTry_StillReported;      // TP-Gegenprobe
    [Test] procedure SourceGuard_WithBareFree_SingleWith_True;
    [Test] procedure SourceGuard_BareFree_TwoWiths_False;    // TP-Gegenprobe
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uAstNode, uLeakDetector2,
  uTestFindingHelper;

procedure TTestMissingFinally.CreateWithoutTryFinally_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  try'#13#10 +
  '    L.Add(''x'');'#13#10 +
  '  except'#13#10 +
  '    Log(''oops'');'#13#10 +
  '  end;'#13#10 +
  '  L.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMissingFinally) >= 1);
  finally F.Free; end;
end;

procedure TTestMissingFinally.CreateWithTryFinally_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  try'#13#10 +
  '    L.Add(''x'');'#13#10 +
  '  finally'#13#10 +
  '    L.Free;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingFinally));
  finally F.Free; end;
end;

procedure TTestMissingFinally.NoCreate_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  WriteLn(''nothing to clean up'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingFinally));
  finally F.Free; end;
end;

procedure TTestMissingFinally.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  try L.Add(''x''); except Log(''oops''); end;'#13#10 +
  '  L.Free;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkMissingFinally then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkMissingFinally finding expected');
    Assert.AreEqual(fkMissingFinally, Hit.Kind);
  finally F.Free; end;
end;

procedure TTestMissingFinally.NestedTryExceptBeforeFinally_NoFinding;
// Welle 2 (finally-Region-by-Source Port, 2026-07-18): korrektes aeusseres
// try/finally mit SL.Free im finally, NESTED try/except im try-Body davor.
// BEHAVIOR-LOCK: dieser saubere Fall darf NIE gemeldet werden. HINWEIS: der
// neue Source-Guard ist im In-Memory-Testpfad (FindingsOf, Datei nicht auf
// Platte) ein No-Op; dieser Test wird bereits ueber AST-FreeInFin=True gruen.
// Die eigentliche Wirkung des finally-Region-Ports (AST-Mis-Attach bei
// {$IFDEF}/'F:=nil;try'/tief-verschachtelt) ist NUR per Korpus-A/B beweisbar
// (Real-Faelle CnObjInspectorCommentFrm/CnFeedWizard/CnSrcEditorBlockTools).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var SL: TStringList;'#13#10 +
  'begin'#13#10 +
  '  SL := TStringList.Create;'#13#10 +
  '  try'#13#10 +
  '    try'#13#10 +
  '      SL.Add(''x'');'#13#10 +
  '    except'#13#10 +
  '      Log(''inner'');'#13#10 +
  '    end;'#13#10 +
  '  finally'#13#10 +
  '    SL.Free;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingFinally),
    'SL.Free liegt quell-basiert im aeusseren finally -> kein MissingFinally');
  finally F.Free; end;
end;

procedure TTestMissingFinally.OwnerParamCreate_NoFinding;
// Welle 2 (IsOwnerParamCreate-Port): TTimer.Create(Self) uebergibt Ownership an
// den Owner (TComponent-Konvention) - selbst ein manueller Free ohne try/finally
// ist kein Leak-Risiko (Owner gibt bei Exception frei). Konsistent mit
// uLeakDetector2 Pfad 1.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.InitUi;'#13#10 +
  'var tmr: TTimer;'#13#10 +
  'begin'#13#10 +
  '  tmr := TTimer.Create(Self);'#13#10 +
  '  tmr.Enabled := True;'#13#10 +
  '  tmr.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingFinally),
    'Create(Self) = owner-managed -> kein MissingFinally');
  finally F.Free; end;
end;

procedure TTestMissingFinally.CreateNilOwnerNoFinally_StillReported;
// TP-Gegenprobe zum owner-param-Gate: Create(nil) hat KEINEN Owner -> der
// Aufrufer besitzt das Objekt; Create+Free ohne try/finally bleibt ein Befund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.LoadDB;'#13#10 +
  'var q: TSQLQuery;'#13#10 +
  'begin'#13#10 +
  '  q := TSQLQuery.Create(nil);'#13#10 +
  '  q.Open;'#13#10 +
  '  q.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMissingFinally) >= 1,
    'Create(nil) ohne try/finally -> Befund bleibt (owner-param-Gate greift nicht)');
  finally F.Free; end;
end;

procedure TTestMissingFinally.SourceGuard_FreeInOuterFinally_MisAttach_True;
// Auto-Runde 2026-07-19: Mis-Attach simuliert - KEIN nkFinallyBlock im Subtree
// (der alte AST-Anker liefe leer = No-Op des 4ae5e7a-Ports), aber die QUELLE
// hat 'finally' + 'sl.free' -> der neue Source-Anker liefert True.
// Geerdet: CnObjInspectorCommentFrm:1192 / CnFeedWizard:1020.
var
  M, Blk : TAstNode;
  Stripped : TArray<string>;
begin
  M := TAstNode.Create(nkMethod, 'foo', 1, 1);
  try
    Blk := M.Add(nkBlock, 'begin', 2, 1);
    Blk.Add(nkAssign, 'sl', 3, 1).TypeRef := 'tstringlist.create';
    Blk.Add(nkCall, 'sl.free', 7, 1);   // mis-attachter Free als Sibling
    Stripped := TArray<string>.Create(
      'procedure foo;',                  // 1
      'begin',                           // 2
      '  sl := tstringlist.create;',     // 3
      '  try',                           // 4
      '    sl.savetofile(x);',           // 5
      '  finally',                       // 6
      '    sl.free;',                    // 7
      '  end; end;');                    // 8 (max Subtree-Line=7 -> Region geklammert)
    Assert.IsTrue(
      TLeakDetector2.FreeInFinallyRegionBySource(M, Stripped, 'sl'),
      'SL.Free quell-basiert im finally trotz fehlendem nkFinallyBlock');
  finally
    M.Free;
  end;
end;

procedure TTestMissingFinally.SourceGuard_ForLoopFreeThenVarFree_True;
// CnSrcEditorBlockTools-Muster: for-Loop-Free der ITEMS im finally, dann
// List.Free ebenfalls im finally - beide in derselben Source-Region.
var
  M, Blk : TAstNode;
  Stripped : TArray<string>;
begin
  M := TAstNode.Create(nkMethod, 'bar', 1, 1);
  try
    Blk := M.Add(nkBlock, 'begin', 2, 1);
    Blk.Add(nkAssign, 'list', 3, 1).TypeRef := 'tlist.create';
    Blk.Add(nkCall, 'list.free', 8, 1);
    Stripped := TArray<string>.Create(
      'procedure bar;',                                   // 1
      'begin',                                            // 2
      '  list := tlist.create;',                          // 3
      '  try',                                            // 4
      '    x;',                                           // 5
      '  finally',                                        // 6
      '    for i := 0 to n do tholder(list[i]).free;',    // 7
      '    list.free; end; end;');                        // 8
    Assert.IsTrue(
      TLeakDetector2.FreeInFinallyRegionBySource(M, Stripped, 'list'),
      'List.Free im finally trotz vorangehendem Item-Free');
  finally
    M.Free;
  end;
end;

procedure TTestMissingFinally.SourceGuard_FreeOutsideFinally_False;
// TP-Gegenprobe (uDOMVisitor TempSL): die Methode HAT ein finally, das aber
// eine ANDERE Var behandelt; TempSL.Free liegt AUSSERHALB der Region ->
// der Guard darf NICHT greifen (Fund bleibt).
var
  M, Blk : TAstNode;
  Stripped : TArray<string>;
begin
  M := TAstNode.Create(nkMethod, 'baz', 1, 1);
  try
    Blk := M.Add(nkBlock, 'begin', 2, 1);
    Blk.Add(nkAssign, 'tempsl', 3, 1).TypeRef := 'tstringlist.create';
    Blk.Add(nkCall, 'tempsl.free', 9, 1);
    Stripped := TArray<string>.Create(
      'procedure baz;',                      // 1
      'begin',                               // 2
      '  tempsl := tstringlist.create;',     // 3
      '  if c then',                         // 4
      '    try foo;',                        // 5
      '    finally',                         // 6
      '      tempmsg := nil;',               // 7
      '    end;',                            // 8
      '  tempsl.free; end;');                // 9
    Assert.IsFalse(
      TLeakDetector2.FreeInFinallyRegionBySource(M, Stripped, 'tempsl'),
      'TempSL.Free ausserhalb der finally-Region -> TP bleibt');
  finally
    M.Free;
  end;
end;

procedure TTestMissingFinally.WithDoTryFinallyBareFree_NotReported;
// A2: klassisches Dialog-Idiom - der Free steht OHNE Receiver im finally des
// with-Bodys. BEHAVIOR-LOCK: die Produktion war fuer das reine Idiom schon
// vor A2 still (CLI-Probe 2026-07-25); A2 haertet die dahinterliegenden
// Mechanismen (SearchFree-WFin-Stack + bare-Free-Source-Gate) fuer die
// Varianten, in denen die Rettung NICHT greift (Mis-Attach, {$IFDEF}).
// FindingsOfFile: Quelle liegt auf Platte, damit laeuft der Source-Guard.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  with L do'#13#10 +
  '  try'#13#10 +
  '    Add(''x'');'#13#10 +
  '  finally'#13#10 +
  '    Free;'#13#10 +
  '  end;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingFinally),
      'bare Free im with-finally ist geschuetzt -> kein MissingFinally');
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'auch kein Leak-/Free-ausserhalb-finally-Befund fuer L');
  finally F.Free; end;
end;

procedure TTestMissingFinally.WithDoBareFreeNoTry_StillReported;
// TP-Gegenprobe: with-Body OHNE try - der bare Free schuetzt nicht vor
// Exceptions zwischen Create und Free -> Befund bleibt. Weder das AST-Gate
// (kein nkFinallyBlock) noch das Source-Gate (verlangt do-try-Idiom +
// finally-Region) duerfen greifen.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  with L do'#13#10 +
  '  begin'#13#10 +
  '    Add(''x'');'#13#10 +
  '    Free;'#13#10 +
  '  end;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkMissingFinally) >= 1,
      'with-Body ohne try: bare Free ungeschuetzt -> MissingFinally bleibt');
  finally F.Free; end;
end;

procedure TTestMissingFinally.SourceGuard_WithBareFree_SingleWith_True;
// A2-Source-Guard direkt (Mis-Attach simuliert: kein nkFinallyBlock im
// Subtree): genau EIN 'with dlg do' + 'try'-Body -> bare 'free' in der
// finally-Region NACH der with-Zeile zaehlt als dlg-Free.
var
  M, Blk : TAstNode;
  Stripped : TArray<string>;
begin
  M := TAstNode.Create(nkMethod, 'foo', 1, 1);
  try
    Blk := M.Add(nkBlock, 'begin', 2, 1);
    Blk.Add(nkAssign, 'dlg', 3, 1).TypeRef := 'topendialog.create';
    Blk.Add(nkCall, 'execute', 8, 1);   // Subtree-Spanne bis Zeile 8
    Stripped := TArray<string>.Create(
      'procedure foo;',                        // 1
      'begin',                                 // 2
      '  dlg := topendialog.create(nil);',     // 3
      '  with dlg do',                         // 4
      '  try',                                 // 5
      '    execute;',                          // 6
      '  finally',                             // 7
      '    free; end; end;');                  // 8
    Assert.IsTrue(
      TLeakDetector2.FreeInFinallyRegionBySource(M, Stripped, 'dlg'),
      'bare Free unter single-with-do-try zaehlt als dlg.Free');
  finally
    M.Free;
  end;
end;

procedure TTestMissingFinally.SourceGuard_BareFree_TwoWiths_False;
// Gegenprobe: ZWEI with-Statements -> Gate aus. Der bare Free waere nicht
// mehr eindeutig zuordenbar (koennte das andere with-Objekt oder Self
// meinen) -> kein Suppress-Beweis, Fund bleibt.
var
  M, Blk : TAstNode;
  Stripped : TArray<string>;
begin
  M := TAstNode.Create(nkMethod, 'foo', 1, 1);
  try
    Blk := M.Add(nkBlock, 'begin', 2, 1);
    Blk.Add(nkAssign, 'dlg', 3, 1).TypeRef := 'topendialog.create';
    Blk.Add(nkCall, 'execute', 10, 1);
    Stripped := TArray<string>.Create(
      'procedure foo;',                        // 1
      'begin',                                 // 2
      '  dlg := topendialog.create(nil);',     // 3
      '  with dlg do',                         // 4
      '  try',                                 // 5
      '    execute;',                          // 6
      '  finally',                             // 7
      '    free;',                             // 8
      '  end;',                                // 9
      '  with other do bar; end;');            // 10
    Assert.IsFalse(
      TLeakDetector2.FreeInFinallyRegionBySource(M, Stripped, 'dlg'),
      'zwei withs -> bare-Free-Gate aus, kein Suppress-Beweis');
  finally
    M.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMissingFinally);

end.
