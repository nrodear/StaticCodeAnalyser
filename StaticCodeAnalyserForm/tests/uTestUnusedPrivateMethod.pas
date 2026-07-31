unit uTestUnusedPrivateMethod;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestUnusedPrivateMethod = class
  public
    [Test] procedure UnusedPrivate_Reported;
    [Test] procedure UsedPrivate_NotReported;
    [Test] procedure PublicMethod_NotReported;
    [Test] procedure Finding_KindAndSeverity;
    // 2026-06-20: DFM-Event-Handler in private-Section nicht als FP melden.
    [Test] procedure DfmBoundPrivateHandler_NotReported;
    // 2026-07-04: Strip-Konsolidierung (lokale Kopie -> TDetectorUtils).
    // Nagelt die Ist-Semantik fest: Vorkommen in //-Kommentar, Block-
    // Kommentar (mit Quote drin), String-Literal und {$IFDEF}-Direktive
    // zaehlen NICHT als Verwendung.
    [Test] procedure StripSemantics_CommentAndStringUsesDontCount;
    // 2026-07-04: `//` INNERHALB eines String-Literals (inkl. verdoppeltem
    // Quote) darf die Zeile nicht abschneiden - der echte Call dahinter
    // muss weiterhin als Verwendung zaehlen.
    [Test] procedure StripSemantics_CallAfterUrlString_NotReported;

    // ---- Referenz-Sichtbarkeits-Gates (30%-Audit 2026-07-31) -------------
    // Je FP-Klasse ein Test plus eine TP-Gegenprobe im GLEICHEN Source,
    // damit ein zu breites Gate sofort auffliegt.
    // GATE A - message-Direktive (VCL-Dispatch), 84% der Korpusfunde.
    [Test] procedure MessageHandler_NotReported;
    // Gegenprobe zum Tiefen-Test: Parameter heisst 'Message', aber es gibt
    // KEINE Direktive -> muss weiter gemeldet werden. Ohne die Pruefung auf
    // Klammertiefe 0 waere dieser Test rot.
    [Test] procedure MessageNamedParamWithoutDirective_StillReported;
    // GATE B - Method-Resolution-Clause 'IFace.Name = Impl;'.
    [Test] procedure MethodResolutionClause_NotReported;
    // GATE C - class constructor / class destructor (RTL-Aufruf).
    // ERSTES Member der Section: uParser2 verschluckt dort den ';class'-
    // Marker, das Gate haengt am Quell-Anker.
    [Test] procedure ClassDestructor_NotReported;
    // Gegenstueck: NICHT erstes Member - hier traegt der TypeRef den
    // ';class'-Marker. Beide Pfade bleiben so einzeln festgenagelt (die
    // Korpus-Realitaet ist ausnahmslos diese Variante).
    [Test] procedure ClassCtorDtor_NotFirstMember_NotReported;
    // GATE D - override (VMT-Dispatch aus dem Vorfahren); 'virtual' allein
    // wird bewusst NICHT gegated.
    [Test] procedure OverrideMethod_NotReported_VirtualStillReported;
    // GATE E - Klasse implementiert ein Interface, das nicht in dieser Unit
    // deklariert ist: ganze Klasse still, Nachbarklasse ohne Interface nicht.
    [Test] procedure ForeignInterfaceClass_Blanket_NotReported;
    // GATE E - Interface LOKAL deklariert: nur namensgleiche Member werden
    // still, echte tote Helfer derselben Klasse bleiben Funde.
    [Test] procedure LocalInterface_OnlyMembersSilenced;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uAstNode, uParser2,
  uUnusedPrivateMethod,
  uTestFindingHelper;

procedure TTestUnusedPrivateMethod.UnusedPrivate_Reported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    procedure UnusedHelper;'#13#10 +
  '  public'#13#10 +
  '    procedure DoStuff;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.UnusedHelper;'#13#10 +
  'begin end;'#13#10 +
  'procedure TFoo.DoStuff;'#13#10 +
  'begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkUnusedPrivateMethod) >= 1);
  finally F.Free; end;
end;

