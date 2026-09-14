unit uTestUseAfterFree;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestUseAfterFree = class
  public
    [Test] procedure FreeThenUse_Reported;
    [Test] procedure FreeAndNilThenUse_Reported;
    [Test] procedure FreeThenReassign_NoFinding;
    [Test] procedure FreeAtEndOfMethod_NoFinding;
    [Test] procedure FreeOnSelf_NoFinding;
    [Test] procedure FreeOnResult_NoFinding;
    [Test] procedure Finding_KindAndSeverity;
    // A.4.6 CFG-Filter
    [Test] procedure CfgFilter_IfThenFreeExit_NoFinding;
    [Test] procedure CfgFilter_FreeInBothBranches_StillNoFinding;
    // Audit-Fixes nach mORMot/Firebird-Self-Test
    [Test] procedure FreeFieldAssignment_NoFinding;
    [Test] procedure FreeMethodWithArgument_NoFinding;
    // CFG-Variable-Overwrite-Bug (base64func.pas-Pattern)
    [Test] procedure CfgFilter_TryWithIfElse_NoFinding;
    // Real-World 2026-06-23: Destruktor-Header + qualifizierter Member
    [Test] procedure DestructorHeader_NotReported;
    [Test] procedure QualifiedMemberOfOtherObject_NotReported;
    // Posten 284: die Abbruchbedingung des Vorwaerts-Scans
    [Test] procedure ForwardScan_EndElseBetween_StillReported;
    [Test] procedure ForwardScan_EndSemicolonBetween_NoFinding_KnownLimit;
    // Posten 217: .Destroy/.DisposeOf, Geschwister-Free, Index-Zugriff
    [Test] procedure DestroyAliasThenUse_Reported;
    [Test] procedure DisposeOfAliasThenUse_Reported;
    [Test] procedure NoFreeAlias_ThenUse_Kontrolle;
    [Test] procedure SiblingFree_AfterFreeAndNil_NoFinding;
    [Test] procedure SiblingFree_RealUse_Kontrolle;
    [Test] procedure SiblingFreeGuard_FreeInstance_Reported;
    [Test] procedure SiblingFree_ThenRealUse_ExactlyOne;
    [Test] procedure CfgFilter_ElseUse_Kontrolle;
    [Test] procedure IndexUseAfterFree_Reported;
    [Test] procedure BareOccurrence_NoAccessor_Kontrolle;
    [Test] procedure CallOnFreedVar_Reported;
    [Test] procedure SiblingGuardNotForDestroy_Reported;
    [Test] procedure SiblingGuardNotForDisposeOf_Reported;
    [Test] procedure CfgFilter_IfElseDestroy_NoFinding;
    [Test] procedure DestroyAsFieldAssignment_NoFinding;
    [Test] procedure DestroyAsFieldAssignment_Kontrolle;
    [Test] procedure DestroyWithArgument_NoFinding;
    [Test] procedure DestroyWithArgument_Kontrolle;
    // ueber die volle Pipeline - nur dort ist der Vorfilter sichtbar
    [Test] procedure DestroyAlias_WithoutFreeToken_PrefilterSkips_KnownLimit;
    [Test] procedure DestroyAlias_WithFreeToken_Kontrolle;
  end;

implementation

// noinspection-file GodClass, LargeClass, DuplicateBlock
// Eine DUnitX-Fixture ist eine flache Liste unabhaengiger Faelle; mit
// Posten 217 sind es 36 Methoden. Und die Paare MUESSEN sich aehneln:
// eine Klammer, die sich in mehr als einer Zeile unterscheidet,
// belegt nichts mehr. DuplicateBlock stand schon vorher mit zwei
// Funden in dieser Datei, aus demselben Grund.

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

