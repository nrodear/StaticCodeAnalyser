unit uRdxProvider;

// reDelphix - der Anbieter: haengt an Funde des SCA-Plugins Aktionen
// (uFindingActions in SCA.Engine, Konzept_SourceRefactor_Quellstellen
// Abschnitt 15). Je Rechtsklick auf einen Fund wird Provide gerufen; es
// oeffnet die Datei ueber TSourcePlaces (nur lesen, kein Scan), baut aus
// den beschriebenen Stellen Aktionen und haelt deren Daten in
// TRdxAction-Objekten, bis das naechste Provide sie ersetzt.
//
// WAS ANGEBOTEN WIRD
//
//   "Stelle zeigen"                    wenn sich die Anweisung des Funds
//                                      beschreiben laesst (Anker der Regel)
//   "Format() aus Verkettung bilden"   fixMode = auto (SCA044); aktiv nur bei
//                                      FixSafe, SysUtils in uses, kein SQL
//   "Parametrisierte Vorlage ..."      fixMode = assisted (SCA003); nur in
//                                      die Zwischenablage, nie geschrieben
//   "uses: X -> Scope.X"               Fund liegt in einer uses-Klausel;
//                                      je unqualifiziertem Eintrag der Zeile,
//                                      dazu "alle n Eintraege"
//
// Ein deaktivierter Eintrag traegt seinen Grund im Hint - der Benutzer
// soll sehen, WARUM sich eine Stelle nicht umformen laesst.
//
// WAS DER ANBIETER NICHT TUT
//
// Er schreibt nichts in eine Datei (nur in den Editor-Puffer, ueber
// uRdxEditor mit Vergleich gegen den Scan), meldet keinen Fund und
// ruft keinen Scan. Nach einer Umformung zeigt die Fundliste des Plugins
// den alten Stand, bis der Benutzer die Datei erneut scannt.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uEngineApi, uRefactorInfo, uMethodd12, uFindingActions,
  uRdxRecipes, uRdxScopeTable;

type
  TRdxActionKind = (akShowSpan, akFormatCall, akSqlTemplate, akUsesExpand);

  // Eine Ersetzung im Editor: Bereich, erwarteter alter Text, neuer Text.
  TRdxEdit = record
    Span     : TRefactorSpan;
    Expected : string;
    NewText  : string;
  end;

  // Ein Menuepunkt samt allem, was Execute braucht. Lebt im Anbieter bis
  // zum naechsten Provide.
  TRdxAction = class
  private
    FKind     : TRdxActionKind;
    FFileName : string;
    FSpan     : TRefactorSpan;
    FTemplate : string;
    FEdits    : TArray<TRdxEdit>;
  public
    // TNotifyEvent fuer TFindingAction.Execute. Fehler laufen als
    // Exception zum Host, der sie in seiner Statuszeile zeigt.
    procedure Execute(Sender: TObject);
  end;

  TRdxProvider = class
  private
    FActions   : TObjectList<TRdxAction>;
    FPlaces    : TSourcePlaces;
    FScopes    : TRdxScopeTable;
    FToken     : Integer;
    FUsesNames : TArray<string>;   // qualifizierte/rohe Namen der uses-Eintraege der Datei
    function NewAction(AKind: TRdxActionKind;
      const AFileName: string): TRdxAction;
    procedure Add(var AList: TArray<TFindingAction>;
      const ACaption, AHint: string; AEnabled: Boolean; AAction: TRdxAction);
    function PartsOf(AInfo: TRefactorInfo): TRdxParts;
    function UnsafeReason(AInfo: TRefactorInfo; const AParts: TRdxParts): string;
    function DescribeAnchor(ALine: Integer; const AAnchor: string;
      out AIsCall: Boolean; out AWhy: string): TRefactorInfo;
    procedure AddShowSpan(var AList: TArray<TFindingAction>;
      const AFileName: string; AInfo: TRefactorInfo);
    procedure AddFormatCall(var AList: TArray<TFindingAction>;
      const AFileName: string; AInfo: TRefactorInfo; const AWhy: string);
    procedure AddSqlTemplate(var AList: TArray<TFindingAction>;
      AInfo: TRefactorInfo; AIsCall: Boolean; const AWhy: string);
    procedure AddUsesActions(var AList: TArray<TFindingAction>;
      const AFileName: string; ALine: Integer);
    // Der Einstieg des Hosts (TFindingActionProvider).
    function Provide(const AFinding: TLeakFinding): TArray<TFindingAction>;
  public
    constructor Create;
    destructor Destroy; override;

    class function Instance: TRdxProvider; static;
    // Abmelden und freigeben - aus der finalization von uRdxRegister.
    class procedure Shutdown; static;

    procedure RegisterAtHost;
    procedure UnregisterAtHost;
    property Token: Integer read FToken;
    property Scopes: TRdxScopeTable read FScopes;
  end;