procedure TTestUnusedPrivateMethod.UsedPrivate_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    procedure UsedHelper;'#13#10 +
  '  public'#13#10 +
  '    procedure DoStuff;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.UsedHelper;'#13#10 +
  'begin end;'#13#10 +
  'procedure TFoo.DoStuff;'#13#10 +
  'begin UsedHelper; end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedPrivateMethod));
  finally F.Free; end;
end;

procedure TTestUnusedPrivateMethod.PublicMethod_NotReported;
// Public-Methoden werden NICHT von diesem Detector geprueft - die koennen
// von anderen Units verwendet werden.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    procedure PublicMaybeUnused;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.PublicMaybeUnused;'#13#10 +
  'begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedPrivateMethod));
  finally F.Free; end;
end;

procedure TTestUnusedPrivateMethod.Finding_KindAndSeverity;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    procedure Dead;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Dead;'#13#10 +
  'begin end;'#13#10 +
  'end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkUnusedPrivateMethod then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkUnusedPrivateMethod finding expected');
    Assert.AreEqual(lsHint, Hit.Severity);
  finally F.Free; end;
end;

procedure TTestUnusedPrivateMethod.DfmBoundPrivateHandler_NotReported;
// Private Methode Button1Click ist Event-Handler im DFM (OnClick = Button1Click).
// Im Pascal-Code wird sie nirgends explizit aufgerufen - klassisches FP-Szenario
// vor dem DFM-Scan-Fix (siehe uUnusedPrivateMethod). Muss jetzt sauber ignoriert
// werden.
const PAS_SRC =
  'unit t; interface'#13#10 +
  'uses Classes, Controls, StdCtrls, Forms;'#13#10 +
  'type'#13#10 +
  '  TFooForm = class(TForm)'#13#10 +
  '    Button1: TButton;'#13#10 +
  '  private'#13#10 +
  '    procedure Button1Click(Sender: TObject);'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  '{$R *.dfm}'#13#10 +
  'procedure TFooForm.Button1Click(Sender: TObject);'#13#10 +
  'begin end;'#13#10 +
  'end.';
const DFM_SRC =
  'object FooForm: TFooForm'#13#10 +
  '  Caption = ''Foo'''#13#10 +
  '  object Button1: TButton'#13#10 +
  '    OnClick = Button1Click'#13#10 +
  '  end'#13#10 +
  'end';
var
  Dir, PasPath, DfmPath : string;
  Parser  : TParser2;
  Root    : TAstNode;
  F       : TObjectList<TLeakFinding>;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'sca_dfmtest_' +
    TGuid.NewGuid.ToString.Replace('{','').Replace('}','').Replace('-',''));
  TDirectory.CreateDirectory(Dir);
  try
    PasPath := TPath.Combine(Dir, 'fooform.pas');
    DfmPath := TPath.Combine(Dir, 'fooform.dfm');
    TFile.WriteAllText(PasPath, PAS_SRC, TEncoding.UTF8);
    TFile.WriteAllText(DfmPath, DFM_SRC, TEncoding.UTF8);

    F := TObjectList<TLeakFinding>.Create(True);
    Parser := TParser2.Create;
    try
      Root := Parser.ParseSource(PAS_SRC);
      try
        TUnusedPrivateMethodDetector.AnalyzeUnit(Root, PasPath, F);
      finally
        Root.Free;
      end;
      Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedPrivateMethod),
        'DFM-bound Button1Click darf nicht als unused gemeldet werden');
    finally
      Parser.Free;
      F.Free;
    end;
  finally
    try TDirectory.Delete(Dir, True); except end;
  end;
end;

