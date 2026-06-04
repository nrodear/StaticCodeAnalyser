unit uAnalyserTypes;

// Gemeinsame Typen, die von Theme-Modul, UI und Detector-Code verwendet
// werden. Dient als Boundary zwischen den lokalisierten Anzeigetexten
// (z.B. 'Fehler', 'Warnung') und der internen Logik.
//
// **WICHTIG**: Strings werden NUR an der UI-Grenze in Enums uebersetzt -
// alle weitere Verarbeitung (Filter, Faerbung, Sortierung) lauft ueber
// das Enum. Damit ist Localization moeglich und Refactoring sicher.
//
// **Bevorzugter Pfad**: `SeverityFromKindLevel(F.Kind, F.Severity)` -
// rein enum-zu-enum, keine String-Roundtrips, keine i18n-Abhaengigkeit.
// **Legacy/Defensiv-Pfad**: `SeverityFromText(SomeString)` - akzeptiert
// sowohl deutsche als auch englische Anzeige-Strings (wird gebraucht
// wo der Cell-Inhalt eines Grids als String zurueckgelesen werden muss).

interface

uses
  uSCAConsts; // TLeakSeverity, TFindingKind

type
  TFindingSeverity = (
    fsUnknown,    // unbekannt / nicht klassifiziert
    fsError,      // 'Fehler' / 'Error'         - Blocker / Bugs
    fsWarning,    // 'Warnung' / 'Warning'      - Code Smell / Risiko
    fsHint,       // 'Hinweis' / 'Hint'         - Info / Style
    fsFileError   // 'Lesefehler' / 'Read Error' - I/O / Parser-Fehler
  );

// Bevorzugter Pfad: mappt direkt vom internen TFindingKind+TLeakSeverity
// auf das Display-Enum, OHNE Umweg ueber lokalisierte Strings.
// FileReadError wird zur eigenen Display-Severity, sonst direkte Mapping
// lsError->fsError, lsWarning->fsWarning, lsHint->fsHint.
function SeverityFromKindLevel(Kind: TFindingKind;
  Sev: TLeakSeverity): TFindingSeverity;

// Locale-toleranter String-zu-Enum-Mapper. Akzeptiert deutsche UND
// englische Schreibweise (`Fehler`/`Error`, `Warnung`/`Warning`, ...).
// Brauchen wir noch fuer Stellen die String-Cell-Inhalte zurueckparsen
// (Grid-Renderer, Sort-Comparer). Neuer Code sollte SeverityFromKindLevel
// benutzen.
function SeverityFromText(const S: string): TFindingSeverity;

// Rueckweg fuer UI-Filter und Default-Anzeige.
function SeverityToText(S: TFindingSeverity): string;

implementation

uses
  System.SysUtils;

function SeverityFromKindLevel(Kind: TFindingKind;
  Sev: TLeakSeverity): TFindingSeverity;
begin
  if Kind = fkFileReadError then
    Exit(fsFileError);
  case Sev of
    lsError   : Result := fsError;
    lsWarning : Result := fsWarning;
    lsHint    : Result := fsHint;
  else
    Result := fsUnknown;
  end;
end;

function SeverityFromText(const S: string): TFindingSeverity;
begin
  // DE und EN parallel - ohne diesen Doppelmatch wuerde der Filter
  // beim Sprachwechsel auf Englisch silent versagen.
  if      SameText(S, 'Fehler')     or SameText(S, 'Error')      then Result := fsError
  else if SameText(S, 'Warnung')    or SameText(S, 'Warning')    then Result := fsWarning
  else if SameText(S, 'Hinweis')    or SameText(S, 'Hint')       then Result := fsHint
  else if SameText(S, 'Lesefehler') or SameText(S, 'Read Error') then Result := fsFileError
  else                                                                Result := fsUnknown;
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
