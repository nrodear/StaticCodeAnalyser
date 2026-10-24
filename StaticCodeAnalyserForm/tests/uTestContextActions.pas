unit uTestContextActions;

// Tests fuer den Vertrag "Code-Aktionen ohne Fund" in uFindingActions
// (Charge B, V1; Entscheide Nico 2026-10-23, E14/E16): TEditorContext,
// RegisterContext, ContextActionsFor, ContextProviderCount und das
// gemeinsame Unregister. Nur Felder des Fund-Stubs (FileName), damit die
// Unit auch im FPC-Pruefstand laeuft (reDelphix/tools/fpc-pruefstand,
// build.sh uTestContextActions). Jeder Test meldet seine Anbieter wieder
// ab - die Registry ist prozessweit.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestContextActions = class
  public
    [Test] procedure NoContextProvider_NoActions;
    [Test] procedure InvalidContext_ProviderNotAsked;
    [Test] procedure Provider_ActionsReturned_KindIsContext;
    [Test] procedure Provider_SeesCaretSelectionAndFindings;
    [Test] procedure TwoProviders_RegistrationOrder;
    [Test] procedure Provider_EmptyElsewhere;
    [Test] procedure Unregister_RemovesContextProvider;
    // ProviderCount zaehlt nur Fund-Anbieter: an ihm haengen Gluehbirne
    // und Tasten, ein Kontext-Anbieter darf sie nicht wecken.
    [Test] procedure ContextProvider_NotAFindingProvider;
    [Test] procedure FindingProvider_NotAskedForContext;
    [Test] procedure RegisterContext_Nil_ReturnsZero;
    [Test] procedure Tokens_UniqueAcrossBothKinds;
    [Test] procedure At_NoSelectionNoFindings;
    [Test] procedure IsValid_NeedsFileLineAndCol;
    [Test] procedure SetSelection_AcceptsOnlyWellFormedNonEmpty;
    [Test] procedure SelectionIsSingleLine;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uMethodd12, uFindingActions;

type
  // Ein Kontext-Anbieter wie ein Package ihn stellen wuerde: liefert seine
  // Captions an jeder Stelle (optional nur in OnlyFile) und merkt sich den
  // zuletzt gesehenen Kontext. Setzt Kind ABSICHTLICH auf fakFix - die
  // Registry muss es auf fakContext stellen.
  TCtxStub = class
  public
    Captions : TArray<string>;
    OnlyFile : string;      // '' = ueberall
    Asked    : Integer;
    Seen     : TEditorContext;
    Ran      : Integer;
    constructor Create(const ACaptions: array of string);
    function Provide(const AContext: TEditorContext): TArray<TFindingAction>;
    procedure DoExecute(Sender: TObject);
  end;

  // Ein Fund-Anbieter, der zaehlt, wie oft er gefragt wurde.
  TFindingStub = class
  public
    Asked : Integer;
    function Provide(const AFinding: TLeakFinding): TArray<TFindingAction>;
  end;

constructor TCtxStub.Create(const ACaptions: array of string);
var
  i : Integer;
begin
  inherited Create;
  SetLength(Captions, Length(ACaptions));
  for i := 0 to High(ACaptions) do
    Captions[i] := ACaptions[i];
end;

function TCtxStub.Provide(
  const AContext: TEditorContext): TArray<TFindingAction>;
var
  i : Integer;
begin
  Result := nil;
  Inc(Asked);
  Seen := AContext;
  if (OnlyFile <> '') and not SameText(AContext.FileName, OnlyFile) then Exit;
  SetLength(Result, Length(Captions));
  for i := 0 to High(Captions) do
  begin
    Result[i].Caption := Captions[i];
    Result[i].Hint    := '';
    Result[i].Enabled := True;
    Result[i].Execute := DoExecute;
    Result[i].Kind    := fakFix;   // die Registry stellt auf fakContext
  end;
end;

procedure TCtxStub.DoExecute(Sender: TObject);
begin
  Inc(Ran);
end;

function TFindingStub.Provide(
  const AFinding: TLeakFinding): TArray<TFindingAction>;
begin
  Result := nil;
  Inc(Asked);
  SetLength(Result, 1);
  Result[0].Caption := 'am Fund';
  Result[0].Enabled := False;
  Result[0].Execute := nil;
