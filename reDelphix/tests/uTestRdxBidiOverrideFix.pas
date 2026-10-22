unit uTestRdxBidiOverrideFix;

// Editorhilfe SCA188 SourceBidiOverride (uRdxCharEscapeFix, BidiOverride):
// die Bidi-Steuerzeichen der gemeldeten Zeile - im Kommentar geloescht, im
// String als #$xxxx geschrieben (Literal aufgebrochen, gleicher Wert).
//   Fixture 1 (Text, ohne Parser und Detektor, FPC-tauglich): Kommentar
//   ('//', '{ }', '(* *)', ueber Zeilen), String (Mitte, Rand, ganz, Folge,
//   verdoppeltes Quote, Surrogatpaar daneben, Bezeichner dahinter, zwei
//   Literale), Kommentar und String in EINER Ersetzung, Wertgleichheit;
//   Gegenproben Code, Direktive, Kommentar-Form, mehrzeiliger String,
//   offener String, '.'/'[' hinter dem Literal, verschobene Zeile, Zeichen
//   ausserhalb der Detektor-Menge (U+200E/U+200F).
//   Fixture 2 (nur Delphi): der ECHTE Detektor (uSourceEncoding) meldet
//   die erste Zeile, die Hilfe (ueber den Einstieg der Tabelle,
//   TRdxFixTable.FixFor) behebt sie, bis der Detektor schweigt.
// Quelltext reines ASCII: die Steuerzeichen entstehen ueber #$xxxx.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxBidiOverrideFix = class
  public
    [Test] procedure Comment_Line_Deleted;
    [Test] procedure Comment_Brace_And_Paren_Deleted;
    [Test] procedure Comment_Over_Lines_Deleted;
    [Test] procedure String_Middle_Escaped;
    [Test] procedure String_Edges_And_Whole;
    [Test] procedure String_Run_And_Doubled_Quote;
    [Test] procedure String_Value_Kept;
    [Test] procedure Comment_And_String_One_Edit;
    [Test] procedure Two_Literals_And_Arabic_Letter_Mark;
    [Test] procedure Identifier_After_Code_Gets_Blank;
    [Test] procedure Surrogate_Pair_Kept;
    [Test] procedure Code_NoHelp;
    [Test] procedure Directive_NoHelp;
    [Test] procedure Comment_Shape_NoHelp;
    [Test] procedure Multi_Line_String_NoHelp;
    [Test] procedure Unclosed_String_NoHelp;
    [Test] procedure Member_After_Literal_NoHelp;
    [Test] procedure Moved_Line_NoHelp;
    [Test] procedure Character_Set_Like_Detector;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxBidiOverrideFixDetector = class
  public
    [Test] procedure Detector_Comment_Then_String_RoundTrip;
    [Test] procedure Detector_Stretched_String_RoundTrip;
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
  Q   = '''';
  RLO = #$202E;
  RLE = #$202B;
  PDF = #$202C;
  LRI = #$2066;
  PDI = #$2069;
  ALM = #$061C;
  LRM = #$200E;
  RLM = #$200F;
  ZWSP = #$200B;
  // U+1F600 als Surrogatpaar.
  EMOJI = #$D83D#$DE00;

// ---- Helfer ----

// FPC 3.2: TStringList haelt AnsiString - mit UTF-8 als Systemcodepage
// bleiben die Steuerzeichen erhalten (Vorbild uTestRdxCleanupScope).
// Unter Delphi ist TStringList Unicode - nichts zu tun.
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
// AnsiString und verloere die Steuerzeichen).
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
    Result := TRdxCharEscapeFix.BidiOverride(Map, ALine, '', AEdit, AReason);
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

// Der Grund "steht im Code" fuer U+202E.
function InCode: string;
begin
  Result := _(R_ESC_IN_CODE, ['U+202E', MsgCheckByHand]);
end;

// Der Wert eines Zeichen-Strings aus Quote-Literalen und #$xxxx-Codes
// ('ab'#$202E'c'); ein anderes Zeichen laesst den Test scheitern.
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

// ---- Fixture 1: Kommentare ----

procedure TTestRdxBidiOverrideFix.Comment_Line_Deleted;
begin
  AssertFix('  X := 1; // ab', '  X := 1; // a' + RLO + 'b');
  // Mehrere, auch Isolates: alle Zeichen der Zeile in einer Ersetzung.
  AssertFix('// check text', '// check ' + RLO + LRI + 'text' + PDI);
  AssertFix('//', '//' + PDF);
end;

procedure TTestRdxBidiOverrideFix.Comment_Brace_And_Paren_Deleted;
begin
  AssertFix('{ a }', '{ a' + RLE + ' }');
  AssertFix('(* ab *)', '(* a' + LRI + 'b *)');
  AssertFix('  X := 1; { c } Y := 2;', '  X := 1; { c' + RLO + ' } Y := 2;');
end;

procedure TTestRdxBidiOverrideFix.Comment_Over_Lines_Deleted;
var
  R : string;
begin
  // Die Zeile beginnt in einem Block-Kommentar der Zeile davor.
  Assert.AreEqual(Lines(['{', '  hidden text', '}']),
    Fix(Lines(['{', '  hidden' + RLO + ' text', '}']), 2, R), R);
  Assert.AreEqual(Lines(['(* a', '  b *) X := 1;']),
    Fix(Lines(['(* a', '  b' + PDI + ' *) X := 1;']), 2, R), R);
end;

// ---- Fixture 1: Strings ----

procedure TTestRdxBidiOverrideFix.String_Middle_Escaped;
begin
  AssertFix('  S := ' + Q + 'abc' + Q + '#$202E' + Q + 'def' + Q + ';',
    '  S := ' + Q + 'abc' + RLO + 'def' + Q + ';');
  AssertFix('  S := ' + Q + 'a' + Q + '#$2066' + Q + 'b' + Q + ' + T;',
    '  S := ' + Q + 'a' + LRI + 'b' + Q + ' + T;');
end;

procedure TTestRdxBidiOverrideFix.String_Edges_And_Whole;
begin
  // Am Anfang, am Ende, das ganze Literal: kein leeres '' entsteht.
  AssertFix('  S := #$202E' + Q + 'abc' + Q + ';',
    '  S := ' + Q + RLO + 'abc' + Q + ';');
  AssertFix('  S := ' + Q + 'abc' + Q + '#$202C;',
    '  S := ' + Q + 'abc' + PDF + Q + ';');
  AssertFix('  C := #$202E;', '  C := ' + Q + RLO + Q + ';');
  AssertFix('  S := #$202A#$202C;', '  S := ' + Q + #$202A + PDF + Q + ';');
end;

procedure TTestRdxBidiOverrideFix.String_Run_And_Doubled_Quote;
begin
  // Folge zweier Zeichen: zwei Codes nebeneinander; das verdoppelte Quote
  // bleibt im Teil-Literal, wie es war.
  AssertFix('  S := ' + Q + 'it' + Q + Q + 's' + Q + '#$202E#$2069' + Q + 'x'
    + Q + ';',
    '  S := ' + Q + 'it' + Q + Q + 's' + RLO + PDI + 'x' + Q + ';');
  // Das Zeichen vor einem verdoppelten Quote: "'" bleibt ein eigenes
  // Literal ''''.
  AssertFix('  S := #$202E' + Q + Q + Q + Q + ';',
    '  S := ' + Q + RLO + Q + Q + Q + ';');
