unit uTestRdxKeywordCaseFix;

// Editorhilfe SCA064 LowercaseKeyword (uRdxKeywordCaseFix) - nur Delphi
// (reDelphix.Test): die Runden- und Katalogtests laufen gegen den ECHTEN
// Detektor (Parser, uLowercaseKeyword). Die Planer-Tests arbeiten auf Text
// mit der Meldung, wie der Detektor sie schreibt:
//   * reservierte Woerter (If, Begin, And, Nil ...) und nur das gemeldete
//     Wort der Zeile,
//   * Sichtbarkeit, Methoden-Direktiven und Klassen-Modifikatoren nur im
//     passenden Zusammenhang,
//   * Gegenproben: Kommentar, String, verschobene Zeile/Spalte, Teil eines
//     Bezeichners, Member ('Foo.End'), '&Begin', benanntes Argument, die
//     Kontextwoerter On/Out/Contains/..., Direktivwort als Anweisung.
// Der Einstieg ueber die Tabelle (FixFor) kommt mit der FIX_ROWS-Zeile.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxKeywordCaseFix = class
  public
    [Test] procedure Reserved_Words;
    [Test] procedure Only_The_Reported_Word;
    [Test] procedure Comment_And_String_Refused;
    [Test] procedure Moved_Or_Part_Of_Identifier_Refused;
    [Test] procedure Member_Escape_NamedArgument_Refused;
    [Test] procedure Context_Words_Refused;
    [Test] procedure Visibility_Positive;
    [Test] procedure Visibility_Refused;
    [Test] procedure Directives_Positive;
    [Test] procedure Directives_As_Statement_Refused;
    [Test] procedure Directives_FieldAfterProcType_Refused;
    [Test] procedure Operator_And_Strict;
    [Test] procedure Class_Modifiers;
    [Test] procedure Adapter_Name_And_Edit;
    [Test] procedure Adapter_Refusal_And_NoFile;
    [Test] procedure Detector_CatalogExample;
    [Test] procedure Detector_MixedUnit_RoundTrip;
    [Test] procedure Detector_Refused_Findings_Remain;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uLowercaseKeyword,
  uRdxBufferMath, uRdxCodeMap, uRdxRecipeRunner,
  uRdxFixTable, uRdxKeywordCaseFix,
  uTestRdxDetectorKit,   // TSeen, DetectSource
  uTestRdxTextKit;       // Join, Apply

const
  KW_PREFIX  = 'rdx_kw_';
  MAX_PASSES = 40;

// ---- Helfer ----

// Die Meldung des Detektors (uLowercaseKeyword).
function Msg(const AWord: string; ACol: Integer): string;
begin
  Result := Format('Keyword "%s" should be lowercase ("%s") at column %d.',
    [AWord, LowerCase(AWord), ACol]);
end;

// Eine Unit mit Routine P und den Zeilen ALines als Rumpf (ab Zeile 6).
function InBody(const ALines: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'implementation', 'procedure P;',
    'begin']) + #13#10 + Join(ALines) + #13#10 + Join(['end;', 'end.']);
end;

function LineText(const ASource: string; ALine: Integer): string;
var
  SL : TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    Result := SL[ALine - 1];
  finally
    SL.Free;
  end;
end;

// ASource mit dem Wort an (ALine, ACol) klein geschrieben.
function Swapped(const ASource: string; ALine, ACol: Integer;
  const AWord: string): string;
var
  SL  : TStringList;
  Off, i : Integer;
begin
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    Off := 0;
    for i := 0 to ALine - 2 do
      Inc(Off, Length(SL[i]) + 2);
  finally
    SL.Free;
  end;
  Result := Copy(ASource, 1, Off + ACol - 1) + LowerCase(AWord)
    + Copy(ASource, Off + ACol + Length(AWord), MaxInt);
end;

// Die Hilfe fuer die Meldung AMessage: neuer Text, '' bei Ablehnung.
function TryFixMsg(const ASource: string; ALine: Integer;
  const AMessage: string; out AReason: string): string;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  E   : TRdxEdit;
begin
  Result := '';
  Map := nil;
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    if TRdxKeywordCaseFix.LowercaseKeyword(Map, ALine, AMessage, E, AReason) then
      Result := Apply(ASource, E);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Die Hilfe fuer das Wort an (ALine, ACol): neuer Text, '' bei Ablehnung.
function TryFix(const ASource: string; ALine: Integer; const AWord: string;
  ACol: Integer; out AReason: string): string;
