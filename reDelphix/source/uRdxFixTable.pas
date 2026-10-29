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
// (TRdxFixFrame, Charge H5c) und die Zeilen. Das gilt auch fuer die
// Planer-Units der Chargen Q und R (je einfache Hilfe eine Unit
// uRdx<Name>Fix): bis zur Folgewelle des Wochen-Reviews 2026-10-21
// (G09-07) trug jede ihren Adapter selbst, band dafuer uEngineApi,
// uRdxRecipeRunner und uRdxFixRunner ein und fiel so aus dem
// FPC-Pruefstand. Eine neue Planer-Unit bindet nur, was ihre Textlogik
// braucht (uRdxCodeMap, uRdxBufferMath, uRdxText, uRefactorInfo); ihr
// Adapter steht hier.
//
// TEXTE: englische msgids, uebersetzt ueber i18n/*.po (Editorhilfen E6)
// in die reDelphix-Sprache (uRdxText._, Entscheid E29 - wie die
// SCA-Oberflaeche oder redelphix.ini [UI] Language; uRdxText nennt den
// Weg): Menuetexte, Hinweise und Gruende. Menuetexte und feste Hinweise
// stehen in FIX_CAPTIONS, FIX_ALT_CAPTIONS und FIX_HINTS - drei String-
// Arrays parallel zu FIX_ROWS, nicht als Feld der Zeile: tools/
// i18n_extract.py liest nur _('..'), _(KONSTANTE) und _(ARRAY[i]) mit
// Literalen im Array; ein Record-Feld (oder ein Array aus Konstanten-
// Namen) bliebe fuer template.pot unsichtbar, und msgmerge markierte die
// Uebersetzungen als obsolet (bis Charge G7 stand der Hinweis als
// deutsche Konstante im Feld Hint der Zeile). uTestRdxFixTable haelt die
// vier Arrays zusammen: eine Erwartungstabelle pinnt je Zeile Art, Planer
// (Name ueber PLANNER_NAMES), Menuetext, Kennzeichnung und zweiten Eintrag
// samt Menuetext - ein vertauschtes 'Plan:' oder ein verschobener
// Menuetext wird dort rot (Wochen-Review 2026-10-21; bis dahin pruefte der
// Test nur "nicht leer" und "nicht KindName"); fester Hinweis genau ohne
// HintByPlanner prueft er wie tools/gen-quickfix-doc.py --check.

interface

uses
  System.Classes,
  uEngineApi,          // TSourcePlaces
  uMethodd12,          // TLeakFinding
  uSCAConsts,          // TFindingKind
  uRdxRecipeRunner,    // TRdxFixOutcome
  uRdxContextRunner;   // TRdxContextOutcome (ContextCaption)

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

    // Menuetext einer Code-Aktion ohne Fund (Charge B, Entscheid F2): der
    // der Fund-Hilfe mit derselben Kette - ckIntroduceConst wie SCA014
    // (fkMagicNumber), ckTryFinallyCreate wie SCA009 (fkMissingFinally) -,
    // gebaut von CaptionFor mit AOutcome.Name und der Kennzeichnung bei
    // ChangesBehavior. Gleich geschrieben, damit die Kontextaktion auf
    // einer Fundzeile hinter der Fund-Hilfe wegfaellt (uFindingActionMenu,
    // Dedup per Caption). ckConcatToFormat (C16) wie das SCA044-Rezept
    // des Anbieters (keine Zeile dieser Tabelle): CAP_CONTEXT_FORMAT.
    // Charge C78: ckGuardClause wie SCA018 (fkDeepNesting); die anderen
    // C7/C8-Arten ohne Fund-Hilfe: TRdxContextRunner.CaptionOf.
    class function ContextCaption(
      const AOutcome: TRdxContextOutcome): string; static;

    // Fuer uTestRdxFixTable: die Zeilen, ihre Menuetexte (msgids,
    // unuebersetzt; AVariant 0 oder 1) und ihre festen Hinweise (msgid aus
    // FIX_HINTS, unuebersetzt; '' bei HintByPlanner).
    class function RowCount: Integer; static;
    class function Row(AIndex: Integer): TRdxFixRow; static;
    class function RawCaption(AIndex, AVariant: Integer): string; static;
    class function RawHint(AIndex: Integer): string; static;
    // Fuer uTestRdxFixTable: der Name des Planers der Zeile AIndex (AVariant
    // 0) bzw. ihres zweiten Eintrags (1) - '' ohne, '?' fuer einen Planer,
    // der in PLANNER_NAMES fehlt.
    class function PlannerName(AIndex, AVariant: Integer): string; static;
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
  uRdxResultFixes,   // SCA121, SCA196
  uRdxInheritedFixes, // SCA096, SCA097
  uRdxMagicFixes,    // SCA014; FileReason/IncludeReason fuer SCA069, SCA111/SCA112
  uRdxHttpsFix,         // SCA115
  uRdxParensFix,        // SCA094
  uRdxAttrGapFix,       // SCA183
  uRdxTwiceInheritedFix, // SCA093
  uRdxNativeIntFix,     // SCA161
  uRdxEmptyFinallyFix,  // SCA083
  uRdxForRangeFix,      // SCA046
  uRdxTabsFix,          // SCA061
  uRdxTrailingBlanksFix, // SCA063
  uRdxKeywordCaseFix,   // SCA064
  uRdxEmptyExceptFix,   // SCA002
  uRdxEmptyOnHandlerFix, // SCA159
  uRdxEmptyBlockFix,    // SCA077
  uRdxNoSonarFix,       // SCA065
  uRdxTrailingCommaFix, // SCA068
  uRdxGroupedDeclFix,   // SCA076
  uRdxIgnoreReasonFix,  // SCA179
  uRdxAttrDuplicateFix, // SCA180
  uRdxCategoryArgFix,   // SCA181
  uRdxGotoExitFix,      // SCA060
  uRdxFormatSettingsFix, // SCA128, SCA059
  uRdxMethodNameFix,    // SCA106
  uRdxIntegerOverflowFix, // SCA137
  uRdxCharEscapeFix,    // SCA188, SCA192
  uRdxThreadResumeFix,  // SCA113
  uRdxInsecureRandomFix, // SCA167
  uRdxFloatEqualityFix, // SCA144
  uRdxMoveSizeFix,      // SCA154
  uRdxDebugOutputFix,   // SCA017
  uRdxDeadCodeFix,      // SCA011
  uRdxIfThenFix,        // SCA131
  uRdxAssertSideEffectFix, // SCA169
  uRdxUnusedParameterFix, // SCA054 (+ TRdxParamPlan fuer SCA170)
  uRdxConstStringParameterFix, // SCA170
  uRdxExceptionNameFix, // SCA118
  uRdxLocalConstantNameFix, // SCA119
  uRdxDigitGroupingFix, // SCA069
  uRdxConsecutiveSectionFix, // SCA079
  uRdxAvoidOutFix,      // SCA086
  uRdxRawExceptionFix,  // SCA127
  uRdxClassMethodFix,   // SCA148
  uRdxAlwaysTrueFix,    // SCA150
  uRdxObjectListFix,    // SCA174
  uRdxHomoglyphFix,     // SCA193
  uRdxParamNameFix,     // SCA199
  uRdxDeepNestingFix,   // SCA018
  uRdxLookupHoistFix,   // SCA111, SCA112
  uRdxLoopBoundFix,     // SCA203
  uRdxInheritedEmptyFix, // SCA125
  uRdxFuncNameFix;      // SCA204

type
  // Was die Hilfe auf einem Netzpfad nicht liest (NetworkPathReason): je
  // Dateiart ein ganzer Satz in R_REMOTE_READS (E29: kein Nomen als %s -
  // bis Charge G7 'liest dort keine %s' mit WHAT_FORMS, WHAT_INCLUDES und
  // WHAT_PROJECT_FILES).
  TRdxRemoteRead = (rrForms, rrIncludes, rrProjectFiles);

const
  // Hinweise, die ein Planer-Adapter setzt (HintByPlanner bzw. zweiter
  // Eintrag): englische msgids, uebersetzt mit _() an der Verwendung
  // (Entscheid E29; de/fr in i18n/*.po - Pruefstand und Tests pruefen die
  // deutsche Fassung). Die FESTEN Hinweise der Zeilen stehen in FIX_HINTS
  // (unten, parallel zu FIX_ROWS): bis Charge G7 standen sie hier als
  // deutsche Konstanten und als Feld Hint in der Zeile - fuer tools/
  // i18n_extract.py unsichtbar (s. Kopf). Bis Charge R8 standen alle
  // Hinweise in uRdxRecipeRunner (LineHint, DeclHint, FlowHint und je
  // Rumpf).
  // SCA149: override (gekennzeichnet) bzw. reintroduce.
  R_OVERRIDE_HINT = 'the virtual call then ends up in this method';
  R_REINTRODUCE_HINT = 'only the warning W1010 goes away - the method still '
    + 'hides the inherited ones';
  // Charge Q: die Hinweise der zweiten Eintraege (SCA093, SCA046) setzen
  // ihre Adapter (PlanTwiceInheritedAlt, PlanReversedForRangeAlt) - bis
  // G09-20 standen sie in den Planer-Units.
  R_TWICE_ALT_HINT = 'the first call goes away - the parent method runs only '
    + 'once; check order and side effects';
  R_FORRANGE_SWAP_HINT = 'the loop never ran so far and then counts up; if '
    + 'it was switched off on purpose, this is an intervention';
  // SCA128 / SCA059 (QF1), zweiter Eintrag: aendert das Verhalten
  // (Kennzeichnung ueber ChangesBehavior im Alt-Adapter).
  R_FMTSET_INV_HINT = 'independent of the system: period as decimal '
    + 'separator, date MM/dd/yyyy, English month and day names - for files, '
    + 'SQL and logs, not for display';
  R_FMTLOC_INV_HINT = 'independent of the system: period as decimal '
    + 'separator, comma as thousands separator - for files, SQL and logs, '
    + 'not for display';
  // SCA144 (QF5): der Adapter setzt ihn vor AppendUses (HintByPlanner).
  R_FLOATEQ_HINT = 'now compares with a tolerance (default epsilon of '
    + 'System.Math) instead of exactly - an intentionally exact comparison '
    + '(flag or sentinel value) changes its meaning';
  // SCA017 (QF6), zweiter Eintrag: gekennzeichnet wie der erste.
  R_DEBUGOUT_DELETE_HINT = 'the output goes away in every build, also when '
    + 'debugging; its arguments are no longer evaluated';
  // SCA086 (QF10): je nach Typ des Parameters (TRdxOutPlan.Changes) - der
  // Adapter setzt den Hinweis (HintByPlanner).
  R_OUT_PLAIN_HINT = 'same meaning - for this simple type Delphi treats out '
    + 'like var; declaration and implementation together';
  R_OUT_MANAGED_HINT = 'out released the caller''s value on the call '
    + '(managed or unknown type) - with var it is kept; if the routine reads '
    + 'the parameter before setting it, it now sees the old value';
  // SCA127 (QF11): nur der Klassenname wechselt; welche Klasse passt,
  // entscheidet der Benutzer (zwei Eintraege, je eine Absicht). Der Adapter
  // setzt den Hinweis vor AppendUses (HintByPlanner).
  R_RAWEXC_HINT = 'only the class name - on handlers for EArgumentException '
    + 'now catch the exception, E.ClassName in the log changes; on E: '
    + 'Exception still catches it';
  R_RAWEXC_ALT_HINT = 'only the class name - on handlers for '
    + 'EInvalidOpException now catch the exception, E.ClassName in the log '
    + 'changes; on E: Exception still catches it';
  // SCA111/SCA112 (QF15): gekennzeichnet (E2) - der Lookup laeuft jetzt
  // auch ohne Durchlauf, und die Referenz wird nur einmal geholt. '%s'
  // zweimal = der neue Name; den Hinweis setzt der Adapter
  // (HintByPlanner).
  R_PARAM_HOIST_HINT = 'the parameter reference %s is fetched once before '
    + 'the loop - if the parameter is missing, the exception now comes even '
    + 'without an iteration; if a call in the loop resets SQL or Params '
    + 'indirectly, %s points to nothing';
  R_FIELD_HOIST_HINT = 'the field reference %s is fetched once before the '
    + 'loop - if the field is missing, the exception now comes even without '
    + 'an iteration; if a call in the loop closes or opens the dataset '
    + 'indirectly, %s points to nothing';
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
  R_MAGIC_HINT = 'same meaning - the constant %s holds the literal; rename '
    + 'it by hand or with Refactor > Rename (Ctrl+Shift+E)';
  // SCA061: die Hinweise (Tabweite und woher sie kommt) stehen seit rwE30 in
  // uRdxTabsFix (TRdxTabsFix.Hint; bis dahin R_TABS_DERIVED_HINT und
  // R_TABS_DEFAULT_HINT hier).

  // ---- Gruende, Dateiarten und Menuetext-Bausteine (keine Hinweise) ----
  // SCA147: Formdateien, die eine Methode per Name an ein Ereignis binden.
  FORM_EXTENSIONS: array[0..2] of string = ('.dfm', '.fmx', '.lfm');
  R_FORM_UNREADABLE = 'form file %s not readable (%s) - an event binding '
    + 'cannot be ruled out';
  // SCA014, SCA147 und SCA164 auf einem Netzpfad bzw. Netzlaufwerk (Review
  // FB, R2-07; SCA014 Gegen-Review Q14, Verdacht e): FileExists auf einer
  // nicht erreichbaren Freigabe blockierte den IDE-Hauptthread (Gegen-Review
  // R4-03: 2,5 bis 16 s je Aufruf). EINE Regel fuer alle drei - bis zum
  // Wochen-Review 2026-10-21 hatte SCA014 einen eigenen Text fuer das
  // Netzlaufwerk (RemoteDriveReason, R_MAGIC_REMOTE). Je Dateiart ein
  // ganzer Satz (TRdxRemoteRead); das Ende ('by hand') kommt als %s aus
  // uRdxText (MsgByHand), der Trenner '; ' davor bleibt im Satz.
  R_REMOTE_READS: array[TRdxRemoteRead] of string = (
    'network path %s - the quick fix reads no form files there (the menu is '
      + 'built in the main thread); %s',
    'network path %s - the quick fix reads no include files there (the menu '
      + 'is built in the main thread); %s',
    'network path %s - the quick fix reads no project or include files '
      + 'there (the menu is built in the main thread); %s');
  // SCA001: nur diese Variante bekommt die Hilfe (Feld TLeakFinding.
  // LeakVariant, das uLeakDetector2 setzt; properties.variant im SARIF).
  LEAK_VARIANT_FOF = 'freed-outside-finally';
  R_NO_FINDING = 'no finding';
  R_NO_ROW     = 'no simple quick fix for this rule';
  // Entscheid E2: eine Hilfe, die das Verhalten aendern kann, sagt es.
  CAP_CHANGES  = '(changes behavior)';
  NAME_UNKNOWN = 'X';
  // C16 (Charge N): der Menuetext von ckConcatToFormat - die msgid von
  // CAP_FORMAT des SCA044-Rezepts (uRdxActionCore, bis E3 uRdxProvider) und
  // uRdxContextRunner.CONTEXT_FORMAT_CAPTION; hier noch einmal, weil der
  // Extraktor eine msgid-Konstante nur in der Unit ihres _() aufloest.
  // Gleichheit: uTestRdxContextFormat.Caption_IsSca044RecipeCaption.
  CAP_CONTEXT_FORMAT = 'Build Format() from concatenation';

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
    // MsgNoFileOpen (uRdxText; bis Charge G7 R_NO_FILE). Sonst der Planer
    // auf der Code-Sicht, Name und Ersetzungen per Parts, nach einem
    // Angebot der Check; gesperrt ohne Ersetzungen. Den Plan bekommt der
    // Aufrufer in APlan (Kennzeichnung, Variants).
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
  Map := TRdxCodeMap.Acquire(ALines);
  try
    Result.Enabled := AForm.Planner(Map, AFinding.LineInt, AFinding.Message,
      APlan, Result.Reason);
    AForm.Parts(APlan, Result);
    if Result.Enabled and Assigned(AForm.Check) then
      Result.Reason := AForm.Check(APlaces, Map, AFinding, APlan);
  finally
    TRdxCodeMap.Release(Map);
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

