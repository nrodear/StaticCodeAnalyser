unit uTestRuleListBox;

// Tests fuer TRuleListBox (SCA.SharedUI\sources\uRuleListBox.pas) -
// die Regelliste, die das Profil-Fenster und der Auswahldialog teilen.
//
// Geprueft wird die LOGIK, nicht das Aussehen: Sortierung, Filter und die
// Zusage "ein Haken ueberlebt das Filtern". Die letzte ist der Grund,
// warum die Klasse ueberhaupt einen eigenen Satz FChecked fuehrt - Fill
// baut die Zeilen neu auf, ein Haken am TListItem waere danach weg. Ohne
// Test bricht das lautlos, sobald jemand Fill anfasst.
//
// Die Klasse braucht ein Elternfenster fuer ihre Steuerelemente. Das
// Testprojekt ist eine VCL-Anwendung (TestInsight-GUI-Build), ein
// unsichtbares TForm ist also zulaessig und kostet nichts.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRuleListBox = class
  public
    // --- Filter ----------------------------------------------------------
    [Test] procedure FilterNarrowsShownButNotTotal;
    [Test] procedure FilterIsCaseInsensitive;
    [Test] procedure FilterMatchesKindToken;
    [Test] procedure EmptyFilterShowsEverything;
    // --- Sortierung ------------------------------------------------------
    // Zweiter Schluessel ist immer die ID; ohne ihn saehe dieselbe Liste
    // bei jedem Aufbau anders aus.
    [Test] procedure SortByIdIsStableAcrossRebuilds;
    [Test] procedure SortDescendingReversesFirstRow;
    // --- Haken -----------------------------------------------------------
    [Test] procedure CheckSurvivesFilterChange;
    [Test] procedure UncheckRemovesFromSet;
    [Test] procedure CheckedIsEmptyWithoutCheckboxes;
  end;

implementation

// noinspection-file DuplicateString, ClassPerFile, PublicField, LegacyInitializationSection
// DuplicateString: Fixture-Text, s.o. ClassPerFile/PublicField:
// TStand ist ein Testgeruest, kein Modell - Fenster und Liste liegen
// offen, damit ein Test sie in einer Zeile erreicht. Eine Kapselung
// mit Gettern haette hier nichts zu schuetzen.

uses
  Vcl.Forms, Vcl.ComCtrls, Vcl.Controls,
  uSCAConsts, uRuleCatalog, uRuleListBox;

type
  // Haelt Fenster und Liste zusammen, damit jeder Test mit zwei Zeilen
  // aufbaut und mit einer abraeumt.
  TStand = class
  public
    Form  : TForm;
    Liste : TRuleListBox;
    constructor Create(ACheckboxes: Boolean);
    destructor Destroy; override;
    /// <summary>Das ListView der Liste - fuer Tests, die einen Haken
    /// setzen muessen, wie es ein Benutzer taete.</summary>
    function Lv: TListView;
  end;

constructor TStand.Create(ACheckboxes: Boolean);
begin
  inherited Create;
  Form := TForm.CreateNew(nil);
  Form.Width := 800;
  Form.Height := 400;
  Liste := TRuleListBox.Create(Form, Form, ACheckboxes);
end;

destructor TStand.Destroy;
begin
  // Reihenfolge wie in beiden Wirten: erst die Liste (haengt ihre
  // Ereignisse ab), dann das Fenster, dem die Steuerelemente gehoeren.
  Liste.Free;
  Form.Free;
  inherited;
end;

function TStand.Lv: TListView;
var
  i : Integer;
begin
  Result := nil;
  for i := 0 to Form.ControlCount - 1 do
    if Form.Controls[i] is TListView then
      Exit(TListView(Form.Controls[i]));
end;

function AlleKinds: TFindingKinds;
begin
  Result := TRuleCatalog.GetProfile('strict');
end;

{ ---------------------------------------------------------------- Filter }

