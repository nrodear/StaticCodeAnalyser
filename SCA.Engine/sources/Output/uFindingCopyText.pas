unit uFindingCopyText;

// Baut den Text, den der KLICK auf eine Befund-Zeile in die Zwischenablage
// legt - gesteuert durch [UI] ClipboardOnClick (TRepoSettings, Werte 1..3,
// Nutzerentscheid 2026-08-12):
//
//   1 = fcmNone         - Zwischenablage NICHT anfassen (Default)
//   2 = fcmJiraMini     - Jira-Mini-Issue: 1 Headline + 5 Fakten-Bullets
//   3 = fcmClaudePrompt - vollstaendiger Claude-AI-Prompt (uClaudePrompt)
//
// Die Unit kennt bewusst KEINE UI und KEIN TRepoSettings - sie bekommt den
// fertigen Modus. Die Consumer (uMainForm, uIDEAnalyserForm) lesen den
// ini-Wert und mappen ihn ueber FindingCopyModeFromInt. Beschriftungen
// laufen ueber uLocalization (englische msgids, Uebersetzung via .po);
// die Befund-INHALTE (Regel-ID, Meldetext, Pfade) bleiben wie geliefert.

interface

uses
  System.Generics.Collections,   // TObjectList (Datei-Ebene, D1)
  uSCAConsts, uMethodd12, uFixHint;

type
  // Die drei Auspraegungen von [UI] ClipboardOnClick. Reihenfolge folgt
  // der ini-Nummerierung (Ord+1 = ini-Wert).
  TFindingCopyMode = (fcmNone, fcmJiraMini, fcmClaudePrompt);

  TFindingCopyText = class
  public
    // Text fuer den Klick-Pfad; '' bei fcmNone - der Aufrufer laesst die
    // Zwischenablage dann unangetastet. FixHint via TFixHintResolver.
    class function Build(F: TLeakFinding; AMode: TFindingCopyMode): string;
      overload; static;

    // Variante mit explizitem FixHint - falls der Aufrufer eine andere
    // Hint-Quelle hat (Muster wie TClaudePrompt.Build).
    class function Build(F: TLeakFinding; AMode: TFindingCopyMode;
      const AHint: TFixHint): string; overload; static;

    // ---- Datei-Ebene (D1-Umzug 2026-09-19 aus TExporter) ----
    // Die drei sind reine TEXTBAUER ohne Datei-I/O und Schwestern von
    // BuildJiraMini - darum leben sie hier (Output) und nicht mehr in
    // der Infrastructure; zugleich Teil 2 der SCA141-Folgearbeit.

    // Jira-Wiki-Markup fuer Befunde einer einzelnen Datei. Severity-
    // Auswahl ueber Filter-Set (z.B. [lsError, lsWarning]). Liefert den
    // fertigen Text - speichern oder Zwischenablage ist Aufrufer-Sache.
    class function BuildJiraText(Findings: TObjectList<TLeakFinding>;
      const SourceFile: string;
      const SeverityFilter: TSeverityFilter): string; static;

    // Zwischenablage-tauglicher Plain-Text mit Fehler+Warnung fuer eine
    // einzelne Datei. Format: "<Severity> [Zeile] <Regel>: <Detail>"
    class function BuildClipboardText(Findings: TObjectList<TLeakFinding>;
      const SourceFile: string;
      const SeverityFilter: TSeverityFilter): string; static;

    // Jira-Wiki-Escaping (|, *, _, ... per Backslash; Umbrueche zu
    // Leerzeichen). Public, weil auch BuildJiraMini-Nachbarn im
    // UI-Umfeld Jira-Text bauen koennten - heute intern genutzt.
    class function JiraEscape(const S: string): string; static;

  private
    class function BuildJiraMini(F: TLeakFinding;
      const AHint: TFixHint): string; static;
  end;

// Mappt den rohen ini-Wert auf den Modus. Alles ausser 2 und 3 faellt
// defensiv auf fcmNone zurueck - zweite Verteidigungslinie hinter der
// Klemmung in TRepoSettings.Load (dort ungueltig -> 1).
function FindingCopyModeFromInt(AValue: Integer): TFindingCopyMode;

implementation

uses
  System.SysUtils, System.Character,
  System.Classes,      // TStringList (AppendIndented, D1)
  uClaudePrompt, uLocalization,
  uDetectorUtils;      // SameSourceFile (D1)

const
  // Fakten-Zeilen werden einzeilig gehalten und hart gekuerzt - ein
  // Mini-Issue soll in die Jira-Beschreibung passen, nicht sie fluten
  // (Nutzer-Vorgabe: je Fakt knapp, Groessenordnung 20 Worte).
  MAX_FACT_LEN = 160;
  // Der Meldetext in der Headline ist noch knapper - Jira zeigt die
  // Summary-Zeile in Listen, dort zaehlt jedes Zeichen.
  MAX_HEAD_LEN = 80;
  ELLIPSIS     = '...';

