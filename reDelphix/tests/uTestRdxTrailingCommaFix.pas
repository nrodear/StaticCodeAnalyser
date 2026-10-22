unit uTestRdxTrailingCommaFix;

// Editorhilfe SCA068 TrailingCommaArgList (uRdxTrailingCommaFix): das
// ueberzaehlige Komma vor ')' faellt weg. Die Faelle auf Text laufen ohne
// Parser und ohne Detektor; die Rundlaeufe mit dem echten Detektor
// (Katalog-Beispiel, zwei Funde auf einer Zeile, fehlendes Argument)
// stehen samt Adapter in einer eigenen Fixture hinter {$IFNDEF FPC}
// (ueber TRdxFixTable.FixFor) und laufen nur in reDelphix.Test.
// Die Text-Fixture laeuft auch im FPC-Pruefstand (build.sh): der Planer
// ist seit der Folgewelle G09-07 ohne Delphi-only-uses (den Adapter traegt
// uRdxFixTable), und der Pruefstand blendet seit der Folgewelle B3 die
// {$IFNDEF FPC}-Teile aus.
// Prueft: Blank und Tab vor ')', verschachtelte und mehrzeilige Klammern,
// Set-Literal als letztes Argument, Fund in Kommentar und String, und die
// Sperren - fehlendes Argument, Komma in '[...]', keine oeffnende Klammer,
// verschobene Zeile.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxTrailingCommaFix = class
  public
    [Test] procedure Sca068_Basic;
    [Test] procedure Sca068_BlanksAndTabs;
    [Test] procedure Sca068_NestedAndCast;
    [Test] procedure Sca068_SecondOfTwo;
    [Test] procedure Sca068_StringAndComment_Helps;
    [Test] procedure Sca068_SetLiteralArgument_Helps;
    [Test] procedure Sca068_MultiLineList_Helps;
    [Test] procedure Sca068_MissingArgument_NoHelp;
    [Test] procedure Sca068_Bracket_NoHelp;
    [Test] procedure Sca068_NoOpener_NoHelp;
    [Test] procedure Sca068_InCommentOrString_NoHelp;
    [Test] procedure Sca068_Moved_NoHelp;
  end;

{$IFNDEF FPC}
  // Rundlaeufe mit dem ECHTEN Detektor und der Adapter (nur Delphi).
  [TestFixture]
  TTestRdxTrailingCommaFixDetector = class
  public
    [Test] procedure Sca068_Detector_CatalogExample;
    [Test] procedure Sca068_Detector_TwoOnOneLine;
    [Test] procedure Sca068_Detector_MissingArgument_NoHelp;
    [Test] procedure Sca068_Adapter_Outcome;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uTrailingCommaArgList,
  uRdxRecipeRunner, uRdxFixTable,
  uTestRdxDetectorKit,   // TSeen, CatalogText, DetectSource, FixAllWith
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxTrailingCommaFix,
  uRdxText,              // _() und die gemeinsamen Gruende (E29)
  uTestRdxTextKit;       // Join, Apply

// ---- Helfer ----

// Der Grund einer verschobenen Stelle, in der Sprache der Tests.
function Moved: string;
begin
  Result := MsgMovedSuffix(_(R_COMMA_MOVED));
end;

// Die Meldung des Detektors fuer die Spalte ACol.
function Msg(ACol: Integer): string;
begin
  Result := Format('Trailing comma in argument list at column %d - drop the '
    + 'comma or add the missing argument.', [ACol]);
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
    if TRdxTrailingCommaFix.DropComma(Map, ALine, AMessage, E, AReason) then
      Result := Apply(ASource, E);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Die Hilfe fuer eine Ein-Zeilen-Quelle; die Spalte ist die des LETZTEN
// Kommas der Zeile.
function FixLine(const ALine: string; out AReason: string): string;
begin
  Result := Fix(ALine, 1, Msg(LastDelimiter(',', ALine)), AReason);
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

procedure TTestRdxTrailingCommaFix.Sca068_Basic;
begin
  AssertFix('Foo(A, B);', 'Foo(A, B,);');
  AssertFix('DoStuff(Param1, Param2);', 'DoStuff(Param1, Param2,);');
  AssertFix('Foo(A);', 'Foo(A,);');
  AssertFix('  Foo(1, 2) ;', '  Foo(1, 2,) ;');
end;

