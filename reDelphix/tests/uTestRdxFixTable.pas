unit uTestRdxFixTable;

// Die Tabelle der einfachen Editorhilfen (uRdxFixTable, Charge R8): jede
// Zeile vollstaendig - Planer, Hinweis (fest oder vom Planer), Menuetext,
// zweiter Eintrag genau mit zweitem Menuetext -, die Arten eindeutig und
// gleich Handles, Menuetexte mit Name, Variante und Kennzeichnung, der
// Einstieg ohne Fund und ohne Zeile, Hinweis und Kennzeichnung aus der
// Zeile. Bis Charge R8 zeigte eine Art ohne Menuetext still ihren internen
// Namen, und kein Test fiel (Wochen-Review 2026-10-13, Bereich B, Major 4).
// Nur in reDelphix.Test (die Tabelle braucht den Laeufer, nicht im
// FPC-Pruefstand).
//
// Seit dem Wochen-Review 2026-10-21 (Major P03/P29) pinnt EXPECTED jede
// Zeile: Art, Planer (Name ueber TRdxFixTable.PlannerName), Menuetext
// (msgid aus FIX_CAPTIONS), Kennzeichnung und zweiten Eintrag samt
// Menuetext. Vorher prueften die Tests nur "nicht leer" und "nicht
// KindName": ein vertauschtes 'Plan:' (PlanTabs/PlanTrailingBlanks) oder
// ein am Ende angehaengter Menuetext blieb gruen. Eine neue Zeile in
// FIX_ROWS braucht hier ihre Zeile - an derselben Stelle.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxFixTable = class
  public
    [Test] procedure EveryRow_HasPlanHintAndCaption;
    [Test] procedure Rows_UniqueAndEqualHandles;
    [Test] procedure CaptionFor_NameVariantChanges;
    [Test] procedure FixFor_NoFindingOrRow;
    [Test] procedure FixFor_TableHintAndChanges;
    // Charge FB (missed R5(5), Absprache mit FE zu R5-06): der feste
    // Hinweis von SCA121 stimmt fuer jeden eingesetzten Wert.
    [Test] procedure ResultDefaultHint_NamesShownValue;
    // Wochen-Review 2026-10-21: die Zeilen fest gepinnt
    [Test] procedure Table_PinsPlannerCaptionChangesAlt;
    [Test] procedure AltRows_SetVariantOne;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uMethodd12, uSCAConsts, uRdxRecipeRunner, uRdxFixTable,
  uRdxText,          // MsgNoFileOpen, _: Texte in der Sprache des Laufs (de)
  uTestRdxTextKit;   // Join

type
  // Eine erwartete Zeile der Tabelle (Index = Index in FIX_ROWS).
  TExpectedRow = record
    Kind       : TFindingKind;
    Plan       : string;    // Name des Planers (PLANNER_NAMES)
    Caption    : string;    // msgid aus FIX_CAPTIONS
    Changes    : Boolean;   // Kennzeichnung der Zeile (E2)
    Alt        : string;    // zweiter Planer, '' ohne
    AltCaption : string;    // msgid aus FIX_ALT_CAPTIONS, '' ohne
  end;

