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
// FPC-Weiche).
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
    [Test] procedure Sca014_OldCompiler_NoHelp;
    [Test] procedure Sca014_LazarusProject_NoHelp;
    [Test] procedure Sca014_FpcInclude_NoHelp;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog,
  uMagicNumbers,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uRdxFixTable,          // CaptionFor
  uTestRdxDetectorKit;   // TSeen, Join, Detect-/Plan-/Apply-Helfer

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

// ---- Faelle ----

procedure TTestRdxMagicFixDetector.Sca014_CatalogExample;
var
  Meta      : TRuleMeta;
  Bad, Good : string;
begin
  // 'bad' ist 'if RetryCount > 3 then ...', 'good' deklariert MAX_RETRIES
  // auf Unit-Ebene - die Hilfe schreibt die Inline-Konstante direkt davor,
  // mit dem vorlaeufigen Namen MagicNr01. Die 3 steht in der Vorgabe-Liste
  // der trivialen Zahlen (uSCAConsts.DEFAULT_MAGIC_TRIVIALS: 0..7, 8, 10,
  // 16 ...) - der Detektor meldet das Katalog-Beispiel so nicht; hier mit
  // 42 (Nebenbefund Charge Q14).
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
  Assert.AreEqual('Introduce local constant for 200',
    TRdxFixTable.CaptionFor(fkMagicNumber, O));
  Assert.IsTrue(Pos('MagicNr01', O.Hint) > 0, O.Hint);
  Assert.IsTrue(Pos('Strg+Umschalt+J', O.Hint) > 0, O.Hint);
end;

// Zweimal 200 in der Bedingung: mehrdeutig (E28: nur eines, sonst sperren).
procedure TTestRdxMagicFixDetector.Sca014_Ambiguous_NoHelp;
begin
  AssertNoHelp(InUnit([], ['  Foo;', '  if (X > 200) or (Y < 200) then Bar;']),
    'mehrdeutig');
end;

// Eine Unit, die nach Delphi XE2 fragt, baut auch dort - ohne
// Inline-Konstante.
procedure TTestRdxMagicFixDetector.Sca014_OldCompiler_NoHelp;
begin
  AssertNoHelp(InUnit(['{$IF CompilerVersion >= 23}{$IFEND}'], ['  Foo;',
    '  if X > 300 then Bar;']), 'Spuren aelterer Compiler');
end;

// Der Check der Tabelle (MagicCheck): ein Lazarus-Paket neben der Unit.
procedure TTestRdxMagicFixDetector.Sca014_LazarusProject_NoHelp;
var
  Dir : string;
  O   : TRdxFixOutcome;
begin
  Dir := IncludeTrailingPathDelimiter(TempName('rdx_magic_laz_', ''));
  ForceDirectories(Dir);
  try
    WriteText(Dir + 'pkg.lpk', '<?xml version="1.0"?>');
    O := OutcomeIn(InUnit([], ['  Foo;', '  if X > 300 then Bar;']),
      Dir + 'u.pas');
    Assert.IsFalse(O.Enabled, 'keine Hilfe');
    Assert.IsTrue(Pos('pkg.lpk', O.Reason) > 0, O.Reason);
    Assert.AreEqual('Introduce local constant for 300',
      TRdxFixTable.CaptionFor(fkMagicNumber, O), 'gesperrt mit Menuetext');
  finally
    DeleteFile(Dir + 'pkg.lpk');
    DeleteFile(Dir + 'u.pas');
    RemoveDir(Dir);
  end;
end;

// Der Check der Tabelle: ein Include mit FPC-Weiche neben der Unit.
procedure TTestRdxMagicFixDetector.Sca014_FpcInclude_NoHelp;
var
  Dir : string;
  O   : TRdxFixOutcome;
begin
  Dir := IncludeTrailingPathDelimiter(TempName('rdx_magic_inc_', ''));
  ForceDirectories(Dir);
  try
    WriteText(Dir + 'defs.inc', '{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}');
    O := OutcomeIn(InUnit(['{$I defs.inc}'], ['  Foo;',
      '  if X > 300 then Bar;']), Dir + 'u.pas');
    Assert.IsFalse(O.Enabled, 'keine Hilfe');
    Assert.IsTrue(Pos('das Include defs.inc traegt eine FPC-Weiche', O.Reason) > 0,
      O.Reason);
  finally
    DeleteFile(Dir + 'defs.inc');
    DeleteFile(Dir + 'u.pas');
    RemoveDir(Dir);
  end;
end;

end.
