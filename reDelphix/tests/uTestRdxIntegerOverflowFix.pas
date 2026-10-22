unit uTestRdxIntegerOverflowFix;

// Editorhilfe SCA137 IntegerOverflow (uRdxIntegerOverflowFix): die Textform
// (CastLeft) und der Typbeweis aus den Antworten des Quellstellen-Diensts
// (ProofReason) auf Text (erste Fixture), der ECHTE Detektor
// (uIntegerOverflow) auf dem echten AST (zweite Fixture, nur Delphi). Den
// Adapter der Tabelle (PlanIntegerOverflow, fragt DeclaredTypeOf und
// InWithBlock) traegt uRdxFixTable - die Rundlaeufe hier gehen ueber ihren
// Einstieg mit geoeffnetem Quellstellen-Dienst (uTestRdxDetectorKit.
// PlanFixIn), der Typbeweis kommt also aus den Deklarationen der Quelle.
// Die Routine 'Foo' von Wrap deklariert Total: Int64 und Count,
// Size: Integer; die erste Rumpfzeile ist Zeile 9 (STMT_LINE).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxIntegerOverflowFix = class
  public
    // ---- Umformung ----
    [Test] procedure Product_CastsLeftOperand;
    [Test] procedure SpellingAndBlanks_Kept;
    [Test] procedure StatementOverTwoLines_CastsOnSecondLine;
    [Test] procedure CommentInside_CastsLeft;
    [Test] procedure SecondStatementOnLine_UsesNamedOne;
    [Test] procedure ElseBranch_CastsLeft;
    // ---- Gegenproben ----
    [Test] procedure MovedLine_NoHelp;
    [Test] procedure OtherStatement_NoHelp;
    [Test] procedure AlreadyCast_NoHelp;
    [Test] procedure PathTarget_NoHelp;
    [Test] procedure CommentOrString_NoHelp;
    [Test] procedure Directive_NoHelp;
    [Test] procedure Int64Shadowed_NoHelp;
    [Test] procedure TwiceOnLine_NoHelp;
    [Test] procedure MessageWithoutForm_NoHelp;
    // ---- Typbeweis (ProofReason) ----
    [Test] procedure Proof_IntegerOperands_Accepted;
    [Test] procedure Proof_OperandNotProven_Refused;
    [Test] procedure Proof_TargetNotInt64_Refused;
    [Test] procedure Proof_WithBlock_Refused;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxIntegerOverflowDetector = class
  public
    [Test] procedure Detector_ReportsLineAndMessage;
    [Test] procedure Detector_RoundTrip;
    [Test] procedure Detector_TwoProducts_BothFixed;
    [Test] procedure Detector_MultiLine_Fixed;
    [Test] procedure Detector_FieldTarget_Fixed;
    [Test] procedure Detector_CatalogExample_Fixed;
    [Test] procedure Detector_PathTarget_NoHelp;
    // ---- Typbeweis ueber die Tabelle ----
    [Test] procedure Table_Proven_EnabledAndMarked;
    [Test] procedure Table_DoubleOperand_NoHelp;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uIntegerOverflow,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uTestRdxDetectorKit,   // TSeen, DetectSource, CatalogText, PlanFixIn
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxIntegerOverflowFix,
  uRdxText,              // _() und die gemeinsamen Gruende
  uTestRdxTextKit;       // Join, Apply

const
  // Die Meldung des Detektors (uIntegerOverflow): Ziel, linker, rechter
  // Operand.
  MSG_FMT = '%s := %s * %s - product overflows in 32-bit before widening to '
    + 'Int64; cast one operand to Int64';
  STMT_LINE = 9;

// ---- Helfer ----

// Eine Unit mit der Routine Foo (Total: Int64; Count, Size: Integer); ABody
// ab Zeile 9.
function Wrap(const ABody: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation', 'procedure Foo;',
    'var', '  Total: Int64;', '  Count, Size: Integer;', 'begin']) + #13#10
    + Join(ABody) + #13#10 + Join(['end;', 'end.']);
end;

// Die Meldung zu 'ATarget := ALeft * ARight'.
function Msg(const ATarget, ALeft, ARight: string): string;
begin
  Result := Format(MSG_FMT, [ATarget, ALeft, ARight]);
end;

