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
// Charge B1-FD (Code-Review reDelphix, Bereich R4; je Test gegen 4358b769
// rot, Fixtures des Pruefers rc/r401.txt, r401b.txt, r404.txt):
//   R4-01     Inline-Deklaration: 'End := 1' (benanntes Argument) beendet
//             den Block nicht - die Verwendung dahinter sperrt, auch mit
//             gleichnamigem Feld bzw. globaler Variable (still umgebunden);
//             steht es davor, bleibt die Deklaration inline (Hilfe);
//   missed 1  eine Verwendung nur in der until-Bedingung sperrt;
//   R4-04     ein Marker-Kommentar hinter der Deklaration bleibt stehen
//             (noinspection gilt der Folgezeile, ein Absichtsmarker wie
//             bei SCA019 bleibt);
//   R4-09     CutEdit am Dateiende hinter einem Surrogatpaar (SCA070) -
//             der Bereich beginnt auf der ersten Haelfte.
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
    [Test] procedure Sca053_InlineNamedEndArg_NoHelp;
    [Test] procedure Sca053_InlineAfterNamedEnd_Offered;
    [Test] procedure Sca053_InlineUntilCondition_NoHelp;
    [Test] procedure Sca053_TrailingMarker_Stays;
    [Test] procedure Sca070_LastLineBehindSurrogatePair;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uRefactorInfo, uRdxBufferMath, uRdxCodeMap, uRdxCleanupFixes;

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

// FPC 3.2: TStringList haelt AnsiString - mit UTF-8 als Systemcodepage
// bleiben Zeichen ausserhalb der Codepage (Surrogatpaare) erhalten, wie in
// den Korpus-Harnessen. Liefert die alte Codepage fuer RestoreCodePage.
// Unter Delphi ist TStringList Unicode - nichts zu tun.
function Utf8CodePage: Integer;
begin
  Result := DefaultSystemCodePage;
  {$IFDEF FPC}
  DefaultSystemCodePage := CP_UTF8;
  {$ENDIF}
end;

// Die Codepage von Utf8CodePage zurueck (unter Delphi derselbe Wert).
procedure RestoreCodePage(AOld: Integer);
begin
  DefaultSystemCodePage := AOld;
end;

// Die Bytes ABytes ab AFrom (ACount Bytes) als Text; '' ohne Bytes (FPC
// 3.2: kein GetString auf einem leeren Ausschnitt).
function Utf8Part(const ABytes: TBytes; AFrom, ACount: Integer): string;
begin
  Result := '';
  if ACount > 0 then
    Result := TEncoding.UTF8.GetString(ABytes, AFrom, ACount);
end;

// AEdit auf die UTF-8-Bytes von ASource anwenden wie der Editor: dieselbe
// Pruefung wie PlanByteEdits (Zeilen, dann der Byte-Ausschnitt) - '' und
// der neue Text in AResult, sonst der Fehler. Unter FPC 3.2 haelt
// TStringList AnsiString, und SpanText (PlanByteEdits) schneidet dort in
// Bytes statt Zeichen; deshalb hier die Byte-Pruefung von PlanOne ueber
// OffsetOf (Zeichen) - eine Grenze des Pruefstands wie in den Korpus-
// Harnessen, nicht des Codes. Unter Delphi zusaetzlich PlanByteEdits.
function ApplyAsEditor(const ASource: string; const AEdit: TRdxEdit;
  out AResult: string): string;
var
  Bytes      : TBytes;
  Starts     : TList<Integer>;
  SL         : TStringList;
  S, E       : Integer;
  Head, Tail : string;
  Slice, Ins : string;
  {$IFNDEF FPC}
  Edits      : TArray<TRdxEdit>;
  Plan       : TArray<TRdxByteEdit>;
  {$ENDIF}
