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
// Gelesen wird nur Pascal-Quelltext (uRdxBufferMath.IsPascalSource): ein
// Fund in einer .dfm, .ini oder .dproj bekommt "reDelphix: nichts
// anzubieten", ohne dass die Datei gelesen wird (Review R1-04 - vorher las
// Provide bis zu 1,8 MB .dfm im Hauptthread fuer genau diese Meldung).
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
// Ebenso bleiben die Zeilen der zuletzt gelesenen Datei stehen, samt ihrer
// Code-Sicht (uRdxCodeMap.TRdxMappedLines, Charge P5): Unterdrueck-Hilfen,
// Planer und Kontext-Laeufer teilen sich EINE Code-Sicht je Text, ueber
// alle Funde eines Menues und die Code-Aktion am Caret (SharedLines); was
// FileReason/IncludeReason auf der Platte sehen, gilt fuer einen
// Menueaufbau (DISK_BATCH_MS, BeginDiskBatch).
//
// WAS ANGEBOTEN WIRD
//
// Die Menuetexte sind englische msgids (CAP_* unten; die der einfachen
// Hilfen in uRdxFixTable, FIX_CAPTIONS; uebersetzt ueber i18n/*.po); hier
// stehen sie deutsch zur Erlaeuterung.
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
//   "(TObject) entfernen"              SCA075 (plant nur auf Zeilen, laeuft
//                                      aber nach dem Oeffnen des Dienstes:
//                                      scheitert der Parse, faellt es weg)
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
  System.Diagnostics,   // TStopwatch (Fenster des Plattenblick-Caches)
  uEngineApi, uRefactorInfo, uMethodd12, uFindingActions,
  uRdxScopeTable,
  uRdxBufferMath,   // TRdxTextSource, SpanFitsEditor
  uRdxCodeMap,      // TRdxMappedLines: Zeilen mit geteilter Code-Sicht (P5)
  uRdxMagicFixes,   // TRdxDiskReasonCache (P5)
  uRdxRecipeRunner;

