unit uTestRdxTryLocks;

// Quick-Fixes try/finally (uRdxTryFixes, Charge H4) an Sperren und Puffern
// auf Text - ohne Parser, ohne Detektor (reDelphix.Test UND FPC-
// Pruefstand):
//   SCA153 UnpairedLock - Lock/UnLock, Acquire/Release, eigene Methode
//          'Lock;', EnterCriticalSection/LeaveCriticalSection (auch
//          qualifiziert); die Freigabe bestimmt der Planer selbst (derselbe
//          Empfaenger, Text ohne Leerraum gleich - fremde und
//          'Self.FLock' gegen 'FLock' zaehlen nicht);
//   SCA109 LockWithoutTryFinally - Enter/Leave, BeginWrite/EndWrite,
//          TMonitor.Enter/Exit(O), 'EnterCriticalSection(...)';
//   SCA156 GetMemWithoutFreeMem - GetMem(P, N), P := AllocMem(N),
//          P := GetMem(N) (FPC); FreeMem(P[, N]).
// Sperren je eine: Frueh-Freigabe, zweite Sperre, Exit, Break nach aussen
// (in einer inneren Schleife geht es), umschliessender Handler mit der
// Freigabe, TMonitor.Enter mit Timeout, mehrdeutige bzw. verschobene Zeile;
// ReallocMem, Result, kein einfacher Zeiger, Zeiger veraendert, Exit mit
// Weitergabe. Objekte (SCA009/SCA001) und die Form des Bausteins:
// uTestRdxTryFixes.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxTryLocks = class
  public
    [Test] procedure Sca153_LockUnlock;
    [Test] procedure Sca153_OwnMethod;
    [Test] procedure Sca153_CriticalSection;
    [Test] procedure Sca153_PartnerByText;
    [Test] procedure Sca153_EarlyReleaseAndSecondLock;
    [Test] procedure Sca153_JumpsAndLoops;
    [Test] procedure Sca153_MovedOrAmbiguous;
    [Test] procedure Sca109_EnterLeave;
    [Test] procedure Sca109_BeginWriteAndAcquire;
    [Test] procedure Sca109_Monitor;
    [Test] procedure Sca109_CriticalSection;
    [Test] procedure Sca109_HandlerReleases;
    [Test] procedure Sca156_GetMem;
    [Test] procedure Sca156_AllocMemAndFunctionForm;
    [Test] procedure Sca156_Refusals;
    [Test] procedure Sca156_PointerChanged;
    [Test] procedure Sca156_ExitAndEscape;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxBufferMath, uRdxCodeMap, uRdxTryFixes;

const
  MSG_109 = 'Lock acquired (%s) but no enclosing try..finally - an exception '
    + 'between Enter and Leave/Release leaves the lock permanently held. Wrap '
    + 'in try..finally with the matching Leave/Release in the finally block.';
  MSG_153 = 'Lock/Enter without surrounding try/finally - exception leaks the '
    + 'lock (%s)';
  MSG_156 = '%s without surrounding try/finally - exception leaks the buffer';

type
  TRule = (r109, r153, r156);

// ---- Helfer ----

function Apply(const ASource: string; const AEdit: TRdxEdit): string;
var
  Bytes : TBytes;
  Edits : TArray<TRdxEdit>;
  Plan  : TArray<TRdxByteEdit>;
  Err   : string;
begin
  SetLength(Edits, 1);
  Edits[0] := AEdit;
  Bytes := TEncoding.UTF8.GetBytes(ASource);
  Assert.IsTrue(PlanByteEdits(Bytes, Edits, Plan, Err), Err);
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

// Eine Unit mit Routine P; ALines ist ihr Rumpf (ab Zeile 6).
function InProc(const ALines: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'implementation', 'procedure P;',
    'begin']) + #13#10 + Join(ALines) + #13#10 + Join(['end;', 'end.']);
end;

