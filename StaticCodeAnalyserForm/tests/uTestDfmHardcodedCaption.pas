unit uTestDfmHardcodedCaption;

// Smoke-Tests für TDfmHardcodedCaptionDetector.
// Validiert die Property-Capture-Pipeline aus Iteration 2:
// Lexer -> Parser -> ComponentGraph (mit Properties) -> Detektor -> Findings.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmHardcodedCaption = class
  public
    // --- Treffer ---
    [Test] procedure Test_Caption_Detected;
    [Test] procedure Test_Hint_Detected;
    [Test] procedure Test_Text_Detected;
    [Test] procedure Test_Caption_OnNestedChild_Detected;
    [Test] procedure Test_MultipleProps_OnSameComponent_AllReported;

    // --- Nicht-Treffer ---
    [Test] procedure Test_EmptyCaption_NotDetected;
    [Test] procedure Test_WhitespaceOnlyCaption_NotDetected;
    [Test] procedure Test_NonStringValue_NotDetected;       // Ident wie 'clRed'
    [Test] procedure Test_NonWhitelistedProp_NotDetected;   // 'Filter' etc.
    [Test] procedure Test_NumericProp_NotDetected;          // 'Top = 42'
    [Test] procedure Test_NonTranslatableCaption_Skipped_TextStillDetected;

    // --- Finding-Inhalt ---
    [Test] procedure Test_Finding_LineNumberMatchesValueLine;
    [Test] procedure Test_Finding_MissingVarContainsComponentAndValue;
    [Test] procedure Test_Finding_SeverityIsHint;
    [Test] procedure Test_Finding_KindIsHardcodedCaption;
    // --- FP-Gates Charge 15 (AQL 31.08.: 11 %; Vollzaehlung rw70b:
    //     1.150 von 26.358). Alle sechs Fixtures VOR dem Bau an der
    //     rw70-Exe verprobt: jede feuert dort (6 Funde), nach den
    //     Gates muessen exakt die drei Gate-Faelle fallen. ---
    [Test] procedure Gate_Glyph_SymbolFontSingleChar_NotReported;
    [Test] procedure Gate_Glyph_NormalFontSingleChar_StillReported;
    [Test] procedure Gate_ResourceString_ReplacedProp_NotReported;
    // Voll-Review 2026-09-12 (Major 56): wortgenauer Sektionswechsel
    [Test] procedure Gate_ResIdentWithKeywordPrefix_NotReported;
    [Test] procedure Gate_PlainAssign_StillReported;
    [Test] procedure Gate_Regime_GnugettextUses_NotReported;
    [Test] procedure Gate_Regime_MarkerOnlyInComment_StillReported;
    // Nachschaerfung nach dem rw71-A/B: Marker-SUBSTRING in einem
    // laengeren Ident (CheckBoxDxgettextSupport - der Installer
    // REDET ueber dxgettext) gated NICHT; das JvGnugettext-uses
    // (jvcl-Wrapper, pyscripter-Muster) gated SEHR WOHL.
    [Test] procedure Gate_Regime_IdentSubstring_StillReported;
    [Test] procedure Gate_Regime_JvGnugettextWrapper_NotReported;
    // Testluecke 134: die zwei fehlenden Gegenrichtungen
    [Test] procedure Gate_RealTypeSectionEndsResBlock_StillReported;
    [Test] procedure Gate_Glyph_SymbolFontOnFormOnly_KnownGap_StillReported;
    // G4 Init-Ueberschreiben (Vertrag im Unit-Kopf)
    [Test] procedure G4_FormCreateZuweisung_NichtGemeldet;
    [Test] procedure G4_EventZuweisung_WirdGemeldet;
    [Test] procedure G4_SelbstreferenzInInit_WirdGemeldet;
    [Test] procedure G4_EineAufrufstufe_NichtGemeldet;
    [Test] procedure G4_GebundenerCreateHandler_NichtGemeldet;
    [Test] procedure G4_FremdklassenZuweisung_WirdGemeldet;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  System.IOUtils,   // TPath/TFile fuer die RunOnFiles-Gate-Tests
  uSCAConsts, uMethodd12,
  uDfmParser, uComponentGraph,
  uDfmHardcodedCaption;

function RunOn(const Src: string): TObjectList<TLeakFinding>;
var
  Parser : TDfmParser;
  Graph  : TComponentGraph;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  Parser := TDfmParser.Create;
  try
    Graph := Parser.ParseSource(Src);
    try
      TDfmHardcodedCaptionDetector.Analyze(Graph, 'test.dfm', Result);
    finally
      Graph.Free;
    end;
  finally
    Parser.Free;
  end;
