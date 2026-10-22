unit uTestRdxParensFix;

// Editorhilfe SCA094 RedundantParentheses (uRdxParensFix): '((X))' -> '(X)'.
// Die Faelle auf Text laufen ohne Parser und ohne Detektor; die Rundlaeufe
// mit dem echten Detektor (Katalog-Beispiel, Aufruf mit Bezeichner) stehen
// hinter {$IFNDEF FPC} (ueber TRdxFixTable.FixFor). Nur Delphi
// (reDelphix.Test).
// Der Planer ist seit der Folgewelle G09-07 ohne Delphi-only-uses (den
// Adapter traegt uRdxFixTable); die Unit steht trotzdem nicht im
// FPC-Pruefstand (build.sh) - dessen Runner kennt die {$IFNDEF FPC}-
// Weichen nicht, sie sind heute ohne Wirkung.
// Prueft: Operator oder Schluesselwort davor, Leerraum, Literale, Aufruf
// mit Literal, und die Sperren - Aufruf/Cast mit Bezeichner, Struktur einer
// Konstante, Kette, Kommentar, verschobene Zeile.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxParensFix = class
  public
    [Test] procedure Sca094_AfterKeywordOrOperator;
    [Test] procedure Sca094_BlanksAndTabs;
    [Test] procedure Sca094_Literals;
    [Test] procedure Sca094_SecondOfTwo;
    [Test] procedure Sca094_TrailingComment_Helps;
    [Test] procedure Sca094_CallWithLiteral_Helps;
    [Test] procedure Sca094_CallWithIdent_NoHelp;
    [Test] procedure Sca094_Structure_NoHelp;
    [Test] procedure Sca094_Comparison_NoHelp;
    [Test] procedure Sca094_Chain_NoHelp;
    [Test] procedure Sca094_Comment_NoHelp;
    [Test] procedure Sca094_Moved_NoHelp;
    {$IFNDEF FPC}
    [Test] procedure Sca094_Detector_CatalogExample;
    [Test] procedure Sca094_Detector_CallWithIdent_NoHelp;
    {$ENDIF}
  end;

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uRuleCatalog, uRedundantParentheses,
  uTestRdxDetectorKit,   // TSeen, DetectSource, FixAllWith, AssertNoHelpWith
  {$ENDIF}
  uSCAConsts, uRdxBufferMath, uRdxCodeMap, uRdxParensFix,
  uRdxText,              // _() und die gemeinsamen Gruende (E29)
  uTestRdxTextKit;       // Join, Apply

// ---- Helfer ----

// Der Grund einer verschobenen Stelle, in der Sprache der Tests.
function Moved: string;
begin
  Result := MsgMovedSuffix(_(R_PAREN_MOVED));
end;

// Die Meldung des Detektors fuer die Spalte ACol.
function Msg(ACol: Integer): string;
begin
  Result := Format('Redundant double parentheses at column %d - drop the '
    + 'outer `(...)` around the simple expression.', [ACol]);
end;

// Die Hilfe fuer Zeile ALine mit der Meldung AMessage: neuer Text oder ''
// bei Ablehnung (AReason).
function Fix(const ASource: string; ALine: Integer; const AMessage: string;
  out AReason: string): string;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  E   : TRdxEdit;
begin
  Result := '';
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    if TRdxParensFix.DoubleParens(Map, ALine, AMessage, E, AReason) then
      Result := Apply(ASource, E);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Die Hilfe fuer eine Ein-Zeilen-Quelle; die Spalte ist die des ersten '((' .
function FixLine(const ALine: string; out AReason: string): string;
begin
  Result := Fix(ALine, 1, Msg(Pos('((', ALine)), AReason);
end;

procedure AssertFix(const AExpected, ALine: string);
var
  Reason : string;
begin
  Assert.AreEqual(AExpected, FixLine(ALine, Reason), Reason);
end;

procedure AssertNoFix(const ALine, AReason: string);
var
  Reason : string;
begin
  Assert.AreEqual('', FixLine(ALine, Reason), ALine);
  Assert.AreEqual(AReason, Reason, ALine);
end;

// ---- Auf Text ----

