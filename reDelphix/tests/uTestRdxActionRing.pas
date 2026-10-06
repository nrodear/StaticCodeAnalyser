unit uTestRdxActionRing;

// Stufe B des Konzepts Editor-Gluehbirne (2026-10-06): der Anbieter gibt
// seine Aktionsobjekte nicht mehr je Provide frei, sondern haelt sie in
// Chargen (eine je Provide) in einem Ring fester Groesse. Hier der Ring
// selbst: Besitz, Chargen, Grenzen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxActionRing = class
  public
    [Test] procedure Batches_OldestFreedBeyondMax;
    [Test] procedure Keep_WithoutBatch_OpensFirstBatch;
    [Test] procedure Destroy_FreesAll;
    [Test] procedure Nil_IsIgnored;
    [Test] procedure MaxBelowOne_IsOne;
  end;

implementation

uses
  uRdxRecipeRunner;

var
  GFreed : Integer = 0;

type
  TCounted = class
  public
    destructor Destroy; override;
  end;

destructor TCounted.Destroy;
begin
  Inc(GFreed);
  inherited;
end;

procedure TTestRdxActionRing.Batches_OldestFreedBeyondMax;
var
  R          : TRdxObjectRing;
  A, B, C, D : TCounted;
begin
  GFreed := 0;
  R := TRdxObjectRing.Create(2);
  try
    // Charge 1: zwei Objekte, Charge 2: eines
    R.BeginBatch; A := TCounted.Create; B := TCounted.Create; R.Keep(A); R.Keep(B);
    R.BeginBatch; C := TCounted.Create; R.Keep(C);
    Assert.AreEqual<Integer>(2, R.BatchCount);
    Assert.AreEqual<Integer>(3, R.Count);
    Assert.AreEqual<Integer>(0, GFreed, 'bis Max Chargen bleibt alles');
    Assert.IsTrue(R.Contains(A) and R.Contains(B) and R.Contains(C));
    // Charge 3 verdraengt Charge 1 samt BEIDEN Objekten - nie nur eines
    // davon, ein Menue haengt an ganzen Chargen. D entsteht VOR dem
    // Verdraengen: sonst bekommt es vom Speichermanager die eben
    // freigegebene Adresse von A, und Contains(A) ist wieder True
    // (TestInsight 2026-10-07, "Condition is True when False expected").
    D := TCounted.Create;
    R.BeginBatch; R.Keep(D);
    Assert.AreEqual<Integer>(2, R.BatchCount);
    Assert.AreEqual<Integer>(2, R.Count);
    Assert.AreEqual<Integer>(2, GFreed);
    // A und B sind frei; der Vergleich ist reiner Adressvergleich, und
    // keine Adresse im Ring kann ihre sein (D und die neue Charge
    // entstanden, als A und B noch lebten).
    Assert.IsFalse(R.Contains(A));
    Assert.IsFalse(R.Contains(B));
    Assert.IsTrue(R.Contains(C) and R.Contains(D));
  finally
    R.Free;
  end;
end;

procedure TTestRdxActionRing.Keep_WithoutBatch_OpensFirstBatch;
var
  R : TRdxObjectRing;
  A : TCounted;
begin
  GFreed := 0;
  R := TRdxObjectRing.Create(3);
  try
    A := TCounted.Create;
    R.Keep(A);
    Assert.AreEqual<Integer>(1, R.BatchCount);
    Assert.IsTrue(R.Contains(A));
  finally
    R.Free;
  end;
  Assert.AreEqual<Integer>(1, GFreed);
end;

procedure TTestRdxActionRing.Destroy_FreesAll;
var
  R : TRdxObjectRing;
begin
  GFreed := 0;
  R := TRdxObjectRing.Create(10);
  try
    R.BeginBatch; R.Keep(TCounted.Create);
    R.BeginBatch; R.Keep(TCounted.Create);
    Assert.AreEqual<Integer>(0, GFreed);
  finally
    R.Free;
  end;
  Assert.AreEqual<Integer>(2, GFreed, 'der Ring gibt beim Freigeben alles frei');
end;

procedure TTestRdxActionRing.Nil_IsIgnored;
var
  R : TRdxObjectRing;
begin
  R := TRdxObjectRing.Create(2);
  try
    R.Keep(nil);
    Assert.AreEqual<Integer>(0, R.Count);
    Assert.IsFalse(R.Contains(nil));
  finally
    R.Free;
  end;
end;

procedure TTestRdxActionRing.MaxBelowOne_IsOne;
var
  R : TRdxObjectRing;
begin
  GFreed := 0;
  R := TRdxObjectRing.Create(0);
  try
    Assert.AreEqual<Integer>(1, R.Max);
    R.BeginBatch; R.Keep(TCounted.Create);
    R.BeginBatch; R.Keep(TCounted.Create);
    Assert.AreEqual<Integer>(1, R.BatchCount);
    Assert.AreEqual<Integer>(1, R.Count);
    Assert.AreEqual<Integer>(1, GFreed);
  finally
    R.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxActionRing);

end.
