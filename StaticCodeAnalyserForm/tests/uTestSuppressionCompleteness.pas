unit uTestSuppressionCompleteness;

// Vollstaendigkeits-Test: jeder einzelne TFindingKind muss per
// `// noinspection <KindName>` unterdrueckt werden koennen.
//
// Hintergrund: TSuppression.KindFromName loest den im Kommentar genannten
// Namen ueber das KIND_META-Array auf. Wenn ein neuer Detektor ohne
// passenden KIND_META-Eintrag (oder mit Tippfehler) hinzukommt, fliegt
// die Suppression still durch und der Suppress-Marker wirkt nicht. Dieser
// Test deckt alle 161 Kinds in einem Rutsch ab und faengt Drift sofort.
//
// Drei Tests:
//   1. EveryKindNameResolvesViaKindFromName
//      KindFromName(KIND_META[K].Name) muss exakt K liefern.
//   2. EveryKindNameIsUnique
//      Keine zwei Kinds duerfen denselben KIND_META.Name haben (sonst
//      kollidiert die Suppression-Reverse-Aufloesung).
//   3. EveryKindCanBeSuppressedEndToEnd
//      Eine einzige Tmp-Datei mit allen 161 Suppress-Markern + je einer
//      Code-Zeile. Synthetische Findings (eines pro Kind) auf die
//      richtigen Code-Zeilen. ApplyToFindings muss alle 161 entfernen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSuppressionCompleteness = class
  public
    [Test] procedure EveryKindNameResolvesViaKindFromName;
    [Test] procedure EveryKindNameIsUnique;
    [Test] procedure EveryKindCanBeSuppressedEndToEnd;

    // ---- fkUnusedSuppression-EMISSION (Audit P4: war komplett ungetestet;
    //      Semantik empirisch validiert 2026-07-04 via CLI-Scan) ----------
    // Staler Marker wird gemeldet, wenn die Datei daneben einen
    // konsumierten Marker hat; Fundzeile = Marker-Zeile.
    [Test] procedure UnusedMarker_WithConsumedSiblingInFile_Reported;
    // Nur konsumierte Marker -> kein UnusedSuppression-Rauschen.
    [Test] procedure ConsumedMarkerOnly_NoUnusedFinding;
    // Audit #2a (2026-07-05) - Fix der frueher hier festgeschriebenen
    // Luecke: Marker werden jetzt zur SCAN-Zeit eingesammelt (ParseLeaks ->
    // TSuppression.CollectMarkersForScan), stale Marker werden auch dann
    // gemeldet, wenn KEIN Marker der Datei etwas konsumiert hat. Der Test
    // hiess vorher StaleMarkerOnly_KnownGap_NotReported und wurde mit dem
    // Fix BEWUSST gedreht (so hat es sein Kommentar gefordert).
    [Test] procedure StaleMarkerOnly_Reported;
    // Audit #2a: stale file-wide-Marker ('// noinspection-file') ohne je
    // ein konsumiertes Finding -> gemeldet, Fundzeile = Marker-Zeile.
    [Test] procedure StaleFileWideMarker_NoConsumption_Reported;
    // Audit #2c: deckt ein Finding BEIDE Marker-Ebenen ab (file-wide UND
    // per-line), werden BEIDE Consumed getagt - kein UnusedSuppression
    // fuer den Per-Line-Marker (vorher: exklusives if/else-if tagte nur
    // die file-wide-Ebene, der Per-Line-Marker galt faelschlich als stale).
    [Test] procedure FileWideAndPerLineBothCover_NoUnusedFinding;
    // Audit #2a, 0-Findings-Pfad: ApplyToFindings mit LEERER Findings-
    // Liste + PreMarkers emittiert die stalen Marker trotzdem (der alte
    // Count=0-Early-Exit gilt nur noch im Legacy-Modus ohne PreMarkers).
    // Direkt-Test: der Pipeline-Weg kann keine garantiert befund-freie
    // ROHE Detektor-Ausgabe erzeugen (irgendein Kind feuert vor dem
    // Confidence-Filter praktisch immer).
    [Test] procedure PreMarkers_EmptyFindingsList_StaleMarkersReported;
    // TD-1 Inkrement 2b: Unused-Emission liest EnabledKinds per-Scan (Zeiger)
    [Test] procedure PerScanEnabledKinds_GatesUnusedEmission;
    // Audit #2b: .dfm-Finding konsumiert einen Marker in der .pas-Host-
    // Datei; der stale Sibling-Marker dort wird mit FileName = .pas
    // gemeldet (vorher: FileName = .dfm bei MarkerLine aus der .pas -
    // Klick lief ins Leere). Legacy-Pfad (ohne PreMarkers); der Pipeline-
    // Weg braeuchte ein echtes DFM-Findings-Setup (DfmAnalysisRunner) und
    // ist hier bewusst nicht nachgebaut.
    [Test] procedure DfmFinding_StaleSiblingMarker_ReportedOnPasHost;

    // ---- Audit #10b (2026-07-05): Lesefehler ist kein stilles fail-open --
    // Marker-Host existiert, ist aber nicht lesbar (exklusiver Lock):
    // Original-Finding bleibt UNGEFILTERT stehen UND es gibt genau ein
    // fkFileReadError-Diagnose-Finding mit MSG_SUPPRESSION_READ_ERROR.
    [Test] procedure UnreadableMarkerHost_EmitsDiagnosticFinding;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes,
  System.Generics.Collections,
  uSCAConsts, uMethodd12, uSuppression,
  uTestFindingHelper;

