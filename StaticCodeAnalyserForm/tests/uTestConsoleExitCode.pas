unit uTestConsoleExitCode;

// Tests fuer die Exit-Code-Ermittlung der CLI: die Rangleiter in
// TConsoleRunner.CalcExitCode und die Herabstufung durch --fail-on in
// ApplyFailOnPolicy.
//
// Warum es diese Unit gibt: bis 2026-08-08 war der Exit-Code voellig
// ungetestet - ausgerechnet die Zahl, an der jede CI-Pipeline haengt.
// Das fiel auf, als sich herausstellte, dass ein Lesefehler von jedem
// beliebigen Hint verdeckt wurde und --fail-on warning daraus eine 0
// machte: gruener Build fuer einen Scan, der Teile des Baums nie
// gesehen hat.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestConsoleExitCode = class
  public
    // ---- Herabstufung mit Lesefehler: Fussboden ist 4, nicht 0 ----
    [Test] procedure FailOnWarning_HintsPlusReadError_ExitsFour;
    [Test] procedure FailOnError_WarningsPlusReadError_ExitsFour;
    [Test] procedure FailOnHint_HintsPlusReadError_KeepsOne;

    // ---- 'none' ist die ausdrueckliche Ausnahme ----
    [Test] procedure FailOnNone_HintsPlusReadError_StaysZero;
    [Test] procedure FailOnNone_RawReadError_StaysZero;

    // ---- Ohne Lesefehler bleibt alles wie bisher ----
    [Test] procedure FailOnWarning_HintsWithoutReadError_StaysZero;
    [Test] procedure FailOnError_WarningsWithoutReadError_StaysZero;

    // ---- Die Rangleiter selbst bleibt unangetastet ----
    [Test] procedure Graded_HintsPlusReadError_KeepsLadder;
    [Test] procedure FailOnWarning_ErrorsPlusReadError_StaysThree;
    [Test] procedure FailOnWarning_RawReadError_StaysFour;

    // ---- Robustheit der Policy-Auswertung ----
    [Test] procedure PolicyValue_IsTrimmedAndCaseInsensitive;
    [Test] procedure UnknownPolicyValue_FallsBackToRaw;

    // ---- Quelle des Flags: die Klassifikation ----
    [Test] procedure CountBySeverity_ReadErrorNeverCountsAsSeverity;
    [Test] procedure CalcExitCode_HintPlusReadError_IsOne;
    [Test] procedure CalcExitCode_ReadErrorOnly_IsFour;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uMethodd12, uSCAConsts, uConsoleRunner;

const
  // Die Zahlen der Exit-Code-Konvention. Bewusst als Literale und nicht
  // ueber den Enum aus uConsoleRunner: der Test soll festnageln, WAS die
  // CLI nach aussen meldet, nicht nur, dass sie mit sich selbst konsistent
  // ist. Eine Umbenennung im Enum darf hier auffallen.
  EXIT_CLEAN      = 0;
  EXIT_HINTS      = 1;
  EXIT_WARNINGS   = 2;
  EXIT_ERRORS     = 3;
  EXIT_READERRORS = 4;

  // Die --fail-on-Werte und die beiden Lesefehler-Zustaende als Konstanten:
  // als Literale wiederholt zaehlt sie der eigene DuplicateString-Detektor.
  POL_GRADED  = 'graded';
  POL_NONE    = 'none';
  POL_HINT    = 'hint';
  POL_WARNING = 'warning';
  POL_ERROR   = 'error';

  WITH_READ_ERROR = 1;   // Anzahl unlesbarer Dateien im Lauf
  NO_READ_ERROR   = 0;

function MakeFinding(AKind: TFindingKind; ASev: TLeakSeverity): TLeakFinding;
begin
  Result := TLeakFinding.Create;
  Result.Kind       := AKind;
  Result.Severity   := ASev;
  Result.FileName   := 'uProbe.pas';
  Result.LineNumber := '1';
end;

{ ---- Herabstufung mit Lesefehler ---- }

procedure TTestConsoleExitCode.FailOnWarning_HintsPlusReadError_ExitsFour;
// Der Kernfall: vor dem Fix lieferte genau das eine 0.
begin
  Assert.AreEqual<Integer>(EXIT_READERRORS,
    ApplyFailOnPolicy(EXIT_HINTS, POL_WARNING, WITH_READ_ERROR));
end;

procedure TTestConsoleExitCode.FailOnError_WarningsPlusReadError_ExitsFour;
// Zeigt, dass der Fussboden in ALLEN herabstufenden Zweigen greift und
// nicht nur im 'warning'-Zweig.
begin
  Assert.AreEqual<Integer>(EXIT_READERRORS,
    ApplyFailOnPolicy(EXIT_WARNINGS, POL_ERROR, WITH_READ_ERROR));
end;

procedure TTestConsoleExitCode.FailOnHint_HintsPlusReadError_KeepsOne;
// 'hint' stuft hier nichts herab - der Fussboden darf den Rang NICHT
// ueberschreiben. Regressionsschutz gegen ein zu frueh gesetztes Exit(4).
begin
  Assert.AreEqual<Integer>(EXIT_HINTS,
    ApplyFailOnPolicy(EXIT_HINTS, POL_HINT, WITH_READ_ERROR));
end;

{ ---- 'none' ---- }