{ --- Posten 284: wo der Vorwaerts-Scan wirklich abbricht --------- }
//
// Der Kopfkommentar dieser Regel versprach bis 2026-09-14 "Wort end
// -> Method-Ende; abbrechen". Das sagt fuer beide Fixturen hier 0
// voraus. RE_END_OF_METHOD (uUseAfterFree.pas:110) bricht aber nur am
// ZEILENANFAENGIGEN "end;" ab oder am naechsten Routinen-Keyword -
// ueber "end else", "end)" und Konsorten laeuft der Scan hinweg.
//
// Beide an der Exe gemessen. Das Verhalten ist plausibel und bleibt;
// falsch war nur der Kommentar, der jetzt die Regex beschreibt.

{ --- Posten 217: die zwei Freigabe-Aliase und zwei stille Pfade -- }
//
// Die 2026-06-18 ergaenzten Aliase .Destroy und .DisposeOf hatten
// keinen einzigen Test - weder positiv noch als Gegenprobe. Ebenso
// ungetestet: der Geschwister-Zweig (ein zweites Free hinter dem
// ersten beendet die Suche) und der Index-Zugriff als Nutzung.
//
// ZUM HARNESS: alle Tests bis auf die letzten zwei rufen
// FindingsOfFile und umgehen damit den Token-Vorfilter. Die
// Fixtures tragen trotzdem eine echte Freigabe (oder eine
// Kommentarzeile), damit sie AUCH in der Produktion gescannt
// wuerden - sonst waeren die Zahlen hier und dort verschieden.
//
// Alle Erwartungen an der Exe gemessen, mit gesetztem
// Konfidenz-Filter: fkUseAfterFree ist fcLow und faellt ohne ihn
// stumm aus.

procedure TTestUseAfterFree.DestroyAliasThenUse_Reported;
// Der erste Alias. Gemessen: 1.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Bar;'#13#10 +
  'var M: TStringList;'#13#10 +
  'begin'#13#10 +
  '  M := TStringList.Create;'#13#10 +
  '  M.Free;'#13#10 +
  'end;'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  L.Destroy;'#13#10 +
  '  L.Add(''x'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkUseAfterFree),
      'Destroy ist eine Freigabe wie Free');
  finally F.Free; end;
end;

procedure TTestUseAfterFree.DisposeOfAliasThenUse_Reported;
// Der zweite Alias. Gemessen: 1.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Bar;'#13#10 +
  'var M: TStringList;'#13#10 +
  'begin'#13#10 +
  '  M := TStringList.Create;'#13#10 +
  '  M.Free;'#13#10 +
  'end;'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  L.DisposeOf;'#13#10 +
  '  L.Add(''x'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkUseAfterFree),
      'DisposeOf ist eine Freigabe wie Free');
  finally F.Free; end;
end;

procedure TTestUseAfterFree.NoFreeAlias_ThenUse_Kontrolle;
// DIE KLAMMER zu beiden: derselbe Aufbau mit einer Methode,
// die nichts freigibt. Gemessen: 0.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Bar;'#13#10 +
  'var M: TStringList;'#13#10 +
  'begin'#13#10 +
  '  M := TStringList.Create;'#13#10 +
  '  M.Free;'#13#10 +
  'end;'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  L.Clear;'#13#10 +
  '  L.Add(''x'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkUseAfterFree),
      'ohne Freigabe ist die Folgenutzung harmlos');
  finally F.Free; end;
end;

procedure TTestUseAfterFree.SiblingFree_AfterFreeAndNil_NoFinding;
// Der Geschwister-Zweig: hinter der Freigabe steht ein
// ZWEITES Free auf derselben Variablen - das typische
// Aufraeummuster. Die Suche endet dort, ohne zu melden.
// Gemessen: 0.
//
// Die Fixture ist absichtlich geradlinig (kein if/else):
// sonst koennte der Ablauffilter die Null erklaeren und der
// Test pruefte den falschen Mechanismus.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  FreeAndNil(L);'#13#10 +
  '  L.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkUseAfterFree),
      'ein zweites Free ist keine Nutzung');
  finally F.Free; end;
end;

