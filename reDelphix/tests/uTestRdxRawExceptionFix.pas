unit uTestRdxRawExceptionFix;

// Editorhilfe SCA127 RaisingRawException (uRdxRawExceptionFix): in
// 'raise Exception.Create(..)' wird nur der Klassenname EArgumentException
// (erster Eintrag) bzw. EInvalidOpException (zweiter Eintrag). Die erste
// Fixture prueft den Planer auf Text (ohne Parser, ohne Detektor), die
// zweite - nur Delphi, hinter {$IFNDEF FPC} - den ECHTEN Detektor
// (uRaisingRawException) auf dem echten AST ueber den Einstieg der Tabelle
// (TRdxFixTable.FixFor bzw. AlternativeFixFor via PlanFixIn/PlanAltFixIn
// mit geoeffnetem Quellstellen-Dienst - die Adapter
// PlanRaisingRawException/PlanRaisingRawExceptionAlt ergaenzen SysUtils in
// uses ueber AppendUses). Die Quellen stehen in einer Routine Foo; ihre
// erste Rumpfzeile ist Zeile 7 (BODY_LINE).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxRawExceptionFix = class
  public
    // ---- Umformung ----
    [Test] procedure Create_BecomesArgumentException;
    [Test] procedure Alt_BecomesInvalidOpException;
    [Test] procedure OtherConstructors_KeepArguments;
    [Test] procedure LowerCase_ReplacesOnlyClassName;
    [Test] procedure ClassOnNextLine_Helps;
    [Test] procedure OnHandlerOnSameLine_Helps;
    [Test] procedure AtClause_Helps;
    [Test] procedure CommentAndStringOnLine_Helps;
    [Test] procedure CommentInsideStatement_Helps;
    [Test] procedure UsesOfNamesAreNoDeclaration_Helps;
    // ---- Gegenproben ----
    [Test] procedure InCommentOrString_NoHelp;
    [Test] procedure MovedLine_NoHelp;
    [Test] procedure SpecificClass_NoHelp;
    [Test] procedure TwoOnLine_NoHelp;
    [Test] procedure NoConstructor_NoHelp;
    [Test] procedure Directive_NoHelp;
    [Test] procedure OwnException_NoHelp;
    [Test] procedure OwnTargetClass_NoHelp;
    [Test] procedure OwnTargetVariable_NoHelp;
    // ---- Realworld-Test rwE29 ----
    [Test] procedure OldCompilerSwitch_NoHelp;
    [Test] procedure NewCompilerSwitch_Helps;
    // ---- Realworld-Test rwE30 Stufe 2 ----
    [Test] procedure OwnException_OtherRoutine_Helps;
    [Test] procedure OwnException_SameRoutine_NoHelp;
    [Test] procedure MormotSymbols_NoHelp;
    [Test] procedure ModernProof_RefutesTrace;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxRawExceptionDetector = class
  public
    [Test] procedure Detector_ReportsRaiseLine;
    [Test] procedure Detector_RoundTrip_Argument;
    [Test] procedure Detector_RoundTrip_InvalidOp;
    [Test] procedure Detector_CreateFmt_RoundTrip;
    [Test] procedure Detector_CatalogExample_Fixed;
    [Test] procedure Detector_ClassOnNextLine_Fixed;
    [Test] procedure Detector_TwoRaises_BothFixed;
    [Test] procedure Detector_TwoOnOneLine_NoHelp;
    [Test] procedure Detector_Bare_NoHelp;
    [Test] procedure Detector_LowerCaseAndQualified;
    // ---- Tabellenzeile ----
    [Test] procedure Table_BothEntriesMarked;
    [Test] procedure Table_MissingSysUtils_AddsUses;
    // ---- Realworld-Test rwE29 (uses im Text, PlanUses) ----
    [Test] procedure Table_SysUtilsBehindKeywordSegment_NoSecondUses;
    [Test] procedure Table_SysUtilsOnlyUnderCondition_NoHelp;
    [Test] procedure Table_SysUtilsOnlyInComment_AddsUses;
    // ---- Realworld-Test rwE30 Stufe 2 (Plattenblick, Sperre bei Beleg) ----
    [Test] procedure Table_OldProjectNearby_NoHelp;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uRaisingRawException,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uRdxFixTable,          // TRdxFixTable.CaptionFor
  uRdxPlacesRunner,      // R_USES_CONDITIONAL (PlanUses)
  uTestRdxDetectorKit,   // TSeen, DetectSource, CatalogText, PlanFixIn
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxRawExceptionFix,
  uRdxText,              // _() und die gemeinsamen Gruende (E29)
  uTestRdxTextKit;       // Join, Apply, LineOf, NewMap

const
  BODY_LINE = 7;   // erste Rumpfzeile von Wrap
  // Die feste Meldung des Detektors (der Planer liest sie nicht).
  DETECTOR_MSG = 'Raising bare "Exception" - use a specific subclass (e.g. '
    + 'EArgumentException)';

// ---- Helfer ----

// Eine Unit mit ADecls im interface und EINER Routine Foo; ohne ADecls
// beginnt der Rumpf auf Zeile 7.
function WrapWith(const ADecls, ABody: array of string): string;
begin
  Result := Join(['unit t;', 'interface']) + #13#10;
  if Length(ADecls) > 0 then
    Result := Result + Join(ADecls) + #13#10;
  Result := Result + Join(['implementation', 'uses SysUtils;',
    'procedure Foo(X: Integer);', 'begin']) + #13#10 + Join(ABody) + #13#10
    + Join(['end;', 'end.']);
end;

function Wrap(const ABody: array of string): string;
begin
  Result := WrapWith([], ABody);
