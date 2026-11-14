unit uTestConsoleExitCode;

// Tests fuer die Exit-Code-Ermittlung der CLI: die Rangleiter in
// TConsoleRunner.CalcExitCode und die Herabstufung durch --fail-on in
// ApplyFailOnPolicy.
//
// Warum es diese Unit gibt: bis 2026-08-08 war der Exit-Code voellig
// ungetestet - ausgerechnet die Zahl, an der jede CI-Pipeline haengt.
// Das fiel auf, als sich herausstellte, dass ein Lesefehler von jedem
// beliebigen Hint verdeckt wurde und --fail-on warning daraus eine 0
// machte: gruener Build fuer einen Scan, der Teile des Baums nie
// gesehen hat.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestConsoleExitCode = class
  public
    // ---- Herabstufung mit Lesefehler: Fussboden ist 4, nicht 0 ----
    [Test] procedure FailOnWarning_HintsPlusReadError_ExitsFour;
    [Test] procedure FailOnError_WarningsPlusReadError_ExitsFour;
    [Test] procedure FailOnHint_HintsPlusReadError_KeepsOne;

    // ---- 'none' ist die ausdrueckliche Ausnahme ----
    [Test] procedure FailOnNone_HintsPlusReadError_StaysZero;
    [Test] procedure FailOnNone_RawReadError_StaysZero;

    // ---- Ohne Lesefehler bleibt alles wie bisher ----
    [Test] procedure FailOnWarning_HintsWithoutReadError_StaysZero;
    [Test] procedure FailOnError_WarningsWithoutReadError_StaysZero;

    // ---- Die Rangleiter selbst bleibt unangetastet ----
    [Test] procedure Graded_HintsPlusReadError_KeepsLadder;
    [Test] procedure FailOnWarning_ErrorsPlusReadError_StaysThree;
    [Test] procedure FailOnWarning_RawReadError_StaysFour;

    // ---- Robustheit der Policy-Auswertung ----
    [Test] procedure PolicyValue_IsTrimmedAndCaseInsensitive;
    [Test] procedure UnknownPolicyValue_FallsBackToRaw;

    // ---- Quelle des Flags: die Klassifikation ----
    [Test] procedure CountBySeverity_ReadErrorNeverCountsAsSeverity;
    [Test] procedure CalcExitCode_HintPlusReadError_IsOne;
    [Test] procedure CalcExitCode_ReadErrorOnly_IsFour;
  end;

  // ---- Stack-Wachposten (2026-09-12) --------------------------------
  // Eigene Fixture: die Klasse darueber gehoert den Exit-Codes.
  [TestFixture]
  TTestStackReserveGuard = class
  public
    [Test] procedure Pe32Plus_32MB_WirdGelesen;
    [Test] procedure Pe32_1MB_WirdGelesen;
    [Test] procedure KeinPeFile_LiefertNull;
    [Test] procedure NichtVorhandeneDatei_LiefertNull;
  end;

  // ---- Opt-in UsesCheck/SCA007 (Recall-Fix 2026-09-19) --------------
  // Eigene Fixture aus demselben Grund. Pinnt die CLI-Politik, mit der
  // SCA007 ueberhaupt laeuft: ini-Schalter ODER Profil 'strict'. Bis
  // zum Fix setzte der CLI das Request-Feld nie - der Detektor lief in
  // KEINEM CLI-Lauf (G13-Befund, Kette im Kopf von uUnusedUses).
  [TestFixture]
  TTestEffektiverUsesCheck = class
  public
    [Test] procedure IniSchalter_Greift;
    [Test] procedure ProfilStrict_Greift_AuchOhneIni;
    [Test] procedure ProfilStrict_IstCaseInsensitiv;
    [Test] procedure DefaultProfilOhneIni_BleibtAus;
  end;

  // ---- Startzeile "N rules active" (2026-11-04) ---------------------
  // Eigene Fixture: pinnt, dass die Zahl der Startzeile dem Profil folgt,
  // das die Engine faehrt. Bei leerem Profil zaehlte die Zeile AllKinds
  // (205), die Engine fuhr 'default' (197).
  [TestFixture]
  TTestAktiveRegelAnzahl = class
  public
    [Test] procedure LeeresProfil_ZaehltWieDefault;
    [Test] procedure BenanntesProfil_ZaehltSeineKinds;
  end;

  // ---- Unbekanntes Profil = Exit 99 (Nico-Entscheid 2026-11-04) -----
  // Eigene Fixture: pinnt die Pruefung, die der CLI VOR dem Scan auf das
  // effektive Profil (--profile vor [Rules] Profile) anwendet. Bis dahin
  // lief ein vertippter Name still mit allen Detektoren. Der Run selbst
  // ist hier nicht greifbar - er laedt die echte analyser.ini unter
  // %APPDATA% -, deshalb die reine Funktion ProfilPruefung.
  [TestFixture]
  TTestProfilPruefung = class
  public
    [Test] procedure UnbekanntesProfil_Exit99_MitMeldung;
    [Test] procedure UnbekanntesProfilAusIni_NenntDieIni;
    [Test] procedure BekanntesProfil_GrossKleinUndLeerraum_KeinFehler;
    [Test] procedure LeeresProfil_KeinFehler;
    [Test] procedure EigenesProfilAusProfilesJson_KeinFehler;
    // Projekt-Profile (2026-11-07): ein Profil aus <--path>\.sca\
    // profiles.json besteht die Pruefung (Exit 0 statt 99), sobald Run
    // die Wurzel gesetzt hat; die Meldung fuer einen unbekannten Namen
    // nennt dann auch die Projektdatei.
    [Test] procedure ProjektProfilImScanPfad_Exit0Statt99;
    // Die Wurzel folgt dem Scan-Ziel: --path, sonst der Ordner von
    // --project, --project-group bzw. --file.
    [Test] procedure ProjektProfilWurzel_FolgtDemScanZiel;
  end;

  // ---- Speicher-Abbruch: Hinweis auf stderr (Review-Runde 2026-11-14) ----
  // Eigene Fixture. Der Exit 99 selbst ist hier nicht greifbar (Run laedt
  // die echte analyser.ini, s. TTestProfilPruefung) - gepinnt wird die
  // Zusatzzeile, die Run beim Speicher-Abbruch schreibt: der Ausweg je
  // Bitbreite (m13). Bis dahin empfahl der 64-Bit-Build sich selbst.
  [TestFixture]
  TTestToolErrorHint = class
  public
    [Test] procedure OutOfMemory_NenntAuswegJeBitbreite;
    [Test] procedure AndereAusnahme_KeinHinweis;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  System.IOUtils,                     // TPath/TFile fuer die PE-Fixtures
  uMethodd12, uSCAConsts, uConsoleRunner,
  uRuleCatalog;                       // Erwartungswerte der Regel-Anzahl

