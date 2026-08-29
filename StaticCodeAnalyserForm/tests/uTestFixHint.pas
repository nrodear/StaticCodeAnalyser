unit uTestFixHint;

// Tests fuer TFixHintResolver (uFixHint) - Schwerpunkt Memoize-Cache.
//
// Hintergrund (Fix 2026-07-26): der Cache-Key war
//   (Ord(Kind) shl 8) or Ord(Severity)
// fkMemoryLeak / SCA001 ist der einzige der Hand-Branches, der zusaetzlich
// Finding.MissingVar auswertet und daraus eine eigene Variante bildet
// ("Rueckgabewert" vs. "Free ausserhalb finally"). Beide sind lsWarning und
// fielen damit auf denselben Cache-Slot: der ERSTE SCA001-Treffer eines
// Scans fuellte den Cache, jeder weitere bekam Description UND Before/After
// der falschen Variante - sichtbar im IDE-Panel, im Hover-Overlay und in
// jedem Export (Jira / Clipboard / HTML / Claude-Prompt).
//
// Der Fix erweitert den Key um ein Variantenbit
//   Kind shl 9 | Severity shl 1 | HintVariant
// statt fkMemoryLeak vom Memoize auszunehmen - SCA001 ist der
// volumenstaerkste Detektor, ein Build()-Aufruf pro Fund waere genau die
// Gettext-plus-3-KB-Allokation, gegen die der Cache eingefuehrt wurde.
//
// Assertion-Strategie: geprueft wird gegen Marker in Before/After. Die sind
// laut uFixHint-Header grundsaetzlich Englisch und laufen NICHT durch _(),
// waehrend Description lokalisiert ist - ein Description-Vergleich wuerde
// den Test von der aktiven UI-Sprache abhaengig machen. Description wird
// deshalb nur auf "nicht leer" und "unterscheidet sich" geprueft.

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,   // TObjectList - ApplyToFindings
  uSCAConsts, uMethodd12, uFixHint,
  uEvidenceTiering,   // der Deckel, der den Bug vom 29.08. ausloeste
  uLocalization;   // SetLanguage/CurrentLanguage - LanguageChangeInvalidatesCache

type
  [TestFixture]
  TTestFixHint = class
  public
    // (a) Regressions-Anker fuer den Memoize-Bug: zwei SCA001-Findings mit
    //     unterschiedlicher MissingVar-Auspraegung, nacheinander durch
    //     FixHint geschickt, muessen jeweils ihre EIGENE Variante bekommen.
    //     Vor dem Fix rot (zweiter Fund erbt den Hint des ersten).
    [Test] procedure MemoryLeakVariantsAreNotSharedAcrossCacheHits;
    // Auch in umgekehrter Aufruf-Reihenfolge - stellt sicher, dass keine
    // der beiden Varianten die andere "gewinnt".
    [Test] procedure MemoryLeakVariantsAreStableInReverseOrder;
    // (b) Gegenprobe: der Cache arbeitet weiter. Zwei Findings derselben
    //     Variante (nur anderer Variablenname) liefern identische Hints.
    [Test] procedure IdenticalVariantsStillShareTheSameHint;
    // Severity-Trennung: der lsError-Zweig ("nie freigegeben") darf nicht
    // mit den lsWarning-Varianten kollidieren.
    [Test] procedure ErrorVariantDiffersFromWarningVariants;
    // Der Rueckgabewert-Marker darf NICHT versehentlich bei einem
    // lsError-Fund greifen: Build wertet dort MissingVar gar nicht aus,
    // also muss auch die Cache-Diskriminante dort neutral bleiben.
    [Test] procedure ReturnValueSuffixIsIgnoredForErrorSeverity;
    // Ein Nicht-SCA001-Kind darf durch das Variantenbit nicht verschoben
    // werden - gleiche Eingabe, gleicher Hint, unabhaengig von MissingVar.
    [Test] procedure OtherKindsIgnoreMissingVar;
    // Sprachwechsel-Waechter (2026-08-19).
    [Test] procedure LanguageChangeInvalidatesCache;
    // (b) Regressions-Anker fuer den Fund vom 29.08.: die Evidenz-Politik
    //     deckelt JEDEN fkMemoryLeak auf lsWarning, danach darf der Hint
    //     die Varianten trotzdem noch auseinanderhalten.
    [Test] procedure CappedErrorStillGetsTheLeakHint;
    [Test] procedure MemoryLeakVariantNamesTheThreeForms;
    [Test] procedure ReturnValueSuffixIsSharedWithProduction;
  end;

