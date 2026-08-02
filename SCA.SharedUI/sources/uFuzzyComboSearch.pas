unit uFuzzyComboSearch;

// Macht eine TComboBox tippbar und filtert ihre Liste per Fuzzy-Suche.
//
// WARUM: die Severity-/Filter-Combo traegt nicht drei Eintraege, sondern
// rund 200 - 'All', die drei Sammel-Eintraege und dazu JEDE Regel als
// 'SCAxxx  KindName', gruppiert durch Sektions-Trenner. Darin zu scrollen
// ist die falsche Bedienung; wer 'sqlinj' tippt, will SCA003 sehen.
//
// ANSATZ: der Helfer haengt sich an eine bestehende Combo, uebernimmt
// deren Ereignisse und legt einen Schnappschuss ihrer Eintraege an
// (Text UND Objects-Tag). Beim Tippen wird die sichtbare Liste auf die
// Treffer reduziert, bei der Auswahl die volle Liste wiederhergestellt.
//
// DIE HOSTS BLEIBEN UNVERAENDERT: beide lesen ihre Auswahl ueber
// Items.Objects[ItemIndex], nicht ueber den Index. Weil AddObject den Tag
// mitfuehrt, stimmt er auch in der gefilterten Liste. Der OnChange des
// Hosts wird NUR bei einer echten Auswahl gerufen, nie beim Tippen -
// sonst wuerde jede Taste einen Filterlauf ueber alle Befunde ausloesen.
//
// Ohne Eingabe verhaelt sich die Combo exakt wie vorher.

interface

uses
  System.Classes, System.SysUtils, System.Generics.Collections,
  System.Generics.Defaults,          // TComparer fuer die Treffer-Sortierung
  Vcl.StdCtrls, Vcl.Controls, Winapi.Windows, Winapi.Messages;

type
  // Ein Eintrag des Schnappschusses.
  TFuzzyComboEntry = record
    Display : string;
    Tag     : NativeInt;
  end;

  TFuzzyComboSearch = class(TComponent)
  private
    FCombo      : TComboBox;
    FAll        : TList<TFuzzyComboEntry>;
    FHostChange : TNotifyEvent;
    FHostSelect : TNotifyEvent;
    FHostKeyUp  : TKeyEvent;
    FUpdating   : Boolean;   // Reentranz-Sperre waehrend wir Items umbauen
    FIsFiltering: Boolean;   // True solange eine Eingabe die Liste reduziert
    FLastQuery  : string;
    procedure ComboChange(Sender: TObject);
    procedure ComboSelect(Sender: TObject);
    procedure ComboKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ApplyQuery(const AQuery: string);
    procedure FillFromSnapshot;
    procedure RestoreAll;
    procedure RestoreAllAndSelect(ATag: NativeInt);
    function  SelectedTag(var ATag: NativeInt): Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    // Haengt sich an ACombo. Die Combo wird dabei auf csDropDown
    // umgestellt - csDropDownList laesst keine Eingabe zu.
    procedure Attach(ACombo: TComboBox);
    // Nach jedem Umbau der Items durch den Host aufrufen (z.B. nach
    // RebuildFilterCombos). Ohne das filtert der Helfer gegen einen
    // veralteten Schnappschuss.
    procedure Resync;
    // True wenn gerade eine Eingabe die Liste reduziert - der Host kann
    // damit einen Filterlauf unterdruecken, falls er OnChange selbst
    // abgreift.
    property IsFiltering: Boolean read FIsFiltering;
  end;

// Fuzzy-Treffer: alle Zeichen von APattern kommen in AText in dieser
// Reihenfolge vor (nicht notwendig zusammenhaengend), Gross-/Kleinschreibung
// egal. AScore ist hoeher fuer zusammenhaengende Treffer und fuer Treffer
// am Wortanfang - damit 'sql' bei 'SQLInjection' vor 'MssqlHelper' landet.
function FuzzyMatch(const APattern, AText: string; var AScore: Integer): Boolean;

implementation

const
  SCORE_CONSECUTIVE = 8;   // direkt an den vorigen Treffer angeschlossen
  SCORE_WORD_START  = 6;   // Zeichen beginnt ein Wort (Anfang, nach Trenner)
  SCORE_CAMEL       = 4;   // Grossbuchstabe mitten im Wort (CamelCase-Grenze)
  PENALTY_GAP       = 1;   // je uebersprungenem Zeichen
  SEPARATOR_TAG     = -1;  // Sektions-Trenner der Filterliste

function IsWordBoundary(const AText: string; AIndex: Integer): Boolean;
var
  P : Char;
