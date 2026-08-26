unit uTestUninitVar;

// Tests fuer TUninitVarDetector (SCA166 fkUninitVar).
// Siehe Konzept_SCA166_UninitVar.md §12 fuer die Test-Strategie.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12, uTestFindingHelper;

type
  [TestFixture]
  TTestUninitVar = class
  public
    // ---- POSITIV (MUST flag fkUninitVar) ----
    [Test] procedure NeverWritten_OnlyRead_Flagged;
    [Test] procedure ConditionalWriteInIf_ReadAfter_Flagged;
    [Test] procedure ReadBeforeWrite_SequentialLines_Flagged;
    [Test] procedure CaseWriteWithoutElse_ReadAfter_Flagged;
    [Test] procedure TryExceptWriteOnly_ReadAfter_Flagged;
    [Test] procedure ClassInstanceUsedBeforeCreate_Flagged;
    // 2026-07-05 Gegenprobe: in-Unit-KLASSE wird NICHT breit gegated
    [Test] procedure InUnitClassReceiverMethod_StillFlagged;

    // ---- NEGATIV (MUST NOT flag) ----
    [Test] procedure CleanAssignThenRead_NoFinding;
    [Test] procedure UnderscorePrefix_NoFinding;
    [Test] procedure ManagedString_NoFinding;
    [Test] procedure ManagedDynamicArray_NoFinding;
    [Test] procedure ReadLnInitialisesVar_NoFinding;
    [Test] procedure ForLoopInitialisesVar_NoFinding;
    [Test] procedure ForInInlineVar_NoFinding;
    [Test] procedure TryGetGenericOutArg_NoFinding;
    [Test] procedure MultiLineVarDeclContinuation_NoFinding;
    [Test] procedure AbsoluteAlias_NoFinding;
    [Test] procedure ReceiverInitMethod_NoFinding;
    // 2026-07-05: in-Unit-Record-Receiver -> JEDER Methodenaufruf initialisiert
    [Test] procedure InUnitRecordReceiverMethod_AnyName_NoFinding;
    // 2026-07-05: cross-unit record via Allowlist-Verb 'prepare' (mORMot TMatch)
    [Test] procedure CrossUnitRecordPrepare_NoFinding;
    [Test] procedure FillCharInitialisesVar_NoFinding;
    [Test] procedure WriteBeforeRead_TryFinally_NoFinding;
    [Test] procedure DeclaredButNeverReferenced_NoFinding;
    [Test] procedure MultiLineVarDecl_CommaList_NoFinding;
    [Test] procedure VarDeclWithInit_NoFinding;

    // ---- EDGE CASES ----
    [Test] procedure AsmBlock_NoCrash;
    // Recharakterisierung after34 (2026-07-13): EINGEBETTETER asm-Block schreibt
    // Local per Register/Memory-Ref -> Methode ueberspringen (kein read-vor-write-FP)
    [Test] procedure EmbeddedAsmWritesLocal_NoFinding;
    [Test] procedure EmptyMethod_NoCrash;
    [Test] procedure MultipleVarsSomeClean_OnlyDirtyFlagged;
    // Real-World 2026-06-23: Array-Element-Write + @/SizeOf kein Read
    [Test] procedure ArrayElementWrite_NoFinding;
    [Test] procedure SizeOfAndAddressOf_NoFinding;
    // Root-Cause-Fix Parser nested routine (2026-06-24)
    [Test] procedure NestedRoutine_OuterVarWrittenBeforeNestedRead_NoFinding;
    // Parser nkNestedRange-Marker -> exakte nested-Range-Skips (2026-06-25)
    [Test] procedure NestedProcWithTry_OuterVarInLaterNested_NoFinding;
    // Real-World 2026-06-28: Auto-init-Record (TRttiContext) + escaped-field
    // Array-Element-Write (name[0].&Type := ...)
    [Test] procedure RttiContextRecord_NoFinding;
    [Test] procedure NonAutoInitRecord_StillFlagged;
    [Test] procedure EscapedFieldArrayElementWrite_NoFinding;
    // Real-World 2026-06-28: Read-Family-Fill (Stream.Read fuellt Buffer)
    [Test] procedure StreamReadFillsIndexedBuffer_NoFinding;
    [Test] procedure StreamReadFillsBareBuffer_NoFinding;
    [Test] procedure ReadBeforeStreamFill_StillFlagged;
    [Test] procedure StreamFillThenLaterArgWrite_NoFinding;
    // Real-World 2026-06-28: Nested-Closure unter Headless-Method-Pattern
    [Test] procedure OuterVarReadOnlyInNestedRoutine_NoFinding;
    [Test] procedure OuterVarUninitDespiteNestedRoutine_StillFlagged;
    // Real-World FP-Audit 2026-07-10 (SCA166 100% FP im Korpus):
    // (A) Typecast-Assignment-Target 'TFoo<T>(x) := y' schreibt x
    [Test] procedure TypecastAssignTargetGeneric_NoFinding;
    // (C) Receiver-Init auf assign-RHS: 'n := tmp.Init(...)' / '.From...(...)'
    [Test] procedure ReceiverInitInAssignRHS_NoFinding;
    [Test] procedure FromInitVerbReceiverInExpr_NoFinding;
    // (E) low()/high() im for-Header sind kein Werte-Read
    [Test] procedure LowHighInForHeader_NoFinding;
    // Gegenprobe: echter uninitialisierter Read bleibt ein Fund (kein Over-Suppress)
    [Test] procedure ReadBeforeTypecastAssign_StillFlagged;
    // Real-World FP-Audit 2026-07-10, clean-Teilklassen:
    // (Fund 10) Member-Access-LHS 'X.field := ...' ist partieller Write von X
    [Test] procedure MemberAccessAssignAfterLabel_NoFinding;
    [Test] procedure MemberReadBeforeWrite_StillFlagged;
    // (Funde 6/8) {$IFDEF}-const-vs-var: const im inaktiven Zweig ist kein Read
    [Test] procedure IfdefConstVsVarBranch_NoFinding;
    [Test] procedure EqualityConditionNotConstDecl_StillFlagged;
    // Welle 3 (dritter nkConditionalRange-Opt-in): Read im {$IFDEF}-Zweig,
    // Write nach dem {$ENDIF} -> verschiedene bedingte Zweige, Phantom-Read.
    [Test] procedure ReadInIfdefBranchWriteAfter_NoFinding;
    // Gegenprobe: Direktive im Method-Body aber NICHT zwischen Read/Write
    // -> echter Read-vor-Write bleibt ein Fund (Guard darf nicht zu breit sein).
    [Test] procedure ReadBeforeWriteDirectiveElsewhere_StillFlagged;
    // --- Real-World FP-Audit 2026-07-12: var-param-out-write (Kat. A/C/D) ---
    [Test] procedure ReceiverTypecastCallOutArg_NoFinding;        // Kat. A '.'
    [Test] procedure ReceiverDerefTypecastCallOutArg_NoFinding;   // Kat. A '^'
    [Test] procedure CaseSelectorCallOutArg_NoFinding;            // Kat. C
    [Test] procedure CallArgWithStringLiteralParen_NoFinding;     // Kat. D
    // FN-Gegenproben (muessen weiter feuern):
    [Test] procedure CastOperandOnlyRead_StillFlagged;            // FN-Edge Kat. A
    [Test] procedure CaseSelectorPlainVarNoCall_StillFlagged;     // Over-Suppress-Guard Kat. C
    // Verify-Nachschaerfung 2026-07-12 (Drop-Stichprobe: chained-call + managed):
    [Test] procedure ChainedCallMultiArgOutArg_NoFinding;         // Komma-Heuristik
    [Test] procedure ManagedInterfaceVarReceiver_NoFinding;       // IsManagedType-Interface
    // --- Recharakterisierung after30 (2026-07-12): 4 detector-lokale FP-Klassen ---
    [Test] procedure HexLiteralSingleLetterVar_NoFinding;         // '$F' ist kein Read von var F
    [Test] procedure HexLiteralNotMaskingRealRead_StillFlagged;   // FN-Gegenprobe zu '$'-Guard
    [Test] procedure LengthOnArrayNotValueRead_NoFinding;         // Length(arr) ist Groessen-Query
    [Test] procedure LengthGuardArrayElementRead_StillFlagged;    // FN-Gegenprobe zu Length-INTR
    [Test] procedure ManagedAliasTbtString_NoFinding;             // tbtString = managed AnsiString
    [Test] procedure IdentToIntVarArgWrite_NoFinding;             // IdentToInt fuellt var-Arg
    // #6 Inkr.4: CFG-Postfilter (Zyklus-Regel + ReachingDefs)
    [Test] procedure CfgLoopAccumulatorGuarded_NoFinding;         // Back-Edge-Drop (Regel B)
    [Test] procedure CfgStraightLineReadBeforeWrite_StillFlagged; // Same-Block = plausibler TP
    [Test] procedure CfgSiblingArmsWithoutLoop_StillFlagged;      // bewusst v1-offen
    // KEIN goto-Guard-Test: Methoden mit label/goto erzeugen empirisch GAR
    // KEINE fcMedium-Funde (label-Sektion stoert die lexikalische Pipeline,
    // CLI-verifiziert 2026-07-24 an 2 Formen) - der BodyHasGotoOrLabel-Guard
    // im Filter ist reine Defense-in-Depth und end-to-end nicht testbar.
    // Inkr.4b (Drop-Sampling-Fixes: 37 Stellen, 1 MASKED_BUG)
    [Test] procedure CfgUnguardedLoopConditionRead_StillFlagged;  // bson-Muster: Regel B braucht Guard
    [Test] procedure DeclInitializedLocal_NoFinding;              // FPC 'V: Integer = 1' = Write
    [Test] procedure DeclCommentEquals_StillFlagged;              // '=' im Kommentar != Initializer
    // Inkrement A3 (Triage 2026-07-24): Exit-Arg-Calls + absolute-Alias
    [Test] procedure ExitArgOutParamCall_NoFinding;
    [Test] procedure ExitArgPlainVar_StillFlagged;
    [Test] procedure AbsoluteAliasWrite_NoFinding;
    [Test] procedure AddressOfFill_NoFinding;
    // Inkrement B (Triage 2026-07-25): Inline-const-RHS, Allowlist-Wrapper, Decl-Init-fcHigh
    [Test] procedure ConstInlineCallVarArg_NoFinding;
    [Test] procedure ConstInlineReadOnlyCall_StillFlagged;
    [Test] procedure AllowlistWrapperInnerCall_NoFinding;
    [Test] procedure AllowlistBareArg_StillFlagged;
    [Test] procedure FpcDeclInitializer_NoHighFinding;
    // Managed-Alias 2026-07-24: Hersteller-Praefix-Interfaces (IwbX)
    [Test] procedure VendorPrefixInterfaceLocal_NoFinding;
    [Test] procedure VendorPrefixButClass_StillFlagged;
    // Inkrement B2 (Triage 2026-07-25): 7-Hook-Runde (Hook 5 Enum-Helper-
    // Receiver bewusst uebersprungen - kollidiert mit der dokumentierten
    // tkiEnum-Ausnahme in ApplyReceiverInit).
    // Hook 1: Call-LHS-Assign 'Fn(Buf, X)^ := ...' registriert Arg-Writes
    [Test] procedure CallLhsAssignMultiArg_NoFinding;
    [Test] procedure CallLhsAssignUnrelatedVar_StillFlagged;
    // Hook 2: Intrinsic-Guard (SizeOf/Length/...) whitespace-tolerant
    [Test] procedure SizeOfWithSpaces_NoFinding;
    [Test] procedure WriteLnWithSpaceParen_StillFlagged;
    // Hook 3: lokale resourcestring-/const-Eintraege als Pseudo-Vars
    [Test] procedure LocalResourceStringEntry_NoFinding;
    [Test] procedure PlainVarDeclOwnLine_StillFlagged;
    // Hook 4: param-misparse (proc-Typ-Parameter / Signatur-Schlusszeilen)
    [Test] procedure ProcTypeMidParamLeak_NoFinding;
    [Test] procedure SignatureTailTypeLeak_NoFinding;
    [Test] procedure ProcPointerVarReadBeforeWrite_StillFlagged;
    // Hook 6: 'with <var> do' = konservativer Basis-Write (Klassen-Gate)
    [Test] procedure WithRecordBasis_NoFinding;
    [Test] procedure WithClassBasis_StillFlagged;
    // Hook 7: Decay-RHS auf psz/lp-Zielfeld (PFLICHT-Gate)
    [Test] procedure DecayRhsPszField_NoFinding;
    [Test] procedure DecayRhsPlainField_StillFlagged;
    // Zensus-Triage 2026-07-25: Hook 1a/1b + Kleinserie H2/H3/H4/H5.
    // Hook 1a: PARENLOSER Record-Init im Expression-Kontext
    // (Zensus mormot.lib.sspi:2211 'sz := tmp.Init shr 1')
    [Test] procedure ParenlessReceiverInitRHS_NoFinding;
    [Test] procedure ParenlessNonInitMemberRead_StillFlagged;
    // Hook 1b: Same-File-Signatur-Aufloesung fuer var/out-Args
    [Test] procedure SameFileVarOutArgCall_NoFinding;
    [Test] procedure ReadBeforeVarOutArgCall_StillFlagged;
    // H2: Inline-const-Ident SELBST ist nie uninit
    [Test] procedure InlineConstSelfIdent_NoFinding;
    [Test] procedure ConstWordInComment_StillFlagged;
    // H3: FPC-'{%H-}'-Suppression adjazent an der Decl
    [Test] procedure FpcHideMarkerAdjacent_NoFinding;
    [Test] procedure HMarkerOtherVar_StillFlagged;
    // H4: '@X := GetProcAddress(...)' (Befund: bereits via A3b-@-Scan
    // abgedeckt - Tests sichern die Zusage ab, kein neuer Code)
    [Test] procedure GetProcAddressAtLhs_NoFinding;
    [Test] procedure ReadBeforeAtLhsAssign_StillFlagged;
    // H5: Symptom-Gate keyword-misparse (Var-Name == in-File-Typname)
    [Test] procedure TypeNamePhantomLocal_NoFinding;
    [Test] procedure NameEqualsConstNotType_StillFlagged;
    // Welle 1 (2026-07-25): managed-autoinit + tkiClass-Gate im parenlosen
    // 1a-Zweig (73er-Zensus, Rest 67).
    // Hook 1: strukturelles dynamisches Array 'array of T' ist managed
    [Test] procedure DynArrayBareLocal_NoFinding;
    [Test] procedure DynArrayHomonymNamedType_StillFlagged;
    // Hook 3: '.Initialized'-Property-Read auf Klassen-Receiver ist KEIN
    // Init-Write (tkiClass-Gate, Vorlage with-Scan-Gate)
    [Test] procedure ParenlessInitVerbClassReceiver_StillFlagged;
    [Test] procedure ParenlessInitRecordReceiver_NoFinding;

    // ---- Real-World-Audit 30% (2026-07-31): SCA166 war 94% FP ----
    // FP-Klasse 1: with-Statement-Scope-Poisoning
    [Test] procedure WithBlockFieldNameCollision_NoFinding;
    [Test] procedure WithBlockReadAfterBlock_StillFlagged;
    // FP-Klasse 2: unbekannte var/out-Param-Writer (MouseToCell & Co.)
    [Test] procedure UnknownVarOutArgCall_NoFinding;
    [Test] procedure IfParenBareVarNotCallArg_StillFlagged;
    // FP-Klasse 3: anonyme Methoden / Closure-Parameter
    [Test] procedure AnonMethodBodyRead_NoFinding;
    [Test] procedure AnonMethodParamShadowsLocal_NoFinding;
    [Test] procedure ReadOutsideAnonMethod_StillFlagged;
    // FP-Klasse 4: cross-unit managed Typen
    [Test] procedure DynArrayAliasType_NoFinding;
    [Test] procedure MarshallerRecord_NoFinding;
    [Test] procedure NonDynArrayAliasType_StillFlagged;
    [Test] procedure VendorInterfaceWithInterfaceParent_NoFinding;
    [Test] procedure VendorPrefixClassWithClassParent_StillFlagged;
    // FP-Klasse 5: Nicht-Read-Kontexte (Record-Ctor, LHS-Punktpfad, Decay)
    [Test] procedure RecordCtorOnInstance_NoFinding;
    [Test] procedure ClassCtorOnInstance_StillFlagged;
    [Test] procedure DirectiveInMemberPathAssign_NoFinding;
    [Test] procedure MemberPathPlainSpaceRead_StillFlagged;
    [Test] procedure MenuItemInfoDecayField_NoFinding;
    // FP-Klasse 6: inline-const/inline-var mit Initialisierer
    [Test] procedure InlineDeclInitLaterHomonym_NoFinding;
    [Test] procedure InlineDeclInitOtherName_StillFlagged;
    // FP-Klasse 7 (Symptom-Gate): Typname als Variablenname = Parser-Phantom
    [Test] procedure LocalNamedLikeManagedType_NoFinding;
    [Test] procedure NameStartsWithTypeName_StillFlagged;

    // ---- Pre-Build-Review 2026-07-31: Korrekturen an den drei Gates ----
    // Fund 'with-Poisoning': Blockende trotz Zeilenkommentar korrekt
    [Test] procedure WithBlockTrailingCommentBoundary_StillFlagged;
    // Fund 'Anon-Range': Kopfzeile gehoert NICHT zum Closure-Rumpf
    [Test] procedure AnonAssignHeaderLineRead_StillFlagged;
    // Fund 'Monotonie': Arg-Write nach dem Read darf den Anker nicht drehen
    [Test] procedure UnknownArgWriteAfterRead_KeepsDeclAnchor;

    // ---- Schluss-Verifikation 2026-07-31: Monotonie der NEUEN PhaseB-Hooks ----
    // Blocker 1: Ctor-Aufruf auf der Instanz NACH einem Read
    [Test] procedure CtorOnInstanceAfterRead_KeepsDeclAnchor;
    // Blocker 2: Decay-Adressnahme auf 'dwTypeData' NACH einem Read
    [Test] procedure DecayFieldAfterRead_KeepsDeclAnchor;
    // Kundenkorpus-FP-Runde K5 (2026-08-20): Feld-Labels typisierter
    // Konstanten sind keine Lesestellen.
    [Test] procedure RecordConstLabel_SameNameAsLocal_NoFinding;
    [Test] procedure RealReadBeforeWrite_StillReported;

    // ---- Voll-Audit 2026-08-15 / rw8-Restfunde (2026-08-26) ----------------
    // Typname-Bug: Kontextwort als Variablenname ('read: integer;',
    // 'Result: PPyObject;' in einer Prozedur) liess den Parser den TYPNAMEN
    // als typlose Variable fuehren - Fix in uParser2 (Var-Section).
    [Test] procedure KeywordNamedLocal_Assigned_NoPhantomTypename;
    [Test] procedure KeywordNamedLocal_ResultInProcedure_NoPhantom;
    // Gegenprobe: der Parser-Fix macht die echte Variable SICHTBAR -
    // ist sie wirklich uninitialisiert, kommt jetzt der korrekte Fund.
    [Test] procedure KeywordNamedLocal_TrulyUninit_ReportedUnderRealName;
    // out-Merge-Bug: die kuerzere Overload-Signatur loeschte das out-Flag
    // der laengeren (JclSysUtils IntToStr) - Merge jetzt auf Max-Laenge.
    [Test] procedure OutParamOverload_ShorterTwin_NoFinding;
  end;

