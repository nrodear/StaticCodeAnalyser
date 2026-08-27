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
// Nicht gemeldet (OS-feste UNC-Namespaces, kein Host-/Freigabename darin):
//   \\wsl$\, \\wsl.localhost\, \\tsclient
//
// Hardkodierte Pfade verhindern Portabilitaet und sind oft umgebungsabhaengig.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  THardcodedPathDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode;
      const FileName: string; Results: TObjectList<TLeakFinding>;
      AContext: TAnalyzeContext = nil);
  private
    class function LooksLikePath(const S: string): Boolean; static;
    class procedure ExtractStrings(const Text: string; Lst: TStringList); static;
    // Aufruf-Text vor der Argumentliste, getrimmt und lowercase; '' wenn der
    // Knotentext gar keine Argumentliste hat. Gemeinsame Basis von
    // IsAssertionCall und IsLocalTestHelperCall - beide Gates muessen den
    // Callee identisch zuschneiden, sonst driften sie auseinander.
    class function CalleeOf(const CallText: string): string; static;
    class function IsAssertionCall(const CallText: string): Boolean; static;
    class function IsLocalTestHelperCall(const CallText: string): Boolean; static;
  end;

implementation

// AContext war seit der AddD-Registrierung (B10, 2026-08-16) ein bewusst
// ungelesener Platzhalter (mit einem noinspection-file UnusedParameter dafuer).
// Mit Gate A (SCA016-FP-Paket 2026-08-27) kommt die Regelaenderung, auf die er
// gewartet hat: der Detektor liest jetzt CtxScanRoot(AContext). Der Marker ist
// damit weg - die Datei hat keinen weiteren Parameter ohne Leser.

// noinspection-file BeginEndRequired, ConcatToFormat, CyclomaticComplexity, MagicNumber, MultipleExit, NestedTry, StringConcatInLoop, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uDetectorUtils;   // Gate A: zentrale Test-Pfad-Muster (IsTestFixturePath)

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
  begin
    // Gate C (SCA016-FP-Paket 2026-08-27, 3 Funde im Korpus): diese
    // UNC-Wurzeln vergibt das Betriebssystem FEST - es steckt weder ein
    // Host- noch ein Freigabename darin, also nichts Umgebungsabhaengiges,
    // das man konfigurierbar machen koennte. Genau als solche Konstanten
    // benutzt sie der Korpus:
    //   doublecmd-master\src\filesources\winnet\wsl\uwslfilesource.pas:44,50,
    //     52,71 - '\\wsl$\' / '\\wsl.localhost\' als Namespace-Praefixe
    //   doublecmd-master\src\platform\udrivewatcher.pas:801 - lpRemoteName
    //     := '\\tsclient'
    // Ein Admin-Share wie '\\server\c$' bleibt Fund: dort IST der Hostname
    // hardkodiert. Analog zur /etc/-Liste unten, aber hier oben, weil der
    // UNC-Arm vor dem ToLower steht - deshalb StartsWith mit IgnoreCase
    // statt eines vorgezogenen ToLower, das der Laufwerks-Arm mitbezahlen
    // muesste.
    // Gegenpruefung 2026-08-27: Praefix-Match NUR bis zur Segmentgrenze.
    // '\\tsclient' ohne Trenner haette auch '\\tsclient01\install\x.exe'
    // verschluckt - dort IST ein Hostname hardkodiert, und genau das
    // nimmt der Absatz oben fuer Admin-Shares ausdruecklich aus.
    for var OsFixedRoot in ['\\wsl$', '\\wsl.localhost', '\\tsclient'] do
      if SameText(S, OsFixedRoot) or
         S.StartsWith(OsFixedRoot + '\', True) then Exit(False);
    Exit(True);
  end;

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

class function THardcodedPathDetector.CalleeOf(const CallText: string): string;
var
  P : Integer;
begin
  Result := '';
  P := Pos('(', CallText);
  if P = 0 then Exit;                        // kein Aufruf mit Argumentliste
  Result := Copy(CallText, 1, P - 1).Trim.ToLower;
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
begin
  Result := False;
  Callee := CalleeOf(CallText);
  if Callee = '' then Exit;

  // DUnitX: 'Assert.AreEqual', 'Assert.Contains', 'Assert.WillRaise...' u.a.,
  // sowie Delphis eingebautes 'Assert(...)'.
  if (Callee = 'assert') or Callee.StartsWith('assert.') then Exit(True);

  // Klassisches DUnit (TTestCase): unqualifiziertes Check / CheckEquals / ...
  // Exakt-Match (KEIN Praefix!) - Produktions-Helfer wie 'CheckFileExists'
  // duerfen NICHT matchen (TP-Schutz).
  //
  // Gate B (SCA016-FP-Paket 2026-08-27, 7 Funde im Korpus): die zweite Haelfte
  // der Liste ist mORMots eigene Assertions-Familie (TSynTestCase.CheckEqual &
  // Co.) - sie fehlte, obwohl sie dieselbe Rolle spielt wie CheckEquals. Belege:
  //   mORMot2-master\test\test.core.base.pas:958,959,6220,6231,6256,6257
  //     CheckEqual(GetFileNameWithoutExtOrPath('c:\temp\toto.ext'), 'toto')
  //   mORMot2-master\test\test.net.proto.pas:4112,4120 - CheckEqual(U.Address,
  //     'c:\path\to')
  // Die Argumente stehen mit im nkCall-Namen (ParsePrimary faltet die ganze
  // Argumentliste inkl. verschachtelter Aufrufe in EINEN Knoten) - der
  // Callee-Match oben greift also auch bei 'CheckEqual(Foo(''c:\x''), ..)'.
  // Der Exakt-Match bleibt Pflicht: mit Praefix-Match wuerde 'CheckFileExists'
  // (echte Datei-Operation) mitkippen.
  for var A in ['check', 'checkequals', 'checknotequals',
                'checkequalsstring', 'checkequalswidestring',
                'checkequalsmem',
                'checkequal', 'checknotequal', 'checkequaltrim',
                'checkutf8', 'checksame', 'checkmatchany'] do
    if Callee = A then Exit(True);

  // Fremd-Framework mit AreEqual/AreNotEqual-Methode (defensiv).
  if Callee.EndsWith('.areequal') or Callee.EndsWith('.arenotequal') then
    Exit(True);
end;

// Gate A (SCA016-FP-Paket 2026-08-27, 98 Funde im Korpus): True, wenn der
// Callee wie ein LOKALER Testvektor-Helfer heisst ('Test...'). Die Konvention
// ist in Test-Units durchgaengig: eine geschachtelte Prozedur nimmt Eingabe-
// und Erwartungswert entgegen und vergleicht selbst. Fuer IsAssertionCall ist
// so ein Callee unsichtbar (er heisst nicht Assert/Check/AreEqual), obwohl das
// Pfadliteral genauso ein Erwartungswert ist und nie das Dateisystem beruehrt.
// Belege (alle 98 Funde stammen aus drei Dateien):
//   issrc\Components\PathFunc.Test.pas                 94 - TestPathCombine,
//     TestPathExpand, TestPathExtracts, ... je ~40 Vektor-Aufrufe
//   issrc\Projects\Src\Setup.PathRedir.Test.pas         2
//   mORMot2-master\test\test.core.base.pas              2
// Der Praefix allein ist bewusst NICHT hinreichend - der Aufrufer verlangt
// zusaetzlich eine Test-Unit (IsTestFixturePath/tplSecret). In Produktionscode
// bleibt 'TestConnection(''C:\db.fdb'')' Fund.
//
// Qualifizierung: geprueft wird der Namensteil hinter dem letzten Punkt, damit
// 'Self.TestPathCombine(..)' genauso greift. Am Korpus ist das messneutral -
// alle 98 Treffer sind unqualifiziert; die Wahl ist reine Robustheit gegen die
// zweite gaengige Schreibweise, nicht eine Zahlenverschiebung.
class function THardcodedPathDetector.IsLocalTestHelperCall(
  const CallText: string): Boolean;
var
  Callee : string;
  D      : Integer;
begin
  Callee := CalleeOf(CallText);
  D := LastDelimiter('.', Callee);
  if D > 0 then Callee := Copy(Callee, D + 1, MaxInt);
  Result := Callee.StartsWith('test');
end;

class procedure THardcodedPathDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  AContext: TAnalyzeContext);
var
  AllNodes   : TList<TAstNode>;
  N          : TAstNode;
  Lst        : TStringList;
  S          : string;
  F          : TLeakFinding;
  Reported   : TDictionary<string, Boolean>;
  Display    : string;
  InTestUnit : Boolean;