const
  // Die Zahlen der Exit-Code-Konvention. Bewusst als Literale und nicht
  // ueber den Enum aus uConsoleRunner: der Test soll festnageln, WAS die
  // CLI nach aussen meldet, nicht nur, dass sie mit sich selbst konsistent
  // ist. Eine Umbenennung im Enum darf hier auffallen.
  EXIT_CLEAN      = 0;
  EXIT_HINTS      = 1;
  EXIT_WARNINGS   = 2;
  EXIT_ERRORS     = 3;
  EXIT_READERRORS = 4;
  EXIT_TOOLERROR  = 99;

  // Die --fail-on-Werte und die beiden Lesefehler-Zustaende als Konstanten:
  // als Literale wiederholt zaehlt sie der eigene DuplicateString-Detektor.
  POL_GRADED  = 'graded';
  POL_NONE    = 'none';
  POL_HINT    = 'hint';
  POL_WARNING = 'warning';
  POL_ERROR   = 'error';

  WITH_READ_ERROR = 1;   // Anzahl unlesbarer Dateien im Lauf
  NO_READ_ERROR   = 0;

function MakeFinding(AKind: TFindingKind; ASev: TLeakSeverity): TLeakFinding;
begin
  Result := TLeakFinding.Create;
  Result.Kind       := AKind;
  Result.Severity   := ASev;
  Result.FileName   := 'uProbe.pas';
  Result.LineNumber := '1';
end;

{ ---- Herabstufung mit Lesefehler ---- }

procedure TTestConsoleExitCode.FailOnWarning_HintsPlusReadError_ExitsFour;
// Der Kernfall: vor dem Fix lieferte genau das eine 0.
begin
  Assert.AreEqual<Integer>(EXIT_READERRORS,
    ApplyFailOnPolicy(EXIT_HINTS, POL_WARNING, WITH_READ_ERROR));
end;

procedure TTestConsoleExitCode.FailOnError_WarningsPlusReadError_ExitsFour;
// Zeigt, dass der Fussboden in ALLEN herabstufenden Zweigen greift und
// nicht nur im 'warning'-Zweig.
begin
  Assert.AreEqual<Integer>(EXIT_READERRORS,
    ApplyFailOnPolicy(EXIT_WARNINGS, POL_ERROR, WITH_READ_ERROR));
