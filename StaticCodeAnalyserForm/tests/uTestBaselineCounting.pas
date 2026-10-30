unit uTestBaselineCounting;

// Tests fuer den ZAEHLENDEN Baseline-Abgleich (uBaseline.TBaselineMatcher,
// 2026-10-30, Review d/MethodAttr, Entscheid Nico "Apply zaehlt").
//
// WARUM ES SIE GIBT
//
// Der Baseline-Fingerprint traegt keine Zeile. Bis 2026-10-30 galt der
// Abgleich als MENGE: kam der Fingerprint (oder der qualifizierte
// contextHash) eines Fundes irgendwo in der Datei vor, war der Fund
// "bekannt" - auch wenn er erst nach dem Schreiben der Baseline dazukam
// und die Baseline nur EINEN Eintrag dieser Art hatte. Seit d/MethodAttr
// bleibt die Methode ausserhalb jeder Routine leer, und dort teilen sich
// alle Funde einer Regel mit gleicher Meldung in einer Datei EINEN
// Fingerprint (rw 13.363, laz 5.693 Funde, vor allem SCA081). Unter der
// Mengen-Regel waere ein neuer Fund dieser Art nie als neu erschienen.
//
// WAS DIE TESTS FESTHALTEN
//   (a) ZweiEintraege_DreiFunde_GenauEinerNeu - zwei gleiche Eintraege,
//       drei Funde: genau einer ist neu, und zwar der hinzugekommene (die
//       beiden alten bekommen ihre Eintraege exakt zuerst).
//       OHNE DEN UMBAU ROT (alle drei fielen weg).
//   (b) ZweiEintraege_ZweiFunde_KeinerNeu - die Gegenrichtung: der Abgleich
//       darf nicht zu GEIZIG werden, auch nicht, wenn der Code ringsum
//       sich geaendert hat und nur noch der Fingerprint traegt.
//       WAECHTER, auch ohne den Umbau gruen - die Mengen-Regel deckte
//       hier ohnehin alles; rot wird er bei einem Matcher, der einen
//       Eintrag doppelt verbraucht oder Stufe 3 verliert.
//   (c) ContextTreffer_VerbrauchtEintrag_ZweiterFundNeu - ein Fund mit
//       geaendertem Meldetext trifft den Eintrag ueber den contextHash und
//       VERBRAUCHT ihn; ein zweiter Fund mit dem Fingerprint des Eintrags
//       ist danach neu. Der zweite Fund steht in der Liste VORN - die
//       Reihenfolge der Stufen entscheidet, nicht die der Liste.
//       OHNE DEN UMBAU ROT (beide fielen weg).
//   (d) AlteBaseline_OhneContextHash_ZaehltUeberFingerprint - eine Datei
//       aus der Zeit vor v0.9.8 (nur 'fingerprint') zaehlt genauso.
//       OHNE DEN UMBAU ROT.
//   (e) AnzeigeFilter_NewOnly_Zaehlt - derselbe Vertrag fuer EXE und
//       Plugin (TBaselineSet.CoveredFlags/NewOnly); Contains bleibt die
//       Einzelfrage und sagt fuer beide Funde True.
//       OHNE DEN UMBAU ROT (NewOnly lief ueber Contains je Fund).
//
// Kein Test hier fasst ein Prozess-Global an - alle Baseline-Operationen
// bekommen ihren Zuschnitt als Parameter.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestBaselineCounting = class
  strict private
    // Quelldatei und Baseline-Datei des laufenden Tests; TearDown raeumt.
    FPasFile      : string;
    FBaselineFile : string;
    procedure WritePas(const APrefix: string);
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure ZweiEintraege_DreiFunde_GenauEinerNeu;
    [Test] procedure ZweiEintraege_ZweiFunde_KeinerNeu;
    [Test] procedure ContextTreffer_VerbrauchtEintrag_ZweiterFundNeu;
    [Test] procedure AlteBaseline_OhneContextHash_ZaehltUeberFingerprint;
    [Test] procedure AnzeigeFilter_NewOnly_Zaehlt;
  end;

