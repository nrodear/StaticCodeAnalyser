unit uTestStaticFiles;

// Tests fuer die Dateisammlung (TStaticFiles) - die ERSTEN ueberhaupt:
// bis zum Lazarus-Paket A2 (2026-09-16) hatte uStaticFiles null
// Testabdeckung, obwohl JEDER Verzeichnis-Scan durch ScanRec laeuft.
//
// Anlass ist der Dialekt-Schalter: dlFpc sammelt zusaetzlich *.pp ein
// (die klassische Free-Pascal-Unit-Endung; im Lazarus-Baum 676 Dateien
// mit ~399k Code-Zeilen). Der Delphi-Default MUSS dabei byte-identisch
// bleiben - die Klammer-Tests hier sind der Teil dieses Beweises, der
// ohne Bau und Referenzlauf fuehrbar ist.
//
// HARNESS-HINWEIS: bewusst DIREKTE Aufrufe von TryGetAllPasFiles auf
// ein GUID-Temp-Verzeichnis (Muster uTestNotIncludedInProject). Der
// Pipeline-Weg (ssRecursive) ist im residenten TestInsight-Prozess
// verboten (IDE-Hang 2026-06-26, s. uTestEngineApi-Unit-Kopf); die
// Sammel-Logik selbst braucht ihn nicht - sie ist hier vollstaendig
// ueber den View-State TStaticFiles.ScanDialect steuerbar.
//
// GLOBALER STATE: jeder Test, der ScanDialect setzt, restauriert ihn
// im finally. Der residente Testprozess teilt den State mit allen
// anderen Fixtures - ein liegengelassener dlFpc wuerde fremde Tests
// unzuverlaessig machen (dokumentierte Projektlehre).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestStaticFiles = class
  private
    FDir : string;
    function W(const ARel: string): string;
    function Sammle: TArray<string>;
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;

    // Die Klammer: der Default sammelt exakt wie vor dem Paket.
    [Test] procedure DelphiDefault_SammeltNurPas;
    // Die Wirkung: dlFpc nimmt *.pp dazu - rekursiv.
    [Test] procedure FpcDialekt_SammeltAuchPp;
    // Die Grenzen bleiben: EXCLUDED_DIRS gilt auch fuer .pp.
    [Test] procedure FpcDialekt_ExcludedDirsGeltenAuchFuerPp;
    // A3: .lpr ist drin, .inc bleibt draussen (Produktentscheid),
    // und der Delphi-Default bleibt bei .pas allein.
    [Test] procedure FpcDialekt_SammeltAuchLpr;
    [Test] procedure FpcDialekt_IncBleibtDraussen;
    [Test] procedure DelphiDefault_LprUndPpBleibenDraussen;
    // A4: Formdatei-Paarung (PairedFormFile/PairedUnitFile/IsFormFileName)
    [Test] procedure PairedFormFile_DelphiDefault_IgnoriertLfm;
    [Test] procedure PairedFormFile_Fpc_FaelltAufLfmZurueck;
    [Test] procedure PairedFormFile_DfmHatVorrang;
    [Test] procedure PairedUnitFile_Fpc_FindetPpSchwester;
    [Test] procedure IsFormFileName_FolgtDemDialekt;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  uSCAConsts, uStaticFiles;

procedure TTestStaticFiles.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath,
    'sca_dialekt_' + TGUID.NewGuid.ToString.Trim(['{', '}']));
  TDirectory.CreateDirectory(FDir);
end;

procedure TTestStaticFiles.TearDown;
begin
  try
    if (FDir <> '') and TDirectory.Exists(FDir) then
      TDirectory.Delete(FDir, True);
  except
  end;
end;

function TTestStaticFiles.W(const ARel: string): string;
begin
  Result := TPath.Combine(FDir, ARel);
  TDirectory.CreateDirectory(ExtractFilePath(Result));
  TFile.WriteAllText(Result, 'unit x; interface implementation end.');
end;

function TTestStaticFiles.Sammle: TArray<string>;
// Sammelt FDir ueber den ECHTEN Produktionsweg (TryGetAllPasFiles ->
// ScanRec) und liefert die RELATIVEN Namen sortiert - so vergleichen
// die Tests Mengen statt Pfad-Praefixe.
var
  Err  : string;
  L    : TStringList;
  i    : Integer;
