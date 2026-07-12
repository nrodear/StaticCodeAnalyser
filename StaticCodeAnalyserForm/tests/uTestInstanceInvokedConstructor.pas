unit uTestInstanceInvokedConstructor;

// Tests fuer den TInstanceInvokedConstructorDetector.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestInstanceInvokedConstructor = class
  public
    // ---- Positive Varianten ------------------------------------------------
    [Test] procedure LowercaseVarCreate_Reported;
    [Test] procedure FieldFPrefixCreate_Reported;
    [Test] procedure CreateWithArgs_Reported;
    [Test] procedure MultipleHits_AllReported;

    // ---- Negative Varianten / Guards --------------------------------------
    [Test] procedure ClassTCreate_NoFinding;
    [Test] procedure ClassICreate_NoFinding;
    [Test] procedure SelfCreate_NoFinding;
    [Test] procedure InheritedCreate_NoFinding;
    [Test] procedure ResultCreate_NoFinding;
    [Test] procedure UppercaseVar_NoFinding;
    [Test] procedure CastCreate_NoFinding;
    [Test] procedure NonCreateCall_NoFinding;
    [Test] procedure MultiDotPath_NoFinding;

    // ---- Finding-Inhalt ----------------------------------------------------
    [Test] procedure Finding_KindAndSeverity;

    // ---- Track C (Cross-Unit-TypeIndex) Opt-in, Runde 3 --------------------
    // FP-Klasse 'record-value-type': `r.Create` wo r eine Var/Param eines
    // WERTTYP-RECORDS ist (TRegEx/... , Seed oder in-source 'record') ist kein
    // Instanz-statt-Klassen-Ctor-Bug. TypeIndex nur im Pipeline-Weg gebaut;
    // FindingsOf ruft mit AContext=nil auf -> Opt-in inaktiv (nil-Fallback).
    [Test] procedure RecordReceiver_InSource_ViaPipeline_Suppressed;
    [Test] procedure RecordReceiver_SeedRegEx_ViaPipeline_Suppressed;
    [Test] procedure ClassReceiver_ViaPipeline_Reported;
    [Test] procedure RecordReceiver_NoContext_StillReported;

    // ---- Track C Feld-Receiver-Erweiterung (2026-07-12) --------------------
    // Empfaenger ist ein KLASSEN-FELD (nicht Local/Param); Typ per Klassen-Feld-
    // Map + TypeIndex aufgeloest. Record-Feld -> unterdrueckt; Klassen-Feld ->
    // Fund bleibt; Local shadowt gleichnamiges Feld -> Local-Typ entscheidet.
    [Test] procedure FieldRecordReceiver_ViaPipeline_Suppressed;
    [Test] procedure FieldClassReceiver_ViaPipeline_Reported;
    [Test] procedure FieldShadowedByClassLocal_ViaPipeline_Reported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestInstanceInvokedConstructor.LowercaseVarCreate_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var obj: TStringList;'#13#10 +
  'begin obj.Create; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInstanceInvokedConstructor));
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.FieldFPrefixCreate_Reported;
// f-Prefix-Field: 'fItems' beginnt mit Lowercase -> Variable.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin fItems.Create; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInstanceInvokedConstructor));
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.CreateWithArgs_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var obj: TFooBar;'#13#10 +
  'begin obj.Create(42, ''hello''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInstanceInvokedConstructor));
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.MultipleHits_AllReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  a.Create;'#13#10 +
  '  b.Create;'#13#10 +
  '  c.Create;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(3, TFindingHelper.Count(F, fkInstanceInvokedConstructor));
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.ClassTCreate_NoFinding;
// TStringList ist eine Klasse (T-Prefix) -> legitimer Class-Call.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin L := TStringList.Create; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInstanceInvokedConstructor));
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.ClassICreate_NoFinding;
// I-Prefix = Interface, theoretisch nicht createbar, aber kein Bug-Pattern.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin IFoo.Create; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInstanceInvokedConstructor));
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.SelfCreate_NoFinding;
// Self.Create in Constructor ist legitim (Delegation).
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin Self.Create(42); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInstanceInvokedConstructor));
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.InheritedCreate_NoFinding;
// 'inherited Create' wird vom Parser als nkInherited gespeichert,
// nicht als nkCall - keine Detektion noetig. Defensiv getestet.
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin inherited Create; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInstanceInvokedConstructor));
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.ResultCreate_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo: TStringList;'#13#10 +
  'begin Result := TStringList.Create; Result.Create; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInstanceInvokedConstructor));
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.UppercaseVar_NoFinding;
// 'MyList.Create' - uppercase Start, koennte Klasse sein (kein T-Prefix
// aber Konvention nicht zwingend). Heuristik skippt.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin MyList.Create; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInstanceInvokedConstructor));
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.CastCreate_NoFinding;
// `TFoo(x).Create` ist Cast-Form, nicht Instance.Create - eigener Detektor
// (CastAndFreeCheck-Familie). Hier sicherheitshalber kein Doppel-Treffer.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: TObject;'#13#10 +
  'begin TStringList(x).Create; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInstanceInvokedConstructor));
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.NonCreateCall_NoFinding;
// `obj.Add(...)` ist normaler Method-Call, nicht Create.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var obj: TStringList;'#13#10 +
  'begin obj.Add(''x''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInstanceInvokedConstructor));
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.MultiDotPath_NoFinding;
// `owner.sub.Create` - Multi-Dot-Receiver, Heuristik kann nicht
// entscheiden ob owner.sub Class oder Instance ist -> skip.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin owner.sub.Create; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInstanceInvokedConstructor));
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var obj: TStringList;'#13#10 +
  'begin obj.Create; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkInstanceInvokedConstructor then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkInstanceInvokedConstructor finding expected');
    Assert.AreEqual(fkInstanceInvokedConstructor, Hit.Kind);
    Assert.AreEqual(lsError,                      Hit.Severity);
  finally F.Free; end;
