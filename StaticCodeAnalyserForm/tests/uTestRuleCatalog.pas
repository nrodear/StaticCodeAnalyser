unit uTestRuleCatalog;

// Tests fuer TRuleCatalog (rules/sca-rules.json).
// Konsistenz-Suite: stellt sicher dass jeder TFindingKind einen Catalog-
// Eintrag hat. Wenn jemand einen neuen Detector + TFindingKind hinzufuegt
// ohne JSON zu pflegen, faellt der Test sofort auf.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.IOUtils,
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
    // Pro Kind muessen BadExample UND GoodExample befuellt sein - der
    // Fallback am Ende von uFixHint.BuildFixHint behauptet diese Garantie
    // ausdruecklich ("examples.bad/good ... existieren fuer ALLE Kinds"),
    // erzwungen hat sie bisher aber kein Test.
    [Test] procedure EveryFindingKindHasExamples;
    // ID == Ordinalzahl des Kinds. Schuetzt gegen ein Enum-Insert in der
    // MITTE von TFindingKind (verschiebt alle Folge-IDs).
    [Test] procedure RuleIDMatchesOrdinal;
    // ID-Konvention: 'SCA' + 3-stellige Nummer.
    [Test] procedure RuleIDsFollowConvention;
    // IDs muessen unique sein.
    [Test] procedure RuleIDsAreUnique;
    // name-Feld muss ueber alle Rules eindeutig sein (analog zu den IDs).
    [Test] procedure RuleNamesAreUnique;
    // shortDescription muss ueber alle Rules eindeutig sein.
    [Test] procedure ShortDescriptionsAreUnique;
    // JSON type-Feld muss zu KIND_META.FindingType passen (Gegenstueck zu
    // JsonSeverityMatchesKindMeta).
    [Test] procedure JsonTypeMatchesKindMeta;
    // Regressions-Anker 2026-07-26: Katalog-Fallback muss INHALTLICH
    // vollstaendig sein (IDE-Plugin findet die JSON oft nicht).
    [Test] procedure FallbackStillProvidesExamples;
    // Regressions-Anker 2026-08-24: der Fallback muss auch die
    // SEVERITY tragen, nicht pauschal lsWarning.
    [Test] procedure FallbackKeepsSeverityFromKindMeta;
    // Kind-Name in JSON muss zu KindName(K) matchen.
    [Test] procedure KindNameMatchesCatalog;
    // Tool-Info muss gesetzt sein (fuer SARIF tool.driver-Block).
    [Test] procedure ToolInfoIsPopulated;
    // Lookup ueber ID muss alle Kinds zurueckliefern koennen.
    [Test] procedure GetRuleByIDRoundtrip;
    // Quellstellen-Dienst (Konzept_SourceRefactor_Quellstellen Abschnitt 4):
    // anchor und fixMode sind optional, aber wenn gesetzt, nur aus der
    // bekannten Wertemenge - ein Tippfehler in der JSON darf nicht still
    // als "unbekannter Anker" durchrutschen.
    [Test] procedure AnchorAndFixModeUseKnownValues;
    // Die beiden Pilot-Regeln des Moduls tragen Anker und Politik: SCA044
    // (Zuweisung, automatisch) und SCA003 (Zuweisung oder Aufruf, nur
    // assistiert - Autopsie 7 TP / 55 FP).
    [Test] procedure RefactorPilotRulesCarryAnchorAndFixMode;
    // AH8: dieselben zwei Felder auch im FALLBACK (einkompilierte Tabelle).
    // Im IDE-Plugin ist der Fallback der Normalfall - ohne die Felder dort
    // sah reDelphix bei jeder Regel fixMode '' und bot nichts an. Seit
    // Nit 11 fuer ALLE Kinds gegen die geladene JSON verglichen.
    [Test] procedure FallbackCarriesAnchorAndFixMode;
    // Minor 40 (Review reDelphiX 2026-10-07): ein Objekt, Array oder eine
    // Zahl als anchor/fixMode darf das Laden nicht aufreissen, ein
    // unbekannter String nicht durchrutschen - beides wird leer und
    // faellt auf die einkompilierte Tabelle zurueck.
    [Test] procedure AnchorFixModeNonStringDoesNotRaise;
    // Minor 40, zweiter Teil: eine aeltere sca-rules.json OHNE die zwei
    // Felder schaltet reDelphix nicht still ab (Tabellenwert), ein
    // ausdrueckliches 'none' dagegen gilt, Gross/Klein egal.
    [Test] procedure AnchorFixModeMissingFallsBackToCompiled;

    // Profile-Loader (sca-rules.json -> profiles.*):
    //
    // VOLLSTAENDIGKEIT, seit 2026-08-02 auf 'strict' verlagert: bis dahin
    // hiess die Zusage "default enthaelt alle Kinds". Seit die sechs reinen
    // Konventions-Regeln aus 'default' in 'style' gewandert sind, stimmt
    // das nicht mehr - der SCHUTZ dahinter aber schon: kein Detektor darf
    // still verlorengehen. Die drei Tests unten sichern das jetzt
    // staerker als der eine vorher:
    //   1. 'strict' enthaelt wirklich alles,
    //   2. 'default' + 'style' ergeben zusammen wieder alles - eine Regel,
    //      die aus default faellt, MUSS in style landen,
    //   3. 'default' laesst genau die sechs weg, nicht mehr und nicht
    //      weniger (nagelt die Entscheidung fest).
    [Test] procedure ProfileStrictContainsAllKinds;
    [Test] procedure ProfileDefaultPlusStyleCoversAllKinds;
    [Test] procedure ProfileDefaultExcludesExactlyTheStyleRules;
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

    // Der Leser hinter "Importieren ..." im Profil-Fenster. Er liest
    // FREMDE Dateien - also alles, was jemand weitergibt, und nicht nur
    // das, was wir selbst schreiben.
    [Test] procedure ReadProfilesFileAcceptsFullShape;
    [Test] procedure ReadProfilesFileAcceptsBareMap;
    [Test] procedure ReadProfilesFileSkipsNonArrayValues;
    [Test] procedure ReadProfilesFileReportsMissingFile;
    // G5-4 (Review 2026-08-25): Profilnamen sind case-insensitiv. Vorher
    // war das Dictionary scharf, die Import-Vorschau unscharf - "Will be
    // overwritten" legte bei anderer Schreibweise ein Duplikat an.
    [Test] procedure ProfileNamesAreCaseInsensitive;
    // Upstream-Befund 5 (GITLAK, 28.08.)
    [Test] procedure ImpactsAsStringsDoesNotRaise;
  end;

  // Review Bereich C Engine-Kern (Blocker 2, Major 7, Minor; 2026-10-14):
  // Reload laeuft unter dem Katalog-Monitor, fixMode 'none' schaltet
  // editorHelp ab, profiles.json wird atomar geschrieben. Eigene Fixture,
  // weil TTestRuleCatalog mit 38 Tests ueber der Grenze je Fixture liegt.
  [TestFixture]
  TTestRuleCatalogGuard = class
  public
    [Test] procedure Reload_WhileWorkersRead_EveryAnswerConsistent;
    [Test] procedure FixModeNone_TurnsEditorHelpOff;
    [Test] procedure SaveUserProfile_WritesAtomically_NoTempFileLeft;
    // Der Tausch scheitert (Ziel schreibgeschuetzt): False mit Text, der
    // alte Dateiinhalt und das Profil im Speicher bleiben, und keine
    // Nachbardatei bleibt liegen (Review Woche G03-10/G03-26).
    [Test] procedure SaveUserProfile_TargetReadOnly_KeepsOldFileNoTempLeft;
  end;

  // Katalogfeld "editorHelps" (Nico 2026-10-28): die Editorhilfen einer
  // Regel je Menueeintrag, Quelle von SARIF properties.editorHelp. Dass die
  // Liste zu reDelphix passt, haelt tools/gen-quickfix-doc.py --check; hier
  // stehen Lader, Fallback und Invariante. Eigene Fixture aus demselben
  // Grund wie TTestRuleCatalogGuard.
  [TestFixture]
  TTestRuleCatalogEditorHelps = class
  public
    // SCA017 hat zwei Eintraege: 'SCA017' und 'SCA017.2', beide aendern
    // das Verhalten, Kurznamen aus dem Menuetext.
    [Test] procedure Sca017_TwoEntries_IdEffectSlug;
    // Die vier Wirkungen kommen vor: template (SCA003), depends (SCA086),
    // same und changes (SCA020 Eintrag 1 und 2).
    [Test] procedure Effects_TemplateDependsSameChanges;
    // Ueber alle Kinds: EditorHelp = (EditorHelps nicht leer), jede id
    // gehoert zur Regel ('SCAnnn', dann 'SCAnnn.2'), effect bekannt.
    [Test] procedure EveryKind_InvariantAndIdsBelongToRule;
    // Fallback (uRuleCatalogData.inc) = geladene JSON, je Kind.
    [Test] procedure Fallback_EqualsJson;
    // Lader: eine Liste aus der Datei gilt (effect Gross/klein egal);
    // unbrauchbar (kein Array, [], unbekannte Wirkung, fremde id, ':' im
    // slug) -> Tabellenwert; editorHelp false oder fixMode none -> keine
    // Hilfen.
    [Test] procedure Loader_FileWins_MalformedFallsBack_FalseClears;
  end;


implementation

uses
  System.Generics.Collections, System.RegularExpressions,
  System.JSON;   // AnchorAndFixModeUseKnownValues liest die rohe Datei

// Profilnamen als Konstanten. Nicht aus Ordnungsliebe: mit den drei neuen
// Profil-Tests stand 'default' dreimal woertlich im Code, und der eigene
// Analyser meldet ab drei Vorkommen DuplicateString - zu Recht, und das
// Dogfooding-Gate hat es gefangen, bevor es jemand anders tat. Nur die drei
// Namen, die die Schwelle reissen; die uebrigen Profile stehen zweimal und
// bleiben woertlich.
//
// Der const-Block steht bewusst NACH der uses-Klausel: in Delphi muss uses
// unmittelbar auf implementation folgen, sonst E2029. Genau dieser Fehler
// ist in dieser Codebasis schon einmal passiert.
const
  PROF_DEFAULT = 'default';
  PROF_STRICT  = 'strict';
  PROF_STYLE   = 'style';