end;

procedure TTestRdxBidiOverrideFix.String_Value_Kept;
const
  OLD_LITS: array[0..3] of string = (
    Q + 'abc' + RLO + 'def' + Q,
    Q + 'it' + Q + Q + 's' + RLO + PDI + 'x' + Q,
    Q + RLO + Q + Q + Q,
    Q + EMOJI + LRI + 'x' + ALM + Q);
var
  i    : Integer;
  R, S : string;
begin
  // Bedeutungsgleich: der neue Zeichen-String hat denselben Wert.
  for i := 0 to High(OLD_LITS) do
  begin
    S := Fix('  S := ' + OLD_LITS[i] + ';', 1, R);
    Assert.IsTrue(S <> '', R);
    S := Copy(S, Length('  S := ') + 1, Length(S) - Length('  S := ') - 1);
    Assert.AreEqual(CharStringValue(OLD_LITS[i]), CharStringValue(S),
      'Wert ' + IntToStr(i));
    Assert.IsTrue(Pos(RLO, S) + Pos(LRI, S) + Pos(PDI, S) + Pos(ALM, S) = 0,
      'kein Steuerzeichen mehr ' + IntToStr(i));
  end;
end;

procedure TTestRdxBidiOverrideFix.Comment_And_String_One_Edit;
var
  E   : TRdxEdit;
  R   : string;
  Src : string;
