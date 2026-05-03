unit uSCAConsts;

interface

uses
  System.Classes, SysUtils;

var
  Flags: Byte;

  LeakyClasses: array [0 .. 26] of string = (
    'TStringList',
    'TList',
    'TObjectList',
    'TOracleQuery',
    'TOracleSession',
    'TQuery',
    'TSQLQuery',
    'TKSQLQuery',
    'TFileStream',
    'TMemoryStream',
    'TStringStream',
    'TBitmap',
    'TFont',
    'TThread',
    'TComponent',
    'TDataSet',
    'TSocket',
    'TRegistry',
    'TResourceStream',
    'TXMLDocument',
    'THTTPClient',
    'TTimer',
    'TIniFile',
    'TMemIniFile',
    'TStreamReader',
    'TStreamWriter',
    'TZipFile'
  );

type
  // Schweregrad eines Befundes - drei Stufen:
  //   lsError   - sichere Bugs / Sicherheitsluecken (Crash, Datenleak)
  //   lsWarning - wahrscheinliche Bugs / riskante Muster
  //   lsHint    - Code-Smells / Stilfragen (kein Bug, nur Wartbarkeit)
  TLeakSeverity = (
    lsError,
    lsWarning,
    lsHint
  );

  // Art des Befundes
  TFindingKind = (
    fkMemoryLeak,       // Speicherleck (TLeakDetector)
    fkEmptyExcept,      // Leerer except-Block (verschluckt Exceptions)
    fkSQLInjection,     // SQL-String per '+' konkateniert (Injection-Risiko)
    fkHardcodedSecret,  // Passwort/Token als Stringliteral im Code
    fkFormatMismatch,   // Format()-Platzhalter ≠ Argument-Anzahl
    fkFileReadError,    // Datei konnte nicht gelesen / geparst werden
    fkUnusedUses,       // Uses-Eintrag moeglicherweise ungenutzt
    fkNilDeref,         // Zugriff auf Variable die nil sein kann
    fkMissingFinally,   // .Create ohne schuetzenden try/finally-Block
    fkDivByZero,        // Division durch Variable/Ausdruck der 0 sein koennte
    fkDeadCode,         // Toter Code nach Exit / raise
    fkLongMethod,       // Methode laenger als N Zeilen
    fkLongParamList,    // Methode hat zu viele Parameter
    fkMagicNumber,      // Zahlenliteral ohne Konstante
    fkDuplicateString,  // String-Literal an mehreren Stellen
    fkHardcodedPath,    // Pfad-Literal im Code (C:\ oder UNC)
    fkDebugOutput,      // WriteLn/ShowMessage in Produktion
    fkDeepNesting,      // Zu tiefe Verschachtelung
    fkTodoComment,      // TODO/FIXME/HACK/XXX im Kommentar
    fkEmptyMethod,      // Methodenrumpf ohne Anweisungen
    fkDuplicateBlock    // mehrere identische Code-Blocks (>=8 Zeilen)
  );

  // SonarQube-aehnliche Kategorisierung der Befunde:
  //   ftBug             - falsches Verhalten (Crash, falsches Ergebnis)
  //   ftCodeSmell       - Wartbarkeit / Lesbarkeit, kein Bug
  //   ftVulnerability   - Sicherheitsluecke
  //   ftSecurityHotspot - sicherheitsrelevant, im Einzelfall pruefen
  //   ftCodeDuplication - kopierter / nicht extrahierter Code
  //   ftFileError       - Sonderfall: Parser/IO-Fehler, kein Code-Befund
  TFindingType = (
    ftBug,
    ftCodeSmell,
    ftVulnerability,
    ftSecurityHotspot,
    ftCodeDuplication,
    ftFileError
  );

  TConsts = record
    class function GetLeakyClasses: TStringList; static;
  end;

  TSectionFlag = record
  const
    FLAG_NONE = $00;     // 00000000
    FLAG_Unit = $01;     // 00000001
    FLAG_interface = $02;// 00000010
    FLAG_uses = $04;     // 00000100
    FLAG_type = $08;     // 00001000
    FLAG_method = $10;   // 00010000
    FLAG_var = $20;      // 00100000
    FLAG_ignore = $40;   // 01000000     !!!!!!!!!!!!!
    FLAG_implementation = $80; // 10000000
    FLAG_ALL = $FF; // 11111111 (Alle Bits gesetzt)
  end;

implementation

{ TConsts }

class function TConsts.GetLeakyClasses: TStringList;
var
  myLeakyClasses: TStringList;
begin
  myLeakyClasses := TStringList.Create;
  myLeakyClasses.AddStrings(LeakyClasses);
  Result := myLeakyClasses;
end;

end.
