unit uTestUnusedUsesSuchtext;

// Tests fuer den Tempo-Umbau von SCA007 UnusedUses (Charge P1, 2026-10-25).
//
// Bis dahin pruefte H1 mit Pos(Praefix + '.', RawText) und H2 mit
// Pos(' ' + Id + ' ', WordText) - je Bezeichner ein Durchlauf ueber den
// ganzen Suchtext. Seitdem: Punkt-Index (PraefixVorPunkt), Wortmenge
// (SammleWoerter), Zeichenabbildung je Teilstring (RawSicht) und der Strip
// aus dem Scan-Kontext. VERHALTEN IDENTISCH ist der Vertrag:
//   * die Baustein-Tests vergleichen jede Antwort mit der ALTEN Pos-Form
//     als Orakel (die Randfaelle des Umbaus: leeres Praefix, Treffer
//     mitten im Wort, Punkte im Praefix, Text-Anfang, Doppelpunkte);
//   * die Datei-Tests pinnen das Detektorverhalten an den Grenzen der
//     neuen Wortmenge (Gross-/Kleinschreibung, Wort nach/vor Punkt,
//     Teilwoerter, Kommentare/Strings, Reihenfolge, Kontext-Weg).
// Die Datei-Tests waren vor dem Umbau ebenso gruen - sie sind Pins, keine
// Rot-Gruen-Tests; die Baustein-Tests kompilieren ohne den Umbau nicht.
// Eigene Fixture, damit uTestUnusedUses (58 Tests) nicht weiter waechst.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

type
  [TestFixture]
  TTestUnusedUsesSuchtext = class
  public
    // ---- Bausteine gegen die alte Pos-Form ----
    [Test] procedure PraefixVorPunkt_GleichPosForm;
    [Test] procedure PraefixVorPunkt_TrefferMittenImWort;
    [Test] procedure PunktPositionen_EinsBasiertAufsteigend;
    [Test] procedure SammleWoerter_GleichPosFormAufWordText;
    [Test] procedure SammleWoerter_PunktTrenntWoerter;
    [Test] procedure RawSicht_ZeichenmengeWieFrueher;
    [Test] procedure IdentsFor_Dotless_GleichKnownIdents;
    // ---- Charge Q5: Wortabfrage ohne Wortmenge, AST-Teil mit einem
    //      ToLower - Orakel ist die Form von Charge P1 ----
    [Test] procedure WoerterVorhanden_GleichSammleWoerter;
    [Test] procedure AstSuchtext_GleichFormJeName;
    // ---- Detektor an den Grenzen der Wortmenge ----
    [Test] procedure Datei_H1_TrefferMittenImWort_NoFinding;
    [Test] procedure Datei_H2_Grossschreibung_NoFinding;
    [Test] procedure Datei_H2_IdentNachPunkt_NoFinding;
    [Test] procedure Datei_H2_NurTeilwoerter_ReportsWarning;
    [Test] procedure Datei_H2_NurKommentarUndString_ReportsWarning;
    [Test] procedure Datei_H2_NurImLiteralMitApostroph_ReportsWarning;
    [Test] procedure Datei_ZweiGemappteUnits_NurUngenutzteGemeldet;
    [Test] procedure Datei_Reihenfolge_ZeilenUndNamen;
    [Test] procedure Datei_MitKontext_GleichOhneKontext;
  end;

implementation

uses
  System.IOUtils,   // TPath/TFile (Tempdatei-Harness)
  uAstNode, uParser2, uAnalyzeContext,
  uUnusedUses;

{ ---- Harness ---- }

// Der Quelltext-Kanal braucht eine ECHTE Datei (FindingsOf uebergibt einen
// Platzhalter-Namen und prueft nur den AST-Weg) - Muster FindingsAusDatei
// in uTestUnusedUses, hier mit optionalem Scan-Kontext.
function FindingsAusDatei(const Source: string;
  Ctx: TAnalyzeContext = nil; Wiederholen: Integer = 1): TObjectList<TLeakFinding>;
