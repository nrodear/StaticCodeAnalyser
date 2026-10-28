unit uTestRdxActionCore;

// Der Kern des Anbieters (uRdxActionCore, Entscheid E3 vom 2026-10-28):
// bis dahin rechnete uRdxProvider die Eintraege zu einem Fund selbst, mit
// ToolsAPI - kein Test erreichte den Ablauf (reDelphix.Test laesst
// uRdxProvider draussen). Seit dem Herausloesen fragen IDE und Probe
// (tools\probe\RdxActionProbe) DENSELBEN Kern; diese Tests sichern den
// Umbau ab, indem sie die Eintraege gegen die Bausteine vergleichen, die
// der Anbieter vorher selbst rief:
//   * einfache Hilfe mit zweitem Eintrag (SCA017): Menuetext, Hinweis,
//     Kennzeichnung und Ersetzungen gleich TRdxFixTable.FixFor bzw.
//     AlternativeFixFor + CaptionFor, Variante 0/1, danach Unterdruecken
//   * Rezept mit Anker (SCA044, echte Detektor-Meldung): 'Stelle zeigen'
//     (fakNavigate, Bereich aus TRdxRecipeRunner.Describe) und Format()
//     gleich FormatRewrite
//   * gesperrter Eintrag mit Grund (SCA165, Marker mit mehreren Arten)
//   * Parser scheitert (Watchdog) bzw. Quelle nicht lesbar: nur der
//     Diagnose-Eintrag, dahinter die Text-Rezepte (SCA165) und
//     Unterdruecken - keine Baum-Rezepte, die Quelle bleibt zu
//   * Regel ohne Hilfe: "reDelphix: <Regel>: kein fixMode", Unterdruecken
//   * uses-Zeile ohne Lieferanten der Projekt-Units (die Probe): kein
//     Umbau, UsesSkipped; mit Lieferant der Umbau-Eintrag wie bisher
//   * der gemeinsame Text MsgTooLongForEditor (bis E3 S_TOO_LONG in
//     uRdxEditor)
// Nur Delphi (anonyme Methoden im Kern, echter Parser mit Watchdog).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxActionCore = class
  public
    [Test] procedure SimpleFix_MainAndAlt_LikeFixTable;
    [Test] procedure Sca044_ShowSpanAndFormat_LikeRunner;
    [Test] procedure RemoveMarker_Blocked_WithReason;
    [Test] procedure ParserWatchdog_OnlyDiagnosisAndSuppress;
    [Test] procedure SourceNotReadable_TextRecipeStays;
    [Test] procedure RuleWithoutHelp_DiagnosisThenSuppress;
    [Test] procedure UsesLine_WithoutProjectUnits_Skipped;
    [Test] procedure FindingDiagnosis_NonPascalAndNoLine;
    [Test] procedure TextMsg_TooLongForEditor;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uParser2,
  uMethodd12,         // TLeakFinding
  uSCAConsts,         // fk*
  uFindingActions,    // fakFix ...
  uConcatToFormat,    // TConcatToFormatDetector (SCA044)
  uEngineApi,         // TSourcePlaces, TScanRequest
  uRefactorInfo,
  uRdxText,           // _(), MsgTooLongForEditor, SetRdxLanguageOverride
  uRdxScopeTable,     // TRdxScopeTable, TRdxProjectUnits
  uRdxBufferMath,     // TRdxEdit, TRdxTextSource
  uRdxRecipeRunner,   // TRdxFixOutcome, Describe, FormatRewrite
  uRdxFixTable,       // FixFor, AlternativeFixFor, CaptionFor
  uRdxActionCore,
  uTestRdxTextKit;    // Join, TempName, WriteText, LineOf

const
  // Eine Unit mit EINER Routine Foo; Rumpf ab Zeile 6 (wie
  // uTestRdxDebugOutputFix.Wrap).
  BODY = 6;

function Wrap(const ABody: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation', 'procedure Foo;',
    'begin']) + #13#10 + Join(ABody) + #13#10 + Join(['end;', 'end.']);
