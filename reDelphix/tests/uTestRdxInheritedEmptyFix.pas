unit uTestRdxInheritedEmptyFix;

// Editorhilfe SCA125 InheritedMethodEmpty (uRdxInheritedEmptyFix, Charge
// A4): der Planer auf Text (erste Fixture, FPC-tauglich) und - nur Delphi -
// der Einstieg der Tabelle (TRdxFixTable.FixFor via PlanFixIn/FixAllWith,
// Adapter PlanInheritedMethodEmpty: zwei Ersetzungen) mit dem ECHTEN
// Detektor (uInheritedMethodEmpty, liest den Quelltext) auf dem echten AST
// (zweite Fixture). Die Fixtures sind Units mit TBase und TFoo(TBase)
// (UnitWith); die gemeldete Zeile ist die des Implementierungskopfs
// (LineStartingWith).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxInheritedEmptyFix = class
  public
    // ---- Umformung ----
    [Test] procedure BareInherited_DeclAndImplGone;
    [Test] procedure PublicOverPublic_NamedArgs_Gone;
    [Test] procedure FunctionResultAssign_Gone;
    [Test] procedure ImplWithoutParamList_Gone;
    [Test] procedure DocAndNamingComment_GoAlong;
    [Test] procedure AncestorTwoLevelsUp_Gone;
    [Test] procedure NarrowerThanAncestor_Gone;
    // ---- Gegenproben ----
    [Test] procedure AncestorNotInFile_NoHelp;
    [Test] procedure NoHeritage_TObject_NoHelp;
    [Test] procedure WidensVisibility_NoHelp;
    [Test] procedure AncestorAbstract_NoHelp;
    [Test] procedure OtherDirective_NoHelp;
    [Test] procedure Attribute_NoHelp;
    [Test] procedure DefaultParameter_NoHelp;
    [Test] procedure BodyNotPassThrough_NoHelp;
    [Test] procedure CommentInMethod_NoHelp;
    [Test] procedure DirectiveInMethod_NoHelp;
    [Test] procedure LocalsOrClassMethod_NoHelp;
    [Test] procedure OverloadOrMovedLine_NoHelp;
    [Test] procedure MessageWithoutName_NoHelp;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxInheritedEmptyDetector = class
  public
    // ---- Einstieg der Tabelle (Adapter PlanInheritedMethodEmpty) ----
    [Test] procedure Adapter_TwoEditsAndName;
    [Test] procedure Adapter_Refused_NameStays;
    // ---- echter Detektor ----
    [Test] procedure Detector_ReportsImplementationHeader;
    [Test] procedure Detector_RoundTrip;
    [Test] procedure Detector_AncestorOutsideUnit_NoHelp;
    [Test] procedure Detector_WidensVisibility_NoFinding;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uInheritedMethodEmpty,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uRdxFixTable,          // TRdxFixTable.CaptionFor
  uTestRdxDetectorKit,   // TSeen, DetectSource, PlanFixIn, FixAllWith
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxRoutineFixes, uRdxInheritedEmptyFix,
  uRdxText,              // _() und die gemeinsamen Gruende
  uTestRdxTextKit;       // Join, Apply, LineOf, LineStartingWith, NewMap

const
  BASE_PAINT = '    procedure Paint; virtual;';
  FOO_PAINT  = '    procedure Paint; override;';
  BASE_IMPL: array[0..3] of string = ('procedure TBase.Paint;', 'begin',
    '  Beep;', 'end;');
  FOO_IMPL: array[0..3] of string = ('procedure TFoo.Paint;', 'begin',
    '  inherited;', 'end;');
  PAINT_HEAD = 'procedure TFoo.Paint';
  // Die Meldung des Detektors (uInheritedMethodEmpty, fcHigh).
  MSG_FMT = 'Override %s contains only "inherited" - remove the override '
    + 'entirely';

// ---- Helfer ----

