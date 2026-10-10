unit uTestRdxStructFixes;

// Editorhilfen der Stufe 3 (uRdxStructFixes) auf Text - ohne Parser, ohne
// Detektor (laeuft in reDelphix.Test UND im FPC-Pruefstand):
//   SCA007 einen uses-Eintrag loeschen (erster, mittlerer, letzter,
//          einziger, 'in'-Pfad, Kommentar im Bereich),
//   SCA168 else vor das end des case (leer, mit raise, Einrueckung mit
//          Tabs, verschachtelt, inline, schon ein else, Direktive),
//   SCA101/SCA099 die Anweisung hinter then/else/do in begin..end (eigene
//          Zeilen, Zeile aufteilen, inline, if-else, else von case und
//          except, bedingter Ausdruck, anonyme Methode, Direktive).
// Die Bereiche der uses-Eintraege baut der Test so, wie
// TSourcePlaces.UsesEntries sie liefert (Name, EndCol hinter dem Namen).
// Die Gegenprobe mit dem echten Detektor steht in
// uTestRdxSimpleFixesDetector (nur Delphi).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxStructFixes = class
  public
    // ---- SCA007 ----
    [Test] procedure Sca007_RemoveFirstAndMiddle;
    [Test] procedure Sca007_RemoveLast;
    [Test] procedure Sca007_RemoveOnly;
    [Test] procedure Sca007_InPath;
    [Test] procedure Sca007_Refusals;
    // ---- SCA168 ----
    [Test] procedure Sca168_EmptyElse;
    [Test] procedure Sca168_RaiseElse;
    [Test] procedure Sca168_NestedAndInline;
    [Test] procedure Sca168_Refusals;
    // Gegen-Review 2026-10-10: letzter Arm ohne ';' (sonst bindet das else
    // an ein if), Einrueckung nach den Armen, '&End'.
    [Test] procedure Sca168_LastArmWithoutSemicolon;
    [Test] procedure Sca168_IndentAndEscapedEnd;
    [Test] procedure Sca007_OwnLineAndSkippedEntry;
    // ---- SCA101 / SCA099 ----
    [Test] procedure Sca101_OwnLines;
    [Test] procedure Sca101_SplitLine;
    [Test] procedure Sca101_Inline;
    [Test] procedure Sca101_IfElse;
    [Test] procedure Sca101_ListElse;
    [Test] procedure Sca101_Refusals;
    [Test] procedure Sca099_EndElse;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRefactorInfo, uRdxBufferMath, uRdxCodeMap, uRdxStructFixes;

// ---- Helfer ----

function Apply(const ASource: string; const AEdits: array of TRdxEdit): string;
var
  Bytes : TBytes;
  Edits : TArray<TRdxEdit>;
  Plan  : TArray<TRdxByteEdit>;
  Err   : string;
  i     : Integer;
begin
  SetLength(Edits, Length(AEdits));
  for i := 0 to High(AEdits) do
    Edits[i] := AEdits[i];
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

// Ein uses-Eintrag wie aus TSourcePlaces.UsesEntries.
function Entry(ALine, ACol: Integer; const AName: string): TRefactorSpan;
begin
  Result := TRefactorSpan.Make('unit', ALine, ACol, ALine, ACol + Length(AName));
  Result.Resolved := AName;
end;

function Clause(AUsesLine: Integer;
  const AEntries: array of TRefactorSpan): TRdxUsesClause;
var
  i : Integer;
begin
  Result.UsesLine := AUsesLine;
  SetLength(Result.Entries, Length(AEntries));
  for i := 0 to High(AEntries) do
    Result.Entries[i] := AEntries[i];
end;

// SCA007: neuer Text oder '' bei Ablehnung (AReason).
function FixUses(const ASource: string; const AClause: TRdxUsesClause;
  AIndex: Integer; out AReason: string): string;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  E   : TRdxEdit;