end;

function LinesOf(const ASource: string): TStringList;
begin
  Result := TStringList.Create;
  Result.Text := ASource;
end;

// Die Eintraege des Kerns fuer AFinding auf ASource (Editor-Puffer, wie
// eine offene Datei); ohne Protokoll, mit optionalem Lieferanten.
function DescribeIn(const ASource: string; AFinding: TLeakFinding;
  AScopes: TRdxScopeTable; const AUnits: TRdxProjectUnitsSource;
  out AUsesSkipped: Boolean): TArray<TRdxActionEntry>; overload;
var
  Core  : TRdxActionCore;
  Lines : TStringList;
begin
  Lines := nil;
  Core := TRdxActionCore.Create(AScopes);
  try
    Core.Logging := False;
    Core.ProjectUnits := AUnits;
    Lines := LinesOf(ASource);
    Result := Core.Describe(AFinding, Lines, txBuffer, ASource);
    AUsesSkipped := Core.UsesSkipped;
  finally
    Lines.Free;
    Core.Free;
  end;
end;

function DescribeIn(const ASource: string;
  AFinding: TLeakFinding): TArray<TRdxActionEntry>; overload;
var
  Skipped : Boolean;
begin
  Result := DescribeIn(ASource, AFinding, nil, nil, Skipped);
end;

// Wie viele Eintraege des Rezepts ARecipe.
function CountOf(const AEntries: TArray<TRdxActionEntry>;
  const ARecipe: string): Integer;
var
  E : TRdxActionEntry;
begin
  Result := 0;
  for E in AEntries do
    if E.Recipe = ARecipe then Inc(Result);
end;

procedure AssertSameEdits(const AExpected, AActual: TArray<TRdxEdit>;
  const AWhat: string);
var
  i : Integer;
begin
  Assert.AreEqual<Integer>(Length(AExpected), Length(AActual),
    AWhat + ': Zahl der Ersetzungen');
  for i := 0 to High(AExpected) do
  begin
    Assert.AreEqual<Integer>(AExpected[i].Span.StartLine,
      AActual[i].Span.StartLine, AWhat + ': StartLine');
    Assert.AreEqual<Integer>(AExpected[i].Span.StartCol,
      AActual[i].Span.StartCol, AWhat + ': StartCol');
    Assert.AreEqual<Integer>(AExpected[i].Span.EndLine,
      AActual[i].Span.EndLine, AWhat + ': EndLine');
    Assert.AreEqual<Integer>(AExpected[i].Span.EndCol,
      AActual[i].Span.EndCol, AWhat + ': EndCol');
    Assert.AreEqual(AExpected[i].Expected, AActual[i].Expected,
      AWhat + ': Expected');
    Assert.AreEqual(AExpected[i].NewText, AActual[i].NewText,
      AWhat + ': NewText');
  end;
end;

// Ein Eintrag der einfachen Hilfe gleich dem, was der Anbieter bis E3 aus
// AOutcome baute (AddSimpleFix.AddOutcome).
procedure AssertLikeOutcome(const AEntry: TRdxActionEntry;
  AKind: TFindingKind; const AOutcome: TRdxFixOutcome; const AWhat: string);
begin
  Assert.AreEqual('SimpleFix', AEntry.Recipe, AWhat + ': Rezept');
  Assert.AreEqual(TRdxFixTable.CaptionFor(AKind, AOutcome), AEntry.Caption,
    AWhat + ': Menuetext');
  Assert.IsTrue(AOutcome.Enabled = AEntry.Enabled, AWhat + ': verfuegbar');
  Assert.AreEqual(AOutcome.Hint, AEntry.Hint, AWhat + ': Hinweis');
  Assert.IsTrue(AOutcome.ChangesBehavior = AEntry.ChangesBehavior,
    AWhat + ': Kennzeichnung');
  Assert.AreEqual<Integer>(AOutcome.Variant, AEntry.Variant,
    AWhat + ': Variante');
  Assert.IsTrue(AEntry.Kind = fakFix, AWhat + ': fakFix');
  Assert.IsTrue(AEntry.HasAction, AWhat + ': mit Daten');
  Assert.IsTrue(AEntry.Action.Kind = akReplace, AWhat + ': Ersetzen');
  Assert.AreEqual('t.pas', AEntry.Action.FileName, AWhat + ': Datei');
  AssertSameEdits(AOutcome.Edits, AEntry.Action.Edits, AWhat);
