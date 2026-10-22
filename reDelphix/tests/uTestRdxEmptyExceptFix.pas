unit uTestRdxEmptyExceptFix;

// Editorhilfe SCA002 EmptyExcept (uRdxEmptyExceptFix): ein leerer except-
// Block bekommt ein 'raise;'. Die Faelle auf Text laufen ohne Parser und ohne
// Detektor; der Adapter und die Rundlaeufe mit dem echten Detektor
// (uCodeSmells2, ueber TRdxFixTable.FixFor) stehen in einer eigenen
// Fixture hinter {$IFNDEF FPC} und laufen nur in reDelphix.Test.
// Die Text-Fixture laeuft auch im FPC-Pruefstand (build.sh): der Planer
// ist seit der Folgewelle G09-07 ohne Delphi-only-uses (den Adapter traegt
// uRdxFixTable), und der Pruefstand blendet seit der Folgewelle B3 die
// {$IFNDEF FPC}-Teile aus.
// Prueft: neue Zeile unter except (Einrueckstufe aus dem try-Rumpf, Tabs,
// Fallback), inline hinter except, Gross-/Kleinschreibung, Leerzeilen - und
// die Sperren: Kommentar, Direktive, Handler/Anweisung/';' im Block,
// verschobene oder mehrdeutige Zeile.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxEmptyExceptFix = class
  public
    // ---- Umformung ----
    [Test] procedure Sca002_NewLine_UnderExcept;
    [Test] procedure Sca002_NewLine_StepFromBody;
    [Test] procedure Sca002_NewLine_Tabs;
    [Test] procedure Sca002_NewLine_FallbackStep;
    [Test] procedure Sca002_NewLine_BlankLinesKept;
    [Test] procedure Sca002_Inline_OneLine;
    [Test] procedure Sca002_Inline_ExceptEndOwnLine;
    [Test] procedure Sca002_KeywordCaseKept;
    // ---- Gegenproben: keine Hilfe ----
    [Test] procedure Sca002_Comment_NoHelp;
    [Test] procedure Sca002_Directive_NoHelp;
    [Test] procedure Sca002_NotEmpty_NoHelp;
    [Test] procedure Sca002_Moved_NoHelp;
    [Test] procedure Sca002_SeveralOnLine_NoHelp;
  end;

{$IFNDEF FPC}
  // Adapter und echter Detektor (nur Delphi).
  [TestFixture]
  TTestRdxEmptyExceptFixDetector = class
  public
    [Test] procedure Sca002_Adapter_Outcome;
    [Test] procedure Sca002_Detector_RoundTrip;
    [Test] procedure Sca002_Detector_CatalogExample;
    [Test] procedure Sca002_Detector_Comment_NoHelp;
    [Test] procedure Sca002_Detector_StraySemicolon_NoHelp;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uRuleCatalog, uCodeSmells2, uRdxRecipeRunner,
  uRdxFixTable,
  uTestRdxDetectorKit,   // TSeen, CatalogText, DetectSource
  uSCAConsts,            // TFindingKind, fk* (nur die Detektor-Fixture)
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxEmptyExceptFix,
  uRdxText,              // _() und die gemeinsamen Gruende (E29)
  uTestRdxTextKit;       // Join, Apply, LineOf

const
  TAB = #9;

// ---- Helfer ----

// Eine Unit mit einer Routine P und den Zeilen ALines als Rumpf.
function InProc(const ALines: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation', 'procedure P;',
    'begin']) + #13#10 + Join(ALines) + #13#10 + Join(['end;', 'end.']);
end;

// Der Planer an Zeile ALine: der neue Text, bei einer Ablehnung '' und der
// Grund in AReason.
function FixAt(const ASource: string; ALine: Integer;
  out AReason: string): string;
var
  SL   : TStringList;
  Map  : TRdxCodeMap;
  Edit : TRdxEdit;
begin
  Result := '';
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    if TRdxEmptyExceptFix.AddRaise(Map, ALine, '', Edit, AReason) then
      Result := Apply(ASource, Edit);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Dasselbe an der ersten Zeile mit 'except'.
function Fix(const ASource: string; out AReason: string): string;
begin
  if LineOf(ASource, 'except') > 0 then
    Result := FixAt(ASource, LineOf(ASource, 'except'), AReason)
  else
    Result := FixAt(ASource, LineOf(ASource, 'EXCEPT'), AReason);
end;

