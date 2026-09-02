unit uTestGetMemWithoutFreeMem;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestGetMemWithoutFreeMem = class
  public
    [Test] procedure GetMemWithoutTryFinally_Reported;
    [Test] procedure AllocMemWithoutTryFinally_Reported;
    [Test] procedure GetMemInTryFinally_NotReported;
    [Test] procedure GetMemWithoutMatchingFreeMem_NotReported;
    [Test] procedure GetMemIntoField_NoFinding;
    [Test] procedure GetMemLocalNoTry_StillReported;
    [Test] procedure Finding_KindAndSeverity;
    // Real-World FP-Audit 2026-07-10: escape via Result / lowercase-Feld
    [Test] procedure AllocMemToResult_NoFinding;
    [Test] procedure AllocMemToLowercaseField_NoFinding;
    // Doku-Quickwins 2026-07-25: Routinen-Grenzen-Clamp fuer den Lookahead
    [Test] procedure FreeMemOnlyInNextRoutine_NoFinding;
    [Test] procedure FreeMemFarApartSameRoutine_NoFinding;
    [Test] procedure PairedNoTryBeforeNextRoutine_StillReported;
    // Alloc INNERHALB eines schon offenen try (AQL-Stichprobe 02.09.,
    // 11 von 20 Funden). Der dritte Test ist der Waechter.
    [Test] procedure AllocInsideOpenTry_FreeInFinally_NoFinding;
    [Test] procedure AllocInsideOpenTry_FreeInExceptWithRaise_NoFinding;
    [Test] procedure AllocNoProtectionAtAll_StillReported;
    // Review 02.09.: ein Handler entlastet nur, solange sein try noch
    // OFFEN ist.
    [Test] procedure AllocInClosedTry_FreeMemOutside_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestGetMemWithoutFreeMem.GetMemWithoutTryFinally_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var P: PByte;'#13#10 +
  'begin'#13#10 +
  '  GetMem(P, 1024);'#13#10 +
  '  DoStuff(P);'#13#10 +
  '  FreeMem(P);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkGetMemWithoutFreeMem),
      'genau 1 GetMem-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'GetMem(P, 1024'),
      TFindingHelper.FirstOf(F, fkGetMemWithoutFreeMem).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestGetMemWithoutFreeMem.AllocMemWithoutTryFinally_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var P: Pointer;'#13#10 +
  'begin'#13#10 +
  '  P := AllocMem(256);'#13#10 +
  '  ProcessBuffer(P);'#13#10 +
  '  FreeMem(P);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkGetMemWithoutFreeMem),
      'genau 1 GetMem-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'AllocMem(256'),
      TFindingHelper.FirstOf(F, fkGetMemWithoutFreeMem).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestGetMemWithoutFreeMem.GetMemInTryFinally_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var P: PByte;'#13#10 +
  'begin'#13#10 +
  '  GetMem(P, 1024);'#13#10 +
  '  try'#13#10 +
  '    DoStuff(P);'#13#10 +
  '  finally'#13#10 +
  '    FreeMem(P);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGetMemWithoutFreeMem));
  finally F.Free; end;
end;

procedure TTestGetMemWithoutFreeMem.GetMemWithoutMatchingFreeMem_NotReported;
// Wenn KEIN FreeMem im Lookahead-Fenster ist, skipt der Detector
// (Ownership-Transfer / Custom-Allocator).
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo: Pointer;'#13#10 +
  'begin'#13#10 +
  '  GetMem(Result, 1024);'#13#10 +
  '  // caller takes ownership and frees it later'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGetMemWithoutFreeMem));
  finally F.Free; end;
end;

procedure TTestGetMemWithoutFreeMem.GetMemIntoField_NoFinding;
// FP-Guard B (2026-06-29): erstes Argument ist ein FELD (FXxx-Konvention).
// Ownership liegt dann beim Objekt, FreeMem im Destruktor - ausserhalb des
// Single-Routine-Scopes dieses Detektors. Trotz fehlendem try/finally:
// kein Befund, weil das Ziel ein Feld FBuffer ist.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  GetMem(FBuffer, 1024);'#13#10 +
  '  DoStuff(FBuffer);'#13#10 +
  '  FreeMem(FBuffer);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGetMemWithoutFreeMem),
    'GetMem in ein Feld FXxx ist Objekt-Ownership -> kein Single-Routine-Leak');
  finally F.Free; end;
end;

procedure TTestGetMemWithoutFreeMem.GetMemLocalNoTry_StillReported;
// Gegenprobe: lokale Variable (kleingeschrieben, kein F-Prefix, kein Feld),
// FreeMem ohne try/finally -> Leak bei Exception zwischen GetMem und FreeMem.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var P: PByte;'#13#10 +
  'begin'#13#10 +
  '  GetMem(P, 1024);'#13#10 +
  '  DoStuff(P);'#13#10 +
  '  FreeMem(P);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkGetMemWithoutFreeMem) >= 1,
    'GetMem in lokale Var ohne try/finally bleibt ein Leak-Treffer');
  finally F.Free; end;
