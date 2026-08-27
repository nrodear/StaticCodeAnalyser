unit uTestLegacyInitializationSection;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestLegacyInitializationSection = class
  public
    [Test] procedure NoInitBlock_NoFinding;
    [Test] procedure ModernInitialization_NoFinding;
    [Test] procedure LegacyBeginInit_Reported;
    [Test] procedure LegacyInit_KindAndSeverity;
    // GATE A - program/library haben keine Unit-Init-Sektion
    [Test] procedure ProgramMainBlock_NoFinding;
    [Test] procedure LibraryMainBlock_NoFinding;
    [Test] procedure UnitAfterLicenseHeader_StillReported;
    // GATE B+C - Rueckwaerts-TOKEN-Walk statt Erste-Wort-je-Zeile
    [Test] procedure SingleLineBeginEnd_NoFinding;
    [Test] procedure BeginInBlockComment_NoFinding;
    [Test] procedure LegacyInitAfterOneLinerRoutine_StillReported;
    // GATE D - Routinen-Header-Wache
    [Test] procedure RoutineHeaderAfterCandidate_NoFinding;
    [Test] procedure MissingEndDot_NoFinding;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestLegacyInitializationSection.NoInitBlock_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLegacyInitializationSection));
  finally F.Free; end;
end;

procedure TTestLegacyInitializationSection.ModernInitialization_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'initialization'#13#10 +
  '  RegisterClass(TFoo);'#13#10 +
  'finalization'#13#10 +
  '  Cleanup;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLegacyInitializationSection));
  finally F.Free; end;
end;

procedure TTestLegacyInitializationSection.LegacyBeginInit_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'begin'#13#10 +
  '  RegisterClass(TFoo);'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkLegacyInitializationSection));
  finally F.Free; end;
end;

procedure TTestLegacyInitializationSection.LegacyInit_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  'implementation'#13#10 +
  'begin'#13#10 +
  '  Foo;'#13#10 +
  'end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkLegacyInitializationSection then
      begin
        Assert.AreEqual<TFindingKind>(fkLegacyInitializationSection, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint, Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkLegacyInitializationSection finding');
  finally F.Free; end;
end;

// GATE A. Im Hauptblock eines Programms IST `begin..end.` der Programmrumpf;
// `initialization` waere dort syntaktisch unzulaessig, der Hint also
// unbefolgbar. Groesste Einzelklasse des Altbefunds: 80 der 168 Korpusfunde.
procedure TTestLegacyInitializationSection.ProgramMainBlock_NoFinding;
const SRC =
  'program p;'#13#10 +
  'uses SysUtils;'#13#10 +
  'begin'#13#10 +
  '  Run;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLegacyInitializationSection));
  finally F.Free; end;
end;

procedure TTestLegacyInitializationSection.LibraryMainBlock_NoFinding;
const SRC =
  'library l;'#13#10 +
  'exports Foo;'#13#10 +
  'begin'#13#10 +
  '  Init;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLegacyInitializationSection));
  finally F.Free; end;
end;

// GATE-A-GEGENPROBE: das Schluesselwort muss aus dem kommentar-bereinigten
// Text kommen, nicht aus Zeile 1. 11 der 21 echten Korpusfunde stehen in
// Dateien, die mit einem mehrzeiligen Lizenzkopf anfangen (ziptypes.pas,
// ssl_openssl_ver.pas); der Kopf hier enthaelt zusaetzlich das Wort 'program'
// als Prosa. Ein Scanner ohne Kommentar-Zustand faende dort 'Lizenzkopf' oder
// 'program' statt 'unit' und wuerde diese Funde alle verlieren.
procedure TTestLegacyInitializationSection.UnitAfterLicenseHeader_StillReported;
const SRC =
  '{ Lizenzkopf'#13#10 +
  '  program: nur Prosa, kein Code'#13#10 +
  '}'#13#10 +
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'begin // <- Legacy-Init'#13#10 +
  '  Init;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkLegacyInitializationSection),
      'Lizenzkopf davor darf den echten Legacy-Init-Fund nicht kosten');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, '<- Legacy-Init'),
      TFindingHelper.FirstOf(F, fkLegacyInitializationSection).LineNumber,
      'Fund muss auf dem Init-begin liegen');
  finally F.Free; end;