end;

procedure TTestConsoleExitCode.FailOnHint_HintsPlusReadError_KeepsOne;
// 'hint' stuft hier nichts herab - der Fussboden darf den Rang NICHT
// ueberschreiben. Regressionsschutz gegen ein zu frueh gesetztes Exit(4).
begin
  Assert.AreEqual<Integer>(EXIT_HINTS,
    ApplyFailOnPolicy(EXIT_HINTS, POL_HINT, WITH_READ_ERROR));
end;

{ ---- 'none' ---- }

procedure TTestConsoleExitCode.FailOnNone_HintsPlusReadError_StaysZero;
begin
  Assert.AreEqual<Integer>(EXIT_CLEAN,
    ApplyFailOnPolicy(EXIT_HINTS, POL_NONE, WITH_READ_ERROR));
end;

procedure TTestConsoleExitCode.FailOnNone_RawReadError_StaysZero;
begin
  Assert.AreEqual<Integer>(EXIT_CLEAN,
    ApplyFailOnPolicy(EXIT_READERRORS, POL_NONE, WITH_READ_ERROR));
end;

{ ---- Ohne Lesefehler ---- }

procedure TTestConsoleExitCode.FailOnWarning_HintsWithoutReadError_StaysZero;
begin
  Assert.AreEqual<Integer>(EXIT_CLEAN,
    ApplyFailOnPolicy(EXIT_HINTS, POL_WARNING, NO_READ_ERROR));
end;

procedure TTestConsoleExitCode.FailOnError_WarningsWithoutReadError_StaysZero;
begin
  Assert.AreEqual<Integer>(EXIT_CLEAN,
    ApplyFailOnPolicy(EXIT_WARNINGS, POL_ERROR, NO_READ_ERROR));
end;

{ ---- Rangleiter ---- }

procedure TTestConsoleExitCode.Graded_HintsPlusReadError_KeepsLadder;
// Beide Schreibweisen des Defaults.
begin
  Assert.AreEqual<Integer>(EXIT_HINTS,
    ApplyFailOnPolicy(EXIT_HINTS, POL_GRADED, WITH_READ_ERROR));
  Assert.AreEqual<Integer>(EXIT_HINTS,
    ApplyFailOnPolicy(EXIT_HINTS, '', WITH_READ_ERROR));
end;

procedure TTestConsoleExitCode.FailOnWarning_ErrorsPlusReadError_StaysThree;
// Errors schlagen Lesefehler - der Fussboden darf das nicht kippen.
begin
  Assert.AreEqual<Integer>(EXIT_ERRORS,
    ApplyFailOnPolicy(EXIT_ERRORS, POL_WARNING, WITH_READ_ERROR));
  Assert.AreEqual<Integer>(EXIT_ERRORS,
    ApplyFailOnPolicy(EXIT_ERRORS, POL_ERROR, WITH_READ_ERROR));
end;

procedure TTestConsoleExitCode.FailOnWarning_RawReadError_StaysFour;
// Der bestehende Guard darf durch den Umbau nicht toter Code werden.
begin
  Assert.AreEqual<Integer>(EXIT_READERRORS,
    ApplyFailOnPolicy(EXIT_READERRORS, POL_WARNING, WITH_READ_ERROR));
end;

{ ---- Robustheit ---- }

procedure TTestConsoleExitCode.PolicyValue_IsTrimmedAndCaseInsensitive;
// Sichert, dass der neue Pfad HINTER LowerCase(Trim(...)) haengt.
begin
  Assert.AreEqual<Integer>(EXIT_READERRORS,
    ApplyFailOnPolicy(EXIT_HINTS, '  WARNING  ', WITH_READ_ERROR));
end;

procedure TTestConsoleExitCode.UnknownPolicyValue_FallsBackToRaw;
// Ein Tippfehler im Schalter liefert weiter das Default-Verhalten und
// nicht ploetzlich eine 4.
begin
  Assert.AreEqual<Integer>(EXIT_HINTS,
    ApplyFailOnPolicy(EXIT_HINTS, 'bogus', WITH_READ_ERROR));
end;

{ ---- Klassifikation ---- }

