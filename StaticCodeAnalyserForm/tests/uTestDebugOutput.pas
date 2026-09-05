unit uTestDebugOutput;

// Tests fuer den TDebugOutputDetector.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  // Gate D (Datei-Name-Gate) laesst sich nur mit einem FREI WAEHLBAREN
  // Dateinamen pruefen - TFindingHelper.FindingsOf fixiert 'sample.pas'.
  // Deshalb hier zusaetzlich der direkte Detektor-Aufruf (gleiches Muster
  // wie SecretCountForPath in uTestHardcodedSecret.pas).
  uAstNode, uParser2, uDebugOutput,
  uTestSrcBuilder,
  uTestFindingHelper;

type
  // ---- DebugOutput (TDebugOutputDetector) --------------------------------------------
  [TestFixture]
  TTestDebugOutput = class
  public
    [Test] procedure Debug_WriteLnCall_ReportsWarning;
    [Test] procedure Debug_ShowMessageCall_ReportsWarning;
    // Scope-Entscheidung 2026-07-11: MessageDlg + InputBox sind keine SCA017-
    // Ziele mehr (bewusste UI bzw. Eingabe-Primitiv) -> NoFinding.
    [Test] procedure Debug_MessageDlg_NoFinding;
    [Test] procedure Debug_OutputDebugStringCall_ReportsWarning;
    [Test] procedure Debug_InputBox_NoFinding;
    [Test] procedure Debug_NormalCall_NoFinding;
    [Test] procedure Debug_PrefixedNameWordBoundary_NoFalsePositive;
    [Test] procedure Debug_LoggerWriteCall_NoFalsePositive;
    [Test] procedure Debug_TwoDebugCalls_BothReported;
    [Test] procedure Debug_ShowMessagePosCall_ReportsWarning;
    // Real-World FP-Audit 2026-07-10: member-qualifiziertes WriteLn
    [Test] procedure Debug_MemberQualifiedWriteLn_NoFinding;
    [Test] procedure Debug_SystemQualifiedWriteLn_ReportsWarning;
    // Welle 2 (nkConditionalRange): Debug-Output in {$IFDEF DEBUG} ist Absicht.
    [Test] procedure Debug_WriteLnInIfdefDebug_NotReported;
    [Test] procedure Debug_WriteLnInIfdefDebugElse_StillReported;
    // Gate A (FP-Paket 2026-08-27): WriteLn auf ein Text-/TextFile-Handle ist
    // Datei-I/O. Drei Beweisquellen fuer ein Handle + drei TP-Gegenproben.
    [Test] procedure Debug_WriteLnToTextFileLocal_NoFinding;
    [Test] procedure Debug_WriteLnToVarParamTextFile_NoFinding;
    [Test] procedure Debug_WriteLnToAssignFileHandle_NoFinding;
    [Test] procedure Debug_WriteLnToTextFileField_NoFinding;
    [Test] procedure Debug_BareWriteLnBesideFileHandle_StillReported;
    [Test] procedure Debug_WriteLnToStandardHandles_StillReported;
    [Test] procedure Debug_WriteLnToStringVar_StillReported;
    // Gate D (FP-Paket 2026-08-27): Logger-/Appender-Senke.
    [Test] procedure Debug_LoggerFileName_NoFinding;
    [Test] procedure Debug_AppenderFileName_NoFinding;
    [Test] procedure Debug_PlainFileName_StillReported;
    // --- Geltungsbereich-Gate (eingeloestes Versprechen, 2026-09-05) ---
    [Test] procedure Debug_TestsDirPath_NoFinding;
    [Test] procedure Debug_SamplesDirPath_NoFinding;
    [Test] procedure Debug_ConsoleUnitName_NoFinding;
    [Test] procedure Debug_NeutralPath_StillReported;
    // Gate E (03.09., AQL-Neumessung): der unqualifizierte Name bindet
    // an eine gleichnamige EIGENE Routine der Unit.
    [Test] procedure Debug_OwnWriteLnMethod_NoFinding;
    [Test] procedure Debug_PlainWriteLn_StillReported;
    // Review 03.09.: Gate E darf den EXPLIZITEN System.-Qualifier nicht
    // schlucken - gerade dort steht er, wo der Name verschattet ist.
    [Test] procedure Debug_SystemQualifiedDespiteOwnMethod_StillReported;
  end;

