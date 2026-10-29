unit uTestRdxMethodNameFix;

// Editorhilfe SCA106 MethodName (uRdxMethodNameFix): der Planer auf Text
// (erste Fixture) und der ECHTE Detektor (uMethodName) auf dem echten AST
// (zweite Fixture, nur Delphi). Den Adapter der Tabelle (PlanMethodName
// ueber TRdxFixFrame) traegt uRdxFixTable - die Rundlaeufe hier gehen ueber
// ihren Einstieg (TRdxFixTable.FixFor), wie der Anbieter.
// Die Standard-Unit (StdUnit) hat die Klasse TFoo ab Zeile 4, 'public' auf
// Zeile 5, die Deklaration auf Zeile 6 (DECL_LINE) und den Kopf der
// Implementierung auf Zeile 9 (IMPL_LINE).
//
// Realwelt-Test rwE29: published sperrt (Double Commander fFindDlg.pas:345
// 'cm_Start', umaincommands.pas:326 'cm_FileLinker' - die Kommandoliste
// filtert die published-Methodentabelle case-sensitiv mit 'cm_';
// PublishedMethod_NoHelp, gegen 7d5de210 rot: dort angeboten, bis dahin
// PublishedMethod_Capitalized). Der Abschnitt ohne Wort bleibt eine Hilfe
// (DefaultSection_Capitalized, auch vorher gruen). Nur die Implementierung
// gemeldet, die Deklaration schon gross (cnwizards DCURecs.pas:7864
// 'TDispPropDecl.visit'): die Implementierung bekommt die Schreibweise der
// Deklaration (ImplSpelling_OnlyImplementation, Detector_ImplOnly_Fixed -
// gegen 7d5de210 rot: R_MN_IMPL_ONLY).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxMethodNameFix = class
  public
    // ---- Umformung ----
    [Test] procedure DeclAndImpl_Capitalized;
    [Test] procedure ClassFunctionWithParams_Capitalized;
    [Test] procedure GenericClass_Capitalized;
    [Test] procedure NestedClass_Capitalized;
    [Test] procedure ImplAlreadyUpper_OnlyDeclaration;
    [Test] procedure CallsAndComments_Unchanged;
    [Test] procedure DefaultSection_Capitalized;
    [Test] procedure ImplSpelling_OnlyImplementation;
    [Test] procedure OtherClassSameName_Untouched;
    // ---- Gegenproben ----
    [Test] procedure Overload_NoHelp;
    [Test] procedure ConditionalTwins_NoHelp;
    [Test] procedure NoImplementation_NoHelp;
    [Test] procedure TwoImplementations_NoHelp;
    [Test] procedure RecordInterface_NoHelp;
    [Test] procedure MovedLine_NoHelp;
    [Test] procedure CommentOrString_NoHelp;
    [Test] procedure AlreadyCapitalized_NoHelp;
    [Test] procedure StringLiteral_NoHelp;
    [Test] procedure IncludeInClass_NoHelp;
    [Test] procedure MessageWithoutName_NoHelp;
    [Test] procedure ImplementationOnly_NoHelp;
    [Test] procedure PublishedMethod_NoHelp;
    [Test] procedure ImplSpelling_Overload_NoHelp;
    // rwE30 Stufe 2 (12 unnoetige Sperren): freie Routinen - alle Koepfe
    // gross; gesperrt, wo ein Linker oder C-Code den genauen Namen braucht.
    [Test] procedure FreeRoutine_DeclAndImpl_Capitalized;
    [Test] procedure FreeRoutine_ImplOnly_Capitalized;
    [Test] procedure FreeRoutine_BoundByName_NoHelp;
    [Test] procedure FreeRoutine_Twins_NoHelp;
    [Test] procedure FreeRoutine_ApiStyleName_NoHelp;
    // rwE30 Stufe 2: nur die Implementierung gemeldet, die Deklaration
    // beginnt auch klein - beide gross bzw. der richtige Grund.
    [Test] procedure ImplSpelling_LowerDecl_BothCapitalized;
    [Test] procedure ImplSpelling_LowerDecl_Published_Reason;
    // rwE30 Stufe 2: ein reiner Punktpfad im Literal ist eine Log-Kennung.
    [Test] procedure Literal_DottedPath_Helps;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxMethodNameDetector = class
  public
    [Test] procedure Detector_ReportsDeclarationLine;
    [Test] procedure Detector_RoundTrip;
    [Test] procedure Detector_TwoMethods_BothFixed;
    [Test] procedure Detector_ImplSpelledDifferently_Fixed;
    [Test] procedure Detector_ImplOnly_Fixed;
    [Test] procedure Detector_CatalogExample_InClass_Fixed;
    [Test] procedure Detector_CatalogExample_FreeRoutine_Fixed;
    [Test] procedure Detector_Overload_NoHelp;
    [Test] procedure Table_NameAndTwoEdits;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uMethodName,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uTestRdxDetectorKit,   // TSeen, DetectSource, CatalogText, PlanFixIn,
                         // FixAllWith
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxMethodNameFix,
  uRdxText,              // _() und die gemeinsamen Gruende
  uTestRdxTextKit;       // Join, Apply, LineOf, NewMap

const
  // Die Meldung des Detektors (uMethodName), Name als Argument.
  MSG_FMT = 'Method `%s` should be PascalCase (start with uppercase letter).';
  DECL_LINE = 6;
  IMPL_LINE = 9;