procedure TTestConsoleExitCode.CountBySeverity_ReadErrorNeverCountsAsSeverity;
// Die Severity des Lesefehlers wird bewusst ignoriert - hier steht sie
// absichtlich auf lsError und darf trotzdem nicht in Errors landen.
var
  L : TObjectList<TLeakFinding>;
  E, W, H, R : Integer;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding(fkFileReadError, lsError));
    L.Add(MakeFinding(fkMemoryLeak, lsHint));
    TConsoleRunner.CountBySeverity(L, E, W, H, R);
    Assert.AreEqual<Integer>(0, E, 'Lesefehler darf nicht als Error zaehlen');
    Assert.AreEqual<Integer>(0, W);
    Assert.AreEqual<Integer>(1, H);
    Assert.AreEqual<Integer>(1, R);
  finally
    L.Free;
  end;
end;

procedure TTestConsoleExitCode.CalcExitCode_HintPlusReadError_IsOne;
// Die Rangleiter bleibt: Hint schlaegt Lesefehler.
var
  L : TObjectList<TLeakFinding>;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding(fkFileReadError, lsError));
    L.Add(MakeFinding(fkMemoryLeak, lsHint));
    Assert.AreEqual<Integer>(EXIT_HINTS, TConsoleRunner.CalcExitCode(L));
  finally
    L.Free;
  end;
end;

procedure TTestConsoleExitCode.CalcExitCode_ReadErrorOnly_IsFour;
var
  L : TObjectList<TLeakFinding>;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding(fkFileReadError, lsError));
    Assert.AreEqual<Integer>(EXIT_READERRORS, TConsoleRunner.CalcExitCode(L));
  finally
    L.Free;
  end;
end;

{ ---- Stack-Wachposten ----------------------------------------------- }

// Baut eine MINIMALE Datei mit PE-Kopf: Offset $3C zeigt auf den
// PE-Header, dort steht ab +$18 der Optional-Header mit Magic und ab
// +$18+$48 die Stack-Reserve. Genau die drei Felder, die
// PeStackReserveMB liest - mehr braucht der Vertrag nicht.
// AMagic ist der Optional-Header-Magic: $10B = PE32, $20B = PE32+.
// Bewusst das Magic statt eines Boolean-Schalters - ein 'APlus: Boolean'
// waere genau der Verzweigungs-Parameter, den SCA146 zu Recht ruegt.
function MachePeDatei(AMagic: Word; AReserve: UInt64): string;
const
  PE_OFS = $80;
  MAGIC_PE32PLUS = $20B;
var
  Buf : TBytes;
  i   : Integer;
begin
  Result := TPath.Combine(TPath.GetTempPath,
    'sca_pe_' + TGuid.NewGuid.ToString.Replace('{', '').Replace('}', '')
      .Replace('-', '') + '.bin');
  SetLength(Buf, PE_OFS + $18 + $48 + 8);
  for i := 0 to High(Buf) do Buf[i] := 0;
  // e_lfanew
  PCardinal(@Buf[$3C])^ := PE_OFS;
  PWord(@Buf[PE_OFS + $18])^ := AMagic;
  if AMagic = MAGIC_PE32PLUS then
    PUInt64(@Buf[PE_OFS + $18 + $48])^ := AReserve
  else
    PCardinal(@Buf[PE_OFS + $18 + $48])^ := Cardinal(AReserve);
  TFile.WriteAllBytes(Result, Buf);
end;

procedure TTestStackReserveGuard.Pe32Plus_32MB_WirdGelesen;
// 64-Bit-Form (PE32+, Magic $20B) - die Reserve steht als UInt64.
var P : string;
begin
  P := MachePeDatei($20B, 32 * 1024 * 1024);
  try
    Assert.AreEqual<Integer>(32, PeStackReserveMB(P),
      'PE32+ mit 32 MB muss als 32 gelesen werden');
  finally
    if TFile.Exists(P) then TFile.Delete(P);
  end;
end;

procedure TTestStackReserveGuard.Pe32_1MB_WirdGelesen;
// 32-Bit-Form (Magic $10B) - die Reserve steht als Cardinal. 1 MB ist
// der Build-Default, also genau der Wert, vor dem der Wachposten warnt.
var P : string;
begin
  P := MachePeDatei($10B, 1024 * 1024);
  try
    Assert.AreEqual<Integer>(1, PeStackReserveMB(P),
      'PE32 mit 1 MB muss als 1 gelesen werden');
  finally
    if TFile.Exists(P) then TFile.Delete(P);
  end;
end;

