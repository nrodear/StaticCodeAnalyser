unit uTestRdxFormatSettingsFix;

// Editorhilfe SCA128 DateFormatSettings (uRdxFormatSettingsFix): an jeden
// Aufruf der Detektor-Liste auf der Fundzeile ', FormatSettings' (Hauptweg)
// bzw. ', TFormatSettings.Invariant' (Alt-Weg) anhaengen. Die Faelle auf Text
// rufen die Planer direkt auf einer TRdxCodeMap; die Rundlaeufe mit dem
// ECHTEN Detektor (TDateFormatSettingsDetector) laufen ueber den Einstieg
// der Tabelle (TRdxFixTable.FixFor bzw. AlternativeFixFor, Adapter
// PlanDateFormatSettings/PlanDateFormatSettingsAlt) und stehen in einer
// eigenen Fixture hinter {$IFNDEF FPC} - die Text-Fixture bleibt
// FPC-tauglich. Im FPC-Pruefstand steht die Unit nicht
// (uRdxFormatSettingsFix fehlt in der Unit-Liste von build.sh).
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
    [Test] procedure Sca128_CallOnFollowingLine_NoHelp;
    [Test] procedure Sca128_StatementContinues_NoHelp;
    [Test] procedure Sca128_QualifiedOrNoCall_NoHelp;
    [Test] procedure Sca128_OtherArity_NoHelp;
    [Test] procedure Sca128_Directive_NoHelp;
    [Test] procedure Sca128_NoSysUtilsOrOwnRoutine_NoHelp;
    [Test] procedure Sca128_FormatSettingsDeclared_OnlyAlt;
    [Test] procedure Sca128_With_NoHelp;
    [Test] procedure Sca128_OldCompiler_Blocks;
    [Test] procedure Sca128_Alt_FpcOrOwnType_NoHelp;
    // ---- Realworld-Test rwE29: Literal gegen Invariant ----
    [Test] procedure Sca128_Alt_LiteralNotInvariant_NoHelp;
    [Test] procedure Sca128_Alt_LiteralInvariant_Helps;
    // ---- Realworld-Test rwE29: Paar-Bruch ----
    [Test] procedure Sca128_Alt_PairInFile_NoHelp;
    [Test] procedure Sca128_Alt_NoPairInFile_Helps;
  end;

{$IFNDEF FPC}
  // Rundlaeufe mit dem ECHTEN Detektor (nur Delphi).
  [TestFixture]
  TTestRdxFormatSettingsFixDetector = class
  public
    [Test] procedure Sca128_Detector_CatalogExample;
    [Test] procedure Sca128_Detector_RoundTrip;
    [Test] procedure Sca128_Detector_RoundTripAlt;
    [Test] procedure Sca128_Detector_ContinuedStatement_NoHelp;
    // ---- Realworld-Test rwE29: was nur die Platte weiss ----
    [Test] procedure Sca128_Detector_OldDelphiProject_NoHelp;
    [Test] procedure Sca128_Detector_LazarusProject_OnlyMainWay;
    [Test] procedure Sca128_Detector_PairInFile_OnlyMainWay;
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

procedure TTestRdxFormatSettingsFix.Sca128_CallOnFollowingLine_NoHelp;
begin
  AssertRefused(InUnit(['  r :=', '    DateToStr(d);']), BODY_LINE,
    Msg('datetostr'), _(R_FS_NEXT_LINE, [BODY_LINE + 1]));
end;

procedure TTestRdxFormatSettingsFix.Sca128_StatementContinues_NoHelp;
begin
  // Der zweite Aufruf bliebe ungeaendert, und der Detektor schwiege.
  AssertRefused(InUnit(['  r := DateToStr(d) + '' '' +', '    TimeToStr(d);']),
    BODY_LINE, Msg('datetostr'), _(R_FS_CONTINUES, [BODY_LINE + 1]));
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
  // Die Klammer schliesst erst auf der Folgezeile.
  AssertRefused(InUnit(['  r := DateToStr(', '    d);']), BODY_LINE,
    Msg('datetostr'), _(R_FS_OPEN, ['DateToStr']));
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

procedure TTestRdxFormatSettingsFix.Sca128_FormatSettingsDeclared_OnlyAlt;
var
  Src : string;