procedure TTestRdxParensFix.Sca094_AfterKeywordOrOperator;
begin
  AssertFix('if (Active) then Exit;', 'if ((Active)) then Exit;');
  AssertFix('while (Go) do Step;', 'while ((Go)) do Step;');
  AssertFix('X := not (Done);', 'X := not ((Done));');
  AssertFix('X := A and (B);', 'X := A and ((B));');
  AssertFix('X := Y + (Z);', 'X := Y + ((Z));');
  AssertFix('Result := (FCache);', 'Result := ((FCache));');
  AssertFix('if (Counter) > 0 then Exit;', 'if ((Counter)) > 0 then Exit;');
end;

procedure TTestRdxParensFix.Sca094_BlanksAndTabs;
begin
  AssertFix('Result := (Foo);', 'Result := (( Foo ));');
  AssertFix('Result := (Foo);', 'Result := ((' + #9 + 'Foo' + #9 + '));');
end;

procedure TTestRdxParensFix.Sca094_Literals;
begin
  AssertFix('Result := (42);', 'Result := ((42));');
  AssertFix('Result := ($FF);', 'Result := (( $FF ));');
  AssertFix('S := (''it''''s'');', 'S := ((''it''''s''));');
  // Ein ')' im String ist kein Ende des Paars.
  AssertFix('S := (''a))'');', 'S := ((''a))''));');
end;

procedure TTestRdxParensFix.Sca094_SecondOfTwo;
var
  Reason : string;
begin
  // Die Spalte der Meldung waehlt das zweite Paar; das erste bleibt.
  Assert.AreEqual('A := ((B)) + (C);',
    Fix('A := ((B)) + ((C));', 1, Msg(14), Reason), Reason);
end;

procedure TTestRdxParensFix.Sca094_TrailingComment_Helps;
begin
  AssertFix('X := (Y); // ((Z))', 'X := ((Y)); // ((Z))');
  AssertFix('X := (Y); { ((Z)) }', 'X := ((Y)); { ((Z)) }');
end;

procedure TTestRdxParensFix.Sca094_CallWithLiteral_Helps;
begin
  // Die aeussere Klammer ist hier die des Aufrufs; mit einem Literal gibt es
  // keinen Unterschied zwischen (1) und 1.
  AssertFix('Foo(1);', 'Foo((1));');
  AssertFix('Foo(''a'');', 'Foo((''a''));');
end;

// ---- Gegenproben ----

procedure TTestRdxParensFix.Sca094_CallWithIdent_NoHelp;
begin
  // '(X)' ist ein Ausdruck, 'X' eine Variable (var-Parameter, Overload,
  // Cast als Wert oder Variable).
  AssertNoFix('Foo((X));', _(R_PAREN_CALL));
  AssertNoFix('Y := TFoo((X));', _(R_PAREN_CALL));
  AssertNoFix('Y := Foo(A)((X));', _(R_PAREN_CALL));
  AssertNoFix('Y := A[1]((X));', _(R_PAREN_CALL));
end;

procedure TTestRdxParensFix.Sca094_Structure_NoHelp;
var
  Reason : string;
begin
  // Typisierte Array-/Record-Konstante: die Klammern sind Struktur.
  AssertNoFix('const A: array[0..0] of Integer = ((1));', _(R_PAREN_STRUCT));
  AssertNoFix('  (X: ((1)); Y: 2)', _(R_PAREN_STRUCT));
  Assert.AreEqual('', Fix('  ((1)), ((2))', 1, Msg(10), Reason));
  Assert.AreEqual(_(R_PAREN_STRUCT), Reason);
  AssertNoFix('  ((1)),', _(R_PAREN_LINESTART));
  // Dreifache Klammer: erst nach dem ersten Durchgang eindeutig.
  Assert.AreEqual('', Fix('Result := (((Y)));', 1, Msg(12), Reason));
  Assert.AreEqual(_(R_PAREN_STRUCT), Reason);
end;

procedure TTestRdxParensFix.Sca094_Comparison_NoHelp;
var
  Reason : string;
begin
  // Nach '=' kann es ein Vergleich oder eine Konstante sein - keine Hilfe.
  AssertNoFix('if X = ((Y)) then Exit;', _(R_PAREN_STRUCT));
  // Die Klammer um einen Vergleich meldet der Detektor nie; ein Fund an
  // einer Stelle mit Vergleich dahinter aendert die Bedeutung nicht.
  Assert.AreEqual('if (a = b) and (c) then Exit;',
    Fix('if (a = b) and ((c)) then Exit;', 1, Msg(16), Reason), Reason);
  // Eine Spalte auf dem Vergleich selbst ist kein '((X))'.
  Fix('if (a = b) and ((c)) then Exit;', 1, Msg(4), Reason);
  Assert.AreEqual(Moved, Reason);
end;

procedure TTestRdxParensFix.Sca094_Chain_NoHelp;
begin
  AssertNoFix('Result := ((X)).Y;', _(R_PAREN_CHAIN));
  AssertNoFix('Result := ((X))[0];', _(R_PAREN_CHAIN));
  AssertNoFix('Result := ((X))(1);', _(R_PAREN_CHAIN));
end;

procedure TTestRdxParensFix.Sca094_Comment_NoHelp;
var
  Reason : string;
begin
  // Ein Kommentar im Paar: der Detektor meldet es nicht, die Hilfe auch nicht.
  AssertNoFix('Result := (( {c} X ));', Moved);
  AssertNoFix('Result := (( X {c} ));', Moved);
  // Fund in einem Kommentar oder String: kein Code.
  Assert.AreEqual('', Fix('// X := ((Y));', 1, Msg(9), Reason));
  Assert.AreEqual(Moved, Reason);
  Assert.AreEqual('', Fix('S := ''((Y))'';', 1, Msg(7), Reason));
  Assert.AreEqual(Moved, Reason);
  // Zeile in einem Block-Kommentar.
  Assert.AreEqual('', Fix(Join(['{', 'X := ((Y));', '}']), 2, Msg(6), Reason));
  Assert.AreEqual(Moved, Reason);
end;

procedure TTestRdxParensFix.Sca094_Moved_NoHelp;
var
  Reason : string;
begin
  // Falsche Spalte, andere Zeile, fehlende Spalte, Zeile ausserhalb.
  Assert.AreEqual('', Fix('Result := ((X));', 1, Msg(3), Reason));
  Assert.AreEqual(Moved, Reason);
  Assert.AreEqual('', Fix('Result := (X);', 1, Msg(11), Reason));
  Assert.AreEqual(Moved, Reason);
  Assert.AreEqual('', Fix('Result := ((X + 1));', 1, Msg(11), Reason));
  Assert.AreEqual(Moved, Reason);
  Assert.AreEqual('', Fix('Result := ((X));', 1, 'Redundant', Reason));
  Assert.AreEqual(MsgNoColumn, Reason);
  Assert.AreEqual('', Fix('Result := ((X));', 5, Msg(11), Reason));
  Assert.AreEqual(Moved, Reason);
end;

{$IFNDEF FPC}

// ---- Mit dem echten Detektor ----

procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TRedundantParenthesesDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := DetectSource('rdx_s094_', ASource, AKind, RunDetector);
end;

function InFunction(const AText: string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation', '',
    'function F: Integer;', 'begin']) + #13#10 + AText + #13#10
    + Join(['end;', '', 'end.']);
end;

procedure TTestRdxParensFix.Sca094_Detector_CatalogExample;
var
  Meta : TRuleMeta;
  Bad  : string;
begin
  // Das Beispiel 'bad' (zwei Funde): '...' wird zu einer Anweisung; nach der
  // Hilfe meldet der Detektor nichts mehr, und die Klammern stehen einfach.
  Meta := TRuleCatalog.GetRuleCanonical(fkRedundantParentheses);
  Bad := StringReplace(CatalogText(Meta.BadExample), ' then ...',
    ' then Exit;', []);
  Assert.AreEqual<Integer>(2, Length(Detect(InFunction(Bad), fkRedundantParentheses)));
  Assert.AreEqual(
    InFunction('if (Active) then Exit;' + #13#10 + 'Result := (42);'),
    FixAllWith(InFunction(Bad), fkRedundantParentheses, Detect));
end;

procedure TTestRdxParensFix.Sca094_Detector_CallWithIdent_NoHelp;
begin
  // Der Detektor meldet auch 'Foo((X))' - die Hilfe lehnt es ab.
  AssertNoHelpWith(InFunction('Foo((X));'), fkRedundantParentheses,
    _(R_PAREN_CALL), Detect);
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxParensFix);

end.
