unit uTestFindingFileIndex;

// Tests fuer uFindingFileIndex (SCA.SharedUI): die Funde einer Editor-Zeile
// fuer Gluehbirne und Editor-Kontextmenue und der Index je Datei, mit dem
// FindingsAtEditorLine seit Charge P (P6, 2026-10-25) nicht mehr linear
// ueber alle Dock-Funde laeuft.
//
// Abgesichert:
//   * die Regel je Fund, unveraendert aus FindingsAtEditorLine: Pfad
//     (Laenge zuerst, '/' gegen '\', Gross/Klein), Bereich mit Deckel,
//     Doppelte einmal, nil;
//   * der Index liefert dieselben Funde in derselben Reihenfolge wie der
//     lineare Lauf ueber die ganze Liste - auch fuer Namen, die nur im
//     Schluessel gleich sind (Leerraum, Nicht-ASCII);
//   * Neubau genau dann, wenn Liste, Anzahl oder Stempel sich aendern;
//   * der Stempel steigt mit jeder Generation (Voll-Befuellung, Watch-Lauf).
//
// UNGEDECKT bleibt die IDE-Seite: dass jeder Schreiber von FAllFindings
// eine Generation weiterdreht (uIDEAnalyserForm, Handtest).
//
// TFindingDelivery (OOM-Diagnose 2026-11-14): die Uebergabe einer neuen
// Fundliste an Besitz- und Anzeige-Liste des Docks. Abgesichert:
//   * die alten Funde werden erst frei, wenn die Anzeige-Liste schon leer
//     ist - gemessen IM Moment der Freigabe (Notify-Haken der Besitzliste);
//   * wirft das Umhaengen, besitzt die Quelle weiter ALLE Funde: kein Leck,
//     kein Doppelbesitz - jeder Fund wird am Ende genau einmal frei;
//   * Discard nach einem Fehler im Nachlauf leert beide Listen, jeder Fund
//     genau einmal frei.

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,
  uMethodd12;                   // TLeakFinding (Signatur der Notify-Haken)

type
  [TestFixture]
  TTestFindingFileIndex = class
  private
    // Zustand der Notify-Haken (TFindingDelivery-Tests).
    FDisplayed          : TList<TLeakFinding>;
    FMaxDisplayedAtFree : Integer;
    FAddsSeen           : Integer;
    FFailAtAdd          : Integer;
    procedure RecordDisplayedAtFree(Sender: TObject; const Item: TLeakFinding;
      Action: TCollectionNotification);
    procedure FailAtNthAdd(Sender: TObject; const Item: TLeakFinding;
      Action: TCollectionNotification);
  public
    [Test] procedure SameFindingFile_SlashAndCase_Match;
    [Test] procedure SameFindingFile_OtherLength_NoMatch;
    [Test] procedure FindingsAtLine_SpanAndCap;
    [Test] procedure FindingsAtLine_DuplicateOnce;
    [Test] procedure FindingsAtLine_NilListAndNilEntries;
    [Test] procedure Index_GroupsByKey_KeepsListOrder;
    [Test] procedure Index_HasFile_NeedsSameLength;
    [Test] procedure Index_MatchesLinearScan;
    [Test] procedure Index_NonAsciiCase_MatchesLinearScan;
    [Test] procedure Sync_SameState_NoRebuild;
    [Test] procedure Sync_NewStamp_Rebuilds;
    [Test] procedure Sync_CountChanged_Rebuilds;
    [Test] procedure Sync_OtherList_Rebuilds;
    [Test] procedure Sync_NilList_EmptyIndex;
    [Test] procedure FindingsStampOf_TakesNewestGeneration;
    [Test] procedure Delivery_FreesOldOnlyAfterDisplayDetached;
    [Test] procedure Delivery_AddFailure_SourceKeepsEveryFinding;
    [Test] procedure Delivery_Discard_EmptiesBothAndFreesOnce;
    [Test] procedure Delivery_AppendFailure_KeepsOwnedAndSource;
  end;

implementation

uses
  System.SysUtils,
  uPathNormalize,               // NormalizePathForKey
  uFindingFileIndex;