// ---- Helfer ----

// Eine Unit mit der Klasse TFoo: AMembers ab Zeile 5, dahinter 'end;',
// implementation und AImpl.
function UnitWith(const AMembers, AImpl: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'type', '  TFoo = class']) + #13#10
    + Join(AMembers) + #13#10 + Join(['  end;', 'implementation']) + #13#10
    + Join(AImpl) + #13#10 + 'end.';
end;

// TFoo mit 'procedure ADecl;' unter public (Zeile 6) und der
// Implementierung 'procedure TFoo.AImpl;' (Zeile 9).
function StdUnit(const ADecl, AImpl: string): string;
begin
  Result := UnitWith(['  public', '    procedure ' + ADecl + ';'],
    ['procedure TFoo.' + AImpl + ';', 'begin', 'end;']);
end;

// Der Planer fuer Zeile ALine mit der Meldung AMessage.
function PlanOf(const ASource: string; ALine: Integer; const AMessage: string;
  out APlan: TRdxMethodNamePlan; out AReason: string): Boolean;
var
  Map : TRdxCodeMap;
begin
  Map := NewMap(ASource);
  try
    Result := TRdxMethodNameFix.Capitalize(Map, ALine, AMessage, APlan,
      AReason);
  finally
    Map.Free;
  end;
end;

// Die Hilfe fuer den Namen AName auf ALine muss gelten; der neue Text.
function Applied(const ASource: string; ALine: Integer;
  const AName: string): string;
var
  P : TRdxMethodNamePlan;
  R : string;
begin
  Assert.IsTrue(PlanOf(ASource, ALine, Format(MSG_FMT, [AName]), P, R), R);
  Result := Apply(ASource, P.Edits);
end;

// Keine Hilfe fuer den Namen AName auf ALine, Grund AReason.
procedure AssertRefused(const ASource: string; ALine: Integer;
  const AName, AReason: string);
var
  P : TRdxMethodNamePlan;
  R : string;
begin
  Assert.IsFalse(PlanOf(ASource, ALine, Format(MSG_FMT, [AName]), P, R),
    'keine Hilfe');
  Assert.AreEqual(AReason, R, 'Grund');
  Assert.AreEqual<Integer>(0, Length(P.Edits), 'keine Ersetzung');
end;

// ---- Umformung ----

procedure TTestRdxMethodNameFix.DeclAndImpl_Capitalized;
var
  P : TRdxMethodNamePlan;
  R : string;
begin
  Assert.AreEqual(StdUnit('DoWork', 'DoWork'),
    Applied(StdUnit('doWork', 'doWork'), DECL_LINE, 'doWork'));
  // Zwei Ersetzungen in EINEM Plan, nur das Wort; der Name fuer den
  // Menuetext ist der neue.
  Assert.IsTrue(PlanOf(StdUnit('doWork', 'doWork'), DECL_LINE,
    Format(MSG_FMT, ['doWork']), P, R), R);
  Assert.AreEqual('DoWork', P.Name, 'Name fuer den Menuetext');
  Assert.AreEqual<Integer>(2, Length(P.Edits), 'Deklaration und Implementierung');
  Assert.AreEqual<Integer>(DECL_LINE, P.Edits[0].Span.StartLine);
  Assert.AreEqual<Integer>(IMPL_LINE, P.Edits[1].Span.StartLine);
  Assert.AreEqual('doWork', P.Edits[0].Expected);
  Assert.AreEqual('DoWork', P.Edits[0].NewText);
  Assert.AreEqual('doWork', P.Edits[1].Expected);
  Assert.AreEqual('DoWork', P.Edits[1].NewText);
end;

procedure TTestRdxMethodNameFix.ClassFunctionWithParams_Capitalized;
var
  Src : string;
begin
  // 'class' vor dem Routinenwort, Parameter und Rueckgabe.
  Src := UnitWith(['  public',
    '    class function calc(A, B: Integer): Integer;'],
    ['class function TFoo.calc(A, B: Integer): Integer;', 'begin',
     '  Result := A + B;', 'end;']);
  Assert.AreEqual(StringReplace(Src, 'calc(', 'Calc(', [rfReplaceAll]),
    Applied(Src, DECL_LINE, 'calc'));
end;

procedure TTestRdxMethodNameFix.GenericClass_Capitalized;
var
  Src : string;
begin
  Src := Join(['unit t;', 'interface', 'type', '  TFoo<T> = class',
    '  public', '    procedure doWork;', '  end;', 'implementation',
    'procedure TFoo<T>.doWork;', 'begin', 'end;', 'end.']);
  Assert.AreEqual(StringReplace(Src, 'doWork', 'DoWork', [rfReplaceAll]),
    Applied(Src, DECL_LINE, 'doWork'));
end;

procedure TTestRdxMethodNameFix.NestedClass_Capitalized;
var
  Src : string;
begin
  // Die Implementierung traegt beide Klassen ('TOuter.TInner.doWork').
  Src := Join(['unit t;', 'interface', 'type', '  TOuter = class',
    '  public', '    type', '      TInner = class', '      public',
    '        procedure doWork;', '      end;', '  end;', 'implementation',
    'procedure TOuter.TInner.doWork;', 'begin', 'end;', 'end.']);
  Assert.AreEqual(StringReplace(Src, 'doWork', 'DoWork', [rfReplaceAll]),
    Applied(Src, 9, 'doWork'));
