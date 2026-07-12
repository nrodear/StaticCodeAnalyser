unit uHardcodedPath;

// Detektor fuer hardkodierte Datei-/Verzeichnispfade im Code.
// Erkannte Muster:
//   'C:\...'    Windows-Laufwerksbuchstabe
//   '\\\\...'   UNC-Pfad
//   '/opt/...'  Unix-Applikations-Pfad
//   '/home/...' Unix-User-Verzeichnis
//   '~/...'     Unix-Home
//
// Nicht gemeldet (kanonische System-Pfade, erwartet in OS-nahem cross-platform Code):
//   /etc/, /var/, /tmp/, /usr/, /proc/, /sys/, /bin/, /sbin/
//
// Hardkodierte Pfade verhindern Portabilitaet und sind oft umgebungsabhaengig.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  THardcodedPathDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    class function LooksLikePath(const S: string): Boolean; static;
    class procedure ExtractStrings(const Text: string; Lst: TStringList); static;
    class function IsAssertionCall(const CallText: string): Boolean; static;
  end;

implementation

// noinspection-file BeginEndRequired, ConcatToFormat, CyclomaticComplexity, MagicNumber, MultipleExit, NestedTry, StringConcatInLoop, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

class function THardcodedPathDetector.LooksLikePath(const S: string): Boolean;
var
  Low: string;