end;

// GATE B+C, Defekt 2: der Einzeiler `begin DoIt; end;` lieferte dem alten
// Zeilenscanner nur sein erstes Wort. Die Tiefe sank um 1, ohne dass das
// zugehoerige `end` sie wieder anhob - danach sah der naechste Routinen-
// `begin` wie ein Unit-Init aus. Alte Fassung: Fund in Zeile 5.
procedure TTestLegacyInitializationSection.SingleLineBeginEnd_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  begin DoIt; end;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLegacyInitializationSection));
  finally F.Free; end;
end;

// GATE B+C, Defekt 3: ExtractFirstWord erkannte nur die ERSTE Zeile eines
// `{ }`-Blocks als Kommentar - die Folgezeilen zaehlten als Code. Das
// auskommentierte `begin` in Zeile 5 wurde als Legacy-Init gemeldet, also ein
// Fund MITTEN IM KOMMENTAR (Hausinvariante: Kommentare sind nie Code).
// Alte Fassung: Fund in Zeile 5.
procedure TTestLegacyInitializationSection.BeginInBlockComment_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  '{ Alt:'#13#10 +
  'begin'#13#10 +
  '}'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  DoIt;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLegacyInitializationSection));
  finally F.Free; end;
end;

// GATE-B+C-GEGENPROBE: dieselben zwei Fallen (Einzeiler-Routine, `begin` im
// Blockkommentar) in einer Datei, die WIRKLICH ein Legacy-Init hat. Der Fund
// muss bleiben und auf Zeile 9 zeigen - nicht auf das `begin` des Einzeilers
// (Zeile 5) und nicht auf das im Kommentar (Zeile 7).
procedure TTestLegacyInitializationSection.LegacyInitAfterOneLinerRoutine_StillReported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin DoIt; end;'#13#10 +
  '{ Alt:'#13#10 +
  'begin'#13#10 +
  '}'#13#10 +
  'begin // <- Legacy-Init'#13#10 +
  '  Init;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkLegacyInitializationSection),
      'genau 1 Legacy-Init-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, '<- Legacy-Init'),
      TFindingHelper.FirstOf(F, fkLegacyInitializationSection).LineNumber,
      'Fund muss auf dem Init-begin liegen, nicht auf Einzeiler oder Kommentar');
  finally F.Free; end;
end;

// GATE D. Muster aus LittleTest43.pas:39 (Formatter-Testfall im Korpus, der
// reservierte Woerter als benannte Argumente missbraucht): das `End` in
// Zeile 9 hebt die Tiefe, das `try` in Zeile 7 senkt sie wieder, und das
// `begin` in Zeile 5 - der Rumpf von Foo - landet dadurch auf Tiefe 0 und
// sieht wie ein Legacy-Init aus. Ohne GATE D waere das ein Fund in Zeile 5;
// der Vorwaertsblick sieht das `procedure` in Zeile 8 zwischen Kandidat und
// `end.` und weiss damit: hier steht noch eine Routine, also ist der Kandidat
// nicht das letzte Element der Datei.
procedure TTestLegacyInitializationSection.RoutineHeaderAfterCandidate_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  Call(a, begin := 0);'#13#10 +
  '  Call(b, try := 0);'#13#10 +
  '  Call(c, procedure := 0);'#13#10 +
  '  Call(d, End := 0);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLegacyInitializationSection));
  finally F.Free; end;
end;

// Ohne `end.` ist die Datei kein vollstaendiger Uebersetzungsteil (Fragment,
// Include-Schnipsel, abgeschnittene Datei). Der Walk hat dann keinen
// Startpunkt - lieber kein Verdikt als ein geratenes. Alte Fassung: Fund in
// Zeile 4.
procedure TTestLegacyInitializationSection.MissingEndDot_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'begin'#13#10 +
  '  Init;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLegacyInitializationSection));
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLegacyInitializationSection);

end.
