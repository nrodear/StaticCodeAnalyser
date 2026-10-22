unit uTestRdxNativeIntFix;

// Editorhilfe SCA161 PointerSubtraction (uRdxNativeIntFix):
//   Fixture 1 (Text, ohne Parser und Detektor): 'Integer(P1) -
//   Integer(P2)' -> NativeInt, 'Cardinal(..)'
//   -> NativeUInt; Gegenproben Kommentar, String, verschobene Zeile,
//   gemischte Casts, mehrere Treffer, Zahl als Operand, Kette, Kommentar
//   zwischen den Casts.
//   Fixture 2: der ECHTE Detektor meldet, der Adapter plant aus dem Fund,
//   die Ersetzung wird angewandt - und der Detektor schweigt.
// Die ganze Unit ist nur Delphi (reDelphix.Test): der Planer bindet
// uEngineApi/uRdxRecipeRunner und uRdxFixRunner, der FPC-Pruefstand
// (build.sh) fuehrt ihn nicht - die {$IFNDEF FPC}-Weichen sind heute ohne
// Wirkung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxNativeIntFix = class
  public
    [Test] procedure Signed_Integer_And_LongInt;
    [Test] procedure Unsigned_Cardinal_And_LongWord;
    [Test] procedure Spelling_And_Spacing_Kept;
    [Test] procedure Jump_Patch_With_Trailing_Term;
    [Test] procedure Comment_Line_NoHelp;
    [Test] procedure String_NoHelp;
    [Test] procedure Block_Comment_Line_NoHelp;
    [Test] procedure Moved_Line_NoHelp;
    [Test] procedure Mixed_Casts_NoHelp;
    [Test] procedure Two_Matches_NoHelp;
    [Test] procedure Number_Operand_NoHelp;
    [Test] procedure Chain_NoHelp;
    [Test] procedure Comment_Between_Casts_NoHelp;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxNativeIntFixDetector = class
  public
    [Test] procedure Detector_Integer_RoundTrip;
    [Test] procedure Detector_CatalogExample;
    [Test] procedure Detector_MixedCasts_NoHelp;
    [Test] procedure Adapter_Without_Lines_NoHelp;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  uRdxBufferMath, uRdxCodeMap, uRdxNativeIntFix,
  uTestRdxTextKit   // Join, Apply
{$IFNDEF FPC}
  , System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uPointerSubtraction,
  uRdxRecipeRunner, uTestRdxDetectorKit
{$ENDIF}
  ;

const
  // Kennungen in den Gruenden, die in en/de/fr gleich bleiben (ASCII in
  // Klammern bzw. Anfuehrung) - der Test haengt nicht an der Sprache.
  REASON_MOVED   = 'Cast(x) - Cast(y)';
  REASON_MANY    = '(SCA161)';
  REASON_MIXED   = 'NativeUInt';
  REASON_OPERAND = 'Cast(5)';
  REASON_CHAIN   = '- Integer(c)';
  REASON_NONCODE = 'Cast { } -';
  // Die Meldung des Detektors wird von der Hilfe nicht gelesen.
  MSG_161 = 'Cardinal/Cardinal subtraction on pointers truncates upper 32 '
    + 'bits on Win64 - use PtrUInt or NativeUInt';

// ---- Helfer ----

// Eine Unit mit einer Routine P; der Rumpf ab Zeile 6.
function InUnit(const ALines: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'implementation', 'procedure P;'])
    + #13#10 + 'begin' + #13#10 + Join(ALines) + #13#10 + Join(['end;', 'end.']);
end;

// Die Hilfe fuer Zeile ALine: neuer Text oder '' bei Ablehnung (AReason).
function Fix(const ASource: string; ALine: Integer;
  out AReason: string): string;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  E   : TRdxEdit;
begin
  Result := '';
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    if TRdxNativeIntFix.PointerSubtraction(Map, ALine, MSG_161, E, AReason) then
      Result := Apply(ASource, E);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Die Hilfe muss ablehnen, mit AReasonPart im Grund.
procedure AssertNoHelp(const ASource: string; ALine: Integer;
  const AReasonPart: string);
var
  R : string;
begin
  Assert.AreEqual('', Fix(ASource, ALine, R), 'keine Aenderung');
  Assert.IsTrue(Pos(AReasonPart, R) > 0, 'Grund: ' + R);
end;

// ---- Fixture 1 ----

procedure TTestRdxNativeIntFix.Signed_Integer_And_LongInt;
var
  R : string;
