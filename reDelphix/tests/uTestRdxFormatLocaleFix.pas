unit uTestRdxFormatLocaleFix;

// Editorhilfe SCA059 FormatLocaleHint (uRdxFormatSettingsFix): an das eine
// Format der Fundzeile das dritte Argument ', FormatSettings' (Hauptweg) bzw.
// ', TFormatSettings.Invariant' (Alt-Weg) anhaengen. Die Faelle auf Text rufen
// die Planer direkt auf einer TRdxCodeMap; die Rundlaeufe mit dem ECHTEN
// Detektor (TFormatMismatchDetector) laufen ueber den Einstieg der Tabelle
// (TRdxFixTable.FixFor bzw. AlternativeFixFor, Adapter PlanFormatLocale/
// PlanFormatLocaleAlt) und stehen in einer eigenen Fixture hinter
// {$IFNDEF FPC}. Der Pruefstand-Runner nimmt nur eine Fixture je Unit - die
// Weiche ist heute ohne Wirkung (wie uTestRdxCategoryArgFix).
// Prueft: Hilfe mit Literal, Konstante, Verkettung, verdoppeltem Quote,
// RTL-Qualifizierung, der Bereich, der Alt-Weg samt Waehrungs-Spec; die
// Sperren - anderer Formatstring, verschoben, zwei Format, qualifiziert,
// Argumentzahl, offene Klammer, Folgezeile, Anweisung geht weiter,
// Direktive, Fragen an die Datei, FPC und alte Compiler, Meldung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxFormatLocaleFix = class
  public
    // ---- Hilfe ----
    [Test] procedure Sca059_Literal_AppendsThirdArgument;
    [Test] procedure Sca059_ConstantFormat_Helps;
    [Test] procedure Sca059_ConcatAndQuote_ReadLikeDetector;
    [Test] procedure Sca059_RtlQualified_Helps;
    [Test] procedure Sca059_Edit_StartsBehindArray;
    [Test] procedure Sca059_Alt_AppendsInvariant;
    [Test] procedure Sca059_Alt_MoneySpec_OnlyMain;
    [Test] procedure Sca059_MessageAndMoneySpec_Read;
    // ---- keine Hilfe ----
    [Test] procedure Sca059_OtherFormatString_NoHelp;
    [Test] procedure Sca059_Moved_NoHelp;
    [Test] procedure Sca059_TwoFormats_NoHelp;
    [Test] procedure Sca059_QualifiedOrArity_NoHelp;
    [Test] procedure Sca059_OpenOrFollowingLine_NoHelp;
    [Test] procedure Sca059_Directive_NoHelp;
    [Test] procedure Sca059_FileChecks_NoHelp;
    [Test] procedure Sca059_Alt_FpcOrOldCompiler_NoHelp;
  end;

{$IFNDEF FPC}
  // Rundlaeufe mit dem ECHTEN Detektor (nur Delphi).
  [TestFixture]
  TTestRdxFormatLocaleFixDetector = class
  public
    [Test] procedure Sca059_Detector_CatalogExample;
    [Test] procedure Sca059_Detector_RoundTrip;
    [Test] procedure Sca059_Detector_TwoFormatsOnLine_NoHelp;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uFormatMismatch,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uRdxFixTable,          // TRdxFixTable.FixFor, AlternativeFixFor
  uTestRdxDetectorKit,   // TSeen, DetectSource, CatalogText
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
  Result := Result + 'procedure P(x: Double);' + CRLF + 'var' + CRLF
    + '  r: string;' + CRLF + 'begin' + CRLF;
  for S in ABody do
    Result := Result + S + CRLF;
  Result := Result + 'end;' + CRLF + 'end.';
end;

function InUnit(const ABody: array of string): string;
begin
  Result := UnitText(RTL_USES, [], ABody);
end;

