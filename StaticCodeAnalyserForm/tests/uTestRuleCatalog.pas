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
  end;

implementation

uses
  System.Generics.Collections, System.RegularExpressions;

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
// Zusatznutzen: TRuleCatalog.ParseFindingType faellt bei unbekannter
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
// 2026-08-03): genau diese sieben reinen Konventions-Regeln sind aus
// 'default' raus - zusammen 48,1 % aller Funde auf dem Referenzkorpus.
// Nicht mehr und nicht weniger; jede spaetere stille Erweiterung der
// Liste faellt hier auf.
const
  EXPECTED : array[0..6] of string = (
    'PublicMemberWithoutDoc', 'NilComparison', 'BeginEndRequired',
    'WithStatement', 'ClassPerFile', 'DfmHardcodedCaption',
    'IfElseBegin');
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
    'default muss GENAU die sieben beschlossenen Regeln weglassen');
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


end.