begin
  // Ein Parameter FormatSettings irgendwo in der Datei: der blosse Name
  // bande dort - der Hauptweg sperrt, der Alt-Weg nennt den Namen nicht.
  Src := UnitText(RTL_USES,
    ['procedure Q(const FormatSettings: TFormatSettings); begin end;'],
    ['  r := DateToStr(d);']);
  AssertRefused(Src, BODY_LINE + 1, Msg('datetostr'), _(R_FS_SHADOW, [6]));
  AssertFixed(UnitText(RTL_USES,
    ['procedure Q(const FormatSettings: TFormatSettings); begin end;'],
    ['  r := DateToStr(d, TFormatSettings.Invariant);']), Src, BODY_LINE + 1,
    Msg('datetostr'), True);
  // In einer Liste und als Feld.
  AssertRefused(UnitText(RTL_USES,
    ['type TFoo = class A, FormatSettings: TFormatSettings; end;'],
    ['  r := DateToStr(d);']), BODY_LINE + 1, Msg('datetostr'),
    _(R_FS_SHADOW, [6]));
  // Als Member (eines fremden Typs).
  AssertRefused(InUnit(['  Writer.FormatSettings.DecimalSeparator := ''.'';',
    '  r := DateToStr(d);']), BODY_LINE + 1, Msg('datetostr'),
    _(R_FS_MEMBER, [BODY_LINE]));
  // SysUtils.FormatSettings ist die RTL - kein Member.
  AssertFixed(InUnit(['  SysUtils.FormatSettings.DecimalSeparator := ''.'';',
    '  r := DateToStr(d, FormatSettings);']),
    InUnit(['  SysUtils.FormatSettings.DecimalSeparator := ''.'';',
    '  r := DateToStr(d);']), BODY_LINE + 1, Msg('datetostr'));
end;

procedure TTestRdxFormatSettingsFix.Sca128_With_NoHelp;
var
  Src : string;
begin
  Src := InUnit(['  with Obj do', '    r := DateToStr(d);']);
  AssertRefused(Src, BODY_LINE + 1, Msg('datetostr'), _(R_FS_WITH, [BODY_LINE]));
  AssertRefused(Src, BODY_LINE + 1, Msg('datetostr'), _(R_FS_WITH, [BODY_LINE]),
    True);
  // Ein with in einer ANDEREN Routine davor stoert nicht.
  AssertFixed(UnitText(RTL_USES,
    ['procedure Q; begin with Obj do Foo; end;'],
    ['  r := DateToStr(d, FormatSettings);']),
    UnitText(RTL_USES, ['procedure Q; begin with Obj do Foo; end;'],
    ['  r := DateToStr(d);']), BODY_LINE + 1, Msg('datetostr'));
end;

procedure TTestRdxFormatSettingsFix.Sca128_OldCompiler_Blocks;
var
  Src : string;