procedure TTestUseAfterFree.SiblingFree_RealUse_Kontrolle;
// DIE KLAMMER dazu: dieselbe Fixture, nur die letzte Zeile
// ist eine echte Nutzung. Gemessen: 1.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  FreeAndNil(L);'#13#10 +
  '  L.Clear;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkUseAfterFree),
      'eine echte Nutzung hinter der Freigabe wird gemeldet');
  finally F.Free; end;
end;

procedure TTestUseAfterFree.SiblingFreeGuard_FreeInstance_Reported;
// Der Geschwister-Zweig prueft auf Wortgrenze: FreeInstance
// beginnt mit Free, ist aber nicht Free. Gemessen: 1.
// Ohne die Wortgrenze waere hier eine echte Nutzung stumm.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  FreeAndNil(L);'#13#10 +
  '  L.FreeInstance;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkUseAfterFree),
      'FreeInstance ist nicht Free - die Wortgrenze traegt');
  finally F.Free; end;
end;

procedure TTestUseAfterFree.SiblingFree_ThenRealUse_ExactlyOne;
// Geschwister-Free UND danach eine echte Nutzung: genau ein
// Fund, auf der Nutzungszeile. Gemessen: 1.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  FreeAndNil(L);'#13#10 +
  '  L.Free;'#13#10 +
  '  L.Clear;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkUseAfterFree),
      'das Geschwister-Free verdeckt die spaetere Nutzung nicht');
  finally F.Free; end;
end;

procedure TTestUseAfterFree.CfgFilter_ElseUse_Kontrolle;
// Zur Abgrenzung: dieselbe Nutzung in einem else-Zweig, den
// die Freigabe nie erreicht. Gemessen: 0 - hier greift der
// Ablauffilter, nicht der Geschwister-Zweig.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(Cond: Boolean);'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  if Cond then'#13#10 +
  '    FreeAndNil(L)'#13#10 +
  '  else'#13#10 +
  '    L.Clear;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkUseAfterFree),
      'unerreichbare Nutzung wird vom Ablauffilter verworfen');
  finally F.Free; end;
end;

procedure TTestUseAfterFree.IndexUseAfterFree_Reported;
// Der Index-Zugriff als Nutzung - eigener Zweig neben dem
// Punkt-Zugriff. Gemessen: 1.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList; S: string;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  L.Free;'#13#10 +
  '  S := L[0];'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkUseAfterFree),
      'ein Index-Zugriff nach der Freigabe ist eine Nutzung');
  finally F.Free; end;
end;

procedure TTestUseAfterFree.BareOccurrence_NoAccessor_Kontrolle;
// DIE KLAMMER: dasselbe Vorkommen ohne Zugriff. Der Kopf
// nennt das ausdruecklich als bewusst nicht geflaggt (zu
// viele Fehlfunde). Gemessen: 0.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList; S: string;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  L.Free;'#13#10 +
  '  S := L;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkUseAfterFree),
      'das blosse Vorkommen ist kein Zugriff');
  finally F.Free; end;
end;

procedure TTestUseAfterFree.CallOnFreedVar_Reported;
// Der dritte Nutzungs-Zweig: die Variable als Funktion
// gerufen. Die Fixture ist synthetisch - so schreibt das
// niemand -, aber sie trifft genau diesen Zweig.
// Gemessen: 1.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList; S: string;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  L.Free;'#13#10 +
  '  S := L(0);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkUseAfterFree),
      'ein Aufruf auf der freigegebenen Variablen ist eine Nutzung');
  finally F.Free; end;
end;

procedure TTestUseAfterFree.SiblingGuardNotForDestroy_Reported;
// Der Geschwister-Zweig gilt NUR fuer Free. Das ist richtig
// so: TObject.Free traegt den nil-Schutz, Destroy nicht -
// nach FreeAndNil dereferenziert Destroy eine nil-Referenz.
// Gemessen: 1.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  FreeAndNil(L);'#13#10 +
  '  L.Destroy;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkUseAfterFree),
      'Destroy hinter FreeAndNil ist ein echter Fund');
  finally F.Free; end;
