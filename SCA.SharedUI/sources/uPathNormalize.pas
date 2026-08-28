unit uPathNormalize;

// Pfad-Normalisierung fuer CACHE- UND VERGLEICHSSCHLUESSEL der UI.
// Loest die ehemaligen 5 (NormalizePath/NormalizeForCache)-
// Duplikate in Frame + Highlighter + Watch-Mode + Properties-Wrapper auf.
//
// ES GIBT DREI NORMALISIERUNGEN IM PROJEKT, und sie tun ABSICHTLICH
// Verschiedenes - zwei davon in entgegengesetzte Richtungen. Wer eine
// davon aendert, aendert NICHT die anderen:
//   * hier (UI-Schluessel)          : "/" -> "\", lowercase, trim
//   * uPathOverrides.NormalizePath  : "\" -> "/", lowercase - fuer
//     Glob-Muster, die beide OS-Konventionen matchen sollen
//   * uSymbolReferenceIndex.NormalizeUnitPath : ExpandFileName +
//     lowercase - absoluter kanonischer Pfad fuer den Unit-Vergleich
// Die frueher hier stehende Zusage "Single Source of Truth fuer
// Pfad-Normalisierung" war deshalb falsch: sie gilt fuer den
// SCHLUESSEL-Zweck, nicht fuer Pfade ueberhaupt.
//
// Konvention: lowercase + Backslash + Trim. Begruendung:
//   * lowercase   - Windows-FS ist case-insensitive; ein Lookup-Key der
//                   case bewahrt produziert sporadisch Cache-Miss.
//   * Backslash   - VCL / IDE-OTAPI nutzen ueberwiegend Backslashes;
//                   einzelne Quellen liefern '/' (z.B. INI manuell editiert,
//                   git-bash-Paths) und werden normalisiert.
//   * Trim        - defensive gegen leading/trailing whitespace aus INI-
//                   Werten und manuellen Edits.
//
// Diese Normalisierung ist NICHT geeignet fuer Glob-Match (siehe
// uPathOverrides) - dort werden forward-slashes erwartet.

interface

function NormalizePathForKey(const APath: string): string;

implementation

uses
  System.SysUtils;

function NormalizePathForKey(const APath: string): string;
begin
  Result := LowerCase(StringReplace(APath, '/', '\', [rfReplaceAll])).Trim;
end;

end.