begin
  Result := '';
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    if TRdxStructFixes.RemoveUsesEntry(Map, AClause, AIndex, E, AReason) then
      Result := Apply(ASource, [E]);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// SCA168: neuer Text oder '' bei Ablehnung (AReason); AStatement = ''
// fuer das leere else.
function FixCase(const ASource: string; ALine: Integer;
  const AStatement: string; out AReason: string): string;
var
  SL    : TStringList;
  Map   : TRdxCodeMap;
  Edits : TArray<TRdxEdit>;
begin
  Result := '';
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    if TRdxStructFixes.CaseElse(Map, ALine, AStatement, Edits, AReason) then
      Result := Apply(ASource, Edits);
  finally
    Map.Free;
    SL.Free;
  end;
end;

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

// ---- SCA007 ----

procedure TTestRdxStructFixes.Sca007_RemoveFirstAndMiddle;
var
  R, Src : string;
  C      : TRdxUsesClause;
begin
  Src := Join(['unit u;', 'interface', 'uses', '  A,', '  B,', '  C;',
    'implementation', 'end.']);
  C := Clause(3, [Entry(4, 3, 'A'), Entry(5, 3, 'B'), Entry(6, 3, 'C')]);
  Assert.AreEqual(Join(['unit u;', 'interface', 'uses', '  A,', '  C;',
    'implementation', 'end.']), FixUses(Src, C, 1, R), 'B mittig: ' + R);
  Assert.AreEqual(Join(['unit u;', 'interface', 'uses', '  B,', '  C;',
    'implementation', 'end.']), FixUses(Src, C, 0, R), 'A vorn: ' + R);
  // Auf einer Zeile.
  Src := Join(['unit u;', 'interface', 'uses A, B, C;', 'implementation', 'end.']);
  C := Clause(3, [Entry(3, 6, 'A'), Entry(3, 9, 'B'), Entry(3, 12, 'C')]);
  Assert.AreEqual(Join(['unit u;', 'interface', 'uses A, C;', 'implementation',
    'end.']), FixUses(Src, C, 1, R), R);
  Assert.AreEqual(Join(['unit u;', 'interface', 'uses B, C;', 'implementation',
    'end.']), FixUses(Src, C, 0, R), R);
end;

procedure TTestRdxStructFixes.Sca007_RemoveLast;
var
  R, Src : string;
  C      : TRdxUsesClause;
begin
  Src := Join(['unit u;', 'interface', 'uses', '  A,', '  B,', '  C;',
    'implementation', 'end.']);
  C := Clause(3, [Entry(4, 3, 'A'), Entry(5, 3, 'B'), Entry(6, 3, 'C')]);
  Assert.AreEqual(Join(['unit u;', 'interface', 'uses', '  A,', '  B;',
    'implementation', 'end.']), FixUses(Src, C, 2, R), R);
  Src := Join(['unit u;', 'interface', 'uses A, B, C;', 'implementation', 'end.']);
  C := Clause(3, [Entry(3, 6, 'A'), Entry(3, 9, 'B'), Entry(3, 12, 'C')]);
  Assert.AreEqual(Join(['unit u;', 'interface', 'uses A, B;', 'implementation',
    'end.']), FixUses(Src, C, 2, R), R);
end;

procedure TTestRdxStructFixes.Sca007_RemoveOnly;
var
  R, Src : string;
begin
  // 'uses' allein am Zeilenanfang: die ganzen Zeilen.
  Src := Join(['unit u;', 'interface', 'uses', '  System.Classes;',
    'implementation', 'end.']);
  Assert.AreEqual(Join(['unit u;', 'interface', 'implementation', 'end.']),
    FixUses(Src, Clause(3, [Entry(4, 3, 'System.Classes')]), 0, R), R);
  // Hinter 'interface' auf derselben Zeile: nur der Text.
  Src := Join(['unit u;', 'interface uses A;', 'implementation', 'end.']);
  Assert.AreEqual(Join(['unit u;', 'interface ', 'implementation', 'end.']),
    FixUses(Src, Clause(2, [Entry(2, 16, 'A')]), 0, R), R);