procedure TTestUnusedPrivateMethod.StripSemantics_CommentAndStringUsesDontCount;
// DeadHelper taucht im Roh-Text 6x auf: Deklaration, Impl-Header,
// //-Kommentar (mit 'Quote'), Block-Kommentar (mit 'Quote), String-Literal,
// {$IFDEF}-Direktive. Nur Deklaration + Impl-Header ueberleben das Strippen
// -> Count 2 (nicht > 2) -> MUSS gemeldet werden. Wuerde irgendeine der
// vier gestrippten Fundstellen faelschlich mitzaehlen, kippte der Test.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    procedure DeadHelper;'#13#10 +
  '  public'#13#10 +
  '    procedure DoStuff;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  '{$IFDEF DEADHELPER}'#13#10 +
  '{$ENDIF}'#13#10 +
  'procedure TFoo.DeadHelper;'#13#10 +
  'begin end;'#13#10 +
  'procedure TFoo.DoStuff;'#13#10 +
  '// DeadHelper wird nicht mehr gerufen (''legacy'')'#13#10 +
  'begin'#13#10 +
  '  Writeln(''call DeadHelper now'');'#13#10 +
  '  { DeadHelper im Block-Kommentar mit ''Quote }'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkUnusedPrivateMethod) >= 1,
    'Kommentar-/String-/Direktiven-Vorkommen duerfen nicht als Use zaehlen');
  finally F.Free; end;
end;