implementation

// =============================================================================
// DebugOutput-Tests
// =============================================================================

procedure TTestDebugOutput.Debug_WriteLnCall_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin WriteLn(''debug''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDebugOutput));
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_ShowMessageCall_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin ShowMessage(''Hallo''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDebugOutput));
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_MessageDlg_NoFinding;
// Scope-Entscheidung 2026-07-11 (Real-World-FP-Audit): MessageDlg mit mt*-Typ +
// [mb*]-Button-Set ist bewusste strukturierte UI, kein vergessenes Debug-Popup
// -> kein Ziel mehr. (ShowMessage bleibt Ziel, s. Debug_ShowMessageCall.)
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin MessageDlg(''ok'', mtInformation, [mbOK], 0); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDebugOutput),
    'MessageDlg ist bewusste UI, kein SCA017-Ziel mehr');
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_OutputDebugStringCall_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin OutputDebugString(''hi''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDebugOutput));
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_InputBox_NoFinding;
// Scope-Entscheidung 2026-07-11 (Real-World-FP-Audit): InputBox/InputQuery sind
// Eingabe-Primitive (liefern einen Wert statt Output) -> kein SCA017-Ziel mehr.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin s := InputBox(''titel'', ''prompt'', ''default''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDebugOutput),
    'InputBox ist Eingabe-Primitiv, kein SCA017-Ziel mehr');
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_NormalCall_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin Logger.Info(''ok''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDebugOutput));
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_PrefixedNameWordBoundary_NoFalsePositive;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin MyWriteLn(''hi''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDebugOutput));
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_LoggerWriteCall_NoFalsePositive;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin Logger.WriteEntry(''msg''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDebugOutput));
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_TwoDebugCalls_BothReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  WriteLn(''a'');'#13#10+
  '  ShowMessage(''b'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkDebugOutput));
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_ShowMessagePosCall_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin ShowMessagePos(''x'', 100, 100); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDebugOutput));
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_MemberQualifiedWriteLn_NoFinding;
// Real-World FP-Audit 2026-07-10: Self.WriteLn / FConsoleWriter.WriteLn ist eine
// eigene Writer-/Logging-Methode der Klasse, KEIN RTL-Debug-Output.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  Self.WriteLn(''x'');'#13#10+
  '  FConsoleWriter.WriteLn(''y'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDebugOutput),
    'member-qualifiziertes WriteLn ist eigene Methode, kein RTL-Debug');
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_SystemQualifiedWriteLn_ReportsWarning;
// Gegenprobe: System.WriteLn IST das RTL-WriteLn -> bleibt Fund.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin System.WriteLn(''debug''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDebugOutput),
    'System.WriteLn ist RTL-Debug-Output');
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_WriteLnInIfdefDebug_NotReported;
// Welle 2 (Core-Detektoren-Architektur): WriteLn in {$IFDEF DEBUG}..{$ENDIF} wird
// aus Release-Builds auskompiliert -> kein vergessener Produktions-Debug. Der vom
// Lexer/Parser gesetzte nkConditionalRange-Marker laesst SCA017 den Fund unterdruecken.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '{$IFDEF DEBUG}'#13#10 +
  '  WriteLn(''trace'');'#13#10 +
  '{$ENDIF}'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDebugOutput),
    'WriteLn in {$IFDEF DEBUG} ist Absicht - kein Fund');
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_WriteLnInIfdefDebugElse_StillReported;
// TP-Guard: der {$ELSE}-Zweig eines {$IFDEF DEBUG} ist der RELEASE-Pfad - ein WriteLn
// DORT ist Produktions-Debug und muss weiter gemeldet werden. Die DEBUG-Range endet
// am {$ELSE}, deckt den else-Zweig also nicht ab.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '{$IFDEF DEBUG}'#13#10 +
  '  DoDebug;'#13#10 +
  '{$ELSE}'#13#10 +
  '  WriteLn(''release'');'#13#10 +
  '{$ENDIF}'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDebugOutput),
    'WriteLn im {$ELSE}=Release-Zweig ist Produktions-Debug -> Fund');
  finally F.Free; end;
end;

