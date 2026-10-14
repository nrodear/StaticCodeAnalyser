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
// die Unit braucht uRdxRecipeRunner, der den Quellstellen-Dienst braucht.
// Die Rumpf-Routinen der Hilfen bleiben, wo sie sind (uRdxRecipeRunner,
// die Planer-Units); hier stehen nur die Adapter auf eine gemeinsame Form
// (TRdxFixPlanner) und die Zeilen.
//
// MENUETEXTE: englische msgids, uebersetzt ueber i18n/*.po (Editorhilfen
// E6). Sie stehen in FIX_CAPTIONS und FIX_ALT_CAPTIONS - zwei String-
// Arrays parallel zu FIX_ROWS, nicht als Feld der Zeile: tools/
// i18n_extract.py liest nur _('..'), _(KONSTANTE) und _(ARRAY[i]); ein
// Record-Feld bliebe fuer template.pot unsichtbar, und msgmerge markierte
// die Uebersetzungen als obsolet. uTestRdxFixTable haelt die drei Arrays
// zusammen (gleicher Index, kein leerer Menuetext, zweiter Menuetext genau
// mit zweitem Planer).

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
  //   Hint           Hinweis des aktiven Eintrags (deutsch, wie die
  //                  Gruende); '' nur mit HintByPlanner: der Planer setzt
  //                  ihn selbst (aus Name oder Ersetzung, bei SCA085/SCA139
  //                  vor dem ' + uses ...'). Genau eines von beiden.
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
    Hint          : string;
    HintByPlanner : Boolean;
    Changes       : Boolean;
    Alt           : TRdxFixPlanner;
  end;

  // Der Einstieg des Anbieters und der Tests. Eine weitere Regel ist eine
  // Zeile mehr in FIX_ROWS samt Menuetext in FIX_CAPTIONS - kein Zweig
  // mehr in einem Verteiler.
  TRdxFixTable = class
  public
    // True, wenn die Tabelle fuer diese Art eine Hilfe kennt.
    class function Handles(AKind: TFindingKind): Boolean; static;

    // Die Hilfe fuer einen Fund: der Planer seiner Art, danach der Hinweis
    // der Zeile (wenn der Planer keinen setzte) und die Kennzeichnung.
    // Ohne Fund: Reason 'kein Fund'; ohne Zeile: 'keine einfache Hilfe
    // fuer diese Regel'.
    class function FixFor(APlaces: TSourcePlaces; ALines: TStrings;
      AFinding: TLeakFinding;
      const AUsesNames: TArray<string>): TRdxFixOutcome; static;

    // Der zweite Eintrag fuer denselben Fund (Variant = 1), sonst ein
    // leeres Ergebnis (Variant = 0).
    class function AlternativeFixFor(APlaces: TSourcePlaces; ALines: TStrings;
      AFinding: TLeakFinding;
      const AUsesNames: TArray<string>): TRdxFixOutcome; static;

    // Menuetext einer Hilfe, uebersetzt: der Eintrag nach AOutcome.Variant,
    // '%s' durch AOutcome.Name ('X', wenn der Planer abgelehnt hat, bevor
    // der Name feststand), dahinter die Kennzeichnung bei ChangesBehavior.
    // '' ohne Zeile - dann entsteht KEIN Eintrag (bis Charge R8 stand dann
    // KindName im Menue).
    class function CaptionFor(AKind: TFindingKind;
      const AOutcome: TRdxFixOutcome): string; static;

    // Fuer uTestRdxFixTable: die Zeilen und ihre Menuetexte (msgids,
    // unuebersetzt; AVariant 0 oder 1).
    class function RowCount: Integer; static;
    class function Row(AIndex: Integer): TRdxFixRow; static;
    class function RawCaption(AIndex, AVariant: Integer): string; static;
  end;

implementation

uses
  System.SysUtils,
  uLocalization,     // _()
  uRdxRecipes,       // AsciiOnly (SCA085-Gegenprobe)
  uRdxCodeMap,       // TRdxCodeMap (Adapter auf die Code-Sicht)
  uRdxBufferMath,    // TRdxEdit
  uRdxSimpleFixes,   // SCA075, SCA087 (ExplicitTObject, EmptySection)
  uRdxLineFixes,     // SCA082, SCA071, SCA088
  uRdxRaiseFixes,    // SCA020, SCA120, SCA122
  uRdxDeclFixes,     // SCA117, SCA197, SCA149
  uRdxFlowFixes;     // SCA098, SCA080, SCA047