implementation

const
  // Muss identisch zu uLeakDetector2 / uFixHint sein. Bewusst als
  // #$FC-Escape statt Literal-Umlaut - so ist die Testdatei ASCII und
  // kann kein Encoding-Drift-Opfer werden.
  SFX_RETURN_VALUE = ' - R'#$FC'ckgabewert';

  // Marker, die jede der drei fkMemoryLeak-Varianten eindeutig
  // identifizieren (je genau ein Vorkommen in uFixHint.pas):
  MARK_ERROR   = 'ReportMemoryLeaksOnShutdown'; // lsError: nie freigegeben
  MARK_RETURN  = 'BuildList()';                 // lsWarning: Rueckgabewert
  MARK_FINALLY = 'too late!';                   // lsWarning: Free ausserhalb finally

// Baut einen SCA001-Befund so, wie ihn uLeakDetector2.AddFinding erzeugt:
// SetKind setzt die Default-Severity, der Detektor ueberschreibt sie
// danach kontextabhaengig.
function MakeLeak(const AMissingVar: string;
  ASeverity: TLeakSeverity): TLeakFinding;
begin
  Result := TLeakFinding.New('Demo.pas', 'DoWork', 42, AMissingVar,
    fkMemoryLeak);
  Result.Severity := ASeverity;
end;

procedure TTestFixHint.MemoryLeakVariantsAreNotSharedAcrossCacheHits;
var
  FRet, FFin : TLeakFinding;
  HRet, HFin : TFixHint;
begin
  FRet := MakeLeak('list1' + SFX_RETURN_VALUE, lsWarning);
  try
    FFin := MakeLeak('list2', lsWarning);
    try
      // Reihenfolge ist der Kern des Bugs: der erste Aufruf fuellt den Slot.
      HRet := TFixHintResolver.FixHint(FRet);
      HFin := TFixHintResolver.FixHint(FFin);

      Assert.Contains(HRet.Before + HRet.After, MARK_RETURN,
        'Rueckgabewert-Variante liefert nicht ihren eigenen Before/After - ' +
        'Memoize-Key unterscheidet die SCA001-Varianten nicht');
      Assert.Contains(HFin.Before + HFin.After, MARK_FINALLY,
        'Free-ausserhalb-finally-Variante hat den Hint des vorherigen ' +
        'Fundes geerbt (Memoize-Bug)');

      Assert.IsNotEmpty(HRet.Description, 'Rueckgabewert: Description leer');
      Assert.IsNotEmpty(HFin.Description, 'FinallyOutside: Description leer');
      Assert.AreNotEqual(HRet.Description, HFin.Description,
        'Beide SCA001-Varianten liefern dieselbe Description');
      Assert.AreNotEqual(HRet.Before, HFin.Before,
        'Beide SCA001-Varianten liefern dasselbe Before-Beispiel');
      Assert.AreNotEqual(HRet.After, HFin.After,
        'Beide SCA001-Varianten liefern dasselbe After-Beispiel');
    finally
      FFin.Free;
    end;
  finally
    FRet.Free;
  end;
end;

procedure TTestFixHint.MemoryLeakVariantsAreStableInReverseOrder;
var
  FFin, FRet : TLeakFinding;
  HFin, HRet : TFixHint;
begin
  FFin := MakeLeak('other1', lsWarning);
  try
    FRet := MakeLeak('other2' + SFX_RETURN_VALUE, lsWarning);
    try
      // Umgekehrte Reihenfolge zum Test oben.
      HFin := TFixHintResolver.FixHint(FFin);
      HRet := TFixHintResolver.FixHint(FRet);

      Assert.Contains(HFin.Before + HFin.After, MARK_FINALLY,
        'FinallyOutside-Variante falsch (Reverse-Order)');
      Assert.Contains(HRet.Before + HRet.After, MARK_RETURN,
        'Rueckgabewert-Variante hat den zuvor gecachten Hint geerbt ' +
        '(Reverse-Order)');
    finally
      FRet.Free;
    end;
  finally
    FFin.Free;
  end;
