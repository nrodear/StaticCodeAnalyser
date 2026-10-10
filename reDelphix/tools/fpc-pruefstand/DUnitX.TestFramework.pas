unit DUnitX.TestFramework;

// Minimal-Ersatz fuer DUnitX, nur fuer den FPC-Pruefstand im Scratchpad.

interface

uses
  SysUtils;

type
  ETestFailure = class(Exception);
  ETestPass = class(Exception);

  Assert = class
  public
    class procedure IsTrue(ACond: Boolean; const AMsg: string = '');
    class procedure IsFalse(ACond: Boolean; const AMsg: string = '');
    class procedure AreEqual(const AExpected, AActual: string;
      const AMsg: string = '');
    class procedure AreEqualInt(AExpected, AActual: Integer;
      const AMsg: string = '');
    class procedure AreNotEqual(const AExpected, AActual: string;
      const AMsg: string = '');
    class procedure AreNotSame(AExpected, AActual: TObject;
      const AMsg: string = '');
    class procedure Pass(const AMsg: string = '');
  end;

  TDUnitX = class
  public
    class procedure RegisterTestFixture(AClass: TClass);
  end;

implementation

class procedure Assert.IsTrue(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise ETestFailure.Create('IsTrue failed. ' + AMsg);
end;

class procedure Assert.IsFalse(ACond: Boolean; const AMsg: string);
begin
  if ACond then
    raise ETestFailure.Create('IsFalse failed. ' + AMsg);
end;

class procedure Assert.AreEqual(const AExpected, AActual: string;
  const AMsg: string);
begin
  if AExpected <> AActual then
    raise ETestFailure.Create('expected <' + AExpected + '> but was <'
      + AActual + '>. ' + AMsg);
end;

class procedure Assert.AreEqualInt(AExpected, AActual: Integer;
  const AMsg: string);
begin
  if AExpected <> AActual then
    raise ETestFailure.Create('expected <' + IntToStr(AExpected)
      + '> but was <' + IntToStr(AActual) + '>. ' + AMsg);
end;

class procedure Assert.AreNotEqual(const AExpected, AActual: string;
  const AMsg: string);
begin
  if AExpected = AActual then
    raise ETestFailure.Create('values are equal <' + AActual + '>. ' + AMsg);
end;

class procedure Assert.AreNotSame(AExpected, AActual: TObject;
  const AMsg: string);
begin
  if AExpected = AActual then
    raise ETestFailure.Create('objects are the same. ' + AMsg);
end;

class procedure Assert.Pass(const AMsg: string);
begin
  raise ETestPass.Create(AMsg);
end;

class procedure TDUnitX.RegisterTestFixture(AClass: TClass);
begin
  // Der Pruefstand ruft die Tests explizit auf.
end;

end.