type
  // Fund mit Freigabe-Zaehler: GDestroyCount[Id] zaehlt, wie oft er frei
  // wurde - 0 = Leck, 1 = richtig, mehr = Doppelfreigabe.
  TTrackedFinding = class(TLeakFinding)
  private
    FId : Integer;
  public
    constructor CreateTracked(AId: Integer);
    destructor Destroy; override;
  end;

var
  GDestroyCount : TArray<Integer>;

constructor TTrackedFinding.CreateTracked(AId: Integer);
begin
  inherited Create;
  FId := AId;
  FileName   := 'C:\src\Unit' + IntToStr(AId) + '.pas';
  LineNumber := '1';
end;

destructor TTrackedFinding.Destroy;
begin
  if (FId >= 0) and (FId < Length(GDestroyCount)) then
    Inc(GDestroyCount[FId]);
  inherited;
end;

// Neue Zaehler fuer ACount Funde (Ids 0..ACount-1).
procedure ResetTracking(ACount: Integer);
var
  i : Integer;
begin
  SetLength(GDestroyCount, ACount);
  for i := 0 to ACount - 1 do
    GDestroyCount[i] := 0;
end;

// AList bekommt die Funde AFrom..ATo (Ids).
procedure AddTracked(AList: TList<TLeakFinding>; AFrom, ATo: Integer);
var
  i : Integer;
begin
  for i := AFrom to ATo do
    AList.Add(TTrackedFinding.CreateTracked(i));
end;

// Ein Fund in AList (Eigentum der Liste).
function AddFinding(AList: TList<TLeakFinding>; const AFile: string;
  ALine, AEndLine: Integer; const AVar: string): TLeakFinding;
begin
  Result := TLeakFinding.Create;
  AList.Add(Result);
  Result.FileName   := AFile;
  Result.LineNumber := IntToStr(ALine);
  Result.EndLine    := AEndLine;
  Result.MissingVar := AVar;
end;

// FindingsAtLine mit dem Schluessel aus NormalizePathForKey.
function AtLine(AList: TList<TLeakFinding>; const AFile: string;
  ALine, AMaxSpan: Integer): TArray<TLeakFinding>;
begin
  Result := FindingsAtLine(AList, AFile, NormalizePathForKey(AFile), ALine,
    AMaxSpan);
end;

// Der lineare Lauf, wie FindingsAtEditorLine ihn vor P6 fuer das Dock ging
// (Kandidaten = die ganze Liste) - die Referenz.
function LinearHasFile(AList: TList<TLeakFinding>; const AFile: string): Boolean;
var
  F : TLeakFinding;
begin
  Result := False;
  for F in AList do
    if Assigned(F)
       and SameFindingFile(F.FileName, AFile, NormalizePathForKey(AFile)) then
      Exit(True);
end;

// Gleiche Funde (Objekte) in gleicher Reihenfolge?
function SameFindings(const A, B: TArray<TLeakFinding>): Boolean;
var
  i : Integer;
begin
  Result := Length(A) = Length(B);
  if not Result then Exit;
  for i := 0 to High(A) do
    if A[i] <> B[i] then
      Exit(False);
end;

// Index gegen den linearen Lauf: je Datei aus AFiles und Zeile 0..AMaxLine
// dieselben Funde in derselben Reihenfolge und dieselbe Antwort auf
// HasFile. Liefert die Zahl der Abweichungen und die Zahl der Treffer.
procedure CompareWithLinear(AList: TList<TLeakFinding>;
  const AFiles: array of string; AMaxLine, AMaxSpan: Integer;
  out AMismatches, AHits: Integer);
var
  Idx  : TFindingFileIndex;
  Key  : string;
  i, L : Integer;
  Linear  : TArray<TLeakFinding>;
  Indexed : TArray<TLeakFinding>;
begin
  AMismatches := 0;
  AHits := 0;
  Idx := TFindingFileIndex.Create;
  try
    Idx.Sync(AList, 1);
    for i := 0 to High(AFiles) do
    begin
      Key := NormalizePathForKey(AFiles[i]);
      if Idx.HasFile(AFiles[i], Key) <> LinearHasFile(AList, AFiles[i]) then
        Inc(AMismatches);
      for L := 0 to AMaxLine do
      begin
        Linear  := FindingsAtLine(AList, AFiles[i], Key, L, AMaxSpan);
        Indexed := FindingsAtLine(Idx.Candidates(Key), AFiles[i], Key, L,
          AMaxSpan);
        if not SameFindings(Linear, Indexed) then
          Inc(AMismatches);
        Inc(AHits, Length(Linear));
      end;
    end;
  finally
    Idx.Free;
  end;
