unit uTestMissingRaise;

// Tests fuer den TMissingRaiseDetector.
//
// Positive Faelle: Exception-Klasse via .Create instanziiert ohne raise.
// Negative Faelle: raise davor, oder gar keine Exception-Klasse.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMissingRaise = class
  public
    // ---- Positive Varianten ------------------------------------------------
    [Test] procedure ExceptionCreate_NoRaise_Reported;
    [Test] procedure SpecificExceptionCreate_NoRaise_Reported;
    [Test] procedure ExceptionCreateWithFormatArg_NoRaise_Reported;
    // Voll-Review 2026-09-12 (Major 77/78): die ECHTEN
    // Konstruktor-Varianten und der klammerlose Aufruf. Der Test
    // darueber hiess bis dahin 'ExceptionCreateFmt...', pruefte aber
    // '.Create(Format(...))' - die Luecke war auch im Test blind.
    [Test] procedure ExceptionCreateFmtVariant_NoRaise_Reported;
    [Test] procedure ExceptionCreateResFmt_NoRaise_Reported;
    [Test] procedure ParenlessCreate_NoRaise_Reported;
    [Test] procedure RaisedCreateFmt_NoFinding;
    [Test] procedure MultipleExceptionCreates_AllReported;

    // ---- Negative Varianten / Guards --------------------------------------
    [Test] procedure RaisedException_NoFinding;
    // Core-Audit [7]/[SCA120] 2026-07-17: raise INNERHALB einer anonymen
    // Methode, die als Call-Argument uebergeben wird (Flachtext im nkCall.Name).
    [Test] procedure RaiseInsideAnonMethodArg_NoFinding;
    [Test] procedure NonExceptionCreate_NoFinding;
    [Test] procedure EditCreate_NotMisidentified_NoFinding;
    [Test] procedure EncodingClass_NotMisidentified_NoFinding;
    // Real-World 2026-06-27 FP-Klassen: eigene 'constructor EFoo.Create'-
    // Definition (mORMot/JVCL) + Exception als Argument eines anderen Calls.
    [Test] procedure ConstructorDefinition_NoFinding;
    [Test] procedure ExceptionAsArgument_NoFinding;
    // Review-MEDIUM 2026-08-09: '.Create' innerhalb eines String-Literals.
    [Test] procedure CreateInsideStringLiteral_NoFinding;

    // ---- Finding-Inhalt ----------------------------------------------------
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestMissingRaise.ExceptionCreate_NoRaise_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin Exception.Create(''boom''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMissingRaise));
  finally F.Free; end;
end;

procedure TTestMissingRaise.SpecificExceptionCreate_NoRaise_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin EConvertError.Create(''bad input''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMissingRaise));
  finally F.Free; end;
end;

procedure TTestMissingRaise.ExceptionCreateWithFormatArg_NoRaise_Reported;
// Variante: .Create mit Format-ARGUMENT. Hiess bis zum Voll-Review
// 2026-09-12 'ExceptionCreateFmt_NoRaise_Reported' und suggerierte
// damit eine Abdeckung von '.CreateFmt', die es nie gab (Major 77) -
// die wirkliche CreateFmt-Form steht jetzt in
// ExceptionCreateFmtVariant_NoRaise_Reported.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(x: Integer);'#13#10 +
  'begin EFooBar.Create(Format(''%d'', [x])); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMissingRaise));
  finally F.Free; end;
end;

procedure TTestMissingRaise.MultipleExceptionCreates_AllReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  EOne.Create(''a'');'#13#10 +
  '  ETwo.Create(''b'');'#13#10 +
  '  EThree.Create(''c'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(3, TFindingHelper.Count(F, fkMissingRaise));
  finally F.Free; end;
end;

procedure TTestMissingRaise.RaisedException_NoFinding;
// Korrekt: raise konsumiert den Call - kein nkCall-Knoten entsteht.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin raise EConvertError.Create(''bad input''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingRaise));
  finally F.Free; end;
end;

