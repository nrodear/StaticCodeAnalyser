unit uTestRdxResultFixes;

// Quick-Fixes "Ergebnis" (uRdxResultFixes, Charge H5) auf Text - ohne
// Parser, ohne Detektor (laeuft in reDelphix.Test UND im FPC-Pruefstand):
//   SCA121 'Result := <Wert>;' - Form (Einrueckung wie die erste
//          Anweisung, sonst begin + Stufe, Tab; Einzeiler inline; Kommentar
//          bzw. Direktive hinter begin), Typ aus der Deklaration, generisch,
//          qualifiziert, Operator, lokale Routine; Sperren Skript-Unit,
//          FPC-Modus/{$X-}, asm, Direktive zwischen Kopf und begin,
//          specialize, mehrzeiliger Typ, veraltete Zeile. Seit Charge H5c
//          ein Literal fuer einfache Typen (False, 0, '''', nil) und
//          Default(T) nur fuer Records, Typparameter und Unbekanntes - die
//          Wertwahl, die Sperre alter Compiler und die Zuweisung im Rumpf
//          pruefen uTestRdxResultGuards;
//   SCA196 'Result := '''';' / 'Result := nil;' / 'VarClear(Result);' - die
//          umschliessende Routine von der Lese-Zeile aus (auch mit lokaler
//          Routine davor), Typbeweise (RTL-DynArray, 'array of' und
//          Interface der Unit); Sperren unbewiesener Typ, absolute Result,
//          Typ anders als in der Meldung, Zeile ohne Result; seit Charge B1
//          ein Typname, den die Unit auch lokal bzw. geschachtelt definiert
//          (Gegen-Review R5, R5-06).
// Dazu die Laufzeit der Planer SCA096/SCA097 auf einer grossen Unit (R5-07,
// ein Planerlauf statt je Frage ein Lauf ueber die ganze Datei).
// SCA096/SCA097 sonst: uTestRdxInheritedFixes; gegen die echten Detektoren:
// uTestRdxResultFixesDetector (nur Delphi).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxResultFixes = class
  public
    [Test] procedure Sca121_Basic;
    [Test] procedure Sca121_Indent;
    [Test] procedure Sca121_InlineOneLiner;
    [Test] procedure Sca121_CommentOrDirectiveAfterBegin;
    [Test] procedure Sca121_TypeFromDecl;
    [Test] procedure Sca121_GenericQualifiedOperator;
    [Test] procedure Sca121_LocalRoutine;
    [Test] procedure Refuse121_ScriptOrInclude;
    [Test] procedure Refuse121_NoResult;
    [Test] procedure Refuse121_AsmAndDirective;
    [Test] procedure Refuse121_TypeAndStale;
    [Test] procedure Sca196_String;
    [Test] procedure Sca196_NilKinds;
    [Test] procedure Sca196_Variant;
    [Test] procedure Sca196_Enclosing;
    [Test] procedure Refuse196_TypeNotProven;
    [Test] procedure Refuse196_Stale;
    [Test] procedure Refuse196_TypeScope;
    [Test] procedure Planners_LargeUnitInTime;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxBufferMath, uRdxCodeMap, uRdxResultFixes;

