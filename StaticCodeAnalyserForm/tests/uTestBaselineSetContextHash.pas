unit uTestBaselineSetContextHash;

// Tests fuer die ZWEITE Match-Quelle von TBaselineSet.Contains: den
// contextHash.
//
// WARUM ES SIE GIBT (Befund Baseline-Identitaet, 2026-08-28)
//
// TBaseline.Fingerprint hasht MissingVar - den Detailtext - mit. Die vier
// Metrik-Detektoren schreiben ihre ZAHL genau dort hinein, und zwar samt
// Schwellwert: 'Cyclomatic complexity 11 (limit: 10)'. Aendert sich der
// Score, oder dreht der Nutzer an dem dokumentierten INI-Knopf
// CyclomaticMax, wechselt damit die IDENTITAET des Fundes - obwohl sich am
// Code keine einzige Zeile geaendert hat. Auf dem Referenzkorpus haengen
// daran 37.987 Funde = 4,8 %.
//
// TBaseline.Apply (CLI) faengt das seit v0.9.8 ueber den contextHash ab.
// TBaselineSet.Contains - der Anzeige-Filter von EXE und IDE-Plugin - tat
// es nicht: TBaseline.Write legte den contextHash in JEDE Baseline-Datei,
// LoadFromFile warf ihn beim Laden wieder weg.
//
// WAS DIE TESTS FESTHALTEN
//   (a) DetailChanged_MatchesViaContextHash - geaendertes Detail bei
//       unveraendertem Code ringsum matcht ueber den contextHash.
//       OHNE DEN UMBAU ROT.
//   (b) LegacyBaseline_BehavesAsBefore - Alt-Format ohne contextHash-Feld:
//       Verhalten unveraendert, kein Absturz. REGRESSIONSSCHUTZ.
//   (c) CodeChanged_StillCountsAsNew - hat sich der Code ringsum
//       geaendert, bleibt der Fund neu. REGRESSIONSSCHUTZ gegen einen
//       Hash, der ALLES matcht.
//   (d) BrokenBaseline_NoErrorNoMatch - fehlende, leere und kaputte Datei
//       bleiben fail-open. REGRESSIONSSCHUTZ.
//   (e) WithoutPrepare_FallsBackToFingerprint - Baseline geladen, aber der
//       Scan-Nachlauf ist nicht gelaufen: sauberer Rueckfall auf den
//       Fingerprint. Nagelt die ehrliche Grenze aus dem Klassenkommentar
//       fest. REGRESSIONSSCHUTZ.
//   (f) WatchRefresh_DropsStaleHashOfChangedFile - Guard fuer die neue
//       Methode RefreshContextHashesForFile: ohne das Wegwerfen verglichen
//       die Eintraege des letzten Scans einen frischen Fund mit dem Hash
//       des ALTEN Codes und blendeten ihn faelschlich aus.
//   (g) TwinFile_SameCode_StaysNew - der contextHash identifiziert ein
//       CODE-FENSTER, keine Fundstelle. Zwei VERSCHIEDEN BENANNTE Dateien
//       mit byte-gleichem Rumpf tragen denselben Hash; ein Baseline-
//       Eintrag fuer Datei A darf Datei B NICHT ausblenden. OHNE DIE
//       QUALIFIZIERUNG DES SCHLUESSELS ROT.
//   (h) OtherRule_SameWindow_StaysNew - dieselbe Grenze quer zur REGEL:
//       zwei Detektoren am selben Fenster teilen den Hash ebenfalls
//       (korpusweit 42.589 Hashes = 17,3 % der Funde). OHNE DIE
//       QUALIFIZIERUNG DES SCHLUESSELS ROT.
//   (i) TwinName_OtherFolder_DefaultScope_MatchesAnyway - die EHRLICHE
//       GRENZE zu (g): heissen die beiden Dateien GLEICH und liegen nur in
//       verschiedenen Baeumen, wird die Grenze im DEFAULT gar nicht
//       gezogen - der Datei-Token ist dort der blosse Basisname. WAECHTER,
//       kein Beweis: der Test ist auch ohne die Qualifizierung gruen. Er
//       haelt die Eigenschaft fest, damit sie niemand versehentlich
//       verschaerft, ohne die Folgen fuer bestehende Baselines zu nennen.
//   (j) TwinName_OtherFolder_PathScope_StaysNew - dieselbe Lage mit
//       PathInFingerprint=1 (TBaselineScope.ByPath): jetzt traegt der
//       Schluessel den Relativpfad, und die Grenze wird GEZOGEN. OHNE DIE
//       QUALIFIZIERUNG DES SCHLUESSELS ROT.
//
// Kein Test hier fasst ein Prozess-Global an - alle Baseline-Operationen
// bekommen ihren Zuschnitt als Parameter (Schritte 2-6).

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,
  uMethodd12;

type
  [TestFixture]
  TTestBaselineSetContextHash = class
  strict private
    // Quelldatei und Baseline-Datei des laufenden Tests - TearDown raeumt
    // sie weg. Das haelt die Testruempfe frei von Aufraeumketten.
    // FPasFileB ist die ZWEITE Quelldatei; nur die Zwillings-Tests
    // brauchen sie, TearDown raeumt sie ebenso weg.
    FPasFile      : string;
    FPasFileB     : string;
    FBaselineFile : string;
    // Die NAMENS-ZWILLINGE der Tests (i)/(j): <FTwinRoot>\<Sub>\<gleicher
    // Dateiname>, zweimal. Eigene Felder statt FPasFile/FPasFileB, weil
    // hier nicht nur zwei Pfade gebraucht werden, sondern ein ganzer Baum -
    // TearDown loescht ihn rekursiv.
    FTwinRoot     : string;
    FTwinA        : string;
    FTwinB        : string;
    function WriteTempPas(const ABody: string): string;
    function WriteTempPasB(const ABody: string): string;
    function TempBaselineFile: string;
    procedure WriteTwinPair(const ABody: string);
    procedure WriteTwinBaselineA;
    procedure WriteTwinBaselineAByPath;
    function MakeFinding(ALine: Integer; const ADetail: string): TLeakFinding;
    function MakeFindingIn(const AFile: string; ALine: Integer;
      const ADetail: string): TLeakFinding;
    function MakeOtherKindFinding(ALine: Integer;
      const ADetail: string): TLeakFinding;
    function ListWith(AFinding: TLeakFinding): TObjectList<TLeakFinding>;
    procedure WriteBaselineFor(const ADetail: string);
    procedure WriteLegacyBaselineFor(const ADetail: string);
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure DetailChanged_MatchesViaContextHash;
    [Test] procedure LegacyBaseline_BehavesAsBefore;
    [Test] procedure CodeChanged_StillCountsAsNew;
    [Test] procedure BrokenBaseline_NoErrorNoMatch;
    [Test] procedure WithoutPrepare_FallsBackToFingerprint;
    [Test] procedure WatchRefresh_DropsStaleHashOfChangedFile;
    [Test] procedure TwinFile_SameCode_StaysNew;
    [Test] procedure OtherRule_SameWindow_StaysNew;
    [Test] procedure TwinName_OtherFolder_DefaultScope_MatchesAnyway;
    [Test] procedure TwinName_OtherFolder_PathScope_StaysNew;
  end;

