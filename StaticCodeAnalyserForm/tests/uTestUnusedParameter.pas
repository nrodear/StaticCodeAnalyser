unit uTestUnusedParameter;

// Tests fuer den TUnusedParameterDetector (fkUnusedParameter).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestUnusedParameter = class
  public
    // ---- Positive ---------------------------------------------------------
    [Test] procedure Param_DeclaredNeverUsed_Reported;
    [Test] procedure Param_TwoParamsOneUnused_OneReported;
    [Test] procedure Param_MultipleUnusedInSameMethod_AllReported;

    // ---- Negative / Skip-Regeln -------------------------------------------
    [Test] procedure Param_Used_NoFinding;
    [Test] procedure Param_OverrideMethod_AllParamsSkipped;
    [Test] procedure Param_EventHandlerSender_Skipped;
    [Test] procedure Param_MultiParamEventHandler_Skipped;
    [Test] procedure Param_UnderscorePrefix_Skipped;
    [Test] procedure Param_VirtualMethod_AllParamsSkipped;
    // Core-Audit 2026-07-18 (SCA054 Welle 1): bare/klammerloses 'inherited'
    // reicht Params implizit an den Parent weiter -> nicht ungenutzt.
    [Test] procedure Param_BareInherited_Skipped;
    [Test] procedure Param_InheritedNoParens_Skipped;
    [Test] procedure Param_InheritedWithExplicitArgs_StillReported;
    // Ist-Messung 2026-07-18: die zwei Parser-Blindstellen der SCA054-FP-Klasse
    [Test] procedure Param_UsedAsCaseSelector_NotReported;
    [Test] procedure Param_UsedOnlyInNestedProc_NotReported;
    [Test] procedure Param_UnusedDespiteNestedProc_StillReported;   // TP-Gegenprobe

    // ---- Finding-Inhalt ---------------------------------------------------
    [Test] procedure Param_Finding_KindAndSeverity;
    [Test] procedure Param_Finding_MissingVarMentionsParamName;
    // Track B1 (2026-07-12): Write/Read-Statement-Call parst jetzt -> Param-Uses sichtbar
    [Test] procedure Param_UsedViaWriteCall_NotReported;
    [Test] procedure Param_KeywordNamedMethodUnused_Reported;
    // T2-Guards-Ruecknahme (2026-07-29): nested types praezise statt pauschal.
    [Test] procedure NestedBridgeDelegate_UnusedParam_NotFlagged;
    [Test] procedure NestedPlainClass_UnusedParam_Flagged;
    // T2b (Review 2026-07-30): generische Basis ist EIN Parent-Eintrag -
    // die Generics-FN-Restklasse aus 86cd02f ist geschlossen.
    [Test] procedure NestedGenericBase_UnusedParam_Flagged;
    [Test] procedure NestedGenericBasePlusInterface_NotFlagged;
    // T3 (2026-07-31): Generic-Call-Statement verlor seine Argumente -
    // der Param im Aufruf galt als ungelesen (Skia-Setter-FP-Klasse).
    [Test] procedure GenericCallArgument_ParamNotFlagged;
    // ---- Interface-Skip fuer normale Klassen + raise-only (2026-08-01) ----
    [Test] procedure PlainClassWithInterface_NotReported;
    [Test] procedure RaiseOnlyBody_NotReported;
    [Test] procedure PlainClassWithoutInterface_StillReported;
    [Test] procedure BodyWithStatementBesideRaise_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestUnusedParameter.Param_DeclaredNeverUsed_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(LogLevel: Integer);'#13#10 +
  'begin Bar; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedParameter));
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_TwoParamsOneUnused_OneReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(Data: Integer; LogLevel: Integer);'#13#10 +
  'begin Bar(Data); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedParameter));
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_MultipleUnusedInSameMethod_AllReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(a: Integer; b: Integer; c: Integer);'#13#10 +
  'begin Bar; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(3, TFindingHelper.Count(F, fkUnusedParameter));
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_Used_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(LogLevel: Integer);'#13#10 +
  'begin Bar(LogLevel); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedParameter));
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_OverrideMethod_AllParamsSkipped;
// override-Methode: Signatur ist von Basis-Klasse vorgegeben, Parameter
// auch wenn ungenutzt notwendig.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  procedure Run(LogLevel: Integer); override;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Run(LogLevel: Integer);'#13#10 +
  'begin Bar; end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedParameter),
    'override-Methoden werden geskippt (Signatur-Konformitaet)');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_EventHandlerSender_Skipped;
