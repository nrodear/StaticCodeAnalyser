unit uAnalyserTypes;

// Gemeinsame Typen, die von Theme-Modul, UI und Detector-Code verwendet
// werden. Dient als Boundary zwischen den lokalisierten Anzeigetexten
// (z. B. 'Fehler', 'Warnung') und der internen Logik.
//
// Strings werden NUR an der UI-Grenze in Enums uebersetzt - alle weitere
// Verarbeitung (Filter, Faerbung, Sortierung) lauft ueber das Enum.
// Damit ist Localization moeglich und Refactoring sicher.

interface

type
  TFindingSeverity = (
    fsUnknown,    // unbekannt / nicht klassifiziert
    fsError,      // 'Fehler'      - Blocker / Bugs
    fsWarning,    // 'Warnung'     - Code Smell / Risiko
    fsHint,       // 'Hinweis'     - Info / Style
    fsFileError   // 'Lesefehler'  - I/O / Parser konnte nicht lesen
  );

// Konvertiert die deutsche Anzeige-Severity (wie sie aus TLeakFinding.
// SeverityText kommt) ins Enum. Unbekannte Werte -> fsUnknown.
function SeverityFromText(const S: string): TFindingSeverity;

// Rueckweg fuer UI-Filter und Default-Anzeige.
function SeverityToText(S: TFindingSeverity): string;

implementation

uses
  System.SysUtils;

function SeverityFromText(const S: string): TFindingSeverity;
begin
  if      SameText(S, 'Fehler')     then Result := fsError
  else if SameText(S, 'Warnung')    then Result := fsWarning
  else if SameText(S, 'Hinweis')    then Result := fsHint
  else if SameText(S, 'Lesefehler') then Result := fsFileError
  else                                   Result := fsUnknown;
end;

function SeverityToText(S: TFindingSeverity): string;
begin
  case S of
    fsError:     Result := 'Fehler';
    fsWarning:   Result := 'Warnung';
    fsHint:      Result := 'Hinweis';
    fsFileError: Result := 'Lesefehler';
  else
    Result := '';
  end;
end;

end.