end;

procedure TTestRdxMethodNameFix.ImplAlreadyUpper_OnlyDeclaration;
var
  P : TRdxMethodNamePlan;
  R : string;
begin
  // Delphi nimmt die Implementierung auch anders geschrieben an - beginnt
  // sie schon gross, bleibt es bei einer Ersetzung.
  Assert.AreEqual(StdUnit('DoWork', 'DoWork'),
    Applied(StdUnit('doWork', 'DoWork'), DECL_LINE, 'doWork'));
  Assert.IsTrue(PlanOf(StdUnit('doWork', 'DoWork'), DECL_LINE,
    Format(MSG_FMT, ['doWork']), P, R), R);
  Assert.AreEqual<Integer>(1, Length(P.Edits), 'nur die Deklaration');
  // Nur der erste Buchstabe: der Rest der Schreibweise bleibt.
  Assert.AreEqual(StdUnit('DoWork', 'Dowork'),
    Applied(StdUnit('doWork', 'dowork'), DECL_LINE, 'doWork'));
end;

procedure TTestRdxMethodNameFix.CallsAndComments_Unchanged;
begin
  // Aufrufe und Kommentare bleiben wie sie sind (Delphi bindet ohne
  // Gross/klein) - die Hilfe aendert nur die beiden Koepfe.
  Assert.AreEqual(
    UnitWith(['  public', '    procedure DoWork;', '    procedure Run;'],
      ['procedure TFoo.DoWork;', 'begin', 'end;', 'procedure TFoo.Run;',
       'begin', '  doWork; // doWork bleibt', '  Self.doWork;', 'end;']),
    Applied(
      UnitWith(['  public', '    procedure doWork;', '    procedure Run;'],
        ['procedure TFoo.doWork;', 'begin', 'end;', 'procedure TFoo.Run;',
         'begin', '  doWork; // doWork bleibt', '  Self.doWork;', 'end;']),
      DECL_LINE, 'doWork'));
end;

procedure TTestRdxMethodNameFix.DefaultSection_Capitalized;
begin
  // Der Abschnitt ohne Wort (published in TPersistent-Erben, die
  // Ereignis-Methoden eines Formulars): eine Formdatei, die 'OnClick =
  // doWork' bindet, bindet weiter (TObject.MethodAddress vergleicht ohne
  // Gross/klein) - keine Sperre. Die Deklaration steht hier auf Zeile 5.
  Assert.AreEqual(
    UnitWith(['    procedure DoWork;'],
      ['procedure TFoo.DoWork;', 'begin', 'end;']),
    Applied(UnitWith(['    procedure doWork;'],
      ['procedure TFoo.doWork;', 'begin', 'end;']), 5, 'doWork'));
end;

procedure TTestRdxMethodNameFix.ImplSpelling_OnlyImplementation;
var
  Src : string;
  P   : TRdxMethodNamePlan;
  R   : string;
begin
  // cnwizards DCURecs.pas:7864 (rwE29): 'procedure Visit(..); override;' in
  // der Klasse, 'procedure TDispPropDecl.visit(' als Implementierung - der
  // Detektor meldet die Implementierung (Zeile 9). Bis rwE29 gesperrt mit
  // "keine Klasse dieser Datei deklariert sie davor" - falsch.
  Src := UnitWith(['  public', '    procedure Visit(V: TObject); override;'],
    ['procedure TFoo.visit(V: TObject);', 'begin', 'end;']);
  Assert.IsTrue(PlanOf(Src, IMPL_LINE, Format(MSG_FMT, ['visit']), P, R), R);
  Assert.AreEqual('Visit', P.Name, 'Schreibweise der Deklaration');
  Assert.AreEqual<Integer>(1, Length(P.Edits), 'nur die Implementierung');
  Assert.AreEqual(StringReplace(Src, 'TFoo.visit', 'TFoo.Visit', []),
    Apply(Src, P.Edits));
end;

procedure TTestRdxMethodNameFix.OtherClassSameName_Untouched;
var
  Src : string;
begin
  Src := Join(['unit t;', 'interface', 'type', '  TFoo = class', '  public',
    '    procedure doWork;', '  end;', '  TBar = class', '  public',
    '    procedure doWork;', '  end;', 'implementation',
    'procedure TFoo.doWork;', 'begin', 'end;', 'procedure TBar.doWork;',
    'begin', 'end;', 'end.']);
  // TFoo (Zeile 6) - TBar bleibt.
  Assert.AreEqual(Join(['unit t;', 'interface', 'type', '  TFoo = class',
    '  public', '    procedure DoWork;', '  end;', '  TBar = class',
    '  public', '    procedure doWork;', '  end;', 'implementation',
    'procedure TFoo.DoWork;', 'begin', 'end;', 'procedure TBar.doWork;',
    'begin', 'end;', 'end.']), Applied(Src, DECL_LINE, 'doWork'));
  // TBar (Zeile 10) - TFoo bleibt.
  Assert.AreEqual(Join(['unit t;', 'interface', 'type', '  TFoo = class',
    '  public', '    procedure doWork;', '  end;', '  TBar = class',
    '  public', '    procedure DoWork;', '  end;', 'implementation',
    'procedure TFoo.doWork;', 'begin', 'end;', 'procedure TBar.DoWork;',
    'begin', 'end;', 'end.']), Applied(Src, 10, 'doWork'));
end;

