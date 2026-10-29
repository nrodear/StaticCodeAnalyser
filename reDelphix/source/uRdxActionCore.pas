unit uRdxActionCore;

// reDelphix - der Kern des Anbieters: was das Menue und die Gluehbirne zu
// EINEM Fund anbieten, als reine Beschreibung - ohne ToolsAPI, ohne VCL,
// ohne Editor (Realworld-Probe der Editorhilfen, Entscheid E3 vom
// 2026-10-28). Bis dahin stand dieser Ablauf in uRdxProvider (Provide,
// AddTreeActions und die Rezepte); dort bleibt seitdem nur, was die IDE
// braucht: den Text lesen (Editor-Puffer oder Platte), die Projekt-Units
// ueber die ToolsAPI, die Aktionsobjekte samt Ausfuehrung (Ersetzen im
// Puffer, Markieren, Zwischenablage) und der Plattenblick je Menueaufbau.
// IDE und Probe (tools\probe\RdxActionProbe) fragen so DENSELBEN Kern -
// was die Probe misst, ist das, was die Gluehbirne anbietet.
//
// WAS DESCRIBE LIEFERT
//
// Je Eintrag ein TRdxActionEntry in der Reihenfolge des Menues: Rezept,
// Menuetext, Hinweis bzw. Grund der Sperre, verfuegbar, Art
// (TFindingActionKind), Kennzeichnung (E2), Variante der einfachen Hilfe
// (0 = FixFor, 1 = AlternativeFixFor) und - nur bei einem verfuegbaren
// Eintrag - die Daten zum Ausfuehren (TRdxActionData: Bereich zum
// Markieren, Ersetzungen fuer EINEN Undo-Schritt, Vorlage fuer die
// Zwischenablage). Der Anbieter uebersetzt jeden Eintrag in eine
// TFindingAction mit Execute (TRdxAction); die Probe wendet die
// Ersetzungen mit PlanByteEdits/ApplyByteEdits an.
//
// Die Reihenfolge: Baum-Rezepte (Stelle zeigen, Format(), SQL-Vorlage,
// uses, die Tabelle der einfachen Hilfen), Text-Rezepte (SCA165),
// "reDelphix: <Grund>", wenn bis dahin nichts entstand, und zuletzt
// Unterdruecken. Das Parsen kostet bei einem Fehler nur die Baum-Rezepte
// (Eintrag "reDelphix: Parser: <Klasse>: <Meldung>"); ein erschoepfter
// Stapel und EAbort laufen weiter (uCrashDiag, Projektregel). Eine
// Ausnahme in einem Rezept laeuft zum Aufrufer (der Host zeigt sie, die
// Probe zaehlt sie) - wie bisher im Anbieter.
//
// EINGABE
//
// Der Fund, die Zeilen der Datei (Editor-Puffer oder Platte, wie der
// Aufrufer sie las) und die Herkunft des Texts: txBuffer parst AText,
// txDisk oeffnet die Datei (AText ist dann nur der Vergleichstext der
// offenen Quelle - gleicher Name, gleiche Herkunft, gleicher Text: kein
// neuer Parse, Review Minor 9). Die Projekt-Units fuer 'uses: X ->
// Scope.X' kommen ueber ProjectUnits (die IDE: TRdxEditor.ProjectUnits);
// ohne Lieferanten entfaellt der uses-Umbau, UsesSkipped sagt, ob die
// Fundzeile in einer uses-Klausel lag (die Probe vermerkt es).
//
// gen-quickfix-doc.py liest die Rezepte HIER (Konstruktor und Ruempfe) -
// Form der Aufrufe Add/AddReplace/AddRefactor und der Zuweisungen
// "F..Recipes[i] := AddXxx;" bitte beibehalten.

interface

uses
  System.SysUtils, System.Classes,
  uEngineApi, uRefactorInfo, uMethodd12, uFindingActions,
  uRdxScopeTable,   // TRdxScopeTable, TRdxProjectUnits
  uRdxBufferMath;   // TRdxTextSource, TRdxEdit, SpanFitsEditor