// Die Meldung des Detektors zum Formatstring AFormat.
function Msg(const AFormat: string): string;
begin
  Result := 'Format: float spec ' + AFormat + ' without TFormatSettings - '
    + 'locale-dependent (comma vs. dot decimal separator)';
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
      Result := TRdxFormatSettingsFix.FormatLocaleInvariant(Map, ALine,
        AMessage, AEdit, AReason)
    else
      Result := TRdxFormatSettingsFix.FormatLocale(Map, ALine, AMessage,
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

// ---- Hilfe ----

procedure TTestRdxFormatLocaleFix.Sca059_Literal_AppendsThirdArgument;
begin
  AssertFixed(InUnit(['  r := Format(''%.2f'', [x], FormatSettings);']),
    InUnit(['  r := Format(''%.2f'', [x]);']), BODY_LINE, Msg('%.2f'));
  // Kommas im Literal und im Array zaehlen nicht; als Argument, mit Kommentar.
  AssertFixed(
    InUnit(['  LogIt(Format(''Sum: %8.3f, total'', [x, 1], FormatSettings)); // x']),
    InUnit(['  LogIt(Format(''Sum: %8.3f, total'', [x, 1])); // x']), BODY_LINE,
    Msg('Sum: %8.3f, total'));
end;

procedure TTestRdxFormatLocaleFix.Sca059_ConstantFormat_Helps;
begin
  // Die Meldung nennt den Wert der Konstanten - ohne Literal keine Gegenprobe.
  AssertFixed(InUnit(['  r := Format(FMT_PRICE, [x], FormatSettings);']),
    InUnit(['  r := Format(FMT_PRICE, [x]);']), BODY_LINE, Msg('%.2f'));
  // Ein Open-Array als Variable.
  AssertFixed(InUnit(['  r := Format(''%g'', Args, FormatSettings);']),
    InUnit(['  r := Format(''%g'', Args);']), BODY_LINE, Msg('%g'));
end;

procedure TTestRdxFormatLocaleFix.Sca059_ConcatAndQuote_ReadLikeDetector;
begin
  // Der Detektor fuegt verkettete Literale zusammen und liest '' als Quote.
  AssertFixed(InUnit(['  r := Format(''a '' + ''%.2f'', [x], FormatSettings);']),
    InUnit(['  r := Format(''a '' + ''%.2f'', [x]);']), BODY_LINE,
    Msg('a %.2f'));
  AssertFixed(InUnit(['  r := Format(''it''''s %.1f'', [x], FormatSettings);']),
    InUnit(['  r := Format(''it''''s %.1f'', [x]);']), BODY_LINE,
    Msg('it''s %.1f'));
end;

procedure TTestRdxFormatLocaleFix.Sca059_RtlQualified_Helps;
begin
  AssertFixed(InUnit(['  r := SysUtils.Format(''%.2f'', [x], FormatSettings);']),
    InUnit(['  r := SysUtils.Format(''%.2f'', [x]);']), BODY_LINE, Msg('%.2f'));
  AssertFixed(
    InUnit(['  r := System.SysUtils.Format(''%.2f'', [x], FormatSettings);']),
    InUnit(['  r := System.SysUtils.Format(''%.2f'', [x]);']), BODY_LINE,
    Msg('%.2f'));
end;

procedure TTestRdxFormatLocaleFix.Sca059_Edit_StartsBehindArray;
var
  E : TRdxEdit;
  R : string;
begin
  // '  r := Format('%.2f', [x]);' - ']' in Spalte 25, ')' in 26.
  Assert.IsTrue(PlanOn(InUnit(['  r := Format(''%.2f'', [x]);']), BODY_LINE,
    Msg('%.2f'), False, E, R), R);
  Assert.AreEqual<Integer>(BODY_LINE, E.Span.StartLine);
  Assert.AreEqual<Integer>(26, E.Span.StartCol);
  Assert.AreEqual<Integer>(BODY_LINE, E.Span.EndLine);
  Assert.AreEqual<Integer>(27, E.Span.EndCol);
  Assert.AreEqual(')', E.Expected);
  Assert.AreEqual(', FormatSettings)', E.NewText);
  // Leerraum vor der Klammer bleibt dahinter.
  Assert.IsTrue(PlanOn(InUnit(['  r := Format(''%.2f'', [x] );']), BODY_LINE,
    Msg('%.2f'), True, E, R), R);
  Assert.AreEqual(' )', E.Expected);
  Assert.AreEqual(', TFormatSettings.Invariant )', E.NewText);
end;

procedure TTestRdxFormatLocaleFix.Sca059_Alt_AppendsInvariant;
begin
  AssertFixed(
    InUnit(['  r := Format(''%.2f'', [x], TFormatSettings.Invariant);']),
    InUnit(['  r := Format(''%.2f'', [x]);']), BODY_LINE, Msg('%.2f'), True);
  // Ein FormatSettings-Parameter der Datei stoert den Alt-Weg nicht.
  AssertFixed(UnitText(RTL_USES,
    ['procedure Q(const FormatSettings: TFormatSettings); begin end;'],
    ['  r := Format(''%e'', [x], TFormatSettings.Invariant);']),
    UnitText(RTL_USES,
    ['procedure Q(const FormatSettings: TFormatSettings); begin end;'],
    ['  r := Format(''%e'', [x]);']), BODY_LINE + 1, Msg('%e'), True);
end;

procedure TTestRdxFormatLocaleFix.Sca059_Alt_MoneySpec_OnlyMain;
var
  Src : string;
begin
  // Invariant schreibt das allgemeine Waehrungszeichen statt des lokalen.
  Src := InUnit(['  r := Format(''%.2m'', [x]);']);
  AssertFixed(InUnit(['  r := Format(''%.2m'', [x], FormatSettings);']), Src,
    BODY_LINE, Msg('%.2m'));
  AssertRefused(Src, BODY_LINE, Msg('%.2m'), _(R_FL_MONEY), True);
  // Auch ueber eine Konstante (die Meldung nennt den Wert).
  AssertRefused(InUnit(['  r := Format(FMT_COST, [x]);']), BODY_LINE,
    Msg('%m net'), _(R_FL_MONEY), True);
end;

procedure TTestRdxFormatLocaleFix.Sca059_MessageAndMoneySpec_Read;
var
  F : string;
begin
  Assert.IsTrue(TRdxFormatSettingsFix.FloatSpecOf(Msg('%.2f EUR'), F));
  Assert.AreEqual('%.2f EUR', F);
  // Ein Formatstring mit ' - ' darin bleibt ganz.
  Assert.IsTrue(TRdxFormatSettingsFix.FloatSpecOf(Msg('a - %f'), F));
  Assert.AreEqual('a - %f', F);
  Assert.IsFalse(TRdxFormatSettingsFix.FloatSpecOf('Format: 2 placeholders, '
    + '1 arguments', F));
  Assert.IsFalse(TRdxFormatSettingsFix.FloatSpecOf(Msg(''), F));
  Assert.IsTrue(TRdxFormatSettingsFix.HasMoneySpec('%m'));
  Assert.IsTrue(TRdxFormatSettingsFix.HasMoneySpec('x %.2M y'));
  Assert.IsTrue(TRdxFormatSettingsFix.HasMoneySpec('%0:m'));
  Assert.IsFalse(TRdxFormatSettingsFix.HasMoneySpec('%%m %.2f'));
  Assert.IsFalse(TRdxFormatSettingsFix.HasMoneySpec('%s mm'));
  AssertRefused(InUnit(['  r := Format(''%.2f'', [x]);']), BODY_LINE,
    'etwas anderes', _(R_FL_NO_SPEC));
end;

// ---- keine Hilfe ----

procedure TTestRdxFormatLocaleFix.Sca059_OtherFormatString_NoHelp;
begin
  // Die Zeile traegt ein anderes Literal als der Fund nennt.
  AssertRefused(InUnit(['  r := Format(''%.2f'', [x]);']), BODY_LINE,
    Msg('%.3f'), MsgMovedSuffix(_(R_FL_OTHER_FMT)));
  AssertRefused(InUnit(['  r := Format(''a '' + ''%.2f'', [x]);']), BODY_LINE,
    Msg('%.2f'), MsgMovedSuffix(_(R_FL_OTHER_FMT)), True);
end;

procedure TTestRdxFormatLocaleFix.Sca059_Moved_NoHelp;
var
  Moved : string;
begin
  Moved := MsgMovedSuffix(_(R_FL_NO_FORMAT));
  AssertRefused(InUnit(['  r := Format(''%.2f'', [x]);']), BODY_LINE - 1,
    Msg('%.2f'), Moved);
  AssertRefused(InUnit(['  // r := Format(''%.2f'', [x]);']), BODY_LINE,
    Msg('%.2f'), Moved);
  AssertRefused(InUnit(['  r := ''Format(''''%.2f'''', [x])'';']), BODY_LINE,
    Msg('%.2f'), Moved, True);
  // mORMot-Funktionen loesen den Detektor auch aus - keine RTL-Format.
  AssertRefused(InUnit(['  r := FormatUtf8(''%f'', [x]);']), BODY_LINE,
    Msg('%f'), Moved);
end;

procedure TTestRdxFormatLocaleFix.Sca059_TwoFormats_NoHelp;
begin
  AssertRefused(
    InUnit(['  r := Format(''%.1f'', [x]) + Format(''%.2f'', [x]);']),
    BODY_LINE, Msg('%.1f'), _(R_FL_MANY, [BODY_LINE, 2]));
  // Verschachtelt ebenso.
  AssertRefused(InUnit(['  r := Format(''%s'', [Format(''%.2f'', [x])]);']),
    BODY_LINE, Msg('%.2f'), _(R_FL_MANY, [BODY_LINE, 2]), True);
end;

procedure TTestRdxFormatLocaleFix.Sca059_QualifiedOrArity_NoHelp;
begin
  AssertRefused(InUnit(['  r := string.Format(''%.2f'', [x]);']), BODY_LINE,
    Msg('%.2f'), _(R_FS_QUALIFIED, ['Format', 'string.Format']));
  AssertRefused(InUnit(['  r := Self.Format(''%.2f'', [x]);']), BODY_LINE,
    Msg('%.2f'), _(R_FS_QUALIFIED, ['Format', 'Self.Format']), True);
  // Schon ein drittes Argument bzw. nur eines.
  AssertRefused(InUnit(['  r := Format(''%.2f'', [x], FS);']), BODY_LINE,
    Msg('%.2f'), _(R_FS_ARITY, ['Format', 3, 2]));
  AssertRefused(InUnit(['  r := Format(''%.2f'');']), BODY_LINE,
    Msg('%.2f'), _(R_FS_ARITY, ['Format', 1, 2]));
  AssertRefused(InUnit(['  F := Format;']), BODY_LINE, Msg('%.2f'),
    _(R_FS_NOT_CALL, ['Format']));
end;

procedure TTestRdxFormatLocaleFix.Sca059_OpenOrFollowingLine_NoHelp;
begin
  AssertRefused(InUnit(['  r := Format(''%.2f'',', '    [x]);']), BODY_LINE,
    Msg('%.2f'), _(R_FS_OPEN, ['Format']));
  AssertRefused(InUnit(['  r :=', '    Format(''%.2f'', [x]);']), BODY_LINE,
    Msg('%.2f'), _(R_FS_NEXT_LINE, [BODY_LINE + 1]));
  AssertRefused(InUnit(['  r := Format(''%.2f'', [x]) +',
    '    Format(''%.3f'', [x]);']), BODY_LINE, Msg('%.2f'),
    _(R_FS_CONTINUES, [BODY_LINE + 1]));
end;

procedure TTestRdxFormatLocaleFix.Sca059_Directive_NoHelp;
begin
  AssertRefused(InUnit(['  r := Format({$IFDEF X}''%.2f''{$ELSE}''%.3f''{$ENDIF}, [x]);']),
    BODY_LINE, Msg('%.2f'), _(R_FS_DIRECTIVE));
end;

procedure TTestRdxFormatLocaleFix.Sca059_FileChecks_NoHelp;
begin
  AssertRefused(UnitText('', [], ['  r := Format(''%.2f'', [x]);']), BODY_LINE,
    Msg('%.2f'), _(R_FS_NO_SYSUTILS));
  AssertRefused(UnitText(RTL_USES,
    ['function Format(const F: string; const A: array of const): string; forward;'],
    ['  r := Format(''%.2f'', [x]);']), BODY_LINE + 1, Msg('%.2f'),
    _(R_FS_OWN_ROUTINE, ['Format']), True);
  AssertRefused(UnitText(RTL_USES,
    ['var', '  FormatSettings: TFormatSettings;'],
    ['  r := Format(''%.2f'', [x]);']), BODY_LINE + 2, Msg('%.2f'),
    _(R_FS_SHADOW, [7]));
  AssertRefused(InUnit(['  with Obj do r := Format(''%.2f'', [x]);']),
    BODY_LINE, Msg('%.2f'), _(R_FS_WITH, [BODY_LINE]));
end;

procedure TTestRdxFormatLocaleFix.Sca059_Alt_FpcOrOldCompiler_NoHelp;
var
  Src : string;
begin
  Src := InUnit(['  r := Format(''%.2f'', [x]);', '  {$IFDEF FPC} Foo; {$ENDIF}']);
  AssertFixed(InUnit(['  r := Format(''%.2f'', [x], FormatSettings);',
    '  {$IFDEF FPC} Foo; {$ENDIF}']), Src, BODY_LINE, Msg('%.2f'));
  AssertRefused(Src, BODY_LINE, Msg('%.2f'), _(R_FS_FPC, [BODY_LINE + 1]), True);
  // Delphi 10.2 Tokyo: der Hauptweg geht, Invariant ist erst ab 10.3 belegt.
  Src := InUnit(['  r := Format(''%.2f'', [x]);',
    '  {$IF CompilerVersion >= 32} Foo; {$IFEND}']);
  AssertFixed(InUnit(['  r := Format(''%.2f'', [x], FormatSettings);',
    '  {$IF CompilerVersion >= 32} Foo; {$IFEND}']), Src, BODY_LINE,
    Msg('%.2f'));
  AssertRefused(Src, BODY_LINE, Msg('%.2f'),
    _(R_FS_OLD_INVARIANT, ['COMPILERVERSION >= 32', BODY_LINE + 1]), True);
  // Delphi 2009 kennt die globale FormatSettings nicht.
  AssertRefused(InUnit(['  r := Format(''%.2f'', [x]);',
    '  {$IFDEF DELPHI2009_UP} Foo; {$ENDIF}']), BODY_LINE, Msg('%.2f'),
    _(R_FS_OLD_VAR, ['DELPHI2009_UP', BODY_LINE + 1]));
end;

{$IFNDEF FPC}

// ---- echter Detektor ----

const
  FILE_PREFIX = 'rdx_fmtloc_';

procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TFormatMismatchDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource(FILE_PREFIX, ASource, fkFormatLocaleHint,
    RunDetector);
end;

// Die Hilfe fuer einen Fund ueber den Einstieg der Tabelle (AAlt: der
// zweite Eintrag) - wie der Anbieter, ohne Quellstellen-Dienst (der Adapter
// liest nur den Text).
function TablePlan(const ASource: string; const ASeen: TSeen;
  AAlt: Boolean): TRdxFixOutcome;
var
  SL : TStringList;
  F  : TLeakFinding;
begin
  SL := TStringList.Create;
  F := TLeakFinding.New('t.pas', '', ASeen.Line, ASeen.Msg,
    fkFormatLocaleHint);
  try
    SL.Text := ASource;
    if AAlt then
      Result := TRdxFixTable.AlternativeFixFor(nil, SL, F, nil)
    else
      Result := TRdxFixTable.FixFor(nil, SL, F, nil);
  finally
    F.Free;
    SL.Free;
  end;
end;

// Fund fuer Fund ueber die Tabelle beheben, bis der Detektor schweigt.
function FixAll(const ASource: string; AAlt: Boolean): string;
const
  MAX_PASSES = 10;
var
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
  Pass : Integer;
begin
  Result := ASource;
  for Pass := 1 to MAX_PASSES do
  begin
    Seen := Detect(Result);
    if Length(Seen) = 0 then Exit;
    O := TablePlan(Result, Seen[0], AAlt);
    Assert.IsTrue(O.Enabled, Format('Zeile %d: %s', [Seen[0].Line, O.Reason]));
    Result := Apply(Result, O.Edits);
  end;
  Assert.Fail('der Detektor meldet nach 10 Runden noch');
end;

// Das Katalog-Beispiel als Rumpf von P (Zeilenenden CRLF).
function CatalogBody(const AExample: string): string;
begin
  Result := InUnit(['  ' + StringReplace(CatalogText(AExample), CRLF,
    CRLF + '  ', [rfReplaceAll])]);
end;

procedure TTestRdxFormatLocaleFixDetector.Sca059_Detector_CatalogExample;
var
  Meta : TRuleMeta;
  Bad  : string;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkFormatLocaleHint);
  Bad := CatalogBody(Meta.BadExample);
  Assert.AreEqual<Integer>(1, Length(Detect(Bad)),
    'der Detektor meldet das Beispiel');
  // Der Alt-Weg schreibt genau das gute Beispiel.
  Assert.AreEqual(CatalogBody(Meta.GoodExample), FixAll(Bad, True));
  Assert.AreEqual(InUnit(['  S := Format(''%.2f'', [Price], FormatSettings);']),
    FixAll(Bad, False));
