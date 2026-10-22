unit uTestEditorFindingStore;

// Tests fuer uEditorFindingStore (SCA.SharedUI): die Kopien der Funde der
// letzten Silent-Laeufe je Datei, aus denen Editor-Kontextmenue und
// Gluehbirne lesen, wenn das Dock die Datei nicht haelt (Review Woche
// 2026-10-21, G04-06 - vorher ungetestet in uIDEAnalyserForm).
//
// Abgesichert: Ersetzen bei vorhandenem Schluessel (nicht Add), Verdraengen
// nach der kleinsten GENERATION (nicht nach der Einfuegereihenfolge, nicht
// beim Ersetzen), Eigentum (Kopien statt geteilter Objekte; Ersetzen,
// Verdraengen und Destroy geben frei; ein scheiternder Lauf leckt nicht und
// laesst den alten Stand stehen - G04-07).
//
// UNGEDECKT bleibt die IDE-Seite: welcher Schluessel (NormalizePathForKey)
// und welche Generation uIDEAnalyserForm hereinreicht.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEditorFindingStore = class
  public
    [Test] procedure Keep_CopiesFieldsAndGeneration;
    [Test] procedure Keep_CopiesAreOwnObjects;
    [Test] procedure Keep_SkipsNilEntriesAndNilList;
    [Test] procedure TryGet_UnknownKey_FalseAndNil;
    [Test] procedure Keep_SameKey_ReplacesAndFreesOldCopy;
    [Test] procedure Keep_SameKeyAtCapacity_DropsNoOtherFile;
    [Test] procedure Keep_NewKeyAtCapacity_DropsOldestGeneration;
    [Test] procedure Keep_ReplacedFile_CountsWithNewGeneration;
    [Test] procedure Keep_DroppedCopy_IsFreed;
    [Test] procedure Keep_FailingCopy_FreesPartialAndKeepsOld;
    [Test] procedure Keep_FailingCopyOfNewFile_StoresNothing;
    [Test] procedure Destroy_FreesAllCopies;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  uSCAConsts,                   // lsHint, fkSQLInjection, fcLow
  uMethodd12,                   // TLeakFinding
  uEditorFindingStore;

var
  // Freigegebene Kopien der Probe - jeder Test setzt ihn vorher auf 0.
  GFreedProbes : Integer = 0;

type
  // Kopie, deren Freigabe der Test zaehlt.
  TProbeFinding = class(TLeakFinding)
  public
    destructor Destroy; override;
  end;

  EProbeCopyFailed = class(Exception);

  // Speicher, dessen Kopien TProbeFinding sind. FailAt > 0 laesst die
  // FailAt-te Kopie (gezaehlt seit Erzeugung, Calls) scheitern.
  TProbeStore = class(TEditorFindingStore)
  protected
    function CopyOf(AFinding: TLeakFinding): TLeakFinding; override;
  public
    FailAt : Integer;
    Calls  : Integer;
  end;

destructor TProbeFinding.Destroy;
begin
  Inc(GFreedProbes);
  inherited;
end;

function TProbeStore.CopyOf(AFinding: TLeakFinding): TLeakFinding;
begin
  Inc(Calls);
  if Calls = FailAt then
    raise EProbeCopyFailed.Create('Kopie scheitert (Probe)');
  Result := TProbeFinding.Create;
  Result.MissingVar := AFinding.MissingVar;
end;

// Quell-Liste mit ACount Funden 'm1'..'mN' (Eigentum des Aufrufers).
function NewSource(ACount: Integer): TObjectList<TLeakFinding>;
var
  i : Integer;
  F : TLeakFinding;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  for i := 1 to ACount do
  begin
    F := TLeakFinding.Create;
    Result.Add(F);
    F.FileName   := 'C:\p\a.pas';
    F.LineNumber := IntToStr(10 * i);
    F.MissingVar := 'm' + IntToStr(i);
  end;
end;

// Keep mit einer frischen Quell-Liste, die danach freigegeben wird - wie
// der Silent-Lauf.
procedure KeepFresh(AStore: TEditorFindingStore; const AKey: string;
  ACount: Integer; AGen: UInt64);
var
  Src : TObjectList<TLeakFinding>;
begin
  Src := NewSource(ACount);
  try
    AStore.Keep(AKey, Src, AGen);
  finally
    Src.Free;
  end;
end;

function Has(AStore: TEditorFindingStore; const AKey: string): Boolean;
var
  Kept : TEditorFindingsCopy;
begin
  Result := AStore.TryGet(AKey, Kept);
end;

procedure TTestEditorFindingStore.Keep_CopiesFieldsAndGeneration;
var
  Store : TEditorFindingStore;
  Src   : TObjectList<TLeakFinding>;
  F     : TLeakFinding;
  Kept  : TEditorFindingsCopy;
  C     : TLeakFinding;
