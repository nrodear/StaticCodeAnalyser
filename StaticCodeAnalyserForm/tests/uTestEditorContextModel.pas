unit uTestEditorContextModel;

// Tests fuer uEditorContextModel (Charge B, V2/V3): die Umrechnung eines
// Editor-Blocks in die Auswahl des TEditorContext (Zeichen-Spalten, Ende
// exklusiv, Spaltenblock abgelehnt), die Zeichen-Spalte aus CharIndex, ob
// das Editor-Kontextmenue Anbieter fragt (Not-Aus EditorContextActions) und
// sein Modell mit und ohne Code-Aktionen ohne Fund samt der Stelle der
// Omitted-Hinweiszeile. Stub-Anbieter meldet jeder Test wieder ab.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEditorContextModel = class
  public
    [Test] procedure Block_NonInclusive_EndAsReported;
    [Test] procedure Block_Inclusive_EndPlusOne;
    [Test] procedure Block_Line_WholeLines;
    [Test] procedure Block_Column_Rejected;
    [Test] procedure Block_Unknown_Rejected;
    [Test] procedure Block_Reversed_Swapped;
    [Test] procedure Block_EmptyNonInclusive_NoSelection;
    [Test] procedure Block_KeepsCaretAndFile;
    [Test] procedure CharCol_IsCharIndexPlusOne_NotBytes;
    [Test] procedure CharCol_Negative_One;
    [Test] procedure Wanted_NoProviders_False;
    [Test] procedure Wanted_ContextProviderOnly_FollowsSwitch;
    [Test] procedure Wanted_FindingProvider_IgnoresSwitch;
    [Test] procedure Popup_SwitchOff_NoContextAsked;
    [Test] procedure Popup_SwitchOn_NoFinding_HeaderAndAction;
    [Test] procedure Popup_SwitchOn_SameCaption_OnceAtTheFinding;
    [Test] procedure Popup_NotWanted_EmptyModel;
    [Test] procedure Omitted_NoContext_AtTheEnd;
    [Test] procedure Omitted_WithContext_BeforeContextPart;
  end;

implementation

uses
  System.SysUtils,
  uMethodd12, uSCAConsts, uFindingActions, uFindingActionMenu,
  uEditorContextModel;

const
  CTX_HEADER = 'Code actions';   // Testdaten; die echte Caption setzt der Host
  // noinspection HardcodedPath
  CTX_FILE   = 'C:\t.pas';   // Testdaten, nie geoeffnet

type
  // Stub fuer beide Anbieterarten; traegt auch den Execute-Zeiger.
  TStub = class
  public
    Captions : TArray<string>;
    Asked    : Integer;
    Ran      : Integer;
    function ProvideFinding(const AFinding: TLeakFinding): TArray<TFindingAction>;
    function ProvideContext(const AContext: TEditorContext): TArray<TFindingAction>;
    procedure DoExecute(Sender: TObject);
  end;

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
  Result := ActionsOf(Self);
end;

procedure TStub.DoExecute(Sender: TObject);
begin
  Inc(Ran);
end;

function Blk(AStyle: TEditorBlockStyle;
  ASL, ASC, AEL, AEC: Integer): TEditorBlockChars;
begin
  Result.Style     := AStyle;
  Result.StartLine := ASL;
  Result.StartCol  := ASC;
  Result.EndLine   := AEL;
  Result.EndCol    := AEC;
end;

// 'Zeile:Spalte..Zeile:Spalte' der Auswahl, '-' ohne Auswahl.
function SelOf(const ACtx: TEditorContext): string;
begin
  if not ACtx.HasSelection then
    Exit('-');
  Result := Format('%d:%d..%d:%d', [ACtx.SelStartLine, ACtx.SelStartCol,
    ACtx.SelEndLine, ACtx.SelEndCol]);
end;

function Finding(const AMsg: string): TLeakFinding;
begin
  Result := TLeakFinding.New(CTX_FILE, 'Run', 10, AMsg, fkConcatToFormat);
end;

{ Block -> Auswahl }

procedure TTestEditorContextModel.Block_NonInclusive_EndAsReported;
var
  C : TEditorContext;
