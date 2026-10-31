unit uRdxProvider;

// reDelphix - der Anbieter: haengt an Funde des SCA-Plugins Aktionen
// (uFindingActions in SCA.Engine, Konzept_SourceRefactor_Quellstellen
// Abschnitt 15). Je Fund eines Menues wird Provide gerufen; es liest den
// Text (Editor-Puffer oder Platte), laesst den Kern (uRdxActionCore) die
// Eintraege beschreiben und haelt die Daten der Aktionen in
// TRdxAction-Objekten, bis RDX_ACTION_BATCHES neuere Provide-Chargen
// entstanden sind (TRdxObjectRing).
//
// KERN UND ANBIETER (Entscheid E3, 2026-10-28)
//
// Was zu einem Fund angeboten wird - Rezepte, Reihenfolge, Gruende,
// Ersetzungen -, rechnet TRdxActionCore ohne ToolsAPI und VCL; dieselbe
// Unit fragt die Realworld-Probe tools\probe\RdxActionProbe. Hier bleibt,
// was nur die IDE kann: den Text lesen (uRdxEditor.ReadBuffer, sonst die
// Platte), die Projekt-Units ueber die ToolsAPI (TRdxEditor.ProjectUnits,
// Lieferant des Kerns), die Aktionsobjekte samt Ausfuehrung (Ersetzen im
// Puffer, Markieren, Zwischenablage), der Plattenblick je Menueaufbau und
// die Code-Aktionen ohne Fund (ProvideContext).
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
// Die zuletzt geoeffnete Quelle bleibt offen (im Kern, TRdxSourceCache):
// gleicher Name, gleiche Herkunft, gleicher Text -> kein neuer Parse
// (Review Minor 9; ein Menue fragt bis zu MAX_FINDINGS_PER_MENU Funde, die
// Gluehbirne jede beruhigte Caret-Zeile). Die Fundzeile wird gegen den
// Fund geprueft (Ziel, '+'-Zahl; TRdxRecipeRunner.QueryOf/Describe): steht
// dort nach einer Bearbeitung eine andere Anweisung, entfallen die
// Baum-Rezepte mit dem Grund "Zeile verschoben?" (Review Minor 20).
// Ebenso bleiben die Zeilen der zuletzt gelesenen Datei stehen, samt ihrer
// Code-Sicht (uRdxCodeMap.TRdxMappedLines, Charge P5): Unterdrueck-Hilfen,
// Planer und Kontext-Laeufer teilen sich EINE Code-Sicht je Text, ueber
// alle Funde eines Menues und die Code-Aktion am Caret (SharedLines); was
// FileReason/IncludeReason auf der Platte sehen, gilt fuer einen
// Menueaufbau (DISK_BATCH_MS, BeginDiskBatch).
//
// WAS ANGEBOTEN WIRD
//
// Die Menuetexte sind englische msgids (CAP_* in uRdxActionCore; die der
// einfachen Hilfen in uRdxFixTable, FIX_CAPTIONS; uebersetzt ueber
// i18n/*.po); hier stehen sie deutsch zur Erlaeuterung.
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
  uEngineApi, uMethodd12, uFindingActions,
  uRdxScopeTable,
  uRdxBufferMath,   // TRdxTextSource, TRdxEdit
  uRdxCodeMap,      // TRdxMappedLines: Zeilen mit geteilter Code-Sicht (P5)
  uRdxMagicFixes,   // TRdxDiskReasonCache (P5)
  uRdxRecipeRunner, // TRdxObjectRing
  uRdxActionCore;   // TRdxActionCore: die Eintraege ohne IDE (E3)

