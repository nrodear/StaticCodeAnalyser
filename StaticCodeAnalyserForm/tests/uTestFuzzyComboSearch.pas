unit uTestFuzzyComboSearch;

// Tests fuer uFuzzyComboSearch (SCA.SharedUI).
//
// Der Kern-Test ist SelChange_DoesNotNotifyHost. Er haelt fest, was die
// urspruengliche Fassung falsch machte: VCLs OnSelect ist CBN_SELCHANGE,
// und Windows sendet das AUCH beim Blaettern mit den Pfeiltasten. Dort
// den Host zu benachrichtigen kostete je Pfeiltaste einen Filterlauf
// ueber alle Befunde plus einen Neuaufbau der ~200 Eintraege.
// Committed wird jetzt bei CBN_CLOSEUP.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes,
  Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, Winapi.Windows, Winapi.Messages,
  uFuzzyComboSearch;

type
  // ---- Fuzzy-Bewertung: reine Funktion, kein Fenster noetig -----------
  [TestFixture]
  TTestFuzzyMatch = class
  public
    [Test] procedure Subsequence_Matches;
    [Test] procedure MissingChar_NoMatch;
    [Test] procedure WrongOrder_NoMatch;
    [Test] procedure EmptyPattern_MatchesEverything;
    [Test] procedure WordStart_ScoresHigherThanMiddle;
    [Test] procedure Consecutive_ScoresHigherThanScattered;
  end;

  // ---- Ereignis-Vertrag gegen eine echte TComboBox --------------------
  [TestFixture]
  TTestFuzzyComboEvents = class
  strict private
    FForm   : TForm;
    FCombo  : TComboBox;
    FSearch : TFuzzyComboSearch;
    FChangeCount : Integer;
    FSelectCount : Integer;
    procedure HostChange(Sender: TObject);
    procedure HostSelect(Sender: TObject);
    procedure SendNotify(ANotifyCode: Word);
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure SelChange_DoesNotNotifyHost;
    [Test] procedure SelChange_DoesNotRebuildList;
    [Test] procedure CloseUp_NotifiesHostOnce;
    [Test] procedure CloseUp_WithoutChange_DoesNotNotify;
    [Test] procedure CloseUp_KeepsTagOfSelectedEntry;
    [Test] procedure NoHits_ListNeverEmpty;
    [Test] procedure NoHits_CommitDoesNotRaise;
    [Test] procedure Resync_ReselectingPreviousEntry_NotifiesAgain;
    [Test] procedure Resync_TakesCurrentSelectionAsCommitted;
    [Test] procedure NoteHostSelection_AlignsCommitGateWithDisplay;
    // Bugfix 06.09.2026 (Nico-Meldung, beide Oberflaechen): bei
    // MAUS-Auswahl sendet Windows CLOSEUP VOR SELCHANGE; das danach
    // eintreffende EN_CHANGE-Echo des Text-Updates armierte den
    // Entprell-Timer neu und die Fuzzy-Reduktion fror die Liste auf
    // den gewaehlten Eintrag ein - jede weitere Auswahl war tot.
    [Test] procedure MouseOrder_EditEcho_DoesNotShrinkList;
    [Test] procedure MouseOrder_SecondSelection_NotifiesAgain;
    [Test] procedure TypedFullTextOfOtherEntry_StillFilters;
    // Event-Review 06.09.2026: Trenner-Klick springt jetzt in BEIDEN
    // Wirten zum ersten Eintrag der Sektion (vorher Host-Sonderweg im
    // Plugin, den das Separator-Gate unerreichbar machte), und die
    // Maus-Reihenfolge hinterlaesst kein stales -1-Pending mehr.
    [Test] procedure SeparatorCommit_Keyboard_JumpsToFirstEntryOfSection;
    [Test] procedure SeparatorClick_MouseOrder_DoesNotSwallowNextSelection;
    [Test] procedure ArrowBrowse_EditEcho_DoesNotShrinkList;
    [Test] procedure ComboFreedBeforeHelper_DestroyDoesNotTouchIt;
    // Event-Review 06.09.2026, Enter-Pfad (Nicos Kernfrage): Enter nach
    // Fuzzy-Tippen lief in den Leer-Zweig (Tippen erzeugt kein
    // CBN_SELCHANGE, der Listen-Neuaufbau laesst ItemIndex = -1) und
    // verwarf Eingabe UND Reduktion. Jetzt committet ein EINDEUTIGES
    // Tipp-Ziel; mehrdeutige Eingaben verwerfen weiterhin bewusst.
    [Test] procedure Enter_TypedUnambiguous_CommitsSingleHit;
    [Test] procedure Enter_TypedAmbiguous_DoesNotCommit;
    [Test] procedure Enter_OnSelectedEntry_NotifiesOnceDespiteCloseUp;
    // Chargen-Review 06.09. (Runde 2): der Einzeltreffer-Commit gilt
    // nur fuer EXPLIZITE Gesten (Enter/Fokusverlust) - ein Zuklappen
    // kommt auch von Escape; die Live-Auswahl schlaegt ein aelteres
    // Blaetter-Pending; Hinweiszeilen-Klicks und Trenner am Listenende
    // committen nichts.
    [Test] procedure EscapeCloseUp_AfterTyping_DoesNotCommit;
    [Test] procedure FocusLoss_UnambiguousTyping_Commits;
    [Test] procedure ArrowBrowseOpen_ThenMouseClick_CommitsClickedEntry;
    [Test] procedure NoMatchesRow_ClickInStaleWindow_DoesNotCommit;
    [Test] procedure SeparatorAtEnd_RestoresPreviousSelection;
  end;

