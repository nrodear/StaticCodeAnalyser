unit uTestExport;

// Vertragstests fuer TExporter (uExport) - die Basis-Ausgabeschicht:
// Pfadanzeige, CSV-/JSON-Escaping, BOM-Politik und Datei-Zuordnung.
//
// WARUM ES DIESE UNIT ERST SEIT 08.09. GIBT: uExport war die einzige
// Unit der Export-Familie OHNE Tests (SARIF, Sonar, HTML haben je
// eigene). Genau dort lebte ein BLOCKER unentdeckt - in
// RelativeDisplayPath stand ein LEERES Suchmuster statt des
// Backslashes, der Pfad ging also mit Windows-Trennern raus, obwohl
// der Vertrag Forward Slashes zusagt. Aufgefallen ist das erst dem
// Modul-Codereview (MUSS-Punkt 5), nicht dem Betrieb: CSV und JSON
// zeigten 'src\u.pas', SARIF fuer denselben Fund 'src/u.pas'.
// Diese Fixture ist die Antwort darauf.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  DUnitX.TestFramework,
  uSCAConsts, uMethodd12;

type
  [TestFixture]
  TTestExport = class
  public
    // Der Fall, der den BLOCKER gefangen haette.
    [Test] procedure RelativeDisplayPath_UsesForwardSlashes;
    [Test] procedure RelativeDisplayPath_WithoutBaseDir_Unchanged;
    [Test] procedure RelativeDisplayPath_OutsideBaseDir_Unchanged;
    [Test] procedure JsonEscape_ControlCharsAndQuotes;
    [Test] procedure KindToName_IsStableAndNonEmpty;
    [Test] procedure SameSourceFile_MatchesRegardlessOfSeparator;
    // Der Ordner-Mix, den der Basisnamen-Vergleich zuliess.
    [Test] procedure SameSourceFile_TrenntGleichnamigeAusAnderenOrdnern;
    [Test] procedure SameSourceFile_AbsoluterPfadGegenRelativenTail;
    [Test] procedure SameSourceFile_SuffixNurAnDerTrennergrenze;
    // Die ExtractFileName-Falle im Fix selbst (Chargen-Review 08.09.).
    [Test] procedure SameSourceFile_BasisnameOhneExtractFileName;
    // Die BOM-Politik, an der die CI haengt - beide Speicherwege.
    [Test] procedure SaveBuilderUtf8_OhneBom_SchreibtKeinePraeambel;
    [Test] procedure SaveBuilderUtf8_MitBom_SchreibtPraeambel;
    [Test] procedure SaveUtf8WithBom_SchreibtPraeambel;

    // Die beiden Writer als GANZES - Praeambel UND Inhalt.
    [Test] procedure ExportCsv_MitBomUndForwardSlashes;
    [Test] procedure ExportJson_OhneBomUndForwardSlashes;
    [Test] procedure ExportCsvUndJson_VertragenNil;
  end;

implementation

// noinspection-file DuplicateString, HardcodedPath
// Fixture-Ausnahme des Profils: 'D:\proj' und 'src\uMain.pas' sind
// der PRUEFGEGENSTAND dieser Unit und wiederholen sich deshalb -
// hier geht es genau darum, was aus einem Pfad wird. Aus demselben
// Grund stehen die Pfade hart im Code: ein aus TPath.GetTempPath
// gebauter Pfad haette je Maschine eine andere Tiefe und der
// erwartete Relativpfad waere nicht mehr aufschreibbar.

uses
  System.IOUtils,
  uExport;

procedure TTestExport.RelativeDisplayPath_UsesForwardSlashes;
// DER Waechter des BLOCKERs vom 08.09.: liegt die Datei unter der
// Wurzel, muss der Rest RELATIV und mit FORWARD SLASHES erscheinen.
// Mit dem alten leeren Suchmuster kam 'src\uMain.pas' heraus - der
// Test waere rot gewesen.
var
  Ergebnis : string;