type
  // Eine Aktion liess sich nicht ausfuehren (Bereich nicht markierbar,
  // Puffer weicht vom Stand beim Menueaufbau ab ...). Message ist der
  // Grund samt Protokollhinweis; der Host zeigt ihn an (Review R1-05,
  // SCA127: bis dahin die Basisklasse Exception).
  ERdxActionFailed = class(Exception);

  // Ein Menuepunkt samt allem, was Execute braucht (die Daten eines
  // Eintrags des Kerns, TRdxActionData). Lebt im Anbieter, bis
  // RDX_ACTION_BATCHES neuere Provide-Chargen entstanden sind (TRdxObjectRing) -
  // nicht nur bis zum naechsten Provide, denn ein Host stellt die
  // Aktionen mehrerer Funde in ein Menue (Stufe B, Konzept Editor-
  // Gluehbirne 2026-10-06). Mehrere Ersetzungen (TRdxEdit aus uRdxBufferMath)
  // prueft uRdxEditor.ReplaceSpans alle gegen den Puffer und schreibt sie
  // dann aufsteigend durch EINEN Writer - ein Undo-Schritt. Die Daten sind
  // der ganze Record des Kerns (Review E3: kein Feld kann beim Umkopieren
  // verloren gehen).
  TRdxAction = class
  private
    FData : TRdxActionData;
  public
    // TNotifyEvent fuer TFindingAction.Execute. Fehler laufen als
    // ERdxActionFailed zum Host, der sie anzeigt.
    procedure Execute(Sender: TObject);
  end;

  TRdxProvider = class
  private
    FActions     : TRdxObjectRing;   // besitzt die TRdxAction-Objekte
    FCore        : TRdxActionCore;   // Eintraege und offene Quelle (E3)
    FScopes      : TRdxScopeTable;
    FToken       : Integer;
    FContextToken: Integer;          // Kontext-Anbieter (Charge B), 0 = ab
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
    // Ein Aktionsobjekt mit AData, im Ring der laufenden Charge.
    function NewAction(const AData: TRdxActionData): TRdxAction;
    procedure Add(var AList: TArray<TFindingAction>;
      const ACaption, AHint: string; AEnabled: Boolean; AAction: TRdxAction);
    // Ein Eintrag des Kerns als Menuepunkt: die Felder ueber
    // TRdxActionCore.FindingActionOf (getestet in uTestRdxActionCore), hier
    // nur noch Execute aus einem TRdxAction im Ring.
    procedure AddEntry(var AList: TArray<TFindingAction>;
      const AEntry: TRdxActionEntry);
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
    // gleicher Text - der schon offene (TRdxSourceCache des Kerns, Minor 9).
    // nil, wenn der Parser scheitert; der Grund steht im Protokoll, die
    // anderen Code-Aktionen bleiben. Ein erschoepfter Stapel und EAbort
    // laufen weiter wie im Kern (AddTreeActions).
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
    // Create baut die Scope-Tabelle und den Kern (Rezeptlisten,
    // Quellstellen-Dienst); Destroy meldet ab (UnregisterAtHost) und gibt
    // alles frei. Von aussen nur ueber Instance/Shutdown - die Tests
    // erzeugen eigene Anbieter.
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
  uFileTextCache,   // LoadFileSmart: dieselbe Dekodierung wie der Scan
  uRdxText,         // _(): in die reDelphix-Sprache, nie uLocalization (E29)
  uRdxFixTable,     // ContextCaption: Menuetexte der Code-Aktionen
  uRdxContextRunner, // Code-Aktionen ohne Fund am Caret (Charge B)
  uRdxEditor,
  uRdxLog;          // Protokoll: DebugView + %TEMP%\reDelphix.log

const
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
  case FData.Kind of
    akShowSpan:
      if not TRdxEditor.SelectSpan(FData.FileName, FData.Span, Err) then
        raise ERdxActionFailed.Create(Err);
    akReplace:
      // Alle Ersetzungen auf einmal: geprueft, dann EIN Undo-Schritt.
      if not TRdxEditor.ReplaceSpans(FData.FileName, FData.Edits, Err) then
        raise ERdxActionFailed.Create(Err);
    akSqlTemplate:
      Clipboard.AsText := FData.Template;
  else
    // Jede Art hat oben ihren Zweig; eine neue ohne Zweig faellt hier auf,
    // statt still nichts zu tun (SCA168) - der Host zeigt die Meldung.
    raise ERdxActionFailed.Create(DIAG_PREFIX
      + _('action kind %d without execution', [Ord(FData.Kind)]));
  end;
end;

{ TRdxProvider }

