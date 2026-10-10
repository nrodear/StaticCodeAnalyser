unit uTestRdxBufferMath;

// Review reDelphiX 2026-10-07, Major 6 und 3 (Editorhilfen Stufe 0): die
// Rechnung Zeile/Zeichen-Spalte -> Byte im UTF-8-Editorpuffer und die
// Pruefung aller Ersetzungen einer Aktion. Die Faelle stehen im Review:
// Umlaut, Tabulatoren, Surrogatpaar und kombinierendes Zeichen VOR dem
// Bereich, je mit CRLF, LF und einsamem CR.
//
// Der Writer der IDE wird hier nachgestellt (ApplyPlan): Praefix kopieren,
// Bereich verwerfen, neuen Text einfuegen, aufsteigend - so prueft der Test
// das Ergebnis, nicht nur die Offsets.
//
// Dazu die SmallInt-Grenze der Editor-Markierung (Nit 8: Spalte und
// Byte-Praefix bis 32767) und die Wahl des Textes (Nit 24: offen, aber
// leer oder nicht lesbar, sperrt - kein stiller Rueckfall auf die Platte).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxBufferMath = class
  public
    [Test] procedure LineStarts_CrLfLfCr;
    [Test] procedure BufferEol_FirstTerminatorWins;
    // Major 6: Byte-Ausschnitt = Bereichstext fuer alle Sonderzeichen
    [Test] procedure Offsets_SpecialCharsBeforeSpan_AllEols;
    // Major 3: alles oder nichts, aufsteigend, Ueberlappung abgelehnt
    [Test] procedure Plan_SortsAscendingAndApplies;
    [Test] procedure Plan_OneMismatch_NothingPlanned;
    [Test] procedure Plan_Overlap_Rejected;
    [Test] procedure Plan_NewTextGetsBufferEol;
    [Test] procedure Plan_EmptyExpected_Rejected;
    [Test] procedure Plan_EmptyBuffer_Rejected;
    // Nit 8: SmallInt-Spalten der Editor-Markierung
    [Test] procedure EditorColumn_AsciiLimit;
    [Test] procedure EditorColumn_MultiByteLimit;
    [Test] procedure SpanFitsEditor_BothEnds;
    // Nit 24: offener Puffer schlaegt die Platte, auch leer
    [Test] procedure ChooseTextSource_OpenBufferWins;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uRefactorInfo, uRdxBufferMath;

function Bytes(const S: string): TBytes;
begin
  Result := TEncoding.UTF8.GetBytes(S);
end;

function Edit(ALine, AStartCol, AEndCol: Integer;
  const AExpected, ANew: string): TRdxEdit;
begin
  Result.Span     := TRefactorSpan.Make('t', ALine, AStartCol, ALine, AEndCol);
  Result.Expected := AExpected;
  Result.NewText  := ANew;
end;

// Der IOTAEditWriter in klein - uRdxBufferMath.ApplyByteEdits, als Text.
function ApplyPlan(const ABytes: TBytes; const APlan: TArray<TRdxByteEdit>): string;
begin
  Result := TEncoding.UTF8.GetString(ApplyByteEdits(ABytes, APlan));
end;

procedure TTestRdxBufferMath.LineStarts_CrLfLfCr;
var
  L : TList<Integer>;
