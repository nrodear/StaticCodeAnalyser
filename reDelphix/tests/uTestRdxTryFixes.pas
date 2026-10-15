unit uTestRdxTryFixes;

// Quick-Fixes try/finally (uRdxTryFixes, Charge H4) auf Text - ohne Parser,
// ohne Detektor (laeuft in reDelphix.Test UND im FPC-Pruefstand): der
// Baustein B5 an SCA009 MissingFinally und SCA001 (Variante freed-outside-
// finally; die Variante prueft die Tabelle, uRdxFixTable):
//   Form - try/finally/end in eigenen Zeilen, Einrueckung wie A, Stufe der
//          Liste (zwei Leerzeichen, vier, Tab), Leerzeilen bleiben leer,
//          Kommentarzeilen ruecken mit, 'X := nil;' geht mit, FreeAndNil,
//          B ohne ';' vor end, A ueber Zeilen, Inline-var als A;
//   Inhalt - Strukturen im Bereich (if/begin, Schleifen, case, try/finally,
//          try/except), Exit, Break/Continue in einer inneren Schleife,
//          umschliessendes try ohne X im Handler, SCA009-Suffix (sagt
//          nichts ueber den Ort - seit Charge H4c wie ohne, Gegen-Review
//          H4, Major 1);
//   Sperren - je eine: Kontext von A, Zeile von A und B, keine Freigabe in
//          der Liste, zweite bzw. bedingte Freigabe, zweite Zuweisung,
//          nichts zu schuetzen, Direktive, mehrzeiliger String, Inline-
//          Deklaration, Marke, goto, asm, Break/Continue nach aussen, Exit
//          mit Weitergabe, raise X, Handler um den Bereich, veraltete Zeile.
// Sperren (SCA109/SCA153) und Puffer (SCA156): uTestRdxTryLocks; die
// Sperren aus dem Gegen-Review H4 (Weitergabe ohne Ausstieg, andere
// Schreibweisen, raise-Ausdruck ...): uTestRdxTryGates; dieselben Hilfen
// gegen die echten Detektoren: uTestRdxTryFixesDetector (nur Delphi).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxTryFixes = class
  public
    [Test] procedure Sca009_Basic;
    [Test] procedure Sca009_NilAndFreeAndNil;
    [Test] procedure Sca009_IndentStep;
    [Test] procedure Sca009_FormOfAAndB;
    [Test] procedure Sca009_BlankLinesAndComments;
    [Test] procedure Sca009_StructuresInside;
    [Test] procedure Sca009_ExitAndInnerLoops;
    [Test] procedure Sca009_EnclosingTry;
    [Test] procedure Sca009_Suffix;
    [Test] procedure Sca001_FreedOutsideFinally;
    [Test] procedure Refuse_Context;
    [Test] procedure Refuse_LineLayout;
    [Test] procedure Refuse_NoReleaseInList;
    [Test] procedure Refuse_SecondReleaseOrAssign;
    [Test] procedure Refuse_NothingToProtect;
    [Test] procedure Refuse_DirectiveAndMultiString;
    [Test] procedure Refuse_DeclLabelGotoAsm;
    [Test] procedure Refuse_JumpsOut;
    [Test] procedure Refuse_Handler;
    [Test] procedure Refuse_Stale;
  end;

implementation

uses
  System.Classes,
  uRdxCodeMap, uRdxTryFixes,
  uTestRdxTextKit;   // Join, Apply

const
  SUFFIX = ' (try/except instead of try/finally)';

// ---- Helfer ----

// Eine Unit mit Routine P; ALines ist ihr Rumpf (ab Zeile 6).
function InProc(const ALines: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'implementation', 'procedure P;',
    'begin']) + #13#10 + Join(ALines) + #13#10 + Join(['end;', 'end.']);
end;

// Der Plan des Planers APlanner fuer Zeile ALine; AReason = '' heisst Hilfe.
function PlanOf(APlanner: TRdxTryPlanner; const ASource: string;
  ALine: Integer; const AMessage: string; out AReason: string): TRdxTryPlan;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    APlanner(Map, ALine, AMessage, Result, AReason);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// SCA009: neuer Text oder '' bei Ablehnung (AReason).
function Fix(const ASource: string; ALine: Integer; const AMessage: string;
  out AReason: string): string;
var
  P : TRdxTryPlan;
