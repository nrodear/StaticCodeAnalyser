unit uFindingActionMenu;

// Das Modell eines Aktionsmenues zu Funden - der EINE Erzeuger fuer alle
// Einstiege: Editor-Kontextmenue, Dock-Grid und Gluehbirne (Konzept
// Editor-Gluehbirne 2026-10-06, Stufe C); die Tasten Ctrl+Alt+F und
// Ctrl+Alt+S waehlen ihre Aktion ueber FirstRunnable aus demselben Modell
// (Review 2026-10-14). Ohne VCL und ohne ToolsAPI, damit TestProject es
// prueft; das Zeichnen als TMenuItem macht uIDEFindingActionMenu im Plugin.
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
// Eintrag eines Funds ein Trenner. Ein Umbau an der Stelle (fakRefactor)
// steht je Modell nur einmal: ein gleichlautender eines spaeteren Funds
// faellt weg; bleibt einem Fund dadurch nichts, faellt er samt Kopf weg.
// Eine Aktion ohne gesetzte Art (fakUnset, die Vorgabe von
// Default(TFindingAction)) erscheint in Kontextmenue und Dock-Grid wie
// angegeben, nie in der Gluehbirne und nie ueber eine Taste.
// BuildFindingMenuModel fragt
// hoechstens MAX_FINDINGS_PER_MENU Funde ab (Vertrag in uFindingActions);
// wie viele es nicht fragte, steht in Omitted. Wirft ein
// Anbieter beim Erfragen, fallen die Aktionen DIESES Funds weg (alle
// Anbieter - TFindingActions.ActionsFor wirft als Ganzes), nie das
// Menue; die Meldung landet in Errors, der Host protokolliert sie.
// Ausgenommen: ein erschoepfter Stapel und EAbort laufen zum Host durch.
//
// Code-Aktionen ohne Fund (Charge B, E14/E16): BuildEditorMenuModel haengt
// hinter die Fund-Aktionen der Caret-Zeile die Aktionen der Kontext-
// Anbieter (Kind = fakContext), abgesetzt durch Trenner und optionale
// Kopfzeile; eine Caption, die schon im Modell steht, kommt nicht zweimal.
// Die Gluehbirnen-Form (moAvailableFixesOnly) bekommt nie Kontextaktionen.

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

  // Was eine Taste (Ctrl+Alt+F, Ctrl+Alt+S) mit dem Modell anfaengt -
  // Ergebnis von TFindingMenuModel.FirstRunnable (Tasten-Policy, Konzept
  // Editorhilfen Entscheid E2): die Taste fuehrt die ERSTE Aktion ihrer
  // Art aus, die verfuegbar ist (Enabled, Execute zugewiesen) und nicht
  // als verhaltensaendernd gekennzeichnet ist. Gibt es keine solche,
  // sagt der Verdikt, warum - mit dem Index der ersten ausgelassenen
  // Aktion dieser Art, damit der Host ihren Grund nennen kann:
  //   kvRun       Index = die auszufuehrende Aktion
  //   kvNone      keine Aktion dieser Art im Modell (Index -1) - der Host
  //               darf auf einen eigenen Weg ausweichen (Ctrl+Alt+S:
  //               Marker ueber uSuppression, Review 2026-10-14 MAJOR 1)
  //   kvDisabled  Index = erste gesperrte Aktion dieser Art; ihr Hint
  //               traegt den Grund
  //   kvChangesBehavior
  //               Index = erste verfuegbare, aber verhaltensaendernde -
  //               die gibt es nur gesehen (Menue, Gluehbirne)
  TFindingKeyVerdict = (kvRun, kvNone, kvDisabled, kvChangesBehavior);

  TFindingKeyChoice = record
    Verdict : TFindingKeyVerdict;
    Index   : Integer;   // in TFindingMenuModel.Actions, -1 bei kvNone
  end;

  TFindingMenuModel = record
    Entries : TArray<TFindingMenuEntry>;
    Actions : TArray<TFindingAction>;
    Errors  : TArray<string>;      // Meldungen werfender Anbieter
    Omitted : Integer;             // Funde ueber MAX_FINDINGS_PER_MENU, nicht gefragt
    // Code-Aktionen ohne Fund (Charge B, AppendContextActions): sie stehen
    // immer am ENDE - die letzten ContextEntryCount Eintraege (samt ihrem
    // Trenner und ihrer Kopfzeile) und die letzten ContextActionCount
    // Aktionen. 0 = keine. Ein Host, der sie als Untermenue zeichnet,
    // schneidet sie damit ab; Default(TFindingMenuModel) = keine.
    ContextEntryCount  : Integer;
    ContextActionCount : Integer;
    // True, wenn das Modell keine einzige Aktion traegt - dann gibt es
    // auch keine Eintraege (Trenner und Kopfzeilen entstehen nur vor
    // Aktionen). Die Gluehbirne erscheint genau dann nicht; Errors und
    // Omitted zaehlen hier nicht mit.
    function IsEmpty: Boolean;
    // Zahl der Aktionen in der flachen Liste Actions (ueber alle Funde,
    // ohne Trenner und Kopfzeilen) - die Tags der Menuepunkte reichen
    // von ATagBase bis ATagBase + ActionCount - 1 (uIDEFindingActionMenu).
    function ActionCount: Integer;
    // Tasten-Policy, siehe TFindingKeyVerdict. Reihenfolge = Reihenfolge
    // in Actions, also Anmeldereihenfolge der Anbieter je Fund. Der erste
    // ausgelassene Grund gewinnt (eine gesperrte VOR einer
    // verhaltensaendernden nennt die gesperrte).
    function FirstRunnable(AKind: TFindingActionKind): TFindingKeyChoice;
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
// und baut daraus das Modell; Anbieterfehler kommen nach Errors (ausser
// EStackExhausted und EAbort - die wirft die Funktion weiter). Nur die
// ersten MAX_FINDINGS_PER_MENU Funde werden gefragt, der Rest zaehlt nach
// Omitted.
function BuildFindingMenuModel(const AFindings: TArray<TLeakFinding>;
  AOptions: TFindingMenuOptions): TFindingMenuModel;