// Single-Sender:TObject = Event-Handler-Konvention. Sender wird oft
// nicht gebraucht und ist trotzdem Teil des Vertrags.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.ButtonClick(Sender: TObject);'#13#10 +
  'begin Bar; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedParameter),
    'Event-Handler mit Single-Sender-Param wird geskippt');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_MultiParamEventHandler_Skipped;
// FP-Fix (Real-World 2026-06-28): Multi-Param-Event-Handler (erster Param
// Sender) - weitere Params sind durch den Event-Typ vorgeschrieben und oft
// ungenutzt. Frueher nur Single-Sender erfasst -> hier 2 FPs (Sender + State).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.GridDrawCell(Sender: TObject; ACol: Integer; State: Integer);'#13#10 +
  'begin Bar(ACol); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedParameter),
    'Multi-Param-Event-Handler (erster Param Sender) wird komplett geskippt');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_UnderscorePrefix_Skipped;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(_LogLevel: Integer);'#13#10 +
  'begin Bar; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedParameter),
    '_-Prefix = intentionally unused -> Skip');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_VirtualMethod_AllParamsSkipped;
// virtual-Methoden duerfen von Subklassen ueberschrieben werden, die
// Parameter brauchen.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  procedure Hook(Data: Integer); virtual;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Hook(Data: Integer);'#13#10 +
  'begin Bar; end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedParameter),
    'virtual-Methoden werden geskippt (Subklassen-Vertrag)');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(orphan: Integer);'#13#10 +
  'begin Bar; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkUnusedParameter then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkUnusedParameter finding expected');
    Assert.AreEqual(fkUnusedParameter, Hit.Kind);
    Assert.AreEqual(lsHint, Hit.Severity);
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_Finding_MissingVarMentionsParamName;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(orphan: Integer);'#13#10 +
  'begin Bar; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkUnusedParameter then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit);
    Assert.Contains(Hit.MissingVar, 'orphan');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_UsedViaWriteCall_NotReported;
// Track B1 (2026-07-12): der Body ruft 'Write(Buf)' auf Statement-Ebene. Vor dem
// Parser-Fix wurde dieser keyword-Call NICHT als nkCall geparst -> Buf-Nutzung
// unsichtbar -> falsches 'unused parameter'. Jetzt parst 'Write(Buf)' als Call
// -> Buf ist benutzt -> kein Fund. (Ersetzt den entfernten IsKeywordRoutineName-Guard.)
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Send(Buf: Integer);'#13#10 +
  'begin Write(Buf); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedParameter),
    'Buf ist via Write(Buf)-Call benutzt - kein unused-parameter-Fund');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_KeywordNamedMethodUnused_Reported;
// Track B1 TP-Gegenprobe: eine keyword-benannte Methode 'Write' mit ECHT
// ungenutztem Param wird jetzt korrekt gemeldet (der fruehere Guard hatte diesen
// echten TP faelschlich unterdrueckt).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Write(Buf: Integer);'#13#10 +
  'begin DoSomething; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedParameter),
    'keyword-benannte Methode mit echt ungenutztem Param -> Fund (Guard entfernt)');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_BareInherited_Skipped;
// Core-Audit 2026-07-18 (SCA054 Welle 1, 5%-FP-Konzept): bare 'inherited;'
// reicht die aktuellen Parameter implizit an die Elternmethode weiter -> der
// Parameter ist NICHT ungenutzt (Parser: nkInherited mit leerem Namen).
// Groesste absolute FP-Klasse (~7.950).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Run(LogLevel: Integer);'#13#10 +
  'begin inherited; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedParameter),
    'bare inherited; reicht Params weiter -> kein unused-Param');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_InheritedNoParens_Skipped;
// Klammerloses 'inherited Create;' reicht die aktuellen Parameter ebenfalls
// implizit weiter (Delphi-Semantik) -> nkInherited.Name='Create' ohne '('.
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create(AOwner: TComponent);'#13#10 +
  'begin inherited Create; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedParameter),
    'klammerloses inherited Create reicht Params weiter -> kein unused-Param');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_InheritedWithExplicitArgs_StillReported;
// TP-Gegenprobe: 'inherited Run(0)' MIT expliziten Args reicht die aktuellen
// Parameter NICHT implizit weiter (nkInherited.Name enthaelt '(') -> ein hier
// ungenutzter Parameter bleibt ein echter Fund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Run(LogLevel: Integer);'#13#10 +
  'begin inherited Run(0); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedParameter),
    'inherited Run(0) mit expliziten Args reicht nicht weiter -> Fund bleibt');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_UsedAsCaseSelector_NotReported;
