unit uRdxProvider;

// reDelphix - der Anbieter: haengt an Funde des SCA-Plugins Aktionen
// (uFindingActions in SCA.Engine, Konzept_SourceRefactor_Quellstellen
// Abschnitt 15). Je Fund eines Menues wird Provide gerufen; es
// oeffnet die Datei ueber TSourcePlaces (nur lesen, kein Scan), laesst
// den Rezept-Laeufer (uRdxRecipeRunner) die Stellen beschreiben und
// haelt die Daten der Aktionen in TRdxAction-Objekten, bis
// RDX_ACTION_BATCHES neuere Provide-Chargen entstanden sind
// (TRdxObjectRing).
//
// WELCHER TEXT GILT
//
// Ist die Datei im Editor offen, der Editor-Puffer - auch mit
// ungespeicherten Aenderungen; ist der Puffer leer oder nicht lesbar,
// kommt nur "reDelphix: Editor-Puffer leer oder nicht lesbar" und KEIN
// Rueckfall auf die Platte (Review Nit 24). Sonst die Platte wie der Scan.
// Die zuletzt geoeffnete Quelle bleibt offen: gleicher Name, gleiche
// Herkunft, gleicher Text -> kein neuer Parse (Review Minor 9; ein Menue
// fragt bis zu MAX_FINDINGS_PER_MENU Funde, die Gluehbirne jede
// beruhigte Caret-Zeile). Die Fundzeile wird gegen den Fund geprueft
// (Ziel, '+'-Zahl; TRdxRecipeRunner.QueryOf/Describe): steht dort nach
// einer Bearbeitung eine andere Anweisung, entfallen die Baum-Rezepte mit
// dem Grund "Zeile verschoben?" (Review Minor 20).
//
// WAS ANGEBOTEN WIRD
//
//   "Stelle zeigen"                    wenn sich die Anweisung des Funds
//                                      beschreiben laesst (Anker der Regel);
//                                      ausgegraut hinter Spalte 32767
//                                      (SmallInt der Editor-Markierung)
//   "Format() aus Verkettung bilden"   fixMode = auto (SCA044); aktiv nach
//                                      der Kompilat-Regel (uRdxRecipes.
//                                      JudgeOperand); fehlt System.SysUtils,
//                                      wird es eingefuegt; kein SQL
//   "Parametrisierte Vorlage ..."      fixMode = assisted (SCA003); nur in
//                                      die Zwischenablage, nie geschrieben
//   "uses: X -> Scope.X"               Fund liegt in einer uses-Klausel
//                                      (auch der Programm-Klausel einer
//                                      .dpr/.lpr); je unqualifiziertem
//                                      Eintrag der Zeile, dazu "alle n
//                                      Eintraege"
//   "FreeAndNil(X) verwenden"          SCA085; X im Quelltext deklariert,
//                                      System.SysUtils kommt notfalls mit
//   "Assigned() statt Vergleich ..."   SCA126; alle Vergleiche der Anweisung
//   "(TObject) entfernen"              SCA075 (nur Zeilen, ohne Parser)
//   "Unterdruecken ..."                je Fund in Pascal-Quelltext
//                                      (Editorhilfen Stufe 1)
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
// uRdxEditor mit Vergleich gegen den Text, auf dem die Aktion beim
// Menueaufbau beschrieben wurde), meldet keinen Fund und ruft keinen
// Scan. Nach einer Umformung zeigt die Fundliste des Plugins
// den alten Stand, bis der Benutzer die Datei erneut scannt.

interface

uses
  System.SysUtils, System.Classes,
  uEngineApi, uRefactorInfo, uMethodd12, uFindingActions,
  uRdxRecipes, uRdxScopeTable,
  uRdxBufferMath,   // TRdxTextSource, SpanFitsEditor
  uRdxRecipeRunner;