// Reine Form der Code-Aktionen ohne Fund (Charge B, E14/E16): haengt
// AActions hinten an AModel an - jede mit Kind = fakContext. Eine Aktion,
// deren Caption schon im Modell steht (eine Fund-Aktion der Zeile oder
// eine fruehere Kontextaktion), faellt weg: gleiche Captions stehen nur
// einmal, und zwar am Fund. Bleibt etwas, steht davor ein Trenner, wenn
// das Modell schon Eintraege hat oder moLeadingSeparator gesetzt ist, und
// mit moHeaders eine deaktivierte Kopfzeile AHeader (leer: keine). Mit
// moAvailableFixesOnly (die Form der Gluehbirne) haengt sie NICHTS an -
// Kontextaktionen stehen nie in der Gluehbirne. Zaehlt
// ContextEntryCount/ContextActionCount hoch.
procedure AppendContextActions(var AModel: TFindingMenuModel;
  const AActions: TArray<TFindingAction>; AOptions: TFindingMenuOptions;
  const AHeader: string);

// Das Modell des Editor-Kontextmenues: die Funde AContext.Findings wie
// BuildFindingMenuModel, dahinter die Code-Aktionen der Kontext-Anbieter
// (TFindingActions.ContextActionsFor, einmal je Aufruf) ueber
// AppendContextActions. Wirft ein Kontext-Anbieter, fallen die Kontext-
// aktionen weg und die Meldung kommt nach Errors (ausser EStackExhausted
// und EAbort) - die Fund-Aktionen bleiben.
function BuildEditorMenuModel(const AContext: TEditorContext;
  AOptions: TFindingMenuOptions; const AContextHeader: string): TFindingMenuModel;

// 'Caption  (Hint)' bzw. nur Caption.
function FindingActionCaption(const AAction: TFindingAction): string;
// 'SCAnnn  Meldung' (Meldung auf MENU_HEADER_MESSAGE_CHARS gekuerzt).
function FindingHeaderCaption(AFinding: TLeakFinding): string;