// Der Plan der Hilfe ARule fuer Zeile ALine mit dem Meldungsteil AText.
function PlanAt(ARule: TRule; const ASource: string; ALine: Integer;
  const AText: string; out AReason: string): TRdxTryPlan;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    case ARule of
      r109: TRdxTryFixes.LockWithoutFinally(Map, ALine,
        Format(MSG_109, [AText]), Result, AReason);
      r153: TRdxTryFixes.UnpairedLock(Map, ALine, Format(MSG_153, [AText]),
        Result, AReason);
    else
      TRdxTryFixes.GetMemWithoutFree(Map, ALine, Format(MSG_156, [AText]),
        Result, AReason);
    end;
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Dasselbe fuer Zeile 6 (die erste des Rumpfs).
function PlanOf(ARule: TRule; const ASource, AText: string;
  out AReason: string): TRdxTryPlan;
begin
  Result := PlanAt(ARule, ASource, 6, AText, AReason);
end;

// Neuer Text oder '' bei Ablehnung (AReason).
function FixAt(ARule: TRule; const ASource: string; ALine: Integer;
  const AText: string; out AReason: string): string;
var
  P : TRdxTryPlan;
begin
  Result := '';
  P := PlanAt(ARule, ASource, ALine, AText, AReason);
  if AReason = '' then
    Result := Apply(ASource, P.Edit);
end;

function Fix(ARule: TRule; const ASource, AText: string;
  out AReason: string): string;
begin
  Result := FixAt(ARule, ASource, 6, AText, AReason);
end;

// Keine Hilfe fuer A auf Zeile ALine, und APart steht im Grund.
procedure AssertRefusedAt(ARule: TRule; const ASource: string; ALine: Integer;
  const AText, APart: string);
var
  R : string;
begin
  Assert.AreEqual('', FixAt(ARule, ASource, ALine, AText, R), 'keine Hilfe');
  Assert.IsTrue(Pos(APart, R) > 0, R);
end;

procedure AssertRefused(ARule: TRule; const ASource, AText, APart: string);
begin
  AssertRefusedAt(ARule, ASource, 6, AText, APart);
end;

// Die Form der Hilfe: A, dann try, S eine Stufe tiefer, finally, B, end.
function Wrapped(const A, S, B: string): string;
begin
  Result := InProc(['  ' + A, '  try', '    ' + S, '  finally', '    ' + B,
    '  end;']);
end;

function Plain(const A, S, B: string): string;
begin
  Result := InProc(['  ' + A, '  ' + S, '  ' + B]);
end;

// ---- SCA153 ----

procedure TTestRdxTryLocks.Sca153_LockUnlock;
var
  R : string;
  P : TRdxTryPlan;
begin
  // Katalog-Beispiel.
  Assert.AreEqual(Wrapped('FLocker.Lock;', 'DoStuff;', 'FLocker.UnLock;'),
    Fix(r153, Plain('FLocker.Lock;', 'DoStuff;', 'FLocker.UnLock;'),
      'FLocker.Lock', R), R);
  P := PlanOf(r153, Plain('FLocker.Lock;', 'DoStuff;', 'FLocker.UnLock;'),
    'FLocker.Lock', R);
  Assert.AreEqual('FLocker', P.Name, 'Menuetext: die Sperre');
  // Acquire/Release, Gross/klein frei, leere Klammern.
  Assert.AreEqual(Wrapped('FCS.Acquire();', 'X := 1;', 'fcs.release;'),
    Fix(r153, Plain('FCS.Acquire();', 'X := 1;', 'fcs.release;'),
      'FCS.Acquire', R), R);
end;

procedure TTestRdxTryLocks.Sca153_OwnMethod;
var
  R : string;
begin
  // Die eigene Methode 'Lock;' und ihr 'UnLock;' (mORMot).
  Assert.AreEqual(Wrapped('Lock;', 'Foo;', 'Unlock;'),
    Fix(r153, Plain('Lock;', 'Foo;', 'Unlock;'), 'Lock', R), R);
  // Der Empfaenger ueber einen Pfad mit Index.
  Assert.AreEqual(Wrapped('FLocks[I].Lock;', 'Foo;', 'FLocks[I].UnLock;'),
    Fix(r153, Plain('FLocks[I].Lock;', 'Foo;', 'FLocks[I].UnLock;'), 'Lock',
      R), R);
end;

procedure TTestRdxTryLocks.Sca153_CriticalSection;
var
  R : string;
