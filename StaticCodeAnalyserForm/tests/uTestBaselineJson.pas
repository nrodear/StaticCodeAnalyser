unit uTestBaselineJson;

// DER WAECHTER, DER HIER GEFEHLT HAT.
//
// Die geschriebene Baseline war kein gueltiges JSON. TBaseline.Write
// serialisierte mit Root.Format(2), und Format ruft ToChars mit LEEREN
// Optionen (System.JSON.pas:1609) - Zeichen unter 0x20 ohne Kurz-Escape
// (#0..#7, #11, #14..#31) gingen damit ROH in die Datei, obwohl RFC 8259
// par.7 dort \uXXXX verlangt.
//
// WARUM ES NIEMAND GEMERKT HAT: Delphis eigener Parser ist toleranter als
// die Spezifikation. TJSONValue.ParseString (System.JSON.pas:2233-2312)
// hat in seiner case-Anweisung genau drei Faelle - Anfuehrungszeichen,
// Backslash, "sonst uebernimm das Byte" - und keinen Guard gegen B < $20.
// Unsere eigenen Leser (TBaseline.Apply, TBaselineSet.LoadFromFile,
// IsBaselineFile) lasen die kaputte Datei also klaglos. Kaputt war sie
// nur fuer FREMDE Werkzeuge: python json.load, jq, JSON.parse brechen an
// der ersten solchen Zeile ab - und damit an der ganzen Datei. Auf dem
// Referenzkorpus rw21 waren es 3 von 783.104 Eintraegen (Bytes 0x00/0x04
// aus zwei JVCL-LED-Demos und einem mORMot-Escaping-Test): Fehlerrate
// 0,00038 %, Ausfallrate 100 %.
//
// Fuer die beiden Schwesterpfade gab es je einen Waechter -
// uTestExportSARIF.ControlCharInMessage_FileStaysParseable und
// uTestExportSonarGeneric.ControlCharInMessage_StillParses. Fuer die
// Baseline gab es keinen. Das ist der Grund, warum derselbe Defekt dort
// zweimal repariert und hier zweimal uebersehen wurde.
//
// DIE PROBE MUSS AM TEXT HAENGEN, NICHT AM PARSER: ein
// "ParseJSONValue liefert nicht nil" waere hier GRUEN GEWESEN, waehrend
// die Datei kaputt war. Deshalb zaehlt RawControlCharCount die rohen
// Steuerzeichen im Dateitext.

interface

uses
  DUnitX.TestFramework,
  uMethodd12;

type
  [TestFixture]
  TTestBaselineJson = class
  strict private
    // Zieldatei des laufenden Tests - TearDown raeumt sie weg.
    FTempFile : string;
    function TempBaselineFile: string;
    // Fund mit ADetail, dessen Quelldatei BEWUSST nicht existiert: ohne
    // lesbare Datei entsteht kein contextHash, und die Tests belegen die
    // Legacy-Fingerprint-Strecke.
    function NewFinding(const ADetail: string): TLeakFinding;
    // Schreibt EINEN Fund mit ADetail und liefert den Dateitext.
    function WriteAndRead(const ADetail: string): string;
  public
    [TearDown] procedure TearDown;
    // DER Test zum Befund: rot ohne den Fix.
    [Test] procedure ControlChars_FileHasNoRawControlChar;
    // Identitaet und Text ueberleben Schreiben und Lesen.
    [Test] procedure ControlChars_RoundTripKeepsTextAndFingerprint;
    // Steuerzeichen ist nicht dasselbe wie Nicht-ASCII.
    [Test] procedure NonAscii_StaysRawAndUnescaped;
    // Zusage an den Bestand: gleiche Bytes wie die RTL, solange nichts zu
    // escapen ist.
    [Test] procedure Layout_MatchesRtlFormatWhenNoControlChars;
    // Der Paar-NAME geht denselben Weg (Schwesterpfad profiles.json).
    [Test] procedure PairName_ControlCharIsEscaped;
    // Alte, kaputt geschriebene Dateien bleiben lesbar - keine Migration.
    [Test] procedure LegacyFileWithRawControlChar_StillApplies;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON,
  System.Generics.Collections,
  uSCAConsts, uBaseline, uJsonFormat;