implementation

// noinspection-file BeginEndRequired, NestedTry, TooLongLine
// Temp-Datei-Tests brauchen geschachtelte try/finally-Ketten und
// Guard-Einzeiler - idiomatisches Testmuster der Nachbardateien.

uses
  System.SysUtils, System.IOUtils, System.JSON,
  uSCAConsts, uBaseline, uFileTextCache, uFindingFingerprint;

const
  // Der Fund sitzt auf Zeile 8; CONTEXT_HASH_RADIUS ist 3, das Fenster
  // reicht also von Zeile 5 bis 11. Die Methodenzeile liegt bewusst
  // ausserhalb.
  FIND_LINE = 8;
  METHOD_P  = 'P';
  // Zwei Detailtexte derselben Regel, die sich NUR im Score unterscheiden -
  // genau der Fall, an dem die Baseline-Identitaet heute zerbricht.
  DETAIL_11 = 'Cyclomatic complexity 11 (limit: 10)';
  DETAIL_12 = 'Cyclomatic complexity 12 (limit: 10)';
  // Praefix ALLER Temp-Pfade dieser Fixture - liegengebliebene Leichen sind
  // daran zu erkennen. Gebraucht wird er nur noch in TempGuidPath.
  TMP_PREFIX = 'sca_blctx_';
  // Die Namens-Zwillinge (i)/(j). Der Dateiname ist BEWUSST fest und nicht
  // per GUID gezogen: dass beide Baeume dieselbe Datei HEISSEN lassen, ist
  // der ganze Gegenstand dieser zwei Tests.
  TWIN_FILE  = 'utwin.pas';
  TWIN_SUB_A = 'baum_a';
  TWIN_SUB_B = 'baum_b';

  BODY_V1 =
    'unit u;'#13#10 +              // 1
    'interface'#13#10 +            // 2
    'implementation'#13#10 +       // 3
    'procedure P;'#13#10 +         // 4  (ausserhalb 8 +/- 3)
    'begin'#13#10 +                // 5  (= 8 - 3)
    '  A := 1;'#13#10 +            // 6
    '  B := 2;'#13#10 +            // 7
    '  C := 3;'#13#10 +            // 8  <- Fund
    '  D := 4;'#13#10 +            // 9
    '  E := 5;'#13#10 +            // 10
    '  F := 6;'#13#10 +            // 11 (= 8 + 3)
    'end;'#13#10 +                 // 12 (ausserhalb)
    'end.'#13#10;                  // 13
  // Wie V1, aber die Fundzeile selbst ist eine andere - und sie ist ein
  // Zeichen laenger. Die Laenge zaehlt: der Text-Cache erkennt eine
  // Ueberschreibung an mtime UND Groesse, und FileAge hat rund eine
  // Sekunde Granularitaet.
  BODY_V2 =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'begin'#13#10 +
    '  A := 1;'#13#10 +
    '  B := 2;'#13#10 +
    '  C := 99;'#13#10 +           // 8  <- geaenderter Code an der Fundstelle
    '  D := 4;'#13#10 +
    '  E := 5;'#13#10 +
    '  F := 6;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;

{ Freie Helfer }

function TempGuidPath(const ASuffix: string): string;
// Ein frischer Pfad unterhalb des Temp-Ordners: Praefix + GUID + Suffix.
// Leeres Suffix liefert einen Ordnernamen. Eine Stelle fuer die Regel,
// damit die Guid-Wasche nicht in jedem Helfer noch einmal steht.
begin
  Result := TPath.Combine(TPath.GetTempPath, TMP_PREFIX +
    TGuid.NewGuid.ToString.Replace('{', '').Replace('}', '') + ASuffix);
end;

procedure WriteOneEntryBaseline(AFinding: TLeakFinding;
  const ADestFile: string; const AScope: TBaselineScope);
// Schreibt GENAU EINEN Eintrag mit dem uebergebenen Zuschnitt und prueft
// die beiden Vorbedingungen, auf die sich jeder Test hier verlaesst. Die
// Liste besitzt den Fund: der Aufrufer uebergibt ihn und vergisst ihn.
//
// Freie Funktion und keine Methode: TBaselineScope kommt aus uBaseline,
// und uBaseline steht in der implementation-uses. Eine Methoden-Signatur
// in der interface-Sektion saehe den Typ nicht (E2003).
var
  List : TObjectList<TLeakFinding>;
begin
  List := TObjectList<TLeakFinding>.Create(True);
  try
    List.Add(AFinding);
    Assert.AreEqual<Integer>(1, TBaseline.Write(List, ADestFile, AScope),
      'Vorbedingung: ein Eintrag geschrieben');
  finally
    List.Free;
  end;
  Assert.Contains(TFile.ReadAllText(ADestFile), 'contextHash',
    'Vorbedingung: die Datei traegt einen contextHash');
end;

{ Fixture-Rahmen }