function NachbarDateienVon(const APfad: string): Integer;
// Zahl der liegengebliebenen Nachbardateien von APfad ('<Datei>*.tmp'):
// trifft den alten festen Namen '<Datei>.tmp' ebenso wie den je Prozess
// ('<Datei>.<pid>.tmp') - der Test haengt nicht an der Namensbildung.
begin
  Result := Length(TDirectory.GetFiles(ExtractFilePath(APfad),
    ExtractFileName(APfad) + '*.tmp'));
end;

procedure LoescheNachbarDateien(const APfad: string);
var
  Datei : string;
begin
  for Datei in TDirectory.GetFiles(ExtractFilePath(APfad),
                 ExtractFileName(APfad) + '*.tmp') do
    System.SysUtils.DeleteFile(Datei);
end;

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
    Meta := TRuleCatalog.GetRuleCanonical(K);
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
    Meta := TRuleCatalog.GetRuleCanonical(K);
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
    Meta := TRuleCatalog.GetRuleCanonical(K);
    Assert.AreEqual<TLeakSeverity>(
      Meta.DefaultSeverity,
      KindDefaultSeverity(K),
      Format('Severity-Drift fuer %s: JSON=%d, KIND_META=%d - ' +
             'rules/sca-rules.json oder uSCAConsts.KIND_META anpassen',
        [KindName(K), Ord(Meta.DefaultSeverity), Ord(KindDefaultSeverity(K))]));
  end;
end;

procedure TTestRuleCatalog.JsonTypeMatchesKindMeta;
// Gegenstueck zu JsonSeverityMatchesKindMeta, nur fuer das type-Feld:
// JSON type == KIND_META.FindingType. Die Kategorie steuert den
// Sonar-/SARIF-Export und die UI-Gruppierung; driftet sie, sehen User
// denselben Befund in der IDE als Bug und im CI-Report als Code Smell.
// Zusatznutzen: ParseFindingType (uRuleCatalog) faellt bei unbekannter
// Schreibweise still auf ftCodeSmell zurueck - ein Tippfehler im
// type-Feld einer Bug-/Vulnerability-Rule wird damit hier sichtbar,
// statt lautlos zum Code Smell zu werden.
var
  K    : TFindingKind;
  Meta : TRuleMeta;
begin
  for K := Low(TFindingKind) to High(TFindingKind) do
  begin
    Meta := TRuleCatalog.GetRuleCanonical(K);
    Assert.AreEqual<TFindingType>(
      Meta.FindingType,
      KindFindingType(K),
      Format('FindingType-Drift fuer %s: JSON=%d, KIND_META=%d - ' +
             'rules/sca-rules.json type-Feld oder uSCAConsts.KIND_META anpassen',
        [KindName(K), Ord(Meta.FindingType), Ord(KindFindingType(K))]));
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
    Meta := TRuleCatalog.GetRuleCanonical(K);

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

procedure TTestRuleCatalog.EveryFindingKindHasExamples;
// Pro Kind muessen examples.bad UND examples.good in
// rules/sca-rules.json stehen und echten Inhalt haben.
//
// Warum das ein eigener Test ist: der Fallback am Ende von
// uFixHint.BuildFixHint (Checklist-Drift-Fix 2026-07-24) setzt
// Before/After direkt aus Meta.BadExample/Meta.GoodExample und
// kommentiert dazu, examples.bad/good existierten fuer ALLE Kinds.
// Erzwungen hat das bisher nichts - EveryFindingKindHasRichMetadata
// prueft nur Name/ShortDescription/DetectorUnit. Ein neuer Detektor
// ohne examples-Block haette also stumm einen Fix-Hint mit leerem
// Before/After produziert.
//
// Platzhalter-Guard: geprueft wird, ob das GANZE Feld nur aus einem
// Stub-Token besteht ('TBD', 'TODO', '...', 'xxx', 'n/a', '-'),
// optional hinter einem //-Kommentarmarker. Ein Substring-Test waere
// hier falsch und wuerde vier legitime Beispiele rot faerben:
// SCA019 (TodoComment) demonstriert im Bad-Example eine echte
// TODO-Zeile, SCA070 (CommentedOutCode) im Good-Example ebenso,
// SCA179 (AttributeIgnoreWithoutReason) zeigt ein Ignore-Attribut mit
// 'TBD ticket #1234', und SCA021 (DuplicateBlock) nennt im
// Good-Example eine 'ValidateXxx'-Prozedur.
const
  PLACEHOLDERS: array[0..5] of string = (
    'TBD', 'TODO', '...', 'xxx', 'n/a', '-'
  );
var
  K    : TFindingKind;
  Meta : TRuleMeta;

  function IsPlaceholder(const S: string): Boolean;
  var
    T : string;
    P : string;
  begin
    Result := True;
    T := Trim(S);
    // fuehrende Kommentarmarker abstreifen - '// TBD' ist genauso ein Stub
    while T.StartsWith('//') do
      T := Trim(T.Substring(2));
    if T = '' then Exit;
    for P in PLACEHOLDERS do
      if SameText(P, T) then Exit;
    Result := False;
  end;

begin
  for K := Low(TFindingKind) to High(TFindingKind) do
  begin
    Meta := TRuleCatalog.GetRuleCanonical(K);

    Assert.IsNotEmpty(Meta.BadExample,
      Format('Kind %s (%s) hat kein examples.bad in rules/sca-rules.json - ' +
             'uFixHint-Fallback liefert dann einen leeren Before-Block',
        [KindName(K), Meta.ID]));
    Assert.IsNotEmpty(Meta.GoodExample,
      Format('Kind %s (%s) hat kein examples.good in rules/sca-rules.json - ' +
             'uFixHint-Fallback liefert dann einen leeren After-Block',
        [KindName(K), Meta.ID]));

    Assert.IsFalse(IsPlaceholder(Meta.BadExample),
      Format('Kind %s (%s): examples.bad ist ein Platzhalter ("%s")',
        [KindName(K), Meta.ID, Meta.BadExample]));
    Assert.IsFalse(IsPlaceholder(Meta.GoodExample),
      Format('Kind %s (%s): examples.good ist ein Platzhalter ("%s")',
        [KindName(K), Meta.ID, Meta.GoodExample]));
  end;
end;

procedure TTestRuleCatalog.RuleIDMatchesOrdinal;
// Strenger als RuleIDsFollowConvention: die ID MUSS die 1-basierte
// Ordinalzahl des Kinds sein (fkMemoryLeak = Ord 0 -> 'SCA001').
//
// Schutzzweck: wird ein neuer TFindingKind in der MITTE des Enums
// eingefuegt (statt am Ende), verschieben sich alle Folge-IDs um eins.
// KIND_META, sca-rules.json und die Detektoren wandern in dem Fall
// mit - die gesamte Doku, alle Baselines, gespeicherte
// Suppression-Marker und jeder extern archivierte SARIF-Report zeigen
// danach aber auf die falsche Regel, ohne dass irgendein Bestandstest
// rot wird (Uniqueness + SCAxxx-Konvention bleiben ja erfuellt).
var
  K        : TFindingKind;
  Meta     : TRuleMeta;
  Expected : string;
begin
  for K := Low(TFindingKind) to High(TFindingKind) do
  begin
    Meta     := TRuleCatalog.GetRuleCanonical(K);
    Expected := Format('SCA%.3d', [Ord(K) + 1]);
    Assert.AreEqual(Expected, Meta.ID,
      Format('Kind %s (Ordinal %d) hat ID "%s", erwartet "%s" - neuer ' +
             'TFindingKind in der Mitte des Enums eingefuegt? Neue Kinds ' +
             'gehoeren ans ENDE von TFindingKind',
        [KindName(K), Ord(K), Meta.ID, Expected]));
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
    Meta := TRuleCatalog.GetRuleCanonical(K);
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
      Meta := TRuleCatalog.GetRuleCanonical(K);
      Assert.IsFalse(Seen.ContainsKey(Meta.ID),
        Format('Doppelte Rule-ID: %s', [Meta.ID]));
      Seen.Add(Meta.ID, True);
    end;
  finally
    Seen.Free;
  end;
end;

procedure TTestRuleCatalog.RuleNamesAreUnique;
// Das name-Feld ist der Titel, den User in IDE-Liste, HTML-Report und
// SARIF-Rule-Block sehen. Zwei Rules mit identischem Namen sind dort
// nicht auseinanderzuhalten - "welche der beiden Regeln hat gefeuert?"
// laesst sich nur noch ueber die ID beantworten, die im HTML-Report
// aber nicht immer mitlaeuft. Verglichen wird case-insensitiv: eine
// Kollision, die sich nur in der Gross-/Kleinschreibung unterscheidet,
// ist fuer den Leser genauso eine Dublette.
var
  K     : TFindingKind;
  Meta  : TRuleMeta;
  Owner : string;
  Seen  : TDictionary<string, string>; // LowerCase(Name) -> erste Rule-ID
begin
  Seen := TDictionary<string, string>.Create;
  try
    for K := Low(TFindingKind) to High(TFindingKind) do
    begin
      Meta := TRuleCatalog.GetRuleCanonical(K);
      if Seen.TryGetValue(LowerCase(Trim(Meta.Name)), Owner) then
        Assert.Fail(
          Format('Doppelter Rule-Name "%s": %s und %s - ' +
                 'name in rules/sca-rules.json eindeutig machen',
            [Meta.Name, Owner, Meta.ID]));
      Seen.Add(LowerCase(Trim(Meta.Name)), Meta.ID);
    end;
    // Abschluss-Assertion (DUnitX 'No assertions were made'): der
    // Kollisionszweig oben feuert im Gutfall NIE, daher hier ein
    // positiver Nachweis - er belegt zugleich, dass wirklich JEDES
    // Kind eingetragen wurde (Seen.Count == Anzahl Kinds; ein
    // Duplikat haette die Zahl gesenkt, ohne den Zweig zu treffen,
    // falls dieser je umgebaut wird).
    Assert.AreEqual<Integer>(
      Ord(High(TFindingKind)) - Ord(Low(TFindingKind)) + 1, Seen.Count,
      'Es wurden nicht alle Rule-Namen geprueft - erwartet je Kind ' +
      'einen Eintrag (Feld name aus rules/sca-rules.json)');
  finally
    Seen.Free;
  end;