implementation

function CountKind(L: TObjectList<TLeakFinding>; K: TFindingKind): Integer;
var
  F : TLeakFinding;
begin
  Result := 0;
  for F in L do
    if F.Kind = K then Inc(Result);
end;

procedure RunOn(const Src: string; out Findings: TObjectList<TLeakFinding>);
begin
  Findings := TFindingHelper.FindingsOfFile(Src);
end;

// ============================================================
// POSITIV
// ============================================================

procedure TTestUninitVar.NeverWritten_OnlyRead_Flagged;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var n: Integer;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(n);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.IsTrue(CountKind(L, fkUninitVar) >= 1,
      'Variable nur gelesen, nie geschrieben - muss SCA166 ausloesen');
  finally L.Free; end;
end;

procedure TTestUninitVar.ConditionalWriteInIf_ReadAfter_Flagged;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(c: Boolean);'#13#10 +
    'var n: Integer;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(n);'#13#10 +
    '  if c then n := 1;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.IsTrue(CountKind(L, fkUninitVar) >= 1,
      'Read VOR conditional-Write - muss flaggen');
  finally L.Free; end;
end;

procedure TTestUninitVar.ReadBeforeWrite_SequentialLines_Flagged;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var n: Integer;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(n);'#13#10 +
    '  n := 42;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.IsTrue(CountKind(L, fkUninitVar) >= 1,
      'Read VOR Write - klassischer UninitVar');
  finally L.Free; end;
end;

procedure TTestUninitVar.CaseWriteWithoutElse_ReadAfter_Flagged;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(k: Integer);'#13#10 +
    'var n: Integer;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(n);'#13#10 +
    '  case k of'#13#10 +
    '    1: n := 10;'#13#10 +
    '    2: n := 20;'#13#10 +
    '  end;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.IsTrue(CountKind(L, fkUninitVar) >= 1,
      'Read vor case-Write ohne else - muss flaggen');
  finally L.Free; end;
end;

procedure TTestUninitVar.TryExceptWriteOnly_ReadAfter_Flagged;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var n: Integer;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(n);'#13#10 +
    '  try'#13#10 +
    '    DoSomething();'#13#10 +
    '  except'#13#10 +
    '    n := 0;'#13#10 +
    '  end;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.IsTrue(CountKind(L, fkUninitVar) >= 1,
      'Read vor try-except-Write - muss flaggen');
  finally L.Free; end;
end;

procedure TTestUninitVar.ClassInstanceUsedBeforeCreate_Flagged;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'uses System.Classes;'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var L: TStringList;'#13#10 +
    'begin'#13#10 +
    '  L.Add(''x'');'#13#10 +
    '  L := TStringList.Create;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  Findings : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, Findings);
  try
    Assert.IsTrue(CountKind(Findings, fkUninitVar) >= 1,
      'Klassen-Instanz gelesen vor Create - muss flaggen');
  finally Findings.Free; end;
end;

// ============================================================
// NEGATIV
// ============================================================

procedure TTestUninitVar.CleanAssignThenRead_NoFinding;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var n: Integer;'#13#10 +
    'begin'#13#10 +
    '  n := 0;'#13#10 +
    '  WriteLn(n);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'Sauber initialisiert - kein SCA166');
  finally L.Free; end;
end;

procedure TTestUninitVar.UnderscorePrefix_NoFinding;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var _temp: Integer;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(_temp);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      '_-Prefix Konvention - kein Flag');
  finally L.Free; end;
end;

procedure TTestUninitVar.ManagedString_NoFinding;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var s: string;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(s);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'Managed type (string) - Pascal initialisiert - kein Flag');
  finally L.Free; end;
end;

procedure TTestUninitVar.ManagedDynamicArray_NoFinding;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var arr: TArray<Integer>;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(Length(arr));'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'TArray<T> ist managed - kein Flag');
  finally L.Free; end;
end;

procedure TTestUninitVar.ReadLnInitialisesVar_NoFinding;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var n: Integer;'#13#10 +
    'begin'#13#10 +
    '  ReadLn(n);'#13#10 +
    '  WriteLn(n);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'ReadLn ist Write (Allowlist) - kein Flag');
  finally L.Free; end;
end;

procedure TTestUninitVar.ForLoopInitialisesVar_NoFinding;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var i: Integer;'#13#10 +
    'begin'#13#10 +
    '  for i := 0 to 10 do'#13#10 +
    '    WriteLn(i);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'for-Loop initialisiert Index-Var - kein Flag');
  finally L.Free; end;
end;

procedure TTestUninitVar.ForInInlineVar_NoFinding;
// Regression LogStats_plugin MainForm.pas:352 - 'for var Pair in ADict do'
// darf NIE UninitVar werfen. Die LoopVar wird implizit vom Enumerator
// vor jedem Body-Durchlauf zugewiesen.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'uses System.Generics.Collections;'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var D: TDictionary<string,Integer>;'#13#10 +
    'begin'#13#10 +
    '  D := TDictionary<string,Integer>.Create;'#13#10 +
    '  for var Pair in D do'#13#10 +
    '    WriteLn(Pair.Key);'#13#10 +
    '  D.Free;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'for-in mit inline-var darf kein UninitVar werfen');
  finally L.Free; end;
end;

procedure TTestUninitVar.TryGetGenericOutArg_NoFinding;
// Regression DUnitX.TestFramework.pas:851 - das Pattern
//   if rType.TryGetAttributeOfType<TestFixtureAttribute>(attrib) then
//     sName := attrib.Name;
// darf KEIN UninitVar werfen. ParseCallsInExpr muss den Generic-Type-
// Parameter <T> zwischen Funktionsname und '(' ueberspringen, damit
// 'attrib' als Call-Arg erkannt und pessimistic als Write registriert
// wird.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var attrib: TObject; sName: string;'#13#10 +
    'begin'#13#10 +
    '  if TryGet<TObject>(attrib) then'#13#10 +
    '    sName := attrib.ClassName;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'TryGet<T>(out arg) im if-Condition darf kein UninitVar werfen');
  finally L.Free; end;
end;

procedure TTestUninitVar.MultiLineVarDeclContinuation_NoFinding;
// Regression TCodeReader RGBLuminanceSource.pas (20 FPs in einer Datei):
// Multi-line var-Decl mit Ein-Ident-pro-Zeile - Continuation-Zeilen
// (nur 'name,' am Zeilenende) duerfen NICHT als Reads interpretiert
// werden. IsVarDeclLine erkennt nur die finale Zeile mit ':type;'.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var'#13#10 +
    '  byte1,'#13#10 +
    '  byte2,'#13#10 +
    '  b5, g5, r5,'#13#10 +
    '  r8, g8, b8 : Byte;'#13#10 +
    'begin'#13#10 +
    '  byte1 := 0;'#13#10 +
    '  byte2 := 0;'#13#10 +
    '  b5 := byte1; g5 := byte1; r5 := byte1;'#13#10 +
    '  r8 := r5; g8 := g5; b8 := b5;'#13#10 +
    '  WriteLn(r8 + g8 + b8);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'multi-line var-decl continuation darf kein UninitVar werfen');
  finally L.Free; end;
end;

procedure TTestUninitVar.AbsoluteAlias_NoFinding;
// Regression Img32.Extra BlendAverage/AlphaAverage (~30 FPs):
// 'c1: TARGB absolute color1;' macht c1 zum Alias der bestehenden
// Variable - eigene Storage gibt es nicht, also auch keine Init-Pflicht.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'function Foo(color: Cardinal): Cardinal;'#13#10 +
    'var c: Cardinal absolute color;'#13#10 +
    'begin'#13#10 +
    '  Result := c shr 8;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'absolute-Alias darf nicht als UninitVar gewertet werden');
  finally L.Free; end;
end;

procedure TTestUninitVar.ReceiverInitMethod_NoFinding;
// Regression mORMot TDocVariantData.InitJson - 'doc.Init<...>(args)' am
// Receiver behandelt mORMot/Spring als Stack-Init: KEINE Init-Pflicht
// vor dem Aufruf.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(const data: string);'#13#10 +
    'var doc: TDocVariantData;'#13#10 +
    'begin'#13#10 +
    '  doc.InitJson(data);'#13#10 +
    '  WriteLn(doc.Count);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'doc.InitJson(...) als erstes Statement = Init des Receivers');
  finally L.Free; end;
end;

procedure TTestUninitVar.InUnitRecordReceiverMethod_AnyName_NoFinding;
// Der Typ TMatch ist in DIESER Unit als record deklariert (nkRecord). Ein
// Methodenaufruf am Record-Receiver initialisiert dessen Felder (Self ist
// var) - das gilt fuer JEDEN Methodennamen, nicht nur die Init-Verb-
// Allowlist. 'Configure' steht bewusst NICHT auf der Allowlist; allein der
// Record-Typ-Check traegt. (Analog mORMot record-with-methods.)
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TMatch = record'#13#10 +
    '    FData: Integer;'#13#10 +
    '    procedure Configure(v: Integer);'#13#10 +
    '    function Run: Boolean;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure TMatch.Configure(v: Integer); begin FData := v; end;'#13#10 +
    'function TMatch.Run: Boolean; begin Result := FData > 0; end;'#13#10 +
    'function IsIt: Boolean;'#13#10 +
    'var m: TMatch;'#13#10 +
    'begin'#13#10 +
    '  m.Configure(42);'#13#10 +
    '  Result := m.Run;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'in-Unit-Record: Methodenaufruf initialisiert den Receiver (jeder Name)');
  finally L.Free; end;
end;

procedure TTestUninitVar.CrossUnitRecordPrepare_NoFinding;
// Exakter Real-World-FP: mORMot mormot.core.search.IsMatch. TMatch ist in
// einer ANDEREN Unit deklariert (hier nicht sichtbar) -> faellt auf die
// Init-Verb-Allowlist zurueck; 'prepare' ist jetzt drin. match.Prepare(...)
// initialisiert den Record, match.Match(...) liest danach.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'function IsMatch(const Pattern, Text: RawUtf8; ci: boolean): boolean;'#13#10 +
    'var match: TMatch;'#13#10 +
    'begin'#13#10 +
    '  match.Prepare(pointer(Pattern), length(Pattern), ci, false);'#13#10 +
    '  result := match.Match(Text);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'match.Prepare(...) initialisiert den Record - kein UninitVar');
  finally L.Free; end;
end;

procedure TTestUninitVar.InUnitClassReceiverMethod_StillFlagged;
// Gegenprobe zum Record-Gate: TFoo ist in dieser Unit eine KLASSE (nkClass,
// NICHT nkRecord). Der Record-Broad-Gate darf hier NICHT greifen - 'f.Go'
// auf einer nie zugewiesenen Klassen-Referenz bleibt ein echter Fund
// (Read vor Write). 'Go' ist zudem kein Allowlist-Verb.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TFoo = class'#13#10 +
    '    procedure Go;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure TFoo.Go; begin end;'#13#10 +
    'procedure P;'#13#10 +
    'var f: TFoo;'#13#10 +
    'begin'#13#10 +
    '  f.Go;'#13#10 +
    '  f := TFoo.Create;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.IsTrue(CountKind(L, fkUninitVar) >= 1,
      'in-Unit-Klasse: Methodenaufruf auf uninit. Referenz bleibt ein Fund');
  finally L.Free; end;
end;

procedure TTestUninitVar.FillCharInitialisesVar_NoFinding;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'type TRec = record A: Integer; end;'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var r: TRec;'#13#10 +
    'begin'#13#10 +
    '  FillChar(r, SizeOf(r), 0);'#13#10 +
    '  WriteLn(r.A);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'FillChar ist Write (Allowlist) - kein Flag');
  finally L.Free; end;
end;

procedure TTestUninitVar.WriteBeforeRead_TryFinally_NoFinding;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'uses System.Classes;'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var L: TStringList;'#13#10 +
    'begin'#13#10 +
    '  L := TStringList.Create;'#13#10 +
    '  try'#13#10 +
    '    L.Add(''x'');'#13#10 +
    '  finally'#13#10 +
    '    L.Free;'#13#10 +
    '  end;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  Findings : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, Findings);
  try
    Assert.AreEqual<Integer>(0, CountKind(Findings, fkUninitVar),
      'Write VOR Read im try-finally - kein Flag');
  finally Findings.Free; end;
end;

procedure TTestUninitVar.DeclaredButNeverReferenced_NoFinding;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var n: Integer;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(''hi'');'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    // Variable n wird nirgends referenziert - das ist UnusedLocal-Domain
    // (SCA019), KEIN UninitVar. Wir muessen sicherstellen dass kein
    // SCA166 emittiert wird.
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'Nicht referenziert - faellt unter UnusedLocal, nicht UninitVar');
  finally L.Free; end;
end;

procedure TTestUninitVar.MultiLineVarDecl_CommaList_NoFinding;
// FP-Fix doublecmd-Audit (EUCSampler.pas:86, nsMBCSMultiProber.pas:277):
// Multi-line var-decl mit Komma-Auflistung listet die Variablen auf
// mehreren Zeilen auf. Der Parser meldet nur EINE DeclLine pro Var.
// Die Zeilen wo die anderen Idents stehen dürfen NICHT als Read
// interpretiert werden.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'function F: Double;'#13#10 +
    'var'#13#10 +
    '   s,'#13#10 +              // Zeile 6: erster Decl-Teil
    '   sum: Double;'#13#10 +   // Zeile 7: zweiter Decl-Teil + Typ
    '   i: Integer;'#13#10 +    // Zeile 8
    'begin'#13#10 +
    '   sum := 0.0;'#13#10 +     // Zeile 10: erster Write
    '   for i := 0 to 10 do'#13#10 +
    '     sum := sum + i;'#13#10 +
    '   Result := sum;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'Multi-line var-decl darf NICHT als Read interpretiert werden');
  finally L.Free; end;
end;

procedure TTestUninitVar.VarDeclWithInit_NoFinding;
// Var-Decl mit Init-Value (`: Type = Value;`) wird als FirstWriteLine
// behandelt - kein UninitVar-Befund.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'function F: Integer;'#13#10 +
    'var n: Integer;'#13#10 +
    'begin'#13#10 +
    '  n := 42;'#13#10 +
    '  Result := n;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'Var-Decl + Assignment + Read ist sauberes Pattern, kein UninitVar');
  finally L.Free; end;
end;

// ============================================================
// EDGE CASES
// ============================================================

procedure TTestUninitVar.AsmBlock_NoCrash;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var n: Integer;'#13#10 +
    'asm'#13#10 +
    '  mov eax, n'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  // Detector soll asm-Block ueberspringen, nicht crashen.
  RunOn(SRC, L);
  try
    Assert.Pass('asm-Block - kein Crash');
  finally L.Free; end;
end;

procedure TTestUninitVar.EmbeddedAsmWritesLocal_NoFinding;
// EMBEDDED asm (begin-Body mit asm-Block, KEINE ;asm-Marker-Methode): 'v' wird im
// asm-Block per 'mov v, eax' geschrieben (fuer den Parser unsichtbar) und danach
// gelesen -> ohne asm-Body-Skip ein read-vor-write-FP. MethodHasAsmBlock findet
// die 'asm'-Zeile im Method-Range -> Methode uebersprungen -> kein Fund.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var v: Integer;'#13#10 +
    'begin'#13#10 +
    '  asm'#13#10 +
    '    mov v, eax'#13#10 +
    '  end;'#13#10 +
    '  WriteLn(v);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(L, fkUninitVar),
    'eingebetteter asm-Block schreibt v -> Methode uebersprungen -> kein uninit-FP');
  finally L.Free; end;
