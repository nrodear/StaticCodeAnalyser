unit uTestGodClass;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestGodClass = class
  public
    [Test] procedure ManyMethods_Reported;
    [Test] procedure ManyFields_Reported;
    [Test] procedure SmallClass_NotReported;
    [Test] procedure AbstractClass_NotReported;
    [Test] procedure Finding_KindAndSeverity;
    // --- Real-World FP-Audit 2026-07-10 Regression (Welle 1+2) ---
    [Test] procedure EmptyExceptionClassDecl_NotReported;
    [Test] procedure FormWithManyControls_Reported;
    // --- FFI-/Typelib-Gate (Backlog 4e-3, 30%-Audit 2026-07-31) ---
    [Test] procedure JniBridgeInterface_NotReported;
    [Test] procedure ObjCProtocolDelegateClass_NotReported;
    [Test] procedure GenericImportArgument_NotReported;
    [Test] procedure MixedUnit_OnlyAppClassReported;
    [Test] procedure TypelibFile_NotReported;
    [Test] procedure NonTypelibFile_Gegenprobe_Reported;
    // --- Phantom-nkField-Fixes (Parser, 2026-09-05) ---
    // Der Feld-Zaehler zaehlte geleakte Direktiven-Token als Felder
    // (message/dynamic/default/cdecl) und splittete prozedurale
    // Feldtypen an ihren Param-Semikola. Fixtures = Exe-Proben.
    [Test] procedure MessageHandlerDirective_NotCountedAsFields;
    [Test] procedure ProcTypeFieldParams_NotCountedAsFields;
    [Test] procedure ArrayPropertyDefault_NotCountedAsField;
    [Test] procedure SixteenRealFields_StillReported;
    // --- Feld-ADDS (Charge 10): Komma-Listen + Keyword-Namen ---
    [Test] procedure CommaListFields_CountPerName;
    [Test] procedure KeywordNamedField_Counted;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.IOUtils,
  uAstNode, uParser2, uGodClass,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

// Laeuft NUR SCA138 gegen eine temporaere Datei mit KONTROLLIERTEM
// Basisnamen - der gemeinsame Harness (FindingsOfFile) vergibt einen
// zufaelligen Namen, das *_TLB.pas-Gate ist damit nicht testbar.
// Muster uebernommen aus uTestInterfaceName (SCA105).
function GodClassFindingsForFile(const ASource, ANameSuffix: string)
  : TObjectList<TLeakFinding>;
var
  Parser : TParser2;
  Root   : TAstNode;
  Path   : string;
  SL     : TStringList;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  Path := TPath.Combine(TPath.GetTempPath,
    'sca_god_' + TGuid.NewGuid.ToString.Replace('{', '').Replace('}', '')
      .Replace('-', '') + ANameSuffix);
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    SL.SaveToFile(Path, TEncoding.UTF8);
  finally
    SL.Free;
  end;
  try
    Parser := TParser2.Create;
    try
      Root := Parser.ParseFile(Path);
      try
        TGodClassDetector.AnalyzeUnit(Root, Path, Result);
      finally
        Root.Free;
      end;
    finally
      Parser.Free;
    end;
  finally
    if TFile.Exists(Path) then TFile.Delete(Path);
  end;
end;

procedure TTestGodClass.ManyMethods_Reported;
// 25 Methoden in einer Klasse > MAX_METHODS = 20.
var
  SB : TStringBuilder;
  i  : Integer;
  F  : TObjectList<TLeakFinding>;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit t; interface');
    SB.AppendLine('type');
    SB.AppendLine('  TGod = class');
    for i := 1 to 25 do
      SB.AppendLine(Format('    procedure M%d;', [i]));
    SB.AppendLine('  end;');
    SB.AppendLine('implementation end.');
    F := TFindingHelper.FindingsOf(SB.ToString);
    try Assert.IsTrue(TFindingHelper.Count(F, fkGodClass) >= 1);
    finally F.Free; end;
  finally
    SB.Free;
  end;
end;

