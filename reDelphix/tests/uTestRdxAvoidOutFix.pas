unit uTestRdxAvoidOutFix;

// Editorhilfe SCA086 AvoidOut (uRdxAvoidOutFix): der Planer auf Text (erste
// Fixture, FPC-tauglich) und der ECHTE Detektor (uAvoidOut) auf dem echten
// AST ueber den Einstieg der Tabelle (TRdxFixTable.FixFor via PlanFixIn/
// FixAllWith, Adapter PlanAvoidOut - Kennzeichnung und Hinweis nach dem Typ;
// zweite Fixture, nur Delphi). Die Spalte ist die des ersten 'out ' der
// Zeile.
//
// Realwelt-Test rwE29 (Fehler mORMot mormot.core.data.pas:948): eine im
// interface-Teil deklarierte Routine bzw. eine ausserhalb der Unit
// sichtbare Methode kann eine andere Unit als Prozedur-/Methodenwert nehmen
// - gesperrt (Exported_NoHelp, gegen 7d5de210 rot: dort angeboten). Die
// Fixtures der Umformung stehen seitdem unter private (unit-lokal); die
// Klasse im implementation-Teil bleibt mit public eine Hilfe
// (ImplementationClassPublic_Helps, auch vorher gruen).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxAvoidOutFix = class
  public
    // ---- Umformung ----
    [Test] procedure MethodPair_Managed_BothHeadsChanged;
    [Test] procedure MethodPair_Plain_SameMeaning;
    [Test] procedure ImplWithoutParamList_DeclOnly;
    [Test] procedure ImplementationClassPublic_Helps;
    [Test] procedure ForwardRoutine_Paired;
    [Test] procedure ImplOnlyRoutine_Changed;
    [Test] procedure NameList_BothHeads;
    [Test] procedure IsManagedType_PlainAndManaged;
    // ---- Gegenproben ----
    [Test] procedure MovedOrNoColumn_NoHelp;
    [Test] procedure Untyped_NoHelp;
    [Test] procedure NotRoutine_NoHelp;
    [Test] procedure OverloadOrSameName_NoHelp;
    [Test] procedure BoundDirective_NoHelp;
    [Test] procedure PublishedOrDefault_NoHelp;
    [Test] procedure ClassWithInterfaces_NoHelp;
    [Test] procedure InterfaceTypeMethod_NoHelp;
    [Test] procedure ReferencedAsPointer_NoHelp;
    [Test] procedure OtherHeadMismatch_NoHelp;
    [Test] procedure DeclarationMissingOrInclude_NoHelp;
    [Test] procedure Exported_NoHelp;
    // rwE30 Stufe 2 (Sperre unnoetig): Interfaces derselben Unit ohne die
    // Methode, Includes im Kopf der Unit, lokale Routinen.
    [Test] procedure LocalInterfaces_Helps;
    [Test] procedure HeaderInclude_Helps;
    [Test] procedure LocalRoutines_ScopedToOuter;
    // rwE30 Stufe 2 (mormot.lib.win7zip.pas:1070, ColorPreview.Parser.pas:
    // 341): verwalteter Typ, nicht als erste Anweisung gesetzt.
    [Test] procedure ManagedNotSetFirst_MenuOnly;
    // rwE31 Stufe 3: ein Record der Datei mit einfachen Feldern (mORMot
    // test.core.data.pas:1332), if/else setzt in beiden Zweigen
    // (delphimvcframework MVCFramework.Utils.pas:62), {$IFDEF} um das
    // Setzen (jcl JclStringConversions.pas:407), Methoden eines records
    // (Kastri DW.Exif.Win.pas:102), lokale Overloads mit anderer Zahl von
    // Parametern und Aufruf ohne Klammern (JclStringConversions.pas:407).
    [Test] procedure LocalPlainRecord_SameMeaning;
    [Test] procedure IfElseSetsBoth_InBulb;
    [Test] procedure DirectiveAroundSet_MenuOnly;
    [Test] procedure RecordMethod_Helps;
    [Test] procedure LocalOverloads_OtherCount_Helps;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxAvoidOutDetector = class
  public
    [Test] procedure Detector_ReportsDeclAndImpl;
    [Test] procedure Detector_RoundTrip;
    [Test] procedure Detector_ImplFinding_FixesBoth;
    [Test] procedure Detector_CatalogExample_Fixed;
    [Test] procedure Detector_Virtual_NoHelp;
    [Test] procedure Detector_InterfaceMethod_NoHelp;
    [Test] procedure Detector_StaleFinding_NoHelp;
    // ---- Tabellenzeile (Kennzeichnung nach dem Typ) ----
    [Test] procedure Table_PlainType_SameMeaning;
    [Test] procedure Table_ManagedType_Marked;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uAvoidOut,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uTestRdxDetectorKit,   // TSeen, DetectSource, CatalogText, PlanFixIn,
                         // FixAllWith
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxAvoidOutFix,
  uRdxText,              // _() und die gemeinsamen Gruende
  uTestRdxTextKit;       // Join, Apply, LineOf, NewMap

// ---- Helfer ----

// Eine Unit mit der Klasse 'TFoo = <AHead>' (AMembers im Rumpf ab Zeile 5)
// und den Zeilen AImpl hinter implementation.
function ClassUnit(const AHead: string;
  const AMembers, AImpl: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'type', '  TFoo = ' + AHead])
    + #13#10 + Join(AMembers) + #13#10 + Join(['  end;', 'implementation'])
    + #13#10 + Join(AImpl) + #13#10 + 'end.';
end;

// Die Methode Get mit 'out S: string' in Klasse und Implementierung.
function GetUnit(const AHead: string; const AMembers: array of string): string;
begin
  Result := ClassUnit(AHead, AMembers, ['procedure TFoo.Get(out S: string);',
    'begin', '  S := ''x'';', 'end;']);
end;

// Die Methode Get mit 'out S: string' unter private, ABody als Rumpf.
function GetUnitBody(const ABody: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'type', '  TFoo = class',
    '  private', '    procedure Get(out S: string);', '  end;',
    'implementation', 'procedure TFoo.Get(out S: string);', 'begin'])
    + #13#10 + Join(ABody) + #13#10 + Join(['end;', 'end.']);
