unit uTestBaselineMetricFingerprint;

// Tests fuer den ZIFFERN-ZWEIG in TBaseline.Fingerprint
// (METRIC_DETAIL_KINDS, uBaseline).
//
// WARUM ES SIE GIBT (Befund Baseline-Identitaet, 2026-08-28)
//
// Der Baseline-Fingerprint hasht den Detailtext mit. Vier Detektoren
// schreiben dort nicht nur ihren gemessenen WERT hinein, sondern auch den
// konfigurierten SCHWELLWERT:
//   SCA022 'Cyclomatic complexity 11 (limit: 10)'
//   SCA018 'Depth 5 (if from line 1456, limit: 4)'
//   SCA176 'Cognitive complexity 21 (limit: 15)'
//   SCA012 '180 body lines, 95 statements (limit: 120 / 60)'
// CyclomaticMax und DeepNestingMaxDepth sind dokumentierte INI-Knoepfe
// (docs/configuration.md). Wer daran dreht, aendert KEINEN einzigen Fund -
// aber jeden Fingerprint dieser vier Regeln. Am Korpus rw20 gemessen:
// 37.990 Funde = 4,85 %.
//
// WAS DIE TESTS FESTHALTEN
//   (a) Score_Wandert_FingerprintBleibt - der gemessene Wert wandert, die
//       Identitaet bleibt. OHNE DEN ZWEIG ROT.
//   (b) Schwellwert_Wandert_FingerprintBleibt - der INI-Knopf wandert, die
//       Identitaet bleibt. OHNE DEN ZWEIG ROT. Das ist der eigentliche
//       Anlass: hier aendert sich am Code und am Fund gar nichts.
//   (c) AlleVierRegeln_IgnorierenIhreZahlen - keine der vier ist vergessen.
//       OHNE DEN ZWEIG ROT (schon beim ersten Assert).
//   (d) DeepNesting_Zeilennummer_FaelltMitWeg - die ZUGABE. SCA018 schrieb
//       'from line 1456' in den Text und brach damit die Zusage am Kopf von
//       uBaseline, Line gehe NICHT in den Fingerprint; alle 3.707
//       SCA018-Funde in rw20 verloren ihre Zuordnung schon bei reiner
//       Zeilenverschiebung. OHNE DEN ZWEIG ROT.
//   (e) DeepNesting_Schluesselwort_BleibtUnterscheider - die Gegenprobe zu
//       (d): der ziffernfreie Teil ('if' gegen 'for') trennt weiterhin.
//       WAECHTER, auch ohne den Zweig gruen.
//   (f) SCA101_Spalte_BleibtUnterscheider - DER WAECHTER GEGEN DIE GLOBALE
//       FASSUNG. Bei SCA101 (285.942 Funde, groesste Regel im Korpus) ist
//       die Spaltennummer der EINZIGE Unterscheider zwischen zwei Funden
//       derselben Datei. Eine Normalisierung ueber alle Regeln kostete an
//       rw20 ausgezaehlt rund 120.700 Identitaeten (~15 %), allein 94.254
//       davon in SCA101 - unsichtbar, weil die Funde einfach verschwinden.
//       WAECHTER, auch ohne den Zweig gruen; er wird rot, sobald jemand die
//       Kind-Menge aufweicht.
//   (g) DuplicateBlock_Zeilen_BleibenUnterscheider - dieselbe Grenze fuer
//       SCA021: die Regel traegt denselben Zeilennummern-Bruch wie SCA018
//       (9.150 Funde), ist aber BEWUSST nicht in der Menge, weil bei ihr die
//       Zeilennummern zwei Duplikat-Gruppen derselben Datei unterscheiden.
//       WAECHTER, auch ohne den Zweig gruen.
//   (h) EinBaselineEintrag_BlendetGleichnamigeMethodeMit -
//       DIE KOSTEN, festgenagelt statt versteckt, und zwar am ECHTEN
//       Weg Write -> Apply statt an zwei Hashes. Zwei gleichnamige Methoden
//       derselben Datei (Overload, oder gleicher Name in zwei Klassen einer
//       Unit) mit verschiedenen Scores teilen ab jetzt einen Fingerprint;
//       ein Baseline-Eintrag blendet beide aus. Am Korpus rw20
//       methodengenau nachgemessen: 185 Faelle - SCA022 61, SCA176 60,
//       SCA018 35, SCA012 29 - also 0,49 % der vier Regeln und 0,024 % des
//       Korpus. OHNE DEN ZWEIG ROT, weil er das NEUE Verhalten beschreibt:
//       bis 2026-08-28 blieb der Zwilling stehen.
//   (i) VerschiedeneMethoden_BleibenGetrennt - die Grenze dazu: der
//       Methodenname traegt weiter. Ohne ihn waere aus den 185 Kollisionen
//       eine je Datei und Regel geworden. REGRESSIONSSCHUTZ.
//   (j) LeererMethodName_LaesstNurNochEineIdentitaetJeDatei - die BEKANNTE
//       GRENZE, beziffert statt verschwiegen. Traegt ein Fund keinen
//       Methodennamen, ist der Detailtext der letzte Unterscheider - und
//       den normalisiert der Zweig weg. Dann gilt die annahmefreie
//       Obergrenze: ein Fingerprint je Datei und Regel, an rw20 waeren das
//       20.194 statt 185. Beobachtet ist der Fall bei diesen vier Regeln
//       nicht (in rw20 kein einziger Fund mit leerem Namen; alle vier
//       brauchen einen RUMPF, und das Headless-Method-Muster erzeugt
//       nkMethod ohne nkBlock, also gar keinen Fund). OHNE DEN ZWEIG ROT.
//
// ZUR ZAHL 185: der Methodenname steht nicht im SARIF, er muss aus der
// Kopfzeile gelesen werden. Bis 2026-08-28 stand hier 222 - das Skript
// brach seine Regex am '<' ab, las aus 'procedure TFoo<T>.Bar' nur 'TFoo'
// und verschmolz alle Methoden einer generischen Klasse. Die Nachmessung
// bildet uParser2.ParseMethodSignature nach (SkipGenericParams nach jedem
// Qualifizierer).
//
// Kein Test hier fasst ein Prozess-Global an; die Fingerprint-Tests fassen
// auch die Platte nicht an, weil TBaselineScope.ByFileName nur den
// Basisnamen braucht. Nur (h) legt eine Quelldatei an - Write und Apply
// rechnen unterwegs contextHashes, und die sollen echt sein statt
// fail-open.

