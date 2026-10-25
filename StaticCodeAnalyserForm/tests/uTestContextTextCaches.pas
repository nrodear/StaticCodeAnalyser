unit uTestContextTextCaches;

// Tests fuer die Ein-Datei-Slots im TAnalyzeContext aus der Perf-Charge P4
// (2026-10-25). Jeder Slot ist ein reiner Tempo-Umbau: mit Context muss
// dasselbe herauskommen wie ohne. Gepinnt werden die Cache-Faelle, die ein
// falscher Schluessel oder eine falsche Lebensdauer verderben wuerde:
// Treffer derselben Datei, Wechsel der Datei, FileName = '' und
// AContext = nil.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestContextTextCaches = class
  public
    // --- Ganztext (TDetectorUtils.LinesTextCached) --------------------------
    [Test] procedure FullText_NilContext_IsLinesText;
    [Test] procedure FullText_SameFile_ServedFromSlot;
    [Test] procedure FullText_FileSwitch_Recomputes;
    [Test] procedure FullText_EmptyFileName_NeverCached;
    // --- FPC-Binding-Typnamen (TDetectorUtils.CollectFpcBindingTypeNames) ----
    [Test] procedure FpcBinding_ContextSameAsNil_AndCallerOwnsList;
    [Test] procedure FpcBinding_FileSwitch_Recomputes;
    [Test] procedure FpcBinding_EmptyResultIsCachedToo;
    [Test] procedure FpcBinding_UpperCaseKind_PassesShortcut;
    [Test] procedure FpcBinding_KindJoinedByComment_PassesShortcut;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uAnalyzeContext, uDetectorUtils;

function MakeLines(const AText: string): TStringList;
begin
  Result := TStringList.Create;
  Result.Text := AText;
end;

procedure TTestContextTextCaches.FullText_NilContext_IsLinesText;
var
  L : TStringList;