end;

function Ctx(const AFile: string; ALine, ACol: Integer): TEditorContext;
begin
  Result := TEditorContext.At(AFile, ALine, ACol);
end;

procedure TTestContextActions.NoContextProvider_NoActions;
begin
  Assert.AreEqual<Integer>(0, TFindingActions.ContextProviderCount,
    'kein Test darf einen Kontext-Anbieter zuruecklassen');
  Assert.AreEqual<Integer>(0,
    Length(TFindingActions.ContextActionsFor(Ctx('a.pas', 3, 5))));
end;

procedure TTestContextActions.InvalidContext_ProviderNotAsked;
var
  P     : TCtxStub;
  Token : Integer;
begin
  P := TCtxStub.Create(['x']);
  Token := TFindingActions.RegisterContext(P.Provide);
  try
    Assert.AreEqual<Integer>(0,
      Length(TFindingActions.ContextActionsFor(Ctx('', 3, 5))), 'ohne Datei');
    Assert.AreEqual<Integer>(0,
      Length(TFindingActions.ContextActionsFor(Ctx('a.pas', 0, 5))), 'Zeile 0');
    Assert.AreEqual<Integer>(0,
      Length(TFindingActions.ContextActionsFor(Ctx('a.pas', 3, 0))), 'Spalte 0');
    Assert.AreEqual<Integer>(0, P.Asked, 'ein ungueltiger Kontext fragt niemanden');
  finally
    TFindingActions.Unregister(Token);
    P.Free;
  end;
end;

procedure TTestContextActions.Provider_ActionsReturned_KindIsContext;
var
  P       : TCtxStub;
  Token   : Integer;
  Actions : TArray<TFindingAction>;
begin
  P := TCtxStub.Create(['Lokale Konstante einfuehren']);
  Token := TFindingActions.RegisterContext(P.Provide);
  try
    Actions := TFindingActions.ContextActionsFor(Ctx('a.pas', 3, 5));
    Assert.AreEqual<Integer>(1, Length(Actions));
    Assert.AreEqual('Lokale Konstante einfuehren', Actions[0].Caption);
    Assert.IsTrue(Actions[0].Kind = fakContext,
      'die Registry setzt fakContext, auch wenn der Anbieter fakFix meldet');
    Assert.IsTrue(Assigned(Actions[0].Execute));
    Actions[0].Execute(nil);
    Assert.AreEqual<Integer>(1, P.Ran, 'der Host ruft den Code des Anbieters');
  finally
    TFindingActions.Unregister(Token);
    P.Free;
  end;
end;

procedure TTestContextActions.Provider_SeesCaretSelectionAndFindings;
var
  P     : TCtxStub;
  Token : Integer;
  C     : TEditorContext;
  F     : TLeakFinding;
begin
  F := TLeakFinding.Create;
  P := TCtxStub.Create(['x']);
  Token := TFindingActions.RegisterContext(P.Provide);
  try
    F.FileName := 'a.pas';
    C := Ctx('a.pas', 7, 12);
    Assert.IsTrue(C.SetSelection(7, 10, 7, 14));
    C.Findings := [F];
    TFindingActions.ContextActionsFor(C);
    Assert.AreEqual<Integer>(1, P.Asked, 'EIN Aufruf je Abfrage, nicht je Fund');
    Assert.AreEqual('a.pas', P.Seen.FileName);
    Assert.AreEqual<Integer>(7, P.Seen.Line);
    Assert.AreEqual<Integer>(12, P.Seen.Col);
    Assert.IsTrue(P.Seen.HasSelection);
    Assert.AreEqual<Integer>(10, P.Seen.SelStartCol);
    Assert.AreEqual<Integer>(14, P.Seen.SelEndCol);
    Assert.AreEqual<Integer>(1, Length(P.Seen.Findings));
    Assert.IsTrue(P.Seen.Findings[0] = F, 'der Fund der Zeile kommt an');
  finally
    TFindingActions.Unregister(Token);
    P.Free;
    F.Free;
  end;
end;

procedure TTestContextActions.TwoProviders_RegistrationOrder;
var
  P1, P2  : TCtxStub;
  T1, T2  : Integer;
  Actions : TArray<TFindingAction>;
