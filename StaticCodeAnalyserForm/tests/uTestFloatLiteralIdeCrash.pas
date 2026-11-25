unit uTestFloatLiteralIdeCrash;

// Tests fuer TFloatLiteralIdeCrashDetector (SCA208, 2026-11-25): eine Unit
// mit Gleitkomma-Literal kann Delphi 12 beim Anzeigen zum Absturz bringen
// (IDE-Parser, clr.dll 0xC00000FD). Genau ein Fund je Datei am ersten
// Literal, Hint, standardmaessig aus.
//
// Der Detektor liest den Dateitext (AcquireLines) - die Tests laufen ueber
// FindingsOfFile (dort registriert); Fakten und Include-Faelle zusaetzlich
// direkt ueber FindFirstLiteral bzw. AnalyzeUnit.
//
// Jede Negativprobe steht mit einer WACHE in derselben Quelle: ein echtes
// Literal ('0.5') HINTER dem Konstrukt, das nicht zaehlen darf. Erwartet ist
// genau der eine Fund an der Wache. Ohne Detektor ist jeder Test damit rot
// (0 Funde); zaehlt der Detektor das Konstrukt faelschlich, steht der Fund
// auf dessen Zeile statt auf der Wache.
//
// Die Randfaelle R1-R3 folgen der IDE-Messung vom 2026-11-25 (Delphi 12.1
// CE, vor und nach Patch 1): abgeschalteter {$IFDEF}-Zweig und Literal in
// einer eingebundenen Datei melden; die gescannte .inc selbst und ein
// Methodenaufruf auf einem Ganzzahl-Literal ('5.ToString', '5.Equals(5)')
// nicht. '1.' ohne Bezeichner dahinter ist ungemessen und meldet.
// Aendert sich ein Befund, aendern sich LiteralCounts und genau die Tests
// im Abschnitt "Randfaelle".

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFloatLiteralIdeCrash = class
  public
    // ---- Melden ------------------------------------------------------------
    [Test] procedure Decimal_4_90_Reported;
    [Test] procedure Decimal_0_5_Reported;
    [Test] procedure Exponent_1e5_Reported;
    [Test] procedure Exponent_1_5E_minus3_Reported;
    [Test] procedure TwoLiterals_OneFindingAtFirst;
    [Test] procedure TwoLiteralsOnOneLine_FirstColumn;
    [Test] procedure Finding_IsHintCodeSmellFileLevel;
    // ---- Nicht melden (je mit Wache) ---------------------------------------
    [Test] procedure Integer_490_NotCounted;
    [Test] procedure Hex_FF_NotCounted;
    [Test] procedure Range_1_5_NotCounted;
    [Test] procedure NumberInComment_NotCounted;
    [Test] procedure NumberInString_NotCounted;
    [Test] procedure IntegerDivision_NotCounted;
    [Test] procedure StrToFloatOfString_NotCounted;
    [Test] procedure NoLiteral_NoFinding;
    // ---- Randfaelle R1-R3 (IDE-Messung 2026-11-25) --------------------------
    [Test] procedure R1_InactiveIfdefBranch_Reported;
    [Test] procedure R2_IncludedFile_ReportedAtDirective;
    [Test] procedure R2_IncludeOrder_FirstInReadingOrderWins;
    [Test] procedure R2_ScannedIncFile_NotReported;
    [Test] procedure R3_IntegerDotToString_NotCounted;
    [Test] procedure R3_IntegerDotEquals_NotCounted;
    [Test] procedure R3_TrailingDotWithoutIdent_Reported;
    [Test] procedure LiteralCounts_FollowsMeasurement;
    // ---- Pipeline, Katalog, Profile ----------------------------------------
    [Test] procedure Pipeline_VisibleAndSuppressible;
    [Test] procedure CatalogExample_BadReported_GoodClean;
    [Test] procedure Profiles_NotDefault_StrictAndStyle;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uRuleCatalog, uLexer,
  uFloatLiteralIdeCrash,
  uTestFindingHelper;

const
  CRLF = #13#10;
  // Meldungsschwanz (englisch, Teil des Fingerprints) - woertlich gepinnt:
  // eine Textaenderung bewegt jeden Bestandsfund.
  MSG_TAIL = 'Delphi 12 may crash while showing this unit ' +
    '(IDE parser fault, clr.dll 0xC00000FD)';