procedure TTestStackReserveGuard.KeinPeFile_LiefertNull;
// Eine Textdatei ist kein PE. Der Wachposten darf davon nicht
// ausgeloest werden und erst recht nicht scheitern - 0 heisst
// 'keine Aussage', und der Aufrufer schweigt dann.
var P : string;
begin
  P := TPath.Combine(TPath.GetTempPath,
    'sca_nope_' + TGuid.NewGuid.ToString.Replace('{', '').Replace('}', '')
      .Replace('-', '') + '.txt');
  TFile.WriteAllText(P, 'kein PE, nur Text');
  try
    Assert.AreEqual<Integer>(0, PeStackReserveMB(P),
      'Nicht-PE liefert 0 (keine Aussage), kein Fehler');
  finally
    if TFile.Exists(P) then TFile.Delete(P);
  end;
end;

procedure TTestStackReserveGuard.NichtVorhandeneDatei_LiefertNull;
// Der Diagnose-Pfad darf einen Analyse-Lauf nie kosten.
begin
  Assert.AreEqual<Integer>(0,
    PeStackReserveMB(TPath.Combine(TPath.GetTempPath, 'gibt_es_nicht_12345.exe')),
    'fehlende Datei liefert 0 statt einer Exception');
end;

{ ---- TTestEffektiverUsesCheck ---- }

procedure TTestEffektiverUsesCheck.IniSchalter_Greift;
// [Detectors] UsesCheck=1 muss den Detektor auch ausserhalb von strict
// einschalten - die Doku verspricht den Schalter an vier Stellen, und
// genau er war im CLI wirkungslos (27 repo-weise Laeufe, alle 0).
begin
  Assert.IsTrue(EffektiverUsesCheck(True, 'default'));
end;

procedure TTestEffektiverUsesCheck.ProfilStrict_Greift_AuchOhneIni;
// uRepoSettings definiert strict als "alle + opt-in Detektoren
// (UsesCheck)" - der Referenzlauf faehrt genau dieses Profil und bekam
// die Regel trotzdem nie.
begin
  Assert.IsTrue(EffektiverUsesCheck(False, 'strict'));
end;

procedure TTestEffektiverUsesCheck.ProfilStrict_IstCaseInsensitiv;
// Profilnamen kommen aus ini UND --profile; die uebrige Profil-
// Aufloesung (TRuleCatalog) ist case-insensitiv - diese Weiche muss
// es genauso sein, sonst haengt der Detektor an der Schreibweise.
begin
  Assert.IsTrue(EffektiverUsesCheck(False, 'STRICT'));
end;

procedure TTestEffektiverUsesCheck.DefaultProfilOhneIni_BleibtAus;
// Gegenprobe: der opt-in-Charakter bleibt. Default-Profil ohne
// ini-Schalter laeuft weiterhin OHNE den teuren Detektor - alles
// andere waere ein stiller Recall-Schub in jedem CI-Lauf.
begin
  Assert.IsFalse(EffektiverUsesCheck(False, 'default'));
  Assert.IsFalse(EffektiverUsesCheck(False, ''));
end;

{ ---- TTestAktiveRegelAnzahl ---- }

function KindsIn(const AKinds: TFindingKinds): Integer;
// Unabhaengige Zaehlung fuer die Erwartung - bewusst nicht ueber
// AktiveRegelAnzahl, sonst prueft der Test nur sich selbst.
begin
  Result := 0;
  for var K := Low(TFindingKind) to High(TFindingKind) do
    if K in AKinds then Inc(Result);
end;

function AnzahlAllerKinds: Integer;
// Die Zahl, die KindsIn(AllKinds) liefern wuerde. TRuleCatalog.AllKinds
// ist strict private (E2361 von aussen) - und AllKinds nimmt ohnehin
// jeden Wert von Low bis High auf, also genau diese Spanne.
begin
  Result := Ord(High(TFindingKind)) - Ord(Low(TFindingKind)) + 1;
end;

procedure TTestAktiveRegelAnzahl.LeeresProfil_ZaehltWieDefault;
// Der Befund: ohne Profil in INI und Kommandozeile faehrt die Engine
// 'default' (ApplyDetectorThresholds), die Startzeile zaehlte aber
// GetProfile('') = AllKinds. Vor dem Fix lieferte die Zaehlung hier
// alle Kinds - beide Asserts waren rot.
var
  AnzahlDefault : Integer;
begin
  AnzahlDefault := KindsIn(TRuleCatalog.GetProfile('default'));
  Assert.AreEqual<Integer>(AnzahlDefault, AktiveRegelAnzahl(''),
    'leeres Profil zaehlt wie default');
  Assert.IsTrue(AktiveRegelAnzahl('') < AnzahlAllerKinds,
    'default laesst die Konventions-Regeln aus - weniger als alle Kinds');