implementation

// noinspection-file BeginEndRequired, TooLongLine
// Guard-Einzeiler und lange Assert-Texte - Muster der Nachbar-Fixtures.

uses
  System.SysUtils, System.IOUtils, System.JSON,
  System.Generics.Collections,
  uSCAConsts, uMethodd12, uBaseline, uFileTextCache;

const
  TMP_PREFIX = 'sca_blcount_';
  // Drei Fundzeilen mit ueberschneidungsfreien Fenstern
  // (CONTEXT_HASH_RADIUS 3): 2..8, 12..18, 22..28. Jede Zeile der Datei
  // ist verschieden, also auch jedes Fenster - ein Treffer ueber den
  // contextHash kann nur von der eigenen Zeile kommen.
  LINE_A = 5;
  LINE_B = 15;
  LINE_C = 25;
  BODY_LINES = 30;
  // Ein Fund ausserhalb jeder Routine, wie ihn d/MethodAttr jetzt meldet:
  // Methode leer, Meldung fuer alle gleich - also EIN Fingerprint.
  NO_METHOD   = '';
  DETAIL_SAME = 'Empty block';
  DETAIL_NEW  = 'Empty block - kein Kommentar, keine Anweisung';

{ Freie Helfer }

function TempGuidPath(const AExt: string): string;
begin
  Result := TPath.Combine(TPath.GetTempPath, TMP_PREFIX +
    TGuid.NewGuid.ToString.Replace('{', '').Replace('}', '') + AExt);
end;

function NumberedBody(const APrefix: string): string;
// BODY_LINES verschiedene Zeilen. Ein anderes APrefix aendert JEDE Zeile -
// und die Dateilaenge, an der der Text-Cache eine Ueberschreibung erkennt.
var
  i  : Integer;
  SB : TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    for i := 1 to BODY_LINES do
    begin
      SB.Append(Format('  %s%d := %d;', [APrefix, i, i * 7])).Append(#13#10);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function NewFinding(const AFile: string; ALine: Integer;
  const ADetail: string): TLeakFinding;
begin
  Result := TLeakFinding.New(AFile, NO_METHOD, ALine, ADetail, fkEmptyBlock);
end;

function FpOf(const AFile: string; ALine: Integer;
  const ADetail: string): string;
var
  F : TLeakFinding;
begin
  F := NewFinding(AFile, ALine, ADetail);
  try
    Result := TBaseline.Fingerprint(F, TBaselineScope.ByFileName);
  finally
    F.Free;
  end;
end;

procedure WriteBaselineAt(const AFile, ADest: string;
  const ALines: array of Integer; const ADetail: string);
// Baseline im heutigen Format (fingerprint + contextHash), ein Eintrag je
// Zeile - genau so, wie TBaseline.Write sie aus einem Scan schreibt.
var
  List : TObjectList<TLeakFinding>;
  i    : Integer;
begin
  List := TObjectList<TLeakFinding>.Create(True);
  try
    for i := Low(ALines) to High(ALines) do
    begin
      List.Add(NewFinding(AFile, ALines[i], ADetail));
    end;
    Assert.AreEqual<Integer>(Length(ALines),
      TBaseline.Write(List, ADest, TBaselineScope.ByFileName),
      'Vorbedingung: ein Eintrag je Fund geschrieben');
  finally
    List.Free;
  end;
  Assert.Contains(TFile.ReadAllText(ADest), 'contextHash',
    'Vorbedingung: die Datei traegt contextHashes');
end;

function LineOf(F: TLeakFinding): Integer;
begin
  Result := StrToIntDef(F.LineNumber, 0);
end;

{ Fixture-Rahmen }

procedure TTestBaselineCounting.Setup;
begin
  FPasFile      := '';
  FBaselineFile := '';
  // Der prozessweite Text-Cache ueberlebt fremde Fixtures; diese Tests
  // schreiben Quelldateien und muessen den NEUEN Inhalt sehen.
  uFileTextCache.ReleaseTransientCaches;
end;

