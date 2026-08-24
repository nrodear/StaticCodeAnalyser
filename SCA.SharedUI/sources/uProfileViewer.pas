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
  // TAppTheme.ResolveSystemColors gegen den aktiven VCL-Style. Dieselbe
  // Schichtgrenze und dasselbe Muster wie StyleServicesProvider und
  // EditorBgProvider in uAnalyserTheme.
  //
  // Der Wirt setzt ihn nur fuer die Dauer des Aufrufs und nimmt ihn
  // danach zurueck. So kann die Closure nicht in entladenen Plugin-Code
  // zeigen - die Falle, vor der uAnalyserTheme bei seinen Providern
  // ausdruecklich warnt.
  TProfileViewerThemeProc = reference to procedure(AControl: TWinControl);

var
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
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.Generics.Defaults,
  // Vcl.Controls steht bereits im interface-uses (TWinControl im
  // Hook-Typ) - hier nicht noch einmal, sonst E2004.
  Vcl.Forms, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls,
  Vcl.Dialogs,
  Winapi.Windows,
  uSCAConsts,       // TFindingKind, TFindingKinds, KindName
  uRuleCatalog,     // Profile lesen UND eigene schreiben
  uLocalization;    // _() und CurrentLanguage

const
  // Alle Kinds als Menge. TRuleCatalog.AllKinds ist strict private, und
  // fuer diesen einen Ausdruck lohnt kein Aufreissen der Kapselung.
  ALL_KINDS = [Low(TFindingKind) .. High(TFindingKind)];

type
  TProfileViewerForm = class(TForm)
  strict private
    FLstProfiles : TListBox;
    FLvRules     : TListView;
    FLblInfo     : TLabel;
    FBtnCopy     : TButton;
    FBtnAdd      : TButton;
    FBtnRemove   : TButton;
    FBtnDelete   : TButton;
    FBtnSave     : TButton;
    // Rohe Profilnamen, index-gleich zu FLstProfiles.Items: die Anzeige
    // haengt Regelzahl und Herkunft an, der Katalog-Zugriff braucht den
    // unveraenderten Namen.
    FNames       : TStringList;
    // Kind je Zeile der Regelliste, index-gleich. Ueber TListItem.Data
    // ginge es auch, aber ein Pointer-Cast auf ein Enum ist genau die
    // Sorte Trick, die beim naechsten Umbau still bricht.
    FRowKinds    : TList<TFindingKind>;
    FCurrent     : string;          // gewaehltes Profil
    FKinds       : TFindingKinds;   // Arbeitsstand des gewaehlten Profils
    FIsOwn       : Boolean;         // eigenes (aenderbares) Profil?
    FDirty       : Boolean;         // ungespeicherte Aenderung
    FChanged     : Boolean;         // angelegt/geloescht -> Combo neu
    procedure BuildUi;
    procedure LoadProfiles(const APreferred: string);
    procedure ShowRulesOf(const AProfile: string);
    procedure RefreshRuleList;
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
function SeverityText(S: TLeakSeverity): string;
begin
  case S of
    lsError   : Result := _('Error');
    lsWarning : Result := _('Warning');
    lsHint    : Result := _('Hint');
  else
    Result := '';
  end;
end;

function TypeText(T: TFindingType): string;
begin
  case T of
    ftBug             : Result := _('Bug');
    ftCodeSmell       : Result := _('Code Smell');
    ftVulnerability   : Result := _('Vulnerability');
    ftSecurityHotspot : Result := _('Security Hotspot');
    ftCodeDuplication : Result := _('Code Duplication');
    ftFileError       : Result := _('Read Error');
  else
    Result := '';
  end;
end;

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
procedure BuildRuleList(const AKinds: TFindingKinds; ADest: TList<TRuleMeta>);
var
  K    : TFindingKind;
  Lang : string;
begin
  ADest.Clear;
  Lang := CurrentLanguage;
  for K := Low(TFindingKind) to High(TFindingKind) do
    if K in AKinds then
      ADest.Add(TRuleCatalog.GetRule(K, Lang));

  // Nach ID sortieren, nicht nach Kind-Ordinal: der Anwender sucht
  // "SCA047", und die Ordinal-Reihenfolge des Enums ist historisch
  // gewachsen, nicht numerisch.
  ADest.Sort(TComparer<TRuleMeta>.Construct(
    function(const A, B: TRuleMeta): Integer
    begin
      Result := CompareText(A.ID, B.ID);
    end));