// SCA014, SCA147, SCA164 (Review FB, R2-07): liegt die Unit im Netz
// (uRdxPaths.IsNetworkPath: UNC, auch mit '/' oder als '\\?\UNC\..', oder
// ein Netzlaufwerk; '\\?\C:\..' ist lokal)? Dann liest die Hilfe dort
// nichts (AWhat: was sie lesen wollte - je Art ein eigener Satz in
// R_REMOTE_READS, E29). Der Grund nennt das Verzeichnis ohne
// Namensraum-Vorsatz bzw. das Netzlaufwerk. '' oder der Grund.
function NetworkPathReason(const AFileName: string;
  AWhat: TRdxRemoteRead): string;
var
  Path, Place : string;
begin
  Result := '';
  if not IsNetworkPath(AFileName) then Exit;
  Path := WithoutNamespacePrefix(AFileName);
  Place := RemoteDriveOf(Path);
  if Place = '' then
    Place := ExtractFileDir(Path);
  Result := _(R_REMOTE_READS[AWhat], [Place, MsgByHand]);
end;

// SCA164: die Include-Dateien vor implementation liest die Hilfe von der
// Platte neben der Unit (Gegen-Review H3, Minor 4) - sie koennen die
// Routine deklarieren oder rufen; nicht gefunden heisst keine Hilfe. Nur,
// wenn der Plan welche nennt (seit Charge B1-FD auch der von SCA147), und
// nicht auf einem Netzpfad (NetworkPathReason, R2-07).
function IncludeCheck(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  AFinding: TLeakFinding; const APlan: TRdxRoutinePlan): string;
begin
  Result := '';
  if Length(APlan.Includes) = 0 then Exit;
  Result := NetworkPathReason(AFinding.FileName, rrIncludes);
  if Result = '' then
    Result := TRdxRoutineFixes.IncludeReason(AFinding.FileName,
      APlan.Includes, APlan.Name);
end;

// SCA014: was nur die Platte weiss - Netzpfad (NetworkPathReason, vor
// jedem Plattenzugriff), Lazarus-Dateiart oder -Projekt bzw. altes
// Delphi-Projekt neben der Unit, die Compiler-Weichen ihrer Includes
// (TRdxMagicFixes).
function MagicCheck(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  AFinding: TLeakFinding; const APlan: TRdxMagicPlan): string;
begin
  Result := NetworkPathReason(AFinding.FileName, rrProjectFiles);
  if Result = '' then
    Result := TRdxMagicFixes.FileReason(AFinding.FileName, lfInlineConst);
  if Result = '' then
    Result := TRdxMagicFixes.IncludeReason(AFinding.FileName, AMap,
      lfInlineConst);
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

// SCA106 (Charge QF2): Deklaration und Implementierung in EINEM
// Undo-Schritt; Name ist der neue Methodenname (schon aus der Meldung, auch
// wenn der Planer ablehnt).
procedure MethodNameParts(const APlan: TRdxMethodNamePlan;
  var AOutcome: TRdxFixOutcome);
begin
  AOutcome.Name := APlan.Name;
  AOutcome.Edits := APlan.Edits;
end;

// SCA106: reine Textlogik - kein Check, kein offener Quellstellen-Dienst.
// Eine Formdatei, die die Methode als Ereignis bindet, liest die Hilfe
// bewusst nicht: TReader findet die Methode ueber TObject.MethodAddress,
// und das vergleicht ohne Gross/klein (System.pas, UTF8IdentIdentCompare).
function MethodNameForm(
  APlanner: TRdxPlannerOf<TRdxMethodNamePlan>): TRdxPlanForm<TRdxMethodNamePlan>;
begin
  Result.Planner := APlanner;
  Result.Parts := MethodNameParts;
  Result.Check := nil;
  Result.NeedsOpen := False;
end;

// SCA137 (Charge QF2): eine Ersetzung (der linke Operand), Name der
// Operand - schon aus der Meldung, auch wenn der Planer ablehnt.
procedure OverflowParts(const APlan: TRdxOverflowPlan;
  var AOutcome: TRdxFixOutcome);
begin
  AOutcome.Name := APlan.Left;
  AOutcome.Edits := TArray<TRdxEdit>.Create(APlan.Edit);
end;

// SCA137: der Typbeweis (Kopf von uRdxIntegerOverflowFix) - an der Zeile des
// Ziels, der Ankerzeile der Anweisung: das Ziel Int64/UInt64/QWord, beide
// Operanden Integer/Cardinal, kein with-Block (WithBefore vor der Zeile,
// InWithBlock auch auf ihr). DeclaredTypeOf liefert '' fuer Properties,
// Methoden, Vorfahren von ausserhalb - das sperrt.
function OverflowCheck(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  AFinding: TLeakFinding; const APlan: TRdxOverflowPlan): string;
var
  L : Integer;
begin
  L := AFinding.LineInt;
  Result := TRdxIntegerOverflowFix.ProofReason(APlan,
    TRdxSimpleFixes.WithBefore(AMap, L) or APlaces.InWithBlock(L),
    APlaces.DeclaredTypeOf(L, APlan.Target),
    APlaces.DeclaredTypeOf(L, APlan.Left),
    APlaces.DeclaredTypeOf(L, APlan.Right));
end;

// SCA137: mit offenem Quellstellen-Dienst (der Typbeweis), danach
// OverflowCheck.
function OverflowForm(
  APlanner: TRdxPlannerOf<TRdxOverflowPlan>): TRdxPlanForm<TRdxOverflowPlan>;
begin
  Result.Planner := APlanner;
  Result.Parts := OverflowParts;
  Result.Check := OverflowCheck;
  Result.NeedsOpen := True;
end;

// SCA054, SCA170 (Charge QF8): alle Ersetzungen (Deklarationen,
// Implementierung, bei SCA054 auch '<param name>' der Doku) in EINEM
// Undo-Schritt; Name der Parameter.
procedure ParamParts(const APlan: TRdxParamPlan; var AOutcome: TRdxFixOutcome);
begin
  AOutcome.Name := APlan.Name;
  AOutcome.Edits := APlan.Edits;
end;

// SCA054, SCA170: reine Textlogik - kein Check, kein offener
// Quellstellen-Dienst.
function ParamForm(
  APlanner: TRdxPlannerOf<TRdxParamPlan>): TRdxPlanForm<TRdxParamPlan>;
begin
  Result.Planner := APlanner;
  Result.Parts := ParamParts;
  Result.Check := nil;
  Result.NeedsOpen := False;
end;

// SCA118 (Charge QF9): alle Ersetzungen der Umbenennung in EINEM
// Undo-Schritt; Name der neue Name ('Rename the exception class to %s') -
// schon gesetzt, wenn der Planer ablehnt.
procedure ExceptionNameParts(const APlan: TRdxExceptionNamePlan;
  var AOutcome: TRdxFixOutcome);
begin
  AOutcome.Name := APlan.Name;
  AOutcome.Edits := APlan.Edits;
end;

// SCA118: nur die Zeilen - kein Quellstellen-Dienst, kein Check.
function ExceptionNameForm: TRdxPlanForm<TRdxExceptionNamePlan>;
begin
  Result.Planner := TRdxExceptionNameFix.RenameClass;
  Result.Parts := ExceptionNameParts;
  Result.Check := nil;
  Result.NeedsOpen := False;
end;

// SCA119 (Charge QF9): alle Ersetzungen der Umbenennung in EINEM
// Undo-Schritt; Name der neue Name ('Rename the constant to %s').
procedure LocalConstantNameParts(const APlan: TRdxLocalConstantNamePlan;
  var AOutcome: TRdxFixOutcome);
begin
  AOutcome.Name := APlan.Name;
  AOutcome.Edits := APlan.Edits;
end;

// SCA119: nur die Zeilen - kein Quellstellen-Dienst, kein Check.
function LocalConstantNameForm: TRdxPlanForm<TRdxLocalConstantNamePlan>;
begin
  Result.Planner := TRdxLocalConstantNameFix.RenameConstant;
  Result.Parts := LocalConstantNameParts;
  Result.Check := nil;
  Result.NeedsOpen := False;
end;

// SCA086 (Charge QF10): Name ist der Parameter, die Ersetzungen 'out' ->
// 'var' in Deklaration und Implementierung (EIN Undo-Schritt).
procedure OutParts(const APlan: TRdxOutPlan; var AOutcome: TRdxFixOutcome);
begin
  AOutcome.Name := APlan.Name;
  AOutcome.Edits := APlan.Edits;
end;

// SCA086: ohne Check, ohne Quellstellen-Dienst.
function OutForm(
  APlanner: TRdxPlannerOf<TRdxOutPlan>): TRdxPlanForm<TRdxOutPlan>;
begin
  Result.Planner := APlanner;
  Result.Parts := OutParts;
  Result.Check := nil;
  Result.NeedsOpen := False;
end;

// SCA174 (Charge QF13): Deklaration und Create in EINEM Undo-Schritt; Name
// ist der Elementtyp aus der Meldung (auch wenn der Planer ablehnt).
procedure ObjectListParts(const APlan: TRdxObjectListPlan;
  var AOutcome: TRdxFixOutcome);
begin
  AOutcome.Name := APlan.Name;
  AOutcome.Edits := APlan.Edits;
end;

// SCA174: reine Textlogik - kein Check, kein offener Quellstellen-Dienst.
function ObjectListForm(
  APlanner: TRdxPlannerOf<TRdxObjectListPlan>): TRdxPlanForm<TRdxObjectListPlan>;
begin
  Result.Planner := APlanner;
  Result.Parts := ObjectListParts;
  Result.Check := nil;
  Result.NeedsOpen := False;
end;

// SCA193 (Charge QF13): alle Vorkommen in EINEM Undo-Schritt; Name ist der
// neue ASCII-Name ('' solange er nicht feststeht - der Menuetext nennt dann
// 'X').
procedure HomoglyphParts(const APlan: TRdxHomoglyphPlan;
  var AOutcome: TRdxFixOutcome);
begin
  AOutcome.Name := APlan.Name;
  AOutcome.Edits := APlan.Edits;
end;

// SCA193: reine Textlogik - kein Check, kein offener Quellstellen-Dienst.
function HomoglyphForm(
  APlanner: TRdxPlannerOf<TRdxHomoglyphPlan>): TRdxPlanForm<TRdxHomoglyphPlan>;
begin
  Result.Planner := APlanner;
  Result.Parts := HomoglyphParts;
  Result.Check := nil;
  Result.NeedsOpen := False;
end;

// SCA111/SCA112 (Charge QF15): die Einfuegung vor der Schleife und je
// Vorkommen in der Schleife eine Ersetzung in EINEM Undo-Schritt; Name ist
// der Aufruf ('Q.FieldByName(''Amount'')') - schon, wenn der Planer danach
// ablehnt (sobald er den Aufruf gelesen hat).
procedure LookupParts(const APlan: TRdxLookupPlan;
  var AOutcome: TRdxFixOutcome);
begin
  AOutcome.Name := APlan.Lookup;
  AOutcome.Edits := APlan.Edits;
end;

