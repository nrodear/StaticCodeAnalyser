unit uTestRegExCache;

// Randfaelle des Regex-Cache-Umbaus (Charge R2 2026-10-26): statische
// TRegEx-Klassenaufrufe mit konstantem Muster und je-Datei-TRegEx.Create
// in Detektoren beziehen ihre Instanz seitdem aus TRegExMatches.CachedEx.
// Der Umbau ist nur dann ein reiner Tempo-Umbau, wenn
//  * die Optionen Teil des Schluessels sind und der Zwei-Argument-
//    Klassenaufruf ([roNotEmpty], Default von TRegEx.Create(Pattern))
//    exakt nachgebildet wird,
//  * eine wiederverwendete Instanz dasselbe liefert wie eine frische
//    (Subject/Startposition je Aufruf neu, Gruppen beim Match kopiert),
//  * NextMatch auf der geteilten Instanz dieselbe Kette liefert,
//  * parallele Worker sich nicht in die Quere kommen (Thread-ID im
//    Schluessel) und ein Leeren des Caches gehaltene Instanzen nicht
//    entwertet,
//  * die Kapazitaet fuer alle Worker des Parallelmodus reicht.
// Dazu zwei Detektor-Proben fuer die beiden Stellen mit Zustand ueber
// mehrere Aufrufe: SCA167 (NextMatch-Kette) und SCA054 GATE E (je Aufruf
// einmal gebaute Muster, Treffer erst in der dritten Namenszeile).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRegExCache = class
  public
    [Test] procedure NotEmptyOption_MatchesTwoArgClassCall;
    [Test] procedure Options_ArePartOfTheKey;
    [Test] procedure Reuse_AfterOtherSubject_SameAsFreshMatch;
    [Test] procedure Reuse_NoMatchAfterMatch_NotStale;
    [Test] procedure NextMatchChain_SameAsClassCall;
    [Test] procedure ParallelWorkers_SamePattern_NoCrossTalk;
    [Test] procedure CacheCleared_HeldInstanceStaysUsable;
    [Test] procedure Capacity_CoversParallelWorkers;
    [Test] procedure InsecureRandom_GlobalAfterQualified_Reported;
    [Test] procedure InsecureRandom_OnlyQualified_NoFinding;
    [Test] procedure UnusedParameter_AddressTakenAfterCalls_NotReported;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.SyncObjs,
  System.Generics.Collections, System.RegularExpressions,
  uSCAConsts, uMethodd12, uRegExMatches,
  uTestFindingHelper;

const
  // Muster mit zwei Gruppen fuer die Wiederverwendungs-Proben.
  ASSIGN_RE = '(\w+)\s*:=\s*(\d+)';
  // Dasselbe Muster wie uInsecureRandom.FindRandomCallInExpr.
  RANDOM_RE = '\b(RandomRange|RandomFrom|Random)\s*\(';

const
  PAR_THREADS = 8;
  PAR_RUNDEN  = 2000;

var
  // Fehlerzaehler der Parallel-Probe. Unit-Variable statt Lokale des
  // Tests: die Worker entstehen in der eigenen Routine MakeParWorker,
  // damit jeder Rumpf SEINE Thread-Nummer faengt (eine im Test gefangene
  // Schleifenvariable teilten sich alle Ruempfe).
  GParFehler : Integer;

// Worker der Parallel-Probe: matcht RUNDEN-mal einen Text mit bekanntem
// Trefferindex und zaehlt Abweichungen.
function MakeParWorker(ANr: Integer): TThread;
begin
  Result := TThread.CreateAnonymousThread(
    procedure
    var
      i, k : Integer;
      M    : TMatch;
    begin
      for i := 1 to PAR_RUNDEN do
      begin
        k := (ANr * 7 + i) mod 50;
        M := TRegExMatches.CachedEx(RANDOM_RE, [roIgnoreCase]).Match(
          StringOfChar(' ', k) + 'Random(' + IntToStr(i) + ')');
        if (not M.Success) or (M.Index <> k + 1) then
          TInterlocked.Increment(GParFehler);
      end;
    end);
  Result.FreeOnTerminate := False;
end;

// Indexkette eines Match/NextMatch-Durchlaufs als Text ('3,17,40').
function Kette(AFirst: TMatch): string;
var
  M : TMatch;
begin
  Result := '';
  M := AFirst;
  while M.Success do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + IntToStr(M.Index) + ':' + M.Groups[1].Value;
    M := M.NextMatch;
  end;
end;

procedure TTestRegExCache.NotEmptyOption_MatchesTwoArgClassCall;
// 'x*' trifft in 'abc' nur leer. Der Zwei-Argument-Klassenaufruf baut
// TRegEx.Create(Pattern) mit [roNotEmpty] und findet daher nichts - der
// Ersatz CachedEx(.., [roNotEmpty]) muss dasselbe sagen.
begin
  Assert.AreEqual<Boolean>(TRegEx.IsMatch('abc', 'x*'),
    TRegExMatches.CachedEx('x*', [roNotEmpty]).IsMatch('abc'),
    'Ersatz muss dem Klassenaufruf gleichen');
  Assert.IsFalse(TRegExMatches.CachedEx('x*', [roNotEmpty]).IsMatch('abc'),
    'roNotEmpty verbietet den Leer-Treffer');
