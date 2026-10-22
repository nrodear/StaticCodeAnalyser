unit uTestRdxMagicFix;

// Quick-Fix SCA014 MagicNumber "Lokale Konstante einfuehren" (uRdxMagicFixes,
// Charge Q14, Entscheid E28) auf Text - ohne Parser, ohne Detektor (laeuft
// in reDelphix.Test UND im FPC-Pruefstand). Vertrag: Kopf von
// uRdxMagicFixes (Ziel aus dem Fund, Sperren) und uRdxCompilerTraces
// (Schwellen); Erwartungen von Hand (Vorher/Nachher-Text), Meldungen im
// Wortlaut des Detektors uMagicNumbers.
//   * Formen: Nicos Fall (Alcinoe Demos/ALCipher Unit1.pas:268), Einzug,
//     Zweig ohne begin (begin..end), nur das Literal der Bedingung (E28),
//     mehrere Bedingungen auf einer Zeile, Nicht-ASCII vor dem Literal;
//   * Ziel: Hex/Float/Vorzeichen/Zifferntrenner sind nicht "200",
//     mehrdeutig (auch ueber Zeilen), Folgezeile der Bedingung, veraltete
//     Zeile, Meldung ohne Zahl bzw. mit Vorzeichen;
//   * Name: kollisionsfrei (auch gegen Kommentare);
//   * Sperren: Spuren alter Compiler (Schwelle 10.3, SCA121 bleibt bei
//     2009), FPC-Weiche, xEdit-Skript, die Sperren der Code-Aktion (else
//     if, case-Zweig, initialization);
//   * Platte (der Check in uRdxFixTable): Lazarus-Dateiart und -Projekt
//     neben der Unit, Compiler-Weichen der Includes (auch verschachtelt,
//     fehlend).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxMagicFix = class
  public
    [Test] procedure Sca014_AlcinoeCipherDemo;
    [Test] procedure Sca014_IndentAndDeclaration;
    [Test] procedure Sca014_BranchGetsBeginEnd;
    [Test] procedure Sca014_OnlyTheConditionLiteral;
    [Test] procedure Sca014_TwoIfsOnOneLine;
    [Test] procedure Sca014_NonAsciiBeforeLiteral;
    [Test] procedure Target_OtherFormsAreNotTheNumber;
    [Test] procedure Target_FloatBesideTheNumber;
    [Test] procedure Refuse_AmbiguousCondition;
    [Test] procedure Refuse_LiteralOnFollowLine;
    [Test] procedure Refuse_StaleLine;
    [Test] procedure Refuse_MessageWithoutNumber;
    [Test] procedure Name_CollisionFree;
    [Test] procedure Refuse_OldCompilerTraces;
    [Test] procedure Sca014_NewCompilerTracesOk;
    [Test] procedure Floors_DefaultStaysAt2009;
    [Test] procedure Refuse_FpcSwitchAndScript;
    [Test] procedure Refuse_IntroContext;
    [Test] procedure Disk_LazarusProjectNearUnit;
    [Test] procedure Disk_IncludeTraces;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxCodeMap, uRdxCompilerTraces, uRdxMagicFixes,
  uTestRdxTextKit;   // Join, Apply, LineOf, WriteText, NewTempDir, RemoveTree,
                     // NewMap

const
  MSG = 'Magic number "%s" in if condition - use a constant';

// ---- Helfer ----

// Eine Unit mit der Prozedur P und dem Rumpf ABody; AHead vor interface.
function UnitWith(const AHead, ABody: array of string): string;
begin
  Result := Join(['unit u;']) + #13#10 + Join(AHead) + #13#10
    + Join(['interface', 'implementation', 'procedure P(X, Y: Integer);',
      'begin']) + #13#10 + Join(ABody) + #13#10 + Join(['end;', 'end.']);
end;

type
  // Ein Lauf des Planers: neuer Text ('' bei Ablehnung), Grund und Plan.
  TFixRun = record
    Text   : string;
    Reason : string;
    Plan   : TRdxMagicPlan;
  end;