begin
  Assert.AreEqual(Wrapped('EnterCriticalSection(FCS);', 'Foo;',
    'LeaveCriticalSection(FCS);'),
    Fix(r153, Plain('EnterCriticalSection(FCS);', 'Foo;',
      'LeaveCriticalSection(FCS);'), 'EnterCriticalSection', R), R);
  // Qualifiziert, Argument mit anderem Leerraum, Freigabe unqualifiziert.
  Assert.AreEqual(Wrapped('Windows.EnterCriticalSection(Self.FCS);', 'Foo;',
    'LeaveCriticalSection(Self . FCS);'),
    Fix(r153, Plain('Windows.EnterCriticalSection(Self.FCS);', 'Foo;',
      'LeaveCriticalSection(Self . FCS);'), 'Windows.EnterCriticalSection', R),
    R);
  // Ein anderes Argument ist eine andere Sperre.
  AssertRefused(r153, Plain('EnterCriticalSection(FCS);', 'Foo;',
    'LeaveCriticalSection(FOther);'), 'EnterCriticalSection',
    'keine Freigabe LeaveCriticalSection(FCS)');
end;

procedure TTestRdxTryLocks.Sca153_PartnerByText;
var
  R : string;
begin
  // Die Freigabe eines fremden Objekts dazwischen ist eine Anweisung wie
  // jede andere (der Detektor nahm sie als Partner).
  Assert.AreEqual(InProc(['  FLock.Lock;', '  try', '    FOther.UnLock;',
    '    Foo;', '  finally', '    FLock.UnLock;', '  end;']),
    Fix(r153, InProc(['  FLock.Lock;', '  FOther.UnLock;', '  Foo;',
      '  FLock.UnLock;']), 'FLock.Lock', R), R);
  // Nur eine fremde Freigabe: keine Hilfe.
  AssertRefused(r153, Plain('FLock.Lock;', 'Foo;', 'FOther.Release;'),
    'FLock.Lock', 'keine Freigabe FLock.UnLock');
  // 'Self.FLock' und 'FLock' sind als Text verschieden.
  AssertRefused(r153, Plain('Self.FLock.Lock;', 'Foo;', 'FLock.UnLock;'),
    'FLock.Lock', 'keine Freigabe Self.FLock.UnLock');
  Assert.AreEqual(Wrapped('Self.FLock.Lock;', 'Foo;', 'Self.FLock.UnLock;'),
    Fix(r153, Plain('Self.FLock.Lock;', 'Foo;', 'Self.FLock.UnLock;'),
      'FLock.Lock', R), R);
end;

procedure TTestRdxTryLocks.Sca153_EarlyReleaseAndSecondLock;
begin
  AssertRefused(r153, InProc(['  FLock.Lock;', '  if C then', '  begin',
    '    FLock.UnLock;', '    Exit;', '  end;', '  Foo;', '  FLock.UnLock;']),
    'FLock.Lock', 'FLock.UnLock in Zeile 9');
  AssertRefused(r153, InProc(['  FLock.Lock;', '  FLock.Lock;', '  Foo;',
    '  FLock.UnLock;', '  FLock.UnLock;']), 'FLock.Lock', 'noch einmal');
end;

procedure TTestRdxTryLocks.Sca153_JumpsAndLoops;
var
  R : string;
begin
  // Exit: Konzept - Ablehnung (der Ausstieg gaebe die Sperre jetzt frei).
  AssertRefused(r153, InProc(['  FLock.Lock;', '  if C then', '    Exit;',
    '  FLock.UnLock;']), 'FLock.Lock', 'Exit in Zeile 8');
  // Break aus einer Schleife um den Bereich.
  AssertRefusedAt(r153, InProc(['  repeat', '    FLock.Lock;',
    '    if C then Break;', '    FLock.UnLock;', '  until D;']), 7,
    'FLock.Lock', 'break in Zeile 8');
  // Break in einer Schleife ganz im Bereich: geht.
  Assert.AreEqual(InProc(['  FLock.Lock;', '  try',
    '    for I := 0 to N do', '      if A[I] then', '        Break;',
    '  finally', '    FLock.UnLock;', '  end;']),
    Fix(r153, InProc(['  FLock.Lock;', '  for I := 0 to N do',
      '    if A[I] then', '      Break;', '  FLock.UnLock;']), 'FLock.Lock', R),
    R);
end;

