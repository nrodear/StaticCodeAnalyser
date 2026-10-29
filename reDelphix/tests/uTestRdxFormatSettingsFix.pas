unit uTestRdxFormatSettingsFix;

// Editorhilfe SCA128 DateFormatSettings (uRdxFormatSettingsFix): an jeden
// Aufruf der Detektor-Liste auf der Fundzeile ', FormatSettings' (Hauptweg)
// bzw. ', TFormatSettings.Invariant' (Alt-Weg) anhaengen. Die Faelle auf Text
// rufen die Planer direkt auf einer TRdxCodeMap; die Rundlaeufe mit dem
// ECHTEN Detektor (TDateFormatSettingsDetector) laufen ueber den Einstieg
// der Tabelle (TRdxFixTable.FixFor bzw. AlternativeFixFor, Adapter
// PlanDateFormatSettings/PlanDateFormatSettingsAlt) und stehen in einer
// eigenen Fixture hinter {$IFNDEF FPC} - die Text-Fixture bleibt
// FPC-tauglich und laeuft seit HilfeFix K (rwE31 Stufe 3) im FPC-
// Pruefstand (uRdxFormatSettingsFix steht in der Unit-Liste von build.sh).
// Prueft: Hilfe fuer ein und zwei Argumente, Schreibweise und Leerraum,
// alle Aufrufe der Zeile in einer Ersetzung, verschachtelt, RTL-qualifiziert,
// der Bereich, der Alt-Weg; die Sperren - verschoben, Folgezeile, Anweisung
// geht weiter, qualifiziert, kein Aufruf, Argumentzahl, offene Klammer,
// Direktive, kein SysUtils, eigene Routine, FormatSettings deklariert bzw.
// als Member, with, alte Compiler, FPC, eigenes TFormatSettings, Meldung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxFormatSettingsFix = class
  public
    // ---- Hilfe ----
    [Test] procedure Sca128_OneArgument_AppendsFormatSettings;
    [Test] procedure Sca128_TwoArguments_AppendsThird;
    [Test] procedure Sca128_CaseAndBlanks_Kept;
    [Test] procedure Sca128_AllCallsOfLine_OneEdit;
    [Test] procedure Sca128_RtlQualified_Helps;
    [Test] procedure Sca128_Edit_StartsBehindLastArgument;
    [Test] procedure Sca128_Alt_AppendsInvariant;
    [Test] procedure Sca128_MessageName_Read;
    // ---- keine Hilfe ----
    [Test] procedure Sca128_Moved_NoHelp;
    [Test] procedure Sca128_CallOnFollowingLine_Helps;
    [Test] procedure Sca128_StatementContinues_EditsAll;
    [Test] procedure Sca128_QualifiedOrNoCall_NoHelp;
    [Test] procedure Sca128_OtherArity_NoHelp;
    [Test] procedure Sca128_Directive_NoHelp;
    [Test] procedure Sca128_NoSysUtilsOrOwnRoutine_NoHelp;
    [Test] procedure Sca128_FormatSettingsDeclared_Qualified;
    [Test] procedure Sca128_With_MainQualified_AltNoHelp;
    [Test] procedure Sca128_OldCompiler_Blocks;
    [Test] procedure Sca128_Alt_FpcOrOwnType_NoHelp;
    // ---- Realworld-Test rwE29: Literal gegen Invariant ----
    [Test] procedure Sca128_Alt_LiteralNotInvariant_NoHelp;
    [Test] procedure Sca128_Alt_LiteralInvariant_Helps;
    // ---- Realworld-Test rwE29: Paar-Bruch ----
    [Test] procedure Sca128_Alt_PairInFile_HintNamesLine;
    [Test] procedure Sca128_Alt_NoPairInFile_PlainHint;
    // ---- Realworld-Test rwE30 Stufe 2 ----
    [Test] procedure Sca128_MultiLineCall_ClosesLower;
    [Test] procedure Sca128_MultiLineCall_Break_NoHelp;
    [Test] procedure Sca128_FollowLines_AllCalls;
    [Test] procedure Sca128_FollowLines_Directive_NoHelp;
    [Test] procedure Sca128_WithEnded_Helps;
    [Test] procedure Sca128_WithEncloses_NoHelp;
    [Test] procedure Sca128_OldMormotSymbols_Block;
    [Test] procedure Sca128_ModernProof_RefutesTraces;
    [Test] procedure Sca128_Alt_InlineVarRefutesFpc;
    [Test] procedure Sca128_Alt_InvariantInFileRefutesTrace;
    [Test] procedure Sca128_Alt_FpcExcludedBranch_Helps;
    [Test] procedure Sca128_Alt_GlobalSettingsSet_NoHelp;
    [Test] procedure Sca128_Alt_CompareLiteral_NoHelp;
    [Test] procedure Sca128_Alt_PairInSameRoutineFirst;
    // ---- Realworld-Test rwE31 Stufe 3: gekoppelte Auswertung ----
    [Test] procedure Sca128_Alt_CoupledCompare_NoHelp;
    [Test] procedure Sca128_Alt_CoupledSettings_NoHelp;
    [Test] procedure Sca128_Alt_NotCoupled_Helps;
    [Test] procedure Sca128_Alt_PairHint_NearestWithoutOwnSettings;
    [Test] procedure Sca128_FollowLines_AnonymousMethod;
  end;

{$IFNDEF FPC}
  // Rundlaeufe mit dem ECHTEN Detektor (nur Delphi).
  [TestFixture]
  TTestRdxFormatSettingsFixDetector = class
  public
    [Test] procedure Sca128_Detector_CatalogExample;
    [Test] procedure Sca128_Detector_RoundTrip;
    [Test] procedure Sca128_Detector_RoundTripAlt;
    [Test] procedure Sca128_Detector_ContinuedStatement_EditsAll;
    // ---- Realworld-Test rwE29: was nur die Platte weiss ----
    [Test] procedure Sca128_Detector_OldDelphiProject_NoHelp;
    [Test] procedure Sca128_Detector_LazarusProject_OnlyMainWay;
    [Test] procedure Sca128_Detector_OldTraceOnlyInInclude_MainWayStays;
    [Test] procedure Sca128_Detector_PairInFile_HintNamesLine;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uDateFormatSettings,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uRdxMagicFixes,        // FileReason, lfFormatSettingsVar/lfFormatInvariant
  uTestRdxDetectorKit,   // TSeen, DetectSource, CatalogText, PlanFixIn,
                         // PlanAltFixIn, FixAllWith
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxFormatSettingsFix,
  uRdxText,              // _() und die gemeinsamen Gruende (E29)
  uTestRdxTextKit;       // Apply, NewMap

const
  CRLF = #13#10;
  // Die erste Zeile des Rumpfs von P (UnitText ohne Kopfzeilen).
  BODY_LINE = 10;
  RTL_USES = 'System.SysUtils';

// ---- Helfer ----

// Eine Unit: uses-Eintrag AUses ('' = keine uses-Klausel, die Zeilen bleiben
// gleich gezaehlt), AHead hinter den uses, dann Routine P mit Rumpf ABody
// (erste Zeile = BODY_LINE + Length(AHead)).
function UnitText(const AUses: string; const AHead,
  ABody: array of string): string;
var
  S : string;
begin
  Result := 'unit t;' + CRLF + 'interface' + CRLF + 'implementation' + CRLF;
  if AUses = '' then
    Result := Result + '// ohne' + CRLF + '// uses' + CRLF
  else
    Result := Result + 'uses' + CRLF + '  ' + AUses + ';' + CRLF;
  for S in AHead do
    Result := Result + S + CRLF;
  Result := Result + 'procedure P(d: TDateTime; const s: string; x: Double);'
    + CRLF + 'var' + CRLF + '  r: string;' + CRLF + 'begin' + CRLF;
  for S in ABody do
    Result := Result + S + CRLF;
  Result := Result + 'end;' + CRLF + 'end.';
end;

function InUnit(const ABody: array of string): string;
begin
  Result := UnitText(RTL_USES, [], ABody);
end;

// Die Meldung des Detektors zum Namen ALow (klein).
function Msg(const ALow: string): string;
begin
  Result := ALow + ' called without explicit TFormatSettings - depends on '
    + 'system locale';
end;

