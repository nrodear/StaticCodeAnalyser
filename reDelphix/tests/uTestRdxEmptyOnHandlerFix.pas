unit uTestRdxEmptyOnHandlerFix;

// Editorhilfe SCA159 EmptyOnHandler (uRdxEmptyOnHandlerFix): der leere
// Handler 'on E: T do ;' bzw. 'do begin end;' bekommt 'raise;'. Die Faelle
// auf Text laufen ohne Parser und ohne Detektor; die Rundlaeufe mit dem
// echten Detektor (Katalog-Beispiel, Blockform, Kommentar - ueber
// TRdxFixTable.FixFor) stehen hinter {$IFNDEF FPC}, der Adapter-Test
// (Sca159_Adapter_Outcome, auch ueber FixFor) davor. Nur Delphi
// (reDelphix.Test).
// Der Planer ist seit der Folgewelle G09-07 ohne Delphi-only-uses (den
// Adapter traegt uRdxFixTable); die Unit steht trotzdem nicht im
// FPC-Pruefstand (build.sh) - dessen Runner kennt die {$IFNDEF FPC}-
// Weichen nicht, sie sind heute ohne Wirkung.
// Prueft: beide Formen (auch ueber Zeilen, mit Tabs, grossgeschrieben,
// anonymer Typ), den Bereich der Ersetzung, und die Sperren - Kommentar und
// Direktive, mehrere Handler auf der Zeile, verschobene Zeile, Typ der
// Meldung, falscher Kontext, EAbort, Layout.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxEmptyOnHandlerFix = class
  public
    [Test] procedure Sca159_Semicolon_Helps;
    [Test] procedure Sca159_Semicolon_Variants;
    [Test] procedure Sca159_BeginEnd_OneLine;
    [Test] procedure Sca159_BeginEnd_ManyLines;
    [Test] procedure Sca159_BeginEnd_TabsAndBlankLine;
    [Test] procedure Sca159_BeginEnd_SpanContract;
    [Test] procedure Sca159_OtherHandlersStay;
    [Test] procedure Sca159_Comment_NoHelp;
    [Test] procedure Sca159_PreviousLineComment_NoHelp;
    [Test] procedure Sca159_Many_NoHelp;
    [Test] procedure Sca159_Moved_NoHelp;
    [Test] procedure Sca159_NotCode_NoHelp;
    [Test] procedure Sca159_Context_NoHelp;
    [Test] procedure Sca159_Abort_NoHelp;
    [Test] procedure Sca159_Layout_NoHelp;
    [Test] procedure Sca159_Adapter_Outcome;
    {$IFNDEF FPC}
    [Test] procedure Sca159_Detector_CatalogExample;
    [Test] procedure Sca159_Detector_BlockForm;
    [Test] procedure Sca159_Detector_Comment_NoHelp;
    {$ENDIF}
  end;

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uRuleCatalog, uEmptyOnHandler,
  uTestRdxDetectorKit,   // TSeen, CatalogText, DetectSource
  {$ENDIF}
  uMethodd12, uSCAConsts, uRdxBufferMath, uRdxCodeMap, uRdxRecipeRunner,
  uRdxFixTable,
  uRdxEmptyOnHandlerFix,
  uRdxText,              // _() und die gemeinsamen Gruende
  uTestRdxTextKit;       // Join, Apply

const
  // Die Zeile des ersten Handlers in InExcept.
  HANDLER_LINE = 9;

// Eine Routine mit try..except; ALines sind die Zeilen des except-Teils
// (ab Zeile 9).
function InExcept(const ALines: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation', 'procedure P;',
    'begin', '  try', '    DoIt;', '  except']) + #13#10 + Join(ALines)
    + #13#10 + Join(['  end;', 'end;', 'end.']);
end;

// Die Meldung des Detektors fuer den Typ AType.
function Msg(const AType: string): string;
begin
  Result := Format('Typed exception handler on %s has empty body - silent '
    + 'failure', [AType]);
end;

// Der Grund einer verschobenen Stelle, in der Sprache der Tests.
function Moved: string;
begin
  Result := MsgMovedSuffix(_(R_EOH_MOVED));
