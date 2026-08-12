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
  end;

implementation

// noinspection-file ClassPerFile, EmptyVisibilitySection, DuplicateString
// Zwei Fixtures in einer Unit: die reine Bewertungsfunktion und der
// Ereignis-Vertrag gehoeren fachlich zusammen und sollen zusammen
// gefunden werden. 'public' direkt nach dem Klassenkopf ist die
// DUnitX-Form (Testmethoden muessen sichtbar sein). Der Beispielstring
// 'SCA003  SQLInjection' wiederholt sich absichtlich - er ist der
// Pruefgegenstand mehrerer Faelle.

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

end.