end;

procedure TTestUninitVar.EmptyMethod_NoCrash;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'begin'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'Leere Methode ohne LocalVars - kein Flag');
  finally L.Free; end;
end;

procedure TTestUninitVar.MultipleVarsSomeClean_OnlyDirtyFlagged;
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var'#13#10 +
    '  a: Integer;'#13#10 +
    '  b: Integer;'#13#10 +
    'begin'#13#10 +
    '  a := 1;'#13#10 +
    '  WriteLn(a);'#13#10 +
    '  WriteLn(b);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    // a ist sauber, b ist UninitVar - es soll genau 1 Finding sein.
    Assert.AreEqual<Integer>(1, CountKind(L, fkUninitVar),
      'Nur b sollte geflaggt werden, a ist sauber');
  finally L.Free; end;
end;

procedure TTestUninitVar.ArrayElementWrite_NoFinding;
// FP-Fix (Real-World 2026-06-23): `LActions[0] := ...` ist ein Element-Write
// (Initialisierung), kein Read-Before-Write der Array-Variable.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var LActions: array[0..1] of Integer;'#13#10 +
    'begin'#13#10 +
    '  LActions[0] := 1;'#13#10 +
    '  LActions[1] := 2;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
    'Array-Element-Write ist Initialisierung, kein Uninit-Read');
  finally L.Free; end;
end;

procedure TTestUninitVar.SizeOfAndAddressOf_NoFinding;
// FP-Fix (Real-World 2026-06-23): `SizeOf(Buf)` und `@Buf` lesen NICHT den
// Wert - oft WinAPI-Out-Param der den Buffer erst fuellt.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var Buf: array[0..15] of Byte; n: Integer;'#13#10 +
    'begin'#13#10 +
    '  n := SizeOf(Buf);'#13#10 +
    '  FillStuff(@Buf, n);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
    'SizeOf(var) / @var sind kein Werte-Read');
  finally L.Free; end;
end;

procedure TTestUninitVar.NestedRoutine_OuterVarWrittenBeforeNestedRead_NoFinding;
// Root-Cause-Fix Parser nested routine: aeussere var `n` wird im OUTER-Body
// geschrieben (`n := 5`) und nur in der nested routine gelesen. Frueher fraß
// ParseLocalVarSection die nested routine als Pseudo-Var und ParseMethodImpl
// nahm den NESTED-Body (`WriteLn(n)`) als Outer-Body -> der echte Outer-Write
// ging verloren -> `n` schien nur gelesen, nie geschrieben -> FP. Jetzt bleibt
// der Outer-Body erhalten, der Write steht vor dem Read.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var n: Integer;'#13#10 +
    '  procedure Helper;'#13#10 +
    '  begin'#13#10 +
    '    WriteLn(n);'#13#10 +
    '  end;'#13#10 +
    'begin'#13#10 +
    '  n := 5;'#13#10 +
    '  Helper;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
    'Outer-Var im Outer-Body geschrieben - nested routine darf Body nicht verschlucken');
  finally L.Free; end;
end;

procedure TTestUninitVar.NestedProcWithTry_OuterVarInLaterNested_NoFinding;
// nkNestedRange-Marker (Parser): eine nested proc MIT try/finally vor einer
// zweiten nested proc, die eine Outer-Var liest (Outer-Var erst im Outer-Body
// zugewiesen). Die line-basierte begin/end-Heuristik balanciert try/case-end
// nicht und konnte die nested-Range abschneiden -> Read galt als Outer-Read ->
// SCA166-FP. Der Parser haengt jetzt EXAKTE nkNestedRange-Marker an die Methode;
// SCA166 skippt damit Reads in nested procs zuverlaessig.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure Outer;'#13#10 +
    'var Data: TStringList;'#13#10 +
    '  procedure First;'#13#10 +
    '  begin'#13#10 +
    '    try'#13#10 +
    '      DoA;'#13#10 +
    '    finally'#13#10 +
    '      DoB;'#13#10 +
    '    end;'#13#10 +
    '  end;'#13#10 +
    '  procedure Second;'#13#10 +
    '  begin'#13#10 +
    '    Data.Add(''x'');'#13#10 +
    '  end;'#13#10 +
    'begin'#13#10 +
    '  Data := TStringList.Create;'#13#10 +
    '  First;'#13#10 +
    '  Second;'#13#10 +
    '  Data.Free;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
    'Read einer Outer-Var in nested proc (nach try-proc) ist kein uninit');
  finally L.Free; end;
end;

procedure TTestUninitVar.RttiContextRecord_NoFinding;
// FP-Fix (Real-World 2026-06-28, Alcinoe.FMX.Controls:1852 / CEF4):
//   var LContext: TRttiContext;
//   LType := LContext.GetType(...);
// TRttiContext ist ein Auto-init-Record (lazy Self-Init / Management-
// Operatoren). Bare-Verwendung ohne explizite Zuweisung ist das Standard-
// RTTI-Idiom und NIE ein uninitialisierter Read.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'uses System.Rtti;'#13#10 +
    'implementation'#13#10 +
    'procedure P(Obj: TObject);'#13#10 +
    'var LContext: TRttiContext;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(LContext.GetType(Obj.ClassType).Name);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
    'TRttiContext ist Auto-init-Record - bare-Verwendung kein UninitVar');
  finally L.Free; end;
end;

procedure TTestUninitVar.NonAutoInitRecord_StillFlagged;
// TP-Gegenkontrolle: die NOINIT_RECORD_TYPES-Denylist ist eng (nur
// TRttiContext). Ein gewoehnlicher Record der vor jedem Write gelesen
// wird MUSS weiter feuern - sonst waere die Denylist zu breit.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'uses System.Types;'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var pt: TPoint;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(pt.X);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.IsTrue(CountKind(L, fkUninitVar) >= 1,
    'gewoehnlicher Record (TPoint) vor Write gelesen - muss weiter flaggen');
  finally L.Free; end;
end;

procedure TTestUninitVar.EscapedFieldArrayElementWrite_NoFinding;
// FP-Fix (Real-World 2026-06-28, Alcinoe.ServiceUtils:107):
//   var LActions: array[0..2] of SC_ACTION;
//   LActions[0].&Type := SC_ACTION_RESTART;
// Das escaped-keyword-Feld '&Type' brach den Qualifier-Walk im Array-
// Element-Write-Skip ab -> der Write wurde als Read fehlgedeutet. Mit '&'
// im Charset wird '[0].&Type :=' korrekt als Element-Write erkannt.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'type TAct = record &Type: Integer; Delay: Integer; end;'#13#10 +
    'procedure P;'#13#10 +
    'var LActions: array[0..1] of TAct;'#13#10 +
    'begin'#13#10 +
    '  LActions[0].&Type := 1;'#13#10 +
    '  LActions[0].Delay := 5000;'#13#10 +
    '  LActions[1].&Type := 1;'#13#10 +
    '  LActions[1].Delay := 5000;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
    'name[i].&Field := ... ist Element-Write (escaped keyword), kein Read');
  finally L.Free; end;
end;

procedure TTestUninitVar.StreamReadFillsIndexedBuffer_NoFinding;
// FP-Fix (Real-World 2026-06-28, Abbrevia AbCompnd / zip / ID3 etc.):
//   var Sig: array[..] of AnsiChar;
//   FStream.Read(Sig[0], n);   <- FUELLT den Buffer (out/var), kein Read
//   if Sig[0] = 'A' ...
// Der by-reference Array-Element-Arg 'Sig[0]' wurde als Read fehlgedeutet,
// der Buffer als "never assigned" gemeldet. Read-Family-Calls fuellen ihre
// Argumente -> das ist ein Write.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'uses System.Classes;'#13#10 +
    'implementation'#13#10 +
    'procedure P(FStream: TStream);'#13#10 +
    'var Sig: array[0..3] of AnsiChar;'#13#10 +
    'begin'#13#10 +
    '  FStream.Read(Sig[0], 4);'#13#10 +
    '  if Sig[0] = ''A'' then Exit;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
    'Stream.Read(Buf[0], n) fuellt den Buffer - kein UninitVar');
  finally L.Free; end;
end;

procedure TTestUninitVar.StreamReadFillsBareBuffer_NoFinding;
// Variante mit bare-Buffer-Arg (CnScanners Bom-Pattern, fcMedium):
//   Stream.Read(Bom, SizeOf(Bom));  <- Fill
//   if Bom[0] = #255 ...
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'uses System.Classes;'#13#10 +
    'implementation'#13#10 +
    'procedure P(Stream: TStream);'#13#10 +
    'var Bom: array[0..1] of AnsiChar;'#13#10 +
    'begin'#13#10 +
    '  Stream.Read(Bom, SizeOf(Bom));'#13#10 +
    '  if Bom[0] = #255 then Exit;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
    'Stream.Read(Bom, SizeOf(Bom)) fuellt den Buffer - kein UninitVar');
  finally L.Free; end;
end;

procedure TTestUninitVar.ReadBeforeStreamFill_StillFlagged;
// TP-Gegenkontrolle: ein ECHTER Read VOR dem Read-Family-Fill bleibt ein
// Bug. Die Fill-Erkennung darf nur die Fill-Zeile entschaerfen, nicht einen
// frueheren echten Read verschlucken.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'uses System.Classes;'#13#10 +
    'implementation'#13#10 +
    'procedure P(Stream: TStream);'#13#10 +
    'var n: Integer;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(n);'#13#10 +
    '  Stream.Read(n, SizeOf(n));'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.IsTrue(CountKind(L, fkUninitVar) >= 1,
    'echter Read vor dem Stream.Read-Fill bleibt ein UninitVar-Bug');
  finally L.Free; end;
end;

procedure TTestUninitVar.StreamFillThenLaterArgWrite_NoFinding;
// FP-Fix (Real-World 2026-06-28, SynEdit/Abbrevia relocated FPs): Num wird per
// Stream.Read gefuellt (echter Write), spaeter via Dec(Num) als Pessimistic-
// Arg-Write an SPAETERER Zeile erneut "geschrieben". Frueher maskierte der
// spaetere Dec-Write den echten Fill -> der Befund wurde nur verschoben
// (read 'while Num>0' vor dem Dec-Write). Earliest-Write-gewinnt loest auf.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'uses System.Classes;'#13#10 +
    'implementation'#13#10 +
    'procedure P(AStream: TStream);'#13#10 +
    'var Num: Integer;'#13#10 +
    'begin'#13#10 +
    '  AStream.Read(Num, SizeOf(Num));'#13#10 +
    '  while Num > 0 do'#13#10 +
    '    Dec(Num);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
    'Stream.Read-Fill darf nicht von spaeterem Dec(Num)-Arg-Write maskiert werden');
  finally L.Free; end;
end;

procedure TTestUninitVar.OuterVarReadOnlyInNestedRoutine_NoFinding;
// FP-Fix (Real-World 2026-06-28, uRuleCatalog.FindJsonFile / uFormatMismatch):
// outer-var 'Cands' wird im OUTER-Body erzeugt, aber nur in der nested routine
// 'AddRoot' gelesen. Die zweite var-Section ('C') triggert das Parser-Headless-
// Pattern -> nkNestedRange-Marker fehlen, AST-Outer-Write geht verloren ->
// frueher fcHigh-FP. Source-basierte Closure-Erkennung faengt das ab.
const
  // Verbatim-getreue Nachbildung von uRuleCatalog.FindJsonFile (Real-World-FP):
  // class function mit qualifiziertem Namen, Kommentar vor der Decl, nested
  // 'AddRoots' (liest Cands in einem for-begin, eigene var Dir/Parent/i),
  // nested function 'ModuleDir', ZWEITE var-Section (C), try/finally, Cands-
  // Create im outer-body. Exakt das Headless-Method-Pattern, das SCA166 frueher
  // als 'Cands never assigned' (fcHigh) fehlmeldete.
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TRuleCatalog = class'#13#10 +
    '    class function FindJsonFile: string; static;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'uses System.Generics.Collections, System.IOUtils;'#13#10 +
    'class function TRuleCatalog.FindJsonFile: string;'#13#10 +
    'var'#13#10 +
    '  // Cands wird im outer-body erstellt; AddRoots (nested) liest es vorher.'#13#10 +
    '  Cands : TList<string>;'#13#10 +
    ''#13#10 +
    '  procedure AddRoots(const BaseDir: string);'#13#10 +
    '  var'#13#10 +
    '    Dir, Parent : string;'#13#10 +
    '    i           : Integer;'#13#10 +
    '  begin'#13#10 +
    '    if BaseDir = '''' then Exit;'#13#10 +
    '    Dir := BaseDir;'#13#10 +
    '    for i := 0 to 8 do'#13#10 +
    '    begin'#13#10 +
    '      Cands.Add(Dir);'#13#10 +
    '      Parent := Dir + ''..'';'#13#10 +
    '      if SameText(Parent, Dir) then Break;'#13#10 +
    '      Dir := Parent;'#13#10 +
    '    end;'#13#10 +
    '  end;'#13#10 +
    ''#13#10 +
    '  function ModuleDir: string;'#13#10 +
    '  begin'#13#10 +
    '    Result := '''';'#13#10 +
    '  end;'#13#10 +
    'var'#13#10 +
    '  C : string;'#13#10 +
    'begin'#13#10 +
    '  Cands := TList<string>.Create;'#13#10 +
    '  try'#13#10 +
    '    AddRoots(''a'');'#13#10 +
    '    C := ModuleDir;'#13#10 +
    '    if C <> '''' then Cands.Add(C);'#13#10 +
    '    Result := '''';'#13#10 +
    '  finally'#13#10 +
    '    Cands.Free;'#13#10 +
    '  end;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
    'outer-var nur in nested routine gelesen, im outer-body erzeugt - kein UninitVar');
  finally L.Free; end;
end;

procedure TTestUninitVar.OuterVarUninitDespiteNestedRoutine_StillFlagged;
// TP-Gegenkontrolle: die Closure-Erkennung darf NUR greifen wenn die Variable
// wirklich in der nested routine vorkommt. 'Total' wird nie geschrieben und im
// OUTER-Body gelesen (nicht in Helper) -> bleibt ein echter UninitVar-Bug,
// auch wenn die Methode eine nested routine enthaelt.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'function F: Integer;'#13#10 +
    'var'#13#10 +
    '  Total: Integer;'#13#10 +
    '  procedure Helper;'#13#10 +
    '  begin'#13#10 +
    '    WriteLn(''hi'');'#13#10 +
    '  end;'#13#10 +
    'begin'#13#10 +
    '  Helper;'#13#10 +
    '  Result := Total;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.IsTrue(CountKind(L, fkUninitVar) >= 1,
    'Total nie geschrieben, im outer-body gelesen - bleibt UninitVar trotz nested routine');
  finally L.Free; end;
end;

// ============================================================
// Real-World FP-Audit 2026-07-10 (SCA166 war 100% FP im Korpus)
// ============================================================

procedure TTestUninitVar.TypecastAssignTargetGeneric_NoFinding;
// FP-Klasse 'typecast-assignment-target': 'TFunc<Integer>(raw) := delegate'
// schreibt raw (LHS-Cast). Der Read-Scan zaehlte raw faelschlich als Read,
// der Write landete erst auf einer spaeteren Arg-Zeile -> 'read before write'.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(const delegate: IInterface);'#13#10 +
    'var raw: TMethod;'#13#10 +
    'begin'#13#10 +
    '  TFunc<Integer>(raw) := delegate;'#13#10 +
    '  WriteLn(raw.Data);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'TFunc<Integer>(raw) := ... schreibt raw (Typecast-Assign-Target)');
  finally L.Free; end;
end;

procedure TTestUninitVar.ReceiverInitInAssignRHS_NoFinding;
// FP-Klasse 'record-method-init' im Expression-Kontext: 'n := tmp.Init(...)'
// initialisiert tmp (Self ist var). ProcessCall sah RHS-Calls nicht, weil der
// Parser sie als TypeRef-String ablegt statt als nkCall.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(const data: string);'#13#10 +
    'var tmp: TSynTempBuffer; n: Integer;'#13#10 +
    'begin'#13#10 +
    '  n := tmp.Init(data);'#13#10 +
    '  WriteLn(tmp.Len);'#13#10 +
    '  WriteLn(n);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'n := tmp.Init(data) initialisiert tmp (Receiver-Init auf RHS)');
  finally L.Free; end;
end;

procedure TTestUninitVar.FromInitVerbReceiverInExpr_NoFinding;
// 'ok := d.FromText(s)' - From*-Verb initialisiert den Receiver d (mORMot
// TSynDate.From... / T.FromHttpDate).
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(const s: string);'#13#10 +
    'var d: TSynDate; ok: Boolean;'#13#10 +
    'begin'#13#10 +
    '  ok := d.FromText(s);'#13#10 +
    '  WriteLn(d.Year);'#13#10 +
    '  WriteLn(ok);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'd.FromText(s) initialisiert d (From*-Init-Verb)');
  finally L.Free; end;
end;