function Msg(const AText: string): string;
begin
  Result := Format('Floating-point literal `%s`: %s', [AText, MSG_TAIL]);
end;

function MsgInc(const AText, AInclude: string; ALine: Integer): string;
begin
  Result := Format('Floating-point literal `%s` in include file %s, ' +
    'line %d: %s', [AText, AInclude, ALine, MSG_TAIL]);
end;

// Eine Quelle aus Zeilen (je mit CRLF) - Zeile k des Arrays ist Zeile k + 1.
function Src(const ALines: array of string): string;
var
  i : Integer;
begin
  Result := '';
  for i := 0 to High(ALines) do
    Result := Result + ALines[i] + CRLF;
end;

// Eindeutiger Dateiname im Temp-Verzeichnis - dort legt auch FindingsOfFile
// seine Unit ab, ein {$I} findet die Datei also relativ.
function TempName(const AExt: string): string;
begin
  Result := 'sca_test_flt_' + TGuid.NewGuid.ToString.Replace('{', '')
    .Replace('}', '').Replace('-', '') + AExt;
end;

function TempPathOf(const AName: string): string;
begin
  Result := TPath.Combine(TPath.GetTempPath, AName);
end;

// Genau ein SCA208-Fund in ASrc (FindingsOfFile) an Zeile/Spalte mit
// Meldung. Funde anderer Regeln zaehlen nicht.
procedure CheckHit(const ASrc: string; ALine, ACol: Integer;
  const AMsg: string);
var
  F : TObjectList<TLeakFinding>;
  X : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(ASrc);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFloatLiteralIdeCrash),
      'Zahl der SCA208-Funde');
    X := TFindingHelper.FirstOf(F, fkFloatLiteralIdeCrash);
    Assert.AreEqual(IntToStr(ALine), X.LineNumber, 'Zeile');
    Assert.AreEqual<Integer>(ACol, X.FixArgs.Col, 'Spalte');
    Assert.AreEqual(AMsg, X.MissingVar, 'Meldung');
  finally
    F.Free;
  end;
end;

// Kein SCA208-Fund in ASrc. Nur zusammen mit einer Positivprobe in
// demselben Test verwenden - allein waere er ohne Detektor gruen.
procedure CheckNoHit(const ASrc: string);
var
  F : TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(ASrc);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFloatLiteralIdeCrash),
      'Zahl der SCA208-Funde');
  finally
    F.Free;
  end;
end;

// Quelle mit einer Konstanten-Zeile AConstLine (Zeile 4) und der Wache
// 'Guard = 0.5;' in Zeile 5, Spalte 11.
function WithGuard(const AConstLine: string): string;
begin
  Result := Src([
    'unit A;',                 // 1
    'interface',               // 2
    'const',                   // 3
    AConstLine,                // 4
    '  Guard = 0.5;',          // 5  Wache
    'implementation',          // 6
    'end.']);                  // 7
end;

const
  GUARD_LINE = 5;
  GUARD_COL  = 11;

// Ein-Zweig-Sicht des Scans fuer die Dauer eines Tests (R1). Die Globals
// gehoeren dem Prozess - Sichern und Zuruecksetzen immer im try/finally.
type
  TIfdefView = record
    OldOn      : Boolean;
    OldDefines : TArray<string>;
    procedure Enter(const ADefines: array of string);
    procedure Leave;
  end;

procedure TIfdefView.Enter(const ADefines: array of string);
var
  D : string;
begin
  OldOn := gLexerIfdefSkipEnabled;
  if Assigned(gLexerIfdefDefines) then
    OldDefines := gLexerIfdefDefines.ToStringArray
  else
    OldDefines := nil;
  LexerIfdefClear;
  for D in ADefines do
    LexerIfdefAddDefine(D);
  gLexerIfdefSkipEnabled := True;
end;

procedure TIfdefView.Leave;
var
  D : string;
begin
  LexerIfdefClear;
  for D in OldDefines do
    LexerIfdefAddDefine(D);
  gLexerIfdefSkipEnabled := OldOn;
end;

{ ---- Melden ---------------------------------------------------------------- }

procedure TTestFloatLiteralIdeCrash.Decimal_4_90_Reported;
begin
  CheckHit(WithGuard('  Price = 4.90;'), 4, 11, Msg('4.90'));
