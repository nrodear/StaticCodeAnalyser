unit uTestLoopPastHighBound;

// Tests fuer TLoopPastHighBoundDetector (Charge A3 / Q2, 2026-10-23):
// for-Schleife einen Index zu weit ('0 to List.Count' mit 'List[i]').
//
// Der Detektor liest die Code-Sicht der Datei (Strip-Cache) - die Tests
// laufen ueber FindingsOfFile (dort registriert).
//
// Jede Negativprobe steht mit einer POSITIVEN Wache in derselben Quelle
// (Zeile mit '// HIT'): der Test verlangt genau einen Fund auf dieser
// Zeile. Ohne den Detektor ist er damit rot (0 Funde), mit einem zu
// weiten Detektor ebenfalls (2 Funde).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestLoopPastHighBound = class
  public
    // ---- Bewiesen -> Error ------------------------------------------------
    [Test] procedure Count_StringList_Error;
    [Test] procedure Count_ObjectsMember_Error;
    [Test] procedure Length_DynArray_Error;
    [Test] procedure Length_String_ErrorWithStringAdvice;
    [Test] procedure HighPlusOne_Array_Error;
    [Test] procedure StringPlusOne_String_Error;
    [Test] procedure CountFromOne_ProvenList_Error;
    // ---- Ohne Beweis oder mit Ausstieg -> Warning --------------------------
    [Test] procedure Count_PropertyChain_Warning;
    [Test] procedure ConditionalBreakBeforeAccess_Warning;
    [Test] procedure CollectionGrows_Warning;
    // ---- Nicht melden (je mit Wache) --------------------------------------
    [Test] procedure CountMinusOne_NotReported;
    [Test] procedure ShiftedIndex_NotReported;
    [Test] procedure InsertPositionOnly_NotReported;
    [Test] procedure OtherCollection_NotReported;
    [Test] procedure StringOneToLength_NotReported;
    [Test] procedure GuardOnIndex_NotReported;
    [Test] procedure ShortString_NotReported;
    [Test] procedure DowntoCommentString_NotReported;
    [Test] procedure CountFromOne_Unproven_NotReported;
    // ---- Meldung -----------------------------------------------------------
    [Test] procedure Message_NamesHeadAccessAndBound;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

const
  CRLF = #13#10;

// Eine Unit mit der Routine Foo: ADecls sind die var-Zeilen, ABody der
// Rumpf (je Zeile mit CRLF).
function Wrap(const ADecls, ABody: string): string;
begin
  Result := 'unit t;' + CRLF + 'interface' + CRLF + 'implementation' + CRLF +
    'uses System.Classes;' + CRLF +
    'procedure Foo(Memo1: TObject);' + CRLF + 'var' + CRLF + ADecls +
    'begin' + CRLF + ABody + 'end;' + CRLF + 'end.';
end;

// Genau ein Fund, auf der Zeile mit '// HIT', mit der Schwere ASev.
procedure AssertOneHit(const ASrc: string; ASev: TLeakSeverity;
  const AWhy: string);
var
  F   : TObjectList<TLeakFinding>;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(ASrc);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkLoopPastHighBound), AWhy);
    Hit := TFindingHelper.FirstOf(F, fkLoopPastHighBound);
    Assert.AreEqual(TFindingHelper.LineOf(ASrc, '// HIT'), Hit.LineNumber,
      'Fundzeile ist die Zeile des for: ' + AWhy);
    Assert.AreEqual<Integer>(Ord(ASev), Ord(Hit.Severity),
      'Schwere: ' + AWhy);
  finally
    F.Free;
  end;
end;

{ ---- Bewiesen -> Error ---- }

procedure TTestLoopPastHighBound.Count_StringList_Error;
begin
  AssertOneHit(Wrap('  L: TStringList;' + CRLF + '  i: Integer;' + CRLF +
    '  S: string;' + CRLF,
    '  for i := 0 to L.Count do // HIT' + CRLF +
    '    S := S + L[i];' + CRLF), lsError,
    'TStringList aus der Deklaration, L[Count] liegt hinter dem Ende');
end;

procedure TTestLoopPastHighBound.Count_ObjectsMember_Error;
begin
  AssertOneHit(Wrap('  L: TStrings;' + CRLF + '  i: Integer;' + CRLF,
    '  for i := 0 to L.Count do // HIT' + CRLF +
    '  begin' + CRLF +
    '    L.Objects[i].Free;' + CRLF +
    '  end;' + CRLF), lsError,
    'L.Objects[i] ist derselbe Zugriff wie L[i]');
end;

procedure TTestLoopPastHighBound.Length_DynArray_Error;
begin
  AssertOneHit(Wrap('  A: array of Integer;' + CRLF + '  i: Integer;' + CRLF,
    '  for i := 0 to Length(A) do // HIT' + CRLF +
    '    A[i] := 0;' + CRLF), lsError,
    'A[Length(A)] liegt hinter dem Ende, auch als Schreibziel');
end;

procedure TTestLoopPastHighBound.Length_String_ErrorWithStringAdvice;
const
  WANT = 'strings start at 1; the loop should run 1 to Length(S)';
