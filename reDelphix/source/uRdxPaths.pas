unit uRdxPaths;

// reDelphix - die EINE Regel "liegt ein Pfad im Netz?" (Code-Review
// reDelphix, Charge B2S-a). Wo reDelphix von der Platte liest - Include-
// Dateien (SCA164, SCA147, SCA014), Formdateien (SCA147), Projektdateien
// (SCA014) und die Verzeichnisse der Projekt-Units ("uses: X -> Scope.X") -,
// liest es auf einem Netzpfad nichts: der Menueaufbau laeuft im
// Hauptthread, und ein nicht erreichbarer Server haelt jedes FileExists
// Sekunden auf (Gegen-Review R4-03: 9 bis 16 s je Include; Review FB,
// R2-07: 2,5 bis 16 s je Aufruf). Die Stellen fragen hier, WAS ein
// Netzpfad ist; ihre Gruende (Texte) behalten sie selbst.
//
// DIE REGEL (IsNetworkPath): ohne den Vorsatz des Win32-Namensraums -
// '\\?\' (lange Pfade) bzw. '\\.\' (Geraete), dahinter 'UNC\' fuer einen
// Netzpfad (WithoutNamespacePrefix) - liegt ein Pfad im Netz, wenn er mit
// zwei Trennern beginnt ('\\server\share\..', auch mit '/') oder auf einem
// Laufwerk, das Windows als Netzlaufwerk fuehrt (GetDriveType). Also:
// '\\?\C:\..' ist lokal, '\\?\UNC\srv\share\..' ist der Netzpfad
// '\\srv\share\..', ein relativer Pfad liegt nirgends.
//
// WARUM EINE UNIT: bis Charge B2S-a stand die Regel an fuenf Stellen, mit
// verschiedenem Verhalten - uRdxFixTable (Namensraum seit Charge FB, das
// Netzlaufwerk von SCA014 ohne ihn), uRdxRoutineFixes.IsNetworkPath fuer
// die Includes (Charge B1-FD; '\\?\C:\..' galt dort als Netzpfad, weil er
// mit zwei Trennern beginnt - SCA164/SCA147 mit Include und SCA014 lehnten
// einen lokalen langen Pfad ab), uRdxMagicFixes (nutzte dieselbe),
// uRdxScopeTable (nur UNC, das Netzlaufwerk ueber eine eigene Naht) und
// uRdxEditor (GetDriveType fuer diese Naht).
//
// OHNE Winapi.Windows: GetDriveType ist selbst deklariert - die Unit
// braechte Tausende Namen in die Planer (vor System.SysUtils verdeckte sie
// FindClose u. a.), und der FPC-Pruefstand kennt Winapi.Windows nicht
// (FPC: Windows). Die Naht fuer Tests ersetzt genau diese eine Frage an
// Windows (SetRdxRemoteDriveTest).

interface

type
  // Ist das Laufwerk ADrive ('Z:') ein Netzlaufwerk? Die Form der Naht
  // SetRdxRemoteDriveTest - eine schlichte Funktion, weil FPC 3.2 keine
  // Funktionsreferenzen kennt.
  TRdxDriveTest = function(const ADrive: string): Boolean;

// APath ohne den Vorsatz des Win32-Namensraums: '\\?\C:\src\t.pas' ->
// 'C:\src\t.pas' (ein lokaler Pfad, lang geschrieben; '\\.\' ebenso),
// '\\?\UNC\srv\share\t.pas' -> '\\srv\share\t.pas' ('UNC\' gross oder
// klein). Ohne Vorsatz unveraendert.
function WithoutNamespacePrefix(const APath: string): string;

// Beginnt APath mit zwei Trennern, '\' oder '/' ('\\server\share',
// '//server/share', auch ein Vorsatz '\\?\')? Reine Form, OHNE den
// Namensraum abzuziehen: so ein Pfad ist absolut (uRdxScopeTable.
// AddSearchPath haengt ihn an kein Projektverzeichnis). Ob er im Netz
// liegt, sagt erst IsNetworkPath.
function HasUncLead(const APath: string): Boolean;

// Das Laufwerk ('Z:', geschrieben wie in APath) von APath ohne
// Namensraum-Vorsatz, wenn Windows es als Netzlaufwerk fuehrt
// (GetDriveType bzw. die Naht); sonst ''. GetDriveType fragt die
// Laufwerkstabelle, nicht den Server - auch ein getrenntes Netzlaufwerk
// antwortet sofort.
function RemoteDriveOf(const APath: string): string;