// ---- Gegenproben ----

procedure TTestRdxMethodNameFix.Overload_NoHelp;
begin
  AssertRefused(UnitWith(['  public', '    procedure doWork; overload;',
    '    procedure doWork(A: Integer); overload;'],
    ['procedure TFoo.doWork;', 'begin', 'end;',
     'procedure TFoo.doWork(A: Integer);', 'begin', 'end;']),
    DECL_LINE, 'doWork', _(R_MN_OVERLOAD, ['doWork']));
end;

procedure TTestRdxMethodNameFix.ConditionalTwins_NoHelp;
begin
  // Zwei Deklarationen ohne overload ($IFDEF-Zweige): welche gemeint ist,
  // weiss die Hilfe nicht.
  AssertRefused(UnitWith(['  public', '  {$IFDEF X}', '    procedure doWork;',
    '  {$ELSE}', '    procedure doWork;', '  {$ENDIF}'],
    ['procedure TFoo.doWork;', 'begin', 'end;']), DECL_LINE + 1, 'doWork',
    _(R_MN_DECLS, [2, 'doWork', 'TFoo']));
end;

procedure TTestRdxMethodNameFix.NoImplementation_NoHelp;
begin
  AssertRefused(UnitWith(['  public', '    procedure doWork; virtual; abstract;'],
    ['procedure Other;', 'begin', 'end;']), DECL_LINE, 'doWork',
    _(R_MN_NO_IMPL, ['TFoo', 'doWork']));
end;

procedure TTestRdxMethodNameFix.TwoImplementations_NoHelp;
begin
  AssertRefused(UnitWith(['  public', '    procedure doWork;'],
    ['{$IFDEF X}', 'procedure TFoo.doWork;', 'begin', 'end;', '{$ELSE}',
     'procedure TFoo.doWork;', 'begin', '  Beep;', 'end;', '{$ENDIF}']),
    DECL_LINE, 'doWork', _(R_MN_IMPLS, [2, 'TFoo', 'doWork']));
end;

procedure TTestRdxMethodNameFix.RecordInterface_NoHelp;
begin
  // Freie Routinen bekommen seit rwE30 Stufe 2 die Hilfe
  // (FreeRoutine_DeclAndImpl_Capitalized); Methoden anderer Typen nicht.
  // Methode eines records.
  AssertRefused(Join(['unit t;', 'interface', 'type', '  TRec = record',
    '    procedure doWork;', '  end;', 'implementation',
    'procedure TRec.doWork;', 'begin', 'end;', 'end.']), 5, 'doWork',
    _(R_MN_NO_CLASS, ['doWork']));
  // Methode eines Interfaces.
  AssertRefused(Join(['unit t;', 'interface', 'type', '  IFoo = interface',
    '    procedure doWork;', '  end;', 'implementation', 'end.']), 5, 'doWork',
    _(R_MN_NO_CLASS, ['doWork']));
end;

procedure TTestRdxMethodNameFix.MovedLine_NoHelp;
var
  Src : string;
begin
  Src := StdUnit('doWork', 'doWork');
  AssertRefused(Src, DECL_LINE - 1, 'doWork',
    MsgMovedSuffix(_(R_MN_NO_HEAD, ['doWork'])));
  AssertRefused(Src, DECL_LINE + 1, 'doWork',
    MsgMovedSuffix(_(R_MN_NO_HEAD, ['doWork'])));
  AssertRefused(Src, 99, 'doWork', MsgMovedSuffix(_(R_MN_NO_HEAD, ['doWork'])));
  AssertRefused(Src, 0, 'doWork', MsgMovedSuffix(_(R_MN_NO_HEAD, ['doWork'])));
  // Ein anderer Name auf der Zeile.
  AssertRefused(Src, DECL_LINE, 'doOther',
    MsgMovedSuffix(_(R_MN_NO_HEAD, ['doOther'])));
end;

procedure TTestRdxMethodNameFix.CommentOrString_NoHelp;
var
  Src : string;
begin
  // Kommentar und String sind nie Code.
  AssertRefused(UnitWith(['  public', '    // procedure doWork;',
    '    procedure Run;'], ['procedure TFoo.Run;', 'begin', 'end;']),
    DECL_LINE, 'doWork', MsgMovedSuffix(_(R_MN_NO_HEAD, ['doWork'])));
  AssertRefused(UnitWith(['  public', '    { procedure doWork; }',
    '    procedure Run;'], ['procedure TFoo.Run;', 'begin', 'end;']),
    DECL_LINE, 'doWork', MsgMovedSuffix(_(R_MN_NO_HEAD, ['doWork'])));
  Src := UnitWith(['  public', '    procedure Run;'],
    ['procedure TFoo.Run;', 'begin', '  S := ''procedure doWork;'';', 'end;']);
  AssertRefused(Src, LineOf(Src, 'S :='), 'doWork',
    MsgMovedSuffix(_(R_MN_NO_HEAD, ['doWork'])));
end;

procedure TTestRdxMethodNameFix.AlreadyCapitalized_NoHelp;
begin
  // Der Fund ist veraltet: die Deklaration beginnt schon gross.
  AssertRefused(StdUnit('DoWork', 'DoWork'), DECL_LINE, 'doWork',
    MsgStaleSuffix(_(R_MN_SPELLING, ['DoWork', 'doWork'])));
end;

procedure TTestRdxMethodNameFix.StringLiteral_NoHelp;
var
  Src : string;