procedure TTestBaselineCounting.TearDown;
begin
  if (FPasFile <> '') and TFile.Exists(FPasFile) then
    TFile.Delete(FPasFile);
  if (FBaselineFile <> '') and TFile.Exists(FBaselineFile) then
    TFile.Delete(FBaselineFile);
  FPasFile      := '';
  FBaselineFile := '';
end;

procedure TTestBaselineCounting.WritePas(const APrefix: string);
// Beim ersten Aufruf Pfade ziehen, danach dieselbe Datei ueberschreiben -
// so entsteht "der Code ringsum hat sich geaendert".
begin
  if FPasFile = '' then
  begin
    FPasFile      := TempGuidPath('.pas');
    FBaselineFile := TempGuidPath('.baseline.json');
  end;
  TFile.WriteAllText(FPasFile, NumberedBody(APrefix), TEncoding.UTF8);
  uFileTextCache.ReleaseTransientCaches;
end;

{ Tests }

procedure TTestBaselineCounting.ZweiEintraege_DreiFunde_GenauEinerNeu;
// (a) OHNE DEN UMBAU ROT: die Mengen-Regel fand den Fingerprint in der
// Datei und liess alle drei Funde fallen (Dropped 3, Rest 0).
var
  List    : TObjectList<TLeakFinding>;
  Dropped : Integer;
begin
  WritePas('A');
  WriteBaselineAt(FPasFile, FBaselineFile, [LINE_A, LINE_B], DETAIL_SAME);
  Assert.AreEqual(FpOf(FPasFile, LINE_A, DETAIL_SAME),
    FpOf(FPasFile, LINE_C, DETAIL_SAME),
    'Vorbedingung: alle Funde teilen EINEN Fingerprint (keine Zeile darin)');

  List := TObjectList<TLeakFinding>.Create(True);
  try
    // Der neue Fund steht bewusst VORN: die exakte Stufe gibt den beiden
    // alten ihre Eintraege, egal in welcher Reihenfolge die Liste kommt.
    List.Add(NewFinding(FPasFile, LINE_C, DETAIL_SAME));
    List.Add(NewFinding(FPasFile, LINE_A, DETAIL_SAME));
    List.Add(NewFinding(FPasFile, LINE_B, DETAIL_SAME));
    Dropped := TBaseline.Apply(List, FBaselineFile, TBaselineScope.ByFileName);
    Assert.AreEqual<Integer>(2, Dropped,
      'zwei Eintraege decken hoechstens zwei Funde');
    Assert.AreEqual<Integer>(1, List.Count, 'genau ein Fund ist neu');
    Assert.AreEqual<Integer>(LINE_C, LineOf(List[0]),
      'und zwar der hinzugekommene - die alten haben ihre Eintraege exakt');
  finally
    List.Free;
  end;
end;

procedure TTestBaselineCounting.ZweiEintraege_ZweiFunde_KeinerNeu;
// (b) WAECHTER gegen einen zu geizigen Abgleich (s. Kopf). Zwei Runden:
// erst unveraendert (Stufe 1 exakt), dann mit geaendertem Code ringsum
// (kein contextHash trifft mehr, Stufe 3 ueber den Fingerprint allein).
var
  List    : TObjectList<TLeakFinding>;
  Dropped : Integer;
begin
  WritePas('A');
  WriteBaselineAt(FPasFile, FBaselineFile, [LINE_A, LINE_B], DETAIL_SAME);

  List := TObjectList<TLeakFinding>.Create(True);
  try
    List.Add(NewFinding(FPasFile, LINE_A, DETAIL_SAME));
    List.Add(NewFinding(FPasFile, LINE_B, DETAIL_SAME));
    Dropped := TBaseline.Apply(List, FBaselineFile, TBaselineScope.ByFileName);
    Assert.AreEqual<Integer>(2, Dropped, 'unveraendert: beide bekannt');
    Assert.AreEqual<Integer>(0, List.Count, 'kein Fund neu');
  finally
    List.Free;
  end;

  // Jede Zeile der Datei aendert sich - die Fenster beider Funde auch.
  WritePas('Bxx');
  List := TObjectList<TLeakFinding>.Create(True);
  try
    List.Add(NewFinding(FPasFile, LINE_B, DETAIL_SAME));
    List.Add(NewFinding(FPasFile, LINE_C, DETAIL_SAME));
    Dropped := TBaseline.Apply(List, FBaselineFile, TBaselineScope.ByFileName);
    Assert.AreEqual<Integer>(2, Dropped,
      'Code ringsum geaendert: zwei Eintraege decken ueber den ' +
      'Fingerprint weiter zwei Funde');
    Assert.AreEqual<Integer>(0, List.Count, 'kein Fund neu');
  finally
    List.Free;
  end;