end;

procedure TTestFloatLiteralIdeCrash.Decimal_0_5_Reported;
// Ohne Wache: das Literal ist der einzige Kandidat.
begin
  CheckHit(Src([
    'unit A;',                 // 1
    'implementation',          // 2
    'procedure P;',            // 3
    'var X: Double;',          // 4
    'begin',                   // 5
    '  X := 0.5;',             // 6
    'end;',                    // 7
    'end.']),                  // 8
    6, 8, Msg('0.5'));
end;

procedure TTestFloatLiteralIdeCrash.Exponent_1e5_Reported;
begin
  CheckHit(WithGuard('  Big = 1e5;'), 4, 9, Msg('1e5'));
end;

procedure TTestFloatLiteralIdeCrash.Exponent_1_5E_minus3_Reported;
begin
  CheckHit(WithGuard('  Small = 1.5E-3;'), 4, 11, Msg('1.5E-3'));
end;

procedure TTestFloatLiteralIdeCrash.TwoLiterals_OneFindingAtFirst;
// Zwei Literale in verschiedenen Zeilen: EIN Fund, am ersten.
begin
  CheckHit(Src([
    'unit A;',                 // 1
    'interface',               // 2
    'const',                   // 3
    '  A = 2.5;',              // 4
    '  B = 7;',                // 5
    '  C = 3.75;',             // 6
    'implementation',          // 7
    'end.']),                  // 8
    4, 7, Msg('2.5'));
end;

procedure TTestFloatLiteralIdeCrash.TwoLiteralsOnOneLine_FirstColumn;
// Zwei Literale in einer Zeile: EIN Fund, Spalte des ersten.
begin
  CheckHit(Src([
    'unit A;',                 // 1
    'interface',               // 2
    'const',                   // 3
    '  S = 1.25 + 0.75;',      // 4
    'implementation',          // 5
    'end.']),                  // 6
    4, 7, Msg('1.25'));
end;

procedure TTestFloatLiteralIdeCrash.Finding_IsHintCodeSmellFileLevel;
// Hint (der Code ist korrekt), Code Smell, fcMedium (ob es bricht, haengt
// am Rechner), Datei-Ebene ohne Methode, SCA208.
var
  F : TObjectList<TLeakFinding>;
  X : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(WithGuard('  Price = 4.90;'));
  try
    X := TFindingHelper.FirstOf(F, fkFloatLiteralIdeCrash);
    Assert.IsNotNull(X, 'Fund fehlt');
    Assert.AreEqual<Integer>(Ord(lsHint), Ord(X.Severity), 'Schweregrad');
    Assert.AreEqual<Integer>(Ord(lsHint),
      Ord(KindDefaultSeverity(fkFloatLiteralIdeCrash)), 'Katalog-Schweregrad');
    Assert.AreEqual<Integer>(Ord(fcMedium), Ord(X.Confidence), 'Konfidenz');
    Assert.AreEqual<Integer>(Ord(ftCodeSmell), Ord(KindFindingType(X.Kind)),
      'Typ');
    Assert.AreEqual('', X.MethodName, 'Methode');
    Assert.AreEqual('FloatLiteralIdeCrash', KindName(fkFloatLiteralIdeCrash),
      'Name');
    Assert.AreEqual('SCA208', X.ResolvedRuleId, 'Regel-ID');
  finally
    F.Free;
  end;
end;

{ ---- Nicht melden ----------------------------------------------------------- }

procedure TTestFloatLiteralIdeCrash.Integer_490_NotCounted;
begin
  CheckHit(WithGuard('  Cents = 490;'), GUARD_LINE, GUARD_COL, Msg('0.5'));
end;

procedure TTestFloatLiteralIdeCrash.Hex_FF_NotCounted;
// '$FF' ist ein Hex-Integer; auch die Hex-Ziffer 'E' macht keinen Exponenten.
begin
  CheckHit(WithGuard('  Mask = $FF; Mask2 = $1E5;'), GUARD_LINE, GUARD_COL,
    Msg('0.5'));
end;