begin
  Result := TryFixMsg(ASource, ALine, Msg(AWord, ACol), AReason);
end;

// Das Wort (erstes Vorkommen in der Zeile) wird klein.
procedure CheckFix(const ASource: string; ALine: Integer; const AWord: string);
var
  Reason : string;
  Col    : Integer;
begin
  Col := Pos(AWord, LineText(ASource, ALine));
  Assert.IsTrue(Col > 0, AWord);
  Assert.AreEqual(Swapped(ASource, ALine, Col, AWord),
    TryFix(ASource, ALine, AWord, Col, Reason), AWord + ': ' + Reason);
end;

// Keine Hilfe, mit genau diesem Grund.
procedure CheckRefused(const ASource: string; ALine: Integer;
  const AWord, AReason: string);
var
  Reason : string;
begin
  Assert.AreEqual('', TryFix(ASource, ALine, AWord,
    Pos(AWord, LineText(ASource, ALine)), Reason), AWord);
  Assert.AreEqual(AReason, Reason, AWord);
end;

procedure RunKeyword(AKind: TFindingKind; Root: TAstNode; const Path: string;
  Results: TObjectList<TLeakFinding>);
begin
  TLowercaseKeywordDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource(KW_PREFIX, ASource, fkLowercaseKeyword, RunKeyword);
end;

// Die Hilfe fuer EINEN gemeldeten Fund ueber den Planer der Tabelle.
function PlanOf(const ASource: string; const ASeen: TSeen): TRdxFixOutcome;
var
  SL      : TStringList;
  Finding : TLeakFinding;
begin
  SL := TStringList.Create;
  Finding := TLeakFinding.New('t.pas', '', ASeen.Line, ASeen.Msg,
    fkLowercaseKeyword);
  try
    SL.Text := ASource;
    Result := TRdxFixTable.FixFor(nil, SL, Finding, nil);
  finally
    Finding.Free;
    SL.Free;
  end;
end;

// Fund fuer Fund, wo eine Hilfe da ist; nach jeder Ersetzung neu gemeldet.
// ARemaining = Funde, fuer die es keine Hilfe gibt.
function FixPossible(const ASource: string; out ARemaining: Integer): string;
var
  Seen    : TArray<TSeen>;
  O       : TRdxFixOutcome;
  Pass, i : Integer;
  Applied : Boolean;
begin
  Result := ASource;
  ARemaining := 0;
  for Pass := 1 to MAX_PASSES do
  begin
    Seen := Detect(Result);
    ARemaining := Length(Seen);
    Applied := False;
    for i := 0 to High(Seen) do
    begin
      O := PlanOf(Result, Seen[i]);
      if O.Enabled then
      begin
        Result := Apply(Result, O.Edits);
        Applied := True;
        Break;
      end;
    end;
    if not Applied then Exit;
  end;
  Assert.Fail('der Detektor meldet nach ' + IntToStr(MAX_PASSES)
    + ' Runden noch');
end;

// Ein Beispiel des Katalogs als Quelltext in einer Unit.
function CatalogUnit(const AExample: string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation',
    CatalogText(AExample), 'end.']);
end;

{ ---- reservierte Woerter ---- }

procedure TTestRdxKeywordCaseFix.Reserved_Words;
begin
  CheckFix(InBody(['  IF X THEN Y;']), 6, 'IF');
  CheckFix(InBody(['  X := A AND B;']), 6, 'AND');
  CheckFix(InBody(['  FOR I := 0 TO 9 DO Y;']), 6, 'FOR');
  CheckFix(InBody(['  FOR I := 0 TO 9 DO Y;']), 6, 'TO');
  CheckFix(InBody(['  X := Nil;']), 6, 'Nil');
  CheckFix(InBody(['  X := Not Y;']), 6, 'Not');
  CheckFix(InBody(['  Begin', '  End;']), 6, 'Begin');
  CheckFix(InBody(['  Begin', '  End;']), 7, 'End');
  CheckFix(Join(['Unit u;', 'interface', 'implementation', 'end.']), 1, 'Unit');
end;

procedure TTestRdxKeywordCaseFix.Only_The_Reported_Word;
begin
  // IF und THEN stehen gross - die Hilfe fuer THEN fasst IF nicht an.
  CheckFix(InBody(['  IF X THEN Y;']), 6, 'THEN');
  CheckFix(InBody(['  IF X THEN Y;']), 6, 'IF');