// Die Hilfe muss Text liefern und ohne Grund auskommen.
function Fixed(const ASource: string): string;
var
  Reason : string;
begin
  Result := Fix(ASource, Reason);
  Assert.AreEqual('', Reason);
end;

// Keine Hilfe, der Grund ist AReason.
procedure AssertRefused(const ASource, AReason: string);
var
  Reason : string;
begin
  Assert.AreEqual('', Fix(ASource, Reason));
  Assert.AreEqual(AReason, Reason);
end;

// ---- Umformung ----

procedure TTestRdxEmptyExceptFix.Sca002_NewLine_UnderExcept;
begin
  // except und end auf eigenen Zeilen: das raise steht in einer neuen Zeile
  // direkt unter except, eine Stufe tiefer.
  Assert.AreEqual(
    InProc(['  try', '    Work;', '  except', '    raise;', '  end;']),
    Fixed(InProc(['  try', '    Work;', '  except', '  end;'])));
end;

procedure TTestRdxEmptyExceptFix.Sca002_NewLine_StepFromBody;
begin
  // Die Stufe kommt aus dem try-Rumpf: vier Leerzeichen, auch wenn eine
  // Fortsetzungszeile tiefer steht.
  Assert.AreEqual(
    InProc(['  try', '    Foo(A,', '        B);', '  except', '    raise;',
      '  end;']),
    Fixed(InProc(['  try', '    Foo(A,', '        B);', '  except',
      '  end;'])));
  Assert.AreEqual(
    InProc(['  try', '      Work;', '  except', '      raise;', '  end;']),
    Fixed(InProc(['  try', '      Work;', '  except', '  end;'])));
  // Eine Kommentarzeile am Rand verfaelscht die Stufe nicht.
  Assert.AreEqual(
    InProc(['  try', '    Work;', '// note', '  except', '    raise;',
      '  end;']),
    Fixed(InProc(['  try', '    Work;', '// note', '  except', '  end;'])));
end;

procedure TTestRdxEmptyExceptFix.Sca002_NewLine_Tabs;
begin
  Assert.AreEqual(
    InProc([TAB + 'try', TAB + TAB + 'Work;', TAB + 'except',
      TAB + TAB + 'raise;', TAB + 'end;']),
    Fixed(InProc([TAB + 'try', TAB + TAB + 'Work;', TAB + 'except',
      TAB + 'end;'])));
end;

procedure TTestRdxEmptyExceptFix.Sca002_NewLine_FallbackStep;
begin
  // Leerer try-Rumpf: keine Stufe zu lesen - zwei Leerzeichen bzw. ein Tab.
  Assert.AreEqual(
    InProc(['  try', '  except', '    raise;', '  end;']),
    Fixed(InProc(['  try', '  except', '  end;'])));
  Assert.AreEqual(
    InProc([TAB + 'try', TAB + 'except', TAB + TAB + 'raise;', TAB + 'end;']),
    Fixed(InProc([TAB + 'try', TAB + 'except', TAB + 'end;'])));
end;

procedure TTestRdxEmptyExceptFix.Sca002_NewLine_BlankLinesKept;
begin
  // Leerzeilen zwischen except und end bleiben, das raise steht unter except.
  Assert.AreEqual(
    InProc(['  try', '    Work;', '  except', '    raise;', '', '  end;']),
    Fixed(InProc(['  try', '    Work;', '  except', '', '  end;'])));
end;

procedure TTestRdxEmptyExceptFix.Sca002_Inline_OneLine;
begin
  Assert.AreEqual(
    InProc(['  try Work except raise; end;']),
    Fixed(InProc(['  try Work except end;'])));
  // Mehr Leerraum bleibt, wie er ist.
  Assert.AreEqual(
    InProc(['  try Work except raise;   end;']),
    Fixed(InProc(['  try Work except   end;'])));
end;

procedure TTestRdxEmptyExceptFix.Sca002_Inline_ExceptEndOwnLine;
begin
  Assert.AreEqual(
    InProc(['  try', '    Work;', '  except raise; end;']),
    Fixed(InProc(['  try', '    Work;', '  except end;'])));
end;

procedure TTestRdxEmptyExceptFix.Sca002_KeywordCaseKept;
begin
  Assert.AreEqual(
    InProc(['  TRY', '    Work;', '  EXCEPT', '    raise;', '  END;']),
    Fixed(InProc(['  TRY', '    Work;', '  EXCEPT', '  END;'])));