constructor TRdxProvider.Create;
begin
  inherited Create;
  // Je Charge die Aktionsobjekte EINES Provide; wie viele am Leben
  // bleiben, steht bei RDX_ACTION_BATCHES (uRdxRecipeRunner).
  FActions := TRdxObjectRing.Create(RDX_ACTION_BATCHES);
  FDiskCache := TRdxDiskReasonCache.Create;
  FScopes  := TRdxScopeTable.Create;
  FScopes.LoadDefault;   // False = keine Tabelle; uses-Aktionen sagen das
  // Der Kern: Rezepte in der Reihenfolge des Menues, offene Quelle. Die
  // Projekt-Units fuer 'uses: X -> Scope.X' liefert die ToolsAPI - erst,
  // wenn ein Eintrag sie braucht (Review R1-02, AddUsesActions).
  FCore := TRdxActionCore.Create(FScopes);
  FCore.ProjectUnits :=
    function(const AFileName: string): TRdxProjectUnits
    begin
      Result := TRdxEditor.ProjectUnits(AFileName);
    end;
end;

destructor TRdxProvider.Destroy;
begin
  UnregisterAtHost;
  FCore.Free;     // vor der Scope-Tabelle: der Kern liest sie nur
  FScopes.Free;
  FDiskCache.Free;
  FLines.Free;
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

function TRdxProvider.NewAction(const AData: TRdxActionData): TRdxAction;
begin
  Result := TRdxAction.Create;
  Result.FData := AData;
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
  A.Kind    := fakFix;   // AddEntry stellt danach auf die Art des Eintrags
  if Assigned(AAction) then
    A.Execute := AAction.Execute
  else
    A.Execute := nil;
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := A;
end;

procedure TRdxProvider.AddEntry(var AList: TArray<TFindingAction>;
  const AEntry: TRdxActionEntry);
var
  A   : TFindingAction;
  Act : TRdxAction;
begin
  // Menuetext, Hinweis, verfuegbar, Art und Kennzeichnung (E2) mappt der
  // Kern; hier haengt nur noch die Ausfuehrung daran.
  A := TRdxActionCore.FindingActionOf(AEntry);
  if AEntry.HasAction then
  begin
    Act := NewAction(AEntry.Action);
    A.Execute := Act.Execute;
  end;
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := A;
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
  Text     : string;
  Source   : TRdxTextSource;
  Lines    : TStrings;
  Why      : string;
  PrevDisk : TRdxDiskReasonCache;
  Entries  : TArray<TRdxActionEntry>;
  Entry    : TRdxActionEntry;
begin
  Result := nil;
  // Kein FActions.Clear mehr (Stufe B): die Objekte des vorigen Provide
  // haengen womoeglich noch an Menuepunkten desselben Menues - eine neue
  // Charge, die aelteste faellt heraus.
  FActions.BeginBatch;
  if not Assigned(AFinding) then Exit;
  Why := TRdxActionCore.FindingDiagnosis(AFinding);
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
    // Was angeboten wird, rechnet der Kern (E3) - dieselben Eintraege
    // sieht die Probe ohne IDE.
    Entries := FCore.Describe(AFinding, Lines, Source, Text);
  finally
    TRdxMagicFixes.UseDiskCache(PrevDisk);
  end;
  for Entry in Entries do
    AddEntry(Result, Entry);
end;


function TRdxProvider.ContextPlaces(const AFileName,
  AText: string): TSourcePlaces;
begin
  Result := nil;
  try
    if FCore.Source.Open(AFileName, txBuffer, AText) <> orFailed then
      Result := FCore.Source.Places;
  except
    on EStackExhausted do raise;
    on EAbort do raise;
    // noinspection ExceptionTooGeneral
    // Wie der Kern (AddTreeActions): ein Fehler beim Parsen kostet nur die
    // Aktion, die den Baum braucht (der Dienst schliesst sich dabei selbst).
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
  Data     : TRdxActionData;
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
        Data := Default(TRdxActionData);
        Data.Kind     := akReplace;
        Data.FileName := AContext.FileName;
        Data.Edits    := O.Edits;
        Act := NewAction(Data);
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
