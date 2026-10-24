unit uFindingActionMenu;

// Das Modell eines Aktionsmenues zu Funden - der EINE Erzeuger fuer alle
// Einstiege: Editor-Kontextmenue, Dock-Grid und Gluehbirne (Konzept
// Editor-Gluehbirne 2026-10-06, Stufe C); die Tasten Ctrl+Alt+F und
// Ctrl+Alt+S waehlen ihre Aktion ueber FirstRunnable aus demselben Modell
// (Review 2026-10-14). Ohne VCL und ohne ToolsAPI, damit TestProject es
// prueft; das Zeichnen als TMenuItem macht uIDEFindingActionMenu im Plugin.
//
// Form (Aktionsmenue nach Vorschlag 2, Konzept 2026-10-24, mit Nicos
// Aenderungen "2b" vom selben Tag - so kurz wie Vorschlag 2): optional ein
// Trenner vor dem ersten Fund mit Aktionen, je Fund optional eine
// deaktivierte Kopfzeile 'SCAnnn  Regelname' (FindingHeaderCaption),
// darunter die Aktionen als Caption + #9 + Kennzeichnung (FindingAction-
// Caption: '=' fuer bedeutungsgleich, sonst der kurze Kopf des Hints - in
// der Spalte, in der Windows sonst die Taste zeigt). Der volle Hint und
// die volle Meldung des Funds stehen in Entry.Hint (FindingActionHint),
// verfuegbare Hilfen und Code-Aktionen tragen das Bild miBulb,
// 'Unterdruecken' miSuppress, die Kopfzeilen IM Untermenue miRule
// (Entry.Icon; die Kopfzeilen oben bleiben ohne Bild). Enabled
// ist Enabled des Anbieters UND Execute zugewiesen; ActionIndex zeigt in
// die flache Liste Actions, ueber die der Host ausfuehrt. Mit
// moAvailableFixesOnly bleiben nur Aktionen, die der Benutzer JETZT
// ausfuehren kann und die etwas aendern (Kind = fakFix, Enabled, Execute
// zugewiesen) - die Form der Gluehbirne: kein "Stelle zeigen", keine
// ausgegrauten Eintraege, keine Diagnosezeilen der Anbieter; ein Fund ohne
// solche Aktion faellt samt Kopfzeile weg. Unterdrueck-Aktionen
// (fakSuppress) bleiben dort NUR, wenn der Fund eine solche Hilfe hat
// (Editorhilfen E1).
//
// Unterdruecken (Aktionsmenue nach Vorschlag 2, Konzept 2026-10-24, mit
// Nicos Aenderung "2b" vom selben Tag): die Unterdrueck-Aktionen ALLER
// Funde stehen in EINEM Untermenue 'Unterdruecken' (mkSubmenu) hinter den
// Fund-Gruppen - je Fund (mit moHeaders) die Kopfzeile 'SCAnnn  Art'
// (FindingSuppressHeaderCaption), darunter seine Unterdrueck-Aktionen nur
// mit ihrer Caption (der Marker steht im Hint), ein Trenner zwischen den
// Funden. Oben steht je Fund nur die Gruppe aus Kopfzeile und uebrigen
// Aktionen, ein Trenner nach jeder Gruppe (vor der naechsten bzw. vor
// 'Unterdruecken', vor dem Abschnitt der Code-Aktionen ohne Fund ohnehin
// einer, AppendContextActions). Ein Fund ohne Unterdrueck-Aktion
// fehlt im Untermenue, ein Fund mit NUR solchen oben; ohne jede kein
// Untermenue. Bis dahin standen sie je Fund flach hinter einem Trenner.
//
// Ein Umbau an der Stelle (fakRefactor) steht je Modell nur einmal: ein
// gleichlautender eines spaeteren Funds
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
  // mkSubmenu (Aktionsmenue nach Vorschlag 2, 2026-10-24): der Kopf eines
  // Untermenues - je Modell hoechstens einer, 'Unterdruecken'
  // (_('Suppress')) ueber den Unterdrueck-Aktionen aller Funde. Er fuehrt
  // nichts aus (ActionIndex -1) und ist Enabled, wenn mindestens eine
  // seiner Aktionen es ist; seine Kinder (Kopfzeilen, Aktionen, Trenner)
  // folgen in Entries UNMITTELBAR hinter ihm, mit Parent = sein Index.
  TFindingMenuEntryKind = (mkSeparator, mkHeader, mkAction, mkSubmenu);

  // Das Bild vor einem Eintrag (Nico 2026-10-24, Mock 2b) - welches Bild
  // das ist und wie es aussieht, entscheidet der Host:
  //   miNone      keines
  //   miBulb      Gluehbirne: verfuegbare Hilfe (fakFix) oder Code-Aktion
  //               ohne Fund (fakContext) der obersten Ebene
  //   miSuppress  durchgestrichenes Auge: der Kopf 'Unterdruecken'
  //   miRule      SCA-Eule: die Kopfzeile eines Funds im Untermenue
  TFindingMenuIcon = (miNone, miBulb, miSuppress, miRule);

  TFindingMenuEntry = record
    Kind        : TFindingMenuEntryKind;
    Caption     : string;
    Hint        : string;
    Enabled     : Boolean;
    ActionIndex : Integer;   // Index in TFindingMenuModel.Actions, -1 sonst
    // Index des mkSubmenu-Eintrags in Entries, unter dem dieser Eintrag
    // steht; -1 = oberste Ebene (Vorschlag 2). Hinten angehaengt - die
    // Felder davor bleiben, wie die Hosts sie lesen.
    Parent      : Integer;
    // Bild vor dem Eintrag (Nico 2026-10-24, TFindingMenuIcon).
    Icon        : TFindingMenuIcon;
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
  // Soviel vom Regelnamen bzw. (ohne ihn) von der Meldung steht hoechstens
  // in der Kopfzeile (FindingHeaderCaption, ShortMenuText).
  MENU_HEADER_TITLE_CHARS = 40;
  // Soviel vom Kopf eines Hints steht hoechstens in der Kennzeichnungs-
  // Spalte einer Aktion (FindingHintHead).
  MENU_MARK_CHARS = 32;
  // Kennzeichnung einer verfuegbaren, bedeutungsgleichen Code-Aenderung.
  MENU_MARK_SAME = '=';
  // Trenner zwischen Menuetext und Kennzeichnung: TMenuItem zeigt den Teil
  // hinter #9 nativ rechtsbuendig in der Tastenspalte.
  MENU_MARK_TAB = #9;
  // Der Kopf eines Hints endet vor dem ersten ' - ' (FindingHintHead).
  HINT_HEAD_SEPARATOR = ' - ';
  // Zwischen Hint der Aktion und Meldung des Funds (FindingActionHint) -
  // kein '|': VCL zeigt von einem Menue-Hint nur den Teil hinter '|'
  // (GetLongHint).
  MENU_HINT_JOIN = ' '#$00B7' ';

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
// einmal, und zwar am Fund. Verglichen OHNE Gross-/Kleinschreibung
// (SameText): ein Name im Menuetext kommt auf dem Fundweg aus der
// Detektormeldung, auf dem Kontextweg aus dem Quelltext - Pascal-
// Bezeichner unterscheiden sie nicht ('Foo' / 'foo', SCA009; Review
// Charge B, Befund 5). Bleibt etwas, steht davor ein Trenner, wenn
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

