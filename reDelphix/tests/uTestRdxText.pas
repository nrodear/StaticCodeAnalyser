unit uTestRdxText;

// Die Sprache der reDelphix-Texte (uRdxText, Entscheid E29, Charge C0):
// Override, die drei Quellen (redelphix.ini, Sprache der SCA, analyser.ini),
// Kommentarzeilen, die Vorlage beim ersten Zugriff, neues Lesen nur bei
// neuer Dateizeit, ein nicht anlegbarer Ordner ohne Ausnahme und mit EINEM
// Versuch, eine zu grosse ini, der Override 'auto'. Ohne Parser -
// laeuft in reDelphix.Test (echte uLocalization, eingebettete .po) UND im
// FPC-Pruefstand (Stub uLocalization, die echten i18n/*.po neben dem
// Runner): dieselben Erwartungen pinnen so auch NormalizeLangCode des
// Stubs gegen die echte Unit.
// Die ini-Tests lenken das Konfigurationsverzeichnis nach
// TEMP\rdx_c0_<GUID>\ um (EnterIni) und raeumen es ab (LeaveIni) - %APPDATA%
// bleibt unberuehrt. Jeder Test stellt Override, Verzeichnis und SCA-Sprache
// wieder her: der Lauf steht auf 'de' (reDelphix.Test.dpr bzw. build.sh).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxText = class
  public
    [Test] procedure Override_German_TranslatesMenuTexts;
    [Test] procedure Override_FrenchEnglishUnknown;
    [Test] procedure Override_NormalizedLikeTheSca;
    [Test] procedure Override_LeavesDiskAlone;
    [Test] procedure Resolve_AutoFollowsScaThenAnalyserIni;
    [Test] procedure Resolve_FixedValueWins;
    [Test] procedure IniTextValue_CommentsSectionsLineEnds;
    [Test] procedure Ini_Missing_TemplateWritten;
    [Test] procedure Ini_Auto_FollowsScaLanguageAtOnce;
    [Test] procedure Ini_Auto_WithoutScaLanguage_ReadsAnalyserIni;
    [Test] procedure Ini_FixedLanguage_BeatsSca;
    [Test] procedure Ini_ReadAgainOnlyOnNewFileTime;
    [Test] procedure Ini_FolderNotCreatable_NoException;
    // Review Woche G05-26.
    [Test] procedure Ini_TooLarge_CountsAsMissing;
    [Test] procedure Override_Auto_FollowsSca;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uLocalization,   // SetLanguage, CurrentLanguage: die Sprache der SCA
  uRdxText,        // _ (immer qualifiziert: uLocalization hat auch eines)
  uTestRdxTextKit; // TempName, RemoveTree

const
  CHANGES_DE = '('#$00E4'ndert Verhalten)';

// ---- Helfer ----

// Ein frisches, noch NICHT angelegtes Verzeichnis TEMP\rdx_c0_<GUID>\ - so
// prueft der Vorlagen-Test auch das Anlegen des Ordners.
function FreshDir: string;
begin
  Result := TempName('rdx_c0_', PathDelim);
end;

// Schreibt AText als UTF-8 ohne BOM, den Text unveraendert. Eigener Name:
// uTestRdxTextKit.WriteText schreibt ueber TStringList - unter FPC ANSI,
// mit Zeilenende am Schluss.
procedure WriteUtf8(const APath, AText: string);
var
  Bytes : TBytes;
  FS    : TFileStream;
begin
  Bytes := TEncoding.UTF8.GetBytes(AText);
  FS := TFileStream.Create(APath, fmCreate);
  try
    if Length(Bytes) > 0 then
      FS.WriteBuffer(Bytes[0], Length(Bytes));
  finally
    FS.Free;
  end;
end;

function ReadBytes(const APath: string): TBytes;
var
  FS : TFileStream;
begin
  FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, FS.Size);
    if Length(Result) > 0 then
      FS.ReadBuffer(Result[0], Length(Result));
  finally
    FS.Free;
  end;
end;

type
  // Was ein ini-Test umstellt und LeaveIni wiederherstellt.
  TIniScope = record
    Dir         : string;   // das umgelenkte Verzeichnis (mit Trenner)
    OldOverride : string;   // der Override des Laufs ('de')
    OldSca      : string;   // die Sprache der SCA davor
  end;