// Der Planer fuer den Fund "AValue" auf der Zeile ALine.
function RunAt(const ASource: string; ALine: Integer;
  const AValue: string): TFixRun;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  Result.Text := '';
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    if TRdxMagicFixes.MagicNumber(Map, ALine, Format(MSG, [AValue]),
         Result.Plan, Result.Reason) then
      Result.Text := Apply(ASource, Result.Plan.Edits);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Dasselbe fuer die erste Zeile, die AOnLine enthaelt.
function Run(const ASource, AOnLine, AValue: string): TFixRun;
begin
  Result := RunAt(ASource, LineOf(ASource, AOnLine), AValue);
end;

procedure AssertRefused(const ASource, AOnLine, AValue, APart: string);
var
  F : TFixRun;
begin
  F := Run(ASource, AOnLine, AValue);
  Assert.AreEqual('', F.Text, 'keine Hilfe: ' + AOnLine);
  Assert.IsTrue(Pos(APart, F.Reason) > 0, AOnLine + ': ' + F.Reason);
end;

// ---- Formen ----

// Nicos Fall: Alcinoe Demos/ALCipher/_Source/Unit1.pas:268 (Zeilen 266-
// 269 nachgebaut, die Datei ohne Direktiven aelterer Compiler).
procedure TTestRdxMagicFix.Sca014_AlcinoeCipherDemo;
var
  S : string;
  F : TFixRun;
begin
  S := UnitWith([], ['    while True do begin',
    '      inc(LCounter);',
    '      if millisecondsbetween(now, LLastGUIUpdate) > 200 then begin',
    '        LLastGUIUpdate := now;',
    '      end;',
    '    end;']);
  F := Run(S, '> 200', '200');
  Assert.AreEqual('', F.Reason);
  Assert.AreEqual(StringReplace(S,
    '      if millisecondsbetween(now, LLastGUIUpdate) > 200 then begin',
    '      const MagicNr01 = 200;'#13#10
    + '      if millisecondsbetween(now, LLastGUIUpdate) > MagicNr01 then begin',
    []), F.Text);
  Assert.AreEqual('200', F.Plan.Value, 'Menuetext');
  Assert.AreEqual('MagicNr01', F.Plan.Name, 'Hinweis');
  Assert.IsFalse(F.Plan.Wrap, 'kein Zweig');
  Assert.AreEqual<Integer>(1, Length(F.Plan.Edits), 'EINE Ersetzung');
end;

// Die Deklaration bekommt den Einzug der Zeile (Tab bleibt Tab); eine
// Vergleichsform ohne Leerraum ('X>=300') und ein Kommentar dazwischen.
procedure TTestRdxMagicFix.Sca014_IndentAndDeclaration;
var
  S : string;