// AText ohne Leerraum aussen; laenger als AMaxChars Zeichen am letzten
// Leerzeichen in der zweiten Haelfte gekuerzt (sonst hart), ohne ',', ';'
// und ':' am Ende, mit '...' (U+2026) abgeschlossen.
function ShortMenuText(const AText: string; AMaxChars: Integer): string;
// Der Kopf eines Hints fuer die Kennzeichnungs-Spalte (Vorschlag 2, Regel
// 1): der Text vor dem ersten ' - ' (ohne ' - ' der ganze Hint), auf
// MENU_MARK_CHARS gekuerzt (ShortMenuText). '' bleibt ''.
// WARUM am uebersetzten Text: der Hint kommt als EIN Satz und EINE msgid
// vom Anbieter (reDelphix FIX_HINTS, R_*_HINT, Gruende); ein eigenes Feld
// fuer den Kopf haette jeden Anbieter und rund 470 msgids geteilt. Der
// Kopf vor ' - ' ist dort die Kennzeichnung ('same meaning - ...', 'Free
// now also runs on an exception and on Exit - ...'), und die
// Uebersetzungen halten diese Form: alle 868 msgids mit ' - ' in i18n/
// tragen es auch in de.po und fr.po, mit dem uebersetzten Kopf davor
// ('gleiche Bedeutung', 'meme sens'; zwei Optionstexte ausserhalb der
// Menues ausgenommen, Stand 2026-10-24). Fehlt es einer Uebersetzung,
// steht der Anfang des ganzen Hints da; der volle Hint steht ohnehin im
// Hint des Menuepunkts.
function FindingHintHead(const AHint: string): string;
// Die Kennzeichnung einer Aktion in der Tastenspalte: MENU_MARK_SAME fuer
// eine verfuegbare Code-Aenderung (fakFix, fakRefactor, fakContext), die
// das Verhalten nicht aendert; sonst - verhaltensaendernd, gesperrt (dann
// ist der Hint der Grund) oder eine andere Art - der Kopf des Hints
// (FindingHintHead), '' ohne Hint.
function FindingActionMark(const AAction: TFindingAction): string;
// Der Menuetext einer Aktion der obersten Ebene: Caption + #9 +
// Kennzeichnung bzw. nur Caption (keine Kennzeichnung). Gleich gebaut fuer
// Fund- und Kontextaktion; dedupliziert wird ueber TFindingAction.Caption,
// den Teil VOR #9 (AppendContextActions) - eine Kontextaktion mit
// derselben Caption faellt weg, auch wenn ihre Kennzeichnung abwiche.
function FindingActionCaption(const AAction: TFindingAction): string;
// 'Caption  (Hint)' mit dem vollen Hint bzw. nur Caption - bis Vorschlag 2
// der Menuetext jeder Aktion, heute fuer Statuszeilen (Ctrl+Alt+S nennt so
// den Marker, der im Menue nur noch im Hint steht).
function FindingActionFullCaption(const AAction: TFindingAction): string;
// Der Hint eines Menuepunkts: der Hint der Aktion und - mit Fund - dessen
// 'SCAnnn: Meldung' (die Kopfzeile nennt nur den Regelnamen), verbunden
// mit MENU_HINT_JOIN; ein leerer Teil faellt weg.
function FindingActionHint(const AAction: TFindingAction;
  AFinding: TLeakFinding): string;