implementation

uses
  Winapi.Windows,   // OutputDebugString - Diagnose ohne UI (DebugView)
  Vcl.Clipbrd,
  uRuleCatalog,
  uRdxEditor;

const
  CAP_SHOW     = 'Stelle zeigen';
  CAP_FORMAT   = 'Format() aus Verkettung bilden';
  CAP_SQL      = 'Parametrisierte Vorlage in die Zwischenablage';
  CAP_USES_ALL = 'uses: alle %d Eintraege qualifizieren';
  DIAG_PREFIX  = 'reDelphix: ';

var
  GInstance : TRdxProvider = nil;

function HeadOf(const ACallName: string): string;
// nkCall.Name traegt den ganzen Aufruf samt Argumenten; der Kopf ist der
// Teil vor der ersten Klammer.
var
  P : Integer;
begin
  Result := ACallName;
  P := Pos('(', Result);
  if P > 0 then
    Result := Copy(Result, 1, P - 1);
  Result := Trim(Result);
end;

procedure SortEditsDescending(var AEdits: TArray<TRdxEdit>);
// Von hinten nach vorn ersetzen, damit fruehere Bereiche gueltig bleiben.
var
  i, j : Integer;
  T    : TRdxEdit;
  Later: Boolean;
begin
  for i := 1 to High(AEdits) do
  begin
    T := AEdits[i];
    j := i - 1;
    while j >= 0 do
    begin
      Later := (T.Span.StartLine > AEdits[j].Span.StartLine)
        or ((T.Span.StartLine = AEdits[j].Span.StartLine)
            and (T.Span.StartCol > AEdits[j].Span.StartCol));
      if not Later then Break;
      AEdits[j + 1] := AEdits[j];
      Dec(j);
    end;
    AEdits[j + 1] := T;
  end;
end;

{ TRdxAction }

procedure TRdxAction.Execute(Sender: TObject);
var
  Err : string;
  i   : Integer;
begin
  case FKind of
    akShowSpan:
      if not TRdxEditor.SelectSpan(FFileName, FSpan, Err) then
        raise Exception.Create(Err);
    akFormatCall, akUsesExpand:
      for i := 0 to High(FEdits) do
        if not TRdxEditor.ReplaceSpan(FFileName, FEdits[i].Span,
             FEdits[i].Expected, FEdits[i].NewText, Err) then
          raise Exception.CreateFmt('%s: %s',
            [TRdxRecipes.CollapseWhitespace(FEdits[i].Expected), Err]);
    akSqlTemplate:
      Clipboard.AsText := FTemplate;
  end;
end;

{ TRdxProvider }

constructor TRdxProvider.Create;
begin
  inherited Create;
  FActions := TObjectList<TRdxAction>.Create(True);
  FPlaces  := TSourcePlaces.Create;
  FScopes  := TRdxScopeTable.Create;
  FScopes.LoadDefault;   // False = keine Tabelle; uses-Aktionen sagen das