end;

procedure TTestRuleCatalog.ShortDescriptionsAreUnique;
// shortDescription ist die einzeilige Erklaerung in Tooltip, Fix-Hint
// (uFixHint-Fallback setzt Description daraus) und SARIF. Aktuell sind
// alle 194 sauber verschieden - dieser Test friert den Zustand ein,
// damit eine per Copy&Paste angelegte neue Rule nicht mit dem Text
// ihrer Vorlage stehen bleibt. Case-insensitiv, gleiche Begruendung
// wie bei RuleNamesAreUnique.
var
  K     : TFindingKind;
  Meta  : TRuleMeta;
  Owner : string;
  Seen  : TDictionary<string, string>; // LowerCase(Desc) -> erste Rule-ID
begin
  Seen := TDictionary<string, string>.Create;
  try
    for K := Low(TFindingKind) to High(TFindingKind) do
    begin
      Meta := TRuleCatalog.GetRuleCanonical(K);
      if Seen.TryGetValue(LowerCase(Trim(Meta.ShortDescription)), Owner) then
        Assert.Fail(
          Format('Doppelte shortDescription "%s": %s und %s - ' +
                 'Copy&Paste beim Anlegen der neuen Rule?',
            [Meta.ShortDescription, Owner, Meta.ID]));
      Seen.Add(LowerCase(Trim(Meta.ShortDescription)), Meta.ID);
    end;
    // Abschluss-Assertion (DUnitX 'No assertions were made'): der
    // Kollisionszweig oben feuert im Gutfall NIE, daher hier ein
    // positiver Nachweis - er belegt zugleich, dass wirklich JEDES
    // Kind eingetragen wurde (Seen.Count == Anzahl Kinds; ein
    // Duplikat haette die Zahl gesenkt, ohne den Zweig zu treffen,
    // falls dieser je umgebaut wird).
    Assert.AreEqual<Integer>(
      Ord(High(TFindingKind)) - Ord(Low(TFindingKind)) + 1, Seen.Count,
      'Es wurden nicht alle shortDescriptions geprueft - erwartet je Kind ' +
      'einen Eintrag (Feld shortDescription aus rules/sca-rules.json)');
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
    Meta := TRuleCatalog.GetRuleCanonical(K);
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
    M1 := TRuleCatalog.GetRuleCanonical(K);
    Found := TRuleCatalog.GetRuleByIDCanonical(M1.ID, M2);
    Assert.IsTrue(Found,
      Format('GetRuleByID("%s") nicht gefunden', [M1.ID]));
    Assert.AreEqual(M1.Kind, M2.Kind,
      Format('Roundtrip Kind-Mismatch fuer %s', [M1.ID]));
  end;
end;

procedure TTestRuleCatalog.ProfileStrictContainsAllKinds;
// 'strict' ist seit 2026-08-02 das Profil, das "wirklich alles" bedeutet.
// Hier haengt die Vollstaendigkeits-Zusage: faellt ein Detektor aus dem
// Katalog oder aus allen Profilen, schlaegt DIESER Test an.
var
  P : TFindingKinds;
  K : TFindingKind;
begin
  P := TRuleCatalog.GetProfile(PROF_STRICT);
  for K := Low(TFindingKind) to High(TFindingKind) do
    Assert.IsTrue(K in P,
      Format('strict-Profile enthaelt %s nicht', [KindName(K)]));
end;

procedure TTestRuleCatalog.ProfileDefaultPlusStyleCoversAllKinds;
// Kein Detektor darf zwischen den beiden Profilen durchfallen. Wer eine
// Regel aus 'default' nimmt, muss sie in 'style' auffangen - sonst waere
// sie ohne 'strict' gar nicht mehr erreichbar.
var
  D, S : TFindingKinds;
  K    : TFindingKind;
begin
  D := TRuleCatalog.GetProfile(PROF_DEFAULT);
  S := TRuleCatalog.GetProfile(PROF_STYLE);
  for K := Low(TFindingKind) to High(TFindingKind) do
    Assert.IsTrue((K in D) or (K in S),
      Format('%s ist weder in default noch in style - Regel verloren',
             [KindName(K)]));
end;

procedure TTestRuleCatalog.ProfileDefaultExcludesExactlyTheStyleRules;
// Nagelt die Entscheidung fest (C1, 2026-08-02; SCA099 nachgezogen am
// 2026-08-03; SCA204 FunctionNameAsResult am 2026-10-25, Nico: "Stil
// entscheidet das Team-Profil"): genau diese acht reinen Konventions-Regeln
// sind aus 'default' raus - die ersten sieben zusammen 48,1 % aller Funde
// auf dem Referenzkorpus. Nicht mehr und nicht weniger; jede spaetere
// stille Erweiterung der Liste faellt hier auf.
const
  EXPECTED : array[0..7] of string = (
    'PublicMemberWithoutDoc', 'NilComparison', 'BeginEndRequired',
    'WithStatement', 'ClassPerFile', 'DfmHardcodedCaption',
    'IfElseBegin', 'FunctionNameAsResult');
var
  D     : TFindingKinds;
  K     : TFindingKind;
  N, E  : string;
  Miss  : Integer;
  Known : Boolean;
begin
  D := TRuleCatalog.GetProfile(PROF_DEFAULT);
  Miss := 0;
  for K := Low(TFindingKind) to High(TFindingKind) do
  begin
    if K in D then Continue;
    Inc(Miss);
    N := KindName(K);
    // Bewusst eine Schleife statt TArray.IndexOf: EXPECTED ist ein
    // STATISCHES Array und laesst sich nicht ohne Kopie als dynamisches
    // uebergeben.
    Known := False;
    for E in EXPECTED do
      if SameText(E, N) then
      begin
        Known := True;
        Break;
      end;
    Assert.IsTrue(Known,
      Format('%s fehlt in default, steht aber nicht auf der beschlossenen '
           + 'Liste - stille Verkleinerung?', [N]));
  end;
  Assert.AreEqual<Integer>(Length(EXPECTED), Miss,
    'default muss GENAU die acht beschlossenen Regeln weglassen');
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
    Require(PROF_DEFAULT);
    Require('ide-fast');
    Require(PROF_STRICT);
    Require('security');
    Require('bugs-only');
    Require('code-quality');
    Require('dfm-only');
    Require(PROF_STYLE); // seit C1 2026-08-02
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
  Assert.IsTrue(fkHardcodedIpAddress  in P, 'security: HardcodedIpAddress fehlt');
  Assert.IsTrue(fkHardcodedIpInConfig in P, 'security: HardcodedIpInConfig fehlt');
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
  Assert.IsTrue(fkComparisonPrecedence in P, 'bugs-only: ComparisonPrecedence fehlt');
  Assert.IsTrue(fkLoopPastHighBound in P, 'bugs-only: LoopPastHighBound fehlt');
  Assert.IsTrue(fkFunctionNameRecursion in P, 'bugs-only: FunctionNameRecursion fehlt');
  // Draussen: Code Smells und Duplikate.
  Assert.IsFalse(fkLongMethod      in P, 'bugs-only: LongMethod sollte raus');
  Assert.IsFalse(fkMagicNumber     in P, 'bugs-only: MagicNumber sollte raus');
  Assert.IsFalse(fkTodoComment     in P, 'bugs-only: TodoComment sollte raus');
  Assert.IsFalse(fkDuplicateString in P, 'bugs-only: DuplicateString sollte raus');
  Assert.IsFalse(fkDuplicateBlock  in P, 'bugs-only: DuplicateBlock sollte raus');
  // SCA204 ist Stil (Hint), SCA205 aus derselben Unit der Bug.
  Assert.IsFalse(fkFunctionNameAsResult in P, 'bugs-only: FunctionNameAsResult sollte raus');
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

procedure TTestRuleCatalog.FallbackStillProvidesExamples;
// ROOT-CAUSE-ANKER (2026-07-26): 19 Kinds (SCA167-SCA184, SCA194 - u.a.
// SCA176 CognitiveComplexity) haben KEINEN Hand-Branch in uFixHint und
// beziehen ihren Vorher/Nachher-Hinweis ausschliesslich ueber den Katalog.
// Findet TRuleCatalog rules/sca-rules.json zur Laufzeit nicht (im IDE-Plugin
// der Normalfall: BPL im Embarcadero-BPL-Verzeichnis, Repo auf anderem
// Laufwerk), griff LoadFallback - und liess Bad/GoodExample LEER. Seit der
// einkompilierten Tabelle (uRuleCatalogData.inc) darf das nicht mehr sein.
// Der Fallback wird hier erzwungen, indem eine KAPUTTE JSON untergeschoben
// wird (Datei existiert -> Pfadsuche nimmt sie -> Parser scheitert ->
// LoadFallback).
var
  TmpFile : string;
  OldPath : string;
  Meta    : TRuleMeta;
  K       : TFindingKind;
  Leer    : Integer;
begin
  OldPath := TRuleCatalog.JsonFilePath;
  TmpFile := TPath.Combine(TPath.GetTempPath,
    'sca_broken_rules_' + TGuid.NewGuid.ToString.Replace('{', '').Replace('}', '') + '.json');
  TFile.WriteAllText(TmpFile, '{ das ist kein gueltiger Regelkatalog');
  try
    TRuleCatalog.JsonFilePath := TmpFile;
    TRuleCatalog.Reload;

    // Stellvertretend der gemeldete Fall - und danach ALLE Kinds.
    Meta := TRuleCatalog.GetRuleCanonical(fkCognitiveComplexity);
    Assert.IsNotEmpty(Meta.BadExample,
      'SCA176: BadExample fehlt im Fallback - im IDE-Plugin sieht der User dann keinen Vorher-Block');
    Assert.IsNotEmpty(Meta.GoodExample,
      'SCA176: GoodExample fehlt im Fallback');
    Assert.IsNotEmpty(Meta.ShortDescription,
      'SCA176: ShortDescription fehlt im Fallback');

    Leer := 0;
    for K := Low(TFindingKind) to High(TFindingKind) do
    begin
      Meta := TRuleCatalog.GetRuleCanonical(K);
      if (Meta.BadExample = '') or (Meta.GoodExample = '') then Inc(Leer);
    end;
    Assert.AreEqual<Integer>(0, Leer,
      'Kinds ohne Beispiel im Fallback (erwartet 0) - uRuleCatalogData.inc regenerieren');
  finally
    TRuleCatalog.JsonFilePath := OldPath;
    TRuleCatalog.Reload;   // echten Katalog fuer die Folgetests wiederherstellen
    if TFile.Exists(TmpFile) then TFile.Delete(TmpFile);
  end;
