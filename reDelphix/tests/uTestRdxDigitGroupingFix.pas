unit uTestRdxDigitGroupingFix;

// Editorhilfe SCA069 DigitGrouping (uRdxDigitGroupingFix): der Planer auf
// Text (erste Fixture, FPC-tauglich) und der ECHTE Detektor (uDigitGrouping)
// auf dem echten AST ueber den Einstieg der Tabelle (TRdxFixTable.FixFor
// via PlanFixIn/FixAllWith, Adapter PlanDigitGrouping samt Plattenblick;
// zweite Fixture, nur Delphi). Die Rundlaeufe planen fuer 't.pas' ohne
// Verzeichnis - der Plattenblick liest dann nichts; die Tabellen-Tests
// legen Dateiart bzw. Projektdateien in einen eigenen Baum im TEMP.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxDigitGroupingFix = class
  public
    // ---- Umformung ----
    [Test] procedure Grouped_ThreeDigitGroupsFromRight;
    [Test] procedure ConstLiteral_Grouped;
    [Test] procedure LiteralInExpression_Grouped;
    [Test] procedure RangeBounds_Grouped;
    [Test] procedure SecondLiteralOfLine_Grouped;
    [Test] procedure CaseLabel_Grouped;
    [Test] procedure Program_Grouped;
    [Test] procedure NewerCompilerCheck_Grouped;
    // ---- Gegenproben ----
    [Test] procedure MovedOrNoColumn_NoHelp;
    [Test] procedure CommentOrString_NoHelp;
    [Test] procedure OtherLiteralForms_NoHelp;
    [Test] procedure CharCode_NoHelp;
    [Test] procedure Label_NoHelp;
    [Test] procedure Asm_NoHelp;
    [Test] procedure FpcSwitch_NoHelp;
    [Test] procedure OldCompiler_NoHelp;
    [Test] procedure NotCompiled_NoHelp;
    // ---- Gruende fuer den Adapter ----
    [Test] procedure FileNameReason_PpAndLpr;
    [Test] procedure ProjectReason_CarriesDetail;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxDigitGroupingDetector = class
  public
    [Test] procedure Detector_ReportsLineAndColumn;
    [Test] procedure Detector_RoundTrip;
    [Test] procedure Detector_TwoLiteralsOnLine_BothGrouped;
    [Test] procedure Detector_CatalogExample_Fixed;
    [Test] procedure Detector_RangeBound_Fixed;
    [Test] procedure Detector_CharCode_NoHelp;
    [Test] procedure Table_StaleFinding_NoHelp;
    // ---- Plattenblick des Adapters (Schwelle Delphi 11) ----
    [Test] procedure Table_PpFile_NoHelp;
    [Test] procedure Table_LazarusProject_NoHelp;
    [Test] procedure Table_DprojVersion_Threshold;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uDigitGrouping,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uRdxMagicFixes,        // FileReason (der erwartete Grund des Adapters)
  uTestRdxDetectorKit,   // TSeen, DetectSource, CatalogText, PlanFixIn,
                         // FixAllWith
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxDigitGroupingFix,
  uRdxText,              // _() und die gemeinsamen Gruende
  uTestRdxTextKit;       // Join, Apply, LineOf, NewMap

const
  BODY_LINE = 6;   // erste Rumpfzeile von InBody

// ---- Helfer ----

// Eine Unit mit EINER Routine; ihre erste Rumpfzeile ist Zeile 6.
function InBody(const ABody: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation', 'procedure Foo;',
    'begin']) + #13#10 + Join(ABody) + #13#10 + Join(['end;', 'end.']);
end;

// Die Meldung des Detektors fuer Spalte ACol; ohne Spalte (ACol = 0) eine
// Meldung ohne 'at column'.
function MessageAt(ACol: Integer): string;
begin
  if ACol = 0 then
    Result := 'Integer literal without digit grouping.'
  else
    Result := Format('Integer literal at column %d has >=%d digits without '
      + '`_` grouping - consider readability (e.g. 1_000_000).',
      [ACol, MIN_DIGITS]);
