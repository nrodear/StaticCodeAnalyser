unit uTestRdxBlocks;

// Charge B2S-b (Code-Review reDelphix, R5-03/R5-07): die Bausteine in
// uRdxBlocks, die die Charge neu oeffentlich macht oder neu baut, und die
// Politik der beiden Suchen "innerste Routine um eine Stelle", die jetzt
// auf TRdxBlocks.HeadBefore laufen:
//   HeadBefore: Koepfe rueckwaerts (die lokale Routine vor der aeusseren),
//          ein Wort aus AStops beendet, ein unsicherer Kopf kommt mit
//          seinem Grund, am Dateianfang False.
//   Politik uRdxHandOver.RoutineAround (SCA009, Weitergabe an eine lokale
//          Variable: ein unsicherer Kopf wird uebergangen, die Suche geht
//          davor weiter) und uRdxResultFixes.EnclosingRoutine (SCA196: der
//          ERSTE unsichere Kopf beendet mit seinem Grund und seiner Zeile) -
//          beide wie vor der Charge. Die Politik von SCA009 trennt erst ein
//          unsicherer Kopf IM Rumpf der gesuchten Routine ('Operator.Reset',
//          TryPolicy_UnsafeHeadSkipped; Gegenpruefung V-B2S-1: gegen
//          die Mutante "der erste unsichere Kopf beendet" rot). Ein Kopf
//          AUF der Fundzeile zaehlt fuer SCA196 mit - die Suche beginnt
//          hinter dem Ende der Zeile (ResultPolicy_HeadOnFindingLine;
//          Gegenpruefung V2-B2S-1: gegen die Mutante "Suche ab dem Anfang
//          der Zeile" rot).
//   MemberHeads und der Index der Klassenkoepfe in uRdxResultFixes (R5-07):
//          zwei Koepfe einer Klasse in $IFDEF-Zweigen aus dem Index
//          (Delegation SCA096); ein generischer Kopf, den der Index nicht
//          lesen kann ('TBase<T(X)>'), fragt wie bisher FindMethodDecls -
//          ohne diesen Rueckfall sah SCA096 den abstrakten Konstruktor
//          nicht (gegen die Charge ohne GenericMiss rot).
//   TypeHasBody: die eine Probe (bis Charge B2S-b drei Kopien).
//   Review Woche: 'Operator := ..' ist kein Routinenkopf (G05-07, weder im
//          Rumpf fuer ReadRoutine noch fuer HeadBefore); HeadBefore an einem
//          'class procedure'-Kopf liefert das Kopfwort, die Grenzen ab
//          'class' (G05-25).
// Laeuft in reDelphix.Test UND im FPC-Pruefstand.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxBlocks = class
  public
    [Test] procedure HeadBefore_LocalHeadFirst;
    [Test] procedure HeadBefore_StopWordAndFileStart;
    [Test] procedure HeadBefore_UnsafeHeadReason;
    [Test] procedure TryPolicy_LocalVarAroundUnsafeLocalRoutine;
    [Test] procedure TryPolicy_UnsafeHeadSkipped;
    [Test] procedure ResultPolicy_FirstUnsafeHeadEnds;
    [Test] procedure ResultPolicy_HeadOnFindingLine;
    [Test] procedure MemberHeads_DepthOneOfOneClass;
    [Test] procedure Sca096_TwoClassHeadsFromIndex;
    [Test] procedure Sca096_GenericMissFallsBack;
    [Test] procedure TypeHasBody_Forms;
    // Review Woche.
    [Test] procedure Body_OperatorAssignIsNoHead;
    [Test] procedure HeadBefore_ClassProcedureHead;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxCodeMap, uRdxBlocks, uRdxTryFixes, uRdxResultFixes, uRdxInheritedFixes,
  uTestRdxTextKit;   // Join, LineStartingWith

