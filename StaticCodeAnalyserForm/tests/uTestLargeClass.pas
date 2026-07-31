unit uTestLargeClass;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestLargeClass = class
  public
    [Test] procedure LargeClass_Reported;
    [Test] procedure SmallClass_NotReported;
    [Test] procedure Finding_KindAndSeverity;
    // Real-World FP-Audit 2026-07-10 Regression (span-overcounts-sibling-classes)
    [Test] procedure SmallSiblingOfBigClass_OnlyBigReported;
    // --- FFI-/Typelib-Gate (Backlog 4e-3, 30%-Audit 2026-07-31) ---
    [Test] procedure JniBridgeInterface_NotReported;
    [Test] procedure MixedUnit_OnlyAppClassReported;
    [Test] procedure TypelibFile_NotReported;
    [Test] procedure NonTypelibFile_Gegenprobe_Reported;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.IOUtils,
  uAstNode, uParser2, uLargeClass,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

// Laeuft NUR SCA141 gegen eine temporaere Datei mit KONTROLLIERTEM
// Basisnamen (der gemeinsame Harness vergibt einen zufaelligen Namen, das
// *_TLB.pas-Gate waere damit nicht testbar) und liefert exakte Zaehlungen
// ohne Fremdregeln. Muster uebernommen aus uTestInterfaceName (SCA105).
function LargeClassFindingsForFile(const ASource, ANameSuffix: string)
  : TObjectList<TLeakFinding>;
var
  Parser : TParser2;
  Root   : TAstNode;
  Path   : string;
  SL     : TStringList;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  Path := TPath.Combine(TPath.GetTempPath,
    'sca_lgc_' + TGuid.NewGuid.ToString.Replace('{', '').Replace('}', '')
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
        TLargeClassDetector.AnalyzeUnit(Root, Path, Result);
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

procedure TTestLargeClass.LargeClass_Reported;
// Erzeuge eine Klasse + Implementation die ueber 500 Zeilen spannt.
var
  SB : TStringBuilder;
  i  : Integer;
  F  : TObjectList<TLeakFinding>;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit t;');
    SB.AppendLine('interface');
    SB.AppendLine('type');
    SB.AppendLine('  TBig = class');
    SB.AppendLine('    procedure A;');
    SB.AppendLine('    procedure B;');
    SB.AppendLine('  end;');
    SB.AppendLine('implementation');
    SB.AppendLine('procedure TBig.A;');
    SB.AppendLine('begin');
    // 600 Zeilen Body in A.
    for i := 1 to 600 do
      SB.AppendLine(Format('  WriteLn(''%d'');', [i]));
    SB.AppendLine('end;');
    SB.AppendLine('procedure TBig.B;');
    SB.AppendLine('begin WriteLn(''b''); end;');
    SB.AppendLine('end.');
    F := TFindingHelper.FindingsOf(SB.ToString);
    try Assert.IsTrue(TFindingHelper.Count(F, fkLargeClass) >= 1);
    finally F.Free; end;
  finally
    SB.Free;
  end;
end;

procedure TTestLargeClass.SmallClass_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '    procedure Bar;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Bar; begin WriteLn(''x''); end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLargeClass));
  finally F.Free; end;
end;

procedure TTestLargeClass.Finding_KindAndSeverity;
var
  SB  : TStringBuilder;
  i   : Integer;
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit t;');
    SB.AppendLine('interface');
    SB.AppendLine('type TBig = class procedure A; end;');
    SB.AppendLine('implementation');
    SB.AppendLine('procedure TBig.A;');
    SB.AppendLine('begin');
    for i := 1 to 600 do
      SB.AppendLine(Format('  WriteLn(''%d'');', [i]));
    SB.AppendLine('end;');
    SB.AppendLine('end.');
    F := TFindingHelper.FindingsOf(SB.ToString);
    try
      Hit := nil;
      for Fnd in F do
        if Fnd.Kind = fkLargeClass then begin Hit := Fnd; Break; end;
      Assert.IsNotNull(Hit, 'fkLargeClass finding expected');
      Assert.AreEqual(lsWarning, Hit.Severity);
    finally F.Free; end;
  finally
    SB.Free;
  end;
end;

procedure TTestLargeClass.SmallSiblingOfBigClass_OnlyBigReported;
// Real-World FP-Audit 2026-07-10 (span-overcounts-sibling-classes): eine winzige
// Klasse, die sich eine Unit mit einer grossen teilt, bekam faelschlich die Span
// der ganzen Unit - der Parser haengt nachfolgende Geschwister-Decls als
// Descendants an die erste Klasse, und die alte max-min-Span zaehlte zusaetzlich
// die erst weit hinten implementierte Einzelmethode voll. Nach dem Summen-Fix
// (Deklarations-Span gedeckelt an der naechsten Klasse + Summe der Methoden-Body-
// Spans) wird NUR die grosse Klasse gemeldet.
var
  SB       : TStringBuilder;
  i        : Integer;
  F        : TObjectList<TLeakFinding>;
  Fnd, Hit : TLeakFinding;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit t; interface');
    SB.AppendLine('type');
    SB.AppendLine('  TSmall = class');   // winzig: 1 Methode, ~3 eigene Zeilen
    SB.AppendLine('    procedure A;');
    SB.AppendLine('  end;');
    SB.AppendLine('  TBig = class');      // gross: 550 Felder-Deklaration
    for i := 1 to 550 do
      SB.AppendLine(Format('    F%d: Integer;', [i]));
    SB.AppendLine('  end;');
    SB.AppendLine('implementation');
    // TSmall.A wird erst NACH den 550 Feldern implementiert (Zeile ~558) -
    // exakt der Fall den die alte max-min-Span als "557 Zeilen" fehlzaehlte.
    SB.AppendLine('procedure TSmall.A; begin end;');
    SB.AppendLine('end.');
    F := TFindingHelper.FindingsOf(SB.ToString);
    try
      Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkLargeClass),
        'nur die grosse Klasse TBig, nicht die winzige Geschwister-Klasse TSmall');
      Hit := nil;
      for Fnd in F do
        if Fnd.Kind = fkLargeClass then begin Hit := Fnd; Break; end;
      Assert.AreEqual('TBig', Hit.MethodName,
        'gemeldete Klasse muss TBig sein (TSmall ist der span-slurp-FP)');
    finally F.Free; end;
  finally
    SB.Free;
  end;