implementation

// noinspection-file ClassPerFile, EmptyVisibilitySection, DuplicateString, GodClass, HardcodedString
// Zwei Fixtures in einer Unit: die reine Bewertungsfunktion und der
// Ereignis-Vertrag gehoeren fachlich zusammen und sollen zusammen
// gefunden werden. 'public' direkt nach dem Klassenkopf ist die
// DUnitX-Form (Testmethoden muessen sichtbar sein). Der Beispielstring
// 'SCA003  SQLInjection' wiederholt sich absichtlich - er ist der
// Pruefgegenstand mehrerer Faelle. GodClass: eine DUnitX-Fixture
// waechst mit jedem Ereignis-Regressionsfall - die Testmethoden SIND
// der Katalog, eine Aufspaltung wuerde nur das Setup duplizieren.
// HardcodedString: 'Rule20'/'Rule1' sind FIXTURE-EINGABEN in das
// Tipp-Feld, keine nutzersichtbaren Texte.

const
  SEPARATOR_TAG = -1;
  // Zeichenfolge, die garantiert keinen Eintrag trifft - genau die
  // Eingabe, mit der die Listenindex-Ausnahme gemeldet wurde.
  NO_MATCH_QUERY = 'tesgvfljkmnlkm';

{ TTestFuzzyMatch }

procedure TTestFuzzyMatch.Subsequence_Matches;
var
  Sc : Integer;
begin
  Sc := 0;
  Assert.IsTrue(FuzzyMatch('sqlinj', 'SCA003  SQLInjection', Sc),
    'Zeichen in Reihenfolge, nicht zusammenhaengend - muss treffen');
end;

procedure TTestFuzzyMatch.MissingChar_NoMatch;
var
  Sc : Integer;
begin
  Sc := 0;
  Assert.IsFalse(FuzzyMatch('sqlxyz', 'SCA003  SQLInjection', Sc));
end;

procedure TTestFuzzyMatch.WrongOrder_NoMatch;
var
  Sc : Integer;
begin
  Sc := 0;
  // 'jni' kommt in 'SQLInjection' nur in anderer Reihenfolge vor.
  Assert.IsFalse(FuzzyMatch('jnq', 'SCA003  SQLInjection', Sc));
end;

procedure TTestFuzzyMatch.EmptyPattern_MatchesEverything;
var
  Sc : Integer;
begin
  Sc := -1;
  Assert.IsTrue(FuzzyMatch('', 'irgendwas', Sc));
  Assert.AreEqual<Integer>(0, Sc, 'leeres Muster hat keinen Score');
end;

procedure TTestFuzzyMatch.WordStart_ScoresHigherThanMiddle;
var
  AtStart, InMiddle : Integer;
begin
  AtStart  := 0;
  InMiddle := 0;
  Assert.IsTrue(FuzzyMatch('sql', 'SQLInjection', AtStart));
  Assert.IsTrue(FuzzyMatch('sql', 'MssqlHelper', InMiddle));
  Assert.IsTrue(AtStart > InMiddle,
    Format('Wortanfang muss besser bewertet sein (%d) als Wortmitte (%d)',
           [AtStart, InMiddle]));
end;

procedure TTestFuzzyMatch.Consecutive_ScoresHigherThanScattered;
var
  Tight, Loose : Integer;
begin
  Tight := 0;
  Loose := 0;
  Assert.IsTrue(FuzzyMatch('abc', 'abcdef', Tight));
  Assert.IsTrue(FuzzyMatch('abc', 'axxbxxc', Loose));
  Assert.IsTrue(Tight > Loose,
    Format('zusammenhaengend (%d) muss besser sein als verstreut (%d)',
           [Tight, Loose]));
end;

{ TTestFuzzyComboEvents }

procedure TTestFuzzyComboEvents.Setup;
var
  i : Integer;