type
  TRdxActionKind = (akShowSpan, akReplace, akSqlTemplate);

  // Eine Aktion liess sich nicht ausfuehren (Bereich nicht markierbar,
  // Puffer weicht vom Stand beim Menueaufbau ab ...). Message ist der
  // Grund samt Protokollhinweis; der Host zeigt ihn an (Review R1-05,
  // SCA127: bis dahin die Basisklasse Exception).
  ERdxActionFailed = class(Exception);

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
    // ERdxActionFailed zum Host, der sie anzeigt.
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
    FContextToken: Integer;          // Kontext-Anbieter (Charge B), 0 = ab
    FUsesNames   : TArray<string>;   // Namen der uses-Eintraege der Datei
    // Die Zeilen der zuletzt gelesenen Datei samt geteilter Code-Sicht
    // (Charge P5, s. SharedLines): Name, Herkunft und Text, aus dem sie
    // entstanden, und der Aenderungszaehler der Zeilen, als sie entstanden
    // (TRdxMappedLines.Changes - weicht er ab, hat ein Verbraucher sie
    // veraendert, und sie gelten nicht mehr als die des Texts).
    FLines       : TRdxMappedLines;
    FLinesName   : string;
    FLinesFrom   : TRdxTextSource;
    FLinesText   : string;
    FLinesChanges: Integer;
    // Plattenblick je Menueaufbau (Charge P5, s. BeginDiskBatch).
    FDiskCache   : TRdxDiskReasonCache;
    FDiskWatch   : TStopwatch;
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
    // Ein Umbau an der Stelle, kein Fix des Funds (fakRefactor): nie in
    // der Gluehbirne, im Menue je Zeile nur einmal (Review nach Bereichen
    // 2026-10-10, Minor 13/14). AAction = nil: gesperrt mit Grund AHint.
    procedure AddRefactor(var AList: TArray<TFindingAction>;
      const ACaption, AHint: string; AAction: TRdxAction);
    // Baum-Rezepte
    procedure AddShowSpan(var AList: TArray<TFindingAction>;
      const ACtx: TRdxRecipeContext);
    procedure AddFormatCall(var AList: TArray<TFindingAction>;
      const ACtx: TRdxRecipeContext);
    procedure AddSqlTemplate(var AList: TArray<TFindingAction>;
      const ACtx: TRdxRecipeContext);
    procedure AddUsesActions(var AList: TArray<TFindingAction>;
      const ACtx: TRdxRecipeContext);
    // Die einfachen Editorhilfen ueber die Tabelle uRdxFixTable (welche
    // Regeln: TRdxFixTable.Handles; Planer, Hinweis und Menuetext je Zeile)
    // - eine weitere Regel braucht hier kein Rezept.
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
    // Die Zeilen zu AText (Charge P5, Performance): txBuffer - AText als
    // Zeilen; txDisk - die Datei, gelesen wie der Scan (LoadFileSmart), AText
    // wird ihr Text (Vergleichstext der offenen Quelle, Minor 9). Passen
    // Dateiname, Herkunft und Inhalt zu den zuletzt gelieferten Zeilen
    // (Puffer: derselbe Text; Platte: dieselben Zeilen), kommen DIESE samt
    // ihrer schon gebauten Code-Sicht zurueck - ein Menue fragt bis zu
    // MAX_FINDINGS_PER_MENU Funde derselben Datei und die Code-Aktion am
    // Caret, und bis dahin baute jeder Fund die Zeilen neu und die
    // Code-Sicht dreimal (Zeilen-Marker, Datei-Marker, Planer). Die Zeilen
    // gehoeren dem Anbieter und aendert niemand (Rezepte, Planer und
    // Laeufer lesen nur); schreibt doch einer hinein, liefert der naechste
    // Aufruf frische Zeilen (FLinesChanges, kein Treffer mehr). nil, wenn
    // die Datei nicht lesbar ist.
    function SharedLines(const AFileName: string; ASource: TRdxTextSource;
      var AText: string): TStrings;
    // Beginnt ein neuer Menueaufbau (Charge P5)? Ist das Fenster
    // DISK_BATCH_MS seit dem ersten Plattenblick der Charge um, wird der
    // Cache von FileReason/IncludeReason geleert - ein Menueaufbau (die Funde
    // und die Code-Aktion) teilt sich EINEN Plattenblick je Datei.
    procedure BeginDiskBatch;
    // Der Quellstellen-Dienst fuer die Code-Aktion am Caret (C16, "Format()
    // aus Verkettung"): AText (der Puffer) geparst oder - gleicher Name,
    // gleicher Text - der schon offene (TRdxSourceCache, Minor 9). nil,
    // wenn der Parser scheitert; der Grund steht im Protokoll, die anderen
    // Code-Aktionen bleiben. Ein erschoepfter Stapel und EAbort laufen
    // weiter wie in AddTreeActions.
    function ContextPlaces(const AFileName, AText: string): TSourcePlaces;
    // Der Einstieg des Hosts (TFindingActionProvider).
    function Provide(const AFinding: TLeakFinding): TArray<TFindingAction>;
    // Code-Aktionen ohne Fund am Caret (Charge B, TContextActionProvider):
    // nur Pascal-Quelltext, den Text nur aus dem Editor-Puffer (das
    // Kontextmenue gehoert zu einer offenen Datei). Die Platte liest erst
    // "Lokale Konstante einfuehren" fuer einen Kandidaten am Caret:
    // TRdxMagicFixes.FileReason (Projektdateien der Verzeichnisse darueber)
    // und IncludeReason (die Includes der Unit) - wie die Fund-Hilfe SCA014;
    // beide pruefen vorher den Netzpfad (uRdxPaths.IsNetworkPath) und
    // greifen dort nicht auf die Platte zu. "Format() aus Verkettung" (C16)
    // braucht den geparsten Puffer: nur, wenn am Caret eine '+'-Kette
    // stehen kann (TRdxContextRunner.WantsPlaces), oeffnet ContextPlaces
    // den Quellstellen-Dienst - derselbe wie fuer die Funde des Menues.
    // Die Eintraege rechnet uRdxContextRunner, die
    // Menuetexte uRdxFixTable.ContextCaption (gleich denen der Fund-
    // Hilfen, Dedup F2). Kein Kandidat am Caret: keine Aktion, auch keine
    // Diagnose (F4) - Kind setzt die Registry (fakContext).
    function ProvideContext(
      const AContext: TEditorContext): TArray<TFindingAction>;
  public
    // Create baut die Rezeptlisten und den Quellstellen-Dienst; Destroy
    // meldet ab (UnregisterAtHost) und gibt beides frei. Von aussen nur
    // ueber Instance/Shutdown - die Tests erzeugen eigene Anbieter.
    constructor Create;
    destructor Destroy; override;

    // Der eine Anbieter des Pakets: beim ersten Aufruf erzeugt (lazy),
    // danach derselbe; Shutdown gibt ihn frei, ein spaeterer Aufruf erzeugte
    // einen neuen. Einziger Einstieg fuer uRdxRegister.
    class function Instance: TRdxProvider; static;
    // Abmelden und freigeben - aus der finalization von uRdxRegister.
    class procedure Shutdown; static;

    // Meldet Provide an der Registry des SCA-Plugins an (TFindingActions,
    // aus uRdxRegister.Register), seit Charge B auch ProvideContext
    // (RegisterContext); ein zweiter Aufruf meldet nicht doppelt an.
    // Protokolliert die Token und die Groesse der Scope-Tabelle.
    procedure RegisterAtHost;
    // Meldet wieder ab, beide Anbieter (Pflicht vor dem Entladen, s.
    // uRdxRegister); ohne Anmeldung ohne Wirkung. Destroy ruft es selbst.
    procedure UnregisterAtHost;
    // Token der Anmeldung bei TFindingActions, 0 = nicht angemeldet.
    property Token: Integer read FToken;
    // Die Scope-Tabelle fuer 'uses: X -> Scope.X' (gehoert dem Anbieter,
    // geladen im Konstruktor; Count = 0: nichts gefunden).
    property Scopes: TRdxScopeTable read FScopes;
  end;