// Der Planer auf ASource; True mit der Ersetzung oder False mit dem Grund.
function PlanOn(const ASource: string; ALine: Integer; const AMessage: string;
  AAlt: Boolean; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Map : TRdxCodeMap;
begin
  Map := NewMap(ASource);
  try
    if AAlt then
      Result := TRdxFormatSettingsFix.DateFormatInvariant(Map, ALine, AMessage,
        AEdit, AReason)
    else
      Result := TRdxFormatSettingsFix.DateFormatSettings(Map, ALine, AMessage,
        AEdit, AReason);
  finally
    Map.Free;
  end;
end;

// Der Text nach der Hilfe; '' bei Ablehnung (Grund in AReason).
function Fix(const ASource: string; ALine: Integer; const AMessage: string;
  AAlt: Boolean; out AReason: string): string;
var
  E : TRdxEdit;
begin
  Result := '';
  if PlanOn(ASource, ALine, AMessage, AAlt, E, AReason) then
    Result := Apply(ASource, E);
end;

procedure AssertFixed(const AExpected, ASource: string; ALine: Integer;
  const AMessage: string; AAlt: Boolean = False);
var
  Reason : string;
begin
  Assert.AreEqual(AExpected, Fix(ASource, ALine, AMessage, AAlt, Reason),
    Reason);
end;

procedure AssertRefused(const ASource: string; ALine: Integer;
  const AMessage, AReason: string; AAlt: Boolean = False);
var
  Got : string;
begin
  Assert.AreEqual('', Fix(ASource, ALine, AMessage, AAlt, Got), 'keine Hilfe');
  Assert.AreEqual(AReason, Got);
end;

function Moved(const ALow: string): string;
begin
  Result := MsgMovedSuffix(_(R_FS_MOVED, [ALow]));
end;

// ---- Hilfe ----

procedure TTestRdxFormatSettingsFix.Sca128_OneArgument_AppendsFormatSettings;
begin
  AssertFixed(InUnit(['  r := DateToStr(d, FormatSettings);']),
    InUnit(['  r := DateToStr(d);']), BODY_LINE, Msg('datetostr'));
  AssertFixed(InUnit(['  x := StrToFloat(s, FormatSettings);']),
    InUnit(['  x := StrToFloat(s);']), BODY_LINE, Msg('strtofloat'));
  // Als Argument eines anderen Aufrufs, mit Kommentar dahinter.
  AssertFixed(InUnit(['  LogIt(FloatToStr(x, FormatSettings)); // Wert']),
    InUnit(['  LogIt(FloatToStr(x)); // Wert']), BODY_LINE, Msg('floattostr'));
end;

procedure TTestRdxFormatSettingsFix.Sca128_TwoArguments_AppendsThird;
begin
  AssertFixed(
    InUnit(['  r := FormatDateTime(''yyyy-mm-dd, hh:nn'', d, FormatSettings);']),
    InUnit(['  r := FormatDateTime(''yyyy-mm-dd, hh:nn'', d);']), BODY_LINE,
    Msg('formatdatetime'));
  AssertFixed(InUnit(['  r := FormatFloat(''0.00'', Max(x, 1), FormatSettings);']),
    InUnit(['  r := FormatFloat(''0.00'', Max(x, 1));']), BODY_LINE,
    Msg('formatfloat'));
end;

procedure TTestRdxFormatSettingsFix.Sca128_CaseAndBlanks_Kept;
begin
  // Der Leerraum vor der Klammer bleibt hinter dem neuen Argument.
  AssertFixed(InUnit(['  r := DATETOSTR( d, FormatSettings );']),
    InUnit(['  r := DATETOSTR( d );']), BODY_LINE, Msg('datetostr'));
  AssertFixed(InUnit(['  r := CurrToStr (x, FormatSettings);']),
    InUnit(['  r := CurrToStr (x);']), BODY_LINE, Msg('currtostr'));
end;

procedure TTestRdxFormatSettingsFix.Sca128_AllCallsOfLine_OneEdit;
begin
  // Der Detektor nennt einen Namen je Anweisung (Listen-Reihenfolge) und
  // schweigt nach dem ersten Settings-Argument ganz - darum alle Aufrufe.
  AssertFixed(
    InUnit(['  r := DateToStr(d, FormatSettings) + '' '' + TimeToStr(d, FormatSettings);']),
    InUnit(['  r := DateToStr(d) + '' '' + TimeToStr(d);']), BODY_LINE,
    Msg('datetostr'));
  // Verschachtelt.
  AssertFixed(
    InUnit(['  r := FloatToStr(StrToFloat(s, FormatSettings), FormatSettings);']),
    InUnit(['  r := FloatToStr(StrToFloat(s));']), BODY_LINE, Msg('strtofloat'));
end;

procedure TTestRdxFormatSettingsFix.Sca128_RtlQualified_Helps;
begin
  AssertFixed(InUnit(['  r := SysUtils.DateToStr(d, FormatSettings);']),
    InUnit(['  r := SysUtils.DateToStr(d);']), BODY_LINE, Msg('datetostr'));
  AssertFixed(InUnit(['  r := System.SysUtils.DateToStr(d, FormatSettings);']),
    InUnit(['  r := System.SysUtils.DateToStr(d);']), BODY_LINE,
    Msg('datetostr'));
end;

procedure TTestRdxFormatSettingsFix.Sca128_Edit_StartsBehindLastArgument;
var
  E : TRdxEdit;
  R : string;
begin
  // '  r := DateToStr(d);' - 'd' in Spalte 18, ')' in 19.
  Assert.IsTrue(PlanOn(InUnit(['  r := DateToStr(d);']), BODY_LINE,
    Msg('datetostr'), False, E, R), R);
  Assert.AreEqual<Integer>(BODY_LINE, E.Span.StartLine);
  Assert.AreEqual<Integer>(19, E.Span.StartCol);
  Assert.AreEqual<Integer>(BODY_LINE, E.Span.EndLine);
  Assert.AreEqual<Integer>(20, E.Span.EndCol);
  Assert.AreEqual(')', E.Expected);
  Assert.AreEqual(', FormatSettings)', E.NewText);
  // Zwei Aufrufe: vom ersten Einfuegepunkt bis hinter die letzte Klammer.
  Assert.IsTrue(PlanOn(InUnit(['  r := DateToStr(d) + TimeToStr(d);']),
    BODY_LINE, Msg('datetostr'), False, E, R), R);
  Assert.AreEqual(') + TimeToStr(d)', E.Expected);
  Assert.AreEqual(', FormatSettings) + TimeToStr(d, FormatSettings)',
    E.NewText);
end;

procedure TTestRdxFormatSettingsFix.Sca128_Alt_AppendsInvariant;
begin
  AssertFixed(InUnit(['  r := DateToStr(d, TFormatSettings.Invariant);']),
    InUnit(['  r := DateToStr(d);']), BODY_LINE, Msg('datetostr'), True);
  AssertFixed(
    InUnit(['  r := FormatFloat(''0.00'', x, TFormatSettings.Invariant) + '
      + 'FloatToStr(x, TFormatSettings.Invariant);']),
    InUnit(['  r := FormatFloat(''0.00'', x) + FloatToStr(x);']), BODY_LINE,
    Msg('floattostr'), True);
end;

procedure TTestRdxFormatSettingsFix.Sca128_MessageName_Read;
var
  Src : string;
begin
  Assert.AreEqual('datetostr', TRdxFormatSettingsFix.CalledNameOf(
    Msg('datetostr')));
  Assert.AreEqual('formatcurr', TRdxFormatSettingsFix.CalledNameOf(
    Msg('formatcurr')));
  // Kein Name der Liste bzw. eine fremde Meldung.
  Assert.AreEqual('', TRdxFormatSettingsFix.CalledNameOf(Msg('strtoint')));
  Assert.AreEqual('', TRdxFormatSettingsFix.CalledNameOf('etwas anderes'));
  Src := InUnit(['  r := DateToStr(d);']);
  AssertRefused(Src, BODY_LINE, 'etwas anderes', _(R_FS_NO_NAME));
  AssertRefused(Src, BODY_LINE, Msg('strtoint'), _(R_FS_NO_NAME), True);
end;

// ---- keine Hilfe ----

procedure TTestRdxFormatSettingsFix.Sca128_Moved_NoHelp;
begin
  // Die Zeile davor (begin), auskommentiert, im String.
  AssertRefused(InUnit(['  r := DateToStr(d);']), BODY_LINE - 1,
    Msg('datetostr'), Moved('datetostr'));
  AssertRefused(InUnit(['  // r := DateToStr(d);']), BODY_LINE,
    Msg('datetostr'), Moved('datetostr'));
  AssertRefused(InUnit(['  r := ''DateToStr(d)'';']), BODY_LINE,
    Msg('datetostr'), Moved('datetostr'), True);
  // Ein anderer Aufruf der Liste als der gemeldete; ein Funktionszeiger.
  AssertRefused(InUnit(['  r := FloatToStr(x);']), BODY_LINE,
    Msg('datetostr'), Moved('datetostr'));
  AssertRefused(InUnit(['  Register(@DateToStr);']), BODY_LINE,
    Msg('datetostr'), Moved('datetostr'));
  // Ausserhalb der Datei.
  AssertRefused(InUnit(['  r := DateToStr(d);']), 999, Msg('datetostr'),
    Moved('datetostr'));
end;

procedure TTestRdxFormatSettingsFix.Sca128_CallOnFollowingLine_Helps;
begin
  // rwE30 Stufe 2: der Planer kennt die Aufrufzeile - bis dahin sperrte er
  // mit 'der Aufruf steht in Zeile 11, einer Folgezeile der Anweisung'.
  AssertFixed(InUnit(['  r :=', '    DateToStr(d, FormatSettings);']),
    InUnit(['  r :=', '    DateToStr(d);']), BODY_LINE, Msg('datetostr'));
end;

procedure TTestRdxFormatSettingsFix.Sca128_StatementContinues_EditsAll;
begin
  // Der Detektor schweigt nach dem ersten Settings-Argument der Anweisung -
  // seit rwE30 Stufe 2 bekommt der Aufruf der Folgezeile es mit (bis dahin
  // R_FS_CONTINUES).
  AssertFixed(InUnit(['  r := DateToStr(d, FormatSettings) + '' '' +',
    '    TimeToStr(d, FormatSettings);']),
    InUnit(['  r := DateToStr(d) + '' '' +', '    TimeToStr(d);']), BODY_LINE,
    Msg('datetostr'));
  // Endet die Anweisung auf der Zeile, stoert die naechste nicht.
  AssertFixed(InUnit(['  r := DateToStr(d, FormatSettings);',
    '  r := TimeToStr(d);']),
    InUnit(['  r := DateToStr(d);', '  r := TimeToStr(d);']), BODY_LINE,
    Msg('datetostr'));
end;

procedure TTestRdxFormatSettingsFix.Sca128_QualifiedOrNoCall_NoHelp;
begin
  AssertRefused(InUnit(['  r := Conv.DateToStr(d);']), BODY_LINE,
    Msg('datetostr'), _(R_FS_QUALIFIED, ['DateToStr', 'Conv.DateToStr']));
  AssertRefused(InUnit(['  r := My.SysUtils.DateToStr(d);']), BODY_LINE,
    Msg('datetostr'), _(R_FS_QUALIFIED, ['DateToStr', 'SysUtils.DateToStr']));
  AssertRefused(InUnit(['  F := DateToStr;']), BODY_LINE, Msg('datetostr'),
    _(R_FS_NOT_CALL, ['DateToStr']));
end;

procedure TTestRdxFormatSettingsFix.Sca128_OtherArity_NoHelp;
begin
  // Schon ein zweites Argument (andere Ueberladung oder schon Settings).
  AssertRefused(InUnit(['  r := DateToStr(d, FS);']), BODY_LINE,
    Msg('datetostr'), _(R_FS_ARITY, ['DateToStr', 2, 1]));
  AssertRefused(InUnit(['  r := DateTimeToStr(d, True);']), BODY_LINE,
    Msg('datetimetostr'), _(R_FS_ARITY, ['DateTimeToStr', 2, 1]), True);
  AssertRefused(InUnit(['  r := FormatDateTime(''yyyy'');']), BODY_LINE,
    Msg('formatdatetime'), _(R_FS_ARITY, ['FormatDateTime', 1, 2]));
  AssertRefused(InUnit(['  r := DateToStr();']), BODY_LINE,
    Msg('datetostr'), _(R_FS_ARITY, ['DateToStr', 0, 1]));
  // Ein weiterer Aufruf der Zeile mit fremder Form sperrt die ganze Zeile.
  AssertRefused(InUnit(['  r := DateToStr(d) + StrToDate(s, ''/'');']),
    BODY_LINE, Msg('strtodate'), _(R_FS_ARITY, ['StrToDate', 2, 1]));
  // Auch ueber Zeilen (rwE30 Stufe 2: die Klammer darf tiefer schliessen).
  AssertRefused(InUnit(['  r := DateToStr(d,', '    True);']), BODY_LINE,
    Msg('datetostr'), _(R_FS_ARITY, ['DateToStr', 2, 1]));
end;

procedure TTestRdxFormatSettingsFix.Sca128_Directive_NoHelp;
begin
  AssertRefused(InUnit(['  r := DateToStr(d) {$IFDEF X} + ''x'' {$ENDIF};']),
    BODY_LINE, Msg('datetostr'), _(R_FS_DIRECTIVE));
end;

procedure TTestRdxFormatSettingsFix.Sca128_NoSysUtilsOrOwnRoutine_NoHelp;
begin
  AssertRefused(UnitText('', [], ['  r := DateToStr(d);']), BODY_LINE,
    Msg('datetostr'), _(R_FS_NO_SYSUTILS));
  AssertRefused(UnitText('Classes, MySysUtils', [], ['  r := DateToStr(d);']),
    BODY_LINE, Msg('datetostr'), _(R_FS_NO_SYSUTILS), True);
  // Der Kurzname reicht.
  AssertFixed(UnitText('Classes, SysUtils', [],
    ['  r := DateToStr(d, FormatSettings);']),
    UnitText('Classes, SysUtils', [], ['  r := DateToStr(d);']), BODY_LINE,
    Msg('datetostr'));
  // Eine eigene Routine des Namens - auch als Methode.
  AssertRefused(UnitText(RTL_USES,
    ['function DateToStr(const D: TDateTime): string; forward;'],
    ['  r := DateToStr(d);']), BODY_LINE + 1, Msg('datetostr'),
    _(R_FS_OWN_ROUTINE, ['DateToStr']));
  AssertRefused(UnitText(RTL_USES,
    ['function TConv.FloatToStr(V: Double): string; begin end;'],
    ['  r := FloatToStr(x);']), BODY_LINE + 1, Msg('floattostr'),
    _(R_FS_OWN_ROUTINE, ['FloatToStr']), True);
end;

procedure TTestRdxFormatSettingsFix.Sca128_FormatSettingsDeclared_Qualified;
var
  Src : string;
begin
  // Ein Parameter FormatSettings irgendwo in der Datei: der blosse Name
  // bande dort. Bis rwE30 Stufe 2 sperrte der Hauptweg (TemplatePro.pas:
  // 3170, R_FS_SHADOW); jetzt nennt er die globale Variable qualifiziert -
  // in der Schreibweise der uses-Klausel. Der Alt-Weg nennt den Namen nicht.
  Src := UnitText(RTL_USES,
    ['procedure Q(const FormatSettings: TFormatSettings); begin end;'],
    ['  r := DateToStr(d);']);
  AssertFixed(UnitText(RTL_USES,
    ['procedure Q(const FormatSettings: TFormatSettings); begin end;'],
    ['  r := DateToStr(d, System.SysUtils.FormatSettings);']), Src,
    BODY_LINE + 1, Msg('datetostr'));
  AssertFixed(UnitText(RTL_USES,
    ['procedure Q(const FormatSettings: TFormatSettings); begin end;'],
    ['  r := DateToStr(d, TFormatSettings.Invariant);']), Src, BODY_LINE + 1,
    Msg('datetostr'), True);
  // In einer Liste und als Feld bzw. Property einer Klasse - 'SysUtils' wie
  // geschrieben.
  AssertFixed(UnitText('Classes, SysUtils',
    ['type TFoo = class A, FormatSettings: TFormatSettings; end;'],
    ['  r := DateToStr(d, SysUtils.FormatSettings);']),
    UnitText('Classes, SysUtils',
    ['type TFoo = class A, FormatSettings: TFormatSettings; end;'],
    ['  r := DateToStr(d);']), BODY_LINE + 1, Msg('datetostr'));
  AssertFixed(UnitText(RTL_USES,
    ['type TFoo = class property FormatSettings: TFormatSettings read F; end;'],
    ['  r := FormatFloat(''0.00'', x, System.SysUtils.FormatSettings);']),
    UnitText(RTL_USES,
    ['type TFoo = class property FormatSettings: TFormatSettings read F; end;'],
    ['  r := FormatFloat(''0.00'', x);']), BODY_LINE + 1, Msg('formatfloat'));
  // Als Member (eines fremden Typs).
  AssertFixed(InUnit(['  Writer.FormatSettings.DecimalSeparator := ''.'';',
    '  r := DateToStr(d, System.SysUtils.FormatSettings);']),
    InUnit(['  Writer.FormatSettings.DecimalSeparator := ''.'';',
    '  r := DateToStr(d);']), BODY_LINE + 1, Msg('datetostr'));
  // SysUtils.FormatSettings ist die RTL - kein Member.
  AssertFixed(InUnit(['  SysUtils.FormatSettings.DecimalSeparator := ''.'';',
    '  r := DateToStr(d, FormatSettings);']),
    InUnit(['  SysUtils.FormatSettings.DecimalSeparator := ''.'';',
    '  r := DateToStr(d);']), BODY_LINE + 1, Msg('datetostr'));
end;

procedure TTestRdxFormatSettingsFix.Sca128_With_MainQualified_AltNoHelp;
var
  Src : string;
begin
  // Seit rwE31 Stufe 3 sperrt ein with nur den Alt-Weg; der Hauptweg nimmt
  // die globale Variable qualifiziert (bis dahin R_FS_WITH auch hier).
  Src := InUnit(['  with Obj do', '    r := DateToStr(d);']);
  AssertFixed(InUnit(['  with Obj do',
    '    r := DateToStr(d, System.SysUtils.FormatSettings);']), Src,
    BODY_LINE + 1, Msg('datetostr'));
  AssertRefused(Src, BODY_LINE + 1, Msg('datetostr'), _(R_FS_WITH, [BODY_LINE]),
    True);
  // HeidiSQL SynEditPrintMarginsDialog.pas:174 (ebenso pyscripter
  // dlgSynPageSetup.pas:458): 'with SynEditMargins do begin' um die
  // FloatToStr, uses mit 'SysUtils' - die Schreibweise der uses-Klausel.
  Src := UnitText('SysUtils', [], ['  with SynEditMargins do begin',
    '    CBUnits.ItemIndex := Ord(UnitSystem);',
    '    EditLeft.Text := FloatToStr(Left);', '  end;']);
  AssertFixed(UnitText('SysUtils', [], ['  with SynEditMargins do begin',
    '    CBUnits.ItemIndex := Ord(UnitSystem);',
    '    EditLeft.Text := FloatToStr(Left, SysUtils.FormatSettings);',
    '  end;']), Src, BODY_LINE + 2, Msg('floattostr'));
  // issrc ISPP.Funcs.pas:1599: with auf eine Interface-Typumwandlung, die
  // Aufrufe im try des with-Blocks.
  Src := InUnit(['  with IInternalFuncParams(Params) do', '  begin',
    '    try', '      MakeStr(ResPtr^, FormatDateTime(Get(1).AsStr, Age));',
    '    finally', '      Foo;', '    end;', '  end;']);
  AssertFixed(InUnit(['  with IInternalFuncParams(Params) do', '  begin',
    '    try', '      MakeStr(ResPtr^, FormatDateTime(Get(1).AsStr, Age, '
    + 'System.SysUtils.FormatSettings));',
    '    finally', '      Foo;', '    end;', '  end;']), Src, BODY_LINE + 3,
    Msg('formatdatetime'));
  AssertRefused(Src, BODY_LINE + 3, Msg('formatdatetime'),
    _(R_FS_WITH, [BODY_LINE]), True);
  // Ein with in einer ANDEREN Routine davor stoert nicht.
  AssertFixed(UnitText(RTL_USES,
    ['procedure Q; begin with Obj do Foo; end;'],
    ['  r := DateToStr(d, FormatSettings);']),
    UnitText(RTL_USES, ['procedure Q; begin with Obj do Foo; end;'],
    ['  r := DateToStr(d);']), BODY_LINE + 1, Msg('datetostr'));
end;

// Eine Unit wie InUnit mit 'SysUtils' im uses - ohne den Namensraum, der
// seit rwE30 Stufe 2 Delphi XE2 beweist (ModernProof).
function InOldUnit(const ABody: array of string): string;
begin
  Result := UnitText('SysUtils', [], ABody);
end;

procedure TTestRdxFormatSettingsFix.Sca128_OldCompiler_Blocks;
var
  Src : string;
begin
  // Delphi 2010 kennt die globale FormatSettings nicht: beide Wege sperren.
  Src := InOldUnit(['  r := DateToStr(d);', '  {$IFDEF VER210} Foo; {$ENDIF}']);
  AssertRefused(Src, BODY_LINE, Msg('datetostr'),
    _(R_FS_OLD_VAR, ['VER210', BODY_LINE + 1]));
  AssertRefused(Src, BODY_LINE, Msg('datetostr'),
    _(R_FS_OLD_INVARIANT, ['VER210', BODY_LINE + 1]), True);
  // Delphi XE: der Hauptweg geht, Invariant erst ab 10.3 geprueft.
  Src := InOldUnit(['  r := DateToStr(d);', '  {$IFDEF VER220} Foo; {$ENDIF}']);
  AssertFixed(InOldUnit(['  r := DateToStr(d, FormatSettings);',
    '  {$IFDEF VER220} Foo; {$ENDIF}']), Src, BODY_LINE, Msg('datetostr'));
  AssertRefused(Src, BODY_LINE, Msg('datetostr'),
    _(R_FS_OLD_INVARIANT, ['VER220', BODY_LINE + 1]), True);
end;

procedure TTestRdxFormatSettingsFix.Sca128_Alt_FpcOrOwnType_NoHelp;
var
  Src : string;
begin
  // FPC kennt FormatSettings (absolute DefaultFormatSettings), aber kein
  // TFormatSettings.Invariant.
  Src := InUnit(['  r := DateToStr(d);', '  {$IFDEF FPC} Foo; {$ENDIF}']);
  AssertFixed(InUnit(['  r := DateToStr(d, FormatSettings);',
    '  {$IFDEF FPC} Foo; {$ENDIF}']), Src, BODY_LINE, Msg('datetostr'));
  AssertRefused(Src, BODY_LINE, Msg('datetostr'),
    _(R_FS_FPC, [BODY_LINE + 1]), True);
  AssertRefused(UnitText(RTL_USES, ['{$mode delphi}'], ['  r := DateToStr(d);']),
    BODY_LINE + 1, Msg('datetostr'), _(R_FS_FPC, [6]), True);
  // Ein eigenes TFormatSettings: Invariant hiesse etwas anderes.
  Src := UnitText(RTL_USES, ['type TFormatSettings = record end;'],
    ['  r := DateToStr(d);']);
  AssertRefused(Src, BODY_LINE + 1, Msg('datetostr'), _(R_FS_OWN_TYPE, [6]),
    True);
end;

procedure TTestRdxFormatSettingsFix.Sca128_Alt_LiteralNotInvariant_NoHelp;
var
  Src : string;
begin
  // rwE29, delphimvcframework ...\Serializers.JsonDataObjectsTestU.pas:1221:
  // StrToDateTime('17/02/2017 16:37:50') mit TFormatSettings.Invariant
  // (MM/dd/yyyy) wirft sicher EConvertError (Monat 17). Ohne die Sperre
  // boete der Alt-Weg es an (nichts sonst in der Datei sperrt) - der
  // Hauptweg bleibt (gleiche Bedeutung).
  Src := InUnit(['  d := StrToDateTime(''17/02/2017 16:37:50'');']);
  AssertRefused(Src, BODY_LINE, Msg('strtodatetime'),
    _(R_FS_LIT_DATE, ['''17/02/2017 16:37:50''', 'StrToDateTime']), True);
  AssertFixed(InUnit(['  d := StrToDateTime(''17/02/2017 16:37:50'', '
    + 'FormatSettings);']), Src, BODY_LINE, Msg('strtodatetime'));
  // Dieselbe Datei, Zeile davor: StrToDate('15/10/1987').
  AssertRefused(InUnit(['  d := StrToDate(''15/10/1987'');']), BODY_LINE,
    Msg('strtodate'), _(R_FS_LIT_DATE, ['''15/10/1987''', 'StrToDate']),
    True);
  // Zahl mit Komma bzw. Tausendertrenner.
  AssertRefused(InUnit(['  x := StrToFloat(''1,5'');']), BODY_LINE,
    Msg('strtofloat'), _(R_FS_LIT_NUMBER, ['''1,5''', 'StrToFloat']), True);
  AssertRefused(InUnit(['  x := StrToCurr(''1.234,50'');']), BODY_LINE,
    Msg('strtocurr'), _(R_FS_LIT_NUMBER, ['''1.234,50''', 'StrToCurr']),
    True);
  // Review e/HilfeFixG: das Literal auf der Folgezeile (die Klammer darf
  // seit rwE30 Stufe 2 tiefer schliessen) - bis dahin las die Probe nur die
  // Zeile des Namens und bot Invariant an (sicherer EConvertError).
  Src := InUnit(['  d := StrToDateTime(', '    ''17/02/2017 16:37:50'');']);
  AssertRefused(Src, BODY_LINE, Msg('strtodatetime'),
    _(R_FS_LIT_DATE, ['''17/02/2017 16:37:50''', 'StrToDateTime']), True);
  AssertFixed(InUnit(['  d := StrToDateTime(',
    '    ''17/02/2017 16:37:50'', FormatSettings);']), Src, BODY_LINE,
    Msg('strtodatetime'));
  // Gegenprobe: ein passendes Literal auf der Folgezeile bekommt Invariant.
  AssertFixed(InUnit(['  d := StrToDateTime(',
    '    ''02/17/2017 16:37:50'', TFormatSettings.Invariant);']),
    InUnit(['  d := StrToDateTime(', '    ''02/17/2017 16:37:50'');']),
    BODY_LINE, Msg('strtodatetime'), True);
end;

procedure TTestRdxFormatSettingsFix.Sca128_Alt_LiteralInvariant_Helps;
begin
  // Gegenprobe: Literale im Invariant-Format (und Aufrufe ohne Literal)
  // bekommen den Alt-Weg.
  AssertFixed(InUnit(['  d := StrToDateTime(''02/17/2017 16:37:50'', '
    + 'TFormatSettings.Invariant);']),
    InUnit(['  d := StrToDateTime(''02/17/2017 16:37:50'');']), BODY_LINE,
    Msg('strtodatetime'), True);
  AssertFixed(InUnit(['  d := StrToTime(''16:40:50'', TFormatSettings.Invariant);']),
    InUnit(['  d := StrToTime(''16:40:50'');']), BODY_LINE, Msg('strtotime'),
    True);
  // Ein reines Zeit-Literal sperrt nie (Review e/HilfeFixC): dass es mit
  // Invariant sicher scheitert, liesse sich nicht behaupten.
  AssertFixed(InUnit(['  d := StrToTime(''16 Uhr'', TFormatSettings.Invariant);']),
    InUnit(['  d := StrToTime(''16 Uhr'');']), BODY_LINE, Msg('strtotime'),
    True);
  AssertFixed(InUnit(['  d := StrToDate(''12/31/1999'', TFormatSettings.Invariant);']),
    InUnit(['  d := StrToDate(''12/31/1999'');']), BODY_LINE, Msg('strtodate'),
    True);
  AssertFixed(InUnit(['  x := StrToFloat(''-1.5e3'', TFormatSettings.Invariant);']),
    InUnit(['  x := StrToFloat(''-1.5e3'');']), BODY_LINE, Msg('strtofloat'),
    True);
  // Ein Literal in einem Schreib-Aufruf liest niemand (Formatmuster).
  AssertFixed(InUnit(['  r := FormatDateTime(''dd/mm/yyyy'', d, '
    + 'TFormatSettings.Invariant);']),
    InUnit(['  r := FormatDateTime(''dd/mm/yyyy'', d);']), BODY_LINE,
    Msg('formatdatetime'), True);
end;

// Der Hinweis zum Alt-Weg auf ALine mit dem Grundhinweis 'B' (PairHint).
function PairHintOf(const ASource: string; ALine: Integer): string;
var
  Map : TRdxCodeMap;
begin
  Map := NewMap(ASource);
  try
    Result := TRdxFormatSettingsFix.PairHint(Map, ALine, 'B');
  finally
    Map.Free;
  end;
end;

procedure TTestRdxFormatSettingsFix.Sca128_Alt_PairInFile_HintNamesLine;
var
  Src : string;
begin
  // rwE29, HeidiSQL main.pas:14718: 'QueryDay := DateToStr(..)' wird mit
  // Eintraegen verglichen, die eine andere Zeile mit DateToStr (Locale)
  // schreibt - nur diese Seite auf Invariant, und der Vergleich ist ausser
  // in en-US immer ungleich. Entscheid M2 (Review e/HilfeFixC): der
  // Alt-Weg bleibt angeboten (aendert Verhalten, nie per Taste), der
  // Hinweis nennt das Gegenstueck. Ohne PairHint bliebe er 'B'.
  // Seit rwE31 Stufe 3 (Nico-Ergaenzung zu M2) sperrt der DIREKTE
  // Vergleich in derselben Routine ('if r <> DateToStr(..)', CoupledReason,
  // Sca128_Alt_CoupledCompare_NoHelp); das Gegenstueck ohne Kopplung bleibt
  // ein Hinweisfall.
  Src := InUnit(['  r := DateToStr(d);', '  Log(DateToStr(Date));']);
  AssertFixed(InUnit(['  r := DateToStr(d, TFormatSettings.Invariant);',
    '  Log(DateToStr(Date));']), Src, BODY_LINE, Msg('datetostr'), True);
  Assert.AreEqual(_(R_FS_PAIR_HINT, ['B', BODY_LINE + 1, 'DateToStr']),
    PairHintOf(Src, BODY_LINE));
  Src := InUnit(['  r := DateToStr(d);', '  if r <> DateToStr(Date) then',
    '    r := '''';']);
  Assert.AreEqual(_(R_FS_PAIR_HINT, ['B', BODY_LINE + 1, 'DateToStr']),
    PairHintOf(Src, BODY_LINE));
  // rwE29, rgInvoiceItemEdit.pas:217: CurrToStr ins Eingabefeld, zurueck
  // mit TryStrToCurr (ohne eigenen Fund) - dieselbe Zahlen-Familie.
  Src := InUnit(['  r := CurrToStr(x);', '  if TryStrToCurr(s, x) then',
    '    r := '''';']);
  Assert.AreEqual(_(R_FS_PAIR_HINT, ['B', BODY_LINE + 1, 'TryStrToCurr']),
    PairHintOf(Src, BODY_LINE));
  // rwE29, wbDefinitionsCommon.pas:996/997: zwei StrToFloat, verglichen;
  // auch ein Aufruf mit der globalen FormatSettings ist kein Invariant.
  Src := InUnit(['  x := StrToFloat(s);',
    '  if x = StrToFloat(r, FormatSettings) then', '    r := '''';']);
  Assert.AreEqual(_(R_FS_PAIR_HINT, ['B', BODY_LINE + 1, 'StrToFloat']),
    PairHintOf(Src, BODY_LINE));
end;

procedure TTestRdxFormatSettingsFix.Sca128_Alt_NoPairInFile_PlainHint;
var
  Src : string;
begin
  // Gegenprobe: eine andere Familie, ein Aufruf derselben Familie, der
  // schon Invariant uebergibt (auch ueber zwei Zeilen), ein Member gleichen
  // Namens (eine andere Routine) und ein Kommentar nennt der Hinweis nicht.
  Src := InUnit(['  r := DateToStr(d);', '  x := StrToFloat(s);',
    '  d := StrToDate(r,', '    TFormatSettings.Invariant);',
    '  r := Fmt.DateToStr(d);', '  // DateToStr(d)']);
  AssertFixed(InUnit(['  r := DateToStr(d, TFormatSettings.Invariant);',
    '  x := StrToFloat(s);',
    '  d := StrToDate(r,', '    TFormatSettings.Invariant);',
    '  r := Fmt.DateToStr(d);', '  // DateToStr(d)']), Src, BODY_LINE,
    Msg('datetostr'), True);
  Assert.AreEqual('B', PairHintOf(Src, BODY_LINE));
  // Ohne Aufruf auf der Zeile bleibt der Grundhinweis.
  Assert.AreEqual('B', PairHintOf(Src, BODY_LINE - 1));
end;

// ---- Realworld-Test rwE30 Stufe 2 ----

procedure TTestRdxFormatSettingsFix.Sca128_MultiLineCall_ClosesLower;
var
  E : TRdxEdit;
  R : string;
begin
  // Die Klammer schliesst eine Zeile tiefer (bis dahin R_FS_OPEN 'schliesst
  // nicht auf der gemeldeten Zeile'): eingefuegt hinter dem letzten Argument
  // auf der Zeile der Klammer.
  AssertFixed(InUnit(['  r := FormatDateTime(''yyyy-mm-dd'',',
    '    d, FormatSettings);']),
    InUnit(['  r := FormatDateTime(''yyyy-mm-dd'',', '    d);']), BODY_LINE,
    Msg('formatdatetime'));
  // Die Klammer allein auf der naechsten Zeile: hinter das Zeilenende des
  // letzten Arguments; der Bereich beginnt auf seinem letzten Zeichen.
  Assert.IsTrue(PlanOn(InUnit(['  r := DateToStr(d', '    );']), BODY_LINE,
    Msg('datetostr'), False, E, R), R);
  Assert.AreEqual<Integer>(BODY_LINE, E.Span.StartLine);
  Assert.AreEqual<Integer>(18, E.Span.StartCol);
  Assert.AreEqual<Integer>(BODY_LINE + 1, E.Span.EndLine);
  Assert.AreEqual('d'#10'    )', E.Expected);
  Assert.AreEqual('d, FormatSettings'#10'    )', E.NewText);
  AssertFixed(InUnit(['  r := DateToStr(d, TFormatSettings.Invariant', '    );']),
    InUnit(['  r := DateToStr(d', '    );']), BODY_LINE, Msg('datetostr'),
    True);
  // Ein Zeilenkommentar zwischen Argument und Klammer bleibt dahinter.
  AssertFixed(InUnit(['  r := DateToStr(d, FormatSettings // Datum', '    );']),
    InUnit(['  r := DateToStr(d // Datum', '    );']), BODY_LINE,
    Msg('datetostr'));
end;

procedure TTestRdxFormatSettingsFix.Sca128_MultiLineCall_Break_NoHelp;
var
  Src : string;
begin
  // Gegenproben: eine Direktive bzw. ein Kommentar ueber Zeilen zwischen
  // den Klammern, eine Klammer mehr als MAX_CALL_LINES (10) tiefer.
  AssertRefused(InUnit(['  r := DateToStr(', '    {$IFDEF X} d {$ELSE} e {$ENDIF});']),
    BODY_LINE, Msg('datetostr'), _(R_FS_CALL_BREAK, ['DateToStr', BODY_LINE,
    BODY_LINE + 1]));
  AssertRefused(InUnit(['  r := DateToStr(d { Datum', '    }', '    );']),
    BODY_LINE, Msg('datetostr'), _(R_FS_CALL_BREAK, ['DateToStr', BODY_LINE,
    BODY_LINE + 2]));
  Src := InUnit(['  r := DateToStr(', '', '', '', '', '', '', '', '', '', '',
    '    d);']);
  AssertRefused(Src, BODY_LINE, Msg('datetostr'),
    _(R_FS_OPEN, ['DateToStr', 10]));
end;

procedure TTestRdxFormatSettingsFix.Sca128_FollowLines_AllCalls;
var
  Src : string;
begin
  // delphimvcframework ...\MainControllerU.pas:47: die Anweisung beginnt mit
  // 'Render(StrDict()', der einzige Aufruf steht zwei Zeilen tiefer.
  Src := InUnit(['  Render(StrDict()', '    .Add(''message'', ''Hello'')',
    '    .Add(''timestamp'', FormatDateTime(''yyyy-mm-dd hh:nn:ss'', d))',
    '    .Add(''storage'', ''Redis''));']);
  AssertFixed(InUnit(['  Render(StrDict()', '    .Add(''message'', ''Hello'')',
    '    .Add(''timestamp'', FormatDateTime(''yyyy-mm-dd hh:nn:ss'', d, '
    + 'TFormatSettings.Invariant))',
    '    .Add(''storage'', ''Redis''));']), Src, BODY_LINE,
    Msg('formatdatetime'), True);
  // TES5Edit wbLOD.pas:3082: 'sl.Add(' und vier FloatToStr auf den
  // Folgezeilen - alle in einer Ersetzung.
  Src := InUnit(['  Add(', '    FloatToStr(x) + #9 +', '    FloatToStr(x) + #9 +',
    '    ''1'');']);
  AssertFixed(InUnit(['  Add(', '    FloatToStr(x, FormatSettings) + #9 +',
    '    FloatToStr(x, FormatSettings) + #9 +', '    ''1'');']), Src,
    BODY_LINE, Msg('floattostr'));
end;

procedure TTestRdxFormatSettingsFix.Sca128_FollowLines_Directive_NoHelp;
begin
  // Gegenprobe: eine Direktive zwischen Fundzeile und Aufruf - Code unter
  // Bedingung.
  AssertRefused(InUnit(['  Add(', '    {$IFDEF X} ''x'' + {$ENDIF}',
    '    FloatToStr(x));']), BODY_LINE, Msg('floattostr'), _(R_FS_DIRECTIVE));
  // Ein Aufruf hinter dem Ende der Anweisung zaehlt nicht mit.
  AssertRefused(InUnit(['  Add(''x'');', '  r := FloatToStr(x);']), BODY_LINE,
    Msg('floattostr'), Moved('floattostr'));
end;

procedure TTestRdxFormatSettingsFix.Sca128_WithEnded_Helps;
begin
  // Dev-Cpp Project.pas:1501: das with endet mit seinem try..finally..end
  // lange vor dem Aufruf (bis dahin R_FS_WITH).
  AssertFixed(InUnit(['  with TObject.Create do try', '    Foo;',
    '  finally', '    Free;', '  end;', '  r := FloatToStr(x, FormatSettings);']),
    InUnit(['  with TObject.Create do try', '    Foo;', '  finally',
    '    Free;', '  end;', '  r := FloatToStr(x);']), BODY_LINE + 5,
    Msg('floattostr'));
  // with mit begin..end und mit einer Anweisung bis ';'.
  AssertFixed(InUnit(['  with Obj do begin Foo; end;', '  with Obj do Bar(1);',
    '  r := FloatToStr(x, FormatSettings);']),
    InUnit(['  with Obj do begin Foo; end;', '  with Obj do Bar(1);',
    '  r := FloatToStr(x);']), BODY_LINE + 2, Msg('floattostr'));
  // TES5Edit ProcAnalyzeMesh.pas:213: das with steht in einer lokalen
  // Prozedur vor dem Rumpf.
  AssertFixed(UnitText(RTL_USES, [],
    ['  r := FloatToStr(x, FormatSettings);']),
    UnitText(RTL_USES, [], ['  r := FloatToStr(x);']), BODY_LINE,
    Msg('floattostr'));
  AssertFixed(StringReplace(UnitText(RTL_USES, [],
    ['  r := FloatToStr(x, FormatSettings);']), 'var' + CRLF + '  r: string;',
    'var' + CRLF + '  r: string;' + CRLF + '  procedure Q;' + CRLF
    + '  begin with Obj do begin Foo; end; end;', []),
    StringReplace(UnitText(RTL_USES, [], ['  r := FloatToStr(x);']),
    'var' + CRLF + '  r: string;', 'var' + CRLF + '  r: string;' + CRLF
    + '  procedure Q;' + CRLF + '  begin with Obj do begin Foo; end; end;', []),
    BODY_LINE + 2, Msg('floattostr'));
end;

procedure TTestRdxFormatSettingsFix.Sca128_WithEncloses_NoHelp;
begin
  // Gegenproben: der Aufruf im Block bzw. in der Anweisung des with - der
  // Alt-Weg sperrt, der Hauptweg qualifiziert (seit rwE31 Stufe 3).
  AssertRefused(InUnit(['  with Obj do begin', '    r := FloatToStr(x);',
    '  end;']), BODY_LINE + 1, Msg('floattostr'), _(R_FS_WITH, [BODY_LINE]),
    True);
  AssertRefused(InUnit(['  with Obj do', '    if x > 0 then', '      Foo',
    '    else', '      r := FloatToStr(x);']), BODY_LINE + 4,
    Msg('floattostr'), _(R_FS_WITH, [BODY_LINE]), True);
  AssertRefused(InUnit(['  with Obj do try', '    r := FloatToStr(x);',
    '  finally', '    Free;', '  end;']), BODY_LINE + 1, Msg('floattostr'),
    _(R_FS_WITH, [BODY_LINE]), True);
  AssertFixed(InUnit(['  with Obj do try',
    '    r := FloatToStr(x, System.SysUtils.FormatSettings);',
    '  finally', '    Free;', '  end;']),
    InUnit(['  with Obj do try', '    r := FloatToStr(x);',
    '  finally', '    Free;', '  end;']), BODY_LINE + 1, Msg('floattostr'));
  // Ein with in der anonymen Methode der Anweisung um einen spaeteren
  // Aufruf (seit rwE31 Stufe 3 jeder Aufruf geprueft).
  AssertRefused(InUnit(['  r := FloatToStr(x) + Run(procedure begin',
    '    with Obj do s := FloatToStr(y); end);']), BODY_LINE,
    Msg('floattostr'), _(R_FS_WITH, [BODY_LINE + 1]), True);
end;

procedure TTestRdxFormatSettingsFix.Sca128_OldMormotSymbols_Block;
begin
  // mORMot2 mormot.core.i18n.pas:1289 - '{$ifdef ISDELPHIXE} .. {$else}
  // // old Delphi 7-2010': die globale FormatSettings gibt es erst ab XE.
  AssertRefused(InOldUnit(['  r := DateTimeToStr(d);',
    '  {$ifdef ISDELPHIXE} Foo; {$else} Bar; {$endif}']), BODY_LINE,
    Msg('datetimetostr'), _(R_FS_OLD_VAR, ['ISDELPHIXE', BODY_LINE + 1]));
  // mormot.core.log.pas:8204 - ISDELPHI2005ANDUP.
  AssertRefused(InOldUnit(['  r := DateToStr(d);',
    '  {$ifdef ISDELPHI2005ANDUP} Foo; {$endif}']), BODY_LINE,
    Msg('datetostr'), _(R_FS_OLD_VAR, ['ISDELPHI2005ANDUP', BODY_LINE + 1]));
  // Das Kit-Include allein sperrt seit rwE31 Stufe 3 nicht mehr im Planer,
  // sondern im Plattenblick - dort widerlegt es ein Projekt der Unit ab XE
  // (uRdxMagicFixes.ProjectReason, uTestRdxMagicGuards.
  // Disk_KitIncludeModernProject_Refutes; mORMot2 dmvc-ai api.impl.pas:50).
  AssertFixed(UnitText('SysUtils', ['{$I ..\mormot.defines.inc}'],
    ['  r := DateToStr(d, FormatSettings);']),
    UnitText('SysUtils', ['{$I ..\mormot.defines.inc}'],
    ['  r := DateToStr(d);']), BODY_LINE + 1, Msg('datetostr'));
  // Gegenprobe: ISDELPHIXE2 (CompilerVersion 23) ist nach XE.
  AssertFixed(InOldUnit(['  r := DateToStr(d, FormatSettings);',
    '  {$ifdef ISDELPHIXE2} Foo; {$endif}']),
    InOldUnit(['  r := DateToStr(d);', '  {$ifdef ISDELPHIXE2} Foo; {$endif}']),
    BODY_LINE, Msg('datetostr'));
end;

procedure TTestRdxFormatSettingsFix.Sca128_ModernProof_RefutesTraces;
begin
  // Ein RTL-Namensraum im uses beweist Delphi XE2: die Weiche fuer Delphi
  // 2010 ist dort toter Code (rwE30 Stufe 2, ModernProof).
  AssertFixed(InUnit(['  r := DateToStr(d, FormatSettings);',
    '  {$IFDEF VER210} Foo; {$ENDIF}']),
    InUnit(['  r := DateToStr(d);', '  {$IFDEF VER210} Foo; {$ENDIF}']),
    BODY_LINE, Msg('datetostr'));
  // Gegenprobe: unter einer Bedingung beweist er nichts.
  AssertRefused(UnitText('{$IFDEF X} System.Classes, {$ENDIF} SysUtils',
    [], ['  r := DateToStr(d);', '  {$IFDEF VER210} Foo; {$ENDIF}']), BODY_LINE,
    Msg('datetostr'), _(R_FS_OLD_VAR, ['VER210', BODY_LINE + 1]));
  // Fuer Invariant (10.3) reicht XE2 nicht.
  AssertRefused(InUnit(['  r := DateToStr(d);', '  {$IFDEF VER320} Foo; {$ENDIF}']),
    BODY_LINE, Msg('datetostr'), _(R_FS_OLD_INVARIANT, ['VER320',
    BODY_LINE + 1]), True);
end;

procedure TTestRdxFormatSettingsFix.Sca128_Alt_InlineVarRefutesFpc;
var
  Src : string;
begin
  // Alcinoe dwsJSON.pas:2612: die FPC-Weiche in Zeile 71 betrifft nur
  // Deklarationen, die Unit nutzt unbedingt Inline-Variablen - FPC 3.2
  // uebersetzt sie nicht, Delphi 10.3+ ist belegt.
  Src := InUnit(['  r := FloatToStr(x);', '  {$IFDEF FPC} Foo; {$ENDIF}',
    '  for var i := 1 to 3 do Bar;']);
  AssertFixed(InUnit(['  r := FloatToStr(x, TFormatSettings.Invariant);',
    '  {$IFDEF FPC} Foo; {$ENDIF}', '  for var i := 1 to 3 do Bar;']), Src,
    BODY_LINE, Msg('floattostr'), True);
  AssertFixed(InUnit(['  r := FloatToStr(x, TFormatSettings.Invariant);',
    '  {$IFDEF VER320} Foo; {$ENDIF}', '  var n: Extended := x;']),
    InUnit(['  r := FloatToStr(x);', '  {$IFDEF VER320} Foo; {$ENDIF}',
    '  var n: Extended := x;']), BODY_LINE, Msg('floattostr'), True);
  // Gegenprobe: die Inline-Variable unter einer Bedingung beweist nichts;
  // ein lokaler var-Abschnitt ist keine.
  AssertRefused(InUnit(['  r := FloatToStr(x);', '  {$IFDEF FPC} Foo; {$ELSE}',
    '  for var i := 1 to 3 do Bar;', '  {$ENDIF}']), BODY_LINE,
    Msg('floattostr'), _(R_FS_FPC, [BODY_LINE + 1]), True);
  AssertRefused(InUnit(['  r := FloatToStr(x);', '  {$IFDEF FPC} Foo; {$ENDIF}']),
    BODY_LINE, Msg('floattostr'), _(R_FS_FPC, [BODY_LINE + 1]), True);
end;

procedure TTestRdxFormatSettingsFix.Sca128_Alt_InvariantInFileRefutesTrace;
begin
  // TemplatePro.pas: die Datei setzt selbst 'fLocaleFormatSettings :=
  // TFormatSettings.Invariant' ohne Weiche - wer sie baut, kennt Invariant.
  AssertFixed(InUnit(['  r := DateToStr(d, TFormatSettings.Invariant);',
    '  {$IFDEF VER320} Foo; {$ENDIF}', '  F := TFormatSettings.Invariant;']),
    InUnit(['  r := DateToStr(d);', '  {$IFDEF VER320} Foo; {$ENDIF}',
    '  F := TFormatSettings.Invariant;']), BODY_LINE, Msg('datetostr'), True);
  // Gegenprobe: unter der Weiche beweist es nichts.
  AssertRefused(InUnit(['  r := DateToStr(d);',
    '  {$IFDEF VER320} F := TFormatSettings.Invariant; {$ENDIF}']), BODY_LINE,
    Msg('datetostr'), _(R_FS_OLD_INVARIANT, ['VER320', BODY_LINE + 1]), True);
end;

procedure TTestRdxFormatSettingsFix.Sca128_Alt_FpcExcludedBranch_Helps;
const
  HEAD: array[0..2] of string = ('{$IF DEFINED(FPC)}', '  {$MODE DELPHI}{$H+}',
    '{$ENDIF}');
begin
  // horse Horse.Core.Param.Field.pas:245: die FPC-Weiche (Zeile 3) gilt
  // nicht im Zweig '{$IF NOT DEFINED(FPC)}' - FPC uebersetzt ihn nie.
  AssertFixed(UnitText(RTL_USES, HEAD, ['  {$IF NOT DEFINED(FPC)}',
    '  x := StrToFloat(s, TFormatSettings.Invariant);', '  {$ENDIF}']),
    UnitText(RTL_USES, HEAD, ['  {$IF NOT DEFINED(FPC)}',
    '  x := StrToFloat(s);', '  {$ENDIF}']), BODY_LINE + 4, Msg('strtofloat'),
    True);
  AssertFixed(UnitText(RTL_USES, HEAD, ['  {$IFDEF FPC} Foo; {$ELSE}',
    '  x := StrToFloat(s, TFormatSettings.Invariant);', '  {$ENDIF}']),
    UnitText(RTL_USES, HEAD, ['  {$IFDEF FPC} Foo; {$ELSE}',
    '  x := StrToFloat(s);', '  {$ENDIF}']), BODY_LINE + 4, Msg('strtofloat'),
    True);
  // Gegenproben: ausserhalb des Zweigs, im FPC-Zweig selbst.
  AssertRefused(UnitText(RTL_USES, HEAD, ['  x := StrToFloat(s);']),
    BODY_LINE + 3, Msg('strtofloat'), _(R_FS_FPC, [6]), True);
  AssertRefused(UnitText(RTL_USES, HEAD, ['  {$IFDEF FPC}',
    '  x := StrToFloat(s);', '  {$ENDIF}']), BODY_LINE + 4, Msg('strtofloat'),
    _(R_FS_FPC, [6]), True);
end;

procedure TTestRdxFormatSettingsFix.Sca128_Alt_GlobalSettingsSet_NoHelp;
var
  Src : string;
begin
  // HeidiSQL: das Programm stellt die globale FormatSettings selbst ein
  // (ShortDateFormat 'yyyy/mm/dd') - Invariant schriebe MM/dd/yyyy
  // (main.pas:11246, EditMask 0000-00-00). Hier in der Unit selbst; das
  // Programm prueft der Plattenblick.
  Src := InUnit(['  r := DateToStr(d);',
    '  FormatSettings.ShortDateFormat := ''yyyy/mm/dd'';']);
  AssertRefused(Src, BODY_LINE, Msg('datetostr'),
    _(R_FS_SETTINGS_SET, ['ShortDateFormat', BODY_LINE + 1]), True);
  AssertFixed(InUnit(['  r := DateToStr(d, FormatSettings);',
    '  FormatSettings.ShortDateFormat := ''yyyy/mm/dd'';']), Src, BODY_LINE,
    Msg('datetostr'));
  AssertRefused(InUnit(['  r := DateToStr(d);',
    '  SysUtils.FormatSettings.LongMonthNames[1] := ''Jan'';']), BODY_LINE,
    Msg('datetostr'), _(R_FS_SETTINGS_SET, ['LongMonthNames', BODY_LINE + 1]),
    True);
  // Gegenproben: ein Zahlenfeld (xEdit.dpr setzt DecimalSeparator '.' -
  // das schreibt Invariant ohnehin), gelesen, als Member eines anderen
  // Objekts.
  AssertFixed(InUnit(['  r := FloatToStr(x, TFormatSettings.Invariant);',
    '  FormatSettings.DecimalSeparator := ''.'';']),
    InUnit(['  r := FloatToStr(x);', '  FormatSettings.DecimalSeparator := ''.'';']),
    BODY_LINE, Msg('floattostr'), True);
  AssertFixed(InUnit(['  r := DateToStr(d, TFormatSettings.Invariant);',
    '  c := FormatSettings.DateSeparator;']),
    InUnit(['  r := DateToStr(d);', '  c := FormatSettings.DateSeparator;']),
    BODY_LINE, Msg('datetostr'), True);
  AssertFixed(InUnit(['  r := DateToStr(d, TFormatSettings.Invariant);',
    '  W.FormatSettings.ShortDateFormat := ''yyyy'';']),
    InUnit(['  r := DateToStr(d);', '  W.FormatSettings.ShortDateFormat := ''yyyy'';']),
    BODY_LINE, Msg('datetostr'), True);
end;

procedure TTestRdxFormatSettingsFix.Sca128_Alt_CompareLiteral_NoHelp;
begin
  // horse Tests.Horse.Core.Param.pas:292: mit Invariant schriebe CurrToStr
  // '5.5', der Vergleich mit '5,5' scheiterte auf jedem System.
  AssertRefused(InUnit(['  Assert.AreEqual(''5,5'', CurrToStr(x));']),
    BODY_LINE, Msg('currtostr'), _(R_FS_LIT_COMPARE, ['''5,5''', 'CurrToStr']),
    True);
  AssertRefused(InUnit(['  if DateToStr(d) = ''29.10.2026'' then Foo;']),
    BODY_LINE, Msg('datetostr'), _(R_FS_LIT_COMPARE, ['''29.10.2026''',
    'DateToStr']), True);
  // Der Hauptweg bleibt (gleiche Bedeutung).
  AssertFixed(InUnit(['  Assert.AreEqual(''5,5'', CurrToStr(x, FormatSettings));']),
    InUnit(['  Assert.AreEqual(''5,5'', CurrToStr(x));']), BODY_LINE,
    Msg('currtostr'));
  // Gegenproben: Literal im Invariant-Format, Formatmuster in der Klammer,
  // ein Text ohne Zahl.
  AssertFixed(InUnit(['  Assert.AreEqual(''5.5'', CurrToStr(x, '
    + 'TFormatSettings.Invariant));']),
    InUnit(['  Assert.AreEqual(''5.5'', CurrToStr(x));']), BODY_LINE,
    Msg('currtostr'), True);
  AssertFixed(InUnit(['  r := FormatFloat(''0,00'', x, TFormatSettings.Invariant);']),
    InUnit(['  r := FormatFloat(''0,00'', x);']), BODY_LINE, Msg('formatfloat'),
    True);
  AssertFixed(InUnit(['  r := ''Wert: 1,5 '' + FloatToStr(x, '
    + 'TFormatSettings.Invariant);']),
    InUnit(['  r := ''Wert: 1,5 '' + FloatToStr(x);']), BODY_LINE,
    Msg('floattostr'), True);
end;

procedure TTestRdxFormatSettingsFix.Sca128_Alt_PairInSameRoutineFirst;
var
  Src : string;
begin
  // HeidiSQL main.pas:14718: das Gegenstueck in derselben Routine (Zeile
  // 14698) zuerst - bis dahin nannte der Hinweis den ersten Aufruf der
  // Datei (Zeile 1782, eine andere Routine).
  Src := UnitText(RTL_USES,
    ['procedure Q;', 'begin', '  r := DateTimeToStr(Now);', 'end;'],
    ['  s := DateToStr(d);', '  if s <> DateToStr(Date) then', '    Foo;']);
  Assert.AreEqual(_(R_FS_PAIR_HINT, ['B', BODY_LINE + 5, 'DateToStr']),
    PairHintOf(Src, BODY_LINE + 4));
  // Ohne Gegenstueck in der Routine: die Datei wie bisher.
  Src := UnitText(RTL_USES,
    ['procedure Q;', 'begin', '  r := DateTimeToStr(Now);', 'end;'],
    ['  s := DateToStr(d);']);
  Assert.AreEqual(_(R_FS_PAIR_HINT, ['B', 8, 'DateTimeToStr']),
    PairHintOf(Src, BODY_LINE + 4));
end;

// ---- Realworld-Test rwE31 Stufe 3: gekoppelte Auswertung ----

procedure TTestRdxFormatSettingsFix.Sca128_Alt_CoupledCompare_NoHelp;
var
  Src : string;
begin
  // delphimvcframework FrameworkTestsU.pas:1986: nur s2 auf Invariant, s1
  // bleibt lokal - 'Assert.areEqual(s1,s2)' scheitert danach ausser in
  // en-US. Bis rwE31 Stufe 3 angeboten (nur Hinweis auf Zeile 1985).
  Src := InUnit([
    '  lDate := ISOTimeStampToDateTime(''2020-08-15T12:12:12Z'');',
    '  s1 := DateTimeToStr(lDate);',
    '  s2 := DateTimeToStr(lDateToCompare);',
    '  Assert.areEqual(s1,s2, ''UTC with no time zone (in DST period)'');']);
  AssertRefused(Src, BODY_LINE + 2, Msg('datetimetostr'),
    _(R_FS_COUPLED_PAIR, [BODY_LINE + 3, 's2', 's1', BODY_LINE + 1,
    'DateTimeToStr']), True);
  // Der Hauptweg aendert nichts am Verhalten und bleibt.
  AssertFixed(InUnit([
    '  lDate := ISOTimeStampToDateTime(''2020-08-15T12:12:12Z'');',
    '  s1 := DateTimeToStr(lDate);',
    '  s2 := DateTimeToStr(lDateToCompare, FormatSettings);',
    '  Assert.areEqual(s1,s2, ''UTC with no time zone (in DST period)'');']),
    Src, BODY_LINE + 2, Msg('datetimetostr'));
  // FrameworkTestsU.pas:1964: zwei Bloecke in der Routine - gemeldet wird
  // der Partner des eigenen Blocks (Zeile 1965) und sein Vergleich (1966),
  // nicht der vorige Block (bis dahin nannte der Hinweis Zeile 1956).
  Src := InUnit(['  s1 := DateTimeToStr(lDate);',
    '  s2 := DateTimeToStr(lDateToCompare);',
    '  Assert.areEqual(s1,s2, ''DST'');',
    '  s1 := DateTimeToStr(lDate);',
    '  s2 := DateTimeToStr(lDateToCompare);',
    '  Assert.areEqual(s1,s2, ''no DST'');']);
  AssertRefused(Src, BODY_LINE + 3, Msg('datetimetostr'),
    _(R_FS_COUPLED_PAIR, [BODY_LINE + 5, 's1', 's2', BODY_LINE + 4,
    'DateTimeToStr']), True);
  // Das Gegenstueck selbst vergleicht mit dem Ergebnis.
  AssertRefused(InUnit(['  r := DateToStr(d);',
    '  if r <> DateToStr(Date) then', '    r := '''';']), BODY_LINE,
    Msg('datetostr'), _(R_FS_COUPLED_CALL, [BODY_LINE + 1, 'r', 'DateToStr']),
    True);
  // Schreiben und Lesen: CurrToStr ins Feld, TryStrToCurr liest es zurueck.
  AssertRefused(InUnit(['  r := CurrToStr(x);', '  if TryStrToCurr(r, x) then',
    '    Foo;']), BODY_LINE, Msg('currtostr'),
    _(R_FS_COUPLED_CALL, [BODY_LINE + 1, 'r', 'TryStrToCurr']), True);
  // Der umgestellte Aufruf nennt das Ziel des Gegenstuecks.
  AssertRefused(InUnit(['  r := DateToStr(Date);',
    '  Result := DateToStr(d) = r;']), BODY_LINE + 1, Msg('datetostr'),
    _(R_FS_COUPLED_PAIR, [BODY_LINE + 1, 'DateToStr', 'r', BODY_LINE,
    'DateToStr']), True);
