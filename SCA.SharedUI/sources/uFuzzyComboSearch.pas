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
  Vcl.StdCtrls, Vcl.Controls, Vcl.ExtCtrls,
  Winapi.Windows, Winapi.Messages;

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
    FHostCloseUp: TNotifyEvent;
    FHostExit   : TNotifyEvent;
    // Auswahl, die beim Blaettern entsteht, aber noch NICHT an den Host
    // gemeldet ist. Committed wird erst beim Zuklappen - siehe ComboSelect.
    FPendingTag : NativeInt;
    FHasPending : Boolean;
    // Zuletzt an den Host gemeldeter Tag. Verhindert, dass ein Zuklappen
    // ohne echte Aenderung einen Filterlauf ausloest.
    FCommitted  : NativeInt;
    FUpdating   : Boolean;   // Reentranz-Sperre waehrend wir Items umbauen
    FIsFiltering: Boolean;   // True solange eine Eingabe die Liste reduziert
    FLastQuery  : string;
    FPending    : string;    // zuletzt getippte, noch nicht angewandte Eingabe
    FTimer      : TTimer;    // Entprellung - siehe TimerTick
    procedure TimerTick(Sender: TObject);
    function  IsListDropped: Boolean;
    procedure SetListDropped(AOpen: Boolean);
    procedure ComboChange(Sender: TObject);
    procedure ComboSelect(Sender: TObject);
    procedure ComboCloseUp(Sender: TObject);
    procedure ComboExit(Sender: TObject);
    procedure CommitSelection;
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
    // veralteten Schnappschuss. Uebernimmt ausserdem die aktuelle
    // Auswahl als Commit-Stand - das Tag-Gate in CommitSelection misst
    // sonst gegen die Auswahl von VOR dem Umbau und verschluckt deren
    // erste Wieder-Auswahl.
    procedure Resync;
    // Entprellung ueberspringen und sofort filtern. Fuer Tests - im
    // Betrieb macht das der Timer.
    procedure FilterNow;
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

uses
  uLocalization;   // _() - die beiden Dropdown-Hinweise sprachen hart deutsch

const
  SCORE_CONSECUTIVE = 8;   // direkt an den vorigen Treffer angeschlossen
  SCORE_WORD_START  = 6;   // Zeichen beginnt ein Wort (Anfang, nach Trenner)
  SCORE_CAMEL       = 4;   // Grossbuchstabe mitten im Wort (CamelCase-Grenze)
  PENALTY_GAP       = 1;   // je uebersprungenem Zeichen
  SEPARATOR_TAG     = -1;  // Sektions-Trenner der Filterliste
  // Entprellung: erst wenn der Nutzer kurz innehaelt, wird gefiltert.
  // Ohne das wurde bei JEDEM Tastendruck die komplette Liste (rund 200
  // Eintraege = 200 Fenster-Nachrichten) neu aufgebaut - spuerbar traege.
  //
  // ZUR CURSOR-FRAGE, in zwei Stufen geklaert:
  //
  // (1) Dass der Zeiger beim Tippen VERSCHWINDET, ist kein Fehler: das
  //     ist Windows' "Zeiger beim Schreiben ausblenden"
  //     (SPI_SETMOUSEVANISH, per Default an). Die Funktion sitzt IM
  //     USER32-EDIT-Control - csDropDownList hat gar kein Edit-Kind,
  //     csDropDown erzeugt eines. Jedes Windows-Textfeld verhaelt sich
  //     so, auch die Pfad-Combo und das Such-Feld daneben. Nicht
  //     wegprogrammieren: ShowCursor(TRUE) im Key-Handler wuerde den
  //     thread-weiten Show-Count lecken.
  //
  // (2) Dass er bei MAUSBEWEGUNG nicht zurueckkam, war sehr wohl unsere
  //     Schuld - siehe die Begruendung in TimerTick. Windows stellt den
  //     Zeiger bei der naechsten Bewegung wieder her; ein offenes
  //     Dropdown, dem man die Eintraege darunter wegbaut, verschluckt
  //     genau das.
  DEBOUNCE_MS       = 160;
  // Mehr Treffer als das liest ohnehin niemand ab, und jeder weitere
  // kostet eine Fenster-Nachricht beim Aufbau. Wird gedeckelt, sagt die
  // letzte Zeile das ausdruecklich - stillschweigend abschneiden waere
  // schlimmer als langsam sein.
  MAX_HITS          = 50;

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
  FTimer := TTimer.Create(Self);
  FTimer.Enabled  := False;
  FTimer.Interval := DEBOUNCE_MS;
  FTimer.OnTimer  := TimerTick;
