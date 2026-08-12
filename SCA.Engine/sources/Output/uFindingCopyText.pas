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
  uClaudePrompt, uLocalization;

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
// brauchen kein Escaping-Regelwerk (TExporter.JiraEscape liegt in der
// Infrastructure-Schicht; Wiederverwendung wuerde die Schichtung
// Output <- Infrastructure invertieren - Zentralisierung erst beim
// dritten Escape-Konsumenten, Rule of Three).
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

end.