// Kopfzeile eines Funds: 'SCAnnn  Regelname' - der Name aus dem Regel-
// katalog in der Sprache der Oberflaeche (TRuleCatalog.GetRule mit
// CurrentLanguage, Overlay sca-rules.<lang>.json); fuer eine eigene Regel
// (RuleID gesetzt) oder ohne Namen die Meldung. Beides auf
// MENU_HEADER_TITLE_CHARS gekuerzt (ShortMenuText). nil -> ''.
function FindingHeaderCaption(AFinding: TLeakFinding): string;
// Kopfzeile eines Funds im Untermenue 'Unterdruecken': 'SCAnnn  Art' -
// die Art, wie sie im Marker steht (uSCAConsts.KindName). nil -> ''.
function FindingSuppressHeaderCaption(AFinding: TLeakFinding): string;

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
  uCrashDiag,     // EStackExhausted
  uLocalization,  // _ ('Suppress'), CurrentLanguage (Regelname der Kopfzeile)
  uRuleCatalog,   // Regelname der Kopfzeile
  uSCAConsts;     // KindName (Kopfzeile im Untermenue)

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

function ShortMenuText(const AText: string; AMaxChars: Integer): string;
const
  ELLIPSIS = #$2026;
var
  Cut : Integer;
begin
  Result := Trim(AText);
  if Length(Result) <= AMaxChars then Exit;
  // Result[Cut] ist das Zeichen hinter dem behaltenen Text.
  Cut := AMaxChars + 1;
  while (Cut > AMaxChars div 2) and (Result[Cut] <> ' ') do
    Dec(Cut);
  if Result[Cut] = ' ' then
    Result := TrimRight(Copy(Result, 1, Cut - 1))
  else
    Result := Copy(Result, 1, AMaxChars);
  while (Result <> '') and CharInSet(Result[Length(Result)], [',', ';', ':']) do
    Result := TrimRight(Copy(Result, 1, Length(Result) - 1));
  Result := Result + ELLIPSIS;