const
  // Vor jedem Eintrag, der nur einen Grund nennt ("reDelphix: Datei nicht
  // lesbar") - Code, kein Text: keine msgid.
  DIAG_PREFIX = 'reDelphix: ';
  // Die Namen der Rezepte (TRdxActionEntry.Recipe) - Code, keine msgid. Die
  // Probe (Spalte Eintrag) und die Tests lesen sie; eine neue Hilfe mit
  // eigenem Rezept bekommt hier ihren Namen und im Konstruktor ihren Platz.
  RECIPE_SHOW_SPAN     = 'ShowSpan';
  RECIPE_FORMAT_CALL   = 'FormatCall';
  RECIPE_SQL_TEMPLATE  = 'SqlTemplate';
  RECIPE_USES_ACTIONS  = 'UsesActions';
  RECIPE_SIMPLE_FIX    = 'SimpleFix';
  RECIPE_REMOVE_MARKER = 'RemoveMarker';
  RECIPE_SUPPRESS      = 'Suppress';
  // Keine Rezepte, aber Herkunft eines Eintrags: die Quelle liess sich
  // nicht oeffnen (Datei nicht lesbar, Parser) bzw. "reDelphix: <Grund>",
  // wenn nichts anderes entstand.
  RECIPE_OPEN          = 'Open';
  RECIPE_DIAGNOSIS     = 'Diagnosis';