procedure TTestBaselineSetContextHash.Setup;
begin
  FPasFile      := '';
  FPasFileB     := '';
  FBaselineFile := '';
  FTwinRoot     := '';
  FTwinA        := '';
  FTwinB        := '';
  // Der prozessweite Text-Cache ueberlebt fremde Fixtures (uTestEngineApi
  // legt ihn an). Diese Tests schreiben Quelldateien um und muessen den
  // NEUEN Inhalt sehen - dasselbe Leeren, das ein echter Scan-Start macht.
  uFileTextCache.ReleaseTransientCaches;
end;

procedure TTestBaselineSetContextHash.TearDown;
begin
  if (FPasFile <> '') and TFile.Exists(FPasFile) then
  begin
    TFile.Delete(FPasFile);
  end;
  if (FPasFileB <> '') and TFile.Exists(FPasFileB) then
  begin
    TFile.Delete(FPasFileB);
  end;
  if (FBaselineFile <> '') and TFile.Exists(FBaselineFile) then
  begin
    TFile.Delete(FBaselineFile);
  end;
  // Der Zwillings-Baum geht komplett - Unterordner und beide Dateien.
  if (FTwinRoot <> '') and TDirectory.Exists(FTwinRoot) then
  begin
    TDirectory.Delete(FTwinRoot, True);
  end;
  FPasFile      := '';
  FPasFileB     := '';
  FBaselineFile := '';
  FTwinRoot     := '';
  FTwinA        := '';
  FTwinB        := '';
end;

{ Helfer }

function TTestBaselineSetContextHash.WriteTempPas(const ABody: string): string;
// Quelldatei des Tests. Der Pfad wird beim ERSTEN Aufruf gezogen und
// danach behalten: ein zweiter Aufruf ueberschreibt dieselbe Datei - genau
// so entsteht "der Code ringsum hat sich geaendert".
begin
  if FPasFile = '' then
  begin
    FPasFile := TempGuidPath('.pas');
  end;
  TFile.WriteAllText(FPasFile, ABody, TEncoding.UTF8);
  Result := FPasFile;
end;

function TTestBaselineSetContextHash.WriteTempPasB(
  const ABody: string): string;
// ZWEITE Quelldatei desselben Tests. Bewusst ein eigener Pfad und kein
// zweiter Aufruf von WriteTempPas: der ueberschriebe die erste, und der
// Zwillings-Test braucht BEIDE gleichzeitig.
begin
  if FPasFileB = '' then
  begin
    FPasFileB := TempGuidPath('.pas');
  end;
  TFile.WriteAllText(FPasFileB, ABody, TEncoding.UTF8);
  Result := FPasFileB;
end;

function TTestBaselineSetContextHash.TempBaselineFile: string;
// Ein Zielpfad JE TEST, ebenfalls beim ersten Aufruf gezogen - Schreiber
// und Leser desselben Tests muessen dieselbe Datei treffen.
begin
  if FBaselineFile = '' then
  begin
    FBaselineFile := TempGuidPath('.baseline.json');
  end;
  Result := FBaselineFile;
end;

procedure TTestBaselineSetContextHash.WriteTwinPair(const ABody: string);
// Die NAMENS-ZWILLINGE: <Temp>\sca_blctx_<guid>\baum_a\utwin.pas und
// ...\baum_b\utwin.pas - GLEICHER Dateiname, verschiedene Baeume,
// byte-gleicher Rumpf. Die Wurzel traegt eine GUID, damit sich zwei
// Laeufe nicht ins Gehege kommen; die Dateinamen sind fest.
//
// Die Groessen-Falle von BODY_V1/BODY_V2 spielt hier keine Rolle: die
// Zwillinge werden je Test genau EINMAL geschrieben, in einen frischen
// Ordner - der Text-Cache kann gar keinen alten Stand von ihnen haben.
begin
  if FTwinRoot = '' then
  begin
    FTwinRoot := TempGuidPath('');
    FTwinA := TPath.Combine(TPath.Combine(FTwinRoot, TWIN_SUB_A), TWIN_FILE);
    FTwinB := TPath.Combine(TPath.Combine(FTwinRoot, TWIN_SUB_B), TWIN_FILE);
    TDirectory.CreateDirectory(ExtractFilePath(FTwinA));
    TDirectory.CreateDirectory(ExtractFilePath(FTwinB));
  end;
  TFile.WriteAllText(FTwinA, ABody, TEncoding.UTF8);
  TFile.WriteAllText(FTwinB, ABody, TEncoding.UTF8);
end;

procedure TTestBaselineSetContextHash.WriteTwinBaselineA;
// Baseline mit genau einem Eintrag fuer Zwilling A, im DEFAULT-Zuschnitt:
// der Datei-Token ist der blosse Dateiname, also 'utwin.pas' - der Baum
// steht nirgends drin.
begin
  WriteOneEntryBaseline(MakeFindingIn(FTwinA, FIND_LINE, DETAIL_11),
    TempBaselineFile, TBaselineScope.ByFileName);
end;

procedure TTestBaselineSetContextHash.WriteTwinBaselineAByPath;
// Dasselbe im PFAD-Modus ab der gemeinsamen Wurzel: der Datei-Token ist
// 'baum_a/utwin.pas' und trennt die Baeume.
begin
  WriteOneEntryBaseline(MakeFindingIn(FTwinA, FIND_LINE, DETAIL_11),
    TempBaselineFile, TBaselineScope.ByPath(FTwinRoot));
end;

function TTestBaselineSetContextHash.MakeFindingIn(const AFile: string;
  ALine: Integer; const ADetail: string): TLeakFinding;
// Ein Metrik-Fund auf einer beliebigen Quelldatei. fkCyclomaticComplexity
// ist keine Zierde: es ist eine der vier Regeln, die ihren Score in den
// Detailtext schreiben.
begin
  Result := TLeakFinding.New(AFile, METHOD_P, ALine, ADetail,
    fkCyclomaticComplexity);
end;

function TTestBaselineSetContextHash.MakeFinding(ALine: Integer;
  const ADetail: string): TLeakFinding;
// Der Normalfall: derselbe Fund auf der Quelldatei dieses Tests.
begin
  Result := MakeFindingIn(FPasFile, ALine, ADetail);
end;

function TTestBaselineSetContextHash.MakeOtherKindFinding(ALine: Integer;
  const ADetail: string): TLeakFinding;
