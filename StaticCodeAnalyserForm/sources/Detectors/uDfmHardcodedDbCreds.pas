unit uDfmHardcodedDbCreds;

// Detektor: Klartext-Credentials auf DB-Verbindungs-Komponenten im DFM.
//
// Findet zwei klassische Vulnerabilities, die der Form-Designer leicht
// einbaut, weil "Connect" zur Designzeit getestet wird und das Passwort
// dabei in die .dfm gespeichert wird:
//
//   1) 'Password' nicht leer als String-Literal
//        Beispiel: 'Password' = 's3cret'
//   2) 'ConnectionString' enthaelt 'Password=' oder 'Pwd=' mit Wert
//        Beispiel: 'ConnectionString' = 'Provider=...;User ID=admin;Password=s3cret;'
//
// Greift nur auf einer kuratierten Whitelist von Connection-Klassen
// (TADOConnection, TFDConnection, TIBDatabase, ...). Query-/StoredProc-
// Komponenten haben in der Regel keine Credentials - sie greifen ueber eine
// Connection auf die DB zu. Die Liste kann via analyser.ini erweitert
// werden (Phase 2, [Components] CredentialBearers=...).
//
// Schweregrad: lsError, FindingType: ftVulnerability.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uComponentGraph;

type
  TDfmHardcodedDbCredsDetector = class
  public
    class procedure Analyze(Graph: TComponentGraph; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  System.StrUtils;

const
  // Default-Whitelist der Klassen, die Credentials tragen koennen.
  // Phase 2 macht das via analyser.ini ueberschreibbar.
  CONNECTION_CLASSES: array[0..6] of string = (
    'TADOConnection', 'TFDConnection', 'TIBDatabase',
    'TSQLConnection', 'TZConnection',  'TUniConnection',
    'TOracleSession'
  );

function IsCredentialBearer(const ClassRef: string): Boolean;
var
  C: string;
begin
  for C in CONNECTION_CLASSES do
    if SameText(ClassRef, C) then Exit(True);
  Result := False;
end;

function ConnectionStringHasPassword(const S: string): Boolean;
// Pruefung ohne echten Connection-String-Parser - die zwei gaengigen
// Schluesselwoerter case-insensitiv abklopfen.
//
// Bewusst false-positive-tolerant: wenn 'Password=' im String vorkommt
// (auch mit angeblich leerem Wert wie 'Password=;'), wird gemeldet -
// echte leere Passwoerter sind in Production-Configs ein eigener Smell.
// Phase-2-Erweiterung kann zwischen "Password=" und "Password=value"
// unterscheiden.
begin
  Result := ContainsText(S, 'Password=') or ContainsText(S, 'Pwd=');
end;

class procedure TDfmHardcodedDbCredsDetector.Analyze(Graph: TComponentGraph;
  const FileName: string; Results: TObjectList<TLeakFinding>);

  procedure AddFinding(N: TComponentNode; const PropName, Why: string;
    Line: Integer);
  var
    F: TLeakFinding;
  begin
    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := '';
    F.LineNumber := IntToStr(Line);
    F.MissingVar := Format('%s (%s).%s: %s',
                            [N.Name, N.ClassRef, PropName, Why]);
    F.Severity   := lsError;
    F.Kind       := fkDfmHardcodedDbCreds;
    Results.Add(F);
  end;

var
  All : TList<TComponentNode>;
  N   : TComponentNode;
  V   : TPropValue;
begin
  if Graph = nil then Exit;

  All := Graph.EnumerateAll;
  try
    for N in All do
    begin
      if not IsCredentialBearer(N.ClassRef) then Continue;

      // 1) Password = '...'
      if N.TryGetProperty('Password', V)
         and (V.Kind = pvkString)
         and (V.RawValue <> '') then
        AddFinding(N, 'Password', 'plaintext password literal in DFM', V.Line);

      // 2) ConnectionString = '...Password=...'
      if N.TryGetProperty('ConnectionString', V)
         and (V.Kind = pvkString)
         and ConnectionStringHasPassword(V.RawValue) then
        AddFinding(N, 'ConnectionString',
                   'connection string embeds Password=/Pwd= credentials',
                   V.Line);
    end;
  finally
    All.Free;
  end;
end;

end.
