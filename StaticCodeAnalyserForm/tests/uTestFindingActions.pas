unit uTestFindingActions;

// Tests fuer uFindingActions, den Erweiterungspunkt "Aktionen am Fund"
// (Konzept_SourceRefactor_Quellstellen 2026-10-02, Abschnitt 15 H1).
//
// Die Anbieter sind kleine Objekte mit Methoden - wie ein echtes Package
// sie stellen wuerde. Jeder Test meldet seine Anbieter wieder ab: die
// Registry ist prozessweit, ein vergessener Anbieter wuerde in jedem
// Folgetest mitantworten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFindingActions = class
  public
    [Test] procedure NoProvider_NoActions;
    [Test] procedure NilFinding_NoActions;
    [Test] procedure Provider_ActionsAreReturned;
    [Test] procedure TwoProviders_RegistrationOrder;
    [Test] procedure Provider_EmptyForOtherFinding;
    [Test] procedure Unregister_RemovesExactlyThatProvider;
    [Test] procedure Unregister_UnknownToken_IsNoOp;
    [Test] procedure Execute_RunsTheProvidersCode;
    [Test] procedure DisabledAction_CarriesReasonInHint;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uMethodd12, uFindingActions;

type
  // Ein Anbieter, wie ihn ein Package stellen wuerde: liefert fuer jeden
  // Fund dieselben Aktionen (Captions), optional nur fuer eine Datei.
  TStubProvider = class
  public
    Captions  : TArray<string>;
    OnlyFile  : string;      // '' = fuer jeden Fund
    Enabled   : Boolean;
    Hint      : string;
    Ran       : Integer;
    constructor Create(const ACaptions: array of string);
    function Provide(const AFinding: TLeakFinding): TArray<TFindingAction>;
    procedure DoExecute(Sender: TObject);
  end;

constructor TStubProvider.Create(const ACaptions: array of string);
var
  i : Integer;
begin
  inherited Create;
  SetLength(Captions, Length(ACaptions));
  for i := 0 to High(ACaptions) do
    Captions[i] := ACaptions[i];
  Enabled := True;
end;

function TStubProvider.Provide(
  const AFinding: TLeakFinding): TArray<TFindingAction>;
var
  i : Integer;
begin
  Result := nil;
  if (OnlyFile <> '') and not SameText(AFinding.FileName, OnlyFile) then Exit;
  SetLength(Result, Length(Captions));
  for i := 0 to High(Captions) do
  begin
    Result[i].Caption := Captions[i];
    Result[i].Hint    := Hint;
    Result[i].Enabled := Enabled;
    if Enabled then
      Result[i].Execute := DoExecute
    else
      Result[i].Execute := nil;
  end;
end;

procedure TStubProvider.DoExecute(Sender: TObject);
begin
  Inc(Ran);
end;

function MakeFinding(const AFile: string; ALine: Integer): TLeakFinding;
begin
  Result := TLeakFinding.Create;
  Result.FileName   := AFile;
  Result.LineNumber := IntToStr(ALine);
end;

procedure TTestFindingActions.NoProvider_NoActions;
var
  F : TLeakFinding;
begin
  F := MakeFinding('a.pas', 1);
  try
    Assert.AreEqual<Integer>(0, TFindingActions.ProviderCount,
      'kein Test darf einen Anbieter zuruecklassen');
    Assert.AreEqual<Integer>(0, Length(TFindingActions.ActionsFor(F)));
  finally
    F.Free;
  end;
end;

procedure TTestFindingActions.NilFinding_NoActions;
var
  P     : TStubProvider;
  Token : Integer;
begin
  P := TStubProvider.Create(['x']);
  Token := TFindingActions.Register(P.Provide);
  try
    Assert.AreEqual<Integer>(0, Length(TFindingActions.ActionsFor(nil)));
  finally
    TFindingActions.Unregister(Token);
    P.Free;
  end;
end;

procedure TTestFindingActions.Provider_ActionsAreReturned;
var
  P       : TStubProvider;
  Token   : Integer;
  F       : TLeakFinding;
  Actions : TArray<TFindingAction>;
begin
  F := MakeFinding('a.pas', 7);
  P := TStubProvider.Create(['Format() bilden']);
  P.Hint := '4 Terme, alle Strings';
  Token := TFindingActions.Register(P.Provide);
  try
    Actions := TFindingActions.ActionsFor(F);
    Assert.AreEqual<Integer>(1, Length(Actions));
    Assert.AreEqual('Format() bilden', Actions[0].Caption);
    Assert.AreEqual('4 Terme, alle Strings', Actions[0].Hint);
    Assert.IsTrue(Actions[0].Enabled);
  finally
    TFindingActions.Unregister(Token);
    P.Free;
    F.Free;
  end;
end;