procedure TTestFloatLiteralIdeCrash.Range_1_5_NotCounted;
// '1..5' ist Integer, '..', Integer (Lookahead in TLexer.ReadNumber) - als
// Teilbereich, Arraygrenze und case-Marke (alle drei an der IDE gemessen:
// kein Absturz).
begin
  CheckHit(Src([
    'unit A;',                                  // 1
    'interface',                                // 2
    'type',                                     // 3
    '  TSmall = 1..5;',                         // 4
    '  TArr = array[1..5] of Integer;',         // 5
    'implementation',                           // 6
    'procedure P(I: Integer);',                 // 7
    'begin',                                    // 8
    '  case I of 1..5: Exit; end;',             // 9
    'end;',                                     // 10
    'const',                                    // 11
    '  Guard = 0.5;',                           // 12  Wache
    'end.']),                                   // 13
    12, 11, Msg('0.5'));
end;

procedure TTestFloatLiteralIdeCrash.NumberInComment_NotCounted;
// Alle drei Kommentarformen, einzeilig und ueber Zeilen.
begin
  CheckHit(Src([
    'unit A;',                                  // 1
    'interface',                                // 2
    '// Price 4.90',                            // 3
    '{ Rate 1.5E-3 }',                          // 4
    '(* Factor 0.25 *)',                        // 5
    '{',                                        // 6
    '  Old = 2.5;',                             // 7
    '}',                                        // 8
    'const',                                    // 9
    '  Guard = 0.5;',                           // 10  Wache
    'implementation',                           // 11
    'end.']),                                   // 12
    10, 11, Msg('0.5'));
end;