end;

procedure TTestUseAfterFree.SiblingGuardNotForDisposeOf_Reported;
// Dasselbe fuer den zweiten Alias. Gemessen: 1.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  FreeAndNil(L);'#13#10 +
  '  L.DisposeOf;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkUseAfterFree),
      'DisposeOf hinter FreeAndNil ist ein echter Fund');
  finally F.Free; end;
end;

procedure TTestUseAfterFree.CfgFilter_IfElseDestroy_NoFinding;
// Und die Klammer dazu: dasselbe Destroy in einem Zweig, den
// die Freigabe nie erreicht. Gemessen: 0 - das Muster wird
// also nicht blind gemeldet.
const SRC =
  'unit t; implementation'#13#10 +
  '// .free'#13#10 +
  'procedure Foo(Cond: Boolean);'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  if Cond then'#13#10 +
  '    FreeAndNil(L)'#13#10 +
  '  else'#13#10 +
  '    L.Destroy;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkUseAfterFree),
      'unerreichbares Destroy wird verworfen');
  finally F.Free; end;
end;

procedure TTestUseAfterFree.DestroyAsFieldAssignment_NoFinding;
// GRENZE DER ALIASE, im Feld belegt: "vTable.Destroy := ..."
// weist einem FELD einen Zeiger zu, es gibt nichts frei.
// Gemessen: 0.
const SRC =
  'unit t; implementation'#13#10 +
  '// .free'#13#10 +
  'procedure Foo;'#13#10 +
  'var vTable: PVTable;'#13#10 +
  'begin'#13#10 +
  '  vTable := PVTable.Create;'#13#10 +
  '  vTable.Destroy := @SomeDestroyDispatcher;'#13#10 +
  '  vTable.execute := @SomeExecuteDispatcher;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkUseAfterFree),
      'eine Zuweisung an ein Feld namens Destroy gibt nichts frei');
  finally F.Free; end;
end;

procedure TTestUseAfterFree.DestroyAsFieldAssignment_Kontrolle;
// DIE KLAMMER: dieselbe Fixture, das ":= @..." entfernt.
// Gemessen: 1.
const SRC =
  'unit t; implementation'#13#10 +
  '// .free'#13#10 +
  'procedure Foo;'#13#10 +
  'var vTable: PVTable;'#13#10 +
  'begin'#13#10 +
  '  vTable := PVTable.Create;'#13#10 +
  '  vTable.Destroy;'#13#10 +
  '  vTable.execute := @SomeExecuteDispatcher;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkUseAfterFree),
      'ohne Zuweisung ist es ein Aufruf und damit eine Freigabe');
  finally F.Free; end;
end;

procedure TTestUseAfterFree.DestroyWithArgument_NoFinding;
// Zweite Grenze: "fCx.Destroy(fGlobalObj)" ist eine
// gleichnamige Methode mit Argument, keine Freigabe.
// Gemessen: 0.
const SRC =
  'unit t; implementation'#13#10 +
  '// .free'#13#10 +
  'procedure Foo;'#13#10 +
  'var fCx: TQuickJSContext;'#13#10 +
  'begin'#13#10 +
  '  fCx := TQuickJSContext.Create;'#13#10 +
  '  fCx.Destroy(fGlobalObj);'#13#10 +
  '  fCx.Done;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkUseAfterFree),
      'Destroy mit Argument ist eine fremde Methode');
  finally F.Free; end;
end;

