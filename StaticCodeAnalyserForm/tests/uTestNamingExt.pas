unit uTestNamingExt;

// Tests fuer TNamingExtDetector (SCA118-119).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestNamingExt = class
  public
    // ExceptionName
    [Test] procedure ExceptionWithoutEPrefix_Reported;
    [Test] procedure ExceptionWithEPrefix_NotReported;
    [Test] procedure NonExceptionClass_NotReported;
    // 2026-08-27 SCA118-Praezisierung (Autopsie rw16, 85 Funde einzeln
    // geprueft: 63 FP). Gate 1 = nur die direkte Basis zaehlt, Gate 2 =
    // E-Praefix auch mit Kleintag/Ziffer. Jeder Gate-Test traegt seine
    // TP-Gegenprobe IM SELBEN Fixture, damit ein "0 Funde" nicht daran
    // liegen kann, dass der Fixture-Text den Detektor gar nicht erreicht.
    [Test] procedure JniInterfaceWithExceptionAncestor_NotReported;
    [Test] procedure ExceptionInterfaceInParentList_NotReported;
    [Test] procedure ExternalSubstringBase_NotReported;
    [Test] procedure LowercaseTagEPrefix_NotReported;
    [Test] procedure DigitEPrefix_NotReported;
    [Test] procedure RealExceptionSubclass_StillReported;
    [Test] procedure ExceptionWithPropsName_StillReported;
    [Test] procedure EPrefixWithoutFollowingCapital_StillReported;
    [Test] procedure AbortErrorBase_StillReported;
    [Test] procedure EShapedBaseWithoutMarker_NotReported;

    // LocalConstantName
    [Test] procedure PascalCaseNumericConst_Reported;
    [Test] procedure UpperSnakeNumericConst_NotReported;
    [Test] procedure ShortConstName_NotReported;
    [Test] procedure StringConst_NotReported;
    // 2026-07-26: Inline-const im RUMPF ist keine Deklarations-Konstante
    [Test] procedure InlineConstInBody_NotReported;
    // 2026-08-01 Konstanten-Gates (30%-Audit): Phantomknoten aus
    // Initialisiererlisten, strukturierte Konstanten, untypisierte
    // String-/Char-Literale.
    [Test] procedure UntypedStringConst_NotReported;
    [Test] procedure CharLiteralConst_NotReported;
    [Test] procedure TypedArrayConst_NotReported;
    [Test] procedure RecordArrayInitializerFields_NotReported;
    [Test] procedure NegativeNumericConst_StillReported;
    [Test] procedure TypedScalarConst_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestNamingExt.ExceptionWithoutEPrefix_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type MyParseError = class(Exception);'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkExceptionName) >= 1);
  finally F.Free; end;
end;

procedure TTestNamingExt.ExceptionWithEPrefix_NotReported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type EMyParseError = class(Exception);'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkExceptionName));
  finally F.Free; end;
end;

procedure TTestNamingExt.NonExceptionClass_NotReported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type MyWorker = class end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkExceptionName));
  finally F.Free; end;
end;

// ---------------------------------------------------------------------------
// SCA118-GATE 1 - nur die DIREKTE Basisklasse entscheidet.
// ---------------------------------------------------------------------------

procedure TTestNamingExt.JniInterfaceWithExceptionAncestor_NotReported;
// GROESSTE FP-Klasse der Autopsie (40 von 85). Der Parser fuehrt Interfaces
// bewusst als nkClass (uParser2.pas:872-878) - ein Gate auf den Knotentyp
// gaebe es also gar nicht. Was diese Deklarationen ausschliesst, ist ihre
// BASIS: 'JExceptionClass' ist eine Java-Klassen-Bruecke, keine Exception.
// Korpus-Beleg: Alcinoe.AndroidApi.AndroidX.Media3.pas:250.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  JExceptionClass = interface'#13#10 +
  '    procedure Init;'#13#10 +
  '  end;'#13#10 +
  '  JPlaybackExceptionClass = interface(JExceptionClass)'#13#10 +
  '    procedure Play;'#13#10 +
  '  end;'#13#10 +
  '  TRealError = class(Exception);'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    // TP-GEGENPROBE im selben Fixture: die echte Exception-Klasse bleibt
    // Fund, das JNI-Interface verschwindet - beides in einem Assert.
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkExceptionName),
      'Nur TRealError darf gemeldet werden, nicht die JNI-Interfaces');
    Assert.AreEqual('TRealError',
      TFindingHelper.FirstOf(F, fkExceptionName).MethodName);
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'TRealError = class'),
      TFindingHelper.FirstOf(F, fkExceptionName).LineNumber);
  finally F.Free; end;