type
  // Was ein verfuegbarer Eintrag beim Ausfuehren tut (der Anbieter fuehrt
  // es aus, uRdxProvider.TRdxAction.Execute).
  TRdxActionKind = (akShowSpan, akReplace, akSqlTemplate);

  // Die Daten zum Ausfuehren - nichts darin kennt den Editor.
  TRdxActionData = record
    Kind     : TRdxActionKind;
    FileName : string;              // '' bei akSqlTemplate
    Span     : TRefactorSpan;       // akShowSpan: der Bereich zum Markieren
    Template : string;              // akSqlTemplate: Text fuer die Zwischenablage
    // akReplace: alle Ersetzungen, EIN Undo-Schritt (uRdxEditor.ReplaceSpans
    // prueft sie gegen den Puffer und sortiert selbst).
    Edits    : TArray<TRdxEdit>;
  end;
  // Die Rezepte reichen Add die Daten eines verfuegbaren Eintrags als
  // Zeiger auf ihren lokalen Record (Add kopiert sie sofort); nil heisst
  // "ohne Daten", der Eintrag ist dann gesperrt. So bleibt die Aufrufform
  // Add(AList, Menuetext, Hinweis, Enabled, nil) erhalten, die
  // tools/gen-quickfix-doc.py in den Rezeptruempfen liest.
  PRdxActionData = ^TRdxActionData;

  // Ein Eintrag wie TFindingAction, als Beschreibung.
  TRdxActionEntry = record
    // Das Rezept, das ihn anlegte: eine der Konstanten RECIPE_* oben
    // (RECIPE_OPEN: Quelle nicht lesbar, Parser; RECIPE_DIAGNOSIS:
    // "reDelphix: <Grund>").
    Recipe          : string;
    Caption         : string;       // Menuetext, uebersetzt (uRdxText)
    Hint            : string;       // Hinweis, bei Enabled = False der Grund
    Enabled         : Boolean;
    Kind            : TFindingActionKind;
    ChangesBehavior : Boolean;      // E2: '(aendert Verhalten)'
    // SimpleFix: 0 = der erste Eintrag (FixFor), 1 = der zweite
    // (AlternativeFixFor); sonst 0.
    Variant         : Integer;
    HasAction       : Boolean;      // nur dann gilt Action
    Action          : TRdxActionData;
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

  // Ein Rezept haengt seine Eintraege an AList an - oder keine.
  TRdxRecipe = procedure(var AList: TArray<TRdxActionEntry>;
    const ACtx: TRdxRecipeContext) of object;

  TRdxOpenResult = (orFailed, orOpened, orReused);

  // Die zuletzt geoeffnete Quelle des Quellstellen-Dienstes, ueber mehrere
  // Aufrufe gehalten (Review Minor 9, s. Kopf): bei gleichem Dateinamen,
  // gleicher Herkunft und gleichem Text wird nicht neu geparst.
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

  // Der Index der Projekt-Units nahe AFileName (IDE: TRdxEditor.
  // ProjectUnits ueber die ToolsAPI). Der Kern gibt ihn frei.
  TRdxProjectUnitsSource = reference to function(
    const AFileName: string): TRdxProjectUnits;

  // Der Ablauf des Anbieters je Fund ohne IDE (s. Kopf): Describe liefert
  // die Eintraege, FindingActionOf macht aus einem Eintrag die
  // TFindingAction ohne Execute. Ein Kern haelt die zuletzt geoeffnete
  // Quelle (Source) ueber mehrere Aufrufe; er ist nicht threadsicher - je
  // Thread ein Kern (der Anbieter haelt genau einen, die Probe einen).
  TRdxActionCore = class
  private
    FSource       : TRdxSourceCache;
    FScopes       : TRdxScopeTable;          // gehoert dem Aufrufer
    FProjectUnits : TRdxProjectUnitsSource;  // nil: kein uses-Umbau
    FUsesNames    : TArray<string>;          // Namen der uses-Eintraege der Datei
    FRecipe       : string;                  // Rezept der naechsten Eintraege
    FUsesSkipped  : Boolean;
    FLogging      : Boolean;
    // Die Rezept-Zuordnung: eine neue Hilfe ist ein Rezept mehr in einer
    // der Listen (Konstruktor), nicht ein Zweig mehr in Describe. Je Liste
    // die Namen der Rezepte in derselben Reihenfolge (TRdxActionEntry.Recipe).
    FTreeRecipes : TArray<TRdxRecipe>;   // brauchen den geparsten Quelltext
    FTextRecipes : TArray<TRdxRecipe>;   // brauchen nur die Zeilen
    // Unterdruecken steht im Menue HINTER den Hilfen und hinter der
    // Diagnose "reDelphix: <Grund>", die nur kommt, wenn keine Hilfe da ist.
    FSuppressRecipes : TArray<TRdxRecipe>;
    FTreeNames     : TArray<string>;
    FTextNames     : TArray<string>;
    FSuppressNames : TArray<string>;
    // Ein Eintrag; AAction = nil: ohne Daten zum Ausfuehren (gesperrt).
    // Art fakFix - Rezepte mit anderer Art stellen sie danach um.
    procedure Add(var AList: TArray<TRdxActionEntry>;
      const ACaption, AHint: string; AEnabled: Boolean; AAction: PRdxActionData);
    // Eine Ersetzung als Eintrag der Art AKind (ohne Hinweistext).
    procedure AddReplace(var AList: TArray<TRdxActionEntry>;
      const ACaption, AFileName: string; const AEdit: TRdxEdit;
      AKind: TFindingActionKind);
    // Ein Umbau an der Stelle, kein Fix des Funds (fakRefactor): nie in
    // der Gluehbirne, im Menue je Zeile nur einmal (Review nach Bereichen
    // 2026-10-10, Minor 13/14). AAction = nil: gesperrt mit Grund AHint.
    procedure AddRefactor(var AList: TArray<TRdxActionEntry>;
      const ACaption, AHint: string; AAction: PRdxActionData);
    // Baum-Rezepte
    procedure AddShowSpan(var AList: TArray<TRdxActionEntry>;
      const ACtx: TRdxRecipeContext);
    procedure AddFormatCall(var AList: TArray<TRdxActionEntry>;
      const ACtx: TRdxRecipeContext);
    procedure AddSqlTemplate(var AList: TArray<TRdxActionEntry>;
      const ACtx: TRdxRecipeContext);
    procedure AddUsesActions(var AList: TArray<TRdxActionEntry>;
      const ACtx: TRdxRecipeContext);
    // Die einfachen Editorhilfen ueber die Tabelle uRdxFixTable (welche
    // Regeln: TRdxFixTable.Handles; Planer, Hinweis und Menuetext je Zeile)
    // - eine weitere Regel braucht hier kein Rezept.
    procedure AddSimpleFix(var AList: TArray<TRdxActionEntry>;
      const ACtx: TRdxRecipeContext);
    // Text-Rezepte (Editorhilfen Stufe 1)
    procedure AddRemoveMarker(var AList: TArray<TRdxActionEntry>;
      const ACtx: TRdxRecipeContext);
    // Zeilen- und Datei-Marker '// noinspection'.
    procedure AddSuppress(var AList: TArray<TRdxActionEntry>;
      const ACtx: TRdxRecipeContext);
    // Die Rezepte einer Liste nacheinander, je mit seinem Namen.
    procedure RunRecipes(var AList: TArray<TRdxActionEntry>;
      const ARecipes: TArray<TRdxRecipe>; const ANames: TArray<string>;
      const ACtx: TRdxRecipeContext);
    // Quelltext parsen (oder wiederverwenden), Anker beschreiben,
    // Baum-Rezepte laufen lassen.
    procedure AddTreeActions(var AList: TArray<TRdxActionEntry>;
      var ACtx: TRdxRecipeContext; ASource: TRdxTextSource;
      const AText: string);
    // "reDelphix: <Grund>", wenn bis hierher kein Eintrag entstanden ist -
    // sonst waere "keine Hilfe" nicht von "Anbieter nicht geladen" zu
    // unterscheiden.
    procedure AddDiagnosis(var AList: TArray<TRdxActionEntry>;
      const ACtx: TRdxRecipeContext);
  public
    // AScopes: die Scope-Tabelle fuer 'uses: X -> Scope.X' (gehoert dem
    // Aufrufer und lebt laenger als der Kern; nil nur ohne ProjectUnits).
    constructor Create(AScopes: TRdxScopeTable);
    destructor Destroy; override;

    // Warum es zum Fund nichts gibt, bevor eine Datei gelesen wird: kein
    // Dateiname, keine Zeile - oder kein Pascal-Quelltext (Review R1-04:
    // fuer andere Dateien gibt es kein Rezept, auch kein Text-Rezept,
    // missed 1). '' = weiter (Describe). Ob die Datei auf der Platte liegt,
    // fragt der Aufrufer erst, wenn sie nicht im Editor offen ist (SMB-
    // Timeout, Wochen-Review 2026-10-21).
    class function FindingDiagnosis(const AFinding: TLeakFinding): string; static;

    // Die Eintraege zu AFinding (Reihenfolge und Inhalt s. Kopf). ALines
    // ist der Text der Datei (gehoert dem Aufrufer; Rezepte und Planer
    // lesen nur), ASource seine Herkunft, AText der geparste (txBuffer)
    // bzw. Vergleichstext (txDisk). Voraussetzung: FindingDiagnosis = ''.
    // Den Plattenblick der Planer (TRdxMagicFixes.UseDiskCache) setzt der
    // Aufrufer, wenn er ihn will.
    function Describe(const AFinding: TLeakFinding; ALines: TStrings;
      ASource: TRdxTextSource; const AText: string): TArray<TRdxActionEntry>;

    // Der Menuepunkt zu AEntry ohne Execute (das haengt der Anbieter an,
    // wenn AEntry.HasAction): Menuetext, Hinweis, Art und Kennzeichnung wie
    // beschrieben, verfuegbar nur mit Daten zum Ausfuehren (wie bis E3
    // TRdxProvider.Add: Enabled and Assigned(Aktion)). Recipe und Variant
    // gehen nicht in die TFindingAction - sie kennt keine solchen Felder
    // (uTestRdxActionCore pinnt die Felder beider Records).
    class function FindingActionOf(
      const AEntry: TRdxActionEntry): TFindingAction; static;

    // Die offene Quelle - der Anbieter teilt sie mit der Code-Aktion am
    // Caret (ContextPlaces).
    property Source: TRdxSourceCache read FSource;
    // Die Scope-Tabelle aus dem Konstruktor (gehoert dem Aufrufer); nil
    // oder leer: 'uses: X -> Scope.X' ist gesperrt (qbNoTable).
    property Scopes: TRdxScopeTable read FScopes;
    // Lieferant der Projekt-Units; nil (Vorgabe): kein uses-Umbau.
    property ProjectUnits: TRdxProjectUnitsSource read FProjectUnits
      write FProjectUnits;
    // Nach Describe: die Fundzeile lag in einer uses-Klausel, aber ohne
    // ProjectUnits gab es keinen uses-Umbau.
    property UsesSkipped: Boolean read FUsesSkipped;
    // Eine Protokollzeile je Fund (uRdxLog, %TEMP%\reDelphix.log);
    // Vorgabe True. Die Probe und die Tests schalten sie ab.
    property Logging: Boolean read FLogging write FLogging;
  end;