begin
  Src := '  S := ' + Q + 'a' + RLO + 'b' + Q + '; // c' + PDF + 'd';
  Assert.IsTrue(PlanEdit(Src, 1, E, R), R);
  // EINE Ersetzung vom oeffnenden Quote bis hinter das letzte Zeichen.
  Assert.AreEqual<Integer>(1, E.Span.StartLine);
  Assert.AreEqual<Integer>(8, E.Span.StartCol);
  Assert.AreEqual<Integer>(Pos(PDF, Src) + 1, E.Span.EndCol);
  Assert.AreEqual(Copy(Src, 8, Pos(PDF, Src) - 7), E.Expected);
  Assert.AreEqual(Q + 'a' + Q + '#$202E' + Q + 'b' + Q + '; // c', E.NewText);
  AssertFix('  S := ' + Q + 'a' + Q + '#$202E' + Q + 'b' + Q + '; // cd', Src);
end;

procedure TTestRdxBidiOverrideFix.Two_Literals_And_Arabic_Letter_Mark;
begin
  AssertFix('  F(' + Q + 'a' + Q + '#$202E, ' + Q + 'b' + Q + '#$061C' + Q
    + 'c' + Q + ');',
    '  F(' + Q + 'a' + RLO + Q + ', ' + Q + 'b' + ALM + 'c' + Q + ');');
end;

procedure TTestRdxBidiOverrideFix.Identifier_After_Code_Gets_Blank;
begin
  // '...'then ist gueltig; #$202Ethen nicht (E ist eine Hex-Ziffer).
  AssertFix('  if S = #$202E then', '  if S = ' + Q + RLO + Q + 'then');
  // Ein Operator dahinter braucht nichts; '..' ist kein Helfer-Aufruf.
  AssertFix('  S := #$202E+T;', '  S := ' + Q + RLO + Q + '+T;');
  AssertFix('  case C of #$202E..' + Q + 'z' + Q + ': ;',
    '  case C of ' + Q + RLO + Q + '..' + Q + 'z' + Q + ': ;');
end;

procedure TTestRdxBidiOverrideFix.Surrogate_Pair_Kept;
begin
  // Das Paar vor dem Zeichen bleibt ganz (der Editor rechnet in Bytes -
  // Apply prueft den Bereich wie PlanByteEdits).
  AssertFix('  S := ' + Q + EMOJI + Q + '#$202E' + Q + 'x' + Q + ';',
    '  S := ' + Q + EMOJI + RLO + 'x' + Q + ';');
  AssertFix('  // ' + EMOJI + EMOJI, '  // ' + EMOJI + RLO + EMOJI);
end;

// ---- Fixture 1: Gegenproben ----

procedure TTestRdxBidiOverrideFix.Code_NoHelp;
begin
  AssertNoFix('  X' + RLO + ' := 1;', 1, InCode);
  // Ein Zeichen im Code sperrt die ganze Zeile, auch Kommentar und String.
  AssertNoFix('  X' + RLO + ' := ' + Q + 'a' + RLO + Q + '; // b' + RLO, 1,
    InCode);
  AssertNoFix('  S := ' + Q + 'a' + RLO + Q + '; X' + RLO + ' := 1;', 1,
    InCode);
end;

procedure TTestRdxBidiOverrideFix.Directive_NoHelp;
var
  R : string;
begin
  R := _(R_ESC_DIRECTIVE, ['U+202E', MsgCheckByHand]);
  AssertNoFix('{$MESSAGE HINT ' + Q + 'a' + RLO + 'b' + Q + '}', 1, R);
  AssertNoFix('{$I a' + RLO + '.inc}', 1, R);
  AssertNoFix('(*$I a' + RLO + '.inc*)', 1, R);
  // Die Direktive beginnt eine Zeile davor.
  AssertNoFix(Lines(['{$MESSAGE HINT ' + Q + 'a', RLO + Q + '}']), 2, R);
  // '{$' in einem '//'-Kommentar ist Text, keine Direktive.
  AssertFix('// {$I a.inc}', '// {$I a' + RLO + '.inc}');