end;

procedure TTestAktiveRegelAnzahl.BenanntesProfil_ZaehltSeineKinds;
// Gegenprobe: ein benanntes Profil zaehlt unveraendert seine Menge,
// ein unbekannter Name wie in der Engine alle Kinds.
begin
  Assert.AreEqual<Integer>(KindsIn(TRuleCatalog.GetProfile('security')),
    AktiveRegelAnzahl('security'), 'security zaehlt seine Kinds');
  Assert.AreEqual<Integer>(AnzahlAllerKinds,
    AktiveRegelAnzahl('strict'), 'strict = alle Kinds');
  Assert.AreEqual<Integer>(AnzahlAllerKinds,
    AktiveRegelAnzahl('gibt-es-nicht'), 'unbekannt faellt auf alle zurueck');
end;

{ ---- TTestProfilPruefung ---- }

const
  QUELLE_SCHALTER = '--profile';
  QUELLE_INI      = 'analyser.ini';

procedure TTestProfilPruefung.UnbekanntesProfil_Exit99_MitMeldung;
// Der Befund: '--profile secuirty' fuhr bis 2026-11-04 alle Detektoren
// und meldete Exit 0..4 wie ein gewollter Lauf. Ohne die Pruefung gibt es
// ProfilPruefung nicht (der Test uebersetzt nicht), und jede Fassung, die
// den Namen durchliesse, scheitert am Exit-Code. Die Meldung muss den
// Namen, die Quelle und die richtige Schreibweise zeigen - sonst ist der
// Abbruch fuer den CI-Autor ein Raetsel.
var
  Meldung : string;
begin
  Assert.AreEqual<Integer>(EXIT_TOOLERROR,
    ProfilPruefung('secuirty', QUELLE_SCHALTER, Meldung),
    'unbekanntes Profil ist ein Tool-Fehler');
  Assert.Contains(Meldung, '"secuirty"', 'Meldung nennt den Namen');
  Assert.Contains(Meldung, QUELLE_SCHALTER, 'Meldung nennt die Quelle');
  Assert.Contains(Meldung, 'security',
    'Meldung nennt die bekannten Profile, also auch die richtige Schreibweise');
end;

procedure TTestProfilPruefung.UnbekanntesProfilAusIni_NenntDieIni;
// Derselbe Abbruch fuer einen Tippfehler in [Rules] Profile: der
// gefaehrlichere Fall, weil er in keinem Pipeline-Skript steht.
var
  Meldung : string;
begin
  Assert.AreEqual<Integer>(EXIT_TOOLERROR,
    ProfilPruefung('bugsonly', QUELLE_INI, Meldung));
  Assert.Contains(Meldung, QUELLE_INI, 'Meldung nennt die analyser.ini');
end;

procedure TTestProfilPruefung.BekanntesProfil_GrossKleinUndLeerraum_KeinFehler;
// Gegenprobe: was die Engine aufloest, darf der CLI nicht abweisen.
// GetProfile vergleicht case-insensitiv und trimmt; die Pruefung muss
// dieselbe Menge sehen, sonst bricht ein Lauf ab, der vorher richtig lief.
var
  Meldung : string;
begin
  Assert.AreEqual<Integer>(EXIT_CLEAN,
    ProfilPruefung('default', QUELLE_SCHALTER, Meldung), 'default');
  Assert.AreEqual('', Meldung, 'keine Meldung fuer ein bekanntes Profil');
  Assert.AreEqual<Integer>(EXIT_CLEAN,
    ProfilPruefung('STRICT', QUELLE_SCHALTER, Meldung), 'Grossschreibung');
  Assert.AreEqual<Integer>(EXIT_CLEAN,
    ProfilPruefung(' Bugs-Only ', QUELLE_INI, Meldung),
    'aeusserer Leerraum und gemischte Schreibweise');
end;

procedure TTestProfilPruefung.LeeresProfil_KeinFehler;
// Weder --profile noch [Rules] Profile: das ist der Normalfall und
// heisst 'default' (TRepoSettings.EffectiveProfileName), kein Tippfehler.
var
  Meldung : string;
begin
  Assert.AreEqual<Integer>(EXIT_CLEAN,
    ProfilPruefung('', QUELLE_INI, Meldung));
  Assert.AreEqual('', Meldung);
end;

