unit uTestRuleOverlay;

// Waechter fuer den Sprach-Overlay-Loader in TRuleCatalog (2026-08-19).
//
// Die fuenf Tests entsprechen den fuenf Zusagen des Bauplans
// (Konzept_OverlayLoader_2026-08-19.md §5):
//   1. Das Overlay leckt NIE in die kanonische Seite - GetRuleCanonical
//      liefert vor und nach einem lokalisierten Zugriff dieselben Texte.
//   2. Der SARIF-Export ist sprachinvariant, byte-genau. Das ist der
//      Regressionswaechter gegen die Fingerprint-Vergiftung: message.text
//      geht in partialFingerprints, ein uebersetzter Text liesse GitHub
//      Code Scanning jeden Alert als neu melden.
//   3. Das Overlay faellt FELDWEISE zurueck: Name/ShortDescription
//      uebersetzt, FullDescription aus dem Overlay, wenn es sie fuehrt,
//      sonst englisch.
//   4. Unbekannte, leere und feindliche Sprachcodes liefern kanonisch.
//   5. Das Overlay greift auch UEBER dem Fallback-Katalog (kaputte JSON)
//      - die Rule-IDs entstehen dort unabhaengig von der JSON, deshalb
//      braucht der Code keinen Sonderfall, aber der Test haelt es fest.
//   6. (2026-11-05) Die einkompilierte Tabelle uRuleCatalogOverlay.inc
//      liefert fuer JEDE Regel und beide Sprachen dieselben Texte wie
//      die losen Overlays - Langtext eingeschlossen. Prueft die Kette
//      Overlay-JSON -> gen-rules-inc.py -> .inc -> EmbeddedOverlay.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRuleOverlay = class
  public
    [Setup]    procedure Setup;
    [Test] procedure OverlayDoesNotLeakIntoCanonical;
    [Test] procedure SarifOutputIsLanguageInvariant;
    [Test] procedure OverlayFallsBackPerField;
    [Test] procedure OverlayUnknownLanguageIsEnglish;
    [Test] procedure OverlayAppliesOnFallbackCatalog;
    [Test] procedure EmbeddedOverlayMatchesJsonOverlay;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Generics.Collections, System.JSON,
  uSCAConsts, uMethodd12, uRuleCatalog, uLocalization, uExportSARIF;

function OverlayJsonLaden(const APfad: string): TJSONObject;
// Ein Overlay als JSON-Baum, nil ohne Datei oder bei kaputtem Inhalt.
// Der Test liest die Datei SELBST statt ueber TRuleCatalog: er soll den
// Katalog-Leser pruefen, nicht ihm glauben.
var
  V : TJSONValue;
begin
  Result := nil;
  if not TFile.Exists(APfad) then Exit;
  V := TJSONObject.ParseJSONValue(TFile.ReadAllText(APfad, TEncoding.UTF8));
  if V is TJSONObject then
    Result := TJSONObject(V)
  else
    V.Free;
end;

function OverlayFeld(ARoot: TJSONObject; const AID, AFeld: string): string;
// Ein Textfeld einer Regel aus dem Overlay-Baum; '' ohne Regel oder Feld.
var
  V : TJSONValue;
begin
  Result := '';
  if not Assigned(ARoot) then Exit;
  V := ARoot.FindValue('rules.' + AID + '.' + AFeld);
  if V is TJSONString then
    Result := TJSONString(V).Value;
end;

function Erwartet(const AOverlay, AKanonisch: string): string;
// Der Vertrag des Overlays: ein leeres oder fehlendes Feld heisst Englisch.
begin
  if AOverlay <> '' then
    Result := AOverlay
  else
    Result := AKanonisch;
end;