begin
  C := TEditorContext.At(CTX_FILE, 3, 5);
  Assert.IsTrue(ApplyEditorBlock(C, Blk(ebsNonInclusive, 3, 5, 3, 9)));
  Assert.AreEqual('3:5..3:9', SelOf(C), 'Ende zeigt schon hinter das letzte Zeichen');
end;

procedure TTestEditorContextModel.Block_Inclusive_EndPlusOne;
var
  C : TEditorContext;
begin
  C := TEditorContext.At(CTX_FILE, 3, 5);
  Assert.IsTrue(ApplyEditorBlock(C, Blk(ebsInclusive, 3, 5, 4, 9)));
  Assert.AreEqual('3:5..4:10', SelOf(C), 'das gemeldete Endzeichen gehoert dazu');
end;

procedure TTestEditorContextModel.Block_Line_WholeLines;
var
  C : TEditorContext;
begin
  C := TEditorContext.At(CTX_FILE, 5, 1);
  Assert.IsTrue(ApplyEditorBlock(C, Blk(ebsLine, 4, 7, 6, 2)));
  Assert.AreEqual('4:1..7:1', SelOf(C), 'Zeilen 4 bis 6 ganz');
end;

procedure TTestEditorContextModel.Block_Column_Rejected;
var
  C : TEditorContext;
begin
  C := TEditorContext.At(CTX_FILE, 3, 5);
  C.SetSelection(1, 1, 2, 1);   // eine alte Auswahl wird verworfen
  Assert.IsFalse(ApplyEditorBlock(C, Blk(ebsColumn, 3, 5, 6, 9)));
  Assert.AreEqual('-', SelOf(C));
  Assert.AreEqual<Integer>(0, C.SelEndLine, 'Felder zurueckgesetzt');
end;

procedure TTestEditorContextModel.Block_Unknown_Rejected;
var
  C : TEditorContext;
begin
  C := TEditorContext.At(CTX_FILE, 3, 5);
  Assert.IsFalse(ApplyEditorBlock(C, Blk(ebsUnknown, 3, 5, 3, 9)));
  Assert.AreEqual('-', SelOf(C));
end;

procedure TTestEditorContextModel.Block_Reversed_Swapped;
var
  C : TEditorContext;
begin
  C := TEditorContext.At(CTX_FILE, 2, 8);
  Assert.IsTrue(ApplyEditorBlock(C, Blk(ebsNonInclusive, 5, 3, 2, 8)));
  Assert.AreEqual('2:8..5:3', SelOf(C));
end;

procedure TTestEditorContextModel.Block_EmptyNonInclusive_NoSelection;
var
  C : TEditorContext;
begin
  C := TEditorContext.At(CTX_FILE, 3, 5);
  Assert.IsFalse(ApplyEditorBlock(C, Blk(ebsNonInclusive, 3, 5, 3, 5)));
  Assert.AreEqual('-', SelOf(C));
end;

procedure TTestEditorContextModel.Block_KeepsCaretAndFile;
var
  C : TEditorContext;
begin
  C := TEditorContext.At(CTX_FILE, 7, 12);
  ApplyEditorBlock(C, Blk(ebsInclusive, 3, 5, 7, 11));
  Assert.AreEqual(CTX_FILE, C.FileName);
  Assert.AreEqual<Integer>(7, C.Line);
  Assert.AreEqual<Integer>(12, C.Col, 'die Auswahl verschiebt den Caret nicht');
  Assert.AreEqual('3:5..7:12', SelOf(C));
end;

{ CharIndex -> Zeichen-Spalte }

procedure TTestEditorContextModel.CharCol_IsCharIndexPlusOne_NotBytes;
const
  // S := 'Gruesse EUR'; X - mit Umlaut, Eszett und Euro-Zeichen: vor dem X
  // stehen 4 UTF-8-Bytes mehr als Zeichen (1 + 1 + 2).
  LINE_TEXT = 'S := ''Gr'#$00FC#$00DF'e '#$20AC'''; X';
var
  Col     : Integer;
  ByteCol : Integer;
begin
  // ConvertPos liefert CharIndex in Zeichen (0-basiert): fuer das X die
  // Zahl der Zeichen davor.
  Col := CharColOfIndex(Pos('X', LINE_TEXT) - 1);
  Assert.AreEqual<Integer>(Pos('X', LINE_TEXT), Col);
  Assert.AreEqual('X', Copy(LINE_TEXT, Col, 1), 'die Spalte trifft das Zeichen');
  ByteCol := TEncoding.UTF8.GetByteCount(Copy(LINE_TEXT, 1, Col - 1)) + 1;
  Assert.AreEqual<Integer>(Col + 4, ByteCol, 'die Byte-Spalte laege 4 weiter rechts');