begin
  L := TList<Integer>.Create;
  try
    LineStartsOf(Bytes('a'#13#10'b'#10'c'#13'd'), L);
    Assert.AreEqual<Integer>(4, L.Count);
    Assert.AreEqual<Integer>(0, L[0]);
    Assert.AreEqual<Integer>(3, L[1]);
    Assert.AreEqual<Integer>(5, L[2]);
    Assert.AreEqual<Integer>(7, L[3]);
  finally
    L.Free;
  end;
end;

procedure TTestRdxBufferMath.BufferEol_FirstTerminatorWins;
begin
  Assert.AreEqual(#13#10, BufferEol(Bytes('a'#13#10'b'#10)));
  Assert.AreEqual(#10, BufferEol(Bytes('a'#10'b'#13#10)));
  Assert.AreEqual(#13, BufferEol(Bytes('a'#13'b')));
  Assert.AreEqual(#13#10, BufferEol(Bytes('ohne Umbruch')), 'Vorgabe CRLF');
end;

procedure TTestRdxBufferMath.Offsets_SpecialCharsBeforeSpan_AllEols;
const
  // Je Zeile steht 'r' (Ziel) hinter einem Sonderfall.
  CASES : array[0..3] of string = (
    'x := ''' + #$00E4 + ''' ; r := a + b;',        // Umlaut (2 Bytes)
    #9#9'r := a + b;',                               // Tabulatoren
    'c := ''' + #$D83D#$DE00 + ''' ; r := d;',       // Surrogatpaar (4 Bytes)
    'e' + #$0301 + ' := 1; r := f;');                // kombinierendes Zeichen
  EOLS : array[0..2] of string = (#13#10, #10, #13);
var
  c, e   : Integer;
  Src    : string;
  B      : TBytes;
  Col    : Integer;
  Plan   : TArray<TRdxByteEdit>;
  Err    : string;
  Slice  : string;
  Ok     : Boolean;
begin
  for e := 0 to High(EOLS) do
    for c := 0 to High(CASES) do
    begin
      {$IFDEF FPC}
      // FPC 3.2.2: TStringList ist ANSI - Surrogatpaar und kombinierendes
      // Zeichen werden beim Zuweisen an .Text zu '?', die Zeilen passen
      // dann nicht mehr zu den Pufferbytes. Eine Grenze des Pruefstands,
      // nicht des Codes (Delphi: TStringList ist Unicode, alle vier Faelle).
      if c >= 2 then Continue;
      {$ENDIF}
      // Zielzeile ist Zeile 2, davor und danach je eine Zeile
      Src := 'unit u;' + EOLS[e] + CASES[c] + EOLS[e] + 'end.';
      B := Bytes(Src);
      Col := Pos('r :=', CASES[c]);
      // Ergebnis erst in eine Variable: die Meldung soll Err NACH dem
      // Aufruf zeigen (Argumentreihenfolge ist nicht festgelegt).
      Ok := PlanByteEdits(B, [Edit(2, Col, Col + 1, 'r', 'q')], Plan, Err);
      Assert.IsTrue(Ok, Format('Fall %d/%d: %s', [c, e, Err]));
      Slice := TEncoding.UTF8.GetString(B, Plan[0].StartPos,
        Plan[0].EndPos - Plan[0].StartPos);
      Assert.AreEqual('r', Slice, Format('Fall %d/%d: Byte-Ausschnitt', [c, e]));
      Assert.AreEqual(StringReplace(Src, 'r :=', 'q :=', []), ApplyPlan(B, Plan),
        Format('Fall %d/%d: Ergebnis', [c, e]));
    end;
end;

procedure TTestRdxBufferMath.Plan_SortsAscendingAndApplies;
var
  B    : TBytes;
  Plan : TArray<TRdxByteEdit>;
  Err  : string;
begin
  // Zwei Ersetzungen, absichtlich absteigend uebergeben (Kette unten,
  // uses oben - wie Format() bilden mit System.SysUtils).
  B := Bytes('uses A;'#13#10's := x + y;');
  Assert.IsTrue(PlanByteEdits(B,
    [Edit(2, 6, 11, 'x + y', 'Format(''%s%s'', [x, y])'),
     Edit(1, 6, 7, 'A', 'A, B')], Plan, Err), Err);
  Assert.AreEqual<Integer>(2, Length(Plan));
  Assert.IsTrue(Plan[0].StartPos < Plan[1].StartPos, 'aufsteigend');
  Assert.AreEqual('uses A, B;'#13#10's := Format(''%s%s'', [x, y]);',
    ApplyPlan(B, Plan));
end;

procedure TTestRdxBufferMath.Plan_OneMismatch_NothingPlanned;
var
  B    : TBytes;
  Plan : TArray<TRdxByteEdit>;
  Err  : string;
begin
  B := Bytes('uses A;'#13#10's := x + y;');
  Assert.IsFalse(PlanByteEdits(B,
    [Edit(1, 6, 7, 'A', 'A, B'),
     Edit(2, 6, 11, 'x - y', 'z')], Plan, Err),
    'der zweite Bereich passt nicht');
  Assert.AreEqual<Integer>(0, Length(Plan), 'auch der erste wird nicht geplant');
  Assert.IsTrue(Pos('weicht vom Scan ab', Err) > 0, Err);
end;

procedure TTestRdxBufferMath.Plan_Overlap_Rejected;
var
  B    : TBytes;
  Plan : TArray<TRdxByteEdit>;
  Err  : string;
begin
  B := Bytes('s := x + y;');
  Assert.IsFalse(PlanByteEdits(B,
    [Edit(1, 6, 11, 'x + y', 'z'), Edit(1, 10, 11, 'y', 'w')], Plan, Err));
  Assert.IsTrue(Pos('ueberlappen', Err) > 0, Err);
end;

procedure TTestRdxBufferMath.Plan_NewTextGetsBufferEol;
var
  B    : TBytes;
  Plan : TArray<TRdxByteEdit>;
  Err  : string;
begin
  B := Bytes('a := 1;'#13#10'b := 2;');
  Assert.IsTrue(PlanByteEdits(B, [Edit(2, 1, 2, 'b', '// x'#10'b')], Plan, Err), Err);
  Assert.AreEqual('// x'#13#10'b', Plan[0].NewText);
  Assert.AreEqual('a := 1;'#13#10'// x'#13#10'b := 2;', ApplyPlan(B, Plan));
end;

procedure TTestRdxBufferMath.Plan_EmptyExpected_Rejected;
var
  B    : TBytes;
  Plan : TArray<TRdxByteEdit>;
  Err  : string;
begin
  B := Bytes('a := 1;');
  Assert.IsFalse(PlanByteEdits(B, [Edit(1, 1, 2, '', 'x')], Plan, Err),
    'blind einfuegen ist nicht erlaubt - immer gegen Text pruefen');
  Assert.IsFalse(PlanByteEdits(B, nil, Plan, Err), 'keine Ersetzung');
end;

procedure TTestRdxBufferMath.Plan_EmptyBuffer_Rejected;
var
  Plan : TArray<TRdxByteEdit>;
  Err  : string;
begin
  // Ein geleerter Editor-Puffer kommt als 0 Bytes (Nit 24): abgelehnt mit
  // Zeilenzahl, nicht mit einer Ausnahme.
  Assert.IsFalse(PlanByteEdits(nil, [Edit(1, 1, 2, 'a', 'b')], Plan, Err));
  Assert.IsTrue(Pos('0 Zeilen', Err) > 0, Err);
  Assert.AreEqual<Integer>(0, Length(Plan));
end;

procedure TTestRdxBufferMath.EditorColumn_AsciiLimit;
var
  L : string;
begin
  L := StringOfChar('a', 40000);
  Assert.IsTrue(EditorColumnFits(L, 1), 'Zeilenanfang');
  Assert.IsTrue(EditorColumnFits(L, EDITOR_MAX_COLUMN),
    'Praefix 32766 Bytes, Anzeigespalte 32767');
  Assert.IsFalse(EditorColumnFits(L, EDITOR_MAX_COLUMN + 1),
    'Spalte 32768 passt nicht in SmallInt');
  Assert.IsFalse(EditorColumnFits(L, 0), 'Spalte 0 gibt es nicht');
  Assert.IsTrue(EditorColumnFits('abc', 4), 'hinter dem letzten Zeichen');
end;

procedure TTestRdxBufferMath.EditorColumn_MultiByteLimit;
var
  L : string;
begin
  // Umlaut: 2 UTF-8-Bytes je Zeichen - die Byte-Grenze kommt bei der
  // halben Zeichen-Spalte.
  L := StringOfChar(#$00E4, 20000);
  Assert.AreEqual<Integer>(32766, Utf8PrefixLength(L, 16384));
  Assert.AreEqual<Integer>(0, Utf8PrefixLength(L, 1), 'kein Praefix');
  Assert.IsTrue(EditorColumnFits(L, 16384), '16383 Zeichen = 32766 Bytes');
  Assert.IsFalse(EditorColumnFits(L, 16385), '16384 Zeichen = 32768 Bytes');
  Assert.IsFalse(EditorColumnFits(L, 20000), 'Spalte passt, Bytes nicht');
end;

procedure TTestRdxBufferMath.SpanFitsEditor_BothEnds;
var
  L : TStringList;
begin
  L := TStringList.Create;
  try
    L.Add('kurz := 1;');
    L.Add(StringOfChar('a', 40000));
    Assert.IsTrue(SpanFitsEditor(L, TRefactorSpan.Make('t', 1, 1, 1, 5)),
      'kurze Zeile');
    Assert.IsTrue(SpanFitsEditor(L, TRefactorSpan.Make('t', 1, 1, 2, 10)),
      'Ende vorn in der langen Zeile');
    Assert.IsFalse(SpanFitsEditor(L, TRefactorSpan.Make('t', 2, 1, 2, 33000)),
      'Ende hinter Spalte 32767');
    Assert.IsFalse(
      SpanFitsEditor(L, TRefactorSpan.Make('t', 2, 33000, 2, 33001)),
      'Anfang hinter Spalte 32767');
    Assert.IsFalse(SpanFitsEditor(L, TRefactorSpan.Make('t', 2, 1, 3, 2)),
      'Ende hinter der letzten Zeile');
  finally
    L.Free;
  end;
end;

procedure TTestRdxBufferMath.ChooseTextSource_OpenBufferWins;
begin
  Assert.IsTrue(ChooseTextSource(True, True, 'unit u;') = txBuffer,
    'offen und gelesen');
  Assert.IsTrue(ChooseTextSource(False, False, '') = txDisk, 'nicht offen');
  Assert.IsTrue(ChooseTextSource(True, True, '') = txBlocked,
    'offen, aber leer - nicht die Platte');
  Assert.IsTrue(ChooseTextSource(True, False, '') = txBlocked,
    'offen, aber nicht lesbar');
  Assert.IsTrue(ChooseTextSource(True, False, 'Rest') = txBlocked,
    'Lesefehler zaehlt, auch mit Teiltext');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxBufferMath);

end.
