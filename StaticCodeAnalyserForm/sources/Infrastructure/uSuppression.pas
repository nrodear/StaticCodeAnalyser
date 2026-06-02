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
  uSCAConsts, uMethodd12;

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
    class function ParseComment(const Line: string;
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
  end;

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

class function TSuppression.ParseComment(const Line: string;
  out Kinds: TSuppressedKinds): Boolean;
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

  Trimmed := TrimLeft(Line);
  if not Trimmed.StartsWith('//') then Exit;
  Trimmed := TrimLeft(Trimmed.Substring(2));
  if not Trimmed.ToLower.StartsWith(TAG) then Exit;

  Trimmed := Trimmed.Substring(Length(TAG));
  // Optional ':' direkt nach 'noinspection' akzeptieren
  if Trimmed.StartsWith(':') then
    Trimmed := Trimmed.Substring(1);
  Trimmed := Trim(Trimmed);

  // 'All' = alle Kategorien
  if SameText(Trimmed, 'all') or (Trimmed = '*') then
  begin
    for K := Low(TFindingKind) to High(TFindingKind) do
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

begin
  Result := TDictionary<Integer, TSuppressedKinds>.Create;
  if not FileExists(FileName) then Exit;

  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(FileName);
    except
      try Lines.LoadFromFile(FileName, TEncoding.UTF8);
      except
        try Lines.LoadFromFile(FileName, TEncoding.Unicode);
        except
          Exit; // unleserlich – keine Suppressions
        end;
      end;
    end;

    for i := 0 to Lines.Count - 1 do
    begin
      if not ParseComment(Lines[i], Kinds) then Continue;
      // Wir emittieren Suppression-Eintraege fuer ZWEI moegliche Targets:
      //   * NextNonEmpty: erste folgende non-empty Zeile - kann auch ein
      //     Kommentar sein (Target eines TodoComment-Suppressors etc.).
      //   * NextCode:     erste folgende non-empty + non-comment Zeile -
      //     Target eines normalen Suppressors (// noinspection MemoryLeak
      //     gefolgt von ggf. dokumentierendem Kommentar gefolgt vom Code).
      // Beide werden gemappt damit Pfade wie
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
    Lines.Free;
  end;
end;

class procedure TSuppression.BuildMarkers(const FileName: string;
  Markers: TList<TSuppressionMarker>);
var
  Lines : TStringList;
  Kinds : TSuppressedKinds;
  i, j  : Integer;
  L     : string;
  M     : TSuppressionMarker;
begin
  if not FileExists(FileName) then Exit;
  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(FileName);
    except
      try Lines.LoadFromFile(FileName, TEncoding.UTF8);
      except
        try Lines.LoadFromFile(FileName, TEncoding.Unicode);
        except Exit;
        end;
      end;
    end;
    for i := 0 to Lines.Count - 1 do
    begin
      if not ParseComment(Lines[i], Kinds) then Continue;
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
    Lines.Free;
  end;
end;

class procedure TSuppression.ApplyToFindings(
  Findings: TObjectList<TLeakFinding>);
var
  FileMaps     : TObjectDictionary<string, TDictionary<Integer, TSuppressedKinds>>;
  FileMarkers  : TObjectDictionary<string, TList<TSuppressionMarker>>;
  i, j, Line   : Integer;
  F            : TLeakFinding;
  Map          : TDictionary<Integer, TSuppressedKinds>;
  Markers      : TList<TSuppressionMarker>;
  M            : TSuppressionMarker;
  Suppressed   : TSuppressedKinds;
  NewFinding   : TLeakFinding;
begin
  if (Findings = nil) or (Findings.Count = 0) then Exit;

  FileMaps    := TObjectDictionary<string, TDictionary<Integer, TSuppressedKinds>>.Create([doOwnsValues]);
  FileMarkers := TObjectDictionary<string, TList<TSuppressionMarker>>.Create([doOwnsValues]);
  try
    // Rueckwaerts iterieren – sicher beim Loeschen
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

      if Map.TryGetValue(Line, Suppressed) and (F.Kind in Suppressed) then
      begin
        // Marker-Liste fuer diese Datei aufbauen wenn noch nicht da -
        // wird gleich fuer das Consumed-Tagging gebraucht.
        if not FileMarkers.TryGetValue(F.FileName, Markers) then
        begin
          Markers := TList<TSuppressionMarker>.Create;
          BuildMarkers(F.FileName, Markers);
          FileMarkers.Add(F.FileName, Markers);
        end;
        // Marker als consumed markieren wenn TargetLine + Kind passen.
        // TList<T> erlaubt nicht direkten Index-Edit auf records via
        // for-in, daher Index-basierter Loop mit explizitem Schreibzugriff.
        for j := 0 to Markers.Count - 1 do
        begin
          M := Markers[j];
          if (M.TargetLine = Line) and (F.Kind in M.Kinds) then
          begin
            M.Consumed := True;
            Markers[j] := M;
          end;
        end;
        Findings.Delete(i);
      end;
    end;

    // Zweite Phase: fkUnusedSuppression-Findings fuer Marker emittieren
    // die KEIN Finding suppress't haben. Damit das nicht ausartet wenn
    // ein Marker mehrere Kinds suppresst und nur eines davon greift,
    // emittieren wir EIN Finding pro Marker (nicht pro nicht-getroffenes
    // Kind im Set).
    for var Pair in FileMarkers do
      for M in Pair.Value do
        if not M.Consumed then
        begin
          NewFinding := TLeakFinding.Create;
          NewFinding.FileName   := Pair.Key;
          NewFinding.MethodName := '';
          NewFinding.LineNumber := IntToStr(M.MarkerLine);
          NewFinding.MissingVar :=
            '// noinspection-Marker suppresst nichts - Detektor wurde ' +
            'verbessert oder Target war falsch. Marker entfernen oder ' +
            'Target-Kind pruefen.';
          NewFinding.SetKind(fkUnusedSuppression);
          Findings.Add(NewFinding);
        end;
  finally
    FileMarkers.Free;
    FileMaps.Free;
  end;
end;

end.