end;

procedure TTestRdxFormatSettingsFix.Sca128_Alt_CoupledSettings_NoHelp;
var
  Src : string;
begin
  // delphimvcframework MVCFramework.Validators.pas:1647: mit Invariant faende
  // 'Pos(FormatSettings.DecimalSeparator, LStrValue)' in Komma-Locales
  // keinen Trenner mehr - die Scale-Pruefung entfiele. Bis rwE31 Stufe 3
  // angeboten.
  Src := InUnit(['  LValue := AValue.AsExtended;',
    '  LStrValue := FloatToStr(Abs(LValue));', '',
    '  LDecimalPos := Pos(FormatSettings.DecimalSeparator, LStrValue);',
    '  if LDecimalPos > 0 then', '    Foo;']);
  AssertRefused(Src, BODY_LINE + 1, Msg('floattostr'),
    _(R_FS_COUPLED_SETTINGS, [BODY_LINE + 3, 'LStrValue',
    'FormatSettings.DecimalSeparator']), True);
  // Der Hauptweg bleibt (dieselbe globale FormatSettings auf beiden Seiten).
  AssertFixed(InUnit(['  LValue := AValue.AsExtended;',
    '  LStrValue := FloatToStr(Abs(LValue), FormatSettings);', '',
    '  LDecimalPos := Pos(FormatSettings.DecimalSeparator, LStrValue);',
    '  if LDecimalPos > 0 then', '    Foo;']), Src, BODY_LINE + 1,
    Msg('floattostr'));
  // Ein Leser, dessen Argument FormatSettings liest: der normalisierte
  // Text passt nicht mehr zu Invariant.
  AssertRefused(InUnit(['  x := StrToFloat(StringReplace(s, ''.'', '
    + 'FormatSettings.DecimalSeparator, []));']), BODY_LINE,
    Msg('strtofloat'), _(R_FS_COUPLED_SETTINGS, [BODY_LINE, 'StrToFloat',
    'FormatSettings.DecimalSeparator']), True);