// Ist-Messung 2026-07-18: Parameter, der NUR als case-Selektor gelesen wird
// ('case AWeight of'). Der Parser verwarf den Selektor frueher via
// SkipTo(tkKwOf) -> unsichtbar -> FP. Jetzt landet er in nkCaseStmt.TypeRef
// und zaehlt als Nutzung (CollectAllTokens).
const SRC =
  'unit t; implementation'#13#10 +
  'function Map(AWeight: Integer): string;'#13#10 +
  'begin'#13#10 +
  '  case AWeight of'#13#10 +
  '    1: Result := ''thin'';'#13#10 +
  '    2: Result := ''bold'';'#13#10 +
  '  else Result := ''normal'';'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedParameter),
    'case-Selektor ist eine Nutzung des Parameters');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_UsedOnlyInNestedProc_NotReported;
// Ist-Messung 2026-07-18: Parameter wird NUR in einer nested proc gelesen.
// Der Parser verwirft nested-Bodies (nkNestedRange-Marker bleibt) -> frueher
// FP. Jetzt scannt der Detektor die Marker-Ranges in der gestrippten Quelle.
// FindingsOfFile noetig (echte Datei -> AcquireLines).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Outer(AStream: TObject);'#13#10 +
  '  procedure Inner;'#13#10 +
  '  begin'#13#10 +
  '    Process(AStream);'#13#10 +
  '  end;'#13#10 +
  'begin'#13#10 +
  '  Inner;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedParameter),
    'Nutzung in nested proc (nkNestedRange-Quelle) ist eine Nutzung');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_UnusedDespiteNestedProc_StillReported;
// TP-Gegenprobe: Methode HAT eine nested proc, aber der Parameter kommt darin
// NICHT vor -> bleibt ein echter unused-Param-Fund (Fallback matcht nicht).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Outer(AOrphan: Integer);'#13#10 +
  '  procedure Inner;'#13#10 +
  '  begin'#13#10 +
  '    DoStuff;'#13#10 +
  '  end;'#13#10 +
  'begin'#13#10 +
  '  Inner;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedParameter),
    'Param ohne Vorkommen in der nested-Range bleibt ungenutzt -> Fund');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.NestedBridgeDelegate_UnusedParam_NotFlagged;
// Bridge-Delegate: nested class implementiert ein Interface (2. Eintrag
// der class(...)-Liste). Signatur compiler-erzwungen (E2291) - der
// ungenutzte Parameter ist nicht behebbar, kein Fund.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TOuter = class'#13#10 +
  '  public'#13#10 +
  '    type'#13#10 +
  '      TDelegate = class(TObject, IInterface)'#13#10 +
  '      public'#13#10 +
  '        procedure onTokenUpdated(oldToken: JToken);'#13#10 +
  '      end;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TOuter.TDelegate.onTokenUpdated(oldToken: JToken);'#13#10 +
  'begin'#13#10 +
  '  Beep;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedParameter),
      'Interface-implementierende nested class: Signatur erzwungen');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.NestedPlainClass_UnusedParam_Flagged;
// Nested class OHNE Interfaces: normale Analyse - der Fall der drei
// TP-belegten Shift-Parameter, die der Blanket-Skip geopfert hatte.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TOuter = class'#13#10 +
  '  public'#13#10 +
  '    type'#13#10 +
  '      TView = class'#13#10 +
  '      public'#13#10 +
  '        procedure InternalMouseDown(Shift: Integer);'#13#10 +
  '      end;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TOuter.TView.InternalMouseDown(Shift: Integer);'#13#10 +
  'begin'#13#10 +
  '  Beep;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedParameter),
      'nested class ohne Interfaces: ungenutzter Param muss gemeldet werden');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.NestedGenericBase_UnusedParam_Flagged;
// T2b (Review 2026-07-30): 'class(TObjectList<TItem>)' ergab vor dem
// Parser-Fix TypeRef 'TObjectList TItem' - zwei Eintraege, von
// OwnerHasInterfaceParents als Basis+Interface gelesen -> Skip -> der
// ungenutzte Parameter blieb ungemeldet (FN-Restklasse aus 86cd02f).
// Seit dem Generic-Zweig des Eltern-Loops (balanciert konsumieren +
// nkGenericArgs-Marker) ist die Basis EIN Eintrag und die nested class
// wird normal analysiert.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TOuter = class'#13#10 +
  '  public'#13#10 +
  '    type'#13#10 +
  '      TView = class(TObjectList<TItem>)'#13#10 +
  '      public'#13#10 +
  '        procedure InternalMouseDown(Shift: Integer);'#13#10 +
  '      end;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TOuter.TView.InternalMouseDown(Shift: Integer);'#13#10 +
  'begin'#13#10 +
  '  Beep;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedParameter),
      'generische Basis allein ist KEIN Interface - Param muss gemeldet ' +
      'werden');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.NestedGenericBasePlusInterface_NotFlagged;