begin
  // Aufruf per Name: ein Vergleich dort kann Gross/klein beachten.
  Src := UnitWith(['  public', '    procedure doWork;', '    procedure Run;'],
    ['procedure TFoo.doWork;', 'begin', 'end;', 'procedure TFoo.Run;',
     'begin', '  if MethodAddress(''doWork'') = nil then Exit;', 'end;']);
  AssertRefused(Src, DECL_LINE, 'doWork',
    _(R_MN_LITERAL, ['doWork', LineOf(Src, 'MethodAddress')]));
end;

procedure TTestRdxMethodNameFix.IncludeInClass_NoHelp;
begin
  AssertRefused(UnitWith(['  public', '    procedure doWork;',
    '    {$I more.inc}'], ['procedure TFoo.doWork;', 'begin', 'end;']),
    DECL_LINE, 'doWork', _(R_MN_INCLUDE, [DECL_LINE + 1]));
end;

procedure TTestRdxMethodNameFix.MessageWithoutName_NoHelp;
var
  P : TRdxMethodNamePlan;
  R : string;
begin
  Assert.IsFalse(PlanOf(StdUnit('doWork', 'doWork'), DECL_LINE,
    'Method should be PascalCase.', P, R));
  Assert.AreEqual(_(R_MN_NO_NAME), R);
  // Ein Name, der schon gross beginnt, ist kein Fund dieser Regel.
  AssertRefused(StdUnit('DoWork', 'DoWork'), DECL_LINE, 'DoWork',
    _(R_MN_NO_NAME));
end;

procedure TTestRdxMethodNameFix.ImplementationOnly_NoHelp;
begin
  // Ohne Deklaration davor meldet der Detektor den Kopf der Implementierung
  // (Klasse in einem Include).
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    'procedure TFoo.doWork;', 'begin', 'end;', 'end.']), 4, 'doWork',
    _(R_MN_IMPL_ONLY, ['doWork']));
end;

procedure TTestRdxMethodNameFix.PublishedMethod_NoHelp;
begin
  // Double Commander fFindDlg.pas:345 (rwE29, Fehler): 'cm_Start' unter
  // published - TFormCommands.GetMethodsList liest die Methodentabelle und
  // filtert mit StrBegins(Name, 'cm_') (CompareChar, case-sensitiv); nach
  // 'Cm_Start' fehlte das Kommando in Hotkeys und Werkzeugleiste.
  AssertRefused(UnitWith(['  published',
    '    procedure cm_Start(const Params: array of string);'],
    ['procedure TFoo.cm_Start(const Params: array of string);', 'begin',
     'end;']), DECL_LINE, 'cm_Start', _(R_MN_PUBLISHED, ['cm_Start']));
end;

procedure TTestRdxMethodNameFix.ImplSpelling_Overload_NoHelp;
begin
  // Nur die Implementierung gemeldet, die Deklaration ueberladen: zwei
  // Deklarationen dieses Namens - welche zur Implementierung gehoert, liest
  // die Hilfe nicht.
  AssertRefused(UnitWith(['  public', '    procedure Visit; overload;',
    '    procedure Visit(N: Integer); overload;'],
    ['procedure TFoo.visit;', 'begin', 'end;',
     'procedure TFoo.Visit(N: Integer);', 'begin', 'end;']), 10, 'visit',
    _(R_MN_DECLS, [2, 'visit', 'TFoo']));
end;

// ---- rwE30 Stufe 2 ----

procedure TTestRdxMethodNameFix.FreeRoutine_DeclAndImpl_Capitalized;
var
  Src, Want : string;
begin
  // DCU32 DAsmUtil.pas:43/440 (minimiert): 'function imPtr' im interface-
  // Teil, der Rumpf im implementation-Teil, ein Aufruf. Bis dahin
  // R_MN_NO_CLASS. Der Aufruf bleibt - er bindet ohne Gross/klein.
  Src := Join(['unit t;', 'interface', 'function imPtr: Boolean;',
    'implementation', 'function imPtr: Boolean;', 'begin', '  Result := True;',
    'end;', 'procedure Use;', 'begin', '  if imPtr then Exit;', 'end;',
    'end.']);
  Want := Join(['unit t;', 'interface', 'function ImPtr: Boolean;',
    'implementation', 'function ImPtr: Boolean;', 'begin', '  Result := True;',
    'end;', 'procedure Use;', 'begin', '  if imPtr then Exit;', 'end;',
    'end.']);
  Assert.AreEqual(Want, Applied(Src, 3, 'imPtr'), 'Fund an der Deklaration');
  Assert.AreEqual(Want, Applied(Src, 5, 'imPtr'), 'Fund am Rumpf');
  // forward statt interface-Teil.
  Assert.AreEqual(Join(['unit t;', 'interface', 'implementation',
    'procedure DoIt; forward;', 'procedure DoIt;', 'begin', 'end;', 'end.']),
    Applied(Join(['unit t;', 'interface', 'implementation',
    'procedure doIt; forward;', 'procedure doIt;', 'begin', 'end;', 'end.']),
    4, 'doIt'));
end;

procedure TTestRdxMethodNameFix.FreeRoutine_ImplOnly_Capitalized;
var
  Src : string;
