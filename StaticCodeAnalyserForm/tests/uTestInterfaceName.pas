unit uTestInterfaceName;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestInterfaceName = class
  public
    [Test] procedure IPrefix_NoFinding;
    [Test] procedure NoIPrefix_Reported;
    [Test] procedure DispInterface_Checked;
    [Test] procedure InterfaceName_KindAndSeverity;
    // --- FFI-/Typelib-Gate (Hebel A, 30%-Audit 2026-07-31) -------------
    [Test] procedure JniBridgeInterfaces_NotReported;
    [Test] procedure ObjCBridgeInterfaces_NotReported;
    [Test] procedure MixedUnit_OnlyPlainInterfaceReported;
    [Test] procedure TypelibFile_NotReported;
    [Test] procedure NonTypelibFile_Gegenprobe_Reported;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.IOUtils,
  uAstNode, uParser2, uInterfaceName,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

// Laeuft NUR SCA105 gegen eine temporaere Datei mit KONTROLLIERTEM
// Basisnamen - der gemeinsame Harness (FindingsOfFile) vergibt einen
// zufaelligen Namen, das *_TLB.pas-Gate ist damit nicht testbar.
// SCA105 liest die Datei selbst (AcquireLines), sie muss also existieren.
function InterfaceFindingsForFile(const ASource, ANameSuffix: string)
  : TObjectList<TLeakFinding>;
var
  Parser : TParser2;
  Root   : TAstNode;
  Path   : string;
  SL     : TStringList;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  Path := TPath.Combine(TPath.GetTempPath,
    'sca_ifn_' + TGuid.NewGuid.ToString.Replace('{', '').Replace('}', '')
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
        TInterfaceNameDetector.AnalyzeUnit(Root, Path, Result);
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

procedure TTestInterfaceName.IPrefix_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  IService = interface end;'#13#10 +
  '  IFoo = interface(IUnknown) end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInterfaceName));
  finally F.Free; end;
end;

procedure TTestInterfaceName.NoIPrefix_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type Service = interface end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInterfaceName));
  finally F.Free; end;
end;

procedure TTestInterfaceName.DispInterface_Checked;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type Service = dispinterface end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInterfaceName));
  finally F.Free; end;
end;

procedure TTestInterfaceName.InterfaceName_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type Service = interface end;'#13#10 +
  'implementation end.';
var
  Findings : TObjectList<TLeakFinding>;
  Fnd      : TLeakFinding;
begin
  Findings := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in Findings do
      if Fnd.Kind = fkInterfaceName then
      begin
        Assert.AreEqual<TFindingKind>(fkInterfaceName, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,         Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkInterfaceName finding');
  finally Findings.Free; end;
end;

{ ---- FFI-/Typelib-Gate (Hebel A, 2026-07-31) ---- }

procedure TTestInterfaceName.JniBridgeInterfaces_NotReported;
// Androidapi-Bridge: die J<Name>-Konvention der RTL ist verbindlich,
// eine Umbenennung auf I<Name> braeche die Bindung. Drei Formen:
// Vorwaerts-Deklaration (erzeugt KEINEN AST-Knoten), Anker-Vererbung
// (JObject/JObjectClass) und ein Interface, dessen Elternteil in einer
// FREMDEN Unit steht und nur ueber TJavaGenericImport belegt ist.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'uses Androidapi.JNIBridge;'#13#10 +
  'type'#13#10 +
  '  JDetector = interface;'#13#10 +
  '  JDetectorClass = interface(JObjectClass)'#13#10 +
  '    function init: Integer; cdecl;'#13#10 +
  '  end;'#13#10 +
  '  JDetector = interface(JObject)'#13#10 +
  '    function detect: Integer; cdecl;'#13#10 +
  '  end;'#13#10 +
  '  JKeyGenParameterSpec = interface(JAlgorithmParameterSpec)'#13#10 +
  '  end;'#13#10 +
  '  TJKeyGenParameterSpec = class(TJavaGenericImport<JDetectorClass, JKeyGenParameterSpec>) end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInterfaceName),
    'JNI-Bridge-Interfaces duerfen nicht gemeldet werden');
  finally F.Free; end;
end;

procedure TTestInterfaceName.ObjCBridgeInterfaces_NotReported;
// ObjC-Bridge: der Interface-Name IST der native Klassenname.
// Deckt Anker (NSObject/NSObjectClass), Vorwaerts-Deklaration und
// transitive Vererbung innerhalb der Unit ab.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'uses Macapi.ObjectiveC;'#13#10 +
  'type'#13#10 +
  '  EKEvent = interface;'#13#10 +
  '  EKObjectClass = interface(NSObjectClass)'#13#10 +
  '  end;'#13#10 +
  '  EKObject = interface(NSObject)'#13#10 +
  '    procedure reset; cdecl;'#13#10 +
  '  end;'#13#10 +
  '  EKEvent = interface(EKObject)'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInterfaceName),
    'ObjC-Bridge-Interfaces duerfen nicht gemeldet werden');
  finally F.Free; end;
end;

procedure TTestInterfaceName.MixedUnit_OnlyPlainInterfaceReported;
// Kern-Gegenprobe: das Gate darf NUR die Bridge-Typen treffen. Ein
// normales Interface ohne I-Praefix in DERSELBEN Unit bleibt Fund.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'uses Androidapi.JNIBridge;'#13#10 +
  'type'#13#10 +
  '  JDetector = interface(JObject)'#13#10 +
  '    function detect: Integer; cdecl;'#13#10 +
  '  end;'#13#10 +
  '  Service = interface'#13#10 +
  '    procedure Run;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInterfaceName),
      'genau das Nicht-Bridge-Interface wird gemeldet');
    Fnd := TFindingHelper.FirstOf(F, fkInterfaceName);
    Assert.IsNotNull(Fnd);
    Assert.IsTrue(Pos('Service', Fnd.MissingVar) > 0,
      'gemeldet wird Service, nicht JDetector: ' + Fnd.MissingVar);
  finally F.Free; end;
end;

procedure TTestInterfaceName.TypelibFile_NotReported;
// Generierte COM-Typelib-Importe: der Importer uebernimmt die
// COM-Originalnamen und regeneriert die Datei bei jedem Refresh.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  _SiteMembershipCondition = interface;'#13#10 +
  '  Service = interface end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := InterfaceFindingsForFile(SRC, '_TLB.pas');
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInterfaceName),
    'in *_TLB.pas ist keine Namens-Empfehlung umsetzbar');
  finally F.Free; end;
end;

procedure TTestInterfaceName.NonTypelibFile_Gegenprobe_Reported;
// Derselbe Quelltext unter normalem Dateinamen MUSS melden - sonst
// wuerde der obige Test auch bei einem kaputten Detektor gruen sein.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  _SiteMembershipCondition = interface;'#13#10 +
  '  Service = interface end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := InterfaceFindingsForFile(SRC, '.pas');
  try Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkInterfaceName),
    'ohne Typelib-Namensmuster bleiben beide Funde');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestInterfaceName);

end.