procedure TTestConsoleExitCode.FailOnNone_HintsPlusReadError_StaysZero;
begin
  Assert.AreEqual<Integer>(EXIT_CLEAN,
    ApplyFailOnPolicy(EXIT_HINTS, POL_NONE, WITH_READ_ERROR));
end;

procedure TTestConsoleExitCode.FailOnNone_RawReadError_StaysZero;
begin
  Assert.AreEqual<Integer>(EXIT_CLEAN,
    ApplyFailOnPolicy(EXIT_READERRORS, POL_NONE, WITH_READ_ERROR));
end;

{ ---- Ohne Lesefehler ---- }

procedure TTestConsoleExitCode.FailOnWarning_HintsWithoutReadError_StaysZero;
begin
  Assert.AreEqual<Integer>(EXIT_CLEAN,
    ApplyFailOnPolicy(EXIT_HINTS, POL_WARNING, NO_READ_ERROR));
end;

procedure TTestConsoleExitCode.FailOnError_WarningsWithoutReadError_StaysZero;
begin
  Assert.AreEqual<Integer>(EXIT_CLEAN,
    ApplyFailOnPolicy(EXIT_WARNINGS, POL_ERROR, NO_READ_ERROR));
end;

{ ---- Rangleiter ---- }

procedure TTestConsoleExitCode.Graded_HintsPlusReadError_KeepsLadder;
// Beide Schreibweisen des Defaults.
begin
  Assert.AreEqual<Integer>(EXIT_HINTS,
    ApplyFailOnPolicy(EXIT_HINTS, POL_GRADED, WITH_READ_ERROR));
  Assert.AreEqual<Integer>(EXIT_HINTS,
    ApplyFailOnPolicy(EXIT_HINTS, '', WITH_READ_ERROR));
end;

procedure TTestConsoleExitCode.FailOnWarning_ErrorsPlusReadError_StaysThree;
// Errors schlagen Lesefehler - der Fussboden darf das nicht kippen.
begin
  Assert.AreEqual<Integer>(EXIT_ERRORS,
    ApplyFailOnPolicy(EXIT_ERRORS, POL_WARNING, WITH_READ_ERROR));
  Assert.AreEqual<Integer>(EXIT_ERRORS,
    ApplyFailOnPolicy(EXIT_ERRORS, POL_ERROR, WITH_READ_ERROR));
end;

procedure TTestConsoleExitCode.FailOnWarning_RawReadError_StaysFour;
// Der bestehende Guard darf durch den Umbau nicht toter Code werden.
begin
  Assert.AreEqual<Integer>(EXIT_READERRORS,
    ApplyFailOnPolicy(EXIT_READERRORS, POL_WARNING, WITH_READ_ERROR));
end;

{ ---- Robustheit ---- }

procedure TTestConsoleExitCode.PolicyValue_IsTrimmedAndCaseInsensitive;
// Sichert, dass der neue Pfad HINTER LowerCase(Trim(...)) haengt.
begin
  Assert.AreEqual<Integer>(EXIT_READERRORS,
    ApplyFailOnPolicy(EXIT_HINTS, '  WARNING  ', WITH_READ_ERROR));
end;

procedure TTestConsoleExitCode.UnknownPolicyValue_FallsBackToRaw;
// Ein Tippfehler im Schalter liefert weiter das Default-Verhalten und
// nicht ploetzlich eine 4.
begin
  Assert.AreEqual<Integer>(EXIT_HINTS,
    ApplyFailOnPolicy(EXIT_HINTS, 'bogus', WITH_READ_ERROR));
end;

{ ---- Klassifikation ---- }

procedure TTestConsoleExitCode.CountBySeverity_ReadErrorNeverCountsAsSeverity;
// Die Severity des Lesefehlers wird bewusst ignoriert - hier steht sie
// absichtlich auf lsError und darf trotzdem nicht in Errors landen.
var
  L : TObjectList<TLeakFinding>;
  E, W, H, R : Integer;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding(fkFileReadError, lsError));
    L.Add(MakeFinding(fkMemoryLeak, lsHint));
    TConsoleRunner.CountBySeverity(L, E, W, H, R);
    Assert.AreEqual<Integer>(0, E, 'Lesefehler darf nicht als Error zaehlen');
    Assert.AreEqual<Integer>(0, W);
    Assert.AreEqual<Integer>(1, H);
    Assert.AreEqual<Integer>(1, R);
  finally
    L.Free;
  end;
end;

procedure TTestConsoleExitCode.CalcExitCode_HintPlusReadError_IsOne;
// Die Rangleiter bleibt: Hint schlaegt Lesefehler.
var
  L : TObjectList<TLeakFinding>;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding(fkFileReadError, lsError));
    L.Add(MakeFinding(fkMemoryLeak, lsHint));
    Assert.AreEqual<Integer>(EXIT_HINTS, TConsoleRunner.CalcExitCode(L));
  finally
    L.Free;
  end;
end;

procedure TTestConsoleExitCode.CalcExitCode_ReadErrorOnly_IsFour;
var
  L : TObjectList<TLeakFinding>;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding(fkFileReadError, lsError));
    Assert.AreEqual<Integer>(EXIT_READERRORS, TConsoleRunner.CalcExitCode(L));
  finally
    L.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConsoleExitCode);

end.
