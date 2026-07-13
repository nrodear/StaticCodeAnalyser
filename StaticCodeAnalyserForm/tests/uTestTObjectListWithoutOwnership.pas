unit uTestTObjectListWithoutOwnership;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestTObjectListWithoutOwnership = class
  public
    [Test] procedure TListAddCreate_Reported;
    [Test] procedure TListSubclassAddCreate_Reported;
    [Test] procedure TObjectListAddCreate_NotReported;
    [Test] procedure TListNoAdd_NotReported;
    [Test] procedure InterfaceListAddCreate_NotReported;
    // --- Track C (Cross-Unit-TypeIndex) Opt-in, Runde 3 -----------------------
    // FP-Klasse 'record-value-type': Add(T.Create) wo T ein WERTTYP-RECORD ist
    // (TRegEx/... , Seed oder in-source 'record') leakt NICHT. Der TypeIndex
    // wird NUR im vollen Pipeline-Weg (FindingsViaPipeline) gebaut; FindingsOf
    // ruft den Detektor mit AContext=nil auf -> Opt-in inaktiv (nil-Fallback).
    [Test] procedure RecordItem_InSource_ViaPipeline_Suppressed;
    [Test] procedure RecordItem_SeedRegEx_ViaPipeline_Suppressed;
    [Test] procedure ClassItem_ViaPipeline_Reported;
    [Test] procedure RecordItem_NoContext_StillReported;
    // Tooling-Haertung (SCA006-Crash 2026-07-13): indizierter LHS darf den
    // Regex-Bau nicht crashen; normaler Fund muss trotzdem kommen.
    [Test] procedure IndexedLhsListVar_NoCrash_NormalStillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestTObjectListWithoutOwnership.TListAddCreate_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TList<TFoo>;'#13#10 +
  'begin'#13#10 +
  '  L := TList<TFoo>.Create;'#13#10 +
  '  L.Add(TFoo.Create);'#13#10 +
  '  L.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkTObjectListWithoutOwnership) >= 1,
      'TList<TFoo> + Add(TFoo.Create) muss gemeldet werden');
  finally F.Free; end;
end;

procedure TTestTObjectListWithoutOwnership.TListSubclassAddCreate_Reported;
// Coverage-Fix (2026-06-21): hinzugefuegter Typ ist eine SUBKLASSE des
// Generic-Args - leakt genauso, muss gemeldet werden.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TList<TAnimal>;'#13#10 +
  'begin'#13#10 +
  '  L := TList<TAnimal>.Create;'#13#10 +
  '  L.Add(TDog.Create);'#13#10 +
  '  L.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkTObjectListWithoutOwnership) >= 1,
      'TList<TAnimal> + Add(TDog.Create) (Subklasse) muss gemeldet werden');
  finally F.Free; end;
end;

procedure TTestTObjectListWithoutOwnership.TObjectListAddCreate_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TObjectList<TFoo>;'#13#10 +
  'begin'#13#10 +
  '  L := TObjectList<TFoo>.Create;'#13#10 +
  '  L.Add(TFoo.Create);'#13#10 +
  '  L.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTObjectListWithoutOwnership),
      'TObjectList ist korrekt - kein Finding');
  finally F.Free; end;
end;

procedure TTestTObjectListWithoutOwnership.TListNoAdd_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TList<TFoo>;'#13#10 +
  'begin'#13#10 +
  '  L := TList<TFoo>.Create;'#13#10 +
  '  L.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTObjectListWithoutOwnership),
      'TList ohne Add ist kein Leak-Risk');
  finally F.Free; end;
end;

procedure TTestTObjectListWithoutOwnership.InterfaceListAddCreate_NotReported;
// FP-Guard: Interface-Listen sind ref-counted - kein Leak. Generic-Arg
// 'IFoo' folgt nicht der Klassen-Konvention 'T...' -> kein Finding.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TList<IFoo>;'#13#10 +
  'begin'#13#10 +
  '  L := TList<IFoo>.Create;'#13#10 +
  '  L.Add(TFooImpl.Create);'#13#10 +
  '  L.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTObjectListWithoutOwnership),
      'Interface-Liste ist ref-counted - kein Leak');
  finally F.Free; end;
end;

// --- Track C (Cross-Unit-TypeIndex) Opt-in, Runde 3 -------------------------
// FP-Klasse 'record-value-type' (SCA174): `List.Add(T.Create)` wo T ein
// WERTTYP-RECORD ist (System.RegularExpressions.TRegEx, TNameValuePair, ...)
// allokiert nichts auf dem Heap - das Item leakt nicht, wenn die Liste
// freigegeben wird, also ist der TObjectList-Rat falsch. Der repo-weite
// TTypeIndex loest den Typ-Kind cross-unit auf (nkRecord bzw. RTL-Seed).
// WICHTIG: Der TypeIndex wird NUR im Pipeline-Weg (TAnalysisSession.Run,
// ssSource -> FindingsViaPipeline) gebaut. FindingsOf ruft den Detektor
// direkt mit AContext=nil auf -> CtxTypeIndex ist nil, Opt-in inaktiv.

