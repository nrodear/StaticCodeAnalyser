unit uTestContextActionMenu;

// Tests fuer die Code-Aktionen ohne Fund im Menuemodell
// (uFindingActionMenu.AppendContextActions / BuildEditorMenuModel; Charge
// B, V1, Entscheide Nico 2026-10-23 E14/E16): Kontextaktionen stehen
// hinter den Fund-Aktionen, gleiche Captions nur einmal (am Fund), nie in
// der Gluehbirne, nie per Taste. Die reine Form mit synthetischen Listen,
// der Registry-Weg mit Stub-Anbietern, die jeder Test wieder abmeldet.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestContextActionMenu = class
  public
    [Test] procedure Append_AfterFindingActions_SeparatorHeaderActions;
    [Test] procedure Append_SameCaptionAsFindingAction_Dropped;
    [Test] procedure Append_SameCaptionTwiceInContext_Once;
    [Test] procedure Append_CaptionDiffersOnlyInCase_Dropped;
    [Test] procedure Append_AllDuplicates_NothingAppended;
    [Test] procedure Append_EmptyModel_SeparatorOnlyWithOption;
    [Test] procedure Append_AvailableFixesOnly_NothingInBulb;
    [Test] procedure Append_StampsContext_KeysNeverRunIt;
    [Test] procedure Append_HeaderOnlyWithOptionAndText;
    [Test] procedure Append_ActionIndexPointsIntoTail;
    [Test] procedure Append_DisabledContextAction_StaysDisabled;
    [Test] procedure Editor_NoFindings_OnlyContextActions;
    [Test] procedure Editor_SameCaption_OnceAtTheFinding;
    [Test] procedure Editor_ContextProviderThrows_FindingActionsStay;
    [Test] procedure Editor_ContextProviderAbort_PassesThrough;
    [Test] procedure Editor_AvailableFixesOnly_ContextProviderNotAsked;
    [Test] procedure Editor_NoProviders_EmptyModel;
  end;

implementation

uses
  System.SysUtils,
  uMethodd12, uSCAConsts, uFindingActions, uFindingActionMenu;

const
  CTX_HEADER = 'Code actions';   // Testdaten; die echte Caption setzt der Host

type
  // Traeger der Execute-Zeiger und Stub fuer beide Anbieterarten.
  TStub = class
  public
    Captions : TArray<string>;
    Asked    : Integer;
    Ran      : Integer;
    Raises   : Integer;   // 1 = Exception, 2 = Abort
    function ProvideFinding(const AFinding: TLeakFinding): TArray<TFindingAction>;
    function ProvideContext(const AContext: TEditorContext): TArray<TFindingAction>;
    procedure DoExecute(Sender: TObject);
  end;

var
  GExec : TStub = nil;

function ActionsOf(AStub: TStub): TArray<TFindingAction>;
var
  i : Integer;
begin
  SetLength(Result, Length(AStub.Captions));
  for i := 0 to High(AStub.Captions) do
  begin
    Result[i] := Default(TFindingAction);
    Result[i].Caption := AStub.Captions[i];
    Result[i].Enabled := True;
    Result[i].Execute := AStub.DoExecute;
    Result[i].Kind    := fakFix;
  end;
end;

function TStub.ProvideFinding(
  const AFinding: TLeakFinding): TArray<TFindingAction>;
begin
  Inc(Asked);
  Result := ActionsOf(Self);
end;

function TStub.ProvideContext(
  const AContext: TEditorContext): TArray<TFindingAction>;
begin
  Inc(Asked);
  case Raises of
    1: raise Exception.Create('Kontext kaputt');
    2: Abort;
  end;
  Result := ActionsOf(Self);
end;

procedure TStub.DoExecute(Sender: TObject);
begin
  Inc(Ran);
end;

function Act(const ACaption: string; AKind: TFindingActionKind;
  AEnabled: Boolean = True): TFindingAction;
begin
  Result := Default(TFindingAction);
  Result.Caption := ACaption;
  Result.Kind    := AKind;
  Result.Enabled := AEnabled;
  if AEnabled then
    Result.Execute := GExec.DoExecute;
end;

function Finding(const AMsg: string): TLeakFinding;
begin
  Result := TLeakFinding.New('C:\t.pas', 'Run', 10, AMsg, fkConcatToFormat);
