unit uTestRegexStackDepth;

// Charge R4 (2026-10-26): Waechter fuer die Regex-Stellen, deren
// wiederholte Gruppe in PCRE 8.45 (Delphi-TRegEx, Interpreter ohne JIT) je
// Wiederholung verschachtelte match()-Rahmen kostete. Ab ~1000-2000
// Wiederholungen lief der 1-MB-Stack von bds.exe/TestProject ueber
// ($C00000FD) - die Scan-EXE hat 32 MB und merkte nichts. Die Gruppen sind
// jetzt possessiv ('*+') bzw. (uHardcodedString) zweizweigig ohne
// Gruppen-Rekursion; das Ergebnis ist identisch (PCRE-8.45-Vergleich alt
// gegen neu auf realworld + lazarus + Zufallstexten, scratchpad chargeR\R4).
//
// Jeder Test mit langer Eingabe haette OHNE den Umbau den Testlauf mit
// Stack-Ueberlauf beendet (Tiefe je Muster gemessen, s. Kommentar am Test).
// Die Detektoren laufen DIREKT (nicht ueber FindingsOfFile): der Waechter
// gilt der einen Regex-Stelle, nicht den uebrigen Detektoren auf Zeilen mit
// mehreren zehn KB. Die beiden kurzen HardcodedString-Tests pinnen den
// Rueckfall-Zweig des neuen Literal-Musters (offenes Literal) - sie sind
// vor und nach dem Umbau gruen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRegexStackDepth = class
  public
    // uDetectorUtils.IsLikelyAttributePosition / LooksLikeMemberDecl
    [Test] procedure AttrPosition_LongFieldListWithType_True;
    [Test] procedure AttrPosition_LongIdentListWithoutType_False;
    // uAttributeDuplicate.LineLooksLikeMemberDecl
    [Test] procedure AttrDuplicate_LongFieldList_Reported;
    // uConcurrencyExt: Resume-Empfaenger-Typ und RE_FUNC_HEADER
    [Test] procedure Resume_LongDeclLists_TypeResolved;
    [Test] procedure FreeAndNilResult_ManyParenPairsInHeader_Reported;
    // uFloatEquality: Deklarations-Muster 209/959 und 429/554/712
    [Test] procedure FloatEq_LongIntegerDeclList_Suppressed;
    [Test] procedure FloatEq_LongFloatDeclLists_SentinelDemoted;
    // uPerfHotspots / uPointerSubtraction / uStringFromPointer
    [Test] procedure PerfConcat_LongIntegerDeclList_Suppressed;
    [Test] procedure PointerSub_LongWordDeclList_Suppressed;
    [Test] procedure StringFromPointer_LongStringDeclList_Suppressed;
    // uHardcodedString: Literal-Rumpf
    [Test] procedure HardcodedString_LongLiteral_FullBody;
    [Test] procedure HardcodedString_LongOpenLiteral_CutBeforeLastPair;
    [Test] procedure HardcodedString_ShortOpenLiteral_CutBeforeLastPair;
    [Test] procedure HardcodedString_OpenLiteralWithoutPair_NotReported;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  uAstNode, uParser2, uSCAConsts, uMethodd12, uDetectorUtils,
  uAttributeDuplicate, uConcurrencyExt, uFloatEquality, uPerfHotspots,
  uPointerSubtraction, uStringFromPointer, uHardcodedString,
  uTestFindingHelper;

const
  LONG_LIST = 5000;   // Listenelemente je langer Liste

type
  TDetectorRun = reference to procedure(Root: TAstNode; const FileName: string;
    Results: TObjectList<TLeakFinding>);

// 'P0, P1, ..., P<N-1>' - eine Zeile, Komma + Leerzeichen.
function IdentList(const APrefix: string; ACount: Integer): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to ACount - 1 do
    begin
      if i > 0 then SB.Append(', ');
      SB.Append(APrefix).Append(i);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Schreibt ASrc in eine Temp-Datei, parst sie (AParse) und ruft ARun.
function RunDetector(const ASrc: string; AParse: Boolean;
  const ARun: TDetectorRun): TObjectList<TLeakFinding>;