end;

// ---- Gegenproben ----

procedure TTestRdxEmptyExceptFix.Sca002_Comment_NoHelp;
begin
  // Ein Kommentar ist Absicht: Zeilenkommentar, Klammerkommentar, ueber
  // Zeilen und auf der except-Zeile.
  AssertRefused(InProc(['  try', '    Work;', '  except', '    // ignore',
    '  end;']), _(R_EXC_COMMENT));
  AssertRefused(InProc(['  try Work except {ok} end;']), _(R_EXC_COMMENT));
  AssertRefused(InProc(['  try', '    Work;', '  except (* a', '  b *)',
    '  end;']), _(R_EXC_COMMENT));
  AssertRefused(InProc(['  try', '    Work;', '  except // fine', '  end;']),
    _(R_EXC_COMMENT));
  // Hinter dem end auf seiner Zeile: der Kommentar begruendet das
  // Verschlucken (wie bei SCA159).
  AssertRefused(InProc(['  try', '    DeleteFile(Tmp);', '  except',
    '  end; // Aufraeumen darf scheitern']), _(R_EXC_COMMENT));
  AssertRefused(InProc(['  try Work except end; { egal }']), _(R_EXC_COMMENT));
end;

procedure TTestRdxEmptyExceptFix.Sca002_Directive_NoHelp;
begin
  AssertRefused(InProc(['  try', '    Work;', '  except', '  {$IFDEF X}',
    '  end;']), _(R_EXC_DIRECTIVE));
  AssertRefused(InProc(['  try Work except {$IFDEF X} end; {$ENDIF}']),
    _(R_EXC_DIRECTIVE));
end;

procedure TTestRdxEmptyExceptFix.Sca002_NotEmpty_NoHelp;
begin
  // Handler, Anweisung, leerer Handler (SCA159), ';' und else: nicht die
  // eindeutige Form.
  AssertRefused(InProc(['  try Work except Cleanup; end;']),
    _(R_EXC_NOT_EMPTY));
  AssertRefused(InProc(['  try Work except on E: Exception do Log(E); end;']),
    _(R_EXC_NOT_EMPTY));
  AssertRefused(InProc(['  try Work except on E: Exception do ; end;']),
    _(R_EXC_NOT_EMPTY));
  AssertRefused(InProc(['  try', '    Work;', '  except;', '  end;']),
    _(R_EXC_NOT_EMPTY));
  AssertRefused(InProc(['  try Work except else Cleanup; end;']),
    _(R_EXC_NOT_EMPTY));
end;

procedure TTestRdxEmptyExceptFix.Sca002_Moved_NoHelp;
var
  S, Reason : string;
begin
  // Die gemeldete Zeile traegt kein except als Code: String und Kommentar,
  // Bezeichner hinter einem Punkt, eine Anweisung.
  S := InProc(['  S := ''except''; // except', '  Work;',
    '  Obj.Except := 1;']);
  Assert.AreEqual('', FixAt(S, LineOf(S, 'S :='), Reason));
  Assert.AreEqual(MsgMovedSuffix(_(R_EXC_MOVED)), Reason);
  Assert.AreEqual('', FixAt(S, LineOf(S, 'Work'), Reason));
  Assert.AreEqual(MsgMovedSuffix(_(R_EXC_MOVED)), Reason);
  Assert.AreEqual('', FixAt(S, LineOf(S, 'Obj.Except'), Reason));
  Assert.AreEqual(MsgMovedSuffix(_(R_EXC_MOVED)), Reason);
end;

procedure TTestRdxEmptyExceptFix.Sca002_SeveralOnLine_NoHelp;
begin
  AssertRefused(InProc(['  try A except end; try B except end;']),
    _(R_EXC_MANY));
end;

{$IFNDEF FPC}

// ---- Adapter und echter Detektor ----

procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TEmptyExceptDetector2.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_s002_', ASource, fkEmptyExcept, RunDetector);
end;