procedure TTestFloatLiteralIdeCrash.NumberInString_NotCounted;
begin
  CheckHit(Src([
    'unit A;',                                  // 1
    'interface',                                // 2
    'const',                                    // 3
    '  S = ''4.90'';',                          // 4
    '  T = ''it''''s 1e5'';',                   // 5
    '  Guard = 0.5;',                           // 6  Wache
    'implementation',                           // 7
    'end.']),                                   // 8
    6, 11, Msg('0.5'));
end;

procedure TTestFloatLiteralIdeCrash.IntegerDivision_NotCounted;
// '49 / 10' ergibt einen Gleitkommawert, schreibt aber kein Literal.
begin
  CheckHit(WithGuard('  Price = 49 / 10;'), GUARD_LINE, GUARD_COL,
    Msg('0.5'));
end;

procedure TTestFloatLiteralIdeCrash.StrToFloatOfString_NotCounted;
begin
  CheckHit(Src([
    'unit A;',                                  // 1
    'implementation',                           // 2
    'uses System.SysUtils;',                    // 3
    'procedure P;',                             // 4
    'var X: Double;',                           // 5
    'begin',                                    // 6
    '  X := StrToFloat(''4.90'');',             // 7
    '  X := 0.5;',                              // 8  Wache
    'end;',                                     // 9
    'end.']),                                   // 10
    8, 8, Msg('0.5'));
end;

procedure TTestFloatLiteralIdeCrash.NoLiteral_NoFinding;
// Datei ohne Literal: kein Fund. Dieselbe Datei mit einem Literal meldet -
// so ist der Test ohne Detektor rot.
begin
  CheckNoHit(Src([
    'unit A;',                                  // 1
    'interface',                                // 2
    'const',                                    // 3
    '  Cents = 490; Mask = $FF;',               // 4
    '  S = ''4.90''; // 4.90',                  // 5
    'implementation',                           // 6
    'end.']));                                  // 7
  CheckHit(Src([
    'unit A;',                                  // 1
    'interface',                                // 2
    'const',                                    // 3
    '  Cents = 490; Mask = $FF;',               // 4
    '  S = ''4.90''; // 4.90',                  // 5
    '  Price = 4.90;',                          // 6
    'implementation',                           // 7
    'end.']),                                   // 8
    6, 11, Msg('4.90'));
end;

{ ---- Randfaelle R1-R3 -------------------------------------------------------- }

procedure TTestFloatLiteralIdeCrash.R1_InactiveIfdefBranch_Reported;
// R1: der Editor zeigt auch den abgeschalteten Zweig. Ohne Ein-Zweig-Sicht
// (Test-Harness) ist es ein gewoehnlicher Fund; mit Sicht setzt der Lauf den
// Fakt InInactiveBranch - und meldet trotzdem: an der IDE gemessen stuerzt
// auch ein Literal im abgeschalteten Zweig ab (mit Ganzzahl dort nicht).
const
  INACTIVE_SRC: array[0..5] of string = (
    'unit A;',                                  // 1
    'implementation',                           // 2
    '{$IFDEF SCA_NEVER_DEFINED}',               // 3
    'const X = 4.90;',                          // 4
    '{$ENDIF}',                                 // 5
    'end.');                                    // 6
var
  View : TIfdefView;
  Hit  : TFloatLiteralHit;
begin
  CheckHit(Src(INACTIVE_SRC), 4, 11, Msg('4.90'));
  View.Enter(['MSWINDOWS']);
  try
    Assert.IsTrue(TFloatLiteralIdeCrashDetector.FindFirstLiteral(
      Src(INACTIVE_SRC), 'sample.pas', Hit), 'abgeschalteter Zweig: Treffer');
    Assert.AreEqual<Integer>(4, Hit.Line, 'Zeile');
    Assert.IsTrue(Hit.Facts.InInactiveBranch, 'Fakt R1 gesetzt');
    // Gegenprobe: derselbe Zweig unter einem gesetzten Define ist aktiv.
    Assert.IsTrue(TFloatLiteralIdeCrashDetector.FindFirstLiteral(Src([
      'unit A;', 'implementation', '{$IFDEF MSWINDOWS}', 'const X = 4.90;',
      '{$ENDIF}', 'end.']), 'sample.pas', Hit), 'aktiver Zweig: Treffer');
    Assert.IsFalse(Hit.Facts.InInactiveBranch, 'Fakt R1 im aktiven Zweig');
    // Ueber den Detektor mit Sicht: weiterhin ein Fund.
    CheckHit(Src(INACTIVE_SRC), 4, 11, Msg('4.90'));
  finally
    View.Leave;
  end;
end;

procedure TTestFloatLiteralIdeCrash.R2_IncludedFile_ReportedAtDirective;
// R2a: das Literal steht nur in der eingebundenen Datei - an der IDE
// gemessen stuerzt das Anzeigen der UNIT ab. Der Fund steht an der
// Direktive der gescannten Datei (Zeile 3, Spalte 1), die Meldung nennt
// Literal, Datei und Zeile. Steht die Direktive in einem abgeschalteten
// Zweig, erbt das Literal den Fakt R1.
var
  IncName, IncPath : string;
  Hit              : TFloatLiteralHit;
  View             : TIfdefView;
begin
  IncName := TempName('.inc');
  IncPath := TempPathOf(IncName);
  TFile.WriteAllText(IncPath, 'const' + CRLF + '  Rate = 4.90;' + CRLF,
    TEncoding.UTF8);
  try
    CheckHit(Src([
      'unit A;',                                // 1
      'interface',                              // 2
      '{$I ' + IncName + '}',                   // 3
      'implementation',                         // 4
      'end.']),                                 // 5
      3, 1, MsgInc('4.90', IncName, 2));
    Assert.IsTrue(TFloatLiteralIdeCrashDetector.FindFirstLiteral(Src([
      'unit A;', 'interface', '{$INCLUDE ''' + IncName + '''}',
      'implementation', 'end.']), TempPathOf('host.pas'), Hit),
      '{$INCLUDE ''..''}: Treffer');
    Assert.IsTrue(Hit.Facts.InIncludedFile, 'Fakt R2 (eingebunden)');
    Assert.IsFalse(Hit.Facts.ScannedFileIsInclude, 'gescannt wird eine .pas');
    Assert.AreEqual(IncName, Hit.IncludeName, 'Include-Name');
    Assert.AreEqual<Integer>(2, Hit.IncludeLine, 'Include-Zeile');
    // Die Direktive im abgeschalteten Zweig (Ein-Zweig-Sicht).
    View.Enter(['MSWINDOWS']);
    try
      Assert.IsTrue(TFloatLiteralIdeCrashDetector.FindFirstLiteral(Src([
        'unit A;', 'interface', '{$IFDEF SCA_NEVER_DEFINED}',
        '{$I ' + IncName + '}', '{$ENDIF}', 'implementation', 'end.']),
        TempPathOf('host.pas'), Hit), 'Direktive im toten Zweig: Treffer');
      Assert.IsTrue(Hit.Facts.InInactiveBranch, 'Fakt R1 vererbt');
      Assert.IsTrue(Hit.Facts.InIncludedFile, 'Fakt R2');
    finally
      View.Leave;
    end;
  finally
    TFile.Delete(IncPath);
  end;
end;

procedure TTestFloatLiteralIdeCrash.R2_IncludeOrder_FirstInReadingOrderWins;
// "Erstes Literal" in Leserichtung: die Direktive steht fuer den Inhalt
// ihrer Datei. Vor einem direkten Literal gewinnt sie, dahinter nicht. Eine
// Include-Datei ohne Literal, {$I+} und eine fehlende Datei melden nichts.
var
  IncName, IncPath, EmptyName, EmptyPath : string;
begin
  IncName   := TempName('.inc');
  IncPath   := TempPathOf(IncName);
  EmptyName := TempName('.inc');
  EmptyPath := TempPathOf(EmptyName);
  TFile.WriteAllText(IncPath, 'const Rate = 4.90;' + CRLF, TEncoding.UTF8);
  TFile.WriteAllText(EmptyPath, 'const Count = 3;' + CRLF, TEncoding.UTF8);
  try
    CheckHit(Src([
      'unit A;',                                // 1
      'interface',                              // 2
      '{$I ' + IncName + '}',                   // 3
      'const Guard = 0.5;',                     // 4
      'implementation',                         // 5
      'end.']),                                 // 6
      3, 1, MsgInc('4.90', IncName, 1));
    CheckHit(Src([
      'unit A;',                                // 1
      'interface',                              // 2
      'const Guard = 0.5;',                     // 3
      '{$I ' + IncName + '}',                   // 4
      'implementation',                         // 5
      'end.']),                                 // 6
      3, 15, Msg('0.5'));
    CheckHit(Src([
      'unit A;',                                // 1
      'interface',                              // 2
      '{$I ' + EmptyName + '}',                 // 3
      '{$I+} {$I sca_test_flt_missing.inc}',    // 4
      'const Guard = 0.5;',                     // 5  Wache
      'implementation',                         // 6
      'end.']),                                 // 7
      5, 15, Msg('0.5'));
  finally
    TFile.Delete(IncPath);
    TFile.Delete(EmptyPath);
  end;
end;

procedure TTestFloatLiteralIdeCrash.R2_ScannedIncFile_NotReported;
// R2b: die gescannte Datei ist selbst eine .inc - sie anzuzeigen ist
// harmlos (gemessen), also KEIN Fund, auch nicht fuer eine von ihr
// eingebundene Datei. Wache: dieselbe .inc ueber eine Unit eingebunden
// meldet an der Direktive.
var
  IncName, IncPath, NestName, NestPath : string;
  F                                    : TObjectList<TLeakFinding>;
  Hit                                  : TFloatLiteralHit;
begin
  NestName := TempName('.inc');
  NestPath := TempPathOf(NestName);
  IncName  := TempName('.inc');
  IncPath  := TempPathOf(IncName);
  TFile.WriteAllText(NestPath, 'const Other = 4.90;' + CRLF, TEncoding.UTF8);
  TFile.WriteAllText(IncPath, 'const' + CRLF + '  Rate = 0.5;' + CRLF +
    '{$I ' + NestName + '}' + CRLF, TEncoding.UTF8);
  F := TObjectList<TLeakFinding>.Create(True);
  try
    TFloatLiteralIdeCrashDetector.AnalyzeUnit(nil, IncPath, F);
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFloatLiteralIdeCrash),
      '.inc selbst gescannt: kein Fund');
    Assert.IsFalse(TFloatLiteralIdeCrashDetector.FindFirstLiteral(
      'const Rate = 0.5;', 'part.inc', Hit), '.inc: kein zaehlendes Literal');
    CheckHit(Src([
      'unit A;',                                // 1
      'interface',                              // 2
      '{$I ' + IncName + '}',                   // 3
      'implementation',                         // 4
      'end.']),                                 // 5
      3, 1, MsgInc('0.5', IncName, 2));
  finally
    F.Free;
    TFile.Delete(IncPath);
    TFile.Delete(NestPath);
  end;
end;

procedure TTestFloatLiteralIdeCrash.R3_IntegerDotToString_NotCounted;
// R3: '5.ToString' - der SCA-Lexer liest '5.' als tkFloatLit, die IDE
// stuerzt nicht ab (gemessen). Kein Fund am Aufruf, der Fund steht an der
// Wache dahinter.
var
  Hit : TFloatLiteralHit;
begin
  CheckHit(Src([
    'unit A;',                                  // 1
    'implementation',                           // 2
    'uses System.SysUtils;',                    // 3
    'procedure P;',                             // 4
    'var S: string; X: Double;',                // 5
    'begin',                                    // 6
    '  S := 5.ToString;',                       // 7
    '  X := 0.5;',                              // 8  Wache
    'end;',                                     // 9
    'end.']),                                   // 10
    8, 8, Msg('0.5'));
  Assert.IsFalse(TFloatLiteralIdeCrashDetector.FindFirstLiteral(
    'S := 5.ToString;', 'sample.pas', Hit), 'nur der Aufruf: kein Treffer');
  Assert.IsTrue(TFloatLiteralIdeCrashDetector.FindFirstLiteral(
    'S := 5.ToString; X := 4.90;', 'sample.pas', Hit), 'Gegenprobe: Treffer');
  Assert.AreEqual('4.90', Hit.Text, 'Literal der Gegenprobe');
  Assert.IsFalse(Hit.Facts.DotWithoutDigits, 'Fakt R3 bei 4.90');
end;

procedure TTestFloatLiteralIdeCrash.R3_IntegerDotEquals_NotCounted;
// R3 mit 'E' hinter dem Punkt: der Lexer prueft nach '5.' auf e/E und
// nimmt das 'E' von 'Equals' als Exponenten - das Token heisst '5.E'
// (hier gepinnt, uLexer bleibt unveraendert). Es zaehlt trotzdem nicht:
// hinter dem Punkt keine Ziffer, ab dem Punkt ein Bezeichner.
var
  Lex : TLexer;
  Tok : TToken;
  Hit : TFloatLiteralHit;
begin
  Lex := TLexer.Create('5.Equals(5)');
  try
    Tok := Lex.Next;
    Assert.IsTrue(Tok.Kind = tkFloatLit, 'Lexer: tkFloatLit');
    Assert.AreEqual('5.E', Tok.Value, 'Lexer: Token-Text');
  finally
    Lex.Free;
  end;
  CheckHit(Src([
    'unit A;',                                  // 1
    'implementation',                           // 2
    'procedure P;',                             // 3
    'var B: Boolean; X: Double;',               // 4
    'begin',                                    // 5
    '  B := 5.Equals(5);',                      // 6
    '  X := 0.5;',                              // 7  Wache
    'end;',                                     // 8
    'end.']),                                   // 9
    7, 8, Msg('0.5'));
  Assert.IsFalse(TFloatLiteralIdeCrashDetector.FindFirstLiteral(
    'B := 5.Equals(5);', 'sample.pas', Hit), 'kein Treffer');
end;

procedure TTestFloatLiteralIdeCrash.R3_TrailingDotWithoutIdent_Reported;
// '1.' ohne Bezeichner dahinter ist an der IDE UNGEMESSEN und meldet
// deshalb weiter (Fakt DotWithoutDigits ja, IdentAfterDot nein).
var
  Hit : TFloatLiteralHit;
begin
  CheckHit(Src([
    'unit A;',                                  // 1
    'implementation',                           // 2
    'procedure P;',                             // 3
    'var X: Double;',                           // 4
    'begin',                                    // 5
    '  X := 1.;',                               // 6
    'end;',                                     // 7
    'end.']),                                   // 8
    6, 8, Msg('1.'));
  Assert.IsTrue(TFloatLiteralIdeCrashDetector.FindFirstLiteral(
    'X := 1.;', 'sample.pas', Hit), 'Treffer');
  Assert.IsTrue(Hit.Facts.DotWithoutDigits, 'Fakt DotWithoutDigits');
  Assert.IsFalse(Hit.Facts.IdentAfterDot, 'Fakt IdentAfterDot');
end;

procedure TTestFloatLiteralIdeCrash.LiteralCounts_FollowsMeasurement;
// Pinnt die Entscheidung je Fakt nach der IDE-Messung vom 2026-11-25.
// Aendert sich ein Befund, kippt genau hier die betreffende Zeile (und der
// passende R-Test oben).
var
  Facts : TFloatLiteralFacts;
begin
  Facts := Default(TFloatLiteralFacts);
  Assert.IsTrue(TFloatLiteralIdeCrashDetector.LiteralCounts('4.90', Facts),
    'ohne Fakt');
  Facts := Default(TFloatLiteralFacts);
  Facts.InInactiveBranch := True;
  Assert.IsTrue(TFloatLiteralIdeCrashDetector.LiteralCounts('4.90', Facts),
    'R1 abgeschalteter Zweig: zaehlt');
  Facts := Default(TFloatLiteralFacts);
  Facts.InIncludedFile := True;
  Assert.IsTrue(TFloatLiteralIdeCrashDetector.LiteralCounts('4.90', Facts),
    'R2 eingebunden: zaehlt');
  Facts := Default(TFloatLiteralFacts);
  Facts.ScannedFileIsInclude := True;
  Assert.IsFalse(TFloatLiteralIdeCrashDetector.LiteralCounts('4.90', Facts),
    'R2 .inc selbst gescannt: zaehlt nicht');
  Facts := Default(TFloatLiteralFacts);
  Facts.DotWithoutDigits := True;
  Facts.IdentAfterDot    := True;
  Assert.IsFalse(TFloatLiteralIdeCrashDetector.LiteralCounts('5.', Facts),
    'R3 Aufruf auf Ganzzahl: zaehlt nicht');
  Facts := Default(TFloatLiteralFacts);
  Facts.DotWithoutDigits := True;
  Assert.IsTrue(TFloatLiteralIdeCrashDetector.LiteralCounts('1.', Facts),
    '''1.'' ohne Bezeichner (ungemessen): zaehlt');
end;

{ ---- Pipeline, Katalog, Profile --------------------------------------------- }

procedure TTestFloatLiteralIdeCrash.Pipeline_VisibleAndSuppressible;
// Ueber die Produktions-Pipeline (Direkt-Modus = alle Detektoren, Konfidenz
// ab medium): sichtbar; ein '// noinspection' in der Zeile davor legt den
// Fund still und gilt als verbraucht.
var
  F : TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(Src([
    'unit A;', 'interface', 'const Price = 4.90;', 'implementation', 'end.']));
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFloatLiteralIdeCrash),
      'sichtbar');
  finally
    F.Free;
  end;
  F := TFindingHelper.FindingsViaPipeline(Src([
    'unit A;', 'interface',
    '// noinspection FloatLiteralIdeCrash - only built with Delphi 13',
    'const Price = 4.90;', 'implementation', 'end.']));
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFloatLiteralIdeCrash),
      'unterdrueckt');
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedSuppression),
      'Marker verbraucht');
  finally
    F.Free;
  end;