var
  Parser   : TParser2;
  Root     : TAstNode;
  TempPath : string;
  SL       : TStringList;
  i        : Integer;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  TempPath := TPath.Combine(TPath.GetTempPath,
    'sca_usesp1_' + TGuid.NewGuid.ToString
      .Replace('{', '').Replace('}', '').Replace('-', '') + '.pas');
  SL := TStringList.Create;
  try
    SL.Text := Source;
    SL.SaveToFile(TempPath, TEncoding.UTF8);
  finally
    SL.Free;
  end;
  try
    Parser := TParser2.Create;
    try
      Root := Parser.ParseFile(TempPath);
      try
        // Wiederholen > 1: dieselbe Datei mehrfach mit DEMSELBEN Kontext -
        // ab dem zweiten Lauf kommt der Strip aus dem Kontext-Slot. Nur
        // die Funde des LETZTEN Laufs bleiben stehen.
        for i := 1 to Wiederholen do
        begin
          Result.Clear;
          TUnusedUsesDetector.AnalyzeUnit(Root, TempPath, Result, Ctx);
        end;
      finally
        Root.Free;
      end;
    finally
      Parser.Free;
    end;
  finally
    if TFile.Exists(TempPath) then TFile.Delete(TempPath);
  end;
end;

// Name@Zeile je Fund, in Ergebnisreihenfolge.
function Beschreibung(F: TObjectList<TLeakFinding>): string;
var
  i : Integer;
begin
  Result := '';
  for i := 0 to F.Count - 1 do
    if F[i].Kind = fkUnusedUses then
      Result := Result + F[i].MissingVar + '@' + F[i].LineNumber + ';';
end;

function AltH1(const Text, Praefix: string): Boolean;
begin
  Result := Pos(Praefix + '.', Text) > 0;   // die Form vor Charge P1
end;

function AltH2(const Text, Id: string): Boolean;
begin
  Result := Pos(' ' + Id + ' ', Text.Replace('.', ' ')) > 0;   // dito
end;

{ ---- Bausteine ---- }

procedure TTestUnusedUsesSuchtext.PraefixVorPunkt_GleichPosForm;
// Jede Zeile: Text|Praefix. Erwartung ist IMMER die alte Pos-Form.
const
  FAELLE: array[0..15] of string = (
    ' classes.tstringlist |classes',
    ' sysutils.inttostr |classes',
    ' vcl.dialogs.showmessage |vcl.dialogs',
    ' vcl.dialogs.showmessage |dialogs',
    ' vcl.dialogsx.foo |vcl.dialogs',
    ' classes |classes',             // kein Punkt dahinter
    ' classes .x |classes',          // Leerzeichen vor dem Punkt
    '.x |',                          // leeres Praefix, Punkt an Position 1
    ' x |',                          // leeres Praefix, kein Punkt
    'classes.x|classes',             // Praefix am Textanfang
    ' a..b |a.',                     // Praefix endet auf Punkt
    ' a..b |a',
    ' ab |abc',                      // Praefix laenger als Text
    ' s.classes.x |s.classes',
    ' xclasses.y classes |classes',  // nur der Treffer mitten im Wort
    '|classes');                     // leerer Text
var
  Fall, Text, Praefix : string;
  p                   : Integer;
begin
  for Fall in FAELLE do
  begin
    p := Pos('|', Fall);
    Text    := Copy(Fall, 1, p - 1);
    Praefix := Copy(Fall, p + 1, MaxInt);
    Assert.IsTrue(
      TUnusedUsesDetector.PraefixVorPunkt(Text,
        TUnusedUsesDetector.PunktPositionen(Text), Praefix) = AltH1(Text, Praefix),
      'PraefixVorPunkt weicht von Pos(Praefix + ''.'') ab: "' + Fall + '"');
  end;
end;

procedure TTestUnusedUsesSuchtext.PraefixVorPunkt_TrefferMittenImWort;
// Der unscheinbare Teil des alten H1-Vertrags: Pos sucht ohne Wortgrenze,
// 'myclasses.foo' deckte 'classes'. Der Punkt-Index muss das erhalten -
// eine "Verbesserung" auf Wortgrenzen waere eine Fundbewegung.
const
  T = ' myclasses.foo ';
