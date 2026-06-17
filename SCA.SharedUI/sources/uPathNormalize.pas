unit uPathNormalize;

// Single Source of Truth fuer Pfad-Normalisierung als Cache-/Vergleichs-
// Schluessel. Loest die ehemaligen 5 (NormalizePath/NormalizeForCache)-
// Duplikate in Frame + Highlighter + Watch-Mode + Properties-Wrapper auf.
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