end;

// Die Meldung des Detektors fuer Spalte ACol; ohne Spalte (0) eine Meldung
// ohne 'at column'.
function MessageAt(ACol: Integer): string;
begin
  if ACol = 0 then
    Result := '`out` parameter - prefer `var`.'
  else
    Result := Format('`out` parameter at column %d - prefer `var` (out clears '
      + 'managed types on entry, leaves records uninitialized).', [ACol]);
end;

// Die Zeile ALine von ASource.
function LineText(const ASource: string; ALine: Integer): string;
var
  SL : TStringList;
begin
  Result := '';
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    if (ALine >= 1) and (ALine <= SL.Count) then
      Result := SL[ALine - 1];
  finally
    SL.Free;
  end;
end;

// Der Planer fuer Zeile ALine, Spalte ACol.
function PlanAt(const ASource: string; ALine, ACol: Integer;
  out APlan: TRdxOutPlan; out AReason: string): Boolean;
var
  Map : TRdxCodeMap;
begin
  Map := NewMap(ASource);
  try
    Result := TRdxAvoidOutFix.OutToVar(Map, ALine, MessageAt(ACol), APlan,
      AReason);
  finally
    Map.Free;
  end;
end;

// Dasselbe an der ersten Zeile mit AText; Spalte: das erste 'out ' dort.
function PlanOn(const ASource, AText: string; out APlan: TRdxOutPlan;
  out AReason: string): Boolean;
var
  Li : Integer;
begin
  Li := LineOf(ASource, AText);
  Assert.IsTrue(Li > 0, AText + ' steht nicht im Text');
  Result := PlanAt(ASource, Li, Pos('out ', LineText(ASource, Li)), APlan,
    AReason);
end;

// Die Hilfe an der Zeile mit AText muss gelten; der neue Text.
function Fix(const ASource, AText: string; out APlan: TRdxOutPlan): string;
var
  R : string;
begin
  Assert.IsTrue(PlanOn(ASource, AText, APlan, R), R);
  Result := Apply(ASource, APlan.Edits);
end;

procedure AssertRefused(const ASource, AText, AReason: string);
var
  P : TRdxOutPlan;
  R : string;
begin
  Assert.IsFalse(PlanOn(ASource, AText, P, R), 'keine Hilfe: ' + AText);
  Assert.AreEqual(AReason, R, 'Grund: ' + AText);
end;

// ---- Umformung ----

procedure TTestRdxAvoidOutFix.MethodPair_Managed_BothHeadsChanged;
var
  Src, Expected : string;
  P             : TRdxOutPlan;
begin
  Src := GetUnit('class', ['  private', '    procedure Get(out S: string);']);
  Expected := StringReplace(Src, 'out S', 'var S', [rfReplaceAll]);
  Assert.AreEqual(Expected, Fix(Src, 'procedure Get(', P));
  Assert.AreEqual<Integer>(2, Length(P.Edits), 'Deklaration und Implementierung');
  Assert.IsTrue(P.Changes, 'string ist verwaltet - gekennzeichnet');
  Assert.AreEqual('S', P.Name);
  // Vom Fund an der Implementierung aus dasselbe.
  Assert.AreEqual(Expected, Fix(Src, 'TFoo.Get(', P));
end;

procedure TTestRdxAvoidOutFix.MethodPair_Plain_SameMeaning;
var
  Src : string;
  P   : TRdxOutPlan;
begin
  Src := ClassUnit('class', ['  private', '    procedure Get(out N: Integer);'],
    ['procedure TFoo.Get(out N: Integer);', 'begin', '  N := 1;', 'end;']);
  Assert.AreEqual(StringReplace(Src, 'out N', 'var N', [rfReplaceAll]),
    Fix(Src, 'procedure Get(', P));
  Assert.IsFalse(P.Changes, 'Integer: out wie var');
end;

procedure TTestRdxAvoidOutFix.ImplWithoutParamList_DeclOnly;
var
  Src : string;
  P   : TRdxOutPlan;
begin
  // Die Implementierung darf die Parameterliste weglassen.
  Src := ClassUnit('class', ['  private', '    procedure Get(out S: string);'],
    ['procedure TFoo.Get;', 'begin', '  S := ''x'';', 'end;']);
  Assert.AreEqual(StringReplace(Src, 'out S', 'var S', []),
    Fix(Src, 'procedure Get(', P));
  Assert.AreEqual<Integer>(1, Length(P.Edits), 'nur die Deklaration');
end;

procedure TTestRdxAvoidOutFix.ImplementationClassPublic_Helps;
var
  Src : string;
  P   : TRdxOutPlan;
begin
  // Eine Klasse des implementation-Teils sieht keine andere Unit - public
  // bleibt dort unit-lokal.
  Src := Join(['unit t;', 'interface', 'implementation', 'type',
    '  TFoo = class', '  public', '    procedure Get(out N: Integer);',
    '  end;', 'procedure TFoo.Get(out N: Integer);', 'begin', '  N := 1;',
    'end;', 'end.']);
  Assert.AreEqual(StringReplace(Src, 'out N', 'var N', [rfReplaceAll]),
    Fix(Src, 'procedure Get(', P));
  Assert.AreEqual<Integer>(2, Length(P.Edits));
end;

procedure TTestRdxAvoidOutFix.ForwardRoutine_Paired;
var
  Src : string;
  P   : TRdxOutPlan;
begin
  // forward-Deklaration, ein Aufruf und der Rumpf.
  Src := Join(['unit t;', 'interface', 'implementation',
    'procedure Load(out Count: Integer); forward;', 'procedure Use;',
    'var N: Integer;', 'begin', '  Load(N);', 'end;',
    'procedure Load(out Count: Integer);', 'begin', '  Count := 1;', 'end;',
    'end.']);
  Assert.AreEqual(StringReplace(Src, 'out Count', 'var Count', [rfReplaceAll]),
    Fix(Src, 'forward', P));
end;

procedure TTestRdxAvoidOutFix.ImplOnlyRoutine_Changed;
var
  Src : string;
  P   : TRdxOutPlan;