// Gleiche Datei, gleiche Zeile, ANDERE Regel - damit sich der
// Code-Kontext (und damit der contextHash) Zeichen fuer Zeichen deckt und
// wirklich nur die Regel auseinandergeht.
begin
  Result := TLeakFinding.New(FPasFile, METHOD_P, ALine, ADetail,
    fkEmptyBlock);
end;

function TTestBaselineSetContextHash.ListWith(
  AFinding: TLeakFinding): TObjectList<TLeakFinding>;
// Besitzende Liste mit genau einem Fund - der Aufrufer gibt die Liste frei
// und mit ihr den Fund.
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  Result.Add(AFinding);
end;

procedure TTestBaselineSetContextHash.WriteBaselineFor(const ADetail: string);
// Baseline im heutigen Format: fingerprint UND contextHash, so wie
// TBaseline.Write sie seit v0.9.8 schreibt - fuer die Quelldatei DIESES
// Tests, im Default-Zuschnitt.
begin
  WriteOneEntryBaseline(MakeFinding(FIND_LINE, ADetail), TempBaselineFile,
    TBaselineScope.ByFileName);
end;

procedure TTestBaselineSetContextHash.WriteLegacyBaselineFor(
  const ADetail: string);
// Alt-Format von Hand gebaut: fingerprint ja, contextHash nein - so sahen
// die Dateien vor v0.9.8 aus (docs/releases/v0.9.8.md).
var
  F    : TLeakFinding;
  Root : TJSONObject;
  Arr  : TJSONArray;
  Obj  : TJSONObject;
begin
  F := MakeFinding(FIND_LINE, ADetail);
  try
    Obj := TJSONObject.Create;
    Obj.AddPair('file',        ExtractFileName(F.FileName));
    Obj.AddPair('kind',        KindName(F.Kind));
    Obj.AddPair('method',      F.MethodName);
    Obj.AddPair('detail',      F.MissingVar);
    Obj.AddPair('line',        F.LineNumber);
    Obj.AddPair('fingerprint',
      TBaseline.Fingerprint(F, TBaselineScope.ByFileName));
    Arr := TJSONArray.Create;
    Arr.AddElement(Obj);
    Root := TJSONObject.Create;
    try
      Root.AddPair('findings', Arr);   // -> Arr + Obj werden mit befreit
      TFile.WriteAllText(TempBaselineFile, Root.ToString, TEncoding.UTF8);
    finally
      Root.Free;
    end;
  finally
    F.Free;
  end;
end;

{ Tests }

procedure TTestBaselineSetContextHash.DetailChanged_MatchesViaContextHash;
// (a) OHNE DEN UMBAU ROT. Der Fund steht an derselben Stelle, der Code
// ringsum ist Zeile fuer Zeile unveraendert - nur der Score im Detailtext
// ist von 11 auf 12 gewandert. Bis 2026-08-28 zeigte der Anzeige-Filter
// ihn deshalb als "neu": LoadFromFile las den contextHash gar nicht erst
// ein, und Contains kannte nur den Fingerprint.
var
  Pas  : string;
  Alt  : TLeakFinding;
  Neu  : TLeakFinding;
  List : TObjectList<TLeakFinding>;
  BSet : TBaselineSet;
begin
  Pas := WriteTempPas(BODY_V1);
  Assert.IsTrue(TFile.Exists(Pas), 'Vorbedingung: Quelldatei geschrieben');
  WriteBaselineFor(DETAIL_11);

  Neu  := MakeFinding(FIND_LINE, DETAIL_12);
  List := ListWith(Neu);
  BSet := TBaselineSet.Create;
  try
    Alt := MakeFinding(FIND_LINE, DETAIL_11);
    try
      Assert.AreNotEqual(
        TBaseline.Fingerprint(Alt, TBaselineScope.ByFileName),
        TBaseline.Fingerprint(Neu, TBaselineScope.ByFileName),
        'Vorbedingung: der Legacy-Fingerprint TRENNT die beiden Details - ' +
        'sonst belegte der Test nicht den contextHash');
    finally
      Alt.Free;
    end;
    Assert.AreEqual<Integer>(1,
      BSet.LoadFromFile(TempBaselineFile, TBaselineScope.ByFileName),
      'ein Fingerprint geladen');
    Assert.AreEqual<Integer>(1, BSet.PrepareContextHashes(List),
      'der Scan-Nachlauf rechnet den Hash des Fundes genau einmal');
    Assert.IsTrue(BSet.Contains(Neu),
      'gleicher Code ringsum, nur anderer Score - der contextHash traegt');
  finally
    BSet.Free;
    List.Free;
  end;
end;

procedure TTestBaselineSetContextHash.LegacyBaseline_BehavesAsBefore;
// (b) REGRESSIONSSCHUTZ. Eine Baseline aus der Zeit vor v0.9.8 traegt kein
// contextHash-Feld. Dort darf sich NICHTS aendern: der identische Fund
// matcht weiter ueber den Fingerprint, der mit geaendertem Detail nicht -
// und die Vorab-Rechnung faellt komplett aus, weil es nichts gaebe, wogegen
// zu matchen waere.
var
  Pas    : string;
  Gleich : TLeakFinding;
  Anders : TLeakFinding;
  List   : TObjectList<TLeakFinding>;
  BSet   : TBaselineSet;
begin
  Pas := WriteTempPas(BODY_V1);
  Assert.IsTrue(TFile.Exists(Pas), 'Vorbedingung: Quelldatei geschrieben');
  WriteLegacyBaselineFor(DETAIL_11);
  Assert.IsFalse(TFile.ReadAllText(TempBaselineFile).Contains('contextHash'),
    'Vorbedingung: die Alt-Datei traegt KEINEN contextHash');

  Gleich := MakeFinding(FIND_LINE, DETAIL_11);
  Anders := MakeFinding(FIND_LINE, DETAIL_12);
  List   := TObjectList<TLeakFinding>.Create(True);
  BSet   := TBaselineSet.Create;
  try
    List.Add(Gleich);
    List.Add(Anders);
    Assert.AreEqual<Integer>(1,
      BSet.LoadFromFile(TempBaselineFile, TBaselineScope.ByFileName),
      'der Fingerprint wird gelesen wie eh und je');
    Assert.AreEqual<Integer>(0, BSet.PrepareContextHashes(List),
      'ohne contextHash in der Datei wird nicht gerechnet');
    Assert.IsTrue(BSet.Contains(Gleich),
      'identischer Fund matcht weiter ueber den Fingerprint');
    Assert.IsFalse(BSet.Contains(Anders),
      'anderes Detail bleibt neu - eine Alt-Baseline rettet nichts');
  finally
    BSet.Free;
    List.Free;
  end;
