unit uTestLocalization;

// Tests fuer den .po-Loader (uLocalization). Er ersetzt seit dem Cutover
// 2026-07-26 das frueher hartcodierte GDeMap-Dictionary; die .po ist die
// einzige Quelle. Die Migration war VERHALTENSNEUTRAL angelegt (alle 447
// GDeMap-Texte wurden als msgstr uebernommen) - diese Tests sichern den
// Parser und die Fallback-Semantik ab.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestLocalization = class
  public
    [Test] procedure ParsePo_SimpleEntry_Translates;
    [Test] procedure ParsePo_EmptyMsgstr_FallsBackToMsgid;
    [Test] procedure ParsePo_MultilineMsgstr_Concatenated;
    [Test] procedure ParsePo_ObsoleteEntry_Ignored;
    [Test] procedure ParsePo_BrokenInput_DoesNotRaise;
    [Test] procedure SetLanguage_Unknown_IsIdentity;
    [Test] procedure SetLanguage_German_IsStableWhenRepeated;
    // Sprachauswahl in der UI (Backlog-Welle 1, 2026-07-26)
    [Test] procedure AvailableLanguages_ContainsEmbeddedCodes;
    [Test] procedure AvailableLanguages_SortedAndFreeOfDuplicates;
    [Test] procedure SetLanguage_UnknownIniValue_FallsBackToEnglish;
    [Test] procedure SetLanguage_RegionalIniValue_LoadsBaseLanguage;
    // 'default' ist zugleich INI-Wert ([Rules] Profile): beide UIs
    // schreiben den Combo-Text zurueck und suchen ihn per IndexOf wieder.
    // Die .po MUSS ihn deshalb als Passthrough halten (msgstr = msgid) -
    // dieser Test macht den Kommentar-Vertrag an den Combo-Populates
    // (uMainForm/uIDEAnalyserForm) maschinell pruefbar.
    [Test] procedure AllLanguages_KeepDefaultAsPassthrough;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uLocalization;

const
  PO_SAMPLE =
    'msgid ""' + #13#10 +
    'msgstr ""' + #13#10 +
    '"Content-Type: text/plain; charset=UTF-8\n"' + #13#10 +
    '' + #13#10 +
    'msgid "Start analysis"' + #13#10 +
    'msgstr "Analyse starten"' + #13#10 +
    '' + #13#10 +
    'msgid "Leer"' + #13#10 +
    'msgstr ""' + #13#10 +
    '' + #13#10 +
    'msgid "Zwei"' + #13#10 +
    'msgstr "Teil A "' + #13#10 +
    '"Teil B"' + #13#10 +
    '' + #13#10 +
    '#~ msgid "Alt"' + #13#10 +
    '#~ msgstr "Veraltet"';

procedure TTestLocalization.ParsePo_SimpleEntry_Translates;
var D: TDictionary<string, string>;
begin
  D := TDictionary<string, string>.Create;
  try
    Assert.IsTrue(ParsePo(PO_SAMPLE, D), 'gueltige .po muss geparst werden');
    Assert.AreEqual('Analyse starten', D['Start analysis'],
      'msgstr muss uebernommen werden');
  finally D.Free; end;
end;

procedure TTestLocalization.ParsePo_EmptyMsgstr_FallsBackToMsgid;
// Leerer msgstr = nicht uebersetzt -> der Eintrag darf NICHT im Dict landen,
// damit _() den englischen Ausgangstext zurueckgibt.
var D: TDictionary<string, string>;
begin
  D := TDictionary<string, string>.Create;
  try
    ParsePo(PO_SAMPLE, D);
    Assert.IsFalse(D.ContainsKey('Leer'),
      'leerer msgstr darf keinen Dict-Eintrag erzeugen');
  finally D.Free; end;
end;

procedure TTestLocalization.ParsePo_MultilineMsgstr_Concatenated;
// Fortsetzungszeilen ("..." "...") gehoeren zum selben msgstr.
var D: TDictionary<string, string>;
begin
  D := TDictionary<string, string>.Create;
  try
    ParsePo(PO_SAMPLE, D);
    Assert.AreEqual('Teil A Teil B', D['Zwei'],
      'mehrzeiliger msgstr muss zusammengesetzt werden');
  finally D.Free; end;
end;

procedure TTestLocalization.ParsePo_ObsoleteEntry_Ignored;
// Mit "#~" auskommentierte Eintraege sind Altlast und muessen ignoriert
// werden - sonst wuerden geloeschte Uebersetzungen wieder aktiv.
var D: TDictionary<string, string>;
begin
  D := TDictionary<string, string>.Create;
  try
    ParsePo(PO_SAMPLE, D);
    Assert.IsFalse(D.ContainsKey('Alt'),
      '#~-Eintraege duerfen nicht geladen werden');
  finally D.Free; end;
end;

procedure TTestLocalization.ParsePo_BrokenInput_DoesNotRaise;
// Auflage des Cutovers: bei kaputter Datei NIE crashen, sondern still auf
// Englisch zurueckfallen.
var
  D  : TDictionary<string, string>;
  Ok : Boolean;
begin
  D := TDictionary<string, string>.Create;
  try
    Ok := True;
    try
      ParsePo('msgid "unterminiert', D);
      ParsePo('', D);
      ParsePo('voelliger Unsinn ohne Struktur', D);
    except
      Ok := False;
    end;
    Assert.IsTrue(Ok, 'kaputte .po darf keine Exception werfen');
  finally D.Free; end;
end;

