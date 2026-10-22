unit uTestRdxExceptionNameFix;

// Editorhilfe SCA118 ExceptionName (uRdxExceptionNameFix): der Planer auf
// Text (erste Fixture, FPC-tauglich) und der ECHTE Detektor (uNamingExt)
// auf dem echten AST ueber den Einstieg der Tabelle (TRdxFixTable.FixFor
// via PlanFixIn/FixAllWith, Adapter PlanExceptionName; zweite Fixture, nur
// Delphi). Die Fixtures stehen in
// einer Unit mit implementation-Teil ab Zeile 4 ('type' auf Zeile 5); die
// Klasse ist auf Zeile 6 deklariert (DECL_LINE).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxExceptionNameFix = class
  public
    // ---- Umformung ----
    [Test] procedure ImplementationClass_RenamesAllUses;
    [Test] procedure OtherCase_RenamedToo;
    [Test] procedure NewName_TPrefixAndAcronym;
    [Test] procedure Comments_KeepOldName;
    [Test] procedure ProgramFile_Renamed;
    [Test] procedure WithInEarlierRoutine_Renamed;
    // ---- Gegenproben ----
    [Test] procedure InterfaceOrIncludeFile_NoHelp;
    [Test] procedure NewNameTaken_NoHelp;
    [Test] procedure StringLiteral_NoHelp;
    [Test] procedure UsedBeforeDeclaration_NoHelp;
    [Test] procedure QualifiedUse_NoHelp;
    [Test] procedure WithBeforeUse_NoHelp;
    [Test] procedure MovedLine_NoHelp;
    [Test] procedure CommentOrDirectiveInDeclaration_NoHelp;
    [Test] procedure DirectiveNamesClass_NoHelp;
    [Test] procedure IncludeInImplementation_NoHelp;
    [Test] procedure AlreadyPrefixed_Stale;
    [Test] procedure NonAsciiOrUnderscore_NoHelp;
    [Test] procedure MessageWithoutName_NoHelp;
    [Test] procedure Refused_NameStillSet;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxExceptionNameDetector = class
  public
    [Test] procedure Detector_ReportsDeclarationLine;
    [Test] procedure Detector_RoundTrip;
    [Test] procedure Detector_CatalogExample_Fixed;
    [Test] procedure Detector_LowercaseName_Silenced;
    [Test] procedure Detector_TPrefix_Silenced;
    [Test] procedure Detector_InterfaceClass_NoHelp;
    // ---- Tabellenzeile ----
    [Test] procedure Table_NameIsNewName;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uNamingExt,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uRdxFixTable,          // TRdxFixTable.CaptionFor
  uTestRdxDetectorKit,   // TSeen, DetectSource, CatalogText, PlanFixIn
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxExceptionNameFix,
  uRdxText,              // _() und die gemeinsamen Gruende
  uTestRdxTextKit;       // Join, Apply

const
  DECL_LINE = 6;   // Zeile der Klasse in UnitWith(['type', '  X = ...'])

// ---- Helfer ----

// Die Meldung des Detektors fuer die Klasse AName.
function Msg(const AName: string): string;
begin
  Result := Format('Exception class %s should start with ''E'' prefix '
    + '(Delphi-RTL convention: EAbort, EDivByZero, EMyError). Suggested: E%s',
    [AName, AName]);
end;

// Eine Unit: Zeilen 1-3 Kopf und interface, Zeile 4 'implementation',
// AImpl ab Zeile 5, dann 'end.'.
function UnitWith(const AImpl: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'uses SysUtils;',
    'implementation']) + #13#10 + Join(AImpl) + #13#10 + 'end.';
end;

// Der Planer fuer Zeile ALine mit AMessage: der neue Text, oder '' bei
// Ablehnung (AReason); den Plan in APlan.
function PlanWith(const ASource: string; ALine: Integer;
  const AMessage: string; out AReason: string;
  out APlan: TRdxExceptionNamePlan): string;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  Ok  : Boolean;
begin
  Result := '';
  AReason := '';
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    try
      Ok := TRdxExceptionNameFix.RenameClass(Map, ALine, AMessage, APlan,
        AReason);
    finally
      Map.Free;
    end;
  finally
    SL.Free;
  end;
  if Ok then
    Result := Apply(ASource, APlan.Edits);
end;

// Die Hilfe muss gelten (sonst scheitert der Test mit dem Grund).
function Applied(const ASource: string; ALine: Integer;
  const AName: string): string;