end;

destructor TRdxProvider.Destroy;
begin
  UnregisterAtHost;
  FScopes.Free;
  FPlaces.Free;
  FActions.Free;
  inherited;
end;

class function TRdxProvider.Instance: TRdxProvider;
begin
  if GInstance = nil then
    GInstance := TRdxProvider.Create;
  Result := GInstance;
end;

class procedure TRdxProvider.Shutdown;
begin
  FreeAndNil(GInstance);   // Destroy meldet ab
end;

procedure TRdxProvider.RegisterAtHost;
begin
  if FToken = 0 then
    FToken := TFindingActions.Register(Provide);
  OutputDebugString(PChar(Format('reDelphix: registriert, Token %d, '
    + 'Anbieter gesamt %d, Scope-Tabelle %d Eintraege aus %s',
    [FToken, TFindingActions.ProviderCount, FScopes.Count, FScopes.Source])));
end;

procedure TRdxProvider.UnregisterAtHost;
begin
  if FToken <> 0 then
  begin
    TFindingActions.Unregister(FToken);
    FToken := 0;
  end;
end;

function TRdxProvider.NewAction(AKind: TRdxActionKind;
  const AFileName: string): TRdxAction;
begin
  Result := TRdxAction.Create;
  Result.FKind     := AKind;
  Result.FFileName := AFileName;
  FActions.Add(Result);
end;

procedure TRdxProvider.Add(var AList: TArray<TFindingAction>;
  const ACaption, AHint: string; AEnabled: Boolean; AAction: TRdxAction);
var
  A : TFindingAction;
begin
  A.Caption := ACaption;
  A.Hint    := AHint;
  A.Enabled := AEnabled and Assigned(AAction);
  if Assigned(AAction) then
    A.Execute := AAction.Execute
  else
    A.Execute := nil;
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := A;
end;

function TRdxProvider.PartsOf(AInfo: TRefactorInfo): TRdxParts;
var
  i : Integer;
begin
  SetLength(Result, Length(AInfo.Parts));
  for i := 0 to High(AInfo.Parts) do
    Result[i] := TRdxRecipes.MakePart(AInfo.Parts[i].Role,
      FPlaces.TextOf(AInfo.Parts[i]), AInfo.Parts[i].ValueType);
end;

function TRdxProvider.UnsafeReason(AInfo: TRefactorInfo;
  const AParts: TRdxParts): string;
var
  i : Integer;
begin
  if rfHasComment in AInfo.Flags then Exit('Kommentar im Bereich');
  if rfInConditional in AInfo.Flags then Exit('Bereich liegt in einem $IFDEF');
  for i := 0 to High(AParts) do
    if (AParts[i].Role = ROLE_OPERAND) and (AParts[i].ValueType <> rvString) then
      Exit(Format('Operand ''%s'': Typ unbekannt',
        [TRdxRecipes.CollapseWhitespace(AParts[i].Text)]));
  Result := 'Kette nicht rein (Operator auf oberster Ebene)';
end;

function TRdxProvider.DescribeAnchor(ALine: Integer; const AAnchor: string;
  out AIsCall: Boolean; out AWhy: string): TRefactorInfo;
var
  Kinds : TNodeKinds;
  Nodes : TArray<TNodeRef>;
  N     : TNodeRef;
