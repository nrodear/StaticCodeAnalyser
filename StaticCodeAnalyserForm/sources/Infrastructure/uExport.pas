unit uExport;

// Export von TLeakFinding-Listen in verschiedenen Formaten:
//   - CSV   (Semikolon-getrennt, fuer deutsches Excel direkt lesbar)
//   - JSON  (Array von Objekten)
//   - Jira  (Wiki-Markup, fuer Tickets)
//   - HTML  (Self-contained Code-Review-Report)
//
// CSV/JSON/HTML werden als UTF-8 mit BOM gespeichert. WICHTIG: in Delphi 12
// ist die Singleton TEncoding.UTF8 mit FUseBOM=False konfiguriert -
// SaveToFile mit dieser schreibt KEIN BOM. Wir verwenden deshalb den
// SaveUtf8WithBom-Helper der ein TUTF8Encoding(UseBOM:=True) erzeugt.
// BOM ist erforderlich damit deutsches Excel CSVs als UTF-8 erkennt
// (sonst werden Umlaute/Sonderzeichen falsch dargestellt).

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12, uFixHint;

type
  // Bitset zur Severity-Auswahl beim Jira-/Clipboard-Export.
  TSeverityFilter = set of TLeakSeverity;

  TExporter = class
  public
    class procedure ExportCsv(Findings: TObjectList<TLeakFinding>;
      const FileName: string); static;
    class procedure ExportJson(Findings: TObjectList<TLeakFinding>;
      const FileName: string); static;

    // Jira-Wiki-Markup fuer Befunde einer einzelnen Datei. Severity-Auswahl
    // ueber Filter-Set (z.B. [lsError, lsWarning] fuer Fehler+Warnungen).
    // Liefert den fertigen Text - speichern oder in die Zwischenablage uebergeben
    // ist Sache des Aufrufers.
    class function BuildJiraText(Findings: TObjectList<TLeakFinding>;
      const SourceFile: string; const SeverityFilter: TSeverityFilter): string; static;

    // Liefert einen Zwischenablage-tauglichen Plain-Text mit Fehler+Warnung
    // fuer eine einzelne Datei. Format: "<Severity> [Zeile] <Regel>: <Detail>"
    class function BuildClipboardText(Findings: TObjectList<TLeakFinding>;
      const SourceFile: string; const SeverityFilter: TSeverityFilter): string; static;

    // Erzeugt einen kompletten, in sich geschlossenen HTML-Report (inkl. CSS).
    // SourceFile ist optional - wenn '' gesetzt, werden alle Befunde gelistet.
    class procedure ExportHtml(Findings: TObjectList<TLeakFinding>;
      const SourceFile: string; const FileName: string); static;

    // Hilfs-Funktion: erzeugt den Standard-Dateinamen
    // "<source-basename>_codereview_<YYYY-MM-DD>.html"
    class function DefaultHtmlFileName(const SourceFile: string;
      const TargetDir: string): string; static;

  private
    // Speichert eine TStringList als UTF-8 MIT BOM. TEncoding.UTF8
    // (Singleton) hat in Delphi 12 FUseBOM=False -> kein BOM via
    // SaveToFile. Wir erzeugen daher eine eigene TUTF8Encoding-Instanz
    // mit UseBOM=True, geben sie nach dem Save wieder frei.
    class procedure SaveUtf8WithBom(SL: TStringList;
      const FileName: string); static;
    class function KindToName(Kind: TFindingKind): string; static;
    class function CsvEscape(const S: string): string; static;
    class function JsonEscape(const S: string): string; static;
    class function JiraEscape(const S: string): string; static;
    class function HtmlEscape(const S: string): string; static;
    class function SameSourceFile(const A, B: string): Boolean; static;
    // Liefert ein HTML-Fragment (<div class="src-snippet">) mit ContextSize Zeilen
    // vor und nach AroundLine. Die Fund-Zeile ist optisch hervorgehoben.
    // Liefert leeren String wenn SourceLines nil/leer oder AroundLine ungueltig.
    class function BuildCodeSnippet(SourceLines: TStringList;
      AroundLine, ContextSize: Integer): string; static;
  end;

implementation

class procedure TExporter.SaveUtf8WithBom(SL: TStringList;
  const FileName: string);
var
  Enc: TUTF8Encoding;