begin
  FChangeCount := 0;
  FSelectCount := 0;

  FForm := TForm.CreateNew(nil);
  FCombo := TComboBox.Create(FForm);
  FCombo.Parent := FForm;
  FCombo.Style  := csDropDownList;         // Ausgangszustand beider Hosts

  // Liste wie in den Hosts: 'All' + Trenner + Regel-Eintraege mit Tag.
  FCombo.Items.AddObject('All', TObject(0));
  FCombo.Items.AddObject('--- Errors (A-Z) ---', TObject(SEPARATOR_TAG));
  for i := 1 to 20 do
    FCombo.Items.AddObject(Format('SCA%.3d  Rule%d', [i, i]), TObject(100 + i));
  FCombo.ItemIndex := 0;

  FCombo.OnChange := HostChange;
  FCombo.OnSelect := HostSelect;

  FCombo.HandleNeeded;
  Assert.IsTrue(FCombo.HandleAllocated, 'Combo braucht ein Fensterhandle');

  FSearch := TFuzzyComboSearch.Create(FForm);
  FSearch.Attach(FCombo);
end;

procedure TTestFuzzyComboEvents.TearDown;
begin
  FreeAndNil(FForm);   // besitzt Combo und Helfer
end;

procedure TTestFuzzyComboEvents.HostChange(Sender: TObject);
begin
  Inc(FChangeCount);
end;

procedure TTestFuzzyComboEvents.HostSelect(Sender: TObject);
begin
  Inc(FSelectCount);
end;

procedure TTestFuzzyComboEvents.SendNotify(ANotifyCode: Word);
// Schickt dieselbe Benachrichtigung, die Windows dem Elternfenster
// schickt: CN_COMMAND mit dem Code im High-Word von WParam
// (siehe Vcl.StdCtrls TCustomCombo.CNCommand).
begin
  FCombo.Perform(CN_COMMAND, MakeWParam(0, ANotifyCode), FCombo.Handle);
end;

procedure TTestFuzzyComboEvents.SelChange_DoesNotNotifyHost;
// DER KERN-TEST. CBN_SELCHANGE feuert auch beim Blaettern mit den
// Pfeiltasten. Wuerde dort der Host benachrichtigt, kostete jede
// Pfeiltaste einen Filterlauf ueber alle Befunde.
var
  i : Integer;
begin
  for i := 1 to 5 do
  begin
    FCombo.ItemIndex := 2 + i;
    SendNotify(CBN_SELCHANGE);
  end;
  Assert.AreEqual<Integer>(0, FChangeCount,
    'Blaettern darf den Host NICHT benachrichtigen');
  Assert.AreEqual<Integer>(0, FSelectCount,
    'Blaettern darf den Host NICHT benachrichtigen');
end;

procedure TTestFuzzyComboEvents.SelChange_DoesNotRebuildList;
// Beim Blaettern darf die Liste nicht neu aufgebaut werden - das waren
// rund 200 Fenster-Nachrichten je Tastendruck.
var
  Before, i : Integer;
begin
  Before := FCombo.Items.Count;
  for i := 1 to 5 do
  begin
    FCombo.ItemIndex := 2 + i;
    SendNotify(CBN_SELCHANGE);
  end;
  Assert.AreEqual<Integer>(Before, FCombo.Items.Count,
    'Die Liste darf beim Blaettern unveraendert bleiben');
end;

procedure TTestFuzzyComboEvents.CloseUp_NotifiesHostOnce;
begin
  FCombo.ItemIndex := 5;
  SendNotify(CBN_SELCHANGE);
  SendNotify(CBN_CLOSEUP);
  Assert.AreEqual<Integer>(1, FChangeCount,
    'Zuklappen mit geaenderter Auswahl meldet GENAU einmal');
  Assert.AreEqual<Integer>(1, FSelectCount);
end;

procedure TTestFuzzyComboEvents.CloseUp_WithoutChange_DoesNotNotify;
// Zuklappen ohne Auswahl-Aenderung (Escape, Klick daneben) darf keinen
// Filterlauf ausloesen - dafuer sorgt das Tag-Gate.
begin
  FCombo.ItemIndex := 5;
  SendNotify(CBN_SELCHANGE);
  SendNotify(CBN_CLOSEUP);
  Assert.AreEqual<Integer>(1, FChangeCount);

  SendNotify(CBN_CLOSEUP);
  Assert.AreEqual<Integer>(1, FChangeCount,
    'Zweites Zuklappen ohne Aenderung darf NICHT erneut melden');
end;

procedure TTestFuzzyComboEvents.CloseUp_KeepsTagOfSelectedEntry;
// C1: die Hosts lesen ihre Auswahl ueber Items.Objects[ItemIndex]. Nach
// dem Zuruecklegen der vollen Liste muss dort derselbe Tag stehen.
var
  Expected : NativeInt;
