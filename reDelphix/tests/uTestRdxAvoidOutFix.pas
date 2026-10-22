unit uTestRdxAvoidOutFix;

// Editorhilfe SCA086 AvoidOut (uRdxAvoidOutFix): der Planer auf Text (erste
// Fixture, FPC-tauglich) und der ECHTE Detektor (uAvoidOut) auf dem echten
// AST mit dem Planer (zweite Fixture, nur Delphi). Die Tabelle
// (uRdxFixTable) kennt die Hilfe erst nach der Integration - die Tests rufen
// den Planer ohne sie. Die Spalte ist die des ersten 'out ' der Zeile.

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
    [Test] procedure InterfaceRoutine_Paired;
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
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uAvoidOut,
  uTestRdxDetectorKit,   // TSeen, DetectSource, CatalogText
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxAvoidOutFix,
  uRdxText,              // _() und die gemeinsamen Gruende
  uTestRdxTextKit;       // Join, Apply, LineOf

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
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    try
      Result := TRdxAvoidOutFix.OutToVar(Map, ALine, MessageAt(ACol), APlan,
        AReason);
    finally
      Map.Free;
    end;
  finally
    SL.Free;
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
  Src := GetUnit('class', ['  public', '    procedure Get(out S: string);']);
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
  Src := ClassUnit('class', ['  public', '    procedure Get(out N: Integer);'],
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
  Src := ClassUnit('class', ['  public', '    procedure Get(out S: string);'],
    ['procedure TFoo.Get;', 'begin', '  S := ''x'';', 'end;']);
  Assert.AreEqual(StringReplace(Src, 'out S', 'var S', []),
    Fix(Src, 'procedure Get(', P));
  Assert.AreEqual<Integer>(1, Length(P.Edits), 'nur die Deklaration');
end;

procedure TTestRdxAvoidOutFix.InterfaceRoutine_Paired;
var
  Src : string;
  P   : TRdxOutPlan;
begin
  Src := Join(['unit t;', 'interface', 'procedure Load(out Count: Integer);',
    'implementation', 'procedure Load(out Count: Integer);', 'begin',
    '  Count := 1;', 'end;', 'end.']);
  Assert.AreEqual(StringReplace(Src, 'out Count', 'var Count', [rfReplaceAll]),
    Fix(Src, 'procedure Load(', P));
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
  Src := ClassUnit('class', ['  public', '    procedure Get(out A, B: string);'],
    ['procedure TFoo.Get(out A, B: string);', 'begin', 'end;']);
  Assert.AreEqual(StringReplace(Src, 'out A', 'var A', [rfReplaceAll]),
    Fix(Src, 'procedure Get(', P));
  Assert.AreEqual('A', P.Name);
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
  Src := GetUnit('class', ['  public', '    procedure Get(out S: string);']);
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
  AssertRefused(ClassUnit('class', ['  public', '    procedure Get(out Obj);'],
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
  AssertRefused(ClassUnit('class', ['  public',
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
  AssertRefused(GetUnit('class', ['  public',
    '    procedure Get(out S: string); virtual;']), 'procedure Get(',
    _(R_OUT_DIRECTIVE, ['Get', 'virtual']));
  AssertRefused(Join(['unit t;', 'interface',
    'procedure Load(out Count: Integer); stdcall;', 'implementation',
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
  AssertRefused(GetUnit('class(TInterfacedObject, IFoo)', ['  public',
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
  AssertRefused(ClassUnit('class', ['  public',
    '    procedure Get(out A, B: string);'],
    ['procedure TFoo.Get(out A: string; out B: string);', 'begin', 'end;']),
    'procedure Get(', _(R_OUT_MISMATCH, ['Get', 'A']));
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

// Der Planer fuer einen Fund (Zeile und Meldung wie vom Detektor).
function PlanSeen(const ASource: string; const ASeen: TSeen;
  out APlan: TRdxOutPlan; out AReason: string): Boolean;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    try
      Result := TRdxAvoidOutFix.OutToVar(Map, ASeen.Line, ASeen.Msg, APlan,
        AReason);
    finally
      Map.Free;
    end;
  finally
    SL.Free;
  end;
end;

// Fund fuer Fund, nach jeder Ersetzung neu gemeldet, bis der Detektor
// schweigt.
function FixAll(const ASource: string): string;
const
  MAX_PASSES = 10;
var
  Pass : Integer;
  Seen : TArray<TSeen>;
  P    : TRdxOutPlan;
  R    : string;
begin
  Result := ASource;
  for Pass := 1 to MAX_PASSES do
  begin
    Seen := Detect(Result);
    if Length(Seen) = 0 then
      Exit;
    Assert.IsTrue(PlanSeen(Result, Seen[0], P, R),
      Format('Zeile %d: %s', [Seen[0].Line, R]));
    Result := Apply(Result, P.Edits);
  end;
  Assert.Fail('der Detektor schweigt auch nach zehn Durchlaeufen nicht');
end;

procedure TTestRdxAvoidOutDetector.Detector_ReportsDeclAndImpl;
var
  Src  : string;
  Seen : TArray<TSeen>;
begin
  Src := GetUnit('class', ['  public', '    procedure Get(out S: string);']);
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
  Src := GetUnit('class', ['  public', '    procedure Get(out S: string);']);
  Fixed := FixAll(Src);
  Assert.AreEqual(StringReplace(Src, 'out S', 'var S', [rfReplaceAll]), Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed)), 'der Detektor schweigt');
end;

procedure TTestRdxAvoidOutDetector.Detector_ImplFinding_FixesBoth;
var
  Src  : string;
  Seen : TArray<TSeen>;
  P    : TRdxOutPlan;
  R    : string;
begin
  Src := GetUnit('class', ['  public', '    procedure Get(out S: string);']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(2, Length(Seen));
  Assert.IsTrue(PlanSeen(Src, Seen[1], P, R), R);
  Assert.AreEqual(StringReplace(Src, 'out S', 'var S', [rfReplaceAll]),
    Apply(Src, P.Edits));
end;

procedure TTestRdxAvoidOutDetector.Detector_CatalogExample_Fixed;
var
  Meta : TRuleMeta;
  Src  : string;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkAvoidOut);
  Assert.IsTrue(Pos('out S', Meta.BadExample) > 0, Meta.BadExample);
  // Das Beispiel als Deklaration im interface-Teil, dazu der Rumpf.
  Src := Join(['unit t;', 'interface']) + #13#10 + CatalogText(Meta.BadExample)
    + #13#10 + Join(['implementation', 'procedure Foo(out S: string);',
    'begin', '  S := '''';', 'end;', 'end.']);
  Assert.AreEqual(Join(['unit t;', 'interface']) + #13#10
    + CatalogText(Meta.GoodExample) + #13#10 + Join(['implementation',
    'procedure Foo(var S: string);', 'begin', '  S := '''';', 'end;', 'end.']),
    FixAll(Src));
end;

procedure TTestRdxAvoidOutDetector.Detector_Virtual_NoHelp;
var
  Src  : string;
  Seen : TArray<TSeen>;
  P    : TRdxOutPlan;
  R    : string;
begin
  // virtual meldet der Detektor (nur override nimmt er aus) - die Hilfe
  // sperrt: Erben ueberschreiben die Signatur mit out.
  Src := GetUnit('class', ['  public',
    '    procedure Get(out S: string); virtual;']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(2, Length(Seen), 'der Detektor meldet');
  Assert.IsFalse(PlanSeen(Src, Seen[0], P, R), 'keine Hilfe');
  Assert.AreEqual(_(R_OUT_DIRECTIVE, ['Get', 'virtual']), R);
end;

procedure TTestRdxAvoidOutDetector.Detector_InterfaceMethod_NoHelp;
var
  Src  : string;
  Seen : TArray<TSeen>;
  P    : TRdxOutPlan;
  R    : string;
begin
  Src := Join(['unit t;', 'interface', 'type', '  IFoo = interface',
    '    procedure Get(out S: string);', '  end;', 'implementation', 'end.']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen), 'der Detektor meldet');
  Assert.IsFalse(PlanSeen(Src, Seen[0], P, R), 'keine Hilfe');
  Assert.AreEqual(_(R_OUT_IN_TYPE, ['Get']), R);
end;

procedure TTestRdxAvoidOutDetector.Detector_StaleFinding_NoHelp;
var
  Src  : string;
  Seen : TArray<TSeen>;
  P    : TRdxOutPlan;
  R    : string;
begin
  // Der Fund stammt aus dem Text vor einer eingefuegten Zeile.
  Src := GetUnit('class', ['  public', '    procedure Get(out S: string);']);
  Seen := Detect(Src);
  Assert.IsTrue(Length(Seen) > 0);
  Src := StringReplace(Src, 'interface', 'interface'#13#10, []);
  Assert.IsFalse(PlanSeen(Src, Seen[0], P, R), 'gesperrt');
  Assert.AreEqual(MsgMovedSuffix(_(R_OUT_MOVED)), R);
  Assert.AreEqual<Integer>(0, Length(P.Edits), 'keine Ersetzung');
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxAvoidOutFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxAvoidOutDetector);
  {$ENDIF}

end.
