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
  System.SysUtils, System.Classes,
  uEngineApi, uRefactorInfo, uMethodd12, uFindingActions,
  uRdxRecipes, uRdxScopeTable, uRdxRecipeRunner;

type
  TRdxActionKind = (akShowSpan, akReplace, akSqlTemplate);

  // Ein Menuepunkt samt allem, was Execute braucht. Lebt im Anbieter, bis
  // RDX_ACTION_BATCHES neuere Provide-Chargen entstanden sind (TRdxObjectRing) -
  // nicht nur bis zum naechsten Provide, denn ein Host stellt die
  // Aktionen mehrerer Funde in ein Menue (Stufe B, Konzept Editor-
  // Gluehbirne 2026-10-06). Mehrere Ersetzungen (TRdxEdit aus uRdxBufferMath)
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

  // Was ein Rezept ueber den Fund weiss (Editorhilfen Stufe 0, Rezept-
  // Zuordnung). Baum-Rezepte bekommen Info/IsCall/Why aus dem geparsten
  // Quelltext; Text-Rezepte brauchen nur die Zeilen.
  TRdxRecipeContext = record
    Finding  : TLeakFinding;
    FileName : string;
    Line     : Integer;
    KindName : string;           // Name der Art fuer '// noinspection'
    FixMode  : string;           // aus dem Regelkatalog, klein
    Lines    : TStrings;         // Text der Datei: Editor-Puffer oder Platte
    Info     : TRefactorInfo;    // nil ohne Anker
    IsCall   : Boolean;
    Why      : string;
  end;

  // Ein Rezept haengt seine Aktionen an AList an - oder keine.
  TRdxRecipe = procedure(var AList: TArray<TFindingAction>;
    const ACtx: TRdxRecipeContext) of object;

  TRdxProvider = class
  private
    FActions     : TRdxObjectRing;   // besitzt die TRdxAction-Objekte
    FPlaces      : TSourcePlaces;
    FScopes      : TRdxScopeTable;
    FToken       : Integer;
    FUsesNames   : TArray<string>;   // Namen der uses-Eintraege der Datei
    // Die Rezept-Zuordnung: eine neue Hilfe ist ein Rezept mehr in einer
    // der beiden Listen (Konstruktor), nicht ein Zweig mehr in Provide.
    FTreeRecipes : TArray<TRdxRecipe>;   // brauchen den geparsten Quelltext
    FTextRecipes : TArray<TRdxRecipe>;   // brauchen nur die Zeilen
    function NewAction(AKind: TRdxActionKind;
      const AFileName: string): TRdxAction;
    procedure Add(var AList: TArray<TFindingAction>;
      const ACaption, AHint: string; AEnabled: Boolean; AAction: TRdxAction);
    // Eine Ersetzung als Aktion der Art AKind (ohne Hinweistext).
    procedure AddReplace(var AList: TArray<TFindingAction>;
      const ACaption, AFileName: string; const AEdit: TRdxEdit;
      AKind: TFindingActionKind);
    // Baum-Rezepte
    procedure AddShowSpan(var AList: TArray<TFindingAction>;
      const ACtx: TRdxRecipeContext);
    procedure AddFormatCall(var AList: TArray<TFindingAction>;
      const ACtx: TRdxRecipeContext);
    procedure AddSqlTemplate(var AList: TArray<TFindingAction>;
      const ACtx: TRdxRecipeContext);
    procedure AddUsesActions(var AList: TArray<TFindingAction>;
      const ACtx: TRdxRecipeContext);
    // Text-Rezepte (Editorhilfen Stufe 1)
    procedure AddSuppressLine(var AList: TArray<TFindingAction>;
      const ACtx: TRdxRecipeContext);
    procedure AddSuppressFile(var AList: TArray<TFindingAction>;
      const ACtx: TRdxRecipeContext);
    procedure AddRemoveMarker(var AList: TArray<TFindingAction>;
      const ACtx: TRdxRecipeContext);
    // Quelltext parsen, Anker beschreiben, Baum-Rezepte laufen lassen.
    procedure AddTreeActions(var AList: TArray<TFindingAction>;
      var ACtx: TRdxRecipeContext; AFromBuffer: Boolean; const AText: string);
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
  uSCAConsts,       // KindName, fkUnusedSuppression
  uFileTextCache,   // LoadFileSmart: dieselbe Dekodierung wie der Scan
  uLocalization,
  uRuleCatalog,
  uRdxSuppress,
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

{ TRdxAction }

procedure TRdxAction.Execute(Sender: TObject);
var
  Err : string;
