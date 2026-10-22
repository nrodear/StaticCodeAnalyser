unit uTestRdxRoutineFixes;

// Ungenutzte freie Routine loeschen (uRdxRoutineFixes, Charge H3b, SCA164)
// und die Bausteine Routinengrenzen (ReadRoutine) und Decl/Impl-Finder auf
// Text (seit Charge B2S-b in uRdxBlocks) - ohne Parser, ohne Detektor
// (laeuft in reDelphix.Test UND im FPC-Pruefstand):
//   Bausteine: lokale Abschnitte (Variantenrecord, Prozedurtypen),
//          lokale Routinen, Direktiven auf Folgezeilen, generische Typen
//          im Kopf, forward, asm mit '@@end'; Ablehnungen (lokaler
//          Klassentyp, Kopf ohne ';', Kopf im Rumpf, fehlendes ';');
//          Finder ueber verschachtelte, generische Klassen, Overloads,
//          class-Methoden.
//   SCA164: Doku-, Kommentar- und Leerzeile gehen mit, ein Einzeiler, die
//          Leerzeile davor (Bereich ab dem Zeichen davor), forward,
//          Abschnittsmarker bleibt / Ueberschrift mit dem Namen geht;
//          Sperren: Verwendung (auch im inaktiven $IFDEF-Zweig, '@X',
//          exports, interface), Overload, String-Literal, Direktive mit dem
//          Namen, {$L}, {$I}, Schalter-Direktive, unausgeglichenes $IFDEF,
//          export, Methode, zwei Routinen auf einer Zeile, Programm,
//          verschobene Meldung. Charge H3c (Gegen-Review H3, je mit der
//          Pruefer-Fixture aus rc/cases164.txt bzw. casesuni.txt): Include
//          vor implementation (Planer nennt es, IncludeReason liest es;
//          Kopf-Includes nicht), FPC-Direktiven in Klammern, Marker und
//          Ueberschrift ueber dem Kopf bleiben, globaler FPC-Operator,
//          Aufruf in anderer Umlaut-Schreibung. Charge B1-FD (Code-Review
//          reDelphix, R4, Pruefer-Fixtures rc/r404.txt, vunc.pas): Marker
//          hinter 'end;' bzw. der forward-Deklaration und
//          'noinspection-file' im Rumpf sperren (R4-04); Include bzw. Unit
//          auf einem Netzpfad ohne Plattenzugriff abgelehnt (R4-03).
//          Nachpruefung B1-FD: ein '// noinspection' ueber dem Kopf bzw.
//          der forward-Deklaration (eigene Zeile, hinter Leerzeile oder
//          hinter dem 'end;' davor) zielt auf die Routine - keine Hilfe
//          (neu 1); '{$I \datei.inc}' liegt auf dem Laufwerk der Unit,
//          nicht dem aktuellen (neu 5, IncludeSearchPath).
//   Review Woche (G05-03, G05-25): ein UTF-8-Include ohne BOM mit Umlaut-
//          Namen wird gelesen; die Ablehnungszweige von OwnLinesReason, die
//          Direktiven-Bilanz mit $REGION, FPC-Klammern ohne ']' bzw. ';'
//          und MAX_NESTING (in den bestehenden Tests - die Fixture hat 20).
// Die Gegenprobe mit dem echten Detektor steht in
// uTestRdxRoutineFixesDetector (nur Delphi).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxRoutineFixes = class
  public
    [Test] procedure Block_ReadRoutine;
    [Test] procedure Block_ReadRoutine_Refusals;
    [Test] procedure Block_Finder;
    [Test] procedure Sca164_DocCommentsBlankLine;
    [Test] procedure Sca164_OneLiner_BlankBefore;
    [Test] procedure Sca164_Forward;
    [Test] procedure Sca164_Marker;
    [Test] procedure Sca164_BalancedIfdef;
    [Test] procedure Sca164_Used_NoHelp;
    [Test] procedure Sca164_ByName_NoHelp;
    [Test] procedure Sca164_Directives_NoHelp;
    [Test] procedure Sca164_Reachable_NoHelp;
    [Test] procedure Sca164_Moved_NoHelp;
    [Test] procedure Sca164_InterfaceInclude;
    [Test] procedure Sca164_FpcModifierBracket_NoHelp;
    [Test] procedure Sca164_MarkerAndHeadingStay;
    [Test] procedure Sca164_GlobalOperator_NoHelp;
    [Test] procedure Sca164_UmlautCall_NoHelp;
    [Test] procedure Sca164_MarkerAround_NoHelp;
    [Test] procedure Sca164_IncludeOnNetworkPath_NoDiskAccess;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxCodeMap, uRdxRoutineFixes,
  uRdxBlocks,  // ReadRoutine, Finder, IncludeSearchPath (seit Charge B2S-b)
  uRdxPaths,   // IsNetworkPath (seit Charge B2S-a dort, bis dahin hier)
  uTestRdxTextKit;   // Join, Apply, WriteText, NewTempDir

const
  MSG_TAIL = ' appears unused (no caller within the unit, no interface '
    + 'forward-declaration)';

// ---- Helfer ----

function Msg(const AName: string): string;
begin
  Result := 'Top-level routine ' + AName + MSG_TAIL;
end;

// Eine Unit, deren implementation ALines traegt (ab Zeile 4).
function InImpl(const ALines: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'implementation']) + #13#10
    + Join(ALines) + #13#10 + 'end.';
end;

