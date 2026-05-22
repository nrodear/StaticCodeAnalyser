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
  uSCAConsts, uMethodd12, uFixHint, uLocalization, uRuleCatalog;

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
    // Implementierung in uExportHtml; diese Methode delegiert dorthin.
    class procedure ExportHtml(Findings: TObjectList<TLeakFinding>;
      const SourceFile: string; const FileName: string); static;

    // Hilfs-Funktion: erzeugt den Standard-Dateinamen
    // "<source-basename>_codereview_<YYYY-MM-DD>.html". Delegation an uExportHtml.
    class function DefaultHtmlFileName(const SourceFile: string;
      const TargetDir: string): string; static;

    // ---- Querschnitts-Helfer (public weil uExportHtml sie braucht) ----

    // Speichert eine TStringList als UTF-8 MIT BOM. TEncoding.UTF8
    // (Singleton) hat in Delphi 12 FUseBOM=False -> kein BOM via
    // SaveToFile. Wir erzeugen daher eine eigene TUTF8Encoding-Instanz
    // mit UseBOM=True, geben sie nach dem Save wieder frei.
    class procedure SaveUtf8WithBom(SL: TStringList;
      const FileName: string); static;
    // Kanonischer Name eines Befund-Kinds (fuer CSV/JSON/Jira/HTML).
    class function KindToName(Kind: TFindingKind): string; static;
    // Vergleicht Datei-Pfade case-insensitiv und mit normalisierten
    // Trennern - ein Befund kann mit absolutem oder relativem Pfad
    // vorliegen, wir vergleichen den Basisnamen-Tail.
    class function SameSourceFile(const A, B: string): Boolean; static;

  private
    class function CsvEscape(const S: string): string; static;
    class function JsonEscape(const S: string): string; static;
    class function JiraEscape(const S: string): string; static;
  end;

implementation

uses
  uExportHtml;

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
// Delegiert an KIND_META in uSCAConsts (single source of truth).
begin
  Result := KindName(Kind);
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
    // Spalte 'Kind' enthaelt den Detector-Kind-Namen (z.B. 'MemoryLeak') -
    // frueher hiess der Header missverstaendlich 'Type', was Sonar-Typen
    // (Bug/CodeSmell/Vulnerability/...) suggerierte.
    SL.Add('File;Method;Line;Kind;Severity;Detail');
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
        SB.Append('"type": "');     SB.Append(JsonEscape(F.TypeText));         SB.Append('", ');
        SB.Append('"severity": "'); SB.Append(JsonEscape(F.SeverityText));     SB.Append('", ');
        // RuleID: Custom-Rule-ID gewinnt; sonst Catalog-Lookup via Kind.
        var Rid: string;
        if F.RuleID <> '' then Rid := F.RuleID
        else Rid := TRuleCatalog.GetRule(F.Kind).ID;
        SB.Append('"ruleID": "');   SB.Append(JsonEscape(Rid));                SB.Append('", ');
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

class function TExporter.SameSourceFile(const A, B: string): Boolean;
// Vergleicht Datei-Pfade case-insensitiv und mit normalisierten Trennern.
// Ein Befund kann mit absolutem oder relativem Pfad vorliegen, Aufrufer
// uebergibt eines davon - wir vergleichen den Basisnamen-Tail.
begin
  if (A = '') or (B = '') then Exit(False);
  Result := SameText(ExtractFileName(A), ExtractFileName(B));
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

    SB.Append(_('h2. Code analysis: '));
    SB.AppendLine(JiraEscape(ExtractFileName(SourceFile)));
    SB.Append(_('As of: '));
    SB.AppendLine(FormatDateTime('yyyy-mm-dd hh:nn', Now));
    SB.AppendLine('');

    SB.AppendLine(Format('|| %s || %s || %s || %s || %s ||',
      [_('Severity'), _('Line'), _('Method'), _('Rule'), _('Detail')]));

    rowCount := 0;
    if Assigned(Findings) then
      for F in Findings do
      begin
        if not (F.Severity in SeverityFilter) then Continue;
        if (SourceFile <> '') and not SameSourceFile(F.FileName, SourceFile) then
          Continue;

        case F.Severity of
          lsError   : begin
                        SB.Append(Format('| {color:red}*%s*{color}', [_('Error')]));
                        Inc(nErr);
                      end;
          lsWarning : begin
                        SB.Append(Format('| {color:#b07000}%s{color}', [_('Warning')]));
                        Inc(nWrn);
                      end;
          lsHint    : begin
                        SB.Append(Format('| {color:#5a8000}%s{color}', [_('Hint')]));
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
      SB.AppendLine(Format('| _%s_ | | | | |', [_('no findings')]));
    end;

    SB.AppendLine('');
    SB.AppendLine(Format('{panel:title=%s|borderColor=#ccc|bgColor=#f8f8f8}',
      [_('Summary')]));
    SB.AppendLine(Format('* %s: %d', [_('Errors'),   nErr]));
    SB.AppendLine(Format('* %s: %d', [_('Warnings'), nWrn]));
    if lsHint in SeverityFilter then
      SB.AppendLine(Format('* %s: %d', [_('Hints'),  nHnt]));
    SB.AppendLine('{panel}');

    // ---- Befunde im Detail mit Loesungs-Hinweisen ----
    if rowCount > 0 then
    begin
      SB.AppendLine('');
      SB.AppendLine('h3. ' + _('Findings in detail'));
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
    SB.Append(_('Code analysis: '));
    SB.AppendLine(ExtractFileName(SourceFile));
    SB.AppendLine(StringOfChar('-', 60));

    if Assigned(Findings) then
      for F in Findings do
      begin
        if not (F.Severity in SeverityFilter) then Continue;
        if (SourceFile <> '') and not SameSourceFile(F.FileName, SourceFile) then
          Continue;

        case F.Severity of
          lsError   : Sev := Format('[%-7s] ', [_('ERROR')]);
          lsWarning : Sev := Format('[%-7s] ', [_('WARNING')]);
          lsHint    : Sev := Format('[%-7s] ', [_('HINT')]);
        else
          Sev := '          ';
        end;

        SB.Append(Sev);
        SB.Append(_('L. '));
        SB.Append(F.LineNumber);
        if F.MethodName <> '' then
        begin
          SB.Append(' ' + _('in') + ' ');
          SB.Append(F.MethodName);
        end;
        SB.Append('  ');
        SB.Append(KindToName(F.Kind));
        SB.Append(': ');
        SB.AppendLine(F.MissingVar);

        Hint := TFixHintResolver.FixHint(F);
        if Hint.Description <> '' then
        begin
          SB.Append('  ' + _('Hint: '));
          SB.AppendLine(Hint.Description);
        end;
        if Hint.Before <> '' then
        begin
          SB.AppendLine('  ' + _('Before:'));
          AppendIndented(SB, Hint.Before, '    ');
        end;
        if Hint.After <> '' then
        begin
          SB.AppendLine('  ' + _('After:'));
          AppendIndented(SB, Hint.After, '    ');
        end;
        SB.AppendLine('');
      end;

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// ---- HTML-Report: nur Delegationen, Implementation in uExportHtml ----

class function TExporter.DefaultHtmlFileName(const SourceFile: string;
  const TargetDir: string): string;
begin
  Result := TExporterHtml.DefaultFileName(SourceFile, TargetDir);
end;

class procedure TExporter.ExportHtml(Findings: TObjectList<TLeakFinding>;
  const SourceFile: string; const FileName: string);
begin
  TExporterHtml.Run(Findings, SourceFile, FileName);
end;

end.
