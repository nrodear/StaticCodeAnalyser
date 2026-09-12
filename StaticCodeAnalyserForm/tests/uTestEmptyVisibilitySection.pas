unit uTestEmptyVisibilitySection;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEmptyVisibilitySection = class
  public
    [Test] procedure FilledSections_NoFinding;
    [Test] procedure EmptyPublicBeforePrivate_Reported;
    [Test] procedure EmptyAtClassEnd_Reported;
    [Test] procedure EmptyVisibilitySection_KindAndSeverity;
    [Test] procedure AttributedMembersOnly_NoFinding;
    [Test] procedure EmptyDespiteAttributeInNextSection_StillReported;
    // Voll-Review 2026-09-12 (Major 61): Kommentar-Fortsetzungszeilen
    [Test] procedure CommentContinuationPrivate_NoPhantomSection;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

// DUnitX-Fixture-Form: die public-Section enthaelt NUR attributierte
// Member ('[Test] procedure ...'). Vor dem Fix galt sie als leer, weil
// Attribut-Zeilen uebersprungen statt als Inhalt gezaehlt wurden - 226
// False-Positives allein im eigenen Testverzeichnis.
procedure TTestEmptyVisibilitySection.AttributedMembersOnly_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFixture = class'#13#10 +
  '  public'#13#10 +
  '    [Test] procedure One;'#13#10 +
  '    [Test]'#13#10 +
  '    procedure Two;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyVisibilitySection));
  finally F.Free; end;
end;

// Gegenrichtung: eine WIRKLICH leere Section vor einer Section, deren
// erster Member ein Attribut traegt, wird weiterhin gemeldet - das
// Attribut gehoert zum Member NACH dem zweiten Keyword, nicht zur
// leeren Section davor.
procedure TTestEmptyVisibilitySection.EmptyDespiteAttributeInNextSection_StillReported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '  private'#13#10 +
  '    [Weak] FRef: TObject;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkEmptyVisibilitySection));
  finally F.Free; end;
end;

procedure TTestEmptyVisibilitySection.FilledSections_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FX: Integer;'#13#10 +
  '  public'#13#10 +
  '    procedure Bar;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyVisibilitySection));
  finally F.Free; end;
end;

procedure TTestEmptyVisibilitySection.EmptyPublicBeforePrivate_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '  private'#13#10 +
  '    FX: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkEmptyVisibilitySection));
  finally F.Free; end;
end;

procedure TTestEmptyVisibilitySection.EmptyAtClassEnd_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FX: Integer;'#13#10 +
  '  public'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkEmptyVisibilitySection));
  finally F.Free; end;
end;

procedure TTestEmptyVisibilitySection.EmptyVisibilitySection_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  public'#13#10 +
  '  private FX: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkEmptyVisibilitySection then
      begin
        Assert.AreEqual<TFindingKind>(fkEmptyVisibilitySection, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,                  Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkEmptyVisibilitySection finding');
  finally F.Free; end;
end;

procedure TTestEmptyVisibilitySection.CommentContinuationPrivate_NoPhantomSection;
// Voll-Review 2026-09-12 (Major 61): 'private ...' in der
// Fortsetzungszeile eines mehrzeiligen Blockkommentars setzte
// LastVis, und das folgende 'end' meldete eine leere private-Section,
// die es nie gab (Bestands-Exe: 1 FP, empirisch belegt, ev1.pas).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    procedure P;'#13#10 +
  '    { Hinweis:'#13#10 +
  '      private Daten nicht anfassen }'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.P; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkEmptyVisibilitySection),
    'private im Kommentar eroeffnet keine Section');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEmptyVisibilitySection);

end.