begin
  case FKind of
    akShowSpan:
      if not TRdxEditor.SelectSpan(FFileName, FSpan, Err) then
        raise Exception.Create(Err);
    akReplace:
      // Alle Ersetzungen auf einmal: geprueft, dann EIN Undo-Schritt.
      if not TRdxEditor.ReplaceSpans(FFileName, FEdits, Err) then
        raise Exception.Create(Err);
    akSqlTemplate:
      Clipboard.AsText := FTemplate;
  end;
end;

{ TRdxProvider }

constructor TRdxProvider.Create;
begin
  inherited Create;
  // Je Charge die Aktionsobjekte EINES Provide; wie viele am Leben
  // bleiben, steht bei RDX_ACTION_BATCHES (uRdxRecipeRunner).
  FActions := TRdxObjectRing.Create(RDX_ACTION_BATCHES);
  FPlaces  := TSourcePlaces.Create;
  FScopes  := TRdxScopeTable.Create;
  FScopes.LoadDefault;   // False = keine Tabelle; uses-Aktionen sagen das
  // Reihenfolge = Reihenfolge im Menue.
  SetLength(FTreeRecipes, 4);
  FTreeRecipes[0] := AddShowSpan;
  FTreeRecipes[1] := AddFormatCall;
  FTreeRecipes[2] := AddSqlTemplate;
  FTreeRecipes[3] := AddUsesActions;
  SetLength(FTextRecipes, 3);
  FTextRecipes[0] := AddRemoveMarker;
  FTextRecipes[1] := AddSuppressLine;
  FTextRecipes[2] := AddSuppressFile;
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
  A.Kind    := fakFix;   // AddShowSpan stellt danach auf fakNavigate
  if Assigned(AAction) then
    A.Execute := AAction.Execute
  else
    A.Execute := nil;
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := A;
end;

procedure TRdxProvider.AddReplace(var AList: TArray<TFindingAction>;
  const ACaption, AFileName: string; const AEdit: TRdxEdit;
  AKind: TFindingActionKind);
var
  Act : TRdxAction;
begin
  Act := NewAction(akReplace, AFileName);
  SetLength(Act.FEdits, 1);
  Act.FEdits[0] := AEdit;
  Add(AList, ACaption, '', True, Act);
  AList[High(AList)].Kind := AKind;
end;

// Nur Pascal-Quelltext traegt '//'-Marker (DFM-Funde nicht).
function IsPascalSource(const AFileName: string): Boolean;
var
  Ext : string;
begin
  Ext := LowerCase(ExtractFileExt(AFileName));
  Result := (Ext = '.pas') or (Ext = '.dpr') or (Ext = '.dpk')
    or (Ext = '.inc') or (Ext = '.lpr') or (Ext = '.pp');
end;

procedure TRdxProvider.AddShowSpan(var AList: TArray<TFindingAction>;
  const ACtx: TRdxRecipeContext);
var
  Act : TRdxAction;
begin
  if not Assigned(ACtx.Info) or not ACtx.Info.Span.IsValid then Exit;
  Act := NewAction(akShowSpan, ACtx.FileName);
  Act.FSpan := ACtx.Info.Span;
  Add(AList, CAP_SHOW, Format('Zeile %d:%d bis %d:%d',
    [ACtx.Info.Span.StartLine, ACtx.Info.Span.StartCol,
     ACtx.Info.Span.EndLine, ACtx.Info.Span.EndCol - 1]), True, Act);
  // Fuehrt nur hin - die Gluehbirne im Editor laesst das weg, der
  // Benutzer steht dort schon an der Stelle.
  AList[High(AList)].Kind := fakNavigate;
end;

procedure TRdxProvider.AddFormatCall(var AList: TArray<TFindingAction>;
  const ACtx: TRdxRecipeContext);
var
  Outcome : TRdxFormatOutcome;
  Act     : TRdxAction;
begin
  if ACtx.FixMode <> 'auto' then Exit;
  Outcome := TRdxRecipeRunner.FormatRewrite(FPlaces, ACtx.Info, ACtx.Why,
    FUsesNames);
  if not Outcome.Enabled then
  begin
    Add(AList, CAP_FORMAT, Outcome.Reason, False, nil);
    Exit;
  end;
  Act := NewAction(akReplace, ACtx.FileName);
  SetLength(Act.FEdits, 1);
  Act.FEdits[0].Span     := Outcome.Span;
  Act.FEdits[0].Expected := Outcome.Expected;
  Act.FEdits[0].NewText  := Outcome.NewText;
  if Outcome.NeedsUses then
  begin
    // Zweite Ersetzung: System.SysUtils in die uses-Klausel. Die
    // Reihenfolge ist gleichgueltig - ReplaceSpans sortiert selbst.
    SetLength(Act.FEdits, 2);
    Act.FEdits[1] := Outcome.UsesEdit;
  end;
  Add(AList, CAP_FORMAT, Outcome.Hint, True, Act);
