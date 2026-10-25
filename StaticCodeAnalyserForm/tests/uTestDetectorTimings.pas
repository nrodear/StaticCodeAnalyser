unit uTestDetectorTimings;

// Tests fuer die Summierung und Ausgabe von --time-detectors (Charge P,
// 2026-10-25).
//
// WARUM: bis 2026-10-25 summierte das AOnTime-Lambda in ParseLeaks je
// Detektor-Aufruf Watch.ElapsedMilliseconds - ganze ms, ABGESCHNITTEN. Ein
// Aufruf unter 1 ms zaehlte 0; auf grossen Korpora zeigte die Tabelle nur
// rund die Haelfte der echten Detektorzeit, kleine Detektoren sprangen
// zwischen 0 und N ms. Jetzt summiert uStaticAnalyzer2 Ticks
// (AccumulateDetectorTicks) und rechnet erst bei der Ausgabe um
// (DetectorTicksToMs, uConsoleRunner.BuildDetectorTimingsLines).
//
// Die Tests rechnen mit fester Frequenz (10 MHz, der uebliche
// QueryPerformanceFrequency-Wert unter Windows 10/11) - unabhaengig von
// der Maschine.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDetectorTimings = class
  public
    // ---- AccumulateDetectorTicks ----
    [Test] procedure Accumulate_ErsterAufruf_LegtEintragAn;
    [Test] procedure Accumulate_ZweiterAufruf_SummiertTicksUndZaehlt;
    [Test] procedure Accumulate_SubMillisekundenAufrufe_GehenNichtVerloren;
    [Test] procedure Accumulate_GetrennteDetektoren_BleibenGetrennt;
    [Test] procedure Accumulate_OhneAkkumulator_TutNichts;
    // ---- Umrechnung ----
    [Test] procedure TicksToMs_LiefertNachkommastellen;
    [Test] procedure TicksToMs_FrequenzNull_LiefertNull;
    [Test] procedure TicksToWholeMs_SchneidetAb_LangsamSchwelleWieBisher;
    [Test] procedure TicksToWholeMs_FrequenzNull_LiefertNull;
    // ---- BuildDetectorTimingsLines (Format 2) ----
    [Test] procedure Lines_OhneDaten_LeereListe;
    [Test] procedure Lines_KopfzeileWieFormat1;
    [Test] procedure Lines_ZeileMitPunktUndNachkommastellen;
    [Test] procedure Lines_SortiertNachTicks_GleichstandNachName;
    [Test] procedure Lines_TotalUndKennzeile;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uStaticAnalyzer2, uConsoleRunner;

const
  FREQ_10MHZ = 10000000;

type
  TTimings = TDictionary<string, TPair<Int64, Integer>>;

function NahGleich(A, B: Double): Boolean;
begin
  Result := Abs(A - B) < 1E-9;
end;

// Zeilen der Tabelle, die mit '| <Rang> |' beginnen (ohne Kopf/Trenner).
function DatenZeilen(ALines: TStringList): TArray<string>;
var
  i: Integer;
  L: TList<string>;
begin
  L := TList<string>.Create;
  try
    for i := 0 to ALines.Count - 1 do
      if ALines[i].StartsWith('| ') and not ALines[i].StartsWith('| Rank') then
        L.Add(ALines[i]);
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

{ TTestDetectorTimings }

procedure TTestDetectorTimings.Accumulate_ErsterAufruf_LegtEintragAn;
var
  T: TTimings;
begin
  T := TTimings.Create;
  try
    AccumulateDetectorTicks(T, 'LeakDetector', 1234);
    Assert.AreEqual<Integer>(1, T.Count, 'ein Eintrag');
    Assert.AreEqual<Int64>(1234, T['LeakDetector'].Key, 'Ticks');
    Assert.AreEqual<Integer>(1, T['LeakDetector'].Value, 'Aufrufe');
  finally
    T.Free;
  end;
end;

procedure TTestDetectorTimings.Accumulate_ZweiterAufruf_SummiertTicksUndZaehlt;
var
  T: TTimings;
