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
  System.SysUtils, System.Classes, System.Generics.Collections,
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

uses
  uExport, uFixHint;

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
  try
    Files := TStringList.Create;
    Files.Duplicates := dupIgnore;
    Files.Sorted := True;
    Files.CaseSensitive := False;
    FilesSev := TDictionary<string, Cardinal>.Create;
    SourceCache := TObjectDictionary<string, TStringList>.Create([doOwnsValues]);
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

  SB := TStringBuilder.Create;
  try
    SB.AppendLine('<!DOCTYPE html>');
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
    SB.AppendLine('  </style>');
    SB.AppendLine('</head>');
    SB.AppendLine('<body>');
    SB.Append    ('  <h1>'); SB.Append(HtmlEscape(Title)); SB.AppendLine('</h1>');
    SB.Append    ('  <div class="meta">Erstellt: ');
    SB.Append    (HtmlEscape(FormatDateTime('yyyy-mm-dd hh:nn', Now)));
    if SourceFile <> '' then
    begin
      SB.Append('  &middot; Datei: ');
      SB.Append(HtmlEscape(SourceFile));
    end;
    SB.AppendLine('</div>');

    SB.AppendLine('  <div class="summary">');
    // Klickbare Severity-Badges - data-sev gibt den Wert fuer den JS-Filter
    // ("err"/"warn"/"hint"/"" fuer alle).
    SB.AppendLine('    <div class="badge b-err sev-filter" data-sev="err"><b>'  + IntToStr(nErr)  + '</b>Fehler</div>');
    SB.AppendLine('    <div class="badge b-warn sev-filter" data-sev="warn"><b>' + IntToStr(nWarn) + '</b>Warnungen</div>');
    SB.AppendLine('    <div class="badge b-hint sev-filter" data-sev="hint"><b>' + IntToStr(nHint) + '</b>Hinweise</div>');
    SB.AppendLine('    <div class="badge b-tot sev-filter sev-active" data-sev=""><b>'  + IntToStr(nTotal)+ '</b>Gesamt</div>');
    SB.AppendLine('  </div>');

    // Controls-Bar mit Datei-Filter (zeigt alle eindeutigen Dateinamen).
    SB.AppendLine('  <div class="controls">');
    SB.AppendLine('    <label for="fileFilter">Datei:</label>');
    SB.AppendLine('    <select id="fileFilter">');
    SB.Append    ('      <option value="">Alle (');
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
    SB.Append    ('    <span class="row-count" id="rowCount">');
    SB.Append    (IntToStr(nTotal));
    SB.AppendLine(' Befunde</span>');
    SB.AppendLine('    <span class="hint">Klick auf Spaltentitel sortiert, Klick auf Befund-Zeile zeigt Hinweis.</span>');
    SB.AppendLine('  </div>');

    SB.AppendLine('  <table id="findingsTable">');
    SB.AppendLine('    <thead><tr>');
    SB.AppendLine('      <th></th>'); // Toggle-Spalte (nicht sortierbar)
    if SourceFile = '' then
      SB.AppendLine('      <th class="sortable" data-col="file">Datei<span class="sort-ind"></span></th>');
    SB.AppendLine('      <th class="sortable" data-col="sev">Severity<span class="sort-ind"></span></th>');
    SB.AppendLine('      <th class="sortable" data-col="type">Typ<span class="sort-ind"></span></th>');
    SB.AppendLine('      <th class="sortable num" data-col="line">Zeile<span class="sort-ind"></span></th>');
    SB.AppendLine('      <th class="sortable" data-col="method">Methode<span class="sort-ind"></span></th>');
    SB.AppendLine('      <th class="sortable" data-col="rule">Regel<span class="sort-ind"></span></th>');
    SB.AppendLine('      <th class="sortable" data-col="detail">Detail<span class="sort-ind"></span></th>');
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

        // Sichtbare Befund-Zeile - data-file fuer Filter, ganze Zeile klickbar
        SB.Append('      <tr class="finding ' + SevCl + '" data-file="');
        SB.Append(HtmlEscape(FileShort));
        SB.Append('" data-base="');
        SB.Append(HtmlEscape(FileBase));
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

          // Echter Code-Auszug aus der Quelldatei mit hervorgehobener Zeile
          if Snippet <> '' then
          begin
            SB.Append('<div class="src-snippet-hdr">Quelle: ');
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
              SB.Append('<div class="code-block code-before"><h5>Vorher (Problem)</h5><pre>');
              SB.Append(HtmlEscape(Hint.Before));
              SB.Append('</pre></div>');
            end;
            if Hint.After <> '' then
            begin
              SB.Append('<div class="code-block code-after"><h5>Nachher (Loesung)</h5><pre>');
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
    SB.AppendLine('  (function() {');
    SB.AppendLine('    var table  = document.getElementById(''findingsTable'');');
    SB.AppendLine('    var tbody  = table.querySelector(''tbody'');');
    SB.AppendLine('    var rowCnt = document.getElementById(''rowCount'');');
    SB.AppendLine('    var fileSel = document.getElementById(''fileFilter'');');
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
    SB.AppendLine('    // Spalten-Index der sortierten Spalte im finding-tr (ohne Toggle).');
    SB.AppendLine('    // Mit Datei-Spalte: 0=Datei,1=Sev,2=Typ,3=Zeile,4=Methode,5=Regel,6=Detail');
    SB.AppendLine('    // Ohne Datei-Spalte verschiebt sich um 1.');
    SB.AppendLine('    var hasFile = !!table.querySelector(''th[data-col="file"]'');');
    SB.AppendLine('    var COL_OFFSET = hasFile ? 1 : 0; // Toggle-Spalte');
    SB.AppendLine('    var colIndex = {');
    SB.AppendLine('      file:   COL_OFFSET + 0,');
    SB.AppendLine('      sev:    COL_OFFSET + (hasFile ? 1 : 0),');
    SB.AppendLine('      type:   COL_OFFSET + (hasFile ? 2 : 1),');
    SB.AppendLine('      line:   COL_OFFSET + (hasFile ? 3 : 2),');
    SB.AppendLine('      method: COL_OFFSET + (hasFile ? 4 : 3),');
    SB.AppendLine('      rule:   COL_OFFSET + (hasFile ? 5 : 4),');
    SB.AppendLine('      detail: COL_OFFSET + (hasFile ? 6 : 5)');
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
    SB.AppendLine('    function applyFilter() {');
    SB.AppendLine('      var fileVal = fileSel ? fileSel.value : '''';');
    SB.AppendLine('      // Gruppen-Filter: "base:<Basename>" matcht alle Files mit gleichem');
    SB.AppendLine('      // Basename (z.B. uMainForm.pas + uMainForm.dfm). Sonst exact match.');
    SB.AppendLine('      var isGroup = fileVal && fileVal.indexOf(''base:'') === 0;');
    SB.AppendLine('      var groupVal = isGroup ? fileVal.substring(5) : '''';');
    SB.AppendLine('      var visible = 0;');
    SB.AppendLine('      document.querySelectorAll(''tr.finding'').forEach(function(row) {');
    SB.AppendLine('        var fileOk;');
    SB.AppendLine('        if (!fileVal) fileOk = true;');
    SB.AppendLine('        else if (isGroup) fileOk = row.getAttribute(''data-base'') === groupVal;');
    SB.AppendLine('        else fileOk = row.getAttribute(''data-file'') === fileVal;');
    SB.AppendLine('        var sevOk  = !activeSev || row.classList.contains(activeSev);');
    SB.AppendLine('        var match  = fileOk && sevOk;');
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
    SB.AppendLine('      if (rowCnt) rowCnt.textContent = visible + '' Befunde'';');
    SB.AppendLine('    }');
    SB.AppendLine('    if (fileSel) fileSel.addEventListener(''change'', function() {');
    SB.AppendLine('      collapseAll();');
    SB.AppendLine('      applyFilter();');
    SB.AppendLine('    });');
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
    SB.AppendLine('      // "Alle (N Dateien)" - Counter aktualisieren');
    SB.AppendLine('      var allOpt = fileSel.querySelector(''option[value=""]'');');
    SB.AppendLine('      if (allOpt) {');
    SB.AppendLine('        if (activeSev)');
    SB.AppendLine('          allOpt.textContent = ''Alle ('' + visible + '' Dateien)'';');
    SB.AppendLine('        else');
    SB.AppendLine('          allOpt.textContent = ''Alle ('' + (opts.length - 1) + '' Dateien)'';');
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
  end;
end;

end.
