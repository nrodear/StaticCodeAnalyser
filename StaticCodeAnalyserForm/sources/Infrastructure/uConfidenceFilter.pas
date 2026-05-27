unit uConfidenceFilter;

// Post-Filter ueber die Konfidenz eines Befundes (TLeakFinding.Confidence).
// Verwirft Befunde, deren Confidence niedriger ist als ein Schwellwert -
// damit koennen Detektoren heuristische (FP-anfaellige) Treffer als fcLow
// emittieren, ohne dass diese standardmaessig im Report landen.
//
// Einordnung in die Post-Filter-Pipeline (vgl. uPathOverrides-Kommentar):
//   1. Detektoren erzeugen Befunde (Default-Confidence = fcHigh)
//   2. uSuppression.ApplyToFindings        (// noinspection)
//   3. uPathOverrides.ApplyToFindings      (analyser.ini [PathOverrides])
//   4. uConfidenceFilter.ApplyToFindings   (FindingMinConfidence)
//
// Der Schwellwert kommt global aus uSCAConsts.FindingMinConfidence (Default
// fcMedium -> nur fcLow raus). fkFileReadError ist immer ausgenommen, weil
// es ein Diagnose-Befund ist und nie unterdrueckt werden darf.

interface

uses
  System.Generics.Collections,
  uSCAConsts, uMethodd12;

type
  TConfidenceFilter = class
  public
    // Entfernt (in-place) alle Befunde mit Confidence < MinConfidence.
    // fkFileReadError bleibt immer erhalten. MinConfidence = fcLow ist ein
    // No-op (kein Filter). Liefert die Anzahl der entfernten Befunde.
    class function ApplyToFindings(Findings: TObjectList<TLeakFinding>;
      MinConfidence: TFindingConfidence): Integer; static;
  end;

implementation

class function TConfidenceFilter.ApplyToFindings(
  Findings: TObjectList<TLeakFinding>;
  MinConfidence: TFindingConfidence): Integer;
var
  i : Integer;
begin
  Result := 0;
  if (Findings = nil) or (Findings.Count = 0) then Exit;
  if MinConfidence = fcLow then Exit; // kein Filter -> Schleife sparen

  // Rueckwaerts iterieren - sicher beim Loeschen.
  for i := Findings.Count - 1 downto 0 do
  begin
    if Findings[i].Kind = fkFileReadError then Continue; // Diagnose nie filtern
    if Ord(Findings[i].Confidence) < Ord(MinConfidence) then
    begin
      Findings.Delete(i);
      Inc(Result);
    end;
  end;
end;

end.
