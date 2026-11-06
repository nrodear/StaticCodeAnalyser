unit uTestRdxFormatterMarkerFix;

// Editorhilfe SCA206 FormatterMarker (uRdxFormatterMarkerFix): ein
// Formatter-Marker mit Leerraum wird zur exakten Form '{(*}' bzw. '{*)}'.
// Die Faelle auf Text laufen ohne Parser und ohne Detektor; die Rundlaeufe
// mit dem echten Detektor (Katalog-Beispiel, Bilanzmeldung ohne Hilfe) und
// der Adapter stehen in einer eigenen Fixture hinter {$IFNDEF FPC} (ueber
// TRdxFixTable.FixFor) und laufen nur in reDelphix.Test. Die Text-Fixture
// laeuft auch im FPC-Pruefstand (build.sh): der Planer hat keine
// Delphi-only-uses, den Adapter traegt uRdxFixTable.
// Prueft: Blank vor/hinter den Sternen, Tab (Meldung '#9'), Marker hinter
// Code, der kaputte von zwei Markern einer Zeile, und die Sperren -
// Bilanzmeldungen (Start ohne Ende, Ende ohne Start, zweiter Start), Marker
// in Kommentar und String, Zeilenanfang im Kommentar, verschobene oder
// schon korrigierte Zeile, derselbe Marker zweimal auf der Zeile.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxFormatterMarkerFix = class
  public
    [Test] procedure Sca206_BlankInStart;
    [Test] procedure Sca206_BlankInEnd;
    [Test] procedure Sca206_BlanksAndTab;
    [Test] procedure Sca206_AfterCode;
    [Test] procedure Sca206_MalformedOfTwoOnLine;
    [Test] procedure Sca206_ExactOf;
    [Test] procedure Sca206_Unpaired_NoHelp;
    [Test] procedure Sca206_InCommentOrString_NoHelp;
    [Test] procedure Sca206_LineStartsInComment_NoHelp;
    [Test] procedure Sca206_Moved_NoHelp;
    [Test] procedure Sca206_Twice_NoHelp;
  end;

{$IFNDEF FPC}
  // Rundlaeufe mit dem ECHTEN Detektor und der Adapter (nur Delphi).
  [TestFixture]
  TTestRdxFormatterMarkerFixDetector = class
  public
    [Test] procedure Sca206_Detector_CatalogExample;
    [Test] procedure Sca206_Detector_Unclosed_NoHelp;
    [Test] procedure Sca206_Adapter_Outcome;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uFormatterMarker,
  uRdxRecipeRunner, uRdxFixTable,
  uTestRdxDetectorKit,   // TSeen, CatalogText, DetectSource, FixAllWith
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxFormatterMarkerFix,
  uRdxText,              // _() und die gemeinsamen Gruende (E29)
  uTestRdxTextKit;       // Join, Apply

const
  // Die festen Meldungen des Detektors (F1-F3) - ohne Hilfe.
  MSG_F1 = 'Formatter marker {(*} is never closed by {*)} - GExperts, ' +
    'CnWizards and JCF leave the rest of the file unformatted';
  MSG_F2 = 'Formatter marker {*)} has no opening {(*} - it closes nothing, ' +
    'the code above it is formatted';
  MSG_F3 = 'Second {(*} inside an open formatter-off region - the markers ' +
    'do not nest, the first {*)} already switches formatting back on';

// ---- Helfer ----

// Der Grund einer verschobenen Stelle, in der Sprache der Tests.
function Moved: string;
begin
  Result := MsgMovedSuffix(_(R_FM_MOVED));
end;

// Die Meldung des Detektors fuer einen falsch geschriebenen Marker (F4):
// AShown wie in der Meldung ('#9' fuer Tab), AExact die exakte Form.
function Msg(const AShown, AExact: string): string;
begin
  Result := Format('Malformed formatter marker ''%s'' - formatters ' +
    'recognise only the exact ''%s'' without blanks, so this marker is ' +
    'ignored', [AShown, AExact]);
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
    if TRdxFormatterMarkerFix.ExactMarker(Map, ALine, AMessage, E, AReason) then
      Result := Apply(ASource, E);
  finally
    Map.Free;
    SL.Free;
  end;
end;

procedure AssertFix(const AExpected, ALine, AShown, AExact: string);
var
  Reason : string;
begin
  Assert.AreEqual(AExpected, Fix(ALine, 1, Msg(AShown, AExact), Reason),
    Reason);