end;

procedure TTestRdxStructFixes.Sca007_InPath;
var
  R, Src : string;
  C      : TRdxUsesClause;
begin
  Src := Join(['program p;', 'uses', '  A in ''a.pas'',', '  B in ''b.pas'';',
    'begin', 'end.']);
  C := Clause(2, [Entry(3, 3, 'A'), Entry(4, 3, 'B')]);
  Assert.AreEqual(Join(['program p;', 'uses', '  B in ''b.pas'';', 'begin',
    'end.']), FixUses(Src, C, 0, R), 'erster mit Pfad: ' + R);
  Assert.AreEqual(Join(['program p;', 'uses', '  A in ''a.pas'';', 'begin',
    'end.']), FixUses(Src, C, 1, R), 'letzter mit Pfad: ' + R);
end;

procedure TTestRdxStructFixes.Sca007_Refusals;
var
  R, Src : string;
begin
  // Ein Kommentar im geloeschten Bereich ginge verloren.
  Src := Join(['unit u;', 'interface', 'uses', '  A, { wichtig }', '  B;',
    'implementation', 'end.']);
  Assert.AreEqual('', FixUses(Src, Clause(3, [Entry(4, 3, 'A'), Entry(5, 3, 'B')]),
    0, R));
  Assert.IsTrue(Pos('Kommentar', R) > 0, R);
  // Formular-Unit im Programm: '{Form1}' hinter dem Pfad.
  Src := Join(['program p;', 'uses', '  Forms,', '  Unit1 in ''Unit1.pas'' {Form1};',
    'begin', 'end.']);
  Assert.AreEqual('', FixUses(Src, Clause(2, [Entry(3, 3, 'Forms'),
    Entry(4, 3, 'Unit1')]), 1, R));
  Assert.IsTrue(Pos('Kommentar', R) > 0, R);
  // Kein Komma hinter dem Eintrag (Bereich passt nicht mehr).
  Src := Join(['unit u;', 'interface', 'uses A B;', 'implementation', 'end.']);
  Assert.AreEqual('', FixUses(Src, Clause(3, [Entry(3, 6, 'A'), Entry(3, 8, 'B')]),
    0, R));
  Assert.IsTrue(Pos('","', R) > 0, R);
  Assert.AreEqual('', FixUses(Src, Clause(3, [Entry(3, 6, 'A')]), 2, R),
    'Index ausserhalb');
  Assert.IsTrue(R <> '');
end;

// ---- SCA168 ----

procedure TTestRdxStructFixes.Sca168_EmptyElse;
var
  R : string;
begin
  Assert.AreEqual(InProc(['  case X of', '    1: A;', '  else', '  end;']),
    FixCase(InProc(['  case X of', '    1: A;', '  end;']), 5, '', R), R);
  // Gross geschriebenes END bleibt, wie es war.
  Assert.AreEqual(InProc(['  case X of', '    1: A;', '  else', '  END;']),
    FixCase(InProc(['  case X of', '    1: A;', '  END;']), 5, '', R), R);
end;

procedure TTestRdxStructFixes.Sca168_RaiseElse;
var
  R : string;