// Kein Override (die ini entscheidet), Verzeichnis FreshDir (noch nicht
// angelegt), SCA-Sprache AScaLanguage.
function EnterIni(const AScaLanguage: string): TIniScope;
begin
  Result.OldOverride := RdxLanguageOverride;
  Result.OldSca := CurrentLanguage;
  Result.Dir := FreshDir;
  SetRdxLanguageOverride('');
  SetRdxConfigDir(Result.Dir);
  SetLanguage(AScaLanguage);
end;

procedure LeaveIni(const AScope: TIniScope);
begin
  SetLanguage(AScope.OldSca);
  SetRdxConfigDir('');
  SetRdxLanguageOverride(AScope.OldOverride);
  RemoveTree(AScope.Dir);
end;

// ---- Override ----

procedure TTestRdxText.Override_German_TranslatesMenuTexts;
var
  Old : string;
begin
  Old := RdxLanguageOverride;
  try
    SetRdxLanguageOverride('de');
    Assert.AreEqual('de', RdxLanguage);
    Assert.AreEqual('Stelle zeigen', uRdxText._('Show location'));
    Assert.AreEqual('Zeile 1:2 bis 3:4',
      uRdxText._('Line %d:%d to %d:%d', [1, 2, 3, 4]));
    Assert.AreEqual(CHANGES_DE, uRdxText._('(changes behavior)'),
      'Umlaut aus der .po');
    Assert.AreEqual('no such msgid', uRdxText._('no such msgid'),
      'ohne Eintrag bleibt der englische Text');
  finally
    SetRdxLanguageOverride(Old);
  end;
end;

procedure TTestRdxText.Override_FrenchEnglishUnknown;
var
  Old : string;
begin
  Old := RdxLanguageOverride;
  try
    SetRdxLanguageOverride('fr');
    Assert.AreEqual('fr', RdxLanguage);
    Assert.AreEqual('Afficher l''emplacement', uRdxText._('Show location'));
    SetRdxLanguageOverride('en');
    Assert.AreEqual('en', RdxLanguage);
    Assert.AreEqual('Show location', uRdxText._('Show location'));
    // Ein Kuerzel ohne Uebersetzung zeigt Englisch - wie SetLanguage in der
    // SCA; es bleibt aber das Kuerzel (eine eigene .po neben der BPL).
    SetRdxLanguageOverride('xx');
    Assert.AreEqual('xx', RdxLanguage);
    Assert.AreEqual('Show location', uRdxText._('Show location'));
  finally
    SetRdxLanguageOverride(Old);
  end;
end;

procedure TTestRdxText.Override_NormalizedLikeTheSca;
// NormalizeLangCode: in reDelphix.Test die echte, im Pruefstand die Kopie
// des Stubs - dieselben Erwartungen in beiden Welten.
var
  Old : string;
begin
  Old := RdxLanguageOverride;
  try
    SetRdxLanguageOverride('de-DE');
    Assert.AreEqual('de', RdxLanguage, 'Region abgeschnitten');
    SetRdxLanguageOverride(' DE ');
    Assert.AreEqual('de', RdxLanguage, 'Leerraum, Grossschreibung');
    SetRdxLanguageOverride('Fr_ca');
    Assert.AreEqual('fr', RdxLanguage, 'Unterstrich');
    SetRdxLanguageOverride('..\..\boese');
    Assert.AreEqual('en', RdxLanguage, 'kein Kuerzel: Englisch');
  finally
    SetRdxLanguageOverride(Old);
  end;
end;

procedure TTestRdxText.Override_LeavesDiskAlone;
// Mit Override wird redelphix.ini weder gelesen noch angelegt - deshalb
// beschreibt kein Testlauf %APPDATA%.
var
  Scope : TIniScope;
begin
  Scope := EnterIni('');
  try
    SetRdxLanguageOverride('de');
    Assert.AreEqual('de', RdxLanguage);
    Assert.AreEqual('Stelle zeigen', uRdxText._('Show location'));
    Assert.IsFalse(DirectoryExists(Scope.Dir),
      'mit Override weder Ordner noch redelphix.ini');
  finally
    LeaveIni(Scope);
  end;
end;

// ---- die drei Quellen (rein) ----