procedure TTestSuppressionCompleteness.EveryKindNameResolvesViaKindFromName;
var
  K, Resolved : TFindingKind;
  Name        : string;
  Missing     : TStringList;
begin
  Missing := TStringList.Create;
  try
    for K := Low(TFindingKind) to High(TFindingKind) do
    begin
      Name := KIND_META[K].Name;
      // Leerer Name = bewusste Lookup-Sperre - aktuell nirgends, aber
      // der Vollstaendigkeit halber tolerant.
      if Name = '' then
      begin
        Missing.Add(Format('Kind ord=%d hat leeren KIND_META.Name', [Ord(K)]));
        Continue;
      end;
      if not KindFromName(Name, Resolved) then
        Missing.Add(Format('KindFromName(%s) liefert false - Reverse-Lookup '
          + 'broken', [Name]))
      else if Resolved <> K then
        Missing.Add(Format(
          'KindFromName(%s) liefert ord=%d statt erwarteter ord=%d (%s)',
          [Name, Ord(Resolved), Ord(K), KIND_META[K].Name]));
    end;
    Assert.AreEqual<Integer>(0, Missing.Count,
      'Fehlende oder falsche KIND_META->Kind Lookups:'#13#10 + Missing.Text);
  finally
    Missing.Free;
  end;
end;

procedure TTestSuppressionCompleteness.EveryKindNameIsUnique;
var
  K, Other    : TFindingKind;
  Duplicates  : TStringList;
begin
  Duplicates := TStringList.Create;
  try
    for K := Low(TFindingKind) to High(TFindingKind) do
    begin
      if KIND_META[K].Name = '' then Continue;
      // Guard gegen Succ(High) - waere Range-Check-Error mit {$R+}.
      if K = High(TFindingKind) then Continue;
      for Other := Succ(K) to High(TFindingKind) do
      begin
        if KIND_META[Other].Name = '' then Continue;
        if SameText(KIND_META[K].Name, KIND_META[Other].Name) then
          Duplicates.Add(Format(
            'KIND_META.Name "%s" ist doppelt: ord=%d UND ord=%d',
            [KIND_META[K].Name, Ord(K), Ord(Other)]));
      end;
    end;
    Assert.AreEqual<Integer>(0, Duplicates.Count,
      'Doppelte KIND_META-Namen (Suppression waere mehrdeutig):'#13#10 +
      Duplicates.Text);
  finally
    Duplicates.Free;
  end;
end;

procedure TTestSuppressionCompleteness.EveryKindCanBeSuppressedEndToEnd;
// Eine einzige Tmp-Datei mit Doppel-Zeilen-Layout:
//   Zeile (2i+1): // noinspection <KIND_META[K_i].Name>
//   Zeile (2i+2): pseudo := True; // i-te Code-Zeile, wo das Finding sitzt
//
// Synthetische Findings (eines pro Kind) auf Zeile (2i+2). Wenn die
// Suppression-Pipeline alle 161 Kinds kennt, muss die Liste nach
// ApplyToFindings leer sein.
var
  K          : TFindingKind;
  KindList   : TList<TFindingKind>;
  Lines      : TStringList;
  TempPath   : string;
  Findings   : TObjectList<TLeakFinding>;
  F          : TLeakFinding;
  i          : Integer;
  RemainingNames : TStringList;
begin
  // Alle Kinds mit non-leerem Namen sammeln (deterministischer Iter-Order).
  // fkFileReadError ist per Design von der Suppression ausgenommen
  // (uSuppression.ApplyToFindings, Z. 211) - Parser/IO-Fehler sollen
  // nicht silent weg-suppressed werden.
  KindList := TList<TFindingKind>.Create;
  try
    for K := Low(TFindingKind) to High(TFindingKind) do
      if (KIND_META[K].Name <> '') and (K <> fkFileReadError) then
        KindList.Add(K);

    // Tmp-Datei bauen: Suppression-Marker + Dummy-Code im Wechsel.
    Lines := TStringList.Create;
    try
      for i := 0 to KindList.Count - 1 do
      begin
        Lines.Add('// noinspection ' + KIND_META[KindList[i]].Name);
        Lines.Add('pseudo := True;');
      end;
      TempPath := TPath.Combine(TPath.GetTempPath,
        'sca_suppress_' + TGuid.NewGuid.ToString.Replace('{','').Replace('}','').Replace('-','')
        + '.pas');
      Lines.SaveToFile(TempPath, TEncoding.UTF8);
    finally
      Lines.Free;
    end;

    try
      // Findings synthetisieren: jeweils auf die Code-Zeile (2i+2).
      Findings := TObjectList<TLeakFinding>.Create(True);
      try
        for i := 0 to KindList.Count - 1 do
        begin
          F := TLeakFinding.Create;
          F.FileName   := TempPath;
          F.MethodName := '';
          F.LineNumber := IntToStr((i * 2) + 2);
          F.MissingVar := 'completeness-test';
          F.SetKind(KindList[i]);
          Findings.Add(F);
        end;

        // Pre-Check: alle Findings sind da.
        Assert.AreEqual(KindList.Count, Findings.Count,
          'Setup-Fehler: erwartete Findings-Zahl mismatch');

        TSuppression.ApplyToFindings(Findings);

        // Post-Check: alle muessten weggefiltert sein.
        if Findings.Count > 0 then
        begin
          RemainingNames := TStringList.Create;
          try
            for F in Findings do
              RemainingNames.Add(Format('Kind %s (ord=%d) Line=%s',
                [KIND_META[F.Kind].Name, Ord(F.Kind), F.LineNumber]));
            Assert.Fail(Format(
              '%d von %d Suppress-Markern haben nicht gewirkt:'#13#10 + '%s',
              [Findings.Count, KindList.Count, RemainingNames.Text]));
          finally
            RemainingNames.Free;
          end;
        end;
      finally
        Findings.Free;
      end;
    finally
      if TFile.Exists(TempPath) then
        TFile.Delete(TempPath);
    end;
  finally
    KindList.Free;
  end;
end;

procedure TTestSuppressionCompleteness.UnusedMarker_WithConsumedSiblingInFile_Reported;
// Konsumierter EmptyMethod-Marker + staler GotoStatement-Marker (kein goto
// im File). Erwartung: EmptyMethod unterdrueckt, genau 1 fkUnusedSuppression
// auf der stalen Marker-Zeile. (Pipeline-Weg: Suppression laeuft nur dort.)
const SRC =
  'unit t; interface implementation'#13#10 +
  '// noinspection EmptyMethod'#13#10 +
  'procedure Leer;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  '// noinspection GotoStatement'#13#10 +
  'procedure Voll;'#13#10 +
  'begin'#13#10 +
  '  Writeln(1);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyMethod),
      'EmptyMethod-Marker muss konsumiert sein');
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedSuppression),
      'genau 1 UnusedSuppression fuer den stalen GotoStatement-Marker');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'noinspection GotoStatement'),
      TFindingHelper.FirstOf(F, fkUnusedSuppression).LineNumber,
      'Fundzeile = Marker-Zeile');
  finally F.Free; end;
