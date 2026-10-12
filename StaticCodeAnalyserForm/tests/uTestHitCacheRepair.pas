unit uTestHitCacheRepair;

// Tests fuer uHitCacheRepair (SCA.SharedUI) - Fix F1 der Caret-Untersuchung
// 2026-10-12: der Voll-Repaint, mit dem uIDELineHighlighter seinen Hover-
// und Klick-Trefferspeicher nachfuellt, laeuft nur noch einmal je
// Sichtzustand statt bei jedem Fehltreffer der Maus alle 500 ms. Jeder
// dieser Repaints hatte die Blinkphase des Carets neu gestartet.
//
// Die Uhr ist ein Parameter: die Tests spielen Minuten in Millisekunden
// durch, ohne Sleep. "Paint" heisst hier: die IDE hat den angeforderten
// Repaint ausgefuehrt, und EndPaint meldet ihn mit dem Sichtzustand von
// dann (NotePaintCompleted).
//
// UNGEDECKT bleibt die IDE-Seite (uIDELineHighlighter: welche Ereignisse die
// Generation hochzaehlen, woher TopRow und LeftColumn kommen) und der Caret
// selbst - das misst Nico in der IDE (caretprobe, Abnahmeliste der
// Synthese).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestHitCacheRepair = class
  public
    [Test] procedure FirstMiss_Repairs;
    // Kern-Regressionstest gegen H1.
    [Test] procedure SameView_120MissesOverOneMinute_RepairOnce;
    [Test] procedure ConfirmedView_NeverRepairsAgain;
    [Test] procedure TopRowChange_RepairsExactlyOnce;
    [Test] procedure LeftColumnChange_RepairsExactlyOnce;
    [Test] procedure FileChange_RepairsExactlyOnce;
    [Test] procedure EditorChange_RepairsExactlyOnce;
    [Test] procedure GenerationBump_RepairsExactlyOnce;
    [Test] procedure NewViewWithinThrottle_WaitsThenRepairsOnce;
    [Test] procedure RequestWithoutPaint_AllowedAgainAfterThrottle;
    [Test] procedure UnrequestedPaint_ConfirmsNothing;
    [Test] procedure InvalidateAll_CountsAsRepairOfCurrentView;
    [Test] procedure InvalidateAll_ArmsTheThrottle;
    [Test] procedure MarkRebuild_InvalidateResetInvalidate_NoExtraRepair;
    [Test] procedure ForceFullRepaintOutsideRequest_RepairsExactlyOnce;
    [Test] procedure ForceFullRepaintInsideRequestedPaint_NoLoop;
    [Test] procedure Reset_AllowsRepairAgain;
    [Test] procedure TimeBase_Beyond32Bit_IsNotTruncated;
    [Test] procedure ClockBeforeLastCheck_FailsOpenWithoutOverflow;
    [Test] procedure UnreachableEditor_ThrottlesWithoutRequest;
  end;

implementation

uses
  uHitCacheRepair;

const
  EDITOR_A = 1001;
  EDITOR_B = 1002;
  // Fuer den Schluessel ist der Name undurchsichtig - ein Pfad muss es
  // nicht sein (und ein fester Pfad waere im Selbst-Scan SCA016).
  FILE_A   = 'Unit1.pas';
  FILE_B   = 'Unit2.pas';
  // Ein Takt knapp ueber der Drossel: JEDE simulierte Mausnachricht kommt
  // durch die Drossel und wird wirklich geprueft. Der alte Code haette bei
  // diesem Takt jedes Mal neu gemalt.
  STEP_MS  = HIT_CACHE_THROTTLE_MS + 1;
  // 120 Takte zu 501 ms: eine gute Minute Mausbewegung.
  MISSES   = 120;
  START_MS = 10000;

function ViewA(var ARepair: THitCacheRepair; ATopRow: Integer): THitCacheViewKey;
// Editor A, Datei A, linke Spalte 1 - die Tests variieren nur, worum es
// ihnen geht.
begin
  Result := ARepair.MakeKey(EDITOR_A, FILE_A, ATopRow, 1);
end;

function CountRepairs(var ARepair: THitCacheRepair;
  const AKey: THitCacheViewKey; AStartMs: UInt64): Integer;
// MISSES Fehltreffer im Takt STEP_MS ab AStartMs. Auf jede Reparatur folgt
// - wie in der IDE - der Paint, den EndPaint mit demselben Sichtzustand
// meldet. Liefert die Zahl der Reparaturen.
var
  I : Integer;
