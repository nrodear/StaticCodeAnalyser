unit uTestRdxLineFixes;

// Editorhilfen an einer Zeile (uRdxLineFixes) auf Text - ohne Parser, ohne
// Detektor (laeuft in reDelphix.Test UND im FPC-Pruefstand):
//   SCA082 ';;' -> ';' (Leerraum dazwischen, verschoben, String),
//   SCA071 Einrueckung vor dem Unit-Schluesselwort (Tabs, Kommentar davor,
//          Zeile in einem Block-Kommentar),
//   SCA088 begin des Unit-Rumpfs -> initialization (Schreibweise, program,
//          Routinen-begin, Direktive),
//   SCA123 'TFoo(X).Free' -> 'X.Free' (Pfad, Interface, Destroy, Aufruf
//          als Operand, zwei Casts) - die Typpruefung (X ist schon TFoo)
//          macht der Laeufer, s. Fixture 6.
// Die Gegenprobe mit dem echten Detektor steht in
// uTestRdxSimpleFixesDetector (Fixture 6, nur Delphi).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxLineFixes = class
  public
    [Test] procedure Sca082_DoubleSemicolon;
    [Test] procedure Sca082_Refusals;
    [Test] procedure Sca071_KeywordIndent;
    [Test] procedure Sca071_Refusals;
    [Test] procedure Sca088_LegacyInit;
    [Test] procedure Sca088_Refusals;
    [Test] procedure Sca123_CastFree;
    [Test] procedure Sca123_Refusals;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxBufferMath, uRdxCodeMap, uRdxLineFixes,
  uTestRdxTextKit;   // Join, Apply

type
  TRdxLineKind = (lkSemi, lkIndent, lkInit, lkCast);

// ---- Helfer ----

// Die Hilfe AKind fuer Zeile ALine mit der Meldung AMessage: neuer Text
// oder '' bei Ablehnung (AReason).
function Fix(AKind: TRdxLineKind; const ASource: string; ALine: Integer;
  const AMessage: string; out AReason: string): string;
var
  SL : TStringList;
  Map : TRdxCodeMap;
  E   : TRdxEdit;
  Ok  : Boolean;
begin
  Result := '';
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    case AKind of
      lkSemi:
        Ok := TRdxLineFixes.DoubleSemicolon(Map, ALine, AMessage, E, AReason);
      lkIndent:
        Ok := TRdxLineFixes.KeywordIndent(Map, ALine, AMessage, E, AReason);
      lkInit:
        Ok := TRdxLineFixes.LegacyInit(Map, ALine, E, AReason);
    else
      Ok := TRdxLineFixes.CastFree(Map, ALine, AMessage, E, AReason);
    end;
    if Ok then
      Result := Apply(ASource, E);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Die Meldungen wie die Detektoren sie schreiben.
function SemiMsg(ACol: Integer): string;
begin
  Result := Format('Double semicolon at column %d (`;;`) - drop the extra '
    + 'one.', [ACol]);
end;

function IndentMsg(const AWord: string; ACol: Integer): string;
begin
  Result := Format('Unit-level keyword "%s" should start at column 1 '
    + '(currently at column %d).', [AWord, ACol]);
end;

function CastMsg(const AType: string): string;
begin
  Result := Format('Type-cast %s(...) before Free/Destroy - on a class-typed '
    + 'operand the cast is redundant (Destroy is virtual)', [AType]);
end;

// Eine Unit mit einer Routine P und den Zeilen ALines als Rumpf von P (ab
// Zeile 5).
function InUnit(const ALines: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'implementation', 'procedure P;'])
    + #13#10 + 'begin' + #13#10 + Join(ALines) + #13#10 + Join(['end;', 'end.']);
end;

// ---- SCA082 ----

procedure TTestRdxLineFixes.Sca082_DoubleSemicolon;
var
  R : string;