end;

// Die letzten beiden Eintraege: 'Hier unterdruecken' und 'In dieser Datei
// unterdruecken' fuer AKindName, wie bisher hinter allem anderen.
procedure AssertSuppressTail(const AEntries: TArray<TRdxActionEntry>;
  const AKindName: string);
var
  n : Integer;
begin
  n := Length(AEntries);
  Assert.IsTrue(n >= 2, 'Unterdruecken am Ende');
  Assert.AreEqual('Suppress', AEntries[n - 2].Recipe);
  Assert.IsTrue(AEntries[n - 2].Kind = fakSuppress, 'Zeile: fakSuppress');
  Assert.AreEqual(_('Suppress here'), AEntries[n - 2].Caption);
  Assert.AreEqual('// noinspection ' + AKindName, AEntries[n - 2].Hint);
  Assert.IsTrue(AEntries[n - 2].Enabled and AEntries[n - 2].HasAction);
  Assert.AreEqual('Suppress', AEntries[n - 1].Recipe);
  Assert.IsTrue(AEntries[n - 1].Kind = fakSuppress, 'Datei: fakSuppress');
  Assert.AreEqual(_('Suppress in this file'), AEntries[n - 1].Caption);
  Assert.AreEqual('// noinspection-file ' + AKindName, AEntries[n - 1].Hint);
end;

procedure TTestRdxActionCore.SimpleFix_MainAndAlt_LikeFixTable;
var
  Src     : string;
  F       : TLeakFinding;
  Places  : TSourcePlaces;
  SL      : TStringList;
  Main    : TRdxFixOutcome;
  Alt     : TRdxFixOutcome;
  Entries : TArray<TRdxActionEntry>;
begin
  // SCA017: einklammern (FixFor) und loeschen (AlternativeFixFor).
  Src := Wrap(['  Foo;', '  WriteLn(''here #3'');', '  Bar;']);
  F := nil;
  Places := nil;
  SL := nil;
  try
    F := TLeakFinding.New('t.pas', 'Foo', BODY + 1, 'Debug output: writeln',
      fkDebugOutput);
    // Was der Anbieter bis E3 selbst rief - derselbe Text, dieselbe Sicht.
    Places := TSourcePlaces.Create;
    Places.SetIfdefDefines(TScanRequest.DefaultIfdefDefines);
    Assert.IsTrue(Places.OpenSource('t.pas', Src), 'OpenSource');
    SL := LinesOf(Src);
    Main := TRdxFixTable.FixFor(Places, SL, F,
      TRdxRecipeRunner.UsesNamesOf(Places));
    Alt := TRdxFixTable.AlternativeFixFor(Places, SL, F,
      TRdxRecipeRunner.UsesNamesOf(Places));
    Assert.IsTrue(Main.Enabled, Main.Reason);
    Assert.IsTrue(Alt.Variant > 0, 'SCA017 hat einen zweiten Eintrag');

    Entries := DescribeIn(Src, F);
    Assert.AreEqual<Integer>(4, Length(Entries),
      'Hilfe, zweiter Eintrag, zwei Unterdruecken');
    AssertLikeOutcome(Entries[0], fkDebugOutput, Main, 'erster Eintrag');
    AssertLikeOutcome(Entries[1], fkDebugOutput, Alt, 'zweiter Eintrag');
    Assert.AreEqual<Integer>(0, CountOf(Entries, 'Diagnosis'),
      'keine Diagnose neben einer Hilfe');
    AssertSuppressTail(Entries, 'DebugOutput');
  finally
    SL.Free;
    Places.Free;
    F.Free;
  end;
