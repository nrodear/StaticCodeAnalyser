unit uTestVirtualCallInCtor;

// Tests fuer den TVirtualCallInCtorDetector (AST + parser-Modifiers).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestVirtualCallInCtor = class
  public
    // ---- Positive Varianten ------------------------------------------------
    [Test] procedure VCall_Virtual_InCtor_Reported;
    [Test] procedure VCall_Override_InCtor_Reported;
    [Test] procedure VCall_TwoVirtuals_InCtor_BothReported;
    [Test] procedure VCall_ExplicitSelf_InCtor_Reported;

    // ---- Negative Varianten ------------------------------------------------
    [Test] procedure NonVirtual_InCtor_NoFinding;
    [Test] procedure VirtualMethod_OutsideCtor_NoFinding;
    [Test] procedure InheritedCreate_NoFinding;
    [Test] procedure CallOnOtherObject_NoFinding;
    [Test] procedure NoConstructor_NoFinding;
    [Test] procedure CtorDelegation_NoFinding;
    [Test] procedure CtorCallsOwnConstructor_NoFinding;
    [Test] procedure CtorCallsVirtualProc_StillReported;

    // ---- FP-Gate 2026-07-31: Event-Zuweisung ist kein Aufruf ---------------
    [Test] procedure InheritedEventAssign_NoFinding;
    [Test] procedure InheritedEventAssign_HelperChain_NoFinding;
    [Test] procedure InheritedCreateThenVirtual_SameLine_StillReported;
    [Test] procedure InheritedCreateThenVirtual_OwnLines_StillReported;
    [Test] procedure InheritedEventAssignInComment_StillReported;
    // Praezisierung 2026-07-31 (Review-Fund uVirtualCallInCtor.pas:426):
    // nur der zugewiesene Handler wird verworfen, nicht die ganze Zeile.
    [Test] procedure InheritedAssign_RhsCallWithArgs_StillReported;
    [Test] procedure InheritedEventAssign_TrailingCall_StillReported;

    // ---- Finding-Inhalt ----------------------------------------------------
    [Test] procedure VCall_Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.IOUtils,
  uAstNode, uParser2,
  uSCAConsts, uMethodd12, uVirtualCallInCtor,
  uTestFindingHelper;

// Lokaler DATEI-Harness. Der zentrale FindingsOf-Harness parst in-memory mit
// dem Platzhalternamen 'sample.pas' - der Quellzeilen-Gate von SCA048
// (IsInheritedEventAssignPhantom) faende dort keine Datei und waere inert
// (vakuum-gruen). Deshalb hier ein echter Temp-File-Durchlauf, der NUR den
// VirtualCallInCtor-Detektor aufruft. Die uebrigen Tests dieses Fixtures
// bleiben bewusst auf FindingsOf (AST-Pfad unveraendert).
function FindingsOfRealFile(const Source: string): TObjectList<TLeakFinding>;
var
  Parser   : TParser2;
  Root     : TAstNode;
  TempPath : string;
  SL       : TStringList;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  TempPath := TPath.Combine(TPath.GetTempPath,
    'sca_vcic_' + TGuid.NewGuid.ToString.Replace('{', '').Replace('}', '')
                    .Replace('-', '') + '.pas');
  SL := TStringList.Create;
  try
    SL.Text := Source;
    SL.SaveToFile(TempPath, TEncoding.UTF8);
  finally
    SL.Free;
  end;
  try
    Parser := TParser2.Create;
    try
      Root := Parser.ParseFile(TempPath);
      try
        TVirtualCallInCtorDetector.AnalyzeUnit(Root, TempPath, Result);
      finally
        Root.Free;
      end;
    finally
      Parser.Free;
    end;
  finally
    if TFile.Exists(TempPath) then
      TFile.Delete(TempPath);
  end;
end;