// Der Plan fuer die Meldung AMessage auf Zeile ALine; AReason = '' heisst
// Hilfe.
function PlanOf(const ASource: string; ALine: Integer; const AMessage: string;
  out AReason: string): TRdxRoutinePlan;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    TRdxRoutineFixes.UnusedRoutine(Map, ALine, AMessage, Result, AReason);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Neuer Text oder '' bei Ablehnung (AReason).
function Fix(const ASource: string; ALine: Integer; const AName: string;
  out AReason: string): string;
var
  P : TRdxRoutinePlan;
begin
  Result := '';
  P := PlanOf(ASource, ALine, Msg(AName), AReason);
  if AReason = '' then
    Result := Apply(ASource, P.Edits);
end;

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

// Das Token, mit dem Zeile ALine beginnt (Kopf fuer ReadRoutine).
function LineHead(AMap: TRdxCodeMap; ALine: Integer): TRdxToken;
begin
  Result := NextToken(AMap, ALine, 1);
end;

// ReadRoutine fuer den Kopf auf Zeile ALine; '' oder der Grund.
function ReadAt(const ASource: string; ALine: Integer;
  out R: TRdxRoutine): string;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    Result := TRdxBlocks.ReadRoutine(Map, LineHead(Map, ALine), R);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Ein frisches Verzeichnis TEMP\rdx_h3c_<GUID>\ fuer Include-Dateien (mit
// Trenner), eigen je Aufruf: unter dem festen Namen 'rdx_h3c_inc' teilten
// sich parallele Laeufe die Dateien, und ein deeper.inc aus einem
// abgebrochenen Lauf machte Sca164_InterfaceInclude rot (Review R6-07).
function TempDir: string;
begin
  Result := NewTempDir('rdx_h3c_');
end;

// Schreibt AText als UTF-8 OHNE BOM (Review Woche G05-03) - dieselbe Form
// wie uTestRdxText.WriteUtf8; uTestRdxTextKit.WriteText schreibt ueber
// TStringList, ohne Umstellung der Systemcodepage ANSI.
procedure WriteUtf8NoBom(const APath, AText: string);
var
  Bytes : TBytes;
  FS    : TFileStream;
begin
  Bytes := TEncoding.UTF8.GetBytes(AText);
  FS := TFileStream.Create(APath, fmCreate);
  try
    if Length(Bytes) > 0 then
      FS.WriteBuffer(Bytes[0], Length(Bytes));
  finally
    FS.Free;
  end;
end;

procedure AssertReadRefused(const ASource: string; ALine: Integer;
  const APart: string);
var
  R      : TRdxRoutine;
  Reason : string;
begin
  Reason := ReadAt(ASource, ALine, R);
  Assert.IsTrue(Pos(APart, Reason) > 0, 'Grund: ' + Reason);
end;

// ---- Bausteine ----

procedure TTestRdxRoutineFixes.Block_ReadRoutine;
var
  Src    : string;
  R      : TRdxRoutine;
begin
  Src := InImpl([
    'function F(const A: array of Integer;',          // 4
    '  B: TFunc<Integer>): TList<string>;',           // 5
    '  overload; inline;',                            // 6
    'type',                                           // 7
    '  TRec = record',                                // 8
    '    case Integer of',                            // 9
    '      0: (X: Integer);',                         // 10
    '      1: (Y: Single);',                          // 11
    '  end;',                                         // 12
    '  TProc = procedure of object;',                 // 13
    'var',                                            // 14
    '  P: procedure(X: Integer);',                    // 15
    '  procedure Local;',                             // 16
    '  begin',                                        // 17
    '    case 1 of 1: ; end;',                        // 18
    '  end;',                                         // 19
    'begin',                                          // 20
    '  try',                                          // 21
    '  finally',                                      // 22
    '  end;',                                         // 23
    'end;',                                           // 24
    'procedure G; forward;',                          // 25
    'procedure H; asm',                               // 26
    '  @@end: ret',                                   // 27
    'end;',                                           // 28
    'class procedure TFoo<T>.Run;',                   // 29
    'begin',                                          // 30
    'end;',                                           // 31
    'procedure V;',                                   // 32
    'type',                                           // 33
    '  R = record case Byte of 0: (A: Integer); end;',  // 34
    'begin',                                          // 35
    'end;']);                                         // 36
  // Variantenrecord ('case' ohne eigenes end), Prozedurtypen und eine
  // lokale Routine im Deklarationsteil; Direktiven auf der Folgezeile.
  Assert.AreEqual('', ReadAt(Src, 4, R));
  Assert.AreEqual('F', R.Name);
  Assert.AreEqual<Integer>(2, Integer(Length(R.Directives)));
  Assert.AreEqual('inline', R.Directives[1]);
  Assert.AreEqual<Integer>(20, R.Body.Line);
  Assert.AreEqual<Integer>(24, R.EndTok.Line);
  Assert.AreEqual<Integer>(24, R.Last.Line);
  // forward: ohne Rumpf, das ';' hinter forward ist das Ende.
  Assert.AreEqual('', ReadAt(Src, 25, R));
  Assert.AreEqual('', R.Body.Low);
  Assert.AreEqual<Integer>(25, R.Last.Line);
  // asm: '@@end' ist eine Marke, das end auf Zeile 28 schliesst.
  Assert.AreEqual('', ReadAt(Src, 26, R));
  Assert.AreEqual('asm', R.Body.Low);
  Assert.AreEqual<Integer>(28, R.EndTok.Line);
  // class-Methode einer generischen Klasse: Kopf ab 'class', Name ohne <T>.
  Assert.AreEqual('', ReadAt(Src, 29, R));
  Assert.AreEqual('class', R.Head.Low);
  Assert.AreEqual('TFoo.Run', R.Name);
  Assert.AreEqual<Integer>(31, R.Last.Line);
  // Variantenrecord ohne lokale Routine danach: zaehlte sein 'case' als
  // Block, blieb ein end offen, und der Rumpf von V wuerde verfehlt.
  Assert.AreEqual('', ReadAt(Src, 32, R));
  Assert.AreEqual<Integer>(35, R.Body.Line);
  Assert.AreEqual<Integer>(36, R.Last.Line);
end;

procedure TTestRdxRoutineFixes.Block_ReadRoutine_Refusals;
var
  Nested  : TArray<string>;
  i       : Integer;
  R       : TRdxRoutine;
begin
  AssertReadRefused(InImpl(['procedure P;', 'type', '  TC = class',
    '  end;', 'begin', 'end;']), 4, 'lokaler Klassen');
  AssertReadRefused(InImpl(['procedure P', 'begin', 'end;']), 4,
    'Ende des Kopfs');
  // Ein Kopf hinter ';' im Rumpf: das passende end wurde verfehlt.
  AssertReadRefused(InImpl(['procedure P;', 'begin', '  X := 1;',
    'procedure Q;', 'begin', 'end;']), 4, 'Routinenkopf im Rumpf');
  AssertReadRefused(InImpl(['procedure P;', 'begin', 'end']), 4,
    'fehlt ";"');
  // Review Woche G05-25: FPC-Direktiven in Klammern ohne ']' bzw. ohne ';'
  // dahinter.
  AssertReadRefused(InImpl(['procedure P; [public', 'begin', 'end;']), 4,
    '"[" ohne "]"');
  AssertReadRefused(InImpl(['procedure P; [public]', 'begin', 'end;']), 4,
    '"[..]" ohne ";"');
  // ... und MAX_NESTING: acht lokale Routinen ineinander liest ReadRoutine
  // noch, die neunte nicht mehr. P0 bis P9 je auf einer Zeile, dann je ein
  // 'begin end;' von innen nach aussen.
  Nested := nil;
  for i := 0 to 9 do
    AddText(Nested, Format('procedure P%d;', [i]));
  for i := 0 to 9 do
    AddText(Nested, 'begin end;');
  AssertReadRefused(InImpl(Nested), 4, 'zu tief verschachtelt');
  Nested := nil;
  for i := 0 to 8 do
    AddText(Nested, Format('procedure P%d;', [i]));
  for i := 0 to 8 do
    AddText(Nested, 'begin end;');
  Assert.AreEqual('', ReadAt(InImpl(Nested), 4, R), 'acht Ebenen');
end;

procedure TTestRdxRoutineFixes.Block_Finder;
var
  SL    : TStringList;
  Map   : TRdxCodeMap;
  Heads : TArray<TRdxToken>;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := Join([
      'unit u;',                                      // 1
      'interface',                                    // 2
      'type',                                         // 3
      '  TOuter = class',                             // 4
      '  private',                                    // 5
      '    type',                                     // 6
      '      TInner = class',                         // 7
      '      private',                                // 8
      '        procedure Run;',                       // 9
      '      end;',                                   // 10
      '    procedure Run(A: Integer); overload;',     // 11
      '    procedure Run(S: string); overload;',      // 12
      '  end;',                                       // 13
      '  TGen<T> = class',                            // 14
      '  strict private',                             // 15
      '    class procedure Make;',                    // 16
      '  end;',                                       // 17
      'implementation',                               // 18
      'procedure TOuter.TInner.Run;',                 // 19
      'begin end;',                                   // 20
      'procedure TOuter.Run(A: Integer);',            // 21
      'begin end;',                                   // 22
      'procedure TOuter.Run(S: string);',             // 23
      'begin end;',                                   // 24
      'class procedure TGen<T>.Make;',                // 25
      'begin end;',                                   // 26
      'end.']);
    Map := TRdxCodeMap.Create(SL);
    Heads := TRdxBlocks.FindMethodDecls(Map, 'TInner', 'Run');
    Assert.AreEqual<Integer>(1, Integer(Length(Heads)), 'TInner.Run deklariert');
    Assert.AreEqual<Integer>(9, Heads[0].Line);
    // Tiefe 1: die Methode der inneren Klasse zaehlt fuer TOuter nicht.
    Assert.AreEqual<Integer>(2, Integer(Length(TRdxBlocks.FindMethodDecls(Map,
      'TOuter', 'Run'))), 'Overloads von TOuter.Run');
    Heads := TRdxBlocks.FindMethodImpls(Map, 'TInner', 'Run');
    Assert.AreEqual<Integer>(1, Integer(Length(Heads)), 'TInner.Run implementiert');
    Assert.AreEqual<Integer>(19, Heads[0].Line);
    Assert.AreEqual<Integer>(1, Integer(Length(TRdxBlocks.FindMethodImpls(Map,
      'TOuter.TInner', 'Run'))), 'mit Pfad');
    Assert.AreEqual<Integer>(2, Integer(Length(TRdxBlocks.FindMethodImpls(Map,
      'TOuter', 'Run'))), 'Overloads implementiert');
    Heads := TRdxBlocks.FindMethodDecls(Map, 'TGen', 'Make');
    Assert.AreEqual<Integer>(1, Integer(Length(Heads)), 'generisch deklariert');
    Assert.AreEqual('class', Heads[0].Low);
    Heads := TRdxBlocks.FindMethodImpls(Map, 'TGen', 'Make');
    Assert.AreEqual<Integer>(1, Integer(Length(Heads)), 'generisch implementiert');
    Assert.AreEqual<Integer>(25, Heads[0].Line);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// ---- SCA164 ----

procedure TTestRdxRoutineFixes.Sca164_DocCommentsBlankLine;
begin
  // '///'-Doku und der Kommentar direkt darueber gehen mit (er nennt die
  // Routine), die lokale Routine (sie ruft Dead - im eigenen Bereich zaehlt
  // das nicht) und die Leerzeile dahinter auch.
  Assert.AreEqual(InImpl(['procedure Keep;', 'begin', 'end;', '',
      'procedure Keep2;', 'begin', '  Keep;', 'end;']),
    FixOk(InImpl(['procedure Keep;', 'begin', 'end;', '',
      '/// <summary>Helper</summary>',
      '// Dead does X',
      'procedure Dead(A: Integer);',       // 10
      'var',
      '  I: Integer;',
      '  procedure Inner;',
      '  begin',
      '    Dead(I);',
      '  end;',
      'begin',
      '  I := A;',
      '  Inner;',
      'end;',
      '',
      'procedure Keep2;', 'begin', '  Keep;', 'end;']), 10, 'Dead'));
end;

procedure TTestRdxRoutineFixes.Sca164_OneLiner_BlankBefore;
var
  P : TRdxRoutinePlan;
  R : string;
  Src : string;
begin
  // Der Einzeiler als ganze Zeile; hinter ihm keine Leerzeile, also die
  // davor - die ist leer, der Bereich beginnt auf dem ';' der Zeile davor
  // (ein Bereich darf nicht auf einer leeren Zeile beginnen).
  Src := InImpl(['procedure A; begin end;', '',
    'procedure Dead; begin end;', 'procedure B; begin A; end;']);
  P := PlanOf(Src, 6, Msg('Dead'), R);
  Assert.AreEqual('', R);
  Assert.AreEqual<Integer>(4, P.Edits[0].Span.StartLine);
  Assert.AreEqual(';'#10, P.Edits[0].NewText);
  Assert.AreEqual(InImpl(['procedure A; begin end;',
    'procedure B; begin A; end;']), Apply(Src, P.Edits));
end;

procedure TTestRdxRoutineFixes.Sca164_Forward;
begin
  // Die forward-Deklaration geht als zweite Ersetzung mit.
  Assert.AreEqual(InImpl(['', 'procedure Keep;', 'begin', 'end;']),
    FixOk(InImpl(['procedure Dead; forward;', '', 'procedure Keep;', 'begin',
      'end;', '', 'procedure Dead;', 'begin', 'end;']), 10, 'Dead'));
end;

procedure TTestRdxRoutineFixes.Sca164_Marker;
var
  Src : string;
begin
  Src := InImpl(['{ Helpers }', 'procedure Dead;', 'begin', 'end;', '',
    '{ Dead2 }', 'procedure Dead2;', 'begin', 'end;', '', 'procedure Keep;',
    'begin', 'end;']);
  // Der Abschnittsmarker gehoert zur Gruppe und bleibt ...
  Assert.AreEqual(InImpl(['{ Helpers }', '{ Dead2 }', 'procedure Dead2;',
    'begin', 'end;', '', 'procedure Keep;', 'begin', 'end;']),
    FixOk(Src, 5, 'Dead'));
  // ... eine Ueberschrift mit dem Namen der Routine geht mit.
  Assert.AreEqual(InImpl(['{ Helpers }', 'procedure Dead;', 'begin', 'end;',
    '', 'procedure Keep;', 'begin', 'end;']), FixOk(Src, 10, 'Dead2'));
end;

procedure TTestRdxRoutineFixes.Sca164_BalancedIfdef;
begin
  // Ein $IFDEF mit $ENDIF im Bereich geht mit der Routine.
  Assert.AreEqual(InImpl(['procedure Keep;', 'begin', 'end;']),
    FixOk(InImpl(['procedure Dead;', 'begin', '{$IFDEF DEBUG}', '  Beep;',
      '{$ELSE}', '  Sleep(1);', '{$ENDIF}', 'end;', '', 'procedure Keep;',
      'begin', 'end;']), 4, 'Dead'));
  // Ebenso $REGION mit $ENDREGION (Review Woche G05-25: der Stapel 'r').
  Assert.AreEqual(InImpl(['procedure Keep;', 'begin', 'end;']),
    FixOk(InImpl(['procedure Dead;', 'begin', '{$REGION ''Teil''}', '  Beep;',
      '{$ENDREGION}', 'end;', '', 'procedure Keep;', 'begin', 'end;']), 4,
      'Dead'));
end;

procedure TTestRdxRoutineFixes.Sca164_Used_NoHelp;
begin
  // Ein Aufruf im inaktiven $IFDEF-Zweig - der Parser des Scans sieht ihn
  // nicht, die Textsuche schon (Korpus: mORMot ExchgLen).
  AssertRefused(InImpl(['procedure Dead;', 'begin', 'end;', 'procedure Keep;',
    'begin', '{$IFDEF NEVER}', '  Dead;', '{$ENDIF}', 'end;']), 4, 'Dead',
    'Zeile 10 verwendet');
  AssertRefused(InImpl(['procedure Dead;', 'begin', 'end;', 'var',
    '  P: Pointer = @Dead;']), 4, 'Dead', 'verwendet');
  AssertRefused(InImpl(['procedure Dead;', 'begin', 'end;',
    'exports Dead;']), 4, 'Dead', 'exports');
  AssertRefused(Join(['unit u;', 'interface', 'procedure Dead;',
    'implementation', 'procedure Dead;', 'begin', 'end;', 'end.']), 5,
    'Dead', 'interface-Teil');
  AssertRefused(InImpl(['procedure Dead(A: Integer); overload;', 'begin',
    'end;', 'procedure Dead(S: string); overload;', 'begin', 'end;']), 4,
    'Dead', 'zweite Routine');
end;

procedure TTestRdxRoutineFixes.Sca164_ByName_NoHelp;
begin
  AssertRefused(InImpl(['procedure Dead;', 'begin', 'end;', 'procedure Keep;',
    'begin', '  GetProcAddress(0, ''Dead'');', 'end;']), 4, 'Dead',
    'String-Literal');
  AssertRefused(InImpl(['{$EXTERNALSYM Dead}', 'procedure Dead;', 'begin',
    'end;']), 5, 'Dead', 'Direktive nennt');
  AssertRefused(InImpl(['{$L dead.obj}', 'procedure Dead; cdecl;', 'begin',
    'end;']), 5, 'Dead', 'Objektdatei');
  AssertRefused(InImpl(['{$I callers.inc}', 'procedure Dead;', 'begin',
    'end;']), 5, 'Dead', 'Include');
end;

procedure TTestRdxRoutineFixes.Sca164_Directives_NoHelp;
begin
  // Ein Schalter im Bereich wirkt ueber die Routine hinaus.
  AssertRefused(InImpl(['procedure Dead;', 'begin', '{$R-}', '  Beep;',
    'end;']), 4, 'Dead', '{$R}');
  // $IFDEF-geteilter Rumpf: das $ENDIF steht hinter dem Bereich.
  AssertRefused(InImpl(['procedure Dead;', 'begin', '{$IFDEF X}', '  Beep;',
    'end;', '{$ELSE}', 'end;', '{$ENDIF}']), 4, 'Dead', 'Gegenstueck');
  // Review Woche G05-25: $ENDREGION ohne $REGION, $ELSE ohne $IF und ein
  // $ENDIF, dessen offenes Gegenstueck eine $REGION ist.
  AssertRefused(InImpl(['procedure Dead;', 'begin', '{$ENDREGION}', 'end;']),
    4, 'Dead', '{$ENDREGION} in Zeile 6 ohne Gegenstueck');
  AssertRefused(InImpl(['procedure Dead;', 'begin', '{$ELSE}', 'end;']), 4,
    'Dead', '{$ELSE} in Zeile 6 ohne $IF');
  AssertRefused(InImpl(['procedure Dead;', 'begin', '{$IFDEF X}',
    '{$REGION ''r''}', '{$ENDIF}', '{$ENDREGION}', 'end;']), 4, 'Dead',
    '{$ENDIF} in Zeile 8 ohne Gegenstueck');
end;

procedure TTestRdxRoutineFixes.Sca164_Reachable_NoHelp;
begin
  AssertRefused(InImpl(['procedure Dead; cdecl; export;', 'begin', 'end;']),
    4, 'Dead', 'export');
  AssertRefused(InImpl(['procedure Dead; external ''x.dll'';']), 4, 'Dead',
    'external');
  AssertRefused(InImpl(['procedure TFoo.Run;', 'begin', 'end;']), 4, 'TFoo',
    'Methode einer Klasse');
  AssertRefused(InImpl(['procedure A; begin end; procedure Dead; begin end;']),
    4, 'Dead', 'vor dem Kopf');
  AssertRefused(Join(['program p;', 'procedure Dead;', 'begin', 'end;',
    'begin', 'end.']), 2, 'Dead', 'implementation-Teil');
  // Review Woche G05-25: die anderen Zweige von OwnLinesReason - Code
  // hinter dem Ende, ein Block-Kommentar, der auf der Kopfzeile endet bzw.
  // hinter dem Ende beginnt, und das Ende auf der letzten Zeile der Datei
  // (InImpl haengt immer 'end.' an, deshalb hier ohne).
  AssertRefused(InImpl(['procedure Dead; begin end; procedure B; begin end;']),
    4, 'Dead', 'hinter dem Ende steht Code');
  AssertRefused(InImpl(['{ Kommentar', '  ueber Zeilen } procedure Dead;',
    'begin', 'end;', 'procedure B;', 'begin', 'end;']), 5, 'Dead',
    'auf der Kopfzeile endet ein Kommentar');
  AssertRefused(InImpl(['procedure Dead;', 'begin', 'end; { Kommentar',
    '  ueber Zeilen }', 'procedure B;', 'begin', 'end;']), 4, 'Dead',
    'hinter dem Ende beginnt ein Kommentar');
  AssertRefused(Join(['unit u;', 'interface', 'implementation',
    'procedure Dead;', 'begin', 'end;']), 4, 'Dead',
    'letzten Zeile der Datei');
end;

procedure TTestRdxRoutineFixes.Sca164_Moved_NoHelp;
var
  R : string;
begin
  AssertRefused(InImpl(['procedure Dead;', 'begin', 'end;']), 5, 'Dead',
    'kein Kopf der Routine Dead');
  PlanOf(InImpl(['procedure Dead;', 'begin', 'end;']), 4,
    'Routine Dead is unused', R);
  Assert.IsTrue(Pos('fehlt in der Meldung', R) > 0, R);
end;

// ---- Charge H3c (Gegen-Review H3) ----

procedure TTestRdxRoutineFixes.Sca164_InterfaceInclude;
var
  P         : TRdxRoutinePlan;
  R, Dir, U : string;
  Incs      : TArray<string>;
begin
  // Pruefer-Fall (Minor 4): das Include im interface-Teil kann Foo
  // deklarieren - nach dem Loeschen E2065. Der Planer nennt es, der
  // Aufrufer liest es neben der Unit (IncludeReason).
  P := PlanOf(Join(['unit u;', 'interface', '{$I decls.inc}', 'implementation',
    '', 'procedure Foo;', 'begin', 'end;', '', 'procedure Bar;', 'begin',
    'end;', '', 'end.']), 6, Msg('Foo'), R);
  Assert.AreEqual('', R);
  Assert.AreEqual<Integer>(1, Integer(Length(P.Includes)), 'Includes');
  Assert.AreEqual('decls.inc', P.Includes[0]);
  Dir := TempDir;
  U := Dir + 'u.pas';
  try
    WriteText(Dir + 'decls.inc', 'procedure Foo;');
    R := TRdxRoutineFixes.IncludeReason(U, P.Includes, 'Foo');
    Assert.IsTrue(Pos('nennt Foo', R) > 0, R);
    // Verschachtelt: decls.inc bindet deeper.inc ein - fehlt es, keine
    // Hilfe; nennt keines Foo, Hilfe.
    WriteText(Dir + 'decls.inc', Join(['{$DEFINE FAST}', '{$I deeper.inc}']));
    R := TRdxRoutineFixes.IncludeReason(U, P.Includes, 'Foo');
    Assert.IsTrue(Pos('eingebunden von decls.inc', R) > 0, R);
    WriteText(Dir + 'deeper.inc', '{$R-}');
    Assert.AreEqual('', TRdxRoutineFixes.IncludeReason(U, P.Includes, 'Foo'));
    // Review Woche G05-03: ein UTF-8-Include OHNE BOM mit einem Namen mit
    // Umlaut. LoadFromFile las es als ANSI, der Name kam ein Zeichen
    // laenger an, und IncludeReason fand ihn nicht (gegen b2538e20 rot) -
    // die Hilfe loeschte die Implementierung, die Deklaration blieb.
    WriteUtf8NoBom(Dir + 'decls.inc', 'procedure Pr' + #$00FC + 'fe;'#13#10);
    R := TRdxRoutineFixes.IncludeReason(U, P.Includes, 'Pr' + #$00FC + 'fe');
    Assert.IsTrue(Pos('nennt Pr', R) > 0, R);
    // Nicht neben der Unit bzw. ohne Datei der Unit: keine Hilfe.
    DeleteFile(Dir + 'decls.inc');
    R := TRdxRoutineFixes.IncludeReason(U, P.Includes, 'Foo');
    Assert.IsTrue(Pos('nicht neben der Unit', R) > 0, R);
    R := TRdxRoutineFixes.IncludeReason('', P.Includes, 'Foo');
    Assert.IsTrue(Pos('unbekannt', R) > 0, R);
  finally
    DeleteFile(Dir + 'decls.inc');
    DeleteFile(Dir + 'deeper.inc');
    RemoveDir(Dir);
  end;
  // {$I %DATE%} (FPC) setzt einen String ein, keine Datei.
  SetLength(Incs, 1);
  Incs[0] := '%DATE%';
  Assert.AreEqual('', TRdxRoutineFixes.IncludeReason('', Incs, 'Foo'));
  // Im Kopf der Unit - vor interface bzw. vor uses - duerfen nur Direktiven
  // stehen: diese Includes muss niemand lesen (jcl.inc, CnWizards.inc).
  P := PlanOf(Join(['unit u;', '{$I jedi.inc}', 'interface', '{$I cfg.inc}',
    'uses Classes;', 'implementation', '', 'procedure Foo;', 'begin', 'end;',
    '', 'end.']), 8, Msg('Foo'), R);
  Assert.AreEqual('', R);
  Assert.AreEqual<Integer>(0, Integer(Length(P.Includes)), 'Kopf-Includes');
end;

procedure TTestRdxRoutineFixes.Sca164_FpcModifierBracket_NoHelp;
begin
  // Pruefer-Faelle (Minor 4): FPC-Direktiven in eckigen Klammern - per
  // alias bzw. public von aussen erreichbar.
  AssertRefused(InImpl(['procedure Foo; [public, alias: ''FOO_C''];', 'begin',
    'end;', '', 'procedure Bar;', 'begin', 'end;']), 4, 'Foo', 'public');
  AssertRefused(InImpl(['procedure Foo; [public];', 'begin', 'end;']), 4,
    'Foo', 'public');
  // Wort-Direktiven hinter der Klammer liest der Planer weiter.
  AssertRefused(InImpl(['procedure Foo; [cdecl]; export;', 'begin', 'end;']),
    4, 'Foo', 'export');
end;

procedure TTestRdxRoutineFixes.Sca164_MarkerAndHeadingStay;
begin
  // Pruefer-Faelle (Minor 3): ein Unterdrueck-Marker fuer die Datei ...
  Assert.AreEqual(InImpl(['', '// noinspection-file UnusedRoutine, LongMethod',
      'procedure Bar;', 'begin', 'end;']),
    FixOk(InImpl(['', '// noinspection-file UnusedRoutine, LongMethod',
      'procedure Foo;', 'begin', 'end;', '', 'procedure Bar;', 'begin',
      'end;']), 6, 'Foo'));
  // ... und Abschnittsueberschrift samt Absichtsmarker bleiben stehen.
  Assert.AreEqual(InImpl(['', '// ===== interne Hilfsroutinen =====',
      '// TODO: Bar beschleunigen', 'procedure Bar;', 'begin', 'end;']),
    FixOk(InImpl(['', '// ===== interne Hilfsroutinen =====',
      '// TODO: Bar beschleunigen', 'procedure Foo;', 'begin', 'end;', '',
      'procedure Bar;', 'begin', 'end;']), 7, 'Foo'));
  // Ein Kommentar ohne den Namen bleibt (Ueberschrift oder Beschreibung -
  // am Text nicht zu unterscheiden); einer, der ihn nennt, geht mit der
  // Doku darueber.
  Assert.AreEqual(InImpl(['procedure Keep;', 'begin', 'end;', '',
      '// default is case-sensitive', '/// <summary>Bar</summary>',
      '{ Bar: tut nichts }', 'procedure Bar;', 'begin', 'end;', '',
      'procedure Keep2;', 'begin', '  Keep;', 'end;']),
    FixOk(InImpl(['procedure Keep;', 'begin', 'end;', '',
      '// default is case-sensitive', 'procedure Foo;', 'begin', 'end;', '',
      '/// <summary>Bar</summary>', '{ Bar: tut nichts }', 'procedure Bar;',
      'begin', 'end;', '', 'procedure Keep2;', 'begin', '  Keep;', 'end;']), 9,
      'Foo'));
  Assert.AreEqual(InImpl(['procedure Keep;', 'begin', 'end;', '',
      '// default is case-sensitive', 'procedure Foo;', 'begin', 'end;', '',
      'procedure Keep2;', 'begin', '  Keep;', 'end;']),
    FixOk(InImpl(['procedure Keep;', 'begin', 'end;', '',
      '// default is case-sensitive', 'procedure Foo;', 'begin', 'end;', '',
      '/// <summary>Bar</summary>', '{ Bar: tut nichts }', 'procedure Bar;',
      'begin', 'end;', '', 'procedure Keep2;', 'begin', '  Keep;', 'end;']), 15,
      'Bar'));
end;

procedure TTestRdxRoutineFixes.Sca164_GlobalOperator_NoHelp;
begin
  // Minor 12: ein globaler FPC-Operator ist keine Methode einer Klasse.
  AssertRefused(InImpl(['operator explicit(A: TFoo): Integer;', 'begin',
    '  Result := 0;', 'end;']), 4, 'explicit', 'globaler Operator');
end;

procedure TTestRdxRoutineFixes.Sca164_UmlautCall_NoHelp;
var
  Lower, Upper : string;
begin
  // Pruefer-Fall (casesuni, Verdacht 1): der Aufruf in Grossschreibung mit
  // Umlaut ruft dieselbe Routine.
  Lower := 'Pr' + #$00FC + 'fe';
  Upper := 'PR' + #$00DC + 'FE';
  AssertRefused(InImpl(['procedure ' + Lower + ';', 'begin', 'end;', '',
    'procedure Bar;', 'begin', '  ' + Upper + ';', 'end;']), 4, Lower,
    'verwendet');
end;

// ---- Charge B1-FD (Code-Review reDelphix, R4; je gegen 4358b769 rot) ----

procedure TTestRdxRoutineFixes.Sca164_MarkerAround_NoHelp;
begin
  // R4-04, Pruefer-Fall r404 (3): der Marker hinter 'end;' gilt der Routine
  // dahinter (uSuppression.BuildMap) - mit der letzten Zeile geloescht,
  // erschiene ihr unterdrueckter Fund wieder.
  AssertRefused(InImpl(['procedure Helper;', 'begin',
    'end; // noinspection UnusedRoutine', 'procedure Other;', 'begin',
    'end;']), 4, 'Helper', 'Zeile 6 endet mit dem Kommentar "// noinspection');
  // Ein Absichtskommentar dort bleibt wie ueber dem Kopf stehen.
  AssertRefused(InImpl(['procedure Helper;', 'begin', 'end; // TODO: weg?',
    'procedure Other;', 'begin', 'end;']), 4, 'Helper', 'Zeile 6 endet');
  // forward-Deklaration: ihre letzte Zeile ebenso.
  AssertRefused(InImpl(['procedure Helper; forward; // noinspection X',
    'procedure Other;', 'begin', 'end;', 'procedure Helper;', 'begin',
    'end;']), 8, 'Helper', 'Zeile 4 endet');
  // '// noinspection-file' im Rumpf gilt der ganzen Datei.
  AssertRefused(InImpl(['procedure Helper;', 'begin',
    '  // noinspection-file DuplicateString', 'end;', 'procedure Other;',
    'begin', 'end;']), 4, 'Helper', 'noinspection-file" in Zeile 6');
  // Gegenproben: ein Kommentar ohne Marker hinter end geht mit; ein Marker
  // auf eigener Zeile im Rumpf zielt in den Rumpf.
  Assert.AreEqual(InImpl(['procedure Other;', 'begin', 'end;']),
    FixOk(InImpl(['procedure Helper;', 'begin', 'end; // Helper',
      'procedure Other;', 'begin', 'end;']), 4, 'Helper'));
  Assert.AreEqual(InImpl(['procedure Other;', 'begin', 'end;']),
    FixOk(InImpl(['procedure Helper;', 'begin', '  // noinspection X',
      '  Foo;', 'end;', 'procedure Other;', 'begin', 'end;']), 4, 'Helper'));
  // Nachpruefung B1-FD, neu 1: ein Marker ueber dem Kopf zielt auf die
  // Routine (uSuppression.BuildMap: die naechste Code-Zeile); TopAbove
  // laesst ihn stehen, und geloescht galt er still der Routine dahinter -
  // auf eigener Zeile, hinter einer Leerzeile, hinter dem 'end;' davor und
  // ueber der forward-Deklaration.
  AssertRefused(InImpl(['// noinspection CyclomaticComplexity',
    'procedure Helper;', 'begin', 'end;', 'procedure Other;', 'begin',
    'end;']), 5, 'Helper', 'in Zeile 4 zielt');
  AssertRefused(InImpl(['// noinspection X', '', 'procedure Helper;', 'begin',
    'end;', 'procedure Other;', 'begin', 'end;']), 6, 'Helper',
    'in Zeile 4 zielt');
  AssertRefused(InImpl(['procedure Keep;', 'begin',
    'end; // noinspection EmptyMethod', 'procedure Helper;', 'begin', 'end;',
    'procedure Other;', 'begin', '  Keep;', 'end;']), 7, 'Helper',
    'in Zeile 6 zielt');
  AssertRefused(InImpl(['// noinspection X', 'procedure Helper; forward;',
    'procedure Other;', 'begin', 'end;', 'procedure Helper;', 'begin',
    'end;']), 9, 'Helper', 'in Zeile 4 zielt');
  // Gegenprobe: der Marker ueber einer anderen Routine zielt weiter auf sie.
  Assert.AreEqual(InImpl(['// noinspection X', 'procedure Keep;', 'begin',
      'end;']),
    FixOk(InImpl(['// noinspection X', 'procedure Keep;', 'begin', 'end;', '',
      'procedure Helper;', 'begin', 'end;']), 9, 'Helper'));
end;

procedure TTestRdxRoutineFixes.Sca164_IncludeOnNetworkPath_NoDiskAccess;
var
  Unc, Dir, R : string;
  T0          : TDateTime;
  Ms          : Integer;
  Incs        : TArray<string>;
begin
  // R4-03, Pruefer-Fall vunc: Include auf einem Netzpfad in einer lokalen
  // Unit bzw. eine Unit auf einem Netzpfad - IncludeReason fragte FileExists
  // dort (9 bis 16 s im Hauptthread je Menueaufbau, SCA164 hatte gar keine
  // Netzpfad-Pruefung). Jetzt kommt der Grund ohne Plattenzugriff. Pfade aus
  // Teilen (ein Literal waere ein SCA016-Fund im Selbstscan).
  Unc := PathDelim + PathDelim + 'rdx-b1fd-gibt-es-nicht' + PathDelim + 'share'
    + PathDelim;
  Dir := TempDir;
  try
    SetLength(Incs, 1);
    Incs[0] := Unc + 'defs.inc';
    T0 := Now;
    R := TRdxRoutineFixes.IncludeReason(Dir + 'u.pas', Incs, 'Helper');
    Ms := Round((Now - T0) * MSecsPerDay);
    Assert.IsTrue(Pos('auf einem Netzpfad', R) > 0, R);
    Assert.IsTrue(Ms < 2000, Format('Include: %d ms', [Ms]));
    Incs[0] := 'defs.inc';
    T0 := Now;
    R := TRdxRoutineFixes.IncludeReason(Unc + 'src' + PathDelim + 'u.pas', Incs,
      'Helper');
    Ms := Round((Now - T0) * MSecsPerDay);
    Assert.IsTrue(Pos('auf einem Netzpfad', R) > 0, R);
    Assert.IsTrue(Ms < 2000, Format('Unit: %d ms', [Ms]));
  finally
    RemoveDir(Dir);
  end;
  // Die Regel: UNC mit beiden Trennern, ein lokales Laufwerk und ein
  // relativer Pfad sind kein Netzpfad.
  Assert.IsTrue(IsNetworkPath(Unc + 'x.inc'), 'UNC');
  Assert.IsTrue(IsNetworkPath(StringReplace(Unc, PathDelim, '/',
    [rfReplaceAll]) + 'x.inc'), 'UNC mit /');
  Assert.IsFalse(IsNetworkPath(Dir + 'u.pas'), 'TEMP ist lokal');
  Assert.IsFalse(IsNetworkPath('defs.inc'), 'relativ');
  // Nachpruefung B1-FD, neu 5: '{$I \x.inc}' liegt ab der Wurzel des
  // Laufwerks der Unit - FileExists suchte es vorher auf dem aktuellen
  // Laufwerk des Prozesses (in der IDE irgendeinem, auch einem
  // Netzlaufwerk, an dem IsNetworkPath vorbeisah). Ohne Laufwerk im
  // Verzeichnis wird nicht gesucht; relativ und absolut wie bisher.
  Assert.AreEqual(ExtractFileDrive(Dir) + PathDelim + 'x.inc',
    IncludeSearchPath(Dir, PathDelim + 'x.inc'), 'ab der Wurzel');
  Assert.AreEqual(ExtractFileDrive(Dir) + '/x.inc',
    IncludeSearchPath(Dir, '/x.inc'), 'ab der Wurzel mit /');
  Assert.AreEqual(Unc + 'x.inc',
    IncludeSearchPath(Unc + 'src' + PathDelim, PathDelim + 'x.inc'), 'UNC');
  Assert.AreEqual('', IncludeSearchPath('src' + PathDelim,
    PathDelim + 'x.inc'), 'ohne Laufwerk');
  Assert.AreEqual(Dir + 'x.inc', IncludeSearchPath(Dir, 'x.inc'), 'relativ');
  Assert.AreEqual(Dir + 'y.inc', IncludeSearchPath(Unc, Dir + 'y.inc'),
    'absolut');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxRoutineFixes);

end.