// =============================================================================
// Gate A - WriteLn auf ein Text-/TextFile-Handle ist Datei-I/O
// (FP-Paket SCA017, 2026-08-27). Korpus: 980 der 2.717 code-echten WriteLn(-
// Stellen haengen an einem belegten Handle; Traeger sind die SynGen-Code-
// generatoren (SynGenUnit.pas, 806), Dev-Cpp/Compiler.pas (60, var-Parameter)
// und doublecmd/uexceptions.pas (8, 'System.Text').
// =============================================================================

procedure TTestDebugOutput.Debug_WriteLnToTextFileLocal_NoFinding;
// Beweisquelle 1: die Typdeklaration der lokalen Variablen.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var F: TextFile;'#13#10+
  'begin WriteLn(F, ''zeile''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDebugOutput),
    'WriteLn auf ein TextFile-Handle schreibt in eine Datei, nicht auf die Konsole');
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_WriteLnToVarParamTextFile_NoFinding;
// Beweisquelle 1 in Parameter-Form. Der Parser legt den Modifier IM NAMEN ab
// ('var F', uParser2.pas:1610) - ohne den Strip im Detektor liefe das Gate
// hier ins Leere. Genau diese Form traegt die 60 Funde in
// Dev-Cpp/Source/Compiler.pas ('procedure NewMakeFile(var F: TextFile)', :110).
const SRC =
  'unit t; implementation'#13#10+
  'procedure TCompiler.NewMakeFile(var F: TextFile);'#13#10+
  'begin WriteLn(F, ''makefile-zeile''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDebugOutput),
    'var-Parameter vom Typ TextFile ist ein Datei-Handle - Modifier-Praefix muss gestrippt werden');
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_WriteLnToAssignFileHandle_NoFinding;
// Beweisquelle 2 OHNE jede Typdeklaration: das erste Argument von AssignFile/
// Rewrite/CloseFile ist per Sprachdefinition ein Datei-Handle.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TGen.Dump;'#13#10+
  'begin'#13#10+
  '  AssignFile(FOut, ''out.txt'');'#13#10+
  '  Rewrite(FOut);'#13#10+
  '  WriteLn(FOut, ''zeile'');'#13#10+
  '  CloseFile(FOut);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDebugOutput),
    'AssignFile/Rewrite belegen das Handle auch ohne sichtbare Typdeklaration');
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_WriteLnToTextFileField_NoFinding;
// Beweisquelle 1 als KLASSENFELD - die Form des groessten Korpus-Clusters
// (SynGenUnit.pas:155 'OutFile: TextFile;', 404 + 402 Funde). Die Deklaration
// steht in der interface-Sektion, der WriteLn Hunderte Zeilen weiter unten.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TGen = class'#13#10+
  '  private'#13#10+
  '    OutFile: TextFile;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'procedure TGen.Emit;'#13#10+
  'begin WriteLn(OutFile, ''generierter code''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDebugOutput),
    'Klassenfeld vom Typ TextFile ist genauso ein Datei-Handle wie eine lokale Variable');
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_BareWriteLnBesideFileHandle_StillReported;
// TP-Gegenprobe zu Gate A: das Gate haengt am ARGUMENT, nicht an der Datei.
// Eine Unit, die eine Textdatei schreibt, darf ihren vergessenen Konsolen-
// WriteLn nicht mit durchschmuggeln.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var F: TextFile;'#13#10+
  'begin'#13#10+
  '  WriteLn(F, ''datei'');'#13#10+
  '  WriteLn(''debug'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDebugOutput),
    'nacktes WriteLn bleibt Fund, auch wenn dieselbe Routine eine Textdatei schreibt');
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_WriteLnToStandardHandles_StillReported;
// TP-Gegenprobe zu Gate A: Output/ErrOutput/Input SIND die Konsole. Sie werden
// hier sogar als TextFile deklariert, landen also in der Handle-Menge - die
// Whitelist muss trotzdem gewinnen. Korpus-Beleg fuer die reale Form:
// LoggerPro.ConsoleAppender.pas:427 'Writeln(ErrOutput, FormatLog(...))'.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var Output, ErrOutput: TextFile;'#13#10+
  'begin'#13#10+
  '  WriteLn(Output, ''a'');'#13#10+
  '  WriteLn(ErrOutput, ''b'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkDebugOutput),
    'Output/ErrOutput sind die Konsole - Standardhandles bleiben immer Fund');
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_WriteLnToStringVar_StillReported;
// TP-Gegenprobe zu Gate A: das Gate keyt auf den TYP, nicht darauf, dass das
// erste Argument ueberhaupt ein Bezeichner ist.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var S: string;'#13#10+
  'begin WriteLn(S); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDebugOutput),
    'WriteLn(S) mit S: string ist Konsolenausgabe und bleibt Fund');
  finally F.Free; end;
