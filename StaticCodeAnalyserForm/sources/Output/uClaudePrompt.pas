unit uClaudePrompt;

// Erzeugt einen Markdown-Block, der einem Claude-AI-Chat als Prompt dienen
// kann: Befund-Metadaten, FixHint (Vorher/Nachher) und Code-Auszug
// (+/-CONTEXT_LINES) aus der Quelldatei mit hervorgehobener Befund-Zeile.
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
  System.SysUtils, System.Classes;

const
  CONTEXT_LINES = 5;

class function TClaudePrompt.KindToName(K: TFindingKind): string;
// Delegiert an KIND_META in uSCAConsts (single source of truth).
begin
  Result := KindName(K);
end;

class function TClaudePrompt.LoadSnippet(const APath: string;
  ALine: Integer): string;
// Liest +/- CONTEXT_LINES Zeilen um ALine herum, mit "> " als Marker
// auf der Befund-Zeile. Robust gegen Encoding-Probleme: erst UTF-8
// versuchen, dann System-Default als Fallback.
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
        if (i + 1) = ALine then Marker := '> ' else Marker := '  ';
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
    SB.AppendLine('# Code-Analyse Befund');
    SB.AppendLine('');
    SB.AppendLine('| Feld | Wert |');
    SB.AppendLine('|------|------|');
    SB.AppendLine('| Datei | `' + F.FileName + '` |');
    SB.AppendLine('| Zeile | ' + F.LineNumber + ' |');
    if F.MethodName <> '' then
      SB.AppendLine('| Methode | `' + F.MethodName + '` |');
    SB.AppendLine('| Schweregrad | ' + F.SeverityText + ' |');
    SB.AppendLine('| Typ | ' + F.TypeText + ' |');
    SB.AppendLine('| Regel | ' + KindToName(F.Kind) + ' |');
    SB.AppendLine('| Detail | ' + F.MissingVar + ' |');
    SB.AppendLine('');

    if Hint.Description <> '' then
    begin
      SB.AppendLine('## Beschreibung');
      SB.AppendLine(Hint.Description);
      SB.AppendLine('');
    end;

    if Snippet <> '' then
    begin
      SB.AppendLine('## Code-Kontext');
      SB.AppendLine('```pascal');
      SB.Append(Snippet);
      SB.AppendLine('```');
      SB.AppendLine('');
    end;

    if Hint.Before <> '' then
    begin
      SB.AppendLine('## Vorher (Problem)');
      SB.AppendLine('```pascal');
      SB.AppendLine(Hint.Before);
      SB.AppendLine('```');
      SB.AppendLine('');
    end;

    if Hint.After <> '' then
    begin
      SB.AppendLine('## Nachher (Loesung)');
      SB.AppendLine('```pascal');
      SB.AppendLine(Hint.After);
      SB.AppendLine('```');
      SB.AppendLine('');
    end;

    SB.AppendLine('---');
    SB.AppendLine('Bitte schlage einen konkreten Fix fuer die markierte ' +
      'Code-Stelle vor. Erklaere kurz die Ursache und liefere den ' +
      'angepassten Code-Block.');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

end.
