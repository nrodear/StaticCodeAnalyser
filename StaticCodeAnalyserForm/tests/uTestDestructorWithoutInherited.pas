unit uTestDestructorWithoutInherited;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDestructorWithoutInherited = class
  public
    [Test] procedure DtorWithInherited_NoFinding;
    [Test] procedure DtorWithoutInherited_Reported;
    [Test] procedure RegularProcedure_NoFinding;
    [Test] procedure DtorForwardDecl_NotReported;
    [Test] procedure ClassDestructor_NotReported;
    [Test] procedure ClassDestructor_AfterVarSection_NotReported;
    [Test] procedure DtorWithoutInherited_KindAndSeverity;

    // ---- FP-Gate 2026-07-31: Codegen-Template-Dateien ---------------------
    [Test] procedure CodegenTemplateFile_NotReported;
    [Test] procedure CodegenTemplateInClassName_NotReported;
    [Test] procedure CharLiteralComparison_StillReported;
    [Test] procedure PlaceholderInStringLiteral_StillReported;
    [Test] procedure PlaceholderInComment_StillReported;
    // TObject-Basis (Kundenkorpus SVGIconImageList, 29.08.)
    [Test] procedure DirectTObjectDescendant_IsWarningNotError;
    [Test] procedure RealParentClass_StaysError;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestDestructorWithoutInherited.DtorWithInherited_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  FreeAndNil(FBar);'#13#10 +
  '  inherited;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDestructorWithoutInherited));
  finally F.Free; end;
end;

procedure TTestDestructorWithoutInherited.DtorWithoutInherited_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  FreeAndNil(FBar);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDestructorWithoutInherited));
  finally F.Free; end;
end;

procedure TTestDestructorWithoutInherited.RegularProcedure_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDestructorWithoutInherited));
  finally F.Free; end;
end;

procedure TTestDestructorWithoutInherited.DtorForwardDecl_NotReported;
// Regression: Forward-Deklaration im Class-Body (`destructor Destroy;
// override;`) ist keine Implementierung - der Detektor darf hier NICHT
// anschlagen. Echte Implementation steht spaeter im implementation-Teil.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    destructor Destroy; override;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  FreeAndNil(FBar);'#13#10 +
  '  inherited;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDestructorWithoutInherited));
  finally F.Free; end;
end;

procedure TTestDestructorWithoutInherited.ClassDestructor_NotReported;
// Spiegelt den realen FP aus uLexer.pas: class destructor laeuft einmal
// pro Klasse beim Modul-Unload und hat KEINE inheritance chain - `inherited`
// ist hier nicht erwuenscht.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '    class constructor Create;'#13#10 +
  '    class destructor Destroy;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'class constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  // init class-level state'#13#10 +
  'end;'#13#10 +
  'class destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  FreeAndNil(FStaticThing);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDestructorWithoutInherited));
  finally F.Free; end;
end;

procedure TTestDestructorWithoutInherited.ClassDestructor_AfterVarSection_NotReported;
// Regression MVCFramework.Commons.pas L875 (1 echter FP) - var-Section
// direkt vor 'class destructor' kann den ';class'-Marker am Parser
// vorbeischmuggeln. Source-Line-Fallback faengt das Pattern.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '    class destructor Destroy;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'var'#13#10 +
  '  G: Integer = 0;'#13#10 +
  'class destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  G := 0;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDestructorWithoutInherited),
    'class destructor nach var-Section darf nicht gemeldet werden');
  finally F.Free; end;
end;

procedure TTestDestructorWithoutInherited.DtorWithoutInherited_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  FreeAndNil(FBar);'#13#10 +
  'end;';
var
  Findings : TObjectList<TLeakFinding>;
  Fnd      : TLeakFinding;
begin
  Findings := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in Findings do
      if Fnd.Kind = fkDestructorWithoutInherited then
      begin
        Assert.AreEqual<TFindingKind>(fkDestructorWithoutInherited, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsError,                     Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkDestructorWithoutInherited finding');
  finally Findings.Free; end;
end;

// ---------------------------------------------------------------------------
// FP-Gate 2026-07-31 (30%-Real-World-Audit sca-rw-after119)
// Beleg: cnwizards/Bin/Data/Templates/CnIniFiler_Section.pas:75 - der
// Destruktor enthaelt textuell 'inherited;', die '<#...>'-Platzhalter brechen
// aber den Parser. Ohne parsebaren Rumpf faellt SCA097 fuer die ganze Datei
// aus. SCA097 laeuft im FILE-Harness (uTestFindingHelper Z.294) - die Tests
// muessen deshalb FindingsOfFile benutzen, sonst waeren sie vakuum-gruen.
// ---------------------------------------------------------------------------

procedure TTestDestructorWithoutInherited.CodegenTemplateFile_NotReported;
// Exakte Korpus-Form aus CnIniFiler_Section.pas: das `inherited;` steht
// TEXTUELL da, aber hinter dem Platzhalter. Der Parser liest
// 'IniSectionsFree' als Anweisung und SkipToSemicolon frisst '>' UND
// 'inherited' bis zum ';' - der Rumpf sieht kein inherited mehr.
// Ohne den Gate ist das ein Error-Fund (der belegte FP).
const SRC =
  'unit t; implementation'#13#10 +
  'destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '<#IniSectionsFree>  inherited;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDestructorWithoutInherited),
    'Codegen-Template - kein Urteil ohne parsebaren Rumpf');
  finally F.Free; end;
