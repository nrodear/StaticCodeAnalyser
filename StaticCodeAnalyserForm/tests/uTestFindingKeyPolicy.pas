unit uTestFindingKeyPolicy;

// Tests fuer die Tasten-Policy in uFindingActionMenu
// (TFindingMenuModel.FirstRunnable, Konzept Editorhilfen Entscheid E2),
// die sichere Kind-Vorgabe fakUnset in uFindingActions und die
// Fund-Identitaet FindingIdentityKey (Review 2026-10-14). Zweite Fixture
// neben uTestFindingActionMenu, die mit 17 Tests nahe der Grenze liegt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFindingKeyPolicy = class
  public
    [Test] procedure FirstRunnable_FirstOfKind_SkipsOtherKinds;
    [Test] procedure FirstRunnable_Disabled_NamesTheFirstSkipped;
    [Test] procedure FirstRunnable_ChangesBehavior_SkippedButLaterRunnableWins;
    [Test] procedure FirstRunnable_NoneOfKind_LetsHostFallBack;
    [Test] procedure DefaultKind_IsUnset_NeverByKey_NeverInBulb_ButInMenu;
    [Test] procedure IdentityKey_SameForCopies_DiffersByKindLineMessage;
    [Test] procedure Refactors_ManyFindings_StillOncePerMenu;
  end;

implementation

uses
  System.SysUtils,
  uMethodd12, uSCAConsts, uFindingActions, uFindingActionMenu;

type
  TExecOwner = class
    Ran : Integer;
    procedure DoExecute(Sender: TObject);
  end;

var
  GExecOwner : TExecOwner = nil;

const
  HINT_PREFIX   = 'Grund ';
  CAP_FORGOTTEN = 'Vergessen';

procedure TExecOwner.DoExecute(Sender: TObject);
begin
  Inc(Ran);
end;

// Eine Aktion mit Execute; AEnabled = False heisst "gesperrt, Grund im
// Hint" - genau so liefert ein Anbieter sie (Execute darf dann auch nil
// sein, fuer die Policy zaehlt Enabled).
function Act(const ACaption: string; AKind: TFindingActionKind;
  AEnabled: Boolean): TFindingAction;
begin
  Result := Default(TFindingAction);
  Result.Caption := ACaption;
  Result.Hint    := HINT_PREFIX + ACaption;
  Result.Kind    := AKind;
  Result.Enabled := AEnabled;
  Result.Execute := GExecOwner.DoExecute;
end;

function ModelOf(const AActions: TArray<TFindingAction>): TFindingMenuModel;
var
  F     : TLeakFinding;
  Lists : TArray<TArray<TFindingAction>>;
begin
  F := TLeakFinding.New('Unit1.pas', 'Run', 10, 'Fund', fkConcatToFormat);
  try
    SetLength(Lists, 1);
    Lists[0] := AActions;
    Result := BuildFindingMenuModelFrom([F], Lists, []);
  finally
    F.Free;
  end;
end;

procedure TTestFindingKeyPolicy.FirstRunnable_FirstOfKind_SkipsOtherKinds;
var
  M : TFindingMenuModel;
  C : TFindingKeyChoice;
begin
  M := ModelOf([Act('Zeigen', fakNavigate, True), Act('Fix 1', fakFix, True),
    Act('Fix 2', fakFix, True), Act('Marker', fakSuppress, True)]);
  C := M.FirstRunnable(fakFix);
  Assert.IsTrue(C.Verdict = kvRun);
  Assert.AreEqual('Fix 1', M.Actions[C.Index].Caption, 'die ERSTE ihrer Art');
  C := M.FirstRunnable(fakSuppress);
  Assert.IsTrue(C.Verdict = kvRun);
  Assert.AreEqual('Marker', M.Actions[C.Index].Caption);
end;

procedure TTestFindingKeyPolicy.FirstRunnable_Disabled_NamesTheFirstSkipped;
var
  M : TFindingMenuModel;
  C : TFindingKeyChoice;
begin
  M := ModelOf([Act('Fix A', fakFix, False), Act('Fix B', fakFix, False)]);
  C := M.FirstRunnable(fakFix);
  Assert.IsTrue(C.Verdict = kvDisabled);
  Assert.AreEqual(HINT_PREFIX + 'Fix A', M.Actions[C.Index].Hint,
    'der Host nennt den Grund der ERSTEN ausgelassenen');
end;

procedure TTestFindingKeyPolicy.FirstRunnable_ChangesBehavior_SkippedButLaterRunnableWins;
var
  M : TFindingMenuModel;
  A : TFindingAction;
  C : TFindingKeyChoice;
begin
  A := Act('Riskant', fakFix, True);
  A.ChangesBehavior := True;
  M := ModelOf([A]);
  C := M.FirstRunnable(fakFix);
  Assert.IsTrue(C.Verdict = kvChangesBehavior,
    'verhaltensaendernde Hilfe gibt es nur gesehen (E2)');
  Assert.AreEqual('Riskant', M.Actions[C.Index].Caption);
  // Eine spaetere, ungefaehrliche Hilfe derselben Art gewinnt.
  M := ModelOf([A, Act('Harmlos', fakFix, True)]);
  C := M.FirstRunnable(fakFix);
  Assert.IsTrue(C.Verdict = kvRun);
  Assert.AreEqual('Harmlos', M.Actions[C.Index].Caption);
  // Gesperrt VOR verhaltensaendernd: der erste Grund gewinnt.
  M := ModelOf([Act('Gesperrt', fakFix, False), A]);
  C := M.FirstRunnable(fakFix);
  Assert.IsTrue(C.Verdict = kvDisabled);
  Assert.AreEqual('Gesperrt', M.Actions[C.Index].Caption);
end;