begin
  Result := 0;
  for I := 0 to MISSES - 1 do
    if ARepair.ShouldRepair(AKey, AStartMs + UInt64(I) * STEP_MS) then
    begin
      Inc(Result);
      ARepair.NotePaintCompleted(AKey);
    end;
end;

procedure ConfirmView(var ARepair: THitCacheRepair;
  const AKey: THitCacheViewKey; ANowMs: UInt64);
// Ausgangslage vieler Tests: fuer AKey ist bei ANowMs ein Voll-Repaint
// angefordert worden und gelaufen.
begin
  ARepair.NoteInvalidateAll(ANowMs);
  ARepair.NotePaintCompleted(AKey);
end;

procedure TTestHitCacheRepair.FirstMiss_Repairs;
var
  R : THitCacheRepair;
begin
  R.Reset;
  Assert.IsTrue(R.ShouldRepair(ViewA(R, 1), START_MS),
    'Der erste Fehltreffer fuellt den Speicher nach');
  Assert.IsTrue(R.HasPendingRequest, 'Die Anforderung ist vorgemerkt');
end;

procedure TTestHitCacheRepair.SameView_120MissesOverOneMinute_RepairOnce;
// H1: der alte Code malte hier 120-mal den ganzen Editor neu und startete
// den Caret 120-mal neu.
var
  R : THitCacheRepair;
begin
  R.Reset;
  Assert.AreEqual<Integer>(1, CountRepairs(R, ViewA(R, 1), START_MS),
    'Im selben Sichtzustand genau eine Reparatur');
end;

procedure TTestHitCacheRepair.ConfirmedView_NeverRepairsAgain;
var
  R : THitCacheRepair;
  K : THitCacheViewKey;
begin
  R.Reset;
  K := ViewA(R, 1);
  Assert.IsTrue(R.ShouldRepair(K, START_MS));
  R.NotePaintCompleted(K);
  Assert.IsFalse(R.HasPendingRequest, 'EndPaint hat bestaetigt');
  Assert.IsFalse(R.ShouldRepair(K, START_MS + 1000));
  Assert.IsTrue(R.IsThrottled(START_MS + 1001),
    'Auch eine Pruefung ohne Reparatur drosselt die naechste - der '
    + 'Highlighter fragt die ToolsAPI hoechstens zweimal je Sekunde');
  Assert.AreEqual<Integer>(0, CountRepairs(R, K, START_MS + 2000),
    'Die erste Minute danach');
  Assert.AreEqual<Integer>(0, CountRepairs(R, K, START_MS + 3600000),
    'Eine Stunde spaeter');
end;

procedure TTestHitCacheRepair.TopRowChange_RepairsExactlyOnce;
// Mausrad-Scroll ohne EditorScrolled: nur TopRow aendert sich.
var
  R : THitCacheRepair;
begin
  R.Reset;
  ConfirmView(R, ViewA(R, 1), START_MS);
  Assert.AreEqual<Integer>(1, CountRepairs(R, ViewA(R, 40),
    START_MS + STEP_MS), 'Neue oberste Zeile: genau eine Reparatur');
end;

procedure TTestHitCacheRepair.LeftColumnChange_RepairsExactlyOnce;
var
  R : THitCacheRepair;
begin
  R.Reset;
  ConfirmView(R, ViewA(R, 1), START_MS);
  Assert.AreEqual<Integer>(1, CountRepairs(R,
    R.MakeKey(EDITOR_A, FILE_A, 1, 30), START_MS + STEP_MS),
    'Waagerecht gescrollt: genau eine Reparatur');
end;

procedure TTestHitCacheRepair.FileChange_RepairsExactlyOnce;
var
  R : THitCacheRepair;
begin
  R.Reset;
  ConfirmView(R, ViewA(R, 1), START_MS);
  Assert.AreEqual<Integer>(1, CountRepairs(R,
    R.MakeKey(EDITOR_A, FILE_B, 1, 1), START_MS + STEP_MS),
    'Tab-Wechsel im selben Editor: genau eine Reparatur');
end;

procedure TTestHitCacheRepair.EditorChange_RepairsExactlyOnce;
var
  R : THitCacheRepair;
begin
  R.Reset;
  ConfirmView(R, ViewA(R, 1), START_MS);
  Assert.AreEqual<Integer>(1, CountRepairs(R,
    R.MakeKey(EDITOR_B, FILE_A, 1, 1), START_MS + STEP_MS),
    'Anderes Editorfenster: genau eine Reparatur');
end;