end;

procedure TRdxProvider.AddSqlTemplate(var AList: TArray<TFindingAction>;
  const ACtx: TRdxRecipeContext);
var
  Template, Hint, Reason : string;
  Act : TRdxAction;
begin
  if ACtx.FixMode <> 'assisted' then Exit;
  if ACtx.Info = nil then
  begin
    Add(AList, CAP_SQL, ACtx.Why, False, nil);
    Exit;
  end;
  if not TRdxRecipeRunner.SqlTemplate(FPlaces, ACtx.Info, ACtx.IsCall,
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
  const ACtx: TRdxRecipeContext);
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
  DirLine : Integer;
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
    if (ACtx.Line >= Lo) and (ACtx.Line <= Hi) then InUses := True;
  end;
  if not InUses then Exit;

  if FScopes.Count = 0 then
  begin
    Add(AList, 'uses: Eintraege qualifizieren',
      'Scope-Tabelle nicht geladen (unitscopes.txt)', False, nil);
    Exit;
  end;
  // Direktiven in einer Klausel: ein Eintrag kann in einem Zweig fuer ein
  // anderes Ziel stehen ('{$IFDEF FPC}LCLIntf,{$ELSE}Windows,{$ENDIF}') -
  // qualifiziert uebersetzte FPC ihn nicht mehr (Review Major 7; dieselbe
  // Sperre wie PlanUses).
  DirLine := TRdxRecipeRunner.UsesDirectiveLine(FPlaces);
  if DirLine > 0 then
  begin
    Add(AList, 'uses: Eintraege qualifizieren',
      Format('uses-Klausel traegt Compiler-Direktiven (Zeile %d)', [DirLine]),
      False, nil);
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
    if OK and TRdxEditor.ProjectHasUnit(Short, ACtx.FileName) then
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
    if Entries[i].StartLine <> ACtx.Line then Continue;
    if OK then
    begin
      Act := NewAction(akReplace, ACtx.FileName);
      SetLength(Act.FEdits, 1);
      Act.FEdits[0] := E;
      Add(AList, 'uses: ' + Short + ' -> ' + Q, '', True, Act);
    end
    else
      Add(AList, 'uses: ' + Short + ' qualifizieren', Reason, False, nil);
  end;
  if Length(All) >= 2 then
  begin
    Act := NewAction(akReplace, ACtx.FileName);
    Act.FEdits := All;
    if Length(All) > 3 then Preview := Preview + ', ...';
    Add(AList, Format(CAP_USES_ALL, [Length(All)]), Preview, True, Act);
  end;
end;

procedure TRdxProvider.AddSuppressLine(var AList: TArray<TFindingAction>;
  const ACtx: TRdxRecipeContext);
var
  E   : TRdxEdit;
  Why : string;
begin
  // Ein wirkungsloser Marker wird entfernt, nicht seinerseits unterdrueckt.
  if (ACtx.Finding.Kind = fkUnusedSuppression)
     or not IsPascalSource(ACtx.FileName) then Exit;
  if not TRdxSuppress.LineMarker(ACtx.Lines, ACtx.Line, ACtx.KindName, E, Why) then
    Exit;
  AddReplace(AList, Format(_('Suppress here (// noinspection %s)'),
    [ACtx.KindName]), ACtx.FileName, E, fakSuppress);
end;

procedure TRdxProvider.AddSuppressFile(var AList: TArray<TFindingAction>;
  const ACtx: TRdxRecipeContext);
var
  E   : TRdxEdit;
  Why : string;
begin
  if (ACtx.Finding.Kind = fkUnusedSuppression)
     or not IsPascalSource(ACtx.FileName) then Exit;
  if not TRdxSuppress.FileMarker(ACtx.Lines, ACtx.KindName, E, Why) then
    Exit;
  AddReplace(AList, Format(_('Suppress in this file (// noinspection-file %s)'),
    [ACtx.KindName]), ACtx.FileName, E, fakSuppress);
end;

procedure TRdxProvider.AddRemoveMarker(var AList: TArray<TFindingAction>;
  const ACtx: TRdxRecipeContext);
var
  E   : TRdxEdit;
  Why : string;
begin
  // SCA165: eine echte Hilfe (fakFix) - der Marker unterdrueckt nichts.
  if ACtx.Finding.Kind <> fkUnusedSuppression then Exit;
  if not TRdxSuppress.RemoveMarker(ACtx.Lines, ACtx.Line, E, Why) then
    Exit;
  AddReplace(AList, _('Remove ineffective suppression marker'),
    ACtx.FileName, E, fakFix);
