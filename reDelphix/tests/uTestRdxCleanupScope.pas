unit uTestRdxCleanupScope;

// SCA053 (uRdxCleanupFixes) - die Sperren der Charge H3c aus dem
// Gegen-Review H3, je mit der Pruefer-Fixture (rc/cases053.txt,
// rc/casesuni.txt) auf Text, ohne Parser (laeuft in reDelphix.Test UND im
// FPC-Pruefstand):
//   Major 1   ein {$I}-Include im Gueltigkeitsbereich (die Hilfe sah es
//             nicht; mit einer globalen Variablen gleichen Namens bindet
//             das Include danach still an sie), eine Direktive, die den
//             Namen nennt, ein FPC-Makro mit dem Namen in der Datei;
//   Minor 1   'var X: T;' auf eigener Zeile in einer offenen Klammer - ein
//             Parameter (eines Prozedurtyps bzw. einer lokalen Routine),
//             keine Variable; ein var-Abschnitt hinter einem Kopf ueber
//             Zeilen bleibt eine Variable;
//   Verdacht 2  asm im Gueltigkeitsbereich ('[ebp-4]' spricht die
//             Variable ohne Namen an);
//   Verdacht 1  ein Bezeichner mit Umlaut in anderer Schreibung ist eine
//             Verwendung (Kontrolle - SCA053 verglich schon vorher so;
//             SameIdent liegt seit H3c in uRdxCodeMap);
//   Major 2   das Ende des Gueltigkeitsbereichs liest ReadRoutine: ein
//             'End' als benanntes Argument beendet ihn nicht mehr still,
//             lokale Routinen vor der var-Section gehoeren dazu.
// Eigene Unit: uTestRdxCleanupFixes traegt 20 Tests (Grenze je Fixture).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxCleanupScope = class
  public
    [Test] procedure Sca053_IncludeInScope_NoHelp;
    [Test] procedure Sca053_DirectiveNamesVar_NoHelp;
    [Test] procedure Sca053_MacroInFile_NoHelp;
    [Test] procedure Sca053_ParameterInOpenParen_NoHelp;
    [Test] procedure Sca053_SectionAfterLongHeader;
    [Test] procedure Sca053_AsmInScope_NoHelp;
    [Test] procedure Sca053_UmlautSpelling_NoHelp;
    [Test] procedure Sca053_EndAsIdentifier_NoHelp;
    [Test] procedure Sca053_LocalRoutineBeforeSection;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxBufferMath, uRdxCodeMap, uRdxCleanupFixes;

// ---- Helfer ----

// Zeilen mit CRLF verbunden (TStringBuilder: string.Join kennt FPC nicht).
function Join(const ALines: array of string): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(ALines) do
    begin
      if i > 0 then SB.Append(#13#10);
      SB.Append(ALines[i]);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Eine Unit, deren implementation ALines traegt (ab Zeile 4).
function InImpl(const ALines: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'implementation']) + #13#10
    + Join(ALines) + #13#10 + 'end.';
end;

// Die Meldung des Detektors uUnusedLocal.
function VarMsg(const AName: string): string;
begin
  Result := Format('Unused local variable: %s (declared but never read or '
    + 'written)', [AName]);
end;

// SCA053 fuer Zeile ALine: neuer Text oder '' bei Ablehnung (AReason).
function Fix(const ASource: string; ALine: Integer; const AName: string;
  out AReason: string): string;
var
  SL    : TStringList;
  Map   : TRdxCodeMap;
  E     : TRdxEdit;
  Ok    : Boolean;
  Bytes : TBytes;
  Edits : TArray<TRdxEdit>;
  Plan  : TArray<TRdxByteEdit>;
  Err   : string;
begin
  Result := '';
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    Ok := TRdxCleanupFixes.UnusedLocalVar(Map, ALine, VarMsg(AName), E,
      AReason);
  finally
    Map.Free;
    SL.Free;
  end;
  if not Ok then Exit;
  SetLength(Edits, 1);
  Edits[0] := E;
  Bytes := TEncoding.UTF8.GetBytes(ASource);
  Assert.IsTrue(PlanByteEdits(Bytes, Edits, Plan, Err), Err);
  Result := TEncoding.UTF8.GetString(ApplyByteEdits(Bytes, Plan));