end;

procedure TTestRdxActionCore.Sca044_ShowSpanAndFormat_LikeRunner;
const
  SRC =
    'unit t;'#13#10 +
    'interface'#13#10 +
    'uses System.SysUtils;'#13#10 +
    'type TFoo = class'#13#10 +
    '  FName: string;'#13#10 +
    '  procedure Run(const Tag: string);'#13#10 +
    'end;'#13#10 +
    'implementation'#13#10 +
    'procedure TFoo.Run(const Tag: string);'#13#10 +
    'var Marker, Text: string;'#13#10 +
    'begin'#13#10 +
    '  Text := Marker + ''a'' + Tag + ''b'' + FName;'#13#10 +
    'end;'#13#10 +
    'end.';
var
  Path    : string;
  Parser  : TParser2;
  Root    : TAstNode;
  Results : TObjectList<TLeakFinding>;
  F       : TLeakFinding;
  Places  : TSourcePlaces;
  Info    : TRefactorInfo;
  IsCall  : Boolean;
  Why     : string;
  O       : TRdxFormatOutcome;
  Entries : TArray<TRdxActionEntry>;
begin
  // Die Meldung des ECHTEN Detektors (wie uTestRdxSca044.FindingsOf).
  Path := TempName('rdx_core_', '.pas');
  WriteText(Path, SRC);
  Results := nil;
  Places := nil;
  try
    Results := TObjectList<TLeakFinding>.Create(True);
    Parser := TParser2.Create;
    try
      Root := Parser.ParseFile(Path);
      try
        TConcatToFormatDetector.AnalyzeUnit(Root, Path, Results);
      finally
        Root.Free;
      end;
    finally
      Parser.Free;
    end;
    Assert.AreEqual<Integer>(1, Results.Count, 'ein SCA044-Fund');
    F := Results[0];
    Assert.AreEqual<Integer>(LineOf(SRC, 'Text := Marker'), F.LineInt);

    // Was der Anbieter bis E3 selbst rief: Anker 'assign', Gegenprobe
    // gegen den Fund, dann FormatRewrite.
    Places := TSourcePlaces.Create;
    Places.SetIfdefDefines(TScanRequest.DefaultIfdefDefines);
    Assert.IsTrue(Places.OpenSource(Path, SRC), 'OpenSource');
    Info := TRdxRecipeRunner.Describe(Places,
      TRdxRecipeRunner.QueryOf(F, 'assign'), IsCall, Why);
    try
      Assert.IsTrue(Assigned(Info), Why);
      O := TRdxRecipeRunner.FormatRewrite(Places, Info, Why,
        TRdxRecipeRunner.UsesNamesOf(Places));
      Assert.IsTrue(O.Enabled, O.Reason);

      Entries := DescribeIn(SRC, F);
      Assert.AreEqual<Integer>(4, Length(Entries),
        'Stelle zeigen, Format(), zwei Unterdruecken');
      Assert.AreEqual('ShowSpan', Entries[0].Recipe);
      Assert.IsTrue(Entries[0].Kind = fakNavigate, 'Stelle zeigen fuehrt hin');
      Assert.IsTrue(Entries[0].Enabled and Entries[0].HasAction);
      Assert.IsTrue(Entries[0].Action.Kind = akShowSpan);
      Assert.AreEqual<Integer>(Info.Span.StartLine,
        Entries[0].Action.Span.StartLine, 'Bereich: Startzeile');
      Assert.AreEqual<Integer>(Info.Span.StartCol,
        Entries[0].Action.Span.StartCol, 'Bereich: Startspalte');
      Assert.AreEqual<Integer>(Info.Span.EndCol,
        Entries[0].Action.Span.EndCol, 'Bereich: Endspalte');

      Assert.AreEqual('FormatCall', Entries[1].Recipe);
      Assert.IsTrue(Entries[1].Kind = fakFix);
      Assert.IsTrue(Entries[1].Enabled and Entries[1].HasAction);
      Assert.AreEqual(O.Hint, Entries[1].Hint, 'Hinweis');
      Assert.AreEqual(_('Build Format() from concatenation'),
        Entries[1].Caption);
      Assert.IsFalse(O.NeedsUses, 'System.SysUtils steht schon da');
      Assert.AreEqual<Integer>(1, Length(Entries[1].Action.Edits));
      Assert.AreEqual(O.Expected, Entries[1].Action.Edits[0].Expected);
      Assert.AreEqual(O.NewText, Entries[1].Action.Edits[0].NewText);
      Assert.AreEqual<Integer>(O.Span.StartCol,
        Entries[1].Action.Edits[0].Span.StartCol);
      AssertSuppressTail(Entries, 'ConcatToFormat');
    finally
      Info.Free;
    end;
  finally
    Places.Free;
    Results.Free;
    DeleteFile(Path);
  end;