procedure TTestUseAfterFree.DestroyWithArgument_Kontrolle;
// DIE KLAMMER: dasselbe ohne Argument. Gemessen: 1.
// Die DisposeOf-Spiegelbilder beider Grenzen sind ebenfalls
// gemessen (0 und 1) und verhalten sich gleich; sie stehen
// hier nicht noch einmal.
const SRC =
  'unit t; implementation'#13#10 +
  '// .free'#13#10 +
  'procedure Foo;'#13#10 +
  'var fCx: TQuickJSContext;'#13#10 +
  'begin'#13#10 +
  '  fCx := TQuickJSContext.Create;'#13#10 +
  '  fCx.Destroy;'#13#10 +
  '  fCx.Done;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkUseAfterFree),
      'ohne Argument ist Destroy die Freigabe');
  finally F.Free; end;
end;

procedure TTestUseAfterFree.DestroyAlias_WithoutFreeToken_PrefilterSkips_KnownLimit;
// DIE EINZIGEN ZWEI TESTS UEBER DIE VOLLE PIPELINE - und
// nur so sichtbar: der Vorfilter dieser Regel kennt nur
// [".free", "freeandnil"]. Eine Datei, die ausschliesslich
// den Alias Destroy benutzt, wird nie gescannt.
// Gemessen: 0, obwohl derselbe Quelltext ueber
// FindingsOfFile 1 liefert.
//
// KEIN Anlass, die Tokenliste anzufassen: 504 der 13.419
// Korpusdateien werden dadurch uebersprungen, und ein
// geoeffneter Vorfilter bringt auf genau diesen Dateien
// NULL zusaetzliche Funde. Der Pin haelt nur fest, was ist.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  L.Destroy;'#13#10 +
  '  L.Add(''x'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC, fcLow);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkUseAfterFree),
      'BEKANNTE GRENZE: ohne Free-Token laeuft der Detektor nicht');
  finally F.Free; end;
end;

procedure TTestUseAfterFree.DestroyAlias_WithFreeToken_Kontrolle;
// DIE KLAMMER: derselbe Fall, aber eine zweite Routine
// enthaelt ein echtes Free - damit traegt die Datei das
// Token und wird gescannt. Gemessen: 1 ueber dieselbe
// Pipeline.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Bar;'#13#10 +
  'var M: TStringList;'#13#10 +
  'begin'#13#10 +
  '  M := TStringList.Create;'#13#10 +
  '  M.Free;'#13#10 +
  'end;'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  L.Destroy;'#13#10 +
  '  L.Add(''x'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC, fcLow);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkUseAfterFree),
      'mit Free-Token irgendwo in der Datei laeuft er');
  finally F.Free; end;
end;


procedure TTestUseAfterFree.ForwardScan_EndElseBetween_StillReported;
// Das "end" des then-Zweigs traegt kein Semikolon - der Scan
// laeuft weiter und findet den Use. Gemessen: 1.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'uses System.Classes;'#13#10 +
  'implementation'#13#10 +
  'procedure Foo(Flag: Boolean);'#13#10 +
  'var'#13#10 +
  '  L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  L.Free;'#13#10 +
  '  if Flag then'#13#10 +
  '  begin'#13#10 +
  '    Beep;'#13#10 +
  '  end'#13#10 +
  '  else'#13#10 +
  '    Beep;'#13#10 +
  '  L.Add(''x'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkUseAfterFree),
      'end ohne Semikolon beendet den Vorwaertsscan nicht');
  finally F.Free; end;
end;

procedure TTestUseAfterFree.ForwardScan_EndSemicolonBetween_NoFinding_KnownLimit;
// DIE GEGENPROBE, und zugleich die bekannte Grenze: dieselbe
// Fixture mit "end;" statt "end else" - der Scan bricht ab und
// der Use bleibt unentdeckt. Gemessen: 0. Ein echter
// Use-after-free hinter einem geschlossenen if-Block wird also
// nicht gemeldet; das ist die defensive Seite der Heuristik.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'uses System.Classes;'#13#10 +
  'implementation'#13#10 +
  'procedure Foo(Flag: Boolean);'#13#10 +
  'var'#13#10 +
  '  L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  L.Free;'#13#10 +
  '  if Flag then'#13#10 +
  '  begin'#13#10 +
  '    Beep;'#13#10 +
  '  end;'#13#10 +
  '  L.Add(''x'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkUseAfterFree),
      'BEKANNTE GRENZE: zeilenanfaengiges end; beendet den Scan');
  finally F.Free; end;