// Identitaet eines Funds fuer Menue und Gluehbirne: Art, Ankerzeile und
// Meldung - NICHT die Datei (die Aufrufer arbeiten je Datei) und nicht
// das Objekt (derselbe Fund kann aus zwei Scans, Dock und Silent-Lauf,
// als zwei Objekte vorliegen und soll einmal erscheinen). Dieselbe
// Funktion liefert den Fingerabdruck der Zeile, mit dem die Gluehbirne
// eine neue Anbieter-Antwort einholt (Review 2026-10-14: vorher zwei
// Kopien in uIDEAnalyserForm und uIDEFindingBulb). nil -> ''.
function FindingIdentityKey(AFinding: TLeakFinding): string;

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

// Darf eine Taste die Aktion ungesehen ausfuehren? Verfuegbar und nicht
// als verhaltensaendernd gekennzeichnet (Entscheid E2).
function RunsBlind(const A: TFindingAction): Boolean;
begin
  Result := A.Enabled and Assigned(A.Execute) and not A.ChangesBehavior;
end;

function TFindingMenuModel.FirstRunnable(
  AKind: TFindingActionKind): TFindingKeyChoice;
var
  i : Integer;
begin
  Result.Verdict := kvNone;
  Result.Index   := -1;
  for i := 0 to High(Actions) do
  begin
    if Actions[i].Kind <> AKind then Continue;
    if RunsBlind(Actions[i]) then
    begin
      Result.Verdict := kvRun;
      Result.Index   := i;
      Exit;
    end;
    // Der erste ausgelassene Grund bleibt stehen; eine spaetere
    // ausfuehrbare Aktion gewinnt trotzdem (Exit oben).
    if Result.Verdict <> kvNone then Continue;
    Result.Index := i;
    if Actions[i].Enabled and Assigned(Actions[i].Execute) then
      Result.Verdict := kvChangesBehavior
    else
      Result.Verdict := kvDisabled;
  end;
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

function FindingIdentityKey(AFinding: TLeakFinding): string;
begin
  if not Assigned(AFinding) then Exit('');
  Result := IntToStr(Ord(AFinding.Kind)) + ':' + IntToStr(AFinding.LineInt)
    + ':' + AFinding.MissingVar;
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
// wird vom Rest des Funds mit einem Trenner abgesetzt. Actions waechst
// einmal je Fund, nicht je Aktion.
procedure AddActionsOf(var AModel: TFindingMenuModel;
  const AActs: TArray<TFindingAction>);
var
  k, Base : Integer;
begin
  Base := Length(AModel.Actions);
  SetLength(AModel.Actions, Base + Length(AActs));
  for k := 0 to High(AActs) do
  begin
    if (AActs[k].Kind = fakSuppress) and (k > 0)
       and (AActs[k - 1].Kind <> fakSuppress) then
      AddEntry(AModel, mkSeparator, '-', '', False, -1);
    AModel.Actions[Base + k] := AActs[k];
    AddEntry(AModel, mkAction, FindingActionCaption(AActs[k]), AActs[k].Hint,
      IsAvailable(AActs[k]), Base + k);
  end;
end;

// Umbauten (fakRefactor), deren Caption schon in ASeen[0..ASeenCount-1]
// steht, fallen weg; die uebrigen kommen nach ASeen. ASeen waechst
// hoechstens einmal je Aufruf (um Length(AActions)) statt je Umbau - das
// SetLength in der Schleife war quadratisch (Review 2026-10-14, Punkt 7);
// ASeenCount zaehlt die belegten Eintraege.
function DropSeenRefactors(const AActions: TArray<TFindingAction>;
  var ASeen: TArray<string>; var ASeenCount: Integer): TArray<TFindingAction>;
var
  k, n, s : Integer;
  Seen    : Boolean;
begin
  SetLength(Result, Length(AActions));
  if ASeenCount + Length(AActions) > Length(ASeen) then
    SetLength(ASeen, ASeenCount + Length(AActions));
  n := 0;
  for k := 0 to High(AActions) do
  begin
    if AActions[k].Kind = fakRefactor then
    begin
      Seen := False;
      for s := 0 to ASeenCount - 1 do
        if ASeen[s] = AActions[k].Caption then
        begin
          Seen := True;
          Break;
        end;
      if Seen then Continue;
      ASeen[ASeenCount] := AActions[k].Caption;
      Inc(ASeenCount);
    end;
    Result[n] := AActions[k];
    Inc(n);
  end;
  SetLength(Result, n);
end;