end;

procedure TTestRdxActionCore.RemoveMarker_Blocked_WithReason;
var
  Src     : string;
  F       : TLeakFinding;
  Entries : TArray<TRdxActionEntry>;
begin
  // SCA165 an einem Marker mit zwei Arten: gesperrt, der Grund im Hinweis
  // (uTestRdxSuppress.RemoveMarker_MultiKind_Refused) - kein Unterdruecken
  // (ein wirkungsloser Marker wird entfernt, nicht unterdrueckt), keine
  // Diagnose (die Liste ist nicht leer).
  Src := Wrap(['  // noinspection NilDeref, TooLongLine',
    '  L := TStringList.Create;']);
  F := TLeakFinding.New('t.pas', 'Foo', BODY, 'unused suppression',
    fkUnusedSuppression);
  try
    Entries := DescribeIn(Src, F);
    Assert.AreEqual<Integer>(1, Length(Entries), 'nur der gesperrte Eintrag');
    Assert.AreEqual('RemoveMarker', Entries[0].Recipe);
    Assert.AreEqual(_('Remove ineffective suppression marker'),
      Entries[0].Caption);
    Assert.IsFalse(Entries[0].Enabled, 'gesperrt');
    Assert.IsFalse(Entries[0].HasAction, 'ohne Daten');
    Assert.IsTrue(Entries[0].Kind = fakFix, 'eine Hilfe, keine Unterdrueckung');
    Assert.IsTrue(Pos('mehrere Arten', Entries[0].Hint) > 0, Entries[0].Hint);
  finally
    F.Free;
  end;
end;

procedure TTestRdxActionCore.ParserWatchdog_OnlyDiagnosisAndSuppress;
var
  SB      : TStringBuilder;
  Src     : string;
  i       : Integer;
  F       : TLeakFinding;
  Core    : TRdxActionCore;
  Lines   : TStringList;
  Entries : TArray<TRdxActionEntry>;
  E       : TRdxActionEntry;
