unit uTestRdxStructFixes;

// Editorhilfen der Stufe 3 (uRdxStructFixes) auf Text - ohne Parser, ohne
// Detektor (laeuft in reDelphix.Test UND im FPC-Pruefstand):
//   SCA007 einen uses-Eintrag loeschen (erster, mittlerer, letzter,
//          einziger, 'in'-Pfad, Kommentar im Bereich),
//   SCA168 else vor das end des case (leer, mit raise, Einrueckung mit
//          Tabs, verschachtelt, inline, schon ein else, Direktive).
// SCA101/SCA099 (begin..end) stehen in uTestRdxBlockFixes - der FPC-
// Pruefstand kennt nur eine Fixture je Unit.
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

initialization
  TDUnitX.RegisterTestFixture(TTestRdxStructFixes);

end.