// Eine Unit: TBase mit Rumpf ABase, TFoo(TBase) mit Rumpf AFoo, dann die
// Implementierungen AImpl.
function UnitWith(const ABase, AFoo, AImpl: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'type', '  TBase = class']) + #13#10
    + Join(ABase) + #13#10 + Join(['  end;', '  TFoo = class(TBase)'])
    + #13#10 + Join(AFoo) + #13#10 + Join(['  end;', 'implementation'])
    + #13#10 + Join(AImpl) + #13#10 + 'end.';
end;

// Die Grundform: Paint protected in beiden, TFoo.Paint nur 'inherited;'.
function PaintUnit(const AFooImpl: array of string): string;
begin
  Result := UnitWith(['  protected', BASE_PAINT], ['  protected', FOO_PAINT],
    BASE_IMPL) ;
  Result := StringReplace(Result, #13#10 + 'end.', #13#10 + Join(AFooImpl)
    + #13#10 + 'end.', []);
end;

// Dieselbe Unit nach der Hilfe: TFoo ohne Paint, nur TBase.Paint.
function PaintUnitAfter: string;
begin
  Result := UnitWith(['  protected', BASE_PAINT], ['  protected'], BASE_IMPL);
end;

function MsgFor(const AMeth: string): string;
begin
  Result := Format(MSG_FMT, [AMeth]);
end;

// Der Planer fuer Zeile ALine und Meldung AMsg: der neue Text, oder '' bei
// Ablehnung (AReason).
function PlanAt(const ASource: string; ALine: Integer; const AMsg: string;
  out AReason: string): string;
var
  Map : TRdxCodeMap;
  P   : TRdxRoutinePlan;
  Ok  : Boolean;
begin
  Result := '';
  AReason := '';
  Map := NewMap(ASource);
  try
    Ok := TRdxInheritedEmptyFix.DeleteOverride(Map, ALine, AMsg, P, AReason);
  finally
    Map.Free;
  end;
  if Ok then
    Result := Apply(ASource, P.Edits);
end;

// Der Planer fuer den Kopf, der mit AHeadStart beginnt, Meldung zu AMeth.
function Plan(const ASource, AHeadStart, AMeth: string;
  out AReason: string): string;
var
  Line : Integer;
begin
  Line := LineStartingWith(ASource, AHeadStart);
  Assert.IsTrue(Line > 0, 'Kopf ' + AHeadStart);
  Result := PlanAt(ASource, Line, MsgFor(AMeth), AReason);
end;

// Die Hilfe muss gelten (sonst scheitert der Test mit dem Grund).
function Applied(const ASource: string; const AHeadStart: string = PAINT_HEAD;
  const AMeth: string = 'Paint'): string;
var
  R : string;
begin
  Result := Plan(ASource, AHeadStart, AMeth, R);
  Assert.IsTrue(Result <> '', R);
end;

procedure AssertRefused(const ASource, AReason: string;
  const AHeadStart: string = PAINT_HEAD; const AMeth: string = 'Paint');
var
  R : string;
begin
  Assert.AreEqual('', Plan(ASource, AHeadStart, AMeth, R), 'keine Hilfe');
  Assert.AreEqual(AReason, R, 'Grund');
end;

// ---- Umformung ----

procedure TTestRdxInheritedEmptyFix.BareInherited_DeclAndImplGone;
begin
  // Deklaration und Implementierung in einem Schritt weg; der leere
  // Abschnitt bleibt (SCA087 hat eine eigene Hilfe).
  Assert.AreEqual(PaintUnitAfter, Applied(PaintUnit(FOO_IMPL)));
  // Ohne ';' vor 'end' (Korpus: Lazarus intfgraphics) ebenso.
  Assert.AreEqual(PaintUnitAfter, Applied(PaintUnit(['procedure TFoo.Paint;',
    'begin', '  inherited', 'end;'])));
end;

procedure TTestRdxInheritedEmptyFix.PublicOverPublic_NamedArgs_Gone;
const
  BASE_MOVE = '    procedure MoveBy(ALeft, ATop: Integer); virtual;';
  BASE_MOVE_IMPL: array[0..3] of string = (
    'procedure TBase.MoveBy(ALeft, ATop: Integer);', 'begin', '  Beep;',
    'end;');
begin
  Assert.AreEqual(UnitWith(['  public', BASE_MOVE], ['  public'],
    BASE_MOVE_IMPL),
    Applied(UnitWith(['  public', BASE_MOVE], ['  public',
      '    procedure MoveBy(ALeft, ATop: Integer); override;'],
      ['procedure TBase.MoveBy(ALeft, ATop: Integer);', 'begin', '  Beep;',
      'end;', 'procedure TFoo.MoveBy(ALeft, ATop: Integer);', 'begin',
      '  inherited MoveBy(ALeft, ATop);', 'end;']),
      'procedure TFoo.MoveBy', 'MoveBy'));
end;

procedure TTestRdxInheritedEmptyFix.FunctionResultAssign_Gone;
const
  BASE_GET = '    function GetText(Index: Integer): string; virtual;';
  BASE_GET_IMPL: array[0..3] of string = (
    'function TBase.GetText(Index: Integer): string;', 'begin',
    '  Result := '''';', 'end;');

  function GetUnit(const ABody: string): string;
  begin
    Result := UnitWith(['  protected', BASE_GET], ['  protected',
      '    function GetText(Index: Integer): string; override;'],
      ['function TBase.GetText(Index: Integer): string;', 'begin',
      '  Result := '''';', 'end;',
      'function TFoo.GetText(Index: Integer): string;', 'begin', ABody,
      'end;']);
  end;

