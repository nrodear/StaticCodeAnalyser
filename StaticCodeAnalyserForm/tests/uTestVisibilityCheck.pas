unit uTestVisibilityCheck;

// Tests fuer den TVisibilityCheckDetector.
// Single-Unit-MVP - die Cross-Unit-Variante ist im TODO 🅷 als kuenftiges
// Architektur-Increment markiert. Tests fokussieren auf das, was die
// Single-Unit-Heuristik decken kann.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestVisibilityCheck = class
  public
    // ---- Positive Varianten ------------------------------------------------
    [Test] procedure PublicMethod_OnlyOwnCallers_CanBePrivate;
    [Test] procedure PublicMethod_OnlySubclassCallers_CanBeProtected;
    [Test] procedure PublicMethod_NoCallers_UnusedPublicMember;
    [Test] procedure PublicField_OnlyOwn_CanBePrivate;

    // ---- Negative Varianten ------------------------------------------------
    [Test] procedure PublicMethod_OutsideCaller_NoFinding;
    [Test] procedure PublishedMethod_Skipped;
    [Test] procedure FormDescendant_PublicMember_Skipped;
    [Test] procedure Create_AlwaysSkipped;

    // ---- Finding-Inhalt ---------------------------------------------------
    [Test] procedure CanBePrivate_KindAndSeverity;
    [Test] procedure UnusedPublicMember_KindAndSeverity;
    [Test] procedure CanBeProtected_KindAndSeverity;

    // ---- Balance: mehr Coverage fuer untervertretene FindingKinds ---------
    [Test] procedure CanBeProtected_DeepSubclassChain_StillDetected;
    [Test] procedure UnusedPublicMember_OnlyInDeclaringClass_NoCalls;
    [Test] procedure UnusedPublicMember_MultiplePublicMembers_AllReported;
    [Test] procedure UnusedPublicMember_MissingVarMentionsClass;

    // ---- Cross-Unit-Mode (gSymbolRefIndex) --------------------------------
    [TearDown] procedure ResetSymbolIndex;
    [Test] procedure CrossUnit_ExternalCallerFound_NoFinding;
    [Test] procedure CrossUnit_NoExternalCallers_StillReported;
    [Test] procedure CrossUnit_HintTextMentionsQuickFix;

    // ---- Skip-Regeln: Vererbungs-Hooks ------------------------------------
    [Test] procedure Virtual_PublicMethod_NotReported;
    [Test] procedure Abstract_PublicMethod_NotReported;

    // ---- Mehr Member-Arten + Section-Layouts -----------------------------
    [Test] procedure PublicProperty_OnlyOwnAccess_CanBePrivate;
    [Test] procedure MultiplePublicSections_AllAnalyzed;

    // ---- Utility-/Namespace-Klassen ueberspringen -------------------------
    [Test] procedure UtilityClass_OnlyClassFunctions_NotReported;
    [Test] procedure UtilityClass_WithCtor_StillAnalyzed;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uSymbolReferenceIndex,
  uTestFindingHelper;

procedure TTestVisibilityCheck.PublicMethod_OnlyOwnCallers_CanBePrivate;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  public'#13#10 +
  '    procedure Helper;'#13#10 +
  '    procedure Run;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Helper; begin end;'#13#10 +
  'procedure TFoo.Run; begin Helper; end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkCanBePrivate) >= 1);
  finally F.Free; end;
end;

procedure TTestVisibilityCheck.PublicMethod_OnlySubclassCallers_CanBeProtected;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TBase = class'#13#10 +
  '  public'#13#10 +
  '    procedure Hook;'#13#10 +
  '  end;'#13#10 +
  '  TSub = class(TBase)'#13#10 +
  '    procedure Run;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TBase.Hook; begin end;'#13#10 +
  'procedure TSub.Run; begin Hook; end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkCanBeProtected) >= 1);
  finally F.Free; end;
end;

procedure TTestVisibilityCheck.PublicMethod_NoCallers_UnusedPublicMember;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  public'#13#10 +
  '    procedure Orphan;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Orphan; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkUnusedPublicMember) >= 1);
  finally F.Free; end;
end;