end;

procedure TTestBaselineSetContextHash.CodeChanged_StillCountsAsNew;
// (c) REGRESSIONSSCHUTZ gegen einen Hash, der ALLES matcht. Gleiche Lage
// wie (a) - anderer Score -, aber diesmal hat sich zusaetzlich der Code an
// der Fundstelle geaendert. Beide Match-Quellen muessen danebenliegen,
// sonst waere der contextHash ein Freibrief.
var
  Pas  : string;
  Neu  : TLeakFinding;
  List : TObjectList<TLeakFinding>;
  BSet : TBaselineSet;
begin
  Pas := WriteTempPas(BODY_V1);
  WriteBaselineFor(DETAIL_11);
  // Dieselbe Datei mit geaendertem Rumpf ueberschreiben und den Text-Cache
  // leeren - genau das, was ein zweiter Scan tut.
  WriteTempPas(BODY_V2);
  uFileTextCache.ReleaseTransientCaches;
  Assert.Contains(TFile.ReadAllText(Pas), 'C := 99;',
    'Vorbedingung: die Quelldatei traegt jetzt den neuen Rumpf');

  Neu  := MakeFinding(FIND_LINE, DETAIL_12);
  List := ListWith(Neu);
  BSet := TBaselineSet.Create;
  try
    BSet.LoadFromFile(TempBaselineFile, TBaselineScope.ByFileName);
    Assert.AreEqual<Integer>(1, BSet.PrepareContextHashes(List),
      'gerechnet wird - nur eben ueber den NEUEN Code');
    Assert.IsFalse(BSet.Contains(Neu),
      'geaenderter Code ringsum: der Fund ist wirklich neu');
  finally
    BSet.Free;
    List.Free;
  end;
end;

procedure TTestBaselineSetContextHash.BrokenBaseline_NoErrorNoMatch;
// (d) REGRESSIONSSCHUTZ. Fehlende, leere und kaputte Baseline bleiben
// fail-open: leeres Set, kein Fehler, nichts wird ausgeblendet. Funde zu
// verstecken, weil eine Datei fehlt, waere die gefaehrlichere Richtung -
// und der neue contextHash-Zweig darf daran nichts aendern.
var
  Pas  : string;
  F    : TLeakFinding;
  List : TObjectList<TLeakFinding>;
  BSet : TBaselineSet;
begin
  Pas  := WriteTempPas(BODY_V1);
  Assert.IsTrue(TFile.Exists(Pas), 'Vorbedingung: Quelldatei geschrieben');
  F    := MakeFinding(FIND_LINE, DETAIL_11);
  List := ListWith(F);
  BSet := TBaselineSet.Create;
  try
    // 1. Datei gibt es gar nicht.
    Assert.AreEqual<Integer>(0,
      BSet.LoadFromFile(TempBaselineFile + '.fehlt',
                        TBaselineScope.ByFileName),
      'fehlende Datei -> nichts geladen');
    Assert.IsTrue(BSet.IsEmpty, 'und das Set ist leer');
    Assert.AreEqual<Integer>(0, BSet.PrepareContextHashes(List),
      'ohne Baseline wird nicht gerechnet');
    Assert.IsFalse(BSet.Contains(F), 'fehlende Datei blendet nichts aus');

    // 2. Datei ist leer.
    TFile.WriteAllText(TempBaselineFile, '', TEncoding.UTF8);
    Assert.AreEqual<Integer>(0,
      BSet.LoadFromFile(TempBaselineFile, TBaselineScope.ByFileName),
      'leere Datei -> nichts geladen');
    Assert.IsFalse(BSet.Contains(F), 'leere Datei blendet nichts aus');

    // 3. Kein JSON.
    TFile.WriteAllText(TempBaselineFile, 'kaputt (((', TEncoding.UTF8);
    Assert.AreEqual<Integer>(0,
      BSet.LoadFromFile(TempBaselineFile, TBaselineScope.ByFileName),
      'Muell -> nichts geladen');
    Assert.AreEqual<Integer>(0, BSet.PrepareContextHashes(List),
      'auch danach wird nicht gerechnet');
    Assert.IsFalse(BSet.Contains(F), 'Muell blendet nichts aus');

    // 4. JSON, aber 'findings' ist kein Array (handverdorben / Merge).
    TFile.WriteAllText(TempBaselineFile, '{"findings": 42}', TEncoding.UTF8);
    Assert.AreEqual<Integer>(0,
      BSet.LoadFromFile(TempBaselineFile, TBaselineScope.ByFileName),
      'falsch typisiertes findings -> nichts geladen');
    Assert.IsFalse(BSet.Contains(F),
      'falsch typisiertes findings blendet nichts aus');
  finally
    BSet.Free;
    List.Free;
  end;
end;

procedure TTestBaselineSetContextHash.WithoutPrepare_FallsBackToFingerprint;
// (e) REGRESSIONSSCHUTZ fuer die ehrliche Grenze aus dem
// Klassenkommentar: wer die Baseline erst NACH dem Scan einschaltet, hat
// keinen Hash-Speicher. Contains darf dann weder abstuerzen noch heimlich
// eine Datei lesen - es entscheidet allein der Fingerprint, also exakt das
// Bestandsverhalten. Die Quelldatei EXISTIERT dabei und traegt den
// passenden Code: nur so belegt der Test, dass die Toleranz am fehlenden
// Speicher haengt und nicht an einer unlesbaren Datei.
var
  Pas    : string;
  Gleich : TLeakFinding;
  Anders : TLeakFinding;
  BSet   : TBaselineSet;