procedure TTestGodClass.ManyFields_Reported;
// 20 Felder > MAX_FIELDS = 15.
var
  SB : TStringBuilder;
  i  : Integer;
  F  : TObjectList<TLeakFinding>;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit t; interface');
    SB.AppendLine('type');
    SB.AppendLine('  TFatRecord = class');
    for i := 1 to 20 do
      SB.AppendLine(Format('    F%d: Integer;', [i]));
    SB.AppendLine('  end;');
    SB.AppendLine('implementation end.');
    F := TFindingHelper.FindingsOf(SB.ToString);
    try Assert.IsTrue(TFindingHelper.Count(F, fkGodClass) >= 1);
    finally F.Free; end;
  finally
    SB.Free;
  end;
end;

procedure TTestGodClass.SmallClass_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '    FA: Integer;'#13#10 +
  '    FB: Integer;'#13#10 +
  '    procedure Run;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGodClass));
  finally F.Free; end;
end;

procedure TTestGodClass.AbstractClass_NotReported;
// `class abstract` ist Designintent - selbst mit vielen Methoden kein
// Refactoring-Bedarf.
var
  SB : TStringBuilder;
  i  : Integer;
  F  : TObjectList<TLeakFinding>;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit t; interface');
    SB.AppendLine('type');
    SB.AppendLine('  TFramework = class abstract');
    for i := 1 to 25 do
      SB.AppendLine(Format('    procedure M%d; virtual; abstract;', [i]));
    SB.AppendLine('  end;');
    SB.AppendLine('implementation end.');
    F := TFindingHelper.FindingsOf(SB.ToString);
    try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGodClass));
    finally F.Free; end;
  finally
    SB.Free;
  end;
end;

procedure TTestGodClass.Finding_KindAndSeverity;
var
  SB  : TStringBuilder;
  i   : Integer;
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit t; interface');
    SB.AppendLine('type');
    SB.AppendLine('  TGod = class');
    for i := 1 to 25 do
      SB.AppendLine(Format('    procedure M%d;', [i]));
    SB.AppendLine('  end;');
    SB.AppendLine('implementation end.');
    F := TFindingHelper.FindingsOf(SB.ToString);
    try
      Hit := nil;
      for Fnd in F do
        if Fnd.Kind = fkGodClass then begin Hit := Fnd; Break; end;
      Assert.IsNotNull(Hit, 'fkGodClass finding expected');
      Assert.AreEqual(fkGodClass, Hit.Kind);
      Assert.AreEqual(lsWarning,  Hit.Severity);
    finally F.Free; end;
  finally
    SB.Free;
  end;
end;


// --- Real-World FP-Audit 2026-07-10 Regression (Welle 1+2) ---

procedure TTestGodClass.EmptyExceptionClassDecl_NotReported;
// Real-World FP-Audit 2026-07-10 (Alcinoe ALOpenOffice.pas / Alcinoe.ExprEval.pas):
// `EFoo = class(Exception);` ist eine leere Einzeiler-Deklaration - die Quellzeile
// endet auf ');' und die Klasse hat KEINEN Body. Der Parser kennt fuer `class(...)`
// keinen Semikolon-Abbruch (ParseClassBody schluckt via `else Next` alles bis zum
// naechsten `end`) und zieht die nachfolgenden Unit-Level-Routinen faelschlich als
// Methoden herein -> absurder God-Class-Count (real EALOpenOfficeException 22m).
// IsEmptyClassDeclLine (Fix ef3608e) erkennt die `);'-Zeile und unterdrueckt den
// reinen Parser-Slurp-Artefakt-Fund. Kein Bug: 0 echte Member.
// MUSS ueber FindingsOfFile laufen - der Guard liest die Quellzeile per AcquireLines
// (im AST-only-Harness FindingsOf ist Lines=nil und der Guard feuert nie).
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  EFoo = class(Exception);'#13#10 +
  '  procedure P01;'#13#10 +
  '  procedure P02;'#13#10 +
  '  procedure P03;'#13#10 +
  '  procedure P04;'#13#10 +
  '  procedure P05;'#13#10 +
  '  procedure P06;'#13#10 +
  '  procedure P07;'#13#10 +
  '  procedure P08;'#13#10 +
  '  procedure P09;'#13#10 +
  '  procedure P10;'#13#10 +
  '  procedure P11;'#13#10 +
  '  procedure P12;'#13#10 +
  '  procedure P13;'#13#10 +
  '  procedure P14;'#13#10 +
  '  procedure P15;'#13#10 +
  '  procedure P16;'#13#10 +
  '  procedure P17;'#13#10 +
  '  procedure P18;'#13#10 +
  '  procedure P19;'#13#10 +
  '  procedure P20;'#13#10 +
  '  procedure P21;'#13#10 +
  '  procedure P22;'#13#10 +
  '  procedure P23;'#13#10 +
  '  procedure P24;'#13#10 +
  '  procedure P25;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGodClass),
    'leere class(...);-Einzeiler-Decl (Parser-Slurp-Artefakt) ist keine God-Klasse');
  finally F.Free; end;
