unit HashStub;

// Stub fuer System.Hash im FPC-Pruefstand. KEIN SHA256 - nur ein
// deterministischer 64-Zeichen-Hexwert (MD5 ueber Text und ueber
// umgedrehten Text), damit die Hash-Tests der Logik laufen.

interface

type
  THashSHA2 = class
  public
    class function GetHashString(const AString: string): string;
  end;

implementation

uses
  SysUtils, md5;

class function THashSHA2.GetHashString(const AString: string): string;
var
  A, R : AnsiString;
  i    : Integer;
begin
  A := UTF8Encode(AString);
  SetLength(R, Length(A));
  for i := 1 to Length(A) do
    R[i] := A[Length(A) - i + 1];
  Result := string(MD5Print(MD5String(A)) + MD5Print(MD5String(R + '#')));
end;

end.