// SCA111/SCA112: was nur der Quellstellen-Dienst und die Platte wissen. Der
// Empfaenger muss an der Schleifenzeile (Ankerzeile einer Anweisung) als
// Variable, Parameter, Feld oder Inline-Variable bekannt sein - sonst
// koennte er eine Funktion sein, die bei jedem Aufruf ein anderes Objekt
// liefert, und der eine Aufruf vor der Schleife taete etwas anderes. Dann
// wie SCA014 (MagicCheck) Netzpfad, Projektdateien und Includes - mit dem
// Sprachmittel lfInlineVar: eine Inline-Variable gibt es wie die Inline-
// Konstante erst ab Delphi 10.3 (dieselbe Schwelle), in FPC 3.2 gar nicht;
// die Gruende nennen die Inline-Variable (Integration QFI3).
function LookupCheck(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  AFinding: TLeakFinding; const APlan: TRdxLookupPlan): string;
begin
  if (APlaces.DeclaredTypeOf(APlan.LoopLine, APlan.Receiver) = '')
     and not TRdxSimpleFixes.DeclaresInlineVar(AMap, APlan.LoopLine,
       APlan.Receiver) then
    Exit(TRdxLookupHoistFix.UnknownReceiverReason(APlan.Receiver));
  Result := NetworkPathReason(AFinding.FileName, rrProjectFiles);
  if Result = '' then
    Result := TRdxMagicFixes.FileReason(AFinding.FileName, lfInlineVar);
  if Result = '' then
    Result := TRdxMagicFixes.IncludeReason(AFinding.FileName, AMap,
      lfInlineVar);
end;

// SCA111/SCA112 (Charge QF15): mit offenem Quellstellen-Dienst (der
// Empfaenger als Variable, LookupCheck); Name der Aufruf.
function LookupForm(
  APlanner: TRdxPlannerOf<TRdxLookupPlan>): TRdxPlanForm<TRdxLookupPlan>;
begin
  Result.Planner := APlanner;
  Result.Parts := LookupParts;
  Result.Check := LookupCheck;
  Result.NeedsOpen := True;
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

// SCA164: zuerst der Name der Unit gegen ihre Datei (rwE30 Stufe 2, jvcl
// 'sample - form.pas': ein Interpreter-Skript, TRdxRoutineFixes.
// UnitFileReason), dann die Includes wie bei SCA147 (IncludeCheck).
function UnusedRoutineCheck(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  AFinding: TLeakFinding; const APlan: TRdxRoutinePlan): string;
begin
  Result := TRdxRoutineFixes.UnitFileReason(AFinding.FileName, AMap);
  if Result = '' then
    Result := IncludeCheck(APlaces, AMap, AFinding, APlan);
end;