// Der Planer fuer Zeile ALine mit der Meldung AMessage.
function PlanOf(const ASource: string; ALine: Integer; const AMessage: string;
  out APlan: TRdxOverflowPlan; out AReason: string): Boolean;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    try
      Result := TRdxIntegerOverflowFix.CastLeft(Map, ALine, AMessage, APlan,
        AReason);
    finally
      Map.Free;
    end;
  finally
    SL.Free;
  end;
end;

// Die Hilfe fuer 'Total := Count * Size' auf ALine muss gelten; der neue Text.
function Applied(const ASource: string; ALine: Integer): string;
var
  P : TRdxOverflowPlan;
  R : string;
begin
  Assert.IsTrue(PlanOf(ASource, ALine, Msg('Total', 'Count', 'Size'), P, R), R);
  Result := Apply(ASource, P.Edit);
end;

// Keine Hilfe fuer 'Total := Count * Size' auf ALine, Grund AReason.
procedure AssertRefused(const ASource: string; ALine: Integer;
  const AReason: string);
var
  P : TRdxOverflowPlan;
  R : string;
begin
  Assert.IsFalse(PlanOf(ASource, ALine, Msg('Total', 'Count', 'Size'), P, R),
    'keine Hilfe');
  Assert.AreEqual(AReason, R, 'Grund');
end;

// Der Grund 'keine Anweisung' fuer 'Total := Count * Size'.
function MovedReason: string;
begin
  Result := MsgMovedSuffix(_(R_IO_MOVED, ['Total', 'Count', 'Size']));
end;

// Der Plan zu 'Total := Count * Size;' (fuer die Tests des Typbeweises).
function BasicPlan: TRdxOverflowPlan;
var
  R : string;
begin
  Assert.IsTrue(PlanOf(Wrap(['  Total := Count * Size;']), STMT_LINE,
    Msg('Total', 'Count', 'Size'), Result, R), R);
end;

// ---- Umformung ----

procedure TTestRdxIntegerOverflowFix.Product_CastsLeftOperand;
var
  P : TRdxOverflowPlan;
  R : string;
begin
  Assert.AreEqual(Wrap(['  Total := Int64(Count) * Size;']),
    Applied(Wrap(['  Total := Count * Size;']), STMT_LINE));
  // Nur der linke Operand; die Namen fuer Menuetext und Typbeweis.
  Assert.IsTrue(PlanOf(Wrap(['  Total := Count * Size;']), STMT_LINE,
    Msg('Total', 'Count', 'Size'), P, R), R);
  Assert.AreEqual('Count', P.Edit.Expected);
  Assert.AreEqual('Int64(Count)', P.Edit.NewText);
  Assert.AreEqual<Integer>(STMT_LINE, P.Edit.Span.StartLine);
  Assert.AreEqual('Total', P.Target);
  Assert.AreEqual('Count', P.Left);
  Assert.AreEqual('Size', P.Right);
end;

procedure TTestRdxIntegerOverflowFix.SpellingAndBlanks_Kept;
var
  P : TRdxOverflowPlan;
  R : string;
  Src : string;
begin
  // Gross/klein egal wie in Delphi; der Cast nimmt die Schreibweise des
  // Quelltexts, und der Plan nennt sie.
  Src := Wrap(['  total:=COUNT*size;']);
  Assert.AreEqual(Wrap(['  total:=Int64(COUNT)*size;']), Applied(Src, STMT_LINE));
  Assert.IsTrue(PlanOf(Src, STMT_LINE, Msg('Total', 'Count', 'Size'), P, R), R);
  Assert.AreEqual('COUNT', P.Left);
  Assert.AreEqual('total', P.Target);
end;

procedure TTestRdxIntegerOverflowFix.StatementOverTwoLines_CastsOnSecondLine;
begin
  // Der Detektor meldet die Zeile des Ziels; der Operand steht darunter.
  Assert.AreEqual(Wrap(['  Total :=', '    Int64(Count) * Size;']),
    Applied(Wrap(['  Total :=', '    Count * Size;']), STMT_LINE));
end;

procedure TTestRdxIntegerOverflowFix.CommentInside_CastsLeft;
begin
  Assert.AreEqual(Wrap(['  Total := Int64(Count) { Stueck } * Size; // Bytes']),
    Applied(Wrap(['  Total := Count { Stueck } * Size; // Bytes']), STMT_LINE));
end;