begin
  P1 := TCtxStub.Create(['erster']);
  P2 := TCtxStub.Create(['zweiter-a', 'zweiter-b']);
  T1 := TFindingActions.RegisterContext(P1.Provide);
  T2 := TFindingActions.RegisterContext(P2.Provide);
  try
    Assert.AreEqual<Integer>(2, TFindingActions.ContextProviderCount);
    Actions := TFindingActions.ContextActionsFor(Ctx('a.pas', 1, 1));
    Assert.AreEqual<Integer>(3, Length(Actions));
    Assert.AreEqual('erster',    Actions[0].Caption);
    Assert.AreEqual('zweiter-a', Actions[1].Caption);
    Assert.AreEqual('zweiter-b', Actions[2].Caption);
    Assert.IsTrue(Actions[2].Kind = fakContext);
  finally
    TFindingActions.Unregister(T2);
    TFindingActions.Unregister(T1);
    P2.Free;
    P1.Free;
  end;
end;

procedure TTestContextActions.Provider_EmptyElsewhere;
var
  P     : TCtxStub;
  Token : Integer;
begin
  P := TCtxStub.Create(['nur in a.pas']);
  P.OnlyFile := 'a.pas';
  Token := TFindingActions.RegisterContext(P.Provide);
  try
    Assert.AreEqual<Integer>(0,
      Length(TFindingActions.ContextActionsFor(Ctx('b.pas', 1, 1))));
    Assert.AreEqual<Integer>(1, P.Asked, 'gefragt wurde er trotzdem');
  finally
    TFindingActions.Unregister(Token);
    P.Free;
  end;
end;

procedure TTestContextActions.Unregister_RemovesContextProvider;
var
  P1, P2  : TCtxStub;
  T1, T2  : Integer;
  Actions : TArray<TFindingAction>;
begin
  P1 := TCtxStub.Create(['bleibt']);
  P2 := TCtxStub.Create(['geht']);
  T1 := TFindingActions.RegisterContext(P1.Provide);
  T2 := TFindingActions.RegisterContext(P2.Provide);
  try
    TFindingActions.Unregister(T2);
    Assert.AreEqual<Integer>(1, TFindingActions.ContextProviderCount);
    Actions := TFindingActions.ContextActionsFor(Ctx('a.pas', 1, 1));
    Assert.AreEqual<Integer>(1, Length(Actions));
    Assert.AreEqual('bleibt', Actions[0].Caption);
  finally
    TFindingActions.Unregister(T1);
    P2.Free;
    P1.Free;
  end;
  Assert.AreEqual<Integer>(0, TFindingActions.ContextProviderCount);
end;

procedure TTestContextActions.ContextProvider_NotAFindingProvider;
var
  P      : TCtxStub;
  Token  : Integer;
  F      : TLeakFinding;
  Before : Integer;
begin
  Before := TFindingActions.ProviderCount;
  F := TLeakFinding.Create;
  P := TCtxStub.Create(['x']);
  Token := TFindingActions.RegisterContext(P.Provide);
  try
    F.FileName := 'a.pas';
    Assert.AreEqual<Integer>(Before, TFindingActions.ProviderCount,
      'ProviderCount zaehlt nur Fund-Anbieter');
    Assert.AreEqual<Integer>(0, Length(TFindingActions.ActionsFor(F)));
    Assert.AreEqual<Integer>(0, P.Asked, 'ActionsFor fragt keinen Kontext-Anbieter');
  finally
    TFindingActions.Unregister(Token);
    P.Free;
    F.Free;
  end;
end;

procedure TTestContextActions.FindingProvider_NotAskedForContext;
var
  S     : TFindingStub;
  Token : Integer;
begin
  S := TFindingStub.Create;
  Token := TFindingActions.Register(S.Provide);
  try
    Assert.AreEqual<Integer>(0, TFindingActions.ContextProviderCount);
    Assert.AreEqual<Integer>(0,
      Length(TFindingActions.ContextActionsFor(Ctx('a.pas', 1, 1))));
    Assert.AreEqual<Integer>(0, S.Asked,
      'ContextActionsFor fragt keinen Fund-Anbieter');
  finally
    TFindingActions.Unregister(Token);
    S.Free;
  end;
end;

procedure TTestContextActions.RegisterContext_Nil_ReturnsZero;
var
  Token : Integer;