begin
  Reported := nil;
  Lst      := nil;

  // Gate A, Haelfte 1 (SCA016-FP-Paket 2026-08-27): Ist das ueberhaupt eine
  // Test-Unit? EINMAL pro Datei, nicht pro Knoten - IsTestFixturePath laeuft
  // ueber 28 Muster und AnalyzeUnit sieht alle nkAssign/nkCall der Datei.
  // Stufe tplSecret ist die richtige: sie meint Test-/Spec-KONVENTIONEN
  // ('PathFunc.Test.pas', 'test.core.base.pas', Verzeichnis 'test'/'tests')
  // und laesst Demo-/Sample-Units bewusst aussen vor - dort ist ein
  // hardkodierter Pfad weiterhin ein echter Befund. tplFixtureDir waere
  // falsch: es prueft NUR Verzeichnisse, und 'PathFunc.Test.pas' liegt in
  // issrc\Components\, also in keinem Testverzeichnis.
  // Der ScanRoot verankert die Verzeichnis-Muster an der Scanwurzel (sonst
  // legte ein Produktionsrepo unter C:\Users\test\... das Gate flaechig um);
  // ohne Kontext (Direktaufruf/Tests) ist er '' = dokumentiertes
  // unverankertes Alt-Verhalten.
  InTestUnit := TDetectorUtils.IsTestFixturePath(FileName,
                  CtxScanRoot(AContext), tplSecret);
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

          // Gate A, Haelfte 2: lokaler 'Test*'-Vektorhelfer IN einer
          // Test-Unit. Begruendung und Korpus-Belege stehen bei
          // IsLocalTestHelperCall. Beide Bedingungen muessen gelten - der
          // Callee-Praefix allein wuerde in Produktionscode echte Funde
          // verschlucken, die Test-Unit allein alle Datei-Operationen des
          // Testcodes (SaveToFile/DeleteFile in einem Fixture-Setup bleibt
          // Fund). Wie das Assertions-Gate nur bei nkCall: die Zuweisung
          // 'FPath := ''C:\...''' bleibt auch in einer Test-Unit Fund.
          if InTestUnit and (Kind = nkCall)
             and IsLocalTestHelperCall(N.Name) then Continue;

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