begin
  Result  := nil;
  AIsCall := False;
  AWhy    := '';
  if AAnchor = 'assign' then
    Kinds := [TNodeKind.nkAssign]
  else if AAnchor = 'call' then
    Kinds := [TNodeKind.nkCall]
  else
    Kinds := [TNodeKind.nkAssign, TNodeKind.nkCall];
  Nodes := FPlaces.NodesAt(ALine, Kinds);
  if Length(Nodes) = 0 then
  begin
    AWhy := Format('keine Anweisung auf Zeile %d gefunden', [ALine]);
    Exit;
  end;
  if Length(Nodes) > 1 then
  begin
    AWhy := Format('Zeile %d ist mehrdeutig (%d Anweisungen)',
      [ALine, Length(Nodes)]);
    Exit;
  end;
  N := Nodes[0];
  if N.Kind = TNodeKind.nkAssign then
    Result := FPlaces.ChainOf(N.Line, N.Col, N.Name)
  else
  begin
    AIsCall := True;
    Result := FPlaces.CallOf(N.Line, N.Col, HeadOf(N.Name));
  end;
  // Ohne Kette wenigstens die Anweisung selbst (fuer "Stelle zeigen").
  if Result = nil then
    Result := FPlaces.StatementAt(N.Line, N.Col);
  if Result = nil then
    AWhy := 'Anweisung laesst sich nicht beschreiben';
end;

procedure TRdxProvider.AddShowSpan(var AList: TArray<TFindingAction>;
  const AFileName: string; AInfo: TRefactorInfo);
var
  Act : TRdxAction;
begin
  if not AInfo.Span.IsValid then Exit;
  Act := NewAction(akShowSpan, AFileName);
  Act.FSpan := AInfo.Span;
  Add(AList, CAP_SHOW, Format('Zeile %d:%d bis %d:%d',
    [AInfo.Span.StartLine, AInfo.Span.StartCol,
     AInfo.Span.EndLine, AInfo.Span.EndCol - 1]), True, Act);
end;

procedure TRdxProvider.AddFormatCall(var AList: TArray<TFindingAction>;
  const AFileName: string; AInfo: TRefactorInfo; const AWhy: string);
var
  Parts   : TRdxParts;
  Reason  : string;
  NewText : string;
  Repl    : TRefactorSpan;
  Act     : TRdxAction;
  Last    : Integer;
begin
  if AInfo = nil then
  begin
    Add(AList, CAP_FORMAT, AWhy, False, nil);
    Exit;
  end;
  Parts   := PartsOf(AInfo);
  Reason  := '';
  NewText := '';
  Last := High(AInfo.Parts);
  if (Last < 1) or (AInfo.Parts[0].Role <> ROLE_TARGET) then
    Reason := 'keine Zuweisung mit Kette'
  else if not AInfo.FixSafe then
    Reason := UnsafeReason(AInfo, Parts)
  else if not TRdxRecipes.HasUnit(FUsesNames, 'SysUtils') then
    Reason := 'System.SysUtils fehlt in uses';
  if Reason = '' then
    TRdxRecipes.BuildFormatCall(Parts, NewText, Reason);
  if Reason <> '' then
  begin
    Add(AList, CAP_FORMAT, Reason, False, nil);
    Exit;
  end;
  // Ersetzt wird vom ersten bis zum letzten Term; Ziel und ':=' bleiben.
  Repl := TRefactorSpan.Make(ROLE_STATEMENT,
    AInfo.Parts[1].StartLine, AInfo.Parts[1].StartCol,
    AInfo.Parts[Last].EndLine, AInfo.Parts[Last].EndCol);
  Act := NewAction(akFormatCall, AFileName);
  SetLength(Act.FEdits, 1);
  Act.FEdits[0].Span     := Repl;
  Act.FEdits[0].Expected := FPlaces.TextOf(Repl);
  Act.FEdits[0].NewText  := NewText;
  if Act.FEdits[0].Expected = '' then
  begin
    Add(AList, CAP_FORMAT, 'Bereich nicht lesbar', False, nil);
    Exit;
  end;
  Add(AList, CAP_FORMAT, Format('%d Terme, alle Strings', [Last]), True, Act);
end;

procedure TRdxProvider.AddSqlTemplate(var AList: TArray<TFindingAction>;
  AInfo: TRefactorInfo; AIsCall: Boolean; const AWhy: string);
var
  Parts    : TRdxParts;
  Template : string;
  Reason   : string;
  Act      : TRdxAction;
  i, N     : Integer;
