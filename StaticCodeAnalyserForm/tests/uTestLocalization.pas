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

initialization
  TDUnitX.RegisterTestFixture(TTestLocalization);

end.