end;

procedure TTestFindingFileIndex.SameFindingFile_SlashAndCase_Match;
const
  FILE_A = 'C:\p\a.pas';
var
  Key : string;
begin
  Key := NormalizePathForKey(FILE_A);
  Assert.IsTrue(SameFindingFile(FILE_A, FILE_A, Key), 'gleich');
  Assert.IsTrue(SameFindingFile('c:\P\A.PAS', FILE_A, Key), 'Gross/Klein');
  Assert.IsTrue(SameFindingFile('C:/p/a.pas', FILE_A, Key), 'Schraegstrich');
  Assert.IsFalse(SameFindingFile('C:\p\b.pas', FILE_A, Key), 'andere Datei');
end;

procedure TTestFindingFileIndex.SameFindingFile_OtherLength_NoMatch;
const
  FILE_A = 'C:\p\a.pas';
begin
  // Gleicher Schluessel (Trim), aber andere Laenge: kein Treffer - die
  // Laenge geht dem Schluessel vor, wie seit Nit 44.
  Assert.AreEqual(NormalizePathForKey(FILE_A),
    NormalizePathForKey(' ' + FILE_A + ' '), 'Vorbedingung: gleicher Schluessel');
  Assert.IsFalse(SameFindingFile(' ' + FILE_A + ' ', FILE_A,
    NormalizePathForKey(FILE_A)));
end;

procedure TTestFindingFileIndex.FindingsAtLine_SpanAndCap;
const
  FILE_A = 'C:\p\a.pas';
var
  L     : TObjectList<TLeakFinding>;
  One   : TLeakFinding;
  Span  : TLeakFinding;
  Huge  : TLeakFinding;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    One  := AddFinding(L, FILE_A, 10, 0, 'one');     // einzeilig
    Span := AddFinding(L, FILE_A, 20, 24, 'span');   // 20..24
    Huge := AddFinding(L, FILE_A, 30, 900, 'huge');  // gedeckelt auf 30..35
    Assert.AreEqual<Integer>(1, Length(AtLine(L, FILE_A, 10, 5)), 'Zeile 10');
    Assert.IsTrue(AtLine(L, FILE_A, 10, 5)[0] = One, 'Zeile 10: one');
    Assert.AreEqual<Integer>(0, Length(AtLine(L, FILE_A, 11, 5)), 'Zeile 11');
    Assert.IsTrue(AtLine(L, FILE_A, 24, 5)[0] = Span, 'Zeile 24: span');
    Assert.AreEqual<Integer>(0, Length(AtLine(L, FILE_A, 25, 5)), 'Zeile 25');
    Assert.IsTrue(AtLine(L, FILE_A, 35, 5)[0] = Huge, 'Zeile 35: Deckel');
    Assert.AreEqual<Integer>(0, Length(AtLine(L, FILE_A, 36, 5)), 'Zeile 36');
  finally
    L.Free;
  end;
end;

procedure TTestFindingFileIndex.FindingsAtLine_DuplicateOnce;
const
  FILE_A = 'C:\p\a.pas';
var
  L      : TObjectList<TLeakFinding>;
  First  : TLeakFinding;
  Other  : TLeakFinding;
  Found  : TArray<TLeakFinding>;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    First := AddFinding(L, FILE_A, 10, 0, 'x');
    AddFinding(L, 'c:/p/A.pas', 10, 0, 'x');   // derselbe Fund, zweiter Scan
    Other := AddFinding(L, FILE_A, 10, 0, 'y');
    Found := AtLine(L, FILE_A, 10, 5);
    Assert.AreEqual<Integer>(2, Length(Found));
    Assert.IsTrue(Found[0] = First, 'der erste bleibt');
    Assert.IsTrue(Found[1] = Other, 'dann der andere');
  finally
    L.Free;
  end;
end;

procedure TTestFindingFileIndex.FindingsAtLine_NilListAndNilEntries;
const
  FILE_A = 'C:\p\a.pas';
