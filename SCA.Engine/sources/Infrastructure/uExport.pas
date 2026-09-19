unit uExport;

// Export von TLeakFinding-Listen in verschiedenen Formaten:
//   - CSV   (Semikolon-getrennt, fuer deutsches Excel direkt lesbar)
//   - JSON  (Array von Objekten)
//   - Jira  (Wiki-Markup, fuer Tickets)
//   - HTML  (Self-contained Code-Review-Report)
//
// CSV und HTML werden als UTF-8 MIT BOM gespeichert, JSON seit
// 2026-08-08 OHNE. Der Unterschied ist Absicht: deutsches Excel erkennt
// eine CSV nur am BOM als UTF-8 (sonst zerfallen die Umlaute), waehrend
// RFC 8259 par.8.1 die Praeambel fuer JSON-Austausch verbietet und Nodes
// JSON.parse daran scheitert - dieselbe Linie wie bei SARIF, Sonar-Export
// und Baseline.
//
// WICHTIG, und bis 08.09. hier GENAU VERKEHRT HERUM aufgeschrieben: die
// Singleton TEncoding.UTF8 hat FUseBOM = TRUE. Sie entsteht ueber
// TUTF8Encoding.Create -> inherited TMBCSEncoding.Create(CP_UTF8, ...),
// und dessen letzte Anweisung ist FUseBOM := True (System.SysUtils).
// TEncoding.UTF8.GetPreamble liefert deshalb EF BB BF.
// Geschrieben wird die Preambel von TStrings.SaveToStream aber nur, wenn
// BEIDES zutrifft: WriteBOM ist True UND GetPreamble ist nicht leer.
//
// Daraus folgt die Regel, an der hier nicht gedreht werden darf: eine
// BOM-lose Ausgabe entsteht NUR, wenn der Schreiber die Preambel aktiv
// unterdrueckt. Wer der alten Begruendung glaubt ("ist doch ohnehin
// leer") und den Schalter streicht, gibt der JSON-Ausgabe eine
// Praeambel - und damit scheitert jeder Node-JSON.parse in der Pipeline.
// Traeger der Politik sind heute TReportFileWriter.SaveBuilderUtf8
// (Parameter AMitBom, CSV/JSON/HTML) und .SaveUtf8WithBom (TStringList,
// Detektor-Katalog) - beide seit der C-Charge 2026-09-19 in
// uReportFileWriter (Output) und dort ATOMAR (erst .sca-tmp, dann
// Tausch); die SCA141-Folgearbeit hat sie aus dieser Klasse gezogen.
// uTestExport haelt beide BOM-Richtungen fest.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12, uFixHint, uLocalization, uRuleCatalog;

type
  // D1-Umzug 2026-09-19: der Typ lebt jetzt in uSCAConsts (Common,
  // neben TLeakSeverity), weil auch Output ihn braucht. Alias fuer
  // bestehende Konsumenten dieses Namensraums.
  TSeverityFilter = uSCAConsts.TSeverityFilter;

  TExporter = class
  public
    // ABaseDir: Wurzel fuer die Pfad-ANZEIGE. Leer = absolute Pfade
    // (bisheriges Verhalten, GUI-Aufrufer bleiben unveraendert). Die CLI
    // reicht --base-dir durch, damit ein CI-Artefakt keine
    // maschinenspezifischen Pfade enthaelt - so wie SARIF, Sonar und
    // der HTML-Report es laengst tun.
    class procedure ExportCsv(Findings: TObjectList<TLeakFinding>;
      const FileName: string; const ABaseDir: string = ''); static;
    class procedure ExportJson(Findings: TObjectList<TLeakFinding>;
      const FileName: string; const ABaseDir: string = ''); static;

    // BuildJiraText/BuildClipboardText/JiraEscape stehen seit D1
    // (2026-09-19) in TFindingCopyText (uFindingCopyText, Output) -
    // reine Textbauer ohne Datei-I/O, Schwestern von BuildJiraMini.
    // Der Umzug ist der zweite Teil der SCA141-Folgearbeit (TExporter
    // 584 -> unter die 500er-Schwelle).

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

    // Die Schreibwege SaveUtf8WithBom und SaveBuilderUtf8 standen bis
    // zur C-Charge 2026-09-19 HIER - sie liegen jetzt als
    // TReportFileWriter in uReportFileWriter (Output) und schreiben
    // dort ATOMAR. Der Umzug ist die im Selbstscan der Charge 22
    // dokumentierte SCA141-Folgearbeit ("die Schreibwege haben mit
    // 'Befundlisten exportieren' nichts zu tun"); Aufrufer rufen den
    // Writer direkt.

    // Anzeigepfad relativ zu ABaseDir (Forward Slashes). Leerer BaseDir
    // oder Datei ausserhalb -> unveraendert.
    class function RelativeDisplayPath(const AFileName,
      ABaseDir: string): string; static;
    // Kanonischer Name eines Befund-Kinds (fuer CSV/JSON/Jira/HTML).
    class function KindToName(Kind: TFindingKind): string; static;
    // Pfadvergleich (Tail an Trennergrenze) - seit D1 Delegation an
    // TDetectorUtils.SameSourceFile (Common), Vertrag und Doku dort.
    // Bleibt hier als Einstiegspunkt fuer uExportHtml und die Tests.
    class function SameSourceFile(const A, B: string): Boolean; static;
    // JSON-String-Escaping - public, weil uExportHtml es fuer den
    // sca-meta-Block (#10) braucht (wie KindToName/SameSourceFile).
    class function JsonEscape(const S: string): string; static;

  private
    class function CsvEscape(const S: string): string; static;
  end;