const
  // Der Meldetext des Befunds: zwei Steuerzeichen OHNE Kurz-Escape (#0
  // wie in 'PasswordChar := #0', #4 wie in der JVCL-LED-Demo) und zwei
  // MIT (#9 Tab, #13#10 Zeilenumbruch). Die beiden letzten pruefen, dass
  // der Fix die Kurzformen nicht verdraengt.
  CTL_DETAIL = 'A'#0'B'#4'C'#9'D'#13#10'E';
  // Umlaut (U+00E4) und CJK (U+4E2D) - als Escape geschrieben, damit die
  // Quelldatei ASCII bleibt.
  INTL_DETAIL = 'Umlaut '#$00E4' CJK '#$4E2D' Ende';
  METHOD_NAME = 'M';
  FILE_UNIT   = 'Unit1.pas';
  DIR_JSONTST = 'sca_json_root';
  // Feldnamen der Baseline-Datei.
  FLD_FINDINGS = 'findings';
  FLD_DETAIL   = 'detail';
  FLD_FP       = 'fingerprint';
  // Die erwarteten Escape-Sequenzen. Der Backslash steht als #92 im
  // Quelltext: so kann kein Werkzeug auf dem Weg hierher die Sequenz
  // selbst als Escape lesen und aufloesen.
  BSL          = #92;
  ESC_NUL      = BSL + 'u0000';
  ESC_EOT      = BSL + 'u0004';

function RawControlCharCount(const S: string): Integer;
// Zeichen unter 0x20 im DATEITEXT, ohne CR und LF: die beiden sind in
// der eingerueckten Ausgabe die Zeilentrenner der STRUKTUR. Innerhalb
// eines JSON-Strings koennen sie nicht roh stehen - die RTL escaped #13
// und #10 immer als \r bzw. \n, unabhaengig von den Optionen
// (System.JSON.pas:2618-2621). Was diese Funktion also zaehlt, ist genau
// das, was RFC 8259 par.7 verbietet.
var
  Ch : Char;
