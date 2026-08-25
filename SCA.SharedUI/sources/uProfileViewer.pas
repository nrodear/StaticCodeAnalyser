unit uProfileViewer;

// Profil-Fenster der Standalone-Anwendung.
//
// STUFE 1 - ansehen: links die Profile, rechts die Regeln des gewaehlten,
// mit ID, Kind-Token, Name, Severity und Typ. Vorher war der Profilname
// im Filter-Combo das Einzige, was ein Anwender ueber ein Profil zu sehen
// bekam; WELCHE Regeln dahinterstehen, stand nur in der JSON.
//
// STUFE 2 - eigene Profile: ein bestehendes kopieren und dann Regeln
// aufnehmen oder entfernen. Die EINGEBAUTEN bleiben unveraenderlich, und
// zwar nicht aus Vorsicht, sondern weil sie aus dem ausgelieferten
// rules/sca-rules.json stammen und bei jedem Update ueberschrieben
// wuerden. Eigene Profile liegen deshalb daneben in profiles.json im
// Konfigverzeichnis - dieselbe Ablage wie analyser.ini - und ueberleben
// ein Update. Geladen werden sie in der Engine (TRuleCatalog), damit ein
// selbst gebautes Profil auch mit `--profile <name>` in der CI greift und
// im IDE-Plugin im Combo steht.
//
// Bewusst ohne .dfm: beide Fenster werden zur Laufzeit komponiert. So
// aendert sich am Projekt-Layout nichts ausser einem uses-Eintrag.
//
// Liegt in SCA.SharedUI, weil BEIDE Oberflaechen es zeigen: die
// Standalone ueber ihr Burger-Menue, das IDE-Plugin ueber seines. Die
// EXE zieht die Unit ueber den Suchpfad, das Plugin ueber das Paket -
// derselbe Weg, den uAppTheme und uIDEStatsTiles schon nehmen.
//
// Feste Groesse, nicht veraenderbar (bsDialog): das Fenster zeigt eine
// Liste bekannter Breite: fuenf Spalten mit festen Werten. Es gibt
// nichts, was von mehr Platz profitierte, und in der IDE soll es sich
// wie ein Eigenschaften-Dialog anfuehlen, nicht wie ein zweites
// Hauptfenster.

interface

uses
  Vcl.Controls;   // TWinControl - Parametertyp des Theme-Hooks

type
  // Wird auf jedes frisch gebaute Fenster dieser Unit angewandt, bevor
  // es sichtbar wird.
  //
  // Warum ein Hook und kein direkter Aufruf: die Unit liegt in
  // SCA.SharedUI und darf ToolsAPI nicht kennen - das IDE-Theming laeuft
  // aber genau darueber (TIDETheme.Apply -> IOTAIDEThemingServices).
  // Und die Standalone braucht etwas anderes als die IDE:
  // TAppTheme.ApplyToForm gegen den aktiven VCL-Style. Dieselbe
  // Schichtgrenze und dasselbe Muster wie StyleServicesProvider und
  // EditorBgProvider in uAnalyserTheme.
  //
  // Der Wirt setzt ihn nur fuer die Dauer des Aufrufs und nimmt ihn
  // danach zurueck. So kann die Closure nicht in entladenen Plugin-Code
  // zeigen - die Falle, vor der uAnalyserTheme bei seinen Providern
  // ausdruecklich warnt.
  //
  // VERTRAG, der daran haengt: das traegt nur, solange die Fenster
  // dieser Unit MODAL sind. Der Hook wird beim Anlegen des Fensters
  // gerufen und danach sofort auf nil gesetzt; ein spaeter feuernder
  // Callback - etwa aus einem Theme-Wechsel bei offenem Fenster - traefe
  // ins Leere. Wird eines der Fenster nicht-modal, braucht es statt
  // dieses Einmal-Hooks ein Abonnement, und der Wirt darf ihn dann nicht
  // mehr zuruecknehmen.
  TProfileViewerThemeProc = reference to procedure(AControl: TWinControl);

var
  // Wird auf das fertig gebaute Fenster angewandt, bevor es sichtbar
  // wird. Die Titelzeile ist KEIN Sonderfall mehr: beide Wirte faerben
  // sie in ihrer Theme-Anwendung mit, sobald ein Fenster uebergeben wird
  // (TAppTheme.ApplyToForm bzw. TIDETheme.Apply).
  ProfileViewerTheme: TProfileViewerThemeProc = nil;

// Zeigt das Fenster modal. Ergebnis True, wenn Profile angelegt oder
// geloescht wurden - der Aufrufer muss dann sein Profil-Combo neu
// befuellen, sonst kennt es den neuen Namen erst nach einem Neustart.
function ShowProfileViewer: Boolean;

implementation

// noinspection-file LongMethod, TooLongLine, UnsortedUses, GodClass
// Runtime-UI-Komposition: der Aufbau EINES Fensters gehoert in EINE
// Methode, sonst zerfaellt die Lesereihenfolge der Layout-Zeilen.

