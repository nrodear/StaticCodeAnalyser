unit uTestSymbolReferenceIndex;

// Tests fuer TSymbolReferenceIndex - der Cross-Unit-Reference-Index.
// HINWEIS: seit dem Visibility-Detektor-Refactor liest uVisibilityCheck
// den Index NICHT mehr (single-file-only). Die Tests bleiben fuer
// kuenftige Konsumenten und Backwards-Compat erhalten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSymbolReferenceIndex = class
  public
    // ---- AddReference / Lookup -----------------------------------------
    [Test] procedure AddReference_SingleEntry_FoundExternally;
    [Test] procedure AddReference_OwnUnit_NotCountedAsExternal;
    [Test] procedure AddReference_MultipleUnits_ReturnsCount;

    // ---- IsEmpty / Empty-State -----------------------------------------
    [Test] procedure NewIndex_IsEmpty;
    [Test] procedure AfterAddReference_NotEmpty;

    // ---- Member-Extraction (Build-Time) --------------------------------
    [Test] procedure Build_DottedCall_IndexedAsMember;
    [Test] procedure Build_BareCall_NotIndexed;
    [Test] procedure Build_AssignDottedLhs_IndexedAsMember;
    [Test] procedure Build_NestedDottedAccess_RightmostIndexed;

    // ---- Case-Insensitivity --------------------------------------------
    [Test] procedure Lookup_IsCaseInsensitive;

    // ---- Build-Robustheit (graceful degradation) ------------------------
    [Test] procedure Build_NonExistentFile_GracefulNoCrash;
    [Test] procedure Build_NilFileList_GracefulNoCrash;
    [Test] procedure Build_EmptyFileList_StaysEmpty;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  uAstNode, uParser2,
  uSymbolReferenceIndex;

procedure TTestSymbolReferenceIndex.AddReference_SingleEntry_FoundExternally;
var Idx: TSymbolReferenceIndex;
begin
  Idx := TSymbolReferenceIndex.Create;
  try
    Idx.AddReference('Helper', 'other.pas');
    Assert.IsTrue(Idx.HasExternalRefs('helper', 'own.pas'),
      'Helper in other.pas muss von own.pas aus extern sein');
  finally
    Idx.Free;
  end;
end;

procedure TTestSymbolReferenceIndex.AddReference_OwnUnit_NotCountedAsExternal;
var Idx: TSymbolReferenceIndex;
begin
  Idx := TSymbolReferenceIndex.Create;
  try
    Idx.AddReference('Helper', 'own.pas');
    Assert.IsFalse(Idx.HasExternalRefs('helper', 'own.pas'),
      'Selbst-Referenz darf nicht als extern zaehlen');
  finally
    Idx.Free;
  end;
end;

procedure TTestSymbolReferenceIndex.AddReference_MultipleUnits_ReturnsCount;
var Idx: TSymbolReferenceIndex;
begin
  Idx := TSymbolReferenceIndex.Create;
  try
    Idx.AddReference('Helper', 'a.pas');
    Idx.AddReference('Helper', 'b.pas');
    Idx.AddReference('Helper', 'c.pas');
    Assert.AreEqual(3, Idx.ExternalReferencingUnitCount('helper', 'own.pas'));
    Assert.AreEqual(2, Idx.ExternalReferencingUnitCount('helper', 'a.pas'));
  finally
    Idx.Free;
  end;
end;

procedure TTestSymbolReferenceIndex.NewIndex_IsEmpty;
var Idx: TSymbolReferenceIndex;
begin
  Idx := TSymbolReferenceIndex.Create;
  try Assert.IsTrue(Idx.IsEmpty);
  finally Idx.Free; end;
end;

procedure TTestSymbolReferenceIndex.AfterAddReference_NotEmpty;
var Idx: TSymbolReferenceIndex;
begin
  Idx := TSymbolReferenceIndex.Create;
  try
    Idx.AddReference('X', 'u.pas');
    Assert.IsFalse(Idx.IsEmpty);
  finally Idx.Free; end;
end;

// Helper: schreibt SRC in Temp, baut den Index ueber die einzelne Datei.
function BuildIndexOver(const SRC: string; out TempFile: string)
  : TSymbolReferenceIndex;
var
  FL : TStringList;
begin
  TempFile := TPath.Combine(TPath.GetTempPath,
    'sca_sri_' + TGuid.NewGuid.ToString.Replace('{','').Replace('}','').Replace('-','')
    + '.pas');
  TFile.WriteAllText(TempFile, SRC, TEncoding.UTF8);
  Result := TSymbolReferenceIndex.Create;
  FL := TStringList.Create;
  try
    FL.Add(TempFile);
    Result.Build(FL);
  finally
    FL.Free;
  end;
end;

procedure TTestSymbolReferenceIndex.Build_DottedCall_IndexedAsMember;
// `Foo.DoStuff;` -> Member 'DoStuff' wird indexed.
const SRC =
  'unit u; implementation'#13#10 +
  'procedure Run;'#13#10 +
  'var Foo: TObject;'#13#10 +
  'begin Foo.DoStuff; end;';
var
  Idx : TSymbolReferenceIndex;
  Tmp : string;
