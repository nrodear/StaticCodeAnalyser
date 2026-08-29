unit uTestEvidenceTiering;

// K2 Stufe 1+2 (Konzept_FpUnter5Prozent_2026-08-26): Evidenz-Politik.
// uEvidenceTiering ist fester Pipeline-Schritt (nach Suppression, VOR
// PathOverrides) - die Tests sichern die Deckel-Matrix, die Diagnose-
// Ausnahme, den Nutzer-Vorrang der PathOverrides und den Trust-Budget-
// Demote von SCA001 (Governance-Pin, s.u.).

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,
  uSCAConsts, uMethodd12, uEvidenceTiering, uPathOverrides;

type
  [TestFixture]
  TTestEvidenceTiering = class
  private
    function MakeFinding(AKind: TFindingKind; ASev: TLeakSeverity;
      AConf: TFindingConfidence): TLeakFinding;
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure HighError_BleibtError;
    [Test] procedure MediumError_WirdWarning;
    [Test] procedure LowFunde_WerdenHint;
    [Test] procedure Deckel_HebtNieAn;
    [Test] procedure FileReadError_BleibtUnangetastet;
    [Test] procedure RueckgabeZaehltNurGedeckelte;
    [Test] procedure PathOverride_Hochstufung_GewinntGegenDenDeckel;
    [Test] procedure MemoryLeak_DefaultKonfidenz_IstMedium;
    [Test] procedure NilDeref_DefaultKonfidenz_IstMedium;
    // Gegenpruefung 2026-08-26 (MAJOR): der Deckel zieht die Severity-
    // Schwelle nach - gedeckelte Funde duerfen einen error-only-Report
    // nicht unterlaufen.
    [Test] procedure MinSevError_GedeckelterFund_WirdEntfernt;
    [Test] procedure MinSevError_HighError_Bleibt;
    // Detektor-Aussage ueberlebt das Deckeln (Fund 29.08.)
    [Test] procedure Deckel_SichertDieDetektorSchwere;
    [Test] procedure ZweiterUeberschreiber_HaeltDieErsteSicherung;
  end;

implementation

function TTestEvidenceTiering.MakeFinding(AKind: TFindingKind;
  ASev: TLeakSeverity; AConf: TFindingConfidence): TLeakFinding;
begin
  Result := TLeakFinding.Create;
  Result.FileName   := 'src\probe.pas';
  Result.MethodName := '';
  Result.LineNumber := '1';
  Result.MissingVar := 'x';
  Result.SetKind(AKind);
  // NACH SetKind: SetKind setzt KindDefaultConfidence, der Test braucht
  // aber eine DEFINIERTE Konfidenz je Fall (genau das ist der Je-Fund-
  // Pfad, den Detektoren wie uUninitVar produktiv gehen).
  Result.Confidence := AConf;
  Result.Severity   := ASev;
end;

procedure TTestEvidenceTiering.Setup;
begin
  TPathOverrides.Clear;
end;

procedure TTestEvidenceTiering.TearDown;
// Regeln nie in andere Fixtures leaken (globaler Rule-State).
begin
  TPathOverrides.Clear;
end;

procedure TTestEvidenceTiering.HighError_BleibtError;
var
  L: TObjectList<TLeakFinding>;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding(fkMemoryLeak, lsError, fcHigh));
    Assert.AreEqual<Integer>(0, TEvidenceTiering.ApplyToFindings(L),
      'fcHigh wird nie gedeckelt');
    Assert.IsTrue(L[0].Severity = lsError, 'Error bleibt Error');
  finally
    L.Free;
  end;
end;

procedure TTestEvidenceTiering.MediumError_WirdWarning;
var
  L: TObjectList<TLeakFinding>;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding(fkSQLInjection, lsError, fcMedium));
    Assert.AreEqual<Integer>(1, TEvidenceTiering.ApplyToFindings(L));
    Assert.IsTrue(L[0].Severity = lsWarning,
      'fcMedium traegt hoechstens Warning ("Error = bewiesen")');
  finally
    L.Free;
  end;
end;

procedure TTestEvidenceTiering.LowFunde_WerdenHint;
var
  L: TObjectList<TLeakFinding>;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding(fkUseAfterFree, lsError,   fcLow));
    L.Add(MakeFinding(fkUseAfterFree, lsWarning, fcLow));
    Assert.AreEqual<Integer>(2, TEvidenceTiering.ApplyToFindings(L));
    Assert.IsTrue(L[0].Severity = lsHint, 'fcLow: Error -> Hint');
    Assert.IsTrue(L[1].Severity = lsHint, 'fcLow: Warning -> Hint');
  finally
    L.Free;
  end;