end;

procedure TTestRuleCatalog.FallbackKeepsSeverityFromKindMeta;
// ROOT-CAUSE-ANKER (2026-08-24): MakeFallbackMeta setzte
// DefaultSeverity pauschal auf lsWarning, waehrend es den FindingType
// eine Zeile weiter korrekt aus KIND_META zog. Im IDE-Plugin ist der
// Fallback der Normalfall (BPL im Embarcadero-Verzeichnis, JSON
// unerreichbar), also zeigte das Profil-Fenster dort bei JEDER Regel
// "Warning" - die Standalone dagegen Error/Warning/Hint. Aufgefallen
// ist es am Vergleich der beiden Oberflaechen.
//
// Der Fallback wird wie im Test darueber erzwungen: eine KAPUTTE JSON
// unterschieben, damit die Pfadsuche sie nimmt und der Parser scheitert.
var
  TmpFile : string;
  OldPath : string;
  Meta    : TRuleMeta;
  K       : TFindingKind;
  Falsch  : Integer;
  Nur1    : Boolean;
  Erste   : TLeakSeverity;
begin
  OldPath := TRuleCatalog.JsonFilePath;
  TmpFile := TPath.Combine(TPath.GetTempPath,
    'sca_broken_sev_' + TGuid.NewGuid.ToString.Replace('{', '').Replace('}', '') + '.json');
  TFile.WriteAllText(TmpFile, '{ das ist kein gueltiger Regelkatalog');
  try
    TRuleCatalog.JsonFilePath := TmpFile;
    TRuleCatalog.Reload;

    // Stellvertretend der Fall, an dem es aufgefallen ist: SCA001
    // MemoryLeak ist in KIND_META lsError, nicht lsWarning.
    Meta := TRuleCatalog.GetRuleCanonical(fkMemoryLeak);
    Assert.AreEqual<TLeakSeverity>(KindDefaultSeverity(fkMemoryLeak),
      Meta.DefaultSeverity,
      'SCA001: Fallback-Severity weicht von KIND_META ab');

    // Und ueber ALLE Kinds: keine einzige Abweichung.
    Falsch := 0;
    for K := Low(TFindingKind) to High(TFindingKind) do
    begin
      Meta := TRuleCatalog.GetRuleCanonical(K);
      if Meta.DefaultSeverity <> KindDefaultSeverity(K) then Inc(Falsch);
    end;
    Assert.AreEqual<Integer>(0, Falsch,
      'Kinds mit falscher Severity im Fallback (erwartet 0)');

    // Gegenprobe gegen einen Test, der nichts prueft: waeren alle Kinds
    // in KIND_META gleich schwer, wuerde die Schleife oben auch bei
    // einem pauschalen Wert gruen. Sie sind es nicht - und genau das
    // sichert diese Zusicherung ab.
    Erste := KindDefaultSeverity(Low(TFindingKind));
    Nur1  := True;
    for K := Low(TFindingKind) to High(TFindingKind) do
      if KindDefaultSeverity(K) <> Erste then
      begin
        Nur1 := False;
        Break;
      end;
    Assert.IsFalse(Nur1,
      'KIND_META fuehrt nur noch EINE Severity - dieser Test kann den ' +
      'Fehler dann nicht mehr entdecken');
  finally
    TRuleCatalog.JsonFilePath := OldPath;
    TRuleCatalog.Reload;   // echten Katalog fuer die Folgetests wiederherstellen
    if TFile.Exists(TmpFile) then TFile.Delete(TmpFile);
  end;
end;

{ ---- TRuleCatalog.ReadProfilesFile ---------------------------------- }

function SchreibeTempJson(const AInhalt: string): string;
// Eigener Dateiname je Aufruf: die Tests duerfen in beliebiger
// Reihenfolge und parallel laufen.
begin
  Result := TPath.Combine(TPath.GetTempPath, 'sca_profiles_' +
    TGuid.NewGuid.ToString.Replace('{', '').Replace('}', '') + '.json');
  TFile.WriteAllText(Result, AInhalt, TEncoding.UTF8);
end;

procedure TTestRuleCatalog.ReadProfilesFileAcceptsFullShape;
// Die Form, die das Profil-Fenster selbst schreibt.
var
  Datei  : string;
  Ziel   : TDictionary<string, TFindingKinds>;
  Fehler : string;
begin
  Datei := SchreibeTempJson(
    '{ "version": 1, "profiles": { "team-a": ["MemoryLeak", "SQLInjection"] } }');
  Ziel := TDictionary<string, TFindingKinds>.Create;
  try
    Assert.IsTrue(TRuleCatalog.ReadProfilesFile(Datei, Ziel, Fehler),
      'Vollform nicht gelesen: ' + Fehler);
    Assert.AreEqual<Integer>(1, Ziel.Count, 'genau ein Profil erwartet');
    Assert.IsTrue(Ziel.ContainsKey('team-a'), 'Profilname fehlt');
    Assert.IsTrue(fkMemoryLeak in Ziel['team-a'], 'MemoryLeak fehlt');
    Assert.IsTrue(fkSQLInjection in Ziel['team-a'], 'SQLInjection fehlt');
  finally
    Ziel.Free;
    if TFile.Exists(Datei) then TFile.Delete(Datei);
  end;
end;

procedure TTestRuleCatalog.ReadProfilesFileAcceptsBareMap;
// Die Form, in der ein Regelwerk oft von Hand weitergereicht wird: nur
// die Abbildung, ohne den "profiles"-Rahmen. Wer sie ablehnt, zwingt den
// Anwender, eine Datei zu reparieren, die er nicht geschrieben hat.
var
  Datei  : string;
  Ziel   : TDictionary<string, TFindingKinds>;
  Fehler : string;
begin
  Datei := SchreibeTempJson('{ "nur-lecks": ["MemoryLeak"] }');
  Ziel := TDictionary<string, TFindingKinds>.Create;
  try
    Assert.IsTrue(TRuleCatalog.ReadProfilesFile(Datei, Ziel, Fehler),
      'blosse Abbildung nicht gelesen: ' + Fehler);
    Assert.AreEqual<Integer>(1, Ziel.Count, 'genau ein Profil erwartet');
    Assert.IsTrue(fkMemoryLeak in Ziel['nur-lecks'], 'MemoryLeak fehlt');
  finally
    Ziel.Free;
    if TFile.Exists(Datei) then TFile.Delete(Datei);
  end;
end;

procedure TTestRuleCatalog.ReadProfilesFileSkipsNonArrayValues;
// Schuetzt vor der wahrscheinlichsten Fehlbedienung: im Dateidialog
// sca-rules.json statt profiles.json erwischt. Dessen Wurzel hat
// Schluessel wie "version" und "rules" - keiner davon ist eine
// Token-Liste. Erwartet wird "nichts gefunden", nicht "Unsinn geladen".
var
  Datei  : string;
  Ziel   : TDictionary<string, TFindingKinds>;
  Fehler : string;
begin
  Datei := SchreibeTempJson(
    '{ "version": 1, "tool": "sca", "rules": [ { "id": "SCA001" } ] }');
  Ziel := TDictionary<string, TFindingKinds>.Create;
  try
    Assert.IsTrue(TRuleCatalog.ReadProfilesFile(Datei, Ziel, Fehler),
      'gueltiges JSON darf keinen Fehler geben: ' + Fehler);
    Assert.AreEqual<Integer>(0, Ziel.Count,
      'aus einem Regelkatalog darf kein Profil entstehen');
  finally
    Ziel.Free;
    if TFile.Exists(Datei) then TFile.Delete(Datei);
  end;
end;

procedure TTestRuleCatalog.ReadProfilesFileReportsMissingFile;
// Der Unterschied zu LoadUserProfiles: dort ist eine fehlende Datei der
// Normalfall und schweigt. Hier hat jemand aktiv eine Datei ausgewaehlt -
// dann muss ein Fehlschlag auch einen Text mitbringen, sonst steht der
// Anwender vor einem Fenster, das nichts sagt und nichts tut.
var
  Ziel   : TDictionary<string, TFindingKinds>;
  Fehler : string;
begin
  Ziel := TDictionary<string, TFindingKinds>.Create;
  try
    Assert.IsFalse(TRuleCatalog.ReadProfilesFile(
      TPath.Combine(TPath.GetTempPath, 'sca_gibt_es_nicht_4711.json'),
      Ziel, Fehler), 'fehlende Datei muss False liefern');
    Assert.IsNotEmpty(Fehler, 'ohne Fehlertext kann die Oberflaeche nichts melden');
  finally
    Ziel.Free;
  end;
end;


procedure TTestRuleCatalog.ProfileNamesAreCaseInsensitive;
var
  Err     : string;
  AltPfad : string;
  TmpPfad : string;