implementation

uses
  uCrashDiag,       // EStackExhausted
  uSCAConsts,       // KindName, fkUnusedSuppression
  uRdxText,         // _(): in die reDelphix-Sprache, nie uLocalization (E29)
  uRuleCatalog,
  uRdxFixTable,     // Tabelle der einfachen Hilfen: Planer und Menuetexte
  uRdxSuppress,
  uRdxRecipeRunner, // Describe, FormatRewrite, SqlTemplate, QualifyUses
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
  // Fuer das Protokoll (deutsch wie die uebrigen Zeilen).
  SOURCE_NAMES : array[TRdxTextSource] of string =
    ('Editor-Puffer', 'Platte', 'gesperrt');
  OPEN_NAMES   : array[TRdxOpenResult] of string =
    ('', ', neu geparst', ', wiederverwendet');

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

{ TRdxActionCore }

constructor TRdxActionCore.Create(AScopes: TRdxScopeTable);
begin
  inherited Create;
  FSource  := TRdxSourceCache.Create;
  FScopes  := AScopes;
  FLogging := True;
  // Reihenfolge = Reihenfolge im Menue.
  SetLength(FTreeRecipes, 5);
  FTreeRecipes[0] := AddShowSpan;
  FTreeRecipes[1] := AddFormatCall;
  FTreeRecipes[2] := AddSqlTemplate;
  FTreeRecipes[3] := AddUsesActions;
  FTreeRecipes[4] := AddSimpleFix;
  FTreeNames := [RECIPE_SHOW_SPAN, RECIPE_FORMAT_CALL, RECIPE_SQL_TEMPLATE,
    RECIPE_USES_ACTIONS, RECIPE_SIMPLE_FIX];
  SetLength(FTextRecipes, 1);
  FTextRecipes[0] := AddRemoveMarker;
  FTextNames := [RECIPE_REMOVE_MARKER];
  SetLength(FSuppressRecipes, 1);
  FSuppressRecipes[0] := AddSuppress;
  FSuppressNames := [RECIPE_SUPPRESS];
  // Je Rezept ein Name in derselben Reihenfolge - ein Rezept ohne Namen
  // truege Recipe = '' (RunRecipes), die Probe ordnete es nicht zu.
  Assert(Length(FTreeNames) = Length(FTreeRecipes), 'FTreeNames');
  Assert(Length(FTextNames) = Length(FTextRecipes), 'FTextNames');
  Assert(Length(FSuppressNames) = Length(FSuppressRecipes), 'FSuppressNames');