begin
  S := UnitWith([], ['  Foo;', #9'if (X>=300) then Bar;']);
  Assert.AreEqual(StringReplace(S, #9'if (X>=300)',
    #9'const MagicNr01 = 300;'#13#10#9'if (X>=MagicNr01)', []),
    Run(S, 'X>=300', '300').Text);
  S := UnitWith([], ['  Foo;', '  if X > { Grenze } 300 then Bar;']);
  Assert.AreEqual(StringReplace(S, '  if X > { Grenze } 300',
    '  const MagicNr01 = 300;'#13#10'  if X > { Grenze } MagicNr01', []),
    Run(S, 'Grenze', '300').Text);
end;

// Zweig ohne begin (Nico, Fall 3): begin..end mit dem Einzug der
// Zweigzeile, die Deklaration darin.
procedure TTestRdxMagicFix.Sca014_BranchGetsBeginEnd;
var
  S : string;
  F : TFixRun;
begin
  S := UnitWith([], ['  if Ready then', '    if X > 300 then Foo;', '  Bar;']);
  F := Run(S, 'X > 300', '300');
  Assert.AreEqual('', F.Reason);
  Assert.IsTrue(F.Plan.Wrap, 'Wrap');
  Assert.AreEqual(UnitWith([], ['  if Ready then', '  begin',
    '    const MagicNr01 = 300;', '    if X > MagicNr01 then Foo;', '  end;',
    '  Bar;']), F.Text);
end;

// E28: nur das Literal der Bedingung - das gleiche hinter 'then' bleibt
// (die Code-Aktion ersetzte alle gleichen der Zeile).
procedure TTestRdxMagicFix.Sca014_OnlyTheConditionLiteral;
var
  S : string;
begin
  S := UnitWith([], ['  Foo;', '  if X > 200 then Y := 200;']);
  Assert.AreEqual(StringReplace(S, '  if X > 200 then',
    '  const MagicNr01 = 200;'#13#10'  if X > MagicNr01 then', []),
    Run(S, 'X > 200', '200').Text);
end;

// Zwei if auf einer Zeile, je ein Fund mit eigener Zahl: jede Bedingung
// zaehlt fuer sich, die Zahl des Funds entscheidet.
procedure TTestRdxMagicFix.Sca014_TwoIfsOnOneLine;
var
  S : string;
begin
  S := UnitWith([], ['  Foo;', '  if X > 300 then if Y < 500 then Bar;']);
  Assert.AreEqual(StringReplace(S, '  if X > 300 then if Y < 500',
    '  const MagicNr01 = 500;'#13#10'  if X > 300 then if Y < MagicNr01', []),
    Run(S, 'Y < 500', '500').Text);
  Assert.AreEqual(StringReplace(S, '  if X > 300 then if Y < 500',
    '  const MagicNr01 = 300;'#13#10'  if X > MagicNr01 then if Y < 500', []),
    Run(S, 'Y < 500', '300').Text);
end;

// Ein Nicht-ASCII-Zeichen (String und Bezeichner) vor dem Literal:
// Zeichenspalten und UTF-8-Bytes zaehlen verschieden.
procedure TTestRdxMagicFix.Sca014_NonAsciiBeforeLiteral;
var
  S, Want : string;
begin
  S := UnitWith([], ['  Foo;',
    '  if (S <> ''Gr'#$00FC'n'') and (L'#$00E4'nge > 300) then Bar;']);
  Want := StringReplace(S, '  if (S', '  const MagicNr01 = 300;'#13#10'  if (S',
    []);
  Want := StringReplace(Want, 'nge > 300)', 'nge > MagicNr01)', []);
  Assert.AreEqual(Want, Run(S, 'nge > 300', '300').Text);
end;

// ---- Ziel aus dem Fund ----

// Hex, Float, Vorzeichen, Zeichencode und Klammern sind nicht der
// Vergleichswert "200" - so meldet der Detektor sie auch nicht (CLI-Scan
// im Review R6-05): steht eine davon an der Stelle, ist die Zeile seit dem
// Scan geaendert.
procedure TTestRdxMagicFix.Target_OtherFormsAreNotTheNumber;
const
  FORMS: array[0..5] of string = ('X > $200', 'X > 200.5', 'X > -200',
    'C = #200', 'X > (200)', 'X > 1e200');
var
  Form : string;
begin
  for Form in FORMS do
    AssertRefused(UnitWith([], ['  Foo;', '  if ' + Form + ' then Bar;']),
      Form, '200', 'Zeile verschoben?');
  // '200_000' meldet der Detektor dagegen als "200" (er liest '_000' als
  // Bezeichner), mit Bruchteil ebenso: ein frischer Fehlalarm. Der Grund
  // nennt ihn samt dem Literal - bis Review R6-05 hiess er 'Zeile
  // verschoben?' (fuer '200_000.5' bis zur Nachbesserung FF), und ein neuer
  // Scan fand denselben Fund wieder.
  AssertRefused(UnitWith([], ['  Foo;', '  if X > 200_000 then Bar;']),
    'X > 200_000', '200', 'vergleicht mit 200_000 - der Detektor liest bei '
    + 'Zifferntrennern nur den ersten Block 200');
  AssertRefused(UnitWith([], ['  Foo;', '  if X > 200_000.5 then Bar;']),
    'X > 200_000.5', '200', 'vergleicht mit 200_000.5 - der Detektor liest '
    + 'bei Zifferntrennern nur den ersten Block 200');
  // Einen Wert liest der Detektor nur hinter einem Vergleich: steht
  // '200_000' anderswo in der Bedingung, ist die Zeile seit dem Scan
  // geaendert (diese Form meldet er nicht).
  AssertRefused(UnitWith([], ['  Foo;', '  if Foo(200_000) > X then Bar;']),
    'Foo(200_000) > X', '200', 'Zeile verschoben?');
  // Trennerwert UND exakter Wert in derselben Bedingung: der Detektor
  // meinte vielleicht das '200_000' (sein erster Vergleich in
  // Op-Reihenfolge) - die Hilfe ersetzte sonst das '200' von Y, und der
  // Fund blieb (Wochen-Review 2026-10-21). Gesperrt als mehrdeutig.
  AssertRefused(UnitWith([], ['  Foo;',
    '  if (X > 200_000) or (Y > 200) then Bar;']), 'X > 200_000', '200',
    'vergleicht mit 200_000 und mit 200 - mehrdeutig');
end;

// '200.5' daneben zaehlt nicht - das eine "200" ist eindeutig.
procedure TTestRdxMagicFix.Target_FloatBesideTheNumber;
var
  S : string;
begin
  S := UnitWith([], ['  Foo;', '  if (A > 200.5) or (B >= 200) then Bar;']);
  Assert.AreEqual(StringReplace(S, '  if (A > 200.5) or (B >= 200)',
    '  const MagicNr01 = 200;'#13#10'  if (A > 200.5) or (B >= MagicNr01)', []),
    Run(S, 'B >= 200', '200').Text);
end;

// Zweimal "200" in der Bedingung - auch ueber die Folgezeile: welches der
// Detektor meinte, sagt die Meldung nicht, und nach EINER Ersetzung meldete
// er das andere (E28: nur eines, sonst sperren).
procedure TTestRdxMagicFix.Refuse_AmbiguousCondition;
begin
  AssertRefused(UnitWith([], ['  Foo;', '  if (X > 200) or (Y < 200) then Bar;']),
    'X > 200', '200', '2-mal mit 200 - mehrdeutig');
  AssertRefused(UnitWith([], ['  Foo;', '  if (X > 200) or',
    '     (Y < 200) then Bar;']), 'X > 200', '200', 'mehrdeutig');
end;

// Der eine Vergleichswert steht in einer Folgezeile der Bedingung: die
// Konstante gehoerte vor die if-Zeile.
procedure TTestRdxMagicFix.Refuse_LiteralOnFollowLine;
begin
  AssertRefused(UnitWith([], ['  Foo;', '  if Ready and',
    '     (X > 200) then Bar;']), 'if Ready', '200', 'Folgezeile');
end;

// Die Zeile traegt den Fund nicht (mehr): kein if, eine andere Zahl, das
// Literal nur hinter 'then' bzw. in einem Kommentar oder String.
procedure TTestRdxMagicFix.Refuse_StaleLine;
var
  S : string;
begin
  S := UnitWith([], ['  Foo(200);', '  if X > 300 then Y := Z > 200;',
    '  if X > { 200 } Y then Bar(''> 200'');']);
  AssertRefused(S, 'Foo(200)', '200', 'kein if - Zeile verschoben?');
  AssertRefused(S, 'X > 300', '200', 'Zeile verschoben?');
  AssertRefused(S, '{ 200 }', '200', 'Zeile verschoben?');
  AssertRefused(S, 'X > 300', '500', 'vergleicht mit 500');
end;

// Die Meldung muss eine Zahl nennen; mit Vorzeichen meldet der Detektor
// nicht (der Lexer trennt '-' ab) - die Hilfe auch nicht.
procedure TTestRdxMagicFix.Refuse_MessageWithoutNumber;
var
  S : string;
begin
  Assert.AreEqual('200', TRdxMagicFixes.NumberOf(Format(MSG, ['200'])));
  Assert.AreEqual('-5', TRdxMagicFixes.NumberOf(Format(MSG, ['-5'])));
  Assert.AreEqual('', TRdxMagicFixes.NumberOf(Format(MSG, ['3.5'])));
  Assert.AreEqual('', TRdxMagicFixes.NumberOf(Format(MSG, ['-'])));
  Assert.AreEqual('', TRdxMagicFixes.NumberOf('Magic number in if condition'));
  S := UnitWith([], ['  Foo;', '  if X > -5 then Bar;']);
  AssertRefused(S, 'X > -5', '-5', 'mit Vorzeichen');
  AssertRefused(S, 'X > -5', '5.0', 'keine Zahl');
end;

// ---- Name ----

// MagicNr01 steht schon in der Datei (auch nur im Kommentar): MagicNr02;
// MagicNr010 ist ein anderes Wort.
procedure TTestRdxMagicFix.Name_CollisionFree;
var
  S : string;
  F : TFixRun;
begin
  S := UnitWith([], ['  Foo; // MagicNr01 von frueher', '  MAGICNR02 := 1;',
    '  MagicNr010 := 2;', '  if X > 300 then Bar;']);
  F := Run(S, 'X > 300', '300');
  Assert.AreEqual('MagicNr03', F.Plan.Name, F.Reason);
  Assert.IsTrue(Pos('  const MagicNr03 = 300;'#13#10'  if X > MagicNr03 then',
    F.Text) > 0, F.Text);
end;

// ---- Sperren ----

// Eine Inline-Konstante gibt es erst ab Delphi 10.3: jede Spur eines
// aelteren Compilers sperrt - auch die Schwelle selbst ('CompilerVersion
// >= 33' schuetzt gerade die Inline-Form fuer aeltere Compiler).
procedure TTestRdxMagicFix.Refuse_OldCompilerTraces;
const
  TRACES: array[0..8] of string = ('{$I jedi.inc}', '{$IFDEF VER320}{$ENDIF}',
    '{$IF CompilerVersion >= 33}{$IFEND}', '{$IF RTLVersion < 33.0}{$IFEND}',
    '{$IFDEF DELPHI12_UP}{$ENDIF}', '{$IFDEF DELPHIXE2_UP}{$ENDIF}',
    '{$IFNDEF DELPHIX_TOKYO_UP}{$ENDIF}', '{$IFDEF COMPILER26_UP}{$ENDIF}',
    '{$IFDEF CONDITIONALEXPRESSIONS}{$ENDIF}');
var
  T : string;
begin
  for T in TRACES do
    AssertRefused(UnitWith([T], ['  Foo;', '  if X > 300 then Bar;']),
      'X > 300', '300', 'Spuren aelterer Compiler');
end;

// Was nur neuere Compiler nennt, sperrt nicht; ein Kommentar ist keine
// Direktive.
procedure TTestRdxMagicFix.Sca014_NewCompilerTracesOk;
const
  NEW_ONLY: array[0..4] of string = ('{$IFDEF VER330}{$ENDIF}',
    '{$IF CompilerVersion >= 34}{$IFEND}', '{$IFDEF DELPHI27_UP}{$ENDIF}',
    '{$IFDEF RTL340_UP}{$ENDIF}', '// {$IFDEF VER150}');
var
  T : string;
  F : TFixRun;
begin
  for T in NEW_ONLY do
  begin
    F := Run(UnitWith([T], ['  Foo;', '  if X > 300 then Bar;']), 'X > 300',
      '300');
    Assert.AreEqual('', F.Reason, T);
    Assert.IsTrue(F.Text <> '', T);
  end;
end;

// Dieselbe Suche mit der Schwelle von SCA121 (Default(), Delphi 2009) -
// was dort nicht alt war, bleibt es (die Angebote von SCA121 bewegen sich
// nicht); mit der Schwelle 10.3 ist es alt.
procedure TTestRdxMagicFix.Floors_DefaultStaysAt2009;
const
  // '{$IFDEF DELPHI12_UP}' zaehlt seit G05-18 als Spur (FLOOR_DEFAULT_FN:
  // DELPHI-Nummer 8..12 ist ein Kit-Name alter Compiler).
  NEWER_THAN_2009: array[0..4] of string = (
    '{$IF CompilerVersion >= 23}{$IFEND}', '{$IFDEF VER210}{$ENDIF}',
    '{$IFDEF DELPHIXE_UP}{$ENDIF}', '{$IFDEF CONDITIONALEXPRESSIONS}{$ENDIF}',
    '{$IFDEF COMPILER14_UP}{$ENDIF}');
var
  T  : string;
  SL : TStringList;
  M  : TRdxCodeMap;
  Li : Integer;
begin
  for T in NEWER_THAN_2009 do
  begin
    SL := TStringList.Create;
    M := nil;
    try
      SL.Text := UnitWith([T], ['  Foo;']);
      M := TRdxCodeMap.Create(SL);
      Assert.AreEqual('', OldCompilerTrace(M, FLOOR_DEFAULT_FN, Li), T);
      Assert.IsTrue(OldCompilerTrace(M, FLOOR_INLINE_DECL, Li) <> '', T);
      Assert.AreEqual<Integer>(2, Li, T + ': Zeile');
    finally
      M.Free;
      SL.Free;
    end;
  end;
end;

// FPC 3.2 kennt keine Inline-Konstante: FPC-Weiche in der Datei
// (TargetAt). Ein xEdit-Skript ('unit' ohne implementation) uebersetzt
// kein Compiler - sein Interpreter kennt sie auch nicht (Korpus: TES5Edit
// 'Edit Scripts').
procedure TTestRdxMagicFix.Refuse_FpcSwitchAndScript;
begin
  AssertRefused(UnitWith(['{$mode delphi}'], ['  Foo;', '  if X > 300 then Bar;']),
    'X > 300', '300', 'FPC-Weiche');
  AssertRefused(UnitWith(['{$IFDEF FPC}{$ENDIF}'], ['  Foo;',
    '  if X > 300 then Bar;']), 'X > 300', '300', 'FPC-Weiche');
  AssertRefused(Join(['unit userscript;', '', 'procedure P(X: Integer);',
    'begin', '  Foo;', '  if X > 300 then Bar;', 'end;', '', 'end.']),
    'X > 300', '300', 'ohne implementation-Teil');
end;

// Die Sperren der Code-Aktion gelten mit: 'else if' (davor darf keine
// Deklaration), case-Zweig, initialization, Direktive zwischen der Zeile
// darueber und der Anweisung, mehrzeiliger Kommentar.
procedure TTestRdxMagicFix.Refuse_IntroContext;
begin
  AssertRefused(UnitWith([], ['  if A then Foo', '  else if X > 300 then Bar;']),
    'X > 300', '300', 'beginnt mit "else"');
  AssertRefused(UnitWith([], ['  case K of', '    1: if X > 300 then Bar;',
    '  end;']), 'X > 300', '300', 'case-Zweig');
  AssertRefused(UnitWith([], ['  Foo;', '  {$IFDEF DEBUG}',
    '  if X > 300 then Bar;', '  {$ENDIF}']), 'X > 300', '300', 'Direktive');
  AssertRefused(StringReplace(UnitWith([], ['  Foo;']), 'end.',
    'initialization' + #13#10 + '  if X > 300 then Bar;' + #13#10 + 'end.', []),
    'X > 300', '300', 'initialization');
end;

// ---- Platte (Check in uRdxFixTable) ----

// Ein frischer Baum TEMP\rdx_q14_<GUID>\AName\ (mit Trenner) - eigen je
// Test, damit nichts aus einem frueheren Lauf oder aus TEMP selbst im
// Fenster von FileReason liegt (Gegen-Review Q14, Minor 14). Die
// GUID-Wurzel kommt in ARoot: RemoveTree(ARoot) raeumt ab. Bis zum
// Wochen-Review 2026-10-21 leiteten die Tests sie per ParentDir-Kette ab -
// eine Ebene weniger, und RemoveTree loeschte TEMP selbst.
function FreshDir(const AName: string; out ARoot: string): string;
begin
  ARoot := NewTempDir('rdx_q14_');
  Result := ARoot + AName + PathDelim;
  ForceDirectories(Result);
end;

// Die Dateiart (.pp, .lpr) und ein Lazarus-Projekt bzw. -Paket im
// Verzeichnis der Unit oder bis zwei darueber (doublecmd: AudioInfo.lpi
// eine Ebene ueber den Units); drei darueber zaehlt nicht mehr.
procedure TTestRdxMagicFix.Disk_LazarusProjectNearUnit;
var
  Tmp, Root, Sub, U, R : string;
begin
  Assert.IsTrue(Pos('FPC 3.2', TRdxMagicFixes.FileReason('C:\x\unit1.pp')) > 0);
  Assert.IsTrue(Pos('.lpr', TRdxMagicFixes.FileReason('project1.LPR')) > 0);
  Assert.AreEqual('', TRdxMagicFixes.FileReason(''));
  Root := FreshDir('laz', Tmp);
  try
    Sub := Root + 'a' + PathDelim;
    U := Sub + 'b' + PathDelim + 'c' + PathDelim + 'u.pas';
    ForceDirectories(ExtractFilePath(U));
    WriteText(Root + 'top.lpi', '<?xml?>');
    Assert.AreEqual('', TRdxMagicFixes.FileReason(U), 'drei Ebenen hoeher');
    WriteText(Sub + 'pkg.lpk', '<?xml?>');
    R := TRdxMagicFixes.FileReason(U);
    Assert.IsTrue(Pos('pkg.lpk', R) > 0, R);
    DeleteFile(Sub + 'pkg.lpk');
    WriteText(ExtractFilePath(U) + 'prog.lpr', 'program prog; begin end.');
    R := TRdxMagicFixes.FileReason(U);
    Assert.IsTrue(Pos('prog.lpr', R) > 0, R);
  finally
    RemoveTree(Tmp);
  end;
end;

// Die Includes der Unit (auch im Kopf, auch verschachtelt): eine FPC-Weiche
// oder Spur aelterer Compiler sperrt, ein fehlendes Include auch; ein
// Include ohne beides nicht.
procedure TTestRdxMagicFix.Disk_IncludeTraces;
var
  Tmp, Dir, U, R : string;
  Map            : TRdxCodeMap;
begin
  Dir := FreshDir('inc', Tmp) + 'a' + PathDelim + 'b' + PathDelim;
  Map := nil;
  try
    ForceDirectories(Dir);
    U := Dir + 'u.pas';
    Map := NewMap(UnitWith(['{$I defs.inc}'],
      ['  Foo;', '  if X > 300 then Bar;']));
    DeleteFile(Dir + 'defs.inc');
    R := TRdxMagicFixes.IncludeReason(U, Map);
    Assert.IsTrue(Pos('Include defs.inc nicht neben der Unit', R) > 0, R);
    WriteText(Dir + 'defs.inc', '{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}');
    R := TRdxMagicFixes.IncludeReason(U, Map);
    Assert.IsTrue(Pos('das Include defs.inc traegt eine FPC-Weiche', R) > 0, R);
    WriteText(Dir + 'defs.inc', Join(['{$DEFINE FAST}', '{$I deeper.inc}']));
    WriteText(Dir + 'deeper.inc', '{$IF CompilerVersion < 30}{$IFEND}');
    R := TRdxMagicFixes.IncludeReason(U, Map);
    Assert.IsTrue(Pos('Spuren aelterer Compiler (COMPILERVERSION < 30', R) > 0, R);
    Assert.IsTrue(Pos('eingebunden von defs.inc', R) > 0, R);
    WriteText(Dir + 'deeper.inc', '{$IF CompilerVersion >= 35}{$IFEND}');
    Assert.AreEqual('', TRdxMagicFixes.IncludeReason(U, Map));
  finally
    Map.Free;
    RemoveTree(Tmp);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxMagicFix);

end.