end;

procedure TTestFloatLiteralIdeCrash.CatalogExample_BadReported_GoodClean;
// Die Beispiele des Katalogs (rules/sca-rules.json) muessen stimmen: bad
// meldet das Literal, good nichts.
var
  Meta : TRuleMeta;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkFloatLiteralIdeCrash);
  Assert.AreEqual('SCA208', Meta.ID);
  CheckHit(Src(['unit A;', 'implementation', 'procedure P;',
    'var Price: Double;', 'begin', Meta.BadExample, 'end;', 'end.']),
    6, 10, Msg('4.90'));
  CheckNoHit(Src(['unit A;', 'implementation', 'procedure P;',
    'var Price: Double;', 'begin', Meta.GoodExample, 'end;', 'end.']));
end;

procedure TTestFloatLiteralIdeCrash.Profiles_NotDefault_StrictAndStyle;
// Standardmaessig aus: nicht im Profil default (das die Engine ohne Profil
// faehrt) und nicht in ide-fast (Vorgabe des IDE-Plugins); strict fuehrt
// alles, style die Regeln, die default auslaesst.
begin
  Assert.IsFalse(fkFloatLiteralIdeCrash in TRuleCatalog.GetProfile('default'),
    'default');
  Assert.IsFalse(fkFloatLiteralIdeCrash in TRuleCatalog.GetProfile('ide-fast'),
    'ide-fast');
  Assert.IsFalse(fkFloatLiteralIdeCrash in TRuleCatalog.GetProfile('bugs-only'),
    'bugs-only');
  Assert.IsTrue(fkFloatLiteralIdeCrash in TRuleCatalog.GetProfile('strict'),
    'strict');
  Assert.IsTrue(fkFloatLiteralIdeCrash in TRuleCatalog.GetProfile('style'),
    'style');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFloatLiteralIdeCrash);

end.