end;

// Modell mit einem Fund und seinen Aktionen (Kontextmenue-Form).
function FindingModel(F: TLeakFinding;
  const AActs: TArray<TFindingAction>): TFindingMenuModel;
var
  Lists : TArray<TArray<TFindingAction>>;
begin
  SetLength(Lists, 1);
  Lists[0] := AActs;
  Result := BuildFindingMenuModelFrom([F], Lists,
    [moLeadingSeparator, moHeaders]);
end;

procedure TTestContextActionMenu.Append_AfterFindingActions_SeparatorHeaderActions;
var
  F : TLeakFinding;
  M : TFindingMenuModel;
begin
  F := Finding('Concat A');
  try
    M := FindingModel(F, [Act('Stelle zeigen', fakNavigate)]);
    Assert.AreEqual<Integer>(3, Length(M.Entries), 'Trenner, Kopf, Aktion');
    AppendContextActions(M, [Act('Konstante', fakFix), Act('try/finally', fakFix)],
      [moLeadingSeparator, moHeaders], CTX_HEADER);
    Assert.AreEqual<Integer>(7, Length(M.Entries));
    Assert.IsTrue(M.Entries[3].Kind = mkSeparator, 'Trenner vor den Kontextaktionen');
    Assert.IsTrue(M.Entries[4].Kind = mkHeader);
    Assert.AreEqual(CTX_HEADER, M.Entries[4].Caption);
    // Code-Aktion, verfuegbar, bedeutungsgleich: '=' hinter #9 (Vorschlag 2)
    Assert.AreEqual('Konstante'#9'=', M.Entries[5].Caption);
    Assert.AreEqual('try/finally'#9'=', M.Entries[6].Caption);
    Assert.AreEqual<Integer>(4, M.ContextEntryCount, 'Trenner + Kopf + 2 Aktionen');
    Assert.AreEqual<Integer>(2, M.ContextActionCount);
    Assert.AreEqual<Integer>(3, M.ActionCount);
  finally
    F.Free;
  end;
end;

procedure TTestContextActionMenu.Append_SameCaptionAsFindingAction_Dropped;
var
  F : TLeakFinding;
  M : TFindingMenuModel;
  i : Integer;
  n : Integer;
begin
  F := Finding('Concat A');
  try
    M := FindingModel(F, [Act('Format() bilden', fakFix)]);
    AppendContextActions(M, [Act('Format() bilden', fakFix), Act('Konstante', fakFix)],
      [moLeadingSeparator, moHeaders], CTX_HEADER);
    n := 0;
    for i := 0 to High(M.Actions) do
      if M.Actions[i].Caption = 'Format() bilden' then
        Inc(n);
    Assert.AreEqual<Integer>(1, n, 'gleiche Caption nur einmal');
    Assert.IsTrue(M.Actions[0].Kind = fakFix, 'sie bleibt am Fund');
    Assert.AreEqual<Integer>(1, M.ContextActionCount);
    Assert.AreEqual('Konstante', M.Actions[1].Caption);
  finally
    F.Free;
  end;
end;

procedure TTestContextActionMenu.Append_SameCaptionTwiceInContext_Once;
var
  M : TFindingMenuModel;
begin
  M := Default(TFindingMenuModel);
  AppendContextActions(M, [Act('A', fakFix), Act('B', fakFix), Act('A', fakFix)],
    [], '');
  Assert.AreEqual<Integer>(2, M.ActionCount);
  Assert.AreEqual('A', M.Actions[0].Caption);
  Assert.AreEqual('B', M.Actions[1].Caption);
  // Ein zweiter Aufruf (zweiter Host-Durchgang) haengt nichts Doppeltes an.
  AppendContextActions(M, [Act('B', fakFix), Act('C', fakFix)], [], '');
  Assert.AreEqual<Integer>(3, M.ActionCount);
  Assert.AreEqual<Integer>(3, M.ContextActionCount);
end;

// Der Name im Menuetext der Fund-Hilfe SCA009 stammt aus der Meldung des
// Detektors, der der Kontextaktion aus dem Quelltext - gleich bis auf die
// Schreibweise ('List' / 'list'): trotzdem nur einmal, am Fund (Review
// Charge B, Befund 5). Auch innerhalb der Kontextliste.
procedure TTestContextActionMenu.Append_CaptionDiffersOnlyInCase_Dropped;
var
  F : TLeakFinding;
  M : TFindingMenuModel;
begin
  F := Finding('Concat A');
  try
    M := FindingModel(F, [Act('Free List in a try/finally block', fakFix)]);
    AppendContextActions(M, [Act('Free list in a try/finally block', fakFix),
      Act('Konstante', fakFix), Act('KONSTANTE', fakFix)],
      [moLeadingSeparator, moHeaders], CTX_HEADER);
    Assert.AreEqual<Integer>(2, M.ActionCount, 'Fund-Aktion + eine Konstante');
    Assert.AreEqual('Free List in a try/finally block', M.Actions[0].Caption,
      'die Schreibweise des Funds bleibt');
    Assert.IsTrue(M.Actions[0].Kind = fakFix, 'am Fund');
    Assert.AreEqual<Integer>(1, M.ContextActionCount);
    Assert.AreEqual('Konstante', M.Actions[1].Caption, 'die erste Schreibweise');
  finally
    F.Free;
  end;
end;

procedure TTestContextActionMenu.Append_AllDuplicates_NothingAppended;
var
  F      : TLeakFinding;
  M      : TFindingMenuModel;
  Before : Integer;
begin
  F := Finding('Concat A');
  try
    M := FindingModel(F, [Act('X', fakFix)]);
    Before := Length(M.Entries);
    AppendContextActions(M, [Act('X', fakFix)], [moLeadingSeparator, moHeaders],
      CTX_HEADER);
    Assert.AreEqual<Integer>(Before, Length(M.Entries),
      'kein verwaister Trenner, keine leere Kopfzeile');
    Assert.AreEqual<Integer>(0, M.ContextEntryCount);
    Assert.AreEqual<Integer>(0, M.ContextActionCount);
  finally
    F.Free;
  end;
end;

procedure TTestContextActionMenu.Append_EmptyModel_SeparatorOnlyWithOption;
var
  M : TFindingMenuModel;
begin
  M := Default(TFindingMenuModel);
  AppendContextActions(M, [Act('A', fakFix)], [], '');
  Assert.AreEqual<Integer>(1, Length(M.Entries), 'ohne Option kein Trenner');
  Assert.IsTrue(M.Entries[0].Kind = mkAction);
  M := Default(TFindingMenuModel);
  AppendContextActions(M, [Act('A', fakFix)], [moLeadingSeparator], '');
  Assert.AreEqual<Integer>(2, Length(M.Entries));
  Assert.IsTrue(M.Entries[0].Kind = mkSeparator,
    'mit moLeadingSeparator: abgesetzt von den Eintraegen der IDE');
end;

procedure TTestContextActionMenu.Append_AvailableFixesOnly_NothingInBulb;
var
  M : TFindingMenuModel;
begin
  M := Default(TFindingMenuModel);
  AppendContextActions(M, [Act('A', fakFix)],
    [moLeadingSeparator, moHeaders, moAvailableFixesOnly], CTX_HEADER);
  Assert.IsTrue(M.IsEmpty, 'Kontextaktionen stehen nie in der Gluehbirne');
  Assert.AreEqual<Integer>(0, Length(M.Entries));
end;

procedure TTestContextActionMenu.Append_StampsContext_KeysNeverRunIt;
var
  M : TFindingMenuModel;
begin
  M := Default(TFindingMenuModel);
  AppendContextActions(M, [Act('Hilfe?', fakFix), Act('Marker?', fakSuppress)],
    [], '');
  Assert.IsTrue(M.Actions[0].Kind = fakContext);
  Assert.IsTrue(M.Actions[1].Kind = fakContext);
  Assert.IsTrue(M.FirstRunnable(fakFix).Verdict = kvNone,
    'Ctrl+Alt+F fuehrt keine Kontextaktion aus');
  Assert.IsTrue(M.FirstRunnable(fakSuppress).Verdict = kvNone,
    'Ctrl+Alt+S auch nicht');
end;

procedure TTestContextActionMenu.Append_HeaderOnlyWithOptionAndText;
var
  M : TFindingMenuModel;
begin
  M := Default(TFindingMenuModel);
  AppendContextActions(M, [Act('A', fakFix)], [moHeaders], '');
  Assert.AreEqual<Integer>(1, Length(M.Entries), 'leerer Kopftext: keine Kopfzeile');
  M := Default(TFindingMenuModel);
  AppendContextActions(M, [Act('A', fakFix)], [], CTX_HEADER);
  Assert.AreEqual<Integer>(1, Length(M.Entries), 'ohne moHeaders: keine Kopfzeile');
  M := Default(TFindingMenuModel);
  AppendContextActions(M, [Act('A', fakFix)], [moHeaders], CTX_HEADER);
  Assert.AreEqual<Integer>(2, Length(M.Entries));
  Assert.IsTrue(M.Entries[0].Kind = mkHeader);
  Assert.IsFalse(M.Entries[0].Enabled);
end;

procedure TTestContextActionMenu.Append_ActionIndexPointsIntoTail;
var
  F : TLeakFinding;
  M : TFindingMenuModel;
  i : Integer;
begin
  F := Finding('Concat A');
  try
    M := FindingModel(F, [Act('F1', fakFix), Act('F2', fakNavigate)]);
    AppendContextActions(M, [Act('K1', fakFix), Act('K2', fakFix)],
      [moLeadingSeparator, moHeaders], CTX_HEADER);
    for i := Length(M.Entries) - M.ContextEntryCount to High(M.Entries) do
      if M.Entries[i].Kind = mkAction then
      begin
        Assert.IsTrue(M.Entries[i].ActionIndex >= M.ActionCount - M.ContextActionCount,
          'Kontext-Eintraege zeigen in den hinteren Teil von Actions');
        Assert.AreEqual(FindingActionCaption(M.Actions[M.Entries[i].ActionIndex]),
          M.Entries[i].Caption);
      end;
    Assert.AreEqual('K2', M.Actions[3].Caption);
  finally
    F.Free;
  end;
end;

procedure TTestContextActionMenu.Append_DisabledContextAction_StaysDisabled;
var
  M : TFindingMenuModel;
  A : TFindingAction;
begin
  A := Act('Konstante', fakFix, False);
  A.Hint := 'kein Literal am Caret';
  M := Default(TFindingMenuModel);
  AppendContextActions(M, [A], [], '');
  Assert.AreEqual<Integer>(1, Length(M.Entries));
  Assert.IsFalse(M.Entries[0].Enabled, 'gesperrt bleibt gesperrt');
  Assert.AreEqual('Konstante'#9'kein Literal am Caret', M.Entries[0].Caption);
end;

procedure TTestContextActionMenu.Editor_NoFindings_OnlyContextActions;
var
  P     : TStub;
  Token : Integer;
  M     : TFindingMenuModel;
begin
  P := TStub.Create;
  P.Captions := ['Konstante'];
  Token := TFindingActions.RegisterContext(P.ProvideContext);
  try
    M := BuildEditorMenuModel(TEditorContext.At('C:\t.pas', 3, 7),
      [moLeadingSeparator, moHeaders], CTX_HEADER);
    Assert.AreEqual<Integer>(1, M.ActionCount, 'ein Menue auch ohne Fund');
    Assert.AreEqual<Integer>(3, Length(M.Entries), 'Trenner, Kopf, Aktion');
    Assert.AreEqual<Integer>(3, M.ContextEntryCount);
    Assert.IsTrue(M.Actions[0].Kind = fakContext);
    M.Actions[0].Execute(nil);
    Assert.AreEqual<Integer>(1, P.Ran);
  finally
    TFindingActions.Unregister(Token);
    P.Free;
  end;
end;

procedure TTestContextActionMenu.Editor_SameCaption_OnceAtTheFinding;
var
  PF, PC : TStub;
  TokF   : Integer;
  TokC   : Integer;
  F      : TLeakFinding;
  C      : TEditorContext;
  M      : TFindingMenuModel;
begin
  F := Finding('Concat A');
  PF := TStub.Create;
  PC := TStub.Create;
  PF.Captions := ['Format() bilden'];
  PC.Captions := ['Format() bilden', 'Konstante'];
  TokF := TFindingActions.Register(PF.ProvideFinding);
  TokC := TFindingActions.RegisterContext(PC.ProvideContext);
  try
    C := TEditorContext.At('C:\t.pas', 10, 3);
    C.Findings := [F];
    M := BuildEditorMenuModel(C, [moLeadingSeparator, moHeaders], CTX_HEADER);
    Assert.AreEqual<Integer>(2, M.ActionCount);
    Assert.IsTrue(M.Actions[0].Kind = fakFix, 'Format() bilden am Fund');
    Assert.AreEqual('Konstante', M.Actions[1].Caption);
    Assert.AreEqual<Integer>(1, M.ContextActionCount);
    Assert.AreEqual<Integer>(1, PC.Asked, 'Kontext-Anbieter einmal je Menue');
  finally
    TFindingActions.Unregister(TokC);
    TFindingActions.Unregister(TokF);
    PC.Free;
    PF.Free;
    F.Free;
  end;
end;

procedure TTestContextActionMenu.Editor_ContextProviderThrows_FindingActionsStay;
var
  PF, PC : TStub;
  TokF   : Integer;
  TokC   : Integer;
  F      : TLeakFinding;
  C      : TEditorContext;
  M      : TFindingMenuModel;
begin
  F := Finding('Concat A');
  PF := TStub.Create;
  PC := TStub.Create;
  PF.Captions := ['Fix'];
  PC.Captions := ['Konstante'];
  PC.Raises := 1;
  TokF := TFindingActions.Register(PF.ProvideFinding);
  TokC := TFindingActions.RegisterContext(PC.ProvideContext);
  try
    C := TEditorContext.At('C:\t.pas', 10, 3);
    C.Findings := [F];
    M := BuildEditorMenuModel(C, [moLeadingSeparator, moHeaders], CTX_HEADER);
    Assert.AreEqual<Integer>(1, M.ActionCount, 'die Fund-Aktion bleibt');
    Assert.AreEqual<Integer>(0, M.ContextActionCount);
    Assert.AreEqual<Integer>(1, Length(M.Errors));
    Assert.AreEqual('Kontext kaputt', M.Errors[0]);
  finally
    TFindingActions.Unregister(TokC);
    TFindingActions.Unregister(TokF);
    PC.Free;
    PF.Free;
    F.Free;
  end;
end;

procedure TTestContextActionMenu.Editor_ContextProviderAbort_PassesThrough;
var
  P     : TStub;
  Token : Integer;
  Hit   : Boolean;
begin
  P := TStub.Create;
  P.Captions := ['Konstante'];
  P.Raises := 2;
  Token := TFindingActions.RegisterContext(P.ProvideContext);
  try
    Hit := False;
    try
      BuildEditorMenuModel(TEditorContext.At('C:\t.pas', 3, 7), [], '');
    except
      on EAbort do Hit := True;
    end;
    Assert.IsTrue(Hit, 'ein Abbruch erreicht den Host, nicht Errors');
  finally
    TFindingActions.Unregister(Token);
    P.Free;
  end;
end;

procedure TTestContextActionMenu.Editor_AvailableFixesOnly_ContextProviderNotAsked;
var
  P     : TStub;
  Token : Integer;
  M     : TFindingMenuModel;
begin
  P := TStub.Create;
  P.Captions := ['Konstante'];
  Token := TFindingActions.RegisterContext(P.ProvideContext);
  try
    M := BuildEditorMenuModel(TEditorContext.At('C:\t.pas', 3, 7),
      [moAvailableFixesOnly], '');
    Assert.IsTrue(M.IsEmpty);
    Assert.AreEqual<Integer>(0, P.Asked,
      'die Gluehbirnen-Form parst nicht fuer Kontextaktionen');
  finally
    TFindingActions.Unregister(Token);
    P.Free;
  end;
end;

procedure TTestContextActionMenu.Editor_NoProviders_EmptyModel;
var
  M : TFindingMenuModel;
begin
  M := BuildEditorMenuModel(TEditorContext.At('C:\t.pas', 3, 7),
    [moLeadingSeparator, moHeaders], CTX_HEADER);
  Assert.IsTrue(M.IsEmpty);
  Assert.AreEqual<Integer>(0, Length(M.Entries));
  Assert.AreEqual<Integer>(0, Length(M.Errors));
end;

initialization
  GExec := TStub.Create;
  TDUnitX.RegisterTestFixture(TTestContextActionMenu);

finalization
  FreeAndNil(GExec);

end.