const
  // Hinweise der Hilfen (deutsch wie die Gruende; Pruefstand und Tests
  // pruefen sie woertlich). Bis Charge R8 in uRdxRecipeRunner (LineHint,
  // DeclHint, FlowHint und je Rumpf) - bis auf die ersten vier: SCA075,
  // SCA074, SCA087 und SCA066 bekommen mit der Tabelle ERSTMALS einen
  // festen Hinweis; bis dahin blieb ihr Hint leer, und der Eintrag stand
  // ohne Erklaerung im Menue (Gegen-Review R8, Major 1; uTestRdxFixTable
  // pinnt R_TOBJECT_HINT woertlich).
  R_TOBJECT_HINT  = 'TObject ist ohnehin der Vorfahr - gleiche Bedeutung';
  R_ASSERT_HINT   = 'die Bedingung als Text - so nennt die Meldung, was '
    + 'fehlschlug';
  R_EMPTYSEC_HINT = 'der Abschnitt war leer - gleiche Bedeutung';
  R_NOARGS_HINT   = 'gleiche Bedeutung - Delphi ruft die Routine auch ohne '
    + 'Klammern auf';
  R_CASE_ELSE_HINT = 'alle anderen Werte: nichts tun (wie bisher)';
  R_BLOCK_HINT     = 'gleiche Bedeutung - nur die Form; eine weitere '
    + 'Anweisung gehoert danach sichtbar in den Zweig';
  R_SEMI_HINT   = 'das zweite ";" war eine leere Anweisung';
  R_INDENT_HINT = 'nur Leerraum';
  R_INIT_HINT   = 'gleiche Bedeutung - der Abschnitt kann danach ein '
    + 'finalization bekommen';
  R_EMPTY_HINT  = 'die Absicht steht im Rumpf - ein Grund dahinter hilft dem '
    + 'naechsten Leser';
  R_MISSING_RAISE_HINT = 'die Exception wird jetzt ausgeloest - der Code '
    + 'dahinter laeuft im Fehlerfall nicht mehr';
  R_RERAISE_HINT = 'dieselbe Exception - der Original-Stack-Trace bleibt '
    + 'erhalten';
  R_DOC_HINT     = 'das Geruest ist leer - summary, param und returns '
    + 'ausfuellen';
  R_GUID_HINT    = 'eine neue GUID - nur fuer eigene Interfaces, nie fuer '
    + 'COM-Importe';
  R_OVERRIDE_HINT = 'der virtuelle Aufruf landet danach in dieser Methode';
  R_REINTRODUCE_HINT = 'nur die Warnung W1010 entfaellt - die Methode '
    + 'verdeckt die geerbten weiterhin';
  R_COND_HINT = 'gleiche Bedeutung - eine Zuweisung statt zweier Zweige';
  R_JUMP_HINT = 'gleiche Bedeutung - der Ablauf verlaesst den Block ohnehin';
  R_SELF_HINT = 'die Zuweisung bewirkt nichts - war ein anderer Wert gemeint '
    + '(Tippfehler), fehlt er weiterhin';
  R_NO_FINDING = 'kein Fund';
  R_NO_ROW     = 'keine einfache Hilfe fuer diese Regel';
  // Entscheid E2: eine Hilfe, die das Verhalten aendern kann, sagt es.
  CAP_CHANGES  = '(changes behavior)';
  NAME_UNKNOWN = 'X';

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
    Result.Reason  := Format('Zeile %d traegt %s.Free, der Fund nennt %s - '
      + 'Zeile verschoben? Datei neu pruefen',
      [AFinding.LineInt, Result.Name, Named]);
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
    Result.Hint := R_OVERRIDE_HINT
  else
    Result.Hint := R_REINTRODUCE_HINT;
end;