end;

// --- Track C (Cross-Unit-TypeIndex) Opt-in, Runde 3 -------------------------
// FP-Klasse 'record-value-type' (SCA124): `r.Create` auf einer lokalen Var/
// Param eines WERTTYP-RECORDS (System.RegularExpressions.TRegEx, TRttiContext,
// ...) allokiert nichts und ueberschreibt keine Instanzfelder - kein Instanz-
// statt-Klassen-Ctor-Bug. Der Detektor loest den Empfaenger-Typ aus den
// nkLocalVar/nkParam-Deklarationen der Methode auf und fragt den repo-weiten
// TTypeIndex nach dem Kind (nkRecord bzw. RTL-Seed). WICHTIG: der TypeIndex
// wird NUR im Pipeline-Weg (FindingsViaPipeline) gebaut; FindingsOf ruft den
// Detektor mit AContext=nil auf -> CtxTypeIndex nil, Opt-in inaktiv.

procedure TTestInstanceInvokedConstructor.RecordReceiver_InSource_ViaPipeline_Suppressed;
// FP-Suppression A: Empfaenger 'r' ist eine lokale Var eines im File
// deklarierten RECORDS. TypeKindOf(trec)=tkiRecord -> unterdrueckt.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TRec = record'#13#10 +
  '    class function Create: TRec; static;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var r: TRec;'#13#10 +
  'begin'#13#10 +
  '  r.Create;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC, fcLow);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInstanceInvokedConstructor),
    'TypeIndex beweist r als Werttyp-Record -> SCA124 unterdrueckt');
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.RecordReceiver_SeedRegEx_ViaPipeline_Suppressed;
// FP-Suppression B (Seed-Pfad, KEIN in-source Decl): 'reg' ist vom RTL-Value-
// Record TRegEx (System.RegularExpressions, nicht im Scan-Scope, per Seed
// vorbelegt). TypeKindOf(tregex)=tkiRecord -> unterdrueckt.
const SRC =
  'unit t; interface'#13#10 +
  'uses System.RegularExpressions;'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var reg: TRegEx;'#13#10 +
  'begin'#13#10 +
  '  reg.Create;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC, fcLow);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInstanceInvokedConstructor),
    'Seed-Record TRegEx -> tkiRecord -> SCA124 unterdrueckt (beweist Seed-Pfad)');
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.ClassReceiver_ViaPipeline_Reported;
// TP-Gegenprobe: 'f' ist eine echte KLASSEN-Instanz (TypeKindOf=tkiClass) -
// `f.Create` bleibt ein Instanz-statt-Klassen-Ctor-Bug -> Fund BLEIBT trotz
// aktivem TypeIndex. Beweist zugleich, dass SCA124 im Pipeline-Weg laeuft.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure Bar;'#13#10 +
  'var f: TFoo;'#13#10 +
  'begin'#13#10 +
  '  f.Create;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC, fcLow);
  try Assert.IsTrue(TFindingHelper.Count(F, fkInstanceInvokedConstructor) >= 1,
    'Klassen-Empfaenger bleibt trotz TypeIndex SCA124-Fund');
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.RecordReceiver_NoContext_StillReported;
// Gegenprobe/Doku: DIESELBE Record-Quelle ueber FindingsOf (AContext=nil, kein
// TypeIndex) -> Opt-in inaktiv, die bisherige Lowercase-Heuristik meldet den
// Fund. Belegt, dass der nil-Fallback das bisherige Verhalten unveraendert laesst.
const SRC =
  'unit t; implementation'#13#10 +
  'type TRec = record class function Create: TRec; static; end;'#13#10 +
  'procedure Foo;'#13#10 +
  'var r: TRec;'#13#10 +
  'begin r.Create; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInstanceInvokedConstructor),
    'ohne TypeIndex (AContext=nil) bleibt das bisherige Verhalten erhalten');
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.FieldRecordReceiver_ViaPipeline_Suppressed;
// Feld-Receiver-Erweiterung: 'myrec' ist ein lowercase KLASSEN-FELD von TOwner
// (kein Local/Param), dessen Typ TRec der TypeIndex als Record kennt. Die in
// AnalyzeUnit vorgebaute Klassen-Feld-Map ('towner.myrec'->'TRec') greift ->
// record-value-type -> unterdrueckt.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TRec = record'#13#10 +
  '    class function Create: TRec; static;'#13#10 +
  '  end;'#13#10 +
  '  TOwner = class'#13#10 +
  '    myrec: TRec;'#13#10 +
  '    procedure Foo;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TOwner.Foo;'#13#10 +
  'begin'#13#10 +
  '  myrec.Create;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC, fcLow);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInstanceInvokedConstructor),
    'Record-Feld-Receiver -> Klassen-Feld-Map + tkiRecord -> SCA124 unterdrueckt');
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.FieldClassReceiver_ViaPipeline_Reported;
// TP-Gegenprobe: 'myfoo' ist ein lowercase Feld einer echten KLASSE (TFoo,
// tkiClass). `myfoo.Create` bleibt ein Instanz-statt-Klassen-Ctor-Bug -> Fund
// BLEIBT trotz aktiver Feld-Map (nur Records werden unterdrueckt).
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  end;'#13#10 +
  '  TOwner = class'#13#10 +
  '    myfoo: TFoo;'#13#10 +
  '    procedure Bar;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TOwner.Bar;'#13#10 +
  'begin'#13#10 +
  '  myfoo.Create;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC, fcLow);
  try Assert.IsTrue(TFindingHelper.Count(F, fkInstanceInvokedConstructor) >= 1,
    'Klassen-Feld-Receiver bleibt trotz Feld-Map SCA124-Fund');
  finally F.Free; end;
end;

procedure TTestInstanceInvokedConstructor.FieldShadowedByClassLocal_ViaPipeline_Reported;
// FN-Schutz/Praezedenz: eine lokale Var 'dup' (KLASSE TFoo) shadowt das
// gleichnamige Record-Feld 'dup'. Der echte Bug ist auf der lokalen Klassen-
// Instanz -> muss GEMELDET bleiben. Beweist, dass Local/Param das Feld shadowt
// (kein Rueckfall auf die Feld-Map, sonst faelschliche Unterdrueckung).
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TRec = record'#13#10 +
  '    class function Create: TRec; static;'#13#10 +
  '  end;'#13#10 +
  '  TFoo = class'#13#10 +
  '  end;'#13#10 +
  '  TOwner = class'#13#10 +
  '    dup: TRec;'#13#10 +
  '    procedure Baz;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TOwner.Baz;'#13#10 +
  'var dup: TFoo;'#13#10 +
  'begin'#13#10 +
  '  dup.Create;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC, fcLow);
  try Assert.IsTrue(TFindingHelper.Count(F, fkInstanceInvokedConstructor) >= 1,
    'lokale Klassen-Var shadowt Record-Feld -> Bug bleibt gemeldet');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestInstanceInvokedConstructor);

end.