procedure TTestRdxText.Resolve_AutoFollowsScaThenAnalyserIni;
begin
  Assert.AreEqual('fr', ResolveRdxLanguage('auto', 'fr', 'de'),
    'auto: zuerst die gesetzte Sprache der SCA');
  Assert.AreEqual('fr', ResolveRdxLanguage('', 'fr-FR', 'de'),
    'leer heisst auto');
  Assert.AreEqual('de', ResolveRdxLanguage(' Auto ', '', 'de'),
    'SCA ohne Sprache: analyser.ini');
  Assert.AreEqual('de', ResolveRdxLanguage('AUTO', '..\x', 'DE'),
    'kein Kuerzel der SCA zaehlt nicht');
  Assert.AreEqual('en', ResolveRdxLanguage('auto', '', ''), 'sonst Englisch');
  Assert.AreEqual('en', ResolveRdxLanguage('auto', '', '..\x'));
end;

procedure TTestRdxText.Resolve_FixedValueWins;
begin
  Assert.AreEqual('de', ResolveRdxLanguage('de', 'fr', 'fr'));
  Assert.AreEqual('en', ResolveRdxLanguage('en', 'de', 'de'),
    'en fest schlaegt die deutsche SCA');
  Assert.AreEqual('fr', ResolveRdxLanguage('FR-ca', 'de', ''));
  Assert.AreEqual('xx', ResolveRdxLanguage('xx', 'de', 'de'),
    'Kuerzel ohne .po bleibt (zeigt Englisch)');
  Assert.AreEqual('en', ResolveRdxLanguage('..\boese', 'de', 'de'),
    'Muell heisst Englisch, nicht auto');
end;

procedure TTestRdxText.IniTextValue_CommentsSectionsLineEnds;
const
  INI = '; Kopf'#13#10
    + 'Language=fr'#13#10            // vor jeder Sektion: zaehlt nicht
    + '[Other]'#13#10
    + 'Language=fr'#13#10
    + '[ui]'#10                      // LF, Kleinschreibung
    + ';Language=fr'#13              // CR, auskommentiertes Beispiel
    + '#Language=fr'#13#10
    + '  language  =  de  '#13#10   // Leerraum um '=' wie TMemIniFile
    + 'Language=en'#13#10            // zweiter Treffer zaehlt nicht
    + 'Key=a=b';
begin
  Assert.AreEqual('de', IniTextValue(INI, 'UI', 'Language'));
  Assert.AreEqual('fr', IniTextValue(INI, 'OTHER', 'LANGUAGE'));
  Assert.AreEqual('a=b', IniTextValue(INI, 'UI', 'Key'), 'nur das erste =');
  Assert.AreEqual('', IniTextValue(INI, 'UI', 'Theme'), 'fehlt');
  Assert.AreEqual('', IniTextValue(';[UI]'#13#10'Language=de', 'UI',
    'Language'), 'auskommentierte Sektion');
  Assert.AreEqual('', IniTextValue('', 'UI', 'Language'));
  Assert.AreEqual('auto', IniTextValue(RdxIniTemplate, 'UI', 'Language'),
    'die Vorlage: aktiv auto, ;Language=de ist ein Beispiel');
end;

// ---- redelphix.ini und analyser.ini auf der Platte ----

procedure TTestRdxText.Ini_Missing_TemplateWritten;
var
  Scope    : TIniScope;
  Bytes    : TBytes;
  Template : string;