begin
  Assert.AreEqual(InUnit(['  Diff := NativeInt(P1) - NativeInt(P2);']),
    Fix(InUnit(['  Diff := Integer(P1) - Integer(P2);']), 6, R), R);
  Assert.AreEqual(InUnit(['  Diff := NativeInt(P1) - NativeInt(P2);']),
    Fix(InUnit(['  Diff := Longint(P1) - LongInt(P2);']), 6, R), R);
  // Integer und LongInt sind dasselbe: gemischt, aber eindeutig.
  Assert.AreEqual(InUnit(['  Diff := NativeInt(P1) - NativeInt(P2);']),
    Fix(InUnit(['  Diff := Integer(P1) - LongInt(P2);']), 6, R), R);
end;

procedure TTestRdxNativeIntFix.Unsigned_Cardinal_And_LongWord;
var
  R : string;
begin
  Assert.AreEqual(InUnit(['  Diff := NativeUInt(P1) - NativeUInt(P2);']),
    Fix(InUnit(['  Diff := Cardinal(P1) - Cardinal(P2);']), 6, R), R);
  Assert.AreEqual(InUnit(['  Diff := NativeUInt(P1) - NativeUInt(P2);']),
    Fix(InUnit(['  Diff := LongWord(P1) - Cardinal(P2);']), 6, R), R);
end;

procedure TTestRdxNativeIntFix.Spelling_And_Spacing_Kept;
var
  R : string;
begin
  // Abstaende, Operanden, Rest der Zeile und der Kommentar dahinter bleiben.
  Assert.AreEqual(
    InUnit(['  Diff:=NativeInt ( p1 ) -NativeInt(P2); // Offset']),
    Fix(InUnit(['  Diff:=INTEGER ( p1 ) -integer(P2); // Offset']), 6, R), R);
end;

procedure TTestRdxNativeIntFix.Jump_Patch_With_Trailing_Term;
var
  R : string;
begin
  // Korpus: Jump-Patch-Code. Der Rest des Ausdrucks bleibt stehen.
  Assert.AreEqual(
    InUnit(['  Rel := NativeInt(Dest) - NativeInt(Src) - 5;']),
    Fix(InUnit(['  Rel := Integer(Dest) - Integer(Src) - 5;']), 6, R), R);
end;

procedure TTestRdxNativeIntFix.Comment_Line_NoHelp;
begin
  AssertNoHelp(InUnit(['  // Diff := Integer(P1) - Integer(P2);']), 6,
    REASON_MOVED);
  AssertNoHelp(InUnit(['  Diff := 0; // Integer(P1) - Integer(P2)']), 6,
    REASON_MOVED);
end;

procedure TTestRdxNativeIntFix.String_NoHelp;
begin
  AssertNoHelp(InUnit(['  S := ''Integer(P1) - Integer(P2)'';']), 6,
    REASON_MOVED);
end;

procedure TTestRdxNativeIntFix.Block_Comment_Line_NoHelp;
begin
  // Die Zeile beginnt in einem Block-Kommentar.
  AssertNoHelp(InUnit(['  {', '  Diff := Integer(P1) - Integer(P2);', '  }']),
    7, REASON_MOVED);
end;

procedure TTestRdxNativeIntFix.Moved_Line_NoHelp;
begin
  // Der Fund meldete Zeile 6; dort steht jetzt etwas anderes.
  AssertNoHelp(InUnit(['  Inc(N);', '  Diff := Integer(P1) - Integer(P2);']),
    6, REASON_MOVED);
  // Ein Member namens Integer ist kein Cast des Detektor-Musters.
  AssertNoHelp(InUnit(['  Diff := R.Integer(P1) - Integer(P2);']), 6,
    REASON_MOVED);
end;

procedure TTestRdxNativeIntFix.Mixed_Casts_NoHelp;
begin
  AssertNoHelp(InUnit(['  Diff := Cardinal(P1) - Integer(P2);']), 6,
    REASON_MIXED);
end;

procedure TTestRdxNativeIntFix.Two_Matches_NoHelp;
begin
  AssertNoHelp(InUnit(['  A := Integer(P1) - Integer(P2); B := Integer(Q1) '
    + '- Integer(Q2);']), 6, REASON_MANY);
end;

procedure TTestRdxNativeIntFix.Number_Operand_NoHelp;
begin
  AssertNoHelp(InUnit(['  Diff := Integer(5) - Integer(P2);']), 6,
    REASON_OPERAND);
end;

procedure TTestRdxNativeIntFix.Chain_NoHelp;
begin
  AssertNoHelp(InUnit(['  Diff := Integer(A) - Integer(B) - Integer(C);']), 6,
    REASON_CHAIN);
end;

procedure TTestRdxNativeIntFix.Comment_Between_Casts_NoHelp;
begin
  AssertNoHelp(InUnit(['  Diff := Integer(P1) { Basis } - Integer(P2);']), 6,
    REASON_NONCODE);
