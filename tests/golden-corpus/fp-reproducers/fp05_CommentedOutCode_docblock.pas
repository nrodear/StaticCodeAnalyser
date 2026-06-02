unit fp05_CommentedOutCode_docblock;

// Regression-Test fuer Round 13 (commit 4a7f1c6):
// Mehrzeilige '//'-Kommentar-Bloecke mit Pascal-Code-Beispielen als
// Dokumentation duerfen NICHT als commented-out Code geflaggt werden.
// Detector-Heuristik IsPrevLineLineComment: //-Kommentar in
// Multi-Line-Block (= Vorzeile auch //) -> skip.
//
// Beispiele die FRUEHER getriggert haetten (vor Round 13):
//   Pattern: avoid
//     for i := 1 to N do
//       X := X + 1;
//     end;
//   Korrekt: vorher Capacity setzen
//     X.Capacity := N;
//     for i := 1 to N do
//       X[i] := i;

interface

implementation

procedure Foo;
begin
  WriteLn('ok');
end;

end.
