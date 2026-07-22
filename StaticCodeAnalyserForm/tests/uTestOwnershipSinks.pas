unit uTestOwnershipSinks;

// Tests fuer die konfigurierbare Ownership-Sink-Registry (#5, Konzept
// EngineArchitektur_FpReduktion) - [Detectors] OwnershipSinks=Routine1,...
//
// Ein Objekt, das an eine gelistete Sink-Routine uebergeben wird, gilt als
// ownership-transferiert (der Consumer besitzt es) -> SCA001 meldet keinen
// Leak. Konsumiert in TLeakDetector2.IsPassedToOwner ueber den Global
// uSCAConsts.OwnershipSinks (per RegisterToLeakyClasses vor dem Scan gesetzt).
//
// WICHTIG: die Registry ist Prozess-State. TearDown leert sie nach JEDEM Test,
// damit ein konfigurierter Sink nicht in die restliche Suite leakt (sonst
// waeren fremde Leak-Tests nicht mehr byte-stabil).

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

type
  [TestFixture]
  TTestOwnershipSinks = class
  public
    [TearDown] procedure TearDown;

    // Leerer Default (Auslieferung): Bare-Proc-Uebergabe unterdrueckt nichts.
    [Test] procedure Sink_EmptyDefault_LeakStillReported;
    // Konfigurierter Sink: Uebergabe = Ownership-Transfer -> kein Leak.
    [Test] procedure Sink_Configured_SuppressesLeak;
    // Wortgrenze links: 'PreOwner(' darf nicht auf Sink 'Owner' matchen.
    [Test] procedure Sink_WordBoundary_NoSubstringMatch;
  end;

implementation

const
  // Uebergabe an einen BARE Proc-Call (kein '.add'/'.create'/Konstruktor) -
  // das trifft KEINE der bestehenden IsPassedToOwner-Regeln, ist per Default
  // also ein echter Leak. Erst der konfigurierte Sink unterdrueckt ihn.
  SRC_REGISTER =
    'unit t; implementation'#13#10+
    'procedure TFoo.Bar;'#13#10+
    'var list: TStringList;'#13#10+
    'begin'#13#10+
    '  list := TStringList.Create;'#13#10+
    '  RegisterOwner(list);'#13#10+
    'end;';

procedure TTestOwnershipSinks.TearDown;
begin
  if Assigned(uSCAConsts.OwnershipSinks) then
    uSCAConsts.OwnershipSinks.Clear;
end;

procedure TTestOwnershipSinks.Sink_EmptyDefault_LeakStillReported;
var
  F: TObjectList<TLeakFinding>;
begin
  // Registry leer (Default) -> der Bare-Call unterdrueckt nichts: Leak bleibt.
  // Beweist zugleich die Byte-Sicherheit des leeren Defaults.
  F := TFindingHelper.FindingsOf(SRC_REGISTER);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMemoryLeak),
      'Ohne konfigurierten Sink bleibt der Leak sichtbar (leerer Default)');
  finally
    F.Free;
  end;
end;

procedure TTestOwnershipSinks.Sink_Configured_SuppressesLeak;
var
  F: TObjectList<TLeakFinding>;
begin
  uSCAConsts.OwnershipSinks.Add('RegisterOwner');
  F := TFindingHelper.FindingsOf(SRC_REGISTER);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Uebergabe an konfigurierten Sink RegisterOwner = Ownership-Transfer -> kein Leak');
  finally
    F.Free;
  end;
end;

procedure TTestOwnershipSinks.Sink_WordBoundary_NoSubstringMatch;
const
  SRC =
    'unit t; implementation'#13#10+
    'procedure TFoo.Bar;'#13#10+
    'var a, b: TStringList;'#13#10+
    'begin'#13#10+
    '  a := TStringList.Create;'#13#10+
    '  PreOwner(a);'#13#10+        // 'preowner(' - Sink 'Owner' darf NICHT matchen
    '  b := TStringList.Create;'#13#10+
    '  Owner(b);'#13#10+           // exakter Sink-Treffer -> unterdrueckt
    'end;';
var
  F: TObjectList<TLeakFinding>;
begin
  uSCAConsts.OwnershipSinks.Add('Owner');
  F := TFindingHelper.FindingsOf(SRC);
  try
    // 'a' bleibt Leak (PreOwner != Owner, Zeichen links ist ein Identifier);
    // 'b' wird unterdrueckt -> genau 1 verbleibender Leak.
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMemoryLeak),
      'Substring-Treffer (PreOwner) darf NICHT als Sink zaehlen; nur exaktes Owner()');
  finally
    F.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestOwnershipSinks);

end.
