unit uTestRdxActionRing;

// Stufe B des Konzepts Editor-Gluehbirne (2026-10-06): der Anbieter gibt
// seine Aktionsobjekte nicht mehr je Provide frei, sondern haelt sie in
// einem Ring fester Groesse. Hier der Ring selbst: Besitz, Reihenfolge,
// Grenzen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxActionRing = class
  public
    [Test] procedure Keep_FreesOldestBeyondMax;
    [Test] procedure Destroy_FreesAll;
    [Test] procedure Nil_IsIgnored;
    [Test] procedure MaxBelowOne_IsOne;
  end;

implementation

uses
  System.SysUtils,
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

procedure TTestRdxActionRing.Keep_FreesOldestBeyondMax;
var
  R          : TRdxObjectRing;
  A, B, C, D : TCounted;
begin
  GFreed := 0;
  R := TRdxObjectRing.Create(3);
  try
    A := TCounted.Create; B := TCounted.Create;
    C := TCounted.Create; D := TCounted.Create;
    R.Keep(A); R.Keep(B); R.Keep(C);
    Assert.AreEqual<Integer>(3, R.Count);
    Assert.AreEqual<Integer>(0, GFreed, 'bis Max bleibt alles');
    Assert.IsTrue(R.Contains(A));
    R.Keep(D);
    Assert.AreEqual<Integer>(3, R.Count);
    Assert.AreEqual<Integer>(1, GFreed, 'das aelteste faellt heraus und wird frei');
    Assert.IsFalse(R.Contains(A));
    Assert.IsTrue(R.Contains(B) and R.Contains(C) and R.Contains(D));
  finally
    R.Free;
  end;
end;

procedure TTestRdxActionRing.Destroy_FreesAll;
var
  R : TRdxObjectRing;
begin
  GFreed := 0;
  R := TRdxObjectRing.Create(10);
  try
    R.Keep(TCounted.Create);
    R.Keep(TCounted.Create);
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
    R.Keep(TCounted.Create);
    R.Keep(TCounted.Create);
    Assert.AreEqual<Integer>(1, R.Count);
    Assert.AreEqual<Integer>(1, GFreed);
  finally
    R.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxActionRing);

end.
