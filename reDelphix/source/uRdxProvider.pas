unit uRdxProvider;

// reDelphix - der Anbieter: haengt an Funde des SCA-Plugins Aktionen
// (uFindingActions in SCA.Engine, Konzept_SourceRefactor_Quellstellen
// Abschnitt 15). Je Rechtsklick auf einen Fund wird Provide gerufen; es
// oeffnet die Datei ueber TSourcePlaces (nur lesen, kein Scan), laesst
// den Rezept-Laeufer (uRdxRecipeRunner) die Stellen beschreiben und
// haelt die Daten der Aktionen in TRdxAction-Objekten, bis das naechste
// Provide sie ersetzt.
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
//   "reDelphix: <Grund>"               ausgegraut, wenn nichts davon geht -
//                                      sonst waere "kein Eintrag" nicht von
//                                      "Anbieter nicht geladen" zu
//                                      unterscheiden
//
// Ein deaktivierter Eintrag traegt seinen Grund im Hint.
//
// WAS DER ANBIETER NICHT TUT
//
// Er schreibt nichts in eine Datei (nur in den Editor-Puffer, ueber
// uRdxEditor mit Vergleich gegen den Scan), meldet keinen Fund und
// ruft keinen Scan. Nach einer Umformung zeigt die Fundliste des Plugins
// den alten Stand, bis der Benutzer die Datei erneut scannt.

interface

uses
  System.SysUtils,
  uEngineApi, uRefactorInfo, uMethodd12, uFindingActions,
  uRdxRecipes, uRdxScopeTable, uRdxRecipeRunner;

type
  TRdxActionKind = (akShowSpan, akReplace, akSqlTemplate);

  // Ein Menuepunkt samt allem, was Execute braucht. Lebt im Anbieter, bis
  // MAX_BATCHES neuere Provide-Chargen entstanden sind (TRdxObjectRing) -
  // nicht nur bis zum naechsten Provide, denn ein Host stellt die
  // Aktionen mehrerer Funde in ein Menue (Stufe B, Konzept Editor-
  // Gluehbirne 2026-10-06). Mehrere Ersetzungen (TRdxEdit aus uRdxRecipeRunner)
  // werden von unten nach oben ausgefuehrt, damit die Bereiche der
  // oberen von den unteren nicht verschoben werden.
  TRdxAction = class
  private
    FKind     : TRdxActionKind;
    FFileName : string;
    FSpan     : TRefactorSpan;
    FTemplate : string;
    FEdits    : TArray<TRdxEdit>;
  public
    // TNotifyEvent fuer TFindingAction.Execute. Fehler laufen als
    // Exception zum Host, der sie anzeigt.
    procedure Execute(Sender: TObject);
  end;

  TRdxProvider = class
  private
    FActions   : TRdxObjectRing;   // besitzt die TRdxAction-Objekte
    FPlaces    : TSourcePlaces;
    FScopes    : TRdxScopeTable;
    FToken     : Integer;
    FUsesNames : TArray<string>;   // Namen der uses-Eintraege der Datei
    function NewAction(AKind: TRdxActionKind;
      const AFileName: string): TRdxAction;
    procedure Add(var AList: TArray<TFindingAction>;
      const ACaption, AHint: string; AEnabled: Boolean; AAction: TRdxAction);
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
  Vcl.Clipbrd,
  uRuleCatalog,
  uRdxEditor,
  uRdxLog;          // Protokoll: DebugView + %TEMP%\reDelphix.log

const
  CAP_SHOW     = 'Stelle zeigen';
  CAP_FORMAT   = 'Format() aus Verkettung bilden';
  CAP_SQL      = 'Parametrisierte Vorlage in die Zwischenablage';
  CAP_USES_ALL = 'uses: alle %d Eintraege qualifizieren';
  DIAG_PREFIX  = 'reDelphix: ';

var
  GInstance : TRdxProvider = nil;

procedure SortEditsDescending(var AEdits: TArray<TRdxEdit>);
// Von hinten nach vorn ersetzen, damit fruehere Bereiche gueltig bleiben.
var
  i, j  : Integer;
  T     : TRdxEdit;
  Later : Boolean;
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
    akReplace:
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

const
  // Soviel Provide-Chargen bleiben am Leben (je Charge alle Aktions-
  // objekte eines Funds); ein Menue umfasst eine Handvoll Funde, 32 deckt
  // auch viele Funde auf einer Zeile.
  MAX_BATCHES = 32;