type
  TRdxActionKind = (akShowSpan, akReplace, akSqlTemplate);

  // Ein Menuepunkt samt allem, was Execute braucht. Lebt im Anbieter, bis
  // RDX_ACTION_BATCHES neuere Provide-Chargen entstanden sind (TRdxObjectRing) -
  // nicht nur bis zum naechsten Provide, denn ein Host stellt die
  // Aktionen mehrerer Funde in ein Menue (Stufe B, Konzept Editor-
  // Gluehbirne 2026-10-06). Mehrere Ersetzungen (TRdxEdit aus uRdxBufferMath)
  // prueft uRdxEditor.ReplaceSpans alle gegen den Puffer und schreibt sie
  // dann aufsteigend durch EINEN Writer - ein Undo-Schritt.
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

  TRdxOpenResult = (orFailed, orOpened, orReused);

  // Die zuletzt geoeffnete Quelle des Quellstellen-Dienstes, ueber mehrere
  // Provide-Aufrufe gehalten (Review Minor 9, s. Kopf): bei gleichem
  // Dateinamen, gleicher Herkunft und gleichem Text wird nicht neu geparst.
  TRdxSourceCache = class
  private
    FPlaces : TSourcePlaces;
    FName   : string;
    FOrigin : TRdxTextSource;
    FText   : string;          // genau der geparste bzw. gelesene Text
  public
    constructor Create;
    destructor Destroy; override;
    // txBuffer: AText parsen (TSourcePlaces.OpenSource); txDisk: die Datei
    // (TSourcePlaces.Open, AText ist dann der Vergleichstext, den der
    // Aufrufer von der Platte las); txBlocked: orFailed. orReused, wenn
    // die offene Quelle passt. Wirft, was der Parser wirft - dann ist
    // nichts offen und nichts gemerkt.
    function Open(const AFileName: string; ASource: TRdxTextSource;
      const AText: string): TRdxOpenResult;
    // Schliessen und vergessen - nach einer Ausnahme in einem Rezept.
    procedure Forget;
    // Der Dienst; offen nach Open <> orFailed.
    property Places: TSourcePlaces read FPlaces;
  end;

  TRdxProvider = class
  private
    FActions     : TRdxObjectRing;   // besitzt die TRdxAction-Objekte
    FSource      : TRdxSourceCache;  // offene Quelle (Minor 9)
    FScopes      : TRdxScopeTable;
    FToken       : Integer;
    FUsesNames   : TArray<string>;   // Namen der uses-Eintraege der Datei
    // Die Rezept-Zuordnung: eine neue Hilfe ist ein Rezept mehr in einer
    // der beiden Listen (Konstruktor), nicht ein Zweig mehr in Provide.
    FTreeRecipes : TArray<TRdxRecipe>;   // brauchen den geparsten Quelltext
    FTextRecipes : TArray<TRdxRecipe>;   // brauchen nur die Zeilen
    // Unterdruecken steht im Menue HINTER den Hilfen und hinter der
    // Diagnose "reDelphix: <Grund>", die nur kommt, wenn keine Hilfe da ist.
    FSuppressRecipes : TArray<TRdxRecipe>;
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
    // Editorhilfen Stufe 2a: die einfachen Hilfen (SCA075, SCA085, SCA126)
    // ueber TRdxFixRunner - eine weitere Regel braucht hier kein Rezept.
    procedure AddSimpleFix(var AList: TArray<TFindingAction>;
      const ACtx: TRdxRecipeContext);
    // Text-Rezepte (Editorhilfen Stufe 1)
    procedure AddRemoveMarker(var AList: TArray<TFindingAction>;
      const ACtx: TRdxRecipeContext);
    // Zeilen- und Datei-Marker '// noinspection'.
    procedure AddSuppress(var AList: TArray<TFindingAction>;
      const ACtx: TRdxRecipeContext);
    // Quelltext parsen (oder wiederverwenden), Anker beschreiben,
    // Baum-Rezepte laufen lassen.
    procedure AddTreeActions(var AList: TArray<TFindingAction>;
      var ACtx: TRdxRecipeContext; ASource: TRdxTextSource;
      const AText: string);
    // "reDelphix: <Grund>", wenn bis hierher kein Eintrag entstanden ist -
    // sonst waere "keine Hilfe" nicht von "Anbieter nicht geladen" zu
    // unterscheiden.
    procedure AddDiagnosis(var AList: TArray<TFindingAction>;
      const ACtx: TRdxRecipeContext);
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
  uCrashDiag,       // EStackExhausted
  uSCAConsts,       // KindName, fkUnusedSuppression
  uFileTextCache,   // LoadFileSmart: dieselbe Dekodierung wie der Scan
  uLocalization,
  uRuleCatalog,
  uRdxSuppress,
  uRdxEditor,
  uRdxLog;          // Protokoll: DebugView + %TEMP%\reDelphix.log