const
  // Von Hand gegen FIX_ROWS, FIX_CAPTIONS und FIX_ALT_CAPTIONS geprueft
  // (Stand b2538e20, Chargen bis R; Charge QF bei der Integration
  // 2026-10-22 gegen die Integrationsnotizen, ebenso QF8..QF11 und
  // QF12..QF15): jede Art mit ihrem Planer und ihrem Menuetext.
  // Gekennzeichnet (Changes) sind SCA007, SCA120, die Hilfen der Charge H4,
  // SCA121, SCA196, SCA115, SCA093, SCA161, SCA046, SCA002, SCA159 und
  // SCA065 sowie SCA137, SCA167, SCA144, SCA154, SCA017, SCA131, SCA169,
  // SCA127, SCA174, SCA199, SCA111 und SCA112; SCA149, SCA096, SCA097 und
  // SCA086 kennzeichnet der Planer, die zweiten Eintraege von SCA128/SCA059
  // kennzeichnen sich selbst.
  EXPECTED: array[0..90] of TExpectedRow = (
    (Kind: fkExplicitTObjectInheritance; Plan: 'PlanExplicitTObject';
     Caption: 'Remove (TObject) from the class declaration';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkFreeAndNilHint; Plan: 'PlanFreeAndNil';
     Caption: 'Use FreeAndNil(%s)';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkNilComparison; Plan: 'PlanNilComparison';
     Caption: 'Use Assigned() instead of comparing with nil';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkAssertMessage; Plan: 'PlanAssertMessage';
     Caption: 'Use the condition as the Assert message';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkEmptyVisibilitySection; Plan: 'PlanEmptySection';
     Caption: 'Remove the empty visibility section';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkFreeWithoutNil; Plan: 'PlanFreeWithoutNil';
     Caption: 'Use FreeAndNil(%s)';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkEmptyArgumentList; Plan: 'PlanEmptyArgs';
     Caption: 'Remove the empty parentheses';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkRedundantBoolean; Plan: 'PlanOperand';
     Caption: 'Remove the redundant comparison with True/False';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkAssignedAndAssignedNil; Plan: 'PlanOperand';
     Caption: 'Remove the redundant comparison with nil';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkUnusedUses; Plan: 'PlanUnusedUses';
     Caption: 'Remove unit %s from uses';
     Changes: True; Alt: ''; AltCaption: ''),
    (Kind: fkDefaultCaseInCaseStatement; Plan: 'PlanCaseElse';
     Caption: 'Add an empty else branch';
     Changes: False; Alt: 'PlanCaseRaise';
     AltCaption: 'Add an else branch that raises an exception'),
    (Kind: fkBeginEndRequired; Plan: 'PlanBlock';
     Caption: 'Put the branch in begin..end';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkIfElseBegin; Plan: 'PlanBlock';
     Caption: 'Put the branch in begin..end';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkSuperfluousSemicolon; Plan: 'PlanDoubleSemicolon';
     Caption: 'Remove the extra semicolon';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkUnitLevelKeywordIndent; Plan: 'PlanKeywordIndent';
     Caption: 'Move the keyword to column 1';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkLegacyInitializationSection; Plan: 'PlanLegacyInit';
     Caption: 'Replace begin with initialization';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkCastAndFree; Plan: 'PlanCastFree';
     Caption: 'Remove the cast to %s before Free';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkEmptyMethod; Plan: 'PlanEmptyIntent';
     Caption: 'Mark the empty body as intentional';
     Changes: False; Alt: 'PlanEmptyRaise';
     AltCaption: 'Raise ENotImplemented in the empty body'),
    (Kind: fkMissingRaise; Plan: 'PlanMissingRaise';
     Caption: 'Raise the exception';
     Changes: True; Alt: ''; AltCaption: ''),
    (Kind: fkReRaiseException; Plan: 'PlanReRaise';
     Caption: 'Use raise; to keep the original stack trace';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkPublicMemberWithoutDoc; Plan: 'PlanDocSkeleton';
     Caption: 'Insert a documentation skeleton';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkInterfaceWithoutGuid; Plan: 'PlanInterfaceGuid';
     Caption: 'Insert a new GUID';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkMissingOverride; Plan: 'PlanMissingOverride';
     Caption: 'Add "%s;" to the declaration';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkRedundantConditional; Plan: 'PlanRedundantConditional';
     Caption: 'Assign the condition to %s directly';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkRedundantJump; Plan: 'PlanRedundantJump';
     Caption: 'Remove the redundant %s';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkSelfAssignment; Plan: 'PlanSelfAssignment';
     Caption: 'Remove the self-assignment of %s';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkUnusedRoutine; Plan: 'PlanUnusedRoutine';
     Caption: 'Delete unused routine %s';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkUnusedPrivateMethod; Plan: 'PlanUnusedPrivateMethod';
     Caption: 'Delete unused private method %s';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkCommentedOutCode; Plan: 'PlanCommentedOut';
     Caption: 'Delete commented-out code';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkUnusedLocalVar; Plan: 'PlanUnusedVar';
     Caption: 'Remove unused variable %s';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkMissingFinally; Plan: 'PlanMissingFinally';
     Caption: 'Free %s in a try/finally block';
     Changes: True; Alt: ''; AltCaption: ''),
    (Kind: fkMemoryLeak; Plan: 'PlanMemoryLeak';
     Caption: 'Free %s in a try/finally block';
     Changes: True; Alt: ''; AltCaption: ''),
    (Kind: fkLockWithoutTryFinally; Plan: 'PlanLockWithoutFinally';
     Caption: 'Release the lock %s in a try/finally block';
     Changes: True; Alt: ''; AltCaption: ''),
    (Kind: fkUnpairedLock; Plan: 'PlanUnpairedLock';
     Caption: 'Release the lock %s in a try/finally block';
     Changes: True; Alt: ''; AltCaption: ''),
    (Kind: fkGetMemWithoutFreeMem; Plan: 'PlanGetMemWithoutFree';
     Caption: 'Free the buffer %s in a try/finally block';
     Changes: True; Alt: ''; AltCaption: ''),
    (Kind: fkConstructorWithoutInherited; Plan: 'PlanCtorInherited';
     Caption: 'Call %s first in the constructor';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkDestructorWithoutInherited; Plan: 'PlanDtorInherited';
     Caption: 'Call inherited last in the destructor';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkRoutineResultUnassigned; Plan: 'PlanResultDefault';
     Caption: 'Initialize Result with %s';
     Changes: True; Alt: ''; AltCaption: ''),
    (Kind: fkManagedResultUninit; Plan: 'PlanManagedResult';
     Caption: 'Initialize Result first: %s';
     Changes: True; Alt: ''; AltCaption: ''),
    (Kind: fkMagicNumber; Plan: 'PlanMagicNumber';
     Caption: 'Introduce local constant for %s';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkHttpInsteadOfHttps; Plan: 'PlanHttps';
     Caption: 'Use https:// instead of http://';
     Changes: True; Alt: ''; AltCaption: ''),
    (Kind: fkRedundantParentheses; Plan: 'PlanRedundantParens';
     Caption: 'Remove the redundant inner parentheses';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkAttributeMisalignment; Plan: 'PlanAttrGap';
     Caption: 'Remove the blank line after the attribute';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkTwiceInheritedCalls; Plan: 'PlanTwiceInherited';
     Caption: 'Remove the second duplicate inherited call';
     Changes: True; Alt: 'PlanTwiceInheritedAlt';
     AltCaption: 'Remove the first duplicate inherited call'),
    (Kind: fkPointerSubtraction; Plan: 'PlanPointerSubtraction';
     Caption: 'Replace the 32-bit casts with NativeInt/NativeUInt';
     Changes: True; Alt: ''; AltCaption: ''),
    (Kind: fkEmptyFinallyBlock; Plan: 'PlanEmptyFinally';
     Caption: 'Remove the empty try/finally';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkReversedForRange; Plan: 'PlanReversedForRange';
     Caption: 'Replace "to" with "downto"';
     Changes: True; Alt: 'PlanReversedForRangeAlt';
     AltCaption: 'Swap the loop bounds'),
    (Kind: fkTabulationCharacter; Plan: 'PlanTabs';
     Caption: 'Replace the tabs in this line with spaces';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkTrailingWhitespace; Plan: 'PlanTrailingBlanks';
     Caption: 'Remove the trailing whitespace';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkLowercaseKeyword; Plan: 'PlanLowercaseKeyword';
     Caption: 'Write %s in lowercase';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkEmptyExcept; Plan: 'PlanEmptyExcept';
     Caption: 'Add raise; to the empty except block';
     Changes: True; Alt: ''; AltCaption: ''),
    (Kind: fkEmptyOnHandler; Plan: 'PlanEmptyOnHandler';
     Caption: 'Add "raise;" to the empty exception handler';
     Changes: True; Alt: ''; AltCaption: ''),
    (Kind: fkEmptyBlock; Plan: 'PlanEmptyBlock';
     Caption: 'Replace the empty "with ... do begin end" by the call';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkNoSonarMarker; Plan: 'PlanNoSonar';
     Caption: 'Replace NOSONAR with a "noinspection All" marker';
     Changes: True; Alt: ''; AltCaption: ''),
    (Kind: fkTrailingCommaArgList; Plan: 'PlanTrailingComma';
     Caption: 'Remove the trailing comma';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkGroupedDeclaration; Plan: 'PlanGroupedDeclaration';
     Caption: 'Split the grouped declaration';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkAttributeIgnoreWithoutReason; Plan: 'PlanIgnoreReason';
     Caption: 'Add a reason to [Ignore]';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkAttributeDuplicate; Plan: 'PlanAttrDuplicate';
     Caption: 'Remove the duplicate attribute';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkAttributeCategoryWithoutString; Plan: 'PlanCategoryArg';
     Caption: 'Add a category name to the attribute';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkGotoStatement; Plan: 'PlanGotoExit';
     Caption: 'Replace "goto" with Exit';
     Changes: False; Alt: ''; AltCaption: ''),
    // Charge QF (14 weitere Hilfen).
    (Kind: fkDateFormatSettings; Plan: 'PlanDateFormatSettings';
     Caption: 'Pass FormatSettings explicitly';
     Changes: False; Alt: 'PlanDateFormatSettingsAlt';
     AltCaption: 'Pass TFormatSettings.Invariant'),
    (Kind: fkFormatLocaleHint; Plan: 'PlanFormatLocale';
     Caption: 'Pass FormatSettings explicitly';
     Changes: False; Alt: 'PlanFormatLocaleAlt';
     AltCaption: 'Pass TFormatSettings.Invariant'),
    (Kind: fkMethodName; Plan: 'PlanMethodName';
     Caption: 'Write the method name as %s';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkIntegerOverflow; Plan: 'PlanIntegerOverflow';
     Caption: 'Cast %s to Int64 before multiplying';
     Changes: True; Alt: ''; AltCaption: ''),
    (Kind: fkSourceBidiOverride; Plan: 'PlanBidiOverride';
     Caption: 'Remove bidi control characters (as #$ code in strings)';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkSourceInvisibleChar; Plan: 'PlanInvisibleChar';
     Caption: 'Remove invisible characters (as #$ code in strings)';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkThreadResumeDeprecated; Plan: 'PlanThreadResume';
     Caption: 'Use %s.Start instead of Resume';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkInsecureRandom; Plan: 'PlanInsecureRandom';
     Caption: 'Call Randomize in the initialization section';
     Changes: True; Alt: ''; AltCaption: ''),
    (Kind: fkFloatEquality; Plan: 'PlanFloatEquality';
     Caption: 'Use %s instead of the exact comparison';
     Changes: True; Alt: ''; AltCaption: ''),
    (Kind: fkMoveSizeOfPointer; Plan: 'PlanMoveSizeOfPointer';
     Caption: 'Use SizeOf(%s) instead of the pointer size';
     Changes: True; Alt: ''; AltCaption: ''),
    (Kind: fkDebugOutput; Plan: 'PlanDebugOutput';
     Caption: 'Put the debug output in {$IFDEF DEBUG}';
     Changes: True; Alt: 'PlanDebugOutputAlt';
     AltCaption: 'Delete the debug output'),
    (Kind: fkDeadCode; Plan: 'PlanDeadCode';
     Caption: 'Delete the unreachable code: %s line(s)';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkIfThenShortCircuit; Plan: 'PlanIfThenToIf';
     Caption: 'Replace IfThen with if..then..else';
     Changes: True; Alt: ''; AltCaption: ''),
    (Kind: fkAssertWithSideEffect; Plan: 'PlanAssertOutside';
     Caption: 'Evaluate the condition outside Assert';
     Changes: True; Alt: ''; AltCaption: ''),
    // Chargen QF8..QF11 (8 weitere Hilfen).
    (Kind: fkUnusedParameter; Plan: 'PlanUnusedParameter';
     Caption: 'Prefix parameter %s with "_" (intentionally unused)';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkConstStringParameter; Plan: 'PlanConstStringParameter';
     Caption: 'Declare parameter %s as const';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkExceptionName; Plan: 'PlanExceptionName';
     Caption: 'Rename the exception class to %s';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkLocalConstantName; Plan: 'PlanLocalConstantName';
     Caption: 'Rename the constant to %s';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkDigitGrouping; Plan: 'PlanDigitGrouping';
     Caption: 'Group the digits with "_"';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkConsecutiveSection; Plan: 'PlanConsecutiveSection';
     Caption: 'Merge with the previous %s section';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkAvoidOut; Plan: 'PlanAvoidOut';
     Caption: 'Replace "out" with "var" for %s';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkRaisingRawException; Plan: 'PlanRaisingRawException';
     Caption: 'Raise EArgumentException instead (wrong argument)';
     Changes: True; Alt: 'PlanRaisingRawExceptionAlt';
     AltCaption: 'Raise EInvalidOpException instead (invalid state)'),
    // Chargen QF12..QF15 (8 weitere Hilfen).
    (Kind: fkCanBeClassMethod; Plan: 'PlanCanBeClassMethod';
     Caption: 'Make %s a static class method';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkBoolAlwaysTrue; Plan: 'PlanBoolAlwaysTrue';
     Caption: 'Remove the always-true condition';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkTObjectListWithoutOwnership; Plan: 'PlanObjectList';
     Caption: 'Use TObjectList<%s> so the list frees its items';
     Changes: True; Alt: ''; AltCaption: ''),
    (Kind: fkSourceNonAsciiIdentifier; Plan: 'PlanHomoglyph';
     Caption: 'Write the name in ASCII letters: %s';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkParamNameMismatch; Plan: 'PlanParamName';
     Caption: 'Use parameter name "%s" from the SQL';
     Changes: True; Alt: ''; AltCaption: ''),
    (Kind: fkDeepNesting; Plan: 'PlanDeepNesting';
     Caption: 'Turn the last if into a guard clause with Exit';
     Changes: False; Alt: ''; AltCaption: ''),
    (Kind: fkParamByNameInLoop; Plan: 'PlanParamByNameLoop';
     Caption: 'Move %s before the loop';
     Changes: True; Alt: ''; AltCaption: ''),
    (Kind: fkFieldByNameInLoop; Plan: 'PlanFieldByNameLoop';
     Caption: 'Move %s before the loop';
     Changes: True; Alt: ''; AltCaption: ''),
    // Charge A (SCA125, Q14).
    (Kind: fkInheritedMethodEmpty; Plan: 'PlanInheritedMethodEmpty';
     Caption: 'Remove the empty override %s';
     Changes: False; Alt: ''; AltCaption: '')
  );