end;

procedure TTestEditorContextModel.CharCol_Negative_One;
begin
  Assert.AreEqual<Integer>(1, CharColOfIndex(0));
  Assert.AreEqual<Integer>(1, CharColOfIndex(-1));
  Assert.AreEqual<Integer>(20, CharColOfIndex(19));
end;

{ Fragt das Menue Anbieter? }

procedure TTestEditorContextModel.Wanted_NoProviders_False;
begin
  Assert.IsFalse(EditorMenuWanted(True));
  Assert.IsFalse(EditorMenuWanted(False));
end;

procedure TTestEditorContextModel.Wanted_ContextProviderOnly_FollowsSwitch;
var
  P   : TStub;
  Tok : Integer;
begin
  P := TStub.Create;
  Tok := TFindingActions.RegisterContext(P.ProvideContext);
  try
    Assert.IsTrue(EditorMenuWanted(True));
    Assert.IsFalse(EditorMenuWanted(False), 'Not-Aus: Kontext-Anbieter allein weckt nichts');
  finally
    TFindingActions.Unregister(Tok);
    P.Free;
  end;
end;

procedure TTestEditorContextModel.Wanted_FindingProvider_IgnoresSwitch;
var
  P   : TStub;
  Tok : Integer;
begin
  P := TStub.Create;
  Tok := TFindingActions.Register(P.ProvideFinding);
  try
    Assert.IsTrue(EditorMenuWanted(False), 'Fund-Aktionen wie bis Charge B');
    Assert.IsTrue(EditorMenuWanted(True));
  finally
    TFindingActions.Unregister(Tok);
    P.Free;
  end;
end;

{ Das Modell }

procedure TTestEditorContextModel.Popup_SwitchOff_NoContextAsked;
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
  PC.Captions := ['Konstante'];
  TokF := TFindingActions.Register(PF.ProvideFinding);
  TokC := TFindingActions.RegisterContext(PC.ProvideContext);
  try
    C := TEditorContext.At(CTX_FILE, 10, 3);
    C.Findings := [F];
    M := BuildEditorPopupModel(C, False, CTX_HEADER);
    Assert.AreEqual<Integer>(1, M.ActionCount, 'nur die Fund-Aktion');
    Assert.AreEqual<Integer>(0, M.ContextEntryCount);
    Assert.AreEqual<Integer>(0, PC.Asked, 'Not-Aus: Kontext-Anbieter nie gefragt');
    Assert.AreEqual<Integer>(3, Length(M.Entries), 'Trenner, Kopf, Aktion wie bisher');
  finally
    TFindingActions.Unregister(TokC);
    TFindingActions.Unregister(TokF);
    PC.Free;
    PF.Free;
    F.Free;
  end;
end;

procedure TTestEditorContextModel.Popup_SwitchOn_NoFinding_HeaderAndAction;
var
  P   : TStub;
  Tok : Integer;
  M   : TFindingMenuModel;
begin
  P := TStub.Create;
  P.Captions := ['Konstante'];
  Tok := TFindingActions.RegisterContext(P.ProvideContext);
  try
    M := BuildEditorPopupModel(TEditorContext.At(CTX_FILE, 3, 7), True, CTX_HEADER);
    Assert.AreEqual<Integer>(1, M.ActionCount, 'ein Menue auch ohne Fund');
    Assert.AreEqual<Integer>(3, Length(M.Entries));
    Assert.IsTrue(M.Entries[0].Kind = mkSeparator, 'Trenner (moLeadingSeparator)');
    Assert.IsTrue(M.Entries[1].Kind = mkHeader, 'Kopfzeile (moHeaders)');
    Assert.AreEqual(CTX_HEADER, M.Entries[1].Caption);
    Assert.IsFalse(M.Entries[1].Enabled, 'Kopfzeile deaktiviert');
    Assert.IsTrue(M.Entries[2].Kind = mkAction);
    Assert.IsTrue(M.Actions[0].Kind = fakContext, 'nie per Taste');
    Assert.AreEqual<Integer>(3, M.ContextEntryCount);
  finally
    TFindingActions.Unregister(Tok);
    P.Free;
  end;