var
  Src : string;
  F   : TObjectList<TLeakFinding>;
begin
  Src := Wrap('  S: string;' + CRLF + '  i, n: Integer;' + CRLF,
    '  for i := 0 to Length(S) do // HIT' + CRLF +
    '    if S[i] = ''x'' then Inc(n);' + CRLF);
  AssertOneHit(Src, lsError, 'S[0] liegt vor dem ersten Zeichen');
  F := TFindingHelper.FindingsOfFile(Src);
  try
    Assert.IsTrue(Pos(WANT, TFindingHelper.FirstOf(F,
      fkLoopPastHighBound).MissingVar) > 0,
      'der Rat nennt die 1-basierte Form');
  finally
    F.Free;
  end;
end;

procedure TTestLoopPastHighBound.HighPlusOne_Array_Error;
begin
  AssertOneHit(Wrap('  A: TBytes;' + CRLF + '  i, Sum: Integer;' + CRLF,
    '  for i := Low(A) to High(A) + 1 do // HIT' + CRLF +
    '    Sum := Sum + A[i] * 2;' + CRLF), lsError,
    'High(A) + 1 ist der Index hinter dem letzten Element');
end;

procedure TTestLoopPastHighBound.StringPlusOne_String_Error;
begin
  AssertOneHit(Wrap('  S: string;' + CRLF + '  i: Integer;' + CRLF +
    '  C: Char;' + CRLF,
    '  for i := 1 to Length(S) + 1 do // HIT' + CRLF +
    '    C := S[i];' + CRLF), lsError,
    'S[Length(S) + 1] liegt hinter dem letzten Zeichen');
end;

procedure TTestLoopPastHighBound.CountFromOne_ProvenList_Error;
begin
  AssertOneHit(Wrap('  L: TList;' + CRLF + '  i: Integer;' + CRLF,
    '  for i := 1 to L.Count do // HIT' + CRLF +
    '    TObject(L[i]).Free;' + CRLF), lsError,
    'eine TList beginnt bei 0 - L[Count] liegt hinter dem Ende');
end;

{ ---- Ohne Beweis oder mit Ausstieg -> Warning ---- }

procedure TTestLoopPastHighBound.Count_PropertyChain_Warning;
begin
  AssertOneHit(Wrap('  i: Integer;' + CRLF + '  S: string;' + CRLF,
    '  for i := 0 to TMemo(Memo1).Lines.Count do' + CRLF +
    '    ;' + CRLF +
    '  for i := 0 to Lines.Count do // HIT' + CRLF +
    '    S := Lines.Strings[i];' + CRLF), lsWarning,
    'Lines ist eine Property unbekannten Typs - Warning, nicht Error; '
    + 'die erste Schleife hat keinen Zugriff');
end;

procedure TTestLoopPastHighBound.ConditionalBreakBeforeAccess_Warning;
begin
  AssertOneHit(Wrap('  L: TStringList;' + CRLF + '  i: Integer;' + CRLF +
    '  Stop: Boolean;' + CRLF + '  S: string;' + CRLF,
    '  for i := 0 to L.Count do // HIT' + CRLF +
    '  begin' + CRLF +
    '    if Stop then Break;' + CRLF +
    '    S := L[i];' + CRLF +
    '  end;' + CRLF), lsWarning,
    'ein bedingter Ausstieg vor dem Zugriff ist nicht bewiesen');
end;

procedure TTestLoopPastHighBound.CollectionGrows_Warning;
begin
  AssertOneHit(Wrap('  L: TStringList;' + CRLF + '  i: Integer;' + CRLF +
    '  S: string;' + CRLF,
    '  for i := 0 to L.Count do // HIT' + CRLF +
    '  begin' + CRLF +
    '    L.Add(''x'');' + CRLF +
    '    S := L[i];' + CRLF +
    '  end;' + CRLF), lsWarning,
    'die Liste waechst im Rumpf - L[Count] kann dann gueltig sein');
end;

{ ---- Nicht melden (je mit Wache) ---- }

// Die Wache: eine bewiesene Schleife, die immer meldet.
function Guard: string;
begin
  Result := '  for g := 0 to G0.Count do // HIT' + CRLF +
    '    G0[g].Free;' + CRLF;
end;

function GuardDecl: string;
begin
  Result := '  G0: TObjectList;' + CRLF + '  g: Integer;' + CRLF;
end;

procedure TTestLoopPastHighBound.CountMinusOne_NotReported;
begin
  AssertOneHit(Wrap(GuardDecl + '  L: TStringList;' + CRLF + '  i: Integer;'
    + CRLF + '  S: string;' + CRLF,
    '  for i := 0 to L.Count - 1 do' + CRLF + '    S := L[i];' + CRLF +
    '  for i := 0 to Pred(L.Count) do' + CRLF + '    S := L[i];' + CRLF +
    Guard), lsError, 'Count - 1 und Pred(Count) sind richtig');
end;