end;

procedure TTestNamingExt.ExceptionInterfaceInParentList_NotReported;
// Substring-Ueberfang ueber die IMPLEMENTIERTE SCHNITTSTELLE. Die alte
// Pos-Kette las den ganzen TypeRef ('TInterfacedObject IgoExceptionReport')
// und traf das Interface. In Delphi ist der erste Eintrag der Elternliste
// zwingend die Basisklasse - alles danach sind Interfaces.
// Korpus-Beleg: Grijjy.ErrorReporting.pas:215.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  IgoExceptionReport = interface'#13#10 +
  '    procedure Report;'#13#10 +
  '  end;'#13#10 +
  '  TgoExceptionReport = class(TInterfacedObject, IgoExceptionReport)'#13#10 +
  '    procedure Report;'#13#10 +
  '  end;'#13#10 +
  '  TRealError = class(Exception);'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkExceptionName),
      'Ein Exception-Interface in der Elternliste macht keine Exception-Klasse');
    Assert.AreEqual('TRealError',
      TFindingHelper.FirstOf(F, fkExceptionName).MethodName);
  finally F.Free; end;
end;

procedure TTestNamingExt.ExternalSubstringBase_NotReported;
// Substring-Ueberfang MITTEN IM WORT: 'TTestDatabaseExternalAbstract'
// enthaelt 'eExternal' und lief damit in den alten EExternal-Marker.
// Korpus-Beleg: mORMot2 PerfTestCases.pas:301 (dort 5 Geschwister).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TTestDatabaseExternalAbstract = class(TObject)'#13#10 +
  '    procedure Run;'#13#10 +
  '  end;'#13#10 +
  '  TTestSqliteExternal = class(TTestDatabaseExternalAbstract)'#13#10 +
  '    procedure Run;'#13#10 +
  '  end;'#13#10 +
  '  TRealError = class(Exception);'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkExceptionName),
      '''DatabaseExternal'' ist kein EExternal-Nachfahre');
    Assert.AreEqual('TRealError',
      TFindingHelper.FirstOf(F, fkExceptionName).MethodName);
  finally F.Free; end;
end;

procedure TTestNamingExt.EShapedBaseWithoutMarker_NotReported;
// DOKUMENTIERTES VERHALTEN, kein Wunschdenken: die Monotonie-Wache in
// IsExceptionDescendant verlangt zusaetzlich zur E-Form einen Exception-
// Marker IM BASISNAMEN. 'EMyBase' hat keinen - der Nachfahre bleibt also
// unsichtbar, genau wie vor der Praezisierung. Ohne diese Wache wuerde das
// Paket 11 Funde HINZUFUEGEN (GEZAEHLT im Korpus, alle 11 echte Funde:
// 'FormatException = class(EJclError)' JclStrings.pas:412 u.a.) und der
// A/B-Vergleich waere nicht mehr lesbar. Wer die 11 holen will, holt sie
// in einem eigenen Paket mit eigener Messung - und aendert dann DIESEN Test.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  MyFail = class(EMyBase);'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkExceptionName),
    'E-foermige Basis ohne Exception-Marker: unveraendert kein Fund');
  finally F.Free; end;
end;

// ---------------------------------------------------------------------------
// SCA118-GATE 2 - E-Praefix auch mit Kleintag oder Ziffer.
// ---------------------------------------------------------------------------

procedure TTestNamingExt.LowercaseTagEPrefix_NotReported;
// 'E' + kurzer Kleinbuchstaben-Tag ist eine eingebuergerte Praefixform.
// Korpus-Belege: EdwsJSONException dwsJSON.pas:525, EheFontStockException
// SynTextDrawer.pas:137, EjimHtmlParserError JimParse.pas:118.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  EdwsJSONException = class(Exception);'#13#10 +
  '  EheFontStockException = class(Exception);'#13#10 +
  '  DwsJSONError = class(Exception);'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    // TP-GEGENPROBE: derselbe Bibliotheks-Praefix OHNE das fuehrende 'E'
    // bleibt ein Fund - das Gate prueft den Praefix, nicht den Wortstamm.
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkExceptionName),
      'Nur DwsJSONError darf gemeldet werden');
    Assert.AreEqual('DwsJSONError',
      TFindingHelper.FirstOf(F, fkExceptionName).MethodName);
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'DwsJSONError = class'),
      TFindingHelper.FirstOf(F, fkExceptionName).LineNumber);
  finally F.Free; end;
end;

procedure TTestNamingExt.DigitEPrefix_NotReported;
// 'E' + Ziffer. Korpus-Beleg: E7Zip mormot.lib.win7zip.pas:455.
// Nebenbei die Gate-1-Kette: ESynException ist E-foermig UND traegt den
// Marker, taugt also weiter als Basis.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  ESynException = class(Exception);'#13#10 +
  '  E7Zip = class(ESynException);'#13#10 +
  '  Zip7Error = class(ESynException);'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkExceptionName),
      'Nur Zip7Error darf gemeldet werden');
    Assert.AreEqual('Zip7Error',
      TFindingHelper.FirstOf(F, fkExceptionName).MethodName);
  finally F.Free; end;
end;

// ---------------------------------------------------------------------------
// TP-Waechter: die Gates duerfen den Kern der Regel nicht mitnehmen.
// ---------------------------------------------------------------------------

procedure TTestNamingExt.RealExceptionSubclass_StillReported;
// Der Normalfall, auf den SCA118 zielt.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TMyError = class(Exception);'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkExceptionName),
      'Direkter Exception-Nachfahre ohne E-Praefix muss Fund bleiben');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'TMyError = class'),
      TFindingHelper.FirstOf(F, fkExceptionName).LineNumber);
  finally F.Free; end;
end;

procedure TTestNamingExt.ExceptionWithPropsName_StillReported;
// WAECHTER FUER MAX_LOWER_TAG. 'ExceptionWithProps' faengt mit 'E' an und
// hat einen Grossbuchstaben hinter dem Kleinbuchstaben-Lauf - ohne die
// Laengengrenze wuerde Gate 2 es als E-praefixiert durchwinken und einen
// TP verschlucken. 'xception' ist 8 Zeichen lang, MAX_LOWER_TAG ist 3.
// Korpus-Beleg: mormot.core.base.pas:547 (4 Kopien im Korpus).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  ExceptionWithProps = class(Exception);'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkExceptionName),
      'Langer Kleinlauf nach dem E ist kein Praefix, sondern ein Wort');
    Assert.AreEqual('ExceptionWithProps',
      TFindingHelper.FirstOf(F, fkExceptionName).MethodName);
  finally F.Free; end;
end;

procedure TTestNamingExt.EPrefixWithoutFollowingCapital_StillReported;
// WAECHTER FUER DIE NACHFOLGE-BEDINGUNG. Zwei verschiedene Angriffe auf
// Gate 2, beide muessen Fund bleiben:
//   'Err'   - Kleinlauf reicht bis Namensende, es folgt kein Wortteil.
//   'Error' - 'rror' ist 4 Zeichen und damit laenger als MAX_LOWER_TAG.
// Beides sind englische Woerter mit E am Anfang, keine E-Praefixe.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  Err = class(Exception);'#13#10 +
  '  Error = class(Exception);'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkExceptionName),
    'E + Kleinlauf ohne folgenden Wortteil ist kein E-Praefix');
  finally F.Free; end;
end;

procedure TTestNamingExt.AbortErrorBase_StillReported;
// WAECHTER FUER DIE MARKER-LISTE. 'EAbortError' enthaelt kein 'exception',
// sondern traf frueher ueber den Sondereintrag 'eaborterror'. Die Liste
// wanderte von 'ganzer TypeRef' auf 'nur die Basis' - sie muss dort
// weiterhin greifen.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  MyAbort = class(EAbortError);'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkExceptionName),
      'EAbortError-Nachfahre muss weiter gemeldet werden');
    Assert.AreEqual('MyAbort',
      TFindingHelper.FirstOf(F, fkExceptionName).MethodName);
  finally F.Free; end;
end;

procedure TTestNamingExt.PascalCaseNumericConst_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'const'#13#10 +
  '  MaxRetries = 3;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkLocalConstantName) >= 1);
  finally F.Free; end;
end;

procedure TTestNamingExt.UpperSnakeNumericConst_NotReported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'const'#13#10 +
  '  MAX_RETRIES = 3;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLocalConstantName));
  finally F.Free; end;
end;

procedure TTestNamingExt.ShortConstName_NotReported;
// Sehr kurze Namen (<=2 Zeichen) sind Loop-Counter, kein Befund.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'const'#13#10 +
  '  N = 10;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLocalConstantName));
  finally F.Free; end;
end;

procedure TTestNamingExt.StringConst_NotReported;
// Strings sind oft UI-Labels (PascalCase OK), kein Befund.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'const'#13#10 +
  '  MsgFileNotFound: string = ''File not found'';'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLocalConstantName));
  finally F.Free; end;
end;

procedure TTestNamingExt.InlineConstInBody_NotReported;
// Seit uParser2.ParseInlineConstStmt (2026-07-26) landet auch
// "const X = 42;" MITTEN IM RUMPF als nkConstSection im AST. SCA119 zielt
// aber auf die Konvention der Deklarations-/Unit-Ebene (UPPER_SNAKE_CASE);
// Inline-Konstanten schreibt man in Delphi 10.3+ wie lokale Variablen.
// Ohne die Direkt-Kind-Einschraenkung schlug das im Korpus mit +523 Funden
// auf (deltaT, interpolated, CPartBase ...) - reines Rauschen.
// GEGENPROBE steckt in PascalCaseNumericConst_Reported: die echte
// const-SEKTION im Deklarationsteil bleibt ein Fund.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  const deltaT = 42;'#13#10 +
  '  Beep;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLocalConstantName),
    'Inline-const im Rumpf darf SCA119 nicht ausloesen');
  finally F.Free; end;
end;

procedure TTestNamingExt.UntypedStringConst_NotReported;
// Der alte Skip sah nur den DEKLARIERTEN Typ. Ohne Typannotation gibt es
// keinen - der Literal-Typ des Initialisierers entscheidet jetzt mit.
// Korpus-Beleg: jvcl JvaDBReg.pas:59 'cItemField = ''ItemField'''.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'const'#13#10 +
  '  cItemField = ''ItemField'';'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLocalConstantName),
    'Untypisierte String-Konstante ist keine numerische Konstante');
  finally F.Free; end;