procedure TTestProfilPruefung.EigenesProfilAusProfilesJson_KeinFehler;
// Ein eigenes Profil aus dem Profil-Fenster liegt in profiles.json und
// laeuft mit --profile <name> (Katalog: EnsureLoaded -> LoadUserProfiles).
// Es darf NIE als unbekannt gelten. Die Datei kommt aus TEMP ueber den
// Test-Hook UserProfilesPath - die echte profiles.json unter %APPDATA%
// wird nicht geschrieben; der Reload am Ende stellt den Katalog so her,
// wie ihn jeder andere Test vorfindet.
var
  AltPfad : string;
  TmpPfad : string;
  Meldung : string;
begin
  AltPfad := TRuleCatalog.UserProfilesPath;
  TmpPfad := TPath.Combine(TPath.GetTempPath, 'sca_test_profiles_cli_' +
    TGuid.NewGuid.ToString.Replace('{', '').Replace('}', '') + '.json');
  try
    TFile.WriteAllText(TmpPfad,
      '{"profiles":{"team-probe":["MemoryLeak","EmptyExcept"]}}');
    TRuleCatalog.UserProfilesPath := TmpPfad;
    TRuleCatalog.Reload;
    Assert.AreEqual<Integer>(EXIT_CLEAN,
      ProfilPruefung('team-probe', QUELLE_SCHALTER, Meldung),
      'eigenes Profil ist bekannt: ' + Meldung);
    Assert.AreEqual<Integer>(EXIT_CLEAN,
      ProfilPruefung('Team-Probe', QUELLE_INI, Meldung),
      'auch in anderer Schreibweise, wie im Katalog');
    // Gegenprobe im selben Katalogstand: die Pruefung ist nicht einfach
    // abgeschaltet, ein Name daneben faellt weiter durch.
    Assert.AreEqual<Integer>(EXIT_TOOLERROR,
      ProfilPruefung('team-probe2', QUELLE_SCHALTER, Meldung));
    // Nur die Listenzeile pruefen und mit Trennern einrahmen: der
    // abgewiesene Name 'team-probe2' steht selbst in der Meldung und
    // enthaelt 'team-probe' - ein blosses Contains waere immer gruen.
    var Liste := '';
    for var Zeile in Meldung.Split([sLineBreak]) do
      if Zeile.StartsWith('Known profiles: ') then
        Liste := ', ' + Zeile.Substring(Length('Known profiles: ')) + ',';
    Assert.Contains(Liste, ', team-probe,',
      'die Liste der bekannten Profile fuehrt das eigene Profil');
  finally
    TRuleCatalog.UserProfilesPath := AltPfad;
    TRuleCatalog.Reload;
    if TFile.Exists(TmpPfad) then TFile.Delete(TmpPfad);
  end;
end;

procedure TTestProfilPruefung.ProjektProfilImScanPfad_Exit0Statt99;
// Der Anlass (Showcase-Demo): ein Projekt bringt sein Profil in
// .sca\profiles.json mit, '--path <Projekt> --profile <name>' muss auf
// jedem Rechner laufen - auch auf einem Build-Dienst ohne eigene
// profiles.json. Vor der Aenderung endete genau das mit Exit 99. Der
// Weg ist der von Run: ParseArgs -> ProjektProfilWurzel ->
// UseProjectRoot -> ProfilPruefung. LUECKE: der Test spielt diese
// Reihenfolge selbst nach - dass Run den UseProjectRoot-Aufruf VOR der
// Pruefung macht und die Hinweise auf stderr schreibt, pinnt er nicht;
// Run laedt die echte analyser.ini unter %APPDATA% (s. Fixture-Kopf).
// Pruefung von Hand: ein CLI-Lauf mit --path auf ein Projekt mit
// .sca\profiles.json.
var
  Wurzel  : string;
  Args    : TCliArgs;
  Meldung : string;