begin
  Result := 0;
  for Ch in S do
  begin
    if (Ord(Ch) < 32) and (Ch <> #13) and (Ch <> #10) then
    begin
      Inc(Result);
    end;
  end;
end;

function TTestBaselineJson.TempBaselineFile: string;
begin
  Result := TPath.Combine(TPath.GetTempPath,
    'sca_json_' + TGuid.NewGuid.ToString + '.baseline.json');
  FTempFile := Result;
end;

function TTestBaselineJson.NewFinding(const ADetail: string): TLeakFinding;
begin
  Result := TLeakFinding.New(
    TPath.Combine(TPath.Combine(TPath.GetTempPath, DIR_JSONTST), FILE_UNIT),
    METHOD_NAME, 10, ADetail, fkEmptyBlock);
end;

function TTestBaselineJson.WriteAndRead(const ADetail: string): string;
var
  Fn   : string;
  List : TObjectList<TLeakFinding>;
begin
  Fn   := TempBaselineFile;
  List := TObjectList<TLeakFinding>.Create(True);
  try
    List.Add(NewFinding(ADetail));
    Assert.AreEqual<Integer>(1,
      TBaseline.Write(List, Fn, TBaselineScope.ByFileName),
      'ein Eintrag geschrieben');
  finally
    List.Free;
  end;
  Result := TFile.ReadAllText(Fn, TEncoding.UTF8);
end;

procedure TTestBaselineJson.TearDown;
begin
  if (FTempFile <> '') and TFile.Exists(FTempFile) then
  begin
    TFile.Delete(FTempFile);
  end;
  FTempFile := '';
end;

procedure TTestBaselineJson.ControlChars_FileHasNoRawControlChar;
// ROT OHNE DEN FIX: Format(2) legt #0 und #4 roh in die Datei, der
// Zaehler steht dann auf 2.
var
  Text : string;
begin
  Text := WriteAndRead(CTL_DETAIL);
  Assert.AreEqual<Integer>(0, RawControlCharCount(Text),
    'kein Steuerzeichen darf roh in der Baseline stehen');
  // Positivprobe: die Zeichen sind nicht verschwunden, sondern escaped.
  Assert.IsTrue(Pos(ESC_NUL, Text) > 0,
    'die Sequenz u0000 fehlt im Output');
  Assert.IsTrue(Pos(ESC_EOT, Text) > 0,
    'die Sequenz u0004 fehlt im Output');
  // Und die Kurzformen bleiben Kurzformen - sonst haette der Fix die
  // bestehende Ausgabe unnoetig veraendert.
  Assert.IsTrue(Pos('\t', Text) > 0, 'Kurz-Escape \t verdraengt');
  Assert.IsTrue(Pos('\r\n', Text) > 0, 'Kurz-Escapes \r\n verdraengt');
end;

procedure TTestBaselineJson.ControlChars_RoundTripKeepsTextAndFingerprint;
// GRUEN VOR UND NACH DEM FIX - und genau deshalb steht er hier: er ist
// die Bedingung, unter der der Fix gemacht werden durfte. Escapen aendert
// die IDENTITAET der Funde nicht. Ein Fix, der die Steuerzeichen
// stattdessen aus dem Text ENTFERNT oder durch '<0x00>' ersetzt (die
// Variante "gar nicht erst in die Meldung lassen"), macht die
// detail-Zusage unten rot - und aendert am Korpus rw21 die Identitaet von
// 3 Funden (bzw. 171, wenn auch Tab und Umbruch fielen).
var
  Fn      : string;
  List    : TObjectList<TLeakFinding>;
  ExpFp   : string;
  Root    : TJSONValue;
  Entry   : TJSONObject;
  Dropped : Integer;
begin
  Fn   := TempBaselineFile;
  List := TObjectList<TLeakFinding>.Create(True);
  try
    List.Add(NewFinding(CTL_DETAIL));
    ExpFp := TBaseline.Fingerprint(List[0], TBaselineScope.ByFileName);
    Assert.AreEqual<Integer>(1,
      TBaseline.Write(List, Fn, TBaselineScope.ByFileName),
      'ein Eintrag geschrieben');
  finally
    List.Free;
  end;

  Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(Fn, TEncoding.UTF8));
  try
    Assert.IsNotNull(Root, 'die geschriebene Baseline parst nicht');
    Entry := (Root as TJSONObject).GetValue<TJSONArray>(FLD_FINDINGS)
               .Items[0] as TJSONObject;
    // Der Text kommt Zeichen fuer Zeichen zurueck - die Sequenz u0000
    // ist beim Lesen wieder ein #0. Das ist der Unterschied zwischen
    // escapen und ersetzen.
    Assert.AreEqual(CTL_DETAIL, Entry.Values[FLD_DETAIL].Value,
      'der Meldetext muss den Roundtrip unveraendert ueberstehen');
    Assert.AreEqual(ExpFp, Entry.Values[FLD_FP].Value,
      'der Fingerprint in der Datei bleibt der des Fundes');
  finally
    Root.Free;
  end;

  List := TObjectList<TLeakFinding>.Create(True);
  try
    List.Add(NewFinding(CTL_DETAIL));
    Dropped := TBaseline.Apply(List, Fn, TBaselineScope.ByFileName);
    Assert.AreEqual<Integer>(1, Dropped,
      'derselbe Fund muss weiterhin ueber die Baseline wegfallen');
  finally
    List.Free;
  end;
end;

procedure TTestBaselineJson.NonAscii_StaysRawAndUnescaped;
// GEGENPROBE ZUM FIX: nur < 0x20 ist das Thema. Waere die Option
// EncodeAbove127 mit hineingeraten, blieben Umlaute und CJK zwar
// gueltiges JSON, aber die Datei waere groesser und jede Meldung fuer
// einen Menschen unlesbar. Rot, sobald jemand "sicherheitshalber" alles
// escaped.
var
  Text : string;