end;

// Der Planer (AAlt: zweiter Eintrag) fuer Zeile ALine.
function PlanAt(const ASource: string; ALine: Integer; AAlt: Boolean;
  out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Map : TRdxCodeMap;
begin
  Map := NewMap(ASource);
  try
    if AAlt then
      Result := TRdxRawExceptionFix.ToInvalidOpException(Map, ALine,
        DETECTOR_MSG, AEdit, AReason)
    else
      Result := TRdxRawExceptionFix.ToArgumentException(Map, ALine,
        DETECTOR_MSG, AEdit, AReason);
  finally
    Map.Free;
  end;
end;

// Die Hilfe muss gelten (sonst scheitert der Test mit dem Grund); der neue
// Text.
function Fixed(const ASource: string; ALine: Integer;
  AAlt: Boolean = False): string;
var
  E : TRdxEdit;
  R : string;
begin
  Assert.IsTrue(PlanAt(ASource, ALine, AAlt, E, R), R);
  Result := Apply(ASource, E);
end;

procedure AssertRefused(const ASource: string; ALine: Integer;
  const AReason: string; AAlt: Boolean = False);
var
  E : TRdxEdit;
  R : string;
begin
  Assert.IsFalse(PlanAt(ASource, ALine, AAlt, E, R), 'keine Hilfe');
  Assert.AreEqual(AReason, R, 'Grund');
end;

// ASource mit dem ersten 'Exception.' hinter 'raise ' durch AClass ersetzt.
function Retyped(const ASource, AClass: string): string;
begin
  Result := StringReplace(ASource, 'raise Exception.', 'raise ' + AClass + '.',
    []);
end;

function Moved: string;
begin
  Result := MsgMovedSuffix(_(R_RAWEXC_MOVED));
end;

// ---- Umformung ----

procedure TTestRdxRawExceptionFix.Create_BecomesArgumentException;
var
  Src : string;
  E   : TRdxEdit;
  R   : string;
begin
  Src := Wrap(['  if X < 0 then raise Exception.Create(''x is negative'');']);
  Assert.AreEqual(Retyped(Src, 'EArgumentException'), Fixed(Src, BODY_LINE));
  // Die Ersetzung trifft genau das Wort 'Exception'.
  Assert.IsTrue(PlanAt(Src, BODY_LINE, False, E, R), R);
  Assert.AreEqual('Exception', E.Expected);
  Assert.AreEqual(RAWEXC_ARGUMENT, E.NewText);
  Assert.AreEqual<Integer>(BODY_LINE, E.Span.StartLine);
  Assert.AreEqual<Integer>(BODY_LINE, E.Span.EndLine);
  Assert.AreEqual<Integer>(23, E.Span.StartCol);
  Assert.AreEqual<Integer>(32, E.Span.EndCol);
end;

procedure TTestRdxRawExceptionFix.Alt_BecomesInvalidOpException;
var
  Src : string;
begin
  Src := Wrap(['  if not FOpen then', '    raise Exception.Create(''not open'');']);
  Assert.AreEqual(Retyped(Src, 'EInvalidOpException'),
    Fixed(Src, BODY_LINE + 1, True));
end;

procedure TTestRdxRawExceptionFix.OtherConstructors_KeepArguments;
var
  Src : string;
begin
  // CreateFmt, CreateRes, CreateHelp: nur der Klassenname wechselt.
  Src := Wrap(['  raise Exception.CreateFmt(''x = %d'', [X]);']);
  Assert.AreEqual(Retyped(Src, 'EArgumentException'), Fixed(Src, BODY_LINE));
  Src := Wrap(['  raise Exception.CreateRes(@SErrText);']);
  Assert.AreEqual(Retyped(Src, 'EInvalidOpException'),
    Fixed(Src, BODY_LINE, True));
  Src := Wrap(['  raise Exception.CreateHelp(''x'', 12);']);
  Assert.AreEqual(Retyped(Src, 'EArgumentException'), Fixed(Src, BODY_LINE));
end;

procedure TTestRdxRawExceptionFix.LowerCase_ReplacesOnlyClassName;
begin
  // Gross/klein des Konstruktors bleibt; die Klasse kommt wie geschrieben.
  Assert.AreEqual(Wrap(['  RAISE EArgumentException.create(''x'');']),
    Fixed(Wrap(['  RAISE exception.create(''x'');']), BODY_LINE));
end;

procedure TTestRdxRawExceptionFix.ClassOnNextLine_Helps;
var
  Src : string;
begin
  // Der Detektor meldet die Zeile des 'raise'; Klasse und Konstruktor
  // stehen darunter.
  Src := Wrap(['  raise', '    Exception.Create(''x'');']);
  Assert.AreEqual(Wrap(['  raise', '    EArgumentException.Create(''x'');']),
    Fixed(Src, BODY_LINE));
  Src := Wrap(['  raise Exception', '    .CreateFmt(''%d'', [X]);']);
  Assert.AreEqual(Wrap(['  raise EInvalidOpException', '    .CreateFmt(''%d'', [X]);']),
    Fixed(Src, BODY_LINE, True));
end;

procedure TTestRdxRawExceptionFix.OnHandlerOnSameLine_Helps;
var
  Src : string;
begin
  // 'on E: Exception' auf derselben Zeile bleibt - nur das raise wechselt.
  Src := Wrap(['  try', '    Work;', '  except',
    '    on E: Exception do raise Exception.Create(''w: '' + E.Message);',
    '  end;']);
  Assert.AreEqual(Retyped(Src, 'EArgumentException'),
    Fixed(Src, BODY_LINE + 3));
end;

procedure TTestRdxRawExceptionFix.AtClause_Helps;
var
  Src : string;
begin
  Src := Wrap(['  raise Exception.Create(''x'') at ReturnAddress;']);
  Assert.AreEqual(Retyped(Src, 'EArgumentException'), Fixed(Src, BODY_LINE));
end;

procedure TTestRdxRawExceptionFix.CommentAndStringOnLine_Helps;
var
  Src : string;
begin
  // Dasselbe Muster in String und Kommentar zaehlt nicht als zweites.
  Src := Wrap(['  raise Exception.Create(''raise Exception.Create''); '
    + '// raise Exception.Create']);
  Assert.AreEqual(Retyped(Src, 'EArgumentException'), Fixed(Src, BODY_LINE));
end;

procedure TTestRdxRawExceptionFix.CommentInsideStatement_Helps;
begin
  // Ein Kommentar (keine Direktive) zwischen raise und Klasse stoert nicht -
  // ersetzt wird nur das Wort.
  Assert.AreEqual(Wrap(['  raise { warum } EArgumentException.Create(''x'');']),
    Fixed(Wrap(['  raise { warum } Exception.Create(''x'');']), BODY_LINE));
end;

procedure TTestRdxRawExceptionFix.UsesOfNamesAreNoDeclaration_Helps;
var
  Src : string;
begin
  // Die Datei NENNT beide Namen nur - als Typ eines Parameters, Ergebnisses
  // oder Handlers, als Elternklasse, Typargument und im is-Test. Das ist
  // keine eigene Deklaration.
  Src := WrapWith(['type', '  EMine = class(Exception);',
    '  TErrs = TArray<EArgumentException>;',
    'function Last: Exception;', 'procedure Log(E: EInvalidOpException);'],
    ['  try', '    Work;', '  except',
    '    on E: EArgumentException do if E is Exception then Log(nil);',
    '  end;', '  raise Exception.Create(''x'');']);
  Assert.AreEqual(Retyped(Src, 'EArgumentException'),
    Fixed(Src, LineOf(Src, 'raise ')));
  Assert.AreEqual(Retyped(Src, 'EInvalidOpException'),
    Fixed(Src, LineOf(Src, 'raise '), True));
end;

// ---- Gegenproben ----

procedure TTestRdxRawExceptionFix.InCommentOrString_NoHelp;
begin
  AssertRefused(Wrap(['  // raise Exception.Create(''x'');']), BODY_LINE, Moved);
  AssertRefused(Wrap(['  { raise Exception.Create(''x''); }']), BODY_LINE, Moved);
  AssertRefused(Wrap(['  S := ''raise Exception.Create(x)'';']), BODY_LINE,
    Moved);
  // Zeile in einem Block-Kommentar.
  AssertRefused(Wrap(['  (*', '  raise Exception.Create(''x'');', '  *)']),
    BODY_LINE + 1, Moved);
end;

procedure TTestRdxRawExceptionFix.MovedLine_NoHelp;
var
  Src : string;
begin
  Src := Wrap(['  Work;', '  raise Exception.Create(''x'');']);
  // Die gemeldete Zeile traegt kein raise (davor, dahinter, ausserhalb).
  AssertRefused(Src, BODY_LINE, Moved);
  AssertRefused(Src, BODY_LINE + 2, Moved);
  AssertRefused(Src, 99, Moved);
  AssertRefused(Src, 0, Moved);
end;

procedure TTestRdxRawExceptionFix.SpecificClass_NoHelp;
begin
  // Schon eine andere Klasse (der Fund ist veraltet), qualifiziert (meldet
  // der Detektor nicht), ein Bezeichner, der nur so anfaengt.
  AssertRefused(Wrap(['  raise EArgumentException.Create(''x'');']),
    BODY_LINE, Moved);
  AssertRefused(Wrap(['  raise SysUtils.Exception.Create(''x'');']),
    BODY_LINE, Moved);
  AssertRefused(Wrap(['  raise ExceptionFactory.Create(''x'');']),
    BODY_LINE, Moved);
  AssertRefused(Wrap(['  raise;']), BODY_LINE, Moved);
end;

procedure TTestRdxRawExceptionFix.TwoOnLine_NoHelp;
begin
  AssertRefused(Wrap(['  if A then raise Exception.Create(''a'') else raise '
    + 'Exception.Create(''b'');']), BODY_LINE,
    _(R_RAWEXC_MANY, [BODY_LINE, 2]));
end;

procedure TTestRdxRawExceptionFix.NoConstructor_NoHelp;
begin
  // 'raise Exception' ohne Konstruktor meldet der Detektor auch.
  AssertRefused(Wrap(['  raise Exception;']), BODY_LINE, _(R_RAWEXC_NO_CTOR));
  AssertRefused(Wrap(['  raise Exception at ReturnAddress;']), BODY_LINE,
    _(R_RAWEXC_NO_CTOR));
  // Ein Member, der kein Konstruktor ist.
  AssertRefused(Wrap(['  raise Exception.ClassInfo;']), BODY_LINE,
    _(R_RAWEXC_NO_CTOR));
end;

procedure TTestRdxRawExceptionFix.Directive_NoHelp;
begin
  AssertRefused(Wrap(['  raise Exception{$IFDEF D}.CreateFmt(''%s'', [S])'
    + '{$ELSE}.Create(S){$ENDIF};']), BODY_LINE, _(R_RAWEXC_DIRECTIVE));
  AssertRefused(Wrap(['  raise {$IFDEF D}Exception.Create(''x''){$ENDIF};']),
    BODY_LINE, _(R_RAWEXC_DIRECTIVE));
end;

procedure TTestRdxRawExceptionFix.OwnException_NoHelp;
var
  Src : string;
begin
  // Eine eigene Klasse 'Exception': die neue Klasse aus SysUtils haette
  // eine andere Hierarchie.
  Src := WrapWith(['type', '  Exception = class(TObject)', '  end;'],
    ['  raise Exception.Create;']);
  AssertRefused(Src, LineOf(Src, 'raise '), _(R_RAWEXC_OWN, ['Exception']));
  AssertRefused(Src, LineOf(Src, 'raise '), _(R_RAWEXC_OWN, ['Exception']),
    True);
end;

// Eine Unit mit zwei Methoden: Other (AOther: Kopf-Rest und Rumpf) und
// Check (raise in Zeile LineOf 'raise ').
function TwoRoutines(const AIface: string; const AOther: array of string;
  const ACheckHead: string): string;
begin
  Result := Join(['unit t;', 'interface', 'uses SysUtils;', AIface,
    'implementation']) + #13#10 + Join(AOther) + #13#10
    + Join([ACheckHead, 'begin', '  if X < 0 then',
    '    raise Exception.Create(''bad index'');', 'end;', 'end.']);
end;

procedure TTestRdxRawExceptionFix.OwnException_OtherRoutine_Helps;
var
  Src : string;
begin
  // Alcinoe Archive\Source\Alcinoe.FBX.Lib.pas:3040 - 'Exception:
  // EALFBXError' ist eine lokale Variable der verschachtelten Prozedur
  // RaiseException einer ANDEREN Methode; bis dahin sperrte die Datei
  // ('die Datei deklariert ein eigenes "Exception"').
  Src := TwoRoutines('', ['procedure Other(const S: Integer);',
    '  procedure RaiseException(const Excep: TClass);', '  var',
    '    Exception: TObject;', '  begin', '    Exception := nil;', '  end;',
    'begin', '  RaiseException(nil);', 'end;'],
    'procedure CheckRange(X: Integer);');
  Assert.AreEqual(Retyped(Src, RAWEXC_ARGUMENT), Fixed(Src,
    LineOf(Src, 'raise ')));
  // issrc Setup.MainFunc.pas:523 - Parameter 'const Exception: AnsiString'
  // einer anderen Routine, im interface deklariert und implementiert.
  Src := TwoRoutines('procedure OnException(const Exception: AnsiString; '
    + 'const Position: Cardinal);',
    ['procedure OnException(const Exception: AnsiString; '
    + 'const Position: Cardinal);', 'begin', '  Log(String(Exception));',
    'end;'], 'procedure CheckRange(X: Integer);');
  Assert.AreEqual(Retyped(Src, RAWEXC_INVALID_OP), Fixed(Src,
    LineOf(Src, 'raise '), True));
end;

procedure TTestRdxRawExceptionFix.OwnException_SameRoutine_NoHelp;
var
  Src : string;
begin
  // Gegenproben: dieselbe Routine (Parameter bzw. lokale Variable), eine
  // lokale Prozedur, deren Variable das raise sieht, eine globale Variable
  // und ein Feld - dort gilt der Name am raise.
  Src := TwoRoutines('', [], 'procedure CheckRange(X: Integer; Exception: '
    + 'TObject);');
  AssertRefused(Src, LineOf(Src, 'raise '), _(R_RAWEXC_OWN, ['Exception']));
  Src := TwoRoutines('', [], 'procedure CheckRange(X: Integer);' + #13#10
    + 'var' + #13#10 + '  Exception: TObject;');
  AssertRefused(Src, LineOf(Src, 'raise '), _(R_RAWEXC_OWN, ['Exception']));
  Src := Join(['unit t;', 'interface', 'implementation', 'uses SysUtils;',
    'procedure Outer(X: Integer);', 'var', '  Exception: TObject;',
    '  procedure Inner;', '  begin',
    '    raise Exception.Create(''x'');', '  end;', 'begin', 'end;',
    'end.']);
  AssertRefused(Src, LineOf(Src, 'raise '), _(R_RAWEXC_OWN, ['Exception']));
  Src := TwoRoutines('var' + #13#10 + '  Exception: TObject;', [],
    'procedure CheckRange(X: Integer);');
  AssertRefused(Src, LineOf(Src, 'raise '), _(R_RAWEXC_OWN, ['Exception']));
  Src := TwoRoutines('type' + #13#10 + '  TFoo = class' + #13#10
    + '    procedure Bar;' + #13#10 + '    Exception: TObject;' + #13#10
    + '  end;', [], 'procedure TFoo.CheckRange(X: Integer);');
  AssertRefused(Src, LineOf(Src, 'raise '), _(R_RAWEXC_OWN, ['Exception']));
end;

procedure TTestRdxRawExceptionFix.MormotSymbols_NoHelp;
var
  Src : string;
begin
  // delphimvcframework lib\dmustache\mormot.core.base.pas:7259 - mORMot 2
  // baut ab Delphi 7: '{$ifndef ISDELPHI2007ANDUP}' (Z. 361), dazu
  // '{$I mormot.defines.inc}'; mORMot2 mormot.core.base.pas:8475 -
  // '{$ifndef FPC_OR_UNICODE}' (Delphi vor 2009).
  Src := WrapWith(['{$ifndef ISDELPHI2007ANDUP}', 'type PtrInt = Integer;',
    '{$endif}'], ['  raise Exception.Create(''x'');']);
  AssertRefused(Src, LineOf(Src, 'raise '),
    _(R_RAWEXC_OLD, ['ISDELPHI2007ANDUP', 3, RAWEXC_ARGUMENT]));
  Src := WrapWith(['{$ifndef FPC_OR_UNICODE}', 'type RawUtf8 = AnsiString;',
    '{$endif}'], ['  raise Exception.Create(''x'');']);
  AssertRefused(Src, LineOf(Src, 'raise '),
    _(R_RAWEXC_OLD, ['FPC_OR_UNICODE', 3, RAWEXC_INVALID_OP]), True);
  Src := WrapWith(['{$I mormot.defines.inc}'], ['  raise Exception.Create(''x'');']);
  AssertRefused(Src, LineOf(Src, 'raise '),
    _(R_RAWEXC_OLD, ['mormot.defines.inc', 3, RAWEXC_ARGUMENT]));
  // Gegenprobe: ISDELPHIXE2 ist nach Delphi 2009.
  Src := WrapWith(['{$ifdef ISDELPHIXE2}', 'type PtrInt = NativeInt;',
    '{$endif}'], ['  raise Exception.Create(''x'');']);
  Assert.AreEqual(Retyped(Src, RAWEXC_ARGUMENT), Fixed(Src,
    LineOf(Src, 'raise ')));
end;

procedure TTestRdxRawExceptionFix.ModernProof_RefutesTrace;
var
  Src : string;
begin
  // Eine Inline-Variable ausserhalb jeder Weiche beweist Delphi 10.3: die
  // Weiche fuer Delphi 7 ist dort toter Code.
  Src := WrapWith(['{$IFDEF VER150}', 'type PtrInt = Integer;', '{$ENDIF}'],
    ['  for var i := 1 to X do', '    raise Exception.Create(''x'');']);
  Assert.AreEqual(Retyped(Src, RAWEXC_ARGUMENT), Fixed(Src,
    LineOf(Src, 'raise ')));
  // Gegenprobe: unter einer Weiche beweist sie nichts.
  Src := WrapWith(['{$IFDEF VER150}', 'type PtrInt = Integer;', '{$ENDIF}'],
    ['  {$IFNDEF VER150} for var i := 1 to X do Foo; {$ENDIF}',
    '  raise Exception.Create(''x'');']);
  AssertRefused(Src, LineOf(Src, 'raise '),
    _(R_RAWEXC_OLD, ['VER150', 3, RAWEXC_ARGUMENT]));
end;

procedure TTestRdxRawExceptionFix.OwnTargetClass_NoHelp;
var
  Src : string;
begin
  // Die Datei deklariert EArgumentException selbst (alte Kompatibilitaets-
  // Unit): der erste Eintrag bande an sie; der zweite bleibt.
  Src := WrapWith(['type', '  EArgumentException = class(Exception);'],
    ['  raise Exception.Create(''x'');']);
  AssertRefused(Src, LineOf(Src, 'raise '),
    _(R_RAWEXC_OWN, [RAWEXC_ARGUMENT]));
  Assert.AreEqual(Retyped(Src, 'EInvalidOpException'),
    Fixed(Src, LineOf(Src, 'raise '), True));
end;

procedure TTestRdxRawExceptionFix.OwnTargetVariable_NoHelp;
var
  Src : string;
begin
  // Variable, Parameter, Routine dieses Namens.
  Src := WrapWith(['var', '  EInvalidOpException: Integer;'],
    ['  raise Exception.Create(''x'');']);
  AssertRefused(Src, LineOf(Src, 'raise '),
    _(R_RAWEXC_OWN, [RAWEXC_INVALID_OP]), True);
  Src := WrapWith(['procedure Bar(EInvalidOpException: Integer);'],
    ['  raise Exception.Create(''x'');']);
  AssertRefused(Src, LineOf(Src, 'raise '),
    _(R_RAWEXC_OWN, [RAWEXC_INVALID_OP]), True);
  Src := WrapWith(['function EArgumentException(const S: string): TObject;'],
    ['  raise Exception.Create(''x'');']);
  AssertRefused(Src, LineOf(Src, 'raise '),
    _(R_RAWEXC_OWN, [RAWEXC_ARGUMENT]));
end;

procedure TTestRdxRawExceptionFix.OldCompilerSwitch_NoHelp;
var
  Src : string;
begin
  // rwE29, cnwizards ThirdParty\PascalScript\uPSRuntime.pas:5927 (gebaut
  // nur mit Delphi 5-2007): die Unit fragt '{$IFDEF DELPHI3UP }' - dort
  // gibt es EArgumentException und EInvalidOpException nicht (erst ab
  // Delphi 2009), die Hilfe brach den Bau (E2003). Ohne die Sperre bekaeme
  // diese Quelle beide Eintraege (die Datei deklariert nichts, SysUtils
  // steht in uses).
  Src := WrapWith(['{$IFDEF DELPHI3UP }', 'uses ActiveX;', '{$ENDIF}'],
    ['  if X < 0 then raise Exception.Create(''bad index'');']);
  AssertRefused(Src, LineOf(Src, 'raise '),
    _(R_RAWEXC_OLD, ['DELPHI3UP', 3, RAWEXC_ARGUMENT]));
  AssertRefused(Src, LineOf(Src, 'raise '),
    _(R_RAWEXC_OLD, ['DELPHI3UP', 3, RAWEXC_INVALID_OP]), True);
  // Die Schwelle selbst zaehlt mit: wer nach Delphi 2009 fragt, baut auch
  // davor.
  Src := WrapWith(['{$IF CompilerVersion >= 20}', '{$DEFINE NEWRTL}',
    '{$IFEND}'], ['  raise Exception.Create(''x'');']);
  AssertRefused(Src, LineOf(Src, 'raise '),
    _(R_RAWEXC_OLD, ['COMPILERVERSION >= 20', 3, RAWEXC_ARGUMENT]));
end;

procedure TTestRdxRawExceptionFix.NewCompilerSwitch_Helps;
var
  Src : string;
begin
  // Gegenprobe: eine Weiche, die nur neuere Compiler nennt (VER330 = 10.3,
  // FPC-Weiche - FPC 3.2.2 kennt beide Klassen), sperrt nicht.
  Src := WrapWith(['{$IFDEF VER330}', '{$DEFINE RIO}', '{$ENDIF}',
    '{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}'],
    ['  raise Exception.Create(''x'');']);
  Assert.AreEqual(Retyped(Src, 'EArgumentException'),
    Fixed(Src, LineOf(Src, 'raise ')));
  Assert.AreEqual(Retyped(Src, 'EInvalidOpException'),
    Fixed(Src, LineOf(Src, 'raise '), True));
end;

{$IFNDEF FPC}

{ ---- Mit dem echten Detektor und der Tabelle ---- }

procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TRaisingRawExceptionDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_s127_', ASource, fkRaisingRawException,
    RunDetector);
end;

// Dasselbe in der Form TDetectFunc (FixAllWith).
function DetectKind(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := DetectSource('rdx_s127_', ASource, AKind, RunDetector);
end;

// Die Hilfe fuer den ersten Fund des Detektors ueber den Einstieg der
// Tabelle - der erste Eintrag (FixFor) bzw. mit AAlt der zweite
// (AlternativeFixFor), mit geoeffnetem Quellstellen-Dienst (AppendUses).
function PlanFirst(const ASource: string; AAlt: Boolean;
  out ASeen: TSeen): TRdxFixOutcome;
var
  Seen : TArray<TSeen>;
begin
  Seen := Detect(ASource);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet einen Fund');
  ASeen := Seen[0];
  if AAlt then
    Result := PlanAltFixIn(ASource, 't.pas', fkRaisingRawException, ASeen)
  else
    Result := PlanFixIn(ASource, 't.pas', fkRaisingRawException, ASeen);
end;

// Fund fuer Fund ueber die Tabelle, nach jeder Ersetzung neu gemeldet, bis
// der Detektor schweigt (FixAllWith; AAlt: der zweite Eintrag).
function FixAll(const ASource: string; AAlt: Boolean = False): string;
begin
  Result := FixAllWith(ASource, fkRaisingRawException, DetectKind, AAlt);
end;

procedure TTestRdxRawExceptionDetector.Detector_ReportsRaiseLine;
var
  Seen : TArray<TSeen>;
begin
  Seen := Detect(Wrap(['  Work;', '  raise Exception.Create(''x'');']));
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  Assert.AreEqual<Integer>(BODY_LINE + 1, Seen[0].Line, 'Zeile des raise');
  Assert.AreEqual(DETECTOR_MSG, Seen[0].Msg, 'feste Meldung ohne Spalte');
end;

procedure TTestRdxRawExceptionDetector.Detector_RoundTrip_Argument;
var
  Src, Done : string;
begin
  Src := Wrap(['  if X < 0 then', '    raise Exception.Create(''negative'');']);
  Done := FixAll(Src);
  Assert.AreEqual(Retyped(Src, 'EArgumentException'), Done);
  Assert.AreEqual<Integer>(0, Length(Detect(Done)), 'der Detektor schweigt');
end;

procedure TTestRdxRawExceptionDetector.Detector_RoundTrip_InvalidOp;
var
  Src, Done : string;
begin
  Src := Wrap(['  if not FOpen then', '    raise Exception.Create(''closed'');']);
  Done := FixAll(Src, True);
  Assert.AreEqual(Retyped(Src, 'EInvalidOpException'), Done);
  Assert.AreEqual<Integer>(0, Length(Detect(Done)), 'der Detektor schweigt');
end;

procedure TTestRdxRawExceptionDetector.Detector_CreateFmt_RoundTrip;
var
  Src : string;
begin
  // 'Exception.CreateFmt' beginnt mit 'Exception.Create' - der Detektor
  // meldet es, die Hilfe behaelt Konstruktor und Argumente.
  Src := Wrap(['  raise Exception.CreateFmt(''x = %d'', [X]);']);
  Assert.AreEqual<Integer>(1, Length(Detect(Src)), 'ein Fund');
  Assert.AreEqual(Retyped(Src, 'EArgumentException'), FixAll(Src));
end;

procedure TTestRdxRawExceptionDetector.Detector_CatalogExample_Fixed;
var
  Meta : TRuleMeta;
  Src  : string;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkRaisingRawException);
  Assert.IsTrue(Pos('raise Exception.Create', Meta.BadExample) > 0,
    Meta.BadExample);
  Src := Wrap([CatalogText(Meta.BadExample)]);
  Assert.AreEqual<Integer>(1, Length(Detect(Src)),
    'der Detektor meldet das Beispiel');
  Assert.AreEqual(Retyped(Src, 'EArgumentException'), FixAll(Src));
end;

procedure TTestRdxRawExceptionDetector.Detector_ClassOnNextLine_Fixed;
var
  Src : string;
begin
  // Der Fund steht auf der Zeile des raise, die Klasse eine Zeile tiefer.
  Src := Wrap(['  raise', '    Exception.Create(''x'');']);
  Assert.AreEqual<Integer>(BODY_LINE, Detect(Src)[0].Line, 'Zeile des raise');
  Assert.AreEqual(Wrap(['  raise', '    EArgumentException.Create(''x'');']),
    FixAll(Src));
end;

procedure TTestRdxRawExceptionDetector.Detector_TwoRaises_BothFixed;
var
  Src : string;
begin
  Src := Wrap(['  if X < 0 then', '    raise Exception.Create(''a'');',
    '  if X > 9 then', '    raise Exception.CreateFmt(''%d'', [X]);']);
  Assert.AreEqual<Integer>(2, Length(Detect(Src)), 'zwei Funde');
  Assert.AreEqual(Wrap(['  if X < 0 then',
    '    raise EInvalidOpException.Create(''a'');', '  if X > 9 then',
    '    raise EInvalidOpException.CreateFmt(''%d'', [X]);']),
    FixAll(Src, True));
end;

procedure TTestRdxRawExceptionDetector.Detector_TwoOnOneLine_NoHelp;
var
  Src : string;
  S   : TSeen;
  O   : TRdxFixOutcome;
begin
  Src := Wrap(['  if A then raise Exception.Create(''a'') else raise '
    + 'Exception.Create(''b'');']);
  Assert.AreEqual<Integer>(2, Length(Detect(Src)), 'zwei Funde, eine Zeile');
  O := PlanFirst(Src, False, S);
  Assert.IsFalse(O.Enabled, 'mehrdeutig');
  Assert.AreEqual(_(R_RAWEXC_MANY, [BODY_LINE, 2]), O.Reason);
end;

procedure TTestRdxRawExceptionDetector.Detector_Bare_NoHelp;
var
  Src : string;
  S   : TSeen;
  O   : TRdxFixOutcome;
begin
  Src := Wrap(['  raise Exception;']);
  Assert.AreEqual<Integer>(1, Length(Detect(Src)), 'der Detektor meldet es');
  O := PlanFirst(Src, False, S);
  Assert.IsFalse(O.Enabled, 'kein Konstruktor');
  Assert.AreEqual(_(R_RAWEXC_NO_CTOR), O.Reason);
  Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
end;

procedure TTestRdxRawExceptionDetector.Detector_LowerCaseAndQualified;
var
  Src : string;
begin
  // Klein geschrieben: der Detektor meldet es, die Hilfe greift.
  Src := Wrap(['  raise exception.create(''x'');']);
  Assert.AreEqual(Wrap(['  raise EArgumentException.create(''x'');']),
    FixAll(Src));
  // Qualifiziert meldet der Detektor nichts - und der Planer lehnt es ab
  // (MovedLine/SpecificClass der ersten Fixture).
  Assert.AreEqual<Integer>(0,
    Length(Detect(Wrap(['  raise SysUtils.Exception.Create(''x'');']))));
end;

procedure TTestRdxRawExceptionDetector.Table_BothEntriesMarked;
var
  Src : string;
  S   : TSeen;
  O   : TRdxFixOutcome;
begin
  // Beide Eintraege gekennzeichnet (E2): EArgumentException (Variant 0,
  // Hinweis des Adapters) und EInvalidOpException (Variant 1); SysUtils
  // steht schon in uses - eine Ersetzung, kein ' + uses'.
  Src := Wrap(['  raise Exception.Create(''x'');']);
  O := PlanFirst(Src, False, S);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual<Integer>(0, O.Variant, 'erster Eintrag');
  Assert.IsTrue(O.ChangesBehavior, 'gekennzeichnet');
  Assert.AreEqual<Integer>(1, Length(O.Edits), 'nur der Klassenname');
  Assert.IsTrue(Pos('EArgumentException', O.Hint) > 0, O.Hint);
  Assert.AreEqual<Integer>(0, Pos(' + uses', O.Hint), O.Hint);
  Assert.IsTrue(TRdxFixTable.CaptionFor(fkRaisingRawException, O) <> '',
    'Menuetext');
  O := PlanFirst(Src, True, S);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual<Integer>(1, O.Variant, 'zweiter Eintrag');
  Assert.IsTrue(O.ChangesBehavior, 'gekennzeichnet');
  Assert.IsTrue(Pos('EInvalidOpException', O.Hint) > 0, O.Hint);
  Assert.AreEqual(Retyped(Src, 'EInvalidOpException'), Apply(Src, O.Edits));
end;

procedure TTestRdxRawExceptionDetector.Table_OldProjectNearby_NoHelp;
var
  Root, U, Dof, Src : string;
  S                 : TSeen;
  Seen              : TArray<TSeen>;
  O                 : TRdxFixOutcome;
begin
  // gexperts Extras\NewEditor\GX_eAlign.pas:302: GExperts baut mit Delphi
  // 3-6 (GExpert4.dof zwei Ebenen hoeher, keine .dproj) - dort gibt es
  // weder EArgumentException noch EInvalidOpException. Die Unit selbst
  // fragt nach keinem Compiler; ohne den Plattenblick des Adapters
  // (TRdxMagicFixes.ProjectReason, lfExceptionClasses) boeten beide
  // Eintraege an. Gegenprobe: ohne die .dof.
  Src := Wrap(['  raise Exception.Create(''No Editor Interface'');']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  S := Seen[0];
  Root := NewTempDir('rdx_s127_');
  try
    U := Root + 'gx' + PathDelim + 'Extras' + PathDelim + 'NewEditor'
      + PathDelim;
    ForceDirectories(U);
    U := U + 'GX_eAlign.pas';
    Dof := Root + 'gx' + PathDelim + 'GExpert4.dof';
    WriteText(Dof, '[Compiler]');
    O := PlanFixIn(Src, U, fkRaisingRawException, S);
    Assert.IsFalse(O.Enabled, 'erster Eintrag gesperrt');
    Assert.IsTrue(Pos('GExpert4.dof', O.Reason) > 0, O.Reason);
    Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
    O := PlanAltFixIn(Src, U, fkRaisingRawException, S);
    Assert.IsFalse(O.Enabled, 'zweiter Eintrag gesperrt');
    Assert.IsTrue(Pos('GExpert4.dof', O.Reason) > 0, O.Reason);
    DeleteFile(Dof);
    O := PlanFixIn(Src, U, fkRaisingRawException, S);
    Assert.IsTrue(O.Enabled, O.Reason);
    O := PlanAltFixIn(Src, U, fkRaisingRawException, S);
    Assert.IsTrue(O.Enabled, O.Reason);
  finally
    RemoveTree(Root);
  end;
end;

procedure TTestRdxRawExceptionDetector.Table_MissingSysUtils_AddsUses;
var
  Src, Done : string;
  S         : TSeen;
  O         : TRdxFixOutcome;
begin
  // Ohne SysUtils in uses (Exception kam ueber eine andere Unit) haengt
  // der Adapter die Einfuegung an (AppendUses) - zwei Ersetzungen, der
  // Hinweis nennt sie.
  Src := Join(['unit t;', 'interface', 'implementation',
    'uses System.Classes;', 'procedure Foo(X: Integer);', 'begin',
    '  raise Exception.Create(''x'');', 'end;', 'end.']);
  O := PlanFirst(Src, False, S);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual<Integer>(2, Length(O.Edits), 'Klassenname und uses');
  Assert.IsTrue(Pos(' + uses ', O.Hint) > 0, O.Hint);
  Done := Apply(Src, O.Edits);
  Assert.IsTrue(Pos('raise EArgumentException.Create(''x'');', Done) > 0, Done);
  Assert.IsTrue(Pos('SysUtils', Done) > 0, Done);
  Assert.AreEqual<Integer>(0, Length(Detect(Done)), 'der Detektor schweigt');
end;

procedure TTestRdxRawExceptionDetector.Table_SysUtilsBehindKeywordSegment_NoSecondUses;
var
  Src : string;
  S   : TSeen;
  O   : TRdxFixOutcome;
begin
  // rwE29, MVCFramework.Serializer.JsonDataObjects.pas:2161: der Parser
  // bricht das interface-uses am Glied 'Abstract' (ein Schluesselwort) ab,
  // 'System.SysUtils' dahinter fehlt im Baum - die Hilfe fuegte es ein
  // zweites Mal ins implementation-uses ein (E2004). Ohne den Blick auf den
  // Text (PlanUses) kaemen zwei Ersetzungen und ' + uses System.SysUtils'.
  Src := Join(['unit t;', 'interface', 'uses', '  System.Classes,',
    '  MVCFramework.Serializer.Abstract,', '  System.SysUtils;',
    'implementation', 'uses', '  System.SysConst;',
    'procedure Foo(X: Integer);', 'begin',
    '  raise Exception.Create(''x'');', 'end;', 'end.']);
  O := PlanFirst(Src, False, S);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual<Integer>(1, Length(O.Edits), 'nur der Klassenname');
  Assert.AreEqual<Integer>(0, Pos(' + uses', O.Hint), O.Hint);
  O := PlanFirst(Src, True, S);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual<Integer>(1, Length(O.Edits), 'nur der Klassenname (Alt)');
end;

procedure TTestRdxRawExceptionDetector.Table_SysUtilsOnlyUnderCondition_NoHelp;
var
  Src : string;
  S   : TSeen;
  O   : TRdxFixOutcome;
begin
  // Der Baum sieht SysUtils nicht (Klausel am 'Abstract' abgebrochen), im
  // Text steht es nur unter '{$IFDEF FPC}' (Zeile 5) - ob im gebauten
  // Zweig, ist offen: gesperrt (rwE29, mormot.crypt.openssl.pas: sysutils
  // nur im {$ifdef USE_OPENSSL}-Zweig, die Hilfe fuegte es in den anderen
  // ein). Ohne den Fix fuegte PlanUses System.SysUtils ein.
  Src := Join(['unit t;', 'interface', 'uses', '  Foo.Abstract,',
    '  {$IFDEF FPC} SysUtils, {$ENDIF}', '  Classes;', 'implementation',
    'procedure Foo(X: Integer);', 'begin',
    '  raise Exception.Create(''x'');', 'end;', 'end.']);
  O := PlanFirst(Src, False, S);
  Assert.IsFalse(O.Enabled, 'gesperrt');
  Assert.AreEqual(_('%s is missing in uses: %s', ['System.SysUtils',
    _(R_USES_CONDITIONAL, [5, MsgByHand])]), O.Reason);
  Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
end;

procedure TTestRdxRawExceptionDetector.Table_SysUtilsOnlyInComment_AddsUses;
var
  Src : string;
  S   : TSeen;
  O   : TRdxFixOutcome;
begin
  // Gegenprobe zum Blick auf den Text: 'uses SysUtils' nur in einem
  // Block-Kommentar und hinter '//' zaehlt nicht - die Einfuegung bleibt.
  Src := Join(['unit t;', 'interface', 'implementation',
    '{ uses SysUtils; }', 'uses System.Classes; // uses SysUtils;',
    'procedure Foo(X: Integer);', 'begin',
    '  raise Exception.Create(''x'');', 'end;', 'end.']);
  O := PlanFirst(Src, False, S);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual<Integer>(2, Length(O.Edits), 'Klassenname und uses');
  Assert.IsTrue(Pos(' + uses ', O.Hint) > 0, O.Hint);
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxRawExceptionFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxRawExceptionDetector);
  {$ENDIF}

end.