// Waechter gegen Ueberdrehen des Parser-Fixes: generische Basis PLUS
// echtes Interface muss weiterhin als Interface-Implementierer gelesen
// werden (Signatur compiler-erzwungen, E2291) - kein Fund. Wuerde der
// Eltern-Loop versehentlich ', IHandler' mitfressen, kippte dieser Test.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TOuter = class'#13#10 +
  '  public'#13#10 +
  '    type'#13#10 +
  '      TDelegate = class(TBaseGen<TItem>, IHandler)'#13#10 +
  '      public'#13#10 +
  '        procedure onFire(AArg: JEvent);'#13#10 +
  '      end;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TOuter.TDelegate.onFire(AArg: JEvent);'#13#10 +
  'begin'#13#10 +
  '  Beep;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedParameter),
      'Basis+Interface: Signatur compiler-erzwungen, Skip muss halten');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.GenericCallArgument_ParamNotFlagged;
// T3 (2026-07-31): 'SetValue<TAlphaColor>(FColor, AValue);' verlor im
// Parser die Argumente (ParsePrimary brach an tkLt ab) - AValue galt
// als ungelesen und der Setter wurde gemeldet (8 belegte FPs in den
// FMX./Vcl.Skia-Settern). Mit dem Generic-Suffix-Zweig traegt der
// nkCall die Argumente und der Parameter zaehlt als gelesen.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TPaint = class'#13#10 +
  '  private'#13#10 +
  '    procedure SetColor(const AValue: Integer);'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TPaint.SetColor(const AValue: Integer);'#13#10 +
  'begin'#13#10 +
  '  SetValue<TAlphaColor>(FColor, AValue);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedParameter),
      'AValue wird im Generic-Call gelesen - kein Fund');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.PlainClassWithInterface_NotReported;
// Audit-FP-Klasse 2 (4/24): der Interface-Skip griff nur bei nested types.
// IMVCSerializer & Co haengen an gewoehnlichen Klassen; deren Signatur ist
// genauso compiler-erzwungen (E2291).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TSerializer = class(TInterfacedObject, IMVCSerializer)'#13#10 +
  '    procedure Serialize(const AObj: TObject; const AIgnored: string);'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TSerializer.Serialize(const AObj: TObject; const AIgnored: string);'#13#10 +
  'begin'#13#10 +
  '  AObj.ToString;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedParameter),
    'Signatur einer interface-tragenden Klasse ist nicht frei aenderbar');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.RaiseOnlyBody_NotReported;
// Ein Rumpf, der nur wirft, KANN seine Parameter nicht lesen. Den Parameter
// zu streichen wuerde die von aussen vorgegebene Signatur brechen.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '    procedure DoIt(const AValue: string);'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.DoIt(const AValue: string);'#13#10 +
  'begin'#13#10 +
  '  raise ENotImplemented.Create(''not supported'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedParameter),
    'raise-only-Rumpf kann Parameter nicht lesen');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.PlainClassWithoutInterface_StillReported;
// WAECHTER: eine gewoehnliche Klasse OHNE Interface behaelt die Pruefung.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class(TObject)'#13#10 +
  '    procedure DoIt(const AUsed, AUnused: string);'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.DoIt(const AUsed, AUnused: string);'#13#10 +
  'begin'#13#10 +
  '  Beep(AUsed);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkUnusedParameter) >= 1,
    'Klasse ohne Interface bleibt pruefbar');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.BodyWithStatementBesideRaise_StillReported;
// WAECHTER: nur der REINE raise-Rumpf ist ausgenommen. Steht noch eine
// Anweisung daneben, koennte der Parameter dort gelesen werden.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class(TObject)'#13#10 +
  '    procedure DoIt(const AUnused: string);'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.DoIt(const AUnused: string);'#13#10 +
  'begin'#13#10 +
  '  Beep;'#13#10 +
  '  raise ENotImplemented.Create(''x'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkUnusedParameter) >= 1,
    'Rumpf mit weiterer Anweisung bleibt pruefbar');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUnusedParameter);

end.