end;

procedure AssertNoFix(const ASource: string; ALine: Integer;
  const AMessage, AReason: string);
var
  Reason : string;
begin
  Assert.AreEqual('', Fix(ASource, ALine, AMessage, Reason), ASource);
  Assert.AreEqual(AReason, Reason, ASource);
end;

// ---- Auf Text ----

procedure TTestRdxFormatterMarkerFix.Sca206_BlankInStart;
begin
  AssertFix('{(*}', '{ (*}', '{ (*}', '{(*}');
  AssertFix('{(*}', '{(* }', '{(* }', '{(*}');
  AssertFix('  {(*}', '  {   (*}', '{   (*}', '{(*}');
end;

procedure TTestRdxFormatterMarkerFix.Sca206_BlankInEnd;
begin
  AssertFix('{*)}', '{ *)}', '{ *)}', '{*)}');
  AssertFix('{*)}', '{*) }', '{*) }', '{*)}');
end;

procedure TTestRdxFormatterMarkerFix.Sca206_BlanksAndTab;
begin
  // Blank auf beiden Seiten; Tab statt Blank - die Meldung zeigt ihn als
  // '#9', die Zeile traegt das Zeichen.
  AssertFix('{(*}', '{ (* }', '{ (* }', '{(*}');
  AssertFix('{(*}', '{(*' + #9 + '}', '{(*#9}', '{(*}');
  AssertFix('{*)}', '{' + #9 + '*)}', '{#9*)}', '{*)}');
end;

procedure TTestRdxFormatterMarkerFix.Sca206_AfterCode;
begin
  // Hinter Code und vor einem //-Kommentar; ein String mit '' davor stoert
  // nicht.
  AssertFix('X := 1; {*)}', 'X := 1; { *)}', '{ *)}', '{*)}');
  AssertFix('S := ''it''''s''; {(*} // tables',
    'S := ''it''''s''; { (*} // tables', '{ (*}', '{(*}');
end;

procedure TTestRdxFormatterMarkerFix.Sca206_MalformedOfTwoOnLine;
begin
  // Ein korrekter Start und ein kaputtes Ende auf einer Zeile: nur das Ende
  // aendert sich.
  AssertFix('{(*} if A then B; {*)}', '{(*} if A then B; {*) }', '{*) }',
    '{*)}');
end;

procedure TTestRdxFormatterMarkerFix.Sca206_ExactOf;
begin
  Assert.AreEqual('{(*}', TRdxFormatterMarkerFix.ExactOf(Msg('{ (*}', '{(*}')));
  Assert.AreEqual('{*)}', TRdxFormatterMarkerFix.ExactOf(Msg('{*) }', '{*)}')));
  Assert.AreEqual('', TRdxFormatterMarkerFix.ExactOf(MSG_F1));
  Assert.AreEqual('', TRdxFormatterMarkerFix.ExactOf(MSG_F2));
  Assert.AreEqual('', TRdxFormatterMarkerFix.ExactOf(MSG_F3));
  Assert.AreEqual('', TRdxFormatterMarkerFix.ExactOf(''));
end;

// ---- Gegenproben ----

procedure TTestRdxFormatterMarkerFix.Sca206_Unpaired_NoHelp;
begin
  // Die Bilanzmeldungen: wohin der Partner gehoert, weiss nur der Autor.
  AssertNoFix('{(*}', 1, MSG_F1, _(R_FM_NOT_MALFORMED));
  AssertNoFix('{*)}', 1, MSG_F2, _(R_FM_NOT_MALFORMED));
  AssertNoFix('{(*}', 1, MSG_F3, _(R_FM_NOT_MALFORMED));
end;

procedure TTestRdxFormatterMarkerFix.Sca206_InCommentOrString_NoHelp;
begin
  // Kein { }-Kommentar im Code: in //, in (* *), im String.
  AssertNoFix('// { (*}', 1, Msg('{ (*}', '{(*}'), Moved);
  AssertNoFix('(* { (*} *)', 1, Msg('{ (*}', '{(*}'), Moved);
  AssertNoFix('S := ''{ (*}'';', 1, Msg('{ (*}', '{(*}'), Moved);
  // Fussnote und Kommentarblock sind keine Marker.
  AssertNoFix('X = 1; { (*) }', 1, Msg('{ (*) }', '{(*}'), Moved);
end;

procedure TTestRdxFormatterMarkerFix.Sca206_LineStartsInComment_NoHelp;
begin
  // Die Zeile beginnt in einem mehrzeiligen (* *)-Kommentar.
  AssertNoFix(Join(['(*', '{ (*}', '*)']), 2, Msg('{ (*}', '{(*}'),
    MsgLineStartsInCommentOrString);
end;

procedure TTestRdxFormatterMarkerFix.Sca206_Moved_NoHelp;
begin
  // Schon korrigiert, anderer Leerraum als gemeldet, andere Form als
  // gemeldet, Zeile ausserhalb.
  AssertNoFix('{(*}', 1, Msg('{ (*}', '{(*}'), Moved);
  AssertNoFix('{  (*}', 1, Msg('{ (*}', '{(*}'), Moved);
  AssertNoFix('{ *)}', 1, Msg('{ *)}', '{(*}'), Moved);
  AssertNoFix('{ (*}', 3, Msg('{ (*}', '{(*}'), Moved);
end;

procedure TTestRdxFormatterMarkerFix.Sca206_Twice_NoHelp;
begin
  // Derselbe kaputte Marker zweimal: welcher gemeint ist, bleibt offen.
  AssertNoFix('{ (*} X := 1; { (*}', 1, Msg('{ (*}', '{(*}'),
    _(R_FM_TWICE));
end;

{$IFNDEF FPC}

// ---- Mit dem echten Detektor ----

procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TFormatterMarkerDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := DetectSource('rdx_s206_', ASource, AKind, RunDetector);
end;

// Eine Unit mit AText im interface-Teil.
function InUnit(const AText: string): string;
begin
  Result := Join(['unit t;', 'interface']) + #13#10 + AText + #13#10
    + Join(['implementation', '', 'end.']);
end;

procedure TTestRdxFormatterMarkerFixDetector.Sca206_Detector_CatalogExample;
var
  Meta : TRuleMeta;
begin
  // Das Beispiel 'bad' (ein Fund am Start): nach der Hilfe meldet der
  // Detektor nichts mehr, und der Text ist das Beispiel 'good'.
  Meta := TRuleCatalog.GetRuleCanonical(fkFormatterMarker);
  Assert.AreEqual<Integer>(1,
    Length(Detect(InUnit(CatalogText(Meta.BadExample)), fkFormatterMarker)));
  Assert.AreEqual(InUnit(CatalogText(Meta.GoodExample)),
    FixAllWith(InUnit(CatalogText(Meta.BadExample)), fkFormatterMarker,
      Detect));
end;

procedure TTestRdxFormatterMarkerFixDetector.Sca206_Detector_Unclosed_NoHelp;
begin
  // Der Detektor meldet den offenen Start (F1) - die Hilfe lehnt ab.
  Assert.AreEqual<Integer>(1,
    Length(Detect(InUnit('{(*}'), fkFormatterMarker)));
  AssertNoHelpWith(InUnit('{(*}'), fkFormatterMarker,
    _(R_FM_NOT_MALFORMED), Detect);
end;

procedure TTestRdxFormatterMarkerFixDetector.Sca206_Adapter_Outcome;
var
  F  : TLeakFinding;
  O  : TRdxFixOutcome;
  SL : TStringList;
  S  : string;
begin
  S := InUnit(Join(['{ (*}', 'const X = 1;', '{*)}']));
  SL := TStringList.Create;
  F := nil;
  try
    F := TLeakFinding.New('t.pas', '', LineOf(S, '{ (*}'),
      Msg('{ (*}', '{(*}'), fkFormatterMarker);
    // Ohne Zeilen: kein Puffer.
    O := TRdxFixTable.FixFor(nil, nil, F, nil);
    Assert.IsFalse(O.Enabled);
    Assert.AreEqual(MsgNoFileOpen, O.Reason);
    SL.Text := S;
    O := TRdxFixTable.FixFor(nil, SL, F, nil);
    Assert.IsTrue(O.Enabled, O.Reason);
    Assert.IsFalse(O.ChangesBehavior, 'bedeutungsgleich');
    Assert.AreEqual(InUnit(Join(['{(*}', 'const X = 1;', '{*)}'])),
      Apply(S, O.Edits));
  finally
    F.Free;
    SL.Free;
  end;
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxFormatterMarkerFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxFormatterMarkerFixDetector);
  {$ENDIF}

end.
