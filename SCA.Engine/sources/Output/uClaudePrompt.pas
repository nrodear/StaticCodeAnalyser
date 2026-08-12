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
    class function LoadSnippet(const APath: string;
      ALine: Integer): string; static;
  end;

implementation

// noinspection-file BeginEndRequired, CanBeStrictPrivate, ClassPerFile, DuplicateString, GroupedDeclaration, LongMethod, MultipleExit, NestedTry, NilComparison, PublicField, RedundantJump, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.
// ClassPerFile/PublicField: TSnippetEntry ist ein implementation-lokaler
// Cache-Slot (struct-artig, nie exportiert) - eine eigene Unit oder
// Property-Huellen waeren Zeremonie ohne Schutzwirkung.

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uLocalization;

const
  CONTEXT_LINES = 5;
  // UI-scope LRU: ueblicher Klick-Workflow trifft mehrfach dieselbe Datei
  // (mehrere Befunde im selben Modul). 4 Slots decken Hin-und-Her zwischen
  // verschiedenen Modulen ab, ohne Memory nennenswert zu kosten.
  SNIPPET_CACHE_CAPACITY = 4;

type
  // Ein Cache-Slot des Modul-LRU: Zeilen plus Gueltigkeitsstempel der
  // Quelldatei. Ein einziges Objekt je Slot statt der frueheren
  // Parallel-Listen (Pfade/Daten) - die konnten bei einer Ausnahme
  // zwischen den beiden Inserts dauerhaft auseinanderlaufen.
  TSnippetEntry = class
  public
    Path  : string;       // LowerCase(ExpandFileName(...)) als Schluessel
    Lines : TStringList;  // owned - Destroy gibt sie frei
    Stamp : TDateTime;    // LastWriteTime der Datei beim Laden
    Size  : Int64;        // Dateigroesse beim Laden
    destructor Destroy; override;
  end;

destructor TSnippetEntry.Destroy;
begin
  Lines.Free;
  inherited;
end;

var
  // Modul-LRU: MRU=Index 0, LRU=Index Count-1.
  // gFileTextCache aus uFileTextCache ist scan-scoped und nach dem Lauf nil -
  // dieser Cache lebt fuer die Form-Lebenszeit, damit aufeinanderfolgende
  // Klicks auf Befunde derselben Datei nicht jedes Mal LoadFromFile ausloesen.
  FSnippets : TObjectList<TSnippetEntry> = nil;   // OwnsObjects = True

function FileStamp(const APath: string; var AStamp: TDateTime;
  var ASize: Int64): Boolean;
// Aenderungszeit UND Groesse in EINEM Plattenzugriff (FindFirst); False
// wenn die Datei fehlt oder nicht erreichbar ist.
var
  SR : TSearchRec;
begin
  AStamp := 0;
  ASize  := 0;
  Result := FindFirst(APath, faAnyFile, SR) = 0;
  if not Result then Exit;
  try
    AStamp := SR.TimeStamp;
    ASize  := SR.Size;
  finally
    FindClose(SR);
  end;
end;

procedure DropCachedEntry(const AKey: string);
// Entfernt einen etwaigen Cache-Eintrag zu AKey - etwa weil die Datei
// verschwunden ist und der Slot sonst Zeilen einer geloeschten Datei
// lieferte.
var
  i : Integer;
begin
  for i := FSnippets.Count - 1 downto 0 do
    if FSnippets[i].Path = AKey then
      FSnippets.Delete(i);
end;

function CachedLines(const AKey: string; const AStamp: TDateTime;
  ASize: Int64): TStringList;
// Liefert den GUELTIGEN Cache-Treffer (und zieht ihn auf MRU) oder nil.
//
// GUELTIGKEIT (Review-Blocker 2026-08-12): der Cache lebt fuer die
// Prozess-Lebenszeit. Ohne Stempelvergleich lieferte er nach "Befund
// klicken -> Datei fixen -> neu scannen -> klicken" den ALTEN Code mit
// falsch sitzendem >>>-Marker in den Prompt - genau das Artefakt, das
// der Nutzer einer AI vorlegt. Ein veralteter Treffer wird entfernt,
// der Aufrufer laedt dann frisch.
var
  i : Integer;