end;

procedure TTestFixHint.IdenticalVariantsStillShareTheSameHint;
var
  FA, FB : TLeakFinding;
  HA, HB : TFixHint;
begin
  // Gegenprobe zum Fix: das Variantenbit darf den Cache nicht aushebeln.
  // Zwei Funde derselben Variante (nur anderer Variablenname) muessen
  // denselben Slot treffen -> byte-identische Hints.
  FA := MakeLeak('cacheA', lsWarning);
  try
    FB := MakeLeak('cacheB', lsWarning);
    try
      HA := TFixHintResolver.FixHint(FA);
      HB := TFixHintResolver.FixHint(FB);

      Assert.AreEqual(HA.Description, HB.Description,
        'Cache greift nicht mehr: gleiche Variante, andere Description');
      Assert.AreEqual(HA.Before, HB.Before,
        'Cache greift nicht mehr: gleiche Variante, anderes Before');
      Assert.AreEqual(HA.After, HB.After,
        'Cache greift nicht mehr: gleiche Variante, anderes After');
    finally
      FB.Free;
    end;
  finally
    FA.Free;
  end;

  // Dieselbe Gegenprobe fuer die Rueckgabewert-Variante.
  FA := MakeLeak('retA' + SFX_RETURN_VALUE, lsWarning);
  try
    FB := MakeLeak('retB' + SFX_RETURN_VALUE, lsWarning);
    try
      HA := TFixHintResolver.FixHint(FA);
      HB := TFixHintResolver.FixHint(FB);
      Assert.AreEqual(HA.Before, HB.Before,
        'Cache greift nicht mehr (Rueckgabewert-Variante)');
      Assert.AreEqual(HA.After, HB.After,
        'Cache greift nicht mehr (Rueckgabewert-Variante)');
    finally
      FB.Free;
    end;
  finally
    FA.Free;
  end;
end;

procedure TTestFixHint.ErrorVariantDiffersFromWarningVariants;
var
  FErr, FWarn : TLeakFinding;
  HErr, HWarn : TFixHint;
begin
  FErr := MakeLeak('leaked', lsError);
  try
    FWarn := MakeLeak('late', lsWarning);
    try
      HErr  := TFixHintResolver.FixHint(FErr);
      HWarn := TFixHintResolver.FixHint(FWarn);

      Assert.Contains(HErr.Before + HErr.After, MARK_ERROR,
        'lsError-Variante liefert nicht den Leak-Hint');
      Assert.Contains(HWarn.Before + HWarn.After, MARK_FINALLY,
        'lsWarning-Variante liefert nicht den finally-Hint');
      Assert.AreNotEqual(HErr.Description, HWarn.Description,
        'lsError und lsWarning teilen sich einen Cache-Slot');
    finally
      FWarn.Free;
    end;
  finally
    FErr.Free;
  end;
end;

procedure TTestFixHint.ReturnValueSuffixIsIgnoredForErrorSeverity;
var
  FA, FB : TLeakFinding;
  HA, HB : TFixHint;
begin
  // Build prueft bei lsError gar nicht erst MissingVar - der Leak-Zweig
  // gewinnt. Die Cache-Diskriminante muss dieselbe Reihenfolge spiegeln,
  // sonst entstehen zwei Slots mit identischem Inhalt.
  FA := MakeLeak('e1', lsError);
  try
    FB := MakeLeak('e2' + SFX_RETURN_VALUE, lsError);
    try
      HA := TFixHintResolver.FixHint(FA);
      HB := TFixHintResolver.FixHint(FB);
      Assert.Contains(HA.Before + HA.After, MARK_ERROR,
        'lsError ohne Suffix: falscher Hint');
      Assert.Contains(HB.Before + HB.After, MARK_ERROR,
        'lsError MIT Rueckgabewert-Suffix darf nicht in den ' +
        'Rueckgabewert-Zweig rutschen');
      Assert.AreEqual(HA.Description, HB.Description,
        'lsError-Funde muessen unabhaengig von MissingVar denselben ' +
        'Hint bekommen');
    finally
      FB.Free;
    end;
  finally
    FA.Free;
  end;