end;


procedure TTestUseAfterFree.FreeThenUse_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  L.Free;'#13#10 +
  '  L.Add(''x'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUseAfterFree),
      'genau 1 UseAfterFree-Fund erwartet');
  finally F.Free; end;
end;

procedure TTestUseAfterFree.FreeAndNilThenUse_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  FreeAndNil(L);'#13#10 +
  '  L.Add(''x'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUseAfterFree),
      'genau 1 UseAfterFree-Fund erwartet');
  finally F.Free; end;
end;

procedure TTestUseAfterFree.FreeThenReassign_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  L.Free;'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  L.Add(''x'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUseAfterFree));
  finally F.Free; end;
end;

procedure TTestUseAfterFree.FreeAtEndOfMethod_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  L.Add(''x'');'#13#10 +
  '  L.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUseAfterFree));
  finally F.Free; end;
end;

procedure TTestUseAfterFree.FreeOnSelf_NoFinding;
// Self.Free + spaeterer Self-Use ist Owner-Pattern, kein Befund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  Self.Free;'#13#10 +
  '  Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUseAfterFree));
  finally F.Free; end;
end;

procedure TTestUseAfterFree.FreeOnResult_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo: TStringList;'#13#10 +
  'begin'#13#10 +
  '  Result := TStringList.Create;'#13#10 +
  '  try'#13#10 +
  '    Result.LoadFromFile(''x'');'#13#10 +
  '  except'#13#10 +
  '    FreeAndNil(Result);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUseAfterFree));
  finally F.Free; end;
end;

procedure TTestUseAfterFree.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  L.Free;'#13#10 +
  '  L.Add(''x'');'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkUseAfterFree then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkUseAfterFree finding expected');
    Assert.AreEqual(fkUseAfterFree, Hit.Kind);
    Assert.AreEqual(lsError,        Hit.Severity);
  finally F.Free; end;
end;

{ ---- A.4.6 CFG-Filter Tests ---- }

procedure TTestUseAfterFree.CfgFilter_IfThenFreeExit_NoFinding;
// Klassischer FP-Fall: Free + Exit im if-Branch, Use im else-Branch.
// Lexisch wuerde der Use auf line 8 als UAF geflagged - mit CFG-Filter
// erkennt CanReach(FreeBlock, UseBlock)=False (Free-Block hat nur
// Exit_ als Successor, kein Pfad zum Use-Block).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(Cond: Boolean);'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  if Cond then'#13#10 +
  '  begin'#13#10 +
  '    FreeAndNil(L);'#13#10 +
  '    Exit;'#13#10 +
  '  end;'#13#10 +
  '  L.Add(''x'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUseAfterFree),
    'CFG-Filter muss FP droppen weil Use nicht von Free aus reachable');
  finally F.Free; end;
end;

procedure TTestUseAfterFree.CfgFilter_FreeInBothBranches_StillNoFinding;
// Free in if-then UND in else-Branch, kein nachfolgender Use. Bisheriger
// lexischer Scan emittiert auch nichts; CFG-Filter veraendert das nicht.
// Sanity-Check dass A.4.6 bestehende negative Cases nicht bricht.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(Cond: Boolean);'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  if Cond then'#13#10 +
  '    FreeAndNil(L)'#13#10 +
  '  else'#13#10 +
  '    L.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUseAfterFree));
  finally F.Free; end;
end;

{ ---- Audit-Fixes ---- }

