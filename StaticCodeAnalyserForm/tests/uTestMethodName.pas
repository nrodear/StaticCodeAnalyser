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
  end;

implementation

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
// Delphi-Klasse mit kleingeschriebener Methode ergibt zwei Funde
// (Deklaration + Implementierung).
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
  try Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkMethodName),
    'Deklaration + Implementierung der normalen Methode');
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
    Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkMethodName),
      'nur die beiden Funde der normalen Klasse');
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

initialization
  TDUnitX.RegisterTestFixture(TTestMethodName);

end.
