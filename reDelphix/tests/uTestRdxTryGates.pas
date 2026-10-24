unit uTestRdxTryGates;

// Quick-Fixes try/finally (uRdxTryFixes) - die Sperren und Formen aus dem
// Gegen-Review der Charge H4 (Charge H4c), je Befund die Pruefer-Fixture
// (scratchpad w4/rc/cases*.txt) als Test; ohne Parser, ohne Detektor
// (reDelphix.Test UND FPC-Pruefstand):
//   Blocker 1 - Weitergabe ohne Ausstieg: die sechs schaedlichen Formen
//          abgelehnt (Add, AddObject, Feld := X, Methodenzeiger an ein
//          Ereignis, Add an eine besitzende Liste, Enqueue), die harmlosen
//          angeboten (InsertComponent, with X, X.Parent := ..; dazu
//          AddStrings und ein Funktionsaufruf um X); Ziele einer Zuweisung
//          (lokale Variable, Inline-var, Result, Parameter, Element); '@X',
//          '@X.M' und Typumwandlungen;
//   Major 1 - das SCA009-Suffix sagt nichts ueber den Ort (die Handler-
//          Pruefung bleibt);
//   Minor 1 - raise-Ausdruck ganz, Objekt-Freigaben in anderer Schreibweise;
//   Minor 2 - 'End := 1' als benanntes Argument;
//   Minor 3 - gemischte Einrueckung (Tab und Leerzeichen);
//   Minor 4 - 'SysUtils.FreeAndNil(X)' als B;
//   Minor 6 - 'X := nil; Foo;' hinter B;
//   Minor 7 - die Gruende in der Schreibweise des Quelltexts;
//   Verdacht 13 - Surrogatpaar am Ende der Zeile von A.
// Dazu das Gegen-Review R5 (Charge B1-FE, je gegen 4358b769 rot): X in einer
// Huelle (Cast, Klammern, 'as') bei Zuweisung und Speicher-Aufruf (R5-04),
// 'System.Exit'/'System.Break' (R5-05), nur lokale Puffer und 'P := nil' mit
// ins finally (R5-02), Puffer als Inline-var (R5-10), '%' im Sperrtext der
// Meldung (missed 2); nach der Nachpruefung (gegen d840f1e5 rot) Huellen
// beliebig tief. Dazu die zweite Gegenpruefung der Charge B2S (V2-B2S-1,
// Review R3-05): X hinter einer geschlossenen Klammer-Gruppe im Aufruf
// bzw. im Ziel (UnmatchedOpener mit ParenDelta). Dazu das Wochen-Review
// 2026-10-21 (G08-02): X durch einen generischen Cast 'TList<TFoo>(X)' und
// in einem Array-Konstruktor '[X]' bzw. '[A, X]'.
// Sperren und Puffer: uTestRdxTryLocks; die Form des Bausteins und die
// Sperren der Charge H4: uTestRdxTryFixes.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxTryGates = class
  public
    [Test] procedure HandOver_HarmfulRefused;
    [Test] procedure HandOver_HarmlessOffered;
    [Test] procedure HandOver_AssignTargets;
    [Test] procedure HandOver_PointersAndCasts;
    [Test] procedure Raise_WholeExpression;
    [Test] procedure Release_OtherSpelling;
    [Test] procedure Suffix_HandlerStillChecked;
    [Test] procedure NamedArgument_End;
    [Test] procedure MixedIndent;
    [Test] procedure QualifiedFreeAndNil;
    [Test] procedure NilWithCodeBehind;
    [Test] procedure Reasons_SourceSpelling;
    [Test] procedure Surrogate_AtLineEnd;
    [Test] procedure HandOver_WrappedAssign;
    [Test] procedure SystemQualified_Jumps;
    [Test] procedure Buffer_LocalOnly;
    [Test] procedure Buffer_InlineVar;
    [Test] procedure Lock_PercentInMessage;
    [Test] procedure HandOver_DeepWrap;
    [Test] procedure HandOver_ArgBehindClosedGroup;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxCodeMap, uRdxTryFixes,
  uTestRdxTextKit;   // Join, Apply, InProc, NewMap

const
  SUFFIX = ' (try/except instead of try/finally)';
  MSG_156 = 'GetMem without surrounding try/finally - exception leaks the '
    + 'buffer';
  MSG_ALLOC_156 = 'AllocMem without surrounding try/finally - exception '
    + 'leaks the buffer';
  MSG_109 = 'Lock acquired (%s) but no enclosing try..finally - an exception '
    + 'between Enter and Leave/Release leaves the lock permanently held.';
  MSG_153 = 'Lock/Enter without surrounding try/finally - exception leaks the '
    + 'lock (%s)';