end;

function CountKind(F: TObjectList<TLeakFinding>; K: TFindingKind): Integer;
var Fnd: TLeakFinding;
begin
  Result := 0;
  for Fnd in F do
    if Fnd.Kind = K then Inc(Result);
end;

{ --- Treffer --- }

procedure TTestDfmHardcodedCaption.Test_Caption_Detected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form2: TForm2'#13#10 +
    '  Caption = ''Static Code Analysis Tool'''#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkDfmHardcodedCaption));
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Test_Hint_Detected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form2: TForm2'#13#10 +
    '  object btnSave: TButton'#13#10 +
    '    Hint = ''Save the current file'''#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkDfmHardcodedCaption));
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Test_Text_Detected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form2: TForm2'#13#10 +
    '  object lblWelcome: TLabel'#13#10 +
    '    Text = ''Welcome'''#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkDfmHardcodedCaption));
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Test_Caption_OnNestedChild_Detected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object pnlOuter: TPanel'#13#10 +
    '    object pnlInner: TPanel'#13#10 +
    '      object btn: TButton'#13#10 +
    '        Caption = ''Speichern'''#13#10 +
    '      end'#13#10 +
    '    end'#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkDfmHardcodedCaption));
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Test_MultipleProps_OnSameComponent_AllReported;
// Eine Komponente mit Caption UND Hint UND Text -> 3 Befunde.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object btn: TButton'#13#10 +
    '    Caption = ''OK'''#13#10 +
    '    Hint = ''Confirm action'''#13#10 +
    '    Text = ''btn-text'''#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(3, CountKind(F, fkDfmHardcodedCaption));
  finally F.Free; end;
end;

{ --- Nicht-Treffer --- }

procedure TTestDfmHardcodedCaption.Test_EmptyCaption_NotDetected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object btn: TButton'#13#10 +
    '    Caption = '''''#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkDfmHardcodedCaption));
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Test_WhitespaceOnlyCaption_NotDetected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object btn: TButton'#13#10 +
    '    Caption = ''   '''#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkDfmHardcodedCaption));
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Test_NonStringValue_NotDetected;
// 'Color = clRed' ist pvkIdent, kein String -> kein UI-Text-Befund.
// Selbst wenn Color hypothetisch in der Whitelist waere, wuerde der Wert-
// Kind-Filter greifen.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  Color = clBtnFace'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkDfmHardcodedCaption));
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Test_NonWhitelistedProp_NotDetected;
// 'Filter' bei TOpenDialog ist auch UI-Text, ist aber bewusst nicht in der
// Phase-1-Whitelist. Wenn jemand das ergaenzt, wuerde dieser Test rot - das
// ist absichtlich der Pin-Test fuer die aktuelle Whitelist-Politik.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Dlg: TOpenDialog'#13#10 +
    '  Filter = ''All files (*.*)|*.*'''#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkDfmHardcodedCaption));
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Test_NumericProp_NotDetected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  Top = 42'#13#10 +
    '  Left = 100'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkDfmHardcodedCaption));
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Test_NonTranslatableCaption_Skipped_TextStillDetected;
// FP-Fix (Real-World 2026-06-28): reine Symbol-/Ziffern-Captions ('...', '-',
// '123') sind nicht lokalisierbar -> kein i18n-Smell. Echter Text ('Save')
// bleibt erkannt. Bidirektional in einer Form.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object btnEllipsis: TButton'#13#10 +
    '    Caption = ''...'''#13#10 +
    '  end'#13#10 +
    '  object btnMinus: TButton'#13#10 +
    '    Caption = ''-'''#13#10 +
    '  end'#13#10 +
    '  object btnSave: TButton'#13#10 +
    '    Caption = ''Save'''#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkDfmHardcodedCaption),
      'nur die echte Text-Caption ''Save'' zaehlt - ''...'' und ''-'' sind nicht uebersetzbar');
  finally F.Free; end;
end;

{ --- Finding-Inhalt --- }