begin
  Token := TFindingActions.RegisterContext(nil);
  try
    Assert.AreEqual<Integer>(0, Token, 'Token 0 = nicht angemeldet');
    Assert.AreEqual<Integer>(0, TFindingActions.ContextProviderCount);
  finally
    TFindingActions.Unregister(Token);
  end;
end;

procedure TTestContextActions.Tokens_UniqueAcrossBothKinds;
var
  S       : TFindingStub;
  P       : TCtxStub;
  TokFind : Integer;
  TokCtx  : Integer;
begin
  S := TFindingStub.Create;
  P := TCtxStub.Create(['x']);
  TokFind := TFindingActions.Register(S.Provide);
  TokCtx  := TFindingActions.RegisterContext(P.Provide);
  try
    Assert.IsTrue(TokFind > 0);
    Assert.IsTrue(TokCtx > 0);
    Assert.IsTrue(TokFind <> TokCtx, 'ein Zaehler fuer beide Arten');
    // Das Token des Kontext-Anbieters meldet keinen Fund-Anbieter ab.
    TFindingActions.Unregister(TokCtx);
    Assert.AreEqual<Integer>(0, TFindingActions.ContextProviderCount);
    Assert.AreEqual<Integer>(1, TFindingActions.ProviderCount);
  finally
    TFindingActions.Unregister(TokCtx);
    TFindingActions.Unregister(TokFind);
    P.Free;
    S.Free;
  end;
end;

procedure TTestContextActions.At_NoSelectionNoFindings;
var
  C : TEditorContext;
begin
  C := TEditorContext.At('a.pas', 4, 9);
  Assert.AreEqual('a.pas', C.FileName);
  Assert.AreEqual<Integer>(4, C.Line);
  Assert.AreEqual<Integer>(9, C.Col);
  Assert.IsFalse(C.HasSelection);
  Assert.AreEqual<Integer>(0, C.SelStartLine);
  Assert.AreEqual<Integer>(0, Length(C.Findings));
end;

procedure TTestContextActions.IsValid_NeedsFileLineAndCol;
var
  Empty : TEditorContext;
begin
  Assert.IsTrue(TEditorContext.At('a.pas', 1, 1).IsValid);
  Assert.IsFalse(TEditorContext.At('', 1, 1).IsValid);
  Assert.IsFalse(TEditorContext.At('a.pas', 0, 1).IsValid);
  Assert.IsFalse(TEditorContext.At('a.pas', 1, 0).IsValid);
  // Erst in eine Variable: eine Methode direkt auf Default(..) ist kein
  // gesicherter Delphi-Ausdruck (Review Charge B, Befund 6).
  Empty := Default(TEditorContext);
  Assert.IsFalse(Empty.IsValid);
end;

procedure TTestContextActions.SetSelection_AcceptsOnlyWellFormedNonEmpty;
var
  C : TEditorContext;
begin
  C := TEditorContext.At('a.pas', 2, 3);
  Assert.IsTrue(C.SetSelection(2, 3, 4, 1), 'mehrzeilig, Ende vor Startspalte');
  Assert.AreEqual<Integer>(4, C.SelEndLine);
  Assert.IsFalse(C.SetSelection(2, 3, 2, 3), 'leer');
  Assert.IsFalse(C.HasSelection);
  Assert.AreEqual<Integer>(0, C.SelEndLine, 'eine verworfene Auswahl ist ganz weg');
  Assert.IsFalse(C.SetSelection(3, 1, 2, 9), 'Ende vor Start');
  Assert.IsFalse(C.SetSelection(0, 1, 2, 9), 'Startzeile 0');
  Assert.IsFalse(C.SetSelection(1, 0, 2, 9), 'Startspalte 0');
  Assert.IsTrue(C.SetSelection(2, 3, 2, 4), 'ein Zeichen');
end;

procedure TTestContextActions.SelectionIsSingleLine;
var
  C : TEditorContext;
begin
  C := TEditorContext.At('a.pas', 2, 3);
  Assert.IsFalse(C.SelectionIsSingleLine, 'ohne Auswahl');
  C.SetSelection(2, 3, 2, 8);
  Assert.IsTrue(C.SelectionIsSingleLine);
  C.SetSelection(2, 3, 3, 1);
  Assert.IsFalse(C.SelectionIsSingleLine);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestContextActions);

end.
