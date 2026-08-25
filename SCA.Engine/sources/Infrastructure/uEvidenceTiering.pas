unit uEvidenceTiering;

// Evidenz-Politik: Severity-Deckel nach Konfidenz (Post-Filter-Schritt).
//
// VERTRAG "Error = bewiesen": Der Error-Tier zeigt nur Befunde, deren
// Detektor-Konfidenz fcHigh ist. Ein Befund, dessen Gate-Lage nur
// fcMedium hergibt, erscheint hoechstens als Warning, fcLow hoechstens
// als Hint - unabhaengig davon, was der Katalog als DefaultSeverity
// fuehrt. Vorbild ist der Industriestandard "kuratierter Default-Satz"
// (CodeQL laedt default nur precision high/very-high, Clang haelt
// rauschende Checker in alpha, Tricorder nimmt Checks erst unter 10 %
// effective-FP auf); Herleitung, Zahlen und Gegenpruefung:
// Konzept_FpUnter5Prozent_2026-08-26.md (lokal). Gemessene Wirkung auf
// dem Referenzkorpus (Audit 2026-08-15): Error-Tier-FP-Quote 32,3 %
// -> ~4 %, weil die grossen fcMedium-Regeln (SCA003/121/109 + SCA001
// nach Demote) den Error-Tier verlassen.
//
// Einordnung in die Post-Filter-Pipeline (vgl. uConfidenceFilter-Kopf):
//   1. Detektoren erzeugen Befunde
//   2. uSuppression.ApplyToFindings        (// noinspection)
//   3. uEvidenceTiering.ApplyToFindings    ([Rules] EvidenceTiering)
//   4. uPathOverrides.ApplyToFindings      (analyser.ini [PathOverrides])
//   5. uConfidenceFilter.ApplyToFindings   (FindingMinConfidence)
//
// BEWUSST VOR den PathOverrides: poaSeverityError ist eine EXPLIZITE
// Nutzer-Hochstufung je Pfad - sie behaelt das letzte Wort gegen die
// Politik. Liefe der Deckel danach, naehme er die Nutzer-Entscheidung
// still zurueck, und der Fund fiele obendrein als "downgraded" aus dem
// Sonar-Export (Gegenpruefung K2, 2026-08-26).
//
// Der Deckel ENTFERNT nie einen Befund (das bleibt Suppression/
// PathOverride-Drop/ConfidenceFilter) und HEBT nie eine Severity an -
// reine Deckelung. fkFileReadError ist ausgenommen (Diagnose-Befund,
// dieselbe Ausnahme wie in uConfidenceFilter/uPathOverrides/uBaseline).
//
// NEBENWIRKUNGEN, dokumentiert statt versteckt:
//   * --fail-on error schlaegt fuer gedeckelte Befunde nicht mehr an -
//     das ist der ZWECK der Politik ("Error = bewiesen"); Opt-out fuer
//     Bestandsnutzer: [Rules] EvidenceTiering=0 in analyser.ini.
//   * Der Sonar-Export laesst zur Laufzeit herabgestufte Befunde
//     by-default weg (uExportSonarGeneric.IsDowngraded) - gedeckelte
//     zaehlen dazu; --sonar-keep-downgraded nimmt sie wieder auf.
//   * Der Baseline-Fingerprint enthaelt weder Severity noch Konfidenz
//     (uBaseline.Fingerprint, uFindingFingerprint.ContextHash) -
//     bestehende Baselines und Suppressions bleiben gueltig.

interface

uses
  System.Generics.Collections,
  uSCAConsts, uMethodd12;

type
  TEvidenceTiering = class
  public
    // Hoechste zulaessige Severity fuer eine Konfidenz-Stufe:
    //   fcHigh -> lsError, fcMedium -> lsWarning, fcLow -> lsHint.
    class function MaxSeverityFor(C: TFindingConfidence): TLeakSeverity; static;
    // Deckelt (in-place) die Severity jedes Befundes auf MaxSeverityFor
    // seiner Konfidenz. Entfernt nichts, hebt nichts an. fkFileReadError
    // bleibt unangetastet. Liefert die Anzahl der gedeckelten Befunde.
    class function ApplyToFindings(
      Findings: TObjectList<TLeakFinding>): Integer; static;
  end;

implementation

class function TEvidenceTiering.MaxSeverityFor(
  C: TFindingConfidence): TLeakSeverity;
begin
  case C of
    fcHigh:   Result := lsError;
    fcMedium: Result := lsWarning;
  else
    Result := lsHint; // fcLow
  end;
end;

class function TEvidenceTiering.ApplyToFindings(
  Findings: TObjectList<TLeakFinding>): Integer;
var
  F   : TLeakFinding;
  Cap : TLeakSeverity;
begin
  Result := 0;
  if (Findings = nil) or (Findings.Count = 0) then Exit;
  for F in Findings do
  begin
    if F.Kind = fkFileReadError then Continue; // Diagnose nie anfassen
    Cap := MaxSeverityFor(F.Confidence);
    // Severity-Ordering: lsError=0 < lsWarning=1 < lsHint=2 - "strenger
    // als der Deckel" heisst KLEINERE Ordinalzahl (vgl. den Ordering-
    // Kommentar an DetectorMinSeverity in uSCAConsts).
    if Ord(F.Severity) < Ord(Cap) then
    begin
      F.Severity := Cap;
      Inc(Result);
    end;
  end;
end;

end.
