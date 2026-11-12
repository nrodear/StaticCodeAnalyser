unit uTestFixArgs;

// T1 (Konzept_FixDatenfeld_2026-10-28.md, Abschnitt 6): TFixArgs
// (uFixArgs) selbst, ohne TLeakFinding - FPC-Pruefstand-faehig (haengt nur
// an SysUtils).

interface

uses
  DUnitX.TestFramework,
  uFixArgs;

type
  [TestFixture]
  TTestFixArgs = class
  public
    [Test] procedure Fresh_IsEmpty;
    [Test] procedure Put_ThenTryGet_ReturnsValue;
    [Test] procedure TryGet_UnknownKey_ReturnsFalse;
    [Test] procedure Get_UnknownKey_ReturnsDefault;
    [Test] procedure Put_SameKeyTwice_Overwrites;
    [Test] procedure Col_ZeroMeansUnset;
    [Test] procedure Put_OnCopy_LeavesOriginalUntouched;
    [Test] procedure SameAs_OrderIndependent;
    [Test] procedure SameAs_DifferentValue_IsFalse;
    [Test] procedure SameAs_DifferentCol_IsFalse;
  end;

implementation

procedure TTestFixArgs.Fresh_IsEmpty;
var
  A: TFixArgs;
begin
  // Default(TFixArgs) ausdruecklich: ein lokaler Record zeroed nur seine
  // VERWALTETEN Felder (Pairs) automatisch, Col (Integer) nicht - anders
  // als ein Klassenfeld (TLeakFinding.FixArgs), das TObject.Create per
  // Speicherzuteilung zuverlaessig nullt. Ohne Default(..) stand Col unter
  // FPC auf Stack-Resten, nicht auf 0 (hier belegt).
  A := Default(TFixArgs);
  Assert.IsTrue(A.IsEmpty);
  Assert.AreEqual<Integer>(0, A.Col);
end;

procedure TTestFixArgs.Put_ThenTryGet_ReturnsValue;
var
  A: TFixArgs;
  V: string;
begin
  A.Put(FA_NAME, 'Foo');
  Assert.IsTrue(A.TryGet(FA_NAME, V));
  Assert.AreEqual('Foo', V);
  Assert.IsFalse(A.IsEmpty);
end;

procedure TTestFixArgs.TryGet_UnknownKey_ReturnsFalse;
var
  A: TFixArgs;
  V: string;
begin
  A.Put(FA_NAME, 'Foo');
  Assert.IsFalse(A.TryGet(FA_TYPE, V));
  Assert.AreEqual('', V);
end;

procedure TTestFixArgs.Get_UnknownKey_ReturnsDefault;
var
  A: TFixArgs;
begin
  Assert.AreEqual('fallback', A.Get(FA_NAME, 'fallback'));
  Assert.AreEqual('', A.Get(FA_NAME));
end;

procedure TTestFixArgs.Put_SameKeyTwice_Overwrites;
var
  A: TFixArgs;
  V: string;
begin
  A.Put(FA_NAME, 'Foo');
  A.Put(FA_NAME, 'Bar');
  Assert.IsTrue(A.TryGet(FA_NAME, V));
  Assert.AreEqual('Bar', V);
  Assert.AreEqual<Integer>(2, Length(A.Pairs), 'kein zweites Paar angehaengt');
end;

procedure TTestFixArgs.Col_ZeroMeansUnset;
var
  A: TFixArgs;
begin
  A.Col := 5;
  Assert.AreEqual<Integer>(5, A.Col);
  Assert.IsFalse(A.IsEmpty);
end;

procedure TTestFixArgs.Put_OnCopy_LeavesOriginalUntouched;
var
  Original, Clone: TFixArgs;
  V: string;
begin
  Original.Put(FA_NAME, 'Foo');
  Clone := Original;             // Record-Zuweisung: teilt Pairs zunaechst
  Clone.Put(FA_NAME, 'Changed');  // copy-on-write darf Original nicht treffen
  Assert.IsTrue(Original.TryGet(FA_NAME, V));
  Assert.AreEqual('Foo', V, 'Original durch Put am Klon veraendert');
  Assert.IsTrue(Clone.TryGet(FA_NAME, V));
  Assert.AreEqual('Changed', V);
end;

procedure TTestFixArgs.SameAs_OrderIndependent;
var
  A, B: TFixArgs;
begin
  // Col unangetastet lassen hiesse: zwei verschiedene Stack-Reste
  // vergleichen (s. Fresh_IsEmpty) - SameAs vergleicht Col zuerst.
  A := Default(TFixArgs);
  B := Default(TFixArgs);
  A.Put(FA_NAME, 'Foo');
  A.Put(FA_TYPE, 'Integer');
  B.Put(FA_TYPE, 'Integer');
  B.Put(FA_NAME, 'Foo');
  Assert.IsTrue(A.SameAs(B));
  Assert.IsTrue(B.SameAs(A));
end;

procedure TTestFixArgs.SameAs_DifferentValue_IsFalse;
var
  A, B: TFixArgs;
begin
  A := Default(TFixArgs);
  B := Default(TFixArgs);
  A.Put(FA_NAME, 'Foo');
  B.Put(FA_NAME, 'Bar');
  Assert.IsFalse(A.SameAs(B));
end;

procedure TTestFixArgs.SameAs_DifferentCol_IsFalse;
var
  A, B: TFixArgs;
begin
  A.Col := 1;
  B.Col := 2;
  Assert.IsFalse(A.SameAs(B));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFixArgs);

end.
