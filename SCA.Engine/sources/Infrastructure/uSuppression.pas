unit uSuppression;

// Filter fuer 'noinspection'-Kommentare im Quelltext.
//
// Erlaubt Unterdruecken einzelner Befunde direkt im Code:
//
//   // noinspection NilDeref
//   obj.DoSomething;
//
//   // noinspection MemoryLeak, MissingFinally
//   list := TStringList.Create;
//
//   // noinspection All
//   // unterdrueckt alle Pruefungen fuer die naechste Code-Zeile
//
// Die Suppression gilt fuer die naechste nicht-leere, nicht-Kommentar-Zeile.
// Mehrere Kategorien koennen mit Komma oder Leerzeichen getrennt werden.
//
// Erkannte Kategorien (case-insensitive): jeder Eintrag in KIND_META
// (uSCAConsts.pas) plus 'All' / '*'. Die Liste wird ueber KindFromName-
// Reverse-Lookup aufgeloest - Single source of truth ist KIND_META,
// damit hier kein Drift mehr entsteht (frueher: statische Liste, hat
// dreimal Detektoren verpasst: TodoComment, EmptyMethod, DuplicateBlock).

interface

uses
  Winapi.Windows,   // OutputDebugString (Diagnose bei nicht lesbaren Marker-Hosts)
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12, uFileTextCache, uDetectorUtils,
  uSuppressionTelemetry;

type
  // 2026-07-05 (Audit_CodeReview #2): TSuppressionMarker + Kind-Set leben
  // jetzt in uSCAConsts - TAnalyzeContext traegt die per-Scan-Marker-
  // Collection und darf uSuppression nicht uses'en (Interface-Zyklus ueber
  // uDetectorUtils/P1-Strip-Cache). Aliase halten alle bestehenden
  // Konsumenten dieser Unit quelltext-stabil.
  TSuppressedKinds = uSCAConsts.TFindingKinds;
  TSuppressionMarker = uSCAConsts.TSuppressionMarker;

  TSuppression = class
  public
    // Filtert unterdrueckte Befunde aus der Liste (in-place). Emittiert
    // zusaetzlich fkUnusedSuppression-Findings fuer Marker die KEIN
    // Finding suppress't haben - Hinweis fuer den User die Suppression
    // zu entfernen.
    //
    // APreMarkers (optional, Audit #2a 2026-07-05): die zur SCAN-Zeit
    // eingesammelte Marker-Collection (ParseLeaks-Main-Loop via
    // CollectMarkersForScan; Key = Marker-HOST-Pfad). Wenn gesetzt:
    //   * wird als FileMarkers-Quelle benutzt (Caller behaelt Ownership -
    //     wird hier NICHT freigegeben), kein lazy BuildMarkers mehr;
    //   * laeuft die Unused-Emission auch bei Findings.Count=0 - stale
    //     Marker in befund-freien Dateien werden damit endlich gemeldet.
    // nil = Legacy-Verhalten (lazy Marker-Build im Match-Zweig).
    class procedure ApplyToFindings(
      Findings: TObjectList<TLeakFinding>;
      APreMarkers: TObjectDictionary<string,
        TList<TSuppressionMarker>> = nil); static;

    // Scan-Zeit-Collection (Audit #2a, 2026-07-05): sammelt die Marker
    // der gerade gescannten Datei in das per-Scan-Dictionary (Key =
    // Marker-HOST-Pfad, ResolveMarkerHostFile). Gedacht fuer den
    // ParseLeaks-Main-Loop, solange der Dateitext noch heiss im
    // gFileTextCache liegt. Perf-Guard: billiger case-insensitiver
    // 'noinspection'-Substring-Check pro Zeile (allokationsfrei) BEVOR
    // BuildMarkers laeuft. Dateien ohne Marker landen NICHT im Dictionary.
    class procedure CollectMarkersForScan(const FileName: string;
      AMarkers: TObjectDictionary<string,
        TList<TSuppressionMarker>>); static;
  private
    // Allokationsfreier case-insensitiver Substring-Check auf
    // 'noinspection' (ASCII-Folding reicht - der Tag selbst ist ASCII).
    // Bewusst OHNE Kommentar-Kontext: nur billiger Vorfilter, die
    // praezise Auswertung macht BuildMarkers/ParseMarkerLine.
    // Hinweis (dokumentierte Design-Abweichung): der von EnsureTokenSet
    // (P4, uStaticAnalyzer2) gelowerte Ganztext ist NICHT wiederverwendbar
    // - er ist ein Lokal der nested Function und beim Collect-Zeitpunkt
    // laengst freigegeben; ihn zu persistieren hiesse eine Ganztext-Kopie
    // pro Datei ueber RunAllDetectors hinaus zu halten. Der Zeilen-Scan
    // hier ist billiger als Pos(LowerCase(...)) und kopiert nichts.
    class function ContainsNoInspectionToken(
      const Line: string): Boolean; static;
    // Pruft eine Zeile mit String-/Kommentar-Kontext-Awareness auf
    // `// noinspection X`. State wird vom Caller zwischen Zeilen
    // mitgefuehrt (offene { ... } / (* ... *)-Bloecke). Schuetzt
    // gegen Marker-Smuggling via String-Literalen wie
    //   Log('// noinspection All // ' + Payload);
    // die heute (ohne ScanCodeLine) als aktiver Marker durchrutschen
    // wuerden.
    class function ParseMarkerLine(const Line: string;
      var State: TCommentScanState;
      out Kinds: TSuppressedKinds;
      out FileWide: Boolean): Boolean; static;
    class function ParseCommentText(const CommentText: string;
      out Kinds: TSuppressedKinds;
      out FileWide: Boolean): Boolean; static;
    class function KindFromName(const Name: string;
      out Kind: TFindingKind): Boolean; static;
    // AFailedFiles (optional): sammelt Marker-Host-Dateien, die trotz
    // Existenz nicht lesbar waren (AcquireLines=nil) - ApplyToFindings
    // emittiert dafuer fkFileReadError-Diagnose-Findings statt still
    // fail-open zu laufen (Audit #10b).
    class function BuildMap(const FileName: string;
      AFailedFiles: TStrings = nil): TDictionary<Integer,
      TSuppressedKinds>; static;
    // Sammelt alle '// noinspection X'-Marker einer Datei. Wird komplementaer
    // zu BuildMap genutzt: BuildMap fuer den Filter-Lookup (O(1) Target->Kinds),
    // BuildMarkers fuer den Unused-Tracking-Output (Marker->Quell-Zeile).
    class procedure BuildMarkers(const FileName: string;
      Markers: TList<TSuppressionMarker>;
      AFailedFiles: TStrings = nil); static;
    // Traegt einen nicht lesbaren Marker-Host dedupliziert in AFailedFiles
    // ein + OutputDebugString (Dev-Diagnose ohne UI/CLI-Abhaengigkeit).
    class procedure NoteReadFailure(const AHostFile: string;
      AFailedFiles: TStrings); static;
    // Phase 1 von ApplyToFindings: entfernt unterdrueckte Findings in-place
    // und markiert die zugehoerigen Marker als Consumed. FileMarkers ist
    // seit 2026-07-05 IMMER nach Marker-HOST-Pfad gekeyt (Audit #2b).
    // APreBuilt=True: FileMarkers kam fertig aus der Scan-Zeit-Collection -
    // KEIN lazy BuildMarkers, nur Lookup via ResolveMarkerHostFile.
    class procedure RemoveSuppressedFindings(
      Findings: TObjectList<TLeakFinding>;
      FileMaps: TObjectDictionary<string, TDictionary<Integer,
        TSuppressedKinds>>;
      FileMarkers: TObjectDictionary<string,
        TList<TSuppressionMarker>>;
      APreBuilt: Boolean;
      AFailedFiles: TStrings); static;
    // Phase 2: emittiert fkUnusedSuppression-Findings fuer alle Marker
    // die nichts unterdrueckt haben.
    class procedure EmitUnusedSuppressionFindings(
      Findings: TObjectList<TLeakFinding>;
      FileMarkers: TObjectDictionary<string,
        TList<TSuppressionMarker>>); static;
  end;

