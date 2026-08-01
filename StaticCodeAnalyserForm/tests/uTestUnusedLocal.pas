unit uTestUnusedLocal;

// Tests fuer den TUnusedLocalDetector (fkUnusedLocalVar).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestUnusedLocal = class
  public
    // ---- Positive ---------------------------------------------------------
    [Test] procedure Local_DeclaredNeverUsed_Reported;
    [Test] procedure Local_TwoUnusedVars_BothReported;
    [Test] procedure Local_MultipleHitsInSameMethod_AllReported;

    // ---- Negative ---------------------------------------------------------
    [Test] procedure Local_UsedAsAssignTarget_NoFinding;
    [Test] procedure Local_UsedInExpression_NoFinding;
    [Test] procedure Local_UnderscorePrefix_Skipped;
    [Test] procedure Local_UsedInCondition_NoFinding;

    // ---- Edge -------------------------------------------------------------
    [Test] procedure Local_NameAsSubstring_DoesNotCount;

    // ---- Quelltext-Rueckfall (30%-Audit 2026-07-31) ------------------------
    [Test] procedure Local_UsedOnlyInNestedRoutine_NoFinding;
    [Test] procedure Local_UsedAfterNestedRoutine_NoFinding;
    [Test] procedure Local_ProceduralTypeParamName_NoFinding;
    [Test] procedure Local_UsedInAsmBlock_NoFinding;
    // Waechter: der Rueckfall darf den Kern der Regel nicht mitnehmen
    [Test] procedure Local_UnusedInRoutineWithNested_StillReported;
    [Test] procedure Local_NameOnlyInComment_StillReported;
    [Test] procedure Local_NameOnlyInStringLiteral_KnownGap;

    // ---- Finding-Inhalt ---------------------------------------------------
    [Test] procedure Local_Finding_KindAndSeverity;
    [Test] procedure Local_Finding_MissingVarMentionsVarName;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestUnusedLocal.Local_DeclaredNeverUsed_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin Bar; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedLocalVar));
  finally F.Free; end;
end;

procedure TTestUnusedLocal.Local_TwoUnusedVars_BothReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x, y: Integer;'#13#10 +
  'begin Bar; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkUnusedLocalVar));
  finally F.Free; end;
end;

procedure TTestUnusedLocal.Local_MultipleHitsInSameMethod_AllReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var a, b, c: Integer;'#13#10 +
  'begin Bar; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(3, TFindingHelper.Count(F, fkUnusedLocalVar));
  finally F.Free; end;
end;

procedure TTestUnusedLocal.Local_UsedAsAssignTarget_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin x := 42; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedLocalVar));
  finally F.Free; end;
end;

procedure TTestUnusedLocal.Local_UsedInExpression_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin Bar(x); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedLocalVar));
  finally F.Free; end;
end;

procedure TTestUnusedLocal.Local_UnderscorePrefix_Skipped;
// `_var` ist Konvention fuer "intentionally unused".
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var _unused: Integer;'#13#10 +
  'begin Bar; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedLocalVar));
  finally F.Free; end;
end;

procedure TTestUnusedLocal.Local_UsedInCondition_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin if x > 0 then Bar; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedLocalVar));
  finally F.Free; end;
end;

procedure TTestUnusedLocal.Local_NameAsSubstring_DoesNotCount;
// `x` als Substring von `xLength` darf NICHT als Referenz zaehlen
// (Wortgrenze ist Pflicht).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const xLength: Integer);'#13#10 +
  'var x: Integer;'#13#10 +
  'begin Bar(xLength); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedLocalVar),
    'x ist ungenutzt; xLength ist Parameter und matched nicht als Wort');
  finally F.Free; end;
end;

procedure TTestUnusedLocal.Local_Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var orphan: Integer;'#13#10 +
  'begin Bar; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkUnusedLocalVar then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkUnusedLocalVar finding expected');
    Assert.AreEqual(fkUnusedLocalVar, Hit.Kind);
    Assert.AreEqual(lsHint, Hit.Severity);
  finally F.Free; end;
end;

procedure TTestUnusedLocal.Local_Finding_MissingVarMentionsVarName;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var orphan: Integer;'#13#10 +
  'begin Bar; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkUnusedLocalVar then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit);
    Assert.Contains(Hit.MissingVar, 'orphan');
  finally F.Free; end;
end;

// ===========================================================================
// Quelltext-Rueckfall (30%-Real-World-Audit 2026-07-31: 62 % FP).
// ALLE Fixtures hier laufen ueber FindingsOfFile - der Rueckfall braucht die
// Quellzeilen. Mit FindingsOf waeren sie vakuum-gruen und wuerden nichts
// beweisen (Lehre aus der SCA096-Runde).
// ===========================================================================

procedure TTestUnusedLocal.Local_UsedOnlyInNestedRoutine_NoFinding;
// uParser2 verwirft nested routines aus dem AST (nur nkNestedRange bleibt).
// Outer locals sind in nested bodies aber SICHTBAR - die Nutzung zaehlt.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var w: Integer;'#13#10 +
  '  procedure SetPoly;'#13#10 +
  '  begin'#13#10 +
  '    w := 42;'#13#10 +
  '  end;'#13#10 +
  'begin'#13#10 +
  '  SetPoly;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedLocalVar),
    'Nutzung in der verschachtelten Routine zaehlt');
  finally F.Free; end;
end;

