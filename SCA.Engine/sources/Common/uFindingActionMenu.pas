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
// die flache Liste Actions, ueber die der Host ausfuehrt. Wirft ein
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
    function IsEmpty: Boolean;
    function ActionCount: Integer;
  end;

  TFindingMenuOption  = (moLeadingSeparator, moHeaders);
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
// und baut daraus das Modell; Anbieterfehler kommen nach Errors.
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

function BuildFindingMenuModelFrom(const AFindings: TArray<TLeakFinding>;
  const AActions: TArray<TArray<TFindingAction>>;
  AOptions: TFindingMenuOptions): TFindingMenuModel;
var
  i, k    : Integer;
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
    Acts := AActions[i];
    if Length(Acts) = 0 then Continue;
    if (moLeadingSeparator in AOptions) and not SepDone then
    begin
      AddEntry(Result, mkSeparator, '-', '', False, -1);
      SepDone := True;
    end;
    if moHeaders in AOptions then
      AddEntry(Result, mkHeader, FindingHeaderCaption(AFindings[i]), '',
        False, -1);
    for k := 0 to High(Acts) do
    begin
      SetLength(Result.Actions, Length(Result.Actions) + 1);
      Result.Actions[High(Result.Actions)] := Acts[k];
      AddEntry(Result, mkAction, FindingActionCaption(Acts[k]), Acts[k].Hint,
        Acts[k].Enabled and Assigned(Acts[k].Execute),
        High(Result.Actions));
    end;
  end;
end;

function BuildFindingMenuModel(const AFindings: TArray<TLeakFinding>;
  AOptions: TFindingMenuOptions): TFindingMenuModel;
var
  i      : Integer;
  Lists  : TArray<TArray<TFindingAction>>;
  Errors : TArray<string>;
  NErr   : Integer;
begin
  SetLength(Lists, Length(AFindings));
  SetLength(Errors, Length(AFindings));   // hoechstens ein Fehler je Fund
  NErr := 0;
  for i := 0 to High(AFindings) do
  begin
    try
      Lists[i] := TFindingActions.ActionsFor(AFindings[i]);
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
  Result := BuildFindingMenuModelFrom(AFindings, Lists, AOptions);
  Result.Errors := Errors;
end;

end.
