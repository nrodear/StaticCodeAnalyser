unit uTestPointerName;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPointerName = class
  public
    [Test] procedure PointerWithP_NoFinding;
    [Test] procedure PointerWithoutP_Reported;
    [Test] procedure NonPointerType_NoFinding;
    [Test] procedure PointerName_KindAndSeverity;
    // --- Voll-Review 2026-09-12 (Blocker): Caret-Char-Notation ---
    [Test] procedure CaretCharConst_NotReported;
    [Test] procedure CaretCharInKeyPress_NotReported;
    [Test] procedure AliasAfterRecordEnd_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestPointerName.PointerWithP_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  PInteger = ^Integer;'#13#10 +
  '  PFoo = ^TFoo;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkPointerName));
  finally F.Free; end;
end;

procedure TTestPointerName.PointerWithoutP_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TIntPtr = ^Integer;'#13#10 +     // <-- Pointer ohne P-Prefix
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkPointerName));
  finally F.Free; end;
end;

procedure TTestPointerName.NonPointerType_NoFinding;
// Normaler Type-Alias ohne `^` - kein Treffer.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  end;'#13#10 +
  '  TIntArray = array of Integer;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkPointerName));
  finally F.Free; end;
end;

procedure TTestPointerName.PointerName_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TIntPtr = ^Integer;'#13#10 +
  'implementation end.';
var
  Findings : TObjectList<TLeakFinding>;
  Fnd      : TLeakFinding;
begin
  Findings := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in Findings do
      if Fnd.Kind = fkPointerName then
      begin
        Assert.AreEqual<TFindingKind>(fkPointerName, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,       Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkPointerName finding');
  finally Findings.Free; end;
end;

procedure TTestPointerName.CaretCharConst_NotReported;
// Voll-Review 2026-09-12 (Blocker): Delphis Caret-Notation fuer
// Steuerzeichen ('const CR = ^M;') matcht das Muster
// '<Ident> = ^<IdentStart>' - der zeilenweise Scan ohne
// Sektions-Kontext meldete 'rename to start with P', obwohl nirgends
// ein Pointer-Typ deklariert wird (Bestands-Exe: 2 Funde, empirisch
// belegt). Jetzt meldet nur die type-Sektion.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'const'#13#10 +
  '  CR = ^M;'#13#10 +
  '  LF = ^J;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkPointerName),
    'Caret-Char-Konstanten sind keine Pointer-Aliase');
  finally F.Free; end;
end;

procedure TTestPointerName.CaretCharInKeyPress_NotReported;
// Zweite Form desselben Blockers: 'if Key = ^C then' im
// Anweisungskontext (KeyPress-Handler-Idiom) matchte ueber den
// zweiten Ident der Zeile (Bestands-Exe: 1 Fund, empirisch belegt).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure HandleKey(var Key: Char);'#13#10 +
  'begin'#13#10 +
  '  if Key = ^C then'#13#10 +
  '    Key := #0;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkPointerName),
    'Caret-Char-Vergleich im Anweisungskontext ist kein Pointer-Alias');
  finally F.Free; end;
end;

procedure TTestPointerName.AliasAfterRecordEnd_StillReported;
// Gegenrichtung zum Sektions-Gate: das 'end;' eines record beendet die
// umgebende type-Sektion NICHT - der Nicht-P-Alias danach gehoert zum
// selben Block und muss weiter gemeldet werden (ein Gate, das an
// jedem 'end' ausschaltet, waere hier rot).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TRec = record'#13#10 +
  '    X: Integer;'#13#10 +
  '  end;'#13#10 +
  '  TBadPtr = ^TRec;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkPointerName),
    'Alias nach record-end liegt noch in der type-Sektion - Fund bleibt');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPointerName);

end.