end;

// Der Planer fuer Zeile ALine, Spalte ACol: der neue Text, oder '' bei
// Ablehnung (AReason).
function PlanAt(const ASource: string; ALine, ACol: Integer;
  out AReason: string): string;
var
  Map : TRdxCodeMap;
  E   : TRdxEdit;
  Ok  : Boolean;
begin
  Result := '';
  AReason := '';
  Map := NewMap(ASource);
  try
    Ok := TRdxDigitGroupingFix.Group(Map, ALine, MessageAt(ACol), E, AReason);
  finally
    Map.Free;
  end;
  if Ok then
    Result := Apply(ASource, E);
end;

// Zeile und Spalte des ersten AText in ASource (Zeile 0 ohne Treffer).
procedure Locate(const ASource, AText: string; out ALine, ACol: Integer);
var
  SL : TStringList;
begin
  ACol := 0;
  ALine := LineOf(ASource, AText);
  if ALine = 0 then Exit;
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    ACol := Pos(AText, SL[ALine - 1]);
  finally
    SL.Free;
  end;
end;

// Die Hilfe am ersten AText muss gelten (sonst scheitert der Test mit dem
// Grund).
function Fix(const ASource, AText: string): string;
var
  Li, Co : Integer;
  R      : string;
begin
  Locate(ASource, AText, Li, Co);
  Assert.IsTrue(Li > 0, AText + ' steht nicht im Text');
  Result := PlanAt(ASource, Li, Co, R);
  Assert.IsTrue(Result <> '', R);
end;

// Die Hilfe am ersten AText muss abgelehnt werden - mit AReason.
procedure AssertRefused(const ASource, AText, AReason: string);
var
  Li, Co : Integer;
  R      : string;
begin
  Locate(ASource, AText, Li, Co);
  Assert.IsTrue(Li > 0, AText + ' steht nicht im Text');
  Assert.AreEqual('', PlanAt(ASource, Li, Co, R), 'keine Hilfe: ' + AText);
  Assert.AreEqual(AReason, R, 'Grund: ' + AText);
end;

function Moved: string;
begin
  Result := MsgMovedSuffix(_(R_DIG_MOVED));
end;

// ---- Umformung ----

procedure TTestRdxDigitGroupingFix.Grouped_ThreeDigitGroupsFromRight;
begin
  Assert.AreEqual('12_345', TRdxDigitGroupingFix.Grouped('12345'));
  Assert.AreEqual('123_456', TRdxDigitGroupingFix.Grouped('123456'));
  Assert.AreEqual('1_800_000', TRdxDigitGroupingFix.Grouped('1800000'));
  Assert.AreEqual('1_234_567_890', TRdxDigitGroupingFix.Grouped('1234567890'));
  Assert.AreEqual('999', TRdxDigitGroupingFix.Grouped('999'));
end;

procedure TTestRdxDigitGroupingFix.ConstLiteral_Grouped;
var
  Src : string;
begin
  Src := Join(['unit t;', 'interface', 'const', '  TIMEOUT_MS = 1800000;',
    'implementation', 'end.']);
  Assert.AreEqual(StringReplace(Src, '1800000', '1_800_000', []),
    Fix(Src, '1800000'));
end;

procedure TTestRdxDigitGroupingFix.LiteralInExpression_Grouped;
var
  Src : string;