var
  R : string;
  P : TRdxExceptionNamePlan;
begin
  Result := PlanWith(ASource, ALine, Msg(AName), R, P);
  Assert.IsTrue(Result <> '', R);
end;

procedure AssertRefused(const ASource: string; ALine: Integer;
  const AName, AReason: string);
var
  R : string;
  P : TRdxExceptionNamePlan;
begin
  Assert.AreEqual('', PlanWith(ASource, ALine, Msg(AName), R, P),
    'keine Hilfe');
  Assert.AreEqual(AReason, R, 'Grund');
  Assert.AreEqual<Integer>(0, Length(P.Edits), 'keine Ersetzung');
end;

// ---- Umformung ----

procedure TTestRdxExceptionNameFix.ImplementationClass_RenamesAllUses;
var
  Src, Fixed : string;
  R          : string;
  P          : TRdxExceptionNamePlan;
begin
  Src := UnitWith(['type', '  MyError = class(Exception);',
    '  MyErrorClass = class of MyError;', '  ESub = class(MyError);', '',
    'procedure Foo;', 'begin', '  try', '    raise MyError.Create(''x'');',
    '  except', '    on E: MyError do', '      raise;', '  end;', 'end;']);
  Fixed := PlanWith(Src, DECL_LINE, Msg('MyError'), R, P);
  Assert.AreEqual(UnitWith(['type', '  EMyError = class(Exception);',
    '  MyErrorClass = class of EMyError;', '  ESub = class(EMyError);', '',
    'procedure Foo;', 'begin', '  try', '    raise EMyError.Create(''x'');',
    '  except', '    on E: EMyError do', '      raise;', '  end;', 'end;']),
    Fixed, R);
  // Je Verweis eine Ersetzung, nur das Wort; 'MyErrorClass' ist ein
  // anderer Bezeichner.
  Assert.AreEqual<Integer>(5, Length(P.Edits), 'fuenf Verweise');
  Assert.AreEqual('MyError', P.Edits[0].Expected);
  Assert.AreEqual('EMyError', P.Edits[0].NewText);
  Assert.AreEqual<Integer>(DECL_LINE, P.Edits[0].Span.StartLine);
  Assert.AreEqual<Integer>(3, P.Edits[0].Span.StartCol);
  Assert.AreEqual('EMyError', P.Name, 'Name fuer den Menuetext');
end;

procedure TTestRdxExceptionNameFix.OtherCase_RenamedToo;
begin
  // Delphi unterscheidet Gross/klein nicht: 'MYERROR' ist dieselbe Klasse,
  // und ein Name mit kleinem Anfang bekommt den grossen nach dem 'E'.
  Assert.AreEqual(UnitWith(['type', '  EMyError = class(Exception);',
    'procedure Foo;', 'begin', '  raise EMyError.Create(''x'');', 'end;']),
    Applied(UnitWith(['type', '  myError = class(Exception);',
      'procedure Foo;', 'begin', '  raise MYERROR.Create(''x'');', 'end;']),
      DECL_LINE, 'myError'));
end;

procedure TTestRdxExceptionNameFix.NewName_TPrefixAndAcronym;
begin
  Assert.AreEqual('EMyError', TRdxExceptionNameFix.PrefixedName('MyError'));
  Assert.AreEqual('EMyError', TRdxExceptionNameFix.PrefixedName('myError'));
  // Der Vorschlag des Detektors 'Eerror' meldet der Detektor weiter.
  Assert.AreEqual('EError', TRdxExceptionNameFix.PrefixedName('error'));
  Assert.AreEqual('EMyError', TRdxExceptionNameFix.PrefixedName('TMyError'));
  // Ein Akronym ist kein Klassen-'T'.
  Assert.AreEqual('ETCPError', TRdxExceptionNameFix.PrefixedName('TCPError'));
  Assert.IsTrue(TRdxExceptionNameFix.HasPrefixShape('EError'));
  Assert.IsFalse(TRdxExceptionNameFix.HasPrefixShape('Eerror'));
end;

procedure TTestRdxExceptionNameFix.Comments_KeepOldName;
begin
  Assert.AreEqual(UnitWith(['type', '  // MyError: raised on bad input',
    '  EMyError = class(Exception);', 'procedure Foo;', 'begin',
    '  raise EMyError.Create(''x''); { MyError }', 'end;']),
    Applied(UnitWith(['type', '  // MyError: raised on bad input',
      '  MyError = class(Exception);', 'procedure Foo;', 'begin',
      '  raise MyError.Create(''x''); { MyError }', 'end;']),
      DECL_LINE + 1, 'MyError'));