end;

destructor TFuzzyComboSearch.Destroy;
begin
  // Ereignisse zurueckgeben, falls die Combo uns ueberlebt (der Host
  // besitzt sie, nicht wir).
  if Assigned(FTimer) then
  begin
    FTimer.Enabled := False;
  end;
  if Assigned(FCombo) then
  begin
    FCombo.OnChange  := FHostChange;
    FCombo.OnSelect  := FHostSelect;
    FCombo.OnCloseUp := FHostCloseUp;
    FCombo.OnExit    := FHostExit;
    FCombo.OnKeyUp   := FHostKeyUp;
  end;
  FAll.Free;
  inherited;
end;

procedure TFuzzyComboSearch.Attach(ACombo: TComboBox);
begin
  if not Assigned(ACombo) then Exit;
  FCombo := ACombo;
  FHostChange  := ACombo.OnChange;
  FHostSelect  := ACombo.OnSelect;
  FHostKeyUp   := ACombo.OnKeyUp;
  FHostCloseUp := ACombo.OnCloseUp;
  FHostExit    := ACombo.OnExit;

  // csDropDownList kann nicht tippen. csDropDown erlaubt Eingabe; die
  // Auswahl selbst laeuft weiterhin ueber die Liste.
  ACombo.Style        := csDropDown;
  ACombo.AutoComplete := False;   // wuerde gegen unsere Filterung arbeiten
  ACombo.OnChange     := ComboChange;
  ACombo.OnSelect     := ComboSelect;
  ACombo.OnCloseUp    := ComboCloseUp;
  ACombo.OnExit       := ComboExit;
  ACombo.OnKeyUp      := ComboKeyUp;

  // Commit-Gedaechtnis und Schnappschuss zieht Resync aus dem
  // Ist-Zustand der Combo - Attach ist nur der Sonderfall "erster Sync".
  Resync;
end;

procedure TFuzzyComboSearch.FilterNow;
begin
  FPending := '';
  if Assigned(FCombo) then
  begin
    FPending := FCombo.Text;
  end;
  FLastQuery := '';          // Gleichheits-Kurzschluss in TimerTick umgehen
  TimerTick(nil);
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
  // Der Umbau durch den Host ist auch ein neuer AUSWAHL-Stand: das
  // Commit-Gedaechtnis muss der Anzeige folgen, sonst verschluckt das
  // Tag-Gate in CommitSelection die erste Wieder-Auswahl des zuletzt
  // gemeldeten Eintrags. Genau so trat es auf (2026-08-12): der Scan
  // setzt die Combo auf 'All' zurueck, der Nutzer waehlt seinen alten
  // Filter erneut - Combo zeigt ihn an, der Host erfaehrt nichts, das
  // Grid bleibt auf dem All-Stand. Eine vor dem Umbau gemerkte, noch
  // nicht committete Auswahl zeigt auf die ALTE Liste und ist damit
  // ebenfalls gegenstandslos.
  FHasPending := False;
  FCommitted  := 0;
  if (FCombo.Items.Count > 0) and (FCombo.ItemIndex >= 0)
     and (FCombo.ItemIndex < FCombo.Items.Count) then
  begin
    FCommitted := NativeInt(FCombo.Items.Objects[FCombo.ItemIndex]);
  end;
  FIsFiltering := False;
  FLastQuery := '';
  FPending := '';
  if Assigned(FTimer) then
  begin
    FTimer.Enabled := False;
  end;