end;

procedure TTestSuppressionCompleteness.ConsumedMarkerOnly_NoUnusedFinding;
const SRC =
  'unit t; interface implementation'#13#10 +
  '// noinspection EmptyMethod'#13#10 +
  'procedure Leer;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyMethod),
      'Marker muss konsumiert sein');
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedSuppression),
      'konsumierter Marker darf nicht als unused gemeldet werden');
  finally F.Free; end;
end;

procedure TTestSuppressionCompleteness.StaleMarkerOnly_Reported;
// Datei hat Findings (Writeln etc.), aber KEIN Marker konsumiert etwas.
// Seit Audit #2a (2026-07-05, Scan-Zeit-Collection in ParseLeaks) wird
// der stale Per-Line-Marker trotzdem gemeldet - vorher wurde FileMarkers
// nur im Match-Zweig gebaut und der Marker blieb unsichtbar (der
// Vorgaenger-Test StaleMarkerOnly_KnownGap_NotReported schrieb das fest).
const SRC =
  'unit t; interface implementation'#13#10 +
  '// noinspection GotoStatement'#13#10 +
  'procedure Voll;'#13#10 +
  'begin'#13#10 +
  '  Writeln(1);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedSuppression),
      'staler Per-Line-Marker ohne Konsum muss gemeldet werden (Audit #2a)');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'noinspection GotoStatement'),
      TFindingHelper.FirstOf(F, fkUnusedSuppression).LineNumber,
      'Fundzeile = Marker-Zeile');
  finally F.Free; end;