procedure TTestVisibilityCheck.PublicField_OnlyOwn_CanBePrivate;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  public'#13#10 +
  '    FCache: Integer;'#13#10 +
  '    procedure Touch;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Touch; begin FCache := 42; end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkCanBePrivate) >= 1);
  finally F.Free; end;
end;

procedure TTestVisibilityCheck.PublicMethod_OutsideCaller_NoFinding;
// Toplevel-Funktion (kein Method-Body einer Klasse) ruft Hook -> public bleibt.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  public'#13#10 +
  '    procedure Hook;'#13#10 +
  '  end;'#13#10 +
  'procedure CallIt;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Hook; begin end;'#13#10 +
  'procedure CallIt; var F: TFoo; begin F.Hook; end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkCanBePrivate));
    Assert.AreEqual(0, TFindingHelper.Count(F, fkCanBeProtected));
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedPublicMember));
  finally F.Free; end;
end;

procedure TTestVisibilityCheck.PublishedMethod_Skipped;
// published-Section ist DFM-/RTTI-API -> nicht analysiert.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  published'#13#10 +
  '    procedure NeverCalled;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.NeverCalled; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkCanBePrivate));
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedPublicMember));
  finally F.Free; end;
end;

procedure TTestVisibilityCheck.FormDescendant_PublicMember_Skipped;
// TForm-Descendant: DFM-Bindung haengt am published-/public-API,
// also komplett ueberspringen.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms;'#13#10 +
  'type TMainForm = class(TForm)'#13#10 +
  '  public'#13#10 +
  '    procedure NeverCalled;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TMainForm.NeverCalled; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkCanBePrivate));
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedPublicMember));
  finally F.Free; end;
end;

procedure TTestVisibilityCheck.Create_AlwaysSkipped;
// Create/Destroy sind per Konvention public - kein Befund.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  public'#13#10 +
  '    constructor Create;'#13#10 +
  '    destructor Destroy; override;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'constructor TFoo.Create; begin end;'#13#10 +
  'destructor TFoo.Destroy; begin inherited; end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkCanBePrivate));
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedPublicMember));
  finally F.Free; end;
end;

procedure TTestVisibilityCheck.CanBePrivate_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  public'#13#10 +
  '    procedure Helper;'#13#10 +
  '    procedure Run;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Helper; begin end;'#13#10 +
  'procedure TFoo.Run; begin Helper; end;'#13#10 +
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
      if Fnd.Kind = fkCanBePrivate then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkCanBePrivate finding expected');
    Assert.AreEqual(lsHint, Hit.Severity);
  finally F.Free; end;
end;

procedure TTestVisibilityCheck.UnusedPublicMember_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  public'#13#10 +
  '    procedure Orphan;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Orphan; begin end;'#13#10 +
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
      if Fnd.Kind = fkUnusedPublicMember then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkUnusedPublicMember finding expected');
    Assert.AreEqual(lsHint, Hit.Severity);
  finally F.Free; end;
end;

procedure TTestVisibilityCheck.CanBeProtected_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TBase = class'#13#10 +
  '  public'#13#10 +
  '    procedure Hook;'#13#10 +
  '  end;'#13#10 +
  '  TSub = class(TBase)'#13#10 +
  '    procedure Run;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TBase.Hook; begin end;'#13#10 +
  'procedure TSub.Run; begin Hook; end;'#13#10 +
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
      if Fnd.Kind = fkCanBeProtected then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkCanBeProtected finding expected');
    Assert.AreEqual(lsHint, Hit.Severity);
  finally F.Free; end;
end;

procedure TTestVisibilityCheck.CanBeProtected_DeepSubclassChain_StillDetected;
// 2-stufige Vererbung (TBase -> TMid -> TLeaf). Hook in TBase wird in
// TLeaf gerufen - der transitive DescendantsOf-Walk muss das finden.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TBase = class'#13#10 +
  '  public'#13#10 +
  '    procedure Hook;'#13#10 +
  '  end;'#13#10 +
  '  TMid = class(TBase) end;'#13#10 +
  '  TLeaf = class(TMid)'#13#10 +
  '    procedure Use;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TBase.Hook; begin end;'#13#10 +
  'procedure TLeaf.Use; begin Hook; end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkCanBeProtected) >= 1,
      'Transitive Subclass-Refs muessen via BFS gefunden werden');
  finally F.Free; end;
end;

