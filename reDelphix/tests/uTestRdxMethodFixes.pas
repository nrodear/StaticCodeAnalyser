unit uTestRdxMethodFixes;

// Ungenutzte private Methode loeschen (uRdxRoutineFixes, Charge H3b,
// SCA147) auf Text - ohne Parser, ohne Detektor (laeuft in reDelphix.Test
// UND im FPC-Pruefstand):
//   Deklaration samt '///'-Doku und Implementierung samt Kommentar darueber
//   und Leerzeile (ein Gruppenkommentar im Klassenrumpf bleibt);
//   strict private, generische und verschachtelte Klasse, class-Methode,
//   lokales Interface der Klasse; Sperren: Abschnitt nicht private,
//   virtual/override/message/overload, Konstruktor, Aufruf, Property-
//   Accessor, Name als String-Literal, {$RTTI}, Attribut an Methode und
//   Klasse, keine Implementierung, {$I} im implementation-Teil, Interface
//   aus einer anderen Unit, verschobene Meldung; die Formdatei-Pruefung.
//   Charge H3c (Gegen-Review H3, Pruefer-Fixtures rc/cases147.txt,
//   casesuni.txt): Interface als erster Eintrag 'class(IFremd)', fremder
//   Vorfahr eines lokalen Interfaces, IInterface-Member als Name, lokale
//   Kette bis IInterface (Hilfe); Kommentar ueber der Implementierung ohne
//   den Namen bleibt; Aufruf in anderer Umlaut-Schreibung.
//   Charge B1-FD (Code-Review reDelphix, R4, Pruefer-Fixture rc/r405.txt):
//   ein Include vor implementation steht im Plan und wird gelesen (R4-05,
//   Property-Accessor einer Nachfahrenklasse im Include); Marker hinter der
//   Deklaration bzw. dem end der Implementierung sperren (R4-04).
// Die Gegenprobe mit dem echten Detektor steht in
// uTestRdxRoutineFixesDetector (nur Delphi).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxMethodFixes = class
  public
    [Test] procedure Sca147_DeclAndImpl;
    [Test] procedure Sca147_StrictGenericClassMethod;
    [Test] procedure Sca147_NestedClass;
    [Test] procedure Sca147_LocalInterface;
    [Test] procedure Sca147_Section_NoHelp;
    [Test] procedure Sca147_Dispatch_NoHelp;
    [Test] procedure Sca147_Used_NoHelp;
    [Test] procedure Sca147_Rtti_NoHelp;
    [Test] procedure Sca147_NoImpl_NoHelp;
    [Test] procedure Sca147_ForeignInterface_NoHelp;
    [Test] procedure Sca147_Moved_NoHelp;
    [Test] procedure Sca147_FormNamesMethod;
    [Test] procedure Sca147_FirstEntryInterface_NoHelp;
    [Test] procedure Sca147_InterfaceAncestors;
    [Test] procedure Sca147_CommentAboveImpl;
    [Test] procedure Sca147_UmlautCall_NoHelp;
    [Test] procedure Sca147_IncludeBeforeImplementation_Read;
    [Test] procedure Sca147_TrailingMarker_NoHelp;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxBufferMath, uRdxCodeMap, uRdxRoutineFixes;

// ---- Helfer ----

function Msg(const AClass, AMethod: string): string;
begin
  Result := 'Private method ' + AClass + '.' + AMethod
    + ' appears unused (no call within the unit)';
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

// Eine Unit: ADecl im interface-Teil (ab Zeile 4, hinter 'type'), AImpl
// im implementation-Teil.
function UnitOf(const ADecl, AImpl: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'type']) + #13#10 + Join(ADecl)
    + #13#10'implementation'#13#10 + Join(AImpl) + #13#10'end.';
end;

// Wie UnitOf, aber ohne Zeilen im implementation-Teil.
function Bare(const ADecl: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'type']) + #13#10 + Join(ADecl)
    + #13#10'implementation'#13#10'end.';
end;

function Apply(const ASource: string; const AEdits: TArray<TRdxEdit>): string;
var
  Bytes : TBytes;
  Plan  : TArray<TRdxByteEdit>;
  Err   : string;