end;

// =============================================================================
// Gate D - Logger-/Appender-Senke (FP-Paket SCA017, 2026-08-27)
// =============================================================================

// Gemeinsame Quelle der drei Gate-D-Tests: eine unstrittige Debug-Ausgabe. Ob
// sie gemeldet wird, haengt AUSSCHLIESSLICH am Dateinamen.
const
  SINK_SRC =
    'unit t; implementation'#13#10+
    'procedure TConsoleAppender.WriteLog;'#13#10+
    'begin'#13#10+
    '  WriteLn(''log line'');'#13#10+
    '  OutputDebugString(''log line'');'#13#10+
    'end;';

// Parst SINK_SRC und laesst NUR den DebugOutput-Detektor unter APath laufen.
// TFindingHelper.FindingsOf fixiert 'sample.pas' und kann Gate D nicht treffen.
function DebugCountForPath(const APath: string): Integer;
var
  Parser : TParser2;
  Root   : TAstNode;
  F      : TObjectList<TLeakFinding>;
begin
  F := TObjectList<TLeakFinding>.Create(True);
  try
    Parser := TParser2.Create;
    try
      Root := Parser.ParseSource(SINK_SRC);
      try
        TDebugOutputDetector.AnalyzeUnit(Root, APath, F);
      finally
        Root.Free;
      end;
    finally
      Parser.Free;
    end;
    Result := TFindingHelper.Count(F, fkDebugOutput);
  finally
    F.Free;
  end;
end;

procedure TTestDebugOutput.Debug_SystemQualifiedDespiteOwnMethod_StillReported;
// WAECHTER (Review 03.09.). Die Unit fuehrt eine eigene WriteLn-Methode -
// Gate E greift hier also. Der Aufruf ist aber EXPLIZIT System.-qualifiziert
// und damit per Sprachdefinition die RTL-Routine; er muss ein Fund bleiben.
//
// Genau diese Kombination ist der Normalfall: man schreibt "System." fast
// nur, wenn der unqualifizierte Name verschattet ist. Der bestehende Test
// Debug_SystemQualifiedWriteLn_ReportsWarning faengt das NICHT - seine
// Fixture traegt keine eigene Deklaration, Gate E wird dort nie aktiv.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TWriter = class'#13#10 +
  '  public'#13#10 +
  '    procedure WriteLn(const S: string);'#13#10 +
  '    procedure Dump;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TWriter.WriteLn(const S: string);'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'procedure TWriter.Dump;'#13#10 +
  'begin'#13#10 +
  '  System.WriteLn(''trace'');'#13#10 +
  'end;'#13#10 +
  'end.'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDebugOutput),
    'System.WriteLn bleibt ein Fund, auch wenn die Unit ein eigenes WriteLn hat');
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_OwnWriteLnMethod_NoFinding;
// Erkennerfehler (AQL-Neumessung 03.09.): ein unqualifizierter Aufruf
// bindet in Pascal zuerst an die eigene Klasse, erst dann an System.
// Wo eine Unit selbst ein WriteLn deklariert - Indys TIdIOHandler ist
// der Archetyp -, meint "WriteLn(..)" im Rumpf diese Methode und keine
// Konsolenausgabe. Am Korpus 68 der 2899 Funde (2,3 %).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TWriter = class'#13#10 +
  '  public'#13#10 +
  '    procedure WriteLn(const S: string);'#13#10 +
  '    procedure Dump;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TWriter.WriteLn(const S: string);'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'procedure TWriter.Dump;'#13#10 +
  'begin'#13#10 +
  '  WriteLn(''x'');'#13#10 +
  'end;'#13#10 +
  'end.'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDebugOutput),
    'eigene WriteLn-Methode ist kein RTL-Debug-Output');
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_PlainWriteLn_StillReported;
// WAECHTER: ohne eigene Deklaration bleibt WriteLn der RTL-Aufruf
// und damit ein Fund. Gate E darf nur greifen, wo die Unit den Namen
// wirklich selbst belegt.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Dump;'#13#10 +
  'begin'#13#10 +
  '  WriteLn(''x'');'#13#10 +
  'end;'#13#10 +
  'end.'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDebugOutput),
    'ohne eigene Deklaration bleibt WriteLn ein Fund');
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_LoggerFileName_NoFinding;
// In der Senke eines Logging-Frameworks ist die Ausgabe die IMPLEMENTIERUNG -
// der Regel-Remedy 'nimm einen Logger' waere dort zirkulaer.
// Beleg: LoggerPro.OutputDebugStringAppender.pas:87 (3 Vendoring-Kopien).
begin
  Assert.AreEqual<Integer>(0, DebugCountForPath('d:\repo\src\MyLogger.pas'),
    'Logger-Senke: WriteLn/OutputDebugString sind dort die Implementierung');
