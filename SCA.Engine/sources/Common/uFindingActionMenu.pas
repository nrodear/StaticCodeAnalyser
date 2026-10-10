unit uFindingActionMenu;

// Das Modell eines Aktionsmenues zu Funden - der EINE Erzeuger fuer alle
// Einstiege: Editor-Kontextmenue, Dock-Grid, kuenftig Gluehbirne und
// Alt+Enter (Konzept Editor-Gluehbirne 2026-10-06, Stufe C). Ohne VCL und
// ohne ToolsAPI, damit TestProject es prueft; das Zeichnen als TMenuItem
// macht uIDEFindingActionMenu im Plugin.
//
// Form (wie das Kontextmenue seit AH13): optional ein Trenner vor dem
// ersten Fund mit Aktionen, je Fund optional eine deaktivierte Kopfzeile
// 'SCAnnn  Meldung', darunter die Aktionen 'Caption  (Hint)'. Enabled
// ist Enabled des Anbieters UND Execute zugewiesen; ActionIndex zeigt in
// die flache Liste Actions, ueber die der Host ausfuehrt. Mit
// moAvailableFixesOnly bleiben nur Aktionen, die der Benutzer JETZT
// ausfuehren kann und die etwas aendern (Kind = fakFix, Enabled, Execute
// zugewiesen) - die Form der Gluehbirne: kein "Stelle zeigen", keine
// ausgegrauten Eintraege, keine Diagnosezeilen der Anbieter; ein Fund ohne
// solche Aktion faellt samt Kopfzeile weg. Unterdrueck-Aktionen
// (fakSuppress) bleiben dort NUR, wenn der Fund eine solche Hilfe hat
// (Editorhilfen E1). In jeder Form steht vor dem ersten Unterdrueck-
// Eintrag eines Funds ein Trenner. BuildFindingMenuModel fragt
// hoechstens MAX_FINDINGS_PER_MENU Funde ab (Vertrag in uFindingActions);
// wie viele es nicht fragte, steht in Omitted. Wirft ein
// Anbieter beim Erfragen, fallen die Aktionen DIESES Funds weg (alle
// Anbieter - TFindingActions.ActionsFor wirft als Ganzes), nie das
// Menue; die Meldung landet in Errors, der Host protokolliert sie.

interface

uses
  System.SysUtils,
  uMethodd12, uFindingActions;

type
  TFindingMenuEntryKind = (mkSeparator, mkHeader, mkAction);

  TFindingMenuEntry = record
    Kind        : TFindingMenuEntryKind;
    Caption     : string;
    Hint        : string;
    Enabled     : Boolean;
    ActionIndex : Integer;   // Index in TFindingMenuModel.Actions, -1 sonst
  end;

  TFindingMenuModel = record
    Entries : TArray<TFindingMenuEntry>;
    Actions : TArray<TFindingAction>;
    Errors  : TArray<string>;      // Meldungen werfender Anbieter
    Omitted : Integer;             // Funde ueber MAX_FINDINGS_PER_MENU, nicht gefragt
    function IsEmpty: Boolean;
    function ActionCount: Integer;
  end;

  TFindingMenuOption  = (moLeadingSeparator, moHeaders, moAvailableFixesOnly);
  TFindingMenuOptions = set of TFindingMenuOption;

const
  // Soviel von der Meldung steht in der Kopfzeile.
  MENU_HEADER_MESSAGE_CHARS = 60;

// Reine Form: Funde und ihre Aktionslisten (gleich lang, Index = Fund)
// -> Modell. Ein Fund ohne Aktionen erscheint nicht.
function BuildFindingMenuModelFrom(const AFindings: TArray<TLeakFinding>;
  const AActions: TArray<TArray<TFindingAction>>;
  AOptions: TFindingMenuOptions): TFindingMenuModel;

// Erfragt die Aktionen je Fund bei der Registry (TFindingActions.ActionsFor)
// und baut daraus das Modell; Anbieterfehler kommen nach Errors. Nur die
// ersten MAX_FINDINGS_PER_MENU Funde werden gefragt, der Rest zaehlt nach
// Omitted.
function BuildFindingMenuModel(const AFindings: TArray<TLeakFinding>;
  AOptions: TFindingMenuOptions): TFindingMenuModel;

// 'Caption  (Hint)' bzw. nur Caption.
function FindingActionCaption(const AAction: TFindingAction): string;
// 'SCAnnn  Meldung' (Meldung auf MENU_HEADER_MESSAGE_CHARS gekuerzt).
function FindingHeaderCaption(AFinding: TLeakFinding): string;

implementation

uses
  uCrashDiag;

{ TFindingMenuModel }

function TFindingMenuModel.IsEmpty: Boolean;
begin
  Result := Length(Actions) = 0;
end;

function TFindingMenuModel.ActionCount: Integer;
begin
  Result := Length(Actions);
end;

{ ---- Beschriftungen ---- }

function FindingActionCaption(const AAction: TFindingAction): string;
begin
  if AAction.Hint <> '' then
    Result := Format('%s  (%s)', [AAction.Caption, AAction.Hint])
  else
    Result := AAction.Caption;
end;

function FindingHeaderCaption(AFinding: TLeakFinding): string;
begin
  if not Assigned(AFinding) then Exit('');
  Result := Format('%s  %s', [AFinding.ResolvedRuleId,
    TrimRight(Copy(AFinding.MissingVar, 1, MENU_HEADER_MESSAGE_CHARS))]);