procedure TTestFindingKeyPolicy.FirstRunnable_NoneOfKind_LetsHostFallBack;
// Ctrl+Alt+S bei einem Config-/DFM-Fund: reDelphix bietet dort keinen
// Unterdrueck-Eintrag - der Host muss das erkennen und selbst schreiben
// (Review 2026-10-14, MAJOR 1).
var
  M : TFindingMenuModel;
  C : TFindingKeyChoice;
begin
  M := ModelOf([Act('Zeigen', fakNavigate, True), Act('Fix', fakFix, True)]);
  C := M.FirstRunnable(fakSuppress);
  Assert.IsTrue(C.Verdict = kvNone);
  Assert.AreEqual<Integer>(-1, C.Index);
  M := ModelOf(nil);
  Assert.IsTrue(M.FirstRunnable(fakFix).Verdict = kvNone, 'leeres Modell');
end;

procedure TTestFindingKeyPolicy.DefaultKind_IsUnset_NeverByKey_NeverInBulb_ButInMenu;
var
  A     : TFindingAction;
  F     : TLeakFinding;
  Lists : TArray<TArray<TFindingAction>>;
  M     : TFindingMenuModel;
begin
  A := Default(TFindingAction);
  Assert.IsTrue(A.Kind = fakUnset, 'die Vorgabe ist keine Hilfe');
  Assert.IsFalse(A.ChangesBehavior);
  A.Caption := CAP_FORGOTTEN;
  A.Enabled := True;
  A.Execute := GExecOwner.DoExecute;
  F := TLeakFinding.New('Unit1.pas', 'Run', 10, 'Fund', fkConcatToFormat);
  try
    SetLength(Lists, 1);
    Lists[0] := [A];
    M := BuildFindingMenuModelFrom([F], Lists, [moHeaders]);
    Assert.AreEqual<Integer>(1, M.ActionCount, 'im Kontextmenue sichtbar');
    Assert.IsTrue(M.Entries[1].Enabled, '... und wie angegeben klickbar');
    Assert.IsTrue(M.FirstRunnable(fakFix).Verdict = kvNone,
      'keine Taste fuehrt eine Aktion ohne Art aus');
    Assert.IsTrue(M.FirstRunnable(fakUnset).Verdict = kvRun,
      'nur wer ausdruecklich nach fakUnset fragt, bekaeme sie - kein Host tut das');
    M := BuildFindingMenuModelFrom([F], Lists, [moAvailableFixesOnly]);
    Assert.IsTrue(M.IsEmpty, 'nie in der Gluehbirne');
  finally
    F.Free;
  end;
end;

procedure TTestFindingKeyPolicy.IdentityKey_SameForCopies_DiffersByKindLineMessage;
var
  A, B : TLeakFinding;
begin
  Assert.AreEqual('', FindingIdentityKey(nil));
  A := TLeakFinding.New('Unit1.pas', 'Run', 10, 'Obj', fkMemoryLeak);
  B := TLeakFinding.New('Other.pas', 'Go', 10, 'Obj', fkMemoryLeak);
  try
    Assert.AreEqual(FindingIdentityKey(A), FindingIdentityKey(B),
      'Kopie aus einem anderen Scan: Datei und Methode zaehlen nicht');
    Assert.IsTrue(Pos(IntToStr(Ord(fkMemoryLeak)) + ':10:Obj',
      FindingIdentityKey(A)) = 1, FindingIdentityKey(A));
    B.LineNumber := '11';
    Assert.AreNotEqual(FindingIdentityKey(A), FindingIdentityKey(B), 'Zeile');
    B.LineNumber := '10';
    B.MissingVar := 'Obj2';
    Assert.AreNotEqual(FindingIdentityKey(A), FindingIdentityKey(B), 'Meldung');
    B.MissingVar := 'Obj';
    B.Kind := fkMissingFinally;
    Assert.AreNotEqual(FindingIdentityKey(A), FindingIdentityKey(B), 'Art');
  finally
    A.Free;
    B.Free;
  end;
end;

procedure TTestFindingKeyPolicy.Refactors_ManyFindings_StillOncePerMenu;
// Das Gedaechtnis der gezeigten Umbauten waechst je Fund einmal (Review
// 2026-10-14, Punkt 7) - das Ergebnis muss dasselbe bleiben wie zuvor.
var
  Many  : TArray<TLeakFinding>;
  Lists : TArray<TArray<TFindingAction>>;
  M     : TFindingMenuModel;
  i, n  : Integer;
  R1    : TFindingAction;
begin
  R1 := Act('uses qualifizieren', fakRefactor, True);
  SetLength(Many, 12);
  SetLength(Lists, 12);
  for i := 0 to High(Many) do
  begin
    Many[i] := TLeakFinding.New('Unit1.pas', 'Run', 10, 'Fund ' + IntToStr(i),
      fkUnsortedUses);
    Lists[i] := [R1, Act('Fix ' + IntToStr(i), fakFix, True),
      Act('Umbau ' + IntToStr(i), fakRefactor, True)];
  end;
  try
    M := BuildFindingMenuModelFrom(Many, Lists, [moHeaders]);
    n := 0;
    for i := 0 to High(M.Actions) do
      if M.Actions[i].Caption = R1.Caption then
        Inc(n);
    Assert.AreEqual<Integer>(1, n, 'derselbe Umbau nur einmal');
    Assert.AreEqual<Integer>(1 + 2 * Length(Many), M.ActionCount,
      'R1 einmal, je Fund die Hilfe und der eigene Umbau');
  finally
    for i := 0 to High(Many) do
      Many[i].Free;
  end;
end;

initialization
  GExecOwner := TExecOwner.Create;
  TDUnitX.RegisterTestFixture(TTestFindingKeyPolicy);

finalization
  FreeAndNil(GExecOwner);

end.