uses
  System.SysUtils, System.Classes,
  System.Generics.Collections,
  uRuleListBox,     // TRuleListBox - die geteilte Regelliste beider Fenster
  // Vcl.Controls steht bereits im interface-uses (TWinControl im
  // Hook-Typ) - hier nicht noch einmal, sonst E2004.
  Vcl.Forms, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls,
  Vcl.Dialogs,
  Winapi.Windows,
  uSCAConsts,       // TFindingKind, TFindingKinds, KindName
  uRuleCatalog,     // Profile lesen UND eigene schreiben
  uLocalization;    // _() und CurrentLanguage

const
  // Fenster- und Knopftexte, die MEHRFACH gebraucht werden: einmal als
  // Beschriftung, dann wieder als Titel der Rueckfrage oder der
  // Fehlermeldung. Der eigene Detektor meldet sie ab dem dritten
  // Vorkommen - zu Recht, denn die Kopien muessen zusammenbleiben: eine
  // geaenderte Beschriftung mit altem Meldungstitel liest sich wie zwei
  // verschiedene Funktionen.
  //
  // Der Wert bleibt der englische Quelltext, _() steht weiterhin an der
  // Verwendungsstelle - die msgid aendert sich also nicht und die .po
  // bleiben unberuehrt.
  TXT_PROFILE_WINDOW = 'Rule-set profiles';
  TXT_REMOVE_RULES   = 'Remove rules';
  TXT_IMPORT         = 'Import profiles';

  // Alle Kinds als Menge. TRuleCatalog.AllKinds ist strict private, und
  // fuer diesen einen Ausdruck lohnt kein Aufreissen der Kapselung.
  ALL_KINDS = [Low(TFindingKind) .. High(TFindingKind)];

type
  TProfileViewerForm = class(TForm)
  strict private
    FLstProfiles : TListBox;
    FRules       : TRuleListBox;
    FLblInfo     : TLabel;
    FBtnCopy     : TButton;
    FBtnAdd      : TButton;
    FBtnRemove   : TButton;
    FBtnDelete   : TButton;
    FBtnSave     : TButton;
    FBtnReload   : TButton;
    FBtnImport   : TButton;
    // Rohe Profilnamen, index-gleich zu FLstProfiles.Items: die Anzeige
    // haengt Regelzahl und Herkunft an, der Katalog-Zugriff braucht den
    // unveraenderten Namen.
    FNames       : TStringList;
    FCurrent     : string;          // gewaehltes Profil
    FKinds       : TFindingKinds;   // Arbeitsstand des gewaehlten Profils
    FIsOwn       : Boolean;         // eigenes (aenderbares) Profil?
    FDirty       : Boolean;         // ungespeicherte Aenderung
    FChanged     : Boolean;         // angelegt/geloescht -> Combo neu
    procedure BuildUi;
    procedure LoadProfiles(const APreferred: string);
    procedure ShowRulesOf(const AProfile: string);
    procedure RefreshRuleList;
    // Haengt an TRuleListBox.OnFilled: die Infozeile muss nach jedem
    // Fuellen stimmen, auch nach einer Filteraenderung.
    procedure RulesFilled;
    procedure UpdateButtons;
    procedure SetDirty(AValue: Boolean);
    function  AskSaveIfDirty: Boolean;   // False = Abbruch durch Anwender
    function  SaveCurrent: Boolean;
    procedure ProfileSelected(Sender: TObject);
    procedure CopyClick(Sender: TObject);
    procedure AddClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    // Liest profiles.json neu ein. Braucht es, weil TRuleCatalog die
    // Datei sonst nur EINMAL je Prozess liest - wer sie von Hand
    // anlegt oder bearbeitet, saehe seine Profile sonst erst nach
    // einem Neustart der Anwendung bzw. der IDE.
    procedure ReloadClick(Sender: TObject);
    // Uebernimmt Profile aus einer BELIEBIGEN Datei in die eigenen.
    // "Neu laden" liest nur den festen Ablageort - wer ein Regelwerk
    // per Mail oder aus einem Projektverzeichnis bekommt, will es nicht
    // erst von Hand dorthin kopieren muessen.
    procedure ImportClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  public
    constructor CreateNew(AOwner: TComponent; Dummy: Integer = 0); override;
    destructor Destroy; override;
    // NICHT 'Changed': TControl fuehrt bereits einen Member dieses
    // Namens, und ihn zu verdecken bringt W1009 - berechtigt, denn wer
    // spaeter TControl.Changed aufrufen will, greift versehentlich hier
    // hinein.
    property ProfilesChanged: Boolean read FChanged;
  end;

