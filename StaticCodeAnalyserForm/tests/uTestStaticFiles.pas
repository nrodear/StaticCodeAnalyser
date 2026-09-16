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
    // Die Grenzen bleiben: EXCLUDED_DIRS gilt auch fuer .pp,
    // und andere Endungen (.lpr!) bleiben draussen - die kommen
    // erst mit Paket A3.
    [Test] procedure FpcDialekt_ExcludedDirsGeltenAuchFuerPp;
    [Test] procedure FpcDialekt_LprBleibtDraussen;
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

procedure TTestStaticFiles.FpcDialekt_LprBleibtDraussen;
// Scope-Pin fuer Paket A3: .lpr (Lazarus-Hauptprogramme) kommt BEWUSST
// noch nicht mit - erst wenn die Endungs-Gates stromabwaerts
// (Encoding-Familie, Indizes, VCS-Filter, Fixture-Masken) nachgezogen
// sind. Faellt dieser Test rot, hat jemand A3 begonnen: dann gehoert
// er bewusst umgestellt, nicht geloescht.
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
  Assert.AreEqual<Integer>(1, Length(Namen),
    '.lpr ist Paket A3, nicht A2 - heute nur .pas und .pp');
  Assert.AreEqual<string>('a.pp', Namen[0]);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestStaticFiles);

end.