procedure TTestMissingRaise.RaiseInsideAnonMethodArg_NoFinding;
// Regression Core-Audit 2026-07-17: eine anonyme Methode, die als Argument an
// einen Aufruf uebergeben wird, landet als FLACHER Text im nkCall.Name des
// aeusseren Aufrufs (der Parser legt hier KEINEN nkRaise-Knoten an). Ein 'raise
// EFoo.Create(...)' im Body wird also von SCA120 als nkCall-Text gesehen. Seit
// dem JoinTokInto-Fix [7] steht dort 'raise Exception' (mit Space) statt
// verklebt 'raiseException' -> ExtractCreateTarget extrahiert 'Exception' sauber
// und muss am vorangehenden 'raise' erkennen, dass die Exception GERAIST wird
// (sonst FP "constructed but never raised"). Spiegelt den realen FP aus
// delphimvcframework RoutesU.MapGet('/throw', function begin raise ... end).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  Router.MapGet(''/throw'','#13#10 +
  '    function: Integer'#13#10 +
  '    begin'#13#10 +
  '      raise Exception.Create(''boom'');'#13#10 +
  '    end);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingRaise),
    'raise innerhalb einer Anon-Method-Arg-Closure ist geraist - kein Missing-Raise');
  finally F.Free; end;
end;

procedure TTestMissingRaise.NonExceptionCreate_NoFinding;
// TStringList.Create ist kein Exception-Constructor.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin TStringList.Create; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingRaise));
  finally F.Free; end;
end;

procedure TTestMissingRaise.EditCreate_NotMisidentified_NoFinding;
// 'Edit' beginnt mit E, aber 2. Zeichen ist Kleinbuchstabe - keine
// Delphi-Exception-Konvention.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(AOwner: TComponent);'#13#10 +
  'begin Edit.Create(AOwner); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingRaise));
  finally F.Free; end;
end;

procedure TTestMissingRaise.EncodingClass_NotMisidentified_NoFinding;
// 'Encoding' - klein nach E. Kein Exception.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin Encoding.Create; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingRaise));
  finally F.Free; end;
end;

procedure TTestMissingRaise.ConstructorDefinition_NoFinding;
// mORMot-Muster: Exception-Klasse mit mehrzeiligem Custom-Konstruktor
// (const-Params, komplexe Typen, ueberladener CreateUtf8, inherited-Body).
// Bei solchen Signaturen laeuft der Parser in den Statement-Fallback und der
// qualifizierte Header 'EMongo...Create(const aMsg: ...; aConn: ...)' landet
// als nkCall - darf NICHT als Missing-Raise feuern (Typ-Annotation im
// Argument = Konstruktor-Definition). Real-World 2026-06-27.
const SRC =
  'unit t; interface'#13#10 +
  'type EMongoConnectionException = class(Exception)'#13#10 +
  '  constructor Create(const aMsg: RawUtf8; aConn: TObject);'#13#10 +
  '  constructor CreateUtf8(const Fmt: RawUtf8; const Args: array of const);'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'constructor EMongoConnectionException.Create(const aMsg: RawUtf8;'#13#10 +
  '  aConn: TObject);'#13#10 +
  'begin'#13#10 +
  '  inherited CreateU(aMsg);'#13#10 +
  '  FConn := aConn;'#13#10 +
  'end;'#13#10 +
  'constructor EMongoConnectionException.CreateUtf8(const Fmt: RawUtf8;'#13#10 +
  '  const Args: array of const);'#13#10 +
  'begin'#13#10 +
  '  inherited CreateUtf8(Fmt, Args);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingRaise),
    'mehrzeiliger Custom-Exception-Konstruktor ist kein Missing-Raise');
  finally F.Free; end;
end;

procedure TTestMissingRaise.ExceptionAsArgument_NoFinding;
// Exception als ARGUMENT eines anderen Calls (Handler/Logger) -> wird
// weitergereicht, kein statement-level Missing-Raise.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin Application.ShowException(EConvertError.Create(''x'')); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingRaise),
    'Exception als Call-Argument ist kein statement-level Missing-Raise');
  finally F.Free; end;
end;