begin
  Src := Join(['unit t;', 'interface', 'implementation',
    'procedure Load(out Count: Integer);', 'begin', '  Count := 1;', 'end;',
    'end.']);
  Assert.AreEqual(StringReplace(Src, 'out Count', 'var Count', []),
    Fix(Src, 'procedure Load(', P));
  Assert.AreEqual<Integer>(1, Length(P.Edits));
end;

procedure TTestRdxAvoidOutFix.NameList_BothHeads;
var
  Src : string;
  P   : TRdxOutPlan;
begin
  Src := ClassUnit('class', ['  private', '    procedure Get(out A, B: string);'],
    ['procedure TFoo.Get(out A, B: string);', 'begin', '  A := ''a'';',
     '  B := ''b'';', 'end;']);
  Assert.AreEqual(StringReplace(Src, 'out A', 'var A', [rfReplaceAll]),
    Fix(Src, 'procedure Get(', P));
  // Der Menuetext nennt beide Parameter, die die Ersetzung trifft (rwE30
  // Stufe 2, MVCFramework.JWT.pas:698 'out Header, Payload' - bis dahin
  // nur 'A').
  Assert.AreEqual('A, B', P.Name);
end;

procedure TTestRdxAvoidOutFix.IsManagedType_PlainAndManaged;
begin
  Assert.IsFalse(TRdxAvoidOutFix.IsManagedType('Integer'));
  Assert.IsFalse(TRdxAvoidOutFix.IsManagedType('System.Integer'));
  Assert.IsFalse(TRdxAvoidOutFix.IsManagedType('TObject'));
  Assert.IsFalse(TRdxAvoidOutFix.IsManagedType('Double'));
  Assert.IsTrue(TRdxAvoidOutFix.IsManagedType('string'));
  Assert.IsTrue(TRdxAvoidOutFix.IsManagedType('IInterface'));
  Assert.IsTrue(TRdxAvoidOutFix.IsManagedType('TBytes'));
  Assert.IsTrue(TRdxAvoidOutFix.IsManagedType('array of Byte'));
  Assert.IsTrue(TRdxAvoidOutFix.IsManagedType('Variant'));
  // Unbekannt (Record? Klasse?) zaehlt als verwaltet.
  Assert.IsTrue(TRdxAvoidOutFix.IsManagedType('TFooRec'));
end;

// ---- Gegenproben ----

procedure TTestRdxAvoidOutFix.MovedOrNoColumn_NoHelp;
var
  Src, R : string;
  P      : TRdxOutPlan;
  Li, Co : Integer;
begin
  Src := GetUnit('class', ['  private', '    procedure Get(out S: string);']);
  Li := LineOf(Src, 'procedure Get(');
  Co := Pos('out ', LineText(Src, Li));
  Assert.IsFalse(PlanAt(Src, Li, Co + 1, P, R), 'Spalte daneben');
  Assert.AreEqual(MsgMovedSuffix(_(R_OUT_MOVED)), R);
  Assert.IsFalse(PlanAt(Src, Li - 1, Co, P, R), 'Zeile davor');
  Assert.AreEqual(MsgMovedSuffix(_(R_OUT_MOVED)), R);
  Assert.IsFalse(PlanAt(Src, 99, Co, P, R), 'hinter der Datei');
  Assert.AreEqual(MsgMovedSuffix(_(R_OUT_MOVED)), R);
  Assert.IsFalse(PlanAt(Src, Li, 0, P, R), 'keine Spalte');
  Assert.AreEqual(MsgNoColumn, R);
  // 'out' im Kommentar und im String ist kein Parameter.
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    '// procedure Get(out S: string);', 'end.']), '// procedure',
    MsgMovedSuffix(_(R_OUT_MOVED)));
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    'const C = ''(out S: string)'';', 'end.']), 'const C',
    MsgMovedSuffix(_(R_OUT_MOVED)));
end;

procedure TTestRdxAvoidOutFix.Untyped_NoHelp;
begin
  AssertRefused(ClassUnit('class', ['  private', '    procedure Get(out Obj);'],
    ['procedure TFoo.Get(out Obj);', 'begin', 'end;']), 'procedure Get(',
    _(R_OUT_UNTYPED));
end;

procedure TTestRdxAvoidOutFix.NotRoutine_NoHelp;
var
  Src : string;
begin
  Src := Join(['unit t;', 'interface', 'type',
    '  TCallback = procedure(out S: string);',
    '  TRef = reference to procedure(out S: string);',
    '  TMeth = procedure(out S: string) of object;', 'implementation',
    'end.']);
  AssertRefused(Src, 'TCallback', _(R_OUT_NOT_ROUTINE));
  AssertRefused(Src, 'TRef', _(R_OUT_NOT_ROUTINE));
  AssertRefused(Src, 'TMeth', _(R_OUT_NOT_ROUTINE));
end;

procedure TTestRdxAvoidOutFix.OverloadOrSameName_NoHelp;
begin
  AssertRefused(ClassUnit('class', ['  private',
    '    procedure Get(out S: string); overload;',
    '    procedure Get(out N: Integer); overload;'],
    ['procedure TFoo.Get(out S: string);', 'begin', 'end;',
     'procedure TFoo.Get(out N: Integer);', 'begin', 'end;']),
    'procedure Get(out S', _(R_OUT_HEADS, [4, 'Get']));
  // Dieselbe Methode in zwei Klassen.
  AssertRefused(Join(['unit t;', 'interface', 'type', '  TA = class',
    '  public', '    procedure Get(out S: string);', '  end;', '  TB = class',
    '  public', '    procedure Get(out S: string);', '  end;',
    'implementation', 'procedure TA.Get(out S: string);', 'begin', 'end;',
    'procedure TB.Get(out S: string);', 'begin', 'end;', 'end.']),
    'procedure Get(', _(R_OUT_HEADS, [4, 'Get']));
end;