end;

procedure TTestDestructorWithoutInherited.CodegenTemplateInClassName_NotReported;
// Der Gate ist DATEI-weit: der Platzhalter steht hier erst in der
// initialization-Section (wie im Original), der Destruktor selbst parst
// sauber und haette ohne den Gate einen Fund geliefert.
const SRC =
  'unit t; implementation'#13#10 +
  'destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  FreeAndNil(FBar);'#13#10 +
  'end;'#13#10 +
  'initialization'#13#10 +
  '  <#IniClassName> := T<#IniClassName>.Create;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDestructorWithoutInherited));
  finally F.Free; end;
end;

procedure TTestDestructorWithoutInherited.CharLiteralComparison_StillReported;
// Gegenprobe: 'if C<#13 then' ist legales Delphi (Char-Literal-Vergleich).
// Nach '<#' steht eine ZIFFER - kein Template-Platzhalter, der Fund bleibt.
const SRC =
  'unit t; implementation'#13#10 +
  'destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  if C<#13 then'#13#10 +
  '    FreeAndNil(FBar);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDestructorWithoutInherited),
    'Char-Literal-Vergleich ist kein Template-Platzhalter');
  finally F.Free; end;
end;

procedure TTestDestructorWithoutInherited.PlaceholderInStringLiteral_StillReported;
// Gegenprobe: '<#Foo>' in einem String-Literal ist Nutzdaten, kein Template.
const SRC =
  'unit t; implementation'#13#10 +
  'destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  FTemplate := ''<#Placeholder>'';'#13#10 +
  '  FreeAndNil(FBar);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDestructorWithoutInherited));
  finally F.Free; end;
end;

procedure TTestDestructorWithoutInherited.PlaceholderInComment_StillReported;
// Gegenprobe: '<#Foo>' im Kommentar zaehlt ebenfalls nicht.
const SRC =
  'unit t; implementation'#13#10 +
  'destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  // Vorlage nutzt <#Placeholder> als Marker'#13#10 +
  '  FreeAndNil(FBar);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDestructorWithoutInherited));
  finally F.Free; end;
end;

procedure TTestDestructorWithoutInherited.DirectTObjectDescendant_IsWarningNotError;
// KUNDENKORPUS SVGIconImageList (29.08.): fuenf der 18 Error-Funde waren
// von dieser Art - Klassen, die DIREKT von TObject erben. TObject.Destroy
// ist leer, das fehlende inherited ueberspringt also nichts. Die Meldung
// "parent class cleanup is skipped, likely leak" trifft dort nicht zu,
// und lsError heisst in diesem Werkzeug "bewiesen".
//
// KEIN Drop: der Konventionsbruch bleibt real und wird zum Fehler, sobald
// jemand eine Zwischenklasse einzieht. Nur die Schwere geht herunter.
//
// Der Weg ueber FindingsViaPipeline ist Pflicht: der TypeIndex wird NUR
// dort gebaut, und ohne ihn faellt das Gate konservativ aus (kein Demote).
const SRC =
  'unit t;' + #13#10 +
  'interface' + #13#10 +
  'type' + #13#10 +
  '  TFoo = class' + #13#10 +
  '    FBar: TObject;' + #13#10 +
  '    destructor Destroy; override;' + #13#10 +
  '  end;' + #13#10 +
  'implementation' + #13#10 +
  'destructor TFoo.Destroy;' + #13#10 +
  'begin' + #13#10 +
  '  FreeAndNil(FBar);' + #13#10 +
  'end;' + #13#10 +
  'end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkDestructorWithoutInherited then
      begin
        Assert.AreEqual<TLeakSeverity>(lsWarning, Fnd.Severity,
          'TObject-Basis: Konventionsbruch, kein Leck - Warnung statt Fehler');
        Exit;
      end;
    Assert.Fail('der Fund muss BLEIBEN, nur milder');
  finally F.Free; end;
end;

procedure TTestDestructorWithoutInherited.RealParentClass_StaysError;
// GEGENPROBE: mit echter Basisklasse bleibt es ein Fehler. Hier
// ueberspringt das fehlende inherited tatsaechlich die Aufraeumarbeit
// der Elternklasse - genau der Fall, den die Regel meint.
const SRC =
  'unit t;' + #13#10 +
  'interface' + #13#10 +
  'type' + #13#10 +
  '  TFoo = class(TComponent)' + #13#10 +
  '    FBar: TObject;' + #13#10 +
  '    destructor Destroy; override;' + #13#10 +
  '  end;' + #13#10 +
  'implementation' + #13#10 +
  'destructor TFoo.Destroy;' + #13#10 +
  'begin' + #13#10 +
  '  FreeAndNil(FBar);' + #13#10 +
  'end;' + #13#10 +
  'end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkDestructorWithoutInherited then
      begin
        Assert.AreEqual<TLeakSeverity>(lsError, Fnd.Severity,
          'echte Basisklasse: das Gate darf NICHT greifen');
        Exit;
      end;
    Assert.Fail('expected fkDestructorWithoutInherited finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDestructorWithoutInherited);

end.