procedure TTestRdxFixTable.EveryRow_HasPlanHintAndCaption;
var
  i : Integer;
  R : TRdxFixRow;
  K : string;
begin
  Assert.IsTrue(TRdxFixTable.RowCount > 20, 'die Tabelle ist gefuellt');
  for i := 0 to TRdxFixTable.RowCount - 1 do
  begin
    R := TRdxFixTable.Row(i);
    K := KindName(R.Kind);
    Assert.IsTrue(Assigned(R.Plan), K + ': Planer');
    // Seit Charge G7 steht der feste Hinweis in FIX_HINTS (RawHint), nicht
    // mehr als Feld der Zeile.
    Assert.IsTrue((TRdxFixTable.RawHint(i) <> '') <> R.HintByPlanner,
      K + ': Hinweis fest ODER vom Planer, nicht beides und nicht keins');
    Assert.AreNotEqual('', TRdxFixTable.RawCaption(i, 0), K + ': Menuetext');
    Assert.AreNotEqual(K, TRdxFixTable.RawCaption(i, 0),
      K + ': der Menuetext ist nicht der interne Name');
    Assert.IsTrue(Assigned(R.Alt) = (TRdxFixTable.RawCaption(i, 1) <> ''),
      K + ': zweiter Eintrag genau mit zweitem Menuetext');
  end;
