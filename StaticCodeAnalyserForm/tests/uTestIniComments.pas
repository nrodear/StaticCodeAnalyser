unit uTestIniComments;

// Tests fuer TCommentPreservingIni (uRepoSettings) - der INI-Schreiber, der
// Kommentare, Reihenfolge und auskommentierte Beispiele der analyser.ini
// erhaelt.
//
// WARUM ES DIESE KLASSE GIBT: die Datei wird beim ersten Start aus einem
// Template erzeugt, das jeden Schluessel erklaert. TMemIniFile schreibt beim
// UpdateFile die ganze Datei aus seinem Speichermodell neu und kennt darin
// nur Sektionen, Schluessel und Werte - ein einziges Speichern der
// Options-Seite loeschte damit die komplette Dokumentation der Datei
// (gemeldet 2026-08-21).
//
// Die Tests arbeiten auf einer echten Datei im Temp-Verzeichnis, weil die
// Klasse genau das tut: Text laden, eine Zeile ersetzen, Text speichern.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestIniComments = class
  private
    FPath : string;
    procedure Given(const AContent: string);
    function  Content: string;
    function  HasLine(const ALine: string): Boolean;
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure ChangedValue_KeepsCommentsAndOrder;
    [Test] procedure ChangedValue_LeavesCommentedExampleAlone;
    [Test] procedure NewKey_GoesAfterLastEntryOfItsSection;
    [Test] procedure NewKey_InSectionWithoutEntries_GoesRightAfterHeader;
    [Test] procedure MissingSection_IsAppendedAtEndOfFile;
    [Test] procedure SectionAndKey_MatchCaseInsensitively;
    [Test] procedure UnchangedValue_LeavesFileUntouched;
    [Test] procedure BoolAndInteger_UseTheSameShapeAsBefore;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, uRepoSettings;

const
  // Ausschnitt im Stil der echten analyser.ini: Erklaerblock, Wert,
  // auskommentiertes Beispiel.
  SAMPLE =
    '[UI]'#13#10 +
    '; Language (string, default: system)'#13#10 +
    '; Sprache der Oberflaeche.'#13#10 +
    'Language=de'#13#10 +
    ';Language=en'#13#10 +
    ''#13#10 +
    '; Theme (string, default: system)'#13#10 +
    'Theme=system'#13#10 +
    ';Theme=dark'#13#10 +
    ''#13#10 +
    '[Empty]'#13#10 +
    ''#13#10 +
    '[Rules]'#13#10 +
    '; Profil-Erklaerung'#13#10 +
    'Profile=default'#13#10;
  // Als Konstanten, weil der Selbst-Scan wiederholte Literale sonst als
  // DuplicateString meldet - und die Baseline anzufassen waere hier die
  // falsche Antwort.
  KEY_LANG = 'Language';
  CLIP_SET = 'ClipboardOnClick=2';

procedure TTestIniComments.Setup;
begin
  FPath := TPath.Combine(TPath.GetTempPath,
    'sca_ini_comments_' + TGUID.NewGuid.ToString + '.ini');
end;

procedure TTestIniComments.TearDown;
begin
  if TFile.Exists(FPath) then
  begin
    TFile.Delete(FPath);
  end;
end;

procedure TTestIniComments.Given(const AContent: string);
begin
  TFile.WriteAllText(FPath, AContent, TEncoding.UTF8);
end;

function TTestIniComments.Content: string;
begin
  Result := TFile.ReadAllText(FPath, TEncoding.UTF8);
end;

function TTestIniComments.HasLine(const ALine: string): Boolean;
var
  SL : TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Text := Content;
    Result  := SL.IndexOf(ALine) >= 0;
  finally
    SL.Free;
  end;
end;

procedure TTestIniComments.ChangedValue_KeepsCommentsAndOrder;
// Der Kern des gemeldeten Fehlers.
var
  Ini : TCommentPreservingIni;
begin
  Given(SAMPLE);
  Ini := TCommentPreservingIni.Create(FPath);
  try
    Ini.WriteString('UI', KEY_LANG, 'en');
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
  Assert.IsTrue(HasLine('; Language (string, default: system)'),
    'der Erklaerblock muss stehenbleiben');
  Assert.IsTrue(HasLine('; Sprache der Oberflaeche.'));
  Assert.IsTrue(HasLine('; Profil-Erklaerung'),
    'auch Kommentare anderer Sektionen');
  Assert.IsTrue(HasLine('Language=en'), 'der Wert muss ankommen');
  Assert.IsFalse(HasLine('Language=de'));
end;

procedure TTestIniComments.ChangedValue_LeavesCommentedExampleAlone;
// ';Language=en' ist ein KOMMENTAR, kein Schluessel. Wer ihn als Schluessel
// liest, schaltet beim Schreiben ein auskommentiertes Beispiel scharf.
var
  Ini : TCommentPreservingIni;
