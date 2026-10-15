unit uTestRdxPaths;

// Charge B2S-a (Code-Review reDelphix, Konsolidierung): die EINE
// Netzpfad-Regel uRdxPaths - lokal, UNC mit '\' und '/', der Win32-
// Namensraum ('\\?\C:\..' und '\\.\C:\..' lokal, '\\?\UNC\..' und
// '\\.\UNC\..' Netzpfad), ein Netzlaufwerk ueber die Naht
// (SetRdxRemoteDriveTest), ein relativer Pfad, das echte GetDriveType an
// TEMP. Dazu die beiden Hilfen, die bis dahin einen lokalen langen Pfad
// ('\\?\C:\..') als Netzpfad ablehnten - beide gegen 9713942b rot: SCA164
// mit Include (TRdxRoutineFixes.IncludeReason; SCA147 liest seine Includes
// ueber dieselbe Kette) und SCA014 (TRdxMagicFixes.FileReason und
// IncludeReason). Je eine Gegenprobe zeigt, dass die Hilfe die Datei ueber
// den langen Pfad wirklich liest. Laeuft in reDelphix.Test UND im
// FPC-Pruefstand. Pfade aus Teilen (ein Literal waere ein SCA016-Fund im
// Selbstscan); die Dateien liegen unter TEMP\rdx_b2s_<GUID>, die Unit drei
// Ebenen tiefer - das Fenster von FileReason (Verzeichnis der Unit und
// zwei darueber) bleibt im eigenen Baum (wie uTestRdxMagicGuards).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxPaths = class
  public
    [Test] procedure LocalDrive_NotNetwork;
    [Test] procedure Unc_BothSeparators_Network;
    [Test] procedure LongLocalPath_NotNetwork;
    [Test] procedure NamespaceUnc_Network;
    [Test] procedure DeviceNamespace_LikeLongPath;
    [Test] procedure RemoteDrive_ViaSeam;
    [Test] procedure RelativePath_NeverNetwork;
    [Test] procedure RealDriveTest_TempIsLocal;
    [Test] procedure Sca164_IncludeOnLongLocalPath_Read;
    [Test] procedure Sca014_LongLocalPath_Read;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxCodeMap, uRdxRoutineFixes, uRdxMagicFixes,
  uRdxPaths;

const
  DRIVE_C = 'C:';
  DRIVE_Q = 'Q:';   // das Netzlaufwerk der Attrappe
  MSG_164 = 'Top-level routine Dead appears unused (no caller within the '
    + 'unit, no interface forward-declaration)';

// ---- Helfer ----

// Die Teile mit ASep verbunden (ein Pfad als Literal waere ein
// SCA016-Fund im Selbstscan). ASep als string: der TStringBuilder von FPC
// 3.2 baut AnsiString, ein Char haengte er nicht sicher als Zeichen an.
function PathOf(const AParts: array of string; const ASep: string): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(AParts) do
    begin
      if i > 0 then
        SB.Append(ASep);
      SB.Append(AParts[i]);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Der Vorsatz des Win32-Namensraums: '\\?\' (lange Pfade) bzw. '\\.\'.
function LongPrefix: string;
begin
  Result := PathDelim + PathDelim + '?' + PathDelim;
end;

function DevicePrefix: string;
begin
  Result := PathDelim + PathDelim + '.' + PathDelim;
end;

// Attrappe fuer GetDriveType: nur Q: ist ein Netzlaufwerk.
function FakeRemoteDrive(const ADrive: string): Boolean;
begin
  Result := SameText(ADrive, DRIVE_Q);
end;

// Attrappe: jedes Laufwerk ist ein Netzlaufwerk.
function FakeAllRemote(const ADrive: string): Boolean;
begin
  Result := ADrive <> '';
end;