begin
  Assert.IsTrue(TUnusedUsesDetector.PraefixVorPunkt(T,
    TUnusedUsesDetector.PunktPositionen(T), 'classes'),
    'Treffer mitten im Wort bleibt ein H1-Nachweis');
  Assert.IsFalse(TUnusedUsesDetector.PraefixVorPunkt(T,
    TUnusedUsesDetector.PunktPositionen(T), 'foo'),
    'nach foo folgt kein Punkt');
end;

procedure TTestUnusedUsesSuchtext.PunktPositionen_EinsBasiertAufsteigend;
var
  P : TArray<Integer>;
begin
  P := TUnusedUsesDetector.PunktPositionen(' a.b..c.');
  Assert.AreEqual<Integer>(4, Length(P), 'vier Punkte');
  Assert.AreEqual<Integer>(3, P[0]);
  Assert.AreEqual<Integer>(5, P[1]);
  Assert.AreEqual<Integer>(6, P[2]);
  Assert.AreEqual<Integer>(8, P[3]);
  Assert.AreEqual<Integer>(0, Length(TUnusedUsesDetector.PunktPositionen('')),
    'leerer Text');
  Assert.AreEqual<Integer>(0, Length(TUnusedUsesDetector.PunktPositionen(' ab ')),
    'Text ohne Punkt');
end;

procedure TTestUnusedUsesSuchtext.SammleWoerter_GleichPosFormAufWordText;
// Vorbedingung des Vertrags wie in AnalyzeUnit: Text leer oder mit ' '
// umrahmt, Id ohne Leerzeichen. Erwartung ist IMMER die alte Pos-Form.
const
  TEXTE: array[0..5] of string = (
    '',
    ' tstringlist ',
    ' obj.tstringlist.create ',
    ' tstringlistex mytstringlist tstringlist_2 ',
    ' a..b . .c. ',
    ' tlist  tobjectlist tlist ');
  IDS: array[0..8] of string = (
    'tstringlist', 'create', 'obj', 'tlist', 'tobjectlist', 'a', 'b', 'c',
    'obj.tstringlist');
var
  Text, Id : string;
  W        : TDictionary<string, Boolean>;
begin
  for Text in TEXTE do
  begin
    W := TDictionary<string, Boolean>.Create;
    try
      TUnusedUsesDetector.SammleWoerter(Text, W);
      for Id in IDS do
        Assert.IsTrue(W.ContainsKey(Id) = AltH2(Text, Id),
          'Wortmenge weicht von Pos('' '' + Id + '' '') ab: Text="' + Text +
          '" Id="' + Id + '"');
    finally
      W.Free;
    end;
  end;
end;

procedure TTestUnusedUsesSuchtext.SammleWoerter_PunktTrenntWoerter;
// Der Punkt trennt Woerter wie das Leerzeichen - WordText war RawText mit
// '.' -> ' '. Ein Wort mit Punkt kommt nie in die Menge.
var
  W : TDictionary<string, Boolean>;
begin
  W := TDictionary<string, Boolean>.Create;
  try
    TUnusedUsesDetector.SammleWoerter(' obj.tstringlist.create  x ', W);
    Assert.AreEqual<Integer>(4, W.Count, 'obj, tstringlist, create, x');
    Assert.IsTrue(W.ContainsKey('tstringlist'), 'Wort zwischen zwei Punkten');
    Assert.IsTrue(W.ContainsKey('obj'), 'Wort vor dem Punkt');
    Assert.IsTrue(W.ContainsKey('create'), 'Wort nach dem Punkt');
    Assert.IsFalse(W.ContainsKey('obj.tstringlist'), 'nie ein Wort mit Punkt');
  finally
    W.Free;
  end;
end;

procedure TTestUnusedUsesSuchtext.WoerterVorhanden_GleichSammleWoerter;
// Orakel: SammleWoerter + ContainsKey (Charge P1). Randfaelle: leeres Id,
// Id mit Punkt/Leerzeichen, doppeltes Id, Wort am Textanfang/-ende, ohne
// umrahmende Leerzeichen, Teilwoerter, gleiches Fach (Laenge und erstes
// Zeichen) bei verschiedenen Woertern, alle Ids gefunden (vorzeitiger
// Schluss).
const
  TEXTE: array[0..7] of string = (
    '',
    ' tstringlist ',
    'tstringlist',
    ' obj.tstringlist.create ',
    ' tstringlistex mytstringlist tstringlist_2 ',
    ' a..b . .c. ',
    ' tlist  tobjectlist tlist ',
    ' tlisx tlist tmemo tmema t ');
  ID_TABELLE: array[0..12] of string = (
    'tstringlist', 'create', 'obj', 'tlist', 'tobjectlist', 'a', 'b', 'c',
    'obj.tstringlist', '', 'tlist', 'tmemo', 'x y');