end;

procedure TTestEditorContextModel.Popup_SwitchOn_SameCaption_OnceAtTheFinding;
const
  CAP = 'Introduce local constant for 42';
var
  PF, PC : TStub;
  TokF   : Integer;
  TokC   : Integer;
  F      : TLeakFinding;
  C      : TEditorContext;
  M      : TFindingMenuModel;
  i, n   : Integer;
begin
  F := Finding('Magic number 42');
  PF := TStub.Create;
  PC := TStub.Create;
  PF.Captions := [CAP];
  PC.Captions := [CAP, 'Free X in a try/finally block'];
  TokF := TFindingActions.Register(PF.ProvideFinding);
  TokC := TFindingActions.RegisterContext(PC.ProvideContext);
  try
    C := TEditorContext.At(CTX_FILE, 10, 3);
    C.Findings := [F];
    M := BuildEditorPopupModel(C, True, CTX_HEADER);
    n := 0;
    for i := 0 to High(M.Actions) do
      if M.Actions[i].Caption = CAP then
        Inc(n);
    Assert.AreEqual<Integer>(1, n, 'gleiche Caption nur einmal');
    Assert.IsTrue(M.Actions[0].Kind = fakFix, 'und zwar am Fund');
    Assert.AreEqual<Integer>(2, M.ActionCount);
    Assert.AreEqual<Integer>(1, M.ContextActionCount);
  finally
    TFindingActions.Unregister(TokC);
    TFindingActions.Unregister(TokF);
    PC.Free;
    PF.Free;
    F.Free;
  end;
end;

procedure TTestEditorContextModel.Popup_NotWanted_EmptyModel;
var
  F : TLeakFinding;
  C : TEditorContext;
  M : TFindingMenuModel;
begin
  F := Finding('Concat A');
  try
    C := TEditorContext.At(CTX_FILE, 10, 3);
    C.Findings := [F];
    M := BuildEditorPopupModel(C, True, CTX_HEADER);
    Assert.IsTrue(M.IsEmpty);
    Assert.AreEqual<Integer>(0, Length(M.Entries));
    Assert.AreEqual<Integer>(0, M.Omitted);
  finally
    F.Free;
  end;
end;

{ Omitted-Hinweiszeile }

function OneFindingModel(F: TLeakFinding): TFindingMenuModel;
var
  Lists : TArray<TArray<TFindingAction>>;
  A     : TFindingAction;
begin
  A := Default(TFindingAction);
  A.Caption := 'Stelle zeigen';
  A.Kind    := fakNavigate;
  SetLength(Lists, 1);
  Lists[0] := [A];
  Result := BuildFindingMenuModelFrom([F], Lists, EDITOR_MENU_OPTIONS);
  Result.Omitted := 3;   // wie bei mehr als MAX_FINDINGS_PER_MENU Funden
end;

procedure TTestEditorContextModel.Omitted_NoContext_AtTheEnd;
var
  F : TLeakFinding;
  M : TFindingMenuModel;
begin
  F := Finding('Concat A');
  try
    M := OneFindingModel(F);
    Assert.AreEqual<Integer>(3, Length(M.Entries));
    Assert.AreEqual<Integer>(3, OmittedLineIndex(M), 'ohne Kontextteil am Ende');
  finally
    F.Free;
  end;
end;

procedure TTestEditorContextModel.Omitted_WithContext_BeforeContextPart;
var
  F : TLeakFinding;
  M : TFindingMenuModel;
  A : TFindingAction;
begin
  F := Finding('Concat A');
  try
    M := OneFindingModel(F);
    A := Default(TFindingAction);
    A.Caption := 'Konstante';
    A.Enabled := True;
    AppendContextActions(M, [A], EDITOR_MENU_OPTIONS, CTX_HEADER);
    Assert.AreEqual<Integer>(6, Length(M.Entries), 'Fund 3 + Trenner, Kopf, Aktion');
    Assert.AreEqual<Integer>(3, OmittedLineIndex(M), 'vor dem Trenner des Kontextteils');
    Assert.IsTrue(M.Entries[OmittedLineIndex(M)].Kind = mkSeparator);
  finally
    F.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEditorContextModel);

end.
