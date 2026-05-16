unit uTestRuleCatalog;

// Tests fuer TRuleCatalog (rules/sca-rules.json).
// Konsistenz-Suite: stellt sicher dass jeder TFindingKind einen Catalog-
// Eintrag hat. Wenn jemand einen neuen Detector + TFindingKind hinzufuegt
// ohne JSON zu pflegen, faellt der Test sofort auf.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes,
  uSCAConsts, uRuleCatalog;

type
  [TestFixture]
  TTestRuleCatalog = class
  public
    [Setup] procedure Setup;

    // Pro TFindingKind muss eine Rule existieren mit nicht-leerer ID.
    [Test] procedure EveryFindingKindHasRule;
    // Strengere Variante: pro Kind muessen Name + ShortDescription gesetzt
    // sein (faengt den Fallback-Pfad ab, der ID befuellt aber Beschreibung
    // leer laesst -> SARIF/Docs unvollstaendig ohne dass Test schreit).
    [Test] procedure EveryFindingKindHasRichMetadata;
    // KIND_META.DefaultSeverity muss zu rules/sca-rules.json
    // defaultSeverity passen - verhindert dass Pascal-Detektoren und
    // JSON-Catalog gegeneinander driften (Catalog ist single source of
    // truth fuer Severity nach Refactor in uMethodd12.TLeakFinding.SetKind).
    [Test] procedure JsonSeverityMatchesKindMeta;
    // Sonar MQR-Mapping: pro Kind MUSS cleanCodeAttribute UND mindestens
    // ein impact gesetzt sein. Verhindert dass neue Detektoren ohne
    // MQR-Klassifikation in den Sonar-Generic-Issue-Export rutschen
    // (P1 in todo-sonar.md).
    [Test] procedure EveryFindingKindHasMqrMapping;
    // ID-Konvention: 'SCA' + 3-stellige Nummer.
    [Test] procedure RuleIDsFollowConvention;
    // IDs muessen unique sein.
    [Test] procedure RuleIDsAreUnique;
    // Kind-Name in JSON muss zu KindName(K) matchen.
    [Test] procedure KindNameMatchesCatalog;
    // Tool-Info muss gesetzt sein (fuer SARIF tool.driver-Block).
    [Test] procedure ToolInfoIsPopulated;
    // Lookup ueber ID muss alle Kinds zurueckliefern koennen.
    [Test] procedure GetRuleByIDRoundtrip;

    // Profile-Loader (sca-rules.json -> profiles.*):
    // 'default' ist immer vorhanden und enthaelt alle Kinds.
    [Test] procedure ProfileDefaultContainsAllKinds;
    // Unbekanntes Profile faellt auf AllKinds zurueck (kein Crash).
    [Test] procedure ProfileUnknownFallsBackToAll;
    // Leerer Profile-Name liefert AllKinds (Sentinel fuer "Profile nicht gesetzt").
    [Test] procedure ProfileEmptyNameReturnsAll;
    // ide-fast schliesst alle Hint-Detektoren (LongMethod, MagicNumber, ...) aus
    // und enthaelt mindestens die kern-sicherheitsrelevanten Kinds.
    [Test] procedure ProfileIdeFastExcludesHintsIncludesSecurity;
    // ProfileNames listet alle Profile aus der JSON (mindestens
    // default, ide-fast, strict).
    [Test] procedure ProfileNamesIncludesBundled;
    // security-Profile enthaelt NUR Vulnerability/Hotspot-Kinds, keine
    // Pascal-Bugs wie MemoryLeak oder Smells wie LongMethod.
    [Test] procedure ProfileSecurityIsTightlyScoped;
    // bugs-only-Profile enthaelt MemoryLeak/NilDeref/... aber KEINE Smells
    // wie LongMethod/TodoComment.
    [Test] procedure ProfileBugsOnlyExcludesSmells;
    // code-quality-Profile ist das Gegenstueck zu bugs-only: nur Smells +
    // Duplikate, keine Bugs / Vulnerabilities.
    [Test] procedure ProfileCodeQualityExcludesBugs;
    // dfm-only enthaelt ausschliesslich Dfm*-Kinds.
    [Test] procedure ProfileDfmOnlyContainsOnlyDfmKinds;
  end;

implementation