function PlanRedundantConditional(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := FlowFix(APlaces, ALines, AFinding,
    TRdxFlowFixes.RedundantConditional, CondAssignReason);
end;

function PlanRedundantJump(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := FlowFix(APlaces, ALines, AFinding, TRdxFlowFixes.RedundantJump, nil);
end;

// SCA047 prueft das Ziel des Plans (SelfAssignReason nimmt den Namen).
function SelfAssignPlanReason(APlaces: TSourcePlaces; AMap: TRdxCodeMap;
  ALine: Integer; const APlan: TRdxFlowPlan): string;
begin
  Result := SelfAssignReason(APlaces, AMap, ALine, APlan.Target);
end;

function PlanSelfAssignment(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
begin
  Result := FlowFix(APlaces, ALines, AFinding, TRdxFlowFixes.SelfAssignment,
    SelfAssignPlanReason);
end;

{ ---- Die Tabelle ---- }

const
  FIX_ROW_HIGH = 25;

  // Je Art eine Zeile; die Reihenfolge ist die der Chargen (Stufe 2a,
  // Stufe 2 Rest, uQuickFix-Umzug/Stufe 3, Zeilen, Ausnahmen, Deklarationen
  // H1, Anweisungen H2). Der Menuetext steht unter demselben Index in
  // FIX_CAPTIONS (s. Kopf).
  FIX_ROWS: array[0..FIX_ROW_HIGH] of TRdxFixRow = (
    (Kind: fkExplicitTObjectInheritance; Plan: PlanExplicitTObject;
     Hint: R_TOBJECT_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkFreeAndNilHint; Plan: PlanFreeAndNil;
     Hint: ''; HintByPlanner: True; Changes: False; Alt: nil),
    (Kind: fkNilComparison; Plan: PlanNilComparison;
     Hint: ''; HintByPlanner: True; Changes: False; Alt: nil),
    (Kind: fkAssertMessage; Plan: PlanAssertMessage;
     Hint: R_ASSERT_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkEmptyVisibilitySection; Plan: PlanEmptySection;
     Hint: R_EMPTYSEC_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkFreeWithoutNil; Plan: PlanFreeWithoutNil;
     Hint: ''; HintByPlanner: True; Changes: False; Alt: nil),
    (Kind: fkEmptyArgumentList; Plan: PlanEmptyArgs;
     Hint: R_NOARGS_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkRedundantBoolean; Plan: PlanOperand;
     Hint: ''; HintByPlanner: True; Changes: False; Alt: nil),
    (Kind: fkAssignedAndAssignedNil; Plan: PlanOperand;
     Hint: ''; HintByPlanner: True; Changes: False; Alt: nil),
    // SCA007: der initialization-Abschnitt der Unit laeuft nicht mehr (E2).
    (Kind: fkUnusedUses; Plan: PlanUnusedUses;
     Hint: ''; HintByPlanner: True; Changes: True; Alt: nil),
    (Kind: fkDefaultCaseInCaseStatement; Plan: PlanCaseElse;
     Hint: R_CASE_ELSE_HINT; HintByPlanner: False; Changes: False;
     Alt: PlanCaseRaise),
    (Kind: fkBeginEndRequired; Plan: PlanBlock;
     Hint: R_BLOCK_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkIfElseBegin; Plan: PlanBlock;
     Hint: R_BLOCK_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkSuperfluousSemicolon; Plan: PlanDoubleSemicolon;
     Hint: R_SEMI_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkUnitLevelKeywordIndent; Plan: PlanKeywordIndent;
     Hint: R_INDENT_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkLegacyInitializationSection; Plan: PlanLegacyInit;
     Hint: R_INIT_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkCastAndFree; Plan: PlanCastFree;
     Hint: ''; HintByPlanner: True; Changes: False; Alt: nil),
    (Kind: fkEmptyMethod; Plan: PlanEmptyIntent;
     Hint: R_EMPTY_HINT; HintByPlanner: False; Changes: False;
     Alt: PlanEmptyRaise),
    // SCA120: die Exception wird jetzt ausgeloest - das ist der Fix (E2).
    (Kind: fkMissingRaise; Plan: PlanMissingRaise;
     Hint: R_MISSING_RAISE_HINT; HintByPlanner: False; Changes: True; Alt: nil),
    (Kind: fkReRaiseException; Plan: PlanReRaise;
     Hint: R_RERAISE_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkPublicMemberWithoutDoc; Plan: PlanDocSkeleton;
     Hint: R_DOC_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkInterfaceWithoutGuid; Plan: PlanInterfaceGuid;
     Hint: R_GUID_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkMissingOverride; Plan: PlanMissingOverride;
     Hint: ''; HintByPlanner: True; Changes: False; Alt: nil),
    (Kind: fkRedundantConditional; Plan: PlanRedundantConditional;
     Hint: R_COND_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkRedundantJump; Plan: PlanRedundantJump;
     Hint: R_JUMP_HINT; HintByPlanner: False; Changes: False; Alt: nil),
    (Kind: fkSelfAssignment; Plan: PlanSelfAssignment;
     Hint: R_SELF_HINT; HintByPlanner: False; Changes: False; Alt: nil)
  );

  // Menuetexte (msgids) unter dem Index der Zeile; '%s' = Name der Hilfe
  // (X bei SCA085/SCA139, die Unit bei SCA007, der Cast-Typ bei SCA123, die
  // Direktive bei SCA149, das Ziel bzw. Exit/Continue bei SCA098/SCA047/
  // SCA080).
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
    'Remove the self-assignment of %s'
  );

  // Menuetexte des zweiten Eintrags (Alt), '' ohne.
  FIX_ALT_CAPTIONS: array[0..FIX_ROW_HIGH] of string = (
    '', '', '', '', '', '', '', '', '', '',
    'Add an else branch that raises an exception',
    '', '', '', '', '', '',
    'Raise ENotImplemented in the empty body',
    '', '', '', '', '', '', '', ''
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

class function TRdxFixTable.FixFor(APlaces: TSourcePlaces; ALines: TStrings;
  AFinding: TLeakFinding; const AUsesNames: TArray<string>): TRdxFixOutcome;
var
  Idx : Integer;
begin
  Result := Default(TRdxFixOutcome);
  if not Assigned(AFinding) then
  begin
    Result.Reason := R_NO_FINDING;
    Exit;
  end;
  Idx := GRowIndex[AFinding.Kind];
  if Idx < 0 then
  begin
    Result.Reason := R_NO_ROW;
    Exit;
  end;
  Result := FIX_ROWS[Idx].Plan(APlaces, ALines, AFinding, AUsesNames);
  if Result.Enabled and (Result.Hint = '') then
    Result.Hint := FIX_ROWS[Idx].Hint;
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
