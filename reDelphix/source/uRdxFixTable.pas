unit uRdxFixTable;

// reDelphix - die Tabelle der einfachen Editorhilfen: je Fundart EINE
// Zeile mit Planer, Hinweis, Kennzeichnung (E2), zweitem Eintrag und
// Menuetext. Der Laeufer-Einstieg (FixFor, AlternativeFixFor, Handles) und
// der Anbieter (CaptionFor) lesen aus derselben Zeile.
//
// WARUM (Wochen-Review 2026-10-13, Bereich B, Major 4; Charge R8): bis
// dahin lag das Wissen je Regel in zwei Units in parallelen case-Ketten -
// uRdxRecipeRunner FixFor -> LaterFixFor -> LineFixFor -> LineFix ->
// LinePlan -> DeclPlan (dazu LineHint -> DeclHint, FlowHint) und
// uRdxProvider SimpleFixCaption -> LaterFixCaption -> LineFixCaption ->
// DeclFixCaption -> FlowFixCaption -, nur zerteilt, um SCA091 (grosses
// case) zu unterbieten. Eine Art ohne Menuetext zeigte still ihren internen
// Namen (KindName), und kein Test fiel. Hier faellt uTestRdxFixTable: jede
// Zeile hat Planer, Hinweis (oder der Planer setzt ihn) und Menuetext.
//
// OHNE ToolsAPI: in reDelphix.Test uebersetzbar. Nicht im FPC-Pruefstand -
// die Unit braucht uRdxRecipeRunner und uRdxFixRunner, die den
// Quellstellen-Dienst brauchen. Die Rumpf-Routinen der Hilfen bleiben, wo
// sie sind (uRdxFixRunner - bis Charge B2S-b in uRdxRecipeRunner -, die
// Planer-Units); hier stehen nur die Adapter auf eine gemeinsame Form
// (TRdxFixPlanner), das EINE Geruest der Planer mit Plan-Record
// (TRdxFixFrame, Charge H5c) und die Zeilen.
//
// TEXTE: englische msgids, uebersetzt ueber i18n/*.po (Editorhilfen E6)
// in die reDelphix-Sprache (uRdxText._, Entscheid E29 - wie die
// SCA-Oberflaeche oder redelphix.ini [UI] Language; uRdxText nennt den
// Weg): Menuetexte, Hinweise und Gruende. Menuetexte und feste Hinweise
// stehen in FIX_CAPTIONS, FIX_ALT_CAPTIONS und FIX_HINTS - drei String-
// Arrays parallel zu FIX_ROWS, nicht als Feld der Zeile: tools/
// i18n_extract.py liest nur _('..'), _(KONSTANTE) und _(ARRAY[i]); ein
// Record-Feld bliebe fuer template.pot unsichtbar, und msgmerge markierte
// die Uebersetzungen als obsolet (bis Charge G7 stand der Hinweis als Feld
// Hint in der Zeile, deutsch). uTestRdxFixTable und tools/
// gen-quickfix-doc.py --check halten die vier Arrays zusammen (gleicher
// Index, kein leerer Menuetext, zweiter Menuetext genau mit zweitem
// Planer, fester Hinweis genau ohne HintByPlanner).

interface

uses
  System.Classes,
  uEngineApi,          // TSourcePlaces
  uMethodd12,          // TLeakFinding
  uSCAConsts,          // TFindingKind
  uRdxRecipeRunner;    // TRdxFixOutcome