end;

class function TRdxActionCore.FindingActionOf(
  const AEntry: TRdxActionEntry): TFindingAction;
begin
  // Default: Execute nil, und kein Feld bleibt auf Zufall (Review Welle 1,
  // Bereich D) - jedes andere Feld setzt die Zuweisung unten ausdruecklich.
  Result := Default(TFindingAction);
  Result.Caption         := AEntry.Caption;
  Result.Hint            := AEntry.Hint;
  Result.Enabled         := AEntry.Enabled and AEntry.HasAction;
  Result.Kind            := AEntry.Kind;
  Result.ChangesBehavior := AEntry.ChangesBehavior;
  Result.Execute         := nil;   // haengt der Anbieter an (TRdxAction)
end;

destructor TRdxActionCore.Destroy;
begin
  FSource.Free;
  inherited;
end;

procedure TRdxActionCore.Add(var AList: TArray<TRdxActionEntry>;
  const ACaption, AHint: string; AEnabled: Boolean; AAction: PRdxActionData);
var
  A : TRdxActionEntry;
begin
  // Ein lokaler Record ist nicht initialisiert: ChangesBehavior (E2, die
  // Taste fuehrt eine so gekennzeichnete Hilfe nicht ungesehen aus) stuende
  // sonst auf Zufall (Review Welle 1, Bereich D). Default setzt alle Felder,
  // auch Kind auf fakUnset - darum unten AUSDRUECKLICH fakFix.
  A := Default(TRdxActionEntry);
  A.Recipe    := FRecipe;
  A.Caption   := ACaption;
  A.Hint      := AHint;
  A.Enabled   := AEnabled and Assigned(AAction);
  A.Kind      := fakFix;   // AddShowSpan stellt danach auf fakNavigate
  A.HasAction := Assigned(AAction);
  if A.HasAction then
    A.Action := AAction^;
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := A;
end;

procedure TRdxActionCore.AddReplace(var AList: TArray<TRdxActionEntry>;
  const ACaption, AFileName: string; const AEdit: TRdxEdit;
  AKind: TFindingActionKind);
var
  Act : TRdxActionData;