procedure TTestHitCacheRepair.GenerationBump_RepairsExactlyOnce;
// Groesse, Faltung, verschobene Marken: Sichtwerte gleich, Speicher alt.
var
  R      : THitCacheRepair;
  Before : THitCacheViewKey;
  After  : THitCacheViewKey;
begin
  R.Reset;
  Before := ViewA(R, 1);
  ConfirmView(R, Before, START_MS);
  R.BumpGeneration;
  After := ViewA(R, 1);
  Assert.IsFalse(SameHitCacheViewKey(Before, After),
    'Die Generation gehoert zum Schluessel');
  Assert.AreEqual<Integer>(1, CountRepairs(R, After, START_MS + STEP_MS),
    'Nach dem Hochzaehlen genau eine Reparatur');
  // Die Generation ZAEHLT - ein Merker oder ein Kippschalter reichte nicht:
  // in der IDE folgt auf Scroll und Settle-Repaint das naechste Ereignis
  // (Groesse, Faltung, Dateiwechsel A->C->A im Paint = zweimal hoch).
  R.BumpGeneration;
  R.BumpGeneration;
  Assert.AreEqual<Integer>(1, CountRepairs(R, ViewA(R, 1), START_MS + 100000),
    'Zwei Ereignisse ohne Paint dazwischen');
  R.BumpGeneration;
  Assert.AreEqual<Integer>(1, CountRepairs(R, ViewA(R, 1), START_MS + 200000),
    'Drittes Ereignis nach Bestaetigung');
end;

procedure TTestHitCacheRepair.NewViewWithinThrottle_WaitsThenRepairsOnce;
var
  R : THitCacheRepair;
begin
  R.Reset;
  Assert.IsTrue(R.ShouldRepair(ViewA(R, 1), START_MS));
  R.NotePaintCompleted(ViewA(R, 1));
  Assert.IsFalse(R.ShouldRepair(ViewA(R, 40), START_MS + 200),
    'Neuer Sichtzustand, aber innerhalb der Drossel');
  Assert.IsFalse(R.ShouldRepair(ViewA(R, 40), START_MS
    + HIT_CACHE_THROTTLE_MS), 'Genau 500 ms reichen nicht (wie bisher: > 500)');
  Assert.IsTrue(R.ShouldRepair(ViewA(R, 40), START_MS
    + HIT_CACHE_THROTTLE_MS + 1), 'Nach Ablauf der Drossel');
  R.NotePaintCompleted(ViewA(R, 40));
  Assert.AreEqual<Integer>(0, CountRepairs(R, ViewA(R, 40), START_MS + 2000),
    'Danach keine weitere');
end;

procedure TTestHitCacheRepair.RequestWithoutPaint_AllowedAgainAfterThrottle;
// Editor verdeckt oder der Repaint ging an ein anderes Editorfenster: ohne
// EndPaint keine Bestaetigung - nach der Drossel darf es erneut versuchen.
var
  R : THitCacheRepair;
begin
  R.Reset;
  Assert.IsTrue(R.ShouldRepair(ViewA(R, 1), START_MS));
  Assert.IsFalse(R.ShouldRepair(ViewA(R, 1), START_MS + 400),
    'Innerhalb der Drossel');
  Assert.IsTrue(R.ShouldRepair(ViewA(R, 1), START_MS + 501),
    'Unbestaetigt: nach der Drossel erneut');
end;

procedure TTestHitCacheRepair.UnrequestedPaint_ConfirmsNothing;
// Ein partieller Paint ohne Anforderung (Scroll legt ein paar Zeilen frei)
// fuellt den Speicher nicht vollstaendig und darf die Reparatur nicht
// verdecken.
var
  R : THitCacheRepair;
begin
  R.Reset;
  R.NotePaintCompleted(ViewA(R, 1));
  Assert.IsFalse(R.HasPendingRequest);
  Assert.IsTrue(R.ShouldRepair(ViewA(R, 1), START_MS),
    'Der Paint ohne Anforderung hat nichts bestaetigt');
  // Auch nach einer Bestaetigung nicht: eine Pruefung OHNE Reparatur darf
  // nichts vormerken. Sonst bestaetigte der naechste partielle Paint nach
  // einem Rad-Scroll ohne EditorScrolled die neue oberste Zeile - genau
  // der Fall, fuer den es die Reparatur gibt.
  R.NotePaintCompleted(ViewA(R, 1));
  Assert.IsFalse(R.ShouldRepair(ViewA(R, 1), START_MS + 1000));
  Assert.IsFalse(R.HasPendingRequest,
    'Eine Pruefung ohne Reparatur merkt nichts vor');
  R.NotePaintCompleted(ViewA(R, 40));
  Assert.IsTrue(R.ShouldRepair(ViewA(R, 40), START_MS + 2000),
    'Partieller Paint nach Rad-Scroll ohne EditorScrolled bestaetigt nichts');