procedure TTestLoopPastHighBound.ShiftedIndex_NotReported;
begin
  AssertOneHit(Wrap(GuardDecl + '  L: TStringList;' + CRLF + '  i: Integer;'
    + CRLF + '  S: string;' + CRLF,
    '  for i := 1 to L.Count do' + CRLF + '    S := L[i - 1];' + CRLF +
    '  for i := 0 to L.Count do' + CRLF + '    S := L[(i)] + L[i+1];' + CRLF +
    Guard), lsError, 'verschobener Index ist kein Zugriff auf L[i]');
end;

procedure TTestLoopPastHighBound.InsertPositionOnly_NotReported;
begin
  AssertOneHit(Wrap(GuardDecl + '  L: TStringList;' + CRLF + '  i: Integer;'
    + CRLF, '  for i := 0 to L.Count do' + CRLF +
    '    L.Insert(i, ''x'');' + CRLF + Guard), lsError,
    'Insert(i, ..) ist bis Count gueltig');
end;

procedure TTestLoopPastHighBound.OtherCollection_NotReported;
begin
  AssertOneHit(Wrap(GuardDecl + '  L, M: TStringList;' + CRLF +
    '  i: Integer;' + CRLF + '  S: string;' + CRLF,
    '  for i := 0 to L.Count do' + CRLF + '    S := M[i];' + CRLF +
    '  for i := 0 to L.Count do' + CRLF + '    S := X.L[i];' + CRLF +
    Guard), lsError,
    'M ist eine andere Sammlung, X.L gehoert zu einem anderen Objekt');
end;

procedure TTestLoopPastHighBound.StringOneToLength_NotReported;
begin
  AssertOneHit(Wrap(GuardDecl + '  S: string;' + CRLF + '  i: Integer;' +
    CRLF + '  C: Char;' + CRLF,
    '  for i := 1 to Length(S) do' + CRLF + '    C := S[i];' + CRLF +
    '  for i := Low(S) to Length(S) do' + CRLF + '    C := S[i];' + CRLF +
    Guard), lsError, 'Strings laufen von 1 bis Length(S)');
end;

procedure TTestLoopPastHighBound.GuardOnIndex_NotReported;
begin
  AssertOneHit(Wrap(GuardDecl + '  A: array of Integer;' + CRLF +
    '  i, x: Integer;' + CRLF,
    '  for i := 0 to Length(A) do' + CRLF +
    '    if i < Length(A) then x := A[i] else x := 0;' + CRLF +
    '  for i := 0 to Length(A) do' + CRLF +
    '    if i = Length(A) then x := 0 else x := A[i];' + CRLF +
    Guard), lsError, 'ein Waechter auf i macht den Schritt zu weit gewollt');
end;

procedure TTestLoopPastHighBound.ShortString_NotReported;
begin
  AssertOneHit(Wrap(GuardDecl + '  S: string[20];' + CRLF + '  i: Integer;' +
    CRLF + '  C: AnsiChar;' + CRLF,
    '  for i := 0 to Length(S) do' + CRLF + '    C := S[i];' + CRLF +
    Guard), lsError,
    'ShortString: S[0] ist das Laengenbyte, S[Length] das letzte Zeichen');
end;

procedure TTestLoopPastHighBound.DowntoCommentString_NotReported;
begin
  AssertOneHit(Wrap(GuardDecl + '  L: TStringList;' + CRLF + '  i: Integer;'
    + CRLF + '  S: string;' + CRLF,
    '  for i := L.Count downto 0 do' + CRLF + '    S := L[i];' + CRLF +
    '  // for i := 0 to L.Count do S := L[i];' + CRLF +
    '  { for i := 0 to L.Count do S := L[i]; }' + CRLF +
    '  S := ''for i := 0 to L.Count do S := L[i];'';' + CRLF +
    Guard), lsError, 'downto, Kommentare und Strings melden nichts');
end;

procedure TTestLoopPastHighBound.CountFromOne_Unproven_NotReported;
begin
  AssertOneHit(Wrap(GuardDecl + '  i: Integer;' + CRLF + '  V: Variant;' +
    CRLF, '  for i := 1 to Sheets.Count do' + CRLF +
    '    V := Sheets[i];' + CRLF + Guard), lsError,
    'ohne Typbeweis kann die Sammlung 1-basiert sein (COM)');
end;

{ ---- Meldung ---- }

procedure TTestLoopPastHighBound.Message_NamesHeadAccessAndBound;
const
  WANT = 'Loop past the last index: i := 0 to L.Count with L.Strings[i] - '
    + 'the last pass is out of range; the bound should be L.Count - 1';
var
  Src : string;
  F   : TObjectList<TLeakFinding>;
begin
  Src := Wrap('  L: TStringList;' + CRLF + '  i: Integer;' + CRLF +
    '  S: string;' + CRLF,
    '  for i := 0 to L.Count do // HIT' + CRLF +
    '    S := L.Strings[i];' + CRLF);
  F := TFindingHelper.FindingsOfFile(Src);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkLoopPastHighBound),
      'ein Fund');
    Assert.AreEqual(WANT, TFindingHelper.FirstOf(F,
      fkLoopPastHighBound).MissingVar,
      'Kopf und Zugriff stehen woertlich in der Meldung (der Planer liest sie)');
  finally
    F.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLoopPastHighBound);

end.