function FindingCopyModeFromInt(AValue: Integer): TFindingCopyMode;
begin
  case AValue of
    2:
    begin
      Result := fcmJiraMini;
    end;
    3:
    begin
      Result := fcmClaudePrompt;
    end;
  else
  begin
    Result := fcmNone;
  end;
  end;
end;

function OneLine(const S: string): string;
// Zeilenumbrueche und Tabs zu Leerzeichen glaetten und Mehrfach-
// Leerzeichen zusammenziehen - jede Fakten-Zeile bleibt EINE Zeile,
// sonst zerfaellt die Bullet-Struktur beim Einfuegen in Jira.
var
  i       : Integer;
  Ch      : Char;
  PrevWs  : Boolean;
  Builder : TStringBuilder;
begin
  Builder := TStringBuilder.Create(Length(S));
  try
    PrevWs := False;
    for i := 1 to Length(S) do
    begin
      Ch := S[i];
      if Ch.IsWhiteSpace then
      begin
        if not PrevWs then
        begin
          Builder.Append(' ');
        end;
        PrevWs := True;
      end
      else
      begin
        Builder.Append(Ch);
        PrevWs := False;
      end;
    end;
    Result := Trim(Builder.ToString);
  finally
    Builder.Free;
  end;
end;

function Crop(const S: string; AMax: Integer): string;
// OneLine + harte Kuerzung mit '...' - nie mitten im Glaetten aufgeben,
// erst glaetten, dann messen.
begin
  Result := OneLine(S);
  if Length(Result) <= AMax then Exit;
  if AMax <= Length(ELLIPSIS) then
  begin
    // Zu klein fuer eine Ellipse: blanke harte Kuerzung. Heute
    // unerreichbar (Aufrufer nutzen 80/160), aber die Zusicherung
    // "Ergebnis <= AMax" soll auch kuenftige Aufrufer tragen.
    Result := Copy(Result, 1, AMax);
    Exit;
  end;
  Result := Copy(Result, 1, AMax - Length(ELLIPSIS));
  // Kein haengendes High-Surrogate vor der Ellipse zuruecklassen - der
  // Schnitt arbeitet auf UTF-16-Code-Units und kann ein Emoji/non-BMP-
  // Zeichen im Meldetext halbieren; die halbe Einheit renderte in Jira
  // als Ersatzzeichen.
  if (Result <> '') and Result[Length(Result)].IsHighSurrogate then
  begin
    SetLength(Result, Length(Result) - 1);
  end;
  Result := Result + ELLIPSIS;
end;

function FactOrDash(const S: string): string;
// Leere Fakten als '-' zeigen: die Beschreibung hat damit deterministisch
// IMMER fuenf Bullets, Leser und Weiterverarbeiter muessen nicht raten,
// ob eine Zeile fehlt oder leer ist.
begin
  Result := Crop(S, MAX_FACT_LEN);
  if Result = '' then
  begin
    Result := '-';
  end;
end;

function LineSpanText(F: TLeakFinding): string;
// '42' - oder '42-47' bei mehrzeiligen Befunden (SpanEnd ist geklemmt,
// siehe uMethodd12).
begin
  Result := IntToStr(F.LineInt);
  if F.IsMultiLine then
  begin
    Result := Result + '-' + IntToStr(F.SpanEnd);
  end;
end;

{ TFindingCopyText }

class function TFindingCopyText.Build(F: TLeakFinding;
  AMode: TFindingCopyMode): string;
begin
  // Nil-Guard VOR der Hint-Aufloesung: TFixHintResolver.FixHint
  // dereferenziert das Finding, und Delphi wertet Argumente vor dem
  // Guard der Ziel-Ueberladung aus - beide Ueberladungen sollen fuer
  // nil dasselbe zusichern ('').
  Result := '';
  if not Assigned(F) then Exit;
  Result := Build(F, AMode, TFixHintResolver.FixHint(F));
end;

class function TFindingCopyText.Build(F: TLeakFinding;
  AMode: TFindingCopyMode; const AHint: TFixHint): string;
begin
  Result := '';
  if not Assigned(F) then Exit;
  case AMode of
    fcmJiraMini:
    begin
      Result := BuildJiraMini(F, AHint);
    end;
    fcmClaudePrompt:
    begin
      Result := TClaudePrompt.Build(F, AHint);
    end;
  else
  begin
    // fcmNone - der Aufrufer fasst die Zwischenablage nicht an.
    Result := '';
  end;
  end;
end;

class function TFindingCopyText.BuildJiraMini(F: TLeakFinding;
  const AHint: TFixHint): string;
