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
    // Review reDelphiX 2026-10-07, Minor 7: nil wird nicht angemeldet.
    [Test] procedure Register_Nil_ReturnsZeroAndCountsNothing;
    // Review Minor 8: ein Anbieter darf WAEHREND ActionsFor die Registry
    // aendern (Kopie unter dem Lock, Aufruf ohne Lock).
    [Test] procedure Provider_UnregistersItselfDuringActionsFor;
    [Test] procedure Provider_RegistersAnotherDuringActionsFor;
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

const
  // Caption der einen Aktion von TReentrantProvider (Testdaten, kein UI).
  REENTRANT_CAPTION = 'reentrant';

type
  // Ein Anbieter, der in Provide die Registry veraendert: sich selbst
  // abmelden (ShouldUnregisterSelf) und/oder beim ersten Aufruf einen
  // zweiten Anbieter anmelden (Second). Liefert immer eine Aktion
  // REENTRANT_CAPTION.
  TReentrantProvider = class
  private
    FSelfToken            : Integer;
    FShouldUnregisterSelf : Boolean;
    FSecond               : TStubProvider;   // nil = keinen anmelden
    FSecondToken          : Integer;
  public
    function Provide(const AFinding: TLeakFinding): TArray<TFindingAction>;
    property SelfToken: Integer read FSelfToken write FSelfToken;
    property ShouldUnregisterSelf: Boolean read FShouldUnregisterSelf
      write FShouldUnregisterSelf;
    property Second: TStubProvider read FSecond write FSecond;
    // Token des in Provide angemeldeten zweiten Anbieters (0 = keiner).
    property SecondToken: Integer read FSecondToken;
  end;

function TReentrantProvider.Provide(
  const AFinding: TLeakFinding): TArray<TFindingAction>;
begin
  Result := nil;
  if FShouldUnregisterSelf then
    TFindingActions.Unregister(FSelfToken);
  if Assigned(FSecond) and (FSecondToken = 0) then
    FSecondToken := TFindingActions.Register(FSecond.Provide);
  SetLength(Result, 1);
  Result[0].Caption := REENTRANT_CAPTION;
  Result[0].Enabled := False;
  Result[0].Execute := nil;
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

procedure TTestFindingActions.Register_Nil_ReturnsZeroAndCountsNothing;
var
  Before : Integer;
  Token  : Integer;
begin
  Before := TFindingActions.ProviderCount;
  Token := TFindingActions.Register(nil);
  try
    Assert.AreEqual<Integer>(0, Token, 'Token 0 = nicht angemeldet');
    Assert.AreEqual<Integer>(Before, TFindingActions.ProviderCount,
      'ein nil-Anbieter zaehlt nicht - der Host bliebe sonst wach');
  finally
    // Unregister(0) ist ein No-Op; ein faelschlich vergebenes Token
    // verschwindet so trotzdem wieder (die Registry ist prozessweit).
    TFindingActions.Unregister(Token);
  end;
  Assert.AreEqual<Integer>(Before, TFindingActions.ProviderCount);
end;

procedure TTestFindingActions.Provider_UnregistersItselfDuringActionsFor;
var
  R       : TReentrantProvider;
  F       : TLeakFinding;
  Actions : TArray<TFindingAction>;
begin
  F := MakeFinding('a.pas', 1);
  R := TReentrantProvider.Create;
  try
    R.ShouldUnregisterSelf := True;
    R.SelfToken := TFindingActions.Register(R.Provide);
    Assert.AreEqual<Integer>(1, TFindingActions.ProviderCount);
    Actions := TFindingActions.ActionsFor(F);
    Assert.AreEqual<Integer>(1, Length(Actions),
      'die Aktionen dieser Runde kommen noch an');
    Assert.AreEqual(REENTRANT_CAPTION, Actions[0].Caption);
    Assert.AreEqual<Integer>(0, TFindingActions.ProviderCount,
      'die Abmeldung im Provide hat gewirkt');
    Assert.AreEqual<Integer>(0, Length(TFindingActions.ActionsFor(F)),
      'die naechste Runde fragt ihn nicht mehr');
  finally
    TFindingActions.Unregister(R.SelfToken);   // No-Op, schon abgemeldet
    R.Free;
    F.Free;
  end;
end;

procedure TTestFindingActions.Provider_RegistersAnotherDuringActionsFor;
var
  R       : TReentrantProvider;
  S       : TStubProvider;
  F       : TLeakFinding;
  Actions : TArray<TFindingAction>;
begin
  F := MakeFinding('a.pas', 1);
  S := TStubProvider.Create(['zweiter']);
  R := TReentrantProvider.Create;
  try
    R.Second := S;
    R.SelfToken := TFindingActions.Register(R.Provide);
    Actions := TFindingActions.ActionsFor(F);
    Assert.AreEqual<Integer>(1, Length(Actions),
      'der neue Anbieter antwortet erst in der naechsten Runde');
    Assert.AreEqual(REENTRANT_CAPTION, Actions[0].Caption);
    Assert.IsTrue(R.SecondToken > 0, 'Register im Provide hat ein Token');
    Assert.AreEqual<Integer>(2, TFindingActions.ProviderCount);
    Actions := TFindingActions.ActionsFor(F);
    Assert.AreEqual<Integer>(2, Length(Actions));
    Assert.AreEqual(REENTRANT_CAPTION, Actions[0].Caption);
    Assert.AreEqual('zweiter',   Actions[1].Caption,
      'Anmeldereihenfolge: der zweite steht hinten');
  finally
    TFindingActions.Unregister(R.SecondToken);
    TFindingActions.Unregister(R.SelfToken);
    R.Free;
    S.Free;
    F.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFindingActions);

end.