end;

procedure TTestDebugOutput.Debug_AppenderFileName_NoFinding;
// Beleg: LoggerPro.ConsoleAppender.pas:427/429 (3 Vendoring-Kopien).
begin
  Assert.AreEqual<Integer>(0,
    DebugCountForPath('d:\repo\lib\LoggerPro.ConsoleAppender.pas'),
    'Appender-Senke: WriteLn/OutputDebugString sind dort die Implementierung');
end;

procedure TTestDebugOutput.Debug_PlainFileName_StillReported;
// TP-Gegenprobe zu Gate D: nur der BASENAME entscheidet. Eine gewoehnliche
// Unit - auch eine, die unter einem Verzeichnis 'logger\' liegt - bleibt voll
// analysiert, sonst wuerde ein einziger Ordnername einen ganzen Baum stummschalten.
begin
  Assert.AreEqual<Integer>(2, DebugCountForPath('d:\repo\logger\uMain.pas'),
    'gewoehnliche Unit: WriteLn und OutputDebugString bleiben Funde');
end;

procedure TTestDebugOutput.Debug_TestsDirPath_NoFinding;
// Geltungsbereich-Gate Stufe 1: tplFixtureDir-Segment 'tests'.
// Ohne das Gate liefert DIESELBE Fixture 2 Funde (s.
// Debug_NeutralPath_StillReported) - dieser Test ist ohne den Fix rot.
begin
  Assert.AreEqual<Integer>(0, DebugCountForPath('d:\repo\tests\uFoo.pas'),
    'WriteLn in einer Testunit ist kein Debug-Rest');
end;

procedure TTestDebugOutput.Debug_SamplesDirPath_NoFinding;
// Stufe 1, breiter als der alte Versprechenstext: samples/demos
// gehoeren zur projektweiten Definition - ein Demo SCHREIBT absichtlich
// auf die Konsole.
begin
  Assert.AreEqual<Integer>(0, DebugCountForPath('d:\repo\samples\uBar.pas'),
    'WriteLn in einem Sample ist Zweck, kein Rest');
end;

procedure TTestDebugOutput.Debug_ConsoleUnitName_NoFinding;
// Stufe 2: *Console*-Unitname (wie versprochen) - alle 6 Korpus-Units
// dieser Klasse sind zweckgebundene CLI-Ausgabe (MVCFramework.Console
// u. a.).
begin
  Assert.AreEqual<Integer>(0, DebugCountForPath('d:\repo\src\MyConsoleApp.pas'),
    'eine Konsolen-Unit hat WriteLn als Zweck');
end;

procedure TTestDebugOutput.Debug_NeutralPath_StillReported;
// GEGENPROBE und Ohne-Fix-Anker: neutraler Pfad, neutraler Name ->
// beide Funde bleiben. Zusammen mit den drei 0-Erwartungen oben ist
// das Gate in beide Richtungen belegt.
begin
  Assert.AreEqual<Integer>(2, DebugCountForPath('d:\repo\src\uNormal.pas'),
    'ausserhalb des Gates meldet SCA017 unveraendert');
end;

end.
