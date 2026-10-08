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

// Der IOTAEditWriter in klein: aufsteigend kopieren, loeschen, einfuegen.
function ApplyPlan(const ABytes: TBytes; const APlan: TArray<TRdxByteEdit>): string;
var
  Pos, i : Integer;
  Out_   : TBytes;
  Ins    : TBytes;
  n      : Integer;
begin
  SetLength(Out_, 0);
  Pos := 0;
  for i := 0 to High(APlan) do
  begin
    n := Length(Out_);
    SetLength(Out_, n + APlan[i].StartPos - Pos);
    if APlan[i].StartPos > Pos then
      Move(ABytes[Pos], Out_[n], APlan[i].StartPos - Pos);
    Ins := TEncoding.UTF8.GetBytes(APlan[i].NewText);
    n := Length(Out_);
    SetLength(Out_, n + Length(Ins));
    if Length(Ins) > 0 then
      Move(Ins[0], Out_[n], Length(Ins));
    Pos := APlan[i].EndPos;
  end;
  n := Length(Out_);
  SetLength(Out_, n + Length(ABytes) - Pos);
  if Length(ABytes) > Pos then
    Move(ABytes[Pos], Out_[n], Length(ABytes) - Pos);
  Result := TEncoding.UTF8.GetString(Out_);
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

initialization
  TDUnitX.RegisterTestFixture(TTestRdxBufferMath);

end.
