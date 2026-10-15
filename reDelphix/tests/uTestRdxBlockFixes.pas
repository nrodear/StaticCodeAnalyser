unit uTestRdxBlockFixes;

// Editorhilfe SCA101/SCA099 (TRdxStructFixes.WrapInBlock) auf Text - ohne
// Parser, ohne Detektor (laeuft in reDelphix.Test UND im FPC-Pruefstand):
// die Anweisung hinter then/else/do in begin..end - eigene Zeilen, Zeile
// aufteilen, inline; if-else (dangling else), else von case und except
// (Anweisungsliste), bedingter Ausdruck (Delphi 13), anonyme Methode,
// Direktive. Eigene Unit neben uTestRdxStructFixes: der FPC-Pruefstand
// kennt nur eine Fixture je Unit, und eine Klasse fuer beides waere zu
// gross (SCA138). Die Gegenprobe mit dem echten Detektor steht in
// uTestRdxSimpleFixesDetector (Fixture 5, nur Delphi).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxBlockFixes = class
  public
    [Test] procedure Sca101_OwnLines;
    [Test] procedure Sca101_SplitLine;
    [Test] procedure Sca101_Inline;
    [Test] procedure Sca101_IfElse;
    [Test] procedure Sca101_ListElse;
    [Test] procedure Sca101_Refusals;
    [Test] procedure Sca099_EndElse;
    // Gegen-Review 2026-10-10: Kopf einer anonymen Methode vor dem else,
    // Ablehnungen ohne Test, repeat/Kommentar/On/'{$' im '//'-Kommentar.
    [Test] procedure Sca101_AnonMethodHeader;
    [Test] procedure Sca101_ReviewRefusals;
    [Test] procedure Sca101_ReviewForms;
  end;

implementation

uses
  System.Classes,
  uRdxBufferMath, uRdxCodeMap, uRdxStructFixes,
  uTestRdxTextKit;   // Join, Apply

// ---- Helfer ----

// SCA101/SCA099: neuer Text oder '' bei Ablehnung (AReason). AWord <> '':
// das Schluesselwort an der Spalte, an der AWord in Zeile ALine zuerst
// steht (SCA101 - AWord darf mehr tragen, etwa 'else Z'); AWord = '': das
// else hinter dem 'end else' auf ALine (SCA099).
function FixBlock(const ASource: string; ALine: Integer; const AWord: string;
  out AReason: string): string;
var
  SL    : TStringList;
  Map   : TRdxCodeMap;
  Kw    : TRdxToken;
  Edits : TArray<TRdxEdit>;
  Found : Boolean;
begin
  Result := '';
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    if AWord = '' then
      Found := TRdxStructFixes.ElseAfterEndOn(Map, ALine, Kw, AReason)
    else
      Found := TRdxStructFixes.BranchKeywordAt(Map, ALine,
        Pos(AWord, SL[ALine - 1]), Kw, AReason);
    if Found and TRdxStructFixes.WrapInBlock(Map, Kw, Edits, AReason) then
      Result := Apply(ASource, Edits);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Anweisungen ab Zeile 4 in einer Routine.
function InProc(const ALines: array of string): string;
begin
  Result := Join(['unit u;', 'implementation', 'procedure P;']) + #13#10
    + 'begin' + #13#10 + Join(ALines) + #13#10 + Join(['end;', 'end.']);
end;

// ---- SCA101 / SCA099 ----

procedure TTestRdxBlockFixes.Sca101_OwnLines;
var
  R : string;
