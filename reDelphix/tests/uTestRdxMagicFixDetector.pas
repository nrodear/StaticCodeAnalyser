unit uTestRdxMagicFixDetector;

// Quick-Fix SCA014 MagicNumber "Lokale Konstante einfuehren" (uRdxMagicFixes,
// Charge Q14) gegen den ECHTEN Detektor (nur Delphi, reDelphix.Test):
// Parser, uMagicNumbers, TSourcePlaces und TRdxFixTable.FixFor - derselbe
// Einstieg wie im Anbieter. Je Fall meldet der Detektor, die Hilfe plant aus
// dem Fund, die Ersetzung wird angewandt - und derselbe Detektor meldet
// danach nichts mehr: die eingefuegte Inline-Konstante ist eine
// Deklaration, kein if (uMagicNumbers sieht nur Bedingungen). Dazu das
// Katalog-Beispiel (aus 'bad' wird 'good' bis auf den Namen), Menuetext,
// Hinweis und Kennzeichnung, und die Sperren, die erst die Tabelle
// beitraegt (MagicCheck: Lazarus-Projekt neben der Unit, Include mit
// FPC-Weiche, Netzlaufwerk - auch lang geschrieben, Gegenpruefung
// V-B2S-3).
//
// Ohne Delphi gegengeprueft (Charge Q14): dieselben Quellen mit der CLI-Exe
// gescannt und ueber den FPC-Planer (Korpus-Harness) behoben.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxMagicFixDetector = class
  public
    [Test] procedure Sca014_CatalogExample;
    [Test] procedure Sca014_AlcinoeRoundTrip;
    [Test] procedure Sca014_TwoFindings_OneAfterTheOther;
    [Test] procedure Sca014_Branch_RoundTrip;
    [Test] procedure Sca014_Outcome_CaptionAndHint;
    [Test] procedure Sca014_Ambiguous_NoHelp;
    // Review R6-05 (Nachbesserung FF): Zifferntrenner, ein Fehlalarm.
    [Test] procedure Sca014_DigitSeparator_FalseAlarm_NoHelp;
    [Test] procedure Sca014_OldCompiler_NoHelp;
    [Test] procedure Sca014_LazarusProject_NoHelp;
    [Test] procedure Sca014_FpcInclude_NoHelp;
    // Gegenpruefung V-B2S-3: das Netzlaufwerk (NetworkPathReason).
    [Test] procedure Sca014_RemoteDrive_NoHelp;
    // Entscheid Nico 2026-10-24: dieselben Trivialen wie die Code-Aktion.
    [Test] procedure Sca014_TrivialsLikeContextAction;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog,
  uMagicNumbers,
  uRepoSettings,         // TRepoSettings (Vorgabe MagicNumberTrivials)
  uRdxCodeMap,           // TRdxCodeMap
  uRdxMagicFixes,        // IsTrivialLiteral
  uRdxRecipeRunner,      // TRdxFixOutcome
  uRdxFixTable,          // CaptionFor
  uRdxPaths,             // SetRdxRemoteDriveTest (Naht fuer das Netzlaufwerk)
  uTestRdxDetectorKit,   // TSeen, Detect-/Plan-/FixAll-Helfer
  uTestRdxTextKit;       // Join, WriteText, TempName

const
  // Das Netzlaufwerk der Attrappe (FakeRemoteDrive).
  DRIVE_Q = 'Q:';

// ---- Helfer ----

// Der Verteiler fuer den echten Detektor (TDetectorRun) - nur SCA014.
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TMagicNumberDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := DetectSource('rdx_magic_', ASource, AKind, RunDetector);
end;

// Fund fuer Fund, bis der Detektor schweigt; er muss mindestens einmal
// melden.
function FixAll(const ASource: string): string;
begin
  Assert.IsTrue(Length(Detect(ASource, fkMagicNumber)) > 0, 'der Detektor meldet');
  Result := FixAllWith(ASource, fkMagicNumber, Detect);
end;

procedure AssertNoHelp(const ASource, AReasonPart: string);
begin
  AssertNoHelpWith(ASource, fkMagicNumber, AReasonPart, Detect);
end;

// Eine Unit mit der Prozedur P(X, Y: Integer) und dem Rumpf ABody; AHead
// vor interface.
function InUnit(const AHead, ABody: array of string): string;
begin
  Result := Join(['unit t;']) + #13#10 + Join(AHead) + #13#10
    + Join(['interface', '', 'implementation', '',
      'procedure P(X, Y: Integer);', 'begin']) + #13#10 + Join(ABody)
    + #13#10 + Join(['end;', '', 'end.']);