end;

// Der Planer an Zeile ALine mit der Meldung AMessage: der neue Text, bei
// einer Ablehnung '' und der Grund in AReason.
function FixAt(const ASource: string; ALine: Integer; const AMessage: string;
  out AReason: string): string;
var
  SL   : TStringList;
  Map  : TRdxCodeMap;
  Edit : TRdxEdit;
begin
  Result := '';
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    try
      if TRdxEmptyOnHandlerFix.Reraise(Map, ALine, AMessage, Edit, AReason) then
        Result := Apply(ASource, Edit);
    finally
      Map.Free;
    end;
  finally
    SL.Free;
  end;
end;

// Der Plan an der ersten Handlerzeile, Typ EFoo; '' bei Ablehnung.
function Fix(const ASource: string; out AReason: string): string;
begin
  Result := FixAt(ASource, HANDLER_LINE, Msg('EFoo'), AReason);
end;

procedure AssertFix(const AExpected: array of string;
  const AHandler: array of string);
var
  Reason : string;
begin
  Assert.AreEqual(InExcept(AExpected), Fix(InExcept(AHandler), Reason), Reason);
end;

procedure AssertNoFix(const AHandler: array of string; const AReason: string);
var
  Reason : string;
begin
  Assert.AreEqual('', Fix(InExcept(AHandler), Reason), AHandler[0]);
  Assert.AreEqual(AReason, Reason, AHandler[0]);
end;

// ---- Auf Text ----

procedure TTestRdxEmptyOnHandlerFix.Sca159_Semicolon_Helps;
var
  Reason : string;
begin
  AssertFix(['    on E: EFoo do raise;'], ['    on E: EFoo do ;']);
  // Alles auf einer Zeile: try ... except on ... do ; end.
  Assert.AreEqual('try DoStuff; except on E: EFoo do raise; end;',
    FixAt('try DoStuff; except on E: EFoo do ; end;', 1, Msg('EFoo'), Reason),
    Reason);
end;

procedure TTestRdxEmptyOnHandlerFix.Sca159_Semicolon_Variants;
begin
  // Kein Leerzeichen vor dem ';', mehrere davor, anonymer Handler ohne E:,
  // andere Schreibweise.
  AssertFix(['    on E: EFoo do raise;'], ['    on E: EFoo do;']);
  AssertFix(['    on E: EFoo do raise;'], ['    on E: EFoo do   ;']);
  AssertFix(['    on EFoo do raise;'], ['    on EFoo do ;']);
  AssertFix(['    ON E : EFoo DO raise;'], ['    ON E : EFoo DO ;']);
  // Das Ende der Zeile bleibt: Leerraum dahinter, naechster Handler.
  AssertFix(['    on E: EFoo do raise;  '], ['    on E: EFoo do ;  ']);
end;

procedure TTestRdxEmptyOnHandlerFix.Sca159_BeginEnd_OneLine;
begin
  AssertFix(['    on E: EFoo do begin raise; end;'],
    ['    on E: EFoo do begin end;']);
  AssertFix(['    on E: EFoo do begin raise; end;'],
    ['    on E: EFoo do begin    end;']);
  AssertFix(['    on E: EFoo do BEGIN raise; END'],
    ['    on E: EFoo do BEGIN END']);
end;

procedure TTestRdxEmptyOnHandlerFix.Sca159_BeginEnd_ManyLines;
begin
  // begin und end auf eigenen Zeilen: 'raise;' eine Stufe tiefer als end.
  AssertFix(['    on E: EFoo do', '    begin', '      raise;', '    end;'],
    ['    on E: EFoo do', '    begin', '    end;']);
  // begin hinter dem do.
  AssertFix(['    on E: EFoo do begin', '      raise;', '    end;'],
    ['    on E: EFoo do begin', '    end;']);
  // Tiefer eingerueckt: die Stufe der Datei bleibt zwei Leerzeichen.
  AssertFix(['        on E: EFoo do', '        begin', '          raise;',
    '        end;'],
    ['        on E: EFoo do', '        begin', '        end;']);
end;

