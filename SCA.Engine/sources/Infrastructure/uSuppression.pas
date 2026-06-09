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
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12, uFileTextCache, uDetectorUtils,
  uSuppressionTelemetry;

type
  TSuppressedKinds = set of TFindingKind;

  // Suppression-Marker: '// noinspection X' an einer Quell-Zeile, das auf
  // eine Target-Zeile (= naechste Code-Zeile danach) zielt. Wird vom
  // Filter konsumiert wenn dort ein Finding der passenden Kind-Sets liegt.
  TSuppressionMarker = record
    MarkerLine : Integer;        // Zeile mit dem '// noinspection ...'
    TargetLine : Integer;        // Zeile auf die der Marker zielt
    Kinds      : TSuppressedKinds;
    Consumed   : Boolean;        // True wenn der Marker mind. 1 Finding suppresst hat
  end;

  TSuppression = class
  public
    // Filtert unterdrueckte Befunde aus der Liste (in-place). Emittiert
    // zusaetzlich fkUnusedSuppression-Findings fuer Marker die KEIN
    // Finding suppress't haben - Hinweis fuer den User die Suppression
    // zu entfernen.
    class procedure ApplyToFindings(
      Findings: TObjectList<TLeakFinding>); static;
  private
    // Pruft eine Zeile mit String-/Kommentar-Kontext-Awareness auf
    // `// noinspection X`. State wird vom Caller zwischen Zeilen
    // mitgefuehrt (offene { ... } / (* ... *)-Bloecke). Schuetzt
    // gegen Marker-Smuggling via String-Literalen wie
    //   Log('// noinspection All // ' + Payload);
    // die heute (ohne ScanCodeLine) als aktiver Marker durchrutschen
    // wuerden.
    class function ParseMarkerLine(const Line: string;
      var State: TCommentScanState;
      out Kinds: TSuppressedKinds): Boolean; static;
    class function ParseCommentText(const CommentText: string;
      out Kinds: TSuppressedKinds): Boolean; static;
    class function KindFromName(const Name: string;
      out Kind: TFindingKind): Boolean; static;
    class function BuildMap(const FileName: string): TDictionary<Integer,
      TSuppressedKinds>; static;
    // Sammelt alle '// noinspection X'-Marker einer Datei. Wird komplementaer
    // zu BuildMap genutzt: BuildMap fuer den Filter-Lookup (O(1) Target->Kinds),
    // BuildMarkers fuer den Unused-Tracking-Output (Marker->Quell-Zeile).
    class procedure BuildMarkers(const FileName: string;
      Markers: TList<TSuppressionMarker>); static;
    // Phase 1 von ApplyToFindings: entfernt unterdrueckte Findings in-place
    // und markiert die zugehoerigen Marker als Consumed.
    class procedure RemoveSuppressedFindings(
      Findings: TObjectList<TLeakFinding>;
      FileMaps: TObjectDictionary<string, TDictionary<Integer,
        TSuppressedKinds>>;
      FileMarkers: TObjectDictionary<string,
        TList<TSuppressionMarker>>); static;
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
  out Kinds: TSuppressedKinds): Boolean;
// In: Text NACH dem '//' (ohne Whitespace-Stripping)
// Out: erkannte Kinds aus '// noinspection X[, Y, ...]'-Direktive
const
  TAG = 'noinspection';
var
  Trimmed   : string;
  KindStrs  : TArray<string>;
  K         : TFindingKind;
  KS        : string;
  HasAny    : Boolean;
begin
  Result := False;
  Kinds  := [];

  Trimmed := TrimLeft(CommentText);
  if not Trimmed.ToLower.StartsWith(TAG) then Exit;

  Trimmed := Trimmed.Substring(Length(TAG));
  // Optional ':' direkt nach 'noinspection' akzeptieren
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
  out Kinds: TSuppressedKinds): Boolean;
// Scant die Zeile mit String-/Block-Kommentar-State-Awareness und
// extrahiert ggf. den '// noinspection X'-Marker NUR aus echtem
// Zeilen-Kommentar (nicht aus Strings, nicht aus offenem (* ... *)).
// State wird vom Caller pro File mitgefuehrt.
var
  LineCommentCol : Integer;
  CommentText    : string;
begin
  Result := False;
  Kinds  := [];

  TDetectorUtils.ScanCodeLine(Line, State, LineCommentCol);
  if LineCommentCol <= 0 then Exit;        // kein //-Kommentar im Code-Anteil

  // Comment-Text = alles nach den '//' Zeichen (LineCommentCol ist 1-basiert,
  // zeigt auf das erste '/').
  if LineCommentCol + 1 > Length(Line) then Exit;
  CommentText := Copy(Line, LineCommentCol + 2, MaxInt);

  Result := ParseCommentText(CommentText, Kinds);
end;

class function TSuppression.BuildMap(const FileName: string):
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
    if Line <= 0 then Exit;
    if Map.TryGetValue(Line, Existing) then
      Map[Line] := Existing + NewKinds
    else
      Map.Add(Line, NewKinds);
  end;

var
  ScanState : TCommentScanState;
  Cached    : Boolean;