uses
  System.Generics.Collections, System.RegularExpressions;

procedure TTestRuleCatalog.Setup;
begin
  TRuleCatalog.Reload; // garantiert frischen Zustand pro Test
end;

procedure TTestRuleCatalog.EveryFindingKindHasRule;
var
  K    : TFindingKind;
  Meta : TRuleMeta;
begin
  for K := Low(TFindingKind) to High(TFindingKind) do
  begin
    Meta := TRuleCatalog.GetRule(K);
    Assert.IsNotEmpty(Meta.ID,
      Format('Kind %s hat keine Rule-ID im Catalog', [KindName(K)]));
    Assert.AreEqual(K, Meta.Kind,
      Format('Kind-Mismatch fuer %s', [KindName(K)]));
  end;
end;

procedure TTestRuleCatalog.EveryFindingKindHasRichMetadata;
// Strenger als EveryFindingKindHasRule: ShortDescription + Name muessen
// non-empty sein. Faengt den Fall ab, dass TRuleCatalog.LoadFallback
// einspringt - der fuellt ID + Kind, laesst aber Beschreibungen leer ->
// SARIF-Reports und docs/rules.md fehlt Content ohne dass irgendein Test
// das sichtbar macht.
var
  K    : TFindingKind;
  Meta : TRuleMeta;
begin
  for K := Low(TFindingKind) to High(TFindingKind) do
  begin
    Meta := TRuleCatalog.GetRule(K);
    Assert.IsNotEmpty(Meta.Name,
      Format('Kind %s hat keinen Catalog-Eintrag mit Name (Fallback aktiv?)',
        [KindName(K)]));
    Assert.IsNotEmpty(Meta.ShortDescription,
      Format('Kind %s hat keine shortDescription in rules/sca-rules.json',
        [KindName(K)]));
    Assert.IsNotEmpty(Meta.DetectorUnit,
      Format('Kind %s hat keinen detectorUnit-Eintrag', [KindName(K)]));
  end;
end;

procedure TTestRuleCatalog.JsonSeverityMatchesKindMeta;
// Konsistenz-Check: JSON-defaultSeverity == KIND_META.DefaultSeverity.
// Nach dem SetKind-Refactor zieht jeder Detector die Severity aus
// KIND_META; SARIF-Export holt sie aus dem JSON-Catalog. Wenn die
// beiden divergieren, sehen User unterschiedliche Severities in IDE
// (KIND_META) vs. Sonar/CI-Report (JSON). Single source of truth ist
// per Definition die JSON - dieser Test enforced dass KIND_META synct.
var
  K    : TFindingKind;
  Meta : TRuleMeta;
begin
  for K := Low(TFindingKind) to High(TFindingKind) do
  begin
    Meta := TRuleCatalog.GetRule(K);
    Assert.AreEqual<TLeakSeverity>(
      Meta.DefaultSeverity,
      KindDefaultSeverity(K),
      Format('Severity-Drift fuer %s: JSON=%d, KIND_META=%d - ' +
             'rules/sca-rules.json oder uSCAConsts.KIND_META anpassen',
        [KindName(K), Ord(Meta.DefaultSeverity), Ord(KindDefaultSeverity(K))]));
  end;
end;

procedure TTestRuleCatalog.EveryFindingKindHasMqrMapping;
// Sonar MQR-Mode braucht pro Rule cleanCodeAttribute + Impacts. Test
// faellt sofort wenn jemand einen neuen TFindingKind hinzufuegt, ohne
// die Mapping in rules/sca-rules.json (cleanCodeAttribute + impacts)
// nachzupflegen. P1 in todo-sonar.md (Sonar Generic Issue Export)
// braucht die Felder; ohne diesen Test wuerde der Export still
// degraded fallen.
const
  ALLOWED_CCA: array[0..13] of string = (
    'FORMATTED', 'CONVENTIONAL', 'IDENTIFIABLE',
    'CLEAR', 'LOGICAL', 'COMPLETE', 'EFFICIENT',
    'FOCUSED', 'DISTINCT', 'MODULAR',
    'TESTED', 'LAWFUL', 'TRUSTWORTHY', 'RESPECTFUL'
  );
var
  K       : TFindingKind;
  Meta    : TRuleMeta;
  Valid   : Boolean;
  S       : string;