begin
  Bytes := TEncoding.UTF8.GetBytes(ASource);
  Assert.IsTrue(PlanByteEdits(Bytes, AEdits, Plan, Err), Err);
  Result := TEncoding.UTF8.GetString(ApplyByteEdits(Bytes, Plan));
end;

// Neuer Text oder '' bei Ablehnung (AReason).
function Fix(const ASource: string; ALine: Integer; const AMessage: string;
  out AReason: string): string;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  P   : TRdxRoutinePlan;
begin
  Result := '';
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    TRdxRoutineFixes.UnusedPrivateMethod(Map, ALine, AMessage, P, AReason);
  finally
    Map.Free;
    SL.Free;
  end;
  if AReason = '' then
    Result := Apply(ASource, P.Edits);
end;

function FixOk(const ASource: string; ALine: Integer;
  const AClass, AMethod: string): string;
var
  R : string;
begin
  Result := Fix(ASource, ALine, Msg(AClass, AMethod), R);
  Assert.AreEqual('', R, 'Grund');
end;

procedure AssertRefused(const ASource: string; ALine: Integer;
  const AClass, AMethod, APart: string);
var
  R : string;
begin
  Assert.AreEqual('', Fix(ASource, ALine, Msg(AClass, AMethod), R),
    'keine Hilfe');
  Assert.IsTrue(Pos(APart, R) > 0, R);
end;

// TFoo mit privatem Dead (Zeile 7) und Run, das nur Used ruft; AExtra
// steht im private-Abschnitt hinter Dead, ABody im Rumpf von Run.
function Foo(const AExtra, ABody: string): string;
begin
  Result := UnitOf([
    '  TFoo = class',                          // 4
    '  private',                               // 5
    '    { Private declarations }',            // 6
    '    procedure Dead(A: Integer);',         // 7
    '    procedure Used;' + AExtra,            // 8
    '  public',
    '    procedure Run;',
    '  end;'], [
    'procedure TFoo.Dead(A: Integer);',
    'begin',
    'end;',
    '',
    'procedure TFoo.Used;',
    'begin',
    'end;',
    '',
    'procedure TFoo.Run;',
    'begin',
    '  Used;' + ABody,
    'end;']);
end;

// ---- Tests ----

procedure TTestRdxMethodFixes.Sca147_DeclAndImpl;
begin
  // '///' geht mit der Deklaration, der Gruppenkommentar im Rumpf bleibt;
  // ueber der Implementierung gehen Kommentar (er nennt die Methode) und
  // Leerzeile mit, der Abschnittsmarker '{ TFoo }' bleibt; der rekursive
  // Aufruf im eigenen Rumpf zaehlt nicht.
  Assert.AreEqual(UnitOf([
      '  TFoo = class',
      '  private',
      '    { Private declarations }',
      '    procedure Used;',
      '  public',
      '    procedure Run;',
      '  end;'], [
      '',
      '{ TFoo }',
      '',
      'procedure TFoo.Used;',
      'begin',
      'end;',
      '',
      'procedure TFoo.Run;',
      'begin',
      '  Used;',
      'end;']),
    FixOk(UnitOf([
      '  TFoo = class',
      '  private',
      '    { Private declarations }',
      '    /// <summary>Old helper</summary>',   // 7
      '    procedure Dead(A: Integer);',         // 8
      '    procedure Used;',
      '  public',
      '    procedure Run;',
      '  end;'], [
      '',
      '{ TFoo }',
      '',
      '// Dead: old helper',
      'procedure TFoo.Dead(A: Integer);',
      'begin',
      '  if A > 0 then',
      '    Dead(A - 1);',
      'end;',
      '',
      'procedure TFoo.Used;',
      'begin',
      'end;',
      '',
      'procedure TFoo.Run;',
      'begin',
      '  Used;',
      'end;']), 8, 'TFoo', 'Dead'));
end;

procedure TTestRdxMethodFixes.Sca147_StrictGenericClassMethod;
begin
  Assert.AreEqual(Bare(['  TGen<T> = class', '  strict private',
      '    FX: T;', '  end;']),
    FixOk(UnitOf(['  TGen<T> = class', '  strict private',
      '    class procedure Dead;', '    FX: T;', '  end;'],
      ['class procedure TGen<T>.Dead;', 'begin', 'end;', '']), 6, 'TGen',
      'Dead'));
end;