end;

// ---------------------------------------------------------------------
// Auswahldialog "Regeln aufnehmen". Zeigt die Kandidaten mit Haken;
// Ergebnis True + APicked, wenn der Anwender mindestens eine waehlt.
// ---------------------------------------------------------------------
function PickRules(const ACandidates: TFindingKinds;
  out APicked: TFindingKinds): Boolean;
var
  Dlg    : TForm;
  Lv     : TListView;
  Bottom : TPanel;
  BtnOk  : TButton;
  BtnNo  : TButton;
  Rules  : TList<TRuleMeta>;
  Kinds  : TList<TFindingKind>;
  M      : TRuleMeta;
  It     : TListItem;
  Col    : TListColumn;
  i      : Integer;
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

  Rules := TList<TRuleMeta>.Create;
  Kinds := TList<TFindingKind>.Create;
  Dlg   := TForm.CreateNew(nil);
  try
    Dlg.Caption      := _('Add rules');
    Dlg.Position     := poMainFormCenter;
    // Gleiche Bauart wie das Profil-Fenster: feste Groesse, kein
    // Sizing-Rahmen. Die Spaltenbreiten stehen fest, also auch die
    // sinnvolle Fensterbreite.
    Dlg.BorderStyle  := bsDialog;
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

    Lv := TListView.Create(Dlg);
    Lv.Parent     := Dlg;
    Lv.Align      := alClient;
    Lv.ViewStyle  := vsReport;
    Lv.ReadOnly   := True;
    Lv.RowSelect  := True;
    Lv.GridLines  := True;
    Lv.Checkboxes := True;

    Col := Lv.Columns.Add; Col.Caption := _('ID');                   Col.Width := 80;
    Col := Lv.Columns.Add; Col.Caption := _('Kind (profile token)'); Col.Width := 190;
    Col := Lv.Columns.Add; Col.Caption := _('Rule');                 Col.Width := 340;
    Col := Lv.Columns.Add; Col.Caption := _('Severity');             Col.Width := 90;
    Col := Lv.Columns.Add; Col.Caption := _('Type');                 Col.Width := 130;

    BuildRuleList(ACandidates, Rules);
    Lv.Items.BeginUpdate;
    try
      for M in Rules do
      begin
        It := Lv.Items.Add;
        It.Caption := M.ID;
        It.SubItems.Add(KindName(M.Kind));
        It.SubItems.Add(M.Name);
        It.SubItems.Add(SeverityText(M.DefaultSeverity));
        It.SubItems.Add(TypeText(M.FindingType));
        Kinds.Add(M.Kind);
      end;
    finally
      Lv.Items.EndUpdate;
    end;

    if Assigned(ProfileViewerTheme) then
      ProfileViewerTheme(Dlg);

    if Dlg.ShowModal = mrOk then
    begin
      for i := 0 to Lv.Items.Count - 1 do
        if Lv.Items[i].Checked then
          Include(APicked, Kinds[i]);
      Result := APicked <> [];
    end;
  finally
    Dlg.Free;
    Kinds.Free;
    Rules.Free;
  end;
end;

{ TProfileViewerForm }

constructor TProfileViewerForm.CreateNew(AOwner: TComponent; Dummy: Integer);
begin
  inherited CreateNew(AOwner, Dummy);
  FNames    := TStringList.Create;
  FRowKinds := TList<TFindingKind>.Create;
  BuildUi;
  LoadProfiles('');
  // Erst jetzt: das Theme muss ueber FERTIGE Controls laufen, sonst
  // faerbt es die noch nicht erzeugten nicht ein.
  if Assigned(ProfileViewerTheme) then
    ProfileViewerTheme(Self);
end;

destructor TProfileViewerForm.Destroy;
begin
  FRowKinds.Free;
  FNames.Free;
  inherited;
end;