procedure TTestRdxIntegerOverflowFix.SecondStatementOnLine_UsesNamedOne;
begin
  // Die Meldung nennt Ziel und Operanden - die andere Anweisung bleibt.
  Assert.AreEqual(Wrap(['  Size := Count * Count; Total := Int64(Count) * Size;']),
    Applied(Wrap(['  Size := Count * Count; Total := Count * Size;']),
      STMT_LINE));
end;

procedure TTestRdxIntegerOverflowFix.ElseBranch_CastsLeft;
begin
  Assert.AreEqual(
    Wrap(['  if Count > 0 then Total := 0 else Total := Int64(Count) * Size;']),
    Applied(Wrap(['  if Count > 0 then Total := 0 else Total := Count * Size;']),
      STMT_LINE));
end;

// ---- Gegenproben ----

procedure TTestRdxIntegerOverflowFix.MovedLine_NoHelp;
var
  Src : string;
begin
  Src := Wrap(['  Total := Count * Size;']);
  AssertRefused(Src, STMT_LINE - 1, MovedReason);
  AssertRefused(Src, STMT_LINE + 1, MovedReason);
  AssertRefused(Src, 99, MovedReason);
  AssertRefused(Src, 0, MovedReason);
  // Die Fortsetzungszeile ist nicht die Zeile der Anweisung.
  AssertRefused(Wrap(['  Total :=', '    Count * Size;']), STMT_LINE + 1,
    MovedReason);
end;

procedure TTestRdxIntegerOverflowFix.OtherStatement_NoHelp;
begin
  // Der Fund ist veraltet bzw. die Anweisung ist mehr als das Produkt.
  AssertRefused(Wrap(['  Total := Count * Other;']), STMT_LINE, MovedReason);
  AssertRefused(Wrap(['  Total := Count * Size + 1;']), STMT_LINE, MovedReason);
  AssertRefused(Wrap(['  Total := Count * Size * 2;']), STMT_LINE, MovedReason);
  AssertRefused(Wrap(['  Total := Size * Count;']), STMT_LINE, MovedReason);
end;

procedure TTestRdxIntegerOverflowFix.AlreadyCast_NoHelp;
begin
  AssertRefused(Wrap(['  Total := Int64(Count) * Size;']), STMT_LINE,
    MovedReason);
end;

procedure TTestRdxIntegerOverflowFix.PathTarget_NoHelp;
begin
  // Die Regex des Detektors beginnt an der Wortgrenze hinter dem '.'.
  AssertRefused(Wrap(['  Self.Total := Count * Size;']), STMT_LINE,
    _(R_IO_PATH, ['Total']));
  AssertRefused(Wrap(['  R.Total := Count * Size;']), STMT_LINE,
    _(R_IO_PATH, ['Total']));
end;

procedure TTestRdxIntegerOverflowFix.CommentOrString_NoHelp;
begin
  // Kommentar und String sind nie Code.
  AssertRefused(Wrap(['  // Total := Count * Size;']), STMT_LINE, MovedReason);
  AssertRefused(Wrap(['  { Total := Count * Size; }']), STMT_LINE, MovedReason);
  AssertRefused(Wrap(['  S := ''Total := Count * Size;'';']), STMT_LINE,
    MovedReason);
end;

procedure TTestRdxIntegerOverflowFix.Directive_NoHelp;
begin
  AssertRefused(Wrap(['  Total := Count * {$IFDEF X} Size {$ENDIF};']),
    STMT_LINE, _(R_IO_DIRECTIVE));
end;

procedure TTestRdxIntegerOverflowFix.Int64Shadowed_NoHelp;
var
  Src : string;