end;

procedure TTestGetMemWithoutFreeMem.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var P: PByte;'#13#10 +
  'begin'#13#10 +
  '  GetMem(P, 1024);'#13#10 +
  '  DoStuff(P);'#13#10 +
  '  FreeMem(P);'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkGetMemWithoutFreeMem then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkGetMemWithoutFreeMem finding expected');
    Assert.AreEqual(lsWarning, Hit.Severity);
  finally F.Free; end;
end;

procedure TTestGetMemWithoutFreeMem.AllocMemToResult_NoFinding;
// Real-World FP-Audit 2026-07-10 'returns-pointer': 'Result := AllocMem(...)' ist
// eine Allocator-Rueckgabe - der Buffer verlaesst die Routine, das (in einem
// SEPARATEN Dispose-Proc liegende) FreeMem ist kein lokaler Leak.
const SRC =
  'unit t; implementation'#13#10 +
  'function Alloc: Pointer;'#13#10 +
  'begin'#13#10 +
  '  Result := AllocMem(256);'#13#10 +
  'end;'#13#10 +
  'procedure DisposeIt(P: Pointer);'#13#10 +
  'begin'#13#10 +
  '  FreeMem(P);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGetMemWithoutFreeMem),
    'Result := AllocMem -> Buffer escaped, kein lokaler Leak');
  finally F.Free; end;
end;

procedure TTestGetMemWithoutFreeMem.AllocMemToLowercaseField_NoFinding;
// Real-World FP-Audit 2026-07-10 'field-lifetime': 'fBuf := AllocMem' (mORMot-
// Feld-Konvention lowercase f) im Ctor, FreeMem im Dtor - RAII-Feld-Lifetime.
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  fBuf := AllocMem(256);'#13#10 +
  'end;'#13#10 +
  'destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  FreeMem(fBuf);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGetMemWithoutFreeMem),
    'fBuf := AllocMem -> Feld-Lifetime (RAII), kein lokaler Leak');
  finally F.Free; end;
end;

procedure TTestGetMemWithoutFreeMem.AllocInClosedTry_FreeMemOutside_StillReported;
// WAECHTER (Review 02.09.). Das try wird VOR dem FreeMem geschlossen -
// das finally raeumt nur die Critical Section auf, nicht den Puffer.
// Eine Ausnahme in DoWork laeuft durch das finally hindurch nach aussen,
// FreeMem hinter dem end wird nie erreicht: der Fund ist ECHT.
//
// Der erste Wurf des Handler-Gates schluckte ihn, weil er von "vor dem
// FreeMem stand ein finally" auf "das FreeMem gehoert dazu" schloss.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure X;'#13#10 +
  'var p: Pointer;'#13#10 +
  'begin'#13#10 +
  '  EnterCriticalSection(FCS);'#13#10 +
  '  try'#13#10 +
  '    GetMem(p, 128);'#13#10 +
  '    DoWork(p);'#13#10 +
  '  finally'#13#10 +
  '    LeaveCriticalSection(FCS);'#13#10 +
  '  end;'#13#10 +
  '  FreeMem(p);'#13#10 +
  'end;'#13#10 +
  'end.'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkGetMemWithoutFreeMem),
    'geschlossenes try entlastet das FreeMem dahinter nicht');
  finally F.Free; end;
end;

procedure TTestGetMemWithoutFreeMem.AllocInsideOpenTry_FreeInFinally_NoFinding;
// Erkennerfehler (02.09., AQL-Stichprobe): die Allokation steht
// INNERHALB eines bereits geoeffneten try. Dessen "try" liegt VOR der
// Alloc-Position, und der Detektor sucht es nur VORWAERTS - er sah es
// nie und meldete einen lehrbuchmaessig geschuetzten Puffer.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure A;'#13#10 +
  'var p: Pointer;'#13#10 +
  'begin'#13#10 +
  '  BeginWork;'#13#10 +
  '  try'#13#10 +
  '    GetMem(p, 128);'#13#10 +
  '    DoWork(p);'#13#10 +
  '  finally'#13#10 +
  '    FreeMem(p);'#13#10 +
  '  end;'#13#10 +
  'end;'#13#10 +
  'end.'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGetMemWithoutFreeMem),
    'Alloc in offenem try, FreeMem im finally - geschuetzt');
  finally F.Free; end;
end;