end;

procedure TTestRdxBidiOverrideFix.Comment_Shape_NoHelp;
var
  R : string;
begin
  R := _(R_ESC_SHAPE, ['U+202E']);
  // Aus dem Kommentar wuerde eine Direktive ...
  AssertNoFix('{' + RLO + '$I x.inc}', 1, R);
  AssertNoFix('(*' + RLO + '$DEFINE X*)', 1, R);
  // ... oder der Kommentar endete frueher, ' b;' wuerde Code.
  AssertNoFix('(* a *' + RLO + ') b; *)', 1, R);
  AssertNoFix(Lines(['(* a', '  *' + RLO + ') b;', '*)']), 2, R);
end;

procedure TTestRdxBidiOverrideFix.Multi_Line_String_NoHelp;
begin
  AssertNoFix(Lines(['  S := ' + Q + Q + Q, '    a' + RLO + 'b',
    '    ' + Q + Q + Q + ';']), 2,
    _(R_ESC_MULTI_LINE, ['U+202E', MsgCheckByHand]));
end;

procedure TTestRdxBidiOverrideFix.Unclosed_String_NoHelp;
begin
  AssertNoFix('  S := ' + Q + 'abc' + RLO, 1, _(R_ESC_UNCLOSED, ['U+202E']));
end;

procedure TTestRdxBidiOverrideFix.Member_After_Literal_NoHelp;
var
  R : string;
begin
  R := _(R_ESC_MEMBER, ['U+202E', MsgCheckByHand]);
  AssertNoFix('  N := ' + Q + 'a' + RLO + Q + '.Length;', 1, R);
  AssertNoFix('  N := ' + Q + 'a' + RLO + Q + ' .Length;', 1, R);
  AssertNoFix('  C := ' + Q + 'a' + RLO + Q + '[1];', 1, R);
end;

procedure TTestRdxBidiOverrideFix.Moved_Line_NoHelp;
var
  R : string;
begin
  R := MsgMovedSuffix(_(R_BIDI_NONE));
  AssertNoFix(Lines(['// a' + RLO, '  X := 1;']), 2, R);
  AssertNoFix('  X := 1;', 1, R);
  AssertNoFix('// a' + RLO, 0, R);
  AssertNoFix('// a' + RLO, 5, R);
end;

procedure TTestRdxBidiOverrideFix.Character_Set_Like_Detector;
var
  R : string;
