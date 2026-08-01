unit uTestCommentedOutCode;

// Tests fuer TCommentedOutCodeDetector (Heuristik auf Pascal-Marker
// in //- und {}-Kommentaren).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCommentedOutCode = class
  public
    [Test] procedure ProseComment_NoFinding;
    [Test] procedure CodeLineComment_Reported;
    [Test] procedure CodeBlockComment_Reported;
    [Test] procedure SinglePascalToken_NoFinding;
    [Test] procedure ProseWithWeakKeywords_NoFinding;
    [Test] procedure CompilerDirective_NoFinding;
    [Test] procedure CommentedOutCode_KindAndSeverity;
    // ---- Adapter-Doku-Header (30%-Audit 2026-07-31) -----------------------
    [Test] procedure AdapterDocHeader_NotReported;
    [Test] procedure CommentedOutOverload_StillReported;
    [Test] procedure HeadOfCommentedBlock_StillReported;
    [Test] procedure ShortNameSubstring_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestCommentedOutCode.ProseComment_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  '// FreeAndNil is safer than Free for fields'#13#10 +
  '// see DocWiki for details'#13#10 +
  'procedure Foo; begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCommentedOutCode));
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.CodeLineComment_Reported;
// Kommentar mit `:=` und trailing `;` -> 2 Marker -> Treffer.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  // X := 42;'#13#10 +
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkCommentedOutCode) >= 1);
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.CodeBlockComment_Reported;
// `{...}` block comment mit `begin`/`end` plus `;` -> 3+ Marker.
const SRC =
  'unit t; implementation'#13#10 +
  '{ if Active then begin DoStuff; end; }'#13#10 +
  'procedure Foo; begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkCommentedOutCode) >= 1);
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.SinglePascalToken_NoFinding;
// Nur ein Marker (trailing `;`) - Schwelle = 2.
const SRC =
  'unit t; implementation'#13#10 +
  '// use FreeAndNil instead of Free;'#13#10 +
  'procedure Foo; begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCommentedOutCode));
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.ProseWithWeakKeywords_NoFinding;
// FP-Fix (Real-World 2026-06-28): englische Prosa mit prosa-haeufigen Keywords
// (if/then/for/while/end) traf frueher die 2-Marker-Schwelle und wurde als
// Code geflaggt. Ohne STARKEN Pascal-Marker (:=, trailing ;, begin/procedure/
// function) jetzt kein Treffer. Kommentar steht isoliert zwischen Code-Zeilen,
// damit nicht der Doc-Block-Guard (angrenzende //) das Ergebnis verfaelscht.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  DoA;'#13#10 +
  '  // if the value is nil then return for each item while at the end'#13#10 +
  '  DoB;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCommentedOutCode),
    'Prosa mit if/then/for/while/end ohne starken Marker ist kein Code');
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.CompilerDirective_NoFinding;
// `{$...}` ist Compiler-Direktive, kein Kommentar - kein Treffer.
const SRC =
  'unit t;'#13#10 +
  '{$IFDEF DEBUG}'#13#10 +
  '{$DEFINE WITH_LOGGING}'#13#10 +
  '{$ENDIF}'#13#10 +
  'implementation'#13#10 +
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCommentedOutCode));
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.CommentedOutCode_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  '// X := 42; if X then begin DoStuff; end;'#13#10 +
  'procedure Foo; begin DoStuff; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkCommentedOutCode then
      begin
        Assert.AreEqual<TFindingKind>(fkCommentedOutCode, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,            Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkCommentedOutCode finding');
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.AdapterDocHeader_NotReported;
// JvInterpreter-Idiom: der Kommentar dokumentiert die ORIGINAL-Signatur
// ueber dem Adapter, der sie umschliesst. Korpus-Beleg jvcl
// JvInterpreter_RegAuto.pas:54. Dominante FP-Klasse des Audits (8/24),
// gemessen 4.515 der 20.354 Funde.
const SRC =
  'unit t; implementation'#13#10 +
  '{ procedure Save; }'#13#10 +
  'procedure TRegAuto_Save(var Value: Variant);'#13#10 +
  'begin'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCommentedOutCode),
    'Signatur-Doku ueber dem Adapter ist kein auskommentierter Code');
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.CommentedOutOverload_StillReported;
// WAECHTER: GLEICHER Name heisst auskommentierte Ueberladung, nicht Doku.
// Im Korpus 42 solcher Faelle - die bleiben Funde.
const SRC =
  'unit t; implementation'#13#10 +
  '//procedure init(random: JSecureRandom); cdecl;'#13#10 +
  'procedure init(keysize: Integer); cdecl;'#13#10 +
  'begin'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkCommentedOutCode) >= 1,
    'Auskommentierte Ueberladung bleibt ein Fund');
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.HeadOfCommentedBlock_StillReported;
// WAECHTER, der teuerste: die ERSTE Zeile eines mehrzeilig
// auskommentierten Blocks sieht aus wie ein Doku-Header. Sie darf nicht
// wegfallen - sonst verliert die Regel den Kopf jedes stillgelegten
// Routinen-Blocks. Schutz: der Kommentar muss auf DERSELBEN Zeile
// schliessen.
const SRC =
  'unit t; implementation'#13#10 +
  '{ procedure OldWorker;'#13#10 +
  '  begin'#13#10 +
  '    DoSomething;'#13#10 +
  '  end; }'#13#10 +
  'procedure TRegAuto_OldWorker(var Value: Variant);'#13#10 +
  'begin'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkCommentedOutCode) >= 1,
    'Kopf eines mehrzeilig auskommentierten Blocks bleibt ein Fund');
  finally F.Free; end;
end;

procedure TTestCommentedOutCode.ShortNameSubstring_StillReported;
// WAECHTER gegen den Zufallstreffer: ohne Unterstrich-Anker und
// Mindestlaenge matchte 'im' in 'ImmedBW' (cnwizards). Der Name im
// Kommentar muss AM UNTERSTRICH im Folgenamen stecken.
const SRC =
  'unit t; implementation'#13#10 +
  '//function im(DS: Integer): Boolean;'#13#10 +
  'function ImmedBW(DS: Integer): Boolean;'#13#10 +
  'begin'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkCommentedOutCode) >= 1,
    'Zufaellige Teilzeichenkette ist kein Adapter-Bezug');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCommentedOutCode);

end.