end;

procedure TTestNamingExt.CharLiteralConst_NotReported;
// Korpus-Beleg: cnwizards TestCharLiterals.pas:18 'Fred = #80'.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'const'#13#10 +
  '  CaptionSeparator = #80;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLocalConstantName),
    'Char-Literal ist keine numerische Konstante');
  finally F.Free; end;
end;

procedure TTestNamingExt.TypedArrayConst_NotReported;
// Korpus-Beleg: jvcl JvListBox.pas:198
// 'Sorted: array[Boolean] of DWORD = (0, LBS_SORT)'. Die Regel empfiehlt
// UPPER_SNAKE_CASE ausdruecklich fuer 'numeric constants'.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'const'#13#10 +
  '  SortFlags: array[Boolean] of DWORD = (0, 2);'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLocalConstantName),
    'Strukturierte typed-Array-Konstante ist kein Naming-Fund');
  finally F.Free; end;
end;

procedure TTestNamingExt.RecordArrayInitializerFields_NotReported;
// DIE FP-KLASSE MIT DER GROESSTEN MASSE. Der Wert-Scan in
// uParser2.ParseVarLikeSection ist nicht klammerbalanciert und bricht am
// ersten ';' ab - auch wenn das INNERHALB der Klammern steht. Ab dort
// laeuft ein neuer Durchlauf, und die Record-FELDNAMEN landen als eigene
// "Konstanten" im AST (Korpus-Beleg: Indy IdGlobalProtocols.pas:2632
// 'Offset', jvcl JvPainterEffectsForm.pas:128 'Pos').
// Erkennungsmerkmal hier: dem Phantom fehlt das '=' im TypeRef - eine
// gueltige Pascal-Konstante MUSS initialisiert sein.
// Der Parser-Fix liegt bewusst ausserhalb dieser Serie.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'type'#13#10 +
  '  TZoneRec = record TimeZone: string; Offset: string; end;'#13#10 +
  'const'#13#10 +
  '  Zones: array[0..1] of TZoneRec = ('#13#10 +
  '    (TimeZone: ''NST''; Offset: ''-0330''),'#13#10 +
  '    (TimeZone: ''EST''; Offset: ''-0500''));'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLocalConstantName),
    'Record-Feldnamen aus einem Initialisierer sind keine Konstanten');
  finally F.Free; end;
end;

procedure TTestNamingExt.NegativeNumericConst_StillReported;
// WAECHTER: die Gates duerfen den Kern der Regel nicht mitnehmen. Ein
// negativer Zahlwert faengt nicht mit '(' oder Quote an und bleibt Fund.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'const'#13#10 +
  '  MinTemperature = -273;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkLocalConstantName) >= 1,
    'Negative Zahlkonstante muss weiter gemeldet werden');
  finally F.Free; end;
end;

procedure TTestNamingExt.TypedScalarConst_StillReported;
// WAECHTER: skalar-typisierte Konstante ist genau der Fall, den die Regel
// meint - der Typteil enthaelt weder array noch record.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'const'#13#10 +
  '  BufferSize: Integer = 4096;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkLocalConstantName) >= 1,
    'Skalar typisierte Konstante muss weiter gemeldet werden');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestNamingExt);

end.