end;

function FindingHintHead(const AHint: string): string;
var
  p : Integer;
begin
  Result := AHint;
  p := Pos(HINT_HEAD_SEPARATOR, Result);
  if p > 0 then
    Result := Copy(Result, 1, p - 1);
  Result := ShortMenuText(Result, MENU_MARK_CHARS);
end;

function IsAvailable(const AAction: TFindingAction): Boolean;
begin
  Result := AAction.Enabled and Assigned(AAction.Execute);
end;

function FindingActionMark(const AAction: TFindingAction): string;
begin
  if IsAvailable(AAction) and not AAction.ChangesBehavior
     and (AAction.Kind in [fakFix, fakRefactor, fakContext]) then
    Result := MENU_MARK_SAME
  else
    Result := FindingHintHead(AAction.Hint);
end;

function FindingActionCaption(const AAction: TFindingAction): string;
var
  Mark : string;
begin
  Mark := FindingActionMark(AAction);
  if Mark <> '' then
    Result := AAction.Caption + MENU_MARK_TAB + Mark
  else
    Result := AAction.Caption;
end;

function FindingActionFullCaption(const AAction: TFindingAction): string;
begin
  if AAction.Hint <> '' then
    Result := Format('%s  (%s)', [AAction.Caption, AAction.Hint])
  else
    Result := AAction.Caption;
end;

function FindingActionHint(const AAction: TFindingAction;
  AFinding: TLeakFinding): string;
var
  Msg : string;
begin
  Result := AAction.Hint;
  if not Assigned(AFinding) then Exit;
  Msg := Trim(AFinding.MissingVar);
  if Msg = '' then Exit;
  Msg := AFinding.ResolvedRuleId + ': ' + Msg;
  if Result = '' then
    Result := Msg
  else
    Result := Result + MENU_HINT_JOIN + Msg;
end;

function FindingHeaderCaption(AFinding: TLeakFinding): string;
var
  Title : string;
begin
  if not Assigned(AFinding) then Exit('');
  Title := '';
  // Eine eigene Regel traegt ihre ID selbst; der Katalogname ihrer Art
  // ('Custom rule') sagte nichts.
  if AFinding.RuleID = '' then
    Title := TRuleCatalog.GetRule(AFinding.Kind, CurrentLanguage).Name;
  if Trim(Title) = '' then
    Title := AFinding.MissingVar;
  Result := Format('%s  %s', [AFinding.ResolvedRuleId,
    ShortMenuText(Title, MENU_HEADER_TITLE_CHARS)]);
end;

function FindingSuppressHeaderCaption(AFinding: TLeakFinding): string;
begin
  if not Assigned(AFinding) then Exit('');
  Result := Format('%s  %s', [AFinding.ResolvedRuleId,
    KindName(AFinding.Kind)]);