procedure TTestMissingRaise.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin EConvertError.Create(''x''); end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkMissingRaise then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkMissingRaise finding expected');
    Assert.AreEqual(fkMissingRaise, Hit.Kind);
    Assert.AreEqual(lsError,        Hit.Severity);
  finally F.Free; end;
end;

procedure TTestMissingRaise.CreateInsideStringLiteral_NoFinding;
// Review-MEDIUM 2026-08-09: 'EFoo.Create' INNERHALB eines String-Literals
// (Log-Meldung) ist kein Konstruktor-Aufruf. Der Parser legt Literale via
// QuoteStrLit in den nkCall-Namen - vor dem Fix passierte das Quote-Zeichen
// vor dem Ident den Guard und 'EParseFault' wurde als never-raised gemeldet.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure ReportParseFailure;'#13#10 +
  'begin Diag.Warn(''EParseFault.Create failed here''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingRaise),
    '''.Create'' im String-Literal ist kein Missing-Raise');
  finally F.Free; end;
end;

procedure TTestMissingRaise.ExceptionCreateFmtVariant_NoRaise_Reported;
// Voll-Review 2026-09-12 (Major 77): es wurde ausschliesslich das
// blanke '.Create' erkannt - hinter '.Create' stand bei '.CreateFmt'
// ein 'F' und die Grenzpruefung schlug fehl, der Fund entfiel
// komplett (Bestands-Exe: 0 Funde auf dieser Fixture, empirisch
// belegt; CreateFmt ist bei Exceptions die haeufigste Variante).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(s: string);'#13#10 +
  'begin EConvertError.CreateFmt(''bad %s'', [s]); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMissingRaise),
    'CreateFmt ohne raise ist derselbe Bug wie Create ohne raise');
  finally F.Free; end;
end;

procedure TTestMissingRaise.ExceptionCreateResFmt_NoRaise_Reported;
// Geschwisterform mit dem LAENGEREN Suffix - pinnt zugleich die
// Reihenfolge der Suffix-Liste: wuerde 'Res' vor 'ResFmt' greifen,
// stuende hinter dem Suffix ein 'F' statt der Klammer (Bestands-Exe:
// 0 Funde, empirisch belegt).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(s: string);'#13#10 +
  'begin EConvertError.CreateResFmt(@SBadArg, [s]); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMissingRaise),
    'CreateResFmt ohne raise muss gemeldet werden');
  finally F.Free; end;
end;

procedure TTestMissingRaise.ParenlessCreate_NoRaise_Reported;
// Voll-Review 2026-09-12 (Major 78): die Suchschleife endete eine
// Position zu frueh, der Punkt eines auf '.Create' ENDENDEN Namens
// wurde nie geprueft und der eigens dafuer gebaute Sonderfall-Zweig
// war toter Code.
//
// Dass die Form ueberhaupt einen nkCall erzeugt, ist an der
// Bestands-Exe GEMESSEN statt vermutet: 'EOutOfMemory.Create()'
// meldet, 'EOutOfMemory.Create;' nicht - die einzige Differenz ist
// das Namensende. Ein abschliessendes ';' im Namen scheidet aus, das
// pruefte schon die alte Grenzpruefung.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin'#13#10 +
  '  EOutOfMemory.Create;'#13#10 +
  '  x := 1;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMissingRaise),
    'klammerloser Konstruktor-Aufruf ohne raise ist derselbe Bug');
  finally F.Free; end;
end;

procedure TTestMissingRaise.RaisedCreateFmt_NoFinding;
// Gegenrichtung zu Major 77: die GERAISETE Variante darf durch die
// Suffix-Erweiterung nicht zum Fund werden (der Parser legt
// 'raise X.CreateFmt(...)' als nkRaise ab, es entsteht kein nkCall -
// dieser Test pinnt das fuer die neuen Suffixe mit).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(s: string);'#13#10 +
  'begin raise EConvertError.CreateFmt(''bad %s'', [s]); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingRaise),
    'geraistes CreateFmt ist kein Fund');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMissingRaise);

end.