end;

procedure TTestGodClass.FormWithManyControls_Reported;
// Must-stay (Real-World-FP-Audit tp_examples_must_stay, Alcinoe ALButton TForm1):
// Composite-Root-Form mit 17 Control-Feldern (> MAX_FIELDS=15). rule_desc zielt
// explizit auf UI-Composite-Roots. Der Klassenkopf endet auf ')' (nicht ');') und
// der Body ist mehrzeilig mit terminierendem 'end;' -> IsEmptyClassDeclLine greift
// NICHT, der echte God-Class-Fund muss weiter feuern. Direkter Kontrastfall zum
// leeren Einzeiler oben (beweist: der Fix killt nur die `);'-Slurp-Artefakte).
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TBigForm = class(TForm)'#13#10 +
  '    E01: TEdit;'#13#10 +
  '    E02: TEdit;'#13#10 +
  '    E03: TEdit;'#13#10 +
  '    E04: TEdit;'#13#10 +
  '    E05: TEdit;'#13#10 +
  '    E06: TEdit;'#13#10 +
  '    E07: TEdit;'#13#10 +
  '    E08: TEdit;'#13#10 +
  '    E09: TEdit;'#13#10 +
  '    E10: TEdit;'#13#10 +
  '    E11: TEdit;'#13#10 +
  '    E12: TEdit;'#13#10 +
  '    E13: TEdit;'#13#10 +
  '    E14: TEdit;'#13#10 +
  '    E15: TEdit;'#13#10 +
  '    E16: TEdit;'#13#10 +
  '    E17: TEdit;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkGodClass) >= 1,
    'Form mit 17 Control-Feldern (> 15) ist eine God-Klasse und muss weiter melden');
  finally F.Free; end;
end;

{ ---- FFI-/Typelib-Gate (Backlog 4e-3, 30%-Audit 2026-07-31) ----
  Nach dem Parser-Inkrement (92dd5c9/3a3e711) sind die generierten
  ObjC-/JNI-Bridge-Units erstmals vollstaendig lesbar; 432 der 5.051
  SCA138-Korpusfunde liegen seitdem auf Binding-Typen. Alle Tests unten
  waeren OHNE das Gate rot (die Klassen/Interfaces reissen die
  20-Methoden-Schwelle deutlich). }

procedure TTestGodClass.JniBridgeInterface_NotReported;
// Kriterium (1) Anker-Vererbung + transitive Kette: JCameraController erbt
// von JObject (RTL-Bridge-Wurzel), JCameraControllerEx erbt davon. Der
// Member-Satz IST die Java-Klasse - "split into focused units" ist dort
// keine ausfuehrbare Empfehlung (real: DW.Androidapi.JNI.AndroidX.Camera).
var
  SB : TStringBuilder;
  i  : Integer;
  F  : TObjectList<TLeakFinding>;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit t; interface');
    SB.AppendLine('uses Androidapi.JNIBridge;');
    SB.AppendLine('type');
    SB.AppendLine('  JCameraController = interface(JObject)');
    for i := 1 to 25 do
      SB.AppendLine(Format('    procedure setZoom%d; cdecl;', [i]));
    SB.AppendLine('  end;');
    SB.AppendLine('  JCameraControllerEx = interface(JCameraController)');
    for i := 1 to 25 do
      SB.AppendLine(Format('    procedure setTorch%d; cdecl;', [i]));
    SB.AppendLine('  end;');
    SB.AppendLine('implementation');
    SB.AppendLine('end.');
    F := TFindingHelper.FindingsOfFile(SB.ToString);
    try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGodClass),
      'JNI-Bridge-Interfaces (auch transitiv geerbte) sind keine God-Klassen');
    finally F.Free; end;
  finally
    SB.Free;
  end;
end;