procedure TTestLocalization.SetLanguage_Unknown_IsIdentity;
// Unbekannte Sprache -> Identity (englischer Ausgangstext).
var Old: string;
begin
  Old := CurrentLanguage;
  try
    SetLanguage('xx');
    Assert.AreEqual('Start analysis', _('Start analysis'),
      'unbekannte Sprache muss den Ausgangstext liefern');
  finally
    SetLanguage(Old);
  end;
end;

procedure TTestLocalization.SetLanguage_German_IsStableWhenRepeated;
// Reentranz: zweimal dieselbe Sprache setzen darf den Bestand nicht
// veraendern (Idempotenz des Lazy-Ladens).
var
  Old : string;
  N1, N2 : Integer;
begin
  Old := CurrentLanguage;
  try
    SetLanguage('de');
    N1 := TranslationCount;
    SetLanguage('de');
    N2 := TranslationCount;
    Assert.AreEqual<Integer>(N1, N2,
      'zweimal SetLanguage(de) muss denselben Bestand liefern');
    Assert.IsTrue(N1 > 100,
      'eingebettete de-Uebersetzungen fehlen (erwartet mehrere hundert)');
  finally
    SetLanguage(Old);
  end;
end;

// Hilfs-Praedikat fuer die AvailableLanguages-Tests. Bewusst kein
// TArray.Contains<string> - das braeuchte einen IComparer und macht die
// Assertion-Meldung unleserlich.
function HasCode(const ACodes: TArray<string>; const ACode: string): Boolean;
var
  I : Integer;
begin
  for I := Low(ACodes) to High(ACodes) do
    if ACodes[I] = ACode then
      Exit(True);
  Result := False;
end;

procedure TTestLocalization.AvailableLanguages_ContainsEmbeddedCodes;
// Speisung der Sprachauswahl in den Optionen: die eingebetteten .po
// (uLocalizationPo.inc, generiert aus i18n\*.po) muessen alle auftauchen.
// 'en' ist die Quellsprache und darf nie fehlen, auch ohne .po.
var
  Codes : TArray<string>;
begin
  Codes := AvailableLanguages;
  Assert.IsTrue(HasCode(Codes, 'de'), 'de fehlt in AvailableLanguages');
  Assert.IsTrue(HasCode(Codes, 'en'), 'en fehlt in AvailableLanguages');
  Assert.IsTrue(HasCode(Codes, 'fr'), 'fr fehlt in AvailableLanguages');
end;

procedure TTestLocalization.AvailableLanguages_SortedAndFreeOfDuplicates;
// Die Liste geht 1:1 in Combo bzw. Menue - sie muss stabil sortiert und
// dublettenfrei sein. Eine externe i18n\de.po neben der EXE darf 'de'
// nicht ein zweites Mal erzeugen.
var
  Codes : TArray<string>;
  I     : Integer;
begin
  Codes := AvailableLanguages;
  Assert.IsTrue(Length(Codes) >= 3, 'mindestens de/en/fr erwartet');
  for I := Low(Codes) + 1 to High(Codes) do
    Assert.IsTrue(Codes[I - 1] < Codes[I],
      Format('nicht sortiert oder doppelt: %s vor %s', [Codes[I - 1], Codes[I]]));
end;

procedure TTestLocalization.SetLanguage_UnknownIniValue_FallsBackToEnglish;
// [UI] Language kann jeden beliebigen Text enthalten. Weder ein unbekanntes
// Kuerzel noch Muell darf etwas anderes bewirken als "Englisch": keine
// Exception, keine geladene Tabelle, Identity-Uebersetzung.
var
  Old : string;
begin
  Old := CurrentLanguage;
  try
    SetLanguage('kl');
    Assert.AreEqual<Integer>(0, TranslationCount,
      'unbekanntes Kuerzel darf keine Tabelle aktivieren');
    Assert.AreEqual('Errors', _('Errors'),
      'unbekanntes Kuerzel muss den englischen Ausgangstext liefern');

    SetLanguage('..\..\boese');
    Assert.AreEqual<Integer>(0, TranslationCount,
      'kein Sprachkuerzel -> keine Tabelle (und kein Pfad-Ausbruch)');

    SetLanguage('');
    Assert.AreEqual<Integer>(0, TranslationCount,
      'leerer INI-Wert = Englisch');
  finally
    SetLanguage(Old);
  end;
end;

procedure TTestLocalization.SetLanguage_RegionalIniValue_LoadsBaseLanguage;
// Traegt der User 'de-DE' (oder 'de_AT') in die INI ein, soll das die
// Basissprache laden statt still auf Englisch zu fallen.
var
  Old : string;
begin
  Old := CurrentLanguage;
  try
    SetLanguage('de-DE');
    Assert.IsTrue(TranslationCount > 100,
      'de-DE muss die de-Tabelle laden');
    SetLanguage('DE_at');
    Assert.IsTrue(TranslationCount > 100,
      'Gross-/Kleinschreibung und Unterstrich muessen egal sein');
  finally
    SetLanguage(Old);
  end;
end;

procedure TTestLocalization.AllLanguages_KeepDefaultAsPassthrough;
// Vertrag an der Deklaration. Laeuft ueber ALLE auswaehlbaren Sprachen
// (eingebettete + extern neben dem Modul liegende .po) - genau die
// Menge, die ein Nutzer in den Optionen einstellen kann.
var
  Old  : string;
  Lang : string;
begin
  Old := CurrentLanguage;
  try
    for Lang in AvailableLanguages do
    begin
      SetLanguage(Lang);
      Assert.AreEqual('default', _('default'),
        Format('Sprache "%s" uebersetzt den INI-Wert ''default'' - '
             + 'bricht den Profile-Rundlauf (IndexOf) beider UIs', [Lang]));
    end;
  finally
    SetLanguage(Old);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLocalization);

end.