begin
  AResult := '';
  Bytes := TEncoding.UTF8.GetBytes(ASource);
  Starts := TList<Integer>.Create;
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    LineStartsOf(Bytes, Starts);
    if not OffsetOf(Starts, SL, AEdit.Span.StartLine, AEdit.Span.StartCol, S)
       or not OffsetOf(Starts, SL, AEdit.Span.EndLine, AEdit.Span.EndCol, E)
       or (E <= S) or (E > Length(Bytes)) then
      Exit('Position im Puffer nicht berechenbar');
    Slice := NormalizeEol(Utf8Part(Bytes, S, E - S));
    if Slice <> AEdit.Expected then
      Exit('Byte-Bereich weicht ab' + DescribeMismatch(AEdit.Expected, Slice));
  finally
    SL.Free;
    Starts.Free;
  end;
  {$IFNDEF FPC}
  SetLength(Edits, 1);
  Edits[0] := AEdit;
  if not PlanByteEdits(Bytes, Edits, Plan, Result) then
    Exit;
  {$ENDIF}
  // Einzeln zuweisen: FPC 3.2.2 verkettet Funktionsergebnisse falsch.
  Head := Utf8Part(Bytes, 0, S);
  Ins := StringReplace(AEdit.NewText, #10, BufferEol(Bytes), [rfReplaceAll]);
  Tail := Utf8Part(Bytes, E, Length(Bytes) - E);
  AResult := Head + Ins + Tail;
  Result := '';
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

// ---- Charge B1-FD (Code-Review reDelphix, R4) ----

procedure TTestRdxCleanupScope.Sca053_InlineNamedEndArg_NoHelp;
begin
  // R4-01, Pruefer-Fall r401 (1): 'End' als benanntes OLE-Argument im Block
  // der Inline-Variablen - BlockStop endete dort, 'X := 5' blieb ungesehen,
  // und nach der Hilfe schrieb es still in die globale Variable X.
  AssertRefused(InImpl(['var', '  X: Integer;', 'procedure P(Doc: Variant);',
    'begin', '  if Doc <> 0 then', '  begin', '    var X: Integer;',
    '    Doc.Range(Start := 0, End := 1);', '    X := 5;', '  end;',
    '  Writeln(X);', 'end;']), 10, 'X', 'noch vor (Zeile 12)');
  // r401b (2), missed 4: dieselbe Form in einer Methode mit dem Feld Count -
  // nach der Hilfe schrieb 'Count := 5' still in Self.Count.
  AssertRefused(Join(['unit u;', 'interface', 'implementation', 'type',
    '  TFoo = class', '    Count: Integer;', '    procedure P(Doc: Variant);',
    '  end;', 'procedure TFoo.P(Doc: Variant);', 'begin', '  if Doc <> 0 then',
    '  begin', '    var Count: Integer;', '    Doc.Range(Start := 0, End := 1);',
    '    Count := 5;', '  end;', 'end;', 'end.']), 13, 'Count',
    'noch vor (Zeile 15)');
  // r401 (4): ebenso 'Until := 3'.
  AssertRefused(InImpl(['procedure P(Doc: Variant);', 'begin',
    '  if Doc <> 0 then', '  begin', '    var X: Integer;',
    '    Foo(Until := 3);', '    X := 5;', '  end;', 'end;']), 8, 'X',
    'noch vor (Zeile 10)');
end;

procedure TTestRdxCleanupScope.Sca053_InlineAfterNamedEnd_Offered;
begin
  // R4-01, Rueckrichtung: 'End := 1' VOR der Inline-Deklaration hielt die
  // Suche nach dem Block fuer ein end - sie las die Deklaration als
  // var-Section und lehnte mit "Rumpf der Routine nicht gefunden" ab. Jetzt
  // ist sie inline, X ist unbenutzt: die Hilfe greift.
  Assert.AreEqual(InImpl(['procedure P(Doc: Variant);', 'begin',
      '  Doc.Range(Start := 0, End := 1);', '  Foo;', 'end;']),
    FixOk(InImpl(['procedure P(Doc: Variant);', 'begin',
      '  Doc.Range(Start := 0, End := 1);', '  var X: Integer;', '  Foo;',
      'end;']), 7, 'X'));
end;

procedure TTestRdxCleanupScope.Sca053_InlineUntilCondition_NoHelp;
begin
  // missed 1, Pruefer-Fall r401b (1): X steht nur in der until-Bedingung -
  // BlockStop endete am until, nach der Hilfe fehlte X (E2003) bzw. band an
  // ein gleichnamiges X ausserhalb.
  AssertRefused(InImpl(['procedure P;', 'begin', '  repeat',
    '    var X: Integer;', '    Foo;', '  until X > 0;', 'end;']), 7, 'X',
    'noch vor (Zeile 9)');
  // Gegenprobe: die Bedingung endet am ';' - danach zaehlt nichts mehr,
  // ein unbenutztes X bekommt die Hilfe.
  Assert.AreEqual(InImpl(['procedure P;', 'begin', '  repeat', '    Foo;',
      '  until Bar > 0;', 'end;']),
    FixOk(InImpl(['procedure P;', 'begin', '  repeat', '    var X: Integer;',
      '    Foo;', '  until Bar > 0;', 'end;']), 7, 'X'));
end;

procedure TTestRdxCleanupScope.Sca053_TrailingMarker_Stays;
begin
  // R4-04, Pruefer-Fall r404 (1): der Marker hinter X gilt der Folgezeile
  // (uSuppression.BuildMap) - er bleibt als eigene Zeile stehen und zielt
  // weiter auf Y.
  Assert.AreEqual(InImpl(['procedure P;', 'var',
      '  // noinspection UnusedLocalVar', '  Y: Integer;', 'begin',
      '  Writeln(''a'');', 'end;']),
    FixOk(InImpl(['procedure P;', 'var',
      '  X: Integer; // noinspection UnusedLocalVar', '  Y: Integer;', 'begin',
      '  Writeln(''a'');', 'end;']), 6, 'X'));
  // r404 (2): ein Absichtsmarker (SCA019) bleibt ebenso; wird die Section
  // leer, ruecken var und Deklaration weg, der Kommentar an ihre Stelle.
  Assert.AreEqual(InImpl(['procedure P;', '// TODO: fuer Version 2', 'begin',
      'end;']),
    FixOk(InImpl(['procedure P;', 'var', '  X: Integer; // TODO: fuer Version 2',
      'begin', 'end;']), 6, 'X'));
  // Inline ebenso.
  Assert.AreEqual(InImpl(['procedure P;', 'begin', '  // noinspection Foo',
      '  Bar;', 'end;']),
    FixOk(InImpl(['procedure P;', 'begin', '  var X: Integer; // noinspection Foo',
      '  Bar;', 'end;']), 6, 'X'));
  // Gegenprobe: ein Kommentar ohne Marker beschreibt die Variable und geht
  // mit der Zeile.
  Assert.AreEqual(InImpl(['procedure P;', 'var', '  Y: Integer;', 'begin',
      '  Y := 1;', 'end;']),
    FixOk(InImpl(['procedure P;', 'var', '  X: Integer; // Zaehler',
      '  Y: Integer;', 'begin', '  Y := 1;', 'end;']), 6, 'X'));
end;

procedure TTestRdxCleanupScope.Sca070_LastLineBehindSurrogatePair;
const
  MSG070 = 'Comment at column 1 looks like commented-out code - delete or '
    + 'extract into a TODO if still relevant.';
var
  Src, Pair, Got, Err, Reason : string;
  SL                          : TStringList;
  Map                         : TRdxCodeMap;
  E                           : TRdxEdit;
  Ok                          : Boolean;
  OldCp                       : Integer;
begin
  // R4-09: der Fund steht in der letzten Zeile, die Zeile davor endet auf
  // einem Emoji (Surrogatpaar). Der Bereich beginnt AUF ihrem letzten
  // Zeichen - bis Charge B1-FD auf der zweiten Haelfte des Paars: die
  // Byte-Pruefung scheiterte bei jedem Klick (PlanOne, "Byte-Bereich
  // weicht ab").
  OldCp := Utf8CodePage;
  try
    Pair := #$D83D#$DE00;
    Src := Join(['unit u;', 'interface', 'implementation',
      'end. // Ende ' + Pair, '// X := 1; Y := 2;']);
    SL := TStringList.Create;
    Map := nil;
    try
      SL.Text := Src;
      Map := TRdxCodeMap.Create(SL);
      Ok := TRdxCleanupFixes.CommentedOutCode(Map, 5, MSG070, E, Reason);
    finally
      Map.Free;
      SL.Free;
    end;
    Assert.IsTrue(Ok, Reason);
    Assert.AreEqual<Integer>(4, E.Span.StartLine, 'Zeile');
    Assert.AreEqual<Integer>(Length('end. // Ende ') + 1, E.Span.StartCol,
      'Spalte = erste Haelfte vom Paar');
    Assert.AreEqual(Pair, E.NewText, 'das Paar wird ganz neu geschrieben');
    Err := ApplyAsEditor(Src, E, Got);
    Assert.AreEqual('', Err, 'Byte-Pruefung');
    Assert.AreEqual(Join(['unit u;', 'interface', 'implementation',
      'end. // Ende ' + Pair]), Got);
  finally
    RestoreCodePage(OldCp);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxCleanupScope);

end.