procedure TTestDfmHardcodedCaption.Test_Finding_LineNumberMatchesValueLine;
// Befund-Zeile zeigt auf die Property-Zeile (nicht die Object-Header-Zeile),
// damit IDE-Marker bzw. Editor-Sprung zum richtigen Ort fuehrt.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +    // Zeile 1
    '  object btn: TButton'#13#10 + // Zeile 2
    '    Caption = ''OK'''#13#10 +  // Zeile 3
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(1, F.Count);
    Assert.AreEqual('3', F[0].LineNumber);
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Test_Finding_MissingVarContainsComponentAndValue;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm'#13#10 +
    '  object btn: TButton'#13#10 +
    '    Caption = ''Speichern'''#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(1, F.Count);
    Assert.Contains(F[0].MissingVar, 'btn');
    Assert.Contains(F[0].MissingVar, 'Caption');
    Assert.Contains(F[0].MissingVar, 'Speichern');
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Test_Finding_SeverityIsHint;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm Caption = ''X'' end');
  try
    Assert.AreEqual(lsHint, F[0].Severity);
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Test_Finding_KindIsHardcodedCaption;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Form: TForm Caption = ''X'' end');
  try
    Assert.AreEqual(fkDfmHardcodedCaption, F[0].Kind);
  finally F.Free; end;
end;

{ --- FP-Gates Charge 15 --- }

function RunOnFiles(const DfmSrc, PasSrc: string)
  : TObjectList<TLeakFinding>;
// Schreibt DFM+PAS unter GUID-Basisnamen (der Datei-Textcache stellt
// per Name zurueck - fester Name machte Tests reihenfolgeabhaengig)
// und laesst den Detektor mit dem ECHTEN DFM-Pfad laufen, damit
// LadeNachbarPas die .pas findet.
var
  Base, DfmPath : string;
  Parser : TDfmParser;
  Graph  : TComponentGraph;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  Base := TPath.Combine(TPath.GetTempPath, 'sca025_'
    + TGuid.NewGuid.ToString.Replace('{', '').Replace('}', '')
      .Replace('-', ''));
  DfmPath := Base + '.dfm';
  TFile.WriteAllText(DfmPath, DfmSrc, TEncoding.UTF8);
  TFile.WriteAllText(Base + '.pas', PasSrc, TEncoding.UTF8);
  Parser := TDfmParser.Create;
  try
    Graph := Parser.ParseSource(DfmSrc);
    try
      TDfmHardcodedCaptionDetector.Analyze(Graph, DfmPath, Result);
    finally
      Graph.Free;
    end;
  finally
    Parser.Free;
    if TFile.Exists(DfmPath) then TFile.Delete(DfmPath);
    if TFile.Exists(Base + '.pas') then TFile.Delete(Base + '.pas');
  end;
end;