begin
  Result := TDictionary<Integer, TSuppressedKinds>.Create;
  if not FileExists(FileName) then Exit;

  // Perf: AcquireLines nutzt gFileTextCache - zweiter Aufruf (BuildMarkers
  // im selben Scan) wird zum Cache-Hit, kein doppeltes I/O.
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    ScanState.InBraceComment := False;
    ScanState.InParenComment := False;
    for i := 0 to Lines.Count - 1 do
    begin
      if not ParseMarkerLine(Lines[i], ScanState, Kinds) then Continue;
      // Wir emittieren Suppression-Eintraege fuer ZWEI moegliche Targets:
      //   * NextNonEmpty: erste folgende non-empty Zeile - kann auch ein
      //     Kommentar sein (Target eines TodoComment-Suppressors etc.).
      //   * NextCode:     erste folgende non-empty + non-comment Zeile -
      //     Target eines normalen Suppressors (// noinspection MemoryLeak
      //     gefolgt von ggf. dokumentierendem Kommentar gefolgt vom Code).
      // Beide werden gemappt damit Pfade wie
      // noinspection TodoComment
      //   // noinspection TodoComment\n// TODO: implementieren
      // genauso funktionieren wie
      //   // noinspection MemoryLeak\nlist := Create;
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
  Markers: TList<TSuppressionMarker>);
var
  Lines  : TStringList;
  Kinds  : TSuppressedKinds;
  i, j   : Integer;
  L      : string;
  M      : TSuppressionMarker;
  Cached : Boolean;
begin
  // Perf: AcquireLines liefert dieselbe TStringList wie BuildMap (gFile-
  // TextCache) wenn beide im selben Scan fuer dasselbe File aufgerufen
  // werden - spart das zweite I/O.
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    var ScanState: TCommentScanState;
    ScanState.InBraceComment := False;
    ScanState.InParenComment := False;
    for i := 0 to Lines.Count - 1 do
    begin
      if not ParseMarkerLine(Lines[i], ScanState, Kinds) then Continue;
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
  FileMarkers: TObjectDictionary<string, TList<TSuppressionMarker>>);
var
  i, j, Line : Integer;
  F          : TLeakFinding;
  Map        : TDictionary<Integer, TSuppressedKinds>;
  Markers    : TList<TSuppressionMarker>;
  M          : TSuppressionMarker;
  Suppressed : TSuppressedKinds;
begin
  // Rueckwaerts iterieren - sicher beim Loeschen.
  for i := Findings.Count - 1 downto 0 do
  begin
    F := Findings[i];
    if (F.FileName = '') or (F.Kind = fkFileReadError) then Continue;

    if not FileMaps.TryGetValue(F.FileName, Map) then
    begin
      Map := BuildMap(F.FileName);
      FileMaps.Add(F.FileName, Map);
    end;

    Line := StrToIntDef(F.LineNumber, 0);
    if Line <= 0 then Continue;

    if not (Map.TryGetValue(Line, Suppressed) and (F.Kind in Suppressed)) then
      Continue;

    // Marker-Liste fuer diese Datei aufbauen wenn noch nicht da - wird
    // gleich fuer das Consumed-Tagging gebraucht.
    if not FileMarkers.TryGetValue(F.FileName, Markers) then
    begin
      Markers := TList<TSuppressionMarker>.Create;
      BuildMarkers(F.FileName, Markers);
      FileMarkers.Add(F.FileName, Markers);
    end;
    // Marker als consumed markieren wenn TargetLine + Kind passen.
    // TList<T> erlaubt keinen direkten Index-Edit auf records via for-in,
    // daher Index-basierter Loop mit explizitem Schreibzugriff.
    var ConsumedMarkerLine := 0;
    for j := 0 to Markers.Count - 1 do
    begin
      M := Markers[j];
      if (M.TargetLine = Line) and (F.Kind in M.Kinds) then
      begin
        M.Consumed := True;
        Markers[j] := M;
        if ConsumedMarkerLine = 0 then
          ConsumedMarkerLine := M.MarkerLine;
      end;
    end;
    // C.5 Telemetrie: pro suppressed Finding eine CSV-Zeile sammeln
    // (wenn aktiviert via --telemetry-csv). Niedriger Overhead durch
    // nil-check.
    if Assigned(gSuppressionTelemetry) then
      gSuppressionTelemetry.Append(KindName(F.Kind), F.FileName,
        Line, ConsumedMarkerLine);
    Findings.Delete(i);
  end;
end;

class procedure TSuppression.EmitUnusedSuppressionFindings(
  Findings: TObjectList<TLeakFinding>;
  FileMarkers: TObjectDictionary<string, TList<TSuppressionMarker>>);
// EIN Finding pro Marker (nicht pro nicht-getroffenes Kind im Set) -
// sonst explodiert die Liste wenn ein Marker mehrere Kinds suppresst
// und nur eines davon greift.
var
  M          : TSuppressionMarker;
  NewFinding : TLeakFinding;
begin
  for var Pair in FileMarkers do
    for M in Pair.Value do
      if not M.Consumed then
      begin
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
  Findings: TObjectList<TLeakFinding>);
var
  FileMaps    : TObjectDictionary<string, TDictionary<Integer, TSuppressedKinds>>;
  FileMarkers : TObjectDictionary<string, TList<TSuppressionMarker>>;
begin
  if (Findings = nil) or (Findings.Count = 0) then Exit;

  FileMaps    := TObjectDictionary<string, TDictionary<Integer, TSuppressedKinds>>.Create([doOwnsValues]);
  FileMarkers := TObjectDictionary<string, TList<TSuppressionMarker>>.Create([doOwnsValues]);
  try
    RemoveSuppressedFindings(Findings, FileMaps, FileMarkers);
    EmitUnusedSuppressionFindings(Findings, FileMarkers);
  finally
    FileMarkers.Free;
    FileMaps.Free;
  end;
end;

end.
