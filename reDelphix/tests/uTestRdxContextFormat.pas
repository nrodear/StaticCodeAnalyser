unit uTestRdxContextFormat;

// Code-Aktion ohne Fund C16 "Format() aus Verkettung bilden" (Charge N,
// 2026-10-25; uRdxContextRunner, ckConcatToFormat): die '+'-Kette am Caret
// ueber TRdxPlacesRunner.DescribeAnchor/FormatRewrite - dieselbe Kette wie
// die Fund-Hilfe SCA044. Der Caret steht als CARET_MARK '{^}' im Text
// (uTestRdxTextKit.CaretOf), VOR dem Zeichen hinter der Marke.
//
// Erste Fixture (reDelphix.Test UND FPC-Pruefstand; dort gegen den Stub-
// Parser, der keine Typen kennt - IntToStr(N) mit N: Integer wird darum nur
// unter Delphi %d): Angebot mit Umwandlung und mit mehreren Literalen,
// Zuweisung und Argument, '%' und Apostroph, fehlendes System.SysUtils;
// Gegenproben: triviale Kette, FloatToStr bleibt %s, Variant-Anzeichen und
// Kommentar im Bereich gesperrt, Kette nur aus Literalen, Kommentar und
// String am Caret, Caret ausserhalb der Kette, Aufruf mit mehreren
// Argumenten, Sperre der ganzen Datei (uses mit Direktive) ohne Eintrag -
// die Fund-Hilfe SCA044 nennt dort weiter den Grund -, ohne Dienst kein
// Eintrag, die Vorprobe WantsPlaces; jede Ersetzung beginnt auf einem
// Zeichen (nie auf einer leeren Zeile); der Menuetext ist die msgid des
// SCA044-Rezepts (Quelltext von uRdxActionCore und uRdxFixTable gelesen;
// bis E3, 2026-10-28, stand das Rezept in uRdxProvider).
// Zweite Fixture (nur Delphi, echter Parser und Typen): ContextCaption,
// Variant-Lokale, mehrzeilige Kette am Caret der Fortsetzungszeile, und die
// Ersetzung gleich der des Fund-Wegs (TRdxRecipeRunner.Describe +
// FormatRewrite, Delegation an uRdxPlacesRunner).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxContextFormat = class
  public
    [Test] procedure Offer_ConversionCall;
    [Test] procedure Offer_IntToStrLocal;
    [Test] procedure Offer_TwoLiterals;
    [Test] procedure Offer_CallArgument;
    [Test] procedure Offer_PercentAndQuote;
    [Test] procedure Offer_SysUtilsMissing_UsesEdit;
    [Test] procedure FloatToStr_StaysString;
    [Test] procedure Trivial_NoEntry;
    [Test] procedure OnlyLiterals_NoEntry;
    [Test] procedure VariantTell_Refused;
    [Test] procedure CommentInChain_Refused;
    [Test] procedure CommentAndString_NoEntry;
    [Test] procedure CaretOutsideChain_NoEntry;
    [Test] procedure MultiArgCall_NoEntry;
    [Test] procedure FileWide_NoEntry_Sca044KeepsReason;
    // Fix-Runde 4: SysUtils nur bedingt, die Kette im selben Zweig.
    [Test] procedure SysUtilsInChainBranch_Offered;
    [Test] procedure NoPlaces_NoEntry;
    [Test] procedure WantsPlaces_PlusNearCaret;
    [Test] procedure Caption_IsSca044RecipeCaption;
    [Test] procedure Order_AfterConstant;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxContextFormatDelphi = class
  public
    [Test] procedure Caption_ContextCaptionLikeSca044;
    [Test] procedure VariantLocal_Refused;
    [Test] procedure MultiLine_ContinuationCaret_Offered;
    [Test] procedure SameAsFindingPath;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  uRdxRecipeRunner,      // Describe, FormatRewrite (Fund-Weg)
  uRdxFixTable,          // ContextCaption
  {$ENDIF}
  uFindingActions,       // TEditorContext
  uRefactorInfo,         // TRefactorInfo
  uSourcePlaces,         // TSourcePlaces
  uRdxBufferMath,        // TRdxEdit
  uRdxPlacesRunner,      // DescribeAnchor, FormatRewrite, UsesNamesOf
  uRdxContextRunner,
  uRdxText,              // _
  uTestRdxTextKit;       // Join, Apply, CaretOf, TempName