// ---- Helfer (Join und Apply kommen seit Review R6-08, InProc und NewMap
// seit der Review Woche G08-14 aus uTestRdxTextKit, die der Pruefstand
// mitkopiert. PlanOf steht wie in uTestRdxTryFixes hier: sein Kopf nennt
// TRdxTryPlanner aus uRdxTryFixes, und das Kit bindet keine Planer-Unit -
// der Pruefstand uebersetzt es fuer jede Testunit mit) ----

// Ein Surrogatpaar (Emoji), zur Laufzeit gebaut: FPC 3.2 wertet ein
// konstantes '...' + #$D83D#$DE00 als ANSI-Ausdruck aus ('?').
function Emoji: string;
begin
  SetLength(Result, 2);
  Result[1] := Char($D83D);
  Result[2] := Char($DE00);
end;

// Eine Unit mit Routine P und den Deklarationszeilen ADecls (Zeilen 5 ..);
// ALines ist ihr Rumpf hinter 'begin'.
function InProcWith(const AHead: string; const ADecls,
  ALines: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'implementation', AHead])
    + #13#10 + Join(ADecls) + #13#10 + 'begin' + #13#10 + Join(ALines)
    + #13#10 + Join(['end;', 'end.']);
end;

// Der Plan des Planers APlanner fuer Zeile ALine; AReason = '' heisst Hilfe.
function PlanOf(APlanner: TRdxTryPlanner; const ASource: string;
  ALine: Integer; const AMessage: string; out AReason: string): TRdxTryPlan;
var
  Map : TRdxCodeMap;
begin
  Map := NewMap(ASource);
  try
    APlanner(Map, ALine, AMessage, Result, AReason);
  finally
    Map.Free;
  end;
end;

// SCA009 mit AMessage: neuer Text oder '' bei Ablehnung (AReason).
function FixAt(const ASource: string; ALine: Integer; const AMessage: string;
  out AReason: string): string;
var
  P : TRdxTryPlan;
begin
  Result := '';
  P := PlanOf(TRdxTryFixes.MissingFinally, ASource, ALine, AMessage, AReason);
  if AReason = '' then
    Result := Apply(ASource, P.Edit);
end;

// Dasselbe fuer X auf Zeile 6 (die erste des Rumpfs von InProc).
function Fix(const ASource: string; out AReason: string): string;
begin
  Result := FixAt(ASource, 6, 'X', AReason);
end;

// Keine Hilfe fuer X auf Zeile ALine, und APart steht im Grund.
procedure AssertRefusedAt(const ASource: string; ALine: Integer;
  const APart: string);
var
  R : string;
begin
  Assert.AreEqual('', FixAt(ASource, ALine, 'X', R), 'keine Hilfe: ' + APart);
  Assert.IsTrue(Pos(APart, R) > 0, R);
end;

procedure AssertRefused(const ASource, APart: string);
begin
  AssertRefusedAt(ASource, 6, APart);
end;

// Eine Hilfe fuer X auf Zeile 6 (der Text pruefen andere Tests).
procedure AssertOffered(const ASource: string);
var
  R : string;
begin
  Assert.AreNotEqual('', Fix(ASource, R), R);
end;

// SCA156 auf Zeile ALine mit der Meldung AMessage: neuer Text oder '' bei
// Ablehnung (AReason).
function BufFixAt(const ASource: string; ALine: Integer;
  const AMessage: string; out AReason: string): string;
var
  P : TRdxTryPlan;
begin
  Result := '';
  P := PlanOf(TRdxTryFixes.GetMemWithoutFree, ASource, ALine, AMessage,
    AReason);
  if AReason = '' then
    Result := Apply(ASource, P.Edit);
end;

// Keine SCA156-Hilfe auf Zeile ALine, und APart steht im Grund.
procedure AssertBufRefused(const ASource: string; ALine: Integer;
  const AMessage, APart: string);
var
  R : string;
begin
  Assert.AreEqual('', BufFixAt(ASource, ALine, AMessage, R),
    'keine Hilfe: ' + APart);
  Assert.IsTrue(Pos(APart, R) > 0, R);
end;

// A, dann AMid und X.Free - die Form der Pruefer-Fixtures.
function Around(const AMid: array of string): string;
var
  L : TArray<string>;
  i : Integer;
begin
  SetLength(L, Length(AMid) + 2);
  L[0] := '  X := TFoo.Create;';
  for i := 0 to High(AMid) do
    L[i + 1] := '  ' + AMid[i];
  L[High(L)] := '  X.Free;';
  Result := InProc(L);
end;

// ---- Blocker 1: Weitergabe ohne Ausstieg ----