procedure TTestDfmHardcodedCaption.Gate_Glyph_SymbolFontSingleChar_NotReported;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object FormA: TFormA'#13#10 +
    '  object Btn1: TButton'#13#10 +
    '    Caption = ''q'''#13#10 +
    '    Font.Name = ''Webdings'''#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkDfmHardcodedCaption),
      'Webdings-Einzelzeichen ist ein Icon, kein Text');
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Gate_Glyph_NormalFontSingleChar_StillReported;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object FormA: TFormA'#13#10 +
    '  object Btn2: TButton'#13#10 +
    '    Caption = ''q'''#13#10 +
    '    Font.Name = ''Tahoma'''#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkDfmHardcodedCaption),
      'Normalfont-Einzelzeichen bleibt Fund (TP-Gegenprobe)');
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Gate_ResourceString_ReplacedProp_NotReported;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOnFiles(
    'object FormB: TFormB'#13#10 +
    '  object BtnR: TButton'#13#10 +
    '    Caption = ''Platzhalter'''#13#10 +
    '  end'#13#10 +
    'end',
    'unit resprobe;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'resourcestring'#13#10 +
    '  SEcht = ''Echter Text'';'#13#10 +
    'procedure TFormB.Init;'#13#10 +
    'begin'#13#10 +
    '  BtnR.Caption := SEcht;'#13#10 +
    'end;'#13#10 +
    'end.');
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkDfmHardcodedCaption),
      'DFM-Wert ist toter Platzhalter - resourcestring ersetzt ihn');
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Gate_ResIdentWithKeywordPrefix_NotReported;
// Voll-Review 2026-09-12 (Major 56): der Praefix-Match beendete den
// resourcestring-Block schon bei 'typeCaption = ...' (StartsText
// 'type') - der folgende Res-Ident fehlte im Gate und die Caption
// wurde trotz Laufzeit-Ersetzung gemeldet.
// Fixture bewusst namens- und layoutvariiert gegen den
// Gate_ResourceString-Nachbarn - sonst meldet der Selbstscan die
// Zwillinge als DuplicateBlock/DuplicateString.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOnFiles(
    'object FormC: TFormC'#13#10'  object BtnQ: TButton'#13#10 +
    '    Caption = ''Rohtext'''#13#10'  end'#13#10'end',
    'unit resprobe2;'#13#10'interface'#13#10'implementation'#13#10 +
    'resourcestring'#13#10 +
    '  typeCaption = ''Anderer Text'';'#13#10 +
    '  SWahr = ''Echter Text 2'';'#13#10 +
    'procedure TFormC.Setup;'#13#10'begin'#13#10 +
    '  BtnQ.Caption := SWahr;'#13#10'end;'#13#10'end.');
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkDfmHardcodedCaption),
      'typeCaption ist ein Res-Ident, kein Sektionswechsel - das Gate ' +
      'muss SWahr weiter sehen');
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Gate_PlainAssign_StillReported;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOnFiles(
    'object FormB: TFormB'#13#10 +
    '  object BtnP: TButton'#13#10 +
    '    Caption = ''Bleibt stehen'''#13#10 +
    '  end'#13#10 +
    'end',
    'unit resprobe;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'var X: string;'#13#10 +
    'procedure TFormB.Init;'#13#10 +
    'begin'#13#10 +
    '  BtnP.Caption := X;'#13#10 +
    'end;'#13#10 +
    'end.');
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkDfmHardcodedCaption),
      'Zuweisung aus Nicht-resourcestring in NICHT-Init-Routine gated nicht (seit G4 ist der Routinen-Kontext das Kriterium)');
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Gate_Regime_GnugettextUses_NotReported;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOnFiles(
    'object FormC: TFormC'#13#10 +
    '  Caption = ''Uebersetzt zur Laufzeit'''#13#10 +
    'end',
    'unit regimeprobe;'#13#10 +
    'interface'#13#10 +
    'uses gnugettext;'#13#10 +
    'implementation'#13#10 +
    'end.');
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkDfmHardcodedCaption),
      'Form im Laufzeit-Uebersetzungs-Regime: DFM-Text ist msgid-Quelle');
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Gate_Regime_MarkerOnlyInComment_StillReported;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOnFiles(
    'object FormD: TFormD'#13#10 +
    '  Caption = ''Marker nur im Kommentar'''#13#10 +
    'end',
    'unit kommprobe;'#13#10 +
    'interface'#13#10 +
    '// gnugettext waere hier nur Prosa'#13#10 +
    'implementation'#13#10 +
    'end.');
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkDfmHardcodedCaption),
      'Kommentare zaehlen NIE als Code-Use - Marker im Kommentar gated nicht');
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Gate_Regime_IdentSubstring_StillReported;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOnFiles(
    'object FormE: TFormE'#13#10 +
    '  Caption = ''Konfig-Seite'''#13#10 +
    'end',
    'unit subprobe;'#13#10 +
    'interface'#13#10 +
    'type TFormE = class'#13#10 +
    '  CheckBoxDxgettextSupport: TObject;'#13#10 +
    'end;'#13#10 +
    'implementation'#13#10 +
    'end.');
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkDfmHardcodedCaption),
      'dxgettext als Ident-SUBSTRING ist kein Uebersetzungs-Regime');
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Gate_Regime_JvGnugettextWrapper_NotReported;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOnFiles(
    'object FormF: TFormF'#13#10 +
    '  Caption = ''Wird uebersetzt'''#13#10 +
    'end',
    'unit wrapprobe;'#13#10 +
    'interface'#13#10 +
    'uses JvGnugettext;'#13#10 +
    'implementation'#13#10 +
    'end.');
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkDfmHardcodedCaption),
      'JvGnugettext ist der jvcl-gettext-Wrapper - echtes Regime');
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.Gate_RealTypeSectionEndsResBlock_StillReported;
// Testluecke 134, Gegenrichtung zu Gate_ResIdentWithKeywordPrefix: der
// wortgenaue Test muss beim ECHTEN Sektionswechsel weiterhin abbrechen.
// Hier steht ein richtiges 'type' zwischen dem resourcestring-Block und
// der Zuweisung - 'SPflicht' ist damit KEIN Res-Ident mehr, und die
// Caption gehoert gemeldet.
//
// Ohne diesen Test bliebe der Sektionswechsel einseitig abgesichert: wer
// ihn ganz entfernte (Block laeuft bis Dateiende), saehe nur gruen.
//
// Der resourcestring steht bewusst als EINZEILER ('resourcestring SEgal =
// ...'): das ist ein eigener Zweig im Sammler (uDfmHardcodedCaption
// Z.206-215, den Rest der Zeile gleich einlesen), er kommt in keinem
// anderen Test vor - und er vermeidet nebenbei den dritten identischen
// 'resourcestring'-Zeilenzwilling, den der Selbstscan sonst meldet.
// Am gebauten Stand nachgemessen: 1 Fund.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOnFiles(
    'object FormT: TFormT'#13#10'  object BtnT: TButton'#13#10 +
    '    Caption = ''Zwischentext'''#13#10'  end'#13#10'end',
    'unit sektionsprobe;'#13#10'interface'#13#10'implementation'#13#10 +
    'resourcestring SEgal = ''Nicht verwendet'';'#13#10 +
    'type'#13#10 +
    '  TSchalter = (sAn, sAus);'#13#10 +
    'procedure TFormT.Init;'#13#10'begin'#13#10 +
    '  BtnT.Caption := SPflicht;'#13#10'end;'#13#10'end.');
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkDfmHardcodedCaption),
      'ein echtes type beendet den Block - SPflicht ist kein Res-Ident');
  finally F.Free; end;