end;

function TFuzzyComboSearch.SelectedTag(var ATag: NativeInt): Boolean;
begin
  ATag := 0;
  // ItemIndex >= 0 allein GENUEGT NICHT: bei leerer Liste wirft
  // Items.Objects[] eine Listenindex-Ausnahme, und ItemIndex kann in
  // Randlagen (Handle-Neuaufbau) trotzdem >= 0 melden. Die Anzahl ist die
  // belastbare Bedingung.
  Result := Assigned(FCombo)
        and (FCombo.Items.Count > 0)
        and (FCombo.ItemIndex >= 0)
        and (FCombo.ItemIndex < FCombo.Items.Count);
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
  Hits        : TList<TPair<Integer, Integer>>;   // Score, Index in FAll
  i, Sc, Shown: Integer;
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
      Shown := Hits.Count;
      if Shown > MAX_HITS then
      begin
        Shown := MAX_HITS;
      end;
      for i := 0 to Shown - 1 do
      begin
        FCombo.Items.AddObject(FAll[Hits[i].Value].Display,
                               TObject(FAll[Hits[i].Value].Tag));
      end;
      // Nicht stillschweigend abschneiden: wer 137 Treffer hat, soll das
      // sehen und die Eingabe schaerfen. Der Eintrag traegt den
      // Trenner-Tag, ist also kein waehlbares Ziel - die Hosts behandeln
      // Trenner bereits (die Regel-Liste enthaelt sie ohnehin).
      if Hits.Count > Shown then
      begin
        FCombo.Items.AddObject(
          Format(_('   ... %d more matches - refine the search'),
                 [Hits.Count - Shown]),
          TObject(SEPARATOR_TAG));
      end;

      // KEINE TREFFER: die Liste darf trotzdem NICHT leer bleiben.
      //
      // Zwei Gruende. Fachlich ist eine leere Aufklappliste nicht von
      // "kaputt" zu unterscheiden - der Nutzer sieht nicht, ob seine
      // Eingabe nichts trifft oder das Feld defekt ist. Technisch ist eine
      // leere TComboBox ein Minenfeld: TCustomComboBoxStrings.GetObject
      // wirft bei Count = 0 "Listenindex ausserhalb des gueltigen
      // Bereichs (0)", und JEDE Stelle - hier wie in beiden Hosts - prueft
      // nur ItemIndex >= 0, nicht die Anzahl. Genau diese Ausnahme trat
      // beim Tippen einer Zeichenfolge ohne Treffer auf. Mit einer immer
      // vorhandenen Zeile ist die ganze Fehlerklasse weg, unabhaengig
      // davon, welcher Zugriff sie ausgeloest hat.
      if FCombo.Items.Count = 0 then
      begin
        FCombo.Items.AddObject(_('   (no matches)'), TObject(SEPARATOR_TAG));
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
//
// Wie ApplyQuery: NIE bei offener Liste umbauen (Begruendung in
// TimerTick). Hier faellt das kaum auf, weil der haeufigste Aufrufer der
// Commit beim ZUKLAPPEN ist - aber Escape und Fokusverlust koennen die
// Liste offen antreffen.
var
  i          : Integer;
  WasDropped : Boolean;
begin
  WasDropped := IsListDropped;
  if WasDropped then
  begin
    SetListDropped(False);
  end;
  FCombo.Items.BeginUpdate;
  FCombo.Items.Clear;
  for i := 0 to FAll.Count - 1 do
  begin
    FCombo.Items.AddObject(FAll[i].Display, TObject(FAll[i].Tag));
  end;
  FCombo.Items.EndUpdate;
  if WasDropped then
  begin
    SetListDropped(True);
  end;
end;

procedure TFuzzyComboSearch.RestoreAll;
begin
  if Assigned(FTimer) then
  begin
    FTimer.Enabled := False;
  end;
  FPending := '';
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

function TFuzzyComboSearch.IsListDropped: Boolean;
begin
  Result := Assigned(FCombo) and FCombo.HandleAllocated
        and (SendMessage(FCombo.Handle, CB_GETDROPPEDSTATE, 0, 0) <> 0);