var
  TempPath : string;
  Parser   : TParser2;
  Root     : TAstNode;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  TempPath := TPath.Combine(TPath.GetTempPath,
    'sca_r4_' + TGuid.NewGuid.ToString
      .Replace('{', '').Replace('}', '').Replace('-', '') + '.pas');
  TFile.WriteAllText(TempPath, ASrc, TEncoding.UTF8);
  try
    if AParse then
    begin
      Parser := TParser2.Create;
      try
        Root := Parser.ParseFile(TempPath);
        try
          ARun(Root, TempPath, Result);
        finally
          Root.Free;
        end;
      finally
        Parser.Free;
      end;
    end
    else
      ARun(nil, TempPath, Result);
  finally
    if TFile.Exists(TempPath) then TFile.Delete(TempPath);
  end;
end;

{ uDetectorUtils }

procedure TTestRegexStackDepth.AttrPosition_LongFieldListWithType_True;
// LooksLikeMemberDecl prueft die Zeile nach dem Attribut mit
// '^[A-Za-z_]\w*(\s*,\s*[A-Za-z_]\w*)*\s*:...' - gierig 4 PCRE-Rahmen je
// Bezeichner (5.000 -> ~20.000 Rahmen, Ueberlauf ab ~1.000).
var
  Lines : TStringList;
begin
  Lines := TStringList.Create;
  try
    Lines.Add('type');
    Lines.Add('  TX = class');
    Lines.Add('  public');
    Lines.Add('    [Inject]');
    Lines.Add('    ' + IdentList('v', LONG_LIST) + ': Integer;');
    Lines.Add('  end;');
    Assert.IsTrue(TDetectorUtils.IsLikelyAttributePosition(Lines, 3),
      'Attribut vor einer Feldliste mit 5.000 Bezeichnern');
  finally
    Lines.Free;
  end;
end;

procedure TTestRegexStackDepth.AttrPosition_LongIdentListWithoutType_False;
// Gegenprobe: dieselbe Liste ohne ':' ist keine Member-Deklaration - die
// Regex laeuft die ganze Liste ab und scheitert (gierig: Ueberlauf, danach
// Backtracking durch alle 5.000 Wiederholungen).
var
  Lines : TStringList;
begin
  Lines := TStringList.Create;
  try
    Lines.Add('type');
    Lines.Add('  TX = class');
    Lines.Add('  public');
    Lines.Add('    [Inject]');
    Lines.Add('    ' + IdentList('v', LONG_LIST) + ';');
    Lines.Add('  end;');
    Assert.IsFalse(TDetectorUtils.IsLikelyAttributePosition(Lines, 3),
      'Liste ohne Typ-Doppelpunkt ist kein Member');
  finally
    Lines.Free;
  end;
end;

{ uAttributeDuplicate }

procedure TTestRegexStackDepth.AttrDuplicate_LongFieldList_Reported;
// Wie TTestAttributeDuplicate.SameAttributeTwice_Reported, das Member ist
// eine Feldliste mit 5.000 Bezeichnern (LineLooksLikeMemberDecl: gleiche
// Regex wie oben, 4 Rahmen je Bezeichner).
var
  SRC : string;
  F   : TObjectList<TLeakFinding>;
begin
  SRC :=
    'unit t; interface'#13#10 +
    'type'#13#10 +
    '  TTest = class'#13#10 +
    '  public'#13#10 +
    '    [Inject]'#13#10 +
    '    [Inject]'#13#10 +
    '    ' + IdentList('v', LONG_LIST) + ': Integer;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';
  F := RunDetector(SRC, False,
    procedure(Root: TAstNode; const FileName: string; Results: TObjectList<TLeakFinding>)
    begin
      TAttributeDuplicateDetector.AnalyzeUnit(Root, FileName, Results);
    end);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkAttributeDuplicate),
      'doppeltes Attribut vor langer Feldliste');
    Assert.AreEqual('6', TFindingHelper.FirstOf(F, fkAttributeDuplicate).LineNumber,
      'Fund auf dem zweiten Attribut');
  finally
    F.Free;
  end;
end;

{ uConcurrencyExt }