begin
  Result := nil;
  for i := 0 to FSnippets.Count - 1 do
  begin
    if FSnippets[i].Path <> AKey then Continue;
    if (FSnippets[i].Stamp = AStamp) and (FSnippets[i].Size = ASize) then
    begin
      Result := FSnippets[i].Lines;
      if i > 0 then
        FSnippets.Move(i, 0);   // Hit -> MRU; Move loescht nicht
    end
    else
    begin
      FSnippets.Delete(i);      // veraltet
    end;
    Exit;
  end;
end;

function GetSnippetLines(const APath: string): TStringList;
// Holt die Zeilen der Datei aus dem LRU-Cache; laed sie bei Bedarf nach.
// Liefert nil wenn die Datei nicht lesbar ist. Caller MUSS die Liste NICHT
// freigeben - der Cache besitzt sie.
var
  Key   : string;
  Stamp : TDateTime;
  Size  : Int64;
  E     : TSnippetEntry;
  SL    : TStringList;
begin
  Result := nil;
  if FSnippets = nil then
    FSnippets := TObjectList<TSnippetEntry>.Create(True);

  Key   := LowerCase(ExpandFileName(APath));
  Stamp := 0;
  Size  := 0;
  if not FileStamp(APath, Stamp, Size) then
  begin
    DropCachedEntry(Key);
    Exit;
  end;

  Result := CachedLines(Key, Stamp, Size);
  if Result <> nil then Exit;

  // Miss -> laden. Encoding-Strategie identisch zum vorherigen Code
  // (UTF-8, sonst System-Default). Der Fallback faengt beide Fehlerwege;
  // das fruehere AEUSSERE try/except um diesen Block war tot.
  SL := TStringList.Create;
  try
    SL.LoadFromFile(APath, TEncoding.UTF8);
  except
    try SL.LoadFromFile(APath); except FreeAndNil(SL); Exit; end;
  end;

  E := TSnippetEntry.Create;
  E.Path  := Key;
  E.Lines := SL;
  E.Stamp := Stamp;
  E.Size  := Size;
  FSnippets.Insert(0, E);

  // Tail verdraengen bis wir wieder unter der Capacity sind. OwnsObjects=True
  // gibt den Eintrag samt Zeilen mit der Delete-Operation frei.
  while FSnippets.Count > SNIPPET_CACHE_CAPACITY do
    FSnippets.Delete(FSnippets.Count - 1);

  Result := SL;
end;

class function TClaudePrompt.LoadSnippet(const APath: string;
  ALine: Integer): string;
// Liest +/- CONTEXT_LINES Zeilen um ALine herum, mit ">>> " als Marker
// auf der Befund-Zeile. Zeilen kommen aus dem Modul-LRU - bei wiederholten
// Klicks auf Befunde derselben Datei spart das den LoadFromFile-Roundtrip
// (bei 150k+ Befunden im selben Modul war das die spuerbare Klick-Latenz).
var
  SL                : TStringList;
  SB                : TStringBuilder;
  i, FromIdx, ToIdx : Integer;
  Marker            : string;
begin
  Result := '';
  if (APath = '') or (ALine <= 0) then Exit;

  SL := GetSnippetLines(APath);
  if SL = nil then Exit;            // Datei fehlt oder nicht lesbar

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
    SB.AppendLine('| ' + _('Rule') + ' | `' + KindName(F.Kind) + '` |');
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
      [KindName(F.Kind)]));
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

initialization

finalization
  // LRU sauber abbauen. OwnsObjects=True gibt die Eintraege samt ihrer
  // TStringList-Instanzen mit Free der TObjectList automatisch frei.
  FreeAndNil(FSnippets);

end.