begin
  Pas := WriteTempPas(BODY_V1);
  Assert.IsTrue(TFile.Exists(Pas), 'Vorbedingung: Quelldatei geschrieben');
  WriteBaselineFor(DETAIL_11);

  Gleich := MakeFinding(FIND_LINE, DETAIL_11);
  Anders := MakeFinding(FIND_LINE, DETAIL_12);
  BSet   := TBaselineSet.Create;
  try
    Assert.AreEqual<Integer>(1,
      BSet.LoadFromFile(TempBaselineFile, TBaselineScope.ByFileName),
      'die Datei ist geladen - nur der Scan-Nachlauf fehlt');
    // KEIN PrepareContextHashes. Das ist der Punkt dieses Tests.
    Assert.IsTrue(BSet.Contains(Gleich),
      'der Fingerprint-Zweig traegt unveraendert');
    Assert.IsFalse(BSet.Contains(Anders),
      'ohne Vorab-Rechnung keine contextHash-Toleranz - und kein I/O');
  finally
    BSet.Free;
    Anders.Free;
    Gleich.Free;
  end;
end;

procedure TTestBaselineSetContextHash.WatchRefresh_DropsStaleHashOfChangedFile;
// (f) Guard fuer die neue Methode RefreshContextHashesForFile. Der
// Watch-Modus ersetzt die Funde EINER Datei im Bestand. Die vorab
// gerechneten Eintraege dieser Datei stammen aus dem letzten Voll-Scan,
// also aus dem Stand VOR der Aenderung, die den Watch-Lauf ueberhaupt
// ausgeloest hat. Bleiben sie stehen, vergleichen sie einen frischen Fund
// mit dem Hash des alten Codes und blenden ihn faelschlich aus.
var
  Pas   : string;
  Alt   : TLeakFinding;
  Neu   : TLeakFinding;
  Voll  : TObjectList<TLeakFinding>;
  Watch : TObjectList<TLeakFinding>;
  BSet  : TBaselineSet;
begin
  Pas := WriteTempPas(BODY_V1);
  Assert.IsTrue(TFile.Exists(Pas), 'Vorbedingung: Quelldatei geschrieben');
  WriteBaselineFor(DETAIL_11);

  Alt   := MakeFinding(FIND_LINE, DETAIL_12);
  Voll  := ListWith(Alt);
  Watch := TObjectList<TLeakFinding>.Create(True);
  BSet  := TBaselineSet.Create;
  try
    BSet.LoadFromFile(TempBaselineFile, TBaselineScope.ByFileName);
    Assert.AreEqual<Integer>(1, BSet.PrepareContextHashes(Voll),
      'Vorbedingung: der Hash des alten Standes liegt im Speicher');
    Assert.IsTrue(BSet.Contains(Alt),
      'Vorbedingung: mit dem alten Code matcht er - das ist Fall (a)');

    // Der Anwender tippt: die Datei aendert sich, und der Watch-Lauf
    // liefert die Funde genau dieser Datei neu.
    WriteTempPas(BODY_V2);
    Neu := MakeFinding(FIND_LINE, DETAIL_12);
    Watch.Add(Neu);
    Assert.AreEqual<Integer>(1, BSet.RefreshContextHashesForFile(Pas, Watch),
      'der Nachzug rechnet den Hash der geaenderten Datei neu');
    Assert.IsFalse(BSet.Contains(Neu),
      'der Eintrag des alten Standes ist weg - der Fund ist wirklich neu');
  finally
    BSet.Free;
    Watch.Free;
    Voll.Free;
  end;
end;

procedure TTestBaselineSetContextHash.TwinFile_SameCode_StaysNew;
// (g) OHNE DIE QUALIFIZIERUNG DES SCHLUESSELS ROT.
//
// TFindingFingerprint.ContextHashFor hasht AUSSCHLIESSLICH die +/- 3
// normalisierten Quellzeilen - kein Pfad, keine Regel. Er identifiziert
// damit ein CODE-FENSTER und keine Fundstelle. Ging er nackt in die
// Match-Menge, blendete EIN Baseline-Eintrag jeden Fund im ganzen Scan
// aus, dessen Fenster textgleich ist: auf dem Referenzkorpus 105.806
// Hashes dateiuebergreifend, 239.018 Funde (30,48 %) durch einen Eintrag
// aus einer ANDEREN Datei ausblendbar - vendorte Kopien, generierte
// Vorlagen, Boilerplate.
//
// WAS DIESER TEST BELEGT - UND WAS NICHT (Korrektur 2026-08-28): die
// beiden Temp-Dateien heissen VERSCHIEDEN (GUID-Namen). Der Legacy-
// Fingerprint zieht die Grenze deshalb hier mit, aber nicht "weil er den
// Datei-Token traegt" - im Default IST dieser Token nur der Basisname
// (DEF_BASELINE_PATH_FINGERPRINT = False, s. TBaselineScope.FileToken).
// Gleichnamige Dateien in verschiedenen Baeumen fallen bei ihm genauso
// zusammen wie beim qualifizierten contextHash; diesen Fall haelt (i)
// fest, und dort wird die Grenze im Default NICHT gezogen. Belegt ist
// hier also: der contextHash ueberschreitet die Grenze zwischen zwei
// VERSCHIEDEN BENANNTEN Dateien nicht mehr.
var
  PasB  : string;
  FundA : TLeakFinding;
  FundB : TLeakFinding;
  List  : TObjectList<TLeakFinding>;
  BSet  : TBaselineSet;
