unit uExportHtml;

// Self-contained HTML-Code-Review-Report. Aus uExport ausgelagert weil
// die HTML-Generierung mit eingebettetem CSS + JavaScript der mit Abstand
// groesste Output-Format ist (Filter, Sort, Snippet-Toggle).
//
// Public API:
//   TExporterHtml.Run(...)          - schreibt die HTML-Datei
//   TExporterHtml.DefaultFileName(..) - liefert den Standard-Dateinamen
//
// Wird intern von TExporter.ExportHtml / TExporter.DefaultHtmlFileName
// als Delegation aufgerufen, sodass der Aufrufer weiterhin nur uExport
// in seinen uses braucht.
//
// HTML-spezifische Helper (HtmlEscape, BuildCodeSnippet) liegen privat
// in dieser Unit. Querschnittsfunktionen (KindToName, SaveUtf8WithBom,
// SameSourceFile) kommen via uExport.

interface

uses
  System.SysUtils, System.Classes, System.Math,
  System.Generics.Collections, System.Generics.Defaults,
  uSCAConsts, uMethodd12;

type
  TExporterHtml = class
  public
    class procedure Run(Findings: TObjectList<TLeakFinding>;
      const SourceFile: string; const FileName: string); static;
    class function DefaultFileName(const SourceFile: string;
      const TargetDir: string): string; static;
  private
    class function HtmlEscape(const S: string): string; static;
    // Liefert ein HTML-Fragment (<div class="src-snippet">) mit
    // ContextSize Zeilen vor und nach AroundLine. Die Fund-Zeile ist
    // optisch hervorgehoben. Liefert leeren String wenn SourceLines
    // nil/leer oder AroundLine ungueltig.
    class function BuildCodeSnippet(SourceLines: TStringList;
      AroundLine, ContextSize: Integer): string; static;
    // Report-Zeitstempel. Ist die Umgebungsvariable SCA_REPORT_TIMESTAMP
    // gesetzt, wird deren Wert VERBATIM zurueckgegeben (deterministische
    // CI-Builds -> byte-stabile Diffs), sonst FormatDateTime(AFmt, Now)
    // wie bisher (Default-Verhalten unveraendert).
    class function ReportTimestamp(const AFmt: string): string; static;
  end;

implementation

// noinspection-file BeginEndRequired, ConcatToFormat, ConsecutiveSection, CyclomaticComplexity, DateFormatSettings, DeepNesting, GroupedDeclaration, MagicNumber, NestedTry, NilComparison, StringConcatInLoop, TooLongLine, UnsortedUses, UnusedLocalVar, UnusedParameter, UnusedPublicMember
// HTML-Export baut HTML-Fragmente pro Finding via String-Concat - typische
// Findings-Liste ist klein (~100-500 Eintraege), kein Perf-Hot-Path.

uses
  uExport, uFixHint, uRuleCatalog, uQuickFix;

type
  // Per-Datei-Aggregat fuer das Top-Dateien-Risiko-Ranking (#11).
  TFileAgg = record
    Err, Warn, Hint: Integer;
  end;

class function TExporterHtml.DefaultFileName(const SourceFile: string;
  const TargetDir: string): string;
var
  Base, DateStr: string;
begin
  if SourceFile = '' then
    Base := 'analyse'
  else
    Base := ChangeFileExt(ExtractFileName(SourceFile), '');
  DateStr := ReportTimestamp('yyyy-mm-dd');
  if TargetDir <> '' then
    Result := IncludeTrailingPathDelimiter(TargetDir) +
              Base + '_codereview_' + DateStr + '.html'
  else
    Result := Base + '_codereview_' + DateStr + '.html';
end;