var
  L   : TObjectList<TLeakFinding>;
  Idx : TFindingFileIndex;
begin
  Assert.AreEqual<Integer>(0, Length(AtLine(nil, FILE_A, 1, 5)), 'nil-Liste');
  L := TObjectList<TLeakFinding>.Create(True);
  Idx := TFindingFileIndex.Create;
  try
    L.Add(nil);
    AddFinding(L, FILE_A, 1, 0, 'a');
    L.Add(nil);
    Assert.AreEqual<Integer>(1, Length(AtLine(L, FILE_A, 1, 5)), 'linear');
    Idx.Sync(L, 1);
    Assert.AreEqual<Integer>(1, Idx.Candidates(NormalizePathForKey(FILE_A)).Count,
      'Index ohne nil');
  finally
    Idx.Free;
    L.Free;
  end;
end;

procedure TTestFindingFileIndex.Index_GroupsByKey_KeepsListOrder;
var
  L     : TObjectList<TLeakFinding>;
  Idx   : TFindingFileIndex;
  A1    : TLeakFinding;
  A2    : TLeakFinding;
  A3    : TLeakFinding;
  Cands : TList<TLeakFinding>;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  Idx := TFindingFileIndex.Create;
  try
    A1 := AddFinding(L, 'C:\p\a.pas', 5, 0, 'a1');
    AddFinding(L, 'C:\p\b.pas', 5, 0, 'b1');
    A2 := AddFinding(L, 'c:/P/a.pas', 3, 0, 'a2');
    AddFinding(L, 'C:\p\b.pas', 1, 0, 'b2');
    A3 := AddFinding(L, 'C:\p\a.pas', 1, 0, 'a3');
    Idx.Sync(L, 1);
    Cands := Idx.Candidates(NormalizePathForKey('C:\p\a.pas'));
    Assert.IsTrue(Assigned(Cands), 'Eimer a.pas');
    Assert.AreEqual<Integer>(3, Cands.Count);
    Assert.IsTrue((Cands[0] = A1) and (Cands[1] = A2) and (Cands[2] = A3),
      'Listenreihenfolge, nicht nach Zeile');
    Assert.IsTrue(Idx.Candidates(NormalizePathForKey('C:\p\c.pas')) = nil,
      'unbekannte Datei');
  finally
    Idx.Free;
    L.Free;
  end;
end;

procedure TTestFindingFileIndex.Index_HasFile_NeedsSameLength;
const
  FILE_A = 'C:\p\a.pas';
var
  L   : TObjectList<TLeakFinding>;
  Idx : TFindingFileIndex;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  Idx := TFindingFileIndex.Create;
  try
    AddFinding(L, FILE_A + ' ', 1, 0, 'a');   // gleicher Schluessel, laenger
    Idx.Sync(L, 1);
    Assert.IsTrue(Assigned(Idx.Candidates(NormalizePathForKey(FILE_A))),
      'Vorbedingung: im Eimer');
    Assert.IsFalse(Idx.HasFile(FILE_A, NormalizePathForKey(FILE_A)),
      'andere Laenge ist keine Datei des Docks');
    Assert.IsFalse(LinearHasFile(L, FILE_A), 'wie der lineare Lauf');
  finally
    Idx.Free;
    L.Free;
  end;
end;

procedure TTestFindingFileIndex.Index_MatchesLinearScan;
const
  NAMES : array[0..9] of string = (
    'C:\p\a.pas', 'c:\P\A.PAS', 'C:/p/a.pas', ' C:\p\a.pas', 'C:\p\a.pas ',
    'C:\p\b.pas', 'C:\q\a.pas', 'C:\p\ab.pas', '', 'C:\P\B.pas');
  QUERIES : array[0..11] of string = (
    'C:\p\a.pas', 'c:\P\A.PAS', 'C:/p/a.pas', ' C:\p\a.pas', 'C:\p\a.pas ',
    'C:\p\b.pas', 'C:\q\a.pas', 'C:\p\ab.pas', '', 'C:\P\B.pas',
    'C:\P\a.pas', 'D:\x.pas');