begin
  WriteTempPas(BODY_V1);
  PasB := WriteTempPasB(BODY_V1);      // byte-gleicher Rumpf, andere Datei
  Assert.AreEqual(TFile.ReadAllText(FPasFile), TFile.ReadAllText(PasB),
    'Vorbedingung: beide Quelldateien sind inhaltsgleich');
  WriteBaselineFor(DETAIL_11);         // Baseline kennt NUR Datei A

  FundA := MakeFinding(FIND_LINE, DETAIL_11);
  FundB := MakeFindingIn(PasB, FIND_LINE, DETAIL_11);
  List  := TObjectList<TLeakFinding>.Create(True);
  BSet  := TBaselineSet.Create;
  try
    List.Add(FundA);
    List.Add(FundB);
    Assert.AreEqual(TFindingFingerprint.ContextHash(FundA),
                    TFindingFingerprint.ContextHash(FundB),
      'Vorbedingung: beide Funde tragen DENSELBEN contextHash - ohne die ' +
      'Gleichheit belegte der Test nichts');
    Assert.AreNotEqual(
      TBaseline.Fingerprint(FundA, TBaselineScope.ByFileName),
      TBaseline.Fingerprint(FundB, TBaselineScope.ByFileName),
      'Vorbedingung: der Legacy-Fingerprint TRENNT die beiden Dateien - ' +
      'ein Treffer kaeme also nur aus dem contextHash-Zweig');
    Assert.AreEqual<Integer>(1,
      BSet.LoadFromFile(TempBaselineFile, TBaselineScope.ByFileName),
      'genau ein Eintrag, und der gehoert Datei A');
    Assert.AreEqual<Integer>(2, BSet.PrepareContextHashes(List),
      'beide Funde bekommen ihren Hash');
    Assert.IsTrue(BSet.Contains(FundA),
      'Datei A steht in der Baseline und bleibt ausgeblendet');
    Assert.IsFalse(BSet.Contains(FundB),
      'Datei B steht NICHT in der Baseline - ein textgleiches ' +
      'Code-Fenster darf sie nicht mit ausblenden');
  finally
    BSet.Free;
    List.Free;
  end;
end;

procedure TTestBaselineSetContextHash.OtherRule_SameWindow_StaysNew;
// (h) OHNE DIE QUALIFIZIERUNG DES SCHLUESSELS ROT.
//
// Dieselbe Grenze quer zur REGEL. Zwei Detektoren, die dieselbe Zeile
// bemaengeln, teilen zwangslaeufig das Code-Fenster und damit den Hash -
// auf dem Referenzkorpus haengen 42.589 Hashes (17,3 % aller Funde) an
// mehr als einer Regel. Wer SCA-Regel X in die Baseline aufnimmt, darf
// damit nicht Regel Y an derselben Stelle miterledigen: die Baseline sagt
// "diesen Befund akzeptiere ich", nicht "an dieser Stelle will ich nichts
// mehr hoeren".
var
  Gleich : TLeakFinding;
  Andere : TLeakFinding;
  List   : TObjectList<TLeakFinding>;
  BSet   : TBaselineSet;
begin
  WriteTempPas(BODY_V1);
  WriteBaselineFor(DETAIL_11);         // Regel fkCyclomaticComplexity

  Gleich := MakeFinding(FIND_LINE, DETAIL_11);
  Andere := MakeOtherKindFinding(FIND_LINE, DETAIL_11);
  List   := TObjectList<TLeakFinding>.Create(True);
  BSet   := TBaselineSet.Create;
  try
    List.Add(Gleich);
    List.Add(Andere);
    Assert.AreEqual(TFindingFingerprint.ContextHash(Gleich),
                    TFindingFingerprint.ContextHash(Andere),
      'Vorbedingung: gleiche Datei, gleiche Zeile - also derselbe ' +
      'contextHash');
    Assert.AreEqual<Integer>(1,
      BSet.LoadFromFile(TempBaselineFile, TBaselineScope.ByFileName),
      'ein Eintrag, und der gehoert der Metrik-Regel');
    Assert.AreEqual<Integer>(2, BSet.PrepareContextHashes(List),
      'beide Funde bekommen ihren Hash (aus demselben Memo-Eintrag)');
    Assert.IsTrue(BSet.Contains(Gleich),
      'die Regel aus der Baseline bleibt ausgeblendet');
    Assert.IsFalse(BSet.Contains(Andere),
      'die ANDERE Regel am selben Fenster ist davon nicht gedeckt');
  finally
    BSet.Free;
    List.Free;
  end;
end;

procedure TTestBaselineSetContextHash.TwinName_OtherFolder_DefaultScope_MatchesAnyway;
// (i) WAECHTER, KEIN BEWEIS - und er nagelt eine Grenze fest, die im
// DEFAULT gar nicht gezogen wird. Das ist Absicht.
//
// (g) belegt die Datei-Grenze mit zwei GUID-Namen, also mit VERSCHIEDENEN
// Dateinamen - den real gemessenen Fall kann er damit nicht bemerken.
// Der sieht so aus: dieselbe Datei, zweimal vendort. Im Default ist
// AScope.FileToken der blosse BASISNAME (DEF_BASELINE_PATH_FINGERPRINT =
// False, s. TBaselineScope.FileToken), beide Baeume teilen also ihren
// Schluessel - auf BEIDEN Strecken. Am Korpus rw19 ausgezaehlt haengt
// synhighlighterjscript.pas mit 604 SCA101-Funden an EINEM Schluessel,
// verteilt ueber Dev-Cpp/Source/VCL/SynEdit und HeidiSQL/components/
// synedit.
//
// DAS IST KEINE REGRESSION DER SCHLUESSEL-QUALIFIZIERUNG, sondern die
// dokumentierte Eigenschaft des Datei-Tokens: der Legacy-Fingerprint
// traegt denselben Basisnamen und zieht die Grenze im Default ebensowenig
// - der erste Assert unten zeigt genau das, bevor irgendein contextHash
// ins Spiel kommt. Wer die Grenze scharf braucht, setzt
// PathInFingerprint=1; das ist Test (j).
//
// Der Test ist deshalb auch OHNE die Qualifizierung gruen. Er steht hier
// als Waechter gegen eine kuenftige stille Verschaerfung: wer den Default
// enger macht, laesst diesen Test rot werden und muss die Folgen fuer
// bestehende Baselines benennen, statt sie zu verstecken.
var
  FundA      : TLeakFinding;
  FundB      : TLeakFinding;
  FundBScore : TLeakFinding;
  List       : TObjectList<TLeakFinding>;
  BSet       : TBaselineSet;