procedure TTestVirtualCallInCtor.VCall_Virtual_InCtor_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBase = class'#13#10 +
  '  constructor Create;'#13#10 +
  '  procedure Init; virtual;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'constructor TBase.Create;'#13#10 +
  'begin'#13#10 +
  '  Init;'#13#10 +
  'end;'#13#10 +
  'procedure TBase.Init; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkVirtualCallInCtor));
  finally F.Free; end;
end;

procedure TTestVirtualCallInCtor.VCall_Override_InCtor_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBase = class'#13#10 +
  '  constructor Create;'#13#10 +
  '  procedure Init; override;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'constructor TBase.Create; begin Init; end;'#13#10 +
  'procedure TBase.Init; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkVirtualCallInCtor));
  finally F.Free; end;
end;

procedure TTestVirtualCallInCtor.VCall_TwoVirtuals_InCtor_BothReported;
// Konstruktor ruft zwei verschiedene virtual-Methoden -> beide Treffer.
// Wichtig: Self.SetupB und SetupA muessen beide als nkCall registriert sein.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBase = class'#13#10 +
  '  constructor Create;'#13#10 +
  '  procedure SetupA; virtual;'#13#10 +
  '  procedure SetupB; virtual;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'constructor TBase.Create;'#13#10 +
  'begin'#13#10 +
  '  SetupA;'#13#10 +
  '  SetupB;'#13#10 +
  'end;'#13#10 +
  'procedure TBase.SetupA; begin end;'#13#10 +
  'procedure TBase.SetupB; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkVirtualCallInCtor),
    'Zwei virtuelle Calls im Ctor -> zwei Findings');
  finally F.Free; end;
end;

procedure TTestVirtualCallInCtor.VCall_ExplicitSelf_InCtor_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBase = class'#13#10 +
  '  constructor Create;'#13#10 +
  '  procedure Init; virtual;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'constructor TBase.Create; begin Self.Init; end;'#13#10 +
  'procedure TBase.Init; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkVirtualCallInCtor));
  finally F.Free; end;
end;

procedure TTestVirtualCallInCtor.NonVirtual_InCtor_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBase = class'#13#10 +
  '  constructor Create;'#13#10 +
  '  procedure Init;'#13#10 +     // KEIN virtual
  'end;'#13#10 +
  'implementation'#13#10 +
  'constructor TBase.Create; begin Init; end;'#13#10 +
  'procedure TBase.Init; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkVirtualCallInCtor));
  finally F.Free; end;
end;

procedure TTestVirtualCallInCtor.VirtualMethod_OutsideCtor_NoFinding;
// Virtual-Call in einer normalen Methode (nicht Constructor) ist OK.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBase = class'#13#10 +
  '  procedure Init; virtual;'#13#10 +
  '  procedure DoStuff;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TBase.DoStuff; begin Init; end;'#13#10 +
  'procedure TBase.Init; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkVirtualCallInCtor));
  finally F.Free; end;
end;

procedure TTestVirtualCallInCtor.InheritedCreate_NoFinding;
// inherited Create geht zur Basisklasse hoch, kein Override-Risiko
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBase = class'#13#10 +
  '  constructor Create;'#13#10 +
  '  procedure Init; virtual;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'constructor TBase.Create; begin inherited Create; end;'#13#10 +
  'procedure TBase.Init; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkVirtualCallInCtor));
  finally F.Free; end;
end;

procedure TTestVirtualCallInCtor.CallOnOtherObject_NoFinding;
// FFoo.DoSomething - kein Self-Call, kein Virtual-Override-Risiko
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBase = class'#13#10 +
  '  FFoo: TObject;'#13#10 +
  '  constructor Create;'#13#10 +
  '  procedure Init; virtual;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'constructor TBase.Create; begin FFoo.Init; end;'#13#10 +
  'procedure TBase.Init; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkVirtualCallInCtor));
  finally F.Free; end;
end;