procedure TTestRdxTryLocks.Sca153_MovedOrAmbiguous;
begin
  AssertRefused(r153, Plain('FLock.Lock;', 'Foo;', 'FLock.UnLock;'),
    'FOther.Lock', 'keine Sperre "FOther.Lock"');
  AssertRefused(r153, Plain('FLock.Lock; FLock.Lock;', 'Foo;',
    'FLock.UnLock;'), 'FLock.Lock', 'mehrdeutig');
  AssertRefused(r153, InProc(['  if C then FLock.Lock;', '  Foo;',
    '  FLock.UnLock;']), 'FLock.Lock', 'allein hinter then');
  // Lock mit Argumenten ist keine Sperre (D3D-Puffer).
  AssertRefused(r153, Plain('Buf.Lock(0, 0);', 'Foo;', 'Buf.UnLock;'),
    'Buf.Lock', 'keine Sperre');
end;

// ---- SCA109 ----

procedure TTestRdxTryLocks.Sca109_EnterLeave;
var
  R : string;
begin
  // Katalog-Beispiel.
  Assert.AreEqual(Wrapped('FLock.Enter;', 'DoWork;', 'FLock.Leave;'),
    Fix(r109, Plain('FLock.Enter;', 'DoWork;', 'FLock.Leave;'), 'FLock', R), R);
  // Die Meldung nennt das Wort vor '.Enter' - auch hinter 'Self.'.
  Assert.AreEqual(Wrapped('Self.FLock.Enter;', 'DoWork;',
    'Self.FLock.Leave;'),
    Fix(r109, Plain('Self.FLock.Enter;', 'DoWork;', 'Self.FLock.Leave;'),
      'FLock', R), R);
end;

procedure TTestRdxTryLocks.Sca109_BeginWriteAndAcquire;
var
  R : string;
begin
  Assert.AreEqual(Wrapped('FSync.BeginWrite;', 'FList.Add(X);',
    'FSync.EndWrite;'),
    Fix(r109, Plain('FSync.BeginWrite;', 'FList.Add(X);', 'FSync.EndWrite;'),
      'FSync', R), R);
  Assert.AreEqual(Wrapped('FCS.Acquire;', 'Foo;', 'FCS.Release;'),
    Fix(r109, Plain('FCS.Acquire;', 'Foo;', 'FCS.Release;'), 'FCS', R), R);
  // Die Freigabe muss zur Sperre passen (Enter -> Leave, nicht Release).
  AssertRefused(r109, Plain('FCS.Enter;', 'Foo;', 'FCS.Release;'), 'FCS',
    'keine Freigabe FCS.Leave');
end;

procedure TTestRdxTryLocks.Sca109_Monitor;
var
  R : string;
begin
  Assert.AreEqual(Wrapped('TMonitor.Enter(FList);', 'FList.Add(X);',
    'TMonitor.Exit(FList);'),
    Fix(r109, Plain('TMonitor.Enter(FList);', 'FList.Add(X);',
      'TMonitor.Exit(FList);'), 'TMonitor.Enter(flist)', R), R);
  Assert.AreEqual(Wrapped('TMonitor.Enter(Self);', 'Foo;',
    'TMonitor.Exit(Self);'),
    Fix(r109, Plain('TMonitor.Enter(Self);', 'Foo;', 'TMonitor.Exit(Self);'),
      'TMonitor.Enter(self)', R), R);
  // Mit Timeout ist Enter eine Bedingung, keine Sperre.
  AssertRefused(r109, Plain('TMonitor.Enter(FList, 100);', 'Foo;',
    'TMonitor.Exit(FList);'), 'TMonitor.Enter(flist)', 'keine Sperre');
end;

procedure TTestRdxTryLocks.Sca109_CriticalSection;
var
  R : string;
begin
  Assert.AreEqual(Wrapped('EnterCriticalSection(FCS);', 'Foo;',
    'LeaveCriticalSection(FCS);'),
    Fix(r109, Plain('EnterCriticalSection(FCS);', 'Foo;',
      'LeaveCriticalSection(FCS);'), 'EnterCriticalSection(...)', R), R);
end;

procedure TTestRdxTryLocks.Sca109_HandlerReleases;
begin
  // Das umschliessende except gibt die Sperre frei - nach dem Fix doppelt.
  AssertRefusedAt(r109, InProc(['  try', '    FLock.Enter;', '    Foo;',
    '    FLock.Leave;', '  except', '    FLock.Leave;', '    raise;', '  end;']),
    7, 'FLock', 'except-Teil');