const
  // Der Kopf der Testunit: implementation-uses mit SysUtils, eine Routine
  // mit Parametern und Lokalen fuer die Ketten.
  HEAD_SYSUTILS = 'SysUtils;';

// Eine Unit mit 'uses <AUses>' im implementation-Teil (ohne Klausel bei
// AUses = '') und der Prozedur P mit dem Rumpf ABody.
function UnitWith(const AUses: string; const ABody: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'implementation']) + #13#10;
  if AUses <> '' then
    Result := Result + Join(['uses', '  ' + AUses]) + #13#10;
  Result := Result + Join(['procedure P(const Name: string; X: Double; '
    + 'Obj: TFoo);', 'var', '  S: string;', '  N: Integer;', 'begin'])
    + #13#10 + Join(ABody) + #13#10 + Join(['end;', 'end.']);
end;

// Ein Dateiname, dessen Verzeichnis es nicht gibt - der Plattenblick der
// Lokalen Konstante (FileReason) findet dort nichts.
function NoDiskFile: string;
begin
  Result := TempName('rdx_ctxfmt_', PathDelim) + 'u.pas';
end;

// Die Eintraege am Caret von AMarked (CARET_MARK); ASource ohne Marke. Der
// Quellstellen-Dienst wird auf demselben Text geoeffnet (AWithPlaces).
function RunAt(const AMarked: string; out ASource: string;
  AWithPlaces: Boolean = True): TArray<TRdxContextOutcome>;
var
  Line, Col : Integer;
  SL        : TStringList;
  Places    : TSourcePlaces;
begin
  ASource := AMarked;
  Assert.IsTrue(CaretOf(ASource, Line, Col), 'Caret-Marke fehlt');
  SL := TStringList.Create;
  Places := TSourcePlaces.Create;
  try
    SL.Text := ASource;
    Assert.IsTrue(Places.OpenSource('u.pas', ASource), 'OpenSource');
    if AWithPlaces then
      Result := TRdxContextRunner.Run(SL,
        TEditorContext.At(NoDiskFile, Line, Col), Places)
    else
      Result := TRdxContextRunner.Run(SL,
        TEditorContext.At(NoDiskFile, Line, Col));
  finally
    Places.Free;
    SL.Free;
  end;
end;

// Zahl der Format-Eintraege in AAll.
function FormatCount(const AAll: TArray<TRdxContextOutcome>): Integer;
var
  O : TRdxContextOutcome;
begin
  Result := 0;
  for O in AAll do
    if O.Kind = ckConcatToFormat then
      Inc(Result);
end;

// Genau EIN Eintrag am Caret, der Format-Eintrag.
function FormatAt(const AMarked: string;
  out ASource: string): TRdxContextOutcome;
var
  All : TArray<TRdxContextOutcome>;
begin
  All := RunAt(AMarked, ASource);
  Assert.AreEqual<Integer>(1, Length(All), 'ein Eintrag: ' + ASource);
  Result := All[0];
  Assert.IsTrue(Result.Kind = ckConcatToFormat, 'Art des Eintrags');
end;

// Kein Format-Eintrag am Caret (andere Arten zaehlen nicht).
procedure AssertNoFormat(const AMarked: string; const AWhat: string);
var
  Src : string;
begin
  Assert.AreEqual<Integer>(0, FormatCount(RunAt(AMarked, Src)), AWhat);
end;

// Jede Ersetzung beginnt auf einem Zeichen der Zeile - nie auf einer
// leeren Zeile oder hinter ihrem Ende.
procedure AssertSpansOnText(const ASource: string;
  const AEdits: TArray<TRdxEdit>);
var
  SL   : TStringList;
  E    : TRdxEdit;
  Text : string;
begin
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    for E in AEdits do
    begin
      Assert.IsTrue((E.Span.StartLine >= 1)
        and (E.Span.StartLine <= SL.Count), 'Zeile der Ersetzung');
      Text := SL[E.Span.StartLine - 1];
      Assert.IsTrue(Trim(Text) <> '', 'Ersetzung auf leerer Zeile');
      Assert.IsTrue((E.Span.StartCol >= 1)
        and (E.Span.StartCol <= Length(Text)), 'Spalte der Ersetzung');
    end;
  finally
    SL.Free;
  end;
end;

// Freigegeben, eine Ersetzung, und das Ergebnis enthaelt AExpected.
procedure AssertOffer(const AMarked, AExpected: string);
var
  Src : string;
  O   : TRdxContextOutcome;
