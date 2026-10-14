unit uTestRdxRoutineFixesDetector;

// SCA164 und SCA147 (Charge H3b, uRdxRoutineFixes) gegen die ECHTEN
// Detektoren: Fund -> Hilfe ueber den Einstieg des Anbieters
// (TRdxFixTable.FixFor) -> neu scannen -> Fund weg; die Katalog-Beispiele;
// Funde, die der Detektor meldet, die Hilfe aber ablehnt (Name als
// String-Literal - der Detektor streicht Strings vor der Suche -, eine
// .fmx neben der Unit nennt die Methode - der Detektor liest nur .dfm).
// Nur Delphi (Parser und Detektoren); die Planer-Faelle auf Text stehen in
// uTestRdxRoutineFixes und uTestRdxMethodFixes (auch im FPC-Pruefstand).
// Eigene Unit statt einer zehnten Fixture in uTestRdxSimpleFixesDetector:
// die Charge H3a ergaenzt jene Unit parallel.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxRoutineFixesDetector = class
  public
    [Test] procedure Sca164_RoundTrip;
    [Test] procedure Sca164_CatalogExample;
    [Test] procedure Sca164_StringLiteral_NoHelp;
    [Test] procedure Sca147_RoundTrip;
    [Test] procedure Sca147_CatalogExample_ThenSca087;
    [Test] procedure Sca147_StringLiteral_NoHelp;
    [Test] procedure Sca147_FmxNamesMethod_NoHelp;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uParser2, uMethodd12, uSCAConsts, uRuleCatalog,
  uUnusedRoutine, uUnusedPrivateMethod, uEmptyVisibilitySection,
  uEngineApi, uRdxBufferMath, uRdxRecipeRunner, uRdxFixTable;

type
  // Was die Hilfe aus einem Fund liest - wie der Anbieter aus TLeakFinding.
  TSeen = record
    Line : Integer;
    Msg  : string;
  end;

// ---- Helfer ----