end;

procedure TTestRegExCache.Options_ArePartOfTheKey;
// Dasselbe Muster mit anderen Optionen ist eine anders kompilierte
// Engine. Kaeme die zuerst gebaute Instanz zurueck, kippte das Ergebnis.
begin
  Assert.IsFalse(TRegExMatches.CachedEx('abc', [roNotEmpty]).IsMatch('xABCx'),
    'ohne roIgnoreCase kein Treffer');
  Assert.IsTrue(TRegExMatches.CachedEx('abc', [roIgnoreCase]).IsMatch('xABCx'),
    'mit roIgnoreCase Treffer');
  Assert.IsTrue(TRegExMatches.CachedEx('x*', []).IsMatch('abc'),
    'ohne roNotEmpty zaehlt der Leer-Treffer');
  Assert.IsFalse(TRegExMatches.CachedEx('x*', [roNotEmpty]).IsMatch('abc'),
    'und mit roNotEmpty weiterhin nicht');
end;

procedure TTestRegExCache.Reuse_AfterOtherSubject_SameAsFreshMatch;
// Zweiter Aufruf auf derselben Instanz mit anderem Text: Index, Laenge
// und Gruppen wie ein frischer Klassenaufruf; der erste TMatch behaelt
// seine Werte (Gruppen werden beim Match kopiert).
const
  T1 = '  alpha := 12;';
  T2 = 'b:=3';
var
  M1, M2, F1, F2 : TMatch;
begin
  M1 := TRegExMatches.CachedEx(ASSIGN_RE, [roNotEmpty]).Match(T1);
  M2 := TRegExMatches.CachedEx(ASSIGN_RE, [roNotEmpty]).Match(T2);
  F1 := TRegEx.Match(T1, ASSIGN_RE);
  F2 := TRegEx.Match(T2, ASSIGN_RE);
  Assert.IsTrue(M2.Success);
  Assert.AreEqual<Integer>(F2.Index, M2.Index);
  Assert.AreEqual<Integer>(F2.Length, M2.Length);
  Assert.AreEqual(F2.Groups[1].Value, M2.Groups[1].Value);
  Assert.AreEqual(F2.Groups[2].Value, M2.Groups[2].Value);
  Assert.AreEqual<Integer>(F1.Index, M1.Index, 'erster Treffer unveraendert');
  Assert.AreEqual(F1.Groups[1].Value, M1.Groups[1].Value);
  Assert.AreEqual(F1.Groups[2].Value, M1.Groups[2].Value);
end;

procedure TTestRegExCache.Reuse_NoMatchAfterMatch_NotStale;
// Ein Fehlschlag nach einem Treffer darf keine Reste des Vorlaufs zeigen.
var
  M : TMatch;
begin
  M := TRegExMatches.CachedEx(ASSIGN_RE, [roNotEmpty]).Match('k := 7');
  Assert.IsTrue(M.Success);
  M := TRegExMatches.CachedEx(ASSIGN_RE, [roNotEmpty]).Match('kein Treffer');
  Assert.IsFalse(M.Success);
  Assert.AreEqual(TRegEx.Match('kein Treffer', ASSIGN_RE).Value, M.Value);
end;

procedure TTestRegExCache.NextMatchChain_SameAsClassCall;
// SCA167 laeuft mit NextMatch ueber die geteilte Instanz. Die Kette muss
// der des frischen Klassenaufrufs gleichen - auch wenn die Instanz vorher
// einen anderen Text gesehen hat.
const
  T = 'x := FRng.Random(5) + random(3) * RandomRange(1, 2) + RandomFrom(A)';
var
  Erwartet : string;
begin
  TRegExMatches.CachedEx(RANDOM_RE, [roIgnoreCase]).Match('Random(1)');
  Erwartet := Kette(TRegEx.Match(T, RANDOM_RE, [roIgnoreCase]));
  Assert.AreEqual(Erwartet,
    Kette(TRegExMatches.CachedEx(RANDOM_RE, [roIgnoreCase]).Match(T)));
  Assert.AreEqual<Integer>(4, Length(Erwartet.Split([','])),
    'vier Aufrufe in der Kette');
end;

procedure TTestRegExCache.ParallelWorkers_SamePattern_NoCrossTalk;
// Acht Threads matchen dasselbe Muster auf je eigene Texte. Mit EINER
// geteilten Instanz (ohne Thread-ID im Schluessel) laesen sie fremde
// Subjects/Offsets und lieferten falsche Indizes.
var
  Th : array[0..PAR_THREADS - 1] of TThread;
  t  : Integer;