const
  MSG_121 = 'Function %s never assigns Result (return value undefined)';
  MSG_196 = 'Function %s reads Result before assigning it (Result appears '
    + 'on the right-hand side of its own first assignment) - for return type '
    + '%s, Result is a hidden var parameter aliasing the caller''s target '
    + 'variable and starts with its OLD content, not empty. Initialize Result '
    + 'first (e.g. Result := nil / Result := [] / Result := '''')';

// ---- Helfer ----

function Apply(const ASource: string; const AEdits: TArray<TRdxEdit>): string;
var
  Bytes : TBytes;
  Plan  : TArray<TRdxByteEdit>;
  Err   : string;
begin
  Bytes := TEncoding.UTF8.GetBytes(ASource);
  Assert.IsTrue(PlanByteEdits(Bytes, AEdits, Plan, Err), Err);
  Result := TEncoding.UTF8.GetString(ApplyByteEdits(Bytes, Plan));
end;

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

// Eine Unit: interface (ohne Typen) + implementation mit den Zeilen AImpl.
function InUnit(const AImpl: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'implementation']) + #13#10
    + Join(AImpl) + #13#10 + 'end.';
end;

// Die erste Zeile (1-basiert), die mit AStart beginnt (Leerraum davor
// zaehlt nicht); 0 ohne.
function LineOf(const ASource, AStart: string): Integer;
var
  SL : TStringList;
  i  : Integer;
begin
  Result := 0;
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    for i := 0 to SL.Count - 1 do
      if Copy(TrimLeft(SL[i]), 1, Length(AStart)) = AStart then
        Exit(i + 1);
  finally
    SL.Free;
  end;
end;

// Der Plan des Planers APlanner fuer Zeile ALine; AReason = '' heisst Hilfe.
function PlanOf(APlanner: TRdxResultPlanner; const ASource: string;
  ALine: Integer; const AMessage: string; out AReason: string): TRdxResultPlan;
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

// SCA121 an der Zeile, die mit AHead beginnt: neuer Text oder '' (AReason).
function Fix121(const ASource, AHead, AName: string; out AReason: string): string;
var
  P : TRdxResultPlan;
begin
  Result := '';
  P := PlanOf(TRdxResultFixes.ResultDefault, ASource, LineOf(ASource, AHead),
    Format(MSG_121, [AName]), AReason);
  if AReason = '' then
    Result := Apply(ASource, P.Edits);
end;

// Die SCA196-Meldung fuer Funktion AName mit Rueckgabetyp AType.
function Msg196(const AName, AType: string): string;
begin
  Result := Format(MSG_196, [AName, AType]);
end;

// SCA196 an der Lese-Zeile, die mit ARead beginnt.
function Fix196(const ASource, ARead, AMessage: string; out AReason: string;
  out APlan: TRdxResultPlan): string;
begin
  Result := '';
  APlan := PlanOf(TRdxResultFixes.ManagedResultInit, ASource,
    LineOf(ASource, ARead), AMessage, AReason);
  if AReason = '' then
    Result := Apply(ASource, APlan.Edits);
end;

procedure AssertRefused121(const ASource, AHead, AName, APart: string);
var
  R : string;
begin
  Assert.AreEqual('', Fix121(ASource, AHead, AName, R), 'keine Hilfe');
  Assert.IsTrue(Pos(APart, R) > 0, R);
end;

procedure AssertRefused196(const ASource, ARead, AName, AType, APart: string);
var
  R : string;
  P : TRdxResultPlan;
begin
  Assert.AreEqual('', Fix196(ASource, ARead, Msg196(AName, AType), R, P),
    'keine Hilfe');
  Assert.IsTrue(Pos(APart, R) > 0, R);
end;

const
  // Ein Typabschnitt ohne Belang (ein leeres offenes Array mag FPC nicht).
  NO_TYPES: array[0..0] of string = ('  TAlias = Integer;');

// Eine Funktion F mit Rueckgabetyp AType, deren Rumpf Result liest.
function ReadsResult(const ATypes: array of string; const AType: string): string;
begin
  Result := Join(['unit u;', 'interface', 'type']) + #13#10 + Join(ATypes)
    + #13#10 + Join(['implementation', 'function F: ' + AType + ';', 'begin',
    '  Use(Result);', 'end;', 'end.']);
end;

// ---- SCA121 ----

procedure TTestRdxResultFixes.Sca121_Basic;
var
  R : string;
  P : TRdxResultPlan;
  S : string;
begin
  S := InUnit(['function F(A: Integer): Integer;', 'begin', '  if A > 0 then',
    '    Log(''x'');', 'end;']);
  Assert.AreEqual(InUnit(['function F(A: Integer): Integer;', 'begin',
    '  Result := 0;', '  if A > 0 then', '    Log(''x'');',
    'end;']), Fix121(S, 'function F', 'F', R), R);
  P := PlanOf(TRdxResultFixes.ResultDefault, S, 4, Format(MSG_121, ['F']), R);
  Assert.AreEqual('0', P.Name);
  Assert.AreEqual<Integer>(1, Length(P.Edits));
  // Ein Programm uebersetzt der Compiler ebenso.
  S := Join(['program p;', 'function F: string;', 'begin', 'end;', 'begin',
    'end.']);
  Assert.AreEqual(Join(['program p;', 'function F: string;', 'begin',
    '  Result := '''';', 'end;', 'begin', 'end.']),
    Fix121(S, 'function F', 'F', R), R);