procedure TTestRegexStackDepth.Resume_LongDeclLists_TypeResolved;
// ResolveResumeReceiverType: '\b<Ident>\s*(?:,\s*\w+)*\s*:...' - gierig 2
// Rahmen je Listenelement. Beide Empfaenger fuehren eine Liste mit 5.000
// Bezeichnern an: Worker loest auf TWorkerThread auf (Fund), Anim auf
// TFloatAnimation (kein Thread-Typ -> unterdrueckt).
var
  SRC : string;
  F   : TObjectList<TLeakFinding>;
begin
  SRC :=
    'unit t; implementation'#13#10 +
    'procedure Foo;'#13#10 +
    'var'#13#10 +
    '  Worker, ' + IdentList('v', LONG_LIST) + ': TWorkerThread;'#13#10 +
    '  Anim, ' + IdentList('w', LONG_LIST) + ': TFloatAnimation;'#13#10 +
    'begin'#13#10 +
    '  Worker.Resume;'#13#10 +
    '  Anim.Resume;'#13#10 +
    'end;'#13#10 +
    'end.';
  F := RunDetector(SRC, False,
    procedure(Root: TAstNode; const FileName: string; Results: TObjectList<TLeakFinding>)
    begin
      TConcurrencyExtDetector.AnalyzeUnit(Root, FileName, Results);
    end);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkThreadResumeDeprecated),
      'nur der Thread-Empfaenger');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'Worker.Resume'),
      TFindingHelper.FirstOf(F, fkThreadResumeDeprecated).LineNumber,
      'Fund auf Worker.Resume');
  finally
    F.Free;
  end;
end;

procedure TTestRegexStackDepth.FreeAndNilResult_ManyParenPairsInHeader_Reported;
// Wie TTestConcurrencyExt.FreeAndNilResult_ThreadReturn_Reported, der Kopf
// traegt 1.940 innere Klammerpaare '()'. ResolveResultType sieht nur die
// 4.000 Zeichen vor dem FreeAndNil - mehr als ~1.980 Paare passen nicht
// hinein. RE_FUNC_HEADER gierig: 2 Rahmen je Paar (~3.900), gemessen mit
// PCRE 8.45 im 1-MB-Thread: 1.800 Paare laufen noch, 1.950 laufen ueber.
// Dieser Test ist damit der Grenzfall - ob er OHNE den Umbau sicher
// ueberlaeuft, haengt an der Rahmengroesse des Delphi-PCRE.
const
  PAIRS = 1940;
var
  SRC : string;
  SB  : TStringBuilder;
  i   : Integer;
  F   : TObjectList<TLeakFinding>;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('unit t; implementation'#13#10 + 'function Spawn(');
    for i := 1 to PAIRS do
      SB.Append('()');
    SB.Append('): TWorkerThread;'#13#10 +
      'begin'#13#10 +
      '  Result := TWorkerThread.Create(True);'#13#10 +
      '  FreeAndNil(Result);'#13#10 +
      'end;'#13#10 +
      'end.');
    SRC := SB.ToString;
  finally
    SB.Free;
  end;
  F := RunDetector(SRC, False,
    procedure(Root: TAstNode; const FileName: string; Results: TObjectList<TLeakFinding>)
    begin
      TConcurrencyExtDetector.AnalyzeUnit(Root, FileName, Results);
    end);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTThreadDestroyWithoutTerminate),
      'Rueckgabetyp TWorkerThread trotz 1.940 Klammerpaaren im Kopf erkannt');
  finally
    F.Free;
  end;
end;

{ uFloatEquality }

procedure TTestRegexStackDepth.FloatEq_LongIntegerDeclList_Suppressed;
// OperandDeclaredNonFloat (209) und NearestDeclTypeLowBefore (959):
// '\b<Var>\b\s*(?:,\s*[A-Za-z_]\w*\s*)*:...' - gierig 3 Rahmen je Element.
// Ratio ist file-global Double (FloatVars). In Bar ist die naechstliegende
// Deklaration die globale -> Fund. In Foo fuehrt Ratio eine Integer-Liste
// mit 5.000 Bezeichnern an -> naechstliegend Integer -> unterdrueckt.
var
  SRC : string;
  F   : TObjectList<TLeakFinding>;