// Die sechs schaedlichen Formen aus rc/cases1.txt: im Fehlerfall gaebe
// finally X frei, waehrend der Halter es noch kennt (bis Charge H4c alle
// angeboten - aus einem Leck wurde ein Use-after-free).
procedure TTestRdxTryGates.HandOver_HarmfulRefused;
begin
  AssertRefused(Around(['List.Add(X);', 'DoWork;', 'List.Remove(X);']),
    'X wird in Zeile 7 an Add weitergegeben');
  // doublecmd ftpfunc.pas:434 - X als zweites Argument.
  AssertRefused(Around(['Index := ConnectionList.AddObject(X.Name, X);',
    'FtpConnect(X.Name);', 'ConnectionList.Delete(Index);']),
    'an AddObject weitergegeben');
  AssertRefused(Around(['FCurrent := X;', 'DoWork;', 'FCurrent := nil;']),
    'an FCurrent weitergegeben (kein lokaler Name');
  AssertRefused(Around(['Btn.OnClick := X.Handler;', 'DoWork;',
    'Btn.OnClick := nil;']), 'Methodenzeiger X.Handler an OnClick');
  AssertRefused(Around(['FOwnedList.Add(X);', 'DoWork;',
    'FOwnedList.Extract(X);']), 'an Add weitergegeben');
  AssertRefused(Around(['FQueue.Enqueue(X);', 'DoWork;', 'FQueue.Dequeue;']),
    'an Enqueue weitergegeben');
  // Das Ereignis als Feld 'FOn..' (EVENT_FIELD).
  AssertRefused(Around(['FOnClick := X.Handler;', 'DoWork;',
    'FOnClick := nil;']), 'Methodenzeiger X.Handler an FOnClick');
end;

// Die harmlosen Formen bleiben angeboten: InsertComponent (der Destruktor
// meldet sich beim Owner ab), with X, ein Member-Zugriff; AddStrings kopiert
// nur den Inhalt, ein Funktionsaufruf um X ('AttToHtml(X)', Korpus
// JvRichEditToHtml) gibt nur sein Ergebnis weiter.
procedure TTestRdxTryGates.HandOver_HarmlessOffered;
var
  R : string;
begin
  AssertOffered(Around(['Owner.InsertComponent(X);', 'DoWork;',
    'Owner.RemoveComponent(X);']));
  Assert.AreEqual(InProc(['  X := TFoo.Create;', '  try', '    with X do',
    '    begin', '      Run;', '    end;', '  finally', '    X.Free;',
    '  end;']), Fix(Around(['with X do', 'begin', '  Run;', 'end;']), R), R);
  AssertOffered(Around(['X.Parent := Self;', 'DoWork;']));
  AssertOffered(Around(['Lines.AddStrings(X);', 'DoWork;']));
  AssertOffered(Around(['Strings.Add(AttToHtml(X));', 'DoWork;']));
end;

// X als ganze rechte Seite: an eine lokale Variable (var-Abschnitt,
// Inline-var) angeboten; an Result, einen Parameter, ein Element oder einen
// Namen ohne Deklaration (Feld, globale Variable) abgelehnt.
procedure TTestRdxTryGates.HandOver_AssignTargets;
var
  R : string;
begin
  Assert.AreEqual(InProcWith('procedure P;', ['var', '  Y: TFoo;'],
    ['  X := TFoo.Create;', '  try', '    Y := X;', '    Y.Run;', '  finally',
    '    X.Free;', '  end;']),
    FixAt(InProcWith('procedure P;', ['var', '  Y: TFoo;'],
      ['  X := TFoo.Create;', '  Y := X;', '  Y.Run;', '  X.Free;']), 8, 'X',
      R), R);
  AssertOffered(Around(['begin', '  var Y := X;', '  Y.Run;', 'end;']));
  AssertRefused(Around(['Result := X;', 'DoWork;']),
    'an Result weitergegeben');
  AssertRefusedAt(InProcWith('procedure P(var AOut: TFoo);', ['var',
    '  Y: TFoo;'], ['  X := TFoo.Create;', '  AOut := X;', '  X.Free;']), 8,
    'an AOut weitergegeben');
  AssertRefused(Around(['Items[I] := X;', 'DoWork;']),
    'an Items[I] weitergegeben');
  AssertRefused(Around(['Cropper.InStream := X;', 'Cropper.Parse;']),
    'an Cropper.InStream weitergegeben');
  // Ein Property-Lesen 'Y := X.Count' ist keine Weitergabe.
  AssertOffered(Around(['FCount := X.Count;', 'DoWork;']));
  // Lokale Routinen im Deklarationsteil (VarInSections/SkipLocalRoutine):
  // ein var-Abschnitt dahinter zaehlt, die Variablen der lokalen Routine
  // nicht.
  Assert.AreNotEqual('', FixAt(InProcWith('procedure P;', ['var',
    '  A: Integer;', '  procedure Inner;', '  begin', '  end;', 'var',
    '  Y: TFoo;'], ['  X := TFoo.Create;', '  Y := X;', '  Y.Run;',
    '  X.Free;']), 13, 'X', R), R);
  AssertRefusedAt(InProcWith('procedure P;', ['  procedure Inner;', '  var',
    '    Y: TFoo;', '  begin', '  end;'], ['  X := TFoo.Create;', '  Y := X;',
    '  Y.Run;', '  X.Free;']), 11, 'an Y weitergegeben (kein lokaler Name');