begin
  FCombo.ItemIndex := 7;
  Expected := NativeInt(FCombo.Items.Objects[7]);
  SendNotify(CBN_SELCHANGE);
  SendNotify(CBN_CLOSEUP);
  Assert.IsTrue(FCombo.ItemIndex >= 0, 'Auswahl muss erhalten bleiben');
  Assert.AreEqual<NativeInt>(Expected,
    NativeInt(FCombo.Items.Objects[FCombo.ItemIndex]),
    'Tag der Auswahl muss den Neuaufbau der Liste ueberleben');
end;

procedure TTestFuzzyComboEvents.NoHits_ListNeverEmpty;
// REGRESSION: eine Eingabe ohne jeden Treffer hinterliess eine LEERE
// Liste. Fachlich ist das nicht von "kaputt" zu unterscheiden, technisch
// wirft TCustomComboBoxStrings.GetObject bei Count = 0
// "Listenindex ausserhalb des gueltigen Bereichs (0)" - und alle
// Zugriffe, hier wie in beiden Hosts, pruefen nur ItemIndex >= 0.
begin
  FCombo.Text := NO_MATCH_QUERY;
  FCombo.Perform(CN_COMMAND, MakeWParam(0, CBN_EDITCHANGE), FCombo.Handle);
  // Entprellung ueberspringen: direkt filtern lassen.
  FSearch.FilterNow;
  Assert.IsTrue(FCombo.Items.Count > 0,
    'Ohne Treffer muss trotzdem eine Zeile stehen - eine leere ComboBox '
    + 'ist ein Minenfeld fuer Items.Objects[]');
end;

procedure TTestFuzzyComboEvents.NoHits_CommitDoesNotRaise;
// Nach einer trefferlosen Eingabe darf ein Commit (Zuklappen, Enter,
// Fokusverlust) keine Ausnahme werfen.
begin
  FCombo.Text := NO_MATCH_QUERY;
  FCombo.Perform(CN_COMMAND, MakeWParam(0, CBN_EDITCHANGE), FCombo.Handle);
  FSearch.FilterNow;
  SendNotify(CBN_CLOSEUP);
  Assert.Pass('Commit ohne Treffer laeuft ohne Ausnahme durch');
end;

procedure TTestFuzzyComboEvents.Resync_ReselectingPreviousEntry_NotifiesAgain;
// REGRESSION (2026-08-12): RebuildFilterCombos setzt die Combo nach dem
// Scan auf 'All' zurueck und ruft Resync. Waehlt der Nutzer danach seinen
// vorigen Filter ERNEUT, verglich das Tag-Gate in CommitSelection noch
// gegen die Auswahl von VOR dem Umbau und schwieg - die Combo zeigte den
// Filter an, der Host erfuhr nichts, das Grid blieb ungefiltert.
begin
  // Nutzer waehlt Eintrag 5 - Host wird gemeldet.
  FCombo.ItemIndex := 5;
  SendNotify(CBN_SELCHANGE);
  SendNotify(CBN_CLOSEUP);
  Assert.AreEqual<Integer>(1, FChangeCount, 'Vorbedingung: erste Auswahl meldet');

  // Host baut um wie RebuildFilterCombos: Reset auf 'All' + Resync.
  FCombo.ItemIndex := 0;
  FSearch.Resync;

  // Dieselbe Auswahl wie vor dem Umbau - muss ERNEUT gemeldet werden.
  FCombo.ItemIndex := 5;
  SendNotify(CBN_SELCHANGE);
  SendNotify(CBN_CLOSEUP);
  Assert.AreEqual<Integer>(2, FChangeCount,
    'Nach Resync ist die alte Auswahl ein NEUER Wechsel und muss melden');
end;

procedure TTestFuzzyComboEvents.NoteHostSelection_AlignsCommitGateWithDisplay;
// REGRESSION (Kachel-Pfad, Review 2026-08-12): Kachel-Klicks setzen
// ItemIndex programmatisch und rufen die Host-Handler direkt - der
// Helfer sieht davon nichts. Ohne NoteHostSelection mass das Tag-Gate
// weiter gegen den alten Commit-Stand: Zuklappen auf der vom Host
// gesetzten Auswahl meldete faelschlich (oder die Wieder-Auswahl des
// alten Eintrags schwieg). NoteHostSelection zieht das Gate auf die
// Anzeige nach.
begin
  // Host setzt die Auswahl programmatisch um (wie ein Kachel-Klick).
  FCombo.ItemIndex := 5;
  FSearch.NoteHostSelection;

  // Zuklappen auf genau dieser Auswahl ist KEINE Aenderung.
  SendNotify(CBN_SELCHANGE);
  SendNotify(CBN_CLOSEUP);
  Assert.AreEqual<Integer>(0, FChangeCount,
    'Zuklappen auf der vom Host gesetzten Auswahl meldet nicht');

  // Ein ANDERER Eintrag ist eine echte Aenderung und muss melden.
  FCombo.ItemIndex := 7;
  SendNotify(CBN_SELCHANGE);
  SendNotify(CBN_CLOSEUP);
  Assert.AreEqual<Integer>(1, FChangeCount,
    'Wechsel auf einen anderen Eintrag meldet genau einmal');