var
  Text : string;
  W    : TDictionary<string, Boolean>;
  Da   : TArray<Boolean>;
  Ids  : TArray<string>;
  k    : Integer;
begin
  SetLength(Ids, Length(ID_TABELLE));
  for k := 0 to High(ID_TABELLE) do
    Ids[k] := ID_TABELLE[k];
  for Text in TEXTE do
  begin
    W := TDictionary<string, Boolean>.Create;
    try
      TUnusedUsesDetector.SammleWoerter(Text, W);
      Da := TUnusedUsesDetector.WoerterVorhanden(Text, Ids);
      Assert.AreEqual<Integer>(Length(Ids), Length(Da), 'ein Eintrag je Id');
      for k := 0 to High(Ids) do
        Assert.IsTrue(Da[k] = W.ContainsKey(Ids[k]),
          'WoerterVorhanden weicht von der Wortmenge ab: Text="' + Text +
          '" Id="' + Ids[k] + '"');
    finally
      W.Free;
    end;
  end;
  // Alle gefunden: der vorzeitige Schluss laesst keinen Eintrag aus.
  Da := TUnusedUsesDetector.WoerterVorhanden(' a b a c ', ['c', 'a', 'b', 'a']);
  Assert.IsTrue(Da[0] and Da[1] and Da[2] and Da[3], 'alle vier gefunden');
  Assert.AreEqual<Integer>(0, Length(TUnusedUsesDetector.WoerterVorhanden(' a ', nil)),
    'keine Ids');
end;

procedure TTestUnusedUsesSuchtext.AstSuchtext_GleichFormJeName;
// Orakel: die Form von Charge P1 - je nichtleerem Name/TypeRef (ausser
// nkUsesItem) ' ' + RawSicht(OhneLiterale(S).ToLower) + ' ' in
// Baumreihenfolge. Namen mit Grossbuchstaben, Nicht-ASCII (Umlaut,
// tuerkisches I mit Punkt, Kelvin-Zeichen), Literalen und Punkten.
var
  Root, Cls, M : TAstNode;

  function AltForm(N: TAstNode): string;
    function Teil(const S: string): string;
    begin
      if S = '' then Exit('');
      Result := ' ' + TUnusedUsesDetector.RawSicht(
        TUnusedUsesDetector.OhneLiterale(S).ToLower) + ' ';
    end;
  var
    i : Integer;
  begin
    Result := '';
    if N.Kind <> nkUsesItem then
      Result := Teil(N.Name) + Teil(N.TypeRef);
    for i := 0 to N.Children.Count - 1 do
      Result := Result + AltForm(N.Children[i]);
  end;