begin
  // Double Commander uluapas.pas:233 (minimiert): nur der Rumpf, registriert
  // per Zeiger und mit einem ANDEREN Namen als Literal.
  Src := Join(['unit t;', 'interface', 'procedure Reg;', 'implementation',
    'function luaMatchesMask(L: Pointer): Integer;', 'begin', '  Result := 0;',
    'end;', 'procedure Reg;', 'begin',
    '  Register(''MatchesMask'', @luaMatchesMask);', 'end;', 'end.']);
  Assert.AreEqual(StringReplace(Src, 'function luaMatchesMask',
    'function LuaMatchesMask', []), Applied(Src, 5, 'luaMatchesMask'));
end;

procedure TTestRdxMethodNameFix.FreeRoutine_BoundByName_NoHelp;
var
  Src : string;
begin
  // Gegenproben: ein Linker, eine Bibliothek oder C-Code bindet den genauen
  // Namen (Kastri/Alcinoe-Importe, AbCrtl.pas 'isdigit; cdecl', JvUIBase
  // 'isc_..; external').
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    'function getVal: Integer; external ''x.dll'';', 'end.']), 4, 'getVal',
    _(R_MN_FREE_BOUND, ['getVal', 'external']));
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    'function isDigit(C: Integer): Integer; cdecl;', 'begin', '  Result := C;',
    'end;', 'end.']), 4, 'isDigit', _(R_MN_FREE_BOUND, ['isDigit', 'cdecl']));
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    'procedure doIt; [public, alias: ''DOIT''];', 'begin', 'end;', 'end.']), 4,
    'doIt', _(R_MN_FREE_BOUND, ['doIt', '[']));
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    'procedure doIt;', 'begin', 'end;', 'exports doIt;', 'end.']), 4, 'doIt',
    _(R_MN_FREE_EXPORTS, ['doIt', 7]));
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    '{$L doit.obj}', 'procedure doIt;', 'begin', 'end;', 'end.']), 5, 'doIt',
    _(R_MN_FREE_LINK, [4, 'doIt']));
  AssertRefused(Join(['unit t;', 'interface', '{$EXTERNALSYM doIt}',
    'procedure doIt;', 'implementation', 'procedure doIt;', 'begin', 'end;',
    'end.']), 4, 'doIt', _(R_MN_FREE_DIRECTIVE, ['doIt', 3]));
  Src := Join(['unit t;', 'interface', 'implementation', 'procedure doIt;',
    'begin', 'end;', 'procedure Run;', 'begin',
    '  GetProcAddress(0, ''doIt'');', 'end;', 'end.']);
  AssertRefused(Src, 4, 'doIt',
    _(R_MN_LITERAL, ['doIt', LineOf(Src, 'GetProcAddress')]));
  // Nur die Deklaration im interface-Teil, kein Rumpf in der Datei.
  AssertRefused(Join(['unit t;', 'interface', 'procedure doIt;',
    'implementation', 'end.']), 3, 'doIt', _(R_MN_FREE_PAIR, ['doIt']));
  // Ueberladen.
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    'procedure doIt; overload;', 'begin', 'end;',
    'procedure doIt(A: Integer); overload;', 'begin', 'end;', 'end.']), 4,
    'doIt', _(R_MN_FREE_BOUND, ['doIt', 'overload']));
end;

procedure TTestRdxMethodNameFix.FreeRoutine_Twins_NoHelp;
begin
  // $IFDEF-Zwillinge: zwei Rumpfe - kein Paar aus Deklaration und Rumpf.
  AssertRefused(Join(['unit t;', 'interface', 'implementation', '{$IFDEF A}',
    'procedure doIt;', 'begin', 'end;', '{$ELSE}', 'procedure doIt;', 'begin',
    'end;', '{$ENDIF}', 'end.']), 5, 'doIt', _(R_MN_FREE_PAIR, ['doIt']));
  AssertRefused(Join(['unit t;', 'interface', 'procedure doIt;',
    'implementation', '{$IFDEF A}', 'procedure doIt;', 'begin', 'end;',
    '{$ELSE}', 'procedure doIt;', 'begin', 'end;', '{$ENDIF}', 'end.']), 3,
    'doIt', _(R_MN_FREE_HEADS, [3, 'doIt']));
end;

procedure TTestRdxMethodNameFix.FreeRoutine_ApiStyleName_NoHelp;
begin
  // Double Commander lua.pas:381 'lua_tocstring', kascrypt kdf.pas:83 'kdf3',
  // Kastri DW.iOSapi.FirebaseAnalytics.pas:161 'kFIRUser..' (rwE30 Stufe 2,
  // dort Sperre ok): Spiegel einer C- oder Plattform-API.
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    'function lua_tocstring(L: Pointer): PChar;', 'begin', '  Result := nil;',
    'end;', 'end.']), 4, 'lua_tocstring', _(R_MN_FREE_API, ['lua_tocstring']));
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    'procedure kdf3;', 'begin', 'end;', 'end.']), 4, 'kdf3',
    _(R_MN_FREE_API, ['kdf3']));
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    'function kFIRSignUp: Pointer;', 'begin', '  Result := nil;', 'end;',
    'end.']), 4, 'kFIRSignUp', _(R_MN_FREE_API, ['kFIRSignUp']));
end;

procedure TTestRdxMethodNameFix.ImplSpelling_LowerDecl_BothCapitalized;
var
  Src : string;
  P   : TRdxMethodNamePlan;
  R   : string;