begin
  O := FormatAt(AMarked, Src);
  Assert.IsTrue(O.Enabled, 'freigegeben: ' + O.Reason);
  Assert.AreEqual<Integer>(1, Length(O.Edits), 'eine Ersetzung');
  Assert.IsTrue(O.Hint <> '', 'Hinweis');
  Assert.IsFalse(O.ChangesBehavior, 'bedeutungsgleich');
  AssertSpansOnText(Src, O.Edits);
  Assert.IsTrue(Pos(AExpected, Apply(Src, O.Edits)) > 0,
    Apply(Src, O.Edits));
end;

// Gesperrt mit Grund.
function AssertRefused(const AMarked: string): string;
var
  Src : string;
  O   : TRdxContextOutcome;
begin
  O := FormatAt(AMarked, Src);
  Assert.IsFalse(O.Enabled, 'gesperrt');
  Assert.IsTrue(O.Reason <> '', 'mit Grund');
  Assert.AreEqual<Integer>(0, Length(O.Edits), 'ohne Ersetzung');
  Result := O.Reason;
end;

// ---- TTestRdxContextFormat ----

procedure TTestRdxContextFormat.Offer_ConversionCall;
begin
  // Ein Literal vorn, eins hinten und eine Umwandlung; Obj.Count ist kein
  // nackter Bezeichner - IntToStr(..) bleibt Argument von %s (Delphi wie
  // FPC). Der Caret darf auf jedem Term stehen.
  AssertOffer(UnitWith(HEAD_SYSUTILS,
    ['  S := ''Count: '' + IntTo{^}Str(Obj.Count) + '' items'';']),
    '  S := Format(''Count: %s items'', [IntToStr(Obj.Count)]);');
  AssertOffer(UnitWith(HEAD_SYSUTILS,
    ['  S := {^}''Count: '' + IntToStr(Obj.Count);']),
    '  S := Format(''Count: %s'', [IntToStr(Obj.Count)]);');
  // Direkt hinter dem letzten Term.
  AssertOffer(UnitWith(HEAD_SYSUTILS,
    ['  S := ''Count: '' + IntToStr(Obj.Count){^};']),
    '  S := Format(''Count: %s'', [IntToStr(Obj.Count)]);');
end;

procedure TTestRdxContextFormat.Offer_IntToStrLocal;
begin
  // Ein Literal und IntToStr(N) - Kandidat. Mit bewiesenem Integer (der
  // echte Parser, Delphi) wird daraus %d mit N; der Stub kennt keine Typen,
  // IntToStr(N) bleibt Argument von %s. Beides bedeutungsgleich.
  AssertOffer(UnitWith(HEAD_SYSUTILS, ['  S := ''N='' + IntToStr({^}N);']),
    {$IFDEF FPC}
    '  S := Format(''N=%s'', [IntToStr(N)]);'
    {$ELSE}
    '  S := Format(''N=%d'', [N]);'
    {$ENDIF});
end;

procedure TTestRdxContextFormat.Offer_TwoLiterals;
begin
  // Zwei Literale um einen String-Parameter, ohne Umwandlung.
  AssertOffer(UnitWith(HEAD_SYSUTILS,
    ['  S := ''Hello '' + Na{^}me + ''!'';']),
    '  S := Format(''Hello %s!'', [Name]);');
  // Selbst-Anhaengen: X bleibt vorn, Format ueber den Rest.
  AssertOffer(UnitWith(HEAD_SYSUTILS,
    ['  S := S + '' ['' + {^}Name + '']'';']),
    '  S := S + Format('' [%s]'', [Name]);');
end;

procedure TTestRdxContextFormat.Offer_CallArgument;
begin
  // Das eine Argument eines Aufrufs (CallOf, wie bei SCA003).
  AssertOffer(UnitWith(HEAD_SYSUTILS,
    ['  ShowMessage(''Count: '' + IntToStr(Obj.{^}Count) + ''.'');']),
    '  ShowMessage(Format(''Count: %s.'', [IntToStr(Obj.Count)]));');
end;