end;

procedure TTestRdxFixTable.Rows_UniqueAndEqualHandles;
var
  Seen : array[TFindingKind] of Boolean;
  K    : TFindingKind;
  i, n : Integer;
begin
  for K := Low(TFindingKind) to High(TFindingKind) do
    Seen[K] := False;
  for i := 0 to TRdxFixTable.RowCount - 1 do
  begin
    K := TRdxFixTable.Row(i).Kind;
    Assert.IsFalse(Seen[K], KindName(K) + ' steht zweimal in der Tabelle');
    Seen[K] := True;
  end;
  n := 0;
  for K := Low(TFindingKind) to High(TFindingKind) do
  begin
    Assert.AreEqual(Seen[K], TRdxFixTable.Handles(K), 'Handles: ' + KindName(K));
    if Seen[K] then Inc(n);
  end;
  Assert.AreEqual<Integer>(TRdxFixTable.RowCount, n);
end;

procedure TTestRdxFixTable.CaptionFor_NameVariantChanges;
// Seit Charge C0 (Entscheid E29) uebersetzt CaptionFor in die reDelphix-
// Sprache, und der Testlauf steht auf Deutsch (reDelphix.Test.dpr): die
// Erwartungen sind die msgstr aus i18n/de.po - so prueft der Test auch,
// dass die msgids dort stehen. Die englische msgid selbst liefert
// RawCaption.
var
  O : TRdxFixOutcome;
  i : Integer;
