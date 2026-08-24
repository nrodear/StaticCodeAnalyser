unit uProfileViewer;

// Modaler Read-Only-Betrachter fuer die Regelsatz-Profile (Stufe 1).
//
// Zeigt links die Profile aus rules/sca-rules.json und rechts, welche
// Detektoren das gewaehlte Profil einschliesst - Regel-ID, Name,
// Severity, Typ und die Detektor-Unit. Bis hierher war der Profilname
// im Combo der Filterzeile das einzige, was der Anwender ueber ein
// Profil zu sehen bekam; WELCHE Regeln dahinterstehen, stand nur in der
// JSON. Genau diese Frage beantwortet dieses Fenster.
//
// Bewusst ohne .dfm, wie uDfmTextViewer daneben: das Fenster wird zur
// Laufzeit komponiert. So aendert sich am Projekt-Layout nichts ausser
// einem uses-Eintrag, und das Fenster hat keine eigene DFM-Decke, die
// mit dem Haupt-Layout driften koennte.
//
// STUFE 2 (noch nicht gebaut): eigene Profile anlegen. Die eingebauten
// bleiben dann unveraenderlich - sie kommen aus dem ausgelieferten
// Katalog und werden bei jedem Update ueberschrieben. Ein eigenes Profil
// gehoert deshalb NICHT in rules/sca-rules.json, sondern in eine eigene
// Datei neben analyser.ini. Die Ankerpunkte dafuer sind unten mit
// "Stufe 2" markiert; BuildRuleList ist bereits so geschnitten, dass es
// eine Kind-Menge beliebiger Herkunft entgegennimmt.

interface

// Einziger Einstiegspunkt. Zeigt das Fenster modal.
procedure ShowProfileViewer;

implementation

// noinspection-file LongMethod, TooLongLine, UnsortedUses
// Runtime-UI-Komposition: der Aufbau EINES Fensters gehoert in EINE
// Methode, sonst zerfaellt die Lesereihenfolge der Layout-Zeilen.

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.Generics.Defaults,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls,
  Winapi.Windows,
  uSCAConsts,       // TFindingKind, TFindingKinds, TLeakSeverity, TFindingType
  uRuleCatalog,     // TRuleCatalog.ProfileNames / GetProfile / GetRule
  uLocalization;    // _() und CurrentLanguage