procedure TTestRdxContextFormat.Offer_PercentAndQuote;
begin
  // '%' im Literal wird '%%', der Apostroph bleibt verdoppelt.
  AssertOffer(UnitWith(HEAD_SYSUTILS,
    ['  S := ''100% of '' + Name{^} + '' isn''''t'';']),
    '  S := Format(''100%% of %s isn''''t'', [Name]);');
end;

procedure TTestRdxContextFormat.Offer_SysUtilsMissing_UsesEdit;
var
  Src, After : string;
  O          : TRdxContextOutcome;
begin
  // Ohne SysUtils in der Klausel: die zweite Ersetzung traegt sie nach
  // (Kurzname - die Datei schreibt keine Unit-Scopes; sortiert hinter
  // Classes), wie beim Rezept des Anbieters.
  O := FormatAt(UnitWith('Classes;',
    ['  S := ''a'' + Name + ''{^}b'';']), Src);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual<Integer>(2, Length(O.Edits), 'Kette + uses');
  AssertSpansOnText(Src, O.Edits);
  After := Apply(Src, O.Edits);
  Assert.IsTrue(Pos('  Classes, SysUtils;', After) > 0, After);
  Assert.IsTrue(Pos('  S := Format(''a%sb'', [Name]);', After) > 0, After);
  Assert.IsTrue(Pos('uses SysUtils', O.Hint) > 0, O.Hint);
  // Ganz ohne Klausel: eine neue hinter 'implementation' - auch sie
  // beginnt auf der (nicht leeren) Zeile des Schluesselworts; ohne einen
  // Eintrag schreibt die Datei den qualifizierten Namen (UsesNameFor).
  O := FormatAt(UnitWith('', ['  S := ''a'' + Name + ''{^}b'';']), Src);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual<Integer>(2, Length(O.Edits), 'Kette + neue Klausel');
  AssertSpansOnText(Src, O.Edits);
  After := StringReplace(Apply(Src, O.Edits), #13#10, #10, [rfReplaceAll]);
  Assert.IsTrue(Pos('implementation' + #10 + #10 + 'uses' + #10
    + '  System.SysUtils;', After) > 0, After);
  Assert.IsTrue(Pos('  S := Format(''a%sb'', [Name]);', After) > 0, After);
end;

procedure TTestRdxContextFormat.FloatToStr_StaysString;
begin
  // FloatToStr ist eine Umwandlung (Kandidat), wird aber nicht %g: das
  // formatierte anders - FloatToStr(X) bleibt Argument von %s.
  AssertOffer(UnitWith(HEAD_SYSUTILS,
    ['  S := ''X='' + FloatToStr(X{^});']),
    '  S := Format(''X=%s'', [FloatToStr(X)]);');
end;

procedure TTestRdxContextFormat.Trivial_NoEntry;
var
  Src : string;
begin
  // Ein Literal und ein Ausdruck ohne Umwandlung: kein Kandidat (F4).
  Assert.AreEqual<Integer>(0, Length(RunAt(UnitWith(HEAD_SYSUTILS,
    ['  S := ''a'' + Na{^}me;']), Src)), 'a + Name');
  Assert.AreEqual<Integer>(0, Length(RunAt(UnitWith(HEAD_SYSUTILS,
    ['  S := ''a'' + Name + Obj.{^}Caption;']), Src)), 'ein Literal');
  // Ohne Literal - auch mit Umwandlung - keiner.
  Assert.AreEqual<Integer>(0, Length(RunAt(UnitWith(HEAD_SYSUTILS,
    ['  S := Name + IntToStr({^}N);']), Src)), 'ohne Literal');
end;

procedure TTestRdxContextFormat.OnlyLiterals_NoEntry;
var
  Src : string;
begin
  // Nur Literale (BuildFormatCall: NoOperand) - auch hinter 'X +'.
  Assert.AreEqual<Integer>(0, Length(RunAt(UnitWith(HEAD_SYSUTILS,
    ['  S := ''a'' + ''b{^}'';']), Src)), 'Literale');
  Assert.AreEqual<Integer>(0, Length(RunAt(UnitWith(HEAD_SYSUTILS,
    ['  S := S + ''a'' + {^}''b'';']), Src)), 'Literale hinter S +');
end;

procedure TTestRdxContextFormat.VariantTell_Refused;
begin
  // Variant-Anzeichen (DS['Name'] = FieldValues, .Value) sperren wie bei
  // SCA044: ist der Wert Null, wirft die Kette - Format gaebe still aus.
  AssertRefused(UnitWith(HEAD_SYSUTILS,
    ['  S := ''Name: '' + Obj[''Name''] + {^}''.'';']));
  AssertRefused(UnitWith(HEAD_SYSUTILS,
    ['  S := ''V: '' + Obj.Field.Va{^}lue + ''.'';']));
end;

procedure TTestRdxContextFormat.CommentInChain_Refused;
begin
  // Ein Kommentar im ersetzten Bereich ginge verloren: gesperrt mit dem
  // Grund der Fund-Hilfe.
  Assert.AreEqual(_('comment in the range'), AssertRefused(
    UnitWith(HEAD_SYSUTILS,
    ['  S := ''a'' + {alt} IntToStr({^}N) + ''b'';'])));
end;

procedure TTestRdxContextFormat.CommentAndString_NoEntry;
begin
  // Die Kette steht nur in einem Kommentar bzw. String.
  AssertNoFormat(UnitWith(HEAD_SYSUTILS,
    ['  // S := ''a'' + IntTo{^}Str(N) + ''b'';', '  S := Name;']),
    'Zeilenkommentar');
  AssertNoFormat(UnitWith(HEAD_SYSUTILS,
    ['  S := ''x := ''''a'''' + IntTo{^}Str(N)'';']), 'im String');
  // Echte Kette davor, der Caret im Kommentar dahinter.
  AssertNoFormat(UnitWith(HEAD_SYSUTILS,
    ['  S := ''a'' + IntToStr(N) + ''b''; // ''x'' + {^}y']),
    'Kommentar hinter der Kette');
end;

procedure TTestRdxContextFormat.CaretOutsideChain_NoEntry;
begin
  // Auf dem Ziel bzw. dem ':=' steht der Caret nicht in der Kette.
  AssertNoFormat(UnitWith(HEAD_SYSUTILS,
    ['  {^}S := ''a'' + IntToStr(N) + ''b'';']), 'Ziel');
  AssertNoFormat(UnitWith(HEAD_SYSUTILS,
    ['  S :{^}= ''a'' + IntToStr(N) + ''b'';']), ':=');
  // Eine Zeile ohne Anweisung unter der Kette: die Zeile darueber endet
  // mit ';', die Suche nach dem Anfang der Anweisung geht nicht hinauf.
  AssertNoFormat(UnitWith(HEAD_SYSUTILS,
    ['  S := ''a'' + IntToStr(N) + ''b'';', '  {^}']),
    'Zeile unter der Anweisung');
end;

procedure TTestRdxContextFormat.MultiArgCall_NoEntry;
begin
  // Ein Aufruf mit mehreren Argumenten zerfaellt in ROLE_ARGUMENT - keine
  // Kette (CallOf beschreibt nur ein einziges Argument als Kette).
  AssertNoFormat(UnitWith(HEAD_SYSUTILS,
    ['  Log(''a'' + IntToStr({^}N) + ''b'', 3);']), 'zwei Argumente');
end;

// Die Fund-Hilfe (SCA044) fuer die Kette der Zeile mit '  S := ' in
// AMarked (die Caret-Marke faellt weg): DescribeAnchor + FormatRewrite.
function FindingFormat(const AMarked: string): TRdxFormatOutcome;
var
  Src    : string;
  Places : TSourcePlaces;
  Info   : TRefactorInfo;
  IsCall : Boolean;
  Why    : string;
begin
  Places := TSourcePlaces.Create;
  try
    Src := StringReplace(AMarked, CARET_MARK, '', []);
    Assert.IsTrue(Places.OpenSource('u.pas', Src), 'OpenSource');
    Info := TRdxPlacesRunner.DescribeAnchor(Places,
      LineOf(Src, '  S := '), 'assign', IsCall, Why);
    try
      Result := TRdxPlacesRunner.FormatRewrite(Places, Info, Why,
        TRdxPlacesRunner.UsesNamesOf(Places));
    finally
      Info.Free;
    end;
  finally
    Places.Free;
  end;
end;

procedure TTestRdxContextFormat.FileWide_NoEntry_Sca044KeepsReason;
var
  Src     : string;
  Outcome : TRdxFormatOutcome;
begin
  // SysUtils fehlt, und jeder Eintrag der Klausel steht in einem
  // bedingten Zweig: die Einfuegung ist nirgends planbar - das gilt jeder
  // Kette der Datei, kein Eintrag. Bis rwE31 'Classes {$IFDEF X},
  // Foo{$ENDIF};' - seitdem geht 'SysUtils, Classes' (Classes steht
  // ausserhalb jedes Zweigs, PlanIntoClause/UnconditionalPlace).
  Src := UnitWith('{$IFDEF X}Foo{$ELSE}Classes{$ENDIF};',
    ['  S := ''a'' + Name + ''{^}b'';']);
  AssertNoFormat(Src, 'uses mit Direktive');
  // Die Fund-Hilfe (dieselbe Kette) nennt den Grund weiter.
  Outcome := FindingFormat(Src);
  Assert.IsFalse(Outcome.Enabled, 'gesperrt');
  Assert.IsTrue(Outcome.FileWide, 'ganze Datei');
  Assert.IsTrue(Pos('System.SysUtils', Outcome.Reason) > 0, Outcome.Reason);
end;

// Fix-Runde 4 (Folge rwE31): SysUtils steht nur unter '{$IFDEF RDX_X}' in
// uses, und derselbe Zweig umschliesst die Kette - dort ist es
// eingebunden: Eintrag frei, nur die Kette, keine uses-Ersetzung. Bis
// dahin fragte FormatUsesReason PlanUses ohne Zeile: R_USES_CONDITIONAL,
// FileWide, kein Eintrag (rot ohne Fix). Den Eintrag verlieren beide
// Baeume: der Delphi-Parser bricht die Klausel am Glied 'Foo.Abstract' ab
// (rwE29), der Stub des FPC-Pruefstands sieht eine Klausel nur, wenn die
// Zeile mit 'uses' beginnt. Gegenprobe: der Zweig endet hinter der
// Klausel - kein Eintrag, die Fund-Hilfe nennt R_USES_CONDITIONAL mit der
// Zeile des Eintrags (5).
procedure TTestRdxContextFormat.SysUtilsInChainBranch_Offered;
const
  BODY = 'procedure P(const Name: string);'#13#10'var'#13#10'  S: string;'
    + #13#10'begin'#13#10'  S := ''a'' + Name + ''{^}b'';'#13#10'end;';
var
  Src, Marked : string;
  O           : TRdxContextOutcome;
  Outcome     : TRdxFormatOutcome;
begin
  Marked := Join(['unit u;', '{$IFDEF RDX_X}', 'interface uses',
    '  Foo.Abstract,', '  SysUtils;', 'implementation', BODY,
    '{$ENDIF RDX_X}', 'end.']);
  O := FormatAt(Marked, Src);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual<Integer>(1, Length(O.Edits), 'nur die Kette');
  Assert.AreEqual<Integer>(0, Pos(' + uses', O.Hint), O.Hint);
  Outcome := FindingFormat(Marked);
  Assert.IsTrue(Outcome.Enabled, Outcome.Reason);
  Assert.IsFalse(Outcome.NeedsUses, 'SysUtils ist im Zweig da');
  // Gegenprobe: die Kette ausserhalb des Zweigs.
  Marked := Join(['unit u;', 'interface', '{$IFDEF RDX_X} uses',
    '  Foo.Abstract,', '  SysUtils;', '{$ENDIF RDX_X}', 'implementation',
    BODY, 'end.']);
  AssertNoFormat(Marked, 'Kette ausserhalb des Zweigs');
  Outcome := FindingFormat(Marked);
  Assert.IsFalse(Outcome.Enabled, 'gesperrt');
  Assert.IsTrue(Outcome.FileWide, 'ganze Datei');
  Assert.AreEqual(_('%s is missing in uses: %s', ['System.SysUtils',
    _(R_USES_CONDITIONAL, [5, MsgByHand])]), Outcome.Reason);
end;

procedure TTestRdxContextFormat.NoPlaces_NoEntry;
var
  Src : string;
begin
  // Ohne Quellstellen-Dienst gibt es keinen Format-Eintrag - die
  // Text-Aktionen bleiben (hier keine: kein Zahl-Literal, kein Create).
  Assert.AreEqual<Integer>(1, Length(RunAt(UnitWith(HEAD_SYSUTILS,
    ['  S := ''a'' + IntToStr({^}N) + ''b'';']), Src)), 'mit Dienst');
  Assert.AreEqual<Integer>(0, Length(RunAt(UnitWith(HEAD_SYSUTILS,
    ['  S := ''a'' + IntToStr({^}N) + ''b'';']), Src, False)), 'ohne Dienst');
end;

procedure TTestRdxContextFormat.WantsPlaces_PlusNearCaret;
var
  SL  : TStringList;
  Src : string;
  L   : Integer;
begin
  Src := UnitWith(HEAD_SYSUTILS, ['  S := ''a'' +', '    IntToStr(N);',
    '  N := 1;', '  S := Name; // a + b', '  S := ''a+b'';']);
  SL := TStringList.Create;
  try
    SL.Text := Src;
    L := LineOf(Src, '    IntToStr(N);');
    // Die Zeile selbst traegt kein '+', die darueber schon.
    Assert.IsTrue(TRdxContextRunner.WantsPlaces(SL,
      TEditorContext.At('u.pas', L, 5)), 'Fortsetzungszeile');
    // Zwei Zeilen unter dem '+' (und darunter ein '+' im Kommentar): nein.
    Assert.IsFalse(TRdxContextRunner.WantsPlaces(SL,
      TEditorContext.At('u.pas', L + 1, 3)), 'zwei Zeilen darunter');
    // '+' nur in Kommentar und String, Nachbarn ohne '+'.
    Assert.IsFalse(TRdxContextRunner.WantsPlaces(SL,
      TEditorContext.At('u.pas', LineOf(Src, '  S := ''a+b'';'), 3)),
      'nur in String und Kommentar');
    Assert.IsFalse(TRdxContextRunner.WantsPlaces(SL,
      TEditorContext.At('u.pas', 1, 1)), 'Kopf der Unit');
  finally
    SL.Free;
  end;
end;

// Der Wert der ersten Konstante ANAME = '...' in der Datei AUnit des
// Moduls (reDelphix\source), vom Arbeitsverzeichnis und von der Exe aus
// aufwaerts gesucht; '' = nicht gefunden.
function SourceConst(const AUnit, AName: string): string;
const
  MAX_UP = 6;
var
  Starts : array[0..1] of string;
  Dir, F : string;
  SL     : TStringList;
  s, k, i: Integer;
  T      : string;
begin
  Result := '';
  Starts[0] := GetCurrentDir;
  Starts[1] := ExtractFileDir(ParamStr(0));
  F := '';
  for s := Low(Starts) to High(Starts) do
  begin
    Dir := Starts[s];
    for k := 0 to MAX_UP do
    begin
      F := IncludeTrailingPathDelimiter(Dir) + 'source' + PathDelim + AUnit;
      if FileExists(F) then Break;
      F := IncludeTrailingPathDelimiter(Dir) + 'reDelphix' + PathDelim
        + 'source' + PathDelim + AUnit;
      if FileExists(F) then Break;
      F := '';
      Dir := ExtractFileDir(Dir);
    end;
    if F <> '' then Break;
  end;
  if F = '' then Exit;
  SL := TStringList.Create;
  try
    SL.LoadFromFile(F);
    for i := 0 to SL.Count - 1 do
    begin
      T := Trim(SL[i]);
      if (Pos(AName, T) = 1) and (Pos('=', T) > 0) then
      begin
        T := Trim(Copy(T, Pos('=', T) + 1, MaxInt));
        if (Length(T) > 2) and (T[1] = '''') and (T[Length(T)] = ';') then
          Exit(Copy(T, 2, Length(T) - 3));
      end;
    end;
  finally
    SL.Free;
  end;
end;

procedure TTestRdxContextFormat.Caption_IsSca044RecipeCaption;
begin
  // Dedup per Caption (F2): der Menuetext der Kontextaktion ist die msgid
  // des SCA044-Rezepts (CAP_FORMAT im Kern des Anbieters) - und die
  // Konstante, die uRdxFixTable.ContextCaption uebersetzt. Gelesen wird der
  // Quelltext, beide Units uebersetzt der FPC-Pruefstand nicht.
  Assert.AreEqual('Build Format() from concatenation', CONTEXT_FORMAT_CAPTION);
  Assert.AreEqual(CONTEXT_FORMAT_CAPTION,
    SourceConst('uRdxActionCore.pas', 'CAP_FORMAT '),
    'uRdxActionCore.CAP_FORMAT');
  Assert.AreEqual(CONTEXT_FORMAT_CAPTION,
    SourceConst('uRdxFixTable.pas', 'CAP_CONTEXT_FORMAT '),
    'uRdxFixTable.CAP_CONTEXT_FORMAT');
  // Uebersetzt wie die Fund-Hilfe (de.po).
  Assert.AreEqual('Format() aus Verkettung bilden', _(CONTEXT_FORMAT_CAPTION));
end;

procedure TTestRdxContextFormat.Order_AfterConstant;
var
  Src : string;
  All : TArray<TRdxContextOutcome>;
begin
  // Ein Zahl-Literal in der Kette: beide Aktionen, Format zuletzt (die
  // Reihenfolge von TRdxContextKind).
  All := RunAt(UnitWith(HEAD_SYSUTILS,
    ['  S := ''a'' + IntToStr(N * 4{^}2) + ''b'';']), Src);
  Assert.AreEqual<Integer>(2, Length(All), 'zwei Eintraege');
  Assert.IsTrue(All[0].Kind = ckIntroduceConst, 'Konstante zuerst');
  Assert.IsTrue(All[1].Kind = ckConcatToFormat, 'Format zuletzt');
  Assert.IsTrue(All[1].Enabled, All[1].Reason);
end;

{$IFNDEF FPC}

// ---- TTestRdxContextFormatDelphi ----

procedure TTestRdxContextFormatDelphi.Caption_ContextCaptionLikeSca044;
var
  O : TRdxContextOutcome;
begin
  O := Default(TRdxContextOutcome);
  O.Kind := ckConcatToFormat;
  O.Name := 'S';
  Assert.AreEqual(_(CONTEXT_FORMAT_CAPTION), TRdxFixTable.ContextCaption(O));
  // Auch gesperrt derselbe Text (der Grund steht im Hint).
  O.Enabled := False;
  O.Reason := 'x';
  Assert.AreEqual(_(CONTEXT_FORMAT_CAPTION), TRdxFixTable.ContextCaption(O));
end;

procedure TTestRdxContextFormatDelphi.VariantLocal_Refused;
var
  Src : string;
  O   : TRdxContextOutcome;
begin
  // Eine deklarierte Variant-Lokale sperrt (echter Typ-Resolver).
  O := FormatAt(Join(['unit u;', 'interface', 'implementation', 'uses',
    '  SysUtils;', 'procedure P;', 'var', '  S: string;', '  V: Variant;',
    'begin', '  S := ''a'' + {^}V + ''b'';', 'end;', 'end.']), Src);
  Assert.IsFalse(O.Enabled, 'Variant gesperrt');
  Assert.IsTrue(O.Reason <> '', 'mit Grund');
end;

procedure TTestRdxContextFormatDelphi.MultiLine_ContinuationCaret_Offered;
var
  Src : string;
  O   : TRdxContextOutcome;
begin
  // Der Caret auf der Fortsetzungszeile: die Anweisung beginnt zwei Zeilen
  // darueber.
  O := FormatAt(UnitWith(HEAD_SYSUTILS, ['  S := ''Count: '' +',
    '    IntToStr(Obj.Count) +', '    '' it{^}ems'';']), Src);
  Assert.IsTrue(O.Enabled, O.Reason);
  AssertSpansOnText(Src, O.Edits);
  Assert.IsTrue(Pos('Format(''Count: %s items'', [IntToStr(Obj.Count)])',
    Apply(Src, O.Edits)) > 0, Apply(Src, O.Edits));
end;

procedure TTestRdxContextFormatDelphi.SameAsFindingPath;
var
  Src, Marked : string;
  O           : TRdxContextOutcome;
  Places      : TSourcePlaces;
  Info        : TRefactorInfo;
  IsCall      : Boolean;
  Why         : string;
  Fix         : TRdxFormatOutcome;
begin
  // Dieselbe Kette wie die Fund-Hilfe SCA044: der Fund-Weg des Anbieters
  // (TRdxRecipeRunner.Describe + FormatRewrite, delegiert) ersetzt
  // denselben Bereich durch denselben Text.
  Marked := UnitWith(HEAD_SYSUTILS,
    ['  S := ''a'' + Name + ''b'' + {^}IntToStr(N) + ''c'';']);
  O := FormatAt(Marked, Src);
  Assert.IsTrue(O.Enabled, O.Reason);
  Places := TSourcePlaces.Create;
  try
    Assert.IsTrue(Places.OpenSource('u.pas', Src), 'OpenSource');
    Info := TRdxRecipeRunner.DescribeAnchor(Places, LineOf(Src, '  S := '),
      'assign', IsCall, Why);
    try
      Fix := TRdxRecipeRunner.FormatRewrite(Places, Info, Why,
        TRdxRecipeRunner.UsesNamesOf(Places));
    finally
      Info.Free;
    end;
  finally
    Places.Free;
  end;
  Assert.IsTrue(Fix.Enabled, Fix.Reason);
  Assert.AreEqual(Fix.NewText, O.Edits[0].NewText);
  Assert.AreEqual(Fix.Expected, O.Edits[0].Expected);
  Assert.AreEqual<Integer>(Fix.Span.StartLine, O.Edits[0].Span.StartLine);
  Assert.AreEqual<Integer>(Fix.Span.StartCol, O.Edits[0].Span.StartCol);
  Assert.AreEqual(Fix.Hint, O.Hint);
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxContextFormat);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxContextFormatDelphi);
  {$ENDIF}

end.
