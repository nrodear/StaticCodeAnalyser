unit fp03_PublicField_multiline_method;

// Regression-Test fuer Round 3 (commit 68de1d3) + Round 13 (commit 4a7f1c6):
// Multi-line Method-Header-Continuation-Zeilen mit ')' am Ende duerfen
// NICHT als public Field geflaggt werden. Detector-Filter: ')' irgendwo
// in der Zeile -> kein Field-Decl.

interface

uses
  System.Generics.Collections;

type
  TDummy = class
  public
    class procedure AnalyzeWithLongSignature(const FileName: string;
      Results: TList<Integer>);                  // <- MUST NOT trigger SCA089
    class function ComputeFromTwoArgs(const A: Integer;
      const B: Integer): Integer;                // <- MUST NOT trigger SCA089
  end;

implementation

class procedure TDummy.AnalyzeWithLongSignature(const FileName: string;
  Results: TList<Integer>);
begin
end;

class function TDummy.ComputeFromTwoArgs(const A: Integer;
  const B: Integer): Integer;
begin
  Result := A + B;
end;

end.
