unit uTestMethodName;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMethodName = class
  public
    [Test] procedure PascalCase_NoFinding;
    [Test] procedure LowerCamel_Reported;
    [Test] procedure QualifiedName_Reported;
    [Test] procedure UnderscorePrefix_NotReported;
    [Test] procedure MethodName_KindAndSeverity;
    // --- FFI-/external-/Typelib-Gate (Hebel A, 30%-Audit 2026-07-31) ---
    [Test] procedure ExternalRoutine_NotReported;
    [Test] procedure JniInterfaceMethods_NotReported;
    [Test] procedure ObjCDelegateDeclAndImpl_NotReported;
    [Test] procedure PlainClassMethod_StillReported;
    [Test] procedure MixedUnit_OnlyPlainMethodReported;
    [Test] procedure FreeCdeclRoutine_StillReported;
    [Test] procedure TypelibFile_NotReported;
    [Test] procedure NonTypelibFile_Gegenprobe_Reported;
    // ---- Eine Meldung je Methode (2026-08-01) -----------------------------
    [Test] procedure DeclAndImpl_ReportedOnce;
    [Test] procedure SameNameInTwoClasses_BothReported;
    [Test] procedure DeclarationOnly_StillReported;
    // ---- Testpfad-Gate (2026-08-05) ----
    [Test] procedure MethodName_TestDirSegment_Suppressed;
    [Test] procedure MethodName_ProductionPath_StillReported;
    [Test] procedure MethodName_BareFileName_StillReported;
    // Gate 6 (2026-08-21): ein Typ, der AUSNAHMSLOS camelCase benennt,
    // spiegelt eine fremde API - dort ist der Name ein ABI-Schluessel.
    [Test] procedure CamelTypeAmnesty_AndItsTwoBoundaries;
    // Gate 7 (2026-08-28): der praeprozessor-blind geparste Dual-Mode-
    // Header ist gar kein Methodenkopf.
    [Test] procedure DualModeHeader_AndItsTwoBoundaries;
  end;

implementation

// noinspection-file HardcodedPath, ClassPerFile, GodClass
// HardcodedPath: die Testpfade sind der PRUEFGEGENSTAND des
// Testpfad-Gates - sie muessen woertlich dastehen, damit die
// Verankerung der Segment-Muster ueberhaupt pruefbar ist.
// ClassPerFile: die Klassen stehen in QUELLTEXT-STRINGS der
// Fixtures, nicht als zweite Klasse dieser Unit.
// GodClass: mit Gate 7 steht die Fixture bei 21 Testmethoden, eine ueber
// der Schwelle von uGodClass (MAX_METHODS=20). Eine DUnitX-Fixture ist
// eine flache Liste unabhaengiger Faelle - "in fokussierte Einheiten
// aufteilen" waere hier kein Gewinn, sondern ein zweites Testmodul samt
// Projektdatei-Eingriff. Vier Schwesterunits (uTestDuplicate,
// uTestMissingFinally, uTestDfmDeadEvent, uTestEditorCommand) fuehren
// denselben Marker aus demselben Grund. Die drei Faelle von Gate 7
// bleiben trotzdem in EINER Methode gebuendelt - s. die Begruendung an
// CamelTypeAmnesty_AndItsTwoBoundaries.

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uParser2, uMethodName,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

// Laeuft NUR SCA106 mit KONTROLLIERTEM Dateinamen. SCA106 ist rein
// AST-basiert und liest die Datei nicht - der Name wird nur fuer das
// *_TLB.pas-Gate gebraucht, eine echte Datei ist nicht noetig.
function MethodFindingsFor(const ASource, AFileName: string)
  : TObjectList<TLeakFinding>;
var
  Parser : TParser2;
  Root   : TAstNode;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(ASource);
    try
      TMethodNameDetector.AnalyzeUnit(Root, AFileName, Result);
    finally
      Root.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TTestMethodName.PascalCase_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure DoStuff; begin end;'#13#10 +
  'function GetX: Integer; begin Result := 0; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMethodName));
  finally F.Free; end;
end;

procedure TTestMethodName.LowerCamel_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure doStuff; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMethodName));
  finally F.Free; end;
