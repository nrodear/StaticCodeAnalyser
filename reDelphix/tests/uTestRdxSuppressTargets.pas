unit uTestRdxSuppressTargets;

// Review reDelphix R1 (Quick-Fix-Modul, 2026-10-15): die Ziele eines
// Zeilen-Markers wie im Core (uSuppression.BuildMap: naechste nicht-leere
// Zeile UND naechste Code-Zeile, Kommentarzeile = '//'-Zeile) in den
// Unterdrueck-Hilfen.
//   * R1-01: SCA165 prueft nur das Code-Ziel. RemoveMarker entfernte darum
//     den Marker, den "Hier unterdruecken" ueber einer TODO-Zeile gesetzt
//     hatte - der Fund kam zurueck (Kreislauf, Fixture cyc0..cyc2 des
//     Pruefers). Jetzt gesperrt, wenn eine Kommentarzeile vor dem Code
//     sein Ziel ist; Block-Kommentar-Zeilen sind fuer den Core Code.
//   * R1-03: auf einer Kommentarzeile schob LineMarker eine neue Zeile
//     zwischen einen Marker und sein Kommentar-Ziel (Leerzeile dazwischen)
//     - dessen Art kam zurueck. Jetzt wird der Marker darueber erweitert,
//     ein nicht erweiterbarer sperrt.
// Jede Ersetzung laeuft durch PlanByteEdits und ApplyByteEdits (CRLF wie im
// Editor).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxSuppressTargets = class
  public
    // R1-01: RemoveMarker
    [Test] procedure RemoveMarker_CommentTarget_Refused;
    [Test] procedure RemoveMarker_CommentTargetAcrossBlank_Refused;
    [Test] procedure RemoveMarker_BraceCommentTarget_Offered;
    [Test] procedure RemoveMarker_TrailingMarkerCommentTarget_Refused;
    [Test] procedure RemoveMarker_Stacked_UpperRefusedLowerOffered;
    [Test] procedure RemoveMarker_FileMarkerAboveComment_Offered;
    [Test] procedure RemoveMarker_LineMarkerAtEnd_Offered;
    [Test] procedure RoundTrip_TodoLine_NoPingPong;
    // R1-03: LineMarker auf einer Kommentarzeile
    [Test] procedure LineMarker_CommentLine_ExtendsAcrossBlank;
    [Test] procedure LineMarker_CommentLine_KindListedAcrossBlank;
    [Test] procedure LineMarker_CommentLine_AllMarkerAbove_Refused;
    [Test] procedure LineMarker_CommentLine_TrailingMarkerAbove_Refused;
    [Test] procedure LineMarker_CommentLine_PlainCommentAbove_Inserts;
    [Test] procedure LineMarker_CommentLine_FileMarkerAbove_Inserts;
    [Test] procedure LineMarker_CommentLine_MarkerInBlockComment_Inserts;
    [Test] procedure LineMarker_CodeLine_MarkerAcrossBlank_Inserts;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxBufferMath, uRdxSuppress;

const
  EOL  = #13#10;
  // Zeilen 1..6 jeder Fixture; die Faelle folgen ab Zeile 7.
  HEAD = 'unit u;' + EOL + 'interface' + EOL + 'implementation' + EOL
    + 'procedure P(var X: Integer);' + EOL + 'begin' + EOL + '  X := 0;' + EOL;
  TAIL = 'end;' + EOL + 'end.';
  TODO_LINE = '  // TODO: Grenzwert pruefen';

// HEAD + die Zeilen ab 7 (je mit EOL) + TAIL.
function Src(const ALines: array of string): string;
var
  L : TStringList;
  i : Integer;
begin
  L := TStringList.Create;
  try
    L.LineBreak := EOL;
    for i := 0 to High(ALines) do
      L.Add(ALines[i]);
    Result := HEAD + L.Text + TAIL;
  finally
    L.Free;
  end;
end;

// Wendet AEdit auf ASource an (wie der Editor) und liefert den neuen Text.
function Apply(const ASource: string; const AEdit: TRdxEdit): string;
var
  Bytes : TBytes;
  Plan  : TArray<TRdxByteEdit>;
  Edits : TArray<TRdxEdit>;
  Err   : string;
begin
  Bytes := TEncoding.UTF8.GetBytes(ASource);
  SetLength(Edits, 1);
  Edits[0] := AEdit;
  Assert.IsTrue(PlanByteEdits(Bytes, Edits, Plan, Err), Err);
  Result := TEncoding.UTF8.GetString(ApplyByteEdits(Bytes, Plan));
end;

// RemoveMarker fuer AMarkerLine von ASource: False mit einem Grund, der
// AReasonPart enthaelt.
procedure ExpectRemoveRefused(const ASource: string; AMarkerLine: Integer;
  const AReasonPart: string);
var
  L : TStringList;
  E : TRdxEdit;
  R : string;
begin
  L := TStringList.Create;
  try
    L.Text := ASource;
    Assert.IsFalse(TRdxSuppress.RemoveMarker(L, AMarkerLine, E, R),
      'Marker in Zeile ' + IntToStr(AMarkerLine) + ' nicht entfernen');
    Assert.IsTrue(Pos(AReasonPart, R) > 0, R);
  finally
    L.Free;
  end;