procedure TTestTObjectListWithoutOwnership.RecordItem_InSource_ViaPipeline_Suppressed;
// FP-Suppression A: der hinzugefuegte Typ ist ein im File deklarierter RECORD.
// TypeKindOf(trec)=tkiRecord -> keine Heap-Allokation -> unterdrueckt.
const SRC =
  'unit t; interface'#13#10 +
  'uses System.Generics.Collections;'#13#10 +
  'type'#13#10 +
  '  TRec = record'#13#10 +
  '    class function Create: TRec; static;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TList<TRec>;'#13#10 +
  'begin'#13#10 +
  '  L := TList<TRec>.Create;'#13#10 +
  '  L.Add(TRec.Create);'#13#10 +
  '  L.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC, fcLow);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTObjectListWithoutOwnership),
    'TypeIndex beweist TRec als Werttyp-Record -> SCA174 unterdrueckt');
  finally F.Free; end;
end;

procedure TTestTObjectListWithoutOwnership.RecordItem_SeedRegEx_ViaPipeline_Suppressed;
// FP-Suppression B (Seed-Pfad, KEIN in-source Decl): TRegEx liegt in
// System.RegularExpressions (nicht im Scan-Scope), ist aber als RTL-Value-
// Record vorbelegt (SeedKnownTypes). TypeKindOf(tregex)=tkiRecord -> unterdrueckt.
const SRC =
  'unit t; interface'#13#10 +
  'uses System.Generics.Collections, System.RegularExpressions;'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TList<TRegEx>;'#13#10 +
  'begin'#13#10 +
  '  L := TList<TRegEx>.Create;'#13#10 +
  '  L.Add(TRegEx.Create(''a''));'#13#10 +
  '  L.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC, fcLow);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTObjectListWithoutOwnership),
    'Seed-Record TRegEx -> tkiRecord -> SCA174 unterdrueckt (beweist Seed-Pfad)');
  finally F.Free; end;
end;

procedure TTestTObjectListWithoutOwnership.ClassItem_ViaPipeline_Reported;
// TP-Gegenprobe: der hinzugefuegte Typ ist eine echte KLASSE (TypeKindOf=
// tkiClass) - `Add(TFoo.Create)` leakt weiterhin -> Fund BLEIBT trotz aktivem
// TypeIndex. Sonst waere das Opt-in ein Detektions-Verlust.
const SRC =
  'unit t; interface'#13#10 +
  'uses System.Generics.Collections;'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure Bar;'#13#10 +
  'var L: TList<TFoo>;'#13#10 +
  'begin'#13#10 +
  '  L := TList<TFoo>.Create;'#13#10 +
  '  L.Add(TFoo.Create);'#13#10 +
  '  L.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC, fcLow);
  try Assert.IsTrue(TFindingHelper.Count(F, fkTObjectListWithoutOwnership) >= 1,
    'Klassen-Item bleibt trotz TypeIndex SCA174-Fund');
  finally F.Free; end;
end;

procedure TTestTObjectListWithoutOwnership.RecordItem_NoContext_StillReported;
// Gegenprobe/Doku: DIESELBE Record-Quelle ueber FindingsOf (AContext=nil, kein
// TypeIndex) -> Opt-in inaktiv, die bisherige Heuristik meldet den Fund. Belegt,
// dass der nil-Fallback das bisherige Verhalten unveraendert laesst.
const SRC =
  'unit t; implementation'#13#10 +
  'type TRec = record class function Create: TRec; static; end;'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TList<TRec>;'#13#10 +
  'begin'#13#10 +
  '  L := TList<TRec>.Create;'#13#10 +
  '  L.Add(TRec.Create);'#13#10 +
  '  L.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkTObjectListWithoutOwnership) >= 1,
    'ohne TypeIndex (AContext=nil) bleibt das bisherige Verhalten erhalten');
  finally F.Free; end;
end;

procedure TTestTObjectListWithoutOwnership.IndexedLhsListVar_NoCrash_NormalStillReported;
// SCA006-Crash-Repro: ein indizierter LHS ('Data[0] := TList<TFoo>.Create')
// erzeugt einen ListVars-Key 'data[0]'. Ohne TRegEx.Escape verschluckt das '['
// das ']' der Zeichenklasse [A-Za-z_] und das folgende ')' bleibt unmatched ->
// TRegEx.Create wirft 'unmatched parentheses' -> die ganze Methoden-Analyse
// bricht ab und der normale Fund (L) geht verloren. Mit Escape kein Crash ->
// der L-Fund muss weiter kommen (beweist: Analyse lief durch).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TList<TFoo>; Data: array of TList<TFoo>;'#13#10 +
  'begin'#13#10 +
  '  L := TList<TFoo>.Create;'#13#10 +
  '  L.Add(TFoo.Create);'#13#10 +
  '  Data[0] := TList<TFoo>.Create;'#13#10 +
  '  Data[0].Add(TFoo.Create);'#13#10 +
  '  L.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkTObjectListWithoutOwnership) >= 1,
    'indizierter LHS darf nicht crashen -> normaler L-Fund muss weiter kommen');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestTObjectListWithoutOwnership);

end.