end;

// '@X' und '@X.M' (FPC-Methodenzeiger; doublecmd udarwinapplication.pas:218)
// sowie X durch eine Typumwandlung hindurch.
procedure TTestRdxTryGates.HandOver_PointersAndCasts;
begin
  AssertRefused(Around(['Hook(@X);', 'DoWork;']), '@X in Zeile 7');
  AssertRefused(Around(['OnMenuPopupHandler := @X.Attach;', 'Menu.PopUp;']),
    '@X in Zeile 7');
  AssertRefused(Around(['List.Add(TObject(X));', 'DoWork;']),
    'an Add weitergegeben');
  AssertRefused(Around(['List.Add(Pointer(X));', 'DoWork;']),
    'an Add weitergegeben');
  // 'as' und Klammern im Argument (Gegen-Review R5, R5-04; bis Charge B1-FE
  // angeboten).
  AssertRefused(Around(['List.Add(X as TObject);', 'DoWork;']),
    'an Add weitergegeben');
  AssertRefused(Around(['List.Add((X));', 'DoWork;']), 'an Add weitergegeben');
  AssertRefused(Around(['List.Add(TObject((X as TFoo)));', 'DoWork;']),
    'an Add weitergegeben');
  // Generischer Cast und Array-Konstruktor (Review Woche G08-02; bis dahin
  // angeboten): vor '(' steht das '>' von 'TList<TFoo>', vor X ein '[' -
  // die Sperre sah keine Zuweisung bzw. keinen Aufruf, nach dem Fix gaebe
  // finally X frei, waehrend FItems bzw. FList es noch kennt.
  AssertRefused(Around(['FItems := TList<TFoo>(X);', 'DoWork;',
    'FItems := nil;']), 'X wird in Zeile 7 an FItems weitergegeben (kein '
    + 'lokaler Name');
  AssertRefused(Around(['FList.AddRange([X]);', 'DoWork;', 'FList.Remove(X);']),
    'X wird in Zeile 7 an AddRange weitergegeben');
  AssertRefused(Around(['FList.AddRange([Y, X]);', 'DoWork;']),
    'an AddRange weitergegeben');
  AssertRefused(Around(['FArr := [X];', 'DoWork;']), 'an FArr weitergegeben');
  AssertRefused(Around(['Reg.Register<TFoo>(X);', 'DoWork;']),
    'an Register weitergegeben');
  // Ein Member durch den generischen Cast und X als Index bleiben
  // angeboten.
  AssertOffered(Around(['Log(TList<TFoo>(X).Count);', 'DoWork;']));
  AssertOffered(Around(['List.Add(Items[X]);', 'DoWork;']));
end;

// ---- Minor 1: raise-Ausdruck und Freigaben in anderer Schreibweise ----

// X ist (Teil) der Ausnahme, wo immer es im raise-Ausdruck steht - bis
// Charge H4c sah der Planer nur das Token hinter raise.
procedure TTestRdxTryGates.Raise_WholeExpression;
begin
  AssertRefused(Around(['if C then', '  raise TObject(X);']),
    'raise TObject(X) in Zeile 8');
  AssertRefused(Around(['if C then', '  raise X at ReturnAddress;']),
    'raise X at ReturnAddress');
  // 'uebergeben' traegt in der de.po einen echten Umlaut (Charge G3) -
  // geprueft werden der Aufruf und das umlautfreie Ende.
  AssertRefused(Around(['if C then', '  Exception.RaiseOuterException(X);']),
    'an RaiseOuterException');
  AssertRefused(Around(['if C then', '  Exception.RaiseOuterException(X);']),
    'das Objekt ist die Ausnahme');
  // Ein Member von X im Ausdruck ist keine Weitergabe.
  AssertOffered(Around(['if C then', '  raise EFoo.Create(X.Name);']));
end;

// Eine fruehe Freigabe anders geschrieben als B - nach dem Fix liefe
// finally ein zweites Mal (bis Charge H4c angeboten).
procedure TTestRdxTryGates.Release_OtherSpelling;
begin
  AssertRefused(Around(['if Bad then', 'begin', '  TObject(X).Free;',
    '  raise EFoo.Create(''x'');', 'end;']), 'in anderer Schreibweise');
  AssertRefused(Around(['if Bad then', 'begin', '  Self.X.Free;',
    '  raise EFoo.Create(''x'');', 'end;']), 'in anderer Schreibweise');
  AssertRefused(Around(['if Bad then', 'begin', '  FreeAndNil(Self.X);',
    '  raise EFoo.Create(''x'');', 'end;']), 'in anderer Schreibweise');
  // Durch einen generischen Cast (Review Woche G08-02; bis dahin angeboten).
  AssertRefused(Around(['if Bad then', 'begin', '  TList<TFoo>(X).Free;',
    '  raise EFoo.Create(''x'');', 'end;']), 'in anderer Schreibweise');