end;

procedure TTestRdxFormatSettingsFix.Sca128_Alt_NotCoupled_Helps;
begin
  // Gegenproben: zwei Werte derselben Familie, getrennt ausgegeben; ein
  // Leser, dessen Zahl formatiert wird (keine Text-Kopplung, Rundlauf des
  // Detektors 'x := StrToCurr(s); r := FormatCurr(.., x)'); FormatSettings
  // in einer anderen Routine; ein Member mit aehnlichem Namen.
  AssertFixed(InUnit(['  s1 := DateTimeToStr(d);', '  Log(s1);',
    '  s2 := DateTimeToStr(Now, TFormatSettings.Invariant);', '  Log(s2);']),
    InUnit(['  s1 := DateTimeToStr(d);', '  Log(s1);',
    '  s2 := DateTimeToStr(Now);', '  Log(s2);']), BODY_LINE + 2,
    Msg('datetimetostr'), True);
  AssertFixed(InUnit(['  x := StrToCurr(s, TFormatSettings.Invariant);',
    '  r := FormatCurr(''0.00'', x);']),
    InUnit(['  x := StrToCurr(s);', '  r := FormatCurr(''0.00'', x);']),
    BODY_LINE, Msg('strtocurr'), True);
  AssertFixed(InUnit(['  x := StrToCurr(s);',
    '  r := FormatCurr(''0.00'', x, TFormatSettings.Invariant);']),
    InUnit(['  x := StrToCurr(s);', '  r := FormatCurr(''0.00'', x);']),
    BODY_LINE + 1, Msg('formatcurr'), True);
  AssertFixed(UnitText(RTL_USES, ['procedure Q;', 'begin',
    '  r := Pos(FormatSettings.DecimalSeparator, r);', 'end;'],
    ['  r := FloatToStr(x, TFormatSettings.Invariant);']),
    UnitText(RTL_USES, ['procedure Q;', 'begin',
    '  r := Pos(FormatSettings.DecimalSeparator, r);', 'end;'],
    ['  r := FloatToStr(x);']), BODY_LINE + 4, Msg('floattostr'), True);
  AssertFixed(InUnit(['  r := FloatToStr(x, TFormatSettings.Invariant);',
    '  Obj.r := Pos(''.'', Obj.FormatSettingsText);']),
    InUnit(['  r := FloatToStr(x);',
    '  Obj.r := Pos(''.'', Obj.FormatSettingsText);']), BODY_LINE,
    Msg('floattostr'), True);