end;

procedure TTestRdxResultFixes.Sca121_Indent;
var
  R : string;
begin
  // wie die erste Anweisung (vier Leerzeichen bzw. ein Tab) ...
  Assert.AreEqual(InUnit(['function F: Boolean;', 'begin',
    '    Result := False;', '    Run;', 'end;']),
    Fix121(InUnit(['function F: Boolean;', 'begin', '    Run;', 'end;']),
      'function F', 'F', R), R);
  Assert.AreEqual(InUnit(['function F: Boolean;', 'begin',
    #9'Result := False;', #9'Run;', 'end;']),
    Fix121(InUnit(['function F: Boolean;', 'begin', #9'Run;', 'end;']),
      'function F', 'F', R), R);
  // ... im leeren Rumpf begin + eine Stufe (Tab, wenn begin Tabs traegt).
  Assert.AreEqual(InUnit(['function F: Boolean;', 'begin',
    '  Result := False;', 'end;']),
    Fix121(InUnit(['function F: Boolean;', 'begin', 'end;']), 'function F',
      'F', R), R);
  Assert.AreEqual(InUnit(['function F: Boolean;', #9'begin',
    #9#9'Result := False;', #9'end;']),
    Fix121(InUnit(['function F: Boolean;', #9'begin', #9'end;']),
      'function F', 'F', R), R);
end;

procedure TTestRdxResultFixes.Sca121_InlineOneLiner;
var
  R : string;
begin
  // Code hinter begin auf seiner Zeile: inline, ohne die Zeilen umzubrechen.
  Assert.AreEqual(InUnit(['function F: Integer; begin Result := 0; end;']),
    Fix121(InUnit(['function F: Integer; begin end;']), 'function F', 'F', R), R);
  Assert.AreEqual(InUnit(['function F: Integer;', 'begin Result := 0; Run;',
    'end;']),
    Fix121(InUnit(['function F: Integer;', 'begin Run;', 'end;']),
      'function F', 'F', R), R);
end;

procedure TTestRdxResultFixes.Sca121_CommentOrDirectiveAfterBegin;
var
  R : string;
begin
  // Ein '//'-Kommentar hinter begin bleibt dort, die Zeile kommt darunter.
  Assert.AreEqual(InUnit(['function F: Integer;', 'begin // Start',
    '  Result := 0;', '  Run;', 'end;']),
    Fix121(InUnit(['function F: Integer;', 'begin // Start', '  Run;', 'end;']),
      'function F', 'F', R), R);
  // Ein Kommentar ueber Zeilen bzw. eine Direktive hinter begin: inline
  // davor - eine neue Zeile laege im Kommentar bzw. im Zweig.
  Assert.AreEqual(InUnit(['function F: Integer;',
    'begin Result := 0; { lang', '  weiter }', '  Run;', 'end;']),
    Fix121(InUnit(['function F: Integer;', 'begin { lang', '  weiter }',
      '  Run;', 'end;']), 'function F', 'F', R), R);
  Assert.AreEqual(InUnit(['function F: Integer;',
    'begin Result := 0; {$IFDEF X}', '  Run;', '{$ENDIF}',
    'end;']),
    Fix121(InUnit(['function F: Integer;', 'begin {$IFDEF X}', '  Run;',
      '{$ENDIF}', 'end;']), 'function F', 'F', R), R);
end;

procedure TTestRdxResultFixes.Sca121_TypeFromDecl;
var
  R, S : string;
begin
  // Implementierungskopf ohne Signatur: der Typ aus der Deklaration
  // (TStrings, eine Klasse der Delphi-Quellen: nil).
  S := Join(['unit u;', 'interface', 'type', '  TFoo = class',
    '    function Bar(A: Integer): TStrings;', '  end;', 'implementation',
    'function TFoo.Bar;', 'begin', 'end;', 'end.']);
  Assert.AreEqual(Join(['unit u;', 'interface', 'type', '  TFoo = class',
    '    function Bar(A: Integer): TStrings;', '  end;', 'implementation',
    'function TFoo.Bar;', 'begin', '  Result := nil;', 'end;',
    'end.']), Fix121(S, 'function TFoo.Bar', 'Bar', R), R);
  // Overload in der Deklaration: welcher Typ, ist offen.
  S := Join(['unit u;', 'interface', 'type', '  TFoo = class',
    '    function Bar(A: Integer): TStrings; overload;',
    '    function Bar: Integer; overload;', '  end;', 'implementation',
    'function TFoo.Bar;', 'begin', 'end;', 'end.']);
  AssertRefused121(S, 'function TFoo.Bar', 'Bar', 'Overload');
end;

procedure TTestRdxResultFixes.Sca121_GenericQualifiedOperator;
var
  R : string;
begin
  // Typparameter und Record: Default(T); eine generische Klasse der
  // Delphi-Quellen (qualifiziert): nil.
  Assert.AreEqual(InUnit(['function TBox<T>.Get: T;', 'begin',
    '  Result := Default(T);', 'end;']),
    Fix121(InUnit(['function TBox<T>.Get: T;', 'begin', 'end;']),
      'function TBox', 'Get', R), R);
  Assert.AreEqual(InUnit(['function F: System.Generics.Collections.TList<Integer>;',
    'begin', '  Result := nil;',
    'end;']),
    Fix121(InUnit(['function F: System.Generics.Collections.TList<Integer>;',
      'begin', 'end;']), 'function F', 'F', R), R);
  Assert.AreEqual(InUnit(['class operator TRec.Add(const A, B: TRec): TRec;',
    'begin', '  Result := Default(TRec);', 'end;']),
    Fix121(InUnit(['class operator TRec.Add(const A, B: TRec): TRec;', 'begin',
      'end;']), 'class operator', 'Add', R), R);
end;

procedure TTestRdxResultFixes.Sca121_LocalRoutine;
var
  R : string;
begin
  // Lokale Routine und var-Abschnitt zwischen Kopf und begin: eingefuegt
  // hinter dem begin der aeusseren Routine.
  Assert.AreEqual(InUnit(['function F: Integer;', '  procedure Inner;',
    '  begin', '    Log(''x'');', '  end;', 'var', '  I: Integer;', 'begin',
    '  Result := 0;', '  Inner;', 'end;']),
    Fix121(InUnit(['function F: Integer;', '  procedure Inner;', '  begin',
      '    Log(''x'');', '  end;', 'var', '  I: Integer;', 'begin', '  Inner;',
      'end;']), 'function F', 'F', R), R);
end;

procedure TTestRdxResultFixes.Refuse121_ScriptOrInclude;
begin
  // xEdit-/JvInterpreter-Skript: 'unit' ohne implementation-Teil.
  AssertRefused121(Join(['unit UserScript;', 'function Initialize: integer;',
    'begin', 'end;', 'end.']), 'function Initialize', 'Initialize',
    'ohne implementation-Teil');
  // Include-Datei bzw. Fragment ohne Kopf.
  AssertRefused121(Join(['function F: Integer;', 'begin', 'end;']),
    'function F', 'F', 'Include oder Skript');
end;

procedure TTestRdxResultFixes.Refuse121_NoResult;
var
  R : string;
begin
  AssertRefused121(Join(['unit u;', '{$mode fpc}', 'interface',
    'implementation', 'function F: Integer;', 'begin', 'end;', 'end.']),
    'function F', 'F', '{$mode fpc}');
  AssertRefused121(Join(['unit u;', '{$X-}', 'interface', 'implementation',
    'function F: Integer;', 'begin', 'end;', 'end.']), 'function F', 'F',
    '{$X-}');
  AssertRefused121(Join(['unit u;', '{$H+,X-}', 'interface', 'implementation',
    'function F: Integer;', 'begin', 'end;', 'end.']), 'function F', 'F',
    '{$X-}');
  AssertRefused121(Join(['unit u;', '{$EXTENDEDSYNTAX OFF}', 'interface',
    'implementation', 'function F: Integer;', 'begin', 'end;', 'end.']),
    'function F', 'F', 'EXTENDEDSYNTAX');
  // objfpc und delphi kennen Result.
  Assert.AreNotEqual('', Fix121(Join(['unit u;', '{$mode objfpc}{$H+}',
    'interface', 'implementation', 'function F: Integer;', 'begin', 'end;',
    'end.']), 'function F', 'F', R), R);
end;

procedure TTestRdxResultFixes.Refuse121_AsmAndDirective;
begin
  AssertRefused121(InUnit(['function F: Integer;', 'asm', '  mov eax, 1',
    'end;']), 'function F', 'F', 'asm-Rumpf');
  AssertRefused121(InUnit(['function F: Integer;', 'begin', '  asm',
    '    mov eax, 1', '  end;', 'end;']), 'function F', 'F', 'asm im Rumpf');
  AssertRefused121(InUnit(['function F: Integer;', '{$IFDEF X}', 'var',
    '  I: Integer;', '{$ENDIF}', 'begin', 'end;']), 'function F', 'F',
    'Direktive zwischen Kopf und begin');
end;

procedure TTestRdxResultFixes.Refuse121_TypeAndStale;
begin
  AssertRefused121(InUnit(['function F: specialize TList<Integer>;', 'begin',
    'end;']), 'function F', 'F', 'specialize');
  AssertRefused121(InUnit(['function F:', '  Integer;', 'begin', 'end;']),
    'function F', 'F', 'mehrere Zeilen');
  // Freie Funktion ohne Signatur (Deklaration im interface-Teil).
  AssertRefused121(InUnit(['function F;', 'begin', 'end;']), 'function F', 'F',
    'keine Methode');
  // Anderer Name: Zeile verschoben.
  AssertRefused121(InUnit(['function G: Integer;', 'begin', 'end;']),
    'function G', 'F', 'Zeile verschoben');
end;

// ---- SCA196 ----

procedure TTestRdxResultFixes.Sca196_String;
var
  R, S : string;
  P    : TRdxResultPlan;
begin
  S := InUnit(['function Join(const A: array of string): string;', 'var',
    '  I: Integer;', 'begin', '  for I := 0 to High(A) do',
    '    Result := Result + A[I];', 'end;']);
  Assert.AreEqual(InUnit(['function Join(const A: array of string): string;',
    'var', '  I: Integer;', 'begin', '  Result := '''';',
    '  for I := 0 to High(A) do', '    Result := Result + A[I];', 'end;']),
    Fix196(S, 'Result := Result', Msg196('Join', 'string'), R, P), R);
  Assert.AreEqual('Result := ''''', P.Name);
  Assert.IsFalse(P.NeedsVariants);
  // ShortString und System.-Praefix gehoeren zur string-Familie.
  S := ReadsResult(NO_TYPES, 'System.ShortString');
  Assert.AreEqual('Result := ''''', PlanOf(TRdxResultFixes.ManagedResultInit,
    S, LineOf(S, 'Use(Result)'), Format(MSG_196, ['F', 'System.ShortString']),
    R).Name, R);
end;

procedure TTestRdxResultFixes.Sca196_NilKinds;
const
  TYPES: array[0..4] of string = ('TArray<string>', 'TBytes',
    'TStringDynArray', 'TInts', 'IFoo');
var
  R, T, S : string;
  P       : TRdxResultPlan;
begin
  for T in TYPES do
  begin
    // 'TInts = array of' und 'IFoo = interface' stehen in der Unit.
    S := ReadsResult(['  TInts = array of Integer;', '  IFoo = interface',
      '  end;'], T);
    Assert.AreEqual(StringReplace(S, 'begin', 'begin'#13#10'  Result := nil;',
      []), Fix196(S, 'Use(Result)', Msg196('F', T), R, P), T + ': ' + R);
    Assert.AreEqual('Result := nil', P.Name, T);
  end;
end;

procedure TTestRdxResultFixes.Sca196_Variant;
var
  R, S : string;
  P    : TRdxResultPlan;
begin
  S := ReadsResult(NO_TYPES, 'Variant');
  Assert.AreEqual(StringReplace(S, 'begin', 'begin'#13#10'  VarClear(Result);',
    []), Fix196(S, 'Use(Result)', Msg196('F', 'Variant'), R, P), R);
  Assert.AreEqual('VarClear(Result)', P.Name);
  Assert.IsTrue(P.NeedsVariants, 'Variants in uses');
  S := ReadsResult(NO_TYPES, 'OleVariant');
  P := PlanOf(TRdxResultFixes.ManagedResultInit, S, LineOf(S, 'Use(Result)'),
    Format(MSG_196, ['F', 'OleVariant']), R);
  Assert.IsTrue(P.NeedsVariants, R);
end;

procedure TTestRdxResultFixes.Sca196_Enclosing;
var
  R, S : string;
  P    : TRdxResultPlan;
begin
  // Die Lese-Zeile im Rumpf der aeusseren Routine, eine lokale Funktion
  // mit eigenem Result davor: eingefuegt hinter dem aeusseren begin.
  S := InUnit(['function Outer: string;', '  function Inner: Integer;',
    '  begin', '    Result := 1;', '  end;', 'begin',
    '  Result := Result + IntToStr(Inner);', 'end;']);
  Assert.AreEqual(InUnit(['function Outer: string;',
    '  function Inner: Integer;', '  begin', '    Result := 1;', '  end;',
    'begin', '  Result := '''';', '  Result := Result + IntToStr(Inner);',
    'end;']), Fix196(S, 'Result := Result', Msg196('Outer', 'string'), R, P), R);
  // Liegt die Zeile in der lokalen Routine, heisst die Routine anders.
  S := InUnit(['function Outer: Integer;', '  function Inner: string;',
    '  begin', '    Result := Result + ''x'';', '  end;', 'begin',
    '  Result := Length(Inner);', 'end;']);
  AssertRefused196(S, 'Result := Result', 'Outer', 'string',
    'die Routine heisst Inner');
end;

procedure TTestRdxResultFixes.Refuse196_TypeNotProven;
begin
  // Ein I-Typ, den die Unit nicht als Interface deklariert (kann ein Record
  // sein), ein '*DynArray' ohne Deklaration.
  AssertRefused196(ReadsResult(NO_TYPES, 'IFremd'), 'Use(Result)', 'F', 'IFremd',
    'nicht als String');
  AssertRefused196(ReadsResult(NO_TYPES, 'TFooDynArray'), 'Use(Result)', 'F',
    'TFooDynArray', 'nicht als String');
  AssertRefused196(InUnit(['function F: string;', 'var',
    '  S: string absolute Result;', 'begin', '  Use(Result);', 'end;']),
    'Use(Result)', 'F', 'string', 'absolute Result');
end;

procedure TTestRdxResultFixes.Refuse196_Stale;
var
  R, S : string;
begin
  AssertRefused196(ReadsResult(NO_TYPES, 'AnsiString'), 'Use(Result)', 'F', 'string',
    'der Kopf nennt AnsiString');
  AssertRefused196(InUnit(['function F: string;', 'begin', '  Use(X);',
    'end;']), 'Use(X)', 'F', 'string', 'kein Result');
  S := ReadsResult(NO_TYPES, 'string');
  Assert.AreEqual('', PlanOf(TRdxResultFixes.ManagedResultInit, S,
    LineOf(S, 'Use(Result)'), 'Function F reads Result before', R).Name);
  Assert.IsTrue(Pos('fehlt in der Meldung', R) > 0, R);
end;

// Die Unit definiert den Typnamen auch lokal in einer anderen Routine bzw.
// geschachtelt in einer Klasse (Gegen-Review R5, R5-06; Pruefer-Fixtures
// R5/r4.txt, R5_verify/v06b.txt): welche Definition gilt, haengt am
// Gueltigkeitsbereich - bis Charge B1 'Result := nil;' fuer mORMots RawUtf8
// (ein String) wegen eines lokalen 'RawUtf8 = array of Byte'.
procedure TTestRdxResultFixes.Refuse196_TypeScope;
begin
  AssertRefused196(InUnit(['procedure Helper;', 'type',
    '  RawUtf8 = array of Byte;', 'var', '  X: RawUtf8;', 'begin',
    '  SetLength(X, 1);', 'end;', 'function Join(const A: RawUtf8): RawUtf8;',
    'begin', '  Result := Result + A;', 'end;']), 'Result := Result', 'Join',
    'RawUtf8', 'Gueltigkeitsbereich');
  AssertRefused196(Join(['unit u;', 'interface', 'type', '  TA = class',
    '  public type', '    TItems = array of Integer;', '  end;',
    'implementation', 'function GetItems: TItems;', 'begin',
    '  Result := Result + [1];', 'end;', 'end.']), 'Result := Result',
    'GetItems', 'TItems', 'Gueltigkeitsbereich');
end;

// Die Unit von Planers_LargeUnitInTime: TFoo erbt von TBase (in der Unit),
// TBase von TComponent (nicht in der Unit); der Konstruktor ruft ACalls
// verschiedene Prozeduren, AFillers Klassen fuellen die Datei.
function LargeUnit(AFillers, ACalls: Integer): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('unit u;'#13#10'interface'#13#10'type'#13#10);
    SB.Append('  TBase = class(TComponent)'#13#10'  public'#13#10);
    SB.Append('    constructor Create(A: Integer); virtual;'#13#10'  end;'#13#10);
    SB.Append('  TFoo = class(TBase)'#13#10'  public'#13#10);
    SB.Append('    constructor Create(A: Integer); override;'#13#10);
    SB.Append('    destructor Destroy; override;'#13#10'  end;'#13#10);
    for i := 1 to AFillers do
      SB.Append(Format('  TFiller%d = class'#13#10'    procedure M;'#13#10
        + '  end;'#13#10, [i]));
    SB.Append('implementation'#13#10);
    SB.Append('constructor TFoo.Create(A: Integer);'#13#10'begin'#13#10);
    for i := 1 to ACalls do
      SB.Append(Format('  Init%d(A);'#13#10, [i]));
    SB.Append('end;'#13#10'destructor TFoo.Destroy;'#13#10'begin'#13#10);
    SB.Append('  Done;'#13#10'end;'#13#10);
    for i := 1 to AFillers do
      SB.Append(Format('procedure TFiller%d.M;'#13#10'begin'#13#10
        + '  Work(%d);'#13#10'end;'#13#10, [i, i]));
    SB.Append('end.');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Laufzeit (Gegen-Review R5, R5-07): SCA096 und SCA097 auf einer Unit von
// gut 20.000 Zeilen. Bis Charge B1 las jede Frage nach Klassenkopf bzw.
// Methodendeklaration die ganze Datei - fuer SCA096 je Aufruf im Rumpf die
// ganze Vorfahrenkette (gut 120 Laeufe, FPC-Pruefstand rund 5 s); jetzt ein
// Index je Planerlauf (rund 0,1 s). Die Schranke laesst Rechner-
// Schwankung mehr als Faktor 5 Luft.
procedure TTestRdxResultFixes.Planners_LargeUnitInTime;
const
  MAX_MS = 1500;
var
  S, R : string;
  P    : TRdxResultPlan;
  T0   : TDateTime;
  Ms   : Int64;
begin
  S := LargeUnit(3000, 20);
  T0 := Now;
  P := PlanOf(TRdxResultFixes.ConstructorInherited, S,
    LineOf(S, 'constructor TFoo.Create'), 'Constructor has no `inherited` '
    + 'call - parent class is not initialized.', R);
  Ms := Round((Now - T0) * MSecsPerDay);
  Assert.AreEqual('', R, 'SCA096 angeboten');
  Assert.AreEqual(STMT_INHERITED, P.Name);
  Assert.IsTrue(Ms < MAX_MS, Format('SCA096: %d ms', [Ms]));
  T0 := Now;
  P := PlanOf(TRdxResultFixes.DestructorInherited, S,
    LineOf(S, 'destructor TFoo.Destroy'), 'Destructor has no `inherited` '
    + 'call - parent class cleanup is skipped.', R);
  Ms := Round((Now - T0) * MSecsPerDay);
  Assert.AreEqual('', R, 'SCA097 angeboten');
  Assert.IsTrue(Ms < MAX_MS, Format('SCA097: %d ms', [Ms]));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxResultFixes);

end.