end;

{ ---- Gegenproben ---- }

procedure TTestRdxKeywordCaseFix.Comment_And_String_Refused;
begin
  CheckRefused(InBody(['  S := ''Begin'';']), 6, 'Begin', KC_MOVED);
  CheckRefused(InBody(['  // Begin']), 6, 'Begin', KC_MOVED);
  CheckRefused(InBody(['  { End }']), 6, 'End', KC_MOVED);
  CheckRefused(InBody(['  (* End *)']), 6, 'End', KC_MOVED);
  // Zeile mitten in einem Block-Kommentar.
  CheckRefused(InBody(['  {', '  Begin', '  }']), 7, 'Begin', KC_MOVED);
end;

procedure TTestRdxKeywordCaseFix.Moved_Or_Part_Of_Identifier_Refused;
var
  Reason : string;
begin
  // Teil eines Bezeichners.
  CheckRefused(InBody(['Beginner := 1;']), 6, 'Begin', KC_MOVED);
  CheckRefused(InBody(['  MyEnd := 1;']), 6, 'End', KC_MOVED);
  CheckRefused(InBody(['  EndX := 1;']), 6, 'End', KC_MOVED);
  // Spalte verschoben, Schreibweise anders, Zeile gibt es nicht.
  Assert.AreEqual('', TryFix(InBody(['  If X then Y;']), 6, 'If', 5, Reason));
  Assert.AreEqual(KC_MOVED, Reason);
  Assert.AreEqual('', TryFix(InBody(['  If X then Y;']), 6, 'IF', 3, Reason));
  Assert.AreEqual(KC_MOVED, Reason);
  Assert.AreEqual('', TryFix(InBody(['  If X then Y;']), 99, 'If', 3, Reason));
  Assert.AreEqual(KC_MOVED, Reason);
  // Schon klein; Meldung ohne Spalte; Meldung ohne Wort.
  Assert.AreEqual('', TryFix(InBody(['  if X then Y;']), 6, 'if', 3, Reason));
  Assert.AreEqual(KC_LOWER, Reason);
  Assert.AreEqual('', TryFixMsg(InBody(['  If X then Y;']), 6,
    'Keyword "If" should be lowercase.', Reason));
  Assert.AreEqual(KC_NO_WORD, Reason);
  Assert.AreEqual('', TryFixMsg(InBody(['  If X then Y;']), 6,
    'at column 3', Reason));
  Assert.AreEqual(KC_NO_WORD, Reason);
end;

procedure TTestRdxKeywordCaseFix.Member_Escape_NamedArgument_Refused;
begin
  CheckRefused(InBody(['  Foo.End := 1;']), 6, 'End', KC_IDENT);
  CheckRefused(InBody(['  Foo. End := 1;']), 6, 'End', KC_IDENT);
  CheckRefused(InBody(['  X := Y.Type;']), 6, 'Type', KC_IDENT);
  CheckRefused(InBody(['  &Begin := 1;']), 6, 'Begin', KC_IDENT);
  CheckRefused(InBody(['  @@End:']), 6, 'End', KC_IDENT);
  CheckRefused(InBody(['  R.Range(Start := 0, End := 1);']), 6, 'End',
    KC_IDENT);
end;

procedure TTestRdxKeywordCaseFix.Context_Words_Refused;
var
  W : string;
begin
  CheckRefused(InBody(['  On E: Exception do Y;']), 6, 'On',
    Format(KC_CONTEXT, ['On']));
  CheckRefused(InBody(['  X := Contains(Y);']), 6, 'Contains',
    Format(KC_CONTEXT, ['Contains']));
  for W in ['Out', 'Requires', 'Implements', 'Absolute'] do
    CheckRefused(InBody(['  ' + W + ' Y;']), 6, W, Format(KC_CONTEXT, [W]));
end;

{ ---- Sichtbarkeit, Direktiven, Modifikatoren ---- }

const
  VIS_UNIT: array[0..14] of string = ('unit u;', 'interface', 'type',
    '  TFoo = class', '  Private', '    FX: Integer;', '  Protected',
    '    procedure A;', '  Strict Private', '    FY: Integer;', '  PUBLIC',
    '    property P: Integer read FX;', '  end;', 'implementation', 'end.');

procedure TTestRdxKeywordCaseFix.Visibility_Positive;
var
  Src : string;