begin
  // Ein eigener Typ, eine Routine bzw. eine Variable 'Int64' in der Datei.
  AssertRefused(Join(['unit t;', 'interface', 'type', '  Int64 = Integer;',
    'implementation', 'procedure Foo;', 'var', '  Total: Int64;',
    '  Count, Size: Integer;', 'begin', '  Total := Count * Size;', 'end;',
    'end.']), 11, _(R_IO_SHADOW));
  AssertRefused(Join(['unit t;', 'interface',
    'function Int64(A: Integer): Integer;', 'implementation', 'procedure Foo;',
    'var', '  Total: Int64;', '  Count, Size: Integer;', 'begin',
    '  Total := Count * Size;', 'end;', 'end.']), 10, _(R_IO_SHADOW));
  AssertRefused(Join(['unit t;', 'interface', 'var', '  Int64, Other: Boolean;',
    'implementation', 'procedure Foo;', 'var', '  Total: UInt64;',
    '  Count, Size: Integer;', 'begin', '  Total := Count * Size;', 'end;',
    'end.']), 11, _(R_IO_SHADOW));
  // Gegenprobe: eine typisierte Konstante 'C: Int64 = 0' deklariert nichts
  // namens Int64.
  Src := Join(['unit t;', 'interface', 'const', '  Limit: Int64 = 0;',
    'implementation', 'procedure Foo;', 'var', '  Total: Int64;',
    '  Count, Size: Integer;', 'begin', '  Total := Count * Size;', 'end;',
    'end.']);
  Assert.AreEqual(StringReplace(Src, ':= Count', ':= Int64(Count)', []),
    Applied(Src, 11));
end;

procedure TTestRdxIntegerOverflowFix.TwiceOnLine_NoHelp;
begin
  AssertRefused(Wrap(['  Total := Count * Size; Total := Count * Size;']),
    STMT_LINE, _(R_IO_MANY, ['Total', 'Count', 'Size']));
end;

procedure TTestRdxIntegerOverflowFix.MessageWithoutForm_NoHelp;
var
  P : TRdxOverflowPlan;
  R : string;
begin
  Assert.IsFalse(PlanOf(Wrap(['  Total := Count * Size;']), STMT_LINE, 'x',
    P, R));
  Assert.AreEqual(_(R_IO_NO_FORM), R);
  // Ein Literal als Operand meldet der Detektor nicht - die Hilfe nimmt es
  // auch aus einer Meldung nicht an.
  Assert.IsFalse(PlanOf(Wrap(['  Total := Count * 1024;']), STMT_LINE,
    Msg('Total', 'Count', '1024'), P, R));
  Assert.AreEqual(_(R_IO_NO_FORM), R);
end;

// ---- Typbeweis ----

procedure TTestRdxIntegerOverflowFix.Proof_IntegerOperands_Accepted;
var
  P : TRdxOverflowPlan;
begin
  P := BasicPlan;
  Assert.AreEqual('', TRdxIntegerOverflowFix.ProofReason(P, False, 'int64',
    'integer', 'integer'));
  Assert.AreEqual('', TRdxIntegerOverflowFix.ProofReason(P, False, 'uint64',
    'cardinal', 'integer'));
  Assert.AreEqual('', TRdxIntegerOverflowFix.ProofReason(P, False, 'qword',
    'longint', 'longword'));
  // DeclaredTypeOf liefert klein - ein gross geschriebener Typ gilt auch.
  Assert.AreEqual('', TRdxIntegerOverflowFix.ProofReason(P, False, 'Int64',
    'Integer', 'FixedInt'));
end;

procedure TTestRdxIntegerOverflowFix.Proof_OperandNotProven_Refused;
var
  P : TRdxOverflowPlan;
begin
  P := BasicPlan;
  // Unbekannt (Property, Funktion ohne Klammern, Vorfahr von ausserhalb).
  Assert.AreEqual(_(R_IO_OPERAND_TYPE, ['Count', _(R_IO_UNKNOWN)]),
    TRdxIntegerOverflowFix.ProofReason(P, False, 'int64', '', 'integer'));
  // Gleitkomma: 'Int64(X)' uebersetzte nicht.
  Assert.AreEqual(_(R_IO_OPERAND_TYPE, ['Size', 'double']),
    TRdxIntegerOverflowFix.ProofReason(P, False, 'int64', 'integer', 'double'));
  // Schon 64 Bit - dann ist der Fund ohnehin keiner.
  Assert.AreEqual(_(R_IO_OPERAND_TYPE, ['Count', 'int64']),
    TRdxIntegerOverflowFix.ProofReason(P, False, 'int64', 'int64', 'integer'));
  Assert.AreEqual(_(R_IO_OPERAND_TYPE, ['Count', 'variant']),
    TRdxIntegerOverflowFix.ProofReason(P, False, 'int64', 'variant', 'integer'));
  // Kleine Ganzzahltypen bleiben aussen vor (Integration, offener Punkt).
  Assert.AreEqual(_(R_IO_OPERAND_TYPE, ['Count', 'word']),
    TRdxIntegerOverflowFix.ProofReason(P, False, 'int64', 'word', 'integer'));