begin
  L := MakeLines('unit a;'#10'interface'#13'end.');
  try
    // TStringList trennt LF, CR und CRLF - der Ganztext ist Lines.Text
    // (CRLF je Zeile), nicht der Rohtext.
    Assert.AreEqual(L.Text, TDetectorUtils.LinesTextCached(L, nil, 'a.pas'));
    Assert.AreEqual('unit a;'#13#10'interface'#13#10'end.'#13#10,
      TDetectorUtils.LinesTextCached(L, nil, 'a.pas'));
  finally
    L.Free;
  end;
end;

procedure TTestContextTextCaches.FullText_SameFile_ServedFromSlot;
var
  Ctx : TAnalyzeContext;
  L1, L2 : TStringList;
begin
  // Innerhalb eines Scans ist der Dateitext ein Snapshot: derselbe
  // FileName liefert den Text des ersten Aufrufs, auch wenn ein zweiter
  // Aufrufer andere Zeilen reicht. Genau das spart den zweiten Aufbau.
  Ctx := TAnalyzeContext.Create;
  L1 := MakeLines('erste');
  L2 := MakeLines('zweite');
  try
    Assert.AreEqual('erste'#13#10, TDetectorUtils.LinesTextCached(L1, Ctx, 'a.pas'));
    Assert.AreEqual('erste'#13#10, TDetectorUtils.LinesTextCached(L2, Ctx, 'a.pas'));
  finally
    L2.Free;
    L1.Free;
    Ctx.Free;
  end;
end;

procedure TTestContextTextCaches.FullText_FileSwitch_Recomputes;
var
  Ctx : TAnalyzeContext;
  L1, L2 : TStringList;
begin
  Ctx := TAnalyzeContext.Create;
  L1 := MakeLines('erste');
  L2 := MakeLines('zweite');
  try
    Assert.AreEqual('erste'#13#10, TDetectorUtils.LinesTextCached(L1, Ctx, 'a.pas'));
    Assert.AreEqual('zweite'#13#10, TDetectorUtils.LinesTextCached(L2, Ctx, 'b.pas'));
    // Nur EINE Datei im Slot: zurueck auf a.pas rechnet neu.
    Assert.AreEqual('zweite'#13#10, TDetectorUtils.LinesTextCached(L2, Ctx, 'a.pas'));
  finally
    L2.Free;
    L1.Free;
    Ctx.Free;
  end;
end;

procedure TTestContextTextCaches.FullText_EmptyFileName_NeverCached;
var
  Ctx : TAnalyzeContext;
  L1, L2 : TStringList;
begin
  // In-Memory-Pfade ohne Dateinamen teilen sich keinen Eintrag.
  Ctx := TAnalyzeContext.Create;
  L1 := MakeLines('erste');
  L2 := MakeLines('zweite');
  try
    Assert.AreEqual('erste'#13#10, TDetectorUtils.LinesTextCached(L1, Ctx, ''));
    Assert.AreEqual('zweite'#13#10, TDetectorUtils.LinesTextCached(L2, Ctx, ''));
  finally
    L2.Free;
    L1.Free;
    Ctx.Free;
  end;
end;

{ ---- FPC-Binding-Typnamen ---- }
//
// Seit Charge P4 liegt das Ergebnis im Ein-Datei-Slot des Context, und
// eine Abkuerzung ueberspringt LowerCase+Split, wenn der GESTRIPPTE Text
// weder 'objc' noch 'cppclass' enthaelt. Die Inhaltsfaelle selbst pinnt
// uTestDetectorUtils (FpcBinding_*, AContext = nil).

const
  SRC_ALLE =
    'type'#13#10 +
    '  TObj = objcclass(NSObject)'#13#10 +
    '  end;'#13#10 +
    '  TCat = objccategory(NSString)'#13#10 +
    '  end;'#13#10 +
    '  TPlain = class(TObject)'#13#10 +
    '  end;'#13#10 +
    '  TCpp = cppclass(QWidget)'#13#10 +
    '  end;';
  SRC_OHNE =
    'type'#13#10 +
    '  TPlain = class(TObject)'#13#10 +
    '  end;';

function Namen(const ASource: string; ACtx: TAnalyzeContext;
  const AFileName: string): string;
var
  L, N : TStringList;
begin
  L := MakeLines(ASource);
  try
    N := TDetectorUtils.CollectFpcBindingTypeNames(L, ACtx, AFileName);
    try
      Result := N.CommaText;
    finally
      N.Free;
    end;
  finally
    L.Free;
  end;
end;

procedure TTestContextTextCaches.FpcBinding_ContextSameAsNil_AndCallerOwnsList;
var
  Ctx : TAnalyzeContext;
  L : TStringList;
  N1, N2 : TStringList;
begin
  Assert.AreEqual('tcat,tcpp,tobj', Namen(SRC_ALLE, nil, 'a.pas'), 'ohne Context');
  Ctx := TAnalyzeContext.Create;
  L := MakeLines(SRC_ALLE);
  try
    N1 := TDetectorUtils.CollectFpcBindingTypeNames(L, Ctx, 'a.pas');
    N2 := TDetectorUtils.CollectFpcBindingTypeNames(L, Ctx, 'a.pas');
    try
      Assert.AreEqual('tcat,tcpp,tobj', N1.CommaText, 'erster Aufruf');
      Assert.AreEqual('tcat,tcpp,tobj', N2.CommaText, 'zweiter Aufruf (Slot)');
      // Jeder Aufrufer bekommt eine eigene Liste, die er freigibt - der
      // Slot haelt nur die Namen.
      Assert.IsFalse(N1 = N2, 'zwei Aufrufe, zwei Listen');
      Assert.IsTrue(N2.Sorted, 'Liste aus dem Slot bleibt sortiert');
      Assert.AreEqual<Integer>(Ord(dupIgnore), Ord(N2.Duplicates));
      Assert.IsFalse(N2.CaseSensitive);
    finally
      N2.Free;
      N1.Free;
    end;
  finally
    L.Free;
    Ctx.Free;
  end;
end;

procedure TTestContextTextCaches.FpcBinding_FileSwitch_Recomputes;
var
  Ctx : TAnalyzeContext;
begin
  Ctx := TAnalyzeContext.Create;
  try
    Assert.AreEqual('tcat,tcpp,tobj', Namen(SRC_ALLE, Ctx, 'a.pas'));
    Assert.AreEqual('', Namen(SRC_OHNE, Ctx, 'b.pas'), 'andere Datei');
    Assert.AreEqual('tcat,tcpp,tobj', Namen(SRC_ALLE, Ctx, 'c.pas'), 'dritte Datei');
  finally
    Ctx.Free;
  end;
end;

procedure TTestContextTextCaches.FpcBinding_EmptyResultIsCachedToo;
var
  Ctx : TAnalyzeContext;
begin
  // Leer ist ein gueltiges Ergebnis: der Treffer haengt am Dateinamen,
  // nicht an der Zahl der Namen (der Normalfall - fast keine Datei hat
  // ein Binding). Gleiche Snapshot-Annahme wie beim Strip-Cache.
  Ctx := TAnalyzeContext.Create;
  try
    Assert.AreEqual('', Namen(SRC_OHNE, Ctx, 'a.pas'));
    Assert.AreEqual('', Namen(SRC_ALLE, Ctx, 'a.pas'), 'Slot derselben Datei');
    Assert.AreEqual('tcat,tcpp,tobj', Namen(SRC_ALLE, Ctx, ''),
      'FileName '''' wird nie gecacht');
  finally
    Ctx.Free;
  end;
end;

procedure TTestContextTextCaches.FpcBinding_UpperCaseKind_PassesShortcut;
begin
  // Die Abkuerzung sucht case-insensitiv: OBJCCLASS/CppClass bleiben
  // Bindings (rot, wenn sie nur kleingeschriebene Woerter faende).
  Assert.AreEqual('tcpp,tobj', Namen(
    'type'#13#10 +
    '  TObj = OBJCCLASS(NSObject)'#13#10 +
    '  end;'#13#10 +
    '  TCpp = CppClass(QWidget)'#13#10 +
    '  end;', nil, 'a.pas'));
end;

procedure TTestContextTextCaches.FpcBinding_KindJoinedByComment_PassesShortcut;
begin
  // Der Strip ENTFERNT Kommentare (spaltenuntreu): 'obj{x}cclass' wird zu
  // 'objcclass'. Die Abkuerzung muss deshalb im gestrippten Text suchen,
  // nicht im Rohtext (dort steht kein 'objc').
  Assert.AreEqual('tobj', Namen(
    'type'#13#10 +
    '  TObj = obj{x}cclass(NSObject)'#13#10 +
    '  end;', nil, 'a.pas'));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestContextTextCaches);

end.