procedure TTestVirtualCallInCtor.NoConstructor_NoFinding;
// Klasse ohne Constructor - dann kann es auch keinen Virtual-Call darin geben
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBase = class'#13#10 +
  '  procedure Init; virtual;'#13#10 +
  '  procedure Other;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TBase.Other; begin Init; end;'#13#10 +
  'procedure TBase.Init; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkVirtualCallInCtor));
  finally F.Free; end;
end;

procedure TTestVirtualCallInCtor.CtorDelegation_NoFinding;
// Regression EMVCException.Create-Ueberladungs-Delegation (40+ FPs):
// Constructor Create(args1) ruft Create(args2) auf - das ist Overload-
// Resolution innerhalb der Klasse, kein virtueller Dispatch zur Subklasse.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBase = class'#13#10 +
  '  constructor Create(const A: string); overload; virtual;'#13#10 +
  '  constructor Create(const A: string; B: Integer); overload;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'constructor TBase.Create(const A: string); begin end;'#13#10 +
  'constructor TBase.Create(const A: string; B: Integer);'#13#10 +
  'begin'#13#10 +
  '  Create(A);'#13#10 +  // <- selber Konstruktor, NICHT virtual-call
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkVirtualCallInCtor),
    'Create-Ueberladungs-Delegation darf nicht als virtual-call gemeldet werden');
  finally F.Free; end;
end;

procedure TTestVirtualCallInCtor.CtorCallsOwnConstructor_NoFinding;
// FP-Guard (2026-06-29): das Call-Ziel ist selbst ein Konstruktor
// (delegating-ctor `CreateFrom; begin Create; ... end`). Ein virtueller
// Konstruktor-Aufruf konstruiert VOLLSTAENDIG -> kein half-init-Self.
// Der gerufene Create ist virtual -> landet in VirtualByName; IsConstructor
// (VMethod) -> Continue. Wichtig: der rufende Ctor (CreateFrom) hat einen
// anderen Namen als der gerufene (Create), sonst greift der Selbst-Skip.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBase = class'#13#10 +
  '  constructor Create; virtual;'#13#10 +
  '  constructor CreateFrom;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'constructor TBase.Create; begin end;'#13#10 +
  'constructor TBase.CreateFrom;'#13#10 +
  'begin'#13#10 +
  '  Create;'#13#10 +  // <- virtueller Ctor-Aufruf, konstruiert vollstaendig
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkVirtualCallInCtor),
    'Aufruf eines virtuellen KONSTRUKTORS aus einem Ctor ist kein half-init');
  finally F.Free; end;
end;

procedure TTestVirtualCallInCtor.CtorCallsVirtualProc_StillReported;
// Gegenprobe: ruft der Ctor eine virtuelle PROZEDUR (kein Konstruktor),
// bleibt es der klassische Anti-Pattern -> Treffer.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBase = class'#13#10 +
  '  constructor Create;'#13#10 +
  '  procedure SetupStuff; virtual;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'constructor TBase.Create;'#13#10 +
  'begin'#13#10 +
  '  SetupStuff;'#13#10 +
  'end;'#13#10 +
  'procedure TBase.SetupStuff; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkVirtualCallInCtor) >= 1,
    'Virtuelle PROZEDUR aus dem Ctor bleibt ein Treffer');
  finally F.Free; end;
end;

procedure TTestVirtualCallInCtor.VCall_Finding_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBase = class'#13#10 +
  '  constructor Create;'#13#10 +
  '  procedure Init; virtual;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'constructor TBase.Create; begin Init; end;'#13#10 +
  'procedure TBase.Init; begin end;'#13#10 +
  'end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkVirtualCallInCtor then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkVirtualCallInCtor finding expected');
    Assert.AreEqual(fkVirtualCallInCtor, Hit.Kind);
    Assert.AreEqual(lsError,             Hit.Severity);
  finally F.Free; end;
end;