end;

procedure TTestBaselineCounting.ContextTreffer_VerbrauchtEintrag_ZweiterFundNeu;
// (c) OHNE DEN UMBAU ROT: die Mengen-Regel liess den Fund mit geaendertem
// Text ueber den contextHash fallen UND den zweiten ueber den Fingerprint
// (Dropped 2, Rest 0).
var
  List    : TObjectList<TLeakFinding>;
  Dropped : Integer;
begin
  WritePas('A');
  WriteBaselineAt(FPasFile, FBaselineFile, [LINE_A], DETAIL_SAME);
  Assert.AreNotEqual(FpOf(FPasFile, LINE_A, DETAIL_SAME),
    FpOf(FPasFile, LINE_A, DETAIL_NEW),
    'Vorbedingung: der geaenderte Meldetext aendert den Fingerprint - der ' +
    'Treffer des ersten Fundes kann nur vom contextHash kommen');

  List := TObjectList<TLeakFinding>.Create(True);
  try
    // VORN der Fund mit dem Fingerprint des Eintrags, aber anderem Fenster.
    List.Add(NewFinding(FPasFile, LINE_C, DETAIL_SAME));
    // Dahinter der Fund an der Stelle des Eintrags, mit neuem Wortlaut.
    List.Add(NewFinding(FPasFile, LINE_A, DETAIL_NEW));
    Dropped := TBaseline.Apply(List, FBaselineFile, TBaselineScope.ByFileName);
    Assert.AreEqual<Integer>(1, Dropped, 'ein Eintrag deckt einen Fund');
    Assert.AreEqual<Integer>(1, List.Count, 'ein Fund ist neu');
    Assert.AreEqual<Integer>(LINE_C, LineOf(List[0]),
      'der contextHash-Treffer (Stufe 2) verbraucht den Eintrag vor dem ' +
      'Fingerprint-Treffer (Stufe 3) - neu ist der Fund an der fremden Stelle');
  finally
    List.Free;
  end;
end;

procedure TTestBaselineCounting.AlteBaseline_OhneContextHash_ZaehltUeberFingerprint;
// (d) OHNE DEN UMBAU ROT: Dropped 3 statt 2. Eine Baseline aus der Zeit
// vor v0.9.8 traegt nur 'fingerprint'; auch sie zaehlt jetzt, und ein Fund
// mit anderem Fingerprint bleibt wie immer neu.
var
  Fp      : string;
  Root    : TJSONObject;
  Arr     : TJSONArray;
  Obj     : TJSONObject;
  i       : Integer;
  List    : TObjectList<TLeakFinding>;
  Dropped : Integer;