procedure TTestRdxTrailingCommaFix.Sca068_BlanksAndTabs;
begin
  // Der Leerraum zwischen Komma und ')' faellt mit weg.
  AssertFix('WriteLn(''A'', ''B'');', 'WriteLn(''A'', ''B'', );');
  AssertFix('Foo(A, B);', 'Foo(A, B,   );');
  AssertFix('Foo(A, B);', 'Foo(A, B,' + #9 + ');');
  AssertFix('Foo(A, B );', 'Foo(A, B ,);');
end;

procedure TTestRdxTrailingCommaFix.Sca068_NestedAndCast;
begin
  AssertFix('Foo(Bar(1), B);', 'Foo(Bar(1), B,);');
  AssertFix('X := TFoo(Y);', 'X := TFoo(Y,);');
  AssertFix('Foo(Bar(1, 2));', 'Foo(Bar(1, 2,));');
  AssertFix('Foo(A[1], B);', 'Foo(A[1], B,);');
end;

procedure TTestRdxTrailingCommaFix.Sca068_SecondOfTwo;
var
  Reason : string;
begin
  // Die Spalte der Meldung waehlt das Komma; das andere bleibt.
  Assert.AreEqual('Foo(A,); Bar(B);',
    Fix('Foo(A,); Bar(B,);', 1, Msg(15), Reason), Reason);
  Assert.AreEqual('Foo(A); Bar(B,);',
    Fix('Foo(A,); Bar(B,);', 1, Msg(6), Reason), Reason);
end;

procedure TTestRdxTrailingCommaFix.Sca068_StringAndComment_Helps;
var
  Reason : string;
begin
  // ',)' im String oder Kommentar derselben Zeile ist kein Code und bleibt.
  AssertFix('WriteLn(''a,)'', B);', 'WriteLn(''a,)'', B,);');
  Assert.AreEqual('Foo(A); // B,)',
    Fix('Foo(A,); // B,)', 1, Msg(6), Reason), Reason);
  Assert.AreEqual('Foo(A); { B,) }',
    Fix('Foo(A,); { B,) }', 1, Msg(6), Reason), Reason);
end;

procedure TTestRdxTrailingCommaFix.Sca068_SetLiteralArgument_Helps;
begin
  // Die ')' schliesst den Aufruf, das Set-Literal davor bleibt unberuehrt.
  AssertFix('Foo([A, B]);', 'Foo([A, B],);');
  AssertFix('Foo(X, [A, B]);', 'Foo(X, [A, B],);');
end;

procedure TTestRdxTrailingCommaFix.Sca068_MultiLineList_Helps;
var
  Reason : string;
begin
  // Die oeffnende Klammer steht auf einer frueheren Zeile.
  Assert.AreEqual(Join(['Foo(', '  A,', '  B)']),
    Fix(Join(['Foo(', '  A,', '  B,)']), 3, Msg(4), Reason), Reason);
  Assert.AreEqual(Join(['Foo(', '  Bar(1),', '  B)']),
    Fix(Join(['Foo(', '  Bar(1),', '  B, )']), 3, Msg(4), Reason), Reason);
end;

// ---- Gegenproben ----

procedure TTestRdxTrailingCommaFix.Sca068_MissingArgument_NoHelp;
var
  Reason : string;
begin
  // Hier fehlt ein Argument, das Komma ist nicht ueberzaehlig.
  AssertNoFix('Foo(,);', _(R_COMMA_NOARG));
  Assert.AreEqual('', Fix('Foo(A,,);', 1, Msg(7), Reason));
  Assert.AreEqual(_(R_COMMA_NOARG), Reason);
  Assert.AreEqual('', Fix(Join(['Foo(', ',)']), 2, Msg(1), Reason));
  Assert.AreEqual(_(R_COMMA_NOARG), Reason);
end;

procedure TTestRdxTrailingCommaFix.Sca068_Bracket_NoHelp;
begin
  // Ein Komma, das eine Liste in '[...]' beschliesst: Set oder Array.
  AssertNoFix('X := [A, B,);', _(R_COMMA_BRACKET));
  AssertNoFix('X := Foo([A, B,);', _(R_COMMA_BRACKET));
end;

procedure TTestRdxTrailingCommaFix.Sca068_NoOpener_NoHelp;
var
  Reason : string;
begin
  AssertNoFix('A, B,);', _(R_COMMA_NO_OPEN));
  // Eine ')' davor schliesst ein anderes Paar, die oeffnende fehlt weiter.
  AssertNoFix('Foo(A), B,);', _(R_COMMA_NO_OPEN));
  // Eine '(' in einem Kommentar zaehlt nicht.
  Assert.AreEqual('', Fix(Join(['// Foo(', 'A, B,);']), 2, Msg(5), Reason));
  Assert.AreEqual(_(R_COMMA_NO_OPEN), Reason);
end;

procedure TTestRdxTrailingCommaFix.Sca068_InCommentOrString_NoHelp;
var
  Reason : string;
begin
  // Fund in einem Kommentar oder String: kein Code.
  Assert.AreEqual('', Fix('// Foo(A,);', 1, Msg(9), Reason));
  Assert.AreEqual(Moved, Reason);
  Assert.AreEqual('', Fix('S := ''Foo(A,)'';', 1, Msg(12), Reason));
  Assert.AreEqual(Moved, Reason);
  Assert.AreEqual('', Fix('(* Foo(A,) *)', 1, Msg(9), Reason));
  Assert.AreEqual(Moved, Reason);
  // Zeile in einem Block-Kommentar.
  Assert.AreEqual('', Fix(Join(['{', 'Foo(A,);', '}']), 2, Msg(6), Reason));
  Assert.AreEqual(Moved, Reason);
end;

procedure TTestRdxTrailingCommaFix.Sca068_Moved_NoHelp;
var
  Reason : string;
begin
  // Falsche Spalte, Argument statt ')' dahinter, Kommentar dazwischen,
  // Zeilenumbruch dazwischen, fehlende Spalte, Zeile und Spalte ausserhalb.
  Assert.AreEqual('', Fix('Foo(A, B,);', 1, Msg(3), Reason));
  Assert.AreEqual(Moved, Reason);
  Assert.AreEqual('', Fix('Foo(A, B);', 1, Msg(6), Reason));
  Assert.AreEqual(Moved, Reason);
  Assert.AreEqual('', Fix('Foo(A, {c} );', 1, Msg(6), Reason));
  Assert.AreEqual(Moved, Reason);
  Assert.AreEqual('', Fix(Join(['Foo(A,', ');']), 1, Msg(6), Reason));
  Assert.AreEqual(Moved, Reason);
  Assert.AreEqual('', Fix('Foo(A, B,);', 1, 'Trailing comma', Reason));
  Assert.AreEqual(MsgNoColumn, Reason);
  Assert.AreEqual('', Fix('Foo(A, B,);', 5, Msg(9), Reason));
  Assert.AreEqual(Moved, Reason);
  Assert.AreEqual('', Fix('Foo(A, B,);', 1, Msg(40), Reason));
  Assert.AreEqual(Moved, Reason);
end;

{$IFNDEF FPC}

// ---- Mit dem echten Detektor ----

procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TTrailingCommaArgListDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := DetectSource('rdx_s068_', ASource, AKind, RunDetector);
end;

function InProc(const AText: string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation', '',
    'procedure P;', 'begin']) + #13#10 + AText + #13#10
    + Join(['end;', '', 'end.']);