end;


{ ---- FFI-/Typelib-Gate (Backlog 4e-3, 30%-Audit 2026-07-31) ----
  Dieselbe Mechanik wie in SCA138 GodClass: der Zeilenumfang eines
  generierten Bridge-Typs ist der Umfang der importierten Java-Klasse
  bzw. des ObjC-Protokolls. Im Korpus (sca-rw-after123) trifft das genau
  EINEN von 1.822 Funden (JBarcodeReaderClass in
  DW.Androidapi.JNI.DataCollection.pas) - das Gate steht fuer die
  Familien-Konsistenz und waechst mit dem JNI-Anteil einer Codebasis. }

procedure TTestLargeClass.JniBridgeInterface_NotReported;
// Ein generiertes JNI-Interface mit 550 {class}-Gettern reisst die
// 500-Zeilen-Schwelle - "split responsibilities" ist dort nicht
// ausfuehrbar. OHNE das Gate meldet der Detektor hier.
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
    SB.AppendLine('  JBarcodeReaderClass = interface(JObject)');
    for i := 1 to 550 do
      SB.AppendLine(Format('    function getCode%d: Integer; cdecl;', [i]));
    SB.AppendLine('  end;');
    SB.AppendLine('implementation');
    SB.AppendLine('end.');
    F := LargeClassFindingsForFile(SB.ToString, '.pas');
    try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLargeClass),
      'generiertes JNI-Bridge-Interface ist keine zu grosse Klasse');
    finally F.Free; end;
  finally
    SB.Free;
  end;
end;

procedure TTestLargeClass.MixedUnit_OnlyAppClassReported;
// KERN-GEGENPROBE (Muss-bleiben): der TYP entscheidet, nicht die Datei.
// Die eigene grosse Klasse in derselben Unit bleibt Fund.
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
    SB.AppendLine('  JBarcodeReaderClass = interface(JObject)');
    for i := 1 to 550 do
      SB.AppendLine(Format('    function getCode%d: Integer; cdecl;', [i]));
    SB.AppendLine('  end;');
    SB.AppendLine('  TBarcodeService = class(TObject)');
    for i := 1 to 550 do
      SB.AppendLine(Format('    F%d: Integer;', [i]));
    SB.AppendLine('  end;');
    SB.AppendLine('implementation');
    SB.AppendLine('end.');
    F := LargeClassFindingsForFile(SB.ToString, '.pas');
    try
      Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkLargeClass),
        'nur die eigene Klasse wird gemeldet, nicht der Bridge-Typ');
      Fnd := TFindingHelper.FirstOf(F, fkLargeClass);
      Assert.IsNotNull(Fnd);
      Assert.AreEqual('TBarcodeService', Fnd.MethodName,
        'gemeldet wird TBarcodeService, nicht JBarcodeReaderClass');
    finally F.Free; end;
  finally
    SB.Free;
  end;
end;

procedure TTestLargeClass.TypelibFile_NotReported;
// Generierter COM-Typelib-Import: die Datei wird bei jedem Refresh
// ueberschrieben, kein Typ darin ist handgeschrieben.
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
    for i := 1 to 550 do
      SB.AppendLine(Format('    F%d: Integer;', [i]));
    SB.AppendLine('  end;');
    SB.AppendLine('implementation');
    SB.AppendLine('end.');
    F := LargeClassFindingsForFile(SB.ToString, '_TLB.pas');
    try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLargeClass),
      'in *_TLB.pas ist kein Refactoring umsetzbar - die Datei wird generiert');
    finally F.Free; end;
  finally
    SB.Free;
  end;
end;

procedure TTestLargeClass.NonTypelibFile_Gegenprobe_Reported;
// Derselbe Quelltext unter normalem Dateinamen MUSS melden.
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
    for i := 1 to 550 do
      SB.AppendLine(Format('    F%d: Integer;', [i]));
    SB.AppendLine('  end;');
    SB.AppendLine('implementation');
    SB.AppendLine('end.');
    F := LargeClassFindingsForFile(SB.ToString, '.pas');
    try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkLargeClass),
      'ohne Typelib-Namensmuster bleibt der Fund');
    finally F.Free; end;
  finally
    SB.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLargeClass);

end.
