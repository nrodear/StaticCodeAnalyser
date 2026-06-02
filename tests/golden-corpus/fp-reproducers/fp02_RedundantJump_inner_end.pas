unit fp02_RedundantJump_inner_end;

// Regression-Test fuer Round 2 (commit 4b7f5cc):
// 'Continue;' direkt vor einem inneren 'end;' (= IF-Block-End innerhalb
// einer Schleife) ist NICHT redundant - es skippt den Rest des Loop-
// Body-Codes. Round-2-Fix prueft via Look-Ahead ob nach dem 'end;'
// wieder ein Block-Terminator kommt; wenn ja flag, wenn nein skip.

interface

implementation

procedure Foo(N: Integer);
var i : Integer;
begin
  for i := 1 to N do
  begin
    if i mod 2 = 0 then
    begin
      WriteLn(i);
      Continue;       // <- MUST NOT trigger SCA080 (skippt das WriteLn unten)
    end;
    WriteLn('odd ', i);
  end;
end;

end.