begin
  Idx := BuildIndexOver(SRC, Tmp);
  try
    Assert.IsTrue(Idx.HasExternalRefs('dostuff', 'other.pas'),
      'DoStuff sollte als Member-Referenz indexiert sein');
  finally
    Idx.Free;
    if TFile.Exists(Tmp) then TFile.Delete(Tmp);
  end;
end;

procedure TTestSymbolReferenceIndex.Build_BareCall_NotIndexed;
// `DoStuff;` ohne Dot - kein Member-Access, also NICHT indexiert
// (sonst wuerde jeder top-level Procedure-Aufruf als 'externer
// Member-Caller' zaehlen -> zu viele false-negatives bei der Visibility).
const SRC =
  'unit u; implementation'#13#10 +
  'procedure Run;'#13#10 +
  'begin DoStuff; end;';
var
  Idx : TSymbolReferenceIndex;
  Tmp : string;
begin
  Idx := BuildIndexOver(SRC, Tmp);
  try
    Assert.IsFalse(Idx.HasExternalRefs('dostuff', 'other.pas'),
      'Bare Call ohne Dot darf nicht als Member-Referenz zaehlen');
  finally
    Idx.Free;
    if TFile.Exists(Tmp) then TFile.Delete(Tmp);
  end;
end;

procedure TTestSymbolReferenceIndex.Build_AssignDottedLhs_IndexedAsMember;
// `Foo.Field := X` -> Member 'Field' wird indexed.
const SRC =
  'unit u; implementation'#13#10 +
  'procedure Run;'#13#10 +
  'var Foo: TObject;'#13#10 +
  'begin Foo.Field := 42; end;';
var
  Idx : TSymbolReferenceIndex;
  Tmp : string;
begin
  Idx := BuildIndexOver(SRC, Tmp);
  try
    Assert.IsTrue(Idx.HasExternalRefs('field', 'other.pas'));
  finally
    Idx.Free;
    if TFile.Exists(Tmp) then TFile.Delete(Tmp);
  end;
end;

procedure TTestSymbolReferenceIndex.Build_NestedDottedAccess_RightmostIndexed;
// `A.B.C.D;` -> nur D wird indexed (rightmost-Member). Wichtig: weder
// A, B noch C dürfen den Index "verschmutzen".
const SRC =
  'unit u; implementation'#13#10 +
  'procedure Run;'#13#10 +
  'var A: TObject;'#13#10 +
  'begin A.B.C.D; end;';
var
  Idx : TSymbolReferenceIndex;
  Tmp : string;
begin
  Idx := BuildIndexOver(SRC, Tmp);
  try
    Assert.IsTrue(Idx.HasExternalRefs('d', 'other.pas'));
    Assert.IsFalse(Idx.HasExternalRefs('a', 'other.pas'),
      'Linkester Ausdruck darf nicht indexiert sein');
    Assert.IsFalse(Idx.HasExternalRefs('b', 'other.pas'),
      'Mittlerer Ausdruck darf nicht indexiert sein');
  finally
    Idx.Free;
    if TFile.Exists(Tmp) then TFile.Delete(Tmp);
  end;
end;

procedure TTestSymbolReferenceIndex.Lookup_IsCaseInsensitive;
var Idx: TSymbolReferenceIndex;
begin
  Idx := TSymbolReferenceIndex.Create;
  try
    Idx.AddReference('HelperFunc', 'u.pas');
    Assert.IsTrue(Idx.HasExternalRefs('helperfunc', 'own.pas'));
    Assert.IsTrue(Idx.HasExternalRefs('HELPERFUNC', 'own.pas'));
    Assert.IsTrue(Idx.HasExternalRefs('HelperFUNC', 'own.pas'));
  finally Idx.Free; end;
end;

procedure TTestSymbolReferenceIndex.Build_NonExistentFile_GracefulNoCrash;
// Build muss bei nicht-existierender Datei nicht crashen - sondern
// die Datei silent skippen (analog uDfmRepoIndex). Wir prufen das,
// indem der Index hinterher leer ist.
var
  Idx : TSymbolReferenceIndex;
  FL  : TStringList;
begin
  Idx := TSymbolReferenceIndex.Create;
  FL := TStringList.Create;
  try
    FL.Add('C:\does\not\exist\xyz123.pas');
    Idx.Build(FL);   // darf nicht raisen
    Assert.IsTrue(Idx.IsEmpty,
      'Non-existent file darf keine Eintraege erzeugen');
  finally
    FL.Free;
    Idx.Free;
  end;
end;

procedure TTestSymbolReferenceIndex.Build_NilFileList_GracefulNoCrash;
var Idx: TSymbolReferenceIndex;
begin
  Idx := TSymbolReferenceIndex.Create;
  try
    Idx.Build(nil);   // darf nicht raisen
    Assert.IsTrue(Idx.IsEmpty);
  finally
    Idx.Free;
  end;
end;

procedure TTestSymbolReferenceIndex.Build_EmptyFileList_StaysEmpty;
var
  Idx : TSymbolReferenceIndex;
  FL  : TStringList;
begin
  Idx := TSymbolReferenceIndex.Create;
  FL := TStringList.Create;
  try
    Idx.Build(FL);
    Assert.IsTrue(Idx.IsEmpty);
    Assert.IsFalse(Idx.HasExternalRefs('anything', 'own.pas'));
  finally
    FL.Free;
    Idx.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSymbolReferenceIndex);

end.