procedure TTestUseAfterFree.FreeFieldAssignment_NoFinding;
// Firebird-Pattern: 'vTable.free := @ptr' ist eine Assignment auf ein
// Field das zufaellig 'free' heisst (Function-Pointer-Setup fuer
// generated TLB-Header). KEIN Destructor-Call.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var vTable: PVTable;'#13#10 +
  'begin'#13#10 +
  '  vTable := PVTable.Create;'#13#10 +
  '  vTable.free := @SomeFreeDispatcher;'#13#10 +
  '  vTable.execute := @SomeExecuteDispatcher;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUseAfterFree),
    'Free als Field-Assignment muss ignoriert werden');
  finally F.Free; end;
end;

procedure TTestUseAfterFree.FreeMethodWithArgument_NoFinding;
// mORMot quickjs-Pattern: 'fCx.Free(fGlobalObj)' ist ein Method-Call
// MIT Argument - eine Method namens 'Free' die nicht der Destructor
// ist. TObject.Free() hat keinen Parameter. Leere Klammern 'fCx.Free()'
// bleiben weiter ein Destructor-Match.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var fCx: TQuickJSContext;'#13#10 +
  'begin'#13#10 +
  '  fCx := TQuickJSContext.Create;'#13#10 +
  '  fCx.Free(fGlobalObj);'#13#10 +
  '  fCx.Done;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUseAfterFree),
    'Free mit Argument ist Method-Call, kein Destructor');
  finally F.Free; end;
end;

procedure TTestUseAfterFree.CfgFilter_TryWithIfElse_NoFinding;
// doublecmd base64func.pas Pattern (Audit-Reproducer):
// Free in if-then-Branch, Use in else-if-Branch, alles innerhalb
// eines try/except. Vor dem Fix wurde der function-level 'Merge'
// von der rekursiven ProcessOneStatement-Call fuer das innere if
// ueberschrieben - nkTryExcept connectete dann gegen den falschen
// Merge-Block, CanReach lieferte True und der FP blieb.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  try'#13#10 +
  '    L.Add(''init'');'#13#10 +
  '    if Length(L.Text) = 0 then'#13#10 +
  '    begin'#13#10 +
  '      FreeAndNil(L);'#13#10 +
  '      Exit;'#13#10 +
  '    end'#13#10 +
  '    else if L.Count > 1 then'#13#10 +
  '    begin'#13#10 +
  '      L.Add(''second'');'#13#10 +
  '    end;'#13#10 +
  '  except'#13#10 +
  '    if Assigned(L) then L.Free;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUseAfterFree),
    'try/if-Free/elseif-Use: CFG-Filter muss FP droppen');
  finally F.Free; end;
end;

procedure TTestUseAfterFree.DestructorHeader_NotReported;
// FP-Fix (Real-World 2026-06-23): `destructor TFoo.Destroy;` ist ein Method-
// HEADER - das Regex matcht sonst den Typnamen TFoo als "freigegeben" und
// flaggt jede spaetere statische Nutzung (TFoo.X / TFoo(x)). Haeufigste
// SCA134-FP-Klasse.
const SRC =
  'unit t; implementation'#13#10 +
  'destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  inherited;'#13#10 +
  'end;'#13#10 +
  'class procedure TFoo.Init;'#13#10 +
  'begin'#13#10 +
  '  TFoo.FInstance := nil;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUseAfterFree),
    'Destruktor-Header ist kein Free des Typnamens');
  finally F.Free; end;
end;

procedure TTestUseAfterFree.QualifiedMemberOfOtherObject_NotReported;
// FP-Fix (Real-World 2026-06-23): freigegebene bare-Var `Params`; spaeter
// `Conn.Session.Params.Text` - dort ist Params Member eines ANDEREN Objekts
// (Links-Boundary '.'), kein Use der freigegebenen Var.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Params: TStringList;'#13#10 +
  'begin'#13#10 +
  '  Params := TStringList.Create;'#13#10 +
  '  Params.Free;'#13#10 +
  '  ShowMessage(Conn.Session.Params.Text);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUseAfterFree),
    'qualifizierter Member eines anderen Objekts ist kein Use-After-Free');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUseAfterFree);

end.
