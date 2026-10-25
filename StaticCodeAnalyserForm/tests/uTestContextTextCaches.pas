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

initialization
  TDUnitX.RegisterTestFixture(TTestContextTextCaches);

end.