end;

// Der Fund in der Datei AFile (auf der Platte, fuer MagicCheck) mit dem
// Text ASource - die Hilfe ueber den Einstieg des Anbieters.
function OutcomeIn(const ASource, AFile: string): TRdxFixOutcome;
var
  Seen : TArray<TSeen>;
begin
  WriteText(AFile, ASource);
  Seen := DetectFile(AFile, fkMagicNumber, RunDetector);
  Assert.AreEqual<Integer>(1, Length(Seen), 'genau ein Fund');
  Result := PlanFixIn(ASource, AFile, fkMagicNumber, Seen[0]);
end;

// Attrappe fuer GetDriveType in der Netzpfad-Regel (uRdxPaths): nur Q: ist
// ein Netzlaufwerk.
function FakeRemoteDrive(const ADrive: string): Boolean;
begin
  Result := SameText(ADrive, DRIVE_Q);
end;

// ---- Faelle ----

procedure TTestRdxMagicFixDetector.Sca014_CatalogExample;
var
  Meta      : TRuleMeta;
  Bad, Good : string;
begin
  // 'bad' ist 'if RetryCount > 3 then ...', 'good' deklariert MAX_RETRIES
  // auf Unit-Ebene - die Hilfe schreibt die Inline-Konstante direkt davor,
  // mit dem vorlaeufigen Namen MagicNr01. Hier mit 42: dieser Test laeuft
  // ohne ApplyDetectorThresholds, also mit der Vorgabe-Liste der
  // trivialen Zahlen aus uSCAConsts.DEFAULT_MAGIC_TRIVIALS - dort ist die
  // 3 trivial. EXE, Plugin und CLI setzen dagegen die Liste aus
  // TRepoSettings ('0,1,2,-1,10,100', uRepoSettings) - dort meldet der
  // Detektor die 3 (Referenzlauf ab8, Katalog-Beispiel im Plugin). Keine
  // ini-Drift (analyser.ini traegt MagicNumberTrivials auskommentiert),
  // sondern zwei Vorgaben im Bestand; sie anzugleichen bewegt Funde - eine
  // Detektor-Charge (Gegen-Review Q14, Minor 12).
  Meta := TRuleCatalog.GetRuleCanonical(fkMagicNumber);
  Bad := StringReplace(CatalogText(Meta.BadExample), ' ...', ' Retry;', []);
  Bad := StringReplace(Bad, '> 3 ', '> 42 ', []);
  Good := StringReplace(CatalogText(Meta.GoodExample), ' ...', ' Retry;', []);
  Good := StringReplace(Good, '= 3;', '= 42;', []);
  Good := StringReplace(Good, 'MAX_RETRIES', 'MagicNr01', [rfReplaceAll]);
  Good := StringReplace(Good, #13#10, #13#10'  ', [rfReplaceAll]);
  Assert.AreEqual(InUnit([], ['  Foo;', '  ' + Good]),
    FixAll(InUnit([], ['  Foo;', '  ' + Bad])));
end;

// Nicos Fall: Alcinoe Demos/ALCipher/_Source/Unit1.pas:268.
procedure TTestRdxMagicFixDetector.Sca014_AlcinoeRoundTrip;
var
  Src, Want : string;
begin
  Src := InUnit([], ['    while True do begin', '      inc(LCounter);',
    '      if millisecondsbetween(now, LLastGUIUpdate) > 200 then begin',
    '        LLastGUIUpdate := now;', '      end;', '    end;']);
  Want := StringReplace(Src,
    '      if millisecondsbetween(now, LLastGUIUpdate) > 200 then begin',
    '      const MagicNr01 = 200;'#13#10
    + '      if millisecondsbetween(now, LLastGUIUpdate) > MagicNr01 then begin',
    []);
  Assert.AreEqual(Want, FixAll(Src));
end;

// Zwei Funde: nach der ersten Hilfe meldet der Detektor den zweiten auf der
// verschobenen Zeile; der zweite Name ist frei (MagicNr02).
procedure TTestRdxMagicFixDetector.Sca014_TwoFindings_OneAfterTheOther;
begin
  Assert.AreEqual(InUnit([], ['  Foo;', '  const MagicNr01 = 300;',
      '  if X > MagicNr01 then Bar;', '  const MagicNr02 = 500;',
      '  if Y < MagicNr02 then Baz;']),
    FixAll(InUnit([], ['  Foo;', '  if X > 300 then Bar;',
      '  if Y < 500 then Baz;'])));
end;

// Zweig ohne begin (Nico, Fall 3): Deklaration und Anweisung kommen in
// einen neuen Block.
procedure TTestRdxMagicFixDetector.Sca014_Branch_RoundTrip;
begin
  Assert.AreEqual(InUnit([], ['  if Y = 0 then', '  begin',
      '    const MagicNr01 = 300;', '    if X > MagicNr01 then Foo;', '  end;',
      '  Bar;']),
    FixAll(InUnit([], ['  if Y = 0 then', '    if X > 300 then Foo;',
      '  Bar;'])));
end;

procedure TTestRdxMagicFixDetector.Sca014_Outcome_CaptionAndHint;
var
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
  Src  : string;
begin
  Src := InUnit([], ['  Foo;', '  if X > 200 then Bar;']);
  Seen := Detect(Src, fkMagicNumber);
  Assert.AreEqual<Integer>(1, Length(Seen), 'genau ein Fund');
  O := PlanFixIn(Src, 't.pas', fkMagicNumber, Seen[0]);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.IsFalse(O.ChangesBehavior, 'bedeutungsgleich (E26)');
  // Deutsch: der Testlauf steht auf 'de' (reDelphix.Test.dpr, Charge C0).
  Assert.AreEqual('Lokale Konstante f'#$00FC'r 200 einf'#$00FC'hren',
    TRdxFixTable.CaptionFor(fkMagicNumber, O));
  Assert.IsTrue(Pos('MagicNr01', O.Hint) > 0, O.Hint);
  // Umbenennen von Hand oder mit Refactor > Rename - nicht Sync Edit (Esc
  // zerstoert dort Text; Gegen-Review Q14, Minor 13).
  Assert.IsTrue(Pos('Strg+Umschalt+E', O.Hint) > 0, O.Hint);
  Assert.IsFalse(Pos('Strg+Umschalt+J', O.Hint) > 0, O.Hint);
end;

// Zweimal 200 in der Bedingung: mehrdeutig (E28: nur eines, sonst sperren).
procedure TTestRdxMagicFixDetector.Sca014_Ambiguous_NoHelp;
begin
  AssertNoHelp(InUnit([], ['  Foo;', '  if (X > 200) or (Y < 200) then Bar;']),
    'mehrdeutig');
end;

// '200_000' - auch mit Bruchteil - meldet der Detektor als "200" (er liest
// '_000' als Bezeichner; ohne Delphi gegengeprueft: CLI-Exe, beide Formen):
// ein Fehlalarm, die Hilfe nennt ihn samt dem Literal statt 'Zeile
// verschoben?'. Behebt eine Detektor-Charge den Fehlalarm, meldet der
// Detektor hier nichts mehr, und der Test faellt mit 'der Detektor meldet'
// - dann diesen Test und den Trenner-Zweig von TRdxMagicFixes.LiteralAt
// anpassen.
procedure TTestRdxMagicFixDetector.Sca014_DigitSeparator_FalseAlarm_NoHelp;
begin
  AssertNoHelp(InUnit([], ['  Foo;', '  if X > 200_000 then Bar;']),
    'vergleicht mit 200_000 - der Detektor liest bei Zifferntrennern nur den '
    + 'ersten Block 200');
  AssertNoHelp(InUnit([], ['  Foo;', '  if X > 200_000.5 then Bar;']),
    'vergleicht mit 200_000.5 - der Detektor liest bei Zifferntrennern nur '
    + 'den ersten Block 200');
end;

// Eine Unit, die nach Delphi XE2 fragt, baut auch dort - ohne
// Inline-Konstante. Umlautfreies Teilstueck des Grunds: '... - die Datei
// traegt Spuren aelterer Compiler' hat in i18n/de.po echte Umlaute
// (Entscheid E29), die Testquellen bleiben ASCII.
procedure TTestRdxMagicFixDetector.Sca014_OldCompiler_NoHelp;
begin
  AssertNoHelp(InUnit(['{$IF CompilerVersion >= 23}{$IFEND}'], ['  Foo;',
    '  if X > 300 then Bar;']), 'gibt es erst ab Delphi 10.3 - die Datei');
end;

// Ein Verzeichnis TEMP\<APrefix><GUID>\a\b\ (mit Trenner): das Fenster
// von FileReason (die Unit und zwei Ebenen darueber) bleibt im eigenen
// Baum - eine fremde Projektdatei in TEMP kippt den Test nicht
// (Gegen-Review Q14, Minor 14). Die Wurzel raeumt RemoveDeepDir ab.
function DeepDir(const APrefix: string): string;
begin
  Result := IncludeTrailingPathDelimiter(TempName(APrefix, '')) + 'a'
    + PathDelim + 'b' + PathDelim;
  ForceDirectories(Result);
end;

// Raeumt den Baum von DeepDir ab (die Dateien hat der Test geloescht).
procedure RemoveDeepDir(const ADir: string);
var
  D : string;
  i : Integer;
begin
  D := ExcludeTrailingPathDelimiter(ADir);
  for i := 1 to 3 do
  begin
    RemoveDir(D);
    D := ExtractFileDir(D);
  end;
end;

// Der Check der Tabelle (MagicCheck): ein Lazarus-Paket neben der Unit.
procedure TTestRdxMagicFixDetector.Sca014_LazarusProject_NoHelp;
var
  Dir : string;
  O   : TRdxFixOutcome;
begin
  Dir := DeepDir('rdx_magic_laz_');
  try
    WriteText(Dir + 'pkg.lpk', '<?xml version="1.0"?>');
    O := OutcomeIn(InUnit([], ['  Foo;', '  if X > 300 then Bar;']),
      Dir + 'u.pas');
    Assert.IsFalse(O.Enabled, 'keine Hilfe');
    Assert.IsTrue(Pos('pkg.lpk', O.Reason) > 0, O.Reason);
    Assert.AreEqual('Lokale Konstante f'#$00FC'r 300 einf'#$00FC'hren',
      TRdxFixTable.CaptionFor(fkMagicNumber, O), 'gesperrt mit Menuetext');
  finally
    DeleteFile(Dir + 'pkg.lpk');
    DeleteFile(Dir + 'u.pas');
    RemoveDeepDir(Dir);
  end;
end;

// Der Check der Tabelle: ein Include mit FPC-Weiche neben der Unit. Der
// Grund 'das Include defs.inc traegt eine FPC-Weiche (Zeile 1) ...' hat in
// i18n/de.po einen echten Umlaut (Entscheid E29) - geprueft werden die
// umlautfreien Teilstuecke davor und dahinter.
procedure TTestRdxMagicFixDetector.Sca014_FpcInclude_NoHelp;
var
  Dir : string;
  O   : TRdxFixOutcome;
begin
  Dir := DeepDir('rdx_magic_inc_');
  try
    WriteText(Dir + 'defs.inc', '{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}');
    O := OutcomeIn(InUnit(['{$I defs.inc}'], ['  Foo;',
      '  if X > 300 then Bar;']), Dir + 'u.pas');
    Assert.IsFalse(O.Enabled, 'keine Hilfe');
    Assert.IsTrue(Pos('das Include defs.inc ', O.Reason) > 0, O.Reason);
    Assert.IsTrue(Pos(' eine FPC-Weiche (Zeile 1)', O.Reason) > 0, O.Reason);
  finally
    DeleteFile(Dir + 'defs.inc');
    DeleteFile(Dir + 'u.pas');
    RemoveDeepDir(Dir);
  end;
end;

// Der Check der Tabelle (MagicCheck fragt zuerst NetworkPathReason - seit
// dem Wochen-Review 2026-10-21 dieselbe Regel und derselbe Text wie
// SCA147/SCA164, vorher "Netzlaufwerk Q: - ..."): die
// Unit auf einem Netzlaufwerk - dort liest die Hilfe weder Projekt- noch
// Include-Dateien. Q: ist eines nur ueber die Naht (SetRdxRemoteDriveTest),
// die Hilfe sieht die Platte nicht an; die Pfade bestehen aus Teilen (ein
// Literal waere ein SCA016-Fund im Selbstscan). Lang geschrieben
// ('\\?\Q:\..') nennt der Grund seit Charge B2S-a ebenso das Laufwerk
// (uRdxPaths.RemoteDriveOf zieht den Vorsatz ab) - bis dahin sah die
// Laufwerks-Probe dort keines, und FileReason lehnte als "Netzpfad
// (\\?\Q:\src)" ab. Die gewollte Aenderung war bis zur Gegenpruefung
// V-B2S-3 ohne Test; ein Laufwerk mit Vorsatz im Grund faellt hier auf.
procedure TTestRdxMagicFixDetector.Sca014_RemoteDrive_NoHelp;
var
  Seen     : TArray<TSeen>;
  Src      : string;
  UnitPath : string;
  O        : TRdxFixOutcome;
begin
  Src := InUnit([], ['  Foo;', '  if X > 300 then Bar;']);
  Seen := Detect(Src, fkMagicNumber);
  Assert.AreEqual<Integer>(1, Length(Seen), 'genau ein Fund');
  UnitPath := DRIVE_Q + PathDelim + 'src' + PathDelim + 'u.pas';
  SetRdxRemoteDriveTest(FakeRemoteDrive);
  try
    O := PlanFixIn(Src, UnitPath, fkMagicNumber, Seen[0]);
    Assert.IsFalse(O.Enabled, 'keine Hilfe auf dem Netzlaufwerk');
    Assert.IsTrue(Pos('Netzpfad Q: - die Hilfe liest dort keine Projekt- und '
      + 'Include-Dateien', O.Reason) > 0, O.Reason);
    O := PlanFixIn(Src, PathDelim + PathDelim + '?' + PathDelim + UnitPath,
      fkMagicNumber, Seen[0]);
    Assert.IsFalse(O.Enabled, 'keine Hilfe, auch lang geschrieben');
    Assert.IsTrue(Pos('Netzpfad Q: - die Hilfe liest dort keine Projekt- und '
      + 'Include-Dateien', O.Reason) > 0, O.Reason);
  finally
    SetRdxRemoteDriveTest(nil);
  end;
end;

// Entscheid Nico 2026-10-24: die Code-Aktion ohne Fund laesst genau die
// Literale aus, die SCA014 durchlaesst (TRdxMagicFixes.IsTrivialLiteral) -
// gemessen mit der Liste, die EXE, Plugin und CLI setzen (die Vorgabe von
// TRepoSettings, nicht uSCAConsts.DEFAULT_MAGIC_TRIVIALS des Pruefstands,
// s. Sca014_CatalogExample). Je Zahl: meldet der Detektor 'if X > N' nicht,
// ist N trivial. Negative Zahlen meldet der Detektor nie (der Lexer trennt
// das '-' ab) - '-1' pruefen die Text-Tests (TTestRdxContextTrivial).
procedure TTestRdxMagicFixDetector.Sca014_TrivialsLikeContextAction;
const
  NUMS: array[0..23] of Integer = (0, 1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 16,
    31, 32, 63, 64, 99, 100, 101, 255, 256, 1000, 1024, 2048);
var
  Settings : TRepoSettings;
  Alt, Own : TStringList;
  N        : Integer;
  S        : string;
  Map      : TRdxCodeMap;
  Silent   : Boolean;
begin
  Alt := DetectorMagicTrivials;
  Own := TStringList.Create;
  try
    // Eine Kopie der Vorgabe-Liste (wie uSCAConsts sie anlegt) - die
    // globale Liste gehoert danach wieder Alt.
    Own.CaseSensitive := False;
    Own.Sorted := True;
    Own.Duplicates := dupIgnore;
    Settings := TRepoSettings.Create;
    try
      Own.AddStrings(Settings.MagicNumberTrivials);
    finally
      Settings.Free;
    end;
    Assert.IsTrue(Own.Count > 0, 'Vorgabe-Liste aus TRepoSettings');
    DetectorMagicTrivials := Own;
    for N in NUMS do
    begin
      S := IntToStr(N);
      Silent := Length(Detect(InUnit([], ['  Foo;',
        '  if X > ' + S + ' then Bar;']), fkMagicNumber)) = 0;
      // '  Bar(' sind sechs Zeichen: das Literal beginnt in Spalte 7.
      Map := NewMap('  Bar(' + S + ');');
      try
        Assert.IsTrue(Silent = TRdxMagicFixes.IsTrivialLiteral(Map, 1, 7,
          7 + Length(S)), S + ': Detektor still = trivial');
      finally
        Map.Free;
      end;
    end;
  finally
    DetectorMagicTrivials := Alt;
    Own.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxMagicFixDetector);

end.