end;

procedure TFuzzyComboSearch.SetListDropped(AOpen: Boolean);
begin
  if not Assigned(FCombo) then Exit;
  if not FCombo.HandleAllocated then Exit;
  SendMessage(FCombo.Handle, CB_SHOWDROPDOWN, WPARAM(Ord(AOpen)), 0);
end;

procedure TFuzzyComboSearch.TimerTick(Sender: TObject);
// Entprellte Filterung: laeuft erst, wenn der Nutzer kurz innehaelt.
// Beim schnellen Tippen wird die Liste damit EINMAL aufgebaut statt je
// Zeichen - vorher waren das rund 200 Fenster-Nachrichten pro Taste.
var
  Q         : string;
  CaretPos  : Integer;
begin
  FTimer.Enabled := False;
  if FUpdating then Exit;
  if not Assigned(FCombo) then Exit;

  Q := FPending;
  if Q = FLastQuery then Exit;
  FLastQuery := Q;

  CaretPos := FCombo.SelStart;

  if Q = '' then
  begin
    RestoreAll;
    Exit;
  end;

  // DIE LISTE WIRD NIE UMGEBAUT, WAEHREND SIE OFFEN IST.
  //
  // Ein offenes Combo-Dropdown haelt die Maus-Capture und verarbeitet
  // Mausbewegungen in einer eigenen Tracking-Schleife. Baut man ihm die
  // Eintraege darunter weg, bleibt dieser Zustand zurueck - und die
  // Wiederanzeige des Zeigers, die Windows normalerweise bei der naechsten
  // MAUSBEWEGUNG macht, kommt nicht mehr an. Genau das war der Unterschied
  // zur Pfad-Combo: die fasst ihre Items nie an und klappt nie von selbst
  // auf, dort taucht der Zeiger beim Bewegen wieder auf.
  //
  // Also: war die Liste offen, wird sie zugeklappt, neu befuellt und
  // wieder aufgeklappt. War sie zu, bleibt sie zu - von selbst
  // aufzuklappen ist nichts, was eine gewoehnliche Combo tut.
  var WasDropped : Boolean := IsListDropped;
  if WasDropped then
  begin
    SetListDropped(False);
  end;

  ApplyQuery(Q);

  if WasDropped then
  begin
    SetListDropped(True);
  end;

  // Der Neuaufbau der Liste setzt den Cursor an den Anfang - zuruecksetzen,
  // sonst tippt man rueckwaerts.
  if FCombo.HandleAllocated then
  begin
    FCombo.SelStart  := CaretPos;
    FCombo.SelLength := 0;
  end;
end;

procedure TFuzzyComboSearch.ComboChange(Sender: TObject);
// Feuert beim Tippen. Hier wird NICHT gefiltert - nur die Eingabe
// gemerkt und der Entprell-Timer neu gestartet. Der OnChange des Hosts
// bleibt still; er laeuft erst bei echter Auswahl (ComboSelect), sonst
// wuerde jede Taste einen Filterlauf ueber alle Befunde ausloesen.
//
// Die frueher hier stehende Heuristik "Text entspricht einem Eintrag ->
// als Auswahl behandeln" ist RAUS: sie konnte beim Tippen zuschlagen und
// dann mitten in der Eingabe einen kompletten Host-Filterlauf starten.
// Die verlaessliche Quelle fuer eine Auswahl ist CBN_SELCHANGE, also
// OnSelect.
begin
  if FUpdating then Exit;
  if not Assigned(FCombo) then Exit;

  FPending := FCombo.Text;
  FIsFiltering := FPending <> '';
  FTimer.Enabled := False;
  FTimer.Enabled := True;
end;