begin
  Scope := EnterIni('');
  try
    Template := RdxIniTemplate;
    Assert.IsFalse(DirectoryExists(Scope.Dir), 'Vorbedingung: Ordner fehlt');
    Assert.AreEqual(Scope.Dir + 'redelphix.ini', RdxIniPath);
    Assert.AreEqual('en', RdxLanguage,
      'auto, keine SCA-Sprache, keine analyser.ini');
    Assert.IsTrue(FileExists(RdxIniPath), 'Vorlage samt Ordner angelegt');
    Bytes := ReadBytes(RdxIniPath);
    Assert.IsTrue((Length(Bytes) > 3) and (Bytes[0] = $EF)
      and (Bytes[1] = $BB) and (Bytes[2] = $BF), 'UTF-8-BOM wie analyser.ini');
    Assert.AreEqual(Template,
      TEncoding.UTF8.GetString(Bytes, 3, Length(Bytes) - 3), 'woertlich');
    Assert.AreEqual('auto', RdxIniValue('UI', 'Language'));
    Assert.IsTrue(Pos(#13#10'[UI]'#13#10, Template) > 0, 'Sektion [UI]');
    Assert.IsTrue(Pos(#13#10'Language=auto'#13#10, Template) > 0,
      'Vorgabe aktiv');
    Assert.IsTrue(Pos(#13#10';Language=de'#13#10, Template) > 0,
      'Beispiel auskommentiert');
    Assert.IsTrue(Pos('%APPDATA%\StaticCodeAnalyser\redelphix.ini',
      Template) > 0, 'der Kopf nennt den Ort');
  finally
    LeaveIni(Scope);
  end;
end;

procedure TTestRdxText.Ini_Auto_FollowsScaLanguageAtOnce;
var
  Scope : TIniScope;
begin
  Scope := EnterIni('fr');
  try
    ForceDirectories(Scope.Dir);
    WriteUtf8(RdxIniPath, '[UI]'#13#10'Language=auto'#13#10);
    WriteUtf8(Scope.Dir + 'analyser.ini', '[UI]'#13#10'Language=de'#13#10);
    Assert.AreEqual('fr', RdxLanguage, 'die gesetzte SCA-Sprache vor der ini');
    Assert.AreEqual('Afficher l''emplacement', uRdxText._('Show location'));
    // Umschalten in den SCA-Optionen (SetLanguage) gilt beim naechsten
    // Aufruf - kein Neustart, kein Cache dazwischen.
    SetLanguage('de');
    Assert.AreEqual('de', RdxLanguage);
    Assert.AreEqual('Stelle zeigen', uRdxText._('Show location'));
    SetLanguage('en');
    Assert.AreEqual('en', RdxLanguage, 'auch Englisch der SCA gilt');
  finally
    LeaveIni(Scope);
  end;
end;

procedure TTestRdxText.Ini_Auto_WithoutScaLanguage_ReadsAnalyserIni;
var
  Scope : TIniScope;
begin
  Scope := EnterIni('');
  try
    ForceDirectories(Scope.Dir);
    WriteUtf8(RdxIniPath, RdxIniTemplate);
    WriteUtf8(Scope.Dir + 'analyser.ini', '[UI]'#13#10';Language=fr'#13#10
      + 'Language=de'#13#10);
    Assert.AreEqual('de', RdxLanguage,
      'analyser.ini [UI] Language - das auskommentierte Beispiel zaehlt nicht');
  finally
    LeaveIni(Scope);
  end;
  Scope := EnterIni('');
  try
    ForceDirectories(Scope.Dir);
    WriteUtf8(Scope.Dir + 'analyser.ini', '[UI]'#13#10';Language=de'#13#10);
    Assert.AreEqual('en', RdxLanguage,
      'nur ein auskommentiertes Beispiel: Englisch');
    Assert.IsTrue(FileExists(RdxIniPath), 'redelphix.ini wurde angelegt');
  finally
    LeaveIni(Scope);
  end;
end;

procedure TTestRdxText.Ini_FixedLanguage_BeatsSca;
var
  Scope : TIniScope;
begin
  Scope := EnterIni('de');
  try
    ForceDirectories(Scope.Dir);
    WriteUtf8(RdxIniPath, '[UI]'#13#10'Language=fr'#13#10);
    Assert.AreEqual('fr', RdxLanguage);
    Assert.AreEqual('Afficher l''emplacement', uRdxText._('Show location'));
    Assert.AreEqual('de', CurrentLanguage,
      'die Sprache der SCA bleibt unberuehrt');
  finally
    LeaveIni(Scope);
  end;
end;

procedure TTestRdxText.Ini_ReadAgainOnlyOnNewFileTime;
// Je Aufruf nur ein FileAge: gleiche Dateizeit heisst "unveraendert". Die
// Zeiten sind gerade Sekunden (FileSetDate rechnet in 2-s-Schritten).
var
  Scope : TIniScope;
  T0    : TDateTime;
begin
  Scope := EnterIni('');
  try
    ForceDirectories(Scope.Dir);
    T0 := EncodeDate(2020, 1, 1) + EncodeTime(10, 0, 0, 0);
    WriteUtf8(RdxIniPath, '[UI]'#13#10'Language=de'#13#10);
    Assert.AreEqual<Integer>(0, FileSetDate(RdxIniPath, DateTimeToFileDate(T0)));
    Assert.AreEqual('de', RdxLanguage);
    WriteUtf8(RdxIniPath, '[UI]'#13#10'Language=fr'#13#10);
    Assert.AreEqual<Integer>(0, FileSetDate(RdxIniPath, DateTimeToFileDate(T0)));
    Assert.AreEqual('de', RdxLanguage, 'gleiche Dateizeit: der Cache gilt');
    Assert.AreEqual<Integer>(0, FileSetDate(RdxIniPath,
      DateTimeToFileDate(T0 + 1 / 24)));
    Assert.AreEqual('fr', RdxLanguage, 'neue Dateizeit: neu gelesen');
  finally
    LeaveIni(Scope);
  end;
end;

procedure TTestRdxText.Ini_FolderNotCreatable_NoException;
// Ein Ordner, der sich nicht anlegen laesst (eine DATEI steht im Weg):
// keine Ausnahme, keine Datei, die Vorgabe auto - und der zweite Aufruf
// versucht es nicht erneut (GTemplateTried: je Verzeichnis EIN Versuch).
// Beobachtet seit Review Woche G05-26: ist der Blocker weg, legt der zweite
// Aufruf trotzdem nichts an; erst SetRdxConfigDir erlaubt den neuen
// Versuch. Ohne die Sperre legte schon der zweite Aufruf die Vorlage an.
var
  Scope : TIniScope;
  Dir   : string;
begin
  Scope := EnterIni('');
  try
    ForceDirectories(Scope.Dir);
    WriteUtf8(Scope.Dir + 'blocker', 'Datei statt Ordner');
    Dir := Scope.Dir + 'blocker' + PathDelim + 'sub' + PathDelim;
    SetRdxConfigDir(Dir);
    Assert.AreEqual('en', RdxLanguage, 'Vorgabe auto, keine Ausnahme');
    Assert.IsFalse(FileExists(RdxIniPath), 'keine Datei');
    Assert.IsTrue(DeleteFile(Scope.Dir + 'blocker'), 'Vorbedingung: Blocker weg');
    Assert.AreEqual('en', RdxLanguage, 'zweiter Aufruf ebenso');
    Assert.IsFalse(FileExists(RdxIniPath),
      'der Versuch ist verbraucht - kein zweiter Plattenzugriff');
    SetRdxConfigDir(Dir);
    Assert.AreEqual('en', RdxLanguage);
    Assert.IsTrue(FileExists(RdxIniPath),
      'SetRdxConfigDir erlaubt einen neuen Versuch');
  finally
    LeaveIni(Scope);
  end;
end;

procedure TTestRdxText.Ini_TooLarge_CountsAsMissing;
// Eine redelphix.ini ueber MAX_INI_BYTES (1 MB) gilt als fehlend - ihr
// Wert zaehlt nicht, die Vorgabe auto entscheidet (hier Englisch); die
// Datei bleibt, wie sie ist (Review Woche G05-26).
var
  Scope : TIniScope;
begin
  Scope := EnterIni('');
  try
    ForceDirectories(Scope.Dir);
    WriteUtf8(RdxIniPath, '[UI]'#13#10'Language=fr'#13#10';'
      + StringOfChar('x', 1024 * 1024) + #13#10);
    Assert.AreEqual('en', RdxLanguage, 'zu gross: wie fehlend');
    Assert.IsTrue(FileExists(RdxIniPath), 'nicht ersetzt');
  finally
    LeaveIni(Scope);
  end;
end;

procedure TTestRdxText.Override_Auto_FollowsSca;
// Der Override 'auto' (Kopf: "'de', 'en', 'auto' ...") ersetzt den Wert der
// ini wie jeder andere: die Sprache der SCA gilt, redelphix.ini wird weder
// gelesen noch angelegt (Review Woche G05-26).
var
  Scope : TIniScope;
begin
  Scope := EnterIni('fr');
  try
    SetRdxLanguageOverride('auto');
    Assert.AreEqual('fr', RdxLanguage, 'auto: die Sprache der SCA');
    SetLanguage('');
    Assert.AreEqual('en', RdxLanguage, 'SCA ohne Sprache, keine analyser.ini');
    Assert.IsFalse(DirectoryExists(Scope.Dir), 'keine Vorlage angelegt');
  finally
    LeaveIni(Scope);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxText);

end.