interface

uses
  DUnitX.TestFramework,
  uSCAConsts;

type
  [TestFixture]
  TTestBaselineMetricFingerprint = class
  strict private
    // Nur (h) braucht sie; TearDown raeumt beide weg.
    FPasFile      : string;
    FBaselineFile : string;
    function TempGuidPath(const AExt: string): string;
    // Fingerprint eines synthetischen Fundes im Default-Zuschnitt. Die
    // Zeilennummer ist bei allen Aufrufen gleich - sie geht ohnehin nicht
    // in den Fingerprint ein, und genau das soll hier nicht das Ergebnis
    // tragen.
    function Fp(AKind: TFindingKind; const AMethod,
      ADetail: string): string;
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure Score_Wandert_FingerprintBleibt;
    [Test] procedure Schwellwert_Wandert_FingerprintBleibt;
    [Test] procedure AlleVierRegeln_IgnorierenIhreZahlen;
    [Test] procedure DeepNesting_Zeilennummer_FaelltMitWeg;
    [Test] procedure DeepNesting_Schluesselwort_BleibtUnterscheider;
    [Test] procedure SCA101_Spalte_BleibtUnterscheider;
    [Test] procedure DuplicateBlock_Zeilen_BleibenUnterscheider;
    [Test] procedure EinBaselineEintrag_BlendetGleichnamigeMethodeMit;
    [Test] procedure VerschiedeneMethoden_BleibenGetrennt;
    [Test] procedure LeererMethodName_LaesstNurNochEineIdentitaetJeDatei;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Generics.Collections,
  uMethodd12, uBaseline, uFileTextCache;