procedure TTestVisibilityCheck.UnusedPublicMember_OnlyInDeclaringClass_NoCalls;
// Public Methode wird NIRGENDS gerufen - nicht mal in eigenen Methoden.
// Klassischer Dead-API-Kandidat.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  public'#13#10 +
  '    procedure DeadApi;'#13#10 +
  '    procedure Run;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.DeadApi; begin end;'#13#10 +
  'procedure TFoo.Run; begin end;'#13#10 +     // nutzt DeadApi NICHT
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkUnusedPublicMember) >= 1,
      'Public Methode ohne jeden Call muss als UnusedPublicMember markiert sein');
  finally F.Free; end;
end;

procedure TTestVisibilityCheck.UnusedPublicMember_MultiplePublicMembers_AllReported;
// Drei dead-public-members in einer Klasse -> drei Findings.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  public'#13#10 +
  '    procedure A;'#13#10 +
  '    procedure B;'#13#10 +
  '    procedure C;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.A; begin end;'#13#10 +
  'procedure TFoo.B; begin end;'#13#10 +
  'procedure TFoo.C; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(3, TFindingHelper.Count(F, fkUnusedPublicMember),
      'Drei dead-public-methods -> drei Findings');
  finally F.Free; end;
end;

procedure TTestVisibilityCheck.UnusedPublicMember_MissingVarMentionsClass;
// Die Detail-Message muss den Klassen- und Member-Namen tragen, damit
// der User sofort weiss wo der Treffer sitzt.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TWidget = class'#13#10 +
  '  public'#13#10 +
  '    procedure DeadCallback;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TWidget.DeadCallback; begin end;'#13#10 +
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
      if Fnd.Kind = fkUnusedPublicMember then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit);
    Assert.Contains(Hit.MissingVar, 'TWidget');
    Assert.Contains(Hit.MissingVar, 'DeadCallback');
  finally F.Free; end;
end;

// ---- Cross-Unit / Skip-Regeln ----------------------------------------------

procedure TTestVisibilityCheck.ResetSymbolIndex;
// Wichtig: Cross-Unit-Tests stoppern den globalen gSymbolRefIndex - andere
// Tests duerfen das nicht ueberleben.
begin
  if Assigned(gSymbolRefIndex) then
    FreeAndNil(gSymbolRefIndex);
end;

procedure TTestVisibilityCheck.CrossUnit_ExternalCallerFound_NoFinding;
// Wenn der gSymbolRefIndex weiss, dass ein anderes Unit-File einen
// 'Foo.Helper'-Call macht, darf der Detektor KEIN Befund melden.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  public'#13#10 +
  '    procedure Helper;'#13#10 +
  '    procedure Run;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Helper; begin end;'#13#10 +
  'procedure TFoo.Run; begin Helper; end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  gSymbolRefIndex := TSymbolReferenceIndex.Create;
  // FindingsOf nutzt 'test.pas' als FileName, also muss die Index-Ref auf
  // eine ANDERE Unit zeigen.
  gSymbolRefIndex.AddReference('Helper', 'other.pas');
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkCanBePrivate),
      'Cross-Unit-Caller muss CanBePrivate unterdruecken');
  finally F.Free; end;
end;

procedure TTestVisibilityCheck.CrossUnit_NoExternalCallers_StillReported;
// Index ist gebaut aber leer fuer den Member -> Befund wird weiter
// gemeldet (Single-File-Path bleibt aktiv).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  public'#13#10 +
  '    procedure Helper;'#13#10 +
  '    procedure Run;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Helper; begin end;'#13#10 +
  'procedure TFoo.Run; begin Helper; end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  gSymbolRefIndex := TSymbolReferenceIndex.Create;
  // Eintrag fuer einen anderen Member - 'Helper' wird nicht referenziert
  gSymbolRefIndex.AddReference('SomethingElse', 'other.pas');
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkCanBePrivate) >= 1,
      'Index ohne passenden Eintrag -> Single-File-Pfad triggert weiter');
  finally F.Free; end;
end;