procedure TTestUninitVar.LowHighInForHeader_NoFinding;
// 'for i := Low(a) to High(a)' - Low/High sind Compile-time-/Typ-Queries und
// lesen den Wert von a NICHT; a[i] := i ist ein Element-Write.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var i: Integer; a: array[0..3] of Integer;'#13#10 +
    'begin'#13#10 +
    '  for i := Low(a) to High(a) do'#13#10 +
    '    a[i] := i;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'Low(a)/High(a) im for-Header sind kein Werte-Read von a');
  finally L.Free; end;
end;

procedure TTestUninitVar.ReadBeforeTypecastAssign_StillFlagged;
// Gegenprobe zu Fix A: ein echter Read VOR dem (spaeteren) Typecast-Write
// bleibt ein Fund - der Fix loest nur auf, unterdrueckt nicht pauschal.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(src: Pointer);'#13#10 +
    'var raw: NativeInt;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(raw);'#13#10 +
    '  Pointer(raw) := src;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.IsTrue(CountKind(L, fkUninitVar) >= 1,
      'raw wird gelesen bevor der Typecast-Write erfolgt - bleibt SCA166');
  finally L.Free; end;
end;

// ============================================================
// Real-World FP-Audit 2026-07-10 - clean-Teilklassen SCA166
// ============================================================

procedure TTestUninitVar.MemberAccessAssignAfterLabel_NoFinding;
// FP-Klasse 'field-assignment-target' (Real-World InlineOp.pas:2710):
// 'Parms.ATag := Tag' ist ein (partieller) WRITE von Parms, kein Read.
// Das vorangehende Label 'TagOk:' verschluckt den AST-nkAssign-Write dieser
// Zeile; der Source-Read-Scan wertete 'Parms.ATag :=' faelschlich als Read
// und die naechste 'Parms.Info :='-Zeile als ersten Write -> read-before-
// write-FP. Der Member-Access-LHS-Skip loest das auf.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'type TParms = record ATag, Info, Id: Integer; end;'#13#10 +
    'function Foo(Tag, Info, Id: Integer): Integer;'#13#10 +
    'var Parms: TParms;'#13#10 +
    'begin'#13#10 +
    ' TagOk:'#13#10 +
    '  Parms.ATag := Tag;'#13#10 +
    '  Parms.Info := Info;'#13#10 +
    '  Parms.Id := Id;'#13#10 +
    '  Result := Parms.ATag;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'Parms.ATag := Tag ist ein Member-Write von Parms, kein uninit-Read');
  finally L.Free; end;
end;

procedure TTestUninitVar.MemberReadBeforeWrite_StillFlagged;
// TP-Gegenkontrolle zum Member-Access-Skip: ein ECHTER Werte-Read eines
// Record-Feldes VOR jedem Write (WriteLn(r.a) vor r.b := 5) bleibt ein Fund.
// Der Skip darf nur den Member-Write (':=' auf der LHS) entschaerfen, nicht
// einen RHS-Feld-Read verschlucken.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'type TRec = record a, b: Integer; end;'#13#10 +
    'procedure P;'#13#10 +
    'var r: TRec;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(r.a);'#13#10 +
    '  r.b := 5;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.IsTrue(CountKind(L, fkUninitVar) >= 1,
      'WriteLn(r.a) liest r vor jedem Write - bleibt ein UninitVar-Bug');
  finally L.Free; end;
end;

procedure TTestUninitVar.IfdefConstVsVarBranch_NoFinding;
// FP-Klasse 'conditional-compilation-const' (Real-World DAsmUtil.pas:497/574):
// SzF ist im {$IFDEF I64}-Zweig 'var SzF: byte' und im {$ELSE}-Zweig
// 'const SzF = 7'. Der Lexer sieht BEIDE Zweige; die const-Deklarationszeile
// des inaktiven Zweigs wurde als Read des var-Zweig-Locals gewertet und lag
// VOR dem echten Write 'SzF := 3' -> read-before-write-FP. Eine const-Decl
// liest nie eine lokale Variable -> IsConstDeclLine-Skip loest das auf.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'function getEA(W: integer): boolean;'#13#10 +
    'var'#13#10 +
    '  CurB: Byte;'#13#10 +
    '{$IFDEF I64}'#13#10 +
    'var'#13#10 +
    '  SzF: byte;'#13#10 +
    '{$ELSE}'#13#10 +
    'const'#13#10 +
    '  SzF = 7;'#13#10 +
    '{$ENDIF}'#13#10 +
    'begin'#13#10 +
    '  Result := false;'#13#10 +
    '  SzF := 3;'#13#10 +
    '  CurB := SzF;'#13#10 +
    '  Result := CurB > 0;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'const SzF = 7 im inaktiven {$ELSE}-Zweig ist kein Read der var-Zweig-Local');
  finally L.Free; end;
end;

procedure TTestUninitVar.EqualityConditionNotConstDecl_StillFlagged;
// TP-Gegenkontrolle zum const-Decl-Skip: eine Gleichheits-BEDINGUNG
// 'if n = 0 then ...' ist KEINE Konstanten-Deklaration und muss weiter als
// Read von n zaehlen. Sichert ab dass IsConstDeclLine nicht zu breit greift.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var n: Integer;'#13#10 +
    'begin'#13#10 +
    '  if n = 0 then WriteLn(''zero'');'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.IsTrue(CountKind(L, fkUninitVar) >= 1,
      'if n = 0 liest n (uninit) - keine const-Decl, muss weiter flaggen');
  finally L.Free; end;
end;

procedure TTestUninitVar.ReadInIfdefBranchWriteAfter_NoFinding;
// Welle 3 (Core-Detektoren-Architektur, dritter nkConditionalRange-Opt-in):
// n wird im {$IFDEF LOGGING}-Zweig gelesen (WriteLn(n)) und ERST NACH dem
// {$ENDIF} geschrieben. Der Lexer sieht beide Positionen; die Read-Zeile liegt
// vor der Write-Zeile -> read-before-write-FP. Auf jeder realen Uebersetzung
// existiert aber nur EIN Zweig (LOGGING an: Read compiliert, aber dann ist der
// Write drunter auch aktiv; LOGGING aus: der Read verschwindet komplett).
// Die {$ENDIF}-Direktivenzeile liegt strikt zwischen Read und Write -> Guard.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var n: Integer;'#13#10 +
    'begin'#13#10 +
    '{$IFDEF LOGGING}'#13#10 +
    '  WriteLn(n);'#13#10 +
    '{$ENDIF}'#13#10 +
    '  n := 5;'#13#10 +
    '  WriteLn(n);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'Read im {$IFDEF}-Zweig + Write nach {$ENDIF} = Preprocessor-Phantom, kein Fund');
  finally L.Free; end;
end;

procedure TTestUninitVar.ReadBeforeWriteDirectiveElsewhere_StillFlagged;
// TP-Gegenkontrolle zum nkConditionalRange-Guard: eine {$IFDEF}-Direktive im
// selben Method-Body, die aber NICHT strikt zwischen Read und Write liegt, darf
// den echten read-before-write NICHT unterdruecken. Sichert ab dass
// DirLineBetween praezise ist (nur die Direktive genau dazwischen zaehlt).
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var n: Integer;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(n);'#13#10 +
    '  n := 5;'#13#10 +
    '{$IFDEF LOGGING}'#13#10 +
    '  WriteLn(n);'#13#10 +
    '{$ENDIF}'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.IsTrue(CountKind(L, fkUninitVar) >= 1,
      'echter Read-vor-Write (Direktive erst danach) muss weiter flaggen');
  finally L.Free; end;
end;

// ============================================================
// Real-World FP-Audit 2026-07-12: var-param-out-write (Kat. A/C/D)
// ============================================================

procedure TTestUninitVar.ReceiverTypecastCallOutArg_NoFinding;
// Kat. A ('.'-Form, Alcinoe TransactionStart): der Receiver-Typecast
// 'TForm(Sender)' ist die ERSTE Klammer-Gruppe - das alte ExtractCallArgsRaw
// lieferte 'Sender' statt des echten var/out-Args 'h'. Jetzt werden ALLE
// Arg-Gruppen gescannt (Cast-Praefix uebersprungen) -> h bekommt pessimistic-Write.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(Sender: TObject);'#13#10 +
    'var h: NativeUInt;'#13#10 +
    'begin'#13#10 +
    '  TForm(Sender).StartTx(h);'#13#10 +
    '  if h > 0 then Exit;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'var/out-Arg nach Receiver-Typecast (.) muss pessimistic-Write bekommen');
  finally L.Free; end;
end;

procedure TTestUninitVar.ReceiverDerefTypecastCallOutArg_NoFinding;
// Kat. A ('^'-Form, CEF4Delphi get_components): 'PUpd(FData)^.get_components(
// PUpd(FData), cnt, comp)' - erstes '(' ist der Cast. cnt (2. Real-Arg) muss
// erkannt werden; der Cast-Operand-Deref '(FData)^' wird uebersprungen.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var cnt: NativeUInt;'#13#10 +
    'begin'#13#10 +
    '  PUpd(FData)^.get_components(PUpd(FData), cnt, comp);'#13#10 +
    '  if cnt > 0 then Exit;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'var/out-Arg im Method-Call nach Deref-Typecast (^) muss Write bekommen');
  finally L.Free; end;
end;

procedure TTestUninitVar.CaseSelectorCallOutArg_NoFinding;
// Kat. C (dominant, Abbrevia/HeidiSQL GetTimeZoneInformation): der Parser
// verwirft den case-Selektor -> 'GetTZI(tzi)' war unsichtbar -> tzi als
// uninitialisiert gemeldet. Der Source-Selektor-Scan registriert jetzt den
// pessimistic-Write fuer tzi.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(out Res: Integer);'#13#10 +
    'var tzi: Integer;'#13#10 +
    'begin'#13#10 +
    '  case GetTZI(tzi) of'#13#10 +
    '    0: Res := tzi;'#13#10 +
    '  else Res := 0;'#13#10 +
    '  end;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'var/out-Arg im case-Selektor-Call muss pessimistic-Write bekommen');
  finally L.Free; end;
end;

procedure TTestUninitVar.CallArgWithStringLiteralParen_NoFinding;
// Kat. D (Indy ParseMessageFlagString): ein String-Literal ')' im verschachtelten
// Arg brach die Paren-Zaehlung ab -> flags (nach dem Literal) wurde verfehlt.
// Nach String-Stripping zaehlen die Klammern korrekt -> flags bekommt Write.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(const s: string);'#13#10 +
    'var flags: Integer;'#13#10 +
    'begin'#13#10 +
    '  ParseFlags(Copy(s, 1, PosIdx('')'', s)), flags);'#13#10 +
    '  if flags > 0 then Exit;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'Arg nach String-Literal ) muss trotz Fehl-Klammer erkannt werden');
  finally L.Free; end;
end;

procedure TTestUninitVar.CastOperandOnlyRead_StillFlagged;
// FN-GEGENPROBE (kritisch): 'raw' kommt NUR als Typecast-Operand 'PFoo(raw)^'
// vor (ein READ), wird nie geschrieben. Der skip-by-suffix-Guard ueberspringt
// diese Gruppe -> raw bekommt KEINEN Write -> echter uninitialisierter Read
// bleibt ein Fund. Beweist dass der Fix Cast-Operanden nicht als Write wertet.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var raw: Pointer;'#13#10 +
    'begin'#13#10 +
    '  PFoo(raw)^.DoA();'#13#10 +
    '  PBar(raw)^.DoB();'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.IsTrue(CountKind(L, fkUninitVar) >= 1,
      'nur als Cast-Operand gelesene, nie geschriebene Var bleibt uninit-Fund');
  finally L.Free; end;
end;

procedure TTestUninitVar.CaseSelectorPlainVarNoCall_StillFlagged;
// OVER-SUPPRESS-GEGENPROBE: der case-Selektor ist die Variable SELBST (kein
// Call) -> der Selektor-Scan darf x NICHT als geschrieben werten. x wird nur
// gelesen, nie geschrieben -> bleibt Fund.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(out Res: Integer);'#13#10 +
    'var x: Integer;'#13#10 +
    'begin'#13#10 +
    '  case x of'#13#10 +
    '    0: Res := x;'#13#10 +
    '  else Res := 2;'#13#10 +
    '  end;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.IsTrue(CountKind(L, fkUninitVar) >= 1,
      'case-Selektor ohne Call darf die Selektor-Var nicht als geschrieben werten');
  finally L.Free; end;
end;

procedure TTestUninitVar.ChainedCallMultiArgOutArg_NoFinding;
// Verify-Nachschaerfung (Drop-Stichprobe mORMot EnterLocal): ein verketteter
// Multi-Arg-Call 'AddLog(n, self, x).Log(...)' fuellt 'n' als var/out-Arg des
// INNEREN Calls. Die Gruppe ist von '.' gefolgt (chained), hat aber ein Komma
// -> Multi-Arg-Call, kein Typecast -> Komma-Heuristik registriert den Write.
// (Ohne die Nachschaerfung wuerde skip-by-suffix 'n' faelschlich ueberspringen
// -> neuer FP; non-managed Typ, damit der managed-Skip das nicht maskiert.)
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var n: Integer;'#13#10 +
    'begin'#13#10 +
    '  Builder.AddLog(n, Self, 42).Log(''done'');'#13#10 +
    '  if n > 0 then Exit;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'var/out-Arg eines verketteten Multi-Arg-Calls (Komma) muss Write bekommen');
  finally L.Free; end;
end;

procedure TTestUninitVar.ManagedInterfaceVarReceiver_NoFinding;
// Verify-Nachschaerfung (Drop-Stichprobe mORMot ISynLog): eine Interface-
// typisierte Var (I + Grossbuchstabe) ist managed (refcounted, auto-nil) ->
// read-without-write ist kein SCA166-uninit-Bug (nil-Interface-Deref waere
// SCA008-Territorium). IsManagedType-Interface-Heuristik skippt sie.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var log: ISomeLog;'#13#10 +
    'begin'#13#10 +
    '  log.WriteLn(''a'');'#13#10 +
    '  log.WriteLn(''b'');'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try
    Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
      'Interface-Var (managed, auto-nil) ist kein SCA166-uninit-Fall');
  finally L.Free; end;
end;

// ============================================================
// Recharakterisierung after30 (2026-07-12): detector-lokale FP-Klassen
// ============================================================

procedure TTestUninitVar.HexLiteralSingleLetterVar_NoFinding;
// FP-Klasse 'hex-literal-digit': in 'D := B1 and $F;' matcht das 'F' in der
// Hex-Literal-Ziffernfolge $F wortgrenzengenau die gleichnamige Ein-Buchstaben-
// Var F. Ein '$' direkt davor -> Hex, kein Read (Bezeichner beginnen nie mit '$').
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var F, B1, D: Byte;'#13#10 +
    'begin'#13#10 +
    '  B1 := 2;'#13#10 +
    '  D := B1 and $F;'#13#10 +
    '  WriteLn(D);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
    '$F ist ein Hex-Literal, kein Read der Var F');
  finally L.Free; end;
end;

procedure TTestUninitVar.HexLiteralNotMaskingRealRead_StillFlagged;
// FN-Gegenprobe zum '$'-Guard: ein ECHTER Read von f (vor '$FF', nicht dahinter)
// bleibt ein Fund. Beweist, dass der Guard nur das $-praefigierte Match skippt.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var f, d: Byte;'#13#10 +
    'begin'#13#10 +
    '  d := f and $FF;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.IsTrue(CountKind(L, fkUninitVar) >= 1,
    'f wird vor jeder Zuweisung real gelesen (d := f ...) -> bleibt SCA166-Fund');
  finally L.Free; end;
end;

procedure TTestUninitVar.LengthOnArrayNotValueRead_NoFinding;
// FP-Klasse 'length-not-value-read': Length(Buf) ist eine Groessen-Query, die
// die Element-Inhalte NICHT liest (dynarray/String -> 0 bei nil; statisches
// Array -> compile-time). Kein uninit-Read.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var Buf: array[0..15] of Byte; n: Integer;'#13#10 +
    'begin'#13#10 +
    '  n := Length(Buf);'#13#10 +
    '  WriteLn(n);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
    'Length(Buf) liest keine Element-Inhalte -> kein uninit-Read');
  finally L.Free; end;
end;

procedure TTestUninitVar.LengthGuardArrayElementRead_StillFlagged;
// FN-Gegenprobe zum Length-INTR: ein echter Element-Read Buf[0] (Inhalt gelesen)
// bleibt ein Fund. Der Length-Guard darf nur Length(...) entschaerfen.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var Buf: array[0..15] of Byte; x: Byte;'#13#10 +
    'begin'#13#10 +
    '  x := Buf[0];'#13#10 +
    '  WriteLn(x);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.IsTrue(CountKind(L, fkUninitVar) >= 1,
    'Buf[0] liest echten Element-Inhalt vor jedem Write -> bleibt SCA166-Fund');
  finally L.Free; end;
end;