end;

procedure TTestRdxExceptionNameFix.ProgramFile_Renamed;
var
  Src : string;
begin
  // Ein Programm hat keinen interface-Teil: seine Typen sieht keine Unit.
  Src := Join(['program p;', 'uses SysUtils;', 'type',
    '  MyError = class(Exception);', 'begin', '  raise MyError.Create(''x'');',
    'end.']);
  Assert.AreEqual(StringReplace(Src, 'MyError', 'EMyError', [rfReplaceAll]),
    Applied(Src, 4, 'MyError'));
end;

procedure TTestRdxExceptionNameFix.WithInEarlierRoutine_Renamed;
var
  Src : string;
begin
  // Das with einer anderen Routine davor bindet hier nichts.
  Src := UnitWith(['type', '  MyError = class(Exception);',
    'procedure Bar(Obj: TObject);', 'begin', '  with Obj do', '    Free;',
    'end;', 'procedure Foo;', 'begin', '  raise MyError.Create(''x'');',
    'end;']);
  Assert.AreEqual(StringReplace(Src, 'MyError', 'EMyError', [rfReplaceAll]),
    Applied(Src, DECL_LINE, 'MyError'));
end;

// ---- Gegenproben ----

procedure TTestRdxExceptionNameFix.InterfaceOrIncludeFile_NoHelp;
begin
  // Im interface-Teil koennen andere Units den Namen nennen.
  AssertRefused(Join(['unit t;', 'interface', 'uses SysUtils;', 'type',
    '  MyError = class(Exception);', 'implementation', 'end.']), 5,
    'MyError', _(R_EXC_NOT_LOCAL));
  // Ohne 'implementation' und ohne 'program': eine Include-Datei.
  AssertRefused(Join(['type', '  MyError = class(Exception);']), 2,
    'MyError', _(R_EXC_NOT_LOCAL));
end;

procedure TTestRdxExceptionNameFix.NewNameTaken_NoHelp;
begin
  // Auch in anderer Schreibweise: Delphi unterscheidet Gross/klein nicht.
  AssertRefused(UnitWith(['type', '  MyError = class(Exception);',
    'procedure Foo;', 'begin', '  raise emyerror.Create(''x'');', 'end;']),
    DECL_LINE, 'MyError', _(R_EXC_TAKEN, ['EMyError']));
end;

procedure TTestRdxExceptionNameFix.StringLiteral_NoHelp;
begin
  AssertRefused(UnitWith(['type', '  MyError = class(Exception);',
    'procedure Foo(E: Exception);', 'begin',
    '  if E.ClassName = ''MyError'' then', '    raise MyError.Create(''x'');',
    'end;']), DECL_LINE, 'MyError', _(R_EXC_STRING, ['MyError']));
end;

procedure TTestRdxExceptionNameFix.UsedBeforeDeclaration_NoHelp;
begin
  // Vor der Deklaration meint der Name einen anderen Typ (etwa aus uses).
  AssertRefused(UnitWith(['procedure Foo;', 'begin',
    '  raise MyError.Create(''x'');', 'end;', 'type',
    '  MyError = class(Exception);']), 10, 'MyError',
    _(R_EXC_BEFORE, ['MyError', 7]));
end;

procedure TTestRdxExceptionNameFix.QualifiedUse_NoHelp;
begin
  AssertRefused(UnitWith(['type', '  MyError = class(Exception);',
    'procedure Foo(Obj: TObject);', 'begin', '  X := Obj.MyError;', 'end;']),
    DECL_LINE, 'MyError', _(R_EXC_QUALIFIED, ['MyError', 9]));
end;

procedure TTestRdxExceptionNameFix.WithBeforeUse_NoHelp;
begin
  AssertRefused(UnitWith(['type', '  MyError = class(Exception);',
    'procedure Foo(Obj: TObject);', 'begin', '  with Obj do',
    '    raise MyError.Create(''x'');', 'end;']), DECL_LINE, 'MyError',
    _(R_EXC_WITH, [10, 'MyError']));
end;

procedure TTestRdxExceptionNameFix.MovedLine_NoHelp;
var
  Src : string;
