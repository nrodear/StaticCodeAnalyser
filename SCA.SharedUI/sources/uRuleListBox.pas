unit uRuleListBox;

// Eine Regelliste mit Kopfzeilen-Sortierung und Textfilter.
//
// Beide Fenster in uProfileViewer - die Regeln eines Profils und die
// Auswahl "Regeln aufnehmen ..." - zeigen dieselben fuenf Spalten,
// brauchen dieselbe Sortierung und denselben Filter, und beide muessen
// von einer Zeile auf ihr TFindingKind zurueckkommen (Entfernen bzw.
// Aufnehmen). Das steckt hier, damit es nicht zweimal gepflegt wird.
//
// EIGENE UNIT, nicht in uProfileViewer (Review 2026-08-25): dort lag die
// Klasse in der implementation und war von aussen unerreichbar - auch
// fuer Tests. Die Zusage "ein Haken ueberlebt das Filtern" bricht
// lautlos, sobald jemand Fill anfasst; ohne Test gibt es dafuer keinen
// Anker. Siehe uTestRuleListBox.
//
// BEWUSST NICHT ueber TListView.SortType/AutoSort: die VCL sortiert nur
// nach Caption, haengt die Items intern um und zerreisst damit die
// Kopplung Zeile -> Kind. Sortiert wird deshalb die DATENLISTE, und die
// Anzeige wird neu aufgebaut.

interface

uses
  System.SysUtils,   // TProc - steht im Typ von OnFilled
  System.Classes, System.Generics.Collections,
  Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls,
  uSCAConsts,       // TFindingKind, TFindingKinds
  uRuleCatalog;     // TRuleMeta

type
  TRuleListBox = class
  strict private
    FLv       : TListView;
    FEdt      : TEdit;
    FAll      : TList<TRuleMeta>;   // alles, in aktueller Sortierung
    FRowKind  : TList<TFindingKind>;// je ANGEZEIGTER Zeile das Kind
    FSortCol  : Integer;            // -1 = Reihenfolge aus BuildRuleList
    FSortDesc : Boolean;
    FOnFilled : TProc;
    // Angehakte Kinds, unabhaengig davon, ob ihre Zeile gerade sichtbar
    // ist. Fill baut die Items neu auf; ein Haken am TListItem ueberlebt
    // das nicht, dieser Satz schon.
    FChecked  : TFindingKinds;
    FFilling  : Boolean;   // Sperre gegen Rueckmeldungen aus Fill
    procedure ColumnClickHandler(Sender: TObject; Column: TListColumn);
    procedure ItemChangeHandler(Sender: TObject; Item: TListItem;
      Change: TItemChange);
    procedure FilterChangeHandler(Sender: TObject);
    procedure Sort;
    function  Matches(const R: TRuleMeta; const ANeedle: string): Boolean;
  public
    /// <summary>Baut Suchfeld und Liste in AParent auf. ACheckboxes fuer
    /// den Auswahldialog; das Profil-Fenster nimmt stattdessen
    /// Mehrfachauswahl.</summary>
    constructor Create(AOwner: TComponent; AParent: TWinControl;
      ACheckboxes: Boolean);
    destructor Destroy; override;

    /// <summary>Setzt die anzuzeigenden Regeln. Sortierung und Filter
    /// bleiben stehen - wer eine Spalte sortiert und dann das Profil
    /// wechselt, will nicht von vorn anfangen.</summary>
    procedure SetKinds(const AKinds: TFindingKinds);

    /// <summary>Baut die Anzeige aus der Datenliste neu auf: sortiert,
    /// gefiltert, Haken wiederhergestellt. Wird nach jeder Aenderung an
    /// Sortierung oder Filter selbst gerufen; oeffentlich, weil der Wirt
    /// nach einem Katalog-Neuladen ebenfalls auffrischen muss.</summary>
    procedure Fill;

    /// <summary>Setzt den Filtertext wie eine Eingabe im Suchfeld -
    /// einschliesslich Neuaufbau der Liste. Damit ist das Filterverhalten
    /// von aussen pruefbar, ohne Tastatureingaben zu simulieren.</summary>
    procedure SetFilter(const AText: string);

    /// <summary>Sortiert nach Spalte (0-basiert; -1 = Reihenfolge des
    /// Katalogs) und baut die Anzeige neu auf. Der Kopfzeilen-Klick
    /// benutzt denselben Weg.</summary>
    procedure SortBy(AColumn: Integer; ADescending: Boolean);

    /// <summary>Die Kinds der MARKIERTEN Zeilen. Nur sichtbare Zeilen
    /// koennen markiert sein - bei aktivem Filter also genau das, was man
    /// vor sich sieht.</summary>
    function SelectedKinds: TFindingKinds;

    /// <summary>Alle ANGEHAKTEN Kinds, auch die gerade weggefilterten.
    /// Ohne Haken (ACheckboxes = False) immer leer.</summary>
    function CheckedKinds: TFindingKinds;

    /// <summary>Anzahl der angehakten Kinds - fuer eine Statuszeile, die
    /// mitzaehlt, ohne die Menge selbst auszuwerten.</summary>
    function CheckedCount: Integer;

    /// <summary>Regeln des gesetzten Kind-Satzes insgesamt.</summary>
    function Total: Integer;

    /// <summary>Davon gerade angezeigt. Ohne Filter gleich Total.</summary>
    function Shown: Integer;

    /// <summary>Der wirksame Filtertext, getrimmt. Leer = kein Filter.</summary>
    function FilterText: string;
    /// <summary>Nach jedem Fuellen UND nach jedem Haken - fuer eine
    /// Statuszeile, die live mitzaehlt.</summary>
    property OnFilled: TProc read FOnFilled write FOnFilled;
  end;


