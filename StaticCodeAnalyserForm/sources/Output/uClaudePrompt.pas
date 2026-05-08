unit uClaudePrompt;

// Erzeugt einen Markdown-Block, der einem Claude-/GPT-/Gemini-AI-Chat als
// Prompt dienen kann: Role-Priming, Befund-Metadaten, Code-Auszug
// (+/-CONTEXT_LINES) mit hervorgehobener Befund-Zeile, optional FixHint
// (Vorher/Nachher als Beispiel-Pattern markiert) und eine strukturierte
// Antwort-Vorgabe (Ursache / Fix / Test).
//
// Text-Bestandteile (Headings, Instruktionen) sind ueber uLocalization
// uebersetzbar - die AI antwortet typischerweise in der Prompt-Sprache,
// d.h. ein DE-User bekommt automatisch deutsche AI-Antworten.
//
// Diese Unit war zuvor 1:1 in uMainForm.pas und uIDEAnalyserForm.pas
// dupliziert - jetzt zentral und identisch fuer Standalone-App und
// IDE-Plugin.

interface

uses
  uSCAConsts, uMethodd12, uFixHint;

type
  TClaudePrompt = class
  public
    // Vollstaendiger Prompt mit FixHint via TFixHintResolver. Default-API.
    class function Build(F: TLeakFinding): string; overload; static;

    // Variante mit explizitem FixHint - falls der Aufrufer eine andere
    // Hint-Quelle hat (z.B. das IDE-Plugin nutzte zuvor eine eigene
    // class-Helper-Methode mit identischer Logik).
    class function Build(F: TLeakFinding; const Hint: TFixHint): string;
      overload; static;

  private
    class function KindToName(K: TFindingKind): string; static;
    class function LoadSnippet(const APath: string;
      ALine: Integer): string; static;
  end;

implementation

uses
  System.SysUtils, System.Classes, uLocalization;

const
  CONTEXT_LINES = 5;

class function TClaudePrompt.KindToName(K: TFindingKind): string;
// Delegiert an KIND_META in uSCAConsts (single source of truth).
begin
  Result := KindName(K);
end;

class function TClaudePrompt.LoadSnippet(const APath: string;
  ALine: Integer): string;
// Liest +/- CONTEXT_LINES Zeilen um ALine herum, mit ">>> " als Marker
// auf der Befund-Zeile (deutlich auffaelliger als nur ">"). Robust gegen
// Encoding-Probleme: erst UTF-8 versuchen, dann System-Default als Fallback.
var
  SL                : TStringList;
  SB                : TStringBuilder;
  i, FromIdx, ToIdx : Integer;
  Marker            : string;
begin
  Result := '';
  if (APath = '') or (ALine <= 0) or not FileExists(APath) then Exit;

  SL := TStringList.Create;
  try
    try
      SL.LoadFromFile(APath, TEncoding.UTF8);
    except
      try SL.LoadFromFile(APath); except Exit; end;
    end;

    FromIdx := ALine - 1 - CONTEXT_LINES;
    ToIdx   := ALine - 1 + CONTEXT_LINES;
    if FromIdx < 0 then FromIdx := 0;
    if ToIdx > SL.Count - 1 then ToIdx := SL.Count - 1;
    if FromIdx > ToIdx then Exit;

    SB := TStringBuilder.Create;
    try
      for i := FromIdx to ToIdx do
      begin
        if (i + 1) = ALine then Marker := '>>> ' else Marker := '    ';
        SB.Append(Marker);
        SB.Append(Format('%4d  ', [i + 1]));
        SB.AppendLine(SL[i]);
      end;
      Result := SB.ToString;
    finally
      SB.Free;
    end;
  finally
    SL.Free;
  end;
end;

class function TClaudePrompt.Build(F: TLeakFinding): string;
begin
  Result := Build(F, TFixHintResolver.FixHint(F));
end;

class function TClaudePrompt.Build(F: TLeakFinding;
  const Hint: TFixHint): string;
var
  SB      : TStringBuilder;
  Line    : Integer;
  Snippet : string;