begin
  SRC :=
    'unit t; implementation'#13#10 +
    'var Ratio: Double;'#13#10 +
    'procedure Bar;'#13#10 +
    'begin'#13#10 +
    '  if Ratio = 0.5 then Exit;'#13#10 +
    'end;'#13#10 +
    'procedure Foo;'#13#10 +
    'var Ratio, ' + IdentList('v', LONG_LIST) + ': Integer;'#13#10 +
    'begin'#13#10 +
    '  if Ratio = 0.5 then Exit;'#13#10 +
    'end;'#13#10 +
    'end.';
  F := RunDetector(SRC, True,
    procedure(Root: TAstNode; const FileName: string; Results: TObjectList<TLeakFinding>)
    begin
      TFloatEqualityDetector.AnalyzeUnit(Root, FileName, Results);
    end);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFloatEquality),
      'nur der Vergleich gegen die globale Double-Variable');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'if Ratio = 0.5'),
      TFindingHelper.FirstOf(F, fkFloatEquality).LineNumber,
      'Fund in Bar');
  finally
    F.Free;
  end;
end;

procedure TTestRegexStackDepth.FloatEq_LongFloatDeclLists_SentinelDemoted;
// Wie TTestFloatEquality.SentinelZeroLocalSimpleAssigns_DemotedToLow, die
// lokalen Best und Seed fuehren je eine Double-Liste mit 5.000 Bezeichnern
// an (Best ist zusaetzlich file-global deklariert, damit es in FloatVars
// steht - Komma-Listen fuellen FloatVars nur mit dem letzten Namen).
// Durchlaufen werden IsLocalFloatVarInHeader (429, Best), die Integer-
// Deklarationssuche im Kopf (712, beide Listen) und die Local-Ident-RHS-
// Pruefung (554, Seed) - je 3 Rahmen je Element.
var
  SRC : string;
  F   : TObjectList<TLeakFinding>;
begin
  SRC :=
    'unit t; implementation'#13#10 +
    'var Best: Double;'#13#10 +
    'procedure Foo;'#13#10 +
    'var Best, ' + IdentList('v', LONG_LIST) + ': Double;'#13#10 +
    '    Seed, ' + IdentList('w', LONG_LIST) + ': Double;'#13#10 +
    'begin'#13#10 +
    '  Seed := 2.5;'#13#10 +
    '  Best := 0;'#13#10 +
    '  if Best = 0 then'#13#10 +
    '    Best := Seed;'#13#10 +
    'end;'#13#10 +
    'end.';
  F := RunDetector(SRC, True,
    procedure(Root: TAstNode; const FileName: string; Results: TObjectList<TLeakFinding>)
    begin
      TFloatEqualityDetector.AnalyzeUnit(Root, FileName, Results);
    end);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFloatEquality),
      'Sentinel-Zero bleibt ein Fund');
    Assert.AreEqual<TFindingConfidence>(fcLow,
      TFindingHelper.FirstOf(F, fkFloatEquality).Confidence,
      'lokales var mit nur direkten einfachen Zuweisungen gegen 0 -> fcLow');
  finally
    F.Free;
  end;
end;

{ uPerfHotspots / uPointerSubtraction / uStringFromPointer }

procedure TTestRegexStackDepth.PerfConcat_LongIntegerDeclList_Suppressed;
// LhsDeclaredNumeric: Total fuehrt eine Integer-Liste mit 5.000
// Bezeichnern an -> numerischer Akkumulator, kein Fund. Die echte
// String-Verkettung daneben bleibt gemeldet.
var
  SRC : string;
  F   : TObjectList<TLeakFinding>;
begin
  SRC :=
    'unit t; implementation'#13#10 +
    'procedure Foo;'#13#10 +
    'var Total, ' + IdentList('v', LONG_LIST) + ': Integer;'#13#10 +
    '    s: string; i: Integer;'#13#10 +
    'begin'#13#10 +
    '  for i := 0 to 10 do'#13#10 +
    '  begin'#13#10 +
    '    Total := Total + i;'#13#10 +
    '    s := s + IntToStr(i);'#13#10 +
    '  end;'#13#10 +
    'end;'#13#10 +
    'end.';
  F := RunDetector(SRC, True,
    procedure(Root: TAstNode; const FileName: string; Results: TObjectList<TLeakFinding>)
    begin
      TPerfHotspotsDetector.AnalyzeUnit(Root, FileName, Results);
    end);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkStringConcatInLoop),
      'nur die String-Verkettung');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 's := s + '),
      TFindingHelper.FirstOf(F, fkStringConcatInLoop).LineNumber,
      'Fund auf der String-Verkettung');
  finally
    F.Free;
  end;