procedure TTestRuleListBox.FilterNarrowsShownButNotTotal;
var
  S : TStand;
begin
  S := TStand.Create(False);
  try
    S.Liste.SetKinds(AlleKinds);
    Assert.IsTrue(S.Liste.Total > 100, 'strict sollte den ganzen Katalog fuehren');
    Assert.AreEqual<Integer>(S.Liste.Total, S.Liste.Shown, 'ohne Filter alles');

    S.Liste.SetFilter('SCA001');
    Assert.AreEqual<Integer>(1, S.Liste.Shown, 'genau eine ID trifft');
    // Total ist die Groesse des PROFILS, nicht der Anzeige - sonst haelt
    // die Infozeile die gefilterte Zahl fuer die Groesse des Profils.
    Assert.IsTrue(S.Liste.Total > 100, 'Total darf sich durch den Filter nicht aendern');
  finally
    S.Free;
  end;
end;

procedure TTestRuleListBox.FilterIsCaseInsensitive;
var
  S : TStand;
  A : Integer;
begin
  S := TStand.Create(False);
  try
    S.Liste.SetKinds(AlleKinds);
    S.Liste.SetFilter('MemoryLeak');
    A := S.Liste.Shown;
    Assert.IsTrue(A > 0, 'MemoryLeak muss treffen');
    S.Liste.SetFilter('memoryleak');
    Assert.AreEqual<Integer>(A, S.Liste.Shown,
      'Schreibweise darf die Trefferzahl nicht aendern');
  finally
    S.Free;
  end;
end;

procedure TTestRuleListBox.FilterMatchesKindToken;
// Der Kind-Token ist das, was in einem Profil steht - danach zu suchen
// ist der eigentliche Zweck des Feldes.
var
  S : TStand;
begin
  S := TStand.Create(False);
  try
    S.Liste.SetKinds(AlleKinds);
    S.Liste.SetFilter('Dfm');
    Assert.IsTrue(S.Liste.Shown > 10,
      'die DFM-Familie sollte ueber ihren Token auffindbar sein');
    Assert.IsTrue(S.Liste.Shown < S.Liste.Total, 'aber nicht alles');
  finally
    S.Free;
  end;
end;

procedure TTestRuleListBox.EmptyFilterShowsEverything;
var
  S : TStand;
begin
  S := TStand.Create(False);
  try
    S.Liste.SetKinds(AlleKinds);
    S.Liste.SetFilter('SCA001');
    S.Liste.SetFilter('   ');   // nur Leerraum = kein Filter
    Assert.AreEqual<Integer>(S.Liste.Total, S.Liste.Shown,
      'ein Filter aus Leerraum ist keiner');
    Assert.AreEqual('', S.Liste.FilterText);
  finally
    S.Free;
  end;
end;

{ ----------------------------------------------------------- Sortierung }

procedure TTestRuleListBox.SortByIdIsStableAcrossRebuilds;
// Spalte 0 (ID) hat keinen eigenen Vergleicher - sie faellt auf den
// zweiten Schluessel zurueck, der ebenfalls die ID ist. Der Test haelt
// fest, dass genau das eine STABILE Reihenfolge ergibt.
var
  S      : TStand;
  Erste  : string;
  Zweite : string;
begin
  S := TStand.Create(False);
  try
    S.Liste.SetKinds(AlleKinds);
    S.Liste.SortBy(0, False);
    Erste := S.Lv.Items[0].Caption;
    // Neu aufbauen, ohne die Sortierung anzufassen.
    S.Liste.SetKinds(AlleKinds);
    Zweite := S.Lv.Items[0].Caption;
    Assert.AreEqual(Erste, Zweite,
      'gleicher Inhalt, gleiche Sortierung - andere erste Zeile');
    Assert.AreEqual('SCA001', Erste, 'aufsteigend nach ID beginnt bei SCA001');
  finally
    S.Free;
  end;
end;

procedure TTestRuleListBox.SortDescendingReversesFirstRow;
var
  S    : TStand;
  Auf  : string;
  Ab   : string;