procedure TTestUnusedLocal.Local_UsedAfterNestedRoutine_NoFinding;
// Korpus-Beleg jvcl JvMarkupLabel.pas:222: 'AColor, FColor: TColor;' plus
// nested function, die Nutzung steht im Hauptrumpf DAHINTER. Der Parser
// desynchronisiert an der nested routine und verliert den Rest des Rumpfes.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var AColor, FColor: Integer;'#13#10 +
  '  function Helper(var Col: Integer): Boolean;'#13#10 +
  '  begin'#13#10 +
  '    Col := 1;'#13#10 +
  '    Result := True;'#13#10 +
  '  end;'#13#10 +
  'begin'#13#10 +
  '  if Helper(AColor) then FColor := AColor;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedLocalVar),
    'Nutzung im Hauptrumpf hinter der nested routine zaehlt');
  finally F.Free; end;
end;

procedure TTestUnusedLocal.Local_ProceduralTypeParamName_NoFinding;
// Korpus-Beleg issrc Shared.CommonFunc.pas:757: 'lpBuffer' ist kein Local,
// sondern Parametername im prozeduralen Typ der Variablen davor. Erkennbar
// an der offenen Klammer vor der Zeile.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var'#13#10 +
  '  GetTempPathFunc: function('#13#10 +
  '    nBufferLength: Cardinal;'#13#10 +
  '    lpBuffer: PChar): Cardinal; stdcall;'#13#10 +
  'begin'#13#10 +
  '  GetTempPathFunc := nil;'#13#10 +
  '  if Assigned(GetTempPathFunc) then Bar;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedLocalVar),
    'Parametername eines prozeduralen Typs ist keine lokale Variable');
  finally F.Free; end;
end;

procedure TTestUnusedLocal.Local_UsedInAsmBlock_NoFinding;
// asm-Bloecke zerlegt der Parser nicht - die Nutzung steht nur im Quelltext.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var sd0: Integer;'#13#10 +
  'begin'#13#10 +
  '  asm'#13#10 +
  '    mov eax, sd0'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedLocalVar),
    'Referenz im asm-Block zaehlt als Nutzung');
  finally F.Free; end;
end;

procedure TTestUnusedLocal.Local_UnusedInRoutineWithNested_StillReported;
// WAECHTER: eine Routine MIT nested routine, in der die Variable wirklich
// nirgends vorkommt - der Rueckfall darf den Kern der Regel nicht abschalten.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var deadVar: Integer;'#13#10 +
  '  procedure SetPoly;'#13#10 +
  '  begin'#13#10 +
  '    Beep;'#13#10 +
  '  end;'#13#10 +
  'begin'#13#10 +
  '  SetPoly;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedLocalVar),
    'Echt unbenutzte Variable bleibt Fund, auch neben einer nested routine');
  finally F.Free; end;
end;

procedure TTestUnusedLocal.Local_NameOnlyInComment_StillReported;
// PROJEKTREGEL: Kommentare zaehlen NIE als Code-Nutzung. Der Rueckfall
// arbeitet deshalb auf der gestrippten Fassung.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var ghostVar: Integer;'#13#10 +
  'begin'#13#10 +
  '  // ghostVar wird hier absichtlich nur erwaehnt'#13#10 +
  '  Bar;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedLocalVar),
    'Erwaehnung im Kommentar ist keine Nutzung');
  finally F.Free; end;
end;

procedure TTestUnusedLocal.Local_NameOnlyInStringLiteral_KnownGap;
// DOKUMENTIERTE LUECKE, nicht das gewuenschte Verhalten.
//
// Sachlich waere ein Name, der nur in einem String-Literal steht, KEINE
// Nutzung - der Fund sollte also stehen bleiben. Er tut es nicht, und die
// Ursache liegt VOR dem neuen Quelltext-Rueckfall: CollectAllTokens haengt
// Name und TypeRef jedes AST-Knotens aneinander, und der Parser legt einen
// Aufruf samt Argumenten als EINEN String ab
// ('Log(''ghostVar konnte nicht geladen werden'')'). Der Literalinhalt
// steckt damit im Body-Text, RefCount wird 2, und der Detektor meldet schon
// deshalb nichts - unabhaengig von allem, was danach kommt.
//
// Der Quelltext-Rueckfall (der Literale korrekt blankt) kann daran nichts
// aendern: er darf nur UNTERDRUECKEN. Einen Fund, den der AST-Scan bereits
// verworfen hat, kann er nicht wiederbeleben.
//
// Der Test haelt den Ist-Zustand fest, damit die Luecke nicht als
// Neben-Effekt dieser Runde missverstanden wird. Behebung gehoert in den
// AST-Scan (Argumente vom Callee-Namen trennen oder Literale blanken) und
// ERZEUGT FUNDE - also eigenes Inkrement mit eigenem A/B und ADD-Sampling.
// Die Gegenprobe steht direkt darueber: im KOMMENTAR erwaehnt zaehlt der
// Name korrekt nicht, dort greift der Rueckfall wie vorgesehen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var ghostVar: Integer;'#13#10 +
  'begin'#13#10 +
  '  Log(''ghostVar konnte nicht geladen werden'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedLocalVar),
    'IST-Zustand: der AST-Token-Scan zaehlt Literalinhalte mit (Luecke, ' +
    'siehe Kommentar) - der Quelltext-Rueckfall kann das nicht heilen');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUnusedLocal);

end.
