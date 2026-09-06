unit uTestDetectorInfoExport;

// Tests fuer uDetectorInfoExport (Regelkatalog als HTML-Seite,
// Nutzerauftrag 2026-09-06): Vollstaendigkeit, Escaping, deutsche
// Overlay-Texte, Sortier-/Such-Geruest, BOM-Schreibweg.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.IOUtils,
  uSCAConsts, uRuleCatalog, uDetectorInfoExport;

type
  [TestFixture]
  TTestDetectorInfoExport = class
  strict private
    FHtml : string;   // einmal gebaut, von allen Faellen gelesen
  public
    [Setup]    procedure Setup;
    [Test] procedure EveryRule_AppearsExactlyOnce;
    [Test] procedure GermanOverlayName_IsUsed;
    [Test] procedure Examples_AreHtmlEscaped;
    [Test] procedure SortAndSearchScaffolding_Present;
    [Test] procedure DefaultProfileColumn_ShowsOnAndOff;
    [Test] procedure WriteToFile_WritesUtf8WithBom;
  end;

implementation

procedure TTestDetectorInfoExport.Setup;
begin
  TRuleCatalog.Reload;   // frischer Katalogzustand (Muster uTestRuleCatalog)
  FHtml := TDetectorInfoExport.BuildHtml('de');
end;

procedure TTestDetectorInfoExport.EveryRule_AppearsExactlyOnce;
// Jede Regel-ID steht als eigene Zelle drin, und die Zahl der
// tbody-Bloecke entspricht der Katalog-Groesse (ein Block je Regel).
var
  K      : TFindingKind;
  Meta   : TRuleMeta;
  Zelle  : string;
  Bloecke, P : Integer;
begin
  for K := Low(TFindingKind) to High(TFindingKind) do
  begin
    Meta  := TRuleCatalog.GetRuleCanonical(K);
    Zelle := '<td>' + Meta.ID + '</td>';
    Assert.IsTrue(Pos(Zelle, FHtml) > 0,
      Format('%s fehlt in der Seite', [Meta.ID]));
  end;
  Bloecke := 0;
  P := Pos('<tbody', FHtml);
  while P > 0 do
  begin
    Inc(Bloecke);
    P := Pos('<tbody', FHtml, P + 1);
  end;
  Assert.AreEqual<Integer>(TRuleCatalog.Count, Bloecke,
    'ein tbody-Block je Regel (Haupt- + Detailzeile als Paar)');
end;

procedure TTestDetectorInfoExport.GermanOverlayName_IsUsed;
// Das DE-Overlay traegt fuer SCA001 den Namen 'Objekt ohne
// ausnahmesichere Freigabe erzeugt' - genau der muss in der Seite
// stehen, nicht der englische Katalogname. Faengt sowohl einen
// Overlay-Ladefehler als auch ein hart-englisches BuildHtml.
var
  MetaDe : TRuleMeta;
  MetaEn : TRuleMeta;
begin
  MetaDe := TRuleCatalog.GetRule(fkMemoryLeak, 'de');
  MetaEn := TRuleCatalog.GetRuleCanonical(fkMemoryLeak);
  Assert.AreNotEqual(MetaEn.Name, MetaDe.Name,
    'Vorbedingung: das DE-Overlay uebersetzt den SCA001-Namen');
  Assert.IsTrue(Pos('<td>' + MetaDe.Name + '</td>', FHtml) > 0,
    'die Seite traegt den deutschen Regelnamen');
end;

procedure TTestDetectorInfoExport.Examples_AreHtmlEscaped;
// Das SCA001-Beispiel enthaelt '<-- exception here leaks list'. Roh
// eingebettet zerrisse das die Seite - es muss als &lt; ankommen.
var
  Meta : TRuleMeta;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkMemoryLeak);
  Assert.IsTrue(Pos('<--', Meta.BadExample) > 0,
    'Vorbedingung: das Katalog-Beispiel enthaelt ein rohes <');
  Assert.IsTrue(Pos('&lt;--', FHtml) > 0,
    'das Beispiel steht escaped in der Seite');
  Assert.IsFalse(Pos('<-- exception', FHtml) > 0,
    'kein rohes < aus dem Beispiel im HTML');
end;

procedure TTestDetectorInfoExport.SortAndSearchScaffolding_Present;
// Nutzerauftrag: Spalten sortierbar + Suche ueber den gesamten
// Inhalt. Prueft das eingebettete Geruest (Funktionen + Verdrahtung).
begin
  Assert.IsTrue(Pos('function sortiere', FHtml) > 0, 'Sortier-JS fehlt');
  Assert.IsTrue(Pos('function suche', FHtml) > 0, 'Such-JS fehlt');
  Assert.IsTrue(Pos('data-search="', FHtml) > 0,
    'Suchbasis je Regel fehlt');
  Assert.IsTrue(Pos('onclick="sortiere(7)"', FHtml) > 0,
    'alle acht Spaltenkoepfe sind verdrahtet');
  Assert.IsTrue(Pos('oninput="suche()"', FHtml) > 0,
    'das Suchfeld ist verdrahtet');
end;

procedure TTestDetectorInfoExport.DefaultProfileColumn_ShowsOnAndOff;
// Das default-Profil schaltet Style-Regeln ab ('*' + !Ausschluesse):
// die Spalte muss beide Zustaende zeigen - mindestens ein 'an' und
// mindestens ein 'aus' (sonst waere GetProfile('default') zum
// AllKinds-Fallback gekippt und die Spalte wertlos).
begin
  Assert.IsTrue(Pos('<span class="an">an</span>', FHtml) > 0,
    'kein aktiver Default-Profil-Eintrag gefunden');
  Assert.IsTrue(Pos('<span class="aus">aus</span>', FHtml) > 0,
    'kein abgeschalteter Default-Profil-Eintrag gefunden');
end;

procedure TTestDetectorInfoExport.WriteToFile_WritesUtf8WithBom;
var
  Datei : string;
  Bytes : TBytes;
begin
  Datei := IncludeTrailingPathDelimiter(TPath.GetTempPath)
    + 'sca_test_detinfo_'
    + TGuid.NewGuid.ToString.Replace('{', '').Replace('}', '')
    + '.html';
  try
    TDetectorInfoExport.WriteToFile(Datei, 'de');
    Bytes := TFile.ReadAllBytes(Datei);
    Assert.IsTrue(Length(Bytes) > 3, 'Datei ist leer');
    Assert.IsTrue((Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF),
      'UTF-8-BOM fehlt (Export-Konvention)');
  finally
    if FileExists(Datei) then DeleteFile(Datei);
  end;
end;

end.