end;

// ---- SCA156 ----

procedure TTestRdxTryLocks.Sca156_GetMem;
var
  R : string;
  P : TRdxTryPlan;
begin
  // Katalog-Beispiel.
  Assert.AreEqual(Wrapped('GetMem(P, 1024);', 'DoStuff(P);', 'FreeMem(P);'),
    Fix(r156, Plain('GetMem(P, 1024);', 'DoStuff(P);', 'FreeMem(P);'),
      'GetMem', R), R);
  P := PlanOf(r156, Plain('GetMem(Buf, 1024);', 'DoStuff(Buf);',
    'FreeMem(Buf);'), 'GetMem', R);
  Assert.AreEqual('Buf', P.Name, 'Menuetext: der Puffer');
  // FreeMem mit Groesse; P^ und P[i] sind Zugriffe.
  Assert.AreEqual(Wrapped('getmem ( P, N );', 'P^ := 0;', 'FreeMem(P, N);'),
    Fix(r156, Plain('getmem ( P, N );', 'P^ := 0;', 'FreeMem(P, N);'),
      'getmem', R), R);
end;

procedure TTestRdxTryLocks.Sca156_AllocMemAndFunctionForm;
var
  R : string;
begin
  Assert.AreEqual(Wrapped('P := AllocMem(1024);', 'DoStuff(P);',
    'FreeMem(P);'),
    Fix(r156, Plain('P := AllocMem(1024);', 'DoStuff(P);', 'FreeMem(P);'),
      'AllocMem', R), R);
  Assert.AreEqual(Wrapped('P := GetMem(1024);', 'DoStuff(P);',
    'FreeMem(P);'),
    Fix(r156, Plain('P := GetMem(1024);', 'DoStuff(P);', 'FreeMem(P);'),
      'GetMem', R), R);
end;

procedure TTestRdxTryLocks.Sca156_Refusals;
begin
  AssertRefused(r156, Plain('ReallocMem(P, 2048);', 'Foo;', 'FreeMem(P);'),
    'ReallocMem', 'ReallocMem');
  AssertRefused(r156, Plain('Result := AllocMem(N);', 'Foo;',
    'FreeMem(Result);'), 'AllocMem', 'Result');
  AssertRefused(r156, Plain('GetMem(Pointer(P), N);', 'Foo;', 'FreeMem(P);'),
    'GetMem', 'kein einfacher Bezeichner');
  AssertRefused(r156, Plain('P := MM.GetMem(N);', 'Foo;', 'FreeMem(P);'),
    'GetMem', 'eigenen Speichermanagers');
  // FreeMem nur bedingt.
  AssertRefused(r156, InProc(['  GetMem(P, N);', '  Foo;', '  if C then',
    '    FreeMem(P);']), 'GetMem', 'tiefer liegende');
end;

procedure TTestRdxTryLocks.Sca156_PointerChanged;
begin
  AssertRefused(r156, InProc(['  GetMem(P, N);', '  Inc(P, 4);',
    '  FreeMem(P);']), 'GetMem', 'veraendert den Zeiger');
  AssertRefused(r156, InProc(['  GetMem(P, N);', '  P := Q;', '  FreeMem(P);']),
    'GetMem', 'zweite Zuweisung');
  AssertRefused(r156, InProc(['  GetMem(P, N);', '  Swap(@P);',
    '  FreeMem(P);']), 'GetMem', '@P');
end;

procedure TTestRdxTryLocks.Sca156_ExitAndEscape;
var
  R : string;
begin
  // Exit mit P nur als Zugriff: FreeMem laeuft jetzt auch dort.
  Assert.AreEqual(InProc(['  GetMem(P, N);', '  try', '    if P^ = 0 then',
    '      Exit;', '  finally', '    FreeMem(P);', '  end;']),
    Fix(r156, InProc(['  GetMem(P, N);', '  if P^ = 0 then', '    Exit;',
      '  FreeMem(P);']), 'GetMem', R), R);
  // Exit, und P wird weitergegeben.
  AssertRefused(r156, InProc(['  GetMem(P, N);', '  if Keep(P) then',
    '    Exit;', '  FreeMem(P);']), 'GetMem', 'weitergegeben');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxTryLocks);

end.