constructor TRdxProvider.Create;
begin
  inherited Create;
  FActions := TRdxObjectRing.Create(MAX_BATCHES);
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
  RdxLog('registriert, Token %d, Anbieter gesamt %d, Scope-Tabelle %d '
    + 'Eintraege aus %s',
    [FToken, TFindingActions.ProviderCount, FScopes.Count, FScopes.Source]);
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
  FActions.Keep(Result);
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
  Outcome : TRdxFormatOutcome;
  Act     : TRdxAction;
begin
  Outcome := TRdxRecipeRunner.FormatRewrite(FPlaces, AInfo, AWhy, FUsesNames);
  if not Outcome.Enabled then
  begin
    Add(AList, CAP_FORMAT, Outcome.Reason, False, nil);
    Exit;
  end;
  Act := NewAction(akReplace, AFileName);
  SetLength(Act.FEdits, 1);
  Act.FEdits[0].Span     := Outcome.Span;
  Act.FEdits[0].Expected := Outcome.Expected;
  Act.FEdits[0].NewText  := Outcome.NewText;
  if Outcome.NeedsUses then
  begin
    // Zweite Ersetzung: System.SysUtils in die uses-Klausel. Liegt
    // oberhalb der Kette - SortEditsDescending fuehrt sie als zweite aus.
    SetLength(Act.FEdits, 2);
    Act.FEdits[1] := Outcome.UsesEdit;
    SortEditsDescending(Act.FEdits);
  end;
  Add(AList, CAP_FORMAT, Outcome.Hint, True, Act);
end;

procedure TRdxProvider.AddSqlTemplate(var AList: TArray<TFindingAction>;
  AInfo: TRefactorInfo; AIsCall: Boolean; const AWhy: string);
var
  Template, Hint, Reason : string;
  Act : TRdxAction;
begin
  if AInfo = nil then
  begin
    Add(AList, CAP_SQL, AWhy, False, nil);
    Exit;
  end;
  if not TRdxRecipeRunner.SqlTemplate(FPlaces, AInfo, AIsCall,
       Template, Hint, Reason) then
  begin
    Add(AList, CAP_SQL, Reason, False, nil);
    Exit;
  end;
  Act := NewAction(akSqlTemplate, '');
  Act.FTemplate := Template;
  Add(AList, CAP_SQL, Hint, True, Act);
end;

procedure TRdxProvider.AddUsesActions(var AList: TArray<TFindingAction>;
  const AFileName: string; ALine: Integer);
var
  Section : TUsesSection;
  Entries : TArray<TRefactorSpan>;
  i       : Integer;
  Lo, Hi  : Integer;
  InUses  : Boolean;
  Fw      : TRdxFramework;
  Short   : string;
  Q       : string;
  Reason  : string;
  OK      : Boolean;
  Act     : TRdxAction;
  All     : TArray<TRdxEdit>;
  E       : TRdxEdit;
  Preview : string;
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
      Act := NewAction(akReplace, AFileName);
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
    Act := NewAction(akReplace, AFileName);
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
  Line       : Integer;
  Info       : TRefactorInfo;
  IsCall     : Boolean;
  Why        : string;
  BufferText   : string;
  BufferSource : string;
  Opened       : Boolean;
begin
  Result := nil;
  // Kein FActions.Clear mehr (Stufe B): die Objekte des vorigen Provide
  // haengen womoeglich noch an Menuepunkten desselben Menues - eine neue
  // Charge, die aelteste faellt heraus.
  FActions.BeginBatch;
  FUsesNames := nil;
  if not Assigned(AFinding) then Exit;
  Line := AFinding.LineInt;
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
    // Der EDITOR-PUFFER ist die Wahrheit, wenn die Datei offen ist: nur
    // dann passen die beschriebenen Bereiche zu dem Text, in den nachher
    // geschrieben wird (ungespeicherte Aenderungen!). Sonst die Platte.
    if TRdxEditor.TryReadBuffer(AFinding.FileName, BufferText) then
    begin
      BufferSource := 'Editor-Puffer';
      Opened := FPlaces.OpenSource(AFinding.FileName, BufferText);
    end
    else
    begin
      BufferSource := 'Platte';
      Opened := FPlaces.Open(AFinding.FileName);
    end;
    if not Opened then
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
    FUsesNames := TRdxRecipeRunner.UsesNamesOf(FPlaces);

    Meta    := TRuleCatalog.GetRuleCanonical(AFinding.Kind);
    Anchor  := LowerCase(Meta.Anchor);
    FixMode := LowerCase(Meta.FixMode);
    RdxLog('Provide %s %s:%d anchor=%s fixMode=%s quelle=%s',
      [AFinding.ResolvedRuleId, ExtractFileName(AFinding.FileName), Line,
       Anchor, FixMode, BufferSource]);

    Info := TRdxRecipeRunner.DescribeAnchor(FPlaces, Line, Anchor, IsCall, Why);
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