begin
  Given(SAMPLE);
  Ini := TCommentPreservingIni.Create(FPath);
  try
    Ini.WriteString('UI', KEY_LANG, 'fr');
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
  Assert.IsTrue(HasLine(';Language=en'),
    'das auskommentierte Beispiel bleibt unveraendert');
  Assert.IsTrue(HasLine('Language=fr'));
end;

procedure TTestIniComments.NewKey_GoesAfterLastEntryOfItsSection;
var
  Ini : TCommentPreservingIni;
  SL  : TStringList;
begin
  Given(SAMPLE);
  Ini := TCommentPreservingIni.Create(FPath);
  try
    Ini.WriteInteger('UI', 'ClipboardOnClick', 2);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
  SL := TStringList.Create;
  try
    SL.Text := Content;
    Assert.IsTrue(SL.IndexOf(CLIP_SET) > SL.IndexOf('[UI]'),
      'muss IN der Sektion [UI] stehen');
    Assert.IsTrue(SL.IndexOf(CLIP_SET) < SL.IndexOf('[Empty]'),
      'und vor der naechsten Sektion');
    Assert.IsTrue(SL.IndexOf(CLIP_SET) > SL.IndexOf(';Theme=dark'),
      'hinter dem letzten Eintrag, nicht vor dessen Erklaerblock');
  finally
    SL.Free;
  end;
end;

procedure TTestIniComments.NewKey_InSectionWithoutEntries_GoesRightAfterHeader;
// Eine Sektion, die nur aus ihrer Kopfzeile besteht. Ohne Sonderbehandlung
// landet der Schluessel am DATEIENDE - also in einer fremden Sektion.
var
  Ini : TCommentPreservingIni;
  SL  : TStringList;
begin
  Given(SAMPLE);
  Ini := TCommentPreservingIni.Create(FPath);
  try
    Ini.WriteString('Empty', 'Neu', '1');
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
  SL := TStringList.Create;
  try
    SL.Text := Content;
    Assert.AreEqual(SL.IndexOf('[Empty]') + 1, SL.IndexOf('Neu=1'),
      'direkt hinter die Kopfzeile');
    Assert.IsTrue(SL.IndexOf('Neu=1') < SL.IndexOf('[Rules]'),
      'nicht in die naechste Sektion gerutscht');
  finally
    SL.Free;
  end;
end;

procedure TTestIniComments.MissingSection_IsAppendedAtEndOfFile;
var
  Ini : TCommentPreservingIni;
begin
  Given(SAMPLE);
  Ini := TCommentPreservingIni.Create(FPath);
  try
    Ini.WriteString('Baseline', 'File', 'x.json');
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
  Assert.IsTrue(HasLine('[Baseline]'), 'Sektion wird angelegt');
  Assert.IsTrue(HasLine('File=x.json'));
  Assert.IsTrue(HasLine('Profile=default'), 'Bestand bleibt unangetastet');
end;

procedure TTestIniComments.SectionAndKey_MatchCaseInsensitively;
// INI-Namen sind traditionell case-insensitiv - sonst entstuenden stille
// Dubletten wie 'Language' neben 'language'.
var
  Ini : TCommentPreservingIni;
  SL  : TStringList;
  n   : Integer;
  i   : Integer;
begin
  Given(SAMPLE);
  Ini := TCommentPreservingIni.Create(FPath);
  try
    Ini.WriteString('ui', 'language', 'it');
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
  SL := TStringList.Create;
  try
    SL.Text := Content;
    n := 0;
    for i := 0 to SL.Count - 1 do
      if SL[i].StartsWith('language=', True) then
      begin
        Inc(n);
      end;
    Assert.AreEqual(1, n, 'genau ein Eintrag, keine Dublette');
  finally
    SL.Free;
  end;
end;

procedure TTestIniComments.UnchangedValue_LeavesFileUntouched;
// Ein Options-Dialog, der ohne Aenderung geschlossen wird, darf die Datei
// nicht anfassen.
var
  Ini    : TCommentPreservingIni;
  Before : string;
begin
  Given(SAMPLE);
  Before := Content;
  Ini := TCommentPreservingIni.Create(FPath);
  try
    Ini.WriteString('UI', KEY_LANG, 'de');   // derselbe Wert
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
  Assert.AreEqual(Before, Content, 'unveraendert heisst unveraendert');
end;

procedure TTestIniComments.BoolAndInteger_UseTheSameShapeAsBefore;
// '1'/'0' wie TMemIniFile.WriteBool - sonst liest der naechste Start
// andere Werte, als der vorige geschrieben hat.
var
  Ini : TCommentPreservingIni;
begin
  Given(SAMPLE);
  Ini := TCommentPreservingIni.Create(FPath);
  try
    Ini.WriteBool('UI', 'OverlayTextOnly', True);
    Ini.WriteBool('UI', 'OverlayShowOnHover', False);
    Ini.WriteInteger('UI', 'ClipboardOnClick', 2);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
  Assert.IsTrue(HasLine('OverlayTextOnly=1'));
  Assert.IsTrue(HasLine('OverlayShowOnHover=0'));
  Assert.IsTrue(HasLine(CLIP_SET));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestIniComments);

end.