end;

procedure TTestFixHint.LanguageChangeInvalidatesCache;
// Der Memoize-Cache haelt eine FERTIG LOKALISIERTE Description: der
// Katalog-Zweig in Build schickt Meta.ShortDescription durch _(), und
// die Hand-Zweige tun dasselbe. Geleert wurde der Cache bis 2026-08-19
// nur in der finalization - wer zur Laufzeit die Sprache umstellte
// (Plugin ueber Tools > Options, EXE ueber das Hamburger-Menue), sah
// seine Hints bis zum Prozessende weiter in der alten Sprache, waehrend
// Regelnamen und Oberflaeche daneben schon umgestellt waren.
//
// Geprueft wird die INVALIDIERUNG, nicht der Wortlaut: ob eine bestimmte
// msgid in der .po steht, ist Sache der Katalogpflege und wuerde diesen
// Test an sie binden. Der Beweis ist, dass nach dem Sprachwechsel ein
// NEUES Build laeuft - sichtbar daran, dass die Description danach zur
// dann aktiven Sprache passt, also der Wert vor und nach dem
// Zuruecksetzen wieder identisch ist.
var
  F        : TLeakFinding;
  Vorher   : TFixHint;
  Fremd    : TFixHint;
  Zurueck  : TFixHint;
  AlteSpr  : string;
begin
  // EIN try/finally mit nil-Vorbelegung statt zweier verschachtelter:
  // NestedTry meldet die Schachtelung sonst im Selbstscan, und Free auf
  // nil ist in Delphi zulaessig (TObject.Free prueft Self).
  AlteSpr := CurrentLanguage;
  F := nil;
  try
    SetLanguage('en');
    F := TLeakFinding.New('Demo.pas', 'DoWork', 7, 'x', fkEmptyExcept);
    Vorher := TFixHintResolver.FixHint(F);
    SetLanguage('de');
    Fremd := TFixHintResolver.FixHint(F);
    SetLanguage('en');
    Zurueck := TFixHintResolver.FixHint(F);
    Assert.IsNotEmpty(Vorher.Description,
      'Description leer - Fixture trifft den Detektor nicht');
    Assert.AreEqual(Vorher.Description, Zurueck.Description,
      'nach dem Rueckwechsel muss wieder derselbe Text stehen');
    // Fremd darf gleich sein (wenn die .po den String nicht kennt), aber
    // nicht leer - ein geleerter Cache muss neu bauen, nicht einen
    // Leerwert liefern.
    Assert.IsNotEmpty(Fremd.Description,
      'nach dem Sprachwechsel wurde nicht neu gebaut');
  finally
    F.Free;
    SetLanguage(AlteSpr);
  end;
end;

procedure TTestFixHint.OtherKindsIgnoreMissingVar;
var
  FA, FB : TLeakFinding;
  HA, HB : TFixHint;
begin
  // Alle uebrigen Kinds werten MissingVar nicht aus - auch nicht, wenn der
  // SCA001-Suffix zufaellig im Text steht. Anker gegen ein zu breit
  // gefasstes Variantenbit.
  FA := TLeakFinding.New('Demo.pas', 'DoWork', 7, 'irgendwas', fkEmptyExcept);
  try
    FB := TLeakFinding.New('Demo.pas', 'DoWork', 9,
      'irgendwas' + SFX_RETURN_VALUE, fkEmptyExcept);
    try
      HA := TFixHintResolver.FixHint(FA);
      HB := TFixHintResolver.FixHint(FB);
      Assert.IsNotEmpty(HA.Description, 'fkEmptyExcept: Description leer');
      Assert.AreEqual(HA.Description, HB.Description,
        'Nicht-SCA001-Kind reagiert auf MissingVar');
      Assert.AreEqual(HA.Before, HB.Before,
        'Nicht-SCA001-Kind reagiert auf MissingVar (Before)');
      Assert.AreEqual(HA.After, HB.After,
        'Nicht-SCA001-Kind reagiert auf MissingVar (After)');
    finally
      FB.Free;
    end;
  finally
    FA.Free;
  end;