begin
  // UseBOM=True erzwingt EF BB BF Preamble in SaveToFile/SaveToStream.
  // Die Standard-Singleton TEncoding.UTF8 hat FUseBOM=False (Boolean-
  // Default) und wuerde keinen BOM schreiben.
  Enc := TUTF8Encoding.Create(True);
  try
    SL.SaveToFile(FileName, Enc);
  finally
    Enc.Free;
  end;
end;

class function TExporter.KindToName(Kind: TFindingKind): string;
begin
  case Kind of
    fkMemoryLeak      : Result := 'MemoryLeak';
    fkEmptyExcept     : Result := 'EmptyExcept';
    fkSQLInjection    : Result := 'SQLInjection';
    fkHardcodedSecret : Result := 'HardcodedSecret';
    fkFormatMismatch  : Result := 'FormatMismatch';
    fkFileReadError   : Result := 'FileReadError';
    fkUnusedUses      : Result := 'UnusedUses';
    fkNilDeref        : Result := 'NilDeref';
    fkMissingFinally  : Result := 'MissingFinally';
    fkDivByZero       : Result := 'DivByZero';
    fkDeadCode        : Result := 'DeadCode';
    fkLongMethod      : Result := 'LongMethod';
    fkLongParamList   : Result := 'LongParamList';
    fkMagicNumber     : Result := 'MagicNumber';
    fkDuplicateString : Result := 'DuplicateString';
    fkHardcodedPath   : Result := 'HardcodedPath';
    fkDebugOutput     : Result := 'DebugOutput';
    fkDeepNesting     : Result := 'DeepNesting';
    fkTodoComment     : Result := 'TodoComment';
    fkEmptyMethod     : Result := 'EmptyMethod';
    fkDuplicateBlock  : Result := 'DuplicateBlock';
  else
    Result := '?';
  end;
end;

class function TExporter.CsvEscape(const S: string): string;
// CSV-Escaping nach RFC 4180: Anfuehrungszeichen verdoppeln, Wert in "" einschliessen
// wenn er Sonderzeichen (Semikolon, Anfuehrungszeichen, Zeilenumbruch) enthaelt.
var
  NeedsQuote : Boolean;