end;

{ ---- Modell ---- }

function IsAvailable(const AAction: TFindingAction): Boolean;
begin
  Result := AAction.Enabled and Assigned(AAction.Execute);
end;

function IsAvailableFix(const AAction: TFindingAction): Boolean;
begin
  Result := (AAction.Kind = fakFix) and IsAvailable(AAction);
end;

// Die Aktionen eines Funds, wie sie ins Modell gehen.
function FilterActions(const AActions: TArray<TFindingAction>;
  AOptions: TFindingMenuOptions): TArray<TFindingAction>;
var
  k, n : Integer;
begin
  if not (moAvailableFixesOnly in AOptions) then
    Exit(AActions);
  SetLength(Result, Length(AActions));
  n := 0;
  for k := 0 to High(AActions) do
    if IsAvailableFix(AActions[k]) then
    begin
      Result[n] := AActions[k];
      Inc(n);
    end;
  // Unterdruecken nur neben einer echten Hilfe (E1) - sonst erschiene die
  // Birne auf jeder Fundzeile.
  if n > 0 then
    for k := 0 to High(AActions) do
      if (AActions[k].Kind = fakSuppress) and IsAvailable(AActions[k]) then
      begin
        Result[n] := AActions[k];
        Inc(n);
      end;
  SetLength(Result, n);
end;

procedure AddEntry(var AModel: TFindingMenuModel; AKind: TFindingMenuEntryKind;
  const ACaption, AHint: string; AEnabled: Boolean; AActionIndex: Integer);
var
  E : TFindingMenuEntry;
begin
  E.Kind        := AKind;
  E.Caption     := ACaption;
  E.Hint        := AHint;
  E.Enabled     := AEnabled;
  E.ActionIndex := AActionIndex;
  SetLength(AModel.Entries, Length(AModel.Entries) + 1);
  AModel.Entries[High(AModel.Entries)] := E;
end;

// Die Aktionen EINES Funds ins Modell; Unterdruecken ist keine Hilfe und
// wird vom Rest des Funds mit einem Trenner abgesetzt.
procedure AddActionsOf(var AModel: TFindingMenuModel;
  const AActs: TArray<TFindingAction>);
var
  k : Integer;
begin
  for k := 0 to High(AActs) do
  begin
    if (AActs[k].Kind = fakSuppress) and (k > 0)
       and (AActs[k - 1].Kind <> fakSuppress) then
      AddEntry(AModel, mkSeparator, '-', '', False, -1);
    SetLength(AModel.Actions, Length(AModel.Actions) + 1);
    AModel.Actions[High(AModel.Actions)] := AActs[k];
    AddEntry(AModel, mkAction, FindingActionCaption(AActs[k]), AActs[k].Hint,
      IsAvailable(AActs[k]), High(AModel.Actions));
  end;
end;

function BuildFindingMenuModelFrom(const AFindings: TArray<TLeakFinding>;
  const AActions: TArray<TArray<TFindingAction>>;
  AOptions: TFindingMenuOptions): TFindingMenuModel;
var
  i       : Integer;
  Count   : Integer;
  Acts    : TArray<TFindingAction>;
  SepDone : Boolean;
begin
  Result  := Default(TFindingMenuModel);
  Count   := Length(AFindings);
  if Length(AActions) < Count then Count := Length(AActions);
  SepDone := False;
  for i := 0 to Count - 1 do
  begin
    Acts := FilterActions(AActions[i], AOptions);
    if Length(Acts) = 0 then Continue;
    if (moLeadingSeparator in AOptions) and not SepDone then
    begin
      AddEntry(Result, mkSeparator, '-', '', False, -1);
      SepDone := True;
    end;
    if moHeaders in AOptions then
      AddEntry(Result, mkHeader, FindingHeaderCaption(AFindings[i]), '',
        False, -1);
    AddActionsOf(Result, Acts);
  end;
end;

function BuildFindingMenuModel(const AFindings: TArray<TLeakFinding>;
  AOptions: TFindingMenuOptions): TFindingMenuModel;
var
  i      : Integer;
  Asked  : TArray<TLeakFinding>;
  Lists  : TArray<TArray<TFindingAction>>;
  Errors : TArray<string>;
  NErr   : Integer;
begin
  // Obergrenze VOR dem ersten Anbieter-Aufruf: ein Anbieter haelt die
  // Objekte nur einer begrenzten Zahl von Abfragen (Vertrag uFindingActions).
  Asked := Copy(AFindings, 0, MAX_FINDINGS_PER_MENU);
  SetLength(Lists, Length(Asked));
  SetLength(Errors, Length(Asked));   // hoechstens ein Fehler je Fund
  NErr := 0;
  for i := 0 to High(Asked) do
  begin
    try
      Lists[i] := TFindingActions.ActionsFor(Asked[i]);
    except
      on EStackExhausted do raise;
      // noinspection ExceptionTooGeneral
      // Ein werfender Anbieter kostet die Aktionen dieses Funds, nie das
      // Menue - deshalb jede Ausnahme ausser dem Stack-Ueberlauf.
      on E: Exception do
      begin
        Lists[i] := nil;
        Errors[NErr] := E.Message;
        Inc(NErr);
      end;
    end;
  end;
  SetLength(Errors, NErr);
  Result := BuildFindingMenuModelFrom(Asked, Lists, AOptions);
  Result.Errors  := Errors;
  Result.Omitted := Length(AFindings) - Length(Asked);
end;

end.
