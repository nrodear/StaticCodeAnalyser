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
  System.SysUtils, System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog,
  uUnusedRoutine, uUnusedPrivateMethod, uEmptyVisibilitySection,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uTestRdxDetectorKit;   // TSeen, Join, Detect-/Plan-/Apply-Helfer (Charge H3c)

// ---- Helfer (die gemeinsamen seit Charge H3c in uTestRdxDetectorKit) ----

// Der Verteiler fuer den echten Detektor der Art AKind (TDetectorRun).
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  case AKind of
    fkUnusedRoutine:
      TUnusedRoutineDetector.AnalyzeUnit(Root, Path, Results);
    fkUnusedPrivateMethod:
      TUnusedPrivateMethodDetector.AnalyzeUnit(Root, Path, Results);
    fkEmptyVisibilitySection:
      TEmptyVisibilitySectionDetector.AnalyzeUnit(Root, Path, Results);
  else
    Assert.Fail('kein Detektor fuer diese Art');
  end;
end;

// Funde der Art AKind - der echte Detektor auf dem echten AST.
function Detect(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := DetectSource('rdx_routine_', ASource, AKind, RunDetector);
end;

// Fund fuer Fund, bis der Detektor schweigt (uTestRdxDetectorKit).
function FixAll(const ASource: string; AKind: TFindingKind): string;
begin
  Result := FixAllWith(ASource, AKind, Detect);
end;

// Der erste Fund muss abgelehnt werden, mit AReasonPart im Grund.
procedure AssertNoHelp(const ASource: string; AKind: TFindingKind;
  const AReasonPart: string);
begin
  AssertNoHelpWith(ASource, AKind, AReasonPart, Detect);
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
    FixAll(Join(['unit t;', 'interface', CatalogText(Meta.BadExample)]),
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
  // '///' an der Deklaration, Kommentar (er nennt die Methode - seit
  // Charge H3c bleibt einer ohne den Namen) und Leerzeile an der
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
      '// Dead: old helper', 'procedure TFoo.Dead(A: Integer);', 'begin',
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
  Res := FixAll(Join(['unit t;', 'interface', 'type',
    CatalogText(Meta.BadExample), 'implementation', 'procedure TFoo.HelperA;',
    'begin', 'end;', '', 'procedure TFoo.DoStuff;', 'begin', 'end;', 'end.']),
    fkUnusedPrivateMethod);
  Assert.AreEqual<Integer>(1, Length(Detect(Res, fkEmptyVisibilitySection)),
    'SCA087 meldet den leeren Abschnitt');
  Good := CatalogText(Meta.GoodExample);
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
  Pas := TempName('rdx_routine_', '.pas');
  Fmx := ChangeFileExt(Pas, '.fmx');
  WriteText(Pas, Src);
  WriteText(Fmx, Join(['object Form1: TForm1', '  OnShow = FormShow', 'end']));
  try
    Seen := DetectFile(Pas, fkUnusedPrivateMethod, RunDetector);
    Assert.AreEqual<Integer>(1, Length(Seen), 'der Detektor meldet');
    O := PlanFixIn(Src, Pas, fkUnusedPrivateMethod, Seen[0]);
    Assert.IsFalse(O.Enabled, 'keine Hilfe');
    Assert.IsTrue(Pos('Formdatei', O.Reason) > 0, O.Reason);
    // Ohne Formdatei hilft sie.
    O := PlanFixIn(Src, 't.pas', fkUnusedPrivateMethod, Seen[0]);
    Assert.IsTrue(O.Enabled, O.Reason);
  finally
    DeleteFile(Fmx);
    DeleteFile(Pas);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxRoutineFixesDetector);

end.