begin
  Assert.AreEqual(InProc(['  case X of', '    1: A;', '  else',
      '    ' + RAISE_UNHANDLED, '  end;']),
    FixCase(InProc(['  case X of', '    1: A;', '  end;']), 5, RAISE_UNHANDLED, R), R);
  // Tabs: eine Stufe tiefer ist ein Tab.
  Assert.AreEqual(InProc([#9'case X of', #9#9'1: A;', #9'else',
      #9#9 + RAISE_UNHANDLED, #9'end;']),
    FixCase(InProc([#9'case X of', #9#9'1: A;', #9'end;']), 5, RAISE_UNHANDLED, R), R);
end;

procedure TTestRdxStructFixes.Sca168_NestedAndInline;
var
  R, Src : string;
begin
  Src := InProc(['  case X of', '    1: begin', '      case Y of', '        2: B;',
    '      end;', '    end;', '  end;']);
  Assert.AreEqual(InProc(['  case X of', '    1: begin', '      case Y of',
      '        2: B;', '      end;', '    end;', '  else', '  end;']),
    FixCase(Src, 5, '', R), 'aeusseres case: ' + R);
  Assert.AreEqual(InProc(['  case X of', '    1: begin', '      case Y of',
      '        2: B;', '      else', '      end;', '    end;', '  end;']),
    FixCase(Src, 7, '', R), 'inneres case: ' + R);
  // if-else in einem Arm ist kein else des case; try zaehlt mit.
  Assert.AreEqual(InProc(['  case X of', '    1: if A then B else C;',
      '    2: try D; finally E; end;', '  else', '  end;']),
    FixCase(InProc(['  case X of', '    1: if A then B else C;',
      '    2: try D; finally E; end;', '  end;']), 5, '', R), R);
  // end auf derselben Zeile: inline.
  Assert.AreEqual(InProc(['  case X of 1: A; else end;']),
    FixCase(InProc(['  case X of 1: A; end;']), 5, '', R), R);
  Assert.AreEqual(InProc(['  case X of 1: A; else ' + RAISE_UNHANDLED + ' end;']),
    FixCase(InProc(['  case X of 1: A; end;']), 5, RAISE_UNHANDLED, R), R);
end;

procedure TTestRdxStructFixes.Sca168_Refusals;
var
  R : string;
begin
  Assert.AreEqual('', FixCase(InProc(['  case X of', '    1: A;', '  else',
    '    B;', '  end;']), 5, '', R), 'schon ein else');
  Assert.IsTrue(Pos('else-Zweig', R) > 0, R);
  Assert.AreEqual('', FixCase(InProc(['  case X of', '{$IFDEF Y}', '    1: A;',
    '{$ENDIF}', '  end;']), 5, '', R), 'Direktive');
  Assert.IsTrue(Pos('Direktive', R) > 0, R);
  Assert.AreEqual('', FixCase(InProc(['  case X of 1: case Y of 2: A; end; end;']),
    5, '', R), 'zwei case auf der Zeile');
  Assert.IsTrue(Pos('mehrdeutig', R) > 0, R);
  Assert.AreEqual('', FixCase(InProc(['  A;']), 5, '', R), 'kein case');
  Assert.IsTrue(Pos('kein case', R) > 0, R);
  Assert.AreEqual('', FixCase(Join(['  case X of', '    1: A;']), 1, '', R),
    'kein end');
  Assert.IsTrue(Pos('kein end', R) > 0, R);
  Assert.AreEqual('', FixCase(InProc(['  case X of', '    1: A;', '  otherwise',
    '    B;', '  end;']), 5, '', R), 'FPC otherwise');
  Assert.IsTrue(Pos('otherwise', R) > 0, R);
  Assert.AreEqual('', FixCase(InProc(['  case X of', '  end;']), 5, '', R),
    'ohne Zweige');
  Assert.IsTrue(Pos('keine Zweige', R) > 0, R);
end;

procedure TTestRdxStructFixes.Sca168_LastArmWithoutSemicolon;
var
  R : string;
begin
  // Ohne das ';' bande das else an das if des Arms.
  Assert.AreEqual(InProc(['  case X of', '    1: if B then DoA;', '  else',
      '  end;']),
    FixCase(InProc(['  case X of', '    1: if B then DoA', '  end;']), 5, '', R), R);
  Assert.AreEqual(InProc(['  case X of', '    1: if B then DoA;', '  else',
      '    ' + RAISE_UNHANDLED, '  end;']),
    FixCase(InProc(['  case X of', '    1: if B then DoA', '  end;']), 5,
      RAISE_UNHANDLED, R), R);
  // Der Arm endet auf einem String - das ';' kommt hinter das Quote.
  Assert.AreEqual(InProc(['  case X of', '    1: S := ''x'';', '  else', '  end;']),
    FixCase(InProc(['  case X of', '    1: S := ''x''', '  end;']), 5, '', R), R);
  // Ein Kommentar dahinter bleibt hinter dem ';'.
  Assert.AreEqual(InProc(['  case X of', '    1: DoA; // weg', '  else', '  end;']),
    FixCase(InProc(['  case X of', '    1: DoA // weg', '  end;']), 5, '', R), R);
  // Inline: das ';' vor das else.
  Assert.AreEqual(InProc(['  case X of 1: if B then A; else end;']),
    FixCase(InProc(['  case X of 1: if B then A end;']), 5, '', R), R);
end;

procedure TTestRdxStructFixes.Sca168_IndentAndEscapedEnd;
var
  R : string;
begin
  // Vier Leerzeichen je Stufe: die raise-Zeile folgt den Armen.
  Assert.AreEqual(InProc(['    case X of', '        1: A;', '    else',
      '        ' + RAISE_UNHANDLED, '    end;']),
    FixCase(InProc(['    case X of', '        1: A;', '    end;']), 5,
      RAISE_UNHANDLED, R), R);
  // '&End' ist ein Bezeichner, kein end.
  Assert.AreEqual(InProc(['  case X of', '    1: &End := 1;', '  else', '  end;']),
    FixCase(InProc(['  case X of', '    1: &End := 1;', '  end;']), 5, '', R), R);
end;

procedure TTestRdxStructFixes.Sca007_OwnLineAndSkippedEntry;
var
  R, Src : string;
  C      : TRdxUsesClause;
begin
  // Allein auf seiner Zeile: die ganze Zeile samt '//'-Kommentar.
  Src := Join(['unit u;', 'interface', 'uses', '  System.SysUtils,',
    '  System.Classes,   // TStringList', '  System.Math;', 'implementation',
    'end.']);
  C := Clause(3, [Entry(4, 3, 'System.SysUtils'), Entry(5, 3, 'System.Classes'),
    Entry(6, 3, 'System.Math')]);
  Assert.AreEqual(Join(['unit u;', 'interface', 'uses', '  System.SysUtils,',
    '  System.Math;', 'implementation', 'end.']), FixUses(Src, C, 1, R), R);
  // Ein Eintrag, den UsesEntries ausliess (hier X), ginge mit - Sperre.
  Src := Join(['unit u;', 'interface', 'uses A, X, C;', 'implementation', 'end.']);
  Assert.AreEqual('', FixUses(Src, Clause(3, [Entry(3, 6, 'A'), Entry(3, 12, 'C')]),
    0, R));
  Assert.IsTrue(Pos('mehr als dieser Eintrag', R) > 0, R);
end;

// ---- SCA101 / SCA099 ----

procedure TTestRdxStructFixes.Sca101_OwnLines;
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

procedure TTestRdxStructFixes.Sca101_SplitLine;
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

procedure TTestRdxStructFixes.Sca101_Inline;
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

procedure TTestRdxStructFixes.Sca101_IfElse;
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

procedure TTestRdxStructFixes.Sca101_ListElse;
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

procedure TTestRdxStructFixes.Sca101_Refusals;
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

procedure TTestRdxStructFixes.Sca099_EndElse;
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
  Assert.AreEqual('', FixBlock(InProc(['  if A then begin X; end else if B then '
    + 'begin Y; end else Z;']), 5, '', R));
  Assert.IsTrue(Pos('mehrdeutig', R) > 0, R);
  Assert.AreEqual('', FixBlock(InProc(['  if A then begin X; end else ;']), 5, '',
    R));
  Assert.IsTrue(Pos('leere Anweisung', R) > 0, R);
  Assert.AreEqual('', FixBlock(InProc(['  if A then begin X; end else asm nop end;']),
    5, '', R));
  Assert.IsTrue(Pos('"asm"', R) > 0, R);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxStructFixes);

end.