begin
  Result := S;
  NeedsQuote := (Pos(';', Result) > 0) or (Pos('"', Result) > 0) or
                (Pos(#13, Result) > 0) or (Pos(#10, Result) > 0);
  Result := Result.Replace('"', '""', [rfReplaceAll]);
  // Zeilenumbrueche durch Leerzeichen ersetzen (sonst Zeilen-Umbruch im CSV)
  Result := Result.Replace(#13#10, ' ', [rfReplaceAll]);
  Result := Result.Replace(#13, ' ', [rfReplaceAll]);
  Result := Result.Replace(#10, ' ', [rfReplaceAll]);
  if NeedsQuote then
    Result := '"' + Result + '"';
end;

class function TExporter.JsonEscape(const S: string): string;
// JSON-Escaping per RFC 8259:
//   - \", \\, \/, \b, \f, \n, \r, \t spezielle Sequenzen
//   - U+0000..U+001F UND U+007F (DEL) als \uXXXX
//   - lone surrogates (U+D800..U+DFFF ohne Pair) als \uXXXX (sonst kein
//     valides UTF-16 in JSON-Strings)
//   - alle anderen BMP- und Surrogate-Pair-Codepoints unveraendert
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
        '"' : SB.Append('\"');
        '\' : SB.Append('\\');
        #8  : SB.Append('\b');
        #9  : SB.Append('\t');
        #10 : SB.Append('\n');
        #12 : SB.Append('\f');
        #13 : SB.Append('\r');
      else
        if (Ord(Ch) < 32) or (Ord(Ch) = 127) then
          SB.Append(Format('\u%.4x', [Ord(Ch)]))
        else if (Ord(Ch) >= $D800) and (Ord(Ch) <= $DBFF)
                and (i < Length(S))
                and (Ord(S[i + 1]) >= $DC00) and (Ord(S[i + 1]) <= $DFFF) then
        begin
          // Gueltiges High/Low-Surrogate-Pair - beide unveraendert ausgeben
          SB.Append(Ch);
          SB.Append(S[i + 1]);
          Inc(i, 2);
          Continue;
        end
        else if (Ord(Ch) >= $D800) and (Ord(Ch) <= $DFFF) then
          // Lone surrogate - escapen, sonst ungueltiges JSON
          SB.Append(Format('\u%.4x', [Ord(Ch)]))
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

class procedure TExporter.ExportCsv(Findings: TObjectList<TLeakFinding>;
  const FileName: string);
var
  SL : TStringList;
  F  : TLeakFinding;
begin
  SL := TStringList.Create;
  try
    SL.Add('File;Method;Line;Type;Severity;Detail');
    if Assigned(Findings) then
      for F in Findings do
        SL.Add(
          CsvEscape(F.FileName)         + ';' +
          CsvEscape(F.MethodName)       + ';' +
          CsvEscape(F.LineNumber)       + ';' +
          CsvEscape(KindToName(F.Kind)) + ';' +
          CsvEscape(F.SeverityText)     + ';' +
          CsvEscape(F.MissingVar));
    SaveUtf8WithBom(SL, FileName);
  finally
    SL.Free;
  end;
end;

class procedure TExporter.ExportJson(Findings: TObjectList<TLeakFinding>;
  const FileName: string);
var
  SB    : TStringBuilder;
  i     : Integer;
  F     : TLeakFinding;
  SL    : TStringList;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('[');
    if Assigned(Findings) and (Findings.Count > 0) then
    begin
      for i := 0 to Findings.Count - 1 do
      begin
        F := Findings[i];
        SB.Append('  {');
        SB.Append('"file": "');     SB.Append(JsonEscape(F.FileName));         SB.Append('", ');
        SB.Append('"method": "');   SB.Append(JsonEscape(F.MethodName));       SB.Append('", ');
        SB.Append('"line": ');      SB.Append(StrToIntDef(F.LineNumber, 0));   SB.Append(', ');
        SB.Append('"kind": "');     SB.Append(JsonEscape(KindToName(F.Kind))); SB.Append('", ');
        SB.Append('"severity": "'); SB.Append(JsonEscape(F.SeverityText));     SB.Append('", ');
        SB.Append('"detail": "');   SB.Append(JsonEscape(F.MissingVar));       SB.Append('"');
        if i < Findings.Count - 1 then
          SB.AppendLine('},')
        else
          SB.AppendLine('}');
      end;
    end;
    SB.AppendLine(']');

    SL := TStringList.Create;
    try
      SL.Text := SB.ToString;
      SaveUtf8WithBom(SL, FileName);
    finally
      SL.Free;
    end;
  finally
    SB.Free;
  end;
end;

{ ---- Jira / Clipboard / HTML ----------------------------------------------- }

class function TExporter.JiraEscape(const S: string): string;
// In Jira-Wiki-Markup haben |, *, _, +, -, [, ], {, } eigene Bedeutung.
// Per Backslash-Escape neutralisieren. Zeilenumbrueche durch Leerzeichen
// ersetzen, weil Tabellenzeilen nicht ueber Zeilenumbrueche gehen.
var
  Ch: Char;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    for Ch in S do
      case Ch of
        #13, #10 : SB.Append(' ');
        '|', '*', '_', '+', '-', '[', ']', '{', '}', '\':
          begin SB.Append('\'); SB.Append(Ch); end;
      else
        SB.Append(Ch);
      end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TExporter.HtmlEscape(const S: string): string;
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

class function TExporter.SameSourceFile(const A, B: string): Boolean;
// Vergleicht Datei-Pfade case-insensitiv und mit normalisierten Trennern.
// Ein Befund kann mit absolutem oder relativem Pfad vorliegen, Aufrufer
// uebergibt eines davon - wir vergleichen den Basisnamen-Tail.
begin
  if (A = '') or (B = '') then Exit(False);
  Result := SameText(ExtractFileName(A), ExtractFileName(B));
end;

class function TExporter.BuildCodeSnippet(SourceLines: TStringList;
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

class function TExporter.BuildJiraText(Findings: TObjectList<TLeakFinding>;
  const SourceFile: string; const SeverityFilter: TSeverityFilter): string;
var
  SB         : TStringBuilder;
  F          : TLeakFinding;
  nErr, nWrn : Integer;
  nHnt       : Integer;
  rowCount   : Integer;
  Hint       : TFixHint;
  SevLabel   : string;
begin
  SB := TStringBuilder.Create;
  try
    nErr := 0; nWrn := 0; nHnt := 0;

    SB.Append('h2. Code-Analyse: ');
    SB.AppendLine(JiraEscape(ExtractFileName(SourceFile)));
    SB.Append('Stand: ');
    SB.AppendLine(FormatDateTime('yyyy-mm-dd hh:nn', Now));
    SB.AppendLine('');

    SB.AppendLine('|| Severity || Zeile || Methode || Regel || Detail ||');

    rowCount := 0;
    if Assigned(Findings) then
      for F in Findings do
      begin
        if not (F.Severity in SeverityFilter) then Continue;
        if (SourceFile <> '') and not SameSourceFile(F.FileName, SourceFile) then
          Continue;

        case F.Severity of
          lsError   : begin
                        SB.Append('| {color:red}*Fehler*{color}');
                        Inc(nErr);
                      end;
          lsWarning : begin
                        SB.Append('| {color:#b07000}Warnung{color}');
                        Inc(nWrn);
                      end;
          lsHint    : begin
                        SB.Append('| {color:#5a8000}Hinweis{color}');
                        Inc(nHnt);
                      end;
        end;
        SB.Append(' | ');     SB.Append(JiraEscape(F.LineNumber));
        SB.Append(' | ');     SB.Append(JiraEscape(F.MethodName));
        SB.Append(' | ');     SB.Append(JiraEscape(KindToName(F.Kind)));
        SB.Append(' | ');     SB.Append(JiraEscape(F.MissingVar));
        SB.AppendLine(' |');
        Inc(rowCount);
      end;

    if rowCount = 0 then
    begin
      SB.AppendLine('| _keine Befunde_ | | | | |');
    end;

    SB.AppendLine('');
    SB.AppendLine('{panel:title=Zusammenfassung|borderColor=#ccc|bgColor=#f8f8f8}');
    SB.AppendLine('* Fehler: ' + IntToStr(nErr));
    SB.AppendLine('* Warnungen: ' + IntToStr(nWrn));
    if lsHint in SeverityFilter then
      SB.AppendLine('* Hinweise: ' + IntToStr(nHnt));
    SB.AppendLine('{panel}');

    // ---- Befunde im Detail mit Loesungs-Hinweisen ----
    if rowCount > 0 then
    begin
      SB.AppendLine('');
      SB.AppendLine('h3. Befunde im Detail');
      SB.AppendLine('');

      for F in Findings do
      begin
        if not (F.Severity in SeverityFilter) then Continue;
        if (SourceFile <> '') and not SameSourceFile(F.FileName, SourceFile) then
          Continue;

        case F.Severity of
          lsError   : SevLabel := '{color:red}*Fehler*{color}';
          lsWarning : SevLabel := '{color:#b07000}Warnung{color}';
          lsHint    : SevLabel := '{color:#5a8000}Hinweis{color}';
        else
          SevLabel := '';
        end;

        // Header pro Befund: "h4. <Severity> - Z. <line> - <Kind> - <Detail>"
        SB.Append('h4. ');
        SB.Append(SevLabel);
        SB.Append(' - Z. ');
        SB.Append(JiraEscape(F.LineNumber));
        if F.MethodName <> '' then
        begin
          SB.Append(' - ');
          SB.Append(JiraEscape(F.MethodName));
        end;
        SB.Append(' - ');
        SB.Append(JiraEscape(KindToName(F.Kind)));
        SB.Append(' - ');
        SB.AppendLine(JiraEscape(F.MissingVar));

        Hint := TFixHintResolver.FixHint(F);
        if Hint.Description <> '' then
        begin
          SB.Append('bq. ');
          SB.AppendLine(JiraEscape(Hint.Description));
        end;
        if Hint.Before <> '' then
        begin
          SB.AppendLine('*Vorher:*');
          SB.AppendLine('{code:delphi}');
          SB.AppendLine(Hint.Before);
          SB.AppendLine('{code}');
        end;
        if Hint.After <> '' then
        begin
          SB.AppendLine('*Nachher:*');
          SB.AppendLine('{code:delphi}');
          SB.AppendLine(Hint.After);
          SB.AppendLine('{code}');
        end;
        SB.AppendLine('');
      end;
    end;

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TExporter.BuildClipboardText(Findings: TObjectList<TLeakFinding>;
  const SourceFile: string; const SeverityFilter: TSeverityFilter): string;

  procedure AppendIndented(SB: TStringBuilder; const Block: string;
    const Prefix: string);
  // Mehrzeiligen Block (Vorher/Nachher) zeilenweise mit Praefix versehen.
  var
    SL: TStringList;
    Line: string;
  begin
    SL := TStringList.Create;
    try
      SL.Text := Block;
      // Letzte leere Zeile der TStringList.Text-Konvention abfangen
      if (SL.Count > 0) and (SL[SL.Count - 1] = '') then
        SL.Delete(SL.Count - 1);
      for Line in SL do
      begin
        SB.Append(Prefix);
        SB.AppendLine(Line);
      end;
    finally
      SL.Free;
    end;
  end;

var
  SB   : TStringBuilder;
  F    : TLeakFinding;
  Sev  : string;
  Hint : TFixHint;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('Code-Analyse: ');
    SB.AppendLine(ExtractFileName(SourceFile));
    SB.AppendLine(StringOfChar('-', 60));

    if Assigned(Findings) then
      for F in Findings do
      begin
        if not (F.Severity in SeverityFilter) then Continue;
        if (SourceFile <> '') and not SameSourceFile(F.FileName, SourceFile) then
          Continue;

        case F.Severity of
          lsError   : Sev := '[FEHLER]  ';
          lsWarning : Sev := '[WARNUNG] ';
          lsHint    : Sev := '[HINWEIS] ';
        else
          Sev := '          ';
        end;

        SB.Append(Sev);
        SB.Append('Z. ');
        SB.Append(F.LineNumber);
        if F.MethodName <> '' then
        begin
          SB.Append(' in ');
          SB.Append(F.MethodName);
        end;
        SB.Append('  ');
        SB.Append(KindToName(F.Kind));
        SB.Append(': ');
        SB.AppendLine(F.MissingVar);

        Hint := TFixHintResolver.FixHint(F);
        if Hint.Description <> '' then
        begin
          SB.Append('  Hinweis: ');
          SB.AppendLine(Hint.Description);
        end;
        if Hint.Before <> '' then
        begin
          SB.AppendLine('  Vorher:');
          AppendIndented(SB, Hint.Before, '    ');
        end;
        if Hint.After <> '' then
        begin
          SB.AppendLine('  Nachher:');
          AppendIndented(SB, Hint.After, '    ');
        end;
        SB.AppendLine('');
      end;

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TExporter.DefaultHtmlFileName(const SourceFile: string;
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

class procedure TExporter.ExportHtml(Findings: TObjectList<TLeakFinding>;
  const SourceFile: string; const FileName: string);
const
  SNIPPET_CONTEXT = 3;  // Zeilen vor und nach der Befund-Zeile
var
  SB        : TStringBuilder;
  F         : TLeakFinding;
  SL        : TStringList;
  Files     : TStringList;
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

  // Erste Schleife: Zaehler + eindeutige Dateinamen fuer den Filter sammeln.
  // SourceCache haelt geladene Quelldatei-Inhalte (TStringList je Pfad), wird
  // beim Cleanup automatisch alle TStringLists freigeben (doOwnsValues).
  Files       := nil;
  SourceCache := nil;
  try
    Files := TStringList.Create;
    Files.Duplicates := dupIgnore;
    Files.Sorted := True;
    Files.CaseSensitive := False;
    SourceCache := TObjectDictionary<string, TStringList>.Create([doOwnsValues]);
    nTotal := 0; nErr := 0; nWarn := 0; nHint := 0;
    if Assigned(Findings) then
      for F in Findings do
      begin
        if (SourceFile <> '') and not SameSourceFile(F.FileName, SourceFile) then
          Continue;
        Inc(nTotal);
        case F.Severity of
          lsError   : Inc(nErr);
          lsWarning : Inc(nWarn);
          lsHint    : Inc(nHint);
        end;
        if F.FileName <> '' then
          Files.Add(ExtractFileName(F.FileName));
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
    for fnDisp in Files do
    begin
      SB.Append('      <option value="');
      SB.Append(HtmlEscape(fnDisp));
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
        if (SourceFile <> '') and not SameSourceFile(F.FileName, SourceFile) then
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

        // Sichtbare Befund-Zeile - data-file fuer Filter, ganze Zeile klickbar
        SB.Append('      <tr class="finding ' + SevCl + '" data-file="');
        SB.Append(HtmlEscape(FileShort));
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
        SB.Append('<td>'); SB.Append(HtmlEscape(KindToName(F.Kind))); SB.Append('</td>');
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
    SB.AppendLine('      var visible = 0;');
    SB.AppendLine('      document.querySelectorAll(''tr.finding'').forEach(function(row) {');
    SB.AppendLine('        var fileOk = !fileVal || row.getAttribute(''data-file'') === fileVal;');
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
      SaveUtf8WithBom(SL, FileName);
    finally
      SL.Free;
    end;
  finally
    SB.Free;
  end;
  finally
    Files.Free;
    SourceCache.Free;
  end;
end;

end.