type
  // Ein Planer der Tabelle - die Form von TRdxFixRunner.FixFor fuer EINE
  // Art: Zeile und Meldung kommen aus AFinding, die uses-Namen fuer eine
  // Einfuegung (SysUtils) aus AUsesNames.
  TRdxFixPlanner = function(APlaces: TSourcePlaces; ALines: TStrings;
    AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;

  // Eine Zeile der Tabelle (FIX_ROWS).
  //   HintByPlanner  True: der Planer setzt den Hinweis des aktiven
  //                  Eintrags selbst (aus Name oder Ersetzung, bei SCA085/
  //                  SCA139 vor dem ' + uses ...'); False: der feste Hinweis
  //                  unter demselben Index in FIX_HINTS (msgid, RawHint).
  //                  Genau eines von beiden.
  //   Changes        Kennzeichnung '(aendert Verhalten)' (E2), soweit sie
  //                  nicht vom Fund abhaengt - SCA149 (override oder
  //                  reintroduce) entscheidet der Planer.
  //   Alt            der zweite Eintrag derselben Art (Variant = 1: SCA168
  //                  else mit raise, SCA020 raise ENotImplemented), nil
  //                  ohne. Er setzt Variant, Hinweis und Kennzeichnung
  //                  selbst (der Hinweis bekommt noch ' + uses ...').
  TRdxFixRow = record
    Kind          : TFindingKind;
    Plan          : TRdxFixPlanner;
    HintByPlanner : Boolean;
    Changes       : Boolean;
    Alt           : TRdxFixPlanner;
  end;

  // Der Einstieg des Anbieters und der Tests. Eine weitere Regel ist eine
  // Zeile mehr in FIX_ROWS samt Menuetext in FIX_CAPTIONS und Hinweis in
  // FIX_HINTS - kein Zweig mehr in einem Verteiler.
  TRdxFixTable = class
  public
    // True, wenn die Tabelle fuer diese Art eine Hilfe kennt.
    class function Handles(AKind: TFindingKind): Boolean; static;

    // Die Hilfe fuer einen Fund: der Planer seiner Art, danach der Hinweis
    // der Zeile (wenn der Planer keinen setzte) und die Kennzeichnung.
    // Hinweis und Grund in der reDelphix-Sprache (uRdxText). Ohne Fund:
    // Reason 'no finding' (de 'kein Fund'); ohne Zeile: 'no simple quick
    // fix for this rule'.
    class function FixFor(APlaces: TSourcePlaces; ALines: TStrings;
      AFinding: TLeakFinding;
      const AUsesNames: TArray<string>): TRdxFixOutcome; static;

    // Der zweite Eintrag fuer denselben Fund (Variant = 1), sonst ein
    // leeres Ergebnis (Variant = 0).
    class function AlternativeFixFor(APlaces: TSourcePlaces; ALines: TStrings;
      AFinding: TLeakFinding;
      const AUsesNames: TArray<string>): TRdxFixOutcome; static;

    // Menuetext einer Hilfe, uebersetzt in die reDelphix-Sprache
    // (uRdxText): der Eintrag nach AOutcome.Variant, '%s' durch
    // AOutcome.Name ('X', wenn der Planer abgelehnt hat, bevor der Name
    // feststand), dahinter die Kennzeichnung bei ChangesBehavior. '' ohne
    // Zeile - dann entsteht KEIN Eintrag (bis Charge R8 stand dann
    // KindName im Menue).
    class function CaptionFor(AKind: TFindingKind;
      const AOutcome: TRdxFixOutcome): string; static;

    // Fuer uTestRdxFixTable: die Zeilen, ihre Menuetexte (msgids,
    // unuebersetzt; AVariant 0 oder 1) und ihre festen Hinweise (msgid aus
    // FIX_HINTS, unuebersetzt; '' bei HintByPlanner).
    class function RowCount: Integer; static;
    class function Row(AIndex: Integer): TRdxFixRow; static;
    class function RawCaption(AIndex, AVariant: Integer): string; static;
    class function RawHint(AIndex: Integer): string; static;
  end;

implementation

uses
  System.SysUtils,
  // Ruempfe der Hilfen mit Quellstellen-Dienst und Bausteine der Tabelle
  // (TRdxFixRunner, MapFix, CastFreeFix, EmptyRaiseFix, AppendUses,
  // CondAssignReason, SelfAssignReason) - bis Charge B2S-b in
  // uRdxRecipeRunner (Review R6-12)
  uRdxFixRunner,
  uRdxPaths,         // IsNetworkPath, RemoteDriveOf, WithoutNamespacePrefix
  uRdxText,          // _(): in die reDelphix-Sprache (E29), nie uLocalization
  uRdxRecipes,       // AsciiOnly (SCA085-Gegenprobe)
  uRdxCodeMap,       // TRdxCodeMap (Adapter auf die Code-Sicht)
  uRdxBufferMath,    // TRdxEdit
  uRdxSimpleFixes,   // SCA075, SCA087 (ExplicitTObject, EmptySection)
  uRdxLineFixes,     // SCA082, SCA071, SCA088
  uRdxRaiseFixes,    // SCA020, SCA120, SCA122
  uRdxDeclFixes,     // SCA117, SCA197, SCA149
  uRdxFlowFixes,     // SCA098, SCA080, SCA047
  uRdxRoutineFixes,  // SCA164, SCA147
  uRdxCleanupFixes,  // SCA070, SCA053
  uRdxTryFixes,      // SCA009, SCA001, SCA109, SCA153, SCA156
  uRdxResultFixes,   // SCA096, SCA097, SCA121, SCA196
  uRdxMagicFixes;    // SCA014

const
  // Hinweise und Gruende, die ein Planer-Adapter setzt: englische msgids,
  // uebersetzt mit _() an der Verwendung (Entscheid E29). Die festen
  // Hinweise der Zeilen stehen in FIX_HINTS (unten, parallel zu FIX_ROWS);
  // bis Charge R8 standen alle in uRdxRecipeRunner (LineHint, DeclHint,
  // FlowHint und je Rumpf), bis Charge G7 deutsch.
  R_OVERRIDE_HINT = 'the virtual call then ends up in this method';
  R_REINTRODUCE_HINT = 'only the warning W1010 goes away - the method still '
    + 'hides the inherited ones';
  R_FORM_UNREADABLE = 'form file %s not readable (%s) - an event binding '
    + 'cannot be ruled out';
  // SCA147: Formdateien, die eine Methode per Name an ein Ereignis binden.
  FORM_EXTENSIONS: array[0..2] of string = ('.dfm', '.fmx', '.lfm');
  // Charge H5 (Ergebnis und Konstruktoren): SCA096/SCA097 je nach Fund -
  // direkter TObject-Erbe bedeutungsgleich, sonst gekennzeichnet; SCA121/
  // SCA196 immer gekennzeichnet (Result ist danach definiert).
  R_CTOR_TOBJECT_HINT = 'TObject.Create is empty - same meaning; the '
    + 'constructor then follows the convention';
  R_CTOR_OVERRIDE_HINT = 'the overridden parent constructor now runs first, '
    + 'with the same arguments';
  R_DTOR_TOBJECT_HINT = 'TObject.Destroy is empty - same meaning; the '
    + 'destructor then follows the convention';
  R_DTOR_HINT = 'the parent destructor now runs at the end and frees the '
    + 'inherited fields';
  R_RESULT_INIT_HINT = 'Result now starts empty instead of with the old '
    + 'content of the caller''s target variable';
  // SCA014 (Charge Q14, E28): die Inline-Konstante haelt die Bedeutung des
  // Literals (E26); den vorlaeufigen Namen benennt der Benutzer selbst um -
  // keine Sync-Edit-Sitzung der Hilfe, und auch kein Rat dazu: Esc
  // zerstoert im Sync Edit Text (UI-Test 2026-10-11), Strg+Umschalt+J
  // braucht eine Markierung (Gegen-Review Q14, Minor 13). Die Taste nennt
  // die Uebersetzung so, wie die IDE ihrer Sprache sie beschriftet (de
  // 'Strg+Umschalt+E').
  R_MAGIC_HINT = 'same meaning - the constant %s holds the literal; rename it '
    + 'by hand or with Refactor > Rename (Ctrl+Shift+E)';
  // SCA014 auf einem Netzlaufwerk: die Hilfe liest dort keine Projekt- und
  // Include-Dateien (Gegen-Review Q14, Verdacht e; UNC prueft FileReason).
  // Das Ende ('by hand') kommt als %s aus uRdxText (MsgByHand), der
  // Trenner '; ' davor bleibt im Satz.
  R_MAGIC_REMOTE = 'network drive %s - the quick fix reads no project or '
    + 'include files there (the menu is built in the main thread); %s';
  // SCA147/SCA164 auf einem Netzpfad bzw. Netzlaufwerk (Review FB, R2-07):
  // dieselbe Regel wie SCA014 - FileExists auf einer nicht erreichbaren
  // Freigabe blockierte den IDE-Hauptthread (Gegen-Review R4-03: 2,5 bis
  // 16 s je Aufruf). Je Dateiart, die die Hilfe lesen wollte, ein ganzer
  // Satz (E29: kein Nomen als %s - bis Charge G7 'liest dort keine %s'
  // mit WHAT_FORMS/WHAT_INCLUDES); das Ende wie bei R_MAGIC_REMOTE.
  R_REMOTE_FORMS = 'network path %s - the quick fix reads no form files '
    + 'there (the menu is built in the main thread); %s';
  R_REMOTE_INCLUDES = 'network path %s - the quick fix reads no include '
    + 'files there (the menu is built in the main thread); %s';
  // SCA001: nur diese Variante bekommt die Hilfe (Feld TLeakFinding.
  // LeakVariant, das uLeakDetector2 setzt; properties.variant im SARIF).
  LEAK_VARIANT_FOF = 'freed-outside-finally';
  R_NO_FINDING = 'no finding';
  R_NO_ROW     = 'no simple quick fix for this rule';
  // Entscheid E2: eine Hilfe, die das Verhalten aendern kann, sagt es.
  CAP_CHANGES  = '(changes behavior)';
  NAME_UNKNOWN = 'X';

{ ---- Das Geruest der Planer-Adapter (Charge H5c) ----
  Gegen-Review H5, Major 2: bis Charge H5c stand das Geruest - Code-Sicht
  oeffnen, Planer rufen, Name, Grund und Ersetzungen uebernehmen, gesperrt
  ohne Ersetzungen - je Plan-Form einmal: FlowFix (uRdxRecipeRunner),
  RoutineFix, TryFix und ResultFix (hier). Jetzt EIN Geruest
  (TRdxFixFrame.Run); je Plan-Form steht nur noch, was sie unterscheidet
  (TRdxPlanForm): wie Name und Ersetzungen aus dem Plan kommen (Parts),
  eine Pruefung nach dem Angebot (Check) und ob der Quellstellen-Dienst
  offen sein muss (NeedsOpen). Generisch, weil die Planer-Units ihre
  Plan-Records behalten (sie laufen im FPC-Pruefstand); diese Unit
  uebersetzt nur Delphi (reDelphix.Test), nicht der Pruefstand. Bewusst
  NICHT im Geruest: MapFix (uRdxFixRunner) - der Laeufer braucht es
  selbst (ExplicitTObjectFix, EmptySectionFix), und seine Planer liefern
  genau eine Ersetzung ohne Plan-Record.
  Delphi-Regeln dazu: freie generische Funktionen gibt es nicht - Run ist
  eine generische Klassenmethode; die Typen stehen im implementation-Teil
  (E2506: ein Generic des interface-Teils duerfte keine Symbole des
  implementation-Teils nutzen); Planer, Parts und Check sind schlichte
  Funktionszeiger (kein 'of object', keine anonyme Methode, die etwas
  einfaengt) - die statischen Klassenmethoden der Planer-Units passen
  unmittelbar hinein. ---- }

type
  // Die Form eines Planers auf der Code-Sicht: ein Plan oder der Grund;
  // True genau dann, wenn AReason = '' (so alle Planer der Tabelle).
  TRdxPlannerOf<TPlan> = function(AMap: TRdxCodeMap; ALine: Integer;
    const AMessage: string; out APlan: TPlan; out AReason: string): Boolean;
  // Name (Menuetext) und Ersetzungen eines Plans in das Ergebnis.
  TRdxPlanPartsOf<TPlan> = procedure(const APlan: TPlan;
    var AOutcome: TRdxFixOutcome);
  // Die Pruefung nach einem Angebot, solange die Code-Sicht offen ist; ''
  // oder der Grund.
  TRdxPlanCheckOf<TPlan> = function(APlaces: TSourcePlaces;
    AMap: TRdxCodeMap; AFinding: TLeakFinding; const APlan: TPlan): string;

  // Eine Plan-Form: Planer, Parts, Check (nil = keiner) und ob der
  // Quellstellen-Dienst offen sein muss (SCA098/SCA080/SCA047 - bis Charge
  // H5c OpenMapFor in FlowFix).
  TRdxPlanForm<TPlan> = record
    Planner   : TRdxPlannerOf<TPlan>;
    Parts     : TRdxPlanPartsOf<TPlan>;
    Check     : TRdxPlanCheckOf<TPlan>;
    NeedsOpen : Boolean;
  end;

  // Das Geruest.
  TRdxFixFrame = class
  public
    // Ohne Zeilen bzw. (NeedsOpen) ohne offenen Quellstellen-Dienst:
    // MsgNoFileOpen (uRdxText). Sonst der Planer auf der Code-Sicht, Name
    // und Ersetzungen per Parts, nach einem Angebot der Check; gesperrt
    // ohne Ersetzungen. Den Plan bekommt der Aufrufer in APlan
    // (Kennzeichnung, Variants).
    class function Run<TPlan>(const AForm: TRdxPlanForm<TPlan>;
      APlaces: TSourcePlaces; ALines: TStrings; AFinding: TLeakFinding;
      out APlan: TPlan): TRdxFixOutcome; static;
  end;

class function TRdxFixFrame.Run<TPlan>(const AForm: TRdxPlanForm<TPlan>;
  APlaces: TSourcePlaces; ALines: TStrings; AFinding: TLeakFinding;
  out APlan: TPlan): TRdxFixOutcome;
var
  Map : TRdxCodeMap;
begin
  Result := Default(TRdxFixOutcome);
  APlan := Default(TPlan);
  Result.Reason := MsgNoFileOpen;
  if not Assigned(ALines) then Exit;
  if AForm.NeedsOpen and not (Assigned(APlaces) and APlaces.IsOpen) then
    Exit;
  Map := TRdxCodeMap.Create(ALines);
  try
    Result.Enabled := AForm.Planner(Map, AFinding.LineInt, AFinding.Message,
      APlan, Result.Reason);
    AForm.Parts(APlan, Result);
    if Result.Enabled and Assigned(AForm.Check) then
      Result.Reason := AForm.Check(APlaces, Map, AFinding, APlan);
  finally
    Map.Free;
  end;
  Result.Enabled := Result.Enabled and (Result.Reason = '');
  if not Result.Enabled then
    Result.Edits := nil;
end;

// Parts je Plan-Form: der Name fuer den Menuetext und die Ersetzungen
// (gesperrt leert Run sie wieder).
procedure FlowParts(const APlan: TRdxFlowPlan; var AOutcome: TRdxFixOutcome);
begin
  AOutcome.Name := APlan.Target;
  AOutcome.Edits := TArray<TRdxEdit>.Create(APlan.Edit);
end;

procedure RoutineParts(const APlan: TRdxRoutinePlan;
  var AOutcome: TRdxFixOutcome);
begin
  AOutcome.Name := APlan.Name;
  AOutcome.Edits := APlan.Edits;
end;

procedure TryParts(const APlan: TRdxTryPlan; var AOutcome: TRdxFixOutcome);
begin
  AOutcome.Name := APlan.Name;
  AOutcome.Edits := TArray<TRdxEdit>.Create(APlan.Edit);
end;

procedure ResultParts(const APlan: TRdxResultPlan;
  var AOutcome: TRdxFixOutcome);
begin
  AOutcome.Name := APlan.Name;
  AOutcome.Edits := APlan.Edits;
end;

// SCA014: der Menuetext nennt die Zahl (schon, wenn der Planer ablehnt),
// den Namen der Konstante nennt der Hinweis.
procedure MagicParts(const APlan: TRdxMagicPlan; var AOutcome: TRdxFixOutcome);
begin
  AOutcome.Name := APlan.Value;
  AOutcome.Edits := APlan.Edits;
end;

// SCA098: X und (in der Gegenrichtung) die Bedingung als Boolean bewiesen
// (CondAssignReason, uRdxFixRunner).
function CondCheck(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  AFinding: TLeakFinding; const APlan: TRdxFlowPlan): string;
begin
  Result := CondAssignReason(APlaces, AMap, AFinding.LineInt, APlan);
end;

// SCA047 prueft das Ziel des Plans (SelfAssignReason nimmt den Namen).
function SelfAssignCheck(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  AFinding: TLeakFinding; const APlan: TRdxFlowPlan): string;
begin
  Result := SelfAssignReason(APlaces, AMap, AFinding.LineInt, APlan.Target);
end;

// SCA014: liegt die Datei auf einem Netzlaufwerk (uRdxPaths.RemoteDriveOf,
// seit Charge B2S-a auch lang geschrieben: '\\?\Z:\..')? Dann liest die
// Hilfe nichts von der Platte - der Menueaufbau laeuft im Hauptthread
// (Gegen-Review Q14, Verdacht e; UNC prueft TRdxMagicFixes.FileReason).
function RemoteDriveReason(const AFileName: string): string;
var
  Drive : string;
begin
  Result := '';
  Drive := RemoteDriveOf(AFileName);
  if Drive <> '' then
    Result := _(R_MAGIC_REMOTE, [Drive, MsgByHand]);
end;

// SCA147/SCA164 (Review FB, R2-07): liegt die Unit im Netz
// (uRdxPaths.IsNetworkPath: UNC, auch mit '/' oder als '\\?\UNC\..', oder
// ein Netzlaufwerk; '\\?\C:\..' ist lokal)? Dann liest die Hilfe dort
// nichts - dieselbe Regel wie SCA014. APlace ist der Ort fuer den Grund:
// das Netzlaufwerk bzw. das Verzeichnis ohne Namensraum-Vorsatz. Bis
// Charge G7 NetworkPathReason mit dem Nomen der Dateiart als %s - jetzt
// setzt der Grund je Art (RemoteFormsReason, RemoteIncludesReason) den Ort
// in seinen eigenen Satz (E29).
function NetworkPlaceOf(const AFileName: string; out APlace: string): Boolean;
var
  Path : string;
begin
  APlace := '';
  Result := IsNetworkPath(AFileName);
  if not Result then Exit;
  Path := WithoutNamespacePrefix(AFileName);
  APlace := RemoteDriveOf(Path);
  if APlace = '' then
    APlace := ExtractFileDir(Path);
end;

// SCA147: die Formdateien neben einer Unit im Netz liest die Hilfe nicht
// (NetworkPlaceOf). '' oder der Grund.
function RemoteFormsReason(const AFileName: string): string;
var
  Place : string;
begin
  Result := '';
  if NetworkPlaceOf(AFileName, Place) then
    Result := _(R_REMOTE_FORMS, [Place, MsgByHand]);
end;

// SCA164 (und SCA147 mit Includes im Plan): die Include-Dateien neben einer
// Unit im Netz liest die Hilfe nicht (NetworkPlaceOf). '' oder der Grund.
function RemoteIncludesReason(const AFileName: string): string;
var
  Place : string;
begin
  Result := '';
  if NetworkPlaceOf(AFileName, Place) then
    Result := _(R_REMOTE_INCLUDES, [Place, MsgByHand]);
end;

// SCA164: die Include-Dateien vor implementation liest die Hilfe von der
// Platte neben der Unit (Gegen-Review H3, Minor 4) - sie koennen die
// Routine deklarieren oder rufen; nicht gefunden heisst keine Hilfe. Nur,
// wenn der Plan welche nennt (seit Charge B1-FD auch der von SCA147), und
// nicht auf einem Netzpfad (RemoteIncludesReason, R2-07).
function IncludeCheck(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  AFinding: TLeakFinding; const APlan: TRdxRoutinePlan): string;
begin
  Result := '';
  if Length(APlan.Includes) = 0 then Exit;
  Result := RemoteIncludesReason(AFinding.FileName);
  if Result = '' then
    Result := TRdxRoutineFixes.IncludeReason(AFinding.FileName,
      APlan.Includes, APlan.Name);
end;

// SCA014: was nur die Platte weiss - Netzlaufwerk, Lazarus-Dateiart oder
// -Projekt bzw. altes Delphi-Projekt neben der Unit, die Compiler-Weichen
// ihrer Includes (TRdxMagicFixes).
function MagicCheck(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  AFinding: TLeakFinding; const APlan: TRdxMagicPlan): string;
begin
  Result := RemoteDriveReason(AFinding.FileName);
  if Result = '' then
    Result := TRdxMagicFixes.FileReason(AFinding.FileName);
  if Result = '' then
    Result := TRdxMagicFixes.IncludeReason(AFinding.FileName, AMap);
end;

// Die Plan-Formen der Tabelle.
// SCA098, SCA080, SCA047 (Charge H2): mit offenem Quellstellen-Dienst,
// ACheck danach (nil = keiner) - Typen, with-Bloecke. Name ist das Ziel
// bzw. Exit/Continue.
function FlowForm(APlanner: TRdxPlannerOf<TRdxFlowPlan>;
  ACheck: TRdxPlanCheckOf<TRdxFlowPlan>): TRdxPlanForm<TRdxFlowPlan>;
begin
  Result.Planner := APlanner;
  Result.Parts := FlowParts;
  Result.Check := ACheck;
  Result.NeedsOpen := True;
end;

// SCA164, SCA147 (Charge H3b): alle Ersetzungen (Deklaration und
// Implementierung bzw. forward und Rumpf) in EINEM Undo-Schritt, Name die
// Routine bzw. Methode, danach die Include-Dateien (IncludeCheck).
function RoutineForm(
  APlanner: TRdxPlannerOf<TRdxRoutinePlan>): TRdxPlanForm<TRdxRoutinePlan>;
begin
  Result.Planner := APlanner;
  Result.Parts := RoutineParts;
  Result.Check := IncludeCheck;
  Result.NeedsOpen := False;
end;

// SCA009, SCA001, SCA109, SCA153, SCA156 (Charge H4): eine Ersetzung von
// der Zeile von A bis zur Freigabe; Name X, die Sperre bzw. der Puffer -
// schon aus der Meldung, auch wenn der Planer ablehnt.
function TryForm(
  APlanner: TRdxPlannerOf<TRdxTryPlan>): TRdxPlanForm<TRdxTryPlan>;
begin
  Result.Planner := APlanner;
  Result.Parts := TryParts;
  Result.Check := nil;
  Result.NeedsOpen := False;
end;

// SCA096, SCA097, SCA121, SCA196 (Charge H5): eine Ersetzung (SCA097: zwei,
// wenn der letzten Anweisung das ';' fehlt); Kennzeichnung nach dem Fund
// und der Bedarf an Variants kommen mit dem Plan.
function ResultForm(
  APlanner: TRdxPlannerOf<TRdxResultPlan>): TRdxPlanForm<TRdxResultPlan>;
begin
  Result.Planner := APlanner;
  Result.Parts := ResultParts;
  Result.Check := nil;
  Result.NeedsOpen := False;
end;

// SCA014 (Charge Q14): eine Ersetzung (Deklaration davor, das Literal
// ersetzt, bei einem Zweig begin..end), Name die Zahl, danach MagicCheck.
function MagicForm(
  APlanner: TRdxPlannerOf<TRdxMagicPlan>): TRdxPlanForm<TRdxMagicPlan>;
begin
  Result.Planner := APlanner;
  Result.Parts := MagicParts;
  Result.Check := MagicCheck;
  Result.NeedsOpen := False;
end;

{ ---- Die Planer je Art: Adapter auf die Rumpf-Routinen, alle in der Form
  TRdxFixPlanner (Zeile und Meldung aus dem Fund). ---- }

function PlanExplicitTObject(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := TRdxFixRunner.ExplicitTObjectFix(ALines, AFinding.LineInt,
    AFinding.Message);
end;

// X aus der SCA085-Meldung '`X.Free; X := nil;` - prefer ...'; '' ohne
// diese Form.
function FreeTargetOf(const AMessage: string): string;
var
  P, Q : Integer;
begin
  Result := '';
  P := Pos('`', AMessage);
  if P = 0 then Exit;
  Q := Pos('.Free', AMessage, P + 1);
  if Q = 0 then Exit;
  Result := Trim(Copy(AMessage, P + 1, Q - P - 1));
end;

function PlanFreeAndNil(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  Named : string;
begin
  Result := TRdxFixRunner.FreeAndNilFix(APlaces, ALines, AFinding.LineInt,
    AUsesNames);
  // Gegenprobe gegen den Fund wie bei SCA044/SCA003 (Minor 20, hier Nit
  // 26): die Meldung nennt X ('`X.Free; X := nil;` - ...'). Steht nach
  // Einfuegungen oberhalb ein anderes Paar auf der Zeile, nicht umschreiben.
  Named := FreeTargetOf(AFinding.Message);
  if Result.Enabled and (Named <> '')
     and not SameText(TRdxRecipes.AsciiOnly(Named),
                      TRdxRecipes.AsciiOnly(Result.Name)) then
  begin
    Result.Enabled := False;
    Result.Edits   := nil;
    Result.Reason  := MsgMovedSuffix(_('line %d carries %s.Free, the '
      + 'finding names %s', [AFinding.LineInt, Result.Name, Named]));
  end;
end;

function PlanNilComparison(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := TRdxFixRunner.NilComparisonFix(APlaces, ALines, AFinding.LineInt);
end;

function PlanAssertMessage(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := TRdxFixRunner.AssertMessageFix(APlaces, ALines, AFinding.LineInt,
    AFinding.Message);
end;

function PlanEmptySection(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := TRdxFixRunner.EmptySectionFix(ALines, AFinding.LineInt,
    AFinding.Message);
end;

function PlanFreeWithoutNil(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := TRdxFixRunner.FreeWithoutNilFix(APlaces, ALines, AFinding.LineInt,
    AFinding.Message, AUsesNames);
end;

function PlanEmptyArgs(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := TRdxFixRunner.EmptyArgsFix(APlaces, ALines, AFinding.LineInt,
    AFinding.Message);
end;

// SCA072 und SCA084 - OperandFix unterscheidet die Art selbst.
function PlanOperand(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := TRdxFixRunner.OperandFix(AFinding.Kind, APlaces, ALines,
    AFinding.LineInt, AFinding.Message);
end;

function PlanUnusedUses(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := TRdxFixRunner.UnusedUsesFix(APlaces, ALines, AFinding.LineInt,
    AFinding.Message);
end;

function PlanCaseElse(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := TRdxFixRunner.CaseElseFix(APlaces, ALines, AFinding.LineInt);
end;

function PlanCaseRaise(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := TRdxFixRunner.CaseRaiseFix(APlaces, ALines, AFinding.LineInt,
    AUsesNames);
end;

// SCA101 und SCA099 - BlockFix unterscheidet die Art selbst.
function PlanBlock(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := TRdxFixRunner.BlockFix(AFinding.Kind, ALines, AFinding.LineInt,
    AFinding.Message);
end;

function PlanDoubleSemicolon(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxLineFixes.DoubleSemicolon);
end;

function PlanKeywordIndent(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxLineFixes.KeywordIndent);
end;

// LegacyInit braucht die Meldung nicht - die Form von TRdxMapPlanner schon.
function LegacyInitOnMap(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
begin
  Result := TRdxLineFixes.LegacyInit(AMap, ALine, AEdit, AReason);
end;

function PlanLegacyInit(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message, LegacyInitOnMap);
end;

function PlanCastFree(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := CastFreeFix(APlaces, ALines, AFinding.LineInt, AFinding.Message);
end;

// SCA020, erster Eintrag: der Absichtskommentar (EmptyBody ohne Anweisung).
function EmptyIntentOnMap(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
begin
  Result := TRdxRaiseFixes.EmptyBody(AMap, ALine, '', AEdit, AReason);
end;

function PlanEmptyIntent(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message, EmptyIntentOnMap);
end;

function PlanEmptyRaise(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := EmptyRaiseFix(APlaces, ALines, AFinding.LineInt, AUsesNames);
end;

function PlanMissingRaise(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxRaiseFixes.MissingRaise);
end;

function PlanReRaise(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxRaiseFixes.ReRaise);
end;

function PlanDocSkeleton(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxDeclFixes.DocSkeleton);
end;

function PlanInterfaceGuid(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxDeclFixes.InterfaceGuid);
end;

// SCA149 nach dem Rat der Meldung (TRdxDeclFixes.DirectiveFor): Name traegt
// die Direktive (Menuetext); nur override aendert das Verhalten (E2) und
// bekommt den Hinweis dazu - nie reintroduce als zweiter Eintrag:
// Strg+Alt+F liesse das gekennzeichnete override aus und deckte den
// Polymorphie-Fehler mit reintroduce still zu.
function PlanMissingOverride(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxDeclFixes.MethodDirective);
  Result.Name := TRdxDeclFixes.DirectiveFor(AFinding.Message);
  Result.ChangesBehavior := Result.Name = DIRECTIVE_OVERRIDE;
  if not Result.Enabled then Exit;
  if Result.ChangesBehavior then
    Result.Hint := _(R_OVERRIDE_HINT)
  else
    Result.Hint := _(R_REINTRODUCE_HINT);
end;

function PlanRedundantConditional(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxFlowPlan;
begin
  Result := TRdxFixFrame.Run<TRdxFlowPlan>(
    FlowForm(TRdxFlowFixes.RedundantConditional, CondCheck),
    APlaces, ALines, AFinding, P);
end;

function PlanRedundantJump(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxFlowPlan;
begin
  Result := TRdxFixFrame.Run<TRdxFlowPlan>(
    FlowForm(TRdxFlowFixes.RedundantJump, nil),
    APlaces, ALines, AFinding, P);
end;

function PlanSelfAssignment(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxFlowPlan;
begin
  Result := TRdxFixFrame.Run<TRdxFlowPlan>(
    FlowForm(TRdxFlowFixes.SelfAssignment, SelfAssignCheck),
    APlaces, ALines, AFinding, P);
end;

function PlanUnusedRoutine(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxRoutinePlan;
begin
  Result := TRdxFixFrame.Run<TRdxRoutinePlan>(
    RoutineForm(TRdxRoutineFixes.UnusedRoutine),
    APlaces, ALines, AFinding, P);
end;

// SCA147: bindet die Formdatei neben der Unit (.dfm/.fmx/.lfm) die Methode
// per Name an ein Ereignis ('OnClick = AName')? Die Hilfe sieht sonst nur
// den Puffer; der Detektor prueft nur .dfm (und .lfm im FPC-Dialekt).
// Gelesen wird die Platte - ein im Designer neu gesetztes Ereignis traegt
// die IDE in den published-Teil ein, nicht unter private. Auf einem
// Netzpfad liest die Hilfe nichts (der Aufrufer prueft RemoteFormsReason
// vorher, R2-07). '' oder Grund.
function FormReason(const AUnitFile, AName: string): string;
var
  Ext, Form : string;
  SL        : TStringList;
begin
  Result := '';
  if AUnitFile = '' then Exit;
  for Ext in FORM_EXTENSIONS do
  begin
    Form := ChangeFileExt(AUnitFile, Ext);
    if not FileExists(Form) then Continue;
    SL := TStringList.Create;
    try
      // Oeffnen/Lesen (EStreamError: EFOpenError, EReadError) und die
      // Kodierung (EEncodingError) - alles andere ist kein Lesefehler.
      try
        SL.LoadFromFile(Form);
      except
        on E: EStreamError do
          Exit(_(R_FORM_UNREADABLE, [ExtractFileName(Form), E.Message]));
        on E: EEncodingError do
          Exit(_(R_FORM_UNREADABLE, [ExtractFileName(Form), E.Message]));
      end;
      if TRdxRoutineFixes.FormNamesMethod(SL.Text, AName) then
        Exit(_('the form file %s names %s - bound to an event by name',
          [ExtractFileName(Form), AName]));
    finally
      SL.Free;
    end;
  end;
end;

function PlanUnusedPrivateMethod(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxRoutinePlan;
begin
  Result := TRdxFixFrame.Run<TRdxRoutinePlan>(
    RoutineForm(TRdxRoutineFixes.UnusedPrivateMethod),
    APlaces, ALines, AFinding, P);
  if not Result.Enabled then Exit;
  Result.Reason := RemoteFormsReason(AFinding.FileName);
  if Result.Reason = '' then
    Result.Reason := FormReason(AFinding.FileName, Result.Name);
  if Result.Reason = '' then Exit;
  Result.Enabled := False;
  Result.Edits := nil;
end;

// SCA070 (Charge H3a): die Region der Meldung (Zeilen, Spalte).
function PlanCommentedOut(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxCleanupFixes.CommentedOutCode);
end;

// SCA053 (Charge H3a): Name fuer den Menuetext aus der Meldung - auch,
// wenn der Planer ablehnt.
function PlanUnusedVar(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxCleanupFixes.UnusedLocalVar);
  Result.Name := TRdxCleanupFixes.UnusedVarName(AFinding.Message);
end;

function PlanMissingFinally(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxTryPlan;
begin
  Result := TRdxFixFrame.Run<TRdxTryPlan>(
    TryForm(TRdxTryFixes.MissingFinally),
    APlaces, ALines, AFinding, P);
end;

// SCA001: nur freed-outside-finally - das Free ist da, liegt aber neben dem
// finally. proven-leak (Konzept: eigene Hilfe, Aufwand L), never-freed und
// return-value-not-freed (Weitergabe bzw. Besitz unbekannt) bekommen keine;
// der Eintrag steht dann gesperrt mit der Variante da. Massgeblich ist das
// FELD LeakVariant (uLeakDetector2), nicht die Ableitung MemoryLeakVariant:
// die raet ohne Feld nach der Schwere (uFieldLeak hat lsError: never-freed)
// - heute liefern beide dasselbe (Gegen-Review H4, Minor 8).
function PlanMemoryLeak(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  LeakVar : string;
  P       : TRdxTryPlan;
begin
  if AFinding.LeakVariant = LEAK_VARIANT_FOF then
    Exit(TRdxFixFrame.Run<TRdxTryPlan>(
      TryForm(TRdxTryFixes.FreedOutsideFinally),
      APlaces, ALines, AFinding, P));
  LeakVar := AFinding.MemoryLeakVariant;
  Result := Default(TRdxFixOutcome);
  Result.Name := TRdxTryFixes.NameOf(AFinding.Message);
  Result.Reason := _('no quick fix for the variant %s - only for %s (Free '
    + 'present, but beside the finally)', [LeakVar, LEAK_VARIANT_FOF]);
end;

function PlanLockWithoutFinally(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxTryPlan;
begin
  Result := TRdxFixFrame.Run<TRdxTryPlan>(
    TryForm(TRdxTryFixes.LockWithoutFinally),
    APlaces, ALines, AFinding, P);
end;

function PlanUnpairedLock(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxTryPlan;
begin
  Result := TRdxFixFrame.Run<TRdxTryPlan>(
    TryForm(TRdxTryFixes.UnpairedLock),
    APlaces, ALines, AFinding, P);
end;

function PlanGetMemWithoutFree(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxTryPlan;
begin
  Result := TRdxFixFrame.Run<TRdxTryPlan>(
    TryForm(TRdxTryFixes.GetMemWithoutFree),
    APlaces, ALines, AFinding, P);
end;

// SCA096: 'inherited Create;' (direkter TObject-Erbe, bedeutungsgleich)
// bzw. 'inherited;' (override, gekennzeichnet) - wie SCA149 entscheidet der
// Planer, die Zeile traegt Hinweis und Kennzeichnung nicht fest.
function PlanCtorInherited(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxResultPlan;
begin
  Result := TRdxFixFrame.Run<TRdxResultPlan>(
    ResultForm(TRdxResultFixes.ConstructorInherited),
    APlaces, ALines, AFinding, P);
  Result.ChangesBehavior := P.Changes;
  if not Result.Enabled then Exit;
  if P.Changes then
    Result.Hint := _(R_CTOR_OVERRIDE_HINT)
  else
    Result.Hint := _(R_CTOR_TOBJECT_HINT);
end;

// SCA097: 'inherited;' am Ende - gekennzeichnet, ausser bei direktem
// TObject-Erben (TObject.Destroy ist leer).
function PlanDtorInherited(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxResultPlan;
begin
  Result := TRdxFixFrame.Run<TRdxResultPlan>(
    ResultForm(TRdxResultFixes.DestructorInherited),
    APlaces, ALines, AFinding, P);
  Result.ChangesBehavior := P.Changes;
  if not Result.Enabled then Exit;
  if P.Changes then
    Result.Hint := _(R_DTOR_HINT)
  else
    Result.Hint := _(R_DTOR_TOBJECT_HINT);
end;

// SCA121: 'Result := <Wert>;' als erste Anweisung - ein Literal oder
// Default(T), Name ist der Wert (Menuetext 'Initialize Result with %s').
// Hinweis und Kennzeichnung setzt die Zeile fest (immer gekennzeichnet:
// Result ist danach definiert statt zufaellig); den Plan selbst braucht
// der Adapter nicht.
function PlanResultDefault(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxResultPlan;
begin
  Result := TRdxFixFrame.Run<TRdxResultPlan>(
    ResultForm(TRdxResultFixes.ResultDefault),
    APlaces, ALines, AFinding, P);
end;

// SCA196: VarClear (Variant/OleVariant) braucht unter FPC die Unit Variants
// (Delphi kennt es auch ohne; die Unit bringt ohnehin jede Variant-
// Operation mit) - fehlt sie in uses, kommt sie mit (AppendUses, wie
// SysUtils bei FreeAndNil).
function PlanManagedResult(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxResultPlan;
begin
  Result := TRdxFixFrame.Run<TRdxResultPlan>(
    ResultForm(TRdxResultFixes.ManagedResultInit),
    APlaces, ALines, AFinding, P);
  if not Result.Enabled then Exit;
  Result.Hint := _(R_RESULT_INIT_HINT);
  if P.NeedsVariants then
    Result.Enabled := AppendUses(APlaces, AUsesNames, 'Variants',
      'System.Variants', Result);
end;

// SCA014: 'const MagicNr01 = 200;' vor der Anweisung, das Literal der
// if-Bedingung durch den Namen; der Hinweis nennt den Namen.
function PlanMagicNumber(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxMagicPlan;
begin
  Result := TRdxFixFrame.Run<TRdxMagicPlan>(
    MagicForm(TRdxMagicFixes.MagicNumber),
    APlaces, ALines, AFinding, P);
  if Result.Enabled then
    Result.Hint := _(R_MAGIC_HINT, [P.Name]);
end;

{ ---- Die Tabelle ---- }

const
  FIX_ROW_HIGH = 39;

  // Je Art eine Zeile; die Reihenfolge ist die der Chargen (Stufe 2a,
  // Stufe 2 Rest, uQuickFix-Umzug/Stufe 3, Zeilen, Ausnahmen, Deklarationen
  // H1, Anweisungen H2, Routinen H3b, Aufraeumen H3a, try/finally H4,
  // Ergebnis und Konstruktoren H5, Magic Number Q14). Der feste Hinweis
  // steht unter demselben Index in FIX_HINTS, der Menuetext in
  // FIX_CAPTIONS (s. Kopf).
  FIX_ROWS: array[0..FIX_ROW_HIGH] of TRdxFixRow = (
    (Kind: fkExplicitTObjectInheritance; Plan: PlanExplicitTObject;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkFreeAndNilHint; Plan: PlanFreeAndNil;
     HintByPlanner: True; Changes: False; Alt: nil),
    (Kind: fkNilComparison; Plan: PlanNilComparison;
     HintByPlanner: True; Changes: False; Alt: nil),
    (Kind: fkAssertMessage; Plan: PlanAssertMessage;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkEmptyVisibilitySection; Plan: PlanEmptySection;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkFreeWithoutNil; Plan: PlanFreeWithoutNil;
     HintByPlanner: True; Changes: False; Alt: nil),
    (Kind: fkEmptyArgumentList; Plan: PlanEmptyArgs;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkRedundantBoolean; Plan: PlanOperand;
     HintByPlanner: True; Changes: False; Alt: nil),
    (Kind: fkAssignedAndAssignedNil; Plan: PlanOperand;
     HintByPlanner: True; Changes: False; Alt: nil),
    // SCA007: der initialization-Abschnitt der Unit laeuft nicht mehr (E2).
    (Kind: fkUnusedUses; Plan: PlanUnusedUses;
     HintByPlanner: True; Changes: True; Alt: nil),
    (Kind: fkDefaultCaseInCaseStatement; Plan: PlanCaseElse;
     HintByPlanner: False; Changes: False; Alt: PlanCaseRaise),
    (Kind: fkBeginEndRequired; Plan: PlanBlock;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkIfElseBegin; Plan: PlanBlock;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkSuperfluousSemicolon; Plan: PlanDoubleSemicolon;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkUnitLevelKeywordIndent; Plan: PlanKeywordIndent;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkLegacyInitializationSection; Plan: PlanLegacyInit;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkCastAndFree; Plan: PlanCastFree;
     HintByPlanner: True; Changes: False; Alt: nil),
    (Kind: fkEmptyMethod; Plan: PlanEmptyIntent;
     HintByPlanner: False; Changes: False; Alt: PlanEmptyRaise),
    // SCA120: die Exception wird jetzt ausgeloest - das ist der Fix (E2).
    (Kind: fkMissingRaise; Plan: PlanMissingRaise;
     HintByPlanner: False; Changes: True; Alt: nil),
    (Kind: fkReRaiseException; Plan: PlanReRaise;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkPublicMemberWithoutDoc; Plan: PlanDocSkeleton;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkInterfaceWithoutGuid; Plan: PlanInterfaceGuid;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkMissingOverride; Plan: PlanMissingOverride;
     HintByPlanner: True; Changes: False; Alt: nil),
    (Kind: fkRedundantConditional; Plan: PlanRedundantConditional;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkRedundantJump; Plan: PlanRedundantJump;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkSelfAssignment; Plan: PlanSelfAssignment;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkUnusedRoutine; Plan: PlanUnusedRoutine;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkUnusedPrivateMethod; Plan: PlanUnusedPrivateMethod;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkCommentedOutCode; Plan: PlanCommentedOut;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkUnusedLocalVar; Plan: PlanUnusedVar;
     HintByPlanner: False; Changes: False; Alt: nil),
    // Charge H4: alle gekennzeichnet (E2) - Strg+Alt+F laesst sie aus.
    (Kind: fkMissingFinally; Plan: PlanMissingFinally;
     HintByPlanner: False; Changes: True; Alt: nil),
    (Kind: fkMemoryLeak; Plan: PlanMemoryLeak;
     HintByPlanner: False; Changes: True; Alt: nil),
    (Kind: fkLockWithoutTryFinally; Plan: PlanLockWithoutFinally;
     HintByPlanner: False; Changes: True; Alt: nil),
    (Kind: fkUnpairedLock; Plan: PlanUnpairedLock;
     HintByPlanner: False; Changes: True; Alt: nil),
    (Kind: fkGetMemWithoutFreeMem; Plan: PlanGetMemWithoutFree;
     HintByPlanner: False; Changes: True; Alt: nil),
    // Charge H5: SCA096/SCA097 kennzeichnet der Planer nach dem Fund (wie
    // SCA149), SCA121/SCA196 immer.
    (Kind: fkConstructorWithoutInherited; Plan: PlanCtorInherited;
     HintByPlanner: True; Changes: False; Alt: nil),
    (Kind: fkDestructorWithoutInherited; Plan: PlanDtorInherited;
     HintByPlanner: True; Changes: False; Alt: nil),
    (Kind: fkRoutineResultUnassigned; Plan: PlanResultDefault;
     HintByPlanner: False; Changes: True; Alt: nil),
    (Kind: fkManagedResultUninit; Plan: PlanManagedResult;
     HintByPlanner: True; Changes: True; Alt: nil),
    // Charge Q14: bedeutungsgleich (E26), den Hinweis setzt der Adapter
    // (Name der Konstante).
    (Kind: fkMagicNumber; Plan: PlanMagicNumber;
     HintByPlanner: True; Changes: False; Alt: nil)
  );

  // Die festen Hinweise (englische msgids) unter dem Index der Zeile;
  // '' genau bei HintByPlanner - FixFor uebersetzt mit _(FIX_HINTS[i]),
  // nie _('') (die msgid '' ist der Kopf der .po). Bis Charge G7 als
  // Feld Hint der Zeile (deutsch) - fuer tools/i18n_extract.py
  // unsichtbar (s. Kopf). SCA075, SCA074, SCA087 und SCA066 haben ihren
  // festen Hinweis seit der Tabelle (Charge R8; bis dahin leer, der
  // Eintrag stand ohne Erklaerung im Menue - Gegen-Review R8, Major 1).
  FIX_HINTS: array[0..FIX_ROW_HIGH] of string = (
    'TObject is the ancestor anyway - same meaning',
    '',
    '',
    'the condition as text - so the message names what failed',
    'the section was empty - same meaning',
    '',
    'same meaning - Delphi calls the routine without parentheses too',
    '',
    '',
    '',
    'all other values: do nothing (as before)',
    'same meaning - only the form; a further statement then visibly belongs '
      + 'to the branch',
    'same meaning - only the form; a further statement then visibly belongs '
      + 'to the branch',
    'the second ";" was an empty statement',
    'whitespace only',
    'same meaning - the section can then get a finalization',
    '',
    'the intent is in the body - a reason after it helps the next reader',
    'the exception is now raised - the code after it no longer runs in the '
      + 'error case',
    'the same exception - the original stack trace is kept',
    'the skeleton is empty - fill in summary, param and returns',
    'a new GUID - only for your own interfaces, never for COM imports',
    '',
    'same meaning - one assignment instead of two branches',
    'same meaning - the control flow leaves the block anyway',
    'the assignment has no effect - if another value was meant (typo), it is '
      + 'still missing',
    'same meaning - the name appears nowhere else in the code of the file; '
      + 'documentation and a comment above it that names the routine go '
      + 'with it',
    'same meaning - declaration and implementation go, the name appears '
      + 'nowhere else in the code of the file',
    'same meaning - only a comment is removed; version control still knows it',
    'same meaning - the variable appears nowhere else',
    // Charge H4 (try/finally): alle gekennzeichnet (E2) - B laeuft danach
    // auch dort, wo es bisher uebersprungen wurde; das ist der Fix.
    'Free now also runs on an exception and on Exit - the lines in between '
      + 'move into the try part',
    'Free now also runs on an exception and on Exit - the lines in between '
      + 'move into the try part',
    'the lock is now also released on an exception - the lines in between '
      + 'move into the try part',
    'the lock is now also released on an exception - the lines in between '
      + 'move into the try part',
    'FreeMem now also runs on an exception and on Exit - the lines in between '
      + 'move into the try part',
    '',
    '',
    // SCA121: der Wert ist ein Literal (0, False, '''', nil ...) oder
    // Default(T) (Charge H5c); der Menuetext nennt ihn. Bis Charge FB hiess
    // es '(wie Default(T))' - das stimmt nicht, wenn ein Member wie der
    // erste Aufzaehlungswert heisst (Gegen-Review R5-06, Fall 2; Absprache
    // mit FE: der Text muss fuer Literal UND Default(T) stimmen).
    'Result now starts with the named value instead of a random one - later '
      + 'assignments still apply',
    '',
    ''
  );

  // Menuetexte (msgids) unter dem Index der Zeile; '%s' = Name der Hilfe
  // (X bei SCA085/SCA139, die Unit bei SCA007, der Cast-Typ bei SCA123, die
  // Direktive bei SCA149, das Ziel bzw. Exit/Continue bei SCA098/SCA047/
  // SCA080, die Routine bzw. Methode bei SCA164/SCA147, die Variable bei SCA053,
  // X bzw. die Sperre bzw. der Puffer bei SCA009/SCA001/SCA109/SCA153/SCA156,
  // die Anweisung bei SCA096/SCA196, der Wert bei SCA121 - ein Literal oder
  // Default(T), Charge H5c; die Zahl bei SCA014, Charge Q14).
  FIX_CAPTIONS: array[0..FIX_ROW_HIGH] of string = (
    'Remove (TObject) from the class declaration',
    'Use FreeAndNil(%s)',
    'Use Assigned() instead of comparing with nil',
    'Use the condition as the Assert message',
    'Remove the empty visibility section',
    'Use FreeAndNil(%s)',
    'Remove the empty parentheses',
    'Remove the redundant comparison with True/False',
    'Remove the redundant comparison with nil',
    'Remove unit %s from uses',
    'Add an empty else branch',
    'Put the branch in begin..end',
    'Put the branch in begin..end',
    'Remove the extra semicolon',
    'Move the keyword to column 1',
    'Replace begin with initialization',
    'Remove the cast to %s before Free',
    'Mark the empty body as intentional',
    'Raise the exception',
    'Use raise; to keep the original stack trace',
    'Insert a documentation skeleton',
    'Insert a new GUID',
    'Add "%s;" to the declaration',
    'Assign the condition to %s directly',
    'Remove the redundant %s',
    'Remove the self-assignment of %s',
    'Delete unused routine %s',
    'Delete unused private method %s',
    'Delete commented-out code',
    'Remove unused variable %s',
    'Free %s in a try/finally block',
    'Free %s in a try/finally block',
    'Release the lock %s in a try/finally block',
    'Release the lock %s in a try/finally block',
    'Free the buffer %s in a try/finally block',
    'Call %s first in the constructor',
    'Call inherited last in the destructor',
    'Initialize Result with %s',
    'Initialize Result first: %s',
    'Introduce local constant for %s'
  );

  // Menuetexte des zweiten Eintrags (Alt), '' ohne.
  FIX_ALT_CAPTIONS: array[0..FIX_ROW_HIGH] of string = (
    '', '', '', '', '', '', '', '', '', '',
    'Add an else branch that raises an exception',
    '', '', '', '', '', '',
    'Raise ENotImplemented in the empty body',
    '', '', '', '', '', '', '', '', '', '', '', '',
    '', '', '', '', '', '', '', '', '', ''
  );

var
  // Index der Zeile je Art, -1 ohne - einmal in der initialization gebaut.
  GRowIndex : array[TFindingKind] of Integer;

{ TRdxFixTable }

class function TRdxFixTable.Handles(AKind: TFindingKind): Boolean;
begin
  Result := GRowIndex[AKind] >= 0;
end;

class function TRdxFixTable.RowCount: Integer;
begin
  Result := Length(FIX_ROWS);
end;

class function TRdxFixTable.Row(AIndex: Integer): TRdxFixRow;
begin
  Result := FIX_ROWS[AIndex];
end;

class function TRdxFixTable.RawCaption(AIndex, AVariant: Integer): string;
begin
  if AVariant = 1 then
    Result := FIX_ALT_CAPTIONS[AIndex]
  else
    Result := FIX_CAPTIONS[AIndex];
end;

class function TRdxFixTable.RawHint(AIndex: Integer): string;
begin
  Result := FIX_HINTS[AIndex];
end;

class function TRdxFixTable.FixFor(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  Idx : Integer;
begin
  Result := Default(TRdxFixOutcome);
  if not Assigned(AFinding) then
  begin
    Result.Reason := _(R_NO_FINDING);
    Exit;
  end;
  Idx := GRowIndex[AFinding.Kind];
  if Idx < 0 then
  begin
    Result.Reason := _(R_NO_ROW);
    Exit;
  end;
  Result := FIX_ROWS[Idx].Plan(APlaces, ALines, AFinding, AUsesNames);
  // Nie _('') - die msgid '' ist der Kopf der .po (HintByPlanner: '').
  if Result.Enabled and (Result.Hint = '') and (FIX_HINTS[Idx] <> '') then
    Result.Hint := _(FIX_HINTS[Idx]);
  // Auch gesperrt gekennzeichnet (wie bisher): der Eintrag steht mit Grund
  // im Menue und sagt, was er taete.
  Result.ChangesBehavior := Result.ChangesBehavior or FIX_ROWS[Idx].Changes;
end;

class function TRdxFixTable.AlternativeFixFor(APlaces: TSourcePlaces;
  ALines: TStrings; AFinding: TLeakFinding;
  const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  Idx : Integer;
begin
  Result := Default(TRdxFixOutcome);
  if not Assigned(AFinding) then Exit;
  Idx := GRowIndex[AFinding.Kind];
  if (Idx < 0) or not Assigned(FIX_ROWS[Idx].Alt) then Exit;
  Result := FIX_ROWS[Idx].Alt(APlaces, ALines, AFinding, AUsesNames);
end;

class function TRdxFixTable.CaptionFor(AKind: TFindingKind;
  const AOutcome: TRdxFixOutcome): string;
var
  Idx  : Integer;
  Name : string;
begin
  Result := '';
  Idx := GRowIndex[AKind];
  if Idx < 0 then Exit;
  // Nie _('') - die msgid '' ist der Kopf der .po.
  if RawCaption(Idx, AOutcome.Variant) = '' then Exit;
  if AOutcome.Variant = 1 then
    Result := _(FIX_ALT_CAPTIONS[Idx])
  else
    Result := _(FIX_CAPTIONS[Idx]);
  Name := AOutcome.Name;
  if Name = '' then Name := NAME_UNKNOWN;
  if Pos('%s', Result) > 0 then
    Result := Format(Result, [Name]);
  if AOutcome.ChangesBehavior then
    Result := Result + ' ' + _(CAP_CHANGES);
end;

procedure BuildRowIndex;
var
  K : TFindingKind;
  i : Integer;
begin
  for K := Low(TFindingKind) to High(TFindingKind) do
    GRowIndex[K] := -1;
  for i := 0 to High(FIX_ROWS) do
    GRowIndex[FIX_ROWS[i].Kind] := i;
end;

initialization
  BuildRowIndex;

end.