end;

procedure TTestRdxFormatSettingsFix.Sca128_FollowLines_AnonymousMethod;
const
  HEAD: array[0..5] of string = ('  TTask.Create (procedure ()', '    begin',
    '      sleep(250);', '      TThread.Synchronize(nil,', '        procedure',
    '        begin');
  TAIL: array[0..1] of string = ('        end);', '    end).Start;');
var
  Src : string;
begin
  // Alcinoe Demos\ALFmxControls\_Source\Main.pas:1444: der Detektor meldet
  // die Zeile von 'TTask.Create (', die beiden FormatFloat stehen in der
  // anonymen Methode in 1450/1451 - ';' und begin/end dort beenden die
  // Anweisung nicht (offene Klammer). Bis rwE31 Stufe 3 'kein Aufruf von
  // formatfloat ... - Zeile verschoben?'.
  Src := InUnit([HEAD[0], HEAD[1], HEAD[2], HEAD[3], HEAD[4], HEAD[5],
    '          Text4.Text := ''buffer: '' + FormatFloat(''0.#####'',a) + '' - '' +',
    '                        ''Paint: '' + FormatFloat(''0.#####'',b) + '' ms'';',
    TAIL[0], TAIL[1]]);
  AssertFixed(InUnit([HEAD[0], HEAD[1], HEAD[2], HEAD[3], HEAD[4], HEAD[5],
    '          Text4.Text := ''buffer: '' + FormatFloat(''0.#####'',a, '
    + 'FormatSettings) + '' - '' +',
    '                        ''Paint: '' + FormatFloat(''0.#####'',b, '
    + 'FormatSettings) + '' ms'';',
    TAIL[0], TAIL[1]]), Src, BODY_LINE, Msg('formatfloat'));
  // Gegenprobe: schliesst die Klammer der anonymen Methode mit ';', gehoert
  // der Aufruf der naechsten Anweisung nicht dazu.
  AssertRefused(InUnit(['  Run(procedure begin Foo; end);',
    '  r := FormatFloat(''0.0'', x);']), BODY_LINE, Msg('formatfloat'),
    Moved('formatfloat'));