begin
  O := Default(TRdxFixOutcome);
  O.Name := 'Obj';
  Assert.AreEqual('FreeAndNil(Obj) verwenden',
    TRdxFixTable.CaptionFor(fkFreeAndNilHint, O));
  O.Name := '';
  Assert.AreEqual('FreeAndNil(X) verwenden',
    TRdxFixTable.CaptionFor(fkFreeWithoutNil, O), 'ohne Namen steht X');
  Assert.AreEqual('Assigned() statt Vergleich mit nil verwenden',
    TRdxFixTable.CaptionFor(fkNilComparison, O));
  O.Variant := 1;
  Assert.AreEqual('else-Zweig mit Exception erg'#$00E4'nzen',
    TRdxFixTable.CaptionFor(fkDefaultCaseInCaseStatement, O));
  Assert.AreEqual('ENotImplemented im leeren Rumpf ausl'#$00F6'sen',
    TRdxFixTable.CaptionFor(fkEmptyMethod, O));
  Assert.AreEqual('', TRdxFixTable.CaptionFor(fkSuperfluousSemicolon, O),
    'ohne zweiten Eintrag kein Menuetext');
  O.Variant := 0;
  O.ChangesBehavior := True;
  O.Name := 'System.Classes';
  Assert.AreEqual('Unit System.Classes aus uses entfernen ('#$00E4'ndert '
    + 'Verhalten)', TRdxFixTable.CaptionFor(fkUnusedUses, O));
  Assert.AreEqual('', TRdxFixTable.CaptionFor(fkConcatToFormat, O),
    'ohne Zeile kein Menuetext (und kein KindName)');
  for i := 0 to TRdxFixTable.RowCount - 1 do
    if TRdxFixTable.Row(i).Kind = fkFreeAndNilHint then
      Assert.AreEqual('Use FreeAndNil(%s)', TRdxFixTable.RawCaption(i, 0),
        'die msgid bleibt englisch');