// Dasselbe in der Form von TDetectFunc (FixAllWith).
function DetectKind(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := DetectSource('rdx_s002_', ASource, AKind, RunDetector);
end;

// Fund fuer Fund ueber den Einstieg der Tabelle (TRdxFixTable.FixFor), nach
// jeder Ersetzung neu gemeldet, bis der Detektor schweigt.
function FixAll(const ASource: string): string;
begin
  Result := FixAllWith(ASource, fkEmptyExcept, DetectKind);
end;

// Der erste Fund wird ueber die Tabelle abgelehnt, mit AReason.
procedure AssertDetectorNoHelp(const ASource, AReason: string);
var
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  Seen := Detect(ASource);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet');
  O := PlanFixIn(ASource, 't.pas', fkEmptyExcept, Seen[0]);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(AReason, O.Reason);
end;

procedure TTestRdxEmptyExceptFixDetector.Sca002_Adapter_Outcome;
var
  S    : string;
  F    : TLeakFinding;
  O    : TRdxFixOutcome;
  SL   : TStringList;
  Seen : TSeen;
begin
  S := InProc(['  try', '    Work;', '  except', '  end;']);
  SL := TStringList.Create;
  F := nil;
  try
    F := TLeakFinding.New('t.pas', '', LineOf(S, 'except'),
      'Empty except block', fkEmptyExcept);
    // Ohne Zeilen: kein Puffer.
    O := TRdxFixTable.FixFor(nil, nil, F, nil);
    Assert.IsFalse(O.Enabled);
    Assert.AreEqual(MsgNoFileOpen, O.Reason);
    SL.Text := S;
    O := TRdxFixTable.FixFor(nil, SL, F, nil);
    Assert.IsTrue(O.Enabled, O.Reason);
    Assert.AreEqual(InProc(['  try', '    Work;', '  except', '    raise;',
      '  end;']), Apply(S, O.Edits));
  finally
    F.Free;
    SL.Free;
  end;
  // Die Kennzeichnung "aendert das Verhalten" setzt erst die Tabellenzeile
  // (FixFor) - der Adapter laesst sie auf dem Default.
  Seen.Line := LineOf(S, 'except');
  Seen.Msg := 'Empty except block';
  Seen.Variant := '';
  O := PlanFixIn(S, 't.pas', fkEmptyExcept, Seen);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.IsTrue(O.ChangesBehavior, 'raise aendert das Verhalten');
end;

procedure TTestRdxEmptyExceptFixDetector.Sca002_Detector_RoundTrip;
var
  Source : string;
begin
  // Ein leeres except im inneren try (das aeussere hat eine Anweisung) und
  // eines inline - der Detektor meldet beide, nach der Hilfe keines mehr.
  Source := InProc(['  try', '    try', '      Work;', '    except',
    '    end;', '  except', '    Log;', '  end;', '  try Other except end;']);
  Assert.AreEqual<Integer>(2, Length(Detect(Source)));
  Assert.AreEqual(
    InProc(['  try', '    try', '      Work;', '    except', '      raise;',
      '    end;', '  except', '    Log;', '  end;',
      '  try Other except raise; end;']),
    FixAll(Source));
end;

procedure TTestRdxEmptyExceptFixDetector.Sca002_Detector_CatalogExample;
var
  Meta   : TRuleMeta;
  Bad    : string;
  Source : string;
begin
  // Das Beispiel 'bad' des Katalogs ('try DoStuff except end;').
  Meta := TRuleCatalog.GetRuleCanonical(fkEmptyExcept);
  Bad := CatalogText(Meta.BadExample);
  Assert.IsTrue(Pos('except end', Bad) > 0, Bad);
  Source := InProc(['  ' + Bad]);
  Assert.AreEqual<Integer>(1, Length(Detect(Source)));
  Assert.AreEqual(
    InProc(['  ' + StringReplace(Bad, 'except end', 'except raise; end', [])]),
    FixAll(Source));
end;

procedure TTestRdxEmptyExceptFixDetector.Sca002_Detector_Comment_NoHelp;
begin
  // Der Detektor meldet auch einen Block mit nur einem Kommentar - die Hilfe
  // nicht: der Kommentar ist Absicht.
  AssertDetectorNoHelp(
    InProc(['  try', '    Work;', '  except', '    // ignore', '  end;']),
    _(R_EXC_COMMENT));
end;

procedure TTestRdxEmptyExceptFixDetector.Sca002_Detector_StraySemicolon_NoHelp;
begin
  // 'except;' meldet der Detektor ebenfalls (leerer Handler), die Hilfe
  // bedient nur die eindeutige Form.
  AssertDetectorNoHelp(
    InProc(['  try', '    Work;', '  except;', '  end;']),
    _(R_EXC_NOT_EMPTY));
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxEmptyExceptFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxEmptyExceptFixDetector);
  {$ENDIF}

end.
