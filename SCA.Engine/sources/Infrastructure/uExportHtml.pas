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
  end;

implementation

// noinspection-file StringConcatInLoop
// HTML-Export baut HTML-Fragmente pro Finding via String-Concat - typische
// Findings-Liste ist klein (~100-500 Eintraege), kein Perf-Hot-Path.

uses
  uExport, uFixHint, uRuleCatalog, uQuickFix;

class function TExporterHtml.DefaultFileName(const SourceFile: string;
  const TargetDir: string): string;
var
  Base, DateStr: string;
begin
  if SourceFile = '' then
    Base := 'analyse'
  else
    Base := ChangeFileExt(ExtractFileName(SourceFile), '');
  DateStr := FormatDateTime('yyyy-mm-dd', Now);
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

class procedure TExporterHtml.Run(Findings: TObjectList<TLeakFinding>;
  const SourceFile: string; const FileName: string);
const
  SNIPPET_CONTEXT = 3;  // Zeilen vor und nach der Befund-Zeile
  TOP_DETECTORS_N = 10; // Anzahl Eintraege in der Top-Liste und im "Top10"-Filter
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
  try
    Files := TStringList.Create;
    Files.Duplicates := dupIgnore;
    Files.Sorted := True;
    Files.CaseSensitive := False;
    FilesSev := TDictionary<string, Cardinal>.Create;
    SourceCache := TObjectDictionary<string, TStringList>.Create([doOwnsValues]);
    KindCount := TDictionary<TFindingKind, Integer>.Create;
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
    SB.AppendLine('  </style>');
    SB.AppendLine('</head>');
    SB.AppendLine('<body>');
    SB.Append    ('  <h1>'); SB.Append(HtmlEscape(Title)); SB.AppendLine('</h1>');
    // meta-Zeile mit zwei i18n-Spans + datums-Daten als Attribute, damit
    // applyLanguage die "Erstellt:" / "Datei:"-Labels neu rendern kann
    // (die Werte selbst sind dynamisch und stehen in data-* drin).
    SB.Append    ('  <div class="meta"><span data-i18n="meta-created" data-when="');
    SB.Append    (HtmlEscape(FormatDateTime('yyyy-mm-dd hh:nn', Now)));
    SB.Append    ('">Erstellt: ');
    SB.Append    (HtmlEscape(FormatDateTime('yyyy-mm-dd hh:nn', Now)));
    SB.Append    ('</span>');
    if SourceFile <> '' then
    begin
      SB.Append('  &middot; <span data-i18n="meta-file" data-file="');
      SB.Append(HtmlEscape(SourceFile));
      SB.Append('">Datei: ');
      SB.Append(HtmlEscape(SourceFile));
      SB.Append('</span>');
    end;
    SB.AppendLine('</div>');

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

      // Gruppen-Optionen zuerst (nur wenn mind. 2 Files mit gleichem Base)
      for var BasePair in Bases do
        if BasePair.Value >= 2 then
        begin
          var GAcc : Cardinal := 0; BasesSev.TryGetValue(BasePair.Key, GAcc);
          DataSev := '';
          if (GAcc and 1) <> 0 then DataSev := DataSev + 'err,';
          if (GAcc and 2) <> 0 then DataSev := DataSev + 'warn,';
          if (GAcc and 4) <> 0 then DataSev := DataSev + 'hint,';
          if DataSev <> '' then
            SetLength(DataSev, Length(DataSev) - 1);

          SB.Append('      <option value="base:');
          SB.Append(HtmlEscape(BasePair.Key));
          SB.Append('" data-sev="');
          SB.Append(DataSev);
          SB.Append('">[+] ');
          SB.Append(HtmlEscape(BasePair.Key));
          SB.Append(' (.pas + .dfm)</option>'#13#10);
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
        var HasHint := (Hint.Description <> '') or
                       (Hint.Before <> '') or (Hint.After <> '') or
                       (Snippet <> '');
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
        SB.Append('      <tr class="finding ' + SevCl + '" data-file="');
        SB.Append(HtmlEscape(FileShort));
        SB.Append('" data-base="');
        SB.Append(HtmlEscape(FileBase));
        SB.Append('" data-rule="');
        SB.Append(HtmlEscape(KindNm));
        SB.Append('" data-search="');
        SB.Append(HtmlEscape(SearchBlob));
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
          // colspan = 7 oder 8 je nachdem ob Datei-Spalte da ist
          var Cols := 7;
          if SourceFile = '' then Cols := 8;
          SB.Append('      <tr class="finding-hint"><td colspan="' + IntToStr(Cols) + '">');
          if Hint.Description <> '' then
          begin
            SB.Append('<div class="hint-desc">');
            SB.Append(HtmlEscape(Hint.Description));
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
    SB.AppendLine('        "audience-hint": "<b>Optimised for Tech-Lead / Senior-Dev review</b> &middot; refactoring prioritisation. Start at the top with the Top Detectors (highest volume, <span class=\"td-qf\">QF</span> = quick-fix available); the table is sorted by severity (Errors &rarr; Hints).",');
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
    SB.AppendLine('        "audience-hint": "<b>Optimiert fuer Tech-Lead / Senior-Dev Review</b> &middot; Refactoring-Priorisierung. Starte oben mit den Top-Detektoren (groesstes Volumen, <span class=\"td-qf\">QF</span> = Quick-Fix vorhanden), die Tabelle ist nach Severity sortiert (Fehler &rarr; Hinweis).",');
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
    SB.AppendLine('        "audience-hint": "<b>Optimis\\u00e9 pour la revue Tech-Lead / Senior-Dev</b> &middot; priorisation du refactoring. Commencez par les Top D\\u00e9tecteurs (volume le plus important, <span class=\"td-qf\">QF</span> = quick-fix disponible)\\u00a0; le tableau est tri\\u00e9 par s\\u00e9v\\u00e9rit\\u00e9 (erreurs &rarr; indices).",');
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
    SB.AppendLine('    //   Multi-File:  Toggle=0, Datei=1, Sev=2, Typ=3, Zeile=4, Methode=5, Regel=6, Detail=7');
    SB.AppendLine('    //   Single-File: Toggle=0,           Sev=1, Typ=2, Zeile=3, Methode=4, Regel=5, Detail=6');
    SB.AppendLine('    var hasFile = !!table.querySelector(''th[data-col="file"]'');');
    SB.AppendLine('    var SEV_BASE = hasFile ? 2 : 1; // erste Spalte nach Toggle (+ ggf. Datei)');
    SB.AppendLine('    var colIndex = {');
    SB.AppendLine('      file:   1, // nur valide wenn hasFile - sortBy(''file'') wird nur wired wenn die Spalte existiert');
    SB.AppendLine('      sev:    SEV_BASE + 0,');
    SB.AppendLine('      type:   SEV_BASE + 1,');
    SB.AppendLine('      line:   SEV_BASE + 2,');
    SB.AppendLine('      method: SEV_BASE + 3,');
    SB.AppendLine('      rule:   SEV_BASE + 4,');
    SB.AppendLine('      detail: SEV_BASE + 5');
    SB.AppendLine('    };');
    SB.AppendLine('    var numericCols = { line: true, sev: true };');
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
    SB.AppendLine('        else if (profileDef)                ruleOk = profileDef.all || (profileDef.kinds[rk] === 1);');
    SB.AppendLine('        else ruleOk = true; // ''all''');
    SB.AppendLine('        // Volltextsuche - matched gegen data-search (Methode + Datei + Detail + Regel).');
    SB.AppendLine('        var searchOk = !q || ((row.getAttribute(''data-search'') || '''').indexOf(q) !== -1);');
    SB.AppendLine('        // Master-Scope = fileOk && ruleOk && searchOk (ohne sev). Daraus die Kacheln.');
    SB.AppendLine('        if (fileOk && ruleOk && searchOk) {');
    SB.AppendLine('          if      (row.classList.contains(''err''))  nErr++;');
    SB.AppendLine('          else if (row.classList.contains(''warn'')) nWarn++;');
    SB.AppendLine('          else if (row.classList.contains(''hint'')) nHint++;');
    SB.AppendLine('        }');
    SB.AppendLine('        var match  = fileOk && sevOk && ruleOk && searchOk;');
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
  end;
end;

end.