end;

procedure TTestSuppressionCompleteness.StaleFileWideMarker_NoConsumption_Reported;
// File-wide-Marker fuer ein Kind, das im File nie feuert (kein goto).
// Muss seit Audit #2a als unused gemeldet werden - auch ohne dass
// irgendein anderer Marker der Datei konsumiert wurde.
const SRC =
  'unit t; interface implementation'#13#10 +
  '// noinspection-file GotoStatement'#13#10 +
  'procedure Voll;'#13#10 +
  'begin'#13#10 +
  '  Writeln(1);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedSuppression),
      'staler file-wide-Marker muss gemeldet werden (Audit #2a)');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'noinspection-file GotoStatement'),
      TFindingHelper.FirstOf(F, fkUnusedSuppression).LineNumber,
      'Fundzeile = Marker-Zeile des file-wide-Markers');
  finally F.Free; end;
end;

procedure TTestSuppressionCompleteness.FileWideAndPerLineBothCover_NoUnusedFinding;
// EIN EmptyMethod-Finding, abgedeckt von file-wide UND per-line Marker.
// Entfernt wird es (wie bisher) ueber die file-wide-Ebene; das Consumed-
// Tagging muss seit Audit #2c aber BEIDE deckenden Marker treffen - sonst
// wuerde der Per-Line-Marker faelschlich als unused gemeldet.
const SRC =
  'unit t; interface implementation'#13#10 +
  '// noinspection-file EmptyMethod'#13#10 +
  '// noinspection EmptyMethod'#13#10 +
  'procedure Leer;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsViaPipeline(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyMethod),
      'EmptyMethod-Finding muss suppresst sein (Entfernen unveraendert)');
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedSuppression),
      'BEIDE deckenden Marker sind Consumed - kein UnusedSuppression ' +
      'fuer den Per-Line-Marker (Audit #2c)');
  finally F.Free; end;
end;

procedure TTestSuppressionCompleteness.PreMarkers_EmptyFindingsList_StaleMarkersReported;
// Kuenstliches PreMarkers-Dictionary, wie es die Scan-Zeit-Collection
// baut (Key = Marker-Host-Pfad). Die Host-Datei muss NICHT existieren:
// bei leerer Findings-Liste liest die Unused-Emission nur das Dictionary.
var
  Findings : TObjectList<TLeakFinding>;
  Pre      : TObjectDictionary<string, TList<TSuppressionMarker>>;
  L        : TList<TSuppressionMarker>;
  M        : TSuppressionMarker;
  F        : TLeakFinding;
  HostPath : string;
  CntWide  : Integer;
  CntLine  : Integer;
begin
  HostPath := 'C:\virtuell\clean.pas';
  Pre      := TObjectDictionary<string, TList<TSuppressionMarker>>.Create([doOwnsValues]);
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    L := TList<TSuppressionMarker>.Create;
    M.MarkerLine := 3;                       // staler file-wide-Marker
    M.TargetLine := 0;
    M.Kinds      := [fkGotoStatement];
    M.Consumed   := False;
    L.Add(M);
    M.MarkerLine := 7;                       // staler per-line-Marker
    M.TargetLine := 8;
    M.Kinds      := [fkMemoryLeak];
    M.Consumed   := False;
    L.Add(M);
    Pre.Add(HostPath, L);                    // Ownership -> Pre (doOwnsValues)

    TSuppression.ApplyToFindings(Findings, Pre);

    Assert.AreEqual<Integer>(2, Findings.Count,
      'beide stalen Marker gemeldet - der Count=0-Early-Exit gilt im ' +
      'PreMarkers-Modus nicht mehr (Audit #2a)');
    CntWide := 0;
    CntLine := 0;
    for F in Findings do
    begin
      Assert.AreEqual<Integer>(Ord(fkUnusedSuppression), Ord(F.Kind),
        'nur fkUnusedSuppression erwartet');
      Assert.AreEqual(HostPath, F.FileName,
        'FileName = Marker-Host (Dictionary-Key)');
      if F.LineNumber = '3' then Inc(CntWide);
      if F.LineNumber = '7' then Inc(CntLine);
    end;
    Assert.AreEqual<Integer>(1, CntWide, 'file-wide-Marker (Zeile 3) gemeldet');
    Assert.AreEqual<Integer>(1, CntLine, 'per-line-Marker (Zeile 7) gemeldet');
  finally
    Findings.Free;
    Pre.Free;                                // Caller behaelt Ownership
  end;