end;

procedure TTestRdxFormatSettingsFix.Sca128_Alt_PairHint_NearestWithoutOwnSettings;
begin
  // FrameworkTestsU.pas:1964 / wbLOD.pas:3543: der Hinweis nennt das
  // NAECHSTE Gegenstueck (bis rwE31 Stufe 3 das erste der Routine bzw.
  // Datei).
  Assert.AreEqual(_(R_FS_PAIR_HINT, ['B', BODY_LINE + 4, 'DateToStr']),
    PairHintOf(InUnit(['  r := DateToStr(Date);', '  Foo;', '  Foo;',
    '  s := DateToStr(d);', '  Bar(DateToStr(e));']), BODY_LINE + 3));
  // TemplatePro.pas:3365: ein Aufruf mit eigenen Einstellungen
  // (fLocaleFormatSettings) ist kein Gegenstueck - der Hinweis riet, ihn
  // auf Invariant umzustellen.
  Assert.AreEqual('B', PairHintOf(InUnit(['  r := FormatFloat(''0.00'', x);',
    '  s := FormatFloat(''0'', x, fLocaleFormatSettings);']), BODY_LINE));
  // Gegenprobe: die globale FormatSettings ausdruecklich bleibt eines.
  Assert.AreEqual(_(R_FS_PAIR_HINT, ['B', BODY_LINE + 1, 'FormatFloat']),
    PairHintOf(InUnit(['  r := FormatFloat(''0.00'', x);',
    '  s := FormatFloat(''0'', x, FormatSettings);']), BODY_LINE));