end;

procedure TTestRdxFixTable.FixFor_NoFindingOrRow;
var
  O : TRdxFixOutcome;
  F : TLeakFinding;
begin
  O := TRdxFixTable.FixFor(nil, nil, nil, nil);
  Assert.IsFalse(O.Enabled);
  Assert.AreEqual('kein Fund', O.Reason);
  Assert.AreEqual<Integer>(0, TRdxFixTable.AlternativeFixFor(nil, nil, nil, nil).Variant);
  F := TLeakFinding.New('t.pas', '', 1, 'x', fkConcatToFormat);
  try
    O := TRdxFixTable.FixFor(nil, nil, F, nil);
    Assert.IsFalse(O.Enabled);
    // de.po: 'keine einfache Hilfe fuer diese Regel' mit echtem Umlaut
    // (Charge G7) - die Quelle bleibt ASCII, also die Teile ohne ihn.
    Assert.IsTrue(Pos('keine einfache Hilfe f', O.Reason) = 1, O.Reason);
    Assert.IsTrue(Pos(' diese Regel', O.Reason) > 0, O.Reason);
    Assert.AreEqual<Integer>(0, TRdxFixTable.AlternativeFixFor(nil, nil, F, nil).Variant);
  finally
    F.Free;
  end;
end;

procedure TTestRdxFixTable.FixFor_TableHintAndChanges;
var
  SL : TStringList;
  F  : TLeakFinding;
  O  : TRdxFixOutcome;
