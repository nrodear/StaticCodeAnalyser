unit uTestUninitVarPerfQ1;

// Tests fuer SCA166 (TUninitVarDetector) zu den Randfaellen des Tempo-
// Umbaus Charge Q1 (2026-10-25). Der Umbau ist verhaltensneutral; diese
// Tests sind Wachen an genau den Stellen, an denen eine falsche Umsetzung
// Funde bewegen wuerde (geteilte Datei-Code-Sicht, asm-Pruefung auf dem
// Strip-Array, Vorfilter, Kandidatenzeilen der @-/with-Scans, Signatur-
// index). Die Erwartungen sind am Altstand gemessen (Exe vom 2026-10-25,
// dieselben Quellen).
//
// JEDER Fall laeuft zweimal: ohne Prozess-Text-Cache (AcquireLines laedt
// je Aufruf neu -> jede Methode strippt selbst, der Altweg) und mit einem
// frischen Cache (AnalyzeUnit und AnalyzeMethod sehen DIESELBE Zeilen-
// Instanz -> die Datei-Code-Sicht wird geteilt). Beide Laeufe muessen
// dieselben SCA166-Funde liefern. Jede Quelle traegt eine Wache (Guard:
// Amount wird gelesen, nie geschrieben), damit "kein Fund" nicht still
// durch einen Totalausfall gruen wird.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestUninitVarPerfQ1 = class
  public
    [Test] procedure BlockCommentOpenAtHeader_FreshStripSemanticsKept;
    [Test] procedure ClosedBlockCommentsBefore_SharedStrip_ExactLines;
    [Test] procedure CommentEndingOnSecondHeader_BothMethodsReported;
    [Test] procedure UpperCaseAsmBlock_SkipsMethod;
    [Test] procedure AsmOnlyInComments_MethodStillAnalysed;
    [Test] procedure ConditionWithoutParen_RegistersNoWrite;
    [Test] procedure ConditionCallArg_StillWrites;
    [Test] procedure AtScan_SecondAtLineIsFirstWrite;
    [Test] procedure WithScan_SecondWithLineIsFirstWrite;
    [Test] procedure MultiLineSignature_HeadlessCall_Writes;
    [Test] procedure ReadInsideOtherIdent_IsNoFill;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uFileTextCache,
  uTestFindingHelper;

// SCA166-Funde als Text (je Fund "Zeile: Meldung" + LF, Fundreihenfolge).
// AWithCache: frischer Prozess-Text-Cache fuer die Dauer des Laufs, sonst
// gar keiner; der vorherige Zustand wird in jedem Fall wiederhergestellt.
function Sca166Text(const ASrc: string; AWithCache: Boolean;
  out ACount: Integer): string;
var
  Saved, Tmp : TFileTextCache;
  L : TObjectList<TLeakFinding>;
  F : TLeakFinding;
begin
  Result := '';
  ACount := 0;
  Saved := gFileTextCache;
  if AWithCache then
    Tmp := TFileTextCache.Create
  else
    Tmp := nil;
  gFileTextCache := Tmp;
  try
    L := TFindingHelper.FindingsOfFile(ASrc);
    try
      for F in L do
        if F.Kind = fkUninitVar then
        begin
          Inc(ACount);
          Result := Result + F.LineNumber + ': ' + F.MissingVar + #10;
        end;
    finally
      L.Free;
    end;
  finally
    gFileTextCache := Saved;
    Tmp.Free;
  end;
end;

// Beide Modi, gleiche Funde, erwartete Zahl. Liefert den Fundtext.
function RunBothModes(const ASrc: string; AExpected: Integer;
  const AWhy: string): string;
var
  NoCache, WithCache : string;
  N1, N2 : Integer;