begin
  T := TTimings.Create;
  try
    AccumulateDetectorTicks(T, 'LeakDetector', 1234);
    AccumulateDetectorTicks(T, 'LeakDetector', 766);
    Assert.AreEqual<Integer>(1, T.Count, 'derselbe Eintrag');
    Assert.AreEqual<Int64>(2000, T['LeakDetector'].Key, 'Ticks summiert');
    Assert.AreEqual<Integer>(2, T['LeakDetector'].Value, 'Aufrufe gezaehlt');
  finally
    T.Free;
  end;
end;

procedure TTestDetectorTimings.Accumulate_SubMillisekundenAufrufe_GehenNichtVerloren;
// Der eigentliche Fehler: 1000 Aufrufe zu je 0,4 ms. Die alte Summierung
// (ganze ms je Aufruf, abgeschnitten) ergab 0 ms - jetzt 400 ms.
var
  T: TTimings;
  i: Integer;
begin
  T := TTimings.Create;
  try
    for i := 1 to 1000 do
      AccumulateDetectorTicks(T, 'TinyDetector', 4000);   // 0,4 ms @ 10 MHz
    Assert.AreEqual<Integer>(1000, T['TinyDetector'].Value, 'Aufrufe');
    Assert.IsTrue(NahGleich(400.0,
      DetectorTicksToMs(T['TinyDetector'].Key, FREQ_10MHZ)),
      'Sub-ms-Aufrufe summieren sich zu 400 ms statt 0');
  finally
    T.Free;
  end;
end;

procedure TTestDetectorTimings.Accumulate_GetrennteDetektoren_BleibenGetrennt;
var
  T: TTimings;
begin
  T := TTimings.Create;
  try
    AccumulateDetectorTicks(T, 'A', 10);
    AccumulateDetectorTicks(T, 'B', 20);
    AccumulateDetectorTicks(T, 'A', 5);
    Assert.AreEqual<Integer>(2, T.Count, 'zwei Eintraege');
    Assert.AreEqual<Int64>(15, T['A'].Key, 'A');
    Assert.AreEqual<Int64>(20, T['B'].Key, 'B');
    Assert.AreEqual<Integer>(1, T['B'].Value, 'B einmal');
  finally
    T.Free;
  end;
end;

procedure TTestDetectorTimings.Accumulate_OhneAkkumulator_TutNichts;
begin
  // gDetectorTimings = nil ist der Normalfall (kein --time-detectors).
  Assert.WillNotRaise(
    procedure
    begin
      AccumulateDetectorTicks(nil, 'LeakDetector', 1234);
    end, nil, 'nil-Akkumulator ist ein No-Op');
end;

procedure TTestDetectorTimings.TicksToMs_LiefertNachkommastellen;
begin
  Assert.IsTrue(NahGleich(1.5, DetectorTicksToMs(15000, FREQ_10MHZ)),
    '15000 Ticks @ 10 MHz = 1,5 ms');
  Assert.IsTrue(NahGleich(1.5, DetectorTicksToMs(4500, 3000000)),
    '4500 Ticks @ 3 MHz = 1,5 ms');
  Assert.IsTrue(NahGleich(0.0001, DetectorTicksToMs(1, FREQ_10MHZ)),
    'ein Tick @ 10 MHz = 0,1 us');
end;

procedure TTestDetectorTimings.TicksToMs_FrequenzNull_LiefertNull;
begin
  Assert.IsTrue(NahGleich(0, DetectorTicksToMs(15000, 0)), 'Frequenz 0');
  Assert.IsTrue(NahGleich(0, DetectorTicksToMs(15000, -1)), 'Frequenz negativ');
end;

procedure TTestDetectorTimings.TicksToWholeMs_SchneidetAb_LangsamSchwelleWieBisher;
// Die "langsam!"-Logzeile behaelt Schwelle (> 500) und Format ('%d ms'):
// 500,9999 ms bleibt 500 (nicht langsam, wie bei ElapsedMilliseconds).
begin
  Assert.AreEqual<Int64>(500, DetectorTicksToWholeMs(5009999, FREQ_10MHZ),
    '500,9999 ms -> 500');
  Assert.AreEqual<Int64>(501, DetectorTicksToWholeMs(5010000, FREQ_10MHZ),
    '501,0 ms -> 501');
  Assert.AreEqual<Int64>(0, DetectorTicksToWholeMs(9999, FREQ_10MHZ),
    '0,9999 ms -> 0');