end;

procedure TTestMethodName.QualifiedName_Reported;
// `TFoo.doStuff` - der Teil nach dem Punkt zaehlt.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.doStuff; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMethodName));
  finally F.Free; end;
end;

procedure TTestMethodName.UnderscorePrefix_NotReported;
// `_Magic` ist ausgenommen (RTL-Konvention fuer Reserved-Magic).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure _MagicCallback; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMethodName));
  finally F.Free; end;
end;

procedure TTestMethodName.MethodName_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure doStuff; begin end;';
var
  Findings : TObjectList<TLeakFinding>;
  Fnd      : TLeakFinding;
begin
  Findings := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in Findings do
      if Fnd.Kind = fkMethodName then
      begin
        Assert.AreEqual<TFindingKind>(fkMethodName, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,      Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkMethodName finding');
  finally Findings.Free; end;
end;

{ ---- FFI-/external-/Typelib-Gate (Hebel A, 2026-07-31) ---- }

procedure TTestMethodName.ExternalRoutine_NotReported;
// Ohne name-Klausel IST der Bezeichner das Link-Symbol der .obj -
// 'PascalCase' waere nicht umsetzbar (jvcl pngzlib.pas).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure inflate_trees_bits; external;'#13#10 +
  'function adler32; external;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMethodName),
    'external-Routinen tragen Link-Symbole, keine Delphi-Namen');
  finally F.Free; end;
end;

procedure TTestMethodName.JniInterfaceMethods_NotReported;
// JNI-Import-Interface: der Methodenname IST der Java-Methodenname,
// ueber den die Bridge marshallt (Kastri/Alcinoe-Muster).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'uses Androidapi.JNIBridge;'#13#10 +
  'type'#13#10 +
  '  JDetector = interface(JObject)'#13#10 +
  '    function detect(frame: Integer): Integer; cdecl;'#13#10 +
  '    procedure receiveFrame(frame: Integer); cdecl;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMethodName),
    'cdecl-Methoden eines Bridge-Interfaces sind Java-Namen');
  finally F.Free; end;
end;

procedure TTestMethodName.ObjCDelegateDeclAndImpl_NotReported;
// TOCLocal-Delegate: die DEKLARATION traegt cdecl, die IMPLEMENTIERUNG
// wiederholt die Direktive NICHT. Nur das Typ-Gate faengt beide - ohne
// das waere die Implementierung weiterhin ein Fund.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'uses Macapi.ObjectiveC;'#13#10 +
  'type'#13#10 +
  '  TDownloadDelegate = class(TOCLocal)'#13#10 +
  '  public'#13#10 +
  '    procedure downloadDidFinish(download: Pointer); cdecl;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TDownloadDelegate.downloadDidFinish(download: Pointer);'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMethodName),
    'Deklaration UND Implementierung des ObjC-Selektors bleiben stumm');
  finally F.Free; end;
end;

procedure TTestMethodName.PlainClassMethod_StillReported;
// Referenzwert fuer MixedUnit_OnlyPlainMethodReported: eine normale
// Delphi-Klasse mit kleingeschriebener Methode ergibt EINEN Fund.
//
// Bis 2026-08-01 waren es zwei (Deklaration UND Implementierung). Die Zahl
// war hier nie eine Aussage, sondern nur der Bezugswert fuer den
// Mixed-Unit-Test - der prueft, dass das FFI-Gate ausschliesslich die
// Bridge-Methoden trifft. Seit der Deduplizierung ist eine Methode EIN
// Befund; beide Tests ziehen deshalb gemeinsam auf 1 nach.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TPlainWorker = class(TObject)'#13#10 +
  '  public'#13#10 +
  '    procedure dosomething;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TPlainWorker.dosomething;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMethodName),
    'Eine Meldung je Methode - Deklaration und Implementierung sind EIN Befund');
  finally F.Free; end;
end;

