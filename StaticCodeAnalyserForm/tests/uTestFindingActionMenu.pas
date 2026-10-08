unit uTestFindingActionMenu;

// Tests fuer uFindingActionMenu, das eine Menue-Modell zu den Aktionen am
// Fund (Konzept Editor-Gluehbirne 2026-10-06, Stufe C). Die reine Form
// wird mit synthetischen Aktionslisten geprueft, der Registry-Weg mit
// zwei Anbietern, von denen einer wirft. Jeder Anbieter wird wieder
// abgemeldet - die Registry ist prozessweit.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFindingActionMenu = class
  public
    [Test] procedure TwoFindings_SeparatorHeadersActions;
    [Test] procedure FindingWithoutActions_IsSkipped;
    [Test] procedure NoActionsAtAll_EmptyModel;
    [Test] procedure DisabledAction_KeepsHintInCaption;
    [Test] procedure ActionWithoutExecute_IsDisabled;
    [Test] procedure WithoutOptions_OnlyActions;
    [Test] procedure HeaderCaption_RuleAndTruncatedMessage;
    [Test] procedure ActionIndex_PointsIntoFlatList;
    [Test] procedure Registry_CollectsProviderErrors;
    // Gluehbirne: nur verfuegbare Hilfen - kein Navigieren, nichts
    // Ausgegrautes, nichts ohne Execute.
    [Test] procedure AvailableFixesOnly_DropsNavigateDisabledAndNoExecute;
    // Ein Fund, dem nach dem Filter nichts bleibt, faellt samt Kopf weg.
    [Test] procedure AvailableFixesOnly_FindingWithoutFixIsSkipped;
    // Ohne die Option bleibt alles wie bisher, auch das Navigieren.
    [Test] procedure WithoutFilter_NavigateStays;
  end;

implementation

uses
  System.SysUtils,
  uMethodd12, uSCAConsts, uFindingActions, uFindingActionMenu;

type
  TStubProvider = class
  public
    Captions : TArray<string>;
    Ran      : Integer;
    Throws   : Boolean;
    function Provide(const AFinding: TLeakFinding): TArray<TFindingAction>;
    procedure DoExecute(Sender: TObject);
  end;

var
  // Traeger der Execute-Methodenzeiger in den synthetischen Aktionen;
  // lebt von initialization bis finalization (kein Leck je Test).
  GExecOwner : TStubProvider = nil;

function TStubProvider.Provide(
  const AFinding: TLeakFinding): TArray<TFindingAction>;
var
  i : Integer;
begin
  if Throws then
    raise Exception.Create('kaputt');
  SetLength(Result, Length(Captions));
  for i := 0 to High(Captions) do
  begin
    Result[i].Caption := Captions[i];
    Result[i].Hint    := '';
    Result[i].Enabled := True;
    Result[i].Execute := DoExecute;
  end;
end;

procedure TStubProvider.DoExecute(Sender: TObject);
begin
  Inc(Ran);
end;

function Act(const ACaption, AHint: string; AEnabled: Boolean;
  AWithExecute: Boolean): TFindingAction;
begin
  Result := Default(TFindingAction);   // Kind = fakFix
  Result.Caption := ACaption;
  Result.Hint    := AHint;
  Result.Enabled := AEnabled;
  if AWithExecute then
    Result.Execute := GExecOwner.DoExecute
  else
    Result.Execute := nil;
end;

function Finding(const AMsg: string): TLeakFinding;
begin
  Result := TLeakFinding.New('C:\t.pas', 'Run', 10, AMsg, fkConcatToFormat);
end;

procedure TTestFindingActionMenu.TwoFindings_SeparatorHeadersActions;
var
  F1, F2 : TLeakFinding;
  Lists  : TArray<TArray<TFindingAction>>;
  M      : TFindingMenuModel;
