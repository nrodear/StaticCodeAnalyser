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
//      uebersetzt, FullDescription (im Overlay nicht gepflegt) englisch.
//   4. Unbekannte, leere und feindliche Sprachcodes liefern kanonisch.
//   5. Das Overlay greift auch UEBER dem Fallback-Katalog (kaputte JSON)
//      - die Rule-IDs entstehen dort unabhaengig von der JSON, deshalb
//      braucht der Code keinen Sonderfall, aber der Test haelt es fest.

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
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uRuleCatalog, uLocalization, uExportSARIF;

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
// ShortDescription); FullDescription bleibt englisch - der dokumentierte
// feldweise Rueckfall, kein Fehler.
var
  Loc : TRuleMeta;
  Can : TRuleMeta;
begin
  Can := TRuleCatalog.GetRuleCanonical(fkMemoryLeak);
  Loc := TRuleCatalog.GetRule(fkMemoryLeak, 'de');
  Assert.AreNotEqual(Can.Name, Loc.Name,
    'SCA001-Name blieb englisch - Overlay nicht gefunden?');
  Assert.AreNotEqual(Can.ShortDescription, Loc.ShortDescription,
    'SCA001-Kurzbeschreibung blieb englisch');
  Assert.AreEqual(Can.FullDescription, Loc.FullDescription,
    'FullDescription muss englisch bleiben (im Overlay nicht gepflegt)');
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

initialization
  TDUnitX.RegisterTestFixture(TTestRuleOverlay);

end.