begin
  Ergebnis := TExporter.RelativeDisplayPath('D:\proj\src\uMain.pas',
    'D:\proj');
  Assert.AreEqual('src/uMain.pas', Ergebnis,
    'Relativpfad muss Forward Slashes tragen (Vertrag der Methode; '
    + 'SARIF und Sonar tun es, CSV/JSON hingen daran)');
  Assert.AreEqual<Integer>(0, Pos('\', Ergebnis),
    'im Ergebnis darf KEIN Windows-Trenner mehr stehen');
end;

procedure TTestExport.RelativeDisplayPath_WithoutBaseDir_Unchanged;
// Ohne Wurzel bleibt der Pfad, wie er ist - darauf verlaesst sich
// der V2-Fundbericht (AnzeigePfad) fuer seine Datei-Zeile.
begin
  Assert.AreEqual('src\uMain.pas',
    TExporter.RelativeDisplayPath('src\uMain.pas', ''),
    'ohne Wurzel wird nichts umgeschrieben');
  Assert.AreEqual('',
    TExporter.RelativeDisplayPath('', 'D:\proj'),
    'leerer Dateiname bleibt leer');
end;

procedure TTestExport.RelativeDisplayPath_OutsideBaseDir_Unchanged;
// Liegt die Datei NICHT unter der Wurzel, bleibt der volle Pfad
// stehen - lieber ein langer Pfad als ein falscher Relativbezug.
var
  Ergebnis : string;
begin
  Ergebnis := TExporter.RelativeDisplayPath('E:\extern\uAlt.pas',
    'D:\proj');
  Assert.AreEqual('E:\extern\uAlt.pas', Ergebnis,
    'ausserhalb der Wurzel bleibt der Pfad unveraendert');
end;

procedure TTestExport.JsonEscape_ControlCharsAndQuotes;
// JSON-Escaping: ein unescaptes Anfuehrungszeichen oder ein rohes
// Steuerzeichen macht den JSON-Report unparsebar - und der geht in
// CI-Pipelines.
begin
  Assert.AreEqual('a\"b', TExporter.JsonEscape('a"b'),
    'Anfuehrungszeichen muss escaped werden');
  Assert.AreEqual('a\\b', TExporter.JsonEscape('a\b'),
    'Backslash muss escaped werden');
  Assert.AreEqual('a\nb', TExporter.JsonEscape('a'#10'b'),
    'Zeilenumbruch muss als \n erscheinen, nicht roh');
  Assert.AreEqual('a\tb', TExporter.JsonEscape('a'#9'b'),
    'Tabulator muss als \t erscheinen');
end;

procedure TTestExport.KindToName_IsStableAndNonEmpty;
// Der Kind-Name ist ein VERTRAG nach aussen: er steht in CSV, JSON,
// SARIF (ruleId-Bezug) und in jedem noinspection-Marker. Ein leerer
// oder wechselnder Name braeche Suppressions beim Nutzer.
var
  K : TFindingKind;
  N : string;
begin
  for K := Low(TFindingKind) to High(TFindingKind) do
  begin
    N := TExporter.KindToName(K);
    Assert.IsTrue(N <> '',
      'leerer Kind-Name bei Ordinalwert ' + IntToStr(Ord(K)));
    Assert.AreEqual<Integer>(0, Pos(' ', N),
      'Kind-Namen duerfen kein Leerzeichen tragen (sie stehen in '
      + 'noinspection-Markern): ' + N);
  end;
  // AreEqual case-SENSITIV (vierter Parameter False): DUnitX vergleicht
  // Strings per Default OHNE Ruecksicht auf Gross-/Kleinschreibung
  // (DUnitX.Assert: fIgnoreCaseDefault := true). Eine Umbenennung auf
  // 'memoryleak' waere sonst durchgewunken - und der Kind-Name geht in
  // die SARIF-ruleId sowie in CSV und JSON, wo externe Konsumenten sehr
  // wohl auf die Schreibweise achten. Fuer die noinspection-Marker
  // selbst waere es egal, die vergleichen per SameText.
  Assert.AreEqual('MemoryLeak', TExporter.KindToName(fkMemoryLeak), False,
    'der bekannteste Kind-Name hat sich geaendert - das braeche '
    + 'jede bestehende noinspection MemoryLeak beim Nutzer');
end;

procedure TTestExport.SameSourceFile_MatchesRegardlessOfSeparator;
// Der Einzeldatei-Export filtert hierueber. Diese drei Faelle galten
// schon vor dem Umbau vom 08.09. und muessen ihn ueberleben.
begin
  Assert.IsTrue(TExporter.SameSourceFile('src\uMain.pas',
    'src/uMain.pas'), 'Trennerform darf nicht entscheiden');
  Assert.IsTrue(TExporter.SameSourceFile('D:\a\uMain.pas',
    'uMain.pas'), 'absoluter gegen blossen Namen muss greifen - ohne '
    + 'Verzeichnisanteil auf einer Seite ist der Basisname alles, was '
    + 'vorliegt');
  Assert.IsFalse(TExporter.SameSourceFile('uMain.pas', 'uOther.pas'),
    'verschiedene Namen duerfen nicht zusammenfallen');
end;

procedure TTestExport.SameSourceFile_TrenntGleichnamigeAusAnderenOrdnern;
// DER Waechter des MAJOR vom 08.09.: gleichnamige Units in mehreren
// Ordnern sind in Delphi-Projektgruppen der Normalfall. Mit dem alten
// Basisnamen-Vergleich war dieser Fall True, und der Einzeldatei-Export
// zog die Befunde beider Dateien stillschweigend zusammen.
begin
  Assert.IsFalse(TExporter.SameSourceFile('D:\projA\uMain.pas',
    'D:\projB\uMain.pas'),
    'gleicher Dateiname in verschiedenen Ordnern ist NICHT dieselbe '
    + 'Datei - genau hier mischte der Export vorher zwei Units');
end;

procedure TTestExport.SameSourceFile_AbsoluterPfadGegenRelativenTail;
// Die Gegenprobe zum Waechter: der Aufrufer haelt mal einen absoluten,
// mal einen relativen Pfad. Ein schlichter Volltextvergleich waere hier
// rot und haette den Einzeldatei-Export leergefegt.
begin
  Assert.IsTrue(TExporter.SameSourceFile('D:\proj\src\uMain.pas',
    'src\uMain.pas'),
    'der relative Pfad ist ein echtes Suffix des absoluten');
end;

procedure TTestExport.SameSourceFile_BasisnameOhneExtractFileName;
// Waechter des BLOCKERs, den der Chargen-Review am 08.09. im FIX selbst
// gefunden hat: die Funktion normalisiert alle Trenner zu '/' und zog
// den Basisnamen danach mit ExtractFileName. Das schneidet unter
// Windows aber nur an '\' und ':' ab (System.SysUtils:
// LastDelimiter([PathDelim, DriveDelim])) - auf dem normalisierten Pfad
// findet es nichts und liefert aus 'src/uMain.pas' wieder
// 'src/uMain.pas'. Der Fallback-Zweig war damit immer falsch.
//
// Dieser Fall trifft den Zweig direkt: eine Seite MIT Ordner, die
// andere OHNE - so kommt es nur zum Basisnamen-Vergleich.
begin
  Assert.IsTrue(TExporter.SameSourceFile('src\uMain.pas', 'uMain.pas'),
    'ein Pfad mit Ordner gegen den blossen Dateinamen muss greifen - '
    + 'mit ExtractFileName auf dem /-normalisierten Pfad war das False');
  Assert.IsTrue(TExporter.SameSourceFile('src/uMain.pas', 'uMain.pas'),
    'dasselbe mit Forward Slash in der Eingabe');
end;

procedure TTestExport.SameSourceFile_SuffixNurAnDerTrennergrenze;
// Die dritte Richtung: ein naiver Suffix-Vergleich ohne Trennergrenze
// waere hier gruen und wuerde 'xsrc' fuer 'src' halten.
begin
  Assert.IsFalse(TExporter.SameSourceFile('D:\proj\xsrc\uMain.pas',
    'src\uMain.pas'),
    'ein Suffix mitten im Ordnernamen zaehlt nicht - vor dem Treffer '
    + 'muss ein Trenner stehen');
end;

// Die drei Speicherwege, die es in uExport gibt. Der Builder-Weg traegt
// heute CSV, JSON und HTML; der Listen-Weg ist dem Detektor-Katalog
// geblieben (uDetectorInfoExport).
type
  TSpeicherweg = (swBuilderOhneBom, swBuilderMitBom, swListeMitBom);

// Schreibt eine Zeile ueber den gewaehlten Weg und liefert die Bytes der
// entstandenen Datei zurueck. Ausgelagert, weil sich die BOM-Tests nur
// im Weg und in der Erwartung unterscheiden.
function ErsteBytes(AWeg: TSpeicherweg; const ADateiname: string): TBytes;
var
  SB   : TStringBuilder;
  SL   : TStringList;
  Ziel : string;
begin
  Ziel := TPath.Combine(TPath.GetTempPath, ADateiname);
  try
    if AWeg = swListeMitBom then
    begin
      SL := TStringList.Create;
      try
        SL.Add('{"a":1}');
        TExporter.SaveUtf8WithBom(SL, Ziel);
      finally
        SL.Free;
      end;
    end
    else
    begin
      SB := TStringBuilder.Create;
      try
        SB.AppendLine('{"a":1}');
        TExporter.SaveBuilderUtf8(SB, Ziel, AWeg = swBuilderMitBom);
      finally
        SB.Free;
      end;
    end;
    Result := TFile.ReadAllBytes(Ziel);
  finally
    if TFile.Exists(Ziel) then
      TFile.Delete(Ziel);
  end;
end;

// True, wenn die Bytes mit der UTF-8-Praeambel EF BB BF beginnen.
function HatUtf8Praeambel(const ABytes: TBytes): Boolean;
begin
  Result := (Length(ABytes) >= 3) and (ABytes[0] = $EF)
    and (ABytes[1] = $BB) and (ABytes[2] = $BF);
end;

procedure TTestExport.SaveBuilderUtf8_OhneBom_SchreibtKeinePraeambel;
// Waechter der JSON-Seite der BOM-Politik, auf dem Weg, den ExportJson
// seit 08.09. wirklich nimmt. Der Test ist NICHT kosmetisch:
// TEncoding.UTF8 hat FUseBOM=True (TMBCSEncoding.Create setzt es
// zuletzt) und GetPreamble liefert sehr wohl ein EF BB BF - allein das
// Unterdruecken haelt es zurueck. Wer den Schalter fuer redundant haelt,
// macht diesen Test rot, statt die CI-Pipeline still zu brechen.
var
  Bytes : TBytes;
begin
  Bytes := ErsteBytes(swBuilderOhneBom, 'sca_test_nobom.json');
  Assert.IsTrue(Length(Bytes) > 0, 'es wurde gar nichts geschrieben');
  Assert.IsFalse(HatUtf8Praeambel(Bytes),
    'die JSON-Ausgabe traegt eine BOM-Praeambel - RFC 8259 par.8.1 '
    + 'verbietet sie, und Nodes JSON.parse scheitert daran');
end;

procedure TTestExport.SaveBuilderUtf8_MitBom_SchreibtPraeambel;
// Die Gegenrichtung auf demselben Weg: ohne BOM zerfallen die Umlaute
// im deutschen Excel, weil es eine CSV nur an der Praeambel als UTF-8
// erkennt. Erst das Paar haelt die Politik an BEIDEN Enden fest - ein
// Test allein waere auch dann gruen, wenn der Parameter gar nichts
// mehr taete.
var
  Bytes : TBytes;
begin
  Bytes := ErsteBytes(swBuilderMitBom, 'sca_test_mitbom.csv');
  Assert.IsTrue(HatUtf8Praeambel(Bytes),
    'CSV und HTML brauchen das BOM - deutsches Excel erkennt UTF-8 '
    + 'nur daran');
end;

procedure TTestExport.SaveUtf8WithBom_SchreibtPraeambel;
// Der Listen-Weg hat seit dem Builder-Umbau nur noch EINEN Aufrufer,
// den Detektor-Katalog (uDetectorInfoExport). Genau deshalb steht er
// hier: eine Politik mit einem einzigen Aufrufer faellt sonst beim
// naechsten Aufraeumen still um.
var
  Bytes : TBytes;
begin
  Bytes := ErsteBytes(swListeMitBom, 'sca_test_liste.html');
  Assert.IsTrue(HatUtf8Praeambel(Bytes),
    'der Listen-Weg muss weiter ein BOM schreiben - der Detektor-'
    + 'Katalog haengt daran');
end;

// Eine Fundliste mit genau einem Fund unterhalb von 'D:\proj'.
// Ownership: der Aufrufer gibt die Liste frei, sie besitzt den Fund.
function EineFundliste: TObjectList<TLeakFinding>;
var
  F : TLeakFinding;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  F := TLeakFinding.Create;
  F.SetKind(fkMemoryLeak);
  F.FileName   := 'D:\proj\src\uMain.pas';
  F.MethodName := 'TFoo.Bar';
  F.LineNumber := '42';
  F.MissingVar := 'list';
  Result.Add(F);
end;

// Schreibt ueber ASchreiber in eine eigene Temp-Datei und liefert den
// kompletten Inhalt als Bytes zurueck. Eigener Dateiname je Aufruf statt
// eines festen - so koennen sich zwei Tests nie in die Quere kommen.
function ExportBytes(const AEndung: string;
  ASchreiber: TProc<TObjectList<TLeakFinding>, string>;
  AFindings: TObjectList<TLeakFinding>): TBytes;
var
  Ziel : string;
begin
  Ziel := TPath.Combine(TPath.GetTempPath,
    'sca_' + TPath.GetGUIDFileName(False) + AEndung);
  try
    ASchreiber(AFindings, Ziel);
    Result := TFile.ReadAllBytes(Ziel);
  finally
    if TFile.Exists(Ziel) then
      TFile.Delete(Ziel);
  end;
end;

// Der Textteil einer Ausgabe ohne die UTF-8-Praeambel.
function TextOhnePraeambel(const ABytes: TBytes): string;
begin
  if HatUtf8Praeambel(ABytes) then
    Result := TEncoding.UTF8.GetString(ABytes, 3, Length(ABytes) - 3)
  else
    Result := TEncoding.UTF8.GetString(ABytes);
end;

procedure TTestExport.ExportCsv_MitBomUndForwardSlashes;
// Der Writer als GANZES. Bis 08.09. gab es fuer ExportCsv und
// ExportJson keinen einzigen Test - geprueft waren nur die Helfer eine
// Ebene tiefer. Damit waere ein vertauschtes Flag
// (SaveBuilderUtf8(..., False) fuer CSV) durchgegangen, obwohl alle
// drei BOM-Tests gruen bleiben. Genau davor soll die Politik schuetzen.
//
// Zweiter Zweck: hier zeigt sich, ob der BLOCKER-Fix in
// RelativeDisplayPath beim KONSUMENTEN ankommt. Der bisherige Test
// prueft nur den Helfer - dass ExportCsv ihn mit dem BaseDir auch
// fuettert, stand nirgends.
var
  L : TObjectList<TLeakFinding>;
  B : TBytes;
  T : string;
begin
  L := EineFundliste;
  try
    B := ExportBytes('.csv',
      procedure(AL: TObjectList<TLeakFinding>; AZiel: string)
      begin
        TExporter.ExportCsv(AL, AZiel, 'D:\proj');
      end, L);
  finally
    L.Free;
  end;

  Assert.IsTrue(HatUtf8Praeambel(B),
    'die CSV braucht das BOM - deutsches Excel erkennt UTF-8 nur daran');
  T := TextOhnePraeambel(B);
  Assert.IsTrue(T.StartsWith('File;Method;Line;Kind;Severity;Detail'),
    'die Kopfzeile ist ein Vertrag nach aussen: ' + Copy(T, 1, 60));
  Assert.IsTrue(T.Contains('src/uMain.pas'),
    'der Pfad muss RELATIV und mit Forward Slashes stehen - genau das '
    + 'war der BLOCKER: ' + Copy(T, 1, 200));
  Assert.AreEqual<Integer>(0, Pos('src\uMain.pas', T),
    'kein Windows-Trenner im Relativpfad');
end;

procedure TTestExport.ExportJson_OhneBomUndForwardSlashes;
// Die Gegenrichtung: JSON darf KEINE Praeambel tragen, und derselbe
// Pfad muss auch hier relativ mit Forward Slashes stehen. Erst das Paar
// haelt fest, dass die beiden Writer unterschiedlich flaggen - ein
// einzelner Test waere auch dann gruen, wenn beide dasselbe taeten.
var
  L : TObjectList<TLeakFinding>;
  B : TBytes;
  T : string;
begin
  L := EineFundliste;
  try
    B := ExportBytes('.json',
      procedure(AL: TObjectList<TLeakFinding>; AZiel: string)
      begin
        TExporter.ExportJson(AL, AZiel, 'D:\proj');
      end, L);
  finally
    L.Free;
  end;

  Assert.IsFalse(HatUtf8Praeambel(B),
    'die JSON-Ausgabe traegt eine BOM-Praeambel - RFC 8259 par.8.1 '
    + 'verbietet sie, und Nodes JSON.parse scheitert daran');
  T := TextOhnePraeambel(B);
  Assert.IsTrue(T.Contains('"file": "src/uMain.pas"'),
    'Pfad relativ mit Forward Slashes im file-Feld: ' + Copy(T, 1, 200));
  Assert.IsTrue(T.Contains('"line": 42'),
    'die Zeilennummer geht als ZAHL raus, nicht als Zeichenkette');
  Assert.IsTrue(T.TrimRight.EndsWith(']'),
    'das Array muss geschlossen sein - ein abgebrochener Schreibvorgang '
    + 'faellt sonst nicht auf');
end;

procedure TTestExport.ExportCsvUndJson_VertragenNil;
// Beide Writer pruefen auf nil (Assigned(Findings)). Der Sonar-Writer
// tat das bis 08.09. NICHT und lief in eine AV - dieselbe Zusage
// gehoert hier festgehalten, sonst faellt sie beim naechsten Umbau
// still um. Erwartet wird eine gueltige, leere Ausgabe.
var
  B : TBytes;
  T : string;
begin
  B := ExportBytes('.csv',
    procedure(AL: TObjectList<TLeakFinding>; AZiel: string)
    begin
      TExporter.ExportCsv(AL, AZiel, '');
    end, nil);
  T := TextOhnePraeambel(B);
  Assert.IsTrue(T.StartsWith('File;Method;Line;Kind;Severity;Detail'),
    'die CSV behaelt ihre Kopfzeile auch ohne Funde');

  B := ExportBytes('.json',
    procedure(AL: TObjectList<TLeakFinding>; AZiel: string)
    begin
      TExporter.ExportJson(AL, AZiel, '');
    end, nil);
  T := TextOhnePraeambel(B).Trim;
  Assert.IsTrue(T.StartsWith('[') and T.EndsWith(']'),
    'JSON bleibt ein gueltiges, leeres Array: ' + T);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestExport);

end.