procedure TTestRdxMethodFixes.Sca147_NestedClass;
var
  Src, Want : string;
begin
  Src := UnitOf(['  TOuter = class', '  public', '    type',
    '      TInner = class', '      private', '        procedure Dead;',
    '      end;', '  end;'],
    ['procedure TOuter.TInner.Dead;', 'begin', 'end;', '']);
  Want := Bare(['  TOuter = class', '  public', '    type',
    '      TInner = class', '      private', '      end;', '  end;']);
  // Die Meldung nennt die innere Klasse - mit oder ohne Pfad.
  Assert.AreEqual(Want, FixOk(Src, 9, 'TInner', 'Dead'));
  Assert.AreEqual(Want, FixOk(Src, 9, 'TOuter.TInner', 'Dead'));
end;

procedure TTestRdxMethodFixes.Sca147_LocalInterface;
begin
  // Das Interface steht in derselben Datei; Dead ist nicht sein Member.
  Assert.AreEqual(UnitOf(['  IFoo = interface', '    procedure Run;',
      '  end;', '  TFoo = class(TInterfacedObject, IFoo)', '  private',
      '  public', '    procedure Run;', '  end;'],
      ['procedure TFoo.Run;', 'begin', 'end;']),
    FixOk(UnitOf(['  IFoo = interface', '    procedure Run;', '  end;',
      '  TFoo = class(TInterfacedObject, IFoo)', '  private',
      '    procedure Dead;', '  public', '    procedure Run;', '  end;'],
      ['procedure TFoo.Dead;', 'begin', 'end;', '', 'procedure TFoo.Run;',
      'begin', 'end;']), 9, 'TFoo', 'Dead'));
end;

procedure TTestRdxMethodFixes.Sca147_Section_NoHelp;
begin
  AssertRefused(UnitOf(['  TFoo = class', '  protected',
    '    procedure Dead;', '  end;'], ['procedure TFoo.Dead;', 'begin',
    'end;']), 6, 'TFoo', 'Dead', 'protected');
  // Ohne Abschnitt: Vorgabe public bzw. published.
  AssertRefused(UnitOf(['  TFoo = class', '    procedure Dead;', '  end;'],
    ['procedure TFoo.Dead;', 'begin', 'end;']), 5, 'TFoo', 'Dead',
    'Vorgabe');
end;

procedure TTestRdxMethodFixes.Sca147_Dispatch_NoHelp;
begin
  AssertRefused(UnitOf(['  TFoo = class', '  private',
    '    procedure Dead; virtual;', '  end;'], ['procedure TFoo.Dead;',
    'begin', 'end;']), 6, 'TFoo', 'Dead', 'virtual');
  AssertRefused(UnitOf(['  TFoo = class', '  private',
    '    procedure Dead(var M: TMessage); message 1024;', '  end;'],
    ['procedure TFoo.Dead(var M: TMessage);', 'begin', 'end;']), 6, 'TFoo',
    'Dead', 'message');
  AssertRefused(UnitOf(['  TFoo = class', '  private',
    '    procedure Dead; overload;', '  end;'], ['procedure TFoo.Dead;',
    'begin', 'end;']), 6, 'TFoo', 'Dead', 'overload');
  AssertRefused(UnitOf(['  TFoo = class', '  private',
    '    constructor Dead;', '  end;'], ['constructor TFoo.Dead;', 'begin',
    'end;']), 6, 'TFoo', 'Dead', 'constructor');
end;