procedure TTestRdxAvoidOutFix.BoundDirective_NoHelp;
begin
  AssertRefused(GetUnit('class', ['  private',
    '    procedure Get(out S: string); virtual;']), 'procedure Get(',
    _(R_OUT_DIRECTIVE, ['Get', 'virtual']));
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    'procedure Load(out Count: Integer); stdcall;', 'begin', '  Count := 1;',
    'end;', 'end.']), 'procedure Load(', _(R_OUT_DIRECTIVE, ['Load', 'stdcall']));
end;

procedure TTestRdxAvoidOutFix.PublishedOrDefault_NoHelp;
begin
  AssertRefused(GetUnit('class', ['  published',
    '    procedure Get(out S: string);']), 'procedure Get(',
    _(R_OUT_PUBLISHED, ['Get', 'TFoo']));
  // Ohne Sichtbarkeitswort (in TPersistent-Erben published).
  AssertRefused(GetUnit('class', ['    procedure Get(out S: string);']),
    'procedure Get(', _(R_OUT_PUBLISHED, ['Get', 'TFoo']));
end;

procedure TTestRdxAvoidOutFix.ClassWithInterfaces_NoHelp;
begin
  AssertRefused(GetUnit('class(TInterfacedObject, IFoo)', ['  private',
    '    procedure Get(out S: string);']), 'procedure Get(',
    _(R_OUT_INTERFACES, ['TFoo', 'Get']));
end;

procedure TTestRdxAvoidOutFix.InterfaceTypeMethod_NoHelp;
begin
  AssertRefused(Join(['unit t;', 'interface', 'type', '  IFoo = interface',
    '    procedure Get(out S: string);', '  end;', 'implementation', 'end.']),
    'procedure Get(', _(R_OUT_IN_TYPE, ['Get']));
end;

procedure TTestRdxAvoidOutFix.ReferencedAsPointer_NoHelp;
begin
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    'procedure Load(out Count: Integer);', 'begin', '  Count := 1;', 'end;',
    'procedure Use;', 'begin', '  Run(@Load);', 'end;', 'end.']),
    'procedure Load(', _(R_OUT_REFERENCE, ['Load', 10]));
end;

procedure TTestRdxAvoidOutFix.OtherHeadMismatch_NoHelp;
begin
  // Die Implementierung teilt die Namensliste anders auf.
  AssertRefused(ClassUnit('class', ['  private',
    '    procedure Get(out A, B: string);'],
    ['procedure TFoo.Get(out A: string; out B: string);', 'begin', 'end;']),
    'procedure Get(', _(R_OUT_MISMATCH, ['Get', 'A, B']));
end;

procedure TTestRdxAvoidOutFix.DeclarationMissingOrInclude_NoHelp;
begin
  // Die Klasse steht in einer anderen Unit.
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    'procedure TFoo.Get(out S: string);', 'begin', 'end;', 'end.']),
    'TFoo.Get', _(R_OUT_NO_DECL, ['Get']));
  // Ein Include koennte die Routine deklarieren.
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    '{$I defs.inc}', 'procedure Load(out Count: Integer);', 'begin',
    '  Count := 1;', 'end;', 'end.']), 'procedure Load(',
    _(R_OUT_INCLUDE, ['Load']));
end;

procedure TTestRdxAvoidOutFix.Exported_NoHelp;
const
  HEAD = 'function _BCI_ObjArray(A, B: pointer; Info: PRttiInfo; out '
    + 'Compared: integer): PtrInt;';
var
  Src, R : string;
  P      : TRdxOutPlan;
begin
  // mORMot mormot.core.data.pas:948 (rwE29, Fehler): '_BCI_ObjArray' steht
  // im interface-Teil; mormot.core.json weist sie 'fCompare[true]' zu
  // (TRttiCompare mit 'out Compared') - nach out -> var E2009 dort. Bis
  // rwE29 angeboten (Deklaration + Rumpf ein Paar, kein Gebrauch HIER).
  Src := Join(['unit t;', 'interface', 'type', '  PRttiInfo = pointer;',
    HEAD, 'implementation', HEAD, 'begin', '  Compared := 0;',
    '  result := 0;', 'end;', 'end.']);
  AssertRefused(Src, HEAD, _(R_OUT_INTERFACE, [5]));
  // Dieselbe Sperre vom Fund am Rumpf (Zeile 7) aus.
  Assert.IsFalse(PlanAt(Src, 7, Pos('out ', HEAD), P, R), 'Rumpf');
  Assert.AreEqual(_(R_OUT_INTERFACE, [5]), R);
  // Methoden einer Klasse des interface-Teils ausserhalb von private: eine
  // andere Unit kann sie als Methodenzeiger nehmen ('OnX := Obj.Get').
  AssertRefused(GetUnit('class', ['  public',
    '    procedure Get(out S: string);']), 'procedure Get(', _(R_OUT_VISIBLE));
  AssertRefused(GetUnit('class', ['  protected',
    '    procedure Get(out S: string);']), 'procedure Get(', _(R_OUT_VISIBLE));
  AssertRefused(GetUnit('class', ['  strict protected',
    '    procedure Get(out S: string);']), 'TFoo.Get(', _(R_OUT_VISIBLE));
end;

procedure TTestRdxAvoidOutFix.LocalInterfaces_Helps;
var
  Src : string;
  P   : TRdxOutPlan;