begin
  GParFehler := 0;
  for t := 0 to PAR_THREADS - 1 do
    Th[t] := nil;
  try
    for t := 0 to PAR_THREADS - 1 do
      Th[t] := MakeParWorker(t);
    for t := 0 to PAR_THREADS - 1 do
      Th[t].Start;
    for t := 0 to PAR_THREADS - 1 do
      Th[t].WaitFor;
  finally
    for t := 0 to PAR_THREADS - 1 do
      Th[t].Free;
  end;
  Assert.AreEqual<Integer>(0, GParFehler, 'kein Worker sieht fremden Zustand');
end;

procedure TTestRegExCache.CacheCleared_HeldInstanceStaysUsable;
// Ueber der Kapazitaet leert CachedEx den ganzen Cache. Eine vorher
// geholte Instanz haelt ihre TPerlRegEx ueber den Notifier selbst und
// muss weiter richtig matchen.
var
  R : TRegEx;
  i : Integer;
  M : TMatch;
begin
  R := TRegExMatches.CachedEx('held(\d)', [roNotEmpty]);
  for i := 0 to TRegExMatches.CacheCapacity + 10 do
    TRegExMatches.CachedEx('fill' + IntToStr(i), [roNotEmpty]);
  M := R.Match('x held7 y');
  Assert.IsTrue(M.Success);
  Assert.AreEqual('7', M.Groups[1].Value);
  Assert.IsTrue(TRegExMatches.CachedEx('held(\d)', [roNotEmpty]).IsMatch('held1'),
    'neu gebaute Instanz nach dem Leeren');
end;

procedure TTestRegExCache.Capacity_CoversParallelWorkers;
// Jeder Worker haelt ~55 konstante Muster; der Parallelmodus startet
// TThread.ProcessorCount Worker. Reichte die Kapazitaet nicht, leerte
// sich der Cache mitten im Scan immer wieder.
begin
  Assert.IsTrue(TRegExMatches.CacheCapacity >= 1280, 'alte Untergrenze');
  Assert.IsTrue(TRegExMatches.CacheCapacity >=
    64 * (TThread.ProcessorCount + 1),
    'Platz fuer 64 Muster je Worker plus Hauptthread');
end;

procedure TTestRegExCache.InsecureRandom_GlobalAfterQualified_Reported;
// Pass 2b: der erste Treffer ist FRng.Random (eigener RNG, uebersprungen),
// erst NextMatch findet das globale Random. Zwei Zuweisungen hintereinander
// - die zweite startet die Kette auf derselben Instanz neu.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  i := FRng.Random(5) + Random(3);'#13#10 +
  '  j := Gen.RandomRange(1, 2) + RandomRange(4, 9);'#13#10 +
  'end;'#13#10 +
  'end.';
var
  F    : TObjectList<TLeakFinding>;
  L    : TLeakFinding;
  Z4   : Integer;
  Z5   : Integer;
  Name5: string;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Z4 := 0;
    Z5 := 0;
    Name5 := '';
    for L in F do
      if L.Kind = fkInsecureRandom then
      begin
        if L.LineNumber = '4' then Inc(Z4);
        if L.LineNumber = '5' then
        begin
          Inc(Z5);
          Name5 := L.MissingVar;
        end;
      end;
    Assert.IsTrue(Z4 >= 1, 'Zeile 4: Random hinter FRng.Random');
    Assert.IsTrue(Z5 >= 1, 'Zeile 5: RandomRange hinter Gen.RandomRange');
    Assert.Contains(Name5, 'RandomRange(...)');
  finally
    F.Free;
  end;
end;

procedure TTestRegExCache.InsecureRandom_OnlyQualified_NoFinding;
// Gegenprobe: nur eigene RNG-Objekte - die Kette endet ohne Treffer.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  i := FRng.Random(5) + Gen.RandomRange(1, 2);'#13#10 +
  'end;'#13#10 +
  'end.';
var
  F : TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInsecureRandom));
  finally
    F.Free;
  end;
end;

procedure TTestRegExCache.UnusedParameter_AddressTakenAfterCalls_NotReported;
// GATE E Form (3) '@Name'. Der Name steht vorher in drei Zeilen ohne
// Treffer (Kopf, zwei Aufrufe) - die je Aufruf einmal gebauten Muster
// laufen also mehrfach, bevor die vierte Zeile trifft.
const SRC =
  'unit t;' + #13#10 +
  'implementation' + #13#10 +
  'procedure DoTheWork(Value: Integer; Unbenutzt: TObject);' + #13#10 +
  'begin' + #13#10 +
  '  WriteLn(Value);' + #13#10 +
  'end;' + #13#10 +
  'procedure Caller;' + #13#10 +
  'var P: Pointer;' + #13#10 +
  'begin' + #13#10 +
  '  DoTheWork(1, nil);' + #13#10 +
  '  DoTheWork(2, nil);' + #13#10 +
  '  P := @DoTheWork;' + #13#10 +
  'end;';
var
  F : TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedParameter),
      'Adresse genommen - die Signatur ist Vertrag');
  finally
    F.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRegExCache);

end.
