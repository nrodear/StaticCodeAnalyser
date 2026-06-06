unit uTestFindingFingerprint;

// Tests fuer uFindingFingerprint (Phase-1-Quick-Win C.2).
// Pruefen:
//   * Snippet-Normalisierung ist stabil gegen Whitespace/Indent-Aenderungen
//   * Hash gleicher Code-Snippets in zwei Files ist identisch
//   * Hash bei Code-Aenderung unterschiedlich
//   * Empty/Missing-File liefert leeren Hash
//   * Baseline matched ueber contextHash auch nach Line-Drift

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.IOUtils,
  System.Generics.Collections,
  uMethodd12, uSCAConsts, uFindingFingerprint, uBaseline;

type
  [TestFixture]
  TTestFindingFingerprint = class
  strict private
    function WriteTempPas(const Body: string): string;
    function MakeFinding(const FileName: string; LineNo: Integer): TLeakFinding;
  public
    [Test] procedure Normalize_StripsLeadingAndTrailingWS;
    [Test] procedure Normalize_CollapsesWhitespaceRuns;
    [Test] procedure Normalize_DropsEmptyLines;
    [Test] procedure Normalize_TabsEqualToSpaces;

    [Test] procedure ContextHash_SameSnippetEqualHash;
    [Test] procedure ContextHash_DifferentSnippetDifferentHash;
    [Test] procedure ContextHash_MissingFileReturnsEmpty;
    [Test] procedure ContextHash_StableAgainstReIndent;

    [Test] procedure Baseline_MatchesViaContextHashAfterLineDrift;
    [Test] procedure Baseline_FallbackToLegacyFingerprintForOldBaseline;
  end;

implementation

uses
  System.JSON;

{ Helpers }

function TTestFindingFingerprint.WriteTempPas(const Body: string): string;
begin
  Result := TPath.Combine(TPath.GetTempPath,
    'sca_fp_' + TGuid.NewGuid.ToString.Replace('{','').Replace('}','') + '.pas');
  TFile.WriteAllText(Result, Body, TEncoding.UTF8);
end;

function TTestFindingFingerprint.MakeFinding(const FileName: string;
  LineNo: Integer): TLeakFinding;
begin
  Result := TLeakFinding.Create;
  Result.Kind       := fkMagicNumber;
  Result.Severity   := lsHint;
  Result.FileName   := FileName;
  Result.LineNumber := IntToStr(LineNo);
  Result.MethodName := 'TestMethod';
  Result.MissingVar := '42';
end;

{ Normalize-Tests }