begin
  // SCA082 plant nur auf den Zeilen (kein Dienst noetig): aktiv, und den
  // Hinweis setzt die Zeile der Tabelle.
  SL := TStringList.Create;
  F := nil;
  try
    // Die Meldung wie der Detektor sie schreibt (uSuperfluousSemicolon).
    F := TLeakFinding.New('t.pas', '', 4, 'Double semicolon at column 7 '
      + '(`;;`) - drop the extra one.', fkSuperfluousSemicolon);
    SL.Text := Join(['unit u;', 'implementation', 'procedure P;',
      'begin ; ;', 'end;', 'end.']);
    O := TRdxFixTable.FixFor(nil, SL, F, nil);
    Assert.IsTrue(O.Enabled, O.Reason);
    Assert.AreEqual('das zweite ";" war eine leere Anweisung', O.Hint);
    Assert.IsFalse(O.ChangesBehavior);
  finally
    F.Free;
    SL.Free;
  end;
  // SCA120 ist nach E2 gekennzeichnet - auch gesperrt (hier: keine Datei).
  F := TLeakFinding.New('t.pas', '', 1, 'Exception EFoo.Create(...) is '
    + 'constructed but never raised', fkMissingRaise);
  try
    O := TRdxFixTable.FixFor(nil, nil, F, nil);
    Assert.IsFalse(O.Enabled);
    // Der Grund kommt aus uRdxFixRunner.MapFix - seit E29 (Gruppe G6) die
    // uebersetzte Fassung; in de traegt sie einen echten Umlaut, darum der
    // Vergleich mit der Funktion statt mit dem Text.
    Assert.AreEqual(MsgNoFileOpen, O.Reason);
    Assert.IsTrue(O.ChangesBehavior, 'SCA120 aendert das Verhalten');
  finally
    F.Free;
  end;
  // SCA149: der Planer setzt Name und Kennzeichnung nach dem Rat der
  // Meldung - override im Menuetext und gekennzeichnet.
  // Die Meldung wie der Detektor sie schreibt (uMissingOverride).
  F := TLeakFinding.New('t.pas', '', 1, 'Method TD.X shadows virtual TB.X - '
    + 'missing `override` (W1010)', fkMissingOverride);
  try
    O := TRdxFixTable.FixFor(nil, nil, F, nil);
    Assert.AreEqual('override', O.Name);
    Assert.IsTrue(O.ChangesBehavior);
    Assert.AreEqual('"override;" an die Deklaration anf'#$00FC'gen ('#$00E4
      + 'ndert Verhalten)', TRdxFixTable.CaptionFor(fkMissingOverride, O));
  finally
    F.Free;
  end;
  // SCA075 bekam mit der Tabelle ERSTMALS einen festen Hinweis - wie
  // SCA074, SCA087 und SCA066 (bis Charge R8 leer; Gegen-Review R8,
  // Major 1): woertlich gepinnt. Der Planer plant nur auf den Zeilen.
  SL := TStringList.Create;
  F := nil;
  try
    F := TLeakFinding.New('t.pas', '', 3, '`class(TObject)` at column 10 - drop '
      + 'the parens (TObject is the implicit base class).',
      fkExplicitTObjectInheritance);
    SL.Text := Join(['unit u;', 'type', '  TFoo = class(TObject)', '  end;',
      'implementation', 'end.']);
    O := TRdxFixTable.FixFor(nil, SL, F, nil);
    Assert.IsTrue(O.Enabled, O.Reason);
    Assert.AreEqual('TObject ist ohnehin der Vorfahr - gleiche Bedeutung',
      O.Hint);
    Assert.IsFalse(O.ChangesBehavior);
  finally
    F.Free;
    SL.Free;
  end;
end;

procedure TTestRdxFixTable.ResultDefaultHint_NamesShownValue;
var
  i : Integer;
  R : TRdxFixRow;