begin
  Line    := StrToIntDef(F.LineNumber, 0);
  Snippet := LoadSnippet(F.FileName, Line);

  SB := TStringBuilder.Create;
  try
    // -- Role-Priming + Quelle der Daten ----------------------------------
    SB.AppendLine('# ' + _('Code review request - Delphi static analysis finding'));
    SB.AppendLine('');
    SB.AppendLine(_('You are a senior Delphi developer reviewing the output ' +
      'of a static code analyser. Target version: Delphi 12 Athens (RTL/VCL). ' +
      'Suggest minimal, idiomatic fixes - no sweeping refactors, no style ' +
      'overhauls, no new dependencies unless strictly required.'));
    SB.AppendLine('');

    // -- Metadaten als Tabelle --------------------------------------------
    SB.AppendLine('## ' + _('Finding'));
    SB.AppendLine('');
    SB.AppendLine('| ' + _('Field') + ' | ' + _('Value') + ' |');
    SB.AppendLine('|------|------|');
    SB.AppendLine('| ' + _('File') + ' | `' + F.FileName + '` |');
    SB.AppendLine('| ' + _('Line') + ' | ' + F.LineNumber + ' |');
    if F.MethodName <> '' then
      SB.AppendLine('| ' + _('Method') + ' | `' + F.MethodName + '` |');
    SB.AppendLine('| ' + _('Severity') + ' | ' + F.SeverityText + ' |');
    SB.AppendLine('| ' + _('Type') + ' | ' + F.TypeText + ' |');
    SB.AppendLine('| ' + _('Rule') + ' | `' + KindToName(F.Kind) + '` |');
    SB.AppendLine('| ' + _('Detail') + ' | ' + F.MissingVar + ' |');
    SB.AppendLine('');

    if Hint.Description <> '' then
    begin
      SB.AppendLine('## ' + _('Rule description'));
      SB.AppendLine(Hint.Description);
      SB.AppendLine('');
    end;

    // -- Eigentlicher Code-Snippet (PRIMARY EVIDENCE) --------------------
    if Snippet <> '' then
    begin
      SB.AppendLine('## ' + _('Code (>>> marks the line that triggered the rule)'));
      SB.AppendLine('```pascal');
      SB.Append(Snippet);
      SB.AppendLine('```');
      SB.AppendLine('');
    end;

    // -- Vorher/Nachher als Beispiel-Pattern markieren --------------------
    if (Hint.Before <> '') or (Hint.After <> '') then
    begin
      SB.AppendLine('## ' + _('Reference pattern (generic example for this rule, NOT the user''s code)'));
      SB.AppendLine('');
      if Hint.Before <> '' then
      begin
        SB.AppendLine('**' + _('Anti-pattern') + ':**');
        SB.AppendLine('```pascal');
        SB.AppendLine(Hint.Before);
        SB.AppendLine('```');
        SB.AppendLine('');
      end;
      if Hint.After <> '' then
      begin
        SB.AppendLine('**' + _('Recommended fix') + ':**');
        SB.AppendLine('```pascal');
        SB.AppendLine(Hint.After);
        SB.AppendLine('```');
        SB.AppendLine('');
      end;
    end;

    // -- Strukturierte Antwort-Vorgabe ------------------------------------
    SB.AppendLine('---');
    SB.AppendLine('## ' + _('Please respond with three sections'));
    SB.AppendLine('');
    SB.AppendLine('1. **' + _('Cause') + '** - ' +
      _('1-2 sentences why the rule fires on THIS specific code (not the generic explanation above).'));
    SB.AppendLine('2. **' + _('Fix') + '** - ' +
      _('the modified code as a Pascal block. Keep diff minimal: only the lines that need to change. Match surrounding indentation and naming style.'));
    SB.AppendLine('3. **' + _('Verify') + '** - ' +
      _('what to test or check after the fix to confirm the issue is gone (and no regressions).'));
    SB.AppendLine('');
    SB.AppendLine(Format(_('If the finding is a false positive, say so and explain why - then suggest a `// noinspection %s` suppression marker on the affected line.'),
      [KindToName(F.Kind)]));
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

end.