end;

procedure TTestHitCacheRepair.InvalidateAll_CountsAsRepairOfCurrentView;
// Scroll mit EditorScrolled: Generation hoch, 90 ms spaeter der Settle-
// Repaint (InvalidateAllLines), dann malt die IDE. Der erste Fehltreffer
// danach darf nicht noch einmal reparieren (Gegenpruefung 2.8).
var
  R : THitCacheRepair;
begin
  R.Reset;
  ConfirmView(R, ViewA(R, 1), START_MS);
  R.BumpGeneration;
  R.NoteInvalidateAll(START_MS + 2000);
  Assert.IsTrue(R.HasPendingRequest, 'Der Settle-Repaint ist angefordert');
  R.NotePaintCompleted(ViewA(R, 40));
  Assert.AreEqual<Integer>(0, CountRepairs(R, ViewA(R, 40), START_MS + 3000),
    'Der Settle-Repaint war die Reparatur');
end;

procedure TTestHitCacheRepair.InvalidateAll_ArmsTheThrottle;
// Waehrend ein Voll-Repaint unterwegs ist, wird nicht nachgelegt.
var
  R : THitCacheRepair;
begin
  R.Reset;
  R.NoteInvalidateAll(START_MS);
  Assert.IsTrue(R.IsThrottled(START_MS + 400));
  Assert.IsFalse(R.ShouldRepair(ViewA(R, 1), START_MS + 400),
    'Fehltreffer kurz nach einem Voll-Repaint');
  Assert.IsFalse(R.IsThrottled(START_MS + 501), 'Drossel abgelaufen');
end;

procedure TTestHitCacheRepair.MarkRebuild_InvalidateResetInvalidate_NoExtraRepair;
// SetAllFindings: InvalidateAllLines, ResetState (Generation hoch),
// InvalidateAllLines; RemoveMarks dasselbe ohne das zweite Invalidate. Der
// Paint danach bestaetigt den Stand NACH dem Hochzaehlen.
var
  R : THitCacheRepair;
begin
  R.Reset;
  R.NoteInvalidateAll(START_MS);
  R.BumpGeneration;
  R.NoteInvalidateAll(START_MS + 1);
  R.NotePaintCompleted(ViewA(R, 1));
  Assert.AreEqual<Integer>(0, CountRepairs(R, ViewA(R, 1), START_MS + 1000),
    'Neue Marken: keine Reparatur hinterher');
end;

procedure TTestHitCacheRepair.ForceFullRepaintOutsideRequest_RepairsExactlyOnce;
// Die IDE schickt von sich aus ForceFullRepaint: BeginPaint leert den
// Speicher, der Sichtzustand bleibt. War der Paint nur partiell, muss der
// naechste Fehltreffer genau einmal reparieren (Gegenpruefung 2.8,
// Ergaenzung 1).
var
  R : THitCacheRepair;
begin
  R.Reset;
  ConfirmView(R, ViewA(R, 1), START_MS);
  R.BumpGeneration;
  R.NotePaintCompleted(ViewA(R, 1));
  Assert.AreEqual<Integer>(1, CountRepairs(R, ViewA(R, 1), START_MS + STEP_MS),
    'Genau eine Reparatur nach ForceFullRepaint');
end;

procedure TTestHitCacheRepair.ForceFullRepaintInsideRequestedPaint_NoLoop;
// Kommt der ANGEFORDERTE Repaint selbst mit ForceFullRepaint, zaehlt
// BeginPaint die Generation zwischen Anforderung und EndPaint hoch.
// Bestaetigt wird der Stand von EndPaint - sonst reparierte jeder
// Fehltreffer wieder, und H1 waere zurueck.
var
  R : THitCacheRepair;
  I : Integer;
  N : Integer;
  T : UInt64;
begin
  R.Reset;
  N := 0;
  for I := 0 to MISSES - 1 do
  begin
    T := START_MS + UInt64(I) * STEP_MS;
    if R.ShouldRepair(ViewA(R, 1), T) then
    begin
      Inc(N);
      R.BumpGeneration;                    // BeginPaint(ForceFullRepaint)
      R.NotePaintCompleted(ViewA(R, 1));   // EndPaint
    end;
  end;
  Assert.AreEqual<Integer>(1, N, 'Keine Reparatur-Schleife');
end;