procedure TTestUninitVar.ManagedAliasTbtString_NoFinding;
// FP-Klasse 'managed-alias' (PascalScript): tbtString = AnsiString (compiler-
// managed, auto ''). Read-without-write ist kein uninit-Bug -> managed-Skip.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var s: tbtString;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(s);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
    'tbtString ist ein managed AnsiString-Alias (auto '''') -> kein uninit-Bug');
  finally L.Free; end;
end;

procedure TTestUninitVar.IdentToIntVarArgWrite_NoFinding;
// FP-Klasse 'var-out-param-write': IdentToInt(const Ident; var Int; const Map)
// FUELLT sein 2. Arg (var). Es stand faelschlich in READ_ALLOWLIST -> das
// gefuellte n galt als uninit-Read. Ohne den Eintrag registriert der pessimistic-
// Write-Default den Write von n vor dem spaeteren Read.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var n: Integer;'#13#10 +
    'begin'#13#10 +
    '  IdentToInt(''Foo'', n, SomeMap);'#13#10 +
    '  WriteLn(n);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var L : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, L);
  try Assert.AreEqual<Integer>(0, CountKind(L, fkUninitVar),
    'IdentToInt fuellt var-Arg n -> Write registriert -> kein uninit-Read');
  finally L.Free; end;
end;

// ============================================================
// #6 Inkr.4: CFG-Postfilter (Zyklus-Regel + ReachingDefs)
// ============================================================

procedure TTestUninitVar.CfgLoopAccumulatorGuarded_NoFinding;
// Regel B (Back-Edge): geguardeter Accumulator - 'Prev' wird in Iteration N
// geschrieben und in Iteration N+1 (im First-geguardeten Arm) gelesen. Der
// lexikalische Vergleich Read < Write meldete das vor Inkr.4 als fcMedium.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(Count: Integer);'#13#10 +
    'var Prev, Cur, Diff, i: Integer; First: Boolean;'#13#10 +
    'begin'#13#10 +
    '  First := True;'#13#10 +
    '  Diff := 0;'#13#10 +
    '  for i := 1 to Count do'#13#10 +
    '  begin'#13#10 +
    '    Cur := i * 2;'#13#10 +
    '    if not First then'#13#10 +
    '      Diff := Cur - Prev;'#13#10 +
    '    Prev := Cur;'#13#10 +
    '    First := False;'#13#10 +
    '  end;'#13#10 +
    '  WriteLn(Diff);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'Def erreicht den geguardeten Read ueber die Loop-Back-Edge -> kein Fund');
  finally F.Free; end;
end;

procedure TTestUninitVar.CfgStraightLineReadBeforeWrite_StillFlagged;
// TP-Gegenprobe (Same-Block-Entscheidung): ungeguardetes Read-vor-Write im
// selben Block ist auch im Loop-Fall ein plausibler Iteration-1-Bug und
// MUSS gemeldet bleiben.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var A, B: Integer;'#13#10 +
    'begin'#13#10 +
    '  B := A;'#13#10 +
    '  A := 1;'#13#10 +
    '  WriteLn(B);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      'straight-line Read-vor-Write bleibt ein Fund (Same-Block kein Drop)');
  finally F.Free; end;
end;

procedure TTestUninitVar.CfgSiblingArmsWithoutLoop_StillFlagged;
// Pin der bewussten v1-Entscheidung: exklusive Arme OHNE Loop droppen wir
// NICHT (Read-Arm kann beim ersten Durchlauf mit uninit V laufen - der
// Wert-Korrelations-Beweis fehlt). Aendert sich die Politik, faellt dieser
// Test bewusst rot.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(c: Boolean);'#13#10 +
    'var V, X: Integer;'#13#10 +
    'begin'#13#10 +
    '  if c then'#13#10 +
    '    X := V'#13#10 +
    '  else'#13#10 +
    '    V := 1;'#13#10 +
    '  WriteLn(X, V);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      'Sibling-Arme ohne Loop: Fund bleibt (v1-Politik, kein Wert-Beweis)');
  finally F.Free; end;
end;

procedure TTestUninitVar.CfgUnguardedLoopConditionRead_StillFlagged;
// Inkr.4b (MASKED_BUG-Fix aus dem Drop-Sampling, destilliert aus mormot
// bson BsonItemsToDocVariant): der Read steht UNGEGUARDET in der Schleifen-
// Bedingung - in Iteration 1 laeuft er auf der uninitialisierten Variable,
// KEIN Guard schuetzt. Die Zyklus-Regel (Write im Body <-> Read im Kopf)
// darf hier NICHT droppen.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var V: Integer;'#13#10 +
    'begin'#13#10 +
    '  while V < 10 do'#13#10 +
    '    V := V + 1;'#13#10 +
    '  WriteLn(V);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      'ungeguardeter Read in der Schleifenbedingung bleibt ein Fund');
  finally F.Free; end;
end;

procedure TTestUninitVar.DeclInitializedLocal_NoFinding;
// Inkr.4b: FPC-Deklarations-Initializer laeuft bei jedem Routineneintritt
// und dominiert jeden Read (im Drop-Sampling der wahre Sicherheits-
// mechanismus hinter ~der Haelfte der doublecmd-Drops). Der AST-Write-Scan
// sieht ihn nicht (kein ':='), Regel 0 des Filters schon.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var V: Integer = 1;'#13#10 +
    '    X: Integer;'#13#10 +
    'begin'#13#10 +
    '  X := V;'#13#10 +
    '  V := 2;'#13#10 +
    '  WriteLn(X, V);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'Decl-Initializer = Write bei Eintritt -> kein read-before-write');
  finally F.Free; end;
end;

procedure TTestUninitVar.DeclCommentEquals_StillFlagged;
// Inkr.4b-Haertung (Re-Scan-Audit: mormot cache x4): ein '=' im KOMMENTAR
// der Decl-Zeile ist KEIN Initializer - Regel 0 matcht auf der gestrippten
// Zeile. Sonst wuerde ein echter (dort sogar absichtlicher) Uninit-Read
// maskiert.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var V: Integer; // default = 1'#13#10 +
    '    X: Integer;'#13#10 +
    'begin'#13#10 +
    '  X := V;'#13#10 +
    '  V := 2;'#13#10 +
    '  WriteLn(X, V);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      'Kommentar-= auf der Decl-Zeile ist kein Initializer -> Fund bleibt');
  finally F.Free; end;
end;

procedure TTestUninitVar.VendorPrefixInterfaceLocal_NoFinding;
// Managed-Alias: 'IwbThing' (I + Kleinpraefix + CamelCase) ist nach Delphi-
// Konvention ein Interface -> compiler-nil-initialisiert -> nie ein echter
// uninit-Read. Vor dem Fix fiel das Muster durch die I-GROSSbuchstaben-
// Konvention (Drop-Sampling TES5Edit: IwbGroupRecord & Co.).
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var G: IwbThing; X: Integer;'#13#10 +
    'begin'#13#10 +
    '  X := G.Count;'#13#10 +
    '  WriteLn(X);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'Hersteller-Praefix-Interface ist managed -> kein uninit-Fund');
  finally F.Free; end;
end;

procedure TTestUninitVar.VendorPrefixButClass_StillFlagged;
// TP-Gegenprobe (Negativ-Gate): der Name sieht aus wie ein Vendor-
// Interface, ist laut TypeIndex aber eine KLASSE - uninitialisiert
// gelesene Klassen-Referenz bleibt ein echter Fund. Voller Pipeline-
// Weg, damit der Cross-Unit-TypeIndex die in-unit-Klasse kennt.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  IwbFake = class'#13#10 +
    '  public'#13#10 +
    '    Count: Integer;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var G: IwbFake; X: Integer;'#13#10 +
    'begin'#13#10 +
    '  X := G.Count;'#13#10 +
    '  WriteLn(X);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      'TypeIndex kennt IwbFake als Klasse -> Konvention geblockt, Fund bleibt');
  finally F.Free; end;
end;

procedure TTestUninitVar.ExitArgOutParamCall_NoFinding;
// A3: 'Exit(TryStrToInt64(S, v))' - der Parser legt das Exit-Argument als
// nkExit.TypeRef ab; KEINER der Expression-Call-Pfade sah das bisher ->
// v galt als never-written (MinimalAPI-Klasse lInt64/lFloat/lDate).
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'function P(const S: string): Boolean;'#13#10 +
    'var v: Int64;'#13#10 +
    'begin'#13#10 +
    '  Exit(TryStrToInt64(S, v));'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'TryStrTo*-out-Param im Exit-Arg zaehlt als Write');
  finally F.Free; end;
end;

procedure TTestUninitVar.ExitArgPlainVar_StillFlagged;
// TP-Gegenprobe: 'Exit(v)' ohne Call schreibt nichts - der neue Pfad
// registriert nur CALL-Argumente, der reine Var-Read bleibt ein Fund.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'function P: Integer;'#13#10 +
    'var v: Integer;'#13#10 +
    'begin'#13#10 +
    '  Exit(v);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      'Exit(v) ohne fuellenden Call bleibt ein uninit-Read');
  finally F.Free; end;
end;

procedure TTestUninitVar.AbsoluteAliasWrite_NoFinding;
// A3: Writes UEBER einen absolute-Alias muessen dem Ziel zugerechnet
// werden (isaac-Muster: ta[j] := ... fuellt tl byteweise).
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var tl: LongWord;'#13#10 +
    '    ta: array[0..3] of Byte absolute tl;'#13#10 +
    '    i: Integer;'#13#10 +
    'begin'#13#10 +
    '  for i := 0 to 3 do'#13#10 +
    '    ta[i] := i;'#13#10 +
    '  WriteLn(tl);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'Alias-Writes (ta[i] :=) zaehlen fuer das absolute-Ziel tl');
  finally F.Free; end;
end;

procedure TTestUninitVar.AddressOfFill_NoFinding;
// A3b: @v im Koerper = Variable kann ueber den Pointer gefuellt werden
// (Indy-Muster: LMsg.msg_name := @LAddr; RecvMsg fuellt). Konservativ
// als Write an der @-Zeile gewertet (dokumentiert FN-tolerant).
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var v: Integer; pp: Pointer;'#13#10 +
    'begin'#13#10 +
    '  pp := @v;'#13#10 +
    '  FillThing(pp);'#13#10 +
    '  WriteLn(v);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'Adressnahme @v zaehlt als potentieller Fill -> kein Fund');
  finally F.Free; end;
end;

procedure TTestUninitVar.ConstInlineCallVarArg_NoFinding;
// B Hook 1: 'const Ok = TryParseIt(S, v);' - der Parser verschluckt die
// RHS von Inline-const komplett (kein tkKwConst-Arm) -> v bekam nie den
// pessimistic-Write und galt als never-written (issrc-Klasse).
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'function P(const S: string): Boolean;'#13#10 +
    'var v: Int64;'#13#10 +
    'begin'#13#10 +
    '  const Ok = TryParseIt(S, v);'#13#10 +
    '  Result := Ok and (v > 0);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'unbekannter Call in Inline-const-RHS = pessimistic-Write auf v');
  finally F.Free; end;
end;

procedure TTestUninitVar.ConstInlineReadOnlyCall_StillFlagged;
// TP-Gegenprobe zu Hook 1: Copy ist READ_ALLOWLIST - die const-RHS
// registriert dann KEINEN Write, v bleibt uninit-Read (Fund bleibt).
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'function P(const S: string): Integer;'#13#10 +
    'var v: Integer;'#13#10 +
    'begin'#13#10 +
    '  const L = Copy(S, 1, v);'#13#10 +
    '  Result := Length(L) + v;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      'read-only const-RHS (Copy) schreibt nichts - Fund bleibt');
  finally F.Free; end;
end;

procedure TTestUninitVar.AllowlistWrapperInnerCall_NoFinding;
// B Hook 2: 'W := Trim(GetWordAt(S, iBeg))' - der read-only Wrapper
// versteckte den inneren Nicht-Allowlist-Call; jetzt Rekursion in die
// Argliste -> GetWordAt registriert den pessimistic-Write auf iBeg.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(const S: string);'#13#10 +
    'var iBeg: Integer;'#13#10 +
    '    W: string;'#13#10 +
    'begin'#13#10 +
    '  W := Trim(GetWordAt(S, iBeg));'#13#10 +
    '  if iBeg > 0 then WriteLn(W);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'innerer Nicht-Allowlist-Call im Trim-Wrapper schreibt iBeg');
  finally F.Free; end;
end;

procedure TTestUninitVar.AllowlistBareArg_StillFlagged;
// TP-Gegenprobe zu Hook 2: Allowlist-in-Allowlist ('Trim(IntToStr(v))')
// - beide read-only, die Rekursion endet ohne Write -> v bleibt Fund.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var v: Integer;'#13#10 +
    '    W: string;'#13#10 +
    'begin'#13#10 +
    '  W := Trim(IntToStr(v));'#13#10 +
    '  WriteLn(W);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      'read-only-Kette schreibt nie - uninit-Read von v bleibt Fund');
  finally F.Free; end;
end;

procedure TTestUninitVar.FpcDeclInitializer_NoHighFinding;
// B Hook 3: 'size: Int64 = 0;' (FPC-Decl-Initializer) laeuft bei jedem
// Routineneintritt - Rule 0 galt bisher nur im fcMedium-Zweig, der
// fcHigh-never-written-Zweig meldete trotzdem (doublecmd-Klasse).
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var size: Int64 = 0;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(size);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'Decl-Initializer dominiert jeden Read - kein fcHigh-Fund');
  finally F.Free; end;
end;

// ============================================================
// Inkrement B2 (Triage 2026-07-25): 7-Hook-Runde
// ============================================================

procedure TTestUninitVar.CallLhsAssignMultiArg_NoFinding;
// B2 Hook 1: 'UpperCopy255Buf(Buf, S)^ := #0' - der Parser legt den ganzen
// Call-Ausdruck als nkAssign.Name ab; ExtractBareIdent lieferte nur den
// Funktionsnamen -> Buf bekam keinen pessimistic-Write und galt als
// never-written (mormot PropNameUpper). RegisterCallArgWrites auf dem LHS
// registriert die Multi-Arg-Gruppe (Komma-Regel).
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(const S: string);'#13#10 +
    'var Buf: array[0..255] of AnsiChar;'#13#10 +
    'begin'#13#10 +
    '  UpperCopy255Buf(Buf, S)^ := #0;'#13#10 +
    '  WriteLn(Buf[0]);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'Call-LHS-Assign fuellt Buf als var/out-Arg - kein uninit-Fund');
  finally F.Free; end;
end;

procedure TTestUninitVar.CallLhsAssignUnrelatedVar_StillFlagged;
// TP-Gegenprobe zu Hook 1: der Hook registriert NUR die Args der LHS-
// Klammergruppe - eine unbeteiligte, nie geschriebene Var im selben Body
// bleibt ein Fund (keine Pauschal-Suppression durch Call-LHS-Zeilen).
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(const S: string);'#13#10 +
    'var Buf: array[0..7] of AnsiChar; u: Integer;'#13#10 +
    'begin'#13#10 +
    '  FillBuf(Buf, S)^ := #0;'#13#10 +
    '  WriteLn(u);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      'u ist kein Arg des Call-LHS - bleibt never-written-Fund');
  finally F.Free; end;
end;

procedure TTestUninitVar.SizeOfWithSpaces_NoFinding;
// B2 Hook 2: 'SizeOf ( Buf )' - der Intrinsic-Guard verlangte Null-Abstand
// in beide Richtungen; Spaces zwischen Intrinsic, '(' und Ident (auch von
// StripLineEx-geblankten Kommentaren erzeugt) liessen den Match als Read
// durchfallen -> never-written-FP auf reine Groessenabfragen.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var Buf: array[0..15] of Byte; n: Integer;'#13#10 +
    'begin'#13#10 +
    '  n := SizeOf ( Buf );'#13#10 +
    '  WriteLn(n);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'SizeOf ( Buf ) mit Spaces ist eine Groessen-Query, kein Werte-Read');
  finally F.Free; end;
end;

procedure TTestUninitVar.WriteLnWithSpaceParen_StillFlagged;
// TP-Gegenprobe zu Hook 2: die Whitespace-Toleranz gilt NUR fuer die 5
// Intrinsics (low/high/sizeof/typeinfo/length), NICHT fuer die
// READ_ALLOWLIST - 'WriteLn (u)' liest u real und bleibt ein Fund.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var u: Integer;'#13#10 +
    'begin'#13#10 +
    '  WriteLn (u);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      'WriteLn (u) mit Space liest u - kein Intrinsic, Fund bleibt');
  finally F.Free; end;
end;

procedure TTestUninitVar.LocalResourceStringEntry_NoFinding;
// B2 Hook 3: 'resourcestring' ist kein Lexer-Keyword - ab dem zweiten
// Eintrag wird jede Zeile 'SSecond = ''...'';' als Var-Decl geparst
// (TypeRef leer) und der Name landete als never-written-Pseudo-Var in der
// Inventur (issrc-Klasse). IsConstDeclLine auf der gestrippten Decl-Zeile
// skippt den Eintrag in PhaseA.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'resourcestring'#13#10 +
    '  SFirst = ''one'';'#13#10 +
    '  SSecond = ''two'';'#13#10 +
    'begin'#13#10 +
    '  WriteLn(SSecond);'#13#10 +
    '  WriteLn(SSecond);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'lokaler resourcestring-Eintrag ist keine Var - kein uninit-Fund');
  finally F.Free; end;
end;

procedure TTestUninitVar.PlainVarDeclOwnLine_StillFlagged;
// TP-Gegenprobe zu Hook 3: eine echte Decl-Zeile 'n: Integer;' (Var-Section,
// Name auf eigener Zeile) matcht IsConstDeclLine NICHT (kein '=') - die Var
// bleibt in der Inventur und der uninit-Read bleibt ein Fund.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var'#13#10 +
    '  n: Integer;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(n);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      'echte var-Decl-Zeile darf der Inventur-Skip nicht fressen');
  finally F.Free; end;
end;

procedure TTestUninitVar.ProcTypeMidParamLeak_NoFinding;
// B2 Hook 4 Form (a): ParseLocalVarSection stoppt die TypeName-Sammlung am
// ERSTEN ';' in der Parameterliste des proc-Typs - der Mittel-Parameter
// 'uFlags' wird als eigenstaendige Var-Decl geparst (TypeRef 'Cardinal',
// kein ')'/'=') und jede Body-Erwaehnung zaehlte als uninit-Read. Netto-
// offenes '(' VOR dem Namens-Match auf der Decl-Zeile -> Inventur-Skip.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var'#13#10 +
    '  CB: procedure(a: Integer; uFlags: Cardinal; c: Byte) of object;'#13#10 +
    'begin'#13#10 +
    '  if uFlags > 0 then'#13#10 +
    '    WriteLn(1);'#13#10 +
    '  if uFlags > 2 then'#13#10 +
    '    WriteLn(2);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'proc-Typ-Mittel-Parameter ist keine Local - kein uninit-Fund');
  finally F.Free; end;
end;

procedure TTestUninitVar.SignatureTailTypeLeak_NoFinding;
// B2 Hook 4 Form (b): bei keyword-benannten Params ('out result: TPayload')
// frisst der Parser 'out'/'result'/':' einzeln weg und sammelt den TYP-
// Ident als Var-NAMEN ein (TypeRef leer -> passiert alle Filter); Body-
// Erwaehnungen des Typs ('Obj is TPayload') zaehlten als uninit-Read
// (mormot 'out result: RawUtf8);'-Klasse). ')'-Ueberschuss ohne
// oeffnendes '(' auf der Decl-Zeile -> Inventur-Skip.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(Obj: TObject);'#13#10 +
    'var'#13#10 +
    '  Setter: procedure(const V: string;'#13#10 +
    '    out result: TPayload);'#13#10 +
    'begin'#13#10 +
    '  if Obj is TPayload then'#13#10 +
    '    WriteLn(1);'#13#10 +
    '  if Obj is TPayload then'#13#10 +
    '    WriteLn(2);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'Signatur-Schlusszeilen-Typ-Ident ist keine Local - kein uninit-Fund');
  finally F.Free; end;
end;

procedure TTestUninitVar.ProcPointerVarReadBeforeWrite_StillFlagged;
// TP-Gegenprobe zu Hook 4: die proc-Pointer-Var CB SELBST (Name VOR der
// Klammer, Zeile paren-balanciert) bleibt in der Inventur - der Aufruf
// 'CB(1, 2)' vor der Zuweisung bleibt ein echter read-before-write-Fund.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var CB: procedure(a: Integer; b: Byte) of object;'#13#10 +
    'begin'#13#10 +
    '  CB(1, 2);'#13#10 +
    '  CB := GetHandler();'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      'proc-Pointer-Var vor Zuweisung aufgerufen - Fund bleibt');
  finally F.Free; end;
end;

procedure TTestUninitVar.WithRecordBasis_NoFinding;
// B2 Hook 6: 'with r do begin Left := 1; ... end' fuellt Felder der Basis,
// die Feld-Writes sind r aber nicht zuordenbar -> r galt als never-written
// obwohl der with-Body initialisiert. Konservativer Write an der with-
// Zeile (analog @-Scan; single-target, wortgebunden).
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var r: TSettingsRec;'#13#10 +
    'begin'#13#10 +
    '  with r do'#13#10 +
    '  begin'#13#10 +
    '    Left := 1;'#13#10 +
    '    Top := 2;'#13#10 +
    '  end;'#13#10 +
    '  WriteLn(r.Left);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'with-Body fuellt die Record-Basis - kein never-written-Fund');
  finally F.Free; end;
end;

procedure TTestUninitVar.WithClassBasis_StillFlagged;
// TP-Gegenprobe zu Hook 6 (Klassen-Gate): der TypeIndex kennt TBox als
// KLASSE - 'with b do' ist der echte Deref einer uninitialisierten
// Referenz, der with-Write darf NICHT registriert werden; der Folge-Read
// b.Left bleibt ein never-written-Fund. Voller Pipeline-Weg, damit der
// Cross-Unit-TypeIndex die in-unit-Klasse kennt.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TBox = class'#13#10 +
    '  public'#13#10 +
    '    Left: Integer;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var b: TBox;'#13#10 +
    'begin'#13#10 +
    '  with b do'#13#10 +
    '    Left := 1;'#13#10 +
    '  WriteLn(b.Left);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      'with auf uninitialisierter Klassen-Referenz bleibt ein Fund');
  finally F.Free; end;
end;

procedure TTestUninitVar.DecayRhsPszField_NoFinding;
// B2 Hook 7: 'Info.pszDisplayName := NameBuffer' nimmt die Adresse des
// statischen Char-Arrays (Decay ohne '@'); SHBrowseForFolder & Co. fuellen
// den Buffer spaeter ueber den gespeicherten Pointer -> NameBuffer galt
// als never-written. psz/lp-Zielfeld + Char-Array-RHS = konservativer
// Write an der Decay-Zeile (Semantik des @-Scans).
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var NameBuffer: array[0..259] of AnsiChar;'#13#10 +
    '    Info: TBrowseInfo;'#13#10 +
    'begin'#13#10 +
    '  Info.pszDisplayName := NameBuffer;'#13#10 +
    '  ShowFolder(Info);'#13#10 +
    '  WriteLn(NameBuffer[0]);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'Decay auf psz-Feld = Adressnahme, Buffer wird via Pointer gefuellt');
  finally F.Free; end;
end;

procedure TTestUninitVar.DecayRhsPlainField_StillFlagged;
// TP-Gegenprobe zu Hook 7 (PFLICHT-psz-Gate, Reviewer-Fall): 'Obj.Name :=
// Buf' ist ein echter WERT-Read des uninitialisierten Char-Arrays
// (String-Property/Ganz-Array-Copy) - das Zielfeld beginnt nicht mit
// psz/lp, der Hook darf keinen Write registrieren, der Garbage-Read
// bleibt ein Fund.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(Obj: TThing);'#13#10 +
    'var Buf: array[0..15] of AnsiChar;'#13#10 +
    'begin'#13#10 +
    '  Obj.Name := Buf;'#13#10 +
    '  Obj.Caption := Buf;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      'Obj.Name := Buf liest den uninit. Buffer - psz-Gate haelt den Fund');
  finally F.Free; end;
end;

// ============================================================
// Zensus-Triage 2026-07-25: Hook 1a/1b + Kleinserie H2/H3/H4/H5
// ============================================================

procedure TTestUninitVar.ParenlessReceiverInitRHS_NoFinding;
// Hook 1a (Zensus mormot.lib.sspi:2211): 'sz := tmp.Init shr 1' ruft den
// PARAMETERLOSEN Record-Init auf (TSynTempBuffer.Init; Self ist var) -
// die '('-Pflicht in ProcessReceiverInitInExpr liess tmp an dieser Zeile
// als Read zaehlen, der pessimistic-Write kam erst mit dem API-Call der
// Folgezeile -> read-before-write-FP. Parenlos gilt NUR die Init-Verb-
// Allowlist (Feld-Read lexikalisch nicht unterscheidbar).
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'function P(H: Cardinal): Cardinal;'#13#10 +
    'var'#13#10 +
    '  tmp: TTempBuf;'#13#10 +
    '  sz, res: Cardinal;'#13#10 +
    'begin'#13#10 +
    '  sz := tmp.Init shr 1;'#13#10 +
    '  res := ApiRead(H, tmp.buf, sz);'#13#10 +
    '  WriteLn(res);'#13#10 +
    '  Result := sz;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'tmp.Init (parenlos) initialisiert den Receiver - kein read-before-write');
  finally F.Free; end;
end;

procedure TTestUninitVar.ParenlessNonInitMemberRead_StillFlagged;
// TP-Gegenprobe zu Hook 1a: ein parenloser Member-Zugriff mit NICHT-Init-
// Verb ('rec.Value') ist ein normaler Feld-READ des uninitialisierten
// Records - das Init-Verb-Gate darf ihn nicht als Write werten, der
// read-before-write-Fund bleibt.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var'#13#10 +
    '  rec: TCrossRec;'#13#10 +
    '  n: Integer;'#13#10 +
    'begin'#13#10 +
    '  n := rec.Value + 1;'#13#10 +
    '  Prepare(rec);'#13#10 +
    '  WriteLn(n);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      'rec.Value ist Feld-Read vor dem ersten Write - Fund bleibt');
  finally F.Free; end;
end;

procedure TTestUninitVar.SameFileVarOutArgCall_NoFinding;
// Hook 1b: Headless-Method-Pattern (nested routine + zweite var-Section)
// verliert die Outer-Body-nkCalls - 'Decode(S, Value)' registrierte keinen
// pessimistic-Write, Value galt als never-written (fcHigh-FP). Die Same-
// File-Signatur-Aufloesung sieht 'var Value: Integer' an Position 2 der
// Decode-Signatur -> Write an der Call-Zeile.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure Decode(const S: string; var Value: Integer);'#13#10 +
    'begin'#13#10 +
    '  Value := Length(S);'#13#10 +
    'end;'#13#10 +
    'procedure P(const S: string);'#13#10 +
    'var'#13#10 +
    '  Value: Integer;'#13#10 +
    ''#13#10 +
    '  procedure Helper;'#13#10 +
    '  begin'#13#10 +
    '    WriteLn(''hi'');'#13#10 +
    '  end;'#13#10 +
    ''#13#10 +
    'var'#13#10 +
    '  C: Integer;'#13#10 +
    'begin'#13#10 +
    '  Helper;'#13#10 +
    '  Decode(S, Value);'#13#10 +
    '  C := Value + 1;'#13#10 +
    '  WriteLn(C);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'Decode fuellt Value (var-Param, same-file Signatur) - kein Fund');
  finally F.Free; end;
end;

procedure TTestUninitVar.ReadBeforeVarOutArgCall_StillFlagged;
// TP-Gegenprobe zu Hook 1b: der var/out-Write zaehlt nur AN der Call-Zeile
// - ein Read VOR dem Fill-Call bleibt ein echter read-before-write-Fund
// (die Aufloesung darf den Read-Anker nicht rueckwirkend loeschen).
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure Fill(var N: Integer);'#13#10 +
    'begin'#13#10 +
    '  N := 1;'#13#10 +
    'end;'#13#10 +
    'procedure P;'#13#10 +
    'var Value: Integer;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(Value);'#13#10 +
    '  Fill(Value);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      'Read VOR dem var-Arg-Call - Fund bleibt trotz Signatur-Aufloesung');
  finally F.Free; end;
end;

procedure TTestUninitVar.InlineConstSelfIdent_NoFinding;
// H2: 'const Half = X div 2;' im Body deklariert eine KONSTANTE - Half
// SELBST ist ab der Decl initialisiert, ein uninit-Fund darauf ist
// kategorisch falsch (die RHS-Args deckt der PhaseC-const-Scan von
// Inkrement B bereits ab).
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(X: Integer);'#13#10 +
    'var Y: Integer;'#13#10 +
    'begin'#13#10 +
    '  const Half = X div 2;'#13#10 +
    '  Y := Half;'#13#10 +
    '  WriteLn(Y);'#13#10 +
    '  WriteLn(Half);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'Inline-const-Ident ist immer initialisiert - kein uninit-Fund');
  finally F.Free; end;
end;

procedure TTestUninitVar.ConstWordInComment_StillFlagged;
// TP-Gegenprobe zu H2 (Kommentar-Konvention): 'const' im ZEILENKOMMENTAR
// der Decl macht die Zeile nicht zur const-Decl - der H2-Check laeuft auf
// der GESTRIPPTEN Zeile, der echte read-before-write bleibt Fund.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var'#13#10 +
    '  n: Integer; // const tuning knob'#13#10 +
    'begin'#13#10 +
    '  WriteLn(n);'#13#10 +
    '  n := 1;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      '''const'' im Kommentar ist keine const-Decl - Fund bleibt');
  finally F.Free; end;