end;

procedure TTestFuzzyComboEvents.Resync_TakesCurrentSelectionAsCommitted;
// Gegenprobe zum Regressionstest: Resync uebernimmt die AKTUELLE Anzeige
// als Commit-Stand. Ein Zuklappen auf dem Eintrag, den die Combo nach dem
// Umbau ohnehin zeigt, ist keine Aenderung und darf nicht melden.
begin
  FCombo.ItemIndex := 5;
  FSearch.Resync;

  SendNotify(CBN_SELCHANGE);   // Blaettern landet wieder auf Eintrag 5
  SendNotify(CBN_CLOSEUP);
  Assert.AreEqual<Integer>(0, FChangeCount,
    'Zuklappen auf der nach dem Umbau angezeigten Auswahl meldet nicht');
end;

procedure TTestFuzzyComboEvents.MouseOrder_EditEcho_DoesNotShrinkList;
// Exakte Maus-Reihenfolge: CLOSEUP -> SELCHANGE -> EN_CHANGE-Echo.
// FilterNow ersetzt den Timerablauf. Ohne den Echo-Waechter in
// ComboChange reduziert die Fuzzy-Suche die Liste auf den
// Anzeigetext der Auswahl - dieser Test ist am Bestand ROT.
var
  Voll : Integer;
begin
  Voll := FCombo.Items.Count;
  FCombo.ItemIndex := 5;
  SendNotify(CBN_CLOSEUP);
  SendNotify(CBN_SELCHANGE);
  FCombo.Text := FCombo.Items[5];   // Text-Update der Auswahl
  SendNotify(CBN_EDITCHANGE);       // dessen EN_CHANGE-Echo
  FSearch.FilterNow;                // Timerablauf
  Assert.AreEqual<Integer>(Voll, FCombo.Items.Count,
    'das Auswahl-Echo darf die Liste nicht reduzieren');
end;

procedure TTestFuzzyComboEvents.MouseOrder_SecondSelection_NotifiesAgain;
begin
  FCombo.ItemIndex := 5;
  SendNotify(CBN_CLOSEUP);
  SendNotify(CBN_SELCHANGE);
  FCombo.Text := FCombo.Items[5];
  SendNotify(CBN_EDITCHANGE);
  FSearch.FilterNow;
  Assert.AreEqual<Integer>(1, FChangeCount, 'erste Auswahl meldet');
  // Zweite Auswahl (wieder Maus-Reihenfolge) MUSS erneut melden -
  // im Bestand war die Liste hier bereits eingefroren.
  FCombo.ItemIndex := 7;
  SendNotify(CBN_CLOSEUP);
  SendNotify(CBN_SELCHANGE);
  Assert.AreEqual<Integer>(2, FChangeCount,
    'zweite Auswahl muss das Grid wieder erreichen');
end;

procedure TTestFuzzyComboEvents.TypedFullTextOfOtherEntry_StillFilters;
// Der Echo-Waechter ist ENG: getippter Volltext eines ANDEREN als
// des selektierten Eintrags filtert weiterhin (TP-Gegenprobe).
var
  Voll : Integer;
begin
  Voll := FCombo.Items.Count;
  FCombo.ItemIndex := 0;             // 'All' selektiert
  FCombo.Text := FCombo.Items[5];    // Volltext eines anderen
  SendNotify(CBN_EDITCHANGE);
  FSearch.FilterNow;
  Assert.IsTrue(FCombo.Items.Count < Voll,
    'echtes Tippen reduziert weiterhin (Liste voll = Waechter zu breit)');
end;

procedure TTestFuzzyComboEvents.Enter_TypedUnambiguous_CommitsSingleHit;
// 'Rule20' trifft in der Fixture GENAU einen Eintrag (von Hand geprueft:
// 'Rule2' hat keine 0, 'Rule12' keine 2-0-Folge). Enter muss dieses
// eine Ziel committen - am Bestand blieb ItemIndex auf 'All' stehen
// (Tippen selektiert nicht) und das Tag-Gate schwieg: dieser Test ist
// am Bestand ROT.
var
  Key : Word;
begin
  FCombo.Text := 'Rule20';
  SendNotify(CBN_EDITCHANGE);
  Key := VK_RETURN;
  FCombo.OnKeyUp(FCombo, Key, []);   // Attach hat ComboKeyUp verdrahtet
  Assert.AreEqual<Integer>(1, FChangeCount,
    'Enter auf eindeutigem Tipp-Treffer muss genau einmal melden');
  Assert.IsTrue(FCombo.ItemIndex >= 0, 'das Ziel muss selektiert sein');
  Assert.AreEqual<NativeInt>(120,
    NativeInt(FCombo.Items.Objects[FCombo.ItemIndex]),
    'committet wird der eine Fuzzy-Treffer (SCA020  Rule20)');