begin
  // Der Menuetext nennt den Wert (ein Literal oder Default(T)); bis Charge
  // FB versprach der Hinweis '(wie Default(T))' - falsch, wenn ein Member
  // wie der erste Aufzaehlungswert heisst (Gegen-Review R5-06, Fall 2).
  // Seit Charge G7 die msgid in FIX_HINTS (RawHint) und ihre deutsche
  // Fassung aus de.po - dort mit echten Umlauten ('zufaellig',
  // 'spaetere'), also hier nur die Teile ohne.
  for i := 0 to TRdxFixTable.RowCount - 1 do
  begin
    R := TRdxFixTable.Row(i);
    if R.Kind <> fkRoutineResultUnassigned then
      Continue;
    Assert.IsFalse(R.HintByPlanner, 'SCA121: fester Hinweis der Zeile');
    Assert.AreEqual('Result now starts with the named value instead of a '
      + 'random one - later assignments still apply', TRdxFixTable.RawHint(i));
    Assert.IsTrue(Pos('Result beginnt jetzt mit dem genannten Wert statt',
      uRdxText._(TRdxFixTable.RawHint(i))) = 1,
      uRdxText._(TRdxFixTable.RawHint(i)));
    Assert.IsTrue(Pos('Zuweisungen gelten weiter',
      uRdxText._(TRdxFixTable.RawHint(i))) > 0,
      uRdxText._(TRdxFixTable.RawHint(i)));
    Exit;
  end;
  Assert.Fail('keine Zeile fuer SCA121');
end;

procedure TTestRdxFixTable.Table_PinsPlannerCaptionChangesAlt;
var
  i : Integer;
  E : TExpectedRow;
  R : TRdxFixRow;
  K : string;
begin
  Assert.AreEqual<Integer>(Length(EXPECTED), TRdxFixTable.RowCount,
    'Zeilenzahl - eine neue Zeile gehoert auch in EXPECTED');
  for i := 0 to High(EXPECTED) do
  begin
    E := EXPECTED[i];
    R := TRdxFixTable.Row(i);
    K := Format('Zeile %d (%s)', [i, KindName(E.Kind)]);
    Assert.AreEqual(KindName(E.Kind), KindName(R.Kind), K + ': Art');
    Assert.AreEqual(E.Plan, TRdxFixTable.PlannerName(i, 0), K + ': Planer');
    Assert.AreEqual(E.Caption, TRdxFixTable.RawCaption(i, 0),
      K + ': Menuetext (FIX_CAPTIONS)');
    Assert.AreEqual(E.Changes, R.Changes, K + ': Kennzeichnung (E2)');
    Assert.AreEqual(E.Alt, TRdxFixTable.PlannerName(i, 1),
      K + ': zweiter Planer');
    Assert.AreEqual(E.AltCaption, TRdxFixTable.RawCaption(i, 1),
      K + ': zweiter Menuetext (FIX_ALT_CAPTIONS)');
  end;
end;

// Jeder zweite Eintrag setzt Variant = 1 - auch ohne Zeilen (gesperrt):
// der Anbieter nimmt ihn nur mit Variant > 0 (uRdxProvider), sonst
// verschwaende er still aus dem Menue.
procedure TTestRdxFixTable.AltRows_SetVariantOne;
var
  i, n : Integer;
  R    : TRdxFixRow;
  F    : TLeakFinding;
  O    : TRdxFixOutcome;
begin
  n := 0;
  for i := 0 to TRdxFixTable.RowCount - 1 do
  begin
    R := TRdxFixTable.Row(i);
    if not Assigned(R.Alt) then
      Continue;
    Inc(n);
    F := TLeakFinding.New('t.pas', '', 1, 'x', R.Kind);
    try
      O := TRdxFixTable.AlternativeFixFor(nil, nil, F, nil);
      Assert.AreEqual<Integer>(1, O.Variant,
        KindName(F.Kind) + ': Variant des zweiten Eintrags');
    finally
      F.Free;
    end;
  end;
  Assert.AreEqual<Integer>(8, n,
    'SCA168, SCA020, SCA093, SCA046, SCA128, SCA059, SCA017, SCA127');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxFixTable);

end.