begin
  WriteTwinPair(BODY_V1);
  Assert.AreEqual(ExtractFileName(FTwinA), ExtractFileName(FTwinB),
    'Vorbedingung: beide Zwillinge HEISSEN gleich');
  Assert.AreNotEqual(FTwinA, FTwinB,
    'Vorbedingung: und liegen doch in verschiedenen Baeumen');
  WriteTwinBaselineA;                  // Baseline kennt NUR Baum A

  FundA      := MakeFindingIn(FTwinA, FIND_LINE, DETAIL_11);
  FundB      := MakeFindingIn(FTwinB, FIND_LINE, DETAIL_11);
  // Derselbe Fund in Baum B, nur mit gewandertem Score: sein Fingerprint
  // trennt, ein Treffer kann bei ihm also NUR aus dem contextHash-Zweig
  // kommen. So deckt der Test beide Strecken getrennt ab.
  FundBScore := MakeFindingIn(FTwinB, FIND_LINE, DETAIL_12);
  List := TObjectList<TLeakFinding>.Create(True);
  BSet := TBaselineSet.Create;
  try
    List.Add(FundA);
    List.Add(FundB);
    List.Add(FundBScore);
    Assert.AreEqual(
      TBaseline.Fingerprint(FundA, TBaselineScope.ByFileName),
      TBaseline.Fingerprint(FundB, TBaselineScope.ByFileName),
      'DAS ist der Kern: schon der LEGACY-Fingerprint faellt zusammen - ' +
      'im Default traegt er nur den Basisnamen');
    Assert.AreNotEqual(
      TBaseline.Fingerprint(FundA, TBaselineScope.ByFileName),
      TBaseline.Fingerprint(FundBScore, TBaselineScope.ByFileName),
      'Vorbedingung: mit gewandertem Score trennt der Fingerprint sehr ' +
      'wohl - bei diesem Fund kaeme ein Treffer nur aus dem contextHash');
    Assert.AreEqual(TFindingFingerprint.ContextHash(FundA),
                    TFindingFingerprint.ContextHash(FundB),
      'Vorbedingung: byte-gleicher Rumpf -> derselbe contextHash');
    Assert.AreEqual<Integer>(1,
      BSet.LoadFromFile(TempBaselineFile, TBaselineScope.ByFileName),
      'genau ein Eintrag, und der gehoert Baum A');
    Assert.AreEqual<Integer>(3, BSet.PrepareContextHashes(List),
      'alle drei Funde bekommen ihren Hash');
    Assert.IsTrue(BSet.Contains(FundA),
      'Baum A steht in der Baseline und bleibt ausgeblendet');
    Assert.IsTrue(BSet.Contains(FundB),
      'EHRLICHE GRENZE: der gleichnamige Zwilling aus Baum B gilt im ' +
      'Default ebenfalls als bekannt - hier traegt schon der Fingerprint');
    Assert.IsTrue(BSet.Contains(FundBScore),
      'EHRLICHE GRENZE, zweite Strecke: auch der QUALIFIZIERTE ' +
      'contextHash-Schluessel trennt die Baeume im Default nicht - sein ' +
      'Datei-Anteil IST der Basisname');
  finally
    BSet.Free;
    List.Free;
  end;
end;

procedure TTestBaselineSetContextHash.TwinName_OtherFolder_PathScope_StaysNew;
// (j) OHNE DIE QUALIFIZIERUNG DES SCHLUESSELS ROT - die Gegenprobe zu (i).
//
// Gleiche Lage, aber mit PathInFingerprint=1: TBaselineScope.ByPath ab der
// gemeinsamen Wurzel macht den Datei-Token zum Relativpfad,
// 'baum_a/utwin.pas' gegen 'baum_b/utwin.pas'. Jetzt wird die Grenze
// gezogen, und zwar auf BEIDEN Strecken. Dass der Fingerprint sie zieht,
// haelt uTestFindingFingerprint.PathMode_DistinguishesSameFileNameInFolders
// schon fest; NEU ist, dass der contextHash-Schluessel mitzieht, weil er
// denselben Token traegt. Vor der Qualifizierung ging der nackte Hash
// ueber die Ordnergrenze hinweg und entwertete den Pfad-Modus fuer die
// contextHash-Strecke komplett.
var
  Scope : TBaselineScope;
  FundA : TLeakFinding;
  FundB : TLeakFinding;
  List  : TObjectList<TLeakFinding>;
  BSet  : TBaselineSet;
begin
  WriteTwinPair(BODY_V1);
  WriteTwinBaselineAByPath;            // Baseline kennt NUR Baum A
  Scope := TBaselineScope.ByPath(FTwinRoot);
  Assert.IsTrue(Scope.Effective,
    'Vorbedingung: Modus UND Wurzel sind gesetzt - sonst faellt der Token ' +
    'still auf den Dateinamen zurueck, und der Test pruefte (i) nach');

  FundA := MakeFindingIn(FTwinA, FIND_LINE, DETAIL_11);
  FundB := MakeFindingIn(FTwinB, FIND_LINE, DETAIL_11);
  List  := TObjectList<TLeakFinding>.Create(True);
  BSet  := TBaselineSet.Create;
  try
    List.Add(FundA);
    List.Add(FundB);
    Assert.AreNotEqual(Scope.FileToken(FTwinA), Scope.FileToken(FTwinB),
      'Vorbedingung: im Pfad-Modus sind die Datei-Tokens verschieden');
    Assert.AreEqual(TFindingFingerprint.ContextHash(FundA),
                    TFindingFingerprint.ContextHash(FundB),
      'Vorbedingung: der contextHash SELBST faellt weiter zusammen - er ' +
      'kennt nur das Code-Fenster. Trennen kann nur der Schluessel');
    Assert.AreEqual<Integer>(1, BSet.LoadFromFile(TempBaselineFile, Scope),
      'ein Eintrag, und der gehoert Baum A');
    Assert.AreEqual<Integer>(2, BSet.PrepareContextHashes(List),
      'beide Funde bekommen ihren Hash');
    Assert.IsTrue(BSet.Contains(FundA),
      'Baum A steht in der Baseline und bleibt ausgeblendet');
    Assert.IsFalse(BSet.Contains(FundB),
      'im Pfad-Modus wird die Grenze GEZOGEN - der gleichnamige Zwilling ' +
      'aus Baum B bleibt neu');
  finally
    BSet.Free;
    List.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestBaselineSetContextHash);

end.