function BuildFindingMenuModelFrom(const AFindings: TArray<TLeakFinding>;
  const AActions: TArray<TArray<TFindingAction>>;
  AOptions: TFindingMenuOptions): TFindingMenuModel;
var
  i         : Integer;
  Count     : Integer;
  Acts      : TArray<TFindingAction>;
  SepDone   : Boolean;
  Seen      : TArray<string>;   // Captions der schon gezeigten Umbauten
  SeenCount : Integer;
begin
  Result    := Default(TFindingMenuModel);
  Count     := Length(AFindings);
  if Length(AActions) < Count then Count := Length(AActions);
  SepDone   := False;
  Seen      := nil;
  SeenCount := 0;
  for i := 0 to Count - 1 do
  begin
    Acts := DropSeenRefactors(FilterActions(AActions[i], AOptions), Seen,
      SeenCount);
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
      on EAbort do raise;   // ein Abbruch erreicht den Host, nicht Errors
      // noinspection ExceptionTooGeneral
      // Ein werfender Anbieter kostet die Aktionen dieses Funds, nie das
      // Menue - deshalb jede Ausnahme ausser Stack-Ueberlauf und Abbruch.
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

{ ---- Code-Aktionen ohne Fund (Charge B) ---- }

function CaptionInModel(const AModel: TFindingMenuModel;
  const ACaption: string): Boolean;
var
  i : Integer;
begin
  Result := False;
  for i := 0 to High(AModel.Actions) do
    if AModel.Actions[i].Caption = ACaption then
      Exit(True);
end;

procedure AppendContextActions(var AModel: TFindingMenuModel;
  const AActions: TArray<TFindingAction>; AOptions: TFindingMenuOptions;
  const AHeader: string);
var
  Keep       : TArray<TFindingAction>;
  k, n, s    : Integer;
  Dup        : Boolean;
  FirstEntry : Integer;
begin
  if moAvailableFixesOnly in AOptions then Exit;   // nie in der Gluehbirne
  SetLength(Keep, Length(AActions));
  n := 0;
  for k := 0 to High(AActions) do
  begin
    // Gegen das Modell (Fund-Aktionen und schon angehaengte Kontext-
    // aktionen) und gegen die schon behaltenen dieser Liste.
    Dup := CaptionInModel(AModel, AActions[k].Caption);
    s := 0;
    while not Dup and (s < n) do
    begin
      Dup := Keep[s].Caption = AActions[k].Caption;
      Inc(s);
    end;
    if Dup then Continue;
    Keep[n] := AActions[k];
    Keep[n].Kind := fakContext;
    Inc(n);
  end;
  if n = 0 then Exit;
  SetLength(Keep, n);
  FirstEntry := Length(AModel.Entries);
  if (FirstEntry > 0) or (moLeadingSeparator in AOptions) then
    AddEntry(AModel, mkSeparator, '-', '', False, -1);
  if (moHeaders in AOptions) and (AHeader <> '') then
    AddEntry(AModel, mkHeader, AHeader, '', False, -1);
  AddActionsOf(AModel, Keep);
  Inc(AModel.ContextEntryCount, Length(AModel.Entries) - FirstEntry);
  Inc(AModel.ContextActionCount, n);
end;

function BuildEditorMenuModel(const AContext: TEditorContext;
  AOptions: TFindingMenuOptions; const AContextHeader: string): TFindingMenuModel;
var
  Ctx : TArray<TFindingAction>;
begin
  Result := BuildFindingMenuModel(AContext.Findings, AOptions);
  if moAvailableFixesOnly in AOptions then Exit;   // Anbieter gar nicht fragen
  try
    Ctx := TFindingActions.ContextActionsFor(AContext);
  except
    on EStackExhausted do raise;
    on EAbort do raise;   // ein Abbruch erreicht den Host, nicht Errors
    // noinspection ExceptionTooGeneral
    // Ein werfender Kontext-Anbieter kostet die Kontextaktionen, nie das
    // Menue und nie die Fund-Aktionen - wie in BuildFindingMenuModel.
    on E: Exception do
    begin
      Ctx := nil;
      SetLength(Result.Errors, Length(Result.Errors) + 1);
      Result.Errors[High(Result.Errors)] := E.Message;
    end;
  end;
  AppendContextActions(Result, Ctx, AOptions, AContextHeader);
end;

end.