function Join(const ALines: array of string): string;
begin
  Result := string.Join(#13#10, ALines);
end;

function TempName(const AExt: string): string;
begin
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP'))
    + 'rdx_routine_' + GUIDToString(TGUID.NewGuid) + AExt;
end;

procedure WriteText(const APath, AText: string);
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

// Funde der Art AKind in der Datei APath - der echte Detektor auf dem
// echten AST.
function DetectFile(const APath: string; AKind: TFindingKind): TArray<TSeen>;
var
  Parser  : TParser2;
  Root    : TAstNode;
  Results : TObjectList<TLeakFinding>;
  F       : TLeakFinding;
  n       : Integer;
begin
  Result := nil;
  Results := TObjectList<TLeakFinding>.Create(True);
  try
    Parser := TParser2.Create;
    try
      Root := Parser.ParseFile(APath);
      try
        case AKind of
          fkUnusedRoutine:
            TUnusedRoutineDetector.AnalyzeUnit(Root, APath, Results);
          fkUnusedPrivateMethod:
            TUnusedPrivateMethodDetector.AnalyzeUnit(Root, APath, Results);
          fkEmptyVisibilitySection:
            TEmptyVisibilitySectionDetector.AnalyzeUnit(Root, APath, Results);
        else
          Assert.Fail('kein Detektor fuer diese Art');
        end;
      finally
        Root.Free;
      end;
    finally
      Parser.Free;
    end;
    SetLength(Result, Results.Count);
    n := 0;
    for F in Results do
      if F.Kind = AKind then
      begin
        Result[n].Line := F.LineInt;
        Result[n].Msg := F.Message;
        Inc(n);
      end;
    SetLength(Result, n);
  finally
    Results.Free;
  end;
end;

function Detect(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
var
  Path : string;
begin
  Path := TempName('.pas');
  WriteText(Path, ASource);
  try
    Result := DetectFile(Path, AKind);
  finally
    DeleteFile(Path);
  end;
end;

// Die Hilfe fuer EINEN Fund ueber den Einstieg des Anbieters; AFile ist der
// Dateiname des Funds (die Formdatei-Pruefung von SCA147 liest daneben).
function PlanFix(const ASource, AFile: string; AKind: TFindingKind;
  const ASeen: TSeen): TRdxFixOutcome;
var
  SL      : TStringList;
  Places  : TSourcePlaces;
  Finding : TLeakFinding;
begin
  Assert.IsTrue(TRdxFixTable.Handles(AKind), 'FixFor kennt die Art');
  SL := TStringList.Create;
  Places := TSourcePlaces.Create;
  Finding := TLeakFinding.New(AFile, '', ASeen.Line, ASeen.Msg, AKind);
  try
    SL.Text := ASource;
    Assert.IsTrue(Places.OpenSource(AFile, ASource), 'OpenSource');
    Result := TRdxFixTable.FixFor(Places, SL, Finding,
      TRdxRecipeRunner.UsesNamesOf(Places));
  finally
    Finding.Free;
    Places.Free;
    SL.Free;
  end;
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

// Fund fuer Fund, nach jeder Ersetzung neu gemeldet, bis der Detektor
// schweigt.
function FixAll(const ASource: string; AKind: TFindingKind): string;
const
  MAX_PASSES = 10;
var
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
  Pass : Integer;
begin
  Result := ASource;
  for Pass := 1 to MAX_PASSES do
  begin
    Seen := Detect(Result, AKind);
    if Length(Seen) = 0 then Exit;
    O := PlanFix(Result, 't.pas', AKind, Seen[0]);
    Assert.IsTrue(O.Enabled, Format('Zeile %d: %s', [Seen[0].Line, O.Reason]));
    Result := Apply(Result, O.Edits);
  end;
  Assert.Fail(Format('der Detektor meldet nach %d Runden noch', [MAX_PASSES]));
end;

// Der erste Fund muss abgelehnt werden, mit AReasonPart im Grund.
procedure AssertNoHelp(const ASource: string; AKind: TFindingKind;
  const AReasonPart: string);
var
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  Seen := Detect(ASource, AKind);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet');
  O := PlanFix(ASource, 't.pas', AKind, Seen[0]);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.IsTrue(Pos(AReasonPart, O.Reason) > 0, O.Reason);
end;

function Snip(const AExample: string): string;
begin
  Result := StringReplace(AExample, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #10, #13#10, [rfReplaceAll]);
end;

// ---- SCA164 ----

procedure TTestRdxRoutineFixesDetector.Sca164_RoundTrip;
begin
  // Doku und Leerzeile dahinter gehen mit; der Einzeiler als Zeile, ohne
  // Leerzeile dahinter mit der davor. Keep bleibt, weil Run es ruft (Run
  // selbst steht im interface-Teil).
  Assert.AreEqual(
    Join(['unit t;', 'interface', 'procedure Run;', 'implementation', '',
      'procedure Keep;', 'begin', 'end;', 'procedure Run;', 'begin',
      '  Keep;', 'end;', '', 'end.']),
    FixAll(Join(['unit t;', 'interface', 'procedure Run;', 'implementation',
      '', '/// <summary>Old helper</summary>', 'procedure Dead(A: Integer);',
      'var', '  I: Integer;', 'begin', '  I := A;', 'end;', '',
      'procedure Keep;', 'begin', 'end;', '',
      'procedure Dead2; begin end;', 'procedure Run;', 'begin', '  Keep;',
      'end;', '', 'end.']), fkUnusedRoutine));
end;

procedure TTestRdxRoutineFixesDetector.Sca164_CatalogExample;
var
  Meta : TRuleMeta;
begin
  // 'good' beschreibt nur in Worten, was zu tun ist - die Hilfe loescht
  // die Routine samt ihrem Zeilenkommentar.
  Meta := TRuleCatalog.GetRuleCanonical(fkUnusedRoutine);
  Assert.IsTrue(Pos('remove InternalHelper', Meta.GoodExample) > 0,
    Meta.GoodExample);
  Assert.AreEqual(Join(['unit t;', 'interface', 'implementation', 'end.']),
    FixAll(Join(['unit t;', 'interface', Snip(Meta.BadExample)]),
    fkUnusedRoutine));
end;

procedure TTestRdxRoutineFixesDetector.Sca164_StringLiteral_NoHelp;
begin
  // Der Detektor streicht Strings vor der Suche und meldet - die Hilfe
  // nicht: 'Dead' kann per Name gerufen werden.
  AssertNoHelp(Join(['unit t;', 'interface', 'procedure Run;',
    'implementation', 'uses Winapi.Windows;', 'procedure Dead; stdcall;',
    'begin', 'end;', 'procedure Run;', 'begin',
    '  GetProcAddress(HInstance, ''Dead'');', 'end;', 'end.']),
    fkUnusedRoutine, 'String-Literal');
end;

// ---- SCA147 ----

procedure TTestRdxRoutineFixesDetector.Sca147_RoundTrip;
begin
  // '///' an der Deklaration, Kommentar und Leerzeile an der
  // Implementierung gehen mit. Ohne rekursiven Aufruf: den zaehlte der
  // Detektor als Verwendung (mehr als zwei Vorkommen) - der Planer-Fall
  // steht in uTestRdxMethodFixes.
  Assert.AreEqual(
    Join(['unit t;', 'interface', 'type', '  TFoo = class', '  private',
      '    procedure Used;', '  public', '    procedure Run;', '  end;',
      'implementation', '', 'procedure TFoo.Used;', 'begin', 'end;', '',
      'procedure TFoo.Run;', 'begin', '  Used;', 'end;', '', 'end.']),
    FixAll(Join(['unit t;', 'interface', 'type', '  TFoo = class',
      '  private', '    /// <summary>Old</summary>',
      '    procedure Dead(A: Integer);', '    procedure Used;', '  public',
      '    procedure Run;', '  end;', 'implementation', '',
      '// Old helper', 'procedure TFoo.Dead(A: Integer);', 'begin',
      'end;', '',
      'procedure TFoo.Used;', 'begin', 'end;', '', 'procedure TFoo.Run;',
      'begin', '  Used;', 'end;', '', 'end.']), fkUnusedPrivateMethod));
end;

procedure TTestRdxRoutineFixesDetector.Sca147_CatalogExample_ThenSca087;
var
  Meta      : TRuleMeta;
  Good, Res : string;
begin
  // Das Katalog-Beispiel bekommt eine Implementierung; nach der Hilfe
  // bleibt der leere private-Abschnitt - SCA087 meldet ihn, und dessen
  // Hilfe fuehrt genau zu 'good' (ohne die Zeile mit dem Rat in Worten).
  Meta := TRuleCatalog.GetRuleCanonical(fkUnusedPrivateMethod);
  Res := FixAll(Join(['unit t;', 'interface', 'type', Snip(Meta.BadExample),
    'implementation', 'procedure TFoo.HelperA;', 'begin', 'end;', '',
    'procedure TFoo.DoStuff;', 'begin', 'end;', 'end.']),
    fkUnusedPrivateMethod);
  Assert.AreEqual<Integer>(1, Length(Detect(Res, fkEmptyVisibilitySection)),
    'SCA087 meldet den leeren Abschnitt');
  Good := Snip(Meta.GoodExample);
  Good := Copy(Good, 1, Pos('end;', Good) + Length('end;') - 1);
  Assert.AreEqual(Join(['unit t;', 'interface', 'type', Good,
    'implementation', 'procedure TFoo.DoStuff;', 'begin', 'end;', 'end.']),
    FixAll(Res, fkEmptyVisibilitySection));
end;

procedure TTestRdxRoutineFixesDetector.Sca147_StringLiteral_NoHelp;
begin
  AssertNoHelp(Join(['unit t;', 'interface', 'type', '  TFoo = class',
    '  private', '    procedure Dead;', '  public', '    procedure Run;',
    '  end;', 'implementation', 'procedure TFoo.Dead;', 'begin', 'end;',
    'procedure TFoo.Run;', 'begin', '  MethodAddress(''Dead'');', 'end;',
    'end.']), fkUnusedPrivateMethod, 'String-Literal');
end;

procedure TTestRdxRoutineFixesDetector.Sca147_FmxNamesMethod_NoHelp;
var
  Src, Pas, Fmx : string;
  Seen          : TArray<TSeen>;
  O             : TRdxFixOutcome;
begin
  // Der Detektor liest nur die .dfm (und .lfm unter FPC) - eine .fmx, die
  // die Methode nennt, sieht er nicht und meldet; die Hilfe liest die
  // Formdatei-Schwestern und lehnt ab.
  Src := Join(['unit t;', 'interface', 'type', '  TForm1 = class',
    '  private', '    procedure FormShow(Sender: TObject);', '  end;',
    'implementation', 'procedure TForm1.FormShow(Sender: TObject);', 'begin',
    'end;', 'end.']);
  Pas := TempName('.pas');
  Fmx := ChangeFileExt(Pas, '.fmx');
  WriteText(Pas, Src);
  WriteText(Fmx, Join(['object Form1: TForm1', '  OnShow = FormShow', 'end']));
  try
    Seen := DetectFile(Pas, fkUnusedPrivateMethod);
    Assert.AreEqual<Integer>(1, Length(Seen), 'der Detektor meldet');
    O := PlanFix(Src, Pas, fkUnusedPrivateMethod, Seen[0]);
    Assert.IsFalse(O.Enabled, 'keine Hilfe');
    Assert.IsTrue(Pos('Formdatei', O.Reason) > 0, O.Reason);
    // Ohne Formdatei hilft sie.
    O := PlanFix(Src, 't.pas', fkUnusedPrivateMethod, Seen[0]);
    Assert.IsTrue(O.Enabled, O.Reason);
  finally
    DeleteFile(Fmx);
    DeleteFile(Pas);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxRoutineFixesDetector);

end.