begin
  Wurzel := TPath.Combine(TPath.GetTempPath, 'sca_test_cli_projroot_' +
    TGuid.NewGuid.ToString.Replace('{', '').Replace('}', ''));
  try
    TDirectory.CreateDirectory(TPath.Combine(Wurzel, '.sca'));
    TFile.WriteAllText(TPath.Combine(TPath.Combine(Wurzel, '.sca'),
      'profiles.json'),
      '{"version":1,"profiles":{"cli-projekt-probe":["MemoryLeak"]}}');
    TRuleCatalog.UseProjectRoot('');
    Assert.AreEqual<Integer>(EXIT_TOOLERROR,
      ProfilPruefung('cli-projekt-probe', QUELLE_SCHALTER, Meldung),
      'Vorbedingung: ohne Wurzel ist das Profil unbekannt');

    Args := TConsoleRunner.ParseArgs(
      ['--path', Wurzel, '--profile', 'cli-projekt-probe']);
    TRuleCatalog.UseProjectRoot(ProjektProfilWurzel(Args));
    Assert.AreEqual<Integer>(EXIT_CLEAN,
      ProfilPruefung(Args.Profile, QUELLE_SCHALTER, Meldung),
      'Projekt-Profil ist bekannt: ' + Meldung);

    // Gegenprobe im selben Stand: ein Name daneben faellt weiter durch,
    // und die Meldung sagt, wo Projekt-Profile gesucht werden.
    Assert.AreEqual<Integer>(EXIT_TOOLERROR,
      ProfilPruefung('cli-projekt-probe2', QUELLE_SCHALTER, Meldung));
    Assert.IsTrue(Pos('Project profiles are read from: ' +
      TRuleCatalog.ProjectProfilesFileFor(Wurzel), Meldung) > 0,
      'die Meldung nennt die Projektdatei: ' + Meldung);
  finally
    TRuleCatalog.UseProjectRoot('');
    if TDirectory.Exists(Wurzel) then TDirectory.Delete(Wurzel, True);
  end;
end;

procedure TTestProfilPruefung.ProjektProfilWurzel_FolgtDemScanZiel;
// Die Projektwurzel je Scan-Ziel. '=' statt Assert.AreEqual: die
// String-Fassung vergleicht ohne Gross/klein, hier zaehlt der Pfad, wie
// ihn der Aufrufer schrieb.
const
  ORDNER = 'C:\ProbeRepo\Projekt';
begin
  Assert.IsTrue(ProjektProfilWurzel(TConsoleRunner.ParseArgs(
    ['--path', ORDNER])) = ORDNER, '--path ist die Wurzel');
  Assert.IsTrue(ProjektProfilWurzel(TConsoleRunner.ParseArgs(
    ['--project', ORDNER + '\Demo.dproj'])) = ORDNER,
    '--project: der Ordner der .dproj');
  Assert.IsTrue(ProjektProfilWurzel(TConsoleRunner.ParseArgs(
    ['--project-group', ORDNER + '\Demo.groupproj'])) = ORDNER,
    '--project-group: der Ordner der .groupproj');
  Assert.IsTrue(ProjektProfilWurzel(TConsoleRunner.ParseArgs(
    ['--file', ORDNER + '\uDemo.pas'])) = ORDNER,
    '--file: der Ordner der Datei');
end;

{ TTestToolErrorHint }

procedure TTestToolErrorHint.OutOfMemory_NenntAuswegJeBitbreite;
// Mit der Klasse, nicht mit einer Instanz: EOutOfMemory-Objekte gibt die
// RTL nie frei (EHeapException.AllowFree) - ein Create hier waere ein Leck.
var
  Hint : string;
begin
  Hint := TConsoleRunner.ToolErrorHint(EOutOfMemory);
  Assert.IsTrue(Pos('Narrow --path', Hint) > 0,
    'der Ausweg Eingrenzen steht in jeder Bitbreite da: ' + Hint);
  Assert.IsTrue(Pos('no report was written', Hint) > 0,
    'die Zeile sagt, dass kein Bericht entstand: ' + Hint);
  {$IFDEF CPU32BITS}
  Assert.IsTrue(Pos('64-bit build', Hint) > 0,
    '32 Bit: der Hinweis nennt den 64-Bit-Build: ' + Hint);
  {$ELSE}
  Assert.IsTrue(Pos('64-bit', Hint) = 0,
    '64 Bit: kein Verweis auf den 64-Bit-Build (das ist dieser): ' + Hint);
  {$ENDIF}
end;

procedure TTestToolErrorHint.AndereAusnahme_KeinHinweis;
begin
  Assert.AreEqual('', TConsoleRunner.ToolErrorHint(EConvertError),
    'eine gewoehnliche Ausnahme bekommt keine Zusatzzeile');
  Assert.AreEqual('', TConsoleRunner.ToolErrorHint(nil), 'nil: keine Zeile');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestStackReserveGuard);
  TDUnitX.RegisterTestFixture(TTestConsoleExitCode);
  TDUnitX.RegisterTestFixture(TTestEffektiverUsesCheck);
  TDUnitX.RegisterTestFixture(TTestAktiveRegelAnzahl);
  TDUnitX.RegisterTestFixture(TTestProfilPruefung);
  TDUnitX.RegisterTestFixture(TTestToolErrorHint);

end.