begin
  if AIndex <= 1 then
  begin
    Result := True;
    Exit;
  end;
  P := AText[AIndex - 1];
  Result := CharInSet(P, [' ', '-', '_', '.', ':', '/', '\', '(', ')', '[', ']']);
end;

function IsCamelStart(const AText: string; AIndex: Integer): Boolean;
begin
  Result := (AIndex > 1)
        and CharInSet(AText[AIndex], ['A'..'Z'])
        and CharInSet(AText[AIndex - 1], ['a'..'z', '0'..'9']);
end;

function PositionBonus(const AText: string; AIndex: Integer): Integer;
// Wie wertvoll ist ein Treffer an dieser Stelle? Wortanfaenge und
// CamelCase-Grenzen sind das, wonach ein Mensch sucht.
begin
  if IsWordBoundary(AText, AIndex) then
  begin
    Result := SCORE_WORD_START;
  end
  else if IsCamelStart(AText, AIndex) then
  begin
    Result := SCORE_CAMEL;
  end
  else
  begin
    Result := 0;
  end;
end;

function FuzzyMatch(const APattern, AText: string; var AScore: Integer): Boolean;
var
  PatPos, TxtPos, LastHit : Integer;
  PL, TL                  : string;
begin
  AScore := 0;
  if APattern = '' then
  begin
    Result := True;
    Exit;
  end;
  if AText = '' then
  begin
    Result := False;
    Exit;
  end;

  PL := LowerCase(APattern);
  TL := LowerCase(AText);

  PatPos  := 1;
  LastHit := 0;
  for TxtPos := 1 to Length(TL) do
  begin
    if PatPos > Length(PL) then Break;
    if TL[TxtPos] <> PL[PatPos] then Continue;

    if LastHit = TxtPos - 1 then
    begin
      Inc(AScore, SCORE_CONSECUTIVE);
    end
    else if LastHit > 0 then
    begin
      Dec(AScore, (TxtPos - LastHit - 1) * PENALTY_GAP);
    end;

    Inc(AScore, PositionBonus(AText, TxtPos));
    LastHit := TxtPos;
    Inc(PatPos);
  end;

  Result := PatPos > Length(PL);
  if not Result then
  begin
    AScore := 0;
  end
  else if AScore < 0 then
  begin
    AScore := 0;
  end;
end;

{ TFuzzyComboSearch }

constructor TFuzzyComboSearch.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FAll := TList<TFuzzyComboEntry>.Create;
end;

destructor TFuzzyComboSearch.Destroy;
begin
  // Ereignisse zurueckgeben, falls die Combo uns ueberlebt (der Host
  // besitzt sie, nicht wir).
  if Assigned(FCombo) then
  begin
    FCombo.OnChange := FHostChange;
    FCombo.OnSelect := FHostSelect;
    FCombo.OnKeyUp  := FHostKeyUp;
  end;
  FAll.Free;
  inherited;
end;

procedure TFuzzyComboSearch.Attach(ACombo: TComboBox);
begin
  if not Assigned(ACombo) then Exit;
  FCombo := ACombo;
  FHostChange := ACombo.OnChange;
  FHostSelect := ACombo.OnSelect;
  FHostKeyUp  := ACombo.OnKeyUp;

  // csDropDownList kann nicht tippen. csDropDown erlaubt Eingabe; die
  // Auswahl selbst laeuft weiterhin ueber die Liste.
  ACombo.Style        := csDropDown;
  ACombo.AutoComplete := False;   // wuerde gegen unsere Filterung arbeiten
  ACombo.OnChange     := ComboChange;
  ACombo.OnSelect     := ComboSelect;
  ACombo.OnKeyUp      := ComboKeyUp;

  Resync;
end;

procedure TFuzzyComboSearch.Resync;
var
  i : Integer;
  E : TFuzzyComboEntry;
begin
  if not Assigned(FCombo) then Exit;
  if FUpdating then Exit;
  FAll.Clear;
  for i := 0 to FCombo.Items.Count - 1 do
  begin
    E.Display := FCombo.Items[i];
    E.Tag     := NativeInt(FCombo.Items.Objects[i]);
    FAll.Add(E);
  end;
  FIsFiltering := False;
  FLastQuery := '';
end;

function TFuzzyComboSearch.SelectedTag(var ATag: NativeInt): Boolean;
begin
  ATag := 0;
  Result := Assigned(FCombo) and (FCombo.ItemIndex >= 0);
  if Result then
  begin
    ATag := NativeInt(FCombo.Items.Objects[FCombo.ItemIndex]);
  end;
end;

procedure TFuzzyComboSearch.ApplyQuery(const AQuery: string);
// Reduziert die sichtbare Liste auf die Fuzzy-Treffer, nach Score
// sortiert. Sektions-Trenner fallen dabei weg - sie sind keine waehlbaren
// Ziele und wuerden die Trefferliste nur verduennen.
var
  Hits   : TList<TPair<Integer, Integer>>;   // Score, Index in FAll
  i, Sc  : Integer;
begin
  if not Assigned(FCombo) then Exit;
  Hits := TList<TPair<Integer, Integer>>.Create;
  try
    Sc := 0;
    for i := 0 to FAll.Count - 1 do
    begin
      if FAll[i].Tag = SEPARATOR_TAG then Continue;
      if not FuzzyMatch(AQuery, FAll[i].Display, Sc) then Continue;
      Hits.Add(TPair<Integer, Integer>.Create(Sc, i));
    end;

    // Bester Treffer zuerst; bei gleichem Score die urspruengliche
    // Reihenfolge, damit die Liste zwischen Tastendruecken stabil bleibt.
    Hits.Sort(TComparer<TPair<Integer, Integer>>.Construct(
      function(const A, B: TPair<Integer, Integer>): Integer
      begin
        Result := B.Key - A.Key;
        if Result = 0 then
        begin
          Result := A.Value - B.Value;
        end;
      end));

    FUpdating := True;
    try
      FCombo.Items.BeginUpdate;
      FCombo.Items.Clear;
      for i := 0 to Hits.Count - 1 do
      begin
        FCombo.Items.AddObject(FAll[Hits[i].Value].Display,
                               TObject(FAll[Hits[i].Value].Tag));
      end;
      FCombo.Items.EndUpdate;
    finally
      FUpdating := False;
    end;
  finally
    Hits.Free;
  end;
end;

procedure TFuzzyComboSearch.FillFromSnapshot;
// Volle Liste aus dem Schnappschuss zuruecklegen.
var
  i : Integer;
begin
  FCombo.Items.BeginUpdate;
  FCombo.Items.Clear;
  for i := 0 to FAll.Count - 1 do
  begin
    FCombo.Items.AddObject(FAll[i].Display, TObject(FAll[i].Tag));
  end;
  FCombo.Items.EndUpdate;
end;

procedure TFuzzyComboSearch.RestoreAll;
begin
  if not Assigned(FCombo) then Exit;
  FUpdating := True;
  try
    FillFromSnapshot;
  finally
    FUpdating := False;
  end;
  FIsFiltering := False;
  FLastQuery := '';
end;

procedure TFuzzyComboSearch.RestoreAllAndSelect(ATag: NativeInt);
// Auswahl ueber den TAG wiederherstellen, nicht ueber den Index - der
// verschiebt sich beim Zuruecklegen der vollen Liste.
var
  i : Integer;
begin
  if not Assigned(FCombo) then Exit;
  FUpdating := True;
  try
    FillFromSnapshot;
    for i := 0 to FCombo.Items.Count - 1 do
    begin
      if NativeInt(FCombo.Items.Objects[i]) = ATag then
      begin
        FCombo.ItemIndex := i;
        Break;
      end;
    end;
  finally
    FUpdating := False;
  end;
  FIsFiltering := False;
  FLastQuery := '';
end;

procedure TFuzzyComboSearch.ComboChange(Sender: TObject);
// Feuert beim Tippen UND bei Auswahl aus der Liste. Beim Tippen wird nur
// gefiltert - der OnChange des Hosts bleibt still, sonst laeuft mit jeder
// Taste ein voller Filterlauf ueber alle Befunde.
var
  Q : string;
begin
  if FUpdating then Exit;
  if not Assigned(FCombo) then Exit;

  Q := FCombo.Text;
  // Auswahl aus der Liste: der Text entspricht exakt einem Eintrag und
  // ItemIndex ist gesetzt -> als Auswahl behandeln, nicht als Eingabe.
  if (FCombo.ItemIndex >= 0)
     and SameText(FCombo.Items[FCombo.ItemIndex], Q) then
  begin
    ComboSelect(Sender);
    Exit;
  end;

  if Q = FLastQuery then Exit;
  FLastQuery := Q;
  FIsFiltering := Q <> '';

  if Q = '' then
  begin
    RestoreAll;
    Exit;
  end;

  ApplyQuery(Q);

  // Liste offen halten und den Cursor hinter der Eingabe lassen - sonst
  // springt er bei jedem Tastendruck an den Anfang.
  if FCombo.HandleAllocated then
  begin
    SendMessage(FCombo.Handle, CB_SHOWDROPDOWN, 1, 0);
    FCombo.SelStart  := Length(Q);
    FCombo.SelLength := 0;
  end;
end;

procedure TFuzzyComboSearch.ComboSelect(Sender: TObject);
// Echte Auswahl: volle Liste zuruecksetzen, Auswahl ueber den Tag
// wiederherstellen und erst DANN den Host benachrichtigen.
var
  Tag : NativeInt;
begin
  if FUpdating then Exit;
  if not Assigned(FCombo) then Exit;
  if SelectedTag(Tag) then
  begin
    RestoreAllAndSelect(Tag);
  end
  else
  begin
    RestoreAll;
  end;
  if Assigned(FHostSelect) then
  begin
    FHostSelect(FCombo);
  end;
  if Assigned(FHostChange) then
  begin
    FHostChange(FCombo);
  end;
end;

procedure TFuzzyComboSearch.ComboKeyUp(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Assigned(FCombo) and (Key = VK_ESCAPE) and FIsFiltering then
  begin
    // Escape verwirft die Eingabe und stellt den vorigen Zustand her.
    RestoreAll;
    Key := 0;
  end;
  if Assigned(FHostKeyUp) then
  begin
    FHostKeyUp(Sender, Key, Shift);
  end;
end;

end.