// ---------------------------------------------------------------------
// Anzeigetexte fuer die beiden Enums.
//
// TLeakFinding.SeverityText/TypeText in uMethodd12 liefern dasselbe,
// haengen aber an einem Befund - hier gibt es keinen Befund, nur eine
// Regel. Die msgids sind absichtlich WORTGLEICH mit denen dort, damit
// beide Stellen aus demselben .po-Eintrag bedient werden.
// ---------------------------------------------------------------------
function KindCount(const AKinds: TFindingKinds): Integer;
var
  K : TFindingKind;
begin
  Result := 0;
  for K := Low(TFindingKind) to High(TFindingKind) do
    if K in AKinds then
      Inc(Result);
end;

// ---------------------------------------------------------------------
// Die Regeln einer Kind-Menge einsammeln, nach Regel-ID sortiert.
//
// Nimmt eine MENGE entgegen, keinen Profilnamen - so bedient dieselbe
// Funktion das gespeicherte Profil und den ungespeicherten Arbeitsstand.
// ---------------------------------------------------------------------
function PickRules(const ACandidates: TFindingKinds;
  out APicked: TFindingKinds): Boolean;
var
  Dlg    : TForm;
  Bottom : TPanel;
  BtnOk  : TButton;
  BtnNo  : TButton;
  Lbl    : TLabel;
  Liste  : TRuleListBox;
begin
  Result  := False;
  APicked := [];
  if ACandidates = [] then
  begin
    Application.MessageBox(
      PChar(_('This profile already contains every rule.')),
      PChar(_('Add rules')), MB_OK or MB_ICONINFORMATION);
    Exit;
  end;

  Liste := nil;   // fuers finally, falls schon der Aufbau wirft
  Dlg   := TForm.CreateNew(nil);
  try
    Dlg.Caption      := _('Add rules');
    Dlg.Position     := poMainFormCenter;
    Dlg.PopupMode    := pmAuto;   // s. Begruendung im Hauptfenster
    // Gleiche Bauart wie das Profil-Fenster: feste Groesse, kein
    // Sizing-Rahmen. Die Spaltenbreiten stehen fest, also auch die
    // sinnvolle Fensterbreite.
    Dlg.BorderStyle  := bsDialog;
    // s. Begruendung im Hauptfenster - ohne das malt der VCL-Style die
    // Titelzeile selbst und die DWM-Farbe bleibt unsichtbar.
    Dlg.StyleElements := Dlg.StyleElements - [seBorder];
    Dlg.ClientWidth  := 900;
    Dlg.ClientHeight := 600;

    Bottom := TPanel.Create(Dlg);
    Bottom.Parent     := Dlg;
    Bottom.Align      := alBottom;
    Bottom.Height     := 44;
    Bottom.BevelOuter := bvNone;

    BtnNo := TButton.Create(Dlg);
    BtnNo.Parent      := Bottom;
    BtnNo.Caption     := _('Cancel');
    BtnNo.ModalResult := mrCancel;
    BtnNo.Cancel      := True;
    BtnNo.Width       := 110;
    BtnNo.Height      := 28;
    BtnNo.Top         := 8;
    BtnNo.Left        := Dlg.ClientWidth - 122;
    BtnNo.Anchors     := [akTop, akRight];

    BtnOk := TButton.Create(Dlg);
    BtnOk.Parent      := Bottom;
    BtnOk.Caption     := _('Add');
    BtnOk.ModalResult := mrOk;
    BtnOk.Default     := True;
    BtnOk.Width       := 110;
    BtnOk.Height      := 28;
    BtnOk.Top         := 8;
    BtnOk.Left        := BtnNo.Left - 118;
    BtnOk.Anchors     := [akTop, akRight];

    Lbl := TLabel.Create(Dlg);
    Lbl.Parent := Bottom;
    Lbl.Left   := 12;
    Lbl.Top    := 14;

    // Dieselbe Liste wie im Profil-Fenster, hier mit Haken. Sortieren
    // und Suchen kommen damit von selbst mit.
    Liste := TRuleListBox.Create(Dlg, Dlg, True);
    // Zaehlt die Haken INSGESAMT, nicht die sichtbaren: man filtert,
    // hakt an, filtert weiter - ohne diese Zeile waere nicht zu sehen,
    // dass die frueheren Haken noch stehen.
    Liste.OnFilled :=
      procedure
      begin
        if Liste.FilterText <> '' then
          Lbl.Caption := Format(
            _('%d of %d rules shown, %d selected'),
            [Liste.Shown, Liste.Total, Liste.CheckedCount])
        else
          Lbl.Caption := Format(_('%d rules, %d selected'),
            [Liste.Total, Liste.CheckedCount]);
      end;
    Liste.SetKinds(ACandidates);

    // Vor dem Anzeigen: das Theming darf hier das Handle neu erzeugen,
    // sichtbar ist noch nichts. Die Titelzeile kommt mit.
    if Assigned(ProfileViewerTheme) then
      ProfileViewerTheme(Dlg);

    if Dlg.ShowModal = mrOk then
    begin
      APicked := Liste.CheckedKinds;
      Result  := APicked <> [];
    end;
  finally
    Liste.Free;
    Dlg.Free;
  end;
