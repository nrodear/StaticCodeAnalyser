unit uTestRdxInvisibleCharFix;

// Editorhilfe SCA192 SourceInvisibleChar (uRdxCharEscapeFix,
// InvisibleChar): die unsichtbaren Zeichen der gemeldeten Zeile - im String
// IMMER als #$xxxx geschrieben (nie geloescht: ZWJ gehoert zu Emoji-Folgen,
// der Wert bleibt gleich), im Kommentar geloescht; ein Joiner (U+200C,
// U+200D) im Kommentar neben einem Nicht-ASCII-Zeichen (Emoji, Schrift)
// sperrt.
//   Fixture 1 (Text, ohne Parser und Detektor, FPC-tauglich): String (ZWSP,
//   Word-Joiner, U+FEFF mitten in der Datei, Emoji-ZWJ-Folge, ZWNJ in
//   einer Schrift), Kommentar (ZWSP auch neben Nicht-ASCII, Joiner neben
//   ASCII), Kommentar und String in einer Ersetzung; Gegenproben Joiner in
//   Emoji-Folge und Schrift, Sperre der ganzen Zeile, Code, U+FEFF am
//   Zeilenanfang, Direktive, Kommentar-Form, mehrzeiliger String,
//   verschobene Zeile, Zeichen ausserhalb der Detektor-Menge (NBSP, U+202E).
//   Fixture 2 (nur Delphi): der ECHTE Detektor (uSourceEncoding) meldet,
//   die Hilfe (ueber den Einstieg der Tabelle, TRdxFixTable.FixFor) behebt,
//   bis der Detektor schweigt - bzw. lehnt ab.
// Quelltext reines ASCII: die Zeichen entstehen ueber #$xxxx.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxInvisibleCharFix = class
  public
    [Test] procedure String_Zwsp_Escaped;
    [Test] procedure String_Word_Joiner_And_Mid_Bom_Escaped;
    [Test] procedure String_Emoji_Zwj_Escaped_Value_Kept;
    [Test] procedure String_Zwnj_In_Script_Escaped;
    [Test] procedure Comment_Zwsp_Deleted;
    [Test] procedure Comment_Joiner_Next_To_Ascii_Deleted;
    [Test] procedure Comment_Zwsp_Next_To_Emoji_Deleted;
    [Test] procedure Comment_And_String_One_Edit;
    [Test] procedure Comment_Joiner_In_Emoji_NoHelp;
    [Test] procedure Comment_Joiner_In_Script_NoHelp;
    [Test] procedure Joiner_Blocks_Whole_Line;
    [Test] procedure Code_NoHelp;
    [Test] procedure Bom_At_Line_Start_NoHelp;
    [Test] procedure Directive_NoHelp;
    [Test] procedure Comment_Shape_NoHelp;
    [Test] procedure Multi_Line_String_NoHelp;
    [Test] procedure Moved_Line_NoHelp;
    [Test] procedure Character_Set_Like_Detector;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxInvisibleCharFixDetector = class
  public
    [Test] procedure Detector_String_Then_Comment_RoundTrip;
    [Test] procedure Detector_Emoji_String_RoundTrip;
    [Test] procedure Detector_Emoji_Comment_NoHelp;
    [Test] procedure Detector_Code_NoHelp;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  uRdxBufferMath, uRdxCodeMap, uRdxCharEscapeFix,
  uRdxText,          // _(), MsgMovedSuffix, MsgCheckByHand (E29)
  uTestRdxTextKit    // Apply, NewMap
{$IFNDEF FPC}
  , System.IOUtils, System.Generics.Collections,
  uMethodd12, uSCAConsts, uSourceEncoding,
  uRdxRecipeRunner,  // TRdxFixOutcome
  uRdxFixTable       // TRdxFixTable.FixFor
{$ENDIF}
  ;