const
  // Menuetexte ueber _() (Editorhilfen E6): englische msgids, de/fr in
  // i18n/*.po. Die Gruende aus den reinen Rezept-Units (uRdxRecipes,
  // uRdxRecipeRunner) sind noch deutsch - Pruefstand und Tests pruefen sie
  // woertlich (Nacharbeit im Todo).
  CAP_SHOW     = 'Show location';
  CAP_FORMAT   = 'Build Format() from concatenation';
  CAP_SQL      = 'Copy parameterized template to clipboard';
  CAP_USES_ALL = 'uses: qualify all %d entries';
  CAP_USES     = 'uses: qualify entries';
  CAP_FREENIL  = 'Use FreeAndNil(%s)';
  CAP_ASSIGNED = 'Use Assigned() instead of comparing with nil';
  CAP_TOBJECT  = 'Remove (TObject) from the class declaration';
  DIAG_PREFIX  = 'reDelphix: ';
  // Gleiche msgid wie in uRdxEditor (SelectSpan).
  R_TOO_LONG   = 'Line too long for the editor selection (the editor '
    + 'reaches at most column %d)';
  // Fuer das Protokoll (deutsch wie die uebrigen Zeilen).
  SOURCE_NAMES : array[TRdxTextSource] of string =
    ('Editor-Puffer', 'Platte', 'gesperrt');
  OPEN_NAMES   : array[TRdxOpenResult] of string =
    ('', ', neu geparst', ', wiederverwendet');

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

{ TRdxSourceCache }

constructor TRdxSourceCache.Create;
begin
  inherited Create;
  FPlaces := TSourcePlaces.Create;
end;

destructor TRdxSourceCache.Destroy;
begin
  FPlaces.Free;   // schliesst selbst
  inherited;
end;

function TRdxSourceCache.Open(const AFileName: string;
  ASource: TRdxTextSource; const AText: string): TRdxOpenResult;
var
  Opened : Boolean;
begin
  if FPlaces.IsOpen and SameText(FName, AFileName) and (FOrigin = ASource)
     and (FText = AText) then
    Exit(orReused);
  // Erst vergessen, dann oeffnen: wirft der Parser, ist nichts offen und
  // nichts gemerkt (TSourcePlaces schliesst sich dann selbst).
  Forget;
  if ASource = txBlocked then
    Exit(orFailed);
  if ASource = txBuffer then
    Opened := FPlaces.OpenSource(AFileName, AText)
  else
    Opened := FPlaces.Open(AFileName);
  if not Opened then
    Exit(orFailed);
  FName   := AFileName;
  FOrigin := ASource;
  FText   := AText;
  Result  := orOpened;
end;

procedure TRdxSourceCache.Forget;
begin
  FPlaces.Close;
  FName   := '';
  FOrigin := txDisk;
  FText   := '';
end;

{ TRdxProvider }

constructor TRdxProvider.Create;
begin
  inherited Create;
  // Je Charge die Aktionsobjekte EINES Provide; wie viele am Leben
  // bleiben, steht bei RDX_ACTION_BATCHES (uRdxRecipeRunner).
  FActions := TRdxObjectRing.Create(RDX_ACTION_BATCHES);
  FSource  := TRdxSourceCache.Create;
  FScopes  := TRdxScopeTable.Create;
  FScopes.LoadDefault;   // False = keine Tabelle; uses-Aktionen sagen das
  // Reihenfolge = Reihenfolge im Menue.
  SetLength(FTreeRecipes, 5);
  FTreeRecipes[0] := AddShowSpan;
  FTreeRecipes[1] := AddFormatCall;
  FTreeRecipes[2] := AddSqlTemplate;
  FTreeRecipes[3] := AddUsesActions;
  FTreeRecipes[4] := AddSimpleFix;
  SetLength(FTextRecipes, 1);
  FTextRecipes[0] := AddRemoveMarker;
  SetLength(FSuppressRecipes, 1);
  FSuppressRecipes[0] := AddSuppress;