end;

procedure TTestEvidenceTiering.Deckel_HebtNieAn;
var
  L: TObjectList<TLeakFinding>;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    // Ein fcHigh-Hint bleibt Hint - der Deckel ist KEINE Buehne nach
    // oben, sonst wuerde die Politik Katalog-Severities ueberschreiben.
    L.Add(MakeFinding(fkTodoComment, lsHint, fcHigh));
    L.Add(MakeFinding(fkNilDeref,    lsWarning, fcMedium));
    Assert.AreEqual<Integer>(0, TEvidenceTiering.ApplyToFindings(L));
    Assert.IsTrue(L[0].Severity = lsHint,    'Hint bleibt Hint');
    Assert.IsTrue(L[1].Severity = lsWarning, 'Warning bleibt Warning');
  finally
    L.Free;
  end;
end;

procedure TTestEvidenceTiering.FileReadError_BleibtUnangetastet;
var
  L: TObjectList<TLeakFinding>;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    // Diagnose-Befund: dieselbe Ausnahme wie in uConfidenceFilter/
    // uPathOverrides/uBaseline - ein Lesefehler darf nie leiser werden,
    // egal welche Konfidenz er traegt.
    L.Add(MakeFinding(fkFileReadError, lsError, fcLow));
    Assert.AreEqual<Integer>(0, TEvidenceTiering.ApplyToFindings(L));
    Assert.IsTrue(L[0].Severity = lsError, 'Diagnose bleibt Error');
  finally
    L.Free;
  end;
end;

procedure TTestEvidenceTiering.RueckgabeZaehltNurGedeckelte;
var
  L: TObjectList<TLeakFinding>;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding(fkSQLInjection, lsError,   fcMedium)); // gedeckelt
    L.Add(MakeFinding(fkMemoryLeak,   lsError,   fcHigh));   // bleibt
    L.Add(MakeFinding(fkTodoComment,  lsHint,    fcMedium)); // schon drunter
    Assert.AreEqual<Integer>(1, TEvidenceTiering.ApplyToFindings(L),
      'nur der eine Error->Warning-Fall zaehlt');
    Assert.AreEqual<Integer>(3, L.Count, 'der Deckel entfernt NIE Befunde');
  finally
    L.Free;
  end;
end;

procedure TTestEvidenceTiering.PathOverride_Hochstufung_GewinntGegenDenDeckel;
var
  L: TObjectList<TLeakFinding>;
begin
  // Pipeline-Reihenfolge: Deckel VOR PathOverrides - die explizite
  // Nutzer-Hochstufung je Pfad (poaSeverityError) behaelt das letzte
  // Wort gegen die Politik (Gegenpruefung K2). Der Test faehrt beide
  // Schritte in Produktions-Reihenfolge.
  TPathOverrides.AddRule('src/*.pas', poaSeverityError, [], True);
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding(fkSQLInjection, lsError, fcMedium));
    TEvidenceTiering.ApplyToFindings(L);
    Assert.IsTrue(L[0].Severity = lsWarning, 'Vorbedingung: Deckel griff');
    TPathOverrides.ApplyToFindings(L);
    Assert.IsTrue(L[0].Severity = lsError,
      'poaSeverityError stuft NACH dem Deckel wieder hoch - Nutzer gewinnt');
  finally
    L.Free;
  end;
end;

procedure TTestEvidenceTiering.MinSevError_GedeckelterFund_WirdEntfernt;
var
  L: TObjectList<TLeakFinding>;
begin
  // Szenario der Gegenpruefung: MinSeverity=error laesst den fcMedium-
  // Error im Detector-Loop passieren (dort ist er noch Error); der
  // Deckel macht ihn zu Warning - in einem error-only-Report darf er
  // dann nicht stehen bleiben.
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding(fkSQLInjection, lsError, fcMedium));
    TEvidenceTiering.ApplyToFindings(L, lsError);
    Assert.AreEqual<Integer>(0, L.Count,
      'gedeckelter Fund reisst die error-Schwelle -> entfernt');
  finally
    L.Free;
  end;
end;