procedure TTestGodClass.ObjCProtocolDelegateClass_NotReported;
// Gleiches Kriterium, andere TYPART: eine handgeschriebene Delphi-KLASSE,
// die ueber TOCLocal ein ObjC-Protokoll implementiert. Ihre Methodenliste
// ist vom Protokoll diktiert, nicht vom Entwickler (real: Alcinoe
// TTextViewDelegate, 26 UITextViewDelegate-Callbacks). Der Parser fuehrt
// class und interface beide als nkClass - das Gate muss beide treffen.
var
  SB : TStringBuilder;
  i  : Integer;
  F  : TObjectList<TLeakFinding>;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit t; interface');
    SB.AppendLine('uses Macapi.ObjectiveC;');
    SB.AppendLine('type');
    SB.AppendLine('  TTextViewDelegate = class(TOCLocal, UITextViewDelegate)');
    SB.AppendLine('  public');
    for i := 1 to 25 do
      SB.AppendLine(Format('    procedure textViewDidChange%d; cdecl;', [i]));
    SB.AppendLine('  end;');
    SB.AppendLine('implementation');
    SB.AppendLine('end.');
    F := TFindingHelper.FindingsOfFile(SB.ToString);
    try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGodClass),
      'TOCLocal-Protokoll-Implementierung ist keine God-Klasse');
    finally F.Free; end;
  finally
    SB.Free;
  end;
end;

procedure TTestGodClass.GenericImportArgument_NotReported;
// Kriterium (2) Generic-Import-Argumente: JBarcodeReader erbt von einem
// Typ aus einer FREMDEN Unit (JParcelable), der Anker ist hier also nicht
// erreichbar. Belegt wird der Typ ueber TJavaGenericImport<...>, das ihn
// als Import-Interface benennt. Ohne dieses Kriterium bliebe der Fund.
var
  SB : TStringBuilder;
  i  : Integer;
  F  : TObjectList<TLeakFinding>;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit t; interface');
    SB.AppendLine('uses Androidapi.JNIBridge;');
    SB.AppendLine('type');
    SB.AppendLine('  JBarcodeReader = interface(JParcelable)');
    for i := 1 to 25 do
      SB.AppendLine(Format('    function getSymbology%d: Integer; cdecl;', [i]));
    SB.AppendLine('  end;');
    SB.AppendLine('  TJBarcodeReader = class(TJavaGenericImport<JBarcodeReaderClass, JBarcodeReader>) end;');
    SB.AppendLine('implementation');
    SB.AppendLine('end.');
    F := TFindingHelper.FindingsOfFile(SB.ToString);
    try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGodClass),
      'ueber TJavaGenericImport belegter Bridge-Typ ist keine God-Klasse');
    finally F.Free; end;
  finally
    SB.Free;
  end;
end;

procedure TTestGodClass.MixedUnit_OnlyAppClassReported;
// KERN-GEGENPROBE (Muss-bleiben): das Gate entscheidet am TYP, nicht an
// der Datei. Eine App-Unit, die nebenbei Androidapi.JNI nutzt und einen
// Bridge-Typ deklariert, behaelt ihre eigenen God-Klassen. Real belegt:
// Alcinoe.FMX.Common.pas hat EINEN Bridge-Typ
// (TALFMXViewBaseAccessPrivate) und 14 eigene God-Klassen, die alle
// weitermelden muessen.
var
  SB  : TStringBuilder;
  i   : Integer;
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit t; interface');
    SB.AppendLine('uses Androidapi.JNIBridge;');
    SB.AppendLine('type');
    SB.AppendLine('  JCameraController = interface(JObject)');
    for i := 1 to 25 do
      SB.AppendLine(Format('    procedure setZoom%d; cdecl;', [i]));
    SB.AppendLine('  end;');
    SB.AppendLine('  TBigForm = class(TForm)');
    for i := 1 to 17 do
      SB.AppendLine(Format('    E%d: TEdit;', [i]));
    SB.AppendLine('  end;');
    SB.AppendLine('implementation');
    SB.AppendLine('end.');
    F := TFindingHelper.FindingsOfFile(SB.ToString);
    try
      Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkGodClass),
        'genau die eigene Klasse wird gemeldet, nicht der Bridge-Typ');
      Fnd := TFindingHelper.FirstOf(F, fkGodClass);
      Assert.IsNotNull(Fnd);
      Assert.AreEqual('TBigForm', Fnd.MethodName,
        'gemeldet wird TBigForm, nicht JCameraController');
    finally F.Free; end;
  finally
    SB.Free;
  end;