// ---------------------------------------------------------------------------
// FP-Gate 2026-07-31 (30%-Real-World-Audit sca-rw-after119)
// Belege: JvPageListTreeView.pas:1614 und JvThread.pas:409 -
// 'inherited OnXxx := Handler;' ist eine Methodenzeiger-ZUWEISUNG. Der Parser
// zerlegt sie in nkInherited + Phantom-nkCall auf den RHS-Bezeichner, und der
// Reachability-Walk hielt das Phantom fuer eine Call-Kante aus dem Ctor.
// ---------------------------------------------------------------------------

procedure TTestVirtualCallInCtor.InheritedEventAssign_NoFinding;
// Direkt-Treffer-Pfad: der zugewiesene Handler ist selbst virtual.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBase = class(TTreeView)'#13#10 +
  '  constructor Create(AOwner: TComponent);'#13#10 +
  '  procedure DoGetSelectedIndex(Sender: TObject); virtual;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'constructor TBase.Create(AOwner: TComponent);'#13#10 +
  'begin'#13#10 +
  '  inherited OnGetSelectedIndex := DoGetSelectedIndex;'#13#10 +
  'end;'#13#10 +
  'procedure TBase.DoGetSelectedIndex(Sender: TObject); begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := FindingsOfRealFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkVirtualCallInCtor),
    'Event-Zuweisung ist kein Aufruf aus dem Ctor');
  finally F.Free; end;
end;

procedure TTestVirtualCallInCtor.InheritedEventAssign_HelperChain_NoFinding;
// Helper-Chain-Pfad (JvThread.pas:409): der Handler ist nicht virtual, ruft
// aber eine virtuelle Methode - er laeuft trotzdem erst beim Event-Feuern.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBase = class(TForm)'#13#10 +
  '  constructor CreateNew(AOwner: TComponent);'#13#10 +
  '  procedure ReplaceFormShow(Sender: TObject);'#13#10 +
  '  procedure CreateFormControls; virtual;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'constructor TBase.CreateNew(AOwner: TComponent);'#13#10 +
  'begin'#13#10 +
  '  inherited OnShow := ReplaceFormShow;'#13#10 +
  'end;'#13#10 +
  'procedure TBase.ReplaceFormShow(Sender: TObject);'#13#10 +
  'begin'#13#10 +
  '  CreateFormControls;'#13#10 +
  'end;'#13#10 +
  'procedure TBase.CreateFormControls; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := FindingsOfRealFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkVirtualCallInCtor));
  finally F.Free; end;
end;

procedure TTestVirtualCallInCtor.InheritedCreateThenVirtual_SameLine_StillReported;
// Gegenprobe: 'inherited Create; Init;' auf EINER Zeile hat kein ':=' - der
// Gate darf hier NICHT greifen (Praezision vor Masse: 626 Error-Funde).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBase = class'#13#10 +
  '  constructor Create;'#13#10 +
  '  procedure Init; virtual;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'constructor TBase.Create;'#13#10 +
  'begin'#13#10 +
  '  inherited Create; Init;'#13#10 +   // Zeile beginnt mit 'inherited', aber ohne ':='
  'end;'#13#10 +
  'procedure TBase.Init; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := FindingsOfRealFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkVirtualCallInCtor),
    'Aufruf nach inherited Create auf einer Zeile bleibt ein Treffer');
  finally F.Free; end;
end;

procedure TTestVirtualCallInCtor.InheritedCreateThenVirtual_OwnLines_StillReported;
// Gegenprobe: der klassische TP-Fall im Datei-Harness (der Gate darf den
// Normalpfad nicht beruehren).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBase = class'#13#10 +
  '  constructor Create;'#13#10 +
  '  procedure Init; virtual;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'constructor TBase.Create;'#13#10 +
  'begin'#13#10 +
  '  inherited Create;'#13#10 +
  '  Init;'#13#10 +
  'end;'#13#10 +
  'procedure TBase.Init; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := FindingsOfRealFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkVirtualCallInCtor));
  finally F.Free; end;
