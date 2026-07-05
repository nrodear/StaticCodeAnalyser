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

// noinspection-file NilComparison, TooLongLine, UnsortedUses, UnusedPublicMember
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

class function TConfidenceFilter.ApplyToFindings(
  Findings: TObjectList<TLeakFinding>;
  MinConfidence: TFindingConfidence): Integer;
var
  r, w    : Integer;
  F       : TLeakFinding;
  OldOwns : Boolean;
begin
  Result := 0;
  if (Findings = nil) or (Findings.Count = 0) then Exit;
  if MinConfidence = fcLow then Exit; // kein Filter -> Schleife sparen

  // Perf (2026-07-05): P5-postfilter-compact - Single-Pass-Kompaktierung
  // statt Delete(i)-Schleife. Delete memmoved bei TObjectList jeweils den
  // Tail; bei grossen Listen (Real-World-Scan ~700k Findings) wird das
  // quadratisch. Stattdessen: Schreibindex w, behaltene Findings nach
  // vorne kopieren, gedroppte manuell freigeben, Count trimmen.
  // OwnsObjects muss dabei temporaer aus sein, sonst wuerde
  // Items[w] := Items[r] das ueberschriebene Objekt freigeben (Notify).
  // Reihenfolge der verbleibenden Findings bleibt exakt erhalten.
  w := 0;
  OldOwns := Findings.OwnsObjects;
  Findings.OwnsObjects := False;
  try
    for r := 0 to Findings.Count - 1 do
    begin
      F := Findings[r];
      if (F.Kind <> fkFileReadError) // Diagnose nie filtern
         and (Ord(F.Confidence) < Ord(MinConfidence)) then
      begin
        if OldOwns then F.Free; // wie Delete bei owning-Liste
        Inc(Result);
      end
      else
      begin
        if w <> r then Findings[w] := F;
        Inc(w);
      end;
    end;
    // Tail abschneiden - enthaelt nur noch Duplikat-Referenzen der nach
    // vorne kopierten Findings; OwnsObjects=False -> kein Free beim Trim.
    Findings.Count := w;
  finally
    Findings.OwnsObjects := OldOwns;
  end;
end;

end.
