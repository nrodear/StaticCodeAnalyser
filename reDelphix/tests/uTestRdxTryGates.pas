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
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxBufferMath, uRdxCodeMap, uRdxTryFixes;

const
  SUFFIX = ' (try/except instead of try/finally)';
  MSG_156 = 'GetMem without surrounding try/finally - exception leaks the '
    + 'buffer';

// ---- Helfer (dieselben wie in uTestRdxTryFixes - der Pruefstand baut
// jede Testunit fuer sich) ----

// Ein Surrogatpaar (Emoji), zur Laufzeit gebaut: FPC 3.2 wertet ein
// konstantes '...' + #$D83D#$DE00 als ANSI-Ausdruck aus ('?').
function Emoji: string;
begin
  SetLength(Result, 2);
  Result[1] := Char($D83D);
  Result[2] := Char($DE00);
end;

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
  AssertRefused(Around(['if C then', '  Exception.RaiseOuterException(X);']),
    'an RaiseOuterException uebergeben');
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

initialization
  TDUnitX.RegisterTestFixture(TTestRdxTryGates);

end.