end;

procedure TTestRdxTrailingCommaFixDetector.Sca068_Detector_CatalogExample;
var
  Meta : TRuleMeta;
begin
  // Das Beispiel 'bad' (zwei Funde): nach der Hilfe meldet der Detektor
  // nichts mehr, und der Text ist das Beispiel 'good'.
  Meta := TRuleCatalog.GetRuleCanonical(fkTrailingCommaArgList);
  Assert.AreEqual<Integer>(2,
    Length(Detect(InProc(CatalogText(Meta.BadExample)), fkTrailingCommaArgList)));
  Assert.AreEqual(InProc(CatalogText(Meta.GoodExample)),
    FixAllWith(InProc(CatalogText(Meta.BadExample)), fkTrailingCommaArgList,
      Detect));
end;

procedure TTestRdxTrailingCommaFixDetector.Sca068_Detector_TwoOnOneLine;
begin
  // Der Detektor meldet je Zeile nur das erste Komma; nach der Hilfe zeigt
  // er das zweite, und die Hilfe laeuft ein zweites Mal.
  Assert.AreEqual<Integer>(1,
    Length(Detect(InProc('  Foo(A,); Bar(B,);'), fkTrailingCommaArgList)));
  Assert.AreEqual(InProc('  Foo(A); Bar(B);'),
    FixAllWith(InProc('  Foo(A,); Bar(B,);'), fkTrailingCommaArgList, Detect));
end;

procedure TTestRdxTrailingCommaFixDetector.Sca068_Detector_MissingArgument_NoHelp;
begin
  // Der Detektor meldet auch 'Foo(,)' - die Hilfe lehnt es ab.
  Assert.AreEqual<Integer>(1,
    Length(Detect(InProc('  Foo(,);'), fkTrailingCommaArgList)));
  AssertNoHelpWith(InProc('  Foo(,);'), fkTrailingCommaArgList,
    _(R_COMMA_NOARG), Detect);
end;

procedure TTestRdxTrailingCommaFixDetector.Sca068_Adapter_Outcome;
var
  F  : TLeakFinding;
  O  : TRdxFixOutcome;
  SL : TStringList;
  S  : string;
begin
  S := InProc('  DoStuff(A, B,);');
  SL := TStringList.Create;
  F := nil;
  try
    F := TLeakFinding.New('t.pas', '', LineOf(S, 'DoStuff'), Msg(15),
      fkTrailingCommaArgList);
    // Ohne Zeilen: kein Puffer.
    O := TRdxFixTable.FixFor(nil, nil, F, nil);
    Assert.IsFalse(O.Enabled);
    Assert.AreEqual(R_NO_FILE, O.Reason);
    SL.Text := S;
    O := TRdxFixTable.FixFor(nil, SL, F, nil);
    Assert.IsTrue(O.Enabled, O.Reason);
    Assert.AreEqual(InProc('  DoStuff(A, B);'), Apply(S, O.Edits));
  finally
    F.Free;
    SL.Free;
  end;
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxTrailingCommaFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxTrailingCommaFixDetector);
  {$ENDIF}

end.