end;

function FindingIdentityKey(AFinding: TLeakFinding): string;
begin
  if not Assigned(AFinding) then Exit('');
  Result := IntToStr(Ord(AFinding.Kind)) + ':' + IntToStr(AFinding.LineInt)
    + ':' + AFinding.MissingVar;
end;

{ ---- Modell ---- }

// Das Bild einer Aktion der obersten Ebene (TFindingMenuIcon).
function ActionIcon(const AAction: TFindingAction): TFindingMenuIcon;
begin
  if IsAvailable(AAction) and (AAction.Kind in [fakFix, fakContext]) then
    Result := miBulb
  else
    Result := miNone;
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
  const ACaption, AHint: string; AEnabled: Boolean; AActionIndex: Integer;
  AParent: Integer = -1; AIcon: TFindingMenuIcon = miNone);
var
  E : TFindingMenuEntry;
begin
  E.Kind        := AKind;
  E.Caption     := ACaption;
  E.Hint        := AHint;
  E.Enabled     := AEnabled;
  E.ActionIndex := AActionIndex;
  E.Parent      := AParent;
  E.Icon        := AIcon;
  SetLength(AModel.Entries, Length(AModel.Entries) + 1);
  AModel.Entries[High(AModel.Entries)] := E;
end;

// Die Aktionen EINES Funds (AFinding; nil fuer Code-Aktionen ohne Fund)
// nach Actions - in der Reihenfolge des Anbieters (Base + k: die Tasten
// und die drei ActionItemClick-Wege lesen ActionIndex wie bisher; Actions
// waechst einmal je Fund, nicht je Aktion) - und alle ausser den
// Unterdrueck-Aktionen als Eintraege der obersten Ebene: Menuetext mit
// Kennzeichnung, Hint mit Meldung, Bild (ActionIcon). Liefert Base.
function AddActionsOf(var AModel: TFindingMenuModel;
  const AActs: TArray<TFindingAction>; AFinding: TLeakFinding): Integer;
var
  k : Integer;
begin
  Result := Length(AModel.Actions);
  SetLength(AModel.Actions, Result + Length(AActs));
  for k := 0 to High(AActs) do
  begin
    AModel.Actions[Result + k] := AActs[k];
    if AActs[k].Kind <> fakSuppress then
      AddEntry(AModel, mkAction, FindingActionCaption(AActs[k]),
        FindingActionHint(AActs[k], AFinding), IsAvailable(AActs[k]),
        Result + k, -1, ActionIcon(AActs[k]));
  end;
end;

function SuppressCount(const AActs: TArray<TFindingAction>): Integer;
var
  k : Integer;
begin
  Result := 0;
  for k := 0 to High(AActs) do
    if AActs[k].Kind = fakSuppress then
      Inc(Result);
end;

// Ein Fund mit Unterdrueck-Aktionen, gemerkt fuer das Untermenue.
type
  TSuppressGroup = record
    Finding : TLeakFinding;
    Base    : Integer;                  // Index seiner ersten Aktion in Actions
    Acts    : TArray<TFindingAction>;   // wie an AddActionsOf gegeben
  end;

// Vor einer Fund-Gruppe bzw. vor 'Unterdruecken': der fuehrende Trenner
// (moLeadingSeparator, einmal je Modell), sonst nach einer vorigen Gruppe
// einer (Vorschlag 2, Aenderung 2b).
procedure SeparateNext(var AModel: TFindingMenuModel;
  AOptions: TFindingMenuOptions; var ASepDone: Boolean; ATopGroups: Integer);
begin
  if (moLeadingSeparator in AOptions) and not ASepDone then
  begin
    AddEntry(AModel, mkSeparator, '-', '', False, -1);
    ASepDone := True;
  end
  else if ATopGroups > 0 then
    AddEntry(AModel, mkSeparator, '-', '', False, -1);
