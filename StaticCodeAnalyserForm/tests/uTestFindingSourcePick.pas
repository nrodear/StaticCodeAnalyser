unit uTestFindingSourcePick;

// Tests fuer uFindingSourcePick (SCA.SharedUI): aus welcher Quelle
// Editor-Kontextmenue und Gluehbirne die Funde einer Datei nehmen - Dock
// oder Silent-Kopien, je Datei die juengere (Review reDelphiX nach
// Bereichen 2026-10-10, Minor 19; herausgezogen Review 2026-10-14).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFindingSourcePick = class
  public
    [Test] procedure OnlyDock_UsesDock;
    [Test] procedure OnlySilent_UsesSilent;
    [Test] procedure Neither_None;
    [Test] procedure Both_SilentNewer_UsesSilent;
    [Test] procedure Both_DockNewerOrSame_UsesDock;
    [Test] procedure DockGeneration_TakesNewerWatchRun;
  end;

implementation

uses
  uFindingSourcePick;

function State(ADock: Boolean; ADockGen: UInt64; ASilent: Boolean;
  ASilentGen: UInt64): TFindingSourceState;
begin
  Result.DockHasFile   := ADock;
  Result.DockGen       := ADockGen;
  Result.SilentHasFile := ASilent;
  Result.SilentGen     := ASilentGen;
end;

procedure TTestFindingSourcePick.OnlyDock_UsesDock;
begin
  Assert.AreEqual<Integer>(Ord(fsDock),
    Ord(PickFindingSource(State(True, 5, False, 9))),
    'ohne Silent-Kopien zaehlt deren Stand nicht');
end;

procedure TTestFindingSourcePick.OnlySilent_UsesSilent;
begin
  Assert.AreEqual<Integer>(Ord(fsSilent),
    Ord(PickFindingSource(State(False, 9, True, 2))),
    'ohne Dock-Funde dieser Datei zaehlt dessen Stand nicht');
end;

procedure TTestFindingSourcePick.Neither_None;
begin
  Assert.AreEqual<Integer>(Ord(fsNone),
    Ord(PickFindingSource(State(False, 0, False, 0))));
end;

procedure TTestFindingSourcePick.Both_SilentNewer_UsesSilent;
begin
  Assert.AreEqual<Integer>(Ord(fsSilent),
    Ord(PickFindingSource(State(True, 5, True, 6))),
    'der juengere Silent-Lauf gewinnt - nie zeilenweise gemischt');
end;

procedure TTestFindingSourcePick.Both_DockNewerOrSame_UsesDock;
begin
  Assert.AreEqual<Integer>(Ord(fsDock),
    Ord(PickFindingSource(State(True, 7, True, 6))));
  Assert.AreEqual<Integer>(Ord(fsDock),
    Ord(PickFindingSource(State(True, 6, True, 6))),
    'Gleichstand: das Dock, das der Benutzer sieht');
end;

procedure TTestFindingSourcePick.DockGeneration_TakesNewerWatchRun;
begin
  Assert.IsTrue(DockGenerationFor(10, 0) = 10, 'kein Watch-Lauf');
  Assert.IsTrue(DockGenerationFor(10, 12) = 12, 'juengerer Watch-Lauf');
  Assert.IsTrue(DockGenerationFor(10, 8) = 10, 'aelterer Watch-Lauf zaehlt nicht');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFindingSourcePick);

end.