procedure TTestMethodName.MixedUnit_OnlyPlainMethodReported;
// Kern-Gegenprobe: dieselbe normale Klasse NEBEN einem ObjC-Delegate.
// Die Fundzahl muss identisch zu PlainClassMethod_StillReported sein -
// das Gate darf ausschliesslich die Bridge-Methoden treffen.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'uses Macapi.ObjectiveC;'#13#10 +
  'type'#13#10 +
  '  TDownloadDelegate = class(TOCLocal)'#13#10 +
  '  public'#13#10 +
  '    procedure downloadDidFinish(download: Pointer); cdecl;'#13#10 +
  '  end;'#13#10 +
  '  TPlainWorker = class(TObject)'#13#10 +
  '  public'#13#10 +
  '    procedure dosomething;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TDownloadDelegate.downloadDidFinish(download: Pointer);'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'procedure TPlainWorker.dosomething;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMethodName),
      'nur der eine Fund der normalen Klasse');
    for Fnd in F do
      if Fnd.Kind = fkMethodName then
        Assert.IsTrue(Pos('downloadDidFinish', Fnd.MissingVar) = 0,
          'der ObjC-Selektor darf nicht darunter sein: ' + Fnd.MissingVar);
  finally F.Free; end;
end;

procedure TTestMethodName.FreeCdeclRoutine_StillReported;
// BEWUSSTE Verengung: cdecl gilt nur an einer TYP-Methode als
// ABI-Bindung. Eine freie cdecl-Routine ist ein vom Autor benannter
// C-Callback (Lua-/SQLite-Muster) - Name frei waehlbar, Regel greift.
const SRC =
  'unit t; implementation'#13#10 +
  'function luaDirectoryExists(L: Pointer): Integer; cdecl;'#13#10 +
  'begin'#13#10 +
  '  Result := 0;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMethodName),
    'freie cdecl-Routine bleibt ein Fund');
  finally F.Free; end;
end;

procedure TTestMethodName.TypelibFile_NotReported;
// Generierter COM-Typelib-Import: Methodennamen stammen aus der
// Typelib und werden bei jedem Refresh regeneriert.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  IWMPCore = interface(IDispatch)'#13#10 +
  '    procedure launchURL(const bstrURL: WideString); safecall;'#13#10 +
  '    function getItemInfo(const bstrItem: WideString): WideString; safecall;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := MethodFindingsFor(SRC, 'D:\repo\plugins\wmplib_1_0_tlb.pas');
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMethodName),
    'in *_TLB.pas ist keine Namens-Empfehlung umsetzbar');
  finally F.Free; end;
end;

procedure TTestMethodName.NonTypelibFile_Gegenprobe_Reported;
// Derselbe Quelltext unter normalem Dateinamen MUSS melden - sonst
// waere der Typelib-Test auch bei einem stummen Detektor gruen.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  IWMPCore = interface(IDispatch)'#13#10 +
  '    procedure launchURL(const bstrURL: WideString); safecall;'#13#10 +
  '    function getItemInfo(const bstrItem: WideString): WideString; safecall;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := MethodFindingsFor(SRC, 'D:\repo\src\uPlayer.pas');
  try Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkMethodName),
    'ohne Typelib-Namensmuster bleiben beide Funde');
  finally F.Free; end;
end;

procedure TTestMethodName.DeclAndImpl_ReportedOnce;
// FindAll(nkMethod) liefert fuer eine implementierte Methode ZWEI Knoten:
// die Deklaration im Typ und die Implementierung. Das ist EIN Bezeichner
// und EINE Umbenennung - also ein Befund. Korpus-Zensus after126: 10.890
// der 30.925 Funde (35 %) waren solche Zwillinge.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '    procedure doStuff;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.doStuff;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMethodName),
    'Deklaration und Implementierung derselben Methode sind EIN Befund');
  finally F.Free; end;
end;

procedure TTestMethodName.SameNameInTwoClasses_BothReported;
// WAECHTER: der Schluessel ist (Besitzertyp, Name), NICHT (Datei, Name).
// 'TFoo.doStuff' und 'TBar.doStuff' sind zwei verschiedene Bezeichner und
// brauchen zwei Umbenennungen. Im Korpus stehen dahinter 5.489
// Mehrfachmeldungen, die zu Recht bestehen bleiben (Firebird.pas meldet
// 'create' 172x - fuer 172 verschiedene Klassen).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '    procedure doStuff;'#13#10 +
  '  end;'#13#10 +
  '  TBar = class'#13#10 +
  '    procedure doStuff;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.doStuff;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'procedure TBar.doStuff;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkMethodName),
    'Gleicher Name in zwei Klassen sind zwei Befunde');
  finally F.Free; end;