end;

{ --- G4 INIT-UEBERSCHREIBEN (2026-09-16) ------------------------- }
//
// Vertrag und Vermessung im Unit-Kopf. Die Klammern zuerst: G4
// skippt NUR Init-Kontexte - die grosszuegige Variante hatte in
// der Handpruefung 56 % Fehlskips (Event-Zuweisungen sind der
// Normalfall "DFM ist der Grundzustand").

procedure TTestDfmHardcodedCaption.G4_FormCreateZuweisung_NichtGemeldet;
// Der Kernfall: FormCreate ersetzt die Caption unbedingt - der
// DFM-Wert ist ein toter Platzhalter. Vor G4: 1 Fund (dieser
// Test war ROT).
var F: TObjectList<TLeakFinding>;
begin
  F := RunOnFiles(
    'object FormG: TFormG'#13#10 +
    '  object LblG: TLabel'#13#10 +
    '    Caption = ''Platzhalter'''#13#10 +
    '  end'#13#10 +
    'end',
    'unit g4probe;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure TFormG.FormCreate(Sender: TObject);'#13#10 +
    'begin'#13#10 +
    '  LblG.Caption := HoleText;'#13#10 +
    'end;'#13#10 +
    'end.');
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkDfmHardcodedCaption),
      'Init-Zuweisung skippt den DFM-Platzhalter');
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.G4_EventZuweisung_WirdGemeldet;
// DIE KLAMMER: im Event-Handler ist der DFM-Text der korrekte
// GRUNDZUSTAND bis zum Klick (btnTest Run -> Stop).
// 14 der 25 grosszuegigen Stichproben-Drops waren genau das.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOnFiles(
    'object FormG: TFormG'#13#10 +
    '  object LblG: TLabel'#13#10 +
    '    Caption = ''Platzhalter'''#13#10 +
    '  end'#13#10 +
    'end',
    'unit g4probe;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure TFormG.BtnKlick(Sender: TObject);'#13#10 +
    'begin'#13#10 +
    '  LblG.Caption := HoleText;'#13#10 +
    'end;'#13#10 +
    'end.');
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkDfmHardcodedCaption),
      'Event-Zuweisung skippt NICHT - der DFM-Text ist der Grundzustand');
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.G4_SelbstreferenzInInit_WirdGemeldet;
// RHS-Selbstreferenz: der DFM-Wert ist das FORMAT-TEMPLATE und
// erreicht den Nutzer als Textbasis doch (33 Faelle im
// Delphi-Korpus, ABOUT.pas-Muster).
var F: TObjectList<TLeakFinding>;
begin
  F := RunOnFiles(
    'object FormG: TFormG'#13#10 +
    '  object LblG: TLabel'#13#10 +
    '    Caption = ''Platzhalter'''#13#10 +
    '  end'#13#10 +
    'end',
    'unit g4probe;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure TFormG.FormCreate(Sender: TObject);'#13#10 +
    'begin'#13#10 +
    '  LblG.Caption := Format(LblG.Caption, [Version]);'#13#10 +
    'end;'#13#10 +
    'end.');
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkDfmHardcodedCaption),
      'Selbstreferenz skippt NICHT - der DFM-Wert ist das Template');
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.G4_EineAufrufstufe_NichtGemeldet;
// Das LoadLocale-/SetLabels-Muster: die Zuweisung liegt eine
// Aufrufstufe unter FormCreate.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOnFiles(
    'object FormG: TFormG'#13#10 +
    '  object LblG: TLabel'#13#10 +
    '    Caption = ''Platzhalter'''#13#10 +
    '  end'#13#10 +
    'end',
    'unit g4probe;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure TFormG.SetzeTexte;'#13#10 +
    'begin'#13#10 +
    '  LblG.Caption := HoleText;'#13#10 +
    'end;'#13#10 +
    'procedure TFormG.FormCreate(Sender: TObject);'#13#10 +
    'begin'#13#10 +
    '  SetzeTexte;'#13#10 +
    'end;'#13#10 +
    'end.');
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkDfmHardcodedCaption),
      'eine Aufrufstufe unter Init skippt');
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.G4_GebundenerCreateHandler_NichtGemeldet;
// Der Lazarus-Kanal: OnCreate ist an einen FREI benannten
// Handler gebunden (CondFormCREATE-Klasse der Vermessung) - die
// Namensliste allein traefe ihn nicht, der Graph liefert ihn.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOnFiles(
    'object FormG: TFormG'#13#10 +
    '  OnCreate = MeinStart'#13#10 +
    '  object LblG: TLabel'#13#10 +
    '    Caption = ''Platzhalter'''#13#10 +
    '  end'#13#10 +
    'end',
    'unit g4probe;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure TFormG.MeinStart(Sender: TObject);'#13#10 +
    'begin'#13#10 +
    '  LblG.Caption := HoleText;'#13#10 +
    'end;'#13#10 +
    'end.');
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkDfmHardcodedCaption),
      'DFM-gebundener Create-Handler zaehlt als Init-Kontext');
  finally F.Free; end;