class function TExporterHtml.HtmlEscape(const S: string): string;
// HTML-Escaping mit Robustheit gegen Steuerzeichen und Lone-Surrogates:
//   - &, <, >, ", ' (apos auch escapen, sonst gefaehrlich in attribute-Kontext)
//   - Newline -> <br>, CR ueberspringen
//   - Tab beibehalten
//   - andere Steuerzeichen (U+0000..U+001F, U+007F) als &#xx;-NCR
//   - lone surrogates ersetzen durch U+FFFD (REPLACEMENT CHARACTER)
var
  i  : Integer;
  Ch : Char;
  SB : TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    i := 1;
    while i <= Length(S) do
    begin
      Ch := S[i];
      case Ch of
        '&'  : SB.Append('&amp;');
        '<'  : SB.Append('&lt;');
        '>'  : SB.Append('&gt;');
        '"'  : SB.Append('&quot;');
        '''' : SB.Append('&#39;');
        #9   : SB.Append(#9); // Tab beibehalten
        #10  : SB.Append('<br>');
        #13  : ;              // CR ueberspringen
      else
        if (Ord(Ch) < 32) or (Ord(Ch) = 127) then
          SB.Append(Format('&#%d;', [Ord(Ch)]))
        else if (Ord(Ch) >= $D800) and (Ord(Ch) <= $DBFF)
                and (i < Length(S))
                and (Ord(S[i + 1]) >= $DC00) and (Ord(S[i + 1]) <= $DFFF) then
        begin
          // Gueltiges Surrogate-Pair - beide unveraendert ausgeben
          SB.Append(Ch);
          SB.Append(S[i + 1]);
          Inc(i, 2);
          Continue;
        end
        else if (Ord(Ch) >= $D800) and (Ord(Ch) <= $DFFF) then
          SB.Append(#$FFFD) // Lone Surrogate -> Replacement
        else
          SB.Append(Ch);
      end;
      Inc(i);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TExporterHtml.BuildCodeSnippet(SourceLines: TStringList;
  AroundLine, ContextSize: Integer): string;
var
  SB                 : TStringBuilder;
  i, FromIdx, ToIdx  : Integer;
  CssClass           : string;
  IsActive           : Boolean;
begin
  Result := '';
  if (SourceLines = nil) or (SourceLines.Count = 0) then Exit;
  if AroundLine <= 0 then Exit;

  // 0-basierter Index in der StringList
  FromIdx := AroundLine - 1 - ContextSize;
  ToIdx   := AroundLine - 1 + ContextSize;
  if FromIdx < 0 then FromIdx := 0;
  if ToIdx > SourceLines.Count - 1 then ToIdx := SourceLines.Count - 1;
  if FromIdx > ToIdx then Exit;

  SB := TStringBuilder.Create;
  try
    SB.Append('<div class="src-snippet">');
    for i := FromIdx to ToIdx do
    begin
      IsActive := (i + 1) = AroundLine;
      if IsActive then
        CssClass := 'src-line src-line-active'
      else
        CssClass := 'src-line';
      SB.Append('<div class="' + CssClass + '">');
      SB.Append('<span class="src-line-num">');
      SB.Append(Format('%4d', [i + 1]));
      SB.Append('</span>');
      SB.Append(' <span class="src-line-bar">');
      if IsActive then
        SB.Append('&#9658;') // ASCII Pfeil rechts
      else
        SB.Append('&nbsp;');
      SB.Append('</span> ');
      SB.Append(HtmlEscape(SourceLines[i]));
      SB.Append('</div>');
    end;
    SB.Append('</div>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TExporterHtml.ReportTimestamp(const AFmt: string): string;
var
  Env : string;
begin
  // GetEnvironmentVariable liefert '' wenn die Variable nicht existiert.
  Env := GetEnvironmentVariable('SCA_REPORT_TIMESTAMP');
  if Env <> '' then
    Result := Env
  else
    Result := FormatDateTime(AFmt, Now);
end;

class procedure TExporterHtml.Run(Findings: TObjectList<TLeakFinding>;
  const SourceFile: string; const FileName: string);
const
  SNIPPET_CONTEXT = 3;  // Zeilen vor und nach der Befund-Zeile
  TOP_DETECTORS_N = 10; // Anzahl Eintraege in der Top-Liste und im "Top10"-Filter
  TOP_FILES_N     = 10; // Anzahl Eintraege im Top-Dateien-Risiko-Ranking (#11)
  TOOL_NAME       = 'StaticCodeAnalyser'; // Audit-Header + JSON-Meta (#10)
  // Health-Score (#5): gewichteter Score + Ampel. Dokumentierte Schwellen:
  //   Score = Err*100 + Warn*10 + Hint*1
  //   gruen  : Score <=  49  (keine Fehler, hoechstens ein paar Warnungen)
  //   gelb   : Score 50..499 (mind. 1 Fehler oder viele Warnungen)
  //   rot    : Score >= 500  (>= 5 Fehler-Aequivalente)
  HEALTH_W_ERR      = 100;
  HEALTH_W_WARN     = 10;
  HEALTH_W_HINT     = 1;
  HEALTH_GREEN_MAX  = 49;
  HEALTH_YELLOW_MAX = 499;
var
  SB        : TStringBuilder;
  F         : TLeakFinding;
  SL        : TStringList;
  Files     : TStringList;
  // Bitmask je Datei: 1=Error, 2=Warning, 4=Hint. Gefuettert in der ersten
  // Schleife unten, ausgewertet beim <option data-sev="...">-Emit, sodass
  // der JS-Severity-Filter passende Files im Dropdown verstecken kann.
  FilesSev  : TDictionary<string, Cardinal>;
  SevMask   : Cardinal;
  DataSev   : string;
  SourceCache : TObjectDictionary<string, TStringList>;
  SevCl     : string;
  Title     : string;
  fnDisp    : string;
  nTotal, nErr, nWarn, nHint: Integer;
  // Per-Detektor-Counter. Wird in der ersten Schleife gefuettert,
  // danach absteigend nach Count sortiert fuer die Top-N-Liste +
  // den Top10-Filter im HTML-Export.
  KindCount : TDictionary<TFindingKind, Integer>;
  KindPairs : TList<TPair<TFindingKind, Integer>>;
  KindEntry : TPair<TFindingKind, Integer>;
  CurKindCnt : Integer;
  Top10Set  : TStringList;  // KindName -> in Top10
  i         : Integer;
  // Per-Datei-Aggregat (err/warn/hint) fuer das Risiko-Ranking (#11) und den
  // Health-Score (#5). FileRank = daraus abgeleitete, nach Score absteigend
  // sortierte Liste (Determinismus: stabiler Tiebreak ueber den Dateinamen).
  FileAgg   : TDictionary<string, TFileAgg>;
  FileRank  : TList<TPair<string, Integer>>;
  Agg       : TFileAgg;
  // Health-Score (#5) + deterministischer Report-Zeitstempel (#2/#10).
  WhenStr     : string;
  HealthScore : Integer;
  HealthLevel : string;   // 'green' / 'yellow' / 'red'
  TopCat      : string;   // Kind-Name des staerksten Detektors (Schwerpunkt)

  function GetSourceLines(const APath: string): TStringList;
  // Liest die Datei genau einmal, cached die Zeilen.
  // Liefert nil wenn die Datei nicht (mehr) existiert oder nicht lesbar ist.
  begin
    if APath = '' then Exit(nil);
    if SourceCache.TryGetValue(APath, Result) then Exit;
    Result := nil;
    if not FileExists(APath) then
    begin
      SourceCache.Add(APath, nil);
      Exit;
    end;
    Result := TStringList.Create;
    try
      Result.LoadFromFile(APath, TEncoding.UTF8);
    except
      // UTF-8 fehlgeschlagen - mit System-Default (ANSI) versuchen
      Result.Clear;
      try
        Result.LoadFromFile(APath);
      except
        FreeAndNil(Result);
      end;
    end;
    // Auch nil ablegen, damit wir nicht jedes Mal neu probieren
    SourceCache.Add(APath, Result);
  end;

begin
  if SourceFile = '' then
    Title := 'Code Review'
  else
    Title := 'Code Review - ' + ExtractFileName(SourceFile);

  // Erste Schleife: Zaehler + eindeutige Dateinamen + pro Datei das Set
  // der vorkommenden Severities (fuer den dropdown-internen Severity-Filter).
  // SourceCache haelt geladene Quelldatei-Inhalte (TStringList je Pfad), wird
  // beim Cleanup automatisch alle TStringLists freigeben (doOwnsValues).
  Files       := nil;
  FilesSev    := nil;
  SourceCache := nil;
  KindCount   := nil;
  KindPairs   := nil;
  Top10Set    := nil;
  FileAgg     := nil;
  FileRank    := nil;
  try
    Files := TStringList.Create;
    Files.Duplicates := dupIgnore;
    Files.Sorted := True;
    Files.CaseSensitive := False;
    FilesSev := TDictionary<string, Cardinal>.Create;
    SourceCache := TObjectDictionary<string, TStringList>.Create([doOwnsValues]);
    KindCount := TDictionary<TFindingKind, Integer>.Create;
    FileAgg := TDictionary<string, TFileAgg>.Create;
    Top10Set := TStringList.Create;
    Top10Set.CaseSensitive := False;
    Top10Set.Sorted := True;
    Top10Set.Duplicates := dupIgnore;
    nTotal := 0; nErr := 0; nWarn := 0; nHint := 0;
    if Assigned(Findings) then
      for F in Findings do
      begin
        if (SourceFile <> '') and not TExporter.SameSourceFile(F.FileName, SourceFile) then
          Continue;
        Inc(nTotal);
        case F.Severity of
          lsError   : Inc(nErr);
          lsWarning : Inc(nWarn);
          lsHint    : Inc(nHint);
        end;
        // Detektor-Counter fuer Top-N-Liste.
        if not KindCount.TryGetValue(F.Kind, CurKindCnt) then CurKindCnt := 0;
        KindCount.AddOrSetValue(F.Kind, CurKindCnt + 1);
        if F.FileName <> '' then
        begin
          fnDisp := ExtractFileName(F.FileName);
          Files.Add(fnDisp);
          // Severity-Bit pro Datei akkumulieren.
          if not FilesSev.TryGetValue(fnDisp, SevMask) then SevMask := 0;
          case F.Severity of
            lsError   : SevMask := SevMask or 1;
            lsWarning : SevMask := SevMask or 2;
            lsHint    : SevMask := SevMask or 4;
          end;
          FilesSev.AddOrSetValue(fnDisp, SevMask);
          // Per-Datei-Aggregat fuer Top-Dateien-Risiko-Ranking (#11).
          if not FileAgg.TryGetValue(fnDisp, Agg) then
          begin
            Agg.Err := 0; Agg.Warn := 0; Agg.Hint := 0;
          end;
          case F.Severity of
            lsError   : Inc(Agg.Err);
            lsWarning : Inc(Agg.Warn);
            lsHint    : Inc(Agg.Hint);
          end;
          FileAgg.AddOrSetValue(fnDisp, Agg);
        end;
      end;

    // Top-N-Detektoren: absteigend nach Count, Tiebreak: Kind-Name aufsteigend.
    KindPairs := TList<TPair<TFindingKind, Integer>>.Create;
    for KindEntry in KindCount do
      KindPairs.Add(KindEntry);
    KindPairs.Sort(TComparer<TPair<TFindingKind, Integer>>.Construct(
      function(const A, B: TPair<TFindingKind, Integer>): Integer
      begin
        Result := B.Value - A.Value; // count desc
        if Result = 0 then
          Result := CompareText(KindName(A.Key), KindName(B.Key));
      end));
    for i := 0 to Min(TOP_DETECTORS_N, KindPairs.Count) - 1 do
      Top10Set.Add(KindName(KindPairs[i].Key));

    // Top-Dateien nach gewichtetem Risiko-Score (#11). Score = Err*100 +
    // Warn*10 + Hint. DETERMINISMUS: FileAgg-Iteration ist Hash-Order, daher
    // in eine Liste kopieren und mit TOTALEM Comparator sortieren (Score
    // absteigend, Tiebreak Dateiname aufsteigend).
    FileRank := TList<TPair<string, Integer>>.Create;
    for var FA in FileAgg do
      FileRank.Add(TPair<string, Integer>.Create(FA.Key,
        FA.Value.Err * HEALTH_W_ERR + FA.Value.Warn * HEALTH_W_WARN +
        FA.Value.Hint * HEALTH_W_HINT));
    FileRank.Sort(TComparer<TPair<string, Integer>>.Construct(
      function(const A, B: TPair<string, Integer>): Integer
      begin
        Result := B.Value - A.Value; // Score absteigend
        if Result = 0 then
          Result := CompareText(A.Key, B.Key); // Dateiname aufsteigend
      end));

    // Health-Score (#5): gewichteter Gesamt-Score -> Ampel + Schwerpunkt.
    HealthScore := nErr * HEALTH_W_ERR + nWarn * HEALTH_W_WARN + nHint * HEALTH_W_HINT;
    if HealthScore <= HEALTH_GREEN_MAX then
      HealthLevel := 'green'
    else if HealthScore <= HEALTH_YELLOW_MAX then
      HealthLevel := 'yellow'
    else
      HealthLevel := 'red';
    if (KindPairs <> nil) and (KindPairs.Count > 0) then
      TopCat := KindName(KindPairs[0].Key)
    else
      TopCat := '-';

    // #14 Security-Aggregation: Summe der Funde, deren Regel CWE/OWASP traegt
    // (RuleCatalog) - Zahl fuer das Security-Uebersichts-Panel oben.
    var SecCount := 0;
    if Assigned(KindPairs) then
      for KindEntry in KindPairs do
      begin
        var SM := TRuleCatalog.GetRule(KindEntry.Key);
        if (Length(SM.CWE) > 0) or (Length(SM.OWASP) > 0) then
          Inc(SecCount, KindEntry.Value);
      end;

  SB := TStringBuilder.Create;
  try
    SB.AppendLine('<!DOCTYPE html>');
    // lang-Attribute wird per JS aus localStorage / navigator.language
    // auf en/de/fr gesetzt - Default 'de' fuer den Pre-JS-Render.
    SB.AppendLine('<html lang="de">');
    SB.AppendLine('<head>');
    SB.AppendLine('  <meta charset="UTF-8">');
    SB.Append    ('  <title>'); SB.Append(HtmlEscape(Title)); SB.AppendLine('</title>');
    SB.AppendLine('  <style>');
    SB.AppendLine('    body { font-family: Segoe UI, Arial, sans-serif; margin: 24px; color: #222; }');
    SB.AppendLine('    h1 { font-size: 18px; margin-bottom: 4px; }');
    SB.AppendLine('    .meta { color: #666; font-size: 12px; margin-bottom: 16px; }');
    SB.AppendLine('    .summary { display: flex; gap: 12px; margin-bottom: 16px; }');
    SB.AppendLine('    .badge { padding: 6px 12px; border-radius: 4px; font-size: 12px; }');
    SB.AppendLine('    .badge b { font-size: 16px; display: block; }');
    SB.AppendLine('    .b-err  { background: #ffe5e5; color: #800; }');
    SB.AppendLine('    .b-warn { background: #fff5d0; color: #704000; }');
    SB.AppendLine('    .b-hint { background: #e8f0d8; color: #305018; }');
    SB.AppendLine('    .b-tot  { background: #eee; color: #333; }');
    SB.AppendLine('    /* Klickbare Severity-Badges */');
    SB.AppendLine('    .sev-filter { cursor: pointer; user-select: none;');
    SB.AppendLine('       border: 2px solid transparent; transition: border-color 0.15s; }');
    SB.AppendLine('    .sev-filter:hover { border-color: #888; }');
    SB.AppendLine('    .sev-filter.sev-active { border-color: #333; box-shadow: inset 0 0 0 1px rgba(0,0,0,0.06); }');
    SB.AppendLine('    table { border-collapse: collapse; width: 100%; font-size: 12px; }');
    SB.AppendLine('    th, td { border-bottom: 1px solid #ddd; padding: 6px 8px; text-align: left; vertical-align: top; }');
    SB.AppendLine('    th { background: #f4f4f4; font-weight: 600; }');
    SB.AppendLine('    tr.err  td.sev { color: #b00000; font-weight: 600; }');
    SB.AppendLine('    tr.warn td.sev { color: #b08000; font-weight: 600; }');
    SB.AppendLine('    tr.hint td.sev { color: #5a8000; font-weight: 600; }');
    SB.AppendLine('    tr.err  { background: #fff5f5; }');
    SB.AppendLine('    tr.warn { background: #fffbe8; }');
    SB.AppendLine('    .num { text-align: right; font-variant-numeric: tabular-nums; color: #666; }');
    SB.AppendLine('    /* Klickbare Befund-Zeile + Folgezeile mit Hint */');
    SB.AppendLine('    tr.finding { cursor: pointer; }');
    SB.AppendLine('    tr.finding:hover { filter: brightness(0.97); }');
    SB.AppendLine('    tr.finding td.toggle { width: 18px; text-align: center; color: #888;');
    SB.AppendLine('       font-size: 10px; user-select: none; }');
    SB.AppendLine('    tr.finding.open td.toggle { color: #333; transform: rotate(0); }');
    SB.AppendLine('    tr.finding-hint { display: none; }');
    SB.AppendLine('    tr.finding-hint.open { display: table-row; }');
    SB.AppendLine('    tr.finding-hint > td { background: #fafafa; padding: 10px 16px;');
    SB.AppendLine('       border-bottom: 2px solid #ddd; }');
    SB.AppendLine('    .hint-desc { font-style: italic; color: #444; margin: 0 0 6px 0; }');
    // #3/#4: Regel-Erklaerung-Fallback, CWE/OWASP-Badges, Regel-Beispiel-Note.
    SB.AppendLine('    .hint-rule-desc { border-left: 3px solid #ccd; padding-left: 8px; }');
    SB.AppendLine('    .sec-badges { margin: 0 0 6px 0; }');
    SB.AppendLine('    .sec-badge { display: inline-block; font-size: 10px; font-weight: 600;');
    SB.AppendLine('      padding: 1px 6px; border-radius: 3px; margin-right: 5px; }');
    SB.AppendLine('    .cwe-badge { background: #fde8e8; color: #a02020; border: 1px solid #e8b0b0; }');
    SB.AppendLine('    .owasp-badge { background: #fff0e0; color: #a06020; border: 1px solid #e8c090; }');
    SB.AppendLine('    .rule-example-note { font-size: 11px; color: #888; font-style: italic; margin: 6px 0 2px 0; }');
    SB.AppendLine('    .code-pair { display: flex; gap: 8px; margin-top: 4px; }');
    SB.AppendLine('    .code-block { flex: 1; min-width: 0; }');
    SB.AppendLine('    .code-block h5 { margin: 0 0 2px 0; font-size: 11px; }');
    SB.AppendLine('    .code-before h5 { color: #800; }');
    SB.AppendLine('    .code-after  h5 { color: #060; }');
    SB.AppendLine('    .code-block pre { margin: 0; padding: 6px 8px; font-size: 11px;');
    SB.AppendLine('       font-family: Consolas, "Courier New", monospace; overflow-x: auto;');
    SB.AppendLine('       border-radius: 3px; white-space: pre; }');
    SB.AppendLine('    .code-before pre { background: #fff0f0; color: #400; }');
    SB.AppendLine('    .code-after  pre { background: #f0f8e8; color: #042; }');
    SB.AppendLine('    /* Code-Snippet aus der echten Quelldatei */');
    SB.AppendLine('    .src-snippet { background: #fafafa; border: 1px solid #e0e0e0;');
    SB.AppendLine('       padding: 4px 0; margin: 0 0 8px 0; font-size: 11px;');
    SB.AppendLine('       font-family: Consolas, "Courier New", monospace; overflow-x: auto;');
    SB.AppendLine('       border-radius: 3px; }');
    SB.AppendLine('    .src-line { white-space: pre; padding: 0 8px; }');
    SB.AppendLine('    .src-line-num { color: #999; user-select: none; }');
    SB.AppendLine('    .src-line-bar { color: #ccc; user-select: none; }');
    SB.AppendLine('    .src-line-active { background: #fff5dc; }');
    SB.AppendLine('    .src-line-active .src-line-num,');
    SB.AppendLine('    .src-line-active .src-line-bar { color: #b08000; font-weight: 600; }');
    SB.AppendLine('    .src-snippet-hdr { font-size: 11px; color: #666; margin: 0 0 2px 0; }');
    SB.AppendLine('    /* Controls-Bar: Datei-Filter + Sort-Hinweise */');
    SB.AppendLine('    .controls { display: flex; gap: 12px; align-items: center;');
    SB.AppendLine('       margin: 8px 0 12px 0; font-size: 12px; }');
    SB.AppendLine('    .controls label { color: #555; }');
    SB.AppendLine('    .controls select { font-size: 12px; padding: 4px 6px;');
    SB.AppendLine('       border: 1px solid #ccc; border-radius: 3px; min-width: 200px; }');
    SB.AppendLine('    .controls .hint { color: #888; font-style: italic; }');
    SB.AppendLine('    .controls .row-count { color: #444; font-weight: 600; }');
    SB.AppendLine('    /* Sortierbare Header */');
    SB.AppendLine('    th.sortable { cursor: pointer; user-select: none; }');
    SB.AppendLine('    th.sortable:hover { background: #ebebeb; }');
    SB.AppendLine('    th.sortable .sort-ind { color: #aaa; margin-left: 4px; font-size: 10px; }');
    SB.AppendLine('    th.sortable.sort-asc  .sort-ind::before { content: "\25B2"; color: #333; }');
    SB.AppendLine('    th.sortable.sort-desc .sort-ind::before { content: "\25BC"; color: #333; }');
    SB.AppendLine('    /* Top-Detektoren-Panel */');
    SB.AppendLine('    .top-detectors { background: #f8f8f8; border: 1px solid #e0e0e0;');
    SB.AppendLine('       border-radius: 4px; padding: 8px 12px; margin-bottom: 12px;');
    SB.AppendLine('       font-size: 12px; }');
    SB.AppendLine('    .top-detectors h2 { font-size: 13px; margin: 0 0 6px 0; color: #444;');
    SB.AppendLine('       font-weight: 600; }');
    SB.AppendLine('    .top-detectors ol { margin: 0; padding-left: 22px; columns: 2;');
    SB.AppendLine('       column-gap: 24px; }');
    SB.AppendLine('    .top-detectors li { padding: 2px 0; cursor: pointer;');
    SB.AppendLine('       user-select: none; }');
    SB.AppendLine('    .top-detectors li:hover { color: #06c; text-decoration: underline; }');
    SB.AppendLine('    .top-detectors .td-name { font-family: Consolas, "Courier New", monospace; }');
    SB.AppendLine('    .top-detectors .td-count { color: #666; font-variant-numeric: tabular-nums; }');
    SB.AppendLine('    /* QF-Badge: markiert Detektoren mit Quick-Fix-Provider (uQuickFix). */');
    SB.AppendLine('    /* Tech-Lead-Hint: das sind die "low-hanging fruit" beim Refactoring-Sprint. */');
    SB.AppendLine('    .top-detectors .td-qf { color: #08a; font-size: 10px; margin-left: 6px;');
    SB.AppendLine('       border: 1px solid #08a; border-radius: 2px; padding: 0 4px;');
    SB.AppendLine('       font-weight: 600; letter-spacing: 0.5px; }');
    SB.AppendLine('    /* Audience-Hint-Banner: macht klar fuer wen der Report optimiert ist. */');
    SB.AppendLine('    .audience-hint { background: #eef5ff; border-left: 3px solid #3b73c4;');
    SB.AppendLine('       padding: 8px 12px; margin: 0 0 12px 0; font-size: 12px; color: #234; }');
    SB.AppendLine('    .audience-hint b { color: #1a3b6a; }');
    // #14 Security-Sektion-Panel
    SB.AppendLine('    .sec-panel { background: #fff0f0; border-left: 3px solid #d04040; border-radius: 4px;');
    SB.AppendLine('      padding: 8px 12px; margin: 0 0 12px 0; font-size: 13px; }');
    SB.AppendLine('    .sec-panel-icon { font-size: 15px; }');
    SB.AppendLine('    .sec-panel b { color: #b00000; }');
    SB.AppendLine('    :root[data-theme="dark"] .sec-panel { background: #331e1e; border-color: #d04040; color: #e0c0c0; }');
    SB.AppendLine('    :root[data-theme="dark"] .sec-panel b { color: #ff8080; }');
    SB.AppendLine('    /* Health-Score-Panel (#5): Ampel gruen/gelb/rot, reuse Severity-Farben */');
    SB.AppendLine('    .health-panel { display: flex; align-items: center; gap: 16px;');
    SB.AppendLine('       border-radius: 4px; padding: 10px 14px; margin: 0 0 12px 0;');
    SB.AppendLine('       border: 1px solid #ddd; }');
    SB.AppendLine('    .health-panel.health-green  { background: #e8f0d8; border-color: #b8d088; }');
    SB.AppendLine('    .health-panel.health-yellow { background: #fff5d0; border-color: #e8cd7a; }');
    SB.AppendLine('    .health-panel.health-red    { background: #ffe5e5; border-color: #e0a0a0; }');
    // #6: Uebersicht-Charts (Donut + Kategorie-Balken)
    SB.AppendLine('    .chart-panel { display: flex; gap: 24px; flex-wrap: wrap; align-items: flex-start; margin: 0 0 14px 0; }');
    SB.AppendLine('    .chart-box { background: #f8f8f8; border: 1px solid #e0e0e0; border-radius: 5px; padding: 10px 14px; }');
    SB.AppendLine('    .chart-box h3 { font-size: 13px; margin: 0 0 8px 0; color: #444; font-weight: 600; }');
    SB.AppendLine('    .donut-wrap { display: flex; align-items: center; gap: 14px; }');
    SB.AppendLine('    .donut { width: 110px; height: 110px; }');
    SB.AppendLine('    .donut-total { font-size: 26px; font-weight: 700; fill: #333; }');
    SB.AppendLine('    .chart-legend { font-size: 12px; line-height: 1.7; }');
    SB.AppendLine('    .chart-legend span { display: block; }');
    SB.AppendLine('    .chart-legend i { display: inline-block; width: 10px; height: 10px;');
    SB.AppendLine('       border-radius: 2px; margin-right: 6px; vertical-align: middle; }');
    SB.AppendLine('    .chart-bars { min-width: 320px; flex: 1; }');
    SB.AppendLine('    .cbar { display: flex; align-items: center; gap: 8px; font-size: 12px; padding: 1px 0; }');
    SB.AppendLine('    .cbar-lbl { width: 160px; font-family: Consolas, "Courier New", monospace;');
    SB.AppendLine('       white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }');
    SB.AppendLine('    .cbar-track { flex: 0 0 190px; background: #eee; border-radius: 2px; height: 12px; }');
    SB.AppendLine('    .cbar-fill { display: block; height: 12px; background: #6aa0d8; border-radius: 2px; }');
    SB.AppendLine('    .cbar-num { color: #666; font-variant-numeric: tabular-nums; }');
    // #7 Baseline-Diff: NEU-Zeilen mit gruenem Balken, bestehende leicht gedimmt.
    SB.AppendLine('    .base-summary { font-size: 12px; color: #555; margin-left: 4px; align-self: center; }');
    SB.AppendLine('    tr.finding[data-bstatus="new"] { box-shadow: inset 3px 0 0 #2a9d2a; }');
    SB.AppendLine('    tr.finding[data-bstatus="seen"] { opacity: 0.7; }');
    SB.AppendLine('    :root[data-theme="dark"] .base-summary { color: #aaa; }');
    SB.AppendLine('    .health-badge { display: flex; flex-direction: column; align-items: center;');
    SB.AppendLine('       min-width: 92px; }');
    SB.AppendLine('    .health-label { font-size: 10px; text-transform: uppercase;');
    SB.AppendLine('       letter-spacing: 0.5px; color: #666; }');
    SB.AppendLine('    .health-num { font-size: 26px; font-weight: 700; line-height: 1.1;');
    SB.AppendLine('       font-variant-numeric: tabular-nums; }');
    SB.AppendLine('    .health-status { font-size: 12px; font-weight: 600; }');
    SB.AppendLine('    .health-green  .health-num, .health-green  .health-status { color: #305018; }');
    SB.AppendLine('    .health-yellow .health-num, .health-yellow .health-status { color: #704000; }');
    SB.AppendLine('    .health-red    .health-num, .health-red    .health-status { color: #800; }');
    SB.AppendLine('    .health-line { font-size: 13px; color: #333; }');
    SB.AppendLine('    /* Top-Dateien-Risiko-Ranking (#11): analog zu .top-detectors */');
    SB.AppendLine('    .top-files { background: #f8f8f8; border: 1px solid #e0e0e0;');
    SB.AppendLine('       border-radius: 4px; padding: 8px 12px; margin-bottom: 12px;');
    SB.AppendLine('       font-size: 12px; }');
    SB.AppendLine('    .top-files h2 { font-size: 13px; margin: 0 0 6px 0; color: #444;');
    SB.AppendLine('       font-weight: 600; }');
    SB.AppendLine('    .top-files ol { margin: 0; padding-left: 22px; columns: 2;');
    SB.AppendLine('       column-gap: 24px; }');
    SB.AppendLine('    .top-files li { padding: 2px 0; cursor: pointer; user-select: none; }');
    SB.AppendLine('    .top-files li:hover { color: #06c; text-decoration: underline; }');
    SB.AppendLine('    .top-files .tf-name { font-family: Consolas, "Courier New", monospace; }');
    SB.AppendLine('    .top-files .tf-score { color: #333; font-weight: 600;');
    SB.AppendLine('       font-variant-numeric: tabular-nums; margin-left: 4px; }');
    SB.AppendLine('    .top-files .tf-counts { margin-left: 6px;');
    SB.AppendLine('       font-variant-numeric: tabular-nums; }');
    SB.AppendLine('    .top-files .tf-e { color: #b00000; font-weight: 600; }');
    SB.AppendLine('    .top-files .tf-w { color: #b08000; font-weight: 600; }');
    SB.AppendLine('    .top-files .tf-h { color: #5a8000; font-weight: 600; }');
    SB.AppendLine('    /* Konfidenz-Badge (#1): reuse Severity-Farbwelt */');
    SB.AppendLine('    .conf-badge { font-size: 10px; padding: 0 5px; border-radius: 2px;');
    SB.AppendLine('       font-weight: 600; }');
    SB.AppendLine('    .conf-high   { background: #e8f0d8; color: #305018; }');
    SB.AppendLine('    .conf-medium { background: #fff5d0; color: #704000; }');
    SB.AppendLine('    .conf-low    { background: #eee; color: #777; }');
    SB.AppendLine('    .controls .conf-toggle { display: inline-flex; align-items: center;');
    SB.AppendLine('       gap: 4px; color: #555; cursor: pointer; }');
    SB.AppendLine('    /* Header-Actions: Sprint-Export, Shortcuts-Help neben Titel */');
    SB.AppendLine('    .header-actions { display: flex; gap: 8px; margin: -8px 0 12px 0; }');
    SB.AppendLine('    .tl-btn { background: #3b73c4; color: white; border: none;');
    SB.AppendLine('       padding: 5px 12px; border-radius: 3px; cursor: pointer;');
    SB.AppendLine('       font-size: 12px; font-family: inherit; }');
    SB.AppendLine('    .tl-btn:hover { background: #2a5fa0; }');
    SB.AppendLine('    .tl-btn.secondary { background: #888; }');
    SB.AppendLine('    .tl-btn.secondary:hover { background: #666; }');
    SB.AppendLine('    /* Search-Input */');
    SB.AppendLine('    .controls input[type="search"] { font-size: 12px; padding: 4px 6px;');
    SB.AppendLine('       border: 1px solid #ccc; border-radius: 3px; width: 200px;');
    SB.AppendLine('       font-family: inherit; }');
    SB.AppendLine('    /* Quick-Wins-Option im Profile-Dropdown abheben */');
    SB.AppendLine('    #ruleFilter option[value="qf"] { color: #08a; font-weight: 600; }');
    SB.AppendLine('    /* Keyboard-Shortcuts-Help-Overlay */');
    SB.AppendLine('    .kbd-overlay { position: fixed; inset: 0; background: rgba(0,0,0,0.4);');
    SB.AppendLine('       z-index: 999; display: none; }');
    SB.AppendLine('    .kbd-overlay.open { display: block; }');
    SB.AppendLine('    .kbd-help { position: fixed; top: 50%; left: 50%;');
    SB.AppendLine('       transform: translate(-50%,-50%); background: white;');
    SB.AppendLine('       border: 1px solid #888; border-radius: 5px; padding: 16px 22px;');
    SB.AppendLine('       box-shadow: 0 4px 20px rgba(0,0,0,0.35); z-index: 1000;');
    SB.AppendLine('       display: none; font-size: 12px; min-width: 360px; }');
    SB.AppendLine('    .kbd-help.open { display: block; }');
    SB.AppendLine('    .kbd-help h3 { margin: 0 0 12px 0; font-size: 14px; color: #1a3b6a; }');
    SB.AppendLine('    .kbd-help table { width: 100%; border: none; }');
    SB.AppendLine('    .kbd-help td { padding: 4px 8px; border: none; }');
    SB.AppendLine('    .kbd-help td.k { width: 110px; text-align: right; }');
    SB.AppendLine('    .kbd-help kbd { background: #eee; border: 1px solid #999;');
    SB.AppendLine('       border-radius: 3px; padding: 1px 6px; font-family: Consolas,');
    SB.AppendLine('       "Courier New", monospace; font-size: 11px; color: #222; }');
    SB.AppendLine('    .kbd-help-close { position: absolute; top: 8px; right: 12px;');
    SB.AppendLine('       background: none; border: none; font-size: 18px; cursor: pointer;');
    SB.AppendLine('       color: #888; }');
    SB.AppendLine('    /* Copy-Toast - kurze Bestaetigung beim Clipboard-Kopieren */');
    SB.AppendLine('    .toast { position: fixed; bottom: 30px; left: 50%;');
    SB.AppendLine('       transform: translateX(-50%); background: #1a3b6a; color: white;');
    SB.AppendLine('       padding: 8px 18px; border-radius: 4px; font-size: 12px;');
    SB.AppendLine('       opacity: 0; transition: opacity 0.25s; pointer-events: none;');
    SB.AppendLine('       z-index: 1001; }');
    SB.AppendLine('    .toast.show { opacity: 1; }');
    // #8 A11y: sichtbarer Fokus-Ring (Tastatur) + reduced-motion.
    SB.AppendLine('    *:focus-visible { outline: 2px solid #4a90e2; outline-offset: 1px; border-radius: 2px; }');
    SB.AppendLine('    @media (prefers-reduced-motion: reduce) { * { transition: none !important; animation: none !important; } }');
    // #9 Dark-Mode: EIN Regelsatz; JS setzt data-theme aus localStorage bzw.
    // prefers-color-scheme (keine @media-Duplikation). health-panel bleibt
    // farbkodiert (Status). Nur Schluessel-Flaechen ueberschrieben.
    SB.AppendLine('    :root[data-theme="dark"] body { background: #1e1e1e; color: #d6d6d6; }');
    SB.AppendLine('    :root[data-theme="dark"] a { color: #6cb0ff; }');
    SB.AppendLine('    :root[data-theme="dark"] .meta { color: #999; }');
    SB.AppendLine('    :root[data-theme="dark"] th, :root[data-theme="dark"] td { border-bottom-color: #3a3a3a; }');
    SB.AppendLine('    :root[data-theme="dark"] th { background: #2c2c2c; }');
    SB.AppendLine('    :root[data-theme="dark"] tr.err  { background: #322020; }');
    SB.AppendLine('    :root[data-theme="dark"] tr.warn { background: #322d1c; }');
    SB.AppendLine('    :root[data-theme="dark"] tr.hint { background: #20301c; }');
    SB.AppendLine('    :root[data-theme="dark"] tr.err  td.sev { color: #ff7373; }');
    SB.AppendLine('    :root[data-theme="dark"] tr.warn td.sev { color: #e6b45a; }');
    SB.AppendLine('    :root[data-theme="dark"] tr.hint td.sev { color: #a8d878; }');
    SB.AppendLine('    :root[data-theme="dark"] tr.finding:hover { filter: brightness(1.25); }');
    SB.AppendLine('    :root[data-theme="dark"] tr.finding-hint > td { background: #242424; }');
    SB.AppendLine('    :root[data-theme="dark"] .code-block pre { background: #262626; color: #d0d0d0; }');
    SB.AppendLine('    :root[data-theme="dark"] .code-before pre { background: #331e1e; color: #f0b0b0; }');
    SB.AppendLine('    :root[data-theme="dark"] .code-after  pre { background: #1e301e; color: #b0e0a0; }');
    SB.AppendLine('    :root[data-theme="dark"] .src-snippet { background: #262626; border-color: #444; }');
    SB.AppendLine('    :root[data-theme="dark"] .chart-box, :root[data-theme="dark"] .top-detectors,');
    SB.AppendLine('      :root[data-theme="dark"] .top-files, :root[data-theme="dark"] .audience-hint { background: #262626; border-color: #444; color: #cfcfcf; }');
    SB.AppendLine('    :root[data-theme="dark"] .chart-box h3, :root[data-theme="dark"] .top-detectors h2, :root[data-theme="dark"] .top-files h2 { color: #ccc; }');
    SB.AppendLine('    :root[data-theme="dark"] .cbar-track { background: #3a3a3a; }');
    SB.AppendLine('    :root[data-theme="dark"] .hint-desc { color: #b8b8b8; }');
    SB.AppendLine('    :root[data-theme="dark"] .donut-total { fill: #e0e0e0; }');
    SB.AppendLine('    :root[data-theme="dark"] input, :root[data-theme="dark"] select,');
    SB.AppendLine('      :root[data-theme="dark"] .tl-btn { background: #2c2c2c; color: #ddd; border-color: #555; }');
    // #9b Dark-Mode Kontrast-Nachtrag: Elemente mit eigener dunkler Text-Farbe,
    // die im Dark-Block bisher ungedeckt waren (dunkel-auf-dunkel) -> aufhellen.
    SB.AppendLine('    :root[data-theme="dark"] .num { color: #b0b0b0; }');
    SB.AppendLine('    :root[data-theme="dark"] tr.finding td.toggle { color: #999; }');
    SB.AppendLine('    :root[data-theme="dark"] tr.finding.open td.toggle { color: #e0e0e0; }');
    SB.AppendLine('    :root[data-theme="dark"] .controls label { color: #bbb; }');
    SB.AppendLine('    :root[data-theme="dark"] .controls .hint { color: #999; }');
    SB.AppendLine('    :root[data-theme="dark"] .controls .row-count { color: #e0e0e0; }');
    SB.AppendLine('    :root[data-theme="dark"] th.sortable .sort-ind { color: #888; }');
    SB.AppendLine('    :root[data-theme="dark"] th.sortable.sort-asc .sort-ind::before,');
    SB.AppendLine('      :root[data-theme="dark"] th.sortable.sort-desc .sort-ind::before { color: #e0e0e0; }');
    SB.AppendLine('    :root[data-theme="dark"] .top-detectors .td-count { color: #aaa; }');
    SB.AppendLine('    :root[data-theme="dark"] .top-detectors .td-qf { color: #5ab0f0; }');
    SB.AppendLine('    :root[data-theme="dark"] .cbar-num { color: #aaa; }');
    SB.AppendLine('    :root[data-theme="dark"] .src-line-num { color: #8a8a8a; }');
    SB.AppendLine('    :root[data-theme="dark"] .src-snippet-hdr { color: #aaa; }');
    SB.AppendLine('    :root[data-theme="dark"] .rule-example-note { color: #a0a0a0; }');
    SB.AppendLine('    :root[data-theme="dark"] .top-files .tf-score { color: #e0e0e0; }');
    SB.AppendLine('    :root[data-theme="dark"] .kbd-help { background: #262626; color: #ddd; border-color: #555; }');
    SB.AppendLine('    :root[data-theme="dark"] .kbd-help h3 { color: #6cb0ff; }');
    SB.AppendLine('    :root[data-theme="dark"] .kbd-help kbd { background: #3a3a3a; color: #ddd; border-color: #666; }');
    SB.AppendLine('    :root[data-theme="dark"] .kbd-help-close { color: #bbb; }');
    SB.AppendLine('  </style>');
    SB.AppendLine('</head>');
    SB.AppendLine('<body>');
    SB.Append    ('  <h1>'); SB.Append(HtmlEscape(Title)); SB.AppendLine('</h1>');
    // meta-Zeile mit zwei i18n-Spans + datums-Daten als Attribute, damit
    // applyLanguage die "Erstellt:" / "Datei:"-Labels neu rendern kann
    // (die Werte selbst sind dynamisch und stehen in data-* drin).
    // Deterministischer Report-Zeitstempel (#2): einmal berechnen, fuer
    // data-when, das lesbare Datum UND generatedAt im JSON-Meta-Block nutzen.
    // Mit SCA_REPORT_TIMESTAMP kann CI den Wert pinnen (byte-stabiles Diff).
    WhenStr := ReportTimestamp('yyyy-mm-dd hh:nn');
    SB.Append    ('  <div class="meta"><span data-i18n="meta-created" data-when="');
    SB.Append    (HtmlEscape(WhenStr));
    SB.Append    ('">Erstellt: ');
    SB.Append    (HtmlEscape(WhenStr));
    SB.Append    ('</span>');
    // Audit-Header (#10): Tool + Version, dann Scope (Fund-/Datei-Zahl).
    SB.Append    (' &middot; <span data-i18n="meta-tool" data-tool="');
    SB.Append    (HtmlEscape(TOOL_NAME + ' ' + SCA_VERSION));
    SB.Append    ('">Tool: ');
    SB.Append    (HtmlEscape(TOOL_NAME + ' ' + SCA_VERSION));
    SB.Append    ('</span>');
    SB.Append    (' &middot; <span data-i18n="meta-scope" data-total="');
    SB.Append    (IntToStr(nTotal));
    SB.Append    ('" data-files="');
    SB.Append    (IntToStr(Files.Count));
    SB.Append    ('">');
    SB.Append    (IntToStr(nTotal));
    SB.Append    (' Befunde in ');
    SB.Append    (IntToStr(Files.Count));
    SB.Append    (' Dateien</span>');
    if SourceFile <> '' then
    begin
      SB.Append('  &middot; <span data-i18n="meta-file" data-file="');
      SB.Append(HtmlEscape(SourceFile));
      SB.Append('">Datei: ');
      SB.Append(HtmlEscape(SourceFile));
      SB.Append('</span>');
    end;
    SB.AppendLine('</div>');

    // Maschinenlesbarer Meta-Block (#10) - kein Rendering (application/json),
    // nur zum Parsen durch die Pipeline. generatedAt = derselbe deterministische
    // Zeitstempel wie data-when. Werte via JsonEscape (RFC 8259).
    SB.Append    ('  <script type="application/json" id="sca-meta">');
    SB.Append    ('{"tool":"');
    SB.Append    (TExporter.JsonEscape(TOOL_NAME));
    SB.Append    ('","version":"');
    SB.Append    (TExporter.JsonEscape(SCA_VERSION));
    SB.Append    ('","generatedAt":"');
    SB.Append    (TExporter.JsonEscape(WhenStr));
    SB.Append    ('","profile":"');
    SB.Append    (TExporter.JsonEscape(''));  // Profil nicht an Run uebergeben -> leer
    SB.Append    ('","counts":{"total":');
    SB.Append    (IntToStr(nTotal));
    SB.Append    (',"error":');
    SB.Append    (IntToStr(nErr));
    SB.Append    (',"warning":');
    SB.Append    (IntToStr(nWarn));
    SB.Append    (',"hint":');
    SB.Append    (IntToStr(nHint));
    SB.Append    ('},"files":');
    SB.Append    (IntToStr(Files.Count));
    SB.AppendLine('}</script>');

    // Health-Score-Panel (#5): grosse Kennzahl + Ampel + Klartext-Satz.
    // Alles server-seitig (deterministisch); data-i18n laesst applyLanguage
    // Label/Status/Satz spaeter uebersetzen (dynamische Werte in data-*).
    SB.Append    ('  <div class="health-panel health-');
    SB.Append    (HealthLevel);
    SB.AppendLine('">');
    SB.AppendLine('    <div class="health-badge">');
    SB.AppendLine('      <span class="health-label" data-i18n="health-label">Gesundheitswert</span>');
    SB.Append    ('      <span class="health-num">');
    SB.Append    (IntToStr(HealthScore));
    SB.AppendLine('</span>');
    SB.Append    ('      <span class="health-status" data-i18n="health-');
    SB.Append    (HealthLevel);
    SB.Append    ('">');
    if HealthLevel = 'green' then
      SB.Append('Gesund')
    else if HealthLevel = 'yellow' then
      SB.Append('Achtung')
    else
      SB.Append('Kritisch');
    SB.AppendLine('</span>');
    SB.AppendLine('    </div>');
    SB.Append    ('    <div class="health-line" data-i18n="health-summary" data-nerr="');
    SB.Append    (IntToStr(nErr));
    SB.Append    ('" data-nwarn="');
    SB.Append    (IntToStr(nWarn));
    SB.Append    ('" data-nfiles="');
    SB.Append    (IntToStr(Files.Count));
    SB.Append    ('" data-topcat="');
    SB.Append    (HtmlEscape(TopCat));
    SB.Append    ('">');
    SB.Append    (IntToStr(nErr));
    SB.Append    (' Fehler, ');
    SB.Append    (IntToStr(nWarn));
    SB.Append    (' Warnungen in ');
    SB.Append    (IntToStr(Files.Count));
    SB.Append    (' Dateien; Schwerpunkt <b>');
    SB.Append    (HtmlEscape(TopCat));
    SB.AppendLine('</b></div>');
    SB.AppendLine('  </div>');

    // #6: Uebersicht-Charts - Severity-Donut (Inline-SVG) + Kategorie-Balken.
    // Serverseitig, DETERMINISTISCH (nur Integer via pathLength=100 -> keine
    // Float/Locale-Dezimaltrenner-Fallen), self-contained (kein JS/CDN). Die
    // Legende traegt die exakten Counts (Daten unabhaengig von der Geometrie).
    if nTotal > 0 then
    begin
      var DoffWarn := Round(nErr / nTotal * 100);          // Start-% Warnungen
      var DoffHint := Round((nErr + nWarn) / nTotal * 100); // Start-% Hinweise
      var DdErr  := DoffWarn;               // Segment-Laenge Fehler (%)
      var DdWarn := DoffHint - DoffWarn;    // Warnungen
      var DdHint := 100 - DoffHint;         // Hinweise (Rest schliesst den Ring)
      SB.AppendLine('  <div class="chart-panel">');
      SB.AppendLine('    <div class="chart-box">');
      SB.AppendLine('      <h3 data-i18n="chart-sev-title">Schweregrad-Verteilung</h3>');
      SB.AppendLine('      <div class="donut-wrap">');
      SB.AppendLine('      <svg viewBox="0 0 120 120" class="donut" role="img" aria-label="Severity">');
      SB.AppendLine('        <circle cx="60" cy="60" r="45" fill="none" stroke="#eee" stroke-width="18"/>');
      if nErr > 0 then
      begin
        SB.Append('        <circle cx="60" cy="60" r="45" fill="none" stroke="#E81123" stroke-width="18" pathLength="100" transform="rotate(-90 60 60)" stroke-dasharray="');
        SB.Append(IntToStr(DdErr)); SB.Append(' '); SB.Append(IntToStr(100 - DdErr));
        SB.AppendLine('" stroke-dashoffset="0"/>');
      end;
      if nWarn > 0 then
      begin
        SB.Append('        <circle cx="60" cy="60" r="45" fill="none" stroke="#FF8C00" stroke-width="18" pathLength="100" transform="rotate(-90 60 60)" stroke-dasharray="');
        SB.Append(IntToStr(DdWarn)); SB.Append(' '); SB.Append(IntToStr(100 - DdWarn));
        SB.Append('" stroke-dashoffset="-'); SB.Append(IntToStr(DoffWarn)); SB.AppendLine('"/>');
      end;
      if nHint > 0 then
      begin
        SB.Append('        <circle cx="60" cy="60" r="45" fill="none" stroke="#0078D4" stroke-width="18" pathLength="100" transform="rotate(-90 60 60)" stroke-dasharray="');
        SB.Append(IntToStr(DdHint)); SB.Append(' '); SB.Append(IntToStr(100 - DdHint));
        SB.Append('" stroke-dashoffset="-'); SB.Append(IntToStr(DoffHint)); SB.AppendLine('"/>');
      end;
      SB.Append('        <text x="60" y="66" text-anchor="middle" class="donut-total">');
      SB.Append(IntToStr(nTotal)); SB.AppendLine('</text>');
      SB.AppendLine('      </svg>');
      SB.AppendLine('      <div class="chart-legend">');
      SB.Append('        <span><i style="background:#E81123"></i><span data-i18n="sev-err">Fehler</span> '); SB.Append(IntToStr(nErr)); SB.AppendLine('</span>');
      SB.Append('        <span><i style="background:#FF8C00"></i><span data-i18n="sev-warn">Warnungen</span> '); SB.Append(IntToStr(nWarn)); SB.AppendLine('</span>');
      SB.Append('        <span><i style="background:#0078D4"></i><span data-i18n="sev-hint">Hinweise</span> '); SB.Append(IntToStr(nHint)); SB.AppendLine('</span>');
      SB.AppendLine('      </div>');
      SB.AppendLine('      </div>');
      SB.AppendLine('    </div>');
      if (KindPairs <> nil) and (KindPairs.Count > 0) then
      begin
        var MaxCnt := KindPairs[0].Value;   // KindPairs ist absteigend sortiert
        if MaxCnt < 1 then MaxCnt := 1;
        SB.AppendLine('    <div class="chart-box chart-bars">');
        SB.AppendLine('      <h3 data-i18n="chart-cat-title">Top-Kategorien</h3>');
        for i := 0 to Min(8, KindPairs.Count) - 1 do
        begin
          var W := Round(KindPairs[i].Value / MaxCnt * 180);
          if W < 2 then W := 2;
          SB.Append('      <div class="cbar"><span class="cbar-lbl">');
          SB.Append(HtmlEscape(KindName(KindPairs[i].Key)));
          SB.Append('</span><span class="cbar-track"><span class="cbar-fill" style="width:');
          SB.Append(IntToStr(W));
          SB.Append('px"></span></span><span class="cbar-num">');
          SB.Append(IntToStr(KindPairs[i].Value));
          SB.AppendLine('</span></div>');
        end;
        SB.AppendLine('    </div>');
      end;
      SB.AppendLine('  </div>');
    end;

    // #14 Security-Sektion: hebt den sonst zwischen Code-Smells vergrabenen
    // Sicherheits-Cluster hervor (nur wenn Security-Funde da sind). Der Button
    // aktiviert den bestehenden sec-Filter (#3) im Regel-Dropdown.
    if SecCount > 0 then
    begin
      SB.Append('  <div class="sec-panel"><span class="sec-panel-icon">&#128274;</span> ');
      SB.Append('<span data-i18n="sec-panel-lbl">Security-relevante Funde</span>: <b>');
      SB.Append(IntToStr(SecCount));
      SB.AppendLine('</b> &middot; <button class="tl-btn" id="btnShowSec" data-i18n="sec-panel-btn">nur Security zeigen</button></div>');
    end;

    // Audience-Hint: macht im Brief sichtbar fuer welche Rolle der Report
    // optimiert ist. Tech-Lead / Senior-Dev brauchen die Top-Detektoren
    // (Volumen) plus Severity-Sortierung (Risiko) - genau das ist der
    // Aufbau dieser Seite. Volltext wird im I18N-Dict gehalten -
    // data-i18n=audience-hint laesst applyLanguage den kompletten HTML-
    // Block durch T() schreiben.
    SB.AppendLine('  <div class="audience-hint" data-i18n="audience-hint">');
    SB.AppendLine('    <b>Optimiert fuer Tech-Lead / Senior-Dev Review</b> ' +
                  '&middot; Refactoring-Priorisierung. ' +
                  'Starte oben mit den Top-Detektoren (groesstes Volumen, ' +
                  '<span class="td-qf">QF</span> = Quick-Fix vorhanden), ' +
                  'die Tabelle ist nach Severity sortiert (Fehler &rarr; Hinweis).');
    SB.AppendLine('  </div>');

    // Header-Actions: zwei Tech-Lead-Tools direkt unter dem Hint.
    //   * Sprint-Liste kopieren: erzeugt Markdown-Liste der Top-Befunde fuer
    //     Issue-Tracker (Linear/Jira). Nutzt aktuell sichtbaren Scope (also
    //     Datei/Severity/Profile-Filter werden respektiert).
    //   * Shortcuts: oeffnet Hilfe-Overlay mit Tastatur-Bindings.
    SB.AppendLine('  <div class="header-actions">');
    SB.AppendLine('    <button class="tl-btn" id="btnSprintCopy" ' +
                  'data-i18n="btn-sprint" data-i18n-title="ttl-sprint" ' +
                  'title="Sichtbare Top-Befunde als Markdown-Liste in die Zwischenablage">' +
                  '&#128203; Sprint-Liste kopieren</button>');
    SB.AppendLine('    <button class="tl-btn" id="btnShareLink" ' +
                  'data-i18n="btn-share" data-i18n-title="ttl-share" ' +
                  'title="Aktuelle Filter-Sicht als URL in die Zwischenablage (zum Teilen)">' +
                  '&#128279; Sicht teilen</button>');
    SB.AppendLine('    <button class="tl-btn secondary" id="btnKbdHelp" ' +
                  'data-i18n="btn-kbd" data-i18n-title="ttl-kbd" ' +
                  'title="Tastatur-Shortcuts anzeigen (?)">&#9000; Shortcuts</button>');
    SB.AppendLine('    <button class="tl-btn secondary" id="btnTheme" ' +
                  'title="Hell/Dunkel umschalten" aria-label="Theme">&#9681; Theme</button>');
    SB.AppendLine('    <button class="tl-btn secondary" id="btnBaseSave" ' +
                  'title="Aktuelle Funde als Baseline-JSON speichern (Download)">&#128190; Baseline speichern</button>');
    SB.AppendLine('    <label class="tl-btn secondary" id="btnBaseLoad" ' +
                  'title="Baseline-JSON laden und Funde als neu/bestehend/behoben markieren">' +
                  '&#128193; Baseline laden<input type="file" id="baseFile" accept=".json,application/json" style="display:none"></label>');
    SB.AppendLine('  </div>');

    SB.AppendLine('  <div class="summary">');
    // Klickbare Severity-Badges - data-sev gibt den Wert fuer den JS-Filter
    // ("err"/"warn"/"hint"/"" fuer alle). Counts haben eigene IDs, damit
    // applyFilter() sie live updaten kann wenn Datei-/Rule-Filter wechseln
    // (Severity-Klick selbst aendert die Counts NICHT - sie zeigen immer
    // den Master-Scope, sonst wuerden die anderen Badges auf 0 fallen
    // sobald man eine Severity klickt).
    SB.AppendLine('    <div class="badge b-err sev-filter" data-sev="err"><b id="count-err">'   + IntToStr(nErr)  + '</b><span data-i18n="sev-err">Fehler</span></div>');
    SB.AppendLine('    <div class="badge b-warn sev-filter" data-sev="warn"><b id="count-warn">' + IntToStr(nWarn) + '</b><span data-i18n="sev-warn">Warnungen</span></div>');
    SB.AppendLine('    <div class="badge b-hint sev-filter" data-sev="hint"><b id="count-hint">' + IntToStr(nHint) + '</b><span data-i18n="sev-hint">Hinweise</span></div>');
    SB.AppendLine('    <div class="badge b-tot sev-filter sev-active" data-sev=""><b id="count-tot">'   + IntToStr(nTotal)+ '</b><span data-i18n="sev-total">Gesamt</span></div>');
    SB.AppendLine('  </div>');

    // Top-Detektoren-Panel - zeigt die Top-N Detektoren nach Befund-Anzahl.
    // Klick auf einen Eintrag setzt den Rule-Filter auf "nur dieser Detektor"
    // (data-rule-Match via "kind:<Name>"). Liste ist absteigend nach Count.
    if (KindPairs <> nil) and (KindPairs.Count > 0) then
    begin
      SB.AppendLine('  <div class="top-detectors">');
      // Top-N-Heading mit i18n: applyLanguage liest data-top-n und data-top-total
      // und baut den Heading-Text aus dem Template fuer die Sprache zusammen.
      SB.Append    ('    <h2 data-i18n="hdr-top-detectors" data-top-n="');
      SB.Append    (IntToStr(Min(TOP_DETECTORS_N, KindPairs.Count)));
      SB.Append    ('" data-top-total="');
      SB.Append    (IntToStr(KindPairs.Count));
      SB.Append    ('">Top ');
      SB.Append    (IntToStr(Min(TOP_DETECTORS_N, KindPairs.Count)));
      SB.Append    (' Detektoren (von ');
      SB.Append    (IntToStr(KindPairs.Count));
      SB.AppendLine(')</h2>');
      SB.AppendLine('    <ol>');
      for i := 0 to Min(TOP_DETECTORS_N, KindPairs.Count) - 1 do
      begin
        var KindNm := KindName(KindPairs[i].Key);
        var HasQf  := TQuickFix.HasProviderFor(KindPairs[i].Key);
        SB.Append('      <li data-kind="');
        SB.Append(HtmlEscape(KindNm));
        SB.Append('"><span class="td-name">');
        SB.Append(HtmlEscape(KindNm));
        SB.Append('</span> <span class="td-count">');
        SB.Append(IntToStr(KindPairs[i].Value));
        SB.Append('</span>');
        if HasQf then
          SB.Append(' <span class="td-qf" title="Quick-Fix verfuegbar (Ctrl+Alt+F im IDE-Plugin)">QF</span>');
        SB.AppendLine('</li>');
      end;
      SB.AppendLine('    </ol>');
      SB.AppendLine('  </div>');
    end;

    // Top-Dateien-Risiko-Ranking (#11): analog zum Detektoren-Panel, aber
    // absteigend nach gewichtetem Score (Err*100+Warn*10+Hint). Klick setzt
    // den Datei-Filter (dispatch 'change' -> gleicher Handler wie das Dropdown).
    // Nur im Repo-Modus (SourceFile=''); im Einzeldatei-Modus waere ein
    // Datei-Ranking redundant. Ausgabe ueber die vorsortierte FileRank-Liste.
    if (SourceFile = '') and (FileRank <> nil) and (FileRank.Count > 0) then
    begin
      SB.AppendLine('  <div class="top-files">');
      SB.Append    ('    <h2 data-i18n="hdr-top-files" data-top-n="');
      SB.Append    (IntToStr(Min(TOP_FILES_N, FileRank.Count)));
      SB.Append    ('" data-top-total="');
      SB.Append    (IntToStr(FileRank.Count));
      SB.Append    ('">Top ');
      SB.Append    (IntToStr(Min(TOP_FILES_N, FileRank.Count)));
      SB.Append    (' Risiko-Dateien (von ');
      SB.Append    (IntToStr(FileRank.Count));
      SB.AppendLine(')</h2>');
      SB.AppendLine('    <ol>');
      for i := 0 to Min(TOP_FILES_N, FileRank.Count) - 1 do
      begin
        var FName := FileRank[i].Key;
        var FSc   := FileRank[i].Value;
        var FAg   : TFileAgg;
        if not FileAgg.TryGetValue(FName, FAg) then
        begin
          FAg.Err := 0; FAg.Warn := 0; FAg.Hint := 0;
        end;
        SB.Append('      <li data-file="');
        SB.Append(HtmlEscape(FName));
        SB.Append('"><span class="tf-name">');
        SB.Append(HtmlEscape(FName));
        SB.Append('</span> <span class="tf-score">');
        SB.Append(IntToStr(FSc));
        SB.Append('</span> <span class="tf-counts"><span class="tf-e">');
        SB.Append(IntToStr(FAg.Err));
        SB.Append('</span> <span class="tf-w">');
        SB.Append(IntToStr(FAg.Warn));
        SB.Append('</span> <span class="tf-h">');
        SB.Append(IntToStr(FAg.Hint));
        SB.AppendLine('</span></span></li>');
      end;
      SB.AppendLine('    </ol>');
      SB.AppendLine('  </div>');
    end;

    // Controls-Bar mit Datei-Filter (zeigt alle eindeutigen Dateinamen).
    SB.AppendLine('  <div class="controls">');
    SB.AppendLine('    <label for="ruleFilter" data-i18n="lbl-profile">Profil:</label>');
    SB.AppendLine('    <select id="ruleFilter">');
    SB.AppendLine('      <option value="all" data-i18n="opt-all">Alle</option>');
    SB.Append    ('      <option value="top10">Top ');
    SB.Append    (IntToStr(TOP_DETECTORS_N));
    SB.AppendLine('</option>');
    // Quick-Wins: alle Befunde deren Kind einen Quick-Fix-Provider hat.
    // Tech-Lead-Workflow: "was kann das Team batch-fixen via Ctrl+Alt+F im
    // IDE-Plugin?". Liste der Quick-Fix-Kinds liefert TQuickFix.HasProviderFor;
    // konkretes Matching passiert im JS gegen ALL_KINDS[*].qf.
    SB.AppendLine('      <option value="qf">Quick-Wins (Quick-Fix verfuegbar)</option>');
    SB.AppendLine('      <option value="sec">Security (CWE / OWASP)</option>');
    // Profile-Optionen aus rules/sca-rules.json (TRuleCatalog.ProfileNames).
    // Werte: "profile:<Name>", damit der JS-Filter Profile von "all"/"top10"
    // unterscheiden kann.
    for var ProfileName in TRuleCatalog.ProfileNames do
    begin
      SB.Append('      <option value="profile:');
      SB.Append(HtmlEscape(ProfileName));
      SB.Append('">');
      SB.Append(HtmlEscape(ProfileName));
      SB.AppendLine('</option>');
    end;
    SB.AppendLine('    </select>');
    // Language-Switcher: EN / DE / FR. Default-Caption ist Deutsch (matched
    // den Pre-JS-Render); applyLanguage(lang) updated alles auf data-i18n-
    // Attribut. Auswahl wird in localStorage gespeichert, beim Reload
    // automatisch aktiviert.
    SB.AppendLine('    <label for="langSelect" data-i18n="lbl-lang">Sprache:</label>');
    SB.AppendLine('    <select id="langSelect">');
    SB.AppendLine('      <option value="en">English</option>');
    SB.AppendLine('      <option value="de" selected>Deutsch</option>');
    SB.AppendLine('      <option value="fr">Fran' + #$E7 + 'ais</option>');
    SB.AppendLine('    </select>');
    SB.AppendLine('    <label for="fileFilter" data-i18n="lbl-file">Datei:</label>');
    SB.AppendLine('    <select id="fileFilter">');
    // "Alle (N Dateien)" - der Text ist data-i18n-kontrolliert,
    // applyLanguage updated ihn (mit Counter).
    SB.Append    ('      <option value="" data-i18n="opt-all-files" data-count="');
    SB.Append    (IntToStr(Files.Count));
    SB.Append    ('">Alle (');
    SB.Append    (IntToStr(Files.Count));
    SB.AppendLine(' Dateien)</option>');

    // Basename-Gruppen aufbauen: wenn 'uMainForm.dfm' UND 'uMainForm.pas'
    // beide existieren, emittieren wir zusaetzlich eine Gruppen-Option
    // 'base:uMainForm' obendrueber. Der JS-Filter erkennt den 'base:'-
    // Praefix und matcht dann gegen das data-base-Attribut jeder Zeile.
    var Bases    := TDictionary<string, Integer>.Create;       // base -> count
    var BasesSev := TDictionary<string, Cardinal>.Create;      // base -> sev mask
    try
      for fnDisp in Files do
      begin
        var BaseName := ChangeFileExt(fnDisp, '');
        var Cur : Integer  := 0; Bases.TryGetValue(BaseName, Cur);
        Bases.AddOrSetValue(BaseName, Cur + 1);
        var Sev : Cardinal := 0; FilesSev.TryGetValue(fnDisp, Sev);
        var Acc : Cardinal := 0; BasesSev.TryGetValue(BaseName, Acc);
        BasesSev.AddOrSetValue(BaseName, Acc or Sev);
      end;

      // Gruppen-Optionen zuerst (nur wenn mind. 2 Files mit gleichem Base).
      // DETERMINISMUS: TDictionary-Iteration ist Hash-Order -> qualifizierende
      // Basisnamen erst in eine sortierte Liste kopieren, dann stabil emittieren.
      var GroupBases := TStringList.Create;
      try
        GroupBases.Sorted := True;
        GroupBases.CaseSensitive := False;
        GroupBases.Duplicates := dupIgnore;
        for var BasePair in Bases do
          if BasePair.Value >= 2 then
            GroupBases.Add(BasePair.Key);
        for var gi := 0 to GroupBases.Count - 1 do
        begin
          var GBase := GroupBases[gi];
          var GAcc : Cardinal := 0; BasesSev.TryGetValue(GBase, GAcc);
          DataSev := '';
          if (GAcc and 1) <> 0 then DataSev := DataSev + 'err,';
          if (GAcc and 2) <> 0 then DataSev := DataSev + 'warn,';
          if (GAcc and 4) <> 0 then DataSev := DataSev + 'hint,';
          if DataSev <> '' then
            SetLength(DataSev, Length(DataSev) - 1);

          SB.Append('      <option value="base:');
          SB.Append(HtmlEscape(GBase));
          SB.Append('" data-sev="');
          SB.Append(DataSev);
          SB.Append('">[+] ');
          SB.Append(HtmlEscape(GBase));
          SB.Append(' (.pas + .dfm)</option>'#13#10);
        end;
      finally
        GroupBases.Free;
      end;
    finally
      BasesSev.Free;
      Bases.Free;
    end;

    for fnDisp in Files do
    begin
      // data-sev = Komma-Liste der Severities die in DIESER Datei
      // vorkommen ('err'/'warn'/'hint'). Leer wenn die Datei nur
      // Read-Errors o.ae. enthaelt - der JS-Filter versteckt sie dann
      // sobald ein Severity-Filter aktiv ist.
      SevMask := 0;
      FilesSev.TryGetValue(fnDisp, SevMask);
      DataSev := '';
      if (SevMask and 1) <> 0 then DataSev := DataSev + 'err,';
      if (SevMask and 2) <> 0 then DataSev := DataSev + 'warn,';
      if (SevMask and 4) <> 0 then DataSev := DataSev + 'hint,';
      if DataSev <> '' then
        SetLength(DataSev, Length(DataSev) - 1);

      SB.Append('      <option value="');
      SB.Append(HtmlEscape(fnDisp));
      SB.Append('" data-sev="');
      SB.Append(DataSev);
      SB.Append('">');
      SB.Append(HtmlEscape(fnDisp));
      SB.AppendLine('</option>');
    end;
    SB.AppendLine('    </select>');
    // Text-Suche - matched gegen data-search-Attribut jeder Befund-Zeile
    // (zusammengesetzt aus Methode + Datei + Detail). Vorher gab es im
    // HTML-Export keine Volltextsuche - Tech-Lead musste die Browser-Suche
    // (Strg+F) nutzen, die aber durch geklappte Hint-Zeilen scrollt und
    // nicht filtert.
    SB.AppendLine('    <label for="searchInput" data-i18n="lbl-search">Suche:</label>');
    SB.AppendLine('    <input type="search" id="searchInput" placeholder="Methode, Datei, Detail..." data-i18n-placeholder="ph-search">');
    // Konfidenz-Filter (#1): blendet fcLow-Befunde aus ("nur belastbare Funde").
    // Haengt in das bestehende applyFilter-Modell ein (kein zweites System).
    SB.AppendLine('    <label class="conf-toggle"><input type="checkbox" id="confFilter"> <span data-i18n="lbl-conf-filter">nur belastbare Funde</span></label>');
    SB.AppendLine('    <label class="conf-toggle"><input type="checkbox" id="baseNewFilter" disabled> <span data-i18n="lbl-base-new">nur NEU seit Baseline</span></label>');
    SB.AppendLine('    <span id="baseSummary" class="base-summary"></span>');
    SB.Append    ('    <span class="row-count" id="rowCount" data-i18n="row-count" data-count="');
    SB.Append    (IntToStr(nTotal));
    SB.Append    ('">');
    SB.Append    (IntToStr(nTotal));
    SB.AppendLine(' Befunde</span>');
    SB.AppendLine('    <span class="hint" data-i18n="hint-bar">Spalte sortieren &middot; Zeile zeigt Hinweis &middot; <kbd>?</kbd> Shortcuts</span>');
    SB.AppendLine('  </div>');

    SB.AppendLine('  <table id="findingsTable">');
    SB.AppendLine('    <thead><tr>');
    SB.AppendLine('      <th></th>'); // Toggle-Spalte (nicht sortierbar)
    // Headers: label-Span hat data-i18n damit applyLanguage nur den
    // Text-Teil aktualisiert, ohne die <span class="sort-ind"> zu zerstoeren.
    if SourceFile = '' then
      SB.AppendLine('      <th class="sortable" data-col="file"><span data-i18n="th-file">Datei</span><span class="sort-ind"></span></th>');
    SB.AppendLine('      <th class="sortable" data-col="sev"><span data-i18n="th-sev">Severity</span><span class="sort-ind"></span></th>');
    SB.AppendLine('      <th class="sortable" data-col="conf"><span data-i18n="th-conf">Konfidenz</span><span class="sort-ind"></span></th>');
    SB.AppendLine('      <th class="sortable" data-col="type"><span data-i18n="th-type">Typ</span><span class="sort-ind"></span></th>');
    SB.AppendLine('      <th class="sortable num" data-col="line"><span data-i18n="th-line">Zeile</span><span class="sort-ind"></span></th>');
    SB.AppendLine('      <th class="sortable" data-col="method"><span data-i18n="th-method">Methode</span><span class="sort-ind"></span></th>');
    SB.AppendLine('      <th class="sortable" data-col="rule"><span data-i18n="th-rule">Regel</span><span class="sort-ind"></span></th>');
    SB.AppendLine('      <th class="sortable" data-col="detail"><span data-i18n="th-detail">Detail</span><span class="sort-ind"></span></th>');
    SB.AppendLine('    </tr></thead>');
    SB.AppendLine('    <tbody>');

    if Assigned(Findings) then
      for F in Findings do
      begin
        if (SourceFile <> '') and not TExporter.SameSourceFile(F.FileName, SourceFile) then
          Continue;

        case F.Severity of
          lsError   : SevCl := 'err';
          lsWarning : SevCl := 'warn';
          lsHint    : SevCl := 'hint';
        else
          SevCl := '';
        end;

        // Severity-Rang fuer JS-Sortierung: Fehler=0 (oben), Hinweis=2 (unten),
        // Lesefehler=3 ans Ende. Wird per data-sort am Severity-<td> abgelegt.
        var SevRank: Integer;
        if F.Kind = fkFileReadError then SevRank := 3
        else case F.Severity of
          lsError   : SevRank := 0;
          lsWarning : SevRank := 1;
          lsHint    : SevRank := 2;
        else
          SevRank := 9;
        end;

        var Hint := TFixHintResolver.FixHint(F);
        // Source-Snippet: ContextSize Zeilen vor und nach der Befund-Zeile
        // direkt aus der Quelldatei lesen, falls die noch existiert.
        var Snippet := '';
        var LineNo := StrToIntDef(F.LineNumber, 0);
        if (F.FileName <> '') and (LineNo > 0) then
        begin
          var SrcLines := GetSourceLines(F.FileName);
          if SrcLines <> nil then
            Snippet := BuildCodeSnippet(SrcLines, LineNo, SNIPPET_CONTEXT);
        end;
        // Regel-Metadaten (#3/#4): Fallback-Erklaerung (fullDescription) +
        // kanonisches bad/good-Beispiel + CWE/OWASP aus dem RuleCatalog, falls
        // der per-Finding-FixHint nichts liefert. GetRule liefert nie nil
        // (MakeFallbackMeta), leere Felder werden unten einfach uebersprungen.
        var Meta := TRuleCatalog.GetRule(F.Kind);
        var HasCwe := (Length(Meta.CWE) > 0) or (Length(Meta.OWASP) > 0);
        var HasHint := (Hint.Description <> '') or
                       (Hint.Before <> '') or (Hint.After <> '') or
                       (Snippet <> '') or
                       (Meta.FullDescription <> '') or
                       (Meta.BadExample <> '') or (Meta.GoodExample <> '') or
                       HasCwe;
        var FileShort := ExtractFileName(F.FileName);
        // data-base = Basename ohne Extension. Dient dem Gruppen-Filter
        // ('base:uMainForm') im Datei-Dropdown, der .pas und .dfm mit
        // gleichem Basename gemeinsam ein-/ausblenden soll.
        var FileBase := ChangeFileExt(FileShort, '');

        // Sichtbare Befund-Zeile - data-file fuer Filter, ganze Zeile klickbar.
        // data-rule = KindName (Catalog-Token), gegen das der Profile-Filter
        // im JS prueft (PROFILES[<name>].kinds[rule]).
        // data-search = lowercased Methode/Datei/Detail/Regel - wird vom JS
        // searchInput.value gegen substring-gematcht. Lowercase einmal hier
        // statt N-mal pro Tastendruck.
        var KindNm := KindName(F.Kind);
        var SearchBlob :=
              LowerCase(F.MethodName) + ' ' +
              LowerCase(FileShort)    + ' ' +
              LowerCase(F.MissingVar) + ' ' +
              LowerCase(KindNm);
        // #7 Baseline-Fingerprint: kind|datei|methode|detail - bewusst OHNE
        // Zeilennummer, damit Zeilen-Verschiebungen keine Pseudo-"neu"-Funde
        // erzeugen (client-seitiger Baseline-Diff neu/bestehend/behoben).
        var Fpid := LowerCase(KindNm) + '|' + LowerCase(FileBase) + '|' +
                    LowerCase(F.MethodName) + '|' + LowerCase(Trim(F.MissingVar));
        // Konfidenz (#1): Name ('high'/'medium'/'low') als data-conf (Filter)
        // + Rang als data-sort der Konfidenz-Spalte (0=high oben). data-qf
        // dient als Tertiaer-Kriterium im Default-Sort (Severity->Konf->QF).
        var ConfNm := ConfidenceName(F.Confidence);
        var ConfRank : Integer;
        case F.Confidence of
          fcHigh:   ConfRank := 0;
          fcMedium: ConfRank := 1;
          fcLow:    ConfRank := 2;
        else
          ConfRank := 0;
        end;
        var RowQf : Integer;
        if TQuickFix.HasProviderFor(F.Kind) then RowQf := 1 else RowQf := 0;
        SB.Append('      <tr class="finding ' + SevCl + '" data-file="');
        SB.Append(HtmlEscape(FileShort));
        SB.Append('" data-base="');
        SB.Append(HtmlEscape(FileBase));
        SB.Append('" data-rule="');
        SB.Append(HtmlEscape(KindNm));
        SB.Append('" data-search="');
        SB.Append(HtmlEscape(SearchBlob));
        SB.Append('" data-conf="');
        SB.Append(ConfNm);
        SB.Append('" data-qf="');
        SB.Append(IntToStr(RowQf));
        SB.Append('" data-sec="');       // #3: 1 = Regel hat CWE/OWASP -> Security-Filter
        if HasCwe then SB.Append('1') else SB.Append('0');
        SB.Append('" data-fpid="');      // #7 Baseline-Fingerprint (zeilenunabhaengig)
        SB.Append(HtmlEscape(Fpid));
        SB.Append('">');
        // Toggle-Indikator: Pfeil rechts (oder leer wenn kein Hint)
        if HasHint then
          SB.Append('<td class="toggle">&#9656;</td>')
        else
          SB.Append('<td class="toggle"></td>');
        if SourceFile = '' then
        begin
          SB.Append('<td>');
          SB.Append(HtmlEscape(FileShort));
          SB.Append('</td>');
        end;
        // Severity mit data-sort = Rang (numerisch sortierbar)
        SB.Append('<td class="sev" data-sort="' + IntToStr(SevRank) + '">');
        SB.Append(HtmlEscape(F.SeverityText));
        SB.Append('</td>');
        // Konfidenz-Spalte (#1): data-sort = Rang, Badge via data-i18n lokalisiert.
        SB.Append('<td class="conf" data-sort="' + IntToStr(ConfRank) + '">');
        SB.Append('<span class="conf-badge conf-' + ConfNm + '" data-i18n="conf-' + ConfNm + '">');
        SB.Append(ConfNm);
        SB.Append('</span></td>');
        SB.Append('<td>'); SB.Append(HtmlEscape(F.TypeText)); SB.Append('</td>');
        // Zeile mit data-sort als rein numerischer Wert
        SB.Append('<td class="num" data-sort="' + F.LineNumber + '">');
        SB.Append(HtmlEscape(F.LineNumber));
        SB.Append('</td>');
        SB.Append('<td>'); SB.Append(HtmlEscape(F.MethodName)); SB.Append('</td>');
        SB.Append('<td>'); SB.Append(HtmlEscape(TExporter.KindToName(F.Kind))); SB.Append('</td>');
        SB.Append('<td>'); SB.Append(HtmlEscape(F.MissingVar)); SB.Append('</td>');
        SB.AppendLine('</tr>');

        // Versteckte Hint-Zeile (wird per JS sichtbar geschaltet)
        if HasHint then
        begin
          // colspan = 8 oder 9 je nachdem ob Datei-Spalte da ist
          // (Toggle + [Datei] + Sev + Konfidenz + Typ + Zeile + Methode + Regel + Detail)
          var Cols := 8;
          if SourceFile = '' then Cols := 9;
          SB.Append('      <tr class="finding-hint"><td colspan="' + IntToStr(Cols) + '">');
          if Hint.Description <> '' then
          begin
            SB.Append('<div class="hint-desc">');
            SB.Append(HtmlEscape(Hint.Description));
            SB.Append('</div>');
          end
          else if Meta.FullDescription <> '' then
          begin
            // #4: Fallback auf die kanonische Regel-Erklaerung (WARUM), wenn
            // der per-Finding-FixHint keine eigene Beschreibung liefert.
            SB.Append('<div class="hint-desc hint-rule-desc">');
            SB.Append(HtmlEscape(Meta.FullDescription));
            SB.Append('</div>');
          end;

          // #3: CWE/OWASP-Badges (Standard-IDs, sprachneutral) - nur wenn die
          // Regel klassifiziert ist. CWE/OWASP sind TArray<string>.
          if HasCwe then
          begin
            SB.Append('<div class="sec-badges">');
            for var CweId in Meta.CWE do
            begin
              SB.Append('<span class="sec-badge cwe-badge">');
              SB.Append(HtmlEscape(CweId));
              SB.Append('</span>');
            end;
            for var OwaspId in Meta.OWASP do
            begin
              SB.Append('<span class="sec-badge owasp-badge">');
              SB.Append(HtmlEscape(OwaspId));
              SB.Append('</span>');
            end;
            SB.Append('</div>');
          end;

          // Echter Code-Auszug aus der Quelldatei mit hervorgehobener Zeile.
          // Header benutzt data-i18n=src-snippet-hdr mit data-file und data-line -
          // applyLanguage rendert den ganzen Header via T("src-snippet-hdr", file, line).
          if Snippet <> '' then
          begin
            SB.Append('<div class="src-snippet-hdr" data-i18n="src-snippet-hdr" data-file="');
            SB.Append(HtmlEscape(FileShort));
            SB.Append('" data-line="');
            SB.Append(F.LineNumber);
            SB.Append('">Quelle: ');
            SB.Append(HtmlEscape(FileShort));
            SB.Append(', Zeile ');
            SB.Append(F.LineNumber);
            SB.Append('</div>');
            SB.Append(Snippet);
          end;

          if (Hint.Before <> '') or (Hint.After <> '') then
          begin
            SB.Append('<div class="code-pair">');
            if Hint.Before <> '' then
            begin
              SB.Append('<div class="code-block code-before"><h5 data-i18n="hint-before">Vorher (Problem)</h5><pre>');
              SB.Append(HtmlEscape(Hint.Before));
              SB.Append('</pre></div>');
            end;
            if Hint.After <> '' then
            begin
              SB.Append('<div class="code-block code-after"><h5 data-i18n="hint-after">Nachher (Loesung)</h5><pre>');
              SB.Append(HtmlEscape(Hint.After));
              SB.Append('</pre></div>');
            end;
            SB.Append('</div>');
          end
          else if (Meta.BadExample <> '') or (Meta.GoodExample <> '') then
          begin
            // #4: Fallback auf das kanonische bad/good-Regel-Beispiel, wenn der
            // FixHint kein per-Finding Vorher/Nachher hat. Note kennzeichnet es
            // als generisches Regel-Beispiel (nicht auf diesen Fund zugeschnitten).
            SB.Append('<div class="rule-example-note" data-i18n="rule-example-note">Kanonisches Regel-Beispiel</div>');
            SB.Append('<div class="code-pair">');
            if Meta.BadExample <> '' then
            begin
              SB.Append('<div class="code-block code-before"><h5 data-i18n="hint-before">Vorher (Problem)</h5><pre>');
              SB.Append(HtmlEscape(Meta.BadExample));
              SB.Append('</pre></div>');
            end;
            if Meta.GoodExample <> '' then
            begin
              SB.Append('<div class="code-block code-after"><h5 data-i18n="hint-after">Nachher (Loesung)</h5><pre>');
              SB.Append(HtmlEscape(Meta.GoodExample));
              SB.Append('</pre></div>');
            end;
            SB.Append('</div>');
          end;
          SB.AppendLine('</td></tr>');
        end;
      end;

    SB.AppendLine('    </tbody>');
    SB.AppendLine('  </table>');
    SB.AppendLine('  <script>');
    // ---- i18n: Sprach-Wahlmoeglichkeit EN / DE / FR -----------------------
    // Strings die im DOM stehen werden via data-i18n-Attribut markiert;
    // dynamische Strings (im JS gebaut) gehen ueber T(key, ...args).
    // Auswahl wird in localStorage["sca-html-lang"] persistiert. Beim
    // ersten Laden: navigator.language -> en/de/fr fallback de.
    SB.AppendLine('    var I18N = {');
    SB.AppendLine('      en: {');
    SB.AppendLine('        "lbl-lang": "Language:",');
    SB.AppendLine('        "lbl-profile": "Profile:",');
    SB.AppendLine('        "lbl-file": "File:",');
    SB.AppendLine('        "lbl-search": "Search:",');
    SB.AppendLine('        "ph-search": "Method, file, detail...",');
    SB.AppendLine('        "opt-all": "All",');
    SB.AppendLine('        "opt-all-files": "All ({0} files)",');
    SB.AppendLine('        "row-count": "{0} findings",');
    SB.AppendLine('        "hint-bar": "Click column to sort &middot; row toggles hint &middot; <kbd>?</kbd> shortcuts",');
    SB.AppendLine('        "th-file": "File",');
    SB.AppendLine('        "th-sev": "Severity",');
    SB.AppendLine('        "th-type": "Type",');
    SB.AppendLine('        "th-line": "Line",');
    SB.AppendLine('        "th-method": "Method",');
    SB.AppendLine('        "th-rule": "Rule",');
    SB.AppendLine('        "th-detail": "Detail",');
    SB.AppendLine('        "sev-err": "Errors",');
    SB.AppendLine('        "sev-warn": "Warnings",');
    SB.AppendLine('        "sev-hint": "Hints",');
    SB.AppendLine('        "sev-total": "Total",');
    SB.AppendLine('        "th-conf": "Confidence",');
    SB.AppendLine('        "rule-example-note": "Canonical rule example",');
    SB.AppendLine('        "chart-sev-title": "Severity distribution",');
    SB.AppendLine('        "chart-cat-title": "Top categories",');
    SB.AppendLine('        "conf-high": "high",');
    SB.AppendLine('        "conf-medium": "medium",');
    SB.AppendLine('        "conf-low": "low",');
    SB.AppendLine('        "lbl-conf-filter": "reliable findings only",');
    SB.AppendLine('        "lbl-base-new": "new since baseline",');
    SB.AppendLine('        "sec-panel-lbl": "Security-relevant findings",');
    SB.AppendLine('        "sec-panel-btn": "show security only",');
    SB.AppendLine('        "health-label": "Health score",');
    SB.AppendLine('        "health-green": "Healthy",');
    SB.AppendLine('        "health-yellow": "Attention",');
    SB.AppendLine('        "health-red": "Critical",');
    SB.AppendLine('        "health-summary": "{0} errors, {1} warnings in {2} files; focus <b>{3}</b>",');
    SB.AppendLine('        "hdr-top-files": "Top {0} risk files (of {1})",');
    SB.AppendLine('        "meta-tool": "Tool: {0}",');
    SB.AppendLine('        "meta-scope": "{0} findings in {1} files",');
    SB.AppendLine('        "btn-sprint": "&#128203; Copy sprint list",');
    SB.AppendLine('        "ttl-sprint": "Visible top findings as Markdown list to the clipboard",');
    SB.AppendLine('        "btn-share": "&#128279; Share view",');
    SB.AppendLine('        "ttl-share": "Current filter view as URL to the clipboard (for sharing)",');
    SB.AppendLine('        "btn-kbd":   "&#9000; Shortcuts",');
    SB.AppendLine('        "ttl-kbd":   "Show keyboard shortcuts (?)",');
    SB.AppendLine('        "hdr-top-detectors": "Top {0} detectors (of {1})",');
    SB.AppendLine('        "kbd-help-title": "Keyboard shortcuts",');
    SB.AppendLine('        "kbd-help-close": "Close",');
    SB.AppendLine('        "sprint-header": "Total visible: {0} findings. Top {1} priorities:",');
    SB.AppendLine('        "meta-created": "Generated: {0}",');
    SB.AppendLine('        "meta-file":    "File: {0}",');
    SB.AppendLine('        "audience-hint": "<b>Optimised for Tech-Lead / Senior-Dev review</b> &middot; ' +
      'refactoring prioritisation. Start at the top with the Top Detectors (highest volume, <span class=\"td-qf\">QF</span> = quick-fix available); the table is sorted by severity (Errors &rarr; Hints).",');
    SB.AppendLine('        "src-snippet-hdr": "Source: {0}, line {1}",');
    SB.AppendLine('        "hint-before": "Before (Problem)",');
    SB.AppendLine('        "hint-after":  "After (Fix)"');
    SB.AppendLine('      },');
    SB.AppendLine('      de: {');
    SB.AppendLine('        "lbl-lang": "Sprache:",');
    SB.AppendLine('        "lbl-profile": "Profil:",');
    SB.AppendLine('        "lbl-file": "Datei:",');
    SB.AppendLine('        "lbl-search": "Suche:",');
    SB.AppendLine('        "ph-search": "Methode, Datei, Detail...",');
    SB.AppendLine('        "opt-all": "Alle",');
    SB.AppendLine('        "opt-all-files": "Alle ({0} Dateien)",');
    SB.AppendLine('        "row-count": "{0} Befunde",');
    SB.AppendLine('        "hint-bar": "Spalte sortieren &middot; Zeile zeigt Hinweis &middot; <kbd>?</kbd> Shortcuts",');
    SB.AppendLine('        "th-file": "Datei",');
    SB.AppendLine('        "th-sev": "Severity",');
    SB.AppendLine('        "th-type": "Typ",');
    SB.AppendLine('        "th-line": "Zeile",');
    SB.AppendLine('        "th-method": "Methode",');
    SB.AppendLine('        "th-rule": "Regel",');
    SB.AppendLine('        "th-detail": "Detail",');
    SB.AppendLine('        "sev-err": "Fehler",');
    SB.AppendLine('        "sev-warn": "Warnungen",');
    SB.AppendLine('        "sev-hint": "Hinweise",');
    SB.AppendLine('        "sev-total": "Gesamt",');
    SB.AppendLine('        "th-conf": "Konfidenz",');
    SB.AppendLine('        "rule-example-note": "Kanonisches Regel-Beispiel",');
    SB.AppendLine('        "chart-sev-title": "Schweregrad-Verteilung",');
    SB.AppendLine('        "chart-cat-title": "Top-Kategorien",');
    SB.AppendLine('        "conf-high": "hoch",');
    SB.AppendLine('        "conf-medium": "mittel",');
    SB.AppendLine('        "conf-low": "niedrig",');
    SB.AppendLine('        "lbl-conf-filter": "nur belastbare Funde",');
    SB.AppendLine('        "lbl-base-new": "nur NEU seit Baseline",');
    SB.AppendLine('        "sec-panel-lbl": "Security-relevante Funde",');
    SB.AppendLine('        "sec-panel-btn": "nur Security zeigen",');
    SB.AppendLine('        "health-label": "Gesundheitswert",');
    SB.AppendLine('        "health-green": "Gesund",');
    SB.AppendLine('        "health-yellow": "Achtung",');
    SB.AppendLine('        "health-red": "Kritisch",');
    SB.AppendLine('        "health-summary": "{0} Fehler, {1} Warnungen in {2} Dateien; Schwerpunkt <b>{3}</b>",');
    SB.AppendLine('        "hdr-top-files": "Top {0} Risiko-Dateien (von {1})",');
    SB.AppendLine('        "meta-tool": "Tool: {0}",');
    SB.AppendLine('        "meta-scope": "{0} Befunde in {1} Dateien",');
    SB.AppendLine('        "btn-sprint": "&#128203; Sprint-Liste kopieren",');
    SB.AppendLine('        "ttl-sprint": "Sichtbare Top-Befunde als Markdown-Liste in die Zwischenablage",');
    SB.AppendLine('        "btn-share": "&#128279; Sicht teilen",');
    SB.AppendLine('        "ttl-share": "Aktuelle Filter-Sicht als URL in die Zwischenablage (zum Teilen)",');
    SB.AppendLine('        "btn-kbd":   "&#9000; Shortcuts",');
    SB.AppendLine('        "ttl-kbd":   "Tastatur-Shortcuts anzeigen (?)",');
    SB.AppendLine('        "hdr-top-detectors": "Top {0} Detektoren (von {1})",');
    SB.AppendLine('        "kbd-help-title": "Tastatur-Shortcuts",');
    SB.AppendLine('        "kbd-help-close": "Schliessen",');
    SB.AppendLine('        "sprint-header": "Gesamt sichtbar: {0} Befunde. Top {1} Prioritaeten:",');
    SB.AppendLine('        "meta-created": "Erstellt: {0}",');
    SB.AppendLine('        "meta-file":    "Datei: {0}",');
    SB.AppendLine('        "audience-hint": "<b>Optimiert fuer Tech-Lead / Senior-Dev Review</b> &middot; ' +
      'Refactoring-Priorisierung. Starte oben mit den Top-Detektoren (groesstes Volumen, <span class=\"td-qf\">QF</span> = Quick-Fix vorhanden), die Tabelle ist nach Severity sortiert (Fehler &rarr; Hinweis).",');
    SB.AppendLine('        "src-snippet-hdr": "Quelle: {0}, Zeile {1}",');
    SB.AppendLine('        "hint-before": "Vorher (Problem)",');
    SB.AppendLine('        "hint-after":  "Nachher (Loesung)"');
    SB.AppendLine('      },');
    SB.AppendLine('      fr: {');
    SB.AppendLine('        "lbl-lang": "Langue\\u00a0:",');
    SB.AppendLine('        "lbl-profile": "Profil\\u00a0:",');
    SB.AppendLine('        "lbl-file": "Fichier\\u00a0:",');
    SB.AppendLine('        "lbl-search": "Rechercher\\u00a0:",');
    SB.AppendLine('        "ph-search": "M\\u00e9thode, fichier, d\\u00e9tail...",');
    SB.AppendLine('        "opt-all": "Tous",');
    SB.AppendLine('        "opt-all-files": "Tous ({0} fichiers)",');
    SB.AppendLine('        "row-count": "{0} d\\u00e9tections",');
    SB.AppendLine('        "hint-bar": "Cliquez sur une colonne pour trier &middot; ligne ouvre l\\u2019indice &middot; <kbd>?</kbd> raccourcis",');
    SB.AppendLine('        "th-file": "Fichier",');
    SB.AppendLine('        "th-sev": "S\\u00e9v\\u00e9rit\\u00e9",');
    SB.AppendLine('        "th-type": "Type",');
    SB.AppendLine('        "th-line": "Ligne",');
    SB.AppendLine('        "th-method": "M\\u00e9thode",');
    SB.AppendLine('        "th-rule": "R\\u00e8gle",');
    SB.AppendLine('        "th-detail": "D\\u00e9tail",');
    SB.AppendLine('        "sev-err": "Erreurs",');
    SB.AppendLine('        "sev-warn": "Avertissements",');
    SB.AppendLine('        "sev-hint": "Indices",');
    SB.AppendLine('        "sev-total": "Total",');
    SB.AppendLine('        "th-conf": "Confiance",');
    SB.AppendLine('        "rule-example-note": "Exemple canonique de r\\u00e8gle",');
    SB.AppendLine('        "chart-sev-title": "R\\u00e9partition par gravit\\u00e9",');
    SB.AppendLine('        "chart-cat-title": "Cat\\u00e9gories principales",');
    SB.AppendLine('        "conf-high": "\\u00e9lev\\u00e9e",');
    SB.AppendLine('        "conf-medium": "moyenne",');
    SB.AppendLine('        "conf-low": "faible",');
    SB.AppendLine('        "lbl-conf-filter": "d\\u00e9tections fiables uniquement",');
    SB.AppendLine('        "lbl-base-new": "nouveaux depuis la r\\u00e9f\\u00e9rence",');
    SB.AppendLine('        "sec-panel-lbl": "D\\u00e9tections li\\u00e9es \\u00e0 la s\\u00e9curit\\u00e9",');
    SB.AppendLine('        "sec-panel-btn": "afficher uniquement la s\\u00e9curit\\u00e9",');
    SB.AppendLine('        "health-label": "Score de sant\\u00e9",');
    SB.AppendLine('        "health-green": "Sain",');
    SB.AppendLine('        "health-yellow": "Attention",');
    SB.AppendLine('        "health-red": "Critique",');
    SB.AppendLine('        "health-summary": "{0} erreurs, {1} avertissements dans {2} fichiers\\u00a0; point cl\\u00e9 <b>{3}</b>",');
    SB.AppendLine('        "hdr-top-files": "Top {0} fichiers \\u00e0 risque (sur {1})",');
    SB.AppendLine('        "meta-tool": "Outil\\u00a0: {0}",');
    SB.AppendLine('        "meta-scope": "{0} d\\u00e9tections dans {1} fichiers",');
    SB.AppendLine('        "btn-sprint": "&#128203; Copier la liste sprint",');
    SB.AppendLine('        "ttl-sprint": "D\\u00e9tections visibles comme liste Markdown dans le presse-papiers",');
    SB.AppendLine('        "btn-share": "&#128279; Partager la vue",');
    SB.AppendLine('        "ttl-share": "Vue de filtre actuelle comme URL dans le presse-papiers (\\u00e0 partager)",');
    SB.AppendLine('        "btn-kbd":   "&#9000; Raccourcis",');
    SB.AppendLine('        "ttl-kbd":   "Afficher les raccourcis clavier (?)",');
    SB.AppendLine('        "hdr-top-detectors": "Top {0} d\\u00e9tecteurs (sur {1})",');
    SB.AppendLine('        "kbd-help-title": "Raccourcis clavier",');
    SB.AppendLine('        "kbd-help-close": "Fermer",');
    SB.AppendLine('        "sprint-header": "Visibles au total\\u00a0: {0} d\\u00e9tections. Top {1} priorit\\u00e9s\\u00a0:",');
    SB.AppendLine('        "meta-created": "G\\u00e9n\\u00e9r\\u00e9\\u00a0: {0}",');
    SB.AppendLine('        "meta-file":    "Fichier\\u00a0: {0}",');
    SB.AppendLine('        "audience-hint": "<b>Optimis\\u00e9 pour la revue Tech-Lead / Senior-Dev</b> &middot; ' +
      'priorisation du refactoring. Commencez par les Top D\\u00e9tecteurs (volume le plus important, <span class=\"td-qf\">QF</span> = quick-fix disponible)\\u00a0; le tableau est tri\\u00e9 par s\\u00e9v\\u00e9rit\\u00e9 (erreurs &rarr; indices).",');
    SB.AppendLine('        "src-snippet-hdr": "Source\\u00a0: {0}, ligne {1}",');
    SB.AppendLine('        "hint-before": "Avant (probl\\u00e8me)",');
    SB.AppendLine('        "hint-after":  "Apr\\u00e8s (solution)"');
    SB.AppendLine('      }');
    SB.AppendLine('    };');
    SB.AppendLine('    var SCA_LANG = (function() {');
    SB.AppendLine('      try {');
    SB.AppendLine('        var s = localStorage.getItem("sca-html-lang");');
    SB.AppendLine('        if (s && I18N[s]) return s;');
    SB.AppendLine('      } catch(e) {}');
    SB.AppendLine('      var nav = (navigator.language || "de").substring(0,2).toLowerCase();');
    SB.AppendLine('      return I18N[nav] ? nav : "de";');
    SB.AppendLine('    })();');
    SB.AppendLine('    function T(key) {');
    SB.AppendLine('      var s = (I18N[SCA_LANG] && I18N[SCA_LANG][key]) || (I18N["en"] && I18N["en"][key]) || key;');
    SB.AppendLine('      for (var i = 1; i < arguments.length; i++) {');
    SB.AppendLine('        s = s.replace(new RegExp("\\{" + (i-1) + "\\}", "g"), arguments[i]);');
    SB.AppendLine('      }');
    SB.AppendLine('      return s;');
    SB.AppendLine('    }');
    SB.AppendLine('    function applyLanguage(lang) {');
    SB.AppendLine('      if (!I18N[lang]) return;');
    SB.AppendLine('      SCA_LANG = lang;');
    SB.AppendLine('      try { localStorage.setItem("sca-html-lang", lang); } catch(e) {}');
    SB.AppendLine('      document.documentElement.lang = lang;');
    SB.AppendLine('      // Text-Nodes: data-i18n-Attribute');
    SB.AppendLine('      document.querySelectorAll("[data-i18n]").forEach(function(el) {');
    SB.AppendLine('        var key = el.getAttribute("data-i18n");');
    SB.AppendLine('        // Dynamische Counter-Strings: data-count / data-top-n / data-top-total');
    SB.AppendLine('        if (key === "row-count")        el.innerHTML = T(key, el.dataset.count || "0");');
    SB.AppendLine('        else if (key === "opt-all-files") el.textContent = T(key, el.dataset.count || "0");');
    SB.AppendLine('        else if (key === "hdr-top-detectors") el.textContent = T(key, el.dataset.topN || "0", el.dataset.topTotal || "0");');
    SB.AppendLine('        // meta-Zeile: Datum/Datei stehen in data-when / data-file');
    SB.AppendLine('        else if (key === "meta-created") el.textContent = T(key, el.dataset.when || "");');
    SB.AppendLine('        else if (key === "meta-file")    el.textContent = T(key, el.dataset.file || "");');
    SB.AppendLine('        // src-snippet-Header: file + line stehen in data-file / data-line');
    SB.AppendLine('        else if (key === "src-snippet-hdr") el.textContent = T(key, el.dataset.file || "", el.dataset.line || "");');
    SB.AppendLine('        // Audit-Header (#10): Tool + Scope stehen in data-*');
    SB.AppendLine('        else if (key === "meta-tool")    el.textContent = T(key, el.dataset.tool || "");');
    SB.AppendLine('        else if (key === "meta-scope")   el.textContent = T(key, el.dataset.total || "0", el.dataset.files || "0");');
    SB.AppendLine('        // Top-Dateien-Heading (#11) analog zu hdr-top-detectors');
    SB.AppendLine('        else if (key === "hdr-top-files") el.textContent = T(key, el.dataset.topN || "0", el.dataset.topTotal || "0");');
    SB.AppendLine('        // Health-Klartext (#5): enthaelt <b>{3}</b> -> innerHTML');
    SB.AppendLine('        else if (key === "health-summary") el.innerHTML = T(key, el.dataset.nerr || "0", el.dataset.nwarn || "0", el.dataset.nfiles || "0", el.dataset.topcat || "");');
    SB.AppendLine('        // audience-hint enthaelt eingebettetes Markup (<b>, <span>, &rarr;) -');
    SB.AppendLine('        // T() darf den Wert nicht escapen, T(key) liefert ihn 1:1 ins innerHTML.');
    SB.AppendLine('        else                            el.innerHTML = T(key);');
    SB.AppendLine('      });');
    SB.AppendLine('      // Placeholder-Attribute');
    SB.AppendLine('      document.querySelectorAll("[data-i18n-placeholder]").forEach(function(el) {');
    SB.AppendLine('        el.placeholder = T(el.getAttribute("data-i18n-placeholder"));');
    SB.AppendLine('      });');
    SB.AppendLine('      // Title-Attribute (Tooltip-Texte)');
    SB.AppendLine('      document.querySelectorAll("[data-i18n-title]").forEach(function(el) {');
    SB.AppendLine('        el.title = T(el.getAttribute("data-i18n-title")).replace(/&[#a-z0-9]+;/g, "");');
    SB.AppendLine('      });');
    SB.AppendLine('      // Sprach-Select selbst auf den aktiven Wert ziehen');
    SB.AppendLine('      var sel = document.getElementById("langSelect");');
    SB.AppendLine('      if (sel) sel.value = lang;');
    SB.AppendLine('    }');
    SB.AppendLine('');
    // TOP10_KINDS: Set-Lookup fuer den Row-Filter "Top 10" (Bedeutung:
    // "zeige nur Zeilen aus den unfiltered Top-10"). Bleibt fix, unabhaengig
    // vom Rule-Filter - sonst waere "Top 10" doppelt-konditional.
    SB.Append    ('    var TOP10_KINDS = {');
    for i := 0 to Top10Set.Count - 1 do
    begin
      if i > 0 then SB.Append(',');
      SB.Append(' "');
      SB.Append(HtmlEscape(Top10Set[i])); // KindNames sind ASCII-Identifier, defensiv escapen
      SB.Append('": 1');
    end;
    SB.AppendLine(' };');
    // ALL_KINDS: vollstaendige Liste aller getroffenen Kinds, absteigend
    // sortiert. JS rebuildet daraus die Top-Detektoren-Liste in
    // Abhaengigkeit vom Profile-Filter.
    SB.AppendLine('    var ALL_KINDS = [');
    if (KindPairs <> nil) then
      for i := 0 to KindPairs.Count - 1 do
      begin
        var KindNm := KindName(KindPairs[i].Key);
        var QfFlag : Integer;
        if TQuickFix.HasProviderFor(KindPairs[i].Key) then QfFlag := 1 else QfFlag := 0;
        SB.Append('      {n:"');
        SB.Append(HtmlEscape(KindNm));
        SB.Append('", c:');
        SB.Append(IntToStr(KindPairs[i].Value));
        SB.Append(', qf:');
        SB.Append(IntToStr(QfFlag));
        SB.Append('}');
        if i < KindPairs.Count - 1 then SB.Append(',');
        SB.AppendLine;
      end;
    SB.AppendLine('    ];');
    SB.Append    ('    var TOP_N = ');
    SB.Append    (IntToStr(TOP_DETECTORS_N));
    SB.AppendLine(';');
    // PROFILES: Profile-Name -> Set der enthaltenen Kind-Namen. "all":true
    // ist ein Wildcard-Marker (default/strict aus rules/sca-rules.json
    // listen "*"); JS-Filter behandelt das als "kein Filter". Andere
    // Profile listen die enthaltenen Kinds explizit auf, JS-Lookup ist
    // dann O(1) ueber die Objekt-Property.
    SB.AppendLine('    var PROFILES = {');
    var ProfileNames := TRuleCatalog.ProfileNames;
    for var pi := 0 to High(ProfileNames) do
    begin
      var PName := ProfileNames[pi];
      var PSet  := TRuleCatalog.GetProfile(PName);
      // Wildcard-Heuristik: wenn das Set alle Kinds enthaelt, behandeln
      // wir es als "all" (sparen das Inline-Listing aller ~107 Namen).
      var IsAll : Boolean := True;
      for var K := Low(TFindingKind) to High(TFindingKind) do
        if not (K in PSet) then begin IsAll := False; Break; end;
      SB.Append('      "');
      SB.Append(HtmlEscape(PName));
      SB.Append('": {all:');
      if IsAll then SB.Append('true,') else SB.Append('false,');
      SB.Append(' kinds:{');
      if not IsAll then
      begin
        var First : Boolean := True;
        for var K := Low(TFindingKind) to High(TFindingKind) do
          if K in PSet then
          begin
            if not First then SB.Append(',');
            SB.Append('"');
            SB.Append(HtmlEscape(KindName(K)));
            SB.Append('":1');
            First := False;
          end;
      end;
      SB.Append('}}');
      if pi < High(ProfileNames) then SB.Append(',');
      SB.AppendLine;
    end;
    SB.AppendLine('    };');
    SB.AppendLine('  (function() {');
    SB.AppendLine('    var table  = document.getElementById(''findingsTable'');');
    SB.AppendLine('    var tbody  = table.querySelector(''tbody'');');
    SB.AppendLine('    var rowCnt = document.getElementById(''rowCount'');');
    SB.AppendLine('    var fileSel = document.getElementById(''fileFilter'');');
    SB.AppendLine('    var ruleSel = document.getElementById(''ruleFilter'');');
    SB.AppendLine('');
    SB.AppendLine('    // ---- Toggle: Klick auf Befund-Zeile blendet Hint-Zeile ein/aus ----');
    SB.AppendLine('    function wireToggle(row) {');
    SB.AppendLine('      var hint = row.nextElementSibling;');
    SB.AppendLine('      if (!hint || !hint.classList.contains(''finding-hint'')) return;');
    SB.AppendLine('      row.addEventListener(''click'', function() {');
    SB.AppendLine('        var open = hint.classList.toggle(''open'');');
    SB.AppendLine('        row.classList.toggle(''open'', open);');
    SB.AppendLine('        var t = row.querySelector(''td.toggle'');');
    SB.AppendLine('        if (t) t.innerHTML = open ? ''&#9662;'' : ''&#9656;'';');
    SB.AppendLine('      });');
    SB.AppendLine('    }');
    SB.AppendLine('    document.querySelectorAll(''tr.finding'').forEach(wireToggle);');
    SB.AppendLine('');
    SB.AppendLine('    // ---- Sortierung: Klick auf Spaltenheader ----');
    SB.AppendLine('    // Spalten-Index im finding-tr - Toggle-Spalte ist immer Index 0,');
    SB.AppendLine('    // die optionale Datei-Spalte (Multi-File-Modus) schiebt alles ab Sev');
    SB.AppendLine('    // um eins nach rechts.');
    SB.AppendLine('    //   Multi-File:  Toggle=0, Datei=1, Sev=2, Konf=3, Typ=4, Zeile=5, Methode=6, Regel=7, Detail=8');
    SB.AppendLine('    //   Single-File: Toggle=0,           Sev=1, Konf=2, Typ=3, Zeile=4, Methode=5, Regel=6, Detail=7');
    SB.AppendLine('    var hasFile = !!table.querySelector(''th[data-col="file"]'');');
    SB.AppendLine('    var SEV_BASE = hasFile ? 2 : 1; // erste Spalte nach Toggle (+ ggf. Datei)');
    SB.AppendLine('    var colIndex = {');
    SB.AppendLine('      file:   1, // nur valide wenn hasFile - sortBy(''file'') wird nur wired wenn die Spalte existiert');
    SB.AppendLine('      sev:    SEV_BASE + 0,');
    SB.AppendLine('      conf:   SEV_BASE + 1,'); // Konfidenz-Spalte (#1) direkt nach Severity
    SB.AppendLine('      type:   SEV_BASE + 2,');
    SB.AppendLine('      line:   SEV_BASE + 3,');
    SB.AppendLine('      method: SEV_BASE + 4,');
    SB.AppendLine('      rule:   SEV_BASE + 5,');
    SB.AppendLine('      detail: SEV_BASE + 6');
    SB.AppendLine('    };');
    SB.AppendLine('    var numericCols = { line: true, sev: true, conf: true };');
    SB.AppendLine('    var currentSort = { col: null, desc: false };');
    SB.AppendLine('');
    SB.AppendLine('    function getKey(row, col) {');
    SB.AppendLine('      var idx = colIndex[col];');
    SB.AppendLine('      var cell = row.children[idx];');
    SB.AppendLine('      if (!cell) return '''';');
    SB.AppendLine('      // data-sort hat Vorrang (numerisch o. Rang), sonst textContent');
    SB.AppendLine('      var k = cell.getAttribute(''data-sort'');');
    SB.AppendLine('      return k !== null ? k : cell.textContent;');
    SB.AppendLine('    }');
    SB.AppendLine('');
    SB.AppendLine('    function compareRows(a, b, col, desc) {');
    SB.AppendLine('      var ka = getKey(a, col);');
    SB.AppendLine('      var kb = getKey(b, col);');
    SB.AppendLine('      var cmp;');
    SB.AppendLine('      if (numericCols[col]) {');
    SB.AppendLine('        cmp = (parseFloat(ka) || 0) - (parseFloat(kb) || 0);');
    SB.AppendLine('      } else {');
    SB.AppendLine('        cmp = ka.localeCompare(kb, ''de'', { sensitivity: ''base'' });');
    SB.AppendLine('      }');
    SB.AppendLine('      // Default-Prio-Sort (#1): beim Severity-Sort sekundaer nach Konfidenz');
    SB.AppendLine('      // (hoch=0 zuerst), tertiaer nach Quick-Fix-Verfuegbarkeit (QF zuerst).');
    SB.AppendLine('      if (cmp === 0 && col === ''sev'') {');
    SB.AppendLine('        var ca = parseInt(getKey(a, ''conf''), 10); if (isNaN(ca)) ca = 0;');
    SB.AppendLine('        var cb = parseInt(getKey(b, ''conf''), 10); if (isNaN(cb)) cb = 0;');
    SB.AppendLine('        cmp = ca - cb;');
    SB.AppendLine('        if (cmp === 0) {');
    SB.AppendLine('          var qa = (a.getAttribute(''data-qf'') === ''1'') ? 0 : 1;');
    SB.AppendLine('          var qb = (b.getAttribute(''data-qf'') === ''1'') ? 0 : 1;');
    SB.AppendLine('          cmp = qa - qb;');
    SB.AppendLine('        }');
    SB.AppendLine('      }');
    SB.AppendLine('      return desc ? -cmp : cmp;');
    SB.AppendLine('    }');
    SB.AppendLine('');
    SB.AppendLine('    function sortBy(col) {');
    SB.AppendLine('      // Bei zweitem Klick auf gleiche Spalte: Richtung umdrehen.');
    SB.AppendLine('      var desc = (currentSort.col === col) ? !currentSort.desc : false;');
    SB.AppendLine('      currentSort = { col: col, desc: desc };');
    SB.AppendLine('');
    SB.AppendLine('      // Header-Indikator');
    SB.AppendLine('      table.querySelectorAll(''th.sortable'').forEach(function(th) {');
    SB.AppendLine('        th.classList.remove(''sort-asc'', ''sort-desc'');');
    SB.AppendLine('        if (th.getAttribute(''data-col'') === col)');
    SB.AppendLine('          th.classList.add(desc ? ''sort-desc'' : ''sort-asc'');');
    SB.AppendLine('      });');
    SB.AppendLine('');
    SB.AppendLine('      // Pairs (finding, finding-hint?) zusammenhalten');
    SB.AppendLine('      var pairs = [];');
    SB.AppendLine('      var rows = Array.from(tbody.children);');
    SB.AppendLine('      for (var i = 0; i < rows.length; i++) {');
    SB.AppendLine('        var r = rows[i];');
    SB.AppendLine('        if (!r.classList.contains(''finding'')) continue;');
    SB.AppendLine('        var nxt = rows[i + 1];');
    SB.AppendLine('        if (nxt && nxt.classList.contains(''finding-hint''))');
    SB.AppendLine('          pairs.push([r, nxt]);');
    SB.AppendLine('        else');
    SB.AppendLine('          pairs.push([r, null]);');
    SB.AppendLine('      }');
    SB.AppendLine('      pairs.sort(function(p1, p2) {');
    SB.AppendLine('        return compareRows(p1[0], p2[0], col, desc);');
    SB.AppendLine('      });');
    SB.AppendLine('      // Re-attach in sortierter Reihenfolge');
    SB.AppendLine('      pairs.forEach(function(p) {');
    SB.AppendLine('        tbody.appendChild(p[0]);');
    SB.AppendLine('        if (p[1]) tbody.appendChild(p[1]);');
    SB.AppendLine('      });');
    SB.AppendLine('    }');
    SB.AppendLine('');
    SB.AppendLine('    table.querySelectorAll(''th.sortable'').forEach(function(th) {');
    SB.AppendLine('      th.addEventListener(''click'', function() {');
    SB.AppendLine('        sortBy(th.getAttribute(''data-col''));');
    SB.AppendLine('      });');
    SB.AppendLine('    });');
    SB.AppendLine('');
    SB.AppendLine('    // ---- Datei- und Severity-Filter (kombinierbar) ----');
    SB.AppendLine('    var activeSev = ''''; // '''' = alle, sonst ''err''/''warn''/''hint''');
    SB.AppendLine('');
    SB.AppendLine('    // Alle expandierten Befunde wieder einklappen.');
    SB.AppendLine('    // Wird bei Filter-Wechsel aufgerufen, damit der User nach dem');
    SB.AppendLine('    // Umschalten nicht mit ploetzlich aufgeklappten Hint-Bloecken einer');
    SB.AppendLine('    // anderen Problem-Gruppe konfrontiert wird.');
    SB.AppendLine('    function collapseAll() {');
    SB.AppendLine('      document.querySelectorAll(''tr.finding.open'').forEach(function(row) {');
    SB.AppendLine('        row.classList.remove(''open'');');
    SB.AppendLine('        var t = row.querySelector(''td.toggle'');');
    SB.AppendLine('        if (t && t.textContent.length > 0) t.innerHTML = ''&#9656;'';');
    SB.AppendLine('      });');
    SB.AppendLine('      document.querySelectorAll(''tr.finding-hint.open'').forEach(function(h) {');
    SB.AppendLine('        h.classList.remove(''open'');');
    SB.AppendLine('        h.style.display = ''''; // CSS uebernimmt wieder (display: none)');
    SB.AppendLine('      });');
    SB.AppendLine('    }');
    SB.AppendLine('');
    SB.AppendLine('    // QF_KINDS: Lookup-Set aller Kinds mit Quick-Fix-Provider.');
    SB.AppendLine('    // Wird einmalig aus ALL_KINDS aufgebaut, vom QF-Filter und vom');
    SB.AppendLine('    // Sprint-Snapshot benutzt.');
    SB.AppendLine('    var QF_KINDS = {};');
    SB.AppendLine('    ALL_KINDS.forEach(function(k) { if (k.qf === 1) QF_KINDS[k.n] = 1; });');
    SB.AppendLine('');
    SB.AppendLine('    var searchInput = document.getElementById(''searchInput'');');
    SB.AppendLine('    var confFilter  = document.getElementById(''confFilter''); // #1: "nur belastbare Funde"');
    SB.AppendLine('    var baseNewFilter = document.getElementById(''baseNewFilter''); // #7: nur NEU seit Baseline');
    SB.AppendLine('');
    SB.AppendLine('    function applyFilter() {');
    SB.AppendLine('      var fileVal = fileSel ? fileSel.value : '''';');
    SB.AppendLine('      // Gruppen-Filter: "base:<Basename>" matcht alle Files mit gleichem');
    SB.AppendLine('      // Basename (z.B. uMainForm.pas + uMainForm.dfm). Sonst exact match.');
    SB.AppendLine('      var isGroup = fileVal && fileVal.indexOf(''base:'') === 0;');
    SB.AppendLine('      var groupVal = isGroup ? fileVal.substring(5) : '''';');
    SB.AppendLine('      // Rule-Filter: all / top10 / qf / profile:<Name> /');
    SB.AppendLine('      // kind:<Name> (Klick auf Eintrag in Top-Detektoren-Liste).');
    SB.AppendLine('      var ruleVal = ruleSel ? ruleSel.value : ''all'';');
    SB.AppendLine('      var pinnedKind = (ruleVal.indexOf(''kind:'') === 0) ? ruleVal.substring(5) : '''';');
    SB.AppendLine('      var profileName = (ruleVal.indexOf(''profile:'') === 0) ? ruleVal.substring(8) : '''';');
    SB.AppendLine('      var profileDef = profileName ? PROFILES[profileName] : null;');
    SB.AppendLine('      var q = searchInput ? searchInput.value.trim().toLowerCase() : '''';');
    SB.AppendLine('      var confOn = confFilter && confFilter.checked; // fcLow ausblenden');
    SB.AppendLine('      var baseOn = baseNewFilter && baseNewFilter.checked; // #7 nur NEU');
    SB.AppendLine('      var visible = 0;');
    SB.AppendLine('      // Master-Scope-Counts pro Severity. Werden in den Top-Kacheln');
    SB.AppendLine('      // angezeigt und reflektieren NUR Datei-+Rule-Filter, NICHT die');
    SB.AppendLine('      // Sev-Klick-Auswahl (sonst wuerden die anderen Badges auf 0');
    SB.AppendLine('      // fallen sobald man "Fehler" klickt - verwirrend).');
    SB.AppendLine('      var nErr = 0, nWarn = 0, nHint = 0;');
    SB.AppendLine('      document.querySelectorAll(''tr.finding'').forEach(function(row) {');
    SB.AppendLine('        var fileOk;');
    SB.AppendLine('        if (!fileVal) fileOk = true;');
    SB.AppendLine('        else if (isGroup) fileOk = row.getAttribute(''data-base'') === groupVal;');
    SB.AppendLine('        else fileOk = row.getAttribute(''data-file'') === fileVal;');
    SB.AppendLine('        var sevOk  = !activeSev || row.classList.contains(activeSev);');
    SB.AppendLine('        var rk = row.getAttribute(''data-rule'') || '''';');
    SB.AppendLine('        var ruleOk;');
    SB.AppendLine('        if (pinnedKind)                     ruleOk = (rk === pinnedKind);');
    SB.AppendLine('        else if (ruleVal === ''top10'')      ruleOk = TOP10_KINDS[rk] === 1;');
    SB.AppendLine('        else if (ruleVal === ''qf'')         ruleOk = QF_KINDS[rk] === 1;');
    SB.AppendLine('        else if (ruleVal === ''sec'')        ruleOk = row.getAttribute(''data-sec'') === ''1''; // #3 Security-Filter');
    SB.AppendLine('        else if (profileDef)                ruleOk = profileDef.all || (profileDef.kinds[rk] === 1);');
    SB.AppendLine('        else ruleOk = true; // ''all''');
    SB.AppendLine('        // Volltextsuche - matched gegen data-search (Methode + Datei + Detail + Regel).');
    SB.AppendLine('        var searchOk = !q || ((row.getAttribute(''data-search'') || '''').indexOf(q) !== -1);');
    SB.AppendLine('        // Konfidenz-Filter (#1): blendet fcLow aus wenn aktiv.');
    SB.AppendLine('        var confOk = !confOn || (row.getAttribute(''data-conf'') !== ''low'');');
    SB.AppendLine('        // Baseline-Filter (#7): nur NEU-Zeilen wenn aktiv (data-bstatus=new).');
    SB.AppendLine('        var baseOk = !baseOn || (row.getAttribute(''data-bstatus'') === ''new'');');
    SB.AppendLine('        // Master-Scope = fileOk && ruleOk && searchOk && confOk && baseOk (ohne sev). Daraus die Kacheln.');
    SB.AppendLine('        if (fileOk && ruleOk && searchOk && confOk && baseOk) {');
    SB.AppendLine('          if      (row.classList.contains(''err''))  nErr++;');
    SB.AppendLine('          else if (row.classList.contains(''warn'')) nWarn++;');
    SB.AppendLine('          else if (row.classList.contains(''hint'')) nHint++;');
    SB.AppendLine('        }');
    SB.AppendLine('        var match  = fileOk && sevOk && ruleOk && searchOk && confOk && baseOk;');
    SB.AppendLine('        row.style.display = match ? '''' : ''none'';');
    SB.AppendLine('        var hint = row.nextElementSibling;');
    SB.AppendLine('        if (hint && hint.classList.contains(''finding-hint'')) {');
    SB.AppendLine('          if (!match) {');
    SB.AppendLine('            hint.style.display = ''none'';');
    SB.AppendLine('          } else if (hint.classList.contains(''open'')) {');
    SB.AppendLine('            hint.style.display = ''table-row'';');
    SB.AppendLine('          } else {');
    SB.AppendLine('            hint.style.display = '''';');
    SB.AppendLine('          }');
    SB.AppendLine('        }');
    SB.AppendLine('        if (match) visible++;');
    SB.AppendLine('      });');
    SB.AppendLine('      if (rowCnt) { rowCnt.dataset.count = visible; rowCnt.innerHTML = T("row-count", visible); }');
    SB.AppendLine('      // Master-Kacheln updaten - reflektieren den Datei-+Rule-Scope.');
    SB.AppendLine('      var cErr  = document.getElementById(''count-err'');');
    SB.AppendLine('      var cWarn = document.getElementById(''count-warn'');');
    SB.AppendLine('      var cHint = document.getElementById(''count-hint'');');
    SB.AppendLine('      var cTot  = document.getElementById(''count-tot'');');
    SB.AppendLine('      if (cErr)  cErr.textContent  = nErr;');
    SB.AppendLine('      if (cWarn) cWarn.textContent = nWarn;');
    SB.AppendLine('      if (cHint) cHint.textContent = nHint;');
    SB.AppendLine('      if (cTot)  cTot.textContent  = (nErr + nWarn + nHint);');
    SB.AppendLine('      // URL-Hash aktualisieren (replaceState = kein History-Eintrag,');
    SB.AppendLine('      // sonst wuerde jeder Tastendruck im Search-Feld die Back-Button-');
    SB.AppendLine('      // History fluten).');
    SB.AppendLine('      syncUrlHash();');
    SB.AppendLine('    }');
    SB.AppendLine('    if (fileSel) fileSel.addEventListener(''change'', function() {');
    SB.AppendLine('      collapseAll();');
    SB.AppendLine('      applyFilter();');
    SB.AppendLine('    });');
    SB.AppendLine('    if (ruleSel) ruleSel.addEventListener(''change'', function() {');
    SB.AppendLine('      collapseAll();');
    SB.AppendLine('      rebuildTopDetectors();');
    SB.AppendLine('      applyFilter();');
    SB.AppendLine('    });');
    SB.AppendLine('    if (searchInput) {');
    SB.AppendLine('      // input statt change - liveupdate beim Tippen, ohne Enter abzuwarten.');
    SB.AppendLine('      var searchTimer = null;');
    SB.AppendLine('      searchInput.addEventListener(''input'', function() {');
    SB.AppendLine('        // Mini-Debounce: vermeidet bei jedem Buchstaben einen Full-Pass');
    SB.AppendLine('        // ueber alle Befund-Zeilen wenn die Tabelle gross ist.');
    SB.AppendLine('        if (searchTimer) clearTimeout(searchTimer);');
    SB.AppendLine('        searchTimer = setTimeout(applyFilter, 120);');
    SB.AppendLine('      });');
    SB.AppendLine('    }');
    SB.AppendLine('    if (confFilter) confFilter.addEventListener(''change'', function() {');
    SB.AppendLine('      collapseAll();');
    SB.AppendLine('      applyFilter();');
    SB.AppendLine('    });');
    SB.AppendLine('');
    SB.AppendLine('    // ---- Top-Detektoren-Liste live aus ALL_KINDS + Profile-Filter ----');
    SB.AppendLine('    // profile:<Name> reduziert den Pool auf die Profile-Kinds (Wildcard');
    SB.AppendLine('    // "all" durchlaesst alles). all/top10/kind:X zeigen die volle Top-N');
    SB.AppendLine('    // (damit der User immer pivotieren kann).');
    SB.AppendLine('    function rebuildTopDetectors() {');
    SB.AppendLine('      var ol = document.querySelector(''.top-detectors ol'');');
    SB.AppendLine('      var h2 = document.querySelector(''.top-detectors h2'');');
    SB.AppendLine('      if (!ol) return;');
    SB.AppendLine('      var rv = ruleSel ? ruleSel.value : ''all'';');
    SB.AppendLine('      var profileName = (rv.indexOf(''profile:'') === 0) ? rv.substring(8) : '''';');
    SB.AppendLine('      var profileDef = profileName ? PROFILES[profileName] : null;');
    SB.AppendLine('      var pool;');
    SB.AppendLine('      if (profileDef && !profileDef.all) {');
    SB.AppendLine('        pool = ALL_KINDS.filter(function(k){ return profileDef.kinds[k.n] === 1; });');
    SB.AppendLine('      } else {');
    SB.AppendLine('        pool = ALL_KINDS;');
    SB.AppendLine('      }');
    SB.AppendLine('      var topN = pool.slice(0, TOP_N);');
    SB.AppendLine('      var html = '''';');
    SB.AppendLine('      topN.forEach(function(k) {');
    SB.AppendLine('        var qfHtml = (k.qf === 1)');
    SB.AppendLine('          ? '' <span class="td-qf" title="Quick-Fix verfuegbar (Ctrl+Alt+F im IDE-Plugin)">QF</span>''');
    SB.AppendLine('          : '''';');
    SB.AppendLine('        html += ''<li data-kind="'' + k.n + ''">'' +');
    SB.AppendLine('                ''<span class="td-name">'' + k.n + ''</span> '' +');
    SB.AppendLine('                ''<span class="td-count">'' + k.c + ''</span>'' +');
    SB.AppendLine('                qfHtml + ''</li>'';');
    SB.AppendLine('      });');
    SB.AppendLine('      ol.innerHTML = html;');
    SB.AppendLine('      if (h2) h2.textContent = ''Top '' + topN.length + '' Detektoren (von '' + pool.length + '')'';');
    SB.AppendLine('      ol.querySelectorAll(''li[data-kind]'').forEach(wireTopDetectorClick);');
    SB.AppendLine('    }');
    SB.AppendLine('');
    SB.AppendLine('    // Klick auf einen Eintrag in der Top-Detektoren-Liste setzt');
    SB.AppendLine('    // den Rule-Filter auf "kind:<Name>" (Einzel-Detektor).');
    SB.AppendLine('    // Erneuter Klick auf den gleichen Eintrag setzt zurueck.');
    SB.AppendLine('    function wireTopDetectorClick(li) {');
    SB.AppendLine('      li.addEventListener(''click'', function() {');
    SB.AppendLine('        if (!ruleSel) return;');
    SB.AppendLine('        var kind = li.getAttribute(''data-kind'');');
    SB.AppendLine('        var pinned = ''kind:'' + kind;');
    SB.AppendLine('        if (ruleSel.value === pinned) {');
    SB.AppendLine('          ruleSel.value = ''all'';');
    SB.AppendLine('        } else {');
    SB.AppendLine('          var existing = ruleSel.querySelector(''option[value="'' + pinned + ''"]'');');
    SB.AppendLine('          if (!existing) {');
    SB.AppendLine('            var opt = document.createElement(''option'');');
    SB.AppendLine('            opt.value = pinned;');
    SB.AppendLine('            opt.textContent = ''Nur: '' + kind;');
    SB.AppendLine('            ruleSel.appendChild(opt);');
    SB.AppendLine('          }');
    SB.AppendLine('          ruleSel.value = pinned;');
    SB.AppendLine('        }');
    SB.AppendLine('        collapseAll();');
    SB.AppendLine('        rebuildTopDetectors();');
    SB.AppendLine('        applyFilter();');
    SB.AppendLine('      });');
    SB.AppendLine('    }');
    SB.AppendLine('    document.querySelectorAll(''.top-detectors li[data-kind]'').forEach(wireTopDetectorClick);');
    SB.AppendLine('');
    SB.AppendLine('    // ---- Klick auf Top-Datei setzt den Datei-Filter (#11) ----');
    SB.AppendLine('    // Reuse des vorhandenen Dropdown-Handlers via dispatch(''change'') -');
    SB.AppendLine('    // kein zweites Filtersystem. Falls die Option per Sev-Filter versteckt');
    SB.AppendLine('    // ist, vorher sichtbar schalten, damit die Auswahl greift.');
    SB.AppendLine('    function wireTopFileClick(li) {');
    SB.AppendLine('      li.addEventListener(''click'', function() {');
    SB.AppendLine('        if (!fileSel) return;');
    SB.AppendLine('        var fn = li.getAttribute(''data-file'');');
    SB.AppendLine('        var opt = fileSel.querySelector(''option[value="'' + fn.replace(/"/g, ''\\"'') + ''"]'');');
    SB.AppendLine('        if (opt) opt.hidden = false;');
    SB.AppendLine('        fileSel.value = fn;');
    SB.AppendLine('        fileSel.dispatchEvent(new Event(''change''));');
    SB.AppendLine('      });');
    SB.AppendLine('    }');
    SB.AppendLine('    document.querySelectorAll(''.top-files li[data-file]'').forEach(wireTopFileClick);');
    SB.AppendLine('');
    SB.AppendLine('    // ---- Datei-Dropdown auf Severity-Filter abstimmen ----');
    SB.AppendLine('    // Wenn ein Severity-Filter aktiv ist, blendet diese Funktion alle');
    SB.AppendLine('    // <option>-Eintraege aus, deren data-sev den activeSev nicht enthaelt.');
    SB.AppendLine('    // Die "Alle"-Option (value="") bleibt immer sichtbar. Wenn das aktuell');
    SB.AppendLine('    // gewaehlte File durch den Filter verschwindet, wird auf "Alle"');
    SB.AppendLine('    // zurueckgesetzt - das verhindert verwirrende leere Tabellen-Ansichten.');
    SB.AppendLine('    function applyFileDropdownVisibility() {');
    SB.AppendLine('      if (!fileSel) return;');
    SB.AppendLine('      var opts = fileSel.querySelectorAll(''option'');');
    SB.AppendLine('      var visible = 0;');
    SB.AppendLine('      for (var i = 0; i < opts.length; i++) {');
    SB.AppendLine('        var opt = opts[i];');
    SB.AppendLine('        if (!opt.value) {');
    SB.AppendLine('          // "Alle"-Option immer sichtbar lassen');
    SB.AppendLine('          opt.hidden = false;');
    SB.AppendLine('          continue;');
    SB.AppendLine('        }');
    SB.AppendLine('        if (!activeSev) {');
    SB.AppendLine('          opt.hidden = false;');
    SB.AppendLine('          visible++;');
    SB.AppendLine('          continue;');
    SB.AppendLine('        }');
    SB.AppendLine('        var ds = opt.getAttribute(''data-sev'') || '''';');
    SB.AppendLine('        var sevList = (ds.length > 0) ? ds.split('','') : [];');
    SB.AppendLine('        var match = sevList.indexOf(activeSev) !== -1;');
    SB.AppendLine('        opt.hidden = !match;');
    SB.AppendLine('        if (match) visible++;');
    SB.AppendLine('      }');
    SB.AppendLine('      // "Alle (N Dateien)" - Counter aktualisieren (i18n via T)');
    SB.AppendLine('      var allOpt = fileSel.querySelector(''option[value=""]'');');
    SB.AppendLine('      if (allOpt) {');
    SB.AppendLine('        var cnt = activeSev ? visible : (opts.length - 1);');
    SB.AppendLine('        allOpt.dataset.count = cnt;');
    SB.AppendLine('        allOpt.textContent   = T("opt-all-files", cnt);');
    SB.AppendLine('      }');
    SB.AppendLine('      // Aktuelle Auswahl unsichtbar geworden -> auf "Alle" zuruecksetzen');
    SB.AppendLine('      var sel = fileSel.selectedOptions && fileSel.selectedOptions[0];');
    SB.AppendLine('      if (sel && sel.hidden) fileSel.value = '''';');
    SB.AppendLine('    }');
    SB.AppendLine('');
    SB.AppendLine('    // Klick auf Severity-Badge filtert die Tabelle. Erneuter Klick auf');
    SB.AppendLine('    // bereits aktive Badge schaltet zurueck auf Gesamt.');
    SB.AppendLine('    document.querySelectorAll(''.sev-filter'').forEach(function(badge) {');
    SB.AppendLine('      badge.addEventListener(''click'', function() {');
    SB.AppendLine('        var newSev = badge.getAttribute(''data-sev'') || '''';');
    SB.AppendLine('        if (newSev === activeSev && newSev !== '''') {');
    SB.AppendLine('          // gleiche Badge erneut -> auf Gesamt zuruecksetzen');
    SB.AppendLine('          newSev = '''';');
    SB.AppendLine('        }');
    SB.AppendLine('        activeSev = newSev;');
    SB.AppendLine('        document.querySelectorAll(''.sev-filter'').forEach(function(b) {');
    SB.AppendLine('          var bSev = b.getAttribute(''data-sev'') || '''';');
    SB.AppendLine('          b.classList.toggle(''sev-active'', bSev === activeSev);');
    SB.AppendLine('        });');
    SB.AppendLine('        collapseAll();');
    SB.AppendLine('        applyFileDropdownVisibility();');
    SB.AppendLine('        applyFilter();');
    SB.AppendLine('      });');
    SB.AppendLine('    });');
    SB.AppendLine('');
    SB.AppendLine('    // ============================================================');
    SB.AppendLine('    // Tech-Lead-Tools: URL-Hash, Keyboard, Sprint-Export, Help-Overlay');
    SB.AppendLine('    // ============================================================');
    SB.AppendLine('');
    SB.AppendLine('    // ---- Toast: kurze Bestaetigung bei Clipboard-Aktionen ----');
    SB.AppendLine('    var toastEl = null;');
    SB.AppendLine('    function showToast(msg) {');
    SB.AppendLine('      if (!toastEl) {');
    SB.AppendLine('        toastEl = document.createElement(''div'');');
    SB.AppendLine('        toastEl.className = ''toast'';');
    SB.AppendLine('        document.body.appendChild(toastEl);');
    SB.AppendLine('      }');
    SB.AppendLine('      toastEl.textContent = msg;');
    SB.AppendLine('      toastEl.classList.add(''show'');');
    SB.AppendLine('      clearTimeout(toastEl._t);');
    SB.AppendLine('      toastEl._t = setTimeout(function() { toastEl.classList.remove(''show''); }, 1800);');
    SB.AppendLine('    }');
    SB.AppendLine('');
    SB.AppendLine('    function copyToClipboard(text) {');
    SB.AppendLine('      // Clipboard-API mit Fallback. Synchrones execCommand-Fallback fuer');
    SB.AppendLine('      // file:// Origin wo navigator.clipboard nicht immer verfuegbar ist.');
    SB.AppendLine('      if (navigator.clipboard && navigator.clipboard.writeText) {');
    SB.AppendLine('        navigator.clipboard.writeText(text).then(');
    SB.AppendLine('          function() { showToast(''In Zwischenablage kopiert''); },');
    SB.AppendLine('          function()  { fallbackCopy(text); });');
    SB.AppendLine('      } else { fallbackCopy(text); }');
    SB.AppendLine('    }');
    SB.AppendLine('    function fallbackCopy(text) {');
    SB.AppendLine('      var ta = document.createElement(''textarea'');');
    SB.AppendLine('      ta.value = text;');
    SB.AppendLine('      ta.style.position = ''fixed'';');
    SB.AppendLine('      ta.style.opacity  = ''0'';');
    SB.AppendLine('      document.body.appendChild(ta);');
    SB.AppendLine('      ta.select();');
    SB.AppendLine('      try { document.execCommand(''copy''); showToast(''In Zwischenablage kopiert''); }');
    SB.AppendLine('      catch(e) { showToast(''Kopieren fehlgeschlagen''); }');
    SB.AppendLine('      document.body.removeChild(ta);');
    SB.AppendLine('    }');
    SB.AppendLine('');
    SB.AppendLine('    // ---- URL-Hash-Sync (Sicht teilen / Bookmark-Restore) ----');
    SB.AppendLine('    // Format: #sev=err&rule=kind:fkXyz&file=foo.pas&q=text');
    SB.AppendLine('    // sev/rule/file/q sind alle optional. Tech-Lead kopiert die URL,');
    SB.AppendLine('    // schickt sie ans Team - Empfaenger oeffnet sie und sieht exakt');
    SB.AppendLine('    // den gleichen Filter-Zustand.');
    SB.AppendLine('    var suspendHashSync = false;');
    SB.AppendLine('    function syncUrlHash() {');
    SB.AppendLine('      if (suspendHashSync) return;');
    SB.AppendLine('      var parts = [];');
    SB.AppendLine('      if (activeSev) parts.push(''sev='' + encodeURIComponent(activeSev));');
    SB.AppendLine('      if (ruleSel && ruleSel.value && ruleSel.value !== ''all'')');
    SB.AppendLine('        parts.push(''rule='' + encodeURIComponent(ruleSel.value));');
    SB.AppendLine('      if (fileSel && fileSel.value)');
    SB.AppendLine('        parts.push(''file='' + encodeURIComponent(fileSel.value));');
    SB.AppendLine('      if (searchInput && searchInput.value.trim())');
    SB.AppendLine('        parts.push(''q='' + encodeURIComponent(searchInput.value.trim()));');
    SB.AppendLine('      if (confFilter && confFilter.checked) parts.push(''conf=1''); // #1');
    SB.AppendLine('      var hash = parts.length ? (''#'' + parts.join(''&'')) : ''#'';');
    SB.AppendLine('      // replaceState statt assign-to-hash, sonst rufen wir uns selbst');
    SB.AppendLine('      // via hashchange wieder auf.');
    SB.AppendLine('      try { history.replaceState(null, '''', hash); }');
    SB.AppendLine('      catch(e) { /* file:// in manchen Browsern */ }');
    SB.AppendLine('    }');
    SB.AppendLine('');
    SB.AppendLine('    function loadFromUrlHash() {');
    SB.AppendLine('      var h = location.hash.replace(/^#/, '''');');
    SB.AppendLine('      if (!h) return;');
    SB.AppendLine('      suspendHashSync = true;');
    SB.AppendLine('      try {');
    SB.AppendLine('        var params = {};');
    SB.AppendLine('        h.split(''&'').forEach(function(kv) {');
    SB.AppendLine('          var eq = kv.indexOf(''='');');
    SB.AppendLine('          if (eq < 0) return;');
    SB.AppendLine('          params[kv.substring(0, eq)] = decodeURIComponent(kv.substring(eq + 1));');
    SB.AppendLine('        });');
    SB.AppendLine('        if (params.sev) {');
    SB.AppendLine('          activeSev = params.sev;');
    SB.AppendLine('          document.querySelectorAll(''.sev-filter'').forEach(function(b) {');
    SB.AppendLine('            var bSev = b.getAttribute(''data-sev'') || '''';');
    SB.AppendLine('            b.classList.toggle(''sev-active'', bSev === activeSev);');
    SB.AppendLine('          });');
    SB.AppendLine('        }');
    SB.AppendLine('        if (params.rule && ruleSel) {');
    SB.AppendLine('          // Falls die Option noch nicht existiert (kind:X), erstellen.');
    SB.AppendLine('          var opt = ruleSel.querySelector(''option[value="'' + params.rule + ''"]'');');
    SB.AppendLine('          if (!opt && params.rule.indexOf(''kind:'') === 0) {');
    SB.AppendLine('            opt = document.createElement(''option'');');
    SB.AppendLine('            opt.value = params.rule;');
    SB.AppendLine('            opt.textContent = ''Nur: '' + params.rule.substring(5);');
    SB.AppendLine('            ruleSel.appendChild(opt);');
    SB.AppendLine('          }');
    SB.AppendLine('          if (opt) ruleSel.value = params.rule;');
    SB.AppendLine('        }');
    SB.AppendLine('        if (params.file && fileSel) {');
    SB.AppendLine('          var fopt = fileSel.querySelector(''option[value="'' + params.file.replace(/"/g, ''\\"'') + ''"]'');');
    SB.AppendLine('          if (fopt) fileSel.value = params.file;');
    SB.AppendLine('        }');
    SB.AppendLine('        if (params.q && searchInput) searchInput.value = params.q;');
    SB.AppendLine('        if (params.conf === ''1'' && confFilter) confFilter.checked = true; // #1');
    SB.AppendLine('      } finally {');
    SB.AppendLine('        suspendHashSync = false;');
    SB.AppendLine('      }');
    SB.AppendLine('      rebuildTopDetectors();');
    SB.AppendLine('      applyFileDropdownVisibility();');
    SB.AppendLine('      applyFilter();');
    SB.AppendLine('    }');
    SB.AppendLine('');
    SB.AppendLine('    // ---- Sprint-Snapshot: Top-N sichtbare Befunde als Markdown ----');
    SB.AppendLine('    // Output-Format gezielt fuer Issue-Tracker (Linear/Jira/GitHub):');
    SB.AppendLine('    //   ## Sprint-Backlog: Static Code Analysis');
    SB.AppendLine('    //   - [ ] **Error** uMainForm.pas:42 - fkNilDeref - <detail>');
    SB.AppendLine('    //   ...');
    SB.AppendLine('    // Plus Top-N Detektor-Aggregat fuer Sprint-Themen.');
    SB.AppendLine('    function buildSprintMarkdown() {');
    SB.AppendLine('      var MAX = 20; // Top-20 ist eine machbare Sprint-Liste');
    SB.AppendLine('      var rows = Array.from(document.querySelectorAll(''tr.finding''))');
    SB.AppendLine('        .filter(function(r) { return r.style.display !== ''none''; });');
    SB.AppendLine('      // Severity-Reihenfolge: rows sind schon sortiert via sortBy(''sev''),');
    SB.AppendLine('      // falls aber der User umgesortet hat: explizit nach Rang sortieren');
    SB.AppendLine('      // (Errors zuerst, fuer das Sprint-Backlog ist das die richtige Prio).');
    SB.AppendLine('      rows.sort(function(a, b) {');
    SB.AppendLine('        var ra = parseInt(a.querySelector(''td.sev'').getAttribute(''data-sort''), 10) || 9;');
    SB.AppendLine('        var rb = parseInt(b.querySelector(''td.sev'').getAttribute(''data-sort''), 10) || 9;');
    SB.AppendLine('        return ra - rb;');
    SB.AppendLine('      });');
    SB.AppendLine('      var picks = rows.slice(0, MAX);');
    SB.AppendLine('      var md = ''## Sprint-Backlog: Static Code Analysis\n\n'';');
    SB.AppendLine('      md += T("sprint-header", rows.length, picks.length) + ''\n\n'';');
    SB.AppendLine('      picks.forEach(function(r) {');
    SB.AppendLine('        var sev    = r.querySelector(''td.sev'') ? r.querySelector(''td.sev'').textContent.trim() : '''';');
    SB.AppendLine('        var file   = r.getAttribute(''data-file'') || '''';');
    SB.AppendLine('        var rule   = r.getAttribute(''data-rule'') || '''';');
    SB.AppendLine('        var qf     = (QF_KINDS[rule] === 1) ? '' [QF]'' : '''';');
    SB.AppendLine('        // Spalten-Reihenfolge: Toggle | (Datei?) | Sev | Typ | Zeile | Methode | Regel | Detail');
    SB.AppendLine('        var cells  = r.children;');
    SB.AppendLine('        var lineIdx   = colIndex.line;');
    SB.AppendLine('        var methIdx   = colIndex.method;');
    SB.AppendLine('        var detIdx    = colIndex.detail;');
    SB.AppendLine('        var line   = cells[lineIdx] ? cells[lineIdx].textContent.trim() : '''';');
    SB.AppendLine('        var meth   = cells[methIdx] ? cells[methIdx].textContent.trim() : '''';');
    SB.AppendLine('        var det    = cells[detIdx]  ? cells[detIdx].textContent.trim()  : '''';');
    SB.AppendLine('        // Detail koennte mehrere Saetze haben - auf 160 Zeichen kuerzen.');
    SB.AppendLine('        if (det.length > 160) det = det.substring(0, 157) + ''...'';');
    SB.AppendLine('        md += ''- [ ] **'' + sev + ''** `'' + file + '':'' + line + ''`'';');
    SB.AppendLine('        if (meth) md += '' in `'' + meth + ''()`'';');
    SB.AppendLine('        md += '' - '' + rule + qf + '' - '' + det + ''\n'';');
    SB.AppendLine('      });');
    SB.AppendLine('      // Detektor-Aggregat fuer Sprint-Themen.');
    SB.AppendLine('      var byKind = {};');
    SB.AppendLine('      rows.forEach(function(r) {');
    SB.AppendLine('        var k = r.getAttribute(''data-rule'') || '''';');
    SB.AppendLine('        byKind[k] = (byKind[k] || 0) + 1;');
    SB.AppendLine('      });');
    SB.AppendLine('      var aggList = Object.keys(byKind).map(function(k) { return {n:k, c:byKind[k]}; });');
    SB.AppendLine('      aggList.sort(function(a, b) { return b.c - a.c; });');
    SB.AppendLine('      var qfAgg = aggList.filter(function(k){ return QF_KINDS[k.n] === 1; });');
    SB.AppendLine('      if (qfAgg.length) {');
    SB.AppendLine('        md += ''\n### Quick-Wins (Ctrl+Alt+F im IDE-Plugin)\n\n'';');
    SB.AppendLine('        qfAgg.slice(0, 10).forEach(function(k) {');
    SB.AppendLine('          md += ''- [ ] '' + k.n + '' ('' + k.c + '' Vorkommen)\n'';');
    SB.AppendLine('        });');
    SB.AppendLine('      }');
    SB.AppendLine('      return md;');
    SB.AppendLine('    }');
    SB.AppendLine('');
    SB.AppendLine('    var btnSprint = document.getElementById(''btnSprintCopy'');');
    SB.AppendLine('    if (btnSprint) btnSprint.addEventListener(''click'', function() {');
    SB.AppendLine('      copyToClipboard(buildSprintMarkdown());');
    SB.AppendLine('    });');
    SB.AppendLine('');
    SB.AppendLine('    var btnShare = document.getElementById(''btnShareLink'');');
    SB.AppendLine('    if (btnShare) btnShare.addEventListener(''click'', function() {');
    SB.AppendLine('      syncUrlHash(); // sicherstellen dass der aktuelle Zustand drin ist');
    SB.AppendLine('      copyToClipboard(location.href);');
    SB.AppendLine('    });');
    SB.AppendLine('');
    SB.AppendLine('    // ---- Keyboard-Shortcuts ----');
    SB.AppendLine('    // 1/2/3   - Severity-Filter (Error/Warning/Hint)');
    SB.AppendLine('    // 0       - alle Severities');
    SB.AppendLine('    // /       - Suche fokussieren');
    SB.AppendLine('    // Esc     - Filter zuruecksetzen (oder Suche leeren)');
    SB.AppendLine('    // ?       - Shortcuts-Hilfe');
    SB.AppendLine('    function activateSev(sev) {');
    SB.AppendLine('      activeSev = sev;');
    SB.AppendLine('      document.querySelectorAll(''.sev-filter'').forEach(function(b) {');
    SB.AppendLine('        var bSev = b.getAttribute(''data-sev'') || '''';');
    SB.AppendLine('        b.classList.toggle(''sev-active'', bSev === activeSev);');
    SB.AppendLine('      });');
    SB.AppendLine('      collapseAll();');
    SB.AppendLine('      applyFileDropdownVisibility();');
    SB.AppendLine('      applyFilter();');
    SB.AppendLine('    }');
    SB.AppendLine('    function resetAllFilters() {');
    SB.AppendLine('      if (ruleSel) ruleSel.value = ''all'';');
    SB.AppendLine('      if (fileSel) fileSel.value = '''';');
    SB.AppendLine('      if (searchInput) searchInput.value = '''';');
    SB.AppendLine('      if (confFilter) confFilter.checked = false; // #1');
    SB.AppendLine('      activateSev('''');');
    SB.AppendLine('      rebuildTopDetectors();');
    SB.AppendLine('    }');
    SB.AppendLine('    document.addEventListener(''keydown'', function(e) {');
    SB.AppendLine('      // Wenn der User in einem Input-Feld tippt: nur Esc abfangen,');
    SB.AppendLine('      // alles andere durchlassen (sonst kann er kein "1" ins Search-Feld).');
    SB.AppendLine('      var inField = (e.target.tagName === ''INPUT'' || e.target.tagName === ''TEXTAREA'' || e.target.tagName === ''SELECT'');');
    SB.AppendLine('      if (e.key === ''Escape'') {');
    SB.AppendLine('        if (kbdOverlay && kbdOverlay.classList.contains(''open'')) { closeKbdHelp(); return; }');
    SB.AppendLine('        if (inField && e.target === searchInput) {');
    SB.AppendLine('          if (searchInput.value) { searchInput.value = ''''; applyFilter(); return; }');
    SB.AppendLine('          searchInput.blur(); return;');
    SB.AppendLine('        }');
    SB.AppendLine('        resetAllFilters();');
    SB.AppendLine('        return;');
    SB.AppendLine('      }');
    SB.AppendLine('      if (inField) return;');
    SB.AppendLine('      if (e.key === ''1'') { activateSev(activeSev === ''err''  ? '''' : ''err''); }');
    SB.AppendLine('      else if (e.key === ''2'') { activateSev(activeSev === ''warn'' ? '''' : ''warn''); }');
    SB.AppendLine('      else if (e.key === ''3'') { activateSev(activeSev === ''hint'' ? '''' : ''hint''); }');
    SB.AppendLine('      else if (e.key === ''0'') { activateSev(''''); }');
    SB.AppendLine('      else if (e.key === ''/'') { e.preventDefault(); if (searchInput) searchInput.focus(); }');
    SB.AppendLine('      else if (e.key === ''?'') { openKbdHelp(); }');
    SB.AppendLine('    });');
    SB.AppendLine('');
    SB.AppendLine('    // ---- Help-Overlay (lazy gebaut, oeffnen via ? / Button) ----');
    SB.AppendLine('    var kbdOverlay = null, kbdHelp = null;');
    SB.AppendLine('    function ensureKbdHelp() {');
    SB.AppendLine('      if (kbdHelp) return;');
    SB.AppendLine('      kbdOverlay = document.createElement(''div'');');
    SB.AppendLine('      kbdOverlay.className = ''kbd-overlay'';');
    SB.AppendLine('      kbdOverlay.addEventListener(''click'', closeKbdHelp);');
    SB.AppendLine('      kbdHelp = document.createElement(''div'');');
    SB.AppendLine('      kbdHelp.className = ''kbd-help'';');
    SB.AppendLine('      kbdHelp.innerHTML = ');
    SB.AppendLine('        ''<button class="kbd-help-close" title="'' + T("kbd-help-close") + ''">&times;</button>'' +');
    SB.AppendLine('        ''<h3>'' + T("kbd-help-title") + ''</h3>'' +');
    SB.AppendLine('        ''<table>'' +');
    SB.AppendLine('        ''<tr><td class="k"><kbd>1</kbd></td><td>nur Fehler</td></tr>'' +');
    SB.AppendLine('        ''<tr><td class="k"><kbd>2</kbd></td><td>nur Warnungen</td></tr>'' +');
    SB.AppendLine('        ''<tr><td class="k"><kbd>3</kbd></td><td>nur Hinweise</td></tr>'' +');
    SB.AppendLine('        ''<tr><td class="k"><kbd>0</kbd></td><td>alle Severities</td></tr>'' +');
    SB.AppendLine('        ''<tr><td class="k"><kbd>/</kbd></td><td>Suche fokussieren</td></tr>'' +');
    SB.AppendLine('        ''<tr><td class="k"><kbd>Esc</kbd></td><td>Filter zuruecksetzen</td></tr>'' +');
    SB.AppendLine('        ''<tr><td class="k"><kbd>?</kbd></td><td>diese Hilfe</td></tr>'' +');
    SB.AppendLine('        ''</table>'';');
    SB.AppendLine('      kbdHelp.querySelector(''.kbd-help-close'').addEventListener(''click'', closeKbdHelp);');
    SB.AppendLine('      document.body.appendChild(kbdOverlay);');
    SB.AppendLine('      document.body.appendChild(kbdHelp);');
    SB.AppendLine('    }');
    SB.AppendLine('    function openKbdHelp()  { ensureKbdHelp(); kbdOverlay.classList.add(''open''); kbdHelp.classList.add(''open''); }');
    SB.AppendLine('    function closeKbdHelp() { if (kbdOverlay) kbdOverlay.classList.remove(''open''); if (kbdHelp) kbdHelp.classList.remove(''open''); }');
    SB.AppendLine('    var btnHelp = document.getElementById(''btnKbdHelp'');');
    SB.AppendLine('    if (btnHelp) btnHelp.addEventListener(''click'', openKbdHelp);');
    SB.AppendLine('');
    SB.AppendLine('    // ---- Initialer Sort: Severity (Fehler -> Hinweis) ----');
    SB.AppendLine('    // Tech-Lead-Default: hoechstes Risiko zuerst. data-sort der Sev-Spalte');
    SB.AppendLine('    // ist der numerische Rang (0=Error, 1=Warning, 2=Hint, 3=Read-Error),');
    SB.AppendLine('    // sortBy(''sev'') sortiert asc und stellt damit Errors an den Anfang.');
    SB.AppendLine('    sortBy(''sev'');');
    SB.AppendLine('');
    SB.AppendLine('    // URL-Hash beim Laden auswerten - wenn die Seite mit Filter-Hash');
    SB.AppendLine('    // geoeffnet wurde, stellt das die Sicht wieder her.');
    SB.AppendLine('    loadFromUrlHash();');
    SB.AppendLine('');
    SB.AppendLine('    // ---- i18n: initiale Sprache anwenden + Listener auf langSelect ----');
    SB.AppendLine('    applyLanguage(SCA_LANG);');
    SB.AppendLine('    var langSel = document.getElementById("langSelect");');
    SB.AppendLine('    if (langSel) langSel.addEventListener("change", function(){ applyLanguage(this.value); });');
    // #9 Dark-Mode: gespeicherte Wahl oder OS-Praeferenz anwenden + Toggle.
    SB.AppendLine('    (function(){');
    SB.AppendLine('      var KEY = "sca-html-theme";');
    SB.AppendLine('      function apply(t){ document.documentElement.setAttribute("data-theme", t); }');
    SB.AppendLine('      var stored = null; try { stored = localStorage.getItem(KEY); } catch(e){}');
    SB.AppendLine('      apply(stored || ((window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches) ? "dark" : "light"));');
    SB.AppendLine('      var bt = document.getElementById("btnTheme");');
    SB.AppendLine('      if (bt) bt.addEventListener("click", function(){');
    SB.AppendLine('        var cur = document.documentElement.getAttribute("data-theme") === "dark" ? "light" : "dark";');
    SB.AppendLine('        apply(cur); try { localStorage.setItem(KEY, cur); } catch(e){}');
    SB.AppendLine('      });');
    SB.AppendLine('    })();');
    // #8 A11y: Custom-Controls fokussierbar + Tastatur (Enter/Space) + aria-live.
    SB.AppendLine('    (function(){');
    SB.AppendLine('      var SEL = ".sev-filter, th.sortable, .top-detectors li[data-kind], .top-files li[data-file]";');
    SB.AppendLine('      document.querySelectorAll(".sev-filter, .top-detectors li[data-kind], .top-files li[data-file]").forEach(function(el){');
    SB.AppendLine('        el.setAttribute("tabindex","0"); el.setAttribute("role","button"); });');
    SB.AppendLine('      document.querySelectorAll("th.sortable").forEach(function(el){ el.setAttribute("tabindex","0"); });');
    SB.AppendLine('      document.addEventListener("keydown", function(e){');
    SB.AppendLine('        if ((e.key === "Enter" || e.key === " ") && e.target && e.target.matches && e.target.matches(SEL)) {');
    SB.AppendLine('          e.preventDefault(); e.target.click(); }');
    SB.AppendLine('      });');
    SB.AppendLine('      var rc = document.getElementById("rowCount");');
    SB.AppendLine('      if (rc) { rc.setAttribute("aria-live","polite"); rc.setAttribute("role","status"); }');
    SB.AppendLine('    })();');
    // #7 Baseline-Diff: speichern (Download aller data-fpid) + laden (FileReader
    // -> Set -> Zeilen als neu/bestehend markieren + Summary + "nur NEU"-Filter).
    // Rein client-seitig (Blob/FileReader/localStorage-frei) -> HTML deterministisch.
    SB.AppendLine('    (function(){');
    SB.AppendLine('      function allFpids(){ var a=[]; document.querySelectorAll("tr.finding[data-fpid]").forEach(function(r){ a.push(r.getAttribute("data-fpid")); }); return a; }');
    SB.AppendLine('      var bs = document.getElementById("btnBaseSave");');
    SB.AppendLine('      if (bs) bs.addEventListener("click", function(){');
    SB.AppendLine('        var data = JSON.stringify({ tool: "StaticCodeAnalyser", fpids: allFpids() });');
    SB.AppendLine('        var blob = new Blob([data], { type: "application/json" });');
    SB.AppendLine('        var a = document.createElement("a"); a.href = URL.createObjectURL(blob); a.download = "sca-baseline.json";');
    SB.AppendLine('        document.body.appendChild(a); a.click(); document.body.removeChild(a); URL.revokeObjectURL(a.href);');
    SB.AppendLine('      });');
    SB.AppendLine('      var TPL = { en: "Baseline: {0} new, {1} existing, {2} fixed", de: "Baseline: {0} neu, {1} bestehend, {2} behoben", fr: "Base: {0} nouveaux, {1} existants, {2} corrig\\u00e9s" };');
    SB.AppendLine('      var bf = document.getElementById("baseFile");');
    SB.AppendLine('      if (bf) bf.addEventListener("change", function(){');
    SB.AppendLine('        var f = bf.files && bf.files[0]; if (!f) return;');
    SB.AppendLine('        var rd = new FileReader();');
    SB.AppendLine('        rd.onload = function(){');
    SB.AppendLine('          var base; try { base = JSON.parse(rd.result); } catch(e){ return; }');
    SB.AppendLine('          var arr = (base && base.fpids) ? base.fpids : (Array.isArray(base) ? base : []);');
    SB.AppendLine('          var set = {}; arr.forEach(function(id){ set[id] = 1; });');
    SB.AppendLine('          var seenNow = {}, nNew = 0, nExist = 0;');
    SB.AppendLine('          document.querySelectorAll("tr.finding[data-fpid]").forEach(function(r){');
    SB.AppendLine('            var id = r.getAttribute("data-fpid"); seenNow[id] = 1;');
    SB.AppendLine('            if (set[id]) { r.setAttribute("data-bstatus","seen"); nExist++; }');
    SB.AppendLine('            else { r.setAttribute("data-bstatus","new"); nNew++; }');
    SB.AppendLine('          });');
    SB.AppendLine('          var nFixed = 0; arr.forEach(function(id){ if (!seenNow[id]) nFixed++; });');
    SB.AppendLine('          var bn = document.getElementById("baseNewFilter"); if (bn) bn.disabled = false;');
    SB.AppendLine('          var sm = document.getElementById("baseSummary");');
    SB.AppendLine('          if (sm) { var lang = document.documentElement.lang || "de"; var tpl = TPL[lang] || TPL.de;');
    SB.AppendLine('            sm.textContent = tpl.replace("{0}", nNew).replace("{1}", nExist).replace("{2}", nFixed); }');
    SB.AppendLine('          if (typeof applyFilters === "function") applyFilters();');
    SB.AppendLine('        };');
    SB.AppendLine('        rd.readAsText(f);');
    SB.AppendLine('      });');
    SB.AppendLine('      var bnf = document.getElementById("baseNewFilter");');
    SB.AppendLine('      if (bnf) bnf.addEventListener("change", function(){ if (typeof applyFilters === "function") applyFilters(); });');
    SB.AppendLine('    })();');
    // #14 Security-Panel-Button: aktiviert den bestehenden sec-Filter (#3).
    SB.AppendLine('    (function(){');
    SB.AppendLine('      var b = document.getElementById("btnShowSec"); var rs = document.getElementById("ruleFilter");');
    SB.AppendLine('      if (b && rs) b.addEventListener("click", function(){ rs.value = "sec"; rs.dispatchEvent(new Event("change")); });');
    SB.AppendLine('    })();');
    SB.AppendLine('  })();');
    SB.AppendLine('  </script>');
    SB.AppendLine('</body>');
    SB.AppendLine('</html>');

    SL := TStringList.Create;
    try
      SL.Text := SB.ToString;
      TExporter.SaveUtf8WithBom(SL, FileName);
    finally
      SL.Free;
    end;
  finally
    SB.Free;
  end;
  finally
    Files.Free;
    FilesSev.Free;
    SourceCache.Free;
    KindCount.Free;
    KindPairs.Free;
    Top10Set.Free;
    FileAgg.Free;
    FileRank.Free;
  end;
end;

end.