end;

procedure TTestMethodName.DeclarationOnly_StillReported;
// WAECHTER: eine Methode ohne Implementierung in derselben Unit (Interface,
// abstract) darf durch die Deduplizierung nicht verschwinden.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  IFoo = interface'#13#10 +
  '    procedure doStuff;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMethodName),
    'Reine Deklaration bleibt ein Befund');
  finally F.Free; end;
end;

{ ---- Testpfad-Gate (2026-08-05) ---- }

// GEMESSEN vor dem Bau: 7.801 der 19.504 Korpusfunde (40 %) liegen in
// Testpfad-Segmenten, davon 6.292 unter 'unittests' - im Wesentlichen
// sechs Kopien eines generierten Firebird-Interface-Headers unter
// bin32/ und bin64/ zweier Repo-Kopien.
const
  SRC_LOWERCASE_METHOD =
    'unit t;'#13#10+
    'interface'#13#10+
    'type'#13#10+
    '  TFoo = class'#13#10+
    '    procedure initSomething;'#13#10+
    '  end;'#13#10+
    'implementation'#13#10+
    'procedure TFoo.initSomething; begin end;'#13#10+
    'end.';

procedure TTestMethodName.MethodName_TestDirSegment_Suppressed;
var F: TObjectList<TLeakFinding>;
begin
  F := MethodFindingsFor(SRC_LOWERCASE_METHOD,
         'D:\repo\unittests\bin32\firebird\Firebird.pas');
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMethodName),
      'Namensregel gilt nicht in Testverzeichnissen');
  finally F.Free; end;
end;

procedure TTestMethodName.MethodName_ProductionPath_StillReported;
// WAECHTER gegen ein zu breites Gate: derselbe Quelltext im Produktivbaum
// MUSS weiter melden. Ohne diesen Test koennte das Gate die Regel
// unbemerkt komplett stilllegen.
var F: TObjectList<TLeakFinding>;
begin
  F := MethodFindingsFor(SRC_LOWERCASE_METHOD, 'D:\repo\src\uFoo.pas');
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMethodName),
      'Produktionsfund darf nicht verschwinden');
  finally F.Free; end;
end;

procedure TTestMethodName.MethodName_BareFileName_StillReported;
// Stufe tplFixtureDir wertet NUR Verzeichnis-Segmente. Ein blosser
// Dateiname - auch einer, der auf ein Basename-Muster passt - darf das
// Gate nie ausloesen (sonst faellt der Test-Harness selbst darunter).
var F: TObjectList<TLeakFinding>;
begin
  F := MethodFindingsFor(SRC_LOWERCASE_METHOD, 'MySample.pas');
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMethodName),
      'Basename ohne Verzeichnis ist kein Testpfad');
  finally F.Free; end;
end;


procedure TTestMethodName.CamelTypeAmnesty_AndItsTwoBoundaries;
// Gate 6 und seine BEIDEN Grenzen in einem Vertrag.
//
// Warum in EINEM Test statt in dreien: TTestMethodName steht bei 20
// Methoden, der Selfscan meldet ab 21 eine God-Klasse. Drei einzelne
// Tests haetten die Fixture ueber die Grenze gehoben, und ein eigenes
// Testmodul haette die Projektdateien angefasst - das war es nicht
// wert. Die drei Faelle gehoeren ohnehin zusammen: die Ausnahme und
// genau das, was sie begrenzt.
var
  F : TObjectList<TLeakFinding>;