end;

// RemoveMarker fuer AMarkerLine von ASource: angeboten, Ergebnis AExpected.
procedure ExpectRemoved(const ASource: string; AMarkerLine: Integer;
  const AExpected: string);
var
  L : TStringList;
  E : TRdxEdit;
  R : string;
begin
  L := TStringList.Create;
  try
    L.Text := ASource;
    Assert.IsTrue(TRdxSuppress.RemoveMarker(L, AMarkerLine, E, R), R);
    Assert.AreEqual(AExpected, Apply(ASource, E));
  finally
    L.Free;
  end;
end;

// LineMarker fuer ALine von ASource: False mit einem Grund, der
// AReasonPart enthaelt.
procedure ExpectLineRefused(const ASource: string; ALine: Integer;
  const AKind, AReasonPart: string);
var
  L : TStringList;
  E : TRdxEdit;
  R : string;
begin
  L := TStringList.Create;
  try
    L.Text := ASource;
    Assert.IsFalse(TRdxSuppress.LineMarker(L, ALine, AKind, E, R),
      'kein Marker fuer Zeile ' + IntToStr(ALine));
    Assert.IsTrue(Pos(AReasonPart, R) > 0, R);
  finally
    L.Free;
  end;
end;

// LineMarker fuer ALine von ASource: angeboten, liefert den neuen Text.
function LineMarked(const ASource: string; ALine: Integer;
  const AKind: string): string;
var
  L : TStringList;
  E : TRdxEdit;
  R : string;
begin
  L := TStringList.Create;
  try
    L.Text := ASource;
    Assert.IsTrue(TRdxSuppress.LineMarker(L, ALine, AKind, E, R), R);
    Result := Apply(ASource, E);
  finally
    L.Free;
  end;
end;

procedure TTestRdxSuppressTargets.RemoveMarker_CommentTarget_Refused;
begin
  // Fixture cyc1 des Pruefers: der Marker unterdrueckt TodoComment auf der
  // TODO-Zeile, der Core meldet ihn trotzdem (SCA165) - bis R1-01 entfernte
  // die Hilfe ihn, und der Fund war zurueck.
  ExpectRemoveRefused(Src(['  // noinspection TodoComment', TODO_LINE,
    '  X := 2;']), 7, 'Kommentarzeile 8');
end;

procedure TTestRdxSuppressTargets.RemoveMarker_CommentTargetAcrossBlank_Refused;
begin
  // Leerzeilen zaehlen nicht: die TODO-Zeile bleibt die naechste nicht-leere.
  ExpectRemoveRefused(Src(['  // noinspection TodoComment', '', TODO_LINE,
    '  X := 2;']), 7, 'Kommentarzeile 9');
end;

procedure TTestRdxSuppressTargets.RemoveMarker_BraceCommentTarget_Offered;
begin
  // Gegenprobe (Fixture f2): eine Zeile, die mit '{' beginnt, ist fuer den
  // Core eine Code-Zeile (IsCommentOnlyLine kennt nur '//') - dort
  // verbraucht er den Marker, SCA165 ist also echt.
  ExpectRemoved(Src(['  // noinspection TodoComment',
    '  { TODO: Grenzwert pruefen }', '  X := 2;']), 7,
    Src(['  { TODO: Grenzwert pruefen }', '  X := 2;']));
end;

procedure TTestRdxSuppressTargets.RemoveMarker_TrailingMarkerCommentTarget_Refused;
begin
  // Auch ein Marker hinter Code zielt auf die naechsten Zeilen.
  ExpectRemoveRefused(Src(['  X := 1; // noinspection TodoComment', TODO_LINE,
    '  X := 2;']), 7, 'Kommentarzeile 8');
end;

procedure TTestRdxSuppressTargets.RemoveMarker_Stacked_UpperRefusedLowerOffered;
var
  S : string;
begin
  // Dem oberen Marker ist die Markerzeile darunter die naechste nicht-leere
  // Zeile - eine Kommentarzeile; lieber ablehnen. Der untere zielt allein
  // auf den Code.
  S := Src(['  // noinspection MemoryLeak', '  // noinspection FormatMismatch',
    '  L := TStringList.Create;']);
  ExpectRemoveRefused(S, 7, 'Kommentarzeile 8');
  ExpectRemoved(S, 8, Src(['  // noinspection MemoryLeak',
    '  L := TStringList.Create;']));
end;

procedure TTestRdxSuppressTargets.RemoveMarker_FileMarkerAboveComment_Offered;
begin
  // Ein Datei-Marker hat kein Zeilenziel.
  ExpectRemoved('unit u;' + EOL + '// noinspection-file TooLongLine' + EOL
    + '// Kopfkommentar' + EOL + 'interface' + EOL + 'end.', 2,
    'unit u;' + EOL + '// Kopfkommentar' + EOL + 'interface' + EOL + 'end.');
end;

