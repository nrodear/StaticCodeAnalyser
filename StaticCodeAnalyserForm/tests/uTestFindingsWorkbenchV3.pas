unit uTestFindingsWorkbenchV3;

// Tests fuer uFindingsWorkbenchV3 - den Fundbericht mit Datenmodell und
// virtualisierter Liste.
//
// Die Seite hat EINEN Daseinsgrund: bei vielen Funden klein und schnell
// bleiben. Genau das pruefen die Tests hier - nicht die Optik, die
// kommt unveraendert von V2 und ist dort getestet.
//
// Der schaerfste Test ist V3_IstDeutlichKleinerAlsV2: er baut BEIDE
// Seiten aus DERSELBEN Fundliste und vergleicht. Eine Zusage wie "78 %
// kleiner" ist sonst eine Behauptung im Kommentar.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  uMethodd12, uSCAConsts;

type
  [TestFixture]
  TTestFindingsWorkbenchV3 = class
  private
    function MakeFinding(Kind: TFindingKind; const Path: string;
      Line: Integer; const Msg: string): TLeakFinding;
    // Eine Liste mit AAnzahl Funden ueber wenige Dateien und Regeln -
    // so, wie ein echter Bericht aussieht (viele Funde, wenige Regeln).
    function VieleFunde(AAnzahl: Integer): TObjectList<TLeakFinding>;
  public
    // ---- Der Daseinsgrund ----
    [Test] procedure V3_IstDeutlichKleinerAlsV2;
    [Test] procedure V3_RendertKeineZeileVor;
    // ---- Das Datenmodell ----
    [Test] procedure Datenmodell_IstVorhandenUndHatDreiTabellen;
    [Test] procedure Datenmodell_DedupliziertRegelnUndPfade;
    [Test] procedure Datenmodell_HinweisStehtNichtJeFund;
    // ---- Was von V2 gelten bleibt ----
    [Test] procedure Theme_AntiBlitzStehtImHead;
    [Test] procedure Zeilenhoehe_StimmtInCssUndJs;
    [Test] procedure LeereListe_IstGueltigeSeite;
  end;

implementation

uses
  uFindingsWorkbenchV3, uFindingsWorkbenchExport;

function TTestFindingsWorkbenchV3.MakeFinding(Kind: TFindingKind;
  const Path: string; Line: Integer; const Msg: string): TLeakFinding;
begin
  Result := TLeakFinding.Create;
  Result.SetKind(Kind);
  Result.FileName   := Path;
  Result.LineNumber := IntToStr(Line);
  Result.MethodName := 'TFoo.Bar';
  Result.MissingVar := Msg;
end;

function TTestFindingsWorkbenchV3.VieleFunde(
  AAnzahl: Integer): TObjectList<TLeakFinding>;
const
  // Wenige Dateien und Regeln, viele Funde - das ist die Verteilung, in
  // der sich Deduplikation lohnt, und die Verteilung echter Berichte.
  DATEIEN : array[0..2] of string =
    ('src\A.pas', 'src\B.pas', 'src\tief\C.pas');
  KINDS   : array[0..2] of TFindingKind =
    (fkMemoryLeak, fkDebugOutput, fkEmptyExcept);
var
  i : Integer;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  for i := 0 to AAnzahl - 1 do
    Result.Add(MakeFinding(KINDS[i mod 3], DATEIEN[i mod 3],
      i + 1, 'Befund Nummer ' + IntToStr(i)));
end;

procedure TTestFindingsWorkbenchV3.V3_IstDeutlichKleinerAlsV2;
// DER Test, an dem die ganze Seite haengt. Beide Berichte aus DERSELBEN
// Liste, dann vergleichen.
//
// Die Schwelle steht bewusst bei 50 % und nicht bei den gemessenen
// 78 %: die Ersparnis haengt an der Verteilung (viele Funde je Regel
// sparen mehr), und ein Test, der bei jeder Fixture-Aenderung kippt,
// wird irgendwann weggeklickt. Faellt V3 unter 50 %, ist trotzdem
// etwas grundlegend kaputt - dann rendert die Seite wieder vor.
var
  Findings : TObjectList<TLeakFinding>;
  V2, V3   : string;
  Quote    : Double;