begin
  Act := Default(TRdxActionData);
  Act.Kind     := akReplace;
  Act.FileName := AFileName;
  SetLength(Act.Edits, 1);
  Act.Edits[0] := AEdit;
  Add(AList, ACaption, '', True, @Act);
  AList[High(AList)].Kind := AKind;
end;

procedure TRdxActionCore.AddRefactor(var AList: TArray<TRdxActionEntry>;
  const ACaption, AHint: string; AAction: PRdxActionData);
begin
  Add(AList, ACaption, AHint, Assigned(AAction), AAction);
  AList[High(AList)].Kind := fakRefactor;
end;

procedure TRdxActionCore.AddShowSpan(var AList: TArray<TRdxActionEntry>;
  const ACtx: TRdxRecipeContext);
var
  Act : TRdxActionData;
begin
  if not Assigned(ACtx.Info) or not ACtx.Info.Span.IsValid then Exit;
  // Die Editor-Markierung rechnet in SmallInt-Spalten (Review Nit 8):
  // weiter rechts wird die Stelle nicht angeboten, sondern begruendet.
  if not SpanFitsEditor(ACtx.Lines, ACtx.Info.Span) then
  begin
    Add(AList, _(CAP_SHOW), MsgTooLongForEditor(EDITOR_MAX_COLUMN),
      False, nil);
    AList[High(AList)].Kind := fakNavigate;
    Exit;
  end;
  Act := Default(TRdxActionData);
  Act.Kind     := akShowSpan;
  Act.FileName := ACtx.FileName;
  Act.Span     := ACtx.Info.Span;
  Add(AList, _(CAP_SHOW), Format(_('Line %d:%d to %d:%d'),
    [ACtx.Info.Span.StartLine, ACtx.Info.Span.StartCol,
     ACtx.Info.Span.EndLine, ACtx.Info.Span.EndCol - 1]), True, @Act);
  // Fuehrt nur hin - die Gluehbirne im Editor laesst das weg, der
  // Benutzer steht dort schon an der Stelle.
  AList[High(AList)].Kind := fakNavigate;
end;

procedure TRdxActionCore.AddFormatCall(var AList: TArray<TRdxActionEntry>;
  const ACtx: TRdxRecipeContext);
var
  Outcome : TRdxFormatOutcome;
  Act     : TRdxActionData;
begin
  if ACtx.FixMode <> 'auto' then Exit;
  Outcome := TRdxRecipeRunner.FormatRewrite(FSource.Places, ACtx.Info, ACtx.Why,
    FUsesNames);
  if not Outcome.Enabled then
  begin
    Add(AList, _(CAP_FORMAT), Outcome.Reason, False, nil);
    Exit;
  end;
  Act := Default(TRdxActionData);
  Act.Kind     := akReplace;
  Act.FileName := ACtx.FileName;
  SetLength(Act.Edits, 1);
  Act.Edits[0].Span     := Outcome.Span;
  Act.Edits[0].Expected := Outcome.Expected;
  Act.Edits[0].NewText  := Outcome.NewText;
  if Outcome.NeedsUses then
  begin
    // Zweite Ersetzung: System.SysUtils in die uses-Klausel. Die
    // Reihenfolge ist gleichgueltig - ReplaceSpans sortiert selbst.
    SetLength(Act.Edits, 2);
    Act.Edits[1] := Outcome.UsesEdit;
  end;
  Add(AList, _(CAP_FORMAT), Outcome.Hint, True, @Act);
end;

procedure TRdxActionCore.AddSqlTemplate(var AList: TArray<TRdxActionEntry>;
  const ACtx: TRdxRecipeContext);
var
  Offer : TRdxSqlOffer;
  Act   : TRdxActionData;
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
  Act := Default(TRdxActionData);
  Act.Kind     := akSqlTemplate;
  Act.Template := Offer.Template;
  Add(AList, _(CAP_SQL), Offer.Hint, True, @Act);
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

procedure TRdxActionCore.AddUsesActions(var AList: TArray<TRdxActionEntry>;
  const ACtx: TRdxRecipeContext);
var
  Plan     : TRdxQualifyPlan;
  Item     : TRdxQualifyItem;
  Act      : TRdxActionData;
  FileName : string;
  Units    : TRdxProjectUnits;
  Supply   : TRdxProjectUnitsSource;