begin
  Root := TAstNode.Create(nkUnit, 'MyUnit');
  try
    Root.Add(nkUsesItem, 'System.Classes');
    Cls := Root.Add(nkClass, 'TFooBar');
    Cls.TypeRef := 'TObjectList<TStringList>';
    M := Cls.Add(nkMethod, #$00C4 + 'rger' + #$0130 + 'STANBUL' + #$212A);
    M.TypeRef := 'Vcl.Dialogs.TOpenDialog';
    M.Add(nkUnknown, '''it''''s TList''');
    M.Add(nkUnknown, '');
    M.Add(nkUnknown, 'X'' Y');
    Root.Add(nkUnknown, 'SysUtils.IntToStr');
    Assert.AreEqual(AltForm(Root), TUnusedUsesDetector.AstSuchtext(Root),
      'AstSuchtext = Form je Name');
    Assert.IsTrue(Pos(' tobjectlist tstringlist ',
      TUnusedUsesDetector.AstSuchtext(Root)) > 0, 'TypeRef klein und getrennt');
    Assert.IsTrue(Pos('system.classes', TUnusedUsesDetector.AstSuchtext(Root)) = 0,
      'nkUsesItem bleibt draussen');
    // Wortgrenzen: 'tlist' steckt als Teilfolge in 'tobjectlist' (TypeRef
    // der Klasse) - die Pruefung gilt dem WORT aus dem Literal, so wie H2
    // fragt (' ' + Id + ' '). Bis 2026-10-25 stand hier Pos('tlist') und
    // war an genau diesem Teilwort rot, obwohl die Gleichheit oben hielt.
    Assert.IsTrue(Pos(' tlist ', TUnusedUsesDetector.AstSuchtext(Root)) = 0,
      'Literalinhalt bleibt draussen');
    Assert.IsTrue(Pos(' it ', TUnusedUsesDetector.AstSuchtext(Root)) = 0,
      'Literalinhalt vor dem verdoppelten Apostroph bleibt draussen');
    // Das offene Literal in 'X'' Y' endet mit seinem Namen - es darf den
    // naechsten Namen in der Verkettung nicht verschlucken.
    Assert.IsTrue(Pos(' x ', TUnusedUsesDetector.AstSuchtext(Root)) > 0,
      'Text vor dem offenen Literal bleibt');
    Assert.IsTrue(Pos(' sysutils.inttostr ', TUnusedUsesDetector.AstSuchtext(Root)) > 0,
      'Name hinter einem offenen Literal bleibt sichtbar');
  finally
    Root.Free;
  end;
end;

procedure TTestUnusedUsesSuchtext.RawSicht_ZeichenmengeWieFrueher;
// Frueher: CharInSet(Ch, ['a'..'z', '0'..'9', '_', '.']) je Zeichen.
// Grossbuchstaben kommen im Detektor nie an (der Text ist lowercase) und
// fallen deshalb wie jedes andere Zeichen auf ' '; ebenso Zeichen ab
// #$80 (CharInSet war dort False). Die Laenge bleibt gleich.
begin
  Assert.AreEqual('ab.c_9 x y  ', TUnusedUsesDetector.RawSicht('ab.c_9-x(y);'),
    'Satzzeichen werden Leerzeichen, Punkt und Unterstrich bleiben');
  Assert.AreEqual(' z', TUnusedUsesDetector.RawSicht('Az'),
    'Grossbuchstabe faellt auf Leerzeichen');
  Assert.AreEqual('a  b', TUnusedUsesDetector.RawSicht('a' + #$00E4 + #$0101 + 'b'),
    'Zeichen ab #$80 fallen auf Leerzeichen');
  Assert.AreEqual('', TUnusedUsesDetector.RawSicht(''), 'leerer Text');
  Assert.AreEqual('  ', TUnusedUsesDetector.RawSicht('~' + #10),
    'Strip-Fuellzeichen und Zeilenumbruch');
end;

procedure TTestUnusedUsesSuchtext.IdentsFor_Dotless_GleichKnownIdents;
// IdentsFor ruft KnownIdents fuer einen dotless Namen nur noch EINMAL
// (der Kurzname ist der Name selbst) - Antwort unveraendert.
begin
  Assert.AreEqual(string.Join(',', TUnusedUsesDetector.KnownIdents('classes')),
    string.Join(',', TUnusedUsesDetector.IdentsFor('classes')),
    'gemappter dotless Name');
  Assert.AreEqual<Integer>(0, Length(TUnusedUsesDetector.IdentsFor('meinzeug')),
    'ungemappter dotless Name bleibt leer');
  Assert.AreEqual(string.Join(',', TUnusedUsesDetector.KnownIdents('styles')),
    string.Join(',', TUnusedUsesDetector.IdentsFor('fmx.styles')),
    'Kurznamen-Rueckfall fuer RTL-Namespaces bleibt');
end;

{ ---- Detektor ---- }

procedure TTestUnusedUsesSuchtext.Datei_H1_TrefferMittenImWort_NoFinding;
// 'MyClasses.Wert' enthaelt 'classes.' - unter dem alten Pos-Vertrag ein
// H1-Nachweis fuer Classes (kein Bezeichner der Classes-Liste im Code).
var F: TObjectList<TLeakFinding>;
begin
  F := FindingsAusDatei(
    'unit t;'#13#10+
    'interface'#13#10+
    'uses Classes;'#13#10+
    'implementation'#13#10+
    'procedure P;'#13#10+
    'begin'#13#10+
    '  MyClasses.Wert := 1;'#13#10+
    'end;'#13#10+
    'end.');
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'Treffer mitten im Wort deckt Classes wie zuvor');
  finally F.Free; end;
end;

procedure TTestUnusedUsesSuchtext.Datei_H2_Grossschreibung_NoFinding;
var F: TObjectList<TLeakFinding>;
begin
  F := FindingsAusDatei(
    'unit t;'#13#10+
    'interface'#13#10+
    'uses Classes;'#13#10+
    'implementation'#13#10+
    'procedure P;'#13#10+
    'begin'#13#10+
    '  FreeAndNil(TSTRINGLIST(X));'#13#10+
    'end;'#13#10+
    'end.');
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'TSTRINGLIST in Grossschrift ist ein H2-Nachweis');
  finally F.Free; end;
end;

procedure TTestUnusedUsesSuchtext.Datei_H2_IdentNachPunkt_NoFinding;
// 'Obj.TStrings' - kein 'classes.' (H1 schweigt), aber 'tstrings' ist
// nach dem Punkt ein eigenes Wort (WordText trennte am Punkt).
var F: TObjectList<TLeakFinding>;
begin
  F := FindingsAusDatei(
    'unit t;'#13#10+
    'interface'#13#10+
    'uses Classes;'#13#10+
    'implementation'#13#10+
    'procedure P;'#13#10+
    'begin'#13#10+
    '  Obj.TStrings.Clear;'#13#10+
    'end;'#13#10+
    'end.');
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedUses),
      'Wort zwischen zwei Punkten ist ein H2-Nachweis');
  finally F.Free; end;