begin
  if AInfo = nil then
  begin
    Add(AList, CAP_SQL, AWhy, False, nil);
    Exit;
  end;
  Parts := PartsOf(AInfo);
  if (Length(Parts) = 0) or (Parts[0].Role <> ROLE_TARGET) then
  begin
    Add(AList, CAP_SQL, 'kein Ziel erkannt', False, nil);
    Exit;
  end;
  if not TRdxRecipes.BuildSqlTemplate(Parts[0].Text, AIsCall, Parts,
       AInfo.InsertIndent, Template, Reason) then
  begin
    Add(AList, CAP_SQL, Reason, False, nil);
    Exit;
  end;
  N := 0;
  for i := 0 to High(Parts) do
    if Parts[i].Role = ROLE_OPERAND then Inc(N);
  Act := NewAction(akSqlTemplate, '');
  Act.FTemplate := Template;
  Add(AList, CAP_SQL, Format('%d Parameter, nichts wird geschrieben', [N]),
    True, Act);
end;

procedure TRdxProvider.AddUsesActions(var AList: TArray<TFindingAction>;
  const AFileName: string; ALine: Integer);
var
  Section  : TUsesSection;
  Entries  : TArray<TRefactorSpan>;
  i        : Integer;
  Lo, Hi   : Integer;
  InUses   : Boolean;
  Fw       : TRdxFramework;
  Short    : string;
  Q        : string;
  Reason   : string;
  OK       : Boolean;
  Act      : TRdxAction;
  All      : TArray<TRdxEdit>;
  E        : TRdxEdit;
  Preview  : string;
begin
  // Nur wenn der Fund in einer uses-Klausel liegt (Zeile des 'uses' bis
  // letzter Eintrag) - sonst stuende "uses: ..." an jedem Fund der Datei.
  InUses := False;
  for Section := TUsesSection.usInterface to TUsesSection.usImplementation do
  begin
    Entries := FPlaces.UsesEntries(Section);
    if Length(Entries) = 0 then Continue;
    Lo := Entries[0].StartLine - 1;
    Hi := Entries[0].EndLine;
    for i := 1 to High(Entries) do
    begin
      if Entries[i].StartLine - 1 < Lo then Lo := Entries[i].StartLine - 1;
      if Entries[i].EndLine > Hi then Hi := Entries[i].EndLine;
    end;
    if (ALine >= Lo) and (ALine <= Hi) then InUses := True;
  end;
  if not InUses then Exit;

  if FScopes.Count = 0 then
  begin
    Add(AList, 'uses: Eintraege qualifizieren',
      'Scope-Tabelle nicht geladen (unitscopes.txt)', False, nil);
    Exit;
  end;

  Entries := FPlaces.UsesEntries(TUsesSection.usAny);
  Fw := TRdxRecipes.DetectFramework(FUsesNames);
  All := nil;
  Preview := '';
  for i := 0 to High(Entries) do
  begin
    Short := Entries[i].Resolved;
    if (Short = '') or (Pos('.', Short) > 0) then Continue;
    OK := FScopes.Resolve(Short, Fw, Q, Reason);
    if OK and TRdxEditor.ProjectHasUnit(Short, AFileName) then
    begin
      OK := False;
      Reason := 'eigene Unit ' + Short + ' im Projekt';
    end;
    if OK then
    begin
      E.Span     := Entries[i];
      E.Expected := Short;
      E.NewText  := Q;
      SetLength(All, Length(All) + 1);
      All[High(All)] := E;
      if Length(All) <= 3 then
      begin
        if Preview <> '' then Preview := Preview + ', ';
        Preview := Preview + Q;
      end;
    end;
    if Entries[i].StartLine <> ALine then Continue;
    if OK then
    begin
      Act := NewAction(akUsesExpand, AFileName);
      SetLength(Act.FEdits, 1);
      Act.FEdits[0] := E;
      Add(AList, 'uses: ' + Short + ' -> ' + Q, '', True, Act);
    end
    else
      Add(AList, 'uses: ' + Short + ' qualifizieren', Reason, False, nil);
  end;
  if Length(All) >= 2 then
  begin
    SortEditsDescending(All);
    Act := NewAction(akUsesExpand, AFileName);
    Act.FEdits := All;
    if Length(All) > 3 then Preview := Preview + ', ...';
    Add(AList, Format(CAP_USES_ALL, [Length(All)]), Preview, True, Act);
  end;