begin
  // Ueber 200.000 Token-Aufrufe: der Watchdog in TParser2.Next wirft
  // (wie uTestSourcePlaces.OpenSource_ParserThrows_NotOpen). Das kostet
  // nur die Baum-Rezepte: ein gesperrter Eintrag "reDelphix: Parser: ...",
  // dahinter Unterdruecken - wie bis E3 im Anbieter.
  SB := TStringBuilder.Create;
  try
    SB.Append('unit t; implementation'#13#10'procedure P;'#13#10'begin'#13#10);
    for i := 1 to 110000 do
      SB.Append('  x := 1;'#13#10);
    SB.Append('end;'#13#10'end.');
    Src := SB.ToString;
  finally
    SB.Free;
  end;
  F := nil;
  Lines := nil;
  Core := TRdxActionCore.Create(nil);
  try
    Core.Logging := False;
    F := TLeakFinding.New('t.pas', 'P', 4, 'Debug output: writeln',
      fkDebugOutput);
    Lines := LinesOf(Src);
    Entries := Core.Describe(F, Lines, txBuffer, Src);
    Assert.IsTrue(Length(Entries) >= 1, 'mindestens die Diagnose');
    Assert.AreEqual('Open', Entries[0].Recipe);
    Assert.IsTrue(Entries[0].Caption.StartsWith(DIAG_PREFIX + 'Parser: '),
      Entries[0].Caption);
    Assert.IsFalse(Entries[0].Enabled, 'die Diagnose ist gesperrt');
    for i := 1 to High(Entries) do
    begin
      E := Entries[i];
      Assert.IsTrue(E.Kind = fakSuppress,
        'hinter der Diagnose nur Unterdruecken: ' + E.Caption);
    end;
    Assert.AreEqual<Integer>(0, CountOf(Entries, 'SimpleFix'),
      'keine Baum-Rezepte');
    Assert.AreEqual<Integer>(0, CountOf(Entries, 'Diagnosis'),
      'keine zweite Diagnose');
    Assert.IsFalse(Core.Source.Places.IsOpen, 'kein halboffener Dienst');
  finally
    Lines.Free;
    F.Free;
    Core.Free;
  end;
end;

procedure TTestRdxActionCore.SourceNotReadable_TextRecipeStays;
var
  Src     : string;
  F       : TLeakFinding;
  Core    : TRdxActionCore;
  Lines   : TStringList;
  Entries : TArray<TRdxActionEntry>;
begin
  // Die Quelle laesst sich nicht oeffnen (leerer Puffertext - so meldet
  // TSourcePlaces.OpenSource False): "reDelphix: Datei nicht lesbar", aber
  // das Text-Rezept SCA165 laeuft auf den Zeilen weiter und entfernt den
  // Marker (eine Art, ganze Zeile).
  Src := Wrap(['  // noinspection NilDeref', '  L := TStringList.Create;']);
  F := nil;
  Lines := nil;
  Core := TRdxActionCore.Create(nil);
  try
    Core.Logging := False;
    F := TLeakFinding.New('t.pas', 'Foo', BODY, 'unused suppression',
      fkUnusedSuppression);
    Lines := LinesOf(Src);
    Entries := Core.Describe(F, Lines, txBuffer, '');
    Assert.AreEqual<Integer>(2, Length(Entries), 'Diagnose und SCA165');
    Assert.AreEqual('Open', Entries[0].Recipe);
    Assert.AreEqual(DIAG_PREFIX + _('file not readable'), Entries[0].Caption);
    Assert.IsFalse(Entries[0].Enabled);
    Assert.AreEqual('RemoveMarker', Entries[1].Recipe);
    Assert.IsTrue(Entries[1].Enabled and Entries[1].HasAction,
      Entries[1].Hint);
    Assert.IsTrue(Entries[1].Kind = fakFix);
    Assert.AreEqual(Wrap(['  L := TStringList.Create;']),
      Apply(Src, Entries[1].Action.Edits), 'der Marker ist weg');
  finally
    Lines.Free;
    F.Free;
    Core.Free;
  end;
end;

procedure TTestRdxActionCore.RuleWithoutHelp_DiagnosisThenSuppress;
var
  F       : TLeakFinding;
  Entries : TArray<TRdxActionEntry>;
begin
  // SCA012 (lange Methode): keine Zeile in der Tabelle, kein Anker, kein
  // fixMode - die Diagnose nennt das, Unterdruecken steht dahinter.
  F := TLeakFinding.New('t.pas', 'Foo', BODY, 'Method too long', fkLongMethod);
  try
    Assert.IsFalse(TRdxFixTable.Handles(fkLongMethod),
      'Voraussetzung: keine einfache Hilfe');
    Entries := DescribeIn(Wrap(['  Foo;']), F);
    Assert.AreEqual<Integer>(3, Length(Entries));
    Assert.AreEqual('Diagnosis', Entries[0].Recipe);
    Assert.AreEqual(DIAG_PREFIX + Format(
      _('%s: no fixMode in the rule catalog'), [F.ResolvedRuleId]),
      Entries[0].Caption);
    Assert.IsFalse(Entries[0].Enabled);
    AssertSuppressTail(Entries, 'LongMethod');
  finally
    F.Free;
  end;
end;

procedure TTestRdxActionCore.UsesLine_WithoutProjectUnits_Skipped;
var
  Src     : string;
  F       : TLeakFinding;
  Scopes  : TRdxScopeTable;
  Skipped : Boolean;
  Entries : TArray<TRdxActionEntry>;
  E       : TRdxActionEntry;
begin
  // Ein Fund auf der uses-Zeile: ohne Lieferanten der Projekt-Units (die
  // Probe) kein uses-Umbau, aber UsesSkipped; mit Lieferant (die IDE) der
  // Umbau-Eintrag wie bis E3 - hier gesperrt, weil die Scope-Tabelle leer
  // ist (qbNoTable).
  Src := Join(['unit t;', 'interface', 'uses Classes;', 'implementation',
    'end.']);
  F := nil;
  Scopes := nil;
  try
    F := TLeakFinding.New('t.pas', '', 3, 'Method too long', fkLongMethod);
    Scopes := TRdxScopeTable.Create;
    Entries := DescribeIn(Src, F, Scopes, nil, Skipped);
    Assert.IsTrue(Skipped, 'die Zeile liegt in der uses-Klausel');
    for E in Entries do
      Assert.IsFalse(E.Kind = fakRefactor, 'kein Umbau: ' + E.Caption);

    Entries := DescribeIn(Src, F, Scopes,
      function(const AFileName: string): TRdxProjectUnits
      begin
        Result := TRdxProjectUnits.Create;
      end, Skipped);
    Assert.IsFalse(Skipped, 'mit Lieferant: nichts ausgelassen');
    Assert.AreEqual('UsesActions', Entries[0].Recipe);
    Assert.IsTrue(Entries[0].Kind = fakRefactor, 'ein Umbau');
    Assert.AreEqual(_('uses: qualify entries'), Entries[0].Caption);
    Assert.IsFalse(Entries[0].Enabled, 'ohne Scope-Tabelle gesperrt');
    Assert.AreEqual(_('Scope table not loaded (unitscopes.txt)'),
      Entries[0].Hint);
  finally
    Scopes.Free;
    F.Free;
  end;
end;

procedure TTestRdxActionCore.FindingDiagnosis_NonPascalAndNoLine;
var
  F : TLeakFinding;
begin
  F := TLeakFinding.New('Form1.dfm', '', 3, 'x', fkLongMethod);
  try
    Assert.AreEqual(_('nothing to offer'), TRdxActionCore.FindingDiagnosis(F));
  finally
    F.Free;
  end;
  F := TLeakFinding.New('t.pas', '', 0, 'x', fkLongMethod);
  try
    Assert.AreEqual(_('finding without line'),
      TRdxActionCore.FindingDiagnosis(F));
  finally
    F.Free;
  end;
  F := TLeakFinding.New('t.pas', '', 3, 'x', fkLongMethod);
  try
    Assert.AreEqual('', TRdxActionCore.FindingDiagnosis(F));
  finally
    F.Free;
  end;
end;

procedure TTestRdxActionCore.TextMsg_TooLongForEditor;
var
  Prev : string;
begin
  // Der Text des Editors UND des Kerns ('Stelle zeigen' hinter Spalte
  // 32767) - bis E3 S_TOO_LONG in uRdxEditor; die msgid ist dieselbe
  // geblieben, die Uebersetzungen in de.po/fr.po gelten weiter.
  Prev := RdxLanguageOverride;
  try
    SetRdxLanguageOverride('en');
    Assert.AreEqual('Line too long for the editor selection (the editor '
      + 'reaches at most column 32767)', MsgTooLongForEditor(32767));
    SetRdxLanguageOverride('de');
    Assert.IsTrue(Pos('Editor-Markierung', MsgTooLongForEditor(32767)) > 0,
      MsgTooLongForEditor(32767));
    Assert.IsTrue(Pos('32767', MsgTooLongForEditor(32767)) > 0);
  finally
    SetRdxLanguageOverride(Prev);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxActionCore);

end.