begin
  // Delphi 2010 kennt die globale FormatSettings nicht: beide Wege sperren.
  Src := InUnit(['  r := DateToStr(d);', '  {$IFDEF VER210} Foo; {$ENDIF}']);
  AssertRefused(Src, BODY_LINE, Msg('datetostr'),
    _(R_FS_OLD_VAR, ['VER210', BODY_LINE + 1]));
  AssertRefused(Src, BODY_LINE, Msg('datetostr'),
    _(R_FS_OLD_INVARIANT, ['VER210', BODY_LINE + 1]), True);
  // Delphi XE: der Hauptweg geht, Invariant erst ab 10.3 geprueft.
  Src := InUnit(['  r := DateToStr(d);', '  {$IFDEF VER220} Foo; {$ENDIF}']);
  AssertFixed(InUnit(['  r := DateToStr(d, FormatSettings);',
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
  // Uhrzeit ohne Minuten, Zahl mit Komma bzw. Tausendertrenner.
  AssertRefused(InUnit(['  d := StrToTime(''16 Uhr'');']), BODY_LINE,
    Msg('strtotime'), _(R_FS_LIT_DATE, ['''16 Uhr''', 'StrToTime']), True);
  AssertRefused(InUnit(['  x := StrToFloat(''1,5'');']), BODY_LINE,
    Msg('strtofloat'), _(R_FS_LIT_NUMBER, ['''1,5''', 'StrToFloat']), True);
  AssertRefused(InUnit(['  x := StrToCurr(''1.234,50'');']), BODY_LINE,
    Msg('strtocurr'), _(R_FS_LIT_NUMBER, ['''1.234,50''', 'StrToCurr']),
    True);
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

procedure TTestRdxFormatSettingsFix.Sca128_Alt_PairInFile_NoHelp;
var
  Src : string;
begin
  // rwE29, HeidiSQL main.pas:14718: 'QueryDay := DateToStr(..)' wird mit
  // Eintraegen verglichen, die eine andere Zeile mit DateToStr (Locale)
  // schreibt - nur diese Seite auf Invariant, und der Vergleich ist ausser
  // in en-US immer ungleich. Ohne die Sperre boete der Alt-Weg an.
  Src := InUnit(['  r := DateToStr(d);', '  if r <> DateToStr(Date) then',
    '    r := '''';']);
  AssertRefused(Src, BODY_LINE, Msg('datetostr'),
    _(R_FS_PAIR, [BODY_LINE + 1, 'DateToStr', MsgByHand]), True);
  // Der Hauptweg bleibt (gleiche Bedeutung).
  AssertFixed(InUnit(['  r := DateToStr(d, FormatSettings);',
    '  if r <> DateToStr(Date) then', '    r := '''';']), Src, BODY_LINE,
    Msg('datetostr'));
  // rwE29, rgInvoiceItemEdit.pas:217: CurrToStr ins Eingabefeld, zurueck
  // mit TryStrToCurr (ohne eigenen Fund) - dieselbe Zahlen-Familie.
  Src := InUnit(['  r := CurrToStr(x);', '  if TryStrToCurr(s, x) then',
    '    r := '''';']);
  AssertRefused(Src, BODY_LINE, Msg('currtostr'),
    _(R_FS_PAIR, [BODY_LINE + 1, 'TryStrToCurr', MsgByHand]), True);
  // rwE29, wbDefinitionsCommon.pas:996/997: zwei StrToFloat, verglichen;
  // auch ein Aufruf mit der globalen FormatSettings ist kein Invariant.
  Src := InUnit(['  x := StrToFloat(s);',
    '  if x = StrToFloat(r, FormatSettings) then', '    r := '''';']);
  AssertRefused(Src, BODY_LINE, Msg('strtofloat'),
    _(R_FS_PAIR, [BODY_LINE + 1, 'StrToFloat', MsgByHand]), True);
end;

procedure TTestRdxFormatSettingsFix.Sca128_Alt_NoPairInFile_Helps;
begin
  // Gegenprobe: eine andere Familie, ein Aufruf derselben Familie, der
  // schon Invariant uebergibt (auch ueber zwei Zeilen), ein Member gleichen
  // Namens (eine andere Routine) und ein Kommentar sperren nicht.
  AssertFixed(InUnit(['  r := DateToStr(d, TFormatSettings.Invariant);',
    '  x := StrToFloat(s);',
    '  d := StrToDate(r,', '    TFormatSettings.Invariant);',
    '  r := Fmt.DateToStr(d);', '  // DateToStr(d)']),
    InUnit(['  r := DateToStr(d);', '  x := StrToFloat(s);',
    '  d := StrToDate(r,', '    TFormatSettings.Invariant);',
    '  r := Fmt.DateToStr(d);', '  // DateToStr(d)']), BODY_LINE,
    Msg('datetostr'), True);
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
  // Je Familie EIN Aufruf: seit dem Realworld-Test rwE29 sperrt der
  // Alt-Weg, solange die Datei einen weiteren derselben Familie ohne
  // Invariant ruft (Paar-Bruch) - bis dahin stand hier dazu
  // 'r := FormatCurr(''0.00'', x);', das jetzt StrToCurr sperrt (und
  // umgekehrt; Sca128_Detector_PairInFile_OnlyMainWay).
  Assert.AreEqual(InUnit([
    '  r := DateTimeToStr(d, TFormatSettings.Invariant);',
    '  x := StrToCurr(s, TFormatSettings.Invariant);']),
    FixAll(InUnit([
    '  r := DateTimeToStr(d);',
    '  x := StrToCurr(s);']), True));
end;

procedure TTestRdxFormatSettingsFixDetector.Sca128_Detector_PairInFile_OnlyMainWay;
var
  Src  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  // Der echte Detektor meldet beide Zeilen; der Alt-Weg sperrt je die eine
  // mit Blick auf die andere, der Hauptweg behebt beide.
  Src := InUnit(['  x := StrToCurr(s);', '  r := FormatCurr(''0.00'', x);']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(2, Length(Seen), 'zwei Funde');
  if Seen[0].Line <> BODY_LINE then
    Seen[0] := Seen[1];
  Assert.AreEqual<Integer>(BODY_LINE, Seen[0].Line, 'Fund der StrToCurr-Zeile');
  O := TablePlan(Src, Seen[0], True);
  Assert.IsFalse(O.Enabled, 'Alt-Weg gesperrt');
  Assert.AreEqual(_(R_FS_PAIR, [BODY_LINE + 1, 'FormatCurr', MsgByHand]),
    O.Reason);
  Assert.AreEqual(InUnit(['  x := StrToCurr(s, FormatSettings);',
    '  r := FormatCurr(''0.00'', x, FormatSettings);']), FixAll(Src, False));
end;

procedure TTestRdxFormatSettingsFixDetector.Sca128_Detector_ContinuedStatement_NoHelp;
var
  Src  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  Src := InUnit(['  r := DateToStr(d) + '' '' +', '    TimeToStr(d);']);
  Seen := Detect(Src);
  Assert.IsTrue(Length(Seen) >= 1, 'der Detektor meldet die Anweisung');
  Assert.AreEqual<Integer>(BODY_LINE, Seen[0].Line, 'Zeile der Anweisung');
  O := TablePlan(Src, Seen[0], False);
  Assert.IsFalse(O.Enabled);
  Assert.AreEqual(_(R_FS_CONTINUES, [BODY_LINE + 1]), O.Reason);
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
  // boeten beide Eintraege an (Gegenprobe unten: ohne .dof).
  Src := InUnit(['  r := DateTimeToStr(d);']);
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

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxFormatSettingsFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxFormatSettingsFixDetector);
  {$ENDIF}

end.
