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
    // seiner Konfidenz; hebt nie an. fkFileReadError bleibt unangetastet.
    //
    // AMinSeverity (Gegenpruefung 2026-08-26, MAJOR): der per-Fund-
    // Severity-Filter laeuft im Detector-Loop VOR diesem Deckel - ein
    // dort als Error durchgelassener fcMedium-Fund wuerde nach der
    // Deckelung als Warning in einem "error-only"-Report stehen
    // (MinSeverity=error + SCA001 = ~700 Vertragsbruch-Faelle am
    // Korpus). Deshalb: reisst die GEDECKELTE Severity die Schwelle,
    // wird der Befund ENTFERNT - das ist die nachgezogene Konsequenz
    // desselben Filters, kein neuer Vertrag. Beim Auslieferungs-Default
    // lsHint (Ord 2 = nichts ist schwaecher) entfernt der Schritt nie
    // etwas; die Korpus-Beweise (byte-identisch bei Politik=aus, -701
    // bei an, beide mit --min-severity hint) bleiben unberuehrt.
    // Liefert die Anzahl der gedeckelten Befunde.
    class function ApplyToFindings(Findings: TObjectList<TLeakFinding>;
      AMinSeverity: TLeakSeverity = lsHint): Integer; static;
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
  Findings: TObjectList<TLeakFinding>;
  AMinSeverity: TLeakSeverity): Integer;
var
  F       : TLeakFinding;
  Cap     : TLeakSeverity;
  r, w    : Integer;
  OldOwns : Boolean;
begin
  Result := 0;
  if (Findings = nil) or (Findings.Count = 0) then Exit;
  // Single-Pass-Kompaktierung wie uConfidenceFilter (P5): Delete(i) waere
  // auf grossen Listen quadratisch; beim Default AMinSeverity=lsHint wird
  // ohnehin nie entfernt und w laeuft synchron mit r.
  w := 0;
  OldOwns := Findings.OwnsObjects;
  Findings.OwnsObjects := False;
  try
    for r := 0 to Findings.Count - 1 do
    begin
      F := Findings[r];
      if F.Kind <> fkFileReadError then // Diagnose nie anfassen/entfernen
      begin
        Cap := MaxSeverityFor(F.Confidence);
        // Severity-Ordering: lsError=0 < lsWarning=1 < lsHint=2 -
        // "strenger als der Deckel" heisst KLEINERE Ordinalzahl.
        if Ord(F.Severity) < Ord(Cap) then
        begin
          F.Severity := Cap;
          Inc(Result);
        end;
        // Nachgezogener MinSeverity-Filter (s. Interface-Kommentar).
        if Ord(F.Severity) > Ord(AMinSeverity) then
        begin
          if OldOwns then F.Free;
          Continue;
        end;
      end;
      if w <> r then Findings[w] := F;
      Inc(w);
    end;
    Findings.Count := w;
  finally
    Findings.OwnsObjects := OldOwns;
  end;
end;

end.