begin
  // delphimvcframework MVCFramework.DotEnv.pas:96 (minimiert): TFoo
  // implementiert IFoo und IBar, beide in derselben Unit, keines nennt Get.
  // Bis dahin R_OUT_INTERFACES.
  Src := Join(['unit t;', 'interface', 'type', '  IFoo = interface',
    '    procedure Run;', '  end;', '  IBar = interface(IFoo)', '  end;',
    '  TFoo = class(TInterfacedObject, IFoo, IBar)', '  private',
    '    procedure Get(out S: string);', '  public', '    procedure Run;',
    '  end;', 'implementation', 'procedure TFoo.Get(out S: string);', 'begin',
    '  S := ''x'';', 'end;', 'procedure TFoo.Run;', 'begin', 'end;', 'end.']);
  Assert.AreEqual(StringReplace(Src, 'out S', 'var S', [rfReplaceAll]),
    Fix(Src, 'procedure Get(', P));
  // Gegenprobe: ein Interface dieser Datei mit Get - ein dritter Kopf.
  Src := StringReplace(Src, '    procedure Run;'#13#10'  end;'#13#10'  IBar',
    '    procedure Get(out S: string);'#13#10'  end;'#13#10'  IBar', []);
  AssertRefused(Src, 'TFoo.Get(', _(R_OUT_HEADS, [3, 'Get']));
  // Gegenprobe: das lokale Interface erbt von einem fremden.
  AssertRefused(GetUnit('class(TInterfacedObject, IFoo)', ['  private',
    '    procedure Get(out S: string);', '  end;',
    '  IFoo = interface(IForeign)']), 'procedure Get(',
    _(R_OUT_INTERFACES, ['TFoo', 'Get']));
end;

// Die Hilfe muss gelten und nur im Menue stehen - mit dem Hinweis
// R_OUT_NOT_FIRST fuer die Zeile mit AAt.
procedure AssertMenuOnly(const ASource, AAt: string);
var
  P : TRdxOutPlan;
  R : string;
begin
  Assert.IsTrue(PlanOn(ASource, 'procedure Get(', P, R), R);
  Assert.IsTrue(P.MenuOnly, 'nur im Menue');
  Assert.AreEqual(_(R_OUT_NOT_FIRST, ['s', 'Get', LineOf(ASource, AAt)]),
    P.Caution);
  Assert.AreEqual(StringReplace(ASource, 'out S', 'var S', [rfReplaceAll]),
    Apply(ASource, P.Edits));
end;

procedure TTestRdxAvoidOutFix.ManagedNotSetFirst_MenuOnly;
var
  Src : string;
  P   : TRdxOutPlan;
begin
  // mORMot mormot.lib.win7zip.pas:1070 (minimiert): dest wird nur bedingt
  // gesetzt - mit var bliebe der alte Wert des Aufrufers ('result') stehen,
  // wo out ihn leerte. Bis dahin sperrte R_OUT_INTERFACES (aus dem falschen
  // Grund; die Interfaces stehen in derselben Datei), bzw. die Hilfe stand
  // gekennzeichnet in der Gluehbirne (ColorPreview.Parser.pas:341).
  AssertMenuOnly(GetUnitBody(['  if Ready then', '    S := ''x'';']),
    '    S := ''x'';');
  // Ein Exit vor dem Setzen.
  AssertMenuOnly(GetUnitBody(['  if not Ready then', '    Exit;',
    '  S := ''x'';']), '    Exit;');
  // Gelesen auf der rechten Seite.
  AssertMenuOnly(GetUnitBody(['  S := S + ''x'';']), '  S := S');
  // Gegenprobe: zuerst gesetzt, dann bedingt weiter - in der Gluehbirne
  // (gekennzeichnet wie bisher).
  Src := GetUnitBody(['  S := '''';', '  if Ready then', '    S := ''x'';']);
  Assert.AreEqual(StringReplace(Src, 'out S', 'var S', [rfReplaceAll]),
    Fix(Src, 'procedure Get(', P));
  Assert.IsTrue(P.Changes, 'verwaltet: gekennzeichnet');
  Assert.IsFalse(P.MenuOnly, 'Gluehbirne');
  // Gegenprobe: ein einfacher Typ braucht das nicht (out = var).
  Src := ClassUnit('class', ['  private', '    procedure Get(out N: Integer);'],
    ['procedure TFoo.Get(out N: Integer);', 'begin', '  if Ready then',
     '    N := 1;', 'end;']);
  Assert.AreEqual(StringReplace(Src, 'out N', 'var N', [rfReplaceAll]),
    Fix(Src, 'procedure Get(', P));
  Assert.IsFalse(P.MenuOnly, 'einfacher Typ: Gluehbirne');
end;

procedure TTestRdxAvoidOutFix.HeaderInclude_Helps;
var
  Src : string;
  P   : TRdxOutPlan;
begin
  // cnwizards CnIDEVersion.pas:331 (minimiert): das einzige Include steht
  // zwischen interface und uses - dort stehen nur Direktiven, es kann die
  // Routine nicht deklarieren. Bis dahin R_OUT_INCLUDE.
  Src := Join(['unit t;', 'interface', '{$I CnWizards.inc}', 'uses Classes;',
    'implementation', 'procedure Load(out Count: Integer);', 'begin',
    '  Count := 1;', 'end;', 'end.']);
  Assert.AreEqual(StringReplace(Src, 'out Count', 'var Count', []),
    Fix(Src, 'procedure Load(', P));
  // mORMot test.core.data.pas: vor interface.
  Src := Join(['unit t;', '{$I mormot.defines.inc}', 'interface',
    'implementation', 'procedure Load(out Count: Integer);', 'begin',
    '  Count := 1;', 'end;', 'end.']);
  Assert.AreEqual(StringReplace(Src, 'out Count', 'var Count', []),
    Fix(Src, 'procedure Load(', P));
  // Gegenprobe: ein Include hinter implementation sperrt weiter
  // (DeclarationMissingOrInclude_NoHelp).
end;

procedure TTestRdxAvoidOutFix.LocalRoutines_ScopedToOuter;
var
  Src : string;
  P   : TRdxOutPlan;
  R   : string;
begin
  // skia4delphi FMX.Skia.Canvas.pas:636/767/1470 (minimiert): drei lokale
  // TryGetVMT in drei Routinen. Bis dahin R_OUT_HEADS (3 Koepfe).
  Src := Join(['unit t;', 'interface', 'implementation', 'procedure A;',
    '  function TryGetVMT(out V: Integer): Boolean;', '  begin',
    '    V := 1;', '    Result := True;', '  end;', 'var', '  X: Integer;',
    'begin', '  TryGetVMT(X);', 'end;', 'procedure B;',
    '  function TryGetVMT(out V: Integer): Boolean;', '  begin',
    '    V := 2;', '    Result := True;', '  end;', 'var', '  Y: Integer;',
    'begin', '  TryGetVMT(Y);', 'end;', 'end.']);
  Assert.IsTrue(PlanAt(Src, 16, Pos('out ', LineText(Src, 16)), P, R), R);
  Assert.AreEqual<Integer>(1, Length(P.Edits), 'nur der Kopf in B');
  Assert.AreEqual<Integer>(16, P.Edits[0].Span.StartLine);
  // jvcl JvLinkLabelTextHandler.pas:455: lokal, ein Include im Kopf.
  Src := Join(['unit t;', '{$I jvcl.inc}', 'interface', 'implementation',
    'procedure A;', '  function GetWidth(out W: Integer): Boolean;',
    '  begin', '    W := 1;', '    Result := True;', '  end;', 'var',
    '  X: Integer;', 'begin', '  GetWidth(X);', 'end;', 'end.']);
  Assert.IsTrue(PlanOn(Src, 'function GetWidth(', P, R), R);
  // Gegenprobe: ein Zeiger auf die lokale Routine in ihrer Routine.
  Src := Join(['unit t;', 'interface', 'implementation', 'procedure A;',
    '  function TryGetVMT(out V: Integer): Boolean;', '  begin',
    '    V := 1;', '    Result := True;', '  end;', 'begin', '  Run(@TryGetVMT);',
    'end;', 'procedure B;', '  function TryGetVMT(out V: Integer): Boolean;',
    '  begin', '    V := 2;', '    Result := True;', '  end;', 'begin',
    'end;', 'end.']);
  Assert.IsFalse(PlanAt(Src, 5, Pos('out ', LineText(Src, 5)), P, R),
    'Zeiger in A');
  Assert.AreEqual(_(R_OUT_REFERENCE, ['TryGetVMT', 11]), R);
end;

// ---- rwE31 Stufe 3 ----

// RangeFromJson wie in test.core.data.pas: TRange im interface-Teil (ATypes
// - die Zeilen dort), die Routine nur im implementation-Teil.
function RangeUnit(const ATypes: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'type']) + #13#10 + Join(ATypes)
    + #13#10 + Join(['implementation',
    'procedure RangeFromJson(out Range: TRange; Json: PChar);', 'begin',
    '  Decode(Json);', '  Range.Min := 1;', '  Range.Max := 2;', 'end;',
    'end.']);
end;

procedure TTestRdxAvoidOutFix.LocalPlainRecord_SameMeaning;
var
  Src, R : string;
  P      : TRdxOutPlan;
begin
  // test.core.data.pas:1332 (minimiert): 'TRange = record Min, Max:
  // Integer; end;' - out und var sind gleich. Bis dahin "range hat einen
  // verwalteten Typ" und nur im Menue (Range.Min ist keine Zuweisung an
  // Range).
  Src := RangeUnit(['  TRange = record', '    Min, Max: Integer;', '  end;']);
  Assert.AreEqual(StringReplace(Src, 'out Range', 'var Range', []),
    Fix(Src, 'procedure RangeFromJson(', P));
  Assert.IsFalse(P.Changes, 'einfacher Record: bedeutungsgleich');
  Assert.IsFalse(P.MenuOnly, 'Gluehbirne');
  // Verschachtelt: ein Record aus einfachen Records, statisches Array,
  // Aufzaehlung.
  Src := RangeUnit(['  TKind = (kA, kB);', '  TPair = packed record',
    '    A: array[0..1] of Byte;', '    K: TKind', '  end;',
    '  TRange = record', '    P: TPair;', '    N: Integer;', '  end;']);
  Assert.IsTrue(PlanOn(Src, 'procedure RangeFromJson(', P, R), R);
  Assert.IsFalse(P.Changes, 'verschachtelt einfach');
  // Gegenproben: ein string-Feld, ein Variantenteil, zwei Deklarationen
  // ($IFDEF-Zwilling) - verwaltet bzw. unbekannt.
  Src := RangeUnit(['  TRange = record', '    Min: Integer;',
    '    Name: string;', '  end;']);
  Assert.IsTrue(PlanOn(Src, 'procedure RangeFromJson(', P, R), R);
  Assert.IsTrue(P.Changes and P.MenuOnly, 'string-Feld');
  Src := RangeUnit(['  TRange = record', '    case Integer of',
    '      0: (Min: Integer);', '  end;']);
  Assert.IsTrue(PlanOn(Src, 'procedure RangeFromJson(', P, R), R);
  Assert.IsTrue(P.Changes, 'Variantenteil');
  Src := RangeUnit(['{$IFDEF X}', '  TRange = record Min: Integer; end;',
    '{$ELSE}', '  TRange = record Min: string; end;', '{$ENDIF}']);
  Assert.IsTrue(PlanOn(Src, 'procedure RangeFromJson(', P, R), R);
  Assert.IsTrue(P.Changes, 'Zwilling');
end;

procedure TTestRdxAvoidOutFix.IfElseSetsBoth_InBulb;
var
  Src, R : string;
  P      : TRdxOutPlan;
begin
  // MVCFramework.Utils.pas:62 (minimiert): eine Anweisung ohne S, dann
  // setzen beide Zweige des if S. Bis dahin nur im Menue (R_OUT_NOT_FIRST).
  Src := GetUnitBody(['  Parts := Split(Token);',
    '  if Length(Parts) = 2 then', '  begin', '    S := Parts[0];',
    '    Ok := True;', '  end', '  else', '  begin', '    S := '''';',
    '    Ok := False;', '  end;']);
  Assert.AreEqual(StringReplace(Src, 'out S', 'var S', [rfReplaceAll]),
    Fix(Src, 'procedure Get(', P));
  Assert.IsTrue(P.Changes, 'verwaltet: gekennzeichnet wie bisher');
  Assert.IsFalse(P.MenuOnly, 'Gluehbirne');
  // Zweige als einzelne Anweisung, das else ohne ';' davor.
  Src := GetUnitBody(['  if Ready then S := ''x'' else S := ''y'';']);
  Assert.IsTrue(PlanOn(Src, 'procedure Get(', P, R), R);
  Assert.IsFalse(P.MenuOnly, 'einzelne Zuweisungen');
  // Gegenproben: ein Zweig liest S zuerst (der Hinweis nennt dann wie bei
  // einem if ohne else die erste Nennung), die Bedingung liest S.
  AssertMenuOnly(GetUnitBody(['  if Ready then', '    S := ''x''', '  else',
    '  begin', '    Log(S);', '    S := '''';', '  end;']), '    S := ''x''');
  AssertMenuOnly(GetUnitBody(['  if S = '''' then', '    S := ''x''',
    '  else', '    S := ''y'';']), '  if S = ');
end;

procedure TTestRdxAvoidOutFix.DirectiveAroundSet_MenuOnly;
begin
  // JclStringConversions.pas:407 (minimiert): im {$ELSE}-Zweig nur raise -
  // dort setzt der Rumpf S nie. Der Token-Leser sieht beide Zweige als
  // Folge; bis dahin stand die Hilfe gekennzeichnet in der Gluehbirne.
  AssertMenuOnly(GetUnitBody(['  {$IFDEF SILENT}', '  S := ''x'';',
    '  {$ELSE}', '  raise EInvalidOp.Create('''');', '  {$ENDIF}']),
    '  S := ''x'';');
end;

procedure TTestRdxAvoidOutFix.RecordMethod_Helps;
var
  Src : string;
  P   : TRdxOutPlan;
begin
  // Kastri DW.Exif.Win.pas:102 (minimiert): 'TGdip = record' im
  // implementation-Teil mit einer class function. Bis dahin
  // R_OUT_NOT_IN_CLASS ("nicht direkt in der Klasse TGdip deklariert").
  Src := Join(['unit t;', 'interface', 'implementation', 'type',
    '  TGdip = record',
    '    class function GetItem(const AId: Integer; out AItem: Integer): '
    + 'Boolean; static;', '  end;',
    'class function TGdip.GetItem(const AId: Integer; out AItem: Integer): '
    + 'Boolean;', 'begin', '  AItem := AId;', '  Result := True;', 'end;',
    'end.']);
  Assert.AreEqual(StringReplace(Src, 'out AItem', 'var AItem',
    [rfReplaceAll]), Fix(Src, 'class function GetItem(', P));
  Assert.IsFalse(P.Changes, 'Integer');
  // mORMot mormot.core.datetime.pas:517 (minimiert): der Typkopf steht
  // doppelt im {$ifdef}, record oder object; der Typ im interface-Teil, die
  // Methode public - eine andere Unit sieht sie. Der Grund war "nicht
  // direkt in der Klasse", jetzt der richtige.
  Src := Join(['unit t;', 'interface', 'type', '{$ifdef USERECORD}',
    '  TSynTime = record', '{$else}', '  TSynTime = object', '{$endif}',
    '  public', '    procedure ToIso(out Text: string);', '  end;',
    'implementation', 'procedure TSynTime.ToIso(out Text: string);', 'begin',
    '  Text := '''';', 'end;', 'end.']);
  AssertRefused(Src, 'procedure ToIso(', _(R_OUT_VISIBLE));
  // ... unter private sieht sie nur diese Unit (mormot.crypt.secure.pas:597).
  Src := StringReplace(Src, '  public', '  private', []);
  Assert.AreEqual(StringReplace(Src, 'out Text', 'var Text', [rfReplaceAll]),
    Fix(Src, 'procedure ToIso(', P));
end;

procedure TTestRdxAvoidOutFix.LocalOverloads_OtherCount_Helps;
var
  Src : string;
  P   : TRdxOutPlan;
begin
  // JclStringConversions.pas:388-416 (minimiert): drei lokale Overloads mit
  // je anderer Zahl von Parametern; die ohne Parameter wird ohne Klammern
  // gerufen ('then Flag;', 'X..Y: Flag;'). Bis dahin R_OUT_REFERENCE
  // ("ohne Aufruf - Methodenzeiger?") bzw. R_OUT_HEADS.
  Src := Join(['unit t;', 'interface', 'implementation',
    'procedure Flag(var P: Integer; out Ch: Cardinal); overload;', 'begin',
    '  Ch := 0;', 'end;', 'procedure Flag(out Ch: Cardinal); overload;',
    'begin', '  Ch := 1;', 'end;', 'procedure Flag; overload;', 'begin',
    'end;', 'procedure Use(B: Byte);', 'var', '  C: Cardinal;', 'begin',
    '  if B = 0 then Flag;', '  case B of', '    1..2: Flag;', '  end;',
    '  Flag(C);', 'end;', 'end.']);
  Assert.AreEqual(StringReplace(Src, 'procedure Flag(out Ch',
    'procedure Flag(var Ch', []), Fix(Src, 'procedure Flag(out Ch', P));
  // Gegenproben: ein Overload mit derselben Zahl, ein Zeiger auf Flag.
  AssertRefused(StringReplace(Src, 'procedure Flag; overload;',
    'procedure Flag(out S: string); overload;', []),
    'procedure Flag(out Ch', _(R_OUT_HEADS, [2, 'Flag']));
  AssertRefused(StringReplace(Src, '  Flag(C);', '  Run(@Flag);', []),
    'procedure Flag(out Ch', _(R_OUT_REFERENCE, ['Flag', 23]));
end;

{$IFNDEF FPC}

{ ---- Detektor ---- }

// Die Funde der Art SCA086 - der echte Detektor auf dem echten AST.
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TAvoidOutDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_out_', ASource, fkAvoidOut, RunDetector);
end;

// Detect in der Form TDetectFunc (FixAllWith).
function DetectKind(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := DetectSource('rdx_out_', ASource, AKind, RunDetector);
end;

// Die Hilfe fuer einen Fund (Zeile und Meldung wie vom Detektor) ueber den
// Einstieg der Tabelle (PlanFixIn: TRdxFixTable.FixFor, Adapter
// PlanAvoidOut).
function PlanSeen(const ASource: string; const ASeen: TSeen): TRdxFixOutcome;
begin
  Result := PlanFixIn(ASource, 't.pas', fkAvoidOut, ASeen);
end;

// Fund fuer Fund, nach jeder Ersetzung neu gemeldet, bis der Detektor
// schweigt (FixAllWith: ueber den Einstieg der Tabelle).
function FixAll(const ASource: string): string;
begin
  Result := FixAllWith(ASource, fkAvoidOut, DetectKind);
end;

procedure TTestRdxAvoidOutDetector.Detector_ReportsDeclAndImpl;
var
  Src  : string;
  Seen : TArray<TSeen>;
begin
  Src := GetUnit('class', ['  private', '    procedure Get(out S: string);']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(2, Length(Seen), 'Deklaration und Implementierung');
  Assert.AreEqual<Integer>(LineOf(Src, 'procedure Get('), Seen[0].Line);
  Assert.AreEqual<Integer>(Pos('out ', LineText(Src, Seen[0].Line)),
    ColumnFromMessage(Seen[0].Msg), 'Spalte des out');
  Assert.AreEqual<Integer>(LineOf(Src, 'TFoo.Get('), Seen[1].Line);
end;

procedure TTestRdxAvoidOutDetector.Detector_RoundTrip;
var
  Src, Fixed : string;
begin
  Src := GetUnit('class', ['  private', '    procedure Get(out S: string);']);
  Fixed := FixAll(Src);
  Assert.AreEqual(StringReplace(Src, 'out S', 'var S', [rfReplaceAll]), Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed)), 'der Detektor schweigt');
end;

procedure TTestRdxAvoidOutDetector.Detector_ImplFinding_FixesBoth;
var
  Src  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  Src := GetUnit('class', ['  private', '    procedure Get(out S: string);']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(2, Length(Seen));
  O := PlanSeen(Src, Seen[1]);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual(StringReplace(Src, 'out S', 'var S', [rfReplaceAll]),
    Apply(Src, O.Edits));
end;

procedure TTestRdxAvoidOutDetector.Detector_CatalogExample_Fixed;
var
  Meta : TRuleMeta;
  Src  : string;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkAvoidOut);
  Assert.IsTrue(Pos('out S', Meta.BadExample) > 0, Meta.BadExample);
  // Das Beispiel als Kopf einer Routine des implementation-Teils, dazu der
  // Rumpf - im interface-Teil waere sie exportiert und gesperrt (rwE29).
  Src := Join(['unit t;', 'interface', 'implementation']) + #13#10
    + CatalogText(Meta.BadExample) + #13#10 + Join(['begin', '  S := '''';',
    'end;', 'end.']);
  Assert.AreEqual(Join(['unit t;', 'interface', 'implementation']) + #13#10
    + CatalogText(Meta.GoodExample) + #13#10 + Join(['begin', '  S := '''';',
    'end;', 'end.']), FixAll(Src));