procedure TTestRdxEmptyOnHandlerFix.Sca159_BeginEnd_TabsAndBlankLine;
begin
  // Tabs: eine Stufe ist ein Tab.
  AssertFix([#9'on E: EFoo do', #9'begin', #9#9'raise;', #9'end;'],
    [#9'on E: EFoo do', #9'begin', #9'end;']);
  // Leerzeilen zwischen begin und end verschwinden mit.
  AssertFix(['    on E: EFoo do begin', '      raise;', '    end;'],
    ['    on E: EFoo do begin', '', '    end;']);
end;

procedure TTestRdxEmptyOnHandlerFix.Sca159_BeginEnd_SpanContract;
var
  SL   : TStringList;
  Map  : TRdxCodeMap;
  Edit : TRdxEdit;
  Src  : string;
  Why  : string;
begin
  // Mehrzeilig: die Spanne beginnt auf dem LETZTEN Zeichen von begin (nie
  // hinter dem Zeilenende) und endet vor dem end.
  Src := InExcept(['    on E: EFoo do begin', '    end;']);
  SL := TStringList.Create;
  try
    SL.Text := Src;
    Map := TRdxCodeMap.Create(SL);
    try
      Assert.IsTrue(TRdxEmptyOnHandlerFix.Reraise(Map, HANDLER_LINE,
        Msg('EFoo'), Edit, Why), Why);
      Assert.AreEqual<Integer>(HANDLER_LINE, Edit.Span.StartLine);
      Assert.AreEqual<Integer>(Length(Map.Raw(HANDLER_LINE)),
        Edit.Span.StartCol);
      Assert.AreEqual<Integer>(HANDLER_LINE + 1, Edit.Span.EndLine);
      Assert.AreEqual<Integer>(5, Edit.Span.EndCol);
      Assert.AreEqual('n' + #10 + '    ', Edit.Expected);
      Assert.AreEqual('n' + #10 + '      raise;' + #10 + '    ',
        Edit.NewText);
    finally
      Map.Free;
    end;
  finally
    SL.Free;
  end;
end;

procedure TTestRdxEmptyOnHandlerFix.Sca159_OtherHandlersStay;
begin
  // Nur der gemeldete Handler wird angefasst; Nachbarn, auch leere, bleiben
  // (jeder hat seinen eigenen Fund auf seiner Zeile).
  AssertFix(['    on E: EFoo do raise;', '    on E: EBar do ;',
    '    on E: EBaz do Log(E);'],
    ['    on E: EFoo do ;', '    on E: EBar do ;',
    '    on E: EBaz do Log(E);']);
end;

procedure TTestRdxEmptyOnHandlerFix.Sca159_Comment_NoHelp;
begin
  // Ein Kommentar ist Absicht - der Detektor sieht ihn nicht, die Hilfe
  // schon.
  AssertNoFix(['    on E: EFoo do ; // darf ignoriert werden'],
    _(R_EOH_COMMENT));
  AssertNoFix(['    on E: EFoo do { ok } ;'], _(R_EOH_COMMENT));
  AssertNoFix(['    on E: EFoo { x } do ;'], _(R_EOH_COMMENT));
  AssertNoFix(['    {c} on E: EFoo do ;'], _(R_EOH_COMMENT));
  AssertNoFix(['    on E: EFoo do begin { x } end;'], _(R_EOH_COMMENT));
  AssertNoFix(['    on E: EFoo do begin // nichts', '    end;'],
    _(R_EOH_COMMENT));
  AssertNoFix(['    on E: EFoo do', '    begin', '      // ignoriert',
    '    end;'], _(R_EOH_COMMENT));
  // Direktive im Handler.
  AssertNoFix(['    on E: EFoo do {$IFDEF X} ; {$ENDIF}'], _(R_EOH_COMMENT));
end;

procedure TTestRdxEmptyOnHandlerFix.Sca159_PreviousLineComment_NoHelp;
var
  Reason : string;
begin
  // Ein Kommentar in der Zeile DAVOR nennt meist die Absicht (der Detektor
  // sieht ihn nicht): keine Hilfe. Der Handler steht dann in Zeile 10.
  Assert.AreEqual('', FixAt(InExcept(['    // Abbruch gewollt',
    '    on E: EFoo do ;']), HANDLER_LINE + 1, Msg('EFoo'), Reason));
  Assert.AreEqual(_(R_EOH_COMMENT), Reason);
end;

procedure TTestRdxEmptyOnHandlerFix.Sca159_Many_NoHelp;
begin
  AssertNoFix(['    on A: EA do ; on B: EB do ;'], _(R_EOH_MANY));
  // Auch, wenn der andere Handler nicht leer ist: der Fund koennte jeden
  // meinen.
  AssertNoFix(['    on A: EA do Foo; on B: EB do ;'], _(R_EOH_MANY));
end;

procedure TTestRdxEmptyOnHandlerFix.Sca159_Moved_NoHelp;
var
  Reason : string;
  Src    : string;
begin
  // Der Handler hat inzwischen einen Rumpf.
  AssertNoFix(['    on E: EFoo do Log(E);'], Moved);
  AssertNoFix(['    on E: EFoo do begin Log(E); end;'], Moved);
  AssertNoFix(['    on E: EFoo do begin', '      Log(E);', '    end;'], Moved);
  // Der Typ der Meldung ist ein anderer: die Zeile gehoert zu einem
  // anderen Fund.
  Src := InExcept(['    on E: EFoo do ;']);
  Assert.AreEqual('', FixAt(Src, HANDLER_LINE, Msg('EBar'), Reason));
  Assert.AreEqual(Moved, Reason);
  // Eine Zeile ohne Handler.
  Assert.AreEqual('', FixAt(Src, HANDLER_LINE - 2, Msg('EFoo'), Reason));
  Assert.AreEqual(Moved, Reason);
  // Ohne Typ in der Meldung (nur die Zeile zaehlt) hilft sie.
  Assert.AreEqual(InExcept(['    on E: EFoo do raise;']),
    FixAt(Src, HANDLER_LINE, 'Typed exception handler', Reason), Reason);
end;

procedure TTestRdxEmptyOnHandlerFix.Sca159_NotCode_NoHelp;
begin
  // Handler in einem Kommentar oder String ist kein Code.
  AssertNoFix(['    // on E: EFoo do ;'], Moved);
  AssertNoFix(['    S := ''on E: EFoo do ;'';'], Moved);
  AssertNoFix(['    { on E: EFoo do ; }'], Moved);
end;

procedure TTestRdxEmptyOnHandlerFix.Sca159_Context_NoHelp;
begin
  // Das 'on' beginnt keinen Handler (davor weder except noch ';').
  AssertNoFix(['    Foo on E: EFoo do ;'], _(R_EOH_CONTEXT));
  AssertNoFix(['    X := on E: EFoo do ;'], _(R_EOH_CONTEXT));
end;

procedure TTestRdxEmptyOnHandlerFix.Sca159_Abort_NoHelp;
var
  Reason : string;
begin
  // Der Detektor meldet EAbort nie; steht der Handler doch da, bleibt er.
  Assert.AreEqual('', FixAt(InExcept(['    on E: EAbort do ;']),
    HANDLER_LINE, Msg('EAbort'), Reason));
  Assert.AreEqual(_(R_EOH_ABORT), Reason);
end;

procedure TTestRdxEmptyOnHandlerFix.Sca159_Layout_NoHelp;
begin
  // Das ';' auf der Folgezeile.
  AssertNoFix(['    on E: EFoo do', '    ;'], _(R_EOH_LAYOUT));
  // Der Kopf ueber zwei Zeilen: auf der gemeldeten Zeile steht kein Kopf.
  AssertNoFix(['    on E: EFoo', '    do ;'], Moved);
end;

procedure TTestRdxEmptyOnHandlerFix.Sca159_Adapter_Outcome;
var
  F  : TLeakFinding;
  O  : TRdxFixOutcome;
  SL : TStringList;
  S  : string;
begin
  S := InExcept(['    on E: EFoo do ;']);
  SL := TStringList.Create;
  F := nil;
  try
    F := TLeakFinding.New('t.pas', '', HANDLER_LINE, Msg('EFoo'),
      fkEmptyOnHandler);
    // Ohne Zeilen: kein Puffer.
    O := TRdxFixTable.FixFor(nil, nil, F, nil);
    Assert.IsFalse(O.Enabled);
    Assert.AreEqual(MsgNoFileOpen, O.Reason);
    SL.Text := S;
    O := TRdxFixTable.FixFor(nil, SL, F, nil);
    Assert.IsTrue(O.Enabled, O.Reason);
    Assert.AreEqual(InExcept(['    on E: EFoo do raise;']),
      Apply(S, O.Edits));
  finally
    F.Free;
    SL.Free;
  end;
end;

{$IFNDEF FPC}

// ---- Mit dem echten Detektor ----

procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TEmptyOnHandlerDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_s159_', ASource, fkEmptyOnHandler, RunDetector);
end;

// Dasselbe in der Form von TDetectFunc (FixAllWith).
function DetectKind(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := DetectSource('rdx_s159_', ASource, AKind, RunDetector);
end;

// Fund fuer Fund ueber den Einstieg der Tabelle (TRdxFixTable.FixFor), nach
// jeder Ersetzung neu gemeldet, bis der Detektor schweigt.
function FixAll(const ASource: string): string;
begin
  Result := FixAllWith(ASource, fkEmptyOnHandler, DetectKind);
end;

procedure TTestRdxEmptyOnHandlerFix.Sca159_Detector_CatalogExample;
var
  Meta : TRuleMeta;
  Bad  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  // Das Beispiel 'bad' des Katalogs in einer Routine: nach der Hilfe
  // meldet der Detektor nichts mehr.
  Meta := TRuleCatalog.GetRuleCanonical(fkEmptyOnHandler);
  Bad := CatalogText(Meta.BadExample);
  Assert.IsTrue(Pos('on E: EDatabaseError do ;', Bad) > 0, Bad);
  Seen := Detect(InExcept([Bad]));
  Assert.AreEqual<Integer>(1, Length(Seen));
  // Die Kennzeichnung "aendert das Verhalten" setzt erst die Tabellenzeile
  // (FixFor) - der Adapter laesst sie auf dem Default.
  O := PlanFixIn(InExcept([Bad]), 't.pas', fkEmptyOnHandler, Seen[0]);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.IsTrue(O.ChangesBehavior, 'raise aendert das Verhalten');
  Assert.AreEqual(
    StringReplace(InExcept([Bad]), 'EDatabaseError do ;',
      'EDatabaseError do raise;', []),
    FixAll(InExcept([Bad])));
end;

procedure TTestRdxEmptyOnHandlerFix.Sca159_Detector_BlockForm;
begin
  // Beide Formen und beide Schreibweisen des Blocks, zwei Funde; die
  // Hilfe behandelt sie nacheinander.
  Assert.AreEqual<Integer>(3, Length(Detect(InExcept([
    '    on A: EA do ;', '    on B: EB do begin end;',
    '    on C: EC do', '    begin', '    end;']))));
  Assert.AreEqual(
    InExcept(['    on A: EA do raise;', '    on B: EB do begin raise; end;',
      '    on C: EC do', '    begin', '      raise;', '    end;']),
    FixAll(InExcept(['    on A: EA do ;', '    on B: EB do begin end;',
      '    on C: EC do', '    begin', '    end;'])));
end;

procedure TTestRdxEmptyOnHandlerFix.Sca159_Detector_Comment_NoHelp;
var
  Seen   : TArray<TSeen>;
  Src    : string;
  Reason : string;
begin
  // Der Detektor meldet den Handler mit Kommentar (er blendet Kommentare
  // aus) - die Hilfe lehnt ihn ab.
  Src := InExcept(['    on E: EFoo do ; // darf ignoriert werden']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen));
  Assert.AreEqual('', FixAt(Src, Seen[0].Line, Seen[0].Msg, Reason));
  Assert.AreEqual(_(R_EOH_COMMENT), Reason);
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxEmptyOnHandlerFix);

end.