function PlanUnusedRoutine(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P    : TRdxRoutinePlan;
  Form : TRdxPlanForm<TRdxRoutinePlan>;
begin
  Form := RoutineForm(TRdxRoutineFixes.UnusedRoutine);
  Form.Check := UnusedRoutineCheck;
  Result := TRdxFixFrame.Run<TRdxRoutinePlan>(Form, APlaces, ALines,
    AFinding, P);
end;

// SCA147: bindet die Formdatei neben der Unit (.dfm/.fmx/.lfm) die Methode
// per Name an ein Ereignis ('OnClick = AName')? Die Hilfe sieht sonst nur
// den Puffer; der Detektor prueft nur .dfm (und .lfm im FPC-Dialekt).
// Gelesen wird die Platte - ein im Designer neu gesetztes Ereignis traegt
// die IDE in den published-Teil ein, nicht unter private. Auf einem
// Netzpfad liest die Hilfe nichts (der Aufrufer prueft NetworkPathReason
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
  Result.Reason := NetworkPathReason(AFinding.FileName, rrForms);
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
    ResultForm(TRdxInheritedFixes.ConstructorInherited),
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
    ResultForm(TRdxInheritedFixes.DestructorInherited),
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

{ ---- Die Adapter der Chargen Q und R (Folgewelle G09-07) ----
  Je einfache Hilfe eine Planer-Unit mit der reinen Textlogik in der Form
  TRdxMapPlanner (FPC-Pruefstand); hier oeffnet MapFix ihr die Code-Sicht,
  Zeile und Meldung kommen aus dem Fund. APlaces und AUsesNames braucht
  keine dieser Hilfen. Hinweis und Kennzeichnung des Hauptwegs setzt die
  Zeile (FixFor); die zweiten Eintraege (SCA093, SCA046) setzen Variant,
  Hinweis und Kennzeichnung selbst - auch gesperrt gekennzeichnet: der
  Eintrag steht mit Grund im Menue und sagt, was er taete (wie SCA168). ---- }

function PlanHttps(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  Why : string;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxHttpsFix.Https);
  // rwE29: in Testcode vergleicht ein Test die Adresse oft woertlich;
  // rwE30: Testcode nur mit Merkmal, nicht schon wegen des Ordners - die
  // Frage liest die Platte, also nur fuer eine angebotene Hilfe.
  if not Result.Enabled then Exit;
  Why := TRdxHttpsFix.TestPathReason(AFinding.FileName, ALines);
  if Why <> '' then
  begin
    Result.Enabled := False;
    Result.Reason := Why;
    Result.Edits := nil;
  end;
end;

function PlanRedundantParens(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxParensFix.DoubleParens);
end;

function PlanAttrGap(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxAttrGapFix.BlankGap);
end;

function PlanTwiceInherited(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxTwiceInheritedFix.DeleteSecond);
end;

function PlanTwiceInheritedAlt(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxTwiceInheritedFix.DeleteFirst);
  Result.Variant := 1;
  Result.ChangesBehavior := True;
  if Result.Enabled then
    Result.Hint := _(R_TWICE_ALT_HINT);
end;

function PlanPointerSubtraction(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxNativeIntFix.PointerSubtraction);
end;

function PlanEmptyFinally(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxEmptyFinallyFix.Unwrap);
end;

function PlanReversedForRange(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxForRangeFix.ToDownto);
end;

function PlanReversedForRangeAlt(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxForRangeFix.SwapBounds);
  Result.Variant := 1;
  Result.ChangesBehavior := True;
  if Result.Enabled then
    Result.Hint := _(R_FORRANGE_SWAP_HINT);
end;

// SCA061: der Hinweis nennt die Tabweite des Plans und woher sie kommt
// (TRdxTabsFix.Hint rechnet sie fuer dieselbe Zeile noch einmal - die
// Belege der Datei aus dem Cache; HintByPlanner).
function PlanTabs(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  Map : TRdxCodeMap;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxTabsFix.Tabs);
  if not Result.Enabled then Exit;
  Map := TRdxCodeMap.Acquire(ALines);
  try
    Result.Hint := TRdxTabsFix.Hint(Map, AFinding.LineInt);
  finally
    TRdxCodeMap.Release(Map);
  end;
end;

function PlanTrailingBlanks(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxTrailingBlanksFix.TrimEnd);
end;

// SCA064: Name = das Wort wie gemeldet ('Begin') fuer den Menuetext - auch,
// wenn der Planer ablehnt.
function PlanLowercaseKeyword(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxKeywordCaseFix.LowercaseKeyword);
  Result.Name := QuotedText(AFinding.Message, '"');
end;

function PlanEmptyExcept(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxEmptyExceptFix.AddRaise);
end;

function PlanEmptyOnHandler(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxEmptyOnHandlerFix.Reraise);
end;

function PlanEmptyBlock(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxEmptyBlockFix.WithToCall);
end;

function PlanNoSonar(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxNoSonarFix.ToNoinspection);
end;

function PlanTrailingComma(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxTrailingCommaFix.DropComma);
end;

function PlanGroupedDeclaration(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxGroupedDeclFix.Split);
end;

function PlanIgnoreReason(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxIgnoreReasonFix.AddReason);
end;

function PlanAttrDuplicate(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxAttrDuplicateFix.DeleteDuplicate);
end;

function PlanCategoryArg(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxCategoryArgFix.AddArgument);
end;

function PlanGotoExit(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxGotoExitFix.GotoToExit);
end;

{ ---- Die Adapter der Charge QF (14 weitere Hilfen) ----
  Wie bei Q und R: die Textlogik in je einer Planer-Unit (FPC-Pruefstand),
  hier nur der Adapter. Typfragen an den Quellstellen-Dienst (DeclaredTypeOf,
  InWithBlock) stellen die Adapter von SCA137 (OverflowCheck), SCA144,
  SCA154 und SCA131; die Antworten pruefen reine Funktionen der Units
  (ProofReason, TypeReason, OperandReason, VariantReason - dort stehen die
  msgids, tools/i18n_extract.py loest nur Konstanten derselben Unit auf). ---- }

// SCA128/SCA059 (Realworld-Test rwE29): was nur Dateiname und Platte
// wissen - der Plattenblick von SCA014 (TRdxMagicFixes, wie
// PlanDigitGrouping): Netzpfad, Lazarus-Dateiart bzw. -Projekt neben der
// Unit, alte Delphi-Projektdatei bzw. .dproj vor der Schwelle, Weichen in
// den Includes. AFeature: lfFormatSettingsVar fuer den Hauptweg (die
// globale Variable ab Delphi XE; FPC kennt sie - Lazarus sperrt nicht),
// lfFormatInvariant fuer den Alt-Weg (ab 10.3 geprueft, FPC 3.2 kennt
// TFormatSettings.Invariant nicht). Die FPC-Weiche und alte Spuren IN der
// Datei prueft schon der Planer. Fundstellen: GExperts GX_DbugIntf.pas
// (Delphi 1-6, GExpert4.dof), Rechnung.lpi (rgReportPayments.pas,
// rgInvoiceItemEdit.pas), Img32.inc mit '{$IFDEF FPC}' (Img32.SVG.Path.pas).
// Die Includes fragt NUR der Alt-Weg (Entscheid Nico nach dem Review
// e/HilfeFixC, M1): fuer den Hauptweg beweist eine Versionsweiche in
// jedi.inc & Co. nichts (die Kits bauen mit vielen Versionen, auch ab XE),
// und ein nicht gefundenes Include sperrt ihn nicht - sonst fielen rund
// 40 % (SCA128) bzw. 50 % (SCA059) der Hauptweg-Angebote weg. Der Hauptweg
// sperrt also nur ueber Spuren in der Unit (Planer) und alte
// Projektdateien (FileReason). Die Netzpfad-Sperre bleibt fuer beide Wege:
// sie ist die Politik des Plattenblicks von SCA014 (auf einem Netzpfad
// liest die Hilfe im Hauptthread keine Projektdatei - ohne den Blick ist
// die Projekt-Sperre nicht pruefbar).
// Seit rwE30 Stufe 2 ueber TRdxMagicFixes.ProjectReason: beweist die
// Datei selbst einen neueren Compiler (Inline-Variable, RTL-Namensraum)
// bzw. nutzt sie Invariant ohne Weiche, fragt er die Platte nicht. Auch
// fuer SCA127 (lfExceptionClasses, mit Includes; dort sperrt der Netzpfad
// nicht - kein Beleg).
procedure FormatSettingsDiskCheck(ALines: TStrings; AFinding: TLeakFinding;
  AFeature: TRdxLateFeature; var AOutcome: TRdxFixOutcome);
var
  Map : TRdxCodeMap;
begin
  if not AOutcome.Enabled then Exit;
  AOutcome.Reason := '';
  if TRdxMagicFixes.MissingBlocks(AFeature) then
    AOutcome.Reason := NetworkPathReason(AFinding.FileName, rrProjectFiles);
  if AOutcome.Reason = '' then
  begin
    Map := TRdxCodeMap.Acquire(ALines);
    try
      AOutcome.Reason := TRdxMagicFixes.ProjectReason(AFinding.FileName, Map,
        AFeature, AFeature in [lfFormatInvariant, lfExceptionClasses]);
    finally
      TRdxCodeMap.Release(Map);
    end;
  end;
  if AOutcome.Reason = '' then Exit;
  AOutcome.Enabled := False;
  AOutcome.Edits := nil;
end;

// SCA128 (Charge QF1): ', FormatSettings' an jeden Aufruf der Liste auf der
// Fundzeile - die Textlogik in uRdxFormatSettingsFix.
function PlanDateFormatSettings(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxFormatSettingsFix.DateFormatSettings);
  FormatSettingsDiskCheck(ALines, AFinding, lfFormatSettingsVar, Result);
end;

// SCA128, zweiter Eintrag: ', TFormatSettings.Invariant' (aendert Verhalten).
function PlanDateFormatSettingsAlt(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  Map : TRdxCodeMap;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxFormatSettingsFix.DateFormatInvariant);
  Result.Variant := 1;
  Result.ChangesBehavior := True;
  FormatSettingsDiskCheck(ALines, AFinding, lfFormatInvariant, Result);
  if not Result.Enabled then Exit;
  // Ein Gegenstueck derselben Familie ohne Invariant sperrt nicht, der
  // Hinweis nennt es (Entscheid M2, Review e/HilfeFixC).
  Map := TRdxCodeMap.Acquire(ALines);
  try
    Result.Hint := TRdxFormatSettingsFix.PairHint(Map, AFinding.LineInt,
      _(R_FMTSET_INV_HINT));
  finally
    TRdxCodeMap.Release(Map);
  end;
end;

// SCA059 (Charge QF1): drittes Argument ', FormatSettings' an das eine
// Format der Fundzeile.
function PlanFormatLocale(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxFormatSettingsFix.FormatLocale);
  FormatSettingsDiskCheck(ALines, AFinding, lfFormatSettingsVar, Result);
end;

// SCA059, zweiter Eintrag: ', TFormatSettings.Invariant' (aendert Verhalten).
function PlanFormatLocaleAlt(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxFormatSettingsFix.FormatLocaleInvariant);
  Result.Variant := 1;
  Result.ChangesBehavior := True;
  FormatSettingsDiskCheck(ALines, AFinding, lfFormatInvariant, Result);
  if Result.Enabled then
    Result.Hint := _(R_FMTLOC_INV_HINT);
end;

// SCA106 (Charge QF2): 'doWork' -> 'DoWork' in Deklaration und
// Implementierung; Aufrufe bleiben (der Hinweis sagt es).
function PlanMethodName(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxMethodNamePlan;
begin
  Result := TRdxFixFrame.Run<TRdxMethodNamePlan>(
    MethodNameForm(TRdxMethodNameFix.Capitalize),
    APlaces, ALines, AFinding, P);
end;

// SCA137 (Charge QF2): 'Total := Count * Size;' ->
// 'Total := Int64(Count) * Size;' - Textform in uRdxIntegerOverflowFix,
// Typbeweis in OverflowCheck. Ohne offenen Quellstellen-Dienst
// MsgNoFileOpen.
function PlanIntegerOverflow(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxOverflowPlan;
begin
  Result := TRdxFixFrame.Run<TRdxOverflowPlan>(
    OverflowForm(TRdxIntegerOverflowFix.CastLeft),
    APlaces, ALines, AFinding, P);
end;

// SCA188 (Charge QF3): die Bidi-Steuerzeichen der Zeile; die Meldung nennt
// weder Spalte noch Zeichen, der Planer liest sie nicht.
function PlanBidiOverride(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxCharEscapeFix.BidiOverride);
end;

// SCA192 (Charge QF3): die unsichtbaren Zeichen der Zeile.
function PlanInvisibleChar(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxCharEscapeFix.InvisibleChar);
end;

// SCA113 (Charge QF4): 'X.Resume' -> 'X.Start', nur mit Beweis
// 'X := T.Create(True)' davor (uRdxThreadResumeFix). Name ist der
// Empfaenger aus der Meldung - auch, wenn der Planer ablehnt.
function PlanThreadResume(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxThreadResumeFix.ResumeToStart);
  Result.Name := TRdxThreadResumeFix.ReceiverOf(AFinding.Message);
end;

// SCA167 (Charge QF4): 'Randomize;' in den initialization-Abschnitt
// (uRdxInsecureRandomFix) - eine Ersetzung, ohne Name.
function PlanInsecureRandom(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxInsecureRandomFix.AddRandomize);
end;

// SCA144 (Charge QF5): der deklarierte Typ eines Operanden; '' fuer eine
// Zahl (sie braucht keinen Beweis). Seit rwE30 zuerst der Feldtyp, wenn
// der Operand ein Feld eines with-Records ist (AWithType,
// WithMemberTypes), und - wenn DeclaredTypeOf schweigt - der Typ aus den
// Routinen um die Zeile (LocalType: Parameter einer verschachtelten
// Routine).
function FloatOperandType(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  ALine: Integer; const AOperand, AWithType: string): string;
begin
  Result := '';
  if TRdxFloatEqualityFix.IsLiteral(AOperand) then
    Exit;
  if AWithType <> '' then
    Exit(AWithType);
  Result := APlaces.DeclaredTypeOf(ALine, AOperand);
  if Result = '' then
    Result := TRdxFloatEqualityFix.LocalType(AMap, ALine, AOperand);
end;

// SCA144: 'A = B' -> 'SameValue(A, B)', eine Null-Seite -> 'IsZero(A)', bei
// '<>' mit 'not' davor - die Ersetzung rechnet
// TRdxFloatEqualityFix.ToleranceCompare auf der Code-Sicht. Typbeweis hier
// (Hausregel): beide Seiten als Single/Double/Extended/Real deklariert
// (DeclaredTypeOf, TypeReason; eine Zahl braucht keinen), kein with-Block
// (InWithBlock) und kein vom Detektor herabgestufter Fund (fcLow:
// Waechter- bzw. Sentinel-Vergleich, exakt gewollt) - ContextReason. Name
// (Menuetext) ist SameValue bzw. IsZero, auch gesperrt. Der Hinweis steht
// vor AppendUses, das ' + uses ..' anhaengt und System.Math (FPC-Datei:
// Math) einfuegt, wenn es fehlt.
function PlanFloatEquality(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  Map          : TRdxCodeMap;
  L, Op, R     : string;
  InWith       : Boolean;
  WithL, WithR : string;
begin
  Result := Default(TRdxFixOutcome);
  Result.Name := TRdxFloatEqualityFix.CallName(AFinding.Message);
  if not Assigned(ALines) or not Assigned(APlaces) or not APlaces.IsOpen then
  begin
    Result.Reason := MsgNoFileOpen;
    Exit;
  end;
  SetLength(Result.Edits, 1);
  Map := TRdxCodeMap.Acquire(ALines);
  try
    Result.Enabled := TRdxFloatEqualityFix.ToleranceCompare(Map,
      AFinding.LineInt, AFinding.Message, Result.Edits[0], Result.Reason);
    // Ein with, dessen Ziele Records dieser Unit nur mit Feldern sind,
    // bindet nur deren Felder (rwE30) - dann zaehlt der Blockbereich des
    // Quellstellen-Dienstes nicht, und ein Operand, der ein Feld ist, hat
    // dessen Typ.
    InWith := False;
    WithL := '';
    WithR := '';
    if Result.Enabled then
    begin
      TRdxFloatEqualityFix.WithMemberTypes(Map, AFinding.LineInt,
        AFinding.Message, InWith, WithL, WithR);
      Result.Reason := TRdxFloatEqualityFix.ContextReason(
        AFinding.Confidence = fcLow,
        APlaces.InWithBlock(AFinding.LineInt) and not InWith,
        AFinding.Message);
    end;
    if Result.Enabled and (Result.Reason = '')
       and TRdxFloatEqualityFix.Operands(AFinding.Message, L, Op, R) then
      Result.Reason := TRdxFloatEqualityFix.TypeReason(
        L, FloatOperandType(APlaces, Map, AFinding.LineInt, L, WithL),
        R, FloatOperandType(APlaces, Map, AFinding.LineInt, R, WithR));
  finally
    TRdxCodeMap.Release(Map);
  end;
  Result.Enabled := Result.Enabled and (Result.Reason = '');
  if not Result.Enabled then
  begin
    Result.Edits := nil;
    Exit;
  end;
  Result.Hint := _(R_FLOATEQ_HINT);
  Result.Enabled := AppendUses(APlaces, AUsesNames, 'Math', 'System.Math',
    Result, AFinding.LineInt);
end;

// SCA154 (Charge QF5): 'SizeOf(PTyp)' -> 'SizeOf(Zieltyp)' fuer einen
// Aufruf, der genau EIN Element anfasst (TRdxMoveSizeFix.PointeeSize).
// Typbeweis hier (Hausregel): jedes Puffer-Argument ist als PTyp ('X^',
// bei CopyMemory/ZeroMemory 'X') bzw. als Zieltyp ('X', '@X') deklariert
// (DeclaredTypeOf, OperandReason) - sonst ist die gemeinte Laenge offen
// (ein Puffer, eine Zahl von Elementen, wirklich ein Zeiger); kein
// with-Block (InWithBlock, ContextReason). Name (Menuetext) ist der
// Zieltyp, auch gesperrt.
function PlanMoveSizeOfPointer(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  Map : TRdxCodeMap;
  Ops : TArray<TRdxSizeOperand>;
  i   : Integer;
begin
  Result := Default(TRdxFixOutcome);
  Result.Name := TRdxMoveSizeFix.TargetTypeOf(AFinding.Message);
  if not Assigned(ALines) or not Assigned(APlaces) or not APlaces.IsOpen then
  begin
    Result.Reason := MsgNoFileOpen;
    Exit;
  end;
  SetLength(Result.Edits, 1);
  Map := TRdxCodeMap.Acquire(ALines);
  try
    Result.Enabled := TRdxMoveSizeFix.PointeeSize(Map, AFinding.LineInt,
      AFinding.Message, Result.Edits[0], Result.Reason)
      and TRdxMoveSizeFix.Operands(Map, AFinding.LineInt, AFinding.Message,
        Ops, Result.Reason);
  finally
    TRdxCodeMap.Release(Map);
  end;
  if Result.Enabled then
    Result.Reason := TRdxMoveSizeFix.ContextReason(
      APlaces.InWithBlock(AFinding.LineInt));
  i := 0;
  while Result.Enabled and (Result.Reason = '') and (i < Length(Ops)) do
  begin
    Result.Reason := TRdxMoveSizeFix.OperandReason(Ops[i],
      APlaces.DeclaredTypeOf(AFinding.LineInt, Ops[i].Name));
    Inc(i);
  end;
  Result.Enabled := Result.Enabled and (Result.Reason = '');
  if not Result.Enabled then
    Result.Edits := nil;
end;

// SCA017 (Charge QF6): die gemeldete Anweisung in '{$IFDEF DEBUG}' ..
// '{$ENDIF}' (eigene Zeilen); Hinweis und Kennzeichnung setzt die Zeile.
function PlanDebugOutput(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxDebugOutputFix.WrapInDebug);
end;

// SCA017, zweiter Eintrag: die Anweisung loeschen - setzt Variant, Hinweis
// und Kennzeichnung selbst (wie PlanReversedForRangeAlt).
function PlanDebugOutputAlt(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxDebugOutputFix.DeleteCall);
  Result.Variant := 1;
  Result.ChangesBehavior := True;
  if Result.Enabled then
    Result.Hint := _(R_DEBUGOUT_DELETE_HINT);
end;

// SCA011 (Charge QF6): die toten Zeilen bis vor das Listenende loeschen;
// Name = Zahl der Zeilen (Menuetext 'Delete the unreachable code: %s
// line(s)') - toter Code ist oft geparkter Code, der Eintrag sagt, wie viel
// geht.
function PlanDeadCode(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxDeadCodeFix.DeleteDeadCode);
  if Result.Enabled then
    Result.Name := IntToStr(TRdxDeadCodeFix.LineCountOf(Result.Edits[0]));
end;

// SCA131 (Charge QF7): die Textlogik in uRdxIfThenFix, hier die Typfrage -
// ist das Ziel als Variant bzw. OleVariant deklariert, bekaeme es aus einem
// Literal-Arm einen anderen VarType als aus dem IfThen-Ergebnis (ShortInt
// statt Integer). Ohne offenen Quellstellen-Dienst und fuer ein Ziel, das
// DeclaredTypeOf nicht kennt (Pfad, Property), keine Sperre.
function PlanIfThenToIf(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  Target, TypeLow : string;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxIfThenFix.IfThenToIf);
  if not Result.Enabled or not Assigned(APlaces) or not APlaces.IsOpen then
    Exit;
  Target := TRdxIfThenFix.TargetOf(Result.Edits[0].Expected);
  TypeLow := LowerCase(APlaces.DeclaredTypeOf(AFinding.LineInt, Target));
  if (TypeLow = 'variant') or (TypeLow = 'olevariant') then
  begin
    Result.Enabled := False;
    Result.Edits := nil;
    Result.Reason := TRdxIfThenFix.VariantReason(Target);
  end;
end;

// SCA169 (Charge QF7): reine Textlogik (uRdxAssertSideEffectFix); eine
// eigene Routine Assert und ein with davor prueft der Planer selbst.
function PlanAssertOutside(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxAssertSideEffectFix.AssertOutside);
end;

{ ---- Die Adapter der Chargen QF8..QF11 (8 weitere Hilfen) ----
  Wie bei QF: die Textlogik in je einer Planer-Unit (FPC-tauglich), hier
  nur der Adapter. SCA054/SCA170, SCA118, SCA119 und SCA086 ueber das
  Geruest TRdxFixFrame (mehrere Ersetzungen in EINEM Undo-Schritt); SCA069
  fragt zusaetzlich die Platte (Plattenblick von SCA014 mit der Schwelle
  der Zifferntrenner), SCA127 ergaenzt SysUtils in uses. ---- }

// SCA054 (Charge QF8): Mode -> _Mode in Implementierung, Deklarationen
// und Doku. Kein Typwissen noetig - reine Textlogik.
function PlanUnusedParameter(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxParamPlan;
begin
  Result := TRdxFixFrame.Run<TRdxParamPlan>(
    ParamForm(TRdxUnusedParameterFix.MarkUnused),
    APlaces, ALines, AFinding, P);
end;

// SCA170 (Charge QF8): const vor den string-Parameter unit-lokaler
// Routinen, Implementierung und Deklarationen in EINEM Undo-Schritt. Kein
// Typwissen noetig - die Textpruefung sperrt jede Schreibstelle und jede
// Nutzung der Routine als Wert.
function PlanConstStringParameter(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxParamPlan;
begin
  Result := TRdxFixFrame.Run<TRdxParamPlan>(
    ParamForm(TRdxConstStringParameterFix.MakeConst),
    APlaces, ALines, AFinding, P);
end;

// SCA118 (Charge QF9): MyError -> EMyError, jeder Verweis der Datei.
function PlanExceptionName(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxExceptionNamePlan;
begin
  Result := TRdxFixFrame.Run<TRdxExceptionNamePlan>(ExceptionNameForm,
    APlaces, ALines, AFinding, P);
end;

// SCA119 (Charge QF9): lokale Konstante in UPPER_SNAKE_CASE, jeder Verweis
// der Routine.
function PlanLocalConstantName(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxLocalConstantNamePlan;
begin
  Result := TRdxFixFrame.Run<TRdxLocalConstantNamePlan>(
    LocalConstantNameForm, APlaces, ALines, AFinding, P);
end;

// SCA069 (Charge QF10): Zifferntrenner gibt es erst ab Delphi 11, FPC 3.2
// kennt sie nicht. Der Planer prueft den Text (FPC-Weiche, Spuren alter
// Compiler, Skript); hier, was nur Dateiname und Platte wissen: Dateiart
// .pp/.lpr, Netzpfad, Lazarus-Projekt bzw. alte Projektdatei neben der
// Unit, Weichen in den Includes - der Plattenblick von SCA014
// (TRdxMagicFixes) mit lfDigitSeparator: Schwelle FLOOR_DIGIT_SEP
// (ProjectVersion 19.3, Spuren bis Delphi 11) und ein Grund, der die
// Zifferntrenner nennt (bis zur Integration QFI2 vorlaeufig mit der
// Schwelle 10.3 und dem Text der Inline-Konstante, Notiz QF10 (h) 1).
function PlanDigitGrouping(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  Map    : TRdxCodeMap;
  Detail : string;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxDigitGroupingFix.Group);
  if not Result.Enabled then Exit;
  Result.Reason := TRdxDigitGroupingFix.FileNameReason(AFinding.FileName);
  if Result.Reason = '' then
    Result.Reason := NetworkPathReason(AFinding.FileName, rrProjectFiles);
  if Result.Reason = '' then
  begin
    Detail := TRdxMagicFixes.FileReason(AFinding.FileName, lfDigitSeparator);
    if Detail = '' then
    begin
      Map := TRdxCodeMap.Acquire(ALines);
      try
        Detail := TRdxMagicFixes.IncludeReason(AFinding.FileName, Map,
          lfDigitSeparator);
      finally
        TRdxCodeMap.Release(Map);
      end;
    end;
    if Detail <> '' then
      Result.Reason := TRdxDigitGroupingFix.ProjectReason(Detail);
  end;
  if Result.Reason = '' then Exit;
  Result.Enabled := False;
  Result.Edits := nil;
end;

// SCA079 (Charge QF10): Name = die Art aus der Meldung ('const', 'var')
// fuer den Menuetext - auch, wenn der Planer ablehnt.
function PlanConsecutiveSection(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxConsecutiveSectionFix.Merge);
  Result.Name := LowerCase(QuotedText(AFinding.Message, '`'));
end;

// SCA086 (Charge QF10): gekennzeichnet nach dem Typ des Parameters (der
// Plan sagt es, auch gesperrt) - einfache Typen bedeutungsgleich, alle
// anderen gelten als verwaltet: out gab den Wert beim Aufruf frei.
function PlanAvoidOut(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxOutPlan;
begin
  Result := TRdxFixFrame.Run<TRdxOutPlan>(OutForm(TRdxAvoidOutFix.OutToVar),
    APlaces, ALines, AFinding, P);
  Result.ChangesBehavior := P.Changes;
  if not Result.Enabled then Exit;
  // Verwaltet und nicht zuerst gesetzt (rwE30 Stufe 2): nur im Menue, der
  // Hinweis nennt die Stelle (TRdxOutPlan.Caution, schon uebersetzt).
  Result.MenuOnly := P.MenuOnly;
  if P.MenuOnly then
    Result.Hint := P.Caution
  else if P.Changes then
    Result.Hint := _(R_OUT_MANAGED_HINT)
  else
    Result.Hint := _(R_OUT_PLAIN_HINT);
end;

// SCA127 (Charge QF11): nur der Klassenname wechselt (uRdxRawExceptionFix).
// Beide Klassen stehen in SysUtils wie Exception; fehlt die Unit in uses
// (Exception kam dann ueber einen Alias), kommt sie mit (AppendUses, wie
// SCA020/SCA168). Der Hinweis steht vor AppendUses (HintByPlanner).
function PlanRaisingRawException(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxRawExceptionFix.ToArgumentException);
  // Alte Compiler in der Nachbarschaft (rwE30 Stufe 2, Sperre bei Beleg).
  FormatSettingsDiskCheck(ALines, AFinding, lfExceptionClasses, Result);
  if not Result.Enabled then Exit;
  Result.Hint := _(R_RAWEXC_HINT);
  Result.Enabled := AppendUses(APlaces, AUsesNames, 'SysUtils',
    'System.SysUtils', Result);
end;

// SCA127, zweiter Eintrag: EInvalidOpException (unzulaessiger Zustand) -
// setzt Variant, Hinweis und Kennzeichnung selbst.
function PlanRaisingRawExceptionAlt(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxRawExceptionFix.ToInvalidOpException);
  Result.Variant := 1;
  Result.ChangesBehavior := True;
  FormatSettingsDiskCheck(ALines, AFinding, lfExceptionClasses, Result);
  if not Result.Enabled then Exit;
  Result.Hint := _(R_RAWEXC_ALT_HINT);
  Result.Enabled := AppendUses(APlaces, AUsesNames, 'SysUtils',
    'System.SysUtils', Result);
end;

{ ---- Chargen QF12..QF15: die Planer-Units (je Hilfe eine, SCA111/SCA112
  teilen sich uRdxLookupHoistFix) tragen nur Textlogik; hier steht der
  Adapter. SCA150, SCA199 und SCA018 ueber MapFix (eine Ersetzung); SCA148
  mit zwei Ersetzungen in der Form von MapFix; SCA174, SCA193 und
  SCA111/SCA112 ueber das Geruest TRdxFixFrame (mehrere Ersetzungen in
  EINEM Undo-Schritt), SCA111/SCA112 dazu mit Quellstellen-Dienst und
  Plattenblick (LookupCheck). ---- }

// SCA148 (Charge QF12): 'class ... static;' an der Deklaration und 'class'
// vor dem Kopf der Implementierung - ZWEI Ersetzungen in einem Schritt,
// darum die Form von MapFix mit einer Liste. Name ist der Methodenname aus
// der Meldung (Menuetext), auch wenn der Planer ablehnt.
function PlanCanBeClassMethod(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  Map : TRdxCodeMap;
begin
  Result := Default(TRdxFixOutcome);
  Result.Name := TRdxClassMethodFix.MethodNameOf(AFinding.Message);
  if not Assigned(ALines) then
  begin
    Result.Reason := MsgNoFileOpen;
    Exit;
  end;
  Map := TRdxCodeMap.Acquire(ALines);
  try
    Result.Enabled := TRdxClassMethodFix.MakeStatic(Map, AFinding.LineInt,
      AFinding.Message, Result.Edits, Result.Reason);
  finally
    TRdxCodeMap.Release(Map);
  end;
  if not Result.Enabled then
    Result.Edits := nil;
end;

// SCA150 (Charge QF12): Zeile des Treffers, die Meldung nennt die Form.
function PlanBoolAlwaysTrue(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxAlwaysTrueFix.ResolveIf);
end;

// SCA174 (Charge QF13): 'TList<T>' -> 'TObjectList<T>' in Deklaration und
// Create der lokalen Liste; gekennzeichnet setzt die Zeile (Changes: True).
function PlanObjectList(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxObjectListPlan;
begin
  Result := TRdxFixFrame.Run<TRdxObjectListPlan>(
    ObjectListForm(TRdxObjectListFix.OwnItems),
    APlaces, ALines, AFinding, P);
end;

// SCA193 (Charge QF13): der Homoglyph-Bezeichner der Zeile in ASCII, an
// allen Vorkommen der Unit (die Meldung nennt weder Namen noch Spalte).
function PlanHomoglyph(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxHomoglyphPlan;
begin
  Result := TRdxFixFrame.Run<TRdxHomoglyphPlan>(
    HomoglyphForm(TRdxHomoglyphFix.ToAscii),
    APlaces, ALines, AFinding, P);
end;

// SCA199 (Charge QF14): das Literal in ParamByName wird zum einen
// Platzhalter der Meldung, der einen Tippfehler entfernt ist. Name = der
// eingesetzte Platzhalter fuer den Menuetext ('%s'); Hinweis und
// Kennzeichnung (Changes: True) setzt die Zeile.
function PlanParamName(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxParamNameFix.UsePlaceholder);
  if Result.Enabled then
    Result.Name := Result.Edits[0].NewText;
end;

// SCA018 (Charge QF14): das letzte 'if A then begin B end' der Routine um
// die gemeldete Stelle wird zu 'if not A then Exit;' mit B eine Stufe
// flacher; Hinweis und Kennzeichnung setzt die Zeile.
function PlanDeepNesting(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxDeepNestingFix.GuardClause);
end;

// SCA111 (Charge QF15): 'var PrmId := Q.ParamByName(''id'');' vor die
// Schleife, die Aufrufe darin durch den Namen; der Hinweis nennt den Namen.
function PlanParamByNameLoop(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxLookupPlan;
begin
  Result := TRdxFixFrame.Run<TRdxLookupPlan>(
    LookupForm(TRdxLookupHoistFix.ParamByNameLoop),
    APlaces, ALines, AFinding, P);
  if Result.Enabled then
    Result.Hint := _(R_PARAM_HOIST_HINT, [P.Name, P.Name]);
end;

// SCA112 (Charge QF15): dasselbe fuer
// 'var FldAmount := Q.FieldByName(''Amount'');'.
function PlanFieldByNameLoop(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxLookupPlan;
begin
  Result := TRdxFixFrame.Run<TRdxLookupPlan>(
    LookupForm(TRdxLookupHoistFix.FieldByNameLoop),
    APlaces, ALines, AFinding, P);
  if Result.Enabled then
    Result.Hint := _(R_FIELD_HOIST_HINT, [P.Name, P.Name]);
end;

// SCA203 (Charge A3 / Q2): die Grenze der for-Schleife, die einen Index zu
// weit laeuft - eine Stelle im Kopf (Count - 1, High, ab 1, ohne + 1). Name
// = der neue Bereich fuer den Menuetext ('%s'), auch wenn der Planer
// ablehnt; Hinweis und Kennzeichnung (Changes: True) setzt die Zeile.
function PlanLoopBound(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxLoopBoundFix.LastIndex);
  Result.Name := TRdxLoopBoundFix.RangeAfter(AFinding.Message);
end;

// SCA125 (Charge A4, Todo Q14): Deklaration und Implementierung des leeren
// Overrides in EINEM Schritt - die Plan-Form von SCA147 (RoutineForm; der
// Plan nennt keine Includes, IncludeCheck bleibt still). Name = der
// Methodenname aus der Meldung, auch gesperrt.
function PlanInheritedMethodEmpty(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  P : TRdxRoutinePlan;
begin
  Result := TRdxFixFrame.Run<TRdxRoutinePlan>(
    RoutineForm(TRdxInheritedEmptyFix.DeleteOverride),
    APlaces, ALines, AFinding, P);
end;

// SCA204 (Charge N / FN): 'Name :=' -> 'Result :=' auf der gemeldeten
// Zeile, bedeutungsgleich. Name = der Funktionsname aus der Meldung fuer den
// Menuetext ('%s'), auch wenn der Planer ablehnt.
function PlanFuncNameResult(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := MapFix(ALines, AFinding.LineInt, AFinding.Message,
    TRdxFuncNameFix.ResultAssign);
  Result.Name := TRdxFuncNameFix.NameOf(AFinding.Message);
end;

{ ---- Die Tabelle ---- }

type
  // Ein Eintrag von PLANNER_NAMES.
  TRdxPlannerName = record
    Name : string;
    Plan : TRdxFixPlanner;
  end;

const
  FIX_ROW_HIGH = 92;

  // Je Art eine Zeile; die Reihenfolge ist die der Chargen (Stufe 2a,
  // Stufe 2 Rest, uQuickFix-Umzug/Stufe 3, Zeilen, Ausnahmen, Deklarationen
  // H1, Anweisungen H2, Routinen H3b, Aufraeumen H3a, try/finally H4,
  // Ergebnis und Konstruktoren H5, Magic Number Q14, einfache Hilfen Q, R,
  // QF, QF8..QF11, QF12..QF15 und Charge A). Der feste Hinweis steht unter
  // demselben Index in FIX_HINTS, der Menuetext in FIX_CAPTIONS (s. Kopf).
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
     HintByPlanner: False; Changes: False;
     Alt: PlanCaseRaise),
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
     HintByPlanner: False; Changes: False;
     Alt: PlanEmptyRaise),
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
     HintByPlanner: True; Changes: False; Alt: nil),
    // Charge Q: zehn einfache Hilfen.
    // SCA115: aendert das Verhalten (E2) - der Server muss https koennen.
    (Kind: fkHttpInsteadOfHttps; Plan: PlanHttps;
     HintByPlanner: False; Changes: True; Alt: nil),
    (Kind: fkRedundantParentheses; Plan: PlanRedundantParens;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkAttributeMisalignment; Plan: PlanAttrGap;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkTwiceInheritedCalls; Plan: PlanTwiceInherited;
     HintByPlanner: False; Changes: True;
     Alt: PlanTwiceInheritedAlt),
    (Kind: fkPointerSubtraction; Plan: PlanPointerSubtraction;
     HintByPlanner: False; Changes: True; Alt: nil),
    (Kind: fkEmptyFinallyBlock; Plan: PlanEmptyFinally;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkReversedForRange; Plan: PlanReversedForRange;
     HintByPlanner: False; Changes: True;
     Alt: PlanReversedForRangeAlt),
    (Kind: fkTabulationCharacter; Plan: PlanTabs;
     HintByPlanner: True; Changes: False; Alt: nil),
    (Kind: fkTrailingWhitespace; Plan: PlanTrailingBlanks;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkLowercaseKeyword; Plan: PlanLowercaseKeyword;
     HintByPlanner: False; Changes: False; Alt: nil),
    // Charge R: zehn weitere Hilfen.
    (Kind: fkEmptyExcept; Plan: PlanEmptyExcept;
     HintByPlanner: False; Changes: True; Alt: nil),
    (Kind: fkEmptyOnHandler; Plan: PlanEmptyOnHandler;
     HintByPlanner: False; Changes: True;
     Alt: nil),
    (Kind: fkEmptyBlock; Plan: PlanEmptyBlock;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkNoSonarMarker; Plan: PlanNoSonar;
     HintByPlanner: False; Changes: True; Alt: nil),
    (Kind: fkTrailingCommaArgList; Plan: PlanTrailingComma;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkGroupedDeclaration; Plan: PlanGroupedDeclaration;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkAttributeIgnoreWithoutReason; Plan: PlanIgnoreReason;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkAttributeDuplicate; Plan: PlanAttrDuplicate;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkAttributeCategoryWithoutString; Plan: PlanCategoryArg;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkGotoStatement; Plan: PlanGotoExit;
     HintByPlanner: False; Changes: False; Alt: nil),
    // Charge QF: 14 weitere Hilfen.
    // SCA128/SCA059: bedeutungsgleich; der zweite Eintrag (Invariant)
    // kennzeichnet sich selbst.
    (Kind: fkDateFormatSettings; Plan: PlanDateFormatSettings;
     HintByPlanner: False; Changes: False;
     Alt: PlanDateFormatSettingsAlt),
    (Kind: fkFormatLocaleHint; Plan: PlanFormatLocale;
     HintByPlanner: False; Changes: False;
     Alt: PlanFormatLocaleAlt),
    // SCA106: bedeutungsgleich (Delphi bindet ohne Gross/klein).
    (Kind: fkMethodName; Plan: PlanMethodName;
     HintByPlanner: False; Changes: False; Alt: nil),
    // SCA137: aendert das Ergebnis, sobald das Produkt nicht in 32 Bit
    // passt - das ist der Fix (E2).
    (Kind: fkIntegerOverflow; Plan: PlanIntegerOverflow;
     HintByPlanner: False; Changes: True; Alt: nil),
    (Kind: fkSourceBidiOverride; Plan: PlanBidiOverride;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkSourceInvisibleChar; Plan: PlanInvisibleChar;
     HintByPlanner: False; Changes: False; Alt: nil),
    // SCA113: bedeutungsgleich - nur mit Beweis Create(True)
    // (uRdxThreadResumeFix); Name ist der Empfaenger.
    (Kind: fkThreadResumeDeprecated; Plan: PlanThreadResume;
     HintByPlanner: False; Changes: False;
     Alt: nil),
    // SCA167: die Zufallsfolge ist danach bei jedem Lauf eine andere (E2).
    (Kind: fkInsecureRandom; Plan: PlanInsecureRandom;
     HintByPlanner: False; Changes: True; Alt: nil),
    // SCA144: Toleranz statt exakt (E2); den Hinweis setzt der Adapter vor
    // AppendUses (System.Math bei Bedarf).
    (Kind: fkFloatEquality; Plan: PlanFloatEquality;
     HintByPlanner: True; Changes: True; Alt: nil),
    // SCA154: die Laenge wird SizeOf(Zieltyp) statt 4/8 (E2).
    (Kind: fkMoveSizeOfPointer; Plan: PlanMoveSizeOfPointer;
     HintByPlanner: False; Changes: True; Alt: nil),
    // SCA017: der Release-Bau (bzw. beim Loeschen jeder Bau) verliert die
    // Ausgabe (E2).
    (Kind: fkDebugOutput; Plan: PlanDebugOutput;
     HintByPlanner: False; Changes: True;
     Alt: PlanDebugOutputAlt),
    // SCA011: bedeutungsgleich (der Code lief nie); der Menuetext nennt die
    // Zahl der Zeilen (Name, Adapter).
    (Kind: fkDeadCode; Plan: PlanDeadCode;
     HintByPlanner: False; Changes: False; Alt: nil),
    // SCA131: nur noch der zutreffende Arm laeuft (E2); die Typfrage
    // (Variant-Ziel) stellt der Adapter.
    (Kind: fkIfThenShortCircuit; Plan: PlanIfThenToIf;
     HintByPlanner: False; Changes: True; Alt: nil),
    // SCA169: die Bedingung laeuft jetzt auch ohne Assertions (E2) - das
    // ist der Fix.
    (Kind: fkAssertWithSideEffect; Plan: PlanAssertOutside;
     HintByPlanner: False; Changes: True; Alt: nil),
    // Charge QF8..QF11: 8 weitere Hilfen.
    // SCA054/SCA170: Parameter-Hilfen (Deklaration und Implementierung in
    // EINEM Undo-Schritt); SCA170 ungekennzeichnet, der Hinweis nennt das
    // const-Aliasing.
    (Kind: fkUnusedParameter; Plan: PlanUnusedParameter;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkConstStringParameter; Plan: PlanConstStringParameter;
     HintByPlanner: False; Changes: False; Alt: nil),
    // SCA118/SCA119: Umbenennungen, bedeutungsgleich.
    (Kind: fkExceptionName; Plan: PlanExceptionName;
     HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkLocalConstantName; Plan: PlanLocalConstantName;
     HintByPlanner: False; Changes: False; Alt: nil),
    // SCA069: bedeutungsgleich; nur ab Delphi 11 (Planer und Adapter
    // sperren FPC und alte Compiler).
    (Kind: fkDigitGrouping; Plan: PlanDigitGrouping;
     HintByPlanner: False; Changes: False; Alt: nil),
    // SCA079: bedeutungsgleich; Name ist die Art aus der Meldung.
    (Kind: fkConsecutiveSection; Plan: PlanConsecutiveSection;
     HintByPlanner: False; Changes: False; Alt: nil),
    // SCA086: Kennzeichnung je nach Typ, Hinweis setzt der Adapter (wie
    // SCA096/SCA097).
    (Kind: fkAvoidOut; Plan: PlanAvoidOut;
     HintByPlanner: True; Changes: False; Alt: nil),
    // SCA127: nur der Klassenname (E2 - Handler fangen anders); zwei
    // Eintraege, je eine Absicht; den Hinweis setzt der Adapter vor
    // AppendUses (SysUtils bei Bedarf).
    (Kind: fkRaisingRawException; Plan: PlanRaisingRawException;
     HintByPlanner: True; Changes: True;
     Alt: PlanRaisingRawExceptionAlt),
    // Charge QF12..QF15: 8 weitere Hilfen.
    // SCA148: Deklaration und Kopf in einem Schritt; bedeutungsgleich in
    // dieser Datei (die Grenze "andere Units" nennt der Hinweis).
    (Kind: fkCanBeClassMethod; Plan: PlanCanBeClassMethod;
     HintByPlanner: False; Changes: False; Alt: nil),
    // SCA150: immer wahres if aufloesen - der else-Zweig lief nie.
    (Kind: fkBoolAlwaysTrue; Plan: PlanBoolAlwaysTrue;
     HintByPlanner: False; Changes: False; Alt: nil),
    // SCA174: die Liste gibt ihre Elemente danach frei - gekennzeichnet (E2).
    (Kind: fkTObjectListWithoutOwnership; Plan: PlanObjectList;
     HintByPlanner: False; Changes: True; Alt: nil),
    // SCA193: bedeutungsgleich - der Name gilt nur in der Unit und ist dort
    // frei; alle Vorkommen in einem Schritt.
    (Kind: fkSourceNonAsciiIdentifier; Plan: PlanHomoglyph;
     HintByPlanner: False; Changes: False; Alt: nil),
    // SCA199: der Aufruf bindet danach einen anderen Parameter (E2); Name =
    // der eingesetzte Platzhalter (Menuetext).
    (Kind: fkParamNameMismatch; Plan: PlanParamName;
     HintByPlanner: False; Changes: True; Alt: nil),
    // SCA018: Waechter-Klausel fuer das letzte if der Routine
    // (bedeutungsgleich).
    (Kind: fkDeepNesting; Plan: PlanDeepNesting;
     HintByPlanner: False; Changes: False; Alt: nil),
    // SCA111/SCA112: Lookup vor die Schleife, gekennzeichnet (E2); den
    // Hinweis setzt der Adapter (Name der Variable).
    (Kind: fkParamByNameInLoop; Plan: PlanParamByNameLoop;
     HintByPlanner: True; Changes: True; Alt: nil),
    (Kind: fkFieldByNameInLoop; Plan: PlanFieldByNameLoop;
     HintByPlanner: True; Changes: True; Alt: nil),
    // SCA203: die Schleife laeuft einmal weniger bzw. ab 1 (E2).
    (Kind: fkLoopPastHighBound; Plan: PlanLoopBound;
     HintByPlanner: False; Changes: True; Alt: nil),
    // Charge A (Wettbewerbs-Todo 2026-10-23). SCA125 (Q14): das leere
    // Override geht ganz - bedeutungsgleich; die Sichtbarkeit belegt der
    // Planer am Vorfahren in der Datei, sonst sperrt er.
    (Kind: fkInheritedMethodEmpty; Plan: PlanInheritedMethodEmpty;
     HintByPlanner: False; Changes: False; Alt: nil),
    // Charge N / FN (2026-10-25). SCA204: Result statt Funktionsname -
    // bedeutungsgleich (links vom ':=' dieselbe Variable).
    (Kind: fkFunctionNameAsResult; Plan: PlanFuncNameResult;
     HintByPlanner: False; Changes: False; Alt: nil)
  );

  // Die festen Hinweise (englische msgids) unter dem Index der Zeile, je
  // Eintrag mit der Art als Kommentar; '' genau bei HintByPlanner -
  // FixFor uebersetzt mit _(FIX_HINTS[i]), nie _('') (die msgid '' ist der
  // Kopf der .po). Bis Charge G7 als deutsche Konstanten R_..._HINT und
  // Feld Hint der Zeile - fuer tools/i18n_extract.py unsichtbar (s. Kopf);
  // der Extraktor liest nur Literale im Array, keine Konstanten-Namen.
  // uTestRdxFixTable (RawHint) und tools/gen-quickfix-doc.py --check
  // halten FIX_HINTS und HintByPlanner zusammen.
  FIX_HINTS: array[0..FIX_ROW_HIGH] of string = (
    // SCA075, SCA074, SCA087 und SCA066 haben ihren festen Hinweis seit der
    // Tabelle (Charge R8; bis dahin leer, der Eintrag stand ohne Erklaerung
    // im Menue - Gegen-Review R8, Major 1; uTestRdxFixTable pinnt den
    // ersten woertlich).
    // ExplicitTObjectInheritance
    'TObject is the ancestor anyway - same meaning',
    // FreeAndNilHint
    '',
    // NilComparison
    '',
    // AssertMessage
    'the condition as text - so the message names what failed',
    // EmptyVisibilitySection
    'the section was empty - same meaning',
    // FreeWithoutNil
    '',
    // EmptyArgumentList
    'same meaning - Delphi calls the routine without parentheses too',
    // RedundantBoolean
    '',
    // AssignedAndAssignedNil
    '',
    // UnusedUses
    '',
    // DefaultCaseInCaseStatement
    'all other values: do nothing (as before)',
    // BeginEndRequired
    'same meaning - only the form; a further statement then visibly belongs '
      + 'to the branch',
    // IfElseBegin
    'same meaning - only the form; a further statement then visibly belongs '
      + 'to the branch',
    // SuperfluousSemicolon
    'the second ";" was an empty statement',
    // UnitLevelKeywordIndent
    'whitespace only',
    // LegacyInitializationSection
    'same meaning - the section can then get a finalization',
    // CastAndFree
    '',
    // EmptyMethod
    'the intent is in the body - a reason after it helps the next reader',
    // MissingRaise
    'the exception is now raised - the code after it no longer runs in the '
      + 'error case',
    // ReRaiseException
    'the same exception - the original stack trace is kept',
    // PublicMemberWithoutDoc
    'the skeleton is empty - fill in summary, param and returns',
    // InterfaceWithoutGuid
    'a new GUID - only for your own interfaces, never for COM imports',
    // MissingOverride
    '',
    // RedundantConditional
    'same meaning - one assignment instead of two branches',
    // RedundantJump
    'same meaning - the control flow leaves the block anyway',
    // SelfAssignment
    'the assignment has no effect - if another value was meant (typo), it is '
      + 'still missing',
    // UnusedRoutine
    'same meaning - the name appears nowhere else in the code of the file; '
      + 'documentation and a comment above it that names the routine go with '
      + 'it',
    // UnusedPrivateMethod
    'same meaning - declaration and implementation go, the name appears '
      + 'nowhere else in the code of the file',
    // Charge H3a (Aufraeumen): SCA070, SCA053.
    // CommentedOutCode
    'same meaning - only a comment is removed; version control still knows it',
    // UnusedLocalVar
    'same meaning - the variable appears nowhere else',
    // Charge H4 (try/finally): alle gekennzeichnet (E2) - B laeuft danach
    // auch dort, wo es bisher uebersprungen wurde; das ist der Fix.
    // MissingFinally
    'Free now also runs on an exception and on Exit - the lines in between '
      + 'move into the try part',
    // MemoryLeak
    'Free now also runs on an exception and on Exit - the lines in between '
      + 'move into the try part',
    // LockWithoutTryFinally
    'the lock is now also released on an exception - the lines in between '
      + 'move into the try part',
    // UnpairedLock
    'the lock is now also released on an exception - the lines in between '
      + 'move into the try part',
    // GetMemWithoutFreeMem
    'FreeMem now also runs on an exception and on Exit - the lines in '
      + 'between move into the try part',
    // ConstructorWithoutInherited
    '',
    // DestructorWithoutInherited
    '',
    // SCA121: der Wert ist ein Literal (0, False, '''', nil ...) oder
    // Default(T) (Charge H5c); der Menuetext nennt ihn. Bis Charge FB
    // hiess es '(wie Default(T))' - das stimmt nicht, wenn ein Member wie
    // der erste Aufzaehlungswert heisst (Gegen-Review R5-06, Fall 2;
    // Absprache mit FE: der Text muss fuer Literal UND Default(T) stimmen).
    // RoutineResultUnassigned
    'Result now starts with the named value instead of a random one - later '
      + 'assignments still apply',
    // ManagedResultUninit
    '',
    // MagicNumber
    '',
    // Charge Q (zehn einfache Hilfen): SCA115, SCA094, SCA183, SCA093,
    // SCA161, SCA083, SCA046, SCA061, SCA063, SCA064.
    // HttpInsteadOfHttps
    'only the scheme; the server must support https on the default port '
      + '(port 443, valid certificate)',
    // RedundantParentheses
    'one pair of parentheses remains - meaning and precedence unchanged',
    // AttributeMisalignment
    'blank lines only - the attribute belongs to the next element anyway',
    // TwiceInheritedCalls
    'the second call goes away - the parent method runs only once; check '
      + 'order and side effects',
    // PointerSubtraction
    'Win64: the difference is now the full address difference; under range '
      + 'checking (R+) the assignment to an Integer target can raise '
      + 'ERangeError',
    // EmptyFinallyBlock
    'same meaning - an empty finally does nothing, exceptions keep '
      + 'propagating outward',
    // ReversedForRange
    'the loop never ran so far and then counts down; if it was switched off '
      + 'on purpose, this is an intervention',
    // SCA061: den Hinweis setzt PlanTabs - er nennt die Tabweite, die
    // uRdxTabsFix.TabWidth aus den Nachbarzeilen ableitet, bzw. die Annahme 2
    // (rwE29; bis dahin hier fest 'tab width 2 (assumption)', Wochen-Review
    // 2026-10-21, P17).
    // TabulationCharacter
    '',
    // TrailingWhitespace
    'whitespace at the end of the line only',
    // LowercaseKeyword
    'same meaning - Delphi does not distinguish upper and lower case',
    // Charge R (zehn weitere Hilfen): SCA002, SCA159, SCA077, SCA065,
    // SCA068, SCA076, SCA179, SCA180, SCA181, SCA060.
    // EmptyExcept
    'an exception swallowed so far now propagates outward - the caller must '
      + 'handle it; if the swallowing was intended, this is an intervention',
    // EmptyOnHandler
    'the exception is no longer swallowed but passed on to the caller - '
      + 'check program flow and outer handlers',
    // EmptyBlock
    'same meaning - the call stays as a statement and runs exactly once as '
      + 'before; the with header and the empty block go away',
    // NoSonarMarker
    'the marker now stands above the line and suppresses all rules of the '
      + 'line (so far NOSONAR suppressed nothing); critical kinds '
      + '(HardcodedSecret, SQLInjection etc.) stay visible',
    // TrailingCommaArgList
    'same meaning for COM - the empty last argument of the late-bound call '
      + '(an omitted optional parameter) is now not passed at all; only a '
      + 'server that counts its arguments sees one fewer',
    // GroupedDeclaration
    'same meaning - each name keeps its type; with "var" each new line '
      + 'carries the "var" again',
    // AttributeIgnoreWithoutReason
    'replace the placeholder "reason" with the real reason (ticket, '
      + 'dependency, known limitation)',
    // AttributeDuplicate
    'the attribute was there twice - it applies only once anyway',
    // AttributeCategoryWithoutString
    'the placeholder "category" still has to be replaced with the real '
      + 'category name',
    // GotoStatement
    'same meaning - the label is at the end of the routine; it stays and, '
      + 'once no goto jumps to it any more, is reported as an unused label '
      + '(hint/warning)',
    // Charge QF (14 weitere Hilfen). SCA128 / SCA059 (QF1): der Hauptweg
    // nennt die globale FormatSettings nur ausdruecklich - die Ueberladung
    // ohne Settings liest dieselbe Variable (RTL 23.0/37.0, FPC 3.2.2
    // absolute DefaultFormatSettings).
    // DateFormatSettings
    'same meaning - without the argument the RTL reads the same global '
      + 'FormatSettings; the call now says so explicitly',
    // FormatLocaleHint
    'same meaning - Format without a third argument reads the same global '
      + 'FormatSettings; the call now says so explicitly',
    // SCA106 (QF2): bedeutungsgleich (Delphi bindet ohne Gross/klein).
    // MethodName
    'same meaning - Delphi does not distinguish upper and lower case; only '
      + 'declaration and implementation are adjusted, calls keep their '
      + 'spelling (RTTI and MethodName then give the new name)',
    // SCA137 (QF2): gekennzeichnet (E2) - das Ergebnis aendert sich, sobald
    // das Produkt nicht in 32 Bit passt; das ist der Fix.
    // IntegerOverflow
    'the product is now computed in 64 bits - a result above MaxInt is kept '
      + 'instead of silently truncated; with overflow checking (Q+) the '
      + 'exception EIntOverflow goes away',
    // SCA188 / SCA192 (QF3): bedeutungsgleich.
    // SourceBidiOverride
    'same meaning - deleted in comments, as #$ code in strings (same value); '
      + 'the line now shows what the compiler reads',
    // SourceInvisibleChar
    'same meaning - deleted in comments, as #$ code in strings (same value, '
      + 'also in emoji sequences)',
    // SCA113 (QF4): nur mit Beweis Create(True) - bedeutungsgleich.
    // ThreadResumeDeprecated
    'same meaning - the thread was created suspended in this routine '
      + '(Create(True)) and never started; Start then works like Resume',
    // SCA167 (QF4): gekennzeichnet (E2) - die Folge aendert sich.
    // InsecureRandom
    'the random sequence then differs on every run (seed from the clock) - a '
      + 'sequence that was repeatable so far, e.g. for tests, is lost; the '
      + 'call when the unit is loaded affects the whole program; Random '
      + 'stays unsuitable for passwords, tokens and keys',
    // SCA144 (QF5): den Hinweis setzt der Adapter (R_FLOATEQ_HINT).
    // FloatEquality
    '',
    // SCA154 (QF5): gekennzeichnet (E2).
    // MoveSizeOfPointer
    'now copies or fills exactly one element (SizeOf of the target type) '
      + 'instead of 4/8 bytes - if a whole buffer was meant, set the length '
      + 'by hand',
    // SCA017 (QF6): beide Eintraege gekennzeichnet.
    // DebugOutput
    'the output only runs when DEBUG is defined (Delphi: configuration '
      + 'Debug); in the release build it goes away together with the '
      + 'evaluation of its arguments - FPC/Lazarus does not define DEBUG by '
      + 'itself',
    // SCA011 (QF6): bedeutungsgleich - der Code lief nie.
    // DeadCode
    'same meaning - the code never ran; parked code then only lives in '
      + 'version control',
    // SCA131 (QF7): gekennzeichnet (E2) - IfThen wertete beide Arme aus.
    // IfThenShortCircuit
    'only the applicable branch runs now - side effects, costs and '
      + 'exceptions of the other go away; the condition still runs exactly '
      + 'once',
    // SCA169 (QF7): gekennzeichnet (E2) - der Aufruf lief ohne Assertions
    // bisher nicht.
    // AssertWithSideEffect
    'the condition now also runs without assertions (release, $C-) - there '
      + 'only the check goes away; without a message the condition becomes '
      + 'the message text',
    // Charge QF8..QF11. SCA054 / SCA170 (QF8): Deklaration und
    // Implementierung in EINEM Undo-Schritt. SCA170 bleibt ungekennzeichnet
    // (Integrationsnotiz (h) 1: das const-Aliasing nennt der Hinweis).
    // UnusedParameter
    'same meaning - a parameter name is not part of the call; declaration, '
      + 'implementation and <param name> of the documentation are then '
      + 'called "_Name", the detector skips such names',
    // ConstStringParameter
    'same meaning - the body does not write the parameter, nobody uses the '
      + 'routine as a value; declaration and implementation get the const. '
      + 'Exception: if the routine itself changes the variable the caller '
      + 'passes (field, global variable), the const parameter then hangs on '
      + 'freed text',
    // SCA118 / SCA119 (QF9): Umbenennungen, bedeutungsgleich.
    // ExceptionName
    'same meaning - the class is in the implementation part and only visible '
      + 'in this file; every reference in the code is renamed too, comments '
      + 'keep the old name',
    // LocalConstantName
    'same meaning - every reference in the routine is renamed too (also in '
      + 'local routines after it), comments keep the old name',
    // SCA069 / SCA079 (QF10): bedeutungsgleich; SCA069 nur ab Delphi 11.
    // DigitGrouping
    'same meaning - the compiler does not read "_" in numbers; digit '
      + 'separators exist only from Delphi 11 on, FPC does not know them',
    // ConsecutiveSection
    'same meaning - one keyword declares both sections',
    // SCA086 (QF10) und SCA127 (QF11): den Hinweis setzt der Adapter.
    // AvoidOut
    '',
    // RaisingRawException
    '',
    // Charge QF12..QF15. SCA148 (QF12): in DIESER Datei bedeutungsgleich;
    // die Grenze "andere Units" nennt der Hinweis.
    // CanBeClassMethod
    'same meaning - the method needs no object (no Self); calls Obj.M(..) '
      + 'stay valid, a use as method pointer (of object) in another unit '
      + 'then no longer compiles',
    // SCA150 (QF12): der else-Zweig lief nie.
    // BoolAlwaysTrue
    'same meaning - the condition was always true (Length is never '
      + 'negative): the then branch runs as before, an else branch never ran '
      + 'and goes away; if another comparison was meant (e.g. > 0), it is '
      + 'still missing',
    // SCA174 (QF13): gekennzeichnet (E2) - die Liste gibt ihre Elemente frei.
    // TObjectListWithoutOwnership
    'the list now frees its items - on Free, Clear and Delete; checked: '
      + 'every item is created there, does not leave the list and is not '
      + 'freed by hand',
    // SCA193 (QF13): bedeutungsgleich - der Name gilt nur in der Unit.
    // SourceNonAsciiIdentifier
    'same meaning - a letter only looked Latin; all occurrences in the code '
      + 'of the unit are renamed, comments stay',
    // SCA199 (QF14): gekennzeichnet - bisher warf der Aufruf.
    // ParamNameMismatch
    'the call now sets the placeholder from the SQL instead of aborting at '
      + 'run time with "parameter not found" - check that the value belongs '
      + 'to this placeholder',
    // SCA018 (QF14): bedeutungsgleich.
    // DeepNesting
    'same meaning - the condition is evaluated once as before; if it is '
      + 'false, the routine ends as before; the body moves out one level',
    // SCA111/SCA112 (QF15): den Hinweis setzt der Adapter.
    // ParamByNameInLoop
    '',
    // FieldByNameInLoop
    '',
    // SCA203 (Charge A3): gekennzeichnet.
    // LoopPastHighBound
    'the loop runs one pass less (a string loop starts at 1) - if the last '
      + 'pass was meant for a sentinel or a terminator, this is an '
      + 'intervention',
    // Charge A. SCA125 (Q14): bedeutungsgleich - die Sichtbarkeit ist
    // belegt (Vorfahr in der Datei, mindestens so sichtbar).
    // InheritedMethodEmpty
    'same meaning - without the override, virtual dispatch calls the '
      + 'method of the ancestor directly; declaration and implementation go '
      + 'together',
    // Charge N / FN. SCA204: bedeutungsgleich.
    // FunctionNameAsResult
    'same meaning - on the left of ":=" Result and the function name are '
      + 'the same variable; the name in an expression stays (a recursive '
      + 'call, SCA205)'
  );

  // Menuetexte (msgids) unter dem Index der Zeile; '%s' = Name der Hilfe
  // (X bei SCA085/SCA139, die Unit bei SCA007, der Cast-Typ bei SCA123, die
  // Direktive bei SCA149, das Ziel bzw. Exit/Continue bei SCA098/SCA047/
  // SCA080, die Routine bzw. Methode bei SCA164/SCA147, die Variable bei SCA053,
  // X bzw. die Sperre bzw. der Puffer bei SCA009/SCA001/SCA109/SCA153/SCA156,
  // die Anweisung bei SCA096/SCA196, der Wert bei SCA121 - ein Literal oder
  // Default(T), Charge H5c; die Zahl bei SCA014, Charge Q14; das Wort wie
  // gemeldet bei SCA064; der neue Name bei SCA106, der linke Operand bei
  // SCA137, der Empfaenger bei SCA113, SameValue bzw. IsZero bei SCA144,
  // der Zieltyp bei SCA154, die Zahl der Zeilen bei SCA011 - Charge QF; der
  // Parameter bei SCA054/SCA170/SCA086, der neue Name bei SCA118/SCA119,
  // const bzw. var bei SCA079 - Chargen QF8..QF11; der Methodenname bei
  // SCA148, der Elementtyp bei SCA174, der neue ASCII-Name bei SCA193, der
  // eingesetzte Platzhalter bei SCA199, der Aufruf bei SCA111/SCA112 -
  // Chargen QF12..QF15).
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
    'Introduce local constant for %s',
    'Use https:// instead of http://',
    'Remove the redundant inner parentheses',
    'Remove the blank line after the attribute',
    'Remove the second duplicate inherited call',
    'Replace the 32-bit casts with NativeInt/NativeUInt',
    'Remove the empty try/finally',
    'Replace "to" with "downto"',
    'Replace the tabs in this line with spaces',
    'Remove the trailing whitespace',
    'Write %s in lowercase',
    'Add raise; to the empty except block',
    'Add "raise;" to the empty exception handler',
    'Replace the empty "with ... do begin end" by the call',
    'Replace NOSONAR with a "noinspection All" marker',
    'Remove the trailing comma',
    'Split the grouped declaration',
    'Add a reason to [Ignore]',
    'Remove the duplicate attribute',
    'Add a category name to the attribute',
    'Replace "goto" with Exit',
    'Pass FormatSettings explicitly',
    'Pass FormatSettings explicitly',
    'Write the method name as %s',
    'Cast %s to Int64 before multiplying',
    'Remove bidi control characters (as #$ code in strings)',
    'Remove invisible characters (as #$ code in strings)',
    'Use %s.Start instead of Resume',
    'Call Randomize in the initialization section',
    'Use %s instead of the exact comparison',
    'Use SizeOf(%s) instead of the pointer size',
    'Put the debug output in {$IFDEF DEBUG}',
    'Delete the unreachable code: %s line(s)',
    'Replace IfThen with if..then..else',
    'Evaluate the condition outside Assert',
    'Prefix parameter %s with "_" (intentionally unused)',
    'Declare parameter %s as const',
    'Rename the exception class to %s',
    'Rename the constant to %s',
    'Group the digits with "_"',
    'Merge with the previous %s section',
    'Replace "out" with "var" for %s',
    'Raise EArgumentException instead (wrong argument)',
    'Make %s a static class method',
    'Remove the always-true condition',
    'Use TObjectList<%s> so the list frees its items',
    'Write the name in ASCII letters: %s',
    'Use parameter name "%s" from the SQL',
    'Turn the last if into a guard clause with Exit',
    'Move %s before the loop',
    'Move %s before the loop',
    'Let the loop run %s',
    'Remove the empty override %s',
    'Write Result instead of %s'
  );

  // Menuetexte des zweiten Eintrags (Alt), '' ohne.
  FIX_ALT_CAPTIONS: array[0..FIX_ROW_HIGH] of string = (
    '', '', '', '', '', '', '', '', '', '',
    'Add an else branch that raises an exception',
    '', '', '', '', '', '',
    'Raise ENotImplemented in the empty body',
    '', '', '', '', '', '', '', '', '', '', '', '',
    '', '', '', '', '', '', '', '', '', '',
    '', '', '',
    'Remove the first duplicate inherited call',
    '', '',
    'Swap the loop bounds',
    '', '', '',
    '', '', '', '', '', '', '', '', '', '',
    'Pass TFormatSettings.Invariant',
    'Pass TFormatSettings.Invariant',
    '', '', '', '', '', '', '', '',
    'Delete the debug output',
    '', '', '',
    '', '', '', '', '', '', '',
    'Raise EInvalidOpException instead (invalid state)',
    '', '', '', '', '', '', '', '', '', '', ''
  );

  // Die Namen der Planer (PlannerName, fuer uTestRdxFixTable): eine eigene
  // Liste Name -> Planer, unabhaengig von der Reihenfolge in FIX_ROWS. So
  // pinnt der Test je Art den Planer - ein vertauschtes 'Plan:' in FIX_ROWS
  // faellt dort auf (Wochen-Review 2026-10-21, Major P03/P29: welcher Planer
  // an welcher Art haengt, band bis dahin kein Test). Ein neuer Planer
  // braucht hier eine Zeile, sonst nennt PlannerName '?'.
  PLANNER_NAMES: array[0..98] of TRdxPlannerName = (
    (Name: 'PlanExplicitTObject'; Plan: PlanExplicitTObject),
    (Name: 'PlanFreeAndNil'; Plan: PlanFreeAndNil),
    (Name: 'PlanNilComparison'; Plan: PlanNilComparison),
    (Name: 'PlanAssertMessage'; Plan: PlanAssertMessage),
    (Name: 'PlanEmptySection'; Plan: PlanEmptySection),
    (Name: 'PlanFreeWithoutNil'; Plan: PlanFreeWithoutNil),
    (Name: 'PlanEmptyArgs'; Plan: PlanEmptyArgs),
    (Name: 'PlanOperand'; Plan: PlanOperand),
    (Name: 'PlanUnusedUses'; Plan: PlanUnusedUses),
    (Name: 'PlanCaseElse'; Plan: PlanCaseElse),
    (Name: 'PlanCaseRaise'; Plan: PlanCaseRaise),
    (Name: 'PlanBlock'; Plan: PlanBlock),
    (Name: 'PlanDoubleSemicolon'; Plan: PlanDoubleSemicolon),
    (Name: 'PlanKeywordIndent'; Plan: PlanKeywordIndent),
    (Name: 'PlanLegacyInit'; Plan: PlanLegacyInit),
    (Name: 'PlanCastFree'; Plan: PlanCastFree),
    (Name: 'PlanEmptyIntent'; Plan: PlanEmptyIntent),
    (Name: 'PlanEmptyRaise'; Plan: PlanEmptyRaise),
    (Name: 'PlanMissingRaise'; Plan: PlanMissingRaise),
    (Name: 'PlanReRaise'; Plan: PlanReRaise),
    (Name: 'PlanDocSkeleton'; Plan: PlanDocSkeleton),
    (Name: 'PlanInterfaceGuid'; Plan: PlanInterfaceGuid),
    (Name: 'PlanMissingOverride'; Plan: PlanMissingOverride),
    (Name: 'PlanRedundantConditional'; Plan: PlanRedundantConditional),
    (Name: 'PlanRedundantJump'; Plan: PlanRedundantJump),
    (Name: 'PlanSelfAssignment'; Plan: PlanSelfAssignment),
    (Name: 'PlanUnusedRoutine'; Plan: PlanUnusedRoutine),
    (Name: 'PlanUnusedPrivateMethod'; Plan: PlanUnusedPrivateMethod),
    (Name: 'PlanCommentedOut'; Plan: PlanCommentedOut),
    (Name: 'PlanUnusedVar'; Plan: PlanUnusedVar),
    (Name: 'PlanMissingFinally'; Plan: PlanMissingFinally),
    (Name: 'PlanMemoryLeak'; Plan: PlanMemoryLeak),
    (Name: 'PlanLockWithoutFinally'; Plan: PlanLockWithoutFinally),
    (Name: 'PlanUnpairedLock'; Plan: PlanUnpairedLock),
    (Name: 'PlanGetMemWithoutFree'; Plan: PlanGetMemWithoutFree),
    (Name: 'PlanCtorInherited'; Plan: PlanCtorInherited),
    (Name: 'PlanDtorInherited'; Plan: PlanDtorInherited),
    (Name: 'PlanResultDefault'; Plan: PlanResultDefault),
    (Name: 'PlanManagedResult'; Plan: PlanManagedResult),
    (Name: 'PlanMagicNumber'; Plan: PlanMagicNumber),
    (Name: 'PlanHttps'; Plan: PlanHttps),
    (Name: 'PlanRedundantParens'; Plan: PlanRedundantParens),
    (Name: 'PlanAttrGap'; Plan: PlanAttrGap),
    (Name: 'PlanTwiceInherited'; Plan: PlanTwiceInherited),
    (Name: 'PlanTwiceInheritedAlt'; Plan: PlanTwiceInheritedAlt),
    (Name: 'PlanPointerSubtraction'; Plan: PlanPointerSubtraction),
    (Name: 'PlanEmptyFinally'; Plan: PlanEmptyFinally),
    (Name: 'PlanReversedForRange'; Plan: PlanReversedForRange),
    (Name: 'PlanReversedForRangeAlt'; Plan: PlanReversedForRangeAlt),
    (Name: 'PlanTabs'; Plan: PlanTabs),
    (Name: 'PlanTrailingBlanks'; Plan: PlanTrailingBlanks),
    (Name: 'PlanLowercaseKeyword'; Plan: PlanLowercaseKeyword),
    (Name: 'PlanEmptyExcept'; Plan: PlanEmptyExcept),
    (Name: 'PlanEmptyOnHandler'; Plan: PlanEmptyOnHandler),
    (Name: 'PlanEmptyBlock'; Plan: PlanEmptyBlock),
    (Name: 'PlanNoSonar'; Plan: PlanNoSonar),
    (Name: 'PlanTrailingComma'; Plan: PlanTrailingComma),
    (Name: 'PlanGroupedDeclaration'; Plan: PlanGroupedDeclaration),
    (Name: 'PlanIgnoreReason'; Plan: PlanIgnoreReason),
    (Name: 'PlanAttrDuplicate'; Plan: PlanAttrDuplicate),
    (Name: 'PlanCategoryArg'; Plan: PlanCategoryArg),
    (Name: 'PlanGotoExit'; Plan: PlanGotoExit),
    (Name: 'PlanDateFormatSettings'; Plan: PlanDateFormatSettings),
    (Name: 'PlanDateFormatSettingsAlt'; Plan: PlanDateFormatSettingsAlt),
    (Name: 'PlanFormatLocale'; Plan: PlanFormatLocale),
    (Name: 'PlanFormatLocaleAlt'; Plan: PlanFormatLocaleAlt),
    (Name: 'PlanMethodName'; Plan: PlanMethodName),
    (Name: 'PlanIntegerOverflow'; Plan: PlanIntegerOverflow),
    (Name: 'PlanBidiOverride'; Plan: PlanBidiOverride),
    (Name: 'PlanInvisibleChar'; Plan: PlanInvisibleChar),
    (Name: 'PlanThreadResume'; Plan: PlanThreadResume),
    (Name: 'PlanInsecureRandom'; Plan: PlanInsecureRandom),
    (Name: 'PlanFloatEquality'; Plan: PlanFloatEquality),
    (Name: 'PlanMoveSizeOfPointer'; Plan: PlanMoveSizeOfPointer),
    (Name: 'PlanDebugOutput'; Plan: PlanDebugOutput),
    (Name: 'PlanDebugOutputAlt'; Plan: PlanDebugOutputAlt),
    (Name: 'PlanDeadCode'; Plan: PlanDeadCode),
    (Name: 'PlanIfThenToIf'; Plan: PlanIfThenToIf),
    (Name: 'PlanAssertOutside'; Plan: PlanAssertOutside),
    (Name: 'PlanUnusedParameter'; Plan: PlanUnusedParameter),
    (Name: 'PlanConstStringParameter'; Plan: PlanConstStringParameter),
    (Name: 'PlanExceptionName'; Plan: PlanExceptionName),
    (Name: 'PlanLocalConstantName'; Plan: PlanLocalConstantName),
    (Name: 'PlanDigitGrouping'; Plan: PlanDigitGrouping),
    (Name: 'PlanConsecutiveSection'; Plan: PlanConsecutiveSection),
    (Name: 'PlanAvoidOut'; Plan: PlanAvoidOut),
    (Name: 'PlanRaisingRawException'; Plan: PlanRaisingRawException),
    (Name: 'PlanRaisingRawExceptionAlt'; Plan: PlanRaisingRawExceptionAlt),
    (Name: 'PlanCanBeClassMethod'; Plan: PlanCanBeClassMethod),
    (Name: 'PlanBoolAlwaysTrue'; Plan: PlanBoolAlwaysTrue),
    (Name: 'PlanObjectList'; Plan: PlanObjectList),
    (Name: 'PlanHomoglyph'; Plan: PlanHomoglyph),
    (Name: 'PlanParamName'; Plan: PlanParamName),
    (Name: 'PlanDeepNesting'; Plan: PlanDeepNesting),
    (Name: 'PlanParamByNameLoop'; Plan: PlanParamByNameLoop),
    (Name: 'PlanFieldByNameLoop'; Plan: PlanFieldByNameLoop),
    (Name: 'PlanLoopBound'; Plan: PlanLoopBound),
    (Name: 'PlanInheritedMethodEmpty'; Plan: PlanInheritedMethodEmpty),
    (Name: 'PlanFuncNameResult'; Plan: PlanFuncNameResult)
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

class function TRdxFixTable.PlannerName(AIndex, AVariant: Integer): string;
var
  P : TRdxFixPlanner;
  N : TRdxPlannerName;
begin
  if AVariant = 1 then
    P := FIX_ROWS[AIndex].Alt
  else
    P := FIX_ROWS[AIndex].Plan;
  Result := '';
  if not Assigned(P) then Exit;
  // '@' vergleicht die Adressen - ohne riefe Delphi die Planer auf.
  for N in PLANNER_NAMES do
    if @N.Plan = @P then
      Exit(N.Name);
  Result := '?';
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

class function TRdxFixTable.ContextCaption(
  const AOutcome: TRdxContextOutcome): string;
const
  // Die Fund-Hilfe je Code-Aktion der Tabelle (dieselbe Planer-Kette).
  CONTEXT_KINDS: array[ckIntroduceConst..ckTryFinallyCreate] of TFindingKind
    = (fkMagicNumber, fkMissingFinally);
var
  Fix : TRdxFixOutcome;
begin
  // SCA044 ist ein Rezept des Anbieters, keine Zeile von FIX_ROWS: sein
  // Menuetext ohne '%s' und ohne Kennzeichnung (bedeutungsgleich).
  if AOutcome.Kind = ckConcatToFormat then
    Exit(_(CAP_CONTEXT_FORMAT));
  Fix := Default(TRdxFixOutcome);
  Fix.Name := AOutcome.Name;
  Fix.ChangesBehavior := AOutcome.ChangesBehavior;
  // C7 Waechter-Klausel (Charge C78): dieselbe Kette wie die Fund-Hilfe
  // SCA018, also ihr Menuetext (Dedup F2).
  if AOutcome.Kind = ckGuardClause then
    Exit(CaptionFor(fkDeepNesting, Fix));
  // Die anderen C7/C8-Arten haben keine Fund-Hilfe: ihr Text steht beim
  // Laeufer (FPC-Pruefstand).
  if AOutcome.Kind > ckTryFinallyCreate then
    Exit(TRdxContextRunner.CaptionOf(AOutcome));
  Result := CaptionFor(CONTEXT_KINDS[AOutcome.Kind], Fix);
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