end;

// Das EINE Untermenue 'Unterdruecken' (Vorschlag 2, Aenderung 2b) als
// letzter Eintrag der Fund-Gruppen: je Fund (mit moHeaders) die Kopfzeile
// 'SCAnnn  Art', darunter seine Unterdrueck-Aktionen nur mit Caption (der
// Marker steht im Hint, Aenderung 2b), ein Trenner zwischen den Funden.
// Enabled, wenn eine Aktion es ist.
procedure AddSuppressMenu(var AModel: TFindingMenuModel;
  const AGroups: TArray<TSuppressGroup>; AOptions: TFindingMenuOptions);
var
  g, k, Sub : Integer;
begin
  AddEntry(AModel, mkSubmenu, _('Suppress'), '', False, -1, -1, miSuppress);
  Sub := High(AModel.Entries);
  for g := 0 to High(AGroups) do
  begin
    if g > 0 then
      AddEntry(AModel, mkSeparator, '-', '', False, -1, Sub);
    if moHeaders in AOptions then
      AddEntry(AModel, mkHeader,
        FindingSuppressHeaderCaption(AGroups[g].Finding), '', False, -1, Sub,
        miRule);
    for k := 0 to High(AGroups[g].Acts) do
    begin
      if AGroups[g].Acts[k].Kind <> fakSuppress then Continue;
      AddEntry(AModel, mkAction, AGroups[g].Acts[k].Caption,
        AGroups[g].Acts[k].Hint, IsAvailable(AGroups[g].Acts[k]),
        AGroups[g].Base + k, Sub);
      if IsAvailable(AGroups[g].Acts[k]) then
        AModel.Entries[Sub].Enabled := True;
    end;
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
  i, Base   : Integer;
  Count     : Integer;
  NSup      : Integer;
  Acts      : TArray<TFindingAction>;
  SepDone   : Boolean;
  TopGroups : Integer;                 // Fund-Gruppen der obersten Ebene
  Seen      : TArray<string>;   // Captions der schon gezeigten Umbauten
  SeenCount : Integer;
  Groups    : TArray<TSuppressGroup>;  // Funde mit Unterdrueck-Aktionen
  NGroups   : Integer;
begin
  Result    := Default(TFindingMenuModel);
  Count     := Length(AFindings);
  if Length(AActions) < Count then Count := Length(AActions);
  SepDone   := False;
  TopGroups := 0;
  Seen      := nil;
  SeenCount := 0;
  SetLength(Groups, Count);
  NGroups   := 0;
  for i := 0 to Count - 1 do
  begin
    Acts := DropSeenRefactors(FilterActions(AActions[i], AOptions), Seen,
      SeenCount);
    if Length(Acts) = 0 then Continue;
    NSup := SuppressCount(Acts);
    if NSup < Length(Acts) then
    begin
      SeparateNext(Result, AOptions, SepDone, TopGroups);
      if moHeaders in AOptions then
        AddEntry(Result, mkHeader, FindingHeaderCaption(AFindings[i]), '',
          False, -1);
      Inc(TopGroups);
    end;
    Base := AddActionsOf(Result, Acts, AFindings[i]);
    if NSup > 0 then
    begin
      Groups[NGroups].Finding := AFindings[i];
      Groups[NGroups].Base    := Base;
      Groups[NGroups].Acts    := Acts;
      Inc(NGroups);
    end;
  end;
  if NGroups = 0 then Exit;
  SetLength(Groups, NGroups);
  SeparateNext(Result, AOptions, SepDone, TopGroups);
  AddSuppressMenu(Result, Groups, AOptions);
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
    if SameText(AModel.Actions[i].Caption, ACaption) then
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
      Dup := SameText(Keep[s].Caption, AActions[k].Caption);
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
  AddActionsOf(AModel, Keep, nil);
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