begin
  // Ablageort auf eine TEMP-Datei umbiegen - dafuer existiert der
  // Test-Hook UserProfilesPath. Ohne ihn schrieb dieser Test in die
  // ECHTE %APPDATA%-profiles.json des Entwicklers (finales Review, R8);
  // die Schreibpfade (SaveUserProfile/DeleteUserProfile) benutzen den
  // Pfad live, ein Reload ist nicht noetig.
  AltPfad := TRuleCatalog.UserProfilesPath;
  TmpPfad := TPath.Combine(TPath.GetTempPath, 'sca_test_profiles_' +
    TGuid.NewGuid.ToString.Replace('{', '').Replace('}', '') + '.json');
  TRuleCatalog.UserProfilesPath := TmpPfad;
  // Aufraeumen von frueheren Laeufen, dann anlegen und anders
  // kapitalisiert wiederfinden, aendern und loeschen.
  TRuleCatalog.DeleteUserProfile('case-probe', Err);
  try
    Assert.IsTrue(TRuleCatalog.SaveUserProfile('Case-Probe',
      [fkMemoryLeak], Err), 'Anlegen: ' + Err);
    Assert.IsTrue(fkMemoryLeak in TRuleCatalog.GetProfile('CASE-PROBE'),
      'GetProfile muss die andere Schreibweise treffen');
    Assert.IsFalse(TRuleCatalog.GetProfile('case-probe') = [],
      'kleingeschrieben ebenso');
    // Ueberschreiben unter anderer Schreibweise erzeugt KEIN Duplikat.
    Assert.IsTrue(TRuleCatalog.SaveUserProfile('CASE-probe',
      [fkEmptyExcept], Err), 'Aendern: ' + Err);
    Assert.IsTrue(fkEmptyExcept in TRuleCatalog.GetProfile('Case-Probe'),
      'die Aenderung muss dasselbe Profil getroffen haben');
    Assert.IsFalse(fkMemoryLeak in TRuleCatalog.GetProfile('Case-Probe'),
      'kein zweites Profil unter alter Schreibweise');
  finally
    TRuleCatalog.DeleteUserProfile('case-probe', Err);
    TRuleCatalog.UserProfilesPath := AltPfad;
    if TFile.Exists(TmpPfad) then TFile.Delete(TmpPfad);
  end;
end;

procedure TTestRuleCatalog.ImpactsAsStringsDoesNotRaise;
// UPSTREAM-BEFUND 5 (GITLAK): der Guard "if IObj = nil then Continue"
// hinter einem as-Cast konnte nie greifen - as liefert nie nil, es
// wirft EInvalidCast. Eine handgepflegte sca-rules.json mit
// "impacts": ["high"] (Strings statt Objekte, etwa aus einem neueren
// Schema) riss damit EnsureLoaded auf, ueber GetRule und
// ResolvedRuleId bis in jeden Exporter: der Lauf starb beim EXPORT,
// nach getaner Analyse.
//
// Setup ruft Reload, der globale Katalogzustand ist danach wieder der
// echte - deshalb darf dieser Test eine eigene Datei laden.
var
  Pfad    : string;
  AltPfad : string;
begin
  // LoadFromJsonFile ist privat - der Weg von aussen fuehrt ueber
  // JsonFilePath + Reload, dasselbe Muster wie beim Profil-Test weiter
  // unten mit UserProfilesPath.
  Pfad    := TPath.Combine(TPath.GetTempPath,
                           'sca-rules-impacts-test.json');
  AltPfad := TRuleCatalog.JsonFilePath;
  try
    TFile.WriteAllText(Pfad, '{"rules":[{"id":"SCA001","kind":"MemoryLeak","name":"n","shortDescription":"s","fullDescription":"f","defaultSeverity":"Error","type":"Bug","impacts":["high"]}]}');
    TRuleCatalog.JsonFilePath := Pfad;
    // Wirft das Laden, faellt der Test mit genau dieser Exception -
    // vor dem Fix war es EInvalidCast.
    TRuleCatalog.Reload;
    Assert.IsTrue(TRuleCatalog.GetRuleCanonical(fkMemoryLeak).ID <> '',
      'der Katalog ist geladen, nicht auf halber Strecke gestorben');
  finally
    TRuleCatalog.JsonFilePath := AltPfad;
    if TFile.Exists(Pfad) then TFile.Delete(Pfad);
    TRuleCatalog.Reload;   // echten Katalog wiederherstellen
  end;
end;

{ ---- Quellstellen-Dienst: anchor / fixMode ---- }

procedure TTestRuleCatalog.AnchorAndFixModeUseKnownValues;
// Seit Minor 40 (Review reDelphiX 2026-10-07) macht der Lader aus einem
// unbekannten Wert leer und fuellt ihn aus der einkompilierten Tabelle.
// Ueber GetRuleCanonical saehe dieser Test einen Tippfehler in der JSON
// also nie mehr - deshalb prueft er zuerst die ROHE Datei, aus der der
// Katalog geladen wurde, und zwar so streng wie das Schema-enum: nur
// Strings, Gross/Klein zaehlt. Danach den Vertrag des Laders.
const
  ANCHORS   : array[0..4] of string = ('statement', 'assign', 'call',
    'assign-or-call', 'uses-item');
  FIX_MODES : array[0..2] of string = ('none', 'assisted', 'auto');

  function InList(const AValue: string; const AList: array of string): Boolean;
  var
    i : Integer;
  begin
    Result := False;
    for i := Low(AList) to High(AList) do
      if AList[i] = AValue then
        Exit(True);
  end;

  procedure PruefeRoh(ARegel: TJSONObject; const AFeld: string;
    const AList: array of string);
  var
    V : TJSONValue;
  begin
    V := ARegel.FindValue(AFeld);
    if V = nil then Exit;   // optional
    Assert.IsTrue((V is TJSONString) and InList(V.Value, AList),
      ARegel.GetValue<string>('id', '?') + ': unbekannter ' + AFeld + ' ' +
      V.ToString + ' in rules/sca-rules.json');
  end;

var
  K      : TFindingKind;
  Meta   : TRuleMeta;
  Pfad   : string;
  Json   : TJSONValue;
  Regeln : TJSONValue;
  i      : Integer;