implementation

uses
  Vcl.Clipbrd,
  uCrashDiag,       // EStackExhausted
  uSCAConsts,       // KindName, fkUnusedSuppression
  uFileTextCache,   // LoadFileSmart: dieselbe Dekodierung wie der Scan
  uRdxText,         // _(): in die reDelphix-Sprache, nie uLocalization (E29)
  uRuleCatalog,
  uRdxFixTable,     // Tabelle der einfachen Hilfen: Planer und Menuetexte
  uRdxContextRunner, // Code-Aktionen ohne Fund am Caret (Charge B)
  uRdxSuppress,
  uRdxEditor,
  uRdxLog;          // Protokoll: DebugView + %TEMP%\reDelphix.log

const
  // Menuetexte ueber _() (Editorhilfen E6): englische msgids, de/fr in
  // i18n/*.po, angezeigt in der reDelphix-Sprache (uRdxText, Entscheid
  // E29: wie die SCA-Oberflaeche oder redelphix.ini [UI] Language). Gruende
  // und Hinweise der Planer kommen schon uebersetzt aus ihren Units
  // (Charge C1 und die Gruppen danach) - hier nie ein zweites _().
  CAP_SHOW     = 'Show location';
  CAP_FORMAT   = 'Build Format() from concatenation';
  CAP_SQL      = 'Copy parameterized template to clipboard';
  CAP_USES_ALL = 'uses: qualify all %d entries';
  CAP_USES     = 'uses: qualify entries';
  // fixMode einer Regel, ausdruecklich abgeschaltet (Minor 5).
  FIX_NONE     = 'none';
  DIAG_PREFIX  = 'reDelphix: ';
  // Fuer das Protokoll (deutsch wie die uebrigen Zeilen).
  SOURCE_NAMES : array[TRdxTextSource] of string =
    ('Editor-Puffer', 'Platte', 'gesperrt');
  OPEN_NAMES   : array[TRdxOpenResult] of string =
    ('', ', neu geparst', ', wiederverwendet');
  // So lange (ms ab dem ersten Plattenblick) gilt ein Ergebnis von
  // FileReason/IncludeReason (Charge P5, BeginDiskBatch): ein Menueaufbau
  // ruft Provide fuer bis zu MAX_FINDINGS_PER_MENU Funde und ProvideContext
  // in einer Schleife; eine Projekt- oder Include-Datei, die in dieser Zeit
  // auf der Platte entsteht oder sich aendert, sieht erst der naechste.
  DISK_BATCH_MS = 2000;

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
        raise ERdxActionFailed.Create(Err);
    akReplace:
      // Alle Ersetzungen auf einmal: geprueft, dann EIN Undo-Schritt.
      if not TRdxEditor.ReplaceSpans(FFileName, FEdits, Err) then
        raise ERdxActionFailed.Create(Err);
    akSqlTemplate:
      Clipboard.AsText := FTemplate;
  else
    // Jede Art hat oben ihren Zweig; eine neue ohne Zweig faellt hier auf,
    // statt still nichts zu tun (SCA168) - der Host zeigt die Meldung.
    raise ERdxActionFailed.Create(DIAG_PREFIX
      + _('action kind %d without execution', [Ord(FKind)]));
  end;
end;

{ TRdxSourceCache }

constructor TRdxSourceCache.Create;
begin
  inherited Create;
  FPlaces := TSourcePlaces.Create;
  // Dieselbe Lexer-Sicht wie die Funde: jeder IDE-Scan laeuft mit
  // TScanRequest.DefaultIfdefDefines (Ein-Zweig, MSWINDOWS/WIN64/UNICODE).
  // In der Doppelzweig-Vorgabe des Dienstes lieferte DeclaredTypeOf fuer
  // '{$IFDEF UNICODE} Msg: string; {$ELSE} Msg: AnsiString; {$ENDIF}'
  // nicht den Typ, mit dem der Fund entstand (Review reDelphiX nach
  // Bereichen 2026-10-10, Minor 4).
  FPlaces.SetIfdefDefines(TScanRequest.DefaultIfdefDefines);
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
  FDiskCache := TRdxDiskReasonCache.Create;
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
  FDiskCache.Free;
  FLines.Free;
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
  if FContextToken = 0 then
    FContextToken := TFindingActions.RegisterContext(ProvideContext);
  RdxLog('registriert, Token %d, Anbieter gesamt %d, Scope-Tabelle %d '
    + 'Eintraege aus %s',
    [FToken, TFindingActions.ProviderCount, FScopes.Count, FScopes.Source]);
  RdxLog('Kontext-Anbieter registriert, Token %d, Kontext-Anbieter gesamt %d',
    [FContextToken, TFindingActions.ContextProviderCount]);