end;

procedure TTestRegexStackDepth.PointerSub_LongWordDeclList_Suppressed;
// OperandDeclaredNonPointer: A fuehrt eine Word-Liste mit 5.000
// Bezeichnern an -> beide Operanden Nicht-Pointer, kein Fund. Die
// Pointer-Differenz daneben bleibt gemeldet.
var
  SRC : string;
  F   : TObjectList<TLeakFinding>;
begin
  SRC :=
    'unit t; implementation'#13#10 +
    'procedure Foo;'#13#10 +
    'var A, ' + IdentList('v', LONG_LIST) + ': Word;'#13#10 +
    '    B: Word;'#13#10 +
    '    P1, P2: Pointer;'#13#10 +
    '    D: Integer;'#13#10 +
    'begin'#13#10 +
    '  D := Cardinal(A) - Cardinal(B);'#13#10 +
    '  D := Cardinal(P1) - Cardinal(P2);'#13#10 +
    'end;'#13#10 +
    'end.';
  F := RunDetector(SRC, False,
    procedure(Root: TAstNode; const FileName: string; Results: TObjectList<TLeakFinding>)
    begin
      TPointerSubtractionDetector.AnalyzeUnit(Root, FileName, Results);
    end);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkPointerSubtraction),
      'nur die Pointer-Differenz');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'Cardinal(P1)'),
      TFindingHelper.FirstOf(F, fkPointerSubtraction).LineNumber,
      'Fund auf der Pointer-Differenz');
  finally
    F.Free;
  end;
end;

procedure TTestRegexStackDepth.StringFromPointer_LongStringDeclList_Suppressed;
// OperandIsManagedString: PName fuehrt eine string-Liste mit 5.000
// Bezeichnern an -> sichere Wert-Konvertierung, kein Fund. Der Cast aus
// PAnsiChar daneben bleibt gemeldet.
var
  SRC : string;
  F   : TObjectList<TLeakFinding>;
begin
  SRC :=
    'unit t; implementation'#13#10 +
    'procedure Foo;'#13#10 +
    'var PName, ' + IdentList('v', LONG_LIST) + ': string;'#13#10 +
    '    PBuf: PAnsiChar;'#13#10 +
    '    s: string;'#13#10 +
    'begin'#13#10 +
    '  s := string(PName);'#13#10 +
    '  s := string(PBuf);'#13#10 +
    'end;'#13#10 +
    'end.';
  F := RunDetector(SRC, False,
    procedure(Root: TAstNode; const FileName: string; Results: TObjectList<TLeakFinding>)
    begin
      TStringFromPointerDetector.AnalyzeUnit(Root, FileName, Results);
    end);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkStringFromPointer),
      'nur der Cast aus dem Pointer');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'string(PBuf)'),
      TFindingHelper.FirstOf(F, fkStringFromPointer).LineNumber,
      'Fund auf string(PBuf)');
  finally
    F.Free;
  end;
end;

{ uHardcodedString }

const
  MSG_ASSIGN = 'User-visible string %s assigned directly - move to resourcestring / i18n';
  MSG_DIALOG = 'User-visible string %s in ShowMessage/MessageDlg - move to resourcestring / i18n';

// 'w0''w1''...''w<N-1>' - Literal-Rumpf mit N-1 verdoppelten Apostrophen.
function PairBody(ACount: Integer): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to ACount - 1 do
    begin
      if i > 0 then SB.Append('''''');
      SB.Append('w').Append(i);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function RunHardcodedString(const ASrc: string): TObjectList<TLeakFinding>;
begin
  Result := RunDetector(ASrc, False,
    procedure(Root: TAstNode; const FileName: string; Results: TObjectList<TLeakFinding>)
    begin
      THardcodedStringDetector.AnalyzeUnit(Root, FileName, Results);
    end);