procedure TTestRdxMethodFixes.Sca147_Used_NoHelp;
begin
  AssertRefused(Foo('', #13#10'    Dead(1);'), 7, 'TFoo', 'Dead',
    'verwendet');
  AssertRefused(Foo(#13#10'    property P: Integer read Dead;', ''), 7,
    'TFoo', 'Dead', 'Accessor');
  AssertRefused(Foo('', #13#10'    MethodAddress(''Dead'');'), 7, 'TFoo',
    'Dead', 'String-Literal');
end;

procedure TTestRdxMethodFixes.Sca147_Rtti_NoHelp;
begin
  AssertRefused(Join(['{$RTTI EXPLICIT METHODS([vcPrivate])}', Foo('', '')]),
    8, 'TFoo', 'Dead', 'RTTI');
  AssertRefused(UnitOf(['  TFoo = class', '  private', '    [Hook]',
    '    procedure Dead;', '  end;'], ['procedure TFoo.Dead;', 'begin',
    'end;']), 7, 'TFoo', 'Dead', 'Attribut');
  AssertRefused(UnitOf(['  [Registered]', '  TFoo = class', '  private',
    '    procedure Dead;', '  end;'], ['procedure TFoo.Dead;', 'begin',
    'end;']), 7, 'TFoo', 'Dead', 'Attribut');
end;

procedure TTestRdxMethodFixes.Sca147_NoImpl_NoHelp;
begin
  AssertRefused(UnitOf(['  TFoo = class', '  private',
    '    procedure Dead;', '  end;'], ['{$I foo_impl.inc}']), 6, 'TFoo',
    'Dead', 'keine Implementierung');
  // Im Klassenrumpf: dort kann 'property P read Dead' stehen.
  AssertRefused(UnitOf(['  TFoo = class', '  private',
    '    procedure Dead;', '    {$I foo_props.inc}', '  end;'],
    ['procedure TFoo.Dead;', 'begin', 'end;']), 6, 'TFoo', 'Dead',
    'Klassenrumpf');
  AssertRefused(UnitOf(['  TFoo = class', '  private',
    '    procedure Dead;', '  end;'], ['{$I foo_more.inc}',
    'procedure TFoo.Dead;', 'begin', 'end;']), 6, 'TFoo', 'Dead',
    'Include');
end;

procedure TTestRdxMethodFixes.Sca147_ForeignInterface_NoHelp;
begin
  // IForeign kommt aus einer anderen Unit - Dead kann sein Member sein.
  AssertRefused(UnitOf(['  TFoo = class(TInterfacedObject, IForeign)',
    '  private', '    procedure Dead;', '  end;'], ['procedure TFoo.Dead;',
    'begin', 'end;']), 6, 'TFoo', 'Dead', 'IForeign');
end;

procedure TTestRdxMethodFixes.Sca147_Moved_NoHelp;
var
  R : string;
begin
  AssertRefused(Foo('', ''), 8, 'TFoo', 'Dead', 'kein Kopf der Methode Dead');
  // Die Klasse der Meldung umschliesst die Deklaration nicht.
  AssertRefused(Foo('', ''), 7, 'TBar', 'Dead', 'nicht im Rumpf');
  Assert.AreEqual('', Fix(Foo('', ''), 7, 'Private method Dead is unused',
    R));
  Assert.IsTrue(Pos('fehlt in der Meldung', R) > 0, R);
end;

procedure TTestRdxMethodFixes.Sca147_FormNamesMethod;
const
  FORM = 'object Form1: TForm1'#13#10'  OnShow = FormShow'#13#10'end';
begin
  Assert.IsTrue(TRdxRoutineFixes.FormNamesMethod(FORM, 'FormShow'));
  Assert.IsTrue(TRdxRoutineFixes.FormNamesMethod(FORM, 'formshow'));
  Assert.IsFalse(TRdxRoutineFixes.FormNamesMethod(FORM, 'Form'));
  Assert.IsFalse(TRdxRoutineFixes.FormNamesMethod(FORM, 'FormShowX'));
end;

// ---- Charge H3c (Gegen-Review H3) ----

procedure TTestRdxMethodFixes.Sca147_FirstEntryInterface_NoHelp;
begin
  // Pruefer-Fall (Minor 2): 'class(IFremd)' - die Basis ist TObject, der
  // erste Eintrag ein Interface aus einer anderen Unit (nach der Hilfe
  // E2291, wenn Bar sein Member ist).
  AssertRefused(UnitOf(['  TImpl = class(IExternal)', '  private',
    '    procedure Bar;', '  end;'], ['procedure TImpl.Bar;', 'begin',
    'end;']), 6, 'TImpl', 'Bar', 'IExternal');
end;

procedure TTestRdxMethodFixes.Sca147_InterfaceAncestors;
begin
  // Pruefer-Fall (Minor 2): das lokale IFoo erbt von IExternal.
  AssertRefused(UnitOf(['  IFoo = interface(IExternal)', '  end;',
    '  TImpl = class(TInterfacedObject, IFoo)', '  private',
    '    procedure Bar;', '  end;'], ['procedure TImpl.Bar;', 'begin',
    'end;']), 8, 'TImpl', 'Bar', 'IExternal');
  // Eine Kette lokaler Interfaces bis IInterface: alle bekannt, Bar ist
  // keines ihrer Member - die Hilfe bleibt.
  Assert.AreEqual(Bare(['  IBase = interface(IInterface)', '  end;',
      '  IFoo = interface(IBase)', '  end;',
      '  TImpl = class(TInterfacedObject, IFoo)', '  private', '  end;']),
    FixOk(UnitOf(['  IBase = interface(IInterface)', '  end;',
      '  IFoo = interface(IBase)', '  end;',
      '  TImpl = class(TInterfacedObject, IFoo)', '  private',
      '    procedure Bar;', '  end;'], ['procedure TImpl.Bar;', 'begin',
      'end;']), 10, 'TImpl', 'Bar'));
  // Ein Member von IInterface als Name: _AddRef bedient das Interface.
  AssertRefused(UnitOf(['  TImpl = class(TObject, IInterface)', '  private',
    '    function _AddRef: Integer; stdcall;', '  end;'],
    ['function TImpl._AddRef: Integer;', 'begin', '  Result := 1;', 'end;']),
    6, 'TImpl', '_AddRef', 'Member von IInterface');
end;

procedure TTestRdxMethodFixes.Sca147_CommentAboveImpl;
var
  Src : string;
begin
  // Minor 3: ein Kommentar ohne den Namen der Methode bleibt (er kann eine
  // Gruppe ueberschreiben); einer, der sie nennt, geht mit.
  Src := UnitOf(['  TFoo = class', '  private', '    procedure Dead;',
    '    procedure Dead2;', '  end;'], ['', '// Gruppe: Aufraeumen',
    'procedure TFoo.Dead;', 'begin', 'end;', '', '// Dead2 raeumt auf',
    'procedure TFoo.Dead2;', 'begin', 'end;']);
  Assert.AreEqual(UnitOf(['  TFoo = class', '  private', '    procedure Dead2;',
      '  end;'], ['', '// Gruppe: Aufraeumen', '// Dead2 raeumt auf',
      'procedure TFoo.Dead2;', 'begin', 'end;']),
    FixOk(Src, 6, 'TFoo', 'Dead'));
  Assert.AreEqual(UnitOf(['  TFoo = class', '  private', '    procedure Dead;',
      '  end;'], ['', '// Gruppe: Aufraeumen', 'procedure TFoo.Dead;', 'begin',
      'end;']),
    FixOk(Src, 7, 'TFoo', 'Dead2'));
end;

procedure TTestRdxMethodFixes.Sca147_UmlautCall_NoHelp;
var
  Lower, Upper : string;
begin
  // Pruefer-Fall (casesuni, Verdacht 1) fuer Methoden: der Aufruf in
  // Grossschreibung mit Umlaut.
  Lower := 'Pr' + #$00FC + 'fe';
  Upper := 'PR' + #$00DC + 'FE';
  AssertRefused(UnitOf(['  TFoo = class', '  private',
    '    procedure ' + Lower + ';', '  public', '    procedure Run;', '  end;'],
    ['procedure TFoo.' + Lower + ';', 'begin', 'end;', '',
    'procedure TFoo.Run;', 'begin', '  ' + Upper + ';', 'end;']), 6, 'TFoo',
    Lower, 'verwendet');
end;

// ---- Charge B1-FD (Code-Review reDelphix, R4; je gegen 4358b769 rot) ----

// Der Plan des Planers fuer die Meldung zu AClass.AMethod auf Zeile ALine.
function MethodPlan(const ASource: string; ALine: Integer; const AClass,
  AMethod: string; out AReason: string): TRdxRoutinePlan;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    TRdxRoutineFixes.UnusedPrivateMethod(Map, ALine, Msg(AClass, AMethod),
      Result, AReason);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Schreibt AText nach APath (Include-Dateien neben der Unit).
procedure SaveText(const APath, AText: string);
var
  SL : TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Text := AText;
    SL.SaveToFile(APath);
  finally
    SL.Free;
  end;
end;

procedure TTestRdxMethodFixes.Sca147_IncludeBeforeImplementation_Read;
var
  P         : TRdxRoutinePlan;
  R, Dir, U : string;
begin
  // R4-05, Pruefer-Fall r405 (1): ein Include zwischen Klasse und
  // implementation kann eine Nachfahrenklasse tragen ('TBar = class(TFoo)
  // property X: Integer read GetX; end;' - private ist in der ganzen Unit
  // sichtbar). Der Planer nannte es nicht, der Check der Tabelle las nichts,
  // und nach der Hilfe brach das Include mit E2003. Jetzt steht es in
  // P.Includes wie bei SCA164.
  P := MethodPlan(UnitOf(['  TFoo = class', '  private',
    '    function GetX: Integer;', '  public', '    procedure Run;', '  end;',
    '{$I derived.inc}'], ['function TFoo.GetX: Integer;', 'begin',
    '  Result := 1;', 'end;', 'procedure TFoo.Run;', 'begin', 'end;']), 6,
    'TFoo', 'GetX', R);
  Assert.AreEqual('', R, 'der Planer selbst bietet an');
  Assert.AreEqual<Integer>(1, Integer(Length(P.Includes)), 'Includes');
  Assert.AreEqual('derived.inc', P.Includes[0]);
  // Der Check liest es neben der Unit: nennt es GetX, keine Hilfe; fehlt
  // es, ebenso; ohne den Namen bleibt die Hilfe.
  Dir := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP'))
    + 'rdx_b1fd_inc' + PathDelim;
  ForceDirectories(Dir);
  U := Dir + 'u.pas';
  try
    SaveText(Dir + 'derived.inc', Join(['type', '  TBar = class(TFoo)',
      '    property X: Integer read GetX;', '  end;']));
    R := TRdxRoutineFixes.IncludeReason(U, P.Includes, P.Name);
    Assert.IsTrue(Pos('nennt GetX', R) > 0, R);
    SaveText(Dir + 'derived.inc', '{$R-}');
    Assert.AreEqual('', TRdxRoutineFixes.IncludeReason(U, P.Includes, P.Name));
    DeleteFile(Dir + 'derived.inc');
    R := TRdxRoutineFixes.IncludeReason(U, P.Includes, P.Name);
    Assert.IsTrue(Pos('nicht neben der Unit', R) > 0, R);
  finally
    DeleteFile(Dir + 'derived.inc');
    RemoveDir(Dir);
  end;
  // Ein Include im Kopf der Unit (vor interface) traegt nur Direktiven -
  // es steht nicht im Plan.
  P := MethodPlan(Join(['unit u;', '{$I cfg.inc}', 'interface', 'type',
    '  TFoo = class', '  private', '    procedure Dead;', '  end;',
    'implementation', 'procedure TFoo.Dead;', 'begin', 'end;', 'end.']), 7,
    'TFoo', 'Dead', R);
  Assert.AreEqual('', R);
  Assert.AreEqual<Integer>(0, Integer(Length(P.Includes)), 'Kopf-Include');
end;

procedure TTestRdxMethodFixes.Sca147_TrailingMarker_NoHelp;
begin
  // R4-04 fuer SCA147: der Marker hinter der Deklaration gilt dem Member
  // dahinter (uSuppression.BuildMap) ...
  AssertRefused(UnitOf(['  TFoo = class', '  private',
    '    procedure Dead; // noinspection DuplicateString',
    '    procedure Used;', '  public', '    procedure Run;', '  end;'],
    ['procedure TFoo.Dead;', 'begin', 'end;', '', 'procedure TFoo.Used;',
    'begin', 'end;', '', 'procedure TFoo.Run;', 'begin', '  Used;', 'end;']),
    6, 'TFoo', 'Dead', 'Zeile 6 endet mit dem Kommentar');
  // ... der hinter dem end der Implementierung der Routine dahinter.
  AssertRefused(UnitOf(['  TFoo = class', '  private', '    procedure Dead;',
    '    procedure Used;', '  public', '    procedure Run;', '  end;'],
    ['procedure TFoo.Dead;', 'begin', 'end; // noinspection EmptyMethod',
    'procedure TFoo.Used;', 'begin', 'end;', '', 'procedure TFoo.Run;',
    'begin', '  Used;', 'end;']), 6, 'TFoo', 'Dead', 'Zeile 14 endet');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxMethodFixes);

end.