end;

procedure TTestUnusedUsesSuchtext.Datei_H2_NurTeilwoerter_ReportsWarning;
// Gegenprobe: nur Woerter, die tstringlist ENTHALTEN, aber nicht SIND.
var F: TObjectList<TLeakFinding>;
begin
  F := FindingsAusDatei(
    'unit t;'#13#10+
    'interface'#13#10+
    'uses Classes;'#13#10+
    'implementation'#13#10+
    'procedure P;'#13#10+
    'begin'#13#10+
    '  TStringListEx(X); MyTStringList(X); TStringList_2(X);'#13#10+
    'end;'#13#10+
    'end.');
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedUses),
      'Teilwoerter sind kein Nachweis - Classes bleibt ein Fund');
  finally F.Free; end;
end;

procedure TTestUnusedUsesSuchtext.Datei_H2_NurKommentarUndString_ReportsWarning;
// Kommentare und Strings zaehlen nie als Code - auch nicht ueber den
// Kontext-Strip.
var F: TObjectList<TLeakFinding>;
begin
  F := FindingsAusDatei(
    'unit t;'#13#10+
    'interface'#13#10+
    'uses Classes;'#13#10+
    'implementation'#13#10+
    '{ TStringList }'#13#10+
    '(* Classes.TStrings *)'#13#10+
    'procedure P;'#13#10+
    'begin'#13#10+
    '  // TStringList'#13#10+
    '  Log(''TStringList Classes.TList'');'#13#10+
    'end;'#13#10+
    'end.');
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedUses),
      'Bezeichner nur in Kommentar und String - Classes bleibt ein Fund');
  finally F.Free; end;
end;