begin
  for K := Low(TFindingKind) to High(TFindingKind) do
  begin
    Meta := TRuleCatalog.GetRule(K);

    Assert.IsNotEmpty(Meta.CleanCodeAttribute,
      Format('Kind %s hat kein cleanCodeAttribute in rules/sca-rules.json',
        [KindName(K)]));

    Valid := False;
    for S in ALLOWED_CCA do
      if SameText(S, Meta.CleanCodeAttribute) then begin Valid := True; Break; end;
    Assert.IsTrue(Valid,
      Format('Kind %s hat cleanCodeAttribute "%s" - kein gueltiger Sonar-MQR-Wert',
        [KindName(K), Meta.CleanCodeAttribute]));

    Assert.IsTrue(Length(Meta.Impacts) >= 1,
      Format('Kind %s hat keinen impact-Eintrag in rules/sca-rules.json',
        [KindName(K)]));
  end;
end;

procedure TTestRuleCatalog.RuleIDsFollowConvention;
var
  K    : TFindingKind;
  Meta : TRuleMeta;
  Rx   : TRegEx;
begin
  Rx := TRegEx.Create('^SCA\d{3}$');
  for K := Low(TFindingKind) to High(TFindingKind) do
  begin
    Meta := TRuleCatalog.GetRule(K);
    Assert.IsTrue(Rx.IsMatch(Meta.ID),
      Format('Rule-ID "%s" matcht nicht SCAxxx-Konvention', [Meta.ID]));
  end;
end;

procedure TTestRuleCatalog.RuleIDsAreUnique;
var
  K    : TFindingKind;
  Meta : TRuleMeta;
  Seen : TDictionary<string, Boolean>;
begin
  Seen := TDictionary<string, Boolean>.Create;
  try
    for K := Low(TFindingKind) to High(TFindingKind) do
    begin
      Meta := TRuleCatalog.GetRule(K);
      Assert.IsFalse(Seen.ContainsKey(Meta.ID),
        Format('Doppelte Rule-ID: %s', [Meta.ID]));
      Seen.Add(Meta.ID, True);
    end;
  finally
    Seen.Free;
  end;
end;

procedure TTestRuleCatalog.KindNameMatchesCatalog;
// Catalog-JSON kind-Feld muss exakt zu KindName(K) passen, sonst stimmt
// die Zuordnung nicht.
var
  K    : TFindingKind;
  Meta : TRuleMeta;
begin
  for K := Low(TFindingKind) to High(TFindingKind) do
  begin
    Meta := TRuleCatalog.GetRule(K);
    // Meta.Kind muss bereits korrekt zum Lookup-K passen
    Assert.AreEqual(K, Meta.Kind,
      Format('Catalog-Kind %s sollte %s sein',
        [KindName(Meta.Kind), KindName(K)]));
  end;
end;

procedure TTestRuleCatalog.ToolInfoIsPopulated;
begin
  Assert.IsNotEmpty(TRuleCatalog.ToolName,
    'tool.driver.name fehlt in rules/sca-rules.json');
  Assert.IsNotEmpty(TRuleCatalog.ToolVersion,
    'tool.driver.version fehlt');
  // Uri ist optional, aber wenn vorhanden sollte sie kein Bullshit sein
end;

procedure TTestRuleCatalog.GetRuleByIDRoundtrip;
var
  K       : TFindingKind;
  M1, M2  : TRuleMeta;
  Found   : Boolean;
begin
  for K := Low(TFindingKind) to High(TFindingKind) do
  begin
    M1 := TRuleCatalog.GetRule(K);
    Found := TRuleCatalog.GetRuleByID(M1.ID, M2);
    Assert.IsTrue(Found,
      Format('GetRuleByID("%s") nicht gefunden', [M1.ID]));
    Assert.AreEqual(M1.Kind, M2.Kind,
      Format('Roundtrip Kind-Mismatch fuer %s', [M1.ID]));
  end;
end;

procedure TTestRuleCatalog.ProfileDefaultContainsAllKinds;
var
  P : TFindingKinds;
  K : TFindingKind;
begin
  P := TRuleCatalog.GetProfile('default');
  for K := Low(TFindingKind) to High(TFindingKind) do
    Assert.IsTrue(K in P,
      Format('default-Profile enthaelt %s nicht', [KindName(K)]));