// Die Regel (s. Kopf): True fuer UNC ('\\server\share\..', '//..',
// '\\?\UNC\..', '\\.\UNC\..') und einen Pfad auf einem Netzlaufwerk
// ('Z:\..', '\\?\Z:\..'); False fuer einen lokalen ('C:\..', '\\?\C:\..',
// '\\.\C:\..') und einen relativen Pfad ('defs.inc', '\defs.inc', '').
function IsNetworkPath(const APath: string): Boolean;

// Die Naht fuer Tests: ATest beantwortet ab jetzt, ob ein Laufwerk ein
// Netzlaufwerk ist; nil stellt GetDriveType wieder her. Der Wert gilt
// prozessweit - ein Test setzt ihn und stellt ihn im finally zurueck.
procedure SetRdxRemoteDriveTest(ATest: TRdxDriveTest);

implementation

uses
  System.SysUtils;   // CharInSet, SameText

const
  // Vorsaetze des Win32-Namensraums: '\\?\' (lange Pfade) und '\\.\'
  // (Geraete); dahinter 'UNC\' = Netzpfad, der als '\\' weitergeht.
  WIN32_NS_PREFIXES: array[0..1] of string = ('\\?\', '\\.\');
  WIN32_NS_UNC = 'UNC\';
  UNC_LEAD     = '\\';
  // GetDriveType: ein Netzlaufwerk (DRIVE_REMOTE, WinBase.h).
  DRIVE_KIND_REMOTE = 4;

{$IFDEF MSWINDOWS}
// GetDriveType aus kernel32, selbst deklariert statt Winapi.Windows (s.
// Kopf).
function GetDriveTypeW(lpRootPathName: PWideChar): Cardinal; stdcall;
  external 'kernel32.dll' name 'GetDriveTypeW';
{$ENDIF}

var
  // Die Naht (SetRdxRemoteDriveTest); nil = GetDriveType.
  GRemoteDriveTest: TRdxDriveTest = nil;

// Ist ADrive ('Z:') ein Netzlaufwerk? Die Naht, sonst GetDriveType.
function IsRemoteDrive(const ADrive: string): Boolean;
begin
  if Assigned(GRemoteDriveTest) then
    Exit(GRemoteDriveTest(ADrive));
  {$IFDEF MSWINDOWS}
  Result := GetDriveTypeW(PWideChar(ADrive + '\')) = DRIVE_KIND_REMOTE;
  {$ELSE}
  Result := False;
  {$ENDIF}
end;

function WithoutNamespacePrefix(const APath: string): string;
var
  i : Integer;
begin
  Result := APath;
  for i := 0 to High(WIN32_NS_PREFIXES) do
    if Copy(APath, 1, Length(WIN32_NS_PREFIXES[i])) = WIN32_NS_PREFIXES[i] then
    begin
      Result := Copy(APath, Length(WIN32_NS_PREFIXES[i]) + 1, MaxInt);
      if SameText(Copy(Result, 1, Length(WIN32_NS_UNC)), WIN32_NS_UNC) then
        Result := UNC_LEAD + Copy(Result, Length(WIN32_NS_UNC) + 1, MaxInt);
      Exit;
    end;
end;

function HasUncLead(const APath: string): Boolean;
begin
  Result := (Length(APath) > 2) and CharInSet(APath[1], ['\', '/'])
    and CharInSet(APath[2], ['\', '/']);
end;

function RemoteDriveOf(const APath: string): string;
var
  Path : string;
begin
  Result := '';
  Path := WithoutNamespacePrefix(APath);
  if (Length(Path) >= 2) and (Path[2] = ':')
     and CharInSet(Path[1], ['A'..'Z', 'a'..'z'])
     and IsRemoteDrive(Copy(Path, 1, 2)) then
    Result := Copy(Path, 1, 2);
end;

function IsNetworkPath(const APath: string): Boolean;
begin
  Result := HasUncLead(WithoutNamespacePrefix(APath))
    or (RemoteDriveOf(APath) <> '');
end;

procedure SetRdxRemoteDriveTest(ATest: TRdxDriveTest);
begin
  GRemoteDriveTest := ATest;
end;

end.