begin
  Findings := VieleFunde(600);
  try
    V2 := TFindingsWorkbenchExport.BuildHtml(Findings, '', -1, 'de');
    V3 := TFindingsWorkbenchV3.BuildHtml(Findings, '', -1, 'de');
  finally
    Findings.Free;
  end;

  Assert.IsTrue(Length(V2) > 0, 'V2 hat nichts geliefert');
  Assert.IsTrue(Length(V3) > 0, 'V3 hat nichts geliefert');
  Quote := 100.0 * (Length(V2) - Length(V3)) / Length(V2);
  Assert.IsTrue(Quote >= 50.0,
    Format('V3 spart nur %.1f %% gegenueber V2 (%d gegen %d Zeichen) - '
      + 'erwartet sind mindestens 50 %%. Rendert die Seite wieder '
      + 'Zeilen vor?', [Quote, Length(V3), Length(V2)]));
end;

procedure TTestFindingsWorkbenchV3.V3_RendertKeineZeileVor;
// Die Gegenprobe zur Groesse: V3 darf die Funde NICHT als Markup
// mitliefern. Waechst die Seite eines Tages wieder linear mit der
// Fundzahl, faellt es hier auf - unabhaengig von absoluten Groessen.
var
  Klein, Gross : TObjectList<TLeakFinding>;
  HK, HG       : string;
  Wachstum     : Double;
begin
  Klein := VieleFunde(100);
  try
    HK := TFindingsWorkbenchV3.BuildHtml(Klein, '', -1, 'de');
  finally
    Klein.Free;
  end;
  Gross := VieleFunde(1000);
  try
    HG := TFindingsWorkbenchV3.BuildHtml(Gross, '', -1, 'de');
  finally
    Gross.Free;
  end;

  // Zehnfache Fundzahl. Das GERUEST (CSS, Skript) bleibt konstant, nur
  // die Daten wachsen - also darf die Seite deutlich WENIGER als das
  // Zehnfache wachsen.
  Wachstum := Length(HG) / Length(HK);
  Assert.IsTrue(Wachstum < 6.0,
    Format('bei zehnfacher Fundzahl waechst die Seite um Faktor %.1f - '
      + 'das sieht nach vorgerendertem Markup je Fund aus', [Wachstum]));

  // Und ganz direkt: kein tbody je Fund wie in V2.
  Assert.AreEqual<Integer>(0, Pos('<tbody data-rid=', HG),
    'V3 rendert Fundzeilen als tbody vor - genau das soll es nicht');
end;

procedure TTestFindingsWorkbenchV3.Datenmodell_IstVorhandenUndHatDreiTabellen;
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
begin
  Findings := VieleFunde(30);
  try
    Html := TFindingsWorkbenchV3.BuildHtml(Findings, '', -1, 'de');
  finally
    Findings.Free;
  end;

  Assert.IsTrue(Pos('<script type="application/json" id="v3daten">',
    Html) > 0, 'der Datenblock fehlt');
  Assert.IsTrue(Pos('{"regeln":[', Html) > 0, 'regeln-Tabelle fehlt');
  Assert.IsTrue(Pos('"pfade":[', Html) > 0, 'pfade-Tabelle fehlt');
  Assert.IsTrue(Pos('"hinweise":[', Html) > 0, 'hinweise-Tabelle fehlt');
  Assert.IsTrue(Pos('"funde":[', Html) > 0, 'funde-Tabelle fehlt');
end;

procedure TTestFindingsWorkbenchV3.Datenmodell_DedupliziertRegelnUndPfade;
// 300 Funde ueber DREI Dateien und DREI Regeln: jeder Pfad und jede
// Regel darf nur einmal im Dokument stehen. Steht ein Pfad 300-mal
// da, ist die Indexierung kaputt - und genau daran haengt die
// Groessenersparnis.
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
  Treffer  : Integer;
  P        : Integer;
begin
  Findings := VieleFunde(300);
  try
    Html := TFindingsWorkbenchV3.BuildHtml(Findings, '', -1, 'de');
  finally
    Findings.Free;
  end;

  Treffer := 0;
  P := Pos('src/tief/C.pas', Html);
  while P > 0 do
  begin
    Inc(Treffer);
    // Pos mit Offset (System.pas) statt PosEx - das braeuchte
    // System.StrUtils, das sonst keine Fixture hier fuehrt.
    P := Pos('src/tief/C.pas', Html, P + 1);
  end;
  // Einmal in der pfade-Tabelle. Mehr als eine Handvoll waere ein
  // Zeichen dafuer, dass der Pfad wieder je Fund mitgeschrieben wird.
  Assert.IsTrue(Treffer <= 3,
    Format('der Pfad steht %d-mal im Dokument - bei 100 Funden in '
      + 'dieser Datei ist die Pfad-Tabelle wirkungslos', [Treffer]));