procedure TTestUnusedPrivateMethod.StripSemantics_CallAfterUrlString_NotReported;
// Der String ''don''t // stop'' enthaelt ein verdoppeltes Quote UND `//`.
// Wuerde der Stripper das `//` im String als Zeilenkommentar deuten, fiele
// der echte Call `UsedHelper;` dahinter weg -> Count 2 -> False Positive.
// Korrekte Semantik: Call zaehlt, Count 3 (> 2) -> KEIN Fund.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    procedure UsedHelper;'#13#10 +
  '  public'#13#10 +
  '    procedure DoStuff;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.UsedHelper;'#13#10 +
  'begin end;'#13#10 +
  'procedure TFoo.DoStuff;'#13#10 +
  'begin'#13#10 +
  '  Writeln(''don''''t // stop''); UsedHelper;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedPrivateMethod),
    '`//` im String-Literal darf den echten Call dahinter nicht abschneiden');
  finally F.Free; end;
end;

// ---------------------------------------------------------------------------
// Zaehlt fkUnusedPrivateMethod-Funde fuer EINEN Methodennamen. Die Gate-Tests
// pruefen immer beide Richtungen im selben Source (gegatete Methode = 0,
// TP-Gegenprobe = 1); ein reines Count(F, Kind) koennte das nicht trennen.
function CountForMethod(F: TObjectList<TLeakFinding>;
  const AMethodName: string): Integer;
var
  Fnd : TLeakFinding;
begin
  Result := 0;
  for Fnd in F do
    if (Fnd.Kind = fkUnusedPrivateMethod) and
       SameText(Fnd.MethodName, AMethodName) then
      Inc(Result);
end;

procedure TTestUnusedPrivateMethod.MessageHandler_NotReported;
// WMPaint kommt im Text genau 2x vor (Deklaration + Impl-Header) und waere
// ohne Gate A ein Fund. Die 'message'-Direktive macht sie zum VCL-
// Dispatch-Ziel - kein toter Code. DeadHelper daneben MUSS Fund bleiben.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    procedure WMPaint(var Message: TWMPaint); message WM_PAINT;'#13#10 +
  '    procedure DeadHelper;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.WMPaint(var Message: TWMPaint);'#13#10 +
  'begin end;'#13#10 +
  'procedure TFoo.DeadHelper;'#13#10 +
  'begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0, CountForMethod(F, 'WMPaint'),
      'message-Handler wird vom VCL-Dispatch gerufen - kein Unused-Fund');
    Assert.AreEqual<Integer>(1, CountForMethod(F, 'DeadHelper'),
      'echter toter Helfer derselben Klasse muss Fund bleiben');
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedPrivateMethod),
      'genau ein Fund insgesamt - sonst hat das Gate zu wenig/zu viel getan');
  finally F.Free; end;
end;

procedure TTestUnusedPrivateMethod.MessageNamedParamWithoutDirective_StillReported;
// Mechanismus-Gegenprobe zu Gate A: der Parameter heisst 'Message' (VCL-
// Konvention), eine Direktive gibt es aber nicht. Wuerde der Scan das Wort
// 'message' ohne Klammertiefen-Test suchen, waere hier faelschlich 0.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    procedure HandleIt(var Message: TWMPaint);'#13#10 +
  '  public'#13#10 +
  '    procedure DoStuff;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.HandleIt(var Message: TWMPaint);'#13#10 +
  'begin end;'#13#10 +
  'procedure TFoo.DoStuff;'#13#10 +
  'begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, CountForMethod(F, 'HandleIt'),
      'ohne message-Direktive bleibt es ein Fund - Parametername zaehlt nicht');
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedPrivateMethod));
  finally F.Free; end;
end;

procedure TTestUnusedPrivateMethod.MethodResolutionClause_NotReported;
// 'function ISearchCommands.CanFindPrev = CanFindNext;' deklariert KEINE
// Methode CanFindPrev - der Parser legt trotzdem einen nkMethod-Knoten mit
// qualifiziertem Namen an. Die Klasse hat bewusst KEINE Elternliste, damit
// nur Gate B den Fund unterdruecken kann (sonst waere der Test vakuum-gruen).
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    function ISearchCommands.CanFindPrev = CanFindNext;'#13#10 +
  '    function CanFindNext: Boolean;'#13#10 +
  '    procedure DeadOne;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'function TFoo.CanFindNext: Boolean;'#13#10 +
  'begin Result := False; end;'#13#10 +
  'procedure TFoo.DeadOne;'#13#10 +
  'begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0, CountForMethod(F, 'ISearchCommands.CanFindPrev'),
      'Resolution-Clause ist keine Methode - darf nicht als unused gelten');
    Assert.AreEqual<Integer>(1, CountForMethod(F, 'DeadOne'),
      'die Klasse darf nicht pauschal stillgeschaltet werden');
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedPrivateMethod),
      'nur DeadOne - der Clause-Knoten darf keinen zweiten Fund erzeugen');
  finally F.Free; end;
end;

procedure TTestUnusedPrivateMethod.ClassDestructor_NotReported;
// class destructor wird von der RTL beim Unit-Finalize gerufen, nie
// namentlich. Ein GEWOEHNLICHER privater Constructor bleibt dagegen Fund.
//
// ACHTUNG - dieser Source trifft die Parser-Luecke: 'class' steht direkt
// hinter 'private', also fehlt der ';class'-Marker im TypeRef (uParser2
// Eat(tkKwClass) im Visibility-Zweig). Gate C greift hier ueber den
// Quell-Anker Sca147DeclIsClassPrefixed, nicht ueber den TypeRef.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    class destructor DestroyClass;'#13#10 +
  '    constructor CreatePlain;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'class destructor TFoo.DestroyClass;'#13#10 +
  'begin end;'#13#10 +
  'constructor TFoo.CreatePlain;'#13#10 +
  'begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0, CountForMethod(F, 'DestroyClass'),
      'class destructor wird von der RTL gerufen - kein Unused-Fund');
    Assert.AreEqual<Integer>(1, CountForMethod(F, 'CreatePlain'),
      'gewoehnlicher privater Constructor bleibt Fund');
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedPrivateMethod));
  finally F.Free; end;
end;

procedure TTestUnusedPrivateMethod.ClassCtorDtor_NotFirstMember_NotReported;
// Korpus-Form (Alcinoe.FMX.NativeView.Win, Kastri DW.Toast.Android,
// MVCFramework.Rtti.Utils): vor dem class destructor steht noch eine
// 'class var'-Zeile, damit laeuft der Parser durch seinen tkKwClass-Zweig
// und der TypeRef traegt ';class'. Nagelt den TypeRef-Pfad von Gate C
// getrennt vom Quell-Anker fest.
//
// 'class procedure DoIt' ist die Gegenprobe: eine gewoehnliche private
// Klassenmethode wird von niemandem automatisch gerufen und MUSS Fund
// bleiben - egal ueber welchen Pfad Gate C laeuft.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    class var FCache: Integer;'#13#10 +
  '    class destructor DestroyClass;'#13#10 +
  '    class constructor CreateClass;'#13#10 +
  '    class procedure DoIt;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'class destructor TFoo.DestroyClass;'#13#10 +
  'begin end;'#13#10 +
  'class constructor TFoo.CreateClass;'#13#10 +
  'begin end;'#13#10 +
  'class procedure TFoo.DoIt;'#13#10 +
  'begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0, CountForMethod(F, 'DestroyClass'),
      'class destructor mit ;class-Marker - kein Unused-Fund');
    Assert.AreEqual<Integer>(0, CountForMethod(F, 'CreateClass'),
      'class constructor mit ;class-Marker - kein Unused-Fund');
    Assert.AreEqual<Integer>(1, CountForMethod(F, 'DoIt'),
      'gewoehnliche private class procedure bleibt Fund');
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedPrivateMethod));
  finally F.Free; end;
end;

procedure TTestUnusedPrivateMethod.OverrideMethod_NotReported_VirtualStillReported;
// Die Basisklasse steht ABSICHTLICH in einer anderen Unit: waere sie hier
// deklariert, kaeme der Name auf > 2 Textvorkommen und der Kandidat fiele
// schon vor den Gates raus (vakuum-gruener Test).
const SRC =
  'unit t; interface'#13#10 +
  'uses uBase;'#13#10 +
  'type'#13#10 +
  '  TFoo = class(TSomeBase)'#13#10 +
  '  private'#13#10 +
  '    procedure DataScrolled; override;'#13#10 +
  '    procedure NewHook; virtual;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.DataScrolled;'#13#10 +
  'begin end;'#13#10 +
  'procedure TFoo.NewHook;'#13#10 +
  'begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0, CountForMethod(F, 'DataScrolled'),
      'override wird per VMT aus dem Vorfahren gerufen');
    Assert.AreEqual<Integer>(1, CountForMethod(F, 'NewHook'),
      'virtual ohne override bleibt bewusst ein Fund');
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedPrivateMethod));
  finally F.Free; end;
end;

procedure TTestUnusedPrivateMethod.ForeignInterfaceClass_Blanket_NotReported;
// IFremd ist in dieser Unit NICHT deklariert -> der Detektor kann nicht
// wissen, welche private Methode das Interface bedient, und schaltet die
// Klasse komplett still. TBar (ohne Interface) bleibt unberuehrt - das
// trennt das Gate von einem globalen Schalter.
const SRC =
  'unit t; interface'#13#10 +
  'uses uFremd;'#13#10 +
  'type'#13#10 +
  '  TFoo = class(TInterfacedObject, IFremd)'#13#10 +
  '  private'#13#10 +
  '    procedure Alpha;'#13#10 +
  '  end;'#13#10 +
  '  TBar = class(TObject)'#13#10 +
  '  private'#13#10 +
  '    procedure Beta;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Alpha;'#13#10 +
  'begin end;'#13#10 +
  'procedure TBar.Beta;'#13#10 +
  'begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0, CountForMethod(F, 'Alpha'),
      'Klasse mit fremdem Interface: Aufruf laeuft ueber Interface-Dispatch');
    Assert.AreEqual<Integer>(1, CountForMethod(F, 'Beta'),
      'Klasse ohne Interface in der Elternliste bleibt voll geprueft');
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedPrivateMethod));
  finally F.Free; end;
end;

procedure TTestUnusedPrivateMethod.LocalInterface_OnlyMembersSilenced;
// IRunnable ist LOKAL deklariert und damit aufloesbar: nur 'Run' (Member)
// wird still, 'DeadHelper' derselben Klasse bleibt Fund. Run hat bewusst
// keine Implementierung, sonst waere es mit 3 Textvorkommen gar kein
// Kandidat mehr und der Test wuerde nichts pruefen.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  IRunnable = interface'#13#10 +
  '    procedure Run;'#13#10 +
  '  end;'#13#10 +
  '  TFoo = class(TInterfacedObject, IRunnable)'#13#10 +
  '  private'#13#10 +
  '    procedure Run;'#13#10 +
  '    procedure DeadHelper;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.DeadHelper;'#13#10 +
  'begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0, CountForMethod(F, 'Run'),
      'Run ist Member des lokal aufloesbaren IRunnable');
    Assert.AreEqual<Integer>(1, CountForMethod(F, 'DeadHelper'),
      'kein Interface-Member -> bleibt Fund (kein Blanket bei lokalem Interface)');
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedPrivateMethod));
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUnusedPrivateMethod);

end.