begin
  Text := WriteAndRead(INTL_DETAIL);
  Assert.IsTrue(Pos(#$00E4, Text) > 0,
    'der Umlaut muss roh in der Datei stehen');
  Assert.IsTrue(Pos(#$4E2D, Text) > 0,
    'das CJK-Zeichen muss roh in der Datei stehen');
  Assert.AreEqual<Integer>(0, Pos('\u', Text),
    'ohne Steuerzeichen darf gar nichts \u-escaped werden');
end;

procedure TTestBaselineJson.Layout_MatchesRtlFormatWhenNoControlChars;
// DIE ZUSAGE AN BESTEHENDE BASELINES: solange nichts zu escapen ist, ist
// die Ausgabe byte-identisch zu TJSONValue.Format(2) - gleiche
// Einrueckung, gleiches ': ' nach dem Namen, gleiches '\/' fuer den
// Schraegstrich, gleiches CRLF. Der Fix formatiert also KEINE
// 371-MB-Datei um; er aendert genau die kaputten Stellen.
//
// Der Vergleich laeuft direkt gegen die RTL. Er wird rot, sobald jemand
// den Formatierer "vereinfacht" (etwa auf ToJSON, das alles in EINE
// Zeile legt).
var
  Root : TJSONObject;
  Arr  : TJSONArray;
begin
  Root := TJSONObject.Create;
  try
    // Absichtlich alle Blatt-Typen und beide Container, dazu die
    // Zeichen, die die RTL ohnehin escaped (Quote, Backslash, Slash).
    Root.AddPair('text', 'Umlaut '#$00E4' "quote" / slash '#92' back');
    Root.AddPair('num',  TJSONNumber.Create(42));
    Root.AddPair('flag', TJSONBool.Create(True));
    Arr := TJSONArray.Create;
    Arr.Add('a');
    Arr.AddElement(TJSONNumber.Create(7));
    Arr.AddElement(TJSONObject.Create(TJSONPair.Create('nested', 'x')));
    Root.AddPair('list', Arr);
    Root.AddPair('empty', TJSONObject.Create);
    Assert.AreEqual(Root.Format(2), JsonFormatEscaped(Root, 2),
      'ohne Steuerzeichen muss die Ausgabe der RTL-Formatierung gleichen');
  finally
    Root.Free;
  end;
end;

procedure TTestBaselineJson.PairName_ControlCharIsEscaped;
// Der zweite Format(2)-Aufrufer im Repo war TRuleCatalog.
// WriteUserProfiles, und dort sind die Paar-NAMEN Nutzereingaben
// (Profilnamen). Die RTL escaped Namen ueber denselben Pfad wie Werte -
// und hat dort denselben Defekt. Rot ohne den Fix.
var
  Root : TJSONObject;
  Text : string;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('Profil'#0'X', 'v');
    Text := JsonFormatEscaped(Root, 2);
  finally
    Root.Free;
  end;
  Assert.AreEqual<Integer>(0, RawControlCharCount(Text),
    'auch im Paar-Namen darf kein Steuerzeichen roh stehen');
  Assert.IsTrue(Pos(ESC_NUL, Text) > 0,
    'der Name muss escaped herauskommen');
end;

procedure TTestBaselineJson.LegacyFileWithRawControlChar_StillApplies;
// KEINE MIGRATION NOETIG: eine vor dem Fix geschriebene Baseline enthaelt
// rohe Steuerzeichen und bleibt trotzdem voll wirksam, weil Delphis
// Parser sie annimmt. Der Fix ist damit in beide Richtungen
// rueckwaertskompatibel - alte Datei plus neue Engine filtert weiter,
// neue Datei plus alte Engine ebenso (u0000 ist Standard-JSON).
// Gruen vor und nach dem Fix; rot, sobald jemand einen Steuerzeichen-
// Guard in den LESEPFAD baut und damit Bestandsdateien entwertet.
var
  Fn      : string;
  Legacy  : string;
  Fp      : string;
  F       : TLeakFinding;
  List    : TObjectList<TLeakFinding>;
  Dropped : Integer;
begin
  Fn := TempBaselineFile;
  F  := NewFinding(CTL_DETAIL);
  try
    Fp := TBaseline.Fingerprint(F, TBaselineScope.ByFileName);
  finally
    F.Free;
  end;
  // Von Hand gebaut, MIT rohem #0 im detail - genau die Form, die
  // TBaseline.Write bis 2026-08-28 erzeugt hat.
  Legacy :=
    '{'#13#10 +
    '  "version": "1",'#13#10 +
    '  "pathFingerprint": false,'#13#10 +
    '  "count": 1,'#13#10 +
    '  "findings": ['#13#10 +
    '    {'#13#10 +
    '      "file": "unit1.pas",'#13#10 +
    '      "kind": "EmptyBlock",'#13#10 +
    '      "method": "M",'#13#10 +
    '      "detail": "A'#0'B",'#13#10 +
    '      "line": "10",'#13#10 +
    '      "fingerprint": "' + Fp + '"'#13#10 +
    '    }'#13#10 +
    '  ]'#13#10 +
    '}'#13#10;
  TFile.WriteAllText(Fn, Legacy, TEncoding.UTF8);

  List := TObjectList<TLeakFinding>.Create(True);
  try
    List.Add(NewFinding(CTL_DETAIL));
    Dropped := TBaseline.Apply(List, Fn, TBaselineScope.ByFileName);
    Assert.AreEqual<Integer>(1, Dropped,
      'eine alte Baseline mit rohem Steuerzeichen muss weiter filtern');
  finally
    List.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestBaselineJson);

end.