const
  // Wird im Finding-Detail der fkUnusedSuppression-Befunde verwendet.
  // Bewusst nicht ueber uLocalization._() - dieser Pfad laeuft im
  // CLI-Mode wo VCL/Localization nicht initialisiert sein muss.
  MSG_UNUSED_SUPPRESSION =
    '// noinspection-Marker suppresst nichts - Detektor wurde ' +
    'verbessert oder Target war falsch. Marker entfernen oder ' +
    'Target-Kind pruefen.';

  // Diagnose-Befund (Audit_CodeReview #10b, 2026-07-05): der Marker-Host
  // einer Datei konnte nicht gelesen werden (Encoding-/IO-Fehler, Lock).
  // Frueher lief das STILL fail-open - alle Suppressions der Datei blieben
  // unbemerkt wirkungslos und unterdrueckte Findings tauchten z.B. im
  // CI-Baseline-Vergleich ploetzlich als "neu" auf.
  MSG_SUPPRESSION_READ_ERROR =
    'Suppression-Marker nicht auswertbar (Datei nicht lesbar) - ' +
    'Findings dieser Datei bleiben ungefiltert.';

  // Kinds die per '// noinspection All' NICHT pauschal unterdrueckt
  // werden duerfen. Wer diese Befunde wirklich unterdruecken will,
  // muss sie explizit nennen ('// noinspection SQLInjection'). Schuetzt
  // gegen Insider/PR-Supply-Chain-Bypass mit einem einzigen All-Marker.
  // Auch fkUnusedSuppression ist drin, damit das eigene Tracking nicht
  // durch All vom Radar fliegt.
  CRITICAL_KINDS_NOT_SUPPRESSIBLE_BY_ALL: TSuppressedKinds = [
    fkHardcodedSecret,
    fkSQLInjection,
    fkCommandInjection,
    fkDfmHardcodedDbCreds,
    fkDfmSqlFromUserInput,
    fkInsecureCryptoAlgorithm,
    fkUnusedSuppression
  ];