begin
  F1 := Finding('Concat A'); F2 := Finding('Concat B');
  try
    SetLength(Lists, 2);
    Lists[0] := [Act('Stelle zeigen', 'Zeile 10', True, True),
                 Act('Format() bilden', '3 Terme', True, True)];
    Lists[1] := [Act('Stelle zeigen', 'Zeile 10', True, True)];
    M := BuildFindingMenuModelFrom([F1, F2], Lists,
      [moLeadingSeparator, moHeaders]);
    // Trenner, Kopf 1, 2 Aktionen, Kopf 2, 1 Aktion = 6 Eintraege
    Assert.AreEqual<Integer>(6, Length(M.Entries));
    Assert.AreEqual<Integer>(3, M.ActionCount);
    Assert.IsTrue(M.Entries[0].Kind = mkSeparator);
    Assert.AreEqual('-', M.Entries[0].Caption);
    Assert.IsTrue(M.Entries[1].Kind = mkHeader);
    Assert.IsFalse(M.Entries[1].Enabled, 'Kopfzeile ist nie klickbar');
    Assert.AreEqual<Integer>(-1, M.Entries[1].ActionIndex);
    Assert.IsTrue(M.Entries[2].Kind = mkAction);
    Assert.AreEqual('Stelle zeigen  (Zeile 10)', M.Entries[2].Caption);
    Assert.AreEqual<Integer>(0, M.Entries[2].ActionIndex);
    Assert.AreEqual('Format() bilden  (3 Terme)', M.Entries[3].Caption);
    Assert.AreEqual<Integer>(1, M.Entries[3].ActionIndex);
    Assert.IsTrue(M.Entries[4].Kind = mkHeader);
    Assert.AreEqual<Integer>(2, M.Entries[5].ActionIndex);
    Assert.IsFalse(M.IsEmpty);
  finally
    F1.Free; F2.Free;
  end;
end;

procedure TTestFindingActionMenu.FindingWithoutActions_IsSkipped;
var
  F1, F2 : TLeakFinding;
  Lists  : TArray<TArray<TFindingAction>>;
  M      : TFindingMenuModel;
begin
  F1 := Finding('ohne'); F2 := Finding('mit');
  try
    SetLength(Lists, 2);
    Lists[0] := nil;
    Lists[1] := [Act('Stelle zeigen', '', True, True)];
    M := BuildFindingMenuModelFrom([F1, F2], Lists, [moLeadingSeparator, moHeaders]);
    Assert.AreEqual<Integer>(3, Length(M.Entries), 'Trenner, Kopf, Aktion');
    Assert.IsTrue(Pos('mit', M.Entries[1].Caption) > 0, M.Entries[1].Caption);
    Assert.AreEqual('Stelle zeigen', M.Entries[2].Caption, 'ohne Hint keine Klammer');
  finally
    F1.Free; F2.Free;
  end;
end;

procedure TTestFindingActionMenu.NoActionsAtAll_EmptyModel;
var
  F     : TLeakFinding;
  Lists : TArray<TArray<TFindingAction>>;
  M     : TFindingMenuModel;
begin
  F := Finding('x');
  try
    SetLength(Lists, 1);
    M := BuildFindingMenuModelFrom([F], Lists, [moLeadingSeparator, moHeaders]);
    Assert.IsTrue(M.IsEmpty);
    Assert.AreEqual<Integer>(0, Length(M.Entries), 'auch kein Trenner');
    M := BuildFindingMenuModelFrom(nil, nil, [moLeadingSeparator]);
    Assert.IsTrue(M.IsEmpty);
  finally
    F.Free;
  end;
end;

procedure TTestFindingActionMenu.DisabledAction_KeepsHintInCaption;
var
  F     : TLeakFinding;
  Lists : TArray<TArray<TFindingAction>>;
  M     : TFindingMenuModel;
begin
  F := Finding('x');
  try
    SetLength(Lists, 1);
    Lists[0] := [Act('Format() bilden', 'Operand ''n'': kein String', False, False)];
    M := BuildFindingMenuModelFrom([F], Lists, []);
    Assert.AreEqual<Integer>(1, Length(M.Entries));
    Assert.IsFalse(M.Entries[0].Enabled);
    Assert.AreEqual('Format() bilden  (Operand ''n'': kein String)',
      M.Entries[0].Caption, 'der Grund steht in der Beschriftung');
    Assert.AreEqual('Operand ''n'': kein String', M.Entries[0].Hint);
  finally
    F.Free;
  end;
end;

procedure TTestFindingActionMenu.ActionWithoutExecute_IsDisabled;
var
  F     : TLeakFinding;
  Lists : TArray<TArray<TFindingAction>>;
  M     : TFindingMenuModel;