const
  // Frei erfundener Pfad fuer die reinen Fingerprint-Tests: der
  // Default-Zuschnitt nimmt davon nur 'udemo.pas', und die Datei muss
  // dafuer nicht existieren.
  PAS_FILE = 'C:\repo\src\uDemo.pas';
  METHOD_A = 'TDemo.DoWork';
  METHOD_B = 'TDemo.Calculate';
  // Beliebig: die Zeile geht nicht in den Fingerprint ein, und genau das
  // soll hier kein Ergebnis tragen.
  ANY_LINE = 42;
  TMP_PREFIX = 'sca_blmetric_';

  // Zitate aus den vier Detektoren, jeweils in mehreren Faellen.
  // SCA022 - uCyclomaticComplexity.pas
  CC_SCORE_11 = 'Cyclomatic complexity 11 (limit: 10) - viele ' +
                'Verzweigungen, schwer zu testen';
  CC_SCORE_12 = 'Cyclomatic complexity 12 (limit: 10) - viele ' +
                'Verzweigungen, schwer zu testen';
  // Gleicher Score 11, anderer Schwellwert - so variiert wirklich NUR der
  // INI-Knopf.
  CC_LIMIT_12 = 'Cyclomatic complexity 11 (limit: 12) - viele ' +
                'Verzweigungen, schwer zu testen';
  // SCA018 - uDeepNesting.pas
  DN_LINE_1456 = 'Depth 5 (if from line 1456, limit: 4)';
  DN_LINE_1502 = 'Depth 5 (if from line 1502, limit: 4)';
  DN_FOR_1456  = 'Depth 5 (for from line 1456, limit: 4)';
  DN_DEPTH_6   = 'Depth 6 (if from line 1456, limit: 4)';
  // SCA176 - uCognitiveComplexity.pas
  CG_SCORE_21 = 'Cognitive complexity 21 (limit: 15) - nested control ' +
                'flow is hard to follow.';
  CG_SCORE_23 = 'Cognitive complexity 23 (limit: 15) - nested control ' +
                'flow is hard to follow.';
  // SCA012 - uLongMethod.pas
  LM_180 = '180 body lines, 95 statements (limit: 120 / 60)';
  LM_190 = '190 body lines, 98 statements (limit: 120 / 60)';

  // SCA101 - uBeginEndRequired.pas. Die Spalte ist der EINZIGE
  // Unterscheider; MethodName setzt der Detektor nicht.
  BE_COL_5  = 'Branch at column 5 uses a single statement without ' +
              '`begin..end`';
  BE_COL_42 = 'Branch at column 42 uses a single statement without ' +
              '`begin..end`';
  // SCA021 - uDuplicateBlock.pas. Auch hier tragen die Zahlen die
  // Unterscheidung, und auch hier setzt der Detektor keinen MethodName.
  DB_248 = 'Code block (lines 248-272, 8 matched lines) appears 2x in file';
  DB_310 = 'Code block (lines 310-334, 8 matched lines) appears 2x in file';

  // Quelldatei fuer (h). Die beiden Overloads stehen weit auseinander,
  // damit ihre contextHash-Fenster (+/- CONTEXT_HASH_RADIUS) sich nicht
  // beruehren - ein Treffer im Test kann dann nur vom Fingerprint kommen.
  OVERLOAD_LINE_A = 4;
  OVERLOAD_LINE_B = 14;
  OVERLOAD_BODY =
    'unit uDemo;'#13#10 +          // 1
    'interface'#13#10 +            // 2
    'implementation'#13#10 +       // 3
    'procedure DoWork(A: Integer);'#13#10 +   // 4  <- Fund 1
    'begin'#13#10 +                // 5
    '  if A > 0 then Inc(A);'#13#10 +         // 6
    '  if A > 1 then Inc(A);'#13#10 +         // 7
    '  if A > 2 then Inc(A);'#13#10 +         // 8
    'end;'#13#10 +                 // 9
    ''#13#10 +                     // 10
    ''#13#10 +                     // 11
    ''#13#10 +                     // 12
    ''#13#10 +                     // 13
    'procedure DoWork(const S: string);'#13#10 +  // 14 <- Fund 2
    'begin'#13#10 +                // 15
    '  if S <> '''' then Exit;'#13#10 +       // 16
    '  if S = ''x'' then Exit;'#13#10 +       // 17
    '  if S = ''y'' then Exit;'#13#10 +       // 18
    'end;'#13#10 +                 // 19
    'end.'#13#10;                  // 20

{ Fixture-Rahmen }

procedure TTestBaselineMetricFingerprint.Setup;
begin
  FPasFile      := '';
  FBaselineFile := '';
  // Der prozessweite Text-Cache ueberlebt fremde Fixtures. (h) schreibt
  // eine Quelldatei und will sie danach frisch gelesen sehen - dasselbe
  // Leeren, das ein echter Scan-Start macht.
  uFileTextCache.ReleaseTransientCaches;
end;

procedure TTestBaselineMetricFingerprint.TearDown;
begin
  if (FPasFile <> '') and TFile.Exists(FPasFile) then
  begin
    TFile.Delete(FPasFile);
  end;
  if (FBaselineFile <> '') and TFile.Exists(FBaselineFile) then
  begin
    TFile.Delete(FBaselineFile);
  end;
  FPasFile      := '';
  FBaselineFile := '';
end;

{ Helfer }

function TTestBaselineMetricFingerprint.TempGuidPath(
  const AExt: string): string;
// Frischer Pfad unterhalb des Temp-Ordners: Praefix + GUID + Endung.
// Dieselbe Guid-Wasche wie in uTestBaselineSetContextHash - liegen
// gebliebene Leichen sind am Praefix zu erkennen.
begin
  Result := TPath.Combine(TPath.GetTempPath, TMP_PREFIX +
    TGuid.NewGuid.ToString.Replace('{', '').Replace('}', '') + AExt);
end;

function TTestBaselineMetricFingerprint.Fp(AKind: TFindingKind;
  const AMethod, ADetail: string): string;
var
  F : TLeakFinding;
begin
  F := TLeakFinding.New(PAS_FILE, AMethod, ANY_LINE, ADetail, AKind);
  try
    Result := TBaseline.Fingerprint(F, TBaselineScope.ByFileName);
  finally
    F.Free;
  end;
end;

{ Tests }

procedure TTestBaselineMetricFingerprint.Score_Wandert_FingerprintBleibt;
// (a) OHNE DEN ZWEIG ROT. Ein Detektor- oder Parserfix verschiebt den
// McCabe-Wert um 1. Der Fund ist derselbe, an derselben Stelle, in
// derselben Methode - nur die Zahl im Meldetext ist gewandert. Bis
// 2026-08-28 war das eine neue Identitaet, und der Nutzer sah den Fund im
// Anzeigefilter einmalig wieder als "neu".
begin
  Assert.AreEqual(
    Fp(fkCyclomaticComplexity, METHOD_A, CC_SCORE_11),
    Fp(fkCyclomaticComplexity, METHOD_A, CC_SCORE_12),
    'ein gewanderter Score darf die Baseline-Identitaet nicht wechseln');
end;

procedure TTestBaselineMetricFingerprint.Schwellwert_Wandert_FingerprintBleibt;
// (b) OHNE DEN ZWEIG ROT - und das ist der eigentliche Anlass. Hier aendert
// sich weder Code noch Fund noch Score: der Nutzer dreht nur
// [Detectors] CyclomaticMax von 10 auf 12, wie es docs/configuration.md
// ausdruecklich anbietet.
begin
  Assert.AreEqual(
    Fp(fkCyclomaticComplexity, METHOD_A, CC_SCORE_11),
    Fp(fkCyclomaticComplexity, METHOD_A, CC_LIMIT_12),
    'ein gedrehter INI-Schwellwert darf keine Baseline entwerten');
end;

procedure TTestBaselineMetricFingerprint.AlleVierRegeln_IgnorierenIhreZahlen;
// (c) OHNE DEN ZWEIG ROT. Vollstaendigkeitsprobe: vergaesse jemand eine der
// vier Regeln in METRIC_DETAIL_KINDS, faellt es hier auf und nicht erst am
// Korpus.
begin
  Assert.AreEqual(
    Fp(fkCyclomaticComplexity, METHOD_A, CC_SCORE_11),
    Fp(fkCyclomaticComplexity, METHOD_A, CC_SCORE_12),
    'SCA022 CyclomaticComplexity');
  Assert.AreEqual(
    Fp(fkDeepNesting, METHOD_A, DN_LINE_1456),
    Fp(fkDeepNesting, METHOD_A, DN_DEPTH_6),
    'SCA018 DeepNesting');
  Assert.AreEqual(
    Fp(fkCognitiveComplexity, METHOD_A, CG_SCORE_21),
    Fp(fkCognitiveComplexity, METHOD_A, CG_SCORE_23),
    'SCA176 CognitiveComplexity');
  Assert.AreEqual(
    Fp(fkLongMethod, METHOD_A, LM_180),
    Fp(fkLongMethod, METHOD_A, LM_190),
    'SCA012 LongMethod');
end;

procedure TTestBaselineMetricFingerprint.DeepNesting_Zeilennummer_FaelltMitWeg;
// (d) OHNE DEN ZWEIG ROT - die ZUGABE, und sie ist mehr wert als das
// Schwellwert-Leck allein. uBaseline sagt am Kopf zu, Line gehe BEWUSST
// NICHT in den Fingerprint, weil Insert/Delete einer Zeile sonst jedes
// Finding verschiebt. SCA018 schrieb die Zeilennummer trotzdem hinein -
// im Meldetext. Alle 3.707 SCA018-Funde in rw20 (100 % der Regel) verloren
// deshalb ihre Baseline-Zuordnung schon dann, wenn oberhalb eine Zeile
// eingefuegt wurde. Der Zweig raeumt das mit weg, weil die Zeilennummer
// eine Ziffernfolge ist wie jede andere.
begin
  Assert.AreEqual(
    Fp(fkDeepNesting, METHOD_A, DN_LINE_1456),
    Fp(fkDeepNesting, METHOD_A, DN_LINE_1502),
    'eine reine Zeilenverschiebung darf SCA018 nicht aus der Baseline ' +
    'werfen - das ist die Zusage am Kopf von uBaseline');
end;

procedure TTestBaselineMetricFingerprint.DeepNesting_Schluesselwort_BleibtUnterscheider;
// (e) WAECHTER, auch ohne den Zweig gruen. Die Gegenprobe zu (d): der
// Zweig loescht ZIFFERN, nicht den halben Meldetext. Das Schluesselwort
// ('if'/'for'/'while'/'repeat'/'case', uDeepNesting.KindName) ist
// ziffernfrei und muss weiter trennen - sonst waere aus der gezielten
// Normalisierung heimlich die globale geworden.
begin
  Assert.AreNotEqual(
    Fp(fkDeepNesting, METHOD_A, DN_LINE_1456),
    Fp(fkDeepNesting, METHOD_A, DN_FOR_1456),
    'if und for sind verschiedene Befunde und muessen es bleiben');
end;

procedure TTestBaselineMetricFingerprint.SCA101_Spalte_BleibtUnterscheider;
// (f) DER WAECHTER GEGEN DIE GLOBALE FASSUNG. Wer die Ziffern-Normalisierung
// "aufraeumt" und sie auf alle Regeln zieht, macht genau diesen Test rot.
//
// SCA101 BeginEndRequired ist mit 285.942 Funden die groesste Regel im
// Korpus. Ihr Meldetext traegt die SPALTE, und der Detektor setzt keinen
// MethodName - die Spaltennummer ist damit der EINZIGE Unterscheider
// zwischen zwei Branches derselben Datei. Global normalisiert kostete das
// an rw20 ausgezaehlt 94.254 Identitaeten allein in dieser Regel, rund
// 120.700 ueber alle: ein einziger Baseline-Eintrag legte dann saemtliche
// Branches einer Datei still, und zwar ohne jede Meldung.
begin
  Assert.AreNotEqual(
    Fp(fkBeginEndRequired, '', BE_COL_5),
    Fp(fkBeginEndRequired, '', BE_COL_42),
    'die Spalte ist bei SCA101 der einzige Unterscheider - ein ' +
    'Baseline-Eintrag darf nicht alle Branches der Datei stilllegen');
end;

procedure TTestBaselineMetricFingerprint.DuplicateBlock_Zeilen_BleibenUnterscheider;
// (g) WAECHTER, auch ohne den Zweig gruen. SCA021 traegt denselben
// Zeilennummern-Bruch wie SCA018 - 'lines 248-272' steht im Text, 9.150
// Funde in rw20 - und ist trotzdem BEWUSST nicht in METRIC_DETAIL_KINDS.
// Grund: bei SCA018 gibt es hoechstens einen Fund je Methode, bei SCA021
// mehrere Duplikat-Gruppen je Datei, und der Detektor setzt MethodName auf
// Leerstring. Die Zeilennummern sind dort das Einzige, was zwei Gruppen
// auseinanderhaelt. Wer SCA021 dazunimmt, um den Vertragsbruch "auch noch"
// zu heilen, verliert die Unterscheidbarkeit - das ist der Handel, und
// dieser Test macht ihn sichtbar.
begin
  Assert.AreNotEqual(
    Fp(fkDuplicateBlock, '', DB_248),
    Fp(fkDuplicateBlock, '', DB_310),
    'zwei Duplikat-Gruppen derselben Datei muessen unterscheidbar bleiben');
end;

procedure TTestBaselineMetricFingerprint.EinBaselineEintrag_BlendetGleichnamigeMethodeMit;
// (h) OHNE DEN ZWEIG ROT, weil er das NEUE Verhalten beschreibt: bis
// 2026-08-28 blieb der zweite Overload stehen.
//
// DAS SIND DIE KOSTEN, und sie stehen hier am ECHTEN Weg (Write -> Apply)
// statt an zwei nackten Hashes: so ist sichtbar, was der Nutzer erlebt.
// Die vier Metrik-Regeln erzeugen hoechstens EINEN Fund je Methode.
// Kollidieren koennen deshalb nur GLEICHNAMIGE Methoden derselben Datei -
// Overloads, oder derselbe Name in zwei Klassen einer Unit. Am Korpus rw20
// methodengenau nachgemessen sind das 185 Faelle (SCA022 61, SCA176 60,
// SCA018 35, SCA012 29) = 0,49 % der vier Regeln, 0,024 % des Korpus.
//
// Die beiden Funde sitzen zehn Zeilen auseinander, ihre contextHash-Fenster
// beruehren sich also nicht: der zweite Treffer kann NUR vom Fingerprint
// kommen und nicht von der zweiten Match-Quelle.
var
  Nur1   : TObjectList<TLeakFinding>;
  Beide  : TObjectList<TLeakFinding>;
  Dropped: Integer;
begin
  FPasFile      := TempGuidPath('.pas');
  FBaselineFile := TempGuidPath('.baseline.json');
  TFile.WriteAllText(FPasFile, OVERLOAD_BODY, TEncoding.UTF8);

  Nur1 := TObjectList<TLeakFinding>.Create(True);
  try
    // Die Baseline kennt NUR den ersten Overload.
    Nur1.Add(TLeakFinding.New(FPasFile, 'DoWork', OVERLOAD_LINE_A,
      CC_SCORE_11, fkCyclomaticComplexity));
    Assert.AreEqual<Integer>(1,
      TBaseline.Write(Nur1, FBaselineFile, TBaselineScope.ByFileName),
      'Vorbedingung: genau ein Eintrag steht in der Baseline');
  finally
    Nur1.Free;
  end;

  Beide := TObjectList<TLeakFinding>.Create(True);
  try
    Beide.Add(TLeakFinding.New(FPasFile, 'DoWork', OVERLOAD_LINE_A,
      CC_SCORE_11, fkCyclomaticComplexity));
    Beide.Add(TLeakFinding.New(FPasFile, 'DoWork', OVERLOAD_LINE_B,
      CC_SCORE_12, fkCyclomaticComplexity));
    Dropped := TBaseline.Apply(Beide, FBaselineFile,
      TBaselineScope.ByFileName);
    Assert.AreEqual<Integer>(2, Dropped,
      'DIE KOSTEN: ein Eintrag blendet BEIDE gleichnamigen Methoden aus - ' +
      '185 solcher Faelle auf rw20, gemessen und akzeptiert');
    Assert.AreEqual<Integer>(0, Beide.Count,
      'und es bleibt kein Fund uebrig');
  finally
    Beide.Free;
  end;
end;

procedure TTestBaselineMetricFingerprint.VerschiedeneMethoden_BleibenGetrennt;
// (i) REGRESSIONSSCHUTZ - die Grenze zu (h). Der Methodenname bleibt Teil
// des Fingerprints. Fiele er mit, waere aus den 185 gemessenen Kollisionen
// eine je Datei und Regel geworden: eine Baseline-Zeile legte dann alle
// komplexen Methoden einer Unit still.
begin
  Assert.AreNotEqual(
    Fp(fkCyclomaticComplexity, METHOD_A, CC_SCORE_11),
    Fp(fkCyclomaticComplexity, METHOD_B, CC_SCORE_11),
    'verschiedene Methoden bleiben verschiedene Funde');
end;

procedure TTestBaselineMetricFingerprint.LeererMethodName_LaesstNurNochEineIdentitaetJeDatei;
// (j) OHNE DEN ZWEIG ROT - und das ist hier kein Erfolg, sondern DIE
// BEKANNTE GRENZE, schriftlich festgehalten statt stillschweigend in Kauf
// genommen.
//
// (i) haelt fest, dass der Methodenname weiter trennt. Dieser Test haelt
// fest, was passiert, wenn es keinen gibt: dann ist der Detailtext der
// letzte Unterscheider zweier Funde derselben Datei - und genau den
// normalisiert der Zweig weg. Zwei verschiedene Methoden mit
// verschiedenen Scores teilen dann EINEN Fingerprint, ein Baseline-Eintrag
// blendet beide aus. Es gilt dann die annahmefreie Obergrenze: ein
// Fingerprint je Datei und Regel, an rw20 waeren das 20.194 statt 185.
//
// WIE WAHRSCHEINLICH IST DAS? Bei diesen vier Regeln nicht beobachtet.
// Alle vier lesen MethodName aus M.Name und brauchen einen RUMPF (Score,
// Statements, Verschachtelung); das Headless-Method-Muster
// (uParser2.pas:178) erzeugt nkMethod OHNE nkBlock - also gar keinen Fund -
// und laesst den Namen intakt. In rw20 traegt kein einziger Fund der vier
// Regeln einen leeren Namen. Wer die Menge aber um eine Regel erweitert,
// die MethodName nicht setzt (SCA091 und SCA062 tun das nicht, SCA021 und
// SCA101 auch nicht), bekommt genau dieses Verhalten - und dieser Test
// sagt ihm, was er dann eingekauft hat.
begin
  Assert.AreEqual(
    Fp(fkCyclomaticComplexity, '', CC_SCORE_11),
    Fp(fkCyclomaticComplexity, '', CC_SCORE_12),
    'BEKANNTE GRENZE: ohne Methodennamen bleibt nach der Normalisierung ' +
    'kein Unterscheider - ein Fingerprint je Datei und Regel');
  // Gegenprobe, damit der Test nicht versehentlich alles gleichsetzt: der
  // DETEKTOR-TYP trennt weiter, auch bei leerem Namen.
  Assert.AreNotEqual(
    Fp(fkCyclomaticComplexity, '', CC_SCORE_11),
    Fp(fkCognitiveComplexity, '', CC_SCORE_11),
    'verschiedene Regeln bleiben verschiedene Funde');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestBaselineMetricFingerprint);

end.