begin
  Result := '';
  P := PlanOf(TRdxTryFixes.MissingFinally, ASource, ALine, AMessage, AReason);
  if AReason = '' then
    Result := Apply(ASource, P.Edit);
end;

// SCA009 mit X: keine Hilfe, und APart steht im Grund.
procedure AssertRefused(const ASource: string; ALine: Integer;
  const AMessage, APart: string);
var
  R : string;
begin
  Assert.AreEqual('', Fix(ASource, ALine, AMessage, R), 'keine Hilfe');
  Assert.IsTrue(Pos(APart, R) > 0, R);
end;

// ---- Angebote ----

procedure TTestRdxTryFixes.Sca009_Basic;
var
  R : string;
  P : TRdxTryPlan;
begin
  Assert.AreEqual(InProc(['  X := TStringList.Create;', '  try',
    '    X.Add(''a'');', '    Foo(X);', '  finally', '    X.Free;', '  end;']),
    Fix(InProc(['  X := TStringList.Create;', '  X.Add(''a'');', '  Foo(X);',
      '  X.Free;']), 6, 'X', R), R);
  // Name fuer den Menuetext: X aus der Meldung, auch mit Suffix.
  P := PlanOf(TRdxTryFixes.MissingFinally, InProc(['  X := TFoo.Create;',
    '  X.Run;', '  X.Free;']), 6, 'X', R);
  Assert.AreEqual('', R);
  Assert.AreEqual('X', P.Name);
  Assert.AreEqual('X', TRdxTryFixes.NameOf('X' + SUFFIX));
  // Gross/klein der Freigabe wie im Quelltext; Create-Varianten.
  Assert.AreEqual(InProc(['  x := TFoo.CreateFmt(''%d'', [1]);', '  try',
    '    x.Run;', '  finally', '    X.free;', '  end;']),
    Fix(InProc(['  x := TFoo.CreateFmt(''%d'', [1]);', '  x.Run;',
      '  X.free;']), 6, 'x', R), R);
end;

procedure TTestRdxTryFixes.Sca009_NilAndFreeAndNil;
var
  R : string;
begin
  // Ein direkt folgendes 'X := nil;' geht mit ins finally.
  Assert.AreEqual(InProc(['  X := TFoo.Create;', '  try', '    X.Run;',
    '  finally', '    X.Free;', '    X := nil;', '  end;', '  Bar;']),
    Fix(InProc(['  X := TFoo.Create;', '  X.Run;', '  X.Free;',
      '  X := nil;', '  Bar;']), 6, 'X', R), R);
  // FreeAndNil und Destroy als Freigabe.
  Assert.AreEqual(InProc(['  X := TFoo.Create;', '  try', '    X.Run;',
    '  finally', '    FreeAndNil(X);', '  end;']),
    Fix(InProc(['  X := TFoo.Create;', '  X.Run;', '  FreeAndNil(X);']), 6,
      'X', R), R);
  Assert.AreEqual(InProc(['  X := TFoo.Create;', '  try', '    X.Run;',
    '  finally', '    X.Destroy;', '  end;']),
    Fix(InProc(['  X := TFoo.Create;', '  X.Run;', '  X.Destroy;']), 6, 'X',
      R), R);
end;

procedure TTestRdxTryFixes.Sca009_IndentStep;
var
  R : string;