type
  TProfileViewerForm = class(TForm)
  strict private
    FLstProfiles : TListBox;
    FLvRules     : TListView;
    FLblInfo     : TLabel;
    // Rohe Profilnamen, index-gleich zu FLstProfiles.Items. Die Anzeige
    // haengt die Regelzahl an ("default (189)"), der Katalog-Zugriff
    // braucht aber den unveraenderten Namen - deshalb zwei Listen und
    // nicht ein Parsen der Anzeigezeile zurueck.
    FNames       : TStringList;
    procedure BuildUi;
    procedure LoadProfiles;
    procedure ShowRulesOf(const AProfile: string);
    procedure ProfileSelected(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  public
    constructor CreateNew(AOwner: TComponent; Dummy: Integer = 0); override;
    destructor Destroy; override;
  end;

// ---------------------------------------------------------------------
// Anzeigetexte fuer die beiden Enums.
//
// TLeakFinding.SeverityText/TypeText in uMethodd12 liefern dasselbe,
// haengen aber an einem Befund - hier gibt es keinen Befund, nur eine
// Regel. Die msgids sind absichtlich WORTGLEICH mit denen dort, damit
// beide Stellen aus demselben .po-Eintrag bedient werden und die
// Uebersetzung nicht zweimal gepflegt werden muss.
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

// ---------------------------------------------------------------------
// Die Regeln einer Kind-Menge einsammeln, nach Regel-ID sortiert.
//
// Nimmt eine MENGE entgegen, kein Profilnamen - damit Stufe 2 dieselbe
// Funktion fuer ein selbst zusammengestelltes Profil nutzen kann, ohne
// dass es dafuer schon einen Namen im Katalog geben muesste.
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

{ TProfileViewerForm }

constructor TProfileViewerForm.CreateNew(AOwner: TComponent; Dummy: Integer);
begin
  inherited CreateNew(AOwner, Dummy);
  FNames := TStringList.Create;
  BuildUi;
  LoadProfiles;
end;

destructor TProfileViewerForm.Destroy;
begin
  FNames.Free;
  inherited;
end;

procedure TProfileViewerForm.BuildUi;
var
  Bottom : TPanel;
  BtnOk  : TButton;
  Col    : TListColumn;
  Split  : TSplitter;
begin
  Caption     := _('Rule-set profiles');
  Position    := poMainFormCenter;
  BorderStyle := bsSizeable;
  Width       := 1000;
  Height      := 640;
  Constraints.MinWidth  := 640;
  Constraints.MinHeight := 400;
  KeyPreview  := True;
  OnKeyDown   := FormKeyDown;

  // ---- Fusszeile zuerst: alClient darueber fuellt dann den Rest ----
  Bottom := TPanel.Create(Self);
  Bottom.Parent     := Self;
  Bottom.Align      := alBottom;
  Bottom.Height     := 44;
  Bottom.BevelOuter := bvNone;

  BtnOk := TButton.Create(Self);
  BtnOk.Parent  := Bottom;
  BtnOk.Caption := _('Close');
  BtnOk.Width   := 100;
  BtnOk.Height  := 28;
  BtnOk.Left    := Bottom.Width - BtnOk.Width - 12;
  BtnOk.Top     := 8;
  BtnOk.Anchors := [akTop, akRight];
  BtnOk.Cancel  := True;
  BtnOk.OnClick := CloseClick;

  FLblInfo := TLabel.Create(Self);
  FLblInfo.Parent   := Bottom;
  FLblInfo.Left     := 12;
  FLblInfo.Top      := 14;
  FLblInfo.Anchors  := [akLeft, akTop, akRight];
  FLblInfo.Caption  := '';

  // ---- links die Profile ----
  FLstProfiles := TListBox.Create(Self);
  FLstProfiles.Parent   := Self;
  FLstProfiles.Align    := alLeft;
  FLstProfiles.Width    := 230;
  FLstProfiles.OnClick  := ProfileSelected;

  Split := TSplitter.Create(Self);
  Split.Parent   := Self;
  Split.Align    := alLeft;
  Split.Left     := FLstProfiles.Width + 1;
  Split.Width    := 5;
  Split.MinSize  := 140;

  // ---- rechts die Regeln des gewaehlten Profils ----
  FLvRules := TListView.Create(Self);
  FLvRules.Parent     := Self;
  FLvRules.Align      := alClient;
  FLvRules.ViewStyle  := vsReport;
  FLvRules.ReadOnly   := True;
  FLvRules.RowSelect  := True;
  FLvRules.GridLines  := True;

  Col := FLvRules.Columns.Add; Col.Caption := _('ID');            Col.Width := 80;
  // Der Kind-Token ist das, was in einem Profil in rules/sca-rules.json
  // steht - nicht die SCA-ID. Ohne diese Spalte muesste man fuer ein
  // eigenes Profil in DETECTORS.md nachschlagen; siehe docs/profiles.md.
  Col := FLvRules.Columns.Add; Col.Caption := _('Kind (profile token)'); Col.Width := 190;
  Col := FLvRules.Columns.Add; Col.Caption := _('Rule');          Col.Width := 330;
  Col := FLvRules.Columns.Add; Col.Caption := _('Severity');      Col.Width := 90;
  Col := FLvRules.Columns.Add; Col.Caption := _('Type');          Col.Width := 130;
  Col := FLvRules.Columns.Add; Col.Caption := _('Detector unit'); Col.Width := 220;
end;

procedure TProfileViewerForm.LoadProfiles;
var
  Names : TArray<string>;
  Name  : string;
  Kinds : TFindingKinds;
  Cnt   : Integer;
  K     : TFindingKind;
begin
  Names := TRuleCatalog.ProfileNames;
  FNames.Clear;
  FLstProfiles.Items.BeginUpdate;
  try
    FLstProfiles.Items.Clear;
    for Name in Names do
    begin
      // Regelzahl gleich mit anzeigen: der Vergleich zweier Profile ist
      // der haeufigste Grund, dieses Fenster zu oeffnen, und dafuer ist
      // die Groesse die erste Kennzahl.
      Kinds := TRuleCatalog.GetProfile(Name);
      Cnt := 0;
      for K := Low(TFindingKind) to High(TFindingKind) do
        if K in Kinds then
          Inc(Cnt);
      FNames.Add(Name);
      FLstProfiles.Items.Add(Format('%s  (%d)', [Name, Cnt]));
    end;
  finally
    FLstProfiles.Items.EndUpdate;
  end;

  if FLstProfiles.Items.Count > 0 then
  begin
    FLstProfiles.ItemIndex := 0;
    ShowRulesOf(FNames[0]);
  end
  else
    // Kein Profil: der Katalog war nicht ladbar. Das ist kein Absturz,
    // aber es muss sichtbar sein - sonst steht der Anwender vor einem
    // leeren Fenster ohne Erklaerung.
    FLblInfo.Caption := _('No rule catalogue found - profiles unavailable.');
end;

procedure TProfileViewerForm.ShowRulesOf(const AProfile: string);
var
  Rules : TList<TRuleMeta>;
  M     : TRuleMeta;
  It    : TListItem;
begin
  Rules := TList<TRuleMeta>.Create;
  try
    BuildRuleList(TRuleCatalog.GetProfile(AProfile), Rules);

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
        It.SubItems.Add(M.DetectorUnit);
      end;
    finally
      FLvRules.Items.EndUpdate;
    end;

    FLblInfo.Caption := Format(
      _('Profile "%s": %d of %d rules active. Built-in profiles come from rules/sca-rules.json and are read-only.'),
      [AProfile, Rules.Count, TRuleCatalog.Count]);
  finally
    Rules.Free;
  end;
end;

procedure TProfileViewerForm.ProfileSelected(Sender: TObject);
var
  Idx : Integer;
begin
  Idx := FLstProfiles.ItemIndex;
  if (Idx >= 0) and (Idx < FNames.Count) then
    ShowRulesOf(FNames[Idx]);
end;

procedure TProfileViewerForm.CloseClick(Sender: TObject);
begin
  Close;
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

procedure ShowProfileViewer;
var
  Dlg : TProfileViewerForm;
begin
  Dlg := TProfileViewerForm.CreateNew(nil);
  try
    Dlg.ShowModal;
  finally
    Dlg.Free;
  end;
end;

end.