begin
  Src := Join(VIS_UNIT);
  CheckFix(Src, 5, 'Private');
  CheckFix(Src, 7, 'Protected');
  CheckFix(Src, 9, 'Strict');
  // Das Private hinter Strict: eigener Fund an eigener Spalte.
  CheckFix(Src, 9, 'Private');
  CheckFix(Src, 11, 'PUBLIC');
end;

procedure TTestRdxKeywordCaseFix.Visibility_Refused;
begin
  // Ein Feld heisst Public: dahinter steht ':'.
  CheckRefused(Join(['unit u;', 'interface', 'type', '  TFoo = class',
    '    Public: Integer;', '  end;', 'implementation', 'end.']), 5,
    'Public', Format(KC_CONTEXT, ['Public']));
  // Als Anweisung und als Parametername.
  CheckRefused(InBody(['  Private;']), 6, 'Private',
    Format(KC_CONTEXT, ['Private']));
  CheckRefused(Join(['unit u;', 'interface', 'implementation',
    'procedure Q(Private: Integer);', 'begin', 'end;', 'end.']), 4,
    'Private', Format(KC_CONTEXT, ['Private']));
end;

const
  DIR_UNIT: array[0..9] of string = ('unit u;', 'interface', 'type',
    '  TFoo = class', '    procedure A; Virtual;',
    '    function B(X: Integer): Integer; Override; Overload;', '  end;',
    '  TProc = procedure(A: Integer); StdCall;', 'implementation', 'end.');

procedure TTestRdxKeywordCaseFix.Directives_Positive;
var
  Src : string;
begin
  Src := Join(DIR_UNIT);
  CheckFix(Src, 5, 'Virtual');
  CheckFix(Src, 6, 'Override');
  // Zweite Direktive der Kette.
  CheckFix(Src, 6, 'Overload');
  CheckFix(Src, 8, 'StdCall');
end;

procedure TTestRdxKeywordCaseFix.Directives_As_Statement_Refused;
begin
  // Ein Aufruf 'Register;' im Rumpf ist keine Direktive.
  CheckRefused(InBody(['  Foo;', '  Register;']), 7, 'Register',
    Format(KC_CONTEXT, ['Register']));
  CheckRefused(InBody(['  Override;']), 6, 'Override',
    Format(KC_CONTEXT, ['Override']));
  CheckRefused(Join(['unit u;', 'interface', 'implementation', 'var',
    '  Virtual: Integer;', 'end.']), 5, 'Virtual',
    Format(KC_CONTEXT, ['Virtual']));
end;

procedure TTestRdxKeywordCaseFix.Directives_FieldAfterProcType_Refused;
var
  Src : string;
begin
  // Rueckwaerts sieht das Feld hinter einem Prozedurtyp-Member aus wie eine
  // Direktive im Kopf ('; ... procedure'); dahinter steht aber ':' - ein
  // Feldname, RTTI-sichtbar.
  Src := Join(['unit u;', 'interface', 'type', '  TJob = class',
    '    OnDone: procedure of object;', '    Forward: Boolean;',
    '    Cb: procedure; Register: Integer;', '  end;', 'implementation',
    'end.']);
  CheckRefused(Src, 6, 'Forward', Format(KC_CONTEXT, ['Forward']));
  CheckRefused(Src, 7, 'Register', Format(KC_CONTEXT, ['Register']));
end;

procedure TTestRdxKeywordCaseFix.Operator_And_Strict;
begin
  // 'operator' hinter 'class' im Record (IsClassModifier).
  CheckFix(Join(['unit u;', 'interface', 'type', '  TR = record',
    '    class Operator Add(const A, B: TR): TR;', '  end;',
    'implementation', 'end.']), 5, 'Operator');
  // 'Strict' ausserhalb eines Klassenkoerpers ist ein Bezeichner.
  CheckRefused(InBody(['  X := Strict;']), 6, 'Strict',
    Format(KC_CONTEXT, ['Strict']));
end;

procedure TTestRdxKeywordCaseFix.Class_Modifiers;
var
  Src : string;
begin
  Src := Join(['unit u;', 'interface', 'type', '  TA = class Abstract;',
    '  TB = class Sealed(TObject) end;', '  TC = class Helper for TObject end;',
    'implementation', 'end.']);
  CheckFix(Src, 4, 'Abstract');
  CheckFix(Src, 5, 'Sealed');
  CheckFix(Src, 6, 'Helper');
end;

{ ---- Adapter ---- }