end;

procedure TTestDetectorTimings.TicksToWholeMs_FrequenzNull_LiefertNull;
begin
  Assert.AreEqual<Int64>(0, DetectorTicksToWholeMs(5010000, 0), 'Frequenz 0');
end;

procedure TTestDetectorTimings.Lines_OhneDaten_LeereListe;
var
  T: TTimings;
  L: TStringList;
begin
  L := BuildDetectorTimingsLines(nil, FREQ_10MHZ);
  try
    Assert.AreEqual<Integer>(0, L.Count, 'nil -> leer');
  finally
    L.Free;
  end;
  T := TTimings.Create;
  try
    L := BuildDetectorTimingsLines(T, FREQ_10MHZ);
    try
      Assert.AreEqual<Integer>(0, L.Count, 'leer -> leer');
    finally
      L.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTestDetectorTimings.Lines_KopfzeileWieFormat1;
// Leser suchen die Tabelle ueber Ueberschrift und Spaltenkopf - beide
// bleiben wortgleich mit Format 1.
var
  T: TTimings;
  L: TStringList;
begin
  T := TTimings.Create;
  try
    AccumulateDetectorTicks(T, 'A', 15000);
    L := BuildDetectorTimingsLines(T, FREQ_10MHZ);
    try
      Assert.IsTrue(L.IndexOf('## Per-Detector Timing') >= 0, 'Ueberschrift');
      Assert.IsTrue(L.IndexOf('| Rank | Detector | Total ms | Calls | Avg ms | % Scan |') >= 0,
        'Spaltenkopf');
    finally
      L.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTestDetectorTimings.Lines_ZeileMitPunktUndNachkommastellen;
// Punkt unabhaengig vom Gebietsschema (frueher Landes-Komma bei Avg/%).
var
  T: TTimings;
  L: TStringList;
  Rows: TArray<string>;
begin
  T := TTimings.Create;
  try
    AccumulateDetectorTicks(T, 'A', 5000);
    AccumulateDetectorTicks(T, 'A', 5000);
    AccumulateDetectorTicks(T, 'A', 5000);   // 3 x 0,5 ms
    L := BuildDetectorTimingsLines(T, FREQ_10MHZ);
    try
      Rows := DatenZeilen(L);
      Assert.AreEqual<Integer>(1, Length(Rows), 'eine Datenzeile');
      Assert.AreEqual('| 1 | A | 1.500 | 3 | 0.5000 | 100.0% |', Rows[0]);
    finally
      L.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTestDetectorTimings.Lines_SortiertNachTicks_GleichstandNachName;
var
  T: TTimings;
  L: TStringList;
  Rows: TArray<string>;
begin
  T := TTimings.Create;
  try
    AccumulateDetectorTicks(T, 'B', 10000);
    AccumulateDetectorTicks(T, 'A', 10000);
    AccumulateDetectorTicks(T, 'C', 30000);
    L := BuildDetectorTimingsLines(T, FREQ_10MHZ);
    try
      Rows := DatenZeilen(L);
      Assert.AreEqual<Integer>(3, Length(Rows), 'drei Datenzeilen');
      Assert.IsTrue(Rows[0].StartsWith('| 1 | C | 3.000 |'), Rows[0]);
      Assert.IsTrue(Rows[1].StartsWith('| 2 | A | 1.000 |'), Rows[1]);
      Assert.IsTrue(Rows[2].StartsWith('| 3 | B | 1.000 |'), Rows[2]);
    finally
      L.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTestDetectorTimings.Lines_TotalUndKennzeile;
var
  T: TTimings;
  L: TStringList;
begin
  T := TTimings.Create;
  try
    AccumulateDetectorTicks(T, 'A', 12345);
    AccumulateDetectorTicks(T, 'B', 7655);
    L := BuildDetectorTimingsLines(T, FREQ_10MHZ);
    try
      Assert.IsTrue(L.IndexOf('Total: 2.000 ms over 2 detectors') >= 0,
        'Total aus der Tick-Summe');
      Assert.IsTrue(L[L.Count - 1].StartsWith('Timing format: 2 '),
        'Kennzeile als letzte Zeile');
    finally
      L.Free;
    end;
  finally
    T.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDetectorTimings);

end.