begin
  // Die Planung liegt im Laeufer (testbar, ohne ToolsAPI); hier nur die
  // Menuetexte. Nichts ausserhalb einer uses-Klausel - sonst stuende
  // "uses: ..." an jedem Fund der Datei. Das Fenster kennt auch die
  // Programm-Klausel (.dpr/.lpr/library, Review Minor 18) und beginnt auf
  // der Zeile des 'uses' (Minor 19). Ein ausdrueckliches fixMode 'none'
  // der Regel schaltet auch den Umbau auf ihrem Signal ab (Minor 5).
  if ACtx.FixMode = FIX_NONE then Exit;
  // Ohne Lieferanten der Projekt-Units (die Probe ohne IDE) entfaellt der
  // Umbau: ob ein Eintrag eine eigene Unit des Projekts ist, wuesste
  // niemand. UsesSkipped sagt, ob er an dieser Zeile stuende.
  Supply := FProjectUnits;
  if not Assigned(Supply) then
  begin
    FUsesSkipped := TRdxRecipeRunner.LineInUsesClause(FSource.Places,
      ACtx.Line);
    Exit;
  end;
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
          Units := Supply(FileName);
        Result := (Units <> nil) and Units.Knows(AShortName);
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
        Act := Default(TRdxActionData);
        Act.Kind     := akReplace;
        Act.FileName := ACtx.FileName;
        SetLength(Act.Edits, 1);
        Act.Edits[0] := Item.Edit;
        AddRefactor(AList, 'uses: ' + Item.Short + ' -> ' + Item.Qualified,
          '', @Act);
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
      Act := Default(TRdxActionData);
      Act.Kind     := akReplace;
      Act.FileName := ACtx.FileName;
      Act.Edits    := Plan.All;
      AddRefactor(AList, Format(_(CAP_USES_ALL), [Length(Plan.All)]),
        Plan.AllPreview, @Act);
    end;
  finally
    Units.Free;
  end;
end;

procedure TRdxActionCore.AddSimpleFix(var AList: TArray<TRdxActionEntry>;
  const ACtx: TRdxRecipeContext);

  // Ein Eintrag zu AOutcome: mit seinen Ersetzungen oder gesperrt mit Grund.
  // Menuetext, Variante und Kennzeichnung (E2) kommen aus der Tabelle;
  // ohne Menuetext kein Eintrag - bis Charge R8 stand dann der interne
  // Name der Art im Menue (uTestRdxFixTable pinnt jede Zeile).
  procedure AddOutcome(const AOutcome: TRdxFixOutcome);
  var
    Caption : string;
    Act     : TRdxActionData;
  begin
    Caption := TRdxFixTable.CaptionFor(ACtx.Finding.Kind, AOutcome);
    if Caption = '' then Exit;
    if not AOutcome.Enabled then
      Add(AList, Caption, AOutcome.Reason, False, nil)
    else
    begin
      Act := Default(TRdxActionData);
      Act.Kind     := akReplace;
      Act.FileName := ACtx.FileName;
      Act.Edits    := AOutcome.Edits;
      Add(AList, Caption, AOutcome.Hint, True, @Act);
    end;
    // E2: Ctrl+Alt+F fuehrt eine solche Hilfe nicht ungesehen aus.
    AList[High(AList)].ChangesBehavior := AOutcome.ChangesBehavior;
    AList[High(AList)].Variant := AOutcome.Variant;
    // Nur im Menue (TRdxFixOutcome.MenuOnly, rwE30): fakRefactor steht nie
    // in der Gluehbirne und laeuft nie per Taste (uFindingActions, VERTRAG);
    // Kontextmenue und Dock-Grid zeigen den Eintrag wie jede Hilfe.
    if AOutcome.MenuOnly then
      AList[High(AList)].Kind := fakRefactor;
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