end;

// Die Hilfe greift: der neue Text.
function FixOk(const ASource: string; ALine: Integer;
  const AName: string): string;
var
  R : string;
begin
  Result := Fix(ASource, ALine, AName, R);
  Assert.AreEqual('', R, 'Grund');
end;

// Keine Hilfe, und APart steht im Grund.
procedure AssertRefused(const ASource: string; ALine: Integer;
  const AName, APart: string);
var
  R : string;
begin
  Assert.AreEqual('', Fix(ASource, ALine, AName, R), 'keine Hilfe');
  Assert.IsTrue(Pos(APart, R) > 0, R);
end;

// ---- Major 1 ----

procedure TTestRdxCleanupScope.Sca053_IncludeInScope_NoHelp;
begin
  // Pruefer-Fall: globales X, lokales X, der Rumpf bindet body.inc ein -
  // nach der Hilfe benutzte das Include still das globale X.
  AssertRefused(InImpl(['var X: Integer;', 'procedure Foo;', 'var',
    '  X: Integer;', 'begin', '  {$I body.inc}', 'end;']), 7, 'X', 'Include');
  // Langform und (*$I*), inline im Block.
  AssertRefused(InImpl(['procedure Foo;', 'begin', '  var X: Integer;',
    '  {$INCLUDE ''more code.inc''}', '  Bar;', 'end;']), 6, 'X', 'Include');
  AssertRefused(InImpl(['procedure Foo;', 'var', '  X: Integer;', 'begin',
    '  (*$I body.inc*)', 'end;']), 6, 'X', 'Include');
  // {$I+} ist der Schalter fuer E/A-Pruefungen, kein Include.
  Assert.AreEqual(InImpl(['procedure Foo;', 'begin', '  {$I+}', 'end;']),
    FixOk(InImpl(['procedure Foo;', 'var', '  X: Integer;', 'begin',
      '  {$I+}', 'end;']), 6, 'X'));
end;

procedure TTestRdxCleanupScope.Sca053_DirectiveNamesVar_NoHelp;
begin
  // FPC-Makro im Rumpf: X steht nur in der Direktive.
  AssertRefused(InImpl(['procedure Foo;', 'var', '  X: Integer;', 'begin',
    '  {$DEFINE M := X}', '  M := 1;', 'end;']), 6, 'X', 'Direktive nennt');
end;

procedure TTestRdxCleanupScope.Sca053_MacroInFile_NoHelp;
begin
  // Das Makro steht vor der Routine, im Rumpf nur sein Name.
  AssertRefused(InImpl(['{$MACRO ON}', '{$DEFINE Cnt:=X}', 'procedure Foo;',
    'var', '  X: Integer;', 'begin', '  Cnt := 1;', 'end;']), 8, 'X',
    'Makro');
  // Ohne ':=' ist {$DEFINE X} ein Symbol, kein Makro - die Hilfe bleibt.
  Assert.AreEqual(InImpl(['{$DEFINE X}', 'procedure Foo;', 'begin', 'end;']),
    FixOk(InImpl(['{$DEFINE X}', 'procedure Foo;', 'var', '  X: Integer;',
      'begin', 'end;']), 7, 'X'));
end;

// ---- Minor 1 ----

procedure TTestRdxCleanupScope.Sca053_ParameterInOpenParen_NoHelp;
begin
  // Pruefer-Faelle: Parameter eines Prozedurtyps ...
  AssertRefused(InImpl(['procedure Foo;', 'var', '  F: function(',
    '    var X: Integer;', '    Y: Integer): Boolean;', 'begin', '  F := nil;',
    'end;']), 7, 'X', 'offenen Klammer');
  // ... und einer lokalen Routine (aus Inner(A, A) wuerde ein Aufruf mit
  // zu vielen Argumenten, Y ein var-Parameter).
  AssertRefused(InImpl(['procedure Outer;', '  procedure Inner(',
    '    var X: Integer;', '    Y: Integer);', '  begin', '    Y := 0;',
    '  end;', 'var A: Integer;', 'begin', '  Inner(A, A);', 'end;']), 6, 'X',
    'offenen Klammer');
  // Hinter ';' in der Klammer (zweiter Parameter auf eigener Zeile) lehnte
  // schon die Suche nach dem var-Abschnitt ab - sie zaehlt Klammern.
  AssertRefused(InImpl(['procedure Outer;', '  procedure Inner(A: Integer;',
    '    X: Integer);', '  begin', '  end;', 'begin', '  Inner(1, 2);',
    'end;']), 6, 'X', 'var-Section');