procedure TTestHitCacheRepair.Reset_AllowsRepairAgain;
// Mit Absicht kleine Uhrwerte: nach Reset gibt es keine Drossel - auch dann
// nicht, wenn die Uhr selbst noch unter HIT_CACHE_THROTTLE_MS steht. Und
// eine offene Anforderung vor dem Reset darf danach nichts bestaetigen.
var
  R : THitCacheRepair;
begin
  R.Reset;
  ConfirmView(R, ViewA(R, 1), 100);
  R.NoteInvalidateAll(150);
  Assert.IsTrue(R.HasPendingRequest);
  R.Reset;
  Assert.IsFalse(R.HasPendingRequest, 'Reset vergisst die offene Anforderung');
  Assert.IsTrue(R.ShouldRepair(ViewA(R, 1), 151),
    'Reset vergisst Bestaetigung und Drossel - auch bei kleiner Uhr');
end;

procedure TTestHitCacheRepair.TimeBase_Beyond32Bit_IsNotTruncated;
// GetTickCount64 ueberschreitet nach 49,7 Tagen 2^32 ms. Eine auf 32 Bit
// gekuerzte Ablage machte aus der Anforderung bei 2^32 + 100 eine bei 100 -
// die Drossel waere dann sofort abgelaufen.
const
  TWO_POW_32 : UInt64 = UInt64($100000000);
var
  R : THitCacheRepair;
begin
  R.Reset;
  Assert.IsTrue(R.ShouldRepair(ViewA(R, 1), TWO_POW_32 - 100),
    'Anforderung kurz vor 2^32');
  Assert.IsFalse(R.ShouldRepair(ViewA(R, 1), TWO_POW_32 + 300),
    'Ueber 2^32 hinweg: 400 ms vergangen');
  Assert.IsTrue(R.ShouldRepair(ViewA(R, 1), TWO_POW_32 + 401),
    'Ueber 2^32 hinweg: 501 ms vergangen');
  Assert.IsFalse(R.ShouldRepair(ViewA(R, 1), TWO_POW_32 + 601),
    'Anforderung jenseits von 2^32: erst 200 ms vergangen');
  Assert.IsTrue(R.ShouldRepair(ViewA(R, 1), TWO_POW_32 + 902),
    'Anforderung jenseits von 2^32: 501 ms vergangen');
  // Der Abstand selbst wird nicht modulo 2^32 gerechnet (alte DWORD-
  // Semantik): 2^32 + 100 ms sind keine 100 ms.
  Assert.IsTrue(R.ShouldRepair(ViewA(R, 1), 2 * TWO_POW_32 + 1002),
    'Mehr als 2^32 ms seit der letzten Pruefung: nicht modulo 2^32');
end;

procedure TTestHitCacheRepair.ClockBeforeLastCheck_FailsOpenWithoutOverflow;
// Laeuft eine fremde Uhr rueckwaerts, gilt die Drossel als abgelaufen -
// und die Subtraktion darf unter $Q+ keine Ausnahme werfen.
var
  R : THitCacheRepair;
begin
  R.Reset;
  Assert.IsTrue(R.ShouldRepair(ViewA(R, 1), START_MS));
  Assert.IsTrue(R.ShouldRepair(ViewA(R, 1), START_MS - 1000),
    'Unbestaetigt und Uhr zurueck: erneut erlaubt');
end;

procedure TTestHitCacheRepair.UnreachableEditor_ThrottlesWithoutRequest;
// Fehltreffer in einem Editor, den InvalidateTopEditor nicht erreicht
// (geteilte Ansicht, zweites Editorfenster): keine Anforderung - der
// Repaint malte nur den anderen Editor und startete dessen Caret neu. Die
// Drossel greift trotzdem, sonst fragte der Highlighter die ToolsAPI bei
// jeder Mausnachricht.
var
  R : THitCacheRepair;
begin
  R.Reset;
  R.NoteRepairUnreachable(START_MS);
  Assert.IsFalse(R.HasPendingRequest, 'Nichts angefordert');
  Assert.IsTrue(R.IsThrottled(START_MS + HIT_CACHE_THROTTLE_MS),
    'Die Pruefung drosselt die naechste');
  R.NotePaintCompleted(ViewA(R, 1));
  Assert.IsTrue(R.ShouldRepair(ViewA(R, 1), START_MS
    + HIT_CACHE_THROTTLE_MS + 1), 'Der Paint danach hat nichts bestaetigt');
  R.NoteRepairUnreachable(START_MS + 2000);
  Assert.IsTrue(R.HasPendingRequest,
    'Eine offene Anforderung bleibt stehen');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestHitCacheRepair);

end.