begin
  WritePas('A');
  Fp := FpOf(FPasFile, LINE_A, DETAIL_SAME);
  Root := TJSONObject.Create;
  try
    Arr := TJSONArray.Create;
    Root.AddPair('findings', Arr);       // -> Arr + Objs gehoeren Root
    for i := 1 to 2 do
    begin
      Obj := TJSONObject.Create;
      Obj.AddPair('file',        ExtractFileName(FPasFile));
      Obj.AddPair('kind',        KindName(fkEmptyBlock));
      Obj.AddPair('method',      NO_METHOD);
      Obj.AddPair('detail',      DETAIL_SAME);
      Obj.AddPair('fingerprint', Fp);
      Arr.AddElement(Obj);
    end;
    TFile.WriteAllText(FBaselineFile, Root.ToString, TEncoding.UTF8);
  finally
    Root.Free;
  end;
  Assert.IsFalse(TFile.ReadAllText(FBaselineFile).Contains('contextHash'),
    'Vorbedingung: die Alt-Datei traegt KEINEN contextHash');

  List := TObjectList<TLeakFinding>.Create(True);
  try
    List.Add(NewFinding(FPasFile, LINE_A, DETAIL_SAME));
    List.Add(NewFinding(FPasFile, LINE_B, DETAIL_SAME));
    List.Add(NewFinding(FPasFile, LINE_C, DETAIL_SAME));
    List.Add(NewFinding(FPasFile, LINE_C, DETAIL_NEW));
    Dropped := TBaseline.Apply(List, FBaselineFile, TBaselineScope.ByFileName);
    Assert.AreEqual<Integer>(2, Dropped,
      'zwei Alt-Eintraege decken zwei der drei gleichen Funde');
    Assert.AreEqual<Integer>(2, List.Count,
      'neu: der dritte gleiche Fund und der mit anderem Fingerprint');
    Assert.AreEqual<Integer>(LINE_C, LineOf(List[0]),
      'ohne contextHash in Listen-Reihenfolge: der dritte ist der neue');
    Assert.AreEqual(DETAIL_NEW, List[1].MissingVar,
      'der Fund mit anderem Fingerprint bleibt neu wie eh und je');
  finally
    List.Free;
  end;
end;

procedure TTestBaselineCounting.AnzeigeFilter_NewOnly_Zaehlt;
// (e) OHNE DEN UMBAU ROT: NewOnly lief ueber Contains je Fund und lieferte
// eine leere Liste. Der Anzeige-Filter von EXE und Plugin (ApplyFilter)
// und die Zaehlbasis der Combos (NewOnly) gehen beide ueber CoveredFlags.
var
  List    : TObjectList<TLeakFinding>;
  BSet    : TBaselineSet;
  Owned   : TList<TLeakFinding>;
  Res     : TList<TLeakFinding>;
  Covered : TArray<Boolean>;
begin
  WritePas('A');
  WriteBaselineAt(FPasFile, FBaselineFile, [LINE_A], DETAIL_SAME);

  List := TObjectList<TLeakFinding>.Create(True);
  BSet := TBaselineSet.Create;
  try
    List.Add(NewFinding(FPasFile, LINE_C, DETAIL_SAME));   // neu
    List.Add(NewFinding(FPasFile, LINE_A, DETAIL_SAME));   // bekannt
    Assert.AreEqual<Integer>(1,
      BSet.LoadFromFile(FBaselineFile, TBaselineScope.ByFileName),
      'ein Fingerprint geladen');
    Assert.AreEqual<Integer>(2, BSet.PrepareContextHashes(List),
      'Scan-Nachlauf: beide Funde haben einen contextHash');

    Covered := BSet.CoveredFlags(List);
    Assert.AreEqual<Integer>(2, Length(Covered), 'index-gleich zur Liste');
    Assert.IsFalse(Covered[0], 'der hinzugekommene Fund ist neu');
    Assert.IsTrue(Covered[1], 'der Fund an der Stelle des Eintrags ist bekannt');

    Res := BSet.NewOnly(List, Owned);
    try
      Assert.IsTrue(Res = Owned, 'geladenes Set: eigene Liste');
      Assert.AreEqual<Integer>(1, Owned.Count, 'genau ein neuer Fund');
      Assert.IsTrue(Owned[0] = List[0], 'und zwar der hinzugekommene');
    finally
      Owned.Free;
    end;

    // Contains ist die Einzelfrage und verbraucht nichts - fuer jeden der
    // beiden Funde gibt es einen passenden Eintrag.
    Assert.IsTrue(BSet.Contains(List[0]),
      'Einzelfrage: der Fingerprint steht in der Baseline');
    Assert.IsTrue(BSet.Contains(List[1]), 'Einzelfrage: ebenso');
  finally
    BSet.Free;
    List.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestBaselineCounting);

end.