begin
  F := Finding('x');
  try
    SetLength(Lists, 1);
    Lists[0] := [Act('Tu was', '', True, False)];
    M := BuildFindingMenuModelFrom([F], Lists, []);
    Assert.IsFalse(M.Entries[0].Enabled, 'Enabled ohne Execute ist nicht klickbar');
  finally
    F.Free;
  end;
end;

procedure TTestFindingActionMenu.WithoutOptions_OnlyActions;
var
  F     : TLeakFinding;
  Lists : TArray<TArray<TFindingAction>>;
  M     : TFindingMenuModel;
begin
  F := Finding('x');
  try
    SetLength(Lists, 1);
    Lists[0] := [Act('A', '', True, True), Act('B', '', True, True)];
    M := BuildFindingMenuModelFrom([F], Lists, []);
    Assert.AreEqual<Integer>(2, Length(M.Entries));
    Assert.IsTrue(M.Entries[0].Kind = mkAction);
    Assert.IsTrue(M.Entries[1].Kind = mkAction);
  finally
    F.Free;
  end;
end;

procedure TTestFindingActionMenu.HeaderCaption_RuleAndTruncatedMessage;
var
  F   : TLeakFinding;
  Cap : string;
begin
  F := Finding(StringOfChar('m', 70) + '   ');
  try
    Cap := FindingHeaderCaption(F);
    Assert.IsTrue(Pos(F.ResolvedRuleId + '  ', Cap) = 1, 'Regel-ID zuerst: ' + Cap);
    Assert.IsTrue(Pos(StringOfChar('m', 60), Cap) > 0);
    Assert.IsFalse(Pos(StringOfChar('m', 61), Cap) > 0, 'auf 60 Zeichen gekuerzt');
    Assert.AreEqual('', FindingHeaderCaption(nil));
  finally
    F.Free;
  end;
end;

procedure TTestFindingActionMenu.ActionIndex_PointsIntoFlatList;
var
  F1, F2 : TLeakFinding;
  Lists  : TArray<TArray<TFindingAction>>;
  M      : TFindingMenuModel;
  i      : Integer;
begin
  F1 := Finding('a'); F2 := Finding('b');
  try
    SetLength(Lists, 2);
    Lists[0] := [Act('A1', '', True, True)];
    Lists[1] := [Act('B1', '', True, True), Act('B2', '', True, True)];
    M := BuildFindingMenuModelFrom([F1, F2], Lists, [moHeaders]);
    for i := 0 to High(M.Entries) do
      if M.Entries[i].Kind = mkAction then
        Assert.IsTrue(Pos(M.Actions[M.Entries[i].ActionIndex].Caption,
          M.Entries[i].Caption) = 1, 'Eintrag ' + IntToStr(i));
    Assert.AreEqual('B2', M.Actions[2].Caption);
  finally
    F1.Free; F2.Free;
  end;
end;

procedure TTestFindingActionMenu.Registry_CollectsProviderErrors;
var
  Good, Bad : TStubProvider;
  TG, TB    : Integer;
  F         : TLeakFinding;
  M         : TFindingMenuModel;
begin
  Good := TStubProvider.Create;
  Good.Captions := ['Stelle zeigen'];
  Bad := TStubProvider.Create;
  Bad.Throws := True;
  F := Finding('x');
  TG := TFindingActions.Register(Good.Provide);
  TB := TFindingActions.Register(Bad.Provide);
  try
    // ActionsFor wirft als Ganzes, wenn ein Anbieter wirft: die Meldung
    // landet in Errors, das Modell bleibt leer statt halb.
    M := BuildFindingMenuModel([F], [moLeadingSeparator]);
    Assert.AreEqual<Integer>(1, Length(M.Errors));
    Assert.IsTrue(Pos('kaputt', M.Errors[0]) > 0, M.Errors[0]);
    Assert.IsTrue(M.IsEmpty);
    TFindingActions.Unregister(TB);
    TB := 0;
    M := BuildFindingMenuModel([F], [moLeadingSeparator]);
    Assert.AreEqual<Integer>(0, Length(M.Errors));
    Assert.AreEqual<Integer>(1, M.ActionCount);
    Assert.AreEqual('Stelle zeigen', M.Actions[0].Caption);
    Assert.IsTrue(M.Entries[0].Kind = mkSeparator);
    M.Actions[0].Execute(nil);
    Assert.AreEqual<Integer>(1, Good.Ran);
  finally
    if TB <> 0 then TFindingActions.Unregister(TB);
    TFindingActions.Unregister(TG);
    F.Free;
    Bad.Free;
    Good.Free;
  end;