end;

{$IFNDEF FPC}

// ---- echter Detektor ----

const
  FILE_PREFIX = 'rdx_fmtset_';

procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TDateFormatSettingsDetector.AnalyzeUnit(Root, Path, Results);
end;

// Dasselbe in der Form TDetectFunc (FixAllWith).
function DetectKind(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := DetectSource(FILE_PREFIX, ASource, AKind, RunDetector);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectKind(ASource, fkDateFormatSettings);
end;

// Die Hilfe fuer einen Fund ueber den Einstieg der Tabelle (AAlt: der
// zweite Eintrag) - wie der Anbieter (PlanFixIn/PlanAltFixIn). Der Adapter
// liest nur den Text; den Quellstellen-Dienst des Kits fragt er nicht.
function TablePlan(const ASource: string; const ASeen: TSeen;
  AAlt: Boolean): TRdxFixOutcome;
begin
  if AAlt then
    Result := PlanAltFixIn(ASource, 't.pas', fkDateFormatSettings, ASeen)
  else
    Result := PlanFixIn(ASource, 't.pas', fkDateFormatSettings, ASeen);
end;

// Fund fuer Fund ueber die Tabelle beheben, bis der Detektor schweigt
// (FixAllWith; AAlt: der zweite Eintrag).
function FixAll(const ASource: string; AAlt: Boolean): string;
begin
  Result := FixAllWith(ASource, fkDateFormatSettings, DetectKind, AAlt);
end;

// Das Katalog-Beispiel als Rumpf von P (Zeilenenden CRLF).
function CatalogBody(const AExample: string): string;
begin
  Result := InUnit(['  ' + StringReplace(CatalogText(AExample), CRLF,
    CRLF + '  ', [rfReplaceAll])]);
end;

procedure TTestRdxFormatSettingsFixDetector.Sca128_Detector_CatalogExample;
var
  Meta  : TRuleMeta;
  Bad   : string;
  Fixd  : string;
  Seen  : TArray<TSeen>;
  Hit   : TSeen;
  SL    : TStringList;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkDateFormatSettings);
  Bad := CatalogBody(Meta.BadExample);
  Seen := Detect(Bad);
  Assert.IsTrue(Length(Seen) >= 1, 'der Detektor meldet das Beispiel');
  Fixd := FixAll(Bad, False);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixd)));
  Assert.IsTrue(Pos('WriteLn(DateToStr(Now, FormatSettings));', Fixd) > 0,
    Fixd);
  // Jede gemeldete Zeile traegt danach das Argument (die Hilfe verschiebt
  // keine Zeilen) - so auch die Inline-Variable, wenn der Detektor sie sieht.
  SL := TStringList.Create;
  try
    SL.Text := Fixd;
    for Hit in Seen do
      Assert.IsTrue(Pos(', FormatSettings)', SL[Hit.Line - 1]) > 0,
        SL[Hit.Line - 1]);
  finally
    SL.Free;
  end;