end;

procedure TTestRdxCleanupScope.Sca053_SectionAfterLongHeader;
begin
  // Gegenprobe: die Parameterliste ist zu, der var-Abschnitt dahinter
  // gehoert der Routine - die Hilfe bleibt.
  Assert.AreEqual(InImpl(['procedure Foo(A: Integer;', '  B: Integer);',
    'begin', 'end;']),
    FixOk(InImpl(['procedure Foo(A: Integer;', '  B: Integer);', 'var',
      '  X: Integer;', 'begin', 'end;']), 7, 'X'));
end;

// ---- Verdacht 2 ----

procedure TTestRdxCleanupScope.Sca053_AsmInScope_NoHelp;
begin
  // Pruefer-Fall: asm spricht X ueber den Stack-Rahmen an.
  AssertRefused(InImpl(['procedure Foo;', 'var X: Integer;', 'begin', '  asm',
    '    mov eax, [ebp-4]', '  end;', 'end;']), 5, 'X', 'asm');
  // Ein asm-Rumpf.
  AssertRefused(InImpl(['procedure Foo;', 'var', '  X: Integer;', 'asm',
    '  ret', 'end;']), 6, 'X', 'asm');
end;

// ---- Verdacht 1 ----

procedure TTestRdxCleanupScope.Sca053_UmlautSpelling_NoHelp;
var
  Lower, Upper : string;
begin
  // Pruefer-Fall (casesuni): 'Groesse' mit Umlaut und sz, verwendet in
  // Grossschreibung - Delphi sieht denselben Bezeichner.
  Lower := 'Gr' + #$00F6 + #$00DF + 'e';
  Upper := 'GR' + #$00D6 + #$00DF + 'E';
  AssertRefused(InImpl(['procedure P;', 'var', '  ' + Lower + ': Integer;',
    'begin', '  ' + Upper + ' := 1;', 'end;']), 6, Lower, 'noch vor');
end;

// ---- Ende des Gueltigkeitsbereichs (ReadRoutine) ----

procedure TTestRdxCleanupScope.Sca053_EndAsIdentifier_NoHelp;
begin
  // 'End' als benanntes OLE-Argument (Korpus: cnwizards LittleTest43): der
  // alte Leser endete dort, sah 'X := 1' nicht und bot die Hilfe an - nach
  // ihr uebersetzte die Unit nicht mehr. ReadRoutine verlangt hinter dem
  // end ein ';'.
  AssertRefused(InImpl(['procedure P;', 'var', '  X: Integer;', 'begin',
    '  Rng := Doc.Range(start := 0, End := 0);', '  X := 1;', 'end;']), 6, 'X',
    'Rumpf der Routine nicht gefunden');
end;

procedure TTestRdxCleanupScope.Sca053_LocalRoutineBeforeSection;
begin
  // Vor der var-Section steht eine lokale Routine: der Bereich ist der
  // Rumpf der aeusseren Routine - die Verwendung dort sperrt ...
  AssertRefused(InImpl(['procedure Outer;', '  procedure Inner;', '  begin',
    '  end;', 'var', '  X: Integer;', 'begin', '  Inner;', '  X := 1;',
    'end;']), 9, 'X', 'noch vor');
  // ... ohne sie hilft die Hilfe.
  Assert.AreEqual(InImpl(['procedure Outer;', '  procedure Inner;', '  begin',
      '  end;', 'begin', '  Inner;', 'end;']),
    FixOk(InImpl(['procedure Outer;', '  procedure Inner;', '  begin', '  end;',
      'var', '  X: Integer;', 'begin', '  Inner;', 'end;']), 9, 'X'));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxCleanupScope);

end.