end;

procedure TTestFuzzyComboEvents.Enter_TypedAmbiguous_DoesNotCommit;
// 'Rule1' trifft Rule1 und Rule10..Rule19 - keine Auto-Auswahl aus
// mehreren Treffern (waere geraten). Enter verwirft wie bisher.
var
  Key  : Word;
  Voll : Integer;
begin
  Voll := FCombo.Items.Count;
  FCombo.Text := 'Rule1';
  SendNotify(CBN_EDITCHANGE);
  Key := VK_RETURN;
  FCombo.OnKeyUp(FCombo, Key, []);
  Assert.AreEqual<Integer>(0, FChangeCount,
    'mehrdeutiges Enter darf nicht raten und nicht melden');
  Assert.AreEqual<Integer>(Voll, FCombo.Items.Count,
    'nach dem verworfenen Enter steht die volle Liste');
end;

procedure TTestFuzzyComboEvents.Enter_OnSelectedEntry_NotifiesOnceDespiteCloseUp;
// Der Kommentar am VK_RETURN-Zweig behauptet seit dem 06.09., das
// Tag-Gate mache den Doppel-Commit (Enter-KeyUp + nachfolgendes
// CBN_CLOSEUP) harmlos - hier ist der Beweis fuer die reale
// Enter-Sequenz (Testluecke aus dem Event-Review).
var
  Key : Word;
begin
  FCombo.ItemIndex := 5;
  SendNotify(CBN_SELCHANGE);
  Key := VK_RETURN;
  FCombo.OnKeyUp(FCombo, Key, []);   // Commit ueber den KeyUp-Zweig
  SendNotify(CBN_CLOSEUP);           // Windows schliesst die Liste danach
  Assert.AreEqual<Integer>(1, FChangeCount,
    'Enter + CloseUp auf derselben Auswahl melden zusammen genau einmal');
end;

procedure TTestFuzzyComboEvents.EscapeCloseUp_AfterTyping_DoesNotCommit;
// Escape schliesst eine offene Liste (CBN_CLOSEUP) BEVOR der
// Escape-KeyUp laeuft. Der CLOSEUP-Commit darf das eindeutige
// Tipp-Ziel deshalb NICHT uebernehmen - sonst wuerde ein Abbruch zur
// Auswahl (Regression der ersten Einzeltreffer-Fassung, vom
// Chargen-Review gefangen: dieser Test ist an ihr ROT).
var
  Voll : Integer;
begin
  Voll := FCombo.Items.Count;
  FCombo.Text := 'Rule20';
  SendNotify(CBN_EDITCHANGE);
  FSearch.FilterNow;                 // Liste = 1 Treffer
  SendNotify(CBN_CLOSEUP);           // Zuklappen durch Escape
  Assert.AreEqual<Integer>(0, FChangeCount,
    'ein Zuklappen ist keine explizite Uebernahme-Geste');
  Assert.AreEqual<Integer>(Voll, FCombo.Items.Count,
    'die volle Liste ist zurueckgelegt');
end;

procedure TTestFuzzyComboEvents.FocusLoss_UnambiguousTyping_Commits;
// Fokusverlust ist wie Enter eine Uebernahme-Geste: ein eindeutiges
// Tipp-Ziel wird committet (Testluecke aus dem Chargen-Review).
begin
  FCombo.Text := 'Rule20';
  SendNotify(CBN_EDITCHANGE);
  FSearch.FilterNow;
  FCombo.OnExit(FCombo);             // Attach hat ComboExit verdrahtet
  Assert.AreEqual<Integer>(1, FChangeCount,
    'Fokusverlust uebernimmt das eindeutige Tipp-Ziel');
  Assert.AreEqual<NativeInt>(120,
    NativeInt(FCombo.Items.Objects[FCombo.ItemIndex]),
    'uebernommen wird der eine Fuzzy-Treffer');
end;

procedure TTestFuzzyComboEvents.ArrowBrowseOpen_ThenMouseClick_CommitsClickedEntry;
// BESTANDSFIX (Chargen-Review 06.09.): Blaettern auf B (Pending),
// dann Maus-Klick auf C - der Maus-Commit laeuft mit cursel=C, das
// Pending traegt noch B. Ohne den Live-Vorrang gewann B und der Klick
// auf C verschwand spurlos; dieser Test ist am Vor-Fix-Stand ROT.
begin
  FCombo.ItemIndex := 5;             // Blaettern -> Pending Tag 104
  SendNotify(CBN_SELCHANGE);
  FCombo.ItemIndex := 7;             // Maus-Klick: cursel steht auf C
  SendNotify(CBN_CLOSEUP);
  SendNotify(CBN_SELCHANGE);         // Nachzuegler der Maus-Reihenfolge
  Assert.AreEqual<Integer>(1, FChangeCount,
    'der Klick committet genau einmal');
  Assert.AreEqual<NativeInt>(106,
    NativeInt(FCombo.Items.Objects[FCombo.ItemIndex]),
    'committet wird der GEKLICKTE Eintrag, nicht das Blaetter-Pending');