procedure TTestVisibilityCheck.CrossUnit_HintTextMentionsQuickFix;
// Hint-Text soll Quick-Fix-Suggestion enthalten.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  public'#13#10 +
  '    procedure Helper;'#13#10 +
  '    procedure Run;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Helper; begin end;'#13#10 +
  'procedure TFoo.Run; begin Helper; end;'#13#10 +
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
      if Fnd.Kind = fkCanBePrivate then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit);
    Assert.Contains(LowerCase(Hit.MissingVar), 'private',
      'Hint-Text muss das Ziel-Visibility-Level erwaehnen');
    Assert.Contains(LowerCase(Hit.MissingVar), 'quick-fix',
      'Hint-Text muss eine Quick-Fix-Suggestion enthalten');
  finally F.Free; end;
end;

procedure TTestVisibilityCheck.Virtual_PublicMethod_NotReported;
// Virtuelle Methode kann von externer Subklasse genutzt werden -> kein Befund.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  public'#13#10 +
  '    procedure Hook; virtual;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Hook; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkCanBePrivate));
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedPublicMember));
  finally F.Free; end;
end;

procedure TTestVisibilityCheck.PublicProperty_OnlyOwnAccess_CanBePrivate;
// Property im public-Block, nur innerhalb der Klasse gelesen -> Befund.
// Properties sind im AST nkProperty - der Detektor muss sie genauso wie
// Methoden + Felder durchprueffen.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  public'#13#10 +
  '    property Counter: Integer read FCounter write FCounter;'#13#10 +
  '    procedure Touch;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Touch; begin Counter := 1; end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkCanBePrivate) >= 1,
      'Property im public-Block muss in der Visibility-Analyse auftauchen');
  finally F.Free; end;
end;

procedure TTestVisibilityCheck.MultiplePublicSections_AllAnalyzed;
// Eine Klasse darf mehrere public-Sections haben (z.B. nach private
// wieder public). Beide werden vom Detektor analysiert.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  public'#13#10 +
  '    procedure A;'#13#10 +
  '  private'#13#10 +
  '    FX: Integer;'#13#10 +
  '  public'#13#10 +
  '    procedure B;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.A; begin end;'#13#10 +
  'procedure TFoo.B; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    // Beide A und B sind nirgendwo gerufen -> beide muessten als
    // UnusedPublicMember reported sein.
    Assert.AreEqual(2, TFindingHelper.Count(F, fkUnusedPublicMember),
      'Detektor muss alle public-Sections analysieren, nicht nur die erste');
  finally F.Free; end;
end;

procedure TTestVisibilityCheck.Abstract_PublicMethod_NotReported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  public'#13#10 +
  '    procedure Hook; virtual; abstract;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedPublicMember),
      'abstract-Methoden sind Vererbungs-Hooks, kein Dead-API');
  finally F.Free; end;
end;

procedure TTestVisibilityCheck.UtilityClass_OnlyClassFunctions_NotReported;
// Klasse ohne Felder/Properties/Konstruktor und ausschliesslich mit
// class-Methoden ist ein Utility-Container (z.B. TDetectorUtils mit
// lauter class functions). CanBePrivate macht hier semantisch keinen
// Sinn - die Methoden leben davon, dass sie von AUSSEN gerufen werden.
// Wichtig: VisibilityCheck wird nur im AST-Pfad ausgefuehrt, deshalb
// FindingsOf statt FindingsOfFile.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TDetectorUtils = class'#13#10 +
  '  public'#13#10 +
  '    class function IsIdentChar(Ch: Char): Boolean; static;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'class function TDetectorUtils.IsIdentChar(Ch: Char): Boolean;'#13#10 +
  'begin'#13#10 +
  '  Result := True;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkCanBePrivate));
  finally F.Free; end;
end;

procedure TTestVisibilityCheck.UtilityClass_WithCtor_StillAnalyzed;
// Negativ-Probe: sobald die Klasse einen Konstruktor (oder eine
// Instanz-Methode) hat, ist sie KEIN Utility-Container mehr - der Skip
// darf nicht greifen, die normale CanBePrivate-Analyse muss laufen.
// Helper wird nur intern aus Run gerufen, also als CanBePrivate gemeldet.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    constructor Create;'#13#10 +
  '    procedure Helper;'#13#10 +
  '    procedure Run;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'constructor TFoo.Create; begin end;'#13#10 +
  'procedure TFoo.Helper; begin end;'#13#10 +
  'procedure TFoo.Run; begin Helper; end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkCanBePrivate) >= 1);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestVisibilityCheck);

end.