const
  // 1) Der Firebird-OO-Fall: fuenf Methoden, alle camelCase. Wer hier
  //    umbenennt, zerbricht die Bindung.
  SRC_AMNESTIE =
    'unit t;'#13#10+
    'interface'#13#10+
    'type'#13#10+
    '  IStatus = interface'#13#10+
    '    procedure addRef;'#13#10+
    '    procedure release;'#13#10+
    '    function getInfo: Integer;'#13#10+
    '    function getPerf: Integer;'#13#10+
    '    procedure setOwner;'#13#10+
    '  end;'#13#10+
    'implementation'#13#10+
    'end.';
  // 2) Erste Grenze - und der Grund fuer 100 %% statt 80 %%: ein
  //    EINZIGER PascalCase-Name zeigt, dass der Typ sich eben NICHT
  //    festgelegt hat. Dann sind die kleinen Namen Nachlaessigkeit,
  //    keine Bindung, und alle fuenf bleiben Funde.
  SRC_EIN_PASCAL =
    'unit t;'#13#10+
    'interface'#13#10+
    'type'#13#10+
    '  TSchlampig = class'#13#10+
    '    procedure addRef;'#13#10+
    '    procedure release;'#13#10+
    '    function getInfo: Integer;'#13#10+
    '    function getPerf: Integer;'#13#10+
    '    procedure setOwner;'#13#10+
    '    procedure DoWork;'#13#10+
    '  end;'#13#10+
    'implementation'#13#10+
    'end.';
  // 3) Zweite Grenze: unter fuenf Methoden ist camelCase noch keine
  //    erkennbare Konvention, sondern koennte Zufall sein.
  SRC_ZU_KLEIN =
    'unit t;'#13#10+
    'interface'#13#10+
    'type'#13#10+
    '  TKlein = class'#13#10+
    '    procedure addRef;'#13#10+
    '    procedure release;'#13#10+
    '  end;'#13#10+
    'implementation'#13#10+
    'end.';
begin
  F := TFindingHelper.FindingsOfFile(SRC_AMNESTIE);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMethodName),
      'ein durchgehend camelCase benannter Typ ist eine Festlegung');
  finally
    F.Free;
  end;

  F := TFindingHelper.FindingsOfFile(SRC_EIN_PASCAL);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkMethodName) >= 5,
      'ein einziger PascalCase-Name hebt die Amnestie auf');
  finally
    F.Free;
  end;

  F := TFindingHelper.FindingsOfFile(SRC_ZU_KLEIN);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkMethodName) >= 2,
      'zwei camelCase-Methoden sind noch keine Konvention');
  finally
    F.Free;
  end;
end;

procedure TTestMethodName.DualModeHeader_AndItsTwoBoundaries;
// Gate 7 und seine BEIDEN Grenzen in einem Vertrag - gleiche Bauform und
// gleicher Grund wie bei CamelTypeAmnesty_AndItsTwoBoundaries.
//
// Das Gate wertet AUSSCHLIESSLICH die Rueckgabetyp-POSITION. Beide
// Grenzen pruefen genau das: ein prozeduraler PARAMETER-Typ und ein
// Typ-Bezeichner, der mit 'Function' ANFAENGT, muessen Funde bleiben.
//
// Was welcher Fall beweist: Fall 1 traegt das Gate (ohne Gate 7 liefert
// SRC_DUAL_MODE 3 Funde statt 0 - alle Namen sind kleingeschrieben,
// OwnerName ist leer, also greifen weder Gate 2 noch Gate 6). Die Faelle
// 2 und 3 sind WAECHTER gegen eine zu breite Implementierung und bleiben
// auch ohne das Gate gruen; sie kippen erst, wenn jemand statt des
// ersten Tokens ein blosses StartsWith prueft oder die Parameterliste
// mit einbezieht.
var
  F : TObjectList<TLeakFinding>;