begin
  Src := UnitWith(['type', '  MyError = class(Exception);',
    '  Other = class(TObject);']);
  AssertRefused(Src, DECL_LINE + 1, 'MyError',
    MsgMovedSuffix(_(R_EXC_MOVED, ['MyError'])));
  // Der Name im Kommentar der Zeile zaehlt nicht.
  AssertRefused(UnitWith(['type', '  // MyError = class(Exception);',
    '  Other = class(TObject);']), DECL_LINE, 'MyError',
    MsgMovedSuffix(_(R_EXC_MOVED, ['MyError'])));
end;

procedure TTestRdxExceptionNameFix.CommentOrDirectiveInDeclaration_NoHelp;
begin
  AssertRefused(UnitWith(['type', '  MyError = class { base } (Exception);']),
    DECL_LINE, 'MyError', _(R_EXC_COMMENT, ['MyError']));
  AssertRefused(UnitWith(['type',
    '  MyError = class({$IFDEF X}Exception{$ELSE}EAbort{$ENDIF});']),
    DECL_LINE, 'MyError', _(R_EXC_COMMENT, ['MyError']));
end;

procedure TTestRdxExceptionNameFix.DirectiveNamesClass_NoHelp;
begin
  AssertRefused(UnitWith(['type', '  MyError = class(Exception);',
    '{$IF DECLARED(MyError)}', 'const X = 1;', '{$IFEND}']), DECL_LINE,
    'MyError', _(R_EXC_DIRECTIVE, ['MyError']));
end;

procedure TTestRdxExceptionNameFix.IncludeInImplementation_NoHelp;
begin
  AssertRefused(UnitWith(['type', '  MyError = class(Exception);',
    '{$I extra.inc}']), DECL_LINE, 'MyError', _(R_EXC_INCLUDE, [7]));
end;

procedure TTestRdxExceptionNameFix.AlreadyPrefixed_Stale;
begin
  AssertRefused(UnitWith(['type', '  EMyError = class(Exception);']),
    DECL_LINE, 'EMyError', MsgStaleSuffix(_(R_EXC_STALE, ['EMyError'])));
end;

procedure TTestRdxExceptionNameFix.NonAsciiOrUnderscore_NoHelp;
var
  Name : string;
begin
  Name := 'My' + #$00C4 + 'rger';
  AssertRefused(UnitWith(['type', '  ' + Name + ' = class(Exception);']),
    DECL_LINE, Name, _(R_EXC_NON_ASCII, [Name]));
  // 'E_Fail' traegt keinen Praefix in der Form des Detektors.
  AssertRefused(UnitWith(['type', '  _Fail = class(Exception);']),
    DECL_LINE, '_Fail', _(R_EXC_SHAPE, ['E_Fail']));
end;

procedure TTestRdxExceptionNameFix.MessageWithoutName_NoHelp;
var
  R : string;
  P : TRdxExceptionNamePlan;
begin
  Assert.AreEqual('', PlanWith(UnitWith(['type',
    '  MyError = class(Exception);']), DECL_LINE, 'Exception without E', R,
    P));
  Assert.AreEqual(_(R_EXC_FORM), R);
end;

procedure TTestRdxExceptionNameFix.Refused_NameStillSet;
var
  R : string;
  P : TRdxExceptionNamePlan;
begin
  // Der Menuetext nennt den neuen Namen auch am gesperrten Eintrag.
  Assert.AreEqual('', PlanWith(Join(['type', '  MyError = class(Exception);']),
    2, Msg('MyError'), R, P));
  Assert.AreEqual(_(R_EXC_NOT_LOCAL), R);
  Assert.AreEqual('MyError', P.OldName);
  Assert.AreEqual('EMyError', P.Name);
end;

{$IFNDEF FPC}

{ ---- Detektor und Tabelle ---- }

// Die Funde der Art SCA118 - der echte Detektor auf dem echten AST.
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TNamingExtDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_excname_', ASource, fkExceptionName,
    RunDetector);
end;