procedure TTestFindingFingerprint.Normalize_StripsLeadingAndTrailingWS;
begin
  Assert.AreEqual('foo',
    TFindingFingerprint.Normalize('   foo   '));
  Assert.AreEqual('foo'#10'bar',
    TFindingFingerprint.Normalize('  foo  '#13#10'  bar  '));
end;

procedure TTestFindingFingerprint.Normalize_CollapsesWhitespaceRuns;
begin
  Assert.AreEqual('a b c',
    TFindingFingerprint.Normalize('a    b      c'));
end;

procedure TTestFindingFingerprint.Normalize_DropsEmptyLines;
begin
  Assert.AreEqual('x'#10'y',
    TFindingFingerprint.Normalize('x'#13#10''#13#10''#13#10'y'));
end;

procedure TTestFindingFingerprint.Normalize_TabsEqualToSpaces;
begin
  Assert.AreEqual(
    TFindingFingerprint.Normalize('a'#9'b'),
    TFindingFingerprint.Normalize('a b'));
end;

{ ContextHash-Tests }

procedure TTestFindingFingerprint.ContextHash_SameSnippetEqualHash;
var
  Body  : string;
  F1,F2 : string;
  H1,H2 : string;
begin
  Body :=
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'begin'#13#10 +
    '  X := 42;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
  F1 := WriteTempPas(Body);
  F2 := WriteTempPas(Body);
  try
    H1 := TFindingFingerprint.ContextHashFor(F1, 6);
    H2 := TFindingFingerprint.ContextHashFor(F2, 6);
    Assert.AreNotEqual('', H1);
    Assert.AreEqual(H1, H2, 'gleicher Code -> gleicher Hash');
  finally
    TFile.Delete(F1); TFile.Delete(F2);
  end;
end;

procedure TTestFindingFingerprint.ContextHash_DifferentSnippetDifferentHash;
var
  A,B   : string;
  HA,HB : string;
begin
  A := WriteTempPas('a'#13#10'b'#13#10'X := 42;'#13#10'd'#13#10'e'#13#10);
  B := WriteTempPas('a'#13#10'b'#13#10'X := 99;'#13#10'd'#13#10'e'#13#10);
  try
    HA := TFindingFingerprint.ContextHashFor(A, 3);
    HB := TFindingFingerprint.ContextHashFor(B, 3);
    Assert.AreNotEqual('', HA);
    Assert.AreNotEqual('', HB);
    Assert.AreNotEqual(HA, HB);
  finally
    TFile.Delete(A); TFile.Delete(B);
  end;
end;

procedure TTestFindingFingerprint.ContextHash_MissingFileReturnsEmpty;
begin
  Assert.AreEqual('',
    TFindingFingerprint.ContextHashFor('C:\nope\nope\nope.pas', 5));
  Assert.AreEqual('',
    TFindingFingerprint.ContextHashFor('', 5));
end;

procedure TTestFindingFingerprint.ContextHash_StableAgainstReIndent;
var
  Tight, Loose : string;
  HTight, HLoose : string;
begin
  Tight := WriteTempPas(
    'unit u;'#13#10 +
    'procedure P;'#13#10 +
    'begin'#13#10 +
    'X := 42;'#13#10 +
    'end;'#13#10);
  Loose := WriteTempPas(
    'unit u;'#13#10 +
    'procedure P;'#13#10 +
    'begin'#13#10 +
    '      X := 42;'#13#10 +     // re-indented mit Spaces
    'end;'#13#10);
  try
    HTight := TFindingFingerprint.ContextHashFor(Tight, 4);
    HLoose := TFindingFingerprint.ContextHashFor(Loose, 4);
    Assert.AreEqual(HTight, HLoose,
      'Re-Indent darf den Hash nicht aendern');
  finally
    TFile.Delete(Tight); TFile.Delete(Loose);
  end;
end;

{ Baseline-Integration-Tests }

procedure TTestFindingFingerprint.Baseline_MatchesViaContextHashAfterLineDrift;
// Szenario:
//   1. V1, Finding auf Zeile 8 (Y := 42) -> Baseline schreiben
//   2. V2 enthaelt 5 zusaetzliche Header-Zeilen + Method renamed
//      -> Finding wandert auf Zeile 13, Method 'P'->'Q'
//      -> legacy fingerprint matched NICHT (Method-Name in Hash)
//   3. Snippet (+/- 3 Zeilen um die jeweilige Fund-Zeile) ist IDENTISCH -
//      Method-Header liegt ausserhalb des Radius -> contextHash matched
//   4. Apply muss Finding via contextHash droppen
const
  V1_BODY =
    'unit u;'#13#10 +              // 1
    'interface'#13#10 +            // 2
    'implementation'#13#10 +       // 3
    'procedure P;'#13#10 +         // 4   (Header ausserhalb 8 +/- 3)
    'begin'#13#10 +                // 5   (= 8 - 3)
    '  // padding'#13#10 +         // 6
    '  // padding'#13#10 +         // 7
    '  Y := 42;'#13#10 +           // 8   <- Finding
    '  Z := 7;'#13#10 +            // 9
    '  // padding'#13#10 +         // 10
    '  // padding'#13#10 +         // 11  (= 8 + 3)
    'end;'#13#10 +                 // 12  (ausserhalb)
    'end.'#13#10;                  // 13
  V2_BODY =
    '// generated header'#13#10 +  // 1   (NEU)
    '// generated header'#13#10 +  // 2   (NEU)
    '// generated header'#13#10 +  // 3   (NEU)
    ''#13#10 +                     // 4   (NEU)
    ''#13#10 +                     // 5   (NEU)
    'unit u;'#13#10 +              // 6
    'interface'#13#10 +            // 7
    'implementation'#13#10 +       // 8
    'procedure Q;'#13#10 +         // 9   <- RENAMED P->Q (ausserhalb 13+/-3)
    'begin'#13#10 +                // 10  (= 13 - 3)
    '  // padding'#13#10 +         // 11
    '  // padding'#13#10 +         // 12
    '  Y := 42;'#13#10 +           // 13  <- gleiches Finding hier
    '  Z := 7;'#13#10 +            // 14
    '  // padding'#13#10 +         // 15
    '  // padding'#13#10 +         // 16  (= 13 + 3)
    'end;'#13#10 +                 // 17  (ausserhalb)
    'end.'#13#10;                  // 18
var
  File1    : string;
  Baseline : string;
  List     : TObjectList<TLeakFinding>;
  Dropped  : Integer;
  F1, F2   : TLeakFinding;
begin
  File1    := WriteTempPas(V1_BODY);
  Baseline := File1 + '.baseline.json';
  try
    // V1: Finding auf Zeile 8
    List := TObjectList<TLeakFinding>.Create(True);
    try
      F1 := MakeFinding(File1, 8);
      F1.MethodName := 'P';
      List.Add(F1);
      TBaseline.Write(List, Baseline);
    finally
      List.Free;
    end;

    // V2: gleiche Datei ueberschrieben, jetzt Zeile 13 + renamed method
    TFile.WriteAllText(File1, V2_BODY, TEncoding.UTF8);
    List := TObjectList<TLeakFinding>.Create(True);
    try
      F2 := MakeFinding(File1, 13);
      F2.MethodName := 'Q';    // <- legacy fingerprint matched NICHT mehr
      List.Add(F2);

      Dropped := TBaseline.Apply(List, Baseline);
      Assert.AreEqual<Integer>(1, Dropped,
        'contextHash sollte Finding trotz Line-Drift + Method-Rename matchen');
      Assert.AreEqual<Integer>(0, List.Count);
    finally
      List.Free;
    end;
  finally
    if TFile.Exists(File1)    then TFile.Delete(File1);
    if TFile.Exists(Baseline) then TFile.Delete(Baseline);
  end;
end;

procedure TTestFindingFingerprint.Baseline_FallbackToLegacyFingerprintForOldBaseline;
// Szenario: alte Baseline ohne contextHash-Key. Apply muss trotzdem matchen
// solange File+Kind+Method+Detail uebereinstimmen.
var
  File1    : string;
  Baseline : string;
  Raw      : string;
  Root     : TJSONObject;
  Arr      : TJSONArray;
  Obj      : TJSONObject;
  List     : TObjectList<TLeakFinding>;
  F        : TLeakFinding;
  Dropped  : Integer;
begin
  File1    := WriteTempPas('unit x;'#13#10'end.');
  Baseline := File1 + '.baseline.json';
  try
    // Hand-crafted ALTES Baseline-Format ohne contextHash
    F := MakeFinding(File1, 1);
    try
      Root := TJSONObject.Create;
      Arr  := TJSONArray.Create;
      Obj  := TJSONObject.Create;
      Obj.AddPair('file',        ExtractFileName(F.FileName));
      Obj.AddPair('kind',        KindName(F.Kind));
      Obj.AddPair('method',      F.MethodName);
      Obj.AddPair('detail',      F.MissingVar);
      Obj.AddPair('line',        F.LineNumber);
      Obj.AddPair('fingerprint', TBaseline.Fingerprint(F));
      Arr.AddElement(Obj);
      Root.AddPair('findings', Arr);
      Raw := Root.ToString;
      Root.Free;
      TFile.WriteAllText(Baseline, Raw, TEncoding.UTF8);
    finally
      F.Free;
    end;

    List := TObjectList<TLeakFinding>.Create(True);
    try
      List.Add(MakeFinding(File1, 1));
      Dropped := TBaseline.Apply(List, Baseline);
      Assert.AreEqual<Integer>(1, Dropped,
        'altes Baseline-Format muss weiter funktionieren (backward-compat)');
    finally
      List.Free;
    end;
  finally
    if TFile.Exists(File1)    then TFile.Delete(File1);
    if TFile.Exists(Baseline) then TFile.Delete(Baseline);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFindingFingerprint);

end.