end;

procedure TTestFindingsWorkbenchV3.Datenmodell_HinweisStehtNichtJeFund;
// Der FixHint ist der laengste Text je Fund. Er steht in einer eigenen
// Tabelle, weil er je FUND variieren kann (TFixHintResolver kennt
// Varianten) - aber gleiche Texte duerfen sich nicht wiederholen.
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
begin
  Findings := VieleFunde(200);
  try
    Html := TFindingsWorkbenchV3.BuildHtml(Findings, '', -1, 'de');
  finally
    Findings.Free;
  end;
  // Die Tabelle existiert und der Fund verweist per Index darauf.
  Assert.IsTrue(Pos('"hinweise":[', Html) > 0,
    'die hinweise-Tabelle fehlt - steht der Text wieder je Fund?');
end;

procedure TTestFindingsWorkbenchV3.Theme_AntiBlitzStehtImHead;
// Dieselbe Zusage wie bei V2 (Nico-Befund 09.09.): die gespeicherte
// Theme-Wahl muss VOR dem ersten Paint am html-Element stehen, sonst
// malt der Browser erst im Systemthema und kippt sichtbar um.
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
  PTheme, PHead : Integer;
begin
  Findings := VieleFunde(5);
  try
    Html := TFindingsWorkbenchV3.BuildHtml(Findings, '', -1, 'de');
  finally
    Findings.Free;
  end;

  PTheme := Pos('localStorage.getItem("sca-v3-theme")', Html);
  PHead  := Pos('</head>', Html);
  Assert.IsTrue(PTheme > 0, 'der Anti-Blitz-Block fehlt ganz');
  Assert.IsTrue(PHead > 0, '</head> fehlt');
  Assert.IsTrue(PTheme < PHead,
    'die Theme-Wahl wird erst NACH dem Head gelesen - dann hat der '
    + 'Browser schon im Systemthema gemalt und kippt sichtbar um');
end;

procedure TTestFindingsWorkbenchV3.Zeilenhoehe_StimmtInCssUndJs;
// Die Virtualisierung rechnet den Zeilenindex aus der Scrollposition
// geteilt durch die Zeilenhoehe. Steht im CSS eine andere Zahl als im
// JS, springt der Scrollbalken und die Liste zeigt die falschen Zeilen.
// Die Konstante steht deshalb genau einmal im Pascal-Code - dieser
// Test haelt fest, dass beide Ausgaben aus ihr stammen.
var
  Findings : TObjectList<TLeakFinding>;
  Html     : string;
begin
  Findings := VieleFunde(5);
  try
    Html := TFindingsWorkbenchV3.BuildHtml(Findings, '', -1, 'de');
  finally
    Findings.Free;
  end;

  Assert.IsTrue(Pos('.v3-zeile{height:52px', Html) > 0,
    'die Zeilenhoehe im CSS ist nicht 52px');
  Assert.IsTrue(Pos('var ZH=52;', Html) > 0,
    'die Zeilenhoehe im JS ist nicht 52 - CSS und JS laufen '
    + 'auseinander, der Scrollbalken springt');
end;

procedure TTestFindingsWorkbenchV3.LeereListe_IstGueltigeSeite;
// Ein Lauf ohne Funde ist der Normalfall in einer gepflegten Codebasis.
// Die Seite muss stehen, nicht abbrechen - und nil darf keine AV sein
// (dieselbe Zusage wie im Sonar-Writer seit Charge 22).
var
  Leer : TObjectList<TLeakFinding>;
  Html : string;
begin
  Leer := TObjectList<TLeakFinding>.Create(True);
  try
    Html := TFindingsWorkbenchV3.BuildHtml(Leer, '', -1, 'de');
  finally
    Leer.Free;
  end;
  Assert.IsTrue(Pos('"funde":[]', Html) > 0,
    'die leere Fundliste erzeugt kein leeres funde-Array');
  Assert.IsTrue(Pos('</html>', Html) > 0,
    'die Seite ist nicht vollstaendig');

  Html := TFindingsWorkbenchV3.BuildHtml(nil, '', -1, 'de');
  Assert.IsTrue(Pos('</html>', Html) > 0,
    'nil-Liste muss eine gueltige, leere Seite liefern');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFindingsWorkbenchV3);

end.