begin
  Assert.AreEqual(InProc(['  if A then', '  begin', '    X;', '  end;']),
    FixBlock(InProc(['  if A then', '    X;']), 5, 'then', R), R);
  // then vor einem else: das ';' kommt in den Block, das end bekommt keines.
  Assert.AreEqual(InProc(['  if A then', '  begin', '    X;', '  end', '  else',
      '    Y;']),
    FixBlock(InProc(['  if A then', '    X', '  else', '    Y;']), 5, 'then', R), R);
  Assert.AreEqual(InProc(['  if A then', '    X', '  else', '  begin', '    Y;',
      '  end;']),
    FixBlock(InProc(['  if A then', '    X', '  else', '    Y;']), 7, 'else', R), R);
  // Kommentare bleiben, wo sie waren; Kommentarzeilen kommen in den Block.
  Assert.AreEqual(InProc(['  if A then // warum', '  begin', '    // Kommentar',
      '    X; // hinten', '  end;']),
    FixBlock(InProc(['  if A then // warum', '    // Kommentar',
      '    X; // hinten']), 5, 'then', R), R);
  // Vor dem end des umgebenden Blocks ohne ';'.
  Assert.AreEqual(InProc(['  if A then', '  begin', '    X;', '  end']),
    FixBlock(InProc(['  if A then', '    X']), 5, 'then', R), R);
  // do: eingerueckt wie die Zeile des for, nicht wie die des do.
  Assert.AreEqual(InProc(['  for I := 0 to', '      N do', '  begin', '    X;',
      '  end;']),
    FixBlock(InProc(['  for I := 0 to', '      N do', '    X;']), 6, 'do', R), R);
  Assert.AreEqual(InProc([#9'while A do', #9'begin', #9#9'X;', #9'end;']),
    FixBlock(InProc([#9'while A do', #9#9'X;']), 5, 'do', R), R);
end;

procedure TTestRdxBlockFixes.Sca101_SplitLine;
var
  R : string;
begin
  // Das Katalog-Beispiel.
  Assert.AreEqual(InProc(['  if Active then', '  begin', '    DoStuff;', '  end;']),
    FixBlock(InProc(['  if Active then DoStuff;']), 5, 'then', R), R);
  // Ein else auf der Zeile beginnt eine neue.
  Assert.AreEqual(InProc(['  if A then', '  begin', '    X;', '  end', '  else Y;']),
    FixBlock(InProc(['  if A then X else Y;']), 5, 'then', R), R);
  Assert.AreEqual(InProc(['  if A then X else', '  begin', '    Y;', '  end;']),
    FixBlock(InProc(['  if A then X else Y;']), 5, 'else', R), R);
  // Ein Kommentar davor bleibt bei der Anweisung, einer dahinter beim end.
  Assert.AreEqual(InProc(['  if A then', '  begin', '    {c} X;', '  end; // d']),
    FixBlock(InProc(['  if A then {c} X; // d']), 5, 'then', R), R);
  // on ... do im except: eingerueckt wie die on-Zeile.
  Assert.AreEqual(InProc(['  try', '    X;', '  except', '    on E: Exception do',
      '    begin', '      Y;', '    end;', '  end;']),
    FixBlock(InProc(['  try', '    X;', '  except', '    on E: Exception do Y;',
      '  end;']), 8, 'do', R), R);
end;

procedure TTestRdxBlockFixes.Sca101_Inline;
var
  R : string;
begin
  // Code hinter der Anweisung auf der Zeile.
  Assert.AreEqual(InProc(['  if A then begin X; end; Y;']),
    FixBlock(InProc(['  if A then X; Y;']), 5, 'then', R), R);
  // Mehrzeilige Anweisung ab der Zeile des then.
  Assert.AreEqual(InProc(['  if A then begin Foo(1,', '    2); end;']),
    FixBlock(InProc(['  if A then Foo(1,', '    2);']), 5, 'then', R), R);
  Assert.AreEqual(InProc(['  repeat if A then begin X; end until B;']),
    FixBlock(InProc(['  repeat if A then X until B;']), 5, 'then', R), R);
  // then am Zeilenende, hinter der Anweisung folgt das else.
  Assert.AreEqual(InProc(['  if A then', '    begin X; end else Y;']),
    FixBlock(InProc(['  if A then', '    X else Y;']), 5, 'then', R), R);
end;

procedure TTestRdxBlockFixes.Sca101_IfElse;
var
  R : string;
begin
  // Dangling else: es gehoert zum inneren if.
  Assert.AreEqual(InProc(['  if A then if B then X else', '  begin', '    Y;',
      '  end;']),
    FixBlock(InProc(['  if A then if B then X else Y;']), 5, 'else', R), R);
  // Das zweite else gehoert zum aeusseren if.
  Assert.AreEqual(InProc(['  if A then if B then X else Y else', '  begin',
      '    Z;', '  end;']),
    FixBlock(InProc(['  if A then if B then X else Y else Z;']), 5, 'else Z', R), R);
  // then des inneren if: das else bleibt bei ihm.
  Assert.AreEqual(InProc(['  if A then if B then', '  begin', '    X;', '  end',
      '  else Y;']),
    FixBlock(InProc(['  if A then if B then X else Y;']), 5, 'then X', R), R);
  // Das letzte else einer else-if-Kette.
  Assert.AreEqual(InProc(['  if A then X', '  else if B then Y', '  else',
      '  begin', '    Z;', '  end;']),
    FixBlock(InProc(['  if A then X', '  else if B then Y', '  else', '    Z;']),
      7, 'else', R), R);
end;

procedure TTestRdxBlockFixes.Sca101_ListElse;
var
  R : string;
begin
  // else des case: die ganze Liste bis vor das end des case.
  Assert.AreEqual(InProc(['  case X of', '    1: A;', '  else', '  begin', '    B;',
      '    C;', '  end;', '  end;']),
    FixBlock(InProc(['  case X of', '    1: A;', '  else', '    B;', '    C;',
      '  end;']), 7, 'else', R), R);
  Assert.AreEqual(InProc(['  case X of', '    1: A;', '  else', '  begin', '    B;',
      '  end', '  end;']),
    FixBlock(InProc(['  case X of', '    1: A;', '  else', '    B', '  end;']), 7,
      'else', R), R);
  // Ein case in der Liste hat sein eigenes end.
  Assert.AreEqual(InProc(['  case X of', '    1: A;', '  else', '  begin', '    B;',
      '    case Y of 2: C; end;', '  end;', '  end;']),
    FixBlock(InProc(['  case X of', '    1: A;', '  else', '    B;',
      '    case Y of 2: C; end;', '  end;']), 7, 'else', R), R);
  // else des except.
  Assert.AreEqual(InProc(['  try', '    A;', '  except', '    on E: Exception do B;',
      '  else', '  begin', '    C;', '  end;', '  end;']),
    FixBlock(InProc(['  try', '    A;', '  except', '    on E: Exception do B;',
      '  else', '    C;', '  end;']), 9, 'else', R), R);
  Assert.AreEqual(InProc(['  case X of 1: A; else begin B; end; end;']),
    FixBlock(InProc(['  case X of 1: A; else B; end;']), 5, 'else', R), R);
end;

procedure TTestRdxBlockFixes.Sca101_Refusals;
var
  R : string;
begin
  // Bedingter Ausdruck (Delphi 13), auch verschachtelt.
  Assert.AreEqual('', FixBlock(InProc(['  X := if A then B else C;']), 5, 'then', R));
  Assert.IsTrue(Pos('Ausdruck', R) > 0, R);
  Assert.AreEqual('', FixBlock(InProc(['  X := if A then B else C;']), 5, 'else', R));
  Assert.IsTrue(Pos('Ausdruck', R) > 0, R);
  Assert.AreEqual('', FixBlock(InProc(['  X := if A then if B then C else D else E;']),
    5, 'then C', R));
  Assert.IsTrue(Pos('Ausdruck', R) > 0, R);
  // In der Anweisung: bedingter Ausdruck, anonyme Methode, Inline-Variable.
  Assert.AreEqual('', FixBlock(InProc(['  if A then X := if B then 1 else 2;']), 5,
    'then X', R));
  Assert.IsTrue(Pos('"if"', R) > 0, R);
  Assert.AreEqual('', FixBlock(InProc(['  if A then Run(procedure begin X; end);']),
    5, 'then', R));
  Assert.IsTrue(Pos('"procedure"', R) > 0, R);
  Assert.AreEqual('', FixBlock(InProc(['  if A then var I := 1;']), 5, 'then', R));
  Assert.IsTrue(Pos('"var"', R) > 0, R);
  Assert.AreEqual('', FixBlock(InProc(['  case X of', '    1: A;', '  else',
    '    var I := 1;', '  end;']), 7, 'else', R));
  Assert.IsTrue(Pos('Inline-Deklaration', R) > 0, R);
  // Abgelehnt: der Zweig ist schon ein Block, eine Direktive steht im
  // Bereich, die Spalte trifft kein Schluesselwort.
  Assert.AreEqual('', FixBlock(InProc(['  if A then begin X; end;']), 5, 'then', R));
  Assert.IsTrue(Pos('schon in begin..end', R) > 0, R);
  Assert.AreEqual('', FixBlock(InProc(['  if A then', '{$IFDEF D}', '    X;',
    '{$ENDIF}']), 5, 'then', R));
  Assert.IsTrue(Pos('Direktive', R) > 0, R);
  Assert.AreEqual('', FixBlock(InProc(['  if A then X;']), 5, 'A', R));
  Assert.IsTrue(Pos('kein then/else/do', R) > 0, R);
end;

procedure TTestRdxBlockFixes.Sca099_EndElse;
var
  R : string;
begin
  Assert.AreEqual(InProc(['  if A then', '  begin', '    X;', '  end else',
      '  begin', '    Y;', '  end;']),
    FixBlock(InProc(['  if A then', '  begin', '    X;', '  end else Y;']), 8, '',
      R), R);
  // else auf der Folgezeile.
  Assert.AreEqual(InProc(['  if A then', '  begin', '    X;', '  end', '  else',
      '  begin', '    Y;', '  end;']),
    FixBlock(InProc(['  if A then', '  begin', '    X;', '  end', '  else', '    Y;']),
      8, '', R), R);
  // end else im case: der else-Zweig des case.
  Assert.AreEqual(InProc(['  case X of', '    1: begin A; end', '  else', '  begin',
      '    B;', '  end;', '  end;']),
    FixBlock(InProc(['  case X of', '    1: begin A; end', '  else', '    B;',
      '  end;']), 6, '', R), R);
  Assert.AreEqual('', FixBlock(InProc(['  if A then X else Y;']), 5, '', R));
  Assert.IsTrue(Pos('kein "end else"', R) > 0, R);
  // 'end else if' meldet der Detektor nicht - es zaehlt nur 'end else Z'.
  Assert.AreEqual(InProc(['  if A then begin X; end else if B then begin Y; end else',
      '  begin', '    Z;', '  end;']),
    FixBlock(InProc(['  if A then begin X; end else if B then begin Y; end else Z;']),
      5, '', R), R);
  Assert.AreEqual('', FixBlock(InProc(['  if A then begin X; end else Y; '
    + 'if B then begin Z; end else W;']), 5, '', R));
  Assert.IsTrue(Pos('mehrdeutig', R) > 0, R);
  // '&End' ist ein Bezeichner.
  Assert.AreEqual('', FixBlock(InProc(['  if A then X.&End else Y;']), 5, '', R));
  Assert.IsTrue(Pos('kein "end else"', R) > 0, R);
  Assert.AreEqual('', FixBlock(InProc(['  if A then begin X; end else ;']), 5, '',
    R));
  Assert.IsTrue(Pos('leere Anweisung', R) > 0, R);
  Assert.AreEqual('', FixBlock(InProc(['  if A then begin X; end else asm nop end;']),
    5, '', R));
  Assert.IsTrue(Pos('"asm"', R) > 0, R);
end;

procedure TTestRdxBlockFixes.Sca101_AnonMethodHeader;
var
  R, Src : string;
begin
  // Das ';' im Kopf einer anonymen Methode beweist kein else eines case -
  // sonst zoege die Hilfe 'Handler();' in den else-Zweig.
  Src := InProc(['  if UseDefault then', '    Handler := procedure', '      var',
    '        S: string;', '      begin', '        Log(S);', '      end', '  else',
    '    Handler := FOnX;', '  Handler();']);
  Assert.AreEqual('', FixBlock(Src, 12, 'else', R), 'SCA101');
  Assert.IsTrue(Pos('anonymen Methode', R) > 0, R);
  Assert.AreEqual('', FixBlock(Src, 11, '', R), 'SCA099');
  Assert.IsTrue(Pos('anonymen Methode', R) > 0, R);
  // Eine lokale Routine im Kopf.
  Assert.AreEqual('', FixBlock(InProc(['  if A then P := procedure procedure Inner; '
    + 'begin end; begin Inner; end else Q := nil; Z := 1;']), 5, 'else', R));
  Assert.IsTrue(Pos('anonymen Methode', R) > 0, R);
  // Ohne Kopf: nur die eine Anweisung kommt in den Block.
  Assert.AreEqual(InProc(['  if A then', '    H := procedure begin Log; end', '  else',
      '  begin', '    H := nil;', '  end;', '  Run;']),
    FixBlock(InProc(['  if A then', '    H := procedure begin Log; end', '  else',
      '    H := nil;', '  Run;']), 7, 'else', R), R);
end;

procedure TTestRdxBlockFixes.Sca101_ReviewRefusals;
var
  R : string;
begin
  // Zwei else hinter einem Arm.
  Assert.AreEqual('', FixBlock(InProc(['  case K of 1: A else B else C end;']), 5,
    'else C', R));
  Assert.IsTrue(Pos('passt zu keinem if', R) > 0, R);
  // Vor dem else nur ein begin.
  Assert.AreEqual('', FixBlock(InProc(['  X else Y;']), 5, 'else', R));
  Assert.IsTrue(Pos('kein if, case oder except', R) > 0, R);
  Assert.AreEqual('', FixBlock(InProc(['  X := F(Y else Z);']), 5, 'else', R));
  Assert.IsTrue(Pos('in Klammern', R) > 0, R);
  // Die Anweisung beginnt mit einem String (der Token-Leser saehe ihn nicht).
  Assert.AreEqual('', FixBlock(InProc(['  if A then begin X; end else ''a''.Foo;']),
    5, '', R));
  Assert.IsTrue(Pos('String', R) > 0, R);
  // record vor dem else: ein case im Variantenteil hat kein eigenes end.
  Assert.AreEqual('', FixBlock(InProc(['  if A then begin var V: record case '
    + 'Integer of 0: (F: Integer); end; X; end else Y;']), 5, 'else', R));
  Assert.IsTrue(Pos('record', R) > 0, R);
  // Eine Direktive zwischen of und else entscheidet mit, wem es gehoert.
  Assert.AreEqual('', FixBlock(InProc(['  case K of', '{$IFDEF D}', '    1: A;',
    '{$ENDIF}', '  else', '    B;', '  end;']), 9, 'else', R));
  Assert.IsTrue(Pos('Direktive', R) > 0, R);
  // ':' in Klammern: ein bedingter Ausdruck als Write-Breite.
  Assert.AreEqual('', FixBlock(InProc(['  Write(X: if A then W else 10);']), 5,
    'then', R));
  Assert.IsTrue(Pos('Ausdruck', R) > 0, R);
  // '&Then' ist ein Bezeichner.
  Assert.AreEqual('', FixBlock(InProc(['  if Obj.&Then then X;']), 5, 'Then', R));
  Assert.IsTrue(Pos('kein then/else/do', R) > 0, R);
end;

procedure TTestRdxBlockFixes.Sca101_ReviewForms;
var
  R : string;
begin
  // repeat..until im then-Zweig wird uebersprungen wie ein Block.
  Assert.AreEqual(InProc(['  if A then repeat X; until B else', '  begin', '    Y;',
      '  end;']),
    FixBlock(InProc(['  if A then repeat X; until B else Y;']), 5, 'else', R), R);
  // Ein Block-Kommentar ueber Zeilen hinter dem then: inline.
  Assert.AreEqual(InProc(['  if A then { Kommentar', '  bis hier }',
      '    begin X; end;']),
    FixBlock(InProc(['  if A then { Kommentar', '  bis hier }', '    X;']), 5,
      'then', R), R);
  // Ein Bezeichner On ist kein Handler.
  Assert.AreEqual(InProc(['  while not On do', '  begin', '    X;', '  end;']),
    FixBlock(InProc(['  while not On do', '    X;']), 5, 'do', R), R);
  // '{$' in einem '//'-Kommentar ist keine Direktive.
  Assert.AreEqual(InProc(['  if A then // siehe {$IFDEF DEBUG}', '  begin', '    X;',
      '  end;']),
    FixBlock(InProc(['  if A then // siehe {$IFDEF DEBUG}', '    X;']), 5, 'then',
      R), R);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxBlockFixes);

end.