/// <summary>Anzeigetext eines Schweregrads - dieselbe Schreibweise wie im
/// Regelkatalog und in der Doku.</summary>
function SeverityText(S: TLeakSeverity): string;
/// <summary>Anzeigetext eines Fundtyps (Sonar-Taxonomie).</summary>
function TypeText(T: TFindingType): string;
/// <summary>Sammelt die Metadaten der uebergebenen Kinds in ADest, in der
/// Reihenfolge des Katalogs. ADest wird geleert.</summary>
procedure BuildRuleList(const AKinds: TFindingKinds; ADest: TList<TRuleMeta>);

implementation

// noinspection-file BeginEndRequired, IfElseBegin, TooLongLine, UnsortedUses

uses
  System.StrUtils,              // ContainsText - Filter
  System.Generics.Defaults,     // TComparer - Sortierung
  uLocalization;                // _()

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
constructor TRuleListBox.Create(AOwner: TComponent; AParent: TWinControl;
  ACheckboxes: Boolean);
var
  Col : TListColumn;
begin
  inherited Create;
  FAll      := TList<TRuleMeta>.Create;
  FRowKind  := TList<TFindingKind>.Create;
  FSortCol  := -1;

  // Suchfeld ZUERST: alTop reserviert seine Hoehe, die Liste darunter
  // bekommt mit alClient den Rest.
  //
  // TextHint statt eines Labels daneben - das Feld erklaert sich selbst
  // und kostet keine Zeile Hoehe.
  FEdt := TEdit.Create(AOwner);
  FEdt.Parent   := AParent;
  FEdt.Align    := alTop;
  FEdt.TextHint := _('Search ID, kind, rule text, severity or type...');
  FEdt.OnChange := FilterChangeHandler;

  FLv := TListView.Create(AOwner);
  FLv.Parent      := AParent;
  FLv.Align       := alClient;
  FLv.ViewStyle   := vsReport;
  FLv.ReadOnly    := True;
  FLv.RowSelect   := True;
  FLv.GridLines   := True;
  FLv.Checkboxes  := ACheckboxes;
  FLv.MultiSelect := not ACheckboxes;
  FLv.ColumnClick := True;
  FLv.OnColumnClick := ColumnClickHandler;
  FLv.OnChange      := ItemChangeHandler;

  Col := FLv.Columns.Add; Col.Caption := _('ID');                   Col.Width := 80;
  // Der Kind-Token ist das, was in einem Profil steht - nicht die
  // SCA-ID. Ohne diese Spalte muesste man fuer ein eigenes Profil in
  // DETECTORS.md nachschlagen; siehe docs/profiles.md.
  Col := FLv.Columns.Add; Col.Caption := _('Kind (profile token)'); Col.Width := 190;
  Col := FLv.Columns.Add; Col.Caption := _('Rule');                 Col.Width := 350;
  Col := FLv.Columns.Add; Col.Caption := _('Severity');             Col.Width := 90;
  Col := FLv.Columns.Add; Col.Caption := _('Type');                 Col.Width := 130;
