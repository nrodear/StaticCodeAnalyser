unit uTestRdxText;

// Die Sprache der reDelphix-Texte (uRdxText, Entscheid E29, Charge C0):
// Override, die drei Quellen (redelphix.ini, Sprache der SCA, analyser.ini),
// Kommentarzeilen, die Vorlage beim ersten Zugriff, neues Lesen nur bei
// neuer Dateizeit, ein nicht anlegbarer Ordner ohne Ausnahme. Ohne Parser -
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
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uLocalization,   // SetLanguage, CurrentLanguage: die Sprache der SCA
  uRdxText;        // _ (immer qualifiziert: uLocalization hat auch eines)

const
  CHANGES_DE = '('#$00E4'ndert Verhalten)';

// ---- Helfer ----

// Ein frisches, noch NICHT angelegtes Verzeichnis TEMP\rdx_c0_<GUID>\ - so
// prueft der Vorlagen-Test auch das Anlegen des Ordners.
function FreshDir: string;
var
  G : TGUID;
begin
  CreateGUID(G);
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP'))
    + 'rdx_c0_' + GUIDToString(G) + PathDelim;
end;

// Loescht den Baum ADir (mit Trenner) samt Inhalt.
procedure RemoveTree(const ADir: string);
var
  SR : TSearchRec;
begin
  if FindFirst(ADir + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then
        Continue;
      if (SR.Attr and faDirectory) <> 0 then
        RemoveTree(ADir + SR.Name + PathDelim)
      else
        DeleteFile(ADir + SR.Name);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
  RemoveDir(ADir);
end;

// Schreibt AText als UTF-8 ohne BOM (TStringList waere unter FPC ANSI).
procedure WriteText(const APath, AText: string);
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
    WriteText(RdxIniPath, '[UI]'#13#10'Language=auto'#13#10);
    WriteText(Scope.Dir + 'analyser.ini', '[UI]'#13#10'Language=de'#13#10);
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
    WriteText(RdxIniPath, RdxIniTemplate);
    WriteText(Scope.Dir + 'analyser.ini', '[UI]'#13#10';Language=fr'#13#10
      + 'Language=de'#13#10);
    Assert.AreEqual('de', RdxLanguage,
      'analyser.ini [UI] Language - das auskommentierte Beispiel zaehlt nicht');
  finally
    LeaveIni(Scope);
  end;
  Scope := EnterIni('');
  try
    ForceDirectories(Scope.Dir);
    WriteText(Scope.Dir + 'analyser.ini', '[UI]'#13#10';Language=de'#13#10);
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
    WriteText(RdxIniPath, '[UI]'#13#10'Language=fr'#13#10);
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
    WriteText(RdxIniPath, '[UI]'#13#10'Language=de'#13#10);
    Assert.AreEqual<Integer>(0, FileSetDate(RdxIniPath, DateTimeToFileDate(T0)));
    Assert.AreEqual('de', RdxLanguage);
    WriteText(RdxIniPath, '[UI]'#13#10'Language=fr'#13#10);
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
// versucht es nicht erneut.
var
  Scope : TIniScope;
begin
  Scope := EnterIni('');
  try
    ForceDirectories(Scope.Dir);
    WriteText(Scope.Dir + 'blocker', 'Datei statt Ordner');
    SetRdxConfigDir(Scope.Dir + 'blocker' + PathDelim + 'sub' + PathDelim);
    Assert.AreEqual('en', RdxLanguage, 'Vorgabe auto, keine Ausnahme');
    Assert.IsFalse(FileExists(RdxIniPath), 'keine Datei');
    Assert.AreEqual('en', RdxLanguage, 'zweiter Aufruf ebenso');
  finally
    LeaveIni(Scope);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxText);

end.