const
  Q      = '''';
  ZWSP   = #$200B;
  ZWNJ   = #$200C;
  ZWJ    = #$200D;
  WJ     = #$2060;
  ZWNBSP = #$FEFF;
  NBSP   = #$00A0;
  RLO    = #$202E;
  VS16   = #$FE0F;
  HEART  = #$2764;
  // U+1F468 MAN, U+1F4BB LAPTOP, U+1F525 FIRE als Surrogatpaare.
  MAN    = #$D83D#$DC68;
  LAPTOP = #$D83D#$DCBB;
  FIRE   = #$D83D#$DD25;
  // Persisch: MEEM, ZWNJ dazwischen, FARSI YEH; Thai: KO KAI, KHO KHAI.
  MEEM      = #$0645;
  FARSI_YEH = #$06CC;
  KO_KAI    = #$0E01;
  KHO_KHAI  = #$0E02;

// ---- Helfer ----

// FPC 3.2: TStringList haelt AnsiString - mit UTF-8 als Systemcodepage
// bleiben die Zeichen erhalten (Vorbild uTestRdxCleanupScope). Unter Delphi
// ist TStringList Unicode - nichts zu tun.
function Utf8CodePage: Integer;
begin
  Result := DefaultSystemCodePage;
  {$IFDEF FPC}
  DefaultSystemCodePage := CP_UTF8;
  {$ENDIF}
end;

procedure RestoreCodePage(AOld: Integer);
begin
  DefaultSystemCodePage := AOld;
end;

// Zeilen mit CRLF verbunden - selbst verkettet (Join baut unter FPC einen
// AnsiString und verloere die Zeichen).
function Lines(const ALines: array of string): string;
var
  i : Integer;
begin
  Result := '';
  for i := 0 to High(ALines) do
  begin
    if i > 0 then
      Result := Result + #13#10;
    Result := Result + ALines[i];
  end;
end;

// Die Ersetzung fuer Zeile ALine; False mit dem Grund.
function PlanEdit(const ASource: string; ALine: Integer; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  Map   : TRdxCodeMap;
  OldCp : Integer;
begin
  OldCp := Utf8CodePage;
  Map := nil;
  try
    Map := NewMap(ASource);
    Result := TRdxCharEscapeFix.InvisibleChar(Map, ALine, '', AEdit, AReason);
  finally
    Map.Free;
    RestoreCodePage(OldCp);
  end;
end;

// Die Hilfe fuer Zeile ALine, angewandt wie der Editor; '' bei Ablehnung.
function Fix(const ASource: string; ALine: Integer; out AReason: string): string;
var
  E     : TRdxEdit;
  OldCp : Integer;
begin
  Result := '';
  if not PlanEdit(ASource, ALine, E, AReason) then Exit;
  OldCp := Utf8CodePage;
  try
    Result := Apply(ASource, E);
  finally
    RestoreCodePage(OldCp);
  end;
end;

procedure AssertFix(const AExpected, ALine: string);
var
  R : string;
begin
  Assert.AreEqual(AExpected, Fix(ALine, 1, R), R);
end;

procedure AssertNoFix(const ASource: string; ALine: Integer;
  const AReason: string);
var
  R : string;
begin
  Assert.AreEqual('', Fix(ASource, ALine, R), 'keine Hilfe');
  Assert.AreEqual(AReason, R);
end;

// Der Grund "Joiner neben Nicht-ASCII" fuer ACode ('U+200D').
function JoinerReason(const ACode: string): string;
begin
  Result := _(R_INVIS_JOINER, [ACode, MsgDecideByHand]);
end;

// Der Grund "steht im Code" fuer ACode.
function InCode(const ACode: string): string;
begin
  Result := _(R_ESC_IN_CODE, [ACode, MsgCheckByHand]);
end;

// Der Wert eines Zeichen-Strings aus Quote-Literalen und #$xxxx-Codes
// ('ab'#$200B'c'); ein anderes Zeichen laesst den Test scheitern.
function CharStringValue(const ACode: string): string;
var
  i, j : Integer;
  Done : Boolean;
begin
  Result := '';
  i := 1;
  while i <= Length(ACode) do
    if ACode[i] = Q then
    begin
      Inc(i);
      Done := False;
      while not Done do
      begin
        Assert.IsTrue(i <= Length(ACode), 'Literal offen: ' + ACode);
        if i > Length(ACode) then Exit;
        if ACode[i] <> Q then
        begin
          Result := Result + ACode[i];
          Inc(i);
        end
        else if (i < Length(ACode)) and (ACode[i + 1] = Q) then
        begin
          Result := Result + Q;
          Inc(i, 2);
        end
        else
        begin
          Inc(i);
          Done := True;
        end;
      end;
    end
    else if (ACode[i] = '#') and (i < Length(ACode)) and (ACode[i + 1] = '$') then
    begin
      j := i + 2;
      while (j <= Length(ACode))
         and CharInSet(ACode[j], ['0'..'9', 'A'..'F', 'a'..'f']) do
        Inc(j);
      Result := Result + Char(StrToInt('$' + Copy(ACode, i + 2, j - i - 2)));
      i := j;
    end
    else
    begin
      Assert.IsTrue(False, 'kein Zeichen-String: ' + ACode);
      Exit;
    end;
end;

// ---- Fixture 1: Strings ----

procedure TTestRdxInvisibleCharFix.String_Zwsp_Escaped;
begin
  AssertFix('  S := ' + Q + 'ab' + Q + '#$200B' + Q + 'c' + Q + ';',
    '  S := ' + Q + 'ab' + ZWSP + 'c' + Q + ';');
  AssertFix('  C := #$200B;', '  C := ' + Q + ZWSP + Q + ';');
end;

procedure TTestRdxInvisibleCharFix.String_Word_Joiner_And_Mid_Bom_Escaped;
begin
  AssertFix('  S := ' + Q + 'a' + Q + '#$2060' + Q + 'b' + Q + '#$FEFF;',
    '  S := ' + Q + 'a' + WJ + 'b' + ZWNBSP + Q + ';');
end;

procedure TTestRdxInvisibleCharFix.String_Emoji_Zwj_Escaped_Value_Kept;
var
  R, Got, Lit : string;
begin
  // Im String nie loeschen - der Joiner gehoert zur Emoji-Folge; der Code
  // haelt den Wert, das Paar links und rechts bleibt ganz.
  Lit := Q + MAN + ZWJ + LAPTOP + Q;
  Got := Fix('  S := ' + Lit + ';', 1, R);
  Assert.AreEqual('  S := ' + Q + MAN + Q + '#$200D' + Q + LAPTOP + Q + ';',
    Got, R);
  Got := Copy(Got, Length('  S := ') + 1, Length(Got) - Length('  S := ') - 1);
  Assert.AreEqual(CharStringValue(Lit), CharStringValue(Got), 'gleicher Wert');
  // Auch hinter U+FE0F.
  AssertFix('  S := ' + Q + HEART + VS16 + Q + '#$200D' + Q + FIRE + Q + ';',
    '  S := ' + Q + HEART + VS16 + ZWJ + FIRE + Q + ';');
end;

procedure TTestRdxInvisibleCharFix.String_Zwnj_In_Script_Escaped;
begin
  AssertFix('  S := ' + Q + MEEM + Q + '#$200C' + Q + FARSI_YEH + Q + ';',
    '  S := ' + Q + MEEM + ZWNJ + FARSI_YEH + Q + ';');
end;

// ---- Fixture 1: Kommentare ----

procedure TTestRdxInvisibleCharFix.Comment_Zwsp_Deleted;
begin
  AssertFix('// ab', '// a' + ZWSP + 'b');
  AssertFix('  X := 1; { ab }', '  X := 1; { a' + WJ + 'b' + ZWNBSP + ' }');
  // ZWSP verbindet nichts - auch neben Nicht-ASCII (Thai) geloescht.
  AssertFix('// ' + KO_KAI + KHO_KHAI, '// ' + KO_KAI + ZWSP + KHO_KHAI);
end;

procedure TTestRdxInvisibleCharFix.Comment_Joiner_Next_To_Ascii_Deleted;
begin
  AssertFix('// ab', '// a' + ZWJ + 'b');
  AssertFix('{ x }', '{ x' + ZWNJ + ' }');
  AssertFix('// x', '// x' + ZWJ);
  AssertFix('(* y *)', '(* ' + ZWJ + 'y *)');
end;

procedure TTestRdxInvisibleCharFix.Comment_Zwsp_Next_To_Emoji_Deleted;
begin
  // Das Paar bleibt ganz (Apply prueft Bytes wie der Editor).
  AssertFix('// ' + MAN + 'x', '// ' + MAN + ZWSP + 'x');
end;

procedure TTestRdxInvisibleCharFix.Comment_And_String_One_Edit;
var
  E   : TRdxEdit;
  R   : string;
  Src : string;
begin
  Src := '  S := ' + Q + 'a' + ZWSP + Q + '; // b' + WJ + 'c';
  Assert.IsTrue(PlanEdit(Src, 1, E, R), R);
  Assert.AreEqual<Integer>(8, E.Span.StartCol);
  Assert.AreEqual<Integer>(Pos(WJ, Src) + 1, E.Span.EndCol);
  AssertFix('  S := ' + Q + 'a' + Q + '#$200B; // bc', Src);
end;

// ---- Fixture 1: Gegenproben ----

procedure TTestRdxInvisibleCharFix.Comment_Joiner_In_Emoji_NoHelp;
begin
  AssertNoFix('// ' + MAN + ZWJ + LAPTOP, 1, JoinerReason('U+200D'));
  AssertNoFix('  X := 1; // ' + HEART + VS16 + ZWJ + FIRE, 1,
    JoinerReason('U+200D'));
end;

procedure TTestRdxInvisibleCharFix.Comment_Joiner_In_Script_NoHelp;
begin
  AssertNoFix('{ ' + MEEM + ZWNJ + FARSI_YEH + ' }', 1, JoinerReason('U+200C'));
end;

procedure TTestRdxInvisibleCharFix.Joiner_Blocks_Whole_Line;
begin
  // Der String davor bekaeme seine Hilfe - eine Teilhilfe liesse den Fund
  // auf der Zeile stehen, darum keine.
  AssertNoFix('  S := ' + Q + 'a' + ZWSP + Q + '; // ' + MAN + ZWJ + LAPTOP, 1,
    JoinerReason('U+200D'));
end;

procedure TTestRdxInvisibleCharFix.Code_NoHelp;
begin
  AssertNoFix('  My' + ZWSP + 'Var := 1;', 1, InCode('U+200B'));
  AssertNoFix('  X :=' + ZWJ + ' 1; // a' + ZWSP, 1, InCode('U+200D'));
end;

procedure TTestRdxInvisibleCharFix.Bom_At_Line_Start_NoHelp;
begin
  // Ein U+FEFF vor 'unit' steht im Code (der Detektor meldet nur eins
  // MITTEN in der Datei; eine echte BOM steht nie im Editor-Puffer).
  AssertNoFix(Lines([ZWNBSP + 'unit u;', 'interface']), 1, InCode('U+FEFF'));
end;

procedure TTestRdxInvisibleCharFix.Directive_NoHelp;
begin
  AssertNoFix('{$I a' + ZWSP + '.inc}', 1,
    _(R_ESC_DIRECTIVE, ['U+200B', MsgCheckByHand]));
end;

procedure TTestRdxInvisibleCharFix.Comment_Shape_NoHelp;
begin
  AssertNoFix('{' + ZWSP + '$I x.inc}', 1, _(R_ESC_SHAPE, ['U+200B']));
  AssertNoFix('(* a *' + WJ + ') b; *)', 1, _(R_ESC_SHAPE, ['U+2060']));
end;

procedure TTestRdxInvisibleCharFix.Multi_Line_String_NoHelp;
begin
  AssertNoFix(Lines(['  S := ' + Q + Q + Q, '    a' + ZWSP + 'b',
    '    ' + Q + Q + Q + ';']), 2,
    _(R_ESC_MULTI_LINE, ['U+200B', MsgCheckByHand]));
end;

procedure TTestRdxInvisibleCharFix.Moved_Line_NoHelp;
var
  R : string;
begin
  R := MsgMovedSuffix(_(R_INVIS_NONE));
  AssertNoFix(Lines(['// a' + ZWSP, '  X := 1;']), 2, R);
  AssertNoFix('// a' + ZWSP, 3, R);
  // NBSP und Bidi-Zeichen sind nicht die Zeichen dieser Regel.
  AssertNoFix('  S := ' + Q + 'a' + NBSP + 'b' + Q + ';', 1, R);
  AssertNoFix('// a' + RLO, 1, R);
end;

procedure TTestRdxInvisibleCharFix.Character_Set_Like_Detector;
begin
  // Die Menge des Detektors (uFileTextCache.IsZeroWidthSeq).
  Assert.IsTrue(TRdxCharEscapeFix.IsInvisible(ZWSP), 'U+200B');
  Assert.IsTrue(TRdxCharEscapeFix.IsInvisible(ZWNJ), 'U+200C');
  Assert.IsTrue(TRdxCharEscapeFix.IsInvisible(ZWJ), 'U+200D');
  Assert.IsTrue(TRdxCharEscapeFix.IsInvisible(WJ), 'U+2060');
  Assert.IsTrue(TRdxCharEscapeFix.IsInvisible(ZWNBSP), 'U+FEFF');
  Assert.IsFalse(TRdxCharEscapeFix.IsInvisible(NBSP), 'U+00A0');
  Assert.IsFalse(TRdxCharEscapeFix.IsInvisible(#$200A), 'U+200A');
  Assert.IsFalse(TRdxCharEscapeFix.IsInvisible(#$200E), 'U+200E');
  Assert.IsFalse(TRdxCharEscapeFix.IsInvisible(#$2061), 'U+2061');
  Assert.IsFalse(TRdxCharEscapeFix.IsInvisible(VS16), 'U+FE0F');
  Assert.IsFalse(TRdxCharEscapeFix.IsInvisible(RLO), 'U+202E');
  Assert.AreEqual('#$FEFF', TRdxCharEscapeFix.CharCode(ZWNBSP));
end;

{$IFNDEF FPC}

// ---- Fixture 2: mit dem echten Detektor (nur Delphi) ----

// ASource als UTF-8 mit BOM in eine neue .pas-Datei (der Detektor liest die
// Rohbytes; WriteText schriebe ANSI und verloere die Zeichen).
function WriteUtf8(const ASource: string): string;
var
  Pre, Body, All : TBytes;
begin
  Result := TempName('rdx_s192_', '.pas');
  Pre := TEncoding.UTF8.GetPreamble;
  Body := TEncoding.UTF8.GetBytes(ASource);
  SetLength(All, Length(Pre) + Length(Body));
  if Length(Pre) > 0 then
    Move(Pre[0], All[0], Length(Pre));
  if Length(Body) > 0 then
    Move(Body[0], All[Length(Pre)], Length(Body));
  TFile.WriteAllBytes(Result, All);
end;

// Zahl der SCA192-Funde in ASource; ALine/AMsg der erste (0/'' ohne).
function Detect(const ASource: string; out ALine: Integer;
  out AMsg: string): Integer;
var
  Path    : string;
  Results : TObjectList<TLeakFinding>;
  F       : TLeakFinding;
begin
  Result := 0;
  ALine := 0;
  AMsg := '';
  Path := WriteUtf8(ASource);
  Results := nil;
  try
    Results := TObjectList<TLeakFinding>.Create(True);
    TSourceEncodingDetector.AnalyzeUnit(nil, Path, Results);
    for F in Results do
      if F.Kind = fkSourceInvisibleChar then
      begin
        if Result = 0 then
        begin
          ALine := F.LineInt;
          AMsg := F.Message;
        end;
        Inc(Result);
      end;
  finally
    Results.Free;
    DeleteFile(Path);
  end;
end;

// Die Hilfe zum ersten Fund ueber den Einstieg der Tabelle
// (TRdxFixTable.FixFor, Adapter PlanInvisibleChar) - ohne Quellstellen-
// Dienst, den die Hilfe nicht braucht.
function PlanFirst(const ASource: string; out AFound: Integer): TRdxFixOutcome;
var
  SL   : TStringList;
  F    : TLeakFinding;
  Line : Integer;
  Msg  : string;
begin
  AFound := Detect(ASource, Line, Msg);
  Assert.IsTrue(AFound > 0, 'der Detektor meldet');
  SL := TStringList.Create;
  F := nil;
  try
    F := TLeakFinding.New('t.pas', '', Line, Msg, fkSourceInvisibleChar);
    SL.Text := ASource;
    Result := TRdxFixTable.FixFor(nil, SL, F, nil);
  finally
    F.Free;
    SL.Free;
  end;
end;

// Fund fuer Fund, bis der Detektor schweigt (je Datei meldet er nur die
// erste Zeile).
function FixAll(const ASource: string): string;
const
  MAX_PASSES = 10;
var
  O     : TRdxFixOutcome;
  Pass  : Integer;
  Found : Integer;
  Line  : Integer;
  Msg   : string;
begin
  Result := ASource;
  for Pass := 1 to MAX_PASSES do
  begin
    if Detect(Result, Line, Msg) = 0 then Exit;
    O := PlanFirst(Result, Found);
    Assert.IsTrue(O.Enabled, Format('Zeile %d: %s', [Line, O.Reason]));
    Result := Apply(Result, O.Edits);
  end;
  Assert.Fail(Format('der Detektor meldet nach %d Runden noch', [MAX_PASSES]));
end;

function InProc(const ABody: array of string): string;
begin
  Result := Lines(['unit t;', 'interface', 'implementation', 'procedure P;',
    'var S: string;', 'begin']) + #13#10 + Lines(ABody) + #13#10
    + Lines(['end;', 'end.']);
end;

procedure TTestRdxInvisibleCharFixDetector.Detector_String_Then_Comment_RoundTrip;
var
  Src, Msg : string;
  Line     : Integer;
begin
  Src := InProc(['  S := ' + Q + 'a' + ZWSP + 'b' + Q + ';',
    '  // hidden' + ZWJ + ' text']);
  Assert.AreEqual<Integer>(1, Detect(Src, Line, Msg));
  Assert.AreEqual<Integer>(7, Line);
  Assert.AreEqual(InProc(['  S := ' + Q + 'a' + Q + '#$200B' + Q + 'b' + Q
    + ';', '  // hidden text']), FixAll(Src));
end;

procedure TTestRdxInvisibleCharFixDetector.Detector_Emoji_String_RoundTrip;
var
  Fixed, Msg : string;
  Line       : Integer;
begin
  Fixed := FixAll(InProc(['  S := ' + Q + MAN + ZWJ + LAPTOP + Q + ';']));
  Assert.AreEqual<Integer>(0, Detect(Fixed, Line, Msg), 'der Detektor schweigt');
  Assert.AreEqual(InProc(['  S := ' + Q + MAN + Q + '#$200D' + Q + LAPTOP + Q
    + ';']), Fixed);
end;

procedure TTestRdxInvisibleCharFixDetector.Detector_Emoji_Comment_NoHelp;
var
  O     : TRdxFixOutcome;
  Found : Integer;
begin
  O := PlanFirst(InProc(['  // done ' + MAN + ZWJ + LAPTOP]), Found);
  Assert.AreEqual<Integer>(1, Found);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(JoinerReason('U+200D'), O.Reason);
end;

procedure TTestRdxInvisibleCharFixDetector.Detector_Code_NoHelp;
var
  O     : TRdxFixOutcome;
  Found : Integer;
begin
  O := PlanFirst(InProc(['  S' + ZWSP + ' := ' + Q + 'a' + Q + ';']), Found);
  Assert.AreEqual<Integer>(1, Found);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(InCode('U+200B'), O.Reason);
  Assert.AreEqual<Integer>(0, Length(O.Edits));
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxInvisibleCharFix);
{$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxInvisibleCharFixDetector);
{$ENDIF}

end.