begin
  // cnwizards DCURecs.pas:7438 (rwE30 Stufe 2): Deklaration 'visitUnit'
  // (klein) in der Klasse, gemeldet der Implementierungskopf. Bis dahin
  // R_MN_SPELLING mit zweimal demselben Namen und "Fund veraltet?".
  Src := UnitWith(['  public', '    procedure visitUnit(U: TObject); virtual;'],
    ['procedure TFoo.visitUnit(U: TObject);', 'begin', 'end;']);
  Assert.IsTrue(PlanOf(Src, IMPL_LINE, Format(MSG_FMT, ['visitUnit']), P, R),
    R);
  Assert.AreEqual('VisitUnit', P.Name);
  Assert.AreEqual(StringReplace(Src, 'visitUnit', 'VisitUnit', [rfReplaceAll]),
    Apply(Src, P.Edits));
end;

procedure TTestRdxMethodNameFix.ImplSpelling_LowerDecl_Published_Reason;
begin
  // Double Commander fviewer.pas:4163 (rwE30 Stufe 2, Fragwuerdig): der
  // Grund war "Deklaration lautet cm_GotoLine, der Fund nennt cm_GotoLine -
  // Fund veraltet?"; richtig ist published.
  AssertRefused(UnitWith(['  published',
    '    procedure cm_GotoLine(const Params: array of string);'],
    ['procedure TFoo.cm_GotoLine(const Params: array of string);', 'begin',
     'end;']), IMPL_LINE, 'cm_GotoLine', _(R_MN_PUBLISHED, ['cm_GotoLine']));
end;

procedure TTestRdxMethodNameFix.Literal_DottedPath_Helps;
var
  Src : string;
begin
  // Alcinoe.FMX.ScrollEngine.pas:1690 und CEF4Delphi uCEFCookieVisitor.pas:189
  // (rwE30 Stufe 2, minimiert): Log-Kennungen als reiner Punktpfad.
  Src := UnitWith(['  public', '    procedure doWork;', '    procedure Run;'],
    ['procedure TFoo.doWork;', 'begin', 'end;', 'procedure TFoo.Run;', 'begin',
     '  Log(''Unit1.TFoo.doWork'');', '  Log(''TOther.doWork'');', 'end;']);
  Assert.AreEqual(StringReplace(StringReplace(Src, 'procedure doWork;',
    'procedure DoWork;', []), 'procedure TFoo.doWork;',
    'procedure TFoo.DoWork;', []), Applied(Src, DECL_LINE, 'doWork'));
  // Gegenprobe: ein Ausdruck ('form.doWork()', ein Skript) ist kein reiner
  // Pfad - gesperrt wie der blosse Name (StringLiteral_NoHelp).
  Src := UnitWith(['  public', '    procedure doWork;', '    procedure Run;'],
    ['procedure TFoo.doWork;', 'begin', 'end;', 'procedure TFoo.Run;', 'begin',
     '  RunScript(''form.doWork()'');', 'end;']);
  AssertRefused(Src, DECL_LINE, 'doWork',
    _(R_MN_LITERAL, ['doWork', LineOf(Src, 'RunScript')]));
end;

{$IFNDEF FPC}

{ ---- Detektor ---- }

// Die Funde der Art SCA106 - der echte Detektor auf dem echten AST.
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TMethodNameDetector.AnalyzeUnit(Root, Path, Results);
end;

// Dasselbe in der Form TDetectFunc (FixAllWith).
function DetectKind(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := DetectSource('rdx_mn_', ASource, AKind, RunDetector);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectKind(ASource, fkMethodName);
end;

// Die Hilfe fuer einen Fund ueber den Einstieg der Tabelle - wie der
// Anbieter (PlanFixIn); der Adapter fragt den Quellstellen-Dienst nicht.
function TablePlan(const ASource: string; const ASeen: TSeen): TRdxFixOutcome;
begin
  Result := PlanFixIn(ASource, 't.pas', fkMethodName, ASeen);
end;

// Fund fuer Fund, nach jeder Ersetzung neu gemeldet, bis der Detektor
// schweigt - ueber die Tabelle (FixAllWith, Zeile und Meldung aus dem
// Fund).
function FixAll(const ASource: string): string;
begin
  Result := FixAllWith(ASource, fkMethodName, DetectKind);
end;

// Der erste Fund des Detektors bekommt keine Hilfe, Grund AReason.
procedure AssertDetectorRefused(const ASource, AReason: string);
var
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  Seen := Detect(ASource);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet');
  O := TablePlan(ASource, Seen[0]);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(AReason, O.Reason, 'Grund');
end;

procedure TTestRdxMethodNameDetector.Detector_ReportsDeclarationLine;
var
  Seen : TArray<TSeen>;
begin
  // EIN Fund fuer Deklaration und Implementierung, auf der Deklaration;
  // die Meldung traegt den Namen in Backticks.
  Seen := Detect(StdUnit('doWork', 'doWork'));
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  Assert.AreEqual<Integer>(DECL_LINE, Seen[0].Line, 'Zeile der Deklaration');
  Assert.AreEqual(Format(MSG_FMT, ['doWork']), Seen[0].Msg);
  Assert.AreEqual('doWork', MethodNameOf(Seen[0].Msg));
end;

procedure TTestRdxMethodNameDetector.Detector_RoundTrip;
var
  Fixed : string;
begin
  Fixed := FixAll(StdUnit('doWork', 'doWork'));
  Assert.AreEqual(StdUnit('DoWork', 'DoWork'), Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed)),
    'der Detektor schweigt danach');