// Zeilen mit CRLF verbunden (TStringBuilder: string.Join kennt FPC nicht).
function Join(const ALines: array of string): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(ALines) do
    begin
      if i > 0 then SB.Append(#13#10);
      SB.Append(ALines[i]);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure WriteText(const APath, AText: string);
var
  SL : TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Text := AText;
    SL.SaveToFile(APath);
  finally
    SL.Free;
  end;
end;

// Loescht den Baum ADir (mit Trenner) samt Inhalt.
procedure RemoveTree(const ADir: string);
var
  SR : TSearchRec;
begin
  if FindFirst(ADir + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then
        Continue;
      if (SR.Attr and faDirectory) <> 0 then
        RemoveTree(ADir + SR.Name + PathDelim)
      else
        DeleteFile(ADir + SR.Name);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
  RemoveDir(ADir);
end;

// Der Baum fuer einen Test: Root\a\b\c\u.pas (s. Kopf); Root und das
// Verzeichnis der Unit mit Trenner.
type
  TTree = record
    Root, Dir, U : string;
  end;

function NewTree: TTree;
var
  G : TGUID;
begin
  CreateGUID(G);
  Result.Root := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP'))
    + 'rdx_b2s_' + GUIDToString(G) + PathDelim;
  Result.Dir := Result.Root + PathOf(['a', 'b', 'c', ''], PathDelim);
  Result.U := Result.Dir + 'u.pas';
  ForceDirectories(Result.Dir);
end;

// ---- Die Regel ----

procedure TTestRdxPaths.LocalDrive_NotNetwork;
var
  P : string;
begin
  SetRdxRemoteDriveTest(FakeRemoteDrive);
  try
    P := PathOf([DRIVE_C, 'src', 'u.pas'], PathDelim);
    Assert.IsFalse(IsNetworkPath(P), P);
    Assert.AreEqual('', RemoteDriveOf(P));
    Assert.IsFalse(HasUncLead(P), 'kein UNC');
    Assert.AreEqual(P, WithoutNamespacePrefix(P), 'ohne Vorsatz unveraendert');
  finally
    SetRdxRemoteDriveTest(nil);
  end;
end;

procedure TTestRdxPaths.Unc_BothSeparators_Network;
var
  Unc : string;
begin
  Unc := PathOf(['', '', 'srv', 'share', 'u.pas'], PathDelim);
  Assert.IsTrue(IsNetworkPath(Unc), Unc);
  Assert.IsTrue(HasUncLead(Unc));
  Assert.AreEqual('', RemoteDriveOf(Unc), 'UNC ist kein Laufwerk');
  Assert.IsTrue(IsNetworkPath(PathOf(['', '', 'srv', 'share', 'u.pas'], '/')),
    'UNC mit /');
  // Zwei Trenner allein sind noch kein Server.
  Assert.IsFalse(HasUncLead(PathDelim + PathDelim), 'nur zwei Trenner');
end;

procedure TTestRdxPaths.LongLocalPath_NotNetwork;
var
  L : string;
begin
  // Der Fehler aus dem Merge der Fix-Welle: '\\?\C:\..' beginnt mit zwei
  // Trennern und hiess in uRdxRoutineFixes.IsNetworkPath "Netzpfad" -
  // uRdxFixTable (Charge FB) wusste es besser. Jetzt EINE Regel.
  SetRdxRemoteDriveTest(FakeRemoteDrive);
  try
    L := LongPrefix + PathOf([DRIVE_C, 'src', 'u.pas'], PathDelim);
    Assert.IsFalse(IsNetworkPath(L), L);
    Assert.AreEqual(PathOf([DRIVE_C, 'src', 'u.pas'], PathDelim),
      WithoutNamespacePrefix(L));
    Assert.IsTrue(HasUncLead(L), 'der Form nach absolut (zwei Trenner)');
    // Ein Netzlaufwerk bleibt eines, auch lang geschrieben.
    L := LongPrefix + PathOf([DRIVE_Q, 'src', 'u.pas'], PathDelim);
    Assert.IsTrue(IsNetworkPath(L), L);
    Assert.AreEqual(DRIVE_Q, RemoteDriveOf(L));
  finally
    SetRdxRemoteDriveTest(nil);
  end;
end;

procedure TTestRdxPaths.NamespaceUnc_Network;
var
  L : string;
begin
  L := LongPrefix + PathOf(['UNC', 'srv', 'share', 'u.pas'], PathDelim);
  Assert.IsTrue(IsNetworkPath(L), L);
  Assert.AreEqual(PathOf(['', '', 'srv', 'share', 'u.pas'], PathDelim),
    WithoutNamespacePrefix(L), 'UNC\ wird zu \\');
  L := LongPrefix + PathOf(['unc', 'srv', 'share'], PathDelim);
  Assert.IsTrue(IsNetworkPath(L), 'UNC\ gross oder klein: ' + L);
end;

procedure TTestRdxPaths.DeviceNamespace_LikeLongPath;
var
  D : string;
begin
  SetRdxRemoteDriveTest(FakeRemoteDrive);
  try
    D := DevicePrefix + PathOf([DRIVE_C, 'src', 'u.pas'], PathDelim);
    Assert.IsFalse(IsNetworkPath(D), D);
    Assert.AreEqual(PathOf([DRIVE_C, 'src', 'u.pas'], PathDelim),
      WithoutNamespacePrefix(D));
    D := DevicePrefix + PathOf(['UNC', 'srv', 'share', 'u.pas'], PathDelim);
    Assert.IsTrue(IsNetworkPath(D), D);
  finally
    SetRdxRemoteDriveTest(nil);
  end;
end;

procedure TTestRdxPaths.RemoteDrive_ViaSeam;
var
  P : string;
begin
  // Die Naht ersetzt genau die Frage an Windows (GetDriveType) - fuer
  // Unit, Include, Formdatei und Projekt-Units dieselbe.
  SetRdxRemoteDriveTest(FakeRemoteDrive);
  try
    P := PathOf([DRIVE_Q, 'lib', 'u.pas'], PathDelim);
    Assert.IsTrue(IsNetworkPath(P), P);
    Assert.AreEqual(DRIVE_Q, RemoteDriveOf(P));
    P := PathOf([LowerCase(DRIVE_Q), 'lib'], PathDelim);
    Assert.IsTrue(IsNetworkPath(P), 'klein geschrieben: ' + P);
    Assert.AreEqual(LowerCase(DRIVE_Q), RemoteDriveOf(P),
      'das Laufwerk wie im Pfad');
    Assert.AreEqual(DRIVE_Q, RemoteDriveOf(DRIVE_Q), 'nur das Laufwerk');
    Assert.IsFalse(IsNetworkPath(PathOf([DRIVE_C, 'lib'], PathDelim)),
      'ein anderes Laufwerk');
  finally
    SetRdxRemoteDriveTest(nil);
  end;
end;

procedure TTestRdxPaths.RelativePath_NeverNetwork;
begin
  // Auch wenn jedes Laufwerk ein Netzlaufwerk waere: ein relativer Pfad
  // nennt keines und liegt nirgends - wie bisher auch '\x.inc' (ab der
  // Wurzel, ohne Laufwerk; uRdxRoutineFixes.IncludeSearchPath sucht es auf
  // dem Laufwerk der Unit, und deren Pfad wird geprueft).
  SetRdxRemoteDriveTest(FakeAllRemote);
  try
    Assert.IsFalse(IsNetworkPath('defs.inc'), 'Dateiname');
    Assert.IsFalse(IsNetworkPath(PathOf(['..', 'inc', 'defs.inc'], PathDelim)),
      'relativ mit ..');
    Assert.IsFalse(IsNetworkPath(PathDelim + 'defs.inc'), 'ab der Wurzel');
    Assert.IsFalse(IsNetworkPath(''), 'leer');
    Assert.AreEqual('', RemoteDriveOf('defs.inc'));
    Assert.IsTrue(IsNetworkPath(PathOf([DRIVE_C, 'x'], PathDelim)),
      'Gegenprobe: mit Laufwerk fragt die Regel die Attrappe');
  finally
    SetRdxRemoteDriveTest(nil);
  end;
end;

procedure TTestRdxPaths.RealDriveTest_TempIsLocal;
var
  T : string;
begin
  // Ohne Naht fragt die Regel Windows (GetDriveTypeW, selbst deklariert).
  // Voraussetzung wie in uTestRdxRoutineFixes: TEMP liegt lokal.
  T := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP'));
  Assert.IsFalse(IsNetworkPath(T), T);
  Assert.AreEqual('', RemoteDriveOf(T));
  Assert.IsFalse(IsNetworkPath(LongPrefix + T), 'lang geschrieben: ' + T);
end;

// ---- Die Hilfen auf einem lokalen langen Pfad ----

procedure TTestRdxPaths.Sca164_IncludeOnLongLocalPath_Read;
var
  T    : TTree;
  SL   : TStringList;
  Map  : TRdxCodeMap;
  Plan : TRdxRoutinePlan;
  R    : string;
  Ok   : Boolean;
begin
  // Bis Charge B2S-a: der Planer nennt das Include, und IncludeReason
  // lehnte ab - "Include defs.inc ... auf einem Netzpfad (\\?\C:)", obwohl
  // uRdxFixTable.NetworkPathReason den Pfad (Charge FB) lokal nannte.
  T := NewTree;
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := Join(['unit u;', 'interface', 'uses Classes;',
      '{$I defs.inc}', 'implementation', '', 'procedure Dead;', 'begin',
      'end;', '', 'end.']);
    Map := TRdxCodeMap.Create(SL);
    Ok := TRdxRoutineFixes.UnusedRoutine(Map, 7, MSG_164, Plan, R);
    Assert.IsTrue(Ok, R);
    Assert.AreEqual<Integer>(1, Integer(Length(Plan.Includes)), 'Includes');
    WriteText(T.Dir + 'defs.inc', '{$DEFINE RDX_B2S}');
    R := TRdxRoutineFixes.IncludeReason(LongPrefix + T.U, Plan.Includes,
      Plan.Name);
    Assert.AreEqual('', R, 'lokal, nur lang geschrieben');
    // Gegenprobe: nennt das Include die Routine, lehnt die Hilfe ab - sie
    // hat es ueber den langen Pfad gelesen.
    WriteText(T.Dir + 'defs.inc', 'procedure Dead;');
    R := TRdxRoutineFixes.IncludeReason(LongPrefix + T.U, Plan.Includes,
      Plan.Name);
    Assert.IsTrue(Pos('nennt Dead', R) > 0, R);
    Assert.IsTrue(Pos('Netzpfad', R) = 0, R);
  finally
    Map.Free;
    SL.Free;
    RemoveTree(T.Root);
  end;
end;

procedure TTestRdxPaths.Sca014_LongLocalPath_Read;
var
  T   : TTree;
  SL  : TStringList;
  Map : TRdxCodeMap;
  R   : string;
begin
  // Bis Charge B2S-a: FileReason lehnte '\\?\C:\..' als "Netzpfad" ab
  // (uRdxRoutineFixes.IsNetworkPath), IncludeReason ebenso.
  T := NewTree;
  SL := TStringList.Create;
  Map := nil;
  try
    Assert.AreEqual('', TRdxMagicFixes.FileReason(LongPrefix + T.U),
      'kein Projekt im Fenster, kein Netzpfad');
    SL.Text := Join(['unit u;', 'interface', '{$I defs.inc}',
      'implementation', 'end.']);
    Map := TRdxCodeMap.Create(SL);
    WriteText(T.Dir + 'defs.inc', '{$DEFINE RDX_B2S}');
    Assert.AreEqual('', TRdxMagicFixes.IncludeReason(LongPrefix + T.U, Map),
      'Include ohne Weiche, lang geschrieben');
    // Gegenprobe: die Weiche im Include liest die Hilfe ueber den langen
    // Pfad - und nur deshalb lehnt sie jetzt ab.
    WriteText(T.Dir + 'defs.inc', Join(['{$IFDEF FPC}', '{$MODE DELPHI}',
      '{$ENDIF}']));
    R := TRdxMagicFixes.IncludeReason(LongPrefix + T.U, Map);
    Assert.IsTrue(Pos('FPC-Weiche', R) > 0, R);
    Assert.IsTrue(Pos('Netzpfad', R) = 0, R);
  finally
    Map.Free;
    SL.Free;
    RemoveTree(T.Root);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxPaths);

end.