implementation

// noinspection-file BeginEndRequired, ConsecutiveSection, CyclomaticComplexity, GroupedDeclaration, IfElseBegin, RedundantJump, TodoComment, TooLongLine, UnsortedUses, UnusedLocalVar, UnusedParameter, UnusedPublicMember
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

class function TSuppression.KindFromName(const Name: string;
  out Kind: TFindingKind): Boolean;
// Delegiert an KIND_META-Reverse-Lookup in uSCAConsts (single source
// of truth). Vorher: 21-Eintrag if-elseif-Kette die zweimal in der
// Vergangenheit unsynchron geworden ist (zuletzt: TodoComment,
// EmptyMethod, DuplicateBlock fehlten).
begin
  Result := uSCAConsts.KindFromName(Name, Kind);
end;

class function TSuppression.ParseCommentText(const CommentText: string;
  out Kinds: TSuppressedKinds; out FileWide: Boolean): Boolean;
// In: Text NACH dem '//' (ohne Whitespace-Stripping)
// Out: erkannte Kinds aus '// noinspection X[, Y, ...]'-Direktive ODER
//      file-weite Variante '// noinspection-file X[, Y, ...]' (FileWide=True).
//
// File-Wide-Marker: ein einziger Marker im File reicht, statt 50+
// Per-Line-Marker. Praktisch fuer hoch-frequente Stil-Warnings (z.B.
// SCA110 String-Concat im Parser, SCA002 Empty-Except im IDE-Plugin).
const
  TAG          = 'noinspection';
  TAG_FILEWIDE = 'noinspection-file';
var
  Trimmed   : string;
  KindStrs  : TArray<string>;
  K         : TFindingKind;
  KS        : string;
  HasAny    : Boolean;