end;

procedure TTestRdxMethodNameDetector.Detector_TwoMethods_BothFixed;
var
  Src : string;
begin
  Src := UnitWith(['  public', '    procedure doWork;',
    '    function getValue: Integer;'],
    ['procedure TFoo.doWork;', 'begin', 'end;',
     'function TFoo.getValue: Integer;', 'begin', '  Result := 0;', 'end;']);
  Assert.AreEqual<Integer>(2, Length(Detect(Src)), 'zwei Funde');
  Assert.AreEqual(UnitWith(['  public', '    procedure DoWork;',
    '    function GetValue: Integer;'],
    ['procedure TFoo.DoWork;', 'begin', 'end;',
     'function TFoo.GetValue: Integer;', 'begin', '  Result := 0;', 'end;']),
    FixAll(Src));
end;

procedure TTestRdxMethodNameDetector.Detector_ImplSpelledDifferently_Fixed;
var
  Src, Fixed : string;
begin
  // Die Implementierung 'dowork': Delphi nimmt sie an, der Detektor meldet
  // nur die Deklaration - ohne die zweite Ersetzung meldete er danach die
  // Implementierung.
  Src := StdUnit('doWork', 'dowork');
  Assert.AreEqual<Integer>(1, Length(Detect(Src)), 'ein Fund');
  Fixed := FixAll(Src);
  Assert.AreEqual(StdUnit('DoWork', 'Dowork'), Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed)),
    'der Detektor schweigt danach');
end;

procedure TTestRdxMethodNameDetector.Detector_ImplOnly_Fixed;
var
  Src, Fixed : string;
  Seen       : TArray<TSeen>;
begin
  // Die Deklaration 'DoWork' besteht die Pruefung, der Detektor meldet die
  // Implementierung 'TFoo.doWork' (rwE29, DCURecs.pas:7864) - die Hilfe
  // gleicht sie an, danach schweigt er.
  Src := StdUnit('DoWork', 'doWork');
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  Assert.AreEqual<Integer>(IMPL_LINE, Seen[0].Line, 'an der Implementierung');
  Fixed := FixAll(Src);
  Assert.AreEqual(StdUnit('DoWork', 'DoWork'), Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed)),
    'der Detektor schweigt danach');
end;

procedure TTestRdxMethodNameDetector.Detector_CatalogExample_InClass_Fixed;
var
  Meta : TRuleMeta;
  Src  : string;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkMethodName);
  Assert.IsTrue(Pos('doStuff', Meta.BadExample) > 0, Meta.BadExample);
  // Das Beispiel ('procedure doStuff;') als Methode von TFoo.
  Src := UnitWith(['  public', '    ' + CatalogText(Meta.BadExample)],
    ['procedure TFoo.doStuff;', 'begin', 'end;']);
  Assert.AreEqual<Integer>(1, Length(Detect(Src)), 'der Detektor meldet das Beispiel');
  Assert.AreEqual(StringReplace(Src, 'doStuff', 'DoStuff', [rfReplaceAll]),
    FixAll(Src));
end;

procedure TTestRdxMethodNameDetector.Detector_CatalogExample_FreeRoutine_Fixed;
var
  Meta : TRuleMeta;
begin
  // Das Beispiel wortgetreu ist eine freie Routine - seit rwE30 Stufe 2
  // eine Hilfe (bis dahin R_MN_NO_CLASS): Deklaration und Rumpf gross, der
  // Detektor schweigt danach.
  Meta := TRuleCatalog.GetRuleCanonical(fkMethodName);
  Assert.AreEqual(Join(['unit t;', 'interface', 'procedure DoStuff;',
    'implementation', 'procedure DoStuff;', 'begin', 'end;', 'end.']),
    FixAll(Join(['unit t;', 'interface', CatalogText(Meta.BadExample),
    'implementation', 'procedure doStuff;', 'begin', 'end;', 'end.'])));
end;

procedure TTestRdxMethodNameDetector.Detector_Overload_NoHelp;
begin
  // Der Detektor meldet die Ueberladungen EINMAL (Schluessel Klasse und
  // Name) - die Hilfe waehlt keine.
  AssertDetectorRefused(UnitWith(['  public', '    procedure doWork; overload;',
    '    procedure doWork(A: Integer); overload;'],
    ['procedure TFoo.doWork;', 'begin', 'end;',
     'procedure TFoo.doWork(A: Integer);', 'begin', 'end;']),
    _(R_MN_OVERLOAD, ['doWork']));
end;

procedure TTestRdxMethodNameDetector.Table_NameAndTwoEdits;
var
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  // Der Eintrag ueber die Tabelle: Name ist der neue Name (Menuetext),
  // Deklaration und Implementierung in einem Schritt, bedeutungsgleich.
  Seen := Detect(StdUnit('doWork', 'doWork'));
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  O := TablePlan(StdUnit('doWork', 'doWork'), Seen[0]);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual('DoWork', O.Name);
  Assert.AreEqual<Integer>(2, Length(O.Edits), 'Deklaration und Implementierung');
  Assert.IsFalse(O.ChangesBehavior, 'nicht gekennzeichnet');
  Assert.IsTrue(O.Hint <> '', 'Hinweis der Zeile');
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxMethodNameFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxMethodNameDetector);
  {$ENDIF}

end.