end;

procedure TRdxProvider.AddTreeActions(var AList: TArray<TFindingAction>;
  var ACtx: TRdxRecipeContext; AFromBuffer: Boolean; const AText: string);
var
  Meta   : TRuleMeta;
  Anchor : string;
  Opened : Boolean;
  R      : TRdxRecipe;
  Source : string;
begin
  try
    // Der EDITOR-PUFFER ist die Wahrheit, wenn die Datei offen ist: nur
    // dann passen die beschriebenen Bereiche zu dem Text, in den nachher
    // geschrieben wird (ungespeicherte Aenderungen!). Sonst die Platte.
    if AFromBuffer then
    begin
      Source := 'Editor-Puffer';
      Opened := FPlaces.OpenSource(ACtx.FileName, AText);
    end
    else
    begin
      Source := 'Platte';
      Opened := FPlaces.Open(ACtx.FileName);
    end;
    if not Opened then
    begin
      Add(AList, DIAG_PREFIX + 'Datei nicht lesbar', '', False, nil);
      Exit;
    end;
  except
    on E: Exception do
    begin
      Add(AList, DIAG_PREFIX + 'Parser: ' + E.Message, '', False, nil);
      Exit;
    end;
  end;
  ACtx.Info := nil;
  try
    FUsesNames := TRdxRecipeRunner.UsesNamesOf(FPlaces);

    Meta         := TRuleCatalog.GetRuleCanonical(ACtx.Finding.Kind);
    Anchor       := LowerCase(Meta.Anchor);
    ACtx.FixMode := LowerCase(Meta.FixMode);
    RdxLog('Provide %s %s:%d anchor=%s fixMode=%s quelle=%s',
      [ACtx.Finding.ResolvedRuleId, ExtractFileName(ACtx.FileName), ACtx.Line,
       Anchor, ACtx.FixMode, Source]);

    ACtx.Info := TRdxRecipeRunner.DescribeAnchor(FPlaces, ACtx.Line, Anchor,
      ACtx.IsCall, ACtx.Why);
    for R in FTreeRecipes do
      R(AList, ACtx);

    if Length(AList) = 0 then
    begin
      if ACtx.Why <> '' then
        Add(AList, DIAG_PREFIX + ACtx.Why, '', False, nil)
      else if ACtx.FixMode = '' then
        Add(AList, DIAG_PREFIX + ACtx.Finding.ResolvedRuleId
          + ': kein fixMode im Regelkatalog', '', False, nil)
      else
        Add(AList, DIAG_PREFIX + 'nichts anzubieten', '', False, nil);
    end;
  finally
    FreeAndNil(ACtx.Info);   // alles Noetige ist in die Aktionen kopiert
    FPlaces.Close;
  end;
end;

function TRdxProvider.Provide(
  const AFinding: TLeakFinding): TArray<TFindingAction>;
var
  Ctx        : TRdxRecipeContext;
  Text       : string;
  FromBuffer : Boolean;
  Lines      : TStringList;
  R          : TRdxRecipe;
begin
  Result := nil;
  // Kein FActions.Clear mehr (Stufe B): die Objekte des vorigen Provide
  // haengen womoeglich noch an Menuepunkten desselben Menues - eine neue
  // Charge, die aelteste faellt heraus.
  FActions.BeginBatch;
  FUsesNames := nil;
  if not Assigned(AFinding) then Exit;
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
  if AFinding.LineInt < 1 then
  begin
    Add(Result, DIAG_PREFIX + 'Fund ohne Zeile', '', False, nil);
    Exit;
  end;
  Lines := TStringList.Create;
  try
    // Den Text EINMAL lesen - Puffer, sonst Platte wie der Scan.
    FromBuffer := TRdxEditor.TryReadBuffer(AFinding.FileName, Text);
    if FromBuffer then
      Lines.Text := Text
    else if not LoadFileSmart(AFinding.FileName, Lines) then
    begin
      Add(Result, DIAG_PREFIX + 'Datei nicht lesbar', '', False, nil);
      Exit;
    end;
    Ctx := Default(TRdxRecipeContext);
    Ctx.Finding  := AFinding;
    Ctx.FileName := AFinding.FileName;
    Ctx.Line     := AFinding.LineInt;
    Ctx.KindName := uSCAConsts.KindName(AFinding.Kind);
    Ctx.Lines    := Lines;
    AddTreeActions(Result, Ctx, FromBuffer, Text);
    for R in FTextRecipes do
      R(Result, Ctx);
  finally
    Lines.Free;
  end;
end;

end.