begin
  Result   := False;
  Kinds    := [];
  FileWide := False;

  Trimmed := TrimLeft(CommentText);
  // File-Wide-Variante zuerst pruefen (laengeres Match) - sonst wuerde
  // 'noinspection-file' als 'noinspection' + Rest interpretiert.
  if Trimmed.ToLower.StartsWith(TAG_FILEWIDE) then
  begin
    FileWide := True;
    Trimmed := Trimmed.Substring(Length(TAG_FILEWIDE));
  end
  else if Trimmed.ToLower.StartsWith(TAG) then
  begin
    Trimmed := Trimmed.Substring(Length(TAG));
  end
  else
    Exit;

  // Optional ':' direkt nach 'noinspection[-file]' akzeptieren
  if Trimmed.StartsWith(':') then
    Trimmed := Trimmed.Substring(1);
  Trimmed := Trim(Trimmed);

  // 'All' = alle Kategorien AUSSER Security-Critical-Kinds + dem
  // fkUnusedSuppression-Safety-Net. Wer Hardcoded-Secret/SQL-Injection/
  // Command-Injection unterdruecken will, MUSS sie explizit nennen -
  // sonst koennte ein einziger 'noinspection All'-Marker einen Backdoor
  // verstecken. fkUnusedSuppression muss auch durch (sonst killt All
  // sein eigenes Tracking).
  if SameText(Trimmed, 'all') or (Trimmed = '*') then
  begin
    for K := Low(TFindingKind) to High(TFindingKind) do
      if not (K in CRITICAL_KINDS_NOT_SUPPRESSIBLE_BY_ALL) then
        Include(Kinds, K);
    Result := True;
    Exit;
  end;

  KindStrs := Trimmed.Split([',', ';', ' ', #9]);
  HasAny := False;
  for KS in KindStrs do
  begin
    if Trim(KS) = '' then Continue;
    if KindFromName(KS, K) then
    begin
      Include(Kinds, K);
      HasAny := True;
    end;
  end;
  Result := HasAny;
end;

class function TSuppression.ParseMarkerLine(const Line: string;
  var State: TCommentScanState;
  out Kinds: TSuppressedKinds; out FileWide: Boolean): Boolean;
// Scant die Zeile mit String-/Block-Kommentar-State-Awareness und
// extrahiert ggf. den '// noinspection X'-Marker NUR aus echtem
// Zeilen-Kommentar (nicht aus Strings, nicht aus offenem (* ... *)).
// State wird vom Caller pro File mitgefuehrt.
var
  LineCommentCol : Integer;
  CommentText    : string;
begin
  Result   := False;
  Kinds    := [];
  FileWide := False;

  TDetectorUtils.ScanCodeLine(Line, State, LineCommentCol);
  if LineCommentCol <= 0 then Exit;        // kein //-Kommentar im Code-Anteil

  // Comment-Text = alles nach den '//' Zeichen (LineCommentCol ist 1-basiert,
  // zeigt auf das erste '/').
  if LineCommentCol + 1 > Length(Line) then Exit;
  CommentText := Copy(Line, LineCommentCol + 2, MaxInt);

  Result := ParseCommentText(CommentText, Kinds, FileWide);
end;

// Liefert fuer eine .dfm-Datei die zugehoerige .pas im selben Verzeichnis -
// fuer .pas/andere Files unveraendert zurueck. DFM-Findings (Form-Layouts)
// koennen keinen //-Kommentar-Marker im DFM tragen, akzeptieren aber den
// Marker in der assoziierten .pas-Datei (die ohnehin alle UI-Form-Patterns
// als idiomatisch markiert hat).
function ResolveMarkerHostFile(const FileName: string): string;
begin
  Result := FileName;
  if SameText(ExtractFileExt(FileName), '.dfm') then
  begin
    var PasFile := ChangeFileExt(FileName, '.pas');
    if FileExists(PasFile) then Result := PasFile;
  end;
end;

class procedure TSuppression.NoteReadFailure(const AHostFile: string;
  AFailedFiles: TStrings);
begin
  OutputDebugString(PChar('[SCA] Suppression: Marker-Host nicht lesbar: ' +
    AHostFile));
  if (AFailedFiles <> nil) and (AFailedFiles.IndexOf(AHostFile) < 0) then
    AFailedFiles.Add(AHostFile);
end;

class function TSuppression.ContainsNoInspectionToken(
  const Line: string): Boolean;
// Case-insensitiver 'noinspection'-Substring-Scan ohne Allokation (kein
// LowerCase/Copy der Zeile). Semantik wie Pos('noinspection',
// LowerCase(Line)) > 0 fuer ASCII - Nicht-ASCII-Zeichen matchen den
// ASCII-Tag ohnehin nie. Deckt 'noinspection-file' mit ab (Prefix).
const
  TOKEN = 'noinspection';                    // lowercase, 12 Zeichen
var
  i, j, MaxStart : Integer;
  C              : Char;
begin
  Result := False;
  MaxStart := Length(Line) - Length(TOKEN) + 1;
  for i := 1 to MaxStart do
  begin
    C := Line[i];
    if (C <> 'n') and (C <> 'N') then Continue;
    j := 1;
    while j < Length(TOKEN) do
    begin
      C := Line[i + j];
      if (C >= 'A') and (C <= 'Z') then
        C := Char(Ord(C) + 32);              // ASCII-Lower ohne Alloc
      if C <> TOKEN[j + 1] then Break;
      Inc(j);
    end;
    if j = Length(TOKEN) then Exit(True);
  end;
end;

class procedure TSuppression.CollectMarkersForScan(const FileName: string;
  AMarkers: TObjectDictionary<string, TList<TSuppressionMarker>>);
// Scan-Zeit-Collection (Audit #2a, 2026-07-05) - siehe Interface-Kommentar.
// Wird im ParseLeaks-Main-Loop pro erfolgreich gescannter Datei gerufen,
// SOLANGE der Dateitext noch im gFileTextCache liegt (AcquireLines =
// Cache-Hit, kein zusaetzliches I/O). AFailedFiles bewusst nil: ein hier
// nicht lesbarer Host wird zur Apply-Zeit von BuildMap (#10b) gemeldet,
// sofern die Datei Findings hat - exakt das Legacy-Diagnose-Verhalten.
var
  HostFile : string;
  Lines    : TStringList;
  Cached   : Boolean;
  HasToken : Boolean;
  i        : Integer;
  List     : TList<TSuppressionMarker>;
begin
  if AMarkers = nil then Exit;
  HostFile := ResolveMarkerHostFile(FileName);
  if AMarkers.ContainsKey(HostFile) then Exit;   // schon eingesammelt
  Lines := AcquireLines(HostFile, Cached);
  if Lines = nil then Exit;                      // unlesbar -> s. Kommentar oben
  try
    // Perf-Guard: erst der billige Substring-Check, BuildMarkers (mit
    // ScanCodeLine-State-Maschine) nur wenn der Tag ueberhaupt vorkommt.
    HasToken := False;
    for i := 0 to Lines.Count - 1 do
      if ContainsNoInspectionToken(Lines[i]) then
      begin
        HasToken := True;
        Break;
      end;
  finally
    ReleaseLines(Lines, Cached);
  end;
  if not HasToken then Exit;                     // kein Eintrag ohne Marker

  List := TList<TSuppressionMarker>.Create;
  BuildMarkers(HostFile, List, nil);             // Cache-Hit (Text noch heiss)
  if List.Count = 0 then
    List.Free                                    // Token war Prosa/String-Payload
  else
    AMarkers.Add(HostFile, List);                // Ownership -> Dictionary
end;

class function TSuppression.BuildMap(const FileName: string;
  AFailedFiles: TStrings):
  TDictionary<Integer, TSuppressedKinds>;
var
  Lines      : TStringList;
  Kinds      : TSuppressedKinds;
  i, j       : Integer;
  L          : string;

  // Existing Suppressions auf der Ziel-Zeile bewahren UND neue Kinds dazu
  // mergen. Vermeidet dass mehrere `// noinspection X`-Marker, die
  // gestapelt aufs selbe Code-Statement zielen, sich gegenseitig
  // ueberschreiben.
  procedure MergeKindsAt(Map: TDictionary<Integer, TSuppressedKinds>;
                         Line: Integer; const NewKinds: TSuppressedKinds);
  var
    Existing: TSuppressedKinds;
  begin
    // Line < 0 = ungueltig; Line = 0 ist OK = File-Wide-Marker-Slot
    // (RemoveSuppressedFindings prueft Map[0] als File-weite Vorgabe).
    if Line < 0 then Exit;
    if Map.TryGetValue(Line, Existing) then
      Map[Line] := Existing + NewKinds
    else
      Map.Add(Line, NewKinds);
  end;

var
  ScanState : TCommentScanState;
  Cached    : Boolean;
  FileWide  : Boolean;
  HostFile  : string;
begin
  Result := TDictionary<Integer, TSuppressedKinds>.Create;
  HostFile := ResolveMarkerHostFile(FileName);
  if not FileExists(HostFile) then Exit;

  // Perf: AcquireLines nutzt gFileTextCache - zweiter Aufruf (BuildMarkers
  // im selben Scan) wird zum Cache-Hit, kein doppeltes I/O.
  Lines := AcquireLines(HostFile, Cached);
  if Lines = nil then
  begin
    // Datei existiert, ist aber nicht lesbar (Encoding/IO/Lock) - NICHT
    // still fail-open (Audit #10b): Diagnose sammeln, leere Map liefern.
    NoteReadFailure(HostFile, AFailedFiles);
    Exit;
  end;
  try
    ScanState.InBraceComment := False;
    ScanState.InParenComment := False;
    for i := 0 to Lines.Count - 1 do
    begin
      if not ParseMarkerLine(Lines[i], ScanState, Kinds, FileWide) then Continue;
      // File-Wide-Marker: in Line 0 ablegen - RemoveSuppressedFindings
      // prueft Line 0 als generelle File-Vorgabe ZUSAETZLICH zum
      // line-spezifischen Match.
      if FileWide then
      begin
        MergeKindsAt(Result, 0, Kinds);
        Continue;
      end;
      // Wir emittieren Suppression-Eintraege fuer ZWEI moegliche Targets:
      //   * NextNonEmpty: erste folgende non-empty Zeile - kann auch ein
      //     Kommentar sein (Target eines TodoComment-Suppressors etc.).
      //   * NextCode:     erste folgende non-empty + non-comment Zeile -
      //     Target eines normalen Suppressors (Form `// noinspection
      //     MemoryLeak` gefolgt von ggf. dokumentierendem Kommentar gefolgt
      //     vom Code).
      // Beide werden gemappt damit Pfade wie
      // `// noinspection TodoComment\n// TODO: implementieren`
      // genauso funktionieren wie `// noinspection MemoryLeak\nlist := Create`.
      // Wenn weder NonEmpty noch Code folgt (Marker am EOF) - keine
      // Map-Eintraege.
      var NextNonEmpty: Integer := -1;
      var NextCode    : Integer := -1;
      for j := i + 1 to Lines.Count - 1 do
      begin
        L := TrimLeft(Lines[j]);
        if L = '' then Continue;
        if NextNonEmpty < 0 then NextNonEmpty := j + 1;
        if not L.StartsWith('//') then
        begin
          NextCode := j + 1;
          Break;
        end;
      end;
      // UNION-Merge statt overwrite: bei gestapelten Markern
      //   // noinspection MemoryLeak
      //   // noinspection FormatMismatch
      //   list := Create;
      // zielen beide Marker auf die Code-Zeile. Mit AddOrSetValue wuerde
      // nur die zuletzt gefundene Kind-Set die Map-Entry behalten -
      // MemoryLeak-Suppression ginge verloren. Vereinen statt ersetzen.
      MergeKindsAt(Result, NextNonEmpty, Kinds);
      if NextCode <> NextNonEmpty then
        MergeKindsAt(Result, NextCode, Kinds);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

class procedure TSuppression.BuildMarkers(const FileName: string;
  Markers: TList<TSuppressionMarker>;
  AFailedFiles: TStrings);
var
  Lines    : TStringList;
  Kinds    : TSuppressedKinds;
  i, j     : Integer;
  L        : string;
  M        : TSuppressionMarker;
  Cached   : Boolean;
  HostFile : string;
begin
  // Perf: AcquireLines liefert dieselbe TStringList wie BuildMap (gFile-
  // TextCache) wenn beide im selben Scan fuer dasselbe File aufgerufen
  // werden - spart das zweite I/O.
  // .dfm-Findings nutzen die .pas im selben Verzeichnis als Marker-Host.
  HostFile := ResolveMarkerHostFile(FileName);
  Lines := AcquireLines(HostFile, Cached);
  if Lines = nil then
  begin
    // Analog BuildMap (Audit #10b): existierende, aber nicht lesbare
    // Hosts als Diagnose melden statt still keine Marker zu liefern.
    if FileExists(HostFile) then
      NoteReadFailure(HostFile, AFailedFiles);
    Exit;
  end;
  try
    var ScanState: TCommentScanState;
    var FileWide: Boolean;
    ScanState.InBraceComment := False;
    ScanState.InParenComment := False;
    for i := 0 to Lines.Count - 1 do
    begin
      if not ParseMarkerLine(Lines[i], ScanState, Kinds, FileWide) then Continue;
      // File-Wide-Marker: TargetLine = 0 (Sonderwert fuer file-weit).
      // RemoveSuppressedFindings tagt sie beim File-Wide-Match als Consumed.
      if FileWide then
      begin
        M.MarkerLine := i + 1;
        M.TargetLine := 0;
        M.Kinds      := Kinds;
        M.Consumed   := False;
        Markers.Add(M);
        Continue;
      end;
      // TargetLine = naechste non-empty + non-comment Zeile (= Code).
      // Wir tracken NUR den Code-Target weil das der harte Suppress-Punkt
      // ist; Doc-Comment-Targets sind ambig (z.B. TodoComment-Suppression
      // auf den TODO-Kommentar selbst) und fuer Unused-Tracking irrelevant.
      var TargetLine: Integer := -1;
      for j := i + 1 to Lines.Count - 1 do
      begin
        L := TrimLeft(Lines[j]);
        if L = '' then Continue;
        if not L.StartsWith('//') then
        begin
          TargetLine := j + 1;
          Break;
        end;
      end;
      if TargetLine <= 0 then Continue;        // Marker am EOF - kein Target
      M.MarkerLine := i + 1;
      M.TargetLine := TargetLine;
      M.Kinds      := Kinds;
      M.Consumed   := False;
      Markers.Add(M);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

class procedure TSuppression.RemoveSuppressedFindings(
  Findings: TObjectList<TLeakFinding>;
  FileMaps: TObjectDictionary<string, TDictionary<Integer, TSuppressedKinds>>;
  FileMarkers: TObjectDictionary<string, TList<TSuppressionMarker>>;
  APreBuilt: Boolean;
  AFailedFiles: TStrings);
var
  i, j, Line     : Integer;
  F              : TLeakFinding;
  Map            : TDictionary<Integer, TSuppressedKinds>;
  Markers        : TList<TSuppressionMarker>;
  M              : TSuppressionMarker;
  Suppressed     : TSuppressedKinds;
  FileWideKinds  : TSuppressedKinds;
  Match          : Boolean;
  TargetForMark  : Integer;
  HostFile       : string;
  Drop           : TArray<Boolean>;
  Dropped        : Integer;
  r, w           : Integer;
  OldOwns        : Boolean;
begin
  // Perf (2026-07-05): P5-postfilter-compact - die Entscheidungs-Schleife
  // laeuft unveraendert rueckwaerts (Consumed-Tagging und Telemetrie-
  // Reihenfolge bleiben damit exakt wie vorher), aber statt
  // Findings.Delete(i) (memmoved den Tail, quadratisch bei ~700k Findings)
  // wird nur Drop[i] markiert und danach single-pass kompaktiert.
  SetLength(Drop, Findings.Count); // dyn array -> alles False
  Dropped := 0;
  for i := Findings.Count - 1 downto 0 do
  begin
    F := Findings[i];
    if (F.FileName = '') or (F.Kind = fkFileReadError) then Continue;

    if not FileMaps.TryGetValue(F.FileName, Map) then
    begin
      Map := BuildMap(F.FileName, AFailedFiles);
      FileMaps.Add(F.FileName, Map);
    end;

    Line := StrToIntDef(F.LineNumber, 0);

    // Match-Strategie:
    //   1. File-Wide-Marker (Map[0]) wirkt unabhaengig von Line-Wert.
    //   2. Per-Line-Marker (Map[Line]) - nur wenn Line > 0.
    // TargetForMark fuehrt zur passenden Marker-TargetLine im Consumed-
    // Tagging: 0 = file-wide, sonst Line.
    Match := False;
    TargetForMark := 0;
    if Map.TryGetValue(0, FileWideKinds) and (F.Kind in FileWideKinds) then
    begin
      Match := True;
      TargetForMark := 0;
    end
    else if (Line > 0) and Map.TryGetValue(Line, Suppressed)
            and (F.Kind in Suppressed) then
    begin
      Match := True;
      TargetForMark := Line;
    end;
    if not Match then Continue;

    // Marker-Liste fuer das Consumed-Tagging. Key ist seit 2026-07-05
    // IMMER der Marker-HOST-Pfad (Audit #2b: .dfm-Findings -> .pas), damit
    // .dfm- und .pas-Findings DIESELBE Liste taggen und die Unused-
    // Emission auf die Host-Datei zeigt (vorher: zwei getrennte Listen-
    // Kopien unter .dfm- und .pas-Key, Emission auf die .dfm).
    HostFile := ResolveMarkerHostFile(F.FileName);
    if not FileMarkers.TryGetValue(HostFile, Markers) then
    begin
      if APreBuilt then
        // Scan-Zeit-Collection kennt diese Datei nicht (Host lag nicht in
        // der Scan-Liste). Defensiv: kein Tagging, aber auch keine Unused-
        // Emission fuer die Datei (nicht im Dictionary) -> kein Rauschen.
        Markers := nil
      else
      begin
        Markers := TList<TSuppressionMarker>.Create;
        BuildMarkers(HostFile, Markers, AFailedFiles);
        FileMarkers.Add(HostFile, Markers);
      end;
    end;
    // Consumed-Tagging (Audit #2c, 2026-07-05): ALLE Marker taggen, die
    // das Finding abdecken - file-wide (TargetLine=0) UND per-line.
    // Vorher exklusiv nur die Match-Ebene (TargetForMark): deckte ein
    // file-wide-Marker das Finding ab, blieb ein ebenfalls zutreffender
    // Per-Line-Marker Consumed=False und wurde faelschlich als unused
    // gemeldet. Das ENTFERNEN des Findings (Match oben) ist unveraendert -
    // einmal ist einmal.
    var ConsumedMarkerLine := 0;
    if Markers <> nil then
      for j := 0 to Markers.Count - 1 do
      begin
        M := Markers[j];
        if (F.Kind in M.Kinds) and
           ((M.TargetLine = 0) or
            ((Line > 0) and (M.TargetLine = Line))) then
        begin
          M.Consumed := True;
          Markers[j] := M;
          // Telemetrie-Zeile wie bisher: erster Marker der PRIMAEREN
          // Match-Ebene (TargetForMark), nicht irgendein Co-Marker.
          if (ConsumedMarkerLine = 0) and (M.TargetLine = TargetForMark) then
            ConsumedMarkerLine := M.MarkerLine;
        end;
      end;
    // C.5 Telemetrie: pro suppressed Finding eine CSV-Zeile sammeln
    // (wenn aktiviert via --telemetry-csv). Niedriger Overhead durch
    // nil-check.
    if Assigned(gSuppressionTelemetry) then
      gSuppressionTelemetry.Append(KindName(F.Kind), F.FileName,
        Line, ConsumedMarkerLine);
    Drop[i] := True;
    Inc(Dropped);
  end;

  if Dropped = 0 then Exit; // nichts zu entfernen -> Kompaktierung sparen

  // Kompaktierung: behaltene Findings nach vorne kopieren, gedroppte
  // manuell freigeben, Count trimmen. OwnsObjects temporaer aus, sonst
  // wuerde Items[w] := Items[r] das ueberschriebene Objekt freigeben
  // (Notify). Reihenfolge der verbleibenden Findings bleibt exakt.
  w := 0;
  OldOwns := Findings.OwnsObjects;
  Findings.OwnsObjects := False;
  try
    for r := 0 to Findings.Count - 1 do
      if Drop[r] then
      begin
        if OldOwns then Findings[r].Free; // wie Delete bei owning-Liste
      end
      else
      begin
        if w <> r then Findings[w] := Findings[r];
        Inc(w);
      end;
    // Tail = nur noch Duplikat-Referenzen; OwnsObjects=False -> kein Free.
    Findings.Count := w;
  finally
    Findings.OwnsObjects := OldOwns;
  end;
end;

class procedure TSuppression.EmitUnusedSuppressionFindings(
  Findings: TObjectList<TLeakFinding>;
  FileMarkers: TObjectDictionary<string, TList<TSuppressionMarker>>);
// EIN Finding pro Marker (nicht pro nicht-getroffenes Kind im Set) -
// sonst explodiert die Liste wenn ein Marker mehrere Kinds suppresst
// und nur eines davon greift.
// FileName = Pair.Key = Marker-HOST-Pfad (Audit #2b, 2026-07-05): fuer
// .dfm-Findings ist das die .pas, aus der MarkerLine stammt - der Fund
// zeigt damit auf die richtige Datei+Zeile (vorher: .dfm-Datei mit
// .pas-Zeilennummer, Klick lief ins Leere). Gilt in beiden Modi, weil
// RemoveSuppressedFindings/CollectMarkersForScan host-gekeyt befuellen.
var
  M          : TSuppressionMarker;
  NewFinding : TLeakFinding;
  KindGate   : Boolean;
begin
  // Review-Fix (2026-07-05, Profil-Rauschen): die Emission laeuft NACH dem
  // Kind-Filter von RunAllDetectors - ohne eigenes Gate wuerden Profil-
  // Scans (bugs-only/security/...), in denen fkUnusedSuppression gar nicht
  // enthalten ist, seit der Scan-Zeit-Collection hunderte Stil-Marker-
  // Funde ausserhalb des angeforderten Profils melden (Self-Scan: ~230
  // file-wide-Marker-Dateien). Gate: Emission nur wenn das Profil
  // fkUnusedSuppression fuehrt ([] = kein Filter = alles), und pro Marker
  // nur, wenn er mindestens einen im Profil AKTIVEN Kind suppresst -
  // Marker deaktivierter Detektoren KOENNEN nichts konsumieren und sind
  // in diesem Profil keine Aussage wert.
  KindGate := DetectorEnabledKinds <> [];
  if KindGate and not (fkUnusedSuppression in DetectorEnabledKinds) then
    Exit;
  for var Pair in FileMarkers do
    for M in Pair.Value do
      if not M.Consumed then
      begin
        if KindGate and (M.Kinds * DetectorEnabledKinds = []) then
          Continue;
        NewFinding := TLeakFinding.Create;
        NewFinding.FileName   := Pair.Key;
        NewFinding.MethodName := '';
        NewFinding.LineNumber := IntToStr(M.MarkerLine);
        NewFinding.MissingVar := MSG_UNUSED_SUPPRESSION;
        NewFinding.SetKind(fkUnusedSuppression);
        Findings.Add(NewFinding);
      end;
end;

class procedure TSuppression.ApplyToFindings(
  Findings: TObjectList<TLeakFinding>;
  APreMarkers: TObjectDictionary<string, TList<TSuppressionMarker>>);
var
  FileMaps    : TObjectDictionary<string, TDictionary<Integer, TSuppressedKinds>>;
  FileMarkers : TObjectDictionary<string, TList<TSuppressionMarker>>;
  FailedFiles : TStringList;
  i           : Integer;
  Ferr        : TLeakFinding;
begin
  if Findings = nil then Exit;
  // Count=0-Early-Exit NUR im Legacy-Modus (Audit #2a, 2026-07-05): mit
  // Scan-Zeit-Collection muss die Unused-Emission auch laufen, wenn die
  // Findings-Liste leer ist - sonst bleiben stale Marker in befund-freien
  // Dateien fuer immer unsichtbar.
  if (Findings.Count = 0) and (APreMarkers = nil) then Exit;

  FileMaps    := TObjectDictionary<string, TDictionary<Integer, TSuppressedKinds>>.Create([doOwnsValues]);
  // Mit PreMarkers wird das Caller-Dictionary direkt benutzt (Key =
  // Marker-HOST-Pfad) und NICHT freigegeben - Ownership bleibt beim
  // Caller (ParseLeaks). Ohne: Legacy-Container, lazy im Match-Zweig.
  if APreMarkers <> nil then
    FileMarkers := APreMarkers
  else
    FileMarkers := TObjectDictionary<string, TList<TSuppressionMarker>>.Create([doOwnsValues]);
  FailedFiles := TStringList.Create;
  try
    FailedFiles.CaseSensitive := False;   // Windows-Pfade
    RemoveSuppressedFindings(Findings, FileMaps, FileMarkers,
      APreMarkers <> nil, FailedFiles);
    // Iteriert ALLE Dictionary-Eintraege - im PreMarkers-Modus also auch
    // Dateien, deren Findings alle unmatched blieben oder die gar keine
    // Findings hatten (Fix Audit #2a).
    EmitUnusedSuppressionFindings(Findings, FileMarkers);

    // Audit #10b (2026-07-05): nicht lesbare Marker-Hosts als Diagnose-
    // Finding sichtbar machen (fkFileReadError laeuft an ConfidenceFilter
    // und Baseline vorbei) - vorher stilles fail-open: Suppressions der
    // Datei wirkten nicht, ohne jede Spur.
    for i := 0 to FailedFiles.Count - 1 do
    begin
      Ferr            := TLeakFinding.Create;
      Ferr.FileName   := FailedFiles[i];
      Ferr.MethodName := '';
      Ferr.LineNumber := '0';
      Ferr.MissingVar := MSG_SUPPRESSION_READ_ERROR;
      Ferr.SetKind(fkFileReadError);
      Findings.Add(Ferr);
    end;
  finally
    FailedFiles.Free;
    if APreMarkers = nil then
      FileMarkers.Free;   // nur den selbst erzeugten Legacy-Container
    FileMaps.Free;
  end;
end;

end.