begin
  L := TStaticFiles.TryGetAllPasFiles(FDir, Err);
  try
    Assert.IsNotNull(L, 'Sammlung fehlgeschlagen: ' + Err);
    for i := 0 to L.Count - 1 do
      L[i] := StringReplace(
        Copy(L[i], Length(IncludeTrailingPathDelimiter(FDir)) + 1, MaxInt),
        '\', '/', [rfReplaceAll]);
    L.Sort;
    Result := L.ToStringArray;
  finally
    L.Free;
  end;
end;

procedure TTestStaticFiles.DelphiDefault_SammeltNurPas;
// DIE KLAMMER. Ohne sie koennte dlFpc versehentlich Default werden
// oder die Umstellung der Maskenlogik den Bestand erweitern - beides
// bewegte den Referenzlauf 752.457. Der Test laesst den State bewusst
// UNANGETASTET: er prueft das Verhalten, das jeder Bestandsaufrufer
// bekommt.
var
  Namen : TArray<string>;
begin
  W('a.pas');
  W('b.pp');
  W('sub\c.pas');
  W('sub\d.pp');
  Namen := Sammle;
  Assert.AreEqual<Integer>(2, Length(Namen),
    'Default sammelt NUR .pas - .pp ist Lazarus-Opt-in');
  Assert.AreEqual<string>('a.pas', Namen[0]);
  Assert.AreEqual<string>('sub/c.pas', Namen[1]);
end;

procedure TTestStaticFiles.FpcDialekt_SammeltAuchPp;
// Die Kernwirkung des Pakets. Vor dem Fix gab es weder das Feld noch
// den State - diese Unit kompilierte nicht; nach dem Fix belegt die
// Klammer oben die Gegenrichtung.
var
  Namen : TArray<string>;
  Alt   : TSourceDialect;
begin
  W('a.pas');
  W('b.pp');
  W('sub\d.pp');
  Alt := TStaticFiles.ScanDialect;
  try
    TStaticFiles.ScanDialect := dlFpc;
    Namen := Sammle;
  finally
    TStaticFiles.ScanDialect := Alt;
  end;
  Assert.AreEqual<Integer>(3, Length(Namen),
    'dlFpc sammelt .pas UND .pp, auch rekursiv');
  Assert.AreEqual<string>('a.pas', Namen[0]);
  Assert.AreEqual<string>('b.pp', Namen[1]);
  Assert.AreEqual<string>('sub/d.pp', Namen[2]);
end;

procedure TTestStaticFiles.FpcDialekt_ExcludedDirsGeltenAuchFuerPp;
// Die Ausschlussliste (node_modules, .git, __history, ...) haengt am
// Verzeichnis-Walk, nicht an der Endung - eine .pp in node_modules
// bleibt auch bei dlFpc draussen. Wer die Maske je umbaut, darf die
// Reihenfolge Walk-vor-Maske nicht kippen.
var
  Namen : TArray<string>;
  Alt   : TSourceDialect;
begin
  W('a.pp');
  W('node_modules\b.pp');
  Alt := TStaticFiles.ScanDialect;
  try
    TStaticFiles.ScanDialect := dlFpc;
    Namen := Sammle;
  finally
    TStaticFiles.ScanDialect := Alt;
  end;
  Assert.AreEqual<Integer>(1, Length(Namen),
    'node_modules bleibt auch fuer .pp ausgeschlossen');
  Assert.AreEqual<string>('a.pp', Namen[0]);
end;

procedure TTestStaticFiles.FpcDialekt_SammeltAuchLpr;
// Paket A3: .lpr (Lazarus-Hauptprogramme) kommt in die dlFpc-Maske -
// die Endungs-Gates stromabwaerts (Encoding, Indizes, VCS, Fixture-
// Masken) sind im selben Paket nachgezogen. Dieser Test war bis A3 der
// Scope-Pin '.lpr bleibt draussen' und ist BEWUSST umgestellt, wie
// sein eigener Kommentar es verlangte.
var
  Namen : TArray<string>;
  Alt   : TSourceDialect;
begin
  W('a.pp');
  W('haupt.lpr');
  Alt := TStaticFiles.ScanDialect;
  try
    TStaticFiles.ScanDialect := dlFpc;
    Namen := Sammle;
  finally
    TStaticFiles.ScanDialect := Alt;
  end;
  Assert.AreEqual<Integer>(2, Length(Namen),
    'dlFpc sammelt seit A3 auch .lpr');
  Assert.AreEqual<string>('a.pp', Namen[0]);
  Assert.AreEqual<string>('haupt.lpr', Namen[1]);
end;

procedure TTestStaticFiles.FpcDialekt_IncBleibtDraussen;
// Scope-Pin fuer den PRODUKTENTSCHEID: .inc wird KEIN Scanziel. Keine
// der 666 .inc im Lazarus-Baum ist eine Unit; 89,4 % sind per
// {%MainUnit} deklarierte Fragmente ihrer Wirts-Unit - Fragment-
// Parsing ohne Kontext erfaende Funde. Wer den Entscheid kippt (das
// kann nur Nico), stellt diesen Test bewusst um.
var
  Namen : TArray<string>;
  Alt   : TSourceDialect;
begin
  W('a.pp');
  W('fragment.inc');
  Alt := TStaticFiles.ScanDialect;
  try
    TStaticFiles.ScanDialect := dlFpc;
    Namen := Sammle;
  finally
    TStaticFiles.ScanDialect := Alt;
  end;
  Assert.AreEqual<Integer>(1, Length(Namen),
    '.inc ist Include-Traeger, kein Scanziel (Produktentscheid A3)');
  Assert.AreEqual<string>('a.pp', Namen[0]);
end;

procedure TTestStaticFiles.DelphiDefault_LprUndPpBleibenDraussen;
// DIE KLAMMER der A3-Erweiterung, Delphi-Seite: der Default sammelt
// weiterhin NUR .pas - der Delphi-Korpus enthaelt 145 .lpr und 9 .pp,
// jede stille Aufnahme bewegte den Referenzlauf.
var
  Namen : TArray<string>;
begin
  W('a.pas');
  W('b.pp');
  W('haupt.lpr');
  Namen := Sammle;
  Assert.AreEqual<Integer>(1, Length(Namen),
    'dlDelphi sammelt auch nach A3 nur .pas');
  Assert.AreEqual<string>('a.pas', Namen[0]);
end;

procedure TTestStaticFiles.PairedFormFile_DelphiDefault_IgnoriertLfm;
// DIE KLAMMER der A4-Paarung: der DELPHI-Referenzkorpus enthaelt 234
// .lfm neben einer .pas ohne .dfm - wuerde der Default sie paaren,
// bewegte sich die Referenz 752.457. dlDelphi darf NUR .dfm sehen.
begin
  W('form.pas');
  W('form.lfm');
  Assert.AreEqual<string>('', TStaticFiles.PairedFormFile(
    TPath.Combine(FDir, 'form.pas')),
    'dlDelphi paart keine .lfm - sonst bewegt sich der Referenzlauf');
end;

procedure TTestStaticFiles.PairedFormFile_Fpc_FaelltAufLfmZurueck;
var
  Alt : TSourceDialect;
begin
  W('form.pas');
  W('form.lfm');
  Alt := TStaticFiles.ScanDialect;
  try
    TStaticFiles.ScanDialect := dlFpc;
    Assert.IsTrue(TStaticFiles.PairedFormFile(
      TPath.Combine(FDir, 'form.pas')).EndsWith('form.lfm'),
      'dlFpc findet die .lfm, wenn keine .dfm existiert');
  finally
    TStaticFiles.ScanDialect := Alt;
  end;
end;

procedure TTestStaticFiles.PairedFormFile_DfmHatVorrang;
// Wo beide liegen (im Delphi-Korpus genau 1 Fall), gewinnt die .dfm -
// auch bei dlFpc. Ohne diesen Pin koennte eine Umsortierung der
// Kandidaten still die Formquelle wechseln.
var
  Alt : TSourceDialect;
begin
  W('form.pas');
  W('form.dfm');
  W('form.lfm');
  Alt := TStaticFiles.ScanDialect;
  try
    TStaticFiles.ScanDialect := dlFpc;
    Assert.IsTrue(TStaticFiles.PairedFormFile(
      TPath.Combine(FDir, 'form.pas')).EndsWith('form.dfm'),
      '.dfm hat Vorrang vor .lfm, auch bei dlFpc');
  finally
    TStaticFiles.ScanDialect := Alt;
  end;
end;

procedure TTestStaticFiles.PairedUnitFile_Fpc_FindetPpSchwester;
// 149 der 1.010 Lazarus-.lfm liegen neben einer .pp ohne .pas - die
// Rueckpaarung (Suppression-Host, Caption-Regime-Gate) muss sie
// finden. Bei dlDelphi bleibt dieselbe Lage leer: die Klammer haengt
// im selben Test, damit beide Richtungen an EINEM Dateibild haengen.
var
  Alt : TSourceDialect;
  Lfm : string;
begin
  W('form.pp');
  W('form.lfm');
  Lfm := TPath.Combine(FDir, 'form.lfm');
  Assert.AreEqual<string>('', TStaticFiles.PairedUnitFile(Lfm),
    'dlDelphi kennt keine .pp-Schwester');
  Alt := TStaticFiles.ScanDialect;
  try
    TStaticFiles.ScanDialect := dlFpc;
    Assert.IsTrue(TStaticFiles.PairedUnitFile(Lfm).EndsWith('form.pp'),
      'dlFpc findet die .pp-Schwester der .lfm');
  finally
    TStaticFiles.ScanDialect := Alt;
  end;
end;

procedure TTestStaticFiles.IsFormFileName_FolgtDemDialekt;
var
  Alt : TSourceDialect;
begin
  Assert.IsTrue(TStaticFiles.IsFormFileName('u.dfm'), '.dfm immer');
  Assert.IsFalse(TStaticFiles.IsFormFileName('u.lfm'),
    '.lfm ist bei dlDelphi KEINE Formdatei (Suppression-Umleitung!)');
  Alt := TStaticFiles.ScanDialect;
  try
    TStaticFiles.ScanDialect := dlFpc;
    Assert.IsTrue(TStaticFiles.IsFormFileName('u.lfm'), '.lfm bei dlFpc');
    Assert.IsFalse(TStaticFiles.IsFormFileName('u.pas'),
      'eine Unit ist nie eine Formdatei');
  finally
    TStaticFiles.ScanDialect := Alt;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestStaticFiles);

end.