begin
  Assert.AreEqual(UnitWith(['  protected', BASE_GET], ['  protected'],
    BASE_GET_IMPL), Applied(GetUnit('  Result := inherited GetText(Index);'),
    'function TFoo.GetText', 'GetText'));
  Assert.AreEqual(UnitWith(['  protected', BASE_GET], ['  protected'],
    BASE_GET_IMPL), Applied(GetUnit('  Result := inherited;'),
    'function TFoo.GetText', 'GetText'));
end;

procedure TTestRdxInheritedEmptyFix.ImplWithoutParamList_Gone;
const
  BASE_RESIZE = '    procedure Resize(AWidth: Integer); virtual;';
  BASE_RESIZE_IMPL: array[0..3] of string = (
    'procedure TBase.Resize(AWidth: Integer);', 'begin', '  Beep;', 'end;');
begin
  // Der Kopf ohne Parameterliste nimmt die der Deklaration.
  Assert.AreEqual(UnitWith(['  protected', BASE_RESIZE], ['  protected'],
    BASE_RESIZE_IMPL),
    Applied(UnitWith(['  protected', BASE_RESIZE], ['  protected',
      '    procedure Resize(AWidth: Integer); override;'],
      ['procedure TBase.Resize(AWidth: Integer);', 'begin', '  Beep;', 'end;',
      'procedure TFoo.Resize;', 'begin', '  inherited Resize(AWidth);',
      'end;']), 'procedure TFoo.Resize', 'Resize'));
end;