procedure TTestRdxSuppressTargets.RemoveMarker_LineMarkerAtEnd_Offered;
begin
  // Ohne Folgezeile kein Ziel - der Marker wirkt nirgends.
  ExpectRemoved('unit u;' + EOL + 'end.' + EOL + '// noinspection Foo', 3,
    'unit u;' + EOL + 'end.');
end;

procedure TTestRdxSuppressTargets.RoundTrip_TodoLine_NoPingPong;
var
  S : string;
begin
  // Der Kreislauf aus R1-01 ueber den Schreibweg: "Hier unterdruecken" auf
  // der TODO-Zeile, danach wird der neue Marker nicht als wirkungslos
  // entfernt.
  S := LineMarked(Src([TODO_LINE, '  X := 2;']), 7, 'TodoComment');
  Assert.AreEqual(Src(['  // noinspection TodoComment', TODO_LINE,
    '  X := 2;']), S);
  ExpectRemoveRefused(S, 7, 'Kommentarzeile 8');
end;

procedure TTestRdxSuppressTargets.LineMarker_CommentLine_ExtendsAcrossBlank;
begin
  // Fixture sup_before des Pruefers: eine neue Zeile ueber der TODO-Zeile
  // nahm dem Marker in Zeile 7 sein Ziel, TodoComment kam zurueck. Jetzt
  // bekommt der Marker darueber die Art und traegt beide.
  Assert.AreEqual(Src(['  // noinspection CommentedOutCode, TodoComment', '',
    '  // TODO: X := X + 1; Inc(X); Foo(X);', '  X := 2;']),
    LineMarked(Src(['  // noinspection TodoComment', '',
    '  // TODO: X := X + 1; Inc(X); Foo(X);', '  X := 2;']), 9,
    'CommentedOutCode'));
end;

procedure TTestRdxSuppressTargets.LineMarker_CommentLine_KindListedAcrossBlank;
begin
  ExpectLineRefused(Src(['  // noinspection TodoComment', '', TODO_LINE,
    '  X := 2;']), 9, 'TodoComment', 'schon da');
end;

procedure TTestRdxSuppressTargets.LineMarker_CommentLine_AllMarkerAbove_Refused;
begin
  // 'All' laesst sich nicht erweitern, und eine Zeile dazwischen naehme ihm
  // die TODO-Zeile (unterdrueckte Funde dort kaemen zurueck).
  ExpectLineRefused(Src(['  // noinspection All', TODO_LINE, '  X := 2;']), 8,
    'HardcodedSecret', 'Zeile 7');
end;

procedure TTestRdxSuppressTargets.LineMarker_CommentLine_TrailingMarkerAbove_Refused;
begin
  ExpectLineRefused(Src(['  X := 1; // noinspection TodoComment', '',
    '  // TODO: X := 1;', '  X := 2;']), 9, 'CommentedOutCode', 'Zeile 7');
end;

procedure TTestRdxSuppressTargets.LineMarker_CommentLine_PlainCommentAbove_Inserts;
begin
  // Gegenprobe: ein Kommentar ohne Marker darueber - wie bisher eine Zeile.
  Assert.AreEqual(Src(['  // Erklaerung', '  // noinspection TodoComment',
    TODO_LINE, '  X := 2;']),
    LineMarked(Src(['  // Erklaerung', TODO_LINE, '  X := 2;']), 8,
    'TodoComment'));
end;

procedure TTestRdxSuppressTargets.LineMarker_CommentLine_FileMarkerAbove_Inserts;
begin
  // Ein Datei-Marker hat kein Zeilenziel, das eine neue Zeile verschoebe.
  Assert.AreEqual(Src(['  // noinspection-file TooLongLine',
    '  // noinspection TodoComment', TODO_LINE, '  X := 2;']),
    LineMarked(Src(['  // noinspection-file TooLongLine', TODO_LINE,
    '  X := 2;']), 8, 'TodoComment'));
end;

procedure TTestRdxSuppressTargets.LineMarker_CommentLine_MarkerInBlockComment_Inserts;
begin
  // Der "Marker" darueber steht in einem Block-Kommentar - fuer den Core
  // keiner (ParseMarkerLine), also kein Ziel, das verloren ginge.
  Assert.AreEqual(Src(['  { Notiz:', '  // noinspection Foo }',
    '  // noinspection TodoComment', TODO_LINE, '  X := 2;']),
    LineMarked(Src(['  { Notiz:', '  // noinspection Foo }', TODO_LINE,
    '  X := 2;']), 9, 'TodoComment'));
end;

procedure TTestRdxSuppressTargets.LineMarker_CodeLine_MarkerAcrossBlank_Inserts;
begin
  // Gegenprobe Code-Zeile: das Code-Ziel des alten Markers bleibt, der Core
  // vereinigt gestapelte Marker dort - wie bisher eine eigene Zeile.
  Assert.AreEqual(Src(['  // noinspection TodoComment', '',
    '  // noinspection MagicNumber', '  X := 2;']),
    LineMarked(Src(['  // noinspection TodoComment', '', '  X := 2;']), 9,
    'MagicNumber'));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxSuppressTargets);

end.