procedure TRdxActionCore.AddSuppress(var AList: TArray<TRdxActionEntry>;
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

procedure TRdxActionCore.AddRemoveMarker(var AList: TArray<TRdxActionEntry>;
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
  // (Review R1, missed 1) - Describe kommt fuer solche Dateien gar nicht
  // dran (FindingDiagnosis).
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

procedure TRdxActionCore.RunRecipes(var AList: TArray<TRdxActionEntry>;
  const ARecipes: TArray<TRdxRecipe>; const ANames: TArray<string>;
  const ACtx: TRdxRecipeContext);
var
  i : Integer;
begin
  for i := 0 to High(ARecipes) do
  begin
    if i <= High(ANames) then
      FRecipe := ANames[i]
    else
      FRecipe := '';
    ARecipes[i](AList, ACtx);
  end;
end;

procedure TRdxActionCore.AddTreeActions(var AList: TArray<TRdxActionEntry>;
  var ACtx: TRdxRecipeContext; ASource: TRdxTextSource; const AText: string);
var
  Meta   : TRuleMeta;
  Anchor : string;
  Opened : TRdxOpenResult;
  Done   : Boolean;
begin
  FRecipe := RECIPE_OPEN;
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

    // fixMode steht schon im Kontext (Describe, vor allen Rezepten); hier
    // nur noch der Anker der Regel.
    Meta   := TRuleCatalog.GetRuleCanonical(ACtx.Finding.Kind);
    Anchor := LowerCase(Meta.Anchor);
    if FLogging then
      RdxLog('Provide %s %s:%d anchor=%s fixMode=%s quelle=%s%s',
        [ACtx.Finding.ResolvedRuleId, ExtractFileName(ACtx.FileName),
         ACtx.Line, Anchor, ACtx.FixMode, SOURCE_NAMES[ASource],
         OPEN_NAMES[Opened]]);

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
    RunRecipes(AList, FTreeRecipes, FTreeNames, ACtx);
    Done := True;
  finally
    FreeAndNil(ACtx.Info);   // alles Noetige ist in die Eintraege kopiert
    // Die Quelle bleibt fuer den naechsten Fund offen (Minor 9) - ausser
    // ein Rezept ist mit einer Ausnahme ausgestiegen: die faul gebauten
    // Teile des Dienstes (Typen, Scope-Fakten) koennten dann halb stehen.
    if not Done then
      FSource.Forget;
  end;
end;

procedure TRdxActionCore.AddDiagnosis(var AList: TArray<TRdxActionEntry>;
  const ACtx: TRdxRecipeContext);
begin
  if Length(AList) > 0 then Exit;
  FRecipe := RECIPE_DIAGNOSIS;
  if ACtx.Why <> '' then
    Add(AList, DIAG_PREFIX + ACtx.Why, '', False, nil)
  else if ACtx.FixMode = '' then
    Add(AList, DIAG_PREFIX + Format(_('%s: no fixMode in the rule catalog'),
      [ACtx.Finding.ResolvedRuleId]), '', False, nil)
  else
    Add(AList, DIAG_PREFIX + _('nothing to offer'), '', False, nil);
end;

class function TRdxActionCore.FindingDiagnosis(
  const AFinding: TLeakFinding): string;
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

function TRdxActionCore.Describe(const AFinding: TLeakFinding;
  ALines: TStrings; ASource: TRdxTextSource;
  const AText: string): TArray<TRdxActionEntry>;
var
  Ctx : TRdxRecipeContext;
begin
  Result := nil;
  FUsesNames   := nil;
  FUsesSkipped := False;
  FRecipe      := '';
  Ctx := Default(TRdxRecipeContext);
  Ctx.Finding  := AFinding;
  Ctx.FileName := AFinding.FileName;
  Ctx.Line     := AFinding.LineInt;
  Ctx.KindName := uSCAConsts.KindName(AFinding.Kind);
  Ctx.Lines    := ALines;
  // fixMode aus dem Katalog vor ALLEN Rezepten: ein ausdrueckliches
  // 'none' sperrt auch die Text-Rezepte (Minor 5), und die brauchen den
  // Baum nicht.
  Ctx.FixMode  := LowerCase(TRuleCatalog.GetRuleCanonical(AFinding.Kind).FixMode);
  // Nur Pascal-Quelltext kommt hier an (FindingDiagnosis) und durch den
  // Parser - ein Fund in .dfm/.dproj braeuchte sonst Parse-Zeit im
  // UI-Thread und verdraengte die zuletzt geparste .pas aus dem Cache
  // (Review nach Bereichen 2026-10-10, Minor 15).
  AddTreeActions(Result, Ctx, ASource, AText);
  RunRecipes(Result, FTextRecipes, FTextNames, Ctx);
  AddDiagnosis(Result, Ctx);
  RunRecipes(Result, FSuppressRecipes, FSuppressNames, Ctx);
end;

end.