var
  L          : TObjectList<TLeakFinding>;
  i          : Integer;
  Seed       : UInt64;
  Line       : Integer;
  Mismatches : Integer;
  Hits       : Integer;

  function Next(AMod: Integer): Integer;
  begin
    // feste Folge (lineare Kongruenz modulo 2^31), damit der Test
    // reproduzierbar ist; Seed < 2^31, das Produkt passt in UInt64.
    Seed := (Seed * 1103515245 + 12345) mod 2147483648;
    Result := Integer((Seed shr 8) mod UInt64(AMod));
  end;

begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    Seed := 4711;
    for i := 1 to 600 do
    begin
      if Next(25) = 0 then
      begin
        L.Add(nil);
        Continue;
      end;
      Line := 1 + Next(40);
      // EndLine: 0 (einzeilig), kleiner als die Zeile, kurz oder ueber dem
      // Deckel - alle Faelle von SpanEnd und MAX_SPAN.
      AddFinding(L, NAMES[Next(Length(NAMES))], Line,
        Line + Next(12) - 3, 'v' + IntToStr(Next(4)));
    end;
    CompareWithLinear(L, QUERIES, 50, 6, Mismatches, Hits);
    Assert.IsTrue(Hits > 100, 'Vorbedingung: der Vergleich sieht Treffer');
    Assert.AreEqual<Integer>(0, Mismatches);
  finally
    L.Free;
  end;
end;