end;

procedure TTestFuzzyComboEvents.NoMatchesRow_ClickInStaleWindow_DoesNotCommit;
// Das 160-ms-Fenster nach dem Textloeschen: FIsFiltering ist schon
// False, die Anzeige zeigt noch die reduzierte Liste. Ein Klick auf
// die '(no matches)'-Hinweiszeile (Tag -1) darf dann keinen
// willkuerlichen Schnappschuss-Eintrag committen - das fruehere
// not-FIsFiltering-Gate tat genau das (dieser Test ist daran ROT);
// das Count-Gate (Anzeige == Schnappschuss) haelt dicht.
begin
  FCombo.Text := NO_MATCH_QUERY;
  SendNotify(CBN_EDITCHANGE);
  FSearch.FilterNow;                 // Liste = ['(no matches)']
  FCombo.Text := '';
  SendNotify(CBN_EDITCHANGE);        // FIsFiltering=False, Liste noch reduziert
  FCombo.ItemIndex := 0;             // Klick auf die Hinweiszeile
  SendNotify(CBN_CLOSEUP);
  Assert.AreEqual<Integer>(0, FChangeCount,
    'die Hinweiszeile ist kein Sprungbrett in den Schnappschuss');
  // Commit-Gedaechtnis unvergiftet: eine normale Auswahl meldet danach.
  FCombo.ItemIndex := 5;
  SendNotify(CBN_SELCHANGE);
  SendNotify(CBN_CLOSEUP);
  Assert.AreEqual<Integer>(1, FChangeCount,
    'danach meldet eine normale Auswahl genau einmal');
end;

procedure TTestFuzzyComboEvents.SeparatorAtEnd_RestoresPreviousSelection;
// Trenner ohne Folge-Eintrag: kein Sprungziel - die vorige Auswahl
// wird zurueckgelegt, nichts gemeldet (Testluecke aus dem Review).
begin
  FCombo.ItemIndex := 5;
  SendNotify(CBN_SELCHANGE);
  SendNotify(CBN_CLOSEUP);
  Assert.AreEqual<Integer>(1, FChangeCount, 'Vorbedingung: Auswahl steht');

  FCombo.Items.AddObject('--- tail ---', TObject(SEPARATOR_TAG));
  FSearch.Resync;                    // Schnappschuss inkl. End-Trenner

  FCombo.ItemIndex := FCombo.Items.Count - 1;   // Klick auf den End-Trenner
  SendNotify(CBN_SELCHANGE);
  SendNotify(CBN_CLOSEUP);
  Assert.AreEqual<Integer>(1, FChangeCount,
    'ohne Sprungziel wird nichts gemeldet');
  Assert.AreEqual<NativeInt>(104,
    NativeInt(FCombo.Items.Objects[FCombo.ItemIndex]),
    'die vorige Auswahl liegt wieder an');
end;

procedure TTestFuzzyComboEvents.ComboFreedBeforeHelper_DestroyDoesNotTouchIt;
// Teardown-Reihenfolge des VCL: Kind-CONTROLS sterben in
// TWinControl.Destroy VOR den besessenen Komponenten (DestroyComponents).
// Die Combo ist also beim Helfer-Destroy schon weg - ohne
// FreeNotification schrieb die Handler-Restauration in freigegebenen
// Speicher. GRENZE DES BEWEISES: ohne FullDebugMode ist ein stilles
// Use-after-free meist symptomlos; der Test dokumentiert den Vertrag
// und schlaegt unter einem pruefenden Speichermanager an.
var
  LCombo  : TComboBox;
  LSearch : TFuzzyComboSearch;
begin
  LCombo := TComboBox.Create(nil);
  try
    LCombo.Parent := FForm;
    LCombo.Items.AddObject('All', TObject(0));
    LCombo.ItemIndex := 0;
    LSearch := TFuzzyComboSearch.Create(nil);
    try
      LSearch.Attach(LCombo);
      FreeAndNil(LCombo);          // Combo stirbt ZUERST (Teardown-Ordnung)
    finally
      LSearch.Free;                // darf die tote Combo nicht anfassen
    end;
  finally
    LCombo.Free;                   // nil-sicher (FreeAndNil oben)
  end;
  Assert.Pass('Helfer-Destroy nach Combo-Free laeuft ohne Zugriff auf die tote Combo');