end;

procedure TTestFixHint.CappedErrorStillGetsTheLeakHint;
// DER REGRESSIONSTEST zum Fund vom 29.08. KindDefaultConfidence
// (fkMemoryLeak) ist fcMedium, also deckelt die Evidenz-Politik JEDEN
// SCA001-Fund auf lsWarning - am Referenzkorpus 568 von 568. Solange
// uFixHint dann Severity las, bekam jedes echte Leck den Hinweis "Free is
// outside the protecting finally block", also den Verweis auf ein Free,
// das es gar nicht gibt.
var
  L : TObjectList<TLeakFinding>;
  H : TFixHint;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeLeak('leaked', lsError));
    L[0].Confidence := fcMedium;   // wie KindDefaultConfidence(fkMemoryLeak)
    TEvidenceTiering.ApplyToFindings(L);

    Assert.AreEqual<Integer>(Ord(lsWarning), Ord(L[0].Severity),
      'Vorbedingung: die Politik hat wirklich gedeckelt');
    Assert.AreEqual<Integer>(Ord(lsError), Ord(L[0].OriginalSeverity),
      'die Detektor-Aussage ueberlebt den Deckel');

    H := TFixHintResolver.FixHint(L[0]);
    Assert.IsTrue(Pos(MARK_ERROR, H.After) > 0,
      'gedeckelter Error behaelt den "nie freigegeben"-Hinweis');
    Assert.AreEqual<Integer>(0, Pos(MARK_FINALLY, H.Before),
      'und bekommt NICHT den finally-Hinweis');
  finally
    L.Free;
  end;
end;

procedure TTestFixHint.MemoryLeakVariantNamesTheThreeForms;
// MemoryLeakVariant ist das, was der SARIF-Export als properties.variant
// ausgibt - ohne sie kann ein SARIF-Konsument die drei Formen nicht
// unterscheiden, weil der Meldetext nur den Variablennamen traegt.
var
  F : TLeakFinding;
begin
  F := MakeLeak('leaked', lsError);
  try
    Assert.AreEqual('never-freed', F.MemoryLeakVariant,
      'lsError = gar kein Free');
    // Deckeln aendert die VARIANTE nicht, nur die angezeigte Schwere.
    F.OverrideSeverity(lsWarning);
    Assert.AreEqual('never-freed', F.MemoryLeakVariant,
      'der Deckel darf die Variante nicht umdeuten');
  finally
    F.Free;
  end;

  F := MakeLeak('list' + SFX_RETURN_VALUE, lsWarning);
  try
    Assert.AreEqual('return-value-not-freed', F.MemoryLeakVariant,
      'Suffix in MissingVar = Rueckgabewert-Form');
  finally
    F.Free;
  end;

  F := MakeLeak('list', lsWarning);
  try
    Assert.AreEqual('freed-outside-finally', F.MemoryLeakVariant,
      'lsWarning ohne Suffix = Free neben dem finally');
    F.SetKind(fkSQLInjection);
    Assert.AreEqual('', F.MemoryLeakVariant,
      'jede andere Fundart hat keine Leck-Variante');
  finally
    F.Free;
  end;
end;

procedure TTestFixHint.ReturnValueSuffixIsSharedWithProduction;
// Die Konstante oben ist seit 2026-08-29 kein Duplikat mehr, sondern ein
// PIN: sie haelt den woertlichen Wert fest, den der Produktionscode
// benutzt. Der Suffix geht ueber MissingVar in den Baseline-Fingerprint -
// wer ihn aendert, entwertet jede Baseline, die solche Funde enthaelt.
begin
  Assert.AreEqual(SFX_RETURN_VALUE, LEAK_RETURN_VALUE_SUFFIX,
    'Testerwartung und Produktionskonstante muessen deckungsgleich sein');
end;

end.