begin
  // Die Menge des Detektors (uFileTextCache.IsBidiOverrideSeq).
  Assert.IsTrue(TRdxCharEscapeFix.IsBidiControl(ALM), 'U+061C');
  Assert.IsTrue(TRdxCharEscapeFix.IsBidiControl(#$202A), 'U+202A');
  Assert.IsTrue(TRdxCharEscapeFix.IsBidiControl(RLO), 'U+202E');
  Assert.IsTrue(TRdxCharEscapeFix.IsBidiControl(LRI), 'U+2066');
  Assert.IsTrue(TRdxCharEscapeFix.IsBidiControl(PDI), 'U+2069');
  Assert.IsFalse(TRdxCharEscapeFix.IsBidiControl(LRM), 'U+200E');
  Assert.IsFalse(TRdxCharEscapeFix.IsBidiControl(RLM), 'U+200F');
  Assert.IsFalse(TRdxCharEscapeFix.IsBidiControl(#$202F), 'U+202F');
  Assert.IsFalse(TRdxCharEscapeFix.IsBidiControl(#$2065), 'U+2065');
  Assert.IsFalse(TRdxCharEscapeFix.IsBidiControl(ZWSP), 'U+200B');
  Assert.AreEqual('#$061C', TRdxCharEscapeFix.CharCode(ALM));
  // LRM/RLM meldet der Detektor nicht - die Hilfe laesst sie stehen.
  AssertNoFix('// a' + LRM + RLM, 1, MsgMovedSuffix(_(R_BIDI_NONE)));
  Assert.AreEqual('// a' + LRM, Fix('// a' + LRM + RLO, 1, R), R);
end;

{$IFNDEF FPC}

// ---- Fixture 2: mit dem echten Detektor (nur Delphi) ----

// ASource als UTF-8 mit BOM in eine neue .pas-Datei (der Detektor liest die
// Rohbytes; WriteText schriebe ANSI und verloere die Zeichen).
function WriteUtf8(const ASource: string): string;
var
  Pre, Body, All : TBytes;
begin
  Result := TempName('rdx_s188_', '.pas');
  Pre := TEncoding.UTF8.GetPreamble;
  Body := TEncoding.UTF8.GetBytes(ASource);
  SetLength(All, Length(Pre) + Length(Body));
  if Length(Pre) > 0 then
    Move(Pre[0], All[0], Length(Pre));
  if Length(Body) > 0 then
    Move(Body[0], All[Length(Pre)], Length(Body));
  TFile.WriteAllBytes(Result, All);
end;

// Zahl der SCA188-Funde in ASource; ALine/AMsg der erste (0/'' ohne).
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
      if F.Kind = fkSourceBidiOverride then
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
// (TRdxFixTable.FixFor, Adapter PlanBidiOverride) - ohne Quellstellen-
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
    F := TLeakFinding.New('t.pas', '', Line, Msg, fkSourceBidiOverride);
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

// Eine Unit t mit Routine P und lokaler Variable S; ABody ist ihr Rumpf
// (ab Zeile 7). Selbst verkettet (Lines, s. dort). Eigener Name: als
// InProc verdeckte sie das gleichnamige aus uTestRdxTextKit (Unit u, ohne
// S, Join) - mit anderer Quelle.
function InProcWithS(const ABody: array of string): string;
begin
  Result := Lines(['unit t;', 'interface', 'implementation', 'procedure P;',
    'var S: string;', 'begin']) + #13#10 + Lines(ABody) + #13#10
    + Lines(['end;', 'end.']);
end;

procedure TTestRdxBidiOverrideFixDetector.Detector_Comment_Then_String_RoundTrip;
var
  Src, Msg : string;
  Line     : Integer;
begin
  Src := InProcWithS(['  // check' + RLO + ' admin',
    '  S := ' + Q + 'a' + RLO + 'b' + Q + ';']);
  // Ein Fund je Datei, auf der ersten Zeile mit dem Zeichen.
  Assert.AreEqual<Integer>(1, Detect(Src, Line, Msg));
  Assert.AreEqual<Integer>(7, Line);
  Assert.AreEqual(InProcWithS(['  // check admin',
    '  S := ' + Q + 'a' + Q + '#$202E' + Q + 'b' + Q + ';']), FixAll(Src));
end;

procedure TTestRdxBidiOverrideFixDetector.Detector_Stretched_String_RoundTrip;
var
  Src, Fixed, Msg : string;
  Line            : Integer;
begin
  // Trojan Source, "stretched string": im Editor scheint der Vergleich
  // hinter einem Kommentar zu enden, der Compiler liest einen String.
  Src := InProcWithS(['  if S <> ' + Q + 'user' + RLO + ' ' + LRI
    + '// Check if admin' + PDI + ' ' + LRI + Q + ' then', '    Exit;']);
  Fixed := FixAll(Src);
  Assert.AreEqual<Integer>(0, Detect(Fixed, Line, Msg), 'der Detektor schweigt');
  Assert.AreEqual(InProcWithS(['  if S <> ' + Q + 'user' + Q + '#$202E' + Q
    + ' ' + Q + '#$2066' + Q + '// Check if admin' + Q + '#$2069' + Q + ' '
    + Q + '#$2066 then', '    Exit;']), Fixed);
end;

procedure TTestRdxBidiOverrideFixDetector.Detector_Code_NoHelp;
var
  O     : TRdxFixOutcome;
  Found : Integer;
begin
  // Der Detektor meldet auch das Zeichen im Code - die Hilfe lehnt ab.
  O := PlanFirst(InProcWithS(['  S' + RLO + ' := ' + Q + 'a' + Q + ';']),
    Found);
  Assert.AreEqual<Integer>(1, Found);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(InCode, O.Reason);
  Assert.AreEqual<Integer>(0, Length(O.Edits));
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxBidiOverrideFix);
{$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxBidiOverrideFixDetector);
{$ENDIF}

end.