end;

procedure TTestRuleCatalog.ProfileUnknownFallsBackToAll;
var
  P : TFindingKinds;
  K : TFindingKind;
begin
  // unbekannter Name -> AllKinds + OutputDebugString-Warnung; kein Crash.
  P := TRuleCatalog.GetProfile('does-not-exist-xyz');
  for K := Low(TFindingKind) to High(TFindingKind) do
    Assert.IsTrue(K in P,
      Format('Fallback fehlt %s', [KindName(K)]));
end;

procedure TTestRuleCatalog.ProfileEmptyNameReturnsAll;
var
  P : TFindingKinds;
  K : TFindingKind;
begin
  // Leerer Name = "Profile nicht gesetzt" Sentinel -> AllKinds.
  P := TRuleCatalog.GetProfile('');
  for K := Low(TFindingKind) to High(TFindingKind) do
    Assert.IsTrue(K in P,
      Format('Empty-Profile fehlt %s', [KindName(K)]));
end;

procedure TTestRuleCatalog.ProfileIdeFastExcludesHintsIncludesSecurity;
var
  P : TFindingKinds;
begin
  P := TRuleCatalog.GetProfile('ide-fast');
  // Security/Bug-Kinds muessen drin sein (sonst macht das Profile keinen Sinn).
  Assert.IsTrue(fkSQLInjection    in P, 'ide-fast: SQLInjection fehlt');
  Assert.IsTrue(fkMemoryLeak      in P, 'ide-fast: MemoryLeak fehlt');
  Assert.IsTrue(fkHardcodedSecret in P, 'ide-fast: HardcodedSecret fehlt');
  Assert.IsTrue(fkNilDeref        in P, 'ide-fast: NilDeref fehlt');
  Assert.IsTrue(fkMissingFinally  in P, 'ide-fast: MissingFinally fehlt');
  // Hint-Detektoren (Code-Smell-Rauschen) muessen draussen sein.
  Assert.IsFalse(fkLongMethod      in P, 'ide-fast: LongMethod sollte raus sein');
  Assert.IsFalse(fkMagicNumber     in P, 'ide-fast: MagicNumber sollte raus sein');
  Assert.IsFalse(fkTodoComment     in P, 'ide-fast: TodoComment sollte raus sein');
  Assert.IsFalse(fkDuplicateBlock  in P, 'ide-fast: DuplicateBlock sollte raus sein');
  Assert.IsFalse(fkEmptyMethod     in P, 'ide-fast: EmptyMethod sollte raus sein');
end;

procedure TTestRuleCatalog.ProfileNamesIncludesBundled;
var
  Names : TArray<string>;
  N     : string;
  Seen  : TDictionary<string, Boolean>;

  procedure Require(const ProfileName: string);
  begin
    Assert.IsTrue(Seen.ContainsKey(LowerCase(ProfileName)),
      Format('ProfileNames: "%s" fehlt', [ProfileName]));
  end;

begin
  Names := TRuleCatalog.ProfileNames;
  Seen  := TDictionary<string, Boolean>.Create;
  try
    for N in Names do Seen.AddOrSetValue(LowerCase(N), True);
    Require('default');
    Require('ide-fast');
    Require('strict');
    Require('security');
    Require('bugs-only');
    Require('code-quality');
    Require('dfm-only');
  finally
    Seen.Free;
  end;
end;

procedure TTestRuleCatalog.ProfileSecurityIsTightlyScoped;
var
  P : TFindingKinds;
begin
  P := TRuleCatalog.GetProfile('security');
  // Drin: nur Security-Kinds.
  Assert.IsTrue(fkSQLInjection      in P, 'security: SQLInjection fehlt');
  Assert.IsTrue(fkHardcodedSecret   in P, 'security: HardcodedSecret fehlt');
  Assert.IsTrue(fkHardcodedPath     in P, 'security: HardcodedPath fehlt');
  Assert.IsTrue(fkDfmHardcodedDbCreds in P, 'security: DfmHardcodedDbCreds fehlt');
  Assert.IsTrue(fkDfmSqlFromUserInput in P, 'security: DfmSqlFromUserInput fehlt');
  // Draussen: alles andere.
  Assert.IsFalse(fkMemoryLeak  in P, 'security: MemoryLeak sollte raus');
  Assert.IsFalse(fkLongMethod  in P, 'security: LongMethod sollte raus');
  Assert.IsFalse(fkTodoComment in P, 'security: TodoComment sollte raus');
  Assert.IsFalse(fkNilDeref    in P, 'security: NilDeref sollte raus (kein Vuln)');