procedure TTestFindingFileIndex.Index_NonAsciiCase_MatchesLinearScan;
// Was SameText bei Nicht-ASCII-Buchstaben sagt, muss der Index ebenso
// sagen - die Begruendung im Kopf von uFindingFileIndex haengt daran.
var
  L          : TObjectList<TLeakFinding>;
  Mismatches : Integer;
  Hits       : Integer;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    AddFinding(L, 'C:\p\' + #$00C4 + '.pas', 1, 0, 'gross');   // A-Umlaut
    AddFinding(L, 'C:\p\' + #$00E4 + '.pas', 1, 0, 'klein');   // a-Umlaut
    AddFinding(L, 'C:\P\' + #$00E4 + '.PAS', 1, 0, 'klein2');
    CompareWithLinear(L, ['C:\p\' + #$00C4 + '.pas', 'C:\p\' + #$00E4 + '.pas',
      'c:\p\' + #$00E4 + '.pas'], 2, 5, Mismatches, Hits);
    Assert.IsTrue(Hits >= 3, 'Vorbedingung: jede Datei findet sich');
    Assert.AreEqual<Integer>(0, Mismatches);
  finally
    L.Free;
  end;
end;

procedure TTestFindingFileIndex.Sync_SameState_NoRebuild;
var
  L   : TObjectList<TLeakFinding>;
  Idx : TFindingFileIndex;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  Idx := TFindingFileIndex.Create;
  try
    AddFinding(L, 'C:\p\a.pas', 1, 0, 'a');
    Idx.Sync(L, 7);
    Idx.Sync(L, 7);
    Idx.Sync(L, 7);
    Assert.AreEqual<Integer>(1, Idx.Builds);
  finally
    Idx.Free;
    L.Free;
  end;
end;

procedure TTestFindingFileIndex.Sync_NewStamp_Rebuilds;
// Ein Watch-Lauf ersetzt die Funde einer Datei bei gleicher Anzahl: nur der
// Stempel verraet ihn - und der Index muss die neuen Objekte liefern.
var
  L   : TObjectList<TLeakFinding>;
  Idx : TFindingFileIndex;
  Neu : TLeakFinding;
  Key : string;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  Idx := TFindingFileIndex.Create;
  try
    Key := NormalizePathForKey('C:\p\a.pas');
    AddFinding(L, 'C:\p\a.pas', 1, 0, 'alt');
    Idx.Sync(L, 7);
    L.Delete(0);
    Neu := AddFinding(L, 'C:\p\a.pas', 2, 0, 'neu');
    Idx.Sync(L, 8);
    Assert.AreEqual<Integer>(2, Idx.Builds);
    Assert.IsTrue(Idx.Candidates(Key)[0] = Neu, 'neues Objekt');
  finally
    Idx.Free;
    L.Free;
  end;
end;

procedure TTestFindingFileIndex.Sync_CountChanged_Rebuilds;
var
  L   : TObjectList<TLeakFinding>;
  Idx : TFindingFileIndex;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  Idx := TFindingFileIndex.Create;
  try
    AddFinding(L, 'C:\p\a.pas', 1, 0, 'a');
    Idx.Sync(L, 7);
    AddFinding(L, 'C:\p\b.pas', 1, 0, 'b');
    Idx.Sync(L, 7);   // Schreiber ohne Generation - die Anzahl faengt ihn
    Assert.AreEqual<Integer>(2, Idx.Builds);
    Assert.IsTrue(Idx.HasFile('C:\p\b.pas', NormalizePathForKey('C:\p\b.pas')));
  finally
    Idx.Free;
    L.Free;
  end;
end;

procedure TTestFindingFileIndex.Sync_OtherList_Rebuilds;
var
  L1  : TObjectList<TLeakFinding>;
  L2  : TObjectList<TLeakFinding>;
  Idx : TFindingFileIndex;
begin
  L1 := TObjectList<TLeakFinding>.Create(True);
  L2 := TObjectList<TLeakFinding>.Create(True);
  Idx := TFindingFileIndex.Create;
  try
    AddFinding(L1, 'C:\p\a.pas', 1, 0, 'a');
    AddFinding(L2, 'C:\p\b.pas', 1, 0, 'b');
    Idx.Sync(L1, 7);
    Idx.Sync(L2, 7);
    Assert.AreEqual<Integer>(2, Idx.Builds);
    Assert.IsFalse(Idx.HasFile('C:\p\a.pas', NormalizePathForKey('C:\p\a.pas')),
      'a.pas gehoert zur alten Liste');
    Assert.IsTrue(Idx.HasFile('C:\p\b.pas', NormalizePathForKey('C:\p\b.pas')));
  finally
    Idx.Free;
    L2.Free;
    L1.Free;
  end;
end;

procedure TTestFindingFileIndex.Sync_NilList_EmptyIndex;
var
  L   : TObjectList<TLeakFinding>;
  Idx : TFindingFileIndex;
  Key : string;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  Idx := TFindingFileIndex.Create;
  try
    Key := NormalizePathForKey('C:\p\a.pas');
    AddFinding(L, 'C:\p\a.pas', 1, 0, 'a');
    Idx.Sync(L, 7);
    Idx.Sync(nil, 7);
    Assert.IsTrue(Idx.Candidates(Key) = nil, 'leer');
    Assert.IsFalse(Idx.HasFile('C:\p\a.pas', Key));
  finally
    Idx.Free;
    L.Free;
  end;
end;

procedure TTestFindingFileIndex.FindingsStampOf_TakesNewestGeneration;
var
  Gens : TDictionary<string, UInt64>;
begin
  Assert.IsTrue(FindingsStampOf(5, nil) = 5, 'ohne Watch-Laeufe');
  Gens := TDictionary<string, UInt64>.Create;
  try
    Assert.IsTrue(FindingsStampOf(5, Gens) = 5, 'leer');
    Gens.Add('a', 3);
    Assert.IsTrue(FindingsStampOf(5, Gens) = 5, 'aelterer Watch-Lauf');
    Gens.Add('b', 9);
    Gens.Add('c', 7);
    Assert.IsTrue(FindingsStampOf(5, Gens) = 9, 'juengster Watch-Lauf');
  finally
    Gens.Free;
  end;
end;

procedure TTestFindingFileIndex.RecordDisplayedAtFree(Sender: TObject;
  const Item: TLeakFinding; Action: TCollectionNotification);
// cnRemoved kommt bei TObjectList VOR der Freigabe: genau der Moment, in
// dem die Anzeige-Liste nichts mehr halten darf.
begin
  if (Action = cnRemoved) and Assigned(FDisplayed)
     and (FDisplayed.Count > FMaxDisplayedAtFree) then
    FMaxDisplayedAtFree := FDisplayed.Count;
end;

procedure TTestFindingFileIndex.FailAtNthAdd(Sender: TObject;
  const Item: TLeakFinding; Action: TCollectionNotification);
// Simuliert das Scheitern des Umhaengens beim FFailAtAdd-ten Add - mit der
// echten Ausnahme der RTL (OutOfMemoryError wirft das vorgefertigte Objekt,
// das nie freigegeben wird und daher auch nicht leckt).
begin
  if Action <> cnAdded then Exit;
  Inc(FAddsSeen);
  if FAddsSeen = FFailAtAdd then
    OutOfMemoryError;
end;

procedure TTestFindingFileIndex.Delivery_FreesOldOnlyAfterDisplayDetached;
// Altes Muster (PopulateFindings bis 2026-11-14): FAllFindings.Clear VOR
// FDisplayedFindings.Clear - hier gaebe das FMaxDisplayedAtFree = 3, die
// Anzeige zeigte im Moment der Freigabe auf drei sterbende Funde.
var
  Owned, Source : TObjectList<TLeakFinding>;
  Displayed     : TList<TLeakFinding>;
  i             : Integer;
begin
  ResetTracking(5);                         // 0..2 alt, 3..4 neu
  Owned     := TObjectList<TLeakFinding>.Create(True);
  Source    := TObjectList<TLeakFinding>.Create(True);
  Displayed := TList<TLeakFinding>.Create;
  try
    AddTracked(Owned, 0, 2);
    Displayed.AddRange(Owned);
    AddTracked(Source, 3, 4);
    FDisplayed := Displayed;
    FMaxDisplayedAtFree := 0;
    Owned.OnNotify := RecordDisplayedAtFree;
    TFindingDelivery.Deliver(Displayed, Owned, Source);
    Owned.OnNotify := nil;
    Assert.AreEqual<Integer>(0, FMaxDisplayedAtFree,
      'beim Freigeben der alten Funde hielt die Anzeige noch Zeiger');
    for i := 0 to 2 do
      Assert.AreEqual<Integer>(1, GDestroyCount[i],
        Format('alter Fund %d genau einmal frei', [i]));
    Assert.AreEqual<Integer>(0, Displayed.Count, 'Anzeige leer');
    Assert.AreEqual<Integer>(2, Owned.Count, 'neue Funde uebernommen');
    Assert.IsFalse(Source.OwnsObjects, 'Quelle hat den Besitz abgegeben');
    FreeAndNil(Source);
    Assert.AreEqual<Integer>(0, GDestroyCount[3] + GDestroyCount[4],
      'die Quelle gibt uebernommene Funde nicht frei');
  finally
    FDisplayed := nil;
    Owned.OnNotify := nil;
    Displayed.Free;
    Source.Free;
    Owned.Free;
  end;
  for i := 3 to 4 do
    Assert.AreEqual<Integer>(1, GDestroyCount[i],
      Format('neuer Fund %d genau einmal frei', [i]));
end;

procedure TTestFindingFileIndex.Delivery_AddFailure_SourceKeepsEveryFinding;
// Altes Muster: findings.OwnsObjects := False VOR der Kopierschleife - ein
// Wurf beim zweiten Add liess Fund 2 bei niemandem zurueck (Zaehler 0) und
// die Quelle ohne Besitz. Hier muss jeder Fund genau einmal frei werden.
var
  Owned, Source : TObjectList<TLeakFinding>;
  Displayed     : TList<TLeakFinding>;
  i             : Integer;
begin
  ResetTracking(3);
  Owned     := TObjectList<TLeakFinding>.Create(True);
  Source    := TObjectList<TLeakFinding>.Create(True);
  Displayed := TList<TLeakFinding>.Create;
  try
    AddTracked(Source, 0, 2);
    FAddsSeen  := 0;
    FFailAtAdd := 2;
    Owned.OnNotify := FailAtNthAdd;
    Assert.WillRaise(
      procedure
      begin
        TFindingDelivery.Deliver(Displayed, Owned, Source);
      end, EOutOfMemory, 'das Umhaengen wirft weiter');
    Owned.OnNotify := nil;
    Assert.AreEqual<Integer>(0, Owned.Count, 'halbe Kopie zurueckgenommen');
    Assert.IsTrue(Source.OwnsObjects, 'die Quelle besitzt weiter alles');
    Assert.AreEqual<Integer>(3, Source.Count, 'die Quelle ist vollstaendig');
    for i := 0 to 2 do
      Assert.AreEqual<Integer>(0, GDestroyCount[i],
        Format('Fund %d nicht vorzeitig frei', [i]));
  finally
    Owned.OnNotify := nil;
    Displayed.Free;
    Owned.Free;
    Source.Free;
  end;
  for i := 0 to 2 do
    Assert.AreEqual<Integer>(1, GDestroyCount[i],
      Format('Fund %d genau einmal frei (0 = Leck)', [i]));
end;

procedure TTestFindingFileIndex.Delivery_AppendFailure_KeepsOwnedAndSource;
// Watch-Lauf (OnWatchFindings) haengt an. Altes Muster dort:
// Findings.OwnsObjects := False VOR der Schleife - ein Wurf liess den Rest
// bei niemandem. Jetzt: Bestand unveraendert, die Quelle besitzt weiter
// alles, jeder Fund am Ende genau einmal frei.
var
  Owned, Source : TObjectList<TLeakFinding>;
  i             : Integer;
begin
  ResetTracking(5);                         // 0..1 Bestand, 2..4 Watch-Lauf
  Owned  := TObjectList<TLeakFinding>.Create(True);
  Source := TObjectList<TLeakFinding>.Create(True);
  try
    AddTracked(Owned, 0, 1);
    AddTracked(Source, 2, 4);
    FAddsSeen  := 0;
    FFailAtAdd := 2;                        // zweites ANGEHAENGTES Add wirft
    Owned.OnNotify := FailAtNthAdd;
    Assert.WillRaise(
      procedure
      begin
        TFindingDelivery.Append(Owned, Source);
      end, EOutOfMemory, 'das Anhaengen wirft weiter');
    Owned.OnNotify := nil;
    Assert.AreEqual<Integer>(2, Owned.Count, 'Bestand unveraendert');
    Assert.IsTrue(Source.OwnsObjects, 'die Quelle besitzt weiter alles');
    for i := 0 to 4 do
      Assert.AreEqual<Integer>(0, GDestroyCount[i],
        Format('Fund %d nicht vorzeitig frei', [i]));
  finally
    Owned.OnNotify := nil;
    Owned.Free;
    Source.Free;
  end;
  for i := 0 to 4 do
    Assert.AreEqual<Integer>(1, GDestroyCount[i],
      Format('Fund %d genau einmal frei (0 = Leck)', [i]));
end;

procedure TTestFindingFileIndex.Delivery_Discard_EmptiesBothAndFreesOnce;
// Nachlauf scheitert (im Dock: UpdateStats/RebuildFilterCombos/ApplyFilter
// werfen EOutOfMemory) -> Discard: Anzeige und Besitz leer, nichts zweimal
// frei. Die Anzeige wird dabei VOR den Funden geleert.
var
  Owned, Source : TObjectList<TLeakFinding>;
  Displayed     : TList<TLeakFinding>;
  i             : Integer;
begin
  ResetTracking(2);
  Owned     := TObjectList<TLeakFinding>.Create(True);
  Source    := TObjectList<TLeakFinding>.Create(True);
  Displayed := TList<TLeakFinding>.Create;
  try
    AddTracked(Source, 0, 1);
    TFindingDelivery.Deliver(Displayed, Owned, Source);
    Displayed.AddRange(Owned);              // Nachlauf hatte schon angefangen
    FDisplayed := Displayed;
    FMaxDisplayedAtFree := 0;
    Owned.OnNotify := RecordDisplayedAtFree;
    TFindingDelivery.Discard(Displayed, Owned);
    Owned.OnNotify := nil;
    Assert.AreEqual<Integer>(0, FMaxDisplayedAtFree,
      'Discard gab Funde frei, die die Anzeige noch hielt');
    Assert.AreEqual<Integer>(0, Displayed.Count, 'Anzeige leer');
    Assert.AreEqual<Integer>(0, Owned.Count, 'Besitz leer');
    for i := 0 to 1 do
      Assert.AreEqual<Integer>(1, GDestroyCount[i],
        Format('Fund %d genau einmal frei', [i]));
  finally
    FDisplayed := nil;
    Owned.OnNotify := nil;
    Displayed.Free;
    Owned.Free;
    Source.Free;
  end;
  for i := 0 to 1 do
    Assert.AreEqual<Integer>(1, GDestroyCount[i],
      Format('Fund %d nach allen Free genau einmal frei', [i]));
end;

end.