procedure TTestRdxKeywordCaseFix.Adapter_Name_And_Edit;
var
  Src     : string;
  Seen    : TSeen;
  O       : TRdxFixOutcome;
begin
  Src := InBody(['  Begin', '  End;']);
  Seen.Line := 6;
  Seen.Msg := Msg('Begin', 3);
  Seen.Variant := '';
  O := PlanOf(Src, Seen);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual('Begin', O.Name);
  Assert.AreEqual<Integer>(1, Integer(Length(O.Edits)));
  Assert.AreEqual('Begin', O.Edits[0].Expected);
  Assert.AreEqual('begin', O.Edits[0].NewText);
  Assert.AreEqual(Swapped(Src, 6, 3, 'Begin'), Apply(Src, O.Edits));
end;

procedure TTestRdxKeywordCaseFix.Adapter_Refusal_And_NoFile;
var
  Seen    : TSeen;
  O       : TRdxFixOutcome;
  Finding : TLeakFinding;
begin
  Seen.Line := 6;
  Seen.Msg := Msg('End', 7);
  Seen.Variant := '';
  O := PlanOf(InBody(['  Foo.End := 1;']), Seen);
  Assert.IsFalse(O.Enabled);
  Assert.AreEqual(KC_IDENT, O.Reason);
  Assert.AreEqual<Integer>(0, Integer(Length(O.Edits)));
  Assert.AreEqual('End', O.Name);
  // Ohne Zeilen: keine Datei.
  Finding := TLeakFinding.New('t.pas', '', 6, Msg('End', 7),
    fkLowercaseKeyword);
  try
    O := TRdxFixTable.FixFor(nil, nil, Finding, nil);
  finally
    Finding.Free;
  end;
  Assert.IsFalse(O.Enabled);
  Assert.AreEqual(R_NO_FILE, O.Reason);
end;

{ ---- echter Detektor ---- }

procedure TTestRdxKeywordCaseFix.Detector_CatalogExample;
var
  Meta      : TRuleMeta;
  Bad, Done : string;
  Left      : Integer;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkLowercaseKeyword);
  Bad := CatalogUnit(Meta.BadExample);
  // Procedure, Begin, If, End.
  Assert.AreEqual<Integer>(4, Integer(Length(Detect(Bad))), Meta.BadExample);
  Done := FixPossible(Bad, Left);
  Assert.AreEqual<Integer>(0, Left);
  Assert.AreEqual(CatalogUnit(Meta.GoodExample), Done);
end;

procedure TTestRdxKeywordCaseFix.Detector_MixedUnit_RoundTrip;
var
  Src, Want, Done : string;
  Left            : Integer;
begin
  Src := Join(['Unit t;', 'Interface', 'Type', '  TFoo = Class',
    '  Private', '    FX: Integer;', '  Public', '    Procedure Run; Virtual;',
    '  End;', 'Implementation', 'Procedure TFoo.Run;', 'Begin',
    '  If FX > 0 Then', '    FX := 0; // Begin im Kommentar',
    '  S := ''End of Begin'';', 'End;', 'End.']);
  Want := Join(['unit t;', 'interface', 'type', '  TFoo = class',
    '  private', '    FX: Integer;', '  public', '    procedure Run; virtual;',
    '  end;', 'implementation', 'procedure TFoo.Run;', 'begin',
    '  if FX > 0 then', '    FX := 0; // Begin im Kommentar',
    '  S := ''End of Begin'';', 'end;', 'end.']);
  Assert.IsTrue(Length(Detect(Src)) >= 15, 'der Detektor meldet');
  Done := FixPossible(Src, Left);
  Assert.AreEqual<Integer>(0, Left);
  Assert.AreEqual(Want, Done);
  Assert.AreEqual<Integer>(0, Integer(Length(Detect(Done))));
end;

procedure TTestRdxKeywordCaseFix.Detector_Refused_Findings_Remain;
var
  Src, Done : string;
  Left      : Integer;
begin
  // Der Detektor meldet alle drei; zu keinem gibt es eine sichere Hilfe.
  Src := Join(['unit t;', 'interface', 'implementation',
    'procedure P(Out A: Integer);', 'begin', '  X := Contains(1);',
    '  Register;', 'end;', 'end.']);
  Assert.AreEqual<Integer>(3, Integer(Length(Detect(Src))));
  Done := FixPossible(Src, Left);
  Assert.AreEqual<Integer>(3, Left);
  Assert.AreEqual(Src, Done);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxKeywordCaseFix);

end.