end;

procedure TRdxProvider.UnregisterAtHost;
begin
  if FToken <> 0 then
  begin
    TFindingActions.Unregister(FToken);
    FToken := 0;
  end;
  if FContextToken <> 0 then
  begin
    TFindingActions.Unregister(FContextToken);
    FContextToken := 0;
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
  // Ein lokaler Record ist nicht initialisiert: ChangesBehavior (E2, die
  // Taste fuehrt eine so gekennzeichnete Hilfe nicht ungesehen aus) stuende
  // sonst auf Zufall (Review Welle 1, Bereich D). Default setzt alle Felder,
  // auch Kind auf fakUnset - darum unten AUSDRUECKLICH fakFix.
  A := Default(TFindingAction);
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

procedure TRdxProvider.AddRefactor(var AList: TArray<TFindingAction>;
  const ACaption, AHint: string; AAction: TRdxAction);
begin
  Add(AList, ACaption, AHint, Assigned(AAction), AAction);
  AList[High(AList)].Kind := fakRefactor;
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
    Add(AList, _(CAP_SHOW), Format(_(S_TOO_LONG), [EDITOR_MAX_COLUMN]),
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
  Offer : TRdxSqlOffer;
  Act   : TRdxAction;
begin
  if ACtx.FixMode <> 'assisted' then Exit;
  if ACtx.Info = nil then
  begin
    Add(AList, _(CAP_SQL), ACtx.Why, False, nil);
    Exit;
  end;
  if not TRdxRecipeRunner.SqlTemplate(FSource.Places, ACtx.Lines, ACtx.Info,
       ACtx.IsCall, Offer) then
  begin
    Add(AList, _(CAP_SQL), Offer.Reason, False, nil);
    Exit;
  end;
  Act := NewAction(akSqlTemplate, '');
  Act.FTemplate := Offer.Template;
  Add(AList, _(CAP_SQL), Offer.Hint, True, Act);
end;

// Warum 'uses: ...' fuer die ganze Klausel gesperrt ist (APlan.Block);
// '' bei qbNone. Bis Review R1-05 ein case ohne else in AddUsesActions.
function QualifyBlockReason(const APlan: TRdxQualifyPlan): string;
begin
  case APlan.Block of
    qbNoTable:
      Result := _('Scope table not loaded (unitscopes.txt)');
    qbDirectives:
      Result := Format(_('uses clause contains compiler directives (line %d)'),
        [APlan.BlockLine]);
    qbFpcSwitch:
      Result := _('file with an FPC switch or FPC mode - FPC 3.2 knows no '
        + 'unit scopes');
  else
    Result := '';   // qbNone: nichts gesperrt
  end;
end;

// Warum ein Eintrag nicht qualifiziert wird (AItem.Why <> qwOk). Bei einer
// Projekt-Unit sagt AUnits, ob es eine ist oder ein Netzpfad die Frage
// offen liess (Review R1-02); AUnits = nil: nie gefragt.
function QualifyItemReason(const AItem: TRdxQualifyItem;
  AUnits: TRdxProjectUnits): string;
begin
  case AItem.Why of
    qwOwnUnit:
      begin
        if (AUnits <> nil) and (AUnits.Unreadable <> '') then
          Result := AUnits.UnreadableReason
        else
          Result := Format(_('own unit %s in the project'), [AItem.Short]);
      end;
    qwUnsorts:
      Result := _('the clause would no longer be sorted (new SCA142)');
  else
    Result := AItem.ScopeReason;
  end;
end;

procedure TRdxProvider.AddUsesActions(var AList: TArray<TFindingAction>;
  const ACtx: TRdxRecipeContext);
var
  Plan     : TRdxQualifyPlan;
  Item     : TRdxQualifyItem;
  Act      : TRdxAction;
  FileName : string;
  Units    : TRdxProjectUnits;
begin
  // Die Planung liegt im Laeufer (testbar, ohne ToolsAPI); hier nur die
  // Menuetexte. Nichts ausserhalb einer uses-Klausel - sonst stuende
  // "uses: ..." an jedem Fund der Datei. Das Fenster kennt auch die
  // Programm-Klausel (.dpr/.lpr/library, Review Minor 18) und beginnt auf
  // der Zeile des 'uses' (Minor 19). Ein ausdrueckliches fixMode 'none'
  // der Regel schaltet auch den Umbau auf ihrem Signal ab (Minor 5).
  if ACtx.FixMode = FIX_NONE then Exit;
  FileName := ACtx.FileName;
  // Die Projekt-Units EINMAL je Aufruf und erst, wenn ein Eintrag sie
  // braucht (Review R1-02): QualifyUses fragt fuer jeden aufloesbaren
  // Eintrag aller Klauseln - bis dahin lief dafuer je Eintrag die ganze
  // Projektgruppe ueber die ToolsAPI, auch fuer die Gluehbirne. Ausserhalb
  // einer uses-Klausel fragt niemand, der Index entsteht dann nicht.
  Units := nil;
  try
    Plan := TRdxRecipeRunner.QualifyUses(FSource.Places, FScopes, ACtx.Line,
      function(const AShortName: string): Boolean
      begin
        if Units = nil then
          Units := TRdxEditor.ProjectUnits(FileName);
        Result := Units.Knows(AShortName);
      end);
    if not Plan.InClause then Exit;
    if Plan.Block <> qbNone then
    begin
      AddRefactor(AList, _(CAP_USES), QualifyBlockReason(Plan), nil);
      Exit;
    end;
    for Item in Plan.Items do
      if Item.Why = qwOk then
      begin
        Act := NewAction(akReplace, ACtx.FileName);
        SetLength(Act.FEdits, 1);
        Act.FEdits[0] := Item.Edit;
        AddRefactor(AList, 'uses: ' + Item.Short + ' -> ' + Item.Qualified,
          '', Act);
      end
      else
        AddRefactor(AList, Format(_('uses: qualify %s'), [Item.Short]),
          QualifyItemReason(Item, Units), nil);
    if Length(Plan.All) < 2 then Exit;
    if Plan.AllUnsorts then
      AddRefactor(AList, Format(_(CAP_USES_ALL), [Length(Plan.All)]),
        _('the clause would no longer be sorted (new SCA142)'), nil)
    else
    begin
      Act := NewAction(akReplace, ACtx.FileName);
      Act.FEdits := Plan.All;
      AddRefactor(AList, Format(_(CAP_USES_ALL), [Length(Plan.All)]),
        Plan.AllPreview, Act);
    end;
  finally
    Units.Free;
  end;
end;

procedure TRdxProvider.AddSimpleFix(var AList: TArray<TFindingAction>;
  const ACtx: TRdxRecipeContext);

  // Ein Eintrag zu AOutcome: mit seinen Ersetzungen oder gesperrt mit Grund.
  // Menuetext, Variante und Kennzeichnung (E2) kommen aus der Tabelle;
  // ohne Menuetext kein Eintrag - bis Charge R8 stand dann der interne
  // Name der Art im Menue (uTestRdxFixTable pinnt jede Zeile).
  procedure AddOutcome(const AOutcome: TRdxFixOutcome);
  var
    Caption : string;
    Act     : TRdxAction;
  begin
    Caption := TRdxFixTable.CaptionFor(ACtx.Finding.Kind, AOutcome);
    if Caption = '' then Exit;
    if not AOutcome.Enabled then
      Add(AList, Caption, AOutcome.Reason, False, nil)
    else
    begin
      Act := NewAction(akReplace, ACtx.FileName);
      Act.FEdits := AOutcome.Edits;
      Add(AList, Caption, AOutcome.Hint, True, Act);
    end;
    // E2: Ctrl+Alt+F fuehrt eine solche Hilfe nicht ungesehen aus.
    AList[High(AList)].ChangesBehavior := AOutcome.ChangesBehavior;
  end;

var
  Alt : TRdxFixOutcome;
begin
  // Nur Pascal-Quelltext kommt bis hierher (FindingDiagnosis) - die
  // Gates IsPascalSource in den Rezepten waren seit R1-04 unerreichbar
  // (Wochen-Review 2026-10-21).
  if not TRdxFixTable.Handles(ACtx.Finding.Kind)
     or (ACtx.FixMode = FIX_NONE) then Exit;
  AddOutcome(TRdxFixTable.FixFor(FSource.Places, ACtx.Lines, ACtx.Finding,
    FUsesNames));
  // Zweiter Eintrag derselben Regel (SCA168, SCA020: jeweils mit raise).
  Alt := TRdxFixTable.AlternativeFixFor(FSource.Places, ACtx.Lines,
    ACtx.Finding, FUsesNames);
  if Alt.Variant > 0 then
    AddOutcome(Alt);
end;

procedure TRdxProvider.AddSuppress(var AList: TArray<TFindingAction>;
  const ACtx: TRdxRecipeContext);
var
  E   : TRdxEdit;
  Why : string;
begin
  // Ein wirkungsloser Marker wird entfernt, nicht seinerseits unterdrueckt.
  // Menuetext nur die Aktion, der Marker steht im Hint (Aktionsmenue nach
  // Vorschlag 2, Mock 2b, Nico 2026-10-24: im Untermenue 'Unterdruecken'
  // stehen nur 'Hier unterdruecken' / 'In dieser Datei unterdruecken'; bis
  // dahin 'Suppress here (// noinspection %s)' als ein Menuetext). Der
  // Marker ist Code, kein Text - keine msgid.
  if ACtx.Finding.Kind = fkUnusedSuppression then Exit;
  if TRdxSuppress.LineMarker(ACtx.Lines, ACtx.Line, ACtx.KindName, E, Why) then
  begin
    AddReplace(AList, _('Suppress here'), ACtx.FileName, E, fakSuppress);
    AList[High(AList)].Hint := '// noinspection ' + ACtx.KindName;
  end;
  if TRdxSuppress.FileMarker(ACtx.Lines, ACtx.KindName, E, Why) then
  begin
    AddReplace(AList, _('Suppress in this file'), ACtx.FileName, E,
      fakSuppress);
    AList[High(AList)].Hint := '// noinspection-file ' + ACtx.KindName;
  end;
end;

procedure TRdxProvider.AddRemoveMarker(var AList: TArray<TFindingAction>;
  const ACtx: TRdxRecipeContext);
var
  E   : TRdxEdit;
  Why : string;
begin
  // SCA165: eine echte Hilfe (fakFix) - der Marker unterdrueckt nichts.
  // Lehnt RemoveMarker ab (Mehrarten- oder 'All'-Marker: vielleicht nur
  // unter dem aktuellen Profil wirkungslos; Kommentarzeile als Ziel, die
  // SCA165 nicht prueft), steht der Eintrag gesperrt mit dem Grund da -
  // die Birne zaehlt nur verfuegbare Hilfen. Nur '//'-Marker in Pascal-
  // Quelltext: ein '; noinspection' einer .ini kennt RemoveMarker nicht
  // (Review R1, missed 1) - Provide liest solche Dateien gar nicht
  // (FindingDiagnosis).
  if (ACtx.Finding.Kind <> fkUnusedSuppression)
     or (ACtx.FixMode = FIX_NONE) then Exit;
  if not TRdxSuppress.RemoveMarker(ACtx.Lines, ACtx.Line, E, Why) then
  begin
    Add(AList, _('Remove ineffective suppression marker'), Why, False, nil);
    Exit;
  end;
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
    // noinspection ExceptionTooGeneral
    // Jeder andere Fehler beim Oeffnen kostet nur die Baum-Rezepte dieses
    // Funds (der Dienst schliesst sich dabei selbst, IsOpen = False); er
    // steht als gesperrter Eintrag mit Klasse und Text im Menue.
    on E: Exception do
    begin
      Add(AList, DIAG_PREFIX + 'Parser: ' + E.ClassName + ': ' + E.Message,
        '', False, nil);
      Exit;
    end;
  end;
  ACtx.Info := nil;
  Done := False;
  try
    FUsesNames := TRdxRecipeRunner.UsesNamesOf(FSource.Places);

    // fixMode steht schon im Kontext (Provide, vor allen Rezepten); hier
    // nur noch der Anker der Regel.
    Meta   := TRuleCatalog.GetRuleCanonical(ACtx.Finding.Kind);
    Anchor := LowerCase(Meta.Anchor);
    RdxLog('Provide %s %s:%d anchor=%s fixMode=%s quelle=%s%s',
      [ACtx.Finding.ResolvedRuleId, ExtractFileName(ACtx.FileName), ACtx.Line,
       Anchor, ACtx.FixMode, SOURCE_NAMES[ASource], OPEN_NAMES[Opened]]);

    // Mit Gegenprobe gegen den Fund (Review Minor 20): traegt die
    // Fundzeile nicht mehr Ziel und '+'-Zahl des Funds, ist Info nil und
    // Why nennt den Grund ("Zeile verschoben?"). Nur mit Anker der Regel:
    // ohne ihn beschrieb der Laeufer 'assign-or-call' irgendeine
    // Anweisung der Zeile - 'Stelle zeigen' markierte bei SCA126 auf
    // 'if A <> nil then B := nil;' die Zuweisung (Review nach Bereichen
    // 2026-10-10, Minor 16).
    if Anchor <> '' then
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

// Warum es zum Fund nichts gibt, bevor eine Datei gelesen wird: kein
// Dateiname, keine Zeile - oder kein Pascal-Quelltext (Review R1-04, s.
// Kopf: fuer andere Dateien gibt es kein Rezept, auch kein Text-Rezept,
// missed 1). '' = weiter. Bis R1-05 vier Zweige in Provide. Ob die Datei
// auf der Platte liegt, fragt Provide erst, wenn sie nicht im Editor offen
// ist: FileExists auf einer getrennten Freigabe blockierte sonst JEDEN
// Provide (Gluehbirne je Caret-Zeile, Hauptthread) fuer den SMB-Timeout -
// auch fuer eine offene Datei, deren Puffer die Wahrheit ist
// (Wochen-Review 2026-10-21; gemessen 2,5 bis 16 s, uRdxPaths).
function FindingDiagnosis(const AFinding: TLeakFinding): string;
begin
  if AFinding.FileName = '' then
    Result := _('finding without file name')
  else if AFinding.LineInt < 1 then
    Result := _('finding without line')
  else if not IsPascalSource(AFinding.FileName) then
    Result := _('nothing to offer')
  else
    Result := '';
end;

function TRdxProvider.SharedLines(const AFileName: string;
  ASource: TRdxTextSource; var AText: string): TStrings;
var
  Fresh : TRdxMappedLines;
begin
  // Aus demselben Puffertext entstehen dieselben Zeilen - solange niemand
  // in sie geschrieben hat (Changes; dann gilt wie bei jedem Fehlschlag:
  // neu bauen).
  if (ASource = txBuffer) and Assigned(FLines) and (FLinesFrom = txBuffer)
     and (FLines.Changes = FLinesChanges)
     and SameText(FLinesName, AFileName) and (FLinesText = AText) then
    Exit(FLines);
  Result := nil;
  Fresh := TRdxMappedLines.Create;
  try
    if ASource = txBuffer then
      Fresh.Text := AText
    else
    begin
      // Von der Platte jedes Mal lesen - verglichen werden die Zeilen.
      if not LoadFileSmart(AFileName, Fresh) then Exit;
      AText := Fresh.Text;
      if Assigned(FLines) and (FLinesFrom = txDisk)
         and (FLines.Changes = FLinesChanges)
         and SameText(FLinesName, AFileName) and FLines.Equals(Fresh) then
        Exit(FLines);
    end;
    FLines.Free;
    FLines     := Fresh;
    Fresh      := nil;   // gehoert jetzt dem Anbieter
    FLinesName := AFileName;
    FLinesFrom := ASource;
    FLinesText := AText;
    FLinesChanges := FLines.Changes;   // nach dem Befuellen: der Ausgangsstand
    Result := FLines;
  finally
    Fresh.Free;
  end;
end;

procedure TRdxProvider.BeginDiskBatch;
begin
  if FDiskWatch.IsRunning
     and (FDiskWatch.ElapsedMilliseconds <= DISK_BATCH_MS) then
    Exit;
  FDiskCache.Clear;
  FDiskWatch := TStopwatch.StartNew;
end;

function TRdxProvider.Provide(
  const AFinding: TLeakFinding): TArray<TFindingAction>;
var
  Ctx      : TRdxRecipeContext;
  Text     : string;
  Source   : TRdxTextSource;
  Lines    : TStrings;
  R        : TRdxRecipe;
  Why      : string;
  PrevDisk : TRdxDiskReasonCache;
begin
  Result := nil;
  // Kein FActions.Clear mehr (Stufe B): die Objekte des vorigen Provide
  // haengen womoeglich noch an Menuepunkten desselben Menues - eine neue
  // Charge, die aelteste faellt heraus.
  FActions.BeginBatch;
  FUsesNames := nil;
  if not Assigned(AFinding) then Exit;
  Why := FindingDiagnosis(AFinding);
  if Why <> '' then
  begin
    Add(Result, DIAG_PREFIX + Why, '', False, nil);
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
  if (Source = txDisk) and not FileExists(AFinding.FileName) then
  begin
    Add(Result, DIAG_PREFIX + Format(_('file not found: %s'),
      [AFinding.FileName]), '', False, nil);
    Exit;
  end;
  // Die Zeilen samt Code-Sicht teilen sich alle Rezepte dieses Funds und -
  // bei unveraendertem Text - die folgenden Funde (Charge P5, SharedLines);
  // bei txDisk wird Text der Vergleichstext der offenen Quelle (Minor 9).
  Lines := SharedLines(AFinding.FileName, Source, Text);
  if Lines = nil then
  begin
    Add(Result, DIAG_PREFIX + _('file not readable'), '', False, nil);
    Exit;
  end;
  BeginDiskBatch;
  PrevDisk := TRdxMagicFixes.UseDiskCache(FDiskCache);
  try
    Ctx := Default(TRdxRecipeContext);
    Ctx.Finding  := AFinding;
    Ctx.FileName := AFinding.FileName;
    Ctx.Line     := AFinding.LineInt;
    Ctx.KindName := uSCAConsts.KindName(AFinding.Kind);
    Ctx.Lines    := Lines;
    // fixMode aus dem Katalog vor ALLEN Rezepten: ein ausdrueckliches
    // 'none' sperrt auch die Text-Rezepte (Minor 5), und die brauchen den
    // Baum nicht.
    Ctx.FixMode  := LowerCase(TRuleCatalog.GetRuleCanonical(AFinding.Kind).FixMode);
    // Nur Pascal-Quelltext kommt hier an (s. oben) und durch den Parser -
    // ein Fund in .dfm/.dproj braeuchte sonst Parse-Zeit im UI-Thread und
    // verdraengte die zuletzt geparste .pas aus dem Cache (Review nach
    // Bereichen 2026-10-10, Minor 15).
    AddTreeActions(Result, Ctx, Source, Text);
    for R in FTextRecipes do
      R(Result, Ctx);
    AddDiagnosis(Result, Ctx);
    for R in FSuppressRecipes do
      R(Result, Ctx);
  finally
    TRdxMagicFixes.UseDiskCache(PrevDisk);
  end;
end;


function TRdxProvider.ContextPlaces(const AFileName,
  AText: string): TSourcePlaces;
begin
  Result := nil;
  try
    if FSource.Open(AFileName, txBuffer, AText) <> orFailed then
      Result := FSource.Places;
  except
    on EStackExhausted do raise;
    on EAbort do raise;
    // noinspection ExceptionTooGeneral
    // Wie AddTreeActions: ein Fehler beim Parsen kostet nur die Aktion,
    // die den Baum braucht (der Dienst schliesst sich dabei selbst).
    on E: Exception do
      RdxLog('Kontext %s: Parser %s: %s',
        [ExtractFileName(AFileName), E.ClassName, E.Message]);
  end;
end;

function TRdxProvider.ProvideContext(
  const AContext: TEditorContext): TArray<TFindingAction>;
var
  Text     : string;
  Lines    : TStrings;
  Places   : TSourcePlaces;
  Outcomes : TArray<TRdxContextOutcome>;
  O        : TRdxContextOutcome;
  Caption  : string;
  Act      : TRdxAction;
  PrevDisk : TRdxDiskReasonCache;
begin
  Result := nil;
  if not IsPascalSource(AContext.FileName) then Exit;
  // Eine eigene Charge im Ring (wie je Provide): die Aktionen der Funde
  // desselben Menues bleiben am Leben (RDX_ACTION_BATCHES). Erst hinter der
  // Pascal-Pruefung - ein Rechtsklick in einer .dfm/.dproj soll keine
  // Charge verbrauchen (Review Charge B, Befund 4).
  FActions.BeginBatch;
  // Nur der Puffer: geschrieben wird in ihn, und das Menue haengt an einer
  // offenen Datei. Leer oder nicht lesbar, oder nicht offen: nichts.
  if TRdxEditor.ReadBuffer(AContext.FileName, Text) <> txBuffer then Exit;
  // Dieselben Zeilen samt Code-Sicht wie die Funde desselben Menues, wenn
  // der Puffer unveraendert ist (Charge P5, SharedLines), und derselbe
  // Plattenblick (BeginDiskBatch).
  Lines := SharedLines(AContext.FileName, txBuffer, Text);
  BeginDiskBatch;
  PrevDisk := TRdxMagicFixes.UseDiskCache(FDiskCache);
  try
    // C16: der Baum nur, wenn am Caret eine Kette stehen kann.
    Places := nil;
    if TRdxContextRunner.WantsPlaces(Lines, AContext) then
      Places := ContextPlaces(AContext.FileName, Text);
    Outcomes := TRdxContextRunner.Run(Lines, AContext, Places);
    for O in Outcomes do
    begin
      Caption := TRdxFixTable.ContextCaption(O);
      if Caption = '' then Continue;
      if O.Enabled then
      begin
        Act := NewAction(akReplace, AContext.FileName);
        Act.FEdits := O.Edits;
        Add(Result, Caption, O.Hint, True, Act);
      end
      else
        Add(Result, Caption, O.Reason, False, nil);
      // E2: gekennzeichnet; Kind setzt die Registry (fakContext).
      Result[High(Result)].ChangesBehavior := O.ChangesBehavior;
    end;
  finally
    TRdxMagicFixes.UseDiskCache(PrevDisk);
  end;
  RdxLog('Kontext %s:%d:%d - %d Eintraege',
    [ExtractFileName(AContext.FileName), AContext.Line, AContext.Col,
     Length(Result)]);
end;

end.