end;

{ TProfileViewerForm }

constructor TProfileViewerForm.CreateNew(AOwner: TComponent; Dummy: Integer);
begin
  inherited CreateNew(AOwner, Dummy);
  FNames    := TStringList.Create;
  BuildUi;
  LoadProfiles('');
  // Jetzt stehen die Controls. Das Theming darf hier das Handle neu
  // erzeugen - das Fenster ist noch nicht sichtbar - und faerbt die
  // Titelzeile gleich mit.
  if Assigned(ProfileViewerTheme) then
    ProfileViewerTheme(Self);
end;

destructor TProfileViewerForm.Destroy;
begin
  FRules.Free;
  FNames.Free;
  inherited;
end;

procedure TProfileViewerForm.BuildUi;
var
  Bottom : TPanel;
  X      : Integer;

  function MkButton(const ACaption: string; AOnClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent  := Bottom;
    Result.Caption := ACaption;
    Result.Width   := 122;
    Result.Height  := 28;
    Result.Top     := 8;
    Dec(X, Result.Width);
    Result.Left    := X;
    Dec(X, 8);
    Result.Anchors := [akTop, akRight];
    Result.OnClick := AOnClick;
  end;

begin
  Caption      := _(TXT_PROFILE_WINDOW);
  Position     := poMainFormCenter;
  // PopupMode NICHT auf pmNone lassen. ShowModal macht sonst
  //   if (PopupMode = pmNone) and (Application.ModalPopupMode <> pmNone)
  //     then RecreateWnd
  // (Vcl.Forms.pas:9792). Das Fensterhandle waere danach ein anderes als
  // das, an dem der Konstruktor die dunkle Titelzeile gesetzt hat - das
  // DWM-Attribut haengt am Handle. Ob die IDE ModalPopupMode setzt, ist
  // von aussen nicht feststellbar; pmAuto nimmt die Frage weg und ist im
  // Plugin ohnehin richtig, weil das Fenster damit dem aktiven Fenster
  // gehoert statt dem Application-Handle.
  PopupMode    := pmAuto;
  // bsDialog: kein Sizing-Rahmen, kein Maximieren-Knopf. Die Breite
  // ergibt sich aus den Spalten (80+190+360+90+130) plus Profilliste.
  BorderStyle  := bsDialog;
  // seBorder heraus - der Rahmen gehoert Windows, nicht dem VCL-Style.
  //
  // Vcl.Forms.TFormStyleHook.IsStyleBorder entscheidet aus drei Werten,
  // ob der Style die Nicht-Client-Flaeche uebernimmt:
  //   (TStyleManager.FormBorderStyle = fbsCurrentStyle)
  //   and (seBorder in StyleElements)
  //   and (CustomTitleBar.Enabled = False)
  // Uebernimmt er sie, malt er die Titelzeile selbst - und ein
  // DWM-Attribut bleibt folgenlos, auch wenn Windows es mit S_OK
  // quittiert. Genau so sah die Messung am 2026-08-24 aus.
  //
  // seBorder ist die einzige der drei Bedingungen, die diesem Fenster
  // gehoert: FormBorderStyle ist prozessglobal, und CustomTitleBar zu
  // aktivieren zoege GlassFrame und eine verschobene Client-Geometrie
  // nach sich - bei alClient- und alBottom-Kindern eine sichtbare
  // Layout-Aenderung. Bezeichnend: CustomTitleBar.SetEnabled nimmt
  // intern SELBST seBorder heraus (Vcl.Forms.pas:15223).
  //
  // Nur seBorder: seClient und seFont bleiben, Inhalt und Schrift
  // bleiben also gethemt. Der Preis ist der Windows-11-Rahmen statt des
  // vom Style nachgebauten.
  //
  // Steht hier und nicht in TIDETheme.Apply: dort traefe es jedes
  // Fenster, das je durch die Methode geht, und eine Theme-Anwendung
  // soll die Rahmen-Konfiguration fremder Fenster nicht umschreiben.
  StyleElements := StyleElements - [seBorder];
  ClientWidth  := 1120;
  ClientHeight := 640;
  KeyPreview   := True;
  OnKeyDown    := FormKeyDown;
  OnCloseQuery := FormCloseQuery;

  // ---- Fusszeile zuerst: alClient darueber fuellt dann den Rest ----
  Bottom := TPanel.Create(Self);
  Bottom.Parent     := Self;
  Bottom.Align      := alBottom;
  Bottom.Height     := 78;
  Bottom.BevelOuter := bvNone;

  // Von rechts nach links aufgereiht - "Schliessen" liegt aussen, weil
  // es der einzige Knopf ist, den man blind sucht.
  X := Bottom.Width - 12;
  MkButton(_('Close'), CloseClick).Cancel := True;
  FBtnSave   := MkButton(_('Save'),           SaveClick);
  FBtnDelete := MkButton(_('Delete profile'), DeleteClick);
  FBtnRemove := MkButton(_(TXT_REMOVE_RULES),   RemoveClick);
  FBtnAdd    := MkButton(_('Add rules...'),   AddClick);
  FBtnCopy   := MkButton(_('Copy...'),        CopyClick);
  FBtnReload := MkButton(_('Reload'),         ReloadClick);
  FBtnImport := MkButton(_('Import...'),      ImportClick);

  FLblInfo := TLabel.Create(Self);
  FLblInfo.Parent  := Bottom;
  FLblInfo.Left    := 12;
  FLblInfo.Top     := 48;
  FLblInfo.Anchors := [akLeft, akTop, akRight];
  FLblInfo.Caption := '';

  // ---- links die Profile ----
  FLstProfiles := TListBox.Create(Self);
  FLstProfiles.Parent  := Self;
  FLstProfiles.Align   := alLeft;
  FLstProfiles.Width   := 250;
  FLstProfiles.OnClick := ProfileSelected;

  // ---- rechts Suchfeld + Regeln des gewaehlten Profils ----
  // Dieselbe Liste wie im Auswahldialog: Kopfzeilen sortieren,
  // Textfeld filtert. Hier ohne Haken, dafuer mit Mehrfachauswahl -
  // "Regeln entfernen" arbeitet darauf.
  FRules := TRuleListBox.Create(Self, Self, False);
  // Als anonyme Huelle: OnFilled ist ein "reference to procedure",
  // RulesFilled eine Methode. Die direkte Zuweisung waere vermutlich
  // erlaubt, aber sie ist selten genug, dass sie hier keinen Platz
  // verdient - die eine Zeile kostet nichts und laesst keine Frage offen.
  FRules.OnFilled := procedure begin RulesFilled; end;
end;

procedure TProfileViewerForm.LoadProfiles(const APreferred: string);
var
  Names : TArray<string>;
  Std   : TStringList;
  Own   : TStringList;
  Name  : string;
  Idx   : Integer;
begin
  Names := TRuleCatalog.ProfileNames;

  // ProfileNames liefert Dictionary-Schluessel, also ohne verlaessliche
  // Reihenfolge. Erst sortieren, dann eingebaute vor eigene - sonst
  // steht die Liste bei jedem Oeffnen anders da.
  Std := TStringList.Create;
  Own := TStringList.Create;
  try
    Std.Sorted := True;
    Own.Sorted := True;
    for Name in Names do
      if TRuleCatalog.IsBuiltInProfile(Name) then
        Std.Add(Name)
      else
        Own.Add(Name);

    FNames.Clear;
    FLstProfiles.Items.BeginUpdate;
    try
      FLstProfiles.Items.Clear;
      for Name in Std do
      begin
        FNames.Add(Name);
        FLstProfiles.Items.Add(Format('%s  (%d)',
          [Name, KindCount(TRuleCatalog.GetProfile(Name))]));
      end;
      for Name in Own do
      begin
        FNames.Add(Name);
        FLstProfiles.Items.Add(Format('%s  (%d)  %s',
          [Name, KindCount(TRuleCatalog.GetProfile(Name)), _('- own')]));
      end;
    finally
      FLstProfiles.Items.EndUpdate;
    end;
  finally
    Own.Free;
    Std.Free;
  end;

  if FLstProfiles.Items.Count = 0 then
  begin
    // Kein Profil: der Katalog war nicht ladbar. Kein Absturz, aber es
    // muss sichtbar sein - sonst steht der Anwender vor einem leeren
    // Fenster ohne Erklaerung.
    FCurrent := '';
    FIsOwn   := False;
    FLblInfo.Caption := _('No rule catalogue found - profiles unavailable.');
    UpdateButtons;
    Exit;
  end;

  Idx := FNames.IndexOf(Trim(APreferred));
  if Idx < 0 then Idx := 0;
  FLstProfiles.ItemIndex := Idx;
  ShowRulesOf(FNames[Idx]);
end;

procedure TProfileViewerForm.ShowRulesOf(const AProfile: string);
begin
  FCurrent := AProfile;
  FKinds   := TRuleCatalog.GetProfile(AProfile);
  FIsOwn   := not TRuleCatalog.IsBuiltInProfile(AProfile);
  FDirty   := False;
  RefreshRuleList;
end;

procedure TProfileViewerForm.RefreshRuleList;
// Sortierung und Filter bleiben ueber den Profilwechsel stehen - wer
// eine Spalte sortiert hat, will nicht bei jedem Klick von vorn
// anfangen.
begin
  FRules.SetKinds(FKinds);
  UpdateButtons;
end;

procedure TProfileViewerForm.RulesFilled;
begin
  if FRules.FilterText <> '' then
    // Bei aktivem Filter sagen, wovon man einen Ausschnitt sieht - sonst
    // haelt man die gefilterte Zahl fuer die Groesse des Profils.
    FLblInfo.Caption := Format(
      _('Profile "%s": %d of %d rules shown (filter "%s").'),
      [FCurrent, FRules.Shown, FRules.Total, FRules.FilterText])
  else if FIsOwn then
    FLblInfo.Caption := Format(
      _('Profile "%s": %d of %d rules. Your own profile, stored in %s'),
      [FCurrent, FRules.Total, TRuleCatalog.Count,
       TRuleCatalog.UserProfilesFilePath])
  else
    FLblInfo.Caption := Format(
      _('Profile "%s": %d of %d rules. Built-in and read-only - use "Copy..." for your own (stored in %s).'),
      [FCurrent, FRules.Total, TRuleCatalog.Count,
       TRuleCatalog.UserProfilesFilePath]);
end;

procedure TProfileViewerForm.UpdateButtons;
var
  Has : Boolean;
begin
  Has := FLstProfiles.Items.Count > 0;
  // Neu laden geht immer - auch wenn die Liste leer ist, denn genau
  // dann will man es (Katalog war nicht da, Datei nachgelegt).
  FBtnReload.Enabled := True;
  FBtnImport.Enabled := True;
  FBtnCopy.Enabled   := Has;
  FBtnAdd.Enabled    := Has and FIsOwn;
  FBtnRemove.Enabled := Has and FIsOwn;
  FBtnDelete.Enabled := Has and FIsOwn;
  FBtnSave.Enabled   := Has and FIsOwn and FDirty;
end;

procedure TProfileViewerForm.SetDirty(AValue: Boolean);
begin
  FDirty := AValue;
  UpdateButtons;
end;

function TProfileViewerForm.SaveCurrent: Boolean;
var
  Err : string;
begin
  Result := TRuleCatalog.SaveUserProfile(FCurrent, FKinds, Err);
  if Result then
    SetDirty(False)
  else
    Application.MessageBox(PChar(Err), PChar(_(TXT_PROFILE_WINDOW)),
                           MB_OK or MB_ICONERROR);
end;

function TProfileViewerForm.AskSaveIfDirty: Boolean;
var
  Answer : Integer;
begin
  Result := True;
  if not FDirty then Exit;

  Answer := Application.MessageBox(
    PChar(Format(_('Save the changes to profile "%s"?'), [FCurrent])),
    PChar(_(TXT_PROFILE_WINDOW)), MB_YESNOCANCEL or MB_ICONQUESTION);
  case Answer of
    IDYES : Result := SaveCurrent;
    IDNO  : SetDirty(False);
  else
    Result := False;
  end;
end;

procedure TProfileViewerForm.ProfileSelected(Sender: TObject);
var
  Idx : Integer;
begin
  Idx := FLstProfiles.ItemIndex;
  if (Idx < 0) or (Idx >= FNames.Count) then Exit;
  if FNames[Idx] = FCurrent then Exit;

  if not AskSaveIfDirty then
  begin
    // Zurueck auf das alte Profil - sonst zeigt die Liste eines an und
    // das Fenster ein anderes.
    FLstProfiles.ItemIndex := FNames.IndexOf(FCurrent);
    Exit;
  end;
  ShowRulesOf(FNames[Idx]);
end;

procedure TProfileViewerForm.CopyClick(Sender: TObject);
var
  NewName : string;
  Err     : string;
begin
  if not AskSaveIfDirty then Exit;
  if FCurrent = '' then Exit;

  NewName := FCurrent + '-copy';
  if not InputQuery(_('Copy profile'), _('Name of the new profile:'), NewName) then
    Exit;

  if not TRuleCatalog.SaveUserProfile(NewName, FKinds, Err) then
  begin
    Application.MessageBox(PChar(Err), PChar(_('Copy profile')),
                           MB_OK or MB_ICONERROR);
    Exit;
  end;
  FChanged := True;
  LoadProfiles(NewName);
end;

procedure TProfileViewerForm.AddClick(Sender: TObject);
var
  Picked : TFindingKinds;
begin
  if not FIsOwn then Exit;
  if PickRules(ALL_KINDS - FKinds, Picked) then
  begin
    FKinds := FKinds + Picked;
    SetDirty(True);
    RefreshRuleList;
  end;
end;

procedure TProfileViewerForm.RemoveClick(Sender: TObject);
var
  Doomed : TFindingKinds;
begin
  if not FIsOwn then Exit;

  // Nur die MARKIERTEN, und nur die gerade sichtbaren - bei aktivem
  // Filter entfernt man genau das, was man vor sich sieht.
  Doomed := FRules.SelectedKinds;

  if Doomed = [] then
  begin
    Application.MessageBox(PChar(_('Select the rules to remove first.')),
      PChar(_(TXT_REMOVE_RULES)), MB_OK or MB_ICONINFORMATION);
    Exit;
  end;
  if FKinds - Doomed = [] then
  begin
    Application.MessageBox(PChar(_('A profile without rules would find nothing.')),
      PChar(_(TXT_REMOVE_RULES)), MB_OK or MB_ICONWARNING);
    Exit;
  end;

  FKinds := FKinds - Doomed;
  SetDirty(True);
  RefreshRuleList;
end;

procedure TProfileViewerForm.DeleteClick(Sender: TObject);
var
  Err : string;
begin
  if not FIsOwn then Exit;
  if Application.MessageBox(
       PChar(Format(_('Delete profile "%s"?'), [FCurrent])),
       PChar(_(TXT_PROFILE_WINDOW)),
       MB_YESNO or MB_ICONQUESTION) <> IDYES then Exit;

  if not TRuleCatalog.DeleteUserProfile(FCurrent, Err) then
  begin
    Application.MessageBox(PChar(Err), PChar(_(TXT_PROFILE_WINDOW)),
                           MB_OK or MB_ICONERROR);
    Exit;
  end;
  FChanged := True;
  FDirty   := False;
  LoadProfiles('');
end;

procedure TProfileViewerForm.SaveClick(Sender: TObject);
begin
  if FIsOwn and FDirty and SaveCurrent then
    // Die Regelzahl in der linken Liste stimmt jetzt nicht mehr.
    LoadProfiles(FCurrent);
end;

procedure TProfileViewerForm.ReloadClick(Sender: TObject);
// Verwirft den Katalog-Cache und liest alles neu, einschliesslich
// profiles.json. Danach steht in der Liste, was auf der Platte liegt.
//
// FChanged wird gesetzt, weil der Wirt sein Profil-Combo danach neu
// befuellen muss: die Datei kann Profile mitbringen, die es beim
// Oeffnen des Fensters noch nicht gab.
var
  Vorher : string;
begin
  if not AskSaveIfDirty then Exit;
  Vorher := FCurrent;
  TRuleCatalog.Reload;
  FChanged := True;
  LoadProfiles(Vorher);
end;

{ Import-Ablauf - Unit-Ebene, nicht Teil des Fensters }
// Aus TProfileViewerForm herausgezogen (Selbstscan: die Klasse lag bei
// 596 Zeilen, Grenze 500). Die drei Schritte brauchen vom Fenster nichts
// ausser der Liste der bekannten Namen, und einzeln sind sie lesbar,
// ohne den ganzen Dialogablauf mitzudenken.

procedure SplitImportNames(ANames, AVorhanden, ANew, AReplaced,
  AFixed: TStringList);
// Teilt die gelesenen Profilnamen in "neu", "wird ueberschrieben" und
// "uebersprungen, Name eines eingebauten Profils". AVorhanden sind die
// heute bekannten Profile.
var
  Name : string;
begin
  for Name in ANames do
    if TRuleCatalog.IsBuiltInProfile(Name) then
      // Ein eingebauter Name ist unantastbar: derselbe Name haette sonst
      // je nach Rechner eine andere Bedeutung.
      AFixed.Add(Name)
    else if AVorhanden.IndexOf(Name) >= 0 then
      AReplaced.Add(Name)
    else
      ANew.Add(Name);
end;

function ImportPrompt(ANew, AReplaced, AFixed: TStringList): string;
// Der Bestaetigungstext zur Dreiteilung. Leerstring, wenn es nichts zu
// uebernehmen gibt - dann hat der Aufrufer nichts zu fragen.
begin
  if (ANew.Count = 0) and (AReplaced.Count = 0) then Exit('');
  Result := '';
  if ANew.Count > 0 then
    Result := Result + Format(_('New: %s'), [ANew.CommaText]) + sLineBreak;
  if AReplaced.Count > 0 then
    Result := Result + Format(_('Will be overwritten: %s'),
                              [AReplaced.CommaText]) + sLineBreak;
  if AFixed.Count > 0 then
    Result := Result + Format(_('Skipped (built-in name): %s'),
                              [AFixed.CommaText]) + sLineBreak;
  Result := Result + sLineBreak + _('Import now?');
end;

function WriteImported(ANames: TStringList;
  AMap: TDictionary<string, TFindingKinds>): string;
// Jedes Profil einzeln ueber SaveUserProfile: dort sitzt die Namens- und
// Inhaltspruefung, und dort wird zurueckgerollt, wenn das Schreiben
// scheitert. Das kostet je Profil einen Schreibvorgang - bei der Handvoll
// Profile einer Datei kein Thema, und es waere die falsche Ersparnis, die
// Pruefung dafuer zu umgehen.
var
  Name           : string;
  Fehler         : string;
  Fehlgeschlagen : Integer;
begin
  Result := '';
  Fehlgeschlagen := 0;
  for Name in ANames do
  begin
    if TRuleCatalog.IsBuiltInProfile(Name) then Continue;
    if TRuleCatalog.SaveUserProfile(Name, AMap[Name], Fehler) then
      Result := Name
    else
    begin
      Inc(Fehlgeschlagen);
      // Nur der erste Fehler wird gezeigt - drei Meldungsfenster
      // hintereinander helfen niemandem.
      if Fehlgeschlagen = 1 then
        Application.MessageBox(PChar(Format(_('"%s" was not imported: %s'),
          [Name, Fehler])), PChar(_(TXT_IMPORT)),
          MB_OK or MB_ICONERROR);
    end;
  end;
end;

procedure TProfileViewerForm.ImportClick(Sender: TObject);
// Liest eine fremde Profildatei und uebernimmt daraus, was uebernommen
// werden darf.
//
// Bewusst zweistufig: erst lesen und zeigen, was passieren WUERDE, dann
// auf Bestaetigung schreiben. Ein Import, der stillschweigend ein
// gleichnamiges eigenes Profil ueberschreibt, waere die eine Sache, die
// man hinterher nicht mehr zurueckholen kann.
var
  Dlg     : TOpenDialog;
  Gelesen : TDictionary<string, TFindingKinds>;
  Fehler  : string;
  Namen   : TStringList;
  Eintrag : TPair<string, TFindingKinds>;
  Neu     : TStringList;   // koennen angelegt werden
  Ersetzt : TStringList;   // eigene Profile, die ueberschrieben wuerden
  Fest    : TStringList;   // Namen eingebauter Profile - unantastbar
  Text    : string;
  Zuletzt : string;
begin
  if not AskSaveIfDirty then Exit;

  Dlg := TOpenDialog.Create(nil);
  Gelesen := TDictionary<string, TFindingKinds>.Create;
  Namen   := TStringList.Create;
  Neu     := TStringList.Create;
  Ersetzt := TStringList.Create;
  Fest    := TStringList.Create;
  try
    Dlg.Title      := _(TXT_IMPORT);
    Dlg.Filter     := _('Profile files (*.json)|*.json|All files (*.*)|*.*');
    Dlg.Options    := Dlg.Options + [ofFileMustExist, ofPathMustExist];
    // Startet dort, wo die eigenen Profile liegen - der haeufigste Fall
    // ist, eine Datei von woanders NEBEN die eigene zu legen.
    Dlg.InitialDir := ExtractFilePath(TRuleCatalog.UserProfilesFilePath);
    if not Dlg.Execute then Exit;

    if not TRuleCatalog.ReadProfilesFile(Dlg.FileName, Gelesen, Fehler) then
    begin
      Application.MessageBox(PChar(Fehler), PChar(_(TXT_IMPORT)),
                             MB_OK or MB_ICONERROR);
      Exit;
    end;

    // Sortiert entscheiden und sortiert berichten - eine Dictionary-
    // Reihenfolge ist nicht festgelegt, und eine Liste, die bei gleichem
    // Inhalt anders aussieht, liest niemand zweimal.
    for Eintrag in Gelesen do
      Namen.Add(Eintrag.Key);
    Namen.Sort;
    SplitImportNames(Namen, FNames, Neu, Ersetzt, Fest);

    Text := ImportPrompt(Neu, Ersetzt, Fest);
    if Text = '' then
    begin
      if Fest.Count > 0 then
        Text := Format(
          _('Nothing to import: %s only contains names of built-in profiles (%s).'),
          [ExtractFileName(Dlg.FileName), Fest.CommaText])
      else
        Text := Format(_('%s contains no profiles.'),
                       [ExtractFileName(Dlg.FileName)]);
      Application.MessageBox(PChar(Text), PChar(_(TXT_IMPORT)),
                             MB_OK or MB_ICONINFORMATION);
      Exit;
    end;

    if Application.MessageBox(PChar(Text), PChar(_(TXT_IMPORT)),
         MB_YESNO or MB_ICONQUESTION) <> IDYES then Exit;

    Zuletzt := WriteImported(Namen, Gelesen);
    if Zuletzt <> '' then
    begin
      FChanged := True;
      LoadProfiles(Zuletzt);
    end;
  finally
    Fest.Free;
    Ersetzt.Free;
    Neu.Free;
    Namen.Free;
    Gelesen.Free;
    Dlg.Free;
  end;
end;

procedure TProfileViewerForm.CloseClick(Sender: TObject);
begin
  Close;
end;

procedure TProfileViewerForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := AskSaveIfDirty;
end;

procedure TProfileViewerForm.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    Key := 0;
    Close;
  end;
end;

function ShowProfileViewer: Boolean;
var
  Dlg : TProfileViewerForm;
begin
  Dlg := TProfileViewerForm.CreateNew(nil);
  try
    Dlg.ShowModal;
    Result := Dlg.ProfilesChanged;
  finally
    Dlg.Free;
  end;
end;

end.