end;

procedure TTestGodClass.TypelibFile_NotReported;
// Generierte COM-Typelib-Importe: der Importer regeneriert die Datei bei
// jedem Refresh, KEIN Typ darin ist handgeschrieben. Einzige Datei-Regel
// des Gates (alle anderen Entscheidungen fallen am Typ).
var
  SB : TStringBuilder;
  i  : Integer;
  F  : TObjectList<TLeakFinding>;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit t; interface');
    SB.AppendLine('type');
    SB.AppendLine('  TZipItem = class(TAutoObject)');
    for i := 1 to 17 do
      SB.AppendLine(Format('    FProp%d: Integer;', [i]));
    SB.AppendLine('  end;');
    SB.AppendLine('implementation');
    SB.AppendLine('end.');
    F := GodClassFindingsForFile(SB.ToString, '_TLB.pas');
    try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGodClass),
      'in *_TLB.pas ist kein Refactoring umsetzbar - die Datei wird generiert');
    finally F.Free; end;
  finally
    SB.Free;
  end;
end;

procedure TTestGodClass.NonTypelibFile_Gegenprobe_Reported;
// Derselbe Quelltext unter normalem Dateinamen MUSS melden - sonst waere
// der Test oben auch bei einem kaputten Detektor gruen.
var
  SB : TStringBuilder;
  i  : Integer;
  F  : TObjectList<TLeakFinding>;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit t; interface');
    SB.AppendLine('type');
    SB.AppendLine('  TZipItem = class(TAutoObject)');
    for i := 1 to 17 do
      SB.AppendLine(Format('    FProp%d: Integer;', [i]));
    SB.AppendLine('  end;');
    SB.AppendLine('implementation');
    SB.AppendLine('end.');
    F := GodClassFindingsForFile(SB.ToString, '.pas');
    try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkGodClass),
      'ohne Typelib-Namensmuster bleibt der Fund');
    finally F.Free; end;
  finally
    SB.Free;
  end;
end;

procedure TTestGodClass.MessageHandlerDirective_NotCountedAsFields;
// 'message WM_X;' leakte als ZWEI Phantom-nkFields ('message' + Ident)
// in den Klassenrumpf - korpusweit die groesste Phantomklasse (3.450).
// Exe-Probe vor dem Fix: 15 echte Felder + 1 Handler = "16 fields".
const SRC =
  'unit t; interface type'#13#10+
  '  TMsg = class(TObject)'#13#10+
  '  private'#13#10+
  '    F1, F2: Integer;'#13#10+   // seit dem Komma-Fix (Charge 10) zaehlen BEIDE
  '    F3: Integer; F4: Integer; F5: Integer; F6: Integer;'#13#10+
  '    F7: Integer; F8: Integer; F9: Integer; F10: Integer;'#13#10+
  '    F11: Integer; F12: Integer; F13: Integer; F14: Integer;'#13#10+
  '    F15: Integer;'#13#10+
  '    procedure WMFoo(var M: TObject); message 42;'#13#10+
  '    procedure CMBar(var M: TObject); message CM_FONTCHANGED;'#13#10+
  '  end;'#13#10+
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  // 15 echte Felder (F1..F15, Komma-Paar inklusive seit Charge 10) +
  // frueher bis zu 3 message-Phantome haetten die 15er-Schwelle
  // gerissen; ohne Phantome bleibt die Klasse exakt drauf und drunter.
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGodClass),
      'message-Direktiven sind keine Felder');
  finally F.Free; end;
end;

procedure TTestGodClass.ProcTypeFieldParams_NotCountedAsFields;
// Prozeduraler Feldtyp: der Type-Walk stoppte am Param-';', die
// Resttoken (aZwei, cdecl) wurden Phantom-nkFields. Exe-Probe vor dem
// Fix: 15 echte Felder -> "17 fields".
const SRC =
  'unit t; interface type'#13#10+
  '  TProz = class(TObject)'#13#10+
  '  private'#13#10+
  '    F1: Integer; F2: Integer; F3: Integer; F4: Integer;'#13#10+
  '    F5: Integer; F6: Integer; F7: Integer; F8: Integer;'#13#10+
  '    F9: Integer; F10: Integer; F11: Integer; F12: Integer;'#13#10+
  '    F13: Integer; F14: Integer;'#13#10+
  '    FRufer: function(aEins: Integer; aZwei: Pointer): Integer; cdecl;'#13#10+
  '  end;'#13#10+
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGodClass),
      'Params und Conventions eines Feldtyps sind keine Felder');
  finally F.Free; end;