const
  // 1) Die Fehlform aus skia4delphi\Source\System.Skia.API.pas, woertlich
  //    nachgebaut. Der Lexer skippt die IFDEFs per Default NICHT (sie sind
  //    fuer ihn Kommentar), also stehen beide Zweige im Tokenstrom:
  //    ParseVarLikeSection steigt am fuehrenden `function` aus, die
  //    Interface-Sektion dispatcht in ParseMethodSignature, und es
  //    entsteht ein nkMethod mit TypeRef 'function:function():...'.
  //    Das ist kein Methodenkopf - kein Fund.
  SRC_DUAL_MODE =
    'unit t;'#13#10+
    'interface'#13#10+
    '{$IFNDEF SK_STATIC_LIBRARY}'#13#10+
    'var'#13#10+
    '{$ENDIF}'#13#10+
    '  {$IFDEF SK_STATIC_LIBRARY}function {$ENDIF}gr4d_backendsemaphore_create'+
    '{$IFNDEF SK_STATIC_LIBRARY}: function {$ENDIF}(): gr_backendsemaphore_t; cdecl;'#13#10+
    '  {$IFDEF SK_STATIC_LIBRARY}procedure {$ENDIF}gr4d_backendsemaphore_destroy'+
    '{$IFNDEF SK_STATIC_LIBRARY}: procedure {$ENDIF}(self: gr_backendsemaphore_t); cdecl;'#13#10+
    // Dritte Zeile: MEHRERE Parameter, und das ist die MEHRHEITSFORM -
    // 463 der 806 Korpusfaelle (57 %) sehen so aus. Die Ret-Type-Schleife
    // in ParseMethodSignature stoppt am ersten tkSemicolon, hier also
    // schon INNERHALB der Parameterliste; der TypeRef bricht mittendrin
    // ab ('procedure:procedure(self:sk_rrect_t') und traegt keine
    // schliessende Klammer. Das Gate darf davon nicht abhaengen - es
    // liest nur das erste Token der Rueckgabeposition, und das steht
    // vor der Abbruchstelle. Ohne diese Zeile pruefte die Fixture nur
    // die Minderheitsform.
    '  {$IFDEF SK_STATIC_LIBRARY}procedure {$ENDIF}sk4d_rrect_inflate'+
    '{$IFNDEF SK_STATIC_LIBRARY}: procedure {$ENDIF}(self: sk_rrect_t; dx, dy: float); cdecl;'#13#10+
    'implementation'#13#10+
    'end.';
  // 2) Erste Grenze: ein prozeduraler PARAMETER-Typ. Hier steht `procedure`
  //    hinter einem Doppelpunkt, aber in der Parameter-Liste - der TypeRef
  //    der Methode traegt gar keinen Rueckgabetyp - beide bleiben Funde.
  //    doStuff ist die realistische Form. doOther ist bewusst SYNTHETISCH:
  //    `cb: procedure` kompiliert in Delphi nicht, denn auch in
  //    Parameterposition verlangt die Sprache einen Typ-BEZEICHNER - genau
  //    die Regel, auf die sich Gate 7 beruft. Als Parser-EINGABE ist die
  //    Zeile trotzdem zulaessig, und sie ist der schaerfste Waechter, den
  //    es gibt: sie bringt das Schluesselwort woertlich hinter einen
  //    Doppelpunkt, ohne dass es in Rueckgabeposition steht.
  SRC_PROC_PARAM =
    'unit t; implementation'#13#10+
    'procedure doStuff(cmp: TCompareFunc); begin end;'#13#10+
    'procedure doOther(cb: procedure); begin end;';
  // 3) Zweite Grenze: ein Typ-BEZEICHNER, der mit 'Function' anfaengt.
  //    Die Wortgrenze muss ueber das erste Token laufen, nicht ueber ein
  //    blosses StartsWith - sonst begnadigt das Gate hier faelschlich.
  SRC_FUNCTION_PREFIX_TYPE =
    'unit t; implementation'#13#10+
    'function getIt: FunctionResult; begin end;';
begin
  F := TFindingHelper.FindingsOfFile(SRC_DUAL_MODE);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMethodName),
      'ein Rueckgabetyp, der mit function/procedure beginnt, ist kein ' +
      'Routinenkopf - in Object Pascal gibt es diese Form nicht');
  finally
    F.Free;
  end;

  F := TFindingHelper.FindingsOfFile(SRC_PROC_PARAM);
  try
    Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkMethodName),
      'nur die Rueckgabe-Position zaehlt, nicht die Parameter');
  finally
    F.Free;
  end;

  F := TFindingHelper.FindingsOfFile(SRC_FUNCTION_PREFIX_TYPE);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMethodName),
      'FunctionResult ist ein Typname, kein Schluesselwort');
  finally
    F.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMethodName);

end.