begin
  Store := TEditorFindingStore.Create(8);
  try
    Src := TObjectList<TLeakFinding>.Create(True);
    try
      F := TLeakFinding.Create;
      Src.Add(F);
      F.FileName   := 'C:\p\a.pas';
      F.MethodName := 'TFoo.Bar';
      F.LineNumber := '12';
      F.EndLine    := 14;
      F.MissingVar := 'Query';
      F.Severity   := lsHint;
      F.Kind       := fkSQLInjection;
      F.Confidence := fcLow;
      F.RuleID     := 'PROJ001';
      Store.Keep('c:\p\a.pas', Src, 42);
    finally
      Src.Free;
    end;
    Assert.IsTrue(Store.TryGet('c:\p\a.pas', Kept), 'Kopie abgelegt');
    Assert.IsTrue(Kept.Gen = 42, 'Generation des Laufs');
    Assert.AreEqual<Integer>(1, Kept.Items.Count);
    C := Kept.Items[0];
    Assert.AreEqual('C:\p\a.pas', C.FileName);
    Assert.AreEqual('TFoo.Bar', C.MethodName);
    Assert.AreEqual('12', C.LineNumber);
    Assert.AreEqual<Integer>(14, C.EndLine);
    Assert.AreEqual('Query', C.MissingVar);
    Assert.AreEqual<Integer>(Ord(lsHint), Ord(C.Severity));
    Assert.AreEqual<Integer>(Ord(fkSQLInjection), Ord(C.Kind));
    Assert.AreEqual<Integer>(Ord(fcLow), Ord(C.Confidence));
    Assert.AreEqual('PROJ001', C.RuleID);
  finally
    Store.Free;
  end;
end;

procedure TTestEditorFindingStore.Keep_CopiesAreOwnObjects;
var
  Store : TEditorFindingStore;
  Src   : TObjectList<TLeakFinding>;
  Kept  : TEditorFindingsCopy;
begin
  Store := TEditorFindingStore.Create(8);
  try
    Src := NewSource(2);
    try
      Store.Keep('a', Src, 1);
      Assert.IsTrue(Store.TryGet('a', Kept));
      Assert.IsTrue(Kept.Items[0] <> Src[0], 'eigene Kopie, kein geteilter Fund');
      Assert.IsTrue(Kept.Items[1] <> Src[1], 'eigene Kopie, kein geteilter Fund');
    finally
      Src.Free;   // der Silent-Lauf gibt seine Liste frei
    end;
    Assert.IsTrue(Store.TryGet('a', Kept));
    Assert.IsTrue(Kept.Items.OwnsObjects, 'die Kopie besitzt ihre Funde');
    Assert.AreEqual('m2', Kept.Items[1].MissingVar,
      'die Kopie ueberlebt die Freigabe der Quelle');
  finally
    Store.Free;
  end;
end;

procedure TTestEditorFindingStore.Keep_SkipsNilEntriesAndNilList;
var
  Store : TEditorFindingStore;
  Src   : TObjectList<TLeakFinding>;
  Kept  : TEditorFindingsCopy;
begin
  Store := TEditorFindingStore.Create(8);
  try
    Src := NewSource(1);
    try
      Src.Add(nil);
      Store.Keep('a', Src, 1);
    finally
      Src.Free;
    end;
    Assert.IsTrue(Store.TryGet('a', Kept));
    Assert.AreEqual<Integer>(1, Kept.Items.Count, 'nil-Eintrag uebersprungen');
    Store.Keep('b', nil, 2);
    Assert.IsTrue(Store.TryGet('b', Kept), 'nil-Liste: leere Kopie');
    Assert.AreEqual<Integer>(0, Kept.Items.Count);
  finally
    Store.Free;
  end;
end;

procedure TTestEditorFindingStore.TryGet_UnknownKey_FalseAndNil;
var
  Store : TEditorFindingStore;
  Kept  : TEditorFindingsCopy;
begin
  Store := TEditorFindingStore.Create(8);
  try
    KeepFresh(Store, 'a', 1, 1);
    Assert.IsFalse(Store.TryGet('b', Kept));
    Assert.IsNull(Kept, 'ohne Kopie kein Zeiger');
  finally
    Store.Free;
  end;
end;

procedure TTestEditorFindingStore.Keep_SameKey_ReplacesAndFreesOldCopy;
var
  Store : TProbeStore;
  Kept  : TEditorFindingsCopy;
begin
  GFreedProbes := 0;
  Store := TProbeStore.Create(4);
  try
    KeepFresh(Store, 'a', 2, 1);
    KeepFresh(Store, 'a', 1, 2);
    Assert.AreEqual<Integer>(1, Store.Count, 'ersetzt, nicht dazugelegt');
    Assert.AreEqual<Integer>(2, GFreedProbes, 'die alte Kopie ist frei');
    Assert.IsTrue(Store.TryGet('a', Kept));
    Assert.IsTrue(Kept.Gen = 2, 'Generation des neuen Laufs');
    Assert.AreEqual<Integer>(1, Kept.Items.Count);
  finally
    Store.Free;
  end;
end;

procedure TTestEditorFindingStore.Keep_SameKeyAtCapacity_DropsNoOtherFile;
var
  Store : TEditorFindingStore;