begin
  Src := InBody(['  X := Y * 1048576 + 3;']);
  Assert.AreEqual(InBody(['  X := Y * 1_048_576 + 3;']), Fix(Src, '1048576'));
  // Ein Tab davor zaehlt als ein Zeichen - wie im Detektor.
  Src := InBody([#9'Z := 123456;']);
  Assert.AreEqual(InBody([#9'Z := 123_456;']), Fix(Src, '123456'));
end;

procedure TTestRdxDigitGroupingFix.RangeBounds_Grouped;
var
  Src, Step : string;
begin
  // Die linke Grenze vor '..' ist kein Float.
  Src := Join(['unit t;', 'interface', 'type', '  TRange = 10000..99999;',
    'implementation', 'end.']);
  Step := Fix(Src, '10000');
  Assert.AreEqual(StringReplace(Src, '10000..', '10_000..', []), Step);
  Assert.AreEqual(StringReplace(Src, '10000..99999', '10_000..99_999', []),
    Fix(Step, '99999'));
end;

procedure TTestRdxDigitGroupingFix.SecondLiteralOfLine_Grouped;
begin
  // Die Spalte entscheidet - nur dieses Literal.
  Assert.AreEqual(InBody(['  X := 12345 + 67_890;']),
    Fix(InBody(['  X := 12345 + 67890;']), '67890'));
end;

procedure TTestRdxDigitGroupingFix.CaseLabel_Grouped;
begin
  // Ohne label-Abschnitt ist '10000:' ein case-Zweig.
  Assert.AreEqual(InBody(['  case X of', '    10_000: Work;', '  end;']),
    Fix(InBody(['  case X of', '    10000: Work;', '  end;']), '10000'));
end;

procedure TTestRdxDigitGroupingFix.Program_Grouped;
var
  Src : string;
begin
  Src := Join(['program p;', 'begin', '  Sleep(1800000);', 'end.']);
  Assert.AreEqual(StringReplace(Src, '1800000', '1_800_000', []),
    Fix(Src, '1800000'));
end;

procedure TTestRdxDigitGroupingFix.NewerCompilerCheck_Grouped;
var
  Src : string;
begin
  // Eine Frage nach Delphi 12 (CompilerVersion 36) bzw. das Symbol von
  // Delphi 11 selbst (VER350) ist keine Spur aelterer Compiler.
  Src := Join(['unit t;', 'interface', '{$IF CompilerVersion >= 36}',
    '{$IFEND}', '{$IFDEF VER350}', '{$ENDIF}', 'const', '  X = 123456;',
    'implementation', 'end.']);
  Assert.AreEqual(StringReplace(Src, '123456', '123_456', []),
    Fix(Src, '123456'));
end;

// ---- Gegenproben ----

procedure TTestRdxDigitGroupingFix.MovedOrNoColumn_NoHelp;
var
  Src, R : string;
begin
  Src := InBody(['  X := 123456 + Y12345 + 1234;']);
  // Zeile hinter der Datei, keine Spalte in der Meldung.
  Assert.AreEqual('', PlanAt(Src, 99, 8, R));
  Assert.AreEqual(Moved, R, 'Zeile hinter der Datei');
  Assert.AreEqual('', PlanAt(Src, BODY_LINE, 0, R));
  Assert.AreEqual(MsgNoColumn, R, 'keine Spalte');
  // Mitten im Literal, auf dem Leerzeichen davor, hinter der Zeile.
  Assert.AreEqual('', PlanAt(Src, BODY_LINE, 9, R));
  Assert.AreEqual(Moved, R, 'mitten im Literal');
  Assert.AreEqual('', PlanAt(Src, BODY_LINE, 7, R));
  Assert.AreEqual(Moved, R, 'Leerzeichen');
  Assert.AreEqual('', PlanAt(Src, BODY_LINE, 99, R));
  Assert.AreEqual(Moved, R, 'hinter der Zeile');
  // Ziffern eines Bezeichners und ein Literal mit nur vier Ziffern.
  AssertRefused(Src, '12345 +', Moved);
  AssertRefused(Src, '1234;', Moved);
end;

procedure TTestRdxDigitGroupingFix.CommentOrString_NoHelp;
begin
  AssertRefused(InBody(['  X := 1; // 123456']), '123456', Moved);
  AssertRefused(InBody(['  S := ''123456'';']), '123456', Moved);
  AssertRefused(InBody(['  { 123456 }']), '123456', Moved);
end;

procedure TTestRdxDigitGroupingFix.OtherLiteralForms_NoHelp;
begin
  // Hex, Binaer, Bruchteil, Float mit Punkt bzw. Exponent, schon gruppiert.
  AssertRefused(InBody(['  A := $123456;']), '123456', Moved);
  AssertRefused(InBody(['  B := %101010;']), '101010', Moved);
  AssertRefused(InBody(['  C := 1.234567;']), '234567', Moved);
  AssertRefused(InBody(['  D := 123456.5;']), '123456', Moved);
  AssertRefused(InBody(['  E := 123456e3;']), '123456', Moved);
  AssertRefused(InBody(['  F := 12_345678;']), '12_', Moved);
  AssertRefused(InBody(['  F := 12_345678;']), '345678', Moved);
end;

procedure TTestRdxDigitGroupingFix.CharCode_NoHelp;
begin
  // Der Detektor meldet das Zeichenliteral mit (Recherche-Tabelle).
  AssertRefused(InBody(['  S := #65279;']), '65279', _(R_DIG_CHAR));
end;

procedure TTestRdxDigitGroupingFix.Label_NoHelp;
var
  Src, R : string;
begin
  Src := Join(['unit t;', 'interface', 'implementation', 'procedure Foo;',
    'label 10000;', 'begin', '  goto 10000;', '10000:', 'end;', 'end.']);
  // label-Abschnitt (Zeile 5, Spalte 7) und goto (Zeile 7, Spalte 8).
  Assert.AreEqual('', PlanAt(Src, 5, 7, R));
  Assert.AreEqual(_(R_DIG_LABEL, ['10000']), R, 'label');
  Assert.AreEqual('', PlanAt(Src, 7, 8, R));
  Assert.AreEqual(_(R_DIG_LABEL, ['10000']), R, 'goto');
  // Die Marke selbst: die Zahl ist in der Datei eine Marke.
  Assert.AreEqual('', PlanAt(Src, 8, 1, R));
  Assert.AreEqual(_(R_DIG_LABEL, ['10000']), R, 'Marke');
end;

procedure TTestRdxDigitGroupingFix.Asm_NoHelp;
var
  Src : string;
begin
  Src := Join(['unit t;', 'interface', 'implementation', 'procedure Foo;',
    'asm', '  MOV EAX, 123456', 'end;', 'procedure Bar;', 'begin',
    '  X := 654321;', 'end;', 'end.']);
  AssertRefused(Src, '123456', _(R_DIG_ASM));
  // Hinter dem asm-Block wieder Code.
  Assert.AreEqual(StringReplace(Src, '654321', '654_321', []),
    Fix(Src, '654321'));
end;

procedure TTestRdxDigitGroupingFix.FpcSwitch_NoHelp;
begin
  AssertRefused(Join(['unit t;', '{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}',
    'interface', 'const', '  X = 123456;', 'implementation', 'end.']),
    '123456', _(R_DIG_FPC, [2]));
end;

procedure TTestRdxDigitGroupingFix.OldCompiler_NoHelp;
begin
  // Wer nach Delphi 11 fragt, baut auch mit dem Compiler davor.
  AssertRefused(Join(['unit t;', 'interface', '{$IF CompilerVersion >= 35}',
    '{$IFEND}', 'const', '  X = 123456;', 'implementation', 'end.']),
    '123456', _(R_DIG_OLD, ['COMPILERVERSION >= 35', 3]));
  // DELPHI27 ist in der JEDI-Zaehlung Delphi 10.4.
  AssertRefused(Join(['unit t;', 'interface', '{$IFDEF DELPHI27_UP}',
    '{$ENDIF}', 'const', '  X = 123456;', 'implementation', 'end.']),
    '123456', _(R_DIG_OLD, ['DELPHI27_UP', 3]));
  AssertRefused(Join(['unit t;', '{$I jedi.inc}', 'interface', 'const',
    '  X = 123456;', 'implementation', 'end.']),
    '123456', _(R_DIG_OLD, ['jedi.inc', 2]));
end;

procedure TTestRdxDigitGroupingFix.NotCompiled_NoHelp;
begin
  // Ein Include und eine Unit ohne implementation-Teil (Skript).
  AssertRefused(Join(['const', '  X = 123456;']), '123456', _(R_DIG_SCRIPT));
  AssertRefused(Join(['unit t;', 'interface', 'const', '  X = 123456;',
    'end.']), '123456', _(R_DIG_SCRIPT));
end;

// ---- Gruende fuer den Adapter ----

procedure TTestRdxDigitGroupingFix.FileNameReason_PpAndLpr;
begin
  Assert.AreEqual(_(R_DIG_FILE, ['.pp']),
    TRdxDigitGroupingFix.FileNameReason('C:\src\unit1.pp'));
  Assert.AreEqual(_(R_DIG_FILE, ['.lpr']),
    TRdxDigitGroupingFix.FileNameReason('C:\src\Project1.LPR'));
  Assert.AreEqual('', TRdxDigitGroupingFix.FileNameReason('C:\src\unit1.pas'));
end;

procedure TTestRdxDigitGroupingFix.ProjectReason_CarriesDetail;
begin
  Assert.AreEqual(_(R_DIG_PROJECT, ['Lazarus x.lpi']),
    TRdxDigitGroupingFix.ProjectReason('Lazarus x.lpi'));
  Assert.IsTrue(Pos('x.lpi', TRdxDigitGroupingFix.ProjectReason('x.lpi')) > 0);
end;

{$IFNDEF FPC}

{ ---- Detektor ---- }

// Die Funde der Art SCA069 - der echte Detektor auf dem echten AST.
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TDigitGroupingDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_dig_', ASource, fkDigitGrouping, RunDetector);
end;

// Detect in der Form TDetectFunc (FixAllWith).
function DetectKind(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := DetectSource('rdx_dig_', ASource, AKind, RunDetector);
end;

// Die Hilfe fuer einen Fund ueber den Einstieg der Tabelle (PlanFixIn:
// TRdxFixTable.FixFor, Adapter PlanDigitGrouping) fuer die Datei AFile.
function PlanSeenIn(const ASource, AFile: string;
  const ASeen: TSeen): TRdxFixOutcome;
begin
  Result := PlanFixIn(ASource, AFile, fkDigitGrouping, ASeen);
end;

// Dasselbe fuer 't.pas' ohne Verzeichnis - der Plattenblick liest nichts.
function PlanSeen(const ASource: string; const ASeen: TSeen): TRdxFixOutcome;
begin
  Result := PlanSeenIn(ASource, 't.pas', ASeen);
end;

// Fund fuer Fund, nach jeder Ersetzung neu gemeldet, bis der Detektor
// schweigt (FixAllWith: ueber den Einstieg der Tabelle).
function FixAll(const ASource: string): string;
begin
  Result := FixAllWith(ASource, fkDigitGrouping, DetectKind);
end;

// Der erste Fund in InBody(['  X := Y * 1048576;']).
function FirstSeen(out ASource: string): TSeen;
var
  Seen : TArray<TSeen>;
begin
  ASource := InBody(['  X := Y * 1048576;']);
  Seen := Detect(ASource);
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  Result := Seen[0];
end;

// Ein Baum TEMP\rdx_dig_<GUID>\a\b\c\ - die Unit in C; die Projektdateien
// liest der Plattenblick in C, B und A (Root liegt ausserhalb).
function NewUnitDir(out ARoot: string): string;
begin
  ARoot := NewTempDir('rdx_dig_');
  Result := ARoot + 'a' + PathDelim + 'b' + PathDelim + 'c' + PathDelim;
  ForceDirectories(Result);
end;

procedure WriteDproj(const APath, AVersion: string);
begin
  WriteText(APath, '<?xml version="1.0" encoding="utf-8"?>' + #13#10
    + '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'
    + #13#10 + '  <PropertyGroup>' + #13#10
    + '    <ProjectVersion>' + AVersion + '</ProjectVersion>' + #13#10
    + '  </PropertyGroup>' + #13#10 + '</Project>');
end;

procedure TTestRdxDigitGroupingDetector.Detector_ReportsLineAndColumn;
var
  Seen : TArray<TSeen>;
begin
  Seen := Detect(InBody(['  X := Y * 1048576;']));
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  Assert.AreEqual<Integer>(BODY_LINE, Seen[0].Line, 'Zeile');
  Assert.AreEqual<Integer>(12, ColumnFromMessage(Seen[0].Msg), 'Spalte');
end;

procedure TTestRdxDigitGroupingDetector.Detector_RoundTrip;
var
  Src, Fixed : string;
begin
  Src := Join(['unit t;', 'interface', 'const', '  TIMEOUT_MS = 1800000;',
    '  MAX_BYTES = 10485760;', 'implementation', 'procedure Foo;', 'begin',
    '  Sleep(123456);', 'end;', 'end.']);
  Fixed := FixAll(Src);
  Assert.AreEqual(Join(['unit t;', 'interface', 'const',
    '  TIMEOUT_MS = 1_800_000;', '  MAX_BYTES = 10_485_760;',
    'implementation', 'procedure Foo;', 'begin', '  Sleep(123_456);', 'end;',
    'end.']), Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed)), 'der Detektor schweigt');
end;

procedure TTestRdxDigitGroupingDetector.Detector_TwoLiteralsOnLine_BothGrouped;
var
  Src : string;
begin
  // Je Zeile meldet der Detektor nur das erste - das zweite danach.
  Src := InBody(['  X := 12345 + 67890;']);
  Assert.AreEqual<Integer>(1, Length(Detect(Src)), 'ein Fund je Zeile');
  Assert.AreEqual(InBody(['  X := 12_345 + 67_890;']), FixAll(Src));
end;

procedure TTestRdxDigitGroupingDetector.Detector_CatalogExample_Fixed;
var
  Meta : TRuleMeta;
  Src  : string;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkDigitGrouping);
  Assert.IsTrue(Pos('1800000', Meta.BadExample) > 0, Meta.BadExample);
  Src := Join(['unit t;', 'interface']) + #13#10 + CatalogText(Meta.BadExample)
    + #13#10 + Join(['implementation', 'end.']);
  Assert.AreEqual(Join(['unit t;', 'interface']) + #13#10
    + CatalogText(Meta.GoodExample) + #13#10 + Join(['implementation', 'end.']),
    FixAll(Src));
end;

procedure TTestRdxDigitGroupingDetector.Detector_RangeBound_Fixed;
var
  Src : string;
begin
  // '10000..MAXBUF': die linke Grenze meldet der Detektor (Range, kein Float);
  // ebenso die rechte in '[0..10000]'.
  Src := Join(['unit t;', 'interface', 'const', '  MAXBUF = 99;', 'type',
    '  TRange = 10000..MAXBUF;', '  TBuf = array[0..10000] of Byte;',
    'implementation', 'end.']);
  Assert.AreEqual(StringReplace(Src, '10000', '10_000', [rfReplaceAll]),
    FixAll(Src));
end;

procedure TTestRdxDigitGroupingDetector.Detector_CharCode_NoHelp;
var
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
  Src  : string;
begin
  Src := InBody(['  S := #65279;']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen), 'der Detektor meldet den Zeichencode');
  O := PlanSeen(Src, Seen[0]);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_DIG_CHAR), O.Reason);
end;

procedure TTestRdxDigitGroupingDetector.Table_StaleFinding_NoHelp;
var
  S : TSeen;
  O : TRdxFixOutcome;
begin
  // Der Fund zeigt auf die Zeile darunter - dort steht kein Literal.
  S.Line := BODY_LINE + 1;
  S.Msg := MessageAt(12);
  S.Variant := '';
  O := PlanSeen(InBody(['  X := Y * 1048576;']), S);
  Assert.IsFalse(O.Enabled, 'gesperrt');
  Assert.AreEqual(Moved, O.Reason);
  Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
end;

procedure TTestRdxDigitGroupingDetector.Table_PpFile_NoHelp;
var
  Src : string;
  S   : TSeen;
  O   : TRdxFixOutcome;
begin
  // Die Dateiart allein (FileNameReason, ohne Plattenzugriff).
  S := FirstSeen(Src);
  O := PlanSeenIn(Src, 'C:\src\unit1.pp', S);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_DIG_FILE, ['.pp']), O.Reason);
  Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
  // Dieselbe Zeile in 't.pas': Angebot, bedeutungsgleich.
  O := PlanSeen(Src, S);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.IsFalse(O.ChangesBehavior, 'bedeutungsgleich');