end;

procedure TTestRdxIntegerOverflowFix.Proof_TargetNotInt64_Refused;
var
  P : TRdxOverflowPlan;
begin
  P := BasicPlan;
  // Ein Integer-Ziel: der Cast liefe mit Bereichspruefung in ERangeError.
  Assert.AreEqual(_(R_IO_TARGET_TYPE, ['Total', 'integer']),
    TRdxIntegerOverflowFix.ProofReason(P, False, 'integer', 'integer',
      'integer'));
  Assert.AreEqual(_(R_IO_TARGET_TYPE, ['Total', _(R_IO_UNKNOWN)]),
    TRdxIntegerOverflowFix.ProofReason(P, False, '', 'integer', 'integer'));
end;

procedure TTestRdxIntegerOverflowFix.Proof_WithBlock_Refused;
var
  P : TRdxOverflowPlan;
begin
  P := BasicPlan;
  Assert.AreEqual(_(R_IO_WITH), TRdxIntegerOverflowFix.ProofReason(P, True,
    'int64', 'integer', 'integer'));
end;

{$IFNDEF FPC}

{ ---- Detektor ---- }

// Die Funde der Art SCA137 - der echte Detektor auf dem echten AST.
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TIntegerOverflowDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_io_', ASource, fkIntegerOverflow, RunDetector);
end;

// Fund fuer Fund, nach jeder Ersetzung neu gemeldet, bis der Detektor
// schweigt - ueber den Einstieg der Tabelle mit geoeffnetem
// Quellstellen-Dienst (PlanFixIn): den Typbeweis tragen die Deklarationen
// der Fixtures (Integer-Operanden, Int64-Ziel; lokal, gruppiert, Feld).
function FixAll(const ASource: string): string;
const
  MAX_PASSES = 10;
var
  Pass : Integer;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  Result := ASource;
  for Pass := 1 to MAX_PASSES do
  begin
    Seen := Detect(Result);
    if Length(Seen) = 0 then
      Exit;
    O := PlanFixIn(Result, 't.pas', fkIntegerOverflow, Seen[0]);
    Assert.IsTrue(O.Enabled, Format('Zeile %d: %s', [Seen[0].Line, O.Reason]));
    Result := Apply(Result, O.Edits);
  end;
  Assert.Fail('der Detektor schweigt auch nach zehn Durchlaeufen nicht');
end;

procedure TTestRdxIntegerOverflowDetector.Detector_ReportsLineAndMessage;
var
  Seen : TArray<TSeen>;
  T, L, R : string;
begin
  Seen := Detect(Wrap(['  Total := Count * Size;']));
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  Assert.AreEqual<Integer>(STMT_LINE, Seen[0].Line, 'Zeile des Ziels');
  Assert.AreEqual(Msg('Total', 'Count', 'Size'), Seen[0].Msg);
  Assert.IsTrue(ProductOf(Seen[0].Msg, T, L, R), Seen[0].Msg);
  Assert.AreEqual('Count', L);
end;

procedure TTestRdxIntegerOverflowDetector.Detector_RoundTrip;
var
  Fixed : string;
begin
  Fixed := FixAll(Wrap(['  Total := Count * Size;']));
  Assert.AreEqual(Wrap(['  Total := Int64(Count) * Size;']), Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed)),
    'der Detektor schweigt danach');
end;

procedure TTestRdxIntegerOverflowDetector.Detector_TwoProducts_BothFixed;
var
  Src : string;
begin
  Src := Wrap(['  Total := Count * Size;', '  Total := Size * Count;']);
  Assert.AreEqual<Integer>(2, Length(Detect(Src)), 'zwei Funde');
  Assert.AreEqual(Wrap(['  Total := Int64(Count) * Size;',
    '  Total := Int64(Size) * Count;']), FixAll(Src));
end;

procedure TTestRdxIntegerOverflowDetector.Detector_MultiLine_Fixed;
var
  Fixed : string;
begin
  Fixed := FixAll(Wrap(['  Total :=', '    Count * Size;']));
  Assert.AreEqual(Wrap(['  Total :=', '    Int64(Count) * Size;']), Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed)),
    'der Detektor schweigt danach');
end;

procedure TTestRdxIntegerOverflowDetector.Detector_FieldTarget_Fixed;
var
  Src : string;