begin
  NoCache   := Sca166Text(ASrc, False, N1);
  WithCache := Sca166Text(ASrc, True, N2);
  Assert.IsTrue(NoCache = WithCache,
    'Mit und ohne Text-Cache dieselben SCA166-Funde (' + AWhy + ')' + #10 +
    'ohne:' + #10 + NoCache + 'mit:' + #10 + WithCache);
  Assert.AreEqual<Integer>(AExpected, N1, AWhy + ' - Funde:' + #10 + NoCache);
  Assert.IsTrue(Pos('Amount is read', NoCache) > 0,
    'Die Wache (Amount) muss gemeldet werden: ' + NoCache);
  Result := NoCache;
end;

procedure AssertReadBeforeWrite(const ASrc, AText, AVar, AReadMarker,
  AWriteMarker: string);
var
  Want : string;
begin
  Want := AVar + ' read on line ' + TFindingHelper.LineOf(ASrc, AReadMarker) +
    ' before its first assignment on line ' +
    TFindingHelper.LineOf(ASrc, AWriteMarker) + '.';
  Assert.IsTrue(Pos(Want, AText) > 0,
    'Erwartet "' + Want + '" in:' + #10 + AText);
end;

procedure TTestUninitVarPerfQ1.BlockCommentOpenAtHeader_FreshStripSemanticsKept;
// Kopfzeile beginnt in einem offenen Blockkommentar: die Datei-Code-Sicht
// darf NICHT genommen werden (AFileFresh = False). Der frische Strip ab
// der Kopfzeile sieht '(*' als Code und blankt den Rest der Methode -
// Altverhalten: Foo ohne Fund. Mit der Datei-Sicht kaeme 'x' dazu.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    '{ note'#13#10 +
    '  (* } function Foo: Integer;'#13#10 +
    'var'#13#10 +
    '  x: Integer;'#13#10 +
    'begin'#13#10 +
    '  Result := x;'#13#10 +
    'end;'#13#10 +
    'function Guard(const S: string): Integer;'#13#10 +
    'var'#13#10 +
    '  Amount: Integer;'#13#10 +
    'begin'#13#10 +
    '  if S = '''' then'#13#10 +
    '    Result := Amount'#13#10 +
    '  else'#13#10 +
    '    Result := 0;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  Txt : string;
begin
  Txt := RunBothModes(SRC, 1, 'BlockCommentOpenAtHeader_FreshStripSemanticsKept');
  Assert.IsTrue(Pos('x is read', Txt) = 0, 'Kein Fund erwartet fuer: x is read' + #10 + Txt);
end;

procedure TTestUninitVarPerfQ1.ClosedBlockCommentsBefore_SharedStrip_ExactLines;
// Zwei geschlossene Mehrzeilen-Kommentare vor der Methode: ab der
// Kopfzeile ist die Datei-Code-Sicht frisch und wird geteilt - Read- und
// Write-Zeile muessen exakt stimmen (Scheibe am richtigen Versatz).
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    '{ a closed'#13#10 +
    '  multi-line comment }'#13#10 +
    '(* and a'#13#10 +
    '   second one *)'#13#10 +
    'procedure P;'#13#10 +
    'var'#13#10 +
    '  v, w: Integer;'#13#10 +
    'begin'#13#10 +
    '  w := v + 1;'#13#10 +
    '  v := 2;'#13#10 +
    '  WriteLn(w, v);'#13#10 +
    'end;'#13#10 +
    'function Guard(const S: string): Integer;'#13#10 +
    'var'#13#10 +
    '  Amount: Integer;'#13#10 +
    'begin'#13#10 +
    '  if S = '''' then'#13#10 +
    '    Result := Amount'#13#10 +
    '  else'#13#10 +
    '    Result := 0;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  Txt : string;
begin
  Txt := RunBothModes(SRC, 2, 'ClosedBlockCommentsBefore_SharedStrip_ExactLines');
  AssertReadBeforeWrite(SRC, Txt, 'v', '  w := v + 1;', '  v := 2;');
end;

procedure TTestUninitVarPerfQ1.CommentEndingOnSecondHeader_BothMethodsReported;
// Ein Kommentar beginnt hinter Methode A und endet auf der Kopfzeile
// von B: A nimmt die geteilte Sicht, B (nicht frisch) den eigenen Strip.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure A;'#13#10 +
    'var'#13#10 +
    '  p: Integer;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(p);'#13#10 +
    'end;'#13#10 +
    '{ trailing remark'#13#10 +
    '  still remark } procedure B;'#13#10 +
    'var'#13#10 +
    '  q: Integer;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(q);'#13#10 +
    'end;'#13#10 +
    'function Guard(const S: string): Integer;'#13#10 +
    'var'#13#10 +
    '  Amount: Integer;'#13#10 +
    'begin'#13#10 +
    '  if S = '''' then'#13#10 +
    '    Result := Amount'#13#10 +
    '  else'#13#10 +
    '    Result := 0;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  Txt : string;
begin
  Txt := RunBothModes(SRC, 3, 'CommentEndingOnSecondHeader_BothMethodsReported');
end;

procedure TTestUninitVarPerfQ1.UpperCaseAsmBlock_SkipsMethod;
// asm-Erkennung liest jetzt das geteilte (gelowerte) Strip-Array statt
// eines zweiten Strips: 'ASM' in Grossbuchstaben ueberspringt weiter.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var'#13#10 +
    '  v: Integer;'#13#10 +
    'begin'#13#10 +
    '  ASM'#13#10 +
    '    mov v, eax'#13#10 +
    '  END;'#13#10 +
    '  WriteLn(v);'#13#10 +
    'end;'#13#10 +
    'function Guard(const S: string): Integer;'#13#10 +
    'var'#13#10 +
    '  Amount: Integer;'#13#10 +
    'begin'#13#10 +
    '  if S = '''' then'#13#10 +
    '    Result := Amount'#13#10 +
    '  else'#13#10 +
    '    Result := 0;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  Txt : string;
begin
  Txt := RunBothModes(SRC, 1, 'UpperCaseAsmBlock_SkipsMethod');
  Assert.IsTrue(Pos('v is read', Txt) = 0, 'Kein Fund erwartet fuer: v is read' + #10 + Txt);
end;

procedure TTestUninitVarPerfQ1.AsmOnlyInComments_MethodStillAnalysed;
// 'asm' nur in {..}, (*..*) und // - kein asm-Block, Fund bleibt.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var'#13#10 +
    '  v: Integer;'#13#10 +
    'begin'#13#10 +
    '  { asm'#13#10 +
    '  }'#13#10 +
    '  (* asm *)'#13#10 +
    '  // asm'#13#10 +
    '  WriteLn(v);'#13#10 +
    'end;'#13#10 +
    'function Guard(const S: string): Integer;'#13#10 +
    'var'#13#10 +
    '  Amount: Integer;'#13#10 +
    'begin'#13#10 +
    '  if S = '''' then'#13#10 +
    '    Result := Amount'#13#10 +
    '  else'#13#10 +
    '    Result := 0;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  Txt : string;
begin
  Txt := RunBothModes(SRC, 2, 'AsmOnlyInComments_MethodStillAnalysed');
end;

procedure TTestUninitVarPerfQ1.ConditionWithoutParen_RegistersNoWrite;
// ProcessCallsInExprText steigt ohne '(' frueh aus: ein Ausdruck ohne
// Call registriert keinen Write - 'if v > 0' bleibt ein Read.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'function F(const S: string): Integer;'#13#10 +
    'var'#13#10 +
    '  v: Integer;'#13#10 +
    'begin'#13#10 +
    '  if v > 0 then'#13#10 +
    '    Result := 1'#13#10 +
    '  else'#13#10 +
    '    Result := 0;'#13#10 +
    'end;'#13#10 +
    'function Guard(const S: string): Integer;'#13#10 +
    'var'#13#10 +
    '  Amount: Integer;'#13#10 +
    'begin'#13#10 +
    '  if S = '''' then'#13#10 +
    '    Result := Amount'#13#10 +
    '  else'#13#10 +
    '    Result := 0;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  Txt : string;
begin
  Txt := RunBothModes(SRC, 2, 'ConditionWithoutParen_RegistersNoWrite');
end;

procedure TTestUninitVarPerfQ1.ConditionCallArg_StillWrites;
// Gegenprobe: mit Call im Ausdruck greift der pessimistic-Write weiter.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'function G(const S: string): Integer;'#13#10 +
    'var'#13#10 +
    '  v: Integer;'#13#10 +
    'begin'#13#10 +
    '  if TryStrToInt(S, v) then'#13#10 +
    '    Result := v'#13#10 +
    '  else'#13#10 +
    '    Result := 0;'#13#10 +
    'end;'#13#10 +
    'function Guard(const S: string): Integer;'#13#10 +
    'var'#13#10 +
    '  Amount: Integer;'#13#10 +
    'begin'#13#10 +
    '  if S = '''' then'#13#10 +
    '    Result := Amount'#13#10 +
    '  else'#13#10 +
    '    Result := 0;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  Txt : string;
begin
  Txt := RunBothModes(SRC, 1, 'ConditionCallArg_StillWrites');
  Assert.IsTrue(Pos('v is read', Txt) = 0, 'Kein Fund erwartet fuer: v is read' + #10 + Txt);
end;

procedure TTestUninitVarPerfQ1.AtScan_SecondAtLineIsFirstWrite;
// @-Scan ueber die Kandidatenzeilen der Methode: zwei @-Zeilen, erst
// die zweite nimmt Buf - die Meldung muss deren Zeile nennen.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var'#13#10 +
    '  Buf, Other: Integer;'#13#10 +
    '  Q: PInteger;'#13#10 +
    'begin'#13#10 +
    '  Other := 0;'#13#10 +
    '  Q := @Other;'#13#10 +
    '  WriteLn(Buf, Q^);'#13#10 +
    '  Q := @Buf;'#13#10 +
    '  Q^ := 1;'#13#10 +
    'end;'#13#10 +
    'function Guard(const S: string): Integer;'#13#10 +
    'var'#13#10 +
    '  Amount: Integer;'#13#10 +
    'begin'#13#10 +
    '  if S = '''' then'#13#10 +
    '    Result := Amount'#13#10 +
    '  else'#13#10 +
    '    Result := 0;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  Txt : string;
begin
  Txt := RunBothModes(SRC, 2, 'AtScan_SecondAtLineIsFirstWrite');
  AssertReadBeforeWrite(SRC, Txt, 'Buf', '  WriteLn(Buf, Q^);', '  Q := @Buf;');
end;

procedure TTestUninitVarPerfQ1.WithScan_SecondWithLineIsFirstWrite;
// with-Scan ueber die Kandidatenzeilen: 'with S' trifft R nicht, erst
// 'with R do' ist die erste Zuweisung.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var'#13#10 +
    '  R, S: TPoint;'#13#10 +
    'begin'#13#10 +
    '  with S do'#13#10 +
    '    X := 0;'#13#10 +
    '  WriteLn(R.X);'#13#10 +
    '  with R do'#13#10 +
    '    X := 1;'#13#10 +
    'end;'#13#10 +
    'function Guard(const S: string): Integer;'#13#10 +
    'var'#13#10 +
    '  Amount: Integer;'#13#10 +
    'begin'#13#10 +
    '  if S = '''' then'#13#10 +
    '    Result := Amount'#13#10 +
    '  else'#13#10 +
    '    Result := 0;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  Txt : string;
begin
  Txt := RunBothModes(SRC, 2, 'WithScan_SecondWithLineIsFirstWrite');
  AssertReadBeforeWrite(SRC, Txt, 'R', '  WriteLn(R.X);', '  with R do');
end;

procedure TTestUninitVarPerfQ1.MultiLineSignature_HeadlessCall_Writes;
// Signaturindex aus der Datei-Code-Sicht, Parameterliste ueber drei
// Zeilen (stueckweise gesammelt): 'var Value' an Position 3 fuellt
// Value im Headless-Muster - kein Fund.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure Decode(const S: string;'#13#10 +
    '  const W: Integer;'#13#10 +
    '  var Value: Integer);'#13#10 +
    'begin'#13#10 +
    '  Value := Length(S) + W;'#13#10 +
    'end;'#13#10 +
    'procedure P(const S: string);'#13#10 +
    'var'#13#10 +
    '  Value: Integer;'#13#10 +
    ''#13#10 +
    '  procedure Helper;'#13#10 +
    '  begin'#13#10 +
    '    WriteLn(''hi'');'#13#10 +
    '  end;'#13#10 +
    ''#13#10 +
    'var'#13#10 +
    '  C: Integer;'#13#10 +
    'begin'#13#10 +
    '  Helper;'#13#10 +
    '  Decode(S, 1, Value);'#13#10 +
    '  C := Value + 1;'#13#10 +
    '  WriteLn(C);'#13#10 +
    'end;'#13#10 +
    'function Guard(const S: string): Integer;'#13#10 +
    'var'#13#10 +
    '  Amount: Integer;'#13#10 +
    'begin'#13#10 +
    '  if S = '''' then'#13#10 +
    '    Result := Amount'#13#10 +
    '  else'#13#10 +
    '    Result := 0;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  Txt : string;
begin
  Txt := RunBothModes(SRC, 1, 'MultiLineSignature_HeadlessCall_Writes');
  Assert.IsTrue(Pos('Value is read', Txt) = 0, 'Kein Fund erwartet fuer: Value is read' + #10 + Txt);
end;

procedure TTestUninitVarPerfQ1.ReadInsideOtherIdent_IsNoFill;
// Read-Fill-Vorfilter 'read': S.Read(Buf, ..) fuellt Buf; 'read' in
// ThreadCount ist kein Fill - N bleibt ein Read vor dem Write.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(S: TStream);'#13#10 +
    'var'#13#10 +
    '  Buf, N: Integer;'#13#10 +
    'begin'#13#10 +
    '  S.Read(Buf, SizeOf(Buf));'#13#10 +
    '  WriteLn(Buf);'#13#10 +
    '  WriteLn(N + ThreadCount);'#13#10 +
    '  N := 1;'#13#10 +
    'end;'#13#10 +
    'function Guard(const S: string): Integer;'#13#10 +
    'var'#13#10 +
    '  Amount: Integer;'#13#10 +
    'begin'#13#10 +
    '  if S = '''' then'#13#10 +
    '    Result := Amount'#13#10 +
    '  else'#13#10 +
    '    Result := 0;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  Txt : string;
begin
  Txt := RunBothModes(SRC, 2, 'ReadInsideOtherIdent_IsNoFill');
  AssertReadBeforeWrite(SRC, Txt, 'N', '  WriteLn(N + ThreadCount);', '  N := 1;');
  Assert.IsTrue(Pos('Buf read', Txt) = 0, 'Kein Fund erwartet fuer: Buf read' + #10 + Txt);
  Assert.IsTrue(Pos('Buf is read', Txt) = 0, 'Kein Fund erwartet fuer: Buf is read' + #10 + Txt);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUninitVarPerfQ1);

end.