procedure TTestRdxInheritedEmptyFix.DocAndNamingComment_GoAlong;
begin
  // '///' ueber der Deklaration und ein Kommentar, der die Methode nennt,
  // ueber der Implementierung gehen mit (wie bei SCA147).
  Assert.AreEqual(PaintUnitAfter,
    Applied(StringReplace(PaintUnit(['// TFoo.Paint: repaint as the base',
      'procedure TFoo.Paint;', 'begin', '  inherited;', 'end;']), FOO_PAINT,
      '    /// <summary>Paints.</summary>' + #13#10 + FOO_PAINT, [])));
end;

procedure TTestRdxInheritedEmptyFix.AncestorTwoLevelsUp_Gone;
var
  Before, After : string;
begin
  // TMid deklariert Paint nicht - der Vorfahr dahinter zaehlt.
  Before := StringReplace(PaintUnit(FOO_IMPL), '  TFoo = class(TBase)',
    Join(['  TMid = class(TBase)', '  public', '    procedure Other;',
    '  end;', '  TFoo = class(TMid)']), []);
  After := StringReplace(PaintUnitAfter, '  TFoo = class(TBase)',
    Join(['  TMid = class(TBase)', '  public', '    procedure Other;',
    '  end;', '  TFoo = class(TMid)']), []);
  Assert.AreEqual(After, Applied(Before));
end;

procedure TTestRdxInheritedEmptyFix.NarrowerThanAncestor_Gone;
begin
  // private ueber protected: das Loeschen macht die Methode nur
  // sichtbarer - kein Aufrufer bricht.
  Assert.AreEqual(UnitWith(['  protected', BASE_PAINT], ['  private'],
    BASE_IMPL),
    Applied(StringReplace(PaintUnit(FOO_IMPL), '  protected' + #13#10
      + FOO_PAINT, '  private' + #13#10 + FOO_PAINT, [])));
end;

// ---- Gegenproben ----

procedure TTestRdxInheritedEmptyFix.AncestorNotInFile_NoHelp;
begin
  // Der haeufigste Fall im Korpus: der Vorfahr steht in einer anderen
  // Unit - die Sichtbarkeit seiner Methode ist nicht belegt.
  AssertRefused(StringReplace(PaintUnit(FOO_IMPL), 'TFoo = class(TBase)',
    'TFoo = class(TControl)', []),
    _(R_IE_VIS_UNPROVEN, ['TControl', MsgCheckByHand]));
end;

procedure TTestRdxInheritedEmptyFix.NoHeritage_TObject_NoHelp;
begin
  AssertRefused(Join(['unit t;', 'interface', 'type', '  TFoo = class',
    '  public', '    destructor Destroy; override;', '  end;',
    'implementation', 'destructor TFoo.Destroy;', 'begin',
    '  inherited Destroy;', 'end;', 'end.']),
    _(R_IE_VIS_UNPROVEN, ['TObject', MsgCheckByHand]), 'destructor TFoo.Destroy',
    'Destroy');
end;

procedure TTestRdxInheritedEmptyFix.WidensVisibility_NoHelp;
begin
  // public ueber protected (TButton.Click): Loeschen braeche Aufrufer.
  AssertRefused(UnitWith(['  protected', BASE_PAINT], ['  public', FOO_PAINT],
    ['procedure TBase.Paint;', 'begin', '  Beep;', 'end;',
    'procedure TFoo.Paint;', 'begin', '  inherited;', 'end;']),
    _(R_IE_VIS_WIDENS, ['public', 'TBase', 'protected']));
  // protected ueber strict protected: die Unit verloere den Zugriff.
  AssertRefused(UnitWith(['  strict protected', BASE_PAINT],
    ['  protected', FOO_PAINT], ['procedure TBase.Paint;', 'begin', '  Beep;',
    'end;', 'procedure TFoo.Paint;', 'begin', '  inherited;', 'end;']),
    _(R_IE_VIS_WIDENS, ['protected', 'TBase', 'strict protected']));
end;

procedure TTestRdxInheritedEmptyFix.AncestorAbstract_NoHelp;
begin
  AssertRefused(UnitWith(['  protected', '    procedure Paint; virtual; '
    + 'abstract;'], ['  protected', FOO_PAINT], FOO_IMPL),
    _(R_IE_ANC_ABSTRACT, ['TBase']));
end;

procedure TTestRdxInheritedEmptyFix.OtherDirective_NoHelp;
begin
  // 'final' versiegelt die Methode - das Loeschen hoebe die Sperre auf.
  AssertRefused(StringReplace(PaintUnit(FOO_IMPL), FOO_PAINT,
    '    procedure Paint; override; final;', []),
    _(R_IE_DIRECTIVE, ['final']));
end;

procedure TTestRdxInheritedEmptyFix.Attribute_NoHelp;
begin
  AssertRefused(StringReplace(PaintUnit(FOO_IMPL), FOO_PAINT,
    '    [MVCPath(''/paint'')]' + #13#10 + FOO_PAINT, []), _(R_IE_ATTR));
end;

procedure TTestRdxInheritedEmptyFix.DefaultParameter_NoHelp;
begin
  AssertRefused(UnitWith(['  protected',
    '    procedure Scroll(Delta: Integer = 1); virtual;'], ['  protected',
    '    procedure Scroll(Delta: Integer = 1); override;'],
    ['procedure TBase.Scroll(Delta: Integer);', 'begin', '  Beep;', 'end;',
    'procedure TFoo.Scroll(Delta: Integer);', 'begin',
    '  inherited Scroll(Delta);', 'end;']), _(R_IE_DEFAULT),
    'procedure TFoo.Scroll', 'Scroll');
end;

procedure TTestRdxInheritedEmptyFix.BodyNotPassThrough_NoHelp;
var
  Stale : string;

  function ResizeUnit(const ABody: string): string;
  begin
    Result := UnitWith(['  protected',
      '    procedure Resize(AWidth: Integer); virtual;'], ['  protected',
      '    procedure Resize(AWidth: Integer); override;'],
      ['procedure TBase.Resize(AWidth: Integer);', 'begin', '  Beep;', 'end;',
      'procedure TFoo.Resize(AWidth: Integer);', 'begin', ABody, 'end;']);
  end;

begin
  Stale := MsgStaleSuffix(_(R_IE_BODY));
  // weitere Anweisung, andere Methode, anderes Argument
  AssertRefused(PaintUnit(['procedure TFoo.Paint;', 'begin', '  inherited;',
    '  Beep;', 'end;']), Stale);
  AssertRefused(PaintUnit(['procedure TFoo.Paint;', 'begin',
    '  inherited Repaint;', 'end;']), Stale);
  AssertRefused(ResizeUnit('  inherited Resize(AWidth + 1);'), Stale,
    'procedure TFoo.Resize', 'Resize');
  // 'inherited Resize;' ruft die parameterlose Variante.
  AssertRefused(ResizeUnit('  inherited Resize;'), Stale,
    'procedure TFoo.Resize', 'Resize');
  // Funktion ohne Zuweisung: das Ergebnis des Vorfahren ginge verloren.
  AssertRefused(UnitWith(['  protected',
    '    function GetCount: Integer; virtual;'], ['  protected',
    '    function GetCount: Integer; override;'],
    ['function TBase.GetCount: Integer;', 'begin', '  Result := 0;', 'end;',
    'function TFoo.GetCount: Integer;', 'begin', '  inherited GetCount;',
    'end;']), Stale, 'function TFoo.GetCount', 'GetCount');
end;

procedure TTestRdxInheritedEmptyFix.CommentInMethod_NoHelp;
var
  Src : string;
begin
  Src := PaintUnit(['procedure TFoo.Paint;', 'begin',
    '  inherited; // keep the frame', 'end;']);
  AssertRefused(Src, _(R_IE_COMMENT, [LineOf(Src, '// keep the frame'),
    MsgDeleteByHand]));
end;

procedure TTestRdxInheritedEmptyFix.DirectiveInMethod_NoHelp;
begin
  AssertRefused(PaintUnit(['procedure TFoo.Paint;', 'begin',
    '  {$WARNINGS OFF}', '  inherited;', 'end;']), _(R_IE_DIRECTIVES));
end;

procedure TTestRdxInheritedEmptyFix.LocalsOrClassMethod_NoHelp;
begin
  AssertRefused(PaintUnit(['procedure TFoo.Paint;', 'var', '  X: Integer;',
    'begin', '  inherited;', 'end;']), _(R_IE_LOCALS));
  AssertRefused(UnitWith(['  protected', '    class procedure Paint; virtual;'],
    ['  protected', '    class procedure Paint; override;'],
    ['class procedure TBase.Paint;', 'begin', '  Beep;', 'end;',
    'class procedure TFoo.Paint;', 'begin', '  inherited;', 'end;']),
    _(R_IE_CLASS_METHOD), 'class procedure TFoo.Paint', 'Paint');
end;

procedure TTestRdxInheritedEmptyFix.OverloadOrMovedLine_NoHelp;
var
  Src : string;
  R   : string;
begin
  AssertRefused(StringReplace(PaintUnit(FOO_IMPL), FOO_PAINT,
    '    procedure Paint; overload; override;' + #13#10
    + '    procedure Paint(N: Integer); overload; override;', []),
    _(R_IE_DECLS, [2, 'Paint']));
  // Die Zeile darunter traegt keinen Kopf mehr.
  Src := PaintUnit(FOO_IMPL);
  Assert.AreEqual('', PlanAt(Src, LineStartingWith(Src, PAINT_HEAD) + 1,
    MsgFor('Paint'), R), 'keine Hilfe');
  Assert.AreEqual(MsgMovedSuffix(_(R_IE_NO_HEAD, ['Paint'])), R);
end;

procedure TTestRdxInheritedEmptyFix.MessageWithoutName_NoHelp;
var
  Src : string;
  R   : string;
begin
  Src := PaintUnit(FOO_IMPL);
  Assert.AreEqual('', PlanAt(Src, LineStartingWith(Src, PAINT_HEAD),
    'Method TFoo.Paint is empty', R), 'keine Hilfe');
  Assert.AreEqual(_(R_IE_MESSAGE), R);
  Assert.AreEqual('Paint', TRdxInheritedEmptyFix.MethodNameOf(MsgFor('Paint')));
end;

{$IFNDEF FPC}

{ ---- Einstieg der Tabelle und echter Detektor ---- }

// Die Funde der Art SCA125 - der echte Detektor auf dem echten AST (er
// liest Attribute und Direktiven aus der Datei, DetectSource schreibt sie).
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TInheritedMethodEmptyDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_ime_', ASource, fkInheritedMethodEmpty,
    RunDetector);
end;

// Dasselbe in der Form TDetectFunc (FixAllWith).
function DetectKind(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := DetectSource('rdx_ime_', ASource, AKind, RunDetector);
end;

// Die Hilfe fuer Zeile und Meldung ueber den Einstieg der Tabelle
// (PlanFixIn: TRdxFixTable.FixFor, Adapter PlanInheritedMethodEmpty).
function PlanVia(const ASource: string; ALine: Integer;
  const AMsg: string): TRdxFixOutcome;
var
  S : TSeen;
begin
  S := Default(TSeen);
  S.Line := ALine;
  S.Msg := AMsg;
  Result := PlanFixIn(ASource, 't.pas', fkInheritedMethodEmpty, S);
end;

// Die Hilfe fuer den ersten Fund des Detektors.
function PlanFirst(const ASource: string): TRdxFixOutcome;
var
  Seen : TArray<TSeen>;
begin
  Seen := Detect(ASource);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet einen Fund');
  Result := PlanVia(ASource, Seen[0].Line, Seen[0].Msg);
end;

procedure TTestRdxInheritedEmptyDetector.Adapter_TwoEditsAndName;
var
  Src : string;
  O   : TRdxFixOutcome;
begin
  Src := PaintUnit(FOO_IMPL);
  O := PlanVia(Src, LineStartingWith(Src, PAINT_HEAD), MsgFor('Paint'));
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual('Paint', O.Name, 'Name fuer den Menuetext');
  Assert.AreEqual<Integer>(2, Length(O.Edits), 'Deklaration und '
    + 'Implementierung');
  Assert.AreEqual(FOO_PAINT + #10, O.Edits[0].Expected,
    'die ganze Zeile der Deklaration (RangeText trennt mit #10)');
  Assert.AreEqual('', O.Edits[0].NewText);
  Assert.AreEqual<Integer>(LineStartingWith(Src, PAINT_HEAD),
    O.Edits[1].Span.StartLine);
  Assert.IsFalse(O.ChangesBehavior, 'bedeutungsgleich (Tabellenzeile)');
  Assert.IsTrue(O.Hint <> '', 'fester Hinweis');
  Assert.IsTrue(Pos('Paint', TRdxFixTable.CaptionFor(fkInheritedMethodEmpty,
    O)) > 0, 'der Menuetext nennt die Methode');
end;

procedure TTestRdxInheritedEmptyDetector.Adapter_Refused_NameStays;
var
  Src : string;
  O   : TRdxFixOutcome;
begin
  Src := StringReplace(PaintUnit(FOO_IMPL), 'TFoo = class(TBase)',
    'TFoo = class(TControl)', []);
  O := PlanVia(Src, LineStartingWith(Src, PAINT_HEAD), MsgFor('Paint'));
  Assert.IsFalse(O.Enabled, 'gesperrt');
  Assert.AreEqual(_(R_IE_VIS_UNPROVEN, ['TControl', MsgCheckByHand]),
    O.Reason);
  Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
  Assert.AreEqual('Paint', O.Name, 'der Name steht auch gesperrt');
end;

procedure TTestRdxInheritedEmptyDetector.Detector_ReportsImplementationHeader;
var
  Src  : string;
  Seen : TArray<TSeen>;
begin
  Src := PaintUnit(FOO_IMPL);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund (TBase.Paint ruft '
    + 'kein inherited)');
  Assert.AreEqual<Integer>(LineStartingWith(Src, PAINT_HEAD), Seen[0].Line,
    'Zeile des Implementierungskopfs');
  Assert.AreEqual(MsgFor('Paint'), Seen[0].Msg);
end;

procedure TTestRdxInheritedEmptyDetector.Detector_RoundTrip;
var
  Fixed : string;
begin
  Fixed := FixAllWith(PaintUnit(FOO_IMPL), fkInheritedMethodEmpty, DetectKind);
  Assert.AreEqual(PaintUnitAfter, Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed)), 'der Detektor schweigt');
end;

procedure TTestRdxInheritedEmptyDetector.Detector_AncestorOutsideUnit_NoHelp;
var
  Src : string;
  O   : TRdxFixOutcome;
begin
  // protected-Override ueber einem Vorfahren aus einer anderen Unit: der
  // Detektor meldet (fcHigh), die Hilfe sperrt - die Sichtbarkeit belegt
  // nur ein Vorfahr in der Datei.
  Src := StringReplace(PaintUnit(FOO_IMPL), 'TFoo = class(TBase)',
    'TFoo = class(TCustomControl)', []);
  O := PlanFirst(Src);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_IE_VIS_UNPROVEN, ['TCustomControl', MsgCheckByHand]),
    O.Reason);
end;

procedure TTestRdxInheritedEmptyDetector.Detector_WidensVisibility_NoFinding;
begin
  // public ueber protected in derselben Unit: das Override hebt an - der
  // Detektor meldet es nicht (Gegenstueck zu WidensVisibility_NoHelp).
  Assert.AreEqual<Integer>(0, Length(Detect(UnitWith(['  protected',
    BASE_PAINT], ['  public', FOO_PAINT], ['procedure TBase.Paint;', 'begin',
    '  Beep;', 'end;', 'procedure TFoo.Paint;', 'begin', '  inherited;',
    'end;']))));
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxInheritedEmptyFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxInheritedEmptyDetector);
  {$ENDIF}

end.