end;

procedure TTestSuppressionCompleteness.PerScanEnabledKinds_GatesUnusedEmission;
// TD-1 Inkrement 2b (2026-07-06): die Unused-Emission liest EnabledKinds jetzt
// per-Scan ueber den AEnabledKinds-Zeiger statt vom Prozess-Global. Beweist
// beide Richtungen, GLOBAL-UNABHAENGIG (AEnabledKinds<>nil ignoriert das
// Global): Set MIT fkUnusedSuppression -> Gate offen, staler Marker gemeldet;
// Set OHNE fkUnusedSuppression -> Gate schliesst, nichts gemeldet.
var
  Findings : TObjectList<TLeakFinding>;
  Pre      : TObjectDictionary<string, TList<TSuppressionMarker>>;
  Kinds    : TFindingKinds;
  HostPath : string;

  function BuildPre: TObjectDictionary<string, TList<TSuppressionMarker>>;
  var
    LL : TList<TSuppressionMarker>;
    MM : TSuppressionMarker;
  begin
    Result := TObjectDictionary<string, TList<TSuppressionMarker>>.Create([doOwnsValues]);
    LL := TList<TSuppressionMarker>.Create;
    MM.MarkerLine := 3;                       // staler file-wide-Marker
    MM.TargetLine := 0;
    MM.Kinds      := [fkGotoStatement];
    MM.Consumed   := False;
    LL.Add(MM);
    Result.Add(HostPath, LL);                 // Ownership -> Result (doOwnsValues)
  end;

begin
  HostPath := 'C:\virtuell\perscan.pas';

  // Richtung 1: per-Scan-Set enthaelt fkUnusedSuppression + den Marker-Kind
  // -> Gate offen -> staler Marker wird gemeldet.
  Kinds    := [fkGotoStatement, fkUnusedSuppression];
  Findings := TObjectList<TLeakFinding>.Create(True);
  Pre      := BuildPre;
  try
    TSuppression.ApplyToFindings(Findings, Pre, @Kinds);
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(Findings, fkUnusedSuppression),
      'per-Scan-Set MIT fkUnusedSuppression -> staler Marker gemeldet');
  finally
    Findings.Free;
    Pre.Free;
  end;

  // Richtung 2: per-Scan-Set OHNE fkUnusedSuppression -> Gate schliesst ->
  // nichts gemeldet (Detektor in diesem Profil nicht aktiv), unabhaengig vom
  // Prozess-Global.
  Kinds    := [fkGotoStatement];
  Findings := TObjectList<TLeakFinding>.Create(True);
  Pre      := BuildPre;
  try
    TSuppression.ApplyToFindings(Findings, Pre, @Kinds);
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(Findings, fkUnusedSuppression),
      'per-Scan-Set OHNE fkUnusedSuppression -> Gate greift, nichts gemeldet');
  finally
    Findings.Free;
    Pre.Free;
  end;
end;

procedure TTestSuppressionCompleteness.DfmFinding_StaleSiblingMarker_ReportedOnPasHost;
// Marker-Host (.pas) mit konsumiertem MemoryLeak-Marker (Konsument ist
// ein synthetisches .dfm-Finding) + stalem GotoStatement-Marker. Die
// .dfm selbst muss nicht existieren - ResolveMarkerHostFile prueft nur
// die .pas. Erwartung (Audit #2b): das Unused-Finding zeigt auf die
// .pas (Host), nicht auf die .dfm; das Entfernen des .dfm-Findings
// bleibt unveraendert.
var
  TmpPas    : string;
  TmpDfm    : string;
  Findings  : TObjectList<TLeakFinding>;
  F         : TLeakFinding;
  UnusedF   : TLeakFinding;
  LeakCnt   : Integer;
  UnusedCnt : Integer;