end;

procedure TTestRegexStackDepth.HardcodedString_LongLiteral_FullBody;
// Literal mit 5.000 verdoppelten Apostrophen (SQL-Text mit ''x''-Werten).
// Alter Rumpf '([^'\n]*(?:''[^'\n]*)*)' gierig: 2 Rahmen je ''.
var
  Body : string;
  F    : TObjectList<TLeakFinding>;
begin
  Body := PairBody(LONG_LIST + 1);
  F := RunHardcodedString(
    'unit t; implementation'#13#10 +
    'procedure Foo;'#13#10 +
    'begin'#13#10 +
    '  Memo1.Text := ''' + Body + ''';'#13#10 +
    'end;'#13#10 +
    'end.');
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHardcodedString),
      'langes Literal');
    Assert.AreEqual(Format(MSG_ASSIGN, [QuotedStr(Body)]),
      TFindingHelper.FirstOf(F, fkHardcodedString).MissingVar,
      'der ganze Rumpf ist Gruppe 1');
  finally
    F.Free;
  end;
end;

procedure TTestRegexStackDepth.HardcodedString_LongOpenLiteral_CutBeforeLastPair;
// Offenes Literal (Zeile endet ohne schliessendes ') mit 5.000 ''. Das alte
// Muster fiel per Backtracking auf "Rumpf bis vor das LETZTE ''" zurueck
// (dessen erstes ' schloss) - Zweig 2 des neuen Musters liefert dasselbe.
var
  Prefix : string;
  F      : TObjectList<TLeakFinding>;
begin
  Prefix := PairBody(LONG_LIST);
  F := RunHardcodedString(
    'unit t; implementation'#13#10 +
    'procedure Foo;'#13#10 +
    'begin'#13#10 +
    '  Memo1.Text := ''' + Prefix + ''''' offen'#13#10 +
    'end;'#13#10 +
    'end.');
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHardcodedString),
      'offenes langes Literal');
    Assert.AreEqual(Format(MSG_ASSIGN, [QuotedStr(Prefix)]),
      TFindingHelper.FirstOf(F, fkHardcodedString).MissingVar,
      'Gruppe 1 endet vor dem letzten verdoppelten Apostroph');
  finally
    F.Free;
  end;
end;

procedure TTestRegexStackDepth.HardcodedString_ShortOpenLiteral_CutBeforeLastPair;
// Randfall des Umbaus (kurz, vor und nach dem Umbau gruen): offenes
// Literal mit zwei '' in ShowMessage -> Gruppe 1 = Zeile ''eins (bis vor
// das zweite '', dessen erstes ' das Literal schloss).
var
  F : TObjectList<TLeakFinding>;
begin
  F := RunHardcodedString(
    'unit t; implementation'#13#10 +
    'procedure Foo;'#13#10 +
    'begin'#13#10 +
    '  ShowMessage(''Zeile ''''eins'''' offen'#13#10 +
    'end;'#13#10 +
    'end.');
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHardcodedString),
      'offenes Literal mit verdoppelten Apostrophen');
    Assert.AreEqual(Format(MSG_DIALOG, [QuotedStr('Zeile ''''eins')]),
      TFindingHelper.FirstOf(F, fkHardcodedString).MissingVar,
      'Gruppe 1 endet vor dem letzten verdoppelten Apostroph');
  finally
    F.Free;
  end;
end;

procedure TTestRegexStackDepth.HardcodedString_OpenLiteralWithoutPair_NotReported;
// Randfall des Umbaus (vor und nach dem Umbau gruen): offenes Literal OHNE
// '' - beide Zweige scheitern wie das alte Muster.
var
  F : TObjectList<TLeakFinding>;
begin
  F := RunHardcodedString(
    'unit t; implementation'#13#10 +
    'procedure Foo;'#13#10 +
    'begin'#13#10 +
    '  Form1.Caption := ''Mein Programm'#13#10 +
    'end;'#13#10 +
    'end.');
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedString),
      'offenes Literal ohne verdoppelten Apostroph');
  finally
    F.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRegexStackDepth);

end.