function OhneCR(const S: string): string;
// Der Generator schreibt Zeilenumbrueche als #13#10 (wie die Beispiele in
// uRuleCatalogData.inc), der JSON-Leser liefert #10. Fuer den Vergleich
// zaehlt der Text, nicht die Umbruchform.
begin
  Result := S.Replace(#13#10, #10);
end;

procedure TTestRuleOverlay.Setup;
begin
  // Frischer Katalog je Test - Reload leert seit dem Overlay-Einbau auch
  // den Sprach-Cache (sonst schleppte ein Test die Map des vorigen mit).
  TRuleCatalog.Reload;
end;

procedure TTestRuleOverlay.OverlayDoesNotLeakIntoCanonical;
// Zusage 1: die lokalisierte Seite arbeitet auf der Record-KOPIE.
// FRules/FRulesByID bleiben englisch - sonst waere die Englisch-Garantie
// fuer SARIF/Sonar nur Konvention statt Struktur.
var
  K       : TFindingKind;
  Vorher  : TRuleMeta;
  Nachher : TRuleMeta;
begin
  for K := Low(TFindingKind) to High(TFindingKind) do
  begin
    Vorher := TRuleCatalog.GetRuleCanonical(K);
    TRuleCatalog.GetRule(K, 'de');   // lokalisierter Zugriff dazwischen
    Nachher := TRuleCatalog.GetRuleCanonical(K);
    Assert.AreEqual(Vorher.Name, Nachher.Name,
      Vorher.ID + ': Name kanonisch veraendert');
    Assert.AreEqual(Vorher.ShortDescription, Nachher.ShortDescription,
      Vorher.ID + ': ShortDescription kanonisch veraendert');
    Assert.AreEqual(Vorher.FullDescription, Nachher.FullDescription,
      Vorher.ID + ': FullDescription kanonisch veraendert');
  end;
end;

procedure TTestRuleOverlay.SarifOutputIsLanguageInvariant;
// Zusage 2, der eigentliche Regressionswaechter: SARIF unter 'en' und
// 'de' BYTE-IDENTISCH. Der Fund traegt bewusst KEINEN Detail-Text
// (MissingVar leer) - genau dann faellt message.text auf die
// ShortDescription des Katalogs zurueck, den sprachempfindlichsten Pfad.
var
  L        : TObjectList<TLeakFinding>;
  AltSpr   : string;
  SarifEn  : string;
  SarifDe  : string;
begin
  AltSpr := CurrentLanguage;
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(TLeakFinding.New('Demo.pas', 'DoWork', 7, '', fkEmptyExcept));
    L.Add(TLeakFinding.New('Demo.pas', 'DoIt', 9, '', fkMemoryLeak));
    SetLanguage('en');
    SarifEn := TSARIFWriter.ToJsonString(L, 'C:' + PathDelim, '1.0', 'T');
    SetLanguage('de');
    SarifDe := TSARIFWriter.ToJsonString(L, 'C:' + PathDelim, '1.0', 'T');
    Assert.AreEqual(SarifEn, SarifDe,
      'SARIF haengt an der UI-Sprache - Fingerprint-Vergiftung: GitHub '
      + 'Code Scanning meldete jeden Alert als neu');
  finally
    L.Free;
    SetLanguage(AltSpr);
  end;
end;

procedure TTestRuleOverlay.OverlayFallsBackPerField;
// Zusage 3: uebersetzt ist, was das Overlay fuehrt (Name,
// ShortDescription); FullDescription kommt aus dem Overlay, wenn es sie
// fuehrt, sonst englisch - der dokumentierte feldweise Rueckfall.
// Bis 2026-11-05 verlangte der Test FullDescription = Englisch fest;
// mit den uebersetzten Langtexten waere er rot geworden, obwohl der
// Leser richtig arbeitet. Die Erwartung liest jetzt die Overlay-Datei.
var
  Loc    : TRuleMeta;
  Can    : TRuleMeta;
  Wurzel : TJSONObject;
begin
  Can := TRuleCatalog.GetRuleCanonical(fkMemoryLeak);
  Loc := TRuleCatalog.GetRule(fkMemoryLeak, 'de');
  Assert.AreNotEqual(Can.Name, Loc.Name,
    'SCA001-Name blieb englisch - Overlay nicht gefunden?');
  Assert.AreNotEqual(Can.ShortDescription, Loc.ShortDescription,
    'SCA001-Kurzbeschreibung blieb englisch');
  Wurzel := OverlayJsonLaden(ExtractFilePath(TRuleCatalog.ResolvedJsonPath)
    + 'sca-rules.de.json');
  try
    Assert.AreEqual(
      OhneCR(Erwartet(OverlayFeld(Wurzel, Can.ID, 'fullDescription'),
        Can.FullDescription)),
      OhneCR(Loc.FullDescription),
      'FullDescription: Overlay-Text, wenn vorhanden, sonst englisch');
  finally
    Wurzel.Free;
  end;
  Assert.AreEqual(Can.ID, Loc.ID, 'die Rule-ID ist ein Token');
end;

procedure TTestRuleOverlay.OverlayUnknownLanguageIsEnglish;
// Zusage 4: unbekannte, leere und feindliche Codes -> kanonisch.
// '..\..\boese' prueft zugleich, dass der Sprachcode nie zum Pfadanteil
// wird (NormalizeLangCode verwirft alles ausser [a-z0-9]).
const
  CODES: array[0..3] of string = ('xx', '', '..' + PathDelim + '..'
    + PathDelim + 'boese', 'EN-us');
var
  Can  : TRuleMeta;
  Loc  : TRuleMeta;
  Code : string;
begin
  Can := TRuleCatalog.GetRuleCanonical(fkMemoryLeak);
  for Code in CODES do
  begin
    Loc := TRuleCatalog.GetRule(fkMemoryLeak, Code);
    Assert.AreEqual(Can.Name, Loc.Name,
      '"' + Code + '" muss kanonisch liefern (Name)');
    Assert.AreEqual(Can.ShortDescription, Loc.ShortDescription,
      '"' + Code + '" muss kanonisch liefern (ShortDescription)');
  end;
end;

procedure TTestRuleOverlay.OverlayAppliesOnFallbackCatalog;
// Zusage 5: auch wenn die JSON kaputt ist und der Katalog aus der
// einkompilierten Tabelle kommt, greift das Overlay - die Rule-IDs
// entstehen im Fallback unabhaengig von der JSON (Format('SCA%.3d')),
// deshalb passt der ID-Schluessel des Overlays weiterhin. Muster der
// kaputten JSON wie in FallbackStillProvidesExamples.
var
  TmpFile : string;
  OldPath : string;
  Can     : TRuleMeta;
  Loc     : TRuleMeta;
begin
  OldPath := TRuleCatalog.JsonFilePath;
  TmpFile := TPath.Combine(TPath.GetTempPath,
    'sca_broken_overlay_' + TGuid.NewGuid.ToString
      .Replace('{', '').Replace('}', '') + '.json');
  TFile.WriteAllText(TmpFile, '{ das ist kein gueltiger Regelkatalog');
  try
    TRuleCatalog.JsonFilePath := TmpFile;
    TRuleCatalog.Reload;

    Can := TRuleCatalog.GetRuleCanonical(fkMemoryLeak);
    Loc := TRuleCatalog.GetRule(fkMemoryLeak, 'de');
    Assert.IsNotEmpty(Can.Name, 'Fallback-Katalog leer?');
    Assert.AreNotEqual(Can.Name, Loc.Name,
      'Overlay greift nicht ueber dem Fallback-Katalog');
  finally
    TRuleCatalog.JsonFilePath := OldPath;
    TRuleCatalog.Reload;
    TFile.Delete(TmpFile);
  end;
end;

procedure TTestRuleOverlay.EmbeddedOverlayMatchesJsonOverlay;
// Zusage 6, Vertrag der Generator-Kette: die einkompilierte Tabelle
// (uRuleCatalogOverlay.inc) traegt fuer jede Regel und beide Sprachen
// dieselben Texte wie rules/sca-rules.<lang>.json - Name,
// ShortDescription UND FullDescription.
//
// Rueckfall erzwingen: Katalog-KOPIE in einem Temp-Ordner, daneben
// KAPUTTE sca-rules.de/fr.json. FindOverlayFile sucht zuerst neben dem
// gefundenen Katalog, findet die kaputte Datei, LoadOverlayFile liefert
// nil - also greift EmbeddedOverlay. Der englische Unterbau ist in
// beiden Faellen derselbe Katalog, die Erwartung ergibt sich je Feld
// aus der Overlay-Datei (leer/fehlend = englisch).
//
// Ehrlich: solange die Overlays keinen Langtext fuehren, ist der
// Langtext-Teil leer = leer und der Test gruen auch OHNE den
// FullDesc-Ausbau. Rot wird er, sobald ein Overlay fullDescription
// traegt und die .inc sie nicht mitfuehrt (Generator ohne FullDesc,
// MapAus mit '' oder .inc nicht regeneriert).
const
  SPRACHEN : array[0..1] of string = ('de', 'fr');
var
  OldPath : string;
  Src     : string;
  TmpDir  : string;
  Kopie   : string;
  Wurzeln : array[0..1] of TJSONObject;
  i       : Integer;
  K       : TFindingKind;
  Can     : TRuleMeta;
  Emb     : TRuleMeta;
  Wo      : string;
begin
  OldPath := TRuleCatalog.JsonFilePath;
  Src := TRuleCatalog.ResolvedJsonPath;
  Assert.IsNotEmpty(Src,
    'rules\sca-rules.json nicht gefunden - Vertrag nicht pruefbar');
  TmpDir := TPath.Combine(TPath.GetTempPath,
    'sca_emb_overlay_' + TGuid.NewGuid.ToString
      .Replace('{', '').Replace('}', ''));
  Kopie := TPath.Combine(TmpDir, 'sca-rules.json');
  Wurzeln[0] := nil;
  Wurzeln[1] := nil;
  try
    for i := 0 to High(SPRACHEN) do
    begin
      Wurzeln[i] := OverlayJsonLaden(ExtractFilePath(Src)
        + 'sca-rules.' + SPRACHEN[i] + '.json');
      Assert.IsNotNull(Wurzeln[i],
        'Overlay ' + SPRACHEN[i] + ' neben dem Katalog fehlt oder ist kaputt');
    end;

    TDirectory.CreateDirectory(TmpDir);
    TFile.Copy(Src, Kopie);
    for i := 0 to High(SPRACHEN) do
      TFile.WriteAllText(TPath.Combine(TmpDir,
        'sca-rules.' + SPRACHEN[i] + '.json'), '{ kaputt, erzwingt die .inc');
    TRuleCatalog.JsonFilePath := Kopie;
    TRuleCatalog.Reload;
    Assert.AreEqual(Kopie, TRuleCatalog.ResolvedJsonPath,
      'Katalog-Kopie nicht geladen - der Rueckfall waere nicht erzwungen');

    for i := 0 to High(SPRACHEN) do
      for K := Low(TFindingKind) to High(TFindingKind) do
      begin
        Can := TRuleCatalog.GetRuleCanonical(K);
        Emb := TRuleCatalog.GetRule(K, SPRACHEN[i]);
        Wo  := SPRACHEN[i] + '/' + Can.ID + ': ';
        Assert.AreEqual(
          OhneCR(Erwartet(OverlayFeld(Wurzeln[i], Can.ID, 'name'), Can.Name)),
          OhneCR(Emb.Name), Wo + 'Name weicht von der Overlay-Datei ab');
        Assert.AreEqual(
          OhneCR(Erwartet(OverlayFeld(Wurzeln[i], Can.ID, 'shortDescription'),
            Can.ShortDescription)),
          OhneCR(Emb.ShortDescription),
          Wo + 'ShortDescription weicht von der Overlay-Datei ab');
        Assert.AreEqual(
          OhneCR(Erwartet(OverlayFeld(Wurzeln[i], Can.ID, 'fullDescription'),
            Can.FullDescription)),
          OhneCR(Emb.FullDescription),
          Wo + 'FullDescription weicht von der Overlay-Datei ab - '
          + 'uRuleCatalogOverlay.inc ohne Langtext oder nicht regeneriert '
          + '(python tools/gen-rules-inc.py)');
      end;
  finally
    TRuleCatalog.JsonFilePath := OldPath;
    TRuleCatalog.Reload;
    for i := 0 to High(Wurzeln) do
      Wurzeln[i].Free;
    if TDirectory.Exists(TmpDir) then
      TDirectory.Delete(TmpDir, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRuleOverlay);

end.