end;

procedure TTestVirtualCallInCtor.InheritedEventAssignInComment_StillReported;
// Gegenprobe fuer StripCodeLine (Review 2026-07-31: der frueheren Fassung
// '  inherited Create; Init; // OnShow := Init' fehlte die Scharfstellung -
// die ROHzeile matchte das Gate-Muster gar nicht, der Test war vakuum-gruen).
//
// Jetzt scharf: die ROHzeile 11 beginnt mit 'inherited OnShow := Init;' und
// wuerde ohne StripCodeLine als Event-Zuweisung gelten - der zugewiesene
// RHS-Bezeichner 'Init' ist derselbe wie der echte Aufruf hinter dem '}',
// also wuerde der Gate den TP stillstellen (Erwartung 1 -> Ist 0 = ROT).
// Nur weil StripCodeLine den in Zeile 10 geoeffneten Block-Kommentar ueber
// die Zeilengrenze mitfuehrt (InBrace), bleibt gestrippt ' Init;' uebrig und
// der echte Treffer wird gemeldet.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBase = class'#13#10 +
  '  constructor Create;'#13#10 +
  '  procedure Init; virtual;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'constructor TBase.Create;'#13#10 +
  'begin'#13#10 +
  '  { alter Code:'#13#10 +
  '  inherited OnShow := Init; } Init;'#13#10 +
  'end;'#13#10 +
  'procedure TBase.Init; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := FindingsOfRealFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkVirtualCallInCtor),
    'auskommentierte Event-Zuweisung darf den echten Aufruf nicht gaten');
  finally F.Free; end;
end;

// ---------------------------------------------------------------------------
// Praezisierung des Gates (Review 2026-07-31, Fund uVirtualCallInCtor.pas:426):
// das Gate darf NUR den zugewiesenen Handler verwerfen, nicht die ganze Zeile.
// ---------------------------------------------------------------------------

procedure TTestVirtualCallInCtor.InheritedAssign_RhsCallWithArgs_StillReported;
// RHS MIT Argumentliste ist ein echter Aufruf, kein Methodenzeiger. Mit dem
// alten zeilenbasierten Gate war das ein TP-Verlust.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBase = class'#13#10 +
  '  constructor Create;'#13#10 +
  '  function ComputeIt(Sender: TObject): string; virtual;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'constructor TBase.Create;'#13#10 +
  'begin'#13#10 +
  '  inherited Caption := ComputeIt(Self);'#13#10 +
  'end;'#13#10 +
  'function TBase.ComputeIt(Sender: TObject): string; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := FindingsOfRealFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkVirtualCallInCtor),
    'RHS mit Klammern ist ein echter Aufruf und bleibt ein Treffer');
  finally F.Free; end;
end;

procedure TTestVirtualCallInCtor.InheritedEventAssign_TrailingCall_StillReported;
// Eine Zeile, zwei Knoten: der zugewiesene Handler (Foo, virtual) faellt weg,
// der nachgestellte echte Aufruf (Init, virtual) bleibt. Mit dem alten
// zeilenbasierten Gate lieferte diese Eingabe 0 statt 1.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBase = class(TForm)'#13#10 +
  '  constructor Create(AOwner: TComponent);'#13#10 +
  '  procedure Foo(Sender: TObject); virtual;'#13#10 +
  '  procedure Init; virtual;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'constructor TBase.Create(AOwner: TComponent);'#13#10 +
  'begin'#13#10 +
  '  inherited OnShow := Foo; Init;'#13#10 +
  'end;'#13#10 +
  'procedure TBase.Foo(Sender: TObject); begin end;'#13#10 +
  'procedure TBase.Init; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := FindingsOfRealFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkVirtualCallInCtor),
    'nur der zugewiesene Handler wird verworfen, Init bleibt ein Treffer');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestVirtualCallInCtor);

end.