end;

procedure TTestRdxFormatSettingsFixDetector.Sca128_Detector_RoundTrip;
begin
  Assert.AreEqual(InUnit([
    '  r := DateToStr(d, FormatSettings);',
    '  LogIt(FloatToStr(x, FormatSettings));',
    '  r := FormatDateTime(''yyyy'', d, FormatSettings) + TimeToStr(d, FormatSettings);',
    '  x := StrToFloat(s, FormatSettings);',
    '  r := FloatToStr(StrToFloat(s, FormatSettings), FormatSettings);',
    '  r := IntToStr(1);']),
    FixAll(InUnit([
    '  r := DateToStr(d);',
    '  LogIt(FloatToStr(x));',
    '  r := FormatDateTime(''yyyy'', d) + TimeToStr(d);',
    '  x := StrToFloat(s);',
    '  r := FloatToStr(StrToFloat(s));',
    '  r := IntToStr(1);']), False));
end;

procedure TTestRdxFormatSettingsFixDetector.Sca128_Detector_RoundTripAlt;
begin
  Assert.AreEqual(InUnit([
    '  r := DateTimeToStr(d, TFormatSettings.Invariant);',
    '  x := StrToCurr(s, TFormatSettings.Invariant);',
    '  r := FormatCurr(''0.00'', x, TFormatSettings.Invariant);']),
    FixAll(InUnit([
    '  r := DateTimeToStr(d);',
    '  x := StrToCurr(s);',
    '  r := FormatCurr(''0.00'', x);']), True));
end;

procedure TTestRdxFormatSettingsFixDetector.Sca128_Detector_PairInFile_HintNamesLine;
var
  Src, Base : string;
  Seen      : TArray<TSeen>;
  O         : TRdxFixOutcome;
begin
  // Entscheid M2 (Review e/HilfeFixC): der echte Detektor meldet beide
  // Zeilen; der Alt-Weg bleibt angeboten, sein Hinweis nennt die andere
  // Zeile (Paar-Bruch); bis dahin sperrte er. Den Grundhinweis des
  // Adapters liefert eine Quelle ohne Gegenstueck.
  Src := InUnit(['  r := DateTimeToStr(d);']);
  O := TablePlan(Src, Detect(Src)[0], True);
  Assert.IsTrue(O.Enabled, O.Reason);
  Base := O.Hint;
  Src := InUnit(['  x := StrToCurr(s);', '  r := FormatCurr(''0.00'', x);']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(2, Length(Seen), 'zwei Funde');
  if Seen[0].Line <> BODY_LINE then
    Seen[0] := Seen[1];
  Assert.AreEqual<Integer>(BODY_LINE, Seen[0].Line, 'Fund der StrToCurr-Zeile');
  O := TablePlan(Src, Seen[0], True);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.IsTrue(O.ChangesBehavior, 'aendert Verhalten');
  Assert.AreEqual(_(R_FS_PAIR_HINT, [Base, BODY_LINE + 1, 'FormatCurr']),
    O.Hint);
end;

procedure TTestRdxFormatSettingsFixDetector.Sca128_Detector_ContinuedStatement_EditsAll;
var
  Src  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  // rwE30 Stufe 2: beide Aufrufe der Anweisung bekommen das Argument (bis
  // dahin R_FS_CONTINUES), danach schweigt der Detektor.
  Src := InUnit(['  r := DateToStr(d) + '' '' +', '    TimeToStr(d);']);
  Seen := Detect(Src);
  Assert.IsTrue(Length(Seen) >= 1, 'der Detektor meldet die Anweisung');
  Assert.AreEqual<Integer>(BODY_LINE, Seen[0].Line, 'Zeile der Anweisung');
  O := TablePlan(Src, Seen[0], False);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual(InUnit(['  r := DateToStr(d, FormatSettings) + '' '' +',
    '    TimeToStr(d, FormatSettings);']), Apply(Src, O.Edits));
  Assert.AreEqual<Integer>(0, Length(Detect(Apply(Src, O.Edits))),
    'der Detektor schweigt');
end;

procedure TTestRdxFormatSettingsFixDetector.Sca128_Detector_OldDelphiProject_NoHelp;
var
  Root, Dir, U, Dof, Src : string;
  Seen                   : TArray<TSeen>;
  O                      : TRdxFixOutcome;
begin
  // rwE29, gexperts\Src\GX_DbugIntf.pas:149: GExperts baut mit Delphi 1-6
  // (GExpert4.dof eine Ebene ueber Src, keine .dproj); die Unit selbst
  // fragt nach keinem Compiler. Dort gibt es weder die globale
  // FormatSettings noch TFormatSettings.Invariant (E2003). Der Adapter
  // fragt jetzt den Plattenblick (FormatSettingsDiskCheck) - ohne ihn
  // boeten beide Eintraege an (Gegenprobe unten: ohne .dof). 'SysUtils'
  // ohne Namensraum: System.SysUtils bewiese Delphi XE2 (ModernProof,
  // rwE30 Stufe 2), und der Hauptweg fragte die Platte nicht.
  Src := InOldUnit(['  r := DateTimeToStr(d);']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  Root := NewTempDir(FILE_PREFIX);
  try
    Dir := Root + 'gx' + PathDelim + 'Src' + PathDelim;
    ForceDirectories(Dir);
    U := Dir + 'GX_DbugIntf.pas';
    Dof := Root + 'gx' + PathDelim + 'GExpert4.dof';
    WriteText(Dof, '[Compiler]');
    O := PlanFixIn(Src, U, fkDateFormatSettings, Seen[0]);
    Assert.IsFalse(O.Enabled, 'Hauptweg gesperrt');
    Assert.AreEqual(TRdxMagicFixes.FileReason(U, lfFormatSettingsVar),
      O.Reason);
    Assert.IsTrue(Pos('GExpert4.dof', O.Reason) > 0, O.Reason);
    Assert.IsTrue(Pos('FormatSettings', O.Reason) > 0, O.Reason);
    Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
    O := PlanAltFixIn(Src, U, fkDateFormatSettings, Seen[0]);
    Assert.IsFalse(O.Enabled, 'Alt-Weg gesperrt');
    Assert.AreEqual(TRdxMagicFixes.FileReason(U, lfFormatInvariant),
      O.Reason);
    Assert.IsTrue(Pos('TFormatSettings.Invariant', O.Reason) > 0, O.Reason);
    // Gegenprobe: ohne die alte Projektdatei bieten beide an.
    DeleteFile(Dof);
    O := PlanFixIn(Src, U, fkDateFormatSettings, Seen[0]);
    Assert.IsTrue(O.Enabled, O.Reason);
    O := PlanAltFixIn(Src, U, fkDateFormatSettings, Seen[0]);
    Assert.IsTrue(O.Enabled, O.Reason);
  finally
    RemoveTree(Root);
  end;
end;

procedure TTestRdxFormatSettingsFixDetector.Sca128_Detector_LazarusProject_OnlyMainWay;
var
  Root, U, Src : string;
  Seen         : TArray<TSeen>;
  O            : TRdxFixOutcome;
begin
  // rwE29, martin-doyle\10-InvoiceExample\src\rgReportPayments.pas:210 (und
  // rgInvoiceItemEdit.pas:217): die Unit steht in Rechnung.lpi im selben
  // Verzeichnis und baut mit FPC 3.2 - dort gibt es kein
  // TFormatSettings.Invariant. Der Alt-Weg sperrt (ohne den Plattenblick
  // boete er an: die Unit traegt keine FPC-Weiche); der Hauptweg bleibt -
  // FPC kennt die globale FormatSettings (FpcKnows).
  Src := InUnit(['  r := FloatToStr(x);']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  Root := NewTempDir(FILE_PREFIX);
  try
    U := Root + 'rgReportPayments.pas';
    WriteText(Root + 'Rechnung.lpi', '<CONFIG/>');
    O := PlanAltFixIn(Src, U, fkDateFormatSettings, Seen[0]);
    Assert.IsFalse(O.Enabled, 'Alt-Weg gesperrt');
    Assert.AreEqual(TRdxMagicFixes.FileReason(U, lfFormatInvariant),
      O.Reason);
    Assert.IsTrue(Pos('Rechnung.lpi', O.Reason) > 0, O.Reason);
    O := PlanFixIn(Src, U, fkDateFormatSettings, Seen[0]);
    Assert.IsTrue(O.Enabled, O.Reason);
    Assert.AreEqual(InUnit(['  r := FloatToStr(x, FormatSettings);']),
      Apply(Src, O.Edits));
  finally
    RemoveTree(Root);
  end;
end;

procedure TTestRdxFormatSettingsFixDetector.Sca128_Detector_OldTraceOnlyInInclude_MainWayStays;
var
  Root, U, Src : string;
  Seen         : TArray<TSeen>;
  O            : TRdxFixOutcome;
begin
  // Entscheid M1 (Review e/HilfeFixC): der Hauptweg fragt die Includes
  // nicht - eine alte Versionsweiche in einem Include ('{$IFDEF VER150}',
  // wie jedi.inc & Co.) und ein nicht gefundenes Include sperren ihn nicht
  // (mit der Include-Pruefung fiel er hier weg). Der Invariant-Weg bleibt
  // streng. Gegenprobe: eine alte Projektdatei (Delphi 7, .dof) daneben
  // sperrt auch den Hauptweg.
  Src := UnitText('SysUtils', ['{$I defs.inc}', '{$I fehlt.inc}'],
    ['  r := DateTimeToStr(d);']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  Root := NewTempDir(FILE_PREFIX);
  try
    U := Root + 'u.pas';
    WriteText(Root + 'defs.inc', '{$IFDEF VER150}' + CRLF + '  {$DEFINE D7}'
      + CRLF + '{$ENDIF}');
    O := PlanFixIn(Src, U, fkDateFormatSettings, Seen[0]);
    Assert.IsTrue(O.Enabled, O.Reason);
    Assert.IsTrue(Pos('DateTimeToStr(d, FormatSettings)', Apply(Src, O.Edits))
      > 0, 'Hauptweg angewendet');
    O := PlanAltFixIn(Src, U, fkDateFormatSettings, Seen[0]);
    Assert.IsFalse(O.Enabled, 'Invariant-Weg gesperrt (Include)');
    Assert.IsTrue(O.Reason <> '', 'mit Grund');
    WriteText(Root + 'Prj.dof', '[Compiler]');
    O := PlanFixIn(Src, U, fkDateFormatSettings, Seen[0]);
    Assert.IsFalse(O.Enabled, 'Hauptweg gesperrt (.dof)');
    Assert.AreEqual(TRdxMagicFixes.FileReason(U, lfFormatSettingsVar),
      O.Reason);
    Assert.IsTrue(Pos('Prj.dof', O.Reason) > 0, O.Reason);
  finally
    RemoveTree(Root);
  end;
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxFormatSettingsFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxFormatSettingsFixDetector);
  {$ENDIF}

end.