procedure TTestFindingActions.TwoProviders_RegistrationOrder;
var
  P1, P2  : TStubProvider;
  T1, T2  : Integer;
  F       : TLeakFinding;
  Actions : TArray<TFindingAction>;
begin
  F  := MakeFinding('a.pas', 1);
  P1 := TStubProvider.Create(['erster']);
  P2 := TStubProvider.Create(['zweiter-a', 'zweiter-b']);
  T1 := TFindingActions.Register(P1.Provide);
  T2 := TFindingActions.Register(P2.Provide);
  try
    Assert.AreEqual<Integer>(2, TFindingActions.ProviderCount);
    Actions := TFindingActions.ActionsFor(F);
    Assert.AreEqual<Integer>(3, Length(Actions));
    Assert.AreEqual('erster',    Actions[0].Caption);
    Assert.AreEqual('zweiter-a', Actions[1].Caption);
    Assert.AreEqual('zweiter-b', Actions[2].Caption);
  finally
    TFindingActions.Unregister(T2);
    TFindingActions.Unregister(T1);
    P2.Free;
    P1.Free;
    F.Free;
  end;
end;

procedure TTestFindingActions.Provider_EmptyForOtherFinding;
var
  P     : TStubProvider;
  Token : Integer;
  F     : TLeakFinding;
begin
  F := MakeFinding('other.pas', 3);
  P := TStubProvider.Create(['nur fuer a.pas']);
  P.OnlyFile := 'a.pas';
  Token := TFindingActions.Register(P.Provide);
  try
    Assert.AreEqual<Integer>(0, Length(TFindingActions.ActionsFor(F)),
      'ein Anbieter, der nichts anzubieten hat, liefert leer');
  finally
    TFindingActions.Unregister(Token);
    P.Free;
    F.Free;
  end;
end;

procedure TTestFindingActions.Unregister_RemovesExactlyThatProvider;
var
  P1, P2  : TStubProvider;
  T1, T2  : Integer;
  F       : TLeakFinding;
  Actions : TArray<TFindingAction>;
begin
  F  := MakeFinding('a.pas', 1);
  P1 := TStubProvider.Create(['bleibt']);
  P2 := TStubProvider.Create(['geht']);
  T1 := TFindingActions.Register(P1.Provide);
  T2 := TFindingActions.Register(P2.Provide);
  try
    TFindingActions.Unregister(T2);
    Assert.AreEqual<Integer>(1, TFindingActions.ProviderCount);
    Actions := TFindingActions.ActionsFor(F);
    Assert.AreEqual<Integer>(1, Length(Actions));
    Assert.AreEqual('bleibt', Actions[0].Caption);
  finally
    TFindingActions.Unregister(T1);
    P2.Free;
    P1.Free;
    F.Free;
  end;
end;

procedure TTestFindingActions.Unregister_UnknownToken_IsNoOp;
begin
  TFindingActions.Unregister(-1);
  TFindingActions.Unregister(0);
  TFindingActions.Unregister(999999);
  Assert.AreEqual<Integer>(0, TFindingActions.ProviderCount);
end;

procedure TTestFindingActions.Execute_RunsTheProvidersCode;
var
  P       : TStubProvider;
  Token   : Integer;
  F       : TLeakFinding;
  Actions : TArray<TFindingAction>;
begin
  F := MakeFinding('a.pas', 1);
  P := TStubProvider.Create(['tu was']);
  Token := TFindingActions.Register(P.Provide);
  try
    Actions := TFindingActions.ActionsFor(F);
    Assert.AreEqual<Integer>(1, Length(Actions));
    Assert.IsTrue(Assigned(Actions[0].Execute));
    Actions[0].Execute(nil);
    Assert.AreEqual<Integer>(1, P.Ran, 'der Host ruft den Code des Anbieters');
  finally
    TFindingActions.Unregister(Token);
    P.Free;
    F.Free;
  end;
end;

procedure TTestFindingActions.DisabledAction_CarriesReasonInHint;
var
  P       : TStubProvider;
  Token   : Integer;
  F       : TLeakFinding;
  Actions : TArray<TFindingAction>;
begin
  F := MakeFinding('a.pas', 1);
  P := TStubProvider.Create(['Format() bilden']);
  P.Enabled := False;
  P.Hint    := 'Operand ''Name'': Typ unbekannt';
  Token := TFindingActions.Register(P.Provide);
  try
    Actions := TFindingActions.ActionsFor(F);
    Assert.AreEqual<Integer>(1, Length(Actions));
    Assert.IsFalse(Actions[0].Enabled, 'anzeigen, aber ausgegraut');
    Assert.AreEqual('Operand ''Name'': Typ unbekannt', Actions[0].Hint);
    Assert.IsFalse(Assigned(Actions[0].Execute));
  finally
    TFindingActions.Unregister(Token);
    P.Free;
    F.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFindingActions);

end.