begin
  // Vier Leerzeichen: die Stufe der Liste (A gegen ihren Oeffner begin).
  Assert.AreEqual(InProc(['    X := TFoo.Create;', '    try',
    '        X.Run;', '    finally', '        X.Free;', '    end;']),
    Fix(InProc(['    X := TFoo.Create;', '    X.Run;', '    X.Free;']), 6, 'X',
      R), R);
  // Tab.
  Assert.AreEqual(InProc([#9'X := TFoo.Create;', #9'try', #9#9'X.Run;',
    #9'finally', #9#9'X.Free;', #9'end;']),
    Fix(InProc([#9'X := TFoo.Create;', #9'X.Run;', #9'X.Free;']), 6, 'X', R),
    R);
  // Im Zweig eines if, der Block beginnt am Ende der Zeile - die Stufe
  // zaehlt gegen deren Einrueckung.
  Assert.AreEqual(InProc(['  if C then begin', '    X := TFoo.Create;',
    '    try', '      X.Run;', '    finally', '      X.Free;', '    end;',
    '  end;']),
    Fix(InProc(['  if C then begin', '    X := TFoo.Create;', '    X.Run;',
      '    X.Free;', '  end;']), 7, 'X', R), R);
  // Ausgerichtet ('1: begin' und tief darunter) ist keine Stufe: Vorgabe.
  Assert.AreEqual(InProc(['  case K of', '    1: begin',
    '         X := TFoo.Create;', '         try', '           X.Run;',
    '         finally', '           X.Free;', '         end;', '       end;',
    '  end;']),
    Fix(InProc(['  case K of', '    1: begin', '         X := TFoo.Create;',
      '         X.Run;', '         X.Free;', '       end;', '  end;']), 8, 'X',
      R), R);
end;

procedure TTestRdxTryFixes.Sca009_FormOfAAndB;
var
  R : string;
begin
  // A ueber Zeilen: try hinter seine letzte Zeile.
  Assert.AreEqual(InProc(['  X := TFoo.Create(A,', '    B);', '  try',
    '    X.Run;', '  finally', '    X.Free;', '  end;']),
    Fix(InProc(['  X := TFoo.Create(A,', '    B);', '  X.Run;', '  X.Free;']),
      6, 'X', R), R);
  // ... auch mit einer anonymen Methode im Argument, deren Parameterliste
  // ';' traegt: dieses ';' steht in Klammern und beendet A nicht
  // (StatementStop/StopStep mit ParenDelta; Gegenpruefung V2-B2S-1: mit
  // falschem Vorzeichen der Klammertiefe rot - A endete am ';' der Liste).
  Assert.AreEqual(InProc(['  X := TFoo.Create(',
    '    function(const A: TItem; const B: TItem): Integer', '    begin',
    '      Result := A.Id - B.Id;', '    end);', '  try', '    X.Run;',
    '  finally', '    X.Free;', '  end;']),
    Fix(InProc(['  X := TFoo.Create(',
      '    function(const A: TItem; const B: TItem): Integer', '    begin',
      '      Result := A.Id - B.Id;', '    end);', '  X.Run;', '  X.Free;']),
      6, 'X', R), R);
  // Inline-Variable als A (ihr Gueltigkeitsbereich bleibt aussen).
  Assert.AreEqual(InProc(['  var L: TList<Integer> := TList<Integer>.Create;',
    '  try', '    L.Add(1);', '  finally', '    L.Free;', '  end;']),
    Fix(InProc(['  var L: TList<Integer> := TList<Integer>.Create;',
      '  L.Add(1);', '  L.Free;']), 6, 'L', R), R);
  // B ohne ';' als letzte Anweisung vor end; ein Kommentar hinter B geht mit.
  Assert.AreEqual(InProc(['  X := TFoo.Create; // neu', '  try', '    X.Run;',
    '  finally', '    X.Free // weg', '  end;']),
    Fix(InProc(['  X := TFoo.Create; // neu', '  X.Run;', '  X.Free // weg']),
      6, 'X', R), R);
end;

procedure TTestRdxTryFixes.Sca009_BlankLinesAndComments;
var
  R : string;
begin
  // Leerzeilen bleiben leer (kein Leerraum am Zeilenende), Kommentarzeilen
  // und die Inhaltszeilen eines Blockkommentars ruecken mit.
  Assert.AreEqual(InProc(['  X := TFoo.Create;', '  try', '', '    // Kommentar',
    '    X.Run;', '    { Block', '      ueber Zeilen }', '  finally',
    '    X.Free;', '  end;']),
    Fix(InProc(['  X := TFoo.Create;', '', '  // Kommentar', '  X.Run;',
      '  { Block', '    ueber Zeilen }', '  X.Free;']), 6, 'X', R), R);
end;

procedure TTestRdxTryFixes.Sca009_StructuresInside;
var
  R : string;
begin
  // if/begin..end, for, case und ein ganzes try/finally im Bereich; B auf
  // der Ebene von A.
  Assert.AreEqual(InProc(['  X := TFoo.Create;', '  try',
    '    if X.Ok then', '    begin', '      for I := 0 to 3 do', '        X.Add(I);',
    '    end;', '    case K of', '      1: X.Run;', '    end;',
    '    Y := TBar.Create;', '    try', '      Y.Use(X);', '    finally',
    '      Y.Free;', '    end;', '  finally', '    X.Free;', '  end;']),
    Fix(InProc(['  X := TFoo.Create;', '  if X.Ok then', '  begin',
      '    for I := 0 to 3 do', '      X.Add(I);', '  end;', '  case K of',
      '    1: X.Run;', '  end;', '  Y := TBar.Create;', '  try',
      '    Y.Use(X);', '  finally', '    Y.Free;', '  end;', '  X.Free;']), 6,
      'X', R), R);
  // Ein end als Bezeichner ('R.End') zaehlt nicht.
  Assert.AreEqual(InProc(['  X := TFoo.Create;', '  try', '    X.Span := R.End;',
    '  finally', '    X.Free;', '  end;']),
    Fix(InProc(['  X := TFoo.Create;', '  X.Span := R.End;', '  X.Free;']), 6,
      'X', R), R);
end;

procedure TTestRdxTryFixes.Sca009_ExitAndInnerLoops;
var
  R : string;
begin
  // Exit: Free laeuft danach auch dort - das ist der Fix (X nur als Member).
  Assert.AreEqual(InProc(['  X := TFoo.Create;', '  try',
    '    if not X.Load then', '      Exit;', '    X.Run;', '  finally',
    '    X.Free;', '  end;']),
    Fix(InProc(['  X := TFoo.Create;', '  if not X.Load then', '    Exit;',
      '  X.Run;', '  X.Free;']), 6, 'X', R), R);
  // Break/Continue in einer Schleife, die ganz im Bereich liegt.
  Assert.AreEqual(InProc(['  X := TFoo.Create;', '  try',
    '    for I := 0 to 3 do', '      if X.Stop(I) then', '        Break;',
    '    while X.More do', '    begin', '      if X.Skip then', '        Continue;',
    '      X.Next;', '    end;', '    repeat', '      if X.Done then Break;',
    '    until X.Eof;', '  finally', '    X.Free;', '  end;']),
    Fix(InProc(['  X := TFoo.Create;', '  for I := 0 to 3 do',
      '    if X.Stop(I) then', '      Break;', '  while X.More do', '  begin',
      '    if X.Skip then', '      Continue;', '    X.Next;', '  end;',
      '  repeat', '    if X.Done then Break;', '  until X.Eof;', '  X.Free;']), 6,
      'X', R), R);
end;

procedure TTestRdxTryFixes.Sca009_EnclosingTry;
var
  R : string;
begin
  // Ein umschliessendes try, dessen Handler X nicht kennt: inneres try.
  Assert.AreEqual(InProc(['  try', '    X := TFoo.Create;', '    try',
    '      X.Run;', '    finally', '      X.Free;', '    end;', '  finally',
    '    Cleanup;', '  end;']),
    Fix(InProc(['  try', '    X := TFoo.Create;', '    X.Run;', '    X.Free;',
      '  finally', '    Cleanup;', '  end;']), 7, 'X', R), R);
  // A im except-Teil: dieser Handler laeuft nicht noch einmal.
  Assert.AreEqual(InProc(['  try', '    Foo;', '  except', '    X := TFoo.Create;',
    '    try', '      X.Log;', '    finally', '      X.Free;', '    end;',
    '    raise;', '  end;']),
    Fix(InProc(['  try', '    Foo;', '  except', '    X := TFoo.Create;',
      '    X.Log;', '    X.Free;', '    raise;', '  end;']), 9, 'X', R), R);
end;

procedure TTestRdxTryFixes.Sca009_Suffix;
var
  R, S : string;
begin
  // Das Suffix sagt nur, dass die METHODE irgendwo ein try/except hat
  // (uMissingFinally) - der Planer prueft wie ohne (Gegen-Review H4,
  // Major 1; bis Charge H4c lehnte er die beiden letzten Formen ab). Das
  // try/except liegt ganz im Bereich:
  Assert.AreEqual(InProc(['  X := TFoo.Create;', '  try', '    try',
    '      X.Load;', '    except', '      Log;', '    end;', '  finally',
    '    X.Free;', '  end;']),
    Fix(InProc(['  X := TFoo.Create;', '  try', '    X.Load;', '  except',
      '    Log;', '  end;', '  X.Free;']), 6, 'X' + SUFFIX, R), R);
  // Es umschliesst den Bereich und nennt X nicht: nach dem Fix laeuft erst
  // das finally, dann der Handler - richtig.
  Assert.AreEqual(InProc(['  try', '    X := TFoo.Create;', '    try',
    '      X.Run;', '    finally', '      X.Free;', '    end;', '  except',
    '    Log;', '  end;']),
    Fix(InProc(['  try', '    X := TFoo.Create;', '    X.Run;', '    X.Free;',
      '  except', '    Log;', '  end;']), 7, 'X' + SUFFIX, R), R);
  // Es liegt vor dem Bereich: dieselbe Hilfe wie ohne Suffix.
  S := InProc(['  try', '    Foo;', '  except', '    Log;', '  end;',
    '  X := TFoo.Create;', '  X.Run;', '  X.Free;']);
  Assert.AreNotEqual('', Fix(S, 11, 'X' + SUFFIX, R), R);
  Assert.AreEqual(Fix(S, 11, 'X', R), Fix(S, 11, 'X' + SUFFIX, R), R);
end;

procedure TTestRdxTryFixes.Sca001_FreedOutsideFinally;
var
  R : string;
  P : TRdxTryPlan;
  S : string;
begin
  // Die Form der Variante: ein try/finally (fuer Y) im Bereich, Free von X
  // daneben - es wird zum inneren try.
  S := InProc(['  X := TStringList.Create;', '  Y := TStringList.Create;',
    '  try', '    Y.Add(''a'');', '  finally', '    Y.Free;', '  end;',
    '  X.Free;']);
  P := PlanOf(TRdxTryFixes.FreedOutsideFinally, S, 6, 'X', R);
  Assert.AreEqual('', R);
  Assert.AreEqual('X', P.Name);
  Assert.AreEqual(InProc(['  X := TStringList.Create;', '  try',
    '    Y := TStringList.Create;', '    try', '      Y.Add(''a'');',
    '    finally', '      Y.Free;', '    end;', '  finally', '    X.Free;',
    '  end;']), Apply(S, P.Edit));
  // Dieselben Sperren wie SCA009.
  PlanOf(TRdxTryFixes.FreedOutsideFinally, InProc(['  X := TFoo.Create;',
    '  if C then', '    X.Free;']), 6, 'X', R);
  Assert.IsTrue(Pos('bedingte', R) > 0, R);
end;

// ---- Sperren ----

procedure TTestRdxTryFixes.Refuse_Context;
begin
  AssertRefused(InProc(['  if C then X := TFoo.Create;', '  X.Run;',
    '  X.Free;']), 6, 'X', 'allein hinter then');
  AssertRefused(InProc(['  case K of', '    1: X := TFoo.Create;', '  end;',
    '  X.Free;']), 7, 'X', 'case-Zweig');
  AssertRefused(InProc(['  Foo; X := TFoo.Create;', '  X.Run;', '  X.Free;']),
    6, 'X', 'vor der Anweisung');
end;

procedure TTestRdxTryFixes.Refuse_LineLayout;
begin
  AssertRefused(InProc(['  X := TFoo.Create; X.Run;', '  Foo;', '  X.Free;']),
    6, 'X', 'hinter der Anweisung');
  AssertRefused(InProc(['  X := TFoo.Create;', '  X.Run;', '  Foo; X.Free;']),
    6, 'X', 'vor der Freigabe');
  AssertRefused(InProc(['  X := TFoo.Create;', '  X.Run;', '  X.Free; Bar;']),
    6, 'X', 'hinter der Freigabe');
  // Ein Blockkommentar hinter A, der auf der Folgezeile weitergeht.
  AssertRefused(InProc(['  X := TFoo.Create; { lang', '    } X.Run;',
    '  X.Free;']), 6, 'X', 'hinter der Anweisung');
end;

procedure TTestRdxTryFixes.Refuse_NoReleaseInList;
begin
  // Free nur hinter dem Block von A, gar nicht, in einem anderen case-Zweig.
  AssertRefused(InProc(['  if C then', '  begin', '    X := TFoo.Create;',
    '    X.Run;', '  end;', '  X.Free;']), 8, 'X', 'keine Freigabe');
  AssertRefused(InProc(['  X := TFoo.Create;', '  X.Run;']), 6, 'X',
    'keine Freigabe');
  AssertRefused(InProc(['  X := TFoo.Create']), 6, 'X', 'letzte Anweisung');
end;

procedure TTestRdxTryFixes.Refuse_SecondReleaseOrAssign;
begin
  // Bedingtes Frueh-Free, Free in einem Block, zweite Zuweisung.
  AssertRefused(InProc(['  X := TFoo.Create;', '  if not X.Ok then',
    '  begin', '    X.Free;', '    Exit;', '  end;', '  X.Free;']), 6, 'X',
    'zweite Freigabe');
  AssertRefused(InProc(['  X := TFoo.Create;', '  X.Run;', '  begin',
    '    X.Free;', '  end;']), 6, 'X', 'tiefer liegende');
  AssertRefused(InProc(['  X := TFoo.Create;', '  X := TFoo.Create;',
    '  X.Free;']), 6, 'X', 'zweite Zuweisung');
end;

procedure TTestRdxTryFixes.Refuse_NothingToProtect;
begin
  // '... - nichts zu schuetzen' traegt in der de.po einen echten Umlaut
  // (Charge G3) - geprueft wird das umlautfreie Teilstueck davor.
  AssertRefused(InProc(['  X := TFoo.Create;', '  X.Free;']), 6, 'X',
    'folgt direkt auf die Zeile 6');
  AssertRefused(InProc(['  X := TFoo.Create;', '  // nur Kommentar',
    '  X.Free;']), 6, 'X', 'folgt direkt auf die Zeile 6');
end;

procedure TTestRdxTryFixes.Refuse_DirectiveAndMultiString;
begin
  AssertRefused(InProc(['  X := TFoo.Create;', '  {$IFDEF D}', '  X.Run;',
    '  {$ENDIF}', '  X.Free;']), 6, 'X', 'Direktive');
  AssertRefused(InProc(['  X := TFoo.Create;', '  X.Text := ''''''',
    '    abc', '    '''''';', '  X.Free;']), 6, 'X', 'mehrzeiliges');
end;

procedure TTestRdxTryFixes.Refuse_DeclLabelGotoAsm;
begin
  AssertRefused(InProc(['  X := TFoo.Create;', '  var N := X.Count;',
    '  X.Free;', '  Foo(N);']), 6, 'X', 'Inline-Deklaration');
  AssertRefused(InProc(['  X := TFoo.Create;', '  L1: X.Run;', '  X.Free;']),
    6, 'X', 'Marke');
  AssertRefused(InProc(['  X := TFoo.Create;', '  if C then goto L1;',
    '  X.Free;']), 6, 'X', 'goto');
  AssertRefused(InProc(['  X := TFoo.Create;', '  asm', '    nop', '  end;',
    '  X.Free;']), 6, 'X', 'asm');
end;

procedure TTestRdxTryFixes.Refuse_JumpsOut;
begin
  // Break nach aussen: X waere hinter der Schleife frei.
  AssertRefused(InProc(['  for I := 0 to 3 do', '  begin',
    '    X := TFoo.Create;', '    if X.Found then', '      Break;',
    '    X.Free;', '  end;']), 8, 'X', 'break');
  // Exit, und X wird weitergegeben (der Ausstieg uebergibt vielleicht).
  AssertRefused(InProc(['  X := TFoo.Create;', '  if List.TryAdd(X) then',
    '    Exit;', '  X.Free;']), 6, 'X', 'weitergegeben');
  // X ist die Ausnahme.
  AssertRefused(InProc(['  X := EFoo.Create(''x'');', '  if C then',
    '    raise X;', '  X.Free;']), 6, 'X', 'raise X');
end;

procedure TTestRdxTryFixes.Refuse_Handler;
begin
  // Der Handler des umschliessenden try nennt X: zweite Freigabe bzw.
  // Zugriff auf ein freigegebenes Objekt nach dem Fix.
  AssertRefused(InProc(['  try', '    X := TFoo.Create;', '    X.Run;',
    '    X.Free;', '  except', '    X.Free;', '    raise;', '  end;']), 7, 'X',
    'except-Teil');
  AssertRefused(InProc(['  try', '    X := TFoo.Create;', '    X.Run;',
    '    X.Free;', '  finally', '    Log(X.Name);', '  end;']), 7, 'X',
    'finally-Teil');
end;

procedure TTestRdxTryFixes.Refuse_Stale;
begin
  // Die Zeile traegt eine andere Zuweisung bzw. keine Erzeugung.
  AssertRefused(InProc(['  X := TFoo.Create;', '  X.Run;', '  X.Free;']), 6,
    'Y', 'keine Zuweisung "Y := .."');
  AssertRefused(InProc(['  X := GetFoo;', '  X.Run;', '  X.Free;']), 6, 'X',
    'keine Erzeugung');
  AssertRefused(InProc(['  X := TFoo.Create; X := TFoo.Create;', '  X.Free;']),
    6, 'X', 'mehrdeutig');
  AssertRefused(InProc(['  X := TFoo.Create;']), 6, '', 'fehlt in der Meldung');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxTryFixes);

end.