end;

destructor TRuleListBox.Destroy;
// Die Steuerelemente gehoeren AOwner, nicht uns - freigeben tut sie das
// Fenster. Die Ereignisse zeigen danach aber auf ein totes Objekt, und
// ein TListView feuert beim Abbau seiner Items durchaus noch OnChange.
// Beide Aufrufer geben diese Liste VOR ihrem Fenster frei; deshalb
// leben FLv und FEdt hier noch und die Zeilen sind sicher.
begin
  FLv.OnColumnClick := nil;
  FLv.OnChange      := nil;
  FEdt.OnChange     := nil;
  FRowKind.Free;
  FAll.Free;
  inherited;
end;

function TRuleListBox.Total: Integer;
begin
  Result := FAll.Count;
end;

function TRuleListBox.Shown: Integer;
begin
  Result := FRowKind.Count;
end;

function TRuleListBox.FilterText: string;
begin
  Result := Trim(FEdt.Text);
end;

procedure TRuleListBox.SetKinds(const AKinds: TFindingKinds);
begin
  BuildRuleList(AKinds, FAll);
  Sort;
  Fill;
end;

procedure TRuleListBox.Sort;
// Zweiter Schluessel ist immer die ID. Ohne ihn waere die Reihenfolge
// innerhalb einer Severity oder eines Typs zufaellig und aenderte sich
// bei jedem Aufbau - eine Liste, die bei gleichem Inhalt anders
// aussieht, ist unbrauchbar.
var
  Spalte     : Integer;
  Absteigend : Boolean;
begin
  if FSortCol < 0 then Exit;
  Spalte     := FSortCol;
  Absteigend := FSortDesc;
  FAll.Sort(TComparer<TRuleMeta>.Construct(
    function(const A, B: TRuleMeta): Integer
    begin
      case Spalte of
        1: Result := CompareText(KindName(A.Kind), KindName(B.Kind));
        2: Result := CompareText(A.Name, B.Name);
        // Severity und Typ nach ihrer ORDNUNG, nicht alphabetisch:
        // Error vor Warning vor Hint ist die erwartete Reihenfolge -
        // alphabetisch kaeme Error, Hint, Warning.
        3: Result := Ord(A.DefaultSeverity) - Ord(B.DefaultSeverity);
        4: Result := Ord(A.FindingType)     - Ord(B.FindingType);
      else
        Result := 0;   // Spalte 0 faellt auf die ID zurueck
      end;
      if Result = 0 then
        Result := CompareText(A.ID, B.ID);
      if Absteigend then
        Result := -Result;
    end));
end;

function TRuleListBox.Matches(const R: TRuleMeta; const ANeedle: string): Boolean;
// Sucht in allem, was in der Zeile SICHTBAR ist. Wer "SCA047" tippt,
// meint die ID; wer "Dfm" tippt, den Kind-Token; wer "Bug" tippt, den
// Typ. Ein Feld fuer alles ist hier richtig - die Zeile hat nur fuenf
// kurze Spalten, und getrennte Filter je Spalte waeren mehr Bedienung
// als Nutzen.
begin
  Result := ContainsText(R.ID, ANeedle)
         or ContainsText(KindName(R.Kind), ANeedle)
         or ContainsText(R.Name, ANeedle)
         or ContainsText(SeverityText(R.DefaultSeverity), ANeedle)
         or ContainsText(TypeText(R.FindingType), ANeedle);
