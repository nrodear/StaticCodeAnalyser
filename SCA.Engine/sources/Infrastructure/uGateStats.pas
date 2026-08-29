unit uGateStats;

// Trefferzaehlung fuer FP-Gates.
//
// WOZU: der Core traegt rund 2.900 Gates ("if <Praedikat> then Continue"),
// jedes davon einzeln begruendet und ueber Monate gewachsen. Was fehlte, war
// die Gegenrichtung: es gab KEINEN Weg festzustellen, welche davon ueberhaupt
// noch etwas tun. Ein Gate, das ein spaeter hinzugekommenes bereits abdeckt,
// kostet CPU im Hot-Path und - schlimmer - Verstaendnis bei jeder Aenderung,
// weil jeder Leser annehmen muss, dass es noch traegt. --time-detectors misst
// je DETEKTOR, nie je Bedingung.
//
// Mit dieser Zaehlung wird ein Gate mit null Treffern ueber den
// Referenzkorpus ein belegbarer Loeschkandidat statt einer Vermutung.
//
// LIFECYCLE wie gDetectorTimings, und aus demselben Grund: der Konsument
// (CLI/IDE) liegt AUSSERHALB des SCA.Engine-Package, ein exportierter
// threadvar traegt dort nicht (W1032, Caller-Thread-TLS-Slot != Engine-Slot).
// Caller erzeugt, die Engine fuellt, der Caller liest und gibt frei.
//
// KOSTEN im Normalbetrieb: ein Nil-Test je Gate-Aufruf. GateHit ist inline,
// der Zweig ist perfekt vorhersagbar (immer nil), und die Zaehlung selbst
// laeuft nur im Diagnosemodus.
//
// NICHT THREAD-SICHER, mit Absicht: das Dictionary wird ungeschuetzt
// beschrieben. Wer zaehlen will, faehrt seriell - genau wie bei den
// Detektor-Timings. Das Gate dafuer sitzt im Analyzer, nicht hier.

interface

uses
  System.Generics.Collections;

var
  // nil = Zaehlung AUS (Normalbetrieb). Nicht selbst erzeugen - der Aufrufer
  // besitzt das Dictionary.
  gGateHits : TDictionary<string, Integer>;

// Einen Gate-Treffer vermerken. AName ist eine KONSTANTE der Form
// '<Regel>.<Praedikat>', z.B. 'SCA001.IsPassedToOwner' - konstante Strings
// kosten keine Allokation.
procedure GateHit(const AName: string); inline;

// Durchreiche-Form fuer die Gate-Kette: liefert AHit unveraendert zurueck
// und zaehlt dabei. Aus
//   if IsFoo(x) then Continue;
// wird
//   if Gate(GS_FOO, IsFoo(x)) then Continue;
// - eine Zeile bleibt eine Zeile, und die Kette liest sich weiter als
// Kette. Der Boolean-Parameter ist hier kein Schalter, sondern der
// Messwert selbst.
// noinspection BooleanParam
function Gate(const AName: string; AHit: Boolean): Boolean; inline;

// Zeilenweiser Bericht, absteigend nach Treffern. Leer, wenn die Zaehlung
// aus war - der Aufrufer soll das UNTERSCHEIDEN koennen und es sagen, statt
// wortlos nichts auszugeben.
function GateStatsReport: string;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Defaults;

procedure GateHit(const AName: string);
var
  N : Integer;
begin
  if gGateHits = nil then Exit;
  if gGateHits.TryGetValue(AName, N) then
    gGateHits[AName] := N + 1
  else
    gGateHits.Add(AName, 1);
end;

function Gate(const AName: string; AHit: Boolean): Boolean;
begin
  Result := AHit;
  if Result then GateHit(AName);
end;

function GateStatsReport: string;
var
  Paare : TArray<TPair<string, Integer>>;
  SB    : TStringBuilder;
  P     : TPair<string, Integer>;
begin
  Result := '';
  if gGateHits = nil then Exit;
  Paare := gGateHits.ToArray;
  TArray.Sort<TPair<string, Integer>>(Paare,
    TComparer<TPair<string, Integer>>.Construct(
      function(const A, B: TPair<string, Integer>): Integer
      begin
        // Absteigend nach Treffern, bei Gleichstand nach Namen - damit der
        // Bericht zwischen zwei Laeufen vergleichbar bleibt.
        Result := B.Value - A.Value;
        if Result = 0 then Result := CompareText(A.Key, B.Key);
      end));
  SB := TStringBuilder.Create;
  try
    for P in Paare do
      SB.Append(Format('%8d  %s', [P.Value, P.Key])).AppendLine;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

initialization
  gGateHits := nil;

end.
