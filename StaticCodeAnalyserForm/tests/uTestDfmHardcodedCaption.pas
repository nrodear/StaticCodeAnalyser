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
    [Test] procedure Gate_PlainAssign_StillReported;
    [Test] procedure Gate_Regime_GnugettextUses_NotReported;
    [Test] procedure Gate_Regime_MarkerOnlyInComment_StillReported;
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
      'Zuweisung aus Nicht-resourcestring gated nicht (TP-Gegenprobe)');
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

initialization
  TDUnitX.RegisterTestFixture(TTestDfmHardcodedCaption);

end.