procedure TTestUnusedUsesSuchtext.Datei_H2_NurImLiteralMitApostroph_ReportsWarning;
// Charge Q5 (AST-Teil verkettet, EIN ToLower): mehrere Literale in
// mehreren AST-Namen, eines mit verdoppeltem Apostroph, eines nur aus
// einem Apostroph. TStringList steht nur im Literal -> Classes bleibt ein
// Fund; ShowMessage steht im CODE hinter den Literalen -> Dialogs gedeckt
// (das Ausblenden darf nicht ueber das Literal hinausreichen). Pin - vor
// Q5 ebenso gruen.
var F: TObjectList<TLeakFinding>;
begin
  F := FindingsAusDatei(
    'unit t;'#13#10+
    'interface'#13#10+
    'uses Classes, Dialogs;'#13#10+
    'implementation'#13#10+
    'procedure P;'#13#10+
    'begin'#13#10+
    '  Log(''it''''s TStringList'');'#13#10+
    '  Log('''''''');'#13#10+
    '  ShowMessage(''y'');'#13#10+
    'end;'#13#10+
    'end.');
  try
    Assert.AreEqual('Classes@3;', Beschreibung(F),
      'Literalinhalt ist kein Nachweis, Code hinter Literalen schon');
  finally F.Free; end;
end;

procedure TTestUnusedUsesSuchtext.Datei_ZweiGemappteUnits_NurUngenutzteGemeldet;
// Die Wortmenge wird je Datei EINMAL gebaut und fuer die zweite gemappte
// Unit wiederverwendet - beide Antworten muessen stimmen.
var F: TObjectList<TLeakFinding>;
begin
  F := FindingsAusDatei(
    'unit t;'#13#10+
    'interface'#13#10+
    'uses Classes, Graphics;'#13#10+
    'implementation'#13#10+
    'procedure P;'#13#10+
    'begin'#13#10+
    '  B := TBitmap.Create;'#13#10+
    'end;'#13#10+
    'end.');
  try
    Assert.AreEqual('Classes@3;', Beschreibung(F),
      'nur Classes ungenutzt, Graphics durch TBitmap gedeckt');
  finally F.Free; end;
end;

procedure TTestUnusedUsesSuchtext.Datei_Reihenfolge_ZeilenUndNamen;
// Reihenfolge, Namen (Originalschreibweise) und Zeilen der Funde sind Teil
// des Identitaetsvertrags; die genutzte Unit dazwischen bleibt still.
var F: TObjectList<TLeakFinding>;
begin
  F := FindingsAusDatei(
    'unit t;'#13#10+
    'interface'#13#10+
    'uses'#13#10+
    '  Graphics,'#13#10+
    '  Classes,'#13#10+
    '  Menus,'#13#10+
    '  Dialogs;'#13#10+
    'implementation'#13#10+
    'procedure P;'#13#10+
    'begin'#13#10+
    '  ShowMessage(''x'');'#13#10+
    'end;'#13#10+
    'end.');
  try
    Assert.AreEqual('Graphics@4;Classes@5;Menus@6;', Beschreibung(F),
      'drei Funde in uses-Reihenfolge, Dialogs gedeckt');
  finally F.Free; end;
end;

procedure TTestUnusedUsesSuchtext.Datei_MitKontext_GleichOhneKontext;
// Der Kontext-Weg (Zeilen- und Strip-Cache) muss dieselbe Antwort geben wie
// der Weg ohne Kontext - beim ersten Lauf (Strip gerechnet und abgelegt)
// und beim zweiten (Strip aus dem Kontext-Slot).
const
  SRC =
    'unit t;'#13#10+
    'interface'#13#10+
    'uses Classes, Graphics, Dialogs, Menus;'#13#10+
    'implementation'#13#10+
    'procedure P;'#13#10+
    'begin'#13#10+
    '  // TPopupMenu'#13#10+
    '  L := TStringList.Create;'#13#10+
    '  Log(''TBitmap'');'#13#10+
    'end;'#13#10+
    'end.';
var
  Ohne, Mit1, Mit2 : TObjectList<TLeakFinding>;
  Ctx              : TAnalyzeContext;
begin
  Ohne := FindingsAusDatei(SRC);
  Ctx  := TAnalyzeContext.Create;
  Mit1 := nil;
  Mit2 := nil;
  try
    Mit1 := FindingsAusDatei(SRC, Ctx, 1);
    Mit2 := FindingsAusDatei(SRC, Ctx, 2);
    Assert.AreEqual('Graphics@3;Dialogs@3;Menus@3;', Beschreibung(Ohne),
      'ohne Kontext: Classes gedeckt, Kommentar/String sind kein Nachweis');
    Assert.AreEqual(Beschreibung(Ohne), Beschreibung(Mit1),
      'mit Kontext, erster Lauf');
    Assert.AreEqual(Beschreibung(Ohne), Beschreibung(Mit2),
      'mit Kontext, Strip aus dem Kontext-Slot');
  finally
    Mit2.Free;
    Mit1.Free;
    Ctx.Free;
    Ohne.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUnusedUsesSuchtext);

end.