begin
  // 1. Die rohe Datei - dort entsteht ein Tippfehler.
  Pfad := TRuleCatalog.ResolvedJsonPath;
  Assert.IsNotEmpty(Pfad,
    'rules/sca-rules.json nicht gefunden - die Rohpruefung braucht die Datei');
  Json := TJSONObject.ParseJSONValue(TFile.ReadAllText(Pfad, TEncoding.UTF8));
  try
    Assert.IsTrue(Json is TJSONObject, Pfad + ' ist kein JSON-Objekt');
    Regeln := TJSONObject(Json).FindValue('rules');
    Assert.IsTrue(Regeln is TJSONArray, Pfad + ' ohne rules-Array');
    for i := 0 to TJSONArray(Regeln).Count - 1 do
      if TJSONArray(Regeln).Items[i] is TJSONObject then
      begin
        PruefeRoh(TJSONObject(TJSONArray(Regeln).Items[i]), 'anchor', ANCHORS);
        PruefeRoh(TJSONObject(TJSONArray(Regeln).Items[i]), 'fixMode', FIX_MODES);
      end;
  finally
    Json.Free;
  end;

  // 2. Der geladene Katalog - leer oder bekannt, und 'auto' nie ohne Anker.
  for K := Low(TFindingKind) to High(TFindingKind) do
  begin
    Meta := TRuleCatalog.GetRuleCanonical(K);
    if Meta.ID = '' then Continue;
    Assert.IsTrue((Meta.Anchor = '') or InList(Meta.Anchor, ANCHORS),
      Meta.ID + ': unbekannter anchor ''' + Meta.Anchor + '''');
    Assert.IsTrue((Meta.FixMode = '') or InList(Meta.FixMode, FIX_MODES),
      Meta.ID + ': unbekannter fixMode ''' + Meta.FixMode + '''');
    // Eine Regel, die automatisch umgeschrieben werden darf, braucht
    // einen Anker - sonst weiss kein Modul, wo.
    if Meta.FixMode = 'auto' then
      Assert.IsTrue(Meta.Anchor <> '', Meta.ID + ': fixMode auto ohne anchor');
  end;
end;

procedure TTestRuleCatalog.RefactorPilotRulesCarryAnchorAndFixMode;
var
  Meta : TRuleMeta;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkConcatToFormat);
  Assert.AreEqual('assign', Meta.Anchor, 'SCA044 ankert an der Zuweisung');
  Assert.AreEqual('auto', Meta.FixMode, 'SCA044 darf automatisch umgeschrieben werden');

  Meta := TRuleCatalog.GetRuleCanonical(fkSQLInjection);
  Assert.AreEqual('assign-or-call', Meta.Anchor,
    'SCA003 meldet Zuweisungen und Aufrufe');
  Assert.AreEqual('assisted', Meta.FixMode,
    'SCA003 ist ein Review-Zeiger - nur assistiert, nie automatisch');
  // Editorhilfe = Code-Aktion zum Fund (Beschluss 2026-10-10, Begriff seit
  // 2026-10-11): SCA044 schreibt (Format()), SCA003 legt die
  // parametrisierte Vorlage in die Zwischenablage - beides ist eine
  // Code-Aktion, Gluehbirne und QF-Badge zeigen sie (Q17, 2026-10-23; bis
  // dahin stand SCA003 hier ausdruecklich ohne).
  Assert.IsTrue(TRuleCatalog.GetRuleCanonical(fkConcatToFormat).EditorHelp,
    'SCA044 hat eine Editorhilfe');
  Assert.IsTrue(Meta.EditorHelp, 'SCA003 hat eine Editorhilfe (SQL-Vorlage)');
end;

procedure TTestRuleCatalog.FallbackCarriesAnchorAndFixMode;
// ROOT-CAUSE-ANKER (2026-10-05): AH4 brachte anchor/fixMode in die JSON,
// aber nicht in die einkompilierte Tabelle. Das IDE-Plugin findet die JSON
// nie (BPL im Embarcadero-Verzeichnis), also lief es im Fallback - und
// reDelphix sah bei SCA044 fixMode '' statt 'auto': kein Menuepunkt.
// Der Fallback wird wie in FallbackStillProvidesExamples erzwungen.
//
// Nit 11 (Review reDelphiX 2026-10-07): verglichen wurden nur SCA044 und
// SCA003. Bekam eine dritte Regel anchor/fixMode in der JSON und blieb
// uRuleCatalogData.inc alt (die AH8-Ursache), blieb alles gruen. Jetzt
// werden VOR dem Umschalten die Werte des echten Katalogs je Kind gemerkt
// und nach dem Fallback-Reload je Kind verglichen. Die Gegenrichtung
// (JSON leer, Tabelle gesetzt) sieht dieser Vergleich nicht: der Lader
// fuellt ein leeres Feld seit Minor 40 aus der Tabelle, beide Wege
// liefern dann denselben Wert. Die Drift selbst haelt
// 'gen-rules-inc.py --check' in der CI.
var
  TmpFile    : string;
  OldPath    : string;
  Meta       : TRuleMeta;
  K          : TFindingKind;
  JsonAnchor : array[TFindingKind] of string;
  JsonFix    : array[TFindingKind] of string;
  JsonHelp   : array[TFindingKind] of Boolean;
  Abweichend : string;

  // Je abweichendem Kind ein Eintrag ' SCAnnn (anchor/fixMode statt
  // anchor/fixMode)' gegen die vorher gemerkten JSON-Werte; leer = gleich.
  function FallbackAbweichungen: string;
  var
    Kind : TFindingKind;
    Fb   : TRuleMeta;
    SB   : TStringBuilder;
  begin
    SB := TStringBuilder.Create;
    try
      for Kind := Low(TFindingKind) to High(TFindingKind) do
      begin
        Fb := TRuleCatalog.GetRuleCanonical(Kind);
        if (Fb.Anchor <> JsonAnchor[Kind]) or (Fb.FixMode <> JsonFix[Kind])
           or (Fb.EditorHelp <> JsonHelp[Kind]) then
          SB.Append(Format(' %s (%s/%s/%s statt %s/%s/%s)',
            [Fb.ID, Fb.Anchor, Fb.FixMode, BoolToStr(Fb.EditorHelp, True),
             JsonAnchor[Kind], JsonFix[Kind], BoolToStr(JsonHelp[Kind], True)]));
      end;
      Result := SB.ToString;
    finally
      SB.Free;
    end;
  end;

begin
  // Ohne geladene JSON verglichen die Schleifen Fallback mit Fallback.
  // detectorUnit fuehrt NUR die JSON, die einkompilierte Tabelle nicht.
  Assert.IsNotEmpty(TRuleCatalog.GetRuleCanonical(fkConcatToFormat).DetectorUnit,
    'echte sca-rules.json nicht geladen - der Vergleich waere Fallback gegen Fallback');
  for K := Low(TFindingKind) to High(TFindingKind) do
  begin
    Meta := TRuleCatalog.GetRuleCanonical(K);
    JsonAnchor[K] := Meta.Anchor;
    JsonFix[K]    := Meta.FixMode;
    JsonHelp[K]   := Meta.EditorHelp;
  end;

  OldPath := TRuleCatalog.JsonFilePath;
  TmpFile := TPath.Combine(TPath.GetTempPath,
    'sca_broken_rules_' + TGuid.NewGuid.ToString.Replace('{', '').Replace('}', '') + '.json');
  TFile.WriteAllText(TmpFile, '{ das ist kein gueltiger Regelkatalog');
  try
    TRuleCatalog.JsonFilePath := TmpFile;
    TRuleCatalog.Reload;

    Meta := TRuleCatalog.GetRuleCanonical(fkConcatToFormat);
    Assert.AreEqual('assign', Meta.Anchor,
      'SCA044 im Fallback ohne anchor - uRuleCatalogData.inc regenerieren');
    Assert.AreEqual('auto', Meta.FixMode,
      'SCA044 im Fallback ohne fixMode - im IDE-Plugin bietet reDelphix dann nichts an');

    Meta := TRuleCatalog.GetRuleCanonical(fkSQLInjection);
    Assert.AreEqual('assign-or-call', Meta.Anchor, 'SCA003 im Fallback ohne anchor');
    Assert.AreEqual('assisted', Meta.FixMode, 'SCA003 im Fallback ohne fixMode');

    // Und ueber ALLE Kinds: Fallback = geladene JSON.
    Abweichend := FallbackAbweichungen;
    Assert.AreEqual('', Abweichend,
      'anchor/fixMode/editorHelp im Fallback abweichend - uRuleCatalogData.inc regenerieren:' +
      Abweichend);
  finally
    TRuleCatalog.JsonFilePath := OldPath;
    TRuleCatalog.Reload;   // echten Katalog fuer die Folgetests wiederherstellen
    if TFile.Exists(TmpFile) then TFile.Delete(TmpFile);
  end;
end;

procedure TTestRuleCatalog.AnchorFixModeNonStringDoesNotRaise;
// Vorher las der Lader beide Felder mit GetValue<string>. Ein Objekt oder
// Array warf dort EJSONException; EnsureLoaded setzt FLoaded erst am Ende,
// also warf danach JEDER Katalogzugriff erneut - bis in den SARIF-Export.
// Die Erwartung kommt aus dem erzwungenen Fallback, nicht aus festen
// Werten: bekommt SCA001 je einen Anker, bleibt der Test richtig.
var
  AltPfad    : string;
  Kaputt     : string;
  Datei      : string;
  Tabelle044 : TRuleMeta;
  Tabelle001 : TRuleMeta;
  Meta       : TRuleMeta;
begin
  AltPfad := TRuleCatalog.JsonFilePath;
  Kaputt  := SchreibeTempJson('{ das ist kein gueltiger Regelkatalog');
  Datei   := SchreibeTempJson(
    '{"rules":[' +
    '{"id":"SCA044","kind":"ConcatToFormat","name":"n44",' +
    '"anchor":{"x":1},"fixMode":["auto"]},' +
    '{"id":"SCA001","kind":"MemoryLeak","name":"n1",' +
    '"anchor":"bogus","fixMode":7}]}');
  try
    // Erwartung: die einkompilierte Tabelle (Fallback erzwungen).
    TRuleCatalog.JsonFilePath := Kaputt;
    TRuleCatalog.Reload;
    Tabelle044 := TRuleCatalog.GetRuleCanonical(fkConcatToFormat);
    Tabelle001 := TRuleCatalog.GetRuleCanonical(fkMemoryLeak);
    Assert.AreEqual('auto', Tabelle044.FixMode,
      'SCA044 fuehrt in der Tabelle fixMode auto - sonst prueft der Rueckfall nichts');

    // Wirft das Laden, faellt der Test mit genau dieser Exception - vor
    // dem Fix war es EJSONException.
    TRuleCatalog.JsonFilePath := Datei;
    TRuleCatalog.Reload;

    Meta := TRuleCatalog.GetRuleCanonical(fkConcatToFormat);
    Assert.AreEqual('n44', Meta.Name,
      'die Test-JSON ist geladen, nicht der Fallback');
    Assert.AreEqual(Tabelle044.Anchor, Meta.Anchor,
      'SCA044: Objekt als anchor -> Tabellenwert');
    Assert.AreEqual(Tabelle044.FixMode, Meta.FixMode,
      'SCA044: Array als fixMode -> Tabellenwert');

    Meta := TRuleCatalog.GetRuleCanonical(fkMemoryLeak);
    Assert.AreEqual('n1', Meta.Name, 'SCA001 kommt aus der Test-JSON');
    Assert.AreEqual(Tabelle001.Anchor, Meta.Anchor,
      'SCA001: unbekannter anchor ''bogus'' rutschte durch');
    Assert.AreEqual(Tabelle001.FixMode, Meta.FixMode,
      'SCA001: Zahl als fixMode rutschte durch');
  finally
    TRuleCatalog.JsonFilePath := AltPfad;
    if TFile.Exists(Datei) then TFile.Delete(Datei);
    if TFile.Exists(Kaputt) then TFile.Delete(Kaputt);
    TRuleCatalog.Reload;   // echten Katalog wiederherstellen
  end;
end;

procedure TTestRuleCatalog.AnchorFixModeMissingFallsBackToCompiled;
// Eine aeltere sca-rules.json kennt anchor/fixMode nicht. Gefunden ueber
// den Aufwaertswalk oder %APPDATA%, ueberdeckte sie die Tabelle - und
// reDelphix bot bei KEINEM Fund mehr etwas an. Jetzt: leeres Feld ->
// Tabellenwert. Ein ausdrueckliches 'none' bleibt aber 'none', sonst
// liesse sich ein Umschreiber ueber den Katalog nicht mehr abschalten.
var
  AltPfad : string;
  Datei   : string;
  Meta    : TRuleMeta;
begin
  AltPfad := TRuleCatalog.JsonFilePath;
  Datei   := SchreibeTempJson(
    '{"rules":[' +
    '{"id":"SCA003","kind":"SQLInjection","name":"n3"},' +
    '{"id":"SCA044","kind":"ConcatToFormat","name":"n44",' +
    '"anchor":"CALL","fixMode":"none","editorHelp":false},' +
    '{"id":"SCA139","kind":"FreeWithoutNil","name":"n139","editorHelp":"ja"}]}');
  try
    TRuleCatalog.JsonFilePath := Datei;
    TRuleCatalog.Reload;

    Meta := TRuleCatalog.GetRuleCanonical(fkSQLInjection);
    Assert.AreEqual('n3', Meta.Name,
      'die Test-JSON ist geladen, nicht der Fallback');
    Assert.AreEqual('assign-or-call', Meta.Anchor,
      'SCA003 ohne anchor in der Datei -> Tabellenwert');
    Assert.AreEqual('assisted', Meta.FixMode,
      'SCA003 ohne fixMode in der Datei -> Tabellenwert, reDelphix bleibt an');

    Meta := TRuleCatalog.GetRuleCanonical(fkConcatToFormat);
    Assert.AreEqual('call', Meta.Anchor,
      'SCA044: ausdruecklicher anchor gilt, klein geschrieben');
    Assert.AreEqual('none', Meta.FixMode,
      'SCA044: ausdrueckliches none schaltet ab - kein Rueckfall auf auto');
    // editorHelp: ausdrueckliches false gilt; kein Boolean -> Tabellenwert.
    Assert.IsFalse(Meta.EditorHelp, 'SCA044: ausdrueckliches editorHelp false gilt');
    Assert.IsTrue(TRuleCatalog.GetRuleCanonical(fkFreeWithoutNil).EditorHelp,
      'SCA139: editorHelp "ja" ist kein Boolean -> Tabellenwert true');
    Assert.IsTrue(TRuleCatalog.GetRuleCanonical(fkSQLInjection).EditorHelp,
      'SCA003 ohne editorHelp in der Datei -> Tabellenwert true');
  finally
    TRuleCatalog.JsonFilePath := AltPfad;
    if TFile.Exists(Datei) then TFile.Delete(Datei);
    TRuleCatalog.Reload;   // echten Katalog wiederherstellen
  end;
end;

{ TTestRuleCatalogGuard }

procedure TTestRuleCatalogGuard.Reload_WhileWorkersRead_EveryAnswerConsistent;
// Vier Leser fragen den Katalog in Schleifen, waehrend der Testthread ihn
// wiederholt neu laedt (das Profil-Fenster 'Neu laden' waehrend eines
// Massenscans). Jede Antwort muss vollstaendig sein: ID gesetzt, Kind
// passend, 'default'-Profil nie leer, lokalisierter Name nie leer. Vor
// dem Monitor las ein Worker in ein halb geleertes Dictionary. Gezaehlt
// statt assertiert: DUnitX-Assertions gehoeren auf den Testthread.
//
// Auch eine EXCEPTION im Worker zaehlt (Review Woche G03-06): das ist das
// Hauptsymptom ohne Monitor (EListError/AV beim Lesen waehrend Clear).
// TThread faengt sie sonst still in FatalException, der Worker endet,
// WaitFor kehrt normal zurueck - und der Zaehler bliebe 0.
var
  Threads : array[0..3] of TThread;
  Fehler  : Integer;
  i, j    : Integer;
begin
  Fehler := 0;
  for i := Low(Threads) to High(Threads) do
  begin
    Threads[i] := TThread.CreateAnonymousThread(
      procedure
      var
        K     : TFindingKind;
        Meta  : TRuleMeta;
        Runde : Integer;
      begin
        try
          for Runde := 1 to 40 do
            for K := Low(TFindingKind) to High(TFindingKind) do
            begin
              Meta := TRuleCatalog.GetRuleCanonical(K);
              if (Meta.ID = '') or (Meta.Kind <> K) then
                AtomicIncrement(Fehler);
              if TRuleCatalog.GetProfile(PROF_DEFAULT) = [] then
                AtomicIncrement(Fehler);
              if TRuleCatalog.GetRule(K, 'de').Name = '' then
                AtomicIncrement(Fehler);
            end;
        except
          // Jede Exception ist ein Befund dieses Tests, keine zu
          // verschluckende Stoerung - sie landet im Zaehler.
          AtomicIncrement(Fehler);
        end;
      end);
    Threads[i].FreeOnTerminate := False;
  end;
  try
    for i := Low(Threads) to High(Threads) do
      Threads[i].Start;
    for j := 1 to 25 do
      TRuleCatalog.Reload;
    for i := Low(Threads) to High(Threads) do
      Threads[i].WaitFor;
    // Zweiter Riegel: was am except oben vorbeikaeme (nichts sollte),
    // stuende hier.
    for i := Low(Threads) to High(Threads) do
      Assert.IsNull(Threads[i].FatalException,
        Format('Worker %d endete mit einer Exception', [i]));
  finally
    for i := Low(Threads) to High(Threads) do
      Threads[i].Free;
  end;
  Assert.AreEqual<Integer>(0, Fehler,
    'unvollstaendige Katalog-Antworten waehrend Reload');
end;

procedure TTestRuleCatalogGuard.FixModeNone_TurnsEditorHelpOff;
// fixMode 'none' schaltet jede Schreibhilfe ab - dann darf der Bericht
// auch kein Quick-Win-Badge zeigen, egal was editorHelp in der Datei
// sagt. Gegenprobe: 'auto' laesst den Tabellenwert (SCA044: true) stehen.
var
  AltPfad : string;
  Datei   : string;
  Meta    : TRuleMeta;
begin
  AltPfad := TRuleCatalog.JsonFilePath;
  Datei := SchreibeTempJson(
    '{"rules":[' +
    '{"id":"SCA139","kind":"FreeWithoutNil","name":"n139",' +
    '"fixMode":"none","editorHelp":true},' +
    '{"id":"SCA044","kind":"ConcatToFormat","name":"n44","fixMode":"auto"}]}');
  try
    TRuleCatalog.JsonFilePath := Datei;
    TRuleCatalog.Reload;
    Meta := TRuleCatalog.GetRuleCanonical(fkFreeWithoutNil);
    Assert.AreEqual('none', Meta.FixMode);
    Assert.IsFalse(Meta.EditorHelp,
      'fixMode none gewinnt gegen editorHelp true');
    Meta := TRuleCatalog.GetRuleCanonical(fkConcatToFormat);
    Assert.AreEqual('auto', Meta.FixMode);
    Assert.IsTrue(Meta.EditorHelp,
      'SCA044 ohne editorHelp in der Datei -> Tabellenwert true');
  finally
    TRuleCatalog.JsonFilePath := AltPfad;
    if TFile.Exists(Datei) then TFile.Delete(Datei);
    TRuleCatalog.Reload;   // echten Katalog wiederherstellen
  end;
end;

procedure TTestRuleCatalogGuard.SaveUserProfile_WritesAtomically_NoTempFileLeft;
// WriteUserProfiles schreibt eine Nachbardatei und benennt sie um: nach
// dem Speichern steht die Zieldatei, die Nachbardatei ist weg, und ein
// zweites Speichern ersetzt die bestehende Datei.
var
  AltPfad : string;
  TmpPfad : string;
  Err     : string;
  Ziel    : TDictionary<string, TFindingKinds>;
begin
  AltPfad := TRuleCatalog.UserProfilesPath;
  TmpPfad := TPath.Combine(TPath.GetTempPath, 'sca_test_profiles_atomic_' +
    TGuid.NewGuid.ToString.Replace('{', '').Replace('}', '') + '.json');
  TRuleCatalog.UserProfilesPath := TmpPfad;
  try
    Assert.IsTrue(TRuleCatalog.SaveUserProfile('atomic-probe',
      [fkMemoryLeak], Err), 'Anlegen: ' + Err);
    Assert.IsTrue(TFile.Exists(TmpPfad), 'Zieldatei steht');
    Assert.AreEqual<Integer>(0, NachbarDateienVon(TmpPfad),
      'die Nachbardatei ist umbenannt, nicht liegengeblieben');
    Ziel := TDictionary<string, TFindingKinds>.Create;
    try
      Assert.IsTrue(TRuleCatalog.ReadProfilesFile(TmpPfad, Ziel, Err),
        'lesbar: ' + Err);
      Assert.IsTrue(Ziel.ContainsKey('atomic-probe'));
    finally
      Ziel.Free;
    end;
    Assert.IsTrue(TRuleCatalog.SaveUserProfile('atomic-probe',
      [fkSQLInjection], Err), 'Aendern: ' + Err);
    Assert.AreEqual<Integer>(0, NachbarDateienVon(TmpPfad));
    Assert.IsTrue(fkSQLInjection in TRuleCatalog.GetProfile('atomic-probe'));
  finally
    TRuleCatalog.DeleteUserProfile('atomic-probe', Err);
    TRuleCatalog.UserProfilesPath := AltPfad;
    if TFile.Exists(TmpPfad) then TFile.Delete(TmpPfad);
    LoescheNachbarDateien(TmpPfad);
  end;
end;

procedure TTestRuleCatalogGuard.SaveUserProfile_TargetReadOnly_KeepsOldFileNoTempLeft;
// Ein schreibgeschuetztes Ziel laesst MoveFileEx(REPLACE_EXISTING) mit
// ERROR_ACCESS_DENIED scheitern - die Nachbardatei ist da schon
// geschrieben. Ohne das Aufraeumen im except blieb sie im
// Konfigverzeichnis liegen; der alte Inhalt muss in jedem Fall stehen.
var
  AltPfad : string;
  TmpPfad : string;
  Err     : string;
  Vorher  : string;
begin
  AltPfad := TRuleCatalog.UserProfilesPath;
  TmpPfad := TPath.Combine(TPath.GetTempPath, 'sca_test_profiles_ro_' +
    TGuid.NewGuid.ToString.Replace('{', '').Replace('}', '') + '.json');
  TRuleCatalog.UserProfilesPath := TmpPfad;
  try
    Assert.IsTrue(TRuleCatalog.SaveUserProfile('ro-probe',
      [fkMemoryLeak], Err), 'Anlegen: ' + Err);
    Vorher := TFile.ReadAllText(TmpPfad);
    Assert.IsTrue(FileSetReadOnly(TmpPfad, True), 'Schreibschutz setzen');

    Assert.IsFalse(TRuleCatalog.SaveUserProfile('ro-probe',
      [fkSQLInjection], Err), 'Tausch auf ein schreibgeschuetztes Ziel');
    Assert.IsTrue(Err <> '', 'Fehlertext fuer die Oberflaeche');
    Assert.AreEqual(Vorher, TFile.ReadAllText(TmpPfad),
      'alter Dateiinhalt unveraendert');
    Assert.AreEqual<Integer>(0, NachbarDateienVon(TmpPfad),
      'keine Nachbardatei-Leiche');
    Assert.IsTrue(fkMemoryLeak in TRuleCatalog.GetProfile('ro-probe'),
      'der Speicher bleibt beim gespeicherten Stand');
    Assert.IsFalse(fkSQLInjection in TRuleCatalog.GetProfile('ro-probe'));
  finally
    if TFile.Exists(TmpPfad) then
      FileSetReadOnly(TmpPfad, False);
    TRuleCatalog.DeleteUserProfile('ro-probe', Err);
    TRuleCatalog.UserProfilesPath := AltPfad;
    if TFile.Exists(TmpPfad) then TFile.Delete(TmpPfad);
    LoescheNachbarDateien(TmpPfad);
  end;
end;

{ TTestRuleCatalogEditorHelps }

function HilfenVon(K: TFindingKind): string;
// Die Hilfen einer Regel als ein Text ('id:effect:slug' mit ' ' getrennt)
// - eine Assertion vergleicht die ganze Liste samt Reihenfolge.
begin
  Result := string.Join(' ', EditorHelpTokens(TRuleCatalog.GetRuleCanonical(K)));
end;

procedure TTestRuleCatalogEditorHelps.Sca017_TwoEntries_IdEffectSlug;
var
  Meta : TRuleMeta;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkDebugOutput);
  Assert.IsTrue(Meta.EditorHelp, 'Vorbedingung: SCA017 editorHelp');
  Assert.AreEqual<Integer>(2, Length(Meta.EditorHelps),
    'SCA017: {$IFDEF DEBUG} und Loeschen - zwei Menueeintraege');
  Assert.AreEqual('SCA017', Meta.EditorHelps[0].Id);
  Assert.AreEqual('changes', Meta.EditorHelps[0].Effect);
  Assert.AreEqual('put-debug-output-in-ifdef-debug', Meta.EditorHelps[0].Slug);
  Assert.AreEqual('SCA017.2', Meta.EditorHelps[1].Id);
  Assert.AreEqual('changes', Meta.EditorHelps[1].Effect);
  Assert.AreEqual('delete-debug-output', Meta.EditorHelps[1].Slug);
end;

procedure TTestRuleCatalogEditorHelps.Effects_TemplateDependsSameChanges;
begin
  Assert.AreEqual('SCA003:template:copy-parameterized-template-to-clipboard',
    HilfenVon(fkSQLInjection), 'SQL-Vorlage schreibt nicht in den Editor');
  Assert.AreEqual('SCA086:depends:replace-out-with-var-for',
    HilfenVon(fkAvoidOut), 'out -> var: Kennzeichnung je nach Fund');
  Assert.AreEqual('SCA020:same:mark-empty-body-as-intentional ' +
    'SCA020.2:changes:raise-enotimplemented-in-empty-body',
    HilfenVon(fkEmptyMethod), 'zwei Eintraege mit verschiedener Wirkung');
  Assert.AreEqual('', HilfenVon(fkDivByZero), 'SCA010 ohne Editorhilfe');
end;

function HilfeBefund(const AMeta: TRuleMeta; AIdx: Integer): string;
// Was am Eintrag AIdx der Hilfen von AMeta nicht stimmt; '' = nichts.
var
  Soll : string;
  H    : TRuleEditorHelp;
begin
  Result := '';
  H := AMeta.EditorHelps[AIdx];
  if AIdx = 0 then
    Soll := AMeta.ID
  else
    Soll := Format('%s.%d', [AMeta.ID, AIdx + 1]);
  if H.Id <> Soll then
    Result := Format(' %s (id %s statt %s)', [AMeta.ID, H.Id, Soll]);
  if Pos(',' + H.Effect + ',', ',same,changes,depends,template,') = 0 then
    Result := Result + Format(' %s (effect %s)', [AMeta.ID, H.Effect]);
  if H.Slug = '' then
    Result := Result + Format(' %s (slug leer)', [AMeta.ID]);
end;

procedure TTestRuleCatalogEditorHelps.EveryKind_InvariantAndIdsBelongToRule;
var
  K    : TFindingKind;
  Meta : TRuleMeta;
  i    : Integer;
  SB   : TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    for K := Low(TFindingKind) to High(TFindingKind) do
    begin
      Meta := TRuleCatalog.GetRuleCanonical(K);
      if Meta.EditorHelp <> (Length(Meta.EditorHelps) > 0) then
        SB.Append(Format(' %s (editorHelp %s, %d Hilfen)', [Meta.ID,
          BoolToStr(Meta.EditorHelp, True), Length(Meta.EditorHelps)]));
      for i := 0 to High(Meta.EditorHelps) do
        SB.Append(HilfeBefund(Meta, i));
    end;
    Assert.AreEqual('', SB.ToString, 'editorHelps im Katalog:' + SB.ToString);
  finally
    SB.Free;
  end;
end;

procedure TTestRuleCatalogEditorHelps.Fallback_EqualsJson;
// Wie FallbackCarriesAnchorAndFixMode: erst die Werte der echten JSON je
// Kind merken, dann den Fallback erzwingen und vergleichen. Ohne das Feld
// in uRuleCatalogData.inc haette das IDE-Plugin (dort ist der Fallback
// der Normalfall) keine Hilfen, die CLI mit gefundener JSON schon.
var
  K          : TFindingKind;
  AusJson    : array[TFindingKind] of string;
  AltPfad    : string;
  Kaputt     : string;
  Abweichend : TStringBuilder;
begin
  Assert.IsNotEmpty(TRuleCatalog.GetRuleCanonical(fkDebugOutput).DetectorUnit,
    'echte sca-rules.json nicht geladen - Fallback gegen Fallback');
  for K := Low(TFindingKind) to High(TFindingKind) do
    AusJson[K] := HilfenVon(K);
  Assert.AreNotEqual('', AusJson[fkDebugOutput], 'Vorbedingung: SCA017 hat Hilfen');

  AltPfad    := TRuleCatalog.JsonFilePath;
  Kaputt     := SchreibeTempJson('{ das ist kein gueltiger Regelkatalog');
  Abweichend := TStringBuilder.Create;
  try
    TRuleCatalog.JsonFilePath := Kaputt;
    TRuleCatalog.Reload;
    for K := Low(TFindingKind) to High(TFindingKind) do
      if HilfenVon(K) <> AusJson[K] then
        Abweichend.Append(Format(' %s [%s] statt [%s]',
          [TRuleCatalog.GetRuleCanonical(K).ID, HilfenVon(K), AusJson[K]]));
    Assert.AreEqual('', Abweichend.ToString,
      'editorHelps im Fallback abweichend - uRuleCatalogData.inc regenerieren:' +
      Abweichend.ToString);
  finally
    Abweichend.Free;
    TRuleCatalog.JsonFilePath := AltPfad;
    if TFile.Exists(Kaputt) then TFile.Delete(Kaputt);
    TRuleCatalog.Reload;   // echten Katalog wiederherstellen
  end;
end;

procedure TTestRuleCatalogEditorHelps.Loader_FileWins_MalformedFallsBack_FalseClears;
var
  AltPfad : string;
  Datei   : string;
begin
  AltPfad := TRuleCatalog.JsonFilePath;
  Datei   := SchreibeTempJson(
    '{"rules":[' +
    // eine Liste aus der Datei gilt (nicht die Tabelle); effect Gross/klein
    // egal, geliefert klein
    '{"id":"SCA044","kind":"ConcatToFormat","name":"n44","editorHelp":true,' +
    '"editorHelps":[{"id":"SCA044","effect":"Changes","slug":"probe"}]},' +
    // leeres Array -> Tabellenwert (Schema minItems 1)
    '{"id":"SCA093","kind":"TwiceInheritedCalls","name":"n93","editorHelp":true,' +
    '"editorHelps":[]},' +
    // id einer anderen Regel -> Tabellenwert
    '{"id":"SCA002","kind":"EmptyExcept","name":"n2","editorHelp":true,' +
    '"editorHelps":[{"id":"SCA003","effect":"changes","slug":"x"}]},' +
    // slug mit ':' (Trenner von EditorHelpTokens) -> Tabellenwert
    '{"id":"SCA007","kind":"UnusedUses","name":"n7","editorHelp":true,' +
    '"editorHelps":[{"id":"SCA007","effect":"changes","slug":"a:b"}]},' +
    // kein Array -> Tabellenwert (zwei Eintraege)
    '{"id":"SCA017","kind":"DebugOutput","name":"n17","editorHelp":true,' +
    '"editorHelps":"ja"},' +
    // unbekannte Wirkung in einem Eintrag -> die ganze Liste faellt auf
    // die Tabelle
    '{"id":"SCA046","kind":"ReversedForRange","name":"n46","editorHelp":true,' +
    '"editorHelps":[{"id":"SCA046","effect":"vielleicht","slug":"x"}]},' +
    // Feld fehlt, editorHelp true -> Tabellenwert
    '{"id":"SCA003","kind":"SQLInjection","name":"n3","editorHelp":true},' +
    // editorHelp false ohne Liste -> keine Hilfen (Invariante)
    '{"id":"SCA020","kind":"EmptyMethod","name":"n20","editorHelp":false},' +
    // fixMode none -> keine Hilfen, auch mit Liste
    '{"id":"SCA139","kind":"FreeWithoutNil","name":"n139","fixMode":"none",' +
    '"editorHelp":true,' +
    '"editorHelps":[{"id":"SCA139","effect":"same","slug":"use-freeandnil"}]}]}');
  try
    TRuleCatalog.JsonFilePath := Datei;
    TRuleCatalog.Reload;
    Assert.AreEqual('n44', TRuleCatalog.GetRuleCanonical(fkConcatToFormat).Name,
      'die Test-JSON ist geladen, nicht der Fallback');

    Assert.AreEqual('SCA044:changes:probe', HilfenVon(fkConcatToFormat),
      'die Liste der Datei gilt, effect "Changes" -> "changes"');
    Assert.AreEqual('SCA093:changes:remove-second-duplicate-inherited-call ' +
      'SCA093.2:changes:remove-first-duplicate-inherited-call',
      HilfenVon(fkTwiceInheritedCalls), '[] -> Tabellenwert');
    Assert.AreEqual('SCA002:changes:add-raise-to-empty-except-block',
      HilfenVon(fkEmptyExcept), 'fremde id -> Tabellenwert');
    Assert.AreEqual('SCA007:changes:remove-unit-from-uses',
      HilfenVon(fkUnusedUses), 'slug mit ":" -> Tabellenwert');
    Assert.AreEqual('SCA017:changes:put-debug-output-in-ifdef-debug ' +
      'SCA017.2:changes:delete-debug-output', HilfenVon(fkDebugOutput),
      'editorHelps "ja" ist keine Liste -> Tabellenwert');
    Assert.AreEqual('SCA046:changes:replace-to-with-downto ' +
      'SCA046.2:changes:swap-loop-bounds', HilfenVon(fkReversedForRange),
      'unbekannte Wirkung -> Tabellenwert');
    Assert.AreEqual('SCA003:template:copy-parameterized-template-to-clipboard',
      HilfenVon(fkSQLInjection), 'ohne Feld -> Tabellenwert');
    Assert.AreEqual('', HilfenVon(fkEmptyMethod),
      'editorHelp false -> keine Hilfen, auch nicht aus der Tabelle');
    Assert.AreEqual('', HilfenVon(fkFreeWithoutNil),
      'fixMode none -> keine Hilfen, auch nicht aus der Datei');
  finally
    TRuleCatalog.JsonFilePath := AltPfad;
    if TFile.Exists(Datei) then TFile.Delete(Datei);
    TRuleCatalog.Reload;   // echten Katalog wiederherstellen
  end;
end;

initialization
  // Anmeldung ausdruecklich, nicht nur ueber UseRTTI des Runners (Review
  // Woche G03-25): ein Runner ohne RTTI-Suche liesse die Waechter sonst
  // still aus.
  TDUnitX.RegisterTestFixture(TTestRuleCatalog);
  TDUnitX.RegisterTestFixture(TTestRuleCatalogGuard);
  TDUnitX.RegisterTestFixture(TTestRuleCatalogEditorHelps);

end.