end;

procedure TRuleListBox.Fill;
var
  M     : TRuleMeta;
  It    : TListItem;
  Suche : string;
begin
  Suche := FilterText;
  FRowKind.Clear;
  // Sperre, solange wir selbst Haken setzen - sonst meldet OnChange
  // jeden davon als Benutzeraktion zurueck und FChecked kaeme
  // durcheinander.
  FFilling := True;
  FLv.Items.BeginUpdate;
  try
    FLv.Items.Clear;
    for M in FAll do
    begin
      if (Suche <> '') and not Matches(M, Suche) then Continue;
      It := FLv.Items.Add;
      It.Caption := M.ID;
      It.SubItems.Add(KindName(M.Kind));
      It.SubItems.Add(M.Name);
      It.SubItems.Add(SeverityText(M.DefaultSeverity));
      It.SubItems.Add(TypeText(M.FindingType));
      if FLv.Checkboxes then
        It.Checked := M.Kind in FChecked;
      FRowKind.Add(M.Kind);
    end;
  finally
    FLv.Items.EndUpdate;
    FFilling := False;
  end;
  if Assigned(FOnFilled) then FOnFilled;
end;

procedure TRuleListBox.ItemChangeHandler(Sender: TObject; Item: TListItem;
  Change: TItemChange);
// ctState feuert auch beim Setzen des Hakens. Nur dann interessiert es
// uns - Auswahlwechsel laufen ueber denselben Weg.
var
  Idx : Integer;
begin
  if FFilling or not FLv.Checkboxes then Exit;
  if Change <> ctState then Exit;
  if not Assigned(Item) then Exit;
  Idx := Item.Index;
  if (Idx < 0) or (Idx >= FRowKind.Count) then Exit;
  if Item.Checked then
    Include(FChecked, FRowKind[Idx])
  else
    Exclude(FChecked, FRowKind[Idx]);
  if Assigned(FOnFilled) then FOnFilled;
end;

procedure TRuleListBox.FilterChangeHandler(Sender: TObject);
begin
  Fill;
end;

procedure TRuleListBox.SetFilter(const AText: string);
begin
  // Ueber die Text-Eigenschaft, nicht ueber ein eigenes Feld: OnChange
  // loest den Neuaufbau aus, und das Suchfeld zeigt danach dasselbe wie
  // die Liste. Ein zweiter Speicherort waere eine zweite Wahrheit.
  FEdt.Text := AText;
end;

procedure TRuleListBox.SortBy(AColumn: Integer; ADescending: Boolean);
begin
  FSortCol  := AColumn;
  FSortDesc := ADescending;
  Sort;
  Fill;
end;

procedure TRuleListBox.ColumnClickHandler(Sender: TObject; Column: TListColumn);
// Erneuter Klick auf dieselbe Spalte dreht die Richtung um.
begin
  if Column.Index = FSortCol then
    SortBy(FSortCol, not FSortDesc)
  else
    SortBy(Column.Index, False);
end;

function TRuleListBox.SelectedKinds: TFindingKinds;
var
  i : Integer;
begin
  Result := [];
  for i := 0 to FLv.Items.Count - 1 do
    if FLv.Items[i].Selected and (i < FRowKind.Count) then
      Include(Result, FRowKind[i]);
end;

function TRuleListBox.CheckedCount: Integer;
var
  K : TFindingKind;
begin
  Result := 0;
  for K := Low(TFindingKind) to High(TFindingKind) do
    if K in FChecked then
      Inc(Result);
end;

function TRuleListBox.CheckedKinds: TFindingKinds;
// Liefert ALLE angehakten Kinds, auch die gerade weggefilterten.
//
// Das ist der Grund fuer FChecked: Fill baut die Items neu auf, ein
// Haken an einem TListItem ueberlebt das nicht. Wer nach "Dfm" filtert,
// drei Regeln ankreuzt, dann nach "Leak" filtert und zwei weitere
// ankreuzt, erwartet fuenf - nicht zwei.
begin
  Result := FChecked;
end;

end.