procedure TTestGetMemWithoutFreeMem.AllocInsideOpenTry_FreeInExceptWithRaise_NoFinding;
// Zweites Idiom derselben Ursache (7 der 11 Stichproben-Fehlalarme):
// "alloziere, gib im Erfolgsfall weiter, raeume nur im Fehlerfall auf".
// Das FreeMem steht im except-Handler mit anschliessendem raise.
const SRC =
  'unit t; implementation'#13#10 +
  'function B: Pointer;'#13#10 +
  'var q: Pointer;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    GetMem(q, 64);'#13#10 +
  '    DoWork(q);'#13#10 +
  '    Result := q;'#13#10 +
  '  except'#13#10 +
  '    FreeMem(q);'#13#10 +
  '    raise;'#13#10 +
  '  end;'#13#10 +
  'end;'#13#10 +
  'end.'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGetMemWithoutFreeMem),
    'FreeMem im except-Handler ist Aufraeumcode, kein fehlendes Pairing');
  finally F.Free; end;
end;

procedure TTestGetMemWithoutFreeMem.AllocNoProtectionAtAll_StillReported;
// WAECHTER: kein try, kein Handler - nur GetMem und FreeMem
// hintereinander. Eine Ausnahme dazwischen verliert den Puffer
// wirklich. Der Fund MUSS bleiben; faellt er weg, ist der neue Test zu
// breit und die Regel im haeufigsten Fall blind.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure C;'#13#10 +
  'var r: Pointer;'#13#10 +
  'begin'#13#10 +
  '  GetMem(r, 32);'#13#10 +
  '  DoWork(r);'#13#10 +
  '  FreeMem(r);'#13#10 +
  'end;'#13#10 +
  'end.'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkGetMemWithoutFreeMem),
    'ohne try und ohne Handler bleibt der Fund');
  finally F.Free; end;
end;

procedure TTestGetMemWithoutFreeMem.FreeMemOnlyInNextRoutine_NoFinding;
// FP-Guard D (Doku-Quickwins 2026-07-25): Das Lookahead-Fenster lief bisher
// ueber das Routinen-Ende hinaus - das FreeMem der NACHBAR-Routine (hier ein
// Allocator/Disposer-Paar) galt als lokales Pairing und triggerte den Fund.
// Mit Routinen-Grenzen-Clamp: FreeMem jenseits des naechsten Routinen-Headers
// zaehlt nicht -> Ownership-Transfer-Skip, kein Fund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Alloc;'#13#10 +
  'var p: PByte;'#13#10 +
  'begin'#13#10 +
  '  GetMem(p, 64);'#13#10 +
  '  Stash(p);'#13#10 +
  'end;'#13#10 +
  'procedure DisposeIt(q: Pointer);'#13#10 +
  'begin'#13#10 +
  '  FreeMem(q);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGetMemWithoutFreeMem),
    'FreeMem in der Nachbar-Routine ist kein lokales Pairing -> kein Fund');
  finally F.Free; end;
end;

procedure TTestGetMemWithoutFreeMem.FreeMemFarApartSameRoutine_NoFinding;
// Doku-Quickwins 2026-07-25: GetMem und FreeMem liegen in DERSELBEN Routine,
// aber weiter als das Lookahead-Fenster (400 Zeichen) auseinander -> das
// FreeMem wird nicht gesehen, der Detektor faellt bewusst in den
// Ownership-Transfer-Skip (lieber False-Negative als 87 % FP-Quote).
var
  SRC: string;
  i  : Integer;
  F  : TObjectList<TLeakFinding>;
begin
  SRC := 'unit t; implementation'#13#10 +
         'procedure Foo;'#13#10 +
         'var p: PByte;'#13#10 +
         'begin'#13#10 +
         '  GetMem(p, 1024);'#13#10;
  for i := 1 to 40 do                       // > 400 Zeichen Fuellcode
    SRC := SRC + '  DoStuff(p, ' + IntToStr(i) + ');'#13#10;
  SRC := SRC + '  FreeMem(p);'#13#10'end;';
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGetMemWithoutFreeMem),
    'FreeMem ausserhalb des Fensters -> Skip, kein Fund');
  finally F.Free; end;
end;

procedure TTestGetMemWithoutFreeMem.PairedNoTryBeforeNextRoutine_StillReported;
// TP-Gegenprobe zum Routinen-Grenzen-Clamp: GetMem+FreeMem OHNE try/finally
// in derselben Routine, DIREKT gefolgt von einer weiteren Routine - der
// Clamp darf das FreeMem VOR der Grenze nicht wegschneiden, der echte
// Leak-Treffer muss bleiben.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var p: PByte;'#13#10 +
  'begin'#13#10 +
  '  GetMem(p, 1024);'#13#10 +
  '  DoStuff(p);'#13#10 +
  '  FreeMem(p);'#13#10 +
  'end;'#13#10 +
  'procedure Bar;'#13#10 +
  'begin'#13#10 +
  '  Beep;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkGetMemWithoutFreeMem),
      'FreeMem vor der Routinen-Grenze bleibt ein echter Treffer');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'GetMem(p, 1024'),
      TFindingHelper.FirstOf(F, fkGetMemWithoutFreeMem).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestGetMemWithoutFreeMem);

end.