end;

procedure TTestDfmHardcodedCaption.G4_FremdklassenZuweisung_WirdGemeldet;
// Qualifizierte Zuweisung (zwei Punkte) ist eine FREMDE Referenz
// auf ein anderes Objekt - die Ein-Punkt-LHS-Regel schliesst sie
// aus (TES5Edit-False-Drop-Klasse der Vermessung).
var F: TObjectList<TLeakFinding>;
begin
  F := RunOnFiles(
    'object FormG: TFormG'#13#10 +
    '  object LblG: TLabel'#13#10 +
    '    Caption = ''Platzhalter'''#13#10 +
    '  end'#13#10 +
    'end',
    'unit g4probe;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure TAnderer.Tu;'#13#10 +
    'begin'#13#10 +
    '  Frame.LblG.Caption := HoleText;'#13#10 +
    'end;'#13#10 +
    'procedure TFormG.FormCreate(Sender: TObject);'#13#10 +
    'begin'#13#10 +
    '  Tu;'#13#10 +
    'end;'#13#10 +
    'end.');
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkDfmHardcodedCaption),
      'Fremdreferenz mit Qualifier skippt NICHT');
  finally F.Free; end;
end;


procedure TTestDfmHardcodedCaption.Gate_Glyph_SymbolFontOnFormOnly_KnownGap_StillReported;
// Testluecke 134, DOKUMENTIERTE GRENZE von G1 - der Fund hier ist eine
// bewusste Ungenauigkeit, kein Ziel.
//
// Das Glyph-Gate liest Font.Name AM KNOTEN SELBST. Setzt die Form den
// Symbolfont und erbt das Kind ihn ueber ParentFont, sieht das Gate am
// Kind kein Font.Name und meldet dessen Ein-Zeichen-Caption. Zur
// Aufloesung muesste der Detektor die ParentFont-Kette auswerten - das
// ist mehr als eine Gate-Bedingung und steht bewusst nicht in v1.
//
// Der Pin macht die Grenze sichtbar: wer die Kette nachruestet, sieht
// hier rot und stellt die Erwartung auf 0. Die Gegenprobe ist der
// Nachbar Gate_Glyph_SymbolFontSingleChar_NotReported - dort traegt das
// Kind den Font selbst und wird korrekt uebersprungen.
// Am gebauten Stand nachgemessen: 1 Fund.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object FormP: TFormP'#13#10 +
    '  Font.Name = ''Wingdings'''#13#10 +
    '  object BtnP: TButton'#13#10 +
    '    ParentFont = True'#13#10 +
    '    Caption = ''a'''#13#10 +
    '  end'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkDfmHardcodedCaption),
      'BEKANNTE GRENZE: geerbter Symbolfont wird nicht erkannt');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmHardcodedCaption);

end.