end;

procedure TTestUninitVar.FpcHideMarkerAdjacent_NoFinding;
// H3: '{%H-}' direkt am Var-Namen der Decl = explizite FPC-/Lazarus-
// Autor-Suppression. BEWUSSTE Ausnahme der 'Kommentare zaehlen nie'-
// Regel: der Marker IST ein Kommentar und wird deshalb auf der ROHEN
// Zeile geprueft (s. HasAdjacentFpcHideMarker).
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var'#13#10 +
    '  {%H-}Buf: Integer;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(Buf);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      '{%H-} an der Decl = Autor-Intent, nie melden');
  finally F.Free; end;
end;

procedure TTestUninitVar.HMarkerOtherVar_StillFlagged;
// TP-Gegenprobe zu H3 (Adjazenz-Pflicht): der Marker an einer ANDEREN
// Variable suppresst nicht mit - N bleibt ein never-written-Fund.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var'#13#10 +
    '  {%H-}Tmp: Integer;'#13#10 +
    '  N: Integer;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(Tmp);'#13#10 +
    '  WriteLn(N);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      '{%H-} gilt nur fuer die markierte Var - N bleibt Fund');
  finally F.Free; end;
end;

procedure TTestUninitVar.GetProcAddressAtLhs_NoFinding;
// H4 (Befund-Absicherung): '@MyProc := GetProcAddress(...)' ist ein Write
// auf MyProc an der Zeile - bereits durch den A3b-@-Scan abgedeckt (die
// LHS-Adressnahme registriert, der Read-Scan skippt '@'-Vorkommen). Der
// Test sichert die Zusage ohne neuen Code ab.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(H: THandle);'#13#10 +
    'var MyProc: TProcFn;'#13#10 +
    'begin'#13#10 +
    '  @MyProc := GetProcAddress(H, ''x'');'#13#10 +
    '  if Assigned(MyProc) then'#13#10 +
    '    WriteLn(1);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      '@X := GetProcAddress(...) schreibt X - kein uninit-Fund');
  finally F.Free; end;
end;

procedure TTestUninitVar.ReadBeforeAtLhsAssign_StillFlagged;
// TP-Gegenprobe zu H4: ein Read VOR der '@X :='-Zeile bleibt ein echter
// read-before-write-Fund (der @-Write zaehlt nur an seiner Zeile).
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(H: THandle);'#13#10 +
    'var MyProc: TProcFn;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(Assigned(MyProc));'#13#10 +
    '  @MyProc := GetProcAddress(H, ''x'');'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      'Read vor @X := ... - Fund bleibt');
  finally F.Free; end;
end;

procedure TTestUninitVar.TypeNamePhantomLocal_NoFinding;
// H5 (Symptom-Gate keyword-misparse): traegt der gemeldete Var-NAME im
// File eine eigene TYP-Deklaration ('TPhantom = class'), ist der
// nkLocalVar-Knoten eine fehlgeparste Decl - der Typname wurde als Local
// eingesammelt. Emit-Skip statt Fund.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TPhantom = class'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var TPhantom: Integer;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(TPhantom);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'Var-Name == in-File-Typname -> fehlgeparste Decl, kein Fund');
  finally F.Free; end;
end;

procedure TTestUninitVar.NameEqualsConstNotType_StillFlagged;
// TP-Gegenprobe zu H5: 'Limit = 5' ist eine KONSTANTE, keine Typ-Decl -
// das Gate verlangt class/record/... hinter dem '=' und darf die echte
// never-written-Local Limit nicht suppressen.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'const'#13#10 +
    '  Limit = 5;'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var Limit: Integer;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(Limit);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      'Namensgleiche Konstante ist kein Typ - Fund bleibt');
  finally F.Free; end;
end;

// ============================================================
// Welle 1 (2026-07-25): managed-autoinit + tkiClass-Gate 1a-Zweig
// ============================================================

procedure TTestUninitVar.DynArrayBareLocal_NoFinding;
// Hook 1 (managed-autoinit): 'var a: array of Byte' ist ein DYNAMISCHES
// Array - der Compiler initialisiert es auf nil (managed wie string) ->
// read-without-write ist nie ein echter uninit-Bug. Beweis kommt aus der
// Decl-Quellzeile ('array' + Whitespace + 'of'), nicht aus dem homonym-
// ambigen Token-konkatenierten TypeRef ('arrayofbyte').
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var'#13#10 +
    '  a: array of Byte;'#13#10 +
    '  n: Byte;'#13#10 +
    'begin'#13#10 +
    '  n := a[0];'#13#10 +
    '  WriteLn(n);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'array of T ist compiler-initialisiert (nil) - kein uninit-Fund');
  finally F.Free; end;
end;

procedure TTestUninitVar.DynArrayHomonymNamedType_StillFlagged;
// TP-Gegenprobe zu Hook 1 (die HeidiSQL-Homonym-Lehre): der NAMENSTYP
// 'ArrayOfByte' liefert im AST denselben TypeRef wie ein echtes
// 'array of Byte' (Token-Konkat ohne Spaces) - seine Fremd-Decl koennte
// ein STATISCHES Array sein, dessen Garbage-Read ein echter Bug ist.
// Das Quellzeilen-Gate (Pflicht-Whitespace in 'array of') darf weder
// den Namenstyp noch das statische 'array[0..3] of Byte' suppressen.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var'#13#10 +
    '  a: ArrayOfByte;'#13#10 +
    '  b: array[0..3] of Byte;'#13#10 +
    '  n: Byte;'#13#10 +
    'begin'#13#10 +
    '  n := a[0];'#13#10 +
    '  n := n + b[0];'#13#10 +
    '  WriteLn(n);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 2,
      'Namenstyp-Homonym + statisches Array bleiben beide Funde');
  finally F.Free; end;