end;

procedure TTestRdxDigitGroupingDetector.Table_LazarusProject_NoHelp;
var
  Root, Dir, U, Src : string;
  S                 : TSeen;
  O                 : TRdxFixOutcome;
begin
  // Ein Lazarus-Projekt eine Ebene ueber der Unit: sie baut wohl auch mit
  // FPC 3.2 - der Grund des Adapters (ProjectReason) traegt den Befund des
  // Plattenblicks mit dem Text der Zifferntrenner.
  S := FirstSeen(Src);
  Dir := NewUnitDir(Root);
  try
    U := Dir + 'u.pas';
    WriteText(ExtractFilePath(ExcludeTrailingPathDelimiter(Dir)) + 'x.lpi',
      '<CONFIG/>');
    O := PlanSeenIn(Src, U, S);
    Assert.IsFalse(O.Enabled, 'keine Hilfe');
    Assert.AreEqual(TRdxDigitGroupingFix.ProjectReason(
      TRdxMagicFixes.FileReason(U, lfDigitSeparator)), O.Reason);
    Assert.IsTrue(Pos('x.lpi', O.Reason) > 0, O.Reason);
    Assert.IsTrue(Pos('Zifferntrenner', O.Reason) > 0, O.Reason);
  finally
    RemoveTree(Root);
  end;