procedure TTestEvidenceTiering.MinSevError_HighError_Bleibt;
var
  L: TObjectList<TLeakFinding>;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding(fkMemoryLeak,    lsError, fcHigh));
    L.Add(MakeFinding(fkFileReadError, lsError, fcLow));
    Assert.AreEqual<Integer>(0, TEvidenceTiering.ApplyToFindings(L, lsError));
    Assert.AreEqual<Integer>(2, L.Count,
      'fcHigh-Error und Diagnose ueberleben die error-Schwelle');
  finally
    L.Free;
  end;
end;

procedure TTestEvidenceTiering.MemoryLeak_DefaultKonfidenz_IstMedium;
begin
  // GOVERNANCE-PIN (K2 Stufe 2): SCA001 steht wegen 62-78 % Korpus-FP
  // (Voll-Audit 2026-08-15) auf fcMedium. Wer diesen Test rot macht,
  // will SCA001 re-promoten - das ist NUR mit frischer Korpus-Messung
  // unter 5 % FP je Evidenzpfad zulaessig (Trust-Budget, Konzept
  // FpUnter5Prozent). Der Pin schuetzt vor versehentlichem Zuruecksetzen.
  Assert.IsTrue(KindDefaultConfidence(fkMemoryLeak) = fcMedium,
    'SCA001 Trust-Budget-Demote (62-78 % FP) darf nicht ohne Messung kippen');
end;

procedure TTestEvidenceTiering.NilDeref_DefaultKonfidenz_IstMedium;
begin
  // GOVERNANCE-PIN (Autopsie 2026-08-27): SCA008 steht wegen 44/48
  // Korpus-FP (91,7 %) auf fcMedium und ist damit aus dem Error-Tier
  // raus. Wer diesen Test rot macht, will SCA008 re-promoten - zulaessig
  // NUR nach den kartierten Gates MIT frischer Korpus-Messung
  // (Konzept_FpUeber50Prozent_2026-08-27.md). fcLow waere die andere
  // falsche Richtung: die Regel findet echte AVs (DDUtil.pas:868).
  Assert.IsTrue(KindDefaultConfidence(fkNilDeref) = fcMedium,
    'SCA008 Autopsie-Demote (91,7 % FP) darf nicht ohne Messung kippen');
end;

procedure TTestEvidenceTiering.Deckel_SichertDieDetektorSchwere;
// Ohne diese Sicherung ist nach dem Deckeln nicht mehr feststellbar, was
// der Detektor gemeint hat. Bei SCA001 unterscheidet genau das die
// Fund-Varianten - und der Deckel trifft dort JEDEN Fund.
var
  L : TObjectList<TLeakFinding>;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(TLeakFinding.New('a.pas', 'M', 1, 'x', fkMemoryLeak));
    L[0].Severity   := lsError;
    L[0].Confidence := fcMedium;
    Assert.AreEqual<Integer>(Ord(lsError), Ord(L[0].OriginalSeverity),
      'vor dem Deckeln ist Severity selbst die Detektor-Aussage');

    TEvidenceTiering.ApplyToFindings(L);

    Assert.AreEqual<Integer>(Ord(lsWarning), Ord(L[0].Severity),
      'gedeckelt');
    Assert.AreEqual<Integer>(Ord(lsError), Ord(L[0].OriginalSeverity),
      'Detektor-Aussage erhalten');
  finally
    L.Free;
  end;
end;

procedure TTestEvidenceTiering.ZweiterUeberschreiber_HaeltDieErsteSicherung;
// Politik und PathOverrides koennen NACHEINANDER auf denselben Fund
// greifen (Pipeline-Schritte 3 und 4). Die Aussage des Detektors gibt es
// aber nur einmal - der zweite Schreiber darf sie nicht durch die
// gedeckelte Zwischenstufe ersetzen.
var
  F : TLeakFinding;
begin
  F := TLeakFinding.New('a.pas', 'M', 1, 'x', fkMemoryLeak);
  try
    F.Severity := lsError;
    F.OverrideSeverity(lsWarning);   // wie die Politik
    F.OverrideSeverity(lsHint);      // wie ein PathOverride danach
    Assert.AreEqual<Integer>(Ord(lsHint), Ord(F.Severity),
      'der letzte Schreiber bestimmt die angezeigte Schwere');
    Assert.AreEqual<Integer>(Ord(lsError), Ord(F.OriginalSeverity),
      'aber die Detektor-Aussage bleibt die erste');
  finally
    F.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEvidenceTiering);

end.