// Dasselbe in der Form TDetectFunc (FixAllWith).
function DetectKind(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := DetectSource('rdx_excname_', ASource, AKind, RunDetector);
end;

// Die Hilfe fuer den ersten Fund des Detektors ueber den Einstieg der
// Tabelle (PlanFixIn: TRdxFixTable.FixFor, Adapter PlanExceptionName).
function PlanFirst(const ASource: string): TRdxFixOutcome;
var
  Seen : TArray<TSeen>;
begin
  Seen := Detect(ASource);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet einen Fund');
  Result := PlanFixIn(ASource, 't.pas', fkExceptionName, Seen[0]);
end;

// Fund fuer Fund ueber die Tabelle, nach jeder Ersetzung neu gemeldet, bis
// der Detektor schweigt (FixAllWith).
function FixAll(const ASource: string): string;
begin
  Result := FixAllWith(ASource, fkExceptionName, DetectKind);
end;

procedure TTestRdxExceptionNameDetector.Detector_ReportsDeclarationLine;
var
  Seen : TArray<TSeen>;
begin
  Seen := Detect(UnitWith(['type', '  MyError = class(Exception);']));
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  Assert.AreEqual<Integer>(DECL_LINE, Seen[0].Line, 'Zeile des Namens');
  Assert.AreEqual('MyError', TRdxExceptionNameFix.ClassNameOf(Seen[0].Msg));
end;

procedure TTestRdxExceptionNameDetector.Detector_RoundTrip;
var
  Src, Fixed : string;
begin
  Src := UnitWith(['type', '  MyError = class(Exception);',
    '  OtherError = class(Exception);', 'procedure Foo(A: Integer);',
    'begin', '  if A = 0 then', '    raise MyError.Create(''a'')', '  else',
    '    raise OtherError.Create(''b'');', 'end;']);
  Assert.AreEqual<Integer>(2, Length(Detect(Src)), 'zwei Funde');
  Fixed := FixAll(Src);
  Assert.AreEqual(UnitWith(['type', '  EMyError = class(Exception);',
    '  EOtherError = class(Exception);', 'procedure Foo(A: Integer);',
    'begin', '  if A = 0 then', '    raise EMyError.Create(''a'')', '  else',
    '    raise EOtherError.Create(''b'');', 'end;']), Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed)),
    'der Detektor schweigt danach');
end;

procedure TTestRdxExceptionNameDetector.Detector_CatalogExample_Fixed;
var
  Meta : TRuleMeta;
  Src  : string;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkExceptionName);
  Assert.IsTrue(Pos('MyError', Meta.BadExample) > 0, Meta.BadExample);
  Src := UnitWith([CatalogText(Meta.BadExample)]);
  Assert.AreEqual<Integer>(1, Length(Detect(Src)),
    'der Detektor meldet das Beispiel');
  Assert.AreEqual(UnitWith([CatalogText(Meta.GoodExample)]), FixAll(Src));
end;

procedure TTestRdxExceptionNameDetector.Detector_LowercaseName_Silenced;
var
  Fixed : string;
begin
  // Der Vorschlag des Detektors ('E' + Name) waere 'Eerror' - und bliebe
  // ein Fund. Die Hilfe schreibt 'EError'.
  Assert.AreEqual<Integer>(1, Length(Detect(UnitWith(['type',
    '  Eerror = class(Exception);']))), 'Eerror bleibt ein Fund');
  Fixed := FixAll(UnitWith(['type', '  error = class(Exception);']));
  Assert.AreEqual(UnitWith(['type', '  EError = class(Exception);']), Fixed);
end;

procedure TTestRdxExceptionNameDetector.Detector_TPrefix_Silenced;
begin
  Assert.AreEqual(UnitWith(['type', '  EParseError = class(Exception);']),
    FixAll(UnitWith(['type', '  TParseError = class(Exception);'])));
end;

procedure TTestRdxExceptionNameDetector.Detector_InterfaceClass_NoHelp;
var
  O : TRdxFixOutcome;
begin
  O := PlanFirst(Join(['unit t;', 'interface', 'uses SysUtils;',
    'type', '  MyError = class(Exception);', 'implementation', 'end.']));
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_EXC_NOT_LOCAL), O.Reason);
  Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
  // Der Menuetext nennt den neuen Namen auch gesperrt.
  Assert.AreEqual('EMyError', O.Name);
end;

procedure TTestRdxExceptionNameDetector.Table_NameIsNewName;
var
  O : TRdxFixOutcome;
begin
  // Name = der neue Name (Menuetext 'Rename the exception class to %s'),
  // Hinweis der Zeile, bedeutungsgleich (nicht gekennzeichnet).
  O := PlanFirst(UnitWith(['type', '  MyError = class(Exception);']));
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual('EMyError', O.Name);
  Assert.IsFalse(O.ChangesBehavior, 'bedeutungsgleich');
  Assert.IsTrue(Pos('implementation', O.Hint) > 0, O.Hint);
  Assert.IsTrue(Pos('EMyError', TRdxFixTable.CaptionFor(fkExceptionName, O)) > 0,
    'der Menuetext nennt den neuen Namen');
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxExceptionNameFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxExceptionNameDetector);
  {$ENDIF}

end.