begin
  Result := False;
  if Length(S) < 4 then Exit;

  // Windows-Laufwerksbuchstabe: 'X:\' oder 'X:/'
  if (Length(S) >= 3) and CharInSet(S[1], ['A'..'Z', 'a'..'z']) and
     (S[2] = ':') and CharInSet(S[3], ['\', '/']) then
    Exit(True);

  // UNC-Pfad: '\\server\share' - Servername darf zusaetzlich '_' und '-'
  // enthalten (RFC 952/1123, gaengige interne Hostnamen).
  if (Length(S) >= 4) and (S[1] = '\') and (S[2] = '\') and
     CharInSet(S[3], ['A'..'Z', 'a'..'z', '0'..'9', '_', '-']) then
    Exit(True);

  Low := S.ToLower;
  // Kanonische Linux-System-Pfade: erwartet in cross-platform OS-Code,
  // kein False-Positive bei '/etc/ssl/certs', '/var/run/...', etc.
  for var SysPrefix in ['/etc/', '/var/', '/tmp/', '/usr/', '/proc/', '/sys/',
                        '/bin/', '/sbin/'] do
    if Low.StartsWith(SysPrefix) then Exit(False);

  // Applikations-/User-spezifische Unix-Pfade sind echte Hardcodes.
  for var AppPrefix in ['/opt/', '/home/'] do
    if Low.StartsWith(AppPrefix) then Exit(True);

  // Unix Home: '~/...'
  if Low.StartsWith('~/') then Exit(True);
end;

class procedure THardcodedPathDetector.ExtractStrings(const Text: string;
  Lst: TStringList);
var
  i      : Integer;
  Inside : Boolean;
  Buf    : string;
begin
  i      := 1;
  Inside := False;
  Buf    := '';
  while i <= Length(Text) do
  begin
    if Text[i] = '''' then
    begin
      if not Inside then
      begin
        Inside := True;
        Buf    := '';
      end
      else
      begin
        if (i < Length(Text)) and (Text[i + 1] = '''') then
        begin
          Buf := Buf + '''';
          Inc(i, 2);
          Continue;
        end;
        Inside := False;
        if Buf <> '' then Lst.Add(Buf);
      end;
    end
    else if Inside then
      Buf := Buf + Text[i];
    Inc(i);
  end;
end;

// Real-World-FP-Audit 2026-07-12 (FP-Klasse 'test-vector-/expected-value-
// Pfadliteral'): True, wenn der Callee dieses Aufrufs eine Test-Assertion ist
// (DUnitX Assert.* inkl. Assert.AreEqual/WillRaiseWithMessage, klassisches
// DUnit Check/CheckEquals/... oder ein AreEqual/AreNotEqual eines Fremd-
// Frameworks). Pfad-Literale in solchen Aufrufen sind Erwartungs-/Vergleichs-
// werte (oder Eingabe-Vektoren fuer Assertions) und beruehren nie das
// Dateisystem - im Gegensatz zu echten Datei-Operationen (SaveToFile,
// LoadFromFile, System.Assign, ...Create, ...), deren Callee hier NICHT matcht
// und die daher Fund bleiben. TP-sicher: greift nur bei nkCall, nie bei
// nkAssign ('FPath := ''C:\...''' bleibt Fund).
class function THardcodedPathDetector.IsAssertionCall(
  const CallText: string): Boolean;
var
  Callee : string;
  P      : Integer;
begin
  Result := False;
  P := Pos('(', CallText);
  if P = 0 then Exit;                        // kein Aufruf mit Argumentliste
  Callee := Copy(CallText, 1, P - 1).Trim.ToLower;
  if Callee = '' then Exit;

  // DUnitX: 'Assert.AreEqual', 'Assert.Contains', 'Assert.WillRaise...' u.a.,
  // sowie Delphis eingebautes 'Assert(...)'.
  if (Callee = 'assert') or Callee.StartsWith('assert.') then Exit(True);

  // Klassisches DUnit (TTestCase): unqualifiziertes Check / CheckEquals / ...
  // Exakt-Match (KEIN Praefix!) - Produktions-Helfer wie 'CheckFileExists'
  // duerfen NICHT matchen (TP-Schutz).
  for var A in ['check', 'checkequals', 'checknotequals',
                'checkequalsstring', 'checkequalswidestring',
                'checkequalsmem'] do
    if Callee = A then Exit(True);

  // Fremd-Framework mit AreEqual/AreNotEqual-Methode (defensiv).
  if Callee.EndsWith('.areequal') or Callee.EndsWith('.arenotequal') then
    Exit(True);
end;

class procedure THardcodedPathDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  AllNodes : TList<TAstNode>;
  N        : TAstNode;
  Lst      : TStringList;
  S        : string;
  F        : TLeakFinding;
  Reported : TDictionary<string, Boolean>;
  Display  : string;
begin
  Reported := nil;
  Lst      := nil;
  try
    Reported := TDictionary<string, Boolean>.Create;
    Lst      := TStringList.Create;
    for var Kind in [nkAssign, nkCall] do
    begin
      AllNodes := UnitNode.FindAll(Kind);
      try
        for N in AllNodes do
        begin
          // Real-World-FP-Audit 2026-07-12 - FP-Klasse 'test-vector-/expected-
          // value-Pfadliteral': ein pfadfoermiges Literal, das nur als
          // Erwartungs-/Vergleichswert eines Assertions-Aufrufs dient
          // (Assert.AreEqual / Check / CheckEquals / Assert.WillRaise...),
          // beruehrt nie das Dateisystem. Additive Suppression NUR fuer nkCall
          // mit Assertions-Callee - ein echter Hardcode in Produktions-Code
          // (SaveToFile/LoadFromFile/Assign/... nkCall mit anderem Callee, oder
          // die Zuweisung 'FPath := ''C:\...''' als nkAssign) bleibt Fund.
          if (Kind = nkCall) and IsAssertionCall(N.Name) then Continue;

          Lst.Clear;
          if Kind = nkAssign then
            ExtractStrings(N.TypeRef, Lst)
          else
            ExtractStrings(N.Name, Lst);

          for S in Lst do
          begin
            if not LooksLikePath(S) then Continue;

            // Pro Pfad nur einmal pro Datei melden
            if Reported.ContainsKey(S) then Continue;
            Reported.Add(S, True);

            Display := S;
            if Length(Display) > 40 then
              Display := Copy(Display, 1, 37) + '...';

            F            := TLeakFinding.Create;
            F.FileName   := FileName;
            F.MethodName := '';
            F.LineNumber := IntToStr(N.Line);
            F.MissingVar := 'Hardcoded path: "' + Display + '"';
            F.SetKind(fkHardcodedPath);
            Results.Add(F);
          end;
        end;
      finally
        AllNodes.Free;
      end;
    end;
  finally
    Lst.Free;
    Reported.Free;
  end;
end;

end.
