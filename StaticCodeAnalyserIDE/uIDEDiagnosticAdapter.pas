unit uIDEDiagnosticAdapter;

// Adapter Engine-Findings -> IDE-Diagnostics.
// Konvertiert TLeakFinding (uMethodd12) zu TDiagnostic (uIDEDiagnostic).
//
// Sprint A von Konzept_DiagnosticsHints.md (lokal).
//
// Range-Heuristik (Phase 1):
//   * LineNumber aus Finding -> StartLine = EndLine
//   * Token-Lookup: MissingVar oder MethodName in der Zeile suchen,
//     wenn gefunden -> praezise StartCol/EndCol
//   * Sonst: FromLine(line) = ganze Zeile

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12, uRuleCatalog,
  uIDEDiagnostic;

type
  TDiagnosticAdapter = class
  public
    // Einzel-Konvertierung. ASourceLines kann nil sein -> Range fallback
    // auf ganze Zeile (kein Token-Lookup).
    class function FromFinding(F: TLeakFinding;
                               ASourceLines: TStrings): TDiagnostic; static;

    // Batch-Konvertierung. Liste in Store-Ownership uebergeben.
    // Caller verliert die Diagnostics-Liste nach Uebergabe an
    // TDiagnosticStore.UpdateFile.
    class function FromFindingsList(
      AFindings: TObjectList<TLeakFinding>;
      const AFileName: string;
      ASourceLines: TStrings): TObjectList<TDiagnostic>; static;

    // Gruppiert eine flache Findings-Liste nach FileName fuer
    // Batch-Update im Store.
    class function GroupByFile(
      AFindings: TObjectList<TLeakFinding>):
      TObjectDictionary<string, TList<TLeakFinding>>; static;
  end;

implementation

function GuessRange(F: TLeakFinding;
  ASourceLines: TStrings): TDiagnosticRange;
var
  LineIdx, P : Integer;
  Line, Token : string;
begin
  LineIdx := StrToIntDef(F.LineNumber, 0);
  if LineIdx <= 0 then
  begin
    Result := TDiagnosticRange.FromLine(1);
    Exit;
  end;
  Result := TDiagnosticRange.FromLine(LineIdx);
  if ASourceLines = nil then Exit;
  if LineIdx > ASourceLines.Count then Exit;
  Line := ASourceLines[LineIdx - 1];

  // Token-Praezisierung: MissingVar bevorzugt, sonst MethodName-Suffix
  Token := Trim(F.MissingVar);
  if Token = '' then
  begin
    Token := F.MethodName;
    // 'TFoo.Bar' -> 'Bar' (Method-Suffix)
    P := LastDelimiter('.', Token);
    if P > 0 then Token := Copy(Token, P + 1, MaxInt);
  end;
  Token := Trim(Token);
  if Token = '' then Exit;

  P := Pos(Token, Line);
  if P > 0 then
    Result := TDiagnosticRange.FromTokenInLine(LineIdx, P, Length(Token));
end;

function SeverityToTitle(S: TDiagnosticSeverity): string;
begin
  case S of
    dsError:   Result := 'Moeglicher Fehler';
    dsWarning: Result := 'Warnung';
    dsHint:    Result := 'Hinweis';
  else
    Result := 'Hinweis';
  end;
end;

class function TDiagnosticAdapter.FromFinding(F: TLeakFinding;
  ASourceLines: TStrings): TDiagnostic;
var
  Sev : TDiagnosticSeverity;
begin
  Result := TDiagnostic.Create;
  Result.FileName    := F.FileName;
  Result.Kind        := F.Kind;
  Sev                := MapSeverity(F.Severity);
  Result.Severity    := Sev;
  Result.Title       := SeverityToTitle(Sev);
  Result.Message     := F.MissingVar;
  Result.Range       := GuessRange(F, ASourceLines);

  // RuleId + Description aus Catalog (GetRule liefert TRuleMeta)
  var Meta := TRuleCatalog.GetRule(F.Kind);
  if F.RuleID <> '' then
    Result.RuleId := F.RuleID
  else
    Result.RuleId := Meta.ID;
  // ShortDescription = einzeilige Description (passt ins Overlay).
  Result.Description := Meta.ShortDescription;
  Result.Example     := '';  // Phase 2 (Catalog erweitern)

  // QuickFix-Marker: heute heuristisch via uQuickFix-Action-Liste.
  // Phase 2 explizit per Finding-Side QuickFixId.
  Result.HasQuickFix := False;
  Result.QuickFixId  := '';
end;

class function TDiagnosticAdapter.FromFindingsList(
  AFindings: TObjectList<TLeakFinding>;
  const AFileName: string;
  ASourceLines: TStrings): TObjectList<TDiagnostic>;
var
  F : TLeakFinding;
  D : TDiagnostic;
begin
  Result := TObjectList<TDiagnostic>.Create(True);
  if AFindings = nil then Exit;
  for F in AFindings do
  begin
    if not SameText(F.FileName, AFileName) then Continue;
    D := FromFinding(F, ASourceLines);
    Result.Add(D);
  end;
end;

class function TDiagnosticAdapter.GroupByFile(
  AFindings: TObjectList<TLeakFinding>):
  TObjectDictionary<string, TList<TLeakFinding>>;
var
  F : TLeakFinding;
  L : TList<TLeakFinding>;
  Key : string;
begin
  Result := TObjectDictionary<string, TList<TLeakFinding>>.Create([doOwnsValues]);
  if AFindings = nil then Exit;
  for F in AFindings do
  begin
    Key := LowerCase(F.FileName);
    if not Result.TryGetValue(Key, L) then
    begin
      L := TList<TLeakFinding>.Create;
      Result.Add(Key, L);
    end;
    L.Add(F);  // nicht owns - AFindings besitzt die Findings weiter
  end;
end;

end.