end;

function TRdxProvider.Provide(
  const AFinding: TLeakFinding): TArray<TFindingAction>;
var
  Meta    : TRuleMeta;
  Anchor  : string;
  FixMode : string;
  Line    : Integer;
  Info    : TRefactorInfo;
  IsCall  : Boolean;
  Why     : string;
  Entries : TArray<TRefactorSpan>;
  i       : Integer;
begin
  Result := nil;
  FActions.Clear;
  FUsesNames := nil;
  if not Assigned(AFinding) then Exit;
  Line := AFinding.LineInt;
  // Bleibt am Ende nichts anzubieten, steht WARUM als ausgegrauter
  // Eintrag im Menue - sonst ist "kein Eintrag" nicht von "Anbieter nicht
  // geladen" zu unterscheiden.
  if AFinding.FileName = '' then
  begin
    Add(Result, DIAG_PREFIX + 'Fund ohne Dateiname', '', False, nil);
    Exit;
  end;
  if not FileExists(AFinding.FileName) then
  begin
    Add(Result, DIAG_PREFIX + 'Datei nicht gefunden: ' + AFinding.FileName,
      '', False, nil);
    Exit;
  end;
  if Line < 1 then
  begin
    Add(Result, DIAG_PREFIX + 'Fund ohne Zeile', '', False, nil);
    Exit;
  end;
  try
    if not FPlaces.Open(AFinding.FileName) then
    begin
      Add(Result, DIAG_PREFIX + 'Datei nicht lesbar', '', False, nil);
      Exit;
    end;
  except
    on E: Exception do
    begin
      Add(Result, DIAG_PREFIX + 'Parser: ' + E.Message, '', False, nil);
      Exit;
    end;
  end;
  Info := nil;
  try
    Entries := FPlaces.UsesEntries(TUsesSection.usAny);
    SetLength(FUsesNames, Length(Entries));
    for i := 0 to High(Entries) do
      FUsesNames[i] := Entries[i].Resolved;

    Meta    := TRuleCatalog.GetRuleCanonical(AFinding.Kind);
    Anchor  := LowerCase(Meta.Anchor);
    FixMode := LowerCase(Meta.FixMode);
    OutputDebugString(PChar(Format('reDelphix: %s %s:%d anchor=%s fixMode=%s',
      [AFinding.ResolvedRuleId, ExtractFileName(AFinding.FileName), Line,
       Anchor, FixMode])));

    Info := DescribeAnchor(Line, Anchor, IsCall, Why);
    if Assigned(Info) then
      AddShowSpan(Result, AFinding.FileName, Info);
    if FixMode = 'auto' then
      AddFormatCall(Result, AFinding.FileName, Info, Why)
    else if FixMode = 'assisted' then
      AddSqlTemplate(Result, Info, IsCall, Why);
    AddUsesActions(Result, AFinding.FileName, Line);

    if Length(Result) = 0 then
    begin
      if Why <> '' then
        Add(Result, DIAG_PREFIX + Why, '', False, nil)
      else if FixMode = '' then
        Add(Result, DIAG_PREFIX + AFinding.ResolvedRuleId
          + ': kein fixMode im Regelkatalog', '', False, nil)
      else
        Add(Result, DIAG_PREFIX + 'nichts anzubieten', '', False, nil);
    end;
  finally
    Info.Free;   // alles Noetige ist in die Aktionen kopiert
    FPlaces.Close;
  end;
end;

end.