// 1 Headline (Jira-Summary-Zeile), Leerzeile, dann exakt 5 Fakten als
// Wiki-Bullets. Bewusst OHNE Jira-Tabellen-Markup: einfache Bullets
// brauchen kein Escaping-Regelwerk. (Das Schichtungs-Argument von
// frueher - JiraEscape lag in der Infrastructure - ist seit dem
// D1-Umzug hinfaellig: JiraEscape lebt jetzt in DIESER Klasse; die
// Bullets bleiben trotzdem escaping-frei, weil OneLine/Crop die
// kritischen Umbrueche ohnehin glaetten und ein Mini-Issue lesbar
// bleiben soll.)
var
  SB : TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    // [SCA001] MemoryLeak - Demo.pas:42 - list1 wird nie freigegeben
    SB.Append('[').Append(F.ResolvedRuleId).Append('] ');
    SB.Append(KindName(F.Kind));
    SB.Append(' - ').Append(ExtractFileName(F.FileName));
    SB.Append(':').Append(LineSpanText(F));
    if OneLine(F.MissingVar) <> '' then
    begin
      SB.Append(' - ').Append(Crop(F.MissingVar, MAX_HEAD_LEN));
    end;
    SB.AppendLine;
    SB.AppendLine;

    SB.Append('* ').Append(_('Rule')).Append(': ')
      .Append(FactOrDash(F.ResolvedRuleId + ' ' + KindName(F.Kind)))
      .AppendLine;
    SB.Append('* ').Append(_('File')).Append(': ')
      .Append(FactOrDash(F.FileName + ':' + LineSpanText(F)))
      .AppendLine;
    SB.Append('* ').Append(_('Method')).Append(': ')
      .Append(FactOrDash(F.MethodName))
      .AppendLine;
    SB.Append('* ').Append(_('Message')).Append(': ')
      .Append(FactOrDash(F.MissingVar))
      .AppendLine;
    SB.Append('* ').Append(_('Fix hint')).Append(': ')
      .Append(FactOrDash(AHint.Description))
      .AppendLine;

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;


{ ---- Datei-Ebene: Jira-/Clipboard-Text (D1-Umzug 2026-09-19) ---- }

class function TFindingCopyText.JiraEscape(const S: string): string;
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

class function TFindingCopyText.BuildJiraText(Findings: TObjectList<TLeakFinding>;
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
        if (SourceFile <> '') and not TDetectorUtils.SameSourceFile(F.FileName, SourceFile) then
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
        SB.Append(' | ');     SB.Append(JiraEscape(KindName(F.Kind)));
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
        if (SourceFile <> '') and not TDetectorUtils.SameSourceFile(F.FileName, SourceFile) then
          Continue;

        // Voll-Review, umgesetzt 2026-09-15: hier standen die drei
        // Severity-Namen HART DEUTSCH ('Fehler', 'Warnung', 'Hinweis'),
        // waehrend die Tabelle weiter oben im SELBEN Dokument
        // _('Error') / _('Warning') / _('Hint') benutzt. Bei englischer
        // Oberflaeche widersprach sich ein und derselbe Bericht: oben
        // "Error", unten "Fehler". Jetzt beide Stellen ueber dieselben
        // msgids - neue Eintraege brauchte es dafuer keine, alle drei
        // stehen seit jeher in i18n/*.po.
        case F.Severity of
          lsError   : SevLabel := Format('{color:red}*%s*{color}', [_('Error')]);
          lsWarning : SevLabel := Format('{color:#b07000}%s{color}', [_('Warning')]);
          lsHint    : SevLabel := Format('{color:#5a8000}%s{color}', [_('Hint')]);
        else
          SevLabel := '';
        end;

        // Header pro Befund: "h4. <Severity> - <Line> <nr> - <Kind> - <Detail>"
        // Das abgekuerzte 'Z.' war die vierte harte Stelle; _('Line')
        // fuehrt die Tabellenueberschrift oben ohnehin schon.
        SB.Append('h4. ');
        SB.Append(SevLabel);
        SB.Append(' - ');
        SB.Append(_('Line'));
        SB.Append(' ');
        SB.Append(JiraEscape(F.LineNumber));
        if F.MethodName <> '' then
        begin
          SB.Append(' - ');
          SB.Append(JiraEscape(F.MethodName));
        end;
        SB.Append(' - ');
        SB.Append(JiraEscape(KindName(F.Kind)));
        SB.Append(' - ');
        SB.AppendLine(JiraEscape(F.MissingVar));

        Hint := TFixHintResolver.FixHint(F);
        if Hint.Description <> '' then
        begin
          SB.Append('bq. ');
          SB.AppendLine(JiraEscape(Hint.Description));
        end;
        // Auch diese beiden waren hart deutsch; 'Before:'/'After:'
        // stehen bereits als msgid in i18n/*.po.
        if Hint.Before <> '' then
        begin
          SB.AppendLine(Format('*%s*', [_('Before:')]));
          SB.AppendLine('{code:delphi}');
          SB.AppendLine(Hint.Before);
          SB.AppendLine('{code}');
        end;
        if Hint.After <> '' then
        begin
          SB.AppendLine(Format('*%s*', [_('After:')]));
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

class function TFindingCopyText.BuildClipboardText(Findings: TObjectList<TLeakFinding>;
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
        if (SourceFile <> '') and not TDetectorUtils.SameSourceFile(F.FileName, SourceFile) then
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
        SB.Append(KindName(F.Kind));
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


end.