end;

procedure TTestRdxFormatLocaleFixDetector.Sca059_Detector_RoundTrip;
const
  HEAD: array[0..1] of string = ('const', '  FMT_PRICE = ''Price: %8.3f'';');
begin
  Assert.AreEqual(UnitText(RTL_USES, HEAD, [
    '  r := Format(''%.2f'', [x], FormatSettings);',
    '  LogIt(Format(''%g / %d'', [x, 1], FormatSettings));',
    '  r := Format(FMT_PRICE, [x], FormatSettings);',
    '  r := Format(''%d items'', [1]);']),
    FixAll(UnitText(RTL_USES, HEAD, [
    '  r := Format(''%.2f'', [x]);',
    '  LogIt(Format(''%g / %d'', [x, 1]));',
    '  r := Format(FMT_PRICE, [x]);',
    '  r := Format(''%d items'', [1]);']), False));
end;

procedure TTestRdxFormatLocaleFixDetector.Sca059_Detector_TwoFormatsOnLine_NoHelp;
var
  Src  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  Src := InUnit(['  r := Format(''%.1f'', [x]) + Format(''%.2f'', [x]);']);
  Seen := Detect(Src);
  Assert.IsTrue(Length(Seen) >= 1, 'der Detektor meldet die Zeile');
  Assert.AreEqual<Integer>(BODY_LINE, Seen[0].Line);
  O := TablePlan(Src, Seen[0], False);
  Assert.IsFalse(O.Enabled);
  Assert.AreEqual(_(R_FL_MANY, [BODY_LINE, 2]), O.Reason);
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxFormatLocaleFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxFormatLocaleFixDetector);
  {$ENDIF}

end.