begin
  Store := TEditorFindingStore.Create(2);
  try
    KeepFresh(Store, 'a', 1, 1);
    KeepFresh(Store, 'b', 1, 2);
    KeepFresh(Store, 'a', 1, 3);
    Assert.AreEqual<Integer>(2, Store.Count);
    Assert.IsTrue(Has(Store, 'a'));
    Assert.IsTrue(Has(Store, 'b'), 'Ersetzen braucht keinen Platz');
  finally
    Store.Free;
  end;
end;

procedure TTestEditorFindingStore.Keep_NewKeyAtCapacity_DropsOldestGeneration;
var
  Store : TEditorFindingStore;
begin
  Store := TEditorFindingStore.Create(2);
  try
    // Generationen gegen die Einfuegereihenfolge: b ist die aelteste.
    KeepFresh(Store, 'a', 1, 7);
    KeepFresh(Store, 'b', 1, 3);
    KeepFresh(Store, 'c', 1, 9);
    Assert.AreEqual<Integer>(2, Store.Count, 'Kapazitaet gehalten');
    Assert.IsFalse(Has(Store, 'b'), 'kleinste Generation verdraengt');
    Assert.IsTrue(Has(Store, 'a'));
    Assert.IsTrue(Has(Store, 'c'));
  finally
    Store.Free;
  end;
end;

procedure TTestEditorFindingStore.Keep_ReplacedFile_CountsWithNewGeneration;
var
  Store : TEditorFindingStore;
begin
  Store := TEditorFindingStore.Create(2);
  try
    KeepFresh(Store, 'a', 1, 1);
    KeepFresh(Store, 'b', 1, 2);
    KeepFresh(Store, 'a', 1, 3);   // a ist jetzt juenger als b
    KeepFresh(Store, 'c', 1, 4);
    Assert.IsTrue(Has(Store, 'a'), 'ersetzte Datei zaehlt mit neuer Generation');
    Assert.IsFalse(Has(Store, 'b'));
    Assert.IsTrue(Has(Store, 'c'));
  finally
    Store.Free;
  end;
end;

procedure TTestEditorFindingStore.Keep_DroppedCopy_IsFreed;
var
  Store : TProbeStore;
begin
  GFreedProbes := 0;
  Store := TProbeStore.Create(1);
  try
    KeepFresh(Store, 'a', 2, 1);
    KeepFresh(Store, 'b', 1, 2);
    Assert.AreEqual<Integer>(1, Store.Count);
    Assert.AreEqual<Integer>(2, GFreedProbes, 'die verdraengte Kopie ist frei');
  finally
    Store.Free;
  end;
end;

procedure TTestEditorFindingStore.Keep_FailingCopy_FreesPartialAndKeepsOld;
var
  Store  : TProbeStore;
  Kept   : TEditorFindingsCopy;
  Raised : Boolean;
begin
  GFreedProbes := 0;
  Store := TProbeStore.Create(4);
  try
    KeepFresh(Store, 'a', 1, 1);
    Store.FailAt := Store.Calls + 2;   // die zweite Kopie des naechsten Laufs
    Raised := False;
    try
      KeepFresh(Store, 'a', 3, 2);
    except
      on EProbeCopyFailed do
        Raised := True;
    end;
    Assert.IsTrue(Raised, 'der Fehler geht an den Aufrufer');
    Assert.AreEqual<Integer>(1, GFreedProbes,
      'die schon kopierte Haelfte ist frei, die alte Kopie nicht');
    Assert.IsTrue(Store.TryGet('a', Kept), 'der alte Stand bleibt');
    Assert.IsTrue(Kept.Gen = 1);
    Assert.AreEqual<Integer>(1, Kept.Items.Count);
  finally
    Store.Free;
  end;
end;

procedure TTestEditorFindingStore.Keep_FailingCopyOfNewFile_StoresNothing;
var
  Store  : TProbeStore;
  Raised : Boolean;
begin
  GFreedProbes := 0;
  Store := TProbeStore.Create(4);
  try
    KeepFresh(Store, 'a', 1, 1);
    Store.FailAt := Store.Calls + 1;
    Raised := False;
    try
      KeepFresh(Store, 'b', 2, 2);
    except
      on EProbeCopyFailed do
        Raised := True;
    end;
    Assert.IsTrue(Raised);
    Assert.IsFalse(Has(Store, 'b'), 'kein halber Eintrag');
    Assert.AreEqual<Integer>(1, Store.Count);
    Assert.AreEqual<Integer>(0, GFreedProbes, 'a bleibt unberuehrt');
  finally
    Store.Free;
  end;
end;

procedure TTestEditorFindingStore.Destroy_FreesAllCopies;
var
  Store : TProbeStore;
begin
  GFreedProbes := 0;
  Store := TProbeStore.Create(4);
  try
    KeepFresh(Store, 'a', 2, 1);
    KeepFresh(Store, 'b', 1, 2);
    Assert.AreEqual<Integer>(0, GFreedProbes);
  finally
    Store.Free;
  end;
  Assert.AreEqual<Integer>(3, GFreedProbes, 'der Speicher gibt alle Kopien frei');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEditorFindingStore);

end.