end;

procedure TTestUninitVar.ParenlessInitVerbClassReceiver_StillFlagged;
// Hook 3 (Review-Follow-up zu Hook 1a): 'b := c.Initialized' auf einem
// KLASSEN-Receiver ist ein Property-/Feld-READ der uninitialisierten
// Referenz - das parenlose Init-Verb-Gate darf ihn NICHT als Init-Write
// werten (sonst waere der echte Bug maskiert). Voller Pipeline-Weg,
// damit der Cross-Unit-TypeIndex TConn als tkiClass beweist.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TConn = class'#13#10 +
    '  public'#13#10 +
    '    Initialized: Boolean;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var c: TConn; b: Boolean;'#13#10 +
    'begin'#13#10 +
    '  b := c.Initialized;'#13#10 +
    '  WriteLn(b);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      'Property-Read auf beweisbarer Klasse zaehlt nicht als Init-Write');
  finally F.Free; end;
end;

procedure TTestUninitVar.ParenlessInitRecordReceiver_NoFinding;
// Gegenprobe zu Hook 3 (Suppression bleibt): auf einem beweisbaren
// RECORD-Receiver initialisiert der parenlose Init-Verb-Zugriff den
// Receiver weiterhin (Self ist var-Parameter) - das tkiClass-Gate darf
// die Hook-1a-Suppression fuer Records/Fremdtypen nicht mitreissen.
// Voller Pipeline-Weg (TypeIndex kennt TTmp als tkiRecord).
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TTmp = record'#13#10 +
    '    buf: Integer;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'function P: Integer;'#13#10 +
    'var tmp: TTmp; sz: Integer;'#13#10 +
    'begin'#13#10 +
    '  sz := tmp.Init shr 1;'#13#10 +
    '  Result := sz + tmp.buf;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'Record-Receiver: parenloses tmp.Init bleibt Init-Write, kein Fund');
  finally F.Free; end;
end;

// ============================================================
// Real-World-Audit 30% (2026-07-31): sechs FP-Klassen, je NoFinding
// (ohne Fix rot) + TP-Gegenprobe.
// ============================================================

procedure TTestUninitVar.WithBlockFieldNameCollision_NoFinding;
// FP-Klasse 'with-Scope-Poisoning' (jcl JclGraphUtils vcl/2657): innerhalb
// 'with Pts[0] do' sind X/Y die FELDER des TPoint, nicht die gleichnamigen
// Locals. Ohne den Fix meldet SCA166 X und Y als nie zugewiesen.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'uses System.Types;'#13#10 +
    'implementation'#13#10 +
    'procedure P(const Pts: array of TPoint);'#13#10 +
    'var'#13#10 +
    '  X, Y: Integer;'#13#10 +
    '  X1, Y1: Integer;'#13#10 +
    'begin'#13#10 +
    '  with Pts[0] do'#13#10 +
    '  begin'#13#10 +
    '    X1 := X;'#13#10 +
    '    Y1 := Y;'#13#10 +
    '  end;'#13#10 +
    '  WriteLn(X1 + Y1);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'Bezeichner im with-Block koennen Felder des with-Ziels sein - kein Fund');
  finally F.Free; end;
end;

procedure TTestUninitVar.WithBlockReadAfterBlock_StillFlagged;
// TP-Gegenprobe: das with-Gate neutralisiert NUR Read-Anker INNERHALB des
// Blocks. Eine nie geschriebene Variable, die nach dem 'end;' gelesen wird,
// bleibt ein Fund (sonst waere die Blockgrenze wirkungslos).
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'uses System.Types;'#13#10 +
    'implementation'#13#10 +
    'procedure P(const Pts: array of TPoint);'#13#10 +
    'var'#13#10 +
    '  X1, N: Integer;'#13#10 +
    'begin'#13#10 +
    '  with Pts[0] do'#13#10 +
    '  begin'#13#10 +
    '    X1 := 1;'#13#10 +
    '  end;'#13#10 +
    '  WriteLn(N + X1);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      'Read ausserhalb des with-Blocks bleibt ein uninit-Fund');
  finally F.Free; end;
end;

procedure TTestUninitVar.UnknownVarOutArgCall_NoFinding;
// FP-Klasse 'unbekannte var/out-Param-Writer' (jvcl JvSpeedbarForm:1049):
// '(Sender as TDrawGrid).MouseToCell(X, Y, Col, Row)' FUELLT Col/Row ueber
// var-Parameter. Das Statement beginnt mit '(' - der Parser liefert dafuer
// keinen nkCall, also fehlte der pessimistic-Write und die Arg-Position
// zaehlte als Read.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(Sender: TObject; var Accept: Boolean);'#13#10 +
    'var'#13#10 +
    '  Col, Row: Longint;'#13#10 +
    'begin'#13#10 +
    '  (Sender as TDrawGrid).MouseToCell(4, 8, Col, Row);'#13#10 +
    '  Accept := (Row >= 0) and (Row <> 7);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'bare Arg-Position eines unbekannten Calls ist ein Write, kein Read');
  finally F.Free; end;
end;

procedure TTestUninitVar.IfParenBareVarNotCallArg_StillFlagged;
// TP-Gegenprobe zum Arg-Write: 'if (n) then' ist KEIN Aufruf - weder steht
// '(' direkt am Bezeichner noch ist 'if' eine Routine (NONCALL_TOKENS).
// Der Read von n bleibt erhalten.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var n: Boolean;'#13#10 +
    'begin'#13#10 +
    '  if (n) then'#13#10 +
    '    WriteLn(''x'');'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      'Klammer-Bedingung ist kein Call-Argument - uninit-Read bleibt Fund');
  finally F.Free; end;
end;

procedure TTestUninitVar.AnonMethodBodyRead_NoFinding;
// FP-Klasse 'anonyme Methoden' (TES5Edit xeMainForm:13373): der Read von
// NodeData steht im Rumpf einer anonymen Funktion und laeuft DEFERRED - die
// Zuweisung im Umgebungsscope erfolgt vor dem AUFRUF, nicht vor der
// Definition. Ohne Fix: read-before-write-FP.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(List: TObject);'#13#10 +
    'var'#13#10 +
    '  NodeData: PNodeData;'#13#10 +
    '  Check: TFunc<Boolean>;'#13#10 +
    'begin'#13#10 +
    '  Check := function: Boolean'#13#10 +
    '    begin'#13#10 +
    '      Result := NodeData.Flag;'#13#10 +
    '    end;'#13#10 +
    '  NodeData := GetData(List);'#13#10 +
    '  if Check() then'#13#10 +
    '    WriteLn(''hit'');'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'Closure-Rumpf ist eigener, deferred Scope - keine Read/Write-Ordnung');
  finally F.Free; end;
end;