const
  MSG_CTOR = 'Constructor has no `inherited` call - parent class is not '
    + 'initialized. Add `inherited Create(...)` or `inherited;` (use // '
    + 'noinspection if intentional).';
  MSG_196 = 'Function F reads Result before assigning it (Result appears '
    + 'on the right-hand side of its own first assignment) - for return type '
    + 'string, Result is a hidden var parameter aliasing the caller''s '
    + 'target variable and starts with its OLD content, not empty. '
    + 'Initialize Result first (e.g. Result := nil / Result := [] / Result '
    + ':= '''')';

// ---- Helfer ----

// Join und LineStartingWith kommen aus uTestRdxTextKit (Review R6-08; bis
// zum Merge der Charge B2T hier je eine Kopie - das lokale LineOf hatte den
// Vertrag von LineStartingWith, NICHT den von uTestRdxTextKit.LineOf).

// Das erste Token AWord (klein) auf der Zeile ALine; Low = '' ohne.
function TokOn(AMap: TRdxCodeMap; ALine: Integer; const AWord: string): TRdxToken;
begin
  Result := NextToken(AMap, ALine, 1);
  while (Result.Low <> '') and (Result.Line = ALine) and (Result.Low <> AWord) do
    Result := After(AMap, Result);
  if (Result.Line <> ALine) or (Result.Low <> AWord) then
    Result := Default(TRdxToken);
end;

// Eine Routine P mit der lokalen Routine Inner (ALocal: ihr
// Deklarationsteil) und dem Rumpf 'Run;' - fuer HeadBefore.
function WithLocal(const ALocal: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'implementation',
    'procedure Outer;', '  procedure Inner;']) + #13#10 + Join(ALocal)
    + #13#10 + Join(['  begin', '  end;', 'begin', '  Run;', 'end;', '',
    'initialization', '  Init;', 'end.']);
end;

// SCA009 fuer X auf der Zeile mit 'X := TFoo.Create': '' (Hilfe) oder der
// Grund.
function TryReason(const ASource: string): string;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  P   : TRdxTryPlan;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    TRdxTryFixes.MissingFinally(Map, LineStartingWith(ASource, 'X := TFoo.Create'),
      'X', P, Result);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Ein Planer aus uRdxResultFixes fuer AMessage auf ALine: '' oder der
// Grund.
function ResultReason(APlanner: TRdxResultPlanner; const ASource: string;
  ALine: Integer; const AMessage: string): string;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  P   : TRdxResultPlan;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    APlanner(Map, ALine, AMessage, P, Result);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Eine Unit mit den Typen ATypes (interface) und den Zeilen AImpl.
function InUnit(const ATypes, AImpl: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'type']) + #13#10 + Join(ATypes)
    + #13#10 + 'implementation' + #13#10 + Join(AImpl) + #13#10 + 'end.';
end;

// ---- HeadBefore ----

// Rueckwaerts aus dem Rumpf von Outer kommt zuerst der Kopf der lokalen
// Routine Inner (ihr Rumpf enthaelt die Stelle nicht), dann Outer - beide
// mit Grenzen.
procedure TTestRdxBlocks.HeadBefore_LocalHeadFirst;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  T   : TRdxToken;
  S   : TRdxHeadStep;
  Src : string;
begin
  Src := WithLocal(['    var I: Integer;']);
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := Src;
    Map := TRdxCodeMap.Create(SL);
    T := TokOn(Map, LineStartingWith(Src, 'Run;'), 'run');
    Assert.IsTrue(TRdxBlocks.HeadBefore(Map, T, [], S), 'erster Kopf');
    Assert.AreEqual('', S.Reason, 'Inner lesbar');
    Assert.AreEqual('Inner', S.Routine.Name);
    Assert.IsFalse(S.Stop);
    Assert.IsTrue(TRdxBlocks.HeadBefore(Map, T, [], S), 'zweiter Kopf');
    Assert.AreEqual('Outer', S.Routine.Name);
    Assert.AreEqual<Integer>(LineStartingWith(Src, 'procedure Outer;'), S.Tok.Line);
    Assert.IsTrue(TokBefore(S.Routine.Body, TokOn(Map, LineStartingWith(Src, 'Run;'),
      'run')), 'Rumpf von Outer vor Run');
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Aus dem initialization-Teil: mit dem Abschnittswort in AStops endet die
// Suche dort (Stop), ohne geht sie zu den Routinen davor (Inner, dann
// Outer); vor dem ersten Token gibt es nichts mehr.
procedure TTestRdxBlocks.HeadBefore_StopWordAndFileStart;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  T   : TRdxToken;
  S   : TRdxHeadStep;
  Src : string;
begin
  Src := WithLocal(['    var I: Integer;']);
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := Src;
    Map := TRdxCodeMap.Create(SL);
    T := TokOn(Map, LineStartingWith(Src, 'Init;'), 'init');
    Assert.IsTrue(TRdxBlocks.HeadBefore(Map, T, ['initialization'], S));
    Assert.IsTrue(S.Stop, 'Abschnittswort beendet');
    Assert.AreEqual('initialization', S.Tok.Low);
    T := TokOn(Map, LineStartingWith(Src, 'Init;'), 'init');
    Assert.IsTrue(TRdxBlocks.HeadBefore(Map, T, [], S));
    Assert.IsFalse(S.Stop, 'ohne AStops weiter');
    // Rueckwaerts kommt der spaetere Kopf zuerst: Inner steht hinter Outer.
    Assert.AreEqual('Inner', S.Routine.Name);
    Assert.IsTrue(TRdxBlocks.HeadBefore(Map, T, [], S));
    Assert.AreEqual('Outer', S.Routine.Name);
    T := NextToken(Map, 1, 1);
    Assert.IsFalse(TRdxBlocks.HeadBefore(Map, T, [], S), 'Dateianfang');
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Ein lokaler Klassentyp macht die Grenzen von Inner unsicher - und damit
// auch die von Outer (ReadRoutine liest Inner mit): beide Koepfe kommen mit
// Grund.
procedure TTestRdxBlocks.HeadBefore_UnsafeHeadReason;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  T   : TRdxToken;
  S   : TRdxHeadStep;
  Src : string;
begin
  Src := WithLocal(['    type TLoc = class end;']);
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := Src;
    Map := TRdxCodeMap.Create(SL);
    T := TokOn(Map, LineStartingWith(Src, 'Run;'), 'run');
    Assert.IsTrue(TRdxBlocks.HeadBefore(Map, T, [], S));
    Assert.IsTrue(Pos('lokaler Klassen', S.Reason) > 0, S.Reason);
    Assert.AreEqual<Integer>(LineStartingWith(Src, 'procedure Inner;'), S.Tok.Line);
    Assert.IsTrue(TRdxBlocks.HeadBefore(Map, T, [], S));
    Assert.IsTrue(Pos('lokale Routine Inner', S.Reason) > 0, S.Reason);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// ---- Die Politik der Aufrufer ----

// SCA009 (RoutineAround): X an eine lokale Variable Y der Routine ist kein
// Halter - angeboten, auch mit einer lokalen Routine davor (ihr Kopf kommt
// rueckwaerts zuerst, ihr Rumpf enthaelt X nicht). Ist deren Grenze
// unsicher (lokaler Klassentyp), ist es auch die von P (ReadRoutine liest
// Inner mit): keine Routine mit sicheren Grenzen um X, Y gilt nicht als
// lokal, keine Hilfe - wie vor der Charge. Beide Faelle gelten unter jeder
// Politik fuer unsichere Koepfe (uebergehen oder beenden); die Politik von
// RoutineAround pinnt TryPolicy_UnsafeHeadSkipped.
procedure TTestRdxBlocks.TryPolicy_LocalVarAroundUnsafeLocalRoutine;
var
  Ok, Unsafe : string;
begin
  Ok := Join(['unit u;', 'interface', 'implementation', 'procedure P;',
    '  procedure Inner;', '  begin', '  end;', 'var', '  Y: TFoo;', 'begin',
    '  X := TFoo.Create;', '  Y := X;', '  Y.Run;', '  X.Free;', 'end;',
    'end.']);
  Assert.AreEqual('', TryReason(Ok), 'lokale Variable mit lokaler Routine');
  Unsafe := StringReplace(Ok, '  procedure Inner;',
    '  procedure Inner;' + #13#10 + '    type TLoc = class end;', []);
  Assert.IsTrue(Pos('kein lokaler Name', TryReason(Unsafe)) > 0,
    TryReason(Unsafe));
end;

// SCA009 (RoutineAround: ein unsicherer Kopf wird uebergangen, die Suche
// geht davor weiter): 'Operator.Reset' im Rumpf von P. 'operator' steht in
// ROUTINE_WORDS, ist aber kein reserviertes Wort - HeadBefore haelt den
// Zugriff fuer einen Kopf, dessen Grenzen ReadRoutine nicht liest (der
// erste Schritt rueckwaerts von X kommt mit Grund; die Vorbedingung prueft
// der Test mit). RoutineAround geht davor weiter zu P: Y ist lokal, die
// Hilfe bleibt - wie vor der Charge. Beendete der erste unsichere Kopf die
// Suche (die Politik von SCA196), fehlte die Routine um X, und SCA009
// lehnte mit 'kein lokaler Name' ab (Gegenpruefung V-B2S-1: mit dieser
// Mutante rot, ohne sie gruen). Bestand: SCA196 (EnclosingRoutine) endet
// an demselben Pseudo-Kopf mit dessen Grund - dort gewollt, lieber keine
// Hilfe als die falsche Routine. Bis Review Woche G05-07 stand hier
// 'Operator := ..' - die Zuweisung ist seitdem kein Kopf mehr
// (Body_OperatorAssignIsNoHead); der Zugriff '.Reset' bleibt einer.
procedure TTestRdxBlocks.TryPolicy_UnsafeHeadSkipped;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  T   : TRdxToken;
  S   : TRdxHeadStep;
  Src : string;
begin
  Src := Join(['unit u;', 'interface', 'implementation', 'procedure P;',
    'var', '  Y: TFoo;', 'begin', '  Operator.Reset;',
    '  X := TFoo.Create;', '  Y := X;', '  Y.Run;', '  X.Free;', 'end;',
    'end.']);
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := Src;
    Map := TRdxCodeMap.Create(SL);
    T := TokOn(Map, LineStartingWith(Src, 'X := TFoo.Create'), 'x');
    Assert.IsTrue(TRdxBlocks.HeadBefore(Map, T, [], S), 'ein Kopf vor X');
    Assert.AreEqual('operator', S.Tok.Low, 'zuerst der Pseudo-Kopf');
    Assert.IsTrue(S.Reason <> '', 'seine Grenzen sind nicht sicher');
  finally
    Map.Free;
    SL.Free;
  end;
  Assert.AreEqual('', TryReason(Src), 'Y ist lokal in P');
end;

// SCA196 (EnclosingRoutine: der ERSTE unsichere Kopf von der Lese-Zeile
// aufwaerts beendet die Suche): Grund und Zeile sind die der lokalen
// Routine Inner, nicht die von F.
procedure TTestRdxBlocks.ResultPolicy_FirstUnsafeHeadEnds;
var
  Src, R : string;
begin
  Src := Join(['unit u;', 'interface', 'implementation',
    'function F: string;', '  procedure Inner;', '    type TLoc = class end;',
    '  begin', '  end;', 'begin', '  Result := Result + ''x'';', 'end;',
    'end.']);
  R := ResultReason(TRdxResultFixes.ManagedResultInit, Src,
    LineStartingWith(Src, 'Result := Result'), MSG_196);
  Assert.IsTrue(Pos(Format('Routine in Zeile %d: lokaler Klassen',
    [LineStartingWith(Src, 'procedure Inner;')]), R) = 1, R);
end;

// SCA196 an einer Funktion in EINER Zeile: Kopf und Lesen von Result
// stehen auf der Fundzeile. EnclosingRoutine sucht seit Charge B2S-b mit
// HeadBefore ab dem Anfang der Zeile DAHINTER (R5-03) - so kommt der Kopf
// auf der Fundzeile mit wie bis dahin in der Schleife ueber
// HeadsOnLine(ALine): Hilfe. Begaenne die Suche am Anfang der Fundzeile,
// fehlte F ('keine Routine um die gemeldete Zeile'; Gegenpruefung
// V2-B2S-1: mit dieser Mutante rot, auf HEAD und vor der Charge gruen).
procedure TTestRdxBlocks.ResultPolicy_HeadOnFindingLine;
var
  Src, R : string;
begin
  Src := Join(['unit u;', 'interface', 'implementation',
    'function F: string; begin Result := Result + ''x''; end;', 'end.']);
  R := ResultReason(TRdxResultFixes.ManagedResultInit, Src,
    LineStartingWith(Src, 'function F:'), MSG_196);
  Assert.AreEqual('', R, 'Hilfe fuer F auf der Fundzeile');
end;

// ---- Klassenkoepfe (R5-07) ----

// MemberHeads: die Koepfe der Methode auf Tiefe 1 EINES Klassenrumpfs -
// beide Overloads, nicht die gleichnamige Methode der geschachtelten Klasse;
// FindMethodDecls ueber alle Koepfe der Klasse liefert dasselbe.
procedure TTestRdxBlocks.MemberHeads_DepthOneOfOneClass;
var
  SL      : TStringList;
  Map     : TRdxCodeMap;
  Heads   : TArray<TRdxToken>;
  Members : TArray<TRdxToken>;
  Src     : string;
begin
  Src := InUnit(['  TFoo = class', '  type', '    TInner = class',
    '      procedure Run;', '    end;', '  public', '    procedure Run; overload;',
    '    procedure Run(A: Integer); overload;', '  end;'], []);
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := Src;
    Map := TRdxCodeMap.Create(SL);
    Heads := TRdxBlocks.FindClassHeads(Map, 'TFoo');
    Assert.AreEqual<Integer>(1, Integer(Length(Heads)), 'ein Kopf');
    Members := TRdxBlocks.MemberHeads(Map, Heads[0], 'Run');
    Assert.AreEqual<Integer>(2, Integer(Length(Members)), 'zwei Overloads');
    Assert.AreEqual<Integer>(LineStartingWith(Src, 'procedure Run; overload;'),
      Members[0].Line);
    Assert.AreEqual<Integer>(2, Integer(Length(TRdxBlocks.FindMethodDecls(Map,
      'TFoo', 'Run'))), 'FindMethodDecls gleich');
  finally
    Map.Free;
    SL.Free;
  end;
end;

// SCA096: TBase steht zweimal in der Unit ($IFDEF-Zweige), nur der erste
// deklariert 'constructor Init'. Die Koepfe beider Zweige kommen aus dem
// Index (MethodDecls je Kopf MemberHeads): der Aufruf 'Init;' ist eine
// Delegation, keine Hilfe.
procedure TTestRdxBlocks.Sca096_TwoClassHeadsFromIndex;
var
  Src, R : string;
begin
  Src := InUnit(['  {$IFDEF OLD}', '  TBase = class', '    constructor Init;',
    '  end;', '  {$ELSE}', '  TBase = class', '    procedure Run;', '  end;',
    '  {$ENDIF}', '  TFoo = class(TBase)', '    constructor Create; override;',
    '  end;'], ['constructor TFoo.Create;', 'begin', '  Init;', 'end;']);
  R := ResultReason(TRdxInheritedFixes.ConstructorInherited, Src,
    LineStartingWith(Src, 'constructor TFoo.Create;'), MSG_CTOR);
  Assert.IsTrue(Pos('Aufruf Init in Zeile', R) = 1, R);
  Assert.IsTrue(Pos('(Delegation)', R) > 0, R);
end;

// SCA096: im ersten Zweig ist TBase generisch mit einem Token in den
// Typparametern, das der Index nicht liest ('TBase<T(X)>' - Codevorlagen
// wie 'T<#Name>' im Korpus): dort fragt MethodDecls wie bisher
// FindMethodDecls und sieht den abstrakten Konstruktor - keine Hilfe.
// Nur ueber den Index (ohne Rueckfall) haette SCA096 ihn angeboten.
procedure TTestRdxBlocks.Sca096_GenericMissFallsBack;
var
  Src, R : string;
begin
  Src := InUnit(['  {$IFDEF OLD}', '  TBase<T(X)> = class',
    '    constructor Create; virtual; abstract;', '  end;', '  {$ELSE}',
    '  TBase = class', '    constructor Create; virtual;', '  end;',
    '  {$ENDIF}', '  TFoo = class(TBase)', '    constructor Create; override;',
    '  end;'], ['constructor TFoo.Create;', 'begin', '  Run;', 'end;']);
  R := ResultReason(TRdxInheritedFixes.ConstructorInherited, Src,
    LineStartingWith(Src, 'constructor TFoo.Create;'), MSG_CTOR);
  Assert.IsTrue(Pos('TBase.Create ist abstrakt', R) = 1, R);
end;

// ---- TypeHasBody ----

// Rumpf mit end: 'class', 'class abstract(TBase)', 'class sealed'; keiner:
// Vorwaerts 'class;', Metaklasse 'class of', Kurzform 'class(TBase);'.
procedure TTestRdxBlocks.TypeHasBody_Forms;
var
  SL   : TStringList;
  Map  : TRdxCodeMap;
  Src  : string;
  i    : Integer;
  Kind : TRdxToken;
const
  FORMS: array[0..5] of string = ('TA = class Run; end;',
    'TB = class abstract(TBase) Run; end;', 'TC = class sealed Run; end;',
    'TD = class;', 'TE = class of TFoo;', 'TF = class(TBase);');
  BODY: array[0..5] of Boolean = (True, True, True, False, False, False);
begin
  Src := InUnit(FORMS, []);
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := Src;
    Map := TRdxCodeMap.Create(SL);
    for i := 0 to High(FORMS) do
    begin
      Kind := TokOn(Map, LineStartingWith(Src, FORMS[i]), 'class');
      // Vorbedingung (Review Woche G05-25): mit leerem Token liefert
      // TypeHasBody True, die True-Faelle gingen sonst leer gruen.
      Assert.AreEqual('class', Kind.Low, FORMS[i] + ': Token class');
      Assert.IsTrue(TypeHasBody(Map, Kind) = BODY[i], FORMS[i]);
    end;
  finally
    Map.Free;
    SL.Free;
  end;
end;

// ---- Review Woche ----

// G05-07: 'Operator' ist kein reserviertes Wort - die Zuweisung
// 'Operator := ..' hinter ';' hielt BodyHook fuer einen Routinenkopf im
// Rumpf (ReadRoutine sperrte P fuer alle Bausteine: SCA053, SCA164, SCA009
// ...), HeadBefore fuer den ersten Kopf vor Foo. Beides gegen b2538e20 rot.
// FPC kennt den Kopf 'operator := (A: T) R: U;' - vor '(' bleibt es einer.
procedure TTestRdxBlocks.Body_OperatorAssignIsNoHead;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  T   : TRdxToken;
  S   : TRdxHeadStep;
  R   : TRdxRoutine;
  Src : string;
begin
  Src := Join(['unit u;', 'interface', 'implementation', 'procedure P;',
    'begin', '  X := 1;', '  Operator := ''+'';', '  Foo;', 'end;', 'end.']);
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := Src;
    Map := TRdxCodeMap.Create(SL);
    Assert.AreEqual('', TRdxBlocks.ReadRoutine(Map,
      TokOn(Map, LineStartingWith(Src, 'procedure P;'), 'procedure'), R),
      'die Zuweisung ist kein Kopf im Rumpf');
    Assert.AreEqual<Integer>(LineStartingWith(Src, 'end;'), R.EndTok.Line);
    T := TokOn(Map, LineStartingWith(Src, 'Foo;'), 'foo');
    Assert.IsTrue(TRdxBlocks.HeadBefore(Map, T, [], S), 'ein Kopf vor Foo');
    Assert.AreEqual('procedure', S.Tok.Low, 'P, nicht die Zuweisung');
    Assert.AreEqual('', S.Reason);
  finally
    Map.Free;
    SL.Free;
  end;
  Src := Join(['unit u;', 'interface', 'implementation', 'procedure P;',
    'begin', '  X := 1;', '  Operator := (A + B);', 'end;', 'end.']);
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := Src;
    Map := TRdxCodeMap.Create(SL);
    Assert.IsTrue(Pos('Routinenkopf im Rumpf', TRdxBlocks.ReadRoutine(Map,
      TokOn(Map, LineStartingWith(Src, 'procedure P;'), 'procedure'), R)) > 0,
      'vor "(" bleibt es ein Kopf (FPC-Zuweisungsoperator)');
  finally
    Map.Free;
    SL.Free;
  end;
end;

// G05-25: HeadBefore an einem 'class procedure'-Kopf: Tok ist das Kopfwort
// (die Pruefung IsRoutineHeadAfter sieht 'class' davor), die Grenzen
// beginnen bei 'class' (ReadRoutine zieht den Kopf darauf).
procedure TTestRdxBlocks.HeadBefore_ClassProcedureHead;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  T   : TRdxToken;
  S   : TRdxHeadStep;
  Src : string;
begin
  Src := InUnit(['  TFoo = class', '    class procedure Run;', '  end;'],
    ['class procedure TFoo.Run;', 'begin', '  Go;', 'end;']);
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := Src;
    Map := TRdxCodeMap.Create(SL);
    T := TokOn(Map, LineStartingWith(Src, 'Go;'), 'go');
    Assert.IsTrue(TRdxBlocks.HeadBefore(Map, T, [], S));
    Assert.AreEqual('', S.Reason);
    Assert.AreEqual('procedure', S.Tok.Low, 'Tok: das Kopfwort');
    Assert.AreEqual('class', S.Routine.Head.Low, 'Grenzen ab class');
    Assert.AreEqual('TFoo.Run', S.Routine.Name);
    Assert.AreEqual<Integer>(LineStartingWith(Src, 'class procedure TFoo.Run;'),
      S.Tok.Line);
  finally
    Map.Free;
    SL.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxBlocks);

end.