end;

procedure TTestFuzzyComboEvents.SeparatorCommit_Keyboard_JumpsToFirstEntryOfSection;
// Tastatur-Reihenfolge (SELCHANGE vor CLOSEUP) auf der Trennzeile:
// der Commit springt zum ERSTEN Eintrag der Sektion darunter und
// meldet GENAU diesen - kein -1 im Commit-Gedaechtnis.
// Fixture: Index 1 = '--- Errors (A-Z) ---', Index 2 = SCA001 (Tag 101).
begin
  FCombo.ItemIndex := 1;
  SendNotify(CBN_SELCHANGE);
  SendNotify(CBN_CLOSEUP);
  Assert.AreEqual<Integer>(1, FChangeCount,
    'Trenner-Klick springt und meldet den Sektions-Anfang genau einmal');
  Assert.IsTrue(FCombo.ItemIndex >= 0, 'Sprungziel muss selektiert sein');
  Assert.AreEqual<NativeInt>(101,
    NativeInt(FCombo.Items.Objects[FCombo.ItemIndex]),
    'Sprungziel ist der erste Eintrag NACH dem Trenner');
  // Dieselbe Sektion erneut anspringen ist keine Aenderung mehr.
  FCombo.ItemIndex := 1;
  SendNotify(CBN_SELCHANGE);
  SendNotify(CBN_CLOSEUP);
  Assert.AreEqual<Integer>(1, FChangeCount,
    'zweiter Sprung auf denselben Eintrag meldet nicht erneut');
end;

procedure TTestFuzzyComboEvents.SeparatorClick_MouseOrder_DoesNotSwallowNextSelection;
// MAUS-Reihenfolge (CLOSEUP vor SELCHANGE) auf der Trennzeile. Am
// Bestand hinterliess der Nachzuegler-SELCHANGE ein Pending mit Tag -1
// (der Gleichheits-Verwurf fasst nur FPendingTag = FCommitted): der
// NAECHSTE Klick auf einen echten Eintrag wurde verworfen und die
// Combo sprang auf den ersten Trenner zurueck - dieser Test ist am
// Bestand ROT.
begin
  FCombo.ItemIndex := 1;             // Klick auf die Trennzeile
  SendNotify(CBN_CLOSEUP);           // Maus: Commit laeuft ZUERST
  SendNotify(CBN_SELCHANGE);         // Nachzuegler liest den Ist-Stand
  FCombo.Text := FCombo.Items[FCombo.ItemIndex];
  SendNotify(CBN_EDITCHANGE);        // EN_CHANGE-Echo des Text-Updates
  Assert.AreEqual<Integer>(1, FChangeCount,
    'Trenner-Klick per Maus springt und meldet genau einmal');

  FCombo.ItemIndex := 7;             // naechster Klick: echter Eintrag
  SendNotify(CBN_CLOSEUP);
  SendNotify(CBN_SELCHANGE);
  Assert.AreEqual<Integer>(2, FChangeCount,
    'der Klick nach dem Trenner darf nicht verschluckt werden');
  Assert.AreEqual<NativeInt>(106,
    NativeInt(FCombo.Items.Objects[FCombo.ItemIndex]),
    'die Combo muss die geklickte Auswahl zeigen, nicht die Trennzeile');
end;

procedure TTestFuzzyComboEvents.ArrowBrowse_EditEcho_DoesNotShrinkList;
// Pfeiltasten-Blaettern bei GESCHLOSSENER Liste aktualisiert den
// Edit-Text je Taste und erzeugt dasselbe EN_CHANGE-Echo wie die
// Maus-Auswahl - nur dass hier NIE ein CLOSEUP den Timer stoppt. Der
// Echo-Waechter muss also auch diese Echos schlucken, sonst reduziert
// der Entprell-Timer die Liste still auf den Auswahltext
// (Testluecke aus dem Event-Review 06.09.).
var
  Voll : Integer;
begin
  Voll := FCombo.Items.Count;
  FCombo.ItemIndex := 5;
  SendNotify(CBN_SELCHANGE);
  FCombo.Text := FCombo.Items[5];
  SendNotify(CBN_EDITCHANGE);
  FCombo.ItemIndex := 6;
  SendNotify(CBN_SELCHANGE);
  FCombo.Text := FCombo.Items[6];
  SendNotify(CBN_EDITCHANGE);
  FSearch.FilterNow;                 // ein faelschlich armierter Timer laeuft ab
  Assert.AreEqual<Integer>(Voll, FCombo.Items.Count,
    'Blaettern-Echos duerfen die Liste nicht reduzieren');
  Assert.AreEqual<Integer>(0, FChangeCount,
    'Blaettern allein meldet weiterhin nicht');
end;

end.