implementation

// noinspection-file BeginEndRequired, CanBeStrictPrivate, ConcatToFormat, ConsecutiveSection, CyclomaticComplexity, DateFormatSettings, DeepNesting, DuplicateString, GroupedDeclaration, LongMethod, MagicNumber, TooLongLine, UnsortedUses, UnusedPublicMember
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.IOUtils,          // TPath (RelativeDisplayPath)
  uExportHtml,
  uReportFileWriter,   // atomare Schreibwege (C-Charge 2026-09-19)
  uDetectorUtils;      // SameSourceFile-Delegation (D1 2026-09-19)

class function TExporter.RelativeDisplayPath(const AFileName,
  ABaseDir: string): string;
var
  Base, Full : string;
begin
  Result := AFileName;
  if (ABaseDir = '') or (AFileName = '') then Exit;
  Base := IncludeTrailingPathDelimiter(TPath.GetFullPath(ABaseDir));
  Full := TPath.GetFullPath(AFileName);
  if SameText(Copy(Full, 1, Length(Base)), Base) then
    // Der Backslash im Suchmuster ist TRAGEND: mit leerem Muster
    // steigt StringReplace sofort aus (RTL: 'if LenOP = 0 then
    // Exit(Source)') und der Pfad ginge mit Windows-Trennern raus -
    // genau das war hier bis 08.09. der Fall, waehrend die drei
    // Schwesterfassungen (SARIF, Sonar, HtmlDisplayPath) korrekt
    // ersetzten. Folge: CSV/JSON zeigten 'src\u.pas', SARIF fuer
    // DENSELBEN Fund 'src/u.pas' - ein CI-Skript, das beide
    // Artefakte ueber den Pfad verbindet, fand null Treffer.
    Result := StringReplace(Copy(Full, Length(Base) + 1, MaxInt),
                            '\', '/', [rfReplaceAll]);
end;

class function TExporter.KindToName(Kind: TFindingKind): string;
// Delegiert an KIND_META in uSCAConsts (single source of truth).
begin
  Result := KindName(Kind);
end;

class function TExporter.CsvEscape(const S: string): string;
// CSV-Escaping nach RFC 4180: Anfuehrungszeichen verdoppeln, Wert in "" einschliessen
// wenn er Sonderzeichen (Semikolon, Anfuehrungszeichen, Zeilenumbruch) enthaelt.
//
// FORMEL-NEUTRALISIERUNG (Voll-Review, umgesetzt 2026-09-15, CWE-1236).
// Beginnt ein Feld mit = + - @ (oder TAB/CR), wertet Excel seinen Inhalt
// als FORMEL aus. Das RFC-Quoting schuetzt davor NICHT - in "=cmd|..."
// sieht Excel weiterhin eine Formel, die Anfuehrungszeichen gehoeren zur
// CSV-Syntax, nicht zum Zellinhalt. Der uebliche Schutz ist ein
// vorangestellter Apostroph: Excel liest ihn als "das ist Text" und
// zeigt ihn nicht an.
//
// DER ANGRIFFSWEG IST BELEGT, nicht theoretisch. Der Korpus selbst ist
// sauber - 231.571 Datenzeilen aus einem jvcl-Export, KEIN einziges
// Feld mit Formel-Praefix -, und ueber die Detail-Spalte kommt man auch
// nicht hinein: zitiert ein Detektor Quelltext (SCA015 "..." 3x -
// extract as a constant), steht das Anfuehrungszeichen davor. Der Weg
// ist der DATEINAME. Eine Datei '=cmd_test.pas' landet ungeschuetzt am
// Anfang der File-Spalte - an der Exe nachgestellt und bestaetigt. Wer
// fremden Code scannt (CI, Pull Request) und den Bericht in Excel
// oeffnet, fuehrt fremde Formeln aus.
//
// Im Normalbetrieb aendert das nichts: bei null betroffenen Feldern von
// 231.571 ist der Zweig schlicht kalt.
const
  FORMEL_START = ['=', '+', '-', '@', #9, #13];
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
  // Nach dem Zeilenumbruch-Ersatz pruefen, nicht davor: ein fuehrendes
  // CR ist dann schon ein Leerzeichen und damit harmlos.
  if (Result <> '') and CharInSet(Result[1], FORMEL_START) then
    Result := '''' + Result;
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
  const FileName: string; const ABaseDir: string);
var
  SB : TStringBuilder;
  F  : TLeakFinding;
begin
  // Builder statt TStringList aus demselben Grund wie in ExportJson: die
  // Liste haelt am Ende den kompletten Bericht, GetTextStr baut daraus
  // eine zweite Vollkopie und GetBytes eine dritte. AppendLine haengt
  // dasselbe sLineBreak an, das GetTextStr angehaengt haette - die Datei
  // ist byte-identisch zum bisherigen Weg.
  SB := TStringBuilder.Create;
  try
    // Spalte 'Kind' enthaelt den Detector-Kind-Namen (z.B. 'MemoryLeak') -
    // frueher hiess der Header missverstaendlich 'Type', was Sonar-Typen
    // (Bug/CodeSmell/Vulnerability/...) suggerierte.
    SB.AppendLine('File;Method;Line;Kind;Severity;Detail');
    if Assigned(Findings) then
      for F in Findings do
        SB.AppendLine(
          CsvEscape(RelativeDisplayPath(F.FileName, ABaseDir)) + ';' +
          CsvEscape(F.MethodName)       + ';' +
          CsvEscape(F.LineNumber)       + ';' +
          CsvEscape(KindToName(F.Kind)) + ';' +
          CsvEscape(F.SeverityText)     + ';' +
          CsvEscape(F.MissingVar));
    TReportFileWriter.SaveBuilderUtf8(SB, FileName, True);
  finally
    SB.Free;
  end;
end;

class procedure TExporter.ExportJson(Findings: TObjectList<TLeakFinding>;
  const FileName: string; const ABaseDir: string);
var
  SB    : TStringBuilder;
  i     : Integer;
  F     : TLeakFinding;
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
        SB.Append('"file": "');     SB.Append(JsonEscape(RelativeDisplayPath(F.FileName, ABaseDir))); SB.Append('", ');
        SB.Append('"method": "');   SB.Append(JsonEscape(F.MethodName));       SB.Append('", ');
        SB.Append('"line": ');      SB.Append(StrToIntDef(F.LineNumber, 0));   SB.Append(', ');
        SB.Append('"kind": "');     SB.Append(JsonEscape(KindToName(F.Kind))); SB.Append('", ');
        SB.Append('"type": "');     SB.Append(JsonEscape(F.TypeText));         SB.Append('", ');
        SB.Append('"severity": "'); SB.Append(JsonEscape(F.SeverityText));     SB.Append('", ');
        // RuleID: Custom-Rule-ID gewinnt; sonst Catalog-Lookup via Kind.
        var Rid: string;
        if F.RuleID <> '' then Rid := F.RuleID
        else Rid := TRuleCatalog.GetRuleCanonical(F.Kind).ID;
        SB.Append('"ruleID": "');   SB.Append(JsonEscape(Rid));                SB.Append('", ');
        SB.Append('"detail": "');   SB.Append(JsonEscape(F.MissingVar));       SB.Append('"');
        if i < Findings.Count - 1 then
          SB.AppendLine('},')
        else
          SB.AppendLine('}');
      end;
    end;
    SB.AppendLine(']');
    // Direkt aus dem Builder, ohne den Umweg ToString -> TStringList ->
    // SaveToStream. Der Umweg legte vier Vollkopien des Reports an, bevor
    // das erste Byte auf Platte lag - siehe TReportFileWriter.
    // Der Inhalt
    // ist dabei unveraendert: JsonEscape neutralisiert #10 und #13, im
    // Builder stehen also nur die AppendLine-Umbrueche, und genau die
    // hat die TStringList zerlegt und wieder zusammengesetzt.
    TReportFileWriter.SaveBuilderUtf8(SB, FileName, False);
  finally
    SB.Free;
  end;
end;

{ ---- Jira / Clipboard / HTML ----------------------------------------------- }

class function TExporter.SameSourceFile(const A, B: string): Boolean;
// Seit D1 (2026-09-19) reine Delegation: der Pfadvergleich ist
// Querschnitt fuer Infrastructure UND Output und lebt darum in
// TDetectorUtils (Common) - Doku und Tail-Vertrag dort.
begin
  Result := TDetectorUtils.SameSourceFile(A, B);
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