end;

function NavAct(const ACaption: string): TFindingAction;
begin
  Result := Act(ACaption, '', True, True);
  Result.Kind := fakNavigate;
end;

procedure TTestFindingActionMenu.AvailableFixesOnly_DropsNavigateDisabledAndNoExecute;
var
  F     : TLeakFinding;
  Lists : TArray<TArray<TFindingAction>>;
  M     : TFindingMenuModel;
begin
  F := Finding('x');
  try
    SetLength(Lists, 1);
    Lists[0] := [NavAct('Stelle zeigen'),
                 Act('Ersetzen', '3 Terme', True, True),
                 Act('Vorlage', 'kein SQL', False, False),
                 Act('Ohne Execute', '', True, False)];
    M := BuildFindingMenuModelFrom([F], Lists, [moHeaders, moAvailableFixesOnly]);
    Assert.AreEqual<Integer>(1, M.ActionCount, 'nur die eine verfuegbare Hilfe');
    Assert.AreEqual('Ersetzen', M.Actions[0].Caption);
    Assert.AreEqual<Integer>(2, Length(M.Entries), 'Kopf und Aktion');
    Assert.IsTrue(M.Entries[0].Kind = mkHeader);
    Assert.IsTrue(M.Entries[1].Kind = mkAction);
    Assert.AreEqual<Integer>(0, M.Entries[1].ActionIndex);
  finally
    F.Free;
  end;
end;

procedure TTestFindingActionMenu.AvailableFixesOnly_FindingWithoutFixIsSkipped;
var
  F1, F2 : TLeakFinding;
  Lists  : TArray<TArray<TFindingAction>>;
  M      : TFindingMenuModel;
begin
  F1 := Finding('nur hinfuehren'); F2 := Finding('mit Hilfe');
  try
    SetLength(Lists, 2);
    Lists[0] := [NavAct('Stelle zeigen'), Act('reDelphix: nichts', '', False, False)];
    Lists[1] := [Act('uses qualifizieren', '', True, True)];
    M := BuildFindingMenuModelFrom([F1, F2], Lists, [moHeaders, moAvailableFixesOnly]);
    Assert.AreEqual<Integer>(2, Length(M.Entries), 'nur Kopf und Aktion des zweiten');
    Assert.IsTrue(Pos('mit Hilfe', M.Entries[0].Caption) > 0, M.Entries[0].Caption);
    SetLength(Lists, 1);   // nur noch der erste Fund
    M := BuildFindingMenuModelFrom([F1], Lists, [moHeaders, moAvailableFixesOnly]);
    Assert.IsTrue(M.IsEmpty, 'ohne Hilfe keine Gluehbirne');
    Assert.AreEqual<Integer>(0, Length(M.Entries));
  finally
    F1.Free; F2.Free;
  end;
end;

procedure TTestFindingActionMenu.WithoutFilter_NavigateStays;
var
  F     : TLeakFinding;
  Lists : TArray<TArray<TFindingAction>>;
  M     : TFindingMenuModel;
begin
  F := Finding('x');
  try
    SetLength(Lists, 1);
    Lists[0] := [NavAct('Stelle zeigen'), Act('Vorlage', 'kein SQL', False, False)];
    M := BuildFindingMenuModelFrom([F], Lists, [moHeaders]);
    Assert.AreEqual<Integer>(2, M.ActionCount, 'Kontextmenue und Grid zeigen alles');
    Assert.IsTrue(M.Actions[0].Kind = fakNavigate);
  finally
    F.Free;
  end;
end;

initialization
  GExecOwner := TStubProvider.Create;
  TDUnitX.RegisterTestFixture(TTestFindingActionMenu);

finalization
  FreeAndNil(GExecOwner);

end.