begin
  S := TStand.Create(False);
  try
    S.Liste.SetKinds(AlleKinds);
    S.Liste.SortBy(0, False);
    Auf := S.Lv.Items[0].Caption;
    S.Liste.SortBy(0, True);
    Ab := S.Lv.Items[0].Caption;
    Assert.AreNotEqual(Auf, Ab, 'absteigend muss oben etwas anderes zeigen');
    Assert.AreEqual(Auf, S.Lv.Items[S.Lv.Items.Count - 1].Caption,
      'was aufsteigend oben stand, steht absteigend unten');
  finally
    S.Free;
  end;
end;

{ ---------------------------------------------------------------- Haken }

procedure TTestRuleListBox.CheckSurvivesFilterChange;
// DER Test dieser Klasse. Nach "Dfm" filtern, ankreuzen, nach "Leak"
// filtern, ankreuzen - beide Haken muessen stehen. Ohne FChecked waere
// der erste beim zweiten Fill verloren, und der Auswahldialog haette
// stillschweigend die halbe Auswahl vergessen.
var
  S : TStand;
begin
  S := TStand.Create(True);
  try
    S.Liste.SetKinds(AlleKinds);

    S.Liste.SetFilter('SCA001');
    Assert.AreEqual<Integer>(1, S.Liste.Shown, 'Vorbedingung: genau eine Zeile');
    S.Lv.Items[0].Checked := True;
    Assert.AreEqual<Integer>(1, S.Liste.CheckedCount);

    S.Liste.SetFilter('SCA002');
    Assert.AreEqual<Integer>(1, S.Liste.Shown, 'Vorbedingung: genau eine Zeile');
    Assert.IsFalse(S.Lv.Items[0].Checked,
      'die zweite Regel darf nicht vorangekreuzt sein');
    S.Lv.Items[0].Checked := True;

    Assert.AreEqual<Integer>(2, S.Liste.CheckedCount,
      'der Haken aus dem ersten Filter ist verloren gegangen');

    // Und er ist auch wieder SICHTBAR, wenn der Filter faellt.
    S.Liste.SetFilter('');
    Assert.AreEqual<Integer>(2, S.Liste.CheckedCount);
    Assert.IsTrue(fkMemoryLeak in S.Liste.CheckedKinds, 'SCA001 fehlt');
    Assert.IsTrue(fkEmptyExcept in S.Liste.CheckedKinds, 'SCA002 fehlt');
  finally
    S.Free;
  end;
end;

procedure TTestRuleListBox.UncheckRemovesFromSet;
var
  S : TStand;
begin
  S := TStand.Create(True);
  try
    S.Liste.SetKinds(AlleKinds);
    S.Liste.SetFilter('SCA001');
    S.Lv.Items[0].Checked := True;
    Assert.AreEqual<Integer>(1, S.Liste.CheckedCount);
    S.Lv.Items[0].Checked := False;
    Assert.AreEqual<Integer>(0, S.Liste.CheckedCount,
      'ein entfernter Haken muss auch aus FChecked verschwinden');
    Assert.IsFalse(fkMemoryLeak in S.Liste.CheckedKinds);
  finally
    S.Free;
  end;
end;

procedure TTestRuleListBox.CheckedIsEmptyWithoutCheckboxes;
// Das Profil-Fenster baut die Liste OHNE Haken, dafuer mit
// Mehrfachauswahl. CheckedKinds muss dort leer bleiben, damit niemand
// versehentlich die Auswahl mit den Haken verwechselt.
var
  S : TStand;
begin
  S := TStand.Create(False);
  try
    S.Liste.SetKinds(AlleKinds);
    Assert.AreEqual<Integer>(0, S.Liste.CheckedCount);
    Assert.IsTrue(S.Liste.CheckedKinds = [], 'ohne Haken keine angehakten Kinds');
  finally
    S.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRuleListBox);

end.