end;

{$IFNDEF FPC}

// ---- Fixture 2 (nur Delphi) ----

procedure RunDetector(AKind: TFindingKind; Root: TAstNode; const Path: string;
  Results: TObjectList<TLeakFinding>);
begin
  TPointerSubtractionDetector.AnalyzeUnit(Root, Path, Results);
end;

// Der erste Fund des echten Detektors, geplant ueber den Adapter und
// angewandt; bei Ablehnung '' und der Grund in AReason.
function FixFirst(const ASource: string; out AReason: string): string;
var
  Seen    : TArray<TSeen>;
  SL      : TStringList;
  Finding : TLeakFinding;
  O       : TRdxFixOutcome;
begin
  Result := '';
  Seen := DetectSource('rdx_q5_', ASource, fkPointerSubtraction, RunDetector);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet');
  SL := TStringList.Create;
  Finding := TLeakFinding.New('t.pas', '', Seen[0].Line, Seen[0].Msg,
    fkPointerSubtraction);
  try
    SL.Text := ASource;
    O := PlanPointerSubtraction(nil, SL, Finding, nil);
    AReason := O.Reason;
    if O.Enabled then
      Result := Apply(ASource, O.Edits);
  finally
    Finding.Free;
    SL.Free;
  end;
end;

// Meldet der Detektor in ASource noch etwas?
function StillReported(const ASource: string): Boolean;
begin
  Result := Length(DetectSource('rdx_q5_', ASource, fkPointerSubtraction,
    RunDetector)) > 0;
end;

// Eine Routine mit Zeiger-Parametern und dem Rumpf ALine.
function WithPointers(const ALine: string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation',
    'procedure P(P1, P2: Pointer);', 'var Diff: NativeInt;', 'begin',
    ALine, 'end;', 'end.']);
end;

procedure TTestRdxNativeIntFixDetector.Detector_Integer_RoundTrip;
var
  Src, Fixed, R : string;
begin
  Src := WithPointers('  Diff := Integer(P1) - Integer(P2);');
  Fixed := FixFirst(Src, R);
  Assert.AreEqual(WithPointers('  Diff := NativeInt(P1) - NativeInt(P2);'),
    Fixed, R);
  Assert.IsFalse(StillReported(Fixed), 'der Detektor schweigt danach');
end;

procedure TTestRdxNativeIntFixDetector.Detector_CatalogExample;
const
  CAT_CASTS = 'Cardinal(P1) - Cardinal(P2)';
var
  Meta : TRuleMeta;
  Bad, Fixed, R : string;
begin
  // Katalog-Beispiel 'bad': Cardinal(P1) - Cardinal(P2) samt Kommentar.
  Meta := TRuleCatalog.GetRuleCanonical(fkPointerSubtraction);
  Bad := WithPointers(CatalogText(Meta.BadExample));
  // Erwartet: genau die beiden Casts aendern sich - ein 'Cardinal' im
  // Kommentar oder in einer Deklaration der Huelle bliebe stehen.
  Assert.IsTrue(Pos(CAT_CASTS, Bad) > 0, Bad);
  Fixed := FixFirst(Bad, R);
  Assert.AreEqual(StringReplace(Bad, CAT_CASTS,
    'NativeUInt(P1) - NativeUInt(P2)', []), Fixed, R);
  Assert.IsFalse(StillReported(Fixed), 'der Detektor schweigt danach');
end;

procedure TTestRdxNativeIntFixDetector.Detector_MixedCasts_NoHelp;
var
  R : string;
begin
  // Der Detektor meldet gemischte Casts (MixedCast_Reported) - die Hilfe
  // raet nicht NativeInt oder NativeUInt.
  Assert.AreEqual('',
    FixFirst(WithPointers('  Diff := Cardinal(P1) - Integer(P2);'), R));
  Assert.IsTrue(Pos(REASON_MIXED, R) > 0, R);
end;

procedure TTestRdxNativeIntFixDetector.Adapter_Without_Lines_NoHelp;
var
  Finding : TLeakFinding;
  O       : TRdxFixOutcome;
begin
  Finding := TLeakFinding.New('t.pas', '', 1, MSG_161, fkPointerSubtraction);
  try
    O := PlanPointerSubtraction(nil, nil, Finding, nil);
    Assert.IsFalse(O.Enabled);
    Assert.IsTrue(O.Reason <> '', 'ein Grund steht da');
    Assert.AreEqual<Integer>(0, Length(O.Edits));
  finally
    Finding.Free;
  end;
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxNativeIntFix);
{$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxNativeIntFixDetector);
{$ENDIF}

end.