end;

procedure TTestGodClass.ArrayPropertyDefault_NotCountedAsField;
// 'property ...; default;' - das nackte default wurde ein Phantomfeld
// (109 am Korpus). Exe-Probe vor dem Fix: 15 + default = "16 fields".
const SRC =
  'unit t; interface type'#13#10+
  '  TDef = class(TObject)'#13#10+
  '  private'#13#10+
  '    F1: Integer; F2: Integer; F3: Integer; F4: Integer;'#13#10+
  '    F5: Integer; F6: Integer; F7: Integer; F8: Integer;'#13#10+
  '    F9: Integer; F10: Integer; F11: Integer; F12: Integer;'#13#10+
  '    F13: Integer; F14: Integer; F15: Integer;'#13#10+
  '    function GetItem(I: Integer): Integer;'#13#10+
  '  public'#13#10+
  '    property Items[I: Integer]: Integer read GetItem; default;'#13#10+
  '  end;'#13#10+
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGodClass),
      'das Array-Property-default ist kein Feld');
  finally F.Free; end;
end;

procedure TTestGodClass.SixteenRealFields_StillReported;
// GEGENPROBE: 16 ECHTE Felder reissen die Schwelle weiter - die
// Guards verwerfen nur nackte Direktiven-Idents, keine Deklarationen.
const SRC =
  'unit t; interface type'#13#10+
  '  TEcht = class(TObject)'#13#10+
  '  private'#13#10+
  '    F1: Integer; F2: Integer; F3: Integer; F4: Integer;'#13#10+
  '    F5: Integer; F6: Integer; F7: Integer; F8: Integer;'#13#10+
  '    F9: Integer; F10: Integer; F11: Integer; F12: Integer;'#13#10+
  '    F13: Integer; F14: Integer; F15: Integer; F16: Integer;'#13#10+
  '  end;'#13#10+
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkGodClass),
      '16 echte Felder bleiben ein God-Class-Fund');
  finally F.Free; end;
end;

procedure TTestGodClass.CommaListFields_CountPerName;
// Feld-ADDS Teil A: 'a, b: T;' zaehlte frueher NULL Felder - jetzt je
// Name eines. 16 Felder ausschliesslich ueber Komma-Listen: ohne den
// Fix meldet die Klasse nichts (0 gezaehlte Felder), mit ihm ist sie
// God-Class. Korpus: 42 solcher neuen Schwellen-Ueberschreiter.
const SRC =
  'unit t; interface type'#13#10+
  '  TKomma = class(TObject)'#13#10+
  '  private'#13#10+
  '    A1, A2, A3, A4: Integer;'#13#10+
  '    B1, B2, B3, B4: Integer;'#13#10+
  '    C1, C2, C3, C4: Integer;'#13#10+
  '    D1, D2, D3, D4: Integer;'#13#10+
  '  end;'#13#10+
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkGodClass),
      '16 Komma-Felder sind 16 Felder');
  finally F.Free; end;
end;

procedure TTestGodClass.KeywordNamedField_Counted;
// Feld-ADDS Teil B: 'Exit: TAction;' - der Lexer liefert tkKwExit,
// der alte else-Zweig verschluckte das Feld (jvcl JvPlayList-Beleg
// aus der rw66-Auswertung). 15 normale + Exit = 16 -> Fund.
const SRC =
  'unit t; interface type'#13#10+
  '  TKw = class(TObject)'#13#10+
  '  private'#13#10+
  '    F1: Integer; F2: Integer; F3: Integer; F4: Integer;'#13#10+
  '    F5: Integer; F6: Integer; F7: Integer; F8: Integer;'#13#10+
  '    F9: Integer; F10: Integer; F11: Integer; F12: Integer;'#13#10+
  '    F13: Integer; F14: Integer; F15: Integer;'#13#10+
  '    Exit: TObject;'#13#10+
  '  end;'#13#10+
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkGodClass),
      'ein Keyword-benanntes Feld ist ein Feld');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestGodClass);

end.