end;

// ---- Major 1: das Suffix ----

// Das Suffix sperrt nicht mehr - ein Handler, der X nennt, aber schon
// (nach dem Fix liefe er hinter dem finally).
procedure TTestRdxTryGates.Suffix_HandlerStillChecked;
var
  R : string;
begin
  AssertRefusedAt(InProc(['  try', '    X := TFoo.Create;', '    X.Run;',
    '    X.Free;', '  except', '    X.Free;', '    raise;', '  end;']), 7,
    'except-Teil');
  Assert.AreEqual('', FixAt(InProc(['  try', '    X := TFoo.Create;',
    '    X.Run;', '    X.Free;', '  except', '    Log(X.Name);', '  end;']), 7,
    'X' + SUFFIX, R), 'auch mit Suffix');
  Assert.IsTrue(Pos('except-Teil', R) > 0, R);
end;

// ---- Minor 2..7, Verdacht 13 ----

// 'End := 1' ist ein benanntes OLE-Argument, kein end (rc/cases7.txt): bis
// Charge H4c senkte es die Blocktiefe - das bedingte Free wurde B, das
// Ergebnis uebersetzte nicht; hinter einem Block fand der Planer B nicht.
procedure TTestRdxTryGates.NamedArgument_End;
var
  R : string;
begin
  AssertRefused(Around(['if C then', 'begin',
    '  R := Doc.Range(Start := 0, End := 1);', '  Bar;', '  X.Free;', 'end;']),
    'tiefer liegende');
  Assert.AreEqual(InProc(['  X := TFoo.Create;', '  try', '    begin',
    '      R := Doc.Range(Start := 0, End := 1);', '      Bar;', '    end;',
    '    X.Run;', '  finally', '    X.Free;', '  end;']),
    Fix(Around(['begin', '  R := Doc.Range(Start := 0, End := 1);', '  Bar;',
      'end;', 'X.Run;']), R), R);
end;

// Die Stufe kommt hinter den Leerraum, den die Zeile mit A teilt
// (rc/cases4.txt): bis Charge H4c wurde '<Tab>  X.Run' zu
// '  <Tab>  X.Run'.
procedure TTestRdxTryGates.MixedIndent;
var
  R : string;