begin
  // Ein Feld als Ziel (der Detektor sammelt es vor der ersten Routine).
  Src := Join(['unit t;', 'interface', 'type', '  TFoo = class',
    '    FTotal: Int64;', '    FCount, FSize: Integer;', '    procedure Run;',
    '  end;', 'implementation', 'procedure TFoo.Run;', 'begin',
    '  FTotal := FCount * FSize;', 'end;', 'end.']);
  Assert.AreEqual<Integer>(1, Length(Detect(Src)), 'ein Fund');
  Assert.AreEqual(StringReplace(Src, ':= FCount', ':= Int64(FCount)', []),
    FixAll(Src));
end;

procedure TTestRdxIntegerOverflowDetector.Detector_CatalogExample_Fixed;
var
  Meta : TRuleMeta;
  Src  : string;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkIntegerOverflow);
  Assert.IsTrue(Pos('SectorCount * SectorSize', Meta.BadExample) > 0,
    Meta.BadExample);
  // Das Beispiel (var-Teil und Rumpf) als Routine.
  Src := Join(['unit t;', 'interface', 'implementation', 'procedure Foo;',
    CatalogText(Meta.BadExample), 'end;', 'end.']);
  Assert.AreEqual<Integer>(1, Length(Detect(Src)), 'der Detektor meldet das Beispiel');
  Assert.AreEqual(StringReplace(Src, ':= SectorCount', ':= Int64(SectorCount)',
    []), FixAll(Src));
end;

procedure TTestRdxIntegerOverflowDetector.Detector_PathTarget_NoHelp;
var
  Src  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  // Der Detektor meldet auch 'Self.FTotal' (Wortgrenze hinter dem '.') -
  // die Hilfe castet nur fuer ein einfaches Ziel.
  Src := Join(['unit t;', 'interface', 'type', '  TFoo = class',
    '    FTotal: Int64;', '    FCount, FSize: Integer;', '    procedure Run;',
    '  end;', 'implementation', 'procedure TFoo.Run;', 'begin',
    '  Self.FTotal := FCount * FSize;', 'end;', 'end.']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  O := PlanFixIn(Src, 't.pas', fkIntegerOverflow, Seen[0]);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_IO_PATH, ['FTotal']), O.Reason);
end;

// Der Fund 'Total := Count * Size' auf STMT_LINE von Wrap (ohne Detektor -
// der Typbeweis ist Sache des Adapters).
function WrapSeen: TSeen;
begin
  Result.Line := STMT_LINE;
  Result.Msg := Msg('Total', 'Count', 'Size');
  Result.Variant := '';
end;

procedure TTestRdxIntegerOverflowDetector.Table_Proven_EnabledAndMarked;
var
  O : TRdxFixOutcome;
begin
  // Total: Int64, Count/Size: Integer (gruppiert) - bewiesen, angeboten,
  // gekennzeichnet (E2), Name der linke Operand.
  O := PlanFixIn(Wrap(['  Total := Count * Size;']), 't.pas',
    fkIntegerOverflow, WrapSeen);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.IsTrue(O.ChangesBehavior, 'gekennzeichnet');
  Assert.AreEqual('Count', O.Name);
  Assert.AreEqual<Integer>(1, Length(O.Edits));
end;

procedure TTestRdxIntegerOverflowDetector.Table_DoubleOperand_NoHelp;
var
  Src  : string;
  Seen : TSeen;
  O    : TRdxFixOutcome;
begin
  // Size: Double - der Cast aenderte die Rechnung; DeclaredTypeOf liefert
  // den Typ klein. Die Anweisung steht eine Zeile tiefer als in Wrap.
  Src := Join(['unit t;', 'interface', 'implementation', 'procedure Foo;',
    'var', '  Total: Int64;', '  Count: Integer;', '  Size: Double;',
    'begin', '  Total := Count * Size;', 'end;', 'end.']);
  Seen := WrapSeen;
  Seen.Line := STMT_LINE + 1;
  O := PlanFixIn(Src, 't.pas', fkIntegerOverflow, Seen);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_IO_OPERAND_TYPE, ['Size', 'double']), O.Reason);
  Assert.IsTrue(O.ChangesBehavior, 'auch gesperrt gekennzeichnet');
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxIntegerOverflowFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxIntegerOverflowDetector);
  {$ENDIF}

end.