begin
  TmpPas := TPath.Combine(TPath.GetTempPath,
    'sca_suppr_dfmhost_' + TGUID.NewGuid.ToString + '.pas');
  TmpDfm := ChangeFileExt(TmpPas, '.dfm');
  TFile.WriteAllText(TmpPas,
    '// noinspection MemoryLeak'#13#10 +
    'x := TStringList.Create;'#13#10 +
    '// noinspection GotoStatement'#13#10 +
    'y := 1;'#13#10);
  try
    Findings := TObjectList<TLeakFinding>.Create(True);
    try
      Findings.Add(TLeakFinding.New(TmpDfm, '', 2, 'x', fkMemoryLeak));
      TSuppression.ApplyToFindings(Findings);

      LeakCnt   := 0;
      UnusedCnt := 0;
      UnusedF   := nil;
      for F in Findings do
      begin
        if F.Kind = fkMemoryLeak then Inc(LeakCnt);
        if F.Kind = fkUnusedSuppression then
        begin
          Inc(UnusedCnt);
          UnusedF := F;
        end;
      end;
      Assert.AreEqual<Integer>(0, LeakCnt,
        '.dfm-Finding via .pas-Host-Marker suppresst (Entfernen unveraendert)');
      Assert.AreEqual<Integer>(1, UnusedCnt,
        'genau 1 UnusedSuppression fuer den stalen GotoStatement-Marker');
      Assert.AreEqual(TmpPas, UnusedF.FileName,
        'FileName = Marker-HOST (.pas), nicht die .dfm (Audit #2b)');
      Assert.AreEqual('3', UnusedF.LineNumber,
        'Fundzeile = Marker-Zeile in der .pas');
    finally
      Findings.Free;
    end;
  finally
    TFile.Delete(TmpPas);
  end;
end;

procedure TTestSuppressionCompleteness.UnreadableMarkerHost_EmitsDiagnosticFinding;
// Audit #10b: BuildMap/BuildMarkers liefen bei AcquireLines=nil still
// fail-open (leere Map, keine Spur). Jetzt: Original-Finding bleibt
// stehen + genau 1 fkFileReadError-Diagnose auf der Datei.
// Der Lesefehler wird ueber einen exklusiven Datei-Lock erzwungen
// (fmShareExclusive verhindert das Open von TStringList.LoadFromFile).
var
  TmpPath  : string;
  Lock     : TFileStream;
  Findings : TObjectList<TLeakFinding>;
  F        : TLeakFinding;
  DiagCnt  : Integer;
  LeakCnt  : Integer;
begin
  TmpPath := TPath.Combine(TPath.GetTempPath,
    'sca_suppr_lock_' + TGUID.NewGuid.ToString + '.pas');
  TFile.WriteAllText(TmpPath,
    '// noinspection MemoryLeak'#13#10 +
    'x := TStringList.Create;'#13#10);
  try
    Lock := TFileStream.Create(TmpPath, fmOpenRead or fmShareExclusive);
    try
      Findings := TObjectList<TLeakFinding>.Create(True);
      try
        Findings.Add(TLeakFinding.New(TmpPath, 'M', 2, 'x', fkMemoryLeak));
        TSuppression.ApplyToFindings(Findings);

        DiagCnt := 0; LeakCnt := 0;
        for F in Findings do
        begin
          if F.Kind = fkFileReadError then
          begin
            Inc(DiagCnt);
            Assert.AreEqual(TmpPath, F.FileName,
              'Diagnose-Finding muss auf den Marker-Host zeigen');
            Assert.AreEqual(MSG_SUPPRESSION_READ_ERROR, F.MissingVar,
              'Diagnose-Message muss die Read-Error-Konstante sein');
          end;
          if F.Kind = fkMemoryLeak then Inc(LeakCnt);
        end;
        Assert.AreEqual<Integer>(1, DiagCnt,
          'genau 1 fkFileReadError-Diagnose fuer den unlesbaren Host');
        Assert.AreEqual<Integer>(1, LeakCnt,
          'Original-Finding bleibt ungefiltert stehen (fail-open, aber sichtbar)');
      finally
        Findings.Free;
      end;
    finally
      Lock.Free;
    end;
  finally
    TFile.Delete(TmpPath);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSuppressionCompleteness);

end.