begin
  Assert.AreEqual(Join(['unit u;', 'interface', 'implementation',
    'procedure P;', #9'begin', #9'  X := TFoo.Create;', #9'  try',
    #9'    X.Run;', #9'  finally', #9'    X.Free;', #9'  end;', #9'end;',
    'end.']),
    Fix(Join(['unit u;', 'interface', 'implementation', 'procedure P;',
      #9'begin', #9'  X := TFoo.Create;', #9'  X.Run;', #9'  X.Free;',
      #9'end;', 'end.']), R), R);
end;

// 'SysUtils.FreeAndNil(X)' als B (rc/cases4.txt): bis Charge H4c "zweite
// Freigabe" - die Pruefung sah die Freigabe erst am Wort hinter dem Punkt.
procedure TTestRdxTryGates.QualifiedFreeAndNil;
var
  R : string;
begin
  Assert.AreEqual(InProc(['  X := TFoo.Create;', '  try', '    X.Run;',
    '  finally', '    SysUtils.FreeAndNil(X);', '  end;']),
    Fix(InProc(['  X := TFoo.Create;', '  X.Run;',
      '  SysUtils.FreeAndNil(X);']), R), R);
  // Frueh und bedingt bleibt es die zweite Freigabe.
  AssertRefused(InProc(['  X := TFoo.Create;', '  if C then',
    '    SysUtils.FreeAndNil(X);', '  X.Run;', '  X.Free;']), 'zweite');
end;

// 'X := nil; Foo;' hinter B: das nil bleibt stehen (bis Charge H4c verwarf
// das die ganze Hilfe); auf der Zeile von B geht es wie bisher mit.
procedure TTestRdxTryGates.NilWithCodeBehind;
var
  R : string;
begin
  Assert.AreEqual(InProc(['  X := TFoo.Create;', '  try', '    X.Run;',
    '  finally', '    X.Free;', '  end;', '  X := nil; Foo;']),
    Fix(InProc(['  X := TFoo.Create;', '  X.Run;', '  X.Free;',
      '  X := nil; Foo;']), R), R);
  Assert.AreEqual(InProc(['  X := TFoo.Create;', '  try', '    X.Run;',
    '  finally', '    X.Free; X := nil;', '  end;']),
    Fix(InProc(['  X := TFoo.Create;', '  X.Run;', '  X.Free; X := nil;']),
      R), R);
end;

// Die Gruende nennen den Namen wie im Quelltext, nicht klein (bis Charge
// H4c 'obj wird weitergegeben', 'Inc(p)').
procedure TTestRdxTryGates.Reasons_SourceSpelling;
var
  R : string;
  P : TRdxTryPlan;
begin
  PlanOf(TRdxTryFixes.MissingFinally, InProc(['  Obj := TFoo.Create;',
    '  if Keep(Obj) then', '    Exit;', '  Obj.Free;']), 6, 'Obj', R);
  Assert.IsTrue(Pos('und Obj wird in Zeile 7 weitergegeben', R) > 0, R);
  P := PlanOf(TRdxTryFixes.GetMemWithoutFree, InProc(['  GetMem(Buf, N);',
    '  Inc(Buf);', '  FreeMem(Buf);']), 6, MSG_156, R);
  Assert.IsTrue(Pos('Inc(Buf) in Zeile 7', R) > 0, R);
  Assert.AreEqual('Buf', P.Name);
end;

// Ein Emoji am Ende der Zeile von A (Kommentar): der Bereich beginnt auf
// dem ganzen Zeichen - bis Charge H4c auf seiner zweiten UTF-16-Haelfte,
// mitten im Zeichen (PlanByteEdits lehnte ab: keine Hilfe).
procedure CheckSurrogate;
var
  Src, R : string;
  P      : TRdxTryPlan;
begin
  Src := InProc(['  X := TFoo.Create; // ok ' + Emoji, '  X.Run;', '  X.Free;']);
  P := PlanOf(TRdxTryFixes.MissingFinally, Src, 6, 'X', R);
  Assert.AreEqual('', R);
  Assert.AreEqual(Emoji, Copy(P.Edit.Expected, 1, 2), 'Bereich ab dem Zeichen');
  Assert.AreEqual(Emoji + #10'  try', Copy(P.Edit.NewText, 1, 8));
  {$IFNDEF FPC}
  Assert.AreEqual(InProc(['  X := TFoo.Create; // ok ' + Emoji, '  try',
    '    X.Run;', '  finally', '    X.Free;', '  end;']), Apply(Src, P.Edit));
  {$ENDIF}
end;

// FPC 3.2 haelt TStringList und TStringBuilder als ANSI - ein Surrogatpaar
// kaeme als '?' an; mit UTF-8 als Systemcodepage bleibt es heil (wie im
// Korpus-Harness). Delphi braucht das nicht.
procedure TTestRdxTryGates.Surrogate_AtLineEnd;
{$IFDEF FPC}
var
  OldCp : TSystemCodePage;
begin
  OldCp := DefaultSystemCodePage;
  DefaultSystemCodePage := CP_UTF8;
  try
    CheckSurrogate;
  finally
    DefaultSystemCodePage := OldCp;
  end;
end;
{$ELSE}
begin
  CheckSurrogate;
end;
{$ENDIF}

// ---- Gegen-Review R5 (Charge B1-FE) ----

// X in einer Huelle als ganze rechte Seite (R5-04; Pruefer-Fixtures
// w7/rv/R5/t1.txt, R5_verify/v04.txt): Cast, 'as', Klammern - bis Charge B1-FE
// angeboten, im Fehlerfall ein Use-after-free wie bei 'FCurrent := X;'. Ein
// lokales Ziel, ein Member-Zugriff und ein Argument bleiben angeboten.
procedure TTestRdxTryGates.HandOver_WrappedAssign;
var
  R : string;
begin
  AssertRefused(Around(['FCurrent := TFoo(X);', 'DoWork;', 'FCurrent := nil;']),
    'an FCurrent weitergegeben (kein lokaler Name');
  AssertRefused(Around(['FCurrent := X as TFoo;', 'DoWork;']),
    'an FCurrent weitergegeben');
  AssertRefused(Around(['Holder.Obj := TObject(X);', 'DoWork;']),
    'an Holder.Obj weitergegeben');
  AssertRefused(Around(['FCurrent := (X);', 'DoWork;']),
    'an FCurrent weitergegeben');
  AssertRefused(Around(['FObj := Pointer(X);', 'DoWork;']),
    'an FObj weitergegeben');
  AssertRefused(Around(['FObj := System.TObject(X);', 'DoWork;']),
    'an FObj weitergegeben');
  AssertRefused(Around(['Btn.OnClick := TFoo(X).Handler;', 'DoWork;']),
    'Methodenzeiger X.Handler an OnClick');
  Assert.AreEqual(InProcWith('procedure P;', ['var', '  Y: TFoo;'],
    ['  X := TFoo.Create;', '  try', '    Y := TFoo(X);', '    Y.Run;',
    '  finally', '    X.Free;', '  end;']),
    FixAt(InProcWith('procedure P;', ['var', '  Y: TFoo;'],
      ['  X := TFoo.Create;', '  Y := TFoo(X);', '  Y.Run;', '  X.Free;']), 8,
      'X', R), R);
  AssertOffered(Around(['FCount := (X as TFoo).Count;', 'DoWork;']));
  AssertOffered(Around(['Log(TFoo(X).Name);', 'DoWork;']));
end;

// 'System.Exit'/'System.Break' wie Exit/Break (R5-05; Pruefer-Fixtures
// R5/t1.txt, t4.txt, R5_verify/v05.txt): hinter '.' war das Wort kein
// Schluesselwort - bei einer Sperre, einem weitergegebenen Objekt und einer
// Schleife um den Bereich wurde angeboten. Ohne Weitergabe laeuft Free jetzt
// auch beim Ausstieg, wie bei Exit.
procedure TTestRdxTryGates.SystemQualified_Jumps;
var
  R : string;
begin
  PlanOf(TRdxTryFixes.LockWithoutFinally, InProc(['  FLock.Enter;',
    '  if C then System.Exit;', '  DoWork;', '  FLock.Leave;']), 6,
    Format(MSG_109, ['FLock']), R);
  Assert.IsTrue(Pos('Exit in Zeile 7 - mit finally', R) > 0, R);
  AssertRefused(Around(['if Keep(X) then', '  System.Exit;']),
    'Exit in Zeile 8, und X wird in Zeile 7 weitergegeben');
  // 'verlaesst' traegt in der de.po einen echten Umlaut (Charge G3) -
  // geprueft wird das umlautfreie Teilstueck mit Sprung und Zeile.
  AssertRefusedAt(InProc(['  for I := 0 to 9 do', '  begin',
    '    X := TFoo.Create;', '    if Done then', '      System.Break;',
    '    X.Free;', '  end;']), 8, 'break in Zeile 10');
  Assert.AreEqual(InProc(['  X := TFoo.Create;', '  try', '    if X.Empty then',
    '      System.Exit;', '    X.Run;', '  finally', '    X.Free;', '  end;']),
    Fix(Around(['if X.Empty then', '  System.Exit;', 'X.Run;']), R), R);
end;

// Nur ein lokaler Puffer (R5-02; Pruefer-Fixtures R5/t3.txt,
// R5_verify/v02.txt): eine globale Variable, ein Feld oder ein Parameter
// kennt den Puffer weiter - im Fehlerfall gaebe finally ihn frei, das 'P :=
// nil' dahinter liefe nicht, und die finalization bzw. der Destruktor gaebe
// ihn ein zweites Mal frei (bis Charge B1-FE angeboten). Ein direkt folgendes
// 'P := nil;' kommt seitdem mit ins finally.
procedure TTestRdxTryGates.Buffer_LocalOnly;
var
  R : string;
begin
  AssertBufRefused(Join(['unit u;', 'interface', 'implementation', 'var',
    '  Buffer: PByte;', 'procedure Run;', 'begin', '  GetMem(Buffer, 100);',
    '  Fill(Buffer, 100);', '  FreeMem(Buffer);', '  Buffer := nil;', 'end;',
    'end.']), 8, MSG_156, 'Buffer ist keine lokale Variable der Routine');
  AssertBufRefused(Join(['unit u;', 'interface', 'implementation',
    'procedure TCodec.Encode;', 'begin', '  Work := AllocMem(4096);',
    '  DoEncode(Work);', '  FreeMem(Work);', 'end;', 'end.']), 6,
    MSG_ALLOC_156, 'Work ist keine lokale Variable');
  AssertBufRefused(Join(['unit u;', 'interface', 'implementation',
    'procedure Alloc(var P: Pointer);', 'begin', '  GetMem(P, 10);',
    '  Fill(P);', '  FreeMem(P);', 'end;', 'end.']), 6, MSG_156,
    'P ist keine lokale Variable');
  Assert.AreEqual(Join(['unit u;', 'interface', 'implementation',
    'procedure Run;', 'var', '  Buffer: PByte;', 'begin',
    '  GetMem(Buffer, 100);', '  try', '    Fill(Buffer, 100);', '  finally',
    '    FreeMem(Buffer);', '    Buffer := nil;', '  end;', 'end;', 'end.']),
    BufFixAt(Join(['unit u;', 'interface', 'implementation', 'procedure Run;',
      'var', '  Buffer: PByte;', 'begin', '  GetMem(Buffer, 100);',
      '  Fill(Buffer, 100);', '  FreeMem(Buffer);', '  Buffer := nil;', 'end;',
      'end.']), 8, MSG_156, R), R);
end;

// Der Puffer als Inline-var (R5-10; Pruefer-Fixtures R5/t1.txt,
// R5_verify/v10.txt): bis Charge B1-FE nahm der Planer das Token vor ':=' -
// den Typ 'PAnsiChar' - als Puffer und lehnte mit falschem Grund ab
// ('case-Zweig', '"var" davor'). Die Inline-Deklaration ist lokal.
procedure TTestRdxTryGates.Buffer_InlineVar;
var
  R, Src : string;
  P      : TRdxTryPlan;
begin
  Src := InProc(['  var Buf: PAnsiChar := AllocMem(64);', '  Fill(Buf);',
    '  FreeMem(Buf);']);
  P := PlanOf(TRdxTryFixes.GetMemWithoutFree, Src, 6, MSG_ALLOC_156, R);
  Assert.AreEqual('', R);
  Assert.AreEqual('Buf', P.Name, 'der Puffer, nicht sein Typ');
  Assert.AreEqual(InProc(['  var Buf: PAnsiChar := AllocMem(64);', '  try',
    '    Fill(Buf);', '  finally', '    FreeMem(Buf);', '  end;']),
    Apply(Src, P.Edit));
  Assert.AreEqual(InProc(['  var Buf := AllocMem(64);', '  try',
    '    Fill(Buf);', '  finally', '    FreeMem(Buf);', '  end;']),
    BufFixAt(InProc(['  var Buf := AllocMem(64);', '  Fill(Buf);',
      '  FreeMem(Buf);']), 6, MSG_ALLOC_156, R), R);
end;

// '%' im Sperrtext der Meldung (missed 2; Delphi-11-Binaerliteral): zwei
// passende Sperren auf der Zeile - der Grund 'mehrdeutig' setzte bis Charge
// B1 den Text der Meldung in das Format-Muster, und Format warf
// EConvertError. Jetzt geht er als Argument hinein (OneTokenReason).
procedure TTestRdxTryGates.Lock_PercentInMessage;
var
  R : string;
begin
  PlanOf(TRdxTryFixes.UnpairedLock, InProc(['  Locks[%1].Lock; Locks[%1].Lock;',
    '  DoWork;', '  Locks[%1].UnLock;']), 6,
    Format(MSG_153, ['Locks[%1].Lock']), R);
  // 'traegt' im Rahmen von uRdxCodeMap.OneTokenReason bekommt seit der
  // Umstellung E29 (Gruppe G5) in de.po einen echten Umlaut - die Quelle
  // bleibt ASCII: Anfang und Ende ohne das Wort.
  Assert.IsTrue(Pos('Zeile 6 tr', R) > 0, R);
  Assert.IsTrue(Pos(' 2 Sperren "Locks[%1].Lock" - mehrdeutig', R) > 0, R);
end;

// Huellen beliebig tief (Nachpruefung R5-04, Nit; gegen d840f1e5 rot): bis
// dahin las die Weitergabe-Sperre hoechstens vier - mit der fuenften (Cast,
// Klammern, 'as') wurde wieder angeboten.
procedure TTestRdxTryGates.HandOver_DeepWrap;
begin
  AssertRefused(Around(['FCurrent := TFoo(TFoo(TFoo(TFoo(TFoo(X)))));',
    'DoWork;']), 'an FCurrent weitergegeben');
  AssertRefused(Around(['List.Add(TObject((((X as TFoo)))));', 'DoWork;']),
    'an Add weitergegeben');
end;

// X als Argument HINTER einer geschlossenen Gruppe (Korpus pyscripter
// dlgSynPageSetup.pas:486: 'HeadFoot.Add(TrimRight(FRichEdit.Lines[Line]),
// AFont, Align, Line + 1)'): rueckwaerts vom ',' oeffnet ')' bzw. ']' eine
// Gruppe, erst die '(' auf Tiefe 0 ist die des Aufrufs (UnmatchedOpener,
// seit Charge B2S-a mit ParenDelta, Review R3-05). Ebenso der Anfang des
// Ziels 'Items[F(1)] := X' (TargetStart). Zaehlte auch eine schliessende
// Klammer auf Tiefe 0 als Oeffner, boete SCA009 bei Add die Hilfe an, und
// der Grund nennte beim Ziel nur ']' (Gegenpruefung V2-B2S-1: mit dieser
// Mutante rot, auf HEAD und vor Charge B2S-a gruen).
procedure TTestRdxTryGates.HandOver_ArgBehindClosedGroup;
begin
  AssertRefused(Around(['Holder.Add(Foo(1), X);', 'DoWork;']),
    'X wird in Zeile 7 an Add weitergegeben');
  AssertRefused(Around(['HeadFoot.Add(TrimRight(Lines[I]), X, Align);',
    'DoWork;']), 'an Add weitergegeben');
  AssertRefused(Around(['Items[F(1)] := X;', 'DoWork;']),
    'an Items[F(1)] weitergegeben');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxTryGates);

end.