procedure TProfileViewerForm.BuildUi;
var
  Bottom : TPanel;
  Col    : TListColumn;
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
  Caption      := _('Rule-set profiles');
  Position     := poMainFormCenter;
  // bsDialog: kein Sizing-Rahmen, kein Maximieren-Knopf. Die Breite
  // ergibt sich aus den Spalten (80+190+360+90+130) plus Profilliste.
  BorderStyle  := bsDialog;
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
  FBtnRemove := MkButton(_('Remove rules'),   RemoveClick);
  FBtnAdd    := MkButton(_('Add rules...'),   AddClick);
  FBtnCopy   := MkButton(_('Copy...'),        CopyClick);

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

  // ---- rechts die Regeln des gewaehlten Profils ----
  FLvRules := TListView.Create(Self);
  FLvRules.Parent      := Self;
  FLvRules.Align       := alClient;
  FLvRules.ViewStyle   := vsReport;
  FLvRules.ReadOnly    := True;
  FLvRules.RowSelect   := True;
  FLvRules.GridLines   := True;
  FLvRules.MultiSelect := True;   // "Regeln entfernen" arbeitet auf der Auswahl

  Col := FLvRules.Columns.Add; Col.Caption := _('ID');                   Col.Width := 80;
  // Der Kind-Token ist das, was in einem Profil steht - nicht die
  // SCA-ID. Ohne diese Spalte muesste man fuer ein eigenes Profil in
  // DETECTORS.md nachschlagen; siehe docs/profiles.md.
  Col := FLvRules.Columns.Add; Col.Caption := _('Kind (profile token)'); Col.Width := 190;
  Col := FLvRules.Columns.Add; Col.Caption := _('Rule');                 Col.Width := 360;
  Col := FLvRules.Columns.Add; Col.Caption := _('Severity');             Col.Width := 90;
  Col := FLvRules.Columns.Add; Col.Caption := _('Type');                 Col.Width := 130;
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
var
  Rules : TList<TRuleMeta>;
  M     : TRuleMeta;
  It    : TListItem;
begin
  Rules := TList<TRuleMeta>.Create;
  try
    BuildRuleList(FKinds, Rules);
    FRowKinds.Clear;

    FLvRules.Items.BeginUpdate;
    try
      FLvRules.Items.Clear;
      for M in Rules do
      begin
        It := FLvRules.Items.Add;
        It.Caption := M.ID;
        It.SubItems.Add(KindName(M.Kind));
        It.SubItems.Add(M.Name);
        It.SubItems.Add(SeverityText(M.DefaultSeverity));
        It.SubItems.Add(TypeText(M.FindingType));
        FRowKinds.Add(M.Kind);
      end;
    finally
      FLvRules.Items.EndUpdate;
    end;

    if FIsOwn then
      FLblInfo.Caption := Format(
        _('Profile "%s": %d of %d rules. Your own profile, stored in %s'),
        [FCurrent, Rules.Count, TRuleCatalog.Count,
         TRuleCatalog.UserProfilesFilePath])
    else
      FLblInfo.Caption := Format(
        _('Profile "%s": %d of %d rules. Built-in and read-only - use "Copy..." for your own.'),
        [FCurrent, Rules.Count, TRuleCatalog.Count]);
  finally
    Rules.Free;
  end;
  UpdateButtons;
end;

procedure TProfileViewerForm.UpdateButtons;
var
  Has : Boolean;
begin
  Has := FLstProfiles.Items.Count > 0;
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
    Application.MessageBox(PChar(Err), PChar(_('Rule-set profiles')),
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
    PChar(_('Rule-set profiles')), MB_YESNOCANCEL or MB_ICONQUESTION);
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
  i      : Integer;
begin
  if not FIsOwn then Exit;

  // Erst einsammeln, dann entfernen: die Zeilenindizes verschieben sich,
  // sobald die Liste neu aufgebaut wird.
  Doomed := [];
  for i := 0 to FLvRules.Items.Count - 1 do
    if FLvRules.Items[i].Selected and (i < FRowKinds.Count) then
      Include(Doomed, FRowKinds[i]);

  if Doomed = [] then
  begin
    Application.MessageBox(PChar(_('Select the rules to remove first.')),
      PChar(_('Remove rules')), MB_OK or MB_ICONINFORMATION);
    Exit;
  end;
  if FKinds - Doomed = [] then
  begin
    Application.MessageBox(PChar(_('A profile without rules would find nothing.')),
      PChar(_('Remove rules')), MB_OK or MB_ICONWARNING);
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
       PChar(_('Rule-set profiles')),
       MB_YESNO or MB_ICONQUESTION) <> IDYES then Exit;

  if not TRuleCatalog.DeleteUserProfile(FCurrent, Err) then
  begin
    Application.MessageBox(PChar(Err), PChar(_('Rule-set profiles')),
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