end;

procedure TTestRdxDigitGroupingDetector.Table_DprojVersion_Threshold;
var
  Root, Dir, U, Src : string;
  S                 : TSeen;
  O                 : TRdxFixOutcome;
begin
  // Zifferntrenner gibt es ab Delphi 11 (ProjectVersion 19.3): eine .dproj
  // mit 19.2 (Delphi 10.4) neben der Unit sperrt, 19.3 nicht - anders als
  // bei SCA014 (Schwelle 18.5).
  S := FirstSeen(Src);
  Dir := NewUnitDir(Root);
  try
    U := Dir + 'u.pas';
    WriteDproj(Dir + 'P.dproj', '19.2');
    O := PlanSeenIn(Src, U, S);
    Assert.IsFalse(O.Enabled, '19.2 = Delphi 10.4');
    Assert.IsTrue(Pos('ProjectVersion 19.2', O.Reason) > 0, O.Reason);
    Assert.IsTrue(Pos('Delphi 11 = 19.3', O.Reason) > 0, O.Reason);
    WriteDproj(Dir + 'P.dproj', '19.3');
    O := PlanSeenIn(Src, U, S);
    Assert.IsTrue(O.Enabled, '19.3 = Delphi 11: ' + O.Reason);
  finally
    RemoveTree(Root);
  end;
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxDigitGroupingFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxDigitGroupingDetector);
  {$ENDIF}

end.