end;

procedure TTestRuleCatalog.ProfileBugsOnlyExcludesSmells;
var
  P : TFindingKinds;
begin
  P := TRuleCatalog.GetProfile('bugs-only');
  // Drin: Bugs + Security (zaehlen als "echtes Problem").
  Assert.IsTrue(fkMemoryLeak    in P, 'bugs-only: MemoryLeak fehlt');
  Assert.IsTrue(fkNilDeref      in P, 'bugs-only: NilDeref fehlt');
  Assert.IsTrue(fkFormatMismatch in P, 'bugs-only: FormatMismatch fehlt');
  Assert.IsTrue(fkDivByZero     in P, 'bugs-only: DivByZero fehlt');
  Assert.IsTrue(fkSQLInjection  in P, 'bugs-only: SQLInjection fehlt');
  Assert.IsTrue(fkDfmDeadEvent  in P, 'bugs-only: DfmDeadEvent fehlt');
  // Draussen: Code Smells und Duplikate.
  Assert.IsFalse(fkLongMethod      in P, 'bugs-only: LongMethod sollte raus');
  Assert.IsFalse(fkMagicNumber     in P, 'bugs-only: MagicNumber sollte raus');
  Assert.IsFalse(fkTodoComment     in P, 'bugs-only: TodoComment sollte raus');
  Assert.IsFalse(fkDuplicateString in P, 'bugs-only: DuplicateString sollte raus');
  Assert.IsFalse(fkDuplicateBlock  in P, 'bugs-only: DuplicateBlock sollte raus');
end;

procedure TTestRuleCatalog.ProfileCodeQualityExcludesBugs;
var
  P : TFindingKinds;
begin
  P := TRuleCatalog.GetProfile('code-quality');
  // Drin: Smells + Duplikate.
  Assert.IsTrue(fkLongMethod      in P, 'code-quality: LongMethod fehlt');
  Assert.IsTrue(fkMagicNumber     in P, 'code-quality: MagicNumber fehlt');
  Assert.IsTrue(fkTodoComment     in P, 'code-quality: TodoComment fehlt');
  Assert.IsTrue(fkDuplicateBlock  in P, 'code-quality: DuplicateBlock fehlt');
  Assert.IsTrue(fkUnusedUses      in P, 'code-quality: UnusedUses fehlt');
  // Draussen: Bugs + Security.
  Assert.IsFalse(fkMemoryLeak     in P, 'code-quality: MemoryLeak sollte raus');
  Assert.IsFalse(fkNilDeref       in P, 'code-quality: NilDeref sollte raus');
  Assert.IsFalse(fkSQLInjection   in P, 'code-quality: SQLInjection sollte raus');
  Assert.IsFalse(fkHardcodedSecret in P, 'code-quality: HardcodedSecret sollte raus');
end;

procedure TTestRuleCatalog.ProfileDfmOnlyContainsOnlyDfmKinds;
var
  P     : TFindingKinds;
  K     : TFindingKind;
  IsDfm : Boolean;
begin
  P := TRuleCatalog.GetProfile('dfm-only');
  // Mindestens ein DFM-Kind muss drin sein.
  Assert.IsTrue(fkDfmDefaultName in P, 'dfm-only: DfmDefaultName fehlt');
  Assert.IsTrue(fkDfmActionMismatch in P, 'dfm-only: DfmActionMismatch fehlt');
  // ALLE Member von P muessen DFM-Kinds sein. KindName-Praefix-Test ist
  // billiger und stabiler als jeden Kind einzeln zu listen.
  for K := Low(TFindingKind) to High(TFindingKind) do
  begin
    if not (K in P) then Continue;
    IsDfm := KindName(K).StartsWith('Dfm');
    Assert.IsTrue(IsDfm,
      Format('dfm-only enthaelt Nicht-DFM-Kind "%s"', [KindName(K)]));
  end;
end;

end.