procedure TFuzzyComboSearch.ComboSelect(Sender: TObject);
// CBN_SELCHANGE - und das ist NICHT gleichbedeutend mit "der Nutzer hat
// gewaehlt". Windows sendet es auch beim Blaettern mit den Pfeiltasten;
// MSDN empfiehlt darum ausdruecklich, auf CBN_CLOSEUP zu warten, wenn am
// Ereignis nennenswerte Verarbeitung haengt.
//
// Genau daran lag die gemeldete Traegheit: hier wurde frueher die volle
// Liste (rund 200 Eintraege) neu aufgebaut UND der Host benachrichtigt -
// dessen OnChange filtert bis zu 500.000 Befunde und baut das Grid neu.
// Ein Druck auf Pfeil-Runter kostete damit rund 400 Fenster-Nachrichten
// plus einen kompletten Filterlauf; durch fuenf Treffer blaettern
// entsprechend fuenfmal.
//
// Jetzt wird die Auswahl nur GEMERKT. Blaettern ist damit wieder so
// billig, wie es sein soll.
begin
  if FUpdating then Exit;
  if not Assigned(FCombo) then Exit;
  // Eine noch anstehende Entprellung ist mit der Auswahl gegenstandslos -
  // sonst baut sie danach die gefilterte Liste wieder auf.
  FTimer.Enabled := False;
  FPending := '';
  FHasPending := SelectedTag(FPendingTag);
end;

procedure TFuzzyComboSearch.CommitSelection;
// Der eine Ort, an dem der Host erfaehrt, dass sich etwas geaendert hat.
//
// Das Tag-Gate ist kein Luxus: Zuklappen ohne Auswahl-Aenderung (Escape,
// Klick daneben, Enter auf dem bereits gewaehlten Eintrag) darf keinen
// Filterlauf ausloesen.
var
  Tag : NativeInt;
begin
  if FUpdating then Exit;
  if not Assigned(FCombo) then Exit;

  FTimer.Enabled := False;
  FPending := '';

  if FHasPending then
  begin
    Tag := FPendingTag;
    RestoreAllAndSelect(Tag);
  end
  else if SelectedTag(Tag) then
  begin
    RestoreAllAndSelect(Tag);
  end
  else
  begin
    RestoreAll;
    Exit;                       // nichts gewaehlt -> nichts zu melden
  end;
  FHasPending := False;

  if Tag = FCommitted then Exit;
  FCommitted := Tag;

  if Assigned(FHostSelect) then
  begin
    FHostSelect(FCombo);
  end;
  if Assigned(FHostChange) then
  begin
    FHostChange(FCombo);
  end;
end;

procedure TFuzzyComboSearch.ComboCloseUp(Sender: TObject);
// CBN_CLOSEUP - die dokumentierte Stelle fuer teure Verarbeitung.
begin
  CommitSelection;
  if Assigned(FHostCloseUp) then
  begin
    FHostCloseUp(FCombo);
  end;
end;

procedure TFuzzyComboSearch.ComboExit(Sender: TObject);
// Fokusverlust bei OFFENER Eingabe: der Nutzer hat getippt und klickt
// weg. Ohne diesen Commit bliebe die gefilterte Liste stehen und die
// Auswahl waere nie gemeldet worden.
begin
  if FIsFiltering or FHasPending then
  begin
    CommitSelection;
  end;
  if Assigned(FHostExit) then
  begin
    FHostExit(FCombo);
  end;
end;

procedure TFuzzyComboSearch.ComboKeyUp(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Assigned(FCombo) and (Key = VK_ESCAPE) and FIsFiltering then
  begin
    // Escape verwirft die Eingabe und stellt den vorigen Zustand her.
    FHasPending := False;
    RestoreAll;
    Key := 0;
  end
  else if Assigned(FCombo) and (Key = VK_RETURN) then
  begin
    // Enter schliesst die Liste nicht ueberall verlaesslich, und
    // Pfeiltasten bei GESCHLOSSENER Liste erzeugen gar kein CBN_CLOSEUP.
    // Das Tag-Gate in CommitSelection macht einen Doppel-Commit harmlos.
    CommitSelection;
  end;
  if Assigned(FHostKeyUp) then
  begin
    FHostKeyUp(Sender, Key, Shift);
  end;
end;

end.