procedure TTestUninitVar.AnonMethodParamShadowsLocal_NoFinding;
// FP-Klasse 'Closure-Parameter-Shadowing' (TES5Edit wbBSArchive:2462): das
// 'j' im Rumpf ist der PARAMETER der anonymen Prozedur (immer definiert),
// nicht das gleichnamige Outer-Local, dessen for-Schleife erst spaeter folgt.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(Total: Integer);'#13#10 +
    'var'#13#10 +
    '  j: Integer;'#13#10 +
    '  s: string;'#13#10 +
    'begin'#13#10 +
    '  s := '''';'#13#10 +
    '  RunParallel(0, Total, procedure(j: Integer) begin'#13#10 +
    '    s := s + IntToStr(j);'#13#10 +
    '  end);'#13#10 +
    '  for j := 0 to Total do'#13#10 +
    '    WriteLn(j);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'Closure-Parameter j ist nicht das Outer-Local - kein uninit-Read');
  finally F.Free; end;
end;

procedure TTestUninitVar.ReadOutsideAnonMethod_StillFlagged;
// TP-Gegenprobe: die Anon-Suppression darf nur greifen, wenn die Variable
// wirklich im Closure-Rumpf vorkommt. 'Total' wird nie geschrieben und
// AUSSERHALB gelesen - der Fund bleibt. Sichert zugleich, dass ein
// EINZEILIGER anonymer Rumpf keinen Range aufspannt, der die Folgezeilen
// mitnimmt (nach Pre-Build-Review 2026-07-31 beginnt der Rumpf erst NACH der
// Kopfzeile, ein Einzeiler ergibt daher gar keinen Range).
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var'#13#10 +
    '  Total: Integer;'#13#10 +
    '  Cb: TProc;'#13#10 +
    'begin'#13#10 +
    '  Cb := procedure begin WriteLn(''hi''); end;'#13#10 +
    '  Cb();'#13#10 +
    '  WriteLn(Total);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      'Total kommt im Closure-Rumpf nicht vor - bleibt never-written-Fund');
  finally F.Free; end;
end;

procedure TTestUninitVar.DynArrayAliasType_NoFinding;
// FP-Klasse 'cross-unit managed Typen' (mormot.db.sql.oracle:1691):
// 'TByteDynArray' ist per Namenskonvention ein dynamisches Array - der
// Compiler initialisiert es auf nil, ein read-without-write ist nie ein Bug.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(Cnt: Integer);'#13#10 +
    'var'#13#10 +
    '  Hacked: TByteDynArray;'#13#10 +
    'begin'#13#10 +
    '  if Hacked = nil then'#13#10 +
    '    SetLength(Hacked, Cnt);'#13#10 +
    '  WriteLn(Length(Hacked));'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'T*DynArray ist managed (auto-nil) - kein UninitVar');
  finally F.Free; end;
end;

procedure TTestUninitVar.MarshallerRecord_NoFinding;
// FP-Klasse 'cross-unit managed Typen' (horse ThirdParty.Posix.Syslog:90):
// TMarshaller ist ein RTL-Record mit ausschliesslich managed Feldern - die
// bare Verwendung ohne Zuweisung IST das offizielle Idiom.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(const AFormat: string);'#13#10 +
    'var'#13#10 +
    '  LMarshaller: TMarshaller;'#13#10 +
    '  str: MarshaledAString;'#13#10 +
    'begin'#13#10 +
    '  str := LMarshaller.AsAnsi(AFormat, CP_UTF8).ToPointer;'#13#10 +
    '  DoLog(str);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'TMarshaller ist auto-init (nur managed Felder) - kein UninitVar');
  finally F.Free; end;
end;

procedure TTestUninitVar.NonDynArrayAliasType_StillFlagged;
// TP-Gegenprobe zur Namenskonvention: 'TByteArray' hat KEIN DynArray-Suffix
// und kann ein statisches Array sein - dessen Garbage-Read ist ein echter
// Bug und muss Fund bleiben.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var'#13#10 +
    '  b: TByteArray;'#13#10 +
    '  n: Byte;'#13#10 +
    'begin'#13#10 +
    '  n := b[0];'#13#10 +
    '  WriteLn(n);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      'Namenstyp ohne DynArray-Suffix bleibt unmanaged - Fund bleibt');
  finally F.Free; end;
end;

procedure TTestUninitVar.VendorInterfaceWithInterfaceParent_NoFinding;
// FP-Klasse 'cross-unit managed Typen', Reichweiten-Grenze tkiClass
// (TES5Edit wbDefinitionsCommon:3310 'var lCER: IwbContainerElementRef'):
// der Parser legt Interfaces als nkClass ab, der TypeIndex fuehrt sie als
// tkiClass und blockte damit die I-Konvention. Die ELTERNKETTE beweist das
// Interface. Voller Pipeline-Weg, damit der TypeIndex die Decl kennt.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  IwbBase = interface'#13#10 +
    '    function Count: Integer;'#13#10 +
    '  end;'#13#10 +
    '  IwbThing = interface(IwbBase)'#13#10 +
    '    function More: Integer;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var G: IwbThing; X: Integer;'#13#10 +
    'begin'#13#10 +
    '  X := G.Count;'#13#10 +
    '  WriteLn(X);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'Interface-Elternkette beweist managed (auto-nil) - kein UninitVar');
  finally F.Free; end;
end;

procedure TTestUninitVar.VendorPrefixClassWithClassParent_StillFlagged;
// TP-Gegenprobe zur Elternketten-Regel: der Name sieht aus wie ein Vendor-
// Interface, der Typ ist aber eine KLASSE mit T-Wurzel (TObject) - die
// uninitialisiert gelesene Referenz bleibt ein echter Fund.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  IwbFake2 = class(TObject)'#13#10 +
    '  public'#13#10 +
    '    Count: Integer;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var G: IwbFake2; X: Integer;'#13#10 +
    'begin'#13#10 +
    '  X := G.Count;'#13#10 +
    '  WriteLn(X);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      'Klasse mit TObject-Wurzel ist kein Interface - Fund bleibt');
  finally F.Free; end;
end;

procedure TTestUninitVar.RecordCtorOnInstance_NoFinding;
// FP-Klasse 'Record-Konstruktor-Instanzaufruf' (Dev-Cpp
// SynHighlighterMulti:841): 'iParser.Create(...)' auf einem TRegEx-RECORD
// initialisiert die Instanz in place (Self ist var-Parameter).
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(const S: string);'#13#10 +
    'var'#13#10 +
    '  iParser: TRegEx;'#13#10 +
    '  M: TMatch;'#13#10 +
    'begin'#13#10 +
    '  iParser.Create(S, []);'#13#10 +
    '  M := iParser.Match(S);'#13#10 +
    '  WriteLn(M.Success);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'Ctor-Aufruf auf der Record-Instanz initialisiert sie - kein UninitVar');
  finally F.Free; end;
end;

procedure TTestUninitVar.ClassCtorOnInstance_StillFlagged;
// TP-Gegenprobe zum Ctor-Gate: auf einer beweisbaren KLASSE (TypeIndex
// tkiClass) ist 'c.Create(...)' der Deref einer uninitialisierten Referenz
// und bleibt ein Fund. Voller Pipeline-Weg wegen des TypeIndex.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TConn2 = class'#13#10 +
    '  public'#13#10 +
    '    Tag: Integer;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var c: TConn2; n: Integer;'#13#10 +
    'begin'#13#10 +
    '  c.Create(5);'#13#10 +
    '  n := c.Tag;'#13#10 +
    '  WriteLn(n);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      'Ctor-Aufruf auf uninitialisierter Klassen-Referenz bleibt ein Fund');
  finally F.Free; end;
end;

procedure TTestUninitVar.DirectiveInMemberPathAssign_NoFinding;
// FP-Klasse 'LHS-Punktpfad' (doublecmd synapse blcksock:3706): eine
// {$IFDEF}-Direktive MITTEN im Feldpfad wird vom Stripper zu Spaces geblankt
// und riss die Qualifier-Kette auf - der partielle WRITE galt als Read.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(const Src: array of Byte);'#13#10 +
    'var'#13#10 +
    '  Multicast6: TIPv6mreq;'#13#10 +
    '  n: Integer;'#13#10 +
    'begin'#13#10 +
    '  for n := 0 to 15 do'#13#10 +
    '    Multicast6.addr.{$IFDEF POSIX}s6a{$ELSE}u6a{$ENDIF}[n] := Src[n];'#13#10 +
    '  Multicast6.iface := 0;'#13#10 +
    '  WriteLn(Multicast6.iface);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'Feld-Zuweisung mit Direktive im Pfad ist ein Write, kein Read');
  finally F.Free; end;
end;

procedure TTestUninitVar.MemberPathPlainSpaceRead_StillFlagged;
// TP-Gegenprobe zur Luecken-Toleranz: echte Trenn-Spaces ('if r.Flag then')
// duerfen die Qualifier-Kette NICHT verlaengern - 'r.Flag' bleibt ein Read
// vor dem spaeteren Feld-Write.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'type TRec = record Flag: Boolean; end;'#13#10 +
    'procedure P;'#13#10 +
    'var'#13#10 +
    '  r: TRec;'#13#10 +
    '  x: Integer;'#13#10 +
    'begin'#13#10 +
    '  if r.Flag then x := 1;'#13#10 +
    '  r.Flag := False;'#13#10 +
    '  WriteLn(x);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      'r.Flag in der Bedingung ist ein Read - Fund bleibt');
  finally F.Free; end;
end;

procedure TTestUninitVar.MenuItemInfoDecayField_NoFinding;
// FP-Klasse 'Array-Adress-Decay' (vcl-styles-utils
// Vcl.Styles.Utils.SystemMenu:91): 'LMenuInfo.dwTypeData := Buffer' nimmt nur
// die ADRESSE des char-Arrays (MENUITEMINFO.dwTypeData ist ein LPTSTR),
// GetMenuItemInfo fuellt den Puffer danach.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(H: THandle; Idx: Integer);'#13#10 +
    'var'#13#10 +
    '  LMenuInfo: TMenuItemInfo;'#13#10 +
    '  Buffer: array [0 .. 79] of char;'#13#10 +
    'begin'#13#10 +
    '  LMenuInfo.fMask := 1;'#13#10 +
    '  LMenuInfo.dwTypeData := Buffer;'#13#10 +
    '  LMenuInfo.cch := SizeOf(Buffer);'#13#10 +
    '  if GetMenuItemInfo(H, Idx, True, LMenuInfo) then'#13#10 +
    '    WriteLn(Buffer);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'Decay auf das LPTSTR-Feld dwTypeData ist Adressnahme, kein Wert-Read');
  finally F.Free; end;
end;

procedure TTestUninitVar.InlineDeclInitLaterHomonym_NoFinding;
// FP-Klasse 'inline-const/inline-var mit Initialisierer' (issrc
// IDE.MainForm:4795 vs. 4831): derselbe Name wird weiter unten als inline-var
// deklariert - der Parser verankert nkLocalVar DORT, und die fruehere
// 'const Info = ...'-Zeile zaehlte als Read vor der 'Erst-Zuweisung'.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(const S: string; c: Boolean);'#13#10 +
    'begin'#13#10 +
    '  if c then begin'#13#10 +
    '    const Info = MakeInfo(S);'#13#10 +
    '    WriteLn(Info.Kind);'#13#10 +
    '  end else begin'#13#10 +
    '    var Info := MakeInfo(S);'#13#10 +
    '    WriteLn(Info.Kind);'#13#10 +
    '  end;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'Deklaration mit Initialisierer ist ein Write dieses Namens');
  finally F.Free; end;
end;

procedure TTestUninitVar.InlineDeclInitOtherName_StillFlagged;
// TP-Gegenprobe zum Namens-Gate: die inline-const deklariert 'Other', nicht
// 'n' - der Initialisierer-Write darf NICHT auf n uebertragen werden, der
// read-before-write von n bleibt ein Fund.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(const S: string);'#13#10 +
    'var n: Integer;'#13#10 +
    'begin'#13#10 +
    '  const Other = Length(S);'#13#10 +
    '  WriteLn(n + Other);'#13#10 +
    '  n := 5;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      'inline-const anderen Namens schreibt n nicht - Fund bleibt');
  finally F.Free; end;
end;

procedure TTestUninitVar.LocalNamedLikeManagedType_NoFinding;
// FP-Klasse 'Keyword-als-Bezeichner' (mormot.net.acme:672 'protected:
// RawUtf8;'): der Parser fuehrt den TYPNAMEN als Variable. Der Test pinnt das
// SYMPTOM-Gate (Var-Name == bekannter managed Typname = Phantom); der
// Parser-Bruch selbst ist ausgeklammert.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var'#13#10 +
    '  RawUtf8: Integer;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(RawUtf8);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
      'Variable mit exaktem Typnamen ist ein Parser-Phantom - kein Fund');
  finally F.Free; end;
end;

procedure TTestUninitVar.NameStartsWithTypeName_StillFlagged;
// TP-Gegenprobe: das Gate matcht EXAKT. Eine echte Variable, deren Name mit
// einem Typnamen BEGINNT ('VariantList'), bleibt in der Inventur.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var'#13#10 +
    '  VariantList: Integer;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(VariantList);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      'Name beginnt nur mit einem Typnamen - echte Variable, Fund bleibt');
  finally F.Free; end;
end;

// ============================================================
// Pre-Build-Review 2026-07-31: Regressionstests zu den drei
// bestaetigten Defekten an den neuen SCA166-Gates.
// ============================================================

procedure TTestUninitVar.WithBlockTrailingCommentBoundary_StillFlagged;
// Review-Fund 'with-Poisoning' (uUninitVar.pas CollectWithRangesFromStripped):
// StripLineEx blankt den Zeilenkommentar zu SPACES und behaelt die Laenge -
// das Blockende per EndsWith(';') schlug deshalb fehl und der with-Range lief
// bis zur naechsten kommentarfreien ';'-Zeile, hier also ueber 'WriteLn(N ...)'
// hinweg. Damit haette AUSGERECHNET der Kommentar den fremden Fund von N
// stillgestellt. Ohne die Korrektur ist dieser Test ROT (0 Funde).
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'uses System.Types;'#13#10 +
    'implementation'#13#10 +
    'procedure P(const Pts: array of TPoint);'#13#10 +
    'var'#13#10 +
    '  X1, N: Integer;'#13#10 +
    'begin'#13#10 +
    '  with Pts[0] do'#13#10 +
    '    X1 := X;   // X ist das Feld des with-Ziels'#13#10 +
    '  WriteLn(N + X1);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      'with-Rumpf endet an der Anweisung - der Read von N danach bleibt Fund');
  finally F.Free; end;
end;

procedure TTestUninitVar.AnonAssignHeaderLineRead_StillFlagged;
// Review-Fund 'Anon-Range' (uUninitVar.pas CollectAnonRangesFromStripped):
// die Range begann auf der KOPFZEILE, dadurch galt das Zuweisungsziel 'CB'
// als 'im Closure-Rumpf benutzt' und der read-before-write aus dem gepinnten
// TP-Test ProcPointerVarReadBeforeWrite_StillFlagged verschwand, sobald die
// RHS eine inline-Anon-Methode ist. Der Rumpf beginnt jetzt erst NACH dem
// Kopf; ein einzeiliger Rumpf ergibt gar keine Range.
// Nur EIN Local deklariert - jeder fkUninitVar-Fund gehoert zu CB.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'var CB: procedure(a: Integer; b: Byte) of object;'#13#10 +
    'begin'#13#10 +
    '  CB(1, 2);'#13#10 +
    '  CB := procedure(a: Integer; b: Byte) begin end;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1,
      'Zuweisungsziel auf der Anon-Kopfzeile ist kein Closure-Gebrauch');
  finally F.Free; end;
end;

procedure TTestUninitVar.UnknownArgWriteAfterRead_KeepsDeclAnchor;
// Review-Fund 'Monotonie' (uUninitVar.pas PhaseC, Arg-Write-Hook): Row wird
// erst in der MouseToCell-Zeile gefuellt, der Read in der if-Bedingung liegt
// DAVOR. Ohne das Monotonie-Gate haette der neue Write den bestehenden
// fcHigh-Fund (Anker Deklarationszeile, 'never assigned') in einen
// fcMedium-Fund auf der if-Zeile verwandelt - im SARIF ein DROP plus ein ADD
// auf einer vorher fundfreien Zeile. Erwartung: Anker unveraendert.
// Col taucht im AST gar nicht auf (das mit '(' beginnende Statement wird von
// SkipToSemicolon verschluckt) -> RefCount 1 -> UnusedLocal-Domain, kein Fund.
// Damit ist Row der einzige erwartete Fund.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(Sender: TObject);'#13#10 +
    'var'#13#10 +
    '  Col, Row: Integer;'#13#10 +
    'begin'#13#10 +
    '  if Row > 0 then Exit;'#13#10 +
    '  (Sender as TDrawGrid).MouseToCell(4, 8, Col, Row);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkUninitVar),
      'genau ein Fund (Row) - Col wird gefuellt und nie gelesen');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'Col, Row: Integer'),
      TFindingHelper.FirstOf(F, fkUninitVar).LineNumber,
      'Anker bleibt die Deklarationszeile - kein Wechsel auf die Read-Zeile');
  finally F.Free; end;
end;

procedure TTestUninitVar.CtorOnInstanceAfterRead_KeepsDeclAnchor;
// Schluss-Verifikation 2026-07-31, BLOCKER 1 (uUninitVar.pas
// ApplyReceiverInit, Zweig "MethodLow = 'create'"): Gegenstueck zu
// RecordCtorOnInstance_NoFinding - hier steht das Vorkommen von iParser VOR
// der Create-Zeile. Der Ctor-Write ist damit KEINE Aufloesung mehr: ohne das
// Monotonie-Gate haette er den bestehenden fcHigh-Fund (Anker
// Deklarationszeile, 'never assigned') in einen fcMedium-Fund auf der
// Match-Zeile umgehaengt - im SARIF ein DROP plus ein ADD auf einer vorher
// fundfreien Zeile (Attributionsbruch beim Korpus-Gate).
// Erwartung: Anker UND Confidence unveraendert. TypeIndex ist ueber
// FindingsOfFile leer, das Klassen-Gate greift also nicht - genau die
// Konstellation, in der der neue Hook feuert.
// M wird auf der Match-Zeile geschrieben und danach gelesen - kein zweiter
// Fund, der Fund fuer iParser ist der einzige erwartete.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(const S: string);'#13#10 +
    'var'#13#10 +
    '  iParser: TRegEx;'#13#10 +
    '  M: TMatch;'#13#10 +
    'begin'#13#10 +
    '  M := iParser.Match(S);'#13#10 +
    '  iParser.Create(S, []);'#13#10 +
    '  WriteLn(M.Success);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkUninitVar),
      'genau ein Fund (iParser) - M wird vor dem Lesen geschrieben');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'iParser: TRegEx'),
      TFindingHelper.FirstOf(F, fkUninitVar).LineNumber,
      'Anker bleibt die Deklarationszeile - kein Wechsel auf die Read-Zeile');
    Assert.AreEqual(fcHigh,
      TFindingHelper.FirstOf(F, fkUninitVar).Confidence,
      'Confidence bleibt fcHigh - kein Kippen in den fcMedium-Zweig');
  finally F.Free; end;
end;

procedure TTestUninitVar.DecayFieldAfterRead_KeepsDeclAnchor;
// Schluss-Verifikation 2026-07-31, BLOCKER 2 (uUninitVar.pas ProcessAssign,
// Decay-Adressnahme-Hook, NEUER Feldname 'dwtypedata'): Gegenstueck zu
// MenuItemInfoDecayField_NoFinding - hier wird der Puffer VOR der
// Decay-Zuweisung gelesen. Ohne das Monotonie-Gate haette der Decay-Write den
// fcHigh-Fund auf der Deklarationszeile in einen fcMedium-Fund auf der
// WriteLn-Zeile umgehaengt (DROP + ADD).
// WriteLn steht in der READ_ALLOWLIST, ist also ein echter Read und kein
// pessimistic-Write; SizeOf ist eine Compile-time-Query und damit ebenfalls
// keine Write-Quelle. Der Decay-Hook ist die einzige Write-Quelle fuer Buffer.
const
  SRC =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P(H: THandle; Idx: Integer);'#13#10 +
    'var'#13#10 +
    '  LMenuInfo: TMenuItemInfo;'#13#10 +
    '  Buffer: array [0 .. 79] of char;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(Buffer);'#13#10 +
    '  LMenuInfo.dwTypeData := Buffer;'#13#10 +
    '  LMenuInfo.cch := SizeOf(Buffer);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  F : TObjectList<TLeakFinding>;
begin
  RunOn(SRC, F);
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkUninitVar),
      'genau ein Fund (Buffer) - LMenuInfo wird nur geschrieben');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'Buffer: array'),
      TFindingHelper.FirstOf(F, fkUninitVar).LineNumber,
      'Anker bleibt die Deklarationszeile - kein Wechsel auf die Read-Zeile');
    Assert.AreEqual(fcHigh,
      TFindingHelper.FirstOf(F, fkUninitVar).Confidence,
      'Confidence bleibt fcHigh - kein Kippen in den fcMedium-Zweig');
  finally F.Free; end;
end;

procedure TTestUninitVar.RecordConstLabel_SameNameAsLocal_NoFinding;
// Der Orpheus-Fall aus dem Kundenkorpus (TestOvcDate.pas:40): das
// 'res:' im Record-Konstruktor benennt ein FELD von TData, nicht die
// gleichnamige lokale Variable. Weil die const-Sektion VOR der
// Zuweisung steht, sah das wie ein 'read before write' aus.
//
// Der Aufbau bildet die Quelle genau nach - insbesondere stehen die
// Record-FELDER auf eigenen Zeilen. Das ist nicht Kosmetik: schreibt
// man den Record einzeilig
//     type TRec = record y: Integer; res: Boolean; end;
// verankert der Detektor die Lesestelle auf DIESER Zeile statt auf dem
// Konstruktor, und das Gate greift nicht. Diese einzeilige Form ist
// ein eigener, im Korpus NICHT gemessener Fall - bewusst offen
// gelassen statt blind mitgefangen.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure Foo;'#13#10+
  'type'#13#10+
  '  TRec = record'#13#10+
  '    y:   Integer;'#13#10+
  '    res: Boolean;'#13#10+
  '  end;'#13#10+
  'const'#13#10+
  '  cData : array[0..1] of TRec ='#13#10+
  '    ((y: 1; res: True),'#13#10+
  '     (y: 2; res: False));'#13#10+
  'var'#13#10+
  '  res : Boolean;'#13#10+
  '  i   : Integer;'#13#10+
  'begin'#13#10+
  '  for i := 0 to 1 do'#13#10+
  '  begin'#13#10+
  '    res := (cData[i].y > 0);'#13#10+
  '    if res <> cData[i].res then'#13#10+
  '      Halt(1);'#13#10+
  '  end;'#13#10+
  'end;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUninitVar),
    'ein Feld-Label im Record-Konstruktor ist kein Lesezugriff');
  finally F.Free; end;
end;

procedure TTestUninitVar.RealReadBeforeWrite_StillReported;
// Gegenprobe: derselbe Aufbau, aber die Variable wird WIRKLICH vor der
// Zuweisung gelesen. Ohne diesen Test koennte das neue Gate die Regel
// stillschweigend abschalten.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var res: Boolean; i: Integer;'#13#10+
  'begin'#13#10+
  '  if res then i := 1;'#13#10+
  '  res := False;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkUninitVar) >= 1,
    'ein echtes read-before-write muss weiterhin melden');
  finally F.Free; end;
end;

procedure TTestUninitVar.KeywordNamedLocal_Assigned_NoPhantomTypename;
// mormot RecvWait-Muster: 'read: integer;' - 'read' ist nicht reserviert.
// Vor dem Parser-Fix wurde 'integer' als typlose Variable gefuehrt und
// jedes 'integer' der Signatur als Read gezaehlt ("integer is read on
// line ... but never assigned").
const SRC =
  'unit t; implementation'#13#10 +
  'function RecvWait(ms: integer): integer;'#13#10 +
  'var'#13#10 +
  '  read: integer;'#13#10 +
  'begin'#13#10 +
  '  read := SizeOf(ms);'#13#10 +
  '  Result := read;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
    'weder Phantom-"integer" noch die korrekt zugewiesene "read"-Var');
  finally F.Free; end;
end;

procedure TTestUninitVar.KeywordNamedLocal_ResultInProcedure_NoPhantom;
// python4delphi-Muster: lokale Variable 'Result' in einer PROZEDUR
// (legal - Result ist dort kein implizites Symbol). Vorher: Phantom-
// Variable 'PPyObject', gelesen auf der Kopfzeile.
const SRC =
  'unit t; implementation'#13#10 +
  'type PPyObject = ^Integer;'#13#10 +
  'procedure ExecuteEvent(Event: PPyObject);'#13#10 +
  'var'#13#10 +
  '  Result: PPyObject;'#13#10 +
  'begin'#13#10 +
  '  Result := nil;'#13#10 +
  '  if Result = nil then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
    'kein Phantom-"PPyObject" - und Result wird vor dem Read gesetzt');
  finally F.Free; end;
end;

procedure TTestUninitVar.KeywordNamedLocal_TrulyUninit_ReportedUnderRealName;
// Der Parser-Fix ist kein blosser Suppressor: die keyword-benannte
// Variable ist jetzt eine ECHTE Variable - bleibt sie uninitialisiert,
// kommt der Fund unter ihrem richtigen Namen.
const SRC =
  'unit t; implementation'#13#10 +
  'function Bad(ms: integer): integer;'#13#10 +
  'var'#13#10 +
  '  read: integer;'#13#10 +
  'begin'#13#10 +
  '  Result := read;'#13#10 +
  'end;';
var
  F : TObjectList<TLeakFinding>;
  i : Integer;
  Getroffen : Boolean;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.IsTrue(CountKind(F, fkUninitVar) >= 1, 'echter uninit-Read');
    Getroffen := False;
    for i := 0 to F.Count - 1 do
      if (F[i].Kind = fkUninitVar) and
         (Pos('read', LowerCase(F[i].MissingVar)) > 0) and
         (Pos('integer is read', LowerCase(F[i].MissingVar)) = 0) then
        Getroffen := True;
    Assert.IsTrue(Getroffen,
      'der Fund nennt die echte Variable "read", nicht den Typnamen');
  finally F.Free; end;
end;

procedure TTestUninitVar.OutParamOverload_ShorterTwin_NoFinding;
// JclSysUtils-Muster: zwei unit-lokale Overloads, die kuerzere OHNE, die
// laengere MIT out-Parameter an Position 2. Der Call bindet die laengere;
// die alte Merge-Kappung auf die KUERZERE Liste loeschte das out-Flag ->
// 'FirstDigitPos is read but never assigned' (2 Error-Tier-FPs in rw8).
const SRC =
  'unit t; implementation'#13#10 +
  'function IntToStr2(const Value: Int64): string; overload;'#13#10 +
  'begin'#13#10 +
  '  Result := '''';'#13#10 +
  'end;'#13#10 +
  'function IntToStr2(const Value: Int64; out FirstDigitPos: Integer): string; overload;'#13#10 +
  'begin'#13#10 +
  '  FirstDigitPos := 1;'#13#10 +
  '  Result := '''';'#13#10 +
  'end;'#13#10 +
  'function Probe(K: Int64): string;'#13#10 +
  'var'#13#10 +
  '  FirstDigitPos: Integer;'#13#10 +
  'begin'#13#10 +
  '  Result := IntToStr2(K, FirstDigitPos);'#13#10 +
  '  if FirstDigitPos > 0 then Result := Result + ''x'';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, CountKind(F, fkUninitVar),
    'out-Position der laengeren Overload zaehlt als Write');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUninitVar);

end.