end;

procedure TTestRdxAvoidOutDetector.Detector_Virtual_NoHelp;
var
  Src  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  // virtual meldet der Detektor (nur override nimmt er aus) - die Hilfe
  // sperrt: Erben ueberschreiben die Signatur mit out.
  Src := GetUnit('class', ['  private',
    '    procedure Get(out S: string); virtual;']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(2, Length(Seen), 'der Detektor meldet');
  O := PlanSeen(Src, Seen[0]);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_OUT_DIRECTIVE, ['Get', 'virtual']), O.Reason);
end;

procedure TTestRdxAvoidOutDetector.Detector_InterfaceMethod_NoHelp;
var
  Src  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  Src := Join(['unit t;', 'interface', 'type', '  IFoo = interface',
    '    procedure Get(out S: string);', '  end;', 'implementation', 'end.']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen), 'der Detektor meldet');
  O := PlanSeen(Src, Seen[0]);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_OUT_IN_TYPE, ['Get']), O.Reason);
end;

procedure TTestRdxAvoidOutDetector.Detector_StaleFinding_NoHelp;
var
  Src  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  // Der Fund stammt aus dem Text vor einer eingefuegten Zeile.
  Src := GetUnit('class', ['  private', '    procedure Get(out S: string);']);
  Seen := Detect(Src);
  Assert.IsTrue(Length(Seen) > 0);
  Src := StringReplace(Src, 'interface', 'interface'#13#10, []);
  O := PlanSeen(Src, Seen[0]);
  Assert.IsFalse(O.Enabled, 'gesperrt');
  Assert.AreEqual(MsgMovedSuffix(_(R_OUT_MOVED)), O.Reason);
  Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
end;

// Die Hilfe fuer den ersten Fund (die Deklaration) in ASource.
function PlanFirst(const ASource: string): TRdxFixOutcome;
var
  Seen : TArray<TSeen>;
begin
  Seen := Detect(ASource);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet');
  Result := PlanSeen(ASource, Seen[0]);
end;

procedure TTestRdxAvoidOutDetector.Table_PlainType_SameMeaning;
var
  O : TRdxFixOutcome;
begin
  // Integer: Delphi behandelt out wie var - bedeutungsgleich, der Hinweis
  // des einfachen Typs (Adapter, HintByPlanner).
  O := PlanFirst(ClassUnit('class', ['  private',
    '    procedure Get(out N: Integer);'], ['procedure TFoo.Get(out N: Integer);',
    'begin', '  N := 1;', 'end;']));
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual('N', O.Name, 'Name ist der Parameter');
  Assert.IsFalse(O.ChangesBehavior, 'bedeutungsgleich');
  // de.po traegt echte Umlaute (Charge G7) - hier als #$-Code.
  Assert.AreEqual('gleiche Bedeutung - f'#$00FC'r diesen einfachen '
    + 'Typ behandelt '
    + 'Delphi out wie var; Deklaration und Implementierung zusammen', O.Hint);
  Assert.AreEqual<Integer>(2, Length(O.Edits), 'Deklaration und Rumpf');
end;

procedure TTestRdxAvoidOutDetector.Table_ManagedType_Marked;
var
  O : TRdxFixOutcome;
begin
  // string: out gab den Wert beim Aufruf frei - gekennzeichnet (E2), der
  // Hinweis des verwalteten Typs.
  O := PlanFirst(GetUnit('class', ['  private',
    '    procedure Get(out S: string);']));
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual('S', O.Name, 'Name ist der Parameter');
  Assert.IsTrue(O.ChangesBehavior, 'gekennzeichnet');
  Assert.AreEqual<Integer>(1, Pos('out gab den Wert des Aufrufers beim '
    + 'Aufruf frei', O.Hint), O.Hint);
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxAvoidOutFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxAvoidOutDetector);
  {$ENDIF}

end.