begin
  Assert.AreEqual(InUnit(['  DoStuff;']), Fix(lkSemi, InUnit(['  DoStuff;;']), 6,
    SemiMsg(10), R), R);
  // Leerraum dazwischen geht mit.
  Assert.AreEqual(InUnit(['  DoStuff; // x']), Fix(lkSemi,
    InUnit(['  DoStuff; ; // x']), 6, SemiMsg(10), R), R);
end;

procedure TTestRdxLineFixes.Sca082_Refusals;
var
  R : string;
begin
  // Die Spalte trifft kein ';;' (Zeile verschoben).
  Assert.AreEqual('', Fix(lkSemi, InUnit(['  DoStuff;']), 6, SemiMsg(10), R));
  Assert.IsTrue(Pos('";;"', R) > 0, R);
  // ';;' in einem String ist kein Code.
  Assert.AreEqual('', Fix(lkSemi, InUnit(['  S := '';;'';']), 6, SemiMsg(9), R));
  Assert.IsTrue(Pos('";;"', R) > 0, R);
  Assert.AreEqual('', Fix(lkSemi, InUnit(['  DoStuff;;']), 6, 'ohne Spalte', R));
  Assert.IsTrue(Pos('Spalte', R) > 0, R);
  // ';;' in einem Kommentar bzw. mehrzeiligen String.
  Assert.AreEqual('', Fix(lkSemi, InUnit(['  DoStuff; // ;;']), 6, SemiMsg(16), R));
  Assert.IsTrue(Pos('";;"', R) > 0, R);
  Assert.AreEqual('', Fix(lkSemi, InUnit(['  S := ''''''', '  ;;', '  '''''';']), 7,
    SemiMsg(3), R));
  Assert.IsTrue(Pos('";;"', R) > 0, R);
end;

// ---- SCA071 ----

procedure TTestRdxLineFixes.Sca071_KeywordIndent;
var
  R : string;
begin
  Assert.AreEqual(Join(['unit u;', 'interface', 'implementation', 'end.']),
    Fix(lkIndent, Join(['unit u;', 'interface', '  implementation', 'end.']), 3,
      IndentMsg('implementation', 3), R), R);
  // Tabs und ein Kommentar dahinter (uses meldet der Detektor nur allein
  // auf der Zeile).
  Assert.AreEqual(Join(['unit u;', 'interface', 'uses // x', '  SysUtils;',
      'implementation', 'end.']),
    Fix(lkIndent, Join(['unit u;', 'interface', #9#9'uses // x', '  SysUtils;',
      'implementation', 'end.']), 3, IndentMsg('uses', 3), R), R);
end;

procedure TTestRdxLineFixes.Sca071_Refusals;
var
  R : string;
begin
  // Ein Kommentar vor dem Schluesselwort ginge verloren.
  Assert.AreEqual('', Fix(lkIndent, Join(['unit u;', 'interface',
    '{x} implementation', 'end.']), 3, IndentMsg('implementation', 5), R));
  Assert.IsTrue(Pos('nicht an der gemeldeten Stelle', R) > 0, R);
  // Die Zeile liegt in einem Block-Kommentar.
  Assert.AreEqual('', Fix(lkIndent, Join(['unit u;', 'interface', '{ alt:',
    '  implementation }', 'implementation', 'end.']), 4,
    IndentMsg('implementation', 3), R));
  Assert.IsTrue(Pos('Kommentar', R) > 0, R);
  // Ein anderes Wort an der Spalte.
  Assert.AreEqual('', Fix(lkIndent, Join(['unit u;', 'interface', '  uses X;',
    'implementation', 'end.']), 3, IndentMsg('implementation', 3), R));
  Assert.IsTrue(Pos('nicht an der gemeldeten Stelle', R) > 0, R);
  // Die Zeile liegt in einem mehrzeiligen String.
  Assert.AreEqual('', Fix(lkIndent, Join(['unit u;', 'interface', 'const',
    '  S = ''''''', '  implementation', '  '''''';', 'implementation', 'end.']), 5,
    IndentMsg('implementation', 3), R));
  Assert.IsTrue(Pos('String', R) > 0, R);
  // Das interface eines Typs (meldet der Detektor auch).
  Assert.AreEqual('', Fix(lkIndent, Join(['unit u;', 'interface', 'type',
    '  IFoo =', '    interface', '  end;', 'implementation', 'end.']), 5,
    IndentMsg('interface', 5), R));
  Assert.IsTrue(Pos('Typ-Deklaration', R) > 0, R);
end;

// ---- SCA088 ----

procedure TTestRdxLineFixes.Sca088_LegacyInit;
var
  R : string;
begin
  Assert.AreEqual(Join(['unit u;', 'interface', 'implementation',
      'procedure P; begin end;', 'initialization', '  P;', 'end.']),
    Fix(lkInit, Join(['unit u;', 'interface', 'implementation',
      'procedure P; begin end;', 'begin', '  P;', 'end.']), 5, '', R), R);
  // Schreibweise wie das begin; Bloecke im Rumpf zaehlen mit.
  Assert.AreEqual(Join(['unit u;', 'interface', 'implementation',
      'INITIALIZATION', '  try X; finally Y; end;', '  case K of 1: Z; end;',
      'END.']),
    Fix(lkInit, Join(['unit u;', 'interface', 'implementation', 'BEGIN',
      '  try X; finally Y; end;', '  case K of 1: Z; end;', 'END.']), 4, '', R), R);
  Assert.AreEqual(Join(['unit u;', 'interface', 'implementation',
      'Initialization', 'end.']),
    Fix(lkInit, Join(['unit u;', 'interface', 'implementation', 'Begin',
      'end.']), 4, '', R), R);
end;

procedure TTestRdxLineFixes.Sca088_Refusals;
var
  R : string;
begin
  // program: begin ist der Rumpf, initialization dort unzulaessig.
  Assert.AreEqual('', Fix(lkInit, Join(['program p;', 'begin', '  X;', 'end.']), 2,
    '', R));
  Assert.IsTrue(Pos('keine Unit', R) > 0, R);
  // Der Rumpf einer Routine endet nicht vor dem Punkt.
  Assert.AreEqual('', Fix(lkInit, Join(['unit u;', 'interface', 'implementation',
    'procedure P;', 'begin', 'end;', 'end.']), 5, '', R));
  Assert.IsTrue(Pos('nicht vor dem Punkt', R) > 0, R);
  // Direktive auf der Zeile.
  Assert.AreEqual('', Fix(lkInit, Join(['unit u;', 'interface', 'implementation',
    '{$IFDEF X} begin', 'end.']), 4, '', R));
  Assert.IsTrue(Pos('Direktive', R) > 0, R);
  Assert.AreEqual('', Fix(lkInit, Join(['unit u;', 'interface', 'implementation',
    'end.']), 3, '', R));
  Assert.IsTrue(Pos('kein begin', R) > 0, R);
  // Zwei begin auf der Zeile; begin nur im Kommentar.
  Assert.AreEqual('', Fix(lkInit, Join(['unit u;', 'interface', 'implementation',
    'begin begin end;', 'end.']), 4, '', R));
  Assert.IsTrue(Pos('mehrdeutig', R) > 0, R);
  Assert.AreEqual('', Fix(lkInit, Join(['unit u;', 'interface', 'implementation',
    '// begin', 'end.']), 4, '', R));
  Assert.IsTrue(Pos('kein begin', R) > 0, R);
end;

// ---- SCA123 ----

procedure TTestRdxLineFixes.Sca123_CastFree;
var
  R : string;
begin
  Assert.AreEqual(InUnit(['  L.Free;']),
    Fix(lkCast, InUnit(['  TStringList(L).Free;']), 6, CastMsg('TStringList'), R), R);
  // Leerraum in den Klammern, Kommentar dahinter. (Bis zur Review Woche
  // G07-17 stand hier ein Pfad 'Self.FList' - den lehnte der Laeufer immer
  // ab, jetzt schon der Planer, s. Sca123_Refusals.)
  Assert.AreEqual(InUnit(['  if A then FList.Free; // weg']),
    Fix(lkCast, InUnit(['  if A then TObjectList( FList ).Free; // weg']), 6,
      CastMsg('TObjectList'), R), R);
  // Gross/klein des Typs wie im Code; ein Cast vor Destroy zaehlt nicht mit.
  Assert.AreEqual(InUnit(['  L.Free;']),
    Fix(lkCast, InUnit(['  tstringlist(L).Free;']), 6, CastMsg('TStringList'), R), R);
  Assert.AreEqual(InUnit(['  TFoo(A).Destroy; B.Free;']),
    Fix(lkCast, InUnit(['  TFoo(A).Destroy; TFoo(B).Free;']), 6, CastMsg('TFoo'),
      R), R);
end;

procedure TTestRdxLineFixes.Sca123_Refusals;
var
  R : string;
begin
  // Interface-Cast: IFoo(X).Free riefe eine Interface-Methode.
  Assert.AreEqual('', Fix(lkCast, InUnit(['  IFoo(X).Free;']), 6, CastMsg('IFoo'), R));
  Assert.IsTrue(Pos('Interface', R) > 0, R);
  // Nur Free.
  Assert.AreEqual('', Fix(lkCast, InUnit(['  TFoo(X).Destroy;']), 6, CastMsg('TFoo'),
    R));
  Assert.IsTrue(Pos('nur fuer Free', R) > 0, R);
  // Aufruf bzw. Index als Operand: der Cast kann zum Uebersetzen noetig sein.
  Assert.AreEqual('', Fix(lkCast, InUnit(['  TFoo(List[0]).Free;']), 6,
    CastMsg('TFoo'), R));
  Assert.IsTrue(Pos('Bezeichner', R) > 0, R);
  Assert.AreEqual('', Fix(lkCast, InUnit(['  TFoo(GetIt()).Free;']), 6,
    CastMsg('TFoo'), R));
  Assert.IsTrue(Pos('Bezeichner', R) > 0, R);
  Assert.AreEqual('', Fix(lkCast, InUnit(['  TFoo(nil).Free;']), 6, CastMsg('TFoo'),
    R));
  Assert.IsTrue(Pos('"nil"', R) > 0, R);
  // Ein Pfad: sein Typ ist fuer den Laeufer nicht pruefbar - der Planer
  // lehnt ihn selbst ab (Review Woche G07-17).
  Assert.AreEqual('', Fix(lkCast, InUnit(['  TObjectList(Self.FList).Free;']), 6,
    CastMsg('TObjectList'), R));
  Assert.IsTrue(Pos('ein Pfad', R) > 0, R);
  // Zwei Casts auf der Zeile; ein Kommentar im Cast; Zeile verschoben.
  Assert.AreEqual('', Fix(lkCast, InUnit(['  TFoo(A).Free; TFoo(B).Free;']), 6,
    CastMsg('TFoo'), R));
  Assert.IsTrue(Pos('mehrdeutig', R) > 0, R);
  Assert.AreEqual('', Fix(lkCast, InUnit(['  TFoo(A {x}).Free;']), 6,
    CastMsg('TFoo'), R));
  Assert.IsTrue(Pos('Kommentar', R) > 0, R);
  Assert.AreEqual('', Fix(lkCast, InUnit(['  A.Free;']), 6, CastMsg('TFoo'), R));
  Assert.IsTrue(Pos('verschoben', R) > 0, R);
  // Der Cast geht ueber zwei Zeilen; die Meldung nennt den Typ wie im Code.
  Assert.AreEqual('', Fix(lkCast, InUnit(['  TFoo(A', '    ).Free;']), 6,
    CastMsg('TFoo'), R));
  Assert.IsTrue(Pos('mehrere Zeilen', R) > 0, R);
  Assert.AreEqual('', Fix(lkCast, InUnit(['  TFoo(A).Free; TFoo(B).Free;']), 6,
    CastMsg('TFoo'), R));
  Assert.IsTrue(Pos('TFoo(...)', R) > 0, R);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxLineFixes);

end.