end;

destructor TRdxProvider.Destroy;
begin
  UnregisterAtHost;
  FScopes.Free;
  FSource.Free;
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
  // Die Editor-Markierung rechnet in SmallInt-Spalten (Review Nit 8):
  // weiter rechts wird die Stelle nicht angeboten, sondern begruendet.
  if not SpanFitsEditor(ACtx.Lines, ACtx.Info.Span) then
  begin
    Add(AList, _(CAP_SHOW), Format(_(R_TOO_LONG), [EDITOR_MAX_COLUMN]),
      False, nil);
    AList[High(AList)].Kind := fakNavigate;
    Exit;
  end;
  Act := NewAction(akShowSpan, ACtx.FileName);
  Act.FSpan := ACtx.Info.Span;
  Add(AList, _(CAP_SHOW), Format(_('Line %d:%d to %d:%d'),
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
  Outcome := TRdxRecipeRunner.FormatRewrite(FSource.Places, ACtx.Info, ACtx.Why,
    FUsesNames);
  if not Outcome.Enabled then
  begin
    Add(AList, _(CAP_FORMAT), Outcome.Reason, False, nil);
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
  Add(AList, _(CAP_FORMAT), Outcome.Hint, True, Act);
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
    Add(AList, _(CAP_SQL), ACtx.Why, False, nil);
    Exit;
  end;
  if not TRdxRecipeRunner.SqlTemplate(FSource.Places, ACtx.Info, ACtx.IsCall,
       Template, Hint, Reason) then
  begin
    Add(AList, _(CAP_SQL), Reason, False, nil);
    Exit;
  end;
  Act := NewAction(akSqlTemplate, '');
  Act.FTemplate := Template;
  Add(AList, _(CAP_SQL), Hint, True, Act);
end;

procedure TRdxProvider.AddUsesActions(var AList: TArray<TFindingAction>;
  const ACtx: TRdxRecipeContext);
var
  Entries : TArray<TRefactorSpan>;
  i       : Integer;
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
  // Das Fenster kennt auch die Programm-Klausel (.dpr/.lpr/library,
  // Review Minor 18) und beginnt auf der Zeile des 'uses', nicht eine
  // davor (Minor 19).
  if not TRdxRecipeRunner.LineInUsesClause(FSource.Places, ACtx.Line) then Exit;

  if FScopes.Count = 0 then
  begin
    Add(AList, _(CAP_USES),
      _('Scope table not loaded (unitscopes.txt)'), False, nil);
    Exit;
  end;
  // Direktiven in einer Klausel: ein Eintrag kann in einem Zweig fuer ein
  // anderes Ziel stehen ('{$IFDEF FPC}LCLIntf,{$ELSE}Windows,{$ENDIF}') -
  // qualifiziert uebersetzte FPC ihn nicht mehr (Review Major 7; dieselbe
  // Sperre wie PlanUses).
  DirLine := TRdxRecipeRunner.UsesDirectiveLine(FSource.Places);
  if DirLine > 0 then
  begin
    Add(AList, _(CAP_USES),
      Format(_('uses clause contains compiler directives (line %d)'), [DirLine]),
      False, nil);
    Exit;
  end;

  Entries := FSource.Places.UsesEntries(TUsesSection.usAny);
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
      Reason := Format(_('own unit %s in the project'), [Short]);
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
      Add(AList, Format(_('uses: qualify %s'), [Short]), Reason, False, nil);
  end;
  if Length(All) >= 2 then
  begin
    Act := NewAction(akReplace, ACtx.FileName);
    Act.FEdits := All;
    if Length(All) > 3 then Preview := Preview + ', ...';
    Add(AList, Format(_(CAP_USES_ALL), [Length(All)]), Preview, True, Act);
  end;
end;

// Menuetext einer einfachen Hilfe; AName ist X bei SCA085 ('' wenn der
// Planer abgelehnt hat, bevor X feststand).
function SimpleFixCaption(AKind: TFindingKind; const AName: string): string;
var
  N : string;
begin
  N := AName;
  if N = '' then N := 'X';
  case AKind of
    fkFreeAndNilHint:
      Result := Format(_(CAP_FREENIL), [N]);
    fkNilComparison:
      Result := _(CAP_ASSIGNED);
    fkExplicitTObjectInheritance:
      Result := _(CAP_TOBJECT);
  else
    Result := uSCAConsts.KindName(AKind);
  end;
end;

procedure TRdxProvider.AddSimpleFix(var AList: TArray<TFindingAction>;
  const ACtx: TRdxRecipeContext);
var
  O       : TRdxFixOutcome;
  Caption : string;
  Act     : TRdxAction;
begin
  if not TRdxFixRunner.Handles(ACtx.Finding.Kind)
     or not IsPascalSource(ACtx.FileName) then Exit;
  O := TRdxFixRunner.FixFor(FSource.Places, ACtx.Lines, ACtx.Finding,
    FUsesNames);
  Caption := SimpleFixCaption(ACtx.Finding.Kind, O.Name);
  if not O.Enabled then
  begin
    Add(AList, Caption, O.Reason, False, nil);
    Exit;
  end;
  Act := NewAction(akReplace, ACtx.FileName);
  Act.FEdits := O.Edits;
  Add(AList, Caption, O.Hint, True, Act);
end;

procedure TRdxProvider.AddSuppress(var AList: TArray<TFindingAction>;
  const ACtx: TRdxRecipeContext);
var
  E   : TRdxEdit;
  Why : string;
begin
  // Ein wirkungsloser Marker wird entfernt, nicht seinerseits unterdrueckt.
  if (ACtx.Finding.Kind = fkUnusedSuppression)
     or not IsPascalSource(ACtx.FileName) then Exit;
  if TRdxSuppress.LineMarker(ACtx.Lines, ACtx.Line, ACtx.KindName, E, Why) then
    AddReplace(AList, Format(_('Suppress here (// noinspection %s)'),
      [ACtx.KindName]), ACtx.FileName, E, fakSuppress);
  if TRdxSuppress.FileMarker(ACtx.Lines, ACtx.KindName, E, Why) then
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
  var ACtx: TRdxRecipeContext; ASource: TRdxTextSource; const AText: string);
var
  Meta   : TRuleMeta;
  Anchor : string;
  Opened : TRdxOpenResult;
  R      : TRdxRecipe;
  Done   : Boolean;
begin
  try
    // Der EDITOR-PUFFER ist die Wahrheit, wenn die Datei offen ist: nur
    // dann passen die beschriebenen Bereiche zu dem Text, in den nachher
    // geschrieben wird (ungespeicherte Aenderungen!). Sonst die Platte.
    Opened := FSource.Open(ACtx.FileName, ASource, AText);
    if Opened = orFailed then
    begin
      Add(AList, DIAG_PREFIX + _('file not readable'), '', False, nil);
      Exit;
    end;
  except
    // Ein erschoepfter Stapel (tiefe Parser-Rekursion) wird nie
    // verschluckt (uCrashDiag, Review Minor 33) - der Host reicht ihn
    // weiter; EAbort ebenso (Projektregel).
    on EStackExhausted do raise;
    on EAbort do raise;
    on E: Exception do
    begin
      Add(AList, DIAG_PREFIX + 'Parser: ' + E.Message, '', False, nil);
      Exit;
    end;
  end;
  ACtx.Info := nil;
  Done := False;
  try
    FUsesNames := TRdxRecipeRunner.UsesNamesOf(FSource.Places);

    Meta         := TRuleCatalog.GetRuleCanonical(ACtx.Finding.Kind);
    Anchor       := LowerCase(Meta.Anchor);
    ACtx.FixMode := LowerCase(Meta.FixMode);
    RdxLog('Provide %s %s:%d anchor=%s fixMode=%s quelle=%s%s',
      [ACtx.Finding.ResolvedRuleId, ExtractFileName(ACtx.FileName), ACtx.Line,
       Anchor, ACtx.FixMode, SOURCE_NAMES[ASource], OPEN_NAMES[Opened]]);

    // Mit Gegenprobe gegen den Fund (Review Minor 20): traegt die
    // Fundzeile nicht mehr Ziel und '+'-Zahl des Funds, ist Info nil und
    // Why nennt den Grund ("Zeile verschoben?").
    ACtx.Info := TRdxRecipeRunner.Describe(FSource.Places,
      TRdxRecipeRunner.QueryOf(ACtx.Finding, Anchor), ACtx.IsCall, ACtx.Why);
    for R in FTreeRecipes do
      R(AList, ACtx);
    Done := True;
  finally
    FreeAndNil(ACtx.Info);   // alles Noetige ist in die Aktionen kopiert
    // Die Quelle bleibt fuer den naechsten Fund offen (Minor 9) - ausser
    // ein Rezept ist mit einer Ausnahme ausgestiegen: die faul gebauten
    // Teile des Dienstes (Typen, Scope-Fakten) koennten dann halb stehen.
    if not Done then
      FSource.Forget;
  end;
end;

procedure TRdxProvider.AddDiagnosis(var AList: TArray<TFindingAction>;
  const ACtx: TRdxRecipeContext);
begin
  if Length(AList) > 0 then Exit;
  if ACtx.Why <> '' then
    Add(AList, DIAG_PREFIX + ACtx.Why, '', False, nil)
  else if ACtx.FixMode = '' then
    Add(AList, DIAG_PREFIX + Format(_('%s: no fixMode in the rule catalog'),
      [ACtx.Finding.ResolvedRuleId]), '', False, nil)
  else
    Add(AList, DIAG_PREFIX + _('nothing to offer'), '', False, nil);
end;

function TRdxProvider.Provide(
  const AFinding: TLeakFinding): TArray<TFindingAction>;
var
  Ctx    : TRdxRecipeContext;
  Text   : string;
  Source : TRdxTextSource;
  Lines  : TStringList;
  R      : TRdxRecipe;
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
    Add(Result, DIAG_PREFIX + _('finding without file name'), '', False, nil);
    Exit;
  end;
  if not FileExists(AFinding.FileName) then
  begin
    Add(Result, DIAG_PREFIX + Format(_('file not found: %s'),
      [AFinding.FileName]), '', False, nil);
    Exit;
  end;
  if AFinding.LineInt < 1 then
  begin
    Add(Result, DIAG_PREFIX + _('finding without line'), '', False, nil);
    Exit;
  end;
  // Den Text EINMAL lesen - Puffer, sonst Platte wie der Scan. Offen, aber
  // leer oder nicht lesbar: kein Rueckfall auf die Platte (Review Nit 24),
  // die Aktionen schrieben in genau diesen Puffer.
  Source := TRdxEditor.ReadBuffer(AFinding.FileName, Text);
  if Source = txBlocked then
  begin
    Add(Result, DIAG_PREFIX + _('editor buffer empty or not readable'), '',
      False, nil);
    Exit;
  end;
  Lines := TStringList.Create;
  try
    if Source = txBuffer then
      Lines.Text := Text
    else if LoadFileSmart(AFinding.FileName, Lines) then
      Text := Lines.Text   // Vergleichstext fuer die offene Quelle (Minor 9)
    else
    begin
      Add(Result, DIAG_PREFIX + _('file not readable'), '', False, nil);
      Exit;
    end;
    Ctx := Default(TRdxRecipeContext);
    Ctx.Finding  := AFinding;
    Ctx.FileName := AFinding.FileName;
    Ctx.Line     := AFinding.LineInt;
    Ctx.KindName := uSCAConsts.KindName(AFinding.Kind);
    Ctx.Lines    := Lines;
    AddTreeActions(Result, Ctx, Source, Text);
    for R in FTextRecipes do
      R(Result, Ctx);
    AddDiagnosis(Result, Ctx);
    for R in FSuppressRecipes do
      R(Result, Ctx);
  finally
    Lines.Free;
  end;
end;

end.
